extends Node

const STEP_LIMIT := 128
const MSGBOX_NPC := "MSGBOX_NPC"
const MSGBOX_SIGN := "MSGBOX_SIGN"
const MSGBOX_DEFAULT := "MSGBOX_DEFAULT"
const SAFE_FOLLOWER_FLAG := "FLAG_SAFE_FOLLOWER_MOVEMENT"
const VAR_RESULT := "VAR_RESULT"
const PLAYER_GENDER_MALE := "MALE"
const PLAYER_GENDER_FEMALE := "FEMALE"
const PLAYER_GENDER_MALE_VALUE := 0
const PLAYER_GENDER_FEMALE_VALUE := 1

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
		"movements": [],
		"object_effects": [],
		"effects": [],
		"unsupported_ops": [],
		"trace": [],
		"context": context,
		"status": "ok",
		"finished": false,
		"last_text_label": "",
		"last_movement_target": "",
		"wait_buttonpress": false,
		"wait_movement": false,
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
		"movements": state["movements"],
		"object_effects": state["object_effects"],
		"effects": state["effects"],
		"unsupported_ops": state["unsupported_ops"],
		"trace": state["trace"],
		"wait_buttonpress": bool(state["wait_buttonpress"]),
		"wait_movement": bool(state["wait_movement"]),
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
		"checkplayergender":
			_execute_checkplayergender(state, line)
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
		"applymovement":
			_execute_applymovement(state, args, line, String(instruction.get("raw", "")))
		"applymovementat":
			_execute_applymovement(state, args, line, String(instruction.get("raw", "")), true)
		"waitmovement":
			_execute_waitmovement(state, args, line)
		"waitmovementat":
			_execute_waitmovement(state, args, line, true)
		"setobjectxy":
			_execute_setobjectxy(state, args, line, String(instruction.get("raw", "")))
		"setobjectxyperm":
			_execute_setobjectxyperm(state, args, line, String(instruction.get("raw", "")))
		"setobjectmovementtype":
			_execute_setobjectmovementtype(state, args, line, String(instruction.get("raw", "")))
		"addobject", "addobjectat", "removeobject", "removeobjectat", "showobject", "showobjectat", "hideobject", "hideobjectat":
			_execute_object_visibility_command(state, op, args, line, String(instruction.get("raw", "")))
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


func _execute_checkplayergender(state: Dictionary, line: int) -> void:
	var gender := _get_player_gender()
	var gender_value := _gender_value(gender)
	_set_var(VAR_RESULT, gender_value)
	_record_effect(state, "checkplayergender", line, {
		"gender": gender,
		"value": gender_value,
		"var": VAR_RESULT,
	})


func _execute_applymovement(
	state: Dictionary,
	args: Array,
	line: int,
	raw: String,
	has_explicit_map: bool = false
) -> void:
	if args.size() < 2:
		_record_unsupported(state, "applymovement", line, raw)
		return

	var target := String(args[0])
	var movement_label := String(args[1])
	var movement_record := _get_movement_record(movement_label)
	if movement_record.is_empty():
		var missing_movement := {
			"target": target,
			"movement_label": movement_label,
			"line": line,
			"status": "missing_movement",
			"steps": [],
			"step_count": 0,
			"unsupported_steps": [],
			"net_delta": [0, 0],
			"final_facing": "",
		}
		if has_explicit_map and args.size() >= 4:
			missing_movement["map_group"] = String(args[2])
			missing_movement["map_num"] = String(args[3])
		state["movements"].append(missing_movement)
		state["status"] = "missing_movement"
		state["finished"] = true
		return

	var movement := _build_movement_effect(target, movement_label, movement_record, line)
	if has_explicit_map and args.size() >= 4:
		movement["map_group"] = String(args[2])
		movement["map_num"] = String(args[3])

	state["movements"].append(movement)
	state["last_movement_target"] = target
	_record_effect(state, "applymovement", line, {
		"target": target,
		"movement_label": movement_label,
		"status": String(movement.get("status", "")),
		"step_count": int(movement.get("step_count", 0)),
		"net_delta": movement.get("net_delta", [0, 0]),
	})

	var unsupported_steps = movement.get("unsupported_steps", [])
	if typeof(unsupported_steps) == TYPE_ARRAY and not unsupported_steps.is_empty():
		state["status"] = "unsupported_movement_step"
		state["finished"] = true


func _execute_waitmovement(
	state: Dictionary,
	args: Array,
	line: int,
	has_explicit_map: bool = false
) -> void:
	var target := "0"
	if args.size() >= 1:
		target = String(args[0])

	var resolved_target := String(state["last_movement_target"])
	if target != "0" and target != "LOCALID_NONE":
		resolved_target = target
		state["last_movement_target"] = target

	var detail := {
		"target": target,
		"resolved_target": resolved_target,
	}
	if has_explicit_map and args.size() >= 3:
		detail["map_group"] = String(args[1])
		detail["map_num"] = String(args[2])
	state["wait_movement"] = true
	_record_effect(state, "waitmovement", line, detail)


func _execute_setobjectxy(state: Dictionary, args: Array, line: int, raw: String) -> void:
	if args.size() < 3:
		_record_unsupported(state, "setobjectxy", line, raw)
		return

	_record_object_effect(state, "setobjectxy", line, {
		"target": String(args[0]),
		"position": [_read_value(String(args[1])), _read_value(String(args[2]))],
	})


func _execute_setobjectxyperm(state: Dictionary, args: Array, line: int, raw: String) -> void:
	if args.size() < 3:
		_record_unsupported(state, "setobjectxyperm", line, raw)
		return

	_record_object_effect(state, "setobjectxyperm", line, {
		"target": String(args[0]),
		"position": [_read_value(String(args[1])), _read_value(String(args[2]))],
	})


func _execute_setobjectmovementtype(state: Dictionary, args: Array, line: int, raw: String) -> void:
	if args.size() < 2:
		_record_unsupported(state, "setobjectmovementtype", line, raw)
		return

	_record_object_effect(state, "setobjectmovementtype", line, {
		"target": String(args[0]),
		"movement_type": String(args[1]),
	})


func _execute_object_visibility_command(
	state: Dictionary,
	op: String,
	args: Array,
	line: int,
	raw: String
) -> void:
	if args.is_empty():
		_record_unsupported(state, op, line, raw)
		return

	var detail := {
		"target": String(args[0]),
	}
	if op.ends_with("at") and args.size() >= 2:
		detail["map"] = String(args[1])

	_record_object_effect(state, op, line, detail)


func _record_object_effect(state: Dictionary, op: String, line: int, detail: Dictionary) -> void:
	var object_effect := {
		"op": op,
		"line": line,
	}
	for key in detail:
		object_effect[key] = detail[key]
	state["object_effects"].append(object_effect)
	_record_effect(state, op, line, detail)


func _build_movement_effect(
	target: String,
	movement_label: String,
	movement_record: Dictionary,
	line: int
) -> Dictionary:
	var instructions = movement_record.get("instructions", [])
	if typeof(instructions) != TYPE_ARRAY:
		return {
			"target": target,
			"movement_label": movement_label,
			"line": line,
			"status": "invalid_movement_record",
			"steps": [],
			"step_count": 0,
			"unsupported_steps": [],
			"net_delta": [0, 0],
			"final_facing": "",
		}

	var steps: Array = []
	var unsupported_steps: Array = []
	var net_delta := [0, 0]
	var final_facing := ""
	for instruction in instructions:
		if typeof(instruction) != TYPE_DICTIONARY:
			var invalid_step := {
				"op": "invalid_movement_instruction",
				"line": 0,
				"raw": "",
			}
			unsupported_steps.append(invalid_step)
			steps.append({
				"kind": "unsupported",
				"op": invalid_step["op"],
				"line": invalid_step["line"],
				"raw": invalid_step["raw"],
			})
			continue

		var step := _movement_step_from_instruction(instruction)
		if String(step.get("kind", "")) == "end":
			break
		steps.append(step)

		var direction := String(step.get("direction", ""))
		if not direction.is_empty() and step.get("updates_facing", true):
			final_facing = direction

		if bool(step.get("moves", false)):
			var delta: Array = step.get("delta", [0, 0])
			net_delta[0] = int(net_delta[0]) + int(delta[0])
			net_delta[1] = int(net_delta[1]) + int(delta[1])

		if String(step.get("kind", "")) == "unsupported":
			unsupported_steps.append({
				"op": String(step.get("op", "")),
				"line": int(step.get("line", 0)),
				"raw": String(step.get("raw", "")),
			})

	return {
		"target": target,
		"movement_label": movement_label,
		"line": line,
		"status": "partial" if not unsupported_steps.is_empty() else "ok",
		"steps": steps,
		"step_count": steps.size(),
		"unsupported_steps": unsupported_steps,
		"net_delta": net_delta,
		"final_facing": final_facing,
	}


func _movement_step_from_instruction(instruction: Dictionary) -> Dictionary:
	var op := String(instruction.get("op", ""))
	var line := int(instruction.get("line", 0))
	var raw := String(instruction.get("raw", ""))

	if op == "step_end":
		return {
			"kind": "end",
			"op": op,
			"line": line,
			"raw": raw,
		}

	var direction := _direction_from_movement_op(op)
	if op.begins_with("delay_"):
		return {
			"kind": "delay",
			"op": op,
			"line": line,
			"raw": raw,
			"frames": int(op.trim_prefix("delay_")),
			"moves": false,
			"updates_facing": false,
		}

	if op.begins_with("face_"):
		return {
			"kind": "face",
			"op": op,
			"line": line,
			"raw": raw,
			"direction": direction,
			"moves": false,
			"updates_facing": not direction.is_empty(),
		}

	if op.begins_with("walk_in_place_"):
		return {
			"kind": "walk_in_place",
			"op": op,
			"line": line,
			"raw": raw,
			"direction": direction,
			"speed": _speed_from_movement_op(op),
			"moves": false,
			"updates_facing": not direction.is_empty(),
		}

	if _is_grid_movement_op(op):
		var delta := _direction_delta(direction)
		return {
			"kind": _grid_movement_kind(op),
			"op": op,
			"line": line,
			"raw": raw,
			"direction": direction,
			"speed": _speed_from_movement_op(op),
			"delta": delta,
			"moves": direction != "" and (int(delta[0]) != 0 or int(delta[1]) != 0),
			"updates_facing": not direction.is_empty(),
		}

	if op.begins_with("jump_in_place_"):
		return {
			"kind": "jump_in_place",
			"op": op,
			"line": line,
			"raw": raw,
			"direction": direction,
			"moves": false,
			"updates_facing": not direction.is_empty(),
		}

	if _is_movement_control_op(op):
		return {
			"kind": "control",
			"op": op,
			"line": line,
			"raw": raw,
			"moves": false,
			"updates_facing": false,
		}

	if op.begins_with("emote_"):
		return {
			"kind": "emote",
			"op": op,
			"line": line,
			"raw": raw,
			"moves": false,
			"updates_facing": false,
		}

	return {
		"kind": "unsupported",
		"op": op,
		"line": line,
		"raw": raw,
		"moves": false,
		"updates_facing": false,
	}


func _is_grid_movement_op(op: String) -> bool:
	if op.begins_with("walk_in_place_"):
		return false
	return (
		op.begins_with("walk_")
		or op.begins_with("player_run_")
		or op.begins_with("slide_")
		or op.begins_with("ride_water_current_")
		or (op.begins_with("jump_") and not op.begins_with("jump_in_place_"))
	)


func _grid_movement_kind(op: String) -> String:
	if op.begins_with("jump_"):
		return "jump"
	if op.begins_with("slide_"):
		return "slide"
	if op.begins_with("ride_water_current_"):
		return "current"
	if op.begins_with("player_run_"):
		return "run"
	return "move"


func _is_movement_control_op(op: String) -> bool:
	return op in [
		"lock_facing_direction",
		"unlock_facing_direction",
		"enable_jump_landing_ground_effect",
		"disable_jump_landing_ground_effect",
		"disable_anim",
		"restore_anim",
		"set_invisible",
		"set_visible",
		"reveal_trainer",
		"rock_smash_break",
		"cut_tree",
		"set_fixed_priority",
		"clear_fixed_priority",
		"init_affine_anim",
		"clear_affine_anim",
		"hide_reflection",
		"show_reflection",
		"lock_anim",
		"unlock_anim",
		"levitate",
		"stop_levitate",
		"destroy_extra_task",
		"figure_8",
		"fly_up",
		"fly_down",
		"exit_pokeball",
		"enter_pokeball",
		"start_anim_in_direction",
	]


func _direction_from_movement_op(op: String) -> String:
	for direction in ["down", "up", "left", "right"]:
		if op.ends_with("_%s" % direction) or op == "face_%s" % direction:
			return direction
	return ""


func _direction_delta(direction: String) -> Array:
	match direction:
		"down":
			return [0, 1]
		"up":
			return [0, -1]
		"left":
			return [-1, 0]
		"right":
			return [1, 0]
	return [0, 0]


func _speed_from_movement_op(op: String) -> String:
	if op.begins_with("player_run_"):
		return "run"
	if op.begins_with("walk_faster_") or op.begins_with("walk_in_place_faster_"):
		return "faster"
	if op.begins_with("walk_fast_") or op.begins_with("walk_in_place_fast_"):
		return "fast"
	if op.begins_with("walk_slow_") or op.begins_with("walk_in_place_slow_"):
		return "slow"
	return "normal"


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
	if _is_known_constant(value):
		return _constant_value(value)
	return int(value)


func _is_known_constant(value: String) -> bool:
	return value in [
		PLAYER_GENDER_MALE,
		PLAYER_GENDER_FEMALE,
		"TRUE",
		"FALSE",
		"YES",
		"NO",
	]


func _constant_value(value: String) -> int:
	match value:
		PLAYER_GENDER_MALE:
			return PLAYER_GENDER_MALE_VALUE
		PLAYER_GENDER_FEMALE:
			return PLAYER_GENDER_FEMALE_VALUE
		"TRUE", "YES":
			return 1
		"FALSE", "NO":
			return 0
	return 0


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


func _get_player_gender() -> String:
	var game_state := _get_game_state()
	if game_state != null and game_state.has_method("get_player_gender"):
		var gender := String(game_state.get_player_gender()).strip_edges().to_upper()
		return PLAYER_GENDER_FEMALE if gender == PLAYER_GENDER_FEMALE else PLAYER_GENDER_MALE
	return PLAYER_GENDER_MALE


func _gender_value(gender: String) -> int:
	return PLAYER_GENDER_FEMALE_VALUE if gender == PLAYER_GENDER_FEMALE else PLAYER_GENDER_MALE_VALUE


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
		"movements": [],
		"object_effects": [],
		"effects": [],
		"unsupported_ops": [],
		"trace": [],
		"wait_buttonpress": false,
		"wait_movement": false,
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


func _get_movement_record(movement_label: String) -> Dictionary:
	var movements = _script_data.get("movements", {})
	if typeof(movements) != TYPE_DICTIONARY:
		return {}
	var record = movements.get(movement_label, {})
	return record if typeof(record) == TYPE_DICTIONARY else {}


func _get_game_state() -> Node:
	if _game_state != null:
		return _game_state
	if is_inside_tree():
		return get_node_or_null("/root/GameState")
	return null
