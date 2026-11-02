package systems

// Fullscreen post-processing: the 3D scene renders into an offscreen
// texture, then a single composite pass adds bloom (bright-pass blur),
// mild vibrance and soft contrast on the way to the backbuffer. The 2D HUD
// draws after, unbloomed, staying crisp.
//
// Usage per frame: postfx_begin() in place of the ClearBackground, render
// the 3D scene, postfx_end() after EndMode3D.

import "core:c"
import "core:fmt"
import rl "vendor:raylib"

postfx_rt: rl.RenderTexture2D
postfx_shader: rl.Shader
postfx_ready := false

postfx_fs :: `
#version 330
in vec2 fragTexCoord;
out vec4 finalColor;
uniform sampler2D texture0;
void main()
{
    ivec2 sz = textureSize(texture0, 0);
    vec2 texel = 1.0 / vec2(sz);
    vec3 col = texture(texture0, fragTexCoord).rgb;

    // Bright-pass blur: 16 taps in two rings. Threshold 0.55 keeps the
    // bloom to sunlit/sky/emissive pixels only.
    vec3 bloom = vec3(0.0);
    vec2 d1 = texel * 1.5;
    vec2 d2 = texel * 4.0;
    bloom += max(texture(texture0, fragTexCoord + vec2( d1.x,  d1.y)).rgb - 0.55, 0.0);
    bloom += max(texture(texture0, fragTexCoord + vec2(-d1.x,  d1.y)).rgb - 0.55, 0.0);
    bloom += max(texture(texture0, fragTexCoord + vec2( d1.x, -d1.y)).rgb - 0.55, 0.0);
    bloom += max(texture(texture0, fragTexCoord + vec2(-d1.x, -d1.y)).rgb - 0.55, 0.0);
    bloom += max(texture(texture0, fragTexCoord + vec2( d2.x,  d2.y)).rgb - 0.55, 0.0);
    bloom += max(texture(texture0, fragTexCoord + vec2(-d2.x,  d2.y)).rgb - 0.55, 0.0);
    bloom += max(texture(texture0, fragTexCoord + vec2( d2.x, -d2.y)).rgb - 0.55, 0.0);
    bloom += max(texture(texture0, fragTexCoord + vec2(-d2.x, -d2.y)).rgb - 0.55, 0.0);
    bloom += max(texture(texture0, fragTexCoord + vec2( d2.x * 2.0, 0.0)).rgb - 0.55, 0.0);
    bloom += max(texture(texture0, fragTexCoord + vec2(-d2.x * 2.0, 0.0)).rgb - 0.55, 0.0);
    bloom += max(texture(texture0, fragTexCoord + vec2(0.0,  d2.y * 2.0)).rgb - 0.55, 0.0);
    bloom += max(texture(texture0, fragTexCoord + vec2(0.0, -d2.y * 2.0)).rgb - 0.55, 0.0);
    bloom /= 12.0;
    col = col * 0.92 + bloom * 0.60;

    // Overall world brightness: gamma lift brightens midtones/shadows more
    // than highlights (no clipping), plus a touch of straight gain.
    col = pow(max(col, vec3(0.0)), vec3(1.0 / 1.4)) * 1.04;

    // Mild vibrance + soft contrast: the original's post chain reads
    // noticeably more saturated than raw texel*light output.
    float lum = dot(col, vec3(0.299, 0.587, 0.114));
    col = mix(vec3(lum), col, 1.12);
    col = clamp((col - 0.5) * 1.06 + 0.5, 0.0, 1.0);

    finalColor = vec4(col, 1.0);
}
`

postfx_vs :: `
#version 330
in vec3 vertexPosition;
in vec2 vertexTexCoord;
out vec2 fragTexCoord;
uniform mat4 mvp;
void main()
{
    fragTexCoord = vertexTexCoord;
    gl_Position = mvp * vec4(vertexPosition, 1.0);
}
`

postfx_init :: proc() {
	if postfx_ready do return
	postfx_shader = rl.LoadShaderFromMemory(postfx_vs, postfx_fs)
	postfx_reload_target()
	postfx_ready = true
}

postfx_shutdown :: proc() {
	if !postfx_ready do return
	rl.UnloadRenderTexture(postfx_rt)
	rl.UnloadShader(postfx_shader)
	postfx_ready = false
}

postfx_reload_target :: proc() {
	if postfx_rt.id != 0 do rl.UnloadRenderTexture(postfx_rt)
	w := rl.GetScreenWidth()
	h := rl.GetScreenHeight()
	if w <= 0 do w = 1280
	if h <= 0 do h = 720
	postfx_rt = rl.LoadRenderTexture(w, h)
}

// Starts the offscreen scene pass (call in place of the frame's
// ClearBackground). Re-creates the target when the window size changes.
postfx_begin :: proc(clear: rl.Color) {
	postfx_init()
	w, h := rl.GetScreenWidth(), rl.GetScreenHeight()
	if postfx_rt.texture.width != c.int(w) || postfx_rt.texture.height != c.int(h) {
		postfx_reload_target()
	}
	rl.BeginTextureMode(postfx_rt)
	rl.ClearBackground(clear)
}

// Composites the scene onto the backbuffer with bloom. Call after
// EndMode3D; the 2D HUD draws on the backbuffer afterwards.
postfx_end :: proc() {
	rl.EndTextureMode()
	rl.BeginShaderMode(postfx_shader)
	src := postfx_rt.texture
	rl.DrawTextureRec(
		src,
		{0, 0, f32(src.width), f32(-src.height)},
		{0, 0},
		rl.WHITE,
	)
	rl.EndShaderMode()
}
