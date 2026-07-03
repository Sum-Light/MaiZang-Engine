extends Node

signal map_changed(map_data: Dictionary, tileset_data: Dictionary, map_size: Vector2i)
signal object_events_changed(object_events: Array)
signal player_position_changed(grid_position: Vector2i)

const COLLISION_NONE := 0
const COLLISION_IMPASSABLE := 1
const ELEVATION_INVALID := -1
const ELEVATION_TRANSITION := 0
const LOCALID_PLAYER := "LOCALID_PLAYER"

var _map_data: Dictionary = {}
var _tileset_data: Dictionary = {}
var _map_size := Vector2i.ZERO
var _block_ids: Array = []
var _collision_grid: Array = []
var _elevation_grid: Array = []
var _metatile_attributes: Dictionary = {}
var _object_events: Array = []
var _object_events_by_position: Dictionary = {}
var _object_events_by_local_id: Dictionary = {}
var _bg_events: Array = []
var _bg_events_by_position: Dictionary = {}
var _warp_events: Array = []
var _warp_events_by_position: Dictionary = {}
var _coord_events: Array = []
var _coord_events_by_position: Dictionary = {}


func _ready() -> void:
	var registry = get_node_or_null("/root/DataRegistry")
	if registry == null:
		return

	configure_from_data(
		registry.get_start_map_data(),
		registry.get_start_tileset_data(),
		registry.get_start_map_size()
	)


func configure_from_data(
	map_data: Dictionary,
	tileset_data: Dictionary,
	fallback_map_size := Vector2i.ZERO
) -> void:
	_map_data = map_data
	_tileset_data = tileset_data
	_map_size = fallback_map_size
	_block_ids = []
	_collision_grid = []
	_elevation_grid = []
	_metatile_attributes = {}
	_object_events = []
	_object_events_by_position = {}
	_object_events_by_local_id = {}
	_bg_events = []
	_bg_events_by_position = {}
	_warp_events = []
	_warp_events_by_position = {}
	_coord_events = []
	_coord_events_by_position = {}

	if not _map_data.is_empty():
		var layout_info = _map_data.get("layout", {})
		if typeof(layout_info) == TYPE_DICTIONARY:
			_map_size = Vector2i(
				int(layout_info.get("width", _map_size.x)),
				int(layout_info.get("height", _map_size.y))
			)

		_block_ids = _array_or_empty(_map_data.get("block_ids", []))
		var map_grid = _map_data.get("map_grid", {})
		if typeof(map_grid) == TYPE_DICTIONARY:
			_collision_grid = _array_or_empty(map_grid.get("collision", []))
			_elevation_grid = _array_or_empty(map_grid.get("elevation", []))

	_index_metatile_attributes()
	_index_object_events()
	_index_bg_events()
	_index_warp_events()
	_index_coord_events()
	map_changed.emit(_map_data, _tileset_data, _map_size)
	object_events_changed.emit(get_object_events())


func is_within_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < _map_size.x and cell.y < _map_size.y


func can_enter_cell(cell: Vector2i) -> bool:
	return (
		is_within_bounds(cell)
		and get_collision_at(cell) == COLLISION_NONE
		and not is_cell_occupied(cell)
	)


func get_map_size() -> Vector2i:
	return _map_size


func get_metatile_id_at(cell: Vector2i) -> int:
	return _grid_value(_block_ids, cell, -1)


func get_collision_at(cell: Vector2i) -> int:
	if not is_within_bounds(cell):
		return COLLISION_IMPASSABLE
	if _collision_grid.is_empty():
		return COLLISION_NONE
	return _grid_value(_collision_grid, cell, COLLISION_IMPASSABLE)


func get_elevation_at(cell: Vector2i) -> int:
	return _grid_value(_elevation_grid, cell, ELEVATION_INVALID)


func get_metatile_attribute(metatile_id: int) -> Dictionary:
	if _metatile_attributes.has(metatile_id):
		var attribute = _metatile_attributes[metatile_id]
		if typeof(attribute) == TYPE_DICTIONARY:
			return attribute
	return {}


func get_metatile_behavior_at(cell: Vector2i) -> int:
	return int(get_metatile_attribute(get_metatile_id_at(cell)).get("behavior", -1))


func get_metatile_layer_type_at(cell: Vector2i) -> int:
	return int(get_metatile_attribute(get_metatile_id_at(cell)).get("layer_type", -1))


func get_object_events(include_hidden := false) -> Array:
	var events := []
	for object_event in _object_events:
		if include_hidden or _is_object_event_visible(object_event):
			events.append(object_event)
	return events


func get_object_events_at(cell: Vector2i, include_hidden := false) -> Array:
	var key := _cell_key(cell)
	var events = _object_events_by_position.get(key, [])
	if typeof(events) != TYPE_ARRAY:
		return []

	var filtered_events := []
	for object_event in events:
		if include_hidden or _is_object_event_visible(object_event):
			filtered_events.append(object_event)
	return filtered_events


func get_object_event_by_local_id(local_id: String, include_hidden := false) -> Dictionary:
	var object_event = _object_events_by_local_id.get(local_id, {})
	if typeof(object_event) != TYPE_DICTIONARY:
		return {}
	if not include_hidden and not _is_object_event_visible(object_event):
		return {}
	return object_event


func get_bg_events() -> Array:
	return _bg_events.duplicate(true)


func get_bg_events_at(cell: Vector2i) -> Array:
	return _events_at(_bg_events_by_position, cell)


func get_warp_events() -> Array:
	return _warp_events.duplicate(true)


func get_warp_events_at(cell: Vector2i) -> Array:
	return _events_at(_warp_events_by_position, cell)


func get_coord_events() -> Array:
	return _coord_events.duplicate(true)


func get_coord_events_at(cell: Vector2i) -> Array:
	return _events_at(_coord_events_by_position, cell)


func is_cell_occupied(cell: Vector2i) -> bool:
	return not get_object_events_at(cell).is_empty()


func get_interaction_target(origin: Vector2i, direction: Vector2i) -> Dictionary:
	var facing_direction := direction
	if facing_direction == Vector2i.ZERO:
		facing_direction = Vector2i.DOWN

	var target_cell := origin + facing_direction
	var object_events := get_object_events_at(target_cell)
	if not object_events.is_empty():
		var object_event: Dictionary = object_events[0]
		return _interaction_target(
			"object_event",
			target_cell,
			object_event,
			String(object_event.get("script", "0x0"))
		)

	var bg_events := get_bg_events_at(target_cell)
	if not bg_events.is_empty():
		var bg_event: Dictionary = bg_events[0]
		return _interaction_target(
			"bg_event",
			target_cell,
			bg_event,
			String(bg_event.get("script", "0x0"))
		)

	var warp_events := get_warp_events_at(origin)
	if not warp_events.is_empty():
		return _interaction_target("warp_event", origin, warp_events[0], "warp")

	return {}


func get_coord_event_target(cell: Vector2i, game_state: Node = null) -> Dictionary:
	var resolved_game_state := game_state
	if resolved_game_state == null and is_inside_tree():
		resolved_game_state = get_node_or_null("/root/GameState")

	var elevation := get_elevation_at(cell)
	for coord_event in get_coord_events_at(cell):
		if typeof(coord_event) != TYPE_DICTIONARY:
			continue
		if not _coord_event_matches_elevation(coord_event, elevation):
			continue
		if not _coord_event_matches_trigger(coord_event, resolved_game_state):
			continue

		var script := String(coord_event.get("script", "0x0"))
		if script.is_empty() or script == "0x0":
			continue
		return _interaction_target("coord_event", cell, coord_event, script)

	return {}


func get_cell_info(cell: Vector2i) -> Dictionary:
	var metatile_id := get_metatile_id_at(cell)
	var object_events_at_cell := get_object_events_at(cell)
	var bg_events_at_cell := get_bg_events_at(cell)
	var warp_events_at_cell := get_warp_events_at(cell)
	var coord_events_at_cell := get_coord_events_at(cell)
	return {
		"position": cell,
		"within_bounds": is_within_bounds(cell),
		"metatile_id": metatile_id,
		"collision": get_collision_at(cell),
		"elevation": get_elevation_at(cell),
		"behavior": get_metatile_attribute(metatile_id).get("behavior", -1),
		"layer_type": get_metatile_attribute(metatile_id).get("layer_type", -1),
		"occupied": not object_events_at_cell.is_empty(),
		"object_event_count": object_events_at_cell.size(),
		"bg_event_count": bg_events_at_cell.size(),
		"warp_event_count": warp_events_at_cell.size(),
		"coord_event_count": coord_events_at_cell.size(),
		"passable": can_enter_cell(cell),
	}


func apply_script_movements(movements: Array, game_state: Node = null) -> Dictionary:
	var summary := {
		"applied": [],
		"skipped": [],
		"object_events_changed": false,
		"player_position_changed": false,
	}
	var resolved_game_state := game_state
	if resolved_game_state == null and is_inside_tree():
		resolved_game_state = get_node_or_null("/root/GameState")

	for movement in movements:
		if typeof(movement) != TYPE_DICTIONARY:
			_record_skipped_movement(summary, "invalid_movement", "", "", Vector2i.ZERO)
			continue

		var target := String(movement.get("target", ""))
		var movement_label := String(movement.get("movement_label", ""))
		var delta := _movement_delta(movement)
		var final_facing := String(movement.get("final_facing", ""))

		if target == LOCALID_PLAYER:
			_apply_player_movement(summary, resolved_game_state, movement_label, delta, final_facing)
		else:
			_apply_object_movement(summary, target, movement_label, delta, final_facing)

	if bool(summary["object_events_changed"]):
		_rebuild_object_event_position_index()
		object_events_changed.emit(get_object_events())
	if bool(summary["player_position_changed"]) and resolved_game_state != null:
		player_position_changed.emit(resolved_game_state.player_grid_position)

	return summary


func apply_script_object_effects(object_effects: Array, game_state: Node = null) -> Dictionary:
	var summary := {
		"applied": [],
		"skipped": [],
		"object_events_changed": false,
	}
	var resolved_game_state := game_state
	if resolved_game_state == null and is_inside_tree():
		resolved_game_state = get_node_or_null("/root/GameState")

	for object_effect in object_effects:
		if typeof(object_effect) != TYPE_DICTIONARY:
			_record_skipped_object_effect(summary, "invalid_object_effect", "", "", 0)
			continue

		var effect: Dictionary = object_effect
		var op := String(effect.get("op", ""))
		var target := String(effect.get("target", ""))
		var line := int(effect.get("line", 0))
		if not _object_effect_targets_current_map(effect):
			_record_skipped_object_effect(summary, "different_map", target, op, line)
			continue

		match op:
			"setobjectxy":
				_apply_set_object_position(summary, effect)
			"setobjectxyperm":
				_apply_set_object_template_position(summary, effect)
			"setobjectmovementtype":
				_apply_set_object_movement_type(summary, effect)
			"addobject", "addobjectat":
				_apply_add_object(summary, effect, resolved_game_state)
			"removeobject", "removeobjectat":
				_apply_remove_object(summary, effect, resolved_game_state)
			"showobject", "showobjectat":
				_apply_set_object_runtime_hidden(summary, effect, false)
			"hideobject", "hideobjectat":
				_apply_set_object_runtime_hidden(summary, effect, true)
			_:
				_record_skipped_object_effect(summary, "unsupported_object_effect", target, op, line)

	if bool(summary["object_events_changed"]):
		_rebuild_object_event_position_index()
		object_events_changed.emit(get_object_events())

	return summary


func set_player_grid_position(grid_position: Vector2i, game_state: Node = null) -> bool:
	if not is_within_bounds(grid_position):
		return false

	var resolved_game_state := game_state
	if resolved_game_state == null and is_inside_tree():
		resolved_game_state = get_node_or_null("/root/GameState")
	if resolved_game_state == null:
		return false

	resolved_game_state.player_grid_position = grid_position
	player_position_changed.emit(grid_position)
	return true


func _index_metatile_attributes() -> void:
	if _tileset_data.is_empty():
		return

	var entries = _tileset_data.get("metatile_entries", [])
	if typeof(entries) != TYPE_ARRAY:
		return

	for entry in entries:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var metatile_id := int(entry.get("id", -1))
		if metatile_id < 0:
			continue
		var attribute = entry.get("attribute", {})
		if typeof(attribute) == TYPE_DICTIONARY:
			_metatile_attributes[metatile_id] = attribute


func _index_object_events() -> void:
	var events = _map_data.get("events", {})
	if typeof(events) != TYPE_DICTIONARY:
		return

	var object_events = events.get("object_events", [])
	if typeof(object_events) != TYPE_ARRAY:
		return

	for index in range(object_events.size()):
		var source_event = object_events[index]
		if typeof(source_event) != TYPE_DICTIONARY:
			continue

		var object_event = source_event.duplicate(true)
		var cell := Vector2i(
			int(object_event.get("x", 0)),
			int(object_event.get("y", 0))
		)
		object_event["index"] = index
		object_event["position"] = cell
		object_event["template_position"] = cell
		object_event["template_x"] = cell.x
		object_event["template_y"] = cell.y
		object_event["template_movement_type"] = String(object_event.get("movement_type", ""))
		_object_events.append(object_event)
		_index_object_event_by_local_id(object_event)
		_add_event_at(_object_events_by_position, cell, object_event)


func _index_bg_events() -> void:
	var events = _map_data.get("events", {})
	if typeof(events) != TYPE_DICTIONARY:
		return

	var bg_events = events.get("bg_events", [])
	if typeof(bg_events) != TYPE_ARRAY:
		return

	for index in range(bg_events.size()):
		var source_event = bg_events[index]
		if typeof(source_event) != TYPE_DICTIONARY:
			continue

		var bg_event = source_event.duplicate(true)
		var cell := Vector2i(
			int(bg_event.get("x", 0)),
			int(bg_event.get("y", 0))
		)
		bg_event["index"] = index
		bg_event["position"] = cell
		_bg_events.append(bg_event)
		_add_event_at(_bg_events_by_position, cell, bg_event)


func _index_warp_events() -> void:
	var events = _map_data.get("events", {})
	if typeof(events) != TYPE_DICTIONARY:
		return

	var warp_events = events.get("warp_events", [])
	if typeof(warp_events) != TYPE_ARRAY:
		return

	for index in range(warp_events.size()):
		var source_event = warp_events[index]
		if typeof(source_event) != TYPE_DICTIONARY:
			continue

		var warp_event = source_event.duplicate(true)
		var cell := Vector2i(
			int(warp_event.get("x", 0)),
			int(warp_event.get("y", 0))
		)
		warp_event["index"] = index
		warp_event["position"] = cell
		_warp_events.append(warp_event)
		_add_event_at(_warp_events_by_position, cell, warp_event)


func _index_coord_events() -> void:
	var events = _map_data.get("events", {})
	if typeof(events) != TYPE_DICTIONARY:
		return

	var coord_events = events.get("coord_events", [])
	if typeof(coord_events) != TYPE_ARRAY:
		return

	for index in range(coord_events.size()):
		var source_event = coord_events[index]
		if typeof(source_event) != TYPE_DICTIONARY:
			continue

		var coord_event = source_event.duplicate(true)
		var cell := Vector2i(
			int(coord_event.get("x", 0)),
			int(coord_event.get("y", 0))
		)
		coord_event["index"] = index
		coord_event["position"] = cell
		_coord_events.append(coord_event)
		_add_event_at(_coord_events_by_position, cell, coord_event)


func _is_object_event_visible(object_event: Dictionary) -> bool:
	if bool(object_event.get("runtime_hidden", false)):
		return false

	var flag := String(object_event.get("flag", "0"))
	if flag.is_empty() or flag == "0":
		return true

	if not is_inside_tree():
		return true

	var game_state = get_node_or_null("/root/GameState")
	if game_state != null and game_state.has_method("is_flag_set"):
		return not game_state.is_flag_set(flag)

	return true


func _coord_event_matches_elevation(coord_event: Dictionary, elevation: int) -> bool:
	var event_elevation := int(coord_event.get("elevation", ELEVATION_INVALID))
	return event_elevation == elevation or event_elevation == ELEVATION_TRANSITION


func _coord_event_matches_trigger(coord_event: Dictionary, game_state: Node) -> bool:
	var trigger := String(coord_event.get("var", coord_event.get("trigger", "")))
	if trigger.is_empty() or trigger == "0" or trigger == "TRIGGER_RUN_IMMEDIATELY":
		return true

	var expected_value := int(coord_event.get("var_value", coord_event.get("index", 0)))
	if trigger.begins_with("VAR_"):
		var actual_value := 0
		if game_state != null and game_state.has_method("get_var"):
			actual_value = int(game_state.get_var(trigger, 0))
		return actual_value == expected_value

	var flag_is_set := false
	if game_state != null and game_state.has_method("is_flag_set"):
		flag_is_set = bool(game_state.is_flag_set(trigger))
	return flag_is_set == (expected_value != 0)


func _apply_player_movement(
	summary: Dictionary,
	game_state: Node,
	movement_label: String,
	delta: Vector2i,
	final_facing: String
) -> void:
	if game_state == null:
		_record_skipped_movement(summary, "missing_game_state", LOCALID_PLAYER, movement_label, delta)
		return

	var current_position: Vector2i = game_state.player_grid_position
	var next_position := current_position + delta
	if not is_within_bounds(next_position):
		_record_skipped_movement(summary, "out_of_bounds", LOCALID_PLAYER, movement_label, delta, next_position)
		return

	game_state.player_grid_position = next_position
	summary["player_position_changed"] = delta != Vector2i.ZERO
	_record_applied_movement(summary, LOCALID_PLAYER, movement_label, current_position, next_position, final_facing)


func _apply_object_movement(
	summary: Dictionary,
	target: String,
	movement_label: String,
	delta: Vector2i,
	final_facing: String
) -> void:
	var object_event := get_object_event_by_local_id(target, true)
	if object_event.is_empty():
		_record_skipped_movement(summary, "missing_object_event", target, movement_label, delta)
		return

	var current_position := _object_event_position(object_event)
	var next_position := current_position + delta
	if not is_within_bounds(next_position):
		_record_skipped_movement(summary, "out_of_bounds", target, movement_label, delta, next_position)
		return

	object_event["position"] = next_position
	object_event["x"] = next_position.x
	object_event["y"] = next_position.y
	if not final_facing.is_empty():
		object_event["facing_direction"] = final_facing
	summary["object_events_changed"] = true
	_record_applied_movement(summary, target, movement_label, current_position, next_position, final_facing)


func _apply_set_object_position(summary: Dictionary, object_effect: Dictionary) -> void:
	var target := String(object_effect.get("target", ""))
	var op := String(object_effect.get("op", ""))
	var line := int(object_effect.get("line", 0))
	if target == LOCALID_PLAYER:
		_record_skipped_object_effect(summary, "player_target_unsupported", target, op, line)
		return

	var object_event := get_object_event_by_local_id(target, true)
	if object_event.is_empty():
		_record_skipped_object_effect(summary, "missing_object_event", target, op, line)
		return

	var next_position := _effect_position(object_effect)
	if not is_within_bounds(next_position):
		_record_skipped_object_effect(summary, "out_of_bounds", target, op, line)
		return

	var current_position := _object_event_position(object_event)
	_set_object_event_position(object_event, next_position)
	summary["object_events_changed"] = true
	_record_applied_object_effect(summary, object_effect, current_position, next_position)


func _apply_set_object_template_position(summary: Dictionary, object_effect: Dictionary) -> void:
	var target := String(object_effect.get("target", ""))
	var op := String(object_effect.get("op", ""))
	var line := int(object_effect.get("line", 0))
	if target == LOCALID_PLAYER:
		_record_skipped_object_effect(summary, "player_target_unsupported", target, op, line)
		return

	var object_event := get_object_event_by_local_id(target, true)
	if object_event.is_empty():
		_record_skipped_object_effect(summary, "missing_object_event", target, op, line)
		return

	var next_position := _effect_position(object_effect)
	if not is_within_bounds(next_position):
		_record_skipped_object_effect(summary, "out_of_bounds", target, op, line)
		return

	var previous_template_position := _object_event_template_position(object_event)
	object_event["template_position"] = next_position
	object_event["template_x"] = next_position.x
	object_event["template_y"] = next_position.y
	summary["object_events_changed"] = true
	_record_applied_object_effect(summary, object_effect, previous_template_position, next_position)


func _apply_set_object_movement_type(summary: Dictionary, object_effect: Dictionary) -> void:
	var target := String(object_effect.get("target", ""))
	var op := String(object_effect.get("op", ""))
	var line := int(object_effect.get("line", 0))
	if target == LOCALID_PLAYER:
		_record_skipped_object_effect(summary, "player_target_unsupported", target, op, line)
		return

	var object_event := get_object_event_by_local_id(target, true)
	if object_event.is_empty():
		_record_skipped_object_effect(summary, "missing_object_event", target, op, line)
		return

	var movement_type := String(object_effect.get("movement_type", ""))
	if movement_type.is_empty():
		_record_skipped_object_effect(summary, "missing_movement_type", target, op, line)
		return

	var current_position := _object_event_position(object_event)
	object_event["template_movement_type"] = movement_type
	object_event["movement_type"] = movement_type
	summary["object_events_changed"] = true
	_record_applied_object_effect(summary, object_effect, current_position, current_position, {
		"movement_type": movement_type,
	})


func _apply_add_object(summary: Dictionary, object_effect: Dictionary, game_state: Node) -> void:
	var target := String(object_effect.get("target", ""))
	var op := String(object_effect.get("op", ""))
	var line := int(object_effect.get("line", 0))
	if target == LOCALID_PLAYER:
		_record_skipped_object_effect(summary, "player_target_unsupported", target, op, line)
		return

	var object_event := get_object_event_by_local_id(target, true)
	if object_event.is_empty():
		_record_skipped_object_effect(summary, "missing_object_event", target, op, line)
		return
	if _object_event_flag_is_set(object_event, game_state):
		_record_skipped_object_effect(summary, "hidden_by_flag", target, op, line)
		return

	var current_position := _object_event_position(object_event)
	var template_position := _object_event_template_position(object_event)
	if not is_within_bounds(template_position):
		_record_skipped_object_effect(summary, "out_of_bounds", target, op, line)
		return

	_set_object_event_position(object_event, template_position)
	object_event["runtime_hidden"] = false
	summary["object_events_changed"] = true
	_record_applied_object_effect(summary, object_effect, current_position, template_position)


func _apply_remove_object(summary: Dictionary, object_effect: Dictionary, game_state: Node) -> void:
	var target := String(object_effect.get("target", ""))
	var op := String(object_effect.get("op", ""))
	var line := int(object_effect.get("line", 0))
	if target == LOCALID_PLAYER:
		_record_skipped_object_effect(summary, "player_target_unsupported", target, op, line)
		return

	var object_event := get_object_event_by_local_id(target, true)
	if object_event.is_empty():
		_record_skipped_object_effect(summary, "missing_object_event", target, op, line)
		return

	var current_position := _object_event_position(object_event)
	_set_object_flag(object_event, game_state, true)
	object_event["runtime_hidden"] = true
	summary["object_events_changed"] = true
	_record_applied_object_effect(summary, object_effect, current_position, current_position, {
		"flag": String(object_event.get("flag", "0")),
		"runtime_hidden": true,
	})


func _apply_set_object_runtime_hidden(summary: Dictionary, object_effect: Dictionary, hidden: bool) -> void:
	var target := String(object_effect.get("target", ""))
	var op := String(object_effect.get("op", ""))
	var line := int(object_effect.get("line", 0))
	if target == LOCALID_PLAYER:
		_record_skipped_object_effect(summary, "player_target_unsupported", target, op, line)
		return

	var object_event := get_object_event_by_local_id(target, true)
	if object_event.is_empty():
		_record_skipped_object_effect(summary, "missing_object_event", target, op, line)
		return

	var current_position := _object_event_position(object_event)
	object_event["runtime_hidden"] = hidden
	summary["object_events_changed"] = true
	_record_applied_object_effect(summary, object_effect, current_position, current_position, {
		"runtime_hidden": hidden,
	})


func _movement_delta(movement: Dictionary) -> Vector2i:
	var delta = movement.get("net_delta", [0, 0])
	if typeof(delta) != TYPE_ARRAY or delta.size() < 2:
		return Vector2i.ZERO
	return Vector2i(int(delta[0]), int(delta[1]))


func _object_effect_targets_current_map(object_effect: Dictionary) -> bool:
	var target_map := String(object_effect.get("map", ""))
	if target_map.is_empty() or target_map == "0":
		return true
	return target_map == _current_map_id()


func _current_map_id() -> String:
	var map_info = _map_data.get("map", {})
	if typeof(map_info) == TYPE_DICTIONARY:
		return String(map_info.get("id", ""))
	return ""


func _effect_position(object_effect: Dictionary) -> Vector2i:
	var position = object_effect.get("position", [])
	if typeof(position) == TYPE_VECTOR2I:
		return position
	if typeof(position) == TYPE_ARRAY and position.size() >= 2:
		return Vector2i(int(position[0]), int(position[1]))
	return Vector2i(-1, -1)


func _object_event_position(object_event: Dictionary) -> Vector2i:
	var position = object_event.get("position", null)
	if typeof(position) == TYPE_VECTOR2I:
		return position
	return Vector2i(
		int(object_event.get("x", 0)),
		int(object_event.get("y", 0))
	)


func _set_object_event_position(object_event: Dictionary, position: Vector2i) -> void:
	object_event["position"] = position
	object_event["x"] = position.x
	object_event["y"] = position.y


func _object_event_template_position(object_event: Dictionary) -> Vector2i:
	var position = object_event.get("template_position", null)
	if typeof(position) == TYPE_VECTOR2I:
		return position
	return Vector2i(
		int(object_event.get("template_x", object_event.get("x", 0))),
		int(object_event.get("template_y", object_event.get("y", 0)))
	)


func _object_event_has_flag(object_event: Dictionary) -> bool:
	var flag := String(object_event.get("flag", "0"))
	return not flag.is_empty() and flag != "0"


func _object_event_flag_is_set(object_event: Dictionary, game_state: Node) -> bool:
	if not _object_event_has_flag(object_event):
		return false

	var flag := String(object_event.get("flag", "0"))
	if game_state != null and game_state.has_method("is_flag_set"):
		return bool(game_state.is_flag_set(flag))
	if is_inside_tree():
		var root_game_state = get_node_or_null("/root/GameState")
		if root_game_state != null and root_game_state.has_method("is_flag_set"):
			return bool(root_game_state.is_flag_set(flag))
	return false


func _set_object_flag(object_event: Dictionary, game_state: Node, enabled: bool) -> void:
	if not _object_event_has_flag(object_event):
		return

	var flag := String(object_event.get("flag", "0"))
	if game_state == null:
		return
	if enabled and game_state.has_method("set_flag"):
		game_state.set_flag(flag, true)
	elif not enabled and game_state.has_method("clear_flag"):
		game_state.clear_flag(flag)


func _rebuild_object_event_position_index() -> void:
	_object_events_by_position = {}
	for object_event in _object_events:
		if typeof(object_event) != TYPE_DICTIONARY:
			continue
		_add_event_at(_object_events_by_position, _object_event_position(object_event), object_event)


func _index_object_event_by_local_id(object_event: Dictionary) -> void:
	var local_id := String(object_event.get("local_id", ""))
	if local_id.is_empty():
		return
	_object_events_by_local_id[local_id] = object_event


func _record_applied_movement(
	summary: Dictionary,
	target: String,
	movement_label: String,
	from_position: Vector2i,
	to_position: Vector2i,
	final_facing: String
) -> void:
	summary["applied"].append({
		"target": target,
		"movement_label": movement_label,
		"from": from_position,
		"to": to_position,
		"final_facing": final_facing,
	})


func _record_skipped_movement(
	summary: Dictionary,
	reason: String,
	target: String,
	movement_label: String,
	delta: Vector2i,
	next_position := Vector2i.ZERO
) -> void:
	summary["skipped"].append({
		"reason": reason,
		"target": target,
		"movement_label": movement_label,
		"delta": delta,
		"to": next_position,
	})


func _record_applied_object_effect(
	summary: Dictionary,
	object_effect: Dictionary,
	from_position: Vector2i,
	to_position: Vector2i,
	detail: Dictionary = {}
) -> void:
	var entry := {
		"op": String(object_effect.get("op", "")),
		"line": int(object_effect.get("line", 0)),
		"target": String(object_effect.get("target", "")),
		"from": from_position,
		"to": to_position,
	}
	for key in detail:
		entry[key] = detail[key]
	summary["applied"].append(entry)


func _record_skipped_object_effect(
	summary: Dictionary,
	reason: String,
	target: String,
	op: String,
	line: int
) -> void:
	summary["skipped"].append({
		"reason": reason,
		"op": op,
		"line": line,
		"target": target,
	})


func _array_or_empty(value) -> Array:
	return value if typeof(value) == TYPE_ARRAY else []


func _cell_key(cell: Vector2i) -> String:
	return "%d,%d" % [cell.x, cell.y]


func _events_at(index: Dictionary, cell: Vector2i) -> Array:
	var events = index.get(_cell_key(cell), [])
	return events.duplicate(true) if typeof(events) == TYPE_ARRAY else []


func _add_event_at(index: Dictionary, cell: Vector2i, event: Dictionary) -> void:
	var key := _cell_key(cell)
	if not index.has(key):
		index[key] = []
	index[key].append(event)


func _interaction_target(
	interaction_type: String,
	position: Vector2i,
	event: Dictionary,
	script: String
) -> Dictionary:
	return {
		"type": interaction_type,
		"position": position,
		"event": event,
		"script": script,
	}


func _grid_value(grid: Array, cell: Vector2i, default_value: int) -> int:
	if cell.y < 0 or cell.y >= grid.size():
		return default_value

	var row = grid[cell.y]
	if typeof(row) != TYPE_ARRAY or cell.x < 0 or cell.x >= row.size():
		return default_value

	return int(row[cell.x])
