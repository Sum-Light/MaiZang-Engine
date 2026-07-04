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
	var comparison := "enemy_lower" if enemy_level < player_level else "enemy_equal_or_higher"
	var selected := ""
	if pyramid:
		selected = "B_TRANSITION_BLUR" if enemy_level < player_level else "B_TRANSITION_GRID_SQUARES"
	else:
		selected = "sBattleTransitionTable_Wild[GetBattleTransitionTypeByMap()][0]" if enemy_level < player_level else "sBattleTransitionTable_Wild[GetBattleTransitionTypeByMap()][1]"
	return {
		"status": "selected_metadata",
		"selected": selected,
		"enemy_level": enemy_level,
		"player_level": player_level,
		"comparison": comparison,
		"battle_pyramid": pyramid,
		"source": "src/battle_setup.c:GetWildBattleTransition",
		"notes": "Map-specific transition type is not resolved until generated battle transition presentation is implemented.",
	}


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


func _constant_symbol(value) -> String:
	if typeof(value) == TYPE_DICTIONARY:
		return String(value.get("symbol", ""))
	var symbol := String(value)
	return symbol


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
