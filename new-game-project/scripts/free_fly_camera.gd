extends Camera3D

@export_range(1.0, 200.0, 1.0) var move_speed := 28.0
@export_range(1.0, 10.0, 0.5) var sprint_multiplier := 3.0
@export_range(0.01, 1.0, 0.01) var look_sensitivity := 0.12
@export_range(1.0, 15.0, 0.5) var wheel_pitch_step := 5.0

var _looking := false
var _pitch := 0.0


func _ready() -> void:
	_pitch = rotation_degrees.x


func _process(delta: float) -> void:
	var direction := Vector3.ZERO
	if Input.is_action_pressed("camera_forward"):
		direction -= global_basis.z
	if Input.is_action_pressed("camera_backward"):
		direction += global_basis.z
	if Input.is_action_pressed("camera_left"):
		direction -= global_basis.x
	if Input.is_action_pressed("camera_right"):
		direction += global_basis.x
	if Input.is_action_pressed("camera_up"):
		direction += Vector3.UP
	if Input.is_action_pressed("camera_down"):
		direction += Vector3.DOWN

	if direction.is_zero_approx():
		return
	var speed := move_speed
	if Input.is_action_pressed("camera_sprint"):
		speed *= sprint_multiplier
	global_position += direction.normalized() * speed * delta


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		if mouse_button.button_index == MOUSE_BUTTON_RIGHT:
			_looking = mouse_button.pressed
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if _looking else Input.MOUSE_MODE_VISIBLE
		elif mouse_button.pressed and mouse_button.button_index == MOUSE_BUTTON_WHEEL_UP:
			_set_pitch(_pitch - wheel_pitch_step)
		elif mouse_button.pressed and mouse_button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_set_pitch(_pitch + wheel_pitch_step)
	elif event is InputEventMouseMotion and _looking:
		var mouse_motion := event as InputEventMouseMotion
		rotation_degrees.y -= mouse_motion.relative.x * look_sensitivity
		_set_pitch(_pitch - mouse_motion.relative.y * look_sensitivity)


func _set_pitch(value: float) -> void:
	_pitch = clampf(value, -89.0, 89.0)
	rotation_degrees.x = _pitch
