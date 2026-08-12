package systems

import "core:math"
import rl "vendor:raylib"

COLLISION_CELL_SIZE :: f32(1.0)

// ── collision grid build ──────────────────────────────────────────────────

build_collision_grid :: proc(zone: ^Zone_Definition) {
	if zone == nil do return
	size := zone.ground.size
	if size <= 0 do return

	cols := int(math.ceil(size / COLLISION_CELL_SIZE))
	rows := cols
	total := cols * rows

	delete(zone.collision_grid)
	resize(&zone.collision_grid, total)
	for i in 0 ..< total do zone.collision_grid[i] = false

	zone.collision_cols = cols
	zone.collision_rows = rows
	zone.collision_cell_size = COLLISION_CELL_SIZE
	zone.collision_origin_x = -size / 2.0
	zone.collision_origin_z = -size / 2.0

	ox := zone.collision_origin_x
	oz := zone.collision_origin_z
	cs := COLLISION_CELL_SIZE
	half := cs * 0.5

	margin := 1
	for r in 0 ..< margin {
		for c in 0 ..< cols {
			zone.collision_grid[r * cols + c] = true
			zone.collision_grid[(rows - 1 - r) * cols + c] = true
		}
	}
	for c in 0 ..< margin {
		for r in 0 ..< rows {
			zone.collision_grid[r * cols + c] = true
			zone.collision_grid[r * cols + (cols - 1 - c)] = true
		}
	}

	for &s in zone.structures {
		hw := s.size_w * 0.5 + half
		hd := s.size_d * 0.5 + half
		min_c := max(0, int(math.floor_f32((s.position.x - hw - ox) / cs)))
		max_c := min(cols - 1, int(math.floor_f32((s.position.x + hw - ox) / cs)))
		min_r := max(0, int(math.floor_f32((s.position.z - hd - oz) / cs)))
		max_r := min(rows - 1, int(math.floor_f32((s.position.z + hd - oz) / cs)))
		for r := min_r; r <= max_r; r += 1 {
			for c := min_c; c <= max_c; c += 1 {
				zone.collision_grid[r * cols + c] = true
			}
		}
	}

	for &o in zone.objects {
		if o.otype == "bush" do continue
		radius: f32 = 0.4
		if o.otype == "tree" do radius = 0.5
		if o.otype == "rock" do radius = 0.35
		radius *= o.scale
		radius += half

		ccx := (o.position.x - ox) / cs
		ccz := (o.position.z - oz) / cs
		cr := int(math.ceil(radius / cs))

		for dr := -cr; dr <= cr; dr += 1 {
			for dc := -cr; dc <= cr; dc += 1 {
				c := int(ccx) + dc
				r := int(ccz) + dr
				if c < 0 || c >= cols || r < 0 || r >= rows do continue
				cx := ox + (f32(c) + 0.5) * cs
				cz := oz + (f32(r) + 0.5) * cs
				dx := cx - o.position.x
				dz := cz - o.position.z
				if dx*dx + dz*dz <= radius*radius {
					zone.collision_grid[r * cols + c] = true
				}
			}
		}
	}
}

// ── coordinate helpers ────────────────────────────────────────────────────

world_to_grid :: proc(wx, wz: f32, zone: ^Zone_Definition) -> (int, int) {
	col := int(math.floor_f32((wx - zone.collision_origin_x) / zone.collision_cell_size))
	row := int(math.floor_f32((wz - zone.collision_origin_z) / zone.collision_cell_size))
	col = max(0, min(col, zone.collision_cols - 1))
	row = max(0, min(row, zone.collision_rows - 1))
	return col, row
}

grid_to_world :: proc(col, row: int, zone: ^Zone_Definition) -> rl.Vector3 {
	return {
		zone.collision_origin_x + (f32(col) + 0.5) * zone.collision_cell_size,
		0,
		zone.collision_origin_z + (f32(row) + 0.5) * zone.collision_cell_size,
	}
}

is_blocked :: proc(col, row: int, zone: ^Zone_Definition) -> bool {
	if col < 0 || col >= zone.collision_cols do return true
	if row < 0 || row >= zone.collision_rows do return true
	return zone.collision_grid[row * zone.collision_cols + col]
}

// ── A* pathfinding ───────────────────────────────────────────────────────
//
// Scratch (g / par / closed + the open-set binary heap) lives in a persistent
// module-level Pathfinder so click-to-move does NO heap allocation after the
// first zone-sized growth — the original allocated ~4 × cols×rows cells every
// click. The open set is a binary min-heap keyed on f = g + h with lazy
// duplicate-push deletion (stale pops are skipped via the closed flag),
// replacing the O(n²) linear scan.

PF_INF :: f32(1e15)

PF_Heap_Entry :: struct {
	f:    f32,
	node: int,
}

Pathfinder :: struct {
	capacity: int,
	g:        [dynamic]f32,
	par:      [dynamic]int,
	closed:   [dynamic]bool,
	heap:     [dynamic]PF_Heap_Entry,
}

pathfinder: Pathfinder

// Ensure scratch arrays are at least `total` cells, then reset the first
// `total` cells. Grows only when a larger zone is loaded; no per-call alloc.
pathfinder_reset :: proc(total: int) {
	if total > pathfinder.capacity {
		resize(&pathfinder.g, total)
		resize(&pathfinder.par, total)
		resize(&pathfinder.closed, total)
		pathfinder.capacity = total
	}
	for i in 0 ..< total {
		pathfinder.g[i] = PF_INF
		pathfinder.par[i] = -1
		pathfinder.closed[i] = false
	}
	clear(&pathfinder.heap)
}

pf_heap_push :: proc(e: PF_Heap_Entry) {
	append(&pathfinder.heap, e)
	i := len(pathfinder.heap) - 1
	for i > 0 {
		parent := (i - 1) / 2
		if pathfinder.heap[parent].f <= pathfinder.heap[i].f do break
		pathfinder.heap[parent], pathfinder.heap[i] = pathfinder.heap[i], pathfinder.heap[parent]
		i = parent
	}
}

// Pop the lowest-f entry. Returns false when the heap is empty.
pf_heap_pop_min :: proc() -> (PF_Heap_Entry, bool) {
	if len(pathfinder.heap) == 0 do return {}, false
	top := pathfinder.heap[0]
	last := pathfinder.heap[len(pathfinder.heap) - 1]
	resize(&pathfinder.heap, len(pathfinder.heap) - 1)
	n := len(pathfinder.heap)
	if n > 0 {
		pathfinder.heap[0] = last
		i := 0
		for {
			l := 2 * i + 1
			r := 2 * i + 2
			best := i
			if l < n && pathfinder.heap[l].f < pathfinder.heap[best].f do best = l
			if r < n && pathfinder.heap[r].f < pathfinder.heap[best].f do best = r
			if best == i do break
			pathfinder.heap[best], pathfinder.heap[i] = pathfinder.heap[i], pathfinder.heap[best]
			i = best
		}
	}
	return top, true
}

octile :: proc "contextless" (c1, r1, c2, r2: int) -> f32 {
	dx := abs(c2 - c1)
	dy := abs(r2 - r1)
	small := min(dx, dy)
	big := max(dx, dy)
	return f32(big) + 0.414 * f32(small)
}

astar :: proc(zone: ^Zone_Definition, sc, sr, ec, er: int) -> [dynamic][2]int {
	path: [dynamic][2]int

	cols := zone.collision_cols
	rows := zone.collision_rows
	total := cols * rows
	if total <= 0 do return path
	if is_blocked(sc, sr, zone) do return path
	if is_blocked(ec, er, zone) do return path

	start_idx := sr * cols + sc
	end_idx := er * cols + ec

	pathfinder_reset(total)
	pathfinder.g[start_idx] = 0
	pf_heap_push({f = octile(sc, sr, ec, er), node = start_idx})

	dirs := [8][2]int{
		{0, -1}, {0, 1}, {-1, 0}, {1, 0},
		{-1, -1}, {-1, 1}, {1, -1}, {1, 1},
	}
	costs := [8]f32{1, 1, 1, 1, 1.414, 1.414, 1.414, 1.414}

	for {
		entry, ok := pf_heap_pop_min()
		if !ok do break
		cur := entry.node
		// Lazy deletion: a node may have several stale entries in the heap;
		// the lowest-f one is popped first and marks the node closed, so any
		// later (higher-f) duplicate is skipped here.
		if pathfinder.closed[cur] do continue

		if cur == end_idx {
			raw: [dynamic]int
			defer delete(raw)
			idx := cur
			for idx != start_idx {
				append(&raw, idx)
				p := pathfinder.par[idx]
				if p < 0 do break
				idx = p
			}
			append(&raw, start_idx)

			for i := len(raw) - 1; i >= 0; i -= 1 {
				pi := raw[i]
				append(&path, [2]int{pi % cols, pi / cols})
			}
			return path
		}

		pathfinder.closed[cur] = true
		cc := cur % cols
		cr_idx := cur / cols

		for d in 0 ..< 8 {
			nc := cc + dirs[d][0]
			nr := cr_idx + dirs[d][1]
			if nc < 0 || nc >= cols || nr < 0 || nr >= rows do continue
			nidx := nr * cols + nc
			if pathfinder.closed[nidx] do continue
			if zone.collision_grid[nidx] do continue
			if dirs[d][0] != 0 && dirs[d][1] != 0 {
				if zone.collision_grid[cr_idx * cols + nc] do continue
				if zone.collision_grid[nr * cols + cc] do continue
			}
			new_g := pathfinder.g[cur] + costs[d]
			if new_g < pathfinder.g[nidx] {
				pathfinder.g[nidx] = new_g
				pathfinder.par[nidx] = cur
				pf_heap_push({f = new_g + octile(nc, nr, ec, er), node = nidx})
			}
		}
	}

	return path
}

// ── path smoothing (line-of-sight shortcutting) ────────────────────────────

smooth_path :: proc(zone: ^Zone_Definition, in_path: [dynamic][2]int) -> [dynamic][2]int {
	if len(in_path) <= 2 do return in_path

	result: [dynamic][2]int
	append(&result, in_path[0])
	current := 0
	i := len(in_path) - 1
	for current < i {
		if line_of_sight(zone, result[len(result)-1], in_path[i]) {
			append(&result, in_path[i])
			current = i
		} else {
			i -= 1
		}
	}
	if len(result) > 0 && result[len(result)-1] != in_path[len(in_path)-1] {
		append(&result, in_path[len(in_path)-1])
	}
	return result
}

line_of_sight :: proc(zone: ^Zone_Definition, a, b: [2]int) -> bool {
	x0: int = a[0]
	y0: int = a[1]
	x1: int = b[0]
	y1: int = b[1]
	dx := abs(x1 - x0)
	dy := abs(y1 - y0)
	sx: int = 1 if x0 < x1 else -1
	sy: int = 1 if y0 < y1 else -1
	err := dx - dy

	for {
		if is_blocked(x0, y0, zone) do return false
		if x0 == x1 && y0 == y1 do return true
		e2 := 2 * err
		if e2 > -dy {
			err -= dy
			x0 += sx
		}
		if e2 < dx {
			err += dx
			y0 += sy
		}
	}
}

// ── ray-ground intersection ───────────────────────────────────────────────

ray_ground_hit :: proc(ray: rl.Ray, ground_y: f32) -> (hit: bool, point: rl.Vector3) {
	if ray.direction.y >= -0.001 do return false, {}
	t := (ground_y - ray.position.y) / ray.direction.y
	if t < 0 do return false, {}
	return true, {
		ray.position.x + ray.direction.x * t,
		ground_y,
		ray.position.z + ray.direction.z * t,
	}
}

// ── high-level: compute world-space move path ────────────────────────────

compute_move_path :: proc(
	zone: ^Zone_Definition,
	start: rl.Vector3,
	goal: rl.Vector3,
) -> [dynamic]rl.Vector3 {
	path: [dynamic]rl.Vector3

	if zone == nil || len(zone.collision_grid) == 0 {
		append(&path, goal)
		return path
	}

	sc, sr := world_to_grid(start.x, start.z, zone)
	ec, er := world_to_grid(goal.x, goal.z, zone)

	raw := astar(zone, sc, sr, ec, er)
	defer delete(raw)
	if len(raw) == 0 {
		append(&path, goal)
		return path
	}

	smoothed := smooth_path(zone, raw)
	defer delete(smoothed)

	for p in smoothed {
		append(&path, grid_to_world(p[0], p[1], zone))
	}
	if len(path) > 0 {
		path[len(path) - 1] = {goal.x, 0, goal.z}
	}
	return path
}
