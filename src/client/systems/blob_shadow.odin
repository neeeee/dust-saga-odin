package systems

// Soft radial blob shadows under characters (the original engine draws one
// under every actor; without it characters read as floating). A procedural
// radial-alpha texture on a ground quad, alpha-blended, depth-tested but
// not depth-written.

import "core:c"
import "core:math"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

blob_mesh: rl.Mesh
blob_mat: rl.Material
blob_ready := false

blob_shadow_init :: proc() {
	if blob_ready do return
	// 64² radial falloff: alpha = (1-r)² · 255.
	img := rl.GenImageColor(64, 64, rl.BLANK)
	for y in 0 ..< 64 {
		for x in 0 ..< 64 {
			dx := (f32(x) - 31.5) / 31.5
			dy := (f32(y) - 31.5) / 31.5
			r := 1.0 - math.min(1.0, math.sqrt(dx * dx + dy * dy))
			a := u8(f32(r * r * r) * 255.0)
			rl.ImageDrawPixel(&img, c.int(x), c.int(y), rl.Color{0, 0, 0, a})
		}
	}
	tex := rl.LoadTextureFromImage(img)
	rl.UnloadImage(img)

	blob_mesh = rl.GenMeshPlane(1, 1, 1, 1)
	blob_mat = rl.LoadMaterialDefault()
	albedo := int(rl.MaterialMapIndex.ALBEDO)
	blob_mat.maps[albedo].texture = tex
	// colDiffuse tints to pure black at ~59% alpha: soft dark disc.
	blob_mat.maps[albedo].color = rl.Color{0, 0, 0, 150}
	blob_ready = true
}

// Draws a soft shadow disc at (x, z) on surface `y` with diameter `d`.
blob_shadow_draw :: proc(x, y, z, d: f32) {
	blob_shadow_init()
	m := rl.MatrixTranslate(x, y + 0.03, z) * rl.MatrixScale(d, 1, d)
	rl.BeginBlendMode(.ALPHA)
	rlgl.DisableDepthMask()
	rl.DrawMesh(blob_mesh, blob_mat, m)
	rlgl.EnableDepthMask()
	rl.EndBlendMode()
}
