extends Control

signal battle_finished(result: Dictionary)

const VIEWPORT_SIZE := Vector2(240, 160)
const BATTLE_WINDOW_RENDERER_SCRIPT := preload("res://scripts/battle/battle_window_renderer.gd")
const TILE_SIZE := 8
const DISPLAY_HEIGHT := 160
const FONT_SIZE := 8
const HP_BAR_PIXELS := 48
const HP_GREEN := Color(0.26, 0.74, 0.30, 1.0)
const HP_YELLOW := Color(0.88, 0.76, 0.24, 1.0)
const HP_RED := Color(0.88, 0.25, 0.22, 1.0)
const PRESENTATION_STATUS := "first_slice_not_source_equivalent"
const SOURCE_FLOW_STATUS := "source_action_move_window_flow_first_pass"
const BG0_Y_ACTION_CHOOSE := DISPLAY_HEIGHT
const BG0_Y_MOVE_CHOOSE := DISPLAY_HEIGHT * 2
const ACTION_FIGHT := "fight"
const ACTION_PARTY := "party"
const ACTION_BAG := "bag"
const ACTION_RUN := "run"
const PHASE_INTRO := "intro_message"
const PHASE_ACTION_SELECT := "action_select"
const PHASE_MOVE_SELECT := "move_select"
const PHASE_TURN_MESSAGE := "turn_message"
const PHASE_FINISHED := "finished"
const STRINGID_INTROMSG := "STRINGID_INTROMSG"

const SOURCE_WINDOW_IDS := {
	"B_WIN_MSG": 0,
	"B_WIN_ACTION_PROMPT": 1,
	"B_WIN_ACTION_MENU": 2,
	"B_WIN_MOVE_NAME_1": 3,
	"B_WIN_MOVE_NAME_2": 4,
	"B_WIN_MOVE_NAME_3": 5,
	"B_WIN_MOVE_NAME_4": 6,
	"B_WIN_PP": 7,
	"B_WIN_PP_REMAINING": 9,
	"B_WIN_MOVE_TYPE": 10,
}

const SOURCE_ACTION_IDS := {
	ACTION_FIGHT: "B_ACTION_USE_MOVE",
	ACTION_PARTY: "B_ACTION_SWITCH",
	ACTION_BAG: "B_ACTION_USE_ITEM",
	ACTION_RUN: "B_ACTION_RUN",
}

const SOURCE_BATTLE_WINDOWS := {
	"B_WIN_MSG": {"tilemap_left": 2, "tilemap_top": 15, "width": 26, "height": 4, "style_id": "message_window", "base_block": 0x0090, "text_x": 0, "text_y": 1, "font": "FONT_NORMAL"},
	"B_WIN_ACTION_PROMPT": {"tilemap_left": 1, "tilemap_top": 35, "width": 14, "height": 4, "style_id": "message_window", "base_block": 0x01c0, "text_x": 1, "text_y": 1, "font": "FONT_NORMAL"},
	"B_WIN_ACTION_MENU": {"tilemap_left": 17, "tilemap_top": 35, "width": 12, "height": 4, "style_id": "battle_menu_window", "base_block": 0x0190, "text_x": 0, "text_y": 1, "font": "FONT_NORMAL"},
	"B_WIN_MOVE_NAME_1": {"tilemap_left": 2, "tilemap_top": 55, "width": 16, "height": 2, "style_id": "battle_menu_window", "base_block": 0x0300, "text_x": 0, "text_y": 1, "font": "FONT_NARROW", "source_fit_width_px": 64},
	"B_WIN_MOVE_NAME_2": {"tilemap_left": 11, "tilemap_top": 55, "width": 8, "height": 2, "style_id": "battle_menu_window", "base_block": 0x0318, "text_x": 0, "text_y": 1, "font": "FONT_NARROW", "source_fit_width_px": 64},
	"B_WIN_MOVE_NAME_3": {"tilemap_left": 2, "tilemap_top": 57, "width": 16, "height": 2, "style_id": "battle_menu_window", "base_block": 0x0328, "text_x": 0, "text_y": 1, "font": "FONT_NARROW", "source_fit_width_px": 64},
	"B_WIN_MOVE_NAME_4": {"tilemap_left": 11, "tilemap_top": 57, "width": 8, "height": 2, "style_id": "battle_menu_window", "base_block": 0x0340, "text_x": 0, "text_y": 1, "font": "FONT_NARROW", "source_fit_width_px": 64},
	"B_WIN_PP": {"tilemap_left": 21, "tilemap_top": 55, "width": 4, "height": 2, "style_id": "battle_menu_window", "base_block": 0x0290, "text_x": 0, "text_y": 1, "font": "FONT_NARROW"},
	"B_WIN_PP_REMAINING": {"tilemap_left": 25, "tilemap_top": 55, "width": 4, "height": 2, "style_id": "battle_menu_window", "base_block": 0x0298, "text_x": 2, "text_y": 1, "font": "FONT_NORMAL"},
	"B_WIN_MOVE_TYPE": {"tilemap_left": 21, "tilemap_top": 57, "width": 8, "height": 2, "style_id": "battle_menu_window", "base_block": 0x02a0, "text_x": 0, "text_y": 1, "font": "FONT_NARROW"},
}

const SOURCE_BATTLE_TEXT_LABELS := {
	"action_prompt": "gText_WhatWillPkmnDo",
	"battle_menu": "gText_BattleMenu",
	"move_pp": "gText_MoveInterfacePP",
	"move_type": "gText_MoveInterfaceType",
}

const FALLBACK_BATTLE_TEXTS := {
	"gText_WhatWillPkmnDo": "{B_BUFF1}",
	"gText_BattleMenu": "Fight{CLEAR_TO 56}Bag\nPokemon{CLEAR_TO 56}Run",
	"gText_MoveInterfacePP": "PP",
	"gText_MoveInterfaceType": "TYPE/",
}

const SOURCE_HEALTHBOX_COORDS := {
	"singles": {
		"player_left": [158, 88],
		"opponent_left": [44, 30],
	},
	"doubles": {
		"player_left": [159, 76],
		"player_right": [171, 101],
		"opponent_left": [44, 19],
		"opponent_right": [32, 44],
	},
}

const SOURCE_UI_ASSETS := {
	"textbox_texture_source": "graphics/battle_interface/textbox.png",
	"textbox_tilemap": "graphics/battle_interface/textbox_map.bin",
	"healthbox_singles_player": "graphics/battle_interface/healthbox_singles_player.png",
	"healthbox_singles_opponent": "graphics/battle_interface/healthbox_singles_opponent.png",
	"healthbar": "graphics/battle_interface/healthbar.png",
	"render_style_policy": "godot_theme_material_shader",
}

var _sequence: Dictionary = {}
var _battle_state: Dictionary = {}
var _battle_engine: Node = null
var _data_registry: Node = null
var _game_state: Node = null
var _built := false
var _move_buttons: Array = []
var _action_buttons: Dictionary = {}
var _message_lines: Array = []
var _last_result: Dictionary = {}
var _ui_mode := "action"
var _ui_phase := PHASE_INTRO
var _selected_move_slot := 0

var _opponent_name_label: Label
var _opponent_hp_label: Label
var _opponent_hp_fill: ColorRect
var _player_name_label: Label
var _player_hp_label: Label
var _player_hp_fill: ColorRect
var _message_label: Label
var _action_prompt_label: Label
var _pp_label: Label
var _pp_remaining_label: Label
var _move_type_label: Label
var _finish_button: Button
var _window_renderer: Control = null


func _ready() -> void:
	_ensure_ui()


func configure(sequence: Dictionary, battle_engine: Node, game_state: Node = null) -> void:
	_ensure_ui()
	_sequence = sequence.duplicate(true)
	_battle_state = _dictionary_value(_sequence.get("battle_state", {})).duplicate(true)
	_battle_engine = battle_engine
	_ensure_data_registry()
	_configure_window_renderer()
	_game_state = game_state
	_last_result = {}
	_message_lines = [_battle_opening_message()]
	_ui_mode = "action"
	_ui_phase = PHASE_INTRO
	_selected_move_slot = max(0, _first_usable_move_slot(_active_mon("player")))
	_finish_button.visible = false
	_refresh()


func configure_battle_engine(battle_engine: Node) -> void:
	_battle_engine = battle_engine
	_ensure_data_registry()
	_configure_window_renderer()


func configure_data_registry(data_registry: Node) -> void:
	_data_registry = data_registry
	_configure_window_renderer()


func load_battle_state(battle_state: Dictionary) -> void:
	configure({
		"battle_state": battle_state,
		"trainer": battle_state.get("trainer", {}),
	}, _battle_engine, _game_state)


func play_player_move(move_slot: int) -> Dictionary:
	if _ui_phase == PHASE_INTRO:
		advance_intro()
	if _ui_mode == "action":
		select_action(ACTION_FIGHT)
	_on_move_pressed(move_slot)
	return {
		"status": "ok" if not _last_result.is_empty() else "blocked",
		"battle_state": _battle_state.duplicate(true),
		"battle_result": _last_result.duplicate(true),
		"messages": _message_lines.duplicate(true),
		"outcome": String(_last_result.get("outcome", "")),
	}


func advance_intro() -> Dictionary:
	if _ui_phase != PHASE_INTRO:
		return {"status": "blocked", "ui_phase": _ui_phase}
	_ui_phase = PHASE_ACTION_SELECT
	_ui_mode = "action"
	_message_lines = []
	_refresh()
	return {"status": "ok", "ui_phase": _ui_phase}


func select_action(action_id: String) -> Dictionary:
	if not _last_result.is_empty():
		return {"status": "blocked", "reason": "battle_result_ready"}
	if _ui_phase == PHASE_INTRO:
		advance_intro()
	match action_id:
		ACTION_FIGHT:
			_ui_mode = "move"
			_ui_phase = PHASE_MOVE_SELECT
			_message_lines = []
			_selected_move_slot = max(0, _first_usable_move_slot(_active_mon("player")))
			_refresh()
			return {"status": "ok", "ui_mode": _ui_mode, "ui_phase": _ui_phase}
		ACTION_PARTY, ACTION_BAG, ACTION_RUN:
			return {
				"status": "unsupported",
				"unsupported_reason": "battle_action_%s_not_implemented" % action_id,
				"source": "src/battle_controller_player.c:HandleInputChooseAction",
			}
	return {
		"status": "error",
		"unsupported_reason": "unknown_battle_action",
		"action": action_id,
	}


func get_battle_state() -> Dictionary:
	return _battle_state.duplicate(true)


func get_battle_result() -> Dictionary:
	return _last_result.duplicate(true)


func get_ui_snapshot() -> Dictionary:
	var player_mon := _active_mon("player")
	var move_labels := _move_labels_for_renderer(player_mon)
	var action_labels := _battle_menu_labels()
	return {
		"player_name": _player_name_label.text if _player_name_label != null else "",
		"opponent_name": _opponent_name_label.text if _opponent_name_label != null else "",
		"player_hp": _player_hp_label.text if _player_hp_label != null else "",
		"opponent_hp": _opponent_hp_label.text if _opponent_hp_label != null else "",
		"moves": move_labels,
		"action_menu": action_labels,
		"action_prompt": _window_text_or_label("B_WIN_ACTION_PROMPT", _action_prompt_label),
		"pp_label": _window_text_or_label("B_WIN_PP", _pp_label),
		"pp_remaining": _window_text_or_label("B_WIN_PP_REMAINING", _pp_remaining_label),
		"move_type": _window_text_or_label("B_WIN_MOVE_TYPE", _move_type_label),
		"message": _window_text_or_label("B_WIN_MSG", _message_label),
		"outcome": String(_last_result.get("outcome", "")),
		"can_return_to_field": _finish_button.visible if _finish_button != null else false,
		"ui_mode": _ui_mode,
		"ui_phase": _ui_phase,
		"source_string_id": _source_string_id_for_phase(),
		"visible_source_windows": _visible_source_windows(),
		"source_action_ids": SOURCE_ACTION_IDS.duplicate(true),
		"presentation_status": PRESENTATION_STATUS,
		"source_flow_status": SOURCE_FLOW_STATUS,
		"viewport_size": [int(VIEWPORT_SIZE.x), int(VIEWPORT_SIZE.y)],
		"source_window_ids": SOURCE_WINDOW_IDS.duplicate(true),
		"source_windows": _source_window_snapshot(),
		"source_text_symbols": _source_text_snapshot(),
		"source_healthbox_coords": SOURCE_HEALTHBOX_COORDS.duplicate(true),
		"source_ui_assets": SOURCE_UI_ASSETS.duplicate(true),
		"source_window_text_info": _source_window_text_info_snapshot(),
		"source_type_display_status": _source_type_display_status(),
		"source_hp_bar_pixels": HP_BAR_PIXELS,
		"source_window_renderer_status": _source_window_renderer_status(),
		"source_window_renderer": _source_window_renderer_snapshot(),
		"source_bg0_y": {
			"choose_action": BG0_Y_ACTION_CHOOSE,
			"choose_move": BG0_Y_MOVE_CHOOSE,
		},
	}


func _ensure_ui() -> void:
	if _built:
		return
	_built = true
	name = "BattleScene"
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)
	custom_minimum_size = VIEWPORT_SIZE

	var background := ColorRect.new()
	background.color = Color(0.55, 0.74, 0.61, 1.0)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	_add_rect(Rect2(0, 112, 240, 48), Color(0.93, 0.91, 0.79, 1.0))
	_add_rect(Rect2(44, 30, 88, 26), Color(0.98, 0.98, 0.91, 1.0))
	_add_rect(Rect2(158, 88, 78, 30), Color(0.98, 0.98, 0.91, 1.0))
	_add_rect(Rect2(12, 28, 48, 28), Color(0.35, 0.46, 0.40, 1.0))
	_add_rect(Rect2(176, 66, 48, 28), Color(0.35, 0.46, 0.40, 1.0))

	_window_renderer = BATTLE_WINDOW_RENDERER_SCRIPT.new()
	_window_renderer.name = "BattleWindowRenderer"
	_window_renderer.position = Vector2.ZERO
	_window_renderer.size = VIEWPORT_SIZE
	_window_renderer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_window_renderer)
	_configure_window_renderer()

	_opponent_name_label = _add_label(Rect2(50, 32, 74, 10), "")
	_opponent_hp_label = _add_label(Rect2(50, 44, 18, 10), "HP")
	_opponent_hp_fill = _add_hp_bar(Rect2(78, 45, HP_BAR_PIXELS, 4))
	_player_name_label = _add_label(Rect2(164, 90, 66, 10), "")
	_player_hp_label = _add_label(Rect2(164, 106, 66, 10), "")
	_player_hp_fill = _add_hp_bar(Rect2(184, 102, HP_BAR_PIXELS, 4))
	_message_label = _add_label(_window_text_rect("B_WIN_MSG", 0), "")
	_message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	_action_prompt_label = _add_label(_window_text_rect("B_WIN_ACTION_PROMPT", BG0_Y_ACTION_CHOOSE), "")
	_action_prompt_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_add_action_button(ACTION_FIGHT, "Fight", Vector2(136, 121))
	_add_action_button(ACTION_BAG, "Bag", Vector2(192, 121))
	_add_action_button(ACTION_PARTY, "Pokemon", Vector2(136, 137))
	_add_action_button(ACTION_RUN, "Run", Vector2(192, 137))

	for index in range(4):
		var button := Button.new()
		var move_rect := _move_button_rect(index)
		button.position = move_rect.position
		button.size = move_rect.size
		button.focus_mode = Control.FOCUS_NONE
		button.flat = true
		button.add_theme_font_size_override("font_size", FONT_SIZE)
		button.pressed.connect(_on_move_pressed.bind(index))
		add_child(button)
		_move_buttons.append(button)

	_pp_label = _add_label(_window_text_rect("B_WIN_PP", BG0_Y_MOVE_CHOOSE), _source_battle_text("gText_MoveInterfacePP"))
	_pp_remaining_label = _add_label(_window_text_rect("B_WIN_PP_REMAINING", BG0_Y_MOVE_CHOOSE), "")
	_move_type_label = _add_label(_window_text_rect("B_WIN_MOVE_TYPE", BG0_Y_MOVE_CHOOSE), "")

	_finish_button = Button.new()
	_finish_button.position = Vector2(128, 148)
	_finish_button.size = Vector2(104, 10)
	_finish_button.text = "Return"
	_finish_button.focus_mode = Control.FOCUS_NONE
	_finish_button.add_theme_font_size_override("font_size", FONT_SIZE)
	_finish_button.pressed.connect(_on_finish_pressed)
	add_child(_finish_button)


func _on_move_pressed(move_slot: int) -> void:
	if _ui_phase == PHASE_INTRO:
		advance_intro()
	if _ui_mode == "action":
		select_action(ACTION_FIGHT)
	if _battle_engine == null or not _battle_engine.has_method("use_move"):
		_message_lines = ["BattleEngine unavailable."]
		_refresh()
		return
	if not _last_result.is_empty():
		return
	_selected_move_slot = move_slot

	if _battle_engine.has_method("execute_player_move_turn"):
		_execute_engine_player_turn(move_slot)
		return

	var player_party := _array_value(_battle_state.get("player_party", []))
	var opponent_party := _array_value(_battle_state.get("opponent_party", []))
	var active := _dictionary_value(_battle_state.get("active", {}))
	var player_index := int(active.get("player", 0))
	var opponent_index := int(active.get("opponent", 0))
	if player_index < 0 or player_index >= player_party.size() or opponent_index < 0 or opponent_index >= opponent_party.size():
		_message_lines = ["Invalid active battler."]
		_refresh()
		return

	var player_mon: Dictionary = player_party[player_index]
	var opponent_mon: Dictionary = opponent_party[opponent_index]
	var messages: Array = []
	var player_result = _battle_engine.use_move(player_mon, opponent_mon, move_slot, {"damage_roll_percent": 100})
	if typeof(player_result) != TYPE_DICTIONARY:
		_message_lines = ["Invalid move result."]
		_refresh()
		return
	messages.append_array(_message_texts(player_result.get("messages", [])))
	player_party[player_index] = player_result.get("attacker", player_mon)
	opponent_party[opponent_index] = player_result.get("defender", opponent_mon)

	var outcome := "in_progress"
	if bool(_dictionary_value(opponent_party[opponent_index]).get("fainted", false)):
		outcome = "player_won"
	else:
		var opponent_slot := _first_usable_move_slot(_dictionary_value(opponent_party[opponent_index]))
		if opponent_slot >= 0:
			var opponent_result = _battle_engine.use_move(
				_dictionary_value(opponent_party[opponent_index]),
				_dictionary_value(player_party[player_index]),
				opponent_slot,
				{"damage_roll_percent": 100}
			)
			if typeof(opponent_result) == TYPE_DICTIONARY:
				messages.append_array(_message_texts(opponent_result.get("messages", [])))
				opponent_party[opponent_index] = opponent_result.get("attacker", opponent_party[opponent_index])
				player_party[player_index] = opponent_result.get("defender", player_party[player_index])
		if bool(_dictionary_value(player_party[player_index]).get("fainted", false)):
			outcome = "opponent_won"

	_battle_state["player_party"] = player_party
	_battle_state["opponent_party"] = opponent_party
	_battle_state["turn"] = int(_battle_state.get("turn", 0)) + 1
	_battle_state["outcome"] = outcome
	_battle_state["last_turn"] = {
		"status": "ok",
		"actor": "round_demo",
		"player_move_slot": move_slot,
		"messages": messages,
		"source": "scripts/battle/battle_scene.gd:first_pass_debug_round_not_source_equivalent",
		"presentation_status": PRESENTATION_STATUS,
	}
	_message_lines = messages
	if outcome == "in_progress":
		_message_lines.append("Debug round complete.")
	elif outcome == "player_won":
		_message_lines.append("You won the battle.")
	elif outcome == "opponent_won":
		_message_lines.append("You lost the battle.")
	_last_result = _build_result_contract(outcome)
	_finish_button.visible = true
	_ui_mode = "result"
	_ui_phase = PHASE_FINISHED
	_refresh()


func _on_finish_pressed() -> void:
	var result := _last_result
	if result.is_empty():
		result = _build_result_contract("debug_cancelled")
	battle_finished.emit(result)


func _refresh() -> void:
	var player_mon := _active_mon("player")
	var opponent_mon := _active_mon("opponent")
	_player_name_label.text = _mon_title(player_mon)
	_player_hp_label.text = _hp_text(player_mon)
	_set_hp_fill(_player_hp_fill, player_mon)
	_opponent_name_label.text = _mon_title(opponent_mon)
	_opponent_hp_label.text = "HP"
	_set_hp_fill(_opponent_hp_fill, opponent_mon)
	_message_label.text = "\n".join(_message_lines.slice(max(0, _message_lines.size() - 4), _message_lines.size()))
	_refresh_bottom_windows(player_mon)


func _refresh_bottom_windows(player_mon: Dictionary) -> void:
	var intro_visible := _ui_phase == PHASE_INTRO
	var action_visible := _ui_phase == PHASE_ACTION_SELECT and _last_result.is_empty()
	var move_visible := _ui_phase == PHASE_MOVE_SELECT and _last_result.is_empty()
	var message_visible := intro_visible or _ui_phase == PHASE_TURN_MESSAGE or _ui_phase == PHASE_FINISHED
	var legacy_text_visible := _window_renderer == null
	_message_label.visible = message_visible and legacy_text_visible
	_action_prompt_label.visible = action_visible and legacy_text_visible
	_action_prompt_label.text = _action_prompt_text(player_mon)
	for action_id in _action_buttons.keys():
		var action_button: Button = _action_buttons[action_id]
		action_button.visible = action_visible
		action_button.disabled = action_id != ACTION_FIGHT
	_refresh_action_button_labels()
	_refresh_move_buttons(player_mon, move_visible)
	_pp_label.visible = move_visible and legacy_text_visible
	_pp_remaining_label.visible = move_visible and legacy_text_visible
	_move_type_label.visible = move_visible and legacy_text_visible
	_refresh_move_selection_metadata(player_mon)
	_refresh_window_renderer(player_mon, message_visible, action_visible, move_visible)


func _refresh_move_buttons(player_mon: Dictionary, visible: bool) -> void:
	var moves := _array_value(player_mon.get("moves", []))
	for index in range(_move_buttons.size()):
		var button: Button = _move_buttons[index]
		button.visible = visible
		if index >= moves.size():
			button.disabled = true
			button.text = "-" if _window_renderer == null else ""
			continue
		var move = moves[index]
		if typeof(move) != TYPE_DICTIONARY:
			button.disabled = true
			button.text = "-" if _window_renderer == null else ""
			continue
		button.disabled = int(move.get("current_pp", 0)) <= 0 or not _last_result.is_empty()
		button.text = _short_text(String(move.get("name", move.get("symbol", "Move"))), 10) if _window_renderer == null else ""


func _refresh_move_selection_metadata(player_mon: Dictionary) -> void:
	var moves := _array_value(player_mon.get("moves", []))
	if _selected_move_slot < 0 or _selected_move_slot >= moves.size():
		_selected_move_slot = max(0, _first_usable_move_slot(player_mon))
	if _selected_move_slot < 0 or _selected_move_slot >= moves.size() or typeof(moves[_selected_move_slot]) != TYPE_DICTIONARY:
		_pp_remaining_label.text = "--/--"
		_move_type_label.text = "%s?" % _source_battle_text("gText_MoveInterfaceType")
		return
	var move: Dictionary = moves[_selected_move_slot]
	_pp_label.text = _source_battle_text("gText_MoveInterfacePP")
	_pp_remaining_label.text = "%2d/%2d" % [int(move.get("current_pp", 0)), int(move.get("max_pp", 0))]
	_move_type_label.text = _move_type_text(move)


func _refresh_window_renderer(player_mon: Dictionary, message_visible: bool, action_visible: bool, move_visible: bool) -> void:
	if _window_renderer == null:
		return
	if message_visible:
		_window_renderer.show_message_window(_message_label.text)
	elif action_visible:
		var prompt_mon_name := _action_prompt_mon_name(player_mon)
		_window_renderer.show_action_windows(
			_action_prompt_text(player_mon),
			_battle_menu_text_for_renderer(),
			_source_battle_text_printer_options("gText_WhatWillPkmnDo", {"{B_BUFF1}": prompt_mon_name})
		)
	elif move_visible:
		var move_type_suffix := _move_type_suffix_for_selected(player_mon)
		_window_renderer.show_move_windows(
			_move_labels_for_renderer(player_mon),
			_source_battle_text("gText_MoveInterfacePP"),
			_pp_remaining_text(player_mon),
			_move_type_text_for_selected(player_mon),
			{
				"B_WIN_PP": _source_battle_text_printer_options("gText_MoveInterfacePP"),
				"B_WIN_MOVE_TYPE": _source_battle_text_printer_options("gText_MoveInterfaceType", {}, move_type_suffix),
			}
		)
	else:
		_window_renderer.clear_windows()


func _build_result_contract(outcome: String) -> Dictionary:
	var result := {}
	if _battle_engine != null and _battle_engine.has_method("build_battle_result"):
		result = _battle_engine.build_battle_result(_battle_state, {"outcome": outcome})
	if typeof(result) != TYPE_DICTIONARY or result.is_empty():
		result = {
			"status": "ok",
			"outcome": outcome,
			"player_party": _array_value(_battle_state.get("player_party", [])),
			"opponent_party": _array_value(_battle_state.get("opponent_party", [])),
			"unsupported": [],
		}
	result["outcome"] = outcome
	result["battle_state"] = _battle_state.duplicate(true)
	result["statistics"] = _sequence.get("statistics", {})
	result["presentation_status"] = PRESENTATION_STATUS
	result["source_flow_status"] = SOURCE_FLOW_STATUS
	result["ui_phase"] = _ui_phase
	var debug_player_party := _dictionary_value(_sequence.get("debug_player_party", _battle_state.get("debug_player_party", {})))
	result["debug_player_party"] = debug_player_party.duplicate(true)
	var source_trace := _array_value(result.get("source_trace", []))
	for trace in _battle_scene_source_trace():
		if not source_trace.has(trace):
			source_trace.append(trace)
	result["source_trace"] = source_trace
	var post_battle = result.get("post_battle", {})
	post_battle = post_battle if typeof(post_battle) == TYPE_DICTIONARY else {}
	post_battle["return_to_field"] = true
	post_battle["field_resume"] = {
		"source_map": String(_sequence.get("source_map", "")),
		"source_position": _sequence.get("source_position", Vector2i.ZERO),
		"callback": _field_resume_callback(),
	}
	post_battle["pending_game_state_party_write"] = not bool(debug_player_party.get("temporary", false))
	post_battle["debug_player_party_temporary"] = bool(debug_player_party.get("temporary", false))
	result["post_battle"] = post_battle
	var unsupported := _array_value(result.get("unsupported", []))
	unsupported.append_array(_battle_scene_unsupported())
	if bool(debug_player_party.get("temporary", false)):
		unsupported.append({
			"code": "debug_player_party_not_persisted",
			"source": "Godot-only debug fixture overlay",
			"detail": "The temporary debug party exists only to enter this battle before the starter flow is ported; Main must not persist it as the player's source party.",
		})
	result["unsupported"] = unsupported
	return result


func _field_resume_callback() -> String:
	return "CB2_EndWildBattle" if String(_sequence.get("battle_kind", _battle_state.get("battle_kind", ""))) == "wild" else "CB2_EndTrainerBattle"


func _battle_scene_source_trace() -> Array:
	return [
		"src/battle_main.c:CB2_InitBattle",
		"src/battle_main.c:BattleMainCB2",
		"src/battle_main.c:DoBattleIntro",
		"src/battle_main.c:HandleTurnActionSelectionState",
		"src/battle_bg.c:sStandardBattleWindowTemplates",
		"src/battle_interface.c",
		"src/battle_interface.c:sBattlerHealthboxCoords",
		"src/battle_controller_player.c",
		"src/battle_controller_player.c:MoveSelectionDisplayMoveType",
		"src/data/types_info.h:gTypesInfo",
		"src/battle_message.c",
		"src/battle_message.c:sTextOnWindowsInfo_Normal",
		"src/battle_setup.c:%s" % _field_resume_callback(),
	]


func _battle_scene_unsupported() -> Array:
	var unsupported := [{
		"code": "battle_scene_not_source_equivalent",
		"source": "src/battle_main.c:CB2_InitBattle",
		"detail": "This scene is a debug vertical slice. It does not recreate the source battle tilemaps, battler sprites, healthbox sprites, window graphics, audio, or exact callback/task flow.",
	}, {
		"code": "battle_ui_windows_not_source_equivalent",
		"source": "src/battle_interface.c; src/battle_controller_player.c; src/battle_message.c",
		"detail": "The first pass now follows source action/move window ids, BG0 scroll offsets, text symbols, and HP bar width, but it still uses Godot controls instead of imported source window tilemaps, RGBA window textures, text printer glyphs, and healthbox sprites.",
	}, {
		"code": "battle_action_menu_partial",
		"source": "src/battle_controller_player.c:PlayerHandleChooseAction; src/battle_controller_player.c:HandleInputChooseAction",
		"detail": "The source Fight/Pokémon/Bag/Run action menu is visible, but only Fight is interactive in this slice.",
	}, {
		"code": "battle_healthbox_sprites_not_imported",
		"source": "src/battle_interface.c:CreateBattlerHealthboxSprites",
		"detail": "Healthbox anchors and 48-pixel HP bar scaling are source-backed, but the OBJ healthbox graphics and slide-in animation are not imported yet.",
	}, {
		"code": "battle_audio_unsupported",
		"source": "src/battle_controller_player.c; src/battle_main.c",
		"detail": "Battle cries, menu sounds, music, and sound effects are intentionally unsupported for now per project scope.",
	}, {
		"code": "debug_battle_scene_single_round",
		"source": "scripts/battle/battle_scene.gd",
		"detail": "The first BattleScene slice returns to field after one deterministic round unless a faint happens first.",
	}, {
		"code": "battle_turn_loop_first_slice",
		"source": "src/battle_main.c:BattleMainCB2",
		"detail": "Speed order, battle controller command queues, trainer AI, accuracy, priority, switching, items, abilities, status, rewards, EXP, and full move effects are not implemented in this scene.",
	}, {
		"code": "trainer_post_battle_flow_incomplete",
		"source": "src/battle_setup.c:CB2_EndTrainerBattle",
		"detail": "Trainer defeat text, money/reward flow, post-battle event scripts, object-event trainer flags, and full field callback restoration remain future source-backed work.",
	}]
	if String(_source_type_display_status().get("status", "")) != "available":
		unsupported.append({
			"code": "battle_type_names_unavailable",
			"source": "src/data/types_info.h:gTypesInfo",
			"detail": "Move type labels fall back to TYPE_* symbols when generated type metadata is unavailable.",
		})
	return unsupported


func _execute_engine_player_turn(move_slot: int) -> void:
	var turn_result = _battle_engine.execute_player_move_turn(_battle_state, move_slot, {"damage_roll_percent": 100})
	if typeof(turn_result) != TYPE_DICTIONARY:
		_message_lines = ["Invalid turn result."]
		_ui_phase = PHASE_TURN_MESSAGE
		_refresh()
		return
	if String(turn_result.get("status", "")) != "ok":
		_message_lines = _message_texts(turn_result.get("messages", []))
		if _message_lines.is_empty():
			_message_lines = [String(turn_result.get("status", "Battle command failed."))]
		_ui_phase = PHASE_TURN_MESSAGE
		_refresh()
		return
	_battle_state = _dictionary_value(turn_result.get("battle_state", _battle_state)).duplicate(true)
	_message_lines = _message_texts(turn_result.get("messages", []))
	var outcome := String(turn_result.get("outcome", "in_progress"))
	if outcome == "in_progress":
		_message_lines.append("Debug player turn complete.")
		_ui_mode = "result"
		_ui_phase = PHASE_TURN_MESSAGE
		_last_result = _build_result_contract(outcome)
		_finish_button.visible = false
	else:
		if outcome == "player_won":
			_message_lines.append("You won the battle.")
		elif outcome == "opponent_won":
			_message_lines.append("You lost the battle.")
		_last_result = _build_result_contract(outcome)
		_finish_button.visible = true
		_ui_mode = "result"
		_ui_phase = PHASE_FINISHED
	_refresh()


func _active_mon(side: String) -> Dictionary:
	var party_key := "player_party" if side == "player" else "opponent_party"
	var active_key := "player" if side == "player" else "opponent"
	var party := _array_value(_battle_state.get(party_key, []))
	var active := _dictionary_value(_battle_state.get("active", {}))
	var index := int(active.get(active_key, 0))
	if index >= 0 and index < party.size() and typeof(party[index]) == TYPE_DICTIONARY:
		return party[index]
	return {}


func _first_usable_move_slot(mon: Dictionary) -> int:
	var moves := _array_value(mon.get("moves", []))
	for index in range(moves.size()):
		var move = moves[index]
		if typeof(move) == TYPE_DICTIONARY and int(move.get("current_pp", 0)) > 0:
			return index
	return -1


func _battle_opening_message() -> String:
	var trainer = _sequence.get("trainer", {})
	if typeof(trainer) == TYPE_DICTIONARY:
		var trainer_name := String(trainer.get("name", trainer.get("symbol", "Trainer")))
		return "%s wants to battle!" % trainer_name
	return "Battle started!"


func _source_string_id_for_phase() -> String:
	if _ui_phase == PHASE_INTRO:
		return STRINGID_INTROMSG
	if _ui_phase == PHASE_ACTION_SELECT:
		return "gText_WhatWillPkmnDo"
	if _ui_phase == PHASE_MOVE_SELECT:
		return "gText_MoveInterfacePP/gText_MoveInterfaceType"
	return ""


func _visible_source_windows() -> Array:
	if _ui_phase == PHASE_INTRO or _ui_phase == PHASE_TURN_MESSAGE or _ui_phase == PHASE_FINISHED:
		return ["B_WIN_MSG"]
	if _ui_phase == PHASE_ACTION_SELECT:
		return ["B_WIN_ACTION_PROMPT", "B_WIN_ACTION_MENU"]
	if _ui_phase == PHASE_MOVE_SELECT:
		return [
			"B_WIN_MOVE_NAME_1",
			"B_WIN_MOVE_NAME_2",
			"B_WIN_MOVE_NAME_3",
			"B_WIN_MOVE_NAME_4",
			"B_WIN_PP",
			"B_WIN_PP_REMAINING",
			"B_WIN_MOVE_TYPE",
		]
	return []


func _refresh_action_button_labels() -> void:
	var labels := _battle_menu_labels()
	for action_id in labels.keys():
		if _action_buttons.has(action_id):
			var button: Button = _action_buttons[action_id]
			button.text = "" if _window_renderer != null else String(labels[action_id])


func _battle_menu_text_for_renderer() -> String:
	return _replace_text_control_with_tab(_source_battle_text("gText_BattleMenu"))


func _move_labels_for_renderer(player_mon: Dictionary) -> Array:
	var moves := _array_value(player_mon.get("moves", []))
	var labels: Array = []
	for index in range(4):
		if index >= moves.size() or typeof(moves[index]) != TYPE_DICTIONARY:
			labels.append("-")
			continue
		var move: Dictionary = moves[index]
		labels.append(_short_text(String(move.get("name", move.get("symbol", "Move"))), 10))
	return labels


func _pp_remaining_text(player_mon: Dictionary) -> String:
	var move := _selected_move_for_metadata(player_mon)
	if move.is_empty():
		return "--/--"
	return "%2d/%2d" % [int(move.get("current_pp", 0)), int(move.get("max_pp", 0))]


func _move_type_text_for_selected(player_mon: Dictionary) -> String:
	var move := _selected_move_for_metadata(player_mon)
	if move.is_empty():
		return "%s?" % _source_battle_text("gText_MoveInterfaceType")
	return _move_type_text(move)


func _selected_move_for_metadata(player_mon: Dictionary) -> Dictionary:
	var moves := _array_value(player_mon.get("moves", []))
	if _selected_move_slot < 0 or _selected_move_slot >= moves.size():
		return {}
	var move = moves[_selected_move_slot]
	return move if typeof(move) == TYPE_DICTIONARY else {}


func _battle_menu_labels() -> Dictionary:
	var text := _replace_text_control_with_tab(_source_battle_text("gText_BattleMenu"))
	var tokens: Array = []
	for line in text.split("\n"):
		for part in String(line).split("\t"):
			var token := String(part).strip_edges()
			if not token.is_empty():
				tokens.append(token)
	return {
		ACTION_FIGHT: String(tokens[0]) if tokens.size() > 0 else "Fight",
		ACTION_BAG: String(tokens[1]) if tokens.size() > 1 else "Bag",
		ACTION_PARTY: String(tokens[2]) if tokens.size() > 2 else "Pokemon",
		ACTION_RUN: String(tokens[3]) if tokens.size() > 3 else "Run",
	}


func _replace_text_control_with_tab(text: String) -> String:
	var result := text
	while true:
		var start := result.find("{CLEAR_TO")
		if start < 0:
			return result
		var end := result.find("}", start)
		if end < 0:
			return result
		result = result.substr(0, start) + "\t" + result.substr(end + 1)
	return result


func _source_battle_text(label: String) -> String:
	var record := _source_battle_text_record(label)
	var text := String(record.get("display_text", ""))
	if text.is_empty():
		text = String(FALLBACK_BATTLE_TEXTS.get(label, ""))
	return text


func _source_battle_text_record(label: String) -> Dictionary:
	_ensure_data_registry()
	if _data_registry != null and _data_registry.has_method("get_battle_text_record"):
		var record = _data_registry.get_battle_text_record(label)
		if typeof(record) == TYPE_DICTIONARY and not record.is_empty():
			return record
	if _data_registry != null and _data_registry.has_method("get_battle_string_record"):
		var string_record = _data_registry.get_battle_string_record(label)
		if typeof(string_record) == TYPE_DICTIONARY and not string_record.is_empty():
			return string_record
	return {}


func _source_text_snapshot() -> Dictionary:
	var result := {}
	for text_label in SOURCE_BATTLE_TEXT_LABELS.values():
		var label := String(text_label)
		var record := _source_battle_text_record(label)
		result[label] = {
			"display_text": _source_battle_text(label),
			"status": "generated" if not record.is_empty() else "fallback",
			"source_text": String(record.get("source_text", "")),
			"text_control_count": _array_value(record.get("text_controls", [])).size(),
			"audio_cue_count": _array_value(record.get("audio_cues", [])).size(),
			"source": record.get("source", {}) if not record.is_empty() else {},
		}
	return result


func _action_prompt_mon_name(player_mon: Dictionary) -> String:
	return _short_text(String(player_mon.get("name", player_mon.get("species", "Pokemon"))), 12)


func _action_prompt_text(player_mon: Dictionary) -> String:
	var mon_name := _action_prompt_mon_name(player_mon)
	return _source_battle_text("gText_WhatWillPkmnDo").replace("{B_BUFF1}", mon_name)


func _move_type_text(move: Dictionary) -> String:
	var type_symbol := String(move.get("type", ""))
	if type_symbol.is_empty():
		return "%s?" % _source_battle_text("gText_MoveInterfaceType")
	var type_name := _type_display_name(type_symbol)
	if type_name.is_empty():
		type_name = type_symbol
	return "%s%s" % [_source_battle_text("gText_MoveInterfaceType"), type_name]


func _move_type_suffix_for_selected(player_mon: Dictionary) -> String:
	var move := _selected_move_for_metadata(player_mon)
	if move.is_empty():
		return "?"
	var type_symbol := String(move.get("type", ""))
	if type_symbol.is_empty():
		return "?"
	var type_name := _type_display_name(type_symbol)
	return type_name if not type_name.is_empty() else type_symbol


func _source_battle_text_printer_options(label: String, replacements: Dictionary = {}, source_text_suffix: String = "") -> Dictionary:
	var record := _source_battle_text_record(label)
	if record.is_empty():
		return {}
	var source_text := String(record.get("source_text", ""))
	if source_text.is_empty():
		return {}
	for raw_value in replacements.keys():
		source_text = source_text.replace(String(raw_value), String(replacements[raw_value]))
	if not source_text_suffix.is_empty():
		source_text += source_text_suffix
	var options := {
		"source_text": source_text,
		"source_text_label": label,
		"text_controls": record.get("text_controls", []),
		"audio_cues": record.get("audio_cues", []),
		"metadata_only": record.get("metadata_only", []),
	}
	if replacements.is_empty() and source_text_suffix.is_empty():
		var encoding := _dict_or_empty(record.get("encoding", {}))
		if not encoding.is_empty():
			options["source_encoding"] = encoding
			options["source_bytes"] = encoding.get("bytes", [])
			options["source_glyphs"] = encoding.get("glyphs", [])
			options["source_encoding_hex"] = String(encoding.get("hex", ""))
	return options


func _type_display_name(type_symbol: String) -> String:
	_ensure_data_registry()
	if _data_registry == null or not _data_registry.has_method("get_type_record"):
		return ""
	var record = _data_registry.get_type_record(type_symbol)
	if typeof(record) != TYPE_DICTIONARY or record.is_empty():
		return ""
	var name = record.get("name", {})
	if typeof(name) != TYPE_DICTIONARY:
		return ""
	return String(name.get("display_text", ""))


func _source_type_display_status() -> Dictionary:
	_ensure_data_registry()
	var result := {
		"source": "src/battle_controller_player.c:MoveSelectionDisplayMoveType -> src/data/types_info.h:gTypesInfo",
		"generated_category": "pokemon/types",
		"status": "available" if _data_registry != null and _data_registry.has_method("get_type_record") else "unavailable",
	}
	if _data_registry != null and _data_registry.has_method("get_type_record"):
		var water = _data_registry.get_type_record("TYPE_WATER")
		if typeof(water) == TYPE_DICTIONARY and not water.is_empty():
			var name = water.get("name", {})
			if typeof(name) == TYPE_DICTIONARY:
				result["sample_type_water_name"] = String(name.get("display_text", ""))
	return result


func _mon_title(mon: Dictionary) -> String:
	if mon.is_empty():
		return "-"
	return "%s Lv.%d" % [_short_text(String(mon.get("name", mon.get("species", "Pokemon"))), 14), int(mon.get("level", 1))]


func _hp_text(mon: Dictionary) -> String:
	if mon.is_empty():
		return "HP -/-"
	return "HP %d/%d" % [int(mon.get("hp", 0)), int(mon.get("max_hp", 1))]


func _set_hp_fill(fill: ColorRect, mon: Dictionary) -> void:
	var max_hp: int = max(1, int(mon.get("max_hp", 1)))
	var hp: int = clampi(int(mon.get("hp", 0)), 0, max_hp)
	var ratio: float = float(hp) / float(max_hp)
	fill.size.x = roundi(float(HP_BAR_PIXELS) * ratio)
	if ratio <= 0.2:
		fill.color = HP_RED
	elif ratio <= 0.5:
		fill.color = HP_YELLOW
	else:
		fill.color = HP_GREEN


func _message_texts(messages) -> Array:
	var result: Array = []
	if typeof(messages) != TYPE_ARRAY:
		return result
	for message in messages:
		if typeof(message) == TYPE_DICTIONARY:
			var text := String(message.get("text", ""))
			if not text.is_empty():
				result.append(text)
	return result


func _add_label(rect: Rect2, text: String) -> Label:
	var label := Label.new()
	label.position = rect.position
	label.size = rect.size
	label.text = text
	label.clip_text = true
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	add_child(label)
	return label


func _add_action_button(action_id: String, text: String, position: Vector2) -> void:
	var button := Button.new()
	button.position = position
	button.size = Vector2(40, 14)
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.flat = true
	button.add_theme_font_size_override("font_size", FONT_SIZE)
	button.pressed.connect(select_action.bind(action_id))
	add_child(button)
	_action_buttons[action_id] = button


func _add_rect(rect: Rect2, color: Color) -> ColorRect:
	var color_rect := ColorRect.new()
	color_rect.position = rect.position
	color_rect.size = rect.size
	color_rect.color = color
	add_child(color_rect)
	return color_rect


func _add_hp_bar(rect: Rect2) -> ColorRect:
	_add_rect(Rect2(rect.position - Vector2(1, 1), rect.size + Vector2(2, 2)), Color(0.16, 0.16, 0.16, 1.0))
	return _add_rect(rect, HP_GREEN)


func _move_button_rect(index: int) -> Rect2:
	var window_id := "B_WIN_MOVE_NAME_%d" % [index + 1]
	var rect := _window_screen_rect(window_id, BG0_Y_MOVE_CHOOSE)
	var fit_width := int(SOURCE_BATTLE_WINDOWS[window_id].get("source_fit_width_px", rect.size.x))
	return Rect2(rect.position, Vector2(fit_width, rect.size.y))


func _window_text_rect(window_id: String, bg0_y: int) -> Rect2:
	var rect := _window_screen_rect(window_id, bg0_y)
	var window := _source_window_record(window_id)
	var text_info := _dict_or_empty(window.get("text_info", {}))
	return Rect2(
		rect.position + Vector2(int(text_info.get("text_x", window.get("text_x", 0))), int(text_info.get("text_y", window.get("text_y", 0)))),
		rect.size
	)


func _window_screen_rect(window_id: String, bg0_y: int) -> Rect2:
	var window := _source_window_record(window_id)
	return Rect2(
		Vector2(
			int(window.get("tilemap_left", 0)) * TILE_SIZE,
			int(window.get("tilemap_top", 0)) * TILE_SIZE - bg0_y
		),
		Vector2(
			int(window.get("width", 0)) * TILE_SIZE,
			int(window.get("height", 0)) * TILE_SIZE
		)
	)


func _source_window_snapshot() -> Dictionary:
	var result := {}
	var generated_windows := _generated_window_templates()
	var source_windows := generated_windows if not generated_windows.is_empty() else SOURCE_BATTLE_WINDOWS
	for window_id in source_windows.keys():
		var source: Dictionary = _sanitized_source_window_record(_dict_or_empty(source_windows[window_id]))
		var bg0_y := 0
		if window_id == "B_WIN_ACTION_PROMPT" or window_id == "B_WIN_ACTION_MENU":
			bg0_y = BG0_Y_ACTION_CHOOSE
		elif window_id.begins_with("B_WIN_MOVE") or window_id == "B_WIN_PP" or window_id == "B_WIN_PP_REMAINING":
			bg0_y = BG0_Y_MOVE_CHOOSE
		source["screen_rect"] = [
			int(source.get("tilemap_left", 0)) * TILE_SIZE,
			int(source.get("tilemap_top", 0)) * TILE_SIZE - bg0_y,
			int(source.get("width", 0)) * TILE_SIZE,
			int(source.get("height", 0)) * TILE_SIZE,
		]
		source["bg0_y"] = bg0_y
		result[window_id] = source
	return result


func _source_window_text_info_snapshot() -> Dictionary:
	var result := {}
	var windows := _generated_window_templates()
	if windows.is_empty():
		windows = SOURCE_BATTLE_WINDOWS
	for window_id in SOURCE_WINDOW_IDS.keys():
		var window := _dict_or_empty(windows.get(window_id, {}))
		var text_info := _dict_or_empty(window.get("text_info", {}))
		if text_info.is_empty():
			continue
		result[window_id] = _sanitized_text_info_record(text_info)
	return result


func _source_window_record(window_id: String) -> Dictionary:
	var generated_windows := _generated_window_templates()
	if generated_windows.has(window_id):
		var generated := _dict_or_empty(generated_windows.get(window_id, {}))
		if not generated.is_empty():
			return generated
	var fallback: Variant = SOURCE_BATTLE_WINDOWS.get(window_id, {})
	return fallback if typeof(fallback) == TYPE_DICTIONARY else {}


func _sanitized_source_window_record(source: Dictionary) -> Dictionary:
	var result := {}
	for key in ["symbol", "bg", "tilemap_left", "tilemap_top", "width", "height", "style_id", "base_block", "source", "runtime_status", "tilemap_composite_rect"]:
		if source.has(key):
			result[key] = source[key]
	var text_info := _dict_or_empty(source.get("text_info", {}))
	if not text_info.is_empty():
		result["text_info"] = _sanitized_text_info_record(text_info)
	return result


func _sanitized_text_info_record(text_info: Dictionary) -> Dictionary:
	return {
		"fill_style": String(text_info.get("fill_style", text_info.get("panel_style", ""))),
		"panel_style": String(text_info.get("panel_style", text_info.get("fill_style", ""))),
		"font": String(text_info.get("font_id", "")),
		"font_id": String(text_info.get("font_id", "")),
		"text_material_id": String(text_info.get("text_material_id", "")),
		"speed": text_info.get("source_speed", text_info.get("table_speed", 0)),
		"table_speed": text_info.get("table_speed", 0),
		"effective_speed_source": String(text_info.get("effective_speed_source", "")),
		"can_ab_speed_up_print": bool(text_info.get("can_ab_speed_up_print", false)),
		"source_fit_width_px": text_info.get("source_fit_width_px", null),
		"source_status": String(text_info.get("status", "")),
	}


func _generated_window_templates() -> Dictionary:
	_ensure_data_registry()
	if _data_registry == null or not _data_registry.has_method("get_battle_interface_data"):
		return {}
	var interface_data = _data_registry.get_battle_interface_data()
	if typeof(interface_data) != TYPE_DICTIONARY:
		return {}
	var templates = interface_data.get("window_templates", {})
	return templates if typeof(templates) == TYPE_DICTIONARY else {}


func _dict_or_empty(value) -> Dictionary:
	return value if typeof(value) == TYPE_DICTIONARY else {}


func _window_text_or_label(window_id: String, label: Label) -> String:
	if _window_renderer != null and _window_renderer.has_method("get_window_text"):
		var text := String(_window_renderer.get_window_text(window_id))
		if not text.is_empty():
			return text
	if label != null:
		return label.text
	return ""


func _source_window_renderer_status() -> String:
	if _window_renderer == null:
		return "unavailable"
	if _window_renderer.has_method("get_renderer_snapshot"):
		var snapshot = _window_renderer.get_renderer_snapshot()
		if typeof(snapshot) == TYPE_DICTIONARY:
			return String(snapshot.get("status", "first_pass"))
	return "first_pass"


func _source_window_renderer_snapshot() -> Dictionary:
	if _window_renderer != null and _window_renderer.has_method("get_renderer_snapshot"):
		var snapshot = _window_renderer.get_renderer_snapshot()
		return snapshot if typeof(snapshot) == TYPE_DICTIONARY else {}
	return {}


func _short_text(value: String, max_length: int) -> String:
	if value.length() <= max_length:
		return value
	return value.substr(0, max(0, max_length - 1)) + "."


func _array_value(value) -> Array:
	return value if typeof(value) == TYPE_ARRAY else []


func _dictionary_value(value) -> Dictionary:
	return value if typeof(value) == TYPE_DICTIONARY else {}


func _ensure_data_registry() -> void:
	if _data_registry != null:
		return
	if _battle_engine != null and _battle_engine.has_method("_get_registry"):
		var registry = _battle_engine._get_registry()
		if registry != null:
			_data_registry = registry
			return
	if has_node("/root/DataRegistry"):
		_data_registry = get_node("/root/DataRegistry")


func _configure_window_renderer() -> void:
	if _window_renderer == null or _data_registry == null:
		return
	if _window_renderer.has_method("configure_data_registry"):
		_window_renderer.configure_data_registry(_data_registry)
