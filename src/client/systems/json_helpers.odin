package systems

import "core:encoding/json"
import "core:math"

// Thin convenience layer over core:encoding/json. The server's `data` payloads
// are polymorphic (e.g. PLAYER_POSITION_UPDATE has a batched-entities form and a
// single-player form; COOLDOWN_UPDATE is discriminated by a `type` string), so
// rather than generate a struct per variant we parse into json.Value and pull
// fields out with these helpers.
//
// Notes on Odin's json types:
//   - JSON_Object is `distinct map[string]Value`   — a map is a reference handle,
//     so passing it by value is cheap and shares storage.
//   - JSON_Array  is `distinct [dynamic]Value`      — same idea (dynamic is a handle).
// We therefore return objects/arrays *by value* and index them directly, which
// sidesteps the "address of map element" problem entirely.

JSON_Value :: json.Value
JSON_Object :: json.Object // distinct map[string]Value
JSON_Array :: json.Array // distinct [dynamic]Value
JSON_String :: json.String

// A zero/absent object — an empty map distinct value. Useful as a nil-safe
// default so callers can chain get_* without null checks.
EMPTY_OBJECT :: JSON_Object{}

// A JSON null value (json.Null wraps a rawptr sentinel).
json_null_value :: proc "contextless" () -> JSON_Value {
	return json.Null(nil)
}

// ---- parse / serialize --------------------------------------------------

json_parse :: proc(data: []byte, allocator := context.allocator) -> (JSON_Value, bool) {
	value, err := json.parse(data, allocator = allocator)
	if err != .None {
		return nil, false
	}
	return value, true
}

json_marshal :: proc(v: ^JSON_Value, allocator := context.allocator) -> (string, bool) {
	out, err := json.unparse(v^, allocator = allocator)
	if err != nil {
		return "", false
	}
	return out, true
}

// ---- typed extractors ---------------------------------------------------
//
// These take a json.Value by value and pull out the payload. is_null checks
// let callers detect absent fields cheaply.

is_null :: proc(v: JSON_Value) -> bool {
	if v == nil do return true
	#partial switch e in v {
	case json.Null:
		return true
	case:
		return false
	}
}

obj_of :: proc(v: JSON_Value) -> JSON_Object {
	#partial switch o in v {
	case json.Object:
		return o
	case:
		return EMPTY_OBJECT
	}
}

array_of :: proc(v: JSON_Value) -> JSON_Array {
	#partial switch a in v {
	case json.Array:
		return a
	case:
		return JSON_Array(nil)
	}
}

string_of :: proc(v: JSON_Value) -> string {
	#partial switch s in v {
	case json.String:
		return s
	case:
		return ""
	}
}

number_of :: proc(v: JSON_Value) -> f64 {
	#partial switch e in v {
	case json.Float:
		return f64(e)
	case json.Integer:
		return f64(e)
	case:
		return 0
	}
}

int_of :: proc(v: JSON_Value) -> int {return int(number_of(v))}

bool_of :: proc(v: JSON_Value) -> bool {
	#partial switch b in v {
	case json.Boolean:
		return b
	case:
		return false
	}
}

// ---- field lookup -------------------------------------------------------

// The underlying map for a JSON_Object. (JSON_Object is distinct map[string]Value.)
as_map :: proc "contextless" (o: JSON_Object) -> map[string]JSON_Value {
	return transmute(map[string]JSON_Value)(o)
}

// The underlying dynamic array for a JSON_Array.
as_dyn :: proc "contextless" (a: JSON_Array) -> [dynamic]JSON_Value {
	return transmute([dynamic]JSON_Value)(a)
}

as_string :: proc(s: JSON_String) -> string {
	return cast(string)s
}

field :: proc(o: JSON_Object, key: string) -> JSON_Value {
	m := as_map(o)
	if v, ok := m[key]; ok do return v
	return json.Null(nil)
}

has_field :: proc(o: JSON_Object, key: string) -> bool {
	_, ok := as_map(o)[key]
	return ok
}

// ---- typed field getters (with fallback defaults) -----------------------

get_string :: proc(obj: json.Object, key: string, default: string = "") -> string {
	val, ok := obj[key]
	if !ok {
		// Clone default to heap
		if len(default) == 0 do return "" // Empty string as literal
		cloned := make([]u8, len(default))
		copy(cloned, default)
		return string(cloned)
	}

	if s, ok := val.(json.String); ok {
		str := string(s)
		// Clone the string to heap
		if len(str) == 0 do return ""
		cloned := make([]u8, len(str))
		copy(cloned, str)
		return string(cloned)
	}

	// Fallback: clone default
	if len(default) == 0 do return ""
	cloned := make([]u8, len(default))
	copy(cloned, default)
	return string(cloned)
}

get_f64 :: proc(o: JSON_Object, key: string, default := 0.0) -> f64 {
	v := field(o, key)
	if is_null(v) do return default
	return number_of(v)
}

get_f32 :: proc(o: JSON_Object, key: string, default: f32 = 0.0) -> f32 {
	return f32(get_f64(o, key, f64(default)))
}

get_int :: proc(o: JSON_Object, key: string, default := 0) -> int {
	v := field(o, key)
	if is_null(v) do return default
	return int_of(v)
}

get_bool :: proc(o: JSON_Object, key: string, default := false) -> bool {
	v := field(o, key)
	if is_null(v) do return default
	return bool_of(v)
}

get_object :: proc(o: JSON_Object, key: string) -> JSON_Object {
	v := field(o, key)
	if is_null(v) do return EMPTY_OBJECT
	return obj_of(v)
}

get_array :: proc(o: JSON_Object, key: string) -> JSON_Array {
	v := field(o, key)
	return array_of(v)
}

// ---- vec3 / vec4 helpers ------------------------------------------------

Vec3 :: [3]f32
// Quaternion (x, y, z, w) as the server sends it.
Quat :: [4]f32

vec3_from :: proc(o: JSON_Object, key: string) -> Vec3 {
	sub := get_object(o, key)
	return {get_f32(sub, "x"), get_f32(sub, "y"), get_f32(sub, "z")}
}

quat_from :: proc(o: JSON_Object, key: string) -> Quat {
	sub := get_object(o, key)
	return {get_f32(sub, "x"), get_f32(sub, "y"), get_f32(sub, "z"), get_f32(sub, "w")}
}

// Recover the player-facing yaw (radians) from the server's quaternion. The TS
// client builds rotation from atan2(dir.x, dir.z); this yields the same angle.
quat_to_yaw :: proc(q: Quat) -> f32 {
	wy := 2.0 * (q[3] * q[1] + q[0] * q[2])
	yy_xx := 1.0 - 2.0 * (q[1] * q[1] + q[0] * q[0])
	return math.atan2(wy, yy_xx)
}
