package systems

// Audio layer: one-shot SE (cached wavs) + a single looping BGM Music stream.
// The game ships no audio table yet, so callers pass asset-relative paths
// taken straight from the data files ("<se> ./sound/SE/ese/ese_067.wav" minus
// the "./", "sound/BGM/BGM_000.ogg"); the scene and zone BGM picks are fixed
// here until a real mapping table appears. Everything follows the assets.odin
// cache pattern: keys are heap-cloned at insert, failed loads are negatively
// cached so per-frame callers can't retry-spam, and one TraceLog fires per
// load attempt.

import "core:fmt"
import "core:hash"
import "core:strings"
import rl "vendor:raylib"

ASSETS_ROOT :: "assets/"

MASTER_VOLUME :: f32(0.8)
BGM_VOLUME    :: f32(0.6)

// Fixed per-scene tracks (arbitrary but stable picks from BGM_000..028).
BGM_TITLE  :: "sound/BGM/BGM_026.ogg"
BGM_LOGIN  :: "sound/BGM/BGM_027.ogg"
BGM_SELECT :: "sound/BGM/BGM_028.ogg"

audio_ready:     bool
audio_sounds:    map[string]rl.Sound // path -> loaded sound (invalid = known-missing)
audio_bgm:       rl.Music
audio_bgm_path:  string // heap-owned path of the current/last track, "" = none
audio_bgm_valid: bool

audio_init :: proc() {
	rl.InitAudioDevice()
	rl.SetMasterVolume(MASTER_VOLUME)
	audio_sounds = make(map[string]rl.Sound)
	audio_ready = true
	rl.TraceLog(.INFO, "audio: device ready")
}

audio_shutdown :: proc() {
	if !audio_ready do return
	for path, s in audio_sounds {
		if rl.IsSoundValid(s) do rl.UnloadSound(s)
		delete_key(&audio_sounds, path)
		delete(path) // keys are heap-cloned at insert
	}
	delete(audio_sounds)
	audio_stop_bgm()
	rl.CloseAudioDevice() // must run before rl.CloseWindow (defer order in main)
	audio_ready = false
}

// Fire-and-forget one-shot sound. `path` is relative to the assets root
// ("sound/SE/ese/ese_067.wav"). Safe to call every frame; loads cache.
audio_play :: proc(path: string, volume := f32(1.0)) {
	if !audio_ready || len(path) == 0 do return

	s, ok := audio_sounds[path]
	if !ok {
		s = rl.LoadSound(assets_cstring(fmt.tprintf("%s%s", ASSETS_ROOT, path)))
		if rl.IsSoundValid(s) {
			rl.TraceLog(.INFO, "audio: loaded sound %s", assets_cstring(path))
		} else {
			rl.TraceLog(.WARNING, "audio: missing sound %s", assets_cstring(path))
		}
		key := strings.clone(path)
		audio_sounds[key] = s
	}
	if !rl.IsSoundValid(s) do return // negative cache

	rl.SetSoundVolume(s, volume)
	rl.PlaySound(s)
}

// Swap the BGM track. No-op when `path` is already the current track, so the
// main loop can call it every frame with the scene's pick.
audio_play_bgm :: proc(path: string) {
	if !audio_ready do return
	if path == audio_bgm_path do return

	audio_stop_bgm()
	if len(path) == 0 do return

	m := rl.LoadMusicStream(assets_cstring(fmt.tprintf("%s%s", ASSETS_ROOT, path)))
	if !rl.IsMusicValid(m) {
		rl.TraceLog(.WARNING, "audio: missing bgm %s", assets_cstring(path))
		return
	}
	audio_bgm = m
	audio_bgm_valid = true
	audio_bgm_path = strings.clone(path)
	audio_bgm.looping = true
	rl.SetMusicVolume(audio_bgm, BGM_VOLUME)
	rl.PlayMusicStream(audio_bgm)
	rl.TraceLog(.INFO, "audio: bgm %s", assets_cstring(path))
}

audio_stop_bgm :: proc() {
	if audio_bgm_valid {
		rl.StopMusicStream(audio_bgm)
		rl.UnloadMusicStream(audio_bgm)
		audio_bgm_valid = false
	}
	if len(audio_bgm_path) > 0 do delete(audio_bgm_path)
	audio_bgm_path = ""
}

// Per-frame music streaming — must be called from the main loop in every
// scene state, or the Music stream stalls.
audio_update :: proc(dt: f32) {
	if audio_bgm_valid do rl.UpdateMusicStream(audio_bgm)
	_ = dt
}

// Stable zone → BGM pick (BGM_000..028) via FNV-1a over the zone id, until a
// real zone→BGM table appears. Returns a temp-allocated path; consumed within
// the frame by audio_play_bgm.
audio_zone_bgm :: proc(zone_id: string) -> string {
	if len(zone_id) == 0 do return "sound/BGM/BGM_000.ogg"
	return fmt.tprintf("sound/BGM/BGM_%03d.ogg", hash.fnv32a(transmute([]byte)zone_id) % 29)
}
