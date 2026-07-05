extends Control

const TILE_SIZE := 8
const VIEWPORT_SIZE := Vector2i(240, 160)
const BG0_Y_ACTION_CHOOSE := 160
const BG0_Y_MOVE_CHOOSE := 320
const BATTLE_TEXT_PRINTER_SCRIPT := preload("res://scripts/battle/battle_text_printer.gd")

const SOURCE_TRACE := [
	"src/battle_bg.c:LoadBattleTextboxAndBackground",
	"src/battle_bg.c:sStandardBattleWindowTemplates",
	"src/battle_message.c:sTextOnWindowsInfo_Normal",
	"src/battle_message.c:BattlePutTextOnWindow",
	"src/text.c:sFontInfos",
	"src/fonts.c:gFont*LatinGlyphWidths",
	"src/chinese_text.c:GetChineseFontWidthFunc",
]

var _data_registry: Node = null
var _interface_data: Dictionary = {}
var _window_templates: Dictionary = {}
var _text_printer: Dictionary = {}
var _texture_nodes: Dictionary = {}
var _text_texture_nodes: Dictionary = {}
var _label_nodes: Dictionary = {}
var _window_texts: Dictionary = {}
var _active_text_printers: Dictionary = {}
var _window_text_printer_option_signatures: Dictionary = {}
var _source_text_bitmap_summaries: Dictionary = {}
var _visible_windows: Array = []
var _bg0_y := 0
var _textbox_composite_path := ""
var _textbox_composite_texture: Texture2D = null
var _textbox_composite_image: Image = null
var _source_font_atlas_images: Dictionary = {}
var _font_role_mask_images: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(VIEWPORT_SIZE)
	size = Vector2(VIEWPORT_SIZE)


func configure_data_registry(data_registry: Node) -> void:
	_data_registry = data_registry
	_load_interface_data()


func show_message_window(text: String, reveal_immediately: bool = true, text_printer_options: Dictionary = {}) -> void:
	show_windows(["B_WIN_MSG"], 0, {"B_WIN_MSG": text}, reveal_immediately, text_printer_options)


func show_message_record(record: Dictionary, reveal_immediately: bool = true, text_printer_options: Dictionary = {}) -> void:
	var options := _text_printer_options_from_record(record, text_printer_options)
	show_message_window(_display_text_from_record(record), reveal_immediately, options)


func show_action_windows(prompt_text: String, menu_text: String, prompt_text_printer_options: Dictionary = {}, menu_text_printer_options: Dictionary = {}) -> void:
	show_windows(
		["B_WIN_ACTION_PROMPT", "B_WIN_ACTION_MENU"],
		BG0_Y_ACTION_CHOOSE,
		{
			"B_WIN_ACTION_PROMPT": prompt_text,
			"B_WIN_ACTION_MENU": menu_text,
		},
		true,
		{
			"windows": {
				"B_WIN_ACTION_PROMPT": prompt_text_printer_options,
				"B_WIN_ACTION_MENU": menu_text_printer_options,
			},
		}
	)


func show_move_windows(move_names: Array, pp_label: String, pp_remaining: String, move_type: String, text_printer_options_by_window: Dictionary = {}) -> void:
	var text_by_window := {
		"B_WIN_PP": pp_label,
		"B_WIN_PP_REMAINING": pp_remaining,
		"B_WIN_MOVE_TYPE": move_type,
	}
	for index in range(4):
		text_by_window["B_WIN_MOVE_NAME_%d" % [index + 1]] = String(move_names[index]) if index < move_names.size() else "-"
	show_windows(
		[
			"B_WIN_MOVE_NAME_1",
			"B_WIN_MOVE_NAME_2",
			"B_WIN_MOVE_NAME_3",
			"B_WIN_MOVE_NAME_4",
			"B_WIN_PP",
			"B_WIN_PP_REMAINING",
			"B_WIN_MOVE_TYPE",
		],
		BG0_Y_MOVE_CHOOSE,
		text_by_window,
		true,
		{"windows": text_printer_options_by_window}
	)


func clear_windows() -> void:
	_visible_windows = []
	for node in _texture_nodes.values():
		if node is CanvasItem:
			node.visible = false
	for node in _text_texture_nodes.values():
		if node is CanvasItem:
			node.visible = false
	for node in _label_nodes.values():
		if node is CanvasItem:
			node.visible = false


func show_windows(window_ids: Array, bg0_y: int, text_by_window: Dictionary = {}, reveal_immediately: bool = true, text_printer_options: Dictionary = {}) -> void:
	_load_interface_data()
	_bg0_y = bg0_y
	_visible_windows = []
	for window_id_value in window_ids:
		var window_id := String(window_id_value)
		var template := _window_template(window_id)
		if template.is_empty():
			continue
		_visible_windows.append(window_id)
		_window_texts[window_id] = String(text_by_window.get(window_id, _window_texts.get(window_id, "")))
		_ensure_window_nodes(window_id)
		_ensure_text_printer(window_id, String(_window_texts.get(window_id, "")), reveal_immediately, _text_printer_options_for_window(window_id, text_printer_options))
		_apply_window_node_layout(window_id)
	_set_node_visibility()


func set_window_text(window_id: String, text: String) -> void:
	_window_texts[window_id] = text
	_ensure_text_printer(window_id, text, true)
	_update_window_text_nodes(window_id)


func get_window_text(window_id: String) -> String:
	return String(_window_texts.get(window_id, ""))


func get_window_visible_text(window_id: String) -> String:
	return _visible_text_for_window(window_id)


func advance_text_printers(frames: int = 1, input: Dictionary = {}) -> Dictionary:
	for window_id in _visible_windows:
		var printer = _active_text_printers.get(window_id, null)
		if printer != null and printer.has_method("advance_frames"):
			printer.advance_frames(frames, input)
		_update_window_text_nodes(window_id)
	return _text_printers_snapshot()


func skip_text_printers_to_end(window_ids: Array = []) -> Dictionary:
	var target_ids := window_ids if not window_ids.is_empty() else _visible_windows
	for window_id_value in target_ids:
		var window_id := String(window_id_value)
		var printer = _active_text_printers.get(window_id, null)
		if printer != null and printer.has_method("skip_to_end"):
			printer.skip_to_end()
		_update_window_text_nodes(window_id)
	return _text_printers_snapshot()


func get_window_screen_rect(window_id: String, bg0_y: int = -1) -> Rect2i:
	var template := _window_template(window_id)
	if template.is_empty():
		return Rect2i()
	var scroll_y := _bg0_y if bg0_y < 0 else bg0_y
	return Rect2i(
		int(template.get("tilemap_left", 0)) * TILE_SIZE,
		int(template.get("tilemap_top", 0)) * TILE_SIZE - scroll_y,
		int(template.get("width", 0)) * TILE_SIZE,
		int(template.get("height", 0)) * TILE_SIZE
	)


func get_window_tilemap_rect(window_id: String) -> Rect2i:
	var template := _window_template(window_id)
	if template.is_empty():
		return Rect2i()
	var composite_rect := _window_composite_rect(template)
	if not composite_rect.is_empty():
		return Rect2i(
			int(composite_rect.get("x", 0)),
			int(composite_rect.get("y", 0)),
			int(composite_rect.get("w", int(template.get("width", 0)) * TILE_SIZE)),
			int(composite_rect.get("h", int(template.get("height", 0)) * TILE_SIZE))
		)
	var composite_size := _composite_size()
	return Rect2i(
		int(template.get("tilemap_left", 0)) * TILE_SIZE,
		_posmodi(int(template.get("tilemap_top", 0)) * TILE_SIZE, composite_size.y),
		int(template.get("width", 0)) * TILE_SIZE,
		int(template.get("height", 0)) * TILE_SIZE
	)


func compose_current_window_layer_image() -> Image:
	return compose_window_layer_image(_visible_windows, _bg0_y)


func compose_window_layer_image(window_ids: Array, bg0_y: int) -> Image:
	var source_image := _load_textbox_composite_image()
	var output := Image.create(VIEWPORT_SIZE.x, VIEWPORT_SIZE.y, false, Image.FORMAT_RGBA8)
	output.fill(Color(0, 0, 0, 0))
	if source_image == null:
		return output
	for window_id_value in window_ids:
		var window_id := String(window_id_value)
		var dst_rect := get_window_screen_rect(window_id, bg0_y)
		var src_rect := get_window_tilemap_rect(window_id)
		if dst_rect.size.x <= 0 or dst_rect.size.y <= 0:
			continue
		_blit_wrapped(source_image, output, src_rect, dst_rect.position)
	for window_id_value in window_ids:
		_blend_text_bitmap_for_window(output, String(window_id_value), bg0_y)
	return output


func get_renderer_snapshot() -> Dictionary:
	var windows := {}
	for window_id in _visible_windows:
		var template := _window_template(window_id)
		var text_info := _source_text_info(window_id)
		var screen_rect := get_window_screen_rect(window_id)
		var tilemap_rect := get_window_tilemap_rect(window_id)
		var composite_rect := _window_composite_rect(template)
		windows[window_id] = {
			"symbol": window_id,
			"screen_rect": _rect_to_array(screen_rect),
			"tilemap_rect": _rect_to_array(tilemap_rect),
			"tilemap_composite_rect_status": String(composite_rect.get("status", "fallback_virtual_tilemap_top")),
			"bg0_y": _bg0_y,
			"style_id": String(template.get("style_id", "")),
			"base_block": int(template.get("base_block", 0)),
			"panel_style": String(text_info.get("panel_style", "")),
			"font_id": String(text_info.get("font_id", "")),
			"text_material_id": String(text_info.get("text_material_id", "")),
			"text_info_status": String(text_info.get("status", "missing_generated_text_info")),
			"table_speed": text_info.get("table_speed", null),
			"source_speed": text_info.get("source_speed", 0),
			"effective_speed_source": String(text_info.get("effective_speed_source", "")),
			"can_ab_speed_up_print": bool(text_info.get("can_ab_speed_up_print", false)),
			"source_fit_width_px": text_info.get("source_fit_width_px", null),
			"text": String(_window_texts.get(window_id, "")),
			"visible_text": _visible_text_for_window(window_id),
			"source_text_bitmap": _source_text_bitmap_snapshot(window_id),
			"text_printer": _text_printer_window_snapshot(window_id),
			"source": template.get("source", {}) if typeof(template.get("source", {})) == TYPE_DICTIONARY else {},
		}
	return {
		"status": "first_pass",
		"visible_windows": _visible_windows.duplicate(true),
		"bg0_y": _bg0_y,
		"viewport_size": [VIEWPORT_SIZE.x, VIEWPORT_SIZE.y],
		"textbox_composite": _textbox_composite_path,
		"windows": windows,
		"source_trace": SOURCE_TRACE.duplicate(true),
		"source_composite_mapping_status": _source_composite_mapping_status(),
		"source_text_info_status": _source_text_info_status(),
		"text_printer": _text_printer_snapshot(),
		"text_printers": _text_printers_snapshot(),
		"runtime_color_policy": "rgba_textures_and_godot_materials",
		"unsupported": [
			"battle_text_full_control_code_renderer_pending",
			"battle_text_link_recorded_speed_overrides_pending",
			"battle_text_screenshot_comparison_pending",
		],
	}


func _ensure_window_nodes(window_id: String) -> void:
	if not _texture_nodes.has(window_id):
		var texture_rect := TextureRect.new()
		texture_rect.name = "%s_Texture" % window_id
		texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		texture_rect.stretch_mode = TextureRect.STRETCH_SCALE
		add_child(texture_rect)
		_texture_nodes[window_id] = texture_rect
	if not _text_texture_nodes.has(window_id):
		var text_texture_rect := TextureRect.new()
		text_texture_rect.name = "%s_SourceTextBitmap" % window_id
		text_texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		text_texture_rect.stretch_mode = TextureRect.STRETCH_SCALE
		add_child(text_texture_rect)
		_text_texture_nodes[window_id] = text_texture_rect
	if not _label_nodes.has(window_id):
		var label := Label.new()
		label.name = "%s_Text" % window_id
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.clip_text = true
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_color_override("font_color", Color(0.08, 0.08, 0.08, 1.0))
		add_child(label)
		_label_nodes[window_id] = label


func _apply_window_node_layout(window_id: String) -> void:
	var texture_rect: TextureRect = _texture_nodes[window_id]
	var text_texture_rect: TextureRect = _text_texture_nodes[window_id]
	var label: Label = _label_nodes[window_id]
	var screen_rect := get_window_screen_rect(window_id)
	var tilemap_rect := get_window_tilemap_rect(window_id)
	texture_rect.position = Vector2(screen_rect.position)
	texture_rect.size = Vector2(screen_rect.size)
	texture_rect.texture = _atlas_texture(tilemap_rect)
	text_texture_rect.position = Vector2(screen_rect.position)
	text_texture_rect.size = Vector2(screen_rect.size)

	var text_info := _source_text_info(window_id)
	var text_offset := Vector2(int(text_info.get("text_x", 0)), int(text_info.get("text_y", 0)))
	label.position = Vector2(screen_rect.position) + text_offset
	label.size = Vector2(screen_rect.size) - text_offset
	label.add_theme_font_size_override("font_size", int(text_info.get("font_size", 8)))
	_update_window_text_nodes(window_id)


func _set_node_visibility() -> void:
	for window_id in _texture_nodes.keys():
		var visible := _visible_windows.has(window_id)
		var texture_node: CanvasItem = _texture_nodes[window_id] as CanvasItem
		var text_texture_node: CanvasItem = _text_texture_nodes.get(window_id, null) as CanvasItem
		var label_node: CanvasItem = _label_nodes.get(window_id, null) as CanvasItem
		if texture_node is CanvasItem:
			texture_node.visible = visible
		if text_texture_node is CanvasItem:
			var summary := _source_text_bitmap_snapshot(window_id)
			text_texture_node.visible = visible and int(summary.get("rendered_glyph_count", 0)) > 0
		if label_node is CanvasItem:
			label_node.visible = visible and not _source_text_bitmap_covers_window(window_id)


func _atlas_texture(region: Rect2i) -> AtlasTexture:
	var atlas := AtlasTexture.new()
	atlas.atlas = _load_textbox_composite_texture()
	atlas.region = Rect2(region)
	return atlas


func _window_template(window_id: String) -> Dictionary:
	_load_interface_data()
	var record: Variant = _window_templates.get(window_id, {})
	return record if typeof(record) == TYPE_DICTIONARY else {}


func _window_composite_rect(template: Dictionary) -> Dictionary:
	var record: Variant = template.get("tilemap_composite_rect", {})
	return record if typeof(record) == TYPE_DICTIONARY else {}


func _source_composite_mapping_status() -> String:
	if _visible_windows.is_empty():
		return "no_visible_windows"
	for window_id in _visible_windows:
		if _window_composite_rect(_window_template(window_id)).is_empty():
			return "fallback_virtual_tilemap_top"
	return "generated_window_template_rects"


func _source_text_info(window_id: String) -> Dictionary:
	var template := _window_template(window_id)
	var record: Variant = template.get("text_info", {})
	return record if typeof(record) == TYPE_DICTIONARY else {}


func _source_text_info_status() -> String:
	if _visible_windows.is_empty():
		return "no_visible_windows"
	for window_id in _visible_windows:
		if _source_text_info(window_id).is_empty():
			return "missing_generated_text_info"
	return "generated_from_sTextOnWindowsInfo_Normal"


func _text_printer_snapshot() -> Dictionary:
	if _text_printer.is_empty():
		return {}
	var font_metrics := _dictionary_value(_text_printer.get("font_metrics", {}))
	var fonts := _dictionary_value(font_metrics.get("fonts", {}))
	return {
		"status": "first_pass_source_glyph_layout",
		"metadata_status": String(_text_printer.get("status", "")),
		"normal_window_text_info_count": int(_text_printer.get("normal_window_text_info_count", 0)),
		"normal_windows_type": String(_text_printer.get("normal_windows_type", "")),
		"message_effective_speed_source": String(_text_printer.get("message_effective_speed_source", "")),
		"runtime_status": "first_pass_source_glyph_layout",
		"source_font_metric_status": String(font_metrics.get("status", "")),
		"source_font_metric_count": int(font_metrics.get("font_count", fonts.size())),
		"source_font_atlas_binding_count": _source_font_atlas_binding_count(font_metrics),
		"source_font_role_mask_binding_count": _source_font_role_mask_binding_count(font_metrics),
		"source_font_atlas_status": "source_font_atlas_preview" if _source_font_atlas_binding_count(font_metrics) > 0 else "missing_source_font_atlas",
		"render_text_material_status": _render_text_material_status(),
		"visible_window_printer_count": _visible_windows.size(),
	}


func _ensure_text_printer(window_id: String, text: String, reveal_immediately: bool, text_printer_options: Dictionary = {}) -> void:
	var display_text := _display_text(text)
	var option_signature := JSON.stringify(text_printer_options, "", true)
	var printer = _active_text_printers.get(window_id, null)
	var should_restart := true
	if printer != null and printer.has_method("get_full_text"):
		var same_text := String(printer.get_full_text()) == display_text
		var same_source_text := true
		if printer.has_method("snapshot"):
			var printer_snapshot = printer.snapshot()
			if typeof(printer_snapshot) == TYPE_DICTIONARY:
				same_source_text = String(printer_snapshot.get("source_text", "")) == String(text_printer_options.get("source_text", ""))
		var same_options := String(_window_text_printer_option_signatures.get(window_id, "")) == option_signature
		var complete := bool(printer.is_complete()) if printer.has_method("is_complete") else true
		should_restart = not same_text or not same_source_text or not same_options or (not reveal_immediately and complete)
	if should_restart:
		printer = BATTLE_TEXT_PRINTER_SCRIPT.new()
		var options := {
			"player_text_speed": "OPTIONS_TEXT_SPEED_FAST",
		}
		options.merge(text_printer_options, true)
		printer.start(window_id, display_text, _source_text_info(window_id), _text_printer, options)
		_active_text_printers[window_id] = printer
		_window_text_printer_option_signatures[window_id] = option_signature
	if reveal_immediately and printer != null and printer.has_method("skip_to_end"):
		printer.skip_to_end()


func _update_window_text_nodes(window_id: String) -> void:
	var text_image := _compose_text_bitmap_for_window(window_id)
	var text_texture_rect: TextureRect = _text_texture_nodes.get(window_id, null) as TextureRect
	if text_texture_rect is TextureRect:
		if text_image != null and int(_source_text_bitmap_snapshot(window_id).get("rendered_glyph_count", 0)) > 0:
			text_texture_rect.texture = ImageTexture.create_from_image(text_image)
		else:
			text_texture_rect.texture = null
	var label: Label = _label_nodes.get(window_id, null) as Label
	if label is Label:
		label.text = _visible_text_for_window(window_id)
		label.visible = _visible_windows.has(window_id) and not _source_text_bitmap_covers_window(window_id)
	_set_node_visibility()


func _compose_text_bitmap_for_window(window_id: String) -> Image:
	var screen_rect := get_window_screen_rect(window_id)
	if screen_rect.size.x <= 0 or screen_rect.size.y <= 0:
		_source_text_bitmap_summaries[window_id] = {"status": "empty_window", "rendered_glyph_count": 0}
		return null
	var output := Image.create(screen_rect.size.x, screen_rect.size.y, false, Image.FORMAT_RGBA8)
	output.fill(Color(0, 0, 0, 0))
	var snapshot := _text_printer_window_snapshot(window_id)
	var layout := _dictionary_value(snapshot.get("source_glyph_layout", {}))
	var glyphs := _array_value(layout.get("glyphs", []))
	var pixel_effect_summary := _dictionary_value(snapshot.get("source_window_pixel_effect_summary", {}))
	var materials := _render_text_material_colors()
	var rendered_count := 0
	var role_colored_count := 0
	var atlas_preview_count := 0
	var missing_count := 0
	var colored_pixel_count := 0
	var transparent_role_pixel_count := 0
	for glyph_value in glyphs:
		var glyph := _dictionary_value(glyph_value)
		if String(glyph.get("source_font_atlas_status", "")) != "source_font_atlas_preview":
			missing_count += 1
			continue
		var source_rect := _rect_from_array(_array_value(glyph.get("source_glyph_rect", [])))
		if source_rect.size.x <= 0 or source_rect.size.y <= 0:
			missing_count += 1
			continue
		var visible_rect := _rect_from_array(_array_value(glyph.get("source_glyph_visible_rect", [])))
		var blit_rect := Rect2i(
			source_rect.position.x + max(0, visible_rect.position.x),
			source_rect.position.y + max(0, visible_rect.position.y),
			max(0, min(source_rect.size.x, visible_rect.size.x)),
			max(0, min(source_rect.size.y, visible_rect.size.y))
		)
		if blit_rect.size.x <= 0 or blit_rect.size.y <= 0:
			missing_count += 1
			continue
		var dst := Vector2i(int(glyph.get("x", 0)), int(glyph.get("y", 0)))
		var role_mask := _load_font_role_mask_image(String(glyph.get("source_font_role_mask_image", "")))
		if role_mask != null and not materials.is_empty():
			var glyph_colored_pixels := 0
			var glyph_transparent_pixels := 0
			var color_indices := _dictionary_value(glyph.get("render_text_color_indices", {}))
			for y in range(blit_rect.size.y):
				for x in range(blit_rect.size.x):
					var target_x := dst.x + x
					var target_y := dst.y + y
					if target_x < 0 or target_y < 0 or target_x >= output.get_width() or target_y >= output.get_height():
						continue
					var role_pixel := role_mask.get_pixel(blit_rect.position.x + x, blit_rect.position.y + y)
					var role := int(round(role_pixel.r * 3.0))
					role = clamp(role, 0, 3)
					var slot := _render_text_slot_for_role(role)
					var material_index := int(color_indices.get(slot, 0))
					var color := _render_text_material_color(material_index, materials)
					if color.a <= 0.0:
						glyph_transparent_pixels += 1
						continue
					output.set_pixel(target_x, target_y, color)
					glyph_colored_pixels += 1
			role_colored_count += 1
			rendered_count += 1
			colored_pixel_count += glyph_colored_pixels
			transparent_role_pixel_count += glyph_transparent_pixels
			continue
		var atlas := _load_source_font_atlas_image(String(glyph.get("source_font_atlas_image", "")))
		if atlas == null:
			missing_count += 1
			continue
		output.blend_rect(atlas, blit_rect, dst)
		atlas_preview_count += 1
		rendered_count += 1
	var status := "render_text_role_colored_preview" if role_colored_count > 0 else ("source_font_atlas_preview" if rendered_count > 0 else "no_source_font_atlas_glyphs")
	_source_text_bitmap_summaries[window_id] = {
		"status": status,
		"rendered_glyph_count": rendered_count,
		"role_colored_glyph_count": role_colored_count,
		"atlas_preview_glyph_count": atlas_preview_count,
		"missing_glyph_count": missing_count,
		"colored_pixel_count": colored_pixel_count,
		"transparent_role_pixel_count": transparent_role_pixel_count,
		"render_text_material_status": _render_text_material_status(),
		"source_window_pixel_effect_status": String(snapshot.get("source_window_pixel_effect_status", "")),
		"source_window_pixel_effect_summary": pixel_effect_summary.duplicate(true),
		"window_size": [screen_rect.size.x, screen_rect.size.y],
		"source": "BattleTextPrinter.source_glyph_layout",
	}
	return output


func _blend_text_bitmap_for_window(target: Image, window_id: String, bg0_y: int) -> void:
	var text_image := _compose_text_bitmap_for_window(window_id)
	if text_image == null:
		return
	var summary := _source_text_bitmap_snapshot(window_id)
	if int(summary.get("rendered_glyph_count", 0)) <= 0:
		return
	var dst_rect := get_window_screen_rect(window_id, bg0_y)
	target.blend_rect(text_image, Rect2i(Vector2i.ZERO, Vector2i(text_image.get_width(), text_image.get_height())), dst_rect.position)


func _source_text_bitmap_snapshot(window_id: String) -> Dictionary:
	var summary := _dictionary_value(_source_text_bitmap_summaries.get(window_id, {}))
	if not summary.is_empty():
		return summary
	return {"status": "not_composed", "rendered_glyph_count": 0, "missing_glyph_count": 0}


func _source_text_bitmap_covers_window(window_id: String) -> bool:
	var summary := _source_text_bitmap_snapshot(window_id)
	var snapshot := _text_printer_window_snapshot(window_id)
	var layout := _dictionary_value(snapshot.get("source_glyph_layout", {}))
	var glyph_count := int(layout.get("glyph_count", 0))
	return glyph_count > 0 and int(summary.get("rendered_glyph_count", 0)) == glyph_count


func _load_source_font_atlas_image(path: String) -> Image:
	if path.is_empty():
		return null
	if _source_font_atlas_images.has(path):
		return _source_font_atlas_images[path]
	var image := Image.new()
	var image_path := ProjectSettings.globalize_path(path) if path.begins_with("res://") else path
	var error := image.load(image_path)
	if error != OK:
		return null
	_source_font_atlas_images[path] = image
	return image


func _load_font_role_mask_image(path: String) -> Image:
	if path.is_empty():
		return null
	if _font_role_mask_images.has(path):
		return _font_role_mask_images[path]
	var image := Image.new()
	var image_path := ProjectSettings.globalize_path(path) if path.begins_with("res://") else path
	var error := image.load(image_path)
	if error != OK:
		return null
	_font_role_mask_images[path] = image
	return image


func _render_text_material_colors() -> Dictionary:
	var result := {}
	var materials := _dictionary_value(_interface_data.get("render_text_materials", {}))
	var colors := _dictionary_value(materials.get("colors", {}))
	for key in colors.keys():
		var record := _dictionary_value(colors[key])
		var index := int(record.get("index", key))
		result[index] = Color(
			float(record.get("r", 0)) / 255.0,
			float(record.get("g", 0)) / 255.0,
			float(record.get("b", 0)) / 255.0,
			float(record.get("a", 0)) / 255.0
		)
	return result


func _render_text_material_status() -> String:
	var materials := _dictionary_value(_interface_data.get("render_text_materials", {}))
	return String(materials.get("status", "missing_render_text_materials"))


func _render_text_material_color(index_value: int, materials: Dictionary) -> Color:
	var index := index_value & 0xF
	if materials.has(index):
		return materials[index]
	return Color(0, 0, 0, 0)


func _render_text_slot_for_role(role: int) -> String:
	match role:
		1:
			return "foreground"
		2:
			return "shadow"
		3:
			return "accent"
	return "background"


func _visible_text_for_window(window_id: String) -> String:
	var printer = _active_text_printers.get(window_id, null)
	if printer != null and printer.has_method("get_visible_text"):
		return String(printer.get_visible_text())
	return _display_text(String(_window_texts.get(window_id, "")))


func _text_printer_window_snapshot(window_id: String) -> Dictionary:
	var printer = _active_text_printers.get(window_id, null)
	if printer != null and printer.has_method("snapshot"):
		var snapshot = printer.snapshot()
		return snapshot if typeof(snapshot) == TYPE_DICTIONARY else {}
	return {}


func _text_printers_snapshot() -> Dictionary:
	var snapshots := {}
	for window_id in _visible_windows:
		snapshots[String(window_id)] = _text_printer_window_snapshot(String(window_id))
	return snapshots


func _load_interface_data() -> void:
	if not _interface_data.is_empty():
		return
	_ensure_data_registry()
	if _data_registry != null and _data_registry.has_method("get_battle_interface_data"):
		var data: Variant = _data_registry.get_battle_interface_data()
		if typeof(data) == TYPE_DICTIONARY:
			_interface_data = data
	if _interface_data.is_empty():
		return
	var templates: Variant = _interface_data.get("window_templates", {})
	if typeof(templates) == TYPE_DICTIONARY:
		_window_templates = templates
	var text_printer: Variant = _interface_data.get("text_printer", {})
	if typeof(text_printer) == TYPE_DICTIONARY:
		_text_printer = text_printer
	var tilemaps: Variant = _interface_data.get("tilemaps", {})
	var textbox_map: Variant = tilemaps.get("textbox_map", {}) if typeof(tilemaps) == TYPE_DICTIONARY else {}
	var composite: Variant = textbox_map.get("tilemap_composite", {}) if typeof(textbox_map) == TYPE_DICTIONARY else {}
	if typeof(composite) == TYPE_DICTIONARY:
		_textbox_composite_path = String(composite.get("image", ""))


func _ensure_data_registry() -> void:
	if _data_registry != null:
		return
	if has_node("/root/DataRegistry"):
		_data_registry = get_node("/root/DataRegistry")


func _load_textbox_composite_texture() -> Texture2D:
	_load_interface_data()
	if _textbox_composite_texture != null:
		return _textbox_composite_texture
	if _textbox_composite_path.is_empty():
		return null
	_textbox_composite_texture = load(_textbox_composite_path)
	return _textbox_composite_texture


func _load_textbox_composite_image() -> Image:
	_load_interface_data()
	if _textbox_composite_image != null:
		return _textbox_composite_image
	if _textbox_composite_path.is_empty():
		return null
	var image := Image.new()
	var image_path := ProjectSettings.globalize_path(_textbox_composite_path) if _textbox_composite_path.begins_with("res://") else _textbox_composite_path
	var error := image.load(image_path)
	if error != OK:
		return null
	_textbox_composite_image = image
	return _textbox_composite_image


func _composite_size() -> Vector2i:
	var image := _load_textbox_composite_image()
	if image != null:
		return Vector2i(image.get_width(), image.get_height())
	var texture := _load_textbox_composite_texture()
	if texture != null:
		return Vector2i(texture.get_width(), texture.get_height())
	return Vector2i(512, 256)


func _blit_wrapped(source: Image, target: Image, src_rect: Rect2i, dst_pos: Vector2i) -> void:
	var remaining_h := src_rect.size.y
	var src_y := src_rect.position.y
	var dst_y := dst_pos.y
	while remaining_h > 0:
		var chunk_h: int = min(remaining_h, source.get_height() - src_y)
		if chunk_h <= 0:
			src_y = 0
			continue
		target.blit_rect(
			source,
			Rect2i(src_rect.position.x, src_y, src_rect.size.x, chunk_h),
			Vector2i(dst_pos.x, dst_y)
		)
		remaining_h -= chunk_h
		dst_y += chunk_h
		src_y = 0


func _display_text(text: String) -> String:
	return text.replace("\t", "    ")


func _display_text_from_record(record: Dictionary) -> String:
	if record.has("text"):
		return String(record.get("text", ""))
	if record.has("display_text"):
		return String(record.get("display_text", ""))
	var nested := _dictionary_value(record.get("record", {}))
	if nested.has("display_text"):
		return String(nested.get("display_text", ""))
	if nested.has("source_text"):
		return String(nested.get("source_text", ""))
	return ""


func _text_printer_options_from_record(record: Dictionary, overrides: Dictionary = {}) -> Dictionary:
	var options := {}
	var nested := _dictionary_value(record.get("record", {}))
	var source_text := String(record.get("source_text", nested.get("source_text", "")))
	var encoding := _dictionary_value(record.get("encoding", nested.get("encoding", {})))
	var substitutions := _array_value(record.get("substitutions", []))
	for substitution_value in substitutions:
		var substitution := _dictionary_value(substitution_value)
		var raw := String(substitution.get("raw", ""))
		if raw.is_empty():
			continue
		source_text = source_text.replace(raw, String(substitution.get("value", "")))
	if not source_text.is_empty():
		options["source_text"] = source_text
		options["source_text_label"] = String(record.get("label", nested.get("label", record.get("message", ""))))
	if not encoding.is_empty() and substitutions.is_empty():
		options["source_encoding"] = encoding
		options["source_bytes"] = encoding.get("bytes", [])
		options["source_glyphs"] = encoding.get("glyphs", [])
		options["source_encoding_hex"] = String(encoding.get("hex", ""))
	options["text_controls"] = record.get("text_controls", nested.get("text_controls", []))
	options["audio_cues"] = record.get("audio_cues", nested.get("audio_cues", []))
	options["metadata_only"] = record.get("metadata_only", nested.get("metadata_only", []))
	options.merge(overrides, true)
	return options


func _text_printer_options_for_window(window_id: String, text_printer_options: Dictionary) -> Dictionary:
	var options := {}
	for key in text_printer_options.keys():
		if String(key) == "windows":
			continue
		options[key] = text_printer_options[key]
	var window_options := _dictionary_value(text_printer_options.get("windows", {}))
	var specific_options := _dictionary_value(window_options.get(window_id, {}))
	options.merge(specific_options, true)
	return options


func _dictionary_value(value) -> Dictionary:
	return value if typeof(value) == TYPE_DICTIONARY else {}


func _array_value(value) -> Array:
	return value if typeof(value) == TYPE_ARRAY else []


func _source_font_atlas_binding_count(font_metrics: Dictionary) -> int:
	var count := 0
	var fonts := _dictionary_value(font_metrics.get("fonts", {}))
	for font_id in fonts.keys():
		var record := _dictionary_value(fonts.get(font_id, {}))
		if String(_dictionary_value(record.get("glyph_atlas", {})).get("status", "")) == "source_font_atlas_preview":
			count += 1
	return count


func _source_font_role_mask_binding_count(font_metrics: Dictionary) -> int:
	var count := 0
	var fonts := _dictionary_value(font_metrics.get("fonts", {}))
	for font_id in fonts.keys():
		var record := _dictionary_value(fonts.get(font_id, {}))
		var binding := _dictionary_value(record.get("glyph_atlas", {}))
		if String(binding.get("role_mask_status", "")) == "source_font_role_mask":
			count += 1
	return count


func _rect_to_array(rect: Rect2i) -> Array:
	return [rect.position.x, rect.position.y, rect.size.x, rect.size.y]


func _rect_from_array(values: Array) -> Rect2i:
	if values.size() < 4:
		return Rect2i()
	return Rect2i(int(values[0]), int(values[1]), int(values[2]), int(values[3]))


func _posmodi(value: int, divisor: int) -> int:
	if divisor <= 0:
		return value
	var result := value % divisor
	return result + divisor if result < 0 else result
