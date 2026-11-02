package systems

// Alpha-cutout + lit shader for the Pandora terrain bakes.
//
// The bakes' foliage/grass/road-decal materials are glTF alphaMode MASK —
// binary-alpha textures meant to be drawn with per-pixel discard. Raylib's
// default material shader has no discard, so those quads write depth across
// their transparent pixels and occlude everything drawn behind them (the sky
// ends up visible through tree canopies, roads render as solid blocks).
// Raylib's loaded rl.Material does not carry the glTF alphaMode, so
// map_builder parses it straight out of the GLB JSON chunk
// (glb_material_alpha) and the draw loop feeds it here as per-material
// uniforms.
//
// Per-material semantics:
//   OPAQUE  — texture alpha ignored (forced 1.0), matching the original
//     engine's opaque pass. The bakes' ground/cliff textures carry export
//     garbage in alpha (a 512² grass chip ships 43% fully-transparent texels
//     whose RGB is the real ground color); cutting or blending those punches
//     sky-colored holes into the terrain. Helper cards that are entirely
//     transparent (bounding-box props) classify as HIDDEN instead.
//   MASK    — discard below the material's own alphaCutoff (0.196..0.588 in
//     these bakes; the old fixed 0.5 punched holes in buildings whose facade
//     textures carry soft edges), and force the kept pixels fully opaque.
//     Without the force, the partial-alpha pixels between cutoff and 1.0
//     blend against whatever is behind the card — the sky-blue clear color
//     leaks through grass/buildings (the early-development tree bug again).
//   BLEND   — no discard, native alpha through (glow/fortress/warp fx cards;
//     discard ate their gradients into hard holes). Drawn UNLIT — these are
//     emissive effects. Raylib's default alpha blending does the rest.
//   HIDDEN  — the material's baseColor texture has no opaque pixel at all
//     (bounding-box helper props): discard everything, as the fixed-0.5
//     shader accidentally did.
//
// LIGHTING (see lighting.odin): hemisphere ambient + one directional sun
// sampled against the zone's static shadow-map bake, then linear fog in the
// original zone colors (environment.fog). OPAQUE and MASK are lit; BLEND
// stays emissive; the litEnabled uniform (F1 toggle) restores fullbright.

import "core:c"
import rl "vendor:raylib"

// glTF alphaMode (+ our derived HIDDEN), as stored per terrain material by
// glb_material_alpha.
Alpha_Mode :: enum u8 {
	OPAQUE,
	MASK,
	BLEND,
	HIDDEN,
}

terrain_cutout_vs :: `
#version 330
in vec3 vertexPosition;
in vec3 vertexNormal;
in vec2 vertexTexCoord;
in vec4 vertexColor;
out vec2 fragTexCoord;
out vec4 fragColor;
out vec3 fragNormal;
out vec3 fragWorld;
uniform mat4 mvp;
uniform mat4 matModel;
void main()
{
    fragTexCoord = vertexTexCoord;
    fragColor = vertexColor;
    fragNormal = mat3(matModel) * vertexNormal;
    fragWorld = (matModel * vec4(vertexPosition, 1.0)).xyz;
    gl_Position = mvp * vec4(vertexPosition, 1.0);
}
`

terrain_cutout_fs :: `
#version 330
in vec2 fragTexCoord;
in vec4 fragColor;
in vec3 fragNormal;
in vec3 fragWorld;
out vec4 finalColor;
uniform sampler2D texture0;
uniform vec4 colDiffuse;
uniform int alphaMode;
uniform float alphaCutoff;
uniform int dbgFlat;
uniform vec3 dbgTint;
uniform int litEnabled;
uniform vec3 sunDir;      // toward the sun (up)
uniform vec3 sunCol;
uniform vec3 ambUp;
uniform vec3 ambLo;
uniform vec3 fogCol;
uniform float fogNear;
uniform float fogFar;
uniform vec3 camPos;
uniform int shadowEnabled;
uniform sampler2D shadowMap;   // texture unit 1
uniform mat4 sunMVP;
uniform float shadowTexel;

vec3 lighting_apply(vec3 N, vec3 world)
{
    float ndl = max(dot(N, sunDir), 0.0);
    float lit = 1.0;
    if (shadowEnabled == 1) {
        // Normal-offset lookup kills most self-shadow acne on terrain;
        // 2x2 PCF softens the penumbra (the original has no hard
        // shadow edges — its dark-pixel share is ~1%).
        vec4 sc = sunMVP * vec4(world + N * shadowTexel * 2.0, 1.0);
        vec3 pc = sc.xyz / sc.w * 0.5 + 0.5;
        if (pc.x >= 0.0 && pc.x <= 1.0 && pc.y >= 0.0 && pc.y <= 1.0 && pc.z <= 1.0) {
            float texel = 1.0 / 2048.0;
            float s = 0.0;
            s += ((pc.z - 0.0012) <= texture(shadowMap, pc.xy + vec2(-texel, -texel)).r) ? 1.0 : 0.0;
            s += ((pc.z - 0.0012) <= texture(shadowMap, pc.xy + vec2( texel, -texel)).r) ? 1.0 : 0.0;
            s += ((pc.z - 0.0012) <= texture(shadowMap, pc.xy + vec2(-texel,  texel)).r) ? 1.0 : 0.0;
            s += ((pc.z - 0.0012) <= texture(shadowMap, pc.xy + vec2( texel,  texel)).r) ? 1.0 : 0.0;
            // Soft shadow floor: full shadow keeps 60% of the sun — the
            // original reads as gentle shading, not black occlusion.
            lit = mix(0.60, 1.0, s / 4.0);
        }
    }
    // Original-engine balance: ambient and sun SHARE the 0..1 range.
    // Full-strength addition multiplies lit ground by ~1.6 and clips
    // (measured against the original client: median lum 209 vs 159,
    // blown whites 4.3% vs 0.2%); 0.75/0.45 puts a sunlit ground plane
    // at ~0.95 like the original — bright with only rare clipping — and
    // full shadow still passes ~83% of the sunlit light (the original
    // has almost no deep darks: 1.2% vs our old 6.5%).
    vec3 hemi = mix(ambLo, ambUp, clamp(N.y * 0.35 + 0.6, 0.0, 1.0)) * 0.75;
    return hemi + sunCol * (ndl * lit) * 0.45;
}

void main()
{
    vec4 texel = texture(texture0, fragTexCoord);
    if (dbgFlat == 1) {
        // Debug: output dbgTint as pure color (mesh attribution probes).
        finalColor = vec4(dbgTint, 1.0);
        return;
    }
    if (alphaMode == 3) {
        // HIDDEN: helper texture with no opaque texel at all — vanish.
        discard;
    } else if (alphaMode == 1) {
        // glTF MASK: cutout at the material's own threshold; kept pixels
        // render fully opaque so partial alpha cannot blend the clear color.
        if (texel.a < alphaCutoff) discard;
        texel.a = 1.0;
    } else if (alphaMode == 0) {
        // glTF OPAQUE: alpha ignored — the bake's ground textures carry
        // export garbage in alpha over valid RGB.
        texel.a = 1.0;
    }
    // alphaMode 2 = glTF BLEND: soft-alpha fx cards, native alpha through,
    // unlit (emissive glow).
    if (litEnabled == 1 && alphaMode != 2) {
        vec3 L = lighting_apply(normalize(fragNormal), fragWorld);
        texel.rgb *= L;
        if (fogFar > fogNear) {
            float dist = distance(camPos, fragWorld);
            float f = clamp((dist - fogNear) / (fogFar - fogNear), 0.0, 1.0);
            texel.rgb = mix(texel.rgb, fogCol, f);
        }
    }
    finalColor = texel * colDiffuse * fragColor;
}
`

terrain_cutout_shader: rl.Shader
terrain_cutout_ready := false
terrain_loc_alpha_mode: c.int
terrain_loc_alpha_cutoff: c.int
terrain_loc_dbg_flat: c.int
terrain_loc_dbg_tint: c.int

// Process-lifetime lazily-loaded cutout shader (rlgl auto-resolves the
// standard locs for these attribute/uniform names).
terrain_shader_get :: proc() -> rl.Shader {
	if terrain_cutout_ready do return terrain_cutout_shader
	terrain_cutout_shader = rl.LoadShaderFromMemory(terrain_cutout_vs, terrain_cutout_fs)
	terrain_loc_alpha_mode = rl.GetShaderLocation(terrain_cutout_shader, "alphaMode")
	terrain_loc_alpha_cutoff = rl.GetShaderLocation(terrain_cutout_shader, "alphaCutoff")
	terrain_loc_dbg_flat = rl.GetShaderLocation(terrain_cutout_shader, "dbgFlat")
	terrain_loc_dbg_tint = rl.GetShaderLocation(terrain_cutout_shader, "dbgTint")
	terrain_cutout_ready = true
	return terrain_cutout_shader
}

// Pushes one material's glTF alpha state into the shared cutout shader.
// Call before DrawMesh; nil/short arrays fall back to the shader's OPAQUE
// path (uniforms keep their previous value only when the locs are missing,
// which cannot happen — both uniforms are static in the source above).
terrain_shader_set_material :: proc(sh: rl.Shader, mat: int, modes: []u8, cutoffs: []f32) {
	if mat < 0 {
		return
	}
	if terrain_loc_alpha_mode >= 0 && mat < len(modes) {
		mode: c.int = c.int(modes[mat])
		rl.SetShaderValue(sh, terrain_loc_alpha_mode, &mode, .INT)
	}
	if terrain_loc_alpha_cutoff >= 0 && mat < len(cutoffs) {
		cutoff := cutoffs[mat]
		rl.SetShaderValue(sh, terrain_loc_alpha_cutoff, &cutoff, .FLOAT)
	}
}
