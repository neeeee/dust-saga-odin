# Pandora map exporter — confirmed bugs to fix (handoff)

Context: the Dust Saga Odin client (`src/client/`) renders the
`assets/maps/map_*.glb` bakes. After the 2026-10-29 16:28 re-export of the
GLBs, whole building fronts vanish in every spec-honoring renderer (Dust Saga
client / raylib, and Noesis). The "Pandora Saga viewer" shows them only
because it ignores the alpha channel. The client-side has workarounds (see
`src/client/systems/map_builder.odin` → `glb_material_alpha`), but the
exporter should be fixed and the maps re-exported.

## Bug 1 (critical): facade textures exported with garbage alpha

Example: `map_T01_04.glb`, texture index 20 (256×256), used by materials
`OM_09_wv_atel01A` (idx 88), `OM_09_wv_bldg01AF` (idx 93), and the other
bldg01C*/smith facade materials — all `alphaMode: MASK, alphaCutoff: 0.392`.

- Alpha histogram: ~55% of texels at alpha 0-15, ~10.6% spread across the
  ENTIRE 16-239 range (soft gradient), ~34.5% at 240-255.
- The building-front prims' UVs (e.g. atelier mesh, node 250 / prim 1,
  259 verts, UVs (0,0)-(0.71,0.93)) sample texels that are ~98% BELOW the
  material's own 0.392 cutoff → any alpha-honoring renderer discards the
  whole facade → "invisible building".
- The RGB under those texels is complete and correct: the viewer shows the
  facade fine because it ignores alpha. The original client's walls are
  opaque, so the source DDS either had no alpha or opaque alpha — the PNG
  conversion invented the transparent channel (likely a light/shadow mask).

**Fix**: when exporting MASK materials, write BINARY alpha (255 where the
texel is meant to render, 0 where it's a cutout hole) — binarize at the
material's alphaCutoff, or drop the alpha channel entirely for
fully-opaque textures. Never emit mid-range alpha for MASK materials.
Affected: all facade/wall textures of this kind across the bakes (T01_04
tex 20 is one confirmed instance; check every bake).

## Bug 2 (high): bbox helper nodes exported as renderable meshes

Example: `map_T01_04.glb`, node 638 → mesh 136 `OM_70_nk_bbox01A` — a
3-vertex, 1×1cm triangle at translation (43.5, 0, -9.26), material idx 237
(`OM_70_nk_bbox01A`, texture idx 46: 64×64 with 100% alpha-0 texels, RGB
black). The original client never renders bbox helpers. In the export they
become renderable meshes whose GPU data manifests as huge garbage triangles
at camera-dependent positions (floating slabs, misplaced wall wedges).

**Fix**: exclude `OM_70_nk_bbox*` (and any other all-transparent helper
meshes — texture with zero opaque texels) from the export entirely, or give
them an explicitly empty mesh.

## Verification

- Noesis (GLB, alpha-honoring) and the Dust Saga client must both show the
  T01_04 plaza buildings: from spawn facing north across the plaza, the
  wall row with the arched door (`OM_09_wv_atel01A` / `OM_09_wv_bldg01C*`
  panels at z 44-83, x -20..+37) must be fully visible.
- Regression tool in the client: `tools/alpha_test.odin` renders
  1001004/1003001/1001001/2003001/99999999 to PNGs
  (`alpha_test_<zone>_<cam>.png` in src/client).
- Per-mesh dump tool: `tools/terrain_dump.exe [zone_id]` prints mesh index,
  material slot, size, center, and flags degenerate point meshes
  (`mesh 1075 mat 237` in the current T01_04 GLB is the bbox triangle).

## Client-side state (already shipped, no action needed)

`src/client/systems/map_builder.odin` (`glb_material_alpha`) now parses the
GLB JSON chunk and classifies per-PRIMITIVE (in raylib's flatten order —
raylib's `meshMaterial` indexes per-primitive material slots, NOT glTF
material indices; keying by glTF material index silently left most meshes
on stale uniforms). Rules: MASK-on-soft-alpha → OPAQUE (alpha ignored),
OPAQUE-on-all-transparent-texture → HIDDEN (skip), OPAQUE-twin-of-MASK →
MASK, BLEND kept, everything else OPAQUE. The draw also binds the shader
per mesh (`BeginShaderMode` before `SetShaderValue`) — uniforms submitted
without an explicit bind land on the previously bound program.
