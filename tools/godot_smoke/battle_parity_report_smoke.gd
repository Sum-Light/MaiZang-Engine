extends SceneTree

const REPORT_PATH := "res://data/generated/reports/battle_parity_report.json"
const SOURCE_INDEX_PATH := "res://data/generated/battle/source_index.json"
const EVENT_LOG_SCHEMA_PATH := "res://data/generated/battle/event_log_schema.json"

var _failed := false


func _init() -> void:
	var report := _read_json(REPORT_PATH)
	var source_index := _read_json(SOURCE_INDEX_PATH)
	var event_log_schema := _read_json(EVENT_LOG_SCHEMA_PATH)

	_assert(String(report.get("generated_by", "")) == "tools/report_battle_parity.py", "unexpected report generator")
	_assert(String(source_index.get("generated_by", "")) == "tools/report_battle_parity.py", "unexpected source index generator")
	_assert(String(event_log_schema.get("generated_by", "")) == "tools/report_battle_parity.py", "unexpected event log schema generator")

	var stats := _dict(report.get("stats", {}))
	var row_counts := _dict(stats.get("coverage_row_counts", {}))
	var expected_counts := _dict(stats.get("expected_counts", {}))
	var missing_expected := _dict(stats.get("missing_expected_coverage", {}))
	_assert(missing_expected.is_empty(), "expected no missing battle coverage rows")
	_assert(int(stats.get("total_coverage_rows", 0)) == 8571, "unexpected total battle coverage row count")
	_assert(int(row_counts.get("moves", 0)) == 935, "unexpected move coverage row count")
	_assert(int(row_counts.get("abilities", 0)) == 311, "unexpected ability coverage row count")
	_assert(int(row_counts.get("trainers", 0)) == 855, "unexpected trainer coverage row count")
	_assert(int(row_counts.get("trainer_party_mons", 0)) == 1825, "unexpected trainer party coverage row count")
	_assert(int(row_counts.get("pokemon_data", 0)) == 1573, "unexpected Pokemon data coverage row count")
	_assert(int(row_counts.get("debug_launchers", 0)) == 2, "unexpected debug launcher coverage row count")
	for key in row_counts.keys():
		_assert(int(row_counts.get(key, -1)) == int(expected_counts.get(key, -2)), "coverage mismatch for %s" % key)

	var coverage_rows := _dict(report.get("coverage_rows", {}))
	var moves := _array(coverage_rows.get("moves", []))
	var abilities := _array(coverage_rows.get("abilities", []))
	var trainers := _array(coverage_rows.get("trainers", []))
	var pokemon_data := _array(coverage_rows.get("pokemon_data", []))
	var debug_launchers := _array(coverage_rows.get("debug_launchers", []))
	for section_name in coverage_rows.keys():
		for row in _array(coverage_rows.get(section_name, [])):
			_assert(_supported_row_has_tests(_dict(row)), "supported row in %s is missing tests" % section_name)
	_assert(not _find_row(moves, "MOVE_TACKLE").is_empty(), "expected MOVE_TACKLE coverage row")
	_assert(not _find_row(abilities, "ABILITY_STENCH").is_empty(), "expected ABILITY_STENCH coverage row")
	_assert(not _find_row(trainers, "TRAINER_SAWYER_1").is_empty(), "expected TRAINER_SAWYER_1 coverage row")
	_assert(not _find_row(pokemon_data, "SPECIES_GEODUDE").is_empty(), "expected SPECIES_GEODUDE coverage row")
	var quick_wild := _find_row(debug_launchers, "debug_quick_wild_battle")
	var trainer_selector := _find_row(debug_launchers, "debug_trainer_battle_selector")
	_assert(bool(quick_wild.get("map_decoupled", false)) and bool(quick_wild.get("developer_only", false)), "expected quick wild launcher debug-only map-decoupled row")
	_assert(bool(trainer_selector.get("map_decoupled", false)) and bool(trainer_selector.get("developer_only", false)), "expected trainer launcher debug-only map-decoupled row")
	_assert(String(quick_wild.get("implementation_status", "")) == "first_pass", "expected quick wild launcher first pass")
	_assert(String(trainer_selector.get("implementation_status", "")) == "first_pass", "expected trainer selector first pass")
	_assert(_array(quick_wild.get("tests", [])).has("tools/godot_smoke/debug_battle_launcher_smoke.gd"), "expected quick wild smoke reference")
	_assert(_array(trainer_selector.get("tests", [])).has("tools/godot_smoke/debug_battle_launcher_smoke.gd"), "expected trainer selector smoke reference")
	_assert(_array(quick_wild.get("unsupported", [])).has("debug_random_wild_not_source_encounter"), "expected random wild debug unsupported code")
	_assert(not _array(quick_wild.get("unsupported", [])).has("debug_launcher_pending"), "quick wild launcher should no longer be pending")
	_assert(not _array(trainer_selector.get("unsupported", [])).has("debug_launcher_pending"), "trainer launcher should no longer be pending")

	var unsupported_registry := _array(report.get("unsupported_code_registry", []))
	_assert(_registry_has_code(unsupported_registry, "battle_audio_playback_pending"), "expected battle audio unsupported registry code")
	_assert(_registry_has_code(unsupported_registry, "pokemon_asset_import_pending"), "expected Pokemon asset unsupported registry code")

	var source_stats := _dict(source_index.get("stats", {}))
	_assert(_array(source_stats.get("missing_fixed_symbols", [])).is_empty(), "expected all fixed source battle symbols indexed")
	_assert(int(source_index.get("symbol_count", 0)) >= 7000, "expected broad source battle symbol index")
	var symbols := _dict(source_index.get("symbols", {}))
	_assert(symbols.has("CB2_InitBattle"), "expected CB2_InitBattle source index entry")
	_assert(symbols.has("gBattleAnimMove_Tackle"), "expected Tackle animation source index entry")

	var required_event_fields := _array(event_log_schema.get("required_event_fields", []))
	for field_name in ["sequence_index", "phase", "event_type", "source_symbol", "message_id", "animation_id", "rng_rolls", "unsupported"]:
		_assert(required_event_fields.has(field_name), "expected event log schema field %s" % field_name)

	if _failed:
		return

	print(JSON.stringify({
		"battle_parity_report_smoke": "ok",
		"total_coverage_rows": int(stats.get("total_coverage_rows", 0)),
		"source_symbol_count": int(source_index.get("symbol_count", 0)),
		"move_rows": int(row_counts.get("moves", 0)),
		"ability_rows": int(row_counts.get("abilities", 0)),
		"trainer_rows": int(row_counts.get("trainers", 0)),
		"pokemon_rows": int(row_counts.get("pokemon_data", 0)),
	}))
	quit(0)


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


func _registry_has_code(rows: Array, code: String) -> bool:
	for row in rows:
		if typeof(row) == TYPE_DICTIONARY and String(row.get("code", "")) == code:
			return true
	return false


func _supported_row_has_tests(row: Dictionary) -> bool:
	var has_supported_status := false
	for key in row.keys():
		if not String(key).ends_with("_status"):
			continue
		var value := String(row.get(key, ""))
		if value == "implemented" or value == "first_pass":
			has_supported_status = true
			break
	if not has_supported_status:
		return true
	return not _array(row.get("tests", [])).is_empty()


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
