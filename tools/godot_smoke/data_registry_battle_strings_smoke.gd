extends SceneTree

const DATA_REGISTRY_SCRIPT := preload("res://scripts/autoload/data_registry.gd")

var _failed := false


func _init() -> void:
	var registry = DATA_REGISTRY_SCRIPT.new()
	registry._ready()

	var battle_strings := registry.get_battle_string_data()
	var stats = battle_strings.get("stats", {})
	_assert(typeof(battle_strings) == TYPE_DICTIONARY and not battle_strings.is_empty(), "expected battle string data")
	_assert(typeof(stats) == TYPE_DICTIONARY, "expected battle string stats")
	_assert(int(stats.get("string_id_count", 0)) == 697, "unexpected battle string id count")
	_assert(int(stats.get("table_entry_count", 0)) == 688, "unexpected battle string table count")
	_assert(int(stats.get("declared_text_count", 0)) == 173, "unexpected declared battle text count")
	_assert(int(stats.get("ui_text_count", 0)) == 19, "unexpected battle UI text count")
	_assert(int(stats.get("unsupported_table_entry_count", -1)) == 0, "expected no unsupported table entries")
	_assert(int(stats.get("unsupported_token_count", -1)) == 0, "expected no unsupported battle text tokens")
	_assert(int(stats.get("audio_cue_count", 0)) == 17, "unexpected audio cue count")
	_assert(int(stats.get("metadata_only_count", 0)) == 17, "unexpected metadata-only audio cue count")

	var runtime_families = battle_strings.get("placeholder_runtime_families", [])
	_assert(_array_has_source_symbol(runtime_families, "B_BUFF_MOVE"), "expected B_BUFF_MOVE runtime family")
	_assert(_array_has_source_symbol(runtime_families, "B_BUFF_TYPE"), "expected B_BUFF_TYPE runtime family")
	_assert(_array_has_source_symbol(runtime_families, "B_BUFF_STAT"), "expected B_BUFF_STAT runtime family")
	_assert(_array_has_source_symbol(runtime_families, "B_BUFF_ABILITY"), "expected B_BUFF_ABILITY runtime family")
	_assert(_array_has_source_symbol(runtime_families, "B_BUFF_ITEM"), "expected B_BUFF_ITEM runtime family")
	_assert(_array_has_source_symbol(runtime_families, "B_BUFF_MON_NICK"), "expected B_BUFF_MON_NICK runtime family")

	var semantic_tags = stats.get("placeholder_semantic_tags", {})
	_assert(int(semantic_tags.get("attacker", 0)) > 0, "expected attacker placeholder metadata")
	_assert(int(semantic_tags.get("target", 0)) > 0, "expected target placeholder metadata")
	_assert(int(semantic_tags.get("move", 0)) > 0, "expected move placeholder metadata")
	_assert(int(semantic_tags.get("item", 0)) > 0, "expected item placeholder metadata")
	_assert(int(semantic_tags.get("ability", 0)) > 0, "expected ability placeholder metadata")
	_assert(int(semantic_tags.get("side", 0)) > 0, "expected side placeholder metadata")
	_assert(int(semantic_tags.get("pokemon_nickname", 0)) > 0, "expected Pokemon nickname placeholder metadata")

	var intro := registry.get_battle_string_by_id(0)
	_assert(String(intro.get("symbol", "")) == "STRINGID_INTROMSG", "expected intro string id round trip")
	_assert(String(intro.get("table_status", "")) == "controller_or_runtime_string", "expected intro controller/runtime status")

	var attack_missed := registry.get_battle_string_record("ATTACKMISSED")
	var attack_missed_by_id := registry.get_battle_string_by_id(19)
	_assert(String(attack_missed.get("symbol", "")) == "STRINGID_ATTACKMISSED", "expected attack-missed record")
	_assert(String(attack_missed_by_id.get("symbol", "")) == "STRINGID_ATTACKMISSED", "expected attack-missed id lookup")
	_assert(String(attack_missed.get("display_text", "")).contains("{B_ATK_NAME_WITH_PREFIX}"), "expected attack placeholder")
	_assert(_placeholders_have_tag(attack_missed.get("placeholders", []), "attacker"), "expected attacker semantic tag")
	_assert(_placeholders_have_tag(attack_missed.get("placeholders", []), "pokemon_nickname"), "expected nickname semantic tag")

	var formatted_attack := registry.format_battle_message("STRINGID_ATTACKMISSED", {
		"B_ATK_NAME_WITH_PREFIX": "Torchic",
	})
	_assert(String(formatted_attack.get("status", "")) == "ok", "expected formatted attack message")
	_assert(String(formatted_attack.get("text", "")).contains("Torchic"), "expected substituted attacker name")
	_assert(not String(formatted_attack.get("text", "")).contains("{B_ATK_NAME_WITH_PREFIX}"), "expected placeholder removed")

	var what_will := registry.get_battle_text_record("gText_WhatWillPkmnDo")
	_assert(String(what_will.get("label", "")) == "gText_WhatWillPkmnDo", "expected what-will text record")
	_assert(_placeholders_have_token(what_will.get("placeholders", []), "B_BUFF1"), "expected B_BUFF1 placeholder")
	_assert(_controls_have_token(what_will.get("text_controls", []), "\\n"), "expected what-will newline control")
	var formatted_what := registry.format_battle_message("gText_WhatWillPkmnDo", {
		"B_BUFF1": "Torchic",
	})
	_assert(String(formatted_what.get("status", "")) == "ok", "expected formatted what-will message")
	_assert(String(formatted_what.get("text", "")).begins_with("Torchic"), "expected B_BUFF1 substitution")

	var battle_menu := registry.get_battle_text_record("gText_BattleMenu")
	_assert(String(battle_menu.get("label", "")) == "gText_BattleMenu", "expected battle menu text")
	_assert(_controls_have_command(battle_menu.get("text_controls", []), "CLEAR_TO"), "expected battle menu clear-to control")
	_assert(_controls_have_token(battle_menu.get("text_controls", []), "\\n"), "expected battle menu newline control")

	var move_pp := registry.get_battle_text_record("gText_MoveInterfacePP")
	var move_type := registry.get_battle_text_record("gText_MoveInterfaceType")
	var move_pp_type := registry.get_battle_text_record("gText_MoveInterfacePpType")
	_assert(String(move_pp.get("display_text", "")) == "PP", "expected PP label")
	_assert(String(move_type.get("display_text", "")).length() > 0, "expected move type label")
	_assert(_controls_have_command(move_pp_type.get("text_controls", []), "PALETTE"), "expected PP/type palette control")
	_assert(_controls_have_command(move_pp_type.get("text_controls", []), "BACKGROUND"), "expected PP/type background control")
	_assert(_controls_have_command(move_pp_type.get("text_controls", []), "TEXT_COLORS"), "expected PP/type text-colors control")

	var got_away := registry.format_battle_message("STRINGID_GOTAWAYSAFELY")
	var audio_cues = got_away.get("audio_cues", [])
	var metadata_only = got_away.get("metadata_only", [])
	_assert(String(got_away.get("status", "")) == "ok", "expected got-away message without unresolved placeholders")
	_assert(_audio_has_command(audio_cues, "PLAY_SE", "SE_FLEE"), "expected SE_FLEE audio cue metadata")
	_assert(_audio_has_command(metadata_only, "PLAY_SE", "SE_FLEE"), "expected SE_FLEE metadata-only note")

	if _failed:
		return

	print(JSON.stringify({
		"data_registry_battle_strings_smoke": "ok",
		"string_id_count": int(stats.get("string_id_count", 0)),
		"table_entry_count": int(stats.get("table_entry_count", 0)),
		"placeholder_count": int(stats.get("placeholder_count", 0)),
		"audio_cue_count": int(stats.get("audio_cue_count", 0)),
	}))
	registry.free()
	quit(0)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true
	quit(1)


func _array_has_source_symbol(records, source_symbol: String) -> bool:
	if typeof(records) != TYPE_ARRAY:
		return false
	for record in records:
		if typeof(record) == TYPE_DICTIONARY and String(record.get("source_symbol", "")) == source_symbol:
			return true
	return false


func _placeholders_have_token(placeholders, token: String) -> bool:
	if typeof(placeholders) != TYPE_ARRAY:
		return false
	for placeholder in placeholders:
		if typeof(placeholder) == TYPE_DICTIONARY and String(placeholder.get("token", "")) == token:
			return true
	return false


func _placeholders_have_tag(placeholders, tag: String) -> bool:
	if typeof(placeholders) != TYPE_ARRAY:
		return false
	for placeholder in placeholders:
		if typeof(placeholder) != TYPE_DICTIONARY:
			continue
		var tags = placeholder.get("semantic_tags", [])
		if typeof(tags) == TYPE_ARRAY and tag in tags:
			return true
	return false


func _controls_have_token(controls, token: String) -> bool:
	if typeof(controls) != TYPE_ARRAY:
		return false
	for control in controls:
		if typeof(control) == TYPE_DICTIONARY and String(control.get("token", "")) == token:
			return true
	return false


func _controls_have_command(controls, command: String) -> bool:
	if typeof(controls) != TYPE_ARRAY:
		return false
	for control in controls:
		if typeof(control) == TYPE_DICTIONARY and String(control.get("command", "")) == command:
			return true
	return false


func _audio_has_command(records, command: String, arg: String) -> bool:
	if typeof(records) != TYPE_ARRAY:
		return false
	for record in records:
		if typeof(record) != TYPE_DICTIONARY:
			continue
		if String(record.get("command", "")) != command:
			continue
		var args = record.get("args", [])
		if typeof(args) == TYPE_ARRAY and arg in args:
			return true
	return false
