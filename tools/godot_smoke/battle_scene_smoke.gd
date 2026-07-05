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
	_assert(not _contains_forbidden_runtime_color_key(intro), "battle scene runtime snapshot must not expose palette/source-color keys")
	var source_assets := _dict_value(intro.get("source_ui_assets", {}))
	_assert(String(source_assets.get("textbox_texture_source", "")) == "graphics/battle_interface/textbox.png", "expected source textbox asset metadata")
	_assert(String(source_assets.get("render_style_policy", "")) == "godot_theme_material_shader", "expected Godot-native render style policy")
	_assert(String(source_assets.get("healthbox_singles_player", "")) == "graphics/battle_interface/healthbox_singles_player.png", "expected source healthbox asset metadata")
	var intro_renderer := _dict_value(intro.get("source_window_renderer", {}))
	_assert(String(intro.get("source_window_renderer_status", "")) == "first_pass", "expected source window renderer status")
	_assert(String(intro_renderer.get("runtime_color_policy", "")) == "rgba_textures_and_godot_materials", "expected renderer RGBA/material policy")
	_assert(String(intro_renderer.get("source_composite_mapping_status", "")) == "generated_window_template_rects", "expected generated renderer composite rect mapping metadata")
	_assert(_array_value(intro_renderer.get("visible_windows", [])).has("B_WIN_MSG"), "expected renderer message window in intro")
	var source_texts := _dict_value(intro.get("source_text_symbols", {}))
	_assert(String(_dict_value(source_texts.get("gText_BattleMenu", {})).get("status", "")) == "generated", "expected generated battle menu text")
	_assert(String(_dict_value(source_texts.get("gText_WhatWillPkmnDo", {})).get("status", "")) == "generated", "expected generated action prompt text")
	var window_text_info := _dict_value(intro.get("source_window_text_info", {}))
	var pp_remaining_info := _dict_value(window_text_info.get("B_WIN_PP_REMAINING", {}))
	_assert(String(pp_remaining_info.get("text_material_id", "")) == "battle_pp_numeric", "expected semantic PP text material")
	_assert(String(pp_remaining_info.get("fill_style", "")) == "menu_panel", "expected semantic PP fill style")
	_assert(String(pp_remaining_info.get("source_status", "")) == "generated_from_sTextOnWindowsInfo_Normal", "expected generated PP text info")
	var message_text_info := _dict_value(window_text_info.get("B_WIN_MSG", {}))
	_assert(String(message_text_info.get("speed", "")) == "player_text_speed_delay", "expected generated message text speed source")
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
	_assert(not _contains_forbidden_runtime_color_key(action_select), "action-select snapshot must not expose palette/source-color keys")
	var action_renderer := _dict_value(action_select.get("source_window_renderer", {}))
	var action_renderer_windows := _dict_value(action_renderer.get("windows", {}))
	var action_prompt_window := _dict_value(action_renderer_windows.get("B_WIN_ACTION_PROMPT", {}))
	var action_menu_window := _dict_value(action_renderer_windows.get("B_WIN_ACTION_MENU", {}))
	_assert(_array_value(action_renderer.get("visible_windows", [])).has("B_WIN_ACTION_PROMPT"), "expected renderer action prompt window")
	_assert(_array_value(action_renderer.get("visible_windows", [])).has("B_WIN_ACTION_MENU"), "expected renderer action menu window")
	var action_prompt_printer := _dict_value(action_prompt_window.get("text_printer", {}))
	_assert(String(action_prompt_printer.get("event_stream_source", "")) == "source_text", "expected action prompt source-text event stream")
	_assert(String(action_prompt_printer.get("source_text_label", "")) == "gText_WhatWillPkmnDo", "expected action prompt source text label")
	_assert(String(action_prompt_printer.get("source_text", "")).find("{B_BUFF1}") < 0, "expected action prompt source placeholder substitution")
	_assert(_array_value(action_menu_window.get("screen_rect", [])) == [136, 120, 96, 32], "expected renderer action menu screen rect")
	_assert(_array_value(action_menu_window.get("tilemap_rect", [])) == [136, 216, 96, 32], "expected renderer action menu composite rect")
	_assert(String(action_menu_window.get("tilemap_composite_rect_status", "")) == "first_pass_generated_textbox_map_preview_rows", "expected generated renderer action menu composite rect status")
	_assert(String(action_menu_window.get("text_info_status", "")) == "generated_from_sTextOnWindowsInfo_Normal", "expected generated renderer action menu text status")
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
	_assert(not _contains_forbidden_runtime_color_key(move_select), "move-select snapshot must not expose palette/source-color keys")
	var move_windows := _array_value(move_select.get("visible_source_windows", []))
	for window_id in ["B_WIN_MOVE_NAME_1", "B_WIN_MOVE_NAME_2", "B_WIN_MOVE_NAME_3", "B_WIN_MOVE_NAME_4", "B_WIN_PP", "B_WIN_PP_REMAINING", "B_WIN_MOVE_TYPE"]:
		_assert(move_windows.has(window_id), "expected move-select window %s" % window_id)
	var move_renderer := _dict_value(move_select.get("source_window_renderer", {}))
	var move_renderer_windows := _dict_value(move_renderer.get("windows", {}))
	var move_name_window := _dict_value(move_renderer_windows.get("B_WIN_MOVE_NAME_1", {}))
	var move_type_window := _dict_value(move_renderer_windows.get("B_WIN_MOVE_TYPE", {}))
	var move_pp_window := _dict_value(move_renderer_windows.get("B_WIN_PP", {}))
	_assert(_array_value(move_renderer.get("visible_windows", [])).size() == 7, "expected renderer move-select windows")
	_assert(_array_value(move_name_window.get("screen_rect", [])) == [16, 120, 128, 16], "expected renderer first move screen rect")
	_assert(_array_value(move_name_window.get("tilemap_rect", [])) == [16, 56, 128, 16], "expected renderer first move composite rect")
	_assert(String(move_name_window.get("tilemap_composite_rect_status", "")) == "first_pass_generated_textbox_map_preview_rows", "expected generated renderer move composite rect status")
	_assert(int(move_name_window.get("source_fit_width_px", 0)) == 64, "expected generated renderer move fit width")
	_assert(_array_value(move_type_window.get("screen_rect", [])) == [168, 136, 64, 16], "expected renderer move type screen rect")
	var move_pp_printer := _dict_value(move_pp_window.get("text_printer", {}))
	var move_type_printer := _dict_value(move_type_window.get("text_printer", {}))
	var move_pp_byte_summary := _dict_value(move_pp_printer.get("source_byte_control_summary", {}))
	_assert(String(move_pp_printer.get("event_stream_source", "")) == "source_bytes", "expected PP label source-byte event stream")
	_assert(String(move_pp_printer.get("source_text_label", "")) == "gText_MoveInterfacePP", "expected PP label source text")
	_assert(int(move_pp_printer.get("source_byte_count", 0)) == 2, "expected PP label generated source byte count")
	_assert(int(move_pp_byte_summary.get("byte_count", 0)) == 2, "expected PP label source byte summary")
	_assert(String(move_type_printer.get("event_stream_source", "")) == "source_text", "expected move type source-text event stream")
	_assert(String(move_type_printer.get("source_text_label", "")) == "gText_MoveInterfaceType", "expected move type source text")
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


func _contains_forbidden_runtime_color_key(value) -> bool:
	if typeof(value) == TYPE_DICTIONARY:
		for key in value.keys():
			var key_text := String(key).to_lower()
			if key_text.contains("palette") or key_text.contains("source_color") or key_text.contains("source_palette"):
				return true
			if _contains_forbidden_runtime_color_key(value[key]):
				return true
	elif typeof(value) == TYPE_ARRAY:
		for item in value:
			if _contains_forbidden_runtime_color_key(item):
				return true
	return false
