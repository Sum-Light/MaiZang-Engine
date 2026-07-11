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

	var camera := main.get_node("Camera") as Camera3D
	camera.global_position = Vector3(
		4.0 * PlatinumWorldStreamer.CHUNK_SIZE - 1.0,
		52.0,
		28.0 * PlatinumWorldStreamer.CHUNK_SIZE - 1.0
	)
	for frame in 30:
		await process_frame
	if streamer.get_focus_cell() != Vector2i(3, 27):
		_fail("Focus moved before crossing the current chunk boundary: %s" % streamer.get_focus_cell())
		return

	camera.global_position = Vector3(9.0 * PlatinumWorldStreamer.CHUNK_SIZE, 52.0, 16.0 * PlatinumWorldStreamer.CHUNK_SIZE + 14.0)
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
