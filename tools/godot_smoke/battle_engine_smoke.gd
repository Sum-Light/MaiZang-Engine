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

	var adamant_torchic := engine.create_battle_mon("SPECIES_TORCHIC", 5, {
		"nature": "NATURE_ADAMANT",
	})
	var modest_torchic := engine.create_battle_mon("SPECIES_TORCHIC", 5, {
		"nature": "NATURE_MODEST",
	})
	_assert(int(_dict_field(adamant_torchic, "stats").get("hp", 0)) == 21, "expected Adamant Torchic hp unchanged")
	_assert(int(_dict_field(adamant_torchic, "stats").get("attack", 0)) == 13, "expected Adamant Torchic attack boost")
	_assert(int(_dict_field(adamant_torchic, "stats").get("sp_attack", 0)) == 11, "expected Adamant Torchic special attack drop")
	_assert(String(_dict_field(adamant_torchic, "nature_info").get("stat_up", "")) == "STAT_ATK", "expected Adamant nature info attack boost")
	_assert(String(_dict_field(adamant_torchic, "nature_info").get("stat_down", "")) == "STAT_SPATK", "expected Adamant nature info special attack drop")
	_assert(not _has_unsupported(adamant_torchic, "non_neutral_nature_modifier_not_applied"), "expected source nature modifier support")
	_assert(not _has_unsupported(adamant_torchic, "missing_nature_data"), "expected generated nature data")
	_assert(int(_dict_field(modest_torchic, "stats").get("attack", 0)) == 10, "expected Modest Torchic attack drop")
	_assert(int(_dict_field(modest_torchic, "stats").get("sp_attack", 0)) == 14, "expected Modest Torchic special attack boost")

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

	var fainted_torchic := torchic.duplicate(true)
	fainted_torchic["hp"] = 0
	fainted_torchic["fainted"] = true
	var wild_battle := engine.create_wild_battle_state({
		"species": "SPECIES_WURMPLE",
		"species_id": 265,
		"level": 2,
		"area": "land_mons",
		"map": "MAP_ROUTE101",
		"record_label": "gRoute101",
		"slot_index": 0,
	}, [fainted_torchic, torchic])
	var wild_opponent := _array_dict(_array_field(wild_battle, "opponent_party"), 0)
	var wild_setup := _dict_field(wild_battle, "battle_setup")
	var wild_transition := _dict_field(wild_setup, "battle_transition")
	_assert(String(wild_battle.get("status", "")) == "ok", "expected wild battle state")
	_assert(String(wild_battle.get("battle_kind", "")) == "wild", "expected wild battle kind")
	_assert(String(wild_opponent.get("species", "")) == "SPECIES_WURMPLE", "expected Wurmple wild opponent")
	_assert(int(wild_opponent.get("level", 0)) == 2, "expected Wurmple wild level")
	_assert(_array_field(wild_battle, "opponent_party").size() == 1, "expected one wild opponent")
	_assert(int(_dict_field(wild_battle, "active").get("player", -1)) == 1, "expected first live player mon active")
	_assert(int(wild_setup.get("active_player_index", -1)) == 1, "expected setup active player index")
	_assert(String(wild_setup.get("battle_setup_function", "")) == "BattleSetup_StartWildBattle", "expected wild battle setup function")
	_assert(String(wild_transition.get("comparison", "")) == "enemy_lower", "expected lower wild transition branch")
	_assert(String(wild_transition.get("selected", "")) == "B_TRANSITION_SLICE", "expected normal lower wild transition")
	_assert(String(wild_transition.get("transition_type", "")) == "TRANSITION_TYPE_NORMAL", "expected normal transition type")
	_assert(int(wild_transition.get("table_column", -1)) == 0, "expected lower transition table column")
	_assert(_array_field(wild_battle, "unsupported").size() >= 1, "expected wild battle presentation unsupported metadata")

	var water_wild := engine.create_wild_battle_state({
		"species": "SPECIES_TENTACOOL",
		"species_id": 72,
		"level": 6,
		"area": "water_mons",
		"map": "MAP_ROUTE119",
		"record_label": "gRoute119",
		"slot_index": 0,
	}, [torchic], {
		"metatile_behavior": "MB_OCEAN_WATER",
		"map": "MAP_ROUTE119",
	})
	var water_transition := _dict_field(_dict_field(water_wild, "battle_setup"), "battle_transition")
	_assert(String(water_transition.get("comparison", "")) == "enemy_equal_or_higher", "expected equal-or-higher water branch")
	_assert(String(water_transition.get("transition_type", "")) == "TRANSITION_TYPE_WATER", "expected water transition type")
	_assert(String(water_transition.get("transition_type_reason", "")) == "MetatileBehavior_IsSurfableWaterOrUnderwater", "expected water metatile transition reason")
	_assert(String(water_transition.get("selected", "")) == "B_TRANSITION_RIPPLE", "expected water equal-or-higher wild transition")
	_assert(int(water_transition.get("table_column", -1)) == 1, "expected equal-or-higher transition table column")

	var flash_wild := engine.create_wild_battle_state({
		"species": "SPECIES_WURMPLE",
		"level": 2,
	}, [torchic], {
		"flash_level": 1,
		"metatile_behavior": "MB_TALL_GRASS",
		"map_type": "MAP_TYPE_UNDERGROUND",
	})
	var flash_transition := _dict_field(_dict_field(flash_wild, "battle_setup"), "battle_transition")
	_assert(String(flash_transition.get("transition_type", "")) == "TRANSITION_TYPE_FLASH", "expected Flash to have transition priority")
	_assert(String(flash_transition.get("selected", "")) == "B_TRANSITION_BLUR", "expected flash lower wild transition")

	var cave_wild := engine.create_wild_battle_state({
		"species": "SPECIES_ZUBAT",
		"level": 2,
	}, [torchic], {
		"map_type": "MAP_TYPE_UNDERGROUND",
	})
	var cave_transition := _dict_field(_dict_field(cave_wild, "battle_setup"), "battle_transition")
	_assert(String(cave_transition.get("transition_type", "")) == "TRANSITION_TYPE_CAVE", "expected underground map transition type")
	_assert(String(cave_transition.get("selected", "")) == "B_TRANSITION_CLOCKWISE_WIPE", "expected cave lower wild transition")

	var underwater_wild := engine.create_wild_battle_state({
		"species": "SPECIES_CLAMPERL",
		"level": 6,
	}, [torchic], {
		"map_type": "MAP_TYPE_UNDERWATER",
	})
	var underwater_transition := _dict_field(_dict_field(underwater_wild, "battle_setup"), "battle_transition")
	_assert(String(underwater_transition.get("transition_type", "")) == "TRANSITION_TYPE_WATER", "expected underwater map transition type")
	_assert(String(underwater_transition.get("selected", "")) == "B_TRANSITION_RIPPLE", "expected underwater equal-or-higher wild transition")

	if _failed:
		return

	print(JSON.stringify({
		"battle_engine_smoke": "ok",
		"ember_damage": int(ember_damage.get("damage", 0)),
		"treecko_hp_after_ember": int(treecko_after.get("hp", 0)),
		"adamant_torchic_attack": int(_dict_field(adamant_torchic, "stats").get("attack", 0)),
		"wallace_party_size": wallace_party.size(),
		"wild_opponent": String(wild_opponent.get("species", "")),
		"wild_water_transition": String(water_transition.get("selected", "")),
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
