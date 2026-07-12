extends SceneTree

const VisualProfileControllerScript := preload("res://scripts/visual_profile_controller.gd")
const MAX_FRAMES := 1800
const MAX_STEP_SAMPLE_FRAMES := 600
const NDS_VIEWPORT_HEIGHT := 192.0
const SOURCE_SPRITE_SIZE := 32.0
const SPRITE_SIZE_TOLERANCE := 1.0

var _step_samples: Array[Dictionary] = []
var _turn_samples: Array[Dictionary] = []
var _step_input_events: Dictionary = {}
var _turn_input_events: Dictionary = {}
var _main: Node
var _streamer: PlatinumWorldStreamer
var _failure_pending := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	if packed == null:
		_fail("Main scene could not be loaded.")
		return
	var main := packed.instantiate()
	_main = main
	root.add_child(main)

	var streamer: PlatinumWorldStreamer
	for frame in MAX_FRAMES:
		await process_frame
		streamer = get_first_node_in_group("platinum_world_streamer") as PlatinumWorldStreamer
		_streamer = streamer
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
	var visual_profile := main.get_node_or_null("VisualProfile") as VisualProfileControllerScript
	var world_environment := main.get_node_or_null("WorldEnvironment") as WorldEnvironment
	var sun := main.get_node_or_null("Sun") as DirectionalLight3D
	var ground_shadow: MeshInstance3D
	if player != null:
		ground_shadow = player.get_node_or_null("GroundShadow") as MeshInstance3D
	if (
		player == null
		or camera == null
		or visual_profile == null
		or world_environment == null
		or sun == null
		or ground_shadow == null
	):
		_fail("Player, camera, or visual profile scene dependencies were not created.")
		return
	player.step_advanced.connect(_record_step)
	player.turn_advanced.connect(_record_turn)
	if not player.is_using_local_sprite_sheet():
		_fail("Dawn walk/run sprite atlas was not loaded.")
		return
	if Engine.physics_ticks_per_second != 60:
		_fail("Grid movement requires a fixed 60 Hz physics cadence.")
		return
	if (
		PlatinumPlayerController.WALK_STEP_FRAMES != 16
		or PlatinumPlayerController.RUN_STEP_FRAMES != 8
		or PlatinumPlayerController.TURN_FRAMES != 6
	):
		_fail("Player timing does not match the 30-to-60 Hz Platinum mapping.")
		return
	if not player.global_position.is_equal_approx(
		PlatinumPlayerController.snap_to_grid_center(player.global_position)
	):
		_fail("Player did not spawn at the center of a 16-pixel map tile.")
		return
	var negative_grid_center := PlatinumPlayerController.snap_to_grid_center(Vector3(-0.1, 2.0, -1.0))
	if not negative_grid_center.is_equal_approx(Vector3(-0.5, 2.0, -0.5)):
		_fail("Negative coordinates did not snap with floor-based grid semantics.")
		return
	if camera.get_follow_target() != player:
		_fail("Camera is not following the player.")
		return
	if not _validate_cardinal_input_rules():
		_fail("Cardinal input history does not match the Platinum priority rules.")
		return
	var has_z_run_binding := false
	for event: InputEvent in InputMap.action_get_events("player_run"):
		if event is InputEventKey and (event as InputEventKey).physical_keycode == KEY_Z:
			has_z_run_binding = true
			break
	if not has_z_run_binding:
		_fail("The running action is not bound to the physical Z key.")
		return
	if not is_equal_approx(camera.rotation_degrees.x, -50.0) or not is_zero_approx(camera.rotation_degrees.y):
		_fail("Unexpected default camera rotation: %s" % camera.rotation_degrees)
		return
	if camera.projection != Camera3D.PROJECTION_ORTHOGONAL or not is_equal_approx(camera.size, 11.24):
		_fail("Camera did not start in the expected orthographic mode.")
		return
	var player_sprite := player.get_node("Sprite3D") as Sprite3D
	var projected_source_size := (
		SOURCE_SPRITE_SIZE * player_sprite.pixel_size * NDS_VIEWPORT_HEIGHT / camera.size
	)
	if absf(projected_source_size - SOURCE_SPRITE_SIZE) > SPRITE_SIZE_TOLERANCE:
		_fail(
			"The 32-pixel source sprite projects to an unexpected height: %.3f"
			% projected_source_size
		)
		return
	var camera_focus := player.global_position + Vector3.UP * camera.target_height
	if (
		not is_equal_approx(camera.get_active_follow_distance(), 16.0)
		or not is_equal_approx(camera.global_position.distance_to(camera_focus), 16.0)
	):
		_fail("Orthographic camera follow distance is incorrect.")
		return
	var initial_camera_transform := camera.global_transform
	var initial_camera_rotation := camera.rotation_degrees
	var initial_player_transform := player.global_transform
	var initial_player_facing := player.get_current_facing()
	var initial_stream_stats := streamer.get_stream_stats()
	var initial_focus_cell := streamer.get_focus_cell()
	var initial_sun_transform := sun.global_transform
	var initial_sprite_camera_position := (
		camera.global_basis.inverse()
		* (player_sprite.global_position - camera.global_position)
	)
	var initial_environment_rid := world_environment.environment.get_rid()
	var initial_shadow_mesh_rid := ground_shadow.mesh.get_rid()
	var initial_visual_state := visual_profile.get_visual_state()
	if (
		visual_profile.get_active_profile_name()
		!= VisualProfileControllerScript.CLASSIC_PROFILE
		or not bool(initial_visual_state.get("fog_enabled", false))
		or not is_equal_approx(float(initial_visual_state.get("fog_density", 0.0)), 0.0001)
		or bool(initial_visual_state.get("pixel_snap_enabled", true))
		or bool(initial_visual_state.get("player_shadow_enabled", true))
		or not is_equal_approx(
			float(initial_visual_state.get("player_sprite_pixel_size", 0.0)), 0.06
		)
		or not bool(initial_visual_state.get("sun_shadow_enabled", false))
		or not is_equal_approx(float(initial_visual_state.get("camera_far", 0.0)), 2500.0)
	):
		_fail("Classic visual profile did not reproduce the current baseline.")
		return

	var f2_event := InputEventKey.new()
	f2_event.keycode = KEY_F2
	f2_event.physical_keycode = KEY_F2
	f2_event.pressed = true
	visual_profile._unhandled_input(f2_event)
	var hd2d_visual_state := visual_profile.get_visual_state()
	if (
		visual_profile.get_active_profile_name()
		!= VisualProfileControllerScript.HD2D_PROFILE
		or not bool(hd2d_visual_state.get("fog_enabled", false))
		or not is_equal_approx(float(hd2d_visual_state.get("fog_density", 0.0)), 0.22)
		or not bool(hd2d_visual_state.get("pixel_snap_enabled", false))
		or not bool(hd2d_visual_state.get("player_shadow_enabled", false))
		or not is_equal_approx(
			float(hd2d_visual_state.get("player_sprite_pixel_size", 0.0)),
			11.24 / NDS_VIEWPORT_HEIGHT
		)
		or bool(hd2d_visual_state.get("sun_shadow_enabled", true))
		or not is_equal_approx(float(hd2d_visual_state.get("camera_far", 0.0)), 256.0)
	):
		_fail("F2 did not enable the expected HD-2D visual profile.")
		return
	if (
		not player.global_transform.is_equal_approx(initial_player_transform)
		or player.get_current_facing() != initial_player_facing
		or streamer.get_focus_cell() != initial_focus_cell
		or streamer.get_stream_stats() != initial_stream_stats
		or camera.projection != Camera3D.PROJECTION_ORTHOGONAL
		or not sun.global_transform.is_equal_approx(initial_sun_transform)
	):
		_fail("Visual profile switching changed gameplay or streaming state.")
		return
	var world_units_per_pixel := camera.get_world_units_per_pixel()
	if not is_equal_approx(world_units_per_pixel, 11.24 / NDS_VIEWPORT_HEIGHT):
		_fail("Orthographic pixel grid size is incorrect: %s" % world_units_per_pixel)
		return
	var projected_hd2d_sprite_size := (
		SOURCE_SPRITE_SIZE * player_sprite.pixel_size / world_units_per_pixel
	)
	var hd2d_sprite_camera_position := (
		camera.global_basis.inverse()
		* (player_sprite.global_position - camera.global_position)
	)
	if (
		not is_equal_approx(projected_hd2d_sprite_size, SOURCE_SPRITE_SIZE)
		or not hd2d_sprite_camera_position.is_equal_approx(initial_sprite_camera_position)
	):
		_fail(
			"HD-2D sprite did not remain native-sized and screen-stable: %.4f %s"
			% [projected_hd2d_sprite_size, hd2d_sprite_camera_position]
		)
		return
	var camera_basis := camera.global_basis.orthonormalized()
	var snap_delta := camera.global_position - camera.get_unsnapped_global_position()
	if (
		absf(snap_delta.dot(camera_basis.z)) > 0.0001
		or absf(snap_delta.dot(camera_basis.x)) > world_units_per_pixel * 0.5 + 0.00001
		or absf(snap_delta.dot(camera_basis.y)) > world_units_per_pixel * 0.5 + 0.00001
	):
		_fail("HD-2D camera pixel snap moved outside the screen plane bounds: %s" % snap_delta)
		return
	var snapped_right := camera.global_position.dot(camera_basis.x) / world_units_per_pixel
	var snapped_up := camera.global_position.dot(camera_basis.y) / world_units_per_pixel
	if (
		not is_equal_approx(snapped_right, roundf(snapped_right))
		or not is_equal_approx(snapped_up, roundf(snapped_up))
	):
		_fail("HD-2D camera did not land on the orthographic pixel grid.")
		return

	visual_profile._unhandled_input(f2_event)
	if (
		visual_profile.get_active_profile_name()
		!= VisualProfileControllerScript.CLASSIC_PROFILE
		or visual_profile.get_visual_state() != initial_visual_state
		or not camera.global_transform.is_equal_approx(initial_camera_transform)
		or world_environment.environment.get_rid() != initial_environment_rid
		or ground_shadow.mesh.get_rid() != initial_shadow_mesh_rid
	):
		_fail("F2 did not restore Classic without reallocating visual resources.")
		return
	print("VISUAL_PROFILE_ROUNDTRIP_OK ", JSON.stringify(hd2d_visual_state))

	var f1_event := InputEventKey.new()
	f1_event.keycode = KEY_F1
	f1_event.pressed = true
	camera._unhandled_input(f1_event)
	if camera.projection != Camera3D.PROJECTION_PERSPECTIVE or not is_equal_approx(camera.fov, 75.0):
		_fail("F1 did not switch the camera to perspective mode.")
		return
	if (
		not camera.rotation_degrees.is_equal_approx(initial_camera_rotation)
		or not is_equal_approx(camera.get_active_follow_distance(), 8.0)
		or not is_equal_approx(camera.global_position.distance_to(camera_focus), 8.0)
	):
		_fail("Perspective debug mode did not preserve the view direction at distance 8.")
		return
	camera._unhandled_input(f1_event)
	if camera.projection != Camera3D.PROJECTION_ORTHOGONAL or not is_equal_approx(camera.size, 11.24):
		_fail("F1 did not restore orthographic mode.")
		return
	if not camera.global_transform.is_equal_approx(initial_camera_transform):
		_fail("F1 did not restore the orthographic camera transform.")
		return
	var wheel_up := InputEventMouseButton.new()
	wheel_up.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel_up.pressed = true
	camera._unhandled_input(wheel_up)
	if not is_equal_approx(camera.rotation_degrees.x, -55.0):
		_fail("Wheel up did not increase the downward pitch: %s" % camera.rotation_degrees.x)
		return
	var wheel_down := InputEventMouseButton.new()
	wheel_down.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel_down.pressed = true
	camera._unhandled_input(wheel_down)
	if not is_equal_approx(camera.rotation_degrees.x, -50.0):
		_fail("Wheel down did not restore the default pitch: %s" % camera.rotation_degrees.x)
		return
	if not is_equal_approx(camera.global_position.distance_to(camera_focus), 16.0):
		_fail("Mouse wheel changed the camera follow distance.")
		return

	var movement_origin := player.global_position

	player.teleport_to_grid(movement_origin, PlatinumPlayerController.Facing.DOWN)
	_reset_motion_capture()
	_turn_input_events = {
		PlatinumPlayerController.TURN_FRAMES: {"release": [&"move_right"]},
	}
	Input.action_press("move_right")
	if not await _wait_for_turn_samples(PlatinumPlayerController.TURN_FRAMES):
		_fail("Stationary direction change did not complete its turn action.")
		return
	var turn_columns: Array[int] = [0, 1, 1, 2, 2, 2]
	for turn_index in PlatinumPlayerController.TURN_FRAMES:
		var turn_sample: Dictionary = _turn_samples[turn_index]
		if not (turn_sample.get("position", Vector3.ZERO) as Vector3).is_equal_approx(movement_origin):
			_fail("Turn action moved the player on frame %d." % (turn_index + 1))
			return
		var expected_turn_frame: int = (
			PlatinumPlayerController.Facing.RIGHT * PlatinumPlayerController.FRAME_COLUMNS
			+ turn_columns[turn_index]
		)
		if int(turn_sample.get("sprite_frame", -1)) != expected_turn_frame:
			_fail("Turn animation phase was incorrect on frame %d." % (turn_index + 1))
			return
	if player.is_turning() or player.is_stepping() or not _step_samples.is_empty():
		_fail("Stationary turn leaked into a movement step.")
		return

	player.teleport_to_grid(movement_origin, PlatinumPlayerController.Facing.DOWN)
	_reset_motion_capture()
	_step_input_events = {
		PlatinumPlayerController.WALK_STEP_FRAMES: {"release": [&"move_right"]},
	}
	Input.action_press("move_right")
	if not await _wait_for_turn_samples(PlatinumPlayerController.TURN_FRAMES):
		_fail("Held direction did not complete its stationary turn.")
		return
	if not await _wait_for_step_samples(PlatinumPlayerController.WALK_STEP_FRAMES):
		_fail("Held direction did not start walking after the turn boundary.")
		return
	if not player.global_position.is_equal_approx(movement_origin + Vector3.RIGHT):
		_fail("Held direction did not land one tile beyond the stationary turn.")
		return

	player.teleport_to_grid(movement_origin, PlatinumPlayerController.Facing.RIGHT)
	_reset_motion_capture()
	var walk_sample_count := PlatinumPlayerController.WALK_STEP_FRAMES * 2
	_step_input_events = {
		walk_sample_count: {"release": [&"move_right"]},
	}
	Input.action_press("move_right")
	if not await _wait_for_step_samples(walk_sample_count):
		_fail("Two source-paced walk steps did not complete.")
		return
	for step_update in range(1, walk_sample_count + 1):
		var walk_sample: Dictionary = _step_samples[step_update - 1]
		var expected_walk_position := movement_origin + Vector3.RIGHT * (
			PlatinumPlayerController.GRID_CELL_SIZE
			* float(step_update)
			/ float(PlatinumPlayerController.WALK_STEP_FRAMES)
		)
		if not (walk_sample.get("position", Vector3.ZERO) as Vector3).is_equal_approx(
			expected_walk_position
		):
			_fail("Walk update %d did not advance by 1/16 cell." % step_update)
			return
		if int(walk_sample.get("step_duration", 0)) != PlatinumPlayerController.WALK_STEP_FRAMES:
			_fail("Walk duration changed inside an atomic step.")
			return
		var walk_gait_frame := step_update % PlatinumPlayerController.GAIT_CYCLE_FRAMES
		var walk_column := floori(
			float(walk_gait_frame) / float(PlatinumPlayerController.GAIT_POSE_FRAMES)
		)
		var expected_walk_frame := (
			PlatinumPlayerController.Facing.RIGHT * PlatinumPlayerController.FRAME_COLUMNS
			+ walk_column
		)
		if int(walk_sample.get("sprite_frame", -1)) != expected_walk_frame:
			_fail("Walk animation left the 0,1,2,3 source phase on update %d." % step_update)
			return
	if player.is_stepping() or not player.global_position.is_equal_approx(
		movement_origin + Vector3.RIGHT * 2.0
	):
		_fail("Two walk steps did not land on the second tile center.")
		return

	player.teleport_to_grid(movement_origin, PlatinumPlayerController.Facing.RIGHT)
	_reset_motion_capture()
	var run_sample_count := PlatinumPlayerController.RUN_STEP_FRAMES * 4
	_step_input_events = {
		run_sample_count: {"release": [&"move_right", &"player_run"]},
	}
	Input.action_press("move_right")
	Input.action_press("player_run")
	if not await _wait_for_step_samples(run_sample_count):
		_fail("Four source-paced run steps did not complete.")
		return
	for step_update in range(1, run_sample_count + 1):
		var run_sample: Dictionary = _step_samples[step_update - 1]
		var expected_run_position := movement_origin + Vector3.RIGHT * (
			PlatinumPlayerController.GRID_CELL_SIZE
			* float(step_update)
			/ float(PlatinumPlayerController.RUN_STEP_FRAMES)
		)
		if not (run_sample.get("position", Vector3.ZERO) as Vector3).is_equal_approx(
			expected_run_position
		):
			_fail("Run update %d did not advance by 1/8 cell." % step_update)
			return
		if int(run_sample.get("step_duration", 0)) != PlatinumPlayerController.RUN_STEP_FRAMES:
			_fail("Run duration changed inside an atomic step.")
			return
		var run_gait_frame := step_update % PlatinumPlayerController.GAIT_CYCLE_FRAMES
		var run_column := PlatinumPlayerController.FRAMES_PER_ACTION + floori(
			float(run_gait_frame) / float(PlatinumPlayerController.GAIT_POSE_FRAMES)
		)
		var expected_run_frame := (
			PlatinumPlayerController.Facing.RIGHT * PlatinumPlayerController.FRAME_COLUMNS
			+ run_column
		)
		if int(run_sample.get("sprite_frame", -1)) != expected_run_frame:
			_fail("Run animation did not visit source columns 4,5,6,7 in order.")
			return
	if player.is_stepping() or not player.global_position.is_equal_approx(
		movement_origin + Vector3.RIGHT * 4.0
	):
		_fail("Four run steps did not land on the fourth tile center.")
		return

	player.teleport_to_grid(movement_origin, PlatinumPlayerController.Facing.RIGHT)
	_reset_motion_capture()
	_step_input_events = {
		1: {"release": [&"move_right"]},
	}
	Input.action_press("move_right")
	if not await _wait_for_step_samples(PlatinumPlayerController.WALK_STEP_FRAMES):
		_fail("Tapped walk input did not finish its atomic tile step.")
		return
	if not player.global_position.is_equal_approx(movement_origin + Vector3.RIGHT):
		_fail("Tapped walk input stopped between tile centers.")
		return

	player.teleport_to_grid(movement_origin, PlatinumPlayerController.Facing.RIGHT)
	_reset_motion_capture()
	var walk_to_run_sample_count := (
		PlatinumPlayerController.WALK_STEP_FRAMES
		+ PlatinumPlayerController.RUN_STEP_FRAMES
	)
	_step_input_events = {
		5: {"press": [&"player_run"]},
		walk_to_run_sample_count: {"release": [&"move_right", &"player_run"]},
	}
	Input.action_press("move_right")
	if not await _wait_for_step_samples(walk_to_run_sample_count):
		_fail("Walk-to-run boundary test did not complete.")
		return
	for sample_index in PlatinumPlayerController.WALK_STEP_FRAMES:
		if (
			int(_step_samples[sample_index].get("step_duration", 0))
			!= PlatinumPlayerController.WALK_STEP_FRAMES
		):
			_fail("Pressing Z mid-walk changed the current step duration.")
			return
	for sample_index in range(
		PlatinumPlayerController.WALK_STEP_FRAMES,
		walk_to_run_sample_count
	):
		if (
			int(_step_samples[sample_index].get("step_duration", 0))
			!= PlatinumPlayerController.RUN_STEP_FRAMES
		):
			_fail("Z was not sampled as running at the next tile boundary.")
			return
	if (
		int(
			_step_samples[PlatinumPlayerController.WALK_STEP_FRAMES].get(
				"sprite_frame", -1
			)
		)
		% PlatinumPlayerController.FRAME_COLUMNS
		!= PlatinumPlayerController.RUN_SECOND_IDLE_COLUMN
	):
		_fail("Walk-to-run transition did not preserve the neutral gait phase.")
		return

	player.teleport_to_grid(movement_origin, PlatinumPlayerController.Facing.RIGHT)
	_reset_motion_capture()
	var run_to_walk_sample_count := (
		PlatinumPlayerController.RUN_STEP_FRAMES
		+ PlatinumPlayerController.WALK_STEP_FRAMES
	)
	_step_input_events = {
		3: {"release": [&"player_run"]},
		run_to_walk_sample_count: {"release": [&"move_right"]},
	}
	Input.action_press("move_right")
	Input.action_press("player_run")
	if not await _wait_for_step_samples(run_to_walk_sample_count):
		_fail("Run-to-walk boundary test did not complete.")
		return
	for sample_index in PlatinumPlayerController.RUN_STEP_FRAMES:
		if (
			int(_step_samples[sample_index].get("step_duration", 0))
			!= PlatinumPlayerController.RUN_STEP_FRAMES
		):
			_fail("Releasing Z mid-run changed the current step duration.")
			return
	for sample_index in range(
		PlatinumPlayerController.RUN_STEP_FRAMES,
		run_to_walk_sample_count
	):
		if (
			int(_step_samples[sample_index].get("step_duration", 0))
			!= PlatinumPlayerController.WALK_STEP_FRAMES
		):
			_fail("Z release was not sampled as walking at the next tile boundary.")
			return
	if (
		int(
			_step_samples[PlatinumPlayerController.RUN_STEP_FRAMES].get(
				"sprite_frame", -1
			)
		)
		% PlatinumPlayerController.FRAME_COLUMNS
		!= PlatinumPlayerController.IDLE_COLUMN
	):
		_fail("Run-to-walk transition did not align to an idle gait phase.")
		return

	player.teleport_to_grid(movement_origin, PlatinumPlayerController.Facing.RIGHT)
	_reset_motion_capture()
	var direction_change_sample_count := PlatinumPlayerController.WALK_STEP_FRAMES * 2
	_step_input_events = {
		5: {"press": [&"move_up"], "release": [&"move_right"]},
		direction_change_sample_count: {"release": [&"move_up"]},
	}
	Input.action_press("move_right")
	if not await _wait_for_step_samples(direction_change_sample_count):
		_fail("Grid-boundary direction change did not complete.")
		return
	for sample_index in PlatinumPlayerController.WALK_STEP_FRAMES:
		var first_step_position := _step_samples[sample_index].get("position", Vector3.ZERO) as Vector3
		var expected_first_position := (
			movement_origin
			+ Vector3.RIGHT
			* float(sample_index + 1)
			/ float(PlatinumPlayerController.WALK_STEP_FRAMES)
		)
		if not first_step_position.is_equal_approx(expected_first_position):
			_fail("Direction changed before the current grid step ended.")
			return
	for sample_index in range(
		PlatinumPlayerController.WALK_STEP_FRAMES,
		direction_change_sample_count
	):
		var second_step_frame := (
			sample_index - PlatinumPlayerController.WALK_STEP_FRAMES + 1
		)
		var second_step_position := _step_samples[sample_index].get("position", Vector3.ZERO) as Vector3
		var expected_second_position := (
			movement_origin
			+ Vector3.RIGHT
			+ Vector3.FORWARD
			* float(second_step_frame)
			/ float(PlatinumPlayerController.WALK_STEP_FRAMES)
		)
		if not second_step_position.is_equal_approx(expected_second_position):
			_fail("New direction did not start at the next grid boundary.")
			return
	if not _turn_samples.is_empty():
		_fail("Continuous walking inserted an unnecessary stationary turn.")
		return

	player.teleport_to_grid(movement_origin, PlatinumPlayerController.Facing.DOWN)
	if player.is_stepping() or player.is_turning() or not player.global_position.is_equal_approx(movement_origin):
		_fail("Grid teleport retained stale motion state.")
		return
	print("PLAYER_GRID_MOVEMENT_OK ", JSON.stringify({
		"cell_size": PlatinumPlayerController.GRID_CELL_SIZE,
		"center_offset": PlatinumPlayerController.GRID_CENTER_OFFSET,
		"walk_frames_60hz": PlatinumPlayerController.WALK_STEP_FRAMES,
		"run_frames_60hz": PlatinumPlayerController.RUN_STEP_FRAMES,
		"turn_frames_60hz": PlatinumPlayerController.TURN_FRAMES,
		"projected_source_sprite_pixels": projected_source_size,
		"walk_columns": [0, 1, 2, 3],
		"run_columns": [4, 5, 6, 7],
	}))

	player.teleport_to_grid(Vector3(
		4.0 * PlatinumWorldStreamer.CHUNK_SIZE - 0.5,
		movement_origin.y,
		28.0 * PlatinumWorldStreamer.CHUNK_SIZE - 0.5
	))
	for frame in 30:
		await process_frame
	if streamer.get_focus_cell() != Vector2i(3, 27):
		_fail("Focus moved before crossing the current chunk boundary: %s" % streamer.get_focus_cell())
		return

	player.teleport_to_grid(Vector3(
		9.0 * PlatinumWorldStreamer.CHUNK_SIZE + 0.5,
		movement_origin.y,
		16.0 * PlatinumWorldStreamer.CHUNK_SIZE + 14.5
	))
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
	if _failure_pending:
		return
	_failure_pending = true
	_release_all_test_inputs()
	push_error(message)
	if is_instance_valid(_streamer):
		_streamer.shutdown()
	if is_instance_valid(_main):
		_main.queue_free()
	call_deferred("_finish_failure")


func _finish_failure() -> void:
	for cleanup_frame in 10:
		await process_frame
	quit(1)


func _record_step(
	step_frame: int,
	step_duration: int,
	world_position: Vector3,
	sprite_frame: int
) -> void:
	_step_samples.append({
		"step_frame": step_frame,
		"step_duration": step_duration,
		"position": world_position,
		"sprite_frame": sprite_frame,
	})
	_apply_input_event(_step_input_events, _step_samples.size())


func _record_turn(
	turn_frame: int,
	turn_duration: int,
	world_position: Vector3,
	sprite_frame: int
) -> void:
	_turn_samples.append({
		"turn_frame": turn_frame,
		"turn_duration": turn_duration,
		"position": world_position,
		"sprite_frame": sprite_frame,
	})
	_apply_input_event(_turn_input_events, _turn_samples.size())


func _apply_input_event(events: Dictionary, sample_count: int) -> void:
	if not events.has(sample_count):
		return
	var event := events[sample_count] as Dictionary
	for action: StringName in event.get("release", []):
		Input.action_release(action)
	for action: StringName in event.get("press", []):
		Input.action_press(action)
	events.erase(sample_count)


func _reset_motion_capture() -> void:
	_release_all_test_inputs()
	_step_samples.clear()
	_turn_samples.clear()
	_step_input_events.clear()
	_turn_input_events.clear()


func _release_all_test_inputs() -> void:
	for action: StringName in [
		&"move_up",
		&"move_down",
		&"move_left",
		&"move_right",
		&"player_run",
	]:
		Input.action_release(action)


func _validate_cardinal_input_rules() -> bool:
	if (
		PlatinumPlayerController.select_cardinal_direction(
			Vector2(1.0, -1.0), Vector2.ZERO, Vector2.ZERO
		)
		!= Vector2.UP
	):
		return false
	if (
		PlatinumPlayerController.select_cardinal_direction(
			Vector2(1.0, -1.0), Vector2(1.0, -1.0), Vector2.UP
		)
		!= Vector2.UP
	):
		return false
	if (
		PlatinumPlayerController.select_cardinal_direction(
			Vector2(1.0, -1.0), Vector2(1.0, 0.0), Vector2.RIGHT
		)
		!= Vector2.UP
	):
		return false
	if (
		PlatinumPlayerController.select_cardinal_direction(
			Vector2(1.0, -1.0), Vector2(0.0, -1.0), Vector2.UP
		)
		!= Vector2.RIGHT
	):
		return false
	return true


func _wait_for_step_samples(expected_count: int) -> bool:
	for frame in MAX_STEP_SAMPLE_FRAMES:
		if _step_samples.size() >= expected_count:
			return true
		await process_frame
	return _step_samples.size() >= expected_count


func _wait_for_turn_samples(expected_count: int) -> bool:
	for frame in MAX_STEP_SAMPLE_FRAMES:
		if _turn_samples.size() >= expected_count:
			return true
		await process_frame
	return _turn_samples.size() >= expected_count


func _finish_success() -> void:
	_release_all_test_inputs()
	quit(0)
