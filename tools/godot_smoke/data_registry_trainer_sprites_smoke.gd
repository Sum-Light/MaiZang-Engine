extends SceneTree

const DATA_REGISTRY_SCRIPT := preload("res://scripts/autoload/data_registry.gd")

var _failed := false


func _init() -> void:
	var registry = DATA_REGISTRY_SCRIPT.new()
	registry._ready()

	var data := registry.get_trainer_sprites_data()
	var stats := _dict(data.get("stats", {}))
	_assert(typeof(data) == TYPE_DICTIONARY and not data.is_empty(), "expected trainer sprite data")
	_assert(int(stats.get("trainer_count", 0)) == 855, "unexpected trainer sprite trainer count")
	_assert(int(stats.get("front_sprite_count", 0)) == 155, "unexpected front trainer sprite count")
	_assert(int(stats.get("front_textures_imported", 0)) == 155, "unexpected front trainer texture count")
	_assert(int(stats.get("front_palette_metadata_count", 0)) == 155, "unexpected front trainer palette count")
	_assert(int(stats.get("back_sprite_count", 0)) == 10, "unexpected back trainer sprite count")
	_assert(int(stats.get("back_textures_imported", 0)) == 10, "unexpected back trainer texture count")
	_assert(int(stats.get("first_pass_asset_trainer_count", 0)) == 855, "unexpected trainer first-pass asset count")
	_assert(int(stats.get("trainer_records_missing_sprite", -1)) == 0, "expected every generated trainer to resolve a sprite")
	_assert(int(stats.get("mugshot_trainer_count", 0)) == 5, "unexpected mugshot trainer count")

	var sawyer := registry.get_trainer_sprite_record("sawyer_1")
	var sawyer_by_id := registry.get_trainer_sprite_record(1)
	_assert(String(sawyer.get("trainer_symbol", "")) == "TRAINER_SAWYER_1", "expected Sawyer trainer sprite record")
	_assert(String(sawyer_by_id.get("trainer_symbol", "")) == "TRAINER_SAWYER_1", "expected Sawyer trainer sprite id lookup")
	_assert(_coverage_status(sawyer, "asset_status") == "first_pass", "expected Sawyer first-pass trainer sprite")
	_assert(String(_dict(sawyer.get("front", {})).get("source_symbol", "")) == "gTrainerFrontPic_Hiker", "expected Sawyer Hiker front symbol")
	_assert(_asset_exists(_dict(sawyer.get("front", {}))), "expected Sawyer trainer front PNG")
	_assert(_palette_color_count(sawyer) == 16, "expected Sawyer trainer palette metadata")
	_assert(String(_dict(_dict(sawyer.get("mugshot", {})).get("color", {})).get("symbol", "")) == "MUGSHOT_COLOR_NONE", "expected Sawyer no mugshot")

	var hiker := registry.get_trainer_front_sprite_record("hiker")
	var hiker_by_id := registry.get_trainer_front_sprite_record(0)
	_assert(String(hiker.get("pic_symbol", "")) == "TRAINER_PIC_FRONT_HIKER", "expected Hiker front sprite")
	_assert(String(hiker_by_id.get("pic_symbol", "")) == "TRAINER_PIC_FRONT_HIKER", "expected Hiker front sprite id lookup")
	_assert(int(hiker.get("trainer_count", 0)) > 0, "expected Hiker shared trainer refs")
	_assert(_asset_exists(_dict(hiker.get("front", {}))), "expected Hiker front PNG")

	var sidney := registry.get_trainer_sprite_record("sidney")
	_assert(String(sidney.get("trainer_symbol", "")) == "TRAINER_SIDNEY", "expected Sidney trainer sprite record")
	_assert(_coverage_status(sidney, "asset_status") == "first_pass", "expected Sidney first-pass trainer sprite")
	_assert(String(_dict(_dict(sidney.get("mugshot", {})).get("color", {})).get("symbol", "")) == "MUGSHOT_COLOR_PURPLE", "expected Sidney purple mugshot")
	_assert(String(_dict(sidney.get("mugshot", {})).get("transition_status", "")) == "metadata_only", "expected Sidney mugshot transition metadata")
	var sidney_mugshot_palette := _dict(_dict(_dict(sidney.get("mugshot", {})).get("palette_ref", {})).get("palette", {}))
	_assert(int(sidney_mugshot_palette.get("color_count", 0)) > 0, "expected Sidney mugshot palette metadata")
	_assert(_asset_exists(_dict(sidney.get("front", {}))), "expected Sidney front PNG")

	var wallace_front := registry.get_trainer_front_sprite_record("champion_wallace")
	var wallace_mugshot := _dict(wallace_front.get("mugshot", {}))
	var wallace_coords := _dict(wallace_mugshot.get("coords", {}))
	_assert(int(wallace_coords.get("x", 0)) == -8, "expected Wallace mugshot x offset")
	_assert(int(wallace_coords.get("y", 0)) == 7, "expected Wallace mugshot y offset")
	_assert(int(wallace_mugshot.get("rotation_scale", 0)) == 0x188, "expected Wallace mugshot rotation scale")

	var brendan_back := registry.get_trainer_back_sprite_record("brendan")
	_assert(String(brendan_back.get("pic_symbol", "")) == "TRAINER_PIC_BACK_BRENDAN", "expected Brendan back sprite")
	_assert(_asset_exists(_dict(brendan_back.get("back", {}))), "expected Brendan back PNG")
	_assert(int(_dict(brendan_back.get("coordinates", {})).get("y_offset", 0)) == 4, "expected Brendan back y offset")

	if _failed:
		return

	print(JSON.stringify({
		"data_registry_trainer_sprites_smoke": "ok",
		"trainer_count": int(stats.get("trainer_count", 0)),
		"front_sprite_count": int(stats.get("front_sprite_count", 0)),
		"first_pass_asset_trainer_count": int(stats.get("first_pass_asset_trainer_count", 0)),
	}))
	registry.free()
	quit(0)


func _coverage_status(record: Dictionary, key: String) -> String:
	return String(_dict(record.get("coverage", {})).get(key, ""))


func _asset_exists(asset: Dictionary) -> bool:
	var path := String(asset.get("image", ""))
	return not path.is_empty() and FileAccess.file_exists(path)


func _palette_color_count(record: Dictionary) -> int:
	return int(_dict(record.get("palette", {})).get("color_count", 0))


func _dict(value) -> Dictionary:
	return value if typeof(value) == TYPE_DICTIONARY else {}


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true
	quit(1)
