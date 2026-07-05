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

	var mudkip := engine.create_battle_mon("SPECIES_MUDKIP", 30, {
		"moves": ["MOVE_WATER_GUN", "MOVE_TACKLE"],
	})
	_assert(String(mudkip.get("status", "")) == "ok", "expected Mudkip battle mon")
	var sawyer_battle := engine.create_trainer_battle_state("TRAINER_SAWYER_1", [mudkip], {
		"map_transition_type": "normal",
	})
	var sawyer_setup := _dict_field(sawyer_battle, "battle_setup")
	var sawyer_transition := _dict_field(sawyer_setup, "battle_transition")
	var sawyer_text_context := _dict_field(sawyer_battle, "battle_text_context")
	_assert(String(sawyer_battle.get("status", "")) == "ok", "expected Sawyer trainer battle state")
	_assert(String(sawyer_battle.get("battle_kind", "")) == "trainer", "expected trainer battle kind")
	_assert(_array_field(sawyer_battle, "battle_type_flags").has("BATTLE_TYPE_TRAINER"), "expected trainer battle type flag")
	_assert(String(sawyer_text_context.get("status", "")) == "battle_text_setup_context_first_pass", "expected trainer battle text setup context")
	_assert(_array_field(sawyer_text_context, "battle_type_flags").has("BATTLE_TYPE_TRAINER"), "expected trainer text context flags")
	_assert(String(_dict_field(sawyer_battle, "trainer").get("symbol", "")) == "TRAINER_SAWYER_1", "expected Sawyer trainer metadata")
	_assert(_array_field(sawyer_battle, "player_party").size() == 1, "expected Sawyer player party")
	_assert(_array_field(sawyer_battle, "opponent_party").size() == 1, "expected Sawyer opponent party")
	_assert(int(_dict_field(sawyer_battle, "active").get("player", -1)) == 0, "expected active player battler")
	_assert(int(_dict_field(sawyer_battle, "active").get("opponent", -1)) == 0, "expected active opponent battler")
	_assert(String(sawyer_setup.get("battle_setup_function", "")) == "BattleSetup_StartTrainerBattle", "expected trainer setup source")
	_assert(String(sawyer_transition.get("selected", "")) == "B_TRANSITION_POKEBALLS_TRAIL", "expected normal lower trainer transition")
	_assert(String(sawyer_transition.get("transition_table", "")) == "sBattleTransitionTable_Trainer", "expected trainer transition table")
	_assert(int(sawyer_transition.get("enemy_level_sum", 0)) == 21, "expected Sawyer enemy level sum")
	_assert(int(sawyer_transition.get("player_level_sum", 0)) == 30, "expected player level sum")
	_assert(String(sawyer_transition.get("transition_type_reason", "")) == "options.map_transition_type", "expected transition hint reason")
	_assert(_dict_field(sawyer_battle, "stats_metadata").has("on_battle_start"), "expected trainer stats metadata")
	_assert(String(_dict_field(sawyer_battle, "callback_metadata").get("saved_callback", "")) == "CB2_EndTrainerBattle", "expected trainer callback metadata")

	var cave_trainer := engine.create_trainer_battle_state("TRAINER_SAWYER_1", [mudkip], {
		"map_transition_type": "cave",
	})
	var cave_trainer_transition := _dict_field(_dict_field(cave_trainer, "battle_setup"), "battle_transition")
	_assert(String(cave_trainer_transition.get("selected", "")) == "B_TRANSITION_SHUFFLE", "expected cave lower trainer transition")
	_assert(String(cave_trainer_transition.get("transition_type", "")) == "TRANSITION_TYPE_CAVE", "expected cave trainer transition type")

	var flash_trainer := engine.create_trainer_battle_state("TRAINER_SAWYER_1", [mudkip], {
		"map_transition_type": "flash",
	})
	var flash_trainer_transition := _dict_field(_dict_field(flash_trainer, "battle_setup"), "battle_transition")
	_assert(String(flash_trainer_transition.get("selected", "")) == "B_TRANSITION_BLUR", "expected flash lower trainer transition")

	var water_trainer := engine.create_trainer_battle_state("TRAINER_SAWYER_1", [mudkip], {
		"map_transition_type": "water",
	})
	var water_trainer_transition := _dict_field(_dict_field(water_trainer, "battle_setup"), "battle_transition")
	_assert(String(water_trainer_transition.get("selected", "")) == "B_TRANSITION_SWIRL", "expected water lower trainer transition")

	var link_trainer := engine.create_trainer_battle_state("TRAINER_SAWYER_1", [mudkip], {
		"link_battle": true,
		"map_transition_type": "normal",
	})
	var link_flags := _array_field(link_trainer, "battle_type_flags")
	var link_context := _dict_field(link_trainer, "battle_text_context")
	_assert(link_flags.has("BATTLE_TYPE_LINK"), "expected link battle flag from setup options")
	_assert(String(link_context.get("battle_text_mode", "")) == "link", "expected link battle text mode from setup options")
	_assert(bool(link_context.get("battle_type_link", false)), "expected link text context flag")
	_assert(_has_unsupported(link_trainer, "link_recorded_battle_setup_flow_metadata_only"), "expected link setup unsupported metadata")

	var recorded_link_trainer := engine.create_trainer_battle_state("TRAINER_SAWYER_1", [mudkip], {
		"recorded_link_battle": true,
		"recorded_text_speed_index": 2,
		"map_transition_type": "normal",
	})
	var recorded_link_flags := _array_field(recorded_link_trainer, "battle_type_flags")
	var recorded_link_context := _dict_field(recorded_link_trainer, "battle_text_context")
	var recorded_link_setup_context := _dict_field(_dict_field(recorded_link_trainer, "battle_setup"), "battle_text_context")
	_assert(recorded_link_flags.has("BATTLE_TYPE_RECORDED"), "expected recorded flag from recorded-link setup")
	_assert(recorded_link_flags.has("BATTLE_TYPE_RECORDED_LINK"), "expected recorded-link flag from setup options")
	_assert(String(recorded_link_context.get("battle_text_mode", "")) == "recorded_link", "expected recorded-link battle text mode")
	_assert(bool(recorded_link_context.get("battle_type_recorded", false)), "expected recorded text context flag")
	_assert(bool(recorded_link_context.get("battle_type_recorded_link", false)), "expected recorded-link text context flag")
	_assert(int(recorded_link_context.get("recorded_text_speed_index", -1)) == 2, "expected recorded text speed index in context")
	_assert(String(recorded_link_setup_context.get("status", "")) == "battle_text_setup_context_first_pass", "expected setup nested text context")
	_assert(_has_unsupported(recorded_link_trainer, "link_recorded_battle_setup_flow_metadata_only"), "expected recorded-link setup unsupported metadata")

	var wallace_battle := engine.create_trainer_battle_state("TRAINER_WALLACE", [mudkip])
	var wallace_transition := _dict_field(_dict_field(wallace_battle, "battle_setup"), "battle_transition")
	_assert(String(wallace_transition.get("selected", "")) == "B_TRANSITION_MUGSHOT", "expected Wallace mugshot transition")
	_assert(String(wallace_transition.get("unsupported_reason", "")) == "trainer_transition_mugshot_placeholder", "expected mugshot unsupported reason")
	_assert(_has_unsupported(wallace_transition, "trainer_transition_mugshot_placeholder"), "expected mugshot unsupported metadata")

	var aqua_battle := engine.create_trainer_battle_state("TRAINER_GRUNT_AQUA_HIDEOUT_1", [mudkip])
	var aqua_transition := _dict_field(_dict_field(aqua_battle, "battle_setup"), "battle_transition")
	_assert(String(aqua_transition.get("selected", "")) == "B_TRANSITION_AQUA", "expected Aqua transition placeholder")
	_assert(String(aqua_transition.get("unsupported_reason", "")) == "trainer_transition_aqua_placeholder", "expected Aqua unsupported reason")

	var fallback_battle := engine.create_trainer_battle_state("TRAINER_SAWYER_1", [], {
		"allow_empty_player_party_fallback": true,
	})
	_assert(String(fallback_battle.get("status", "")) == "ok", "expected empty-party fallback trainer state")
	_assert(_array_field(fallback_battle, "player_party").size() == 1, "expected fallback player party")
	_assert(_has_unsupported(fallback_battle, "empty_player_party_debug_fallback"), "expected empty-party fallback unsupported note")

	var trainer_turn := engine.execute_player_move_turn(sawyer_battle, 0, {
		"damage_roll_percent": 100,
	})
	var trainer_state_after_turn := _dict_field(trainer_turn, "battle_state")
	var trainer_player_after_turn := _array_dict(_array_field(trainer_state_after_turn, "player_party"), 0)
	var trainer_opponent_after_turn := _array_dict(_array_field(trainer_state_after_turn, "opponent_party"), 0)
	var used_water_gun := _array_dict(_array_field(trainer_player_after_turn, "moves"), 0)
	var trainer_result_contract := _dict_field(trainer_turn, "battle_result")
	var trainer_result_parties := _dict_field(trainer_result_contract, "parties")
	_assert(String(trainer_turn.get("status", "")) == "ok", "expected trainer turn execution")
	_assert(int(trainer_turn.get("turn", 0)) == 1, "expected trainer turn increment")
	_assert(int(used_water_gun.get("current_pp", -1)) == 24, "expected Water Gun PP decrement")
	_assert(int(trainer_opponent_after_turn.get("hp", -1)) == 0, "expected Sawyer Geodude fainted")
	_assert(bool(trainer_opponent_after_turn.get("fainted", false)), "expected opponent faint flag")
	_assert(String(trainer_turn.get("outcome", "")) == "player_won", "expected player win outcome")
	_assert(String(trainer_result_contract.get("outcome", "")) == "player_won", "expected result contract outcome")
	_assert(_array_field(trainer_result_parties, "player").size() == 1, "expected result contract player party")
	_assert(_array_field(trainer_result_parties, "opponent").size() == 1, "expected result contract opponent party")
	_assert(_dict_field(trainer_result_contract, "stats").has("battle_start"), "expected result contract stats")
	_assert(_array_field(trainer_result_contract, "unsupported").size() >= 1, "expected result contract unsupported notes")
	_assert(String(_dict_field(trainer_result_contract, "post_battle").get("post_battle_script_resolver", "")) == "BattleSetup_GetTrainerPostBattleScript", "expected post-battle metadata")

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
		"trainer_transition": String(sawyer_transition.get("selected", "")),
		"trainer_outcome": String(trainer_result_contract.get("outcome", "")),
		"battle_text_setup_contexts": 3,
		"recorded_link_setup_speed_index": int(recorded_link_context.get("recorded_text_speed_index", -1)),
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
