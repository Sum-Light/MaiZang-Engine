extends Node2D

@export var map_size := Vector2i(20, 20)
@export var tile_size := 16

const TILE_A := Color(0.64, 0.78, 0.50, 1.0)
const TILE_B := Color(0.56, 0.72, 0.45, 1.0)
const GRID_LINE := Color(0.22, 0.31, 0.24, 0.55)
const BORDER_LINE := Color(0.08, 0.12, 0.10, 0.95)


func _draw() -> void:
	for y in range(map_size.y):
		for x in range(map_size.x):
			var rect := Rect2(x * tile_size, y * tile_size, tile_size, tile_size)
			var fill := TILE_A if (x + y) % 2 == 0 else TILE_B
			draw_rect(rect, fill, true)
			draw_rect(rect, GRID_LINE, false, 1.0)

	var border := Rect2(Vector2.ZERO, Vector2(map_size.x * tile_size, map_size.y * tile_size))
	draw_rect(border, BORDER_LINE, false, 2.0)
