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

	var fishing_standard := engine.try_standard_encounter("MAP_ROUTE119", "fishing", {
		"encounter_roll": 0,
	})
	_assert(String(fishing_standard.get("status", "")) == "no_encounter", "expected fishing to bypass standard encounter rate path")
	_assert(String(fishing_standard.get("reason", "")) == "non_standard_area", "expected fishing non-standard reason")

	var route111_rocks_ignore_ability := engine.try_standard_encounter("MAP_ROUTE111", "rock_smash", {
		"lead_ability": "ABILITY_ILLUMINATE",
		"encounter_roll": 320,
		"slot_roll": 0,
		"level_roll": 0,
	})
	_assert(String(route111_rocks_ignore_ability.get("status", "")) == "no_encounter", "expected Rock Smash to ignore lead encounter-rate ability")
	_assert(String(route111_rocks_ignore_ability.get("reason", "")) == "encounter_rate_miss", "expected Rock Smash miss at unmodified rate")
	_assert(int(_dict_field(route111_rocks_ignore_ability, "encounter_check").get("adjusted_rate", 0)) == 320, "expected Rock Smash base rate 320")
	_assert(not _modifier_codes(_dict_field(route111_rocks_ignore_ability, "encounter_check")).has("lead_ability_encounter_rate"), "expected no lead ability rate modifier for Rock Smash")

	var bike_rate := engine.check_encounter_rate(4, {
		"bike_active": true,
		"encounter_roll": 51,
	})
	_assert(not bool(bike_rate.get("encounter", true)), "expected bike-reduced rate to miss at roll 51")
	_assert(int(bike_rate.get("adjusted_rate", 0)) == 51, "expected bike 80 percent integer rate 51")
	_assert(_modifier_codes(bike_rate).has("bike_encounter_rate"), "expected bike modifier metadata")

	game_state.set_flag("FLAG_SYS_ENC_UP_ITEM", true)
	game_state.clear_flag("FLAG_SYS_ENC_DOWN_ITEM")
	var white_flute_rate := engine.check_encounter_rate(4, {
		"encounter_roll": 95,
	})
	_assert(bool(white_flute_rate.get("encounter", false)), "expected white flute to increase encounter rate")
	_assert(int(white_flute_rate.get("adjusted_rate", 0)) == 96, "expected white flute adjusted rate 96")
	_assert(_modifier_codes(white_flute_rate).has("white_flute_encounter_rate"), "expected white flute modifier metadata")

	game_state.clear_flag("FLAG_SYS_ENC_UP_ITEM")
	game_state.set_flag("FLAG_SYS_ENC_DOWN_ITEM", true)
	var black_flute_rate := engine.check_encounter_rate(4, {
		"encounter_roll": 32,
	})
	_assert(not bool(black_flute_rate.get("encounter", true)), "expected black flute to miss at roll 32")
	_assert(int(black_flute_rate.get("adjusted_rate", 0)) == 32, "expected black flute adjusted rate 32")
	_assert(_modifier_codes(black_flute_rate).has("black_flute_encounter_rate"), "expected black flute modifier metadata")
	game_state.clear_flag("FLAG_SYS_ENC_DOWN_ITEM")

	var cleanse_rate := engine.check_encounter_rate(4, {
		"player_party": [{"species": "SPECIES_TORCHIC", "level": 5, "held_item": "ITEM_CLEANSE_TAG", "is_egg": true}],
		"encounter_roll": 42,
	})
	_assert(not bool(cleanse_rate.get("encounter", true)), "expected Cleanse Tag to miss at roll 42")
	_assert(int(cleanse_rate.get("adjusted_rate", 0)) == 42, "expected Cleanse Tag adjusted rate 42")
	_assert(_modifier_codes(cleanse_rate).has("cleanse_tag_encounter_rate"), "expected Cleanse Tag modifier metadata")

	var illuminate_rate := engine.check_encounter_rate(4, {
		"lead_ability": "ABILITY_ILLUMINATE",
		"encounter_roll": 127,
	})
	_assert(bool(illuminate_rate.get("encounter", false)), "expected Illuminate to double encounter rate")
	_assert(int(illuminate_rate.get("adjusted_rate", 0)) == 128, "expected Illuminate adjusted rate 128")
	_assert(_modifier_codes(illuminate_rate).has("lead_ability_encounter_rate"), "expected lead ability modifier metadata")

	var ignored_ability_rate := engine.check_encounter_rate(4, {
		"lead_ability": "ABILITY_ILLUMINATE",
		"ignore_ability": true,
		"encounter_roll": 64,
	})
	_assert(not bool(ignored_ability_rate.get("encounter", true)), "expected ignored ability to preserve base miss")
	_assert(int(ignored_ability_rate.get("adjusted_rate", 0)) == 64, "expected ignored ability adjusted rate 64")
	_assert(not _modifier_codes(ignored_ability_rate).has("lead_ability_encounter_rate"), "expected no ability modifier when ignored")

	var sand_veil_rate := engine.check_encounter_rate(4, {
		"lead_ability": "ABILITY_SAND_VEIL",
		"weather": "WEATHER_SANDSTORM",
		"encounter_roll": 32,
	})
	_assert(not bool(sand_veil_rate.get("encounter", true)), "expected Sand Veil sandstorm to miss at roll 32")
	_assert(int(sand_veil_rate.get("adjusted_rate", 0)) == 32, "expected Sand Veil adjusted rate 32")

	var pyramid_stench_rate := engine.check_encounter_rate(4, {
		"lead_ability": "ABILITY_STENCH",
		"map_layout_id": "LAYOUT_BATTLE_FRONTIER_BATTLE_PYRAMID_FLOOR",
		"encounter_roll": 48,
	})
	_assert(not bool(pyramid_stench_rate.get("encounter", true)), "expected Battle Pyramid Stench to miss at roll 48")
	_assert(int(pyramid_stench_rate.get("adjusted_rate", 0)) == 48, "expected Battle Pyramid Stench 3/4 rate")

	var capped_rate := engine.check_encounter_rate(180, {
		"lead_ability": "ABILITY_NO_GUARD",
		"repel_lure_var": 32768 + 5,
		"encounter_roll": 2879,
	})
	_assert(bool(capped_rate.get("encounter", false)), "expected capped rate to hit max roll")
	_assert(int(capped_rate.get("adjusted_rate", 0)) == 2880, "expected source max encounter rate cap")
	_assert(_modifier_codes(capped_rate).has("max_encounter_rate_cap"), "expected cap metadata")

	var lure_rate := engine.check_encounter_rate(4, {
		"repel_lure_var": 32768 + 5,
		"encounter_roll": 100,
	})
	_assert(bool(lure_rate.get("encounter", false)), "expected lure to double Route119-style water rate")
	_assert(int(lure_rate.get("adjusted_rate", 0)) == 128, "expected lure adjusted rate 128")
	_assert(_array_field(lure_rate, "modifiers").size() == 1, "expected lure rate modifier metadata")

	game_state.set_var("VAR_REPEL_STEP_COUNT", 32768 + 5)
	var route101_lure := engine.choose_wild_mon("MAP_ROUTE101", "land", {
		"slot_roll": 0,
		"lure_swap_roll": 0,
	})
	_assert(int(route101_lure.get("slot_index", -1)) == 11, "expected lure swap to reverse Route101 slot")
	_assert(String(route101_lure.get("species", "")) == "SPECIES_ZIGZAGOON", "expected lure-swapped Route101 Zigzagoon")
	_assert(int(route101_lure.get("level", 0)) == 4, "expected lure level to be max same-species level plus one")
	_assert(bool(_dict_field(_dict_field(route101_lure, "slot_choice"), "lure_swap").get("swapped", false)), "expected lure swap metadata")
	_assert(bool(_dict_field(route101_lure, "level_choice").get("lure_active", false)), "expected lure level metadata")

	game_state.set_var("VAR_REPEL_STEP_COUNT", 10)
	game_state.set_player_party([{"species": "SPECIES_TORCHIC", "level": 5, "is_egg": false, "hp": 0}])
	var repel_block := engine.try_standard_encounter("MAP_ROUTE101", "land", {
		"encounter_roll": 0,
		"slot_roll": 0,
		"level_roll": 0,
	})
	_assert(String(repel_block.get("status", "")) == "no_encounter", "expected repel to block low-level Route101 mon")
	_assert(String(repel_block.get("reason", "")) == "repel_level_filter", "expected repel filter reason")
	_assert(bool(_dict_field(repel_block, "encounter_check").get("encounter", false)), "expected repel block after rate hit")
	_assert(bool(_dict_field(_dict_field(repel_block, "repel_filter"), "lead").get("include_fainted", false)), "expected current config to include fainted lead")

	game_state.set_player_party([{"species": "SPECIES_TORCHIC", "level": 2, "is_egg": false, "hp": 0}])
	var repel_allow := engine.try_standard_encounter("MAP_ROUTE101", "land", {
		"encounter_roll": 0,
		"slot_roll": 0,
		"level_roll": 0,
	})
	_assert(String(repel_allow.get("status", "")) == "ok", "expected equal-level repel lead to allow encounter")
	_assert(String(repel_allow.get("species", "")) == "SPECIES_WURMPLE", "expected repel-allowed Route101 Wurmple")
	_assert(String(_dict_field(repel_allow, "repel_filter").get("status", "")) == "allowed", "expected repel allowed metadata")
	game_state.set_var("VAR_REPEL_STEP_COUNT", 0)
	game_state.clear_player_party()

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


func _array_field(record: Dictionary, field_name: String) -> Array:
	var value = record.get(field_name, [])
	return value if typeof(value) == TYPE_ARRAY else []


func _modifier_codes(record: Dictionary) -> Array:
	var codes := []
	for modifier in _array_field(record, "modifiers"):
		if typeof(modifier) == TYPE_DICTIONARY:
			codes.append(String(modifier.get("code", "")))
	return codes
