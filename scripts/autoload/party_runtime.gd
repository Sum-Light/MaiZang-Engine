extends Node

const BATTLE_ENGINE_SCRIPT := preload("res://scripts/autoload/battle_engine.gd")

const PARTY_SIZE := 6
const MAX_MON_MOVES := 4
const SPECIES_NONE := "SPECIES_NONE"
const ITEM_NONE := "ITEM_NONE"
const ABILITY_NONE := "ABILITY_NONE"
const NATURE_COUNT := 25
const DEFAULT_POKEBALL := "ITEM_POKE_BALL"
const DEFAULT_LANGUAGE := "LANGUAGE_ENGLISH"
const MON_MALE := 0x00
const MON_FEMALE := 0xFE
const MON_GENDERLESS := 0xFF
const SHINY_ODDS := 8
const SOURCE_TRACE := [
	"include/constants/global.h:PARTY_SIZE/MAX_MON_MOVES",
	"include/pokemon.h:struct Pokemon/struct BoxPokemon",
	"src/pokemon.c:CreateMon",
	"src/pokemon.c:CreateBoxMon",
	"src/pokemon.c:CreateMonWithIVs",
	"src/pokemon.c:GiveBoxMonInitialMoveset",
	"src/pokemon.c:PokemonToBattleMon",
	"src/pokemon.c:GiveCapturedMonToPlayer",
	"src/pokemon.c:CalculatePartyCount",
]

var _registry: Node = null
var _battle_engine: Node = null
var _evolution_engine: Node = null
var _owned_battle_engine: Node = null


func configure_registry(registry: Node) -> void:
	_registry = registry
	if _owned_battle_engine != null and _owned_battle_engine.has_method("configure_registry"):
		_owned_battle_engine.configure_registry(registry)


func configure_battle_engine(engine: Node) -> void:
	_battle_engine = engine


func configure_evolution_engine(engine: Node) -> void:
	_evolution_engine = engine


func create_party_mon(species_id_or_symbol, level: int, options: Dictionary = {}) -> Dictionary:
	var species_record := _get_species_record(species_id_or_symbol)
	if species_record.is_empty():
		return _error_result("unknown_species", "Could not resolve species %s." % [str(species_id_or_symbol)])

	var battle_engine := _get_battle_engine()
	if battle_engine == null or not battle_engine.has_method("create_battle_mon"):
		return _error_result("missing_battle_engine", "BattleEngine is required for source-backed stat and move initialization.")

	var creation_options := options.duplicate(true)
	var warnings: Array = []
	var unsupported: Array = []
	var personality := _u32(creation_options.get("personality", 0))
	if not creation_options.has("personality"):
		unsupported.append({
			"code": "personality_rng_not_implemented",
			"source": "src/pokemon.c:CreateRandomMonWithIVs -> Random32",
			"detail": "First PartyRuntime slice uses personality 0 unless the caller provides one.",
		})
		creation_options["personality"] = personality
	if not creation_options.has("nature"):
		creation_options["nature"] = _nature_symbol_from_personality(personality)
	if not creation_options.has("friendship"):
		creation_options["friendship"] = int(species_record.get("friendship", 0))
	if not creation_options.has("held_item"):
		creation_options["held_item"] = ITEM_NONE
	if not creation_options.has("moves") and not creation_options.has("move_source_behavior") and bool(creation_options.get("initial_moves", true)):
		creation_options["move_source_behavior"] = {"kind": "level_up_default"}

	var mon = battle_engine.create_battle_mon(_record_symbol(species_record), level, creation_options)
	if typeof(mon) != TYPE_DICTIONARY:
		return _error_result("invalid_battle_engine_result", "BattleEngine did not return a Pokemon dictionary.")
	if String(mon.get("status", "")) != "ok":
		return mon

	var runtime_mon: Dictionary = mon.duplicate(true)
	runtime_mon["runtime_kind"] = "party_mon"
	runtime_mon["box_projection_source"] = "src/pokemon.c:CreateBoxMon"
	runtime_mon["battle_projection_source"] = "src/pokemon.c:PokemonToBattleMon"
	runtime_mon["personality"] = personality
	runtime_mon["ot_id"] = _u32(creation_options.get("ot_id", 0))
	runtime_mon["ot_name"] = String(creation_options.get("ot_name", ""))
	runtime_mon["language"] = String(creation_options.get("language", DEFAULT_LANGUAGE))
	runtime_mon["nickname"] = String(creation_options.get("nickname", mon.get("name", _record_symbol(species_record))))
	runtime_mon["gender"] = _gender_for_species_personality(species_record, personality, creation_options)
	runtime_mon["gender_symbol"] = String(_dict_field(runtime_mon, "gender").get("symbol", ""))
	runtime_mon["gender_value"] = int(_dict_field(runtime_mon, "gender").get("value", -1))
	runtime_mon["ability_slot"] = _ability_slot_for_species_personality(species_record, personality, creation_options)
	if not creation_options.has("ability"):
		runtime_mon["ability"] = _ability_symbol_for_slot(species_record, int(runtime_mon.get("ability_slot", 0)))
	runtime_mon["pokeball"] = _normalize_item_symbol(_constant_symbol(creation_options.get("pokeball", DEFAULT_POKEBALL)))
	runtime_mon["is_shiny"] = _is_shiny(int(runtime_mon.get("ot_id", 0)), personality, creation_options)
	runtime_mon["is_egg"] = bool(creation_options.get("is_egg", false))
	runtime_mon["met"] = {
		"location": creation_options.get("met_location", ""),
		"level": int(runtime_mon.get("level", level)),
		"game": creation_options.get("met_game", ""),
		"source": "src/pokemon.c:CreateBoxMon",
	}
	runtime_mon["contest"] = _contest_stats(creation_options.get("contest", {}))
	var source_trace := SOURCE_TRACE.duplicate()
	source_trace.append_array(_array_field(mon, "source_trace"))
	runtime_mon["source_trace"] = source_trace
	warnings.append_array(_array_field(mon, "warnings"))
	unsupported.append_array(_array_field(mon, "unsupported"))
	runtime_mon["warnings"] = warnings
	runtime_mon["unsupported"] = unsupported
	return runtime_mon


func create_party(mon_specs: Array, options: Dictionary = {}) -> Dictionary:
	var party: Array = []
	var warnings: Array = []
	var unsupported: Array = []
	var errors: Array = []
	for spec in mon_specs:
		if party.size() >= PARTY_SIZE:
			warnings.append({
				"code": "party_full",
				"source": "src/pokemon.c:GiveCapturedMonToPlayer",
				"detail": "Only six Pokemon can be carried in the party.",
			})
			break
		if typeof(spec) != TYPE_DICTIONARY:
			errors.append({"code": "invalid_party_spec"})
			continue
		var mon_options := _dict_field(spec, "options").duplicate(true)
		for key in spec.keys():
			if ["species", "level", "options"].has(String(key)):
				continue
			if not mon_options.has(key):
				mon_options[key] = spec.get(key)
		var mon := create_party_mon(spec.get("species", SPECIES_NONE), int(spec.get("level", 1)), mon_options)
		if String(mon.get("status", "")) != "ok":
			errors.append(mon)
			continue
		mon["party_index"] = party.size()
		party.append(mon)
		warnings.append_array(_array_field(mon, "warnings"))
		unsupported.append_array(_array_field(mon, "unsupported"))
	return {
		"status": "ok" if errors.is_empty() else "partial",
		"party": party,
		"party_count": calculate_party_count(party),
		"first_live_index": first_live_mon_index(party),
		"warnings": warnings,
		"unsupported": unsupported,
		"errors": errors,
		"source_trace": ["src/pokemon.c:CalculatePartyCount"],
	}


func add_party_mon(party: Array, mon: Dictionary) -> Dictionary:
	var updated_party := party.duplicate(true)
	if calculate_party_count(updated_party) >= PARTY_SIZE:
		return {
			"status": "blocked",
			"block_reason": "party_full",
			"party": updated_party,
			"source_trace": ["src/pokemon.c:GiveCapturedMonToPlayer"],
		}
	var stored := mon.duplicate(true)
	stored["party_index"] = updated_party.size()
	updated_party.append(stored)
	return {
		"status": "ok",
		"party": updated_party,
		"party_count": calculate_party_count(updated_party),
		"added_index": updated_party.size() - 1,
		"source_trace": ["src/pokemon.c:GiveCapturedMonToPlayer"],
	}


func add_mon_to_player_party(mon: Dictionary, game_state: Node = null) -> Dictionary:
	var resolved_game_state := _get_game_state(game_state)
	if resolved_game_state == null or not resolved_game_state.has_method("get_player_party"):
		return _error_result("missing_game_state", "GameState with party accessors is unavailable.")
	var result := add_party_mon(resolved_game_state.get_player_party(), mon)
	if String(result.get("status", "")) == "ok" and resolved_game_state.has_method("set_player_party"):
		resolved_game_state.set_player_party(result.get("party", []))
	return result


func calculate_party_count(party: Array) -> int:
	var count := 0
	for mon in party:
		if typeof(mon) != TYPE_DICTIONARY:
			break
		if _mon_species_symbol(mon) == SPECIES_NONE:
			break
		count += 1
		if count >= PARTY_SIZE:
			break
	return count


func first_live_mon_index(party: Array) -> int:
	for index in range(min(party.size(), PARTY_SIZE)):
		var mon = party[index]
		if typeof(mon) != TYPE_DICTIONARY:
			continue
		if bool(mon.get("is_egg", false)):
			continue
		if _mon_species_symbol(mon) == SPECIES_NONE:
			continue
		if int(mon.get("hp", 0)) > 0:
			return index
	return PARTY_SIZE


func to_battle_mon(mon: Dictionary) -> Dictionary:
	var battle_mon := mon.duplicate(true)
	battle_mon["battle_projection_source"] = "src/pokemon.c:PokemonToBattleMon"
	return battle_mon


func build_battle_party(party: Array) -> Array:
	var battle_party: Array = []
	for index in range(min(party.size(), PARTY_SIZE)):
		var mon = party[index]
		if typeof(mon) != TYPE_DICTIONARY:
			continue
		var battle_mon := to_battle_mon(mon)
		battle_mon["battle_party_index"] = index
		battle_party.append(battle_mon)
	return battle_party


func check_party_mon_evolution(party: Array, index: int, mode: String = "EVO_MODE_NORMAL", options: Dictionary = {}) -> Dictionary:
	if index < 0 or index >= party.size():
		return _error_result("invalid_party_index", "Party index %d is unavailable." % [index])
	var evolution_engine := _get_evolution_engine()
	if evolution_engine == null or not evolution_engine.has_method("get_evolution_target_species"):
		return _error_result("missing_evolution_engine", "EvolutionEngine is unavailable.")
	var mon = party[index]
	if typeof(mon) != TYPE_DICTIONARY:
		return _error_result("invalid_party_mon", "Party entry is not a Pokemon dictionary.")
	var evo_options := options.duplicate(true)
	evo_options["party"] = party
	evo_options["party_count"] = calculate_party_count(party)
	evo_options["party_index"] = index
	evo_options["first_live_party_index"] = first_live_mon_index(party)
	return evolution_engine.get_evolution_target_species(mon, mode, evo_options)


func _get_registry() -> Node:
	if _registry != null:
		return _registry
	if has_node("/root/DataRegistry"):
		_registry = get_node("/root/DataRegistry")
	return _registry


func _get_battle_engine() -> Node:
	if _battle_engine != null:
		return _battle_engine
	if has_node("/root/BattleEngine"):
		_battle_engine = get_node("/root/BattleEngine")
		return _battle_engine
	if _owned_battle_engine == null:
		_owned_battle_engine = BATTLE_ENGINE_SCRIPT.new()
		if _owned_battle_engine.has_method("configure_registry"):
			_owned_battle_engine.configure_registry(_get_registry())
	return _owned_battle_engine


func _get_evolution_engine() -> Node:
	if _evolution_engine != null:
		return _evolution_engine
	if has_node("/root/EvolutionEngine"):
		_evolution_engine = get_node("/root/EvolutionEngine")
	return _evolution_engine


func _get_game_state(game_state: Node) -> Node:
	if game_state != null:
		return game_state
	return get_node_or_null("/root/GameState")


func _get_species_record(species_id_or_symbol) -> Dictionary:
	var registry := _get_registry()
	if registry == null or not registry.has_method("get_species_record"):
		return {}
	var record = registry.get_species_record(species_id_or_symbol)
	return record if typeof(record) == TYPE_DICTIONARY else {}


func _get_nature_record(nature_id_or_symbol) -> Dictionary:
	var registry := _get_registry()
	if registry == null or not registry.has_method("get_nature_record"):
		return {}
	var record = registry.get_nature_record(nature_id_or_symbol)
	return record if typeof(record) == TYPE_DICTIONARY else {}


func _nature_symbol_from_personality(personality: int) -> String:
	var nature_record := _get_nature_record(abs(personality) % NATURE_COUNT)
	if nature_record.is_empty():
		return "NATURE_HARDY"
	return _record_symbol(nature_record)


func _gender_for_species_personality(species_record: Dictionary, personality: int, options: Dictionary) -> Dictionary:
	if options.has("gender"):
		var gender_symbol := _normalize_gender_symbol(_constant_symbol(options.get("gender")))
		return {
			"symbol": gender_symbol,
			"value": _gender_value_for_symbol(gender_symbol),
			"source": "caller_override",
		}
	var gender_ratio = species_record.get("gender_ratio", {})
	if typeof(gender_ratio) != TYPE_DICTIONARY:
		return {"symbol": "MON_GENDERLESS", "value": MON_GENDERLESS, "source": "missing_gender_ratio"}
	var ratio_value := int(gender_ratio.get("value", MON_GENDERLESS))
	if ratio_value == MON_GENDERLESS:
		return {"symbol": "MON_GENDERLESS", "value": MON_GENDERLESS, "source": "src/pokemon.c:GetGenderFromSpeciesAndPersonality"}
	if ratio_value == MON_FEMALE:
		return {"symbol": "MON_FEMALE", "value": MON_FEMALE, "source": "src/pokemon.c:GetGenderFromSpeciesAndPersonality"}
	if ratio_value == MON_MALE:
		return {"symbol": "MON_MALE", "value": MON_MALE, "source": "src/pokemon.c:GetGenderFromSpeciesAndPersonality"}
	if (personality & 0xFF) < ratio_value:
		return {"symbol": "MON_FEMALE", "value": MON_FEMALE, "source": "src/pokemon.c:GetGenderFromSpeciesAndPersonality"}
	return {"symbol": "MON_MALE", "value": MON_MALE, "source": "src/pokemon.c:GetGenderFromSpeciesAndPersonality"}


func _ability_slot_for_species_personality(species_record: Dictionary, personality: int, options: Dictionary) -> int:
	if options.has("ability_slot"):
		return clampi(int(options.get("ability_slot", 0)), 0, 2)
	if options.has("ability_num"):
		return clampi(int(options.get("ability_num", 0)), 0, 2)
	var abilities = species_record.get("abilities", [])
	if typeof(abilities) == TYPE_ARRAY and abilities.size() > 1 and _constant_symbol(abilities[1]) != ABILITY_NONE:
		return personality & 0x1
	return 0


func _ability_symbol_for_slot(species_record: Dictionary, ability_slot: int) -> String:
	var abilities = species_record.get("abilities", [])
	if typeof(abilities) == TYPE_ARRAY and ability_slot >= 0 and ability_slot < abilities.size():
		var ability_symbol := _constant_symbol(abilities[ability_slot])
		return _normalize_ability_symbol(ability_symbol)
	return ABILITY_NONE


func _is_shiny(ot_id: int, personality: int, options: Dictionary) -> bool:
	if options.has("is_shiny"):
		return bool(options.get("is_shiny"))
	if not options.has("ot_id") or not options.has("personality"):
		return false
	var shiny_value := ((ot_id >> 16) & 0xFFFF) ^ (ot_id & 0xFFFF) ^ ((personality >> 16) & 0xFFFF) ^ (personality & 0xFFFF)
	return shiny_value < SHINY_ODDS


func _contest_stats(value) -> Dictionary:
	var raw = value if typeof(value) == TYPE_DICTIONARY else {}
	return {
		"cool": int(raw.get("cool", 0)),
		"beauty": int(raw.get("beauty", 0)),
		"cute": int(raw.get("cute", 0)),
		"smart": int(raw.get("smart", 0)),
		"tough": int(raw.get("tough", 0)),
		"sheen": int(raw.get("sheen", 0)),
	}


func _mon_species_symbol(mon: Dictionary) -> String:
	var species = mon.get("species", SPECIES_NONE)
	if typeof(species) == TYPE_DICTIONARY:
		return _normalize_species_symbol(_constant_symbol(species))
	if typeof(species) == TYPE_INT or typeof(species) == TYPE_FLOAT:
		var species_record := _get_species_record(int(species))
		return _record_symbol(species_record)
	return _normalize_species_symbol(String(species))


func _dict_field(record, field_name: String) -> Dictionary:
	if typeof(record) != TYPE_DICTIONARY:
		return {}
	var value = record.get(field_name, {})
	return value if typeof(value) == TYPE_DICTIONARY else {}


func _array_field(record, field_name: String) -> Array:
	if typeof(record) != TYPE_DICTIONARY:
		return []
	var value = record.get(field_name, [])
	return value if typeof(value) == TYPE_ARRAY else []


func _record_symbol(record: Dictionary) -> String:
	return String(record.get("symbol", ""))


func _constant_symbol(value) -> String:
	if typeof(value) == TYPE_DICTIONARY:
		return String(value.get("symbol", ""))
	if value == null:
		return ""
	return String(value)


func _numeric_value(value, default_value: int) -> int:
	if value == null:
		return default_value
	if typeof(value) == TYPE_DICTIONARY:
		if value.has("value") and value.get("value") != null:
			return int(value.get("value"))
		return default_value
	if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
		return int(value)
	var text := String(value)
	if text.is_valid_int():
		return int(text)
	return default_value


func _u32(value) -> int:
	var number := _numeric_value(value, 0)
	if number < 0:
		number = 0
	return number & 0xFFFFFFFF


func _gender_value_for_symbol(symbol: String) -> int:
	match symbol:
		"MON_MALE":
			return MON_MALE
		"MON_FEMALE":
			return MON_FEMALE
		"MON_GENDERLESS":
			return MON_GENDERLESS
		_:
			return -1


func _normalize_gender_symbol(gender_symbol: String) -> String:
	if gender_symbol.is_empty():
		return ""
	if gender_symbol.begins_with("MON_"):
		return gender_symbol
	return "MON_%s" % [gender_symbol.to_upper()]


func _normalize_species_symbol(species_symbol: String) -> String:
	if species_symbol.is_empty():
		return ""
	if species_symbol.begins_with("SPECIES_"):
		return species_symbol
	return "SPECIES_%s" % [species_symbol.to_upper()]


func _normalize_item_symbol(item_symbol: String) -> String:
	if item_symbol.is_empty():
		return ITEM_NONE
	if item_symbol.begins_with("ITEM_"):
		return item_symbol
	return "ITEM_%s" % [item_symbol.to_upper()]


func _normalize_ability_symbol(ability_symbol: String) -> String:
	if ability_symbol.is_empty():
		return ABILITY_NONE
	if ability_symbol.begins_with("ABILITY_"):
		return ability_symbol
	return "ABILITY_%s" % [ability_symbol.to_upper()]


func _error_result(code: String, detail: String) -> Dictionary:
	return {
		"status": "error",
		"error": code,
		"detail": detail,
		"source_trace": SOURCE_TRACE.duplicate(),
	}
