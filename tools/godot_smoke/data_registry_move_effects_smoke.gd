extends SceneTree

const DATA_REGISTRY_SCRIPT := preload("res://scripts/autoload/data_registry.gd")

var _failed := false


func _init() -> void:
	var registry = DATA_REGISTRY_SCRIPT.new()
	registry._ready()

	var effects_data := registry.get_battle_move_effects_data()
	var stats = effects_data.get("stats", {})
	_assert(typeof(effects_data) == TYPE_DICTIONARY and not effects_data.is_empty(), "expected battle move effects data")
	_assert(typeof(stats) == TYPE_DICTIONARY, "expected battle move effects stats")
	_assert(int(stats.get("effect_count", 0)) == 332, "unexpected battle effect count")
	_assert(int(stats.get("table_entry_count", 0)) == 332, "unexpected battle effect table count")
	_assert(int(stats.get("unique_battle_script_count", 0)) == 217, "unexpected unique battle script count")
	_assert(int(stats.get("resolved_battle_script_count", 0)) == 332, "unexpected resolved battle script count")
	_assert(int(stats.get("missing_table_entry_count", -1)) == 0, "expected no missing battle move effect table entries")
	_assert(int(stats.get("missing_battle_script_label_count", -1)) == 0, "expected no missing battle script labels")
	_assert(int(stats.get("pending_vm_effect_count", 0)) == 332, "unexpected pending VM effect count")

	var hit := registry.get_battle_move_effect_record("EFFECT_HIT")
	var hit_by_id := registry.get_battle_move_effect_record(1)
	var hit_by_short := registry.get_battle_move_effect_record("hit")
	_assert(String(hit.get("battle_script", "")) == "BattleScript_EffectHit", "expected hit effect script")
	_assert(String(hit_by_id.get("symbol", "")) == "EFFECT_HIT", "expected hit id lookup")
	_assert(String(hit_by_short.get("symbol", "")) == "EFFECT_HIT", "expected hit short lookup")
	_assert(bool(hit.get("battle_script_resolved", false)), "expected hit script resolved")

	var status := registry.get_battle_move_effect_record("EFFECT_NON_VOLATILE_STATUS")
	_assert(String(status.get("battle_script", "")) == "BattleScript_EffectNonVolatileStatus", "expected status effect script")
	_assert(bool(status.get("encourage_encore", false)), "expected status encourage encore metadata")

	var attack_down := registry.get_battle_move_effect_record("EFFECT_ATTACK_DOWN")
	_assert(String(attack_down.get("battle_script", "")) == "BattleScript_EffectAttackDown", "expected attack-down effect script")
	_assert(String(attack_down.get("battle_factory_style", "")) == "FACTORY_STYLE_WEAKENING", "expected attack-down factory style")

	var roar := registry.get_battle_move_effect_record("EFFECT_ROAR")
	_assert(String(roar.get("battle_script", "")) == "BattleScript_EffectRoar", "expected Roar effect script")
	_assert(int(roar.get("battle_tv_score", -1)) == 5, "unexpected Roar battle TV score")

	var moves_data := registry.get_moves_data()
	var move_stats = moves_data.get("stats", {})
	_assert(int(move_stats.get("moves_with_battle_effect_scripts", 0)) == 935, "expected every move to have battle effect script")
	_assert(int(move_stats.get("missing_battle_effect_script_count", -1)) == 0, "expected no missing move battle effect scripts")

	_assert(_move_has_script(registry, "MOVE_POUND", "EFFECT_HIT", "BattleScript_EffectHit"), "expected Pound hit script link")
	_assert(_move_has_script(registry, "MOVE_SLEEP_POWDER", "EFFECT_NON_VOLATILE_STATUS", "BattleScript_EffectNonVolatileStatus"), "expected Sleep Powder status script link")
	_assert(_move_has_script(registry, "MOVE_GROWL", "EFFECT_ATTACK_DOWN", "BattleScript_EffectAttackDown"), "expected Growl stat-down script link")
	_assert(_move_has_script(registry, "MOVE_ROAR", "EFFECT_ROAR", "BattleScript_EffectRoar"), "expected Roar force-switch script link")

	if _failed:
		return

	print(JSON.stringify({
		"data_registry_move_effects_smoke": "ok",
		"effect_count": int(stats.get("effect_count", 0)),
		"resolved_battle_script_count": int(stats.get("resolved_battle_script_count", 0)),
		"moves_with_battle_effect_scripts": int(move_stats.get("moves_with_battle_effect_scripts", 0)),
	}))
	registry.free()
	quit(0)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true
	quit(1)


func _move_has_script(registry: Node, move_symbol: String, effect_symbol: String, script_label: String) -> bool:
	var move = registry.get_move_record(move_symbol)
	if move.is_empty():
		return false
	if String(move.get("battle_effect_script", "")) != script_label:
		return false
	var effect = move.get("effect", {})
	return typeof(effect) == TYPE_DICTIONARY and String(effect.get("symbol", "")) == effect_symbol
