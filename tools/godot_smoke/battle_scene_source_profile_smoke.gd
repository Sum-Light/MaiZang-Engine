extends SceneTree

const PROFILE_ROOT := "res://assets/source/battle_scene_captures/emerald_2011_zh"
const PROFILE_COUNT := 24
const WINDOW_CAPTURE_ROOT := "res://assets/source/battle_window_captures"
const WINDOW_CAPTURE_NAMES := ["action.png", "message.png", "move.png"]
const KEY_PHASES := {
	0: "action_menu",
	1: "move_menu",
	2: "move_message",
	12: "grass_intro",
	16: "send_out_ball",
	23: "send_out_complete",
}
const EXPECTED_LAYOUT_RECTS := {
	"capture_00": {
		"opponent_hp_green_rect": [52, 33, 48, 2],
		"player_hp_green_rect": [174, 92, 48, 2],
		"action_prompt_red_frame_rect": [1, 115, 119, 42],
		"action_prompt_body_rect": [8, 117, 112, 38],
	},
	"capture_02": {
		"message_red_frame_rect": [1, 115, 238, 42],
		"message_body_rect": [8, 117, 224, 38],
	},
	"capture_23": {
		"opponent_hp_green_rect": [52, 33, 48, 2],
		"player_hp_green_rect": [179, 91, 48, 2],
	},
}
const HP_GREEN_COLOR_KEYS := ["90,214,132,255", "115,255,173,255"]
const RED_FRAME_COLOR_KEYS := ["214,74,57,255"]
const TEXTBOX_BODY_COLOR_KEYS := ["107,165,165,255"]
const EXPECTED_SIGNATURES := [
	"3695D0A6",
	"E49CB0A1",
	"16E12769",
	"7AC1C82B",
	"BD1DB8E3",
	"33DE68DC",
	"0D46786D",
	"4E61BEBD",
	"102EA5EA",
	"7BC616E8",
	"F6008FE4",
	"8C1D1F3C",
	"2F09DC69",
	"90A317F5",
	"80B86DFF",
	"3B2429D3",
	"9D8B53A7",
	"705C288A",
	"976E6F6E",
	"8B443E89",
	"E5D144D6",
	"4F60BC55",
	"9F749E64",
	"336A672A",
]

var _failed := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var rows := []
	var signatures := []
	var layout_rects := {}
	var nonblank_count := 0
	for index in range(PROFILE_COUNT):
		var path := "%s/capture_%02d.png" % [PROFILE_ROOT, index]
		_assert(FileAccess.file_exists(path), "expected full-scene source capture %s" % path)
		var image := Image.new()
		var load_error := image.load(path)
		_assert(load_error == OK, "expected source capture to load: %s" % path)
		_assert(image.get_width() == 240 and image.get_height() == 160, "expected 240x160 source capture %02d" % index)
		var signature := _image_signature(image)
		var nonblack_pixels := _nonblack_pixel_count(image)
		var bottom_pixels := _distinct_rgb_count(image, Rect2i(0, 112, 240, 48))
		_assert(signature == String(EXPECTED_SIGNATURES[index]), "expected stable source capture signature %02d" % index)
		_assert(nonblack_pixels > 1000, "expected nonblank source capture %02d" % index)
		_assert(bottom_pixels > 1, "expected non-flat bottom UI/source region %02d" % index)
		var layout_key := "capture_%02d" % index
		if EXPECTED_LAYOUT_RECTS.has(layout_key):
			var measured_layout := _measure_layout_rects(index, image)
			layout_rects[layout_key] = measured_layout
			for rect_key in _dictionary_value(EXPECTED_LAYOUT_RECTS.get(layout_key, {})).keys():
				_assert(
					_array_equals(_array_value(measured_layout.get(rect_key, [])), _array_value(EXPECTED_LAYOUT_RECTS[layout_key].get(rect_key, []))),
					"expected %s %s to match source profile" % [layout_key, rect_key]
				)
		rows.append({
			"index": index,
			"path": path,
			"signature": signature,
			"phase": String(KEY_PHASES.get(index, "sequence_frame")),
			"nonblack_pixels": nonblack_pixels,
			"bottom_distinct_rgb": bottom_pixels,
		})
		signatures.append(signature)
		nonblank_count += 1

	var window_missing := []
	for file_name in WINDOW_CAPTURE_NAMES:
		var window_path := "%s/%s" % [WINDOW_CAPTURE_ROOT, file_name]
		if not FileAccess.file_exists(window_path):
			window_missing.append(file_name)
	_assert(window_missing.size() == 3, "expected the 3 exact window-layer captures to remain separate and missing")

	if _failed:
		return
	print(JSON.stringify({
		"battle_scene_source_profile_smoke": "ok",
		"profile_root": PROFILE_ROOT,
		"profile_count": rows.size(),
		"nonblank_count": nonblank_count,
		"key_phase_count": KEY_PHASES.size(),
		"window_exact_capture_missing_count": window_missing.size(),
		"measured_layout_rects": layout_rects,
		"signatures": signatures,
		"key_rows": _key_rows(rows),
	}))
	quit(0)


func _key_rows(rows: Array) -> Array:
	var selected := []
	for row in rows:
		var index := int(row.get("index", -1))
		if KEY_PHASES.has(index):
			selected.append(row)
	return selected


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true
	quit(1)


func _image_signature(image: Image) -> String:
	var hash: int = 2166136261
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var color := image.get_pixel(x, y)
			hash = _fnv1a(hash, int(round(color.r * 255.0)))
			hash = _fnv1a(hash, int(round(color.g * 255.0)))
			hash = _fnv1a(hash, int(round(color.b * 255.0)))
			hash = _fnv1a(hash, int(round(color.a * 255.0)))
	return "%08X" % (hash & 0xFFFFFFFF)


func _fnv1a(hash: int, value: int) -> int:
	return int(((hash ^ (value & 0xFF)) * 16777619) & 0xFFFFFFFF)


func _nonblack_pixel_count(image: Image) -> int:
	var count := 0
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var color := image.get_pixel(x, y)
			if color.r > 0.01 or color.g > 0.01 or color.b > 0.01:
				count += 1
	return count


func _distinct_rgb_count(image: Image, rect: Rect2i) -> int:
	var values := {}
	for y in range(rect.position.y, rect.position.y + rect.size.y):
		for x in range(rect.position.x, rect.position.x + rect.size.x):
			if x < 0 or y < 0 or x >= image.get_width() or y >= image.get_height():
				continue
			var color := image.get_pixel(x, y)
			var key := "%02X%02X%02X" % [
				int(round(color.r * 255.0)),
				int(round(color.g * 255.0)),
				int(round(color.b * 255.0)),
			]
			values[key] = true
	return values.size()


func _measure_layout_rects(index: int, image: Image) -> Dictionary:
	match index:
		0:
			return {
				"opponent_hp_green_rect": _color_bbox(image, Rect2i(0, 0, 120, 60), HP_GREEN_COLOR_KEYS),
				"player_hp_green_rect": _color_bbox(image, Rect2i(120, 60, 120, 60), HP_GREEN_COLOR_KEYS),
				"action_prompt_red_frame_rect": _color_bbox(image, Rect2i(0, 112, 120, 48), RED_FRAME_COLOR_KEYS),
				"action_prompt_body_rect": _color_bbox(image, Rect2i(0, 112, 120, 48), TEXTBOX_BODY_COLOR_KEYS),
			}
		2:
			return {
				"message_red_frame_rect": _color_bbox(image, Rect2i(0, 112, 240, 48), RED_FRAME_COLOR_KEYS),
				"message_body_rect": _color_bbox(image, Rect2i(0, 112, 240, 48), TEXTBOX_BODY_COLOR_KEYS),
			}
		23:
			return {
				"opponent_hp_green_rect": _color_bbox(image, Rect2i(0, 0, 120, 60), HP_GREEN_COLOR_KEYS),
				"player_hp_green_rect": _color_bbox(image, Rect2i(120, 60, 120, 60), HP_GREEN_COLOR_KEYS),
			}
	return {}


func _color_bbox(image: Image, rect: Rect2i, color_keys: Array) -> Array:
	var found := false
	var min_x := image.get_width()
	var min_y := image.get_height()
	var max_x := -1
	var max_y := -1
	for y in range(rect.position.y, rect.position.y + rect.size.y):
		for x in range(rect.position.x, rect.position.x + rect.size.x):
			if x < 0 or y < 0 or x >= image.get_width() or y >= image.get_height():
				continue
			if not color_keys.has(_rgba_key(image.get_pixel(x, y))):
				continue
			found = true
			min_x = min(min_x, x)
			min_y = min(min_y, y)
			max_x = max(max_x, x)
			max_y = max(max_y, y)
	if not found:
		return []
	return [min_x, min_y, max_x - min_x + 1, max_y - min_y + 1]


func _rgba_key(color: Color) -> String:
	return "%d,%d,%d,%d" % [
		int(round(color.r * 255.0)),
		int(round(color.g * 255.0)),
		int(round(color.b * 255.0)),
		int(round(color.a * 255.0)),
	]


func _array_equals(left: Array, right: Array) -> bool:
	if left.size() != right.size():
		return false
	for index in range(left.size()):
		if left[index] != right[index]:
			return false
	return true


func _dictionary_value(value) -> Dictionary:
	return value if typeof(value) == TYPE_DICTIONARY else {}


func _array_value(value) -> Array:
	return value if typeof(value) == TYPE_ARRAY else []
