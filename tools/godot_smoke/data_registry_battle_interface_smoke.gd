extends SceneTree

const DATA_REGISTRY_SCRIPT := preload("res://scripts/autoload/data_registry.gd")

var _failed := false


func _init() -> void:
	var registry = DATA_REGISTRY_SCRIPT.new()
	registry._ready()

	var data := registry.get_battle_interface_data()
	var stats := _dict(data.get("stats", {}))
	_assert(typeof(data) == TYPE_DICTIONARY and not data.is_empty(), "expected battle interface data")
	_assert(int(stats.get("texture_count", 0)) == 68, "unexpected battle interface texture count")
	_assert(int(stats.get("source_png_asset_count", 0)) == 68, "unexpected battle interface source PNG count")
	_assert(int(stats.get("source_color_file_count", 0)) == 8, "unexpected battle interface source color file count")
	_assert(int(stats.get("source_binary_tilemap_count", 0)) == 1, "unexpected battle interface tilemap count")
	_assert(int(stats.get("tilemap_composite_count", 0)) == 1, "unexpected battle interface composite count")
	_assert(int(stats.get("window_template_count", 0)) == 25, "unexpected battle window template count")
	_assert(int(stats.get("window_template_composite_rect_count", 0)) == 10, "unexpected battle window composite rect count")
	_assert(int(stats.get("healthbox_coord_group_count", 0)) == 2, "unexpected healthbox coord group count")
	_assert(int(stats.get("healthbox_frame_texture_count", 0)) == 5, "unexpected healthbox frame texture count")
	_assert(int(stats.get("healthbox_element_texture_count", 0)) == 13, "unexpected healthbox element texture count")
	_assert(int(stats.get("gimmick_trigger_texture_count", 0)) == 5, "unexpected gimmick trigger texture count")
	_assert(int(stats.get("gimmick_indicator_texture_count", 0)) == 23, "unexpected gimmick indicator texture count")
	_assert(int(stats.get("missing_texture_count", -1)) == 0, "expected no missing battle interface textures")
	_assert(int(stats.get("tilemap_warning_count", -1)) == 0, "expected no battle interface tilemap warnings")

	var color_policy := _dict(data.get("runtime_color_policy", {}))
	_assert(String(color_policy.get("status", "")) == "no_runtime_palette", "expected no-runtime-palette policy")
	_assert(String(color_policy.get("variant_rule", "")).contains("distinct RGBA images"), "expected distinct RGBA variant rule")
	_assert(String(color_policy.get("effect_rule", "")).contains("Godot Shader"), "expected Godot shader/material effect rule")

	var textbox := registry.get_battle_interface_texture_record("textbox")
	_assert(String(textbox.get("id", "")) == "textbox", "expected textbox texture")
	_assert(String(textbox.get("group", "")) == "textbox", "expected textbox group")
	_assert(_asset_exists(textbox), "expected textbox PNG")
	_assert(_size_is(_dict(textbox.get("size", {})), 128, 128), "expected textbox size")
	_assert(bool(_dict(textbox.get("alpha", {})).get("has_opaque", false)), "expected textbox visible pixels")

	var hpbar := registry.get_battle_interface_texture_record("graphics/battle_interface/hpbar.png")
	_assert(String(hpbar.get("id", "")) == "hpbar", "expected hpbar texture by source path")
	_assert(String(hpbar.get("role", "")) == "hp_bar", "expected hpbar role")
	_assert(_size_is(_dict(hpbar.get("size", {})), 96, 8), "expected hpbar size")

	var tera := registry.get_battle_interface_texture_record("tera_trigger")
	_assert(String(tera.get("group", "")) == "gimmick_trigger", "expected Tera trigger group")
	_assert(_size_is(_dict(tera.get("size", {})), 32, 64), "expected Tera trigger size")

	var action_menu := registry.get_battle_window_template_record("action_menu")
	_assert(String(action_menu.get("symbol", "")) == "B_WIN_ACTION_MENU", "expected action menu template")
	_assert(int(action_menu.get("tilemap_left", -1)) == 17, "expected action menu left")
	_assert(int(action_menu.get("tilemap_top", -1)) == 35, "expected action menu top")
	_assert(int(action_menu.get("width", -1)) == 12, "expected action menu width")
	_assert(int(action_menu.get("height", -1)) == 4, "expected action menu height")
	_assert(String(action_menu.get("style_id", "")) == "battle_menu_text", "expected action menu style")
	_assert(not action_menu.has("paletteNum"), "window template must not expose source paletteNum")
	_assert(not action_menu.has("source_palette"), "window template must not expose source palette data")
	var action_menu_composite_rect := _dict(action_menu.get("tilemap_composite_rect", {}))
	_assert(_rect_record_is(action_menu_composite_rect, 136, 216, 96, 32), "expected action menu composite rect")
	_assert(String(action_menu_composite_rect.get("status", "")) == "first_pass_generated_textbox_map_preview_rows", "expected generated action menu composite status")

	var move_desc := registry.get_battle_window_template_record("B_WIN_MOVE_DESCRIPTION")
	_assert(String(move_desc.get("symbol", "")) == "B_WIN_MOVE_DESCRIPTION", "expected move description template")
	_assert(int(move_desc.get("tilemap_left", -1)) == 1, "expected move description left")
	_assert(int(move_desc.get("tilemap_top", -1)) == 47, "expected move description top")

	var sections := _dict(data.get("sections", {}))
	var healthbox := _dict(sections.get("healthbox", {}))
	var coords := _dict(healthbox.get("coords", {}))
	var singles := _dict(coords.get("BATTLE_COORDS_SINGLES", {}))
	var doubles := _dict(coords.get("BATTLE_COORDS_DOUBLES", {}))
	_assert(_coord_is(_dict(singles.get("B_POSITION_PLAYER_LEFT", {})), 158, 88), "expected singles player healthbox coord")
	_assert(_coord_is(_dict(singles.get("B_POSITION_OPPONENT_LEFT", {})), 44, 30), "expected singles opponent healthbox coord")
	_assert(_coord_is(_dict(doubles.get("B_POSITION_PLAYER_RIGHT", {})), 171, 101), "expected doubles player-right healthbox coord")
	_assert(_coord_is(_dict(doubles.get("B_POSITION_OPPONENT_RIGHT", {})), 32, 44), "expected doubles opponent-right healthbox coord")

	var tilemaps := _dict(data.get("tilemaps", {}))
	var textbox_map := _dict(tilemaps.get("textbox_map", {}))
	var composite := _dict(textbox_map.get("tilemap_composite", {}))
	_assert(int(textbox_map.get("entry_count_16bit", 0)) == 2048, "expected textbox tilemap entries")
	_assert(int(composite.get("missing_tile_count", -1)) == 0, "expected no missing textbox composite tiles")
	_assert(int(composite.get("window_rect_count", 0)) == 10, "expected textbox composite window rect count")
	_assert(String(composite.get("window_rect_status", "")) == "first_pass_generated_textbox_map_preview_rows", "expected textbox composite window rect status")
	_assert(_asset_exists(composite), "expected textbox tilemap composite PNG")
	_assert(_size_is(_dict(composite.get("size", {})), 512, 256), "expected textbox composite size")

	var ability_popup := _dict(sections.get("ability_popup", {}))
	var motion := _dict(ability_popup.get("motion", {}))
	_assert(int(_dict(motion.get("x_diff", {})).get("value", 0)) == 64, "expected ability popup x diff")
	_assert(int(_dict(motion.get("x_slide", {})).get("value", 0)) == 128, "expected ability popup x slide")
	_assert(int(_dict(motion.get("x_speed_px_per_frame", {})).get("value", 0)) == 4, "expected ability popup x speed")
	_assert(int(_dict(motion.get("idle_frames", {})).get("value", 0)) == 48, "expected ability popup idle frames")
	_assert(String(_dict(motion.get("audio_cue", {})).get("status", "")) == "metadata_only", "expected ability popup audio metadata-only")

	var source_colors := _dict(data.get("source_color_provenance", {}))
	for color_id in source_colors.keys():
		var record := _dict(source_colors.get(color_id, {}))
		_assert(bool(record.get("import_only", false)), "source color file must be import-only for %s" % color_id)
		_assert(int(record.get("color_count", 0)) > 0, "expected colors for source color file %s" % color_id)

	if _failed:
		return

	print(JSON.stringify({
		"data_registry_battle_interface_smoke": "ok",
		"texture_count": int(stats.get("texture_count", 0)),
		"window_template_count": int(stats.get("window_template_count", 0)),
		"tilemap_composite_count": int(stats.get("tilemap_composite_count", 0)),
	}))
	registry.free()
	quit(0)


func _asset_exists(asset: Dictionary) -> bool:
	var path := String(asset.get("image", ""))
	return not path.is_empty() and FileAccess.file_exists(path)


func _coord_is(coord: Dictionary, x: int, y: int) -> bool:
	return int(coord.get("x", 0)) == x and int(coord.get("y", 0)) == y


func _size_is(size: Dictionary, w: int, h: int) -> bool:
	return int(size.get("w", 0)) == w and int(size.get("h", 0)) == h


func _rect_record_is(rect: Dictionary, x: int, y: int, w: int, h: int) -> bool:
	return (
		int(rect.get("x", -1)) == x
		and int(rect.get("y", -1)) == y
		and int(rect.get("w", -1)) == w
		and int(rect.get("h", -1)) == h
	)


func _dict(value) -> Dictionary:
	return value if typeof(value) == TYPE_DICTIONARY else {}


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true
	quit(1)
