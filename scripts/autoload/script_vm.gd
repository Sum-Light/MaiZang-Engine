extends Node

const STEP_LIMIT := 128
const MSGBOX_NPC := "MSGBOX_NPC"
const MSGBOX_SIGN := "MSGBOX_SIGN"
const MSGBOX_DEFAULT := "MSGBOX_DEFAULT"
const SAFE_FOLLOWER_FLAG := "FLAG_SAFE_FOLLOWER_MOVEMENT"

var _script_data: Dictionary = {}
var _game_state: Node = null


func _ready() -> void:
	var registry = get_node_or_null("/root/DataRegistry")
	if registry != null and registry.has_method("get_start_script_data"):
		configure_from_script_data(registry.get_start_script_data())
	_game_state = get_node_or_null("/root/GameState")


func configure_from_script_data(script_data: Dictionary) -> void:
	_script_data = script_data


func configure_game_state(game_state: Node) -> void:
	_game_state = game_state


func run_script(script_label: String, context: Dictionary = {}) -> Dictionary:
	if script_label.is_empty() or script_label == "0x0":
		return _empty_result(script_label, "no_script", true)
	if _get_script_record(script_label).is_empty():
		return _empty_result(script_label, "missing_script", true)

	var state := {
		"script_label": script_label,
		"current_label": script_label,
		"ip": 0,
		"stack": [],
		"messages": [],
		"effects": [],
		"unsupported_ops": [],
		"trace": [],
		"context": context,
		"status": "ok",
		"finished": false,
		"last_text_label": "",
		"wait_buttonpress": false,
		"step_count": 0,
	}

	while int(state["step_count"]) < STEP_LIMIT and not bool(state["finished"]):
		var current_label := String(state["current_label"])
		var script_record := _get_script_record(current_label)
		if script_record.is_empty():
			state["status"] = "missing_branch_target"
			state["finished"] = true
			break

		var instructions = script_record.get("instructions", [])
		if typeof(instructions) != TYPE_ARRAY:
			state["status"] = "invalid_script_record"
			state["finished"] = true
			break

		var ip := int(state["ip"])
		if ip >= instructions.size():
			_return_from_script(state)
			continue

		var instruction = instructions[ip]
		state["ip"] = ip + 1
		state["step_count"] = int(state["step_count"]) + 1
		if typeof(instruction) != TYPE_DICTIONARY:
			_record_unsupported(state, "invalid_instruction", 0, "")
			continue

		_execute_instruction(state, instruction)

	if not bool(state["finished"]):
		state["status"] = "step_limit"
		state["finished"] = true

	return {
		"script_label": script_label,
		"status": String(state["status"]),
		"finished": bool(state["finished"]),
		"messages": state["messages"],
		"effects": state["effects"],
		"unsupported_ops": state["unsupported_ops"],
		"trace": state["trace"],
		"wait_buttonpress": bool(state["wait_buttonpress"]),
		"step_count": int(state["step_count"]),
	}


func _execute_instruction(state: Dictionary, instruction: Dictionary) -> void:
	var op := String(instruction.get("op", ""))
	var args = instruction.get("args", [])
	if typeof(args) != TYPE_ARRAY:
		args = []
	var line := int(instruction.get("line", 0))
	state["trace"].append({
		"label": String(state["current_label"]),
		"op": op,
		"line": line,
	})

	match op:
		"end":
			state["finished"] = true
		"return":
			_return_from_script(state)
		"call":
			if args.size() >= 1:
				_call_script(state, String(args[0]))
			else:
				_record_unsupported(state, op, line, String(instruction.get("raw", "")))
		"goto":
			if args.size() >= 1:
				_jump_to_script(state, String(args[0]))
			else:
				_record_unsupported(state, op, line, String(instruction.get("raw", "")))
		"call_if_set", "call_if_unset", "call_if_eq", "call_if_ne":
			_execute_conditional_branch(state, op, args, true, line, String(instruction.get("raw", "")))
		"goto_if_set", "goto_if_unset", "goto_if_eq", "goto_if_ne":
			_execute_conditional_branch(state, op, args, false, line, String(instruction.get("raw", "")))
		"setflag":
			if args.size() >= 1:
				_set_flag(String(args[0]), true)
				_record_effect(state, op, line, {"flag": String(args[0])})
			else:
				_record_unsupported(state, op, line, String(instruction.get("raw", "")))
		"clearflag":
			if args.size() >= 1:
				_set_flag(String(args[0]), false)
				_record_effect(state, op, line, {"flag": String(args[0])})
			else:
				_record_unsupported(state, op, line, String(instruction.get("raw", "")))
		"setvar":
			if args.size() >= 2:
				_set_var(String(args[0]), _read_value(String(args[1])))
				_record_effect(state, op, line, {
					"var": String(args[0]),
					"value": _read_value(String(args[1])),
				})
			else:
				_record_unsupported(state, op, line, String(instruction.get("raw", "")))
		"lock", "lockall", "release", "releaseall", "faceplayer", "waitmessage", "waitbuttonpress", "closemessage":
			_execute_basic_field_command(state, op, line)
		"message":
			if args.size() >= 1:
				_execute_message(state, String(args[0]), "", op, line)
			else:
				_record_unsupported(state, op, line, String(instruction.get("raw", "")))
		"msgbox":
			if args.size() >= 1:
				var mode := MSGBOX_DEFAULT
				if args.size() >= 2:
					mode = String(args[1])
				_execute_msgbox(state, String(args[0]), mode, line)
			else:
				_record_unsupported(state, op, line, String(instruction.get("raw", "")))
		_:
			_record_unsupported(state, op, line, String(instruction.get("raw", "")))


func _execute_conditional_branch(
	state: Dictionary,
	op: String,
	args: Array,
	is_call: bool,
	line: int,
	raw: String
) -> void:
	if args.size() < 2:
		_record_unsupported(state, op, line, raw)
		return

	var target := String(args[args.size() - 1])
	var matched := _condition_matches(op, args)
	_record_effect(state, op, line, {
		"target": target,
		"matched": matched,
	})
	if not matched:
		return
	if is_call:
		_call_script(state, target)
	else:
		_jump_to_script(state, target)


func _execute_basic_field_command(state: Dictionary, op: String, line: int) -> void:
	_record_effect(state, op, line)
	if op == "waitbuttonpress":
		state["wait_buttonpress"] = true


func _execute_msgbox(state: Dictionary, text_label: String, mode: String, line: int) -> void:
	match mode:
		MSGBOX_NPC:
			_execute_basic_field_command(state, "lock", line)
			_execute_basic_field_command(state, "faceplayer", line)
			_execute_message(state, text_label, mode, "msgbox", line)
			_execute_basic_field_command(state, "waitmessage", line)
			_execute_basic_field_command(state, "waitbuttonpress", line)
			_execute_basic_field_command(state, "release", line)
		MSGBOX_SIGN:
			_set_flag(SAFE_FOLLOWER_FLAG, true)
			_record_effect(state, "setflag", line, {"flag": SAFE_FOLLOWER_FLAG, "source": "msgbox"})
			_execute_basic_field_command(state, "lockall", line)
			_execute_message(state, text_label, mode, "msgbox", line)
			_execute_basic_field_command(state, "waitmessage", line)
			_execute_basic_field_command(state, "waitbuttonpress", line)
			_execute_basic_field_command(state, "releaseall", line)
			_set_flag(SAFE_FOLLOWER_FLAG, false)
			_record_effect(state, "clearflag", line, {"flag": SAFE_FOLLOWER_FLAG, "source": "msgbox"})
		MSGBOX_DEFAULT:
			_execute_message(state, text_label, mode, "msgbox", line)
			_execute_basic_field_command(state, "waitmessage", line)
			_execute_basic_field_command(state, "waitbuttonpress", line)
		_:
			_record_unsupported(state, "msgbox:%s" % mode, line, "msgbox %s, %s" % [text_label, mode])


func _execute_message(
	state: Dictionary,
	text_label: String,
	mode: String,
	source_op: String,
	line: int
) -> void:
	if text_label == "NULL" or text_label == "0x0":
		text_label = String(state["last_text_label"])
	else:
		state["last_text_label"] = text_label

	var text_record := _get_text_record(text_label)
	var status := "ok" if not text_record.is_empty() else "missing_text"
	state["messages"].append({
		"text_label": text_label,
		"mode": mode,
		"op": source_op,
		"line": line,
		"text": String(text_record.get("display_text", "")),
		"status": status,
	})
	_record_effect(state, "message", line, {
		"text_label": text_label,
		"mode": mode,
		"status": status,
	})


func _call_script(state: Dictionary, target: String) -> void:
	if _get_script_record(target).is_empty():
		state["status"] = "missing_branch_target"
		state["finished"] = true
		return
	var stack: Array = state["stack"]
	stack.append({
		"label": String(state["current_label"]),
		"ip": int(state["ip"]),
	})
	state["stack"] = stack
	_jump_to_script(state, target)


func _jump_to_script(state: Dictionary, target: String) -> void:
	if _get_script_record(target).is_empty():
		state["status"] = "missing_branch_target"
		state["finished"] = true
		return
	state["current_label"] = target
	state["ip"] = 0


func _return_from_script(state: Dictionary) -> void:
	var stack: Array = state["stack"]
	if stack.is_empty():
		state["finished"] = true
		return
	var frame = stack.pop_back()
	state["stack"] = stack
	if typeof(frame) != TYPE_DICTIONARY:
		state["status"] = "invalid_call_frame"
		state["finished"] = true
		return
	state["current_label"] = String(frame.get("label", ""))
	state["ip"] = int(frame.get("ip", 0))


func _condition_matches(op: String, args: Array) -> bool:
	match op:
		"call_if_set", "goto_if_set":
			return _is_flag_set(String(args[0]))
		"call_if_unset", "goto_if_unset":
			return not _is_flag_set(String(args[0]))
		"call_if_eq", "goto_if_eq":
			return _read_value(String(args[0])) == _read_value(String(args[1]))
		"call_if_ne", "goto_if_ne":
			return _read_value(String(args[0])) != _read_value(String(args[1]))
	return false


func _read_value(token: String) -> int:
	var value := token.strip_edges()
	if value.begins_with("VAR_"):
		return _get_var(value)
	return int(value)


func _get_var(var_name: String) -> int:
	var game_state := _get_game_state()
	if game_state != null and game_state.has_method("get_var"):
		return int(game_state.get_var(var_name, 0))
	return 0


func _set_var(var_name: String, value: int) -> void:
	var game_state := _get_game_state()
	if game_state != null and game_state.has_method("set_var"):
		game_state.set_var(var_name, value)


func _is_flag_set(flag_name: String) -> bool:
	var game_state := _get_game_state()
	if game_state != null and game_state.has_method("is_flag_set"):
		return bool(game_state.is_flag_set(flag_name))
	return false


func _set_flag(flag_name: String, enabled: bool) -> void:
	var game_state := _get_game_state()
	if game_state == null:
		return
	if enabled and game_state.has_method("set_flag"):
		game_state.set_flag(flag_name, true)
	elif not enabled and game_state.has_method("clear_flag"):
		game_state.clear_flag(flag_name)


func _record_effect(state: Dictionary, op: String, line: int, detail: Dictionary = {}) -> void:
	var effect := {
		"op": op,
		"line": line,
	}
	for key in detail:
		effect[key] = detail[key]
	state["effects"].append(effect)


func _record_unsupported(state: Dictionary, op: String, line: int, raw: String) -> void:
	state["unsupported_ops"].append({
		"op": op,
		"line": line,
		"raw": raw,
		"label": String(state["current_label"]),
	})
	state["status"] = "unsupported_op"
	state["finished"] = true


func _empty_result(script_label: String, status: String, finished: bool) -> Dictionary:
	return {
		"script_label": script_label,
		"status": status,
		"finished": finished,
		"messages": [],
		"effects": [],
		"unsupported_ops": [],
		"trace": [],
		"wait_buttonpress": false,
		"step_count": 0,
	}


func _get_script_record(script_label: String) -> Dictionary:
	var scripts = _script_data.get("scripts", {})
	if typeof(scripts) != TYPE_DICTIONARY:
		return {}
	var record = scripts.get(script_label, {})
	return record if typeof(record) == TYPE_DICTIONARY else {}


func _get_text_record(text_label: String) -> Dictionary:
	var texts = _script_data.get("texts", {})
	if typeof(texts) != TYPE_DICTIONARY:
		return {}
	var record = texts.get(text_label, {})
	return record if typeof(record) == TYPE_DICTIONARY else {}


func _get_game_state() -> Node:
	if _game_state != null:
		return _game_state
	if is_inside_tree():
		return get_node_or_null("/root/GameState")
	return null
