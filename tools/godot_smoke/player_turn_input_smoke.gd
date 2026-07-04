extends Node

const PLAYER_SCENE := preload("res://scenes/overworld/player.tscn")

var _failed := false
var _moved_count := 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_ensure_builtin_ui_actions()
	MapRuntime.configure_from_data(
		DataRegistry.get_start_map_data({"include_debug_overlays": true}),
		DataRegistry.get_start_tileset_data(),
		DataRegistry.get_start_map_size()
	)
	GameState.player_grid_position = Vector2i(10, 13)

	var player = PLAYER_SCENE.instantiate()
	add_child(player)
	await get_tree().process_frame
	player.facing_direction = Vector2i.DOWN
	player.set_grid_position(Vector2i(10, 13))
	player.moved.connect(func(_grid_position): _moved_count += 1)

	_assert(MapRuntime.can_enter_cell(Vector2i(11, 13)), "expected test target cell to be enterable")

	Input.action_press("ui_right")
	await _wait_physics_processed()
	_assert(player.facing_direction == Vector2i.RIGHT, "expected first different-direction input to turn right")
	_assert(player.grid_position == Vector2i(10, 13), "expected turn-in-place not to move player")
	_assert(_moved_count == 0, "expected turn-in-place not to emit moved")
	_assert(_array_value(player.last_input_source_trace).has("src/field_player_avatar.c:TURN_DIRECTION"), "expected turn source trace")

	await _wait_physics_processed()
	_assert(player.grid_position == Vector2i(11, 13), "expected second held same-direction frame to start movement")
	_assert(_array_value(player.last_input_source_trace).has("src/event_object_movement.c:SetSpriteDataForNormalStep"), "expected normal step source trace")
	await get_tree().create_timer(0.35).timeout
	Input.action_release("ui_right")
	_assert(_moved_count == 1, "expected one completed tile movement")

	if _failed:
		return

	print(JSON.stringify({
		"player_turn_input_smoke": "ok",
		"position": [player.grid_position.x, player.grid_position.y],
		"moved_count": _moved_count,
	}))
	player.queue_free()
	get_tree().quit(0)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true
	get_tree().quit(1)


func _array_value(value) -> Array:
	return value if typeof(value) == TYPE_ARRAY else []


func _wait_physics_processed() -> void:
	await get_tree().physics_frame
	await get_tree().process_frame


func _ensure_builtin_ui_actions() -> void:
	for action in ["ui_up", "ui_down", "ui_left", "ui_right"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
