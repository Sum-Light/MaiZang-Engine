extends SceneTree

const DATA_REGISTRY_SCRIPT := preload("res://scripts/autoload/data_registry.gd")

var _failed := false


func _init() -> void:
	var registry = DATA_REGISTRY_SCRIPT.new()
	registry._ready()

	var moves_data := registry.get_moves_data()
	var stats = moves_data.get("stats", {})
	_assert(typeof(moves_data) == TYPE_DICTIONARY and not moves_data.is_empty(), "expected moves data")
	_assert(typeof(stats) == TYPE_DICTIONARY, "expected moves stats")
	_assert(int(stats.get("move_count", 0)) == 935, "unexpected active move count")
	_assert(int(stats.get("moves_with_core_battle_fields", 0)) == 935, "unexpected core battle move count")
	_assert(int(stats.get("moves_with_additional_effects", 0)) == 337, "unexpected additional-effect move count")
	_assert(int(stats.get("moves_with_battle_effect_scripts", 0)) == 935, "unexpected battle-effect script move count")
	_assert(int(stats.get("missing_battle_effect_script_count", -1)) == 0, "expected no missing move battle-effect scripts")
	_assert(int(stats.get("preprocessor_decision_count", 0)) == 77, "unexpected move preprocessor decision count")
	_assert(int(stats.get("preprocessor_warning_count", -1)) == 0, "expected no move preprocessor warnings")
	_assert(int(stats.get("warning_count", -1)) == 0, "expected no move export warnings")
	_assert(int(stats.get("unsupported_field_count", -1)) == 0, "expected no unsupported move fields")

	var none := registry.get_move_record("MOVE_NONE")
	var pound := registry.get_move_record("MOVE_POUND")
	var pound_by_id := registry.get_move_record(1)
	var pound_by_short_name := registry.get_move_record("pound")
	_assert(String(none.get("symbol", "")) == "MOVE_NONE", "expected MOVE_NONE record")
	_assert(int(none.get("id", -1)) == 0, "unexpected MOVE_NONE id")
	_assert(int(none.get("pp", -1)) == 0, "unexpected MOVE_NONE pp")
	_assert(String(_text_field(none, "name").get("display_text", "")) == "-", "unexpected MOVE_NONE name")
	_assert(not pound.is_empty(), "expected Pound move record")
	_assert(String(pound_by_id.get("symbol", "")) == "MOVE_POUND", "expected move id lookup")
	_assert(String(pound_by_short_name.get("symbol", "")) == "MOVE_POUND", "expected short move symbol lookup")
	_assert(int(pound.get("id", -1)) == 1, "unexpected Pound move id")
	_assert(String(_text_field(pound, "name").get("display_text", "")).length() > 0, "expected Pound display name")
	_assert(String(_text_field(pound, "description").get("display_text", "")).contains("\n"), "expected Pound multiline description")
	_assert(_constant_symbol(pound.get("effect", {})) == "EFFECT_HIT", "unexpected Pound effect")
	_assert(_constant_symbol(pound.get("type", {})) == "TYPE_NORMAL", "unexpected Pound type")
	_assert(_constant_symbol(pound.get("category", {})) == "DAMAGE_CATEGORY_PHYSICAL", "unexpected Pound category")
	_assert(_constant_symbol(pound.get("target", {})) == "TARGET_SELECTED", "unexpected Pound target")
	_assert(int(pound.get("power", 0)) == 40, "unexpected Pound power")
	_assert(int(pound.get("accuracy", 0)) == 100, "unexpected Pound accuracy")
	_assert(int(pound.get("pp", 0)) == 35, "unexpected Pound pp")
	_assert(_bool_field(pound.get("flags", {}), "makes_contact"), "expected Pound contact flag")
	_assert(String(pound.get("battle_effect_script", "")) == "BattleScript_EffectHit", "unexpected Pound battle effect script")
	_assert(String(pound.get("battle_anim_script", "")) == "gBattleAnimMove_Pound", "unexpected Pound anim script")
	_assert(_constant_symbol(_dict_field(pound.get("contest", {}), "combo_starter")) == "COMBO_STARTER_POUND", "unexpected Pound contest starter")

	var fire_punch := registry.get_move_record("MOVE_FIRE_PUNCH")
	var fire_effects = fire_punch.get("additional_effects", [])
	_assert(String(fire_punch.get("symbol", "")) == "MOVE_FIRE_PUNCH", "expected Fire Punch move record")
	_assert(int(fire_punch.get("id", -1)) == 7, "unexpected Fire Punch id")
	_assert(int(fire_punch.get("power", 0)) == 75, "unexpected Fire Punch power")
	_assert(_constant_symbol(fire_punch.get("type", {})) == "TYPE_FIRE", "unexpected Fire Punch type")
	_assert(_bool_field(fire_punch.get("flags", {}), "makes_contact"), "expected Fire Punch contact flag")
	_assert(_bool_field(fire_punch.get("flags", {}), "punching_move"), "expected Fire Punch punching flag")
	_assert(String(fire_punch.get("battle_effect_script", "")) == "BattleScript_EffectHit", "unexpected Fire Punch battle effect script")
	_assert(typeof(fire_effects) == TYPE_ARRAY and fire_effects.size() == 1, "expected Fire Punch burn effect")
	if typeof(fire_effects) == TYPE_ARRAY and fire_effects.size() > 0:
		var burn_effect = fire_effects[0]
		_assert(typeof(burn_effect) == TYPE_DICTIONARY, "expected Fire Punch effect record")
		if typeof(burn_effect) == TYPE_DICTIONARY:
			_assert(_constant_symbol(burn_effect.get("move_effect", {})) == "MOVE_EFFECT_BURN", "unexpected Fire Punch additional effect")
			_assert(int(burn_effect.get("chance", 0)) == 10, "unexpected Fire Punch burn chance")
	_assert(String(fire_punch.get("battle_anim_script", "")) == "gBattleAnimMove_FirePunch", "unexpected Fire Punch anim script")
	_assert(_constant_symbol(_dict_field(fire_punch.get("contest", {}), "category")) == "CONTEST_CATEGORY_COOL", "unexpected Fire Punch contest category")

	var thunder := registry.get_move_record("MOVE_THUNDER")
	var thunder_effects = thunder.get("additional_effects", [])
	_assert(String(thunder.get("symbol", "")) == "MOVE_THUNDER", "expected Thunder move record")
	_assert(int(thunder.get("power", 0)) == 110, "unexpected Thunder power")
	_assert(int(thunder.get("accuracy", 0)) == 70, "unexpected Thunder accuracy")
	_assert(_bool_field(thunder.get("flags", {}), "damages_airborne"), "expected Thunder airborne flag")
	_assert(_bool_field(thunder.get("flags", {}), "always_hits_in_rain"), "expected Thunder rain accuracy flag")
	_assert(_bool_field(thunder.get("flags", {}), "accuracy50_in_sun"), "expected Thunder sun accuracy flag")
	if typeof(thunder_effects) == TYPE_ARRAY and thunder_effects.size() > 0:
		var paralysis_effect = thunder_effects[0]
		_assert(_constant_symbol(paralysis_effect.get("move_effect", {})) == "MOVE_EFFECT_PARALYSIS", "unexpected Thunder additional effect")
		_assert(int(paralysis_effect.get("chance", 0)) == 30, "unexpected Thunder paralysis chance")

	if _failed:
		return

	print(JSON.stringify({
		"data_registry_moves_smoke": "ok",
		"move_count": int(stats.get("move_count", 0)),
		"moves_with_additional_effects": int(stats.get("moves_with_additional_effects", 0)),
		"pound_power": int(pound.get("power", 0)),
		"fire_punch_burn_chance": int(fire_effects[0].get("chance", 0)),
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


func _dict_field(record, field_name: String) -> Dictionary:
	if typeof(record) != TYPE_DICTIONARY:
		return {}
	var value = record.get(field_name, {})
	return value if typeof(value) == TYPE_DICTIONARY else {}


func _constant_symbol(record) -> String:
	if typeof(record) != TYPE_DICTIONARY:
		return ""
	return String(record.get("symbol", ""))


func _bool_field(record, field_name: String) -> bool:
	if typeof(record) != TYPE_DICTIONARY:
		return false
	return bool(record.get(field_name, false))
