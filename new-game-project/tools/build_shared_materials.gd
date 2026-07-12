extends SceneTree

const MaterialCatalogSupport = preload("res://tools/material_catalog_support.gd")

const CATALOG_PATH := "res://assets/platinum/matrix_catalog.json"
const FALLBACK_MANIFEST_PATH := "res://assets/platinum/matrix_0000/manifest.json"
const SHARED_MATERIAL_ROOT := "res://assets/platinum/shared_materials"
const MATERIAL_PREFIX := "dspre_"
const ASSET_GROUP_NAMES: Array[String] = ["terrain", "buildings"]

var _asset_limit := 0
var _configured_assets := 0
var _saved_materials := 0
var _reused_materials := 0
var _pruned_materials := 0
var _asset_filters: Dictionary = {}
var _reuse_existing_materials := false
var _material_paths: Dictionary = {}
var _expected_materials: Dictionary = {}
var _expected_asset_materials: Dictionary = {}
var _validated_existing_materials: Dictionary = {}
var _failed := false


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--limit-assets="):
			_asset_limit = maxi(0, int(argument.trim_prefix("--limit-assets=")))
		elif argument.begins_with("--asset="):
			var asset_path := argument.trim_prefix("--asset=").replace("\\", "/").simplify_path()
			_asset_filters[asset_path] = true
		elif argument == "--reuse-existing-materials":
			_reuse_existing_materials = true
	call_deferred("_run")


func _run() -> void:
	var manifest_paths := _discover_manifest_paths()
	if _failed:
		return
	if not _collect_material_expectations(manifest_paths):
		return
	var asset_paths := _collect_asset_paths(manifest_paths)
	if _failed:
		return
	if asset_paths.is_empty():
		_fail("No GLBs were listed by the selected manifests.")
		return
	if asset_paths.size() != _expected_asset_materials.size():
		_fail(
			"Manifest and material catalog GLB counts disagree: %d != %d"
			% [asset_paths.size(), _expected_asset_materials.size()]
		)
		return
	for asset_path: String in asset_paths:
		if not _expected_asset_materials.has(asset_path):
			_fail("Material catalogs do not describe manifest GLB: %s" % asset_path)
			return
	var discovered_asset_count := asset_paths.size()
	if not _asset_filters.is_empty():
		var filtered_paths: Array[String] = []
		for asset_path_value: Variant in _asset_filters:
			var asset_path := String(asset_path_value)
			if not asset_paths.has(asset_path):
				_fail("Requested material asset is absent from the matrix catalog: %s" % asset_path)
				return
			filtered_paths.append(asset_path)
		filtered_paths.sort()
		asset_paths = filtered_paths
	if _reuse_existing_materials and not _validate_expected_material_files_present():
		return

	var make_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHARED_MATERIAL_ROOT))
	if make_error != OK:
		_fail("Could not create shared material directory %s (error %d)." % [SHARED_MATERIAL_ROOT, make_error])
		return

	for asset_path: String in asset_paths:
		if _asset_limit > 0 and _configured_assets >= _asset_limit:
			break
		if not _configure_asset(asset_path):
			return

	var complete_build := (
		_asset_filters.is_empty()
		and _asset_limit <= 0
		and _configured_assets == discovered_asset_count
	)
	if complete_build:
		if not _prune_stale_materials():
			return
		if not _validate_expected_material_files():
			return

	print("SHARED_MATERIAL_BUILD_OK ", JSON.stringify({
		"manifests": manifest_paths.size(),
		"discovered_assets": discovered_asset_count,
		"selected_assets": asset_paths.size(),
		"configured_assets": _configured_assets,
		"saved_materials": _saved_materials,
		"reused_materials": _reused_materials,
		"pruned_materials": _pruned_materials,
		"expected_materials": _expected_materials.size(),
		"unique_materials": _material_paths.size(),
		"complete": complete_build,
	}))
	call_deferred("_finish_success")


func _discover_manifest_paths() -> Array[String]:
	var manifest_paths: Array[String] = []
	if not FileAccess.file_exists(CATALOG_PATH):
		if not FileAccess.file_exists(FALLBACK_MANIFEST_PATH):
			_fail("Neither the matrix catalog nor fallback manifest exists.")
			return manifest_paths
		manifest_paths.append(FALLBACK_MANIFEST_PATH)
		return manifest_paths

	var catalog := _load_json_object(CATALOG_PATH, "Matrix catalog")
	if _failed:
		return manifest_paths
	var destinations_value: Variant = catalog.get("destinations", null)
	if typeof(destinations_value) != TYPE_ARRAY:
		_fail("Matrix catalog destinations is not an array: %s" % CATALOG_PATH)
		return manifest_paths
	var destinations := destinations_value as Array
	if destinations.is_empty():
		_fail("Matrix catalog contains no destinations: %s" % CATALOG_PATH)
		return manifest_paths

	var seen_paths: Dictionary = {}
	for destination_index in destinations.size():
		var destination_value: Variant = destinations[destination_index]
		if typeof(destination_value) != TYPE_DICTIONARY:
			_fail("Matrix catalog destination %d is not an object." % destination_index)
			return manifest_paths
		var destination := destination_value as Dictionary
		var manifest_value: Variant = destination.get("manifest", null)
		if typeof(manifest_value) != TYPE_STRING or String(manifest_value).is_empty():
			_fail("Matrix catalog destination %d has no manifest path." % destination_index)
			return manifest_paths
		var manifest_path := _resolve_relative_path(CATALOG_PATH, String(manifest_value))
		if seen_paths.has(manifest_path):
			_fail("Matrix catalog lists a manifest more than once: %s" % manifest_path)
			return manifest_paths
		if not FileAccess.file_exists(manifest_path):
			_fail("Destination manifest does not exist: %s" % manifest_path)
			return manifest_paths
		seen_paths[manifest_path] = true
		manifest_paths.append(manifest_path)

	return manifest_paths


func _collect_material_expectations(manifest_paths: Array[String]) -> bool:
	var result := MaterialCatalogSupport.collect_expectations(manifest_paths)
	if not bool(result.get("ok", false)):
		_fail(String(result.get("error", "Could not collect material catalog expectations.")))
		return false
	_expected_materials = result.get("expected_materials", {}) as Dictionary
	_expected_asset_materials = result.get("asset_materials", {}) as Dictionary
	if _expected_materials.is_empty() or _expected_asset_materials.is_empty():
		_fail("Material catalogs contain no material or asset expectations.")
		return false
	return true


func _collect_asset_paths(manifest_paths: Array[String]) -> Array[String]:
	var asset_paths: Array[String] = []
	var seen_paths: Dictionary = {}
	for manifest_path: String in manifest_paths:
		var manifest := _load_json_object(manifest_path, "Manifest")
		if _failed:
			return asset_paths
		var assets_value: Variant = manifest.get("assets", null)
		if typeof(assets_value) != TYPE_DICTIONARY:
			_fail("Manifest assets is not an object: %s" % manifest_path)
			return asset_paths
		var assets := assets_value as Dictionary
		for group_name: String in ASSET_GROUP_NAMES:
			var group_value: Variant = assets.get(group_name, [])
			if typeof(group_value) != TYPE_ARRAY:
				_fail("Manifest asset group %s is not an array: %s" % [group_name, manifest_path])
				return asset_paths
			for asset_value: Variant in group_value as Array:
				if typeof(asset_value) != TYPE_DICTIONARY:
					_fail("Manifest asset in group %s is not an object: %s" % [group_name, manifest_path])
					return asset_paths
				var asset := asset_value as Dictionary
				var output_glbs_value: Variant = asset.get("output_glbs", [])
				if typeof(output_glbs_value) != TYPE_ARRAY:
					_fail("Manifest asset output_glbs is not an array: %s" % manifest_path)
					return asset_paths
				for output_glb_value: Variant in output_glbs_value as Array:
					if typeof(output_glb_value) != TYPE_STRING or String(output_glb_value).is_empty():
						_fail("Manifest contains an invalid GLB path: %s" % manifest_path)
						return asset_paths
					var asset_path := _resolve_relative_path(manifest_path, String(output_glb_value))
					if not FileAccess.file_exists(asset_path):
						_fail("Manifest GLB does not exist: %s" % asset_path)
						return asset_paths
					if seen_paths.has(asset_path):
						continue
					seen_paths[asset_path] = true
					asset_paths.append(asset_path)

	asset_paths.sort()
	return asset_paths


func _load_json_object(path: String, label: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		_fail("%s does not exist: %s" % [label, path])
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		_fail("%s is not a JSON object: %s" % [label, path])
		return {}
	return parsed as Dictionary


func _resolve_relative_path(base_file_path: String, relative_path: String) -> String:
	var normalized_path := relative_path.replace("\\", "/")
	if normalized_path.begins_with("res://"):
		return normalized_path.simplify_path()
	return base_file_path.get_base_dir().path_join(normalized_path).simplify_path()


func _configure_asset(asset_path: String) -> bool:
	var packed := ResourceLoader.load(asset_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene
	if packed == null:
		_fail("Could not load imported GLB: %s" % asset_path)
		return false
	var scene := packed.instantiate()
	if scene == null:
		_fail("Could not instantiate imported GLB: %s" % asset_path)
		return false
	var collection := MaterialCatalogSupport.collect_scene_materials(scene, true)
	if not bool(collection.get("ok", false)):
		scene.free()
		_fail("%s: %s" % [asset_path, String(collection.get("error", "Material collection failed."))])
		return false
	var materials := collection.get("materials", {}) as Dictionary
	var expected_materials := _expected_asset_materials.get(asset_path, {}) as Dictionary
	if not MaterialCatalogSupport.dictionaries_have_same_keys(materials, expected_materials):
		scene.free()
		_fail(
			"Imported GLB material keys do not match its material catalog: %s (actual %s, expected %s)"
			% [asset_path, materials.keys(), expected_materials.keys()]
		)
		return false

	var raw_materials: Dictionary = {}
	var needs_raw_validation := false
	for material_name_value: Variant in materials:
		var material_name := String(material_name_value)
		if not material_name.begins_with(MATERIAL_PREFIX) or not _expected_materials.has(material_name):
			scene.free()
			_fail("Imported GLB has an unexpected material name %s: %s" % [material_name, asset_path])
			return false
		var material_path := _material_path_for_name(material_name)
		if FileAccess.file_exists(material_path) and not _validated_existing_materials.has(material_name):
			needs_raw_validation = true
	if needs_raw_validation:
		var raw_result := MaterialCatalogSupport.load_raw_scene_materials(asset_path)
		if not bool(raw_result.get("ok", false)):
			scene.free()
			_fail(String(raw_result.get("error", "Raw GLB material validation failed.")))
			return false
		raw_materials = raw_result.get("materials", {}) as Dictionary
		if not MaterialCatalogSupport.dictionaries_have_same_keys(raw_materials, expected_materials):
			scene.free()
			_fail("Raw GLB material keys do not match its material catalog: %s" % asset_path)
			return false

	var material_settings: Dictionary = {}
	for material_name_value: Variant in materials:
		var material_name := String(material_name_value)
		var source_material: Material = raw_materials.get(material_name) as Material
		var material_path := _get_or_save_material(materials[material_name] as Material, source_material)
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


func _get_or_save_material(material: Material, source_material: Material) -> String:
	var material_name := material.resource_name
	if _material_paths.has(material_name):
		_reused_materials += 1
		return String(_material_paths[material_name])

	var material_path := _material_path_for_name(material_name)
	if FileAccess.file_exists(material_path):
		if source_material == null and not _reuse_existing_materials:
			_fail("Existing shared material was not independently validated from its raw GLB: %s" % material_name)
			return ""
		var external_material := ResourceLoader.load(
			material_path, "Material", ResourceLoader.CACHE_MODE_IGNORE_DEEP
		) as Material
		if (
			external_material == null
			or external_material.resource_name != material_name
			or (
				not _reuse_existing_materials
				and not MaterialCatalogSupport.materials_equivalent(source_material, external_material)
			)
		):
			_fail(
				"Existing shared material does not match raw GLB content; remove or rebuild it: %s"
				% material_path
			)
			return ""
		_material_paths[material_name] = material_path
		_validated_existing_materials[material_name] = true
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


func _material_path_for_name(material_name: String) -> String:
	return SHARED_MATERIAL_ROOT.path_join("%s.tres" % material_name.trim_prefix(MATERIAL_PREFIX))


func _prune_stale_materials() -> bool:
	var expected_paths: Dictionary = {}
	for material_name_value: Variant in _expected_materials:
		expected_paths[_material_path_for_name(String(material_name_value))] = true
	var existing_paths: Array[String] = []
	_append_external_material_paths(SHARED_MATERIAL_ROOT, existing_paths)
	for material_path: String in existing_paths:
		if expected_paths.has(material_path):
			continue
		var remove_error := DirAccess.remove_absolute(ProjectSettings.globalize_path(material_path))
		if remove_error != OK:
			_fail("Could not remove stale shared material %s (error %d)." % [material_path, remove_error])
			return false
		_pruned_materials += 1
	return true


func _validate_expected_material_files() -> bool:
	if not _validate_expected_material_files_present():
		return false
	for material_name_value: Variant in _expected_materials:
		var material_name := String(material_name_value)
		if not _material_paths.has(material_name):
			_fail("Expected shared material was not found on any catalog GLB: %s" % material_name)
			return false
	return true


func _validate_expected_material_files_present() -> bool:
	for material_name_value: Variant in _expected_materials:
		var material_name := String(material_name_value)
		var material_path := _material_path_for_name(material_name)
		if not FileAccess.file_exists(material_path):
			_fail("Expected shared material was not generated: %s" % material_path)
			return false
	return true


func _append_external_material_paths(directory_path: String, material_paths: Array[String]) -> void:
	for file_name: String in DirAccess.get_files_at(directory_path):
		if file_name.get_extension().to_lower() == "tres":
			material_paths.append(directory_path.path_join(file_name))
	for child_name: String in DirAccess.get_directories_at(directory_path):
		if child_name.begins_with("."):
			continue
		_append_external_material_paths(directory_path.path_join(child_name), material_paths)


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
	if _failed:
		return
	_failed = true
	push_error(message)
	quit(1)


func _finish_success() -> void:
	quit(0)
