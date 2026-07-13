extends SceneTree

const MAX_PHYSICS_FRAMES := 120

class TestCollisionProvider:
	extends Node

	var blocked := false
	var ok_value: Variant = true
	var blocked_value: Variant = false
	var disposition := "allow"
	var action := "none"
	var preflight_height := 9.0
	var invalid_target := false
	var invalid_height := false
	var omit_landing_target := false
	var omit_next_context := false
	var next_context_value: Variant = {
		"locomotion": "walk",
		"bridge_layer": "elevated",
	}
	var replacement_owner: Node = null
	var replacement_provider: Node = null
	var replace_during_step_query := false
	var replace_during_height_query := false
	var mutate_received_context := false
	var height_samples := 0
	var received_contexts: Array[Dictionary] = []

	func resolve_player_step(origin: Vector3, direction: Vector2i, context: Dictionary) -> Dictionary:
		received_contexts.append(context.duplicate(true))
		if mutate_received_context:
			mutate_received_context = false
			context["bridge_layer"] = "ground"
		if blocked:
			return {
				"ok": true,
				"blocked": true,
				"disposition": "blocked",
				"action": "none",
				"reason": "tile_collision",
				"target": origin,
				"next_context": {"locomotion": "walk", "bridge_layer": "elevated"},
			}
		var target := (
			Vector3(NAN, origin.y, origin.z)
			if invalid_target
			else origin + Vector3(direction.x, preflight_height, direction.y)
		)
		var result := {
			"ok": ok_value,
			"blocked": blocked_value,
			"disposition": disposition,
			"action": action,
			"reason": "",
			"target": target,
			"landing_target": target,
			"next_context": next_context_value,
		}
		if omit_landing_target:
			result.erase("landing_target")
		if omit_next_context:
			result.erase("next_context")
		if replace_during_step_query:
			replace_during_step_query = false
			replacement_owner.call("set_collision_provider", replacement_provider)
		return result

	func resolve_player_height(world_position: Vector3, _reference_height: float) -> float:
		height_samples += 1
		if replace_during_height_query:
			replace_during_height_query = false
			replacement_owner.call("set_collision_provider", replacement_provider)
		if invalid_height:
			return NAN
		return world_position.x - 0.5


class SelfQueueFreeCollisionProvider:
	extends Node

	var queue_free_during_step_query := false
	var queue_free_during_height_query := false

	func resolve_player_step(origin: Vector3, direction: Vector2i, _context: Dictionary) -> Dictionary:
		var target := origin + Vector3(direction.x, 0.0, direction.y)
		var result := {
			"ok": true,
			"blocked": false,
			"disposition": "allow",
			"action": "none",
			"target": target,
			"landing_target": target,
			"next_context": {"locomotion": "walk", "bridge_layer": "ground"},
		}
		if queue_free_during_step_query:
			queue_free()
		return result

	func resolve_player_height(world_position: Vector3, _reference_height: float) -> float:
		if queue_free_during_height_query:
			queue_free()
		return world_position.y


class StepOnlyCollisionProvider:
	extends Node

	func resolve_player_step(origin: Vector3, direction: Vector2i, _context: Dictionary) -> Dictionary:
		return {
			"ok": true,
			"blocked": false,
			"disposition": "allow",
			"action": "none",
			"target": origin + Vector3(direction.x, 0.0, direction.y),
			"next_context": {"locomotion": "walk", "bridge_layer": "ground"},
		}


var _samples: Array[Vector3] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var player := PlatinumPlayerController.new()
	player.name = "Player"
	var sprite := Sprite3D.new()
	sprite.name = "Sprite3D"
	player.add_child(sprite)
	root.add_child(player)
	player.step_advanced.connect(_record_step)

	var origin := Vector3(0.5, 0.0, 0.5)
	player.teleport_to_grid(origin, PlatinumPlayerController.Facing.RIGHT)
	Input.action_press("move_right")
	for frame in 3:
		await physics_frame
	Input.action_release("move_right")
	if player.is_stepping() or not player.global_position.is_equal_approx(origin):
		_fail("Player moved without a collision provider.")
		return

	var step_only_provider := StepOnlyCollisionProvider.new()
	root.add_child(step_only_provider)
	player.set_collision_provider(step_only_provider)
	player.teleport_to_grid(origin, PlatinumPlayerController.Facing.RIGHT)
	Input.action_press("move_right")
	for frame in 3:
		await physics_frame
	Input.action_release("move_right")
	if player.is_stepping() or not player.global_position.is_equal_approx(origin):
		_fail("Player moved with an incomplete collision-provider contract.")
		return
	step_only_provider.queue_free()

	var provider := TestCollisionProvider.new()
	root.add_child(provider)
	player.set_collision_provider(provider)
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
	provider.disposition = "special"
	provider.action = "jump"
	player.teleport_to_grid(origin, PlatinumPlayerController.Facing.RIGHT)
	Input.action_press("move_right")
	for frame in 3:
		await physics_frame
	Input.action_release("move_right")
	if player.is_stepping() or not player.global_position.is_equal_approx(origin):
		_fail("Player treated a special collision action as a normal step.")
		return

	provider.disposition = "allow"
	player.teleport_to_grid(origin, PlatinumPlayerController.Facing.RIGHT)
	Input.action_press("move_right")
	for frame in 3:
		await physics_frame
	Input.action_release("move_right")
	if player.is_stepping() or not player.global_position.is_equal_approx(origin):
		_fail("Player consumed a named action through the normal allow path.")
		return

	provider.action = "none"
	provider.invalid_target = true
	player.teleport_to_grid(origin, PlatinumPlayerController.Facing.RIGHT)
	Input.action_press("move_right")
	for frame in 3:
		await physics_frame
	Input.action_release("move_right")
	if player.is_stepping() or not player.global_position.is_equal_approx(origin):
		_fail("Player accepted a non-finite collision-provider target.")
		return

	provider.invalid_target = false
	provider.invalid_height = true
	player.teleport_to_grid(origin, PlatinumPlayerController.Facing.RIGHT)
	Input.action_press("move_right")
	for frame in 2:
		await physics_frame
	Input.action_release("move_right")
	if player.is_stepping() or not player.global_position.is_equal_approx(origin):
		_fail("Player accepted a non-finite collision-provider height sample.")
		return

	provider.invalid_height = false
	provider.ok_value = "false"
	player.teleport_to_grid(origin, PlatinumPlayerController.Facing.RIGHT)
	Input.action_press("move_right")
	for frame in 3:
		await physics_frame
	Input.action_release("move_right")
	if player.is_stepping() or not player.global_position.is_equal_approx(origin):
		_fail("Player coerced a malformed provider ok value.")
		return

	provider.ok_value = true
	provider.blocked_value = 0
	player.teleport_to_grid(origin, PlatinumPlayerController.Facing.RIGHT)
	Input.action_press("move_right")
	for frame in 3:
		await physics_frame
	Input.action_release("move_right")
	if player.is_stepping() or not player.global_position.is_equal_approx(origin):
		_fail("Player coerced a malformed provider blocked value.")
		return

	provider.blocked_value = false
	provider.omit_landing_target = true
	player.teleport_to_grid(origin, PlatinumPlayerController.Facing.RIGHT)
	Input.action_press("move_right")
	for frame in 3:
		await physics_frame
	Input.action_release("move_right")
	if player.is_stepping() or not player.global_position.is_equal_approx(origin):
		_fail("Player accepted a provider result without landing_target.")
		return

	provider.omit_landing_target = false
	provider.omit_next_context = true
	player.teleport_to_grid(origin, PlatinumPlayerController.Facing.RIGHT)
	Input.action_press("move_right")
	for frame in 3:
		await physics_frame
	Input.action_release("move_right")
	if player.is_stepping() or not player.global_position.is_equal_approx(origin):
		_fail("Player accepted a provider result without next_context.")
		return

	provider.omit_next_context = false
	provider.next_context_value = "invalid"
	player.teleport_to_grid(origin, PlatinumPlayerController.Facing.RIGHT)
	Input.action_press("move_right")
	for frame in 3:
		await physics_frame
	Input.action_release("move_right")
	if player.is_stepping() or not player.global_position.is_equal_approx(origin):
		_fail("Player accepted a non-dictionary next_context.")
		return

	provider.next_context_value = {"locomotion": 1, "bridge_layer": "elevated"}
	player.teleport_to_grid(origin, PlatinumPlayerController.Facing.RIGHT)
	Input.action_press("move_right")
	for frame in 3:
		await physics_frame
	Input.action_release("move_right")
	if player.is_stepping() or not player.global_position.is_equal_approx(origin):
		_fail("Player accepted malformed next_context fields.")
		return

	provider.next_context_value = {"locomotion": "walk", "bridge_layer": "elevated"}
	provider.ok_value = false
	provider.mutate_received_context = true
	player.teleport_to_grid(
		origin,
		PlatinumPlayerController.Facing.RIGHT,
		{"locomotion": "walk", "bridge_layer": "elevated"}
	)
	Input.action_press("move_right")
	await physics_frame
	Input.action_release("move_right")
	if (
		player.is_stepping()
		or not player.global_position.is_equal_approx(origin)
		or String(player.get_collision_context().bridge_layer) != "elevated"
	):
		_fail("A rejected provider query mutated the active collision context.")
		return

	provider.ok_value = true
	provider.height_samples = 0
	_samples.clear()
	player.teleport_to_grid(
		origin,
		PlatinumPlayerController.Facing.RIGHT,
		{"locomotion": "walk", "bridge_layer": "elevated"}
	)
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
		or String(provider.received_contexts[-1].bridge_layer) != "elevated"
	):
		_fail("An explicit teleport context did not carry across the accepted step.")
		return
	var completed_slope_samples := _samples.size()
	var completed_height_queries := provider.height_samples
	var completed_target := player.global_position

	var replacement_provider := TestCollisionProvider.new()
	root.add_child(replacement_provider)
	_samples.clear()
	player.teleport_to_grid(origin, PlatinumPlayerController.Facing.RIGHT)
	Input.action_press("move_right")
	await physics_frame
	if not player.is_stepping():
		Input.action_release("move_right")
		_fail("Provider-replacement regression did not enter a step.")
		return
	player.set_collision_provider(replacement_provider)
	Input.action_release("move_right")
	if player.is_stepping() or not player.global_position.is_equal_approx(origin):
		_fail("Player did not roll back when its collision provider was replaced.")
		return

	provider.replacement_owner = player
	provider.replacement_provider = replacement_provider
	player.set_collision_provider(provider)
	provider.replace_during_step_query = true
	player.teleport_to_grid(origin, PlatinumPlayerController.Facing.RIGHT)
	Input.action_press("move_right")
	await physics_frame
	Input.action_release("move_right")
	if player.is_stepping() or not player.global_position.is_equal_approx(origin):
		_fail("Player accepted a step from a provider replaced during preflight.")
		return

	player.set_collision_provider(provider)
	provider.replace_during_height_query = true
	player.teleport_to_grid(origin, PlatinumPlayerController.Facing.RIGHT)
	Input.action_press("move_right")
	await physics_frame
	Input.action_release("move_right")
	if (
		provider.replace_during_height_query
		or player.is_stepping()
		or not player.global_position.is_equal_approx(origin)
	):
		_fail("Player moved after its provider was replaced during height sampling.")
		return

	var self_free_step_provider := SelfQueueFreeCollisionProvider.new()
	self_free_step_provider.queue_free_during_step_query = true
	root.add_child(self_free_step_provider)
	player.set_collision_provider(self_free_step_provider)
	player.teleport_to_grid(origin, PlatinumPlayerController.Facing.RIGHT)
	Input.action_press("move_right")
	await physics_frame
	Input.action_release("move_right")
	await physics_frame
	if player.is_stepping() or not player.global_position.is_equal_approx(origin):
		_fail("Player accepted a step from a provider freed during preflight.")
		return

	var self_free_height_provider := SelfQueueFreeCollisionProvider.new()
	self_free_height_provider.queue_free_during_height_query = true
	root.add_child(self_free_height_provider)
	player.set_collision_provider(self_free_height_provider)
	player.teleport_to_grid(origin, PlatinumPlayerController.Facing.RIGHT)
	Input.action_press("move_right")
	await physics_frame
	Input.action_release("move_right")
	await physics_frame
	if player.is_stepping() or not player.global_position.is_equal_approx(origin):
		_fail("Player moved after its provider was freed during height sampling.")
		return

	player.set_collision_provider(replacement_provider)
	player.teleport_to_grid(origin, PlatinumPlayerController.Facing.RIGHT)
	Input.action_press("move_right")
	await physics_frame
	if not player.is_stepping():
		Input.action_release("move_right")
		_fail("Provider-loss regression did not enter a step before provider removal.")
		return
	replacement_provider.free()
	await physics_frame
	Input.action_release("move_right")
	if player.is_stepping() or not player.global_position.is_equal_approx(origin):
		_fail("Player did not roll back an active step after losing its collision provider.")
		return

	print("PLAYER_COLLISION_OK ", JSON.stringify({
		"blocked_origin": origin,
		"slope_samples": completed_slope_samples,
		"height_queries": completed_height_queries,
		"target": completed_target,
		"provider_replacement_rolled_back": true,
		"reentrant_provider_replacement_rolled_back": true,
		"reentrant_provider_free_rolled_back": true,
		"provider_loss_rolled_back": true,
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
