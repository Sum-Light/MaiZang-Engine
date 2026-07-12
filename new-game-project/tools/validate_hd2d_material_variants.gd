extends SceneTree

const BASE_MATERIAL_ROOT := "res://assets/platinum/shared_materials"
const VARIANT_ROOT := "res://assets/platinum/hd2d/shared_variants"
const DEFAULT_PROFILE_PATH := "res://assets/platinum/hd2d/p3_city.profile.json"
const SUPPORTED_VARIANT := "lit_vertex"

var _profile_path := DEFAULT_PROFILE_PATH


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--profile="):
			_profile_path = argument.trim_prefix("--profile=")
	call_deferred("_run")


func _run() -> void:
	var profile := _load_json(_profile_path)
	if profile.is_empty():
		return
	if int(profile.get("schema_version", 0)) != 1 or not bool(profile.get("enabled", false)):
		_fail("HD2D material profile is disabled or uses an unsupported schema.")
		return
	if typeof(profile.get("assets")) != TYPE_DICTIONARY:
		_fail("HD2D material profile assets must be an object.")
		return
	var unique_variants: Dictionary = {}
	var profile_assets: Dictionary = profile.get("assets", {})
	if profile_assets.is_empty():
		_fail("HD2D material profile has no assets.")
		return
	for asset_profile_value: Variant in profile_assets.values():
		if typeof(asset_profile_value) != TYPE_DICTIONARY:
			_fail("HD2D asset profile is not an object.")
			return
		var asset_profile := asset_profile_value as Dictionary
		if typeof(asset_profile.get("material_variants")) != TYPE_DICTIONARY:
			_fail("HD2D material variants are not an object.")
			return
		var material_variants: Dictionary = asset_profile.get("material_variants", {})
		if material_variants.is_empty():
			_fail("HD2D asset profile has no material variants.")
			return
		for material_key_value: Variant in material_variants.keys():
			var material_key := String(material_key_value)
			var variant_tag := String(material_variants[material_key_value])
			if variant_tag != SUPPORTED_VARIANT:
				_fail("Unsupported HD2D material variant: %s" % variant_tag)
				return
			var cache_key := "%s:%s" % [variant_tag, material_key]
			if unique_variants.has(cache_key):
				continue
			if not _validate_variant(material_key, variant_tag):
				return
			unique_variants[cache_key] = true

	var expectations: Dictionary = profile.get("expectations", {})
	var expected_variants := int(expectations.get("unique_variants", unique_variants.size()))
	if unique_variants.size() != expected_variants:
		_fail("Unexpected validated HD2D variant count: %d" % unique_variants.size())
		return
	print("HD2D_MATERIAL_VALIDATION_OK ", JSON.stringify({
		"profile": String(profile.get("profile_id", "")),
		"unique_variants": unique_variants.size(),
	}))
	call_deferred("_finish_success")


func _validate_variant(material_key: String, variant_tag: String) -> bool:
	var base_path := BASE_MATERIAL_ROOT.path_join("%s.tres" % material_key)
	var variant_path := VARIANT_ROOT.path_join(variant_tag).path_join("%s.tres" % material_key)
	var base := ResourceLoader.load(base_path, "StandardMaterial3D", ResourceLoader.CACHE_MODE_REUSE) as StandardMaterial3D
	var variant := ResourceLoader.load(variant_path, "StandardMaterial3D", ResourceLoader.CACHE_MODE_REUSE) as StandardMaterial3D
	if base == null or variant == null:
		_fail("Could not load HD2D material pair: %s" % material_key)
		return false
	if base.resource_path == variant.resource_path:
		_fail("HD2D variant replaced its base material: %s" % material_key)
		return false
	if variant.resource_path != variant_path:
		_fail("HD2D variant resource path is incorrect: %s" % material_key)
		return false
	if variant.resource_name != "hd2d_%s_%s" % [variant_tag, material_key]:
		_fail("HD2D variant resource name is incorrect: %s" % material_key)
		return false
	if variant.resource_local_to_scene:
		_fail("HD2D variant is local to scene: %s" % material_key)
		return false
	if base.shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED:
		_fail("HD2D base shading mode changed: %s" % material_key)
		return false
	if variant.shading_mode != BaseMaterial3D.SHADING_MODE_PER_VERTEX:
		_fail("HD2D variant is not per-vertex lit: %s" % material_key)
		return false
	if not is_zero_approx(variant.metallic) or not is_equal_approx(variant.roughness, 1.0):
		_fail("HD2D variant surface response is incorrect: %s" % material_key)
		return false
	if base.has_meta("hd2d_variant_tag") or base.has_meta("hd2d_base_material_key"):
		_fail("HD2D metadata leaked into a base material: %s" % material_key)
		return false
	if (
		variant.get_meta("hd2d_variant_tag", "") != variant_tag
		or variant.get_meta("hd2d_base_material_key", "") != material_key
	):
		_fail("HD2D variant metadata is incorrect: %s" % material_key)
		return false
	if not _same_base_properties(base, variant):
		_fail("HD2D variant changed protected base properties: %s" % material_key)
		return false
	return true


func _same_base_properties(base: StandardMaterial3D, variant: StandardMaterial3D) -> bool:
	return (
		base.albedo_color.is_equal_approx(variant.albedo_color)
		and _texture_path(base.albedo_texture) == _texture_path(variant.albedo_texture)
		and base.albedo_texture == variant.albedo_texture
		and base.transparency == variant.transparency
		and is_equal_approx(base.alpha_scissor_threshold, variant.alpha_scissor_threshold)
		and base.vertex_color_use_as_albedo == variant.vertex_color_use_as_albedo
		and base.texture_filter == variant.texture_filter
		and base.texture_repeat == variant.texture_repeat
		and base.cull_mode == variant.cull_mode
	)


func _texture_path(texture: Texture2D) -> String:
	return texture.resource_path if texture != null else ""


func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		_fail("HD2D profile does not exist: %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		_fail("HD2D profile root is not an object: %s" % path)
		return {}
	return parsed as Dictionary


func _fail(message: String) -> void:
	push_error(message)
	quit(1)


func _finish_success() -> void:
	quit(0)
