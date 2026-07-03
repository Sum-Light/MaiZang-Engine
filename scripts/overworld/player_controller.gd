extends "res://scripts/overworld/grid_mover.gd"

signal movement_blocked(target_position: Vector2i, cell_info: Dictionary)
signal interaction_requested(
	origin_position: Vector2i,
	target_position: Vector2i,
	facing_direction: Vector2i,
	interaction: Dictionary
)

var facing_direction := Vector2i.DOWN


func _ready() -> void:
	tile_size = DataRegistry.TILE_SIZE
	set_grid_position(GameState.player_grid_position)


func _physics_process(_delta: float) -> void:
	if _is_moving:
		return

	if Input.is_action_just_pressed("ui_accept"):
		_emit_interaction_request()
		return

	var direction := _read_input_direction()
	if direction != Vector2i.ZERO:
		facing_direction = direction
		var target_position := grid_position + direction
		if MapRuntime.can_enter_cell(target_position):
			try_move(direction)
		else:
			movement_blocked.emit(target_position, MapRuntime.get_cell_info(target_position))


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


func _emit_interaction_request() -> void:
	var interaction := MapRuntime.get_interaction_target(grid_position, facing_direction)
	interaction_requested.emit(
		grid_position,
		grid_position + facing_direction,
		facing_direction,
		interaction
	)
