extends SceneTree

const DATA_REGISTRY_SCRIPT := preload("res://scripts/autoload/data_registry.gd")

const ALPHA_NONBLANK := "nonblank"
const ALPHA_OPAQUE := "opaque"
const ALPHA_TRANSPARENT := "transparent"

var _failed := false
var _image_load_count := 0
var _metadata_image_ref_count := 0
var _source_color_provenance_count := 0
var _tilemap_composite_count := 0


func _init() -> void:
	var registry = DATA_REGISTRY_SCRIPT.new()
	registry._ready()

	var pokemon_data := registry.get_pokemon_battle_sprites_data()
	var trainer_data := registry.get_trainer_sprites_data()
	var environment_data := registry.get_battle_environments_data()
	var transition_data := registry.get_battle_transitions_data()

	_check_pokemon_assets(pokemon_data)
	_check_trainer_assets(trainer_data)
	_check_environment_assets(environment_data)
	_check_transition_assets(transition_data)

	if _failed:
		return

	print(JSON.stringify({
		"battle_asset_image_quality_smoke": "ok",
		"image_load_count": _image_load_count,
		"metadata_image_ref_count": _metadata_image_ref_count,
		"source_color_provenance_count": _source_color_provenance_count,
		"tilemap_composite_count": _tilemap_composite_count,
	}))
	registry.free()
	quit(0)


func _check_pokemon_assets(data: Dictionary) -> void:
	var stats := _dict(data.get("stats", {}))
	_assert(int(stats.get("front_textures_imported", 0)) == 1330, "unexpected Pokemon front texture count")
	_assert(int(stats.get("back_textures_imported", 0)) == 1330, "unexpected Pokemon back texture count")
	_assert(int(stats.get("icon_textures_imported", 0)) == 1328, "unexpected Pokemon icon texture count")
	_assert(int(stats.get("female_front_textures_imported", 0)) == 96, "unexpected Pokemon female front texture count")
	_assert(int(stats.get("female_back_textures_imported", 0)) == 86, "unexpected Pokemon female back texture count")
	_assert(int(stats.get("female_icon_textures_imported", 0)) == 10, "unexpected Pokemon female icon texture count")
	_assert(int(stats.get("missing_palette_asset_count", -1)) == 0, "expected Pokemon source color provenance to resolve")
	_assert(int(stats.get("missing_image_asset_count", -1)) == 3, "unexpected Pokemon missing image report count")

	var sprites := _dict(data.get("sprites", {}))
	var pokemon_image_refs := 0
	for species_symbol in _array(data.get("sprite_order", [])):
		var record := _dict(sprites.get(species_symbol, {}))
		for asset_key in ["front", "back", "icon"]:
			if _check_sprite_metadata(_dict(record.get(asset_key, {})), "%s.%s" % [species_symbol, asset_key], asset_key != "icon"):
				pokemon_image_refs += 1
		var female := _dict(record.get("female", {}))
		for asset_key in ["front", "back", "icon"]:
			if _check_sprite_metadata(_dict(female.get(asset_key, {})), "%s.female_%s" % [species_symbol, asset_key], asset_key != "icon"):
				pokemon_image_refs += 1

	_assert(pokemon_image_refs == 4180, "unexpected Pokemon imported image metadata count")
	_metadata_image_ref_count += pokemon_image_refs

	for species_symbol in ["SPECIES_TORCHIC", "SPECIES_GEODUDE", "SPECIES_PIKACHU"]:
		var record := _dict(sprites.get(species_symbol, {}))
		_assert(_pokemon_source_color_count(record, "normal") == 16, "expected normal source colors for %s" % species_symbol)
		_assert(_pokemon_source_color_count(record, "shiny") == 16, "expected shiny source colors for %s" % species_symbol)
		_source_color_provenance_count += 2

	var torchic := _dict(sprites.get("SPECIES_TORCHIC", {}))
	_check_image_asset(_dict(torchic.get("front", {})), "Torchic front", ALPHA_TRANSPARENT)
	_check_image_asset(_dict(torchic.get("back", {})), "Torchic back", ALPHA_TRANSPARENT)
	_check_image_asset(_dict(torchic.get("icon", {})), "Torchic icon", ALPHA_TRANSPARENT)

	var pikachu_female := _dict(_dict(sprites.get("SPECIES_PIKACHU", {})).get("female", {}))
	_check_image_asset(_dict(pikachu_female.get("front", {})), "Pikachu female front", ALPHA_TRANSPARENT)
	_check_image_asset(_dict(pikachu_female.get("back", {})), "Pikachu female back", ALPHA_TRANSPARENT)
	_check_image_asset(_dict(pikachu_female.get("icon", {})), "Pikachu female icon", ALPHA_TRANSPARENT)


func _check_trainer_assets(data: Dictionary) -> void:
	var stats := _dict(data.get("stats", {}))
	_assert(int(stats.get("front_textures_imported", 0)) == 155, "unexpected trainer front texture count")
	_assert(int(stats.get("back_textures_imported", 0)) == 10, "unexpected trainer back texture count")
	_assert(int(stats.get("front_palette_metadata_count", 0)) == 155, "unexpected trainer front source color count")
	_assert(int(stats.get("back_palette_metadata_count", 0)) == 10, "unexpected trainer back source color count")
	_assert(int(stats.get("trainer_records_missing_sprite", -1)) == 0, "expected no trainer sprite gaps")

	var trainer_image_refs := 0
	for pic_symbol in _array(data.get("front_sprite_order", [])):
		var record := _dict(_dict(data.get("front_sprites", {})).get(pic_symbol, {}))
		if _check_sprite_metadata(_dict(record.get("front", {})), "%s.front" % pic_symbol, false):
			trainer_image_refs += 1
		_assert(_source_color_count(_dict(record.get("palette", {}))) == 16, "expected trainer front source colors for %s" % pic_symbol)
		_source_color_provenance_count += 1
	for pic_symbol in _array(data.get("back_sprite_order", [])):
		var record := _dict(_dict(data.get("back_sprites", {})).get(pic_symbol, {}))
		if _check_sprite_metadata(_dict(record.get("back", {})), "%s.back" % pic_symbol, false):
			trainer_image_refs += 1
		_assert(_source_color_count(_dict(record.get("palette", {}))) == 16, "expected trainer back source colors for %s" % pic_symbol)
		_source_color_provenance_count += 1

	_assert(trainer_image_refs == 165, "unexpected trainer imported image metadata count")
	_metadata_image_ref_count += trainer_image_refs

	var hiker := _dict(_dict(data.get("front_sprites", {})).get("TRAINER_PIC_FRONT_HIKER", {}))
	_check_image_asset(_dict(hiker.get("front", {})), "Hiker trainer front", ALPHA_TRANSPARENT)
	var brendan := _dict(_dict(data.get("back_sprites", {})).get("TRAINER_PIC_BACK_BRENDAN", {}))
	_check_image_asset(_dict(brendan.get("back", {})), "Brendan trainer back", ALPHA_TRANSPARENT)


func _check_environment_assets(data: Dictionary) -> void:
	var stats := _dict(data.get("stats", {}))
	_assert(int(stats.get("background_texture_count", 0)) == 23, "unexpected battle environment background count")
	_assert(int(stats.get("entry_texture_count", 0)) == 23, "unexpected battle environment entry count")
	_assert(int(stats.get("palette_metadata_count", 0)) == 23, "unexpected battle environment source color count")
	_assert(int(stats.get("warning_count", -1)) == 0, "expected no battle environment asset warnings")

	var environment_image_refs := 0
	var environments := _dict(data.get("environments", {}))
	for environment_symbol in _array(data.get("environment_order", [])):
		var record := _dict(environments.get(environment_symbol, {}))
		var coverage := _dict(record.get("coverage", {}))
		if String(coverage.get("asset_status", "")) != "first_pass":
			continue
		var background := _dict(record.get("background", {}))
		var entry := _dict(record.get("entry", {}))
		_check_asset_metadata(background, "%s.background" % environment_symbol)
		_check_asset_metadata(entry, "%s.entry" % environment_symbol)
		_assert(bool(background.get("transparent_zero", true)) == false, "expected opaque battle background conversion for %s" % environment_symbol)
		_assert(bool(entry.get("transparent_zero", false)) == true, "expected entry overlay alpha conversion for %s" % environment_symbol)
		_assert(_source_color_count(_dict(record.get("palette", {}))) > 0, "expected battle environment source colors for %s" % environment_symbol)
		environment_image_refs += 2
		_source_color_provenance_count += 1

	_assert(environment_image_refs == 46, "unexpected battle environment imported image metadata count")
	_metadata_image_ref_count += environment_image_refs

	var grass := _dict(environments.get("BATTLE_ENVIRONMENT_GRASS", {}))
	_check_image_asset(_dict(grass.get("background", {})), "grass battle background", ALPHA_OPAQUE)
	_check_image_asset(_dict(grass.get("entry", {})), "grass battle entry", ALPHA_TRANSPARENT)


func _check_transition_assets(data: Dictionary) -> void:
	var stats := _dict(data.get("stats", {}))
	_assert(int(stats.get("texture_count", 0)) == 23, "unexpected battle transition texture count")
	_assert(int(stats.get("source_palette_asset_count", 0)) == 19, "unexpected battle transition source color count")
	_assert(int(stats.get("tilemap_composite_count", 0)) == 14, "unexpected battle transition composite count")
	_assert(int(stats.get("missing_asset_ref_count", -1)) == 0, "expected no battle transition missing asset refs")
	_assert(int(stats.get("tilemap_composite_missing_tile_count", -1)) == 0, "expected no battle transition missing composite tiles")

	var assets := _dict(data.get("assets", {}))
	var transition_image_refs := 0
	for asset_id in _array(data.get("asset_order", [])):
		var asset := _dict(assets.get(asset_id, {}))
		var kind := String(asset.get("kind", ""))
		if kind == "texture":
			_check_asset_metadata(asset, asset_id)
			if int(asset.get("source_palette_color_count", 0)) > 0:
				_assert(bool(asset.get("transparent_zero", false)), "expected transition texture alpha conversion for %s" % asset_id)
				_source_color_provenance_count += 1
			transition_image_refs += 1
		elif kind == "palette":
			_assert(_source_color_count(asset) > 0, "expected transition source color provenance for %s" % asset_id)
			_source_color_provenance_count += 1
		var composite := _dict(asset.get("tilemap_composite", {}))
		if not composite.is_empty():
			_check_asset_metadata(composite, "%s.tilemap_composite" % asset_id)
			var tilemap := _dict(composite.get("tilemap", {}))
			_assert(int(tilemap.get("missing_tile_count", -1)) == 0, "expected no missing tiles in transition composite %s" % asset_id)
			_assert(bool(tilemap.get("entry_count_mismatch", true)) == false, "expected matching tilemap entry count for %s" % asset_id)
			transition_image_refs += 1
			_tilemap_composite_count += 1

	_assert(transition_image_refs == 37, "unexpected battle transition imported image metadata count")
	_metadata_image_ref_count += transition_image_refs

	var transitions := _dict(data.get("transitions", {}))
	for transition_symbol in _array(data.get("transition_order", [])):
		var record := _dict(transitions.get(transition_symbol, {}))
		_assert(_array(record.get("missing_asset_refs", [])).is_empty(), "expected no missing transition refs for %s" % transition_symbol)
		for ref_key in ["texture_refs", "palette_refs", "binary_refs", "tilemap_composite_refs"]:
			for asset_ref in _array(record.get(ref_key, [])):
				_assert(assets.has(asset_ref), "expected transition asset ref %s from %s" % [asset_ref, transition_symbol])

	_check_image_asset(_dict(assets.get("graphics/battle_transitions/big_pokeball.png", {})), "Big Pokeball transition texture", ALPHA_TRANSPARENT)
	_assert(int(_dict(assets.get("graphics/battle_transitions/big_pokeball.png", {})).get("source_palette_color_count", 0)) == 16, "expected Big Pokeball transition source color conversion metadata")
	_check_image_asset(_dict(assets.get("graphics/battle_transitions/team_aqua.png", {})), "Aqua transition texture", ALPHA_TRANSPARENT)
	_assert(int(_dict(assets.get("graphics/battle_transitions/team_aqua.png", {})).get("source_palette_color_count", 0)) == 16, "expected Aqua transition source color conversion metadata")
	_check_image_asset(_dict(_dict(assets.get("graphics/battle_transitions/big_pokeball_map.bin", {})).get("tilemap_composite", {})), "Big Pokeball transition composite", ALPHA_OPAQUE)
	_check_image_asset(_dict(_dict(assets.get("graphics/battle_transitions/frontier_squares.bin", {})).get("tilemap_composite", {})), "Frontier Squares dynamic block preview", ALPHA_NONBLANK)


func _check_sprite_metadata(asset: Dictionary, label: String, has_frame_size: bool) -> bool:
	if String(asset.get("status", "")) != "imported":
		return false
	_check_asset_metadata(asset, label)
	var transparency := _dict(asset.get("transparency", {}))
	_assert(int(transparency.get("source_palette_index", -1)) == 0, "expected source index 0 alpha metadata for %s" % label)
	if has_frame_size:
		var frame_size := _dict(asset.get("frame_size", {}))
		var image_size := _size_dict(asset)
		_assert(int(frame_size.get("w", 0)) > 0 and int(frame_size.get("h", 0)) > 0, "expected frame size metadata for %s" % label)
		_assert(int(frame_size.get("w", 0)) <= int(image_size.get("w", 0)), "expected frame width inside image for %s" % label)
		_assert(int(frame_size.get("h", 0)) <= int(image_size.get("h", 0)), "expected frame height inside image for %s" % label)
	return true


func _check_asset_metadata(asset: Dictionary, label: String) -> void:
	var path := String(asset.get("image", ""))
	_assert(not path.is_empty(), "expected image path for %s" % label)
	_assert(FileAccess.file_exists(path), "expected image file for %s at %s" % [label, path])
	var size := _size_dict(asset)
	_assert(int(size.get("w", 0)) > 0 and int(size.get("h", 0)) > 0, "expected image dimensions for %s" % label)


func _check_image_asset(asset: Dictionary, label: String, alpha_policy: String) -> void:
	_check_asset_metadata(asset, label)
	var path := String(asset.get("image", ""))
	var image := Image.new()
	var load_error := image.load(path)
	_assert(load_error == OK, "expected image to load for %s at %s" % [label, path])
	if load_error != OK:
		return
	_image_load_count += 1
	var size := _size_dict(asset)
	_assert(image.get_width() == int(size.get("w", 0)), "expected image width to match metadata for %s" % label)
	_assert(image.get_height() == int(size.get("h", 0)), "expected image height to match metadata for %s" % label)
	var alpha := _alpha_summary(image)
	_assert(bool(alpha.get("has_opaque", false)), "expected visible pixels for %s" % label)
	if alpha_policy == ALPHA_TRANSPARENT:
		_assert(bool(alpha.get("has_transparent", false)), "expected transparent pixels for %s" % label)
	elif alpha_policy == ALPHA_OPAQUE:
		_assert(not bool(alpha.get("has_transparent", false)), "expected fully opaque pixels for %s" % label)


func _alpha_summary(image: Image) -> Dictionary:
	var has_opaque := false
	var has_transparent := false
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var alpha := image.get_pixel(x, y).a
			if alpha <= 0.01:
				has_transparent = true
			elif alpha >= 0.99:
				has_opaque = true
			else:
				has_opaque = true
				has_transparent = true
			if has_opaque and has_transparent:
				return {"has_opaque": true, "has_transparent": true}
	return {"has_opaque": has_opaque, "has_transparent": has_transparent}


func _pokemon_source_color_count(record: Dictionary, source_key: String) -> int:
	return _source_color_count(_dict(_dict(record.get("palettes", {})).get(source_key, {})))


func _source_color_count(source_color_record: Dictionary) -> int:
	var value = source_color_record.get("color_count", 0)
	if value == null:
		return 0
	return int(value)


func _size_dict(asset: Dictionary) -> Dictionary:
	var image_size := _dict(asset.get("image_size", {}))
	if not image_size.is_empty():
		return image_size
	return _dict(asset.get("size", {}))


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
