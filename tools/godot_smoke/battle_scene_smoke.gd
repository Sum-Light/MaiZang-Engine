extends SceneTree

const DATA_REGISTRY_SCRIPT := preload("res://scripts/autoload/data_registry.gd")
const BATTLE_ENGINE_SCRIPT := preload("res://scripts/autoload/battle_engine.gd")
const BATTLE_SCENE := preload("res://scenes/battle/battle_scene.tscn")

var _failed := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var registry = DATA_REGISTRY_SCRIPT.new()
	registry._ready()

	var engine = BATTLE_ENGINE_SCRIPT.new()
	engine.configure_registry(registry)

	var mudkip := engine.create_battle_mon("SPECIES_MUDKIP", 30, {
		"moves": ["MOVE_WATER_GUN", "MOVE_TACKLE"],
	})
	var battle_state := engine.create_trainer_battle_state("TRAINER_SAWYER_1", [mudkip], {
		"map_transition_type": "normal",
	})
	_assert(String(battle_state.get("status", "")) == "ok", "expected trainer battle state for scene")

	var scene = BATTLE_SCENE.instantiate()
	scene.configure_battle_engine(engine)
	scene.configure_data_registry(registry)
	get_root().add_child(scene)
	await create_timer(0.05).timeout
	scene.load_battle_state(battle_state)
	await create_timer(0.05).timeout

	var intro: Dictionary = scene.get_ui_snapshot()
	_assert(not String(intro.get("player_name", "")).is_empty(), "expected player name label")
	_assert(not String(intro.get("opponent_name", "")).is_empty(), "expected opponent name label")
	_assert(String(intro.get("player_hp", "")).begins_with("HP "), "expected player HP label")
	_assert(String(intro.get("opponent_hp", "")) == "HP", "expected opponent source healthbox HP label")
	_assert(String(intro.get("message", "")).contains("wants to battle"), "expected trainer intro message")
	_assert(String(intro.get("ui_phase", "")) == "intro_message", "expected intro phase")
	_assert(String(intro.get("source_string_id", "")) == "STRINGID_INTROMSG", "expected trainer intro string id metadata")
	_assert(_array_value(intro.get("visible_source_windows", [])).has("B_WIN_MSG"), "expected message window visible in intro")
	_assert(_array_value(intro.get("viewport_size", [])) == [240, 160], "expected 240x160 battle viewport metadata")
	_assert(
		String(intro.get("presentation_status", "")) == "first_slice_not_source_equivalent",
		"expected battle scene to expose non-source-equivalent status"
	)
	_assert(String(intro.get("source_flow_status", "")) == "source_action_move_window_flow_first_pass", "expected source flow metadata")
	_assert(intro.get("source_hp_bar_pixels", 0) == 48, "expected source HP bar pixel width")
	var source_assets := _dict_value(intro.get("source_ui_assets", {}))
	_assert(String(source_assets.get("textbox_tiles", "")) == "graphics/battle_interface/textbox.png", "expected source textbox asset metadata")
	_assert(String(source_assets.get("healthbox_singles_player", "")) == "graphics/battle_interface/healthbox_singles_player.png", "expected source healthbox asset metadata")
	var window_text_info := _dict_value(intro.get("source_window_text_info", {}))
	var pp_remaining_info := _dict_value(window_text_info.get("B_WIN_PP_REMAINING", {}))
	var pp_text_color := _dict_value(pp_remaining_info.get("text_color", {}))
	_assert(int(pp_text_color.get("foreground", -1)) == 12, "expected source PP remaining foreground color")
	_assert(int(pp_text_color.get("shadow", -1)) == 11, "expected source PP remaining shadow color")
	var type_display_status := _dict_value(intro.get("source_type_display_status", {}))
	_assert(String(type_display_status.get("status", "")) == "available", "expected generated source type names available")
	_assert(String(type_display_status.get("sample_type_water_name", "")) == "水", "expected source TYPE_WATER display name")
	var healthbox_coords := _dict_value(intro.get("source_healthbox_coords", {}))
	var singles_coords := _dict_value(healthbox_coords.get("singles", {}))
	_assert(_array_value(singles_coords.get("player_left", [])) == [158, 88], "expected source player healthbox coord")
	_assert(_array_value(singles_coords.get("opponent_left", [])) == [44, 30], "expected source opponent healthbox coord")

	var intro_advance: Dictionary = scene.advance_intro()
	_assert(String(intro_advance.get("status", "")) == "ok", "expected intro advance")
	await create_timer(0.05).timeout
	var action_select: Dictionary = scene.get_ui_snapshot()
	_assert(String(action_select.get("ui_phase", "")) == "action_select", "expected action select phase")
	_assert(_array_value(action_select.get("visible_source_windows", [])).has("B_WIN_ACTION_PROMPT"), "expected action prompt window")
	_assert(_array_value(action_select.get("visible_source_windows", [])).has("B_WIN_ACTION_MENU"), "expected action menu window")
	var action_ids := _dict_value(action_select.get("source_action_ids", {}))
	_assert(String(action_ids.get("fight", "")) == "B_ACTION_USE_MOVE", "expected Fight action id")
	_assert(String(action_ids.get("party", "")) == "B_ACTION_SWITCH", "expected Pokemon action id")
	_assert(String(action_ids.get("bag", "")) == "B_ACTION_USE_ITEM", "expected Bag action id")
	_assert(String(action_ids.get("run", "")) == "B_ACTION_RUN", "expected Run action id")
	_assert(String(action_select.get("action_prompt", "")).contains("要做什么呢"), "expected source action prompt text")

	var fight_result: Dictionary = scene.select_action("fight")
	_assert(String(fight_result.get("status", "")) == "ok", "expected Fight action selection")
	await create_timer(0.05).timeout
	var move_select: Dictionary = scene.get_ui_snapshot()
	var move_windows := _array_value(move_select.get("visible_source_windows", []))
	for window_id in ["B_WIN_MOVE_NAME_1", "B_WIN_MOVE_NAME_2", "B_WIN_MOVE_NAME_3", "B_WIN_MOVE_NAME_4", "B_WIN_PP", "B_WIN_PP_REMAINING", "B_WIN_MOVE_TYPE"]:
		_assert(move_windows.has(window_id), "expected move-select window %s" % window_id)
	var move_labels := _array_value(move_select.get("moves", []))
	_assert(move_labels.size() == 4, "expected four move name slots")
	_assert(not String(move_labels[0]).is_empty(), "expected first move name")
	_assert(String(move_select.get("pp_label", "")) == "PP", "expected PP label")
	_assert(String(move_select.get("pp_remaining", "")).contains("25/25"), "expected first move PP before turn")
	_assert(String(move_select.get("move_type", "")).contains("水"), "expected source TYPE_WATER display name")
	_assert(not String(move_select.get("move_type", "")).contains("TYPE_WATER"), "expected move type label to use generated source type names")

	var turn_result: Dictionary = scene.play_player_move(0)
	await create_timer(0.05).timeout
	var after: Dictionary = scene.get_ui_snapshot()
	var result_contract: Dictionary = scene.get_battle_result()
	_assert(String(turn_result.get("status", "")) == "ok", "expected scene move turn")
	_assert(int(_dict_value(turn_result.get("battle_state", {})).get("turn", 0)) == 1, "expected one source-shaped player turn")
	_assert(String(result_contract.get("outcome", "")) == "player_won", "expected scene result outcome")
	_assert(_has_unsupported(result_contract, "battle_scene_not_source_equivalent"), "expected battle scene source-equivalence unsupported note")
	_assert(_has_unsupported(result_contract, "battle_turn_loop_first_slice"), "expected battle turn loop unsupported note")
	_assert(_has_unsupported(result_contract, "battle_ui_windows_not_source_equivalent"), "expected source window unsupported note")
	_assert(_has_source_trace(result_contract, "src/battle_main.c:HandleTurnActionSelectionState"), "expected action selection source trace")
	var turn_opponent_party := _array_value(_dict_value(turn_result.get("battle_state", {})).get("opponent_party", []))
	var opponent_after_turn := _dict_value(turn_opponent_party[0]) if not turn_opponent_party.is_empty() else {}
	_assert(int(opponent_after_turn.get("hp", -1)) == 0, "expected opponent HP to reach zero")
	var turn_player_party := _array_value(_dict_value(turn_result.get("battle_state", {})).get("player_party", []))
	var player_after_turn := _dict_value(turn_player_party[0]) if not turn_player_party.is_empty() else {}
	var moves_after_turn := _array_value(player_after_turn.get("moves", []))
	var used_move := _dict_value(moves_after_turn[0]) if not moves_after_turn.is_empty() else {}
	_assert(String(used_move.get("symbol", "")) == "MOVE_WATER_GUN", "expected first move symbol")
	_assert(int(used_move.get("current_pp", -1)) == 24, "expected first move PP after turn")
	_assert(String(after.get("message", "")).contains("You won the battle."), "expected win message")
	_assert(bool(after.get("can_return_to_field", false)), "expected final outcome can return to field")

	if _failed:
		return

	print(JSON.stringify({
		"battle_scene_smoke": "ok",
		"outcome": String(result_contract.get("outcome", "")),
		"opponent_hp": String(after.get("opponent_hp", "")),
	}))
	scene.queue_free()
	engine.free()
	registry.free()
	quit(0)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true
	quit(1)


func _array_value(value) -> Array:
	return value if typeof(value) == TYPE_ARRAY else []


func _dict_value(value) -> Dictionary:
	return value if typeof(value) == TYPE_DICTIONARY else {}


func _has_unsupported(record: Dictionary, code: String) -> bool:
	var unsupported = record.get("unsupported", [])
	if typeof(unsupported) != TYPE_ARRAY:
		return false
	for item in unsupported:
		if typeof(item) == TYPE_DICTIONARY and String(item.get("code", "")) == code:
			return true
	return false


func _has_source_trace(record: Dictionary, trace: String) -> bool:
	var source_trace = record.get("source_trace", [])
	return typeof(source_trace) == TYPE_ARRAY and source_trace.has(trace)
