extends SceneTree

const DATA_REGISTRY_SCRIPT := preload("res://scripts/autoload/data_registry.gd")

var _failed := false


func _init() -> void:
	var registry = DATA_REGISTRY_SCRIPT.new()
	registry._ready()

	var data := registry.get_battle_environments_data()
	var stats := _dict(data.get("stats", {}))
	_assert(typeof(data) == TYPE_DICTIONARY and not data.is_empty(), "expected battle environment data")
	_assert(int(stats.get("environment_count", 0)) == 35, "unexpected battle environment count")
	_assert(int(stats.get("source_table_environment_count", 0)) == 35, "unexpected source environment table count")
	_assert(int(stats.get("background_texture_count", 0)) == 23, "unexpected battle background texture count")
	_assert(int(stats.get("entry_texture_count", 0)) == 23, "unexpected battle entry texture count")
	_assert(int(stats.get("palette_metadata_count", 0)) == 23, "unexpected battle environment palette count")
	_assert(int(stats.get("first_pass_asset_environment_count", 0)) == 23, "unexpected first-pass environment asset count")
	_assert(int(stats.get("unsupported_asset_environment_count", 0)) == 12, "unexpected unsupported asset environment count")
	_assert(int(stats.get("map_scene_mapping_count", 0)) == 8, "unexpected map scene mapping count")
	_assert(int(stats.get("warning_count", -1)) == 0, "expected no battle environment warnings")

	var grass := registry.get_battle_environment_record("grass")
	var grass_by_id := registry.get_battle_environment_record(0)
	_assert(String(grass.get("symbol", "")) == "BATTLE_ENVIRONMENT_GRASS", "expected grass battle environment")
	_assert(String(grass_by_id.get("symbol", "")) == "BATTLE_ENVIRONMENT_GRASS", "expected grass battle environment by id")
	_assert(_coverage_status(grass, "asset_status") == "first_pass", "expected grass first-pass asset status")
	_assert(String(_dict(grass.get("source_assets", {})).get("background_asset", "")) == "TallGrass", "expected grass TallGrass background")
	_assert(_asset_exists(_dict(grass.get("background", {}))), "expected grass background PNG")
	_assert(_asset_exists(_dict(grass.get("entry", {}))), "expected grass entry PNG")
	_assert(_size_is(_dict(_dict(grass.get("background", {})).get("size", {})), 512, 256), "expected full grass background size")
	_assert(_size_is(_dict(_dict(grass.get("entry", {})).get("size", {})), 256, 256), "expected grass entry overlay size")
	_assert(int(_dict(grass.get("palette", {})).get("color_count", 0)) == 48, "expected grass 48-color palette")

	var water := registry.get_battle_environment_record("water")
	_assert(String(water.get("symbol", "")) == "BATTLE_ENVIRONMENT_WATER", "expected water battle environment")
	_assert(String(_dict(water.get("source_assets", {})).get("background_asset", "")) == "Water", "expected water background asset")
	_assert(_asset_exists(_dict(water.get("background", {}))), "expected water background PNG")

	var leader := registry.get_battle_environment_record("leader")
	_assert(String(leader.get("symbol", "")) == "BATTLE_ENVIRONMENT_LEADER", "expected leader battle environment")
	_assert(String(_dict(leader.get("source_assets", {})).get("background_asset", "")) == "Building", "expected leader building background")
	_assert(String(_dict(leader.get("source_assets", {})).get("palette_symbol", "")) == "gBattleEnvironmentPalette_BuildingLeader", "expected leader palette")
	_assert(_asset_exists(_dict(leader.get("background", {}))), "expected leader background PNG")

	var gym_from_scene := registry.get_battle_environment_record_for_map_scene("gym")
	_assert(String(gym_from_scene.get("symbol", "")) == "BATTLE_ENVIRONMENT_GYM", "expected gym map scene environment")
	var frontier_from_scene := registry.get_battle_environment_record_for_map_scene("MAP_BATTLE_SCENE_FRONTIER")
	_assert(String(frontier_from_scene.get("symbol", "")) == "BATTLE_ENVIRONMENT_FRONTIER", "expected frontier map scene environment")

	var soaring := registry.get_battle_environment_record("soaring")
	_assert(String(soaring.get("symbol", "")) == "BATTLE_ENVIRONMENT_SOARING", "expected soaring battle environment")
	_assert(_coverage_status(soaring, "asset_status") == "unsupported", "expected soaring asset unsupported")
	_assert(_array(soaring.get("unsupported", [])).has("battle_environment_asset_pending"), "expected soaring asset pending code")
	_assert(_array(soaring.get("unsupported", [])).has("battle_environment_runtime_pending"), "expected soaring runtime pending code")

	var render_notes := _dict(data.get("rendering_notes", {}))
	var viewport := _dict(render_notes.get("visible_viewport", {}))
	_assert(_size_is(viewport, 240, 160), "expected GBA visible battle viewport metadata")
	_assert(String(render_notes.get("audio_status", "")) == "metadata_only", "expected audio metadata-only note")

	if _failed:
		return

	print(JSON.stringify({
		"data_registry_battle_environments_smoke": "ok",
		"environment_count": int(stats.get("environment_count", 0)),
		"background_texture_count": int(stats.get("background_texture_count", 0)),
		"entry_texture_count": int(stats.get("entry_texture_count", 0)),
	}))
	registry.free()
	quit(0)


func _coverage_status(record: Dictionary, key: String) -> String:
	return String(_dict(record.get("coverage", {})).get(key, ""))


func _asset_exists(asset: Dictionary) -> bool:
	var path := String(asset.get("image", ""))
	return not path.is_empty() and FileAccess.file_exists(path)


func _size_is(size: Dictionary, w: int, h: int) -> bool:
	return int(size.get("w", 0)) == w and int(size.get("h", 0)) == h


func _array(value) -> Array:
	return value if typeof(value) == TYPE_ARRAY else []


func _dict(value) -> Dictionary:
	return value if typeof(value) == TYPE_DICTIONARY else {}


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true
	quit(1)
