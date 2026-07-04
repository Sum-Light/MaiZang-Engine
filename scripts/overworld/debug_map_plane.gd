extends Node2D

@export var map_size := Vector2i(20, 20)
@export var tile_size := 16
@export var show_grid := false

var block_ids: Array = []
var tileset_data: Dictionary = {}
var _map_data: Dictionary = {}
var _data_registry: Node = null
var _border_grid: Dictionary = {}
var _connections: Array = []
var _atlas_texture: Texture2D = null
var _atlas_tile_size := 16
var _atlas_columns := 0
var _atlas_total_metatiles := 0
var _door_animation_overlays: Dictionary = {}
var _door_animation_texture_cache: Dictionary = {}

const FALLBACK_TILE_SIZE := 16
const FALLBACK_MAP_SIZE := Vector2i(20, 20)
const MAP_OFFSET := 7
const TILE_A := Color(0.64, 0.78, 0.50, 1.0)
const TILE_B := Color(0.56, 0.72, 0.45, 1.0)
const GRID_LINE := Color(0.22, 0.31, 0.24, 0.55)
const BORDER_LINE := Color(0.08, 0.12, 0.10, 0.95)
const BLOCK_COLORS := [
	Color(0.44, 0.68, 0.36, 1.0),
	Color(0.58, 0.76, 0.42, 1.0),
	Color(0.72, 0.66, 0.45, 1.0),
	Color(0.43, 0.58, 0.72, 1.0),
	Color(0.55, 0.46, 0.70, 1.0),
	Color(0.70, 0.52, 0.42, 1.0),
	Color(0.45, 0.70, 0.62, 1.0),
	Color(0.68, 0.70, 0.50, 1.0),
]


func configure_data_registry(data_registry: Node) -> void:
	_data_registry = data_registry


func configure_from_map_data(map_data: Dictionary, new_tileset_data: Dictionary = {}) -> void:
	var registry := get_node_or_null("/root/DataRegistry") if is_inside_tree() else null
	if _data_registry == null:
		_data_registry = registry
	tile_size = FALLBACK_TILE_SIZE
	_configure_tileset_data(new_tileset_data)
	_map_data = map_data.duplicate(true)
	_border_grid = {}
	_connections = []

	if map_data.is_empty():
		map_size = _registry_start_map_size(registry)
		block_ids = []
		clear_door_animations()
		queue_redraw()
		return

	var layout_info = map_data.get("layout", {})
	if typeof(layout_info) == TYPE_DICTIONARY:
		map_size = Vector2i(
			int(layout_info.get("width", map_size.x)),
			int(layout_info.get("height", map_size.y))
		)
	block_ids = map_data.get("block_ids", [])
	var border_grid = map_data.get("border_grid", {})
	if typeof(border_grid) == TYPE_DICTIONARY:
		_border_grid = border_grid
	_index_connections(map_data)
	clear_door_animations()
	queue_redraw()


func _draw() -> void:
	for y in range(-MAP_OFFSET, map_size.y + MAP_OFFSET):
		for x in range(-MAP_OFFSET, map_size.x + MAP_OFFSET + 1):
			var rect := Rect2(x * tile_size, y * tile_size, tile_size, tile_size)
			var block_id := _get_block_id(x, y)
			if not _draw_atlas_tile(block_id, rect):
				var fill := _get_tile_color(block_id, x, y)
				draw_rect(rect, fill, true)
			if show_grid:
				draw_rect(rect, GRID_LINE, false, 1.0)

	var border := Rect2(Vector2.ZERO, Vector2(map_size.x * tile_size, map_size.y * tile_size))
	_draw_door_animation_overlays()
	draw_rect(border, BORDER_LINE, false, 2.0)


func set_grid_visible(value: bool) -> void:
	show_grid = value
	queue_redraw()


func is_grid_visible() -> bool:
	return show_grid


func set_door_animation_frame(position: Vector2i, animation: Dictionary, frame_index: int) -> bool:
	if frame_index < 0:
		clear_door_animation(position)
		return true

	var texture := _door_animation_texture(animation)
	if texture == null:
		return false

	var frame := _door_animation_frame(animation, frame_index)
	if frame.is_empty():
		return false

	_door_animation_overlays[_cell_key(position)] = {
		"position": position,
		"texture": texture,
		"source_rect": frame["source_rect"],
		"frame_size": frame["frame_size"],
	}
	queue_redraw()
	return true


func clear_door_animation(position: Vector2i) -> void:
	var key := _cell_key(position)
	if _door_animation_overlays.has(key):
		_door_animation_overlays.erase(key)
		queue_redraw()


func clear_door_animations() -> void:
	if _door_animation_overlays.is_empty():
		return
	_door_animation_overlays.clear()
	queue_redraw()


func get_door_animation_overlay_count() -> int:
	return _door_animation_overlays.size()


func get_render_block_id(cell: Vector2i) -> int:
	return _get_block_id(cell.x, cell.y)


func _configure_tileset_data(new_tileset_data: Dictionary) -> void:
	tileset_data = new_tileset_data
	_atlas_texture = null
	_atlas_tile_size = tile_size
	_atlas_columns = 0
	_atlas_total_metatiles = 0

	if tileset_data.is_empty():
		return

	var atlas_info = tileset_data.get("atlas", {})
	if typeof(atlas_info) != TYPE_DICTIONARY:
		return

	_atlas_tile_size = int(atlas_info.get("tile_size", tile_size))
	_atlas_columns = int(atlas_info.get("columns", 0))
	_atlas_total_metatiles = int(atlas_info.get("total_metatiles", 0))
	if _atlas_tile_size > 0:
		tile_size = _atlas_tile_size

	var image_path := String(atlas_info.get("image", ""))
	if image_path.is_empty():
		return

	var loaded_resource := load(image_path)
	if loaded_resource is Texture2D:
		_atlas_texture = loaded_resource
		return

	var image := Image.new()
	var load_error := image.load(image_path)
	if load_error != OK:
		push_warning("Could not load generated tileset atlas: %s" % image_path)
		return

	_atlas_texture = ImageTexture.create_from_image(image)


func _get_block_id(x: int, y: int) -> int:
	if y >= 0 and y < block_ids.size():
		var row = block_ids[y]
		if typeof(row) == TYPE_ARRAY and x >= 0 and x < row.size():
			return int(row[x])
	var connected := _connected_block_id(Vector2i(x, y))
	if bool(connected.get("found", false)):
		return int(connected.get("value", -1))
	var border := _border_block_id(Vector2i(x, y))
	if bool(border.get("found", false)):
		return int(border.get("value", -1))
	return -1


func _index_connections(map_data: Dictionary) -> void:
	var connections = map_data.get("connections", [])
	if typeof(connections) != TYPE_ARRAY:
		var events = map_data.get("events", {})
		if typeof(events) == TYPE_DICTIONARY:
			connections = events.get("connections", [])
	if typeof(connections) != TYPE_ARRAY:
		return

	for source_connection in connections:
		if typeof(source_connection) != TYPE_DICTIONARY:
			continue
		var connection = source_connection.duplicate(true)
		connection["direction"] = _normalize_connection_direction(String(connection.get("direction", "")))
		connection["offset"] = int(connection.get("offset", 0))
		if String(connection.get("direction", "")).is_empty():
			continue
		if String(connection.get("map", "")).is_empty():
			continue
		_connections.append(connection)


func _connected_block_id(cell: Vector2i) -> Dictionary:
	var connection := _connection_for_cell(cell)
	if connection.is_empty():
		return {"found": false}

	var connected_map := _connected_map_data(String(connection.get("map", "")))
	if connected_map.is_empty():
		return {"found": false}

	var destination_position := _connection_destination_position(connection, cell)
	var destination_size := _map_size_from_data(connected_map)
	if not _is_cell_in_size(destination_position, destination_size):
		return {"found": false}

	var connected_block_ids = connected_map.get("block_ids", [])
	if typeof(connected_block_ids) != TYPE_ARRAY:
		return {"found": false}
	return _grid_cell_value(connected_block_ids, destination_position)


func _border_block_id(cell: Vector2i) -> Dictionary:
	if _border_grid.is_empty():
		return {"found": false}

	var values = _border_grid.get("metatile_ids", [])
	if typeof(values) != TYPE_ARRAY:
		values = _border_grid.get("block_ids", [])
	if typeof(values) != TYPE_ARRAY or values.is_empty():
		return {"found": false}

	var dimensions := _border_grid_dimensions(values)
	if dimensions.x <= 0 or dimensions.y <= 0:
		return {"found": false}

	var index := _border_grid_index(cell, dimensions.x, dimensions.y)
	if index < 0 or index >= values.size():
		return {"found": false}
	return {
		"found": true,
		"value": int(values[index]),
	}


func _border_grid_dimensions(values: Array) -> Vector2i:
	var width := int(_border_grid.get("width", 0))
	var height := int(_border_grid.get("height", 0))
	if width <= 0:
		width = 2 if values.size() >= 2 else 1
	if height <= 0:
		height = int(values.size() / width)
		if values.size() % width != 0:
			height += 1
	return Vector2i(width, height)


func _border_grid_index(cell: Vector2i, width: int, height: int) -> int:
	var rule := String(_border_grid.get("source_index_rule", ""))
	var map_offset := int(_border_grid.get("map_offset", MAP_OFFSET))
	if rule == "emerald_2x2_parity":
		return (
			_positive_mod(cell.y + map_offset + 1, height) * width
			+ _positive_mod(cell.x + map_offset + 1, width)
		)
	if rule == "frlg_wrapped_border":
		return _positive_mod(cell.y, height) * width + _positive_mod(cell.x, width)
	return _positive_mod(cell.y, height) * width + _positive_mod(cell.x, width)


func _connection_for_cell(cell: Vector2i) -> Dictionary:
	if _is_cell_in_size(cell, map_size):
		return {}

	for connection in _connections:
		if typeof(connection) != TYPE_DICTIONARY:
			continue
		if _connection_matches_cell(connection, cell):
			return connection
	return {}


func _connection_matches_cell(connection: Dictionary, cell: Vector2i) -> bool:
	var direction := String(connection.get("direction", ""))
	var destination_size := _map_size_for_connection(connection)
	if destination_size == Vector2i.ZERO:
		destination_size = map_size
	var offset := int(connection.get("offset", 0))

	match direction:
		"north":
			return cell.y < 0 and _is_axis_in_destination(cell.x - offset, destination_size.x)
		"south":
			return cell.y >= map_size.y and _is_axis_in_destination(cell.x - offset, destination_size.x)
		"west":
			return cell.x < 0 and _is_axis_in_destination(cell.y - offset, destination_size.y)
		"east":
			return cell.x >= map_size.x and _is_axis_in_destination(cell.y - offset, destination_size.y)
	return false


func _connection_destination_position(connection: Dictionary, cell: Vector2i) -> Vector2i:
	var direction := String(connection.get("direction", ""))
	var destination_size := _map_size_for_connection(connection)
	if destination_size == Vector2i.ZERO:
		destination_size = map_size
	var offset := int(connection.get("offset", 0))

	match direction:
		"north":
			return Vector2i(cell.x - offset, destination_size.y + cell.y)
		"south":
			return Vector2i(cell.x - offset, cell.y - map_size.y)
		"west":
			return Vector2i(destination_size.x + cell.x, cell.y - offset)
		"east":
			return Vector2i(cell.x - map_size.x, cell.y - offset)
	return Vector2i(-1, -1)


func _map_size_for_connection(connection: Dictionary) -> Vector2i:
	var connected_map := _connected_map_data(String(connection.get("map", "")))
	if connected_map.is_empty():
		return Vector2i.ZERO
	return _map_size_from_data(connected_map)


func _connected_map_data(map_id: String) -> Dictionary:
	if map_id.is_empty():
		return {}
	var registry := _registry()
	if registry == null or not registry.has_method("get_map_data"):
		return {}
	var map_data = registry.get_map_data(map_id)
	return map_data if typeof(map_data) == TYPE_DICTIONARY else {}


func _map_size_from_data(map_data: Dictionary) -> Vector2i:
	var layout_info = map_data.get("layout", {})
	if typeof(layout_info) != TYPE_DICTIONARY:
		return Vector2i.ZERO
	return Vector2i(
		int(layout_info.get("width", 0)),
		int(layout_info.get("height", 0))
	)


func _grid_cell_value(grid: Array, cell: Vector2i) -> Dictionary:
	if cell.y < 0 or cell.y >= grid.size():
		return {"found": false}

	var row = grid[cell.y]
	if typeof(row) != TYPE_ARRAY or cell.x < 0 or cell.x >= row.size():
		return {"found": false}
	return {
		"found": true,
		"value": int(row[cell.x]),
	}


func _registry() -> Node:
	if _data_registry != null:
		return _data_registry
	if is_inside_tree():
		return get_node_or_null("/root/DataRegistry")
	return null


func _is_axis_in_destination(axis_value: int, destination_max: int) -> bool:
	return destination_max > 0 and axis_value >= 0 and axis_value < destination_max


func _is_cell_in_size(cell: Vector2i, size: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < size.x and cell.y < size.y


func _normalize_connection_direction(direction: String) -> String:
	var normalized := direction.to_lower()
	if normalized.begins_with("connection_"):
		normalized = normalized.replace("connection_", "")
	match normalized:
		"up", "north":
			return "north"
		"down", "south":
			return "south"
		"left", "west":
			return "west"
		"right", "east":
			return "east"
	return normalized


func _positive_mod(value: int, modulo: int) -> int:
	if modulo <= 0:
		return 0
	var result := value % modulo
	if result < 0:
		result += modulo
	return result


func _draw_atlas_tile(block_id: int, rect: Rect2) -> bool:
	if _atlas_texture == null or _atlas_columns <= 0 or block_id < 0:
		return false
	if _atlas_total_metatiles > 0 and block_id >= _atlas_total_metatiles:
		return false

	var atlas_column := block_id % _atlas_columns
	var atlas_row := int(floor(float(block_id) / float(_atlas_columns)))
	var source_rect := Rect2(
		atlas_column * _atlas_tile_size,
		atlas_row * _atlas_tile_size,
		_atlas_tile_size,
		_atlas_tile_size
	)
	draw_texture_rect_region(_atlas_texture, rect, source_rect)
	return true


func _draw_door_animation_overlays() -> void:
	for overlay in _door_animation_overlays.values():
		if typeof(overlay) != TYPE_DICTIONARY:
			continue
		var texture = overlay.get("texture", null)
		if not texture is Texture2D:
			continue
		var position = overlay.get("position", Vector2i.ZERO)
		if typeof(position) != TYPE_VECTOR2I:
			continue
		var source_rect = overlay.get("source_rect", Rect2())
		if typeof(source_rect) != TYPE_RECT2:
			continue
		var frame_size = overlay.get("frame_size", Vector2(tile_size, tile_size * 2))
		if typeof(frame_size) != TYPE_VECTOR2:
			continue
		var dest_rect := Rect2(
			position.x * tile_size,
			position.y * tile_size,
			frame_size.x,
			frame_size.y
		)
		draw_texture_rect_region(texture, dest_rect, source_rect)


func _door_animation_texture(animation: Dictionary) -> Texture2D:
	var image_path := String(animation.get("image", ""))
	if image_path.is_empty():
		return null
	if _door_animation_texture_cache.has(image_path):
		var cached = _door_animation_texture_cache[image_path]
		return cached if cached is Texture2D else null

	var load_path := image_path
	if load_path.begins_with("res://") or load_path.begins_with("user://"):
		load_path = ProjectSettings.globalize_path(load_path)
	var image := Image.new()
	if image.load(load_path) != OK:
		push_warning("Could not load generated door animation atlas: %s" % image_path)
		return null

	var texture := ImageTexture.create_from_image(image)
	_door_animation_texture_cache[image_path] = texture
	return texture


func _door_animation_frame(animation: Dictionary, frame_index: int) -> Dictionary:
	var frames = animation.get("frames", [])
	if typeof(frames) != TYPE_ARRAY:
		return {}

	var frame_size_info = animation.get("frame_size", {})
	var frame_size := Vector2(tile_size, tile_size * 2)
	if typeof(frame_size_info) == TYPE_DICTIONARY:
		frame_size = Vector2(
			float(frame_size_info.get("w", frame_size.x)),
			float(frame_size_info.get("h", frame_size.y))
		)

	for frame in frames:
		if typeof(frame) != TYPE_DICTIONARY or int(frame.get("index", -1)) != frame_index:
			continue
		var rect_info = frame.get("source_rect", {})
		if typeof(rect_info) != TYPE_DICTIONARY:
			return {}
		return {
			"source_rect": Rect2(
				float(rect_info.get("x", 0)),
				float(rect_info.get("y", 0)),
				float(rect_info.get("w", frame_size.x)),
				float(rect_info.get("h", frame_size.y))
			),
			"frame_size": frame_size,
		}
	return {}


func _cell_key(cell: Vector2i) -> String:
	return "%d,%d" % [cell.x, cell.y]


func _registry_start_map_size(registry: Node) -> Vector2i:
	if registry != null and registry.has_method("get_start_map_size"):
		var size = registry.call("get_start_map_size")
		if typeof(size) == TYPE_VECTOR2I:
			return size
	return FALLBACK_MAP_SIZE


func _get_tile_color(block_id: int, x: int, y: int) -> Color:
	if block_id >= 0:
		return BLOCK_COLORS[block_id % BLOCK_COLORS.size()]
	return TILE_A if (x + y) % 2 == 0 else TILE_B
