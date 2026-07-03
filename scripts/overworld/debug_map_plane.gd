extends Node2D

@export var map_size := Vector2i(20, 20)
@export var tile_size := 16

var block_ids: Array = []
var tileset_data: Dictionary = {}
var _atlas_texture: Texture2D = null
var _atlas_tile_size := 16
var _atlas_columns := 0
var _atlas_total_metatiles := 0

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


func configure_from_map_data(map_data: Dictionary, new_tileset_data: Dictionary = {}) -> void:
	tile_size = DataRegistry.TILE_SIZE
	_configure_tileset_data(new_tileset_data)

	if map_data.is_empty():
		map_size = DataRegistry.get_start_map_size()
		block_ids = []
		queue_redraw()
		return

	var layout_info = map_data.get("layout", {})
	if typeof(layout_info) == TYPE_DICTIONARY:
		map_size = Vector2i(
			int(layout_info.get("width", map_size.x)),
			int(layout_info.get("height", map_size.y))
		)
	block_ids = map_data.get("block_ids", [])
	queue_redraw()


func _draw() -> void:
	for y in range(map_size.y):
		for x in range(map_size.x):
			var rect := Rect2(x * tile_size, y * tile_size, tile_size, tile_size)
			var block_id := _get_block_id(x, y)
			if not _draw_atlas_tile(block_id, rect):
				var fill := _get_tile_color(block_id, x, y)
				draw_rect(rect, fill, true)
			draw_rect(rect, GRID_LINE, false, 1.0)

	var border := Rect2(Vector2.ZERO, Vector2(map_size.x * tile_size, map_size.y * tile_size))
	draw_rect(border, BORDER_LINE, false, 2.0)


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
	if y < block_ids.size():
		var row = block_ids[y]
		if typeof(row) == TYPE_ARRAY and x < row.size():
			return int(row[x])
	return -1


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


func _get_tile_color(block_id: int, x: int, y: int) -> Color:
	if block_id >= 0:
		return BLOCK_COLORS[block_id % BLOCK_COLORS.size()]
	return TILE_A if (x + y) % 2 == 0 else TILE_B
