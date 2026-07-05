extends RefCounted

const STATUS := "first_pass_plain_text_cadence"
const DEFAULT_PLAYER_TEXT_SPEED := "OPTIONS_TEXT_SPEED_FAST"
const SOURCE_SPEED_PLAYER_TEXT_DELAY := "player_text_speed_delay"
const SOURCE_TRACE := [
	"src/battle_message.c:BattlePutTextOnWindow",
	"src/text.c:GetPlayerTextSpeedDelay",
	"src/text.c:AddTextPrinter",
	"src/text.c:RunTextPrinters",
	"src/text.c:RenderText",
]
const FIRST_PASS_UNSUPPORTED := [
	"battle_text_glyph_renderer_pending",
	"battle_text_source_byte_stream_pending",
	"battle_text_control_codes_pending",
	"battle_text_wait_page_down_arrow_pending",
	"battle_text_ab_speedup_input_pending",
	"battle_text_link_recorded_speed_overrides_pending",
]

var _window_id := ""
var _full_text := ""
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
var _player_text_speed_is_instant := false
var _can_ab_speed_up_print := false
var _unsupported: Array = []


func start(window_id: String, text: String, text_info: Dictionary, text_printer_metadata: Dictionary, options: Dictionary = {}) -> void:
	_window_id = window_id
	_full_text = _display_text(text)
	_visible_char_count = 0
	_delay_counter = 0
	_frame_count = 0
	_render_call_count = 0
	_active = false
	_complete = false
	_synchronous_render = false
	_source_speed = text_info.get("source_speed", text_info.get("table_speed", 0))
	_can_ab_speed_up_print = bool(text_info.get("can_ab_speed_up_print", false))
	_unsupported = FIRST_PASS_UNSUPPORTED.duplicate(true)
	_resolve_player_text_speed(text_printer_metadata, options)
	_resolve_frame_delay(text_info, text_printer_metadata, options)
	_note_text_limitations()

	if _full_text.is_empty() or _resolved_frame_delay == 0:
		_visible_char_count = _full_text.length()
		_active = false
		_complete = true
		_synchronous_render = true
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
			_render_all_remaining()
			continue
		var repeats: int = max(1, _player_text_speed_modifier)
		for _repeat_index in range(repeats):
			_render_step(input)
			if not _active:
				break
	return snapshot()


func skip_to_end() -> Dictionary:
	_render_all_remaining()
	_synchronous_render = true
	return snapshot()


func get_visible_text() -> String:
	return _full_text.substr(0, _visible_char_count)


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
		"player_text_speed_is_instant": _player_text_speed_is_instant,
		"can_ab_speed_up_print": _can_ab_speed_up_print,
		"synchronous_render": _synchronous_render,
		"source_trace": SOURCE_TRACE.duplicate(true),
		"unsupported": _unsupported.duplicate(true),
	}


func _render_step(_input: Dictionary) -> void:
	if not _active:
		return
	_render_call_count += 1
	if _delay_counter > 0 and _source_text_speed > 0:
		_delay_counter -= 1
		return
	_delay_counter = _source_text_speed
	_visible_char_count = min(_visible_char_count + 1, _full_text.length())
	if _visible_char_count >= _full_text.length():
		_active = false
		_complete = true


func _render_all_remaining() -> void:
	if _full_text.is_empty():
		_visible_char_count = 0
	else:
		_visible_char_count = _full_text.length()
	_active = false
	_complete = true
	_delay_counter = 0


func _resolve_player_text_speed(text_printer_metadata: Dictionary, options: Dictionary) -> void:
	_player_text_speed = String(options.get("player_text_speed", DEFAULT_PLAYER_TEXT_SPEED))
	var player_speed: Dictionary = _dictionary_value(text_printer_metadata.get("player_text_speed", {}))
	var modifiers: Dictionary = _dictionary_value(player_speed.get("modifiers", {}))
	_player_text_speed_modifier = int(modifiers.get(_player_text_speed, 1))
	if _player_text_speed_modifier <= 0:
		_player_text_speed_modifier = 1
	_player_text_speed_is_instant = _player_text_speed == "OPTIONS_TEXT_SPEED_INSTANT"


func _resolve_frame_delay(text_info: Dictionary, text_printer_metadata: Dictionary, options: Dictionary) -> void:
	if options.has("battle_text_speed_override"):
		_resolved_frame_delay = max(0, int(options.get("battle_text_speed_override", 0)))
		_effective_speed_source = "option_battle_text_speed_override"
		return
	if typeof(_source_speed) == TYPE_STRING and String(_source_speed) == SOURCE_SPEED_PLAYER_TEXT_DELAY:
		var player_speed: Dictionary = _dictionary_value(text_printer_metadata.get("player_text_speed", {}))
		var frame_delays: Dictionary = _dictionary_value(player_speed.get("frame_delays", {}))
		_resolved_frame_delay = max(0, int(frame_delays.get(_player_text_speed, 1)))
		_effective_speed_source = "GetPlayerTextSpeedDelay:%s" % _player_text_speed
		return
	_resolved_frame_delay = max(0, int(text_info.get("source_speed", text_info.get("table_speed", 0))))
	_effective_speed_source = "sTextOnWindowsInfo_Normal.speed"


func _note_text_limitations() -> void:
	if _full_text.find("{") >= 0 and _full_text.find("}") > _full_text.find("{"):
		_add_unsupported("battle_text_runtime_control_token_seen")
	if _full_text.find("\n") >= 0:
		_add_unsupported("battle_text_newline_layout_approximation")


func _add_unsupported(code: String) -> void:
	if not _unsupported.has(code):
		_unsupported.append(code)


func _display_text(text: String) -> String:
	return text.replace("\t", "    ")


func _dictionary_value(value) -> Dictionary:
	return value if typeof(value) == TYPE_DICTIONARY else {}
