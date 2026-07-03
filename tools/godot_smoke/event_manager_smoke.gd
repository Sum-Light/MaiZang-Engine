extends SceneTree

const EVENT_MANAGER_SCRIPT := preload("res://scripts/autoload/event_manager.gd")
const SCRIPT_VM_SCRIPT := preload("res://scripts/autoload/script_vm.gd")
const MAP_RUNTIME_SCRIPT := preload("res://scripts/autoload/map_runtime.gd")
const GAME_STATE_SCRIPT := preload("res://scripts/autoload/game_state.gd")
const SCRIPT_PATH := "res://data/generated/scripts/littleroot_town.json"
const MAP_PATH := "res://data/generated/maps/littleroot_town.json"
const TILESET_PATH := "res://data/generated/tilesets/littleroot_town.json"


func _init() -> void:
	var script_data := _load_json_object(SCRIPT_PATH)
	var map_data := _load_json_object(MAP_PATH)
	var tileset_data := _load_json_object(TILESET_PATH)
	var vm = SCRIPT_VM_SCRIPT.new()
	vm.configure_from_script_data(script_data)
	var runtime = MAP_RUNTIME_SCRIPT.new()
	runtime.configure_from_data(map_data, tileset_data, _map_size_from_data(map_data))
	var game_state = GAME_STATE_SCRIPT.new()
	var manager = EVENT_MANAGER_SCRIPT.new()
	manager.configure_from_script_data(script_data)
	manager.configure_script_vm(vm)
	manager.configure_map_runtime(runtime)
	manager.configure_game_state(game_state)

	var twin_preview := manager.get_script_preview("LittlerootTown_EventScript_Twin")
	var sign_preview := manager.get_script_preview("LittlerootTown_EventScript_TownSign")
	var need_pokemon_preview := manager.get_script_preview("LittlerootTown_EventScript_NeedPokemonTriggerLeft")
	var empty_preview := manager.get_script_preview("0x0")
	_assert(game_state.player_grid_position == Vector2i(10, 10), "expected preview to leave player position unchanged")
	_assert(
		_event_position(runtime.get_object_event_by_local_id("LOCALID_LITTLEROOT_TWIN", true)) == Vector2i(16, 10),
		"expected preview to leave twin position unchanged"
	)
	var captured := {}
	manager.debug_message_requested.connect(func(lines: PackedStringArray) -> void:
		captured["lines"] = lines
	)
	manager.dispatch_interaction({
		"type": "object_event",
		"script": "LittlerootTown_EventScript_Twin",
		"position": Vector2i(16, 10),
		"event": {
			"graphics_id": "OBJ_EVENT_GFX_TWIN",
			"script": "LittlerootTown_EventScript_Twin",
		},
	})
	manager.dispatch_interaction({
		"type": "object_event",
		"script": "LittlerootTown_EventScript_NeedPokemonTriggerLeft",
		"position": Vector2i(16, 10),
		"event": {
			"graphics_id": "OBJ_EVENT_GFX_TWIN",
			"script": "LittlerootTown_EventScript_NeedPokemonTriggerLeft",
		},
	})

	_assert(twin_preview.get("status", "") == "ok", "expected Twin script preview")
	_assert(twin_preview.get("vm_status", "") == "ok", "expected Twin VM status")
	_assert(
		twin_preview.get("text_label", "") == "LittlerootTown_Text_IfYouGoInGrassPokemonWillJumpOut",
		"unexpected Twin text label"
	)
	_assert(not String(twin_preview.get("text", "")).is_empty(), "expected Twin preview text")
	_assert(sign_preview.get("status", "") == "ok", "expected town sign script preview")
	_assert(sign_preview.get("vm_status", "") == "ok", "expected town sign VM status")
	_assert(
		sign_preview.get("text_label", "") == "LittlerootTown_Text_TownSign",
		"unexpected town sign text label"
	)
	_assert(not String(sign_preview.get("text", "")).is_empty(), "expected town sign preview text")
	_assert(need_pokemon_preview.get("status", "") == "ok", "expected need-pokemon script preview")
	_assert(
		need_pokemon_preview.get("text_label", "") == "LittlerootTown_Text_IfYouGoInGrassPokemonWillJumpOut",
		"unexpected need-pokemon preview text label"
	)
	_assert(game_state.player_grid_position == Vector2i(10, 11), "expected dispatch to apply player movement")
	_assert(
		_event_position(runtime.get_object_event_by_local_id("LOCALID_LITTLEROOT_TWIN", true)) == Vector2i(16, 10),
		"expected dispatch to return twin to original cell"
	)
	_assert(empty_preview.is_empty(), "expected empty script preview for 0x0")
	_assert(captured.has("lines"), "expected dispatch to emit dialogue lines")
	_assert(_lines_contain(captured["lines"], "ScriptVM: ok"), "expected VM status in emitted lines")
	_assert(
		_lines_contain(captured["lines"], "Movement effects: 4 applied, 0 skipped"),
		"expected movement effect summary in emitted lines"
	)

	print(JSON.stringify({
		"event_manager_smoke": "ok",
		"twin": _preview_summary(twin_preview),
		"town_sign": _preview_summary(sign_preview),
		"need_pokemon": _preview_summary(need_pokemon_preview),
		"player_position_after_dispatch": _vector_to_array(game_state.player_grid_position),
	}))
	manager.free()
	game_state.free()
	runtime.free()
	vm.free()
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
		"vm_status": String(preview.get("vm_status", "")),
		"text_length": String(preview.get("text", "")).length(),
	}


func _lines_contain(lines: PackedStringArray, needle: String) -> bool:
	for line in lines:
		if line == needle:
			return true
	return false


func _map_size_from_data(map_data: Dictionary) -> Vector2i:
	var layout_info = map_data.get("layout", {})
	if typeof(layout_info) != TYPE_DICTIONARY:
		return Vector2i.ZERO
	return Vector2i(
		int(layout_info.get("width", 0)),
		int(layout_info.get("height", 0))
	)


func _event_position(object_event: Dictionary) -> Vector2i:
	var position = object_event.get("position", Vector2i.ZERO)
	if typeof(position) == TYPE_VECTOR2I:
		return position
	return Vector2i(
		int(object_event.get("x", 0)),
		int(object_event.get("y", 0))
	)


func _vector_to_array(value: Vector2i) -> Array:
	return [value.x, value.y]
