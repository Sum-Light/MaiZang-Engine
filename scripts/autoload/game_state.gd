extends Node

const PLAYER_GENDER_MALE := "MALE"
const PLAYER_GENDER_FEMALE := "FEMALE"
const DEFAULT_PLAYER_NAME := "玩家"
const PLAYER_NAME_LENGTH := 7
const PARTY_SIZE := 6

var current_map_id := "MAP_LITTLEROOT_TOWN"
var player_gender := PLAYER_GENDER_MALE
var player_name := DEFAULT_PLAYER_NAME
var player_grid_position := Vector2i(10, 10)
var player_party: Array = []
var flags: Dictionary = {}
var vars: Dictionary = {}
var game_stats: Dictionary = {}


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


func set_game_stat(stat_name: String, value: int) -> void:
	game_stats[stat_name] = maxi(0, value)


func get_game_stat(stat_name: String, default_value := 0) -> int:
	return int(game_stats.get(stat_name, default_value))


func increment_game_stat(stat_name: String, amount := 1) -> int:
	var value: int = maxi(0, get_game_stat(stat_name, 0) + amount)
	game_stats[stat_name] = value
	return value


func get_game_stats() -> Dictionary:
	return game_stats.duplicate(true)


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


func set_player_party(party: Array) -> void:
	player_party = party.duplicate(true)
	if player_party.size() > PARTY_SIZE:
		player_party.resize(PARTY_SIZE)
	_refresh_party_indexes()


func get_player_party() -> Array:
	return player_party.duplicate(true)


func clear_player_party() -> void:
	player_party = []


func calculate_player_party_count() -> int:
	var count := 0
	for mon in player_party:
		if typeof(mon) != TYPE_DICTIONARY:
			break
		if _party_mon_species(mon).is_empty() or _party_mon_species(mon) == "SPECIES_NONE":
			break
		count += 1
		if count >= PARTY_SIZE:
			break
	return count


func get_player_party_count() -> int:
	return calculate_player_party_count()


func get_party_mon(index: int) -> Dictionary:
	if index < 0 or index >= player_party.size():
		return {}
	var mon = player_party[index]
	return mon.duplicate(true) if typeof(mon) == TYPE_DICTIONARY else {}


func set_party_mon(index: int, mon: Dictionary) -> Dictionary:
	if index < 0 or index >= PARTY_SIZE:
		return {"status": "error", "error": "invalid_party_index"}
	if index > player_party.size():
		return {"status": "error", "error": "party_gap_not_supported"}
	var stored := mon.duplicate(true)
	stored["party_index"] = index
	if index == player_party.size():
		player_party.append(stored)
	else:
		player_party[index] = stored
	_refresh_party_indexes()
	return {"status": "ok", "party_count": calculate_player_party_count()}


func add_party_mon(mon: Dictionary) -> Dictionary:
	if calculate_player_party_count() >= PARTY_SIZE:
		return {"status": "blocked", "block_reason": "party_full"}
	var stored := mon.duplicate(true)
	stored["party_index"] = player_party.size()
	player_party.append(stored)
	return {
		"status": "ok",
		"added_index": player_party.size() - 1,
		"party_count": calculate_player_party_count(),
	}


func _refresh_party_indexes() -> void:
	for index in range(player_party.size()):
		var mon = player_party[index]
		if typeof(mon) == TYPE_DICTIONARY:
			mon["party_index"] = index
			player_party[index] = mon


func _party_mon_species(mon: Dictionary) -> String:
	var species = mon.get("species", "")
	if typeof(species) == TYPE_DICTIONARY:
		return String(species.get("symbol", ""))
	return String(species)
