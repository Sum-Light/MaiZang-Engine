extends SceneTree

const DATA_REGISTRY_SCRIPT := preload("res://scripts/autoload/data_registry.gd")
const BATTLE_ENGINE_SCRIPT := preload("res://scripts/autoload/battle_engine.gd")

var _failed := false


func _init() -> void:
	var registry = DATA_REGISTRY_SCRIPT.new()
	registry._ready()

	var engine = BATTLE_ENGINE_SCRIPT.new()
	engine.configure_registry(registry)

	var torchic := engine.create_battle_mon("SPECIES_TORCHIC", 5, {
		"moves": ["MOVE_EMBER", "MOVE_TACKLE"],
	})
	var treecko := engine.create_battle_mon("SPECIES_TREECKO", 5, {})
	var gastly := engine.create_battle_mon("SPECIES_GASTLY", 5, {})
	_assert(String(torchic.get("status", "")) == "ok", "expected Torchic battle mon")
	_assert(String(treecko.get("status", "")) == "ok", "expected Treecko battle mon")
	_assert(String(gastly.get("status", "")) == "ok", "expected Gastly battle mon")
	_assert(int(_dict_field(torchic, "stats").get("hp", 0)) == 21, "unexpected Torchic hp")
	_assert(int(_dict_field(torchic, "stats").get("attack", 0)) == 12, "unexpected Torchic attack")
	_assert(int(_dict_field(torchic, "stats").get("sp_attack", 0)) == 13, "unexpected Torchic sp attack")
	_assert(int(_dict_field(treecko, "stats").get("hp", 0)) == 20, "unexpected Treecko hp")
	_assert(int(_dict_field(treecko, "stats").get("sp_defense", 0)) == 12, "unexpected Treecko sp defense")

	var ember := _array_dict(_array_field(torchic, "moves"), 0)
	var ember_damage := engine.calculate_basic_damage(torchic, treecko, ember, {"damage_roll_percent": 100})
	_assert(String(ember_damage.get("status", "")) == "ok", "expected Ember damage result")
	_assert(int(ember_damage.get("base_damage", 0)) == 5, "unexpected Ember base damage")
	_assert(int(ember_damage.get("after_stab", 0)) == 7, "unexpected Ember STAB damage")
	_assert(int(ember_damage.get("damage", 0)) == 14, "unexpected Ember final damage")
	_assert(String(_dict_field(ember_damage, "effectiveness").get("result", "")) == "super_effective", "expected Ember super-effective result")

	var ember_turn := engine.use_move(torchic, treecko, 0, {"damage_roll_percent": 100})
	var torchic_after := _dict_field(ember_turn, "attacker")
	var treecko_after := _dict_field(ember_turn, "defender")
	var used_ember := _array_dict(_array_field(torchic_after, "moves"), 0)
	_assert(String(ember_turn.get("status", "")) == "ok", "expected Ember turn result")
	_assert(int(_dict_field(ember_turn, "damage").get("damage", 0)) == 14, "expected Ember turn damage")
	_assert(int(used_ember.get("current_pp", -1)) == 24, "expected Ember PP decrement")
	_assert(int(treecko_after.get("hp", -1)) == 6, "expected Treecko HP after Ember")
	_assert(bool(treecko_after.get("fainted", true)) == false, "expected Treecko still standing")

	var tackle_turn := engine.use_move(torchic, gastly, 1, {"damage_roll_percent": 100})
	var gastly_after := _dict_field(tackle_turn, "defender")
	_assert(String(tackle_turn.get("status", "")) == "ok", "expected Tackle turn result")
	_assert(int(_dict_field(tackle_turn, "damage").get("damage", -1)) == 0, "expected Normal vs Ghost immunity")
	_assert(int(gastly_after.get("hp", -1)) == int(gastly.get("hp", -2)), "expected Gastly HP unchanged")
	_assert(String(_dict_field(_dict_field(tackle_turn, "damage"), "effectiveness").get("result", "")) == "immune", "expected immune effectiveness")

	var wallace_result := engine.create_trainer_party("TRAINER_WALLACE")
	var wallace_party := _array_field(wallace_result, "party")
	var wallace_lead := _array_dict(wallace_party, 0)
	var wallace_moves := _array_field(wallace_lead, "moves")
	_assert(String(wallace_result.get("status", "")) == "ok", "expected Wallace party")
	_assert(wallace_party.size() == 6, "expected Wallace six-mon party")
	_assert(String(wallace_lead.get("species", "")) == "SPECIES_WAILORD", "expected Wallace lead Wailord")
	_assert(wallace_moves.size() == 4, "expected Wallace explicit moves")
	_assert(String(_array_dict(wallace_moves, 0).get("symbol", "")) == "MOVE_RAIN_DANCE", "expected Wallace lead Rain Dance")
	_assert(int(_array_dict(wallace_moves, 0).get("max_pp", -1)) == 5, "expected Rain Dance PP")
	_assert(String(_array_dict(wallace_moves, 1).get("symbol", "")) == "MOVE_WATER_SPOUT", "expected Wallace lead Water Spout")
	_assert(int(_array_dict(wallace_moves, 1).get("power", -1)) == 150, "expected Water Spout power")
	_assert(_array_field(wallace_result, "unsupported").is_empty(), "expected Wallace explicit party to avoid unsupported default moves")

	var sawyer_result := engine.create_trainer_party("TRAINER_SAWYER_1")
	var sawyer_party := _array_field(sawyer_result, "party")
	var sawyer_lead := _array_dict(sawyer_party, 0)
	var sawyer_moves := _array_field(sawyer_lead, "moves")
	_assert(sawyer_party.size() == 1, "expected Sawyer one-mon party")
	_assert(String(sawyer_lead.get("species", "")) == "SPECIES_GEODUDE", "expected Sawyer Geodude")
	_assert(sawyer_moves.size() == 4, "expected Sawyer default moves from level-up learnset")
	_assert(String(_array_dict(sawyer_moves, 0).get("symbol", "")) == "MOVE_ROLLOUT", "expected Sawyer Rollout")
	_assert(String(_array_dict(sawyer_moves, 1).get("symbol", "")) == "MOVE_BULLDOZE", "expected Sawyer Bulldoze")
	_assert(String(_array_dict(sawyer_moves, 2).get("symbol", "")) == "MOVE_ROCK_THROW", "expected Sawyer Rock Throw")
	_assert(String(_array_dict(sawyer_moves, 3).get("symbol", "")) == "MOVE_SMACK_DOWN", "expected Sawyer Smack Down")
	_assert(not _has_unsupported(sawyer_result, "missing_level_up_learnset_data"), "expected Sawyer learnset support")

	var battle_state := engine.create_single_battle_state([torchic], wallace_party)
	_assert(String(battle_state.get("status", "")) == "ok", "expected single battle state")
	_assert(String(battle_state.get("battle_type", "")) == "single", "expected single battle type")
	_assert(_array_field(battle_state, "player_party").size() == 1, "expected player party in battle state")
	_assert(_array_field(battle_state, "opponent_party").size() == 6, "expected opponent party in battle state")

	if _failed:
		return

	print(JSON.stringify({
		"battle_engine_smoke": "ok",
		"ember_damage": int(ember_damage.get("damage", 0)),
		"treecko_hp_after_ember": int(treecko_after.get("hp", 0)),
		"wallace_party_size": wallace_party.size(),
	}))
	engine.free()
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


func _has_unsupported(record: Dictionary, code: String) -> bool:
	var unsupported := _array_field(record, "unsupported")
	for item in unsupported:
		if typeof(item) == TYPE_DICTIONARY and String(item.get("code", "")) == code:
			return true
	return false
