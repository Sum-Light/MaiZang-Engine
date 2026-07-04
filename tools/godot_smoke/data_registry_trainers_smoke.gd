extends SceneTree

const DATA_REGISTRY_SCRIPT := preload("res://scripts/autoload/data_registry.gd")

var _failed := false


func _init() -> void:
	var registry = DATA_REGISTRY_SCRIPT.new()
	registry._ready()

	var trainers_data := registry.get_trainers_data()
	var stats = trainers_data.get("stats", {})
	_assert(typeof(trainers_data) == TYPE_DICTIONARY and not trainers_data.is_empty(), "expected trainer data")
	_assert(typeof(stats) == TYPE_DICTIONARY, "expected trainer stats")
	_assert(int(stats.get("trainer_count", 0)) == 855, "unexpected trainer count")
	_assert(int(stats.get("trainers_count_constant", 0)) == 855, "unexpected TRAINERS_COUNT")
	_assert(int(stats.get("highest_trainer_id", 0)) == 854, "unexpected highest trainer id")
	_assert(int(stats.get("party_mon_count", 0)) == 1825, "unexpected trainer party mon count")
	_assert(int(stats.get("double_battle_count", 0)) == 77, "unexpected double battle count")
	_assert(int(stats.get("trainer_with_items_count", 0)) == 141, "unexpected trainer item count")
	_assert(int(stats.get("trainer_with_ai_flags_count", 0)) == 839, "unexpected AI trainer count")
	_assert(int(stats.get("trainer_with_mugshot_count", 0)) == 5, "unexpected mugshot trainer count")
	_assert(int(stats.get("explicit_move_mon_count", 0)) == 436, "unexpected explicit move mon count")
	_assert(int(stats.get("default_move_mon_count", 0)) == 1389, "unexpected default move mon count")
	_assert(int(stats.get("held_item_mon_count", 0)) == 142, "unexpected held item mon count")
	_assert(int(stats.get("unique_species_count", 0)) == 208, "unexpected unique trainer species count")
	_assert(int(stats.get("unique_move_count", 0)) == 210, "unexpected unique trainer move count")
	_assert(int(stats.get("warning_count", -1)) == 0, "expected no trainer warnings")
	_assert(int(stats.get("unsupported_field_count", -1)) == 0, "expected no unsupported trainer fields")
	_assert(int(stats.get("unresolved_constant_count", -1)) == 0, "expected no unresolved trainer constants")

	var config := _dict_field(trainers_data, "config")
	var target := _dict_field(config, "target")
	var party_config := _dict_field(config, "party")
	var battle_config := _dict_field(config, "battle")
	_assert(target.get("is_frlg", true) == false, "expected Emerald trainer target")
	_assert(int(target.get("max_trainers_count", 0)) == 864, "unexpected MAX_TRAINERS_COUNT")
	_assert(int(party_config.get("party_size", 0)) == 6, "unexpected PARTY_SIZE")
	_assert(int(party_config.get("max_mon_moves", 0)) == 4, "unexpected MAX_MON_MOVES")
	_assert(int(battle_config.get("max_dynamax_level", 0)) == 10, "unexpected MAX_DYNAMAX_LEVEL")
	_assert(battle_config.get("trainer_mon_random_ability", true) == false, "expected source random ability config disabled")

	var none := registry.get_trainer_record("TRAINER_NONE")
	_assert(String(none.get("symbol", "")) == "TRAINER_NONE", "expected TRAINER_NONE")
	_assert(int(none.get("id", -1)) == 0, "unexpected TRAINER_NONE id")
	_assert(_array_field(none, "party").is_empty(), "expected TRAINER_NONE empty party")

	var sawyer := registry.get_trainer_record("sawyer_1")
	var sawyer_by_id := registry.get_trainer_record(1)
	var sawyer_party := _array_field(sawyer, "party")
	var sawyer_mon := _array_dict(sawyer_party, 0)
	_assert(String(sawyer_by_id.get("symbol", "")) == "TRAINER_SAWYER_1", "expected trainer id lookup")
	_assert(String(sawyer.get("symbol", "")) == "TRAINER_SAWYER_1", "expected short trainer symbol lookup")
	_assert(int(_dict_field(sawyer, "party_size").get("value", -1)) == 1, "unexpected Sawyer party size")
	_assert(int(sawyer.get("ai_flags_mask", -1)) == 7, "unexpected Sawyer Basic Trainer AI mask")
	_assert(String(_dict_field(sawyer_mon, "species").get("symbol", "")) == "SPECIES_GEODUDE", "expected Sawyer Geodude")
	_assert(int(_dict_field(sawyer_mon, "level").get("value", -1)) == 21, "unexpected Sawyer Geodude level")
	_assert(int(_dict_field(sawyer_mon, "ivs").get("packed_value", -1)) == 0, "unexpected Sawyer Geodude IV pack")
	_assert(String(_dict_field(sawyer_mon, "held_item").get("symbol", "")) == "ITEM_NONE", "expected Sawyer held item default")
	_assert(String(_dict_field(sawyer_mon, "move_source_behavior").get("kind", "")) == "level_up_default", "expected Sawyer default move behavior")

	var gabby := registry.get_trainer_record("gabby_and_ty_1")
	var gabby_party := _array_field(gabby, "party")
	var gabby_mon := _array_dict(gabby_party, 0)
	_assert(int(gabby.get("id", -1)) == 51, "unexpected Gabby and Ty id")
	_assert(_dict_field(gabby, "battle_type").get("is_double", false) == true, "expected Gabby and Ty double battle")
	_assert(gabby_party.size() == 2, "expected Gabby and Ty party size")
	_assert(int(gabby.get("ai_flags_mask", -1)) == 1, "unexpected Gabby and Ty AI mask")
	_assert(String(_dict_field(gabby_mon, "species").get("symbol", "")) == "SPECIES_MAGNEMITE", "expected Gabby and Ty Magnemite")
	_assert(int(_dict_field(gabby_mon, "ivs").get("packed_value", -1)) == 207820998, "unexpected Gabby and Ty IV pack")

	var winona := registry.get_trainer_record_by_id(790)
	var winona_party := _array_field(winona, "party")
	var winona_mon := _array_dict(winona_party, 0)
	var winona_moves := _array_field(winona_mon, "moves")
	var winona_items := _array_field(_dict_field(winona, "items"), "explicit")
	_assert(String(winona.get("symbol", "")) == "TRAINER_WINONA_2", "expected Winona id lookup")
	_assert(_dict_field(winona, "battle_type").get("is_double", false) == true, "expected Winona double battle")
	_assert(winona_party.size() == 5, "expected Winona party count")
	_assert(winona_items.size() == 3, "expected Winona explicit item count")
	_assert(String(_dict_field(_array_dict(winona_items, 0), "source").get("file", "")) == "src/data/trainers.party", "expected Winona item source")
	_assert(String(_dict_field(winona_mon, "species").get("symbol", "")) == "SPECIES_DRATINI", "expected Winona lead species")
	_assert(String(_dict_field(winona_mon, "held_item").get("symbol", "")) == "ITEM_SITRUS_BERRY", "expected Winona lead held item")
	_assert(winona_moves.size() == 4, "expected Winona explicit move count")
	_assert(String(_array_dict(winona_moves, 0).get("symbol", "")) == "MOVE_THUNDER_WAVE", "expected Winona move 1")
	_assert(String(_array_dict(winona_moves, 3).get("symbol", "")) == "MOVE_ICE_BEAM", "expected Winona move 4")
	_assert(String(_dict_field(winona_mon, "move_source_behavior").get("kind", "")) == "explicit", "expected Winona explicit move behavior")

	var wallace := registry.get_trainer_record("wallace")
	_assert(int(wallace.get("id", -1)) == 335, "unexpected Wallace trainer id")
	_assert(String(_dict_field(wallace, "mugshot").get("symbol", "")) == "MUGSHOT_COLOR_YELLOW", "expected Wallace mugshot color")

	if _failed:
		return

	print(JSON.stringify({
		"data_registry_trainers_smoke": "ok",
		"trainer_count": int(stats.get("trainer_count", 0)),
		"party_mon_count": int(stats.get("party_mon_count", 0)),
		"winona_move_count": winona_moves.size(),
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


func _array_dict(records: Array, index: int) -> Dictionary:
	if index < 0 or index >= records.size():
		return {}
	var value = records[index]
	return value if typeof(value) == TYPE_DICTIONARY else {}
