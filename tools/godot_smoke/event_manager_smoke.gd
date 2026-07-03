extends SceneTree

const EVENT_MANAGER_SCRIPT := preload("res://scripts/autoload/event_manager.gd")
const SCRIPT_PATH := "res://data/generated/scripts/littleroot_town.json"


func _init() -> void:
	var script_data := _load_json_object(SCRIPT_PATH)
	var manager = EVENT_MANAGER_SCRIPT.new()
	manager.configure_from_script_data(script_data)

	var twin_preview := manager.get_script_preview("LittlerootTown_EventScript_Twin")
	var sign_preview := manager.get_script_preview("LittlerootTown_EventScript_TownSign")
	var empty_preview := manager.get_script_preview("0x0")

	_assert(twin_preview.get("status", "") == "ok", "expected Twin script preview")
	_assert(
		twin_preview.get("text_label", "") == "LittlerootTown_Text_IfYouGoInGrassPokemonWillJumpOut",
		"unexpected Twin text label"
	)
	_assert(not String(twin_preview.get("text", "")).is_empty(), "expected Twin preview text")
	_assert(sign_preview.get("status", "") == "ok", "expected town sign script preview")
	_assert(
		sign_preview.get("text_label", "") == "LittlerootTown_Text_TownSign",
		"unexpected town sign text label"
	)
	_assert(not String(sign_preview.get("text", "")).is_empty(), "expected town sign preview text")
	_assert(empty_preview.is_empty(), "expected empty script preview for 0x0")

	print(JSON.stringify({
		"event_manager_smoke": "ok",
		"twin": _preview_summary(twin_preview),
		"town_sign": _preview_summary(sign_preview),
	}))
	manager.free()
	quit(0)


func _load_json_object(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Could not open %s" % path)
		quit(1)
		return {}

	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("%s is not a JSON object" % path)
		quit(1)
		return {}

	return parsed


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	quit(1)


func _preview_summary(preview: Dictionary) -> Dictionary:
	return {
		"script_label": String(preview.get("script_label", "")),
		"text_label": String(preview.get("text_label", "")),
		"mode": String(preview.get("mode", "")),
		"text_length": String(preview.get("text", "")).length(),
	}
