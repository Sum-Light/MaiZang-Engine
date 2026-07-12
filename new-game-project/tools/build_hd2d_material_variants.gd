extends SceneTree

const MANIFEST_PATH := "res://assets/platinum/matrix_0000/manifest.json"
const CATALOG_PATH := "res://assets/platinum/matrix_0000/material_catalog.json"
const BASE_MATERIAL_ROOT := "res://assets/platinum/shared_materials"
const VARIANT_ROOT := "res://assets/platinum/hd2d/shared_variants"
const DEFAULT_PROFILE_PATH := "res://assets/platinum/hd2d/world_semantics.profile.json"
const SUPPORTED_VARIANTS := {
	"lit_vertex": true,
	"emissive_window": true,
}
const SUPPORTED_MATERIAL_POLICIES := {
	"water_pixel_static": true,
	"foliage_pixel_cutout": true,
	"legacy_shadow_keep": true,
	"manual_review": true,
}

var _profile_path := DEFAULT_PROFILE_PATH
var _saved_variants := 0
var _removed_stale_variants := 0
var _variant_paths: Dictionary = {}
var _preserved_materials: Dictionary = {}


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--profile="):
			_profile_path = argument.trim_prefix("--profile=")
	call_deferred("_run")


func _run() -> void:
	var manifest := _load_json(MANIFEST_PATH)
	var catalog := _load_json(CATALOG_PATH)
	var profile := _load_json(_profile_path)
	if manifest.is_empty() or catalog.is_empty() or profile.is_empty():
		_fail("Required HD2D input JSON must not be empty.")
		return
	if int(profile.get("schema_version", 0)) != 1:
		_fail("Unsupported HD2D material profile schema.")
		return
	if not bool(profile.get("enabled", false)):
		_fail("HD2D material profile is disabled: %s" % _profile_path)
		return
	if typeof(profile.get("cells")) != TYPE_ARRAY or (profile.get("cells") as Array).is_empty():
		_fail("HD2D material profile cells must be a non-empty array.")
		return
	if typeof(profile.get("assets")) != TYPE_DICTIONARY:
		_fail("HD2D material profile assets must be an object.")
		return

	var asset_glbs := _build_asset_glb_lookup(manifest)
	var catalog_materials := _build_catalog_material_lookup(catalog)
	var pilot_assets := _build_pilot_asset_set(manifest, profile.get("cells", []))
	if pilot_assets.is_empty():
		_fail("HD2D profile has no valid pilot cells.")
		return

	var profile_assets: Dictionary = profile.get("assets", {})
	for asset_key_value: Variant in profile_assets.keys():
		var asset_key := String(asset_key_value)
		if not pilot_assets.has(asset_key):
			_fail("Profile asset is not present in a pilot cell: %s" % asset_key)
			return
		if not asset_glbs.has(asset_key):
			_fail("Profile asset is absent from the manifest: %s" % asset_key)
			return
		var glb_path := String(asset_glbs[asset_key])
		if not catalog_materials.has(glb_path):
			_fail("Profile asset is absent from the material catalog: %s" % asset_key)
			return
		var owned_materials := catalog_materials[glb_path] as Dictionary
		if typeof(profile_assets[asset_key_value]) != TYPE_DICTIONARY:
			_fail("Profile asset definition is not an object: %s" % asset_key)
			return
		var asset_profile := profile_assets[asset_key_value] as Dictionary
		if typeof(asset_profile.get("material_variants")) != TYPE_DICTIONARY:
			_fail("Profile material variants are not an object: %s" % asset_key)
			return
		var material_variants: Dictionary = asset_profile.get("material_variants", {})
		if typeof(asset_profile.get("material_policies", {})) != TYPE_DICTIONARY:
			_fail("Profile material policies are not an object: %s" % asset_key)
			return
		var material_policies: Dictionary = asset_profile.get("material_policies", {})
		var shadow_policy := String(asset_profile.get("shadow_policy", "inherit"))
		if shadow_policy not in ["inherit", "legacy_only"]:
			_fail("Unsupported HD2D shadow policy: %s" % shadow_policy)
			return
		if material_variants.is_empty() and material_policies.is_empty() and shadow_policy == "inherit":
			_fail("Profile asset has no semantic effect: %s" % asset_key)
			return
		for material_key_value: Variant in material_variants.keys():
			var material_key := String(material_key_value)
			var variant_tag := String(material_variants[material_key_value])
			if not owned_materials.has(material_key):
				_fail("Material %s does not belong to asset %s." % [material_key, asset_key])
				return
			if not SUPPORTED_VARIANTS.has(variant_tag):
				_fail("Unsupported HD2D material variant: %s" % variant_tag)
				return
			if not _build_variant(material_key, variant_tag):
				return
		for material_key_value: Variant in material_policies.keys():
			var material_key := String(material_key_value)
			var material_policy := String(material_policies[material_key_value])
			if not owned_materials.has(material_key):
				_fail("Policy material %s does not belong to asset %s." % [material_key, asset_key])
				return
			if material_variants.has(material_key):
				_fail("Material has both a variant and preserve policy: %s" % material_key)
				return
			if not SUPPORTED_MATERIAL_POLICIES.has(material_policy):
				_fail("Unsupported HD2D material policy: %s" % material_policy)
				return
			_preserved_materials["%s:%s" % [material_policy, material_key]] = true

	if not _prune_stale_variants():
		return
	var expectations: Dictionary = profile.get("expectations", {})
	var expected_variants := int(expectations.get("unique_variants", _variant_paths.size()))
	if _variant_paths.size() != expected_variants:
		_fail(
			"Unexpected HD2D variant count: expected=%d actual=%d"
			% [expected_variants, _variant_paths.size()]
		)
		return

	print("HD2D_MATERIAL_BUILD_OK ", JSON.stringify({
		"profile": String(profile.get("profile_id", "")),
		"profile_assets": profile_assets.size(),
		"saved_variants": _saved_variants,
		"removed_stale_variants": _removed_stale_variants,
		"unique_variants": _variant_paths.size(),
		"preserved_materials": _preserved_materials.size(),
	}))
	call_deferred("_finish_success")


func _build_variant(material_key: String, variant_tag: String) -> bool:
	var cache_key := "%s:%s" % [variant_tag, material_key]
	if _variant_paths.has(cache_key):
		return true
	var base_path := BASE_MATERIAL_ROOT.path_join("%s.tres" % material_key)
	var base_material := ResourceLoader.load(
		base_path,
		"StandardMaterial3D",
		ResourceLoader.CACHE_MODE_REUSE
	) as StandardMaterial3D
	if base_material == null:
		_fail("Could not load base HD2D material: %s" % base_path)
		return false
	if base_material.shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED:
		_fail("Base material is not unshaded: %s" % material_key)
		return false

	var variant := base_material.duplicate(false) as StandardMaterial3D
	if variant == null:
		_fail("Could not duplicate base HD2D material: %s" % material_key)
		return false
	variant.resource_name = "hd2d_%s_%s" % [variant_tag, material_key]
	variant.resource_local_to_scene = false
	_configure_variant(variant, base_material, variant_tag)
	variant.set_meta("hd2d_variant_tag", variant_tag)
	variant.set_meta("hd2d_base_material_key", material_key)

	var variant_directory := VARIANT_ROOT.path_join(variant_tag)
	var directory_error := DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(variant_directory)
	)
	if directory_error != OK:
		_fail("Could not create HD2D variant directory (error %d)." % directory_error)
		return false
	var variant_path := variant_directory.path_join("%s.tres" % material_key)
	var save_error := ResourceSaver.save(variant, variant_path)
	if save_error != OK:
		_fail("Could not save HD2D material %s (error %d)." % [variant_path, save_error])
		return false
	_variant_paths[cache_key] = variant_path
	_saved_variants += 1
	return true


func _configure_variant(
	variant: StandardMaterial3D,
	base_material: StandardMaterial3D,
	variant_tag: String
) -> void:
	variant.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	variant.metallic = 0.0
	variant.roughness = 1.0
	if variant_tag == "emissive_window":
		variant.metallic_specular = 0.0
		variant.emission_enabled = true
		variant.emission = Color(1.0, 0.84, 0.62, 1.0)
		variant.emission_texture = base_material.albedo_texture
		variant.emission_energy_multiplier = 0.25
		variant.emission_operator = BaseMaterial3D.EMISSION_OP_ADD


func _prune_stale_variants() -> bool:
	var retained_paths: Dictionary = {}
	for path_value: Variant in _variant_paths.values():
		retained_paths[String(path_value)] = true
	return _prune_stale_variants_in_directory(VARIANT_ROOT, retained_paths)


func _prune_stale_variants_in_directory(
	directory_path: String,
	retained_paths: Dictionary
) -> bool:
	var directory := DirAccess.open(directory_path)
	if directory == null:
		return true
	directory.list_dir_begin()
	var filename := directory.get_next()
	while not filename.is_empty():
		var resource_path := directory_path.path_join(filename)
		if directory.current_is_dir():
			if not _prune_stale_variants_in_directory(resource_path, retained_paths):
				directory.list_dir_end()
				return false
		elif filename.ends_with(".tres") and not retained_paths.has(resource_path):
			var remove_error := DirAccess.remove_absolute(
				ProjectSettings.globalize_path(resource_path)
			)
			if remove_error != OK:
				_fail("Could not remove stale HD2D variant: %s" % resource_path)
				directory.list_dir_end()
				return false
			_removed_stale_variants += 1
		filename = directory.get_next()
	directory.list_dir_end()
	return true


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


func _build_catalog_material_lookup(catalog: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for asset_value: Variant in catalog.get("assets", []):
		var asset := asset_value as Dictionary
		var materials: Dictionary = {}
		for material_value: Variant in asset.get("materials", []):
			var material := material_value as Dictionary
			materials[String(material.get("material_key", ""))] = true
		result[String(asset.get("glb", "")).replace("\\", "/")] = materials
	return result


func _build_pilot_asset_set(manifest: Dictionary, cell_values: Variant) -> Dictionary:
	if typeof(cell_values) != TYPE_ARRAY:
		_fail("HD2D pilot cells are not an array.")
		return {}
	var requested_cells: Dictionary = {}
	var cells := cell_values as Array
	for cell_value: Variant in cells:
		requested_cells[String(cell_value)] = true
	var matched_cells: Dictionary = {}
	var result: Dictionary = {}
	for cell_value: Variant in manifest.get("cells", []):
		var cell := cell_value as Dictionary
		var cell_key := "%d,%d" % [int(cell.get("x", -1)), int(cell.get("y", -1))]
		if not requested_cells.has(cell_key):
			continue
		matched_cells[cell_key] = true
		result[String(cell.get("terrain_asset_key", ""))] = true
		for building_value: Variant in cell.get("buildings", []):
			var building := building_value as Dictionary
			result[String(building.get("asset_key", ""))] = true
	for requested_cell_value: Variant in requested_cells.keys():
		if not matched_cells.has(requested_cell_value):
			_fail("HD2D pilot cell is absent from the manifest: %s" % requested_cell_value)
			return {}
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
		_fail("JSON object is empty: %s" % path)
		return {}
	return document


func _fail(message: String) -> void:
	push_error(message)
	quit(1)


func _finish_success() -> void:
	quit(0)
