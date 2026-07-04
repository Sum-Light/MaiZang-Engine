extends SceneTree

const EVENT_MANAGER_SCRIPT := preload("res://scripts/autoload/event_manager.gd")
const SCRIPT_VM_SCRIPT := preload("res://scripts/autoload/script_vm.gd")
const MAP_RUNTIME_SCRIPT := preload("res://scripts/autoload/map_runtime.gd")
const GAME_STATE_SCRIPT := preload("res://scripts/autoload/game_state.gd")
const DATA_REGISTRY_SCRIPT := preload("res://scripts/autoload/data_registry.gd")
const START_MAP := "MAP_LITTLEROOT_TOWN"
const START_LAYOUT := "LAYOUT_LITTLEROOT_TOWN"


func _init() -> void:
	var registry = DATA_REGISTRY_SCRIPT.new()
	registry._ready()
	var map_data := registry.get_start_map_data()
	var tileset_data := registry.get_start_tileset_data()
	var script_data := registry.get_start_script_data()
	var runtime = MAP_RUNTIME_SCRIPT.new()
	runtime.configure_data_registry(registry)
	runtime.configure_from_data(map_data, tileset_data, _map_size_from_data(map_data))
	var game_state = GAME_STATE_SCRIPT.new()
	var vm = SCRIPT_VM_SCRIPT.new()
	vm.configure_from_script_data(script_data)
	var manager = EVENT_MANAGER_SCRIPT.new()
	manager.configure_from_script_data(script_data)
	manager.configure_script_vm(vm)
	manager.configure_map_runtime(runtime)
	manager.configure_game_state(game_state)
	manager.configure_data_registry(registry)

	var player_position_before: Vector2i = game_state.player_grid_position
	var twin_position_before := _event_position(runtime.get_object_event_by_local_id("LOCALID_LITTLEROOT_TWIN", true))
	var snapshot := runtime.get_current_map_runtime_debug_snapshot(game_state)
	var dump := manager.get_current_map_debug_dump()
	var player_position_after: Vector2i = game_state.player_grid_position
	var twin_position_after := _event_position(runtime.get_object_event_by_local_id("LOCALID_LITTLEROOT_TWIN", true))

	_assert(String(snapshot.get("status", "")) == "ok", "expected runtime snapshot ok")
	_assert(String(dump.get("status", "")) == "ok", "expected current-map debug dump ok")
	_assert(bool(dump.get("debug_only", false)), "expected debug-only dump")
	_assert(String(dump.get("map_id", "")) == START_MAP, "unexpected map id")
	_assert(String(dump.get("layout_id", "")) == START_LAYOUT, "unexpected layout id")
	_assert(_dict_value(dump.get("map_size", {})).get("x", 0) == 20, "unexpected map width")
	_assert(_dict_value(dump.get("map_size", {})).get("y", 0) == 20, "unexpected map height")
	_assert(String(_dict_value(dump.get("tileset_pair", {})).get("primary", "")) == "gTileset_General", "unexpected primary tileset")
	_assert(String(_dict_value(dump.get("tileset_pair", {})).get("secondary", "")) == "gTileset_Petalburg", "unexpected secondary tileset")
	_assert(String(dump.get("map_type", "")) == "MAP_TYPE_TOWN", "unexpected map type")
	_assert(String(dump.get("weather", "")) == "WEATHER_SUNNY", "unexpected weather")
	_assert(String(dump.get("music", "")) == "MUS_LITTLEROOT", "unexpected music")
	_assert(int(dump.get("object_count", 0)) == 8, "unexpected object count")
	_assert(int(dump.get("visible_object_count", 0)) == 8, "unexpected visible object count")
	_assert(int(dump.get("hidden_object_count", -1)) == 0, "unexpected hidden object count")
	_assert(int(dump.get("warp_count", 0)) == 3, "unexpected warp count")
	_assert(int(dump.get("coord_event_count", 0)) == 9, "unexpected coord event count")
	_assert(int(dump.get("bg_event_count", 0)) == 4, "unexpected bg event count")
	_assert(int(dump.get("connection_count", 0)) == 1, "unexpected connection count")
	_assert(int(dump.get("door_animation_count", 0)) == 2, "unexpected door animation count")

	var active_scripts := _dict_value(dump.get("active_scripts", {}))
	_assert(int(active_scripts.get("count", 0)) == 3, "expected three Littleroot map script hooks")
	_assert(_has_label(active_scripts, "MAP_SCRIPT_ON_TRANSITION", "LittlerootTown_OnTransition"), "missing OnTransition label")
	_assert(_has_label(active_scripts, "MAP_SCRIPT_ON_FRAME_TABLE", "LittlerootTown_OnFrame"), "missing OnFrame label")
	_assert(_has_label(active_scripts, "MAP_SCRIPT_ON_WARP_INTO_MAP_TABLE", "LittlerootTown_OnWarp"), "missing OnWarp label")
	_assert(_find_script_entry(active_scripts, "MAP_SCRIPT_ON_TRANSITION", "LittlerootTown_OnTransition").get("source_function", "") == "RunOnTransitionMapScript", "unexpected OnTransition source function")
	_assert(_find_script_entry(active_scripts, "MAP_SCRIPT_ON_FRAME_TABLE", "LittlerootTown_OnFrame").get("source_function", "") == "TryRunOnFrameMapScript", "unexpected OnFrame source function")
	_assert(_find_script_entry(active_scripts, "MAP_SCRIPT_ON_WARP_INTO_MAP_TABLE", "LittlerootTown_OnWarp").get("source_function", "") == "TryRunOnWarpIntoMapScript", "unexpected OnWarp source function")

	var on_frame_entry := _find_script_entry(active_scripts, "MAP_SCRIPT_ON_FRAME_TABLE", "LittlerootTown_OnFrame")
	var on_frame_table := _dict_value(on_frame_entry.get("table", {}))
	var first_on_frame_table_entry := _first_table_entry(on_frame_table)
	_assert(int(on_frame_table.get("entry_count", 0)) == 3, "unexpected OnFrame table entry count")
	_assert(bool(on_frame_table.get("terminal_found", false)), "expected OnFrame terminal")
	_assert(String(first_on_frame_table_entry.get("script_label", "")) == "LittlerootTown_EventScript_StepOffTruckMale", "unexpected first OnFrame script")
	_assert(not bool(first_on_frame_table_entry.get("condition_matched", true)), "expected first OnFrame condition to be false by default")
	_assert(player_position_before == player_position_after, "debug dump should not move the player")
	_assert(twin_position_before == twin_position_after, "debug dump should not move object events")

	game_state.set_var("VAR_LITTLEROOT_INTRO_STATE", 1)
	var matched_dump := manager.get_current_map_debug_dump()
	var matched_on_frame := _find_script_entry(_dict_value(matched_dump.get("active_scripts", {})), "MAP_SCRIPT_ON_FRAME_TABLE", "LittlerootTown_OnFrame")
	var matched_first_entry := _first_table_entry(_dict_value(matched_on_frame.get("table", {})))
	_assert(bool(matched_first_entry.get("condition_matched", false)), "expected OnFrame table to reflect GameState vars")
	_assert(String(matched_first_entry.get("var_source", "")) == "src/event_data.c:VarGet/GameState", "unexpected OnFrame var source")

	var unsupported_codes := _unsupported_codes(dump)
	for code in [
		"layer_split_pending",
		"tileset_animation_runtime_pending",
		"door_overlay_not_source_equivalent",
		"object_movement_task_pending",
		"object_event_sprite_animation_pending",
		"script_async_runtime_pending",
		"weather_runtime_pending",
		"audio_playback_pending",
		"source_collision_rules_pending",
	]:
		_assert(unsupported_codes.has(code), "missing unsupported code %s" % code)

	print(JSON.stringify({
		"overworld_runtime_debug_dump_smoke": "ok",
		"map_id": String(dump.get("map_id", "")),
		"layout_id": String(dump.get("layout_id", "")),
		"active_script_count": int(active_scripts.get("count", 0)),
		"object_count": int(dump.get("object_count", 0)),
		"warp_count": int(dump.get("warp_count", 0)),
		"coord_event_count": int(dump.get("coord_event_count", 0)),
		"unsupported_count": unsupported_codes.size(),
	}))
	manager.free()
	vm.free()
	game_state.free()
	runtime.free()
	registry.free()
	quit(0)


func _map_size_from_data(map_data: Dictionary) -> Vector2i:
	var layout_info = map_data.get("layout", {})
	if typeof(layout_info) != TYPE_DICTIONARY:
		return Vector2i.ZERO
	return Vector2i(
		int(layout_info.get("width", 0)),
		int(layout_info.get("height", 0))
	)


func _dict_value(value) -> Dictionary:
	return value if typeof(value) == TYPE_DICTIONARY else {}


func _array_value(value) -> Array:
	return value if typeof(value) == TYPE_ARRAY else []


func _has_label(active_scripts: Dictionary, script_type: String, label: String) -> bool:
	var labels_by_type := _dict_value(active_scripts.get("labels_by_type", {}))
	var labels := _array_value(labels_by_type.get(script_type, []))
	return labels.has(label)


func _find_script_entry(active_scripts: Dictionary, script_type: String, label: String) -> Dictionary:
	for entry in _array_value(active_scripts.get("entries", [])):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if String(entry.get("script_type", "")) == script_type and String(entry.get("label", "")) == label:
			return entry
	return {}


func _first_table_entry(table: Dictionary) -> Dictionary:
	var entries := _array_value(table.get("entries", []))
	if entries.is_empty() or typeof(entries[0]) != TYPE_DICTIONARY:
		return {}
	return entries[0]


func _unsupported_codes(dump: Dictionary) -> Array:
	var codes := []
	for item in _array_value(dump.get("unsupported_runtime_features", [])):
		if typeof(item) == TYPE_DICTIONARY:
			codes.append(String(item.get("code", "")))
	return codes


func _event_position(object_event: Dictionary) -> Vector2i:
	var position = object_event.get("position", Vector2i.ZERO)
	if typeof(position) == TYPE_VECTOR2I:
		return position
	return Vector2i(
		int(object_event.get("x", 0)),
		int(object_event.get("y", 0))
	)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	quit(1)
