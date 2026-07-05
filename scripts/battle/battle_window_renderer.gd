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
var _label_nodes: Dictionary = {}
var _window_texts: Dictionary = {}
var _active_text_printers: Dictionary = {}
var _visible_windows: Array = []
var _bg0_y := 0
var _textbox_composite_path := ""
var _textbox_composite_texture: Texture2D = null
var _textbox_composite_image: Image = null


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
	var label: Label = _label_nodes.get(window_id, null) as Label
	if label is Label:
		label.text = _visible_text_for_window(window_id)


func get_window_text(window_id: String) -> String:
	return String(_window_texts.get(window_id, ""))


func get_window_visible_text(window_id: String) -> String:
	return _visible_text_for_window(window_id)


func advance_text_printers(frames: int = 1, input: Dictionary = {}) -> Dictionary:
	for window_id in _visible_windows:
		var printer = _active_text_printers.get(window_id, null)
		if printer != null and printer.has_method("advance_frames"):
			printer.advance_frames(frames, input)
		_update_window_label_text(window_id)
	return _text_printers_snapshot()


func skip_text_printers_to_end(window_ids: Array = []) -> Dictionary:
	var target_ids := window_ids if not window_ids.is_empty() else _visible_windows
	for window_id_value in target_ids:
		var window_id := String(window_id_value)
		var printer = _active_text_printers.get(window_id, null)
		if printer != null and printer.has_method("skip_to_end"):
			printer.skip_to_end()
		_update_window_label_text(window_id)
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
			"battle_text_glyph_bitmap_renderer_pending",
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
	var label: Label = _label_nodes[window_id]
	var screen_rect := get_window_screen_rect(window_id)
	var tilemap_rect := get_window_tilemap_rect(window_id)
	texture_rect.position = Vector2(screen_rect.position)
	texture_rect.size = Vector2(screen_rect.size)
	texture_rect.texture = _atlas_texture(tilemap_rect)

	var text_info := _source_text_info(window_id)
	var text_offset := Vector2(int(text_info.get("text_x", 0)), int(text_info.get("text_y", 0)))
	label.position = Vector2(screen_rect.position) + text_offset
	label.size = Vector2(screen_rect.size) - text_offset
	label.text = _visible_text_for_window(window_id)
	label.add_theme_font_size_override("font_size", int(text_info.get("font_size", 8)))


func _set_node_visibility() -> void:
	for window_id in _texture_nodes.keys():
		var visible := _visible_windows.has(window_id)
		var texture_node: CanvasItem = _texture_nodes[window_id] as CanvasItem
		var label_node: CanvasItem = _label_nodes.get(window_id, null) as CanvasItem
		if texture_node is CanvasItem:
			texture_node.visible = visible
		if label_node is CanvasItem:
			label_node.visible = visible


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
		"visible_window_printer_count": _visible_windows.size(),
	}


func _ensure_text_printer(window_id: String, text: String, reveal_immediately: bool, text_printer_options: Dictionary = {}) -> void:
	var display_text := _display_text(text)
	var printer = _active_text_printers.get(window_id, null)
	var should_restart := true
	if printer != null and printer.has_method("get_full_text"):
		var same_text := String(printer.get_full_text()) == display_text
		var same_source_text := true
		if printer.has_method("snapshot"):
			var printer_snapshot = printer.snapshot()
			if typeof(printer_snapshot) == TYPE_DICTIONARY:
				same_source_text = String(printer_snapshot.get("source_text", "")) == String(text_printer_options.get("source_text", ""))
		var complete := bool(printer.is_complete()) if printer.has_method("is_complete") else true
		should_restart = not same_text or not same_source_text or (not reveal_immediately and complete)
	if should_restart:
		printer = BATTLE_TEXT_PRINTER_SCRIPT.new()
		var options := {
			"player_text_speed": "OPTIONS_TEXT_SPEED_FAST",
		}
		options.merge(text_printer_options, true)
		printer.start(window_id, display_text, _source_text_info(window_id), _text_printer, options)
		_active_text_printers[window_id] = printer
	if reveal_immediately and printer != null and printer.has_method("skip_to_end"):
		printer.skip_to_end()


func _update_window_label_text(window_id: String) -> void:
	var label: Label = _label_nodes.get(window_id, null) as Label
	if label is Label:
		label.text = _visible_text_for_window(window_id)


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


func _rect_to_array(rect: Rect2i) -> Array:
	return [rect.position.x, rect.position.y, rect.size.x, rect.size.y]


func _posmodi(value: int, divisor: int) -> int:
	if divisor <= 0:
		return value
	var result := value % divisor
	return result + divisor if result < 0 else result
