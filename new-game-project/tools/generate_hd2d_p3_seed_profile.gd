extends SceneTree

const MANIFEST_PATH := "res://assets/platinum/matrix_0000/manifest.json"
const CATALOG_PATH := "res://assets/platinum/matrix_0000/material_catalog.json"
const MATRIX_ROOT := "res://assets/platinum/matrix_0000"
const DEFAULT_OUTPUT_PATH := "res://assets/platinum/hd2d/p3_city.profile.json"
const TARGET_CELL := Vector2i(3, 27)
const GLB_MAGIC := 0x46546C67
const GLB_JSON_CHUNK := 0x4E4F534A
const TERRAIN_MATERIAL_NAMES := {
	"hage": true,
	"ngrass": true,
	"nsand": true,
	"nsandp": true,
}
const EXPECTED_UNIQUE_VARIANTS := 8
const EXPECTED_PILOT_INSTANCES := 9
const EXPECTED_SURFACE_OVERRIDES := 22

var _output_path := DEFAULT_OUTPUT_PATH
var _lm_suffix_regex := RegEx.new()
var _legacy_shadow_regex := RegEx.new()


func _initialize() -> void:
	_lm_suffix_regex.compile("_lm[0-9]+$")
	_legacy_shadow_regex.compile("(^|_)(h_kage|kage[0-9]*|tshadow|shadowchip)($|_)")
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output-profile="):
			_output_path = argument.trim_prefix("--output-profile=")
	call_deferred("_run")


func _run() -> void:
	var manifest := _load_json(MANIFEST_PATH)
	var catalog := _load_json(CATALOG_PATH)
	if manifest.is_empty() or catalog.is_empty():
		return
	var cell := _find_target_cell(manifest)
	if cell.is_empty():
		_fail("P3 seed cell is absent from the manifest.")
		return
	var glb_by_asset := _build_asset_glb_lookup(manifest)
	var catalog_by_glb := _build_catalog_lookup(catalog)
	var profile_assets: Dictionary = {}

	var terrain_key := String(cell.get("terrain_asset_key", ""))
	var terrain_profile := _build_asset_profile(
		terrain_key,
		glb_by_asset,
		catalog_by_glb,
		true
	)
	if terrain_profile.is_empty():
		return
	profile_assets[terrain_key] = terrain_profile

	for building_value: Variant in cell.get("buildings", []):
		var building := building_value as Dictionary
		var asset_key := String(building.get("asset_key", ""))
		if profile_assets.has(asset_key):
			continue
		var building_profile := _build_asset_profile(
			asset_key,
			glb_by_asset,
			catalog_by_glb,
			false
		)
		if building_profile.is_empty():
			return
		profile_assets[asset_key] = building_profile

	var unique_variants: Dictionary = {}
	for asset_profile_value: Variant in profile_assets.values():
		var asset_profile := asset_profile_value as Dictionary
		var variants: Dictionary = asset_profile.get("material_variants", {})
		for material_key_value: Variant in variants.keys():
			unique_variants[String(material_key_value)] = true
	if unique_variants.size() != EXPECTED_UNIQUE_VARIANTS:
		_fail(
			"Unexpected P3 seed material count: expected=%d actual=%d"
			% [EXPECTED_UNIQUE_VARIANTS, unique_variants.size()]
		)
		return

	var building_values: Array = cell.get("buildings", [])
	var pilot_instances := 1 + building_values.size()
	if pilot_instances != EXPECTED_PILOT_INSTANCES:
		_fail(
			"Unexpected P3 seed instance count: expected=%d actual=%d"
			% [EXPECTED_PILOT_INSTANCES, pilot_instances]
		)
		return
	var surface_overrides := _count_selected_surfaces(
		terrain_key,
		terrain_profile,
		glb_by_asset,
		catalog_by_glb
	)
	if surface_overrides < 0:
		return
	for building_value: Variant in building_values:
		var building := building_value as Dictionary
		var asset_key := String(building.get("asset_key", ""))
		var selected_surface_count := _count_selected_surfaces(
			asset_key,
			profile_assets.get(asset_key, {}) as Dictionary,
			glb_by_asset,
			catalog_by_glb
		)
		if selected_surface_count < 0:
			return
		surface_overrides += selected_surface_count
	if surface_overrides != EXPECTED_SURFACE_OVERRIDES:
		_fail(
			"Unexpected P3 seed surface count: expected=%d actual=%d"
			% [EXPECTED_SURFACE_OVERRIDES, surface_overrides]
		)
		return

	var profile := {
		"schema_version": 1,
		"profile_id": "p3_city_03_27",
		"enabled": true,
		"cells": ["3,27"],
		"assets": profile_assets,
		"expectations": {
			"unique_variants": EXPECTED_UNIQUE_VARIANTS,
			"surface_overrides": surface_overrides,
			"pilot_instances": pilot_instances,
		},
	}
	var directory_error := DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(_output_path.get_base_dir())
	)
	if directory_error != OK:
		_fail("Could not create P3 seed profile directory (error %d)." % directory_error)
		return
	var output := FileAccess.open(_output_path, FileAccess.WRITE)
	if output == null:
		_fail("Could not open P3 seed profile for writing: %s" % _output_path)
		return
	output.store_string(JSON.stringify(profile, "  ", true, true) + "\n")
	output.close()
	print("HD2D_P3_SEED_PROFILE_OK ", JSON.stringify({
		"profile": _output_path,
		"assets": profile_assets.size(),
		"unique_variants": unique_variants.size(),
		"pilot_instances": pilot_instances,
		"surface_overrides": surface_overrides,
	}))
	call_deferred("_finish_success")


func _build_asset_profile(
	asset_key: String,
	glb_by_asset: Dictionary,
	catalog_by_glb: Dictionary,
	is_terrain: bool
) -> Dictionary:
	if not glb_by_asset.has(asset_key):
		_fail("P3 seed asset is absent from the manifest: %s" % asset_key)
		return {}
	var glb_path := String(glb_by_asset[asset_key])
	if not catalog_by_glb.has(glb_path):
		_fail("P3 seed asset is absent from the material catalog: %s" % asset_key)
		return {}
	var catalog_asset := catalog_by_glb[glb_path] as Dictionary
	var variants: Dictionary = {}
	for material_value: Variant in catalog_asset.get("materials", []):
		var material := material_value as Dictionary
		var normalized_name := _normalize_material_name(String(material.get("source_name", "")))
		var include := (
			TERRAIN_MATERIAL_NAMES.has(normalized_name)
			if is_terrain
			else not _is_legacy_shadow_name(normalized_name)
		)
		if include:
			variants[String(material.get("material_key", ""))] = "lit_vertex"
	if variants.is_empty():
		_fail("P3 seed asset has no selected materials: %s" % asset_key)
		return {}
	return {
		"shadow_policy": "legacy_only",
		"material_variants": variants,
	}


func _normalize_material_name(value: String) -> String:
	return _lm_suffix_regex.sub(value.to_lower(), "", true)


func _is_legacy_shadow_name(value: String) -> bool:
	return _legacy_shadow_regex.search(value) != null


func _count_selected_surfaces(
	asset_key: String,
	asset_profile: Dictionary,
	glb_by_asset: Dictionary,
	catalog_by_glb: Dictionary
) -> int:
	if asset_profile.is_empty() or typeof(asset_profile.get("material_variants")) != TYPE_DICTIONARY:
		_fail("P3 seed asset profile is invalid: %s" % asset_key)
		return -1
	if not glb_by_asset.has(asset_key):
		_fail("P3 seed asset is absent from the manifest: %s" % asset_key)
		return -1
	var glb_path := String(glb_by_asset[asset_key])
	if not catalog_by_glb.has(glb_path):
		_fail("P3 seed asset is absent from the material catalog: %s" % asset_key)
		return -1
	var catalog_asset := catalog_by_glb[glb_path] as Dictionary
	var material_keys_by_index: Dictionary = {}
	for material_value: Variant in catalog_asset.get("materials", []):
		var material := material_value as Dictionary
		var output_index := int(material.get("output_index", -1))
		var material_key := String(material.get("material_key", ""))
		if output_index < 0 or material_key.is_empty():
			_fail("P3 seed catalog material mapping is invalid: %s" % asset_key)
			return -1
		if (
			material_keys_by_index.has(output_index)
			and String(material_keys_by_index[output_index]) != material_key
		):
			_fail("P3 seed catalog material index is ambiguous: %s" % asset_key)
			return -1
		material_keys_by_index[output_index] = material_key

	var selected_materials: Dictionary = asset_profile.get("material_variants", {})
	var matched_materials: Dictionary = {}
	var glb := _load_glb_json(MATRIX_ROOT.path_join(glb_path))
	if glb.is_empty():
		return -1
	var surface_count := 0
	for mesh_value: Variant in glb.get("meshes", []):
		var mesh := mesh_value as Dictionary
		for primitive_value: Variant in mesh.get("primitives", []):
			var primitive := primitive_value as Dictionary
			if not primitive.has("material"):
				continue
			var material_index := int(primitive.get("material", -1))
			if not material_keys_by_index.has(material_index):
				_fail("P3 seed GLB primitive material is absent from the catalog: %s" % asset_key)
				return -1
			var material_key := String(material_keys_by_index[material_index])
			if selected_materials.has(material_key):
				surface_count += 1
				matched_materials[material_key] = true
	for material_key_value: Variant in selected_materials.keys():
		if not matched_materials.has(material_key_value):
			_fail(
				"P3 seed selected material has no GLB primitive: %s in %s"
				% [String(material_key_value), asset_key]
			)
			return -1
	return surface_count


func _load_glb_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_fail("Could not open GLB for P3 seed audit: %s" % path)
		return {}
	if file.get_length() < 12 or file.get_32() != GLB_MAGIC:
		_fail("Invalid GLB header during P3 seed audit: %s" % path)
		return {}
	var version := int(file.get_32())
	var total_length := int(file.get_32())
	if version != 2 or total_length < 12 or total_length > file.get_length():
		_fail("Invalid GLB size or version during P3 seed audit: %s" % path)
		return {}
	while file.get_position() + 8 <= total_length:
		var chunk_length := int(file.get_32())
		var chunk_type := int(file.get_32())
		if chunk_length < 0 or file.get_position() + chunk_length > total_length:
			_fail("Invalid GLB chunk during P3 seed audit: %s" % path)
			return {}
		var chunk_data := file.get_buffer(chunk_length)
		if chunk_type != GLB_JSON_CHUNK:
			continue
		var parsed: Variant = JSON.parse_string(chunk_data.get_string_from_utf8().strip_edges())
		if typeof(parsed) != TYPE_DICTIONARY:
			_fail("GLB JSON root is invalid during P3 seed audit: %s" % path)
			return {}
		var document := parsed as Dictionary
		if document.is_empty():
			_fail("GLB JSON root must not be empty during P3 seed audit: %s" % path)
			return {}
		return document
	_fail("GLB contains no JSON chunk during P3 seed audit: %s" % path)
	return {}


func _find_target_cell(manifest: Dictionary) -> Dictionary:
	for cell_value: Variant in manifest.get("cells", []):
		var cell := cell_value as Dictionary
		if Vector2i(int(cell.get("x", -1)), int(cell.get("y", -1))) == TARGET_CELL:
			return cell
	return {}


func _build_asset_glb_lookup(manifest: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	var assets: Dictionary = manifest.get("assets", {})
	for group_name in ["terrain", "buildings"]:
		for asset_value: Variant in assets.get(group_name, []):
			var asset := asset_value as Dictionary
			var output_glbs: Array = asset.get("output_glbs", [])
			if output_glbs.is_empty():
				continue
			result[String(asset.get("key", ""))] = String(output_glbs[0]).replace("\\", "/")
	return result


func _build_catalog_lookup(catalog: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for asset_value: Variant in catalog.get("assets", []):
		var asset := asset_value as Dictionary
		result[String(asset.get("glb", "")).replace("\\", "/")] = asset
	return result


func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		_fail("Required JSON file does not exist: %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		_fail("JSON root is not an object: %s" % path)
		return {}
	var document := parsed as Dictionary
	if document.is_empty():
		_fail("JSON root must not be empty: %s" % path)
		return {}
	return document


func _fail(message: String) -> void:
	push_error(message)
	quit(1)


func _finish_success() -> void:
	quit(0)
