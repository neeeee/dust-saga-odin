package systems

import "core:math"

add_position_snapshot :: proc(buf: ^Interp_Buffer, x: f32, y: f32, z: f32, time: f64) {
	idx := (buf.head + buf.count) % len(buf.points)
	buf.points[idx] = {x, y, z, time}
	if buf.count < len(buf.points) {
		buf.count += 1
	} else {
		buf.head = (buf.head + 1) % len(buf.points) // Overwrite oldest
	}
}

get_interpolated_position :: proc(
	buf: ^Interp_Buffer,
	target_time: f64,
	interp_delay: f64,
) -> [3]f32 {
	if buf.count < 2 do return {}

	render_time := target_time - interp_delay

	prev: ^Interp_Point = &buf.points[buf.head]
	next: ^Interp_Point = &buf.points[(buf.head + 1) % len(buf.points)]

	// Find the two points surrounding render_time
	for i in 1 ..< buf.count {
		curr_idx := (buf.head + i) % len(buf.points)
		prev_idx := (buf.head + i - 1) % len(buf.points)
		next = &buf.points[curr_idx]
		prev = &buf.points[prev_idx]

		if next.time >= render_time do break
	}

	dt := next.time - prev.time
	if dt == 0 do return {prev.x, prev.y, prev.z}

	t_f64 := (render_time - prev.time) / dt
	t_f64 = math.clamp(t_f64, 0.0, 1.0)
	t := f32(t_f64)

	return {
		math.lerp(prev.x, next.x, t),
		math.lerp(prev.y, next.y, t),
		math.lerp(prev.z, next.z, t),
	}
}
