extends Node

signal map_changed(map_data: Dictionary, tileset_data: Dictionary, map_size: Vector2i)
signal object_events_changed(object_events: Array)
signal player_position_changed(grid_position: Vector2i)

const COLLISION_NONE := 0
const COLLISION_IMPASSABLE := 1
const ELEVATION_INVALID := -1
const ELEVATION_TRANSITION := 0
const LOCALID_PLAYER := "LOCALID_PLAYER"
const MAPGRID_METATILE_ID_MASK := 0x03FF
const MAPGRID_COLLISION_MASK := 0x0C00
const MAPGRID_COLLISION_SHIFT := 10
const MAPGRID_ELEVATION_SHIFT := 12
const MAP_OFFSET := 7
const MAPGRID_IMPASSABLE_COLLISION := MAPGRID_COLLISION_MASK >> MAPGRID_COLLISION_SHIFT
const OBJECT_SAVE_TRACE := [
	"src/load_save.c:SaveObjectEvents",
	"src/load_save.c:LoadObjectEvents",
	"src/load_save.c:CopyPartyAndObjectsToSave",
	"src/load_save.c:CopyPartyAndObjectsFromSave",
]
const CURRENT_MAP_DEBUG_SOURCE_TRACE := [
	"data/maps/*/map.json",
	"data/layouts/layouts.json",
	"src/data/tilesets/headers.h",
	"include/constants/metatile_behaviors.h",
	"src/fieldmap.c:InitMap",
	"src/event_object_movement.c:TrySpawnObjectEvents",
]

var _map_data: Dictionary = {}
var _tileset_data: Dictionary = {}
var _data_registry: Node = null
var _map_size := Vector2i.ZERO
var _block_ids: Array = []
var _raw_grid: Array = []
var _collision_grid: Array = []
var _elevation_grid: Array = []
var _border_grid: Dictionary = {}
var _metatile_attributes: Dictionary = {}
var _door_animations_by_metatile_id: Dictionary = {}
var _connections: Array = []
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
	_data_registry = registry

	configure_from_data(
		registry.get_start_map_data(),
		registry.get_start_tileset_data(),
		registry.get_start_map_size()
	)


func configure_data_registry(data_registry: Node) -> void:
	_data_registry = data_registry


func configure_from_data(
	map_data: Dictionary,
	tileset_data: Dictionary,
	fallback_map_size := Vector2i.ZERO
) -> void:
	_map_data = map_data.duplicate(true)
	_tileset_data = tileset_data
	_map_size = fallback_map_size
	_block_ids = []
	_raw_grid = []
	_collision_grid = []
	_elevation_grid = []
	_border_grid = {}
	_metatile_attributes = {}
	_door_animations_by_metatile_id = {}
	_connections = []
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
			_raw_grid = _array_or_empty(map_grid.get("raw", []))
			_collision_grid = _array_or_empty(map_grid.get("collision", []))
			_elevation_grid = _array_or_empty(map_grid.get("elevation", []))
		var border_grid = _map_data.get("border_grid", {})
		if typeof(border_grid) == TYPE_DICTIONARY:
			_border_grid = border_grid

	_index_metatile_attributes()
	_index_door_animations()
	_index_connections()
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


func get_current_map_id() -> String:
	return _current_map_id()


func get_metatile_id_at(cell: Vector2i) -> int:
	return _map_or_edge_grid_value("metatile_ids", _block_ids, cell, -1)


func get_collision_at(cell: Vector2i) -> int:
	if _collision_grid.is_empty():
		return COLLISION_NONE
	return _map_or_edge_grid_value("collision", _collision_grid, cell, COLLISION_IMPASSABLE)


func get_elevation_at(cell: Vector2i) -> int:
	return _map_or_edge_grid_value("elevation", _elevation_grid, cell, ELEVATION_INVALID)


func get_metatile_attribute(metatile_id: int) -> Dictionary:
	if _metatile_attributes.has(metatile_id):
		var attribute = _metatile_attributes[metatile_id]
		if typeof(attribute) == TYPE_DICTIONARY:
			return attribute
	return {}


func get_metatile_behavior_at(cell: Vector2i) -> int:
	return int(get_metatile_attribute(get_metatile_id_at(cell)).get("behavior", -1))


func get_metatile_behavior_name_at(cell: Vector2i) -> String:
	return String(get_metatile_attribute(get_metatile_id_at(cell)).get("behavior_name", ""))


func get_metatile_layer_type_at(cell: Vector2i) -> int:
	return int(get_metatile_attribute(get_metatile_id_at(cell)).get("layer_type", -1))


func get_door_animation_for_metatile(metatile_id: int) -> Dictionary:
	var animation = _door_animations_by_metatile_id.get(metatile_id, {})
	return animation.duplicate(true) if typeof(animation) == TYPE_DICTIONARY else {}


func get_door_animation_at(cell: Vector2i) -> Dictionary:
	return get_door_animation_for_metatile(get_metatile_id_at(cell))


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


func export_object_event_state(game_state: Node = null) -> Dictionary:
	var records: Array = []
	for object_event in _object_events:
		if typeof(object_event) != TYPE_DICTIONARY:
			continue
		var position := _object_event_position(object_event)
		var template_position := _object_event_template_position(object_event)
		var flag := String(object_event.get("flag", "0"))
		records.append({
			"index": int(object_event.get("index", records.size())),
			"local_id": String(object_event.get("local_id", "")),
			"source_local_id": int(object_event.get("source_local_id", 0)),
			"position": _vector2i_to_save(position),
			"x": position.x,
			"y": position.y,
			"template_position": _vector2i_to_save(template_position),
			"template_x": template_position.x,
			"template_y": template_position.y,
			"movement_type": String(object_event.get("movement_type", "")),
			"template_movement_type": String(object_event.get("template_movement_type", "")),
			"facing_direction": String(object_event.get("facing_direction", "")),
			"runtime_hidden": bool(object_event.get("runtime_hidden", false)),
			"flag": flag,
			"flag_is_set": _object_event_flag_is_set(object_event, game_state),
			"active": bool(object_event.get("active", true)),
		})
	return {
		"status": "ok",
		"map_id": _current_map_id(),
		"object_events_count": records.size(),
		"object_events": records,
		"source_trace": OBJECT_SAVE_TRACE.duplicate(),
	}


func apply_object_event_state(state: Dictionary, game_state: Node = null) -> Dictionary:
	var state_map_id := String(state.get("map_id", ""))
	var current_map_id := _current_map_id()
	if not state_map_id.is_empty() and not current_map_id.is_empty() and state_map_id != current_map_id:
		return {
			"status": "blocked",
			"block_reason": "map_mismatch",
			"state_map_id": state_map_id,
			"current_map_id": current_map_id,
			"source_trace": OBJECT_SAVE_TRACE.duplicate(),
		}

	var summary := {
		"status": "ok",
		"applied": [],
		"skipped": [],
		"object_events_changed": false,
		"source_trace": OBJECT_SAVE_TRACE.duplicate(),
	}
	for record in _array_or_empty(state.get("object_events", [])):
		if typeof(record) != TYPE_DICTIONARY:
			continue
		var object_event := _resolve_object_event_state_target(record)
		if object_event.is_empty():
			summary["skipped"].append({
				"reason": "missing_object_event",
				"local_id": String(record.get("local_id", "")),
				"source_local_id": int(record.get("source_local_id", 0)),
				"index": int(record.get("index", -1)),
			})
			continue
		_apply_object_event_state_record(object_event, record, game_state)
		summary["applied"].append({
			"local_id": String(object_event.get("local_id", "")),
			"source_local_id": int(object_event.get("source_local_id", 0)),
			"position": _vector2i_to_save(_object_event_position(object_event)),
			"runtime_hidden": bool(object_event.get("runtime_hidden", false)),
		})
		summary["object_events_changed"] = true

	if bool(summary["object_events_changed"]):
		_rebuild_object_event_position_index()
		object_events_changed.emit(get_object_events())
	return summary


func get_bg_events() -> Array:
	return _bg_events.duplicate(true)


func get_bg_events_at(cell: Vector2i) -> Array:
	return _events_at(_bg_events_by_position, cell)


func get_warp_events() -> Array:
	return _warp_events.duplicate(true)


func get_warp_events_at(cell: Vector2i) -> Array:
	return _events_at(_warp_events_by_position, cell)


func get_warp_event_target(cell: Vector2i) -> Dictionary:
	var elevation := get_elevation_at(cell)
	for warp_event in get_warp_events_at(cell):
		if typeof(warp_event) != TYPE_DICTIONARY:
			continue
		if not _warp_event_matches_elevation(warp_event, elevation):
			continue
		return _interaction_target("warp_event", cell, warp_event, "warp")
	return {}


func get_connection_target(cell: Vector2i) -> Dictionary:
	var connection := _connection_for_cell(cell)
	if connection.is_empty():
		return {}

	var event_data := connection.duplicate(true)
	var destination_map_id := String(event_data.get("map", ""))
	var destination_position := _connection_destination_position(event_data, cell)
	event_data["dest_map"] = destination_map_id
	event_data["dest_position"] = destination_position
	event_data["source_map"] = _current_map_id()
	event_data["source_position"] = _edge_source_position(cell)
	event_data["trigger_position"] = cell
	return _interaction_target("map_connection", cell, event_data, "map_connection")


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
		var origin_warp_target := get_warp_event_target(origin)
		if not origin_warp_target.is_empty():
			return origin_warp_target

	var target_warp_target := get_warp_event_target(target_cell)
	if not target_warp_target.is_empty():
		return target_warp_target

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
		"behavior_name": get_metatile_attribute(metatile_id).get("behavior_name", ""),
		"layer_type": get_metatile_attribute(metatile_id).get("layer_type", -1),
		"occupied": not object_events_at_cell.is_empty(),
		"object_event_count": object_events_at_cell.size(),
		"bg_event_count": bg_events_at_cell.size(),
		"warp_event_count": warp_events_at_cell.size(),
		"coord_event_count": coord_events_at_cell.size(),
		"passable": can_enter_cell(cell),
	}


func get_current_map_runtime_debug_snapshot(game_state: Node = null) -> Dictionary:
	var source_trace := CURRENT_MAP_DEBUG_SOURCE_TRACE.duplicate()
	if _map_data.is_empty():
		return {
			"schema_version": 1,
			"dump_kind": "overworld_current_map_runtime_debug_snapshot",
			"status": "missing_map_data",
			"debug_only": true,
			"source_trace": source_trace,
		}

	var map_info = _map_data.get("map", {})
	map_info = map_info if typeof(map_info) == TYPE_DICTIONARY else {}
	var layout_info = _map_data.get("layout", {})
	layout_info = layout_info if typeof(layout_info) == TYPE_DICTIONARY else {}
	var source_info = _map_data.get("source", {})
	source_info = source_info if typeof(source_info) == TYPE_DICTIONARY else {}
	var map_tilesets = _map_data.get("tilesets", {})
	map_tilesets = map_tilesets if typeof(map_tilesets) == TYPE_DICTIONARY else {}
	var generated_tilesets = _tileset_data.get("tilesets", {})
	generated_tilesets = generated_tilesets if typeof(generated_tilesets) == TYPE_DICTIONARY else {}
	var atlas_info = _tileset_data.get("atlas", {})
	atlas_info = atlas_info if typeof(atlas_info) == TYPE_DICTIONARY else {}
	for source_key in ["map_json", "map_script", "layouts_json", "blockdata", "border"]:
		var source_path := String(source_info.get(source_key, ""))
		if not source_path.is_empty() and not source_trace.has(source_path):
			source_trace.append(source_path)

	var visible_object_count := _visible_object_event_count_for_debug(game_state)
	var object_count := _object_events.size()
	var counts := {
		"object": object_count,
		"visible_object": visible_object_count,
		"hidden_object": max(0, object_count - visible_object_count),
		"warp": _warp_events.size(),
		"coord_event": _coord_events.size(),
		"bg_event": _bg_events.size(),
		"connection": _connections.size(),
		"door_animation": _door_animations_by_metatile_id.size(),
		"metatile_attribute": _metatile_attributes.size(),
	}
	return {
		"schema_version": 1,
		"dump_kind": "overworld_current_map_runtime_debug_snapshot",
		"status": "ok",
		"debug_only": true,
		"map_id": _current_map_id(),
		"map_name": String(map_info.get("name", "")),
		"layout_id": String(layout_info.get("id", "")),
		"layout_name": String(layout_info.get("name", "")),
		"map_size": {"x": _map_size.x, "y": _map_size.y},
		"tileset_pair": {
			"primary": String(layout_info.get("primary_tileset", "")),
			"secondary": String(layout_info.get("secondary_tileset", "")),
		},
		"tilesets": {
			"map": map_tilesets.duplicate(true),
			"generated": generated_tilesets.duplicate(true),
		},
		"atlas_image": String(atlas_info.get("image", atlas_info.get("image_project_path", ""))),
		"map_type": String(map_info.get("map_type", "")),
		"weather": String(map_info.get("weather", "")),
		"music": String(map_info.get("music", "")),
		"region_map_section": String(map_info.get("region_map_section", "")),
		"battle_scene": String(map_info.get("battle_scene", "")),
		"object_count": counts["object"],
		"visible_object_count": counts["visible_object"],
		"hidden_object_count": counts["hidden_object"],
		"warp_count": counts["warp"],
		"coord_event_count": counts["coord_event"],
		"bg_event_count": counts["bg_event"],
		"connection_count": counts["connection"],
		"door_animation_count": counts["door_animation"],
		"counts": counts,
		"source": source_info.duplicate(true),
		"source_trace": source_trace,
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


func sync_object_events_to_templates_for_map_load(targets: Array = []) -> Dictionary:
	var summary := {
		"status": "ok",
		"targets": [],
		"applied": [],
		"skipped": [],
		"unchanged": [],
		"object_events_changed": false,
		"source_trace": [
			"src/overworld.c:LoadMapFromWarp/LoadMapFromCameraTransition",
			"src/script.c:RunOnTransitionMapScript",
			"src/scrcmd.c:ScrCmd_setobjectxyperm",
		],
	}
	var unique_targets := []
	for target_value in targets:
		var target := String(target_value)
		if target.is_empty() or unique_targets.has(target):
			continue
		unique_targets.append(target)
	summary["targets"] = unique_targets

	for target in unique_targets:
		if target == LOCALID_PLAYER:
			_record_skipped_object_effect(summary, "player_target_unsupported", target, "map_load_template_sync", 0)
			continue

		var object_event := get_object_event_by_local_id(target, true)
		if object_event.is_empty():
			_record_skipped_object_effect(summary, "missing_object_event", target, "map_load_template_sync", 0)
			continue

		var template_position := _object_event_template_position(object_event)
		if not is_within_bounds(template_position):
			_record_skipped_object_effect(summary, "out_of_bounds", target, "map_load_template_sync", 0)
			continue

		var current_position := _object_event_position(object_event)
		if current_position == template_position:
			summary["unchanged"].append({
				"target": target,
				"position": current_position,
			})
			continue

		_set_object_event_position(object_event, template_position)
		summary["object_events_changed"] = true
		summary["applied"].append({
			"op": "map_load_template_sync",
			"target": target,
			"from": current_position,
			"to": template_position,
		})

	if bool(summary["object_events_changed"]):
		_rebuild_object_event_position_index()
		object_events_changed.emit(get_object_events())

	return summary


func apply_script_field_effects(field_effects: Array) -> Dictionary:
	var summary := {
		"applied": [],
		"skipped": [],
		"map_changed": false,
	}

	for field_effect in field_effects:
		if typeof(field_effect) != TYPE_DICTIONARY:
			_record_skipped_field_effect(summary, "invalid_field_effect", "", 0, Vector2i(-1, -1))
			continue

		var effect: Dictionary = field_effect
		var op := String(effect.get("op", ""))
		if op != "setmetatile":
			continue
		_apply_setmetatile_effect(summary, effect)

	if bool(summary["map_changed"]):
		map_changed.emit(_map_data, _tileset_data, _map_size)

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


func _index_door_animations() -> void:
	if _tileset_data.is_empty():
		return

	var door_animations = _tileset_data.get("door_animations", {})
	if typeof(door_animations) != TYPE_DICTIONARY:
		return

	var animations = door_animations.get("animations", [])
	if typeof(animations) != TYPE_ARRAY:
		return

	for animation in animations:
		if typeof(animation) != TYPE_DICTIONARY:
			continue
		var metatile_id := int(animation.get("metatile_id", -1))
		if metatile_id < 0:
			continue
		_door_animations_by_metatile_id[metatile_id] = animation


func _index_connections() -> void:
	var connections = _map_data.get("connections", [])
	if typeof(connections) != TYPE_ARRAY:
		var events = _map_data.get("events", {})
		if typeof(events) == TYPE_DICTIONARY:
			connections = events.get("connections", [])

	if typeof(connections) != TYPE_ARRAY:
		return

	for source_connection in connections:
		if typeof(source_connection) != TYPE_DICTIONARY:
			continue
		var connection = source_connection.duplicate(true)
		connection["direction"] = _normalize_connection_direction(String(connection.get("direction", "")))
		connection["offset"] = int(connection.get("offset", 0))
		if String(connection.get("direction", "")).is_empty():
			continue
		if String(connection.get("map", "")).is_empty():
			continue
		_connections.append(connection)


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
		object_event["source_local_id"] = index + 1
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


func _visible_object_event_count_for_debug(game_state: Node) -> int:
	var count := 0
	for object_event in _object_events:
		if _is_object_event_visible_for_debug(object_event, game_state):
			count += 1
	return count


func _is_object_event_visible_for_debug(object_event: Dictionary, game_state: Node) -> bool:
	if bool(object_event.get("runtime_hidden", false)):
		return false

	var flag := String(object_event.get("flag", "0"))
	if flag.is_empty() or flag == "0":
		return true

	if game_state != null and game_state.has_method("is_flag_set"):
		return not bool(game_state.is_flag_set(flag))

	return _is_object_event_visible(object_event)


func _coord_event_matches_elevation(coord_event: Dictionary, elevation: int) -> bool:
	var event_elevation := int(coord_event.get("elevation", ELEVATION_INVALID))
	return event_elevation == elevation or event_elevation == ELEVATION_TRANSITION


func _warp_event_matches_elevation(warp_event: Dictionary, elevation: int) -> bool:
	var event_elevation := int(warp_event.get("elevation", ELEVATION_INVALID))
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


func _apply_setmetatile_effect(summary: Dictionary, field_effect: Dictionary) -> void:
	var line := int(field_effect.get("line", 0))
	var position := _effect_position(field_effect)
	if not is_within_bounds(position):
		_record_skipped_field_effect(summary, "out_of_bounds", "setmetatile", line, position)
		return

	var metatile_id := int(field_effect.get("metatile_id", -1))
	if metatile_id < 0:
		_record_skipped_field_effect(summary, "missing_metatile_id", "setmetatile", line, position)
		return
	if not _metatile_attributes.has(metatile_id):
		_record_skipped_field_effect(summary, "unknown_metatile_id", "setmetatile", line, position)
		return

	var previous_metatile_id := get_metatile_id_at(position)
	var previous_collision := get_collision_at(position)
	var elevation := get_elevation_at(position)
	if elevation == ELEVATION_INVALID:
		elevation = 0

	var collision := int(field_effect.get("collision", COLLISION_NONE))
	_set_grid_value(_block_ids, position, metatile_id)
	_set_grid_value(_collision_grid, position, collision)
	_set_grid_value(_elevation_grid, position, elevation)
	_set_grid_value(_raw_grid, position, _pack_map_grid_value(metatile_id, collision, elevation))
	_sync_map_grid_data(position, metatile_id, collision, elevation)

	summary["map_changed"] = true
	_record_applied_field_effect(summary, field_effect, position, {
		"previous_metatile_id": previous_metatile_id,
		"previous_collision": previous_collision,
		"metatile_id": metatile_id,
		"collision": collision,
		"elevation": elevation,
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


func _set_object_event_template_position(object_event: Dictionary, position: Vector2i) -> void:
	object_event["template_position"] = position
	object_event["template_x"] = position.x
	object_event["template_y"] = position.y


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


func _resolve_object_event_state_target(record: Dictionary) -> Dictionary:
	var local_id := String(record.get("local_id", ""))
	if not local_id.is_empty():
		var event_by_local_id := get_object_event_by_local_id(local_id, true)
		if not event_by_local_id.is_empty():
			return event_by_local_id
	var source_local_id := int(record.get("source_local_id", 0))
	if source_local_id > 0:
		var event_by_source_id := get_object_event_by_local_id(str(source_local_id), true)
		if not event_by_source_id.is_empty():
			return event_by_source_id
	var index := int(record.get("index", -1))
	if index >= 0 and index < _object_events.size():
		var event_by_index = _object_events[index]
		if typeof(event_by_index) == TYPE_DICTIONARY:
			return event_by_index
	return {}


func _apply_object_event_state_record(object_event: Dictionary, record: Dictionary, game_state: Node) -> void:
	var position := _vector2i_from_save(record.get("position", {}), _object_event_position(object_event))
	if is_within_bounds(position):
		_set_object_event_position(object_event, position)
	var template_position := _vector2i_from_save(record.get("template_position", {}), _object_event_template_position(object_event))
	if is_within_bounds(template_position):
		_set_object_event_template_position(object_event, template_position)
	if record.has("movement_type"):
		object_event["movement_type"] = String(record.get("movement_type", ""))
	if record.has("template_movement_type"):
		object_event["template_movement_type"] = String(record.get("template_movement_type", ""))
	if record.has("facing_direction"):
		var facing_direction := String(record.get("facing_direction", ""))
		if facing_direction.is_empty():
			object_event.erase("facing_direction")
		else:
			object_event["facing_direction"] = facing_direction
	if record.has("runtime_hidden"):
		object_event["runtime_hidden"] = bool(record.get("runtime_hidden", false))
	if record.has("active"):
		object_event["active"] = bool(record.get("active", true))
	if record.has("flag_is_set"):
		_set_object_flag(object_event, game_state, bool(record.get("flag_is_set", false)))


func _rebuild_object_event_position_index() -> void:
	_object_events_by_position = {}
	for object_event in _object_events:
		if typeof(object_event) != TYPE_DICTIONARY:
			continue
		_add_event_at(_object_events_by_position, _object_event_position(object_event), object_event)


func _vector2i_to_save(value: Vector2i) -> Dictionary:
	return {"x": value.x, "y": value.y}


func _vector2i_from_save(value, default_value: Vector2i) -> Vector2i:
	if typeof(value) == TYPE_DICTIONARY:
		return Vector2i(int(value.get("x", default_value.x)), int(value.get("y", default_value.y)))
	if typeof(value) == TYPE_ARRAY and value.size() >= 2:
		return Vector2i(int(value[0]), int(value[1]))
	if typeof(value) == TYPE_VECTOR2I:
		return value
	return default_value


func _index_object_event_by_local_id(object_event: Dictionary) -> void:
	var local_id := String(object_event.get("local_id", ""))
	if not local_id.is_empty():
		_object_events_by_local_id[local_id] = object_event

	var source_local_id := int(object_event.get("source_local_id", 0))
	if source_local_id > 0:
		_object_events_by_local_id[str(source_local_id)] = object_event


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


func _record_applied_field_effect(
	summary: Dictionary,
	field_effect: Dictionary,
	position: Vector2i,
	detail: Dictionary = {}
) -> void:
	var entry := {
		"op": String(field_effect.get("op", "")),
		"line": int(field_effect.get("line", 0)),
		"position": position,
	}
	for key in detail:
		entry[key] = detail[key]
	summary["applied"].append(entry)


func _record_skipped_field_effect(
	summary: Dictionary,
	reason: String,
	op: String,
	line: int,
	position: Vector2i
) -> void:
	summary["skipped"].append({
		"reason": reason,
		"op": op,
		"line": line,
		"position": position,
	})


func _pack_map_grid_value(metatile_id: int, collision: int, elevation: int) -> int:
	return (
		(metatile_id & MAPGRID_METATILE_ID_MASK)
		| ((collision & 0x03) << MAPGRID_COLLISION_SHIFT)
		| ((elevation & 0x0F) << MAPGRID_ELEVATION_SHIFT)
	)


func _sync_map_grid_data(position: Vector2i, metatile_id: int, collision: int, elevation: int) -> void:
	_set_map_data_grid_value("block_ids", position, metatile_id)
	var map_grid = _map_data.get("map_grid", {})
	if typeof(map_grid) != TYPE_DICTIONARY:
		map_grid = {}
		_map_data["map_grid"] = map_grid
	_set_nested_grid_value(map_grid, "raw", position, _pack_map_grid_value(metatile_id, collision, elevation))
	_set_nested_grid_value(map_grid, "collision", position, collision)
	_set_nested_grid_value(map_grid, "elevation", position, elevation)


func _set_map_data_grid_value(key: String, position: Vector2i, value: int) -> void:
	var grid = _map_data.get(key, [])
	if typeof(grid) != TYPE_ARRAY:
		return
	_set_grid_value(grid, position, value)


func _set_nested_grid_value(parent: Dictionary, key: String, position: Vector2i, value: int) -> void:
	var grid = parent.get(key, [])
	if typeof(grid) != TYPE_ARRAY:
		return
	_set_grid_value(grid, position, value)


func _set_grid_value(grid: Array, position: Vector2i, value: int) -> void:
	if position.y < 0 or position.y >= grid.size():
		return
	var row = grid[position.y]
	if typeof(row) != TYPE_ARRAY:
		return
	if position.x < 0 or position.x >= row.size():
		return
	row[position.x] = value


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


func _map_or_edge_grid_value(grid_name: String, primary_grid: Array, cell: Vector2i, default_value: int) -> int:
	if is_within_bounds(cell):
		return _grid_value(primary_grid, cell, default_value)

	var connected := _connected_grid_value(grid_name, cell)
	if bool(connected.get("found", false)):
		return int(connected.get("value", default_value))

	var border := _border_grid_value(grid_name, cell)
	if bool(border.get("found", false)):
		return int(border.get("value", default_value))

	return default_value


func _connected_grid_value(grid_name: String, cell: Vector2i) -> Dictionary:
	var connection := _connection_for_cell(cell)
	if connection.is_empty():
		return {"found": false}

	var destination_map_id := String(connection.get("map", ""))
	var connected_map_data := _connected_map_data(destination_map_id)
	if connected_map_data.is_empty():
		return {"found": false}

	var destination_position := _connection_destination_position(connection, cell)
	var destination_size := _map_size_from_data(connected_map_data)
	if not _is_cell_in_size(destination_position, destination_size):
		return {"found": false}

	var grid := _map_grid_from_data(connected_map_data, grid_name)
	if grid.is_empty():
		return {"found": false}

	return _grid_cell_value(grid, destination_position)


func _border_grid_value(grid_name: String, cell: Vector2i) -> Dictionary:
	if _border_grid.is_empty():
		return {"found": false}

	var values = _border_grid.get(grid_name, [])
	if typeof(values) != TYPE_ARRAY and grid_name == "metatile_ids":
		values = _border_grid.get("block_ids", [])
	if typeof(values) != TYPE_ARRAY or values.is_empty():
		return {"found": false}

	var dimensions := _border_grid_dimensions(values)
	if dimensions.x <= 0 or dimensions.y <= 0:
		return {"found": false}

	var index := _border_grid_index(cell, dimensions.x, dimensions.y)
	if index < 0 or index >= values.size():
		return {"found": false}
	var value := int(values[index])
	if grid_name == "collision":
		value = MAPGRID_IMPASSABLE_COLLISION
	return {
		"found": true,
		"value": value,
	}


func _border_grid_dimensions(values: Array) -> Vector2i:
	var width := int(_border_grid.get("width", 0))
	var height := int(_border_grid.get("height", 0))
	if width <= 0:
		width = 2 if values.size() >= 2 else 1
	if height <= 0:
		height = int(values.size() / width)
		if values.size() % width != 0:
			height += 1
	return Vector2i(width, height)


func _border_grid_index(cell: Vector2i, width: int, height: int) -> int:
	var rule := String(_border_grid.get("source_index_rule", ""))
	var map_offset := int(_border_grid.get("map_offset", MAP_OFFSET))
	if rule == "emerald_2x2_parity":
		return (
			_positive_mod(cell.y + map_offset + 1, height) * width
			+ _positive_mod(cell.x + map_offset + 1, width)
		)
	if rule == "frlg_wrapped_border":
		return _positive_mod(cell.y, height) * width + _positive_mod(cell.x, width)
	return _positive_mod(cell.y, height) * width + _positive_mod(cell.x, width)


func _connection_for_cell(cell: Vector2i) -> Dictionary:
	if is_within_bounds(cell):
		return {}

	for connection in _connections:
		if typeof(connection) != TYPE_DICTIONARY:
			continue
		if _connection_matches_cell(connection, cell):
			return connection
	return {}


func _connection_matches_cell(connection: Dictionary, cell: Vector2i) -> bool:
	var direction := String(connection.get("direction", ""))
	var destination_size := _map_size_for_connection(connection)
	if destination_size == Vector2i.ZERO:
		destination_size = _map_size
	var offset := int(connection.get("offset", 0))

	match direction:
		"north":
			return cell.y < 0 and _is_axis_in_destination(cell.x - offset, destination_size.x)
		"south":
			return cell.y >= _map_size.y and _is_axis_in_destination(cell.x - offset, destination_size.x)
		"west":
			return cell.x < 0 and _is_axis_in_destination(cell.y - offset, destination_size.y)
		"east":
			return cell.x >= _map_size.x and _is_axis_in_destination(cell.y - offset, destination_size.y)
	return false


func _connection_destination_position(connection: Dictionary, cell: Vector2i) -> Vector2i:
	var direction := String(connection.get("direction", ""))
	var destination_size := _map_size_for_connection(connection)
	if destination_size == Vector2i.ZERO:
		destination_size = _map_size
	var offset := int(connection.get("offset", 0))

	match direction:
		"north":
			return Vector2i(cell.x - offset, destination_size.y + cell.y)
		"south":
			return Vector2i(cell.x - offset, cell.y - _map_size.y)
		"west":
			return Vector2i(destination_size.x + cell.x, cell.y - offset)
		"east":
			return Vector2i(cell.x - _map_size.x, cell.y - offset)
	return Vector2i(-1, -1)


func _edge_source_position(cell: Vector2i) -> Vector2i:
	if _map_size == Vector2i.ZERO:
		return cell

	var x := cell.x
	var y := cell.y
	if x < 0:
		x = 0
	elif x >= _map_size.x:
		x = _map_size.x - 1
	if y < 0:
		y = 0
	elif y >= _map_size.y:
		y = _map_size.y - 1
	return Vector2i(x, y)


func _map_size_for_connection(connection: Dictionary) -> Vector2i:
	var map_data := _connected_map_data(String(connection.get("map", "")))
	if map_data.is_empty():
		return Vector2i.ZERO
	return _map_size_from_data(map_data)


func _connected_map_data(map_id: String) -> Dictionary:
	if map_id.is_empty() or _data_registry == null or not _data_registry.has_method("get_map_data"):
		return {}
	var map_data = _data_registry.get_map_data(map_id)
	return map_data if typeof(map_data) == TYPE_DICTIONARY else {}


func _map_size_from_data(map_data: Dictionary) -> Vector2i:
	var layout_info = map_data.get("layout", {})
	if typeof(layout_info) != TYPE_DICTIONARY:
		return Vector2i.ZERO
	return Vector2i(
		int(layout_info.get("width", 0)),
		int(layout_info.get("height", 0))
	)


func _map_grid_from_data(map_data: Dictionary, grid_name: String) -> Array:
	if grid_name == "metatile_ids" or grid_name == "block_ids":
		return _array_or_empty(map_data.get("block_ids", []))

	var map_grid = map_data.get("map_grid", {})
	if typeof(map_grid) != TYPE_DICTIONARY:
		return []
	return _array_or_empty(map_grid.get(grid_name, []))


func _grid_cell_value(grid: Array, cell: Vector2i) -> Dictionary:
	if cell.y < 0 or cell.y >= grid.size():
		return {"found": false}

	var row = grid[cell.y]
	if typeof(row) != TYPE_ARRAY or cell.x < 0 or cell.x >= row.size():
		return {"found": false}

	return {
		"found": true,
		"value": int(row[cell.x]),
	}


func _is_axis_in_destination(axis_value: int, destination_max: int) -> bool:
	return destination_max > 0 and axis_value >= 0 and axis_value < destination_max


func _is_cell_in_size(cell: Vector2i, size: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < size.x and cell.y < size.y


func _normalize_connection_direction(direction: String) -> String:
	var normalized := direction.to_lower()
	if normalized.begins_with("connection_"):
		normalized = normalized.replace("connection_", "")
	match normalized:
		"up", "north":
			return "north"
		"down", "south":
			return "south"
		"left", "west":
			return "west"
		"right", "east":
			return "east"
	return normalized


func _positive_mod(value: int, modulo: int) -> int:
	if modulo <= 0:
		return 0
	var result := value % modulo
	if result < 0:
		result += modulo
	return result


func _grid_value(grid: Array, cell: Vector2i, default_value: int) -> int:
	if cell.y < 0 or cell.y >= grid.size():
		return default_value

	var row = grid[cell.y]
	if typeof(row) != TYPE_ARRAY or cell.x < 0 or cell.x >= row.size():
		return default_value

	return int(row[cell.x])
