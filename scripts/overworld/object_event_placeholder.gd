extends Node2D

@export var tile_size := 16

var event_data: Dictionary = {}
var grid_position := Vector2i.ZERO
var _body_color := Color(0.88, 0.58, 0.32, 1.0)
var _accent_color := Color(0.18, 0.16, 0.14, 1.0)

const BODY_COLORS := [
	Color(0.86, 0.42, 0.38, 1.0),
	Color(0.34, 0.56, 0.82, 1.0),
	Color(0.90, 0.70, 0.30, 1.0),
	Color(0.46, 0.72, 0.48, 1.0),
	Color(0.70, 0.50, 0.78, 1.0),
	Color(0.82, 0.54, 0.34, 1.0),
	Color(0.36, 0.68, 0.68, 1.0),
	Color(0.78, 0.76, 0.42, 1.0),
]


func configure(new_event_data: Dictionary, new_tile_size: int) -> void:
	event_data = new_event_data
	tile_size = new_tile_size
	grid_position = event_data.get("position", Vector2i(
		int(event_data.get("x", 0)),
		int(event_data.get("y", 0))
	))
	position = Vector2(grid_position.x * tile_size, grid_position.y * tile_size)
	z_index = grid_position.y
	_body_color = _color_from_graphics_id(String(event_data.get("graphics_id", "")))
	queue_redraw()


func _draw() -> void:
	var body_rect := Rect2(-5, -11, 10, 15)
	var feet_rect := Rect2(-4, 4, 8, 4)
	var shadow_rect := Rect2(-6, 5, 12, 4)

	draw_rect(shadow_rect, Color(0.05, 0.07, 0.06, 0.35), true)
	draw_rect(body_rect, _body_color, true)
	draw_rect(body_rect, _accent_color, false, 1.0)
	draw_rect(feet_rect, _accent_color, true)


func _color_from_graphics_id(graphics_id: String) -> Color:
	if graphics_id == "OBJ_EVENT_GFX_TRUCK":
		return Color(0.34, 0.40, 0.46, 1.0)

	var color_index := 0
	for index in range(graphics_id.length()):
		color_index += graphics_id.unicode_at(index)
	return BODY_COLORS[color_index % BODY_COLORS.size()]
