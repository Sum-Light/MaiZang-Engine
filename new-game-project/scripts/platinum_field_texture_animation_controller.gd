class_name PlatinumFieldTextureAnimationController
extends Node

const SOURCE_FPS := 30
const SOURCE_FRAME_SECONDS := 1.0 / float(SOURCE_FPS)
const CATALOG_SCHEMA_VERSION := 1

static var _pending_request_handoffs: Dictionary = {}

var _bindings: Dictionary = {}
var _binding_ids_by_texture_sha: Dictionary = {}
var _registrations: Dictionary = {}
var _surface_owners: Dictionary = {}
var _texture_states: Dictionary = {}
var _pending_texture_paths: Array[String] = []
var _active_binding_ids: Array[StringName] = []
var _source_tick := 0
var _source_accumulator := 0.0
var _pruned_surfaces := 0
var _failed_texture_loads := 0
var _frame_switches := 0


func _physics_process(delta: float) -> void:
	_poll_pending_request_handoffs()
	_poll_texture_loads()
	if delta <= 0.0 or not is_finite(delta):
		return
	_source_accumulator += delta
	var elapsed_ticks := int(floor(_source_accumulator / SOURCE_FRAME_SECONDS))
	if elapsed_ticks <= 0:
		return
	_source_accumulator -= float(elapsed_ticks) * SOURCE_FRAME_SECONDS
	_source_tick += elapsed_ticks
	_refresh_active_bindings()


func configure(catalog_section: Dictionary, catalog_root: String) -> Dictionary:
	var parsed_result := _parse_catalog(catalog_section, catalog_root)
	if not bool(parsed_result.get("ok", false)):
		return parsed_result
	clear()
	_bindings = parsed_result.bindings as Dictionary
	_binding_ids_by_texture_sha = parsed_result.binding_ids_by_texture_sha as Dictionary
	return {
		"ok": true,
		"status": "configured",
		"bindings": _bindings.size(),
		"source_fps": SOURCE_FPS,
	}


func resolve_binding_id(base_material: StandardMaterial3D) -> StringName:
	if base_material == null or base_material.albedo_texture == null:
		return StringName()
	var texture_path := base_material.albedo_texture.resource_path
	if texture_path.is_empty():
		return StringName()
	var texture_sha := texture_path.get_file().get_basename().to_lower()
	if not _binding_ids_by_texture_sha.has(texture_sha):
		return StringName()
	return StringName(_binding_ids_by_texture_sha[texture_sha])


func register_surface(
	stable_id: StringName,
	mesh_instance: MeshInstance3D,
	surface_index: int,
	binding_id: StringName,
	base_material: StandardMaterial3D = null
) -> Dictionary:
	if String(stable_id).is_empty():
		return _error_result("invalid_stable_id", "Field texture animation stable ID is empty.")
	if mesh_instance == null or not is_instance_valid(mesh_instance):
		return _error_result("invalid_mesh_instance", "Animated mesh instance is unavailable.")
	if mesh_instance.mesh == null or surface_index < 0 or surface_index >= mesh_instance.mesh.get_surface_count():
		return _error_result("invalid_surface", "Animated mesh surface index is out of range.")
	if not _bindings.has(binding_id):
		return _error_result("unknown_binding", "Field texture animation binding is unavailable.")

	if _registrations.has(stable_id):
		unregister_surface(stable_id)
	var surface_key := _surface_key(mesh_instance, surface_index)
	if _surface_owners.has(surface_key):
		return _error_result("duplicate_surface", "Animated mesh surface is already registered.")

	var previous_override := mesh_instance.get_surface_override_material(surface_index)
	var effective_base := base_material
	if effective_base == null and previous_override is StandardMaterial3D:
		effective_base = previous_override as StandardMaterial3D
	if effective_base == null:
		var mesh_material := mesh_instance.mesh.surface_get_material(surface_index)
		if mesh_material is StandardMaterial3D:
			effective_base = mesh_material as StandardMaterial3D
	if effective_base == null:
		return _error_result("invalid_base_material", "Animated surface has no StandardMaterial3D base.")

	var binding := _bindings[binding_id] as Dictionary
	var targets := binding.targets as Array
	var material_group_key := _material_group_key(effective_base)
	var material_groups := binding.material_groups as Dictionary
	var material_group: Dictionary
	if material_groups.has(material_group_key):
		material_group = material_groups[material_group_key] as Dictionary
	else:
		var duplicate_value := effective_base.duplicate(false)
		if not duplicate_value is StandardMaterial3D:
			return _error_result("material_duplicate_failed", "Animated material could not be duplicated.")
		var new_runtime_material := duplicate_value as StandardMaterial3D
		new_runtime_material.resource_name = "%s_field_animation" % effective_base.resource_name
		material_group = {
			"runtime_material": new_runtime_material,
			"base_material_ref": weakref(effective_base),
			"applied_frame_index": -1,
			"references": 0,
		}
		material_groups[material_group_key] = material_group
	if targets.is_empty():
		_activate_binding(binding_id, binding)

	var runtime_material := material_group.runtime_material as StandardMaterial3D
	if runtime_material == null:
		return _error_result("runtime_material_unavailable", "Animated runtime material is unavailable.")
	var target := {
		"mesh_ref": weakref(mesh_instance),
		"mesh_instance_id": mesh_instance.get_instance_id(),
		"surface_index": surface_index,
		"surface_key": surface_key,
		"binding_id": binding_id,
		"material_group_key": material_group_key,
		"previous_override": previous_override,
	}
	_registrations[stable_id] = target
	_surface_owners[surface_key] = stable_id
	targets.append(stable_id)
	material_group.references = int(material_group.references) + 1
	mesh_instance.set_surface_override_material(surface_index, runtime_material)
	_refresh_binding(binding)
	return {
		"ok": true,
		"status": "registered",
		"stable_id": stable_id,
		"binding_id": binding_id,
		"material_group_key": material_group_key,
		"loading": _binding_load_state(binding) == &"loading",
	}


func unregister_surface(stable_id: StringName) -> Dictionary:
	if not _registrations.has(stable_id):
		return _error_result("not_registered", "Field texture animation surface is not registered.")
	_remove_registration(stable_id, true, false)
	return {
		"ok": true,
		"status": "unregistered",
		"stable_id": stable_id,
	}


func clear() -> Dictionary:
	var removed := _registrations.size()
	var stable_ids := _registrations.keys()
	for stable_id_value in stable_ids:
		_remove_registration(StringName(stable_id_value), true, false)
	_bindings.clear()
	_binding_ids_by_texture_sha.clear()
	for path in _pending_texture_paths:
		_pending_request_handoffs[path] = true
	_texture_states.clear()
	_pending_texture_paths.clear()
	_active_binding_ids.clear()
	_surface_owners.clear()
	_source_tick = 0
	_source_accumulator = 0.0
	_pruned_surfaces = 0
	_failed_texture_loads = 0
	_frame_switches = 0
	return {
		"ok": true,
		"status": "cleared",
		"removed": removed,
	}


func get_stats() -> Dictionary:
	_prune_released_surfaces()
	var loaded_textures := 0
	var loading_textures := 0
	var retained_textures := 0
	var active_material_groups := 0
	for binding_id in _active_binding_ids:
		if _bindings.has(binding_id):
			active_material_groups += (_bindings[binding_id] as Dictionary).material_groups.size()
	for state_value in _texture_states.values():
		var state := state_value as Dictionary
		if int(state.ref_count) > 0:
			retained_textures += 1
		match StringName(state.status):
			&"loaded":
				loaded_textures += 1
			&"loading":
				loading_textures += 1
	return {
		"configured_bindings": _bindings.size(),
		"active_bindings": _active_binding_ids.size(),
		"active_material_groups": active_material_groups,
		"registered_surfaces": _registrations.size(),
		"retained_textures": retained_textures,
		"loaded_textures": loaded_textures,
		"loading_textures": loading_textures,
		"failed_texture_loads": _failed_texture_loads,
		"source_tick": _source_tick,
		"frame_switches": _frame_switches,
		"pruned_surfaces": _pruned_surfaces,
	}


func _parse_catalog(catalog_section: Dictionary, catalog_root: String) -> Dictionary:
	var schema_result := _parse_integral_number(catalog_section.get("schema_version", null))
	if not bool(schema_result.get("ok", false)) or int(schema_result.value) != CATALOG_SCHEMA_VERSION:
		return _error_result("invalid_schema", "Field texture animation catalog schema is not 1.")
	var source_fps_result := _parse_integral_number(catalog_section.get("source_fps", null))
	if not bool(source_fps_result.get("ok", false)) or int(source_fps_result.value) != SOURCE_FPS:
		return _error_result("invalid_source_fps", "Field texture animation source rate is not 30 Hz.")
	var bindings_value: Variant = catalog_section.get("bindings", null)
	if bindings_value is not Array and bindings_value is not Dictionary:
		return _error_result("invalid_bindings", "Field texture animation catalog has no binding collection.")

	var normalized_root := catalog_root.trim_suffix("/").trim_suffix("\\")
	var descriptors: Array = []
	if bindings_value is Array:
		descriptors = bindings_value as Array
	else:
		var binding_dictionary := bindings_value as Dictionary
		for key_value in binding_dictionary:
			var descriptor_value: Variant = binding_dictionary[key_value]
			if not descriptor_value is Dictionary:
				return _error_result("invalid_binding", "Field texture animation binding is not a dictionary.")
			var descriptor := (descriptor_value as Dictionary).duplicate(true)
			descriptor["binding_id"] = String(key_value)
			descriptors.append(descriptor)

	var parsed_bindings: Dictionary = {}
	var parsed_texture_sha_bindings: Dictionary = {}
	for descriptor_value in descriptors:
		if not descriptor_value is Dictionary:
			return _error_result("invalid_binding", "Field texture animation binding is not a dictionary.")
		var descriptor := descriptor_value as Dictionary
		var binding_id_value: Variant = descriptor.get("binding_id", null)
		if typeof(binding_id_value) not in [TYPE_STRING, TYPE_STRING_NAME]:
			return _error_result("invalid_binding_id", "Field texture animation binding has no string ID.")
		var binding_id := StringName(String(binding_id_value))
		if String(binding_id).is_empty() or parsed_bindings.has(binding_id):
			return _error_result("invalid_binding_id", "Field texture animation binding ID is empty or duplicated.")
		var texture_sha := String(descriptor.get("base_texture_sha256", "")).to_lower()
		if not _is_sha256(texture_sha) or parsed_texture_sha_bindings.has(texture_sha):
			return _error_result(
				"invalid_texture_sha256",
				"Field texture animation base texture hash is invalid or duplicated."
			)
		parsed_texture_sha_bindings[texture_sha] = binding_id
		var frames_value: Variant = descriptor.get("frames", null)
		if not frames_value is Array or (frames_value as Array).is_empty():
			return _error_result("invalid_frames", "Field texture animation binding has no frames.")

		var frames: Array = []
		var unique_paths: Array[String] = []
		var path_set: Dictionary = {}
		var period_ticks := 0
		for frame_value in frames_value as Array:
			if not frame_value is Dictionary:
				return _error_result("invalid_frame", "Field texture animation frame is not a dictionary.")
			var frame := frame_value as Dictionary
			var path_value: Variant = frame.get("path", null)
			if typeof(path_value) != TYPE_STRING:
				return _error_result("invalid_frame_path", "Field texture animation frame path is not a string.")
			var resolved_path := _resolve_frame_path(String(path_value), normalized_root)
			if resolved_path.is_empty():
				return _error_result("invalid_frame_path", "Field texture animation frame path escapes its catalog root.")
			var hold_result := _parse_integral_number(frame.get("hold_ticks", null))
			if not bool(hold_result.get("ok", false)) or int(hold_result.value) <= 0:
				return _error_result("invalid_hold_ticks", "Field texture animation hold must be a positive integer.")
			period_ticks += int(hold_result.value)
			if period_ticks <= 0:
				return _error_result("invalid_period", "Field texture animation period overflowed.")
			frames.append({
				"path": resolved_path,
				"hold_ticks": int(hold_result.value),
				"end_tick": period_ticks,
			})
			if not path_set.has(resolved_path):
				path_set[resolved_path] = true
				unique_paths.append(resolved_path)
		parsed_bindings[binding_id] = {
			"binding_id": binding_id,
			"base_texture_sha256": texture_sha,
			"frames": frames,
			"paths": unique_paths,
			"period_ticks": period_ticks,
			"first_hold_ticks": int((frames[0] as Dictionary).hold_ticks),
			"targets": [],
			"material_groups": {},
			"active": false,
			"failed": false,
		}
	return {
		"ok": true,
		"bindings": parsed_bindings,
		"binding_ids_by_texture_sha": parsed_texture_sha_bindings,
		"catalog_root": normalized_root,
	}


func _resolve_frame_path(relative_or_resource_path: String, catalog_root: String) -> String:
	if relative_or_resource_path.is_empty() or relative_or_resource_path.contains("\\"):
		return ""
	if relative_or_resource_path.begins_with("res://") or relative_or_resource_path.begins_with("user://"):
		return relative_or_resource_path.simplify_path()
	if catalog_root.is_empty() or relative_or_resource_path.begins_with("/"):
		return ""
	var resolved := (catalog_root + "/" + relative_or_resource_path).simplify_path()
	var root_prefix := catalog_root + "/"
	if not resolved.begins_with(root_prefix):
		return ""
	return resolved


func _activate_binding(binding_id: StringName, binding: Dictionary) -> void:
	if bool(binding.active):
		return
	binding.active = true
	_active_binding_ids.append(binding_id)
	for path_value in binding.paths as Array[String]:
		_retain_texture_path(path_value)


func _deactivate_binding(binding_id: StringName, binding: Dictionary) -> void:
	if not bool(binding.active):
		return
	binding.active = false
	var active_index := _active_binding_ids.find(binding_id)
	if active_index >= 0:
		_active_binding_ids.remove_at(active_index)
	for path_value in binding.paths as Array[String]:
		_release_texture_path(path_value)
	(binding.material_groups as Dictionary).clear()
	binding.failed = false


func _retain_texture_path(path: String) -> void:
	if _texture_states.has(path):
		var existing := _texture_states[path] as Dictionary
		existing.ref_count = int(existing.ref_count) + 1
		return
	if _pending_request_handoffs.has(path):
		_pending_request_handoffs.erase(path)
		_texture_states[path] = {
			"status": &"loading",
			"resource": null,
			"ref_count": 1,
		}
		_pending_texture_paths.append(path)
		return
	var request_error := ResourceLoader.load_threaded_request(
		path,
		"Texture2D",
		false,
		ResourceLoader.CACHE_MODE_REUSE
	)
	if request_error != OK:
		_texture_states[path] = {
			"status": &"failed",
			"resource": null,
			"ref_count": 1,
		}
		_failed_texture_loads += 1
		return
	_texture_states[path] = {
		"status": &"loading",
		"resource": null,
		"ref_count": 1,
	}
	_pending_texture_paths.append(path)


func _poll_pending_request_handoffs() -> void:
	for path_value in _pending_request_handoffs.keys():
		var path := String(path_value)
		match ResourceLoader.load_threaded_get_status(path):
			ResourceLoader.THREAD_LOAD_LOADED:
				ResourceLoader.load_threaded_get(path)
				_pending_request_handoffs.erase(path)
			ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				_pending_request_handoffs.erase(path)


func _release_texture_path(path: String) -> void:
	if not _texture_states.has(path):
		return
	var state := _texture_states[path] as Dictionary
	state.ref_count = maxi(0, int(state.ref_count) - 1)
	if int(state.ref_count) == 0 and StringName(state.status) != &"loading":
		_texture_states.erase(path)


func _poll_texture_loads() -> void:
	var loads_changed := false
	var index := _pending_texture_paths.size() - 1
	while index >= 0:
		var path := _pending_texture_paths[index]
		if not _texture_states.has(path):
			_pending_texture_paths.remove_at(index)
			index -= 1
			continue
		var state := _texture_states[path] as Dictionary
		match ResourceLoader.load_threaded_get_status(path):
			ResourceLoader.THREAD_LOAD_LOADED:
				var resource_value: Variant = ResourceLoader.load_threaded_get(path)
				_pending_texture_paths.remove_at(index)
				if int(state.ref_count) <= 0:
					_texture_states.erase(path)
				elif resource_value is Texture2D:
					state.status = &"loaded"
					state.resource = resource_value
				else:
					state.status = &"failed"
					state.resource = null
					_failed_texture_loads += 1
				loads_changed = true
			ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				_pending_texture_paths.remove_at(index)
				if int(state.ref_count) <= 0:
					_texture_states.erase(path)
				else:
					state.status = &"failed"
					state.resource = null
					_failed_texture_loads += 1
				loads_changed = true
		index -= 1
	if loads_changed:
		_refresh_active_bindings()


func _refresh_active_bindings() -> void:
	var index := _active_binding_ids.size() - 1
	while index >= 0:
		if index >= _active_binding_ids.size():
			index = _active_binding_ids.size() - 1
			continue
		var binding_id := _active_binding_ids[index]
		if not _bindings.has(binding_id):
			_active_binding_ids.remove_at(index)
			index -= 1
			continue
		var binding := _bindings[binding_id] as Dictionary
		_prune_binding_targets(binding_id, binding)
		if bool(binding.active):
			_refresh_binding(binding)
		index -= 1


func _refresh_binding(binding: Dictionary) -> void:
	if bool(binding.failed):
		return
	var load_state := _binding_load_state(binding)
	if load_state == &"failed":
		binding.failed = true
		return
	if load_state != &"loaded":
		return
	var desired_frame := _desired_frame_index(binding)
	if desired_frame < 0:
		return
	var frames := binding.frames as Array
	var frame := frames[desired_frame] as Dictionary
	var texture_state := _texture_states.get(String(frame.path), {}) as Dictionary
	var texture := texture_state.get("resource", null) as Texture2D
	if texture == null:
		binding.failed = true
		return
	var material_groups := binding.material_groups as Dictionary
	for group_key in material_groups:
		var material_group := material_groups[group_key] as Dictionary
		if desired_frame == int(material_group.applied_frame_index):
			continue
		var runtime_material := material_group.runtime_material as StandardMaterial3D
		if runtime_material == null:
			continue
		runtime_material.albedo_texture = texture
		material_group.applied_frame_index = desired_frame
		_frame_switches += 1


func _binding_load_state(binding: Dictionary) -> StringName:
	for path_value in binding.paths as Array[String]:
		if not _texture_states.has(path_value):
			return &"loading"
		var state := _texture_states[path_value] as Dictionary
		if StringName(state.status) == &"failed":
			return &"failed"
		if StringName(state.status) != &"loaded":
			return &"loading"
	return &"loaded"


func _desired_frame_index(binding: Dictionary) -> int:
	if _source_tick < int(binding.first_hold_ticks):
		return -1
	var period_ticks := int(binding.period_ticks)
	if period_ticks <= 0:
		return -1
	var phase_tick := _source_tick % period_ticks
	var frames := binding.frames as Array
	var frame_index := 0
	while frame_index < frames.size():
		if phase_tick < int((frames[frame_index] as Dictionary).end_tick):
			return frame_index
		frame_index += 1
	return frames.size() - 1


func _prune_released_surfaces() -> void:
	var active_index := _active_binding_ids.size() - 1
	while active_index >= 0:
		if active_index >= _active_binding_ids.size():
			active_index = _active_binding_ids.size() - 1
			continue
		var binding_id := _active_binding_ids[active_index]
		if _bindings.has(binding_id):
			_prune_binding_targets(binding_id, _bindings[binding_id] as Dictionary)
		active_index -= 1


func _prune_binding_targets(binding_id: StringName, binding: Dictionary) -> void:
	var targets := binding.targets as Array
	var target_index := targets.size() - 1
	while target_index >= 0:
		var stable_id := StringName(targets[target_index])
		if not _registrations.has(stable_id):
			targets.remove_at(target_index)
		else:
			var target := _registrations[stable_id] as Dictionary
			var mesh := (target.mesh_ref as WeakRef).get_ref() as MeshInstance3D
			if mesh == null or not is_instance_valid(mesh):
				_remove_registration(stable_id, false, true)
		target_index -= 1
	if targets.is_empty():
		_deactivate_binding(binding_id, binding)


func _remove_registration(stable_id: StringName, restore_override: bool, pruned: bool) -> void:
	if not _registrations.has(stable_id):
		return
	var target := _registrations[stable_id] as Dictionary
	var binding_id := StringName(target.binding_id)
	var material_group_key := String(target.material_group_key)
	var binding := _bindings.get(binding_id, {}) as Dictionary
	var material_groups := binding.get("material_groups", {}) as Dictionary
	var material_group := material_groups.get(material_group_key, {}) as Dictionary
	var mesh := (target.mesh_ref as WeakRef).get_ref() as MeshInstance3D
	if restore_override and mesh != null and is_instance_valid(mesh):
		var surface_index := int(target.surface_index)
		if mesh.mesh != null and surface_index >= 0 and surface_index < mesh.mesh.get_surface_count():
			var runtime_material := material_group.get("runtime_material", null) as StandardMaterial3D
			if mesh.get_surface_override_material(surface_index) == runtime_material:
				mesh.set_surface_override_material(surface_index, target.previous_override as Material)
	_surface_owners.erase(String(target.surface_key))
	_registrations.erase(stable_id)
	if _bindings.has(binding_id):
		var targets := binding.targets as Array
		var target_index := targets.find(stable_id)
		if target_index >= 0:
			targets.remove_at(target_index)
		if not material_group.is_empty():
			material_group.references = maxi(0, int(material_group.references) - 1)
			if int(material_group.references) == 0:
				material_groups.erase(material_group_key)
		if targets.is_empty():
			_deactivate_binding(binding_id, binding)
	if pruned:
		_pruned_surfaces += 1


func _surface_key(mesh_instance: MeshInstance3D, surface_index: int) -> String:
	return "%d:%d" % [mesh_instance.get_instance_id(), surface_index]


func _material_group_key(material: StandardMaterial3D) -> String:
	if not material.resource_name.is_empty():
		return "name:%s" % material.resource_name
	if not material.resource_path.is_empty():
		return "path:%s" % material.resource_path
	return "instance:%d" % material.get_instance_id()


func _parse_integral_number(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_INT:
		return {"ok": true, "value": int(value)}
	if typeof(value) != TYPE_FLOAT:
		return {"ok": false}
	var numeric_value := float(value)
	if (
		not is_finite(numeric_value)
		or numeric_value != floor(numeric_value)
		or numeric_value < -2147483648.0
		or numeric_value > 2147483647.0
	):
		return {"ok": false}
	return {"ok": true, "value": int(numeric_value)}


func _is_sha256(value: String) -> bool:
	if value.length() != 64:
		return false
	for character in value:
		if character not in "0123456789abcdef":
			return false
	return true


func _error_result(reason: String, message: String) -> Dictionary:
	return {
		"ok": false,
		"status": "error",
		"reason": reason,
		"error": message,
	}
