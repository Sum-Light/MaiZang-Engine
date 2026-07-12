class_name PlatinumWorldStreamer
extends Node3D

signal initial_chunks_ready
signal stream_error(message: String)

const CHUNK_SIZE := 32.0
const HEIGHT_STEP := 0.5
const MODEL_SCALE := 1.0 / 16.0
const DEFAULT_START_CELL := Vector2i(3, 27)
const VisualProfileControllerScript := preload("res://scripts/visual_profile_controller.gd")
const HD2D_VARIANT_ROOT := "res://assets/platinum/hd2d/shared_variants"
const DEFAULT_HD2D_MATERIAL_PROFILE := "res://assets/platinum/hd2d/world_semantics.profile.json"
const HD2D_BINDINGS_META := &"hd2d_surface_bindings"
const HD2D_ORIGINAL_CAST_SHADOW_META := &"hd2d_original_cast_shadow"

@export_file("*.json") var manifest_path := "res://assets/platinum/matrix_0000/manifest.json"
@export var focus_path: NodePath
@export var visual_profile_path: NodePath
@export_file("*.json") var hd2d_material_profile_path := DEFAULT_HD2D_MATERIAL_PROFILE
@export_range(0, 8, 1) var load_radius := 1
@export_range(0, 10, 1) var prefetch_radius := 2
@export_range(1, 12, 1) var unload_radius := 3
@export_range(0.02, 1.0, 0.01) var stream_interval := 0.12

var _focus: Node3D
var _visual_profile: VisualProfileControllerScript
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
var _hd2d_profile_loaded := false
var _hd2d_profile_id := ""
var _hd2d_semantic_materials: Dictionary = {}
var _hd2d_semantic_surface_references: Dictionary = {}
var _hd2d_preserved_material_count := 0
var _hd2d_material_enabled := false
var _hd2d_pilot_cells: Dictionary = {}
var _hd2d_asset_profiles: Dictionary = {}
var _hd2d_variant_cache: Dictionary = {}
var _hd2d_registered_surface_count := 0
var _hd2d_override_count := 0
var _hd2d_pilot_instance_count := 0
var _hd2d_active_pilot_instance_count := 0

@onready var _chunks_root: Node3D = $LoadedChunks


func _ready() -> void:
	add_to_group("platinum_world_streamer")
	_focus = get_node_or_null(focus_path) as Node3D
	if _focus == null:
		_fail("World streamer focus node was not found: %s" % focus_path)
		set_process(false)
		return
	_visual_profile = get_node_or_null(visual_profile_path) as VisualProfileControllerScript
	if _visual_profile != null:
		_visual_profile.profile_changed.connect(_on_visual_profile_changed)
	elif not visual_profile_path.is_empty():
		push_warning("World streamer visual profile node was not found: %s" % visual_profile_path)
	_load_hd2d_material_profile()
	if not _load_manifest():
		set_process(false)
		return
	_refresh_stream(true)
	call_deferred("_sync_visual_profile")


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
		"hd2d_profile_loaded": _hd2d_profile_loaded,
		"hd2d_profile_id": _hd2d_profile_id,
		"hd2d_semantic_materials": _hd2d_semantic_materials.duplicate(true),
		"hd2d_semantic_surface_references": _hd2d_semantic_surface_references.duplicate(true),
		"hd2d_preserved_materials": _hd2d_preserved_material_count,
		"hd2d_variants": _hd2d_variant_cache.size(),
		"hd2d_registered_surfaces": _hd2d_registered_surface_count,
		"hd2d_overrides": _hd2d_override_count,
		"hd2d_pilot_instances": _hd2d_pilot_instance_count,
		"hd2d_active_pilot_instances": _hd2d_active_pilot_instance_count,
		"hd2d_profile_instances": _hd2d_pilot_instance_count,
		"hd2d_active_profile_instances": _hd2d_active_pilot_instance_count,
	}


func is_chunk_loaded(coordinate: Vector2i) -> bool:
	return _loaded_chunks.has(coordinate)


func get_hd2d_binding_snapshot() -> Array[Dictionary]:
	var snapshot: Array[Dictionary] = []
	for coordinate_value: Variant in _loaded_chunks.keys():
		var coordinate := coordinate_value as Vector2i
		var chunk := _loaded_chunks[coordinate] as Node3D
		if is_instance_valid(chunk):
			_collect_hd2d_bindings(chunk, chunk, coordinate, "", snapshot)
	snapshot.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.get("binding_key", "")) < String(b.get("binding_key", ""))
	)
	return snapshot


func get_hd2d_variant_snapshot() -> Array[Dictionary]:
	var snapshot: Array[Dictionary] = []
	for cache_key_value: Variant in _hd2d_variant_cache.keys():
		var material := _hd2d_variant_cache[cache_key_value] as StandardMaterial3D
		if material == null:
			continue
		snapshot.append({
			"cache_key": String(cache_key_value),
			"variant_tag": String(material.get_meta("hd2d_variant_tag", "")),
			"base_material_key": String(material.get_meta("hd2d_base_material_key", "")),
			"resource_path": material.resource_path,
			"material_rid": material.get_rid().get_id(),
			"shading_mode": int(material.shading_mode),
			"emission_enabled": material.emission_enabled,
		})
	snapshot.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.get("cache_key", "")) < String(b.get("cache_key", ""))
	)
	return snapshot


func get_focus_cell() -> Vector2i:
	return _last_focus_cell


func shutdown() -> void:
	set_process(false)
	if _visual_profile != null and _visual_profile.profile_changed.is_connected(
		_on_visual_profile_changed
	):
		_visual_profile.profile_changed.disconnect(_on_visual_profile_changed)
	_hd2d_material_enabled = false
	_apply_hd2d_to_loaded_chunks()
	_wanted_chunks.clear()
	_retained_asset_paths.clear()
	_asset_states.clear()
	_shared_materials.clear()
	_hd2d_variant_cache.clear()
	_hd2d_asset_profiles.clear()
	_hd2d_pilot_cells.clear()
	_hd2d_profile_loaded = false
	_hd2d_profile_id = ""
	_hd2d_semantic_materials.clear()
	_hd2d_semantic_surface_references.clear()
	_hd2d_preserved_material_count = 0
	for chunk_value: Variant in _loaded_chunks.values():
		var chunk := chunk_value as Node3D
		if is_instance_valid(chunk):
			chunk.queue_free()
	_loaded_chunks.clear()
	_hd2d_registered_surface_count = 0
	_hd2d_override_count = 0
	_hd2d_pilot_instance_count = 0
	_hd2d_active_pilot_instance_count = 0


func _sync_visual_profile() -> void:
	if _visual_profile == null:
		return
	_on_visual_profile_changed(_visual_profile.get_active_profile_name())


func _on_visual_profile_changed(profile_name: StringName) -> void:
	_hd2d_material_enabled = profile_name == VisualProfileControllerScript.HD2D_PROFILE
	_apply_hd2d_to_loaded_chunks()


func _load_hd2d_material_profile() -> void:
	_hd2d_profile_loaded = false
	_hd2d_profile_id = ""
	_hd2d_semantic_materials.clear()
	_hd2d_semantic_surface_references.clear()
	_hd2d_preserved_material_count = 0
	_hd2d_pilot_cells.clear()
	_hd2d_asset_profiles.clear()
	_hd2d_variant_cache.clear()
	if not FileAccess.file_exists(hd2d_material_profile_path):
		push_warning(
			"Optional HD2D material profile was not found: %s"
			% hd2d_material_profile_path
		)
		return
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(hd2d_material_profile_path)
	)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("HD2D material profile root is not an object.")
		return
	var profile := parsed as Dictionary
	if int(profile.get("schema_version", 0)) != 1 or not bool(profile.get("enabled", false)):
		push_warning("HD2D material profile is disabled or uses an unsupported schema.")
		return
	for cell_value: Variant in profile.get("cells", []):
		var components := String(cell_value).split(",", false)
		if components.size() != 2:
			push_warning("Invalid HD2D pilot cell: %s" % cell_value)
			continue
		_hd2d_pilot_cells[Vector2i(components[0].to_int(), components[1].to_int())] = true
	var profile_assets: Dictionary = profile.get("assets", {})
	var loaded_variants := _preload_hd2d_variants(profile_assets)
	var expectations: Dictionary = profile.get("expectations", {})
	var expected_variants := int(expectations.get("unique_variants", loaded_variants.size()))
	if (
		_hd2d_pilot_cells.is_empty()
		or profile_assets.is_empty()
		or loaded_variants.size() != expected_variants
	):
		push_warning(
			"HD2D material profile is incomplete: expected %d variants, loaded %d."
			% [expected_variants, loaded_variants.size()]
		)
		_hd2d_pilot_cells.clear()
		return
	_hd2d_asset_profiles = profile_assets.duplicate(true)
	_hd2d_variant_cache = loaded_variants
	_hd2d_profile_id = String(profile.get("profile_id", ""))
	var semantic_materials: Dictionary = expectations.get("semantic_materials", {})
	_hd2d_semantic_materials = semantic_materials.duplicate(true)
	var semantic_surfaces: Dictionary = expectations.get("semantic_surface_references", {})
	_hd2d_semantic_surface_references = semantic_surfaces.duplicate(true)
	_hd2d_preserved_material_count = int(expectations.get("preserved_materials", 0))
	_hd2d_profile_loaded = true


func _preload_hd2d_variants(profile_assets: Dictionary) -> Dictionary:
	var loaded_variants: Dictionary = {}
	for asset_profile_value: Variant in profile_assets.values():
		if typeof(asset_profile_value) != TYPE_DICTIONARY:
			return {}
		var asset_profile := asset_profile_value as Dictionary
		var material_variants: Dictionary = asset_profile.get("material_variants", {})
		for material_key_value: Variant in material_variants.keys():
			var material_key := String(material_key_value)
			var variant_tag := String(material_variants[material_key_value])
			var cache_key := "%s:%s" % [variant_tag, material_key]
			if loaded_variants.has(cache_key):
				continue
			var variant := _load_hd2d_variant_resource(material_key, variant_tag)
			if variant == null:
				return {}
			loaded_variants[cache_key] = variant
	return loaded_variants


func _load_hd2d_variant_resource(material_key: String, variant_tag: String) -> Material:
	var variant_path := HD2D_VARIANT_ROOT.path_join(variant_tag).path_join(
		"%s.tres" % material_key
	)
	var variant := ResourceLoader.load(
		variant_path,
		"StandardMaterial3D",
		ResourceLoader.CACHE_MODE_REUSE
	) as Material
	if variant == null:
		push_warning("Could not load HD2D material variant: %s" % variant_path)
		return null
	if (
		String(variant.get_meta("hd2d_variant_tag", "")) != variant_tag
		or String(variant.get_meta("hd2d_base_material_key", "")) != material_key
	):
		push_warning("HD2D material variant metadata is invalid: %s" % variant_path)
		return null
	return variant


func _apply_hd2d_to_loaded_chunks() -> void:
	for coordinate_value: Variant in _loaded_chunks.keys():
		var coordinate := coordinate_value as Vector2i
		var chunk := _loaded_chunks[coordinate] as Node3D
		if is_instance_valid(chunk):
			_apply_hd2d_chunk(chunk, coordinate)
	_refresh_hd2d_stats()


func _apply_hd2d_chunk(chunk: Node3D, coordinate: Vector2i) -> void:
	var is_pilot_cell := _hd2d_profile_loaded and _hd2d_pilot_cells.has(coordinate)
	var registered_surface_count := 0
	var override_count := 0
	var pilot_instance_count := 0
	var active_pilot_instance_count := 0
	var stack: Array[Node] = [chunk]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node.has_meta("hd2d_asset_key"):
			var asset_key := String(node.get_meta("hd2d_asset_key", ""))
			var asset_profile_value: Variant = _hd2d_asset_profiles.get(asset_key)
			if is_pilot_cell and typeof(asset_profile_value) == TYPE_DICTIONARY:
				var counts := _apply_hd2d_asset(
					node,
					asset_profile_value as Dictionary,
					_hd2d_material_enabled
				)
				registered_surface_count += counts.x
				override_count += counts.y
				pilot_instance_count += 1
				if _hd2d_material_enabled:
					active_pilot_instance_count += 1
			else:
				_clear_hd2d_asset(node)
			continue
		for child: Node in node.get_children():
			stack.append(child)
	chunk.set_meta("hd2d_registered_surface_count", registered_surface_count)
	chunk.set_meta("hd2d_override_count", override_count)
	chunk.set_meta("hd2d_pilot_instance_count", pilot_instance_count)
	chunk.set_meta("hd2d_active_pilot_instance_count", active_pilot_instance_count)


func _apply_hd2d_asset(root: Node, asset_profile: Dictionary, enabled: bool) -> Vector2i:
	var material_variants: Dictionary = asset_profile.get("material_variants", {})
	var use_legacy_shadows := String(asset_profile.get("shadow_policy", "")) == "legacy_only"
	var registered_surface_count := 0
	var override_count := 0
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child: Node in node.get_children():
			stack.append(child)
		if not node is MeshInstance3D:
			continue
		var mesh_instance := node as MeshInstance3D
		if use_legacy_shadows and not mesh_instance.has_meta(HD2D_ORIGINAL_CAST_SHADOW_META):
			mesh_instance.set_meta(
				HD2D_ORIGINAL_CAST_SHADOW_META,
				int(mesh_instance.cast_shadow)
			)
		if use_legacy_shadows:
			mesh_instance.cast_shadow = (
				GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				if enabled
				else int(mesh_instance.get_meta(HD2D_ORIGINAL_CAST_SHADOW_META))
			)
		var mesh := mesh_instance.mesh
		if mesh == null:
			continue
		var bindings: Dictionary = mesh_instance.get_meta(HD2D_BINDINGS_META, {}) as Dictionary
		if bindings.is_empty():
			for surface_index in mesh.get_surface_count():
				var material_key := _surface_material_key(mesh_instance, surface_index)
				if not material_variants.has(material_key):
					continue
				var variant_tag := String(material_variants[material_key])
				var cache_key := "%s:%s" % [variant_tag, material_key]
				var variant := _hd2d_variant_cache.get(cache_key) as Material
				if variant == null:
					continue
				bindings[surface_index] = {
					"classic_override": mesh_instance.get_surface_override_material(surface_index),
					"material_key": material_key,
					"variant": variant,
				}
			if not bindings.is_empty():
				mesh_instance.set_meta(HD2D_BINDINGS_META, bindings)
		for surface_index_value: Variant in bindings.keys():
			var surface_index := int(surface_index_value)
			var binding := bindings[surface_index_value] as Dictionary
			var desired := (
				binding.get("variant") as Material
				if enabled
				else binding.get("classic_override") as Material
			)
			mesh_instance.set_surface_override_material(surface_index, desired)
			registered_surface_count += 1
			if enabled:
				override_count += 1
	return Vector2i(registered_surface_count, override_count)


func _clear_hd2d_asset(root: Node) -> void:
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child: Node in node.get_children():
			stack.append(child)
		if not node is MeshInstance3D:
			continue
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.has_meta(HD2D_BINDINGS_META):
			var bindings := mesh_instance.get_meta(HD2D_BINDINGS_META) as Dictionary
			for surface_index_value: Variant in bindings.keys():
				var surface_index := int(surface_index_value)
				var binding := bindings[surface_index_value] as Dictionary
				var original := binding.get("classic_override") as Material
				mesh_instance.set_surface_override_material(surface_index, original)
			mesh_instance.remove_meta(HD2D_BINDINGS_META)
		if mesh_instance.has_meta(HD2D_ORIGINAL_CAST_SHADOW_META):
			mesh_instance.cast_shadow = int(
				mesh_instance.get_meta(HD2D_ORIGINAL_CAST_SHADOW_META)
			)
			mesh_instance.remove_meta(HD2D_ORIGINAL_CAST_SHADOW_META)


func _surface_material_key(mesh_instance: MeshInstance3D, surface_index: int) -> String:
	var material := mesh_instance.mesh.surface_get_material(surface_index)
	if material == null or not material.resource_name.begins_with("dspre_mat_"):
		return ""
	return material.resource_name.trim_prefix("dspre_")


func _collect_hd2d_bindings(
	chunk: Node3D,
	node: Node,
	coordinate: Vector2i,
	asset_key: String,
	snapshot: Array[Dictionary]
) -> void:
	var current_asset_key := asset_key
	if node.has_meta("hd2d_asset_key"):
		current_asset_key = String(node.get_meta("hd2d_asset_key", ""))
	if node is MeshInstance3D and node.has_meta(HD2D_BINDINGS_META):
		var mesh_instance := node as MeshInstance3D
		var bindings := mesh_instance.get_meta(HD2D_BINDINGS_META) as Dictionary
		for surface_index_value: Variant in bindings.keys():
			var surface_index := int(surface_index_value)
			var binding := bindings[surface_index_value] as Dictionary
			var base_material := mesh_instance.mesh.surface_get_material(surface_index)
			var classic_override := binding.get("classic_override") as Material
			var variant := binding.get("variant") as Material
			var active_override := mesh_instance.get_surface_override_material(surface_index)
			var relative_path := String(chunk.get_path_to(mesh_instance))
			snapshot.append({
				"binding_key": "%d,%d|%s|%s|%d" % [
					coordinate.x,
					coordinate.y,
					current_asset_key,
					relative_path,
					surface_index,
				],
				"cell": "%d,%d" % [coordinate.x, coordinate.y],
				"asset_key": current_asset_key,
				"node_path": relative_path,
				"node_instance_id": mesh_instance.get_instance_id(),
				"mesh_rid": mesh_instance.mesh.get_rid().get_id(),
				"surface_index": surface_index,
				"material_key": String(binding.get("material_key", "")),
				"variant_tag": String(variant.get_meta("hd2d_variant_tag", "")) if variant != null else "",
				"base_path": base_material.resource_path if base_material != null else "",
				"base_rid": base_material.get_rid().get_id() if base_material != null else 0,
				"base_shading_mode": int(base_material.shading_mode) if base_material is BaseMaterial3D else -1,
				"classic_override_rid": _material_rid_id(classic_override),
				"variant_path": variant.resource_path if variant != null else "",
				"variant_rid": _material_rid_id(variant),
				"variant_shading_mode": int(variant.shading_mode) if variant is BaseMaterial3D else -1,
				"active_override_rid": _material_rid_id(active_override),
			})
	for child: Node in node.get_children():
		_collect_hd2d_bindings(chunk, child, coordinate, current_asset_key, snapshot)


func _material_rid_id(material: Material) -> int:
	return material.get_rid().get_id() if material != null else 0


func _refresh_hd2d_stats() -> void:
	_hd2d_registered_surface_count = 0
	_hd2d_override_count = 0
	_hd2d_pilot_instance_count = 0
	_hd2d_active_pilot_instance_count = 0
	for chunk_value: Variant in _loaded_chunks.values():
		var chunk := chunk_value as Node3D
		if not is_instance_valid(chunk):
			continue
		_hd2d_registered_surface_count += int(
			chunk.get_meta("hd2d_registered_surface_count", 0)
		)
		_hd2d_override_count += int(chunk.get_meta("hd2d_override_count", 0))
		_hd2d_pilot_instance_count += int(
			chunk.get_meta("hd2d_pilot_instance_count", 0)
		)
		_hd2d_active_pilot_instance_count += int(
			chunk.get_meta("hd2d_active_pilot_instance_count", 0)
		)


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
	chunk.set_meta("cell_coordinate", coordinate)
	_chunks_root.add_child(chunk)

	var terrain_key := String(cell.get("terrain_asset_key", ""))
	var terrain := _instantiate_asset(String(_terrain_paths[terrain_key]))
	if terrain != null:
		terrain.name = "Terrain"
		terrain.set_meta("hd2d_asset_key", terrain_key)
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
		instance.set_meta("hd2d_asset_key", asset_key)
		instance.position = _dictionary_to_vector3(building.get("position", {}))
		instance.rotation_degrees = _dictionary_to_vector3(building.get("rotation_degrees", {}))
		instance.scale = _building_scale(building.get("size", {}))
		buildings.add_child(instance)
		_share_materials(instance)
		building_index += 1

	_loaded_chunks[coordinate] = chunk
	_apply_hd2d_chunk(chunk, coordinate)
	_refresh_hd2d_stats()
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
	_refresh_hd2d_stats()


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
