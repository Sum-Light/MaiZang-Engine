extends SceneTree

const DATA_REGISTRY_SCRIPT := preload("res://scripts/autoload/data_registry.gd")
const BATTLE_TEXT_PRINTER_SCRIPT := preload("res://scripts/battle/battle_text_printer.gd")

var _failed := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var registry = DATA_REGISTRY_SCRIPT.new()
	registry._ready()
	var interface_data := _dict(registry.get_battle_interface_data())
	var templates := _dict(interface_data.get("window_templates", {}))
	var text_printer_metadata := _dict(interface_data.get("text_printer", {}))
	var message_info := _dict(_dict(templates.get("B_WIN_MSG", {})).get("text_info", {}))
	var action_menu_info := _dict(_dict(templates.get("B_WIN_ACTION_MENU", {})).get("text_info", {}))

	var slow_printer = BATTLE_TEXT_PRINTER_SCRIPT.new()
	slow_printer.start("B_WIN_MSG", "ABC", message_info, text_printer_metadata, {
		"player_text_speed": "OPTIONS_TEXT_SPEED_SLOW",
	})
	var initial := _dict(slow_printer.snapshot())
	_assert(String(initial.get("status", "")) == "first_pass_source_glyph_layout", "expected first-pass printer status")
	_assert(String(slow_printer.get_visible_text()) == "", "expected async message to start hidden")
	_assert(int(initial.get("resolved_frame_delay", 0)) == 8, "expected slow player text delay")
	_assert(int(initial.get("source_add_text_printer_text_speed", -1)) == 7, "expected AddTextPrinter speed minus one")
	_assert(String(initial.get("effective_speed_source", "")).contains("OPTIONS_TEXT_SPEED_SLOW"), "expected slow speed source metadata")

	slow_printer.advance_frames(1)
	_assert(String(slow_printer.get_visible_text()) == "A", "expected first glyph on first render frame")
	slow_printer.advance_frames(7)
	_assert(String(slow_printer.get_visible_text()) == "A", "expected slow delay before second glyph")
	slow_printer.advance_frames(1)
	_assert(String(slow_printer.get_visible_text()) == "AB", "expected second glyph after slow delay")
	slow_printer.skip_to_end()
	_assert(String(slow_printer.get_visible_text()) == "ABC", "expected skip to complete text")
	_assert(bool(_dict(slow_printer.snapshot()).get("is_complete", false)), "expected complete after skip")

	var instant_menu_printer = BATTLE_TEXT_PRINTER_SCRIPT.new()
	instant_menu_printer.start("B_WIN_ACTION_MENU", "Fight\tBag", action_menu_info, text_printer_metadata)
	var menu_snapshot := _dict(instant_menu_printer.snapshot())
	_assert(String(instant_menu_printer.get_visible_text()) == "Fight    Bag", "expected speed-zero menu text immediately visible")
	_assert(bool(menu_snapshot.get("synchronous_render", false)), "expected speed-zero source path to render synchronously")
	_assert(int(menu_snapshot.get("resolved_frame_delay", -1)) == 0, "expected action menu source speed zero")
	var menu_layout := _dict(menu_snapshot.get("source_glyph_layout", {}))
	_assert(String(menu_snapshot.get("source_glyph_layout_status", "")) == "source_metrics_layout", "expected generated source font metrics")
	_assert(int(menu_layout.get("glyph_count", 0)) == String(instant_menu_printer.get_visible_text()).length(), "expected synchronous menu layout glyph count")

	var instant_player_printer = BATTLE_TEXT_PRINTER_SCRIPT.new()
	instant_player_printer.start("B_WIN_MSG", "XYZ", message_info, text_printer_metadata, {
		"player_text_speed": "OPTIONS_TEXT_SPEED_INSTANT",
	})
	_assert(String(instant_player_printer.get_visible_text()) == "", "expected instant player speed to wait for RunTextPrinters")
	instant_player_printer.advance_frames(1)
	var instant_snapshot := _dict(instant_player_printer.snapshot())
	_assert(String(instant_player_printer.get_visible_text()) == "XYZ", "expected instant player text speed to finish on first frame")
	_assert(bool(instant_snapshot.get("player_text_speed_is_instant", false)), "expected instant speed metadata")
	_assert(int(instant_snapshot.get("player_text_speed_modifier", 0)) == 12, "expected source instant text modifier")

	var speedup_printer = BATTLE_TEXT_PRINTER_SCRIPT.new()
	speedup_printer.start("B_WIN_MSG", "ABC", message_info, text_printer_metadata, {
		"player_text_speed": "OPTIONS_TEXT_SPEED_SLOW",
	})
	speedup_printer.advance_frames(1)
	speedup_printer.advance_frames(1, {"a_pressed": true})
	var speedup_pressed := _dict(speedup_printer.snapshot())
	_assert(String(speedup_printer.get_visible_text()) == "A", "expected A/B press to clear delay before next glyph")
	_assert(bool(speedup_pressed.get("has_print_been_sped_up", false)), "expected source A/B speed-up flag")
	_assert(int(speedup_pressed.get("ab_speedup_count", 0)) == 1, "expected one A/B speed-up event")
	speedup_printer.advance_frames(1, {"a_held": true})
	_assert(String(speedup_printer.get_visible_text()) == "AB", "expected held A/B to render next glyph on following frame")

	var pause_printer = BATTLE_TEXT_PRINTER_SCRIPT.new()
	pause_printer.start("B_WIN_MSG", "{PAUSE 2}AB", message_info, text_printer_metadata)
	pause_printer.advance_frames(1)
	var pause_start := _dict(pause_printer.snapshot())
	_assert(String(pause_printer.get_visible_text()) == "", "expected pause control to stay hidden")
	_assert(String(pause_start.get("wait_state", "")) == "pause", "expected pause render state")
	_assert(int(pause_start.get("pause_counter", 0)) == 2, "expected pause frame count")
	pause_printer.advance_frames(3)
	_assert(String(pause_printer.get_visible_text()) == "", "expected pause to clear before printing next glyph")
	pause_printer.advance_frames(1)
	_assert(String(pause_printer.get_visible_text()) == "A", "expected text after pause clears")
	var pause_after := _dict(pause_printer.snapshot())
	_assert(int(pause_after.get("pause_event_count", 0)) == 1, "expected one pause control event")

	var page_printer = BATTLE_TEXT_PRINTER_SCRIPT.new()
	page_printer.start("B_WIN_MSG", "A\n\nB", message_info, text_printer_metadata)
	page_printer.advance_frames(1)
	page_printer.advance_frames(1)
	var page_wait := _dict(page_printer.snapshot())
	_assert(String(page_printer.get_visible_text()) == "A\n\n", "expected paragraph marker visible as display-text page break")
	_assert(String(page_wait.get("wait_state", "")) == "wait_with_down_arrow", "expected prompt-scroll wait state")
	_assert(bool(page_wait.get("down_arrow_visible", false)), "expected down-arrow metadata while waiting")
	_assert(int(page_wait.get("page_wait_count", 0)) == 1, "expected one page wait event")
	page_printer.advance_frames(2)
	_assert(String(page_printer.get_visible_text()) == "A\n\n", "expected page wait to block without input")
	page_printer.advance_frames(1, {"b_pressed": true})
	page_printer.advance_frames(1)
	_assert(String(page_printer.get_visible_text()) == "A\n\nB", "expected B press to release page wait")
	_assert(String(page_wait.get("event_stream_source", "")) == "display_text", "expected display-text event stream without source text")

	var source_page_printer = BATTLE_TEXT_PRINTER_SCRIPT.new()
	source_page_printer.start("B_WIN_MSG", "A\n\nB", message_info, text_printer_metadata, {
		"source_text": "A\\pB",
		"source_text_label": "fixture_prompt_scroll",
	})
	source_page_printer.advance_frames(1)
	source_page_printer.advance_frames(1)
	var source_page_wait := _dict(source_page_printer.snapshot())
	_assert(String(source_page_wait.get("event_stream_source", "")) == "source_text", "expected source-text event stream")
	_assert(String(source_page_wait.get("event_stream_status", "")) == "first_pass_source_text_events", "expected source-text event stream status")
	_assert(String(source_page_wait.get("source_text_label", "")) == "fixture_prompt_scroll", "expected source text label metadata")
	_assert(String(source_page_printer.get_visible_text()) == "A\n\n", "expected source \\p to become prompt-scroll visible text")
	_assert(String(source_page_wait.get("wait_state", "")) == "wait_with_down_arrow", "expected source \\p page wait state")
	_assert(int(source_page_wait.get("page_wait_count", 0)) == 1, "expected source \\p page wait count")

	var source_pause_printer = BATTLE_TEXT_PRINTER_SCRIPT.new()
	source_pause_printer.start("B_WIN_MSG", "AB", message_info, text_printer_metadata, {
		"source_text": "{PAUSE 2}AB",
		"text_controls": [{"command": "PAUSE"}],
	})
	source_pause_printer.advance_frames(1)
	var source_pause := _dict(source_pause_printer.snapshot())
	_assert(String(source_pause.get("event_stream_source", "")) == "source_text", "expected source pause event stream")
	_assert(String(source_pause.get("wait_state", "")) == "pause", "expected source pause wait state")
	_assert(int(source_pause.get("source_text_control_metadata_count", 0)) == 1, "expected source text control metadata count")
	source_pause_printer.advance_frames(4)
	_assert(String(source_pause_printer.get_visible_text()) == "A", "expected source pause to reveal text after clearing")

	var source_newline_printer = BATTLE_TEXT_PRINTER_SCRIPT.new()
	source_newline_printer.start("B_WIN_MSG", "A\nB", message_info, text_printer_metadata, {
		"source_text": "A\\lB$",
	})
	source_newline_printer.skip_to_end()
	_assert(String(source_newline_printer.get_visible_text()) == "A\nB", "expected source \\l and trailing terminator handling")

	var byte_newline_printer = BATTLE_TEXT_PRINTER_SCRIPT.new()
	byte_newline_printer.start("B_WIN_MSG", "A\nB", message_info, text_printer_metadata, {
		"source_text": "AB",
		"source_bytes": [0x41, 0xFE, 0x42],
	})
	byte_newline_printer.skip_to_end()
	var byte_newline := _dict(byte_newline_printer.snapshot())
	_assert(String(byte_newline_printer.get_visible_text()) == "A\nB", "expected source byte CHAR_NEWLINE event independent of source text escapes")
	_assert(int(byte_newline.get("source_byte_event_count", 0)) == 3, "expected three source byte events for A newline B")

	var byte_glyph_printer = BATTLE_TEXT_PRINTER_SCRIPT.new()
	byte_glyph_printer.start("B_WIN_MSG", "G", message_info, text_printer_metadata, {
		"source_text": "G",
		"source_bytes": [0x0F, 0x0B],
		"source_glyphs": [{
			"text": "G",
			"source_offset": 0,
			"byte_offset": 0,
			"byte_count": 2,
			"bytes": [0x0F, 0x0B],
			"hex": "0F 0B",
		}],
	})
	byte_glyph_printer.advance_frames(1)
	var byte_glyph := _dict(byte_glyph_printer.snapshot())
	var byte_glyph_layout := _dict(byte_glyph.get("source_glyph_layout", {}))
	var byte_glyph_layout_glyphs := _array(byte_glyph_layout.get("glyphs", []))
	var byte_glyph_layout_first := _dict(byte_glyph_layout_glyphs[0]) if not byte_glyph_layout_glyphs.is_empty() else {}
	_assert(String(byte_glyph_printer.get_visible_text()) == "G", "expected one glyph from a two-byte source span")
	_assert(int(byte_glyph.get("source_glyph_count", 0)) == 1, "expected one source glyph span")
	_assert(int(byte_glyph.get("source_byte_event_count", 0)) == 1, "expected two source bytes to map to one glyph event")
	_assert(int(byte_glyph.get("event_count", 0)) == 1, "expected one event for grouped source glyph bytes")
	_assert(String(byte_glyph.get("source_glyph_layout_status", "")) == "source_metrics_layout", "expected source metrics layout for grouped glyph")
	_assert(int(byte_glyph_layout.get("glyph_count", 0)) == 1, "expected one source glyph layout record")
	_assert(int(byte_glyph_layout_first.get("width", 0)) == 12, "expected source Chinese glyph width")
	_assert(int(byte_glyph_layout_first.get("height", 0)) == 15, "expected source Chinese glyph height")
	_assert(int(byte_glyph_layout_first.get("advance", 0)) == 12, "expected source Chinese glyph advance")
	_assert(int(byte_glyph_layout_first.get("source_byte_count", 0)) == 2, "expected two bytes on grouped glyph layout")
	_assert(_array(byte_glyph_layout_first.get("source_byte_span", [])) == [0x0F, 0x0B], "expected layout source byte span")

	var byte_clear_printer = BATTLE_TEXT_PRINTER_SCRIPT.new()
	byte_clear_printer.start("B_WIN_MSG", "AB", message_info, text_printer_metadata, {
		"source_text": "AB",
		"source_bytes": [0x41, 0xFB, 0x42],
		"source_encoding_hex": "41 FB 42",
	})
	byte_clear_printer.advance_frames(1)
	byte_clear_printer.advance_frames(1)
	var byte_clear_wait := _dict(byte_clear_printer.snapshot())
	var byte_clear_summary := _dict(byte_clear_wait.get("source_byte_control_summary", {}))
	var byte_clear_log := _array(byte_clear_wait.get("event_log", []))
	var byte_clear_event := _dict(byte_clear_log[0]) if not byte_clear_log.is_empty() else {}
	_assert(String(byte_clear_wait.get("event_stream_source", "")) == "source_bytes", "expected source-byte event stream")
	_assert(String(byte_clear_wait.get("event_stream_status", "")) == "first_pass_source_byte_control_events", "expected source-byte event stream status")
	_assert(String(byte_clear_wait.get("wait_state", "")) == "wait_clear", "expected source byte CHAR_PROMPT_CLEAR wait")
	_assert(String(byte_clear_printer.get_visible_text()) == "A", "expected source byte clear wait to keep current page visible")
	_assert(int(byte_clear_wait.get("prompt_clear_count", 0)) == 1, "expected one source byte prompt-clear event")
	_assert(int(byte_clear_summary.get("prompt_clear_count", 0)) == 1, "expected one source byte prompt-clear summary")
	_assert(String(byte_clear_event.get("source_event_source", "")) == "source_bytes", "expected prompt-clear event to come from source bytes")
	_assert(int(byte_clear_event.get("source_offset", -1)) == 1, "expected prompt-clear byte source offset")
	byte_clear_printer.advance_frames(1, {"a_pressed": true})
	_assert(String(byte_clear_printer.get_visible_text()) == "", "expected source byte prompt clear to clear visible text after input")
	byte_clear_printer.advance_frames(1)
	_assert(String(byte_clear_printer.get_visible_text()) == "B", "expected source byte text after prompt clear")

	var byte_scroll_printer = BATTLE_TEXT_PRINTER_SCRIPT.new()
	byte_scroll_printer.start("B_WIN_MSG", "A\nB", message_info, text_printer_metadata, {
		"source_text": "AB",
		"source_bytes": [0x41, 0xFA, 0x42],
	})
	byte_scroll_printer.advance_frames(1)
	byte_scroll_printer.advance_frames(1)
	var byte_scroll_wait := _dict(byte_scroll_printer.snapshot())
	var byte_scroll_summary := _dict(byte_scroll_wait.get("source_byte_control_summary", {}))
	_assert(String(byte_scroll_wait.get("wait_state", "")) == "wait_with_down_arrow", "expected source byte CHAR_PROMPT_SCROLL wait")
	_assert(int(byte_scroll_wait.get("prompt_scroll_count", 0)) == 1, "expected one source byte prompt-scroll event")
	_assert(int(byte_scroll_summary.get("prompt_scroll_count", 0)) == 1, "expected one source byte prompt-scroll summary")

	var byte_pause_printer = BATTLE_TEXT_PRINTER_SCRIPT.new()
	byte_pause_printer.start("B_WIN_MSG", "A", message_info, text_printer_metadata, {
		"source_text": "A",
		"source_bytes": [0xFC, 0x08, 0x02, 0x41],
	})
	byte_pause_printer.advance_frames(1)
	var byte_pause := _dict(byte_pause_printer.snapshot())
	var byte_pause_summary := _dict(byte_pause.get("source_byte_control_summary", {}))
	var byte_ext_controls := _array(byte_pause_summary.get("ext_controls", []))
	var byte_pause_control := _dict(byte_ext_controls[0]) if not byte_ext_controls.is_empty() else {}
	_assert(String(byte_pause.get("event_stream_source", "")) == "source_bytes", "expected source byte pause event stream")
	_assert(String(byte_pause.get("wait_state", "")) == "pause", "expected source byte pause wait state")
	_assert(String(byte_pause_control.get("name", "")) == "EXT_CTRL_CODE_PAUSE", "expected source byte EXT_CTRL_CODE_PAUSE summary")
	_assert(_array(byte_pause_control.get("args", [])) == [2], "expected source byte pause arg")

	var audio_printer = BATTLE_TEXT_PRINTER_SCRIPT.new()
	audio_printer.start("B_WIN_MSG", "A{PLAY_SE SE_SELECT}{WAIT_SE}B", message_info, text_printer_metadata)
	audio_printer.advance_frames(1)
	audio_printer.advance_frames(1)
	var audio_snapshot := _dict(audio_printer.snapshot())
	_assert(int(audio_snapshot.get("audio_cue_count", 0)) == 2, "expected PLAY_SE and WAIT_SE metadata events")
	_assert(int(audio_snapshot.get("wait_se_count", 0)) == 1, "expected one WAIT_SE event")
	_assert(String(audio_printer.get_visible_text()) == "A", "expected audio metadata frame before next glyph")
	audio_printer.advance_frames(1)
	_assert(String(audio_printer.get_visible_text()) == "AB", "expected metadata-only audio wait to continue")

	var link_printer = BATTLE_TEXT_PRINTER_SCRIPT.new()
	link_printer.start("B_WIN_MSG", "AB", message_info, text_printer_metadata, {
		"battle_text_mode": "link",
		"player_text_speed": "OPTIONS_TEXT_SPEED_SLOW",
	})
	var link_snapshot := _dict(link_printer.snapshot())
	_assert(int(link_snapshot.get("resolved_frame_delay", 0)) == 1, "expected link battle text speed override")
	_assert(bool(link_snapshot.get("auto_scroll", false)), "expected link battle auto-scroll metadata")

	if _failed:
		return
	print(JSON.stringify({
		"battle_text_printer_smoke": "ok",
		"slow_delay": int(initial.get("resolved_frame_delay", 0)),
		"instant_modifier": int(instant_snapshot.get("player_text_speed_modifier", 0)),
		"control_events": int(audio_snapshot.get("control_event_count", 0)) + int(pause_after.get("control_event_count", 0)),
		"page_waits": int(page_wait.get("page_wait_count", 0)),
		"source_page_waits": int(source_page_wait.get("page_wait_count", 0)),
		"byte_events": int(byte_newline.get("source_byte_event_count", 0)),
		"byte_glyph_events": int(byte_glyph.get("source_byte_event_count", 0)),
		"byte_prompt_clears": int(byte_clear_wait.get("prompt_clear_count", 0)),
		"byte_prompt_scrolls": int(byte_scroll_wait.get("prompt_scroll_count", 0)),
		"source_glyph_width": int(byte_glyph_layout_first.get("width", 0)),
		"ab_speedups": int(speedup_pressed.get("ab_speedup_count", 0)),
	}))
	registry.free()
	quit(0)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true
	quit(1)


func _dict(value) -> Dictionary:
	return value if typeof(value) == TYPE_DICTIONARY else {}


func _array(value) -> Array:
	return value if typeof(value) == TYPE_ARRAY else []
