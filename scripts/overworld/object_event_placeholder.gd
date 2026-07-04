extends Node2D

@export var tile_size := 16

var event_data: Dictionary = {}
var grid_position := Vector2i.ZERO
var _body_color := Color(0.88, 0.58, 0.32, 1.0)
var _accent_color := Color(0.18, 0.16, 0.14, 1.0)
var _sprite_record: Dictionary = {}
var _sprite_texture: Texture2D = null
var _sprite_source_rect := Rect2()
var _sprite_flip_h := false
var _resolved_graphics_id := ""
var _graphics_resolution: Dictionary = {}

const BODY_COLORS := [
	Color(0.86, 0.42, 0.38, 1.0),
	Color(0.34, 0.56, 0.82, 1.0),
	Color(0.90, 0.70, 0.30, 1.0),
	Color(0.46, 0.72, 0.48, 1.0),
	Color(0.70, 0.50, 0.78, 1.0),
	Color(0.82, 0.54, 0.34, 1.0),
	Color(0.36, 0.68, 0.68, 1.0),
	Color(0.78, 0.76, 0.42, 1.0),
]


func configure(new_event_data: Dictionary, new_tile_size: int) -> void:
	event_data = new_event_data
	tile_size = new_tile_size
	grid_position = event_data.get("position", Vector2i(
		int(event_data.get("x", 0)),
		int(event_data.get("y", 0))
	))
	position = _grid_to_world(grid_position)
	z_index = grid_position.y
	_body_color = _color_from_graphics_id(String(event_data.get("graphics_id", "")))
	_configure_static_sprite()
	queue_redraw()


func _draw() -> void:
	if _sprite_texture != null:
		var dest_rect := _sprite_dest_rect()
		draw_rect(Rect2(-6, 5, 12, 4), Color(0.05, 0.07, 0.06, 0.35), true)
		if _sprite_flip_h:
			draw_set_transform(Vector2.ZERO, 0.0, Vector2(-1.0, 1.0))
		draw_texture_rect_region(_sprite_texture, dest_rect, _sprite_source_rect)
		if _sprite_flip_h:
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return

	var body_rect := Rect2(-5, -11, 10, 15)
	var feet_rect := Rect2(-4, 4, 8, 4)
	var shadow_rect := Rect2(-6, 5, 12, 4)

	draw_rect(shadow_rect, Color(0.05, 0.07, 0.06, 0.35), true)
	draw_rect(body_rect, _body_color, true)
	draw_rect(body_rect, _accent_color, false, 1.0)
	draw_rect(feet_rect, _accent_color, true)


func is_using_sprite() -> bool:
	return _sprite_texture != null


func get_sprite_record() -> Dictionary:
	return _sprite_record.duplicate(true)


func get_sprite_snapshot() -> Dictionary:
	return {
		"using_sprite": is_using_sprite(),
		"graphics_id": String(event_data.get("graphics_id", "")),
		"facing_direction": _facing_direction(),
		"source_rect": [
			int(_sprite_source_rect.position.x),
			int(_sprite_source_rect.position.y),
			int(_sprite_source_rect.size.x),
			int(_sprite_source_rect.size.y),
		],
		"h_flip": _sprite_flip_h,
		"dest_rect": [
			int(_sprite_dest_rect().position.x),
			int(_sprite_dest_rect().position.y),
			int(_sprite_dest_rect().size.x),
			int(_sprite_dest_rect().size.y),
		],
		"world_position": [int(position.x), int(position.y)],
		"resolved_graphics_id": _resolved_graphics_id,
		"graphics_resolution": _graphics_resolution.duplicate(true),
		"source_trace": _sprite_record.get("source_trace", []),
		"unsupported": _sprite_record.get("unsupported", []),
	}


func _configure_static_sprite() -> void:
	_sprite_record = {}
	_sprite_texture = null
	_sprite_source_rect = Rect2()
	_sprite_flip_h = false
	_resolved_graphics_id = ""
	_graphics_resolution = {}

	var graphics_id := String(event_data.get("graphics_id", ""))
	if graphics_id.is_empty():
		return
	_resolved_graphics_id = graphics_id

	var registry := _registry()
	if registry == null or not registry.has_method("get_object_event_sprite_record"):
		return

	if registry.has_method("resolve_object_event_graphics_id"):
		var resolution = registry.resolve_object_event_graphics_id(graphics_id, _game_state())
		if typeof(resolution) == TYPE_DICTIONARY:
			_graphics_resolution = resolution.duplicate(true)
			_resolved_graphics_id = String(resolution.get("graphics_id", graphics_id))

	var record = registry.get_object_event_sprite_record(_resolved_graphics_id)
	if typeof(record) != TYPE_DICTIONARY or record.is_empty():
		return

	var texture := _load_texture(String(record.get("image", "")))
	if texture == null:
		return

	var frame_size := _frame_size(record)
	if frame_size == Vector2.ZERO:
		return

	var columns := int(record.get("columns", 0))
	if columns <= 0:
		var image_size = record.get("image_size", {})
		if typeof(image_size) == TYPE_DICTIONARY and frame_size.x > 0:
			columns = int(float(image_size.get("w", 0)) / frame_size.x)
	if columns <= 0:
		columns = 1

	var facing_direction := _facing_direction()
	var frame_index := _static_frame_index(record, facing_direction)
	_sprite_record = record.duplicate(true)
	_sprite_texture = texture
	_sprite_flip_h = _static_frame_flip_h(record, facing_direction)
	var frame_row := int(floor(float(frame_index) / float(columns)))
	_sprite_source_rect = Rect2(
		float(frame_index % columns) * frame_size.x,
		float(frame_row) * frame_size.y,
		frame_size.x,
		frame_size.y
	)


func _load_texture(image_path: String) -> Texture2D:
	if image_path.is_empty():
		return null

	var loaded_resource := load(image_path)
	if loaded_resource is Texture2D:
		return loaded_resource

	var image := Image.new()
	if image.load(image_path) != OK:
		push_warning("Could not load generated object event sprite: %s" % image_path)
		return null
	return ImageTexture.create_from_image(image)


func _frame_size(record: Dictionary) -> Vector2:
	var frame_size_info = record.get("frame_size", {})
	if typeof(frame_size_info) != TYPE_DICTIONARY:
		return Vector2.ZERO
	return Vector2(
		float(frame_size_info.get("w", 0)),
		float(frame_size_info.get("h", 0))
	)


func _sprite_dest_rect() -> Rect2:
	var frame_size := _sprite_source_rect.size
	if frame_size == Vector2.ZERO:
		frame_size = Vector2(float(tile_size), float(tile_size) * 2.0)
	return Rect2(
		-frame_size.x * 0.5,
		-frame_size.y + float(tile_size) * 0.5,
		frame_size.x,
		frame_size.y
	)


func _grid_to_world(value: Vector2i) -> Vector2:
	return Vector2(
		value.x * tile_size + tile_size * 0.5,
		value.y * tile_size + tile_size * 0.5
	)


func _static_frame_index(record: Dictionary, facing_direction: String) -> int:
	var static_frames = record.get("static_frames", {})
	if typeof(static_frames) != TYPE_DICTIONARY:
		return 0
	if static_frames.has(facing_direction):
		return int(static_frames.get(facing_direction, 0))
	return int(static_frames.get("down", 0))


func _static_frame_flip_h(record: Dictionary, facing_direction: String) -> bool:
	var static_frame_flips = record.get("static_frame_flips", {})
	if typeof(static_frame_flips) != TYPE_DICTIONARY:
		return false
	var flip_info = static_frame_flips.get(facing_direction, {})
	if typeof(flip_info) != TYPE_DICTIONARY:
		return false
	return bool(flip_info.get("h", false))


func _facing_direction() -> String:
	var facing_direction := String(event_data.get("facing_direction", "")).to_lower()
	if not facing_direction.is_empty():
		return facing_direction

	var movement_type := String(event_data.get("movement_type", "")).to_lower()
	if movement_type.ends_with("face_up"):
		return "up"
	if movement_type.ends_with("face_down"):
		return "down"
	if movement_type.ends_with("face_left"):
		return "left"
	if movement_type.ends_with("face_right"):
		return "right"
	return "down"


func _registry() -> Node:
	if is_inside_tree():
		return get_node_or_null("/root/DataRegistry")
	return null


func _game_state() -> Node:
	if is_inside_tree():
		return get_node_or_null("/root/GameState")
	return null


func _color_from_graphics_id(graphics_id: String) -> Color:
	if graphics_id == "OBJ_EVENT_GFX_TRUCK":
		return Color(0.34, 0.40, 0.46, 1.0)

	var color_index := 0
	for index in range(graphics_id.length()):
		color_index += graphics_id.unicode_at(index)
	return BODY_COLORS[color_index % BODY_COLORS.size()]
