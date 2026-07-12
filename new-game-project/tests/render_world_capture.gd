extends SceneTree

const VisualProfileControllerScript := preload("res://scripts/visual_profile_controller.gd")
const MAX_FRAMES := 1800
const NDS_SCREEN_SIZE := Vector2i(256, 192)
const DEFAULT_CAPTURE_PATH := "res://captures/world_player.png"
const DEFAULT_CAPTURE_CELL := Vector2i(3, 27)
const DEFAULT_VISUAL_PROFILE := &"classic"

var _main: Node
var _streamer: PlatinumWorldStreamer
var _measurement_enabled := false
var _failure_pending := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = NDS_SCREEN_SIZE
	var capture_cell := DEFAULT_CAPTURE_CELL
	var capture_offset := Vector2.ZERO
	var capture_path := DEFAULT_CAPTURE_PATH
	var metrics_path := ""
	var requested_profile := DEFAULT_VISUAL_PROFILE
	var warmup_frames := 10
	var measure_frames := 0
	var force_perspective := false
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--cell="):
			var cell_components := argument.trim_prefix("--cell=").split(",")
			if cell_components.size() == 2:
				capture_cell = Vector2i(int(cell_components[0]), int(cell_components[1]))
		elif argument.begins_with("--offset="):
			var offset_components := argument.trim_prefix("--offset=").split(",")
			if offset_components.size() == 2:
				capture_offset = Vector2(float(offset_components[0]), float(offset_components[1]))
		elif argument.begins_with("--output="):
			capture_path = argument.trim_prefix("--output=")
		elif argument.begins_with("--metrics-output="):
			metrics_path = argument.trim_prefix("--metrics-output=")
		elif argument.begins_with("--visual-profile="):
			requested_profile = StringName(argument.trim_prefix("--visual-profile=").to_lower())
		elif argument.begins_with("--warmup-frames="):
			warmup_frames = maxi(0, int(argument.trim_prefix("--warmup-frames=")))
		elif argument.begins_with("--measure-frames="):
			measure_frames = maxi(0, int(argument.trim_prefix("--measure-frames=")))
		elif argument == "--perspective":
			force_perspective = true

	if requested_profile not in [
		VisualProfileControllerScript.CLASSIC_PROFILE,
		VisualProfileControllerScript.HD2D_PROFILE,
	]:
		_fail("Unknown visual profile requested for capture: %s" % requested_profile)
		return
	if not _is_capture_path(capture_path):
		_fail("Capture output must remain under res://captures/: %s" % capture_path)
		return
	if not metrics_path.is_empty() and not _is_capture_path(metrics_path):
		_fail("Metrics output must remain under res://captures/: %s" % metrics_path)
		return

	var packed := load("res://scenes/main.tscn") as PackedScene
	if packed == null:
		_fail("Main scene could not be loaded.")
		return
	var main := packed.instantiate()
	_main = main
	var player := main.get_node_or_null("Player") as PlatinumPlayerController
	var camera := main.get_node_or_null("Camera") as PlatinumFollowCamera
	var visual_profile := main.get_node_or_null("VisualProfile") as VisualProfileControllerScript
	if player == null or camera == null or visual_profile == null:
		_fail("Player, camera, or VisualProfile was not created.")
		return
	player.position = Vector3(
		capture_cell.x * PlatinumWorldStreamer.CHUNK_SIZE + capture_offset.x,
		player.position.y,
		capture_cell.y * PlatinumWorldStreamer.CHUNK_SIZE + capture_offset.y
	)
	root.add_child(main)
	if visual_profile.get_active_profile_name() != requested_profile:
		_fail(
			"Visual profile mismatch: requested=%s active=%s"
			% [requested_profile, visual_profile.get_active_profile_name()]
		)
		return
	if force_perspective:
		camera.toggle_projection()

	var stats: Dictionary
	for frame in MAX_FRAMES:
		await process_frame
		_streamer = get_first_node_in_group("platinum_world_streamer") as PlatinumWorldStreamer
		if _streamer == null:
			continue
		stats = _streamer.get_stream_stats()
		if int(stats.loaded_chunks) >= 9 and int(stats.loading_assets) == 0:
			break

	if _streamer == null or int(stats.get("loaded_chunks", 0)) < 9:
		_fail("World did not become ready for capture.")
		return
	if int(stats.get("failed_assets", -1)) != 0:
		_fail("World has failed assets: %s" % JSON.stringify(stats))
		return
	if int(stats.get("material_replacements", -1)) != 0:
		_fail("World changed shared materials at runtime: %s" % JSON.stringify(stats))
		return

	var viewport_rid := root.get_viewport_rid()
	if measure_frames > 0:
		RenderingServer.viewport_set_measure_render_time(viewport_rid, true)
		_measurement_enabled = true
	for frame in warmup_frames:
		await process_frame
		await RenderingServer.frame_post_draw

	var metrics := {}
	if measure_frames > 0:
		metrics = await _collect_metrics(viewport_rid, measure_frames)
		RenderingServer.viewport_set_measure_render_time(viewport_rid, false)
		_measurement_enabled = false
		if not metrics_path.is_empty() and not _write_json(metrics_path, metrics):
			return

	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image.is_empty():
		_fail("Rendered viewport image is empty.")
		return
	if image.get_size() != NDS_SCREEN_SIZE:
		_fail("Unexpected capture size: %s" % image.get_size())
		return
	var capture_absolute_path := ProjectSettings.globalize_path(capture_path)
	DirAccess.make_dir_recursive_absolute(capture_absolute_path.get_base_dir())
	var save_error := image.save_png(capture_absolute_path)
	if save_error != OK:
		_fail("Could not save capture (error %d)." % save_error)
		return

	var forward := -camera.global_basis.z
	print("WORLD_CAPTURE_OK ", capture_absolute_path)
	print("WORLD_CAPTURE_STATS ", JSON.stringify(stats))
	print("WORLD_CAPTURE_VISUAL_PROFILE ", visual_profile.get_active_profile_name())
	print("WORLD_CAPTURE_VISUAL_STATE ", JSON.stringify(visual_profile.get_visual_state()))
	print("WORLD_CAPTURE_CAMERA_FORWARD ", forward)
	print("WORLD_CAPTURE_PROJECTION ", camera.get_projection_name())
	print("WORLD_CAPTURE_CAMERA_DISTANCE ", camera.get_active_follow_distance())
	print("WORLD_CAPTURE_PLAYER_FRAME ", player.get_current_sprite_frame())
	if not metrics.is_empty():
		print("WORLD_CAPTURE_METRICS ", JSON.stringify(metrics))
	_cleanup_scene()
	for cleanup_frame in 10:
		await process_frame
	call_deferred("_finish_success")


func _collect_metrics(viewport_rid: RID, sample_count: int) -> Dictionary:
	var process_ms: Array[float] = []
	var physics_ms: Array[float] = []
	var render_cpu_ms: Array[float] = []
	var render_gpu_ms: Array[float] = []
	var setup_cpu_ms: Array[float] = []
	var visible_draw_calls: Array[float] = []
	var visible_objects: Array[float] = []
	var visible_primitives: Array[float] = []
	for sample in sample_count:
		await process_frame
		await RenderingServer.frame_post_draw
		process_ms.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		physics_ms.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		render_cpu_ms.append(RenderingServer.viewport_get_measured_render_time_cpu(viewport_rid))
		render_gpu_ms.append(RenderingServer.viewport_get_measured_render_time_gpu(viewport_rid))
		setup_cpu_ms.append(RenderingServer.get_frame_setup_time_cpu())
		visible_draw_calls.append(float(RenderingServer.viewport_get_render_info(
			viewport_rid,
			RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,
			RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME
		)))
		visible_objects.append(float(RenderingServer.viewport_get_render_info(
			viewport_rid,
			RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,
			RenderingServer.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME
		)))
		visible_primitives.append(float(RenderingServer.viewport_get_render_info(
			viewport_rid,
			RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,
			RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME
		)))
	return {
		"schema_version": 1,
		"samples": sample_count,
		"visual_profile": String(
			(get_first_node_in_group("platinum_visual_profile") as VisualProfileControllerScript)
			.get_active_profile_name()
		),
		"viewport": [NDS_SCREEN_SIZE.x, NDS_SCREEN_SIZE.y],
		"process_ms": _sample_summary(process_ms),
		"physics_ms": _sample_summary(physics_ms),
		"render_cpu_ms": _sample_summary(render_cpu_ms),
		"render_gpu_ms": _sample_summary(render_gpu_ms, true),
		"setup_cpu_ms": _sample_summary(setup_cpu_ms),
		"visible_draw_calls": _sample_summary(visible_draw_calls),
		"visible_objects": _sample_summary(visible_objects),
		"visible_primitives": _sample_summary(visible_primitives),
		"world": _streamer.get_stream_stats(),
	}


func _sample_summary(values: Array[float], zero_is_unavailable: bool = false) -> Dictionary:
	if values.is_empty():
		return {"available": false, "count": 0}
	var sorted_values: Array[float] = values.duplicate()
	sorted_values.sort()
	var total := 0.0
	for value: float in sorted_values:
		total += value
	var maximum := sorted_values[sorted_values.size() - 1]
	return {
		"available": not zero_is_unavailable or maximum > 0.0,
		"count": sorted_values.size(),
		"min": sorted_values[0],
		"mean": total / float(sorted_values.size()),
		"p50": _nearest_rank(sorted_values, 0.50),
		"p95": _nearest_rank(sorted_values, 0.95),
		"p99": _nearest_rank(sorted_values, 0.99),
		"max": maximum,
	}


func _nearest_rank(sorted_values: Array[float], percentile: float) -> float:
	var index := clampi(
		ceili(percentile * float(sorted_values.size())) - 1,
		0,
		sorted_values.size() - 1
	)
	return sorted_values[index]


func _write_json(path: String, value: Dictionary) -> bool:
	var absolute_path := ProjectSettings.globalize_path(path)
	DirAccess.make_dir_recursive_absolute(absolute_path.get_base_dir())
	var file := FileAccess.open(absolute_path, FileAccess.WRITE)
	if file == null:
		_fail("Could not open metrics output: %s" % path)
		return false
	file.store_string(JSON.stringify(value, "\t") + "\n")
	return true


func _is_capture_path(path: String) -> bool:
	return path.begins_with("res://captures/") and not path.contains("..")


func _cleanup_scene() -> void:
	if _measurement_enabled:
		RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), false)
		_measurement_enabled = false
	if is_instance_valid(_streamer):
		_streamer.shutdown()
	if is_instance_valid(_main):
		_main.queue_free()


func _fail(message: String) -> void:
	if _failure_pending:
		return
	_failure_pending = true
	push_error(message)
	_cleanup_scene()
	call_deferred("_finish_failure")


func _finish_failure() -> void:
	for cleanup_frame in 10:
		await process_frame
	quit(1)


func _finish_success() -> void:
	quit(0)
