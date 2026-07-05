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
	var scene_capture_profile := _dict_value(intro.get("source_scene_capture_profile", {}))
	_assert(String(scene_capture_profile.get("status", "")) == "full_scene_source_profile", "expected full-scene source capture profile")
	_assert(String(scene_capture_profile.get("root", "")) == "assets/source/battle_scene_captures/emerald_2011_zh", "expected source scene capture root")
	_assert(int(scene_capture_profile.get("capture_count", 0)) == 24, "expected 24 full-scene source captures")
	_assert(String(scene_capture_profile.get("window_exact_capture_policy", "")) == "separate_action_message_move_window_layer_pngs", "expected separate window exact-capture policy")
	var scene_layout_profile := _dict_value(intro.get("source_scene_layout_profile", {}))
	_assert(String(scene_layout_profile.get("status", "")) == "measured_full_scene_layout_first_pass", "expected measured full-scene layout profile")
	_assert(String(scene_layout_profile.get("runtime_rect_policy", "")) == "use_capture_00_action_menu_static_rects_until_healthbox_subsprite_runtime", "expected source layout rect policy")
	var measured_key_frames := _dict_value(scene_layout_profile.get("measured_key_frames", {}))
	var action_layout := _dict_value(measured_key_frames.get("capture_00_action_menu", {}))
	_assert(_array_value(action_layout.get("opponent_hp_green_rect", [])) == [52, 33, 48, 2], "expected source-profile opponent HP green rect")
	_assert(_array_value(action_layout.get("player_hp_green_rect", [])) == [174, 92, 48, 2], "expected source-profile player HP green rect")
	_assert(_array_value(action_layout.get("action_prompt_red_frame_rect", [])) == [1, 115, 119, 42], "expected source-profile action prompt frame rect")
	var presentation := _dict_value(intro.get("battle_presentation_assets", {}))
	_assert(String(presentation.get("status", "")) == "exported_asset_layout_first_pass", "expected exported battle asset layout status")
	_assert(int(presentation.get("loaded_asset_count", 0)) >= 6, "expected exported presentation assets to load")
	var asset_rules := _dict_value(presentation.get("asset_rules", {}))
	_assert(String(asset_rules.get("runtime_image_policy", "")) == "exported_rgba_textures_only", "expected exported RGBA asset policy")
	_assert(String(asset_rules.get("source_equivalence", "")) == "not_claimed", "expected presentation layout to avoid source-equivalence claim")
	var environment_assets := _dict_value(presentation.get("environment", {}))
	_assert(String(environment_assets.get("symbol", "")) == "BATTLE_ENVIRONMENT_GRASS", "expected default grass battle environment")
	_assert(String(environment_assets.get("background_path", "")).ends_with("assets/generated/battle_environment/grass/background.png"), "expected grass background texture path")
	_assert(_array_value(environment_assets.get("background_screen_rect", [])) == [0, 0, 240, 112], "expected grass background screen rect")
	_assert(_array_value(environment_assets.get("background_region_rect", [])) == [0, 0, 240, 112], "expected grass background region rect")
	var battler_assets := _dict_value(presentation.get("battlers", {}))
	var player_asset := _dict_value(battler_assets.get("player", {}))
	var opponent_asset := _dict_value(battler_assets.get("opponent", {}))
	_assert(String(player_asset.get("species", "")) == "SPECIES_MUDKIP", "expected player sprite species")
	_assert(String(player_asset.get("path", "")).ends_with("assets/generated/pokemon_battle/mudkip/back.png"), "expected player back sprite texture path")
	_assert(_array_value(player_asset.get("screen_rect", [])) == [32, 56, 64, 64], "expected player sprite screenshot-aligned rect")
	_assert(String(opponent_asset.get("path", "")).find("assets/generated/pokemon_battle/") >= 0, "expected opponent front sprite texture path")
	_assert(_array_value(opponent_asset.get("screen_rect", [])) == [144, 30, 64, 64], "expected opponent sprite screenshot-aligned rect")
	_assert(_array_value(opponent_asset.get("frame_region_rect", [])) == [0, 0, 64, 64], "expected opponent front sprite first-frame crop")
	var healthbox_assets := _dict_value(presentation.get("healthboxes", {}))
	var player_healthbox := _dict_value(healthbox_assets.get("player", {}))
	var opponent_healthbox := _dict_value(healthbox_assets.get("opponent", {}))
	_assert(String(player_healthbox.get("path", "")).ends_with("assets/generated/battle_interface/healthbox_singles_player.png"), "expected player healthbox texture path")
	_assert(String(opponent_healthbox.get("path", "")).ends_with("assets/generated/battle_interface/healthbox_singles_opponent.png"), "expected opponent healthbox texture path")
	_assert(_array_value(player_healthbox.get("screen_rect", [])) == [128, 74, 128, 64], "expected player healthbox screenshot-aligned rect")
	_assert(_array_value(opponent_healthbox.get("screen_rect", [])) == [12, 14, 128, 32], "expected opponent healthbox screenshot-aligned rect")
	var hp_bar_assets := _dict_value(presentation.get("hp_bars", {}))
	_assert(_array_value(hp_bar_assets.get("player", [])) == [174, 92, 48, 2], "expected player HP bar rect")
	_assert(_array_value(hp_bar_assets.get("opponent", [])) == [52, 33, 48, 2], "expected opponent HP bar rect")
	_assert(int(hp_bar_assets.get("height_px", 0)) == 2, "expected source-profile HP bar height")
	_assert(String(hp_bar_assets.get("fill_style", "")) == "source_scaled_hp_fraction_48px_runtime_first_pass", "expected source-profile HP runtime fill style")
	var hp_bar_color_rows := _dict_value(hp_bar_assets.get("hp_fill_rgba_rows", {}))
	_assert(_array_value(hp_bar_color_rows.get("green", [])) == [[90, 214, 132, 255], [115, 255, 173, 255]], "expected source HP green color rows")
	_assert(String(hp_bar_assets.get("runtime_status", "")) == "source_healthbox_runtime_first_pass", "expected HP bar runtime status")
	var source_healthbox_runtime := _dict_value(intro.get("source_healthbox_runtime", {}))
	_assert(String(intro.get("source_healthbox_runtime_status", "")) == "source_healthbox_runtime_first_pass", "expected source healthbox runtime status")
	_assert(String(source_healthbox_runtime.get("status", "")) == "source_healthbox_runtime_first_pass", "expected source healthbox runtime snapshot status")
	var player_runtime := _dict_value(source_healthbox_runtime.get("player", {}))
	var opponent_runtime := _dict_value(source_healthbox_runtime.get("opponent", {}))
	var player_runtime_bar := _dict_value(player_runtime.get("hp_bar", {}))
	var opponent_runtime_bar := _dict_value(opponent_runtime.get("hp_bar", {}))
	var player_runtime_battler := _dict_value(player_runtime.get("battler", {}))
	var opponent_runtime_battler := _dict_value(opponent_runtime.get("battler", {}))
	var player_runtime_contract := _dict_value(player_runtime.get("source_contract", {}))
	_assert(int(player_runtime_contract.get("healthbar_pixels", 0)) == 48, "expected runtime source HP bar width")
	_assert(_array_value(player_runtime.get("source_coord", [])) == [158, 88], "expected runtime player healthbox source coord")
	_assert(_array_value(opponent_runtime.get("source_coord", [])) == [44, 30], "expected runtime opponent healthbox source coord")
	_assert(int(player_runtime_bar.get("filled_px", -1)) == 48, "expected initial player runtime HP width")
	_assert(int(opponent_runtime_bar.get("filled_px", -1)) == 48, "expected initial opponent runtime HP width")
	_assert(String(player_runtime_bar.get("level", "")) == "full", "expected initial player runtime HP level")
	_assert(String(opponent_runtime_bar.get("level", "")) == "full", "expected initial opponent runtime HP level")
	_assert(int(player_runtime_battler.get("current_hp", -1)) == int(player_runtime_battler.get("max_hp", -2)), "expected initial player runtime full HP")
	_assert(int(opponent_runtime_battler.get("current_hp", -1)) == int(opponent_runtime_battler.get("max_hp", -2)), "expected initial opponent runtime full HP")
	var battle_input := _dict_value(intro.get("battle_input", {}))
	_assert(String(battle_input.get("status", "")) == "keyboard_input_first_pass", "expected battle keyboard input metadata")
	_assert(_array_value(battle_input.get("supported_actions", [])).has("ui_accept"), "expected ui_accept battle input support")
	_assert(String(battle_input.get("selected_action", "")) == "fight", "expected default Fight selection")
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
	var controller_metrics: Dictionary = await _run_battle_text_controller_scene_checks(registry, engine, battle_state)
	if _failed:
		return
	var input_metrics: Dictionary = await _run_unhandled_input_scene_checks(registry, engine, battle_state)
	if _failed:
		return

	var intro_advance: Dictionary = scene.handle_battle_input("ui_accept")
	_assert(String(intro_advance.get("status", "")) == "ok", "expected intro advance")
	_assert(String(intro_advance.get("input_status", "")) == "keyboard_input_first_pass", "expected intro advance through keyboard input")
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

	var action_right: Dictionary = scene.handle_battle_input("ui_right")
	_assert(String(action_right.get("selected_action", "")) == "bag", "expected action cursor to move right to Bag")
	var action_left: Dictionary = scene.handle_battle_input("ui_left")
	_assert(String(action_left.get("selected_action", "")) == "fight", "expected action cursor to move left to Fight")
	var fight_result: Dictionary = scene.handle_battle_input("ui_accept")
	_assert(String(fight_result.get("status", "")) == "ok", "expected Fight action selection")
	_assert(String(fight_result.get("input_status", "")) == "keyboard_input_first_pass", "expected Fight selection through keyboard input")
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
	_assert(int(move_pp_printer.get("source_glyph_count", 0)) == 2, "expected PP label generated source glyph count")
	_assert(int(move_pp_printer.get("source_byte_event_count", 0)) == 2, "expected PP label generated source byte event count")
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

	var move_right: Dictionary = scene.handle_battle_input("ui_right")
	_assert(int(move_right.get("selected_move_slot", -1)) == 1, "expected move cursor to move right to second move")
	var move_left: Dictionary = scene.handle_battle_input("ui_left")
	_assert(int(move_left.get("selected_move_slot", -1)) == 0, "expected move cursor to move back left to first move")

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
	_assert(_has_unsupported(result_contract, "battle_presentation_asset_layout_first_pass"), "expected battle presentation asset layout unsupported note")
	_assert(_has_unsupported(result_contract, "battle_keyboard_input_first_pass"), "expected battle keyboard input first-pass note")
	_assert(_has_source_trace(result_contract, "src/battle_main.c:HandleTurnActionSelectionState"), "expected action selection source trace")
	var turn_opponent_party := _array_value(_dict_value(turn_result.get("battle_state", {})).get("opponent_party", []))
	var opponent_after_turn := _dict_value(turn_opponent_party[0]) if not turn_opponent_party.is_empty() else {}
	_assert(int(opponent_after_turn.get("hp", -1)) == 0, "expected opponent HP to reach zero")
	var after_healthbox_runtime := _dict_value(after.get("source_healthbox_runtime", {}))
	var after_opponent_runtime := _dict_value(after_healthbox_runtime.get("opponent", {}))
	var after_opponent_bar := _dict_value(after_opponent_runtime.get("hp_bar", {}))
	var after_opponent_event := _dict_value(after_opponent_runtime.get("last_update_event", {}))
	_assert(int(after_opponent_bar.get("filled_px", -1)) == 0, "expected opponent runtime HP width to reach zero")
	_assert(String(after_opponent_bar.get("level", "")) == "empty", "expected opponent runtime HP level to be empty")
	_assert(String(after_opponent_event.get("status", "")) == "applied", "expected opponent HP runtime event")
	_assert(String(after_opponent_event.get("kind", "")) == "drain", "expected opponent HP runtime drain")
	_assert(int(after_opponent_event.get("from_hp", 0)) > 0, "expected opponent HP runtime event to start above zero")
	_assert(int(after_opponent_event.get("to_hp", -1)) == 0, "expected opponent HP runtime event to end at zero")
	_assert(int(after_opponent_event.get("to_filled_px", -1)) == 0, "expected opponent HP runtime event final width")
	_assert(bool(after_opponent_event.get("vm_hp_delta_consumed", false)), "expected opponent HP runtime event to consume VM delta")
	_assert(bool(after_opponent_event.get("final_pixel_width_matches_source_fraction", false)), "expected opponent HP runtime source width match")
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
		"presentation_asset_count": int(_dict_value(after.get("battle_presentation_assets", {})).get("loaded_asset_count", 0)),
		"battle_input_count": int(_dict_value(after.get("battle_input", {})).get("handled_input_count", 0)),
		"unhandled_input_events": int(input_metrics.get("events", 0)),
		"battle_text_controller_contexts": int(controller_metrics.get("contexts", 0)),
		"recorded_intro_delay": int(controller_metrics.get("recorded_intro_delay", -1)),
		"recorded_link_intro_delay": int(controller_metrics.get("recorded_link_intro_delay", -1)),
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


func _run_battle_text_controller_scene_checks(registry, engine, base_battle_state: Dictionary) -> Dictionary:
	var metrics := {
		"contexts": 0,
		"recorded_intro_delay": -1,
		"recorded_link_intro_delay": -1,
	}
	var context_scene = BATTLE_SCENE.instantiate()
	context_scene.configure_battle_engine(engine)
	context_scene.configure_data_registry(registry)
	get_root().add_child(context_scene)
	await create_timer(0.05).timeout

	var recorded_state: Dictionary = engine.create_trainer_battle_state("TRAINER_SAWYER_1", _array_value(base_battle_state.get("player_party", [])), {
		"recorded_battle": true,
		"recorded_text_speed_index": 1,
		"map_transition_type": "normal",
	})
	_assert(String(recorded_state.get("status", "")) == "ok", "expected recorded trainer state from BattleEngine")
	context_scene.load_battle_state(recorded_state)
	await create_timer(0.05).timeout
	var recorded_intro: Dictionary = context_scene.get_ui_snapshot()
	var recorded_controller := _dict_value(recorded_intro.get("source_battle_text_controller_context", {}))
	_assert(String(recorded_controller.get("status", "")) == "source_battle_text_controller_context_first_pass", "expected recorded controller context status")
	_assert(String(recorded_controller.get("source", "")).contains("BattlePutTextOnWindow"), "expected recorded controller source trace")
	_assert(_array_value(recorded_controller.get("battle_type_flags", [])).has("BATTLE_TYPE_RECORDED"), "expected recorded controller battle flag")
	_assert(String(recorded_controller.get("battle_text_mode", "")) == "recorded", "expected recorded controller mode")
	var recorded_printer := _window_text_printer(recorded_intro, "B_WIN_MSG")
	var recorded_context := _dict_value(recorded_printer.get("battle_text_context", {}))
	_assert(String(recorded_printer.get("battle_text_context_status", "")) == "source_battle_text_context_first_pass", "expected recorded printer context status")
	_assert(int(recorded_printer.get("resolved_frame_delay", -1)) == 4, "expected recorded intro text delay index 1")
	_assert(int(recorded_printer.get("recorded_text_speed_index", -1)) == 1, "expected recorded text speed index propagated")
	_assert(int(recorded_printer.get("recorded_text_speed_value", -1)) == 4, "expected recorded text speed value propagated")
	_assert(bool(recorded_printer.get("auto_scroll", false)), "expected recorded scene text auto-scroll")
	_assert(_array_value(recorded_printer.get("auto_scroll_reasons", [])).has("BATTLE_TYPE_RECORDED"), "expected recorded scene auto-scroll reason")
	_assert(bool(recorded_context.get("battle_type_recorded", false)), "expected recorded scene printer context flag")
	metrics["contexts"] = int(metrics.get("contexts", 0)) + 1
	metrics["recorded_intro_delay"] = int(recorded_printer.get("resolved_frame_delay", -1))

	var recorded_link_state: Dictionary = engine.create_trainer_battle_state("TRAINER_SAWYER_1", _array_value(base_battle_state.get("player_party", [])), {
		"recorded_link_battle": true,
		"recorded_text_speed_index": 2,
		"map_transition_type": "normal",
	})
	_assert(String(recorded_link_state.get("status", "")) == "ok", "expected recorded-link trainer state from BattleEngine")
	context_scene.load_battle_state(recorded_link_state)
	await create_timer(0.05).timeout
	var recorded_link_intro: Dictionary = context_scene.get_ui_snapshot()
	var recorded_link_controller := _dict_value(recorded_link_intro.get("source_battle_text_controller_context", {}))
	_assert(String(recorded_link_controller.get("battle_text_mode", "")) == "recorded_link", "expected recorded-link controller mode")
	_assert(_array_value(recorded_link_controller.get("battle_type_flags", [])).has("BATTLE_TYPE_RECORDED_LINK"), "expected recorded-link controller battle flag")
	var recorded_link_printer := _window_text_printer(recorded_link_intro, "B_WIN_MSG")
	var recorded_link_context := _dict_value(recorded_link_printer.get("battle_text_context", {}))
	_assert(int(recorded_link_printer.get("resolved_frame_delay", -1)) == 1, "expected recorded-link intro text delay")
	_assert(String(recorded_link_printer.get("effective_speed_source", "")).contains("recorded_link_battle_speed"), "expected recorded-link speed source")
	_assert(bool(recorded_link_printer.get("auto_scroll", false)), "expected recorded-link scene text auto-scroll")
	_assert(bool(recorded_link_context.get("battle_type_recorded_link", false)), "expected recorded-link printer context flag")
	_assert(bool(recorded_link_context.get("battle_type_recorded", false)), "expected recorded-link printer recorded context")
	metrics["contexts"] = int(metrics.get("contexts", 0)) + 1
	metrics["recorded_link_intro_delay"] = int(recorded_link_printer.get("resolved_frame_delay", -1))

	context_scene.queue_free()
	return metrics


func _run_unhandled_input_scene_checks(registry, engine, battle_state: Dictionary) -> Dictionary:
	var metrics := {"events": 0}
	var input_scene = BATTLE_SCENE.instantiate()
	input_scene.configure_battle_engine(engine)
	input_scene.configure_data_registry(registry)
	get_root().add_child(input_scene)
	await create_timer(0.05).timeout
	input_scene.load_battle_state(battle_state)
	await create_timer(0.05).timeout

	_send_unhandled_action(input_scene, "ui_accept")
	metrics["events"] = int(metrics.get("events", 0)) + 1
	await create_timer(0.05).timeout
	var action_select: Dictionary = input_scene.get_ui_snapshot()
	_assert(String(action_select.get("ui_phase", "")) == "action_select", "expected _unhandled_input ui_accept to enter action select")
	_assert(int(_dict_value(action_select.get("battle_input", {})).get("handled_input_count", 0)) == 1, "expected one handled unhandled-input event")

	_send_unhandled_action(input_scene, "ui_right")
	metrics["events"] = int(metrics.get("events", 0)) + 1
	await create_timer(0.05).timeout
	var action_right: Dictionary = input_scene.get_ui_snapshot()
	_assert(String(_dict_value(action_right.get("battle_input", {})).get("selected_action", "")) == "bag", "expected _unhandled_input ui_right to select Bag")

	_send_unhandled_action(input_scene, "ui_left")
	metrics["events"] = int(metrics.get("events", 0)) + 1
	await create_timer(0.05).timeout
	var action_left: Dictionary = input_scene.get_ui_snapshot()
	_assert(String(_dict_value(action_left.get("battle_input", {})).get("selected_action", "")) == "fight", "expected _unhandled_input ui_left to return to Fight")

	_send_unhandled_action(input_scene, "ui_accept")
	metrics["events"] = int(metrics.get("events", 0)) + 1
	await create_timer(0.05).timeout
	var move_select: Dictionary = input_scene.get_ui_snapshot()
	_assert(String(move_select.get("ui_phase", "")) == "move_select", "expected _unhandled_input ui_accept to enter move select")

	_send_unhandled_action(input_scene, "ui_right")
	metrics["events"] = int(metrics.get("events", 0)) + 1
	await create_timer(0.05).timeout
	var move_right: Dictionary = input_scene.get_ui_snapshot()
	_assert(int(_dict_value(move_right.get("battle_input", {})).get("selected_move_slot", -1)) == 1, "expected _unhandled_input ui_right to select second move")

	_send_unhandled_action(input_scene, "ui_cancel")
	metrics["events"] = int(metrics.get("events", 0)) + 1
	await create_timer(0.05).timeout
	var canceled: Dictionary = input_scene.get_ui_snapshot()
	_assert(String(canceled.get("ui_phase", "")) == "action_select", "expected _unhandled_input ui_cancel to return to action select")
	_assert(int(_dict_value(canceled.get("battle_input", {})).get("handled_input_count", 0)) == int(metrics.get("events", 0)), "expected all unhandled-input events counted")

	input_scene.queue_free()
	return metrics


func _send_unhandled_action(scene, action_name: String) -> void:
	var event := InputEventAction.new()
	event.action = action_name
	event.pressed = true
	scene._unhandled_input(event)


func _window_text_printer(snapshot: Dictionary, window_id: String) -> Dictionary:
	var renderer := _dict_value(snapshot.get("source_window_renderer", {}))
	var windows := _dict_value(renderer.get("windows", {}))
	var window := _dict_value(windows.get(window_id, {}))
	return _dict_value(window.get("text_printer", {}))


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
