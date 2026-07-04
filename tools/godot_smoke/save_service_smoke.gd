extends SceneTree

const DATA_REGISTRY_SCRIPT := preload("res://scripts/autoload/data_registry.gd")
const BATTLE_ENGINE_SCRIPT := preload("res://scripts/autoload/battle_engine.gd")
const EVOLUTION_ENGINE_SCRIPT := preload("res://scripts/autoload/evolution_engine.gd")
const PARTY_RUNTIME_SCRIPT := preload("res://scripts/autoload/party_runtime.gd")
const GAME_STATE_SCRIPT := preload("res://scripts/autoload/game_state.gd")
const SAVE_SERVICE_SCRIPT := preload("res://scripts/autoload/save_service.gd")

var _failed := false


func _init() -> void:
	var registry = DATA_REGISTRY_SCRIPT.new()
	registry._ready()

	var battle_engine = BATTLE_ENGINE_SCRIPT.new()
	battle_engine.configure_registry(registry)

	var evolution_engine = EVOLUTION_ENGINE_SCRIPT.new()
	evolution_engine.configure_registry(registry)

	var party_runtime = PARTY_RUNTIME_SCRIPT.new()
	party_runtime.configure_registry(registry)
	party_runtime.configure_battle_engine(battle_engine)
	party_runtime.configure_evolution_engine(evolution_engine)

	var game_state = GAME_STATE_SCRIPT.new()
	game_state.set_player_name("SAVE")
	game_state.set_player_gender("FEMALE")
	game_state.current_map_id = "MAP_LITTLEROOT_TOWN_BRENDANS_HOUSE_1F"
	game_state.player_grid_position = Vector2i(8, 8)
	game_state.set_flag("FLAG_RECEIVED_RUNNING_SHOES", true)
	game_state.set_var("VAR_LITTLEROOT_INTRO_STATE", 3)

	var party_result := party_runtime.create_party([
		{"species": "SPECIES_TORCHIC", "level": 5, "personality": 0},
		{"species": "SPECIES_BULBASAUR", "level": 16, "personality": 0x20},
	])
	_assert(String(party_result.get("status", "")) == "ok", "expected party creation")
	game_state.set_player_party(_array_field(party_result, "party"))

	var save_service = SAVE_SERVICE_SCRIPT.new()
	save_service.configure_game_state(game_state)
	var save_path := "user://save_service_smoke_%d.json" % [Time.get_ticks_usec()]
	var save_result := save_service.save_game(game_state, save_path, {"slot_id": "smoke"})
	_assert(String(save_result.get("status", "")) == "ok", "expected save ok")
	_assert(int(save_result.get("save_status_value", 0)) == SAVE_SERVICE_SCRIPT.SAVE_STATUS_OK, "expected OK save status")
	var snapshot := _dict_field(save_result, "snapshot")
	_assert(String(snapshot.get("schema", "")) == SAVE_SERVICE_SCRIPT.SCHEMA_NAME, "expected save schema")
	_assert(int(snapshot.get("save_counter", 0)) == 1, "expected first save counter")
	var snapshot_state := _dict_field(snapshot, "game_state")
	_assert(int(snapshot_state.get("player_party_count", 0)) == 2, "expected saved party count")
	_assert(_flow_has_label(_dict_field(snapshot, "save_flow"), "gText_ConfirmSave"), "expected confirm-save flow label")
	_assert(_flow_has_label(_dict_field(snapshot, "save_flow"), "gText_PlayerSavedGame"), "expected success-save flow label")

	game_state.set_player_name("BROKEN")
	game_state.set_player_gender("MALE")
	game_state.current_map_id = "MAP_LITTLEROOT_TOWN"
	game_state.player_grid_position = Vector2i(1, 2)
	game_state.clear_flag("FLAG_RECEIVED_RUNNING_SHOES")
	game_state.set_var("VAR_LITTLEROOT_INTRO_STATE", 0)
	game_state.clear_player_party()

	var load_result := save_service.load_game(save_path, game_state)
	_assert(String(load_result.get("status", "")) == "ok", "expected load ok")
	_assert(game_state.get_player_name() == "SAVE", "expected restored player name")
	_assert(game_state.get_player_gender() == "FEMALE", "expected restored player gender")
	_assert(game_state.current_map_id == "MAP_LITTLEROOT_TOWN_BRENDANS_HOUSE_1F", "expected restored map")
	_assert(game_state.player_grid_position == Vector2i(8, 8), "expected restored position")
	_assert(game_state.is_flag_set("FLAG_RECEIVED_RUNNING_SHOES"), "expected restored flag")
	_assert(game_state.get_var("VAR_LITTLEROOT_INTRO_STATE", 0) == 3, "expected restored var")
	_assert(game_state.calculate_player_party_count() == 2, "expected restored party")

	var second_save := save_service.save_game(game_state, save_path, {"slot_id": "smoke"})
	_assert(String(second_save.get("status", "")) == "ok", "expected second save ok")
	_assert(int(second_save.get("save_counter", 0)) == 2, "expected incremented save counter")

	var empty_result := save_service.load_game("user://missing_save_service_smoke_%d.json" % [Time.get_ticks_usec()], game_state)
	_assert(String(empty_result.get("status", "")) == "empty", "expected missing save to report empty")
	_assert(int(empty_result.get("save_status_value", -1)) == SAVE_SERVICE_SCRIPT.SAVE_STATUS_EMPTY, "expected empty save status")

	if _failed:
		return

	print(JSON.stringify({
		"save_service_smoke": "ok",
		"save_counter": int(second_save.get("save_counter", 0)),
		"map": game_state.current_map_id,
		"party_count": game_state.calculate_player_party_count(),
	}))
	save_service.free()
	party_runtime.free()
	evolution_engine.free()
	battle_engine.free()
	registry.free()
	game_state.free()
	quit(0)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true
	quit(1)


func _array_field(record: Dictionary, field_name: String) -> Array:
	var value = record.get(field_name, [])
	return value if typeof(value) == TYPE_ARRAY else []


func _dict_field(record: Dictionary, field_name: String) -> Dictionary:
	var value = record.get(field_name, {})
	return value if typeof(value) == TYPE_DICTIONARY else {}


func _flow_has_label(flow: Dictionary, text_label: String) -> bool:
	for step in _array_field(flow, "steps"):
		if typeof(step) == TYPE_DICTIONARY and String(step.get("text_label", "")) == text_label:
			return true
	return false
