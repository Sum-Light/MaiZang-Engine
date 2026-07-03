extends Node2D

@export var map_size := Vector2i(20, 20)
@export var tile_size := 16

var block_ids: Array = []

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


func configure_from_map_data(map_data: Dictionary) -> void:
	tile_size = DataRegistry.TILE_SIZE
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
			var fill := _get_tile_color(x, y)
			draw_rect(rect, fill, true)
			draw_rect(rect, GRID_LINE, false, 1.0)

	var border := Rect2(Vector2.ZERO, Vector2(map_size.x * tile_size, map_size.y * tile_size))
	draw_rect(border, BORDER_LINE, false, 2.0)


func _get_tile_color(x: int, y: int) -> Color:
	if y < block_ids.size():
		var row = block_ids[y]
		if typeof(row) == TYPE_ARRAY and x < row.size():
			var block_id := int(row[x])
			return BLOCK_COLORS[block_id % BLOCK_COLORS.size()]
	return TILE_A if (x + y) % 2 == 0 else TILE_B
