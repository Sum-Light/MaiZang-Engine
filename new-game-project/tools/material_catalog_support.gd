extends RefCounted


static func collect_expectations(manifest_paths: Array[String]) -> Dictionary:
	var expected_materials: Dictionary = {}
	var asset_materials: Dictionary = {}
	var manifest_material_counts: Dictionary = {}
	for manifest_path: String in manifest_paths:
		var manifest_result := _load_json_object(manifest_path, "Manifest")
		if not bool(manifest_result.ok):
			return manifest_result
		var manifest := manifest_result.value as Dictionary
		var dedupe_value: Variant = manifest.get("material_dedupe", null)
		if typeof(dedupe_value) != TYPE_DICTIONARY:
			return _error("Manifest material_dedupe is not an object: %s" % manifest_path)
		var dedupe := dedupe_value as Dictionary
		var catalog_value: Variant = dedupe.get("catalog", null)
		if typeof(catalog_value) != TYPE_STRING or String(catalog_value).is_empty():
			return _error("Manifest has no material catalog path: %s" % manifest_path)
		var catalog_path := resolve_relative_path(manifest_path, String(catalog_value))
		var catalog_result := _load_json_object(catalog_path, "Material catalog")
		if not bool(catalog_result.ok):
			return catalog_result
		var catalog := catalog_result.value as Dictionary

		var materials_value: Variant = catalog.get("materials", null)
		if typeof(materials_value) != TYPE_ARRAY:
			return _error("Material catalog materials is not an array: %s" % catalog_path)
		var local_materials: Dictionary = {}
		for material_index in (materials_value as Array).size():
			var material_value: Variant = (materials_value as Array)[material_index]
			if typeof(material_value) != TYPE_DICTIONARY:
				return _error("Material catalog entry %d is not an object: %s" % [material_index, catalog_path])
			var material_entry := material_value as Dictionary
			var key_value: Variant = material_entry.get("key", null)
			if typeof(key_value) != TYPE_STRING or not String(key_value).begins_with("mat_"):
				return _error("Material catalog entry %d has an invalid key: %s" % [material_index, catalog_path])
			var material_name := "dspre_%s" % String(key_value)
			if local_materials.has(material_name):
				return _error("Material catalog repeats key %s: %s" % [material_name, catalog_path])
			var signature_value: Variant = material_entry.get("signature", null)
			if typeof(signature_value) != TYPE_DICTIONARY:
				return _error("Material catalog key %s has no signature: %s" % [material_name, catalog_path])
			var signature_json := JSON.stringify(signature_value)
			local_materials[material_name] = signature_json
			if expected_materials.has(material_name):
				var existing := expected_materials[material_name] as Dictionary
				if String(existing.signature) != signature_json:
					return _error("Material key has conflicting signatures across destinations: %s" % material_name)
			else:
				expected_materials[material_name] = {
					"signature": signature_json,
					"catalog_path": catalog_path,
				}

		var expected_local_count := int(dedupe.get("unique_materials", -1))
		var summary_value: Variant = catalog.get("summary", null)
		if typeof(summary_value) != TYPE_DICTIONARY:
			return _error("Material catalog summary is not an object: %s" % catalog_path)
		var summary_count := int((summary_value as Dictionary).get("unique_materials", -1))
		if expected_local_count < 0 or expected_local_count != local_materials.size() or summary_count != local_materials.size():
			return _error(
				"Material counts disagree for %s: manifest %d, catalog %d, entries %d"
				% [manifest_path, expected_local_count, summary_count, local_materials.size()]
			)
		manifest_material_counts[manifest_path] = local_materials.size()

		var assets_value: Variant = catalog.get("assets", null)
		if typeof(assets_value) != TYPE_ARRAY:
			return _error("Material catalog assets is not an array: %s" % catalog_path)
		for asset_index in (assets_value as Array).size():
			var asset_value: Variant = (assets_value as Array)[asset_index]
			if typeof(asset_value) != TYPE_DICTIONARY:
				return _error("Material catalog asset %d is not an object: %s" % [asset_index, catalog_path])
			var asset := asset_value as Dictionary
			var glb_value: Variant = asset.get("glb", null)
			if typeof(glb_value) != TYPE_STRING or String(glb_value).is_empty():
				return _error("Material catalog asset %d has no GLB path: %s" % [asset_index, catalog_path])
			var asset_path := resolve_relative_path(manifest_path, String(glb_value))
			if asset_materials.has(asset_path):
				return _error("Material catalogs list a GLB more than once: %s" % asset_path)
			var bindings_value: Variant = asset.get("materials", null)
			if typeof(bindings_value) != TYPE_ARRAY:
				return _error("Material catalog asset has no material bindings: %s" % asset_path)
			var names: Dictionary = {}
			for binding_value: Variant in bindings_value as Array:
				if typeof(binding_value) != TYPE_DICTIONARY:
					return _error("Material binding is not an object: %s" % asset_path)
				var material_key_value: Variant = (binding_value as Dictionary).get("material_key", null)
				if typeof(material_key_value) != TYPE_STRING:
					return _error("Material binding has no key: %s" % asset_path)
				var material_name := "dspre_%s" % String(material_key_value)
				if not local_materials.has(material_name):
					return _error("Asset references unknown material %s: %s" % [material_name, asset_path])
				names[material_name] = true
			var output_material_count := int(asset.get("output_material_count", -1))
			if output_material_count <= 0 or output_material_count != names.size():
				return _error(
					"Asset material count disagrees for %s: catalog %d, unique bindings %d"
					% [asset_path, output_material_count, names.size()]
				)
			asset_materials[asset_path] = names

	return {
		"ok": true,
		"expected_materials": expected_materials,
		"asset_materials": asset_materials,
		"manifest_material_counts": manifest_material_counts,
	}


static func collect_scene_materials(root: Node, reject_null_surfaces: bool = true) -> Dictionary:
	var materials: Dictionary = {}
	var surface_count := 0
	var stack: Array[Node] = [root]
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
			surface_count += 1
			var material := mesh.surface_get_material(surface_index)
			var mesh_label: String = (
				String(mesh_instance.get_path())
				if mesh_instance.is_inside_tree()
				else String(mesh_instance.name)
			)
			if material == null:
				if reject_null_surfaces:
					return _error(
						"Mesh surface has no material: %s surface %d"
						% [mesh_label, surface_index]
					)
				continue
			var material_name := material.resource_name
			if material_name.is_empty():
				return _error("Mesh surface material has no resource name: %s" % mesh_label)
			if materials.has(material_name):
				if not materials_equivalent(materials[material_name] as Material, material):
					return _error("One scene contains different materials with the same name: %s" % material_name)
			else:
				materials[material_name] = material
	return {
		"ok": true,
		"materials": materials,
		"surface_count": surface_count,
	}


static func load_raw_scene_materials(asset_path: String) -> Dictionary:
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var append_error := document.append_from_file(asset_path, state)
	if append_error != OK:
		return _error("Could not parse raw GLB %s (error %d)." % [asset_path, append_error])
	var scene := document.generate_scene(state)
	if scene == null:
		return _error("Could not generate a raw GLB scene: %s" % asset_path)
	var result := collect_scene_materials(scene, true)
	scene.free()
	return result


static func materials_equivalent(expected: Material, actual: Material) -> bool:
	if expected == null or actual == null or expected.get_class() != actual.get_class():
		return false
	var actual_properties: Dictionary = {}
	for property: Dictionary in actual.get_property_list():
		actual_properties[String(property.get("name", ""))] = int(property.get("usage", 0))
	for property: Dictionary in expected.get_property_list():
		var property_name := String(property.get("name", ""))
		if int(property.get("usage", 0)) & PROPERTY_USAGE_STORAGE == 0:
			continue
		if property_name.begins_with("resource_"):
			continue
		if not actual_properties.has(property_name):
			return false
		if not _values_equivalent(expected.get(property_name), actual.get(property_name)):
			return false
	return true


static func dictionaries_have_same_keys(left: Dictionary, right: Dictionary) -> bool:
	if left.size() != right.size():
		return false
	for key: Variant in left:
		if not right.has(key):
			return false
	return true


static func resolve_relative_path(base_file_path: String, relative_path: String) -> String:
	var normalized_path := relative_path.replace("\\", "/")
	if normalized_path.begins_with("res://"):
		return normalized_path.simplify_path()
	return base_file_path.get_base_dir().path_join(normalized_path).simplify_path()


static func _values_equivalent(expected: Variant, actual: Variant) -> bool:
	if typeof(expected) != typeof(actual):
		return false
	match typeof(expected):
		TYPE_FLOAT:
			return is_equal_approx(float(expected), float(actual))
		TYPE_VECTOR2:
			return (expected as Vector2).is_equal_approx(actual as Vector2)
		TYPE_VECTOR3:
			return (expected as Vector3).is_equal_approx(actual as Vector3)
		TYPE_VECTOR4:
			return (expected as Vector4).is_equal_approx(actual as Vector4)
		TYPE_COLOR:
			return (expected as Color).is_equal_approx(actual as Color)
		TYPE_OBJECT:
			if expected == null or actual == null:
				return expected == actual
			if expected is Texture2D or actual is Texture2D:
				if not expected is Texture2D or not actual is Texture2D:
					return false
				return _textures_equivalent(expected as Texture2D, actual as Texture2D)
			return expected == actual
		_:
			return expected == actual


static func _textures_equivalent(expected: Texture2D, actual: Texture2D) -> bool:
	var expected_image := expected.get_image()
	var actual_image := actual.get_image()
	if expected_image == null or actual_image == null:
		return expected_image == actual_image
	if expected_image.is_empty() or actual_image.is_empty():
		return expected_image.is_empty() and actual_image.is_empty()
	if expected_image.get_size() != actual_image.get_size():
		return false
	if expected_image.is_compressed() and expected_image.decompress() != OK:
		return false
	if actual_image.is_compressed() and actual_image.decompress() != OK:
		return false
	expected_image.convert(Image.FORMAT_RGBA8)
	actual_image.convert(Image.FORMAT_RGBA8)
	return expected_image.get_data() == actual_image.get_data()


static func _load_json_object(path: String, label: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _error("%s does not exist: %s" % [label, path])
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return _error("%s is not a JSON object: %s" % [label, path])
	return {"ok": true, "value": parsed as Dictionary}


static func _error(message: String) -> Dictionary:
	return {"ok": false, "error": message}
