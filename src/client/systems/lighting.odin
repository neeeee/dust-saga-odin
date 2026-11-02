package systems

// Per-zone lighting environment + a static sun shadow bake.
//
// The original game's lighting lives in world/env_settings/<zone>/
// {light,fog,ambient}.csv — sun color, fog color/range and a HEMISPHERE
// ambient (sky/upper + ground/lower). The map exporter already carries all
// of it in each zone JSON's `environment` block (sun direction is the same
// global vector for every zone), so this module just reads that:
//
//   environment.light.dir / .diffuse      directional sun
//   environment.ambient.upper / .lower    hemisphere ambient
//   environment.fog.color / .near / .far  linear fog (cm in JSON → m here)
//
// SHADOWS. The terrain is static and the sun direction is constant per
// zone, so instead of a per-frame shadow pass the whole bake is rendered
// ONCE per zone into a depth texture from a tight orthographic sun camera
// (lighting_bake_shadows). Terrain and entities sample that static map to
// receive shadows; moving entities do not cast into it (acceptable for the
// stylized look — the bake covers trees, buildings and terrain
// self-shadowing, which is most of the scene).
//
// SHADER PLUMBING. Two programs share the lighting model:
//   - the terrain cutout shader (terrain_shader.odin) — per-material glTF
//     alpha modes plus lighting;
//   - the entity shader here — swapped onto every model at load in
//     assets_model_acquire (characters, monsters, horses, gear), which
//     also survives the avatar subset material copies.
// raylib auto-provides `mvp`/`matModel` for custom shaders; the camera
// position and the lighting state itself are pushed as plain uniforms
// (rl.SetShaderValue submits to the currently bound program, so every push
// wraps itself in BeginShaderMode).

import "core:c"
import "core:math"
import "core:encoding/json"
import "core:os"
import "core:strings"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

// Shadow map resolution. One 2048² depth texture covers even the 1680m
// field maps at ~0.8m/texel — plenty for tree/building shadows.
SHADOW_RES :: 2048

// World→texel size of the current bake (for the shader's normal-offset
// lookup scale); 0 when no bake exists.
lighting_shadow_texel: f32

// The zone lighting environment, parsed from the map JSON's `environment`.
Zone_Lighting :: struct {
	has_env:  bool,
	sun_dir:  rl.Vector3, // normalized, the direction the light TRAVELS (down)
	sun_col:  [3]f32,
	amb_up:   [3]f32,
	amb_lo:   [3]f32,
	fog_col:  [3]f32,
	fog_near: f32, // meters from camera
	fog_far:  f32, // meters; <= fog_near = no fog
}

// Neutral daylight for zones without an environment block (and the
// non-gameplay scenes): soft white sun + even ambient, no fog, no shadows.
lighting_neutral :: proc() -> Zone_Lighting {
	return Zone_Lighting {
		has_env  = true,
		sun_dir  = rl.Vector3Normalize({0.38, -0.92, -0.04}),
		sun_col  = {0.55, 0.53, 0.50},
		amb_up   = {0.55, 0.55, 0.58},
		amb_lo   = {0.42, 0.40, 0.38},
		fog_near = 1.0,
		fog_far  = 0.0, // off
	}
}

// Runtime state. lighting_env holds the CURRENT zone's values (uniforms
// were pushed from it); lighting_enabled is the F1 debug toggle — flipping
// it re-pushes uniforms with/without lighting.
lighting_enabled: bool = true
lighting_env:      Zone_Lighting
lighting_env_base: Zone_Lighting // the zone's static environment
lighting_zone_id:  string        // heap clone; "" = no zone applied
lighting_shadow_tex: rl.Texture2D // .id == 0 = no bake
lighting_sun_mvp: rl.Matrix

// ── day/night cycle ───────────────────────────────────────────────────────
// The original env_settings CSVs key light/ambient/fog by HOUR (night rows
// at 0/4/19, day rows 5-18 — e.g. F02's night fog is dark blue RGB(27,52,
// 88), day fog light gray RGB(112,121,128)). assets/env/time_env.json
// carries those keyframes per zone (generated from the extracted CSVs);
// each value holds from its hour until the next. lighting_time_hours < 0
// follows the local wall clock; the F1 debug slider overrides it.

Time_Key :: struct {
	hour:  f32,
	fog_n: f32,
	fog_f: f32,
	fog_c: [3]f32,
	sun:   [3]f32,
	up:    [3]f32,
	lo:    [3]f32,
}

lighting_time_hours: f32 = -1
lighting_time_table: map[string][dynamic]Time_Key
lighting_time_loaded: bool
lighting_time_loading: bool

@(private) lerp3 :: proc "contextless" (a, b: [3]f32, t: f32) -> [3]f32 {
	return {a[0] + (b[0]-a[0])*t, a[1] + (b[1]-a[1])*t, a[2] + (b[2]-a[2])*t}
}

// Lazy-loads the time table once. Failures leave it empty (zones keep their
// static JSON environment).
lighting_time_load :: proc() {
	if lighting_time_loaded || lighting_time_loading do return
	lighting_time_loading = true
	defer lighting_time_loading = false
	data, err := os.read_entire_file_from_path("assets/env/time_env.json", allocator = context.allocator)
	if err != nil {
		lighting_time_loaded = true
		return
	}
	defer delete(data)
	root_v, perr := json.parse(data)
	if perr != .None {
		lighting_time_loaded = true
		return
	}
	defer json.destroy_value(root_v)
	root := obj_of(root_v)
	if is_null(root_v) {
		lighting_time_loaded = true
		return
	}
	for key, rows_arr in root {
		// json.parse keys view `data`, which is deleted below — clone the
		// key or every later lookup compares against freed bytes.
		key_owned := strings.clone(key)
		arr, _ := rows_arr.(json.Array)
		rows_dyn := as_dyn(arr)
		if len(rows_dyn) == 0 {
			delete(key_owned)
			continue
		}
		rows := make([dynamic]Time_Key)
		for rv in rows_dyn {
			o := obj_of(rv)
			k := Time_Key{hour = f32(get_f32(o, "h", 0))}
			k.fog_n = f32(get_f32(o, "fog_n", 0))
			k.fog_f = f32(get_f32(o, "fog_f", 0))
			if a := as_dyn(get_array(o, "fog_c")); len(a) >= 3 {
				k.fog_c = {f32(number_of(a[0])), f32(number_of(a[1])), f32(number_of(a[2]))}
			}
			if a := as_dyn(get_array(o, "sun")); len(a) >= 3 {
				k.sun = {f32(number_of(a[0])), f32(number_of(a[1])), f32(number_of(a[2]))}
				k.up = k.sun // fallback when the zone has no ambient rows
			}
			if a := as_dyn(get_array(o, "up")); len(a) >= 3 {
				k.up = {f32(number_of(a[0])), f32(number_of(a[1])), f32(number_of(a[2]))}
			}
			if a := as_dyn(get_array(o, "lo")); len(a) >= 3 {
				k.lo = {f32(number_of(a[0])), f32(number_of(a[1])), f32(number_of(a[2]))}
			}
			append(&rows, k)
		}
		lighting_time_table[key_owned] = rows
	}
	lighting_time_loaded = true
}

// The effective time of day (hours 0..24): the F1 override when set, else
// fixed NOON. The original runs on SERVER game time (its day/night follows
// the server clock, not the player's wall clock — AoA screenshots taken at
// 23:00 local show full daylight); without a server time source, daytime
// matches the reference look. The F1 slider still previews night.
lighting_time_now :: proc() -> f32 {
	if lighting_time_hours >= 0 do return math.mod(lighting_time_hours, 24.0)
	return 12.0
}

// Overwrites `env`'s time-varying fields from the zone's keyframes,
// interpolated at the current hour (wrapping midnight).
lighting_apply_time :: proc(env: ^Zone_Lighting, zone_id: string) {
	lighting_time_load()
	rows, ok := lighting_time_table[zone_id]
	if !ok || len(rows) == 0 do return
	h := lighting_time_now()
	cur_i := 0
	for r, i in rows {
		if r.hour <= h do cur_i = i
	}
	nxt_i := cur_i + 1
	nxt_hour := f32(24)
	if nxt_i < len(rows) {
		nxt_hour = rows[nxt_i].hour
	} else {
		nxt_i = 0
		nxt_hour = rows[0].hour + 24
	}
	cur := rows[cur_i]
	span := nxt_hour - cur.hour
	t := span > 0 ? math.clamp((h - cur.hour) / span, 0, 1) : 0
	env.fog_near = cur.fog_n + (rows[nxt_i].fog_n - cur.fog_n) * t
	env.fog_far = cur.fog_f + (rows[nxt_i].fog_f - cur.fog_f) * t
	env.fog_col = lerp3(cur.fog_c, rows[nxt_i].fog_c, t)
	env.sun_col = lerp3(cur.sun, rows[nxt_i].sun, t)
	env.amb_up = lerp3(cur.up, rows[nxt_i].up, t)
	env.amb_lo = lerp3(cur.lo, rows[nxt_i].lo, t)
}

// ── entity (lit model) shader ─────────────────────────────────────────────

lighting_entity_vs :: `
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

lighting_entity_fs :: `
#version 330
in vec2 fragTexCoord;
in vec4 fragColor;
in vec3 fragNormal;
in vec3 fragWorld;
out vec4 finalColor;
uniform sampler2D texture0;
uniform vec4 colDiffuse;
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

// ENTITY variant: characters need soft, ambient-dominated shading (the
// original's faces carry no harsh sun terminator). Wrap lighting bends the
// sun around the silhouette and the ambient share rises, so the lit/shadow
// side ratio stays gentle. The terrain shader keeps the crisper model.
vec3 lighting_apply(vec3 N, vec3 world)
{
    float ndl = clamp((dot(N, sunDir) + 0.65) / 1.65, 0.0, 1.0);
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
    // Character balance: ambient-dominated so faces never go mask-dark.
    // 0.85 ambient + 0.22 wrapped sun keeps the lit/shadow ratio around
    // 1.2x — the AoA close-up shows exactly that gentle modeling.
    vec3 hemi = mix(ambLo, ambUp, clamp(N.y * 0.25 + 0.7, 0.0, 1.0)) * 0.85;
    return hemi + sunCol * (ndl * lit) * 0.22;
}

void main()
{
    vec4 texel = texture(texture0, fragTexCoord);
    vec3 rgb = texel.rgb;
    float a = texel.a;
    if (litEnabled == 1) {
        vec3 L = lighting_apply(normalize(fragNormal), fragWorld);
        rgb *= L;
        if (fogFar > fogNear) {
            float dist = distance(camPos, fragWorld);
            float f = clamp((dist - fogNear) / (fogFar - fogNear), 0.0, 1.0);
            rgb = mix(rgb, fogCol, f);
        }
    }
    finalColor = vec4(rgb, a) * colDiffuse * fragColor;
}
`

lighting_entity_shader: rl.Shader
lighting_entity_ready: bool

lighting_entity_shader_get :: proc() -> rl.Shader {
	if lighting_entity_ready do return lighting_entity_shader
	lighting_entity_shader = rl.LoadShaderFromMemory(lighting_entity_vs, lighting_entity_fs)
	lighting_entity_ready = true
	return lighting_entity_shader
}

// ── uniform plumbing ──────────────────────────────────────────────────────

// Location cache per shader (created lazily; raylib resolves standard
// names like mvp/matModel on load, the lighting ones are ours).
Lighting_Locs :: struct {
	lit_enable:   c.int,
	sun_dir:      c.int,
	sun_col:      c.int,
	amb_up:       c.int,
	amb_lo:       c.int,
	fog_col:      c.int,
	fog_near:     c.int,
	fog_far:      c.int,
	cam_pos:      c.int,
	shadow_on:    c.int,
	shadow_map:   c.int,
	sun_mvp:      c.int,
	shadow_texel: c.int,
}

lighting_locs_cache: map[rl.Shader]Lighting_Locs

lighting_locs :: proc(sh: rl.Shader) -> Lighting_Locs {
	if l, ok := lighting_locs_cache[sh]; ok do return l
	l: Lighting_Locs
	l.lit_enable = rl.GetShaderLocation(sh, "litEnabled")
	l.sun_dir = rl.GetShaderLocation(sh, "sunDir")
	l.sun_col = rl.GetShaderLocation(sh, "sunCol")
	l.amb_up = rl.GetShaderLocation(sh, "ambUp")
	l.amb_lo = rl.GetShaderLocation(sh, "ambLo")
	l.fog_col = rl.GetShaderLocation(sh, "fogCol")
	l.fog_near = rl.GetShaderLocation(sh, "fogNear")
	l.fog_far = rl.GetShaderLocation(sh, "fogFar")
	l.cam_pos = rl.GetShaderLocation(sh, "camPos")
	l.shadow_on = rl.GetShaderLocation(sh, "shadowEnabled")
	l.shadow_map = rl.GetShaderLocation(sh, "shadowMap")
	l.sun_mvp = rl.GetShaderLocation(sh, "sunMVP")
	l.shadow_texel = rl.GetShaderLocation(sh, "shadowTexel")
	lighting_locs_cache[sh] = l
	return l
}

// Push the current environment + camera into one shader. SetShaderValue
// submits to the CURRENTLY BOUND program, hence the BeginShaderMode wrap.
lighting_push_shader :: proc(sh: rl.Shader, cam_pos: rl.Vector3) {
	l := lighting_locs(sh)
	rl.BeginShaderMode(sh)

	on: c.int = lighting_enabled && lighting_env.has_env ? 1 : 0
	if l.lit_enable >= 0 do rl.SetShaderValue(sh, l.lit_enable, &on, .INT)

	sun := rl.Vector3{
		-lighting_env.sun_dir.x,
		-lighting_env.sun_dir.y,
		-lighting_env.sun_dir.z,
	}
	if l.sun_dir >= 0 do rl.SetShaderValue(sh, l.sun_dir, &sun, .VEC3)
	if l.sun_col >= 0 do rl.SetShaderValue(sh, l.sun_col, &lighting_env.sun_col, .VEC3)
	if l.amb_up >= 0 do rl.SetShaderValue(sh, l.amb_up, &lighting_env.amb_up, .VEC3)
	if l.amb_lo >= 0 do rl.SetShaderValue(sh, l.amb_lo, &lighting_env.amb_lo, .VEC3)
	if l.fog_col >= 0 do rl.SetShaderValue(sh, l.fog_col, &lighting_env.fog_col, .VEC3)
	if l.fog_near >= 0 do rl.SetShaderValue(sh, l.fog_near, &lighting_env.fog_near, .FLOAT)
	if l.fog_far >= 0 do rl.SetShaderValue(sh, l.fog_far, &lighting_env.fog_far, .FLOAT)
	if l.cam_pos >= 0 {
		cp := cam_pos
		rl.SetShaderValue(sh, l.cam_pos, &cp, .VEC3)
	}

	shadow_on: c.int = (lighting_enabled && lighting_shadow_tex.id != 0) ? 1 : 0
	if l.shadow_on >= 0 do rl.SetShaderValue(sh, l.shadow_on, &shadow_on, .INT)
	if l.shadow_map >= 0 {
		// The sampler lives on texture unit 1 (unit 0 is the material's
		// albedo); bind the depth texture there and tell the shader.
		unit: c.int = 1
		rl.SetShaderValue(sh, l.shadow_map, &unit, .INT)
		rlgl.ActiveTextureSlot(1)
		rlgl.EnableTexture(lighting_shadow_tex.id)
		rlgl.ActiveTextureSlot(0)
	}
	if l.sun_mvp >= 0 do rl.SetShaderValueMatrix(sh, l.sun_mvp, lighting_sun_mvp)
	if l.shadow_texel >= 0 {
		texel := lighting_shadow_tex.id != 0 ? lighting_shadow_texel : 0.0
		rl.SetShaderValue(sh, l.shadow_texel, &texel, .FLOAT)
	}

	rl.EndShaderMode()
}

// Per-frame: camera position for fog distance, plus the day/night
// re-evaluation of the environment (fog/sun/ambient vary by hour; the sun
// DIRECTION is static). Called from render_zone inside BeginMode3D.
lighting_set_camera :: proc(cam_pos: rl.Vector3) {
	if lighting_zone_id != "" {
		lighting_env = lighting_env_base
		lighting_apply_time(&lighting_env, lighting_zone_id)
	}
	lighting_push_shader(terrain_shader_get(), cam_pos)
	lighting_push_shader(lighting_entity_shader_get(), cam_pos)
}

// ── zone wiring ───────────────────────────────────────────────────────────

// Parses the map JSON's `environment` block. Missing/invalid → neutral
// defaults (has_env still true — lighting without fog/shadows).
lighting_parse_environment :: proc(root: JSON_Object) -> Zone_Lighting {
	env := lighting_neutral()
	o := get_object(root, "environment")
	if is_null(json.Value(o)) do return env

	light := get_object(o, "light")
	dir := get_array(light, "dir")
	if len(as_dyn(dir)) >= 3 {
		v := rl.Vector3{
			f32(number_of(as_dyn(dir)[0])),
			f32(number_of(as_dyn(dir)[1])),
			f32(number_of(as_dyn(dir)[2])),
		}
		if v.x != 0 || v.y != 0 || v.z != 0 {
			env.sun_dir = rl.Vector3Normalize(v)
		}
	}
	copy_rgb(get_array(light, "diffuse"), &env.sun_col)

	ambient := get_object(o, "ambient")
	copy_rgb(get_array(ambient, "upper"), &env.amb_up)
	copy_rgb(get_array(ambient, "lower"), &env.amb_lo)

	fog := get_object(o, "fog")
	if get_int(fog, "enable", 0) == 1 {
		copy_rgb(get_array(fog, "color"), &env.fog_col)
		// JSON distances are engine centimeters.
		near := f32(get_f32(fog, "near", 0)) * 0.01
		far := f32(get_f32(fog, "far", 0)) * 0.01
		if far > near {
			env.fog_near = near
			env.fog_far = far
		}
	}
	return env
}

@(private) copy_rgb :: proc (arr: JSON_Array, dst: ^[3]f32) {
	dyn := as_dyn(arr)
	if len(dyn) >= 3 {
		dst^ = {
			f32(number_of(dyn[0])),
			f32(number_of(dyn[1])),
			f32(number_of(dyn[2])),
		}
	}
}

// Clear color for the frame: the fog color (the original horizon blend);
// sky blue before fog exists / with fog off. Re-evaluates the day/night env
// so the very first frame after a zone load clears with the right color.
lighting_clear_color :: proc() -> rl.Color {
	env := lighting_env
	if lighting_zone_id != "" {
		env = lighting_env_base
		lighting_apply_time(&env, lighting_zone_id)
	}
	if lighting_enabled && env.has_env && env.fog_far > env.fog_near {
		return rl.Color{
			u8(math.clamp(env.fog_col[0], 0, 1) * 255),
			u8(math.clamp(env.fog_col[1], 0, 1) * 255),
			u8(math.clamp(env.fog_col[2], 0, 1) * 255),
			255,
		}
	}
	return rl.SKYBLUE
}

// Installs a zone's environment and bakes its static shadow map. Call once
// per zone load, after the terrain model + bounding spheres exist. nil zone
// (leaving a zone) resets to the neutral environment without shadows.
lighting_apply :: proc(zone: ^Zone_Definition) {
	lighting_shadow_tex = {}
	lighting_shadow_texel = 0
	if len(lighting_zone_id) > 0 do delete(lighting_zone_id)
	lighting_zone_id = ""
	// NOTE: load_zone_map calls this BEFORE z.loaded is set, so gate on the
	// parsed environment itself, not the loaded flag.
	lighting_env = zone != nil && zone.lighting.has_env ? zone.lighting : lighting_neutral()
	lighting_env_base = lighting_env
	if zone != nil {
		lighting_zone_id = strings.clone(zone.id)
	}

	if zone != nil && zone.terrain != nil && lighting_env.has_env {
		lighting_bake_shadows(zone)
	}

	// Push to both programs with a placeholder camera; the real camera
	// position arrives per frame via lighting_set_camera.
	cam := rl.Vector3{0, 10, 0}
	lighting_push_shader(terrain_shader_get(), cam)
	lighting_push_shader(lighting_entity_shader_get(), cam)
}

// F1 toggle handler: re-push uniforms from the stored environment.
lighting_refresh :: proc() {
	cam := rl.Vector3{0, 10, 0}
	lighting_push_shader(terrain_shader_get(), cam)
	lighting_push_shader(lighting_entity_shader_get(), cam)
}

// ── static shadow bake ────────────────────────────────────────────────────

@(private) shadow_blank_mat: rl.Material
@(private) shadow_blank_loaded: bool

// Renders the zone's terrain meshes into a depth texture from a tight
// orthographic sun camera. Stores the world→sun-clip matrix and the depth
// texture id globally; keeps the RenderTexture alive on the zone (freed by
// zone_destroy → lighting_release_zone).
lighting_bake_shadows :: proc(zone: ^Zone_Definition) {
	model := &zone.terrain.model
	if model.meshCount == 0 do return

	// Tight world AABB over all terrain meshes.
	min := rl.Vector3{1e9, 1e9, 1e9}
	max := rl.Vector3{-1e9, -1e9, -1e9}
	for i in 0 ..< int(model.meshCount) {
		if model.meshes[i].vertexCount <= 0 do continue
		b := rl.GetMeshBoundingBox(model.meshes[i])
		min.x = math.min(min.x, b.min.x)
		min.y = math.min(min.y, b.min.y)
		min.z = math.min(min.z, b.min.z)
		max.x = math.max(max.x, b.max.x)
		max.y = math.max(max.y, b.max.y)
		max.z = math.max(max.z, b.max.z)
	}
	if min.x > max.x do return

	center := (min + max) * 0.5
	sun := lighting_env.sun_dir // points down, toward the scene
	eye := center - sun * 200.0
	view := rl.MatrixLookAt(eye, center, {0, 1, 0})

	// Fit the ortho box around the world AABB expressed in sun-space axes
	// (the view matrix's rows are the camera basis under row-major math).
	right := rl.Vector3{view[0, 0], view[0, 1], view[0, 2]}
	up := rl.Vector3{view[1, 0], view[1, 1], view[1, 2]}
	fwd := rl.Vector3{view[2, 0], view[2, 1], view[2, 2]}
	half_x, half_y := f32(0), f32(0)
	near, far := f32(1e9), f32(-1e9)
	corners := [8]rl.Vector3{
		{min.x, min.y, min.z}, {max.x, min.y, min.z},
		{min.x, max.y, min.z}, {max.x, max.y, min.z},
		{min.x, min.y, max.z}, {max.x, min.y, max.z},
		{min.x, max.y, max.z}, {max.x, max.y, max.z},
	}
	for corner in corners {
		d := corner - eye
		half_x = math.max(half_x, math.abs(rl.Vector3DotProduct(d, right)))
		half_y = math.max(half_y, math.abs(rl.Vector3DotProduct(d, up)))
		z := rl.Vector3DotProduct(d, fwd)
		near = math.min(near, z)
		far = math.max(far, z)
	}
	near -= 50
	far += 50
	proj := rl.MatrixOrtho(-half_x, half_x, -half_y, half_y, near, far)
	lighting_sun_mvp = proj * view
	lighting_shadow_texel = (half_x * 2 + half_y * 2) / f32(SHADOW_RES * 2)

	if !shadow_blank_loaded {
		shadow_blank_mat = rl.LoadMaterialDefault()
		shadow_blank_loaded = true
	}

	rt := rl.LoadRenderTexture(SHADOW_RES, SHADOW_RES)
	if rt.id == 0 || rt.depth.id == 0 {
		// No sampleable depth attachment in this raylib build — skip
		// shadows rather than sample garbage.
		rl.TraceLog(.WARNING, "lighting: no depth texture, shadows disabled")
		if rt.id != 0 do rl.UnloadRenderTexture(rt)
		lighting_shadow_tex = {}
		return
	}

	rl.BeginTextureMode(rt)
	rl.ClearBackground(rl.WHITE)
	rlgl.ClearScreenBuffers() // depth too
	rlgl.SetMatrixProjection(proj)
	rlgl.SetMatrixModelview(view)
	ident := rl.Matrix(1)
	for i in 0 ..< int(model.meshCount) {
		if model.meshes[i].vertexCount <= 0 do continue
		rl.DrawMesh(model.meshes[i], shadow_blank_mat, ident)
	}
	rl.EndTextureMode()
	// BeginTextureMode leaves 2D matrices; whatever draws next sets its own
	// (BeginMode3D), so no restore is needed here.

	zone.shadow_rt = rt
	lighting_shadow_tex = rt.depth
	rl.TraceLog(.INFO, "lighting: baked %dx%d shadow map (%.0fx%.0fm)",
		c.int(SHADOW_RES), c.int(SHADOW_RES), half_x * 2, half_y * 2)
}

// Frees the zone's shadow RenderTexture (the terrain model itself is
// cache-shared and released separately).
lighting_release_zone :: proc(zone: ^Zone_Definition) {
	if zone == nil do return
	if zone.shadow_rt.id != 0 {
		// Drop the global sampler binding before the texture dies; the
		// shadowEnabled uniform derives from it, so re-push both shaders.
		if zone.shadow_rt.depth.id == lighting_shadow_tex.id {
			lighting_shadow_tex = {}
			lighting_shadow_texel = 0
			lighting_refresh()
		}
		rl.UnloadRenderTexture(zone.shadow_rt)
		zone.shadow_rt = {}
	}
}

Lighting_Apply_Time_Test :: lighting_apply_time
