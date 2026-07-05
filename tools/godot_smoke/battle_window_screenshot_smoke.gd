extends SceneTree

const DATA_REGISTRY_SCRIPT := preload("res://scripts/autoload/data_registry.gd")
const BATTLE_WINDOW_RENDERER_SCRIPT := preload("res://scripts/battle/battle_window_renderer.gd")

var _failed := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var registry = DATA_REGISTRY_SCRIPT.new()
	registry._ready()

	var renderer = BATTLE_WINDOW_RENDERER_SCRIPT.new()
	renderer.configure_data_registry(registry)
	get_root().add_child(renderer)
	await create_timer(0.05).timeout

	var prompt_mon_name := "Mudkip"
	var prompt_text := _source_battle_text(registry, "gText_WhatWillPkmnDo").replace("{B_BUFF1}", prompt_mon_name)
	var menu_text := _replace_text_control_with_tab(_source_battle_text(registry, "gText_BattleMenu"))
	renderer.show_action_windows(
		prompt_text,
		menu_text,
		_source_battle_text_printer_options(registry, "gText_WhatWillPkmnDo", {"{B_BUFF1}": prompt_mon_name}),
		_source_battle_text_printer_options(registry, "gText_BattleMenu")
	)
	var action_image: Image = renderer.compose_current_window_layer_image()
	var action_snapshot := _dict(renderer.get_renderer_snapshot())
	var action_windows := _dict(action_snapshot.get("windows", {}))
	var action_menu := _dict(action_windows.get("B_WIN_ACTION_MENU", {}))
	var action_menu_bitmap := _dict(action_menu.get("source_text_bitmap", {}))
	var action_menu_printer := _dict(action_menu.get("text_printer", {}))
	var action_menu_effects := _dict(action_menu_printer.get("source_window_pixel_effect_summary", {}))
	_assert(_is_viewport_image(action_image), "expected action 240x160 screenshot layer")
	_assert(_array(action_snapshot.get("visible_windows", [])).has("B_WIN_ACTION_PROMPT"), "expected source action prompt window")
	_assert(_array(action_snapshot.get("visible_windows", [])).has("B_WIN_ACTION_MENU"), "expected source action menu window")
	_assert(String(action_menu_bitmap.get("status", "")) == "render_text_role_colored_preview", "expected source role-colored action menu bitmap")
	_assert(int(action_menu_bitmap.get("colored_pixel_count", 0)) > 1500, "expected action menu source text pixels")
	_assert(int(action_menu_effects.get("clear_text_span_count", 0)) == 2, "expected two source CLEAR_TO spans in battle menu")
	_assert(not _contains_forbidden_runtime_color_key(action_snapshot), "action snapshot must not expose runtime palette/source-color keys")
	var action_menu_rect := Rect2i(136, 120, 96, 32)
	var action_menu_opaque := _rect_opaque_count(action_image, action_menu_rect)
	var action_menu_text := _rect_opaque_count(action_image, Rect2i(136, 121, 76, 30))
	var action_signature := _image_signature(action_image)
	_assert(action_menu_opaque == 2670, "expected opaque action menu screenshot pixels")
	_assert(action_menu_text == 2122, "expected action menu text screenshot pixels")
	_assert(action_signature == "E1635039", "expected action screenshot signature")
	_assert(_rect_opaque_count(action_image, Rect2i(0, 0, 16, 16)) == 0, "expected transparent outside action windows")

	renderer.show_message_record(_latin_record("fixture_message_screenshot", "ABC", [0xBB, 0xBC, 0xBD]), true)
	var message_image: Image = renderer.compose_current_window_layer_image()
	var message_snapshot := _dict(renderer.get_renderer_snapshot())
	var message_windows := _dict(message_snapshot.get("windows", {}))
	var message_window := _dict(message_windows.get("B_WIN_MSG", {}))
	var message_bitmap := _dict(message_window.get("source_text_bitmap", {}))
	_assert(_is_viewport_image(message_image), "expected message 240x160 screenshot layer")
	_assert(_array(message_snapshot.get("visible_windows", [])).has("B_WIN_MSG"), "expected message window visible")
	_assert(String(message_bitmap.get("status", "")) == "render_text_role_colored_preview", "expected role-colored message bitmap")
	_assert(int(message_bitmap.get("rendered_glyph_count", 0)) == 3, "expected three message source glyphs")
	var message_opaque := _rect_opaque_count(message_image, Rect2i(0, 120, 240, 40))
	var message_text := _rect_opaque_count(message_image, Rect2i(8, 121, 64, 24))
	var message_signature := _image_signature(message_image)
	_assert(message_opaque == 3478, "expected opaque message window screenshot pixels")
	_assert(message_text == 774, "expected source text pixels in message window")
	_assert(message_signature == "D256DE44", "expected message screenshot signature")
	_assert(not _contains_forbidden_runtime_color_key(message_snapshot), "message snapshot must not expose runtime palette/source-color keys")

	renderer.show_message_record(_latin_record("fixture_prompt_clear_screenshot", "AB", [0xBB, 0xFB, 0xBC]), false)
	renderer.advance_text_printers(1)
	renderer.advance_text_printers(1)
	var clear_wait := _message_printer_snapshot(renderer)
	_assert(String(clear_wait.get("wait_state", "")) == "wait_clear", "expected source-byte prompt clear wait")
	_assert(String(clear_wait.get("visible_text", "")) == "A", "expected A visible before prompt clear")
	renderer.advance_text_printers(1, {"a_pressed": true})
	var clear_after := _message_printer_snapshot(renderer)
	var clear_summary := _dict(clear_after.get("source_window_pixel_effect_summary", {}))
	_assert(String(clear_after.get("visible_text", "")) == "", "expected prompt clear to clear visible text")
	_assert(int(clear_summary.get("fill_window_count", 0)) == 1, "expected prompt clear FillWindowPixelBuffer effect")
	_assert(int(clear_summary.get("effect_count", 0)) == 1, "expected one source prompt-clear pixel effect")

	renderer.show_message_record(_latin_record("fixture_prompt_scroll_screenshot", "A\nB", [0xBB, 0xFA, 0xBC]), false)
	renderer.advance_text_printers(1)
	renderer.advance_text_printers(1)
	var scroll_wait := _message_printer_snapshot(renderer)
	_assert(String(scroll_wait.get("wait_state", "")) == "wait_with_down_arrow", "expected source-byte prompt scroll wait")
	renderer.advance_text_printers(1, {"a_pressed": true})
	var scroll_started := _message_printer_snapshot(renderer)
	_assert(String(scroll_started.get("wait_state", "")) == "scroll", "expected source prompt scroll state after input")
	for _index in range(4):
		renderer.advance_text_printers(1)
	var scroll_after := _message_printer_snapshot(renderer)
	var scroll_summary := _dict(scroll_after.get("source_window_pixel_effect_summary", {}))
	_assert(int(scroll_summary.get("scroll_start_count", 0)) == 1, "expected one source scroll start effect")
	_assert(int(scroll_summary.get("scroll_step_count", 0)) >= 4, "expected source scroll step effects")
	_assert(int(scroll_summary.get("scroll_complete_count", 0)) == 1, "expected source scroll complete effect")
	_assert(int(scroll_summary.get("scroll_total_px", 0)) == int(scroll_summary.get("scroll_distance_px_total", 0)), "expected source scroll pixels to match total distance")

	var water_type := _type_display_name(registry, "TYPE_WATER")
	var type_prefix := _source_battle_text(registry, "gText_MoveInterfaceType")
	renderer.show_move_windows(
		["Water Gun", "Tackle", "-", "-"],
		_source_battle_text(registry, "gText_MoveInterfacePP"),
		"25/25",
		"%s%s" % [type_prefix, water_type],
		{
			"B_WIN_PP": _source_battle_text_printer_options(registry, "gText_MoveInterfacePP"),
			"B_WIN_MOVE_TYPE": _source_battle_text_printer_options(registry, "gText_MoveInterfaceType", {}, water_type),
		}
	)
	var move_image: Image = renderer.compose_current_window_layer_image()
	var move_snapshot := _dict(renderer.get_renderer_snapshot())
	var move_windows := _dict(move_snapshot.get("windows", {}))
	var move_name := _dict(move_windows.get("B_WIN_MOVE_NAME_1", {}))
	var move_type := _dict(move_windows.get("B_WIN_MOVE_TYPE", {}))
	var move_pp := _dict(move_windows.get("B_WIN_PP", {}))
	var move_name_bitmap := _dict(move_name.get("source_text_bitmap", {}))
	var move_type_bitmap := _dict(move_type.get("source_text_bitmap", {}))
	var move_pp_printer := _dict(move_pp.get("text_printer", {}))
	_assert(_is_viewport_image(move_image), "expected move 240x160 screenshot layer")
	_assert(_array(move_snapshot.get("visible_windows", [])).size() == 7, "expected seven source move windows")
	_assert(String(move_name_bitmap.get("status", "")) == "render_text_role_colored_preview", "expected role-colored move-name bitmap")
	_assert(String(move_type_bitmap.get("status", "")) == "render_text_role_colored_preview", "expected role-colored move-type bitmap")
	_assert(String(move_pp_printer.get("event_stream_source", "")) == "source_bytes", "expected PP label to use generated source bytes")
	var move_name_opaque := _rect_opaque_count(move_image, Rect2i(16, 120, 128, 16))
	var move_type_opaque := _rect_opaque_count(move_image, Rect2i(168, 136, 64, 16))
	var move_signature := _image_signature(move_image)
	_assert(move_name_opaque == 2048, "expected opaque first move screenshot pixels")
	_assert(move_type_opaque == 560, "expected opaque move type screenshot pixels")
	_assert(move_signature == "43C20F69", "expected move screenshot signature")
	_assert(not _contains_forbidden_runtime_color_key(move_snapshot), "move snapshot must not expose runtime palette/source-color keys")

	if _failed:
		return
	print(JSON.stringify({
		"battle_window_screenshot_smoke": "ok",
		"action_signature": action_signature,
		"message_signature": message_signature,
		"move_signature": move_signature,
		"action_menu_opaque_pixels": action_menu_opaque,
		"action_menu_text_pixels": action_menu_text,
		"message_opaque_pixels": message_opaque,
		"message_text_pixels": message_text,
		"move_name_opaque_pixels": move_name_opaque,
		"move_type_opaque_pixels": move_type_opaque,
		"action_clear_to_spans": int(action_menu_effects.get("clear_text_span_count", 0)),
		"prompt_clear_effects": int(clear_summary.get("effect_count", 0)),
		"prompt_scroll_steps": int(scroll_summary.get("scroll_step_count", 0)),
		"prompt_scroll_pixels": int(scroll_summary.get("scroll_total_px", 0)),
	}))
	renderer.queue_free()
	registry.free()
	quit(0)


func _source_battle_text(registry: Node, label: String) -> String:
	var record := _source_battle_text_record(registry, label)
	var text := String(record.get("display_text", ""))
	if text.is_empty():
		text = String(record.get("source_text", ""))
	return text


func _source_battle_text_record(registry: Node, label: String) -> Dictionary:
	if registry != null and registry.has_method("get_battle_text_record"):
		var record = registry.get_battle_text_record(label)
		if typeof(record) == TYPE_DICTIONARY and not record.is_empty():
			return record
	if registry != null and registry.has_method("get_battle_string_record"):
		var string_record = registry.get_battle_string_record(label)
		if typeof(string_record) == TYPE_DICTIONARY and not string_record.is_empty():
			return string_record
	return {}


func _source_battle_text_printer_options(registry: Node, label: String, replacements: Dictionary = {}, source_text_suffix: String = "") -> Dictionary:
	var record := _source_battle_text_record(registry, label)
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
		var encoding := _dict(record.get("encoding", {}))
		if not encoding.is_empty():
			options["source_encoding"] = encoding
			options["source_bytes"] = encoding.get("bytes", [])
			options["source_glyphs"] = encoding.get("glyphs", [])
			options["source_encoding_hex"] = String(encoding.get("hex", ""))
	return options


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


func _type_display_name(registry: Node, type_symbol: String) -> String:
	if registry == null or not registry.has_method("get_type_record"):
		return type_symbol
	var record = registry.get_type_record(type_symbol)
	if typeof(record) != TYPE_DICTIONARY or record.is_empty():
		return type_symbol
	var name := _dict(record.get("name", {}))
	var text := String(name.get("display_text", ""))
	return text if not text.is_empty() else type_symbol


func _latin_record(label: String, display_text: String, bytes: Array) -> Dictionary:
	var glyphs := []
	var source_offset := 0
	var byte_offset := 0
	for byte_value in bytes:
		var byte := int(byte_value) & 0xFF
		if byte == 0xFA or byte == 0xFB:
			byte_offset += 1
			source_offset += 2
			continue
		glyphs.append({
			"text": _latin_text_for_byte(byte),
			"source_offset": source_offset,
			"byte_offset": byte_offset,
			"byte_count": 1,
			"bytes": [byte],
			"hex": "%02X" % byte,
		})
		byte_offset += 1
		source_offset += 1
	var encoded_bytes := bytes.duplicate(true)
	encoded_bytes.append(0xFF)
	return {
		"label": label,
		"display_text": display_text,
		"source_text": _source_text_for_latin_record(display_text),
		"encoding": {
			"bytes": encoded_bytes,
			"hex": _hex_string(encoded_bytes),
			"glyphs": glyphs,
		},
		"text_controls": [],
		"audio_cues": [],
		"metadata_only": [],
	}


func _source_text_for_latin_record(display_text: String) -> String:
	var result := display_text.replace("\n\n", "\\p").replace("\n", "\\l")
	return "%s$" % result


func _latin_text_for_byte(byte: int) -> String:
	if byte >= 0xBB and byte <= 0xD4:
		return String.chr("A".unicode_at(0) + byte - 0xBB)
	return "[%02X]" % byte


func _hex_string(bytes: Array) -> String:
	var parts := []
	for byte_value in bytes:
		parts.append("%02X" % (int(byte_value) & 0xFF))
	return " ".join(parts)


func _message_printer_snapshot(renderer: Control) -> Dictionary:
	var snapshot := _dict(renderer.get_renderer_snapshot())
	var windows := _dict(snapshot.get("windows", {}))
	var message := _dict(windows.get("B_WIN_MSG", {}))
	return _dict(message.get("text_printer", {}))


func _is_viewport_image(image: Image) -> bool:
	return image.get_width() == 240 and image.get_height() == 160


func _rect_opaque_count(image: Image, rect: Rect2i) -> int:
	var count := 0
	for y in range(rect.position.y, rect.position.y + rect.size.y):
		for x in range(rect.position.x, rect.position.x + rect.size.x):
			if x < 0 or y < 0 or x >= image.get_width() or y >= image.get_height():
				continue
			if image.get_pixel(x, y).a > 0.01:
				count += 1
	return count


func _image_signature(image: Image) -> String:
	var hash: int = 2166136261
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var color := image.get_pixel(x, y)
			hash = _fnv1a(hash, int(round(color.r * 255.0)))
			hash = _fnv1a(hash, int(round(color.g * 255.0)))
			hash = _fnv1a(hash, int(round(color.b * 255.0)))
			hash = _fnv1a(hash, int(round(color.a * 255.0)))
	return "%08X" % (hash & 0xFFFFFFFF)


func _fnv1a(hash: int, value: int) -> int:
	return int(((hash ^ (value & 0xFF)) * 16777619) & 0xFFFFFFFF)


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
