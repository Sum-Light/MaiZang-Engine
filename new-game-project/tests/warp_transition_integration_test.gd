extends SceneTree

const MAIN_SCENE_PATH := "res://scenes/main.tscn"
const MAX_FRAMES := 1800
const SOURCE_MATRIX := 7
const SOURCE_AREA := 54
const SOURCE_HEADER := 203
const SOURCE_WARP := 4
const SOURCE_CELL := Vector2i(2, 0)
const SOURCE_START_TILE := Vector2i(10, 16)
const DESTINATION_MATRIX := 86
const DESTINATION_AREA := 66
const DESTINATION_HEADER := 295
const DESTINATION_WARP := 4
const DESTINATION_CELL := Vector2i.ZERO
const DESTINATION_TILE := Vector2i(9, 15)
const DOOR_MODEL_ID := 441
const WorldTransitionRequest := preload("res://scripts/world_transition_request.gd")

var _transition_request: Dictionary = {}
var _failure_pending := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	ProjectSettings.set_setting("maizang/debug/matrix_id", SOURCE_MATRIX)
	ProjectSettings.set_setting("maizang/debug/area_data_id", SOURCE_AREA)
	ProjectSettings.set_setting("maizang/debug/matrix_cell", SOURCE_CELL)
	ProjectSettings.set_setting("maizang/debug/map_tile", SOURCE_START_TILE)
	var change_error := change_scene_to_file(MAIN_SCENE_PATH)
	if change_error != OK:
		_fail("Warp test could not start the main scene (error %d)." % change_error)
		return

	var source_scene := await _wait_for_replacement_scene(0)
	var source_streamer := await _wait_for_streamer(
		source_scene, SOURCE_MATRIX, SOURCE_AREA, SOURCE_CELL
	)
	if source_streamer == null:
		_fail("Static door Warp source did not finish loading.")
		return
	var player := source_scene.get_node_or_null("Player") as PlatinumPlayerController
	var warp_controller := source_scene.get_node_or_null("WarpController") as PlatinumWarpController
	var animation_controller := source_scene.get_node_or_null(
		"MapAnimationController"
	) as PlatinumMapAnimationController
	if player == null or warp_controller == null or animation_controller == null:
		_fail("Main scene is missing the Warp or map-animation runtime nodes.")
		return
	var animation_stats := animation_controller.get_stats()
	if int(animation_stats.get("registered", 0)) < 1:
		_fail("The source door MapProp was not registered with the animation controller.")
		return
	warp_controller.transition_started.connect(_capture_transition_request)

	var source_scene_id := source_scene.get_instance_id()
	Input.action_press(&"move_up")
	var destination_scene: Node
	for frame in MAX_FRAMES:
		await process_frame
		if not _transition_request.is_empty():
			Input.action_release(&"move_up")
		if current_scene != null and current_scene.get_instance_id() != source_scene_id:
			destination_scene = current_scene
			break
	Input.action_release(&"move_up")
	if destination_scene == null:
		_fail("The static door Warp did not reload the scene.")
		return
	if not _validate_departure_request():
		return

	var destination_streamer := await _wait_for_streamer(
		destination_scene, DESTINATION_MATRIX, DESTINATION_AREA, DESTINATION_CELL
	)
	if destination_streamer == null:
		_fail("The Warp destination did not finish loading.")
		return
	var destination_player := destination_scene.get_node_or_null(
		"Player"
	) as PlatinumPlayerController
	var destination_controller := destination_scene.get_node_or_null(
		"WarpController"
	) as PlatinumWarpController
	if destination_player == null or destination_controller == null:
		_fail("The Warp destination lost its player or controller.")
		return
	var expected_position: Variant = destination_streamer.resolve_cell_tile_world_position(
		DESTINATION_CELL, DESTINATION_TILE
	)
	if (
		expected_position == null
		or not destination_player.global_position.is_equal_approx(expected_position as Vector3)
		or destination_player.get_current_facing() != PlatinumPlayerController.Facing.UP
	):
		_fail("The Warp destination position or facing is incorrect.")
		return
	for frame in MAX_FRAMES:
		await process_frame
		if not destination_controller.is_busy():
			break
	if destination_controller.is_busy() or not destination_player.is_input_enabled():
		_fail("Arrival door animation did not release player input.")
		return
	if WorldTransitionRequest.has_pending(self):
		_fail("The Warp handoff metadata was not consumed exactly once.")
		return

	var reverse_resolution := destination_streamer.resolve_warp_transition_request(
		destination_player.global_position,
		Vector2i.DOWN,
		{"disposition": "special", "action": "transition"}
	)
	if (
		not bool(reverse_resolution.get("ok", false))
		or int(reverse_resolution.get("source_header_id", -1)) != DESTINATION_HEADER
		or int(reverse_resolution.get("source_warp_id", -1)) != DESTINATION_WARP
		or int(reverse_resolution.get("matrix", -1)) != SOURCE_MATRIX
	):
		_fail("The arrival Header context was not preserved for the reciprocal Warp.")
		return

	print("WARP_TRANSITION_INTEGRATION_OK ", JSON.stringify({
		"source_header": SOURCE_HEADER,
		"source_warp": SOURCE_WARP,
		"destination_header": DESTINATION_HEADER,
		"destination_warp": DESTINATION_WARP,
		"door_model": DOOR_MODEL_ID,
	}))
	destination_streamer.shutdown()
	destination_scene.queue_free()
	call_deferred("_finish_success")


func _capture_transition_request(request: Dictionary) -> void:
	_transition_request = request.duplicate(true)


func _validate_departure_request() -> bool:
	if (
		int(_transition_request.get("source_header_id", -1)) != SOURCE_HEADER
		or int(_transition_request.get("source_warp_id", -1)) != SOURCE_WARP
		or int(_transition_request.get("destination_header_id", -1)) != DESTINATION_HEADER
		or int(_transition_request.get("destination_warp_id", -1)) != DESTINATION_WARP
		or int(_transition_request.get("matrix", -1)) != DESTINATION_MATRIX
		or int(_transition_request.get("area", -1)) != DESTINATION_AREA
		or _transition_request.get("cell", Vector2i(-1, -1)) != DESTINATION_CELL
		or _transition_request.get("tile", Vector2i(-1, -1)) != DESTINATION_TILE
		or int(_transition_request.get("door_model_id", -1)) != DOOR_MODEL_ID
	):
		_fail("The static door Warp produced an incorrect normalized request.")
		return false
	return true


func _wait_for_replacement_scene(previous_instance_id: int) -> Node:
	for frame in MAX_FRAMES:
		await process_frame
		if current_scene != null and current_scene.get_instance_id() != previous_instance_id:
			return current_scene
	return null


func _wait_for_streamer(
	scene: Node,
	matrix_id: int,
	area_data_id: int,
	loaded_cell: Vector2i
) -> PlatinumWorldStreamer:
	if scene == null:
		return null
	for frame in MAX_FRAMES:
		await process_frame
		if not is_instance_valid(scene) or current_scene != scene:
			return null
		var streamer := scene.get_node_or_null("WorldStreamer") as PlatinumWorldStreamer
		if streamer == null:
			continue
		var stats := streamer.get_stream_stats()
		if (
			int(stats.get("matrix", -1)) == matrix_id
			and int(stats.get("area", -1)) == area_data_id
			and int(stats.get("loading_assets", 0)) == 0
			and int(stats.get("failed_assets", 0)) == 0
			and streamer.is_chunk_loaded(loaded_cell)
		):
			return streamer
	return null


func _fail(message: String) -> void:
	if _failure_pending:
		return
	_failure_pending = true
	Input.action_release(&"move_up")
	push_error(message)
	if current_scene != null:
		var streamer := current_scene.get_node_or_null("WorldStreamer") as PlatinumWorldStreamer
		if streamer != null:
			streamer.shutdown()
		current_scene.queue_free()
	call_deferred("_finish_failure")


func _finish_failure() -> void:
	for frame in 10:
		await process_frame
	quit(1)


func _finish_success() -> void:
	for frame in 10:
		await process_frame
	quit(0)
