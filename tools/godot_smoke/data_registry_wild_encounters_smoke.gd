extends SceneTree

const DATA_REGISTRY_SCRIPT := preload("res://scripts/autoload/data_registry.gd")

var _failed := false


func _init() -> void:
	var registry = DATA_REGISTRY_SCRIPT.new()
	registry._ready()

	var wild_data := registry.get_wild_encounters_data()
	var stats = wild_data.get("stats", {})
	_assert(typeof(wild_data) == TYPE_DICTIONARY and not wild_data.is_empty(), "expected wild encounter data")
	_assert(typeof(stats) == TYPE_DICTIONARY, "expected wild encounter stats")
	_assert(int(stats.get("encounter_record_count", 0)) == 399, "unexpected encounter record count")
	_assert(int(stats.get("map_encounter_count", 0)) == 388, "unexpected map encounter count")
	_assert(int(stats.get("group_count", 0)) == 3, "unexpected encounter group count")
	_assert(int(stats.get("mon_slot_count", 0)) == 6459, "unexpected wild mon slot count")
	_assert(int(stats.get("unique_species_count", 0)) == 222, "unexpected unique species count")
	_assert(int(stats.get("warning_count", -1)) == 0, "expected no wild encounter warnings")
	_assert(int(stats.get("unsupported_field_count", -1)) == 0, "expected no unsupported wild encounter fields")

	var table_counts := _dict_field(stats, "table_counts")
	var slot_counts := _dict_field(stats, "slot_counts")
	_assert(int(table_counts.get("land_mons", 0)) == 332, "unexpected land table count")
	_assert(int(table_counts.get("water_mons", 0)) == 155, "unexpected water table count")
	_assert(int(table_counts.get("rock_smash_mons", 0)) == 34, "unexpected rock smash table count")
	_assert(int(table_counts.get("fishing_mons", 0)) == 153, "unexpected fishing table count")
	_assert(int(slot_counts.get("land_mons", 0)) == 3984, "unexpected land slot count")
	_assert(int(slot_counts.get("fishing_mons", 0)) == 1530, "unexpected fishing slot count")

	var config := _dict_field(wild_data, "config")
	var time_config := _dict_field(config, "time")
	var generated_times := _array_field(time_config, "generated_header_times")
	_assert(time_config.get("time_of_day_encounters", true) == false, "expected source TOD encounters disabled")
	_assert(generated_times.size() == 1, "expected one generated fallback time")
	_assert(String(_array_dict(generated_times, 0).get("symbol", "")) == "TIME_MORNING", "expected generated TIME_MORNING fallback")
	_assert(String(_dict_field(time_config, "runtime_default_time").get("symbol", "")) == "TIME_OF_DAY_DEFAULT", "expected runtime default TOD")
	_assert(int(_dict_field(time_config, "runtime_default_time").get("value", -1)) == 0, "unexpected runtime default TOD value")
	_assert(config.get("dexnav_enabled", true) == false, "expected DexNav disabled by source config")

	var fields := _dict_field(wild_data, "field_definitions")
	var land_def := _dict_field(fields, "land_mons")
	var fishing_def := _dict_field(fields, "fishing_mons")
	_assert(int(_dict_field(land_def, "slot_count_constant").get("value", -1)) == 12, "expected LAND_WILD_COUNT")
	_assert(int(land_def.get("total_rate", -1)) == 100, "expected land total rate")
	_assert(_array_field(land_def, "slot_rates").size() == 12, "expected land slot rate count")
	_assert(int(_array_dict(_array_field(land_def, "slot_rates"), 1).get("cumulative_threshold", -1)) == 40, "expected land cumulative threshold")
	_assert(int(_dict_field(fishing_def, "slot_count_constant").get("value", -1)) == 10, "expected FISH_WILD_COUNT")
	var rod_groups := _dict_field(fishing_def, "rod_groups")
	_assert(int(_dict_field(rod_groups, "old_rod").get("total_rate", -1)) == 100, "expected Old Rod total rate")
	_assert(int(_dict_field(rod_groups, "good_rod").get("total_rate", -1)) == 100, "expected Good Rod total rate")
	_assert(int(_dict_field(rod_groups, "super_rod").get("total_rate", -1)) == 100, "expected Super Rod total rate")

	var groups := _dict_field(wild_data, "groups")
	_assert(int(_dict_field(groups, "gWildMonHeaders").get("encounter_count", 0)) == 388, "unexpected gWildMonHeaders count")
	_assert(int(_dict_field(groups, "gBattlePyramidWildMonHeaders").get("encounter_count", 0)) == 7, "unexpected Battle Pyramid encounter count")
	_assert(int(_dict_field(groups, "gBattlePikeWildMonHeaders").get("encounter_count", 0)) == 4, "unexpected Battle Pike encounter count")

	var route101 := registry.get_wild_encounter_record("gRoute101")
	var route101_by_map := registry.get_wild_encounter_record_for_map("route101")
	var route101_records := registry.get_wild_encounter_records_for_map("MAP_ROUTE101")
	_assert(String(route101.get("label", "")) == "gRoute101", "expected gRoute101 label lookup")
	_assert(String(route101_by_map.get("label", "")) == "gRoute101", "expected Route101 map lookup")
	_assert(route101_records.size() == 1, "expected one Route101 encounter record")
	_assert(int(_dict_field(route101, "map").get("value", -1)) == 16, "unexpected Route101 map id")
	var route101_land := _table(route101, "land_mons")
	_assert(int(route101_land.get("encounter_rate", -1)) == 20, "unexpected Route101 land encounter rate")
	_assert(_array_field(route101_land, "slots").size() == 12, "unexpected Route101 land slot count")
	_assert(String(_species(_slot(route101_land, 0)).get("symbol", "")) == "SPECIES_WURMPLE", "expected Route101 slot 0 species")
	_assert(int(_species(_slot(route101_land, 0)).get("value", -1)) == 265, "unexpected Wurmple species id")
	_assert(String(_species(_slot(route101_land, 1)).get("symbol", "")) == "SPECIES_POOCHYENA", "expected Route101 slot 1 species")

	var route119 := registry.get_wild_encounter_record_for_map("MAP_ROUTE119")
	var route119_land := _table(route119, "land_mons")
	var route119_water := _table(route119, "water_mons")
	var route119_fishing := _table(route119, "fishing_mons")
	_assert(String(route119.get("label", "")) == "gRoute119", "expected Route119 map lookup")
	_assert(int(route119_land.get("encounter_rate", -1)) == 15, "unexpected Route119 land rate")
	_assert(int(route119_water.get("encounter_rate", -1)) == 4, "unexpected Route119 water rate")
	_assert(int(route119_fishing.get("encounter_rate", -1)) == 30, "unexpected Route119 fishing rate")
	_assert(String(_species(_slot(route119_water, 0)).get("symbol", "")) == "SPECIES_TENTACOOL", "expected Route119 water slot 0")
	_assert(int(_species(_slot(route119_water, 0)).get("value", -1)) == 72, "unexpected Tentacool species id")
	_assert(String(_species(_slot(route119_fishing, 0)).get("symbol", "")) == "SPECIES_MAGIKARP", "expected Route119 fishing slot 0")

	var altering_records := registry.get_wild_encounter_records_for_map("altering_cave")
	var altering_first := registry.get_wild_encounter_record("gAlteringCave1")
	_assert(altering_records.size() == 9, "expected Altering Cave table count")
	_assert(String(altering_first.get("source_map_symbol", "")) == "MAP_ALTERING_CAVE", "expected Altering Cave source map")
	_assert(int(_dict_field(altering_first, "map").get("group", -1)) == 24, "unexpected Altering Cave map group")
	_assert(String(_species(_slot(_table(altering_first, "land_mons"), 0)).get("symbol", "")) == "SPECIES_ZUBAT", "expected Altering Cave slot 0")
	var altering_case := _dict_field(_dict_field(wild_data, "special_cases"), "altering_cave")
	_assert(int(altering_case.get("table_count", -1)) == 9, "unexpected special-case Altering Cave table count")
	_assert(int(_dict_field(altering_case, "table_count_constant").get("value", -1)) == 9, "unexpected NUM_ALTERING_CAVE_TABLES")

	if _failed:
		return

	print(JSON.stringify({
		"data_registry_wild_encounters_smoke": "ok",
		"encounter_record_count": int(stats.get("encounter_record_count", 0)),
		"mon_slot_count": int(stats.get("mon_slot_count", 0)),
		"altering_cave_tables": altering_records.size(),
	}))
	registry.free()
	quit(0)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true
	quit(1)


func _dict_field(record, field_name: String) -> Dictionary:
	if typeof(record) != TYPE_DICTIONARY:
		return {}
	var value = record.get(field_name, {})
	return value if typeof(value) == TYPE_DICTIONARY else {}


func _array_field(record: Dictionary, field_name: String) -> Array:
	var value = record.get(field_name, [])
	return value if typeof(value) == TYPE_ARRAY else []


func _array_dict(records: Array, index: int) -> Dictionary:
	if index < 0 or index >= records.size():
		return {}
	var value = records[index]
	return value if typeof(value) == TYPE_DICTIONARY else {}


func _table(record: Dictionary, field_name: String) -> Dictionary:
	return _dict_field(_dict_field(record, "tables"), field_name)


func _slot(table: Dictionary, index: int) -> Dictionary:
	return _array_dict(_array_field(table, "slots"), index)


func _species(slot: Dictionary) -> Dictionary:
	return _dict_field(slot, "species")
