extends SceneTree

const DATA_REGISTRY_SCRIPT := preload("res://scripts/autoload/data_registry.gd")
const GAME_STATE_SCRIPT := preload("res://scripts/autoload/game_state.gd")
const BATTLE_ENGINE_SCRIPT := preload("res://scripts/autoload/battle_engine.gd")
const PARTY_RUNTIME_SCRIPT := preload("res://scripts/autoload/party_runtime.gd")
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

	var battle_engine = BATTLE_ENGINE_SCRIPT.new()
	battle_engine.configure_registry(registry)
	var party_runtime = PARTY_RUNTIME_SCRIPT.new()
	party_runtime.configure_registry(registry)
	party_runtime.configure_battle_engine(battle_engine)
	var player_mon := battle_engine.create_battle_mon("SPECIES_TORCHIC", 5, {
		"moves": ["MOVE_SCRATCH"],
	})
	game_state.set_player_party([player_mon])

	var runtime = FakeMapRuntime.new()
	var engine = ENCOUNTER_ENGINE_SCRIPT.new()
	engine.configure_registry(registry)
	engine.configure_game_state(game_state)

	var manager = EVENT_MANAGER_SCRIPT.new()
	manager.configure_data_registry(registry)
	manager.configure_game_state(game_state)
	manager.configure_map_runtime(runtime)
	manager.configure_encounter_engine(engine)
	manager.configure_battle_engine(battle_engine)
	manager.configure_party_runtime(party_runtime)

	var captured := {}
	manager.debug_message_requested.connect(func(lines: PackedStringArray) -> void:
		captured["lines"] = lines
	)
	manager.battle_start_sequence_requested.connect(func(sequence: Dictionary) -> void:
		captured["battle_start_sequence"] = sequence
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
	var hit_battle_start := _dict_field(hit, "battle_start_sequence")
	var hit_battle_sequence := _dict_field(hit_battle_start, "sequence")
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
	_assert(_lines_contain(hit_lines, "Battle setup: state_created"), "expected battle setup debug output")
	_assert(_lines_contain(hit_lines, "Battle start: sequence_requested"), "expected battle start debug output")
	var hit_battle_setup := _dict_field(hit, "battle_setup")
	var hit_battle_state := _dict_field(hit_battle_setup, "battle_state")
	var hit_opponent := _array_dict(_array_field(hit_battle_state, "opponent_party"), 0)
	_assert(String(hit_battle_setup.get("status", "")) == "state_created", "expected wild battle setup state")
	_assert(String(hit_battle_state.get("battle_kind", "")) == "wild", "expected wild battle kind")
	_assert(String(hit_opponent.get("species", "")) == "SPECIES_WURMPLE", "expected battle opponent Wurmple")
	_assert(int(hit_battle_setup.get("player_party_count", 0)) == 1, "expected one player party mon in battle setup")
	_assert(String(hit_battle_start.get("status", "")) == "sequence_requested", "expected battle start sequence request")
	_assert(String(hit_battle_sequence.get("type", "")) == "battle_start", "expected battle-start sequence type")
	_assert(String(hit_battle_sequence.get("species", "")) == "SPECIES_WURMPLE", "expected battle-start Wurmple species")
	_assert(_first_step_op(hit_battle_sequence) == "lock_controls", "expected battle-start to lock controls first")
	_assert(_has_step_op(hit_battle_sequence, "battle_transition_start"), "expected battle transition start step")
	_assert(_has_step_op(hit_battle_sequence, "clear_mirage_tower_pulse_blend"), "expected Mirage Tower blend cleanup metadata")
	_assert(_has_step_op(hit_battle_sequence, "set_main_callback"), "expected CB2_InitBattle handoff step")
	_assert(_dict_field(hit_battle_sequence, "battle_transition").get("comparison", "") == "enemy_lower", "expected lower-level wild transition comparison")
	_assert(game_state.get_game_stat("GAME_STAT_TOTAL_BATTLES", 0) == 1, "expected total battle stat increment")
	_assert(game_state.get_game_stat("GAME_STAT_WILD_BATTLES", 0) == 1, "expected wild battle stat increment")
	_assert(_dict_field(captured, "battle_start_sequence").get("id", -1) == hit_battle_start.get("id", -2), "expected signal sequence id to match summary")

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
	var player_step_battle_start := _dict_field(player_step_wild, "battle_start_sequence")
	_assert(String(_dict_field(player_step_first, "wild_encounter").get("reason", "")) == "immunity_steps", "expected player-step immunity")
	_assert(game_state.get_game_stat("GAME_STAT_STEPS", 0) == 5, "expected player-step stat increments")
	_assert(game_state.get_game_stat("GAME_STAT_TOTAL_BATTLES", 0) == 1, "expected player-step total battle stat increment")
	_assert(game_state.get_game_stat("GAME_STAT_WILD_BATTLES", 0) == 1, "expected player-step wild battle stat increment")
	_assert(String(player_step_hit.get("consumed_by", "")) == "standard_wild_encounter", "expected player-step wild consumption")
	_assert(String(player_step_wild.get("species", "")) == "SPECIES_WURMPLE", "expected player-step Route101 Wurmple")
	_assert(String(player_step_battle_start.get("status", "")) == "sequence_requested", "expected player-step battle-start sequence")

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
		"battle_start_type": String(hit_battle_sequence.get("type", "")),
		"immunity_after_hit": int(after_hit_state.get("immunity_steps", -1)),
	}))
	manager.free()
	engine.free()
	party_runtime.free()
	battle_engine.free()
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


func _array_field(record: Dictionary, field_name: String) -> Array:
	var value = record.get(field_name, [])
	return value if typeof(value) == TYPE_ARRAY else []


func _array_dict(records: Array, index: int) -> Dictionary:
	if index < 0 or index >= records.size():
		return {}
	var value = records[index]
	return value if typeof(value) == TYPE_DICTIONARY else {}


func _first_step_op(sequence: Dictionary) -> String:
	var steps = sequence.get("steps", [])
	if typeof(steps) != TYPE_ARRAY or steps.is_empty():
		return ""
	var first = steps[0]
	return String(first.get("op", "")) if typeof(first) == TYPE_DICTIONARY else ""


func _has_step_op(sequence: Dictionary, op: String) -> bool:
	var steps = sequence.get("steps", [])
	if typeof(steps) != TYPE_ARRAY:
		return false
	for step in steps:
		if typeof(step) == TYPE_DICTIONARY and String(step.get("op", "")) == op:
			return true
	return false
