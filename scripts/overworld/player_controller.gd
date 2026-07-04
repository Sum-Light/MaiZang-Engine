extends "res://scripts/overworld/grid_mover.gd"

signal movement_blocked(target_position: Vector2i, cell_info: Dictionary, facing_direction: Vector2i)
signal interaction_requested(
	origin_position: Vector2i,
	target_position: Vector2i,
	facing_direction: Vector2i,
	interaction: Dictionary
)

var facing_direction := Vector2i.DOWN
var input_locked := false
var field_input_precheck := Callable()
var last_input_source_trace: Array = []
var _sprite_record: Dictionary = {}
var _sprite_texture: Texture2D = null
var _sprite_source_rect := Rect2()
var _sprite_flip_h := false
var _graphics_id := ""
var _sprite_unsupported: Array = []


func _ready() -> void:
	tile_size = DataRegistry.TILE_SIZE
	_hide_legacy_placeholder_children()
	_configure_player_sprite()
	set_grid_position(GameState.player_grid_position)


func _physics_process(_delta: float) -> void:
	if input_locked or _is_moving:
		return

	if field_input_precheck.is_valid() and bool(field_input_precheck.call()):
		return

	if Input.is_action_just_pressed("ui_accept"):
		_emit_interaction_request()
		return

	var direction := _read_input_direction()
	if direction != Vector2i.ZERO:
		if direction != facing_direction:
			facing_direction = direction
			_configure_player_sprite()
			last_input_source_trace = [
				"src/field_player_avatar.c:CheckMovementInputNotOnBike",
				"src/field_player_avatar.c:TURN_DIRECTION",
			]
			return
		facing_direction = direction
		var target_position := grid_position + direction
		if MapRuntime.can_enter_cell(target_position):
			last_input_source_trace = [
				"src/field_player_avatar.c:CheckMovementInputNotOnBike",
				"src/event_object_movement.c:SetSpriteDataForNormalStep",
				"src/event_object_movement.c:Step1",
			]
			_configure_player_sprite()
			try_move(direction)
		else:
			last_input_source_trace = [
				"src/field_player_avatar.c:CheckMovementInputNotOnBike",
				"src/field_player_avatar.c:MOVING",
			]
			movement_blocked.emit(target_position, MapRuntime.get_cell_info(target_position), facing_direction)


func _draw() -> void:
	if _sprite_texture == null:
		return
	draw_rect(Rect2(-6, 5, 12, 4), Color(0.05, 0.07, 0.06, 0.35), true)
	var dest_rect := _sprite_dest_rect()
	if _sprite_flip_h:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(-1.0, 1.0))
	draw_texture_rect_region(_sprite_texture, dest_rect, _sprite_source_rect)
	if _sprite_flip_h:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func set_input_locked(value: bool) -> void:
	input_locked = value


func configure_field_input_precheck(callback: Callable) -> void:
	field_input_precheck = callback


func get_sprite_snapshot() -> Dictionary:
	return {
		"using_sprite": _sprite_texture != null,
		"graphics_id": _graphics_id,
		"facing_direction": _facing_direction_name(),
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
		"unsupported": _sprite_unsupported.duplicate(true),
	}


func _read_input_direction() -> Vector2i:
	if Input.is_action_pressed("ui_up"):
		return Vector2i.UP
	if Input.is_action_pressed("ui_down"):
		return Vector2i.DOWN
	if Input.is_action_pressed("ui_left"):
		return Vector2i.LEFT
	if Input.is_action_pressed("ui_right"):
		return Vector2i.RIGHT
	return Vector2i.ZERO


func _emit_interaction_request() -> void:
	var interaction := MapRuntime.get_interaction_target(grid_position, facing_direction)
	interaction_requested.emit(
		grid_position,
		grid_position + facing_direction,
		facing_direction,
		interaction
	)


func _hide_legacy_placeholder_children() -> void:
	for child in get_children():
		if child is CanvasItem:
			child.visible = false


func _configure_player_sprite() -> void:
	_sprite_record = {}
	_sprite_texture = null
	_sprite_source_rect = Rect2()
	_sprite_flip_h = false
	_sprite_unsupported = []
	_graphics_id = _player_graphics_id()

	if _graphics_id.is_empty() or not DataRegistry.has_method("get_object_event_sprite_record"):
		queue_redraw()
		return

	var record = DataRegistry.get_object_event_sprite_record(_graphics_id)
	if typeof(record) != TYPE_DICTIONARY or record.is_empty():
		queue_redraw()
		return

	var texture := _load_texture(String(record.get("image", "")))
	if texture == null:
		queue_redraw()
		return

	var frame_size := _frame_size(record)
	if frame_size == Vector2.ZERO:
		queue_redraw()
		return

	var columns := int(record.get("columns", 0))
	if columns <= 0:
		var image_size = record.get("image_size", {})
		if typeof(image_size) == TYPE_DICTIONARY and frame_size.x > 0:
			columns = int(float(image_size.get("w", 0)) / frame_size.x)
	if columns <= 0:
		columns = 1

	var facing_name := _facing_direction_name()
	var frame_index := _static_frame_index(record, facing_name)
	var frame_row := int(floor(float(frame_index) / float(columns)))
	_sprite_record = record.duplicate(true)
	_sprite_texture = texture
	_sprite_flip_h = _static_frame_flip_h(record, facing_name)
	_sprite_source_rect = Rect2(
		float(frame_index % columns) * frame_size.x,
		float(frame_row) * frame_size.y,
		frame_size.x,
		frame_size.y
	)
	var unsupported = record.get("unsupported", [])
	_sprite_unsupported = unsupported.duplicate(true) if typeof(unsupported) == TYPE_ARRAY else []
	queue_redraw()


func _player_graphics_id() -> String:
	var gender := ""
	if GameState != null and GameState.has_method("get_player_gender"):
		gender = String(GameState.get_player_gender()).to_upper()
	else:
		gender = String(GameState.player_gender).to_upper()
	if gender == "FEMALE":
		return "OBJ_EVENT_GFX_MAY_NORMAL"
	return "OBJ_EVENT_GFX_BRENDAN_NORMAL"


func _facing_direction_name() -> String:
	match facing_direction:
		Vector2i.UP:
			return "up"
		Vector2i.LEFT:
			return "left"
		Vector2i.RIGHT:
			return "right"
		_:
			return "down"


func _load_texture(image_path: String) -> Texture2D:
	if image_path.is_empty():
		return null
	var loaded_resource := load(image_path)
	if loaded_resource is Texture2D:
		return loaded_resource
	var image := Image.new()
	if image.load(image_path) != OK:
		push_warning("Could not load generated player object event sprite: %s" % image_path)
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


func _static_frame_index(record: Dictionary, facing_name: String) -> int:
	var static_frames = record.get("static_frames", {})
	if typeof(static_frames) != TYPE_DICTIONARY:
		return 0
	if static_frames.has(facing_name):
		return int(static_frames.get(facing_name, 0))
	return int(static_frames.get("down", 0))


func _static_frame_flip_h(record: Dictionary, facing_name: String) -> bool:
	var static_frame_flips = record.get("static_frame_flips", {})
	if typeof(static_frame_flips) != TYPE_DICTIONARY:
		return false
	var flip_info = static_frame_flips.get(facing_name, {})
	if typeof(flip_info) != TYPE_DICTIONARY:
		return false
	return bool(flip_info.get("h", false))
