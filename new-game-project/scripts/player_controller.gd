class_name PlatinumPlayerController
extends CharacterBody3D

signal step_advanced(step_frame: int, step_duration: int, world_position: Vector3, sprite_frame: int)
signal turn_advanced(turn_frame: int, turn_duration: int, world_position: Vector3, sprite_frame: int)
signal special_action_requested(origin: Vector3, direction: Vector2i, special_result: Dictionary)

enum Facing {
	DOWN,
	UP,
	LEFT,
	RIGHT,
}

enum MotionState {
	READY,
	TURNING,
	STEPPING,
}

enum ActionKind {
	STOP,
	TURN,
	WALK,
}

const FRAME_COLUMNS := 8
const FRAMES_PER_ACTION := 4
const GRID_CELL_SIZE := 1.0
const GRID_CENTER_OFFSET := GRID_CELL_SIZE * 0.5
const SOURCE_FRAME_SCALE := 2
const WALK_STEP_FRAMES := 16
const RUN_STEP_FRAMES := 8
const TURN_FRAMES := 6
const GAIT_CYCLE_FRAMES := 32
const GAIT_POSE_FRAMES := 8
const GAIT_IDLE_ALIGNMENT := 16
const RUN_STOP_HANDOFF_FRAMES := 4
const IDLE_COLUMN := 0
const WALK_FIRST_FOOT_COLUMN := 1
const WALK_SECOND_IDLE_COLUMN := 2
const WALK_SECOND_FOOT_COLUMN := 3
const RUN_START_COLUMN := 4
const RUN_FIRST_FOOT_COLUMN := 5
const RUN_SECOND_IDLE_COLUMN := 6
const RUN_SECOND_FOOT_COLUMN := 7

@export_file("*.png") var sprite_sheet_path := "res://assets/platinum/characters/dawn_overworld.png"

var _facing := Facing.DOWN
var _motion_state := MotionState.READY
var _previous_action := ActionKind.STOP
var _accepted_input_axes := Vector2.ZERO
var _move_direction := Vector2.ZERO
var _step_origin := Vector3.ZERO
var _step_target := Vector3.ZERO
var _action_frame := 0
var _action_duration := WALK_STEP_FRAMES
var _step_running := false
var _animation_running := false
var _gait_frame := 0
var _run_stop_frame := 0
var _has_animation_sheet := false
var _collision_provider: Node
var _collision_context := {"locomotion": "walk", "bridge_layer": "unknown"}
var _pending_collision_context := _collision_context.duplicate()
var _input_enabled := true
var _special_action_latched := false

@onready var _sprite := $Sprite3D as Sprite3D


func _ready() -> void:
	_load_sprite_sheet()
	teleport_to_grid(global_position)


func _physics_process(delta: float) -> void:
	if not _input_enabled:
		return
	if _motion_state == MotionState.TURNING:
		_advance_turn()
		return
	if _motion_state == MotionState.STEPPING:
		_advance_step(delta)
		return

	var input_axes := _read_input_axes()
	var direction := select_cardinal_direction(input_axes, _accepted_input_axes, _move_direction)
	if direction.is_zero_approx():
		_special_action_latched = false
		_settle_idle()
		return

	_accepted_input_axes = input_axes
	var next_facing := _facing_for_direction(direction)
	if next_facing != _facing and _previous_action != ActionKind.WALK:
		_begin_turn(direction, next_facing)
		_advance_turn()
		return

	if _begin_step(direction, next_facing):
		_advance_step(delta)


static func cardinalize(input_vector: Vector2) -> Vector2:
	var input_axes := Vector2(signf(input_vector.x), signf(input_vector.y))
	return select_cardinal_direction(input_axes, Vector2.ZERO, Vector2.ZERO)


static func select_cardinal_direction(
	input_axes: Vector2,
	accepted_input_axes: Vector2,
	move_direction: Vector2
) -> Vector2:
	var horizontal := signf(input_axes.x)
	var vertical := signf(input_axes.y)
	if is_zero_approx(horizontal):
		return Vector2(0.0, vertical)
	if is_zero_approx(vertical):
		return Vector2(horizontal, 0.0)

	if not move_direction.is_zero_approx():
		if (
			is_equal_approx(horizontal, accepted_input_axes.x)
			and is_equal_approx(vertical, accepted_input_axes.y)
		):
			return move_direction
		if not is_equal_approx(vertical, accepted_input_axes.y):
			return Vector2(0.0, vertical)
		return Vector2(horizontal, 0.0)

	return Vector2(0.0, vertical)


func get_current_facing() -> int:
	return _facing


func get_current_sprite_frame() -> int:
	return _sprite.frame


func is_running() -> bool:
	return _motion_state == MotionState.STEPPING and _step_running


func is_stepping() -> bool:
	return _motion_state == MotionState.STEPPING


func is_turning() -> bool:
	return _motion_state == MotionState.TURNING


func get_step_frame() -> int:
	return _action_frame if is_stepping() else 0


func get_step_duration() -> int:
	return _action_duration if is_stepping() else 0


func get_turn_frame() -> int:
	return _action_frame if is_turning() else 0


func get_turn_duration() -> int:
	return TURN_FRAMES


func get_gait_frame() -> int:
	return _gait_frame


func get_step_origin() -> Vector3:
	return _step_origin


func get_step_target() -> Vector3:
	return _step_target


func is_using_local_sprite_sheet() -> bool:
	return _has_animation_sheet


func set_collision_provider(provider: Node) -> void:
	if provider == _collision_provider:
		return
	if is_stepping():
		_cancel_step()
	_collision_provider = provider


func set_input_enabled(enabled: bool) -> void:
	if _input_enabled == enabled:
		return
	_input_enabled = enabled
	_special_action_latched = false
	if enabled:
		return
	if is_stepping():
		_cancel_step()
		return
	if is_turning():
		_cancel_turn()
		return
	velocity = Vector3.ZERO
	_accepted_input_axes = Vector2.ZERO
	_move_direction = Vector2.ZERO
	_previous_action = ActionKind.STOP
	if is_instance_valid(_sprite):
		_settle_idle()


func is_input_enabled() -> bool:
	return _input_enabled


func get_collision_context() -> Dictionary:
	return _collision_context.duplicate(true)


static func snap_to_grid_center(world_position: Vector3) -> Vector3:
	return Vector3(
		floorf(world_position.x / GRID_CELL_SIZE) * GRID_CELL_SIZE + GRID_CENTER_OFFSET,
		world_position.y,
		floorf(world_position.z / GRID_CELL_SIZE) * GRID_CELL_SIZE + GRID_CENTER_OFFSET
	)


func teleport_to_grid(
	world_position: Vector3,
	facing: int = -1,
	collision_context: Dictionary = {}
) -> void:
	var snapped_position := snap_to_grid_center(world_position)
	global_position = snapped_position
	velocity = Vector3.ZERO
	if facing >= 0 and facing < Facing.size():
		_facing = facing
	_motion_state = MotionState.READY
	_previous_action = ActionKind.STOP
	_accepted_input_axes = Vector2.ZERO
	_move_direction = Vector2.ZERO
	_step_origin = snapped_position
	_step_target = snapped_position
	_action_frame = 0
	_action_duration = WALK_STEP_FRAMES
	_step_running = false
	_animation_running = false
	_gait_frame = 0
	_run_stop_frame = 0
	_special_action_latched = false
	_collision_context = _normalized_collision_context(collision_context)
	_pending_collision_context = _collision_context.duplicate()
	if is_instance_valid(_sprite):
		_update_sprite_frame()


func _read_input_axes() -> Vector2:
	var horizontal := 0.0
	if Input.is_action_pressed("move_left"):
		horizontal = -1.0
	elif Input.is_action_pressed("move_right"):
		horizontal = 1.0

	var vertical := 0.0
	if Input.is_action_pressed("move_up"):
		vertical = -1.0
	elif Input.is_action_pressed("move_down"):
		vertical = 1.0
	return Vector2(horizontal, vertical)


func _begin_turn(direction: Vector2, next_facing: int) -> void:
	_facing = next_facing
	_motion_state = MotionState.TURNING
	_previous_action = ActionKind.TURN
	_move_direction = direction
	_action_frame = 0
	_action_duration = TURN_FRAMES
	_step_running = false
	_animation_running = false
	_gait_frame = 0
	_run_stop_frame = 0
	velocity = Vector3.ZERO
	_update_sprite_frame()


func _advance_turn() -> void:
	_action_frame += 1
	if _action_frame <= TURN_FRAMES - SOURCE_FRAME_SCALE and _action_frame % SOURCE_FRAME_SCALE == 0:
		_gait_frame = (_gait_frame + GAIT_POSE_FRAMES) % GAIT_CYCLE_FRAMES
	_update_sprite_frame()
	var emitted_frame := _action_frame
	if _action_frame >= TURN_FRAMES:
		_motion_state = MotionState.READY
		_action_frame = 0
	turn_advanced.emit(emitted_frame, TURN_FRAMES, global_position, get_current_sprite_frame())


func _begin_step(direction: Vector2, next_facing: int) -> bool:
	var direction_changed := next_facing != _facing
	var wants_to_run := Input.is_action_pressed("player_run")
	_prepare_step_animation(wants_to_run, direction_changed)
	_facing = next_facing
	_move_direction = direction
	_step_origin = global_position
	if not _has_collision_provider_contract():
		_stop_before_step()
		return false
	var collision_provider := _collision_provider
	var step_direction := Vector2i(roundi(direction.x), roundi(direction.y))
	var step_value: Variant = collision_provider.call(
		"resolve_player_step",
		_step_origin,
		step_direction,
		_collision_context.duplicate(true)
	)
	if not is_instance_valid(collision_provider) or collision_provider != _collision_provider:
		_stop_before_step()
		return false
	if not step_value is Dictionary:
		_stop_before_step()
		return false
	var step_result := step_value as Dictionary
	var ok_value: Variant = step_result.get("ok", null)
	var blocked_value: Variant = step_result.get("blocked", null)
	var disposition_value: Variant = step_result.get("disposition", null)
	var action_value: Variant = step_result.get("action", null)
	var target_value: Variant = step_result.get("target", null)
	var landing_target_value: Variant = step_result.get("landing_target", null)
	if _is_valid_transition_action(step_result, _step_origin):
		_stop_before_step()
		if not _special_action_latched:
			_special_action_latched = true
			special_action_requested.emit(
				_step_origin,
				step_direction,
				step_result.duplicate(true)
			)
		return false
	if (
		typeof(ok_value) != TYPE_BOOL
		or not ok_value
		or typeof(blocked_value) != TYPE_BOOL
		or blocked_value
		or typeof(disposition_value) != TYPE_STRING
		or disposition_value != "allow"
		or typeof(action_value) != TYPE_STRING
		or action_value != "none"
		or not target_value is Vector3
		or not landing_target_value is Vector3
		or not (landing_target_value as Vector3).is_equal_approx(target_value as Vector3)
	):
		_stop_before_step()
		return false
	_step_target = target_value as Vector3
	if not _is_valid_normal_step_target(_step_target, step_direction):
		_stop_before_step()
		return false
	var next_context_value: Variant = step_result.get("next_context", null)
	if (
		not next_context_value is Dictionary
		or not _is_valid_collision_context(next_context_value as Dictionary)
	):
		_stop_before_step()
		return false
	_pending_collision_context = _normalized_collision_context(next_context_value as Dictionary)
	var collision := move_and_collide(_step_target - _step_origin, true)
	if collision != null:
		_stop_before_step()
		return false

	_motion_state = MotionState.STEPPING
	_previous_action = ActionKind.WALK
	_action_frame = 0
	_action_duration = RUN_STEP_FRAMES if wants_to_run else WALK_STEP_FRAMES
	_step_running = wants_to_run
	_special_action_latched = false
	return true


func _prepare_step_animation(wants_to_run: bool, direction_changed: bool) -> void:
	_run_stop_frame = 0
	if direction_changed:
		_gait_frame = 0
	elif wants_to_run != _animation_running:
		if wants_to_run:
			_gait_frame = floori(
				float(_gait_frame) / float(GAIT_POSE_FRAMES)
			) * GAIT_POSE_FRAMES
		else:
			_gait_frame = _align_gait_to_idle(_gait_frame)
	_animation_running = wants_to_run


func _advance_step(delta: float) -> void:
	var collision_provider := _collision_provider
	if not is_instance_valid(collision_provider):
		_cancel_step()
		return
	_action_frame += 1
	var progress := float(_action_frame) / float(_action_duration)
	var desired_position := _step_origin.lerp(_step_target, progress)
	var sampled_height: Variant = collision_provider.call(
		"resolve_player_height", desired_position, global_position.y
	)
	if (
		_motion_state != MotionState.STEPPING
		or not is_instance_valid(collision_provider)
		or collision_provider != _collision_provider
	):
		if _motion_state == MotionState.STEPPING:
			_cancel_step()
		return
	if sampled_height == null or not sampled_height is float and not sampled_height is int:
		_cancel_step()
		return
	var resolved_height := float(sampled_height)
	if is_nan(resolved_height) or is_inf(resolved_height):
		_cancel_step()
		return
	desired_position.y = resolved_height
	var motion := desired_position - global_position
	velocity = motion / maxf(delta, 0.000001)
	var collision := move_and_collide(motion)
	if collision != null:
		_cancel_step()
		return

	_gait_frame = (_gait_frame + 1) % GAIT_CYCLE_FRAMES
	_update_sprite_frame()
	var emitted_frame := _action_frame
	var emitted_duration := _action_duration
	if _action_frame >= _action_duration:
		_step_target = Vector3(_step_target.x, desired_position.y, _step_target.z)
		global_position = _step_target
		_collision_context = _pending_collision_context.duplicate(true)
		velocity = Vector3.ZERO
		_motion_state = MotionState.READY
		_action_frame = 0
		_step_running = false
	step_advanced.emit(
		emitted_frame,
		emitted_duration,
		global_position,
		get_current_sprite_frame()
	)


func _cancel_step() -> void:
	global_position = _step_origin
	velocity = Vector3.ZERO
	_step_target = _step_origin
	_pending_collision_context = _collision_context.duplicate(true)
	_motion_state = MotionState.READY
	_previous_action = ActionKind.STOP
	_action_frame = 0
	_step_running = false
	_animation_running = false
	_gait_frame = _align_gait_to_idle(_gait_frame)
	_run_stop_frame = 0
	_update_sprite_frame()


func _cancel_turn() -> void:
	velocity = Vector3.ZERO
	_motion_state = MotionState.READY
	_previous_action = ActionKind.STOP
	_accepted_input_axes = Vector2.ZERO
	_move_direction = Vector2.ZERO
	_action_frame = 0
	_action_duration = WALK_STEP_FRAMES
	_step_running = false
	_animation_running = false
	_gait_frame = _align_gait_to_idle(_gait_frame)
	_run_stop_frame = 0
	if is_instance_valid(_sprite):
		_update_sprite_frame()


func _stop_before_step() -> void:
	_previous_action = ActionKind.STOP
	_step_target = _step_origin
	_pending_collision_context = _collision_context.duplicate(true)
	_step_running = false
	_animation_running = false
	_gait_frame = _align_gait_to_idle(_gait_frame)
	velocity = Vector3.ZERO
	_update_sprite_frame()


func _has_collision_provider_contract() -> bool:
	return (
		is_instance_valid(_collision_provider)
		and _collision_provider.has_method("resolve_player_step")
		and _collision_provider.has_method("resolve_player_height")
	)


func _is_finite_vector3(value: Vector3) -> bool:
	return (
		not is_nan(value.x)
		and not is_inf(value.x)
		and not is_nan(value.y)
		and not is_inf(value.y)
		and not is_nan(value.z)
		and not is_inf(value.z)
	)


func _is_valid_normal_step_target(target: Vector3, direction: Vector2i) -> bool:
	return (
		_is_finite_vector3(target)
		and is_equal_approx(target.x, _step_origin.x + direction.x * GRID_CELL_SIZE)
		and is_equal_approx(target.z, _step_origin.z + direction.y * GRID_CELL_SIZE)
	)


func _is_valid_transition_action(result: Dictionary, origin: Vector3) -> bool:
	var ok_value: Variant = result.get("ok", null)
	var blocked_value: Variant = result.get("blocked", null)
	var disposition_value: Variant = result.get("disposition", null)
	var action_value: Variant = result.get("action", null)
	var reason_value: Variant = result.get("reason", null)
	var target_value: Variant = result.get("target", null)
	var landing_target_value: Variant = result.get("landing_target", false)
	var forced_direction_value: Variant = result.get("forced_direction", false)
	var attributes_value: Variant = result.get("attributes", null)
	var behavior_value: Variant = result.get("behavior", null)
	var height_delta_value: Variant = result.get("height_delta", null)
	var next_context_value: Variant = result.get("next_context", null)
	if (
		typeof(ok_value) != TYPE_BOOL
		or not ok_value
		or typeof(blocked_value) != TYPE_BOOL
		or not blocked_value
		or typeof(disposition_value) != TYPE_STRING
		or disposition_value != "special"
		or typeof(action_value) != TYPE_STRING
		or action_value != "transition"
		or typeof(reason_value) != TYPE_STRING
		or reason_value != "special_behavior"
		or not target_value is Vector3
		or not (target_value as Vector3).is_equal_approx(origin)
		or not _is_finite_vector3(target_value as Vector3)
		or landing_target_value != null
		or forced_direction_value != null
		or typeof(attributes_value) != TYPE_INT
		or typeof(behavior_value) != TYPE_INT
		or typeof(height_delta_value) not in [TYPE_INT, TYPE_FLOAT]
		or not is_zero_approx(float(height_delta_value))
		or not next_context_value is Dictionary
	):
		return false
	return _is_valid_collision_context(next_context_value as Dictionary)


func _is_valid_collision_context(context: Dictionary) -> bool:
	if not context.has("bridge_layer") or not context.has("locomotion"):
		return false
	var bridge_layer: Variant = context.bridge_layer
	var locomotion: Variant = context.locomotion
	return (
		typeof(bridge_layer) == TYPE_STRING
		and bridge_layer in ["ground", "elevated", "unknown"]
		and typeof(locomotion) == TYPE_STRING
		and not locomotion.is_empty()
	)


func _normalized_collision_context(context: Dictionary) -> Dictionary:
	var bridge_layer := String(context.get("bridge_layer", "unknown"))
	if bridge_layer not in ["ground", "elevated", "unknown"]:
		bridge_layer = "unknown"
	var locomotion := String(context.get("locomotion", "walk"))
	if locomotion.is_empty():
		locomotion = "walk"
	return {
		"locomotion": locomotion,
		"bridge_layer": bridge_layer,
	}


func _settle_idle() -> void:
	velocity = Vector3.ZERO
	_previous_action = ActionKind.STOP
	_accepted_input_axes = Vector2.ZERO
	_move_direction = Vector2.ZERO

	if _animation_running:
		_run_stop_frame += 1
		if _run_stop_frame >= RUN_STOP_HANDOFF_FRAMES:
			_animation_running = false
			_gait_frame = _align_gait_to_idle(_gait_frame)
			_run_stop_frame = 0
	else:
		_gait_frame = _align_gait_to_idle(_gait_frame)
		_run_stop_frame = 0
	_update_sprite_frame()


func _align_gait_to_idle(gait_frame: int) -> int:
	return floori(
		float(gait_frame) / float(GAIT_IDLE_ALIGNMENT)
	) * GAIT_IDLE_ALIGNMENT


func _facing_for_direction(direction: Vector2) -> int:
	if direction.y > 0.0:
		return Facing.DOWN
	if direction.y < 0.0:
		return Facing.UP
	if direction.x < 0.0:
		return Facing.LEFT
	return Facing.RIGHT


func _update_sprite_frame() -> void:
	if not _has_animation_sheet:
		_sprite.frame = 0
		return
	var action_column := FRAMES_PER_ACTION if _animation_running else 0
	var gait_column := floori(float(_gait_frame) / float(GAIT_POSE_FRAMES))
	_sprite.frame = (_facing * FRAME_COLUMNS) + action_column + gait_column


func _load_sprite_sheet() -> void:
	if ResourceLoader.exists(sprite_sheet_path):
		var texture := load(sprite_sheet_path) as Texture2D
		if texture != null:
			_sprite.texture = texture
			_sprite.hframes = FRAME_COLUMNS
			_sprite.vframes = Facing.size()
			_has_animation_sheet = true
			return

	push_warning("Dawn sprite atlas is missing; run tools/import_player_sprite.ps1.")
	var fallback_image := Image.create_empty(2, 2, false, Image.FORMAT_RGBA8)
	fallback_image.fill(Color(0.9, 0.2, 0.55, 1.0))
	_sprite.texture = ImageTexture.create_from_image(fallback_image)
	_sprite.hframes = 1
	_sprite.vframes = 1
	_sprite.pixel_size = 0.75
