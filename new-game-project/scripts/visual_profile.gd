class_name PlatinumVisualProfile
extends Resource

@export var profile_name: StringName = &"classic"

@export_group("Environment")
@export var background_color := Color(0.43, 0.58, 0.67, 1.0)
@export var ambient_light_source := 3
@export var ambient_light_color := Color(0.8, 0.84, 0.78, 1.0)
@export_range(0.0, 8.0, 0.01) var ambient_light_energy := 0.8
@export var tonemap_mode := 0
@export_range(0.1, 8.0, 0.01) var tonemap_exposure := 1.0
@export_range(0.1, 16.0, 0.01) var tonemap_white := 1.0

@export_group("Fog")
@export var fog_enabled := false
@export var fog_mode := 0
@export var fog_light_color := Color(0.518, 0.553, 0.608, 1.0)
@export_range(0.0, 8.0, 0.01) var fog_light_energy := 1.0
@export_range(0.0, 1.0, 0.0001) var fog_density := 0.01
@export_range(0.0, 4096.0, 0.1) var fog_depth_begin := 10.0
@export_range(0.1, 4096.0, 0.1) var fog_depth_end := 100.0
@export_range(0.01, 8.0, 0.01) var fog_depth_curve := 1.0
@export_range(-1024.0, 1024.0, 0.1) var fog_height := 0.0
@export_range(-16.0, 16.0, 0.001) var fog_height_density := 0.0
@export_range(0.0, 1.0, 0.01) var fog_aerial_perspective := 0.0
@export_range(0.0, 1.0, 0.01) var fog_sun_scatter := 0.0

@export_group("Adjustments")
@export var glow_enabled := false
@export var adjustment_enabled := false
@export_range(0.01, 8.0, 0.01) var adjustment_brightness := 1.0
@export_range(0.01, 8.0, 0.01) var adjustment_contrast := 1.0
@export_range(0.0, 8.0, 0.01) var adjustment_saturation := 1.0

@export_group("Sun")
@export var sun_color := Color(1.0, 0.94, 0.82, 1.0)
@export_range(0.0, 16.0, 0.01) var sun_energy := 1.2
@export var sun_shadow_enabled := true
@export_range(0.0, 4096.0, 0.5) var sun_shadow_max_distance := 160.0

@export_group("Camera and Player")
@export_range(1.0, 4096.0, 1.0) var camera_far := 2500.0
@export var pixel_snap_enabled := false
@export var player_shadow_enabled := false
@export_range(0.001, 1.0, 0.000001) var player_sprite_pixel_size := 0.06
