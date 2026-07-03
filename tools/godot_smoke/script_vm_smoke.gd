extends SceneTree

const SCRIPT_VM_SCRIPT := preload("res://scripts/autoload/script_vm.gd")
const SCRIPT_PATH := "res://data/generated/scripts/littleroot_town.json"


func _init() -> void:
	var script_data := _load_json_object(SCRIPT_PATH)
	var vm = SCRIPT_VM_SCRIPT.new()
	vm.configure_from_script_data(script_data)

	var twin_result := vm.run_script("LittlerootTown_EventScript_Twin")
	var town_sign_result := vm.run_script("LittlerootTown_EventScript_TownSign")
	var need_pokemon_result := vm.run_script("LittlerootTown_EventScript_NeedPokemonTriggerLeft")
	var missing_result := vm.run_script("Missing_EventScript")

	_assert(twin_result.get("status", "") == "ok", "expected Twin script to execute")
	_assert(twin_result.get("finished", false), "expected Twin script to finish")
	_assert(_first_text_label(twin_result) == "LittlerootTown_Text_IfYouGoInGrassPokemonWillJumpOut", "unexpected Twin text")
	_assert(_has_effect(twin_result, "lock"), "expected Twin lock effect")
	_assert(_has_effect(twin_result, "faceplayer"), "expected Twin faceplayer effect")
	_assert(_has_effect(twin_result, "release"), "expected Twin release effect")
	_assert(_unsupported_count(twin_result) == 0, "expected no unsupported Twin ops")

	_assert(town_sign_result.get("status", "") == "ok", "expected town sign script to execute")
	_assert(town_sign_result.get("finished", false), "expected town sign script to finish")
	_assert(_first_text_label(town_sign_result) == "LittlerootTown_Text_TownSign", "unexpected town sign text")
	_assert(_has_effect(town_sign_result, "lockall"), "expected town sign lockall effect")
	_assert(_has_effect(town_sign_result, "releaseall"), "expected town sign releaseall effect")
	_assert(_unsupported_count(town_sign_result) == 0, "expected no unsupported town sign ops")

	_assert(need_pokemon_result.get("status", "") == "ok", "expected need-pokemon script to execute")
	_assert(need_pokemon_result.get("finished", false), "expected need-pokemon script to finish")
	_assert(_message_count(need_pokemon_result) == 2, "expected two need-pokemon messages")
	_assert(_movement_count(need_pokemon_result) == 4, "expected four need-pokemon movements")
	_assert(
		_movement_label(need_pokemon_result, 0) == "LittlerootTown_Movement_TwinApproachPlayerLeft",
		"unexpected first need-pokemon movement"
	)
	_assert(_movement_target(need_pokemon_result, 0) == "LOCALID_LITTLEROOT_TWIN", "unexpected first movement target")
	_assert(_movement_net_delta(need_pokemon_result, 0) == Vector2i(3, -2), "unexpected first movement delta")
	_assert(_movement_step_count(need_pokemon_result, 0) == 13, "unexpected first movement step count")
	_assert(_movement_final_facing(need_pokemon_result, 0) == "down", "unexpected first movement facing")
	_assert(_has_movement(need_pokemon_result, "LOCALID_PLAYER", "LittlerootTown_Movement_PushPlayerBackFromRoute"), "expected player push movement")
	_assert(_effect_count_for_op(need_pokemon_result, "waitmovement") == 3, "expected three waitmovement effects")
	_assert(bool(need_pokemon_result.get("wait_movement", false)), "expected wait movement metadata")
	_assert(_unsupported_count(need_pokemon_result) == 0, "expected no unsupported need-pokemon ops")

	_assert(missing_result.get("status", "") == "missing_script", "expected missing script status")

	print(JSON.stringify({
		"script_vm_smoke": "ok",
		"twin": _result_summary(twin_result),
		"town_sign": _result_summary(town_sign_result),
		"need_pokemon": _result_summary(need_pokemon_result),
		"missing_status": String(missing_result.get("status", "")),
	}))
	vm.free()
	quit(0)


func _load_json_object(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Could not open %s" % path)
		quit(1)
		return {}

	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("%s is not a JSON object" % path)
		quit(1)
		return {}

	return parsed


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	quit(1)


func _first_text_label(result: Dictionary) -> String:
	var messages = result.get("messages", [])
	if typeof(messages) != TYPE_ARRAY or messages.is_empty():
		return ""
	var first = messages[0]
	if typeof(first) != TYPE_DICTIONARY:
		return ""
	return String(first.get("text_label", ""))


func _has_effect(result: Dictionary, op: String) -> bool:
	var effects = result.get("effects", [])
	if typeof(effects) != TYPE_ARRAY:
		return false
	for effect in effects:
		if typeof(effect) == TYPE_DICTIONARY and String(effect.get("op", "")) == op:
			return true
	return false


func _effect_count_for_op(result: Dictionary, op: String) -> int:
	var effects = result.get("effects", [])
	if typeof(effects) != TYPE_ARRAY:
		return 0
	var count := 0
	for effect in effects:
		if typeof(effect) == TYPE_DICTIONARY and String(effect.get("op", "")) == op:
			count += 1
	return count


func _unsupported_count(result: Dictionary) -> int:
	var unsupported_ops = result.get("unsupported_ops", [])
	if typeof(unsupported_ops) != TYPE_ARRAY:
		return 0
	return unsupported_ops.size()


func _result_summary(result: Dictionary) -> Dictionary:
	return {
		"status": String(result.get("status", "")),
		"message_count": _message_count(result),
		"first_text_label": _first_text_label(result),
		"effect_count": _effect_count(result),
		"movement_count": _movement_count(result),
		"wait_buttonpress": bool(result.get("wait_buttonpress", false)),
		"wait_movement": bool(result.get("wait_movement", false)),
		"step_count": int(result.get("step_count", 0)),
	}


func _message_count(result: Dictionary) -> int:
	var messages = result.get("messages", [])
	return messages.size() if typeof(messages) == TYPE_ARRAY else 0


func _effect_count(result: Dictionary) -> int:
	var effects = result.get("effects", [])
	return effects.size() if typeof(effects) == TYPE_ARRAY else 0


func _movement_count(result: Dictionary) -> int:
	var movements = result.get("movements", [])
	return movements.size() if typeof(movements) == TYPE_ARRAY else 0


func _movement_at(result: Dictionary, index: int) -> Dictionary:
	var movements = result.get("movements", [])
	if typeof(movements) != TYPE_ARRAY or index < 0 or index >= movements.size():
		return {}
	var movement = movements[index]
	return movement if typeof(movement) == TYPE_DICTIONARY else {}


func _movement_label(result: Dictionary, index: int) -> String:
	return String(_movement_at(result, index).get("movement_label", ""))


func _movement_target(result: Dictionary, index: int) -> String:
	return String(_movement_at(result, index).get("target", ""))


func _movement_step_count(result: Dictionary, index: int) -> int:
	return int(_movement_at(result, index).get("step_count", 0))


func _movement_final_facing(result: Dictionary, index: int) -> String:
	return String(_movement_at(result, index).get("final_facing", ""))


func _movement_net_delta(result: Dictionary, index: int) -> Vector2i:
	var delta = _movement_at(result, index).get("net_delta", [0, 0])
	if typeof(delta) != TYPE_ARRAY or delta.size() < 2:
		return Vector2i.ZERO
	return Vector2i(int(delta[0]), int(delta[1]))


func _has_movement(result: Dictionary, target: String, movement_label: String) -> bool:
	var movements = result.get("movements", [])
	if typeof(movements) != TYPE_ARRAY:
		return false
	for movement in movements:
		if typeof(movement) != TYPE_DICTIONARY:
			continue
		if String(movement.get("target", "")) == target and String(movement.get("movement_label", "")) == movement_label:
			return true
	return false
