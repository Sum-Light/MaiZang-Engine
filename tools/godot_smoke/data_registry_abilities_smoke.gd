extends SceneTree

const DATA_REGISTRY_SCRIPT := preload("res://scripts/autoload/data_registry.gd")

var _failed := false


func _init() -> void:
	var registry = DATA_REGISTRY_SCRIPT.new()
	registry._ready()

	var abilities_data := registry.get_abilities_data()
	var stats = abilities_data.get("stats", {})
	_assert(typeof(abilities_data) == TYPE_DICTIONARY and not abilities_data.is_empty(), "expected abilities data")
	_assert(typeof(stats) == TYPE_DICTIONARY, "expected ability stats")
	_assert(int(stats.get("ability_count", 0)) == 311, "unexpected ability count")
	_assert(int(stats.get("abilities_with_present_ai_rating", 0)) == 310, "unexpected ability ai rating count")
	_assert(int(stats.get("abilities_with_any_present_flag", 0)) == 122, "unexpected present ability flag count")
	_assert(int(stats.get("abilities_with_any_true_flag", 0)) == 120, "unexpected true ability flag count")
	_assert(int(stats.get("preprocessor_decision_count", -1)) == 0, "unexpected ability preprocessor decision count")
	_assert(int(stats.get("preprocessor_warning_count", -1)) == 0, "expected no ability preprocessor warnings")
	_assert(int(stats.get("warning_count", -1)) == 0, "expected no ability export warnings")
	_assert(int(stats.get("unsupported_field_count", -1)) == 0, "expected no unsupported ability fields")

	var none := registry.get_ability_record("ABILITY_NONE")
	var sturdy := registry.get_ability_record("ABILITY_STURDY")
	var sturdy_by_id := registry.get_ability_record(5)
	var sturdy_by_short_name := registry.get_ability_record("sturdy")
	_assert(String(none.get("symbol", "")) == "ABILITY_NONE", "expected ABILITY_NONE record")
	_assert(int(none.get("id", -1)) == 0, "unexpected ABILITY_NONE id")
	_assert(String(_text_field(none, "name").get("display_text", "")) == "-------", "unexpected ABILITY_NONE name")
	_assert(String(_text_field(none, "description").get("display_text", "")).length() > 0, "expected ABILITY_NONE description")
	_assert(_bool_field(none.get("flags", {}), "cant_be_swapped"), "expected ABILITY_NONE cant_be_swapped")
	_assert(_bool_field(none.get("flags", {}), "cant_be_traced"), "expected ABILITY_NONE cant_be_traced")
	_assert(not _bool_field(none.get("flags", {}), "breakable"), "expected ABILITY_NONE default breakable false")
	_assert(not sturdy.is_empty(), "expected Sturdy ability record")
	_assert(String(sturdy_by_id.get("symbol", "")) == "ABILITY_STURDY", "expected ability id lookup")
	_assert(String(sturdy_by_short_name.get("symbol", "")) == "ABILITY_STURDY", "expected short ability symbol lookup")
	_assert(int(sturdy.get("id", -1)) == 5, "unexpected Sturdy id")
	_assert(int(sturdy.get("ai_rating", 0)) == 6, "unexpected Sturdy ai rating")
	_assert(_bool_field(sturdy.get("flags", {}), "breakable"), "expected Sturdy breakable flag")
	_assert(not _bool_field(sturdy.get("flags", {}), "cant_be_copied"), "expected Sturdy default cant_be_copied false")

	var truant := registry.get_ability_record("truant")
	_assert(String(truant.get("symbol", "")) == "ABILITY_TRUANT", "expected Truant ability record")
	_assert(int(truant.get("id", -1)) == 54, "unexpected Truant id")
	_assert(int(truant.get("ai_rating", 0)) == -2, "unexpected Truant ai rating")
	_assert(_bool_field(truant.get("flags", {}), "cant_be_overwritten"), "expected Truant cant_be_overwritten")

	var forecast := registry.get_ability_record("ABILITY_FORECAST")
	_assert(int(forecast.get("id", -1)) == 59, "unexpected Forecast id")
	_assert(_bool_field(forecast.get("flags", {}), "cant_be_copied"), "expected Forecast cant_be_copied")
	_assert(_bool_field(forecast.get("flags", {}), "cant_be_traced"), "expected Forecast cant_be_traced from GEN_4 expression")
	_assert(_bool_field(forecast.get("flags", {}), "fails_on_imposter"), "expected Forecast fails_on_imposter from GEN_5 expression")

	var gulp_missile := registry.get_ability_record("ABILITY_GULP_MISSILE")
	_assert(int(gulp_missile.get("id", -1)) == 241, "unexpected Gulp Missile id")
	_assert(not _bool_field(gulp_missile.get("flags", {}), "cant_be_swapped"), "expected Gulp Missile GEN_9 cant_be_swapped false")
	_assert(not _bool_field(gulp_missile.get("flags", {}), "cant_be_copied"), "expected Gulp Missile GEN_9 cant_be_copied false")
	_assert(not _bool_field(gulp_missile.get("flags", {}), "cant_be_traced"), "expected Gulp Missile GEN_9 cant_be_traced false")
	_assert(_bool_field(gulp_missile.get("flags", {}), "cant_be_suppressed"), "expected Gulp Missile cant_be_suppressed")
	_assert(_bool_field(gulp_missile.get("flags", {}), "cant_be_overwritten"), "expected Gulp Missile cant_be_overwritten")
	_assert(_bool_field(gulp_missile.get("flags", {}), "fails_on_imposter"), "expected Gulp Missile fails_on_imposter")

	var libero := registry.get_ability_record("ABILITY_LIBERO")
	_assert(int(libero.get("id", -1)) == 236, "unexpected Libero id")
	_assert(int(libero.get("ai_rating", -1)) == 0, "expected Libero ai rating default")
	_assert(_array_field(libero, "defaulted_fields").has("ai_rating"), "expected Libero ai rating default marker")

	var poison_puppeteer := registry.get_ability_record("ABILITY_POISON_PUPPETEER")
	_assert(String(poison_puppeteer.get("symbol", "")) == "ABILITY_POISON_PUPPETEER", "expected Poison Puppeteer record")
	_assert(int(poison_puppeteer.get("id", -1)) == 310, "unexpected Poison Puppeteer id")
	_assert(_bool_field(poison_puppeteer.get("flags", {}), "cant_be_copied"), "expected Poison Puppeteer cant_be_copied")
	_assert(_bool_field(poison_puppeteer.get("flags", {}), "cant_be_swapped"), "expected Poison Puppeteer cant_be_swapped")
	_assert(_bool_field(poison_puppeteer.get("flags", {}), "cant_be_traced"), "expected Poison Puppeteer cant_be_traced")

	if _failed:
		return

	print(JSON.stringify({
		"data_registry_abilities_smoke": "ok",
		"ability_count": int(stats.get("ability_count", 0)),
		"sturdy_ai_rating": int(sturdy.get("ai_rating", 0)),
		"gulp_missile_cant_be_copied": _bool_field(gulp_missile.get("flags", {}), "cant_be_copied"),
	}))
	registry.free()
	quit(0)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true
	quit(1)


func _text_field(record: Dictionary, field_name: String) -> Dictionary:
	var value = record.get(field_name, {})
	return value if typeof(value) == TYPE_DICTIONARY else {}


func _array_field(record: Dictionary, field_name: String) -> Array:
	var value = record.get(field_name, [])
	return value if typeof(value) == TYPE_ARRAY else []


func _bool_field(record, field_name: String) -> bool:
	if typeof(record) != TYPE_DICTIONARY:
		return false
	return bool(record.get(field_name, false))
