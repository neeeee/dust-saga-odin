package systems

import "core:strings"
import rl "vendor:raylib"

// raylib's DrawText / MeasureText want cstring; these wrappers accept Odin
// strings (cloned to a NUL-terminated cstring on the temp allocator) so the
// gameplay and UI code can pass fmt.tprintf results and string literals
// directly without manual conversion at every call site.

draw_text :: proc(text: string, x, y: int, size: int, color: rl.Color) {
	c := strings.clone_to_cstring(text, context.temp_allocator)
	rl.DrawText(c, i32(x), i32(y), i32(size), color)
}

measure_text :: proc(text: string, size: int) -> int {
	c := strings.clone_to_cstring(text, context.temp_allocator)
	return int(rl.MeasureText(c, i32(size)))
}
