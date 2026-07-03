extends Node

const TRANSITION_FRAME_RATE := 60.0
const TRANSITION_FADE_SECONDS := 0.18

var event_manager: Node = null
var map_runtime: Node = null
var game_state: Node = null
var player: Node = null
var overlay: ColorRect = null
var label: Label = null
var playback_token := 0
var playback_tween: Tween = null


func configure(
	new_event_manager: Node,
	new_map_runtime: Node,
	new_game_state: Node,
	new_player: Node,
	new_overlay: ColorRect,
	new_label: Label
) -> void:
	event_manager = new_event_manager
	map_runtime = new_map_runtime
	game_state = new_game_state
	player = new_player
	overlay = new_overlay
	label = new_label


func play(sequence: Dictionary) -> void:
	playback_token += 1
	if playback_tween != null and playback_tween.is_running():
		playback_tween.kill()

	_play_sequence(sequence, playback_token)


func is_playing() -> bool:
	return overlay != null and overlay.visible


func _play_sequence(sequence: Dictionary, token: int) -> void:
	if player != null and player.has_method("set_input_locked"):
		player.set_input_locked(true)

	if overlay != null:
		overlay.visible = true
		overlay.modulate.a = 0.0
	if label != null:
		label.text = _sequence_label(sequence)

	var steps = sequence.get("steps", [])
	if typeof(steps) == TYPE_ARRAY:
		for step in steps:
			if token != playback_token:
				return
			if typeof(step) == TYPE_DICTIONARY:
				await _play_step(sequence, step, token)

	if token == playback_token:
		_finish()


func _play_step(sequence: Dictionary, step: Dictionary, token: int) -> void:
	if label != null:
		label.text = _step_label(sequence, step)

	match String(step.get("op", "")):
		"lock_controls", "freeze_object_events", "play_se":
			return
		"door_open", "door_close":
			await _wait_step(step, token)
		"player_step":
			await _animate_player_step(step, token, false)
		"hide_player":
			if player != null:
				player.visible = bool(step.get("visible", true))
		"fade_out":
			await _fade_overlay(1.0, TRANSITION_FADE_SECONDS, token)
		"load_map":
			_apply_deferred_transition(sequence)
			if player != null:
				player.visible = true
		"fade_in":
			var exit_task = sequence.get("exit_task", {})
			if player != null and typeof(exit_task) == TYPE_DICTIONARY and String(exit_task.get("task", "")) == "Task_ExitDoor":
				player.visible = false
			await _fade_overlay(0.0, TRANSITION_FADE_SECONDS, token)
		"exit_task_select":
			if player != null and String(step.get("selected", "")) == "Task_ExitDoor":
				player.visible = false
		"conditional_exit_door_player_step":
			if bool(step.get("condition_result", false)):
				if player != null:
					player.visible = true
				await _animate_player_step(step, token, true)
		"unlock_controls":
			return


func _apply_deferred_transition(sequence: Dictionary) -> void:
	if event_manager == null or not event_manager.has_method("apply_deferred_transition"):
		return

	var sequence_id := int(sequence.get("id", 0))
	if sequence_id <= 0:
		return

	event_manager.apply_deferred_transition(sequence_id)


func _wait_step(step: Dictionary, token: int) -> void:
	var seconds := _step_seconds(step)
	if seconds <= 0.0:
		return
	await get_tree().create_timer(seconds).timeout
	if token != playback_token:
		return


func _animate_player_step(step: Dictionary, token: int, update_runtime_position: bool) -> void:
	if player == null:
		return

	var from_position := _step_vector(step, "from", _current_player_position())
	var to_position := _step_vector(step, "to", from_position)
	var seconds := _step_seconds(step)
	if player.has_method("set_grid_position"):
		player.set_grid_position(from_position)
	if seconds <= 0.0:
		if player.has_method("set_grid_position"):
			player.set_grid_position(to_position)
		if update_runtime_position and map_runtime != null and map_runtime.has_method("set_player_grid_position"):
			map_runtime.set_player_grid_position(to_position, game_state)
		return

	if player.has_method("animate_grid_position"):
		await player.animate_grid_position(to_position, seconds)
	elif player.has_method("set_grid_position"):
		player.set_grid_position(to_position)

	if token != playback_token:
		return
	if update_runtime_position and map_runtime != null and map_runtime.has_method("set_player_grid_position"):
		map_runtime.set_player_grid_position(to_position, game_state)


func _fade_overlay(target_alpha: float, duration: float, token: int) -> void:
	if overlay == null:
		return

	overlay.visible = true
	if playback_tween != null and playback_tween.is_running():
		playback_tween.kill()
	playback_tween = create_tween()
	playback_tween.tween_property(overlay, "modulate:a", target_alpha, duration)
	await playback_tween.finished
	if token != playback_token:
		return


func _finish() -> void:
	if overlay != null:
		overlay.visible = false
	if label != null:
		label.text = ""
	if player != null and player.has_method("set_input_locked"):
		player.set_input_locked(false)


func _current_player_position() -> Vector2i:
	if game_state != null:
		return game_state.player_grid_position
	return Vector2i.ZERO


func _step_seconds(step: Dictionary) -> float:
	var frames := int(step.get("duration_frames", 0))
	if frames <= 0:
		return 0.0
	return float(frames) / TRANSITION_FRAME_RATE


func _step_vector(step: Dictionary, key: String, default_value: Vector2i) -> Vector2i:
	var value = step.get(key, default_value)
	if typeof(value) == TYPE_VECTOR2I:
		return value
	if typeof(value) == TYPE_ARRAY and value.size() >= 2:
		return Vector2i(int(value[0]), int(value[1]))
	if typeof(value) == TYPE_DICTIONARY:
		return Vector2i(int(value.get("x", default_value.x)), int(value.get("y", default_value.y)))
	return default_value


func _sequence_label(sequence: Dictionary) -> String:
	return "%s -> %s | %s" % [
		String(sequence.get("source_map", "")),
		String(sequence.get("destination_map", "")),
		String(sequence.get("presentation", "normal")),
	]


func _step_label(sequence: Dictionary, step: Dictionary) -> String:
	return "%s | %s" % [
		_sequence_label(sequence),
		String(step.get("op", "")),
	]
