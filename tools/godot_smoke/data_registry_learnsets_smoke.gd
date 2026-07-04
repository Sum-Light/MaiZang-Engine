extends SceneTree

const DATA_REGISTRY_SCRIPT := preload("res://scripts/autoload/data_registry.gd")

var _failed := false


func _init() -> void:
	var registry = DATA_REGISTRY_SCRIPT.new()
	registry._ready()

	var learnsets_data := registry.get_learnsets_data()
	var stats = learnsets_data.get("stats", {})
	var source = learnsets_data.get("source", {})
	var selection := _dict_field(source, "selection")
	_assert(typeof(learnsets_data) == TYPE_DICTIONARY and not learnsets_data.is_empty(), "expected learnset data")
	_assert(typeof(stats) == TYPE_DICTIONARY, "expected learnset stats")
	_assert(String(selection.get("active_generation", "")) == "GEN_9", "expected active GEN_9 learnsets")
	_assert(int(stats.get("learnset_count", 0)) > 1000, "expected broad learnset coverage")
	_assert(int(stats.get("move_entry_count", 0)) > 10000, "expected broad learnset move coverage")
	_assert(int(stats.get("warning_count", -1)) == 0, "expected no learnset warnings")
	_assert(int(stats.get("unresolved_move_count", -1)) == 0, "expected no unresolved learnset moves")

	var geodude := registry.get_level_up_learnset_for_species("GEODUDE")
	var geodude_moves := _array_field(geodude, "moves")
	_assert(String(geodude.get("label", "")) == "sGeodudeLevelUpLearnset", "expected Geodude learnset label")
	_assert(geodude_moves.size() >= 8, "expected Geodude learnset moves")
	_assert(_has_level_move(geodude_moves, 1, "MOVE_TACKLE"), "expected Geodude Tackle at level 1")
	_assert(_has_level_move(geodude_moves, 12, "MOVE_BULLDOZE"), "expected Geodude Bulldoze at level 12")
	_assert(_has_level_move(geodude_moves, 18, "MOVE_SMACK_DOWN"), "expected Geodude Smack Down at level 18")
	_assert(_has_level_move(geodude_moves, 24, "MOVE_SELF_DESTRUCT"), "expected Geodude Self-Destruct at level 24")

	var torchic := registry.get_level_up_learnset_for_species("SPECIES_TORCHIC")
	var torchic_moves := _array_field(torchic, "moves")
	_assert(String(torchic.get("label", "")) == "sTorchicLevelUpLearnset", "expected Torchic learnset label")
	_assert(_has_level_move(torchic_moves, 1, "MOVE_SCRATCH"), "expected Torchic Scratch")
	_assert(_has_level_move(torchic_moves, 3, "MOVE_EMBER"), "expected Torchic Ember")

	if _failed:
		return

	print(JSON.stringify({
		"data_registry_learnsets_smoke": "ok",
		"learnset_count": int(stats.get("learnset_count", 0)),
		"move_entry_count": int(stats.get("move_entry_count", 0)),
		"geodude_move_count": geodude_moves.size(),
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


func _has_level_move(moves: Array, level: int, move_symbol: String) -> bool:
	for entry in moves:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var move = entry.get("move", {})
		if typeof(move) != TYPE_DICTIONARY:
			continue
		if int(entry.get("level", -1)) == level and String(move.get("symbol", "")) == move_symbol:
			return true
	return false
