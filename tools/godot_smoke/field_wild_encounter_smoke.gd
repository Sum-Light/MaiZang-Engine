extends SceneTree

const DATA_REGISTRY_SCRIPT := preload("res://scripts/autoload/data_registry.gd")
const GAME_STATE_SCRIPT := preload("res://scripts/autoload/game_state.gd")
const ENCOUNTER_ENGINE_SCRIPT := preload("res://scripts/autoload/encounter_engine.gd")
const EVENT_MANAGER_SCRIPT := preload("res://scripts/autoload/event_manager.gd")

var _failed := false


class FakeMapRuntime:
	extends Node

	var behavior_name := "MB_TALL_GRASS"
	var map_id := "MAP_ROUTE101"
	var coord_target: Dictionary = {}
	var warp_target: Dictionary = {}

	func get_metatile_behavior_name_at(_cell: Vector2i) -> String:
		return behavior_name

	func get_current_map_id() -> String:
		return map_id

	func get_coord_event_target(_cell: Vector2i, _game_state: Node = null) -> Dictionary:
		return coord_target.duplicate(true)

	func get_warp_event_target(_cell: Vector2i) -> Dictionary:
		return warp_target.duplicate(true)


func _init() -> void:
	var registry = DATA_REGISTRY_SCRIPT.new()
	registry._ready()

	var game_state = GAME_STATE_SCRIPT.new()
	game_state.current_map_id = "MAP_ROUTE101"

	var runtime = FakeMapRuntime.new()
	var engine = ENCOUNTER_ENGINE_SCRIPT.new()
	engine.configure_registry(registry)
	engine.configure_game_state(game_state)

	var manager = EVENT_MANAGER_SCRIPT.new()
	manager.configure_data_registry(registry)
	manager.configure_game_state(game_state)
	manager.configure_map_runtime(runtime)
	manager.configure_encounter_engine(engine)

	var captured := {}
	manager.debug_message_requested.connect(func(lines: PackedStringArray) -> void:
		captured["lines"] = lines
	)

	var cell := Vector2i(1, 1)
	var first_step := manager.try_dispatch_standard_wild_encounter(cell, {
		"encounter_roll": 0,
		"slot_roll": 0,
		"level_roll": 0,
	})
	var second_step := manager.try_dispatch_standard_wild_encounter(cell, {
		"encounter_roll": 0,
		"slot_roll": 0,
		"level_roll": 0,
	})
	manager.try_dispatch_standard_wild_encounter(cell, {
		"encounter_roll": 0,
		"slot_roll": 0,
		"level_roll": 0,
	})
	var fourth_step := manager.try_dispatch_standard_wild_encounter(cell, {
		"encounter_roll": 0,
		"slot_roll": 0,
		"level_roll": 0,
	})
	var hit := manager.try_dispatch_standard_wild_encounter(cell, {
		"encounter_roll": 0,
		"slot_roll": 0,
		"level_roll": 0,
	})
	var hit_lines = captured.get("lines", PackedStringArray())
	var after_hit_state := manager.get_wild_encounter_dispatch_state()

	_assert(String(first_step.get("reason", "")) == "immunity_steps", "expected first step immunity")
	_assert(int(first_step.get("immunity_steps_after", -1)) == 1, "expected first immunity count")
	_assert(String(second_step.get("reason", "")) == "immunity_steps", "expected second step immunity")
	_assert(String(fourth_step.get("reason", "")) == "immunity_steps", "expected fourth step immunity")
	_assert(int(fourth_step.get("immunity_steps_after", -1)) == 4, "expected fourth immunity count")
	_assert(bool(hit.get("encounter_requested", false)), "expected fifth step encounter request")
	_assert(String(hit.get("species", "")) == "SPECIES_WURMPLE", "expected Route101 Wurmple request")
	_assert(int(hit.get("level", 0)) == 2, "expected Route101 Wurmple level 2")
	_assert(int(after_hit_state.get("immunity_steps", -1)) == 0, "expected hit to reset immunity")
	_assert(_lines_contain(hit_lines, "Wild encounter"), "expected wild encounter debug output")
	_assert(_lines_contain(hit_lines, "Battle setup: pending"), "expected pending battle debug output")

	manager.reset_wild_encounter_immunity_steps()
	game_state.game_stats = {}
	runtime.behavior_name = "MB_TALL_GRASS"
	game_state.current_map_id = "MAP_ROUTE101"
	var player_step_first := manager.dispatch_player_step(cell, {
		"encounter_roll": 0,
		"slot_roll": 0,
		"level_roll": 0,
	})
	for _i in range(3):
		manager.dispatch_player_step(cell, {
			"encounter_roll": 0,
			"slot_roll": 0,
			"level_roll": 0,
		})
	var player_step_hit := manager.dispatch_player_step(cell, {
		"encounter_roll": 0,
		"slot_roll": 0,
		"level_roll": 0,
	})
	var player_step_wild := _dict_field(player_step_hit, "wild_encounter")
	_assert(String(_dict_field(player_step_first, "wild_encounter").get("reason", "")) == "immunity_steps", "expected player-step immunity")
	_assert(game_state.get_game_stat("GAME_STAT_STEPS", 0) == 5, "expected player-step stat increments")
	_assert(String(player_step_hit.get("consumed_by", "")) == "standard_wild_encounter", "expected player-step wild consumption")
	_assert(String(player_step_wild.get("species", "")) == "SPECIES_WURMPLE", "expected player-step Route101 Wurmple")

	manager.reset_wild_encounter_immunity_steps()
	runtime.coord_target = {
		"type": "coord_event",
		"position": cell,
		"script": "0x0",
		"event": {"script": "0x0", "var": "VAR_TEST", "var_value": 1},
	}
	var coord_step := manager.dispatch_player_step(cell, {
		"encounter_roll": 0,
	})
	_assert(String(coord_step.get("consumed_by", "")) == "coord_event", "expected coord event before wild")
	_assert(_dict_field(coord_step, "wild_encounter").is_empty(), "expected coord event to skip wild check")
	runtime.coord_target = {}

	runtime.warp_target = {
		"type": "warp_event",
		"position": cell,
		"script": "warp",
		"event": {"dest_map": "MAP_NOT_GENERATED", "dest_warp_id": 0},
	}
	var warp_step := manager.dispatch_player_step(cell, {
		"encounter_roll": 0,
	})
	_assert(String(warp_step.get("consumed_by", "")) == "warp_event", "expected warp event before wild")
	_assert(_dict_field(warp_step, "wild_encounter").is_empty(), "expected warp event to skip wild check")
	runtime.warp_target = {}

	manager.reset_wild_encounter_immunity_steps()
	game_state.set_var("VAR_REPEL_STEP_COUNT", 1)
	var repel_step := manager.dispatch_player_step(cell, {
		"encounter_roll": 0,
	})
	_assert(String(repel_step.get("consumed_by", "")) == "repel", "expected repel wear-off before wild")
	_assert(game_state.get_var("VAR_REPEL_STEP_COUNT", -1) == 0, "expected repel counter decrement to zero")
	_assert(_dict_field(repel_step, "wild_encounter").is_empty(), "expected repel wear-off to skip wild check")

	manager.reset_wild_encounter_immunity_steps()
	game_state.set_flag("OW_FLAG_NO_ENCOUNTER", true)
	var disabled := manager.try_dispatch_standard_wild_encounter(cell, {
		"encounter_roll": 0,
	})
	_assert(not bool(disabled.get("encounter_requested", false)), "expected no-encounter flag to block")
	_assert(String(disabled.get("reason", "")) == "no_encounter_flag", "expected no-encounter flag reason")
	_assert(int(disabled.get("immunity_steps_after", -1)) == 0, "expected flag not to advance immunity")
	game_state.clear_flag("OW_FLAG_NO_ENCOUNTER")

	manager.reset_wild_encounter_immunity_steps()
	runtime.behavior_name = "MB_NORMAL"
	for _i in range(4):
		manager.try_dispatch_standard_wild_encounter(cell, {})
	var normal_tile := manager.try_dispatch_standard_wild_encounter(cell, {
		"encounter_roll": 0,
	})
	_assert(not bool(normal_tile.get("encounter_requested", false)), "expected normal tile to skip encounters")
	_assert(String(normal_tile.get("reason", "")) == "non_encounter_metatile", "expected normal tile reason")

	manager.reset_wild_encounter_immunity_steps()
	runtime.behavior_name = "MB_OCEAN_WATER"
	game_state.current_map_id = "MAP_ROUTE119"
	for _i in range(4):
		manager.try_dispatch_standard_wild_encounter(cell, {})
	var water_hit := manager.try_dispatch_standard_wild_encounter(cell, {
		"encounter_roll": 0,
		"slot_roll": 0,
		"level_roll": 0,
	})
	_assert(bool(water_hit.get("encounter_requested", false)), "expected water encounter request")
	_assert(String(water_hit.get("species", "")) == "SPECIES_TENTACOOL", "expected Route119 water Tentacool")
	_assert(String(water_hit.get("area", "")) == "water_mons", "expected water encounter area")

	if _failed:
		return

	print(JSON.stringify({
		"field_wild_encounter_smoke": "ok",
		"route101_species": String(hit.get("species", "")),
		"route119_water_species": String(water_hit.get("species", "")),
		"immunity_after_hit": int(after_hit_state.get("immunity_steps", -1)),
	}))
	manager.free()
	engine.free()
	runtime.free()
	game_state.free()
	registry.free()
	quit(0)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true
	quit(1)


func _lines_contain(lines: PackedStringArray, needle: String) -> bool:
	for line in lines:
		if String(line).find(needle) != -1:
			return true
	return false


func _dict_field(record: Dictionary, field_name: String) -> Dictionary:
	var value = record.get(field_name, {})
	return value if typeof(value) == TYPE_DICTIONARY else {}
