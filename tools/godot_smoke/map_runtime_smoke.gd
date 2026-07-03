extends SceneTree

const MAP_RUNTIME_SCRIPT := preload("res://scripts/autoload/map_runtime.gd")
const SCRIPT_VM_SCRIPT := preload("res://scripts/autoload/script_vm.gd")
const GAME_STATE_SCRIPT := preload("res://scripts/autoload/game_state.gd")
const MAP_PATH := "res://data/generated/maps/littleroot_town.json"
const TILESET_PATH := "res://data/generated/tilesets/littleroot_town.json"
const SCRIPT_PATH := "res://data/generated/scripts/littleroot_town.json"


func _init() -> void:
	var map_data := _load_json_object(MAP_PATH)
	var tileset_data := _load_json_object(TILESET_PATH)
	var script_data := _load_json_object(SCRIPT_PATH)
	var map_size := _map_size_from_data(map_data)
	var runtime = MAP_RUNTIME_SCRIPT.new()
	runtime.configure_from_data(map_data, tileset_data, map_size)
	var vm = SCRIPT_VM_SCRIPT.new()
	vm.configure_from_script_data(script_data)
	var game_state = GAME_STATE_SCRIPT.new()
	vm.configure_game_state(game_state)

	var start_cell := Vector2i(10, 10)
	var object_cell := Vector2i(16, 10)
	var mom_cell := Vector2i(5, 8)
	var twin_approach_cell := Vector2i(19, 8)
	var bg_event_cell := Vector2i(15, 13)
	var warp_cell := Vector2i(7, 16)
	var mays_house_door_cell := Vector2i(14, 8)
	var need_pokemon_coord_cell := Vector2i(10, 1)
	var running_shoes_coord_cell := Vector2i(10, 2)
	var blocked_cell := _first_blocked_cell(map_data)
	game_state.player_grid_position = start_cell

	_assert(runtime.get_map_size() == Vector2i(20, 20), "unexpected map size")
	_assert(runtime.can_enter_cell(start_cell), "expected start cell to be passable")
	_assert(not runtime.can_enter_cell(Vector2i(-1, start_cell.y)), "expected west out-of-bounds to be blocked")
	_assert(blocked_cell != Vector2i(-1, -1), "expected at least one blocked source cell")
	_assert(not runtime.can_enter_cell(blocked_cell), "expected source collision cell to be blocked")
	_assert(runtime.get_object_events().size() == 8, "expected LittlerootTown object events")
	_assert(runtime.get_coord_events().size() == 9, "expected LittlerootTown coord events")
	_assert(runtime.get_collision_at(object_cell) == 0, "expected object test cell to be collision-passable")
	_assert(runtime.is_cell_occupied(object_cell), "expected object test cell to be occupied")
	_assert(not runtime.can_enter_cell(object_cell), "expected occupied object cell to be blocked")
	_assert(runtime.get_bg_events().size() == 4, "expected LittlerootTown bg events")
	_assert(runtime.get_warp_events().size() == 3, "expected LittlerootTown warp events")
	_assert(runtime.get_coord_events_at(need_pokemon_coord_cell).size() == 1, "expected need-pokemon coord event")
	_assert(runtime.get_coord_event_target(need_pokemon_coord_cell, game_state).get("script", "") == "LittlerootTown_EventScript_NeedPokemonTriggerLeft", "expected initial coord trigger")
	game_state.set_var("VAR_LITTLEROOT_TOWN_STATE", 3)
	_assert(runtime.get_coord_event_target(running_shoes_coord_cell, game_state).get("script", "") == "LittlerootTown_EventScript_GiveRunningShoesTrigger0", "expected state-gated coord trigger")
	game_state.set_var("VAR_LITTLEROOT_TOWN_STATE", 0)
	_assert(runtime.get_bg_events_at(bg_event_cell).size() == 1, "expected town sign bg event")
	_assert(runtime.get_warp_events_at(warp_cell).size() == 1, "expected Birch lab warp event")
	var mays_house_warp_target := runtime.get_warp_event_target(mays_house_door_cell)
	_assert(mays_house_warp_target.get("type", "") == "warp_event", "expected May house warp target")
	_assert(
		mays_house_warp_target.get("event", {}).get("dest_map", "") == "MAP_LITTLEROOT_TOWN_MAYS_HOUSE_1F",
		"expected May house warp destination"
	)
	_assert(
		runtime.get_interaction_target(Vector2i(15, 10), Vector2i.RIGHT).get("type", "") == "object_event",
		"expected object interaction target"
	)
	_assert(
		runtime.get_interaction_target(Vector2i(15, 14), Vector2i.UP).get("type", "") == "bg_event",
		"expected bg interaction target"
	)
	_assert(
		runtime.get_interaction_target(warp_cell, Vector2i.UP).get("type", "") == "warp_event",
		"expected warp interaction target"
	)
	_assert(runtime.get_metatile_behavior_at(start_cell) >= 0, "expected metatile behavior lookup")

	var need_pokemon_result := vm.run_script("LittlerootTown_EventScript_NeedPokemonTriggerLeft")
	var movements = need_pokemon_result.get("movements", [])
	_assert(typeof(movements) == TYPE_ARRAY and movements.size() == 4, "expected need-pokemon movements")
	var first_apply := runtime.apply_script_movements([movements[0]], game_state)
	_assert(_summary_count(first_apply, "applied") == 1, "expected first movement to apply")
	_assert(_summary_count(first_apply, "skipped") == 0, "expected first movement not to skip")
	_assert(not runtime.is_cell_occupied(object_cell), "expected original twin cell to be cleared")
	_assert(runtime.is_cell_occupied(twin_approach_cell), "expected twin approach cell to be occupied")
	_assert(
		_event_position(runtime.get_object_event_by_local_id("LOCALID_LITTLEROOT_TWIN", true)) == twin_approach_cell,
		"expected twin to move to approach cell"
	)

	var rest_apply := runtime.apply_script_movements([movements[1], movements[2], movements[3]], game_state)
	_assert(_summary_count(rest_apply, "applied") == 3, "expected remaining movements to apply")
	_assert(_summary_count(rest_apply, "skipped") == 0, "expected remaining movements not to skip")
	_assert(
		_event_position(runtime.get_object_event_by_local_id("LOCALID_LITTLEROOT_TWIN", true)) == object_cell,
		"expected twin to return to source cell"
	)
	_assert(game_state.player_grid_position == Vector2i(10, 11), "expected player movement to update game state")

	game_state.set_var("VAR_LITTLEROOT_TOWN_STATE", 1)
	var set_twin_pos_result := vm.run_script("LittlerootTown_EventScript_SetTwinPos")
	var set_twin_object_effects = set_twin_pos_result.get("object_effects", [])
	_assert(typeof(set_twin_object_effects) == TYPE_ARRAY and set_twin_object_effects.size() == 2, "expected set-twin object effects")
	var set_twin_apply := runtime.apply_script_object_effects(set_twin_object_effects, game_state)
	var twin_event := runtime.get_object_event_by_local_id("LOCALID_LITTLEROOT_TWIN", true)
	_assert(_summary_count(set_twin_apply, "applied") == 2, "expected set-twin object effects to apply")
	_assert(_summary_count(set_twin_apply, "skipped") == 0, "expected set-twin object effects not to skip")
	_assert(_template_position(twin_event) == Vector2i(10, 1), "expected twin template position to update")
	_assert(_event_position(twin_event) == object_cell, "expected setobjectxyperm not to move active twin")
	_assert(String(twin_event.get("movement_type", "")) == "MOVEMENT_TYPE_FACE_UP", "expected twin movement type to update")

	var set_rival_birch_result := vm.run_script("LittlerootTown_EventScript_SetRivalBirchPosForDexUpgradeMale")
	var set_rival_birch_effects = set_rival_birch_result.get("object_effects", [])
	_assert(typeof(set_rival_birch_effects) == TYPE_ARRAY and set_rival_birch_effects.size() == 2, "expected rival/birch object effects")
	var set_rival_birch_apply := runtime.apply_script_object_effects(set_rival_birch_effects, game_state)
	_assert(_summary_count(set_rival_birch_apply, "applied") == 2, "expected rival/birch object effects to apply")
	_assert(_summary_count(set_rival_birch_apply, "skipped") == 0, "expected rival/birch object effects not to skip")
	_assert(
		_event_position(runtime.get_object_event_by_local_id("LOCALID_LITTLEROOT_RIVAL", true)) == Vector2i(6, 10),
		"expected rival to move to dex-upgrade position"
	)
	_assert(
		_event_position(runtime.get_object_event_by_local_id("LOCALID_LITTLEROOT_BIRCH", true)) == Vector2i(5, 10),
		"expected Birch to move to dex-upgrade position"
	)
	_assert(runtime.is_cell_occupied(Vector2i(6, 10)), "expected rival destination to be occupied")
	_assert(runtime.is_cell_occupied(Vector2i(5, 10)), "expected Birch destination to be occupied")

	var hide_mom_apply := runtime.apply_script_object_effects([
		{"op": "hideobjectat", "target": "LOCALID_LITTLEROOT_MOM", "map": "MAP_LITTLEROOT_TOWN", "line": 0},
	], game_state)
	_assert(_summary_count(hide_mom_apply, "applied") == 1, "expected hideobjectat to apply")
	_assert(runtime.get_object_event_by_local_id("LOCALID_LITTLEROOT_MOM").is_empty(), "expected hidden Mom to be invisible")
	_assert(not runtime.is_cell_occupied(mom_cell), "expected hidden Mom cell to be unoccupied")

	var show_mom_apply := runtime.apply_script_object_effects([
		{"op": "showobjectat", "target": "LOCALID_LITTLEROOT_MOM", "map": "MAP_LITTLEROOT_TOWN", "line": 0},
	], game_state)
	_assert(_summary_count(show_mom_apply, "applied") == 1, "expected showobjectat to apply")
	_assert(not runtime.get_object_event_by_local_id("LOCALID_LITTLEROOT_MOM").is_empty(), "expected shown Mom to be visible")
	_assert(runtime.is_cell_occupied(mom_cell), "expected shown Mom cell to be occupied")

	var running_shoes_result := vm.run_script("LittlerootTown_EventScript_SetReceivedRunningShoes")
	var running_shoes_effects = running_shoes_result.get("object_effects", [])
	_assert(typeof(running_shoes_effects) == TYPE_ARRAY and running_shoes_effects.size() == 1, "expected running-shoes object effect")
	var remove_mom_apply := runtime.apply_script_object_effects(running_shoes_effects, game_state)
	_assert(_summary_count(remove_mom_apply, "applied") == 1, "expected removeobject to apply")
	_assert(game_state.is_flag_set("FLAG_HIDE_LITTLEROOT_TOWN_MOM_OUTSIDE"), "expected removeobject to set Mom hide flag")
	_assert(runtime.get_object_event_by_local_id("LOCALID_LITTLEROOT_MOM").is_empty(), "expected removed Mom to be invisible")

	var blocked_add_mom_apply := runtime.apply_script_object_effects([
		{"op": "addobject", "target": "LOCALID_LITTLEROOT_MOM", "line": 0},
	], game_state)
	_assert(_summary_count(blocked_add_mom_apply, "applied") == 0, "expected addobject to skip while flag is set")
	_assert(_summary_count(blocked_add_mom_apply, "skipped") == 1, "expected hidden-by-flag addobject skip")

	game_state.clear_flag("FLAG_HIDE_LITTLEROOT_TOWN_MOM_OUTSIDE")
	var add_mom_apply := runtime.apply_script_object_effects([
		{"op": "addobject", "target": "LOCALID_LITTLEROOT_MOM", "line": 0},
	], game_state)
	_assert(_summary_count(add_mom_apply, "applied") == 1, "expected addobject to apply after clearing flag")
	_assert(not runtime.get_object_event_by_local_id("LOCALID_LITTLEROOT_MOM").is_empty(), "expected added Mom to be visible")
	_assert(runtime.is_cell_occupied(mom_cell), "expected added Mom cell to be occupied")

	print(JSON.stringify({
		"map_runtime_smoke": "ok",
		"map_size": _vector_to_array(runtime.get_map_size()),
		"object_event_count": runtime.get_object_events().size(),
		"bg_event_count": runtime.get_bg_events().size(),
		"warp_event_count": runtime.get_warp_events().size(),
		"coord_event_count": runtime.get_coord_events().size(),
		"need_pokemon_coord": _target_summary(runtime.get_coord_event_target(need_pokemon_coord_cell, game_state)),
		"first_movement_apply": _movement_apply_summary(first_apply),
		"rest_movement_apply": _movement_apply_summary(rest_apply),
		"set_twin_object_apply": _object_apply_summary(set_twin_apply),
		"set_rival_birch_object_apply": _object_apply_summary(set_rival_birch_apply),
		"remove_mom_object_apply": _object_apply_summary(remove_mom_apply),
		"add_mom_object_apply": _object_apply_summary(add_mom_apply),
		"player_position_after_script": _vector_to_array(game_state.player_grid_position),
		"start_cell": _cell_info_summary(runtime.get_cell_info(start_cell)),
		"object_cell": _cell_info_summary(runtime.get_cell_info(object_cell)),
		"bg_event_cell": _cell_info_summary(runtime.get_cell_info(bg_event_cell)),
		"warp_cell": _cell_info_summary(runtime.get_cell_info(warp_cell)),
		"mays_house_warp": _target_summary(mays_house_warp_target),
		"blocked_cell": _cell_info_summary(runtime.get_cell_info(blocked_cell)),
	}))
	game_state.free()
	vm.free()
	runtime.free()
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


func _map_size_from_data(map_data: Dictionary) -> Vector2i:
	var layout_info = map_data.get("layout", {})
	if typeof(layout_info) != TYPE_DICTIONARY:
		return Vector2i.ZERO
	return Vector2i(
		int(layout_info.get("width", 0)),
		int(layout_info.get("height", 0))
	)


func _first_blocked_cell(map_data: Dictionary) -> Vector2i:
	var map_grid = map_data.get("map_grid", {})
	if typeof(map_grid) != TYPE_DICTIONARY:
		return Vector2i(-1, -1)

	var collision_grid = map_grid.get("collision", [])
	if typeof(collision_grid) != TYPE_ARRAY:
		return Vector2i(-1, -1)

	for y in range(collision_grid.size()):
		var row = collision_grid[y]
		if typeof(row) != TYPE_ARRAY:
			continue
		for x in range(row.size()):
			if int(row[x]) != 0:
				return Vector2i(x, y)

	return Vector2i(-1, -1)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	quit(1)


func _cell_info_summary(cell_info: Dictionary) -> Dictionary:
	var position = cell_info.get("position", Vector2i(-1, -1))
	return {
		"position": _vector_to_array(position),
		"within_bounds": bool(cell_info.get("within_bounds", false)),
		"metatile_id": int(cell_info.get("metatile_id", -1)),
		"collision": int(cell_info.get("collision", -1)),
		"elevation": int(cell_info.get("elevation", -1)),
		"behavior": int(cell_info.get("behavior", -1)),
		"layer_type": int(cell_info.get("layer_type", -1)),
		"occupied": bool(cell_info.get("occupied", false)),
		"object_event_count": int(cell_info.get("object_event_count", 0)),
		"bg_event_count": int(cell_info.get("bg_event_count", 0)),
		"warp_event_count": int(cell_info.get("warp_event_count", 0)),
		"coord_event_count": int(cell_info.get("coord_event_count", 0)),
		"passable": bool(cell_info.get("passable", false)),
	}


func _vector_to_array(value: Vector2i) -> Array:
	return [value.x, value.y]


func _event_position(object_event: Dictionary) -> Vector2i:
	var position = object_event.get("position", Vector2i.ZERO)
	if typeof(position) == TYPE_VECTOR2I:
		return position
	return Vector2i(
		int(object_event.get("x", 0)),
		int(object_event.get("y", 0))
	)


func _template_position(object_event: Dictionary) -> Vector2i:
	var position = object_event.get("template_position", Vector2i.ZERO)
	if typeof(position) == TYPE_VECTOR2I:
		return position
	return Vector2i(
		int(object_event.get("template_x", 0)),
		int(object_event.get("template_y", 0))
	)


func _summary_count(summary: Dictionary, key: String) -> int:
	var entries = summary.get(key, [])
	return entries.size() if typeof(entries) == TYPE_ARRAY else 0


func _movement_apply_summary(summary: Dictionary) -> Dictionary:
	return {
		"applied": _summary_count(summary, "applied"),
		"skipped": _summary_count(summary, "skipped"),
		"object_events_changed": bool(summary.get("object_events_changed", false)),
		"player_position_changed": bool(summary.get("player_position_changed", false)),
	}


func _object_apply_summary(summary: Dictionary) -> Dictionary:
	return {
		"applied": _summary_count(summary, "applied"),
		"skipped": _summary_count(summary, "skipped"),
		"object_events_changed": bool(summary.get("object_events_changed", false)),
	}


func _target_summary(target: Dictionary) -> Dictionary:
	return {
		"type": String(target.get("type", "")),
		"script": String(target.get("script", "")),
		"position": _vector_to_array(target.get("position", Vector2i.ZERO)),
	}
