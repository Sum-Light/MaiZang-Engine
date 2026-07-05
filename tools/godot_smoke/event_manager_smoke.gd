extends SceneTree

const EVENT_MANAGER_SCRIPT := preload("res://scripts/autoload/event_manager.gd")
const SCRIPT_VM_SCRIPT := preload("res://scripts/autoload/script_vm.gd")
const MAP_RUNTIME_SCRIPT := preload("res://scripts/autoload/map_runtime.gd")
const GAME_STATE_SCRIPT := preload("res://scripts/autoload/game_state.gd")
const DATA_REGISTRY_SCRIPT := preload("res://scripts/autoload/data_registry.gd")
const BATTLE_ENGINE_SCRIPT := preload("res://scripts/autoload/battle_engine.gd")
const PARTY_RUNTIME_SCRIPT := preload("res://scripts/autoload/party_runtime.gd")
const START_MAP := "MAP_LITTLEROOT_TOWN"
const BRENDANS_HOUSE_1F := "MAP_LITTLEROOT_TOWN_BRENDANS_HOUSE_1F"
const BRENDANS_HOUSE_2F := "MAP_LITTLEROOT_TOWN_BRENDANS_HOUSE_2F"
const MAYS_HOUSE_1F := "MAP_LITTLEROOT_TOWN_MAYS_HOUSE_1F"
const MAYS_HOUSE_2F := "MAP_LITTLEROOT_TOWN_MAYS_HOUSE_2F"


func _init() -> void:
	var registry = DATA_REGISTRY_SCRIPT.new()
	registry._ready()
	_assert(registry.has_map_data(START_MAP), "expected start map in registry")
	_assert(registry.has_map_data(BRENDANS_HOUSE_1F), "expected Brendan house 1F in registry")
	_assert(registry.has_map_data(MAYS_HOUSE_1F), "expected May house 1F in registry")
	_assert(registry.get_map_size(BRENDANS_HOUSE_1F) == Vector2i(11, 9), "unexpected Brendan house map size")
	_assert(registry.get_map_size(MAYS_HOUSE_1F) == Vector2i(11, 9), "unexpected May house map size")

	var script_data := registry.get_start_script_data()
	var map_data := registry.get_start_map_data()
	var tileset_data := registry.get_start_tileset_data()
	var vm = SCRIPT_VM_SCRIPT.new()
	vm.configure_from_script_data(script_data)
	var runtime = MAP_RUNTIME_SCRIPT.new()
	runtime.configure_data_registry(registry)
	runtime.configure_from_data(map_data, tileset_data, _map_size_from_data(map_data))
	var game_state = GAME_STATE_SCRIPT.new()
	var manager = EVENT_MANAGER_SCRIPT.new()
	manager.configure_from_script_data(script_data)
	manager.configure_script_vm(vm)
	manager.configure_map_runtime(runtime)
	manager.configure_game_state(game_state)
	manager.configure_data_registry(registry)
	var battle_engine = BATTLE_ENGINE_SCRIPT.new()
	battle_engine.configure_registry(registry)
	var party_runtime = PARTY_RUNTIME_SCRIPT.new()
	party_runtime.configure_registry(registry)
	party_runtime.configure_battle_engine(battle_engine)
	manager.configure_battle_engine(battle_engine)
	manager.configure_party_runtime(party_runtime)

	var fallback_script_data := script_data.duplicate(true)
	var fallback_scripts: Dictionary = fallback_script_data.get("scripts", {})
	fallback_scripts["Smoke_EventScript_GlobalTextPreview"] = {
		"kind": "script",
		"label": "Smoke_EventScript_GlobalTextPreview",
		"line": 1,
		"instructions": [
			{"op": "msgbox", "args": ["gText_ConfirmSave", "MSGBOX_DEFAULT"], "line": 1, "raw": "msgbox gText_ConfirmSave, MSGBOX_DEFAULT"},
			{"op": "end", "args": [], "line": 2, "raw": "end"},
		],
		"msgboxes": [
			{"op": "msgbox", "text_label": "gText_ConfirmSave", "mode": "MSGBOX_DEFAULT", "line": 1},
		],
	}
	fallback_script_data["scripts"] = fallback_scripts
	var fallback_manager = EVENT_MANAGER_SCRIPT.new()
	fallback_manager.configure_from_script_data(fallback_script_data)
	fallback_manager.configure_data_registry(registry)
	var global_fallback_preview := fallback_manager.get_script_preview("Smoke_EventScript_GlobalTextPreview")

	var twin_preview := manager.get_script_preview("LittlerootTown_EventScript_Twin")
	var sign_preview := manager.get_script_preview("LittlerootTown_EventScript_TownSign")
	var need_pokemon_preview := manager.get_script_preview("LittlerootTown_EventScript_NeedPokemonTriggerLeft")
	var empty_preview := manager.get_script_preview("0x0")
	var need_pokemon_coord := runtime.get_coord_event_target(Vector2i(10, 1), game_state)
	_assert(game_state.player_grid_position == Vector2i(10, 10), "expected preview to leave player position unchanged")
	_assert(
		_event_position(runtime.get_object_event_by_local_id("LOCALID_LITTLEROOT_TWIN", true)) == Vector2i(16, 10),
		"expected preview to leave twin position unchanged"
	)
	_assert(need_pokemon_coord.get("type", "") == "coord_event", "expected need-pokemon coord event target")
	_assert(
		need_pokemon_coord.get("script", "") == "LittlerootTown_EventScript_NeedPokemonTriggerLeft",
		"unexpected need-pokemon coord script"
	)
	var captured := {}
	manager.debug_message_requested.connect(func(lines: PackedStringArray) -> void:
		captured["lines"] = lines
	)
	var captured_sequences := []
	manager.transition_sequence_requested.connect(func(sequence: Dictionary) -> void:
		captured_sequences.append(sequence)
	)
	var trainer_battle_request := manager.request_trainer_battle_start({
		"trainer_id": "TRAINER_SAWYER_1",
		"map": START_MAP,
		"position": Vector2i(10, 12),
		"debug_fixture": true,
		"debug_allow_empty_party_fallback": true,
		"battle_origin": "debug_trainer_npc",
		"recorded_link_battle": true,
		"recorded_text_speed_index": 2,
	})
	var trainer_battle_sequence := _dict_value(trainer_battle_request.get("sequence", {}))
	var trainer_battle_ops := _step_ops(trainer_battle_sequence)
	var trainer_battle_text_context := _dict_value(trainer_battle_sequence.get("battle_text_context", {}))
	manager.dispatch_interaction({
		"type": "object_event",
		"script": "LittlerootTown_EventScript_Twin",
		"position": Vector2i(16, 10),
		"event": {
			"graphics_id": "OBJ_EVENT_GFX_TWIN",
			"script": "LittlerootTown_EventScript_Twin",
		},
	})
	game_state.player_grid_position = Vector2i(10, 1)
	manager.dispatch_interaction(need_pokemon_coord)
	var coord_lines = captured.get("lines", PackedStringArray())
	captured.clear()
	manager.dispatch_interaction({
		"type": "object_event",
		"script": "LittlerootTown_EventScript_SetRivalBirchPosForDexUpgradeMale",
		"position": Vector2i(13, 10),
		"event": {
			"graphics_id": "OBJ_EVENT_GFX_RIVAL_BRENDAN_NORMAL",
			"script": "LittlerootTown_EventScript_SetRivalBirchPosForDexUpgradeMale",
		},
	})
	var object_effect_lines = captured.get("lines", PackedStringArray())
	var player_position_after_coord_dispatch: Vector2i = game_state.player_grid_position
	var twin_position_after_coord_dispatch := _event_position(runtime.get_object_event_by_local_id("LOCALID_LITTLEROOT_TWIN", true))
	var rival_position_after_object_dispatch := _event_position(runtime.get_object_event_by_local_id("LOCALID_LITTLEROOT_RIVAL", true))
	var birch_position_after_object_dispatch := _event_position(runtime.get_object_event_by_local_id("LOCALID_LITTLEROOT_BIRCH", true))
	captured.clear()
	captured_sequences.clear()
	manager.dispatch_interaction({
		"type": "coord_event",
		"script": "LittlerootTown_EventScript_StepOffTruckMale",
		"position": Vector2i(0, 0),
		"event": {
			"script": "LittlerootTown_EventScript_StepOffTruckMale",
		},
	})
	var transition_lines = captured.get("lines", PackedStringArray())
	var truck_transition_sequence = captured_sequences[0] if captured_sequences.size() > 0 else {}
	var truck_exit_task := _exit_task(truck_transition_sequence)
	var truck_exit_step := _first_step(truck_transition_sequence, "exit_task_select")
	var truck_conditional_step := _first_step(truck_transition_sequence, "conditional_exit_door_player_step")
	var player_position_after_step_off: Vector2i = game_state.player_grid_position
	var house_script_result := manager.run_script("LittlerootTown_BrendansHouse_1F_EventScript_MoveMomToDoor")
	var old_map_script_result := manager.run_script("LittlerootTown_EventScript_Twin")
	var brendan_map_data: Dictionary = registry.get_map_data(BRENDANS_HOUSE_1F)
	var brendan_object_events = brendan_map_data.get("events", {}).get("object_events", [])
	var brendan_mom_after_transition := runtime.get_object_event_by_local_id("LOCALID_PLAYERS_HOUSE_1F_MOM", true)
	var brendan_mom_position_after_transition := _event_position(brendan_mom_after_transition)
	var brendan_mom_movement_after_transition := String(brendan_mom_after_transition.get("movement_type", ""))
	var brendan_on_frame_intro := manager.dispatch_on_frame_map_script({
		"trigger": "smoke_on_frame_intro",
		"map": game_state.current_map_id,
	})
	var brendan_on_frame_intro_lines = captured.get("lines", PackedStringArray())
	var brendan_on_frame_intro_script = brendan_on_frame_intro.get("script", {})
	var brendan_on_frame_intro_runtime = brendan_on_frame_intro.get("runtime", {})
	var brendan_on_frame_intro_movements = brendan_on_frame_intro_runtime.get("movements", {}) if typeof(brendan_on_frame_intro_runtime) == TYPE_DICTIONARY else {}
	var player_position_after_brendan_intro: Vector2i = game_state.player_grid_position
	var brendan_mom_by_numeric_local_id := runtime.get_object_event_by_local_id("1", true)
	var brendan_intro_mom_local_id := game_state.get_var("VAR_0x8004", -1)
	var brendan_intro_gender_value := game_state.get_var("VAR_0x8005", -1)
	var brendan_intro_state_value := game_state.get_var("VAR_LITTLEROOT_INTRO_STATE", -1)

	_assert(twin_preview.get("status", "") == "ok", "expected Twin script preview")
	_assert(twin_preview.get("vm_status", "") == "ok", "expected Twin VM status")
	_assert(
		twin_preview.get("text_label", "") == "LittlerootTown_Text_IfYouGoInGrassPokemonWillJumpOut",
		"unexpected Twin text label"
	)
	_assert(not String(twin_preview.get("text", "")).is_empty(), "expected Twin preview text")
	_assert(sign_preview.get("status", "") == "ok", "expected town sign script preview")
	_assert(sign_preview.get("vm_status", "") == "ok", "expected town sign VM status")
	_assert(
		sign_preview.get("text_label", "") == "LittlerootTown_Text_TownSign",
		"unexpected town sign text label"
	)
	_assert(not String(sign_preview.get("text", "")).is_empty(), "expected town sign preview text")
	_assert(need_pokemon_preview.get("status", "") == "ok", "expected need-pokemon script preview")
	_assert(
		need_pokemon_preview.get("text_label", "") == "LittlerootTown_Text_IfYouGoInGrassPokemonWillJumpOut",
		"unexpected need-pokemon preview text label"
	)
	_assert(global_fallback_preview.get("status", "") == "ok", "expected global direct fallback preview")
	_assert(global_fallback_preview.get("text_label", "") == "gText_ConfirmSave", "unexpected global fallback text label")
	_assert(global_fallback_preview.get("text_source", "") == "data/text/save.inc", "unexpected global fallback text source")
	_assert(global_fallback_preview.get("text_kind", "") == "text", "unexpected global fallback text kind")
	_assert(global_fallback_preview.get("encoding_status", "") == "ok", "unexpected global fallback encoding status")
	_assert(int(global_fallback_preview.get("source_byte_count", 0)) == 29, "unexpected global fallback byte count")
	_assert(bool(global_fallback_preview.get("terminator_present", false)), "expected global fallback terminator")
	_assert(String(global_fallback_preview.get("text", "")).find("\n") != -1, "expected global fallback display newline")
	_assert(trainer_battle_request.get("status", "") == "sequence_requested", "expected trainer battle sequence request")
	_assert(trainer_battle_sequence.get("battle_kind", "") == "trainer", "expected trainer battle sequence kind")
	_assert(_array_value(trainer_battle_sequence.get("battle_type_flags", [])).has("BATTLE_TYPE_RECORDED_LINK"), "expected recorded-link flag on trainer battle sequence")
	_assert(String(trainer_battle_text_context.get("battle_text_mode", "")) == "recorded_link", "expected recorded-link battle text context on sequence")
	_assert(int(trainer_battle_text_context.get("recorded_text_speed_index", -1)) == 2, "expected recorded text speed index on sequence")
	_assert(trainer_battle_ops.has("clear_mirage_tower_pulse_blend"), "expected trainer battle Mirage Tower cleanup step")
	_assert(trainer_battle_ops.has("restart_wild_encounter_immunity_steps"), "expected trainer battle wild immunity reset step")
	_assert(trainer_battle_ops.has("clear_poison_step_counter"), "expected trainer battle poison step counter clear")
	_assert(
		trainer_battle_ops.find("battle_transition_start") < trainer_battle_ops.find("clear_mirage_tower_pulse_blend"),
		"expected trainer battle cleanup after BattleTransition_StartOnField"
	)
	_assert(
		trainer_battle_ops.find("set_main_callback") < trainer_battle_ops.find("restart_wild_encounter_immunity_steps"),
		"expected trainer battle immunity reset after CB2_InitBattle callback handoff"
	)
	_assert(
		trainer_battle_ops.find("restart_wild_encounter_immunity_steps") < trainer_battle_ops.find("clear_poison_step_counter"),
		"expected trainer battle poison counter clear after immunity reset"
	)
	_assert(player_position_after_coord_dispatch == Vector2i(10, 2), "expected coord dispatch to apply player movement")
	_assert(
		twin_position_after_coord_dispatch == Vector2i(16, 10),
		"expected dispatch to return twin to original cell"
	)
	_assert(
		rival_position_after_object_dispatch == Vector2i(6, 10),
		"expected object-effect dispatch to move rival"
	)
	_assert(
		birch_position_after_object_dispatch == Vector2i(5, 10),
		"expected object-effect dispatch to move Birch"
	)
	_assert(empty_preview.is_empty(), "expected empty script preview for 0x0")
	_assert(not coord_lines.is_empty(), "expected coord dispatch to emit dialogue lines")
	_assert(_lines_contain(coord_lines, "Coord event"), "expected coord event line in emitted output")
	_assert(_lines_contain(coord_lines, "ScriptVM: ok"), "expected VM status in emitted lines")
	_assert(
		_lines_contain(coord_lines, "Movement effects: 4 applied, 0 skipped"),
		"expected movement effect summary in emitted lines"
	)
	_assert(not object_effect_lines.is_empty(), "expected object-effect dispatch to emit lines")
	_assert(
		_lines_contain(object_effect_lines, "Object effects: 2 applied, 0 skipped"),
		"expected object effect summary in emitted lines"
	)
	_assert(game_state.current_map_id == BRENDANS_HOUSE_1F, "expected step-off-truck transition to Brendan house")
	_assert(player_position_after_step_off == Vector2i(8, 8), "expected step-off-truck destination position")
	_assert(runtime.get_map_size() == Vector2i(11, 9), "expected runtime to load Brendan house size")
	_assert(
		typeof(brendan_object_events) == TYPE_ARRAY and runtime.get_object_events(true).size() == brendan_object_events.size(),
		"expected runtime object events to match Brendan house"
	)
	_assert(
		runtime.get_metatile_id_at(Vector2i(5, 4)) == 624,
		"expected Brendan house OnLoad to apply open moving-box metatile"
	)
	_assert(
		runtime.get_collision_at(Vector2i(5, 4)) == 3,
		"expected Brendan house OnLoad open moving-box collision"
	)
	_assert(
		runtime.get_metatile_id_at(Vector2i(5, 2)) == 616,
		"expected Brendan house OnLoad to apply closed moving-box metatile"
	)
	_assert(
		runtime.get_collision_at(Vector2i(5, 2)) == 3,
		"expected Brendan house OnLoad closed moving-box collision"
	)
	_assert(
		brendan_mom_position_after_transition == Vector2i(9, 8),
		"expected Brendan OnTransition to place Mom by the door"
	)
	_assert(
		brendan_mom_movement_after_transition == "MOVEMENT_TYPE_FACE_UP",
		"expected Brendan OnTransition to face Mom upward"
	)
	_assert(not brendan_on_frame_intro_lines.is_empty(), "expected Brendan OnFrame dispatch to emit lines")
	_assert(_lines_contain(brendan_on_frame_intro_lines, "OnFrame map script"), "expected OnFrame dispatch label")
	_assert(_lines_contain(brendan_on_frame_intro_lines, "ScriptVM: ok"), "expected OnFrame VM status line")
	_assert(
		_lines_contain(brendan_on_frame_intro_lines, "Text label: PlayersHouse_1F_Text_IsntItNiceInHere"),
		"expected Brendan OnFrame intro text label in emitted lines"
	)
	_assert(bool(brendan_on_frame_intro.get("matched", false)), "expected Brendan OnFrame intro table match")
	_assert(
		brendan_on_frame_intro.get("selected_script", "") == "LittlerootTown_BrendansHouse_1F_EventScript_EnterHouseMovingIn",
		"unexpected Brendan OnFrame intro script"
	)
	_assert(
		brendan_on_frame_intro.get("status", "") == "ok",
		"expected Brendan intro to run through shared PlayersHouse script"
	)
	_assert(
		typeof(brendan_on_frame_intro_script) == TYPE_DICTIONARY and int(brendan_on_frame_intro_script.get("message_count", 0)) == 2,
		"expected Brendan intro to emit two source messages"
	)
	_assert(
		typeof(brendan_on_frame_intro_script) == TYPE_DICTIONARY and int(brendan_on_frame_intro_script.get("movement_count", 0)) == 4,
		"expected Brendan intro to emit four source movements"
	)
	_assert(
		_movement_summary_count(brendan_on_frame_intro_movements, "applied") == 4,
		"expected Brendan intro runtime to apply four movement effects"
	)
	_assert(
		_movement_summary_count(brendan_on_frame_intro_movements, "skipped") == 0,
		"expected Brendan intro runtime to skip no movement effects"
	)
	_assert(int(brendan_on_frame_intro.get("entry_count", 0)) == 1, "expected first OnFrame entry to match")
	_assert(player_position_after_brendan_intro == Vector2i(8, 7), "expected Brendan intro player walk-in movement")
	_assert(not brendan_mom_by_numeric_local_id.is_empty(), "expected numeric source local-id lookup for Brendan Mom")
	_assert(brendan_intro_mom_local_id == 1, "expected local-id constant to resolve to Mom object id")
	_assert(brendan_intro_gender_value == 0, "expected Brendan intro gender var to be MALE")
	_assert(brendan_intro_state_value == 4, "expected Brendan intro state to advance")
	game_state.set_var("VAR_LITTLEROOT_INTRO_STATE", 5)
	var brendan_on_frame_clock := manager.try_run_on_frame_map_script({
		"trigger": "smoke_on_frame_clock",
		"map": game_state.current_map_id,
	})
	var brendan_on_frame_clock_script = brendan_on_frame_clock.get("script", {})
	_assert(bool(brendan_on_frame_clock.get("matched", false)), "expected Brendan OnFrame clock table match")
	_assert(
		brendan_on_frame_clock.get("selected_script", "") == "LittlerootTown_BrendansHouse_1F_EventScript_GoUpstairsToSetClock",
		"unexpected Brendan OnFrame clock script"
	)
	_assert(brendan_on_frame_clock.get("status", "") == "ok", "expected Brendan clock OnFrame script to run")
	_assert(
		typeof(brendan_on_frame_clock_script) == TYPE_DICTIONARY and int(brendan_on_frame_clock_script.get("message_count", 0)) == 1,
		"expected Brendan clock OnFrame script to emit one message"
	)
	_assert(
		typeof(brendan_on_frame_clock_script) == TYPE_DICTIONARY and int(brendan_on_frame_clock_script.get("movement_count", 0)) == 2,
		"expected Brendan clock OnFrame script to move player and Mom"
	)
	_assert(
		typeof(brendan_on_frame_clock_script) == TYPE_DICTIONARY and int(brendan_on_frame_clock_script.get("transition_effect_count", 0)) == 1,
		"expected Brendan clock OnFrame script to record upstairs warp"
	)
	_assert(game_state.current_map_id == BRENDANS_HOUSE_2F, "expected Brendan clock OnFrame to load Brendan house 2F")
	_assert(game_state.player_grid_position == Vector2i(7, 1), "expected Brendan clock warp explicit upstairs position")
	_configure_map_fixture(registry, runtime, manager, game_state, BRENDANS_HOUSE_1F, Vector2i(8, 8))
	game_state.set_var("VAR_LITTLEROOT_INTRO_STATE", 3)
	_assert(not transition_lines.is_empty(), "expected transition dispatch to emit lines")
	_assert(
		_lines_contain(transition_lines, "Transition effects: 1 applied, 0 skipped"),
		"expected transition effect summary in emitted lines"
	)
	_assert(truck_transition_sequence.get("presentation", "") == "silent", "expected truck warp silent presentation")
	_assert(
		_step_ops(truck_transition_sequence) == [
			"lock_controls",
			"fade_out",
			"load_map",
			"fade_in",
			"exit_task_select",
			"conditional_exit_door_player_step",
			"unlock_controls",
		],
		"unexpected normal transition sequence steps"
	)
	_assert(String(truck_exit_task.get("task", "")) == "Task_ExitNonDoor", "expected truck warp exit task")
	_assert(String(truck_exit_task.get("behavior_name", "")) == "MB_SOUTH_ARROW_WARP", "expected truck destination behavior")
	_assert(
		String(truck_exit_step.get("selected", "")) == String(truck_exit_task.get("task", "")),
		"expected truck exit step to record selected task"
	)
	_assert(not bool(truck_conditional_step.get("condition_result", true)), "expected no truck exit-door player step")
	_assert(house_script_result.get("status", "") == "ok", "expected transitioned script data to run Brendan house script")
	_assert(old_map_script_result.get("status", "") == "ok", "expected generated script labels to remain globally available")

	captured.clear()
	captured_sequences.clear()
	var brendan_exit_warp := runtime.get_warp_event_target(Vector2i(8, 8))
	manager.dispatch_interaction(brendan_exit_warp)
	var map_warp_lines = captured.get("lines", PackedStringArray())
	var map_warp_sequence = captured_sequences[0] if captured_sequences.size() > 0 else {}
	var map_warp_exit_task := _exit_task(map_warp_sequence)
	var map_warp_exit_step := _first_step(map_warp_sequence, "exit_task_select")
	var map_warp_conditional_step := _first_step(map_warp_sequence, "conditional_exit_door_player_step")
	var town_script_result := manager.run_script("LittlerootTown_EventScript_Twin")
	var current_map_after_map_warp: String = game_state.current_map_id
	_assert(brendan_exit_warp.get("type", "") == "warp_event", "expected Brendan house exit warp")
	_assert(game_state.current_map_id == START_MAP, "expected map warp to return to LittlerootTown")
	_assert(game_state.player_grid_position == Vector2i(5, 8), "expected map warp to use destination warp-id coordinates")
	_assert(runtime.get_map_size() == Vector2i(20, 20), "expected runtime to reload town size")
	_assert(not map_warp_lines.is_empty(), "expected map-warp dispatch to emit lines")
	_assert(
		_lines_contain(map_warp_lines, "Warp effects: 1 applied, 0 skipped"),
		"expected map warp effect summary in emitted lines"
	)
	_assert(map_warp_sequence.get("presentation", "") == "normal", "expected step map warp normal presentation")
	_assert(_step_ops(map_warp_sequence).has("exit_task_select"), "expected normal map warp exit task step")
	_assert(String(map_warp_exit_task.get("task", "")) == "Task_ExitDoor", "expected town destination exit door task")
	_assert(String(map_warp_exit_task.get("behavior_name", "")) == "MB_ANIMATED_DOOR", "expected town destination door behavior")
	_assert(
		String(map_warp_exit_step.get("selected", "")) == String(map_warp_exit_task.get("task", "")),
		"expected map warp exit step to record selected task"
	)
	_assert(bool(map_warp_conditional_step.get("condition_result", false)), "expected town destination exit-door player step")
	_assert(town_script_result.get("status", "") == "ok", "expected town script data after map warp")

	captured.clear()
	captured_sequences.clear()
	game_state.player_grid_position = Vector2i(14, 9)
	var may_house_door_warp := runtime.get_warp_event_target(Vector2i(14, 8))
	may_house_door_warp["presentation"] = {
		"kind": "door",
		"entry_direction": "up",
		"source_position": [14, 9],
		"trigger_position": [14, 8],
	}
	manager.dispatch_interaction(may_house_door_warp)
	var door_warp_sequence = captured_sequences[0] if captured_sequences.size() > 0 else {}
	var door_open_step := _first_step(door_warp_sequence, "door_open")
	var door_close_step := _first_step(door_warp_sequence, "door_close")
	var door_play_se_step := _first_step(door_warp_sequence, "play_se")
	var door_player_step := _first_step(door_warp_sequence, "player_step")
	var door_exit_task := _exit_task(door_warp_sequence)
	var door_exit_step := _first_step(door_warp_sequence, "exit_task_select")
	var conditional_door_step := _first_step(door_warp_sequence, "conditional_exit_door_player_step")
	var door_open_animation = door_open_step.get("animation", {})
	var current_map_after_may_warp := String(game_state.current_map_id)
	var may_open_box_metatile_after_warp := runtime.get_metatile_id_at(Vector2i(5, 4))
	var may_closed_box_metatile_after_warp := runtime.get_metatile_id_at(Vector2i(5, 2))
	var may_mom_after_door_warp := runtime.get_object_event_by_local_id("LOCALID_PLAYERS_HOUSE_1F_MOM", true)
	var may_mom_position_after_door_warp := _event_position(may_mom_after_door_warp)
	var may_mom_movement_after_door_warp := String(may_mom_after_door_warp.get("movement_type", ""))
	var player_position_after_may_warp: Vector2i = game_state.player_grid_position
	game_state.set_var("VAR_LITTLEROOT_INTRO_STATE", 3)
	var may_on_frame_intro := manager.dispatch_on_frame_map_script({
		"trigger": "smoke_on_frame_intro",
		"map": game_state.current_map_id,
	})
	var may_on_frame_intro_lines = captured.get("lines", PackedStringArray())
	var may_on_frame_intro_script = may_on_frame_intro.get("script", {})
	var may_on_frame_intro_runtime = may_on_frame_intro.get("runtime", {})
	var may_on_frame_intro_movements = may_on_frame_intro_runtime.get("movements", {}) if typeof(may_on_frame_intro_runtime) == TYPE_DICTIONARY else {}
	var player_position_after_may_intro: Vector2i = game_state.player_grid_position
	var may_intro_mom_local_id := game_state.get_var("VAR_0x8004", -1)
	var may_intro_gender_value := game_state.get_var("VAR_0x8005", -1)
	var may_intro_state_value := game_state.get_var("VAR_LITTLEROOT_INTRO_STATE", -1)
	game_state.set_var("VAR_LITTLEROOT_INTRO_STATE", 5)
	var may_on_frame_clock := manager.try_run_on_frame_map_script({
		"trigger": "smoke_on_frame_clock",
		"map": game_state.current_map_id,
	})
	var may_on_frame_clock_script = may_on_frame_clock.get("script", {})
	_assert(may_house_door_warp.get("type", "") == "warp_event", "expected May house door warp")
	_assert(current_map_after_may_warp == MAYS_HOUSE_1F, "expected door warp to load May house")
	_assert(
		may_open_box_metatile_after_warp == 624,
		"expected May house OnLoad to apply open moving-box metatile"
	)
	_assert(
		may_closed_box_metatile_after_warp == 616,
		"expected May house OnLoad to apply closed moving-box metatile"
	)
	_assert(
		may_mom_position_after_door_warp == Vector2i(1, 8),
		"expected May OnTransition to place Mom by the door"
	)
	_assert(
		may_mom_movement_after_door_warp == "MOVEMENT_TYPE_FACE_UP",
		"expected May OnTransition to face Mom upward"
	)
	_assert(player_position_after_may_warp == Vector2i(2, 8), "expected May house door warp destination position")
	_assert(not may_on_frame_intro_lines.is_empty(), "expected May OnFrame dispatch to emit lines")
	_assert(_lines_contain(may_on_frame_intro_lines, "OnFrame map script"), "expected May OnFrame dispatch label")
	_assert(_lines_contain(may_on_frame_intro_lines, "ScriptVM: ok"), "expected May OnFrame VM status line")
	_assert(
		_lines_contain(may_on_frame_intro_lines, "Text label: PlayersHouse_1F_Text_IsntItNiceInHere"),
		"expected May OnFrame intro text label in emitted lines"
	)
	_assert(bool(may_on_frame_intro.get("matched", false)), "expected May OnFrame intro table match")
	_assert(
		may_on_frame_intro.get("selected_script", "") == "LittlerootTown_MaysHouse_1F_EventScript_EnterHouseMovingIn",
		"unexpected May OnFrame intro script"
	)
	_assert(may_on_frame_intro.get("status", "") == "ok", "expected May intro OnFrame script to run")
	_assert(
		typeof(may_on_frame_intro_script) == TYPE_DICTIONARY and int(may_on_frame_intro_script.get("message_count", 0)) == 2,
		"expected May intro OnFrame script to emit two messages"
	)
	_assert(
		typeof(may_on_frame_intro_script) == TYPE_DICTIONARY and int(may_on_frame_intro_script.get("movement_count", 0)) == 4,
		"expected May intro OnFrame script to move player and Mom"
	)
	_assert(
		_movement_summary_count(may_on_frame_intro_movements, "applied") == 4,
		"expected May intro runtime to apply four movement effects"
	)
	_assert(
		_movement_summary_count(may_on_frame_intro_movements, "skipped") == 0,
		"expected May intro runtime to skip no movement effects"
	)
	_assert(player_position_after_may_intro == Vector2i(2, 7), "expected May intro player walk-in movement")
	_assert(may_intro_mom_local_id == 1, "expected May local-id constant to resolve to Mom object id")
	_assert(may_intro_gender_value == 1, "expected May intro gender var to be FEMALE")
	_assert(may_intro_state_value == 4, "expected May intro state to advance")
	_assert(bool(may_on_frame_clock.get("matched", false)), "expected May OnFrame clock table match")
	_assert(
		may_on_frame_clock.get("selected_script", "") == "LittlerootTown_MaysHouse_1F_EventScript_GoUpstairsToSetClock",
		"unexpected May OnFrame clock script"
	)
	_assert(may_on_frame_clock.get("status", "") == "ok", "expected May clock OnFrame script to run")
	_assert(
		typeof(may_on_frame_clock_script) == TYPE_DICTIONARY and int(may_on_frame_clock_script.get("message_count", 0)) == 1,
		"expected May clock OnFrame script to emit one message"
	)
	_assert(
		typeof(may_on_frame_clock_script) == TYPE_DICTIONARY and int(may_on_frame_clock_script.get("movement_count", 0)) == 2,
		"expected May clock OnFrame script to move player and Mom"
	)
	_assert(
		typeof(may_on_frame_clock_script) == TYPE_DICTIONARY and int(may_on_frame_clock_script.get("transition_effect_count", 0)) == 1,
		"expected May clock OnFrame script to record upstairs warp"
	)
	_assert(game_state.current_map_id == MAYS_HOUSE_2F, "expected May clock OnFrame to load May house 2F")
	_assert(game_state.player_grid_position == Vector2i(1, 1), "expected May clock warp explicit upstairs position")
	_assert(door_warp_sequence.get("presentation", "") == "door", "expected door presentation sequence")
	_assert(
		_step_ops(door_warp_sequence) == [
			"lock_controls",
			"freeze_object_events",
			"play_se",
			"door_open",
			"player_step",
			"hide_player",
			"door_close",
			"fade_out",
			"load_map",
			"fade_in",
			"exit_task_select",
			"conditional_exit_door_player_step",
			"unlock_controls",
		],
		"unexpected door transition sequence steps"
	)
	_assert(String(door_play_se_step.get("sound", "")) == "SE_DOOR", "expected source door sound effect")
	_assert(String(door_play_se_step.get("sound_source", "")) == "GetDoorSoundEffect", "expected door sound source")
	_assert(int(door_open_step.get("duration_frames", 0)) == 16, "expected source door open to last 16 frames")
	_assert(int(door_close_step.get("duration_frames", 0)) == 16, "expected source door close to last 16 frames")
	_assert(door_open_step.get("frame_indices", []) == [-1, 0, 1, 2], "expected source door open frame order")
	_assert(door_close_step.get("frame_indices", []) == [2, 1, 0, -1], "expected source door close frame order")
	_assert(
		typeof(door_open_animation) == TYPE_DICTIONARY and int(door_open_animation.get("metatile_id", -1)) == 584,
		"expected door open step to include Littleroot door animation"
	)
	_assert(
		String(door_open_animation.get("image", "")).ends_with("littleroot_town_littleroot.png"),
		"expected door open step to include generated door frame atlas"
	)
	_assert(int(door_player_step.get("duration_frames", 0)) == 16, "expected source normal walk step to last 16 frames")
	_assert(String(door_exit_task.get("task", "")) == "Task_ExitNonDoor", "expected May house destination non-door exit task")
	_assert(String(door_exit_task.get("behavior_name", "")) == "MB_SOUTH_ARROW_WARP", "expected May house destination behavior")
	_assert(
		String(door_exit_step.get("selected", "")) == String(door_exit_task.get("task", "")),
		"expected door warp exit step to record selected task"
	)
	_assert(not bool(conditional_door_step.get("condition_result", true)), "expected no exit-door step on May house south-arrow warp")

	var connection_vm = SCRIPT_VM_SCRIPT.new()
	connection_vm.configure_from_script_data(script_data)
	var connection_runtime = MAP_RUNTIME_SCRIPT.new()
	connection_runtime.configure_data_registry(registry)
	connection_runtime.configure_from_data(map_data, tileset_data, _map_size_from_data(map_data))
	var connection_game_state = GAME_STATE_SCRIPT.new()
	connection_game_state.current_map_id = START_MAP
	connection_game_state.player_grid_position = Vector2i(10, 0)
	var connection_manager = EVENT_MANAGER_SCRIPT.new()
	connection_manager.configure_from_script_data(script_data)
	connection_manager.configure_script_vm(connection_vm)
	connection_manager.configure_map_runtime(connection_runtime)
	connection_manager.configure_game_state(connection_game_state)
	connection_manager.configure_data_registry(registry)
	var connection_captured := {}
	var connection_sequences := []
	connection_manager.debug_message_requested.connect(func(lines: PackedStringArray) -> void:
		connection_captured["lines"] = lines
	)
	connection_manager.transition_sequence_requested.connect(func(sequence: Dictionary) -> void:
		connection_sequences.append(sequence)
	)
	var littleroot_north_connection := connection_runtime.get_connection_target(Vector2i(10, -1))
	connection_manager.dispatch_interaction(littleroot_north_connection)
	var connection_lines = connection_captured.get("lines", PackedStringArray())
	var connection_sequence = connection_sequences[0] if connection_sequences.size() > 0 else {}
	_assert(littleroot_north_connection.get("type", "") == "map_connection", "expected Littleroot north connection target")
	_assert(connection_game_state.current_map_id == "MAP_ROUTE101", "expected connection to load Route101")
	_assert(connection_game_state.player_grid_position == Vector2i(10, 19), "expected Route101 south-edge destination")
	_assert(connection_runtime.get_map_size() == Vector2i(20, 20), "expected Route101 runtime size")
	_assert(not connection_lines.is_empty(), "expected connection dispatch to emit lines")
	_assert(_lines_contain(connection_lines, "Map connection"), "expected map connection emitted line")
	_assert(
		_lines_contain(connection_lines, "Connection effects: 1 applied, 0 skipped"),
		"expected map connection transition effect summary"
	)
	_assert(connection_sequence.get("presentation", "") == "connection", "expected connection presentation")
	var connection_step := _first_step(connection_sequence, "player_step")
	_assert(int(connection_step.get("duration_frames", 0)) == 16, "expected connection edge step to last 16 frames")
	_assert(_vector_from_value(connection_step.get("from", Vector2i.ZERO)) == Vector2i(10, 0), "expected connection step from north edge source cell")
	_assert(_vector_from_value(connection_step.get("to", Vector2i.ZERO)) == Vector2i(10, -1), "expected connection step to trigger cell")
	_assert(_has_unsupported(connection_sequence, "map_connection_camera_backup_not_source_equivalent"), "expected connection camera backup unsupported note")
	_assert(
		_step_ops(connection_sequence) == ["lock_controls", "player_step", "load_map", "unlock_controls"],
		"unexpected connection transition sequence steps"
	)

	print(JSON.stringify({
		"event_manager_smoke": "ok",
		"twin": _preview_summary(twin_preview),
		"town_sign": _preview_summary(sign_preview),
		"need_pokemon": _preview_summary(need_pokemon_preview),
		"global_fallback": _preview_summary(global_fallback_preview),
		"player_position_after_coord_dispatch": _vector_to_array(player_position_after_coord_dispatch),
		"current_map_after_transition": BRENDANS_HOUSE_1F,
		"current_map_after_map_warp": current_map_after_map_warp,
		"truck_exit_task": truck_exit_task,
		"map_warp_exit_task": map_warp_exit_task,
		"door_exit_task": door_exit_task,
		"door_sequence_ops": _step_ops(door_warp_sequence),
		"connection_sequence_ops": _step_ops(connection_sequence),
		"trainer_battle_text_mode": String(trainer_battle_text_context.get("battle_text_mode", "")),
		"rival_position_after_object_dispatch": _vector_to_array(rival_position_after_object_dispatch),
	}))
	connection_manager.free()
	connection_game_state.free()
	connection_runtime.free()
	connection_vm.free()
	party_runtime.free()
	battle_engine.free()
	manager.free()
	fallback_manager.free()
	game_state.free()
	runtime.free()
	vm.free()
	registry.free()
	quit(0)


func _configure_map_fixture(registry: Node, runtime: Node, manager: Node, game_state: Node, map_id: String, position: Vector2i) -> void:
	var map_data: Dictionary = registry.get_map_data(map_id)
	var tileset_data: Dictionary = registry.get_tileset_data_for_map(map_id)
	var script_data: Dictionary = registry.get_script_data_for_map(map_id)
	runtime.configure_from_data(map_data, tileset_data, registry.get_map_size(map_id))
	manager.configure_from_script_data(script_data)
	game_state.current_map_id = map_id
	runtime.set_player_grid_position(position, game_state)


func _load_json_object(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Could not open %s" % path)
		quit(1)
		return {}

	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("%s is not a JSON object" % path)
		quit(1)
		return {}

	return parsed


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	quit(1)


func _preview_summary(preview: Dictionary) -> Dictionary:
	return {
		"script_label": String(preview.get("script_label", "")),
		"text_label": String(preview.get("text_label", "")),
		"mode": String(preview.get("mode", "")),
		"vm_status": String(preview.get("vm_status", "")),
		"text_length": String(preview.get("text", "")).length(),
	}


func _lines_contain(lines: PackedStringArray, needle: String) -> bool:
	for line in lines:
		if line == needle:
			return true
	return false


func _step_ops(sequence: Dictionary) -> Array:
	var ops := []
	var steps = sequence.get("steps", [])
	if typeof(steps) != TYPE_ARRAY:
		return ops
	for step in steps:
		if typeof(step) == TYPE_DICTIONARY:
			ops.append(String(step.get("op", "")))
	return ops


func _dict_value(value) -> Dictionary:
	return value if typeof(value) == TYPE_DICTIONARY else {}


func _array_value(value) -> Array:
	return value if typeof(value) == TYPE_ARRAY else []


func _first_step(sequence: Dictionary, op: String) -> Dictionary:
	var steps = sequence.get("steps", [])
	if typeof(steps) != TYPE_ARRAY:
		return {}
	for step in steps:
		if typeof(step) == TYPE_DICTIONARY and String(step.get("op", "")) == op:
			return step
	return {}


func _exit_task(sequence: Dictionary) -> Dictionary:
	var exit_task = sequence.get("exit_task", {})
	return exit_task if typeof(exit_task) == TYPE_DICTIONARY else {}


func _has_unsupported(record: Dictionary, code: String) -> bool:
	var unsupported = record.get("unsupported", [])
	if typeof(unsupported) != TYPE_ARRAY:
		return false
	for item in unsupported:
		if typeof(item) == TYPE_DICTIONARY and String(item.get("code", "")) == code:
			return true
	return false


func _map_size_from_data(map_data: Dictionary) -> Vector2i:
	var layout_info = map_data.get("layout", {})
	if typeof(layout_info) != TYPE_DICTIONARY:
		return Vector2i.ZERO
	return Vector2i(
		int(layout_info.get("width", 0)),
		int(layout_info.get("height", 0))
	)


func _event_position(object_event: Dictionary) -> Vector2i:
	var position = object_event.get("position", Vector2i.ZERO)
	if typeof(position) == TYPE_VECTOR2I:
		return position
	return Vector2i(
		int(object_event.get("x", 0)),
		int(object_event.get("y", 0))
	)


func _vector_to_array(value: Vector2i) -> Array:
	return [value.x, value.y]


func _vector_from_value(value) -> Vector2i:
	if typeof(value) == TYPE_VECTOR2I:
		return value
	if typeof(value) == TYPE_ARRAY and value.size() >= 2:
		return Vector2i(int(value[0]), int(value[1]))
	if typeof(value) == TYPE_DICTIONARY:
		return Vector2i(int(value.get("x", 0)), int(value.get("y", 0)))
	return Vector2i.ZERO


func _movement_summary_count(summary: Dictionary, key: String) -> int:
	var items = summary.get(key, [])
	return items.size() if typeof(items) == TYPE_ARRAY else 0
