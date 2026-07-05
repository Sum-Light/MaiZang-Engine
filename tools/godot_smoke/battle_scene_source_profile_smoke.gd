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
