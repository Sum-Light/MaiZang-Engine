extends Node

const PLAYER_GENDER_MALE := "MALE"
const PLAYER_GENDER_FEMALE := "FEMALE"
const DEFAULT_PLAYER_NAME := "玩家"
const PLAYER_NAME_LENGTH := 7

var current_map_id := "MAP_LITTLEROOT_TOWN"
var player_gender := PLAYER_GENDER_MALE
var player_name := DEFAULT_PLAYER_NAME
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


func set_player_gender(gender: String) -> void:
	var normalized := gender.strip_edges().to_upper()
	player_gender = PLAYER_GENDER_FEMALE if normalized == PLAYER_GENDER_FEMALE else PLAYER_GENDER_MALE


func get_player_gender() -> String:
	return player_gender


func set_player_name(name: String) -> void:
	var normalized := name.strip_edges()
	if normalized.is_empty():
		player_name = DEFAULT_PLAYER_NAME
		return
	player_name = normalized.substr(0, PLAYER_NAME_LENGTH)


func get_player_name() -> String:
	return player_name
