class_name PlatinumPlayerController
extends CharacterBody3D

enum Facing {
	DOWN,
	UP,
	LEFT,
	RIGHT,
}

const FRAME_COLUMNS := 8
const FRAMES_PER_ACTION := 4

@export_range(0.1, 20.0, 0.1) var walk_speed := 3.0
@export_range(0.1, 30.0, 0.1) var run_speed := 5.5
@export_range(1.0, 30.0, 0.5) var walk_animation_fps := 7.5
@export_range(1.0, 30.0, 0.5) var run_animation_fps := 11.0
@export_file("*.png") var sprite_sheet_path := "res://assets/platinum/characters/dawn_overworld.png"

var _facing := Facing.DOWN
var _animation_time := 0.0
var _is_moving := false
var _is_running := false
var _has_animation_sheet := false

@onready var _sprite := $Sprite3D as Sprite3D


func _ready() -> void:
	_load_sprite_sheet()
	_update_sprite_frame()


func _physics_process(delta: float) -> void:
	var input_vector := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var direction := cardinalize(input_vector)
	_is_moving = not direction.is_zero_approx()
	_is_running = _is_moving and Input.is_action_pressed("player_run")

	if _is_moving:
		var next_facing := _facing_for_direction(direction)
		if next_facing != _facing:
			_facing = next_facing
			_animation_time = 0.0
		_animation_time += delta
		var speed := run_speed if _is_running else walk_speed
		velocity = Vector3(direction.x, 0.0, direction.y) * speed
	else:
		velocity = Vector3.ZERO
		_animation_time = 0.0

	move_and_slide()
	_update_sprite_frame()


static func cardinalize(input_vector: Vector2) -> Vector2:
	if input_vector.is_zero_approx():
		return Vector2.ZERO
	if absf(input_vector.x) > absf(input_vector.y):
		return Vector2(signf(input_vector.x), 0.0)
	return Vector2(0.0, signf(input_vector.y))


func get_current_facing() -> int:
	return _facing


func get_current_sprite_frame() -> int:
	return _sprite.frame


func is_running() -> bool:
	return _is_running


func is_using_local_sprite_sheet() -> bool:
	return _has_animation_sheet


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
	var column := 0
	if _is_moving:
		var frame_rate := run_animation_fps if _is_running else walk_animation_fps
		var action_offset := FRAMES_PER_ACTION if _is_running else 0
		column = action_offset + (floori(_animation_time * frame_rate) % FRAMES_PER_ACTION)
	_sprite.frame = (_facing * FRAME_COLUMNS) + column


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
