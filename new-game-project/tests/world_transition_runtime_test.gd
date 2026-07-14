extends SceneTree

const WorldTransitionRequest := preload("res://scripts/world_transition_request.gd")
const DebugDestinationRequest := preload("res://scripts/debug_destination_request.gd")
const PlayerController := preload("res://scripts/player_controller.gd")
const WarpController := preload("res://scripts/platinum_warp_controller.gd")


class TransitionCollisionProvider:
	extends Node

	var blocked_value: Variant = true

	func resolve_player_step(origin: Vector3, direction: Vector2i, _context: Dictionary) -> Dictionary:
		return {
			"ok": true,
			"blocked": blocked_value,
			"disposition": "special",
			"action": "transition",
			"reason": "special_behavior",
			"target": origin,
			"landing_target": null,
			"forced_direction": null,
			"attributes": 0x0003,
			"behavior": 0x0003,
			"height_delta": 0.0,
			"next_context": {"locomotion": "walk", "bridge_layer": "ground"},
		}

	func resolve_player_height(world_position: Vector3, _reference_height: float) -> float:
		return world_position.y


class FakePlayer:
	extends Node

	signal special_action_requested(origin: Vector3, direction: Vector2i, special_result: Dictionary)
	signal step_advanced(step_frame: int, step_duration: int, world_position: Vector3, sprite_frame: int)

	var input_enabled := true

	func set_input_enabled(enabled: bool) -> void:
		input_enabled = enabled


class FakeStreamer:
	extends Node
	const TransitionRequest := preload("res://scripts/world_transition_request.gd")

	var resolution: Dictionary = {}
	var arrival_request: Dictionary = {}
	var resolve_calls := 0
	var queue_calls := 0
	var cancel_calls := 0
	var door_phases: Array[StringName] = []

	func resolve_warp_transition_request(
		_origin: Vector3,
		_direction: Vector2i,
		_special_result: Dictionary
	) -> Dictionary:
		resolve_calls += 1
		return resolution.duplicate(true)

	func queue_world_transition_request(request: Dictionary) -> Dictionary:
		queue_calls += 1
		return TransitionRequest.queue(get_tree(), request)

	func cancel_world_transition_request(token: StringName) -> bool:
		cancel_calls += 1
		return TransitionRequest.cancel(get_tree(), token)

	func get_world_transition_arrival_request() -> Dictionary:
		return arrival_request.duplicate(true)

	func play_warp_door_animation(_request: Dictionary, phase: StringName) -> bool:
		door_phases.append(phase)
		return false


var _special_count := 0
var _special_origin := Vector3.ZERO
var _special_direction := Vector2i.ZERO
var _special_result: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var request := _valid_request()
	root.set_meta(DebugDestinationRequest.META_KEY, {"sentinel": true})
	var queue_result := WorldTransitionRequest.queue(self, request)
	if not bool(queue_result.ok) or not WorldTransitionRequest.has_pending(self):
		_fail("A valid world transition could not be queued.")
		return
	if not root.has_meta(DebugDestinationRequest.META_KEY):
		_fail("World transition metadata collided with the debug destination request.")
		return
	var duplicate_result := WorldTransitionRequest.queue(self, request)
	if bool(duplicate_result.ok):
		_fail("A second world transition replaced an existing pending request.")
		return
	if WorldTransitionRequest.cancel(self, &"wrong_token"):
		_fail("A mismatched token canceled the pending world transition.")
		return
	var take_result := WorldTransitionRequest.take(self)
	var taken_request := take_result.get("request", {}) as Dictionary
	if (
		not bool(take_result.ok)
		or not bool(take_result.pending)
		or taken_request != request
		or WorldTransitionRequest.has_pending(self)
	):
		_fail("The world transition was not consumed exactly once.")
		return
	root.remove_meta(DebugDestinationRequest.META_KEY)

	var malformed := request.duplicate(true)
	malformed["door_model_id"] = null
	if bool(WorldTransitionRequest.normalize(malformed).ok):
		_fail("A world transition accepted an ambiguous door model id.")
		return
	root.set_meta(WorldTransitionRequest.META_KEY, {"schema_version": 1})
	var malformed_take := WorldTransitionRequest.take(self)
	if bool(malformed_take.ok) or WorldTransitionRequest.has_pending(self):
		_fail("Malformed pending metadata was not rejected and consumed.")
		return

	if not await _test_player_special_action():
		return
	if not await _test_warp_controller(request):
		return
	print("WORLD_TRANSITION_RUNTIME_OK ", JSON.stringify({
		"metadata_isolated": true,
		"special_signal_strict": true,
		"failed_reload_canceled": true,
		"arrival_cleared_on_departure": true,
	}))
	quit(0)


func _test_player_special_action() -> bool:
	var player := PlayerController.new()
	var sprite := Sprite3D.new()
	sprite.name = "Sprite3D"
	player.add_child(sprite)
	root.add_child(player)
	var provider := TransitionCollisionProvider.new()
	root.add_child(provider)
	player.set_collision_provider(provider)
	player.special_action_requested.connect(_record_special)
	var origin := Vector3(0.5, 0.0, 0.5)
	player.teleport_to_grid(origin, PlayerController.Facing.RIGHT)
	Input.action_press(&"move_right")
	for frame in 3:
		await physics_frame
	Input.action_release(&"move_right")
	await physics_frame
	if (
		_special_count != 1
		or _special_origin != origin
		or _special_direction != Vector2i.RIGHT
		or String(_special_result.get("action", "")) != "transition"
		or player.is_stepping()
		or player.global_position != origin
	):
		_fail("The player did not emit one strict, stationary transition request.")
		return false

	provider.blocked_value = "true"
	Input.action_press(&"move_right")
	for frame in 2:
		await physics_frame
	Input.action_release(&"move_right")
	await physics_frame
	if _special_count != 1:
		_fail("The player emitted a transition for malformed collision data.")
		return false

	provider.blocked_value = true
	player.set_input_enabled(false)
	Input.action_press(&"move_right")
	for frame in 2:
		await physics_frame
	Input.action_release(&"move_right")
	if _special_count != 1 or player.global_position != origin or player.is_input_enabled():
		_fail("The player input lock did not stop transition polling.")
		return false
	player.set_input_enabled(true)
	if not player.is_input_enabled():
		_fail("The player input lock could not be released.")
		return false

	player.queue_free()
	provider.queue_free()
	await process_frame
	return true


func _test_warp_controller(request: Dictionary) -> bool:
	var player := FakePlayer.new()
	var streamer := FakeStreamer.new()
	streamer.resolution = request.merged({"ok": true})
	root.add_child(player)
	root.add_child(streamer)
	var controller := WarpController.new()
	controller.fade_duration = 0.0
	if not controller.configure(player, streamer):
		_fail("The Warp controller rejected valid runtime dependencies.")
		return false
	root.add_child(controller)
	await process_frame

	player.special_action_requested.emit(
		Vector3(2.5, 0.0, 3.5),
		Vector2i.UP,
		{"action": "transition"}
	)
	if not controller.is_busy() or player.input_enabled:
		_fail("The Warp controller did not lock input before its deferred handoff.")
		return false
	for frame in 5:
		await process_frame
		if not controller.is_busy():
			break
	if (
		controller.is_busy()
		or not player.input_enabled
		or streamer.queue_calls != 1
		or streamer.cancel_calls != 1
		or WorldTransitionRequest.has_pending(self)
		or streamer.door_phases != [&"departure"]
	):
		_fail("A failed scene reload did not cancel the handoff and restore input.")
		return false

	streamer.resolution = {"ok": false, "error": "special return", "field": "warp"}
	player.special_action_requested.emit(Vector3.ZERO, Vector2i.DOWN, {})
	if controller.is_busy() or not player.input_enabled or streamer.queue_calls != 1:
		_fail("An unresolved Warp entered the transition lifecycle.")
		return false

	Input.action_press(&"move_right")
	if not controller.begin_arrival_suppression(request):
		Input.action_release(&"move_right")
		_fail("A normalized arrival could not start suppression.")
		return false
	await process_frame
	if not controller.is_busy() or not controller.is_arrival_suppressed() or player.input_enabled:
		Input.action_release(&"move_right")
		_fail("Arrival suppression released a held input prematurely.")
		return false
	Input.action_release(&"move_right")
	for frame in 3:
		await process_frame
	if controller.is_busy() or not player.input_enabled or not controller.is_arrival_suppressed():
		_fail("Arrival input lock and tile suppression did not separate correctly.")
		return false
	var resolve_calls_before_suppressed_request := streamer.resolve_calls
	var arrival_cell := request.cell as Vector2i
	var arrival_tile := request.tile as Vector2i
	var arrival_world_tile := arrival_cell * WorldTransitionRequest.MAP_TILE_SIZE + arrival_tile
	player.special_action_requested.emit(
		Vector3(arrival_world_tile.x + 0.5, 0.0, arrival_world_tile.y + 0.5),
		Vector2i.DOWN,
		{"action": "transition"}
	)
	if streamer.resolve_calls != resolve_calls_before_suppressed_request:
		_fail("The arrival Warp was resolved again before the player left its tile.")
		return false
	player.step_advanced.emit(
		16,
		16,
		Vector3(arrival_world_tile.x + 1.5, 0.0, arrival_world_tile.y + 0.5),
		0
	)
	if controller.is_arrival_suppressed() or streamer.door_phases != [&"departure", &"arrival"]:
		_fail("Arrival suppression did not clear after a completed departure step.")
		return false

	controller.queue_free()
	player.queue_free()
	streamer.queue_free()
	await process_frame
	return true


func _valid_request() -> Dictionary:
	return {
		"matrix": 49,
		"area": 61,
		"cell": Vector2i(1, 1),
		"tile": Vector2i(7, 9),
		"facing": PlayerController.Facing.DOWN,
		"source_cell": Vector2i(3, 27),
		"source_tile": Vector2i(16, 15),
		"source_header_id": 12,
		"source_warp_id": 1,
		"destination_header_id": 88,
		"destination_warp_id": 2,
		"transition_kind": &"warp",
		"door_model_id": 41,
	}


func _record_special(origin: Vector3, direction: Vector2i, result: Dictionary) -> void:
	_special_count += 1
	_special_origin = origin
	_special_direction = direction
	_special_result = result.duplicate(true)


func _fail(message: String) -> void:
	for action: StringName in [&"move_left", &"move_right", &"move_up", &"move_down", &"player_run"]:
		Input.action_release(action)
	push_error(message)
	quit(1)
