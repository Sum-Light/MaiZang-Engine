extends Node

const PARTY_SIZE := 6
const SPECIES_NONE := "SPECIES_NONE"
const ITEM_NONE := "ITEM_NONE"
const SOURCE_TRACE := [
	"src/pokemon.c:GetEvolutionTargetSpecies",
	"src/pokemon.c:DoesMonMeetAdditionalConditions",
	"src/pokemon.c:GetSpeciesPreEvolution",
	"src/evolution_scene.c:TryCreateSplitEvoMon",
	"src/evolution_scene.c:CreateShedinja",
]

const AMPED_NATURES := [
	"NATURE_HARDY",
	"NATURE_BRAVE",
	"NATURE_ADAMANT",
	"NATURE_NAUGHTY",
	"NATURE_DOCILE",
	"NATURE_IMPISH",
	"NATURE_LAX",
	"NATURE_HASTY",
	"NATURE_JOLLY",
	"NATURE_NAIVE",
	"NATURE_RASH",
	"NATURE_SASSY",
	"NATURE_QUIRKY",
]

const LOW_KEY_NATURES := [
	"NATURE_LONELY",
	"NATURE_BOLD",
	"NATURE_RELAXED",
	"NATURE_TIMID",
	"NATURE_SERIOUS",
	"NATURE_MODEST",
	"NATURE_MILD",
	"NATURE_QUIET",
	"NATURE_BASHFUL",
	"NATURE_CALM",
	"NATURE_GENTLE",
	"NATURE_CAREFUL",
]

var _registry: Node = null


func configure_registry(registry: Node) -> void:
	_registry = registry


func get_evolution_target_species(mon: Dictionary, mode: String = "EVO_MODE_NORMAL", options: Dictionary = {}) -> Dictionary:
	var source_species_key = _mon_species_key(mon)
	var species_record := _get_species_record(source_species_key)
	if species_record.is_empty():
		return _error_result("unknown_species", "Could not resolve species %s." % [str(source_species_key)])

	var source_species := _record_symbol(species_record)
	var normalized_mode := _normalize_mode(mode)
	var evo_state := String(options.get("evo_state", "CHECK_EVO"))
	var base_result := _base_result(source_species, normalized_mode)
	base_result["evo_state"] = evo_state

	var evolutions := _get_evolutions_for_species(source_species)
	if evolutions.is_empty():
		return base_result

	var held_item := _mon_held_item_symbol(mon)
	var hold_effect := _item_hold_effect_symbol(held_item)
	if hold_effect == "HOLD_EFFECT_PREVENT_EVOLVE" and normalized_mode != "EVO_MODE_ITEM_CHECK" and source_species != "SPECIES_KADABRA":
		base_result["status"] = "blocked"
		base_result["block_reason"] = "held_item_prevent_evolve"
		base_result["held_item"] = held_item
		base_result["source"] = "src/pokemon.c:GetEvolutionTargetSpecies Everstone guard"
		return base_result

	var can_stop := bool(options.get("can_stop_evolution", true))
	var unsupported: Array = []
	var inspected: Array = []

	for index in range(evolutions.size()):
		var evolution = evolutions[index]
		if typeof(evolution) != TYPE_DICTIONARY:
			continue
		var target_symbol := _target_species_symbol(evolution)
		if target_symbol.is_empty() or target_symbol == SPECIES_NONE:
			continue

		var primary := _primary_method_result(evolution, normalized_mode, mon, options)
		inspected.append(primary)
		if not bool(primary.get("met", false)):
			continue

		var condition_options := options.duplicate(true)
		condition_options["mode"] = normalized_mode
		condition_options["evo_state"] = evo_state
		condition_options["can_stop_evolution"] = can_stop
		if normalized_mode == "EVO_MODE_TRADE":
			condition_options["trade_partner"] = options.get("trade_partner", {})
		if normalized_mode == "EVO_MODE_BATTLE_SPECIAL":
			condition_options["party_id"] = _evolution_item_value(options, PARTY_SIZE)

		var conditions := does_mon_meet_additional_conditions(mon, _array_field(evolution, "conditions"), condition_options)
		unsupported.append_array(_array_field(conditions, "unsupported"))
		can_stop = bool(conditions.get("can_stop_evolution", can_stop))
		if not bool(conditions.get("met", false)):
			continue

		if normalized_mode == "EVO_MODE_ITEM_USE" or normalized_mode == "EVO_MODE_ITEM_CHECK":
			can_stop = false

		var result := _base_result(source_species, normalized_mode)
		result["status"] = "ok"
		result["target_species"] = target_symbol
		result["target_species_id"] = _target_species_id(evolution)
		result["matched_index"] = int(evolution.get("index", index))
		result["evolution"] = evolution.duplicate(true)
		result["primary_method"] = primary
		result["conditions"] = _array_field(conditions, "conditions")
		result["can_stop_evolution"] = can_stop
		result["pending_item_removals"] = _array_field(conditions, "pending_item_removals")
		result["unsupported"] = unsupported
		result["inspected"] = inspected
		result["evo_state"] = evo_state
		if bool(mon.get("gmax_factor", false)):
			result["unsupported"].append({
				"code": "gmax_factor_exception_not_evaluated",
				"source": "src/pokemon.c:GetEvolutionTargetSpecies -> GetGMaxTargetSpecies",
				"detail": "Generated form-change data is not available in this runtime slice.",
			})
		return result

	base_result["unsupported"] = unsupported
	base_result["inspected"] = inspected
	base_result["can_stop_evolution"] = can_stop
	return base_result


func does_mon_meet_additional_conditions(mon: Dictionary, conditions: Array, options: Dictionary = {}) -> Dictionary:
	var result := {
		"status": "ok",
		"met": true,
		"conditions": [],
		"pending_item_removals": [],
		"can_stop_evolution": bool(options.get("can_stop_evolution", true)),
		"unsupported": [],
		"source_trace": ["src/pokemon.c:DoesMonMeetAdditionalConditions"],
	}
	var evo_state := String(options.get("evo_state", "CHECK_EVO"))
	for condition_record in conditions:
		if typeof(condition_record) != TYPE_DICTIONARY:
			continue
		var evaluated := _evaluate_condition(mon, condition_record, options, result)
		result["conditions"].append(evaluated)
		if not bool(evaluated.get("met", false)):
			result["met"] = false
			return result
	return result


func get_species_pre_evolution(species_id_or_symbol) -> Dictionary:
	var registry := _get_registry()
	if registry == null or not registry.has_method("get_pre_evolution_records_for_species"):
		return _error_result("registry_missing_pre_evolution_lookup", "DataRegistry pre-evolution lookup is unavailable.")
	var records = registry.get_pre_evolution_records_for_species(species_id_or_symbol)
	if typeof(records) != TYPE_ARRAY or records.is_empty():
		return {
			"status": "no_evolution",
			"target_species": _normalize_species_symbol(String(species_id_or_symbol)),
			"source_species": SPECIES_NONE,
			"source_trace": ["src/pokemon.c:GetSpeciesPreEvolution"],
		}

	var best_record: Dictionary = {}
	var best_id := 2147483647
	for record in records:
		if typeof(record) != TYPE_DICTIONARY:
			continue
		var source_species = record.get("source_species", {})
		var source_id := best_id
		if typeof(source_species) == TYPE_DICTIONARY and source_species.has("value") and source_species.get("value") != null:
			source_id = int(source_species.get("value"))
		if source_id < best_id:
			best_id = source_id
			best_record = record

	if best_record.is_empty():
		return _error_result("invalid_pre_evolution_record", "Generated pre-evolution record is malformed.")
	var evolution = best_record.get("evolution", {})
	var target_symbol := SPECIES_NONE
	if typeof(evolution) == TYPE_DICTIONARY:
		target_symbol = _target_species_symbol(evolution)
	return {
		"status": "ok",
		"source_species": String(best_record.get("source_species_symbol", SPECIES_NONE)),
		"source_species_id": best_id,
		"target_species": target_symbol,
		"record": best_record.duplicate(true),
		"source_trace": ["src/pokemon.c:GetSpeciesPreEvolution"],
	}


func get_split_evolution_candidate(pre_evo_species, post_evo_species, mon: Dictionary, options: Dictionary = {}) -> Dictionary:
	var pre_record := _get_species_record(pre_evo_species)
	var post_record := _get_species_record(post_evo_species)
	if pre_record.is_empty():
		return _error_result("unknown_pre_evolution_species", "Could not resolve pre-evolution species %s." % [str(pre_evo_species)])
	if post_record.is_empty():
		return _error_result("unknown_post_evolution_species", "Could not resolve post-evolution species %s." % [str(post_evo_species)])

	var pre_symbol := _record_symbol(pre_record)
	var post_symbol := _record_symbol(post_record)
	var evolutions := _get_evolutions_for_species(pre_symbol)
	for index in range(evolutions.size()):
		var evolution = evolutions[index]
		if typeof(evolution) != TYPE_DICTIONARY:
			continue
		if _method_symbol(evolution) != "EVO_SPLIT_FROM_EVO":
			continue
		if not _constant_matches(_dict_field(evolution, "param"), post_symbol):
			continue

		var party_count := int(options.get("party_count", _party_count(options.get("party", []))))
		if party_count >= PARTY_SIZE:
			return {
				"status": "blocked",
				"block_reason": "party_full",
				"source_species": pre_symbol,
				"post_evolution_species": post_symbol,
				"target_species": SPECIES_NONE,
				"evolution": evolution.duplicate(true),
				"source_trace": ["src/evolution_scene.c:TryCreateSplitEvoMon"],
			}

		var condition_options := options.duplicate(true)
		condition_options["evo_state"] = "CHECK_EVO"
		var conditions := does_mon_meet_additional_conditions(mon, _array_field(evolution, "conditions"), condition_options)
		if not bool(conditions.get("met", false)):
			return {
				"status": "no_evolution",
				"source_species": pre_symbol,
				"post_evolution_species": post_symbol,
				"target_species": SPECIES_NONE,
				"evolution": evolution.duplicate(true),
				"conditions": _array_field(conditions, "conditions"),
				"unsupported": _array_field(conditions, "unsupported"),
				"source_trace": ["src/evolution_scene.c:TryCreateSplitEvoMon"],
			}

		var target_symbol := _target_species_symbol(evolution)
		var pending_removals := _array_field(conditions, "pending_item_removals")
		pending_removals.append({
			"kind": "bag_item",
			"item": "ITEM_POKE_BALL",
			"count": 1,
			"source": "src/evolution_scene.c:CreateShedinja P_SHEDINJA_BALL >= GEN_4",
		})
		return {
			"status": "ok",
			"source_species": pre_symbol,
			"post_evolution_species": post_symbol,
			"target_species": target_symbol,
			"target_species_id": _target_species_id(evolution),
			"matched_index": int(evolution.get("index", index)),
			"evolution": evolution.duplicate(true),
			"conditions": _array_field(conditions, "conditions"),
			"pending_item_removals": pending_removals,
			"clone_template": {
				"copy_from_source_mon": true,
				"set_species": target_symbol,
				"nickname_source": "GetSpeciesName",
				"clear_held_item": true,
				"clear_markings": true,
				"clear_status": true,
				"clear_mail": true,
				"pokeball": "ITEM_POKE_BALL",
				"recalculate_stats": true,
				"set_pokedex_seen_caught": true,
			},
			"source_trace": [
				"src/evolution_scene.c:TryCreateSplitEvoMon",
				"src/evolution_scene.c:CreateShedinja",
			],
		}

	return {
		"status": "no_evolution",
		"source_species": pre_symbol,
		"post_evolution_species": post_symbol,
		"target_species": SPECIES_NONE,
		"source_trace": ["src/evolution_scene.c:TryCreateSplitEvoMon"],
	}


func _evaluate_condition(mon: Dictionary, condition_record: Dictionary, options: Dictionary, aggregate_result: Dictionary) -> Dictionary:
	var condition_symbol := _constant_symbol(condition_record.get("condition", {}))
	var arg1 := _dict_field(condition_record, "arg1")
	var arg2 := _dict_field(condition_record, "arg2")
	var arg3 := _dict_field(condition_record, "arg3")
	var met := false
	var detail := ""
	var unsupported: Array = []
	var pending_removals: Array = []
	var evo_state := String(options.get("evo_state", "CHECK_EVO"))

	match condition_symbol:
		"IF_GENDER":
			met = _symbol_or_value_matches(_mon_gender(mon), _mon_gender_value(mon), arg1)
		"IF_MIN_FRIENDSHIP":
			met = _mon_friendship(mon) >= _value_field(arg1)
		"IF_ATK_GT_DEF":
			met = _mon_attack(mon) > _mon_defense(mon)
		"IF_ATK_EQ_DEF":
			met = _mon_attack(mon) == _mon_defense(mon)
		"IF_ATK_LT_DEF":
			met = _mon_attack(mon) < _mon_defense(mon)
		"IF_TIME":
			var time_value = _context_value(options, "time_of_day", null)
			if time_value == null:
				unsupported.append(_missing_context("time_of_day", condition_symbol))
			met = time_value != null and _symbol_or_value_matches(_constant_symbol(time_value), _numeric_value(time_value, -1), arg1)
		"IF_NOT_TIME":
			var time_value_not = _context_value(options, "time_of_day", null)
			if time_value_not == null:
				unsupported.append(_missing_context("time_of_day", condition_symbol))
			met = time_value_not != null and not _symbol_or_value_matches(_constant_symbol(time_value_not), _numeric_value(time_value_not, -1), arg1)
		"IF_HOLD_ITEM":
			met = _item_matches(_mon_held_item_symbol(mon), _mon_held_item_id(mon), arg1)
			if met:
				pending_removals.append({
					"kind": "held_item",
					"item": _mon_held_item_symbol(mon),
					"count": 1,
					"source": "src/pokemon.c:DoesMonMeetAdditionalConditions IF_HOLD_ITEM",
				})
		"IF_PID_UPPER_MODULO_10_GT":
			met = ((int(_mon_personality(mon)) >> 16) % 10) > _value_field(arg1)
		"IF_PID_UPPER_MODULO_10_EQ":
			met = ((int(_mon_personality(mon)) >> 16) % 10) == _value_field(arg1)
		"IF_PID_UPPER_MODULO_10_LT":
			met = ((int(_mon_personality(mon)) >> 16) % 10) < _value_field(arg1)
		"IF_MIN_BEAUTY":
			met = _mon_contest_stat(mon, "beauty") >= _value_field(arg1)
		"IF_MIN_COOLNESS":
			met = _mon_contest_stat(mon, "cool") >= _value_field(arg1)
		"IF_MIN_SMARTNESS":
			met = _mon_contest_stat(mon, "smart") >= _value_field(arg1)
		"IF_MIN_TOUGHNESS":
			met = _mon_contest_stat(mon, "tough") >= _value_field(arg1)
		"IF_MIN_CUTENESS":
			met = _mon_contest_stat(mon, "cute") >= _value_field(arg1)
		"IF_SPECIES_IN_PARTY":
			met = _party_has_species(_context_array(options, "party"), arg1)
			if not options.has("party") and not _dict_field(options, "context").has("party"):
				unsupported.append(_missing_context("party", condition_symbol))
		"IF_IN_MAP":
			var current_map = _context_value(options, "current_map", _context_value(options, "map", null))
			if current_map == null:
				unsupported.append(_missing_context("current_map", condition_symbol))
			met = current_map != null and _symbol_or_value_matches(_constant_symbol(current_map), _numeric_value(current_map, -1), arg1)
		"IF_IN_MAPSEC":
			var current_mapsec = _context_value(options, "current_map_section", _context_value(options, "map_section", null))
			if current_mapsec == null:
				unsupported.append(_missing_context("map_section", condition_symbol))
			met = current_mapsec != null and _symbol_or_value_matches(_constant_symbol(current_mapsec), _numeric_value(current_mapsec, -1), arg1)
		"IF_KNOWS_MOVE":
			met = _mon_knows_move(mon, arg1)
		"IF_TRADE_PARTNER_SPECIES":
			var partner := _dict_field(options, "trade_partner")
			if partner.is_empty():
				unsupported.append(_missing_context("trade_partner", condition_symbol))
			var partner_species := _mon_species_symbol(partner)
			var partner_item := _mon_held_item_symbol(partner)
			met = not partner.is_empty() and _constant_matches(arg1, partner_species) and _item_hold_effect_symbol(partner_item) != "HOLD_EFFECT_PREVENT_EVOLVE"
		"IF_TYPE_IN_PARTY":
			met = _party_has_type(_context_array(options, "party"), _constant_symbol(arg1))
			if not options.has("party") and not _dict_field(options, "context").has("party"):
				unsupported.append(_missing_context("party", condition_symbol))
		"IF_WEATHER":
			var weather = _context_value(options, "weather", null)
			if weather == null:
				unsupported.append(_missing_context("weather", condition_symbol))
			met = weather != null and _weather_matches(_constant_symbol(weather), _numeric_value(weather, -1), arg1)
		"IF_KNOWS_MOVE_TYPE":
			met = _mon_knows_move_type(mon, _constant_symbol(arg1))
		"IF_NATURE":
			met = _nature_matches(mon, arg1)
		"IF_AMPED_NATURE":
			met = AMPED_NATURES.has(_mon_nature_symbol(mon))
		"IF_LOW_KEY_NATURE":
			met = LOW_KEY_NATURES.has(_mon_nature_symbol(mon))
		"IF_RECOIL_DAMAGE_GE":
			met = _mon_evolution_tracker(mon) >= _value_field(arg1)
		"IF_CURRENT_DAMAGE_GE":
			var current_hp := _mon_hp(mon)
			met = current_hp != 0 and (_mon_max_hp(mon) - current_hp) >= _value_field(arg1)
		"IF_CRITICAL_HITS_GE":
			var party_id := int(options.get("party_id", PARTY_SIZE))
			met = party_id != PARTY_SIZE and _critical_hits_for_party_id(options, party_id) >= _value_field(arg1)
		"IF_USED_MOVE_X_TIMES":
			met = _mon_evolution_tracker(mon) >= _value_field(arg2)
		"IF_DEFEAT_X_WITH_ITEMS":
			met = _mon_evolution_tracker(mon) >= _value_field(arg3)
		"IF_PID_MODULO_100_GT":
			met = (int(_mon_personality(mon)) % 100) > _value_field(arg1)
		"IF_PID_MODULO_100_EQ":
			met = (int(_mon_personality(mon)) % 100) == _value_field(arg1)
		"IF_PID_MODULO_100_LT":
			met = (int(_mon_personality(mon)) % 100) < _value_field(arg1)
		"IF_MIN_OVERWORLD_STEPS":
			var follower_steps := int(_context_value(options, "follower_steps", 0))
			met = _is_first_live_mon(mon, options) and follower_steps >= _value_field(arg1)
		"IF_BAG_ITEM_COUNT":
			var bag_items = _context_value(options, "bag_items", null)
			if bag_items == null:
				unsupported.append(_missing_context("bag_items", condition_symbol))
			met = bag_items != null and _bag_has_item_count(bag_items, arg1, _value_field(arg2))
			if met:
				aggregate_result["can_stop_evolution"] = false
				pending_removals.append({
					"kind": "bag_item",
					"item": _constant_symbol(arg1),
					"count": _value_field(arg2),
					"source": "src/pokemon.c:DoesMonMeetAdditionalConditions IF_BAG_ITEM_COUNT",
				})
		"IF_REGION":
			var region = _context_value(options, "region", _context_value(options, "current_region", null))
			if region == null:
				unsupported.append(_missing_context("region", condition_symbol))
			met = region != null and _symbol_or_value_matches(_constant_symbol(region), _numeric_value(region, -1), arg1)
		"IF_NOT_REGION":
			var not_region = _context_value(options, "region", _context_value(options, "current_region", null))
			if not_region == null:
				unsupported.append(_missing_context("region", condition_symbol))
			met = not_region != null and not _symbol_or_value_matches(_constant_symbol(not_region), _numeric_value(not_region, -1), arg1)
		_:
			unsupported.append({
				"code": "unsupported_evolution_condition",
				"condition": condition_symbol,
				"source": "src/pokemon.c:DoesMonMeetAdditionalConditions",
			})
			detail = "Condition is not implemented in this runtime slice."

	if evo_state == "DO_EVO" and met:
		for removal in pending_removals:
			aggregate_result["pending_item_removals"].append(removal)

	for item in unsupported:
		aggregate_result["unsupported"].append(item)

	return {
		"condition": condition_symbol,
		"met": met,
		"arg1": arg1,
		"arg2": arg2,
		"arg3": arg3,
		"pending_item_removals": pending_removals if evo_state == "DO_EVO" and met else [],
		"unsupported": unsupported,
		"detail": detail,
		"source": "src/pokemon.c:DoesMonMeetAdditionalConditions",
	}


func _primary_method_result(evolution: Dictionary, mode: String, mon: Dictionary, options: Dictionary) -> Dictionary:
	var method := _method_symbol(evolution)
	var param := _dict_field(evolution, "param")
	var level := _mon_level(mon)
	var met := false
	var reason := ""
	match mode:
		"EVO_MODE_NORMAL", "EVO_MODE_BATTLE_ONLY":
			if method == "EVO_LEVEL":
				met = _value_field(param) <= level
			elif method == "EVO_LEVEL_BATTLE_ONLY":
				met = mode == "EVO_MODE_BATTLE_ONLY" and _value_field(param) <= level
			else:
				reason = "method_not_used_in_level_mode"
		"EVO_MODE_TRADE":
			met = method == "EVO_TRADE"
		"EVO_MODE_ITEM_USE", "EVO_MODE_ITEM_CHECK":
			met = method == "EVO_ITEM" and _item_matches(_evolution_item_symbol(options), _evolution_item_value(options, -1), param)
		"EVO_MODE_BATTLE_SPECIAL":
			met = method == "EVO_BATTLE_END"
		"EVO_MODE_OVERWORLD_SPECIAL":
			met = method == "EVO_SPIN" and _value_field(param) == int(_context_value(options, "special_var_0x8000", _context_value(options, "spin_param", -1)))
		"EVO_MODE_SCRIPT_TRIGGER":
			met = method == "EVO_SCRIPT_TRIGGER"
		_:
			reason = "unknown_evolution_mode"
	return {
		"method": method,
		"mode": mode,
		"met": met,
		"level": level,
		"param": param,
		"target_species": _target_species_symbol(evolution),
		"reason": reason,
		"source": "src/pokemon.c:GetEvolutionTargetSpecies",
	}


func _base_result(source_species: String, mode: String) -> Dictionary:
	return {
		"status": "no_evolution",
		"source_species": source_species,
		"target_species": SPECIES_NONE,
		"target_species_id": 0,
		"matched_index": -1,
		"mode": mode,
		"can_stop_evolution": true,
		"conditions": [],
		"pending_item_removals": [],
		"unsupported": [],
		"inspected": [],
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


func _get_item_record(item_id_or_symbol) -> Dictionary:
	var registry := _get_registry()
	if registry == null or not registry.has_method("get_item_record"):
		return {}
	var record = registry.get_item_record(item_id_or_symbol)
	return record if typeof(record) == TYPE_DICTIONARY else {}


func _get_move_record(move_id_or_symbol) -> Dictionary:
	var registry := _get_registry()
	if registry == null or not registry.has_method("get_move_record"):
		return {}
	var record = registry.get_move_record(move_id_or_symbol)
	return record if typeof(record) == TYPE_DICTIONARY else {}


func _get_evolutions_for_species(species_id_or_symbol) -> Array:
	var registry := _get_registry()
	if registry == null or not registry.has_method("get_evolutions_for_species"):
		return []
	var evolutions = registry.get_evolutions_for_species(species_id_or_symbol)
	return evolutions if typeof(evolutions) == TYPE_ARRAY else []


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


func _method_symbol(evolution: Dictionary) -> String:
	return _constant_symbol(evolution.get("method", {}))


func _target_species_symbol(evolution: Dictionary) -> String:
	return _constant_symbol(evolution.get("target_species", {}))


func _target_species_id(evolution: Dictionary) -> int:
	var target := _dict_field(evolution, "target_species")
	return _value_field(target)


func _mon_species_key(mon: Dictionary):
	if mon.has("species") and mon.get("species") != null:
		var species = mon.get("species")
		if typeof(species) == TYPE_DICTIONARY:
			var species_symbol := _constant_symbol(species)
			if not species_symbol.is_empty():
				return species_symbol
			if species.has("value") and species.get("value") != null:
				return int(species.get("value"))
		return species
	if mon.has("species_symbol") and mon.get("species_symbol") != null:
		return mon.get("species_symbol")
	if mon.has("species_id") and mon.get("species_id") != null:
		return int(mon.get("species_id"))
	return ""


func _mon_species_symbol(mon: Dictionary) -> String:
	var key = _mon_species_key(mon)
	if typeof(key) == TYPE_INT or typeof(key) == TYPE_FLOAT:
		var species := _get_species_record(int(key))
		return _record_symbol(species)
	return _normalize_species_symbol(String(key))


func _mon_level(mon: Dictionary) -> int:
	return max(1, int(mon.get("level", 1)))


func _mon_friendship(mon: Dictionary) -> int:
	return int(mon.get("friendship", 0))


func _mon_attack(mon: Dictionary) -> int:
	if mon.has("attack"):
		return int(mon.get("attack", 0))
	if mon.has("atk"):
		return int(mon.get("atk", 0))
	var stats := _dict_field(mon, "stats")
	return int(stats.get("attack", stats.get("atk", 0)))


func _mon_defense(mon: Dictionary) -> int:
	if mon.has("defense"):
		return int(mon.get("defense", 0))
	if mon.has("def"):
		return int(mon.get("def", 0))
	var stats := _dict_field(mon, "stats")
	return int(stats.get("defense", stats.get("def", 0)))


func _mon_hp(mon: Dictionary) -> int:
	return int(mon.get("hp", 0))


func _mon_max_hp(mon: Dictionary) -> int:
	if mon.has("max_hp"):
		return int(mon.get("max_hp", 0))
	var stats := _dict_field(mon, "stats")
	return int(stats.get("hp", 0))


func _mon_personality(mon: Dictionary) -> int:
	if mon.has("personality"):
		return int(mon.get("personality", 0))
	return int(mon.get("pid", 0))


func _mon_evolution_tracker(mon: Dictionary) -> int:
	return int(mon.get("evolution_tracker", mon.get("evo_tracker", 0)))


func _mon_gender(mon: Dictionary) -> String:
	if mon.has("gender_symbol"):
		return _constant_symbol(mon.get("gender_symbol"))
	if mon.has("gender"):
		return _constant_symbol(mon.get("gender"))
	return ""


func _mon_gender_value(mon: Dictionary) -> int:
	return _numeric_value(mon.get("gender", null), -1)


func _mon_nature_symbol(mon: Dictionary) -> String:
	var nature = mon.get("nature", "NATURE_HARDY")
	if typeof(nature) == TYPE_INT or typeof(nature) == TYPE_FLOAT:
		var registry := _get_registry()
		if registry != null and registry.has_method("get_nature_record"):
			var record = registry.get_nature_record(int(nature))
			if typeof(record) == TYPE_DICTIONARY:
				return _record_symbol(record)
	return _normalize_nature_symbol(_constant_symbol(nature))


func _mon_nature_value(mon: Dictionary) -> int:
	var nature = mon.get("nature", null)
	return _numeric_value(nature, -1)


func _mon_contest_stat(mon: Dictionary, stat_name: String) -> int:
	if mon.has(stat_name):
		return int(mon.get(stat_name, 0))
	var contest := _dict_field(mon, "contest")
	if contest.has(stat_name):
		return int(contest.get(stat_name, 0))
	return 0


func _mon_held_item_symbol(mon: Dictionary) -> String:
	var held = mon.get("held_item", ITEM_NONE)
	if typeof(held) == TYPE_INT or typeof(held) == TYPE_FLOAT:
		var item := _get_item_record(int(held))
		return _record_symbol(item) if not item.is_empty() else ITEM_NONE
	var symbol := _constant_symbol(held)
	if symbol.is_empty():
		return ITEM_NONE
	return _normalize_item_symbol(symbol)


func _mon_held_item_id(mon: Dictionary) -> int:
	var held = mon.get("held_item", null)
	if typeof(held) == TYPE_INT or typeof(held) == TYPE_FLOAT:
		return int(held)
	if typeof(held) == TYPE_DICTIONARY and held.has("value") and held.get("value") != null:
		return int(held.get("value"))
	var record := _get_item_record(_mon_held_item_symbol(mon))
	if record.has("id"):
		return int(record.get("id"))
	return -1


func _mon_knows_move(mon: Dictionary, move_arg: Dictionary) -> bool:
	var moves = mon.get("moves", mon.get("known_moves", []))
	if typeof(moves) != TYPE_ARRAY:
		return false
	for move in moves:
		var symbol := _move_symbol(move)
		var value := _numeric_value(move, -1)
		if _symbol_or_value_matches(symbol, value, move_arg):
			return true
	return false


func _mon_knows_move_type(mon: Dictionary, type_symbol: String) -> bool:
	var moves = mon.get("moves", mon.get("known_moves", []))
	if typeof(moves) != TYPE_ARRAY:
		return false
	var normalized_type := _normalize_type_symbol(type_symbol)
	for move in moves:
		var move_type := _move_type_symbol(move)
		if move_type == normalized_type:
			return true
	return false


func _move_symbol(move) -> String:
	if typeof(move) == TYPE_DICTIONARY:
		var symbol := _constant_symbol(move.get("symbol", ""))
		if not symbol.is_empty():
			return symbol
		if move.has("move"):
			return _constant_symbol(move.get("move"))
		if move.has("id"):
			var record := _get_move_record(int(move.get("id")))
			return _record_symbol(record)
	if typeof(move) == TYPE_INT or typeof(move) == TYPE_FLOAT:
		var record_by_id := _get_move_record(int(move))
		return _record_symbol(record_by_id)
	return _normalize_move_symbol(String(move))


func _move_type_symbol(move) -> String:
	if typeof(move) == TYPE_DICTIONARY:
		var direct_type := _constant_symbol(move.get("type", ""))
		if not direct_type.is_empty():
			return _normalize_type_symbol(direct_type)
	var symbol := _move_symbol(move)
	var record := _get_move_record(symbol)
	if record.is_empty():
		return ""
	return _normalize_type_symbol(_constant_symbol(record.get("type", "")))


func _party_has_species(party: Array, species_arg: Dictionary) -> bool:
	for party_mon in party:
		var species_symbol := ""
		var species_value := -1
		if typeof(party_mon) == TYPE_DICTIONARY:
			species_symbol = _mon_species_symbol(party_mon)
			species_value = _numeric_value(_mon_species_key(party_mon), -1)
		else:
			species_symbol = _normalize_species_symbol(String(party_mon))
			species_value = _numeric_value(party_mon, -1)
		if _symbol_or_value_matches(species_symbol, species_value, species_arg):
			return true
	return false


func _party_has_type(party: Array, type_symbol: String) -> bool:
	var normalized_type := _normalize_type_symbol(type_symbol)
	for party_mon in party:
		for party_type in _types_for_mon(party_mon):
			if String(party_type) == normalized_type:
				return true
	return false


func _types_for_mon(mon) -> Array:
	var types: Array = []
	if typeof(mon) == TYPE_DICTIONARY:
		var raw_types = mon.get("types", [])
		if typeof(raw_types) == TYPE_ARRAY:
			for type_value in raw_types:
				var type_symbol := _normalize_type_symbol(_constant_symbol(type_value))
				if not type_symbol.is_empty() and not types.has(type_symbol):
					types.append(type_symbol)
			if not types.is_empty():
				return types
		var species_record := _get_species_record(_mon_species_key(mon))
		return _types_from_species_record(species_record)
	var fallback_record := _get_species_record(mon)
	return _types_from_species_record(fallback_record)


func _types_from_species_record(species_record: Dictionary) -> Array:
	var types: Array = []
	var raw_types = species_record.get("types", [])
	if typeof(raw_types) != TYPE_ARRAY:
		return types
	for type_value in raw_types:
		var type_symbol := _normalize_type_symbol(_constant_symbol(type_value))
		if not type_symbol.is_empty() and not types.has(type_symbol):
			types.append(type_symbol)
	return types


func _critical_hits_for_party_id(options: Dictionary, party_id: int) -> int:
	var critical_hits = _context_value(options, "critical_hits", {})
	if typeof(critical_hits) == TYPE_ARRAY:
		if party_id >= 0 and party_id < critical_hits.size():
			return int(critical_hits[party_id])
		return 0
	if typeof(critical_hits) == TYPE_DICTIONARY:
		if critical_hits.has(party_id):
			return int(critical_hits.get(party_id, 0))
		if critical_hits.has(str(party_id)):
			return int(critical_hits.get(str(party_id), 0))
	return 0


func _is_first_live_mon(mon: Dictionary, options: Dictionary) -> bool:
	if options.has("is_first_live_mon"):
		return bool(options.get("is_first_live_mon"))
	if mon.has("is_first_live_mon"):
		return bool(mon.get("is_first_live_mon"))
	var party_index := int(options.get("party_index", mon.get("party_index", 0)))
	var first_live_index := int(options.get("first_live_party_index", 0))
	return party_index == first_live_index


func _bag_has_item_count(bag_items, item_arg: Dictionary, count: int) -> bool:
	if typeof(bag_items) != TYPE_DICTIONARY:
		return false
	var symbol := _constant_symbol(item_arg)
	var value := _value_field(item_arg)
	var normalized_symbol := _normalize_item_symbol(symbol)
	if bag_items.has(normalized_symbol):
		return int(bag_items.get(normalized_symbol, 0)) >= count
	if bag_items.has(symbol):
		return int(bag_items.get(symbol, 0)) >= count
	if bag_items.has(value):
		return int(bag_items.get(value, 0)) >= count
	if bag_items.has(str(value)):
		return int(bag_items.get(str(value), 0)) >= count
	return false


func _item_hold_effect_symbol(item_symbol: String) -> String:
	var normalized := _normalize_item_symbol(item_symbol)
	if normalized == ITEM_NONE or normalized.is_empty():
		return "HOLD_EFFECT_NONE"
	var item := _get_item_record(normalized)
	if item.is_empty():
		return "HOLD_EFFECT_NONE"
	return _constant_symbol(item.get("hold_effect", "HOLD_EFFECT_NONE"))


func _item_matches(item_symbol: String, item_value: int, arg: Dictionary) -> bool:
	return _symbol_or_value_matches(_normalize_item_symbol(item_symbol), item_value, arg)


func _nature_matches(mon: Dictionary, arg: Dictionary) -> bool:
	return _symbol_or_value_matches(_mon_nature_symbol(mon), _mon_nature_value(mon), arg)


func _weather_matches(weather_symbol: String, weather_value: int, arg: Dictionary) -> bool:
	var target_symbol := _constant_symbol(arg)
	var target_value := _value_field(arg)
	var normalized_weather := _normalize_weather_symbol(weather_symbol)
	if target_symbol == "WEATHER_RAIN":
		return ["WEATHER_RAIN", "WEATHER_RAIN_THUNDERSTORM", "WEATHER_DOWNPOUR"].has(normalized_weather) or weather_value == target_value
	if target_symbol == "WEATHER_FOG":
		return ["WEATHER_FOG_DIAGONAL", "WEATHER_FOG_HORIZONTAL"].has(normalized_weather) or weather_value == target_value
	return _symbol_or_value_matches(normalized_weather, weather_value, arg)


func _symbol_or_value_matches(symbol: String, value: int, arg: Dictionary) -> bool:
	var arg_symbol := _constant_symbol(arg)
	if not arg_symbol.is_empty() and not symbol.is_empty():
		if symbol == arg_symbol:
			return true
	var arg_value := _value_field(arg)
	return arg_value >= 0 and value == arg_value


func _constant_matches(arg: Dictionary, expected_symbol: String) -> bool:
	var arg_symbol := _constant_symbol(arg)
	if not arg_symbol.is_empty() and expected_symbol == arg_symbol:
		return true
	var expected_record := _get_species_record(expected_symbol)
	if not expected_record.is_empty() and arg.has("value") and arg.get("value") != null:
		return int(expected_record.get("id", -1)) == int(arg.get("value"))
	return false


func _constant_symbol(value) -> String:
	if typeof(value) == TYPE_DICTIONARY:
		return String(value.get("symbol", ""))
	if value == null:
		return ""
	return String(value)


func _value_field(record) -> int:
	if typeof(record) != TYPE_DICTIONARY:
		return _numeric_value(record, -1)
	if not record.has("value") or record.get("value") == null:
		return -1
	return int(record.get("value"))


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


func _context_value(options: Dictionary, key: String, default_value):
	if options.has(key):
		return options.get(key)
	var context := _dict_field(options, "context")
	if context.has(key):
		return context.get(key)
	return default_value


func _context_array(options: Dictionary, key: String) -> Array:
	var value = _context_value(options, key, [])
	return value if typeof(value) == TYPE_ARRAY else []


func _evolution_item_symbol(options: Dictionary) -> String:
	var value = options.get("evolution_item", options.get("item", ITEM_NONE))
	if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
		var record := _get_item_record(int(value))
		return _record_symbol(record)
	return _normalize_item_symbol(_constant_symbol(value))


func _evolution_item_value(options: Dictionary, default_value: int) -> int:
	var value = options.get("evolution_item", options.get("item", default_value))
	if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
		return int(value)
	var record := _get_item_record(_evolution_item_symbol(options))
	if record.has("id"):
		return int(record.get("id"))
	return default_value


func _normalize_mode(mode: String) -> String:
	if mode.begins_with("EVO_MODE_"):
		return mode
	var upper := mode.to_upper()
	if upper in ["NORMAL", "TRADE", "ITEM_USE", "ITEM_CHECK", "BATTLE_SPECIAL", "OVERWORLD_SPECIAL", "SCRIPT_TRIGGER", "BATTLE_ONLY"]:
		return "EVO_MODE_%s" % [upper]
	return mode


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


func _normalize_move_symbol(move_symbol: String) -> String:
	if move_symbol.is_empty():
		return ""
	if move_symbol.begins_with("MOVE_"):
		return move_symbol
	return "MOVE_%s" % [move_symbol.to_upper()]


func _normalize_nature_symbol(nature_symbol: String) -> String:
	if nature_symbol.is_empty():
		return "NATURE_HARDY"
	if nature_symbol.begins_with("NATURE_"):
		return nature_symbol
	return "NATURE_%s" % [nature_symbol.to_upper()]


func _normalize_type_symbol(type_symbol: String) -> String:
	if type_symbol.is_empty():
		return ""
	if type_symbol.begins_with("TYPE_"):
		return type_symbol
	return "TYPE_%s" % [type_symbol.to_upper()]


func _normalize_weather_symbol(weather_symbol: String) -> String:
	if weather_symbol.is_empty():
		return ""
	if weather_symbol.begins_with("WEATHER_"):
		return weather_symbol
	return "WEATHER_%s" % [weather_symbol.to_upper()]


func _party_count(party) -> int:
	if typeof(party) == TYPE_ARRAY:
		return party.size()
	return 0


func _missing_context(key: String, condition_symbol: String) -> Dictionary:
	return {
		"code": "missing_evolution_context",
		"context_key": key,
		"condition": condition_symbol,
		"source": "src/pokemon.c:DoesMonMeetAdditionalConditions",
	}


func _error_result(code: String, detail: String) -> Dictionary:
	return {
		"status": "error",
		"error": code,
		"detail": detail,
		"source_trace": SOURCE_TRACE.duplicate(),
	}
