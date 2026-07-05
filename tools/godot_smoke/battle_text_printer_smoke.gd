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
	_assert(String(menu_snapshot.get("source_font_atlas_status", "")) == "source_font_atlas_preview", "expected generated source font atlas binding")
	_assert(int(menu_snapshot.get("source_font_atlas_binding_count", 0)) == 12, "expected source font atlas binding count")
	_assert(int(menu_layout.get("glyph_count", 0)) == String(instant_menu_printer.get_visible_text()).length(), "expected synchronous menu layout glyph count")
	var menu_layout_glyphs := _array(menu_layout.get("glyphs", []))
	var first_menu_glyph := _dict(menu_layout_glyphs[0])
	_assert(String(first_menu_glyph.get("source_font_atlas_status", "")) == "source_font_atlas_preview", "expected first menu glyph atlas status")
	_assert(String(first_menu_glyph.get("source_font_atlas_id", "")) == "latin_normal", "expected first menu glyph Latin normal atlas")
	_assert(String(first_menu_glyph.get("source_font_role_mask_status", "")) == "generated_source_font_role_mask", "expected first menu glyph source role mask")
	_assert(int(first_menu_glyph.get("source_font_atlas_glyph_index", 0)) == 0xC0, "expected F glyph source charmap atlas index")
	_assert(_array(first_menu_glyph.get("source_glyph_rect", [])) == [0, 192, 16, 16], "expected F glyph charmap atlas rect")

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

	var byte_color_printer = BATTLE_TEXT_PRINTER_SCRIPT.new()
	byte_color_printer.start("B_WIN_MSG", "AB", message_info, text_printer_metadata, {
		"source_text": "AB",
		"source_bytes": [0xBB, 0xFC, 0x01, 0x04, 0xBC],
	})
	byte_color_printer.skip_to_end()
	var byte_color := _dict(byte_color_printer.snapshot())
	var byte_color_layout := _dict(byte_color.get("source_glyph_layout", {}))
	var byte_color_glyphs := _array(byte_color_layout.get("glyphs", []))
	var byte_color_first := _dict(byte_color_glyphs[0]) if byte_color_glyphs.size() > 0 else {}
	var byte_color_second := _dict(byte_color_glyphs[1]) if byte_color_glyphs.size() > 1 else {}
	var byte_color_first_indices := _dict(byte_color_first.get("render_text_color_indices", {}))
	var byte_color_second_indices := _dict(byte_color_second.get("render_text_color_indices", {}))
	_assert(String(byte_color_printer.get_visible_text()) == "AB", "expected source byte color fixture visible text")
	_assert(int(byte_color.get("render_text_color_control_count", 0)) == 1, "expected one RenderText color control")
	_assert(int(byte_color_first_indices.get("foreground", 0)) == 1, "expected initial message foreground before color control")
	_assert(int(byte_color_second_indices.get("foreground", 0)) == 4, "expected red foreground after EXT_CTRL_CODE_COLOR")

	var byte_layout_control_printer = BATTLE_TEXT_PRINTER_SCRIPT.new()
	byte_layout_control_printer.start("B_WIN_MSG", "FPFFPFPF", message_info, text_printer_metadata, {
		"source_text": "FPFFPFPF",
		"source_bytes": [
			0xC0,
			0xFC, 0x0D, 20,
			0xCA,
			0xFC, 0x0E, 8,
			0xC0,
			0xFC, 0x14, 12,
			0xC0,
			0xCA,
			0xFC, 0x12, 4,
			0xC0,
			0xFC, 0x1B, 2,
			0xFC, 0x11, 4,
			0xCA,
			0xFC, 0x13, 50,
			0xC0,
			0xFF,
		],
		"source_glyphs": [
			{"byte_offset": 0, "bytes": [0xC0], "text": "F", "hex": "C0"},
			{"byte_offset": 4, "bytes": [0xCA], "text": "P", "hex": "CA"},
			{"byte_offset": 8, "bytes": [0xC0], "text": "F", "hex": "C0"},
			{"byte_offset": 12, "bytes": [0xC0], "text": "F", "hex": "C0"},
			{"byte_offset": 13, "bytes": [0xCA], "text": "P", "hex": "CA"},
			{"byte_offset": 17, "bytes": [0xC0], "text": "F", "hex": "C0"},
			{"byte_offset": 24, "bytes": [0xCA], "text": "P", "hex": "CA"},
			{"byte_offset": 28, "bytes": [0xC0], "text": "F", "hex": "C0"},
		],
	})
	byte_layout_control_printer.skip_to_end()
	var byte_layout_control := _dict(byte_layout_control_printer.snapshot())
	var byte_layout_summary := _dict(byte_layout_control.get("render_text_control_summary", {}))
	var byte_layout_pixel_summary := _dict(byte_layout_control.get("source_window_pixel_effect_summary", {}))
	var byte_layout_source_summary := _dict(byte_layout_control.get("source_byte_control_summary", {}))
	var byte_layout := _dict(byte_layout_control.get("source_glyph_layout", {}))
	var byte_layout_origin := _array(byte_layout.get("origin", []))
	var byte_layout_glyphs := _array(byte_layout.get("glyphs", []))
	var byte_layout_origin_x := int(byte_layout_origin[0]) if byte_layout_origin.size() > 0 else 0
	var byte_layout_origin_y := int(byte_layout_origin[1]) if byte_layout_origin.size() > 1 else 0
	var shift_right_glyph := _glyph_by_source_offset(byte_layout_glyphs, 4)
	var shift_down_glyph := _glyph_by_source_offset(byte_layout_glyphs, 8)
	var skip_glyph := _glyph_by_source_offset(byte_layout_glyphs, 17)
	var clear_to_glyph := _glyph_by_source_offset(byte_layout_glyphs, 28)
	_assert(String(byte_layout_control.get("render_text_control_status", "")) == "source_render_text_control_side_effects_first_pass", "expected RenderText control summary status")
	_assert(int(byte_layout_source_summary.get("ext_control_count", 0)) == 7, "expected seven source byte EXT controls")
	_assert(int(byte_layout_summary.get("shift_right_count", 0)) == 1, "expected one shift-right control")
	_assert(int(byte_layout_summary.get("shift_down_count", 0)) == 1, "expected one shift-down control")
	_assert(int(byte_layout_summary.get("skip_count", 0)) == 1, "expected one skip control")
	_assert(int(byte_layout_summary.get("clear_span_count", 0)) == 1, "expected one clear-span control")
	_assert(int(byte_layout_summary.get("clear_to_count", 0)) == 1, "expected one clear-to control")
	_assert(int(byte_layout_summary.get("min_letter_spacing_count", 0)) == 1, "expected one min-letter-spacing control")
	_assert(int(byte_layout_pixel_summary.get("clear_text_span_count", 0)) == 2, "expected CLEAR and CLEAR_TO pixel spans")
	_assert(int(byte_layout_pixel_summary.get("clear_text_span_filled_count", 0)) == 2, "expected CLEAR and CLEAR_TO to use filled background material")
	_assert(int(shift_right_glyph.get("x", -1)) == byte_layout_origin_x + 20, "expected SHIFT_RIGHT to set currentX from source origin")
	_assert(int(shift_down_glyph.get("y", -1)) == byte_layout_origin_y + 8, "expected SHIFT_DOWN to set currentY from source origin")
	_assert(int(skip_glyph.get("advance", 0)) == max(int(skip_glyph.get("width", 0)), 12), "expected MIN_LETTER_SPACING to clamp later glyph advance")
	_assert(int(skip_glyph.get("x", -1)) == byte_layout_origin_x + 4, "expected SKIP to set currentX from source origin")
	_assert(int(clear_to_glyph.get("x", -1)) == byte_layout_origin_x + 50, "expected CLEAR_TO to advance to source target x")

	var byte_fill_printer = BATTLE_TEXT_PRINTER_SCRIPT.new()
	byte_fill_printer.start("B_WIN_MSG", "FP", message_info, text_printer_metadata, {
		"source_text": "FP",
		"source_bytes": [0xC0, 0xFC, 0x1B, 2, 0xFC, 0x0F, 0xCA, 0xFF],
		"source_glyphs": [
			{"byte_offset": 0, "bytes": [0xC0], "text": "F", "hex": "C0"},
			{"byte_offset": 6, "bytes": [0xCA], "text": "P", "hex": "CA"},
		],
	})
	byte_fill_printer.skip_to_end()
	var byte_fill := _dict(byte_fill_printer.snapshot())
	var byte_fill_summary := _dict(byte_fill.get("render_text_control_summary", {}))
	var byte_fill_pixel_summary := _dict(byte_fill.get("source_window_pixel_effect_summary", {}))
	var byte_fill_layout := _dict(byte_fill.get("source_glyph_layout", {}))
	var byte_fill_glyphs := _array(byte_fill_layout.get("glyphs", []))
	var byte_fill_first_glyph := _dict(byte_fill_glyphs[0]) if not byte_fill_glyphs.is_empty() else {}
	_assert(String(byte_fill_printer.get_visible_text()) == "P", "expected FILL_WINDOW to clear prior visible text")
	_assert(int(byte_fill_summary.get("fill_window_count", 0)) == 1, "expected one fill-window control")
	_assert(int(byte_fill_summary.get("clear_visible_text_count", 0)) == 1, "expected fill-window to clear visible layout")
	_assert(int(byte_fill_pixel_summary.get("fill_window_count", 0)) == 1, "expected fill-window pixel effect")
	_assert(int(byte_fill_layout.get("glyph_count", 0)) == 1, "expected one glyph after fill-window reset")
	_assert(String(byte_fill_first_glyph.get("text", "")) == "P", "expected post-fill glyph to remain")

	var byte_font_material_printer = BATTLE_TEXT_PRINTER_SCRIPT.new()
	byte_font_material_printer.start("B_WIN_MSG", "FFPFP", message_info, text_printer_metadata, {
		"source_text": "FFPFP",
		"source_bytes": [
			0xC0,
			0xFC, 0x06, 0x07,
			0xC0,
			0xFC, 0x07,
			0xCA,
			0xFC, 0x15,
			0xC0,
			0xFC, 0x16,
			0xFC, 0x05, 0x03,
			0xFC, 0x04, 0x04, 0x02, 0x06,
			0xFC, 0x02, 0x05,
			0xFC, 0x1C, 0x08, 0x09, 0x0A,
			0xCA,
			0xFF,
		],
		"source_glyphs": [
			{"byte_offset": 0, "bytes": [0xC0], "text": "F", "hex": "C0"},
			{"byte_offset": 4, "bytes": [0xC0], "text": "F", "hex": "C0"},
			{"byte_offset": 7, "bytes": [0xCA], "text": "P", "hex": "CA"},
			{"byte_offset": 10, "bytes": [0xC0], "text": "F", "hex": "C0"},
			{"byte_offset": 29, "bytes": [0xCA], "text": "P", "hex": "CA"},
		],
	})
	byte_font_material_printer.skip_to_end()
	var byte_font_material := _dict(byte_font_material_printer.snapshot())
	var byte_font_material_summary := _dict(byte_font_material.get("render_text_control_summary", {}))
	var byte_font_material_source_summary := _dict(byte_font_material.get("source_byte_control_summary", {}))
	var byte_font_material_layout := _dict(byte_font_material.get("source_glyph_layout", {}))
	var byte_font_material_glyphs := _array(byte_font_material_layout.get("glyphs", []))
	var normal_font_glyph := _glyph_by_source_offset(byte_font_material_glyphs, 0)
	var narrow_font_glyph := _glyph_by_source_offset(byte_font_material_glyphs, 4)
	var reset_noop_glyph := _glyph_by_source_offset(byte_font_material_glyphs, 7)
	var final_color_glyph := _glyph_by_source_offset(byte_font_material_glyphs, 29)
	var final_color_indices := _dict(final_color_glyph.get("render_text_color_indices", {}))
	_assert(int(byte_font_material_source_summary.get("ext_control_count", 0)) == 8, "expected eight font/material source byte EXT controls")
	_assert(int(byte_font_material_summary.get("font_count", 0)) == 1, "expected one font control")
	_assert(int(byte_font_material_summary.get("font_reset_noop_count", 0)) == 1, "expected one reset-font no-op control")
	_assert(int(byte_font_material_summary.get("japanese_mode_count", 0)) == 2, "expected JPN and ENG controls")
	_assert(int(byte_font_material_summary.get("material_bank_skip_count", 0)) == 1, "expected one palette/material-bank skip")
	_assert(int(byte_font_material_summary.get("render_text_color_count", 0)) == 3, "expected three color-family controls")
	_assert(String(normal_font_glyph.get("font_id", "")) == "FONT_NORMAL", "expected initial normal font glyph")
	_assert(String(narrow_font_glyph.get("font_id", "")) == "FONT_NARROW", "expected FONT control to select narrow font")
	_assert(String(reset_noop_glyph.get("font_id", "")) == "FONT_NARROW", "expected RESET_FONT source no-op to preserve font id")
	_assert(not bool(byte_font_material_layout.get("japanese_mode", true)), "expected ENG control to leave final Japanese mode false")
	_assert(int(final_color_indices.get("foreground", -1)) == 8, "expected TEXT_COLORS foreground")
	_assert(int(final_color_indices.get("shadow", -1)) == 9, "expected TEXT_COLORS shadow")
	_assert(int(final_color_indices.get("accent", -1)) == 10, "expected TEXT_COLORS accent")
	_assert(int(final_color_indices.get("background", -1)) == 5, "expected HIGHLIGHT background to persist through TEXT_COLORS")

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
	_assert(String(link_snapshot.get("battle_text_context_status", "")) == "source_battle_text_context_first_pass", "expected battle text context status")
	_assert(String(link_snapshot.get("auto_scroll_source", "")).contains("BATTLE_TYPE_LINK"), "expected link auto-scroll source")
	var link_context := _dict(link_snapshot.get("battle_text_context", {}))
	_assert(bool(link_context.get("battle_type_link", false)), "expected link context flag")

	var expected_recorded_delays := [8, 4, 1, 0]
	var recorded_delays := []
	for speed_index in range(expected_recorded_delays.size()):
		var recorded_printer = BATTLE_TEXT_PRINTER_SCRIPT.new()
		recorded_printer.start("B_WIN_MSG", "AB", message_info, text_printer_metadata, {
			"battle_text_mode": "recorded",
			"recorded_text_speed_index": speed_index,
			"player_text_speed": "OPTIONS_TEXT_SPEED_SLOW",
		})
		var recorded_snapshot := _dict(recorded_printer.snapshot())
		var recorded_context := _dict(recorded_snapshot.get("battle_text_context", {}))
		recorded_delays.append(int(recorded_snapshot.get("resolved_frame_delay", -1)))
		_assert(bool(recorded_snapshot.get("auto_scroll", false)), "expected recorded battle auto-scroll metadata")
		_assert(_array(recorded_snapshot.get("auto_scroll_reasons", [])).has("BATTLE_TYPE_RECORDED"), "expected recorded auto-scroll reason")
		_assert(bool(recorded_context.get("battle_type_recorded", false)), "expected recorded context flag")
		_assert(int(recorded_snapshot.get("recorded_text_speed_index", -1)) == speed_index, "expected recorded speed index metadata")
		_assert(int(recorded_snapshot.get("recorded_text_speed_value", -1)) == int(expected_recorded_delays[speed_index]), "expected recorded speed value metadata")
		_assert(String(recorded_snapshot.get("effective_speed_source", "")).contains("recorded_battle_speed[%d]" % speed_index), "expected recorded speed source metadata")
	_assert(recorded_delays == expected_recorded_delays, "expected recorded speed delay table")

	var recorded_link_printer = BATTLE_TEXT_PRINTER_SCRIPT.new()
	recorded_link_printer.start("B_WIN_MSG", "AB", message_info, text_printer_metadata, {
		"battle_text_mode": "recorded_link",
		"player_text_speed": "OPTIONS_TEXT_SPEED_SLOW",
	})
	var recorded_link_snapshot := _dict(recorded_link_printer.snapshot())
	var recorded_link_context := _dict(recorded_link_snapshot.get("battle_text_context", {}))
	_assert(int(recorded_link_snapshot.get("resolved_frame_delay", 0)) == 1, "expected recorded-link battle speed override")
	_assert(String(recorded_link_snapshot.get("effective_speed_source", "")).contains("recorded_link_battle_speed"), "expected recorded-link speed source")
	_assert(bool(recorded_link_snapshot.get("auto_scroll", false)), "expected recorded-link mode to carry recorded auto-scroll context")
	_assert(bool(recorded_link_context.get("battle_type_recorded_link", false)), "expected recorded-link context flag")
	_assert(bool(recorded_link_context.get("battle_type_recorded", false)), "expected recorded-link mode to include recorded flag context")

	var recorded_link_flag_printer = BATTLE_TEXT_PRINTER_SCRIPT.new()
	recorded_link_flag_printer.start("B_WIN_MSG", "AB", message_info, text_printer_metadata, {
		"battle_type_recorded_link": true,
	})
	var recorded_link_flag_snapshot := _dict(recorded_link_flag_printer.snapshot())
	_assert(int(recorded_link_flag_snapshot.get("resolved_frame_delay", 0)) == 1, "expected recorded-link flag speed override")
	_assert(not bool(recorded_link_flag_snapshot.get("auto_scroll", true)), "expected recorded-link flag alone not to set source auto-scroll")
	_assert(String(recorded_link_flag_snapshot.get("auto_scroll_source", "")).contains("FALSE"), "expected recorded-link flag-only auto-scroll false source")

	var test_runner_page_printer = BATTLE_TEXT_PRINTER_SCRIPT.new()
	test_runner_page_printer.start("B_WIN_MSG", "A\n\nB", message_info, text_printer_metadata, {
		"test_runner_enabled": true,
	})
	test_runner_page_printer.advance_frames(1)
	test_runner_page_printer.advance_frames(1)
	var test_runner_wait := _dict(test_runner_page_printer.snapshot())
	_assert(bool(test_runner_wait.get("auto_scroll", false)), "expected test runner auto-scroll metadata")
	_assert(_array(test_runner_wait.get("auto_scroll_reasons", [])).has("gTestRunnerEnabled"), "expected test runner auto-scroll reason")
	_assert(String(test_runner_wait.get("wait_state", "")) == "wait_with_down_arrow", "expected test runner prompt-scroll wait")
	_assert(not bool(test_runner_wait.get("down_arrow_visible", true)), "expected auto-scroll to suppress down arrow")
	test_runner_page_printer.advance_frames(49)
	var test_runner_before_release := _dict(test_runner_page_printer.snapshot())
	_assert(int(test_runner_before_release.get("auto_scroll_delay", -1)) == 49, "expected source auto-scroll delay before release")
	_assert(String(test_runner_before_release.get("wait_state", "")) == "wait_with_down_arrow", "expected auto-scroll wait before release frame")
	test_runner_page_printer.advance_frames(1)
	var test_runner_released := _dict(test_runner_page_printer.snapshot())
	_assert(String(test_runner_released.get("wait_state", "unexpected")) == "", "expected auto-scroll release after 50 wait frames")
	_assert(int(test_runner_released.get("auto_scroll_delay", -1)) == 0, "expected auto-scroll delay reset")
	test_runner_page_printer.advance_frames(1)
	_assert(String(test_runner_page_printer.get_visible_text()) == "A\n\nB", "expected auto-scroll release to resume text")

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
		"render_text_color_controls": int(byte_color.get("render_text_color_control_count", 0)),
		"source_glyph_width": int(byte_glyph_layout_first.get("width", 0)),
		"ab_speedups": int(speedup_pressed.get("ab_speedup_count", 0)),
		"recorded_speed_cases": recorded_delays.size(),
		"recorded_delays": recorded_delays,
		"recorded_link_delay": int(recorded_link_snapshot.get("resolved_frame_delay", 0)),
		"auto_scroll_release_frames": 50,
		"render_text_control_ext_controls": int(byte_layout_source_summary.get("ext_control_count", 0)),
		"render_text_control_clear_spans": int(byte_layout_pixel_summary.get("clear_text_span_count", 0)),
		"render_text_control_filled_spans": int(byte_layout_pixel_summary.get("clear_text_span_filled_count", 0)),
		"render_text_control_fill_windows": int(byte_fill_pixel_summary.get("fill_window_count", 0)),
		"render_text_control_min_spacing": int(byte_layout_summary.get("min_letter_spacing_count", 0)),
		"render_text_font_material_ext_controls": int(byte_font_material_source_summary.get("ext_control_count", 0)),
		"render_text_font_controls": int(byte_font_material_summary.get("font_count", 0)),
		"render_text_font_reset_noops": int(byte_font_material_summary.get("font_reset_noop_count", 0)),
		"render_text_material_bank_skips": int(byte_font_material_summary.get("material_bank_skip_count", 0)),
		"render_text_color_family_controls": int(byte_font_material_summary.get("render_text_color_count", 0)),
		"render_text_jpn_eng_controls": int(byte_font_material_summary.get("japanese_mode_count", 0)),
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


func _glyph_by_source_offset(glyphs: Array, source_offset: int) -> Dictionary:
	for glyph_value in glyphs:
		var glyph := _dict(glyph_value)
		if int(glyph.get("source_offset", -1)) == source_offset:
			return glyph
	return {}
