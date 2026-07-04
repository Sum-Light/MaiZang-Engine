extends SceneTree

const DATA_REGISTRY_SCRIPT := preload("res://scripts/autoload/data_registry.gd")

var _failed := false


func _init() -> void:
	var registry = DATA_REGISTRY_SCRIPT.new()
	registry._ready()

	var data := registry.get_pokemon_battle_sprites_data()
	var stats := _dict(data.get("stats", {}))
	_assert(typeof(data) == TYPE_DICTIONARY and not data.is_empty(), "expected Pokemon battle sprite data")
	_assert(int(stats.get("species_count", 0)) == 1573, "unexpected battle sprite species count")
	_assert(int(stats.get("front_textures_imported", 0)) == 1330, "unexpected front texture count")
	_assert(int(stats.get("back_textures_imported", 0)) == 1330, "unexpected back texture count")
	_assert(int(stats.get("icon_textures_imported", 0)) == 1328, "unexpected icon texture count")
	_assert(int(stats.get("first_pass_asset_records", 0)) == 1330, "unexpected first-pass asset record count")
	_assert(int(stats.get("macro_initializer_count", 0)) == 207, "unexpected macro initializer count")
	_assert(int(stats.get("missing_palette_asset_count", -1)) == 0, "expected all referenced palettes to parse")

	var torchic := registry.get_pokemon_battle_sprite_record("SPECIES_TORCHIC")
	var torchic_by_id := registry.get_pokemon_battle_sprite_record(255)
	_assert(String(torchic.get("species_symbol", "")) == "SPECIES_TORCHIC", "expected Torchic sprite record")
	_assert(String(torchic_by_id.get("species_symbol", "")) == "SPECIES_TORCHIC", "expected Torchic id lookup")
	_assert(_coverage_status(torchic, "asset_status") == "first_pass", "expected Torchic first-pass sprites")
	_assert(_asset_source(torchic, "front") == "gMonFrontPic_Torchic", "expected Torchic front symbol")
	_assert(_asset_source(torchic, "back") == "gMonBackPic_Torchic", "expected Torchic back symbol")
	_assert(_asset_exists(_dict(torchic.get("front", {}))), "expected Torchic front PNG")
	_assert(_asset_exists(_dict(torchic.get("back", {}))), "expected Torchic back PNG")
	_assert(_asset_exists(_dict(torchic.get("icon", {}))), "expected Torchic icon PNG")
	_assert(_palette_color_count(torchic, "normal") == 16, "expected Torchic normal palette")
	_assert(_palette_color_count(torchic, "shiny") == 16, "expected Torchic shiny palette")
	_assert(String(_dict(torchic.get("animation", {})).get("front_anim_id", "")) == "ANIM_V_JUMPS_SMALL", "expected modern Torchic anim id")
	_assert(_array(_dict(torchic.get("animation", {})).get("front_frames", [])).size() == 7, "expected Torchic front anim frames")
	_assert(int(_dict(torchic.get("placement", {})).get("front_pic_y_offset", -1)) == 12, "expected Torchic front y offset")
	_assert(String(_dict(torchic.get("cry", {})).get("audio_status", "")) == "metadata_only", "expected Torchic cry metadata-only")

	for species_symbol in ["SPECIES_TREECKO", "SPECIES_MUDKIP", "SPECIES_GEODUDE"]:
		var record := registry.get_pokemon_battle_sprite_record(species_symbol)
		_assert(_coverage_status(record, "asset_status") == "first_pass", "expected first-pass sprites for %s" % species_symbol)
		_assert(_asset_exists(_dict(record.get("front", {}))), "expected front PNG for %s" % species_symbol)
		_assert(_asset_exists(_dict(record.get("back", {}))), "expected back PNG for %s" % species_symbol)

	var pikachu := registry.get_pokemon_battle_sprite_record("pikachu")
	var female := _dict(pikachu.get("female", {}))
	_assert(String(_dict(female.get("front", {})).get("source_symbol", "")) == "gMonFrontPic_PikachuF", "expected Pikachu female front symbol")
	_assert(String(_dict(female.get("back", {})).get("source_symbol", "")) == "gMonBackPic_PikachuF", "expected Pikachu female back symbol")
	_assert(String(_dict(female.get("icon", {})).get("source_symbol", "")) == "gMonIcon_PikachuF", "expected Pikachu female icon symbol")
	_assert(_asset_exists(_dict(female.get("front", {}))), "expected Pikachu female front PNG")
	_assert(_asset_exists(_dict(female.get("back", {}))), "expected Pikachu female back PNG")
	_assert(_asset_exists(_dict(female.get("icon", {}))), "expected Pikachu female icon PNG")

	var cosplay := registry.get_pokemon_battle_sprite_record("SPECIES_PIKACHU_COSPLAY")
	var cosplay_palettes := _dict(cosplay.get("palettes", {}))
	var cosplay_normal_palette := _dict(cosplay_palettes.get("normal", {}))
	_assert(_coverage_status(cosplay, "asset_status") == "first_pass", "expected Pikachu Cosplay first-pass sprites")
	_assert(String(_dict(cosplay.get("front", {})).get("source_image_path", "")).contains("pikachu/cosplay/front.png"), "expected form source front path")
	_assert(String(cosplay_normal_palette.get("source_palette_path", "")).contains("pikachu/cosplay/normal.pal"), "expected form source palette path")

	var unown := registry.get_pokemon_battle_sprite_record("SPECIES_UNOWN")
	_assert(String(unown.get("initializer_kind", "")) == "macro_call", "expected Unown macro record")
	_assert(_coverage_status(unown, "asset_status") == "unsupported", "expected Unown asset gap")
	_assert(_array(unown.get("unsupported", [])).has("pokemon_asset_import_pending"), "expected Unown unsupported asset code")

	if _failed:
		return

	print(JSON.stringify({
		"data_registry_pokemon_battle_sprites_smoke": "ok",
		"species_count": int(stats.get("species_count", 0)),
		"front_textures_imported": int(stats.get("front_textures_imported", 0)),
		"first_pass_asset_records": int(stats.get("first_pass_asset_records", 0)),
	}))
	registry.free()
	quit(0)


func _coverage_status(record: Dictionary, key: String) -> String:
	return String(_dict(record.get("coverage", {})).get(key, ""))


func _asset_source(record: Dictionary, key: String) -> String:
	return String(_dict(record.get(key, {})).get("source_symbol", ""))


func _asset_exists(asset: Dictionary) -> bool:
	var path := String(asset.get("image", ""))
	return not path.is_empty() and FileAccess.file_exists(path)


func _palette_color_count(record: Dictionary, palette_key: String) -> int:
	var palettes := _dict(record.get("palettes", {}))
	var palette := _dict(palettes.get(palette_key, {}))
	return int(palette.get("color_count", 0))


func _dict(value) -> Dictionary:
	return value if typeof(value) == TYPE_DICTIONARY else {}


func _array(value) -> Array:
	return value if typeof(value) == TYPE_ARRAY else []


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true
	quit(1)
