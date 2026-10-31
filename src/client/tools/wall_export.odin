package wall_export

// Exports every zone's wall segments (hit proxies + JSON colliders +
// blocking instances + bake structure faces) to a JSON the server loads
// for line-of-sight and knockback clamping:
//
//   src/server/data/zone_walls.json
//     { "lists": [ [[x1,z1,x2,z2,yMin,yMax,move?], ...], ... ],
//       "zones": { "<zoneId>": <listIndex> } }
//
// Zones sharing a terrain bake produce identical wall sets — they share
// one list. The client builds the exact same set in
// terrain_heightfield_build, so server and client always agree on what
// blocks.
//
// Run from src/client:  odin build tools\wall_export.odin -file -o wall_export.exe
//                       .\wall_export.exe <out.json>

import "core:fmt"
import "core:os"
import "core:strings"
import sys "../systems"
import rl "vendor:raylib"

write_str :: proc(f: ^os.File, s: string) {
	os.write(f, transmute([]u8)s)
}

Seg_List :: struct {
	segs: []sys.Wall_Seg,
}

// Cheap list fingerprint: length + three sampled segments. Identical zone
// builds (same terrain, same walls) collide with certainty; different
// builds colliding is practically impossible.
fingerprint :: proc(segs: []sys.Wall_Seg) -> string {
	if len(segs) == 0 do return ""
	s := segs[len(segs) / 2]
	e := segs[len(segs) - 1]
	return fmt.aprintf(
		"%d|%.2f,%.2f,%.2f,%.2f|%.2f,%.2f,%.2f,%.2f",
		len(segs),
		segs[0].x1, segs[0].z1, segs[0].y_min, segs[0].y_max,
		s.x2, s.z2, e.y_min, e.y_max,
	)
}

main :: proc() {
	rl.SetTraceLogLevel(.WARNING)
	rl.SetConfigFlags({rl.ConfigFlag.WINDOW_HIDDEN})
	rl.InitWindow(320, 240, "wall export")
	defer rl.CloseWindow()

	out_path := "../server/data/zone_walls.json"
	if len(os.args) > 1 do out_path = os.args[1]

	infos, err := os.read_all_directory_by_path("assets/maps", context.allocator)
	if err != nil {
		fmt.eprintfln("cannot list assets/maps: %v", err)
		return
	}

	lists: [dynamic]Seg_List
	defer {
		for l in lists do delete(l.segs)
		delete(lists)
	}
	list_keys := map[string]int{}
	defer delete(list_keys)
	zone_map := map[string]int{}

	total_segs := 0
	for info in infos {
		if info.type != .Regular do continue
		if !strings.has_suffix(info.name, ".json") do continue
		zone_id := info.name[:len(info.name) - 5]
		zone := sys.load_zone_map(zone_id)
		if zone == nil || zone.heightfield == nil || len(zone.heightfield.segs) == 0 {
			if zone != nil do sys.zone_destroy(zone)
			continue
		}
		segs := zone.heightfield.segs
		key := fingerprint(segs)
		idx, ok := list_keys[key]
		if !ok {
			clone := make([]sys.Wall_Seg, len(segs))
			copy(clone, segs)
			append(&lists, Seg_List{clone})
			idx = len(lists) - 1
			list_keys[key] = idx
			total_segs += len(segs)
			moves := 0
			for seg in segs {
				if seg.move do moves += 1
			}
			fmt.eprintfln("list #%d %-10s segs=%-7d move=%d", idx, zone_id, len(segs), moves)
		}
		zone_map[zone_id] = idx
		sys.zone_destroy(zone)
	}

	f, cerr := os.create(out_path)
	if cerr != nil {
		fmt.eprintfln("cannot create %s: %v", out_path, cerr)
		return
	}
	write_str(f, "{\"lists\":[")
	for l, li in lists {
		if li > 0 do write_str(f, ",")
		write_str(f, "[")
		for seg, i in l.segs {
			if i > 0 do write_str(f, ",")
			write_str(f, fmt.aprintf(
				"[%.1f,%.1f,%.1f,%.1f,%.1f,%.1f,%d]",
				seg.x1, seg.z1, seg.x2, seg.z2, seg.y_min, seg.y_max,
				seg.move ? 1 : 0,
			))
		}
		write_str(f, "]")
	}
	write_str(f, "],\"zones\":{")
	first := true
	for zone_id, idx in zone_map {
		if !first do write_str(f, ",")
		first = false
		write_str(f, fmt.aprintf("\"%s\":%d", zone_id, idx))
	}
	write_str(f, "}}\n")
	os.close(f)
	fmt.eprintfln(
		"DONE %d zones -> %d unique lists, %d segments -> %s",
		len(zone_map), len(lists), total_segs, out_path)
}
