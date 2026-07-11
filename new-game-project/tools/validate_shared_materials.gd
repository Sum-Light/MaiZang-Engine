extends SceneTree

const MANIFEST_PATH := "res://assets/platinum/matrix_0000/manifest.json"
const SHARED_MATERIAL_ROOT := "res://assets/platinum/shared_materials"
const EXPECTED_ASSET_COUNT := 398
const EXPECTED_MATERIAL_SURFACE_REFERENCES := 3249
const EXPECTED_UNIQUE_MATERIALS := 511


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		_fail("Manifest is not a JSON object.")
		return

	var manifest := parsed as Dictionary
	var assets: Dictionary = manifest.get("assets", {})
	var asset_paths: Array[String] = []
	for group_name in ["terrain", "buildings"]:
		for asset_value: Variant in assets.get(group_name, []):
			var asset := asset_value as Dictionary
			var output_glbs: Array = asset.get("output_glbs", [])
			if not output_glbs.is_empty():
				asset_paths.append(MANIFEST_PATH.get_base_dir().path_join(String(output_glbs[0])))

	var material_surface_references := 0
	var material_paths: Dictionary = {}
	for asset_path: String in asset_paths:
		var packed := ResourceLoader.load(asset_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene
		if packed == null:
			_fail("Could not load imported GLB: %s" % asset_path)
			return
		var scene := packed.instantiate()
		var stack: Array[Node] = [scene]
		while not stack.is_empty():
			var node: Node = stack.pop_back()
			for child: Node in node.get_children():
				stack.append(child)
			if not node is MeshInstance3D:
				continue
			var mesh_instance := node as MeshInstance3D
			for surface_index in mesh_instance.mesh.get_surface_count():
				var material := mesh_instance.mesh.surface_get_material(surface_index)
				if material == null:
					continue
				material_surface_references += 1
				var expected_path := SHARED_MATERIAL_ROOT.path_join("%s.tres" % material.resource_name.trim_prefix("dspre_"))
				if material.resource_path != expected_path:
					scene.free()
					_fail("Material is not externalized: %s -> %s" % [material.resource_name, material.resource_path])
					return
				material_paths[material.resource_path] = true
		scene.free()

	if asset_paths.size() != EXPECTED_ASSET_COUNT:
		_fail("Unexpected asset count: %d" % asset_paths.size())
		return
	if material_surface_references != EXPECTED_MATERIAL_SURFACE_REFERENCES:
		_fail("Unexpected material surface reference count: %d" % material_surface_references)
		return
	if material_paths.size() != EXPECTED_UNIQUE_MATERIALS:
		_fail("Unexpected unique material count: %d" % material_paths.size())
		return

	print("SHARED_MATERIAL_VALIDATION_OK ", JSON.stringify({
		"assets": asset_paths.size(),
		"material_surface_references": material_surface_references,
		"unique_materials": material_paths.size(),
	}))
	call_deferred("_finish_success")


func _fail(message: String) -> void:
	push_error(message)
	quit(1)


func _finish_success() -> void:
	quit(0)
