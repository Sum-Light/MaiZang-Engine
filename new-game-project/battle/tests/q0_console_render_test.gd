extends SceneTree

const TEXT_CONSOLE_SCENE := "res://battle/scenes/battle_text_console.tscn"
const DEFAULT_CAPTURE_PATH := "res://battle/.tmp/q0_text_console.png"
const EXPECTED_SIZE := Vector2i(256, 192)
const SETTLE_FRAMES := 4


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var initial_pause := paused
	var packed := ResourceLoader.load(
		TEXT_CONSOLE_SCENE,
		"PackedScene",
		ResourceLoader.CACHE_MODE_IGNORE
	) as PackedScene
	if packed == null:
		_fail("Text console scene could not be loaded for rendering.")
		return

	var console := packed.instantiate() as Control
	if console == null:
		_fail("Text console scene has no Control root.")
		return
	root.add_child(console)
	for frame in SETTLE_FRAMES:
		await process_frame

	var image := root.get_texture().get_image()
	if image.is_empty() or image.get_size() != EXPECTED_SIZE:
		_fail("Text console render has an invalid image size: %s" % image.get_size())
		console.queue_free()
		return
	if not _has_visible_variation(image):
		_fail("Text console render is blank or has no visible variation.")
		console.queue_free()
		return

	var capture_path := _capture_path_from_arguments()
	var capture_directory := ProjectSettings.globalize_path(capture_path.get_base_dir())
	var directory_error := DirAccess.make_dir_recursive_absolute(capture_directory)
	if directory_error != OK:
		_fail("Could not create Q0 capture directory (error %d)." % directory_error)
		console.queue_free()
		return
	var save_error := image.save_png(ProjectSettings.globalize_path(capture_path))
	if save_error != OK:
		_fail("Could not save Q0 capture (error %d)." % save_error)
		console.queue_free()
		return

	if paused != initial_pause:
		_fail("Text console changed the SceneTree pause state.")
		return

	print("BATTLE_Q0_RENDER_OK ", ProjectSettings.globalize_path(capture_path))
	var exit_button := console.get_node_or_null(NodePath("%ExitButton")) as Button
	if exit_button == null:
		_fail("Text console has no Exit button.")
		return
	exit_button.pressed.emit()
	await process_frame
	_fail("Exit button did not stop the battle scene.")


func _capture_path_from_arguments() -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture="):
			var value := argument.trim_prefix("--capture=").strip_edges()
			if not value.is_empty() and value.to_lower().ends_with(".png"):
				return value
	return DEFAULT_CAPTURE_PATH


func _has_visible_variation(image: Image) -> bool:
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
				return true
	return false


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
