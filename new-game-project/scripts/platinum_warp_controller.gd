class_name PlatinumWarpController
extends Node

signal transition_started(request: Dictionary)
signal transition_failed(message: String)
signal arrival_suppression_changed(active: bool)

const WorldTransitionRequest := preload("res://scripts/world_transition_request.gd")
const MOVEMENT_ACTIONS: Array[StringName] = [
	&"move_left",
	&"move_right",
	&"move_up",
	&"move_down",
	&"player_run",
]

@export var player_path: NodePath
@export var streamer_path: NodePath
@export_range(0.0, 2.0, 0.01) var fade_duration := 0.12

var _player: Node
var _streamer: Node
var _busy := false
var _arrival_suppression := false
var _arrival_world_tile := Vector2i.ZERO
var _reload_committed := false
var _last_error := ""
var _fade_layer: CanvasLayer
var _fade_rect: ColorRect


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if _player == null and not player_path.is_empty():
		_player = get_node_or_null(player_path)
	if _streamer == null and not streamer_path.is_empty():
		_streamer = get_node_or_null(streamer_path)
	_connect_player()
	_ensure_fade_overlay()
	call_deferred("_discover_arrival")


func _exit_tree() -> void:
	if not _reload_committed:
		_set_player_input_enabled(true)


func configure(player: Node, streamer: Node) -> bool:
	if is_inside_tree():
		return false
	_player = player
	_streamer = streamer
	return _player != null and _streamer != null


func is_busy() -> bool:
	return _busy


func is_arrival_suppressed() -> bool:
	return _arrival_suppression


func get_last_error() -> String:
	return _last_error


func begin_arrival_suppression(request: Dictionary) -> bool:
	if _busy:
		return false
	var normalized := WorldTransitionRequest.normalize(request)
	if not bool(normalized.ok):
		_last_error = String(normalized.error)
		return false
	_busy = true
	_arrival_suppression = true
	var normalized_request := normalized.request as Dictionary
	var arrival_cell := normalized_request.cell as Vector2i
	var arrival_tile := normalized_request.tile as Vector2i
	_arrival_world_tile = arrival_cell * WorldTransitionRequest.MAP_TILE_SIZE + arrival_tile
	arrival_suppression_changed.emit(true)
	_set_player_input_enabled(false)
	_set_fade_alpha(1.0)
	call_deferred("_finish_arrival", normalized_request.duplicate(true))
	return true


func _connect_player() -> void:
	if _player == null:
		return
	if _player.has_signal("special_action_requested"):
		var special_callback := Callable(self, "_on_special_action_requested")
		if not _player.is_connected("special_action_requested", special_callback):
			_player.connect("special_action_requested", special_callback)
	if _player.has_signal("step_advanced"):
		var step_callback := Callable(self, "_on_player_step_advanced")
		if not _player.is_connected("step_advanced", step_callback):
			_player.connect("step_advanced", step_callback)


func _on_special_action_requested(
	origin: Vector3,
	direction: Vector2i,
	special_result: Dictionary
) -> void:
	if _busy or _streamer == null:
		return
	if _arrival_suppression:
		if Vector2i(floori(origin.x), floori(origin.z)) == _arrival_world_tile:
			return
		_clear_arrival_suppression()
	if not _streamer.has_method("resolve_warp_transition_request"):
		return
	var resolution_value: Variant = _streamer.call(
		"resolve_warp_transition_request",
		origin,
		direction,
		special_result.duplicate(true)
	)
	if typeof(resolution_value) != TYPE_DICTIONARY:
		return
	var resolution := resolution_value as Dictionary
	var normalized := WorldTransitionRequest.normalize(resolution)
	if not bool(normalized.ok):
		return
	_busy = true
	_last_error = ""
	_set_player_input_enabled(false)
	var request := (normalized.request as Dictionary).duplicate(true)
	transition_started.emit(request.duplicate(true))
	call_deferred("_execute_transition", request)


func _execute_transition(request: Dictionary) -> void:
	if not is_inside_tree() or not is_instance_valid(_streamer):
		_recover("World transition dependencies left the scene before reload.")
		return
	await _play_door_animation(request, &"departure")
	await _fade_to(1.0)
	if not is_inside_tree() or not is_instance_valid(_streamer):
		_recover("World transition dependencies left the scene before handoff.")
		return
	if not _streamer.has_method("queue_world_transition_request"):
		_recover("World transition handoff is unavailable.")
		return
	var queue_value: Variant = _streamer.call("queue_world_transition_request", request)
	if typeof(queue_value) != TYPE_DICTIONARY:
		_recover("World transition handoff returned invalid data.")
		return
	var queue_result := queue_value as Dictionary
	var ok_value: Variant = queue_result.get("ok", null)
	var token_value: Variant = queue_result.get("token", null)
	if typeof(ok_value) != TYPE_BOOL or not ok_value or not token_value is StringName:
		_recover(String(queue_result.get("error", "World transition handoff failed.")))
		return
	var token := token_value as StringName
	if token == StringName():
		_recover("World transition handoff returned no token.")
		return
	var reload_error := _reload_current_scene()
	if reload_error == OK:
		_reload_committed = true
		return
	if is_instance_valid(_streamer) and _streamer.has_method("cancel_world_transition_request"):
		_streamer.call("cancel_world_transition_request", token)
	_recover("Scene reload failed (error %d)." % reload_error)


func _discover_arrival() -> void:
	if _busy or not is_instance_valid(_streamer):
		return
	if not _streamer.has_method("get_world_transition_arrival_request"):
		return
	var arrival_value: Variant = _streamer.call("get_world_transition_arrival_request")
	if typeof(arrival_value) != TYPE_DICTIONARY or (arrival_value as Dictionary).is_empty():
		return
	begin_arrival_suppression(arrival_value as Dictionary)


func _finish_arrival(request: Dictionary) -> void:
	if not is_inside_tree():
		return
	await _fade_to(0.0)
	await _play_door_animation(request, &"arrival")
	while is_inside_tree() and _has_held_movement_input():
		await get_tree().process_frame
	if not is_inside_tree():
		return
	_busy = false
	_set_player_input_enabled(true)


func _on_player_step_advanced(
	step_frame: int,
	step_duration: int,
	world_position: Vector3,
	_sprite_frame: int
) -> void:
	if (
		_arrival_suppression
		and step_frame >= step_duration
		and Vector2i(floori(world_position.x), floori(world_position.z)) != _arrival_world_tile
	):
		_clear_arrival_suppression()


func _clear_arrival_suppression() -> void:
	if not _arrival_suppression:
		return
	_arrival_suppression = false
	arrival_suppression_changed.emit(false)


func _play_door_animation(request: Dictionary, phase: StringName) -> void:
	if int(request.get("door_model_id", -1)) < 0:
		return
	if not is_instance_valid(_streamer) or not _streamer.has_method("play_warp_door_animation"):
		return
	await _streamer.call("play_warp_door_animation", request.duplicate(true), phase)


func _recover(message: String) -> void:
	_last_error = message
	_reload_committed = false
	await _fade_to(0.0)
	_busy = false
	_set_player_input_enabled(true)
	transition_failed.emit(message)


func _reload_current_scene() -> Error:
	if get_tree().current_scene == null:
		return ERR_UNCONFIGURED
	return get_tree().reload_current_scene()


func _set_player_input_enabled(enabled: bool) -> void:
	if is_instance_valid(_player) and _player.has_method("set_input_enabled"):
		_player.call("set_input_enabled", enabled)


func _has_held_movement_input() -> bool:
	for action: StringName in MOVEMENT_ACTIONS:
		if Input.is_action_pressed(action):
			return true
	return false


func _ensure_fade_overlay() -> void:
	if is_instance_valid(_fade_rect):
		return
	_fade_layer = CanvasLayer.new()
	_fade_layer.name = "WarpFadeLayer"
	_fade_layer.layer = 1000
	add_child(_fade_layer)
	_fade_rect = ColorRect.new()
	_fade_rect.name = "WarpFade"
	_fade_layer.add_child(_fade_rect)
	_fade_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_rect.color = Color(0.0, 0.0, 0.0, 0.0)


func _set_fade_alpha(alpha: float) -> void:
	_ensure_fade_overlay()
	var color := _fade_rect.color
	color.a = clampf(alpha, 0.0, 1.0)
	_fade_rect.color = color


func _fade_to(alpha: float) -> void:
	_ensure_fade_overlay()
	var target := clampf(alpha, 0.0, 1.0)
	if fade_duration <= 0.0 or not is_inside_tree():
		_set_fade_alpha(target)
		return
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(_fade_rect, "color:a", target, fade_duration)
	await tween.finished
