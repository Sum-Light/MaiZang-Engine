extends Node

const MAX_ENCOUNTER_RATE := 2880
const REPEL_LURE_MASK := 1 << 15
const PLAYER_AVATAR_FLAG_MACH_BIKE := 1 << 1
const PLAYER_AVATAR_FLAG_ACRO_BIKE := 1 << 2
const WEATHER_SNOW_VALUE := 4
const WEATHER_SANDSTORM_VALUE := 8
const BATTLE_PYRAMID_LAYOUT := "LAYOUT_BATTLE_FRONTIER_BATTLE_PYRAMID_FLOOR"
const SOURCE_TRACE := [
	"src/wild_encounter.c:GetCurrentMapWildMonHeaderId",
	"src/wild_encounter.c:GetTimeOfDayForEncounters",
	"src/wild_encounter.c:ChooseWildMonIndex_Land",
	"src/wild_encounter.c:ChooseWildMonIndex_Water",
	"src/wild_encounter.c:ChooseWildMonIndex_Rocks",
	"src/wild_encounter.c:ChooseWildMonIndex_Fishing",
	"src/wild_encounter.c:ChooseWildMonLevel",
	"src/wild_encounter.c:TryGetAbilityInfluencedWildMonIndex",
	"src/wild_encounter.c:TryGetRandomWildMonIndexByType",
	"src/wild_encounter.c:WildEncounterCheck",
	"src/wild_encounter.c:StandardWildEncounter",
	"src/wild_encounter.c:FishingWildEncounter",
	"include/constants/item.h:REPEL_LURE_MASK/LURE_STEP_COUNT/REPEL_STEP_COUNT",
	"include/constants/items.h:ITEM_CLEANSE_TAG",
	"include/constants/abilities.h:overworld encounter abilities",
	"include/constants/pokemon.h:enum Type",
	"include/constants/flags.h:FLAG_SYS_ENC_UP_ITEM/FLAG_SYS_ENC_DOWN_ITEM",
	"include/constants/weather.h:WEATHER_SANDSTORM/WEATHER_SNOW",
	"include/config/item.h:I_REPEL_INCLUDE_FAINTED",
	"include/config/overworld.h:OW_INFILTRATOR/OW_LIGHTNING_ROD/OW_FLASH_FIRE/OW_HARVEST/OW_STORM_DRAIN",
	"include/global.fieldmap.h:PLAYER_AVATAR_FLAG_MACH_BIKE/PLAYER_AVATAR_FLAG_ACRO_BIKE",
	"include/wild_encounter.h",
	"include/constants/wild_encounter.h",
]

const TYPE_SYMBOL_TO_VALUE := {
	"TYPE_NONE": 0,
	"TYPE_NORMAL": 1,
	"TYPE_FIGHTING": 2,
	"TYPE_FLYING": 3,
	"TYPE_POISON": 4,
	"TYPE_GROUND": 5,
	"TYPE_ROCK": 6,
	"TYPE_BUG": 7,
	"TYPE_GHOST": 8,
	"TYPE_STEEL": 9,
	"TYPE_MYSTERY": 10,
	"TYPE_FIRE": 11,
	"TYPE_WATER": 12,
	"TYPE_GRASS": 13,
	"TYPE_ELECTRIC": 14,
	"TYPE_PSYCHIC": 15,
	"TYPE_ICE": 16,
	"TYPE_DRAGON": 17,
	"TYPE_DARK": 18,
	"TYPE_FAIRY": 19,
	"TYPE_STELLAR": 20,
}

const ABILITY_SLOT_RULES := [
	{
		"ability": "ABILITY_MAGNET_PULL",
		"type": "TYPE_STEEL",
		"source": "src/wild_encounter.c:TryGenerateWildMon MAGNET_PULL -> TYPE_STEEL",
	},
	{
		"ability": "ABILITY_STATIC",
		"type": "TYPE_ELECTRIC",
		"source": "src/wild_encounter.c:TryGenerateWildMon STATIC -> TYPE_ELECTRIC",
	},
	{
		"ability": "ABILITY_LIGHTNING_ROD",
		"type": "TYPE_ELECTRIC",
		"option": "ow_lightning_rod_gen8",
		"source": "src/wild_encounter.c:TryGenerateWildMon OW_LIGHTNING_ROD >= GEN_8 -> TYPE_ELECTRIC",
	},
	{
		"ability": "ABILITY_FLASH_FIRE",
		"type": "TYPE_FIRE",
		"option": "ow_flash_fire_gen8",
		"source": "src/wild_encounter.c:TryGenerateWildMon OW_FLASH_FIRE >= GEN_8 -> TYPE_FIRE",
	},
	{
		"ability": "ABILITY_HARVEST",
		"type": "TYPE_GRASS",
		"option": "ow_harvest_gen8",
		"source": "src/wild_encounter.c:TryGenerateWildMon OW_HARVEST >= GEN_8 -> TYPE_GRASS",
	},
	{
		"ability": "ABILITY_STORM_DRAIN",
		"type": "TYPE_WATER",
		"option": "ow_storm_drain_gen8",
		"source": "src/wild_encounter.c:TryGenerateWildMon OW_STORM_DRAIN >= GEN_8 -> TYPE_WATER",
	},
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
	var adjusted_rate: int = maxi(0, encounter_rate * 16)
	var modifiers := []

	var bike := _bike_state(options)
	if bool(bike.get("active", false)):
		var before_bike := adjusted_rate
		adjusted_rate = _mul_div_floor(adjusted_rate, 80, 100)
		modifiers.append(_rate_modifier(
			"bike_encounter_rate",
			"multiply_by_80_percent",
			before_bike,
			adjusted_rate,
			"src/wild_encounter.c:WildEncounterCheck TestPlayerAvatarFlags bike path",
			{"state": bike}
		))

	var flute := _flute_state(options)
	if bool(flute.get("white_flute_active", false)):
		var before_white_flute := adjusted_rate
		adjusted_rate += _div_floor(adjusted_rate, 2)
		modifiers.append(_rate_modifier(
			"white_flute_encounter_rate",
			"add_half",
			before_white_flute,
			adjusted_rate,
			"src/wild_encounter.c:ApplyFluteEncounterRateMod FLAG_SYS_ENC_UP_ITEM",
			{"state": flute}
		))
	elif bool(flute.get("black_flute_active", false)):
		var before_black_flute := adjusted_rate
		adjusted_rate = _div_floor(adjusted_rate, 2)
		modifiers.append(_rate_modifier(
			"black_flute_encounter_rate",
			"divide_by_2",
			before_black_flute,
			adjusted_rate,
			"src/wild_encounter.c:ApplyFluteEncounterRateMod FLAG_SYS_ENC_DOWN_ITEM",
			{"state": flute}
		))

	var cleanse_tag := _cleanse_tag_state(options)
	if bool(cleanse_tag.get("active", false)):
		var before_cleanse_tag := adjusted_rate
		adjusted_rate = _mul_div_floor(adjusted_rate, 2, 3)
		modifiers.append(_rate_modifier(
			"cleanse_tag_encounter_rate",
			"multiply_by_2_over_3",
			before_cleanse_tag,
			adjusted_rate,
			"src/wild_encounter.c:ApplyCleanseTagEncounterRateMod",
			{"state": cleanse_tag}
		))

	var repel_lure := _repel_lure_state(options)
	if bool(repel_lure.get("lure_active", false)):
		var before_lure := adjusted_rate
		adjusted_rate *= 2
		modifiers.append(_rate_modifier(
			"lure_encounter_rate",
			"multiply_by_2",
			before_lure,
			adjusted_rate,
			"src/wild_encounter.c:WildEncounterCheck LURE_STEP_COUNT path",
			{"state": repel_lure}
		))

	var lead_ability := _lead_ability_state(options)
	if bool(lead_ability.get("applies", false)):
		var ability := String(lead_ability.get("ability", ""))
		var before_ability := adjusted_rate
		var source := "src/wild_encounter.c:WildEncounterCheck lead ability path"
		var operation := ""
		match ability:
			"ABILITY_STENCH":
				if _is_battle_pyramid_layout(options):
					adjusted_rate = _mul_div_floor(adjusted_rate, 3, 4)
					operation = "multiply_by_3_over_4"
					source = "src/wild_encounter.c:WildEncounterCheck STENCH Battle Pyramid path"
				else:
					adjusted_rate = _div_floor(adjusted_rate, 2)
					operation = "divide_by_2"
					source = "src/wild_encounter.c:WildEncounterCheck STENCH path"
			"ABILITY_ILLUMINATE":
				adjusted_rate *= 2
				operation = "multiply_by_2"
				source = "src/wild_encounter.c:WildEncounterCheck ILLUMINATE path"
			"ABILITY_WHITE_SMOKE":
				adjusted_rate = _div_floor(adjusted_rate, 2)
				operation = "divide_by_2"
				source = "src/wild_encounter.c:WildEncounterCheck WHITE_SMOKE path"
			"ABILITY_ARENA_TRAP":
				adjusted_rate *= 2
				operation = "multiply_by_2"
				source = "src/wild_encounter.c:WildEncounterCheck ARENA_TRAP path"
			"ABILITY_SAND_VEIL":
				if _weather_matches(options, "WEATHER_SANDSTORM"):
					adjusted_rate = _div_floor(adjusted_rate, 2)
					operation = "divide_by_2"
					source = "src/wild_encounter.c:WildEncounterCheck SAND_VEIL sandstorm path"
			"ABILITY_SNOW_CLOAK":
				if _weather_matches(options, "WEATHER_SNOW"):
					adjusted_rate = _div_floor(adjusted_rate, 2)
					operation = "divide_by_2"
					source = "src/wild_encounter.c:WildEncounterCheck SNOW_CLOAK snow path"
			"ABILITY_QUICK_FEET":
				adjusted_rate = _div_floor(adjusted_rate, 2)
				operation = "divide_by_2"
				source = "src/wild_encounter.c:WildEncounterCheck QUICK_FEET path"
			"ABILITY_INFILTRATOR":
				if bool(lead_ability.get("ow_infiltrator_gen8", true)):
					adjusted_rate = _div_floor(adjusted_rate, 2)
					operation = "divide_by_2"
					source = "src/wild_encounter.c:WildEncounterCheck INFILTRATOR OW_INFILTRATOR >= GEN_8 path"
			"ABILITY_NO_GUARD":
				adjusted_rate *= 2
				operation = "multiply_by_2"
				source = "src/wild_encounter.c:WildEncounterCheck NO_GUARD path"
		if not operation.is_empty():
			modifiers.append(_rate_modifier(
				"lead_ability_encounter_rate",
				operation,
				before_ability,
				adjusted_rate,
				source,
				{"state": lead_ability}
			))

	if adjusted_rate > MAX_ENCOUNTER_RATE:
		var before_cap := adjusted_rate
		adjusted_rate = MAX_ENCOUNTER_RATE
		modifiers.append(_rate_modifier(
			"max_encounter_rate_cap",
			"clamp_to_max",
			before_cap,
			adjusted_rate,
			"src/wild_encounter.c:WildEncounterCheck MAX_ENCOUNTER_RATE cap",
			{}
		))

	var roll := _option_roll(options, "encounter_roll", MAX_ENCOUNTER_RATE)
	var hit := roll < adjusted_rate
	return {
		"status": "ok",
		"encounter": hit,
		"encounter_rate": encounter_rate,
		"adjusted_rate": adjusted_rate,
		"max_rate": MAX_ENCOUNTER_RATE,
		"roll": roll,
		"bike": bike,
		"flute": flute,
		"cleanse_tag": cleanse_tag,
		"repel_lure": repel_lure,
		"lead_ability": lead_ability,
		"modifiers": modifiers,
		"source": "src/wild_encounter.c:WildEncounterCheck -> EncounterOddsCheck",
		"unsupported": [{
			"code": "encounter_rate_modifiers_partially_integrated",
			"source": "src/wild_encounter.c:WildEncounterCheck",
			"detail": "Source-order bike, flute, Cleanse Tag, Lure, and lead ability encounter-rate math is applied when the needed field/party state is provided. Full avatar, weather, flute item-use UI, and Battle Frontier state integration remain future traced work.",
		}],
		"source_trace": SOURCE_TRACE.duplicate(),
	}


func try_standard_encounter(map_symbol: String, area = "land", options: Dictionary = {}) -> Dictionary:
	var table_result := get_table_for_area(map_symbol, area, options)
	if String(table_result.get("status", "")) != "ok":
		return table_result
	var table_field := String(table_result.get("area", ""))
	if table_field == "fishing_mons" or table_field == "hidden_mons":
		return {
			"status": "no_encounter",
			"reason": "non_standard_area",
			"area": table_field,
			"source": "src/wild_encounter.c:StandardWildEncounter excludes fishing/hidden encounters",
			"source_trace": SOURCE_TRACE.duplicate(),
		}

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
	var rate_options := options.duplicate(true)
	if table_field == "rock_smash_mons" and not rate_options.has("ignore_ability") and not rate_options.has("ignoreAbility"):
		rate_options["ignore_ability"] = true
	var rate_check := check_encounter_rate(int(table.get("encounter_rate", 0)), rate_options)
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
	elif String(wild_mon.get("status", "")) == "no_encounter":
		wild_mon["encounter_check"] = rate_check
		wild_mon["standard_encounter"] = {
			"status": "blocked_after_rate_check",
			"source": "src/wild_encounter.c:StandardWildEncounter -> TryGenerateWildMon",
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

	var ability_slot_choice := _ability_influenced_slot_choice(slots, table_field, options)
	var slot_result := {}
	if bool(ability_slot_choice.get("selected", false)):
		slot_result = {
			"slot_index": int(ability_slot_choice.get("slot_index", 0)),
			"ability_slot_choice": ability_slot_choice,
			"source": "src/wild_encounter.c:TryGenerateWildMon ability-influenced branch",
		}
	else:
		slot_result = _choose_slot(slots, field_definition, table_field, options)
		slot_result["ability_slot_choice"] = ability_slot_choice
	var slot_index := int(slot_result.get("slot_index", 0))
	if slot_index < 0 or slot_index >= slots.size():
		return _error_result("slot_index_out_of_range", "Selected wild slot %d is outside the generated table." % [slot_index])
	var slot = slots[slot_index]
	if typeof(slot) != TYPE_DICTIONARY:
		return _error_result("invalid_slot_record", "Selected wild slot %d is not a dictionary." % [slot_index])

	var level_result := _choose_level(slot, slots, table_field, options)
	var repel_filter := _repel_filter_result(int(level_result.get("level", 1)), table_field, options)
	if not bool(repel_filter.get("allowed", true)):
		return {
			"status": "no_encounter",
			"reason": "repel_level_filter",
			"map": _normalize_map_symbol(map_symbol),
			"area": table_field,
			"slot_index": slot_index,
			"slot": slot.duplicate(true),
			"slot_choice": slot_result,
			"ability_slot_choice": ability_slot_choice,
			"level": int(level_result.get("level", 1)),
			"level_choice": level_result,
			"repel_filter": repel_filter,
			"source": "src/wild_encounter.c:TryGenerateWildMon -> IsWildLevelAllowedByRepel",
			"unsupported": _first_pass_unsupported(table_field),
			"source_trace": SOURCE_TRACE.duplicate(),
		}
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
		"ability_slot_choice": ability_slot_choice,
		"species": String(species.get("symbol", "")),
		"species_id": int(species.get("value", 0)),
		"min_level": int(slot.get("min_level", 0)),
		"max_level": int(slot.get("max_level", 0)),
		"level": int(level_result.get("level", 1)),
		"level_choice": level_result,
		"repel_filter": repel_filter,
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
	var lure_swap := _lure_swap_result(options)
	if bool(lure_swap.get("swapped", false)):
		selected = slots.size() - 1 - selected
	return {
		"slot_index": selected,
		"roll": roll,
		"total_rate": total_rate,
		"lure_swap": lure_swap,
		"source": String(field_definition.get("selector", "")),
	}


func _ability_influenced_slot_choice(slots: Array, table_field: String, options: Dictionary) -> Dictionary:
	if table_field != "land_mons" and table_field != "water_mons":
		return {
			"selected": false,
			"status": "skipped",
			"reason": "area_not_supported",
			"area": table_field,
			"source": "src/wild_encounter.c:TryGenerateWildMon applies ability slots only to land/water",
			"source_trace": [
				"src/wild_encounter.c:TryGenerateWildMon",
			],
		}

	var lead_ability := _lead_slot_ability_state(options)
	if not bool(lead_ability.get("applies", false)):
		return {
			"selected": false,
			"status": "skipped",
			"reason": "lead_ability_unavailable",
			"lead_ability": lead_ability,
			"area": table_field,
			"source": "src/wild_encounter.c:TryGetAbilityInfluencedWildMonIndex lead egg/ability checks",
			"source_trace": [
				"src/wild_encounter.c:TryGetAbilityInfluencedWildMonIndex",
				"src/pokemon.c:GetMonData/GetMonAbility",
			],
		}

	var ability := String(lead_ability.get("ability", "ABILITY_NONE"))
	var rule := _ability_slot_rule_for_ability(ability, options)
	if rule.is_empty():
		return {
			"selected": false,
			"status": "skipped",
			"reason": "ability_has_no_slot_rule",
			"lead_ability": lead_ability,
			"ability": ability,
			"area": table_field,
			"source": "src/wild_encounter.c:TryGenerateWildMon source-order ability slot rules",
			"source_trace": [
				"src/wild_encounter.c:TryGenerateWildMon",
				"include/constants/abilities.h",
				"include/config/overworld.h",
			],
		}

	var activation_roll := _option_roll(options, "ability_slot_roll", 2)
	if activation_roll != 0:
		return {
			"selected": false,
			"status": "missed_roll",
			"reason": "activation_roll_failed",
			"lead_ability": lead_ability,
			"ability": ability,
			"target_type": String(rule.get("type", "")),
			"target_type_value": _source_type_value(String(rule.get("type", ""))),
			"activation_roll": activation_roll,
			"activation_modulo": 2,
			"area": table_field,
			"source": "src/wild_encounter.c:TryGetAbilityInfluencedWildMonIndex Random() % 2 != 0",
			"source_trace": [
				"src/wild_encounter.c:TryGetAbilityInfluencedWildMonIndex",
			],
		}

	var target_type := String(rule.get("type", ""))
	var valid_indices := _wild_slot_indices_by_type(slots, target_type)
	if valid_indices.is_empty():
		return {
			"selected": false,
			"status": "no_match",
			"reason": "no_slots_with_target_type",
			"lead_ability": lead_ability,
			"ability": ability,
			"target_type": target_type,
			"target_type_value": _source_type_value(target_type),
			"valid_indices": valid_indices,
			"valid_count": 0,
			"table_size": slots.size(),
			"activation_roll": activation_roll,
			"activation_modulo": 2,
			"area": table_field,
			"source": "src/wild_encounter.c:TryGetRandomWildMonIndexByType validMonCount == 0",
			"source_trace": [
				"src/wild_encounter.c:TryGetRandomWildMonIndexByType",
				"src/pokemon.c:GetSpeciesType",
			],
		}
	if valid_indices.size() == slots.size():
		return {
			"selected": false,
			"status": "all_slots_match",
			"reason": "valid_count_equals_table_size",
			"lead_ability": lead_ability,
			"ability": ability,
			"target_type": target_type,
			"target_type_value": _source_type_value(target_type),
			"valid_indices": valid_indices,
			"valid_count": valid_indices.size(),
			"table_size": slots.size(),
			"activation_roll": activation_roll,
			"activation_modulo": 2,
			"area": table_field,
			"source": "src/wild_encounter.c:TryGetRandomWildMonIndexByType validMonCount == numMon",
			"source_trace": [
				"src/wild_encounter.c:TryGetRandomWildMonIndexByType",
				"src/pokemon.c:GetSpeciesType",
			],
		}

	var pick_roll := _option_roll(options, "ability_slot_pick_roll", valid_indices.size())
	var selected_index := int(valid_indices[pick_roll])
	return {
		"selected": true,
		"status": "selected",
		"slot_index": selected_index,
		"pick_roll": pick_roll,
		"pick_modulo": valid_indices.size(),
		"lead_ability": lead_ability,
		"ability": ability,
		"target_type": target_type,
		"target_type_value": _source_type_value(target_type),
		"valid_indices": valid_indices,
		"valid_count": valid_indices.size(),
		"table_size": slots.size(),
		"activation_roll": activation_roll,
		"activation_modulo": 2,
		"area": table_field,
		"rule_source": String(rule.get("source", "")),
		"source": "src/wild_encounter.c:TryGetAbilityInfluencedWildMonIndex -> TryGetRandomWildMonIndexByType",
		"source_trace": [
			"src/wild_encounter.c:TryGenerateWildMon",
			"src/wild_encounter.c:TryGetAbilityInfluencedWildMonIndex",
			"src/wild_encounter.c:TryGetRandomWildMonIndexByType",
			"src/pokemon.c:GetSpeciesType",
		],
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
	var lure_swap := _lure_swap_result(options)
	if bool(lure_swap.get("swapped", false)) and typeof(indices) == TYPE_ARRAY and not indices.is_empty():
		var first := int(indices[0])
		var last := int(indices[indices.size() - 1])
		selected = first + last - selected
	return {
		"slot_index": selected,
		"roll": roll,
		"total_rate": total_rate,
		"rod_group": group_name,
		"rod": _rod_symbol(group_name),
		"lure_swap": lure_swap,
		"source": "src/wild_encounter.c:ChooseWildMonIndex_Fishing",
	}


func _choose_level(slot: Dictionary, slots: Array, table_field: String, options: Dictionary) -> Dictionary:
	var min_level := int(slot.get("min_level", 1))
	var max_level := int(slot.get("max_level", min_level))
	if min_level > max_level:
		var swap := min_level
		min_level = max_level
		max_level = swap

	var repel_lure := _repel_lure_state(options)
	if bool(repel_lure.get("lure_active", false)):
		var lure_level := max_level + 1
		if table_field != "fishing_mons":
			var max_same_species := _max_level_for_species(slots, _species_symbol(slot))
			if max_same_species > 0:
				lure_level = max_same_species + 1
		return {
			"level": lure_level,
			"min_level": min_level,
			"max_level": max_level,
			"repel_lure": repel_lure,
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


func _bike_state(options: Dictionary) -> Dictionary:
	if options.has("bike_active"):
		return {
			"active": bool(options.get("bike_active", false)),
			"source": "options.bike_active",
			"source_trace": ["src/wild_encounter.c:WildEncounterCheck", "include/global.fieldmap.h:PLAYER_AVATAR_FLAG_BIKE"],
		}
	if options.has("avatar_flags"):
		return {
			"active": _avatar_flags_include_bike(options.get("avatar_flags")),
			"source": "options.avatar_flags",
			"source_trace": ["src/wild_encounter.c:WildEncounterCheck", "include/global.fieldmap.h:PLAYER_AVATAR_FLAG_BIKE"],
		}
	return {
		"active": false,
		"source": "default_inactive",
		"source_trace": ["src/wild_encounter.c:WildEncounterCheck"],
	}


func _flute_state(options: Dictionary) -> Dictionary:
	var white_active := false
	var black_active := false
	var source := "default_inactive"
	if options.has("flute"):
		var flute := _normalize_item_symbol(options.get("flute"))
		white_active = flute == "ITEM_WHITE_FLUTE" or flute == "WHITE_FLUTE"
		black_active = flute == "ITEM_BLACK_FLUTE" or flute == "BLACK_FLUTE"
		source = "options.flute"
	if options.has("white_flute_active"):
		white_active = bool(options.get("white_flute_active", false))
		source = "options.white_flute_active"
	if options.has("black_flute_active"):
		black_active = bool(options.get("black_flute_active", false))
		source = "options.black_flute_active"
	if source == "default_inactive":
		var game_state := _get_game_state(options.get("game_state", null))
		if game_state != null and game_state.has_method("is_flag_set"):
			white_active = bool(game_state.is_flag_set("FLAG_SYS_ENC_UP_ITEM"))
			black_active = bool(game_state.is_flag_set("FLAG_SYS_ENC_DOWN_ITEM"))
			source = "GameState.FLAG_SYS_ENC_UP_ITEM/FLAG_SYS_ENC_DOWN_ITEM"
	if white_active:
		black_active = false
	return {
		"active": white_active or black_active,
		"white_flute_active": white_active,
		"black_flute_active": black_active,
		"source": source,
		"source_trace": [
			"src/item_use.c:ItemUseOutOfBattle_BlackWhiteFlute",
			"src/wild_encounter.c:ApplyFluteEncounterRateMod",
			"include/constants/flags.h:FLAG_SYS_ENC_UP_ITEM/FLAG_SYS_ENC_DOWN_ITEM",
		],
	}


func _cleanse_tag_state(options: Dictionary) -> Dictionary:
	if options.has("cleanse_tag_active"):
		return {
			"active": bool(options.get("cleanse_tag_active", false)),
			"held_item": "ITEM_CLEANSE_TAG" if bool(options.get("cleanse_tag_active", false)) else "ITEM_NONE",
			"source": "options.cleanse_tag_active",
			"source_trace": ["src/wild_encounter.c:ApplyCleanseTagEncounterRateMod"],
		}

	var held_item := ""
	var source := "default_no_party"
	if options.has("lead_held_item"):
		held_item = _normalize_item_symbol(options.get("lead_held_item"))
		source = "options.lead_held_item"
	elif options.has("held_item"):
		held_item = _normalize_item_symbol(options.get("held_item"))
		source = "options.held_item"
	else:
		var lead := _first_party_mon(options)
		held_item = _held_item_symbol(lead.get("mon", {}))
		source = String(lead.get("source", "default_no_party"))
	return {
		"active": held_item == "ITEM_CLEANSE_TAG",
		"held_item": held_item,
		"source": source,
		"source_trace": [
			"src/wild_encounter.c:ApplyCleanseTagEncounterRateMod",
			"include/constants/items.h:ITEM_CLEANSE_TAG",
		],
	}


func _lead_ability_state(options: Dictionary) -> Dictionary:
	var ignored := bool(options.get("ignore_ability", options.get("ignoreAbility", false)))
	if ignored:
		return {
			"applies": false,
			"ignored": true,
			"ability": "ABILITY_NONE",
			"source": "options.ignore_ability",
			"source_trace": ["src/wild_encounter.c:WildEncounterCheck ignoreAbility parameter"],
		}

	var ability := ""
	var is_egg := false
	var source := "default_no_party"
	if options.has("lead_ability"):
		ability = _normalize_ability_symbol(options.get("lead_ability"))
		is_egg = bool(options.get("lead_is_egg", false))
		source = "options.lead_ability"
	elif options.has("ability"):
		ability = _normalize_ability_symbol(options.get("ability"))
		is_egg = bool(options.get("lead_is_egg", false))
		source = "options.ability"
	else:
		var lead := _first_party_mon(options)
		var mon: Dictionary = lead.get("mon", {})
		ability = _ability_symbol(mon)
		is_egg = bool(mon.get("is_egg", false))
		source = String(lead.get("source", "default_no_party"))

	var can_apply := not is_egg and not ability.is_empty() and ability != "ABILITY_NONE"
	return {
		"applies": can_apply,
		"ignored": false,
		"ability": ability if not ability.is_empty() else "ABILITY_NONE",
		"is_egg": is_egg,
		"ow_infiltrator_gen8": bool(options.get("ow_infiltrator_gen8", true)),
		"source": source,
		"source_trace": [
			"src/wild_encounter.c:WildEncounterCheck lead ability branch",
			"include/constants/abilities.h",
			"include/config/overworld.h:OW_INFILTRATOR",
		],
	}


func _lead_slot_ability_state(options: Dictionary) -> Dictionary:
	var ignored := bool(options.get("ignore_ability_slot", options.get("ignoreAbilitySlot", false)))
	if ignored:
		return {
			"applies": false,
			"ignored": true,
			"ability": "ABILITY_NONE",
			"source": "options.ignore_ability_slot",
			"source_trace": ["src/wild_encounter.c:TryGenerateWildMon test override"],
		}
	var slot_options := options.duplicate(false)
	slot_options.erase("ignore_ability")
	slot_options.erase("ignoreAbility")
	var state := _lead_ability_state(slot_options)
	state["source_trace"] = [
		"src/wild_encounter.c:TryGetAbilityInfluencedWildMonIndex",
		"src/pokemon.c:GetMonData/GetMonAbility",
		"include/constants/abilities.h",
	]
	return state


func _repel_lure_state(options: Dictionary) -> Dictionary:
	var raw_value := 0
	var source := "default_inactive"
	if options.has("repel_lure_var"):
		raw_value = int(options.get("repel_lure_var", 0))
		source = "options.repel_lure_var"
	else:
		var game_state := _get_game_state(options.get("game_state", null))
		if game_state != null and game_state.has_method("get_var"):
			raw_value = int(game_state.get_var("VAR_REPEL_STEP_COUNT", 0))
			source = "GameState.VAR_REPEL_STEP_COUNT"

	var steps := raw_value & (REPEL_LURE_MASK - 1)
	var is_lure := (raw_value & REPEL_LURE_MASK) != 0
	var explicit_lure := options.has("lure_active") and bool(options.get("lure_active", false))
	var explicit_repel_steps := int(options.get("repel_steps", -1))
	var explicit_lure_steps := int(options.get("lure_steps", -1))
	var repel_steps := 0 if is_lure else steps
	var lure_steps := steps if is_lure else 0
	if explicit_repel_steps >= 0:
		repel_steps = explicit_repel_steps
		source = "options.repel_steps"
	if explicit_lure_steps >= 0:
		lure_steps = explicit_lure_steps
		source = "options.lure_steps"
	if explicit_lure and lure_steps <= 0:
		lure_steps = 1
		source = "options.lure_active"

	return {
		"raw_value": raw_value,
		"steps": steps,
		"is_lure": is_lure or lure_steps > 0,
		"repel_steps": repel_steps,
		"lure_steps": lure_steps,
		"repel_active": repel_steps > 0,
		"lure_active": lure_steps > 0,
		"source": source,
		"source_trace": [
			"include/constants/item.h:REPEL_LURE_MASK/LURE_STEP_COUNT/REPEL_STEP_COUNT",
			"src/wild_encounter.c:WildEncounterCheck/IsWildLevelAllowedByRepel",
		],
	}


func _lure_swap_result(options: Dictionary) -> Dictionary:
	var repel_lure := _repel_lure_state(options)
	if options.has("lure_swap"):
		return {
			"active": true,
			"swapped": bool(options.get("lure_swap", false)),
			"roll": -1,
			"threshold": 2,
			"modulo": 10,
			"repel_lure": repel_lure,
			"source": "test_override:lure_swap",
		}
	if not bool(repel_lure.get("lure_active", false)):
		return {
			"active": false,
			"swapped": false,
			"roll": -1,
			"threshold": 2,
			"modulo": 10,
			"repel_lure": repel_lure,
			"source": "src/wild_encounter.c:ChooseWildMonIndex_* LURE_STEP_COUNT inactive",
		}

	var roll := _option_roll(options, "lure_swap_roll", 10)
	return {
		"active": true,
		"swapped": roll < 2,
		"roll": roll,
		"threshold": 2,
		"modulo": 10,
		"repel_lure": repel_lure,
		"source": "src/wild_encounter.c:ChooseWildMonIndex_* LURE_STEP_COUNT swap roll",
	}


func _repel_filter_result(level: int, table_field: String, options: Dictionary) -> Dictionary:
	var repel_lure := _repel_lure_state(options)
	var applies := ["land_mons", "water_mons", "rock_smash_mons"].has(table_field)
	if bool(options.get("ignore_repel", false)):
		applies = false
	if bool(options.get("force_repel_filter", false)):
		applies = true
	if not applies:
		return {
			"status": "not_applicable",
			"allowed": true,
			"level": level,
			"area": table_field,
			"repel_lure": repel_lure,
			"source": "src/wild_encounter.c:TryGenerateWildMon flags without WILD_CHECK_REPEL",
		}
	if not bool(repel_lure.get("repel_active", false)):
		return {
			"status": "inactive",
			"allowed": true,
			"level": level,
			"area": table_field,
			"repel_lure": repel_lure,
			"source": "src/wild_encounter.c:IsWildLevelAllowedByRepel",
		}

	var lead := _repel_lead_level(options)
	var lead_level := int(lead.get("level", 0))
	var allowed := bool(lead.get("found", false)) and level >= lead_level
	return {
		"status": "allowed" if allowed else "blocked",
		"allowed": allowed,
		"level": level,
		"lead_level": lead_level,
		"lead": lead,
		"area": table_field,
		"repel_lure": repel_lure,
		"source": "src/wild_encounter.c:IsWildLevelAllowedByRepel",
	}


func _repel_lead_level(options: Dictionary) -> Dictionary:
	if options.has("repel_lead_level"):
		return {
			"found": true,
			"level": int(options.get("repel_lead_level", 0)),
			"source": "options.repel_lead_level",
		}

	var party: Array = []
	if options.has("player_party"):
		var option_party = options.get("player_party", [])
		party = option_party if typeof(option_party) == TYPE_ARRAY else []
	else:
		var game_state := _get_game_state(options.get("game_state", null))
		if game_state != null and game_state.has_method("get_player_party"):
			party = game_state.get_player_party()

	for index in range(min(party.size(), 6)):
		var mon = party[index]
		if typeof(mon) != TYPE_DICTIONARY:
			continue
		if bool(mon.get("is_egg", false)):
			continue
		if _party_species_is_none(mon):
			continue
		return {
			"found": true,
			"level": int(mon.get("level", 0)),
			"party_index": index,
			"include_fainted": true,
			"source": "src/wild_encounter.c:IsWildLevelAllowedByRepel + include/config/item.h:I_REPEL_INCLUDE_FAINTED = GEN_LATEST",
		}

	return {
		"found": false,
		"level": 0,
		"include_fainted": true,
		"source": "src/wild_encounter.c:IsWildLevelAllowedByRepel no non-egg party mon",
	}


func _party_species_is_none(mon: Dictionary) -> bool:
	var species = mon.get("species", "")
	if typeof(species) == TYPE_DICTIONARY:
		return String(species.get("symbol", "")) == "SPECIES_NONE"
	return String(species) == "SPECIES_NONE" or String(species).is_empty()


func _first_party_mon(options: Dictionary) -> Dictionary:
	if options.has("lead_mon"):
		var lead_mon = options.get("lead_mon", {})
		return {
			"mon": lead_mon if typeof(lead_mon) == TYPE_DICTIONARY else {},
			"source": "options.lead_mon",
		}
	var party: Array = []
	var source := "default_no_party"
	if options.has("player_party"):
		var option_party = options.get("player_party", [])
		party = option_party if typeof(option_party) == TYPE_ARRAY else []
		source = "options.player_party"
	else:
		var game_state := _get_game_state(options.get("game_state", null))
		if game_state != null and game_state.has_method("get_player_party"):
			party = game_state.get_player_party()
			source = "GameState.player_party"
	if party.is_empty() or typeof(party[0]) != TYPE_DICTIONARY:
		return {"mon": {}, "source": source}
	return {"mon": party[0], "source": source}


func _held_item_symbol(mon: Dictionary) -> String:
	var held_item = mon.get("held_item", mon.get("item", "ITEM_NONE"))
	return _normalize_item_symbol(held_item)


func _ability_symbol(mon: Dictionary) -> String:
	var ability = mon.get("ability", mon.get("ability_symbol", "ABILITY_NONE"))
	return _normalize_ability_symbol(ability)


func _rate_modifier(
	code: String,
	operation: String,
	before: int,
	after: int,
	source: String,
	extra: Dictionary
) -> Dictionary:
	var result := {
		"code": code,
		"operation": operation,
		"before": before,
		"after": after,
		"source": source,
	}
	for key in extra.keys():
		result[key] = extra[key]
	return result


func _div_floor(value: int, denominator: int) -> int:
	if denominator <= 0:
		return value
	return int(floor(float(value) / float(denominator)))


func _mul_div_floor(value: int, numerator: int, denominator: int) -> int:
	if denominator <= 0:
		return value
	return int(floor(float(value) * float(numerator) / float(denominator)))


func _avatar_flags_include_bike(value) -> bool:
	if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
		var flags := int(value)
		return (flags & (PLAYER_AVATAR_FLAG_MACH_BIKE | PLAYER_AVATAR_FLAG_ACRO_BIKE)) != 0
	if typeof(value) == TYPE_ARRAY:
		for entry in value:
			if _avatar_flag_entry_is_bike(entry):
				return true
		return false
	if typeof(value) == TYPE_DICTIONARY:
		for key in value.keys():
			if bool(value.get(key, false)) and _avatar_flag_entry_is_bike(key):
				return true
		return false
	return _avatar_flag_entry_is_bike(value)


func _avatar_flag_entry_is_bike(value) -> bool:
	var normalized := String(value).strip_edges().to_upper()
	return normalized in [
		"PLAYER_AVATAR_FLAG_MACH_BIKE",
		"PLAYER_AVATAR_FLAG_ACRO_BIKE",
		"PLAYER_AVATAR_FLAG_BIKE",
		"MACH_BIKE",
		"ACRO_BIKE",
		"BIKE",
	]


func _is_battle_pyramid_layout(options: Dictionary) -> bool:
	if bool(options.get("battle_pyramid_layout", false)):
		return true
	var layout = options.get("map_layout_id", options.get("layout_id", options.get("map_layout", "")))
	if typeof(layout) == TYPE_DICTIONARY:
		layout = layout.get("symbol", layout.get("id", ""))
	return String(layout).strip_edges().to_upper() == BATTLE_PYRAMID_LAYOUT


func _weather_matches(options: Dictionary, expected_weather: String) -> bool:
	return _normalize_weather_symbol(options.get("weather", "")) == expected_weather


func _normalize_weather_symbol(value) -> String:
	if typeof(value) == TYPE_DICTIONARY:
		if value.has("symbol"):
			return _normalize_weather_symbol(value.get("symbol", ""))
		if value.has("value"):
			return _normalize_weather_symbol(value.get("value", ""))
	if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
		var weather_value := int(value)
		if weather_value == WEATHER_SANDSTORM_VALUE:
			return "WEATHER_SANDSTORM"
		if weather_value == WEATHER_SNOW_VALUE:
			return "WEATHER_SNOW"
		return "WEATHER_%d" % [weather_value]
	var text := String(value).strip_edges().to_upper()
	if text.is_empty():
		return ""
	if text.begins_with("WEATHER_"):
		return text
	return "WEATHER_%s" % [text]


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
		"code": "wild_encounter_modifiers_partially_applied",
		"source": "src/wild_encounter.c:TryGenerateWildMon",
		"detail": "First-pass encounter-rate modifiers, ability-influenced land/water species slot selection, Repel/Lure rate/slot/level behavior, and Repel level filtering are applied. Roamer, mass outbreaks, double wild battles, Safari Pokeblocks, Synchronize, gender forcing, random IV/personality, and battle transition selection remain future traced work.",
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


func _wild_slot_indices_by_type(slots: Array, target_type: String) -> Array:
	var valid_indices: Array = []
	for index in range(slots.size()):
		var slot = slots[index]
		if typeof(slot) != TYPE_DICTIONARY:
			continue
		if _slot_species_has_type(slot, target_type):
			valid_indices.append(index)
	return valid_indices


func _slot_species_has_type(slot: Dictionary, target_type: String) -> bool:
	var species_symbol := _species_symbol(slot)
	if species_symbol.is_empty():
		return false
	var registry := _get_registry()
	if registry == null or not registry.has_method("get_species_record"):
		return false
	var species_record = registry.get_species_record(species_symbol)
	if typeof(species_record) != TYPE_DICTIONARY or species_record.is_empty():
		return false
	return _species_record_has_type(species_record, target_type)


func _species_record_has_type(species_record: Dictionary, target_type: String) -> bool:
	var raw_types = species_record.get("types", [])
	if typeof(raw_types) != TYPE_ARRAY:
		return false
	var normalized_target := _normalize_type_symbol(target_type)
	var target_value := _source_type_value(normalized_target)
	for type_record in raw_types:
		var type_symbol := _normalize_type_symbol(_constant_symbol(type_record))
		if not type_symbol.is_empty() and type_symbol == normalized_target:
			return true
		if target_value >= 0 and _type_record_value(type_record) == target_value:
			return true
	return false


func _type_record_value(type_record) -> int:
	if typeof(type_record) == TYPE_DICTIONARY:
		if type_record.has("value"):
			return int(type_record.get("value", -1))
		var symbol := _normalize_type_symbol(_constant_symbol(type_record))
		return _source_type_value(symbol)
	var symbol := _normalize_type_symbol(_constant_symbol(type_record))
	return _source_type_value(symbol)


func _source_type_value(type_symbol: String) -> int:
	var normalized := _normalize_type_symbol(type_symbol)
	if TYPE_SYMBOL_TO_VALUE.has(normalized):
		return int(TYPE_SYMBOL_TO_VALUE.get(normalized, -1))
	return -1


func _ability_slot_rule_for_ability(ability: String, options: Dictionary) -> Dictionary:
	for rule in ABILITY_SLOT_RULES:
		if typeof(rule) != TYPE_DICTIONARY:
			continue
		if String(rule.get("ability", "")) != ability:
			continue
		var option_key := String(rule.get("option", ""))
		if not option_key.is_empty() and not bool(options.get(option_key, true)):
			return {}
		return rule.duplicate(true)
	return {}


func _constant_symbol(value) -> String:
	if typeof(value) == TYPE_DICTIONARY:
		if value.has("symbol"):
			return String(value.get("symbol", ""))
		if value.has("id"):
			return String(value.get("id", ""))
	if value == null:
		return ""
	return String(value)


func _normalize_item_symbol(value) -> String:
	var item_symbol := _constant_symbol(value).strip_edges().to_upper()
	if item_symbol.is_empty():
		return "ITEM_NONE"
	if item_symbol.begins_with("ITEM_"):
		return item_symbol
	return "ITEM_%s" % [item_symbol]


func _normalize_ability_symbol(value) -> String:
	var ability_symbol := _constant_symbol(value).strip_edges().to_upper()
	if ability_symbol.is_empty():
		return "ABILITY_NONE"
	if ability_symbol.begins_with("ABILITY_"):
		return ability_symbol
	return "ABILITY_%s" % [ability_symbol]


func _normalize_type_symbol(value) -> String:
	var type_symbol := _constant_symbol(value).strip_edges().to_upper()
	if type_symbol.is_empty():
		return ""
	if type_symbol.begins_with("TYPE_"):
		return type_symbol
	return "TYPE_%s" % [type_symbol]


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
