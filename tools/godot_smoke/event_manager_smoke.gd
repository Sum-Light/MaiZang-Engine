extends SceneTree

const EVENT_MANAGER_SCRIPT := preload("res://scripts/autoload/event_manager.gd")
const SCRIPT_VM_SCRIPT := preload("res://scripts/autoload/script_vm.gd")
const MAP_RUNTIME_SCRIPT := preload("res://scripts/autoload/map_runtime.gd")
const GAME_STATE_SCRIPT := preload("res://scripts/autoload/game_state.gd")
const DATA_REGISTRY_SCRIPT := preload("res://scripts/autoload/data_registry.gd")
const START_MAP := "MAP_LITTLEROOT_TOWN"
const BRENDANS_HOUSE_1F := "MAP_LITTLEROOT_TOWN_BRENDANS_HOUSE_1F"
const MAYS_HOUSE_1F := "MAP_LITTLEROOT_TOWN_MAYS_HOUSE_1F"


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
	runtime.configure_from_data(map_data, tileset_data, _map_size_from_data(map_data))
	var game_state = GAME_STATE_SCRIPT.new()
	var manager = EVENT_MANAGER_SCRIPT.new()
	manager.configure_from_script_data(script_data)
	manager.configure_script_vm(vm)
	manager.configure_map_runtime(runtime)
	manager.configure_game_state(game_state)
	manager.configure_data_registry(registry)

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
	var house_script_result := manager.run_script("LittlerootTown_BrendansHouse_1F_EventScript_MoveMomToDoor")
	var old_map_script_result := manager.run_script("LittlerootTown_EventScript_Twin")
	var brendan_map_data: Dictionary = registry.get_map_data(BRENDANS_HOUSE_1F)
	var brendan_object_events = brendan_map_data.get("events", {}).get("object_events", [])

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
	_assert(game_state.player_grid_position == Vector2i(8, 8), "expected step-off-truck destination position")
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
	_assert(old_map_script_result.get("status", "") == "missing_script", "expected old map script to be unavailable after transition")

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
	_assert(may_house_door_warp.get("type", "") == "warp_event", "expected May house door warp")
	_assert(game_state.current_map_id == MAYS_HOUSE_1F, "expected door warp to load May house")
	_assert(
		runtime.get_metatile_id_at(Vector2i(5, 4)) == 624,
		"expected May house OnLoad to apply open moving-box metatile"
	)
	_assert(
		runtime.get_metatile_id_at(Vector2i(5, 2)) == 616,
		"expected May house OnLoad to apply closed moving-box metatile"
	)
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
		"rival_position_after_object_dispatch": _vector_to_array(rival_position_after_object_dispatch),
	}))
	manager.free()
	fallback_manager.free()
	game_state.free()
	runtime.free()
	vm.free()
	registry.free()
	quit(0)


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
