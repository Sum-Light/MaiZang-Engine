extends SceneTree

const MAX_PHYSICS_FRAMES := 120

class TestCollisionProvider:
	extends Node

	var blocked := false
	var height_samples := 0
	var received_contexts: Array[Dictionary] = []

	func resolve_player_step(origin: Vector3, direction: Vector2i, context: Dictionary) -> Dictionary:
		received_contexts.append(context.duplicate(true))
		if blocked:
			return {
				"ok": true,
				"blocked": true,
				"reason": "tile_collision",
				"target": origin,
				"next_context": {"locomotion": "walk", "bridge_layer": "elevated"},
			}
		return {
			"ok": true,
			"blocked": false,
			"reason": "",
			"target": origin + Vector3(direction.x, 1.0, direction.y),
			"next_context": {"locomotion": "walk", "bridge_layer": "elevated"},
		}

	func resolve_player_height(world_position: Vector3, _reference_height: float) -> float:
		height_samples += 1
		return world_position.x - 0.5


var _samples: Array[Vector3] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var provider := TestCollisionProvider.new()
	root.add_child(provider)
	var player := PlatinumPlayerController.new()
	player.name = "Player"
	var sprite := Sprite3D.new()
	sprite.name = "Sprite3D"
	player.add_child(sprite)
	root.add_child(player)
	player.set_collision_provider(provider)
	player.step_advanced.connect(_record_step)

	var origin := Vector3(0.5, 0.0, 0.5)
	player.teleport_to_grid(origin, PlatinumPlayerController.Facing.RIGHT)
	provider.blocked = true
	Input.action_press("move_right")
	for frame in 3:
		await physics_frame
	Input.action_release("move_right")
	if player.is_stepping() or not player.global_position.is_equal_approx(origin):
		_fail("Player entered a statically blocked grid step.")
		return
	if String(player.get_collision_context().bridge_layer) != "unknown":
		_fail("A blocked step committed its pending collision context.")
		return

	provider.blocked = false
	provider.height_samples = 0
	_samples.clear()
	player.teleport_to_grid(origin, PlatinumPlayerController.Facing.RIGHT)
	Input.action_press("move_right")
	for frame in MAX_PHYSICS_FRAMES:
		await physics_frame
		if _samples.size() >= PlatinumPlayerController.WALK_STEP_FRAMES:
			Input.action_release("move_right")
			break
	Input.action_release("move_right")
	if _samples.size() != PlatinumPlayerController.WALK_STEP_FRAMES:
		_fail("Slope step did not complete in 16 physics ticks.")
		return
	for index in _samples.size():
		var expected_progress := float(index + 1) / float(PlatinumPlayerController.WALK_STEP_FRAMES)
		var expected := origin + Vector3(expected_progress, expected_progress, 0.0)
		if not _samples[index].is_equal_approx(expected):
			_fail("Slope sample %d did not follow the collision height: %s" % [index, _samples[index]])
			return
	if provider.height_samples < PlatinumPlayerController.WALK_STEP_FRAMES:
		_fail("Player did not resample terrain height during the slope step.")
		return
	if not player.global_position.is_equal_approx(Vector3(1.5, 1.0, 0.5)):
		_fail("Player did not land on the target BDHC height.")
		return
	if (
		String(player.get_collision_context().bridge_layer) != "elevated"
		or provider.received_contexts.is_empty()
		or String(provider.received_contexts[-1].bridge_layer) != "unknown"
	):
		_fail("An accepted step did not carry collision context across the grid boundary.")
		return

	print("PLAYER_COLLISION_OK ", JSON.stringify({
		"blocked_origin": origin,
		"slope_samples": _samples.size(),
		"height_queries": provider.height_samples,
		"target": player.global_position,
	}))
	player.queue_free()
	provider.queue_free()
	quit(0)


func _record_step(
	_step_frame: int,
	_step_duration: int,
	world_position: Vector3,
	_sprite_frame: int
) -> void:
	_samples.append(world_position)


func _fail(message: String) -> void:
	Input.action_release("move_right")
	push_error(message)
	quit(1)
