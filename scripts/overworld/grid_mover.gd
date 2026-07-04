extends Node2D

signal moved(grid_position: Vector2i)

@export var tile_size := 16
@export var move_duration := 16.0 / 60.0

var grid_position := Vector2i.ZERO
var _is_moving := false
var _move_tween: Tween = null


func set_grid_position(value: Vector2i) -> void:
	grid_position = value
	position = _grid_to_world(grid_position)


func try_move(direction: Vector2i) -> bool:
	if _is_moving or direction == Vector2i.ZERO:
		return false

	_is_moving = true
	grid_position += direction

	_move_tween = create_tween()
	_move_tween.tween_property(self, "position", _grid_to_world(grid_position), move_duration) \
		.set_trans(Tween.TRANS_LINEAR) \
		.set_ease(Tween.EASE_IN_OUT)
	_move_tween.finished.connect(_on_move_finished)
	return true


func animate_grid_position(value: Vector2i, duration: float) -> void:
	if _move_tween != null and _move_tween.is_running():
		_move_tween.kill()

	if duration <= 0.0:
		set_grid_position(value)
		return

	_is_moving = true
	grid_position = value
	_move_tween = create_tween()
	_move_tween.tween_property(self, "position", _grid_to_world(value), duration) \
		.set_trans(Tween.TRANS_LINEAR) \
		.set_ease(Tween.EASE_IN_OUT)
	await _move_tween.finished
	_is_moving = false


func _on_move_finished() -> void:
	_is_moving = false
	moved.emit(grid_position)


func _grid_to_world(value: Vector2i) -> Vector2:
	return Vector2(value.x * tile_size, value.y * tile_size)
