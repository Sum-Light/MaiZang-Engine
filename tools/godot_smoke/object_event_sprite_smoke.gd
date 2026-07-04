extends Node

const OBJECT_EVENT_PLACEHOLDER := preload("res://scripts/overworld/object_event_placeholder.gd")

var _failed := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var record: Dictionary = DataRegistry.get_object_event_sprite_record("OBJ_EVENT_GFX_BOY_1")
	_assert(not record.is_empty(), "expected Boy1 object event sprite record")
	_assert(int(record.get("columns", 0)) == 9, "expected Boy1 nine source frames")
	_assert(_frame_for_direction(record, "down") == 0, "expected source south frame 0")
	_assert(_frame_for_direction(record, "up") == 1, "expected source north frame 1")
	_assert(_frame_for_direction(record, "left") == 2, "expected source west frame 2")
	_assert(_frame_for_direction(record, "right") == 2, "expected source east frame 2")
	_assert(_flip_for_direction(record, "right"), "expected source east frame hFlip")
	_assert(not _flip_for_direction(record, "left"), "expected source west frame unflipped")

	var animation_table := _dict_field(record, "animation_table")
	_assert(String(animation_table.get("source_symbol", "")) == "sAnimTable_Standard", "expected standard animation table")
	var walk_table := _dict_field(animation_table, "walk")
	_assert(_frames(walk_table.get("down", [])) == [3, 0, 4, 0], "expected source south walk cycle")
	_assert(_frames(walk_table.get("up", [])) == [5, 1, 6, 1], "expected source north walk cycle")
	_assert(_frames(walk_table.get("left", [])) == [7, 2, 8, 2], "expected source west walk cycle")
	_assert(_frames(walk_table.get("right", [])) == [7, 2, 8, 2], "expected source east walk cycle")
	_assert(_all_h_flipped(walk_table.get("right", [])), "expected source east walk cycle hFlip")

	var placeholder = OBJECT_EVENT_PLACEHOLDER.new()
	get_tree().root.add_child(placeholder)
	placeholder.configure({
		"graphics_id": "OBJ_EVENT_GFX_BOY_1",
		"position": Vector2i.ZERO,
		"facing_direction": "right",
	}, 16)
	await get_tree().process_frame
	var right_snapshot: Dictionary = placeholder.get_sprite_snapshot()
	_assert(bool(right_snapshot.get("using_sprite", false)), "expected placeholder to use generated Boy1 sprite")
	_assert(_array_field(right_snapshot, "source_rect") == [32, 0, 16, 32], "expected east static source rect")
	_assert(bool(right_snapshot.get("h_flip", false)), "expected east static frame hFlip")

	placeholder.configure({
		"graphics_id": "OBJ_EVENT_GFX_BOY_1",
		"position": Vector2i.ZERO,
		"facing_direction": "up",
	}, 16)
	await get_tree().process_frame
	var up_snapshot: Dictionary = placeholder.get_sprite_snapshot()
	_assert(_array_field(up_snapshot, "source_rect") == [16, 0, 16, 32], "expected north static source rect")
	_assert(not bool(up_snapshot.get("h_flip", false)), "expected north static frame unflipped")

	placeholder.queue_free()

	if _failed:
		return

	print(JSON.stringify({
		"object_event_sprite_smoke": "ok",
		"right_source_rect": right_snapshot.get("source_rect", []),
		"right_h_flip": right_snapshot.get("h_flip", false),
	}))
	get_tree().quit(0)


func _frame_for_direction(record: Dictionary, direction: String) -> int:
	var static_frames := _dict_field(record, "static_frames")
	return int(static_frames.get(direction, -1))


func _flip_for_direction(record: Dictionary, direction: String) -> bool:
	var static_frame_flips := _dict_field(record, "static_frame_flips")
	var flip_info = static_frame_flips.get(direction, {})
	if typeof(flip_info) != TYPE_DICTIONARY:
		return false
	return bool(flip_info.get("h", false))


func _frames(value) -> Array:
	var result := []
	if typeof(value) != TYPE_ARRAY:
		return result
	for entry in value:
		if typeof(entry) == TYPE_DICTIONARY:
			result.append(int(entry.get("frame", -1)))
	return result


func _all_h_flipped(value) -> bool:
	if typeof(value) != TYPE_ARRAY or value.is_empty():
		return false
	for entry in value:
		if typeof(entry) != TYPE_DICTIONARY or not bool(entry.get("h_flip", false)):
			return false
	return true


func _dict_field(record: Dictionary, key: String) -> Dictionary:
	var value = record.get(key, {})
	return value if typeof(value) == TYPE_DICTIONARY else {}


func _array_field(record: Dictionary, key: String) -> Array:
	var value = record.get(key, [])
	return value if typeof(value) == TYPE_ARRAY else []


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)
	get_tree().quit(1)
