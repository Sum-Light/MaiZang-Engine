extends SceneTree

const DATA_REGISTRY_SCRIPT := preload("res://scripts/autoload/data_registry.gd")

var _failed := false


func _init() -> void:
	var registry = DATA_REGISTRY_SCRIPT.new()
	registry._ready()

	var evolutions_data := registry.get_evolutions_data()
	var stats = evolutions_data.get("stats", {})
	_assert(typeof(evolutions_data) == TYPE_DICTIONARY and not evolutions_data.is_empty(), "expected evolution data")
	_assert(typeof(stats) == TYPE_DICTIONARY, "expected evolution stats")
	_assert(int(stats.get("species_with_evolutions_count", 0)) == 486, "unexpected species evolution count")
	_assert(int(stats.get("evolution_entry_count", 0)) == 647, "unexpected evolution entry count")
	_assert(int(stats.get("condition_entry_count", 0)) == 291, "unexpected evolution condition count")
	_assert(int(stats.get("split_evolution_count", 0)) == 1, "unexpected split evolution count")
	_assert(int(stats.get("warning_count", -1)) == 0, "expected no evolution warnings")
	_assert(int(stats.get("unresolved_value_count", -1)) == 0, "expected no unresolved evolution values")

	var bulbasaur := registry.get_evolution_record("BULBASAUR")
	var bulbasaur_by_id := registry.get_evolution_record(1)
	var bulbasaur_evos := registry.get_evolutions_for_species("SPECIES_BULBASAUR")
	_assert(String(bulbasaur.get("species_symbol", "")) == "SPECIES_BULBASAUR", "expected Bulbasaur evolution record")
	_assert(String(bulbasaur_by_id.get("species_symbol", "")) == "SPECIES_BULBASAUR", "expected Bulbasaur id lookup")
	_assert(bulbasaur_evos.size() == 1, "expected one Bulbasaur evolution")
	if bulbasaur_evos.size() > 0:
		var ivy = bulbasaur_evos[0]
		_assert(_method_symbol(ivy) == "EVO_LEVEL", "expected Bulbasaur level evolution")
		_assert(_value_field(ivy.get("param", {})) == 16, "expected Bulbasaur level 16")
		_assert(_target_symbol(ivy) == "SPECIES_IVYSAUR", "expected Bulbasaur target Ivysaur")

	var ivysaur_pre := registry.get_pre_evolution_records_for_species("IVYSAUR")
	_assert(_has_pre_evolution(ivysaur_pre, "SPECIES_BULBASAUR", "SPECIES_IVYSAUR"), "expected Ivysaur pre-evolution from Bulbasaur")

	var tyrogue_evos := registry.get_evolutions_for_species("TYROGUE")
	_assert(tyrogue_evos.size() == 3, "expected Tyrogue split stat evolutions")
	if tyrogue_evos.size() == 3:
		_assert(_target_symbol(tyrogue_evos[0]) == "SPECIES_HITMONCHAN", "expected Tyrogue source order target 0")
		_assert(_condition_symbol_at(tyrogue_evos[0], 0) == "IF_ATK_LT_DEF", "expected Tyrogue low attack condition")
		_assert(_target_symbol(tyrogue_evos[1]) == "SPECIES_HITMONLEE", "expected Tyrogue source order target 1")
		_assert(_condition_symbol_at(tyrogue_evos[1], 0) == "IF_ATK_GT_DEF", "expected Tyrogue high attack condition")
		_assert(_target_symbol(tyrogue_evos[2]) == "SPECIES_HITMONTOP", "expected Tyrogue source order target 2")
		_assert(_condition_symbol_at(tyrogue_evos[2], 0) == "IF_ATK_EQ_DEF", "expected Tyrogue equal attack condition")

	var eevee_evos := registry.get_evolutions_for_species("EEVEE")
	var sylveon := _find_evolution_by_target(eevee_evos, "SPECIES_SYLVEON")
	_assert(eevee_evos.size() == 10, "expected source Eevee evolution options")
	_assert(not sylveon.is_empty(), "expected Sylveon evolution")
	_assert(_method_symbol(sylveon) == "EVO_LEVEL", "expected Sylveon level evolution")
	_assert(_condition_symbol_at(sylveon, 0) == "IF_MIN_FRIENDSHIP", "expected Sylveon friendship condition")
	_assert(_condition_arg_value(sylveon, 0, "arg1") == 160, "expected source friendship threshold")
	_assert(_condition_symbol_at(sylveon, 1) == "IF_KNOWS_MOVE_TYPE", "expected Sylveon move-type condition")
	_assert(_condition_arg_symbol(sylveon, 1, "arg1") == "TYPE_FAIRY", "expected Sylveon fairy move type")

	var nincada_evos := registry.get_evolutions_for_species("NINCADA")
	var shedinja := _find_evolution_by_target(nincada_evos, "SPECIES_SHEDINJA")
	_assert(nincada_evos.size() == 2, "expected Nincada primary and split evolutions")
	_assert(not shedinja.is_empty(), "expected Shedinja split evolution")
	_assert(_method_symbol(shedinja) == "EVO_SPLIT_FROM_EVO", "expected Shedinja split method")
	_assert(_param_symbol(shedinja) == "SPECIES_NINJASK", "expected split post-evolution param")
	_assert(_condition_symbol_at(shedinja, 0) == "IF_BAG_ITEM_COUNT", "expected Shedinja bag-item condition")
	_assert(_condition_arg_symbol(shedinja, 0, "arg1") == "ITEM_POKE_BALL", "expected Shedinja Poke Ball condition")
	_assert(_condition_arg_value(shedinja, 0, "arg2") == 1, "expected Shedinja Poke Ball count")

	var shedinja_pre := registry.get_pre_evolution_records_for_species(292)
	_assert(_has_pre_evolution(shedinja_pre, "SPECIES_NINCADA", "SPECIES_SHEDINJA"), "expected Shedinja pre-evolution by id")

	if _failed:
		return

	print(JSON.stringify({
		"data_registry_evolutions_smoke": "ok",
		"species_with_evolutions_count": int(stats.get("species_with_evolutions_count", 0)),
		"evolution_entry_count": int(stats.get("evolution_entry_count", 0)),
		"condition_entry_count": int(stats.get("condition_entry_count", 0)),
		"eevee_evolution_count": eevee_evos.size(),
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


func _array_field(record, field_name: String) -> Array:
	if typeof(record) != TYPE_DICTIONARY:
		return []
	var value = record.get(field_name, [])
	return value if typeof(value) == TYPE_ARRAY else []


func _method_symbol(evolution) -> String:
	return String(_dict_field(evolution, "method").get("symbol", ""))


func _param_symbol(evolution) -> String:
	return String(_dict_field(evolution, "param").get("symbol", ""))


func _target_symbol(evolution) -> String:
	return String(_dict_field(evolution, "target_species").get("symbol", ""))


func _condition_symbol_at(evolution, index: int) -> String:
	var conditions := _array_field(evolution, "conditions")
	if index < 0 or index >= conditions.size():
		return ""
	return String(_dict_field(conditions[index], "condition").get("symbol", ""))


func _condition_arg_symbol(evolution, condition_index: int, arg_name: String) -> String:
	var condition := _condition_at(evolution, condition_index)
	if condition.is_empty():
		return ""
	return String(_dict_field(condition, arg_name).get("symbol", ""))


func _condition_arg_value(evolution, condition_index: int, arg_name: String) -> int:
	var condition := _condition_at(evolution, condition_index)
	if condition.is_empty():
		return -1
	return _value_field(_dict_field(condition, arg_name))


func _condition_at(evolution, index: int) -> Dictionary:
	var conditions := _array_field(evolution, "conditions")
	if index < 0 or index >= conditions.size():
		return {}
	var condition = conditions[index]
	return condition if typeof(condition) == TYPE_DICTIONARY else {}


func _value_field(record) -> int:
	if typeof(record) != TYPE_DICTIONARY:
		return -1
	if not record.has("value") or record.get("value") == null:
		return -1
	return int(record.get("value"))


func _find_evolution_by_target(evolutions: Array, target_symbol: String) -> Dictionary:
	for evolution in evolutions:
		if typeof(evolution) != TYPE_DICTIONARY:
			continue
		if _target_symbol(evolution) == target_symbol:
			return evolution
	return {}


func _has_pre_evolution(records: Array, source_symbol: String, target_symbol: String) -> bool:
	for record in records:
		if typeof(record) != TYPE_DICTIONARY:
			continue
		if String(record.get("source_species_symbol", "")) != source_symbol:
			continue
		var evolution = record.get("evolution", {})
		if typeof(evolution) == TYPE_DICTIONARY and _target_symbol(evolution) == target_symbol:
			return true
	return false
