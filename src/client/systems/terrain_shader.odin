package systems

// Alpha-cutout shader for the Pandora terrain bakes.
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
//     discard ate their gradients into hard holes). Raylib's default alpha
//     blending does the rest.
//   HIDDEN  — the material's baseColor texture has no opaque pixel at all
//     (bounding-box helper props): discard everything, as the fixed-0.5
//     shader accidentally did.
//
// Applied to EVERY terrain material: the uniform defaults keep opaque
// textures unaffected, so it saves tracking which mesh uses which material
// beyond the one lookup per mesh draw.

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
in vec2 vertexTexCoord;
in vec4 vertexColor;
out vec2 fragTexCoord;
out vec4 fragColor;
uniform mat4 mvp;
void main()
{
    fragTexCoord = vertexTexCoord;
    fragColor = vertexColor;
    gl_Position = mvp * vec4(vertexPosition, 1.0);
}
`

terrain_cutout_fs :: `
#version 330
in vec2 fragTexCoord;
in vec4 fragColor;
out vec4 finalColor;
uniform sampler2D texture0;
uniform vec4 colDiffuse;
uniform int alphaMode;
uniform float alphaCutoff;
uniform int dbgFlat;
uniform vec3 dbgTint;
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
    // alphaMode 2 = glTF BLEND: soft-alpha fx cards, native alpha through.
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
