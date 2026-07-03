extends Node

const COLLISION_NONE := 0
const COLLISION_IMPASSABLE := 1
const ELEVATION_INVALID := -1

var _map_data: Dictionary = {}
var _tileset_data: Dictionary = {}
var _map_size := Vector2i.ZERO
var _block_ids: Array = []
var _collision_grid: Array = []
var _elevation_grid: Array = []
var _metatile_attributes: Dictionary = {}


func _ready() -> void:
	var registry = get_node_or_null("/root/DataRegistry")
	if registry == null:
		return

	configure_from_data(
		registry.get_start_map_data(),
		registry.get_start_tileset_data(),
		registry.get_start_map_size()
	)


func configure_from_data(
	map_data: Dictionary,
	tileset_data: Dictionary,
	fallback_map_size := Vector2i.ZERO
) -> void:
	_map_data = map_data
	_tileset_data = tileset_data
	_map_size = fallback_map_size
	_block_ids = []
	_collision_grid = []
	_elevation_grid = []
	_metatile_attributes = {}

	if not _map_data.is_empty():
		var layout_info = _map_data.get("layout", {})
		if typeof(layout_info) == TYPE_DICTIONARY:
			_map_size = Vector2i(
				int(layout_info.get("width", _map_size.x)),
				int(layout_info.get("height", _map_size.y))
			)

		_block_ids = _array_or_empty(_map_data.get("block_ids", []))
		var map_grid = _map_data.get("map_grid", {})
		if typeof(map_grid) == TYPE_DICTIONARY:
			_collision_grid = _array_or_empty(map_grid.get("collision", []))
			_elevation_grid = _array_or_empty(map_grid.get("elevation", []))

	_index_metatile_attributes()


func is_within_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < _map_size.x and cell.y < _map_size.y


func can_enter_cell(cell: Vector2i) -> bool:
	return is_within_bounds(cell) and get_collision_at(cell) == COLLISION_NONE


func get_map_size() -> Vector2i:
	return _map_size


func get_metatile_id_at(cell: Vector2i) -> int:
	return _grid_value(_block_ids, cell, -1)


func get_collision_at(cell: Vector2i) -> int:
	if not is_within_bounds(cell):
		return COLLISION_IMPASSABLE
	if _collision_grid.is_empty():
		return COLLISION_NONE
	return _grid_value(_collision_grid, cell, COLLISION_IMPASSABLE)


func get_elevation_at(cell: Vector2i) -> int:
	return _grid_value(_elevation_grid, cell, ELEVATION_INVALID)


func get_metatile_attribute(metatile_id: int) -> Dictionary:
	if _metatile_attributes.has(metatile_id):
		var attribute = _metatile_attributes[metatile_id]
		if typeof(attribute) == TYPE_DICTIONARY:
			return attribute
	return {}


func get_metatile_behavior_at(cell: Vector2i) -> int:
	return int(get_metatile_attribute(get_metatile_id_at(cell)).get("behavior", -1))


func get_metatile_layer_type_at(cell: Vector2i) -> int:
	return int(get_metatile_attribute(get_metatile_id_at(cell)).get("layer_type", -1))


func get_cell_info(cell: Vector2i) -> Dictionary:
	var metatile_id := get_metatile_id_at(cell)
	return {
		"position": cell,
		"within_bounds": is_within_bounds(cell),
		"metatile_id": metatile_id,
		"collision": get_collision_at(cell),
		"elevation": get_elevation_at(cell),
		"behavior": get_metatile_attribute(metatile_id).get("behavior", -1),
		"layer_type": get_metatile_attribute(metatile_id).get("layer_type", -1),
		"passable": can_enter_cell(cell),
	}


func _index_metatile_attributes() -> void:
	if _tileset_data.is_empty():
		return

	var entries = _tileset_data.get("metatile_entries", [])
	if typeof(entries) != TYPE_ARRAY:
		return

	for entry in entries:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var metatile_id := int(entry.get("id", -1))
		if metatile_id < 0:
			continue
		var attribute = entry.get("attribute", {})
		if typeof(attribute) == TYPE_DICTIONARY:
			_metatile_attributes[metatile_id] = attribute


func _array_or_empty(value) -> Array:
	return value if typeof(value) == TYPE_ARRAY else []


func _grid_value(grid: Array, cell: Vector2i, default_value: int) -> int:
	if cell.y < 0 or cell.y >= grid.size():
		return default_value

	var row = grid[cell.y]
	if typeof(row) != TYPE_ARRAY or cell.x < 0 or cell.x >= row.size():
		return default_value

	return int(row[cell.x])
