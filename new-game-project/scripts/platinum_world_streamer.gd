class_name PlatinumWorldStreamer
extends Node3D

signal initial_chunks_ready
signal stream_error(message: String)

const CHUNK_SIZE := 32.0
const HEIGHT_STEP := 0.5
const MODEL_SCALE := 1.0 / 16.0
const DEFAULT_START_CELL := Vector2i(3, 27)

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

@onready var _chunks_root: Node3D = $LoadedChunks


func _ready() -> void:
	add_to_group("platinum_world_streamer")
	_focus = get_node_or_null(focus_path) as Node3D
	if _focus == null:
		_fail("World streamer focus node was not found: %s" % focus_path)
		set_process(false)
		return
	if not _load_manifest():
		set_process(false)
		return
	_refresh_stream(true)


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
	return {
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


func is_chunk_loaded(coordinate: Vector2i) -> bool:
	return _loaded_chunks.has(coordinate)


func get_focus_cell() -> Vector2i:
	return _last_focus_cell


func shutdown() -> void:
	set_process(false)
	_wanted_chunks.clear()
	_retained_asset_paths.clear()
	_asset_states.clear()
	_shared_materials.clear()
	for chunk_value: Variant in _loaded_chunks.values():
		var chunk := chunk_value as Node3D
		if is_instance_valid(chunk):
			chunk.queue_free()
	_loaded_chunks.clear()


func _load_manifest() -> bool:
	if not FileAccess.file_exists(manifest_path):
		_fail("World manifest does not exist: %s" % manifest_path)
		return false

	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if typeof(parsed) != TYPE_DICTIONARY:
		_fail("World manifest is not a JSON object: %s" % manifest_path)
		return false

	var manifest := parsed as Dictionary
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
		float(cell.get("altitude", 0)) * HEIGHT_STEP,
		coordinate.y * CHUNK_SIZE
	)
	chunk.set_meta("map_id", int(cell.get("map_id", -1)))
	chunk.set_meta("header_id", int(cell.get("header_id", -1)))
	_chunks_root.add_child(chunk)

	var terrain_key := String(cell.get("terrain_asset_key", ""))
	var terrain := _instantiate_asset(String(_terrain_paths[terrain_key]))
	if terrain != null:
		terrain.name = "Terrain"
		terrain.scale = Vector3.ONE * MODEL_SCALE
		chunk.add_child(terrain)
		_share_materials(terrain)

	var buildings := Node3D.new()
	buildings.name = "Buildings"
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
		instance.scale = _building_scale(building.get("size", {}))
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


func _building_scale(value: Variant) -> Vector3:
	var size := value as Dictionary
	return Vector3(
		float(size.get("width", 16.0)) / 16.0,
		float(size.get("height", 16.0)) / 16.0,
		float(size.get("length", 16.0)) / 16.0
	) * MODEL_SCALE


func _fail(message: String) -> void:
	push_error(message)
	stream_error.emit(message)
