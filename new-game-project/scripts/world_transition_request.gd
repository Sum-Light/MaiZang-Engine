class_name PlatinumWorldTransitionRequest
extends RefCounted

const META_KEY := &"_maizang_pending_world_transition"
const SCHEMA_VERSION := 1
const MAP_TILE_SIZE := 32
const MAX_U16 := 0xFFFF


static func queue(tree: SceneTree, normalized_request: Dictionary) -> Dictionary:
	var root_result := _get_root(tree)
	if not bool(root_result.ok):
		return _error("request", String(root_result.error))
	var root := root_result.root as Window
	if root.has_meta(META_KEY):
		return _error("request", "A world transition is already pending.")
	var normalized := normalize(normalized_request)
	if not bool(normalized.ok):
		return normalized
	var request := (normalized.request as Dictionary).duplicate(true)
	var token := StringName("%d_%d" % [root.get_instance_id(), Time.get_ticks_usec()])
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
		return _empty_take()
	var pending_value: Variant = root.get_meta(META_KEY)
	root.remove_meta(META_KEY)
	if typeof(pending_value) != TYPE_DICTIONARY:
		return _take_error("The pending world transition is not an object.")
	var pending := pending_value as Dictionary
	if typeof(pending.get("schema_version", null)) != TYPE_INT:
		return _take_error("The pending world transition has no valid schema.")
	if int(pending.schema_version) != SCHEMA_VERSION:
		return _take_error("The pending world transition has an unsupported schema.")
	var token_value: Variant = pending.get("token", null)
	if typeof(token_value) != TYPE_STRING_NAME:
		return _take_error("The pending world transition has no valid token.")
	var token := StringName(token_value)
	if token == StringName():
		return _take_error("The pending world transition has no valid token.")
	var normalized := normalize(pending)
	if not bool(normalized.ok):
		return {
			"ok": false,
			"error": String(normalized.error),
			"field": String(normalized.field),
			"pending": true,
			"token": token,
			"request": {},
		}
	return {
		"ok": true,
		"error": "",
		"field": "",
		"pending": true,
		"token": token,
		"request": (normalized.request as Dictionary).duplicate(true),
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
	var pending_token_value: Variant = (pending_value as Dictionary).get("token", null)
	if typeof(pending_token_value) != TYPE_STRING_NAME:
		return false
	if StringName(pending_token_value) != token:
		return false
	root.remove_meta(META_KEY)
	return true


static func clear(tree: SceneTree, token: StringName) -> bool:
	return cancel(tree, token)


static func has_pending(tree: SceneTree) -> bool:
	var root_result := _get_root(tree)
	return (
		bool(root_result.ok)
		and (root_result.root as Window).has_meta(META_KEY)
	)


static func normalize(value: Dictionary) -> Dictionary:
	if value.has("ok"):
		var ok_value: Variant = value.ok
		if typeof(ok_value) != TYPE_BOOL or not ok_value:
			return _error(
				String(value.get("field", "request")),
				String(value.get("error", "World transition validation failed."))
			)
	var matrix_result := _bounded_int(value, "matrix", 0, 0x7FFFFFFF)
	if not bool(matrix_result.ok):
		return matrix_result
	var area_result := _bounded_int(value, "area", -1, MAX_U16)
	if not bool(area_result.ok):
		return area_result
	var cell_value: Variant = value.get("cell", null)
	if not cell_value is Vector2i:
		return _error("cell", "A world transition requires an occupied matrix cell.")
	var tile_value: Variant = value.get("tile", null)
	if not tile_value is Vector2i:
		return _error("tile", "A world transition requires a map tile.")
	var tile := tile_value as Vector2i
	if tile.x < 0 or tile.x >= MAP_TILE_SIZE or tile.y < 0 or tile.y >= MAP_TILE_SIZE:
		return _error("tile", "A world transition tile must be within 0..31.")
	var facing_result := _bounded_int(value, "facing", 0, 3)
	if not bool(facing_result.ok):
		return facing_result
	var source_cell_value: Variant = value.get("source_cell", null)
	if not source_cell_value is Vector2i:
		return _error("source_cell", "A world transition requires its source matrix cell.")
	var source_tile_value: Variant = value.get("source_tile", null)
	if not source_tile_value is Vector2i:
		return _error("source_tile", "A world transition requires its source map tile.")
	var source_tile := source_tile_value as Vector2i
	if (
		source_tile.x < 0
		or source_tile.x >= MAP_TILE_SIZE
		or source_tile.y < 0
		or source_tile.y >= MAP_TILE_SIZE
	):
		return _error("source_tile", "A world transition source tile must be within 0..31.")
	var source_header_result := _bounded_int(value, "source_header_id", 0, MAX_U16)
	if not bool(source_header_result.ok):
		return source_header_result
	var source_warp_result := _bounded_int(value, "source_warp_id", 0, MAX_U16)
	if not bool(source_warp_result.ok):
		return source_warp_result
	var destination_header_result := _bounded_int(
		value, "destination_header_id", 0, MAX_U16
	)
	if not bool(destination_header_result.ok):
		return destination_header_result
	var destination_warp_result := _bounded_int(value, "destination_warp_id", 0, MAX_U16)
	if not bool(destination_warp_result.ok):
		return destination_warp_result
	var kind_value: Variant = value.get("transition_kind", null)
	if typeof(kind_value) not in [TYPE_STRING, TYPE_STRING_NAME] or String(kind_value) != "warp":
		return _error("transition_kind", "Only normalized warp transitions are supported.")
	var door_result := _bounded_int(value, "door_model_id", -1, MAX_U16)
	if not bool(door_result.ok):
		return door_result
	return {
		"ok": true,
		"error": "",
		"field": "",
		"request": {
			"matrix": int(matrix_result.value),
			"area": int(area_result.value),
			"cell": cell_value as Vector2i,
			"tile": tile,
			"facing": int(facing_result.value),
			"source_cell": source_cell_value as Vector2i,
			"source_tile": source_tile,
			"source_header_id": int(source_header_result.value),
			"source_warp_id": int(source_warp_result.value),
			"destination_header_id": int(destination_header_result.value),
			"destination_warp_id": int(destination_warp_result.value),
			"transition_kind": &"warp",
			"door_model_id": int(door_result.value),
		},
	}


static func _bounded_int(value: Dictionary, field: String, minimum: int, maximum: int) -> Dictionary:
	var field_value: Variant = value.get(field, null)
	if typeof(field_value) != TYPE_INT:
		return _error(field, "World transition %s must be an integer." % field)
	var number := int(field_value)
	if number < minimum or number > maximum:
		return _error(
			field,
			"World transition %s must be within %d..%d." % [field, minimum, maximum]
		)
	return {"ok": true, "value": number}


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


static func _empty_take() -> Dictionary:
	return {
		"ok": true,
		"error": "",
		"field": "",
		"pending": false,
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
