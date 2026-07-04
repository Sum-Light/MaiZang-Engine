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
	GameState.set_player_gender("MALE")

	var player = PLAYER_SCENE.instantiate()
	add_child(player)
	await get_tree().process_frame
	player.set_physics_process(false)
	player.facing_direction = Vector2i.DOWN
	player.set_grid_position(Vector2i(10, 13))
	player.moved.connect(func(_grid_position): _moved_count += 1)
	var initial_snapshot: Dictionary = player.get_sprite_snapshot()
	_assert(bool(initial_snapshot.get("using_sprite", false)), "expected player to use source object-event sprite")
	_assert(String(initial_snapshot.get("graphics_id", "")) == "OBJ_EVENT_GFX_BRENDAN_NORMAL", "expected male player Brendan source graphics")
	_assert(_array_value(initial_snapshot.get("source_rect", [])) == [0, 0, 16, 32], "expected player south static source rect")
	_assert(_array_value(initial_snapshot.get("dest_rect", [])) == [-8, -24, 16, 32], "expected player source sprite bottom-of-tile dest rect")
	_assert(_array_value(initial_snapshot.get("world_position", [])) == [168, 216], "expected player tile-center world anchor")
	_assert(_unsupported_has(initial_snapshot, "player_avatar_walk_animation_not_runtime_driven"), "expected explicit player walk animation unsupported note")

	_assert(MapRuntime.can_enter_cell(Vector2i(11, 13)), "expected test target cell to be enterable")

	_release_test_actions()
	Input.action_press("ui_right")
	player._physics_process(1.0 / 60.0)
	Input.action_release("ui_right")
	await get_tree().process_frame
	_assert(player.facing_direction == Vector2i.RIGHT, "expected first different-direction input to turn right")
	_assert(player.grid_position == Vector2i(10, 13), "expected turn-in-place not to move player")
	_assert(_moved_count == 0, "expected turn-in-place not to emit moved")
	_assert(_array_value(player.last_input_source_trace).has("src/field_player_avatar.c:TURN_DIRECTION"), "expected turn source trace")
	var right_snapshot: Dictionary = player.get_sprite_snapshot()
	_assert(_array_value(right_snapshot.get("source_rect", [])) == [32, 0, 16, 32], "expected player east static source rect")
	_assert(bool(right_snapshot.get("h_flip", false)), "expected player east hFlip")

	_release_test_actions()
	Input.action_press("ui_right")
	player._physics_process(1.0 / 60.0)
	Input.action_release("ui_right")
	await get_tree().process_frame
	_assert(player.grid_position == Vector2i(11, 13), "expected second held same-direction frame to start movement")
	_assert(_array_value(player.last_input_source_trace).has("src/event_object_movement.c:SetSpriteDataForNormalStep"), "expected normal step source trace")
	await get_tree().create_timer(0.35).timeout
	_assert(_moved_count == 1, "expected one completed tile movement")

	GameState.set_player_gender("FEMALE")
	var female_player = PLAYER_SCENE.instantiate()
	add_child(female_player)
	await get_tree().process_frame
	female_player.set_physics_process(false)
	female_player.facing_direction = Vector2i.DOWN
	female_player.set_grid_position(Vector2i(10, 13))
	var female_snapshot: Dictionary = female_player.get_sprite_snapshot()
	_assert(bool(female_snapshot.get("using_sprite", false)), "expected female player to use source object-event sprite")
	_assert(String(female_snapshot.get("graphics_id", "")) == "OBJ_EVENT_GFX_MAY_NORMAL", "expected female player May source graphics")
	_assert(_array_value(female_snapshot.get("source_rect", [])) == [0, 0, 16, 32], "expected female player south static source rect")
	_assert(_array_value(female_snapshot.get("dest_rect", [])) == [-8, -24, 16, 32], "expected female player source sprite bottom-of-tile dest rect")
	_assert(_unsupported_has(female_snapshot, "player_avatar_walk_animation_not_runtime_driven"), "expected female player walk animation unsupported note")
	female_player.queue_free()

	if _failed:
		return

	print(JSON.stringify({
		"player_turn_input_smoke": "ok",
		"position": [player.grid_position.x, player.grid_position.y],
		"moved_count": _moved_count,
		"female_graphics_id": female_snapshot.get("graphics_id", ""),
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


func _unsupported_has(snapshot: Dictionary, code: String) -> bool:
	var unsupported = snapshot.get("unsupported", [])
	if typeof(unsupported) != TYPE_ARRAY:
		return false
	for entry in unsupported:
		if typeof(entry) == TYPE_DICTIONARY and String(entry.get("code", "")) == code:
			return true
	return false


func _ensure_builtin_ui_actions() -> void:
	for action in ["ui_up", "ui_down", "ui_left", "ui_right"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)


func _release_test_actions() -> void:
	for action in ["ui_up", "ui_down", "ui_left", "ui_right", "ui_accept"]:
		Input.action_release(action)
