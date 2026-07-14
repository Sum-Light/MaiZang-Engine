extends SceneTree

const FieldTextureAnimationController = preload(
	"res://scripts/platinum_field_texture_animation_controller.gd"
)
const LOAD_TIMEOUT_FRAMES := 240

var _temporary_paths: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var frame_colors: Array[Color] = [Color.RED, Color.GREEN, Color.BLUE]
	for frame_index in frame_colors.size():
		var path := "user://field_texture_animation_frame_%d.tres" % frame_index
		var texture := _make_texture(frame_colors[frame_index])
		if ResourceSaver.save(texture, path) != OK:
			_fail("Could not save threaded texture fixture %d." % frame_index)
			return
		_temporary_paths.append(path)
	var base_texture := _make_texture(Color.WHITE)
	var base_texture_path := "user://%s.tres" % "a".repeat(64)
	if ResourceSaver.save(base_texture, base_texture_path) != OK:
		_fail("Could not save the base texture lookup fixture.")
		return
	_temporary_paths.append(base_texture_path)
	base_texture = ResourceLoader.load(base_texture_path, "Texture2D") as Texture2D
	if base_texture == null:
		_fail("Could not reload the base texture lookup fixture.")
		return

	var controller := FieldTextureAnimationController.new()
	controller.name = "FieldTextureAnimationController"
	root.add_child(controller)
	controller.set_physics_process(false)
	var catalog_section := {
		"schema_version": 1,
		"source_fps": 30,
		"bindings": [{
			"binding_id": "lake_material",
			"base_texture_sha256": "a".repeat(64),
			"frames": [
				{"path": _temporary_paths[0], "hold_ticks": 2},
				{"path": _temporary_paths[1], "hold_ticks": 2},
				{"path": _temporary_paths[2], "hold_ticks": 2},
			],
		}],
	}
	var configure_result := controller.configure(catalog_section, "")
	if not bool(configure_result.get("ok", false)):
		_fail(String(configure_result.get("error", "Controller configuration failed.")))
		return
	var configured_stats := controller.get_stats() as Dictionary
	if (
		int(configured_stats.get("retained_textures", -1)) != 0
		or int(configured_stats.get("loading_textures", -1)) != 0
	):
		_fail("Catalog configuration eagerly requested unused frame textures.")
		return

	var base_material := StandardMaterial3D.new()
	base_material.resource_name = "dspre_mat_lake"
	base_material.albedo_texture = base_texture
	if controller.resolve_binding_id(base_material) != &"lake_material":
		_fail("Base texture SHA did not resolve its animation binding.")
		return
	var shared_mesh := _make_mesh(base_material)
	var first_mesh := MeshInstance3D.new()
	first_mesh.mesh = shared_mesh
	root.add_child(first_mesh)
	var second_mesh := MeshInstance3D.new()
	second_mesh.mesh = shared_mesh
	root.add_child(second_mesh)
	var alternate_material := base_material.duplicate(false) as StandardMaterial3D
	alternate_material.resource_name = "dspre_mat_lake_transparent"
	alternate_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	alternate_material.albedo_color = Color(1.0, 1.0, 1.0, 0.5)
	var alternate_mesh := MeshInstance3D.new()
	alternate_mesh.mesh = _make_mesh(alternate_material)
	root.add_child(alternate_mesh)

	var first_result := controller.register_surface(
		&"cell_0_lake_0",
		first_mesh,
		0,
		&"lake_material",
		base_material
	)
	var second_result := controller.register_surface(
		&"cell_0_lake_1",
		second_mesh,
		0,
		&"lake_material",
		base_material
	)
	var alternate_result := controller.register_surface(
		&"cell_0_lake_transparent",
		alternate_mesh,
		0,
		&"lake_material",
		alternate_material
	)
	if (
		not bool(first_result.get("ok", false))
		or not bool(second_result.get("ok", false))
		or not bool(alternate_result.get("ok", false))
	):
		_fail("Animated surfaces could not be registered.")
		return
	var first_override := first_mesh.get_surface_override_material(0) as StandardMaterial3D
	var second_override := second_mesh.get_surface_override_material(0) as StandardMaterial3D
	var alternate_override := alternate_mesh.get_surface_override_material(0) as StandardMaterial3D
	if (
		first_override == null
		or first_override == base_material
		or first_override != second_override
		or alternate_override == null
		or alternate_override == first_override
		or alternate_override.transparency != BaseMaterial3D.TRANSPARENCY_ALPHA
		or not is_equal_approx(alternate_override.albedo_color.a, 0.5)
		or shared_mesh.surface_get_material(0) != base_material
		or base_material.albedo_texture != base_texture
	):
		_fail("Animated surfaces did not share one isolated runtime material override.")
		return
	if int((controller.get_stats() as Dictionary).get("active_material_groups", -1)) != 2:
		_fail("Distinct material signatures were incorrectly merged into one runtime duplicate.")
		return

	if not await _wait_for_texture_loads(controller, 3):
		_fail("Threaded field texture fixtures did not finish loading.")
		return
	if not _texture_has_path(first_override.albedo_texture, base_texture_path):
		_fail("Animation replaced the original texture before its first hold completed.")
		return

	controller._physics_process(1.0 / 60.0)
	if not _texture_has_path(first_override.albedo_texture, base_texture_path):
		_fail("Animation advanced before one 30 Hz source tick.")
		return
	controller._physics_process(1.0 / 60.0)
	if not _texture_has_path(first_override.albedo_texture, base_texture_path):
		_fail("Animation did not preserve the base texture through the initial hold.")
		return
	controller._physics_process(1.0 / 30.0)
	if (
		not _texture_has_path(first_override.albedo_texture, _temporary_paths[1])
		or not _texture_has_path(alternate_override.albedo_texture, _temporary_paths[1])
	):
		_fail("Animation did not switch to frame 1 after two source ticks.")
		return
	controller._physics_process(2.0 / 30.0)
	if not _texture_has_path(first_override.albedo_texture, _temporary_paths[2]):
		_fail("Animation did not switch to frame 2 on the global timeline.")
		return

	var late_mesh := MeshInstance3D.new()
	late_mesh.mesh = shared_mesh
	root.add_child(late_mesh)
	var late_result := controller.register_surface(
		&"cell_1_lake_0",
		late_mesh,
		0,
		&"lake_material",
		base_material
	)
	var late_override := late_mesh.get_surface_override_material(0) as StandardMaterial3D
	if (
		not bool(late_result.get("ok", false))
		or late_override != first_override
		or not _texture_has_path(late_override.albedo_texture, _temporary_paths[2])
	):
		_fail("A late streamed surface did not join the existing material and global phase.")
		return

	controller._physics_process(2.0 / 30.0)
	if not _texture_has_path(first_override.albedo_texture, _temporary_paths[0]):
		_fail("Animation did not wrap to the exported frame 0 texture.")
		return
	var unregister_result := controller.unregister_surface(&"cell_0_lake_0")
	if (
		not bool(unregister_result.get("ok", false))
		or first_mesh.get_surface_override_material(0) != null
		or second_mesh.get_surface_override_material(0) != first_override
	):
		_fail("Explicit unregister did not restore only the requested surface.")
		return
	controller.unregister_surface(&"cell_0_lake_1")
	controller.unregister_surface(&"cell_1_lake_0")
	controller.unregister_surface(&"cell_0_lake_transparent")
	if alternate_mesh.get_surface_override_material(0) != null:
		_fail("Material-group unregister did not restore its original surface override.")
		return
	var released_stats := controller.get_stats()
	if (
		int(released_stats.get("registered_surfaces", -1)) != 0
		or int(released_stats.get("active_bindings", -1)) != 0
		or int(released_stats.get("retained_textures", -1)) != 0
	):
		_fail("Unused field animation textures or registrations remained retained.")
		return

	var released_mesh := MeshInstance3D.new()
	released_mesh.mesh = shared_mesh
	root.add_child(released_mesh)
	var weak_result := controller.register_surface(
		&"cell_2_lake_0",
		released_mesh,
		0,
		&"lake_material",
		base_material
	)
	if not bool(weak_result.get("ok", false)):
		_fail("Weak-reference fixture could not be registered.")
		return
	var released_ref: WeakRef = weakref(released_mesh)
	released_mesh.free()
	controller._physics_process(1.0 / 30.0)
	if not await _wait_for_pending_loads(controller):
		_fail("Released surface left a threaded texture request pending.")
		return
	var final_stats := controller.get_stats()
	if (
		released_ref.get_ref() != null
		or int(final_stats.get("registered_surfaces", -1)) != 0
		or int(final_stats.get("pruned_surfaces", -1)) < 1
		or int(final_stats.get("failed_texture_loads", -1)) != 0
	):
		_fail("Released surface was retained or not pruned from the controller.")
		return
	if shared_mesh.surface_get_material(0) != base_material or base_material.albedo_texture != base_texture:
		_fail("Controller mutated the shared ArrayMesh material.")
		return

	var handoff_mesh := MeshInstance3D.new()
	handoff_mesh.mesh = shared_mesh
	root.add_child(handoff_mesh)
	var handoff_result := controller.register_surface(
		&"handoff_lake_0",
		handoff_mesh,
		0,
		&"lake_material",
		base_material
	)
	if (
		not bool(handoff_result.get("ok", false))
		or int((controller.get_stats() as Dictionary).get("loading_textures", 0)) != 3
	):
		_fail("Pending-request handoff fixture did not start three frame loads.")
		return
	controller.clear()
	controller.free()

	var replacement_controller := FieldTextureAnimationController.new()
	replacement_controller.name = "ReplacementFieldTextureAnimationController"
	root.add_child(replacement_controller)
	replacement_controller.set_physics_process(false)
	var replacement_configure := replacement_controller.configure(catalog_section, "")
	if not bool(replacement_configure.get("ok", false)):
		_fail("Replacement controller could not accept the animation catalog.")
		return
	var replacement_result := replacement_controller.register_surface(
		&"replacement_lake_0",
		handoff_mesh,
		0,
		&"lake_material",
		base_material
	)
	if (
		not bool(replacement_result.get("ok", false))
		or not await _wait_for_texture_loads(replacement_controller, 3)
		or int((replacement_controller.get_stats() as Dictionary).get("failed_texture_loads", -1)) != 0
	):
		_fail("Replacement controller did not drain and adopt pending frame requests.")
		return
	replacement_controller.unregister_surface(&"replacement_lake_0")
	replacement_controller.clear()
	replacement_controller.free()

	print("FIELD_TEXTURE_ANIMATION_OK ", JSON.stringify({
		"source_tick": int(final_stats.get("source_tick", -1)),
		"frame_switches": int(final_stats.get("frame_switches", -1)),
		"shared_runtime_material": true,
		"threaded_subthreads": false,
		"world_scan_per_tick": false,
		"weak_surface_released": true,
		"pending_request_handoff": true,
	}))
	first_mesh.free()
	second_mesh.free()
	late_mesh.free()
	alternate_mesh.free()
	handoff_mesh.free()
	_cleanup()
	quit(0)


func _wait_for_texture_loads(controller: Node, expected_count: int) -> bool:
	for frame in LOAD_TIMEOUT_FRAMES:
		controller._physics_process(0.0)
		var stats := controller.get_stats() as Dictionary
		if int(stats.get("failed_texture_loads", 0)) > 0:
			return false
		if int(stats.get("loaded_textures", 0)) == expected_count:
			return true
		await process_frame
	return false


func _wait_for_pending_loads(controller: Node) -> bool:
	for frame in LOAD_TIMEOUT_FRAMES:
		controller._physics_process(0.0)
		if int((controller.get_stats() as Dictionary).get("loading_textures", 0)) == 0:
			return true
		await process_frame
	return false


func _make_texture(_color: Color) -> PlaceholderTexture2D:
	var texture := PlaceholderTexture2D.new()
	texture.size = Vector2(2.0, 2.0)
	return texture


func _make_mesh(material: StandardMaterial3D) -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3.ZERO,
		Vector3.RIGHT,
		Vector3.FORWARD,
	])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)
	return mesh


func _texture_has_path(texture: Texture2D, expected_path: String) -> bool:
	return texture != null and texture.resource_path == expected_path


func _cleanup() -> void:
	for path in _temporary_paths:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_temporary_paths.clear()


func _fail(message: String) -> void:
	_cleanup()
	push_error(message)
	quit(1)
