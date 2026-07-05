extends "res://scripts/overworld/grid_mover.gd"

const OVERWORLD_DEPTH := preload("res://scripts/overworld/overworld_depth.gd")

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
const SOURCE_FRAMES_PER_SECOND := 60.0
const NORMAL_STEP_SOURCE_FRAMES := 16
const TURN_IN_PLACE_SOURCE_FRAMES := 8

var _sprite_record: Dictionary = {}
var _sprite_texture: Texture2D = null
var _sprite_source_rect := Rect2()
var _sprite_flip_h := false
var _graphics_id := ""
var _sprite_unsupported: Array = []
var _sprite_frame_size := Vector2.ZERO
var _sprite_columns := 1
var _sprite_frame_index := 0
var _sprite_animation_state := "static"
var _sprite_animation_active := false
var _sprite_animation_elapsed_seconds := 0.0
var _sprite_animation_elapsed_frames := 0
var _sprite_animation_total_frames := 0
var _sprite_animation_table_key := ""
var _sprite_animation_phase_start_index := 0
var _step_anim_cmd_index := 0
var _depth_record: Dictionary = {}


func _ready() -> void:
	tile_size = 16
	_hide_legacy_placeholder_children()
	_configure_player_sprite()
	var game_state := _game_state()
	if game_state != null:
		set_grid_position(game_state.player_grid_position)


func _physics_process(_delta: float) -> void:
	if input_locked or _is_moving or _sprite_animation_active:
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
				"src/field_player_avatar.c:PlayerTurnInPlace",
				"src/event_object_movement.c:GetWalkInPlaceFastMovementAction",
				"src/event_object_movement.c:InitMoveInPlace",
				"src/event_object_movement.c:SetStepAnimHandleAlternation",
				"src/data/object_events/object_event_anims.h:sAnimTable_BrendanMayNormal",
			]
			_start_turn_in_place_animation()
			return
		facing_direction = direction
		var target_position := grid_position + direction
		var map_runtime := _map_runtime()
		if map_runtime != null and map_runtime.can_enter_cell(target_position):
			last_input_source_trace = [
				"src/field_player_avatar.c:CheckMovementInputNotOnBike",
				"src/field_player_avatar.c:PlayerWalkNormal",
				"src/event_object_movement.c:GetWalkNormalMovementAction",
				"src/event_object_movement.c:MovementAction_WalkNormal*_Step0",
				"src/event_object_movement.c:SetStepAnimHandleAlternation",
				"src/event_object_movement.c:SetSpriteDataForNormalStep",
				"src/event_object_movement.c:Step1",
				"src/event_object_movement.c:NpcTakeStep",
				"src/data/object_events/object_event_anims.h:sAnimTable_BrendanMayNormal",
			]
			_configure_player_sprite()
			if try_move(direction):
				_start_normal_walk_animation()
		else:
			last_input_source_trace = [
				"src/field_player_avatar.c:CheckMovementInputNotOnBike",
				"src/field_player_avatar.c:MOVING",
			]
			var cell_info: Dictionary = map_runtime.get_cell_info(target_position) if map_runtime != null else {}
			movement_blocked.emit(target_position, cell_info, facing_direction)


func _process(delta: float) -> void:
	if not _sprite_animation_active:
		return
	_sprite_animation_elapsed_seconds += delta
	var elapsed_frames := int(floor(_sprite_animation_elapsed_seconds * SOURCE_FRAMES_PER_SECOND))
	if _sprite_animation_state == "turning" and elapsed_frames >= _sprite_animation_total_frames:
		_finish_active_sprite_animation()
		return
	_apply_active_sprite_animation_frame(mini(elapsed_frames, _sprite_animation_total_frames - 1))


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
		"animation_state": _sprite_animation_state,
		"animation_frame_index": _sprite_frame_index,
		"animation_elapsed_frames": _sprite_animation_elapsed_frames,
		"animation_total_frames": _sprite_animation_total_frames if _sprite_animation_active else 0,
		"animation_phase_start_index": _sprite_animation_phase_start_index,
		"step_anim_cmd_index": _step_anim_cmd_index,
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
		"depth": _depth_record.duplicate(true),
		"z_index": z_index,
		"unsupported": _sprite_unsupported.duplicate(true),
	}


func set_grid_position(value: Vector2i) -> void:
	super.set_grid_position(value)
	_apply_depth_z_index()


func try_move(direction: Vector2i) -> bool:
	var moved := super.try_move(direction)
	if moved:
		_apply_depth_z_index()
	return moved


func animate_grid_position(value: Vector2i, duration: float) -> void:
	await super.animate_grid_position(value, duration)
	_apply_depth_z_index()


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


func _apply_depth_z_index() -> void:
	_depth_record = OVERWORLD_DEPTH.sprite_depth_record(
		grid_position,
		_current_player_elevation(),
		0
	)
	z_index = int(_depth_record.get("godot_z_index", OVERWORLD_DEPTH.SPRITE_INTERLEAVE_Z_INDEX))
	z_as_relative = true


func _current_player_elevation() -> int:
	var map_runtime := _map_runtime()
	if map_runtime != null and map_runtime.has_method("get_elevation_at"):
		var elevation := int(map_runtime.get_elevation_at(grid_position))
		if elevation >= 0:
			return elevation
	return OVERWORLD_DEPTH.DEFAULT_ELEVATION


func _data_registry() -> Node:
	if is_inside_tree():
		return get_node_or_null("/root/DataRegistry")
	return null


func _game_state() -> Node:
	if is_inside_tree():
		return get_node_or_null("/root/GameState")
	return null


func _map_runtime() -> Node:
	if is_inside_tree():
		return get_node_or_null("/root/MapRuntime")
	return null


func _emit_interaction_request() -> void:
	var map_runtime := _map_runtime()
	var interaction: Dictionary = map_runtime.get_interaction_target(grid_position, facing_direction) if map_runtime != null else {}
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

	var registry := _data_registry()
	if _graphics_id.is_empty() or registry == null or not registry.has_method("get_object_event_sprite_record"):
		queue_redraw()
		return

	var record = registry.get_object_event_sprite_record(_graphics_id)
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
	_sprite_record = record.duplicate(true)
	_sprite_texture = texture
	_sprite_frame_size = frame_size
	_sprite_columns = columns
	_set_sprite_frame(_static_frame_index(record, facing_name), _static_frame_flip_h(record, facing_name))
	_sprite_animation_state = "static"
	_sprite_animation_active = false
	_sprite_animation_elapsed_seconds = 0.0
	_sprite_animation_elapsed_frames = 0
	_sprite_animation_total_frames = 0
	_sprite_animation_table_key = ""
	_sprite_animation_phase_start_index = 0
	var unsupported = record.get("unsupported", [])
	_sprite_unsupported = unsupported.duplicate(true) if typeof(unsupported) == TYPE_ARRAY else []
	queue_redraw()


func _player_graphics_id() -> String:
	var gender := ""
	var game_state := _game_state()
	if game_state != null and game_state.has_method("get_player_gender"):
		gender = String(game_state.get_player_gender()).to_upper()
	elif game_state != null:
		gender = String(game_state.player_gender).to_upper()
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


func _set_sprite_frame(frame_index: int, h_flip: bool) -> void:
	_sprite_frame_index = frame_index
	_sprite_flip_h = h_flip
	var columns: int = maxi(_sprite_columns, 1)
	var frame_row := int(floor(float(frame_index) / float(columns)))
	_sprite_source_rect = Rect2(
		float(frame_index % columns) * _sprite_frame_size.x,
		float(frame_row) * _sprite_frame_size.y,
		_sprite_frame_size.x,
		_sprite_frame_size.y
	)
	queue_redraw()


func _start_normal_walk_animation() -> void:
	_start_step_animation("walking", "walk", NORMAL_STEP_SOURCE_FRAMES)


func _finish_normal_walk_animation() -> void:
	if not _sprite_animation_active or _sprite_animation_state != "walking":
		return
	_finish_active_sprite_animation()


func _start_turn_in_place_animation() -> void:
	_start_step_animation("turning", "fast_walk", TURN_IN_PLACE_SOURCE_FRAMES)


func _start_step_animation(state_name: String, table_key: String, total_frames: int) -> void:
	if _sprite_record.is_empty():
		return
	_sprite_animation_active = true
	_sprite_animation_elapsed_seconds = 0.0
	_sprite_animation_elapsed_frames = 0
	_sprite_animation_total_frames = total_frames
	_sprite_animation_table_key = table_key
	_sprite_animation_phase_start_index = _source_step_anim_phase_start_index()
	_sprite_animation_state = state_name
	_apply_active_sprite_animation_frame(0)


func _finish_active_sprite_animation() -> void:
	if not _sprite_animation_active:
		return
	_step_anim_cmd_index = _finished_step_anim_cmd_index()
	_sprite_animation_active = false
	_sprite_animation_elapsed_seconds = 0.0
	_sprite_animation_elapsed_frames = _sprite_animation_total_frames
	_sprite_animation_total_frames = 0
	_sprite_animation_table_key = ""
	_sprite_animation_state = "static"
	var facing_name := _facing_direction_name()
	_set_sprite_frame(_static_frame_index(_sprite_record, facing_name), _static_frame_flip_h(_sprite_record, facing_name))


func _apply_active_sprite_animation_frame(elapsed_frames: int) -> void:
	if _sprite_record.is_empty():
		return
	var animation_table = _sprite_record.get("animation_table", {})
	if typeof(animation_table) != TYPE_DICTIONARY:
		return
	var keyed_table = animation_table.get(_sprite_animation_table_key, {})
	if typeof(keyed_table) != TYPE_DICTIONARY:
		return
	var sequence = keyed_table.get(_facing_direction_name(), [])
	if typeof(sequence) != TYPE_ARRAY or sequence.is_empty():
		return

	_sprite_animation_elapsed_frames = clampi(elapsed_frames, 0, maxi(_sprite_animation_total_frames - 1, 0))
	var entry := _animation_entry_for_elapsed_frame(
		sequence,
		_sprite_animation_elapsed_frames,
		_sprite_animation_phase_start_index,
		2
	)
	if entry.is_empty():
		return
	_set_sprite_frame(int(entry.get("frame", 0)), bool(entry.get("h_flip", false)))


func _animation_entry_for_elapsed_frame(
	sequence: Array,
	elapsed_frames: int,
	start_index: int,
	entry_count: int
) -> Dictionary:
	var remaining := elapsed_frames
	var end_index: int = mini(start_index + entry_count, sequence.size())
	for index in range(start_index, end_index):
		var entry = sequence[index]
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var duration: int = maxi(int(entry.get("duration_frames", 1)), 1)
		if remaining < duration:
			return entry
		remaining -= duration
	for i in range(end_index - 1, start_index - 1, -1):
		var fallback = sequence[i]
		if typeof(fallback) == TYPE_DICTIONARY:
			return fallback
	return {}


func _source_step_anim_phase_start_index() -> int:
	if _step_anim_cmd_index == 1:
		return 2
	if _step_anim_cmd_index == 3:
		return 0
	return clampi(_step_anim_cmd_index, 0, 3)


func _finished_step_anim_cmd_index() -> int:
	var sequence := _active_animation_sequence()
	if sequence.is_empty():
		return _step_anim_cmd_index
	var end_index: int = mini(_sprite_animation_phase_start_index + 1, sequence.size() - 1)
	return end_index


func _active_animation_sequence() -> Array:
	if _sprite_record.is_empty() or _sprite_animation_table_key.is_empty():
		return []
	var animation_table = _sprite_record.get("animation_table", {})
	if typeof(animation_table) != TYPE_DICTIONARY:
		return []
	var keyed_table = animation_table.get(_sprite_animation_table_key, {})
	if typeof(keyed_table) != TYPE_DICTIONARY:
		return []
	var sequence = keyed_table.get(_facing_direction_name(), [])
	return sequence if typeof(sequence) == TYPE_ARRAY else []


func _on_move_finished() -> void:
	_finish_normal_walk_animation()
	super._on_move_finished()
