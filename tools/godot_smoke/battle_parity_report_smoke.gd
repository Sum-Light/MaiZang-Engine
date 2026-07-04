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
	_assert(int(stats.get("total_coverage_rows", 0)) == 8644, "unexpected total battle coverage row count")
	_assert(int(row_counts.get("moves", 0)) == 935, "unexpected move coverage row count")
	_assert(int(row_counts.get("abilities", 0)) == 311, "unexpected ability coverage row count")
	_assert(int(row_counts.get("trainers", 0)) == 855, "unexpected trainer coverage row count")
	_assert(int(row_counts.get("trainer_party_mons", 0)) == 1825, "unexpected trainer party coverage row count")
	_assert(int(row_counts.get("pokemon_data", 0)) == 1573, "unexpected Pokemon data coverage row count")
	_assert(int(row_counts.get("battle_environments", 0)) == 35, "unexpected battle environment coverage row count")
	_assert(int(row_counts.get("battle_transitions", 0)) == 38, "unexpected battle transition coverage row count")
	_assert(int(row_counts.get("debug_launchers", 0)) == 2, "unexpected debug launcher coverage row count")
	for key in row_counts.keys():
		_assert(int(row_counts.get(key, -1)) == int(expected_counts.get(key, -2)), "coverage mismatch for %s" % key)

	var coverage_rows := _dict(report.get("coverage_rows", {}))
	var moves := _array(coverage_rows.get("moves", []))
	var abilities := _array(coverage_rows.get("abilities", []))
	var trainers := _array(coverage_rows.get("trainers", []))
	var pokemon_data := _array(coverage_rows.get("pokemon_data", []))
	var battle_environments := _array(coverage_rows.get("battle_environments", []))
	var battle_transitions := _array(coverage_rows.get("battle_transitions", []))
	var debug_launchers := _array(coverage_rows.get("debug_launchers", []))
	for section_name in coverage_rows.keys():
		for row in _array(coverage_rows.get(section_name, [])):
			_assert(_supported_row_has_tests(_dict(row)), "supported row in %s is missing tests" % section_name)
	var tackle := _find_row(moves, "MOVE_TACKLE")
	_assert(not tackle.is_empty(), "expected MOVE_TACKLE coverage row")
	_assert(String(tackle.get("battle_script_label", "")) == "BattleScript_EffectHit", "expected Tackle battle script link")
	_assert(_array(tackle.get("tests", [])).has("tools/godot_smoke/data_registry_move_effects_smoke.gd"), "expected move effect smoke reference")
	_assert(not _find_row(abilities, "ABILITY_STENCH").is_empty(), "expected ABILITY_STENCH coverage row")
	var sawyer := _find_row(trainers, "TRAINER_SAWYER_1")
	_assert(not sawyer.is_empty(), "expected TRAINER_SAWYER_1 coverage row")
	_assert(String(sawyer.get("asset_status", "")) == "first_pass", "expected Sawyer first-pass trainer sprite")
	_assert(String(sawyer.get("front_sprite_image", "")).ends_with("assets/generated/trainers/front_pics/hiker.png"), "expected Sawyer Hiker front sprite path")
	_assert(_array(sawyer.get("tests", [])).has("tools/godot_smoke/data_registry_trainer_sprites_smoke.gd"), "expected trainer sprite smoke reference")
	_assert(not _array(sawyer.get("unsupported", [])).has("trainer_asset_import_pending"), "Sawyer trainer sprite should no longer be pending")
	var geodude := _find_row(pokemon_data, "SPECIES_GEODUDE")
	_assert(not geodude.is_empty(), "expected SPECIES_GEODUDE coverage row")
	_assert(String(geodude.get("asset_status", "")) == "first_pass", "expected Geodude first-pass battle sprites")
	_assert(String(geodude.get("front_sprite_image", "")).ends_with("assets/generated/pokemon_battle/geodude/front.png"), "expected Geodude front sprite path")
	_assert(_array(geodude.get("tests", [])).has("tools/godot_smoke/data_registry_pokemon_battle_sprites_smoke.gd"), "expected Pokemon battle sprite smoke reference")
	_assert(not _array(geodude.get("unsupported", [])).has("pokemon_asset_import_pending"), "Geodude sprites should no longer be pending")
	var grass_environment := _find_row(battle_environments, "BATTLE_ENVIRONMENT_GRASS")
	_assert(not grass_environment.is_empty(), "expected grass battle environment coverage row")
	_assert(String(grass_environment.get("asset_status", "")) == "first_pass", "expected grass environment first-pass asset")
	_assert(String(grass_environment.get("background_image", "")).ends_with("assets/generated/battle_environment/grass/background.png"), "expected grass environment background path")
	_assert(_array(grass_environment.get("tests", [])).has("tools/godot_smoke/data_registry_battle_environments_smoke.gd"), "expected battle environment smoke reference")
	var soaring_environment := _find_row(battle_environments, "BATTLE_ENVIRONMENT_SOARING")
	_assert(not soaring_environment.is_empty(), "expected soaring battle environment coverage row")
	_assert(String(soaring_environment.get("asset_status", "")) == "unsupported", "expected soaring environment asset unsupported")
	_assert(_array(soaring_environment.get("unsupported", [])).has("battle_environment_asset_pending"), "expected soaring environment asset pending")
	var big_pokeball_transition := _find_row(battle_transitions, "B_TRANSITION_BIG_POKEBALL")
	_assert(not big_pokeball_transition.is_empty(), "expected Big Pokeball transition coverage row")
	_assert(String(big_pokeball_transition.get("asset_status", "")) == "first_pass", "expected Big Pokeball transition first-pass asset")
	_assert(String(big_pokeball_transition.get("first_texture", "")).ends_with("assets/generated/battle_transitions/big_pokeball.png"), "expected Big Pokeball texture path")
	_assert(_array(big_pokeball_transition.get("tests", [])).has("tools/godot_smoke/data_registry_battle_transitions_smoke.gd"), "expected battle transition smoke reference")
	var blur_transition := _find_row(battle_transitions, "B_TRANSITION_BLUR")
	_assert(not blur_transition.is_empty(), "expected Blur transition coverage row")
	_assert(String(blur_transition.get("asset_status", "")) == "metadata_only", "expected Blur metadata-only asset status")
	_assert(_array(blur_transition.get("unsupported", [])).has("battle_transition_runtime_pending"), "expected Blur runtime pending")
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
	_assert(_registry_has_code(unsupported_registry, "battle_environment_runtime_pending"), "expected battle environment runtime unsupported registry code")
	_assert(_registry_has_code(unsupported_registry, "battle_transition_runtime_pending"), "expected battle transition runtime unsupported registry code")

	var source_stats := _dict(source_index.get("stats", {}))
	_assert(_array(source_stats.get("missing_fixed_symbols", [])).is_empty(), "expected all fixed source battle symbols indexed")
	_assert(int(source_index.get("symbol_count", 0)) >= 7000, "expected broad source battle symbol index")
	var symbols := _dict(source_index.get("symbols", {}))
	_assert(symbols.has("CB2_InitBattle"), "expected CB2_InitBattle source index entry")
	_assert(symbols.has("BattleScript_EffectHit"), "expected battle script source index entry")
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
		"battle_environment_rows": int(row_counts.get("battle_environments", 0)),
		"battle_transition_rows": int(row_counts.get("battle_transitions", 0)),
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
