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
	GameState.player_grid_position = Vector2i(2, 2)
	GameState.set_player_gender("MALE")

	var player = PLAYER_SCENE.instantiate()
	add_child(player)
	await get_tree().process_frame
	player.set_physics_process(false)
	player.facing_direction = Vector2i.DOWN
	player.set_grid_position(Vector2i(2, 2))
	player.moved.connect(func(_grid_position): _moved_count += 1)
	var initial_snapshot: Dictionary = player.get_sprite_snapshot()
	_assert(bool(initial_snapshot.get("using_sprite", false)), "expected player to use source object-event sprite")
	_assert(String(initial_snapshot.get("graphics_id", "")) == "OBJ_EVENT_GFX_BRENDAN_NORMAL", "expected male player Brendan source graphics")
	_assert(_array_value(initial_snapshot.get("source_rect", [])) == [0, 0, 16, 32], "expected player south static source rect")
	_assert(_array_value(initial_snapshot.get("dest_rect", [])) == [-8, -24, 16, 32], "expected player source sprite bottom-of-tile dest rect")
	_assert(_array_value(initial_snapshot.get("world_position", [])) == [40, 40], "expected player tile-center world anchor")
	_assert(String(initial_snapshot.get("animation_state", "")) == "static", "expected initial player animation state to be static")
	_assert(int(initial_snapshot.get("animation_frame_index", -1)) == 0, "expected initial player source frame 0")
	_assert(not _unsupported_has(initial_snapshot, "player_avatar_walk_animation_not_runtime_driven"), "expected player normal walk animation to be runtime-supported")
	_assert(_unsupported_has(initial_snapshot, "player_avatar_run_continuous_fast_walk_spin_animation_not_runtime_driven"), "expected explicit unsupported note for non-normal player animation states")

	_assert(MapRuntime.can_enter_cell(Vector2i(3, 2)), "expected test target cell to be enterable")

	_release_test_actions()
	Input.action_press("ui_right")
	player._physics_process(1.0 / 60.0)
	Input.action_release("ui_right")
	_assert(player.facing_direction == Vector2i.RIGHT, "expected first different-direction input to turn right")
	_assert(player.grid_position == Vector2i(2, 2), "expected turn-in-place not to move player")
	_assert(_moved_count == 0, "expected turn-in-place not to emit moved")
	_assert(_array_value(player.last_input_source_trace).has("src/field_player_avatar.c:TURN_DIRECTION"), "expected turn source trace")
	_assert(_array_value(player.last_input_source_trace).has("src/event_object_movement.c:GetWalkInPlaceFastMovementAction"), "expected source walk-in-place fast trace")
	var turn_start_snapshot: Dictionary = player.get_sprite_snapshot()
	_assert(String(turn_start_snapshot.get("animation_state", "")) == "turning", "expected turn-in-place to run source fast-walk animation")
	_assert(_array_value(turn_start_snapshot.get("source_rect", [])) == [112, 0, 16, 32], "expected source east turn frame 7 at fast-walk frame 0")
	_assert(bool(turn_start_snapshot.get("h_flip", false)), "expected source east turn frame hFlip")
	_assert(int(turn_start_snapshot.get("animation_total_frames", -1)) == 8, "expected source turn-in-place fast duration")
	player._apply_active_sprite_animation_frame(4)
	var turn_mid_snapshot: Dictionary = player.get_sprite_snapshot()
	_assert(_array_value(turn_mid_snapshot.get("source_rect", [])) == [32, 0, 16, 32], "expected source east turn frame 2 at fast-walk frame 4")
	player._finish_active_sprite_animation()
	var right_snapshot: Dictionary = player.get_sprite_snapshot()
	_assert(String(right_snapshot.get("animation_state", "")) == "static", "expected turn-in-place to finish on static animation state")
	_assert(_array_value(right_snapshot.get("source_rect", [])) == [32, 0, 16, 32], "expected player east static source rect")
	_assert(bool(right_snapshot.get("h_flip", false)), "expected player east hFlip")
	_assert(int(right_snapshot.get("animation_elapsed_frames", -1)) == 8, "expected source turn-in-place finish frame count")

	_assert(MapRuntime.can_enter_cell(Vector2i(4, 2)), "expected second movement target cell to be enterable")
	_release_test_actions()
	Input.action_press("ui_right")
	player._physics_process(1.0 / 60.0)
	Input.action_release("ui_right")
	_assert(player.grid_position == Vector2i(3, 2), "expected second held same-direction frame to start movement")
	_assert(_array_value(player.last_input_source_trace).has("src/event_object_movement.c:SetSpriteDataForNormalStep"), "expected normal step source trace")
	_assert(_array_value(player.last_input_source_trace).has("src/event_object_movement.c:NpcTakeStep"), "expected source 16-frame normal-step trace")
	var walk_start_snapshot: Dictionary = player.get_sprite_snapshot()
	_assert(String(walk_start_snapshot.get("animation_state", "")) == "walking", "expected player normal step to start walking animation")
	_assert(_array_value(walk_start_snapshot.get("source_rect", [])) == [128, 0, 16, 32], "expected source east walk frame 8 after turn-in-place alternation")
	_assert(bool(walk_start_snapshot.get("h_flip", false)), "expected source east walk frame 8 hFlip")
	_assert(int(walk_start_snapshot.get("animation_phase_start_index", -1)) == 2, "expected first east step after turn to use second gait phase")
	_assert(int(walk_start_snapshot.get("animation_elapsed_frames", -1)) == 0, "expected source walk animation elapsed frame 0")
	_assert(int(walk_start_snapshot.get("animation_total_frames", -1)) == 16, "expected source normal step to expose 16 frames")
	player._apply_active_sprite_animation_frame(8)
	var walk_mid_snapshot: Dictionary = player.get_sprite_snapshot()
	_assert(_array_value(walk_mid_snapshot.get("source_rect", [])) == [32, 0, 16, 32], "expected source east walk frame 2 at normal-step frame 8")
	_assert(bool(walk_mid_snapshot.get("h_flip", false)), "expected source east walk frame 2 hFlip")
	_assert(int(walk_mid_snapshot.get("animation_elapsed_frames", -1)) == 8, "expected source walk animation elapsed frame 8")
	await get_tree().create_timer(0.35).timeout
	_assert(_moved_count == 1, "expected one completed tile movement")
	var walk_finished_snapshot: Dictionary = player.get_sprite_snapshot()
	_assert(String(walk_finished_snapshot.get("animation_state", "")) == "static", "expected player to return to static facing frame after normal step")
	_assert(_array_value(walk_finished_snapshot.get("source_rect", [])) == [32, 0, 16, 32], "expected player east static source rect after normal step")
	_assert(int(walk_finished_snapshot.get("animation_elapsed_frames", -1)) == 16, "expected source normal step finish frame count")
	_assert(int(walk_finished_snapshot.get("step_anim_cmd_index", -1)) == 3, "expected source step alternation command index after second gait phase")

	_release_test_actions()
	Input.action_press("ui_right")
	player._physics_process(1.0 / 60.0)
	Input.action_release("ui_right")
	_assert(player.grid_position == Vector2i(4, 2), "expected next same-direction input to start another movement")
	var second_walk_start_snapshot: Dictionary = player.get_sprite_snapshot()
	_assert(_array_value(second_walk_start_snapshot.get("source_rect", [])) == [112, 0, 16, 32], "expected next east step to alternate back to source frame 7")
	_assert(int(second_walk_start_snapshot.get("animation_phase_start_index", -1)) == 0, "expected next east step to use first gait phase")
	await get_tree().create_timer(0.35).timeout
	_assert(_moved_count == 2, "expected two completed tile movements")

	GameState.set_player_gender("FEMALE")
	var female_player = PLAYER_SCENE.instantiate()
	add_child(female_player)
	await get_tree().process_frame
	female_player.set_physics_process(false)
	female_player.facing_direction = Vector2i.DOWN
	female_player.set_grid_position(Vector2i(2, 2))
	var female_snapshot: Dictionary = female_player.get_sprite_snapshot()
	_assert(bool(female_snapshot.get("using_sprite", false)), "expected female player to use source object-event sprite")
	_assert(String(female_snapshot.get("graphics_id", "")) == "OBJ_EVENT_GFX_MAY_NORMAL", "expected female player May source graphics")
	_assert(_array_value(female_snapshot.get("source_rect", [])) == [0, 0, 16, 32], "expected female player south static source rect")
	_assert(_array_value(female_snapshot.get("dest_rect", [])) == [-8, -24, 16, 32], "expected female player source sprite bottom-of-tile dest rect")
	_assert(not _unsupported_has(female_snapshot, "player_avatar_walk_animation_not_runtime_driven"), "expected female normal walk animation to be runtime-supported")
	_assert(_unsupported_has(female_snapshot, "player_avatar_non_normal_state_graphics_not_runtime_driven"), "expected female player non-normal state unsupported note")
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
