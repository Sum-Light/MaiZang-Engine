extends SceneTree

const MAX_FRAMES := 1800
const NDS_SCREEN_SIZE := Vector2i(256, 192)
const DEFAULT_CAPTURE_PATH := "res://captures/world_player.png"
const DEFAULT_CAPTURE_CELL := Vector2i(3, 27)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = NDS_SCREEN_SIZE
	var capture_matrix_id := 0
	var capture_area_data_id := -1
	var capture_cell := DEFAULT_CAPTURE_CELL
	var capture_tile := PlatinumWorldStreamer.DEFAULT_START_TILE
	var capture_offset := Vector2.ZERO
	var capture_path := DEFAULT_CAPTURE_PATH
	var force_perspective := false
	var expected_player_position: Variant = null
	var destination_changed := false
	var cell_overridden := false
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--matrix="):
			var value := argument.trim_prefix("--matrix=").strip_edges()
			if not value.is_valid_int():
				_fail("Invalid --matrix value: %s" % value)
				return
			capture_matrix_id = int(value)
			destination_changed = true
		elif argument.begins_with("--area="):
			var value := argument.trim_prefix("--area=").strip_edges()
			if not value.is_valid_int():
				_fail("Invalid --area value: %s" % value)
				return
			capture_area_data_id = int(value)
			destination_changed = true
		elif argument.begins_with("--cell="):
			var value: Variant = _parse_vector2i(argument.trim_prefix("--cell="), "--cell")
			if value == null:
				return
			capture_cell = value as Vector2i
			cell_overridden = true
		elif argument.begins_with("--tile="):
			var value: Variant = _parse_vector2i(argument.trim_prefix("--tile="), "--tile")
			if value == null:
				return
			capture_tile = value as Vector2i
		elif argument.begins_with("--offset="):
			var value: Variant = _parse_vector2(argument.trim_prefix("--offset="), "--offset")
			if value == null:
				return
			capture_offset = value as Vector2
		elif argument.begins_with("--output="):
			capture_path = argument.trim_prefix("--output=")
		elif argument.begins_with("--expect-player-position="):
			expected_player_position = _parse_vector3(
				argument.trim_prefix("--expect-player-position="), "--expect-player-position"
			)
			if expected_player_position == null:
				return
		elif argument == "--perspective":
			force_perspective = true
	if destination_changed and not cell_overridden:
		capture_cell = PlatinumWorldStreamer.USE_DESTINATION_DEFAULT_CELL

	var packed := load("res://scenes/main.tscn") as PackedScene
	if packed == null:
		_fail("Main scene could not be loaded.")
		return
	var main := packed.instantiate()
	var player := main.get_node("Player") as PlatinumPlayerController
	var camera := main.get_node("Camera") as PlatinumFollowCamera
	var streamer := main.get_node("WorldStreamer") as PlatinumWorldStreamer
	if player == null or camera == null or streamer == null:
		_fail("Main scene is missing its player, camera, or world streamer.")
		return
	if not streamer.configure_debug_destination(
		capture_matrix_id, capture_area_data_id, capture_cell, capture_tile
	):
		_fail("Capture destination could not be configured.")
		return
	root.add_child(main)
	if not capture_offset.is_zero_approx():
		var resolved_position: Variant = streamer.resolve_offset_grid_world_position(
			player.global_position, capture_offset
		)
		if resolved_position == null:
			_fail("Capture offset resolves to an unoccupied matrix cell.")
			return
		player.teleport_to_grid(resolved_position as Vector3)
	if (
		expected_player_position != null
		and not player.global_position.is_equal_approx(expected_player_position as Vector3)
	):
		_fail(
			"Capture player position is incorrect: %s != %s"
			% [player.global_position, expected_player_position]
		)
		return
	if force_perspective:
		camera.toggle_projection()

	var stats: Dictionary
	for frame in MAX_FRAMES:
		await process_frame
		stats = streamer.get_stream_stats()
		var player_cell := Vector2i(
			floori(player.global_position.x / PlatinumWorldStreamer.CHUNK_SIZE),
			floori(player.global_position.z / PlatinumWorldStreamer.CHUNK_SIZE)
		)
		if (
			streamer.get_focus_cell() == player_cell
			and streamer.is_chunk_loaded(player_cell)
			and int(stats.loading_assets) == 0
		):
			break

	if not streamer.is_chunk_loaded(streamer.get_focus_cell()):
		_fail("World did not become ready for capture.")
		return
	if int(stats.get("failed_assets", 0)) != 0:
		_fail("World assets failed to load for capture: %s" % JSON.stringify(stats))
		return

	for frame in 10:
		await process_frame
	await RenderingServer.frame_post_draw

	var capture_directory := ProjectSettings.globalize_path(capture_path.get_base_dir())
	DirAccess.make_dir_recursive_absolute(capture_directory)
	var image := root.get_texture().get_image()
	if image.is_empty():
		_fail("Rendered viewport image is empty.")
		return
	if image.get_size() != NDS_SCREEN_SIZE:
		_fail("Unexpected capture size: %s" % image.get_size())
		return
	var save_error := image.save_png(ProjectSettings.globalize_path(capture_path))
	if save_error != OK:
		_fail("Could not save capture (error %d)." % save_error)
		return

	var forward := -camera.global_basis.z
	print("WORLD_CAPTURE_OK ", ProjectSettings.globalize_path(capture_path))
	print("WORLD_CAPTURE_STATS ", JSON.stringify(stats))
	print("WORLD_CAPTURE_CAMERA_FORWARD ", forward)
	print("WORLD_CAPTURE_PROJECTION ", camera.get_projection_name())
	print("WORLD_CAPTURE_CAMERA_DISTANCE ", camera.get_active_follow_distance())
	print("WORLD_CAPTURE_PLAYER_POSITION ", player.global_position)
	print("WORLD_CAPTURE_PLAYER_FRAME ", player.get_current_sprite_frame())
	streamer.shutdown()
	main.queue_free()
	for cleanup_frame in 10:
		await process_frame
	call_deferred("_finish_success")


func _fail(message: String) -> void:
	push_error(message)
	quit(1)


func _parse_vector2i(raw_value: String, option_name: String) -> Variant:
	var components := raw_value.split(",", false)
	if components.size() != 2:
		_fail("%s expects x,y: %s" % [option_name, raw_value])
		return null
	var x_value := String(components[0]).strip_edges()
	var y_value := String(components[1]).strip_edges()
	if not x_value.is_valid_int() or not y_value.is_valid_int():
		_fail("%s expects integer x,y: %s" % [option_name, raw_value])
		return null
	return Vector2i(int(x_value), int(y_value))


func _parse_vector2(raw_value: String, option_name: String) -> Variant:
	var components := raw_value.split(",", false)
	if components.size() != 2:
		_fail("%s expects x,y: %s" % [option_name, raw_value])
		return null
	var x_value := String(components[0]).strip_edges()
	var y_value := String(components[1]).strip_edges()
	if not x_value.is_valid_float() or not y_value.is_valid_float():
		_fail("%s expects numeric x,y: %s" % [option_name, raw_value])
		return null
	return Vector2(float(x_value), float(y_value))


func _parse_vector3(raw_value: String, option_name: String) -> Variant:
	var components := raw_value.split(",", false)
	if components.size() != 3:
		_fail("%s expects x,y,z: %s" % [option_name, raw_value])
		return null
	var x_value := String(components[0]).strip_edges()
	var y_value := String(components[1]).strip_edges()
	var z_value := String(components[2]).strip_edges()
	if not x_value.is_valid_float() or not y_value.is_valid_float() or not z_value.is_valid_float():
		_fail("%s expects numeric x,y,z: %s" % [option_name, raw_value])
		return null
	return Vector3(float(x_value), float(y_value), float(z_value))


func _finish_success() -> void:
	quit(0)
