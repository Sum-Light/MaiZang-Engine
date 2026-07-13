extends SceneTree

const MAIN_SCENE_PATH := "res://scenes/main.tscn"
const PANEL_PATH := NodePath("DebugDestinationPanel")
const MAX_FRAMES := 1800
const SETTLE_FRAMES := 12
const CLEANUP_FRAMES := 10
const MOVEMENT_BLOCK_FRAMES := 30
const CAPTURE_SETTLE_FRAMES := 3
const NDS_SCREEN_SIZE := Vector2i(256, 192)
const TEST_MATRIX_ID := 49
const TEST_AREA_DATA_ID := 61
const TEST_CELL := Vector2i(1, 1)
const TEST_TILE := Vector2i(31, 31)
const TEST_POSITION := Vector3(63.5, 0.5, 63.5)
const DebugDestinationRequest := preload("res://scripts/debug_destination_request.gd")

var _current_streamer: PlatinumWorldStreamer
var _panel: Node
var _failure_pending := false
var _capture_path := ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_capture_path = _capture_path_from_arguments()
	if _failure_pending:
		return
	var change_error := change_scene_to_file(MAIN_SCENE_PATH)
	if change_error != OK:
		_fail("Main scene could not be started (error %d)." % change_error)
		return

	var initial_scene: Node = await _wait_for_replacement_scene(0)
	if initial_scene == null:
		_fail("Main scene did not become current within %d frames." % MAX_FRAMES)
		return
	_current_streamer = await _wait_for_streamer(initial_scene, 0, -1, null)
	if _current_streamer == null:
		_fail("Default matrix did not finish its initial load within %d frames." % MAX_FRAMES)
		return
	var player := initial_scene.get_node_or_null("Player") as PlatinumPlayerController
	_panel = initial_scene.get_node_or_null(PANEL_PATH)
	if player == null or not _validate_panel_contract(_panel):
		return

	await _send_f2()
	if not _panel_is_open() or not paused:
		_fail("F2 did not open and pause the runtime debug destination panel.")
		return
	if not _field_owns_focus(_panel, NodePath("%MatrixSpin")):
		_fail("Opening the runtime debug panel did not focus the matrix input.")
		return

	var movement_origin := player.global_position
	Input.action_press(&"move_right")
	for frame in MOVEMENT_BLOCK_FRAMES:
		await process_frame
	Input.action_release(&"move_right")
	if not player.global_position.is_equal_approx(movement_origin):
		_fail("Player movement was not blocked while the runtime debug panel was open.")
		return

	await _send_f2()
	if _panel_is_open() or paused:
		_fail("F2 did not close and unpause the runtime debug destination panel.")
		return
	await _send_f2()
	if not _panel_is_open() or not paused:
		_fail("F2 did not reopen the runtime debug destination panel.")
		return
	if not _field_owns_focus(_panel, NodePath("%MatrixSpin")):
		_fail("Reopening the runtime debug panel did not restore matrix input focus.")
		return

	var initial_scene_id := initial_scene.get_instance_id()
	_panel.call(
		"set_destination_fields",
		TEST_MATRIX_ID,
		-1,
		false,
		TEST_CELL,
		TEST_TILE
	)
	_panel.call("submit_jump")
	for frame in SETTLE_FRAMES:
		await process_frame
	if current_scene == null or current_scene.get_instance_id() != initial_scene_id:
		_fail("An ambiguous matrix destination reloaded the scene instead of reporting an error.")
		return
	if not _panel_is_open() or not paused:
		_fail("An invalid runtime jump did not preserve the open, paused panel.")
		return
	var error_text := String(_panel.call("get_error_text")).strip_edges()
	if error_text.is_empty():
		_fail("An ambiguous matrix destination did not show an error message.")
		return
	if not _field_owns_focus(_panel, NodePath("%AreaSpin")):
		_fail("An ambiguous matrix destination did not return focus to the AreaData input.")
		return
	if not await _capture_open_panel():
		return

	_panel.call(
		"set_destination_fields",
		TEST_MATRIX_ID,
		TEST_AREA_DATA_ID,
		false,
		TEST_CELL,
		TEST_TILE
	)
	var old_scene_id := initial_scene_id
	_panel.call("submit_jump")
	if DebugDestinationRequest.has_pending(self):
		_fail("The runtime jump was queued before its deferred scene reload began.")
		return
	_panel = null
	player = null
	_current_streamer = null
	initial_scene = null

	var jumped_scene: Node = await _wait_for_replacement_scene(old_scene_id)
	if jumped_scene == null:
		_fail("The valid runtime debug jump did not reload the scene within %d frames." % MAX_FRAMES)
		return
	_current_streamer = await _wait_for_streamer(
		jumped_scene,
		TEST_MATRIX_ID,
		TEST_AREA_DATA_ID,
		TEST_CELL
	)
	if _current_streamer == null:
		_fail("Matrix 0049 area 0061 did not finish loading within %d frames." % MAX_FRAMES)
		return
	if DebugDestinationRequest.has_pending(self):
		_fail("The runtime debug destination handoff was not consumed after scene reload.")
		return
	if paused:
		_fail("The scene tree remained paused after the runtime debug jump.")
		return

	var stats := _current_streamer.get_stream_stats()
	if int(stats.get("manifest_cells", 0)) != 4 or int(stats.get("loaded_chunks", 0)) != 4:
		_fail("The runtime debug jump did not load all four destination chunks: %s" % JSON.stringify(stats))
		return
	if int(stats.get("failed_assets", 0)) != 0:
		_fail("The runtime debug jump had failed assets: %s" % JSON.stringify(stats))
		return
	var start := stats.get("start", {}) as Dictionary
	var start_cell := start.get("cell", {}) as Dictionary
	var start_tile := start.get("tile", {}) as Dictionary
	if Vector2i(int(start_cell.get("x", -1)), int(start_cell.get("y", -1))) != TEST_CELL:
		_fail("The runtime debug jump reported an incorrect start cell: %s" % JSON.stringify(start))
		return
	if Vector2i(int(start_tile.get("x", -1)), int(start_tile.get("y", -1))) != TEST_TILE:
		_fail("The runtime debug jump reported an incorrect start tile: %s" % JSON.stringify(start))
		return

	var jumped_player := jumped_scene.get_node_or_null("Player") as PlatinumPlayerController
	if jumped_player == null or not jumped_player.global_position.is_equal_approx(TEST_POSITION):
		var actual_position := jumped_player.global_position if jumped_player != null else Vector3.INF
		_fail("The runtime debug jump placed the player incorrectly: %s" % actual_position)
		return
	var streamers := get_nodes_in_group("platinum_world_streamer")
	if streamers.size() != 1 or streamers[0] != _current_streamer:
		_fail("Scene reload left an unexpected number of world streamers: %d" % streamers.size())
		return

	print("RUNTIME_DEBUG_JUMP_OK ", JSON.stringify(stats))
	call_deferred("_finish_success")


func _wait_for_replacement_scene(previous_instance_id: int) -> Node:
	for frame in MAX_FRAMES:
		await process_frame
		var scene := current_scene
		if scene != null and scene.get_instance_id() != previous_instance_id:
			return scene
	return null


func _wait_for_streamer(
	scene: Node,
	expected_matrix: int,
	expected_area: int,
	expected_cell: Variant
) -> PlatinumWorldStreamer:
	for frame in MAX_FRAMES:
		await process_frame
		if not is_instance_valid(scene) or current_scene != scene:
			return null
		var streamer := scene.get_node_or_null("WorldStreamer") as PlatinumWorldStreamer
		if streamer == null:
			continue
		var stats := streamer.get_stream_stats()
		if int(stats.get("matrix", -1)) != expected_matrix:
			continue
		if int(stats.get("area", -2)) != expected_area:
			continue
		if int(stats.get("loading_assets", 0)) != 0:
			continue
		if int(stats.get("loaded_chunks", 0)) < 1:
			continue
		if expected_cell != null and not streamer.is_chunk_loaded(expected_cell as Vector2i):
			continue
		return streamer
	return null


func _validate_panel_contract(panel: Node) -> bool:
	if panel == null:
		_fail("Main scene has no DebugDestinationPanel.")
		return false
	for method_name: StringName in [
		&"is_open",
		&"open_panel",
		&"close_panel",
		&"set_destination_fields",
		&"submit_jump",
		&"get_error_text",
	]:
		if not panel.has_method(method_name):
			_fail("DebugDestinationPanel is missing %s()." % method_name)
			return false
	if panel.get_node_or_null(NodePath("%MatrixSpin")) == null:
		_fail("DebugDestinationPanel has no unique MatrixSpin control.")
		return false
	if panel.get_node_or_null(NodePath("%AreaSpin")) == null:
		_fail("DebugDestinationPanel has no unique AreaSpin control.")
		return false
	return true


func _panel_is_open() -> bool:
	return is_instance_valid(_panel) and bool(_panel.call("is_open"))


func _field_owns_focus(panel: Node, field_path: NodePath) -> bool:
	if not is_instance_valid(panel):
		return false
	var field := panel.get_node_or_null(field_path) as Control
	var focus_owner := root.gui_get_focus_owner()
	if field == null or focus_owner == null:
		return false
	return focus_owner == field or field.is_ancestor_of(focus_owner)


func _send_f2() -> void:
	var press := InputEventKey.new()
	press.keycode = KEY_F2
	press.physical_keycode = KEY_F2
	press.pressed = true
	Input.parse_input_event(press)
	await process_frame
	var release := press.duplicate() as InputEventKey
	release.pressed = false
	Input.parse_input_event(release)
	await process_frame


func _capture_path_from_arguments() -> String:
	for argument: String in OS.get_cmdline_user_args():
		if not argument.begins_with("--capture-panel="):
			continue
		var value := argument.trim_prefix("--capture-panel=").strip_edges()
		if value.is_empty() or not value.to_lower().ends_with(".png"):
			_fail("--capture-panel expects a nonempty PNG path.")
			return ""
		return value
	return ""


func _capture_open_panel() -> bool:
	if _capture_path.is_empty():
		return true
	for frame in CAPTURE_SETTLE_FRAMES:
		await process_frame
	var image := root.get_texture().get_image()
	if image.is_empty():
		_fail("Runtime debug panel capture is empty.")
		return false
	if image.get_size() != NDS_SCREEN_SIZE:
		_fail("Runtime debug panel capture has an unexpected size: %s" % image.get_size())
		return false
	var first_pixel := image.get_pixel(0, 0)
	var has_visible_pixel := false
	var has_variation := false
	for y in image.get_height():
		for x in image.get_width():
			var pixel := image.get_pixel(x, y)
			if pixel.a > 0.01:
				has_visible_pixel = true
			if not pixel.is_equal_approx(first_pixel):
				has_variation = true
			if has_visible_pixel and has_variation:
				break
		if has_visible_pixel and has_variation:
			break
	if not has_visible_pixel or not has_variation:
		_fail("Runtime debug panel capture contains no visible image variation.")
		return false
	var capture_directory := ProjectSettings.globalize_path(_capture_path.get_base_dir())
	var directory_error := DirAccess.make_dir_recursive_absolute(capture_directory)
	if directory_error != OK:
		_fail("Runtime debug panel capture directory could not be created (error %d)." % directory_error)
		return false
	var save_error := image.save_png(ProjectSettings.globalize_path(_capture_path))
	if save_error != OK:
		_fail("Runtime debug panel capture could not be saved (error %d)." % save_error)
		return false
	print("RUNTIME_DEBUG_JUMP_CAPTURE_OK ", ProjectSettings.globalize_path(_capture_path))
	return true


func _release_test_inputs() -> void:
	Input.action_release(&"move_right")


func _fail(message: String) -> void:
	if _failure_pending:
		return
	_failure_pending = true
	push_error(message)
	paused = false
	_release_test_inputs()
	if is_instance_valid(_current_streamer):
		_current_streamer.shutdown()
	if is_instance_valid(current_scene):
		current_scene.queue_free()
	call_deferred("_finish_failure")


func _finish_failure() -> void:
	for frame in CLEANUP_FRAMES:
		await process_frame
	quit(1)


func _finish_success() -> void:
	paused = false
	_release_test_inputs()
	if is_instance_valid(_current_streamer):
		_current_streamer.shutdown()
	if is_instance_valid(current_scene):
		current_scene.queue_free()
	for frame in CLEANUP_FRAMES:
		await process_frame
	quit(0)
