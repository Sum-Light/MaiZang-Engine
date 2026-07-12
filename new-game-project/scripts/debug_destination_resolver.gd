class_name PlatinumDebugDestinationResolver
extends RefCounted

const USE_DESTINATION_DEFAULT_CELL := Vector2i(-1, -1)
const MAP_TILE_SIZE := 32


static func make_request(
	matrix_id: int,
	area_data_id: int = -1,
	matrix_cell: Vector2i = USE_DESTINATION_DEFAULT_CELL,
	map_tile: Vector2i = Vector2i.ZERO
) -> Dictionary:
	return {
		"matrix": matrix_id,
		"area": area_data_id,
		"cell": matrix_cell,
		"has_cell": matrix_cell != USE_DESTINATION_DEFAULT_CELL,
		"tile": map_tile,
	}


static func resolve(catalog_path: String, request: Dictionary) -> Dictionary:
	var result := _base_result(request)
	var matrix_value: Variant = request.get("matrix", null)
	if typeof(matrix_value) != TYPE_INT:
		return _error(result, "matrix", "Debug matrix id must be an integer.")
	var requested_matrix := int(matrix_value)
	result["matrix"] = requested_matrix
	if requested_matrix < 0:
		return _error(
			result,
			"matrix",
			"Debug matrix id must be zero or greater: %d" % requested_matrix
		)

	var area_value: Variant = request.get("area", -1)
	if typeof(area_value) != TYPE_INT:
		return _error(result, "area", "Debug area data id must be an integer.")
	var requested_area := int(area_value)
	result["area"] = requested_area
	if requested_area < -1:
		return _error(
			result,
			"area",
			"Debug area data id must be -1 or greater: %d" % requested_area
		)

	var tile_result := _vector2i(request.get("tile", Vector2i.ZERO), "tile")
	if not bool(tile_result.ok):
		return _error(result, "tile", String(tile_result.error))
	var map_tile := tile_result.value as Vector2i
	result["tile"] = map_tile
	if not _is_valid_map_tile(map_tile):
		return _error(
			result,
			"tile",
			"Debug map tile must be within 0..31 on both axes: %s" % map_tile
		)

	var has_explicit_cell := bool(request.get("has_cell", false))
	var explicit_cell := USE_DESTINATION_DEFAULT_CELL
	if has_explicit_cell:
		var cell_result := _vector2i(request.get("cell", null), "cell")
		if not bool(cell_result.ok):
			return _error(result, "cell", String(cell_result.error))
		explicit_cell = cell_result.value as Vector2i
		result["cell"] = explicit_cell

	var catalog_result := _load_json_object(catalog_path, "Matrix catalog")
	if not bool(catalog_result.ok):
		return _error(result, "catalog", String(catalog_result.error))
	var catalog := catalog_result.value as Dictionary
	var destinations_value: Variant = catalog.get("destinations", null)
	if typeof(destinations_value) != TYPE_ARRAY:
		return _error(
			result,
			"catalog",
			"Matrix catalog destinations are not an array: %s" % catalog_path
		)

	var matrix_destinations: Array[Dictionary] = []
	var matching_destinations: Array[Dictionary] = []
	var area_less_destinations: Array[Dictionary] = []
	for destination_value: Variant in destinations_value as Array:
		if typeof(destination_value) != TYPE_DICTIONARY:
			continue
		var destination := destination_value as Dictionary
		var destination_matrix_value: Variant = destination.get("matrix_id", null)
		if not _is_integer_number(destination_matrix_value):
			continue
		if int(destination_matrix_value) != requested_matrix:
			continue
		matrix_destinations.append(destination)
		var destination_area: Variant = destination.get("area_data_id", null)
		if destination_area == null:
			area_less_destinations.append(destination)
		elif not _is_integer_number(destination_area):
			return _error(
				result,
				"catalog",
				"Matrix %04d has a destination with an invalid area data id."
				% requested_matrix
			)
		elif requested_area >= 0 and int(destination_area) == requested_area:
			matching_destinations.append(destination)

	if matrix_destinations.is_empty():
		return _error(
			result,
			"matrix",
			"Matrix %04d has no ready destination in the matrix catalog."
			% requested_matrix
		)

	var selected: Dictionary
	if requested_area >= 0:
		if matching_destinations.size() != 1:
			return _error(
				result,
				"area",
				"Matrix %04d has no unique ready destination for area %04d."
				% [requested_matrix, requested_area]
			)
		selected = matching_destinations[0]
	elif area_less_destinations.size() == 1:
		selected = area_less_destinations[0]
	elif matrix_destinations.size() == 1:
		selected = matrix_destinations[0]
	else:
		var available_areas: Array[int] = []
		for destination: Dictionary in matrix_destinations:
			var destination_area: Variant = destination.get("area_data_id", null)
			if destination_area != null:
				available_areas.append(int(destination_area))
		available_areas.sort()
		return _error(
			result,
			"area",
			"Matrix %04d has multiple ready areas %s; specify an area."
			% [requested_matrix, available_areas]
		)

	var selected_matrix := int(selected.get("matrix_id", requested_matrix))
	var selected_area_value: Variant = selected.get("area_data_id", null)
	var selected_area := -1 if selected_area_value == null else int(selected_area_value)
	result["matrix"] = selected_matrix
	result["area"] = selected_area
	result["destination_key"] = String(selected.get("key", ""))

	var relative_manifest_value: Variant = selected.get("manifest", null)
	if typeof(relative_manifest_value) != TYPE_STRING or String(relative_manifest_value).is_empty():
		return _error(result, "manifest", "The selected matrix destination has no manifest path.")
	var relative_manifest := String(relative_manifest_value).replace("\\", "/")
	var resolved_manifest_path := relative_manifest.simplify_path()
	if not relative_manifest.begins_with("res://"):
		resolved_manifest_path = (
			catalog_path.get_base_dir().path_join(relative_manifest).simplify_path()
		)
	result["manifest_path"] = resolved_manifest_path

	var manifest_result := _load_json_object(resolved_manifest_path, "World manifest")
	if not bool(manifest_result.ok):
		return _error(result, "manifest", String(manifest_result.error))
	var manifest := manifest_result.value as Dictionary
	var manifest_matrix_value: Variant = manifest.get("matrix", null)
	if typeof(manifest_matrix_value) != TYPE_DICTIONARY:
		return _error(
			result,
			"manifest",
			"World manifest matrix is not an object: %s" % resolved_manifest_path
		)
	var manifest_matrix := manifest_matrix_value as Dictionary
	var manifest_id_value: Variant = manifest_matrix.get("id", null)
	if not _is_integer_number(manifest_id_value) or int(manifest_id_value) != selected_matrix:
		return _error(
			result,
			"manifest",
			"World manifest matrix id does not match the selected catalog destination."
		)
	var manifest_area_value: Variant = manifest_matrix.get("area_data_id", null)
	if selected_area >= 0:
		if not _is_integer_number(manifest_area_value) or int(manifest_area_value) != selected_area:
			return _error(
				result,
				"manifest",
				"World manifest area id does not match the selected catalog destination."
			)
	elif manifest_area_value != null:
		return _error(
			result,
			"manifest",
			"World manifest area id does not match the selected catalog destination."
		)

	var start_cell := explicit_cell
	if not has_explicit_cell:
		var default_cell_result := _dictionary_vector2i(selected.get("default_cell", null))
		if not bool(default_cell_result.ok):
			return _error(
				result,
				"cell",
				"The selected matrix destination has no valid default cell."
			)
		start_cell = default_cell_result.value as Vector2i
	result["cell"] = start_cell

	var cells_value: Variant = manifest.get("cells", null)
	if typeof(cells_value) != TYPE_ARRAY:
		return _error(
			result,
			"manifest",
			"World manifest cells are not an array: %s" % resolved_manifest_path
		)
	var matching_cell_count := 0
	for cell_value: Variant in cells_value as Array:
		if typeof(cell_value) != TYPE_DICTIONARY:
			return _error(
				result,
				"manifest",
				"World manifest contains a cell that is not an object: %s"
				% resolved_manifest_path
			)
		var cell_result := _dictionary_vector2i(cell_value)
		if not bool(cell_result.ok):
			return _error(
				result,
				"manifest",
				"World manifest contains a cell with invalid coordinates: %s"
				% resolved_manifest_path
			)
		if cell_result.value as Vector2i == start_cell:
			matching_cell_count += 1
	if matching_cell_count == 0:
		return _error(
			result,
			"cell",
			"Debug start cell %s is not occupied in matrix %04d area %d."
			% [start_cell, selected_matrix, selected_area]
		)
	if matching_cell_count > 1:
		return _error(
			result,
			"manifest",
			"World manifest repeats occupied cell %s: %s"
			% [start_cell, resolved_manifest_path]
		)

	result["ok"] = true
	result["has_cell"] = true
	result["uses_default_cell"] = not has_explicit_cell
	return result


static func _base_result(_request: Dictionary) -> Dictionary:
	return {
		"ok": false,
		"error": "",
		"field": "",
		"matrix": -1,
		"area": -1,
		"cell": USE_DESTINATION_DEFAULT_CELL,
		"tile": Vector2i.ZERO,
		"has_cell": false,
		"uses_default_cell": false,
		"manifest_path": "",
		"destination_key": "",
	}


static func _load_json_object(path: String, label: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "%s does not exist: %s" % [label, path]}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"ok": false, "error": "%s is not a JSON object: %s" % [label, path]}
	return {"ok": true, "value": parsed as Dictionary}


static func _vector2i(value: Variant, field_name: String) -> Dictionary:
	if value is Vector2i:
		return {"ok": true, "value": value as Vector2i}
	if value is Vector2:
		return {"ok": true, "value": Vector2i(value as Vector2)}
	return {
		"ok": false,
		"error": "Debug %s must be a Vector2i." % field_name,
	}


static func _dictionary_vector2i(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {"ok": false}
	var data := value as Dictionary
	var x_value: Variant = data.get("x", null)
	var y_value: Variant = data.get("y", null)
	if not _is_integer_number(x_value) or not _is_integer_number(y_value):
		return {"ok": false}
	return {"ok": true, "value": Vector2i(int(x_value), int(y_value))}


static func _is_integer_number(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	if typeof(value) != TYPE_FLOAT:
		return false
	var number := float(value)
	return is_finite(number) and number == floorf(number)


static func _is_valid_map_tile(tile: Vector2i) -> bool:
	return (
		tile.x >= 0
		and tile.x < MAP_TILE_SIZE
		and tile.y >= 0
		and tile.y < MAP_TILE_SIZE
	)


static func _error(result: Dictionary, field_name: String, message: String) -> Dictionary:
	result["ok"] = false
	result["error"] = message
	result["field"] = field_name
	return result
