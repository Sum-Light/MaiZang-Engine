extends SceneTree

const MAX_FRAMES := 1800


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	if packed == null:
		_fail("Main scene could not be loaded.")
		return
	var main := packed.instantiate()
	root.add_child(main)

	var streamer: PlatinumWorldStreamer
	for frame in MAX_FRAMES:
		await process_frame
		streamer = get_first_node_in_group("platinum_world_streamer") as PlatinumWorldStreamer
		if streamer == null:
			continue
		var stats := streamer.get_stream_stats()
		if int(stats.loaded_chunks) >= 1 and int(stats.loading_assets) == 0:
			if int(stats.manifest_cells) != 468:
				_fail("Unexpected manifest cell count: %s" % stats.manifest_cells)
				return
			if int(stats.failed_assets) != 0:
				_fail("Asset loads failed: %s" % stats.failed_assets)
				return
			if int(stats.shared_materials) == 0:
				_fail("No DSPRE materials were discovered.")
				return
			print("WORLD_STREAMER_INITIAL_OK ", JSON.stringify(stats))
			break

	if streamer == null or not streamer.is_chunk_loaded(Vector2i(3, 27)):
		_fail("Initial world chunks did not become ready within %d frames." % MAX_FRAMES)
		return

	var player := main.get_node("Player") as PlatinumPlayerController
	var camera := main.get_node("Camera") as PlatinumFollowCamera
	if player == null or camera == null:
		_fail("Player or follow camera was not created.")
		return
	if not player.is_using_local_sprite_sheet():
		_fail("Dawn walk/run sprite atlas was not loaded.")
		return
	if camera.get_follow_target() != player:
		_fail("Camera is not following the player.")
		return
	if PlatinumPlayerController.cardinalize(Vector2(1.0, -1.0)) != Vector2(0.0, -1.0):
		_fail("Diagonal input was not reduced to one cardinal direction.")
		return
	var has_z_run_binding := false
	for event: InputEvent in InputMap.action_get_events("player_run"):
		if event is InputEventKey and (event as InputEventKey).physical_keycode == KEY_Z:
			has_z_run_binding = true
			break
	if not has_z_run_binding:
		_fail("The running action is not bound to the physical Z key.")
		return
	if not is_equal_approx(camera.rotation_degrees.x, -60.0) or not is_zero_approx(camera.rotation_degrees.y):
		_fail("Unexpected default camera rotation: %s" % camera.rotation_degrees)
		return
	if camera.projection != Camera3D.PROJECTION_ORTHOGONAL or not is_equal_approx(camera.size, 12.3):
		_fail("Camera did not start in the expected orthographic mode.")
		return
	var camera_focus := player.global_position + Vector3.UP * camera.target_height
	if not is_equal_approx(camera.global_position.distance_to(camera_focus), camera.follow_distance):
		_fail("Camera follow distance is incorrect.")
		return
	var initial_camera_transform := camera.global_transform
	var f1_event := InputEventKey.new()
	f1_event.keycode = KEY_F1
	f1_event.pressed = true
	camera._unhandled_input(f1_event)
	if camera.projection != Camera3D.PROJECTION_PERSPECTIVE or not is_equal_approx(camera.fov, 75.0):
		_fail("F1 did not switch the camera to perspective mode.")
		return
	if not camera.global_transform.is_equal_approx(initial_camera_transform):
		_fail("Projection switching changed the camera transform.")
		return
	camera._unhandled_input(f1_event)
	if camera.projection != Camera3D.PROJECTION_ORTHOGONAL or not is_equal_approx(camera.size, 12.3):
		_fail("F1 did not restore orthographic mode.")
		return
	var wheel_up := InputEventMouseButton.new()
	wheel_up.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel_up.pressed = true
	camera._unhandled_input(wheel_up)
	if not is_equal_approx(camera.rotation_degrees.x, -65.0):
		_fail("Wheel up did not increase the downward pitch: %s" % camera.rotation_degrees.x)
		return
	var wheel_down := InputEventMouseButton.new()
	wheel_down.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel_down.pressed = true
	camera._unhandled_input(wheel_down)
	if not is_equal_approx(camera.rotation_degrees.x, -60.0):
		_fail("Wheel down did not restore the default pitch: %s" % camera.rotation_degrees.x)
		return
	if not is_equal_approx(camera.global_position.distance_to(camera_focus), camera.follow_distance):
		_fail("Mouse wheel changed the camera follow distance.")
		return

	var movement_origin := player.global_position
	var walk_delta := Vector3.ZERO
	var direction_cases := [
		{"action": "move_down", "direction": Vector3.BACK, "facing": PlatinumPlayerController.Facing.DOWN},
		{"action": "move_up", "direction": Vector3.FORWARD, "facing": PlatinumPlayerController.Facing.UP},
		{"action": "move_left", "direction": Vector3.LEFT, "facing": PlatinumPlayerController.Facing.LEFT},
		{"action": "move_right", "direction": Vector3.RIGHT, "facing": PlatinumPlayerController.Facing.RIGHT},
	]
	for direction_case: Dictionary in direction_cases:
		player.global_position = movement_origin
		player.velocity = Vector3.ZERO
		var action := StringName(direction_case.action)
		var expected_direction := direction_case.direction as Vector3
		Input.action_press(action)
		for frame in 6:
			await physics_frame
		var movement_delta := player.global_position - movement_origin
		Input.action_release(action)
		var forward_distance := movement_delta.dot(expected_direction)
		var off_axis_delta := movement_delta - expected_direction * forward_distance
		if forward_distance <= 0.0 or off_axis_delta.length() > 0.001:
			_fail("Movement was not constrained to %s: %s" % [action, movement_delta])
			return
		if player.get_current_facing() != int(direction_case.facing):
			_fail("Movement did not select the expected facing for %s." % action)
			return
		if action == &"move_right":
			walk_delta = movement_delta

	player.global_position = movement_origin
	player.velocity = Vector3.ZERO
	Input.action_press("move_right")
	Input.action_press("player_run")
	for frame in 6:
		await physics_frame
	var run_delta := player.global_position - movement_origin
	if not player.is_running() or player.get_current_sprite_frame() % 8 < 4:
		_fail("Z running did not select the running animation frames.")
		return
	Input.action_release("player_run")
	Input.action_release("move_right")
	if run_delta.x <= walk_delta.x * 1.5 or not is_zero_approx(run_delta.z):
		_fail("Running was not faster than walking: walk=%s run=%s" % [walk_delta, run_delta])
		return

	player.global_position = Vector3(
		4.0 * PlatinumWorldStreamer.CHUNK_SIZE - 1.0,
		movement_origin.y,
		28.0 * PlatinumWorldStreamer.CHUNK_SIZE - 1.0
	)
	for frame in 30:
		await process_frame
	if streamer.get_focus_cell() != Vector2i(3, 27):
		_fail("Focus moved before crossing the current chunk boundary: %s" % streamer.get_focus_cell())
		return

	player.global_position = Vector3(
		9.0 * PlatinumWorldStreamer.CHUNK_SIZE,
		movement_origin.y,
		16.0 * PlatinumWorldStreamer.CHUNK_SIZE + 14.0
	)
	for frame in MAX_FRAMES:
		await process_frame
		var stats := streamer.get_stream_stats()
		if (
			streamer.is_chunk_loaded(Vector2i(9, 16))
			and not streamer.is_chunk_loaded(Vector2i(3, 27))
			and int(stats.loading_assets) == 0
		):
			if int(stats.failed_assets) != 0:
				_fail("Asset loads failed after streaming: %s" % stats.failed_assets)
				return
			if int(stats.loaded_assets) > int(stats.retained_assets):
				_fail("Asset cache retained resources outside the unload radius: %s" % JSON.stringify(stats))
				return
			print("WORLD_STREAMER_MOVE_OK ", JSON.stringify(stats))
			streamer.shutdown()
			main.queue_free()
			for cleanup_frame in 10:
				await process_frame
			call_deferred("_finish_success")
			return

	_fail("World streamer did not load the destination and unload the origin within %d frames." % MAX_FRAMES)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)


func _finish_success() -> void:
	quit(0)
