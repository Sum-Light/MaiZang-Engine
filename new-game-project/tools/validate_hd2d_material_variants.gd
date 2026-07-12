extends SceneTree

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
const EXPECTED_PROFILE_CELLS := 468
const EXPECTED_PROFILE_ASSETS := 311
const EXPECTED_VARIANTS := 22
const EXPECTED_PRESERVED_MATERIALS := 63
const EXPECTED_SEMANTIC_MATERIALS := {
	"ambiguous": 1,
	"emissive": 16,
	"foliage": 23,
	"legacy_shadow": 7,
	"ordinary_lit": 432,
	"water": 32,
}
const EXPECTED_SEMANTIC_SURFACES := {
	"ambiguous": 21,
	"emissive": 124,
	"foliage": 469,
	"legacy_shadow": 278,
	"ordinary_lit": 2070,
	"water": 287,
}

var _profile_path := DEFAULT_PROFILE_PATH
var _expected_variant_paths: Dictionary = {}


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--profile="):
			_profile_path = argument.trim_prefix("--profile=")
	call_deferred("_run")


func _run() -> void:
	var profile := _load_json(_profile_path)
	if profile.is_empty():
		_fail("HD2D material profile must not be empty.")
		return
	if int(profile.get("schema_version", 0)) != 1 or not bool(profile.get("enabled", false)):
		_fail("HD2D material profile is disabled or uses an unsupported schema.")
		return
	if typeof(profile.get("assets")) != TYPE_DICTIONARY:
		_fail("HD2D material profile assets must be an object.")
		return
	var unique_variants: Dictionary = {}
	var preserved_materials: Dictionary = {}
	var profile_assets: Dictionary = profile.get("assets", {})
	if profile_assets.size() != EXPECTED_PROFILE_ASSETS:
		_fail("Unexpected HD2D semantic profile asset count: %d" % profile_assets.size())
		return
	if typeof(profile.get("cells")) != TYPE_ARRAY:
		_fail("HD2D semantic profile cells are not an array.")
		return
	if (profile.get("cells") as Array).size() != EXPECTED_PROFILE_CELLS:
		_fail("Unexpected HD2D semantic profile cell count.")
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
		if typeof(asset_profile.get("material_policies", {})) != TYPE_DICTIONARY:
			_fail("HD2D material policies are not an object.")
			return
		var material_policies: Dictionary = asset_profile.get("material_policies", {})
		var shadow_policy := String(asset_profile.get("shadow_policy", "inherit"))
		if shadow_policy not in ["inherit", "legacy_only"]:
			_fail("Unsupported HD2D shadow policy: %s" % shadow_policy)
			return
		if material_variants.is_empty() and material_policies.is_empty() and shadow_policy == "inherit":
			_fail("HD2D asset profile has no semantic effect.")
			return
		for material_key_value: Variant in material_variants.keys():
			var material_key := String(material_key_value)
			var variant_tag := String(material_variants[material_key_value])
			if not SUPPORTED_VARIANTS.has(variant_tag):
				_fail("Unsupported HD2D material variant: %s" % variant_tag)
				return
			var cache_key := "%s:%s" % [variant_tag, material_key]
			if unique_variants.has(cache_key):
				continue
			if not _validate_variant(material_key, variant_tag):
				return
			unique_variants[cache_key] = true
			_expected_variant_paths[
				VARIANT_ROOT.path_join(variant_tag).path_join("%s.tres" % material_key)
			] = true
		for material_key_value: Variant in material_policies.keys():
			var material_key := String(material_key_value)
			var material_policy := String(material_policies[material_key_value])
			if material_variants.has(material_key):
				_fail("Material has both a variant and preserve policy: %s" % material_key)
				return
			if not SUPPORTED_MATERIAL_POLICIES.has(material_policy):
				_fail("Unsupported HD2D material policy: %s" % material_policy)
				return
			preserved_materials["%s:%s" % [material_policy, material_key]] = true

	var expectations: Dictionary = profile.get("expectations", {})
	if (
		not _counts_match(
			expectations.get("semantic_materials", {}) as Dictionary,
			EXPECTED_SEMANTIC_MATERIALS
		)
		or not _counts_match(
			expectations.get("semantic_surface_references", {}) as Dictionary,
			EXPECTED_SEMANTIC_SURFACES
		)
	):
		_fail("HD2D semantic classification counts changed unexpectedly.")
		return
	var expected_variants := int(expectations.get("unique_variants", unique_variants.size()))
	if unique_variants.size() != expected_variants or expected_variants != EXPECTED_VARIANTS:
		_fail("Unexpected validated HD2D variant count: %d" % unique_variants.size())
		return
	if (
		preserved_materials.size() != EXPECTED_PRESERVED_MATERIALS
		or int(expectations.get("preserved_materials", 0)) != EXPECTED_PRESERVED_MATERIALS
	):
		_fail("Unexpected HD2D preserved-material count: %d" % preserved_materials.size())
		return
	if not _generated_variant_paths_match():
		_fail("HD2D variant directories contain stale resources.")
		return
	print("HD2D_MATERIAL_VALIDATION_OK ", JSON.stringify({
		"profile": String(profile.get("profile_id", "")),
		"unique_variants": unique_variants.size(),
		"preserved_materials": preserved_materials.size(),
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
	if not _variant_properties_are_valid(base, variant, variant_tag):
		_fail("HD2D semantic variant properties are incorrect: %s" % material_key)
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


func _variant_properties_are_valid(
	base: StandardMaterial3D,
	variant: StandardMaterial3D,
	variant_tag: String
) -> bool:
	if variant_tag == "lit_vertex":
		return variant.emission_enabled == base.emission_enabled
	if variant_tag == "emissive_window":
		return (
			variant.emission_enabled
			and variant.emission.is_equal_approx(Color(1.0, 0.84, 0.62, 1.0))
			and variant.emission_texture == base.albedo_texture
			and _texture_path(variant.emission_texture) == _texture_path(base.albedo_texture)
			and is_equal_approx(variant.emission_energy_multiplier, 0.25)
			and variant.emission_operator == BaseMaterial3D.EMISSION_OP_ADD
			and is_zero_approx(variant.metallic_specular)
		)
	return false


func _same_base_properties(base: StandardMaterial3D, variant: StandardMaterial3D) -> bool:
	return (
		base.albedo_color.is_equal_approx(variant.albedo_color)
		and _texture_path(base.albedo_texture) == _texture_path(variant.albedo_texture)
		and base.albedo_texture == variant.albedo_texture
		and base.transparency == variant.transparency
		and is_equal_approx(base.alpha_scissor_threshold, variant.alpha_scissor_threshold)
		and base.depth_draw_mode == variant.depth_draw_mode
		and base.alpha_antialiasing_mode == variant.alpha_antialiasing_mode
		and base.vertex_color_use_as_albedo == variant.vertex_color_use_as_albedo
		and base.texture_filter == variant.texture_filter
		and base.texture_repeat == variant.texture_repeat
		and base.cull_mode == variant.cull_mode
		and base.uv1_scale.is_equal_approx(variant.uv1_scale)
		and base.uv1_offset.is_equal_approx(variant.uv1_offset)
		and base.uv2_scale.is_equal_approx(variant.uv2_scale)
		and base.uv2_offset.is_equal_approx(variant.uv2_offset)
	)


func _texture_path(texture: Texture2D) -> String:
	return texture.resource_path if texture != null else ""


func _counts_match(actual: Dictionary, expected: Dictionary) -> bool:
	if actual.size() != expected.size():
		return false
	for key: Variant in expected.keys():
		if int(actual.get(key, -1)) != int(expected[key]):
			return false
	return true


func _generated_variant_paths_match() -> bool:
	var generated_paths: Dictionary = {}
	_collect_generated_variant_paths(VARIANT_ROOT, generated_paths)
	return generated_paths == _expected_variant_paths


func _collect_generated_variant_paths(directory_path: String, result: Dictionary) -> void:
	var directory := DirAccess.open(directory_path)
	if directory == null:
		return
	directory.list_dir_begin()
	var filename := directory.get_next()
	while not filename.is_empty():
		var resource_path := directory_path.path_join(filename)
		if directory.current_is_dir():
			_collect_generated_variant_paths(resource_path, result)
		elif filename.ends_with(".tres"):
			result[resource_path] = true
		filename = directory.get_next()
	directory.list_dir_end()


func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		_fail("HD2D profile does not exist: %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		_fail("HD2D profile root is not an object: %s" % path)
		return {}
	var document := parsed as Dictionary
	if document.is_empty():
		_fail("HD2D profile object is empty: %s" % path)
		return {}
	return document


func _fail(message: String) -> void:
	push_error(message)
	quit(1)


func _finish_success() -> void:
	quit(0)
