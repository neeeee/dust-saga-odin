package systems

// The original game's sky: a two-layer dome rendered behind everything.
//
// Each area ships a sky placement (world/sky/<area>/attr/SZ_<area>_??_
// sky01A.vra — referenced by the zone JSON's source.sky) pointing at a dome
// mesh and TWO 512² textures: a base gradient (ST_<area>_??_sky01) and an
// overlaid band (ST_..._sky02, alpha-blended). The textures are vertical
// gradients — dark zenith at the top, a bright haze band at the bottom that
// matches the zone's fog color — with mild per-azimuth variation (clouds,
// glow). The original dome mesh is a binary .dxg with no in-repo parser, so
// the dome is generated (GenMeshSphere) and the texture is mapped by VIEW
// DIRECTION in the shader: v from elevation (zenith → texture top, horizon
// → bottom band), u from a MIRRORED azimuth so there is no wrap seam
// (the textures are not horizontally tileable).
//
// Rendering order: sky_draw runs first inside BeginMode3D with depth test
// and write disabled — it fills the backdrop, and the terrain (drawn after,
// fading into the zone fog color) composes over it seamlessly. The dome
// follows the camera (model matrix = translate(cam_pos)·scale(R)), so it is
// always the same distance away and never clips geometry.

import "core:c"
import "core:fmt"
import "core:math"
import "core:strings"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

SKY_DOME_RADIUS :: f32(2500.0) // inside the 8000 far plane, outside all terrain

sky_shader: rl.Shader
sky_dome: rl.Mesh
sky_mat: rl.Material // albedo map swapped per layer; shader = sky_shader
sky_ready := false
sky_tex_cache := map[string]rl.Texture{}

sky_vs :: `
#version 330
in vec3 vertexPosition;
out vec3 fragWorld;
uniform mat4 mvp;
uniform mat4 matModel;
void main()
{
    fragWorld = (matModel * vec4(vertexPosition, 1.0)).xyz;
    gl_Position = mvp * vec4(vertexPosition, 1.0);
}
`

sky_fs :: `
#version 330
in vec3 fragWorld;
out vec4 finalColor;
uniform sampler2D texture0;
uniform vec3 camPos;
uniform vec3 skyTint;   // day/night modulation from the zone env
void main()
{
    vec3 d = normalize(fragWorld - camPos);
    // Mirrored azimuth: continuous at the seam, no wrap discontinuity.
    float u = 1.0 - abs(atan(d.x, -d.z) / 3.14159265);
    // Zenith samples the texture top (dark), horizon the bottom haze band;
    // below the horizon clamps to the band, which matches the zone fog.
    float v = 1.0 - clamp(d.y, 0.0, 1.0);
    finalColor = texture(texture0, vec2(u, v)) * vec4(skyTint, 1.0);
}
`

sky_loc_cam: c.int
sky_loc_tint: c.int

sky_init :: proc() {
	if sky_ready do return
	sky_dome = rl.GenMeshSphere(1.0, 24, 48)
	sky_shader = rl.LoadShaderFromMemory(sky_vs, sky_fs)
	sky_loc_cam = rl.GetShaderLocation(sky_shader, "camPos")
	sky_loc_tint = rl.GetShaderLocation(sky_shader, "skyTint")
	sky_mat = rl.LoadMaterialDefault()
	sky_mat.shader = sky_shader
	sky_ready = true
}

// Derives the zone's sky textures from source.sky
// ("T01/attr/SZ_T01_ho_sky01A.vra" → ST_T01_ho_sky01/02.tga) and loads them
// into the zone. Dungeons (D01) reference a rock texture instead — the
// derived name simply fails to load and the zone stays on the fog backdrop.
sky_load_zone :: proc(z: ^Zone_Definition, sky_src: string) {
	if z == nil do return
	z.sky_tex1 = {}
	z.sky_tex2 = {}
	if len(sky_src) == 0 do return

	// "SZ_<area>_..._sky01A.vra" -> "ST_<area>_..._sky01" texture basename.
	name := sky_src
	if i := strings.last_index_byte(name, '/'); i >= 0 do name = name[i + 1:]
	if i := strings.last_index_byte(name, '\\'); i >= 0 do name = name[i + 1:]
	if !strings.has_prefix(name, "SZ_") do return
	base := fmt.tprintf("ST_%s", name[3:])
	if i := strings.last_index_byte(base, 'A'); i >= 0 {
		base = base[:i] // strip the trailing mesh-variant letter
	}

	sky_init()
	z.sky_tex1 = sky_texture(fmt.tprintf("%s1.png", base[:len(base) - 1]))
	z.sky_tex2 = sky_texture(fmt.tprintf("%s2.png", base[:len(base) - 1]))
}

// Process-lifetime texture cache keyed by asset path.
sky_texture :: proc(name: string) -> rl.Texture {
	if t, ok := sky_tex_cache[name]; ok do return t
	t := rl.LoadTexture(assets_cstring(fmt.tprintf("assets/sky/%s", name)))
	assets_texture_quality(&t)
	if t.id == 0 {
		rl.TraceLog(.WARNING, "sky: missing %s", assets_cstring(name))
	}
	sky_tex_cache[name] = t
	return t
}

// Draws the zone's sky dome behind everything. Call first inside
// BeginMode3D; cam_pos is the active camera position (render_zone derives
// it from the modelview for lighting already).
sky_draw :: proc(z: ^Zone_Definition, cam_pos: rl.Vector3) {
	if z == nil || z.sky_tex1.id == 0 do return
	if !sky_ready do return

	m := rl.MatrixTranslate(cam_pos.x, cam_pos.y, cam_pos.z) *
		rl.MatrixScale(SKY_DOME_RADIUS, SKY_DOME_RADIUS, SKY_DOME_RADIUS)
	albedo := int(rl.MaterialMapIndex.ALBEDO)

	rlgl.DisableDepthTest()
	rlgl.DisableDepthMask()
	rlgl.DisableBackfaceCulling()

	cp := cam_pos
	// Day/night modulation: bright at noon, deep blue under the night rows
	// (the original tints the dome with the time-of-day environment).
	tint := rl.Vector3{
		math.clamp(lighting_env.amb_up[0]*0.55 + lighting_env.sun_col[0]*0.35, 0, 1),
		math.clamp(lighting_env.amb_up[1]*0.55 + lighting_env.sun_col[1]*0.35, 0, 1),
		math.clamp(lighting_env.amb_up[2]*0.55 + lighting_env.sun_col[2]*0.35, 0, 1),
	}
	rl.BeginShaderMode(sky_shader)
	rl.SetShaderValue(sky_shader, sky_loc_cam, &cp, .VEC3)
	if sky_loc_tint >= 0 do rl.SetShaderValue(sky_shader, sky_loc_tint, &tint, .VEC3)
	sky_mat.maps[albedo].texture = z.sky_tex1
	rl.DrawMesh(sky_dome, sky_mat, m)
	if z.sky_tex2.id != 0 {
		rl.BeginBlendMode(.ALPHA)
		sky_mat.maps[albedo].texture = z.sky_tex2
		rl.DrawMesh(sky_dome, sky_mat, m)
		rl.EndBlendMode()
	}
	rl.EndShaderMode()

	rlgl.EnableDepthTest()
	rlgl.EnableDepthMask()
	rlgl.EnableBackfaceCulling()
}
