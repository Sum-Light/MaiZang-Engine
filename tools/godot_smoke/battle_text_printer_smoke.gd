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

	if _failed:
		return
	print(JSON.stringify({
		"battle_text_printer_smoke": "ok",
		"slow_delay": int(initial.get("resolved_frame_delay", 0)),
		"instant_modifier": int(instant_snapshot.get("player_text_speed_modifier", 0)),
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
