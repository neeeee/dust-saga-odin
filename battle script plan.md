# Battle script + sound integration plan

Exploration confirmed: 1,072 UTF-16 battle scripts (`atk_pc` auto-attacks keyed by anim code, `skill_exec` keyed by skill.csv serial id, `item_use` keyed by item id) whose commands are `<motion>`, `<wait>`, `<fx>`, `<se>`, `<hit>` (+ rare others we skip). `<fx>` resolves through fx.csv `TYPE,ID → fx/.../X.vra`; `<se>` is a literal path into `sound/SE/ese/`. The client has zero audio today; raylib's audio module is in the vendor binding. All hooks exist: `try_auto_attack`, `tick_cast`'s `used_pending`, `handle_damage`, scene transitions in `main.odin`, `handle_world_state` for zones.

## Phase 1 — audio foundation

**New `src/client/systems/audio.odin`** (mirrors assets.odin patterns):

- `audio_init` — `rl.InitAudioDevice` + master volume; called from `main.odin` right after `assets_init`; `audio_shutdown` frees cache + closes device.
- Lazy `map[string]rl.Sound` cache with negative caching for missing files; `audio_play(path, volume)` fire-and-forget (SE wavs are small mono 16-bit).
- BGM: one `rl.Music` stream at a time; `audio_play_bgm(path)` (stop/unload current, load+loop new); `audio_update(dt)` → `UpdateMusicStream` called from the main loop.
- Wiring: per-scene tracks at the `main.odin` state transitions (title/login/select/gameplay); in-game, `handle_world_state` picks a stable track per zone id (hash into BGM_000..028) — trivial to remap when a real zone→BGM table appears.

## Phase 2 — CSV readers + battle-script interpreter

**New `src/client/systems/battle_script.odin`**:

- UTF-16LE→UTF-8 decoder (BOM + surrogate pairs, ~40 lines; no CSV parser exists yet) + tolerant line/field splitting (CRLF, stray trailing commas, `#` comment lines).
- **fx.csv** loader: `(type,id) → .vra path` map (basis for the phase-3 renderer too). **skill.csv** loader: display-name → serial-id map (names verified to match the client's skill registry, e.g. "Provoke", "Heave").
- Script model: parsed `[dynamic]Battle_Op` timeline (MOTION code/speed/scale, WAIT, FX, SE, HIT; unknown ops like `make_chr` parsed + skipped with a one-time log). Lazy parse + cache keyed `"<model>,<code>"`; filename prefix = `<model_int*1000>` as %07d (verified 011→0011000 … 063→0063000).
- **Playback**: a small `Battle_Playback` bound to the local avatar; per-frame it walks the timeline — MOTION → `chara_avatar_play_action` (same clip codes we play today), SE → `audio_play`, FX → logged stub (renderer next round), HIT → no-op marker (the server's DAMAGE packet stays authoritative for impact feedback).
- **Combat wiring**:
  - `try_auto_attack` (after range + cooldown gates): resolve the family attack code as today, find `atk_pc[<model>_<code>]`; if present play the script (its motion op drives the same animation, timed sounds included); otherwise fall back to current `chara_avatar_play_attack`.
  - `tick_cast` on `used_pending`: resolve skill.csv id by skill name → `skill_exec[<model>_<id>]`; if present play the script; else current `play_skill_execution`.
  - Direct feedback sounds (non-script): `handle_damage` plays an impact wav on real hits (louder/different on crit, nothing on miss); `push_notification` gains an optional sound for "success"/"error" kinds only (blacksmith success, errors), "info" stays silent. Fixed ese picks to start.
- Item-use scripts: deferred until the client has an in-world item-use flow (noted in code).

## Out of scope this round (follow-ups)

FX renderer (fx.csv → .vra parser → generic particle system following the Arrow_Tracer pattern; hit/crit/block effects from fx.csv type 4, enhancement/level-up effects), `.mrb`/`.dxg`/voice assets, and migrating gameplay tables (item/monster/buff CSVs) onto file data — only the two small lookups above are loaded now.

## Verification

Build with `odin build` (green = link-checks `UpdateMusicStream`/`LoadSound` symbols too), plus one-time TraceLogs on first script load/fallback so a run log confirms which path (script vs fallback) fires. Runtime listening needs a manual run — check auto-attack sound timing, skill script pickup, blacksmith chime, BGM per scene/zone.
