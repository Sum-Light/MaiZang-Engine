extends Node

const MAX_MON_MOVES := 4
const DEFAULT_IV := 31
const DEFAULT_EV := 0
const DAMAGE_ROLL_PERCENT_LO := 85
const DAMAGE_ROLL_PERCENT_HI := 100
const STAT_KEYS := ["hp", "attack", "defense", "speed", "sp_attack", "sp_defense"]
const NEUTRAL_NATURES := {
	"NATURE_HARDY": true,
	"NATURE_DOCILE": true,
	"NATURE_SERIOUS": true,
	"NATURE_BASHFUL": true,
	"NATURE_QUIRKY": true,
}
const SOURCE_TRACE := [
	"src/pokemon.c:CalculateMonStats",
	"src/pokemon.c:ModifyStatByNature",
	"src/battle_main.c:CreateNPCTrainerPartyFromTrainer",
	"src/battle_main.c:CustomTrainerPartyAssignMoves",
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
	var stats := _calculate_stats(species_record, clamped_level, ivs, evs, nature_symbol, unsupported)
	var moves_result := _build_move_slots(options.get("moves", []))
	warnings.append_array(moves_result.get("warnings", []))
	unsupported.append_array(moves_result.get("unsupported", []))

	var move_source_behavior = options.get("move_source_behavior", {})
	if moves_result.get("moves", []).is_empty() and typeof(move_source_behavior) == TYPE_DICTIONARY:
		if String(move_source_behavior.get("kind", "")) == "level_up_default":
			unsupported.append({
				"code": "missing_level_up_learnset_data",
				"source": "src/battle_main.c:CustomTrainerPartyAssignMoves",
				"detail": "Source would call GiveMonInitialMoveset, but generated learnset data is not available yet.",
			})

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


func _calculate_stats(species_record: Dictionary, level: int, ivs: Dictionary, evs: Dictionary, nature_symbol: String, unsupported: Array) -> Dictionary:
	var base_stats = species_record.get("base_stats", {})
	var stats := {}
	var base_hp := int(base_stats.get("hp", 1))
	var hp_iv := int(ivs.get("hp", DEFAULT_IV))
	var hp_ev := int(evs.get("hp", DEFAULT_EV))
	var max_hp := 1 if _record_symbol(species_record) == "SPECIES_SHEDINJA" else _idiv((2 * base_hp + hp_iv + _idiv(hp_ev, 4)) * level, 100) + level + 10
	stats["hp"] = max_hp
	for stat_key in STAT_KEYS:
		if String(stat_key) == "hp":
			continue
		var base := int(base_stats.get(stat_key, 1))
		var iv := int(ivs.get(stat_key, DEFAULT_IV))
		var ev := int(evs.get(stat_key, DEFAULT_EV))
		var value := _idiv((2 * base + iv + _idiv(ev, 4)) * level, 100) + 5
		if not NEUTRAL_NATURES.has(nature_symbol):
			unsupported.append({
				"code": "non_neutral_nature_modifier_not_applied",
				"source": "src/pokemon.c:ModifyStatByNature",
				"detail": "%s stat modifiers require gNaturesInfo export before source-faithful application." % [nature_symbol],
			})
		stats[String(stat_key)] = value
	return stats


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
			"source": {
				"move_data": move_record.get("source", {}),
				"assignment": "src/battle_main.c:CustomTrainerPartyAssignMoves",
				"pp": "src/battle_main.c:CustomTrainerPartyAssignMoves -> GetMovePP",
			},
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
