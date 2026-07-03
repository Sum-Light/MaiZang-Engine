extends Node2D

signal moved(grid_position: Vector2i)

@export var tile_size := 16
@export var move_duration := 0.12

var grid_position := Vector2i.ZERO
var _is_moving := false


func set_grid_position(value: Vector2i) -> void:
	grid_position = value
	position = _grid_to_world(grid_position)


func try_move(direction: Vector2i) -> bool:
	if _is_moving or direction == Vector2i.ZERO:
		return false

	_is_moving = true
	grid_position += direction

	var tween := create_tween()
	tween.tween_property(self, "position", _grid_to_world(grid_position), move_duration) \
		.set_trans(Tween.TRANS_SINE) \
		.set_ease(Tween.EASE_OUT)
	tween.finished.connect(_on_move_finished)
	return true


func _on_move_finished() -> void:
	_is_moving = false
	moved.emit(grid_position)


func _grid_to_world(value: Vector2i) -> Vector2:
	return Vector2(value.x * tile_size, value.y * tile_size)
