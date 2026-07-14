class_name PlatinumWorldStreamer
extends Node3D

signal initial_chunks_ready
signal initial_chunks_settled(ready: bool)
signal stream_error(message: String)

const CHUNK_SIZE := 32.0
const HEIGHT_STEP := 0.5
const MODEL_SCALE := 1.0 / 16.0
const DEFAULT_START_CELL := Vector2i(3, 27)
const DEFAULT_START_TILE := Vector2i(16, 16)
const USE_DESTINATION_DEFAULT_CELL := Vector2i(-1, -1)

const DEBUG_MATRIX_SETTING := "maizang/debug/matrix_id"
const DEBUG_AREA_SETTING := "maizang/debug/area_data_id"
const DEBUG_CELL_SETTING := "maizang/debug/matrix_cell"
const DEBUG_TILE_SETTING := "maizang/debug/map_tile"
const DebugDestinationResolver := preload("res://scripts/debug_destination_resolver.gd")
const DebugDestinationRequest := preload("res://scripts/debug_destination_request.gd")
const WorldTransitionRequest := preload("res://scripts/world_transition_request.gd")
const CollisionMap := preload("res://scripts/platinum_collision_map.gd")
const DOOR_MODEL_IDS := {
	66: true, 67: true, 68: true, 69: true, 70: true, 75: true, 128: true,
	246: true, 260: true, 298: true, 312: true, 313: true, 427: true, 438: true,
	441: true, 442: true, 444: true, 456: true, 484: true, 527: true,
}
const CURRENT_TRANSITION_DIRECTIONS := {
	0x5E: Vector2i.RIGHT,
	0x5F: Vector2i.LEFT,
	0x62: Vector2i.RIGHT,
	0x63: Vector2i.LEFT,
	0x65: Vector2i.DOWN,
	0x6C: Vector2i.RIGHT,
	0x6D: Vector2i.LEFT,
	0x6F: Vector2i.DOWN,
}
const CURRENT_AUTOMATIC_TRANSITIONS := {
	0x64: true,
	0x67: true,
	0x6A: true,
	0x6B: true,
	0x6E: true,
}

@export_file("*.json") var catalog_path := "res://assets/platinum/matrix_catalog.json"
@export_file("*.json") var manifest_path := "res://assets/platinum/matrix_0000/manifest.json"
@export var focus_path: NodePath
@export var map_animation_controller_path: NodePath
@export var field_texture_animation_controller_path: NodePath
@export_range(0, 8, 1) var load_radius := 1
@export_range(0, 10, 1) var prefetch_radius := 2
@export_range(1, 12, 1) var unload_radius := 3
@export_range(0.02, 1.0, 0.01) var stream_interval := 0.12

var _focus: Node3D
var _cells: Dictionary = {}
var _terrain_paths: Dictionary = {}
var _building_paths: Dictionary = {}
var _building_animations: Dictionary = {}
var _asset_states: Dictionary = {}
var _retained_asset_paths: Dictionary = {}
var _wanted_chunks: Dictionary = {}
var _loaded_chunks: Dictionary = {}
var _shared_materials: Dictionary = {}
var _warps_by_header_tile: Dictionary = {}
var _manifest_header_ids: Dictionary = {}
var _catalog_headers: Dictionary = {}
var _catalog_destinations: Dictionary = {}
var _map_prop_instances: Dictionary = {}
var _door_props_by_world_tile: Dictionary = {}
var _chunk_prop_ids: Dictionary = {}
var _chunk_field_texture_ids: Dictionary = {}
var _stream_accumulator := 0.0
var _last_focus_cell := Vector2i(1 << 20, 1 << 20)
var _initial_signal_sent := false
var _initial_chunks_are_settled := false
var _initial_chunks_succeeded := false
var _failed_asset_count := 0
var _material_replacement_count := 0
var _has_explicit_debug_destination := false
var _explicit_debug_destination: Dictionary = {}
var _configuration_error := false
var _matrix_id := -1
var _area_data_id := -1
var _start_cell := DEFAULT_START_CELL
var _start_tile := DEFAULT_START_TILE
var _start_world_position := Vector3.ZERO
var _start_facing := -1
var _current_header_id := -1
var _header_context_cell := USE_DESTINATION_DEFAULT_CELL
var _default_header_id := -1
var _manifest_variant := ""
var _world_transition_arrival: Dictionary = {}
var _arrival_escape_world_tile: Variant = null
var _shutdown_complete := false
var _collision_map := CollisionMap.new() as PlatinumCollisionMap
var _map_animation_controller: Node
var _field_texture_animation_controller: Node

@onready var _chunks_root: Node3D = $LoadedChunks


func _ready() -> void:
	add_to_group("platinum_world_streamer")
	_focus = get_node_or_null(focus_path) as Node3D
	_map_animation_controller = get_node_or_null(map_animation_controller_path)
	_field_texture_animation_controller = get_node_or_null(field_texture_animation_controller_path)
	if _focus == null:
		_fail("World streamer focus node was not found: %s" % focus_path)
		set_process(false)
		return
	if _field_texture_animation_controller == null:
		_fail("Field texture animation controller was not found: %s" % field_texture_animation_controller_path)
		set_process(false)
		return
	if not _resolve_debug_destination():
		set_process(false)
		return
	if not _load_manifest():
		set_process(false)
		return
	if not _place_focus_at_start():
		set_process(false)
		return
	_refresh_stream(true)


func _exit_tree() -> void:
	shutdown()


func _process(delta: float) -> void:
	_poll_asset_loads()
	_instantiate_ready_chunks()

	_stream_accumulator += delta
	if _stream_accumulator < stream_interval:
		return
	_stream_accumulator = 0.0
	_refresh_stream(false)


func get_stream_stats() -> Dictionary:
	var loading_assets := 0
	var loaded_assets := 0
	for record: Dictionary in _asset_states.values():
		match record.state:
			"loading":
				loading_assets += 1
			"loaded":
				loaded_assets += 1
	var stats := {
		"matrix": _matrix_id,
		"area": _area_data_id,
		"start": {
			"cell": {"x": _start_cell.x, "y": _start_cell.y},
			"tile": {"x": _start_tile.x, "y": _start_tile.y},
			"world": {
				"x": _start_world_position.x,
				"y": _start_world_position.y,
				"z": _start_world_position.z,
			},
		},
		"manifest_cells": _cells.size(),
		"wanted_chunks": _wanted_chunks.size(),
		"retained_assets": _retained_asset_paths.size(),
		"loaded_chunks": _loaded_chunks.size(),
		"loading_assets": loading_assets,
		"loaded_assets": loaded_assets,
		"failed_assets": _failed_asset_count,
		"shared_materials": _shared_materials.size(),
		"material_replacements": _material_replacement_count,
	}
	stats["collision"] = _collision_map.get_stats()
	if (
		is_instance_valid(_field_texture_animation_controller)
		and _field_texture_animation_controller.has_method("get_stats")
	):
		stats["field_texture_animations"] = _field_texture_animation_controller.call("get_stats")
	return stats


func configure_debug_destination(
	matrix_id: int,
	area_data_id: int = -1,
	matrix_cell: Vector2i = USE_DESTINATION_DEFAULT_CELL,
	map_tile: Vector2i = DEFAULT_START_TILE
) -> bool:
	if is_inside_tree():
		_fail("Debug destinations can only be configured before the streamer enters the scene tree.")
		return false
	_has_explicit_debug_destination = true
	_explicit_debug_destination = {
		"matrix": matrix_id,
		"area": area_data_id,
		"cell": matrix_cell,
		"has_cell": matrix_cell != USE_DESTINATION_DEFAULT_CELL,
		"tile": map_tile,
	}
	return true


func resolve_debug_destination_request(
	matrix_id: int,
	area_data_id: int = -1,
	matrix_cell: Vector2i = USE_DESTINATION_DEFAULT_CELL,
	map_tile: Vector2i = DEFAULT_START_TILE
) -> Dictionary:
	var request: Dictionary = DebugDestinationResolver.make_request(
		matrix_id, area_data_id, matrix_cell, map_tile
	)
	return DebugDestinationResolver.resolve(catalog_path, request)


func queue_debug_destination_request(normalized_request: Dictionary) -> Dictionary:
	if not is_inside_tree():
		return {
			"ok": false,
			"error": "Debug destination requests require a streamer inside the SceneTree.",
			"field": "request",
			"token": &"",
			"request": {},
		}
	return DebugDestinationRequest.queue(get_tree(), normalized_request)


func cancel_debug_destination_request(token: StringName) -> bool:
	if not is_inside_tree():
		return false
	return DebugDestinationRequest.cancel(get_tree(), token)


func queue_world_transition_request(normalized_request: Dictionary) -> Dictionary:
	if not is_inside_tree():
		return {
			"ok": false,
			"error": "World transitions require a streamer inside the SceneTree.",
			"field": "request",
			"token": &"",
			"request": {},
		}
	return WorldTransitionRequest.queue(get_tree(), normalized_request)


func cancel_world_transition_request(token: StringName) -> bool:
	return is_inside_tree() and WorldTransitionRequest.cancel(get_tree(), token)


func get_world_transition_arrival_request() -> Dictionary:
	return _world_transition_arrival.duplicate(true)


func resolve_warp_transition_request(
	origin: Vector3,
	direction: Vector2i,
	special_result: Dictionary
) -> Dictionary:
	if (
		direction not in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
		or String(special_result.get("disposition", "")) != "special"
		or String(special_result.get("action", "")) != "transition"
	):
		return _warp_error("The player action is not a normalized map transition.")
	var source_cell := _world_to_cell(origin)
	if not _cells.has(source_cell):
		return _warp_error("The player is outside an occupied matrix cell.")
	var source_header := _header_for_cell(source_cell)
	if source_header < 0:
		return _warp_error("The current MapHeader is unavailable.")
	var origin_tile := Vector2i(floori(origin.x), floori(origin.z))
	var adjacent_tile := origin_tile + direction
	var current_behavior_value: Variant = get_tile_behavior(
		source_cell,
		origin_tile - source_cell * int(CHUNK_SIZE)
	)
	var target_cell := Vector2i(
		floori(float(adjacent_tile.x) / CHUNK_SIZE),
		floori(float(adjacent_tile.y) / CHUNK_SIZE)
	)
	var target_behavior_value: Variant = get_tile_behavior(
		target_cell,
		adjacent_tile - target_cell * int(CHUNK_SIZE)
	)
	var current_behavior := -1 if current_behavior_value == null else int(current_behavior_value)
	var target_behavior := -1 if target_behavior_value == null else int(target_behavior_value)
	var source_world_tile := _transition_source_world_tile(
		origin_tile, adjacent_tile, current_behavior, direction
	)
	var warp: Dictionary = _warp_at(source_header, source_world_tile)
	if warp.is_empty():
		return _warp_error("No Warp event matches the current Header and transition tile.")
	if String(warp.get("runtime_disposition", "")) != "ready":
		return _warp_error("This Warp depends on unsupported dynamic or saved state.")
	var destination := warp.get("destination", {}) as Dictionary
	var destination_header_id := int(destination.get("header_id", -1))
	if not _catalog_headers.has(destination_header_id):
		return _warp_error("The destination Header is absent from the runnable catalog.")
	var header_record := _catalog_headers[destination_header_id] as Dictionary
	var destination_key := String(header_record.get("destination_key", ""))
	if (
		destination_key != String(destination.get("variant", ""))
		or not _catalog_destinations.has(destination_key)
	):
		return _warp_error("The Warp destination disagrees with the Header catalog.")
	var destination_record := _catalog_destinations[destination_key] as Dictionary
	if int(destination_record.get("matrix_id", -1)) != int(destination.get("matrix_id", -1)):
		return _warp_error("The Warp destination matrix disagrees with the catalog.")
	var area_value: Variant = destination_record.get("area_data_id", null)
	var destination_area := -1 if area_value == null else int(area_value)
	var destination_cell := _point_to_vector2i(destination.get("cell", {}))
	var destination_tile := _point_to_vector2i(destination.get("tile", {}))
	if destination_cell == USE_DESTINATION_DEFAULT_CELL or not _is_valid_map_tile(destination_tile):
		return _warp_error("The Warp destination has invalid matrix-cell coordinates.")
	var facing := _direction_to_facing(direction)
	if current_behavior == 0x6A:
		facing = _opposite_facing(facing)
	var source_matrix_cell := Vector2i(
		floori(float(source_world_tile.x) / CHUNK_SIZE),
		floori(float(source_world_tile.y) / CHUNK_SIZE)
	)
	var source_map_tile := source_world_tile - source_matrix_cell * int(CHUNK_SIZE)
	var door_model_id := -1
	if current_behavior == 0x69 or target_behavior == 0x69:
		door_model_id = _find_door_model_id(source_world_tile)
	return {
		"ok": true,
		"matrix": int(destination.get("matrix_id", -1)),
		"area": destination_area,
		"cell": destination_cell,
		"tile": destination_tile,
		"facing": facing,
		"source_cell": source_matrix_cell,
		"source_tile": source_map_tile,
		"source_header_id": source_header,
		"source_warp_id": int(warp.source.get("warp_id", -1)),
		"destination_header_id": destination_header_id,
		"destination_warp_id": int(destination.get("warp_id", -1)),
		"transition_kind": &"warp",
		"door_model_id": door_model_id,
	}


func play_warp_door_animation(request: Dictionary, phase: StringName) -> void:
	if not is_instance_valid(_map_animation_controller):
		return
	if phase == &"arrival" and not _initial_chunks_are_settled:
		var ready_value: Variant = await initial_chunks_settled
		if (
			typeof(ready_value) != TYPE_BOOL
			or not ready_value
			or not is_inside_tree()
			or not is_instance_valid(_map_animation_controller)
		):
			return
	if phase == &"arrival" and not _initial_chunks_succeeded:
		return
	var world_tile: Vector2i
	var expected_model := -1
	var slot := 0
	if phase == &"departure":
		world_tile = (request.source_cell as Vector2i) * int(CHUNK_SIZE) + (request.source_tile as Vector2i)
		expected_model = int(request.get("door_model_id", -1))
	else:
		world_tile = (request.cell as Vector2i) * int(CHUNK_SIZE) + (request.tile as Vector2i)
		slot = 1
	var stable_id := _find_door_stable_id(world_tile, expected_model)
	if stable_id == StringName():
		return
	var result_value: Variant = _map_animation_controller.call("play_one_shot", stable_id, slot)
	if typeof(result_value) != TYPE_DICTIONARY:
		return
	var result := result_value as Dictionary
	if bool(result.get("ok", false)) and typeof(result.get("completion", null)) == TYPE_SIGNAL:
		await result.completion


func is_chunk_loaded(coordinate: Vector2i) -> bool:
	return _loaded_chunks.has(coordinate)


func get_focus_cell() -> Vector2i:
	return _last_focus_cell


func resolve_cell_tile_world_position(matrix_cell: Vector2i, map_tile: Vector2i) -> Variant:
	return _collision_map.resolve_cell_tile_world_position(matrix_cell, map_tile)


func resolve_player_step(
	origin: Vector3, direction: Vector2i, context: Dictionary = {}
) -> Dictionary:
	var ignore_current_transition := false
	if _arrival_escape_world_tile is Vector2i:
		var origin_tile := Vector2i(floori(origin.x), floori(origin.z))
		if origin_tile == (_arrival_escape_world_tile as Vector2i):
			ignore_current_transition = true
		else:
			_arrival_escape_world_tile = null
	return _collision_map.resolve_step(
		origin, direction, context, ignore_current_transition
	)


func resolve_player_height(world_position: Vector3, reference_height: float) -> Variant:
	return _collision_map.sample_ground_height(world_position, reference_height)


func get_tile_attributes(matrix_cell: Vector2i, map_tile: Vector2i) -> Variant:
	return _collision_map.get_tile_attributes(matrix_cell, map_tile)


func get_tile_behavior(matrix_cell: Vector2i, map_tile: Vector2i) -> Variant:
	return _collision_map.get_tile_behavior(matrix_cell, map_tile)


func find_map_props_at_tile(matrix_cell: Vector2i, map_tile: Vector2i) -> Array[Dictionary]:
	return _collision_map.find_map_props_at_tile(matrix_cell, map_tile)


func resolve_offset_grid_world_position(world_position: Vector3, offset: Vector2) -> Variant:
	var offset_position := Vector3(
		floorf(world_position.x + offset.x) + 0.5,
		world_position.y,
		floorf(world_position.z + offset.y) + 0.5
	)
	var offset_cell := _world_to_cell(offset_position)
	var offset_tile := Vector2i(
		floori(offset_position.x - offset_cell.x * CHUNK_SIZE),
		floori(offset_position.z - offset_cell.y * CHUNK_SIZE)
	)
	return _collision_map.resolve_cell_tile_world_position(
		offset_cell, offset_tile, world_position.y
	)


func shutdown() -> void:
	if _shutdown_complete:
		return
	_shutdown_complete = true
	_settle_initial_chunks(false)
	set_process(false)
	_wanted_chunks.clear()
	_retained_asset_paths.clear()
	_asset_states.clear()
	_shared_materials.clear()
	_collision_map.clear()
	for coordinate_value: Variant in _loaded_chunks.keys():
		_unload_chunk(coordinate_value as Vector2i)
	if (
		is_instance_valid(_map_animation_controller)
		and _map_animation_controller.has_method("clear")
	):
		_map_animation_controller.call("clear")
	if (
		is_instance_valid(_field_texture_animation_controller)
		and _field_texture_animation_controller.has_method("clear")
	):
		_field_texture_animation_controller.call("clear")
	_building_animations.clear()
	_warps_by_header_tile.clear()
	_manifest_header_ids.clear()
	_catalog_headers.clear()
	_catalog_destinations.clear()
	_map_prop_instances.clear()
	_door_props_by_world_tile.clear()
	_chunk_prop_ids.clear()
	_chunk_field_texture_ids.clear()


func _resolve_debug_destination() -> bool:
	_configuration_error = false
	var configuration: Dictionary
	if _has_explicit_debug_destination:
		configuration = _explicit_debug_destination.duplicate()
	else:
		var transition_result: Dictionary = WorldTransitionRequest.take(get_tree())
		if not bool(transition_result.ok):
			_configuration_fail(String(transition_result.error))
			return false
		if bool(transition_result.pending):
			_world_transition_arrival = (
				transition_result.request as Dictionary
			).duplicate(true)
			configuration = {
				"matrix": int(_world_transition_arrival.matrix),
				"area": int(_world_transition_arrival.area),
				"cell": _world_transition_arrival.cell as Vector2i,
				"has_cell": true,
				"tile": _world_transition_arrival.tile as Vector2i,
			}
			_start_facing = int(_world_transition_arrival.facing)
			_current_header_id = int(_world_transition_arrival.destination_header_id)
		else:
			var pending_result: Dictionary = DebugDestinationRequest.take(get_tree())
			if not bool(pending_result.ok):
				_configuration_fail(String(pending_result.error))
				return false
			if bool(pending_result.pending):
				configuration = (pending_result.request as Dictionary).duplicate(true)
			else:
				configuration = _debug_destination_from_settings_and_cli()
	if _configuration_error:
		return false

	var resolution: Dictionary = DebugDestinationResolver.resolve(catalog_path, configuration)
	if not bool(resolution.ok):
		_configuration_fail(String(resolution.error))
		return false
	manifest_path = String(resolution.manifest_path)
	_matrix_id = int(resolution.matrix)
	_area_data_id = int(resolution.area)
	_start_cell = resolution.cell as Vector2i
	_start_tile = resolution.tile as Vector2i
	return true


func _debug_destination_from_settings_and_cli() -> Dictionary:
	var configured_cell: Variant = _project_vector2i_setting(DEBUG_CELL_SETTING, DEFAULT_START_CELL)
	var configured_tile: Variant = _project_vector2i_setting(DEBUG_TILE_SETTING, DEFAULT_START_TILE)
	if configured_cell == null or configured_tile == null:
		return {}
	var configuration := {
		"matrix": int(ProjectSettings.get_setting(DEBUG_MATRIX_SETTING, 0)),
		"area": int(ProjectSettings.get_setting(DEBUG_AREA_SETTING, -1)),
		"cell": configured_cell as Vector2i,
		"has_cell": true,
		"tile": configured_tile as Vector2i,
	}
	var overrides := _parse_debug_destination_arguments(OS.get_cmdline_user_args())
	if _configuration_error:
		return {}
	var destination_changed := overrides.has("matrix") or overrides.has("area")
	for key: String in ["matrix", "area", "cell", "tile"]:
		if overrides.has(key):
			configuration[key] = overrides[key]
	if overrides.has("cell"):
		configuration["has_cell"] = true
	elif destination_changed:
		configuration["has_cell"] = false
	return configuration


func _parse_debug_destination_arguments(arguments: PackedStringArray) -> Dictionary:
	var overrides: Dictionary = {}
	for argument: String in arguments:
		if argument.begins_with("--matrix="):
			var value := argument.trim_prefix("--matrix=").strip_edges()
			if not value.is_valid_int():
				_configuration_fail("Invalid --matrix value: %s" % value)
				return {}
			overrides["matrix"] = int(value)
		elif argument.begins_with("--area="):
			var value := argument.trim_prefix("--area=").strip_edges()
			if not value.is_valid_int():
				_configuration_fail("Invalid --area value: %s" % value)
				return {}
			overrides["area"] = int(value)
		elif argument.begins_with("--cell="):
			var value: Variant = _parse_vector2i(argument.trim_prefix("--cell="), "--cell")
			if value == null:
				return {}
			overrides["cell"] = value
		elif argument.begins_with("--tile="):
			var value: Variant = _parse_vector2i(argument.trim_prefix("--tile="), "--tile")
			if value == null:
				return {}
			overrides["tile"] = value
	return overrides


func _parse_vector2i(raw_value: String, option_name: String) -> Variant:
	var components := raw_value.split(",", false)
	if components.size() != 2:
		_configuration_fail("%s expects x,y: %s" % [option_name, raw_value])
		return null
	var x_value := String(components[0]).strip_edges()
	var y_value := String(components[1]).strip_edges()
	if not x_value.is_valid_int() or not y_value.is_valid_int():
		_configuration_fail("%s expects integer x,y: %s" % [option_name, raw_value])
		return null
	return Vector2i(int(x_value), int(y_value))


func _project_vector2i_setting(setting_name: String, fallback: Vector2i) -> Variant:
	var value: Variant = ProjectSettings.get_setting(setting_name, fallback)
	if value is Vector2i:
		return value
	if value is Vector2:
		return Vector2i(value as Vector2)
	_configuration_fail("Project setting %s must be a Vector2i." % setting_name)
	return null


func _is_valid_map_tile(tile: Vector2i) -> bool:
	return tile.x >= 0 and tile.x < 32 and tile.y >= 0 and tile.y < 32


func _place_focus_at_start() -> bool:
	if not _world_transition_arrival.is_empty():
		_adjust_warp_arrival()
		_header_context_cell = _start_cell
		var arrival_behavior: Variant = get_tile_behavior(_start_cell, _start_tile)
		if arrival_behavior != null and int(arrival_behavior) in [0x67, 0x6E]:
			_arrival_escape_world_tile = _start_cell * int(CHUNK_SIZE) + _start_tile
	var start_world_position: Variant = resolve_cell_tile_world_position(_start_cell, _start_tile)
	if start_world_position == null:
		_configuration_fail(
			"Debug start cell %s is not occupied in matrix %04d area %d."
			% [_start_cell, _matrix_id, _area_data_id]
		)
		return false
	_start_world_position = start_world_position as Vector3
	if _focus.has_method("teleport_to_grid"):
		if _start_facing >= 0:
			_focus.call("teleport_to_grid", _start_world_position, _start_facing)
		else:
			_focus.call("teleport_to_grid", _start_world_position)
	else:
		_focus.global_position = _start_world_position
	return true


func _adjust_warp_arrival() -> void:
	var behavior_value: Variant = get_tile_behavior(_start_cell, _start_tile)
	if behavior_value == null:
		return
	var behavior := int(behavior_value)
	var world_tile := _start_cell * int(CHUNK_SIZE) + _start_tile
	if behavior == 0x5E:
		world_tile += Vector2i.RIGHT
		_start_facing = 2
	elif behavior == 0x5F:
		world_tile += Vector2i.LEFT
		_start_facing = 3
	elif behavior in [0x6A, 0x6B] and _start_facing in [2, 3]:
		world_tile += Vector2i.LEFT if _start_facing == 3 else Vector2i.RIGHT
	else:
		return
	_start_cell = Vector2i(
		floori(float(world_tile.x) / CHUNK_SIZE),
		floori(float(world_tile.y) / CHUNK_SIZE)
	)
	_start_tile = world_tile - _start_cell * int(CHUNK_SIZE)


func _configuration_fail(message: String) -> void:
	_configuration_error = true
	_fail(message)


func _load_manifest() -> bool:
	if not FileAccess.file_exists(manifest_path):
		_fail("World manifest does not exist: %s" % manifest_path)
		return false

	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if typeof(parsed) != TYPE_DICTIONARY:
		_fail("World manifest is not a JSON object: %s" % manifest_path)
		return false

	return _apply_manifest(parsed as Dictionary)


func _apply_manifest(manifest: Dictionary) -> bool:
	_cells.clear()
	_terrain_paths.clear()
	_building_paths.clear()
	_building_animations.clear()
	_warps_by_header_tile.clear()
	_manifest_header_ids.clear()
	_default_header_id = -1
	_catalog_headers.clear()
	_catalog_destinations.clear()
	if int(manifest.get("schema_version", -1)) != 4:
		_fail("World manifest schema is not 4.")
		return false
	var matrix: Dictionary = manifest.get("matrix", {})
	if int(matrix.get("id", -1)) != _matrix_id:
		_fail("World manifest matrix id does not match the selected catalog destination.")
		return false
	var manifest_area: Variant = matrix.get("area_data_id", null)
	if _area_data_id >= 0 and (manifest_area == null or int(manifest_area) != _area_data_id):
		_fail("World manifest area id does not match the selected catalog destination.")
		return false
	_manifest_variant = String(matrix.get("variant", ""))
	if _manifest_variant.is_empty():
		_fail("World manifest has no destination variant key.")
		return false
	if not _load_catalog_indices():
		return false
	if not _catalog_destinations.has(_manifest_variant):
		_fail("World manifest destination is absent from the matrix catalog.")
		return false
	var collision_error := _collision_map.configure(manifest)
	if not collision_error.is_empty():
		_fail(collision_error)
		return false
	var assets: Dictionary = manifest.get("assets", {})
	for asset_value: Variant in assets.get("terrain", []):
		var asset := asset_value as Dictionary
		var path := _first_asset_path(asset)
		if not path.is_empty():
			_terrain_paths[String(asset.get("key", ""))] = path
	for asset_value: Variant in assets.get("buildings", []):
		var asset := asset_value as Dictionary
		var asset_key := String(asset.get("key", ""))
		var path := _first_asset_path(asset)
		if not path.is_empty():
			_building_paths[asset_key] = path
		var animation_value: Variant = asset.get("map_animation", null)
		if animation_value is Dictionary:
			_building_animations[asset_key] = (animation_value as Dictionary).duplicate(true)

	for cell_value: Variant in manifest.get("cells", []):
		var cell := cell_value as Dictionary
		var coordinate := Vector2i(int(cell.get("x", -1)), int(cell.get("y", -1)))
		_cells[coordinate] = cell

	if _cells.is_empty() or _terrain_paths.is_empty():
		_fail("World manifest has no cells or terrain assets.")
		return false
	if not _index_field_features(manifest.get("field_features", {}) as Dictionary):
		return false
	if is_instance_valid(_focus) and _focus.has_method("set_collision_provider"):
		_focus.call("set_collision_provider", self)
	return true


func _first_asset_path(asset: Dictionary) -> String:
	var output_glbs: Array = asset.get("output_glbs", [])
	if output_glbs.is_empty():
		return ""
	return manifest_path.get_base_dir().path_join(String(output_glbs[0]))


func _load_catalog_indices() -> bool:
	if not FileAccess.file_exists(catalog_path):
		_fail("Matrix catalog does not exist: %s" % catalog_path)
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(catalog_path))
	if typeof(parsed) != TYPE_DICTIONARY:
		_fail("Matrix catalog is not a JSON object: %s" % catalog_path)
		return false
	var catalog := parsed as Dictionary
	if int(catalog.get("schema_version", -1)) != 3:
		_fail("Matrix catalog schema is not 3.")
		return false
	if is_instance_valid(_field_texture_animation_controller):
		var field_texture_section_value: Variant = catalog.get("field_texture_animations", null)
		if not field_texture_section_value is Dictionary:
			_fail("Matrix catalog has no field texture animation section.")
			return false
		if not _field_texture_animation_controller.has_method("configure"):
			_fail("Field texture animation controller has no configure API.")
			return false
		var field_texture_result: Variant = _field_texture_animation_controller.call(
			"configure",
			field_texture_section_value as Dictionary,
			catalog_path.get_base_dir()
		)
		if (
			not field_texture_result is Dictionary
			or not bool((field_texture_result as Dictionary).get("ok", false))
		):
			_fail("Matrix catalog field texture animation section is invalid.")
			return false
	for destination_value: Variant in catalog.get("destinations", []):
		if not destination_value is Dictionary:
			_fail("Matrix catalog contains a malformed destination.")
			return false
		var destination := destination_value as Dictionary
		var destination_key := String(destination.get("key", ""))
		if destination_key.is_empty() or _catalog_destinations.has(destination_key):
			_fail("Matrix catalog contains an empty or duplicate destination key.")
			return false
		_catalog_destinations[destination_key] = destination
	for header_value: Variant in catalog.get("headers", []):
		if not header_value is Dictionary:
			_fail("Matrix catalog contains a malformed Header record.")
			return false
		var header := header_value as Dictionary
		var header_id := int(header.get("header_id", -1))
		var destination_key := String(header.get("destination_key", ""))
		if (
			header_id < 0
			or _catalog_headers.has(header_id)
			or not _catalog_destinations.has(destination_key)
		):
			_fail("Matrix catalog contains an invalid or duplicate Header record.")
			return false
		_catalog_headers[header_id] = header
	if _catalog_destinations.is_empty() or _catalog_headers.is_empty():
		_fail("Matrix catalog has no runnable destinations or Headers.")
		return false
	return true


func _index_field_features(field_features: Dictionary) -> bool:
	if (
		int(field_features.get("schema_version", -1)) != 1
		or String(field_features.get("source_selection", "")) != "first_warp_id_at_tile"
	):
		_fail("World manifest field-feature contract is unsupported.")
		return false
	for header_id_value: Variant in field_features.get("header_ids", []):
		var header_id := int(header_id_value)
		if header_id < 0 or _manifest_header_ids.has(header_id):
			_fail("World manifest contains an invalid or duplicate Header id.")
			return false
		_manifest_header_ids[header_id] = true
	var default_header_value: Variant = field_features.get("default_header_id", null)
	if default_header_value != null:
		_default_header_id = int(default_header_value)
		if not _manifest_header_ids.has(_default_header_id):
			_fail("World manifest default Header is absent from its Header set.")
			return false
	for cell_value: Variant in _cells.values():
		var cell := cell_value as Dictionary
		var cell_header := int(cell.get("header_id", -1))
		if cell_header >= 0 and not _manifest_header_ids.has(cell_header):
			_fail("World manifest cell references an undeclared Header.")
			return false
	for warp_value: Variant in field_features.get("warps", []):
		if not warp_value is Dictionary:
			_fail("World manifest contains a malformed Warp event.")
			return false
		var warp := warp_value as Dictionary
		var source_value: Variant = warp.get("source", null)
		if not source_value is Dictionary:
			_fail("World manifest Warp has no source endpoint.")
			return false
		var source := source_value as Dictionary
		var header_id := int(source.get("header_id", -1))
		if (
			not _manifest_header_ids.has(header_id)
			or int(source.get("matrix_id", -1)) != _matrix_id
			or String(source.get("variant", "")) != _manifest_variant
		):
			_fail("World manifest Warp references an undeclared source Header.")
			return false
		var world_tile := _point_to_vector2i(source.get("world_tile", {}))
		var warp_key := Vector3i(header_id, world_tile.x, world_tile.y)
		if _warps_by_header_tile.has(warp_key):
			var existing := _warps_by_header_tile[warp_key] as Dictionary
			var existing_source := existing.get("source", {}) as Dictionary
			if int(existing_source.get("warp_id", 0x10000)) <= int(source.get("warp_id", -1)):
				continue
		_warps_by_header_tile[warp_key] = warp
	if _manifest_header_ids.is_empty():
		_fail("World manifest has no MapHeader context.")
		return false
	if _current_header_id < 0 and _cells.has(_start_cell):
		var start_cell := _cells[_start_cell] as Dictionary
		_current_header_id = int(start_cell.get("header_id", -1))
	if _current_header_id < 0:
		_current_header_id = _default_header_id
	if not _manifest_header_ids.has(_current_header_id):
		_fail("Selected world Header is unavailable in this destination.")
		return false
	_header_context_cell = _start_cell
	return true


func _refresh_stream(force: bool) -> void:
	var focus_cell := _world_to_cell(_focus.global_position)
	if not force and focus_cell == _last_focus_cell:
		return
	_last_focus_cell = focus_cell
	if focus_cell != _header_context_cell and _cells.has(focus_cell):
		var cell_header := int((_cells[focus_cell] as Dictionary).get("header_id", -1))
		if cell_header >= 0:
			_current_header_id = cell_header
		_header_context_cell = focus_cell
	_wanted_chunks.clear()
	_retained_asset_paths.clear()
	_collision_map.prepare_region(focus_cell, unload_radius)

	for z in range(focus_cell.y - unload_radius, focus_cell.y + unload_radius + 1):
		for x in range(focus_cell.x - unload_radius, focus_cell.x + unload_radius + 1):
			var coordinate := Vector2i(x, z)
			if _cells.has(coordinate):
				_retain_chunk_assets(coordinate)

	for z in range(focus_cell.y - prefetch_radius, focus_cell.y + prefetch_radius + 1):
		for x in range(focus_cell.x - prefetch_radius, focus_cell.x + prefetch_radius + 1):
			var coordinate := Vector2i(x, z)
			if not _cells.has(coordinate):
				continue
			_prefetch_chunk(coordinate)
			if _cell_distance(coordinate, focus_cell) <= load_radius:
				_wanted_chunks[coordinate] = true

	for coordinate_value: Variant in _loaded_chunks.keys():
		var coordinate := coordinate_value as Vector2i
		if _cell_distance(coordinate, focus_cell) > unload_radius:
			_unload_chunk(coordinate)
	_prune_asset_cache()


func _retain_chunk_assets(coordinate: Vector2i) -> void:
	var cell: Dictionary = _cells[coordinate]
	var terrain_key := String(cell.get("terrain_asset_key", ""))
	if _terrain_paths.has(terrain_key):
		_retained_asset_paths[String(_terrain_paths[terrain_key])] = true

	for building_value: Variant in cell.get("buildings", []):
		var building := building_value as Dictionary
		var asset_key := String(building.get("asset_key", ""))
		if _building_paths.has(asset_key):
			_retained_asset_paths[String(_building_paths[asset_key])] = true


func _prune_asset_cache() -> void:
	for path_value: Variant in _asset_states.keys():
		var path := String(path_value)
		var record: Dictionary = _asset_states[path]
		if not _retained_asset_paths.has(path) and record.state != "loading":
			_asset_states.erase(path)


func _prefetch_chunk(coordinate: Vector2i) -> void:
	var cell: Dictionary = _cells[coordinate]
	var terrain_key := String(cell.get("terrain_asset_key", ""))
	if _terrain_paths.has(terrain_key):
		_request_asset(String(_terrain_paths[terrain_key]))
	else:
		_fail("Terrain asset key is missing from the manifest: %s" % terrain_key)

	for building_value: Variant in cell.get("buildings", []):
		var building := building_value as Dictionary
		var asset_key := String(building.get("asset_key", ""))
		if _building_paths.has(asset_key):
			_request_asset(String(_building_paths[asset_key]))
		else:
			_fail("Building asset key is missing from the manifest: %s" % asset_key)


func _request_asset(path: String) -> void:
	if _asset_states.has(path):
		return
	var error := ResourceLoader.load_threaded_request(path, "PackedScene", false, ResourceLoader.CACHE_MODE_REUSE)
	if error != OK:
		_asset_states[path] = {"state": "failed", "resource": null}
		_failed_asset_count += 1
		_fail("Could not request asset %s (error %d)." % [path, error])
		return
	_asset_states[path] = {"state": "loading", "resource": null}


func _poll_asset_loads() -> void:
	for path_value: Variant in _asset_states.keys():
		var path := String(path_value)
		var record: Dictionary = _asset_states[path]
		if record.state != "loading":
			continue
		match ResourceLoader.load_threaded_get_status(path):
			ResourceLoader.THREAD_LOAD_LOADED:
				var resource := ResourceLoader.load_threaded_get(path)
				if not _retained_asset_paths.has(path):
					_asset_states.erase(path)
					continue
				if resource is PackedScene:
					record.state = "loaded"
					record.resource = resource
				else:
					record.state = "failed"
					_failed_asset_count += 1
					_fail("Asset did not import as PackedScene: %s" % path)
			ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				record.state = "failed"
				_failed_asset_count += 1
				_fail("Threaded asset load failed: %s" % path)
				if not _retained_asset_paths.has(path):
					_asset_states.erase(path)


func _instantiate_ready_chunks() -> void:
	for coordinate_value: Variant in _wanted_chunks.keys():
		var coordinate := coordinate_value as Vector2i
		if _loaded_chunks.has(coordinate) or not _chunk_assets_ready(coordinate):
			continue
		_instantiate_chunk(coordinate)


func _chunk_assets_ready(coordinate: Vector2i) -> bool:
	var cell: Dictionary = _cells[coordinate]
	var paths: Array[String] = [_terrain_paths.get(String(cell.get("terrain_asset_key", "")), "")]
	for building_value: Variant in cell.get("buildings", []):
		var building := building_value as Dictionary
		paths.append(_building_paths.get(String(building.get("asset_key", "")), ""))
	for path: String in paths:
		if path.is_empty() or not _asset_states.has(path):
			return false
		var record: Dictionary = _asset_states[path]
		if record.state != "loaded":
			return false
	return true


func _instantiate_chunk(coordinate: Vector2i) -> void:
	var cell: Dictionary = _cells[coordinate]
	var chunk := Node3D.new()
	chunk.name = "Chunk_%02d_%02d" % [coordinate.x, coordinate.y]
	chunk.position = Vector3(
		coordinate.x * CHUNK_SIZE,
		0.0,
		coordinate.y * CHUNK_SIZE
	)
	chunk.set_meta("map_id", int(cell.get("map_id", -1)))
	chunk.set_meta("header_id", int(cell.get("header_id", -1)))
	_chunks_root.add_child(chunk)

	var terrain_key := String(cell.get("terrain_asset_key", ""))
	var terrain := _instantiate_asset(String(_terrain_paths[terrain_key]))
	if terrain != null:
		terrain.name = "Terrain"
		terrain.position = Vector3(
			CHUNK_SIZE * 0.5,
			float(cell.get("altitude", 0)) * HEIGHT_STEP,
			CHUNK_SIZE * 0.5
		)
		terrain.scale = Vector3.ONE * MODEL_SCALE
		chunk.add_child(terrain)
		_share_materials(terrain, coordinate)

	var buildings := Node3D.new()
	buildings.name = "Buildings"
	buildings.position = Vector3(CHUNK_SIZE * 0.5, 0.0, CHUNK_SIZE * 0.5)
	chunk.add_child(buildings)
	var building_index := 0
	for building_value: Variant in cell.get("buildings", []):
		var building := building_value as Dictionary
		var asset_key := String(building.get("asset_key", ""))
		var instance := _instantiate_asset(String(_building_paths[asset_key]))
		if instance == null:
			building_index += 1
			continue
		instance.name = "Building_%04d_%02d" % [int(building.get("model_id", -1)), building_index]
		instance.position = _dictionary_to_vector3(building.get("position", {}))
		instance.rotation_degrees = _dictionary_to_vector3(building.get("rotation_degrees", {}))
		instance.scale = _building_scale(building)
		buildings.add_child(instance)
		_share_materials(instance, coordinate)
		_register_map_prop_instance(coordinate, building_index, building, instance)
		building_index += 1

	_loaded_chunks[coordinate] = chunk
	if not _initial_signal_sent and coordinate == _last_focus_cell:
		_initial_signal_sent = true
		_settle_initial_chunks(true)
		initial_chunks_ready.emit()


func _settle_initial_chunks(ready: bool) -> void:
	if _initial_chunks_are_settled:
		return
	_initial_chunks_are_settled = true
	_initial_chunks_succeeded = ready
	initial_chunks_settled.emit(ready)


func _instantiate_asset(path: String) -> Node3D:
	var record: Dictionary = _asset_states[path]
	var packed_scene := record.resource as PackedScene
	if packed_scene == null:
		return null
	return packed_scene.instantiate() as Node3D


func _share_materials(root: Node, coordinate: Vector2i) -> void:
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child: Node in node.get_children():
			stack.append(child)
		if not node is MeshInstance3D:
			continue
		var mesh_instance := node as MeshInstance3D
		var mesh := mesh_instance.mesh
		if mesh == null:
			continue
		for surface_index in mesh.get_surface_count():
			var material := mesh.surface_get_material(surface_index)
			if material == null or not material.resource_name.begins_with("dspre_mat_"):
				continue
			var material_key := material.resource_name.trim_prefix("dspre_")
			var effective_material := material
			if _shared_materials.has(material_key):
				var shared_material := _shared_materials[material_key] as Material
				if material != shared_material:
					mesh_instance.set_surface_override_material(surface_index, shared_material)
					_material_replacement_count += 1
				effective_material = shared_material
			else:
				_shared_materials[material_key] = material
			_register_field_texture_surface(
				coordinate,
				mesh_instance,
				surface_index,
				effective_material
			)


func _register_field_texture_surface(
	coordinate: Vector2i,
	mesh_instance: MeshInstance3D,
	surface_index: int,
	material: Material
) -> void:
	if not material is StandardMaterial3D:
		return
	if not _field_texture_animation_controller.has_method("resolve_binding_id"):
		return
	var binding_id := StringName(_field_texture_animation_controller.call(
		"resolve_binding_id", material as StandardMaterial3D
	))
	if String(binding_id).is_empty():
		return
	var stable_id := StringName(
		"%s:%d:%d:field:%d:%d" % [
			_manifest_variant,
			coordinate.x,
			coordinate.y,
			mesh_instance.get_instance_id(),
			surface_index,
		]
	)
	var result: Variant = _field_texture_animation_controller.call(
		"register_surface",
		stable_id,
		mesh_instance,
		surface_index,
		binding_id,
		material as StandardMaterial3D
	)
	if not result is Dictionary or not bool((result as Dictionary).get("ok", false)):
		_fail("Field texture animation surface registration failed: %s" % stable_id)
		return
	if not _chunk_field_texture_ids.has(coordinate):
		_chunk_field_texture_ids[coordinate] = []
	(_chunk_field_texture_ids[coordinate] as Array).append(stable_id)


func _unload_chunk(coordinate: Vector2i) -> void:
	_unregister_chunk_field_textures(coordinate)
	_unregister_chunk_props(coordinate)
	var chunk := _loaded_chunks.get(coordinate) as Node3D
	if chunk != null:
		chunk.queue_free()
	_loaded_chunks.erase(coordinate)


func _unregister_chunk_field_textures(coordinate: Vector2i) -> void:
	if not _chunk_field_texture_ids.has(coordinate):
		return
	if _field_texture_animation_controller.has_method("unregister_surface"):
		for stable_id_value: Variant in _chunk_field_texture_ids[coordinate] as Array:
			_field_texture_animation_controller.call(
				"unregister_surface", StringName(stable_id_value)
			)
	_chunk_field_texture_ids.erase(coordinate)


func _register_map_prop_instance(
	coordinate: Vector2i,
	building_index: int,
	building: Dictionary,
	instance: Node3D
) -> void:
	var asset_key := String(building.get("asset_key", ""))
	if not _building_animations.has(asset_key):
		return
	var descriptor := (_building_animations[asset_key] as Dictionary).duplicate(true)
	var model_id := int(building.get("model_id", -1))
	if int(descriptor.get("model_id", -1)) != model_id:
		_fail("MapProp animation model does not match its building instance.")
		return
	var stable_id := StringName(
		"%s:%d:%d:%d" % [_manifest_variant, coordinate.x, coordinate.y, building_index]
	)
	var position := _dictionary_to_vector3(building.get("position", {}))
	var world_tile := coordinate * int(CHUNK_SIZE) + Vector2i(
		floori(position.x + CHUNK_SIZE * 0.5),
		floori(position.z + CHUNK_SIZE * 0.5)
	)
	var is_door := bool(descriptor.get("is_door", false))
	if is_door and not DOOR_MODEL_IDS.has(model_id):
		_fail("MapProp animation marks an unknown model as a Warp door: %d" % model_id)
		return
	_map_prop_instances[stable_id] = {
		"root_ref": weakref(instance),
		"model_id": model_id,
		"owner_cell": coordinate,
		"world_tile": world_tile,
		"is_door": is_door,
	}
	var stable_ids: Array = _chunk_prop_ids.get(coordinate, [])
	stable_ids.append(stable_id)
	_chunk_prop_ids[coordinate] = stable_ids
	if is_door:
		var door_ids: Array = _door_props_by_world_tile.get(world_tile, [])
		door_ids.append(stable_id)
		_door_props_by_world_tile[world_tile] = door_ids
	if (
		is_instance_valid(_map_animation_controller)
		and _map_animation_controller.has_method("register_map_prop")
	):
		var registration_value: Variant = _map_animation_controller.call(
			"register_map_prop", stable_id, instance, descriptor
		)
		if typeof(registration_value) == TYPE_DICTIONARY:
			var registration := registration_value as Dictionary
			if String(registration.get("status", "")) == "error":
				_fail(String(registration.get("error", "MapProp animation registration failed.")))


func _unregister_chunk_props(coordinate: Vector2i) -> void:
	var stable_ids: Array = _chunk_prop_ids.get(coordinate, [])
	for stable_id_value: Variant in stable_ids:
		_unregister_map_prop_instance(StringName(stable_id_value))
	_chunk_prop_ids.erase(coordinate)


func _unregister_map_prop_instance(stable_id: StringName) -> void:
	if not _map_prop_instances.has(stable_id):
		return
	if (
		is_instance_valid(_map_animation_controller)
		and _map_animation_controller.has_method("unregister_map_prop")
	):
		_map_animation_controller.call("unregister_map_prop", stable_id)
	var record := _map_prop_instances[stable_id] as Dictionary
	if bool(record.get("is_door", false)):
		var world_tile := record.get("world_tile", Vector2i.ZERO) as Vector2i
		var door_ids: Array = _door_props_by_world_tile.get(world_tile, [])
		door_ids.erase(stable_id)
		if door_ids.is_empty():
			_door_props_by_world_tile.erase(world_tile)
		else:
			_door_props_by_world_tile[world_tile] = door_ids
	_map_prop_instances.erase(stable_id)


func _find_door_stable_id(world_tile: Vector2i, expected_model: int = -1) -> StringName:
	var offsets: Array[Vector2i] = [
		Vector2i.ZERO,
		Vector2i.RIGHT,
		Vector2i.LEFT,
		Vector2i.DOWN,
		Vector2i.UP,
	]
	for offset: Vector2i in offsets:
		var anchor := world_tile + offset
		var stable_ids: Array = _door_props_by_world_tile.get(anchor, [])
		for stable_id_value: Variant in stable_ids.duplicate():
			var stable_id := StringName(stable_id_value)
			if not _map_prop_instances.has(stable_id):
				continue
			var record := _map_prop_instances[stable_id] as Dictionary
			var root := (record.root_ref as WeakRef).get_ref() as Node3D
			if root == null or not is_instance_valid(root):
				_unregister_map_prop_instance(stable_id)
				continue
			if expected_model >= 0 and int(record.get("model_id", -1)) != expected_model:
				continue
			return stable_id
	return StringName()


func _find_door_model_id(world_tile: Vector2i) -> int:
	var stable_id := _find_door_stable_id(world_tile)
	if stable_id == StringName() or not _map_prop_instances.has(stable_id):
		return -1
	return int((_map_prop_instances[stable_id] as Dictionary).get("model_id", -1))


func _header_for_cell(coordinate: Vector2i) -> int:
	if not _cells.has(coordinate):
		return -1
	if coordinate == _header_context_cell and _manifest_header_ids.has(_current_header_id):
		return _current_header_id
	var cell := _cells[coordinate] as Dictionary
	var cell_header := int(cell.get("header_id", -1))
	if cell_header >= 0:
		return cell_header if _manifest_header_ids.has(cell_header) else -1
	if _manifest_header_ids.has(_current_header_id):
		return _current_header_id
	return _default_header_id if _manifest_header_ids.has(_default_header_id) else -1


func _warp_at(header_id: int, world_tile: Vector2i) -> Dictionary:
	var warp_value: Variant = _warps_by_header_tile.get(
		Vector3i(header_id, world_tile.x, world_tile.y), null
	)
	return warp_value as Dictionary if warp_value is Dictionary else {}


func _transition_source_world_tile(
	origin_tile: Vector2i,
	adjacent_tile: Vector2i,
	current_behavior: int,
	direction: Vector2i
) -> Vector2i:
	var uses_current_tile: bool = (
		CURRENT_TRANSITION_DIRECTIONS.has(current_behavior)
		and direction == (CURRENT_TRANSITION_DIRECTIONS[current_behavior] as Vector2i)
	) or CURRENT_AUTOMATIC_TRANSITIONS.has(current_behavior)
	return origin_tile if uses_current_tile else adjacent_tile


func _point_to_vector2i(value: Variant) -> Vector2i:
	if value is Vector2i:
		return value as Vector2i
	if value is Dictionary:
		var point := value as Dictionary
		return Vector2i(int(point.get("x", -1)), int(point.get("y", -1)))
	return USE_DESTINATION_DEFAULT_CELL


func _direction_to_facing(direction: Vector2i) -> int:
	match direction:
		Vector2i.DOWN:
			return 0
		Vector2i.UP:
			return 1
		Vector2i.LEFT:
			return 2
		Vector2i.RIGHT:
			return 3
	return -1


func _opposite_facing(facing: int) -> int:
	match facing:
		0:
			return 1
		1:
			return 0
		2:
			return 3
		3:
			return 2
	return facing


func _warp_error(message: String) -> Dictionary:
	return {
		"ok": false,
		"error": message,
		"field": "warp",
	}


func _world_to_cell(world_position: Vector3) -> Vector2i:
	return Vector2i(floori(world_position.x / CHUNK_SIZE), floori(world_position.z / CHUNK_SIZE))


func _cell_distance(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


func _dictionary_to_vector3(value: Variant) -> Vector3:
	var data := value as Dictionary
	return Vector3(float(data.get("x", 0.0)), float(data.get("y", 0.0)), float(data.get("z", 0.0)))


func _building_scale(building: Dictionary) -> Vector3:
	var scale_value: Variant = building.get("scale", null)
	if scale_value is Dictionary:
		return _dictionary_to_vector3(scale_value) * MODEL_SCALE
	var size := building.get("size", {}) as Dictionary
	return Vector3(
		float(size.get("width", 16.0)) / 16.0,
		float(size.get("height", 16.0)) / 16.0,
		float(size.get("length", 16.0)) / 16.0
	) * MODEL_SCALE


func _fail(message: String) -> void:
	_settle_initial_chunks(false)
	push_error(message)
	stream_error.emit(message)
