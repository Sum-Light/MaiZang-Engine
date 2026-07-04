extends SceneTree

const DATA_REGISTRY_SCRIPT := preload("res://scripts/autoload/data_registry.gd")
const BATTLE_ENGINE_SCRIPT := preload("res://scripts/autoload/battle_engine.gd")
const PARTY_RUNTIME_SCRIPT := preload("res://scripts/autoload/party_runtime.gd")
const GAME_STATE_SCRIPT := preload("res://scripts/autoload/game_state.gd")
const EVENT_MANAGER_SCRIPT := preload("res://scripts/autoload/event_manager.gd")
const DEBUG_LAUNCHER_SCRIPT := preload("res://scripts/debug/battle_debug_launcher.gd")

var _failed := false


func _init() -> void:
	var registry = DATA_REGISTRY_SCRIPT.new()
	registry._ready()

	var battle_engine = BATTLE_ENGINE_SCRIPT.new()
	battle_engine.configure_registry(registry)

	var party_runtime = PARTY_RUNTIME_SCRIPT.new()
	party_runtime.configure_registry(registry)
	party_runtime.configure_battle_engine(battle_engine)

	var game_state = GAME_STATE_SCRIPT.new()
	game_state.clear_player_party()
	game_state.player_grid_position = Vector2i(7, 9)

	var manager = EVENT_MANAGER_SCRIPT.new()
	manager.configure_data_registry(registry)
	manager.configure_battle_engine(battle_engine)
	manager.configure_party_runtime(party_runtime)
	manager.configure_game_state(game_state)

	var captured_sequences := []
	manager.battle_start_sequence_requested.connect(func(sequence: Dictionary) -> void:
		captured_sequences.append(sequence)
	)

	var launcher = DEBUG_LAUNCHER_SCRIPT.new()
	launcher.configure(registry, battle_engine, party_runtime, game_state, manager)

	var encounter := launcher.create_random_wild_encounter({
		"species_symbol": "SPECIES_WURMPLE",
		"level": 37,
	})
	_assert(String(encounter.get("status", "")) == "ok", "expected deterministic debug wild encounter")
	_assert(String(encounter.get("species", "")) == "SPECIES_WURMPLE", "expected requested Wurmple species")
	_assert(int(encounter.get("level", 0)) == 37, "expected requested debug wild level")
	_assert(bool(encounter.get("debug_random", false)), "expected debug random metadata")
	_assert(_has_unsupported(encounter, "debug_random_wild_not_source_encounter"), "expected random wild unsupported marker")

	var wild_launch := launcher.launch_random_wild_battle({
		"species_symbol": "SPECIES_WURMPLE",
		"level": 37,
		"debug_player_level": 37,
	})
	var wild_sequence := _dict(wild_launch.get("sequence", {}))
	var wild_state := _dict(wild_sequence.get("battle_state", {}))
	var wild_opponent := _array_dict(_array(wild_state.get("opponent_party", [])), 0)
	var wild_player_party := _dict(wild_launch.get("debug_player_party", {}))
	_assert(String(wild_launch.get("status", "")) == "sequence_requested", "expected debug wild sequence")
	_assert(captured_sequences.size() == 1, "expected one emitted wild sequence")
	_assert(String(wild_sequence.get("battle_kind", "")) == "wild", "expected wild sequence kind")
	_assert(String(wild_sequence.get("presentation", "")) == "debug_random_wild_battle_start", "expected debug wild presentation")
	_assert(bool(wild_sequence.get("enable_battle_scene_handoff", false)), "expected debug wild handoff")
	_assert(String(wild_opponent.get("species", "")) == "SPECIES_WURMPLE", "expected debug wild opponent")
	_assert(int(wild_opponent.get("level", 0)) == 37, "expected debug wild opponent level")
	_assert(bool(wild_player_party.get("temporary", false)), "expected temporary debug player party")
	_assert(int(wild_player_party.get("level", 0)) == 37, "expected debug player fallback to match wild level")
	_assert(String(_dict(wild_sequence.get("statistics", {})).get("status", "")) == "debug_not_incremented", "expected debug wild to avoid game stat mutation")
	_assert(game_state.get_game_stat("GAME_STAT_WILD_BATTLES", 0) == 0, "expected debug wild not to mutate wild battle stats")
	_assert(_has_unsupported(wild_state, "debug_random_wild_not_source_encounter"), "expected debug wild battle state marker")

	var sawyer_by_symbol := launcher.resolve_trainer_ref("TRAINER_SAWYER_1")
	var sawyer_id := int(_dict(sawyer_by_symbol.get("trainer", {})).get("id", -1))
	var sawyer_by_short := launcher.resolve_trainer_ref("SAWYER_1")
	var sawyer_by_id := launcher.resolve_trainer_ref(sawyer_id)
	_assert(String(sawyer_by_symbol.get("status", "")) == "ok", "expected full trainer symbol resolution")
	_assert(String(sawyer_by_short.get("status", "")) == "ok", "expected short trainer symbol resolution")
	_assert(String(sawyer_by_id.get("status", "")) == "ok", "expected numeric trainer id resolution")
	_assert(String(_dict(sawyer_by_short.get("trainer", {})).get("symbol", "")) == "TRAINER_SAWYER_1", "expected short trainer symbol to normalize")
	_assert(String(_dict(sawyer_by_id.get("trainer", {})).get("symbol", "")) == "TRAINER_SAWYER_1", "expected numeric trainer id to normalize")
	_assert(String(launcher.resolve_trainer_ref("NO_SUCH_TRAINER").get("status", "")) == "unknown_trainer", "expected invalid trainer rejection")

	var trainer_launch := launcher.launch_trainer_battle("SAWYER_1")
	var trainer_sequence := _dict(trainer_launch.get("sequence", {}))
	var trainer_state := _dict(trainer_sequence.get("battle_state", {}))
	var trainer_battle_setup := _dict(trainer_launch.get("battle_setup", {}))
	var trainer_debug_party := _dict(trainer_battle_setup.get("debug_player_party", {}))
	_assert(String(trainer_launch.get("status", "")) == "sequence_requested", "expected trainer selector sequence")
	_assert(captured_sequences.size() == 2, "expected emitted trainer sequence")
	_assert(String(trainer_sequence.get("battle_kind", "")) == "trainer", "expected trainer sequence kind")
	_assert(bool(trainer_sequence.get("enable_battle_scene_handoff", false)), "expected trainer handoff")
	_assert(String(_dict(trainer_state.get("trainer", {})).get("symbol", "")) == "TRAINER_SAWYER_1", "expected Sawyer trainer battle")
	_assert(bool(trainer_debug_party.get("temporary", false)), "expected temporary trainer debug party")
	_assert(game_state.get_player_party_count() == 0, "expected temporary debug party not to persist")

	if _failed:
		return

	print(JSON.stringify({
		"debug_battle_launcher_smoke": "ok",
		"wild_species": String(wild_opponent.get("species", "")),
		"wild_level": int(wild_opponent.get("level", 0)),
		"trainer_id": sawyer_id,
		"sequence_count": captured_sequences.size(),
	}))
	quit(0)


func _dict(value) -> Dictionary:
	return value if typeof(value) == TYPE_DICTIONARY else {}


func _array(value) -> Array:
	return value if typeof(value) == TYPE_ARRAY else []


func _array_dict(array: Array, index: int) -> Dictionary:
	if index < 0 or index >= array.size():
		return {}
	var value = array[index]
	return value if typeof(value) == TYPE_DICTIONARY else {}


func _has_unsupported(record: Dictionary, code: String) -> bool:
	var unsupported = record.get("unsupported", [])
	if typeof(unsupported) != TYPE_ARRAY:
		return false
	for item in unsupported:
		if typeof(item) == TYPE_DICTIONARY and String(item.get("code", "")) == code:
			return true
	return false


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true
	quit(1)
