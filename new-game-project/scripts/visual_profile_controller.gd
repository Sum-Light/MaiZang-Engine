class_name PlatinumVisualProfileController
extends Node

signal profile_changed(profile_name: StringName)

const CLASSIC_PROFILE := &"classic"
const HD2D_PROFILE := &"hd2d"
const VisualProfileResource := preload("res://scripts/visual_profile.gd")

@export_node_path("WorldEnvironment") var world_environment_path: NodePath
@export_node_path("DirectionalLight3D") var sun_path: NodePath
@export_node_path("PlatinumFollowCamera") var camera_path: NodePath
@export_node_path("MeshInstance3D") var player_shadow_path: NodePath
@export_node_path("Sprite3D") var player_sprite_path: NodePath
@export var classic_profile: VisualProfileResource
@export var hd2d_profile: VisualProfileResource
@export var default_profile: StringName = CLASSIC_PROFILE

var _world_environment: WorldEnvironment
var _sun: DirectionalLight3D
var _camera: PlatinumFollowCamera
var _player_shadow: MeshInstance3D
var _player_sprite: Sprite3D
var _active_profile_name := StringName()


func _ready() -> void:
	add_to_group("platinum_visual_profile")
	_world_environment = get_node_or_null(world_environment_path) as WorldEnvironment
	_sun = get_node_or_null(sun_path) as DirectionalLight3D
	_camera = get_node_or_null(camera_path) as PlatinumFollowCamera
	_player_shadow = get_node_or_null(player_shadow_path) as MeshInstance3D
	_player_sprite = get_node_or_null(player_sprite_path) as Sprite3D
	if not _dependencies_are_valid():
		set_process_unhandled_input(false)
		return
	var runtime_environment := _world_environment.environment.duplicate(true) as Environment
	runtime_environment.resource_local_to_scene = true
	_world_environment.environment = runtime_environment

	var requested_profile := default_profile
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--visual-profile="):
			requested_profile = StringName(argument.trim_prefix("--visual-profile=").to_lower())
	if not set_profile(requested_profile):
		push_warning("Unknown visual profile '%s'; using Classic." % requested_profile)
		set_profile(CLASSIC_PROFILE)


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key_event := event as InputEventKey
	var is_f2 := key_event.keycode == KEY_F2 or key_event.physical_keycode == KEY_F2
	if key_event.pressed and not key_event.echo and is_f2:
		toggle_profile()
		get_viewport().set_input_as_handled()


func set_profile(profile_name: StringName) -> bool:
	var profile := _profile_for_name(profile_name)
	if profile == null:
		return false
	_apply_profile(profile)
	_active_profile_name = profile.profile_name
	profile_changed.emit(_active_profile_name)
	print("VISUAL_PROFILE ", _active_profile_name)
	return true


func toggle_profile() -> void:
	set_profile(HD2D_PROFILE if _active_profile_name == CLASSIC_PROFILE else CLASSIC_PROFILE)


func get_active_profile_name() -> StringName:
	return _active_profile_name


func is_hd2d_enabled() -> bool:
	return _active_profile_name == HD2D_PROFILE


func get_visual_state() -> Dictionary:
	var environment := _world_environment.environment
	return {
		"profile": String(_active_profile_name),
		"fog_enabled": environment.fog_enabled,
		"fog_density": environment.fog_density,
		"adjustment_enabled": environment.adjustment_enabled,
		"pixel_snap_enabled": _camera.is_pixel_snap_enabled(),
		"player_shadow_enabled": _player_shadow.visible,
		"player_sprite_pixel_size": _player_sprite.pixel_size,
		"camera_far": _camera.far,
		"sun_shadow_enabled": _sun.shadow_enabled,
		"sun_shadow_max_distance": _sun.directional_shadow_max_distance,
	}


func _profile_for_name(profile_name: StringName) -> VisualProfileResource:
	match profile_name:
		CLASSIC_PROFILE:
			return classic_profile
		HD2D_PROFILE:
			return hd2d_profile
		_:
			return null


func _apply_profile(profile: VisualProfileResource) -> void:
	var environment := _world_environment.environment
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = profile.background_color
	environment.ambient_light_source = profile.ambient_light_source
	environment.ambient_light_color = profile.ambient_light_color
	environment.ambient_light_energy = profile.ambient_light_energy
	environment.tonemap_mode = profile.tonemap_mode
	environment.tonemap_exposure = profile.tonemap_exposure
	environment.tonemap_white = profile.tonemap_white
	environment.fog_enabled = profile.fog_enabled
	environment.fog_mode = profile.fog_mode
	environment.fog_light_color = profile.fog_light_color
	environment.fog_light_energy = profile.fog_light_energy
	environment.fog_density = profile.fog_density
	environment.fog_depth_begin = profile.fog_depth_begin
	environment.fog_depth_end = profile.fog_depth_end
	environment.fog_depth_curve = profile.fog_depth_curve
	environment.fog_height = profile.fog_height
	environment.fog_height_density = profile.fog_height_density
	environment.fog_aerial_perspective = profile.fog_aerial_perspective
	environment.fog_sun_scatter = profile.fog_sun_scatter
	environment.adjustment_enabled = profile.adjustment_enabled
	environment.adjustment_brightness = profile.adjustment_brightness
	environment.adjustment_contrast = profile.adjustment_contrast
	environment.adjustment_saturation = profile.adjustment_saturation

	_sun.light_color = profile.sun_color
	_sun.light_energy = profile.sun_energy
	_sun.shadow_enabled = profile.sun_shadow_enabled
	_sun.directional_shadow_max_distance = profile.sun_shadow_max_distance
	_camera.far = profile.camera_far
	_player_sprite.pixel_size = profile.player_sprite_pixel_size
	_camera.set_pixel_snap_enabled(profile.pixel_snap_enabled)
	_player_shadow.visible = profile.player_shadow_enabled


func _dependencies_are_valid() -> bool:
	if _world_environment == null or _world_environment.environment == null:
		push_error("Visual profile WorldEnvironment is missing.")
		return false
	if _sun == null:
		push_error("Visual profile DirectionalLight3D is missing.")
		return false
	if _camera == null:
		push_error("Visual profile camera is missing.")
		return false
	if _player_shadow == null:
		push_error("Visual profile player shadow is missing.")
		return false
	if _player_sprite == null:
		push_error("Visual profile player sprite is missing.")
		return false
	if classic_profile == null or hd2d_profile == null:
		push_error("Visual profile resources are missing.")
		return false
	return true
