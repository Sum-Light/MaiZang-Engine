extends SceneTree

const DATA_REGISTRY_SCRIPT := preload("res://scripts/autoload/data_registry.gd")

var _failed := false


func _init() -> void:
	var registry = DATA_REGISTRY_SCRIPT.new()
	registry._ready()

	var species_data := registry.get_species_data()
	var stats = species_data.get("stats", {})
	_assert(typeof(species_data) == TYPE_DICTIONARY and not species_data.is_empty(), "expected species data")
	_assert(typeof(stats) == TYPE_DICTIONARY, "expected species stats")
	_assert(int(stats.get("species_count", 0)) == 1573, "unexpected active species initializer count")
	_assert(int(stats.get("struct_initializer_count", 0)) == 1366, "unexpected struct species initializer count")
	_assert(int(stats.get("macro_initializer_count", 0)) == 207, "unexpected macro species initializer count")
	_assert(int(stats.get("species_with_core_stats", 0)) == 1329, "unexpected core species stat count")
	_assert(int(stats.get("preprocessor_warning_count", -1)) == 0, "expected no species preprocessor warnings")
	_assert(int(stats.get("warning_count", 0)) == 207, "expected only macro initializer species warnings")

	var bulbasaur := registry.get_species_record("SPECIES_BULBASAUR")
	var bulbasaur_by_id := registry.get_species_record(1)
	var bulbasaur_by_short_name := registry.get_species_record("bulbasaur")
	_assert(not bulbasaur.is_empty(), "expected Bulbasaur species record")
	_assert(String(bulbasaur_by_id.get("symbol", "")) == "SPECIES_BULBASAUR", "expected species id lookup")
	_assert(String(bulbasaur_by_short_name.get("symbol", "")) == "SPECIES_BULBASAUR", "expected short species symbol lookup")
	_assert(int(bulbasaur.get("id", -1)) == 1, "unexpected Bulbasaur species id")
	_assert(String(bulbasaur.get("initializer_kind", "")) == "struct", "expected Bulbasaur struct initializer")

	var base_stats = bulbasaur.get("base_stats", {})
	var gender_ratio = bulbasaur.get("gender_ratio", {})
	var species_name = bulbasaur.get("species_name", {})
	var category_name = bulbasaur.get("category_name", {})
	var description = bulbasaur.get("description", {})
	var national_dex = bulbasaur.get("national_dex", {})
	var growth_rate = bulbasaur.get("growth_rate", {})
	_assert(typeof(base_stats) == TYPE_DICTIONARY, "expected Bulbasaur base stats")
	_assert(int(base_stats.get("hp", 0)) == 45, "unexpected Bulbasaur HP")
	_assert(int(base_stats.get("attack", 0)) == 49, "unexpected Bulbasaur attack")
	_assert(int(base_stats.get("sp_attack", 0)) == 65, "unexpected Bulbasaur special attack")
	_assert(int(bulbasaur.get("catch_rate", 0)) == 45, "unexpected Bulbasaur catch rate")
	_assert(int(bulbasaur.get("exp_yield", 0)) == 64, "unexpected Bulbasaur exp yield")
	_assert(int(gender_ratio.get("value", 0)) == 31, "unexpected Bulbasaur gender ratio")
	_assert(String(gender_ratio.get("kind", "")) == "percent_female", "unexpected Bulbasaur gender kind")
	_assert(int(national_dex.get("value", 0)) == 1, "unexpected Bulbasaur national dex number")
	_assert(String(growth_rate.get("symbol", "")) == "GROWTH_MEDIUM_SLOW", "unexpected Bulbasaur growth rate")
	_assert(String(species_name.get("display_text", "")).length() > 0, "expected Bulbasaur display name")
	_assert(String(category_name.get("display_text", "")).length() > 0, "expected Bulbasaur category name")
	_assert(String(description.get("display_text", "")).contains("\n"), "expected Bulbasaur multiline description")
	_assert(_constant_symbol_at(bulbasaur.get("types", []), 0) == "TYPE_GRASS", "unexpected Bulbasaur first type")
	_assert(_constant_symbol_at(bulbasaur.get("types", []), 1) == "TYPE_POISON", "unexpected Bulbasaur second type")
	_assert(_constant_symbol_at(bulbasaur.get("abilities", []), 0) == "ABILITY_OVERGROW", "unexpected Bulbasaur first ability")
	_assert(_constant_symbol_at(bulbasaur.get("abilities", []), 2) == "ABILITY_CHLOROPHYLL", "unexpected Bulbasaur hidden ability")
	_assert(_constant_symbol_at(bulbasaur.get("egg_groups", []), 0) == "EGG_GROUP_MONSTER", "unexpected Bulbasaur first egg group")
	_assert(_constant_symbol_at(bulbasaur.get("egg_groups", []), 1) == "EGG_GROUP_GRASS", "unexpected Bulbasaur second egg group")

	var references = bulbasaur.get("source_references", {})
	_assert(String(references.get("front_pic", "")) == "gMonFrontPic_Bulbasaur", "expected Bulbasaur front pic source symbol")
	_assert(String(references.get("palette", "")) == "gMonPalette_Bulbasaur", "expected Bulbasaur palette source symbol")
	_assert(String(references.get("level_up_learnset", "")) == "sBulbasaurLevelUpLearnset", "expected Bulbasaur learnset source symbol")
	_assert(String(references.get("evolutions", "")).contains("SPECIES_IVYSAUR"), "expected Bulbasaur evolution source symbol")

	var unown := registry.get_species_record("SPECIES_UNOWN")
	_assert(String(unown.get("initializer_kind", "")) == "macro_call", "expected Unown macro initializer record")
	_assert(String(unown.get("evaluation_status", "")) == "partial", "expected Unown partial status")
	_assert(int(unown.get("id", 0)) > 0, "expected Unown species id")

	var egg := registry.get_species_record("SPECIES_EGG")
	_assert(String(egg.get("symbol", "")) == "SPECIES_EGG", "expected Egg species record")
	_assert(int(egg.get("id", -1)) == 1573, "unexpected Egg species id")

	if _failed:
		return

	print(JSON.stringify({
		"data_registry_species_smoke": "ok",
		"species_count": int(stats.get("species_count", 0)),
		"struct_initializer_count": int(stats.get("struct_initializer_count", 0)),
		"macro_initializer_count": int(stats.get("macro_initializer_count", 0)),
		"bulbasaur_exp_yield": int(bulbasaur.get("exp_yield", 0)),
	}))
	registry.free()
	quit(0)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true
	quit(1)


func _constant_symbol_at(records, index: int) -> String:
	if typeof(records) != TYPE_ARRAY:
		return ""
	if records.size() <= index:
		return ""
	var record = records[index]
	if typeof(record) != TYPE_DICTIONARY:
		return ""
	return String(record.get("symbol", ""))
