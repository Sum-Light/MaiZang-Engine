extends SceneTree

const MAX_FRAMES := 1800
const TEST_MATRIX_ID := 49
const TEST_AREA_DATA_ID := 61
const TEST_CELL := Vector2i(1, 1)
const TEST_TILE := Vector2i(31, 31)
const CLI_TEST_AREA_DATA_ID := 4
const CLI_TEST_CELL := Vector2i(0, 0)
const CLI_TEST_TILE := Vector2i(7, 9)
const ALTITUDE_TEST_CELL := Vector2i(4, 25)
const ALTITUDE_TEST_TILE := Vector2i(28, 30)
const ALTITUDE_TEST_POSITION := Vector3(156.5, 2.0, 830.5)

var _main: Node
var _streamer: PlatinumWorldStreamer


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	if packed == null:
		_fail("Main scene could not be loaded.")
		return
	_main = packed.instantiate()
	_streamer = _main.get_node("WorldStreamer") as PlatinumWorldStreamer
	if _streamer == null:
		_fail("Main scene has no world streamer.")
		return
	var use_runtime_cli := OS.get_cmdline_user_args().has("--expect-runtime-cli")
	var expected_area := CLI_TEST_AREA_DATA_ID if use_runtime_cli else TEST_AREA_DATA_ID
	var expected_cell := CLI_TEST_CELL if use_runtime_cli else TEST_CELL
	var expected_tile := CLI_TEST_TILE if use_runtime_cli else TEST_TILE
	if not use_runtime_cli and not _streamer.configure_debug_destination(
		TEST_MATRIX_ID, TEST_AREA_DATA_ID, TEST_CELL, TEST_TILE
	):
		_fail("Explicit debug destination could not be configured.")
		return
	root.add_child(_main)

	var stats: Dictionary
	for frame in MAX_FRAMES:
		await process_frame
		stats = _streamer.get_stream_stats()
		if (
			_streamer.is_chunk_loaded(expected_cell)
			and int(stats.get("loading_assets", 0)) == 0
		):
			break

	if not _streamer.is_chunk_loaded(expected_cell):
		_fail("The configured debug destination did not load.")
		return
	if int(stats.get("matrix", -1)) != TEST_MATRIX_ID:
		_fail("The explicit matrix did not override lower-priority configuration.")
		return
	if int(stats.get("area", -1)) != expected_area:
		_fail("The requested matrix area variant was not selected.")
		return
	if int(stats.get("manifest_cells", 0)) != 4 or int(stats.get("loaded_chunks", 0)) != 4:
		_fail("The 2x2 destination did not load all four occupied cells: %s" % JSON.stringify(stats))
		return
	if int(stats.get("failed_assets", 0)) != 0:
		_fail("The destination had failed assets: %s" % JSON.stringify(stats))
		return

	var start := stats.get("start", {}) as Dictionary
	var start_cell := start.get("cell", {}) as Dictionary
	var start_tile := start.get("tile", {}) as Dictionary
	if Vector2i(int(start_cell.get("x", -1)), int(start_cell.get("y", -1))) != expected_cell:
		_fail("The reported start cell is incorrect: %s" % JSON.stringify(start))
		return
	if Vector2i(int(start_tile.get("x", -1)), int(start_tile.get("y", -1))) != expected_tile:
		_fail("The reported start tile is incorrect: %s" % JSON.stringify(start))
		return

	var player := _main.get_node("Player") as PlatinumPlayerController
	var expected_position := Vector3(
		expected_cell.x * PlatinumWorldStreamer.CHUNK_SIZE + expected_tile.x + 0.5,
		1.0,
		expected_cell.y * PlatinumWorldStreamer.CHUNK_SIZE + expected_tile.y + 0.5
	)
	if player == null or not player.global_position.is_equal_approx(expected_position):
		var actual_position := player.global_position if player != null else Vector3.INF
		_fail("Player start position is incorrect: %s" % actual_position)
		return
	print("DEBUG_DESTINATION_OK ", JSON.stringify(stats))
	_streamer.shutdown()
	_main.queue_free()
	for cleanup_frame in 10:
		await process_frame
	if not await _validate_nonzero_altitude_start(packed):
		return
	call_deferred("_finish_success")


func _validate_nonzero_altitude_start(packed: PackedScene) -> bool:
	_main = packed.instantiate()
	_streamer = _main.get_node("WorldStreamer") as PlatinumWorldStreamer
	if _streamer == null or not _streamer.configure_debug_destination(
		0, -1, ALTITUDE_TEST_CELL, ALTITUDE_TEST_TILE
	):
		_fail("The nonzero-altitude destination could not be configured.")
		return false
	root.add_child(_main)

	var stats: Dictionary
	for frame in MAX_FRAMES:
		await process_frame
		stats = _streamer.get_stream_stats()
		if (
			_streamer.is_chunk_loaded(ALTITUDE_TEST_CELL)
			and int(stats.get("loading_assets", 0)) == 0
		):
			break
	if not _streamer.is_chunk_loaded(ALTITUDE_TEST_CELL):
		_fail("The nonzero-altitude matrix cell did not load.")
		return false

	var resolved_position: Variant = _streamer.resolve_cell_tile_world_position(
		ALTITUDE_TEST_CELL, ALTITUDE_TEST_TILE
	)
	if resolved_position == null or not (resolved_position as Vector3).is_equal_approx(
		ALTITUDE_TEST_POSITION
	):
		_fail("The streamer resolved an incorrect nonzero-altitude position: %s" % resolved_position)
		return false
	var player := _main.get_node("Player") as PlatinumPlayerController
	if player == null or not player.global_position.is_equal_approx(ALTITUDE_TEST_POSITION):
		var actual_position := player.global_position if player != null else Vector3.INF
		_fail("The player did not start at the selected cell altitude: %s" % actual_position)
		return false
	var start := stats.get("start", {}) as Dictionary
	var start_world := start.get("world", {}) as Dictionary
	var reported_position := Vector3(
		float(start_world.get("x", INF)),
		float(start_world.get("y", INF)),
		float(start_world.get("z", INF))
	)
	if not reported_position.is_equal_approx(ALTITUDE_TEST_POSITION):
		_fail("Stream stats reported an incorrect altitude-aware start: %s" % reported_position)
		return false
	print("DEBUG_DESTINATION_ALTITUDE_OK ", JSON.stringify(stats))
	_streamer.shutdown()
	_main.queue_free()
	for cleanup_frame in 10:
		await process_frame
	return true


func _fail(message: String) -> void:
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


func _finish_success() -> void:
	quit(0)
