extends SceneTree

const ATLAS_PATH := "res://assets/platinum/characters/dawn_overworld.png"
const FRAME_COLUMNS := 8
const FRAME_ROWS := 4
const EXPECTED_FRAME_SIZE := Vector2i(34, 34)
const MAX_RENDER_FRAMES := 8


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var texture := load(ATLAS_PATH) as Texture2D
	if texture == null:
		_fail("Player atlas is missing: %s" % ATLAS_PATH)
		return
	var atlas_image := texture.get_image()
	var expected_atlas_size := Vector2i(
		EXPECTED_FRAME_SIZE.x * FRAME_COLUMNS,
		EXPECTED_FRAME_SIZE.y * FRAME_ROWS
	)
	if atlas_image == null or atlas_image.is_empty() or atlas_image.get_size() != expected_atlas_size:
		_fail("Player atlas dimensions are invalid: %s" % texture.get_size())
		return

	RenderingServer.set_default_clear_color(Color(0.0, 0.0, 0.0, 0.0))
	var viewport := SubViewport.new()
	viewport.size = EXPECTED_FRAME_SIZE
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var scene_root := Node3D.new()
	viewport.add_child(scene_root)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = float(EXPECTED_FRAME_SIZE.y)
	camera.near = 0.1
	camera.far = 20.0
	camera.position = Vector3(0.0, 0.0, 10.0)
	camera.current = true
	scene_root.add_child(camera)
	var sprite := Sprite3D.new()
	sprite.texture = texture
	sprite.hframes = FRAME_COLUMNS
	sprite.vframes = FRAME_ROWS
	sprite.pixel_size = 1.0
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	scene_root.add_child(sprite)

	for frame_index in FRAME_COLUMNS * FRAME_ROWS:
		sprite.frame = frame_index
		var rendered := await _render_frame(viewport)
		if rendered.is_empty():
			_fail("Player sprite viewport did not render frame %d." % frame_index)
			return
		var source_rect := Rect2i(
			(frame_index % FRAME_COLUMNS) * EXPECTED_FRAME_SIZE.x,
			(frame_index / FRAME_COLUMNS) * EXPECTED_FRAME_SIZE.y,
			EXPECTED_FRAME_SIZE.x,
			EXPECTED_FRAME_SIZE.y
		)
		var source := atlas_image.get_region(source_rect)
		if not _alpha_mask_matches(rendered, source):
			var capture_root := "res://captures/player_sprite_pixel_test"
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(capture_root))
			rendered.save_png(ProjectSettings.globalize_path(capture_root.path_join("rendered.png")))
			source.save_png(ProjectSettings.globalize_path(capture_root.path_join("source.png")))
			_fail("Rendered player frame alpha is distorted: %d" % frame_index)
			return

	print("PLAYER_SPRITE_PIXEL_TEST_OK ", JSON.stringify({
		"atlas": [expected_atlas_size.x, expected_atlas_size.y],
		"frame": [EXPECTED_FRAME_SIZE.x, EXPECTED_FRAME_SIZE.y],
		"frames": FRAME_COLUMNS * FRAME_ROWS,
	}))
	viewport.queue_free()
	for cleanup_frame in 4:
		await process_frame
	RenderingServer.force_sync()
	quit(0)


func _render_frame(viewport: SubViewport) -> Image:
	for render_frame in MAX_RENDER_FRAMES:
		await process_frame
		await RenderingServer.frame_post_draw
		var image := viewport.get_texture().get_image()
		if image != null and not image.is_empty():
			return image
	return Image.new()


func _alpha_mask_matches(rendered: Image, source: Image) -> bool:
	if rendered.get_size() != source.get_size():
		return false
	for y in EXPECTED_FRAME_SIZE.y:
		for x in EXPECTED_FRAME_SIZE.x:
			var actual := rendered.get_pixel(x, y)
			var expected := source.get_pixel(x, y)
			if not is_equal_approx(actual.a, expected.a):
				return false
	return true


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
