class_name PlatinumFollowCamera
extends Camera3D

@export_node_path("Node3D") var target_path: NodePath
@export_node_path("Node3D") var pixel_snap_anchor_path: NodePath
@export_group("Projection")
@export_range(1.0, 32.0, 0.01) var orthographic_size := 11.24
@export_range(20.0, 120.0, 1.0) var perspective_fov := 75.0
@export_group("Follow")
@export_range(2.0, 64.0, 0.25) var orthographic_follow_distance := 16.0
@export_range(2.0, 30.0, 0.25) var perspective_follow_distance := 8.0
@export_range(0.0, 4.0, 0.05) var target_height := 0.9
@export_range(1.0, 15.0, 0.5) var wheel_pitch_step := 5.0
@export_range(10.0, 80.0, 1.0) var minimum_downward_pitch := 35.0
@export_range(20.0, 89.0, 1.0) var maximum_downward_pitch := 80.0

var _target: Node3D
var _pixel_snap_anchor: Node3D
var _pixel_snap_anchor_base_position := Vector3.ZERO
var _pitch := -50.0
var _pixel_snap_enabled := false
var _last_unsnapped_global_position := Vector3.ZERO


func _ready() -> void:
	process_priority = 10
	_set_projection(Camera3D.PROJECTION_ORTHOGONAL)
	_pitch = clampf(rotation_degrees.x, -maximum_downward_pitch, -minimum_downward_pitch)
	_target = get_node_or_null(target_path) as Node3D
	_pixel_snap_anchor = get_node_or_null(pixel_snap_anchor_path) as Node3D
	if _pixel_snap_anchor != null:
		_pixel_snap_anchor_base_position = _pixel_snap_anchor.position
	if _target == null:
		push_error("Follow camera target was not found: %s" % target_path)
		set_physics_process(false)
		return
	snap_to_target()


func _physics_process(_delta: float) -> void:
	snap_to_target()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		var is_f1 := key_event.keycode == KEY_F1 or key_event.physical_keycode == KEY_F1
		if key_event.pressed and not key_event.echo and is_f1:
			toggle_projection()
			get_viewport().set_input_as_handled()
		return
	if not event is InputEventMouseButton:
		return
	var mouse_button := event as InputEventMouseButton
	if not mouse_button.pressed:
		return
	if mouse_button.button_index == MOUSE_BUTTON_WHEEL_UP:
		_set_pitch(_pitch - wheel_pitch_step)
	elif mouse_button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_set_pitch(_pitch + wheel_pitch_step)


func snap_to_target() -> void:
	if _target == null:
		return
	var focus := _target.global_position + Vector3.UP * target_height
	var pitch_radians := deg_to_rad(-_pitch)
	var follow_distance := get_active_follow_distance()
	_last_unsnapped_global_position = focus + Vector3(
		0.0,
		sin(pitch_radians) * follow_distance,
		cos(pitch_radians) * follow_distance
	)
	global_position = _last_unsnapped_global_position
	rotation_degrees = Vector3(_pitch, 0.0, 0.0)
	if _pixel_snap_enabled and projection == Camera3D.PROJECTION_ORTHOGONAL:
		_snap_to_orthographic_pixel_grid()
	_apply_pixel_snap_anchor_offset(global_position - _last_unsnapped_global_position)


func get_follow_target() -> Node3D:
	return _target


func get_active_follow_distance() -> float:
	return (
		orthographic_follow_distance
		if projection == Camera3D.PROJECTION_ORTHOGONAL
		else perspective_follow_distance
	)


func set_pixel_snap_enabled(enabled: bool) -> void:
	_pixel_snap_enabled = enabled
	snap_to_target()


func is_pixel_snap_enabled() -> bool:
	return _pixel_snap_enabled


func is_pixel_snap_active() -> bool:
	return (
		_pixel_snap_enabled
		and projection == Camera3D.PROJECTION_ORTHOGONAL
		and get_world_units_per_pixel() > 0.0
	)


func get_world_units_per_pixel() -> float:
	var viewport_height := get_viewport().get_visible_rect().size.y
	if viewport_height <= 0.0:
		return 0.0
	return size / viewport_height


func get_unsnapped_global_position() -> Vector3:
	return _last_unsnapped_global_position


func toggle_projection() -> void:
	if projection == Camera3D.PROJECTION_ORTHOGONAL:
		_set_projection(Camera3D.PROJECTION_PERSPECTIVE)
	else:
		_set_projection(Camera3D.PROJECTION_ORTHOGONAL)
	print("CAMERA_PROJECTION ", get_projection_name())


func get_projection_name() -> String:
	return "orthographic" if projection == Camera3D.PROJECTION_ORTHOGONAL else "perspective"


func _set_pitch(value: float) -> void:
	_pitch = clampf(value, -maximum_downward_pitch, -minimum_downward_pitch)
	snap_to_target()


func _set_projection(value: Camera3D.ProjectionType) -> void:
	projection = value
	if projection == Camera3D.PROJECTION_ORTHOGONAL:
		size = orthographic_size
	else:
		fov = perspective_fov
	snap_to_target()


func _snap_to_orthographic_pixel_grid() -> void:
	var world_units_per_pixel := get_world_units_per_pixel()
	if world_units_per_pixel <= 0.0:
		return
	var camera_basis := global_basis.orthonormalized()
	var camera_right := camera_basis.x
	var camera_up := camera_basis.y
	var right_coordinate := _last_unsnapped_global_position.dot(camera_right)
	var up_coordinate := _last_unsnapped_global_position.dot(camera_up)
	var right_offset := snappedf(right_coordinate, world_units_per_pixel) - right_coordinate
	var up_offset := snappedf(up_coordinate, world_units_per_pixel) - up_coordinate
	global_position = (
		_last_unsnapped_global_position
		+ camera_right * right_offset
		+ camera_up * up_offset
	)


func _apply_pixel_snap_anchor_offset(world_offset: Vector3) -> void:
	if _pixel_snap_anchor == null:
		return
	var anchor_parent := _pixel_snap_anchor.get_parent_node_3d()
	if anchor_parent == null:
		_pixel_snap_anchor.position = _pixel_snap_anchor_base_position
		return
	var local_offset := anchor_parent.global_basis.inverse() * world_offset
	_pixel_snap_anchor.position = _pixel_snap_anchor_base_position + local_offset
