class_name PlatinumDebugDestinationRequest
extends RefCounted

const META_KEY := &"_maizang_pending_debug_destination"
const SCHEMA_VERSION := 1
const MAP_TILE_SIZE := 32


static func queue(tree: SceneTree, normalized_request: Dictionary) -> Dictionary:
	var root_result := _get_root(tree)
	if not bool(root_result.ok):
		return _error("request", String(root_result.error))
	var root := root_result.root as Window
	if root.has_meta(META_KEY):
		return _error("request", "A debug destination reload is already pending.")

	var request_result := _normalize_request(normalized_request)
	if not bool(request_result.ok):
		return request_result
	var request := request_result.request as Dictionary
	var token := StringName(
		"%d_%d" % [root.get_instance_id(), Time.get_ticks_usec()]
	)
	request["schema_version"] = SCHEMA_VERSION
	request["token"] = token
	root.set_meta(META_KEY, request.duplicate(true))
	return {
		"ok": true,
		"error": "",
		"field": "",
		"token": token,
		"request": request.duplicate(true),
	}


static func take(tree: SceneTree) -> Dictionary:
	var root_result := _get_root(tree)
	if not bool(root_result.ok):
		return _take_error(String(root_result.error))
	var root := root_result.root as Window
	if not root.has_meta(META_KEY):
		return {
			"ok": true,
			"error": "",
			"field": "",
			"pending": false,
			"token": &"",
			"request": {},
		}

	var pending_value: Variant = root.get_meta(META_KEY)
	root.remove_meta(META_KEY)
	if typeof(pending_value) != TYPE_DICTIONARY:
		return _take_error("The pending debug destination request is not an object.")
	var pending := pending_value as Dictionary
	if int(pending.get("schema_version", -1)) != SCHEMA_VERSION:
		return _take_error("The pending debug destination request has an unsupported schema.")
	var request_result := _normalize_request(pending)
	if not bool(request_result.ok):
		return {
			"ok": false,
			"error": String(request_result.error),
			"field": String(request_result.field),
			"pending": true,
			"token": StringName(pending.get("token", "")),
			"request": {},
		}
	return {
		"ok": true,
		"error": "",
		"field": "",
		"pending": true,
		"token": StringName(pending.get("token", "")),
		"request": (request_result.request as Dictionary).duplicate(true),
	}


static func cancel(tree: SceneTree, token: StringName) -> bool:
	var root_result := _get_root(tree)
	if not bool(root_result.ok):
		return false
	var root := root_result.root as Window
	if not root.has_meta(META_KEY):
		return false
	var pending_value: Variant = root.get_meta(META_KEY)
	if typeof(pending_value) != TYPE_DICTIONARY:
		return false
	var pending := pending_value as Dictionary
	if StringName(pending.get("token", "")) != token:
		return false
	root.remove_meta(META_KEY)
	return true


static func clear(tree: SceneTree, token: StringName) -> bool:
	return cancel(tree, token)


static func has_pending(tree: SceneTree) -> bool:
	var root_result := _get_root(tree)
	if not bool(root_result.ok):
		return false
	return (root_result.root as Window).has_meta(META_KEY)


static func _normalize_request(value: Dictionary) -> Dictionary:
	if value.has("ok") and not bool(value.get("ok", false)):
		return _error(
			String(value.get("field", "request")),
			String(value.get("error", "Debug destination validation failed."))
		)
	var matrix_value: Variant = value.get("matrix", null)
	if typeof(matrix_value) != TYPE_INT or int(matrix_value) < 0:
		return _error("matrix", "A normalized debug destination requires a valid matrix id.")
	var area_value: Variant = value.get("area", null)
	if typeof(area_value) != TYPE_INT or int(area_value) < -1:
		return _error("area", "A normalized debug destination requires a valid area id.")
	var cell_value: Variant = value.get("cell", null)
	if not cell_value is Vector2i:
		return _error("cell", "A normalized debug destination requires an occupied cell.")
	var tile_value: Variant = value.get("tile", null)
	if not tile_value is Vector2i:
		return _error("tile", "A normalized debug destination requires a map tile.")
	var tile := tile_value as Vector2i
	if tile.x < 0 or tile.x >= MAP_TILE_SIZE or tile.y < 0 or tile.y >= MAP_TILE_SIZE:
		return _error("tile", "A normalized debug destination requires a tile within 0..31.")
	return {
		"ok": true,
		"request": {
			"matrix": int(matrix_value),
			"area": int(area_value),
			"cell": cell_value as Vector2i,
			"has_cell": true,
			"tile": tile,
		},
	}


static func _get_root(tree: SceneTree) -> Dictionary:
	if tree == null or tree.root == null:
		return {"ok": false, "error": "SceneTree root is not available."}
	return {"ok": true, "root": tree.root}


static func _error(field_name: String, message: String) -> Dictionary:
	return {
		"ok": false,
		"error": message,
		"field": field_name,
		"token": &"",
		"request": {},
	}


static func _take_error(message: String) -> Dictionary:
	return {
		"ok": false,
		"error": message,
		"field": "request",
		"pending": true,
		"token": &"",
		"request": {},
	}
