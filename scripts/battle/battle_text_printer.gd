extends RefCounted

const STATUS := "first_pass_source_glyph_layout"
const FONT_ATLAS_PREVIEW_STATUS := "source_font_atlas_preview"
const RENDER_TEXT_COLOR_STATUS := "source_render_text_color_controls"
const RENDER_TEXT_CONTROL_STATUS := "source_render_text_control_side_effects_first_pass"
const SOURCE_WINDOW_PIXEL_EFFECT_STATUS := "source_window_pixel_effects_first_pass"
const BATTLE_TEXT_CONTEXT_STATUS := "source_battle_text_context_first_pass"
const DEFAULT_PLAYER_TEXT_SPEED := "OPTIONS_TEXT_SPEED_FAST"
const SOURCE_SPEED_PLAYER_TEXT_DELAY := "player_text_speed_delay"
const NUM_FRAMES_AUTO_SCROLL_DELAY := 49
const CHAR_PROMPT_SCROLL := 0xFA
const CHAR_PROMPT_CLEAR := 0xFB
const CHAR_DYNAMIC := 0xF7
const CHAR_KEYPAD_ICON := 0xF8
const CHAR_EXTRA_SYMBOL := 0xF9
const EXT_CTRL_CODE_BEGIN := 0xFC
const PLACEHOLDER_BEGIN := 0xFD
const CHAR_NEWLINE := 0xFE
const EOS := 0xFF
const EXT_CTRL_CODE_COLOR := 0x01
const EXT_CTRL_CODE_HIGHLIGHT := 0x02
const EXT_CTRL_CODE_SHADOW := 0x03
const EXT_CTRL_CODE_COLOR_HIGHLIGHT_SHADOW := 0x04
const EXT_CTRL_CODE_PALETTE := 0x05
const EXT_CTRL_CODE_FONT := 0x06
const EXT_CTRL_CODE_RESET_FONT := 0x07
const EXT_CTRL_CODE_PAUSE := 0x08
const EXT_CTRL_CODE_PAUSE_UNTIL_PRESS := 0x09
const EXT_CTRL_CODE_WAIT_SE := 0x0A
const EXT_CTRL_CODE_PLAY_BGM := 0x0B
const EXT_CTRL_CODE_ESCAPE := 0x0C
const EXT_CTRL_CODE_SHIFT_RIGHT := 0x0D
const EXT_CTRL_CODE_SHIFT_DOWN := 0x0E
const EXT_CTRL_CODE_FILL_WINDOW := 0x0F
const EXT_CTRL_CODE_PLAY_SE := 0x10
const EXT_CTRL_CODE_CLEAR := 0x11
const EXT_CTRL_CODE_SKIP := 0x12
const EXT_CTRL_CODE_CLEAR_TO := 0x13
const EXT_CTRL_CODE_MIN_LETTER_SPACING := 0x14
const EXT_CTRL_CODE_JPN := 0x15
const EXT_CTRL_CODE_ENG := 0x16
const EXT_CTRL_CODE_PAUSE_MUSIC := 0x17
const EXT_CTRL_CODE_RESUME_MUSIC := 0x18
const EXT_CTRL_CODE_SPEAKER := 0x19
const EXT_CTRL_CODE_ACCENT := 0x1A
const EXT_CTRL_CODE_BACKGROUND := 0x1B
const EXT_CTRL_CODE_TEXT_COLORS := 0x1C
const SOURCE_TRACE := [
	"src/battle_message.c:BattlePutTextOnWindow",
	"src/text.c:GetPlayerTextSpeedDelay",
	"src/text.c:AddTextPrinter",
	"src/text.c:RunTextPrinters",
	"src/text.c:RenderText",
	"src/text.c:PrintGlyph",
	"src/text.c:GetStringWidth",
	"src/text.c:TextPrinterWaitWithDownArrow",
	"src/chinese_text.c:IsChineseChar",
	"src/chinese_text.c:GetChineseFontWidthFunc",
]
const FIRST_PASS_UNSUPPORTED := [
	"battle_text_full_control_code_renderer_pending",
	"battle_text_full_link_recorded_controller_context_pending",
	"battle_text_screenshot_comparison_pending",
]
const AUDIO_CONTROL_COMMANDS := {
	"PLAY_SE": true,
	"WAIT_SE": true,
	"PLAY_BGM": true,
	"PLAY_FANFARE": true,
	"STOP_BGM": true,
	"FADE_BGM": true,
}
const STYLE_CONTROL_COMMANDS := {
	"BACKGROUND": true,
	"COLOR": true,
	"SHADOW": true,
	"ACCENT": true,
	"HIGHLIGHT": true,
	"COLOR_HIGHLIGHT_SHADOW": true,
	"TEXT_COLORS": true,
	"PALETTE": true,
	"FONT": true,
	"FONT_NORMAL": true,
	"FONT_MALE": true,
	"FONT_FEMALE": true,
	"RESET_FONT": true,
	"SHIFT_RIGHT": true,
	"SHIFT_DOWN": true,
	"FILL_WINDOW": true,
	"CLEAR": true,
	"SKIP": true,
	"CLEAR_TO": true,
	"MIN_LETTER_SPACING": true,
	"JPN": true,
	"ENG": true,
	"SPEAKER": true,
}
const TEXT_COLOR_NAME_TO_INDEX := {
	"TRANSPARENT": 0,
	"WHITE": 1,
	"DARK_GRAY": 2,
	"LIGHT_GRAY": 3,
	"RED": 4,
	"LIGHT_RED": 5,
	"GREEN": 6,
	"LIGHT_GREEN": 7,
	"BLUE": 8,
	"LIGHT_BLUE": 9,
	"TEXT_COLOR_TRANSPARENT": 0,
	"TEXT_COLOR_WHITE": 1,
	"TEXT_COLOR_DARK_GRAY": 2,
	"TEXT_COLOR_LIGHT_GRAY": 3,
	"TEXT_COLOR_RED": 4,
	"TEXT_COLOR_LIGHT_RED": 5,
	"TEXT_COLOR_GREEN": 6,
	"TEXT_COLOR_LIGHT_GREEN": 7,
	"TEXT_COLOR_BLUE": 8,
	"TEXT_COLOR_LIGHT_BLUE": 9,
	"TEXT_DYNAMIC_COLOR_1": 10,
	"TEXT_DYNAMIC_COLOR_2": 11,
	"TEXT_DYNAMIC_COLOR_3": 12,
	"TEXT_DYNAMIC_COLOR_4": 13,
	"TEXT_DYNAMIC_COLOR_5": 14,
	"TEXT_DYNAMIC_COLOR_6": 15,
	"DYNAMIC_COLOR_1": 10,
	"DYNAMIC_COLOR_2": 11,
	"DYNAMIC_COLOR_3": 12,
	"DYNAMIC_COLOR_4": 13,
	"DYNAMIC_COLOR_5": 14,
	"DYNAMIC_COLOR_6": 15,
	"DYNAMIC_COLOR1": 10,
	"DYNAMIC_COLOR2": 11,
	"DYNAMIC_COLOR3": 12,
	"DYNAMIC_COLOR4": 13,
	"DYNAMIC_COLOR5": 14,
	"DYNAMIC_COLOR6": 15,
}

var _window_id := ""
var _full_text := ""
var _visible_text := ""
var _visible_char_count := 0
var _delay_counter := 0
var _source_text_speed := 0
var _resolved_frame_delay := 0
var _frame_count := 0
var _render_call_count := 0
var _active := false
var _complete := true
var _synchronous_render := false
var _source_speed = 0
var _effective_speed_source := ""
var _player_text_speed := DEFAULT_PLAYER_TEXT_SPEED
var _player_text_speed_modifier := 1
var _player_text_scroll_speed := 1
var _player_text_speed_is_instant := false
var _can_ab_speed_up_print := false
var _has_print_been_sped_up := false
var _ab_speedup_count := 0
var _auto_scroll := false
var _auto_scroll_delay := 0
var _auto_scroll_source := ""
var _auto_scroll_reasons: Array = []
var _battle_text_context: Dictionary = {}
var _recorded_battle_text_speeds: Array = []
var _recorded_text_speed_index := -1
var _recorded_text_speed_value := -1
var _wait_state := ""
var _pause_counter := 0
var _down_arrow_visible := false
var _events: Array = []
var _event_index := 0
var _event_stream_source := "display_text"
var _source_text := ""
var _source_text_label := ""
var _source_bytes: Array = []
var _source_glyphs: Array = []
var _source_encoding_hex := ""
var _source_byte_control_summary := {}
var _source_byte_event_count := 0
var _source_text_control_metadata_count := 0
var _source_audio_cue_metadata_count := 0
var _source_metadata_only_count := 0
var _glyph_encoding: Dictionary = {}
var _single_byte_char_map: Dictionary = {}
var _font_metrics: Dictionary = {}
var _font_atlas_binding_count := 0
var _layout_font_id := "FONT_NORMAL"
var _layout_initial_font_id := "FONT_NORMAL"
var _render_text_initial_color_indices: Dictionary = {}
var _render_text_color_indices: Dictionary = {}
var _render_text_color_control_count := 0
var _source_window_pixel_effects: Array = []
var _pending_scroll_remaining_px := 0
var _pending_scroll_total_px := 0
var _pending_scroll_utility_counter := 0
var _layout_origin := Vector2i.ZERO
var _layout_cursor := Vector2i.ZERO
var _layout_min_letter_spacing := 0
var _layout_japanese := false
var _layout_glyphs: Array = []
var _layout_control_events: Array = []
var _layout_glyph_count := 0
var _layout_total_advance_px := 0
var _layout_line_count := 1
var _layout_max_line_width_px := 0
var _event_log: Array = []
var _control_event_count := 0
var _style_event_count := 0
var _audio_cue_count := 0
var _pause_event_count := 0
var _page_wait_count := 0
var _prompt_scroll_count := 0
var _prompt_clear_count := 0
var _wait_input_count := 0
var _wait_se_count := 0
var _unsupported: Array = []


func start(window_id: String, text: String, text_info: Dictionary, text_printer_metadata: Dictionary, options: Dictionary = {}) -> void:
	_window_id = window_id
	_full_text = _display_text(text)
	_visible_text = ""
	_visible_char_count = 0
	_delay_counter = 0
	_frame_count = 0
	_render_call_count = 0
	_active = false
	_complete = false
	_synchronous_render = false
	_has_print_been_sped_up = false
	_ab_speedup_count = 0
	_auto_scroll_source = ""
	_auto_scroll_reasons = []
	_battle_text_context = {}
	_recorded_battle_text_speeds = []
	_recorded_text_speed_index = -1
	_recorded_text_speed_value = -1
	_auto_scroll = _resolve_auto_scroll(options)
	_auto_scroll_delay = 0
	_wait_state = ""
	_pause_counter = 0
	_down_arrow_visible = false
	_source_text = String(options.get("source_text", ""))
	_source_text_label = String(options.get("source_text_label", options.get("text_label", "")))
	var source_encoding := _dictionary_value(options.get("source_encoding", {}))
	_source_bytes = _int_array_value(options.get("source_bytes", source_encoding.get("bytes", [])))
	_source_glyphs = _array_value(options.get("source_glyphs", source_encoding.get("glyphs", [])))
	_source_encoding_hex = String(options.get("source_encoding_hex", source_encoding.get("hex", "")))
	_source_byte_control_summary = _source_byte_control_summary_from_bytes(_source_bytes)
	_source_text_control_metadata_count = _array_value(options.get("text_controls", [])).size()
	_source_audio_cue_metadata_count = _array_value(options.get("audio_cues", [])).size()
	_source_metadata_only_count = _array_value(options.get("metadata_only", [])).size()
	_glyph_encoding = _dictionary_value(text_printer_metadata.get("glyph_encoding", {}))
	_single_byte_char_map = _single_byte_char_map_from_glyph_encoding(_glyph_encoding)
	_font_metrics = _resolve_font_metrics(text_info, text_printer_metadata, options)
	_layout_origin = Vector2i(int(text_info.get("text_x", 0)), int(text_info.get("text_y", 0)))
	_layout_initial_font_id = String(text_info.get("font_id", "FONT_NORMAL"))
	_render_text_initial_color_indices = _render_text_color_indices_from_text_info(text_info)
	_render_text_color_control_count = 0
	_source_window_pixel_effects = []
	_pending_scroll_remaining_px = 0
	_pending_scroll_total_px = 0
	_pending_scroll_utility_counter = 0
	_reset_layout_state(_layout_initial_font_id)
	_event_stream_source = "source_bytes" if not _source_bytes.is_empty() else ("source_text" if not _source_text.is_empty() else "display_text")
	var event_text := _strip_source_text_terminator(_source_text) if _event_stream_source == "source_text" else _full_text
	if _event_stream_source == "source_bytes":
		event_text = _strip_source_text_terminator(_source_text) if not _source_text.is_empty() else _full_text
		_events = _parse_source_byte_events(_source_bytes, event_text, _source_glyphs)
	else:
		_events = _parse_text_events(event_text, _event_stream_source)
	_source_byte_event_count = _count_source_byte_events(_events)
	_event_index = 0
	_event_log = []
	_control_event_count = 0
	_style_event_count = 0
	_audio_cue_count = 0
	_pause_event_count = 0
	_page_wait_count = 0
	_prompt_scroll_count = 0
	_prompt_clear_count = 0
	_wait_input_count = 0
	_wait_se_count = 0
	_source_speed = text_info.get("source_speed", text_info.get("table_speed", 0))
	_can_ab_speed_up_print = bool(text_info.get("can_ab_speed_up_print", false))
	_unsupported = FIRST_PASS_UNSUPPORTED.duplicate(true)
	_resolve_player_text_speed(text_printer_metadata, options)
	_resolve_frame_delay(text_info, text_printer_metadata, options)
	_battle_text_context = _build_battle_text_context(options, text_printer_metadata)
	_note_text_limitations()

	if _full_text.is_empty() or _resolved_frame_delay == 0:
		_render_events_until_blocked_or_complete(0x400)
		_synchronous_render = true
		_active = not _complete
		return

	_source_text_speed = max(0, _resolved_frame_delay - 1)
	_active = true


func advance_frames(frames: int = 1, input: Dictionary = {}) -> Dictionary:
	var frame_total: int = max(0, frames)
	for _frame_index in range(frame_total):
		_frame_count += 1
		if not _active:
			continue
		if _player_text_speed_is_instant:
			_render_events_until_blocked_or_complete(0x400, input)
			continue
		var repeats: int = max(1, _player_text_speed_modifier)
		for _repeat_index in range(repeats):
			_render_step(input)
			if not _active:
				break
	return snapshot()


func skip_to_end() -> Dictionary:
	if _complete and _event_index >= _events.size():
		_synchronous_render = true
		return snapshot()
	_render_all_remaining()
	_synchronous_render = true
	return snapshot()


func get_visible_text() -> String:
	return _visible_text


func get_full_text() -> String:
	return _full_text


func is_complete() -> bool:
	return _complete


func snapshot() -> Dictionary:
	return {
		"status": STATUS,
		"window_id": _window_id,
		"full_text_length": _full_text.length(),
		"visible_char_count": _visible_char_count,
		"visible_text": get_visible_text(),
		"is_active": _active,
		"is_complete": _complete,
		"frame_count": _frame_count,
		"render_call_count": _render_call_count,
		"delay_counter": _delay_counter,
		"source_add_text_printer_text_speed": _source_text_speed,
		"resolved_frame_delay": _resolved_frame_delay,
		"source_speed": _source_speed,
		"effective_speed_source": _effective_speed_source,
		"player_text_speed": _player_text_speed,
		"player_text_speed_modifier": _player_text_speed_modifier,
		"player_text_scroll_speed": _player_text_scroll_speed,
		"player_text_speed_is_instant": _player_text_speed_is_instant,
		"can_ab_speed_up_print": _can_ab_speed_up_print,
		"has_print_been_sped_up": _has_print_been_sped_up,
		"ab_speedup_count": _ab_speedup_count,
		"auto_scroll": _auto_scroll,
		"auto_scroll_delay": _auto_scroll_delay,
		"auto_scroll_source": _auto_scroll_source,
		"auto_scroll_reasons": _auto_scroll_reasons.duplicate(true),
		"battle_text_context_status": BATTLE_TEXT_CONTEXT_STATUS,
		"battle_text_context": _battle_text_context.duplicate(true),
		"recorded_text_speed_index": _recorded_text_speed_index,
		"recorded_text_speed_value": _recorded_text_speed_value,
		"wait_state": _wait_state,
		"pause_counter": _pause_counter,
		"down_arrow_visible": _down_arrow_visible,
		"synchronous_render": _synchronous_render,
		"event_stream_status": _event_stream_status(),
		"event_stream_source": _event_stream_source,
		"source_text": _source_text,
		"source_text_label": _source_text_label,
		"source_text_length": _source_text.length(),
		"source_byte_count": _source_bytes.size(),
		"source_glyph_count": _source_glyphs.size(),
		"source_encoding_hex": _source_encoding_hex,
		"source_byte_control_summary": _source_byte_control_summary.duplicate(true),
		"source_byte_event_count": _source_byte_event_count,
		"source_text_control_metadata_count": _source_text_control_metadata_count,
		"source_audio_cue_metadata_count": _source_audio_cue_metadata_count,
		"source_metadata_only_count": _source_metadata_only_count,
		"glyph_encoding_status": String(_glyph_encoding.get("status", "")),
		"glyph_encoding_single_byte_count": _single_byte_char_map.size(),
		"render_text_color_status": RENDER_TEXT_COLOR_STATUS,
		"render_text_initial_color_indices": _render_text_initial_color_indices.duplicate(true),
		"render_text_current_color_indices": _render_text_color_indices.duplicate(true),
		"render_text_color_control_count": _render_text_color_control_count,
		"render_text_control_status": RENDER_TEXT_CONTROL_STATUS,
		"render_text_control_summary": _render_text_control_summary(),
		"source_window_pixel_effect_status": SOURCE_WINDOW_PIXEL_EFFECT_STATUS,
		"source_window_pixel_effects": _source_window_pixel_effects.duplicate(true),
		"source_window_pixel_effect_summary": _source_window_pixel_effect_summary(),
		"scroll_distance_px_remaining": _pending_scroll_remaining_px,
		"scroll_distance_px_total": _pending_scroll_total_px,
		"source_glyph_layout_status": "source_metrics_layout" if _has_font_metrics() else "fallback_constant_width_layout",
		"source_font_atlas_status": _source_font_atlas_status(),
		"source_font_atlas_binding_count": _font_atlas_binding_count,
		"source_glyph_layout": {
			"font_id": _layout_font_id,
			"origin": [_layout_origin.x, _layout_origin.y],
			"cursor": [_layout_cursor.x, _layout_cursor.y],
			"glyph_count": _layout_glyph_count,
			"line_count": _layout_line_count,
			"max_line_width_px": _layout_max_line_width_px,
			"total_advance_px": _layout_total_advance_px,
			"min_letter_spacing": _layout_min_letter_spacing,
			"japanese_mode": _layout_japanese,
			"font_metrics_status": String(_font_metrics.get("status", "")),
			"glyphs": _layout_glyphs.duplicate(true),
			"control_events": _layout_control_events.duplicate(true),
			"control_summary": _render_text_control_summary(),
		},
		"event_count": _events.size(),
		"event_index": _event_index,
		"control_event_count": _control_event_count,
		"style_event_count": _style_event_count,
		"audio_cue_count": _audio_cue_count,
		"pause_event_count": _pause_event_count,
		"page_wait_count": _page_wait_count,
		"prompt_scroll_count": _prompt_scroll_count,
		"prompt_clear_count": _prompt_clear_count,
		"wait_input_count": _wait_input_count,
		"wait_se_count": _wait_se_count,
		"event_log": _event_log.duplicate(true),
		"source_trace": SOURCE_TRACE.duplicate(true),
		"unsupported": _unsupported.duplicate(true),
	}


func _render_step(input: Dictionary) -> void:
	if not _active:
		return
	_render_call_count += 1
	if not _wait_state.is_empty():
		_advance_wait_state(input)
		return
	if _has_print_been_sped_up and _can_ab_speed_up_print and _is_advance_input_held(input):
		_delay_counter = 0
	if _delay_counter > 0 and _source_text_speed > 0:
		if _can_ab_speed_up_print and _is_advance_input_just_pressed(input):
			_has_print_been_sped_up = true
			_ab_speedup_count += 1
			_delay_counter = 0
			return
		_delay_counter -= 1
		return
	_delay_counter = _source_text_speed
	_render_events_until_visible_or_blocked(input)


func _render_all_remaining() -> void:
	_wait_state = ""
	_pause_counter = 0
	_down_arrow_visible = false
	_visible_text = ""
	_visible_char_count = 0
	_reset_layout_state(_layout_initial_font_id)
	for event_value in _events:
		var event := _dictionary_value(event_value)
		_apply_final_event_to_text_and_layout(event)
	_visible_char_count = _visible_text.length()
	_event_index = _events.size()
	_active = false
	_complete = true
	_delay_counter = 0


func _apply_final_event_to_text_and_layout(event: Dictionary) -> void:
	match String(event.get("kind", "")):
		"visible":
			_visible_text += String(event.get("text", ""))
			_record_visible_layout(event)
		"newline":
			_visible_text += "\n"
			_record_newline_layout(event)
		"page_break":
			_visible_text += String(event.get("text", "\n"))
			_record_page_break_layout(event)
		"page_clear":
			_clear_visible_text("CHAR_PROMPT_CLEAR")
		"style":
			_apply_layout_style_event(event)
		"pause":
			_record_layout_control_event(event, {
				"kind": "pause",
				"frames": int(event.get("frames", 0)),
				"source": String(event.get("source", "PAUSE")),
			})
		"wait_input":
			_record_layout_control_event(event, {
				"kind": "wait",
				"source": String(event.get("source", "EXT_CTRL_CODE_PAUSE_UNTIL_PRESS")),
			})
		"wait_se":
			_record_layout_control_event(event, {
				"kind": "wait_se",
				"source": String(event.get("source", "EXT_CTRL_CODE_WAIT_SE")),
				"status": "metadata_only",
			})
		"audio":
			_record_layout_control_event(event, {
				"kind": "audio",
				"command": String(event.get("command", "")),
				"status": "metadata_only",
			})
		"placeholder":
			_record_layout_control_event(event, {
				"kind": "placeholder",
				"placeholder_id": int(event.get("placeholder_id", -1)),
				"status": "metadata_only",
			})
		_:
			var text := String(event.get("text", ""))
			if not text.is_empty():
				_visible_text += text
				_record_visible_layout(event)


func _resolve_player_text_speed(text_printer_metadata: Dictionary, options: Dictionary) -> void:
	_player_text_speed = String(options.get("player_text_speed", DEFAULT_PLAYER_TEXT_SPEED))
	var player_speed: Dictionary = _dictionary_value(text_printer_metadata.get("player_text_speed", {}))
	var modifiers: Dictionary = _dictionary_value(player_speed.get("modifiers", {}))
	_player_text_speed_modifier = int(modifiers.get(_player_text_speed, 1))
	if _player_text_speed_modifier <= 0:
		_player_text_speed_modifier = 1
	var scroll_speeds: Dictionary = _dictionary_value(player_speed.get("scroll_speeds", {}))
	_player_text_scroll_speed = int(scroll_speeds.get(_player_text_speed, 1))
	if _player_text_scroll_speed <= 0:
		_player_text_scroll_speed = 1
	_player_text_speed_is_instant = _player_text_speed == "OPTIONS_TEXT_SPEED_INSTANT"


func _resolve_frame_delay(text_info: Dictionary, text_printer_metadata: Dictionary, options: Dictionary) -> void:
	_recorded_battle_text_speeds = _array_value(text_printer_metadata.get("recorded_battle_text_speeds", []))
	if options.has("battle_text_speed_override"):
		_resolved_frame_delay = max(0, int(options.get("battle_text_speed_override", 0)))
		_effective_speed_source = "option_battle_text_speed_override"
		return
	if _is_message_speed_window() and (_is_link_battle_text_context(options) or _is_recorded_link_battle_text_context(options)):
		_resolved_frame_delay = 1
		_effective_speed_source = "BattlePutTextOnWindow:recorded_link_battle_speed" if _is_recorded_link_battle_text_context(options) and not _is_link_battle_text_context(options) else "BattlePutTextOnWindow:link_battle_speed"
		return
	if _is_message_speed_window() and _is_recorded_battle_text_context(options):
		var speed_index := clampi(int(options.get("recorded_text_speed_index", 0)), 0, max(0, _recorded_battle_text_speeds.size() - 1))
		_recorded_text_speed_index = speed_index
		_recorded_text_speed_value = max(0, int(_recorded_battle_text_speeds[speed_index])) if not _recorded_battle_text_speeds.is_empty() else 1
		_resolved_frame_delay = _recorded_text_speed_value
		_effective_speed_source = "BattlePutTextOnWindow:recorded_battle_speed[%d]" % speed_index
		return
	if typeof(_source_speed) == TYPE_STRING and String(_source_speed) == SOURCE_SPEED_PLAYER_TEXT_DELAY:
		var player_speed: Dictionary = _dictionary_value(text_printer_metadata.get("player_text_speed", {}))
		var frame_delays: Dictionary = _dictionary_value(player_speed.get("frame_delays", {}))
		_resolved_frame_delay = max(0, int(frame_delays.get(_player_text_speed, 1)))
		_effective_speed_source = "GetPlayerTextSpeedDelay:%s" % _player_text_speed
		return
	_resolved_frame_delay = max(0, int(text_info.get("source_speed", text_info.get("table_speed", 0))))
	_effective_speed_source = "sTextOnWindowsInfo_Normal.speed"


func _build_battle_text_context(options: Dictionary, text_printer_metadata: Dictionary) -> Dictionary:
	var recorded_speeds: Array = _array_value(text_printer_metadata.get("recorded_battle_text_speeds", []))
	var pokedude_excluded := _is_pokedude_battle_text_context(options) and _window_id == "B_WIN_OAK_OLD_MAN"
	return {
		"status": BATTLE_TEXT_CONTEXT_STATUS,
		"source": "src/battle_message.c:BattlePutTextOnWindow",
		"wait_source": "src/text.c:TextPrinterWaitWithDownArrow",
		"battle_text_mode": _battle_text_mode(options),
		"window_id": _window_id,
		"is_message_speed_window": _is_message_speed_window(),
		"battle_type_link": _is_link_battle_text_context(options),
		"battle_type_recorded": _is_recorded_battle_text_context(options),
		"battle_type_recorded_link": _is_recorded_link_battle_text_context(options),
		"battle_type_pokedude": _is_pokedude_battle_text_context(options),
		"pokedude_oak_old_man_window_excluded": pokedude_excluded,
		"test_runner_enabled": bool(options.get("test_runner_enabled", false)),
		"auto_scroll": _auto_scroll,
		"auto_scroll_source": _auto_scroll_source,
		"auto_scroll_reasons": _auto_scroll_reasons.duplicate(true),
		"message_speed_source": _effective_speed_source,
		"resolved_frame_delay": _resolved_frame_delay,
		"recorded_battle_text_speeds": recorded_speeds.duplicate(true),
		"recorded_text_speed_index": _recorded_text_speed_index,
		"recorded_text_speed_value": _recorded_text_speed_value,
		"can_ab_speed_up_print": _can_ab_speed_up_print,
	}


func _note_text_limitations() -> void:
	if _full_text.find("\n") >= 0:
		_add_unsupported("battle_text_newline_layout_approximation")


func _render_events_until_visible_or_blocked(input: Dictionary = {}) -> void:
	var guard := 0
	while _event_index < _events.size() and guard < 0x400:
		guard += 1
		var event: Dictionary = _dictionary_value(_events[_event_index])
		_event_index += 1
		var kind := String(event.get("kind", ""))
		match kind:
			"visible":
				_visible_text += String(event.get("text", ""))
				_visible_char_count = _visible_text.length()
				_record_visible_layout(event)
				_mark_complete_if_done()
				return
			"newline":
				_visible_text += "\n"
				_visible_char_count = _visible_text.length()
				_record_newline_layout(event)
				_event_log.append({"kind": "newline", "source": "CHAR_NEWLINE"})
			"page_break":
				_visible_text += String(event.get("text", "\n"))
				_visible_char_count = _visible_text.length()
				_record_page_break_layout(event)
				_wait_state = "wait_with_down_arrow"
				_down_arrow_visible = not _auto_scroll
				_page_wait_count += 1
				_prompt_scroll_count += 1
				_event_log.append(_event_log_entry(event, {"kind": "page_break", "source": "CHAR_PROMPT_SCROLL", "auto_scroll": _auto_scroll}))
				return
			"page_clear":
				_wait_state = "wait_clear"
				_down_arrow_visible = not _auto_scroll
				_record_layout_control_event(event, {"kind": "page_clear", "source": "CHAR_PROMPT_CLEAR"})
				_page_wait_count += 1
				_prompt_clear_count += 1
				_event_log.append(_event_log_entry(event, {"kind": "page_clear", "source": "CHAR_PROMPT_CLEAR", "auto_scroll": _auto_scroll}))
				return
			"pause":
				_wait_state = "pause"
				_pause_counter = max(0, int(event.get("frames", 0)))
				_pause_event_count += 1
				_control_event_count += 1
				_event_log.append(_event_log_entry(event, {"kind": "pause", "frames": _pause_counter, "source": "EXT_CTRL_CODE_PAUSE"}))
				return
			"wait_input":
				_wait_state = "wait"
				_wait_input_count += 1
				_control_event_count += 1
				_event_log.append(_event_log_entry(event, {"kind": "wait", "source": "EXT_CTRL_CODE_PAUSE_UNTIL_PRESS", "auto_scroll": _auto_scroll}))
				return
			"wait_se":
				_wait_state = "wait_se"
				_wait_se_count += 1
				_control_event_count += 1
				_audio_cue_count += 1
				_event_log.append(_event_log_entry(event, {"kind": "wait_se", "status": "metadata_only", "source": "EXT_CTRL_CODE_WAIT_SE"}))
				if not bool(input.get("audio_playing", false)):
					_wait_state = ""
					_down_arrow_visible = false
				return
			"audio":
				_audio_cue_count += 1
				_control_event_count += 1
				_event_log.append(_event_log_entry(event, {
					"kind": "audio",
					"command": String(event.get("command", "")),
					"args": event.get("args", []),
					"status": "metadata_only",
				}))
			"style":
				_apply_layout_style_event(event)
				_style_event_count += 1
				_control_event_count += 1
				_event_log.append(_event_log_entry(event, {
					"kind": "style",
					"command": String(event.get("command", "")),
					"args": event.get("args", []),
				}))
			"placeholder":
				_control_event_count += 1
				_event_log.append(_event_log_entry(event, {
					"kind": "placeholder",
					"placeholder_id": int(event.get("placeholder_id", -1)),
					"status": "metadata_only",
				}))
			_:
				_visible_text += String(event.get("text", ""))
				_visible_char_count = _visible_text.length()
				_record_visible_layout(event)
				_mark_complete_if_done()
				return
	_mark_complete_if_done()


func _render_events_until_blocked_or_complete(max_ops: int, input: Dictionary = {}) -> void:
	var guard := 0
	while _event_index < _events.size() and _wait_state.is_empty() and guard < max_ops:
		guard += 1
		_render_events_until_visible_or_blocked(input)
		if not _wait_state.is_empty():
			break
	_mark_complete_if_done()


func _advance_wait_state(input: Dictionary) -> void:
	match _wait_state:
		"pause":
			if _pause_counter != 0:
				_pause_counter -= 1
				return
			_wait_state = ""
		"wait", "wait_with_down_arrow", "wait_clear":
			if _auto_scroll:
				if _auto_scroll_delay >= NUM_FRAMES_AUTO_SCROLL_DELAY:
					_auto_scroll_delay = 0
					_finish_prompt_wait()
					return
				_auto_scroll_delay += 1
			if _is_advance_input_just_pressed(input):
				_finish_prompt_wait()
		"scroll":
			_advance_source_window_scroll()
		"wait_se":
			if bool(input.get("audio_finished", false)) or not bool(input.get("audio_playing", false)):
				_wait_state = ""
		_:
			_wait_state = ""
	_mark_complete_if_done()


func _finish_prompt_wait() -> void:
	var previous_wait_state := _wait_state
	_auto_scroll_delay = 0
	_down_arrow_visible = false
	match previous_wait_state:
		"wait_clear":
			_clear_visible_text("CHAR_PROMPT_CLEAR")
			_wait_state = ""
		"wait_with_down_arrow":
			if _event_stream_source == "source_bytes":
				_start_source_window_scroll("CHAR_PROMPT_SCROLL")
			else:
				_wait_state = ""
		_:
			_wait_state = ""


func _start_source_window_scroll(source: String) -> void:
	var distance: int = max(0, _font_line_advance(_layout_font_id))
	_pending_scroll_total_px = distance
	_pending_scroll_remaining_px = distance
	_pending_scroll_utility_counter = 0
	_record_source_window_pixel_effect({
		"kind": "scroll_window_start",
		"source": source,
		"operation": "TextPrinterClearDownArrow_then_RENDER_STATE_SCROLL",
		"scroll_distance_px": distance,
		"scroll_speed_px": _player_text_scroll_speed,
		"speed_modifier": _player_text_speed_modifier,
		"source_rule": "src/text.c:RENDER_STATE_SCROLL_START sets scrollDistance to maxLetterHeight + lineSpacing",
	})
	if distance <= 0:
		_wait_state = ""
		return
	_wait_state = "scroll"


func _advance_source_window_scroll() -> void:
	if _pending_scroll_remaining_px <= 0:
		_finish_source_window_scroll()
		return
	if _pending_scroll_utility_counter > 0:
		_pending_scroll_utility_counter -= 1
		return
	var step: int = min(_pending_scroll_remaining_px, max(1, _player_text_scroll_speed))
	_pending_scroll_remaining_px -= step
	_shift_layout_glyphs_y(-step)
	_record_source_window_pixel_effect({
		"kind": "scroll_window_step",
		"source": "CHAR_PROMPT_SCROLL",
		"operation": "ScrollWindow",
		"direction": "up",
		"dy_px": step,
		"remaining_px": _pending_scroll_remaining_px,
		"scroll_speed_px": _player_text_scroll_speed,
		"source_rule": "src/text.c:RENDER_STATE_SCROLL calls ScrollWindow by GetPlayerTextScrollSpeed()",
	})
	if _pending_scroll_remaining_px <= 0:
		_finish_source_window_scroll()
		return
	_pending_scroll_utility_counter = _player_text_speed_modifier if _player_text_speed_modifier > 1 else 0


func _finish_source_window_scroll() -> void:
	_record_source_window_pixel_effect({
		"kind": "scroll_window_complete",
		"source": "CHAR_PROMPT_SCROLL",
		"operation": "RENDER_STATE_HANDLE_CHAR",
		"scroll_distance_px": _pending_scroll_total_px,
		"source_rule": "src/text.c:RENDER_STATE_SCROLL returns to HANDLE_CHAR when scrollDistance reaches zero",
	})
	_pending_scroll_remaining_px = 0
	_pending_scroll_utility_counter = 0
	_wait_state = ""


func _mark_complete_if_done() -> void:
	if _event_index >= _events.size() and _wait_state.is_empty():
		_active = false
		_complete = true


func _parse_text_events(text: String, event_source: String = "display_text") -> Array:
	var events := []
	var index := 0
	while index < text.length():
		var character := text.substr(index, 1)
		if (event_source == "source_text" or event_source == "source_bytes") and character == "\\":
			if index + 1 >= text.length():
				events.append({"kind": "visible", "text": "\\"})
				index += 1
				continue
			var escaped := text.substr(index + 1, 1)
			match escaped:
				"n":
					events.append({"kind": "newline", "source": "CHAR_NEWLINE", "source_escape": "\\n"})
				"l":
					if event_source == "source_bytes":
						events.append({"kind": "page_break", "text": "\n", "source": "CHAR_PROMPT_SCROLL", "source_escape": "\\l"})
					else:
						events.append({"kind": "newline", "source": "CHAR_NEWLINE", "source_escape": "\\l"})
				"p":
					if event_source == "source_bytes":
						events.append({"kind": "page_clear", "source": "CHAR_PROMPT_CLEAR", "source_escape": "\\p"})
					else:
						events.append({"kind": "newline", "source": "CHAR_NEWLINE", "source_escape": "\\p"})
						events.append({"kind": "page_break", "text": "\n", "source": "CHAR_PROMPT_SCROLL", "source_escape": "\\p"})
				"r":
					events.append({"kind": "visible", "text": "\r", "source_escape": "\\r"})
				"t":
					events.append({"kind": "visible", "text": "    ", "source_escape": "\\t"})
				"\\":
					events.append({"kind": "visible", "text": "\\", "source_escape": "\\\\"})
				"\"":
					events.append({"kind": "visible", "text": "\"", "source_escape": "\\\""})
				_:
					events.append({"kind": "visible", "text": "\\%s" % escaped, "source_escape": "\\%s" % escaped})
			index += 2
			continue
		if character == "{":
			var close_index := text.find("}", index + 1)
			if close_index > index:
				var token_content := text.substr(index + 1, close_index - index - 1)
				var control_event := _control_event_from_token(token_content)
				if not control_event.is_empty():
					events.append(control_event)
					index = close_index + 1
					continue
		if character == "\n":
			if index + 1 < text.length() and text.substr(index + 1, 1) == "\n":
				events.append({"kind": "newline", "source": "CHAR_NEWLINE"})
				events.append({"kind": "page_break", "text": "\n", "source": "CHAR_PROMPT_SCROLL"})
				index += 2
				continue
			events.append({"kind": "newline", "source": "CHAR_NEWLINE"})
			index += 1
			continue
		events.append({"kind": "visible", "text": _display_text(character)})
		index += 1
	return events


func _control_event_from_token(token_content: String) -> Dictionary:
	var parts := token_content.strip_edges().split(" ", false)
	if parts.is_empty():
		return {}
	var command := String(parts[0]).to_upper()
	var args := []
	for index in range(1, parts.size()):
		args.append(parts[index])
	if command == "PAUSE":
		return {"kind": "pause", "command": command, "args": args, "frames": int(args[0]) if not args.is_empty() else 0}
	if command == "PAUSE_UNTIL_PRESS":
		return {"kind": "wait_input", "command": command, "args": args}
	if command == "WAIT_SE":
		return {"kind": "wait_se", "command": command, "args": args}
	if AUDIO_CONTROL_COMMANDS.has(command):
		return {"kind": "audio", "command": command, "args": args}
	if STYLE_CONTROL_COMMANDS.has(command) or command.begins_with("DYNAMIC_COLOR"):
		return {"kind": "style", "command": command, "args": args}
	return {}


func _parse_source_byte_events(bytes: Array, visible_fallback_text: String, source_glyphs: Array = []) -> Array:
	var events := []
	var visible_chars := _visible_fallback_chars_for_source_bytes(visible_fallback_text)
	var glyph_by_offset := _source_glyphs_by_byte_offset(source_glyphs)
	var visible_index := 0
	var index := 0
	while index < bytes.size():
		var byte := int(bytes[index]) & 0xFF
		var glyph := _dictionary_value(glyph_by_offset.get(index, {}))
		if byte != EOS and not glyph.is_empty():
			var glyph_event := _source_byte_glyph_visible_event(glyph, visible_chars, visible_index, byte, index)
			events.append(glyph_event)
			visible_index += 1
			index += max(1, int(glyph_event.get("source_byte_count", 1)))
			continue
		match byte:
			EOS:
				break
			CHAR_NEWLINE:
				events.append({
					"kind": "newline",
					"source": "CHAR_NEWLINE",
					"source_event_source": "source_bytes",
					"source_offset": index,
					"source_byte": byte,
				})
				index += 1
			CHAR_PROMPT_SCROLL:
				events.append({
					"kind": "page_break",
					"text": "\n",
					"source": "CHAR_PROMPT_SCROLL",
					"source_event_source": "source_bytes",
					"source_offset": index,
					"source_byte": byte,
				})
				index += 1
			CHAR_PROMPT_CLEAR:
				events.append({
					"kind": "page_clear",
					"source": "CHAR_PROMPT_CLEAR",
					"source_event_source": "source_bytes",
					"source_offset": index,
					"source_byte": byte,
				})
				index += 1
			PLACEHOLDER_BEGIN:
				var placeholder_id := int(bytes[index + 1]) & 0xFF if index + 1 < bytes.size() else -1
				events.append({
					"kind": "placeholder",
					"source": "PLACEHOLDER_BEGIN",
					"source_event_source": "source_bytes",
					"source_offset": index,
					"source_byte": byte,
					"placeholder_id": placeholder_id,
				})
				index += 2
			CHAR_DYNAMIC:
				var dynamic_id := int(bytes[index + 1]) & 0xFF if index + 1 < bytes.size() else -1
				events.append({
					"kind": "placeholder",
					"source": "CHAR_DYNAMIC",
					"source_event_source": "source_bytes",
					"source_offset": index,
					"source_byte": byte,
					"placeholder_id": dynamic_id,
				})
				index += 2
			CHAR_KEYPAD_ICON, CHAR_EXTRA_SYMBOL:
				var visible_text := _next_source_byte_visible_text(visible_chars, visible_index, byte)
				visible_index += 1
				events.append({
					"kind": "visible",
					"text": visible_text,
					"source_event_source": "source_bytes",
					"source_offset": index,
					"source_byte": byte,
					"source_sub_code": int(bytes[index + 1]) & 0xFF if index + 1 < bytes.size() else -1,
				})
				index += 2
			EXT_CTRL_CODE_BEGIN:
				var control_code := int(bytes[index + 1]) & 0xFF if index + 1 < bytes.size() else -1
				var arg_count := _ext_control_arg_count(control_code)
				var args := []
				for arg_index in range(arg_count):
					var byte_index := index + 2 + arg_index
					if byte_index >= bytes.size():
						break
					args.append(int(bytes[byte_index]) & 0xFF)
				var event := _source_byte_ext_control_event(control_code, args, index)
				if String(event.get("kind", "")) == "visible":
					var visible_text := _next_source_byte_visible_text(visible_chars, visible_index, byte)
					visible_index += 1
					event["text"] = visible_text
				if not event.is_empty():
					events.append(event)
				index += 2 + arg_count
			_:
				var visible_text := _next_source_byte_visible_text(visible_chars, visible_index, byte)
				visible_index += 1
				events.append({
					"kind": "visible",
					"text": visible_text,
					"source_event_source": "source_bytes",
					"source_offset": index,
					"source_byte": byte,
				})
				index += 1
	return events


func _source_glyphs_by_byte_offset(source_glyphs: Array) -> Dictionary:
	var result := {}
	for glyph_index in range(source_glyphs.size()):
		var glyph := _dictionary_value(source_glyphs[glyph_index])
		var byte_offset := int(glyph.get("byte_offset", -1))
		if byte_offset < 0:
			continue
		var glyph_bytes := _int_array_value(glyph.get("bytes", []))
		if glyph_bytes.is_empty():
			continue
		var record := glyph.duplicate(true)
		record["source_glyph_index"] = glyph_index
		result[byte_offset] = record
	return result


func _source_byte_glyph_visible_event(glyph: Dictionary, visible_chars: Array, visible_index: int, source_byte: int, source_offset: int) -> Dictionary:
	var glyph_bytes := _int_array_value(glyph.get("bytes", []))
	var visible_text := String(glyph.get("text", ""))
	if visible_text.is_empty():
		visible_text = _next_source_byte_visible_text(visible_chars, visible_index, source_byte)
	return {
		"kind": "visible",
		"text": visible_text,
		"source_event_source": "source_bytes",
		"source_offset": source_offset,
		"source_byte": source_byte,
		"source_byte_span": glyph_bytes,
		"source_byte_count": glyph_bytes.size(),
		"source_text_offset": int(glyph.get("source_offset", -1)),
		"source_glyph_index": int(glyph.get("source_glyph_index", -1)),
		"source_glyph_hex": String(glyph.get("hex", "")),
	}


func _source_byte_ext_control_event(control_code: int, args: Array, source_offset: int) -> Dictionary:
	var control_name := _ext_control_name(control_code)
	var event := {
		"command": control_name,
		"args": args.duplicate(true),
		"source": control_name,
		"source_event_source": "source_bytes",
		"source_offset": source_offset,
		"source_byte": EXT_CTRL_CODE_BEGIN,
		"source_control_code": control_code,
	}
	match control_code:
		EXT_CTRL_CODE_PAUSE:
			event["kind"] = "pause"
			event["frames"] = int(args[0]) if not args.is_empty() else 0
		EXT_CTRL_CODE_PAUSE_UNTIL_PRESS:
			event["kind"] = "wait_input"
		EXT_CTRL_CODE_WAIT_SE:
			event["kind"] = "wait_se"
		EXT_CTRL_CODE_PLAY_BGM, EXT_CTRL_CODE_PLAY_SE:
			event["kind"] = "audio"
		EXT_CTRL_CODE_ESCAPE:
			event["kind"] = "visible"
		_:
			event["kind"] = "style"
	return event


func _visible_text_from_events() -> String:
	var text := ""
	for event_value in _events:
		var event := _dictionary_value(event_value)
		match String(event.get("kind", "")):
			"visible":
				text += String(event.get("text", ""))
			"newline":
				text += "\n"
			"page_break":
				text += String(event.get("text", "\n"))
			"page_clear":
				text = ""
	return text


func _visible_fallback_chars_for_source_bytes(text: String) -> Array:
	var chars := []
	var source := _strip_source_text_terminator(text)
	var index := 0
	while index < source.length():
		var character := source.substr(index, 1)
		if character == "\\":
			if index + 1 >= source.length():
				chars.append("\\")
				index += 1
				continue
			var escaped := source.substr(index + 1, 1)
			match escaped:
				"n", "l", "p":
					pass
				"r":
					chars.append("\r")
				"t":
					chars.append("    ")
				"\\":
					chars.append("\\")
				"\"":
					chars.append("\"")
				_:
					chars.append("\\%s" % escaped)
			index += 2
			continue
		if character == "{":
			var close_index := source.find("}", index + 1)
			if close_index > index:
				index = close_index + 1
				continue
		if character == "\n":
			index += 1
			continue
		chars.append(_display_text(character))
		index += 1
	return chars


func _next_source_byte_visible_text(visible_chars: Array, visible_index: int, source_byte: int) -> String:
	if visible_index < visible_chars.size():
		return String(visible_chars[visible_index])
	return "[%02X]" % (source_byte & 0xFF)


func _count_source_byte_events(events: Array) -> int:
	var count := 0
	for event_value in events:
		var event := _dictionary_value(event_value)
		if String(event.get("source_event_source", "")) == "source_bytes":
			count += 1
	return count


func _event_log_entry(event: Dictionary, base: Dictionary) -> Dictionary:
	var entry := base.duplicate(true)
	if event.has("source_event_source"):
		entry["source_event_source"] = event.get("source_event_source")
	if event.has("source_offset"):
		entry["source_offset"] = event.get("source_offset")
	if event.has("source_byte"):
		entry["source_byte"] = event.get("source_byte")
	if event.has("source_control_code"):
		entry["source_control_code"] = event.get("source_control_code")
	return entry


func _resolve_auto_scroll(options: Dictionary) -> bool:
	_auto_scroll_reasons = []
	if bool(options.get("auto_scroll", false)):
		_auto_scroll_reasons.append("option_auto_scroll")
	if _is_link_battle_text_context(options):
		_auto_scroll_reasons.append("BATTLE_TYPE_LINK")
	if _is_recorded_battle_text_context(options):
		_auto_scroll_reasons.append("BATTLE_TYPE_RECORDED")
	if bool(options.get("test_runner_enabled", false)):
		_auto_scroll_reasons.append("gTestRunnerEnabled")
	if _is_pokedude_battle_text_context(options) and _window_id != "B_WIN_OAK_OLD_MAN":
		_auto_scroll_reasons.append("BATTLE_TYPE_POKEDUDE")
	var result := not _auto_scroll_reasons.is_empty()
	_auto_scroll_source = "BattlePutTextOnWindow:gTextFlags.autoScroll=TRUE:%s" % _join_string_array(_auto_scroll_reasons, ",") if result else "BattlePutTextOnWindow:gTextFlags.autoScroll=FALSE"
	return result


func _battle_text_mode(options: Dictionary) -> String:
	return String(options.get("battle_text_mode", "")).to_lower()


func _is_link_battle_text_context(options: Dictionary) -> bool:
	return _battle_text_mode(options) == "link" or bool(options.get("battle_type_link", false))


func _is_recorded_battle_text_context(options: Dictionary) -> bool:
	var mode := _battle_text_mode(options)
	return mode == "recorded" or mode == "recorded_link" or bool(options.get("battle_type_recorded", false))


func _is_recorded_link_battle_text_context(options: Dictionary) -> bool:
	return _battle_text_mode(options) == "recorded_link" or bool(options.get("battle_type_recorded_link", false))


func _is_pokedude_battle_text_context(options: Dictionary) -> bool:
	return _battle_text_mode(options) == "pokedude" or bool(options.get("battle_type_pokedude", false))


func _join_string_array(values: Array, separator: String) -> String:
	var strings := PackedStringArray()
	for value in values:
		strings.append(String(value))
	return separator.join(strings)


func _is_message_speed_window() -> bool:
	return _window_id == "B_WIN_MSG" or _window_id == "ARENA_WIN_JUDGMENT_TEXT" or _window_id == "B_WIN_OAK_OLD_MAN"


func _is_advance_input_just_pressed(input: Dictionary) -> bool:
	return bool(input.get("a_pressed", false)) \
		or bool(input.get("b_pressed", false)) \
		or bool(input.get("accept_pressed", false)) \
		or bool(input.get("advance_pressed", false))


func _is_advance_input_held(input: Dictionary) -> bool:
	return _is_advance_input_just_pressed(input) \
		or bool(input.get("a_held", false)) \
		or bool(input.get("b_held", false)) \
		or bool(input.get("accept_held", false)) \
		or bool(input.get("advance_held", false))


func _add_unsupported(code: String) -> void:
	if not _unsupported.has(code):
		_unsupported.append(code)


func _event_stream_status() -> String:
	if _event_stream_source == "source_bytes":
		return "first_pass_source_byte_control_events"
	if _event_stream_source == "source_text":
		return "first_pass_source_text_events"
	return "first_pass_display_text_events"


func _clear_visible_text(source: String = "CHAR_PROMPT_CLEAR") -> void:
	var background_material_index := int(_render_text_color_indices.get("background", 0))
	_visible_text = ""
	_visible_char_count = 0
	_layout_cursor = _layout_origin
	_layout_glyphs = []
	_layout_glyph_count = 0
	_layout_total_advance_px = 0
	_layout_line_count = 1
	_layout_max_line_width_px = 0
	_render_text_color_indices = _render_text_initial_color_indices.duplicate(true)
	_record_source_window_pixel_effect({
		"kind": "fill_window",
		"source": source,
		"operation": "FillWindowPixelBuffer",
		"background_material_index": background_material_index,
		"x": 0,
		"y": 0,
		"source_rule": "src/text.c:RENDER_STATE_CLEAR and EXT_CTRL_CODE_FILL_WINDOW fill the window with the current background material",
	})
	_layout_control_events.append({
		"kind": "clear_visible_text",
		"x": _layout_cursor.x,
		"y": _layout_cursor.y,
		"source": source,
	})


func _record_source_window_pixel_effect(effect: Dictionary) -> void:
	var record := effect.duplicate(true)
	record["index"] = _source_window_pixel_effects.size()
	record["status"] = SOURCE_WINDOW_PIXEL_EFFECT_STATUS
	_source_window_pixel_effects.append(record)


func _source_window_pixel_effect_summary() -> Dictionary:
	var summary := {
		"status": SOURCE_WINDOW_PIXEL_EFFECT_STATUS,
		"effect_count": _source_window_pixel_effects.size(),
		"fill_window_count": 0,
		"clear_text_span_count": 0,
		"clear_text_span_filled_count": 0,
		"scroll_start_count": 0,
		"scroll_step_count": 0,
		"scroll_complete_count": 0,
		"scroll_total_px": 0,
		"scroll_distance_px_remaining": _pending_scroll_remaining_px,
		"scroll_distance_px_total": _pending_scroll_total_px,
		"scroll_speed_px": _player_text_scroll_speed,
	}
	for effect_value in _source_window_pixel_effects:
		var effect := _dictionary_value(effect_value)
		match String(effect.get("kind", "")):
			"fill_window":
				summary["fill_window_count"] = int(summary["fill_window_count"]) + 1
			"clear_text_span":
				summary["clear_text_span_count"] = int(summary["clear_text_span_count"]) + 1
				if String(effect.get("pixel_status", "")) == "filled":
					summary["clear_text_span_filled_count"] = int(summary["clear_text_span_filled_count"]) + 1
			"scroll_window_start":
				summary["scroll_start_count"] = int(summary["scroll_start_count"]) + 1
			"scroll_window_step":
				summary["scroll_step_count"] = int(summary["scroll_step_count"]) + 1
				summary["scroll_total_px"] = int(summary["scroll_total_px"]) + int(effect.get("dy_px", 0))
			"scroll_window_complete":
				summary["scroll_complete_count"] = int(summary["scroll_complete_count"]) + 1
	return summary


func _render_text_control_summary() -> Dictionary:
	var summary := {
		"status": RENDER_TEXT_CONTROL_STATUS,
		"control_event_count": _layout_control_events.size(),
		"render_text_color_count": _render_text_color_control_count,
		"font_count": 0,
		"font_reset_noop_count": 0,
		"shift_right_count": 0,
		"shift_down_count": 0,
		"skip_count": 0,
		"clear_span_count": 0,
		"clear_to_count": 0,
		"fill_window_count": 0,
		"clear_visible_text_count": 0,
		"min_letter_spacing_count": 0,
		"japanese_mode_count": 0,
		"material_bank_skip_count": 0,
		"placeholder_count": 0,
		"wait_count": 0,
		"audio_metadata_count": 0,
		"source_rule": "src/text.c:RenderText EXT_CTRL_CODE_* cursor, clear, fill, material, font, language, wait, and audio side effects",
	}
	for control_value in _layout_control_events:
		var control := _dictionary_value(control_value)
		match String(control.get("kind", "")):
			"font":
				summary["font_count"] = int(summary["font_count"]) + 1
			"font_reset_noop":
				summary["font_reset_noop_count"] = int(summary["font_reset_noop_count"]) + 1
			"shift_right":
				summary["shift_right_count"] = int(summary["shift_right_count"]) + 1
			"shift_down":
				summary["shift_down_count"] = int(summary["shift_down_count"]) + 1
			"skip":
				summary["skip_count"] = int(summary["skip_count"]) + 1
			"clear_span":
				summary["clear_span_count"] = int(summary["clear_span_count"]) + 1
			"clear_to":
				summary["clear_to_count"] = int(summary["clear_to_count"]) + 1
			"fill_window":
				summary["fill_window_count"] = int(summary["fill_window_count"]) + 1
			"clear_visible_text":
				summary["clear_visible_text_count"] = int(summary["clear_visible_text_count"]) + 1
			"min_letter_spacing":
				summary["min_letter_spacing_count"] = int(summary["min_letter_spacing_count"]) + 1
			"japanese_mode":
				summary["japanese_mode_count"] = int(summary["japanese_mode_count"]) + 1
			"render_text_material_bank_argument_skipped":
				summary["material_bank_skip_count"] = int(summary["material_bank_skip_count"]) + 1
			"placeholder":
				summary["placeholder_count"] = int(summary["placeholder_count"]) + 1
			"wait", "pause", "wait_se":
				summary["wait_count"] = int(summary["wait_count"]) + 1
			"audio":
				summary["audio_metadata_count"] = int(summary["audio_metadata_count"]) + 1
	return summary


func _text_span_rect(width: int) -> Rect2i:
	return Rect2i(
		_layout_cursor.x,
		_layout_cursor.y,
		max(0, width),
		max(0, _font_glyph_height(_layout_font_id))
	)


func _record_clear_text_span_effect(event: Dictionary, rect: Rect2i, width: int) -> void:
	if width <= 0:
		return
	var background_material_index := int(_render_text_color_indices.get("background", 0))
	var pixel_status := "filled" if background_material_index != 0 and width > 0 else "transparent_background_skipped"
	if pixel_status == "filled":
		_clear_layout_glyphs_in_rect(rect)
	_record_source_window_pixel_effect({
		"kind": "clear_text_span",
		"source": String(event.get("source", event.get("command", "EXT_CTRL_CODE_CLEAR"))),
		"operation": "ClearTextSpan",
		"x": rect.position.x,
		"y": rect.position.y,
		"w": rect.size.x,
		"h": rect.size.y,
		"background_material_index": background_material_index,
		"pixel_status": pixel_status,
		"source_rule": "src/text.c:ClearTextSpan fills the current glyph-height span only when the background material is not transparent",
	})


func _clear_layout_glyphs_in_rect(rect: Rect2i) -> void:
	if rect.size.x <= 0 or rect.size.y <= 0:
		return
	var kept := []
	for glyph_value in _layout_glyphs:
		var glyph := _dictionary_value(glyph_value)
		var glyph_rect := Rect2i(
			int(glyph.get("x", 0)),
			int(glyph.get("y", 0)),
			int(glyph.get("width", 0)),
			int(glyph.get("height", 0))
		)
		if not _rects_intersect(glyph_rect, rect):
			kept.append(glyph)
	_layout_glyphs = kept
	_layout_glyph_count = _layout_glyphs.size()
	_recalculate_layout_widths()


func _shift_layout_glyphs_y(delta_y: int) -> void:
	if delta_y == 0:
		return
	for index in range(_layout_glyphs.size()):
		var glyph := _dictionary_value(_layout_glyphs[index]).duplicate(true)
		glyph["y"] = int(glyph.get("y", 0)) + delta_y
		_layout_glyphs[index] = glyph


func _recalculate_layout_widths() -> void:
	_layout_total_advance_px = 0
	_layout_max_line_width_px = 0
	for index in range(_layout_glyphs.size()):
		var glyph := _dictionary_value(_layout_glyphs[index]).duplicate(true)
		glyph["index"] = index
		_layout_glyphs[index] = glyph
		_layout_total_advance_px += int(glyph.get("advance", 0))
		_layout_max_line_width_px = max(_layout_max_line_width_px, int(glyph.get("x", 0)) - _layout_origin.x + int(glyph.get("advance", 0)))


func _rects_intersect(a: Rect2i, b: Rect2i) -> bool:
	return a.position.x < b.position.x + b.size.x \
		and a.position.x + a.size.x > b.position.x \
		and a.position.y < b.position.y + b.size.y \
		and a.position.y + a.size.y > b.position.y


func _display_text(text: String) -> String:
	return text.replace("\t", "    ")


func _strip_source_text_terminator(text: String) -> String:
	if text.ends_with("$"):
		return text.substr(0, text.length() - 1)
	return text


func _source_byte_control_summary_from_bytes(bytes: Array) -> Dictionary:
	var summary := {
		"byte_count": bytes.size(),
		"newline_count": 0,
		"prompt_scroll_count": 0,
		"prompt_clear_count": 0,
		"ext_control_count": 0,
		"placeholder_count": 0,
		"terminator_count": 0,
		"ext_controls": [],
	}
	var index := 0
	while index < bytes.size():
		var byte := int(bytes[index]) & 0xFF
		match byte:
			CHAR_NEWLINE:
				summary["newline_count"] = int(summary["newline_count"]) + 1
				index += 1
			CHAR_PROMPT_SCROLL:
				summary["prompt_scroll_count"] = int(summary["prompt_scroll_count"]) + 1
				index += 1
			CHAR_PROMPT_CLEAR:
				summary["prompt_clear_count"] = int(summary["prompt_clear_count"]) + 1
				index += 1
			PLACEHOLDER_BEGIN:
				summary["placeholder_count"] = int(summary["placeholder_count"]) + 1
				index += 2
			EOS:
				summary["terminator_count"] = int(summary["terminator_count"]) + 1
				index += 1
			EXT_CTRL_CODE_BEGIN:
				var control_code := int(bytes[index + 1]) & 0xFF if index + 1 < bytes.size() else -1
				var arg_count := _ext_control_arg_count(control_code)
				var control := {
					"offset": index,
					"code": control_code,
					"name": _ext_control_name(control_code),
					"arg_count": arg_count,
					"args": [],
				}
				for arg_index in range(arg_count):
					var byte_index := index + 2 + arg_index
					if byte_index >= bytes.size():
						break
					control["args"].append(int(bytes[byte_index]) & 0xFF)
				summary["ext_control_count"] = int(summary["ext_control_count"]) + 1
				summary["ext_controls"].append(control)
				index += 2 + arg_count
			_:
				index += 1
	return summary


func _resolve_font_metrics(text_info: Dictionary, text_printer_metadata: Dictionary, options: Dictionary) -> Dictionary:
	var explicit_metrics := _dictionary_value(options.get("font_metrics", {}))
	if not explicit_metrics.is_empty():
		_count_font_atlas_bindings(explicit_metrics)
		return explicit_metrics
	var text_info_metrics := _dictionary_value(text_info.get("font_metrics", {}))
	var printer_metrics := _dictionary_value(text_printer_metadata.get("font_metrics", {}))
	if printer_metrics.is_empty():
		_count_font_atlas_bindings(text_info_metrics)
		return text_info_metrics
	if text_info_metrics.is_empty():
		_count_font_atlas_bindings(printer_metrics)
		return printer_metrics
	var result := printer_metrics.duplicate(true)
	result["active_font_metrics"] = text_info_metrics
	_count_font_atlas_bindings(result)
	return result


func _single_byte_char_map_from_glyph_encoding(glyph_encoding: Dictionary) -> Dictionary:
	var source_chars := _dictionary_value(glyph_encoding.get("single_byte_chars", {}))
	var result := {}
	for key in source_chars.keys():
		var character := String(key)
		if character.length() == 1:
			result[character] = int(source_chars[key]) & 0xFF
	return result


func _render_text_color_indices_from_text_info(text_info: Dictionary) -> Dictionary:
	var source_indices := _dictionary_value(text_info.get("text_color_indices", {}))
	var result := {}
	for slot in ["background", "foreground", "shadow", "accent"]:
		var index := _render_text_color_index_from_arg(source_indices.get(slot, 0))
		result[slot] = index if index >= 0 else 0
	return result


func _reset_layout_state(font_id: String) -> void:
	_layout_font_id = font_id if not font_id.is_empty() else "FONT_NORMAL"
	_layout_cursor = _layout_origin
	_layout_min_letter_spacing = 0
	_layout_japanese = false
	_render_text_color_indices = _render_text_initial_color_indices.duplicate(true)
	_layout_glyphs = []
	_layout_control_events = []
	_layout_glyph_count = 0
	_layout_total_advance_px = 0
	_layout_line_count = 1
	_layout_max_line_width_px = 0


func _record_visible_layout(event: Dictionary) -> void:
	var text := String(event.get("text", ""))
	var glyph_bytes := _int_array_value(event.get("source_byte_span", []))
	var glyph_width := _glyph_width_for_event(event, text, glyph_bytes)
	var glyph_height := _glyph_height_for_event(event, glyph_bytes)
	var x := _layout_cursor.x
	var y := _layout_cursor.y
	var advance := _glyph_advance_px(glyph_width)
	_layout_glyph_count += 1
	_layout_total_advance_px += advance
	_layout_max_line_width_px = max(_layout_max_line_width_px, x - _layout_origin.x + advance)
	var record := {
		"index": _layout_glyph_count - 1,
		"text": text,
		"font_id": _layout_font_id,
		"x": x,
		"y": y,
		"width": glyph_width,
		"height": glyph_height,
		"advance": advance,
		"line": _layout_line_count - 1,
		"kind": "glyph",
		"source": event.get("source", "visible"),
		"render_text_color_status": RENDER_TEXT_COLOR_STATUS,
		"render_text_color_indices": _render_text_color_indices.duplicate(true),
	}
	_copy_event_source_fields(event, record)
	if not glyph_bytes.is_empty():
		record["source_byte_span"] = glyph_bytes
		record["source_byte_count"] = glyph_bytes.size()
		record["glyph_kind"] = "source_bytes"
	else:
		record["glyph_kind"] = _glyph_kind_for_event(event, text)
	_attach_glyph_atlas_record(record, glyph_bytes, event, text)
	_layout_glyphs.append(record)
	_layout_cursor.x += advance


func _record_newline_layout(event: Dictionary) -> void:
	_layout_max_line_width_px = max(_layout_max_line_width_px, _layout_cursor.x - _layout_origin.x)
	_layout_cursor.x = _layout_origin.x
	_layout_cursor.y += _font_line_advance(_layout_font_id)
	_layout_line_count += 1
	_record_layout_control_event(event, {
		"kind": "newline",
		"source": "CHAR_NEWLINE",
		"x": _layout_cursor.x,
		"y": _layout_cursor.y,
		"line": _layout_line_count - 1,
	})


func _record_page_break_layout(event: Dictionary) -> void:
	var page_text := String(event.get("text", "\n"))
	if page_text.find("\n") >= 0:
		_record_newline_layout(event)
	_record_layout_control_event(event, {
		"kind": "page_break",
		"source": "CHAR_PROMPT_SCROLL",
		"x": _layout_cursor.x,
		"y": _layout_cursor.y,
		"line": _layout_line_count - 1,
	})


func _record_layout_control_event(event: Dictionary, base: Dictionary) -> void:
	var record := base.duplicate(true)
	_copy_event_source_fields(event, record)
	_layout_control_events.append(record)


func _apply_layout_style_event(event: Dictionary) -> void:
	var command := String(event.get("command", event.get("source", "")))
	var args := _array_value(event.get("args", []))
	if _apply_render_text_color_event(command, args, event):
		return
	match command:
		"FONT", "EXT_CTRL_CODE_FONT":
			var font_id := _font_id_from_arg(args[0]) if not args.is_empty() else ""
			if not font_id.is_empty():
				_layout_font_id = font_id
				_record_layout_control_event(event, {"kind": "font", "font_id": _layout_font_id})
		"FONT_NORMAL":
			_layout_font_id = "FONT_NORMAL"
			_record_layout_control_event(event, {"kind": "font", "font_id": _layout_font_id})
		"FONT_MALE", "FONT_FEMALE":
			_layout_font_id = "FONT_NORMAL"
			_record_layout_control_event(event, {"kind": "font", "font_id": _layout_font_id, "alias": command})
		"EXT_CTRL_CODE_RESET_FONT", "RESET_FONT":
			_record_layout_control_event(event, {
				"kind": "font_reset_noop",
				"font_id": _layout_font_id,
				"source_rule": "src/text.c:RenderText EXT_CTRL_CODE_RESET_FONT returns RENDER_REPEAT without changing fontId",
			})
		"EXT_CTRL_CODE_SHIFT_RIGHT", "SHIFT_RIGHT":
			var offset := int(args[0]) if not args.is_empty() else 0
			_layout_cursor.x = _layout_origin.x + offset
			_record_layout_control_event(event, {"kind": "shift_right", "x": _layout_cursor.x})
		"EXT_CTRL_CODE_SHIFT_DOWN", "SHIFT_DOWN":
			var offset := int(args[0]) if not args.is_empty() else 0
			_layout_cursor.y = _layout_origin.y + offset
			_record_layout_control_event(event, {"kind": "shift_down", "y": _layout_cursor.y})
		"EXT_CTRL_CODE_CLEAR", "CLEAR":
			var width := int(args[0]) if not args.is_empty() else 0
			_record_clear_text_span_effect(event, _text_span_rect(max(0, width)), width)
			_layout_cursor.x += max(0, width)
			_record_layout_control_event(event, {"kind": "clear_span", "width": width, "x": _layout_cursor.x})
		"EXT_CTRL_CODE_SKIP", "SKIP":
			var offset := int(args[0]) if not args.is_empty() else 0
			_layout_cursor.x = _layout_origin.x + offset
			_record_layout_control_event(event, {"kind": "skip", "x": _layout_cursor.x})
		"EXT_CTRL_CODE_CLEAR_TO", "CLEAR_TO":
			var target := _layout_origin.x + (int(args[0]) if not args.is_empty() else 0)
			if target > _layout_cursor.x:
				_record_clear_text_span_effect(event, _text_span_rect(target - _layout_cursor.x), target - _layout_cursor.x)
				_layout_cursor.x = target
			_record_layout_control_event(event, {"kind": "clear_to", "x": _layout_cursor.x})
		"EXT_CTRL_CODE_MIN_LETTER_SPACING", "MIN_LETTER_SPACING":
			_layout_min_letter_spacing = int(args[0]) if not args.is_empty() else 0
			_record_layout_control_event(event, {"kind": "min_letter_spacing", "value": _layout_min_letter_spacing})
		"EXT_CTRL_CODE_JPN", "JPN":
			_layout_japanese = true
			_record_layout_control_event(event, {"kind": "japanese_mode", "value": true})
		"EXT_CTRL_CODE_ENG", "ENG":
			_layout_japanese = false
			_record_layout_control_event(event, {"kind": "japanese_mode", "value": false})
		"EXT_CTRL_CODE_FILL_WINDOW", "FILL_WINDOW":
			_clear_visible_text(command)
			_record_layout_control_event(event, {"kind": "fill_window", "x": _layout_cursor.x, "y": _layout_cursor.y})
		_:
			_record_layout_control_event(event, {"kind": "style", "command": command})


func _apply_render_text_color_event(command: String, args: Array, event: Dictionary) -> bool:
	var changes := []
	match command:
		"EXT_CTRL_CODE_BACKGROUND", "BACKGROUND":
			_set_render_text_color_slot("background", args[0] if not args.is_empty() else null, changes)
		"EXT_CTRL_CODE_COLOR", "COLOR":
			_set_render_text_color_slot("foreground", args[0] if not args.is_empty() else null, changes)
		"EXT_CTRL_CODE_SHADOW", "SHADOW":
			_set_render_text_color_slot("shadow", args[0] if not args.is_empty() else null, changes)
		"EXT_CTRL_CODE_ACCENT", "ACCENT":
			_set_render_text_color_slot("accent", args[0] if not args.is_empty() else null, changes)
		"EXT_CTRL_CODE_HIGHLIGHT", "HIGHLIGHT":
			var highlight_value = args[0] if not args.is_empty() else null
			_set_render_text_color_slot("background", highlight_value, changes)
			_set_render_text_color_slot("accent", highlight_value, changes)
		"EXT_CTRL_CODE_COLOR_HIGHLIGHT_SHADOW", "COLOR_HIGHLIGHT_SHADOW":
			_set_render_text_color_slot("foreground", args[0] if args.size() > 0 else null, changes)
			_set_render_text_color_slot("background", args[1] if args.size() > 1 else null, changes)
			_set_render_text_color_slot("accent", args[1] if args.size() > 1 else null, changes)
			_set_render_text_color_slot("shadow", args[2] if args.size() > 2 else null, changes)
		"EXT_CTRL_CODE_TEXT_COLORS", "TEXT_COLORS":
			_set_render_text_color_slot("foreground", args[0] if args.size() > 0 else null, changes)
			_set_render_text_color_slot("shadow", args[1] if args.size() > 1 else null, changes)
			_set_render_text_color_slot("accent", args[2] if args.size() > 2 else null, changes)
		"EXT_CTRL_CODE_PALETTE", "PALETTE":
			_record_layout_control_event(event, {
				"kind": "render_text_material_bank_argument_skipped",
				"command": command,
				"arg": args[0] if not args.is_empty() else null,
				"source_rule": "src/text.c:RenderText skips EXT_CTRL_CODE_PALETTE argument in this path",
				"color_indices": _render_text_color_indices.duplicate(true),
			})
			return true
		_:
			return false
	if changes.is_empty():
		_add_unsupported("battle_text_unknown_color_control_argument")
	_record_layout_control_event(event, {
		"kind": "render_text_color",
		"command": command,
		"changes": changes,
		"color_indices": _render_text_color_indices.duplicate(true),
		"source_rule": "src/text.c:RenderText color control",
	})
	_render_text_color_control_count += 1
	return true


func _set_render_text_color_slot(slot: String, value, changes: Array) -> void:
	var color_index := _render_text_color_index_from_arg(value)
	if color_index < 0:
		return
	_render_text_color_indices[slot] = color_index
	changes.append({
		"slot": slot,
		"index": color_index,
	})


func _render_text_color_index_from_arg(value) -> int:
	if value == null:
		return -1
	if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
		return int(value) & 0xF
	var raw := String(value).strip_edges().to_upper()
	if raw.is_empty():
		return -1
	if TEXT_COLOR_NAME_TO_INDEX.has(raw):
		return int(TEXT_COLOR_NAME_TO_INDEX[raw])
	if raw.is_valid_int():
		return int(raw) & 0xF
	if raw.begins_with("0X") and raw.length() > 2:
		return int(raw.substr(2).hex_to_int()) & 0xF
	return -1


func _glyph_width_for_event(event: Dictionary, text: String, glyph_bytes: Array) -> int:
	if int(event.get("source_byte", -1)) == CHAR_KEYPAD_ICON:
		return 8
	var byte_value := _glyph_first_byte(event, text, glyph_bytes)
	if _is_chinese_glyph_bytes(glyph_bytes) or _is_chinese_punctuation_byte(byte_value):
		return _chinese_glyph_width(byte_value, glyph_bytes)
	var widths := _latin_widths_for_font(_layout_font_id)
	if byte_value >= 0 and byte_value < widths.size():
		return int(widths[byte_value])
	var font_record := _font_record(_layout_font_id)
	var fallback_width := int(font_record.get("max_letter_width", 8))
	return fallback_width if fallback_width > 0 else 8


func _glyph_height_for_event(_event: Dictionary, glyph_bytes: Array) -> int:
	var byte_value := int(glyph_bytes[0]) if not glyph_bytes.is_empty() else -1
	if _is_chinese_glyph_bytes(glyph_bytes) or _is_chinese_punctuation_byte(byte_value):
		var rule := _dictionary_value(_font_record(_layout_font_id).get("chinese_width_rule", {}))
		return int(rule.get("height", 15))
	var font_record := _font_record(_layout_font_id)
	var height := int(font_record.get("latin_glyph_height", font_record.get("max_letter_height", 0)))
	return height if height > 0 else 8


func _glyph_advance_px(width: int) -> int:
	if _layout_min_letter_spacing > 0:
		return max(width, _layout_min_letter_spacing)
	if _layout_japanese:
		return width + _font_letter_spacing(_layout_font_id)
	return width


func _attach_glyph_atlas_record(record: Dictionary, glyph_bytes: Array, event: Dictionary, text: String) -> void:
	var binding := _dictionary_value(_font_record(_layout_font_id).get("glyph_atlas", {}))
	if binding.is_empty() or String(binding.get("status", "")) != FONT_ATLAS_PREVIEW_STATUS:
		record["source_font_atlas_status"] = "missing_source_font_atlas"
		return
	var glyph_index := _glyph_atlas_index_for_event(event, text, glyph_bytes)
	if glyph_index < 0:
		record["source_font_atlas_status"] = "unsupported_glyph_index"
		return
	var atlas_kind := "chinese" if _is_chinese_glyph_bytes(glyph_bytes) else "latin"
	var image := String(binding.get("%s_image" % atlas_kind, ""))
	var columns := int(binding.get("%s_columns" % atlas_kind, 0))
	var capacity := int(binding.get("%s_glyph_capacity" % atlas_kind, 0))
	if image.is_empty() or columns <= 0 or glyph_index >= capacity:
		record["source_font_atlas_status"] = "glyph_out_of_atlas_range"
		record["source_font_atlas_glyph_index"] = glyph_index
		return
	var cell := _dictionary_value(binding.get("glyph_cell", {}))
	var cell_w := int(cell.get("w", 16))
	var cell_h := int(cell.get("h", 16))
	record["source_font_atlas_status"] = FONT_ATLAS_PREVIEW_STATUS
	record["source_font_atlas_kind"] = atlas_kind
	record["source_font_atlas_id"] = String(binding.get("%s_atlas_id" % atlas_kind, ""))
	record["source_font_atlas_image"] = image
	record["source_font_role_mask_status"] = String(binding.get("%s_role_mask_status" % atlas_kind, binding.get("role_mask_status", "")))
	record["source_font_role_mask_image"] = String(binding.get("%s_role_mask_image" % atlas_kind, ""))
	record["source_font_role_mask_encoding"] = String(binding.get("role_mask_encoding", ""))
	record["source_font_role_slots"] = _dictionary_value(binding.get("role_slots", {})).duplicate(true)
	record["source_font_atlas_glyph_index"] = glyph_index
	record["source_glyph_rect"] = [
		int(glyph_index % columns) * cell_w,
		int(glyph_index / columns) * cell_h,
		cell_w,
		cell_h,
	]
	record["source_glyph_visible_rect"] = [0, 0, int(record.get("width", cell_w)), int(record.get("height", cell_h))]


func _glyph_atlas_index_for_event(event: Dictionary, text: String, glyph_bytes: Array) -> int:
	if _is_chinese_glyph_bytes(glyph_bytes):
		return _chinese_source_glyph_index(glyph_bytes)
	var byte_value := _glyph_first_byte(event, text, glyph_bytes)
	if byte_value >= 0 and byte_value < 0x100:
		return byte_value
	return -1


func _chinese_source_glyph_index(glyph_bytes: Array) -> int:
	if glyph_bytes.size() < 2:
		return -1
	var high := int(glyph_bytes[0]) & 0xFF
	var low := int(glyph_bytes[1]) & 0xFF
	if high > 0x1B:
		high -= 1
	if high > 0x06:
		high -= 1
	high -= 1
	return (high << 8) | low


func _glyph_first_byte(event: Dictionary, text: String, glyph_bytes: Array) -> int:
	if not glyph_bytes.is_empty():
		return int(glyph_bytes[0]) & 0xFF
	if event.has("source_sub_code"):
		return int(event.get("source_sub_code", -1)) & 0x1FF
	if event.has("source_byte"):
		var source_byte := int(event.get("source_byte", -1))
		if source_byte >= 0 and source_byte < 0xF7:
			return source_byte & 0xFF
	if not text.is_empty():
		var first_char := text.substr(0, 1)
		if _single_byte_char_map.has(first_char):
			return int(_single_byte_char_map[first_char]) & 0xFF
		var codepoint := text.unicode_at(0)
		if codepoint >= 0 and codepoint < 0x100:
			return codepoint
	return -1


func _is_chinese_glyph_bytes(glyph_bytes: Array) -> bool:
	if glyph_bytes.size() < 2 or _layout_japanese or _layout_font_id == "FONT_BRAILLE":
		return false
	var high := int(glyph_bytes[0]) & 0xFF
	var low := int(glyph_bytes[1]) & 0xFF
	return high >= 0x01 and high <= 0x1E and high != 0x06 and high != 0x1B and low <= 0xF6


func _is_chinese_punctuation_byte(byte_value: int) -> bool:
	if byte_value < 0 or _layout_japanese or _layout_font_id == "FONT_BRAILLE":
		return false
	if byte_value == 0x30:
		return true
	return byte_value >= 0x36 and byte_value <= 0x3F and byte_value != 0x38


func _chinese_glyph_width(byte_value: int, glyph_bytes: Array) -> int:
	var rule := _dictionary_value(_font_record(_layout_font_id).get("chinese_width_rule", {}))
	var default_width := int(rule.get("default_width", 12))
	var punctuation_widths := _dictionary_value(rule.get("punctuation_widths", {}))
	if glyph_bytes.size() == 1 or _is_chinese_punctuation_byte(byte_value):
		var key := "0x%02X" % (byte_value & 0xFF)
		return int(punctuation_widths.get(key, default_width))
	return default_width


func _glyph_kind_for_event(event: Dictionary, text: String) -> String:
	if event.has("source_event_source"):
		return String(event.get("source_event_source", ""))
	if text.length() == 1 and text.unicode_at(0) > 0xFF:
		return "unicode_fallback"
	return "display_text"


func _font_record(font_id: String) -> Dictionary:
	var fonts := _dictionary_value(_font_metrics.get("fonts", {}))
	var record := _dictionary_value(fonts.get(font_id, {}))
	if record.is_empty():
		record = _dictionary_value(_font_metrics.get("active_font_metrics", {}))
	return record


func _latin_widths_for_font(font_id: String) -> Array:
	return _array_value(_font_record(font_id).get("latin_widths", []))


func _font_line_advance(font_id: String) -> int:
	var record := _font_record(font_id)
	var advance := int(record.get("line_advance", 0))
	if advance > 0:
		return advance
	return int(record.get("max_letter_height", 16)) + int(record.get("line_spacing", 0))


func _font_glyph_height(font_id: String) -> int:
	var record := _font_record(font_id)
	var height := int(record.get("latin_glyph_height", record.get("max_letter_height", 0)))
	return height if height > 0 else 8


func _font_letter_spacing(font_id: String) -> int:
	return int(_font_record(font_id).get("letter_spacing", 0))


func _source_font_atlas_status() -> String:
	if _font_atlas_binding_count > 0:
		return FONT_ATLAS_PREVIEW_STATUS
	return "missing_source_font_atlas"


func _count_font_atlas_bindings(metrics: Dictionary) -> void:
	_font_atlas_binding_count = 0
	var fonts := _dictionary_value(metrics.get("fonts", {}))
	if fonts.is_empty():
		var active := _dictionary_value(metrics.get("active_font_metrics", {}))
		if String(_dictionary_value(active.get("glyph_atlas", {})).get("status", "")) == FONT_ATLAS_PREVIEW_STATUS:
			_font_atlas_binding_count = 1
		return
	for font_id in fonts.keys():
		var record := _dictionary_value(fonts.get(font_id, {}))
		var binding := _dictionary_value(record.get("glyph_atlas", {}))
		if String(binding.get("status", "")) == FONT_ATLAS_PREVIEW_STATUS:
			_font_atlas_binding_count += 1


func _font_id_from_arg(value) -> String:
	var index := int(value)
	match index:
		0:
			return "FONT_SMALL"
		1:
			return "FONT_NORMAL"
		2:
			return "FONT_SHORT"
		3:
			return "FONT_SHORT_COPY_1"
		4:
			return "FONT_SHORT_COPY_2"
		5:
			return "FONT_SHORT_COPY_3"
		6:
			return "FONT_BRAILLE"
		7:
			return "FONT_NARROW"
		8:
			return "FONT_SMALL_NARROW"
		9:
			return "FONT_BOLD"
		10:
			return "FONT_NARROWER"
		11:
			return "FONT_SMALL_NARROWER"
		12:
			return "FONT_SHORT_NARROW"
		13:
			return "FONT_SHORT_NARROWER"
	return ""


func _has_font_metrics() -> bool:
	return not _dictionary_value(_font_metrics.get("fonts", {})).is_empty() or not _dictionary_value(_font_metrics.get("active_font_metrics", {})).is_empty()


func _copy_event_source_fields(event: Dictionary, target: Dictionary) -> void:
	for key in [
		"source_event_source",
		"source_offset",
		"source_byte",
		"source_sub_code",
		"source_control_code",
		"source_byte_count",
		"source_text_offset",
		"source_glyph_index",
		"source_glyph_hex",
	]:
		if event.has(key):
			target[key] = event.get(key)


func _ext_control_arg_count(control_code: int) -> int:
	match control_code:
		EXT_CTRL_CODE_COLOR_HIGHLIGHT_SHADOW, EXT_CTRL_CODE_TEXT_COLORS:
			return 3
		EXT_CTRL_CODE_PLAY_BGM, EXT_CTRL_CODE_PLAY_SE:
			return 2
		EXT_CTRL_CODE_COLOR, EXT_CTRL_CODE_HIGHLIGHT, EXT_CTRL_CODE_SHADOW, EXT_CTRL_CODE_PALETTE, EXT_CTRL_CODE_FONT, EXT_CTRL_CODE_PAUSE, EXT_CTRL_CODE_ESCAPE, EXT_CTRL_CODE_SHIFT_RIGHT, EXT_CTRL_CODE_SHIFT_DOWN, EXT_CTRL_CODE_CLEAR, EXT_CTRL_CODE_SKIP, EXT_CTRL_CODE_CLEAR_TO, EXT_CTRL_CODE_MIN_LETTER_SPACING, EXT_CTRL_CODE_SPEAKER, EXT_CTRL_CODE_ACCENT, EXT_CTRL_CODE_BACKGROUND:
			return 1
	return 0


func _ext_control_name(control_code: int) -> String:
	match control_code:
		EXT_CTRL_CODE_COLOR:
			return "EXT_CTRL_CODE_COLOR"
		EXT_CTRL_CODE_HIGHLIGHT:
			return "EXT_CTRL_CODE_HIGHLIGHT"
		EXT_CTRL_CODE_SHADOW:
			return "EXT_CTRL_CODE_SHADOW"
		EXT_CTRL_CODE_COLOR_HIGHLIGHT_SHADOW:
			return "EXT_CTRL_CODE_COLOR_HIGHLIGHT_SHADOW"
		EXT_CTRL_CODE_PALETTE:
			return "EXT_CTRL_CODE_PALETTE"
		EXT_CTRL_CODE_FONT:
			return "EXT_CTRL_CODE_FONT"
		EXT_CTRL_CODE_RESET_FONT:
			return "EXT_CTRL_CODE_RESET_FONT"
		EXT_CTRL_CODE_PAUSE:
			return "EXT_CTRL_CODE_PAUSE"
		EXT_CTRL_CODE_PAUSE_UNTIL_PRESS:
			return "EXT_CTRL_CODE_PAUSE_UNTIL_PRESS"
		EXT_CTRL_CODE_WAIT_SE:
			return "EXT_CTRL_CODE_WAIT_SE"
		EXT_CTRL_CODE_PLAY_BGM:
			return "EXT_CTRL_CODE_PLAY_BGM"
		EXT_CTRL_CODE_ESCAPE:
			return "EXT_CTRL_CODE_ESCAPE"
		EXT_CTRL_CODE_SHIFT_RIGHT:
			return "EXT_CTRL_CODE_SHIFT_RIGHT"
		EXT_CTRL_CODE_SHIFT_DOWN:
			return "EXT_CTRL_CODE_SHIFT_DOWN"
		EXT_CTRL_CODE_FILL_WINDOW:
			return "EXT_CTRL_CODE_FILL_WINDOW"
		EXT_CTRL_CODE_PLAY_SE:
			return "EXT_CTRL_CODE_PLAY_SE"
		EXT_CTRL_CODE_CLEAR:
			return "EXT_CTRL_CODE_CLEAR"
		EXT_CTRL_CODE_SKIP:
			return "EXT_CTRL_CODE_SKIP"
		EXT_CTRL_CODE_CLEAR_TO:
			return "EXT_CTRL_CODE_CLEAR_TO"
		EXT_CTRL_CODE_MIN_LETTER_SPACING:
			return "EXT_CTRL_CODE_MIN_LETTER_SPACING"
		EXT_CTRL_CODE_JPN:
			return "EXT_CTRL_CODE_JPN"
		EXT_CTRL_CODE_ENG:
			return "EXT_CTRL_CODE_ENG"
		EXT_CTRL_CODE_PAUSE_MUSIC:
			return "EXT_CTRL_CODE_PAUSE_MUSIC"
		EXT_CTRL_CODE_RESUME_MUSIC:
			return "EXT_CTRL_CODE_RESUME_MUSIC"
		EXT_CTRL_CODE_SPEAKER:
			return "EXT_CTRL_CODE_SPEAKER"
		EXT_CTRL_CODE_ACCENT:
			return "EXT_CTRL_CODE_ACCENT"
		EXT_CTRL_CODE_BACKGROUND:
			return "EXT_CTRL_CODE_BACKGROUND"
		EXT_CTRL_CODE_TEXT_COLORS:
			return "EXT_CTRL_CODE_TEXT_COLORS"
	return "EXT_CTRL_CODE_%02X" % control_code


func _dictionary_value(value) -> Dictionary:
	return value if typeof(value) == TYPE_DICTIONARY else {}


func _array_value(value) -> Array:
	return value if typeof(value) == TYPE_ARRAY else []


func _int_array_value(value) -> Array:
	var result: Array = []
	if typeof(value) != TYPE_ARRAY:
		return result
	for item in value:
		result.append(int(item) & 0xFF)
	return result
