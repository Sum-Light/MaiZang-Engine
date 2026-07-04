extends Node

const MAX_MON_MOVES := 4
const DEFAULT_IV := 31
const DEFAULT_EV := 0
const DAMAGE_ROLL_PERCENT_LO := 85
const DAMAGE_ROLL_PERCENT_HI := 100
const STAT_KEYS := ["hp", "attack", "defense", "speed", "sp_attack", "sp_defense"]
const STAT_KEY_TO_SOURCE_STAT := {
	"attack": "STAT_ATK",
	"defense": "STAT_DEF",
	"speed": "STAT_SPEED",
	"sp_attack": "STAT_SPATK",
	"sp_defense": "STAT_SPDEF",
}
const SOURCE_TRACE := [
	"src/pokemon.c:CalculateMonStats",
	"src/pokemon.c:gNaturesInfo",
	"src/pokemon.c:ModifyStatByNature",
	"src/battle_main.c:CreateNPCTrainerPartyFromTrainer",
	"src/battle_main.c:CustomTrainerPartyAssignMoves",
	"src/pokemon.c:GiveBoxMonInitialMoveset",
	"src/wild_encounter.c:CreateWildMon",
	"src/battle_setup.c:BattleSetup_StartWildBattle",
	"src/battle_setup.c:DoStandardWildBattle",
	"src/battle_setup.c:GetWildBattleTransition",
	"src/battle_util.c:CalculateBaseDamage",
	"src/battle_util.c:DoMoveDamageCalcVars",
	"src/battle_util.c:ApplyModifiersAfterDmgRoll",
	"src/data/types_info.h:gTypeEffectivenessTable",
]

const WILD_BATTLE_TRANSITION_TABLE := {
	"TRANSITION_TYPE_NORMAL": ["B_TRANSITION_SLICE", "B_TRANSITION_WHITE_BARS_FADE"],
	"TRANSITION_TYPE_CAVE": ["B_TRANSITION_CLOCKWISE_WIPE", "B_TRANSITION_GRID_SQUARES"],
	"TRANSITION_TYPE_FLASH": ["B_TRANSITION_BLUR", "B_TRANSITION_GRID_SQUARES"],
	"TRANSITION_TYPE_WATER": ["B_TRANSITION_WAVE", "B_TRANSITION_RIPPLE"],
}
const TRAINER_BATTLE_TRANSITION_TABLE := {
	"TRANSITION_TYPE_NORMAL": ["B_TRANSITION_POKEBALLS_TRAIL", "B_TRANSITION_ANGLED_WIPES"],
	"TRANSITION_TYPE_CAVE": ["B_TRANSITION_SHUFFLE", "B_TRANSITION_BIG_POKEBALL"],
	"TRANSITION_TYPE_FLASH": ["B_TRANSITION_BLUR", "B_TRANSITION_GRID_SQUARES"],
	"TRANSITION_TYPE_WATER": ["B_TRANSITION_SWIRL", "B_TRANSITION_RIPPLE"],
}
const TRAINER_MAGMA_CLASSES := {
	"TRAINER_CLASS_TEAM_MAGMA": true,
	"TRAINER_CLASS_MAGMA_LEADER": true,
	"TRAINER_CLASS_MAGMA_ADMIN": true,
}
const TRAINER_AQUA_CLASSES := {
	"TRAINER_CLASS_TEAM_AQUA": true,
	"TRAINER_CLASS_AQUA_LEADER": true,
	"TRAINER_CLASS_AQUA_ADMIN": true,
}
const SURFABLE_WATER_TRANSITION_BEHAVIORS := {
	"MB_POND_WATER": true,
	"MB_INTERIOR_DEEP_WATER": true,
	"MB_DEEP_WATER": true,
	"MB_WATERFALL": true,
	"MB_SOOTOPOLIS_DEEP_WATER": true,
	"MB_OCEAN_WATER": true,
	"MB_NO_SURFACING": true,
	"MB_SEAWEED": true,
	"MB_SEAWEED_NO_SURFACING": true,
	"MB_EASTWARD_CURRENT": true,
	"MB_WESTWARD_CURRENT": true,
	"MB_NORTHWARD_CURRENT": true,
	"MB_SOUTHWARD_CURRENT": true,
	"MB_WATER_DOOR": true,
	"MB_WATER_SOUTH_ARROW_WARP": true,
	"MB_UNUSED_6F": true,
	"MB_FAST_WATER": true,
	"MB_CYCLING_ROAD_WATER": true,
}

const TYPE_EFFECTIVENESS := {
	"TYPE_NORMAL": {
		"TYPE_ROCK": [1, 2],
		"TYPE_GHOST": [0, 1],
		"TYPE_STEEL": [1, 2],
	},
	"TYPE_FIGHTING": {
		"TYPE_NORMAL": [2, 1],
		"TYPE_FLYING": [1, 2],
		"TYPE_POISON": [1, 2],
		"TYPE_ROCK": [2, 1],
		"TYPE_BUG": [1, 2],
		"TYPE_GHOST": [0, 1],
		"TYPE_STEEL": [2, 1],
		"TYPE_PSYCHIC": [1, 2],
		"TYPE_ICE": [2, 1],
		"TYPE_DARK": [2, 1],
		"TYPE_FAIRY": [1, 2],
	},
	"TYPE_FLYING": {
		"TYPE_FIGHTING": [2, 1],
		"TYPE_ROCK": [1, 2],
		"TYPE_BUG": [2, 1],
		"TYPE_STEEL": [1, 2],
		"TYPE_GRASS": [2, 1],
		"TYPE_ELECTRIC": [1, 2],
	},
	"TYPE_POISON": {
		"TYPE_POISON": [1, 2],
		"TYPE_GROUND": [1, 2],
		"TYPE_ROCK": [1, 2],
		"TYPE_BUG": [1, 2],
		"TYPE_GHOST": [1, 2],
		"TYPE_STEEL": [0, 1],
		"TYPE_GRASS": [2, 1],
		"TYPE_FAIRY": [2, 1],
	},
	"TYPE_GROUND": {
		"TYPE_FLYING": [0, 1],
		"TYPE_POISON": [2, 1],
		"TYPE_ROCK": [2, 1],
		"TYPE_BUG": [1, 2],
		"TYPE_STEEL": [2, 1],
		"TYPE_FIRE": [2, 1],
		"TYPE_GRASS": [1, 2],
		"TYPE_ELECTRIC": [2, 1],
	},
	"TYPE_ROCK": {
		"TYPE_FIGHTING": [1, 2],
		"TYPE_FLYING": [2, 1],
		"TYPE_GROUND": [1, 2],
		"TYPE_BUG": [2, 1],
		"TYPE_STEEL": [1, 2],
		"TYPE_FIRE": [2, 1],
		"TYPE_ICE": [2, 1],
	},
	"TYPE_BUG": {
		"TYPE_FIGHTING": [1, 2],
		"TYPE_FLYING": [1, 2],
		"TYPE_POISON": [1, 2],
		"TYPE_GHOST": [1, 2],
		"TYPE_STEEL": [1, 2],
		"TYPE_FIRE": [1, 2],
		"TYPE_GRASS": [2, 1],
		"TYPE_PSYCHIC": [2, 1],
		"TYPE_DARK": [2, 1],
		"TYPE_FAIRY": [1, 2],
	},
	"TYPE_GHOST": {
		"TYPE_NORMAL": [0, 1],
		"TYPE_GHOST": [2, 1],
		"TYPE_STEEL": [1, 1],
		"TYPE_PSYCHIC": [2, 1],
		"TYPE_DARK": [1, 2],
	},
	"TYPE_STEEL": {
		"TYPE_ROCK": [2, 1],
		"TYPE_STEEL": [1, 2],
		"TYPE_FIRE": [1, 2],
		"TYPE_WATER": [1, 2],
		"TYPE_ELECTRIC": [1, 2],
		"TYPE_ICE": [2, 1],
		"TYPE_FAIRY": [2, 1],
	},
	"TYPE_FIRE": {
		"TYPE_ROCK": [1, 2],
		"TYPE_BUG": [2, 1],
		"TYPE_STEEL": [2, 1],
		"TYPE_FIRE": [1, 2],
		"TYPE_WATER": [1, 2],
		"TYPE_GRASS": [2, 1],
		"TYPE_ICE": [2, 1],
		"TYPE_DRAGON": [1, 2],
	},
	"TYPE_WATER": {
		"TYPE_GROUND": [2, 1],
		"TYPE_ROCK": [2, 1],
		"TYPE_FIRE": [2, 1],
		"TYPE_WATER": [1, 2],
		"TYPE_GRASS": [1, 2],
		"TYPE_DRAGON": [1, 2],
	},
	"TYPE_GRASS": {
		"TYPE_FLYING": [1, 2],
		"TYPE_POISON": [1, 2],
		"TYPE_GROUND": [2, 1],
		"TYPE_ROCK": [2, 1],
		"TYPE_BUG": [1, 2],
		"TYPE_STEEL": [1, 2],
		"TYPE_FIRE": [1, 2],
		"TYPE_WATER": [2, 1],
		"TYPE_GRASS": [1, 2],
		"TYPE_DRAGON": [1, 2],
	},
	"TYPE_ELECTRIC": {
		"TYPE_FLYING": [2, 1],
		"TYPE_GROUND": [0, 1],
		"TYPE_WATER": [2, 1],
		"TYPE_GRASS": [1, 2],
		"TYPE_ELECTRIC": [1, 2],
		"TYPE_DRAGON": [1, 2],
	},
	"TYPE_PSYCHIC": {
		"TYPE_FIGHTING": [2, 1],
		"TYPE_POISON": [2, 1],
		"TYPE_STEEL": [1, 2],
		"TYPE_PSYCHIC": [1, 2],
		"TYPE_DARK": [0, 1],
	},
	"TYPE_ICE": {
		"TYPE_FLYING": [2, 1],
		"TYPE_GROUND": [2, 1],
		"TYPE_STEEL": [1, 2],
		"TYPE_FIRE": [1, 2],
		"TYPE_WATER": [1, 2],
		"TYPE_GRASS": [2, 1],
		"TYPE_ICE": [1, 2],
		"TYPE_DRAGON": [2, 1],
	},
	"TYPE_DRAGON": {
		"TYPE_STEEL": [1, 2],
		"TYPE_DRAGON": [2, 1],
		"TYPE_FAIRY": [0, 1],
	},
	"TYPE_DARK": {
		"TYPE_FIGHTING": [1, 2],
		"TYPE_GHOST": [2, 1],
		"TYPE_STEEL": [1, 1],
		"TYPE_PSYCHIC": [2, 1],
		"TYPE_DARK": [1, 2],
		"TYPE_FAIRY": [1, 2],
	},
	"TYPE_FAIRY": {
		"TYPE_FIGHTING": [2, 1],
		"TYPE_POISON": [1, 2],
		"TYPE_STEEL": [1, 2],
		"TYPE_FIRE": [1, 2],
		"TYPE_DRAGON": [2, 1],
		"TYPE_DARK": [2, 1],
	},
}

var _registry: Node = null


func configure_registry(registry: Node) -> void:
	_registry = registry


func create_battle_mon(species_id_or_symbol, level: int, options: Dictionary = {}) -> Dictionary:
	var species_record := _get_species_record(species_id_or_symbol)
	if species_record.is_empty():
		return _error_result("unknown_species", "Could not resolve species %s" % [str(species_id_or_symbol)])

	var base_stats = species_record.get("base_stats", {})
	if typeof(base_stats) != TYPE_DICTIONARY:
		return _error_result("missing_base_stats", "Species %s has no generated base stats" % [_record_symbol(species_record)])

	var warnings: Array = []
	var unsupported: Array = []
	var clamped_level: int = max(1, level)
	var ivs := _normalize_stat_values(options.get("ivs", {}), DEFAULT_IV)
	var evs := _normalize_stat_values(options.get("evs", {}), DEFAULT_EV)
	var nature_symbol := _constant_symbol(options.get("nature", "NATURE_HARDY"))
	if nature_symbol.is_empty():
		nature_symbol = "NATURE_HARDY"
	var nature_record := _get_nature_record(nature_symbol)
	var stats := _calculate_stats(species_record, clamped_level, ivs, evs, nature_symbol, nature_record, unsupported)
	var move_specs = options.get("moves", [])
	var move_source_behavior = options.get("move_source_behavior", {})
	if (typeof(move_specs) != TYPE_ARRAY or move_specs.is_empty()) and typeof(move_source_behavior) == TYPE_DICTIONARY:
		if String(move_source_behavior.get("kind", "")) == "level_up_default":
			move_specs = _move_specs_for_initial_learnset(species_record, clamped_level, unsupported)
	var moves_result := _build_move_slots(move_specs)
	warnings.append_array(moves_result.get("warnings", []))
	unsupported.append_array(moves_result.get("unsupported", []))

	var hp := int(options.get("hp", stats.get("hp", 1)))
	hp = clampi(hp, 0, int(stats.get("hp", 1)))
	var species_symbol := _record_symbol(species_record)
	return {
		"status": "ok",
		"species": species_symbol,
		"species_id": int(species_record.get("id", -1)),
		"name": _display_text(species_record.get("species_name", {}), species_symbol),
		"level": clamped_level,
		"types": _type_symbols_from_record(species_record),
		"base_stats": base_stats.duplicate(true),
		"ivs": ivs,
		"evs": evs,
		"nature": nature_symbol,
		"nature_info": _battle_nature_info(nature_symbol, nature_record),
		"stats": stats,
		"max_hp": int(stats.get("hp", 1)),
		"hp": hp,
		"fainted": hp <= 0,
		"moves": moves_result.get("moves", []),
		"held_item": _constant_symbol(options.get("held_item", "ITEM_NONE")),
		"ability": _constant_symbol(options.get("ability", "ABILITY_NONE")),
		"friendship": int(options.get("friendship", 0)),
		"source_trace": SOURCE_TRACE.duplicate(),
		"warnings": warnings,
		"unsupported": unsupported,
	}


func create_trainer_party(trainer_id_or_symbol, options: Dictionary = {}) -> Dictionary:
	var trainer := _get_trainer_record(trainer_id_or_symbol)
	if trainer.is_empty():
		return _error_result("unknown_trainer", "Could not resolve trainer %s" % [str(trainer_id_or_symbol)])

	var party_records = trainer.get("party", [])
	if typeof(party_records) != TYPE_ARRAY:
		party_records = []
	var party: Array = []
	var warnings: Array = []
	var unsupported: Array = []
	var limit := int(options.get("limit", party_records.size()))
	limit = clampi(limit, 0, party_records.size())

	for index in range(limit):
		var party_record = party_records[index]
		if typeof(party_record) != TYPE_DICTIONARY:
			continue
		var species_symbol := _constant_symbol(party_record.get("species", {}))
		var level := int(_dict_value(party_record.get("level", {}), 100))
		var move_specs = party_record.get("moves", [])
		if typeof(move_specs) != TYPE_ARRAY:
			move_specs = []
		var mon_options := {
			"ivs": _normalize_stat_values(party_record.get("ivs", {}), DEFAULT_IV),
			"evs": _normalize_stat_values(party_record.get("evs", {}), DEFAULT_EV),
			"moves": move_specs,
			"held_item": party_record.get("held_item", {}),
			"ability": party_record.get("ability", {}),
			"nature": party_record.get("nature", {}),
			"friendship": int(_dict_value(party_record.get("friendship", {}), 0)),
			"move_source_behavior": party_record.get("move_source_behavior", {}),
		}
		var mon := create_battle_mon(species_symbol, level, mon_options)
		mon["trainer_party_index"] = index
		mon["trainer_party_source"] = party_record.get("source", {})
		party.append(mon)
		warnings.append_array(mon.get("warnings", []))
		unsupported.append_array(mon.get("unsupported", []))

	return {
		"status": "ok",
		"trainer": {
			"symbol": _record_symbol(trainer),
			"id": int(trainer.get("id", -1)),
			"name": _display_text(trainer.get("name", {}), _record_symbol(trainer)),
			"battle_type": trainer.get("battle_type", {}),
		},
		"party": party,
		"warnings": warnings,
		"unsupported": unsupported,
		"source_trace": [
			"src/battle_main.c:CreateNPCTrainerParty",
			"src/battle_main.c:CreateNPCTrainerPartyFromTrainer",
			"src/battle_main.c:CustomTrainerPartyAssignMoves",
		],
	}


func create_trainer_battle_state(trainer_id_or_symbol, player_party: Array, options: Dictionary = {}) -> Dictionary:
	var trainer_record := _get_trainer_record(trainer_id_or_symbol)
	if trainer_record.is_empty():
		return _error_result("unknown_trainer", "Could not resolve trainer %s" % [str(trainer_id_or_symbol)])

	var trainer_party_result := create_trainer_party(trainer_id_or_symbol, options.get("trainer_party_options", {}))
	if String(trainer_party_result.get("status", "")) != "ok":
		return trainer_party_result

	var opponent_party = trainer_party_result.get("party", [])
	if typeof(opponent_party) != TYPE_ARRAY:
		opponent_party = []
	if opponent_party.is_empty():
		return _error_result("empty_trainer_party", "Trainer %s has no generated opponent party." % [_record_symbol(trainer_record)])
	var normalized_player_party := _player_party_for_battle_state(player_party, options)
	var fallback_unsupported := _array_value(normalized_player_party.get("unsupported", []))
	var battle_player_party := _array_value(normalized_player_party.get("party", []))

	var battle_options := options.duplicate(true)
	if not battle_options.has("player_active"):
		battle_options["player_active"] = _first_usable_battle_party_index(battle_player_party)
	if not battle_options.has("opponent_active"):
		battle_options["opponent_active"] = 0

	var battle_state := create_single_battle_state(battle_player_party, opponent_party, battle_options)
	var battle_setup := _trainer_battle_setup_metadata(
		trainer_record,
		battle_player_party,
		opponent_party,
		options
	)
	var battle_transition := _dictionary_value(battle_setup.get("battle_transition", {}))
	battle_state["battle_kind"] = "trainer"
	battle_state["battle_type"] = "double" if _trainer_min_party_count(trainer_record) == 2 else "single"
	battle_state["trainer"] = _trainer_summary(trainer_record)
	battle_state["battle_type_flags"] = _trainer_battle_type_flags(trainer_record, options)
	battle_state["battle_setup"] = battle_setup
	battle_state["active_battlers"] = {
		"player": [int(battle_options.get("player_active", 0))],
		"opponent": [int(battle_options.get("opponent_active", 0))],
		"source": "src/battle_setup.c:BattleSetup_StartTrainerBattle -> CB2_InitBattle",
	}
	battle_state["stats_metadata"] = _trainer_battle_stats_metadata()
	battle_state["callback_metadata"] = _trainer_battle_callback_metadata(options)
	battle_state["warnings"] = trainer_party_result.get("warnings", [])
	battle_state["unsupported"] = _trainer_battle_unsupported(options)
	battle_state["unsupported"].append_array(fallback_unsupported)
	battle_state["unsupported"].append_array(_array_value(battle_transition.get("unsupported", [])))
	if battle_state["battle_type"] == "double":
		battle_state["unsupported"].append({
			"code": "trainer_double_battle_not_supported",
			"source": "src/battle_setup.c:GetTrainerBattleType; src/battle_main.c:CB2_InitBattle",
			"detail": "Double trainer battle flags and transition level comparison are recorded, but the current battle state and BattleScene are single-battler only.",
		})
	var trainer_unsupported = trainer_party_result.get("unsupported", [])
	if typeof(trainer_unsupported) == TYPE_ARRAY:
		battle_state["unsupported"].append_array(trainer_unsupported)
	battle_state["unsupported_reason"] = String(battle_transition.get("unsupported_reason", ""))
	battle_state["source_trace"] = _merged_trace(battle_state.get("source_trace", []), [
		"include/constants/battle.h:BATTLE_TYPE_TRAINER",
		"src/battle_setup.c:BattleSetup_StartTrainerBattle",
		"src/battle_setup.c:DoTrainerBattle",
		"src/battle_setup.c:GetTrainerBattleTransition",
		"src/battle_setup.c:sBattleTransitionTable_Trainer",
		"src/battle_main.c:CreateNPCTrainerParty",
		"src/battle_main.c:CB2_InitBattle",
		"src/battle_setup.c:CB2_EndTrainerBattle",
	])
	return battle_state


func create_single_battle_state(player_party: Array, opponent_party: Array, options: Dictionary = {}) -> Dictionary:
	return {
		"status": "ok",
		"battle_type": "single",
		"turn": 0,
		"player_party": player_party.duplicate(true),
		"opponent_party": opponent_party.duplicate(true),
		"active": {
			"player": int(options.get("player_active", 0)),
			"opponent": int(options.get("opponent_active", 0)),
		},
		"source_trace": [
			"src/battle_main.c:CreateNPCTrainerPartyFromTrainer",
			"src/battle_util.c:CalculateMoveDamage",
		],
	}


func create_wild_battle_state(encounter: Dictionary, player_party: Array, options: Dictionary = {}) -> Dictionary:
	var species_symbol := _constant_symbol(encounter.get("species", encounter.get("species_symbol", "")))
	if species_symbol.is_empty():
		return _error_result("missing_wild_species", "Wild encounter does not include a species.")
	var level := int(encounter.get("level", 1))
	var wild_options := {}
	var option_wild = options.get("wild_mon_options", {})
	if typeof(option_wild) == TYPE_DICTIONARY:
		wild_options = option_wild.duplicate(true)
	wild_options["move_source_behavior"] = {
		"kind": "level_up_default",
		"source": "src/wild_encounter.c:CreateWildMon -> GiveMonInitialMoveset",
	}
	var wild_mon := create_battle_mon(species_symbol, level, wild_options)
	if String(wild_mon.get("status", "")) != "ok":
		return wild_mon
	wild_mon["wild_encounter"] = _wild_encounter_summary(encounter)
	wild_mon["enemy_party_index"] = 0
	wild_mon["source_trace"] = _merged_trace(wild_mon.get("source_trace", []), [
		"src/wild_encounter.c:CreateWildMon",
		"src/pokemon.c:CreateMonWithIVs",
		"src/pokemon.c:GiveMonInitialMoveset",
	])

	var battle_options := options.duplicate(true)
	if not battle_options.has("player_active"):
		battle_options["player_active"] = _first_usable_battle_party_index(player_party)
	var battle_state := create_single_battle_state(player_party, [wild_mon], battle_options)
	battle_state["battle_kind"] = "wild"
	battle_state["battle_type_flags"] = _wild_battle_type_flags(options)
	battle_state["wild_encounter"] = _wild_encounter_summary(encounter)
	battle_state["battle_setup"] = _wild_battle_setup_metadata(encounter, player_party, wild_mon, options)
	battle_state["source_trace"] = _merged_trace(battle_state.get("source_trace", []), [
		"src/wild_encounter.c:CreateWildMon",
		"src/wild_encounter.c:StandardWildEncounter",
		"src/wild_encounter.c:SweetScentWildEncounter",
		"src/battle_setup.c:BattleSetup_StartWildBattle",
		"src/battle_setup.c:DoStandardWildBattle",
		"src/battle_setup.c:GetWildBattleTransition",
	])
	battle_state["unsupported"] = _wild_battle_unsupported(options)
	return battle_state


func calculate_type_effectiveness(move_type_symbol: String, defender: Dictionary) -> Dictionary:
	var move_type := _normalize_type_symbol(move_type_symbol)
	var defender_types := _type_symbols_from_battle_record(defender)
	var numerator := 1
	var denominator := 1
	var applied: Array = []
	for defender_type in defender_types:
		var factor := _type_factor(move_type, String(defender_type))
		numerator *= int(factor[0])
		denominator *= int(factor[1])
		applied.append({
			"attacking_type": move_type,
			"defending_type": String(defender_type),
			"numerator": int(factor[0]),
			"denominator": int(factor[1]),
		})
		if numerator == 0:
			break
	var reduced := _reduce_fraction(numerator, denominator)
	return {
		"move_type": move_type,
		"defender_types": defender_types,
		"numerator": int(reduced[0]),
		"denominator": int(reduced[1]),
		"multiplier": 0.0 if int(reduced[0]) == 0 else float(reduced[0]) / float(reduced[1]),
		"result": _effectiveness_result(int(reduced[0]), int(reduced[1])),
		"applied": applied,
		"source": "src/data/types_info.h:gTypeEffectivenessTable",
	}


func calculate_basic_damage(attacker: Dictionary, defender: Dictionary, move: Dictionary, options: Dictionary = {}) -> Dictionary:
	var unsupported: Array = []
	var category := _constant_symbol(move.get("category", ""))
	var move_type := _constant_symbol(move.get("type", ""))
	var power := int(move.get("power", 0))
	if category == "DAMAGE_CATEGORY_STATUS" or power <= 0:
		return {
			"status": "ok",
			"damage": 0,
			"move": move.get("symbol", ""),
			"category": category,
			"effectiveness": calculate_type_effectiveness(move_type, defender),
			"unsupported": [{
				"code": "move_effect_not_executed",
				"source": "src/battle_util.c:DoFixedDamageMoveCalc",
				"detail": "First battle slice only applies ordinary damaging moves.",
			}],
			"source_trace": SOURCE_TRACE.duplicate(),
		}

	var attacker_stats = attacker.get("stats", {})
	var defender_stats = defender.get("stats", {})
	if typeof(attacker_stats) != TYPE_DICTIONARY or typeof(defender_stats) != TYPE_DICTIONARY:
		return _error_result("missing_battle_stats", "Attacker or defender does not have calculated battle stats.")

	var attack_stat_key := "attack" if category == "DAMAGE_CATEGORY_PHYSICAL" else "sp_attack"
	var defense_stat_key := "defense" if category == "DAMAGE_CATEGORY_PHYSICAL" else "sp_defense"
	var attack_stat: int = max(1, int(attacker_stats.get(attack_stat_key, 1)))
	var defense_stat: int = max(1, int(defender_stats.get(defense_stat_key, 1)))
	var level: int = max(1, int(attacker.get("level", 1)))
	var level_term := _idiv(2 * level, 5) + 2
	var base_damage := _idiv(_idiv(power * attack_stat * level_term, defense_stat), 50) + 2
	var roll_percent := clampi(int(options.get("damage_roll_percent", DAMAGE_ROLL_PERCENT_HI)), DAMAGE_ROLL_PERCENT_LO, DAMAGE_ROLL_PERCENT_HI)
	var after_roll := _idiv(base_damage * roll_percent, 100)
	var after_stab := after_roll
	var stab := _has_stab(attacker, move_type)
	if stab:
		after_stab = _apply_fraction(after_stab, 3, 2)
	var effectiveness := calculate_type_effectiveness(move_type, defender)
	var type_numerator := int(effectiveness.get("numerator", 1))
	var type_denominator := int(effectiveness.get("denominator", 1))
	var final_damage := 0
	if type_numerator > 0:
		final_damage = _apply_fraction(after_stab, type_numerator, type_denominator)
		if final_damage == 0:
			final_damage = 1

	unsupported.append({
		"code": "first_pass_damage_omissions",
		"source": "src/battle_util.c:DoMoveDamageCalcVars",
		"detail": "Weather, critical hits, burn/frostbite, protection, abilities, held items, screens, multi-target modifiers, accuracy, and move-specific effects are not applied yet.",
	})

	return {
		"status": "ok",
		"damage": final_damage,
		"base_damage": base_damage,
		"after_roll": after_roll,
		"after_stab": after_stab,
		"stab": stab,
		"damage_roll_percent": roll_percent,
		"move": move.get("symbol", ""),
		"move_type": move_type,
		"category": category,
		"attack_stat": attack_stat_key,
		"attack_stat_value": attack_stat,
		"defense_stat": defense_stat_key,
		"defense_stat_value": defense_stat,
		"effectiveness": effectiveness,
		"unsupported": unsupported,
		"source_trace": SOURCE_TRACE.duplicate(),
	}


func use_move(attacker: Dictionary, defender: Dictionary, move_slot: int = 0, options: Dictionary = {}) -> Dictionary:
	var attacker_after := attacker.duplicate(true)
	var defender_after := defender.duplicate(true)
	var moves = attacker_after.get("moves", [])
	if typeof(moves) != TYPE_ARRAY or move_slot < 0 or move_slot >= moves.size():
		return _error_result("invalid_move_slot", "Move slot %d is not available." % [move_slot])
	var move = moves[move_slot]
	if typeof(move) != TYPE_DICTIONARY:
		return _error_result("invalid_move_record", "Move slot %d is not a move record." % [move_slot])
	var current_pp := int(move.get("current_pp", 0))
	if current_pp <= 0:
		return {
			"status": "no_pp",
			"attacker": attacker_after,
			"defender": defender_after,
			"move": move,
			"messages": [_message("no_pp", "%s has no PP left for %s." % [attacker_after.get("name", attacker_after.get("species", "Pokemon")), move.get("name", move.get("symbol", "move"))])],
			"source_trace": ["src/battle_main.c:CustomTrainerPartyAssignMoves"],
		}

	move["current_pp"] = current_pp - 1
	moves[move_slot] = move
	attacker_after["moves"] = moves

	var damage_result := calculate_basic_damage(attacker_after, defender_after, move, options)
	if String(damage_result.get("status", "ok")) != "ok":
		return damage_result
	var damage := int(damage_result.get("damage", 0))
	var defender_hp: int = max(0, int(defender_after.get("hp", 0)) - damage)
	defender_after["hp"] = defender_hp
	defender_after["fainted"] = defender_hp <= 0

	var messages: Array = []
	messages.append(_message("move_used", "%s used %s." % [attacker_after.get("name", attacker_after.get("species", "Pokemon")), move.get("name", move.get("symbol", "move"))]))
	if damage > 0:
		messages.append(_message("damage", "%s took %d damage." % [defender_after.get("name", defender_after.get("species", "Pokemon")), damage]))
	else:
		messages.append(_message("no_effect", "It had no effect."))
	var effectiveness = damage_result.get("effectiveness", {})
	if typeof(effectiveness) == TYPE_DICTIONARY:
		var result := String(effectiveness.get("result", "normal"))
		if result == "super_effective":
			messages.append(_message("effectiveness", "It is super effective."))
		elif result == "not_very_effective":
			messages.append(_message("effectiveness", "It is not very effective."))
	if bool(defender_after.get("fainted", false)):
		messages.append(_message("fainted", "%s fainted." % [defender_after.get("name", defender_after.get("species", "Pokemon"))]))

	return {
		"status": "ok",
		"attacker": attacker_after,
		"defender": defender_after,
		"move": move,
		"damage": damage_result,
		"messages": messages,
		"source_trace": SOURCE_TRACE.duplicate(),
	}


func execute_player_move_turn(battle_state: Dictionary, move_slot: int = 0, options: Dictionary = {}) -> Dictionary:
	var state := battle_state.duplicate(true)
	var player_party := _array_value(state.get("player_party", []))
	var opponent_party := _array_value(state.get("opponent_party", []))
	var active := _dictionary_value(state.get("active", {}))
	var player_index := int(active.get("player", 0))
	var opponent_index := int(active.get("opponent", 0))
	if player_index < 0 or player_index >= player_party.size():
		return _error_result("invalid_player_active", "Player active index %d is not available." % [player_index])
	if opponent_index < 0 or opponent_index >= opponent_party.size():
		return _error_result("invalid_opponent_active", "Opponent active index %d is not available." % [opponent_index])

	var turn_options := options.duplicate(true)
	if not turn_options.has("damage_roll_percent"):
		turn_options["damage_roll_percent"] = DAMAGE_ROLL_PERCENT_HI
	var move_result := use_move(player_party[player_index], opponent_party[opponent_index], move_slot, turn_options)
	if String(move_result.get("status", "")) != "ok":
		state["last_turn"] = {
			"status": String(move_result.get("status", "error")),
			"actor": "player",
			"move_slot": move_slot,
			"messages": _array_value(move_result.get("messages", [])),
			"source_trace": move_result.get("source_trace", []),
		}
		var blocked_result := build_battle_result(state)
		return {
			"status": String(move_result.get("status", "error")),
			"battle_state": state,
			"messages": _array_value(move_result.get("messages", [])),
			"outcome": String(blocked_result.get("outcome", "")),
			"battle_result": blocked_result,
			"source_trace": move_result.get("source_trace", []),
		}

	player_party[player_index] = move_result.get("attacker", player_party[player_index])
	opponent_party[opponent_index] = move_result.get("defender", opponent_party[opponent_index])
	state["player_party"] = player_party
	state["opponent_party"] = opponent_party
	state["turn"] = int(state.get("turn", 0)) + 1
	state["last_turn"] = {
		"status": "ok",
		"actor": "player",
		"move_slot": move_slot,
		"move": move_result.get("move", {}),
		"damage": move_result.get("damage", {}),
		"messages": _array_value(move_result.get("messages", [])),
		"source_trace": move_result.get("source_trace", []),
	}
	var outcome := _battle_outcome(state)
	state["outcome"] = outcome
	var result_contract := build_battle_result(state, {"outcome": outcome})
	state["battle_result"] = result_contract
	return {
		"status": "ok",
		"turn": int(state.get("turn", 0)),
		"battle_state": state,
		"move_result": move_result,
		"messages": _array_value(move_result.get("messages", [])),
		"outcome": outcome,
		"battle_result": result_contract,
		"unsupported": _array_value(result_contract.get("unsupported", [])),
		"source_trace": _merged_trace(move_result.get("source_trace", []), [
			"src/battle_main.c:HandleTurnActionSelectionState",
		]),
	}


func build_battle_result(battle_state: Dictionary, options: Dictionary = {}) -> Dictionary:
	var outcome := String(options.get("outcome", ""))
	if outcome.is_empty():
		outcome = _battle_outcome(battle_state)
	var unsupported := _array_value(battle_state.get("unsupported", [])).duplicate(true)
	var last_turn := _dictionary_value(battle_state.get("last_turn", {}))
	var damage := _dictionary_value(last_turn.get("damage", {}))
	unsupported.append_array(_array_value(damage.get("unsupported", [])))
	if outcome == "in_progress":
		unsupported.append({
			"code": "battle_resolution_in_progress",
			"source": "src/battle_main.c",
			"detail": "The result contract can be produced mid-battle, but switching, opponent AI, rewards, and full battle-end cleanup wait for later slices.",
		})
	var stats_metadata := _dictionary_value(battle_state.get("stats_metadata", {}))
	var player_party := _array_value(battle_state.get("player_party", [])).duplicate(true)
	var opponent_party := _array_value(battle_state.get("opponent_party", [])).duplicate(true)
	return {
		"status": "ok",
		"outcome": outcome,
		"battle_kind": String(battle_state.get("battle_kind", "")),
		"battle_type": String(battle_state.get("battle_type", "")),
		"battle_type_flags": _array_value(battle_state.get("battle_type_flags", [])),
		"trainer": _dictionary_value(battle_state.get("trainer", {})),
		"wild_encounter": _dictionary_value(battle_state.get("wild_encounter", {})),
		"parties": {
			"player": player_party,
			"opponent": opponent_party,
		},
		"player_party": player_party,
		"opponent_party": opponent_party,
		"stats": {
			"turns": int(battle_state.get("turn", 0)),
			"battle_start": stats_metadata,
			"pending_game_state_mutation": true,
		},
		"unsupported": unsupported,
		"unsupported_reason": String(battle_state.get("unsupported_reason", "")),
		"post_battle": _post_battle_metadata(battle_state, outcome),
		"source_trace": _merged_trace(battle_state.get("source_trace", []), [
			"src/battle_setup.c:CB2_EndTrainerBattle",
			"src/battle_setup.c:BattleSetup_GetTrainerPostBattleScript",
		]),
	}


func _get_registry() -> Node:
	if _registry != null:
		return _registry
	if has_node("/root/DataRegistry"):
		_registry = get_node("/root/DataRegistry")
	return _registry


func _get_species_record(species_id_or_symbol) -> Dictionary:
	var registry := _get_registry()
	if registry == null or not registry.has_method("get_species_record"):
		return {}
	var record = registry.get_species_record(species_id_or_symbol)
	return record if typeof(record) == TYPE_DICTIONARY else {}


func _get_move_record(move_id_or_symbol) -> Dictionary:
	var registry := _get_registry()
	if registry == null or not registry.has_method("get_move_record"):
		return {}
	var record = registry.get_move_record(move_id_or_symbol)
	return record if typeof(record) == TYPE_DICTIONARY else {}


func _get_trainer_record(trainer_id_or_symbol) -> Dictionary:
	var registry := _get_registry()
	if registry == null or not registry.has_method("get_trainer_record"):
		return {}
	var record = registry.get_trainer_record(trainer_id_or_symbol)
	return record if typeof(record) == TYPE_DICTIONARY else {}


func _get_nature_record(nature_id_or_symbol) -> Dictionary:
	var registry := _get_registry()
	if registry == null or not registry.has_method("get_nature_record"):
		return {}
	var record = registry.get_nature_record(nature_id_or_symbol)
	return record if typeof(record) == TYPE_DICTIONARY else {}


func _get_level_up_learnset_record(species_record: Dictionary) -> Dictionary:
	var registry := _get_registry()
	if registry == null:
		return {}
	if registry.has_method("get_level_up_learnset_for_species"):
		var record = registry.get_level_up_learnset_for_species(_record_symbol(species_record))
		return record if typeof(record) == TYPE_DICTIONARY else {}
	if not registry.has_method("get_level_up_learnset_record"):
		return {}
	var learnset_label := _learnset_label_from_species_record(species_record)
	if learnset_label.is_empty():
		return {}
	var fallback_record = registry.get_level_up_learnset_record(learnset_label)
	return fallback_record if typeof(fallback_record) == TYPE_DICTIONARY else {}


func _calculate_stats(species_record: Dictionary, level: int, ivs: Dictionary, evs: Dictionary, nature_symbol: String, nature_record: Dictionary, unsupported: Array) -> Dictionary:
	var base_stats = species_record.get("base_stats", {})
	var stats := {}
	var base_hp := int(base_stats.get("hp", 1))
	var hp_iv := int(ivs.get("hp", DEFAULT_IV))
	var hp_ev := int(evs.get("hp", DEFAULT_EV))
	var max_hp := 1 if _record_symbol(species_record) == "SPECIES_SHEDINJA" else _idiv((2 * base_hp + hp_iv + _idiv(hp_ev, 4)) * level, 100) + level + 10
	stats["hp"] = max_hp
	if nature_record.is_empty():
		unsupported.append({
			"code": "missing_nature_data",
			"source": "src/pokemon.c:gNaturesInfo -> src/pokemon.c:ModifyStatByNature",
			"detail": "Could not resolve generated nature data for %s." % [nature_symbol],
		})
	for stat_key in STAT_KEYS:
		if String(stat_key) == "hp":
			continue
		var base := int(base_stats.get(stat_key, 1))
		var iv := int(ivs.get(stat_key, DEFAULT_IV))
		var ev := int(evs.get(stat_key, DEFAULT_EV))
		var value := _idiv((2 * base + iv + _idiv(ev, 4)) * level, 100) + 5
		stats[String(stat_key)] = _modify_stat_by_nature(value, String(stat_key), nature_record)
	return stats


func _modify_stat_by_nature(value: int, stat_key: String, nature_record: Dictionary) -> int:
	if nature_record.is_empty():
		return value
	var source_stat := String(STAT_KEY_TO_SOURCE_STAT.get(stat_key, ""))
	if source_stat.is_empty():
		return value
	var stat_up := _constant_symbol(nature_record.get("stat_up", {}))
	var stat_down := _constant_symbol(nature_record.get("stat_down", {}))
	if stat_up.is_empty() or stat_down.is_empty() or stat_up == stat_down:
		return value
	if source_stat == stat_up:
		return _idiv(value * 110, 100)
	if source_stat == stat_down:
		return _idiv(value * 90, 100)
	return value


func _battle_nature_info(nature_symbol: String, nature_record: Dictionary) -> Dictionary:
	if nature_record.is_empty():
		return {
			"symbol": nature_symbol,
			"status": "missing",
			"source": "src/pokemon.c:gNaturesInfo",
		}
	return {
		"symbol": _record_symbol(nature_record),
		"id": int(nature_record.get("id", -1)),
		"name": _display_text(nature_record.get("name", {}), _record_symbol(nature_record)),
		"stat_up": _constant_symbol(nature_record.get("stat_up", {})),
		"stat_down": _constant_symbol(nature_record.get("stat_down", {})),
		"neutral": bool(nature_record.get("neutral", false)),
		"source": nature_record.get("source", {}),
	}


func _wild_encounter_summary(encounter: Dictionary) -> Dictionary:
	return {
		"species": _constant_symbol(encounter.get("species", encounter.get("species_symbol", ""))),
		"species_id": int(encounter.get("species_id", -1)),
		"level": int(encounter.get("level", 1)),
		"area": String(encounter.get("area", "")),
		"map": String(encounter.get("map", "")),
		"record_label": String(encounter.get("record_label", "")),
		"slot_index": int(encounter.get("slot_index", -1)),
		"source": "src/wild_encounter.c:TryGenerateWildMon -> CreateWildMon",
	}


func _wild_battle_setup_metadata(encounter: Dictionary, player_party: Array, wild_mon: Dictionary, options: Dictionary) -> Dictionary:
	var battle_flags := _wild_battle_type_flags(options)
	var transition_info := _wild_battle_transition_metadata(player_party, wild_mon, options)
	return {
		"status": "state_created",
		"kind": "wild",
		"battle_setup_function": "BattleSetup_StartWildBattle",
		"standard_function": "DoStandardWildBattle(FALSE)",
		"saved_callback": "CB2_EndWildBattle",
		"battle_type_flags": battle_flags,
		"battle_transition": transition_info,
		"active_player_index": _first_usable_battle_party_index(player_party),
		"active_player_source": "src/battle_controllers.c first valid non-egg, non-fainted player mon",
		"statistics": [
			"IncrementGameStat(GAME_STAT_TOTAL_BATTLES)",
			"IncrementGameStat(GAME_STAT_WILD_BATTLES)",
			"IncrementDailyWildBattles",
			"TryUpdateGymLeaderRematchFromWild",
		],
		"battle_start_task_sequence": [
			"LockPlayerFieldControls",
			"FreezeObjectEvents",
			"StopPlayerAvatar",
			"CreateBattleStartTask(GetWildBattleTransition(), 0)",
			"wait until FldEffPoison_IsActive() is false",
			"BattleTransition_StartOnField",
			"wait until IsBattleTransitionDone()",
			"PrepareForFollowerNPCBattle",
			"CleanupOverworldWindowsAndTilemaps",
			"SetMainCallback2(CB2_InitBattle)",
			"RestartWildEncounterImmunitySteps",
			"ClearPoisonStepCounter",
		],
		"enemy_party_source": "src/wild_encounter.c:CreateWildMon -> gEnemyParty[0]",
		"player_party_count": player_party.size(),
		"wild_encounter": _wild_encounter_summary(encounter),
		"source_trace": [
			"src/wild_encounter.c:CreateWildMon",
			"src/battle_setup.c:BattleSetup_StartWildBattle",
			"src/battle_setup.c:DoStandardWildBattle",
			"src/battle_setup.c:Task_BattleStart",
		],
	}


func _wild_battle_transition_metadata(player_party: Array, wild_mon: Dictionary, options: Dictionary) -> Dictionary:
	var enemy_level := int(wild_mon.get("level", 1))
	var player_level := _first_battle_party_level(player_party)
	var pyramid := bool(options.get("battle_pyramid", options.get("battle_pyramid_layout", false)))
	var enemy_lower := enemy_level < player_level
	var comparison := "enemy_lower" if enemy_lower else "enemy_equal_or_higher"
	var table_column := 0 if enemy_lower else 1
	var transition_type_info := _wild_battle_transition_type_info(options)
	var transition_type := String(transition_type_info.get("transition_type", "TRANSITION_TYPE_NORMAL"))
	var selected := _wild_battle_transition_for_type(transition_type, table_column)
	var selection_source := "src/battle_setup.c:sBattleTransitionTable_Wild[%s][%d]" % [transition_type, table_column]
	if pyramid:
		selected = "B_TRANSITION_BLUR" if enemy_lower else "B_TRANSITION_GRID_SQUARES"
		selection_source = "src/battle_setup.c:GetWildBattleTransition Battle Pyramid override"

	return {
		"status": "selected_metadata",
		"selected": selected,
		"enemy_level": enemy_level,
		"player_level": player_level,
		"comparison": comparison,
		"table_column": table_column,
		"transition_type": transition_type,
		"transition_type_reason": String(transition_type_info.get("reason", "")),
		"transition_table": "" if pyramid else "sBattleTransitionTable_Wild",
		"selection_source": selection_source,
		"map": String(options.get("map", "")),
		"map_type": String(transition_type_info.get("map_type", "")),
		"metatile_behavior": String(transition_type_info.get("metatile_behavior", "")),
		"flash_level": int(transition_type_info.get("flash_level", 0)),
		"battle_pyramid": pyramid,
		"source": "src/battle_setup.c:GetWildBattleTransition",
		"source_trace": [
			"src/battle_setup.c:GetBattleTransitionTypeByMap",
			"src/metatile_behavior.c:MetatileBehavior_IsSurfableWaterOrUnderwater",
			"src/battle_setup.c:GetWildBattleTransition",
			"src/battle_setup.c:sBattleTransitionTable_Wild",
		],
	}


func _wild_battle_transition_type_info(options: Dictionary) -> Dictionary:
	var flash_level := _wild_transition_flash_level(options)
	var behavior_name := _source_symbol(options.get("metatile_behavior", options.get("current_metatile_behavior", "")))
	var map_type := _source_symbol(options.get("map_type", options.get("mapType", options.get("source_map_type", ""))))
	var hinted_transition_type := _transition_type_hint(options)
	if not hinted_transition_type.is_empty():
		return _wild_transition_type_result(
			hinted_transition_type,
			"options.map_transition_type",
			flash_level,
			behavior_name,
			map_type
		)
	if flash_level != 0:
		return _wild_transition_type_result(
			"TRANSITION_TYPE_FLASH",
			"GetFlashLevel",
			flash_level,
			behavior_name,
			map_type
		)
	if SURFABLE_WATER_TRANSITION_BEHAVIORS.has(behavior_name):
		return _wild_transition_type_result(
			"TRANSITION_TYPE_WATER",
			"MetatileBehavior_IsSurfableWaterOrUnderwater",
			flash_level,
			behavior_name,
			map_type
		)
	if map_type == "MAP_TYPE_UNDERGROUND" or map_type == "UNDERGROUND":
		return _wild_transition_type_result(
			"TRANSITION_TYPE_CAVE",
			"gMapHeader.mapType == MAP_TYPE_UNDERGROUND",
			flash_level,
			behavior_name,
			map_type
		)
	if map_type == "MAP_TYPE_UNDERWATER" or map_type == "UNDERWATER":
		return _wild_transition_type_result(
			"TRANSITION_TYPE_WATER",
			"gMapHeader.mapType == MAP_TYPE_UNDERWATER",
			flash_level,
			behavior_name,
			map_type
		)
	return _wild_transition_type_result(
		"TRANSITION_TYPE_NORMAL",
		"default",
		flash_level,
		behavior_name,
		map_type
	)


func _wild_transition_type_result(
	transition_type: String,
	reason: String,
	flash_level: int,
	behavior_name: String,
	map_type: String
) -> Dictionary:
	return {
		"transition_type": transition_type,
		"reason": reason,
		"flash_level": flash_level,
		"metatile_behavior": behavior_name,
		"map_type": map_type,
	}


func _wild_battle_transition_for_type(transition_type: String, table_column: int) -> String:
	var transitions = WILD_BATTLE_TRANSITION_TABLE.get(transition_type, WILD_BATTLE_TRANSITION_TABLE["TRANSITION_TYPE_NORMAL"])
	if typeof(transitions) != TYPE_ARRAY or transitions.is_empty():
		transitions = WILD_BATTLE_TRANSITION_TABLE["TRANSITION_TYPE_NORMAL"]
	var column := clampi(table_column, 0, transitions.size() - 1)
	return String(transitions[column])


func _wild_transition_flash_level(options: Dictionary) -> int:
	if options.has("flash_level"):
		return int(options.get("flash_level", 0))
	if options.has("flashLevel"):
		return int(options.get("flashLevel", 0))
	if bool(options.get("flash_active", options.get("flashActive", false))):
		return 1
	return 0


func _transition_type_hint(options: Dictionary) -> String:
	var raw_hint := _source_symbol(options.get("map_transition_type", options.get("transition_type_hint", "")))
	if raw_hint.is_empty():
		return ""
	if not raw_hint.begins_with("TRANSITION_TYPE_"):
		raw_hint = "TRANSITION_TYPE_%s" % [raw_hint]
	if TRAINER_BATTLE_TRANSITION_TABLE.has(raw_hint) or WILD_BATTLE_TRANSITION_TABLE.has(raw_hint):
		return raw_hint
	return ""


func _first_battle_party_level(player_party: Array) -> int:
	var active_index := _first_usable_battle_party_index(player_party)
	if active_index >= 0 and active_index < player_party.size():
		var active_mon = player_party[active_index]
		if typeof(active_mon) == TYPE_DICTIONARY:
			return max(1, int(active_mon.get("level", 1)))
	return 1


func _first_usable_battle_party_index(player_party: Array) -> int:
	for index in range(player_party.size()):
		var mon = player_party[index]
		if typeof(mon) != TYPE_DICTIONARY:
			continue
		var species := _constant_symbol(mon.get("species", ""))
		if species.is_empty() or species == "SPECIES_NONE":
			continue
		if bool(mon.get("is_egg", false)):
			continue
		if int(mon.get("hp", 0)) <= 0 or bool(mon.get("fainted", false)):
			continue
		return index
	return 0


func _wild_battle_type_flags(options: Dictionary) -> Array:
	var flags: Array = []
	if bool(options.get("npc_follower_wild_battle", false)):
		flags.append("BATTLE_TYPE_MULTI")
		flags.append("BATTLE_TYPE_INGAME_PARTNER")
		flags.append("BATTLE_TYPE_DOUBLE")
	elif bool(options.get("double_wild_battle", false)):
		flags.append("BATTLE_TYPE_DOUBLE")
	if bool(options.get("battle_pyramid", options.get("battle_pyramid_layout", false))):
		flags.append("BATTLE_TYPE_PYRAMID")
	return flags


func _wild_battle_unsupported(options: Dictionary) -> Array:
	var unsupported: Array = [{
		"code": "wild_battle_presentation_not_played",
		"source": "src/battle_setup.c:CreateBattleStartTask/Task_BattleStart",
		"detail": "The battle state and source-order setup metadata are created, but field locking, object freezing, poison wait, battle transition playback, BGM, and battle scene switching still need presentation/runtime integration.",
	}, {
		"code": "wild_personality_nature_gender_ivs_partial",
		"source": "src/wild_encounter.c:CreateWildMon -> GetMonPersonality/CreateMonWithIVs",
		"detail": "First-pass wild battle creation uses BattleEngine default deterministic nature/IV behavior unless explicit options are supplied; Synchronize/gender forcing/random IV/personality generation remain future traced work.",
	}, {
		"code": "wild_held_item_and_form_changes_not_applied",
		"source": "src/battle_main.c:CB2_InitBattle -> SetWildMonHeldItem/TryFormChange",
		"detail": "Held-item assignment, begin-battle form changes, friendship adjustments, and enemy-party count side effects are not applied yet.",
	}]
	if bool(options.get("double_wild_battle", false)) or bool(options.get("npc_follower_wild_battle", false)):
		unsupported.append({
			"code": "wild_double_battle_enemy_slot_one_missing",
			"source": "src/battle_setup.c:BattleSetup_StartDoubleWildBattle",
			"detail": "Only gEnemyParty[0]-equivalent single wild enemy creation is implemented in this slice.",
		})
	return unsupported


func _player_party_for_battle_state(player_party: Array, options: Dictionary) -> Dictionary:
	if not player_party.is_empty():
		return {
			"party": player_party.duplicate(true),
			"unsupported": [],
		}
	if not bool(options.get("allow_empty_player_party_fallback", false)):
		return {
			"party": [],
			"unsupported": [{
				"code": "empty_player_party",
				"source": "src/battle_setup.c:BattleSetup_StartTrainerBattle",
				"detail": "Source trainer battles expect a player party; no fallback was requested.",
			}],
		}

	var fallback_options = options.get("player_party_fallback", {})
	if typeof(fallback_options) != TYPE_DICTIONARY:
		fallback_options = {}
	var species := _constant_symbol(fallback_options.get("species", "SPECIES_TORCHIC"))
	if species.is_empty():
		species = "SPECIES_TORCHIC"
	var level := int(fallback_options.get("level", 5))
	var mon_options := {
		"moves": fallback_options.get("moves", ["MOVE_SCRATCH", "MOVE_GROWL", "MOVE_EMBER"]),
		"nature": fallback_options.get("nature", "NATURE_HARDY"),
	}
	var fallback_mon := create_battle_mon(species, level, mon_options)
	var unsupported := [{
		"code": "empty_player_party_debug_fallback",
		"source": "src/battle_setup.c:BattleSetup_StartTrainerBattle",
		"detail": "A deterministic debug Pokemon was created because the caller supplied no player party.",
	}]
	if String(fallback_mon.get("status", "")) != "ok":
		unsupported.append({
			"code": "empty_player_party_fallback_failed",
			"source": "BattleEngine.create_trainer_battle_state",
			"detail": String(fallback_mon.get("detail", "Could not create fallback player Pokemon.")),
		})
		return {
			"party": [],
			"unsupported": unsupported,
		}
	fallback_mon["debug_fallback"] = true
	return {
		"party": [fallback_mon],
		"unsupported": unsupported,
	}


func _trainer_summary(trainer_record: Dictionary) -> Dictionary:
	return {
		"symbol": _record_symbol(trainer_record),
		"id": int(trainer_record.get("id", -1)),
		"name": _display_text(trainer_record.get("name", {}), _record_symbol(trainer_record)),
		"trainer_class": trainer_record.get("trainer_class", {}),
		"battle_type": trainer_record.get("battle_type", {}),
		"pic": trainer_record.get("pic", {}),
		"mugshot": trainer_record.get("mugshot", {}),
	}


func _trainer_battle_setup_metadata(
	trainer_record: Dictionary,
	player_party: Array,
	opponent_party: Array,
	options: Dictionary
) -> Dictionary:
	var battle_flags := _trainer_battle_type_flags(trainer_record, options)
	var transition_info := _trainer_battle_transition_metadata(
		trainer_record,
		player_party,
		opponent_party,
		options
	)
	return {
		"status": "state_created",
		"kind": "trainer",
		"battle_setup_function": "BattleSetup_StartTrainerBattle",
		"standard_function": "DoTrainerBattle",
		"saved_callback": "CB2_EndTrainerBattle",
		"battle_type_flags": battle_flags,
		"battle_transition": transition_info,
		"active_player_index": _first_usable_battle_party_index(player_party),
		"active_opponent_index": _first_usable_battle_party_index(opponent_party),
		"active_player_source": "src/battle_controllers.c first valid non-egg, non-fainted player mon",
		"callback_metadata": _trainer_battle_callback_metadata(options),
		"statistics": [
			"IncrementGameStat(GAME_STAT_TOTAL_BATTLES)",
			"IncrementGameStat(GAME_STAT_TRAINER_BATTLES)",
		],
		"battle_start_task_sequence": [
			"LockPlayerFieldControls",
			"FreezeObjectEvents",
			"StopPlayerAvatar",
			"gBattleTypeFlags |= BATTLE_TYPE_TRAINER",
			"CreateBattleStartTask(GetTrainerBattleTransition(), 0)",
			"wait until FldEffPoison_IsActive() is false",
			"BattleTransition_StartOnField",
			"wait until IsBattleTransitionDone()",
			"PrepareForFollowerNPCBattle",
			"CleanupOverworldWindowsAndTilemaps",
			"SetMainCallback2(CB2_InitBattle)",
		],
		"trainer": _trainer_summary(trainer_record),
		"player_party_count": player_party.size(),
		"opponent_party_count": opponent_party.size(),
		"source_trace": [
			"src/battle_setup.c:BattleSetup_StartTrainerBattle",
			"src/battle_setup.c:DoTrainerBattle",
			"src/battle_setup.c:GetTrainerBattleTransition",
			"src/battle_setup.c:Task_BattleStart",
		],
	}


func _trainer_battle_transition_metadata(
	trainer_record: Dictionary,
	player_party: Array,
	opponent_party: Array,
	options: Dictionary
) -> Dictionary:
	var trainer_symbol := _record_symbol(trainer_record)
	var mugshot = trainer_record.get("mugshot", {})
	if typeof(mugshot) == TYPE_DICTIONARY and int(mugshot.get("value", 0)) != 0:
		return _trainer_special_transition(
			"B_TRANSITION_MUGSHOT",
			trainer_symbol,
			"src/battle_setup.c:GetTrainerBattleTransition -> DoesTrainerHaveMugshot",
			options
		)

	var trainer_class := _constant_symbol(trainer_record.get("trainer_class", {}))
	if TRAINER_MAGMA_CLASSES.has(trainer_class):
		return _trainer_special_transition(
			"B_TRANSITION_MAGMA",
			trainer_symbol,
			"src/battle_setup.c:GetTrainerBattleTransition Team Magma trainer class branch",
			options
		)
	if TRAINER_AQUA_CLASSES.has(trainer_class):
		return _trainer_special_transition(
			"B_TRANSITION_AQUA",
			trainer_symbol,
			"src/battle_setup.c:GetTrainerBattleTransition Team Aqua trainer class branch",
			options
		)

	var min_party_count := _trainer_min_party_count(trainer_record)
	var enemy_level := _sum_party_levels(opponent_party, min_party_count)
	var player_level := _sum_player_party_levels(player_party, min_party_count)
	var enemy_lower := enemy_level < player_level
	var table_column := 0 if enemy_lower else 1
	var transition_type_info := _wild_battle_transition_type_info(options)
	var transition_type := String(transition_type_info.get("transition_type", "TRANSITION_TYPE_NORMAL"))
	return {
		"status": "selected_metadata",
		"selected": _trainer_battle_transition_for_type(transition_type, table_column),
		"trainer": trainer_symbol,
		"trainer_class": trainer_class,
		"enemy_level_sum": enemy_level,
		"player_level_sum": player_level,
		"min_party_count": min_party_count,
		"comparison": "enemy_lower" if enemy_lower else "enemy_equal_or_higher",
		"table_column": table_column,
		"transition_type": transition_type,
		"transition_type_reason": String(transition_type_info.get("reason", "")),
		"transition_table": "sBattleTransitionTable_Trainer",
		"selection_source": "src/battle_setup.c:sBattleTransitionTable_Trainer[%s][%d]" % [transition_type, table_column],
		"map": String(options.get("map", "")),
		"map_type": String(transition_type_info.get("map_type", "")),
		"metatile_behavior": String(transition_type_info.get("metatile_behavior", "")),
		"flash_level": int(transition_type_info.get("flash_level", 0)),
		"source": "src/battle_setup.c:GetTrainerBattleTransition",
		"source_trace": [
			"src/battle_setup.c:GetBattleTransitionTypeByMap",
			"src/battle_setup.c:GetTrainerBattleTransition",
			"src/battle_setup.c:sBattleTransitionTable_Trainer",
		],
	}


func _trainer_special_transition(
	selected: String,
	trainer_symbol: String,
	selection_source: String,
	options: Dictionary
) -> Dictionary:
	var branch := selected.trim_prefix("B_TRANSITION_").to_lower()
	return {
		"status": "selected_unsupported_placeholder",
		"selected": selected,
		"trainer": trainer_symbol,
		"comparison": "special_case",
		"table_column": -1,
		"transition_type": "TRANSITION_TYPE_SPECIAL",
		"transition_type_reason": "trainer_special_case",
		"transition_table": "",
		"selection_source": selection_source,
		"map": String(options.get("map", "")),
		"source": "src/battle_setup.c:GetTrainerBattleTransition",
		"unsupported_reason": "trainer_transition_%s_placeholder" % [branch],
		"unsupported": [{
			"code": "trainer_transition_%s_placeholder" % [branch],
			"source": selection_source,
			"detail": "The source transition id is selected, but exact mugshot/team transition graphics are not implemented in the first Godot presentation slice.",
		}],
	}


func _trainer_battle_transition_for_type(transition_type: String, table_column: int) -> String:
	var transitions = TRAINER_BATTLE_TRANSITION_TABLE.get(transition_type, TRAINER_BATTLE_TRANSITION_TABLE["TRANSITION_TYPE_NORMAL"])
	if typeof(transitions) != TYPE_ARRAY or transitions.is_empty():
		transitions = TRAINER_BATTLE_TRANSITION_TABLE["TRANSITION_TYPE_NORMAL"]
	var column := clampi(table_column, 0, transitions.size() - 1)
	return String(transitions[column])


func _trainer_min_party_count(trainer_record: Dictionary) -> int:
	var battle_type = trainer_record.get("battle_type", {})
	if typeof(battle_type) == TYPE_DICTIONARY and bool(battle_type.get("is_double", false)):
		return 2
	return 1


func _sum_party_levels(party: Array, count: int) -> int:
	var total := 0
	var remaining := maxi(1, count)
	for mon in party:
		if remaining <= 0:
			break
		if typeof(mon) != TYPE_DICTIONARY:
			continue
		total += max(1, int(mon.get("level", 1)))
		remaining -= 1
	return total


func _sum_player_party_levels(party: Array, count: int) -> int:
	var total := 0
	var remaining := maxi(1, count)
	for mon in party:
		if remaining <= 0:
			break
		if typeof(mon) != TYPE_DICTIONARY:
			continue
		var species := _constant_symbol(mon.get("species", ""))
		if species.is_empty() or species == "SPECIES_NONE":
			continue
		if bool(mon.get("is_egg", false)):
			continue
		if int(mon.get("hp", 0)) <= 0 or bool(mon.get("fainted", false)):
			continue
		total += max(1, int(mon.get("level", 1)))
		remaining -= 1
	return total


func _trainer_battle_type_flags(trainer_record: Dictionary, options: Dictionary) -> Array:
	var flags: Array = ["BATTLE_TYPE_TRAINER"]
	var battle_type = trainer_record.get("battle_type", {})
	if typeof(battle_type) == TYPE_DICTIONARY and bool(battle_type.get("is_double", false)):
		flags.append("BATTLE_TYPE_DOUBLE")
	if bool(options.get("partner_battle", false)):
		flags.append("BATTLE_TYPE_INGAME_PARTNER")
	if bool(options.get("multi_battle", false)):
		flags.append("BATTLE_TYPE_MULTI")
	if bool(options.get("battle_pyramid", options.get("battle_pyramid_layout", false))):
		flags.append("BATTLE_TYPE_PYRAMID")
	if bool(options.get("trainer_hill", false)):
		flags.append("BATTLE_TYPE_TRAINER_HILL")
	return flags


func _trainer_battle_unsupported(options: Dictionary) -> Array:
	var unsupported: Array = [{
		"code": "trainer_battle_presentation_first_slice",
		"source": "src/battle_setup.c:CreateBattleStartTask/Task_BattleStart",
		"detail": "The state records trainer setup, transition metadata, and callback intent; exact transition graphics, trainer intro text, BGM, AI, rewards, rematches, and post-battle scripts remain future traced work.",
	}, {
		"code": "trainer_ai_and_rewards_not_executed",
		"source": "src/battle_main.c/CB2_EndTrainerBattle",
		"detail": "The first battle scene runs deterministic player/opponent move execution only and does not award money, EXP, items, or trainer flags.",
	}]
	if bool(options.get("partner_battle", false)) or bool(options.get("multi_battle", false)):
		unsupported.append({
			"code": "trainer_partner_multi_battle_not_executed",
			"source": "src/battle_setup.c:BattleSetup_StartTrainerBattle",
			"detail": "Partner and multi battle flags are recorded, but ally party setup and multi battle turn flow are not implemented in this slice.",
		})
	if bool(options.get("battle_pyramid", options.get("battle_pyramid_layout", false))) or bool(options.get("trainer_hill", false)):
		unsupported.append({
			"code": "trainer_frontier_party_fill_not_executed",
			"source": "src/battle_setup.c:DoBattlePyramidTrainerHillBattle",
			"detail": "Battle Pyramid and Trainer Hill branch metadata is recorded, but their special party fill and random transition tables remain future traced work.",
		})
	return unsupported


func _trainer_battle_stats_metadata() -> Dictionary:
	return {
		"source": "src/battle_setup.c:DoTrainerBattle",
		"on_battle_start": [
			"IncrementGameStat(GAME_STAT_TOTAL_BATTLES)",
			"IncrementGameStat(GAME_STAT_TRAINER_BATTLES)",
			"TryUpdateGymLeaderRematchFromTrainer",
		],
		"mutated_by_battle_engine": false,
	}


func _trainer_battle_callback_metadata(options: Dictionary) -> Dictionary:
	return {
		"saved_callback": String(options.get("saved_callback", "CB2_EndTrainerBattle")),
		"battle_callback": "CB2_InitBattle",
		"return_to_field_callback": "CB2_ReturnToFieldContinueScriptPlayMapMusic",
		"whiteout_callback": "CB2_WhiteOut",
		"post_battle_script_resolver": "BattleSetup_GetTrainerPostBattleScript",
		"source_trace": [
			"src/battle_setup.c:BattleSetup_StartTrainerBattle",
			"src/battle_setup.c:CB2_EndTrainerBattle",
			"src/battle_setup.c:BattleSetup_GetTrainerPostBattleScript",
		],
	}


func _battle_outcome(battle_state: Dictionary) -> String:
	var player_has_usable := _party_has_usable_mon(_array_value(battle_state.get("player_party", [])))
	var opponent_has_usable := _party_has_usable_mon(_array_value(battle_state.get("opponent_party", [])))
	if not player_has_usable and not opponent_has_usable:
		return "draw"
	if not opponent_has_usable:
		return "player_won"
	if not player_has_usable:
		return "opponent_won"
	return "in_progress"


func _party_has_usable_mon(party: Array) -> bool:
	for mon in party:
		if typeof(mon) != TYPE_DICTIONARY:
			continue
		var species := _constant_symbol(mon.get("species", ""))
		if species.is_empty() or species == "SPECIES_NONE":
			continue
		if bool(mon.get("is_egg", false)):
			continue
		if int(mon.get("hp", 0)) <= 0 or bool(mon.get("fainted", false)):
			continue
		return true
	return false


func _post_battle_metadata(battle_state: Dictionary, outcome: String) -> Dictionary:
	var callback_metadata := _dictionary_value(battle_state.get("callback_metadata", {}))
	var battle_kind := String(battle_state.get("battle_kind", ""))
	var post_battle := {
		"battle_kind": battle_kind,
		"outcome": outcome,
		"saved_callback": String(callback_metadata.get("saved_callback", "")),
		"source_trace": [
			"src/battle_setup.c:CB2_EndTrainerBattle",
			"src/battle_setup.c:BattleSetup_GetTrainerPostBattleScript",
		],
	}
	if battle_kind == "trainer":
		post_battle["post_battle_script_resolver"] = String(callback_metadata.get("post_battle_script_resolver", "BattleSetup_GetTrainerPostBattleScript"))
		post_battle["return_to_field_callback"] = String(callback_metadata.get("return_to_field_callback", "CB2_ReturnToFieldContinueScriptPlayMapMusic"))
		post_battle["whiteout_callback"] = String(callback_metadata.get("whiteout_callback", "CB2_WhiteOut"))
		post_battle["on_player_win"] = [
			"SetMainCallback2(CB2_ReturnToFieldContinueScriptPlayMapMusic)",
			"DowngradeBadPoison",
			"RegisterTrainerInMatchCall",
			"SetBattledTrainersFlags",
		]
		post_battle["on_player_loss"] = [
			"SetMainCallback2(CB2_WhiteOut) unless no-whiteout/frontier/no-alive-mon exceptions apply",
		]
	else:
		post_battle["return_to_field_callback"] = "CB2_EndWildBattle"
	return post_battle


func _merged_trace(existing, extra: Array) -> Array:
	var trace: Array = []
	if typeof(existing) == TYPE_ARRAY:
		for item in existing:
			var value := String(item)
			if not value.is_empty() and not trace.has(value):
				trace.append(value)
	for item in extra:
		var value := String(item)
		if not value.is_empty() and not trace.has(value):
			trace.append(value)
	return trace


func _move_specs_for_initial_learnset(species_record: Dictionary, level: int, unsupported: Array) -> Array:
	var learnset_label := _learnset_label_from_species_record(species_record)
	var learnset_record := _get_level_up_learnset_record(species_record)
	if learnset_record.is_empty():
		unsupported.append({
			"code": "missing_level_up_learnset_data",
			"source": "src/battle_main.c:CustomTrainerPartyAssignMoves -> src/pokemon.c:GiveBoxMonInitialMoveset",
			"detail": "Could not resolve generated level-up learnset %s for %s." % [learnset_label, _record_symbol(species_record)],
		})
		return []

	var selected: Array = []
	var entries = learnset_record.get("moves", [])
	if typeof(entries) != TYPE_ARRAY:
		return selected

	for entry in entries:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var learn_level := int(entry.get("level", 0))
		if learn_level > level:
			break
		if learn_level == 0:
			continue
		var move_record = entry.get("move", {})
		if typeof(move_record) != TYPE_DICTIONARY:
			continue
		var move_key = _move_lookup_key(move_record)
		if String(move_key).is_empty() or String(move_key) == "MOVE_NONE":
			continue

		var already_known := false
		for selected_move in selected:
			if String(_move_lookup_key(selected_move)) == String(move_key):
				already_known = true
				break
		if already_known:
			continue

		var move_spec: Dictionary = move_record.duplicate(true)
		move_spec["learnset"] = learnset_label
		move_spec["learnset_level"] = learn_level
		move_spec["source"] = entry.get("source", {})
		move_spec["assignment_source"] = "src/pokemon.c:GiveBoxMonInitialMoveset"
		if selected.size() < MAX_MON_MOVES:
			selected.append(move_spec)
		else:
			selected.remove_at(0)
			selected.append(move_spec)
	return selected


func _build_move_slots(move_specs) -> Dictionary:
	var moves: Array = []
	var warnings: Array = []
	var unsupported: Array = []
	if typeof(move_specs) != TYPE_ARRAY:
		return {"moves": moves, "warnings": warnings, "unsupported": unsupported}
	for move_spec in move_specs:
		if moves.size() >= MAX_MON_MOVES:
			break
		var move_key = _move_lookup_key(move_spec)
		if String(move_key).is_empty() or String(move_key) == "MOVE_NONE":
			continue
		var move_record := _get_move_record(move_key)
		if move_record.is_empty():
			warnings.append({
				"code": "unknown_move",
				"move": move_key,
				"source": move_spec.get("source", {}) if typeof(move_spec) == TYPE_DICTIONARY else {},
			})
			continue
		var symbol := _record_symbol(move_record)
		var assignment_source := "src/battle_main.c:CustomTrainerPartyAssignMoves"
		var learnset_source := {}
		if typeof(move_spec) == TYPE_DICTIONARY:
			assignment_source = String(move_spec.get("assignment_source", assignment_source))
			learnset_source = {
				"label": String(move_spec.get("learnset", "")),
				"level": int(move_spec.get("learnset_level", 0)),
				"entry": move_spec.get("source", {}),
			}
		var source_info := {
			"move_data": move_record.get("source", {}),
			"assignment": assignment_source,
			"pp": "%s -> GetMovePP" % [assignment_source],
		}
		if typeof(learnset_source) == TYPE_DICTIONARY and not String(learnset_source.get("label", "")).is_empty():
			source_info["learnset"] = learnset_source
		moves.append({
			"id": int(move_record.get("id", -1)),
			"symbol": symbol,
			"name": _display_text(move_record.get("name", {}), symbol),
			"effect": _constant_symbol(move_record.get("effect", "")),
			"type": _constant_symbol(move_record.get("type", "")),
			"category": _constant_symbol(move_record.get("category", "")),
			"power": int(move_record.get("power", 0)),
			"accuracy": int(move_record.get("accuracy", 0)),
			"max_pp": int(move_record.get("pp", 0)),
			"current_pp": int(move_record.get("pp", 0)),
			"source": source_info,
		})
	return {"moves": moves, "warnings": warnings, "unsupported": unsupported}


func _move_lookup_key(move_spec):
	if typeof(move_spec) == TYPE_DICTIONARY:
		var symbol := String(move_spec.get("symbol", ""))
		if not symbol.is_empty():
			return symbol
		if move_spec.has("value") and move_spec.get("value") != null:
			return int(move_spec.get("value"))
		return ""
	if typeof(move_spec) == TYPE_INT or typeof(move_spec) == TYPE_FLOAT:
		return int(move_spec)
	return String(move_spec)


func _normalize_stat_values(value, default_value: int) -> Dictionary:
	var stats := {}
	for stat_key in STAT_KEYS:
		stats[String(stat_key)] = default_value
	if typeof(value) != TYPE_DICTIONARY:
		return stats
	var raw_values = value.get("values", value)
	if typeof(raw_values) != TYPE_DICTIONARY:
		return stats
	for stat_key in STAT_KEYS:
		if raw_values.has(stat_key):
			stats[String(stat_key)] = int(raw_values.get(stat_key, default_value))
	return stats


func _dict_value(value, default_value):
	if typeof(value) == TYPE_DICTIONARY:
		return value.get("value", default_value)
	if value == null:
		return default_value
	return value


func _dictionary_value(value) -> Dictionary:
	return value if typeof(value) == TYPE_DICTIONARY else {}


func _array_value(value) -> Array:
	return value if typeof(value) == TYPE_ARRAY else []


func _constant_symbol(value) -> String:
	if typeof(value) == TYPE_DICTIONARY:
		return String(value.get("symbol", ""))
	var symbol := String(value)
	return symbol


func _source_symbol(value) -> String:
	return _constant_symbol(value).strip_edges().to_upper()


func _record_symbol(record: Dictionary) -> String:
	return String(record.get("symbol", ""))


func _learnset_label_from_species_record(species_record: Dictionary) -> String:
	var learnset_label := String(species_record.get("level_up_learnset", ""))
	if not learnset_label.is_empty():
		return learnset_label
	var source_references = species_record.get("source_references", {})
	if typeof(source_references) == TYPE_DICTIONARY:
		learnset_label = String(source_references.get("level_up_learnset", ""))
	return learnset_label


func _display_text(value, fallback: String) -> String:
	if typeof(value) == TYPE_DICTIONARY:
		var display := String(value.get("display_text", ""))
		if not display.is_empty():
			return display
		var source_text := String(value.get("source_text", ""))
		if not source_text.is_empty():
			return source_text
	return fallback


func _type_symbols_from_record(species_record: Dictionary) -> Array:
	var types: Array = []
	var raw_types = species_record.get("types", [])
	if typeof(raw_types) != TYPE_ARRAY:
		return types
	for type_record in raw_types:
		var type_symbol := _normalize_type_symbol(_constant_symbol(type_record))
		if not type_symbol.is_empty() and not types.has(type_symbol):
			types.append(type_symbol)
	return types


func _type_symbols_from_battle_record(record: Dictionary) -> Array:
	var types = record.get("types", [])
	if typeof(types) == TYPE_ARRAY:
		var normalized_types: Array = []
		for type_value in types:
			var type_symbol := _normalize_type_symbol(_constant_symbol(type_value))
			if not type_symbol.is_empty() and not normalized_types.has(type_symbol):
				normalized_types.append(type_symbol)
		return normalized_types
	var species := _get_species_record(record.get("species", ""))
	if not species.is_empty():
		return _type_symbols_from_record(species)
	return []


func _normalize_type_symbol(type_symbol: String) -> String:
	if type_symbol.is_empty():
		return ""
	if type_symbol.begins_with("TYPE_"):
		return type_symbol
	return "TYPE_%s" % [type_symbol.to_upper()]


func _type_factor(move_type: String, defender_type: String) -> Array:
	var attacking_table = TYPE_EFFECTIVENESS.get(move_type, {})
	if typeof(attacking_table) != TYPE_DICTIONARY:
		return [1, 1]
	var factor = attacking_table.get(defender_type, [1, 1])
	return factor if typeof(factor) == TYPE_ARRAY and factor.size() == 2 else [1, 1]


func _has_stab(attacker: Dictionary, move_type: String) -> bool:
	if move_type == "TYPE_MYSTERY" or move_type.is_empty():
		return false
	return _type_symbols_from_battle_record(attacker).has(move_type)


func _effectiveness_result(numerator: int, denominator: int) -> String:
	if numerator == 0:
		return "immune"
	if numerator > denominator:
		return "super_effective"
	if numerator < denominator:
		return "not_very_effective"
	return "normal"


func _reduce_fraction(numerator: int, denominator: int) -> Array:
	if numerator == 0:
		return [0, 1]
	var divisor := _gcd(abs(numerator), abs(denominator))
	return [_idiv(numerator, divisor), _idiv(denominator, divisor)]


func _gcd(a: int, b: int) -> int:
	var x := a
	var y := b
	while y != 0:
		var next := x % y
		x = y
		y = next
	return max(1, x)


func _apply_fraction(value: int, numerator: int, denominator: int) -> int:
	if numerator == 0:
		return 0
	return _idiv(value * numerator, max(1, denominator))


func _idiv(numerator: int, denominator: int) -> int:
	if denominator == 0:
		return 0
	return int(numerator / denominator)


func _message(kind: String, text: String) -> Dictionary:
	return {
		"kind": kind,
		"text": text,
		"source": "first_pass_battle_debug_message",
		"final_text_source_pending": "src/battle_message.c",
	}


func _error_result(code: String, detail: String) -> Dictionary:
	return {
		"status": "error",
		"error": code,
		"detail": detail,
		"source_trace": SOURCE_TRACE.duplicate(),
	}
