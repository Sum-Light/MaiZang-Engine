extends SceneTree

const MAX_FRAMES := 1800
const NDS_SCREEN_SIZE := Vector2i(256, 192)
const DEFAULT_CAPTURE_PATH := "res://captures/world_start.png"
const DEFAULT_CAPTURE_CELL := Vector2i(3, 27)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = NDS_SCREEN_SIZE
	var capture_cell := DEFAULT_CAPTURE_CELL
	var capture_path := DEFAULT_CAPTURE_PATH
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--cell="):
			var components := argument.trim_prefix("--cell=").split(",")
			if components.size() == 2:
				capture_cell = Vector2i(int(components[0]), int(components[1]))
		elif argument.begins_with("--output="):
			capture_path = argument.trim_prefix("--output=")

	var packed := load("res://scenes/main.tscn") as PackedScene
	if packed == null:
		_fail("Main scene could not be loaded.")
		return
	var main := packed.instantiate()
	var camera := main.get_node("Camera") as Camera3D
	camera.position = Vector3(
		capture_cell.x * PlatinumWorldStreamer.CHUNK_SIZE,
		52.0,
		capture_cell.y * PlatinumWorldStreamer.CHUNK_SIZE + 14.0
	)
	root.add_child(main)

	var streamer: PlatinumWorldStreamer
	var stats: Dictionary
	for frame in MAX_FRAMES:
		await process_frame
		streamer = get_first_node_in_group("platinum_world_streamer") as PlatinumWorldStreamer
		if streamer == null:
			continue
		stats = streamer.get_stream_stats()
		if int(stats.loaded_chunks) >= 9 and int(stats.loading_assets) == 0:
			break

	if streamer == null or int(stats.get("loaded_chunks", 0)) < 9:
		_fail("World did not become ready for capture.")
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
	streamer.shutdown()
	main.queue_free()
	for cleanup_frame in 10:
		await process_frame
	call_deferred("_finish_success")


func _fail(message: String) -> void:
	push_error(message)
	quit(1)


func _finish_success() -> void:
	quit(0)
