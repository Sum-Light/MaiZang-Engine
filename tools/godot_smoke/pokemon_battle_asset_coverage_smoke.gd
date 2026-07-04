extends SceneTree

const REPORT_PATH := "res://data/generated/reports/pokemon_battle_asset_coverage.json"

var _failed := false


func _init() -> void:
	var report := _read_json(REPORT_PATH)
	_assert(String(report.get("generated_by", "")) == "tools/report_pokemon_battle_assets.py", "unexpected Pokemon battle asset report generator")
	_assert(int(report.get("schema_version", 0)) == 1, "unexpected Pokemon battle asset report schema")
	_assert(not _contains_key_recursive(report, "runtime_palette"), "report must not expose a runtime palette API")

	var policy := _dict(report.get("runtime_color_policy", {}))
	var rule := String(policy.get("rule", ""))
	_assert(String(policy.get("status", "")) == "no_runtime_palette", "expected no runtime palette policy")
	_assert(rule.contains("distinct RGBA assets"), "expected distinct RGBA asset rule")
	_assert(rule.contains("Shader/Material/Animation"), "expected Godot-native color effect rule")
	_assert(String(policy.get("audio_status", "")) == "metadata_only", "expected audio metadata-only policy")

	var stats := _dict(report.get("stats", {}))
	_assert(int(stats.get("coverage_row_count", 0)) == 1573, "unexpected Pokemon coverage row count")
	_assert(int(stats.get("species_count", 0)) == 1573, "unexpected Pokemon species count")
	_assert(int(stats.get("normal_front_imported_count", 0)) == 1330, "unexpected normal front import count")
	_assert(int(stats.get("normal_back_imported_count", 0)) == 1330, "unexpected normal back import count")
	_assert(int(stats.get("normal_icon_imported_count", 0)) == 1328, "unexpected normal icon import count")
	_assert(int(stats.get("normal_pair_first_pass_count", 0)) == 1330, "unexpected normal first-pass pair count")
	_assert(int(stats.get("female_front_imported_count", 0)) == 96, "unexpected female front import count")
	_assert(int(stats.get("female_back_imported_count", 0)) == 86, "unexpected female back import count")
	_assert(int(stats.get("female_icon_imported_count", 0)) == 10, "unexpected female icon import count")
	_assert(int(stats.get("female_variant_first_pass_count", 0)) == 100, "unexpected female variant first-pass count")
	_assert(int(stats.get("source_color_normal_metadata_only_count", 0)) == 1329, "unexpected normal source color count")
	_assert(int(stats.get("source_color_shiny_metadata_only_count", 0)) == 1329, "unexpected shiny source color count")
	_assert(int(stats.get("source_color_female_normal_metadata_only_count", 0)) == 6, "unexpected female normal source color count")
	_assert(int(stats.get("source_color_female_shiny_metadata_only_count", 0)) == 6, "unexpected female shiny source color count")
	_assert(int(stats.get("shiny_front_pending_distinct_asset_count", 0)) == 1329, "unexpected shiny front distinct-asset gap count")
	_assert(int(stats.get("shiny_back_pending_distinct_asset_count", 0)) == 1329, "unexpected shiny back distinct-asset gap count")
	_assert(int(stats.get("female_shiny_front_pending_distinct_asset_count", 0)) == 3, "unexpected female shiny front distinct-asset gap count")
	_assert(int(stats.get("female_shiny_back_pending_distinct_asset_count", 0)) == 3, "unexpected female shiny back distinct-asset gap count")
	_assert(int(stats.get("pending_distinct_color_variant_count", 0)) == 2664, "unexpected pending distinct color variant count")
	_assert(int(stats.get("rows_with_pending_distinct_color_variants", 0)) == 1329, "unexpected rows-with-variant-gaps count")
	_assert(int(stats.get("front_animation_metadata_count", 0)) == 1328, "unexpected front animation metadata count")
	_assert(int(stats.get("cry_metadata_only_count", 0)) == 1330, "unexpected cry metadata-only count")

	var rows := _array(report.get("coverage_rows", []))
	_assert(rows.size() == 1573, "unexpected Pokemon coverage row array size")
	_check_row_shapes(rows)
	_check_fixture_rows(rows)

	var unsupported_registry := _array(report.get("unsupported_code_registry", []))
	for code in [
		"pokemon_distinct_shiny_asset_pending",
		"pokemon_distinct_female_shiny_asset_pending",
		"battle_audio_playback_pending",
		"battle_animation_runtime_pending",
	]:
		_assert(_registry_has_code(unsupported_registry, code), "expected unsupported registry code %s" % code)

	if _failed:
		return

	print(JSON.stringify({
		"pokemon_battle_asset_coverage_smoke": "ok",
		"coverage_rows": int(stats.get("coverage_row_count", 0)),
		"normal_pair_first_pass_count": int(stats.get("normal_pair_first_pass_count", 0)),
		"pending_distinct_color_variant_count": int(stats.get("pending_distinct_color_variant_count", 0)),
		"rows_with_pending_distinct_color_variants": int(stats.get("rows_with_pending_distinct_color_variants", 0)),
	}))
	quit(0)


func _check_row_shapes(rows: Array) -> void:
	for value in rows:
		var row := _dict(value)
		for key in ["species_data", "normal_assets", "female_assets", "distinct_color_variant_assets", "source_color_provenance", "animation", "placement", "cry", "unsupported"]:
			_assert(row.has(key), "Pokemon coverage row missing %s" % key)
		if String(_dict(row.get("cry", {})).get("source_symbol", "")) != "":
			_assert(String(_dict(row.get("cry", {})).get("audio_status", "")) == "metadata_only", "Pokemon cry playback must remain metadata-only")


func _check_fixture_rows(rows: Array) -> void:
	var torchic := _find_row(rows, "SPECIES_TORCHIC")
	_assert(not torchic.is_empty(), "expected Torchic coverage row")
	_assert(String(torchic.get("asset_status", "")) == "first_pass_with_variant_gaps", "expected Torchic first pass with shiny gaps")
	_assert(_asset_status(torchic, "normal_assets", "front") == "imported", "expected Torchic front import")
	_assert(_asset_status(torchic, "normal_assets", "back") == "imported", "expected Torchic back import")
	_assert(_asset_status(torchic, "normal_assets", "icon") == "imported", "expected Torchic icon import")
	_assert(_source_color_status(torchic, "normal") == "metadata_only", "expected Torchic normal source color")
	_assert(_source_color_status(torchic, "shiny") == "metadata_only", "expected Torchic shiny source color")
	_assert(_variant_status(torchic, "shiny", "front") == "pending_distinct_asset", "expected Torchic shiny front distinct image gap")
	_assert(_variant_status(torchic, "shiny", "back") == "pending_distinct_asset", "expected Torchic shiny back distinct image gap")
	_assert(String(_dict(torchic.get("animation", {})).get("runtime_status", "")) == "unsupported", "expected Torchic animation runtime pending")
	_assert(String(_dict(torchic.get("cry", {})).get("audio_status", "")) == "metadata_only", "expected Torchic cry metadata-only")
	_assert(_unsupported_has(torchic, "pokemon_distinct_shiny_asset_pending"), "expected Torchic shiny unsupported code")

	var pikachu := _find_row(rows, "SPECIES_PIKACHU")
	_assert(not pikachu.is_empty(), "expected Pikachu coverage row")
	_assert(String(_dict(pikachu.get("female_assets", {})).get("variant_status", "")) == "first_pass", "expected Pikachu female asset coverage")
	_assert(_asset_status(pikachu, "female_assets", "front") == "imported", "expected Pikachu female front import")
	_assert(_asset_status(pikachu, "female_assets", "back") == "imported", "expected Pikachu female back import")
	_assert(_asset_status(pikachu, "female_assets", "icon") == "imported", "expected Pikachu female icon import")
	_assert(String(_dict(pikachu.get("species_data", {})).get("form_change_table", "")) == "sPikachuFormChangeTable", "expected Pikachu form-change table")

	var unfezant := _find_row(rows, "SPECIES_UNFEZANT")
	_assert(not unfezant.is_empty(), "expected Unfezant coverage row")
	_assert(_source_color_status(unfezant, "female_shiny") == "metadata_only", "expected Unfezant female shiny source color")
	_assert(_variant_status(unfezant, "female_shiny", "front") == "pending_distinct_asset", "expected Unfezant female shiny front gap")
	_assert(_variant_status(unfezant, "female_shiny", "back") == "pending_distinct_asset", "expected Unfezant female shiny back gap")
	_assert(_unsupported_has(unfezant, "pokemon_distinct_female_shiny_asset_pending"), "expected Unfezant female shiny unsupported code")

	var unown := _find_row(rows, "SPECIES_UNOWN")
	_assert(not unown.is_empty(), "expected Unown coverage row")
	_assert(String(unown.get("asset_status", "")) == "unsupported", "expected Unown unsupported asset status")
	_assert(_asset_status(unown, "normal_assets", "front") == "missing_source_reference", "expected Unown missing front source")
	_assert(_asset_status(unown, "normal_assets", "back") == "missing_source_reference", "expected Unown missing back source")
	_assert(_unsupported_has(unown, "pokemon_asset_import_pending"), "expected Unown asset import pending code")
	_assert(_unsupported_has(unown, "pokemon_normal_battle_sprite_pending"), "expected Unown normal sprite pending code")

	var geodude := _find_row(rows, "SPECIES_GEODUDE")
	_assert(not geodude.is_empty(), "expected Geodude coverage row")
	_assert(String(_dict(geodude.get("placement", {})).get("status", "")) == "metadata_only", "expected Geodude placement metadata")
	_assert(String(_dict(geodude.get("placement", {})).get("shadow_status", "")) == "metadata_only", "expected Geodude shadow metadata")

	var castform := _find_row(rows, "SPECIES_CASTFORM_NORMAL")
	_assert(not castform.is_empty(), "expected Castform coverage row")
	_assert(String(_dict(castform.get("species_data", {})).get("form_species_table", "")) == "sCastformFormSpeciesIdTable", "expected Castform form species table")
	_assert(String(_dict(castform.get("species_data", {})).get("form_change_table", "")) == "sCastformFormChangeTable", "expected Castform form change table")

	var mega_venusaur := _find_row(rows, "SPECIES_VENUSAUR_MEGA")
	_assert(not mega_venusaur.is_empty(), "expected Mega Venusaur coverage row")
	_assert(String(_dict(mega_venusaur.get("species_data", {})).get("form_species_table", "")) == "sVenusaurFormSpeciesIdTable", "expected Mega Venusaur form species table")
	_assert(_asset_status(mega_venusaur, "normal_assets", "icon") == "imported", "expected Mega Venusaur battle UI icon")


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		_assert(false, "missing JSON file %s" % path)
		return {}
	var text := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		_assert(false, "expected JSON dictionary at %s" % path)
		return {}
	return parsed


func _find_row(rows: Array, row_id: String) -> Dictionary:
	for row in rows:
		if typeof(row) == TYPE_DICTIONARY and String(row.get("id", "")) == row_id:
			return row
	return {}


func _asset_status(row: Dictionary, group_key: String, asset_key: String) -> String:
	return String(_dict(_dict(row.get(group_key, {})).get(asset_key, {})).get("status", ""))


func _source_color_status(row: Dictionary, color_key: String) -> String:
	return String(_dict(_dict(row.get("source_color_provenance", {})).get(color_key, {})).get("status", ""))


func _variant_status(row: Dictionary, variant_key: String, asset_key: String) -> String:
	var variants := _dict(row.get("distinct_color_variant_assets", {}))
	return String(_dict(_dict(variants.get(variant_key, {})).get(asset_key, {})).get("status", ""))


func _unsupported_has(row: Dictionary, code: String) -> bool:
	return _array(row.get("unsupported", [])).has(code)


func _registry_has_code(rows: Array, code: String) -> bool:
	for row in rows:
		if typeof(row) == TYPE_DICTIONARY and String(row.get("code", "")) == code:
			return true
	return false


func _contains_key_recursive(value, key_name: String) -> bool:
	if typeof(value) == TYPE_DICTIONARY:
		if value.has(key_name):
			return true
		for key in value.keys():
			if _contains_key_recursive(value[key], key_name):
				return true
	elif typeof(value) == TYPE_ARRAY:
		for item in value:
			if _contains_key_recursive(item, key_name):
				return true
	return false


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
