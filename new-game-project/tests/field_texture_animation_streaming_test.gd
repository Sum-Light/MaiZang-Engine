extends SceneTree

const MAIN_SCENE_PATH := "res://scenes/main.tscn"
const CATALOG_PATH := "res://assets/platinum/matrix_catalog.json"
const MATRIX_ZERO_MATERIAL_CATALOG_PATH := (
	"res://assets/platinum/matrix_0000/material_catalog.json"
)
const MAX_LOAD_FRAMES := 1800
const MAX_ANIMATION_FRAMES := 600
const CLEANUP_FRAMES := 12
const DEFAULT_CELL := Vector2i(3, 27)
const SEA_CELL := Vector2i(27, 5)
const RHANA_CELL := Vector2i(6, 20)
const DEFAULT_TILE := Vector2i(16, 16)
const LAKEP_TEXTURE_NAME := "lakep.1"
const SEA_TEXTURE_NAME := "sea"
const RHANA_TEXTURE_NAME := "rhana"
const STATIC_FLOWER_ALIAS := "nhana.png"

var _main: Node
var _streamer: PlatinumWorldStreamer
var _failure_pending := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var catalog_result := _read_json_dictionary(CATALOG_PATH)
	if not bool(catalog_result.get("ok", false)):
		_fail(String(catalog_result.get("error", "Matrix catalog could not be read.")))
		return
	var catalog := catalog_result.value as Dictionary
	var field_section_value: Variant = catalog.get("field_texture_animations", null)
	if not field_section_value is Dictionary:
		_fail("Matrix catalog has no field texture animation section.")
		return
	var bindings_result := _index_bindings_by_texture_name(
		(field_section_value as Dictionary).get("bindings", null)
	)
	if not bool(bindings_result.get("ok", false)):
		_fail(String(bindings_result.get("error", "Field texture bindings are invalid.")))
		return
	var bindings_by_name := bindings_result.value as Dictionary
	for required_name in [LAKEP_TEXTURE_NAME, SEA_TEXTURE_NAME, RHANA_TEXTURE_NAME]:
		if not bindings_by_name.has(required_name):
			_fail("Field texture catalog has no ready %s binding." % required_name)
			return

	var material_catalog_result := _read_json_dictionary(MATRIX_ZERO_MATERIAL_CATALOG_PATH)
	if not bool(material_catalog_result.get("ok", false)):
		_fail(String(material_catalog_result.get("error", "Matrix 0000 material catalog could not be read.")))
		return
	var nhana_sha := _find_image_sha_for_alias(
		material_catalog_result.value as Dictionary,
		STATIC_FLOWER_ALIAS
	)
	if nhana_sha.is_empty():
		_fail("Matrix 0000 material catalog has no nhana texture alias.")
		return
	for binding_value: Variant in (field_section_value as Dictionary).get("bindings", []):
		if (
			binding_value is Dictionary
			and String((binding_value as Dictionary).get("base_texture_sha256", "")) == nhana_sha
		):
			_fail("The original static nhana texture was falsely exported as an animation binding.")
			return

	var packed := load(MAIN_SCENE_PATH) as PackedScene
	if packed == null:
		_fail("Main scene could not be loaded.")
		return
	var lakep_result := await _exercise_destination(
		packed,
		DEFAULT_CELL,
		LAKEP_TEXTURE_NAME,
		bindings_by_name[LAKEP_TEXTURE_NAME] as Array
	)
	if not bool(lakep_result.get("ok", false)):
		_fail(String(lakep_result.get("error", "lakep animation validation failed.")))
		return
	if not await _release_current_scene():
		_fail("Default field-animation scene did not release cleanly.")
		return

	var sea_result := await _exercise_destination(
		packed,
		SEA_CELL,
		SEA_TEXTURE_NAME,
		bindings_by_name[SEA_TEXTURE_NAME] as Array
	)
	if not bool(sea_result.get("ok", false)):
		_fail(String(sea_result.get("error", "sea animation validation failed.")))
		return
	if not await _release_current_scene():
		_fail("sea field-animation scene did not release cleanly.")
		return

	var rhana_result := await _exercise_destination(
		packed,
		RHANA_CELL,
		RHANA_TEXTURE_NAME,
		bindings_by_name[RHANA_TEXTURE_NAME] as Array
	)
	if not bool(rhana_result.get("ok", false)):
		_fail(String(rhana_result.get("error", "rhana animation validation failed.")))
		return
	if not await _release_current_scene():
		_fail("rhana field-animation scene did not release cleanly.")
		return

	print("FIELD_TEXTURE_ANIMATION_STREAMING_OK ", JSON.stringify({
		"lakep": lakep_result.get("summary", {}),
		"sea": sea_result.get("summary", {}),
		"rhana": rhana_result.get("summary", {}),
		"nhana_static": true,
		"scene_lifecycles": 3,
	}))
	quit(0)


func _exercise_destination(
	packed: PackedScene,
	cell: Vector2i,
	texture_name: String,
	bindings: Array
) -> Dictionary:
	_main = packed.instantiate()
	_streamer = _main.get_node_or_null("WorldStreamer") as PlatinumWorldStreamer
	var controller: Node = _main.get_node_or_null(
		"FieldTextureAnimationController"
	)
	if _streamer == null or controller == null:
		return _error_result("Main scene has no streamer or field texture animation controller.")
	if not _streamer.configure_debug_destination(0, -1, cell, DEFAULT_TILE):
		return _error_result("Matrix 0000 cell %s could not be configured." % cell)
	root.add_child(_main)

	var stats: Dictionary
	for frame in MAX_LOAD_FRAMES:
		await process_frame
		stats = _streamer.get_stream_stats()
		if int(stats.get("failed_assets", 0)) != 0:
			return _error_result(
				"Matrix 0000 cell %s reported asset-load failures: %s"
				% [cell, JSON.stringify(stats)]
			)
		if _streamer.is_chunk_loaded(cell) and int(stats.get("loading_assets", 0)) == 0:
			break
	if not _streamer.is_chunk_loaded(cell) or int(stats.get("loading_assets", -1)) != 0:
		return _error_result("Matrix 0000 cell %s did not settle within the timeout." % cell)

	var expected_binding_ids: Dictionary = {}
	for binding_value: Variant in bindings:
		if not binding_value is Dictionary:
			return _error_result("The %s binding list is malformed." % texture_name)
		var binding_id := String((binding_value as Dictionary).get("binding_id", ""))
		if binding_id.is_empty() or expected_binding_ids.has(binding_id):
			return _error_result("The %s binding has an empty or duplicate ID." % texture_name)
		expected_binding_ids[binding_id] = true
	var surface_result := _find_bound_surface(controller, cell, expected_binding_ids)
	if not bool(surface_result.get("ok", false)):
		return _error_result(
			"Matrix 0000 cell %s did not register %s: %s"
			% [cell, texture_name, String(surface_result.get("error", "surface unavailable"))]
		)
	var mesh_instance := surface_result.mesh as MeshInstance3D
	var surface_index := int(surface_result.surface_index)
	var selected_binding_id := String(surface_result.binding_id)

	for frame in MAX_LOAD_FRAMES:
		await process_frame
		stats = _streamer.get_stream_stats()
		var field_stats := stats.get("field_texture_animations", {}) as Dictionary
		if (
			int(stats.get("failed_assets", 0)) != 0
			or int(field_stats.get("failed_texture_loads", 0)) != 0
		):
			return _error_result(
				"%s frame assets failed to load: %s" % [texture_name, JSON.stringify(stats)]
			)
		if int(field_stats.get("loading_textures", -1)) == 0:
			break
	var ready_field_stats := stats.get("field_texture_animations", {}) as Dictionary
	if (
		int(ready_field_stats.get("loading_textures", -1)) != 0
		or int(ready_field_stats.get("registered_surfaces", 0)) < 1
		or int(ready_field_stats.get("active_bindings", 0)) < 1
	):
		return _error_result(
			"%s did not finish its asynchronous registration: %s"
			% [texture_name, JSON.stringify(ready_field_stats)]
		)

	var runtime_material := mesh_instance.get_surface_override_material(
		surface_index
	) as StandardMaterial3D
	if runtime_material == null or runtime_material.albedo_texture == null:
		return _error_result("%s has no runtime animation material." % texture_name)
	var initial_texture_path := runtime_material.albedo_texture.resource_path
	var initial_switches := int(ready_field_stats.get("frame_switches", -1))
	var final_field_stats := ready_field_stats
	var texture_changed := false
	for frame in MAX_ANIMATION_FRAMES:
		await physics_frame
		if not is_instance_valid(mesh_instance) or not is_instance_valid(runtime_material):
			return _error_result("%s surface was released while its chunk remained active." % texture_name)
		final_field_stats = controller.call("get_stats") as Dictionary
		if (
			int(final_field_stats.get("failed_texture_loads", 0)) != 0
			or int((_streamer.get_stream_stats() as Dictionary).get("failed_assets", 0)) != 0
		):
			return _error_result("%s failed while advancing its texture timeline." % texture_name)
		var current_texture := runtime_material.albedo_texture
		if (
			current_texture != null
			and current_texture.resource_path != initial_texture_path
			and int(final_field_stats.get("frame_switches", -1)) > initial_switches
		):
			texture_changed = true
			break
	if not texture_changed:
		return _error_result(
			"%s did not switch its registered surface texture within %d physics frames."
			% [texture_name, MAX_ANIMATION_FRAMES]
		)
	return {
		"ok": true,
		"summary": {
			"cell": {"x": cell.x, "y": cell.y},
			"binding_id": selected_binding_id,
			"registered_surfaces": int(final_field_stats.get("registered_surfaces", -1)),
			"loaded_textures": int(final_field_stats.get("loaded_textures", -1)),
			"frame_switches_before": initial_switches,
			"frame_switches_after": int(final_field_stats.get("frame_switches", -1)),
			"texture_changed": true,
		},
	}


func _find_bound_surface(
	controller: Node,
	cell: Vector2i,
	expected_binding_ids: Dictionary
) -> Dictionary:
	var chunk := _streamer.get_node_or_null(
		"LoadedChunks/Chunk_%02d_%02d" % [cell.x, cell.y]
	)
	if chunk == null:
		return _error_result("Target chunk node is unavailable.")
	for mesh_instance in _collect_mesh_instances(chunk):
		if mesh_instance.mesh == null:
			continue
		for surface_index in mesh_instance.mesh.get_surface_count():
			var base_material := mesh_instance.mesh.surface_get_material(
				surface_index
			) as StandardMaterial3D
			if base_material == null:
				continue
			var resolved_binding_id := String(
				controller.call("resolve_binding_id", base_material)
			)
			if expected_binding_ids.has(resolved_binding_id):
				return {
					"ok": true,
					"mesh": mesh_instance,
					"surface_index": surface_index,
					"binding_id": resolved_binding_id,
				}
	return _error_result(
		"No surface resolves to one of %s." % JSON.stringify(expected_binding_ids.keys())
	)


func _collect_mesh_instances(root_node: Node) -> Array[MeshInstance3D]:
	var meshes: Array[MeshInstance3D] = []
	var stack: Array[Node] = [root_node]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is MeshInstance3D:
			meshes.append(node as MeshInstance3D)
		for child in node.get_children():
			stack.append(child as Node)
	return meshes


func _index_bindings_by_texture_name(bindings_value: Variant) -> Dictionary:
	if not bindings_value is Array:
		return _error_result("Field texture animation bindings are not an array.")
	var by_name: Dictionary = {}
	for binding_value: Variant in bindings_value as Array:
		if not binding_value is Dictionary:
			return _error_result("Field texture animation catalog contains a malformed binding.")
		var binding := binding_value as Dictionary
		var texture_name := String(binding.get("texture_name", ""))
		if texture_name.is_empty():
			return _error_result("Field texture animation texture name is empty.")
		if not by_name.has(texture_name):
			by_name[texture_name] = []
		(by_name[texture_name] as Array).append(binding)
	return {"ok": true, "value": by_name}


func _find_image_sha_for_alias(material_catalog: Dictionary, alias: String) -> String:
	for image_value: Variant in material_catalog.get("images", []):
		if not image_value is Dictionary:
			continue
		var image := image_value as Dictionary
		for alias_value: Variant in image.get("aliases", []):
			if String(alias_value).to_lower() == alias.to_lower():
				return String(image.get("sha256", "")).to_lower()
	return ""


func _read_json_dictionary(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _error_result("Required test asset does not exist: %s" % path)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return _error_result("Required test JSON is malformed: %s" % path)
	return {"ok": true, "value": parsed as Dictionary}


func _release_current_scene() -> bool:
	var released_ref: WeakRef = weakref(_main)
	if is_instance_valid(_streamer):
		_streamer.shutdown()
	if is_instance_valid(_main):
		_main.queue_free()
	_streamer = null
	_main = null
	for frame in CLEANUP_FRAMES:
		await process_frame
		if released_ref.get_ref() == null:
			return true
	return released_ref.get_ref() == null


func _error_result(message: String) -> Dictionary:
	return {"ok": false, "error": message}


func _fail(message: String) -> void:
	if _failure_pending:
		return
	_failure_pending = true
	push_error(message)
	if is_instance_valid(_streamer):
		_streamer.shutdown()
	if is_instance_valid(_main):
		_main.queue_free()
	call_deferred("_finish_failure")


func _finish_failure() -> void:
	for frame in CLEANUP_FRAMES:
		await process_frame
	quit(1)
