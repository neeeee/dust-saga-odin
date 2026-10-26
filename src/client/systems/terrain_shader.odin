package systems

// Alpha-cutout shader for the Pandora terrain bakes.
//
// The bakes' foliage/grass/road-decal materials are glTF alphaMode MASK —
// binary-alpha textures meant to be drawn with per-pixel discard. Raylib's
// default material shader has no discard, so those quads write depth across
// their transparent pixels and occlude everything drawn behind them (the sky
// ends up visible through tree canopies, roads render as solid blocks).
//
// This shader is the default unlit shader plus `if (a < 0.5) discard`. It is
// applied to EVERY terrain material, not just MASK ones: fully opaque
// textures never drop below the cutoff, so they are unaffected, and it saves
// tracking which material was which (raylib's loaded rl.Material does not
// carry the glTF alphaMode).

import rl "vendor:raylib"

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
void main()
{
    vec4 texel = texture(texture0, fragTexCoord);
    // Alpha cutout: foliage/grass/decal cards are binary-alpha (glTF MASK).
    // Discarded fragments write no depth, so nothing behind them is occluded.
    if (texel.a < 0.5) discard;
    finalColor = texel * colDiffuse * fragColor;
}
`

terrain_cutout_shader: rl.Shader
terrain_cutout_ready := false

// Process-lifetime lazily-loaded cutout shader (rlgl auto-resolves the
// standard locs for these attribute/uniform names).
terrain_shader_get :: proc() -> rl.Shader {
	if terrain_cutout_ready do return terrain_cutout_shader
	terrain_cutout_shader = rl.LoadShaderFromMemory(terrain_cutout_vs, terrain_cutout_fs)
	terrain_cutout_ready = true
	return terrain_cutout_shader
}
