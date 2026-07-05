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

	renderer.show_action_windows("Mudkip wants?", "Fight\tBag\nPokemon\tRun")
	var action_snapshot := _dict(renderer.get_renderer_snapshot())
	_assert(String(action_snapshot.get("status", "")) == "first_pass", "expected first-pass renderer status")
	_assert(String(action_snapshot.get("source_composite_mapping_status", "")) == "generated_window_template_rects", "expected generated composite rect mapping")
	_assert(String(action_snapshot.get("source_text_info_status", "")) == "generated_from_sTextOnWindowsInfo_Normal", "expected generated text info mapping")
	var text_printer := _dict(action_snapshot.get("text_printer", {}))
	_assert(String(text_printer.get("status", "")) == "first_pass_source_glyph_layout", "expected first-pass text printer runtime snapshot")
	_assert(String(text_printer.get("metadata_status", "")) == "metadata_only", "expected generated text printer metadata status")
	_assert(int(text_printer.get("normal_window_text_info_count", 0)) == 25, "expected text printer normal window info count")
	_assert(String(text_printer.get("source_font_metric_status", "")) == "generated_from_text_c_font_tables", "expected generated source font metrics")
	_assert(int(text_printer.get("source_font_metric_count", 0)) == 14, "expected generated source font metric count")
	_assert(String(text_printer.get("source_font_atlas_status", "")) == "source_font_atlas_preview", "expected source font atlas preview")
	_assert(int(text_printer.get("source_font_atlas_binding_count", 0)) == 12, "expected source font atlas binding count")
	_assert(int(text_printer.get("source_font_role_mask_binding_count", 0)) == 12, "expected source font role mask binding count")
	_assert(String(text_printer.get("render_text_material_status", "")) == "generated_from_textbox_indexed_colors", "expected RenderText material metadata")
	_assert(int(text_printer.get("visible_window_printer_count", 0)) == 2, "expected two visible action text printers")
	_assert(not _contains_forbidden_runtime_color_key(action_snapshot), "renderer snapshot must not expose runtime color/palette keys")
	_assert(_array(action_snapshot.get("visible_windows", [])).has("B_WIN_ACTION_PROMPT"), "expected action prompt visible")
	_assert(_array(action_snapshot.get("visible_windows", [])).has("B_WIN_ACTION_MENU"), "expected action menu visible")
	var action_windows := _dict(action_snapshot.get("windows", {}))
	var action_menu := _dict(action_windows.get("B_WIN_ACTION_MENU", {}))
	_assert(_array(action_menu.get("screen_rect", [])) == [136, 120, 96, 32], "expected action menu screen rect")
	_assert(_array(action_menu.get("tilemap_rect", [])) == [136, 216, 96, 32], "expected action menu source tilemap rect")
	_assert(String(action_menu.get("tilemap_composite_rect_status", "")) == "first_pass_generated_textbox_map_preview_rows", "expected action menu generated composite rect status")
	_assert(String(action_menu.get("text_info_status", "")) == "generated_from_sTextOnWindowsInfo_Normal", "expected action menu generated text status")
	_assert(String(action_menu.get("style_id", "")) == "battle_menu_text", "expected generated action menu style id")
	_assert(String(action_menu.get("panel_style", "")) == "menu_panel", "expected semantic action menu panel style")
	_assert(int(action_menu.get("source_speed", -1)) == 0, "expected action menu instant source speed")
	_assert(String(action_menu.get("visible_text", "")) == "Fight    Bag\nPokemon    Run", "expected action menu text revealed immediately")
	var action_menu_printer := _dict(action_menu.get("text_printer", {}))
	_assert(bool(action_menu_printer.get("synchronous_render", false)), "expected speed-zero action menu printer to render synchronously")
	var action_menu_bitmap := _dict(action_menu.get("source_text_bitmap", {}))
	_assert(String(action_menu_bitmap.get("status", "")) == "render_text_role_colored_preview", "expected action menu role-colored source font bitmap")
	_assert(int(action_menu_bitmap.get("rendered_glyph_count", 0)) >= 20, "expected action menu source font glyph pixels")
	_assert(int(action_menu_bitmap.get("role_colored_glyph_count", 0)) >= 20, "expected action menu role-colored glyph count")
	_assert(int(action_menu_bitmap.get("colored_pixel_count", 0)) > 500, "expected action menu role-colored source pixels")
	var action_image: Image = renderer.compose_current_window_layer_image()
	_assert(action_image.get_width() == 240 and action_image.get_height() == 160, "expected 240x160 action layer image")
	_assert(action_image.get_pixel(0, 0).a <= 0.01, "expected transparent pixels outside source windows")
	var action_opaque := _rect_opaque_count(action_image, Rect2i(136, 120, 96, 32))
	var action_text_opaque := _rect_opaque_count(action_image, Rect2i(136, 121, 76, 30))
	_assert(action_opaque > 100, "expected opaque action menu source pixels")
	_assert(action_text_opaque > 500, "expected action menu source font atlas pixels")

	renderer.show_message_window("ABC", false)
	var reveal_start := _dict(renderer.get_renderer_snapshot())
	var reveal_windows := _dict(reveal_start.get("windows", {}))
	var reveal_message := _dict(reveal_windows.get("B_WIN_MSG", {}))
	var reveal_printer := _dict(reveal_message.get("text_printer", {}))
	_assert(String(reveal_message.get("visible_text", "")) == "", "expected hidden message before first text-printer frame")
	_assert(String(reveal_printer.get("effective_speed_source", "")).contains("OPTIONS_TEXT_SPEED_FAST"), "expected default fast player text source")
	_assert(int(reveal_printer.get("resolved_frame_delay", 0)) == 1, "expected default fast message frame delay")
	renderer.advance_text_printers(1)
	_assert(String(renderer.get_window_visible_text("B_WIN_MSG")) == "A", "expected first message glyph after one frame")
	renderer.skip_text_printers_to_end()
	_assert(String(renderer.get_window_visible_text("B_WIN_MSG")) == "ABC", "expected message skip to reveal all")

	renderer.show_message_window("A\n\nB", false)
	renderer.advance_text_printers(1)
	renderer.advance_text_printers(1)
	var page_snapshot := _dict(renderer.get_renderer_snapshot())
	var page_windows := _dict(page_snapshot.get("windows", {}))
	var page_message := _dict(page_windows.get("B_WIN_MSG", {}))
	var page_printer := _dict(page_message.get("text_printer", {}))
	_assert(String(page_message.get("visible_text", "")) == "A\n\n", "expected renderer message page break before B")
	_assert(String(page_printer.get("wait_state", "")) == "wait_with_down_arrow", "expected renderer page wait state")
	_assert(bool(page_printer.get("down_arrow_visible", false)), "expected renderer down-arrow metadata")
	renderer.advance_text_printers(1, {"a_pressed": true})
	renderer.advance_text_printers(1)
	_assert(String(renderer.get_window_visible_text("B_WIN_MSG")) == "A\n\nB", "expected renderer page wait release")

	renderer.show_message_record({
		"label": "fixture_source_record",
		"display_text": "A\n\nB",
		"source_text": "A\\pB",
		"encoding": {
			"bytes": [0x41, 0xFB, 0x42],
			"hex": "41 FB 42",
		},
		"text_controls": [{"command": "PROMPT_SCROLL"}],
	}, false)
	renderer.advance_text_printers(1)
	renderer.advance_text_printers(1)
	var source_record_snapshot := _dict(renderer.get_renderer_snapshot())
	var source_record_windows := _dict(source_record_snapshot.get("windows", {}))
	var source_record_message := _dict(source_record_windows.get("B_WIN_MSG", {}))
	var source_record_printer := _dict(source_record_message.get("text_printer", {}))
	var source_record_byte_summary := _dict(source_record_printer.get("source_byte_control_summary", {}))
	_assert(String(source_record_printer.get("event_stream_source", "")) == "source_bytes", "expected renderer record source-byte event stream")
	_assert(String(source_record_printer.get("source_text_label", "")) == "fixture_source_record", "expected renderer record source-text label")
	_assert(int(source_record_printer.get("source_text_control_metadata_count", 0)) == 1, "expected renderer record text-control metadata count")
	_assert(String(source_record_message.get("visible_text", "")) == "A", "expected renderer source record prompt clear before B")
	_assert(String(source_record_printer.get("wait_state", "")) == "wait_clear", "expected renderer source record prompt-clear wait")
	_assert(int(source_record_printer.get("prompt_clear_count", 0)) == 1, "expected renderer source record prompt-clear count")
	_assert(int(source_record_printer.get("source_byte_event_count", 0)) == 3, "expected renderer record source byte event count")
	_assert(int(source_record_byte_summary.get("prompt_clear_count", 0)) == 1, "expected renderer source record byte prompt-clear summary")

	renderer.show_move_windows(["Water Gun", "Tackle", "-", "-"], "PP", "25/25", "TYPE/Water")
	var move_snapshot := _dict(renderer.get_renderer_snapshot())
	_assert(String(move_snapshot.get("source_composite_mapping_status", "")) == "generated_window_template_rects", "expected generated move composite rect mapping")
	_assert(String(move_snapshot.get("source_text_info_status", "")) == "generated_from_sTextOnWindowsInfo_Normal", "expected generated move text info mapping")
	_assert(not _contains_forbidden_runtime_color_key(move_snapshot), "move renderer snapshot must not expose runtime color/palette keys")
	_assert(_array(move_snapshot.get("visible_windows", [])).size() == 7, "expected seven move-select windows")
	var move_windows := _dict(move_snapshot.get("windows", {}))
	var move_name_1 := _dict(move_windows.get("B_WIN_MOVE_NAME_1", {}))
	var move_type := _dict(move_windows.get("B_WIN_MOVE_TYPE", {}))
	var move_bitmap := _dict(move_name_1.get("source_text_bitmap", {}))
	_assert(_array(move_name_1.get("screen_rect", [])) == [16, 120, 128, 16], "expected first move screen rect")
	_assert(_array(move_name_1.get("tilemap_rect", [])) == [16, 56, 128, 16], "expected first move source tilemap rect")
	_assert(String(move_name_1.get("tilemap_composite_rect_status", "")) == "first_pass_generated_textbox_map_preview_rows", "expected first move generated composite rect status")
	_assert(int(move_name_1.get("source_fit_width_px", 0)) == 64, "expected first move generated fit width")
	_assert(_array(move_type.get("screen_rect", [])) == [168, 136, 64, 16], "expected move type screen rect")
	_assert(String(move_type.get("text", "")) == "TYPE/Water", "expected move type renderer text")
	_assert(String(move_bitmap.get("status", "")) == "render_text_role_colored_preview", "expected move name role-colored source font bitmap")
	_assert(int(move_bitmap.get("role_colored_glyph_count", 0)) >= 8, "expected move-name role-colored glyph count")
	var move_image: Image = renderer.compose_current_window_layer_image()
	var move_opaque := _rect_opaque_count(move_image, Rect2i(16, 120, 128, 16))
	var type_opaque := _rect_opaque_count(move_image, Rect2i(168, 136, 64, 16))
	_assert(move_opaque > 80, "expected opaque move-name source pixels")
	_assert(type_opaque > 40, "expected opaque move-type source pixels")

	if _failed:
		return
	print(JSON.stringify({
		"battle_window_renderer_smoke": "ok",
		"action_windows": _array(action_snapshot.get("visible_windows", [])).size(),
		"move_windows": _array(move_snapshot.get("visible_windows", [])).size(),
		"action_menu_opaque_pixels": action_opaque,
		"action_menu_text_pixels": action_text_opaque,
		"move_name_opaque_pixels": move_opaque,
		"move_type_opaque_pixels": type_opaque,
		"message_page_waits": int(page_printer.get("page_wait_count", 0)),
		"source_record_page_waits": int(source_record_printer.get("page_wait_count", 0)),
	}))
	renderer.queue_free()
	registry.free()
	quit(0)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true
	quit(1)


func _array(value) -> Array:
	return value if typeof(value) == TYPE_ARRAY else []


func _dict(value) -> Dictionary:
	return value if typeof(value) == TYPE_DICTIONARY else {}


func _rect_opaque_count(image: Image, rect: Rect2i) -> int:
	var count := 0
	for y in range(rect.position.y, rect.position.y + rect.size.y):
		for x in range(rect.position.x, rect.position.x + rect.size.x):
			if x < 0 or y < 0 or x >= image.get_width() or y >= image.get_height():
				continue
			if image.get_pixel(x, y).a > 0.01:
				count += 1
	return count


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
