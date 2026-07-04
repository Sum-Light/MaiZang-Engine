extends SceneTree

const DATA_REGISTRY_SCRIPT := preload("res://scripts/autoload/data_registry.gd")
const BATTLE_ENGINE_SCRIPT := preload("res://scripts/autoload/battle_engine.gd")
const EVOLUTION_ENGINE_SCRIPT := preload("res://scripts/autoload/evolution_engine.gd")
const PARTY_RUNTIME_SCRIPT := preload("res://scripts/autoload/party_runtime.gd")
const GAME_STATE_SCRIPT := preload("res://scripts/autoload/game_state.gd")

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

	var torchic := party_runtime.create_party_mon("SPECIES_TORCHIC", 5, {
		"personality": 0x00000000,
		"ot_id": 0x00000000,
	})
	_assert(String(torchic.get("status", "")) == "ok", "expected Torchic party mon")
	_assert(String(torchic.get("species", "")) == "SPECIES_TORCHIC", "expected Torchic species")
	_assert(int(torchic.get("level", 0)) == 5, "expected Torchic level 5")
	_assert(int(torchic.get("friendship", -1)) == 50, "expected Torchic source friendship")
	_assert(int(torchic.get("hp", 0)) == int(torchic.get("max_hp", -1)), "expected full Torchic HP")
	_assert(String(torchic.get("nature", "")) == "NATURE_HARDY", "expected personality 0 Hardy nature")
	_assert(String(torchic.get("gender_symbol", "")) == "MON_FEMALE", "expected Torchic personality 0 female under source ratio")
	_assert(String(torchic.get("ability", "")) == "ABILITY_BLAZE", "expected Torchic first ability")
	_assert(String(torchic.get("pokeball", "")) == "ITEM_POKE_BALL", "expected default Poke Ball")
	_assert(_move_symbols(torchic) == ["MOVE_SCRATCH", "MOVE_GROWL", "MOVE_EMBER"], "expected Torchic source initial moves")
	_assert(_array_field(torchic, "move_slots").size() == 0 or _array_field(torchic, "moves").size() == 3, "expected move data shape")

	var bulbasaur := party_runtime.create_party_mon("SPECIES_BULBASAUR", 16, {
		"personality": 0x00000020,
	})
	_assert(String(bulbasaur.get("status", "")) == "ok", "expected Bulbasaur party mon")
	_assert(int(bulbasaur.get("hp", 0)) == int(bulbasaur.get("max_hp", -1)), "expected full Bulbasaur HP")

	var party_result := party_runtime.create_party([
		{"species": "SPECIES_TORCHIC", "level": 5, "personality": 0},
		{"species": "SPECIES_BULBASAUR", "level": 16, "personality": 0x20},
		{"species": "SPECIES_TREECKO", "level": 5, "personality": 1},
		{"species": "SPECIES_MUDKIP", "level": 5, "personality": 2},
		{"species": "SPECIES_EEVEE", "level": 20, "personality": 3},
		{"species": "SPECIES_NINCADA", "level": 20, "personality": 4},
		{"species": "SPECIES_ZIGZAGOON", "level": 3, "personality": 5},
	])
	var party := _array_field(party_result, "party")
	_assert(String(party_result.get("status", "")) == "ok", "expected party creation ok")
	_assert(party.size() == 6, "expected party capped to six")
	_assert(int(party_result.get("party_count", 0)) == 6, "expected source party count six")
	_assert(_has_warning(party_result, "party_full"), "expected seventh mon party-full warning")

	game_state.set_player_party(party)
	_assert(game_state.calculate_player_party_count() == 6, "expected GameState party count")
	var extra_add := party_runtime.add_mon_to_player_party(torchic, game_state)
	_assert(String(extra_add.get("status", "")) == "blocked", "expected full GameState party add blocked")
	_assert(String(extra_add.get("block_reason", "")) == "party_full", "expected party-full block reason")

	game_state.clear_player_party()
	var add_one := party_runtime.add_mon_to_player_party(torchic, game_state)
	_assert(String(add_one.get("status", "")) == "ok", "expected add mon to empty GameState party")
	_assert(game_state.calculate_player_party_count() == 1, "expected one GameState party mon")

	var battle_party := party_runtime.build_battle_party([torchic])
	var wallace := battle_engine.create_trainer_party("TRAINER_WALLACE")
	var battle_state := battle_engine.create_single_battle_state(battle_party, _array_field(wallace, "party"))
	_assert(String(battle_state.get("status", "")) == "ok", "expected battle state from runtime party")
	_assert(_array_field(battle_state, "player_party").size() == 1, "expected one player battle mon")

	var evo_check := party_runtime.check_party_mon_evolution([bulbasaur], 0, "EVO_MODE_NORMAL")
	_assert(String(evo_check.get("status", "")) == "ok", "expected Bulbasaur evolution from runtime party")
	_assert(String(evo_check.get("target_species", "")) == "SPECIES_IVYSAUR", "expected Bulbasaur to target Ivysaur")

	var nincada := party_runtime.create_party_mon("SPECIES_NINCADA", 20, {"personality": 0x44})
	var split_open := evolution_engine.get_split_evolution_candidate("SPECIES_NINCADA", "SPECIES_NINJASK", nincada, {
		"party_count": 5,
		"bag_items": {"ITEM_POKE_BALL": 1},
	})
	var split_full := evolution_engine.get_split_evolution_candidate("SPECIES_NINCADA", "SPECIES_NINJASK", nincada, {
		"party_count": 6,
		"bag_items": {"ITEM_POKE_BALL": 1},
	})
	_assert(String(split_open.get("target_species", "")) == "SPECIES_SHEDINJA", "expected open-party Shedinja candidate")
	_assert(String(split_full.get("status", "")) == "blocked", "expected full-party Shedinja block")

	if _failed:
		return

	print(JSON.stringify({
		"party_runtime_smoke": "ok",
		"torchic_moves": _move_symbols(torchic),
		"game_state_party_count": game_state.calculate_player_party_count(),
		"bulbasaur_target": String(evo_check.get("target_species", "")),
		"shedinja_target": String(split_open.get("target_species", "")),
	}))
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


func _move_symbols(mon: Dictionary) -> Array:
	var symbols: Array = []
	for move in _array_field(mon, "moves"):
		if typeof(move) != TYPE_DICTIONARY:
			continue
		var symbol := String(move.get("symbol", ""))
		if not symbol.is_empty() and symbol != "MOVE_NONE":
			symbols.append(symbol)
	return symbols


func _array_field(record: Dictionary, field_name: String) -> Array:
	var value = record.get(field_name, [])
	return value if typeof(value) == TYPE_ARRAY else []


func _has_warning(record: Dictionary, code: String) -> bool:
	for warning in _array_field(record, "warnings"):
		if typeof(warning) == TYPE_DICTIONARY and String(warning.get("code", "")) == code:
			return true
	return false
