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
	_assert(String(initial.get("status", "")) == "first_pass_plain_text_cadence", "expected first-pass printer status")
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
