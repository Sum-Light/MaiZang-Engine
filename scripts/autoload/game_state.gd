extends Node

var current_map_id := "MAP_LITTLEROOT_TOWN"
var player_grid_position := Vector2i(10, 10)
var flags: Dictionary = {}
var vars: Dictionary = {}


func set_flag(flag_name: String, enabled := true) -> void:
	flags[flag_name] = enabled


func is_flag_set(flag_name: String) -> bool:
	return bool(flags.get(flag_name, false))


func clear_flag(flag_name: String) -> void:
	flags.erase(flag_name)


func set_var(var_name: String, value: int) -> void:
	vars[var_name] = value


func get_var(var_name: String, default_value := 0) -> int:
	return int(vars.get(var_name, default_value))
