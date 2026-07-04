extends SceneTree

const DATA_REGISTRY_SCRIPT := preload("res://scripts/autoload/data_registry.gd")

var _failed := false


func _init() -> void:
	var registry = DATA_REGISTRY_SCRIPT.new()
	registry._ready()

	var scripts_data := registry.get_battle_scripts_data()
	var stats = scripts_data.get("stats", {})
	_assert(typeof(scripts_data) == TYPE_DICTIONARY and not scripts_data.is_empty(), "expected battle scripts data")
	_assert(typeof(stats) == TYPE_DICTIONARY, "expected battle script stats")
	_assert(int(stats.get("script_count", 0)) == 1393, "unexpected battle script count")
	_assert(int(stats.get("script_instruction_count", 0)) == 6309, "unexpected battle script instruction count")
	_assert(int(stats.get("command_instruction_count", 0)) == 5217, "unexpected battle command instruction count")
	_assert(int(stats.get("opcode_count", 0)) == 256, "unexpected battle opcode count")
	_assert(int(stats.get("command_handler_count", 0)) == 256, "unexpected battle command handler count")
	_assert(int(stats.get("command_macro_count", 0)) == 431, "unexpected battle command macro count")
	_assert(int(stats.get("audio_metadata_only_command_macro_count", 0)) == 10, "unexpected audio metadata macro count")
	_assert(int(stats.get("pending_vm_opcode_count", 0)) == 256, "unexpected pending VM opcode count")
	_assert(int(stats.get("fallthrough_script_count", 0)) == 479, "unexpected battle script fallthrough count")
	_assert(int(stats.get("unresolved_label_reference_count", -1)) == 0, "expected no unresolved battle script labels")

	var hit := registry.get_battle_script_record("BattleScript_EffectHit")
	_assert(String(hit.get("label", "")) == "BattleScript_EffectHit", "expected EffectHit script")
	_assert(int(hit.get("instruction_count", 0)) == 1, "expected direct EffectHit instruction count")
	_assert(String(hit.get("fallthrough_label", "")) == "BattleScript_HitFromAccCheck", "expected EffectHit fallthrough")
	_assert(_script_has_macro(hit, "attackcanceler"), "expected EffectHit attackcanceler")

	var hit_acc := registry.get_battle_script_record("BattleScript_HitFromAccCheck")
	_assert(_script_has_macro(hit_acc, "accuracycheck"), "expected hit accuracycheck")

	var hit_damage := registry.get_battle_script_record("BattleScript_HitFromDamageCalc")
	_assert(_script_has_macro(hit_damage, "damagecalc"), "expected hit damagecalc")
	_assert(_script_has_macro(hit_damage, "call"), "expected hit damage animation call")

	var stat_down := registry.get_battle_script_record("BattleScript_EffectAttackDown")
	_assert(_script_has_macro(stat_down, "setstatchanger"), "expected AttackDown setstatchanger")
	_assert(_script_has_macro(stat_down, "goto"), "expected AttackDown goto")

	var status := registry.get_battle_script_record("BattleScript_EffectNonVolatileStatus")
	_assert(_script_has_macro(status, "trynonvolatilestatus"), "expected nonvolatile status setup")
	_assert(_script_has_macro(status, "setnonvolatilestatus"), "expected nonvolatile status apply")
	_assert(_script_has_macro(status, "attackanimation"), "expected status attack animation")
	_assert(_script_has_macro(status, "waitanimation"), "expected status wait animation")

	var roar := registry.get_battle_script_record("BattleScript_EffectRoar")
	_assert(_script_has_macro(roar, "jumpifroarfails"), "expected Roar failure branch")
	_assert(_script_has_macro(roar, "forcerandomswitch"), "expected Roar force switch macro")
	_assert(_script_has_referenced_label(roar, "BattleScript_ButItFailed"), "expected Roar failure label reference")

	var attackcanceler := registry.get_battle_script_command_record("B_SCR_OP_ATTACKCANCELER")
	_assert(int(attackcanceler.get("opcode", -1)) == 0, "unexpected attackcanceler opcode")
	_assert(String(attackcanceler.get("handler", "")) == "Cmd_attackcanceler", "unexpected attackcanceler handler")
	_assert(String(attackcanceler.get("primary_macro", "")) == "attackcanceler", "unexpected attackcanceler macro")
	_assert(String(attackcanceler.get("runtime_status", "")) == "pending_vm", "expected pending VM opcode status")

	var attackcanceler_by_macro := registry.get_battle_script_command_record("attackcanceler")
	_assert(String(attackcanceler_by_macro.get("macro", "")) == "attackcanceler", "expected macro lookup")
	_assert(String(attackcanceler_by_macro.get("opcode_symbol", "")) == "B_SCR_OP_ATTACKCANCELER", "expected macro opcode link")

	var playse := registry.get_battle_script_command_record("playse")
	_assert(String(playse.get("audio_status", "")) == "metadata_only", "expected playse metadata-only audio")
	_assert(_array_has_string(playse.get("side_effect_tags", []), "audio"), "expected playse audio tag")

	if _failed:
		return

	print(JSON.stringify({
		"data_registry_battle_scripts_smoke": "ok",
		"script_count": int(stats.get("script_count", 0)),
		"opcode_count": int(stats.get("opcode_count", 0)),
		"fallthrough_script_count": int(stats.get("fallthrough_script_count", 0)),
		"audio_metadata_only_command_macro_count": int(stats.get("audio_metadata_only_command_macro_count", 0)),
	}))
	registry.free()
	quit(0)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true
	quit(1)


func _script_has_macro(script: Dictionary, macro_name: String) -> bool:
	var instructions = script.get("instructions", [])
	if typeof(instructions) != TYPE_ARRAY:
		return false
	for instruction in instructions:
		if typeof(instruction) == TYPE_DICTIONARY and String(instruction.get("macro", "")) == macro_name:
			return true
	return false


func _script_has_referenced_label(script: Dictionary, label: String) -> bool:
	var labels = script.get("referenced_labels", [])
	return typeof(labels) == TYPE_ARRAY and label in labels


func _array_has_string(records, value: String) -> bool:
	if typeof(records) != TYPE_ARRAY:
		return false
	return value in records
