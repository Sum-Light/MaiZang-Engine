extends SceneTree

const FIXTURE_MANIFEST := "res://tests/fixtures/nonzero_altitude_manifest.json"
const START_CELL := Vector2i(5, 26)
const TARGET_CELL := Vector2i(4, 25)
const TARGET_TILE := Vector2i(28, 30)
const EXPECTED_START := Vector3(160.5, 1.0, 832.5)
const EXPECTED_TARGET := Vector3(156.5, 2.0, 830.5)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var streamer := PlatinumWorldStreamer.new()
	streamer.manifest_path = FIXTURE_MANIFEST
	streamer._matrix_id = 9999
	streamer._area_data_id = -1
	if not streamer._load_manifest():
		_fail("Synthetic altitude manifest could not be loaded.")
		streamer.free()
		return

	var start_position: Variant = streamer.resolve_cell_tile_world_position(START_CELL, Vector2i.ZERO)
	if start_position == null or not (start_position as Vector3).is_equal_approx(EXPECTED_START):
		_fail("Synthetic start position is incorrect: %s" % start_position)
		streamer.free()
		return
	var target_position: Variant = streamer.resolve_cell_tile_world_position(TARGET_CELL, TARGET_TILE)
	if target_position == null or not (target_position as Vector3).is_equal_approx(EXPECTED_TARGET):
		_fail("Nonzero-altitude tile position is incorrect: %s" % target_position)
		streamer.free()
		return
	var offset_position: Variant = streamer.resolve_offset_grid_world_position(
		start_position as Vector3, Vector2(-4.0, -2.0)
	)
	if offset_position == null or not (offset_position as Vector3).is_equal_approx(EXPECTED_TARGET):
		_fail("Cross-cell capture offset did not adopt the destination altitude: %s" % offset_position)
		streamer.free()
		return
	if streamer.resolve_cell_tile_world_position(TARGET_CELL, Vector2i(32, 0)) != null:
		_fail("Out-of-range map tile was accepted.")
		streamer.free()
		return

	print("DEBUG_COORDINATE_OK ", JSON.stringify({
		"start": EXPECTED_START,
		"target_cell": TARGET_CELL,
		"target_tile": TARGET_TILE,
		"target": EXPECTED_TARGET,
	}))
	streamer.free()
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
