extends SceneTree

const DATA_REGISTRY_SCRIPT := preload("res://scripts/autoload/data_registry.gd")

var _failed := false


func _init() -> void:
	var registry = DATA_REGISTRY_SCRIPT.new()
	registry._ready()

	var data := registry.get_battle_transitions_data()
	var stats := _dict(data.get("stats", {}))
	_assert(typeof(data) == TYPE_DICTIONARY and not data.is_empty(), "expected battle transition data")
	_assert(int(stats.get("transition_count", 0)) == 38, "unexpected battle transition count")
	_assert(int(stats.get("transition_group_count", 0)) == 10, "unexpected battle transition group count")
	_assert(int(stats.get("graphics_definition_count", 0)) == 55, "unexpected transition graphics definition count")
	_assert(int(stats.get("source_png_asset_count", 0)) == 23, "unexpected transition PNG asset count")
	_assert(int(stats.get("source_palette_asset_count", 0)) == 19, "unexpected transition palette asset count")
	_assert(int(stats.get("source_binary_asset_count", 0)) == 14, "unexpected transition binary asset count")
	_assert(int(stats.get("texture_count", 0)) == 23, "unexpected imported transition texture count")
	_assert(int(stats.get("missing_asset_ref_count", -1)) == 0, "expected no missing transition asset refs")
	_assert(int(stats.get("wild_transition_table_count", 0)) == 4, "unexpected wild transition table count")
	_assert(int(stats.get("trainer_transition_table_count", 0)) == 4, "unexpected trainer transition table count")
	_assert(int(stats.get("battle_frontier_transition_count", 0)) == 12, "unexpected frontier transition table count")
	_assert(int(stats.get("battle_pyramid_transition_count", 0)) == 3, "unexpected pyramid transition table count")
	_assert(int(stats.get("battle_dome_transition_count", 0)) == 4, "unexpected dome transition table count")

	var blur := registry.get_battle_transition_record("blur")
	_assert(String(blur.get("symbol", "")) == "B_TRANSITION_BLUR", "expected blur transition")
	_assert(String(blur.get("main_task", "")) == "Task_Blur", "expected blur main task")
	_assert(_coverage_status(blur, "asset_status") == "metadata_only", "expected blur metadata-only asset status")
	_assert(_array(blur.get("texture_refs", [])).is_empty(), "expected blur to have no static texture refs")
	_assert(_array(blur.get("unsupported", [])).has("battle_transition_runtime_pending"), "expected blur runtime pending")

	var big_pokeball := registry.get_battle_transition_record("big_pokeball")
	var big_pokeball_by_id := registry.get_battle_transition_record(3)
	_assert(String(big_pokeball.get("symbol", "")) == "B_TRANSITION_BIG_POKEBALL", "expected big Pokeball transition")
	_assert(String(big_pokeball_by_id.get("symbol", "")) == "B_TRANSITION_BIG_POKEBALL", "expected big Pokeball id lookup")
	_assert(String(big_pokeball.get("main_task", "")) == "Task_BigPokeball", "expected big Pokeball main task")
	_assert(_coverage_status(big_pokeball, "asset_status") == "first_pass", "expected big Pokeball first-pass assets")
	_assert(_has_ref(big_pokeball, "texture_refs", "graphics/battle_transitions/big_pokeball.png"), "expected big Pokeball texture ref")
	_assert(_has_ref(big_pokeball, "binary_refs", "graphics/battle_transitions/big_pokeball_map.bin"), "expected big Pokeball tilemap ref")
	_assert(_asset_exists(data, "graphics/battle_transitions/big_pokeball.png"), "expected imported big Pokeball PNG")

	var aqua := registry.get_battle_transition_record("aqua")
	_assert(String(aqua.get("main_task", "")) == "Task_Aqua", "expected Aqua transition task")
	_assert(_has_ref(aqua, "texture_refs", "graphics/battle_transitions/team_aqua.png"), "expected Aqua texture")
	_assert(_has_ref(aqua, "palette_refs", "graphics/battle_transitions/evil_team.pal"), "expected Aqua evil team palette")
	_assert(_asset_exists(data, "graphics/battle_transitions/team_aqua.png"), "expected imported Aqua texture")

	var mugshot := registry.get_battle_transition_record("mugshot")
	_assert(String(mugshot.get("main_task", "")) == "Task_Mugshot", "expected mugshot transition task")
	_assert(_has_ref(mugshot, "texture_refs", "graphics/battle_transitions/elite_four_bg.png"), "expected mugshot banner texture")
	_assert(_has_ref(mugshot, "palette_refs", "graphics/battle_transitions/brendan_bg.pal"), "expected Brendan mugshot palette")
	_assert(_has_ref(mugshot, "palette_refs", "graphics/battle_transitions/may_bg.pal"), "expected May mugshot palette")

	var frontier_circles := registry.get_battle_transition_record("frontier_circles_meet")
	_assert(String(frontier_circles.get("main_task", "")) == "Task_FrontierCirclesMeet", "expected Frontier circles task")
	_assert(_has_ref(frontier_circles, "texture_refs", "graphics/battle_transitions/frontier_logo_center.png"), "expected Frontier center texture")
	_assert(_has_ref(frontier_circles, "texture_refs", "graphics/battle_transitions/frontier_logo_circles.png"), "expected Frontier circles texture")

	var selection_tables := _dict(data.get("selection_tables", {}))
	var wild := _array(selection_tables.get("wild", []))
	var trainer := _array(selection_tables.get("trainer", []))
	_assert(String(_dict(wild[0]).get("enemy_lower", "")) == "B_TRANSITION_SLICE", "expected normal lower wild transition")
	_assert(String(_dict(wild[0]).get("enemy_equal_or_higher", "")) == "B_TRANSITION_WHITE_BARS_FADE", "expected normal higher wild transition")
	_assert(String(_dict(trainer[0]).get("enemy_lower", "")) == "B_TRANSITION_POKEBALLS_TRAIL", "expected normal lower trainer transition")
	_assert(_array(_dict(selection_tables.get("battle_pyramid", {})).get("transitions", [])).has("B_TRANSITION_FRONTIER_SQUARES_SPIRAL"), "expected Pyramid frontier squares spiral")

	for transition_symbol in _current_engine_transition_symbols():
		var transition := registry.get_battle_transition_record(transition_symbol)
		_assert(not transition.is_empty(), "expected current BattleEngine transition %s to resolve" % transition_symbol)
		_assert(_array(transition.get("unsupported", [])).has("battle_transition_runtime_pending"), "expected transition runtime pending for %s" % transition_symbol)

	var render_notes := _dict(data.get("rendering_notes", {}))
	_assert(String(render_notes.get("runtime_status", "")) == "unsupported", "expected runtime unsupported note")
	_assert(String(render_notes.get("audio_status", "")) == "metadata_only", "expected audio metadata-only note")

	if _failed:
		return

	print(JSON.stringify({
		"data_registry_battle_transitions_smoke": "ok",
		"transition_count": int(stats.get("transition_count", 0)),
		"texture_count": int(stats.get("texture_count", 0)),
		"battle_frontier_transition_count": int(stats.get("battle_frontier_transition_count", 0)),
	}))
	registry.free()
	quit(0)


func _current_engine_transition_symbols() -> Array:
	return [
		"B_TRANSITION_SLICE",
		"B_TRANSITION_WHITE_BARS_FADE",
		"B_TRANSITION_CLOCKWISE_WIPE",
		"B_TRANSITION_GRID_SQUARES",
		"B_TRANSITION_BLUR",
		"B_TRANSITION_WAVE",
		"B_TRANSITION_RIPPLE",
		"B_TRANSITION_POKEBALLS_TRAIL",
		"B_TRANSITION_ANGLED_WIPES",
		"B_TRANSITION_SHUFFLE",
		"B_TRANSITION_BIG_POKEBALL",
		"B_TRANSITION_SWIRL",
		"B_TRANSITION_MUGSHOT",
		"B_TRANSITION_MAGMA",
		"B_TRANSITION_AQUA",
	]


func _coverage_status(record: Dictionary, key: String) -> String:
	return String(_dict(record.get("coverage", {})).get(key, ""))


func _has_ref(record: Dictionary, key: String, expected: String) -> bool:
	return _array(record.get(key, [])).has(expected)


func _asset_exists(data: Dictionary, asset_id: String) -> bool:
	var asset := _dict(_dict(data.get("assets", {})).get(asset_id, {}))
	var path := String(asset.get("image", ""))
	return not path.is_empty() and FileAccess.file_exists(path)


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
