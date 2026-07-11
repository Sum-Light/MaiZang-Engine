extends SceneTree

const MANIFEST_PATH := "res://assets/platinum/matrix_0000/manifest.json"
const SHARED_MATERIAL_ROOT := "res://assets/platinum/shared_materials"
const MATERIAL_PREFIX := "dspre_"

var _asset_limit := 0
var _configured_assets := 0
var _saved_materials := 0
var _reused_materials := 0
var _material_paths: Dictionary = {}


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--limit-assets="):
			_asset_limit = maxi(0, int(argument.trim_prefix("--limit-assets=")))
	call_deferred("_run")


func _run() -> void:
	if not FileAccess.file_exists(MANIFEST_PATH):
		_fail("Manifest does not exist: %s" % MANIFEST_PATH)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		_fail("Manifest is not a JSON object.")
		return

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHARED_MATERIAL_ROOT))
	var manifest := parsed as Dictionary
	var assets: Dictionary = manifest.get("assets", {})
	var asset_paths: Array[String] = []
	for group_name in ["terrain", "buildings"]:
		for asset_value: Variant in assets.get(group_name, []):
			var asset := asset_value as Dictionary
			var output_glbs: Array = asset.get("output_glbs", [])
			if output_glbs.is_empty():
				continue
			asset_paths.append(MANIFEST_PATH.get_base_dir().path_join(String(output_glbs[0])))

	asset_paths.sort()
	for asset_path: String in asset_paths:
		if _asset_limit > 0 and _configured_assets >= _asset_limit:
			break
		if not _configure_asset(asset_path):
			return

	print("SHARED_MATERIAL_BUILD_OK ", JSON.stringify({
		"configured_assets": _configured_assets,
		"saved_materials": _saved_materials,
		"reused_materials": _reused_materials,
		"unique_materials": _material_paths.size(),
	}))
	call_deferred("_finish_success")


func _configure_asset(asset_path: String) -> bool:
	var packed := ResourceLoader.load(asset_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene
	if packed == null:
		_fail("Could not load imported GLB: %s" % asset_path)
		return false
	var scene := packed.instantiate()
	var material_settings: Dictionary = {}
	var stack: Array[Node] = [scene]
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
			if material == null or not material.resource_name.begins_with(MATERIAL_PREFIX):
				continue
			var material_name := material.resource_name
			var material_path := _get_or_save_material(material)
			if material_path.is_empty():
				scene.free()
				return false
			material_settings[material_name] = {
				"use_external/enabled": true,
				"use_external/path": material_path,
				"use_external/fallback_path": material_path,
			}

	scene.free()
	if material_settings.is_empty():
		_fail("Imported GLB has no DSPRE materials: %s" % asset_path)
		return false
	if not _write_import_settings(asset_path, material_settings):
		return false
	_configured_assets += 1
	return true


func _get_or_save_material(material: Material) -> String:
	var material_name := material.resource_name
	if _material_paths.has(material_name):
		_reused_materials += 1
		return String(_material_paths[material_name])

	var material_path := SHARED_MATERIAL_ROOT.path_join("%s.tres" % material_name.trim_prefix(MATERIAL_PREFIX))
	if FileAccess.file_exists(material_path):
		_material_paths[material_name] = material_path
		_reused_materials += 1
		return material_path

	var external_material := material.duplicate(false) as Material
	external_material.resource_name = material_name
	var save_error := ResourceSaver.save(external_material, material_path)
	if save_error != OK:
		_fail("Could not save shared material %s (error %d)." % [material_path, save_error])
		return ""
	_material_paths[material_name] = material_path
	_saved_materials += 1
	return material_path


func _write_import_settings(asset_path: String, material_settings: Dictionary) -> bool:
	var import_path := ProjectSettings.globalize_path("%s.import" % asset_path)
	var config := ConfigFile.new()
	var load_error := config.load(import_path)
	if load_error != OK:
		_fail("Could not load import settings %s (error %d)." % [import_path, load_error])
		return false

	var subresources: Dictionary = config.get_value("params", "_subresources", {})
	subresources["materials"] = material_settings
	config.set_value("params", "_subresources", subresources)
	var save_error := config.save(import_path)
	if save_error != OK:
		_fail("Could not save import settings %s (error %d)." % [import_path, save_error])
		return false
	return true


func _fail(message: String) -> void:
	push_error(message)
	quit(1)


func _finish_success() -> void:
	quit(0)
