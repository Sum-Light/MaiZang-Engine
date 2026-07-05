extends Control

const TILE_SIZE := 8
const VIEWPORT_SIZE := Vector2i(240, 160)
const BG0_Y_ACTION_CHOOSE := 160
const BG0_Y_MOVE_CHOOSE := 320

const SOURCE_TEXT_INFO := {
	"B_WIN_MSG": {"text_x": 0, "text_y": 1, "font_id": "FONT_NORMAL", "font_size": 8, "source_speed": "player_text_speed", "panel_style": "message_panel", "text_material_id": "battle_text_primary"},
	"B_WIN_ACTION_PROMPT": {"text_x": 1, "text_y": 1, "font_id": "FONT_NORMAL", "font_size": 8, "source_speed": 0, "panel_style": "message_panel", "text_material_id": "battle_text_primary"},
	"B_WIN_ACTION_MENU": {"text_x": 0, "text_y": 1, "font_id": "FONT_NORMAL", "font_size": 8, "source_speed": 0, "panel_style": "menu_panel", "text_material_id": "battle_text_menu"},
	"B_WIN_MOVE_NAME_1": {"text_x": 0, "text_y": 1, "font_id": "FONT_NARROW", "font_size": 8, "source_speed": 0, "panel_style": "menu_panel", "text_material_id": "battle_text_menu", "source_fit_width_px": 64},
	"B_WIN_MOVE_NAME_2": {"text_x": 0, "text_y": 1, "font_id": "FONT_NARROW", "font_size": 8, "source_speed": 0, "panel_style": "menu_panel", "text_material_id": "battle_text_menu", "source_fit_width_px": 64},
	"B_WIN_MOVE_NAME_3": {"text_x": 0, "text_y": 1, "font_id": "FONT_NARROW", "font_size": 8, "source_speed": 0, "panel_style": "menu_panel", "text_material_id": "battle_text_menu", "source_fit_width_px": 64},
	"B_WIN_MOVE_NAME_4": {"text_x": 0, "text_y": 1, "font_id": "FONT_NARROW", "font_size": 8, "source_speed": 0, "panel_style": "menu_panel", "text_material_id": "battle_text_menu", "source_fit_width_px": 64},
	"B_WIN_PP": {"text_x": 0, "text_y": 1, "font_id": "FONT_NARROW", "font_size": 8, "source_speed": 0, "panel_style": "menu_panel", "text_material_id": "battle_text_menu"},
	"B_WIN_PP_REMAINING": {"text_x": 2, "text_y": 1, "font_id": "FONT_NORMAL", "font_size": 8, "source_speed": 0, "panel_style": "menu_panel", "text_material_id": "battle_pp_numeric"},
	"B_WIN_MOVE_TYPE": {"text_x": 0, "text_y": 1, "font_id": "FONT_NARROW", "font_size": 8, "source_speed": 0, "panel_style": "menu_panel", "text_material_id": "battle_text_menu"},
}

const SOURCE_TRACE := [
	"src/battle_bg.c:LoadBattleTextboxAndBackground",
	"src/battle_bg.c:sStandardBattleWindowTemplates",
	"src/battle_message.c:sTextOnWindowsInfo_Normal",
	"src/battle_message.c:BattlePutTextOnWindow",
]

var _data_registry: Node = null
var _interface_data: Dictionary = {}
var _window_templates: Dictionary = {}
var _texture_nodes: Dictionary = {}
var _label_nodes: Dictionary = {}
var _window_texts: Dictionary = {}
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


func show_message_window(text: String) -> void:
	show_windows(["B_WIN_MSG"], 0, {"B_WIN_MSG": text})


func show_action_windows(prompt_text: String, menu_text: String) -> void:
	show_windows(
		["B_WIN_ACTION_PROMPT", "B_WIN_ACTION_MENU"],
		BG0_Y_ACTION_CHOOSE,
		{
			"B_WIN_ACTION_PROMPT": prompt_text,
			"B_WIN_ACTION_MENU": menu_text,
		}
	)


func show_move_windows(move_names: Array, pp_label: String, pp_remaining: String, move_type: String) -> void:
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
		text_by_window
	)


func clear_windows() -> void:
	_visible_windows = []
	for node in _texture_nodes.values():
		if node is CanvasItem:
			node.visible = false
	for node in _label_nodes.values():
		if node is CanvasItem:
			node.visible = false


func show_windows(window_ids: Array, bg0_y: int, text_by_window: Dictionary = {}) -> void:
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
		_apply_window_node_layout(window_id)
	_set_node_visibility()


func set_window_text(window_id: String, text: String) -> void:
	_window_texts[window_id] = text
	var label: Label = _label_nodes.get(window_id, null) as Label
	if label is Label:
		label.text = _display_text(text)


func get_window_text(window_id: String) -> String:
	return String(_window_texts.get(window_id, ""))


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
			"source_speed": text_info.get("source_speed", 0),
			"text": String(_window_texts.get(window_id, "")),
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
		"runtime_color_policy": "rgba_textures_and_godot_materials",
		"unsupported": [
			"battle_text_glyph_renderer_pending",
			"battle_text_printer_timing_pending",
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
	label.text = _display_text(String(_window_texts.get(window_id, "")))
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
	var record: Variant = SOURCE_TEXT_INFO.get(window_id, {})
	return record if typeof(record) == TYPE_DICTIONARY else {}


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


func _rect_to_array(rect: Rect2i) -> Array:
	return [rect.position.x, rect.position.y, rect.size.x, rect.size.y]


func _posmodi(value: int, divisor: int) -> int:
	if divisor <= 0:
		return value
	var result := value % divisor
	return result + divisor if result < 0 else result
