extends SceneTree

const MAP_RUNTIME_SCRIPT := preload("res://scripts/autoload/map_runtime.gd")
const MAP_PATH := "res://data/generated/maps/littleroot_town.json"
const TILESET_PATH := "res://data/generated/tilesets/littleroot_town.json"


func _init() -> void:
	var map_data := _load_json_object(MAP_PATH)
	var tileset_data := _load_json_object(TILESET_PATH)
	var map_size := _map_size_from_data(map_data)
	var runtime = MAP_RUNTIME_SCRIPT.new()
	runtime.configure_from_data(map_data, tileset_data, map_size)

	var start_cell := Vector2i(10, 10)
	var blocked_cell := _first_blocked_cell(map_data)
	_assert(runtime.get_map_size() == Vector2i(20, 20), "unexpected map size")
	_assert(runtime.can_enter_cell(start_cell), "expected start cell to be passable")
	_assert(not runtime.can_enter_cell(Vector2i(-1, start_cell.y)), "expected west out-of-bounds to be blocked")
	_assert(blocked_cell != Vector2i(-1, -1), "expected at least one blocked source cell")
	_assert(not runtime.can_enter_cell(blocked_cell), "expected source collision cell to be blocked")
	_assert(runtime.get_metatile_behavior_at(start_cell) >= 0, "expected metatile behavior lookup")

	print(JSON.stringify({
		"map_runtime_smoke": "ok",
		"map_size": _vector_to_array(runtime.get_map_size()),
		"start_cell": _cell_info_summary(runtime.get_cell_info(start_cell)),
		"blocked_cell": _cell_info_summary(runtime.get_cell_info(blocked_cell)),
	}))
	runtime.free()
	quit(0)


func _load_json_object(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Could not open %s" % path)
		quit(1)
		return {}

	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("%s is not a JSON object" % path)
		quit(1)
		return {}

	return parsed


func _map_size_from_data(map_data: Dictionary) -> Vector2i:
	var layout_info = map_data.get("layout", {})
	if typeof(layout_info) != TYPE_DICTIONARY:
		return Vector2i.ZERO
	return Vector2i(
		int(layout_info.get("width", 0)),
		int(layout_info.get("height", 0))
	)


func _first_blocked_cell(map_data: Dictionary) -> Vector2i:
	var map_grid = map_data.get("map_grid", {})
	if typeof(map_grid) != TYPE_DICTIONARY:
		return Vector2i(-1, -1)

	var collision_grid = map_grid.get("collision", [])
	if typeof(collision_grid) != TYPE_ARRAY:
		return Vector2i(-1, -1)

	for y in range(collision_grid.size()):
		var row = collision_grid[y]
		if typeof(row) != TYPE_ARRAY:
			continue
		for x in range(row.size()):
			if int(row[x]) != 0:
				return Vector2i(x, y)

	return Vector2i(-1, -1)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	quit(1)


func _cell_info_summary(cell_info: Dictionary) -> Dictionary:
	var position = cell_info.get("position", Vector2i(-1, -1))
	return {
		"position": _vector_to_array(position),
		"within_bounds": bool(cell_info.get("within_bounds", false)),
		"metatile_id": int(cell_info.get("metatile_id", -1)),
		"collision": int(cell_info.get("collision", -1)),
		"elevation": int(cell_info.get("elevation", -1)),
		"behavior": int(cell_info.get("behavior", -1)),
		"layer_type": int(cell_info.get("layer_type", -1)),
		"passable": bool(cell_info.get("passable", false)),
	}


func _vector_to_array(value: Vector2i) -> Array:
	return [value.x, value.y]
