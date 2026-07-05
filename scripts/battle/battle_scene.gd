extends Control

signal battle_finished(result: Dictionary)

const VIEWPORT_SIZE := Vector2(240, 160)
const BATTLE_WINDOW_RENDERER_SCRIPT := preload("res://scripts/battle/battle_window_renderer.gd")
const TILE_SIZE := 8
const DISPLAY_HEIGHT := 160
const FONT_SIZE := 8
const HP_BAR_PIXELS := 48
const HP_BAR_HEIGHT := 2
const HP_GREEN_TOP := Color8(90, 214, 132, 255)
const HP_GREEN_BOTTOM := Color8(115, 255, 173, 255)
const HP_YELLOW_TOP := Color8(205, 172, 8, 255)
const HP_YELLOW_BOTTOM := Color8(255, 230, 57, 255)
const HP_RED_TOP := Color8(172, 65, 74, 255)
const HP_RED_BOTTOM := Color8(255, 90, 57, 255)
const HP_BAR_OUTLINE := Color8(82, 107, 90, 255)
const PRESENTATION_STATUS := "first_slice_not_source_equivalent"
const PRESENTATION_ASSET_LAYOUT_STATUS := "exported_asset_layout_first_pass"
const SOURCE_FLOW_STATUS := "source_action_move_window_flow_first_pass"
const SOURCE_BATTLE_TEXT_CONTROLLER_CONTEXT_STATUS := "source_battle_text_controller_context_first_pass"
const BATTLE_INPUT_STATUS := "keyboard_input_first_pass"
const BG0_Y_ACTION_CHOOSE := DISPLAY_HEIGHT
const BG0_Y_MOVE_CHOOSE := DISPLAY_HEIGHT * 2
const ACTION_FIGHT := "fight"
const ACTION_PARTY := "party"
const ACTION_BAG := "bag"
const ACTION_RUN := "run"
const ACTION_ORDER := [ACTION_FIGHT, ACTION_BAG, ACTION_PARTY, ACTION_RUN]
const PHASE_INTRO := "intro_message"
const PHASE_ACTION_SELECT := "action_select"
const PHASE_MOVE_SELECT := "move_select"
const PHASE_TURN_MESSAGE := "turn_message"
const PHASE_FINISHED := "finished"
const STRINGID_INTROMSG := "STRINGID_INTROMSG"
const DEFAULT_BATTLE_ENVIRONMENT := "BATTLE_ENVIRONMENT_GRASS"
const BACKGROUND_ZERO_KEY_SHADER_CODE := """
shader_type canvas_item;
void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	if (tex.a > 0.99 && tex.r < 0.01 && tex.g < 0.01 && tex.b < 0.01) {
		discard;
	}
	COLOR = tex * COLOR;
}
"""

const SCREEN_ASSET_RECTS := {
	"environment_background": [0, 0, 240, 112],
	"environment_background_region": [0, 0, 240, 112],
	"environment_entry": [0, 65, 240, 47],
	"environment_entry_region": [0, 65, 240, 47],
	"player_sprite": [32, 56, 64, 64],
	"opponent_sprite": [144, 30, 64, 64],
	"opponent_shadow": [160, 70, 32, 8],
	"opponent_healthbox": [12, 14, 128, 32],
	"player_healthbox": [128, 74, 128, 64],
	"opponent_hp_bar": [52, 33, 48, 2],
	"player_hp_bar": [174, 92, 48, 2],
	"opponent_name": [17, 17, 88, 10],
	"opponent_hp_label": [36, 29, 18, 10],
	"player_name": [143, 78, 82, 10],
	"player_hp_label": [174, 99, 60, 10],
}

const SOURCE_SCENE_LAYOUT_PROFILE := {
	"status": "measured_full_scene_layout_first_pass",
	"profile": "emerald_2011_zh",
	"basis": "assets/source/battle_scene_captures/emerald_2011_zh",
	"source_capture_count": 24,
	"measured_key_frames": {
		"capture_00_action_menu": {
			"opponent_hp_green_rect": [52, 33, 48, 2],
			"player_hp_green_rect": [174, 92, 48, 2],
			"action_prompt_red_frame_rect": [1, 115, 119, 42],
			"action_prompt_body_rect": [8, 117, 112, 38],
		},
		"capture_02_move_message": {
			"message_red_frame_rect": [1, 115, 238, 42],
			"message_body_rect": [8, 117, 224, 38],
		},
		"capture_23_send_out_complete": {
			"opponent_hp_green_rect": [52, 33, 48, 2],
			"player_hp_green_rect": [179, 91, 48, 2],
		},
	},
	"runtime_rect_policy": "use_capture_00_action_menu_static_rects_until_healthbox_subsprite_runtime",
	"hp_bar_policy": "source_capture_two_row_color_first_pass",
	"window_exact_capture_policy": "separate_action_message_move_window_layer_pngs",
}

const ACTION_CURSOR_POSITIONS := {
	ACTION_FIGHT: [137, 122],
	ACTION_BAG: [193, 122],
	ACTION_PARTY: [137, 138],
	ACTION_RUN: [193, 138],
}

const MOVE_CURSOR_POSITIONS := [
	[17, 122],
	[89, 122],
	[17, 138],
	[89, 138],
]

const BATTLE_PRESENTATION_ASSET_RULES := {
	"asset_status": PRESENTATION_ASSET_LAYOUT_STATUS,
	"runtime_image_policy": "exported_rgba_textures_only",
	"environment_policy": "use_generated_battle_environment_texture_with_zero_rgb_discard_material_first_pass",
	"pokemon_sprite_policy": "use_generated_battle_sprite_pngs_first_frame_static",
	"front_sprite_frame_policy": "front_png_first_64x64_frame_until_source_animation_runtime",
	"healthbox_policy": "use_generated_healthbox_frame_pngs_at_screenshot_aligned_rects",
	"hp_bar_policy": "source_capture_two_row_color_fill_over_generated_healthbox_first_pass",
	"audio_policy": "metadata_only",
	"source_equivalence": "not_claimed",
}

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

const SOURCE_SCENE_CAPTURE_PROFILE := {
	"status": "full_scene_source_profile",
	"profile": "emerald_2011_zh",
	"root": "assets/source/battle_scene_captures/emerald_2011_zh",
	"capture_count": 24,
	"viewport_size": [240, 160],
	"purpose": "full_battle_scene_layout_profile",
	"window_exact_capture_root": "assets/source/battle_window_captures",
	"window_exact_capture_policy": "separate_action_message_move_window_layer_pngs",
	"key_frames": {
		"action_menu": "capture_00.png",
		"move_menu": "capture_01.png",
		"move_message": "capture_02.png",
		"grass_intro": "capture_12.png",
		"send_out_ball": "capture_16.png",
		"send_out_complete": "capture_23.png",
	},
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
var _selected_action_id := ACTION_FIGHT
var _battle_input_count := 0

var _battle_backdrop: ColorRect
var _environment_background: TextureRect
var _environment_entry: TextureRect
var _opponent_shadow: TextureRect
var _opponent_sprite: TextureRect
var _player_sprite: TextureRect
var _opponent_healthbox_texture: TextureRect
var _player_healthbox_texture: TextureRect
var _opponent_name_label: Label
var _opponent_hp_label: Label
var _opponent_hp_fill: Control
var _player_name_label: Label
var _player_hp_label: Label
var _player_hp_fill: Control
var _message_label: Label
var _action_prompt_label: Label
var _pp_label: Label
var _pp_remaining_label: Label
var _move_type_label: Label
var _action_cursor_label: Label
var _move_cursor_label: Label
var _finish_button: Button
var _window_renderer: Control = null
var _presentation_assets_snapshot: Dictionary = {}
var _background_zero_key_material: ShaderMaterial = null


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
	_selected_action_id = ACTION_FIGHT
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


func handle_battle_input(action_name: String) -> Dictionary:
	_ensure_ui()
	var action := String(action_name)
	var before_phase := _ui_phase
	var before_mode := _ui_mode
	var result := {
		"status": "ignored",
		"input_status": BATTLE_INPUT_STATUS,
		"action": action,
		"ui_phase_before": before_phase,
		"ui_mode_before": before_mode,
	}
	match action:
		"ui_accept":
			result = _activate_current_selection()
		"ui_cancel":
			result = _cancel_current_selection()
		"ui_left":
			result = _move_current_selection(Vector2i(-1, 0))
		"ui_right":
			result = _move_current_selection(Vector2i(1, 0))
		"ui_up":
			result = _move_current_selection(Vector2i(0, -1))
		"ui_down":
			result = _move_current_selection(Vector2i(0, 1))
		_:
			result["reason"] = "unsupported_battle_input_action"
			return result
	_battle_input_count += 1
	result["input_status"] = BATTLE_INPUT_STATUS
	result["action"] = action
	result["ui_phase_before"] = before_phase
	result["ui_mode_before"] = before_mode
	result["ui_phase_after"] = _ui_phase
	result["ui_mode_after"] = _ui_mode
	result["selected_action"] = _selected_action_id
	result["selected_move_slot"] = _selected_move_slot
	_refresh_input_cursors()
	return result


func advance_intro() -> Dictionary:
	if _ui_phase != PHASE_INTRO:
		return {"status": "blocked", "ui_phase": _ui_phase}
	_ui_phase = PHASE_ACTION_SELECT
	_ui_mode = "action"
	_message_lines = []
	_refresh()
	return {"status": "ok", "ui_phase": _ui_phase}


func select_action(action_id: String) -> Dictionary:
	if ACTION_ORDER.has(action_id):
		_selected_action_id = action_id
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
		"source_scene_capture_profile": SOURCE_SCENE_CAPTURE_PROFILE.duplicate(true),
		"source_scene_layout_profile": SOURCE_SCENE_LAYOUT_PROFILE.duplicate(true),
		"source_window_text_info": _source_window_text_info_snapshot(),
		"source_battle_text_controller_context": _source_battle_text_controller_context_snapshot(),
		"source_type_display_status": _source_type_display_status(),
		"source_hp_bar_pixels": HP_BAR_PIXELS,
		"battle_presentation_assets": _battle_presentation_assets_snapshot(),
		"battle_input": _battle_input_snapshot(),
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

	_battle_backdrop = ColorRect.new()
	_battle_backdrop.color = Color8(197, 238, 189)
	_battle_backdrop.position = Vector2.ZERO
	_battle_backdrop.size = VIEWPORT_SIZE
	add_child(_battle_backdrop)

	_environment_background = _add_texture_rect("EnvironmentBackground", _rect_from_array(SCREEN_ASSET_RECTS["environment_background"]))
	_environment_background.material = _background_zero_key_shader_material()
	_environment_entry = _add_texture_rect("EnvironmentEntry", _rect_from_array(SCREEN_ASSET_RECTS["environment_entry"]))
	_environment_entry.visible = false
	_opponent_shadow = _add_texture_rect("OpponentShadow", _rect_from_array(SCREEN_ASSET_RECTS["opponent_shadow"]))
	_opponent_sprite = _add_texture_rect("OpponentSprite", _rect_from_array(SCREEN_ASSET_RECTS["opponent_sprite"]))
	_player_sprite = _add_texture_rect("PlayerSprite", _rect_from_array(SCREEN_ASSET_RECTS["player_sprite"]))
	_opponent_healthbox_texture = _add_texture_rect("OpponentHealthbox", _rect_from_array(SCREEN_ASSET_RECTS["opponent_healthbox"]))
	_player_healthbox_texture = _add_texture_rect("PlayerHealthbox", _rect_from_array(SCREEN_ASSET_RECTS["player_healthbox"]))

	_window_renderer = BATTLE_WINDOW_RENDERER_SCRIPT.new()
	_window_renderer.name = "BattleWindowRenderer"
	_window_renderer.position = Vector2.ZERO
	_window_renderer.size = VIEWPORT_SIZE
	_window_renderer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_window_renderer)
	_configure_window_renderer()

	_opponent_name_label = _add_label(_rect_from_array(SCREEN_ASSET_RECTS["opponent_name"]), "")
	_opponent_hp_label = _add_label(_rect_from_array(SCREEN_ASSET_RECTS["opponent_hp_label"]), "HP")
	_opponent_hp_fill = _add_hp_bar(_rect_from_array(SCREEN_ASSET_RECTS["opponent_hp_bar"]))
	_player_name_label = _add_label(_rect_from_array(SCREEN_ASSET_RECTS["player_name"]), "")
	_player_hp_label = _add_label(_rect_from_array(SCREEN_ASSET_RECTS["player_hp_label"]), "")
	_player_hp_fill = _add_hp_bar(_rect_from_array(SCREEN_ASSET_RECTS["player_hp_bar"]))
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
	_action_cursor_label = _add_label(Rect2(Vector2.ZERO, Vector2(8, 10)), ">")
	_move_cursor_label = _add_label(Rect2(Vector2.ZERO, Vector2(8, 10)), ">")

	_finish_button = Button.new()
	_finish_button.position = Vector2(128, 148)
	_finish_button.size = Vector2(104, 10)
	_finish_button.text = "Return"
	_finish_button.focus_mode = Control.FOCUS_NONE
	_finish_button.add_theme_font_size_override("font_size", FONT_SIZE)
	_finish_button.pressed.connect(_on_finish_pressed)
	add_child(_finish_button)


func _unhandled_input(event: InputEvent) -> void:
	if event == null or not is_visible_in_tree():
		return
	for action in ["ui_accept", "ui_cancel", "ui_left", "ui_right", "ui_up", "ui_down"]:
		if event.is_action_pressed(action):
			var result := handle_battle_input(action)
			if String(result.get("status", "")) != "ignored":
				get_viewport().set_input_as_handled()
			return


func _activate_current_selection() -> Dictionary:
	if _ui_phase == PHASE_INTRO:
		return advance_intro()
	if _ui_phase == PHASE_ACTION_SELECT:
		return select_action(_selected_action_id)
	if _ui_phase == PHASE_MOVE_SELECT:
		return play_player_move(_selected_move_slot)
	if _ui_phase == PHASE_FINISHED and _finish_button != null and _finish_button.visible:
		_on_finish_pressed()
		return {"status": "ok", "ui_phase": _ui_phase, "action": "finish"}
	return {"status": "blocked", "reason": "no_active_battle_input_target", "ui_phase": _ui_phase}


func _cancel_current_selection() -> Dictionary:
	if _ui_phase == PHASE_MOVE_SELECT:
		_ui_mode = "action"
		_ui_phase = PHASE_ACTION_SELECT
		_message_lines = []
		_selected_action_id = ACTION_FIGHT
		_refresh()
		return {"status": "ok", "ui_phase": _ui_phase, "ui_mode": _ui_mode}
	return {"status": "blocked", "reason": "battle_cancel_not_available", "ui_phase": _ui_phase}


func _move_current_selection(delta: Vector2i) -> Dictionary:
	if _ui_phase == PHASE_ACTION_SELECT:
		_selected_action_id = _move_action_selection(delta)
		_refresh_input_cursors()
		return {"status": "ok", "ui_phase": _ui_phase, "selected_action": _selected_action_id}
	if _ui_phase == PHASE_MOVE_SELECT:
		_selected_move_slot = _move_slot_selection(delta)
		_refresh_move_selection_metadata(_active_mon("player"))
		_refresh_input_cursors()
		_refresh_window_renderer(_active_mon("player"), false, false, true)
		return {"status": "ok", "ui_phase": _ui_phase, "selected_move_slot": _selected_move_slot}
	return {"status": "blocked", "reason": "battle_direction_not_available", "ui_phase": _ui_phase}


func _move_action_selection(delta: Vector2i) -> String:
	var index := ACTION_ORDER.find(_selected_action_id)
	if index < 0:
		index = 0
	var col := clampi(index % 2 + delta.x, 0, 1)
	var row := clampi(floori(float(index) / 2.0) + delta.y, 0, 1)
	return String(ACTION_ORDER[row * 2 + col])


func _move_slot_selection(delta: Vector2i) -> int:
	var moves := _array_value(_active_mon("player").get("moves", []))
	var usable_count = mini(4, max(1, moves.size()))
	var index := clampi(_selected_move_slot, 0, usable_count - 1)
	var col := index % 2
	var row := floori(float(index) / 2.0)
	var next := clampi((row + delta.y), 0, 1) * 2 + clampi(col + delta.x, 0, 1)
	if next >= usable_count:
		return index
	return next


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
	_refresh_presentation_assets(player_mon, opponent_mon)
	_player_name_label.text = _mon_title(player_mon)
	_player_hp_label.text = _hp_text(player_mon)
	_set_hp_fill(_player_hp_fill, player_mon)
	_opponent_name_label.text = _mon_title(opponent_mon)
	_opponent_hp_label.text = "HP"
	_set_hp_fill(_opponent_hp_fill, opponent_mon)
	_message_label.text = "\n".join(_message_lines.slice(max(0, _message_lines.size() - 4), _message_lines.size()))
	_refresh_bottom_windows(player_mon)
	_refresh_input_cursors()


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
		_window_renderer.show_message_window(_message_label.text, true, _battle_text_controller_options())
	elif action_visible:
		var prompt_mon_name := _action_prompt_mon_name(player_mon)
		_window_renderer.show_action_windows(
			_action_prompt_text(player_mon),
			_battle_menu_text_for_renderer(),
			_battle_text_options_with_controller(_source_battle_text_printer_options("gText_WhatWillPkmnDo", {"{B_BUFF1}": prompt_mon_name})),
			_battle_text_options_with_controller(_source_battle_text_printer_options("gText_BattleMenu"))
		)
	elif move_visible:
		var move_type_suffix := _move_type_suffix_for_selected(player_mon)
		_window_renderer.show_move_windows(
			_move_labels_for_renderer(player_mon),
			_source_battle_text("gText_MoveInterfacePP"),
			_pp_remaining_text(player_mon),
			_move_type_text_for_selected(player_mon),
			_move_text_printer_options_by_window(move_type_suffix)
		)
	else:
		_window_renderer.clear_windows()


func _refresh_presentation_assets(player_mon: Dictionary, opponent_mon: Dictionary) -> void:
	var environment_record := _battle_environment_record()
	var background_asset := _dict_or_empty(environment_record.get("background", {}))
	var entry_asset := _dict_or_empty(environment_record.get("entry", {}))
	var player_sprite_record := _pokemon_sprite_record(player_mon)
	var opponent_sprite_record := _pokemon_sprite_record(opponent_mon)
	var player_sprite_asset := _dict_or_empty(player_sprite_record.get("back", {}))
	var opponent_sprite_asset := _dict_or_empty(opponent_sprite_record.get("front", {}))
	var player_healthbox_asset := _battle_interface_texture_record("healthbox_singles_player")
	var opponent_healthbox_asset := _battle_interface_texture_record("healthbox_singles_opponent")
	var shadow_asset := _battle_interface_texture_record("enemy_mon_shadow")

	_apply_texture_asset(
		_environment_background,
		background_asset,
		_rect_from_array(SCREEN_ASSET_RECTS["environment_background"]),
		_rect_from_array(SCREEN_ASSET_RECTS["environment_background_region"])
	)
	var entry_visible := _should_show_environment_entry()
	_apply_texture_asset(
		_environment_entry,
		entry_asset,
		_rect_from_array(SCREEN_ASSET_RECTS["environment_entry"]),
		_rect_from_array(SCREEN_ASSET_RECTS["environment_entry_region"])
	)
	_environment_entry.visible = entry_visible and _environment_entry.texture != null
	_apply_texture_asset(_opponent_shadow, shadow_asset, _rect_from_array(SCREEN_ASSET_RECTS["opponent_shadow"]))
	_apply_texture_asset(_player_sprite, player_sprite_asset, _rect_from_array(SCREEN_ASSET_RECTS["player_sprite"]))
	_apply_texture_asset(
		_opponent_sprite,
		opponent_sprite_asset,
		_rect_from_array(SCREEN_ASSET_RECTS["opponent_sprite"]),
		Rect2(0, 0, 64, 64)
	)
	_apply_texture_asset(_opponent_healthbox_texture, opponent_healthbox_asset, _rect_from_array(SCREEN_ASSET_RECTS["opponent_healthbox"]))
	_apply_texture_asset(_player_healthbox_texture, player_healthbox_asset, _rect_from_array(SCREEN_ASSET_RECTS["player_healthbox"]))

	_presentation_assets_snapshot = {
		"status": PRESENTATION_ASSET_LAYOUT_STATUS,
		"asset_rules": BATTLE_PRESENTATION_ASSET_RULES.duplicate(true),
		"layout_basis": "2011_zh_capture_aligned_first_pass_plus_source_metadata",
		"loaded_asset_count": _loaded_presentation_asset_count(),
		"environment": {
			"symbol": String(environment_record.get("symbol", DEFAULT_BATTLE_ENVIRONMENT)),
			"background_path": _asset_project_path(background_asset),
			"background_screen_rect": _rect_array(_rect_from_array(SCREEN_ASSET_RECTS["environment_background"])),
			"background_region_rect": _rect_array(_rect_from_array(SCREEN_ASSET_RECTS["environment_background_region"])),
			"background_material": "zero_rgb_discard_first_pass",
			"entry_path": _asset_project_path(entry_asset),
			"entry_visible": entry_visible,
			"entry_screen_rect": _rect_array(_rect_from_array(SCREEN_ASSET_RECTS["environment_entry"])),
			"entry_region_rect": _rect_array(_rect_from_array(SCREEN_ASSET_RECTS["environment_entry_region"])),
		},
		"battlers": {
			"player": _presentation_battler_snapshot(player_mon, player_sprite_asset, _rect_from_array(SCREEN_ASSET_RECTS["player_sprite"]), "back"),
			"opponent": _presentation_battler_snapshot(opponent_mon, opponent_sprite_asset, _rect_from_array(SCREEN_ASSET_RECTS["opponent_sprite"]), "front"),
		},
		"healthboxes": {
			"player": _presentation_asset_rect_snapshot(player_healthbox_asset, _rect_from_array(SCREEN_ASSET_RECTS["player_healthbox"])),
			"opponent": _presentation_asset_rect_snapshot(opponent_healthbox_asset, _rect_from_array(SCREEN_ASSET_RECTS["opponent_healthbox"])),
			"source_sprite_origin_coords": SOURCE_HEALTHBOX_COORDS.duplicate(true),
			"screen_rect_policy": "screenshot_aligned_until_subsprite_healthbox_runtime",
		},
		"hp_bars": {
			"player": _rect_array(_rect_from_array(SCREEN_ASSET_RECTS["player_hp_bar"])),
			"opponent": _rect_array(_rect_from_array(SCREEN_ASSET_RECTS["opponent_hp_bar"])),
			"width_px": HP_BAR_PIXELS,
			"height_px": HP_BAR_HEIGHT,
			"fill_style": "source_capture_two_row_color_first_pass",
			"hp_fill_rgba_rows": {
				"green": [[90, 214, 132, 255], [115, 255, 173, 255]],
				"yellow": [[205, 172, 8, 255], [255, 230, 57, 255]],
				"red": [[172, 65, 74, 255], [255, 90, 57, 255]],
			},
			"layout_profile": SOURCE_SCENE_LAYOUT_PROFILE.duplicate(true),
		},
		"shadow": _presentation_asset_rect_snapshot(shadow_asset, _rect_from_array(SCREEN_ASSET_RECTS["opponent_shadow"])),
	}


func _battle_environment_record() -> Dictionary:
	_ensure_data_registry()
	var environment_symbol := String(_battle_state.get("battle_environment", _sequence.get("battle_environment", "")))
	if environment_symbol.is_empty():
		environment_symbol = String(_battle_state.get("battle_environment_symbol", _sequence.get("battle_environment_symbol", "")))
	if environment_symbol.is_empty():
		environment_symbol = DEFAULT_BATTLE_ENVIRONMENT
	if _data_registry != null and _data_registry.has_method("get_battle_environment_record"):
		var record = _data_registry.get_battle_environment_record(environment_symbol)
		if typeof(record) == TYPE_DICTIONARY and not record.is_empty():
			return record
	return {"symbol": environment_symbol}


func _pokemon_sprite_record(mon: Dictionary) -> Dictionary:
	var species_symbol := _mon_species_symbol(mon)
	if species_symbol.is_empty():
		return {}
	_ensure_data_registry()
	if _data_registry != null and _data_registry.has_method("get_pokemon_battle_sprite_record"):
		var record = _data_registry.get_pokemon_battle_sprite_record(species_symbol)
		if typeof(record) == TYPE_DICTIONARY:
			return record
	return {}


func _battle_interface_texture_record(asset_id: String) -> Dictionary:
	_ensure_data_registry()
	if _data_registry != null and _data_registry.has_method("get_battle_interface_texture_record"):
		var record = _data_registry.get_battle_interface_texture_record(asset_id)
		if typeof(record) == TYPE_DICTIONARY:
			return record
	return {}


func _mon_species_symbol(mon: Dictionary) -> String:
	for key in ["species", "species_symbol", "symbol"]:
		var value := String(mon.get(key, ""))
		if value.is_empty():
			continue
		if value.begins_with("SPECIES_"):
			return value
		return "SPECIES_%s" % value.to_upper()
	return ""


func _should_show_environment_entry() -> bool:
	return String(_sequence.get("battle_kind", _battle_state.get("battle_kind", ""))) == "wild" and _ui_phase == PHASE_INTRO


func _apply_texture_asset(target: TextureRect, asset: Dictionary, rect: Rect2, region: Rect2 = Rect2()) -> void:
	if target == null:
		return
	target.position = rect.position
	target.size = rect.size
	var texture := _load_texture_for_asset(asset)
	if texture != null and region.size.x > 0 and region.size.y > 0:
		var atlas := AtlasTexture.new()
		atlas.atlas = texture
		atlas.region = region
		texture = atlas
	target.texture = texture
	target.visible = target.texture != null


func _load_texture_for_asset(asset: Dictionary) -> Texture2D:
	var path := _asset_resource_path(asset)
	if path.is_empty():
		return null
	var texture = load(path)
	return texture if texture is Texture2D else null


func _asset_resource_path(asset: Dictionary) -> String:
	var path := String(asset.get("image", ""))
	if not path.is_empty():
		return path
	var project_path := String(asset.get("image_project_path", ""))
	if project_path.is_empty():
		return ""
	return "res://%s" % project_path


func _asset_project_path(asset: Dictionary) -> String:
	var project_path := String(asset.get("image_project_path", ""))
	if not project_path.is_empty():
		return project_path
	var path := String(asset.get("image", ""))
	if path.begins_with("res://"):
		return path.trim_prefix("res://")
	return path


func _presentation_battler_snapshot(mon: Dictionary, asset: Dictionary, rect: Rect2, sprite_side: String) -> Dictionary:
	var result := _presentation_asset_rect_snapshot(asset, rect)
	result["species"] = _mon_species_symbol(mon)
	result["sprite_side"] = sprite_side
	if sprite_side == "front":
		result["frame_region_rect"] = [0, 0, 64, 64]
		result["frame_policy"] = "first_frame_static"
	return result


func _presentation_asset_rect_snapshot(asset: Dictionary, rect: Rect2) -> Dictionary:
	var size := _dict_or_empty(asset.get("size", asset.get("image_size", {})))
	return {
		"path": _asset_project_path(asset),
		"screen_rect": _rect_array(rect),
		"image_size": [int(size.get("w", 0)), int(size.get("h", 0))],
		"asset_status": String(asset.get("status", asset.get("asset_status", ""))),
	}


func _loaded_presentation_asset_count() -> int:
	var count := 0
	for texture_rect in [
		_environment_background,
		_environment_entry,
		_opponent_shadow,
		_opponent_sprite,
		_player_sprite,
		_opponent_healthbox_texture,
		_player_healthbox_texture,
	]:
		if texture_rect != null and texture_rect.texture != null:
			count += 1
	return count


func _battle_presentation_assets_snapshot() -> Dictionary:
	return _presentation_assets_snapshot.duplicate(true)


func _battle_input_snapshot() -> Dictionary:
	return {
		"status": BATTLE_INPUT_STATUS,
		"selected_action": _selected_action_id,
		"selected_move_slot": _selected_move_slot,
		"handled_input_count": _battle_input_count,
		"supported_actions": ["ui_accept", "ui_cancel", "ui_left", "ui_right", "ui_up", "ui_down"],
		"action_order": ACTION_ORDER.duplicate(),
	}


func _refresh_input_cursors() -> void:
	if _action_cursor_label == null or _move_cursor_label == null:
		return
	_action_cursor_label.visible = _ui_phase == PHASE_ACTION_SELECT and _last_result.is_empty()
	_move_cursor_label.visible = _ui_phase == PHASE_MOVE_SELECT and _last_result.is_empty()
	if _action_cursor_label.visible:
		_action_cursor_label.position = _vector_from_array(ACTION_CURSOR_POSITIONS.get(_selected_action_id, ACTION_CURSOR_POSITIONS[ACTION_FIGHT]))
	if _move_cursor_label.visible:
		var move_index := clampi(_selected_move_slot, 0, MOVE_CURSOR_POSITIONS.size() - 1)
		_move_cursor_label.position = _vector_from_array(MOVE_CURSOR_POSITIONS[move_index])


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
		"src/data/graphics/battle_environment.h",
		"src/battle_interface.c",
		"src/battle_interface.c:sBattlerHealthboxCoords",
		"src/battle_controller_player.c",
		"src/battle_controller_player.c:MoveSelectionDisplayMoveType",
		"src/data/graphics/pokemon.h",
		"src/data/types_info.h:gTypesInfo",
		"src/battle_message.c",
		"src/battle_message.c:sTextOnWindowsInfo_Normal",
		"src/battle_setup.c:%s" % _field_resume_callback(),
	]


func _battle_scene_unsupported() -> Array:
	var unsupported := [{
		"code": "battle_scene_not_source_equivalent",
		"source": "src/battle_main.c:CB2_InitBattle",
		"detail": "This scene is a debug vertical slice. It now places first-pass exported battle assets, but does not recreate the exact source battle tilemaps, sprite animation, healthbox subtasks, audio, or callback/task flow.",
	}, {
		"code": "battle_ui_windows_not_source_equivalent",
		"source": "src/battle_interface.c; src/battle_controller_player.c; src/battle_message.c",
		"detail": "The first pass now follows source action/move window ids, BG0 scroll offsets, text symbols, HP bar width, and static exported healthbox frame PNGs, but exact text pixels, cursor sprites, healthbox subtasks, and full controller flow remain pending.",
	}, {
		"code": "battle_presentation_asset_layout_first_pass",
		"source": "src/battle_bg.c; src/battle_interface.c; src/data/graphics/pokemon.h",
		"detail": "Generated RGBA environment, Pokemon, shadow, and healthbox textures are placed in screenshot-aligned single-battle rects. Exact background scrolling, entry playback, Pokemon sprite offsets/elevation, and healthbox slide animation are still pending.",
	}, {
		"code": "battle_action_menu_partial",
		"source": "src/battle_controller_player.c:PlayerHandleChooseAction; src/battle_controller_player.c:HandleInputChooseAction",
		"detail": "The source Fight/Pokémon/Bag/Run action menu is visible, but only Fight is interactive in this slice.",
	}, {
		"code": "battle_healthbox_sprites_static_first_pass",
		"source": "src/battle_interface.c:CreateBattlerHealthboxSprites",
		"detail": "Generated healthbox frame PNGs are displayed statically. Source healthbox subtasks, right-side sprite composition, slide-in, status icons, and exact number glyphs remain future work.",
	}, {
		"code": "battle_keyboard_input_first_pass",
		"source": "src/battle_controller_player.c:PlayerHandleChooseAction",
		"detail": "Godot ui_accept/ui_cancel/directional actions now drive the debug BattleScene menus. Exact source cursor sprite playback, repeat timing, and button sound effects remain pending.",
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


func _battle_text_controller_context_data() -> Dictionary:
	var result := {}
	result.merge(_dictionary_value(_sequence.get("battle_text_context", {})), true)
	result.merge(_dictionary_value(_sequence.get("battle_text_options", {})), true)
	result.merge(_dictionary_value(_battle_state.get("battle_text_context", {})), true)
	result.merge(_dictionary_value(_battle_state.get("battle_text_options", {})), true)
	for key in [
		"battle_type_flags",
		"battle_text_mode",
		"battle_type_link",
		"battle_type_recorded",
		"battle_type_recorded_link",
		"battle_type_pokedude",
		"test_runner_enabled",
		"recorded_text_speed_index",
		"battle_text_speed_override",
		"player_text_speed",
		"auto_scroll",
	]:
		if _sequence.has(key):
			result[key] = _sequence[key]
		if _battle_state.has(key):
			result[key] = _battle_state[key]
	return result


func _battle_text_controller_options() -> Dictionary:
	var context := _battle_text_controller_context_data()
	var flags := _battle_type_flags_from_context(context)
	var mode := String(context.get("battle_text_mode", context.get("mode", ""))).to_lower()
	if mode.is_empty():
		mode = _battle_text_mode_from_flags(flags)
	var options := {}
	if not mode.is_empty():
		options["battle_text_mode"] = mode
	if bool(context.get("battle_type_link", false)) or flags.has("BATTLE_TYPE_LINK"):
		options["battle_type_link"] = true
	if bool(context.get("battle_type_recorded", false)) or flags.has("BATTLE_TYPE_RECORDED"):
		options["battle_type_recorded"] = true
	if bool(context.get("battle_type_recorded_link", false)) or flags.has("BATTLE_TYPE_RECORDED_LINK"):
		options["battle_type_recorded_link"] = true
	if bool(context.get("battle_type_pokedude", false)) or flags.has("BATTLE_TYPE_POKEDUDE"):
		options["battle_type_pokedude"] = true
	if context.has("test_runner_enabled"):
		options["test_runner_enabled"] = bool(context.get("test_runner_enabled", false))
	if context.has("recorded_text_speed_index"):
		options["recorded_text_speed_index"] = int(context.get("recorded_text_speed_index", 0))
	if context.has("battle_text_speed_override"):
		options["battle_text_speed_override"] = int(context.get("battle_text_speed_override", 0))
	if context.has("player_text_speed"):
		options["player_text_speed"] = String(context.get("player_text_speed", ""))
	if context.has("auto_scroll"):
		options["auto_scroll"] = bool(context.get("auto_scroll", false))
	return options


func _battle_text_options_with_controller(options: Dictionary = {}) -> Dictionary:
	var merged := _battle_text_controller_options()
	merged.merge(options, true)
	return merged


func _move_text_printer_options_by_window(move_type_suffix: String) -> Dictionary:
	var result := {}
	for window_id in [
		"B_WIN_MOVE_NAME_1",
		"B_WIN_MOVE_NAME_2",
		"B_WIN_MOVE_NAME_3",
		"B_WIN_MOVE_NAME_4",
		"B_WIN_PP",
		"B_WIN_PP_REMAINING",
		"B_WIN_MOVE_TYPE",
	]:
		result[window_id] = _battle_text_options_with_controller()
	result["B_WIN_PP"] = _battle_text_options_with_controller(_source_battle_text_printer_options("gText_MoveInterfacePP"))
	result["B_WIN_MOVE_TYPE"] = _battle_text_options_with_controller(_source_battle_text_printer_options("gText_MoveInterfaceType", {}, move_type_suffix))
	return result


func _battle_type_flags_from_context(context: Dictionary) -> Array:
	var flags: Array = []
	var raw_flags = context.get("battle_type_flags", _battle_state.get("battle_type_flags", []))
	if typeof(raw_flags) == TYPE_ARRAY:
		for flag in raw_flags:
			flags.append(String(flag))
	elif typeof(raw_flags) == TYPE_DICTIONARY:
		for flag in raw_flags.keys():
			if bool(raw_flags[flag]):
				flags.append(String(flag))
	elif typeof(raw_flags) == TYPE_STRING:
		for flag_text in String(raw_flags).replace("|", ",").split(",", false):
			var flag := String(flag_text).strip_edges()
			if not flag.is_empty():
				flags.append(flag)
	return flags


func _battle_text_mode_from_flags(flags: Array) -> String:
	if flags.has("BATTLE_TYPE_LINK"):
		return "link"
	if flags.has("BATTLE_TYPE_RECORDED_LINK"):
		return "recorded_link"
	if flags.has("BATTLE_TYPE_RECORDED"):
		return "recorded"
	if flags.has("BATTLE_TYPE_POKEDUDE"):
		return "pokedude"
	return ""


func _source_battle_text_controller_context_snapshot() -> Dictionary:
	var context := _battle_text_controller_context_data()
	var options := _battle_text_controller_options()
	var flags := _battle_type_flags_from_context(context)
	return {
		"status": SOURCE_BATTLE_TEXT_CONTROLLER_CONTEXT_STATUS,
		"source": "src/battle_message.c:BattlePutTextOnWindow",
		"wait_source": "src/text.c:TextPrinterWaitWithDownArrow",
		"battle_type_flags": flags,
		"battle_text_mode": String(options.get("battle_text_mode", "")),
		"battle_type_link": bool(options.get("battle_type_link", false)),
		"battle_type_recorded": bool(options.get("battle_type_recorded", false)),
		"battle_type_recorded_link": bool(options.get("battle_type_recorded_link", false)),
		"battle_type_pokedude": bool(options.get("battle_type_pokedude", false)),
		"test_runner_enabled": bool(options.get("test_runner_enabled", false)),
		"recorded_text_speed_index": int(options.get("recorded_text_speed_index", -1)),
		"auto_scroll_option": bool(options.get("auto_scroll", false)),
		"message_window_speed_source": "src/battle_message.c:BattlePutTextOnWindow:message_window_speed_branch",
		"auto_scroll_source": "src/battle_message.c:BattlePutTextOnWindow:gTextFlags.autoScroll",
		"unsupported": [
			"battle_text_full_link_recorded_controller_flow_pending",
		],
	}


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


func _set_hp_fill(fill: Control, mon: Dictionary) -> void:
	if fill == null:
		return
	var max_hp: int = max(1, int(mon.get("max_hp", 1)))
	var hp: int = clampi(int(mon.get("hp", 0)), 0, max_hp)
	var ratio: float = float(hp) / float(max_hp)
	fill.size.x = roundi(float(HP_BAR_PIXELS) * ratio)
	var colors := _hp_bar_colors(ratio)
	var top := fill.get_node_or_null("Top") as ColorRect
	var bottom := fill.get_node_or_null("Bottom") as ColorRect
	if top != null:
		top.color = colors[0]
		top.size = Vector2(fill.size.x, 1)
	if bottom != null:
		bottom.color = colors[1]
		bottom.position = Vector2(0, 1)
		bottom.size = Vector2(fill.size.x, 1)


func _hp_bar_colors(ratio: float) -> Array:
	if ratio <= 0.2:
		return [HP_RED_TOP, HP_RED_BOTTOM]
	if ratio <= 0.5:
		return [HP_YELLOW_TOP, HP_YELLOW_BOTTOM]
	return [HP_GREEN_TOP, HP_GREEN_BOTTOM]


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
	label.add_theme_color_override("font_color", Color(0.10, 0.16, 0.14, 1.0))
	add_child(label)
	return label


func _add_texture_rect(node_name: String, rect: Rect2) -> TextureRect:
	var texture_rect := TextureRect.new()
	texture_rect.name = node_name
	texture_rect.position = rect.position
	texture_rect.size = rect.size
	texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_rect.stretch_mode = TextureRect.STRETCH_SCALE
	texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	add_child(texture_rect)
	return texture_rect


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


func _add_hp_bar(rect: Rect2) -> Control:
	_add_rect(Rect2(rect.position - Vector2(1, 1), rect.size + Vector2(2, 2)), HP_BAR_OUTLINE)
	var container := Control.new()
	container.position = rect.position
	container.size = Vector2(rect.size.x, max(HP_BAR_HEIGHT, int(rect.size.y)))
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var top := ColorRect.new()
	top.name = "Top"
	top.position = Vector2.ZERO
	top.size = Vector2(rect.size.x, 1)
	top.color = HP_GREEN_TOP
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(top)
	var bottom := ColorRect.new()
	bottom.name = "Bottom"
	bottom.position = Vector2(0, 1)
	bottom.size = Vector2(rect.size.x, 1)
	bottom.color = HP_GREEN_BOTTOM
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(bottom)
	add_child(container)
	return container


func _rect_from_array(values) -> Rect2:
	var items := _array_value(values)
	if items.size() < 4:
		return Rect2()
	return Rect2(Vector2(int(items[0]), int(items[1])), Vector2(int(items[2]), int(items[3])))


func _vector_from_array(values) -> Vector2:
	var items := _array_value(values)
	if items.size() < 2:
		return Vector2.ZERO
	return Vector2(int(items[0]), int(items[1]))


func _rect_array(rect: Rect2) -> Array:
	return [int(rect.position.x), int(rect.position.y), int(rect.size.x), int(rect.size.y)]


func _background_zero_key_shader_material() -> ShaderMaterial:
	if _background_zero_key_material != null:
		return _background_zero_key_material
	var shader := Shader.new()
	shader.code = BACKGROUND_ZERO_KEY_SHADER_CODE
	_background_zero_key_material = ShaderMaterial.new()
	_background_zero_key_material.shader = shader
	return _background_zero_key_material


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
