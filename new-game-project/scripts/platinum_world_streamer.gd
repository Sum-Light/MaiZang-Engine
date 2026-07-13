class_name PlatinumWorldStreamer
extends Node3D

signal initial_chunks_ready
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
const CollisionMap := preload("res://scripts/platinum_collision_map.gd")

@export_file("*.json") var catalog_path := "res://assets/platinum/matrix_catalog.json"
@export_file("*.json") var manifest_path := "res://assets/platinum/matrix_0000/manifest.json"
@export var focus_path: NodePath
@export_range(0, 8, 1) var load_radius := 1
@export_range(0, 10, 1) var prefetch_radius := 2
@export_range(1, 12, 1) var unload_radius := 3
@export_range(0.02, 1.0, 0.01) var stream_interval := 0.12

var _focus: Node3D
var _cells: Dictionary = {}
var _terrain_paths: Dictionary = {}
var _building_paths: Dictionary = {}
var _asset_states: Dictionary = {}
var _retained_asset_paths: Dictionary = {}
var _wanted_chunks: Dictionary = {}
var _loaded_chunks: Dictionary = {}
var _shared_materials: Dictionary = {}
var _stream_accumulator := 0.0
var _last_focus_cell := Vector2i(1 << 20, 1 << 20)
var _initial_signal_sent := false
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
var _shutdown_complete := false
var _collision_map := CollisionMap.new() as PlatinumCollisionMap

@onready var _chunks_root: Node3D = $LoadedChunks


func _ready() -> void:
	add_to_group("platinum_world_streamer")
	_focus = get_node_or_null(focus_path) as Node3D
	if _focus == null:
		_fail("World streamer focus node was not found: %s" % focus_path)
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


func is_chunk_loaded(coordinate: Vector2i) -> bool:
	return _loaded_chunks.has(coordinate)


func get_focus_cell() -> Vector2i:
	return _last_focus_cell


func resolve_cell_tile_world_position(matrix_cell: Vector2i, map_tile: Vector2i) -> Variant:
	return _collision_map.resolve_cell_tile_world_position(matrix_cell, map_tile)


func resolve_player_step(
	origin: Vector3, direction: Vector2i, context: Dictionary = {}
) -> Dictionary:
	return _collision_map.resolve_step(origin, direction, context)


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
	set_process(false)
	_wanted_chunks.clear()
	_retained_asset_paths.clear()
	_asset_states.clear()
	_shared_materials.clear()
	_collision_map.clear()
	for chunk_value: Variant in _loaded_chunks.values():
		var chunk := chunk_value as Node3D
		if is_instance_valid(chunk) and not chunk.is_queued_for_deletion():
			chunk.queue_free()
	_loaded_chunks.clear()


func _resolve_debug_destination() -> bool:
	_configuration_error = false
	var configuration: Dictionary
	if _has_explicit_debug_destination:
		configuration = _explicit_debug_destination.duplicate()
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
	var start_world_position: Variant = resolve_cell_tile_world_position(_start_cell, _start_tile)
	if start_world_position == null:
		_configuration_fail(
			"Debug start cell %s is not occupied in matrix %04d area %d."
			% [_start_cell, _matrix_id, _area_data_id]
		)
		return false
	_start_world_position = start_world_position as Vector3
	if _focus.has_method("teleport_to_grid"):
		_focus.call("teleport_to_grid", _start_world_position)
	else:
		_focus.global_position = _start_world_position
	return true


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
	var matrix: Dictionary = manifest.get("matrix", {})
	if int(matrix.get("id", -1)) != _matrix_id:
		_fail("World manifest matrix id does not match the selected catalog destination.")
		return false
	var manifest_area: Variant = matrix.get("area_data_id", null)
	if _area_data_id >= 0 and (manifest_area == null or int(manifest_area) != _area_data_id):
		_fail("World manifest area id does not match the selected catalog destination.")
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
		var path := _first_asset_path(asset)
		if not path.is_empty():
			_building_paths[String(asset.get("key", ""))] = path

	for cell_value: Variant in manifest.get("cells", []):
		var cell := cell_value as Dictionary
		var coordinate := Vector2i(int(cell.get("x", -1)), int(cell.get("y", -1)))
		_cells[coordinate] = cell

	if _cells.is_empty() or _terrain_paths.is_empty():
		_fail("World manifest has no cells or terrain assets.")
		return false
	if is_instance_valid(_focus) and _focus.has_method("set_collision_provider"):
		_focus.call("set_collision_provider", self)
	return true


func _first_asset_path(asset: Dictionary) -> String:
	var output_glbs: Array = asset.get("output_glbs", [])
	if output_glbs.is_empty():
		return ""
	return manifest_path.get_base_dir().path_join(String(output_glbs[0]))


func _refresh_stream(force: bool) -> void:
	var focus_cell := _world_to_cell(_focus.global_position)
	if not force and focus_cell == _last_focus_cell:
		return
	_last_focus_cell = focus_cell
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
		_share_materials(terrain)

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
			continue
		instance.name = "Building_%04d_%02d" % [int(building.get("model_id", -1)), building_index]
		instance.position = _dictionary_to_vector3(building.get("position", {}))
		instance.rotation_degrees = _dictionary_to_vector3(building.get("rotation_degrees", {}))
		instance.scale = _building_scale(building)
		buildings.add_child(instance)
		_share_materials(instance)
		building_index += 1

	_loaded_chunks[coordinate] = chunk
	if not _initial_signal_sent and coordinate == _last_focus_cell:
		_initial_signal_sent = true
		initial_chunks_ready.emit()


func _instantiate_asset(path: String) -> Node3D:
	var record: Dictionary = _asset_states[path]
	var packed_scene := record.resource as PackedScene
	if packed_scene == null:
		return null
	return packed_scene.instantiate() as Node3D


func _share_materials(root: Node) -> void:
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
			if _shared_materials.has(material_key):
				var shared_material := _shared_materials[material_key] as Material
				if material != shared_material:
					mesh_instance.set_surface_override_material(surface_index, shared_material)
					_material_replacement_count += 1
			else:
				_shared_materials[material_key] = material


func _unload_chunk(coordinate: Vector2i) -> void:
	var chunk := _loaded_chunks.get(coordinate) as Node3D
	if chunk != null:
		chunk.queue_free()
	_loaded_chunks.erase(coordinate)


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
	push_error(message)
	stream_error.emit(message)
