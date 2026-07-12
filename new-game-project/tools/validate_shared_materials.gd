extends SceneTree

const MaterialCatalogSupport = preload("res://tools/material_catalog_support.gd")

const CATALOG_PATH := "res://assets/platinum/matrix_catalog.json"
const FALLBACK_MANIFEST_PATH := "res://assets/platinum/matrix_0000/manifest.json"
const SHARED_MATERIAL_ROOT := "res://assets/platinum/shared_materials"
const MATERIAL_PREFIX := "dspre_"
const ASSET_GROUP_NAMES: Array[String] = ["terrain", "buildings"]

var _asset_limit := 0
var _failed := false
var _catalog_expected_unique_materials := -1
var _expected_materials: Dictionary = {}
var _expected_asset_materials: Dictionary = {}
var _content_validated_materials: Dictionary = {}


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--limit-assets="):
			_asset_limit = maxi(0, int(argument.trim_prefix("--limit-assets=")))
	call_deferred("_run")


func _run() -> void:
	var manifest_records := _discover_manifest_records()
	if _failed:
		return
	if not _collect_material_expectations(manifest_records):
		return
	var asset_paths := _collect_asset_paths(manifest_records)
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

	var material_surface_references := 0
	var referenced_material_paths: Dictionary = {}
	var validated_assets := 0
	for asset_path: String in asset_paths:
		if _asset_limit > 0 and validated_assets >= _asset_limit:
			break
		var packed := ResourceLoader.load(asset_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
		if packed == null:
			_fail("Could not load imported GLB: %s" % asset_path)
			return
		var scene := packed.instantiate()
		if scene == null:
			_fail("Could not instantiate imported GLB: %s" % asset_path)
			return
		var collection := MaterialCatalogSupport.collect_scene_materials(scene, true)
		if not bool(collection.get("ok", false)):
			scene.free()
			_fail("%s: %s" % [asset_path, String(collection.get("error", "Material collection failed."))])
			return
		var materials := collection.get("materials", {}) as Dictionary
		var expected_asset_materials := _expected_asset_materials.get(asset_path, {}) as Dictionary
		if not MaterialCatalogSupport.dictionaries_have_same_keys(materials, expected_asset_materials):
			scene.free()
			_fail(
				"Imported GLB material keys do not match its material catalog: %s (actual %s, expected %s)"
				% [asset_path, materials.keys(), expected_asset_materials.keys()]
			)
			return
		material_surface_references += int(collection.get("surface_count", 0))
		for material_name_value: Variant in materials:
			var material_name := String(material_name_value)
			var material := materials[material_name] as Material
			if not material_name.begins_with(MATERIAL_PREFIX) or not _expected_materials.has(material_name):
				scene.free()
				_fail("Material does not have an expected DSPRE name in %s: %s" % [asset_path, material_name])
				return
			var expected_path := _material_path_for_name(material_name)
			if material.resource_path != expected_path:
				scene.free()
				_fail("Material is not externalized: %s -> %s" % [material_name, material.resource_path])
				return
			if not FileAccess.file_exists(expected_path):
				scene.free()
				_fail("External material does not exist: %s" % expected_path)
				return
			referenced_material_paths[material.resource_path] = true
		if not _validate_raw_material_content(asset_path, materials, expected_asset_materials):
			scene.free()
			return
		scene.free()
		validated_assets += 1

	if material_surface_references == 0:
		_fail("No material-bearing mesh surfaces were found.")
		return

	var complete_validation := validated_assets == asset_paths.size()
	var external_material_paths := _collect_external_material_paths()
	if _failed:
		return
	var external_material_names: Dictionary = {}
	for material_path: String in external_material_paths:
		var material := ResourceLoader.load(material_path, "Material", ResourceLoader.CACHE_MODE_REUSE) as Material
		if material == null:
			_fail("Could not load external material: %s" % material_path)
			return
		var material_name := material.resource_name
		if not material_name.begins_with(MATERIAL_PREFIX):
			_fail("External material does not have a DSPRE name: %s" % material_path)
			return
		if _material_path_for_name(material_name) != material_path:
			_fail("External material filename does not match its DSPRE name: %s" % material_path)
			return
		if external_material_names.has(material_name):
			_fail("DSPRE material name maps to multiple external resources: %s" % material_name)
			return
		external_material_names[material_name] = material_path
		if not _expected_materials.has(material_name):
			_fail("External material is not present in any destination material catalog: %s" % material_path)
			return
		if complete_validation and not referenced_material_paths.has(material_path):
			_fail("External material is not referenced by any destination GLB: %s" % material_path)
			return

	if complete_validation:
		if referenced_material_paths.size() != _expected_materials.size():
			_fail(
				"Referenced material count does not match catalog expectation: %d != %d"
				% [referenced_material_paths.size(), _expected_materials.size()]
			)
			return
		if external_material_paths.size() != _expected_materials.size():
			_fail(
				"External material count does not match catalog expectation: %d != %d"
				% [external_material_paths.size(), _expected_materials.size()]
			)
			return
		if _content_validated_materials.size() != _expected_materials.size():
			_fail(
				"Content-validated material count does not match catalog expectation: %d != %d"
				% [_content_validated_materials.size(), _expected_materials.size()]
			)
			return

	print("SHARED_MATERIAL_VALIDATION_OK ", JSON.stringify({
		"catalog_used": FileAccess.file_exists(CATALOG_PATH),
		"complete": complete_validation,
		"manifests": manifest_records.size(),
		"discovered_assets": asset_paths.size(),
		"validated_assets": validated_assets,
		"assets": validated_assets,
		"material_surface_references": material_surface_references,
		"expected_materials": _expected_materials.size(),
		"content_validated_materials": _content_validated_materials.size(),
		"referenced_materials": referenced_material_paths.size(),
		"unique_materials": referenced_material_paths.size(),
		"external_materials": external_material_paths.size(),
	}))
	call_deferred("_finish_success")


func _discover_manifest_records() -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	if not FileAccess.file_exists(CATALOG_PATH):
		if not FileAccess.file_exists(FALLBACK_MANIFEST_PATH):
			_fail("Neither the matrix catalog nor fallback manifest exists.")
			return records
		records.append({
			"key": "matrix_0000",
			"manifest_path": FALLBACK_MANIFEST_PATH,
			"expected_glbs": -1,
			"expected_materials": -1,
		})
		return records

	var catalog := _load_json_object(CATALOG_PATH, "Matrix catalog")
	if _failed:
		return records
	var summary_value: Variant = catalog.get("summary", null)
	if typeof(summary_value) != TYPE_DICTIONARY:
		_fail("Matrix catalog summary is not an object: %s" % CATALOG_PATH)
		return records
	var unique_materials_value: Variant = (summary_value as Dictionary).get("unique_materials", null)
	var unique_materials_type := typeof(unique_materials_value)
	if unique_materials_type != TYPE_INT and unique_materials_type != TYPE_FLOAT:
		_fail("Matrix catalog has an invalid unique material count.")
		return records
	_catalog_expected_unique_materials = int(unique_materials_value)
	if (
		_catalog_expected_unique_materials <= 0
		or float(_catalog_expected_unique_materials) != float(unique_materials_value)
	):
		_fail("Matrix catalog has an invalid unique material count.")
		return records
	var destinations_value: Variant = catalog.get("destinations", null)
	if typeof(destinations_value) != TYPE_ARRAY:
		_fail("Matrix catalog destinations is not an array: %s" % CATALOG_PATH)
		return records
	var destinations := destinations_value as Array
	if destinations.is_empty():
		_fail("Matrix catalog contains no destinations: %s" % CATALOG_PATH)
		return records

	var seen_paths: Dictionary = {}
	for destination_index in destinations.size():
		var destination_value: Variant = destinations[destination_index]
		if typeof(destination_value) != TYPE_DICTIONARY:
			_fail("Matrix catalog destination %d is not an object." % destination_index)
			return records
		var destination := destination_value as Dictionary
		var destination_key := String(destination.get("key", "destination_%d" % destination_index))
		var manifest_value: Variant = destination.get("manifest", null)
		if typeof(manifest_value) != TYPE_STRING or String(manifest_value).is_empty():
			_fail("Matrix catalog destination %s has no manifest path." % destination_key)
			return records
		var glbs_value: Variant = destination.get("glbs", null)
		var glbs_type := typeof(glbs_value)
		if glbs_type != TYPE_INT and glbs_type != TYPE_FLOAT:
			_fail("Matrix catalog destination %s has an invalid GLB count." % destination_key)
			return records
		var expected_glbs := int(glbs_value)
		if expected_glbs < 0 or float(expected_glbs) != float(glbs_value):
			_fail("Matrix catalog destination %s has an invalid GLB count." % destination_key)
			return records
		var materials_value: Variant = destination.get("materials", null)
		var materials_type := typeof(materials_value)
		if materials_type != TYPE_INT and materials_type != TYPE_FLOAT:
			_fail("Matrix catalog destination %s has an invalid material count." % destination_key)
			return records
		var expected_materials := int(materials_value)
		if expected_materials <= 0 or float(expected_materials) != float(materials_value):
			_fail("Matrix catalog destination %s has an invalid material count." % destination_key)
			return records
		var manifest_path := _resolve_relative_path(CATALOG_PATH, String(manifest_value))
		if seen_paths.has(manifest_path):
			_fail("Matrix catalog lists a manifest more than once: %s" % manifest_path)
			return records
		if not FileAccess.file_exists(manifest_path):
			_fail("Destination manifest does not exist: %s" % manifest_path)
			return records
		seen_paths[manifest_path] = true
		records.append({
			"key": destination_key,
			"manifest_path": manifest_path,
			"expected_glbs": expected_glbs,
			"expected_materials": expected_materials,
		})

	return records


func _collect_material_expectations(manifest_records: Array[Dictionary]) -> bool:
	var manifest_paths: Array[String] = []
	for record: Dictionary in manifest_records:
		manifest_paths.append(String(record["manifest_path"]))
	var result := MaterialCatalogSupport.collect_expectations(manifest_paths)
	if not bool(result.get("ok", false)):
		_fail(String(result.get("error", "Could not collect material catalog expectations.")))
		return false
	_expected_materials = result.get("expected_materials", {}) as Dictionary
	_expected_asset_materials = result.get("asset_materials", {}) as Dictionary
	var manifest_material_counts := result.get("manifest_material_counts", {}) as Dictionary
	if _expected_materials.is_empty() or _expected_asset_materials.is_empty():
		_fail("Material catalogs contain no material or asset expectations.")
		return false
	if (
		_catalog_expected_unique_materials >= 0
		and _catalog_expected_unique_materials != _expected_materials.size()
	):
		_fail(
			"Matrix catalog unique material count disagrees with destination catalogs: %d != %d"
			% [_catalog_expected_unique_materials, _expected_materials.size()]
		)
		return false
	for record: Dictionary in manifest_records:
		var expected_count := int(record.get("expected_materials", -1))
		if expected_count < 0:
			continue
		var manifest_path := String(record["manifest_path"])
		var actual_count := int(manifest_material_counts.get(manifest_path, -1))
		if expected_count != actual_count:
			_fail(
				"Catalog material count does not match manifest %s: %d != %d"
				% [record["key"], expected_count, actual_count]
			)
			return false
	return true


func _collect_asset_paths(manifest_records: Array[Dictionary]) -> Array[String]:
	var asset_paths: Array[String] = []
	var seen_paths: Dictionary = {}
	for record: Dictionary in manifest_records:
		var manifest_path := String(record["manifest_path"])
		var manifest := _load_json_object(manifest_path, "Manifest")
		if _failed:
			return asset_paths
		var assets_value: Variant = manifest.get("assets", null)
		if typeof(assets_value) != TYPE_DICTIONARY:
			_fail("Manifest assets is not an object: %s" % manifest_path)
			return asset_paths
		var assets := assets_value as Dictionary
		var destination_asset_count := 0
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
						_fail("A destination GLB is listed more than once: %s" % asset_path)
						return asset_paths
					seen_paths[asset_path] = true
					asset_paths.append(asset_path)
					destination_asset_count += 1

		var expected_glbs := int(record["expected_glbs"])
		if expected_glbs >= 0 and destination_asset_count != expected_glbs:
			_fail("Catalog GLB count does not match manifest %s: %d != %d" % [record["key"], expected_glbs, destination_asset_count])
			return asset_paths

	asset_paths.sort()
	return asset_paths


func _validate_raw_material_content(
	asset_path: String,
	imported_materials: Dictionary,
	expected_asset_materials: Dictionary
) -> bool:
	var requires_validation := false
	for material_name_value: Variant in expected_asset_materials:
		if not _content_validated_materials.has(String(material_name_value)):
			requires_validation = true
			break
	if not requires_validation:
		return true

	var raw_result := MaterialCatalogSupport.load_raw_scene_materials(asset_path)
	if not bool(raw_result.get("ok", false)):
		_fail(String(raw_result.get("error", "Raw GLB material validation failed.")))
		return false
	var raw_materials := raw_result.get("materials", {}) as Dictionary
	if not MaterialCatalogSupport.dictionaries_have_same_keys(raw_materials, expected_asset_materials):
		_fail("Raw GLB material keys do not match its material catalog: %s" % asset_path)
		return false
	for material_name_value: Variant in expected_asset_materials:
		var material_name := String(material_name_value)
		if _content_validated_materials.has(material_name):
			continue
		var raw_material := raw_materials.get(material_name) as Material
		var imported_material := imported_materials.get(material_name) as Material
		if not MaterialCatalogSupport.materials_equivalent(raw_material, imported_material):
			_fail("External material content does not match raw GLB material %s: %s" % [material_name, asset_path])
			return false
		_content_validated_materials[material_name] = true
	return true


func _collect_external_material_paths() -> Array[String]:
	var material_paths: Array[String] = []
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(SHARED_MATERIAL_ROOT)):
		_fail("Shared material directory does not exist: %s" % SHARED_MATERIAL_ROOT)
		return material_paths
	_append_external_material_paths(SHARED_MATERIAL_ROOT, material_paths)
	material_paths.sort()
	if material_paths.is_empty():
		_fail("Shared material directory contains no .tres resources: %s" % SHARED_MATERIAL_ROOT)
	return material_paths


func _append_external_material_paths(directory_path: String, material_paths: Array[String]) -> void:
	for file_name: String in DirAccess.get_files_at(directory_path):
		if file_name.get_extension().to_lower() == "tres":
			material_paths.append(directory_path.path_join(file_name))
	for child_name: String in DirAccess.get_directories_at(directory_path):
		if child_name.begins_with("."):
			continue
		_append_external_material_paths(directory_path.path_join(child_name), material_paths)


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


func _material_path_for_name(material_name: String) -> String:
	return SHARED_MATERIAL_ROOT.path_join("%s.tres" % material_name.trim_prefix(MATERIAL_PREFIX))


func _fail(message: String) -> void:
	if _failed:
		return
	_failed = true
	push_error(message)
	quit(1)


func _finish_success() -> void:
	quit(0)
