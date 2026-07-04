extends Node

const MAX_ENCOUNTER_RATE := 2880
const SOURCE_TRACE := [
	"src/wild_encounter.c:GetCurrentMapWildMonHeaderId",
	"src/wild_encounter.c:GetTimeOfDayForEncounters",
	"src/wild_encounter.c:ChooseWildMonIndex_Land",
	"src/wild_encounter.c:ChooseWildMonIndex_Water",
	"src/wild_encounter.c:ChooseWildMonIndex_Rocks",
	"src/wild_encounter.c:ChooseWildMonIndex_Fishing",
	"src/wild_encounter.c:ChooseWildMonLevel",
	"src/wild_encounter.c:WildEncounterCheck",
	"src/wild_encounter.c:StandardWildEncounter",
	"src/wild_encounter.c:FishingWildEncounter",
	"include/wild_encounter.h",
	"include/constants/wild_encounter.h",
]

const AREA_TO_TABLE := {
	"land": "land_mons",
	"water": "water_mons",
	"rocks": "rock_smash_mons",
	"rock": "rock_smash_mons",
	"rock_smash": "rock_smash_mons",
	"fishing": "fishing_mons",
	"fish": "fishing_mons",
	"hidden": "hidden_mons",
	"WILD_AREA_LAND": "land_mons",
	"WILD_AREA_WATER": "water_mons",
	"WILD_AREA_ROCKS": "rock_smash_mons",
	"WILD_AREA_FISHING": "fishing_mons",
	"WILD_AREA_HIDDEN": "hidden_mons",
	"land_mons": "land_mons",
	"water_mons": "water_mons",
	"rock_smash_mons": "rock_smash_mons",
	"fishing_mons": "fishing_mons",
	"hidden_mons": "hidden_mons",
}

const ROD_TO_GROUP := {
	"OLD_ROD": "old_rod",
	"GOOD_ROD": "good_rod",
	"SUPER_ROD": "super_rod",
	"ITEM_OLD_ROD": "old_rod",
	"ITEM_GOOD_ROD": "good_rod",
	"ITEM_SUPER_ROD": "super_rod",
	"old_rod": "old_rod",
	"good_rod": "good_rod",
	"super_rod": "super_rod",
	"old": "old_rod",
	"good": "good_rod",
	"super": "super_rod",
	"0": "old_rod",
	"1": "good_rod",
	"2": "super_rod",
}

const LAND_ENCOUNTER_BEHAVIORS := {
	"MB_TALL_GRASS": true,
	"MB_LONG_GRASS": true,
	"MB_UNUSED_05": true,
	"MB_DEEP_SAND": true,
	"MB_CAVE": true,
	"MB_INDOOR_ENCOUNTER": true,
	"MB_ASHGRASS": true,
	"MB_FOOTPRINTS": true,
	"MB_CYCLING_ROAD_PULL_DOWN_GRASS": true,
}

const WATER_ENCOUNTER_BEHAVIORS := {
	"MB_POND_WATER": true,
	"MB_INTERIOR_DEEP_WATER": true,
	"MB_DEEP_WATER": true,
	"MB_OCEAN_WATER": true,
	"MB_SEAWEED": true,
	"MB_SEAWEED_NO_SURFACING": true,
}

const BRIDGE_OVER_WATER_BEHAVIORS := {
	"MB_BRIDGE_OVER_OCEAN": true,
	"MB_BRIDGE_OVER_POND_LOW": true,
	"MB_BRIDGE_OVER_POND_MED": true,
	"MB_BRIDGE_OVER_POND_HIGH": true,
	"MB_BRIDGE_OVER_POND_HIGH_EDGE_1": true,
	"MB_BRIDGE_OVER_POND_HIGH_EDGE_2": true,
	"MB_UNUSED_BRIDGE": true,
	"MB_BIKE_BRIDGE_OVER_BARRIER": true,
}

const METATILE_ROUTING_SOURCE_TRACE := [
	"src/metatile_behavior.c:sTileBitAttributes",
	"src/metatile_behavior.c:MetatileBehavior_IsEncounterTile",
	"src/metatile_behavior.c:MetatileBehavior_IsSurfableWaterOrUnderwater",
	"src/metatile_behavior.c:MetatileBehavior_IsLandWildEncounter",
	"src/metatile_behavior.c:MetatileBehavior_IsWaterWildEncounter",
	"src/metatile_behavior.c:MetatileBehavior_IsBridgeOverWater",
	"src/wild_encounter.c:StandardWildEncounter",
]

var _registry: Node = null
var _game_state: Node = null


func configure_registry(registry: Node) -> void:
	_registry = registry


func configure_game_state(game_state: Node) -> void:
	_game_state = game_state


func get_encounter_record_for_map(map_symbol: String, options: Dictionary = {}) -> Dictionary:
	var registry := _get_registry()
	if registry == null or not registry.has_method("get_wild_encounter_records_for_map"):
		return {}
	var records = registry.get_wild_encounter_records_for_map(_normalize_map_symbol(map_symbol))
	if typeof(records) != TYPE_ARRAY or records.is_empty():
		return {}

	var first_record = records[0]
	if typeof(first_record) != TYPE_DICTIONARY:
		return {}
	if _is_altering_cave_record(first_record):
		var index := _altering_cave_index(options, records.size())
		var record = records[index]
		return record if typeof(record) == TYPE_DICTIONARY else {}
	return first_record


func get_table_for_area(map_symbol: String, area, options: Dictionary = {}) -> Dictionary:
	var table_field := _area_table_field(area)
	if table_field.is_empty():
		return _error_result("unknown_area", "Could not resolve wild encounter area %s." % [str(area)])
	var record := get_encounter_record_for_map(map_symbol, options)
	if record.is_empty():
		return {
			"status": "no_table",
			"reason": "missing_encounter_record",
			"map": _normalize_map_symbol(map_symbol),
			"area": table_field,
			"source_trace": SOURCE_TRACE.duplicate(),
		}
	var tables := _dict_field(record, "tables")
	var table := _dict_field(tables, table_field)
	if table.is_empty():
		return {
			"status": "no_table",
			"reason": "missing_area_table",
			"map": _normalize_map_symbol(map_symbol),
			"record_id": String(record.get("id", "")),
			"record_label": String(record.get("label", "")),
			"area": table_field,
			"source_trace": SOURCE_TRACE.duplicate(),
		}
	return {
		"status": "ok",
		"map": _normalize_map_symbol(map_symbol),
		"area": table_field,
		"record": record,
		"table": table,
		"field_definition": _field_definition(table_field),
		"source_time": record.get("source_time", {}),
		"runtime_time": record.get("runtime_time", {}),
		"source_trace": SOURCE_TRACE.duplicate(),
	}


func has_fishing_encounters(map_symbol: String, options: Dictionary = {}) -> bool:
	var result := get_table_for_area(map_symbol, "fishing", options)
	return String(result.get("status", "")) == "ok"


func area_for_metatile_behavior(behavior_name: String, options: Dictionary = {}) -> Dictionary:
	var normalized := _normalize_behavior_name(behavior_name)
	if LAND_ENCOUNTER_BEHAVIORS.has(normalized):
		return {
			"status": "ok",
			"area": "land",
			"table_field": "land_mons",
			"behavior_name": normalized,
			"source": "src/metatile_behavior.c:MetatileBehavior_IsLandWildEncounter",
			"source_trace": METATILE_ROUTING_SOURCE_TRACE.duplicate(),
		}
	if WATER_ENCOUNTER_BEHAVIORS.has(normalized):
		return {
			"status": "ok",
			"area": "water",
			"table_field": "water_mons",
			"behavior_name": normalized,
			"source": "src/metatile_behavior.c:MetatileBehavior_IsWaterWildEncounter",
			"source_trace": METATILE_ROUTING_SOURCE_TRACE.duplicate(),
		}
	if bool(options.get("surfing", false)) and BRIDGE_OVER_WATER_BEHAVIORS.has(normalized):
		return {
			"status": "ok",
			"area": "water",
			"table_field": "water_mons",
			"behavior_name": normalized,
			"bridge_over_water": true,
			"source": "src/wild_encounter.c:StandardWildEncounter surfing bridge branch",
			"source_trace": METATILE_ROUTING_SOURCE_TRACE.duplicate(),
		}
	return {
		"status": "no_encounter",
		"reason": "non_encounter_metatile",
		"behavior_name": normalized,
		"source": "src/wild_encounter.c:StandardWildEncounter",
		"source_trace": METATILE_ROUTING_SOURCE_TRACE.duplicate(),
	}


func try_standard_encounter_for_behavior(
	map_symbol: String,
	current_behavior_name: String,
	previous_behavior_name = "",
	options: Dictionary = {}
) -> Dictionary:
	var routing := area_for_metatile_behavior(current_behavior_name, options)
	if String(routing.get("status", "")) != "ok":
		routing["map"] = _normalize_map_symbol(map_symbol)
		return routing

	var encounter_options := options.duplicate(true)
	var previous := _normalize_behavior_name(previous_behavior_name)
	encounter_options["metatile_changed"] = (
		not previous.is_empty()
		and previous != String(routing.get("behavior_name", ""))
	)
	var result := try_standard_encounter(map_symbol, String(routing.get("area", "")), encounter_options)
	result["metatile_routing"] = routing
	result["current_metatile_behavior"] = String(routing.get("behavior_name", ""))
	result["previous_metatile_behavior"] = previous
	return result


func check_encounter_rate(encounter_rate: int, options: Dictionary = {}) -> Dictionary:
	var adjusted_rate := clampi(encounter_rate * 16, 0, MAX_ENCOUNTER_RATE)
	var roll := _option_roll(options, "encounter_roll", MAX_ENCOUNTER_RATE)
	var hit := roll < adjusted_rate
	return {
		"status": "ok",
		"encounter": hit,
		"encounter_rate": encounter_rate,
		"adjusted_rate": adjusted_rate,
		"max_rate": MAX_ENCOUNTER_RATE,
		"roll": roll,
		"source": "src/wild_encounter.c:WildEncounterCheck -> EncounterOddsCheck",
		"unsupported": [{
			"code": "encounter_rate_modifiers_not_applied",
			"source": "src/wild_encounter.c:WildEncounterCheck",
			"detail": "Bike, flute, Cleanse Tag, lure, lead ability, weather, Repel, and map-specific encounter-rate modifiers are future traced work.",
		}],
		"source_trace": SOURCE_TRACE.duplicate(),
	}


func try_standard_encounter(map_symbol: String, area = "land", options: Dictionary = {}) -> Dictionary:
	var table_result := get_table_for_area(map_symbol, area, options)
	if String(table_result.get("status", "")) != "ok":
		return table_result

	if bool(options.get("metatile_changed", false)):
		var metatile_roll := _option_roll(options, "new_metatile_roll", 100)
		if metatile_roll >= 60:
			return {
				"status": "no_encounter",
				"reason": "new_metatile_skip",
				"new_metatile_roll": metatile_roll,
				"source": "src/wild_encounter.c:AllowWildCheckOnNewMetatile",
				"source_trace": SOURCE_TRACE.duplicate(),
			}

	var table := _dict_field(table_result, "table")
	var rate_check := check_encounter_rate(int(table.get("encounter_rate", 0)), options)
	if not bool(rate_check.get("encounter", false)):
		return {
			"status": "no_encounter",
			"reason": "encounter_rate_miss",
			"encounter_check": rate_check,
			"source": "src/wild_encounter.c:StandardWildEncounter",
			"source_trace": SOURCE_TRACE.duplicate(),
		}

	var wild_mon := choose_wild_mon(map_symbol, area, options)
	if String(wild_mon.get("status", "")) == "ok":
		wild_mon["encounter_check"] = rate_check
		wild_mon["standard_encounter"] = {
			"status": "started",
			"source": "src/wild_encounter.c:StandardWildEncounter",
		}
	return wild_mon


func choose_wild_mon(map_symbol: String, area = "land", options: Dictionary = {}) -> Dictionary:
	var table_result := get_table_for_area(map_symbol, area, options)
	if String(table_result.get("status", "")) != "ok":
		return table_result
	var table_field := String(table_result.get("area", ""))
	if table_field == "hidden_mons":
		return _error_result("unsupported_hidden_encounters", "DexNav hidden encounter selection is not implemented yet.")

	var table := _dict_field(table_result, "table")
	var field_definition := _dict_field(table_result, "field_definition")
	var slots := _array_field(table, "slots")
	if slots.is_empty():
		return {
			"status": "no_encounter",
			"reason": "empty_table",
			"area": table_field,
			"source_trace": SOURCE_TRACE.duplicate(),
		}

	var slot_result := _choose_slot(slots, field_definition, table_field, options)
	var slot_index := int(slot_result.get("slot_index", 0))
	if slot_index < 0 or slot_index >= slots.size():
		return _error_result("slot_index_out_of_range", "Selected wild slot %d is outside the generated table." % [slot_index])
	var slot = slots[slot_index]
	if typeof(slot) != TYPE_DICTIONARY:
		return _error_result("invalid_slot_record", "Selected wild slot %d is not a dictionary." % [slot_index])

	var level_result := _choose_level(slot, slots, table_field, options)
	var record := _dict_field(table_result, "record")
	var species := _dict_field(slot, "species")
	return {
		"status": "ok",
		"map": _normalize_map_symbol(map_symbol),
		"record_id": String(record.get("id", "")),
		"record_label": String(record.get("label", "")),
		"area": table_field,
		"table": {
			"field": table_field,
			"encounter_rate": int(table.get("encounter_rate", 0)),
			"source_info_label": String(table.get("source_info_label", "")),
			"source_mons_label": String(table.get("source_mons_label", "")),
		},
		"slot_index": slot_index,
		"slot": slot.duplicate(true),
		"slot_choice": slot_result,
		"species": String(species.get("symbol", "")),
		"species_id": int(species.get("value", 0)),
		"min_level": int(slot.get("min_level", 0)),
		"max_level": int(slot.get("max_level", 0)),
		"level": int(level_result.get("level", 1)),
		"level_choice": level_result,
		"source_time": table_result.get("source_time", {}),
		"runtime_time": table_result.get("runtime_time", {}),
		"unsupported": _first_pass_unsupported(table_field),
		"source_trace": SOURCE_TRACE.duplicate(),
	}


func _choose_slot(slots: Array, field_definition: Dictionary, table_field: String, options: Dictionary) -> Dictionary:
	if table_field == "fishing_mons":
		return _choose_fishing_slot(field_definition, options)

	var total_rate := int(field_definition.get("total_rate", 0))
	if total_rate <= 0:
		total_rate = max(1, slots.size())
	var roll := _option_roll(options, "slot_roll", total_rate)
	var slot_rates := _array_field(field_definition, "slot_rates")
	var selected := _slot_from_thresholds(slot_rates, roll, slots.size())
	if bool(options.get("lure_swap", false)):
		selected = slots.size() - 1 - selected
	return {
		"slot_index": selected,
		"roll": roll,
		"total_rate": total_rate,
		"lure_swap": bool(options.get("lure_swap", false)),
		"source": String(field_definition.get("selector", "")),
	}


func _choose_fishing_slot(field_definition: Dictionary, options: Dictionary) -> Dictionary:
	var group_name := _rod_group(options.get("rod", "OLD_ROD"))
	var rod_groups := _dict_field(field_definition, "rod_groups")
	var group := _dict_field(rod_groups, group_name)
	if group.is_empty():
		return {
			"slot_index": 0,
			"roll": 0,
			"total_rate": 0,
			"rod_group": group_name,
			"source": "src/wild_encounter.c:ChooseWildMonIndex_Fishing",
			"warning": "missing_rod_group",
		}
	var total_rate := int(group.get("total_rate", 100))
	var roll := _option_roll(options, "slot_roll", total_rate)
	var thresholds = group.get("cumulative_thresholds", [])
	var indices = group.get("indices", [])
	var selected_offset := _offset_from_thresholds(thresholds, roll)
	var selected := 0
	if typeof(indices) == TYPE_ARRAY and selected_offset >= 0 and selected_offset < indices.size():
		selected = int(indices[selected_offset])
	if bool(options.get("lure_swap", false)) and typeof(indices) == TYPE_ARRAY and not indices.is_empty():
		var first := int(indices[0])
		var last := int(indices[indices.size() - 1])
		selected = first + last - selected
	return {
		"slot_index": selected,
		"roll": roll,
		"total_rate": total_rate,
		"rod_group": group_name,
		"rod": _rod_symbol(group_name),
		"lure_swap": bool(options.get("lure_swap", false)),
		"source": "src/wild_encounter.c:ChooseWildMonIndex_Fishing",
	}


func _choose_level(slot: Dictionary, slots: Array, table_field: String, options: Dictionary) -> Dictionary:
	var min_level := int(slot.get("min_level", 1))
	var max_level := int(slot.get("max_level", min_level))
	if min_level > max_level:
		var swap := min_level
		min_level = max_level
		max_level = swap

	if bool(options.get("lure_active", false)):
		var lure_level := max_level + 1
		if table_field != "fishing_mons":
			var max_same_species := _max_level_for_species(slots, _species_symbol(slot))
			if max_same_species > 0:
				lure_level = max_same_species + 1
		return {
			"level": lure_level,
			"min_level": min_level,
			"max_level": max_level,
			"lure_active": true,
			"source": "src/wild_encounter.c:ChooseWildMonLevel LURE_STEP_COUNT path",
		}

	var range: int = maxi(1, max_level - min_level + 1)
	var roll := _option_roll(options, "level_roll", range)
	return {
		"level": min_level + roll,
		"min_level": min_level,
		"max_level": max_level,
		"roll": roll,
		"range": range,
		"source": "src/wild_encounter.c:ChooseWildMonLevel",
	}


func _slot_from_thresholds(slot_rates: Array, roll: int, fallback_size: int) -> int:
	for index in range(slot_rates.size()):
		var rate = slot_rates[index]
		if typeof(rate) != TYPE_DICTIONARY:
			continue
		if roll < int(rate.get("cumulative_threshold", 0)):
			return int(rate.get("slot", index))
	return max(0, fallback_size - 1)


func _offset_from_thresholds(thresholds, roll: int) -> int:
	if typeof(thresholds) != TYPE_ARRAY:
		return 0
	for index in range(thresholds.size()):
		if roll < int(thresholds[index]):
			return index
	return max(0, thresholds.size() - 1)


func _field_definition(table_field: String) -> Dictionary:
	var registry := _get_registry()
	if registry == null or not registry.has_method("get_wild_encounters_data"):
		return {}
	var wild_data = registry.get_wild_encounters_data()
	if typeof(wild_data) != TYPE_DICTIONARY:
		return {}
	return _dict_field(_dict_field(wild_data, "field_definitions"), table_field)


func _altering_cave_index(options: Dictionary, record_count: int) -> int:
	var index := int(options.get("altering_cave_set", -1))
	if index < 0:
		var game_state := _get_game_state(options.get("game_state", null))
		if game_state != null and game_state.has_method("get_var"):
			index = int(game_state.get_var("VAR_ALTERING_CAVE_WILD_SET", 0))
	if index < 0 or index >= record_count:
		index = 0
	return index


func _is_altering_cave_record(record: Dictionary) -> bool:
	return String(record.get("source_map_symbol", "")) == "MAP_ALTERING_CAVE"


func _first_pass_unsupported(table_field: String) -> Array:
	var unsupported := [{
		"code": "wild_battle_creation_not_executed",
		"source": "src/wild_encounter.c:CreateWildMon -> src/battle_setup.c:BattleSetup_StartWildBattle",
		"detail": "This runtime slice selects source-backed species/level metadata but does not create enemy party Pokemon or start battle presentation.",
	}, {
		"code": "wild_encounter_modifiers_not_applied",
		"source": "src/wild_encounter.c:TryGenerateWildMon",
		"detail": "Repel, lead abilities, roamer, mass outbreaks, double wild battles, Safari Pokeblocks, Synchronize, gender forcing, random IV/personality, and battle transition selection remain future traced work.",
	}]
	if table_field == "fishing_mons":
		unsupported.append({
			"code": "fishing_bite_flow_not_executed",
			"source": "src/fishing.c -> src/wild_encounter.c:FishingWildEncounter",
			"detail": "Rod bite odds, fishing minigame timing, Feebas spots, chain fishing, audio, and player fishing animation remain future traced work.",
		})
	return unsupported


func _area_table_field(area) -> String:
	var key := String(area)
	var direct := String(AREA_TO_TABLE.get(key, ""))
	if not direct.is_empty():
		return direct
	var lower := key.to_lower()
	return String(AREA_TO_TABLE.get(lower, ""))


func _rod_group(rod) -> String:
	var key := String(rod)
	var direct := String(ROD_TO_GROUP.get(key, ""))
	if not direct.is_empty():
		return direct
	return String(ROD_TO_GROUP.get(key.to_lower(), "old_rod"))


func _rod_symbol(group_name: String) -> String:
	match group_name:
		"good_rod":
			return "GOOD_ROD"
		"super_rod":
			return "SUPER_ROD"
		_:
			return "OLD_ROD"


func _get_registry() -> Node:
	if _registry != null:
		return _registry
	if has_node("/root/DataRegistry"):
		_registry = get_node("/root/DataRegistry")
	return _registry


func _get_game_state(explicit_state = null) -> Node:
	if explicit_state != null and explicit_state is Node:
		return explicit_state
	if _game_state != null:
		return _game_state
	if has_node("/root/GameState"):
		_game_state = get_node("/root/GameState")
	return _game_state


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


func _species_symbol(slot: Dictionary) -> String:
	return String(_dict_field(slot, "species").get("symbol", ""))


func _max_level_for_species(slots: Array, species_symbol: String) -> int:
	var max_level := 0
	for slot in slots:
		if typeof(slot) != TYPE_DICTIONARY:
			continue
		if _species_symbol(slot) == species_symbol:
			max_level = maxi(max_level, int(slot.get("max_level", 0)))
	return max_level


func _option_roll(options: Dictionary, key: String, modulo: int) -> int:
	var max_value: int = maxi(1, modulo)
	if options.has(key):
		return clampi(int(options.get(key, 0)) % max_value, 0, max_value - 1)
	return randi() % max_value


func _normalize_map_symbol(map_symbol: String) -> String:
	if map_symbol.is_empty():
		return ""
	if map_symbol.begins_with("MAP_"):
		return map_symbol
	return "MAP_%s" % [map_symbol.to_upper()]


func _normalize_behavior_name(behavior_name: String) -> String:
	return behavior_name.strip_edges().to_upper()


func _error_result(code: String, detail: String) -> Dictionary:
	return {
		"status": "error",
		"error": code,
		"detail": detail,
		"source_trace": SOURCE_TRACE.duplicate(),
	}
