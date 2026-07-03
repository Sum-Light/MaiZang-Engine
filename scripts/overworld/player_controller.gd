extends "res://scripts/overworld/grid_mover.gd"


func _ready() -> void:
	tile_size = DataRegistry.TILE_SIZE
	set_grid_position(GameState.player_grid_position)


func _physics_process(_delta: float) -> void:
	if _is_moving:
		return

	var direction := _read_input_direction()
	if direction != Vector2i.ZERO:
		try_move(direction)


func _read_input_direction() -> Vector2i:
	if Input.is_action_pressed("ui_up"):
		return Vector2i.UP
	if Input.is_action_pressed("ui_down"):
		return Vector2i.DOWN
	if Input.is_action_pressed("ui_left"):
		return Vector2i.LEFT
	if Input.is_action_pressed("ui_right"):
		return Vector2i.RIGHT
	return Vector2i.ZERO
