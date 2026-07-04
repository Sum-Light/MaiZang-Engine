extends SceneTree

const DATA_REGISTRY_SCRIPT := preload("res://scripts/autoload/data_registry.gd")
const GAME_STATE_SCRIPT := preload("res://scripts/autoload/game_state.gd")
const ENCOUNTER_ENGINE_SCRIPT := preload("res://scripts/autoload/encounter_engine.gd")

var _failed := false


func _init() -> void:
	var registry = DATA_REGISTRY_SCRIPT.new()
	registry._ready()

	var game_state = GAME_STATE_SCRIPT.new()
	var engine = ENCOUNTER_ENGINE_SCRIPT.new()
	engine.configure_registry(registry)
	engine.configure_game_state(game_state)

	var route101 := engine.choose_wild_mon("MAP_ROUTE101", "land", {
		"slot_roll": 0,
		"level_roll": 0,
	})
	var land_routing := engine.area_for_metatile_behavior("MB_TALL_GRASS")
	var water_routing := engine.area_for_metatile_behavior("MB_OCEAN_WATER")
	var bridge_no_surf := engine.area_for_metatile_behavior("MB_BRIDGE_OVER_OCEAN")
	var bridge_surf := engine.area_for_metatile_behavior("MB_BRIDGE_OVER_OCEAN", {
		"surfing": true,
	})
	var routed_route101 := engine.try_standard_encounter_for_behavior(
		"MAP_ROUTE101",
		"MB_TALL_GRASS",
		"MB_NORMAL",
		{
			"new_metatile_roll": 0,
			"encounter_roll": 0,
			"slot_roll": 0,
			"level_roll": 0,
		}
	)
	_assert(String(route101.get("status", "")) == "ok", "expected Route101 land encounter")
	_assert(String(route101.get("record_label", "")) == "gRoute101", "expected Route101 label")
	_assert(String(route101.get("area", "")) == "land_mons", "expected land area")
	_assert(int(route101.get("slot_index", -1)) == 0, "expected Route101 slot 0")
	_assert(String(route101.get("species", "")) == "SPECIES_WURMPLE", "expected Route101 Wurmple")
	_assert(int(route101.get("species_id", 0)) == 265, "expected Wurmple species id")
	_assert(int(route101.get("level", 0)) == 2, "expected Route101 Wurmple level 2")
	_assert(String(_dict_field(route101, "runtime_time").get("symbol", "")) == "TIME_OF_DAY_DEFAULT", "expected default encounter time")
	_assert(String(land_routing.get("area", "")) == "land", "expected tall grass to route to land")
	_assert(String(water_routing.get("area", "")) == "water", "expected ocean water to route to water")
	_assert(String(bridge_no_surf.get("status", "")) == "no_encounter", "expected bridge without surfing to skip")
	_assert(String(bridge_surf.get("area", "")) == "water", "expected surfing bridge to route to water")
	_assert(String(routed_route101.get("status", "")) == "ok", "expected routed Route101 encounter")
	_assert(String(routed_route101.get("species", "")) == "SPECIES_WURMPLE", "expected routed Route101 Wurmple")
	_assert(bool(_dict_field(routed_route101, "metatile_routing").has("source_trace")), "expected routing source trace")

	var route101_late_slot := engine.choose_wild_mon("route101", "WILD_AREA_LAND", {
		"slot_roll": 99,
		"level_roll": 0,
	})
	_assert(int(route101_late_slot.get("slot_index", -1)) == 11, "expected Route101 final land slot")
	_assert(String(route101_late_slot.get("species", "")) == "SPECIES_ZIGZAGOON", "expected Route101 final slot Zigzagoon")

	var route119_old_rod := engine.choose_wild_mon("MAP_ROUTE119", "fishing", {
		"rod": "OLD_ROD",
		"slot_roll": 69,
		"level_roll": 0,
	})
	var route119_good_rod := engine.choose_wild_mon("MAP_ROUTE119", "fishing", {
		"rod": "GOOD_ROD",
		"slot_roll": 60,
		"level_roll": 0,
	})
	var route119_super_rod := engine.choose_wild_mon("MAP_ROUTE119", "fishing", {
		"rod": "SUPER_ROD",
		"slot_roll": 99,
		"level_roll": 0,
	})
	_assert(int(route119_old_rod.get("slot_index", -1)) == 0, "expected Old Rod slot 0")
	_assert(String(route119_old_rod.get("species", "")) == "SPECIES_MAGIKARP", "expected Old Rod Magikarp")
	_assert(int(route119_good_rod.get("slot_index", -1)) == 3, "expected Good Rod slot 3")
	_assert(String(_dict_field(route119_good_rod, "slot_choice").get("rod_group", "")) == "good_rod", "expected Good Rod group")
	_assert(int(route119_super_rod.get("slot_index", -1)) == 9, "expected Super Rod final slot")
	_assert(String(_dict_field(route119_super_rod, "slot_choice").get("rod_group", "")) == "super_rod", "expected Super Rod group")
	_assert(engine.has_fishing_encounters("MAP_ROUTE119"), "expected Route119 fishing table")

	var route119_standard_miss := engine.try_standard_encounter("MAP_ROUTE119", "water", {
		"encounter_roll": 64,
		"slot_roll": 0,
		"level_roll": 0,
	})
	var route119_standard_hit := engine.try_standard_encounter("MAP_ROUTE119", "water", {
		"encounter_roll": 63,
		"slot_roll": 0,
		"level_roll": 0,
	})
	_assert(String(route119_standard_miss.get("status", "")) == "no_encounter", "expected Route119 water miss")
	_assert(String(route119_standard_miss.get("reason", "")) == "encounter_rate_miss", "expected miss reason")
	_assert(String(route119_standard_hit.get("status", "")) == "ok", "expected Route119 water hit")
	_assert(String(route119_standard_hit.get("species", "")) == "SPECIES_TENTACOOL", "expected Route119 water Tentacool")
	_assert(bool(_dict_field(route119_standard_hit, "encounter_check").get("encounter", false)), "expected encounter hit metadata")

	var route101_skip := engine.try_standard_encounter("MAP_ROUTE101", "land", {
		"metatile_changed": true,
		"new_metatile_roll": 60,
		"encounter_roll": 0,
		"slot_roll": 0,
	})
	_assert(String(route101_skip.get("status", "")) == "no_encounter", "expected new-metatile skip")
	_assert(String(route101_skip.get("reason", "")) == "new_metatile_skip", "expected new-metatile skip reason")

	game_state.set_var("VAR_ALTERING_CAVE_WILD_SET", 2)
	var altering_from_state := engine.choose_wild_mon("altering_cave", "land", {
		"slot_roll": 0,
		"level_roll": 0,
	})
	var altering_clamped := engine.choose_wild_mon("MAP_ALTERING_CAVE", "land", {
		"altering_cave_set": 99,
		"slot_roll": 0,
		"level_roll": 0,
	})
	_assert(String(altering_from_state.get("record_label", "")) == "gAlteringCave3", "expected Altering Cave var offset")
	_assert(String(altering_from_state.get("species", "")) == "SPECIES_PINECO", "expected Altering Cave set 3 Pineco")
	_assert(String(altering_clamped.get("record_label", "")) == "gAlteringCave1", "expected Altering Cave clamp to first table")
	_assert(String(altering_clamped.get("species", "")) == "SPECIES_ZUBAT", "expected Altering Cave default Zubat")

	if _failed:
		return

	print(JSON.stringify({
		"encounter_engine_smoke": "ok",
		"route101_species": String(route101.get("species", "")),
		"route119_water_species": String(route119_standard_hit.get("species", "")),
		"altering_cave_record": String(altering_from_state.get("record_label", "")),
	}))
	engine.free()
	game_state.free()
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
