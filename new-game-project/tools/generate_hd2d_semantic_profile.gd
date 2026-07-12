extends SceneTree

const MANIFEST_PATH := "res://assets/platinum/matrix_0000/manifest.json"
const CATALOG_PATH := "res://assets/platinum/matrix_0000/material_catalog.json"
const MATRIX_ROOT := "res://assets/platinum/matrix_0000"
const DEFAULT_RULES_PATH := "res://tools/hd2d_semantic_rules.json"
const DEFAULT_SEED_PROFILE_PATH := "res://assets/platinum/hd2d/p3_city.profile.json"
const DEFAULT_OUTPUT_PATH := "res://assets/platinum/hd2d/world_semantics.profile.json"
const GLB_MAGIC := 0x46546C67
const GLB_JSON_CHUNK := 0x4E4F534A
const EXPECTED_SURFACE_REFERENCES := 3249

var _rules_path := DEFAULT_RULES_PATH
var _seed_profile_path := DEFAULT_SEED_PROFILE_PATH
var _output_path := DEFAULT_OUTPUT_PATH
var _lm_suffix_regex := RegEx.new()
var _non_alphanumeric_regex := RegEx.new()


func _initialize() -> void:
	_lm_suffix_regex.compile("_lm[0-9]+$")
	_non_alphanumeric_regex.compile("[^a-z0-9]+")
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--rules="):
			_rules_path = argument.trim_prefix("--rules=")
		elif argument.begins_with("--seed-profile="):
			_seed_profile_path = argument.trim_prefix("--seed-profile=")
		elif argument.begins_with("--output-profile="):
			_output_path = argument.trim_prefix("--output-profile=")
	call_deferred("_run")


func _run() -> void:
	var manifest := _load_required_json(MANIFEST_PATH)
	var catalog := _load_required_json(CATALOG_PATH)
	var rules_document := _load_required_json(_rules_path)
	if manifest.is_empty() or catalog.is_empty() or rules_document.is_empty():
		return
	if int(rules_document.get("schema_version", 0)) != 1:
		_fail("Unsupported HD2D semantic rule schema.")
		return
	var compiled_rules := _compile_rules(rules_document.get("rules"))
	if compiled_rules.is_empty():
		return
	var catalog_audit := _audit_catalog_assets(catalog)
	if catalog_audit.is_empty():
		return
	var material_rules := _classify_materials(
		catalog,
		compiled_rules,
		catalog_audit.get("aliases_by_material", {}) as Dictionary
	)
	if material_rules.is_empty():
		_fail("HD2D semantic classification produced no textured materials.")
		return

	var asset_keys_by_glb := _build_asset_key_lookup(manifest)
	var profile_assets := _build_profile_assets(catalog, asset_keys_by_glb, material_rules)
	if profile_assets.is_empty():
		_fail("HD2D semantic classification produced no profile assets.")
		return

	var seed_profile: Dictionary = {}
	if FileAccess.file_exists(_seed_profile_path):
		seed_profile = _load_required_json(_seed_profile_path)
		if seed_profile.is_empty():
			return
		if int(seed_profile.get("schema_version", 0)) != 1:
			_fail("Unsupported HD2D seed profile schema.")
			return
		if not _merge_seed_assets(
			profile_assets,
			seed_profile.get("assets", {}),
			material_rules
		):
			return
	else:
		push_warning("Optional HD2D seed profile was not found: %s" % _seed_profile_path)

	var profile_cells: Array[String] = []
	for cell_value: Variant in manifest.get("cells", []):
		var cell := cell_value as Dictionary
		profile_cells.append("%d,%d" % [int(cell.get("x", -1)), int(cell.get("y", -1))])
	profile_cells.sort()

	var unique_variants: Dictionary = {}
	var unique_material_policies: Dictionary = {}
	var semantic_materials: Dictionary = {}
	var semantic_surface_references: Dictionary = {}
	for material_key_value: Variant in material_rules.keys():
		var material_key := String(material_key_value)
		var rule := material_rules[material_key_value] as Dictionary
		var semantic := String(rule.get("semantic", ""))
		semantic_materials[semantic] = int(semantic_materials.get(semantic, 0)) + 1
	for material_key_value: Variant in catalog_audit.get("surface_material_keys", []):
		var material_key := String(material_key_value)
		var rule := material_rules[material_key] as Dictionary
		var semantic := String(rule.get("semantic", ""))
		semantic_surface_references[semantic] = int(
			semantic_surface_references.get(semantic, 0)
		) + 1
	for asset_profile_value: Variant in profile_assets.values():
		var asset_profile := asset_profile_value as Dictionary
		var material_variants: Dictionary = asset_profile.get("material_variants", {})
		for material_key_value: Variant in material_variants.keys():
			var variant_tag := String(material_variants[material_key_value])
			unique_variants["%s:%s" % [variant_tag, material_key_value]] = true
		var material_policies: Dictionary = asset_profile.get("material_policies", {})
		for material_key_value: Variant in material_policies.keys():
			var material_policy := String(material_policies[material_key_value])
			unique_material_policies["%s:%s" % [material_policy, material_key_value]] = true

	var profile := {
		"schema_version": 1,
		"profile_id": "world_semantics_v1",
		"enabled": true,
		"cells": profile_cells,
		"assets": profile_assets,
		"expectations": {
			"unique_variants": unique_variants.size(),
			"preserved_materials": unique_material_policies.size(),
			"profile_assets": profile_assets.size(),
			"profile_cells": profile_cells.size(),
			"semantic_materials": semantic_materials,
			"semantic_surface_references": semantic_surface_references,
		},
	}
	var output_directory := _output_path.get_base_dir()
	var directory_error := DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(output_directory)
	)
	if directory_error != OK:
		_fail("Could not create HD2D profile directory (error %d)." % directory_error)
		return
	var output := FileAccess.open(_output_path, FileAccess.WRITE)
	if output == null:
		_fail("Could not open HD2D semantic profile for writing: %s" % _output_path)
		return
	output.store_string(JSON.stringify(profile, "  ", true, true) + "\n")
	output.close()
	print("HD2D_SEMANTIC_PROFILE_OK ", JSON.stringify({
		"profile": _output_path,
		"cells": profile_cells.size(),
		"assets": profile_assets.size(),
		"unique_variants": unique_variants.size(),
		"preserved_materials": unique_material_policies.size(),
		"semantic_materials": semantic_materials,
		"semantic_surface_references": semantic_surface_references,
	}))
	call_deferred("_finish_success")


func _compile_rules(rules_value: Variant) -> Array[Dictionary]:
	var compiled: Array[Dictionary] = []
	if typeof(rules_value) != TYPE_ARRAY:
		_fail("HD2D semantic rules must be an array.")
		return compiled
	if (rules_value as Array).is_empty():
		_fail("HD2D semantic rules must not be empty.")
		return compiled
	for rule_value: Variant in rules_value as Array:
		if typeof(rule_value) != TYPE_DICTIONARY:
			_fail("HD2D semantic rule is not an object.")
			return []
		var rule := rule_value as Dictionary
		var semantic := String(rule.get("semantic", ""))
		var variant_tag := String(rule.get("variant_tag", ""))
		var material_policy := String(rule.get("material_policy", ""))
		var shadow_policy := String(rule.get("shadow_policy", "inherit"))
		var match_emissive_factor := bool(rule.get("match_emissive_factor", false))
		var match_image_aliases := bool(rule.get("match_image_aliases", true))
		if (
			semantic.is_empty()
			or (
				variant_tag.is_empty()
				and material_policy.is_empty()
				and shadow_policy == "inherit"
			)
		):
			_fail("HD2D semantic rule has no effect: %s" % semantic)
			return []
		if typeof(rule.get("patterns")) != TYPE_ARRAY:
			_fail("HD2D semantic rule patterns are not an array: %s" % semantic)
			return []
		var expressions: Array[RegEx] = []
		for pattern_value: Variant in rule.get("patterns", []):
			var expression := RegEx.new()
			var compile_error := expression.compile(String(pattern_value))
			if compile_error != OK:
				_fail("Invalid HD2D semantic regex for %s." % semantic)
				return []
			expressions.append(expression)
		var alpha_modes: Array[String] = []
		if typeof(rule.get("alpha_modes", [])) != TYPE_ARRAY:
			_fail("HD2D semantic alpha modes are not an array: %s" % semantic)
			return []
		for alpha_mode_value: Variant in rule.get("alpha_modes", []):
			alpha_modes.append(String(alpha_mode_value).to_upper())
		compiled.append({
			"semantic": semantic,
			"variant_tag": variant_tag,
			"material_policy": material_policy,
			"shadow_policy": shadow_policy,
			"expressions": expressions,
			"alpha_modes": alpha_modes,
			"match_emissive_factor": match_emissive_factor,
			"match_image_aliases": match_image_aliases,
		})
	return compiled


func _classify_materials(
	catalog: Dictionary,
	rules: Array[Dictionary],
	aliases_by_material: Dictionary
) -> Dictionary:
	var material_rules: Dictionary = {}
	if typeof(catalog.get("materials")) != TYPE_ARRAY:
		_fail("Material catalog has no global material records.")
		return {}
	for material_value: Variant in catalog.get("materials", []):
		var material := material_value as Dictionary
		var material_key := String(material.get("key", ""))
		var signature: Dictionary = material.get("signature", {})
		var material_aliases: Array[String] = []
		for alias_value: Variant in material.get("aliases", []):
			material_aliases.append(_normalize_alias(String(alias_value)))
		var image_aliases: Array[String] = []
		for alias_value: Variant in aliases_by_material.get(material_key, []):
			image_aliases.append(_normalize_alias(String(alias_value)))
		var matched_rules: Array[Dictionary] = []
		for rule: Dictionary in rules:
			if _rule_matches_material(rule, material_aliases, image_aliases, signature):
				matched_rules.append(rule)
		if matched_rules.size() > 1:
			material_rules[material_key] = {
				"semantic": "ambiguous",
				"variant_tag": "",
				"material_policy": "manual_review",
				"shadow_policy": "inherit",
			}
		elif matched_rules.size() == 1:
			material_rules[material_key] = matched_rules[0].duplicate(false)
		else:
			material_rules[material_key] = {
				"semantic": "ordinary_lit",
				"variant_tag": "",
				"material_policy": "",
				"shadow_policy": "inherit",
			}
	if material_rules.size() != (catalog.get("materials", []) as Array).size():
		_fail("HD2D semantic classification did not cover every unique material.")
		return {}
	return material_rules


func _audit_catalog_assets(catalog: Dictionary) -> Dictionary:
	var image_aliases_by_digest: Dictionary = {}
	for image_value: Variant in catalog.get("images", []):
		var image := image_value as Dictionary
		image_aliases_by_digest[String(image.get("key", "")).trim_prefix("img_")] = (
			image.get("aliases", [])
		)
	var aliases_by_material: Dictionary = {}
	var surface_material_keys: Array[String] = []
	for asset_value: Variant in catalog.get("assets", []):
		var asset := asset_value as Dictionary
		var glb_relative_path := String(asset.get("glb", "")).replace("\\", "/")
		var glb := _load_glb_json(MATRIX_ROOT.path_join(glb_relative_path))
		if glb.is_empty():
			return {}
		var glb_materials: Array = glb.get("materials", [])
		var glb_textures: Array = glb.get("textures", [])
		var glb_images: Array = glb.get("images", [])
		var material_keys_by_index: Dictionary = {}
		for material_record_value: Variant in asset.get("materials", []):
			var material_record := material_record_value as Dictionary
			var output_index := int(material_record.get("output_index", -1))
			var material_key := String(material_record.get("material_key", ""))
			if output_index < 0 or output_index >= glb_materials.size():
				_fail("Invalid GLB material index in catalog: %s" % glb_relative_path)
				return {}
			material_keys_by_index[output_index] = material_key
			var glb_material := glb_materials[output_index] as Dictionary
			var pbr: Dictionary = glb_material.get("pbrMetallicRoughness", {})
			_append_texture_aliases(
				material_key,
				pbr.get("baseColorTexture", {}),
				glb_textures,
				glb_images,
				image_aliases_by_digest,
				aliases_by_material
			)
			_append_texture_aliases(
				material_key,
				glb_material.get("emissiveTexture", {}),
				glb_textures,
				glb_images,
				image_aliases_by_digest,
				aliases_by_material
			)
		for mesh_value: Variant in glb.get("meshes", []):
			var mesh := mesh_value as Dictionary
			for primitive_value: Variant in mesh.get("primitives", []):
				var primitive := primitive_value as Dictionary
				if not primitive.has("material"):
					continue
				var material_index := int(primitive.get("material", -1))
				if not material_keys_by_index.has(material_index):
					_fail("GLB primitive material is absent from catalog: %s" % glb_relative_path)
					return {}
				surface_material_keys.append(String(material_keys_by_index[material_index]))
	if surface_material_keys.size() != EXPECTED_SURFACE_REFERENCES:
		_fail(
			"Unexpected material-bearing GLB surface count: %d"
			% surface_material_keys.size()
		)
		return {}
	return {
		"aliases_by_material": aliases_by_material,
		"surface_material_keys": surface_material_keys,
	}


func _append_texture_aliases(
	material_key: String,
	texture_info_value: Variant,
	textures: Array,
	images: Array,
	image_aliases_by_digest: Dictionary,
	aliases_by_material: Dictionary
) -> void:
	if typeof(texture_info_value) != TYPE_DICTIONARY:
		return
	var texture_info := texture_info_value as Dictionary
	if not texture_info.has("index"):
		return
	var texture_index := int(texture_info.get("index", -1))
	if texture_index < 0 or texture_index >= textures.size():
		return
	var texture := textures[texture_index] as Dictionary
	var image_index := int(texture.get("source", -1))
	if image_index < 0 or image_index >= images.size():
		return
	var image := images[image_index] as Dictionary
	var digest := String(image.get("uri", "")).get_file().get_basename()
	var aliases: Array = aliases_by_material.get(material_key, [])
	for alias_value: Variant in image_aliases_by_digest.get(digest, []):
		if alias_value not in aliases:
			aliases.append(alias_value)
	aliases_by_material[material_key] = aliases


func _load_glb_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_fail("Could not open GLB for semantic audit: %s" % path)
		return {}
	if file.get_32() != GLB_MAGIC:
		_fail("Invalid GLB header during semantic audit: %s" % path)
		return {}
	file.get_32()
	var total_length := int(file.get_32())
	while file.get_position() + 8 <= total_length:
		var chunk_length := int(file.get_32())
		var chunk_type := int(file.get_32())
		var chunk_data := file.get_buffer(chunk_length)
		if chunk_type != GLB_JSON_CHUNK:
			continue
		var parsed: Variant = JSON.parse_string(chunk_data.get_string_from_utf8().strip_edges())
		if typeof(parsed) != TYPE_DICTIONARY:
			_fail("GLB JSON root is invalid during semantic audit: %s" % path)
			return {}
		var document := parsed as Dictionary
		if document.is_empty():
			_fail("GLB JSON root must not be empty during semantic audit: %s" % path)
			return {}
		return document
	_fail("GLB contains no JSON chunk during semantic audit: %s" % path)
	return {}


func _rule_matches_material(
	rule: Dictionary,
	material_aliases: Array[String],
	image_aliases: Array[String],
	signature: Dictionary
) -> bool:
	var alpha_modes: Array = rule.get("alpha_modes", [])
	if (
		not alpha_modes.is_empty()
		and String(signature.get("alpha_mode", "OPAQUE")).to_upper() not in alpha_modes
	):
		return false
	if bool(rule.get("match_emissive_factor", false)):
		for component_value: Variant in signature.get("emissive_factor", []):
			if not is_zero_approx(float(component_value)):
				return true
	var aliases: Array[String] = material_aliases.duplicate()
	if bool(rule.get("match_image_aliases", true)):
		aliases.append_array(image_aliases)
	var expressions: Array = rule.get("expressions", [])
	for alias: String in aliases:
		for expression_value: Variant in expressions:
			var expression := expression_value as RegEx
			if expression.search(alias) != null:
				return true
	return false


func _normalize_alias(value: String) -> String:
	var normalized := value.replace("\\", "/").get_file().get_basename().to_lower()
	normalized = _lm_suffix_regex.sub(normalized, "", true)
	normalized = _non_alphanumeric_regex.sub(normalized, "_", true)
	return normalized.trim_prefix("_").trim_suffix("_")


func _build_asset_key_lookup(manifest: Dictionary) -> Dictionary:
	var lookup: Dictionary = {}
	var assets: Dictionary = manifest.get("assets", {})
	for group_name in ["terrain", "buildings"]:
		for asset_value: Variant in assets.get(group_name, []):
			var asset := asset_value as Dictionary
			var output_glbs: Array = asset.get("output_glbs", [])
			if output_glbs.is_empty():
				continue
			lookup[String(output_glbs[0]).replace("\\", "/")] = String(asset.get("key", ""))
	return lookup


func _build_profile_assets(
	catalog: Dictionary,
	asset_keys_by_glb: Dictionary,
	material_rules: Dictionary
) -> Dictionary:
	var profile_assets: Dictionary = {}
	for catalog_asset_value: Variant in catalog.get("assets", []):
		var catalog_asset := catalog_asset_value as Dictionary
		var glb_path := String(catalog_asset.get("glb", "")).replace("\\", "/")
		if not asset_keys_by_glb.has(glb_path):
			_fail("Material catalog GLB is absent from the manifest: %s" % glb_path)
			return {}
		var material_variants: Dictionary = {}
		var material_policies: Dictionary = {}
		var shadow_policy := "inherit"
		for material_value: Variant in catalog_asset.get("materials", []):
			var material := material_value as Dictionary
			var material_key := String(material.get("material_key", ""))
			if not material_rules.has(material_key):
				continue
			var rule := material_rules[material_key] as Dictionary
			var variant_tag := String(rule.get("variant_tag", ""))
			if not variant_tag.is_empty():
				material_variants[material_key] = variant_tag
			var material_policy := String(rule.get("material_policy", ""))
			if not material_policy.is_empty():
				material_policies[material_key] = material_policy
			if String(rule.get("shadow_policy", "inherit")) != "inherit":
				shadow_policy = String(rule.get("shadow_policy"))
		if (
			material_variants.is_empty()
			and material_policies.is_empty()
			and shadow_policy == "inherit"
		):
			continue
		profile_assets[String(asset_keys_by_glb[glb_path])] = {
			"shadow_policy": shadow_policy,
			"material_variants": material_variants,
			"material_policies": material_policies,
		}
	return profile_assets


func _merge_seed_assets(
	profile_assets: Dictionary,
	seed_assets_value: Variant,
	material_rules: Dictionary
) -> bool:
	if typeof(seed_assets_value) != TYPE_DICTIONARY:
		_fail("HD2D seed profile assets are not an object.")
		return false
	var seed_assets := seed_assets_value as Dictionary
	if seed_assets.is_empty():
		_fail("HD2D seed profile assets must not be empty.")
		return false
	for asset_key_value: Variant in seed_assets.keys():
		var asset_key := String(asset_key_value)
		if typeof(seed_assets[asset_key_value]) != TYPE_DICTIONARY:
			_fail("HD2D seed asset is not an object: %s" % asset_key)
			return false
		var seed_asset := seed_assets[asset_key_value] as Dictionary
		if typeof(seed_asset.get("material_variants")) != TYPE_DICTIONARY:
			_fail("HD2D seed material variants are not an object: %s" % asset_key)
			return false
		if typeof(seed_asset.get("material_policies", {})) != TYPE_DICTIONARY:
			_fail("HD2D seed material policies are not an object: %s" % asset_key)
			return false
		var seed_policies: Dictionary = seed_asset.get("material_policies", {})
		if not seed_policies.is_empty():
			_fail("HD2D seed profiles cannot define preserve policies: %s" % asset_key)
			return false
		var seed_shadow_policy := String(seed_asset.get("shadow_policy", "inherit"))
		if seed_shadow_policy not in ["inherit", "legacy_only"]:
			_fail("Unsupported HD2D seed shadow policy: %s" % seed_shadow_policy)
			return false
		var target: Dictionary = profile_assets.get(asset_key, {
			"shadow_policy": "inherit",
			"material_variants": {},
			"material_policies": {},
		})
		var target_variants: Dictionary = target.get("material_variants", {})
		var target_policies: Dictionary = target.get("material_policies", {})
		var seed_variants: Dictionary = seed_asset.get("material_variants", {})
		for material_key_value: Variant in seed_variants.keys():
			var material_key := String(material_key_value)
			var seed_variant := String(seed_variants[material_key_value])
			if seed_variant != "lit_vertex":
				_fail(
					"HD2D seed can only request lit_vertex: %s in %s"
					% [material_key, asset_key]
				)
				return false
			if not material_rules.has(material_key):
				_fail("HD2D seed material is absent from semantic classification: %s" % material_key)
				return false
			var semantic_rule := material_rules[material_key] as Dictionary
			var semantic := String(semantic_rule.get("semantic", ""))
			if target_policies.has(material_key_value):
				_fail(
					"HD2D seed conflicts with preserved %s material: %s in %s"
					% [semantic, material_key, asset_key]
				)
				return false
			if target_variants.has(material_key_value):
				var semantic_variant := String(semantic_rule.get("variant_tag", ""))
				if (
					semantic_variant.is_empty()
					or String(target_variants[material_key_value]) != semantic_variant
				):
					_fail(
						"HD2D seed conflicts with semantic variant: %s in %s"
						% [material_key, asset_key]
					)
					return false
				# Semantic-owned variants, such as emissive windows, take precedence.
				continue
			if (
				semantic != "ordinary_lit"
				or not String(semantic_rule.get("variant_tag", "")).is_empty()
				or not String(semantic_rule.get("material_policy", "")).is_empty()
			):
				_fail(
					"HD2D seed can only add ordinary-lit materials: %s is %s"
					% [material_key, semantic]
				)
				return false
			target_variants[material_key_value] = seed_variant
		target["material_variants"] = target_variants
		target["material_policies"] = target_policies
		if (
			String(target.get("shadow_policy", "inherit")) == "inherit"
			and String(seed_asset.get("shadow_policy", "inherit")) != "inherit"
		):
			target["shadow_policy"] = seed_asset.get("shadow_policy")
		profile_assets[asset_key] = target
	return true


func _load_required_json(path: String) -> Dictionary:
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
