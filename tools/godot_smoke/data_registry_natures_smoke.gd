extends SceneTree

const DATA_REGISTRY_SCRIPT := preload("res://scripts/autoload/data_registry.gd")

var _failed := false


func _init() -> void:
	var registry = DATA_REGISTRY_SCRIPT.new()
	registry._ready()

	var natures_data := registry.get_natures_data()
	var stats = natures_data.get("stats", {})
	_assert(typeof(natures_data) == TYPE_DICTIONARY and not natures_data.is_empty(), "expected nature data")
	_assert(typeof(stats) == TYPE_DICTIONARY, "expected nature stats")
	_assert(int(stats.get("nature_count", 0)) == 25, "unexpected nature count")
	_assert(int(stats.get("neutral_nature_count", 0)) == 5, "unexpected neutral nature count")
	_assert(int(stats.get("non_neutral_nature_count", 0)) == 20, "unexpected non-neutral nature count")
	_assert(int(stats.get("warning_count", -1)) == 0, "expected no nature warnings")
	_assert(int(stats.get("unsupported_field_count", -1)) == 0, "expected no unsupported nature fields")
	_assert(int(stats.get("unresolved_stat_count", -1)) == 0, "expected no unresolved nature stats")

	var hardy := registry.get_nature_record("HARDY")
	var adamant := registry.get_nature_record("NATURE_ADAMANT")
	var modest := registry.get_nature_record(15)
	var jolly := registry.get_nature_record_by_symbol("jolly")
	_assert(String(hardy.get("symbol", "")) == "NATURE_HARDY", "expected Hardy lookup")
	_assert(int(hardy.get("id", -1)) == 0, "unexpected Hardy id")
	_assert(bool(hardy.get("neutral", false)) == true, "expected Hardy neutral")
	_assert(_constant_symbol(hardy.get("stat_up", {})) == "STAT_ATK", "expected Hardy stat up")
	_assert(_constant_symbol(hardy.get("stat_down", {})) == "STAT_ATK", "expected Hardy stat down")
	_assert(String(adamant.get("symbol", "")) == "NATURE_ADAMANT", "expected Adamant lookup")
	_assert(int(adamant.get("id", -1)) == 3, "unexpected Adamant id")
	_assert(_constant_symbol(adamant.get("stat_up", {})) == "STAT_ATK", "expected Adamant attack boost")
	_assert(_constant_symbol(adamant.get("stat_down", {})) == "STAT_SPATK", "expected Adamant special attack drop")
	_assert(String(modest.get("symbol", "")) == "NATURE_MODEST", "expected Modest id lookup")
	_assert(_constant_symbol(modest.get("stat_up", {})) == "STAT_SPATK", "expected Modest special attack boost")
	_assert(_constant_symbol(modest.get("stat_down", {})) == "STAT_ATK", "expected Modest attack drop")
	_assert(String(_dict_field(modest, "name").get("display_text", "")).length() > 0, "expected Modest display name")
	_assert(String(jolly.get("symbol", "")) == "NATURE_JOLLY", "expected short Jolly lookup")
	_assert(_constant_symbol(jolly.get("stat_up", {})) == "STAT_SPEED", "expected Jolly speed boost")

	var palace := _dict_field(adamant, "battle_palace_percents")
	var cumulative := _array_field(palace, "stored_cumulative")
	_assert(cumulative.size() == 4, "expected Adamant palace cumulative values")
	_assert(int(cumulative[0]) == 38, "unexpected Adamant palace attack high-hp threshold")
	_assert(int(cumulative[1]) == 69, "unexpected Adamant palace defense high-hp threshold")
	_assert(int(cumulative[2]) == 70, "unexpected Adamant palace attack low-hp threshold")
	_assert(int(cumulative[3]) == 85, "unexpected Adamant palace defense low-hp threshold")
	var pokeblock_anim := _array_field(adamant, "poke_block_anim")
	_assert(_constant_symbol_at(pokeblock_anim, 0) == "ANIM_ADAMANT", "expected Adamant pokeblock anim")
	_assert(_constant_symbol_at(pokeblock_anim, 1) == "AFFINE_NONE", "expected Adamant affine anim")

	if _failed:
		return

	print(JSON.stringify({
		"data_registry_natures_smoke": "ok",
		"nature_count": int(stats.get("nature_count", 0)),
		"adamant_stat_up": _constant_symbol(adamant.get("stat_up", {})),
	}))
	registry.free()
	quit(0)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true
	quit(1)


func _dict_field(record, field_name: String) -> Dictionary:
	if typeof(record) != TYPE_DICTIONARY:
		return {}
	var value = record.get(field_name, {})
	return value if typeof(value) == TYPE_DICTIONARY else {}


func _array_field(record: Dictionary, field_name: String) -> Array:
	var value = record.get(field_name, [])
	return value if typeof(value) == TYPE_ARRAY else []


func _constant_symbol(value) -> String:
	if typeof(value) != TYPE_DICTIONARY:
		return ""
	return String(value.get("symbol", ""))


func _constant_symbol_at(records, index: int) -> String:
	if typeof(records) != TYPE_ARRAY:
		return ""
	if records.size() <= index:
		return ""
	return _constant_symbol(records[index])
