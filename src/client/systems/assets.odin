package systems

// Asset manager: process-wide caches for GPU resources (textures, models).
//
// Scenes request assets by path and get value copies of the raylib handles;
// the cache owns the underlying GPU data and unloads everything on shutdown.
// All paths are relative to the client working directory (src/client).
//
// Textures are cached for the whole session (icons/UI/cursors are small and
// reused constantly). Models are refcounted — character glbs are 20-45 MB of
// VRAM each, so the owner (e.g. the character-select preview) releases them
// when done and the cache unloads at refcount zero.
//
// Failed loads are negatively cached (so per-frame callers don't retry-spam)
// and return an invalid resource; callers guard draws on `.id > 0` /
// `entry != nil`.

import "core:os"
import "core:strings"
import rl "vendor:raylib"

Model_Entry :: struct {
	model: rl.Model,
	refs:  int,
}

asset_textures: map[string]rl.Texture2D
asset_models:   map[string]^Model_Entry
asset_ready:    bool

assets_init :: proc() {
	asset_textures = make(map[string]rl.Texture2D)
	asset_models = make(map[string]^Model_Entry)
	asset_ready = true
}

assets_destroy :: proc() {
	if !asset_ready do return
	for _, entry in asset_models {
		rl.UnloadModel(entry.model)
		free(entry)
	}
	delete(asset_models)
	for key, tex in asset_textures {
		if tex.id > 0 do rl.UnloadTexture(tex)
		delete(key) // keys are heap-cloned at insert
	}
	delete(asset_textures)
	asset_ready = false
}

// Load-once texture lookup. Safe to call every frame — hits are a pure map
// lookup (no allocation), misses load once and cache (including failures).
// .tga files go through our own decoder (see assets_texture_tga).
assets_texture :: proc(path: string) -> rl.Texture2D {
	if tex, ok := asset_textures[path]; ok do return tex

	tex: rl.Texture2D
	if strings.has_suffix(path, ".tga") {
		tex = assets_texture_tga(path)
	} else {
		tex = rl.LoadTexture(assets_cstring(path))
	}
	if tex.id == 0 {
		rl.TraceLog(.WARNING, "assets: failed to load texture %s", assets_cstring(path))
	} else {
		rl.TraceLog(.INFO, "assets: loaded texture %s (%dx%d)",
			assets_cstring(path), tex.width, tex.height)
	}
	key := strings.clone(path)
	asset_textures[key] = tex
	return tex
}

// Minimal TGA decoder for the game's UI assets: raylib's built-in TGA loader
// rejects this set (32-bit top-down, RLE variants), so we decode type 2/10,
// 8/24/32 bpp ourselves into RGBA8 and upload from memory. Bottom-up files are
// flipped; with 32 bpp the 4th byte is treated as alpha (these are cursor /
// icon sprites that rely on it).
assets_texture_tga :: proc(path: string) -> rl.Texture2D {
	data, err := os.read_entire_file_from_path(path, allocator = context.allocator)
	if err != nil {
		return {}
	}
	defer delete(data)

	if len(data) < 18 {
		return {}
	}
	id_len := int(data[0])
	color_map_type := data[1]
	image_type := data[2]
	w := int(data[12]) | int(data[13]) << 8
	h := int(data[14]) | int(data[15]) << 8
	bpp := int(data[16])
	descriptor := data[17]

	if color_map_type != 0 || (image_type != 2 && image_type != 10) || w <= 0 || h <= 0 {
		return {}
	}
	bytes_pp := bpp / 8
	if (bpp != 8 && bpp != 24 && bpp != 32) || bytes_pp == 0 {
		return {}
	}

	src := data[18 + id_len:]
	pixels := make([]u8, w * h * 4)
	written := 0 // RGBA bytes written so far
	off := 0

	read_pixel :: proc(src: []u8, off: ^int, bytes_pp: int, px: []u8) -> bool {
		if off^ + bytes_pp > len(src) do return false
		if bytes_pp == 1 {
			v := src[off^]
			px[0], px[1], px[2], px[3] = v, v, v, 255
		} else {
			px[0] = src[off^ + 2] // R
			px[1] = src[off^ + 1] // G
			px[2] = src[off^]     // B
			px[3] = bytes_pp == 4 ? src[off^ + 3] : 255
		}
		off^ += bytes_pp
		return true
	}

	put_pixel :: proc(pixels: []u8, written: ^int, px: []u8) {
		if written^ + 4 <= len(pixels) {
			for i in 0..<4 do pixels[written^ + i] = px[i]
			written^ += 4
		}
	}

	px_buf: [4]u8
	px := px_buf[:]
	if image_type == 2 { // uncompressed
		for written < len(pixels) {
			if !read_pixel(src, &off, bytes_pp, px) {
				delete(pixels)
				return {}
			}
			put_pixel(pixels, &written, px)
		}
	} else { // type 10: run-length encoded
		for written < len(pixels) {
			if off >= len(src) {
				delete(pixels)
				return {}
			}
			packet := src[off]
			off += 1
			count := int(packet & 0x7F) + 1
			if packet & 0x80 != 0 { // RLE run: one pixel repeated
				if !read_pixel(src, &off, bytes_pp, px) {
					delete(pixels)
					return {}
				}
				for c in 0..<count do put_pixel(pixels, &written, px)
			} else { // raw packet: `count` literal pixels
				for c in 0..<count {
					if !read_pixel(src, &off, bytes_pp, px) {
						delete(pixels)
						return {}
					}
					put_pixel(pixels, &written, px)
				}
			}
		}
	}

	// Bottom-up TGA origin → flip to top-down.
	if descriptor & 0x20 == 0 {
		row := make([]u8, w * 4)
		for y in 0..<h / 2 {
			top := y * w * 4
			bot := (h - 1 - y) * w * 4
			copy(row, pixels[top:top + w * 4])
			copy(pixels[top:top + w * 4], pixels[bot:bot + w * 4])
			copy(pixels[bot:bot + w * 4], row)
		}
		delete(row)
	}

	image := rl.Image{
		data    = raw_data(pixels),
		width   = i32(w),
		height  = i32(h),
		mipmaps = 1,
		format  = .UNCOMPRESSED_R8G8B8A8,
	}
	tex := rl.LoadTextureFromImage(image)
	delete(pixels)
	return tex
}

// Acquires (and loads on first request) a model. The caller must eventually
// assets_model_release the returned entry. Failed loads return nil.
assets_model_acquire :: proc(path: string) -> ^Model_Entry {
	if entry, ok := asset_models[path]; ok {
		entry.refs += 1
		return entry
	}

	model := rl.LoadModel(assets_cstring(path))
	if model.meshCount == 0 {
		rl.TraceLog(.WARNING, "assets: failed to load model %s", assets_cstring(path))
		return nil
	}
	rl.TraceLog(.INFO, "assets: loaded model %s (%d meshes)",
		assets_cstring(path), model.meshCount)

	entry := new(Model_Entry)
	entry.model = model
	entry.refs = 1
	key := strings.clone(path)
	asset_models[key] = entry
	return entry
}

// Drops one reference; the model is unloaded when the last reference goes.
assets_model_release :: proc(entry: ^Model_Entry) {
	if entry == nil do return
	entry.refs -= 1
	if entry.refs > 0 do return
	for key, v in asset_models {
		if v == entry {
			delete_key(&asset_models, key)
			delete(key) // keys are heap-cloned at insert
			break
		}
	}
	rl.UnloadModel(entry.model)
	free(entry)
}

// cstring for raylib's file-loading APIs. Same trade-off as draw_text: cloned
// on the temp allocator, which is the per-frame arena during the main loop and
// the heap for one-shot init-time loads — both fine to leave unreleased.
assets_cstring :: proc(s: string) -> cstring {
	return strings.clone_to_cstring(s, context.temp_allocator)
}
