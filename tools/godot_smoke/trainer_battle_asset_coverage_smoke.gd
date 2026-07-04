extends SceneTree

const REPORT_PATH := "res://data/generated/reports/trainer_battle_asset_coverage.json"

var _failed := false


func _init() -> void:
	var report := _read_json(REPORT_PATH)
	_assert(String(report.get("generated_by", "")) == "tools/report_trainer_battle_assets.py", "unexpected trainer battle asset report generator")
	_assert(int(report.get("schema_version", 0)) == 1, "unexpected trainer battle asset report schema")
	_assert(not _contains_key_recursive(report, "runtime_palette"), "report must not expose a runtime palette API")

	var policy := _dict(report.get("runtime_color_policy", {}))
	var rule := String(policy.get("rule", ""))
	_assert(String(policy.get("status", "")) == "no_runtime_palette", "expected no runtime palette policy")
	_assert(rule.contains("distinct RGBA assets"), "expected distinct RGBA asset rule")
	_assert(rule.contains("Shader/Material/Animation"), "expected Godot-native color effect rule")
	_assert(String(policy.get("audio_status", "")) == "metadata_only", "expected audio metadata-only policy")

	var stats := _dict(report.get("stats", {}))
	_assert(int(stats.get("coverage_row_count", 0)) == 855, "unexpected trainer coverage row count")
	_assert(int(stats.get("trainer_count", 0)) == 855, "unexpected trainer count")
	_assert(int(stats.get("asset_status_first_pass_count", 0)) == 855, "unexpected first-pass trainer asset count")
	_assert(int(stats.get("front_sprite_imported_count", 0)) == 855, "unexpected trainer-row front sprite count")
	_assert(int(stats.get("front_sprite_definition_count", 0)) == 155, "unexpected front sprite definition count")
	_assert(int(stats.get("front_textures_imported_count", 0)) == 155, "unexpected imported front texture count")
	_assert(int(stats.get("unique_front_sprite_used_count", 0)) == 93, "unexpected used front sprite count")
	_assert(int(stats.get("back_sprite_definition_count", 0)) == 10, "unexpected back sprite definition count")
	_assert(int(stats.get("back_textures_imported_count", 0)) == 10, "unexpected back texture count")
	_assert(int(stats.get("front_source_color_metadata_only_count", 0)) == 855, "unexpected front source color metadata count")
	_assert(int(stats.get("mugshot_transition_metadata_only_count", 0)) == 5, "unexpected mugshot trainer count")
	_assert(int(stats.get("mugshot_source_color_metadata_only_count", 0)) == 5, "unexpected mugshot source color count")
	_assert(int(stats.get("music_audio_metadata_only_count", 0)) == 855, "unexpected trainer music metadata count")
	_assert(int(stats.get("party_mon_count", 0)) == 1825, "unexpected party mon count")
	_assert(int(stats.get("party_status_first_pass_count", 0)) == 852, "unexpected first-pass party count")
	_assert(int(stats.get("party_status_not_required_count", 0)) == 1, "unexpected no-party trainer count")
	_assert(int(stats.get("party_status_unsupported_count", 0)) == 2, "unexpected unsupported party count")
	_assert(int(stats.get("party_missing_species_asset_count", 0)) == 2, "unexpected party species asset gap count")
	_assert(int(stats.get("party_explicit_move_mon_count", 0)) == 436, "unexpected explicit-move party mon count")
	_assert(int(stats.get("party_default_move_mon_count", 0)) == 1389, "unexpected default-move party mon count")
	_assert(int(stats.get("party_held_item_mon_count", 0)) == 142, "unexpected held-item party mon count")
	_assert(int(stats.get("trainer_with_items_count", 0)) == 141, "unexpected trainer item count")
	_assert(int(stats.get("trainer_with_ai_flags_count", 0)) == 839, "unexpected trainer AI flag count")
	_assert(int(stats.get("double_battle_count", 0)) == 77, "unexpected double battle count")
	_assert(int(stats.get("transition_kind_mugshot_count", 0)) == 5, "unexpected mugshot transition count")
	_assert(int(stats.get("transition_kind_team_magma_count", 0)) == 33, "unexpected Magma transition count")
	_assert(int(stats.get("transition_kind_team_aqua_count", 0)) == 30, "unexpected Aqua transition count")
	_assert(int(stats.get("transition_kind_trainer_transition_table_count", 0)) == 787, "unexpected trainer transition-table count")
	_assert(int(stats.get("text_refs_unsupported_count", 0)) == 854, "unexpected text-ref pending count")
	_assert(int(stats.get("reward_unsupported_count", 0)) == 854, "unexpected reward pending count")

	var rows := _array(report.get("coverage_rows", []))
	_assert(rows.size() == 855, "unexpected trainer coverage row array size")
	_check_row_shapes(rows)
	_check_fixture_rows(rows)

	var unsupported_registry := _array(report.get("unsupported_code_registry", []))
	for code in [
		"trainer_party_species_asset_pending",
		"trainer_intro_defeat_text_pending",
		"trainer_reward_flow_pending",
		"trainer_transition_magma_runtime_pending",
		"trainer_transition_aqua_runtime_pending",
		"trainer_mugshot_runtime_pending",
		"battle_audio_playback_pending",
	]:
		_assert(_registry_has_code(unsupported_registry, code), "expected unsupported registry code %s" % code)

	if _failed:
		return

	print(JSON.stringify({
		"trainer_battle_asset_coverage_smoke": "ok",
		"coverage_rows": int(stats.get("coverage_row_count", 0)),
		"asset_status_first_pass_count": int(stats.get("asset_status_first_pass_count", 0)),
		"party_missing_species_asset_count": int(stats.get("party_missing_species_asset_count", 0)),
		"mugshot_transitions": int(stats.get("transition_kind_mugshot_count", 0)),
		"magma_transitions": int(stats.get("transition_kind_team_magma_count", 0)),
		"aqua_transitions": int(stats.get("transition_kind_team_aqua_count", 0)),
	}))
	quit(0)


func _check_row_shapes(rows: Array) -> void:
	for value in rows:
		var row := _dict(value)
		for key in ["trainer_data", "front_sprite", "source_color_provenance", "mugshot", "slide", "transition", "music", "party_sprite_requirements", "text_refs", "reward_metadata", "unsupported"]:
			_assert(row.has(key), "trainer coverage row missing %s" % key)
		_assert(String(_dict(row.get("music", {})).get("audio_status", "")) == "metadata_only", "trainer music must remain metadata-only")


func _check_fixture_rows(rows: Array) -> void:
	var none := _find_row(rows, "TRAINER_NONE")
	_assert(not none.is_empty(), "expected TRAINER_NONE row")
	_assert(int(none.get("numeric_id", -1)) == 0, "expected TRAINER_NONE id 0")
	_assert(String(none.get("party_status", "")) == "not_required", "expected TRAINER_NONE no-party status")
	_assert(String(_dict(none.get("text_refs", {})).get("status", "")) == "not_required", "expected TRAINER_NONE text refs not required")
	_assert(String(_dict(none.get("reward_metadata", {})).get("status", "")) == "not_required", "expected TRAINER_NONE reward not required")

	var sawyer := _find_row(rows, "TRAINER_SAWYER_1")
	_assert(not sawyer.is_empty(), "expected Sawyer row")
	_assert(int(sawyer.get("numeric_id", -1)) == 1, "expected Sawyer id")
	_assert(String(sawyer.get("asset_status", "")) == "first_pass", "expected Sawyer first-pass trainer asset")
	_assert(String(sawyer.get("party_status", "")) == "first_pass", "expected Sawyer first-pass party assets")
	_assert(String(_dict(sawyer.get("front_sprite", {})).get("source_symbol", "")) == "gTrainerFrontPic_Hiker", "expected Sawyer Hiker front sprite")
	_assert(String(_dict(_dict(sawyer.get("source_color_provenance", {})).get("front", {})).get("status", "")) == "metadata_only", "expected Sawyer front source color")
	_assert(String(_dict(sawyer.get("music", {})).get("source_symbol", "")) == "TRAINER_ENCOUNTER_MUSIC_HIKER", "expected Sawyer music symbol")
	_assert(String(_dict(sawyer.get("transition", {})).get("kind", "")) == "trainer_transition_table", "expected Sawyer normal trainer transition table")
	var sawyer_party := _dict(sawyer.get("party_sprite_requirements", {}))
	var sawyer_mon := _dict(_array(sawyer_party.get("pokemon", []))[0])
	_assert(int(sawyer_mon.get("index", -1)) == 0, "expected Sawyer party index 0")
	_assert(String(sawyer_mon.get("species_symbol", "")) == "SPECIES_GEODUDE", "expected Sawyer Geodude")
	_assert(String(sawyer_mon.get("battle_sprite_status", "")) == "first_pass", "expected Sawyer Geodude sprite coverage")
	_assert(_unsupported_has(sawyer, "trainer_intro_defeat_text_pending"), "expected Sawyer text pending code")
	_assert(_unsupported_has(sawyer, "trainer_reward_flow_pending"), "expected Sawyer reward pending code")

	var sidney := _find_row(rows, "TRAINER_SIDNEY")
	_assert(not sidney.is_empty(), "expected Sidney row")
	_assert(String(_dict(sidney.get("mugshot", {})).get("color_symbol", "")) == "MUGSHOT_COLOR_PURPLE", "expected Sidney purple mugshot")
	_assert(String(_dict(sidney.get("transition", {})).get("selected", "")) == "B_TRANSITION_MUGSHOT", "expected Sidney mugshot transition")
	_assert(String(_dict(_dict(sidney.get("source_color_provenance", {})).get("mugshot_background", {})).get("status", "")) == "metadata_only", "expected Sidney mugshot source color")
	_assert(_unsupported_has(sidney, "trainer_mugshot_runtime_pending"), "expected Sidney mugshot runtime pending")

	var wallace := _find_row(rows, "TRAINER_WALLACE")
	_assert(not wallace.is_empty(), "expected Wallace row")
	_assert(String(_dict(_dict(wallace.get("mugshot", {})).get("trainer_sprite_coords", {})).get("status", "")) == "metadata_only", "expected Wallace mugshot coordinate metadata")
	_assert(String(_dict(_dict(wallace.get("source_color_provenance", {})).get("mugshot_background", {})).get("source_symbol", "")) == "sMugshotPal_Yellow", "expected Wallace yellow mugshot source color")

	var aqua := _find_row(rows, "TRAINER_GRUNT_AQUA_HIDEOUT_1")
	_assert(not aqua.is_empty(), "expected Aqua grunt row")
	_assert(String(_dict(aqua.get("transition", {})).get("selected", "")) == "B_TRANSITION_AQUA", "expected Aqua special transition")
	_assert(_unsupported_has(aqua, "trainer_transition_aqua_runtime_pending"), "expected Aqua runtime pending code")

	var magma := _find_row(rows, "TRAINER_GRUNT_MAGMA_HIDEOUT_1")
	_assert(not magma.is_empty(), "expected Magma grunt row")
	_assert(String(_dict(magma.get("transition", {})).get("selected", "")) == "B_TRANSITION_MAGMA", "expected Magma special transition")
	_assert(_unsupported_has(magma, "trainer_transition_magma_runtime_pending"), "expected Magma runtime pending code")

	var angelica := _find_row(rows, "TRAINER_ANGELICA")
	_assert(not angelica.is_empty(), "expected Angelica row")
	var angelica_party := _dict(angelica.get("party_sprite_requirements", {}))
	var angelica_mon := _dict(_array(angelica_party.get("pokemon", []))[0])
	_assert(String(angelica.get("party_status", "")) == "unsupported", "expected Angelica party asset gap")
	_assert(int(angelica_party.get("missing_species_asset_count", 0)) == 1, "expected Angelica Castform species asset gap")
	_assert(String(angelica_mon.get("species_symbol", "")) == "SPECIES_CASTFORM", "expected Angelica Castform source species")
	_assert(String(angelica_mon.get("battle_sprite_status", "")) == "missing_species_asset_row", "expected Castform alias gap")
	_assert(_unsupported_has(angelica, "trainer_party_species_asset_pending"), "expected Angelica party species pending code")

	var double_trainer := _find_row(rows, "TRAINER_GABBY_AND_TY_1")
	_assert(not double_trainer.is_empty(), "expected double trainer row")
	_assert(bool(_dict(_dict(double_trainer.get("trainer_data", {})).get("battle_type", {})).get("is_double", false)), "expected double battle metadata")
	_assert(_unsupported_has(double_trainer, "trainer_double_battle_runtime_pending"), "expected double battle runtime pending code")


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
