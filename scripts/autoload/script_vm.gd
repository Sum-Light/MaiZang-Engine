extends Node

const STEP_LIMIT := 128
const MSGBOX_NPC := "MSGBOX_NPC"
const MSGBOX_SIGN := "MSGBOX_SIGN"
const MSGBOX_DEFAULT := "MSGBOX_DEFAULT"
const MSGBOX_YESNO := "MSGBOX_YESNO"
const SAFE_FOLLOWER_FLAG := "FLAG_SAFE_FOLLOWER_MOVEMENT"
const VAR_RESULT := "VAR_RESULT"
const PLACEHOLDER_PLAYER := "PLAYER"
const PLACEHOLDER_KUN := "KUN"
const PLACEHOLDER_RIVAL := "RIVAL"
const PLACEHOLDER_B_PC_CREATOR_NAME := "B_PC_CREATOR_NAME"
const STR_VAR_1 := "STR_VAR_1"
const STR_VAR_2 := "STR_VAR_2"
const STR_VAR_3 := "STR_VAR_3"
const DEFAULT_PLAYER_NAME := "玩家"
const RIVAL_NAME_MALE_PLAYER := "小遥"
const RIVAL_NAME_FEMALE_PLAYER := "小悠"
const BATTLE_PC_CREATOR_SOMEONES := "某人的"
const BATTLE_PC_CREATOR_LANETTES := "真由美的"
const BATTLE_PC_CREATOR_BILLS := "正辉的"
const FLAG_SYS_PC_LANETTE := "FLAG_SYS_PC_LANETTE"
const SOURCE_IS_FRLG := false
const PLAYER_GENDER_MALE := "MALE"
const PLAYER_GENDER_FEMALE := "FEMALE"
const PLAYER_GENDER_MALE_VALUE := 0
const PLAYER_GENDER_FEMALE_VALUE := 1
const TEXT_CTRL_COLOR := "COLOR"
const TEXT_CTRL_SHADOW := "SHADOW"
const TEXT_CTRL_FONT := "FONT"
const TEXT_CTRL_PAUSE := "PAUSE"
const TEXT_CTRL_PAUSE_UNTIL_PRESS := "PAUSE_UNTIL_PRESS"
const TEXT_CONTROL_CODE_IDS := {
	TEXT_CTRL_COLOR: 0x01,
	TEXT_CTRL_SHADOW: 0x03,
	TEXT_CTRL_FONT: 0x06,
	TEXT_CTRL_PAUSE: 0x08,
	TEXT_CTRL_PAUSE_UNTIL_PRESS: 0x09,
}
const TEXT_CONTROL_SOURCE_CODES := {
	TEXT_CTRL_COLOR: "EXT_CTRL_CODE_COLOR",
	TEXT_CTRL_SHADOW: "EXT_CTRL_CODE_SHADOW",
	TEXT_CTRL_FONT: "EXT_CTRL_CODE_FONT",
	TEXT_CTRL_PAUSE: "EXT_CTRL_CODE_PAUSE",
	TEXT_CTRL_PAUSE_UNTIL_PRESS: "EXT_CTRL_CODE_PAUSE_UNTIL_PRESS",
}
const TEXT_CONTROL_SOURCE_LENGTHS := {
	TEXT_CTRL_COLOR: 2,
	TEXT_CTRL_SHADOW: 2,
	TEXT_CTRL_FONT: 2,
	TEXT_CTRL_PAUSE: 2,
	TEXT_CTRL_PAUSE_UNTIL_PRESS: 1,
}
const TEXT_COLOR_IDS := {
	"DARK_GRAY": 0x02,
	"LIGHT_GRAY": 0x03,
	"BLUE": 0x08,
	"LIGHT_BLUE": 0x09,
}
const TEXT_FONT_IDS := {
	"FONT_NORMAL": 0x01,
	"FONT_MALE": 0x01,
	"FONT_FEMALE": 0x01,
}
const MAPGRID_METATILE_ID_MASK := 0x03FF
const MAPGRID_COLLISION_SHIFT := 10
const MAPGRID_COLLISION_IMPASSABLE := 0x03
const WARP_ID_NONE_VALUE := -1
const LOCALID_NONE := "LOCALID_NONE"
const LOCALID_PLAYER := "LOCALID_PLAYER"
const LOCALID_CAMERA := "LOCALID_CAMERA"
const LOCALID_FOLLOWING_POKEMON := "LOCALID_FOLLOWING_POKEMON"
const LOCALID_NONE_VALUE := 0
const LOCALID_CAMERA_VALUE := 127
const LOCALID_FOLLOWING_POKEMON_VALUE := 254
const LOCALID_PLAYER_VALUE := 255
const YESNO_PENDING_VALUE := 0xFF
const YESNO_INPUT_DELAY_FRAMES := 5
const YESNO_DEFAULT_MENU_LEFT := 21
const YESNO_DEFAULT_MENU_TOP := 9
const YESNO_DEFAULT_MENU_WIDTH := 5
const YESNO_DEFAULT_MENU_HEIGHT := 4

var _script_data: Dictionary = {}
var _game_state: Node = null
var _data_registry: Node = null


func _ready() -> void:
	var registry = get_node_or_null("/root/DataRegistry")
	if registry != null and registry.has_method("get_start_script_data"):
		_data_registry = registry
		configure_from_script_data(registry.get_start_script_data())
	_game_state = get_node_or_null("/root/GameState")


func configure_from_script_data(script_data: Dictionary) -> void:
	_script_data = script_data


func configure_game_state(game_state: Node) -> void:
	_game_state = game_state


func configure_data_registry(data_registry: Node) -> void:
	_data_registry = data_registry


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
		"field_effects": [],
		"ui_effects": [],
		"special_effects": [],
		"audio_effects": [],
		"transition_effects": [],
		"player_effects": [],
		"effects": [],
		"unsupported_ops": [],
		"trace": [],
		"string_vars": _initial_string_vars(),
		"context": context,
		"status": "ok",
		"finished": false,
		"last_text_label": "",
		"last_movement_target": "",
		"wait_buttonpress": false,
		"wait_movement": false,
		"wait_ui": false,
		"wait_state": false,
		"wait_audio": false,
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
		"field_effects": state["field_effects"],
		"ui_effects": state["ui_effects"],
		"special_effects": state["special_effects"],
		"audio_effects": state["audio_effects"],
		"transition_effects": state["transition_effects"],
		"player_effects": state["player_effects"],
		"effects": state["effects"],
		"unsupported_ops": state["unsupported_ops"],
		"trace": state["trace"],
		"string_vars": state["string_vars"],
		"wait_buttonpress": bool(state["wait_buttonpress"]),
		"wait_movement": bool(state["wait_movement"]),
		"wait_ui": bool(state["wait_ui"]),
		"wait_state": bool(state["wait_state"]),
		"wait_audio": bool(state["wait_audio"]),
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
		"call_if_set", "call_if_unset", "call_if_lt", "call_if_eq", "call_if_gt", "call_if_le", "call_if_ge", "call_if_ne":
			_execute_conditional_branch(state, op, args, true, line, String(instruction.get("raw", "")))
		"goto_if_set", "goto_if_unset", "goto_if_lt", "goto_if_eq", "goto_if_gt", "goto_if_le", "goto_if_ge", "goto_if_ne":
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
		"special":
			if args.size() >= 1:
				_execute_special(state, String(args[0]), line, String(instruction.get("raw", "")))
			else:
				_record_unsupported(state, op, line, String(instruction.get("raw", "")))
		"checkplayergender":
			_execute_checkplayergender(state, line)
		"lock", "lockall", "release", "releaseall", "faceplayer", "waitmessage", "waitbuttonpress", "closemessage":
			_execute_basic_field_command(state, op, line)
		"waitstate":
			_execute_waitstate(state, line)
		"delay":
			_execute_delay(state, args, line, String(instruction.get("raw", "")))
		"setmetatile":
			_execute_setmetatile(state, args, line, String(instruction.get("raw", "")))
		"opendoor", "closedoor":
			_execute_door_command(state, op, args, line, String(instruction.get("raw", "")))
		"waitdooranim":
			_execute_waitdooranim(state, line)
		"playse":
			_execute_playse(state, args, line, String(instruction.get("raw", "")))
		"playfanfare":
			_execute_playfanfare(state, args, line, String(instruction.get("raw", "")))
		"waitfanfare":
			_execute_waitfanfare(state, line)
		"warp", "warpsilent":
			_execute_warp_command(state, op, args, line, String(instruction.get("raw", "")))
		"hideplayer":
			_execute_hideplayer(state, line)
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
		"yesnobox":
			if args.size() >= 2:
				_execute_yesnobox(state, args, line, String(instruction.get("raw", "")))
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


func _execute_waitstate(state: Dictionary, line: int) -> void:
	state["wait_state"] = true
	_record_field_effect(state, "waitstate", line, {
		"waits_for": "script_context_enable",
	})


func _execute_delay(state: Dictionary, args: Array, line: int, raw: String) -> void:
	if args.size() < 1:
		_record_unsupported(state, "delay", line, raw)
		return

	_record_field_effect(state, "delay", line, {
		"frames": _read_value(String(args[0])),
	})


func _execute_setmetatile(state: Dictionary, args: Array, line: int, raw: String) -> void:
	if args.size() < 4:
		_record_unsupported(state, "setmetatile", line, raw)
		return

	var metatile_token := String(args[2])
	var metatile_info := _resolve_metatile_token(metatile_token)
	if not bool(metatile_info.get("resolved", false)):
		_record_unsupported(state, "setmetatile:metatile_label", line, raw)
		return

	var metatile_raw_value := int(metatile_info.get("id", -1))
	var is_impassable := _read_value(String(args[3])) != 0
	var collision := MAPGRID_COLLISION_IMPASSABLE if is_impassable else ((metatile_raw_value >> MAPGRID_COLLISION_SHIFT) & 0x03)
	_record_field_effect(state, "setmetatile", line, {
		"position": [_read_value(String(args[0])), _read_value(String(args[1]))],
		"x_arg": String(args[0]),
		"y_arg": String(args[1]),
		"metatile_token": metatile_token,
		"metatile_id": metatile_raw_value & MAPGRID_METATILE_ID_MASK,
		"metatile_raw_value": metatile_raw_value,
		"metatile_resolve_source": String(metatile_info.get("source", "")),
		"is_impassable": is_impassable,
		"collision": collision,
		"source_function": "ScrCmd_setmetatile",
		"map_offset_applied_in_source": true,
		"runtime_coordinates_are_unoffset": true,
	})


func _execute_door_command(state: Dictionary, op: String, args: Array, line: int, raw: String) -> void:
	if args.size() < 2:
		_record_unsupported(state, op, line, raw)
		return

	_record_field_effect(state, op, line, {
		"position": [_read_value(String(args[0])), _read_value(String(args[1]))],
		"x_arg": String(args[0]),
		"y_arg": String(args[1]),
	})


func _execute_waitdooranim(state: Dictionary, line: int) -> void:
	_record_field_effect(state, "waitdooranim", line, {
		"waits_for": "door_animation",
	})


func _execute_playse(state: Dictionary, args: Array, line: int, raw: String) -> void:
	if args.size() < 1:
		_record_unsupported(state, "playse", line, raw)
		return

	_record_audio_effect(state, "playse", line, {
		"sound": String(args[0]),
	})


func _execute_playfanfare(state: Dictionary, args: Array, line: int, raw: String) -> void:
	if args.size() < 1:
		_record_unsupported(state, "playfanfare", line, raw)
		return

	_record_audio_effect(state, "playfanfare", line, {
		"fanfare": String(args[0]),
	})


func _execute_waitfanfare(state: Dictionary, line: int) -> void:
	state["wait_audio"] = true
	_record_audio_effect(state, "waitfanfare", line, {
		"waits_for": "fanfare",
	})


func _execute_warp_command(state: Dictionary, op: String, args: Array, line: int, raw: String) -> void:
	if args.size() < 1:
		_record_unsupported(state, op, line, raw)
		return

	var warp_id := WARP_ID_NONE_VALUE
	var x := -1
	var y := -1
	if args.size() == 2:
		warp_id = _read_value(String(args[1]))
	elif args.size() == 3:
		x = _read_value(String(args[1]))
		y = _read_value(String(args[2]))
	elif args.size() >= 4:
		warp_id = _read_value(String(args[1]))
		x = _read_value(String(args[2]))
		y = _read_value(String(args[3]))

	var detail := {
		"map": String(args[0]),
		"warp_id": warp_id,
		"position": [x, y],
		"has_explicit_position": x != -1 or y != -1,
		"uses_warp_id": warp_id != WARP_ID_NONE_VALUE,
		"style": "silent" if op == "warpsilent" else "normal",
		"reset_initial_player_avatar_state": true,
	}
	if op == "warp":
		detail["sound_effect"] = "SE_EXIT"

	_record_transition_effect(state, op, line, detail)


func _execute_hideplayer(state: Dictionary, line: int) -> void:
	_record_player_effect(state, "hideplayer", line, {
		"target": LOCALID_PLAYER,
		"visible": false,
		"source_op": "hideobjectat",
	})


func _execute_checkplayergender(state: Dictionary, line: int) -> void:
	var gender := _get_player_gender()
	var gender_value := _gender_value(gender)
	_set_var(VAR_RESULT, gender_value)
	_record_effect(state, "checkplayergender", line, {
		"gender": gender,
		"value": gender_value,
		"var": VAR_RESULT,
	})


func _execute_special(state: Dictionary, function_name: String, line: int, raw: String) -> void:
	var gender := _get_player_gender()
	match function_name:
		"GetPlayerBigGuyGirlString":
			var text := "大哥哥" if gender == PLAYER_GENDER_MALE else "大姐姐"
			_set_string_var(state, STR_VAR_1, text)
			_record_special_effect(state, line, {
				"function": function_name,
				"gender": gender,
				"writes": [{"var": STR_VAR_1, "value": text}],
				"source": "src/field_specials.c",
				"source_context": "GetPlayerBigGuyGirlString",
				"raw": raw,
			})
		"GetRivalSonDaughterString":
			var text := "女儿" if gender == PLAYER_GENDER_MALE else "儿子"
			_set_string_var(state, STR_VAR_1, text)
			_record_special_effect(state, line, {
				"function": function_name,
				"gender": gender,
				"writes": [{"var": STR_VAR_1, "value": text}],
				"source": "src/field_specials.c",
				"source_context": "GetRivalSonDaughterString",
				"raw": raw,
			})
		_:
			_record_unsupported(state, "special:%s" % function_name, line, raw)


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

	var raw_target := String(args[0])
	var target := _resolve_movement_target(raw_target)
	var movement_label := String(args[1])
	var movement_record := _get_movement_record(movement_label)
	if movement_record.is_empty():
		var missing_movement := {
			"target": target,
			"raw_target": raw_target,
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
	movement["raw_target"] = raw_target
	if has_explicit_map and args.size() >= 4:
		movement["map_group"] = String(args[2])
		movement["map_num"] = String(args[3])

	state["movements"].append(movement)
	state["last_movement_target"] = target
	_record_effect(state, "applymovement", line, {
		"target": target,
		"raw_target": raw_target,
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
	var raw_target := "0"
	if args.size() >= 1:
		raw_target = String(args[0])
	var target := _resolve_movement_target(raw_target)

	var resolved_target := String(state["last_movement_target"])
	if target != "0":
		resolved_target = target
		state["last_movement_target"] = target

	var detail := {
		"target": target,
		"raw_target": raw_target,
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


func _record_field_effect(state: Dictionary, op: String, line: int, detail: Dictionary) -> void:
	var field_effect := {
		"op": op,
		"line": line,
	}
	for key in detail:
		field_effect[key] = detail[key]
	state["field_effects"].append(field_effect)
	_record_effect(state, op, line, detail)


func _record_ui_effect(state: Dictionary, op: String, line: int, detail: Dictionary) -> void:
	var ui_effect := {
		"op": op,
		"line": line,
	}
	for key in detail:
		ui_effect[key] = detail[key]
	state["ui_effects"].append(ui_effect)
	_record_effect(state, op, line, detail)


func _record_special_effect(state: Dictionary, line: int, detail: Dictionary) -> void:
	var special_effect := {
		"op": "special",
		"line": line,
	}
	for key in detail:
		special_effect[key] = detail[key]
	state["special_effects"].append(special_effect)
	_record_effect(state, "special", line, detail)


func _record_audio_effect(state: Dictionary, op: String, line: int, detail: Dictionary) -> void:
	var audio_effect := {
		"op": op,
		"line": line,
	}
	for key in detail:
		audio_effect[key] = detail[key]
	state["audio_effects"].append(audio_effect)
	_record_effect(state, op, line, detail)


func _record_transition_effect(state: Dictionary, op: String, line: int, detail: Dictionary) -> void:
	var transition_effect := {
		"op": op,
		"line": line,
	}
	for key in detail:
		transition_effect[key] = detail[key]
	state["transition_effects"].append(transition_effect)
	_record_effect(state, op, line, detail)


func _record_player_effect(state: Dictionary, op: String, line: int, detail: Dictionary) -> void:
	var player_effect := {
		"op": op,
		"line": line,
	}
	for key in detail:
		player_effect[key] = detail[key]
	state["player_effects"].append(player_effect)
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
		MSGBOX_YESNO:
			_execute_message(state, text_label, mode, "msgbox", line)
			_execute_basic_field_command(state, "waitmessage", line)
			_execute_yesnobox(state, ["20", "8"], line, "yesnobox 20, 8", "Std_MsgboxYesNo")
		_:
			_record_unsupported(state, "msgbox:%s" % mode, line, "msgbox %s, %s" % [text_label, mode])


func _execute_yesnobox(
	state: Dictionary,
	args: Array,
	line: int,
	raw: String,
	source_context: String = "script"
) -> void:
	if args.size() < 2:
		_record_unsupported(state, "yesnobox", line, raw)
		return

	var script_left := _read_value(String(args[0]))
	var script_top := _read_value(String(args[1]))
	var choice := _resolve_yesno_choice(state)
	var selected_choice := String(choice.get("choice", "PENDING"))
	var selected_value := int(choice.get("value", YESNO_PENDING_VALUE))
	_set_var(VAR_RESULT, selected_value)
	state["wait_ui"] = true
	_record_ui_effect(state, "yesnobox", line, {
		"script_position": [script_left, script_top],
		"menu_position": [YESNO_DEFAULT_MENU_LEFT, YESNO_DEFAULT_MENU_TOP],
		"menu_size": [YESNO_DEFAULT_MENU_WIDTH, YESNO_DEFAULT_MENU_HEIGHT],
		"script_position_ignored": true,
		"default_choice": "YES",
		"default_value": _constant_value("YES"),
		"b_choice": "NO",
		"b_value": _constant_value("NO"),
		"pending_value": YESNO_PENDING_VALUE,
		"input_delay_frames": YESNO_INPUT_DELAY_FRAMES,
		"result_var": VAR_RESULT,
		"selected_choice": selected_choice,
		"selected_value": selected_value,
		"choice_source": String(choice.get("source", "")),
		"source": "ScriptMenu_YesNo",
		"source_context": source_context,
		"raw": raw,
	})
	if not bool(choice.get("has_choice", false)):
		state["status"] = "waiting_for_ui"
		state["finished"] = true


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
	var encoding = text_record.get("encoding", {})
	var encoding_status := "unknown"
	var source_byte_count := 0
	var terminator_present := false
	if typeof(encoding) == TYPE_DICTIONARY:
		encoding_status = String(encoding.get("status", "unknown"))
		source_byte_count = int(encoding.get("byte_count", 0))
		terminator_present = bool(encoding.get("terminator_present", false))
	var unexpanded_text := String(text_record.get("display_text", ""))
	var placeholder_substitutions := _placeholder_substitutions(state, unexpanded_text)
	var expanded_text := _expand_message_placeholders(state, unexpanded_text)
	var text_control_result := _parse_text_controls(expanded_text)
	var text_controls: Array = text_control_result.get("text_controls", [])
	if _text_controls_wait_for_buttonpress(text_controls):
		state["wait_buttonpress"] = true
	state["messages"].append({
		"text_label": text_label,
		"mode": mode,
		"op": source_op,
		"line": line,
		"text": String(text_control_result.get("text", expanded_text)),
		"unexpanded_text": unexpanded_text,
		"expanded_text": expanded_text,
		"placeholder_substitutions": placeholder_substitutions,
		"text_controls": text_controls,
		"status": status,
		"text_source": String(text_record.get("source", "")),
		"text_kind": String(text_record.get("kind", "text")),
		"encoding_status": encoding_status,
		"source_byte_count": source_byte_count,
		"terminator_present": terminator_present,
	})
	_record_effect(state, "message", line, {
		"text_label": text_label,
		"mode": mode,
		"status": status,
		"encoding_status": encoding_status,
		"placeholder_substitution_count": placeholder_substitutions.size(),
		"text_control_count": text_controls.size(),
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
		"call_if_lt", "goto_if_lt":
			return _read_value(String(args[0])) < _read_value(String(args[1]))
		"call_if_eq", "goto_if_eq":
			return _read_value(String(args[0])) == _read_value(String(args[1]))
		"call_if_gt", "goto_if_gt":
			return _read_value(String(args[0])) > _read_value(String(args[1]))
		"call_if_le", "goto_if_le":
			return _read_value(String(args[0])) <= _read_value(String(args[1]))
		"call_if_ge", "goto_if_ge":
			return _read_value(String(args[0])) >= _read_value(String(args[1]))
		"call_if_ne", "goto_if_ne":
			return _read_value(String(args[0])) != _read_value(String(args[1]))
	return false


func _resolve_metatile_token(token: String) -> Dictionary:
	var value := token.strip_edges()
	if value.begins_with("METATILE_"):
		var label_id := _metatile_label_id(value)
		return {
			"resolved": label_id >= 0,
			"id": label_id,
			"source": "generated_tileset_metatile_labels",
		}

	return {
		"resolved": true,
		"id": _read_value(value),
		"source": "script_literal",
	}


func _metatile_label_id(label: String) -> int:
	var tileset_data := _current_tileset_data()
	var label_data = tileset_data.get("metatile_labels", {})
	if typeof(label_data) != TYPE_DICTIONARY:
		return -1

	var ids = label_data.get("ids", {})
	if typeof(ids) == TYPE_DICTIONARY and ids.has(label):
		return int(ids[label])

	var entries = label_data.get("entries", [])
	if typeof(entries) != TYPE_ARRAY:
		return -1
	for entry in entries:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if String(entry.get("name", "")) == label:
			return int(entry.get("id", -1))
	return -1


func _current_tileset_data() -> Dictionary:
	var registry := _get_data_registry()
	if registry == null:
		return {}

	var map_id := _current_map_id()
	if not map_id.is_empty() and registry.has_method("get_tileset_data_for_map"):
		var tileset_data = registry.get_tileset_data_for_map(map_id)
		if typeof(tileset_data) == TYPE_DICTIONARY and not tileset_data.is_empty():
			return tileset_data

	if registry.has_method("get_start_tileset_data"):
		var start_tileset_data = registry.get_start_tileset_data()
		if typeof(start_tileset_data) == TYPE_DICTIONARY:
			return start_tileset_data
	return {}


func _current_map_id() -> String:
	var game_state := _get_game_state()
	if game_state == null:
		return ""
	var map_id = game_state.get("current_map_id")
	return String(map_id) if map_id != null else ""


func _read_value(token: String) -> int:
	var value := token.strip_edges()
	if value.begins_with("VAR_"):
		return _get_var(value)
	if _is_known_constant(value):
		return _constant_value(value)
	if value.begins_with("LOCALID_"):
		var local_id_value := _local_id_value(value)
		if bool(local_id_value.get("resolved", false)):
			return int(local_id_value.get("value", 0))
	return int(value)


func _resolve_movement_target(token: String) -> String:
	var value := token.strip_edges()
	if value == LOCALID_PLAYER:
		return LOCALID_PLAYER
	if value == LOCALID_NONE:
		return "0"
	if value.begins_with("VAR_") or value.begins_with("LOCALID_") or value.is_valid_int():
		var resolved_value := _read_value(value)
		if resolved_value == LOCALID_PLAYER_VALUE:
			return LOCALID_PLAYER
		return str(resolved_value)
	return value


func _is_known_constant(value: String) -> bool:
	return value in [
		PLAYER_GENDER_MALE,
		PLAYER_GENDER_FEMALE,
		"TRUE",
		"FALSE",
		"YES",
		"NO",
		"WARP_ID_NONE",
		LOCALID_NONE,
		LOCALID_CAMERA,
		LOCALID_FOLLOWING_POKEMON,
		LOCALID_PLAYER,
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
		"WARP_ID_NONE":
			return WARP_ID_NONE_VALUE
		LOCALID_NONE:
			return LOCALID_NONE_VALUE
		LOCALID_CAMERA:
			return LOCALID_CAMERA_VALUE
		LOCALID_FOLLOWING_POKEMON:
			return LOCALID_FOLLOWING_POKEMON_VALUE
		LOCALID_PLAYER:
			return LOCALID_PLAYER_VALUE
	return 0


func _local_id_value(local_id: String) -> Dictionary:
	var map_data := _current_map_data_for_local_ids()
	var events = map_data.get("events", {})
	var object_events = events.get("object_events", []) if typeof(events) == TYPE_DICTIONARY else []
	if typeof(object_events) == TYPE_ARRAY:
		for index in range(object_events.size()):
			var object_event = object_events[index]
			if typeof(object_event) == TYPE_DICTIONARY and String(object_event.get("local_id", "")) == local_id:
				return {
					"resolved": true,
					"value": index + 1,
					"source": "tools/mapjson/mapjson.cpp local_id i+1",
				}
	return {
		"resolved": false,
		"value": 0,
		"source": "unresolved_local_id",
	}


func _current_map_data_for_local_ids() -> Dictionary:
	var registry := _get_data_registry()
	if registry == null:
		return {}

	var map_id := _current_map_id()
	if not map_id.is_empty() and registry.has_method("get_map_data"):
		var map_data = registry.get_map_data(map_id)
		if typeof(map_data) == TYPE_DICTIONARY and not map_data.is_empty():
			return map_data

	if registry.has_method("get_start_map_data"):
		var start_map_data = registry.get_start_map_data()
		return start_map_data if typeof(start_map_data) == TYPE_DICTIONARY else {}
	return {}


func _resolve_yesno_choice(state: Dictionary) -> Dictionary:
	var context = state.get("context", {})
	if typeof(context) != TYPE_DICTIONARY:
		return _yesno_choice_record("PENDING", YESNO_PENDING_VALUE, false, "")

	for key in ["yesno_choice", "menu_choice", "choice"]:
		if context.has(key):
			return _parse_yesno_choice(context[key], key)
	return _yesno_choice_record("PENDING", YESNO_PENDING_VALUE, false, "")


func _parse_yesno_choice(value, source_key: String) -> Dictionary:
	match typeof(value):
		TYPE_BOOL:
			if bool(value):
				return _yesno_choice_record("YES", _constant_value("YES"), true, source_key)
			return _yesno_choice_record("NO", _constant_value("NO"), true, source_key)
		TYPE_INT, TYPE_FLOAT:
			var int_value := int(value)
			if int_value == _constant_value("YES"):
				return _yesno_choice_record("YES", _constant_value("YES"), true, source_key)
			if int_value == _constant_value("NO"):
				return _yesno_choice_record("NO", _constant_value("NO"), true, source_key)

	var text := String(value).strip_edges().to_upper()
	match text:
		"YES", "TRUE", "1":
			return _yesno_choice_record("YES", _constant_value("YES"), true, source_key)
		"NO", "FALSE", "0":
			return _yesno_choice_record("NO", _constant_value("NO"), true, source_key)
		"B", "MENU_B_PRESSED":
			return _yesno_choice_record("B", _constant_value("NO"), true, source_key)
	return _yesno_choice_record("PENDING", YESNO_PENDING_VALUE, false, source_key)


func _yesno_choice_record(choice: String, value: int, has_choice: bool, source_key: String) -> Dictionary:
	return {
		"choice": choice,
		"value": value,
		"has_choice": has_choice,
		"source": source_key,
	}


func _initial_string_vars() -> Dictionary:
	return {
		STR_VAR_1: "",
		STR_VAR_2: "",
		STR_VAR_3: "",
	}


func _string_var_names() -> Array:
	return [STR_VAR_1, STR_VAR_2, STR_VAR_3]


func _placeholder_names() -> Array:
	return [
		PLACEHOLDER_PLAYER,
		PLACEHOLDER_KUN,
		PLACEHOLDER_RIVAL,
		PLACEHOLDER_B_PC_CREATOR_NAME,
		STR_VAR_1,
		STR_VAR_2,
		STR_VAR_3,
	]


func _placeholder_id(placeholder_name: String) -> int:
	match placeholder_name:
		PLACEHOLDER_PLAYER:
			return 0x1
		STR_VAR_1:
			return 0x2
		STR_VAR_2:
			return 0x3
		STR_VAR_3:
			return 0x4
		PLACEHOLDER_KUN:
			return 0x5
		PLACEHOLDER_RIVAL:
			return 0x6
		PLACEHOLDER_B_PC_CREATOR_NAME:
			return 0x27
	return 0


func _set_string_var(state: Dictionary, var_name: String, value: String) -> void:
	var string_vars = state.get("string_vars", {})
	if typeof(string_vars) != TYPE_DICTIONARY:
		string_vars = _initial_string_vars()
	string_vars[var_name] = value
	state["string_vars"] = string_vars


func _get_string_var(state: Dictionary, var_name: String) -> String:
	var string_vars = state.get("string_vars", {})
	if typeof(string_vars) != TYPE_DICTIONARY:
		return ""
	return String(string_vars.get(var_name, ""))


func _placeholder_value(state: Dictionary, placeholder_name: String) -> String:
	match placeholder_name:
		PLACEHOLDER_PLAYER:
			return _get_player_name()
		PLACEHOLDER_KUN:
			return _get_kun_placeholder()
		PLACEHOLDER_RIVAL:
			return _get_rival_placeholder()
		PLACEHOLDER_B_PC_CREATOR_NAME:
			return _get_battle_pc_creator_placeholder()
	return _get_string_var(state, placeholder_name)


func _placeholder_value_key(placeholder_name: String) -> String:
	match placeholder_name:
		PLACEHOLDER_B_PC_CREATOR_NAME:
			return _battle_pc_creator_key()
	return placeholder_name


func _placeholder_source(placeholder_name: String) -> String:
	match placeholder_name:
		PLACEHOLDER_B_PC_CREATOR_NAME:
			return "BattleStringExpandPlaceholders"
	return "StringExpandPlaceholders"


func _placeholder_substitutions(state: Dictionary, display_text: String) -> Array:
	var substitutions: Array = []
	for placeholder_name in _placeholder_names():
		var placeholder_name_string := String(placeholder_name)
		var token := "{%s}" % placeholder_name_string
		var cursor := display_text.find(token)
		while cursor != -1:
			substitutions.append({
				"token": token,
				"var": placeholder_name_string,
				"placeholder_id": _placeholder_id(placeholder_name_string),
				"value": _placeholder_value(state, placeholder_name_string),
				"value_key": _placeholder_value_key(placeholder_name_string),
				"offset": cursor,
				"source": _placeholder_source(placeholder_name_string),
			})
			cursor = display_text.find(token, cursor + token.length())
	return substitutions


func _expand_message_placeholders(state: Dictionary, display_text: String) -> String:
	var expanded := display_text
	for placeholder_name in _placeholder_names():
		var token := "{%s}" % String(placeholder_name)
		expanded = expanded.replace(token, _placeholder_value(state, String(placeholder_name)))
	return expanded


func _parse_text_controls(display_text: String) -> Dictionary:
	var clean_text := ""
	var text_controls: Array = []
	var cursor := 0
	while cursor < display_text.length():
		var open_index := display_text.find("{", cursor)
		if open_index == -1:
			clean_text += display_text.substr(cursor)
			break
		var close_index := display_text.find("}", open_index + 1)
		if close_index == -1:
			clean_text += display_text.substr(cursor)
			break

		clean_text += display_text.substr(cursor, open_index - cursor)
		var token := display_text.substr(open_index, close_index - open_index + 1)
		var token_body := display_text.substr(open_index + 1, close_index - open_index - 1).strip_edges()
		var control := _text_control_record(token_body, token, open_index, clean_text.length())
		if control.is_empty():
			clean_text += token
		else:
			text_controls.append(control)
		cursor = close_index + 1
	return {
		"text": clean_text,
		"text_controls": text_controls,
	}


func _text_control_record(token_body: String, token: String, offset: int, text_offset: int) -> Dictionary:
	var parts := token_body.split(" ", false)
	if parts.is_empty():
		return {}

	var control_name := String(parts[0])
	match control_name:
		TEXT_CTRL_COLOR, TEXT_CTRL_SHADOW:
			if parts.size() != 2:
				return {}
			var color_name := String(parts[1])
			if not TEXT_COLOR_IDS.has(color_name):
				return {}
			var record := _base_text_control_record(token, control_name, offset, text_offset)
			record["value"] = color_name
			record["value_id"] = int(TEXT_COLOR_IDS[color_name])
			record["source_value"] = "TEXT_COLOR_%s" % color_name
			return record
		TEXT_CTRL_PAUSE:
			if parts.size() != 2:
				return {}
			var frame_text := String(parts[1])
			if not frame_text.is_valid_int():
				return {}
			var frames := int(frame_text)
			var record := _base_text_control_record(token, control_name, offset, text_offset)
			record["value"] = frame_text
			record["value_id"] = frames
			record["frames"] = frames
			return record
		TEXT_CTRL_PAUSE_UNTIL_PRESS:
			if parts.size() != 1:
				return {}
			var record := _base_text_control_record(token, control_name, offset, text_offset)
			record["waits_for"] = "button_press"
			return record
		TEXT_CTRL_FONT:
			if parts.size() != 2:
				return {}
			return _font_text_control_record(String(parts[1]), token, offset, text_offset)
		_:
			if parts.size() == 1 and TEXT_FONT_IDS.has(control_name):
				return _font_text_control_record(control_name, token, offset, text_offset)
	return {}


func _font_text_control_record(font_name: String, token: String, offset: int, text_offset: int) -> Dictionary:
	if not TEXT_FONT_IDS.has(font_name):
		if not font_name.is_valid_int():
			return {}
		var font_id := int(font_name)
		var numeric_record := _base_text_control_record(token, TEXT_CTRL_FONT, offset, text_offset)
		numeric_record["value"] = font_name
		numeric_record["value_id"] = font_id
		numeric_record["font"] = font_name
		numeric_record["font_id"] = font_id
		return numeric_record

	var record := _base_text_control_record(token, TEXT_CTRL_FONT, offset, text_offset)
	record["value"] = font_name
	record["value_id"] = int(TEXT_FONT_IDS[font_name])
	record["font"] = font_name
	record["font_id"] = int(TEXT_FONT_IDS[font_name])
	return record


func _base_text_control_record(token: String, control_name: String, offset: int, text_offset: int) -> Dictionary:
	return {
		"token": token,
		"control": control_name,
		"code": String(TEXT_CONTROL_SOURCE_CODES.get(control_name, "")),
		"code_id": int(TEXT_CONTROL_CODE_IDS.get(control_name, 0)),
		"source_length": int(TEXT_CONTROL_SOURCE_LENGTHS.get(control_name, 0)),
		"offset": offset,
		"text_offset": text_offset,
		"source": "src/text.c",
		"length_source": "src/string_util.c:GetExtCtrlCodeLength",
	}


func _text_controls_wait_for_buttonpress(text_controls: Array) -> bool:
	for control in text_controls:
		if typeof(control) == TYPE_DICTIONARY and String(control.get("control", "")) == TEXT_CTRL_PAUSE_UNTIL_PRESS:
			return true
	return false


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


func _get_player_name() -> String:
	var game_state := _get_game_state()
	if game_state != null and game_state.has_method("get_player_name"):
		var player_name := String(game_state.get_player_name())
		return DEFAULT_PLAYER_NAME if player_name.is_empty() else player_name
	return DEFAULT_PLAYER_NAME


func _get_kun_placeholder() -> String:
	return ""


func _get_rival_placeholder() -> String:
	return RIVAL_NAME_FEMALE_PLAYER if _get_player_gender() == PLAYER_GENDER_FEMALE else RIVAL_NAME_MALE_PLAYER


func _get_battle_pc_creator_placeholder() -> String:
	match _battle_pc_creator_key():
		"LANETTES":
			return BATTLE_PC_CREATOR_LANETTES
		"BILLS":
			return BATTLE_PC_CREATOR_BILLS
	return BATTLE_PC_CREATOR_SOMEONES


func _battle_pc_creator_key() -> String:
	if _is_flag_set(FLAG_SYS_PC_LANETTE):
		return "BILLS" if SOURCE_IS_FRLG else "LANETTES"
	return "SOMEONES"


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
		"field_effects": [],
		"ui_effects": [],
		"special_effects": [],
		"audio_effects": [],
		"transition_effects": [],
		"player_effects": [],
		"effects": [],
		"unsupported_ops": [],
		"trace": [],
		"string_vars": _initial_string_vars(),
		"wait_buttonpress": false,
		"wait_movement": false,
		"wait_ui": false,
		"wait_state": false,
		"wait_audio": false,
		"step_count": 0,
	}


func _get_script_record(script_label: String) -> Dictionary:
	var scripts = _script_data.get("scripts", {})
	if typeof(scripts) == TYPE_DICTIONARY:
		var record = scripts.get(script_label, {})
		if typeof(record) == TYPE_DICTIONARY and not record.is_empty():
			return record

	var registry := _get_data_registry()
	if registry != null and registry.has_method("get_script_record"):
		var global_record = registry.get_script_record(script_label)
		if typeof(global_record) == TYPE_DICTIONARY:
			return global_record
	return {}


func _get_text_record(text_label: String) -> Dictionary:
	var texts = _script_data.get("texts", {})
	if typeof(texts) == TYPE_DICTIONARY:
		var record = texts.get(text_label, {})
		if typeof(record) == TYPE_DICTIONARY and not record.is_empty():
			return record

	var registry := _get_data_registry()
	if registry != null and registry.has_method("get_script_text_record"):
		var script_record = registry.get_script_text_record(text_label)
		if typeof(script_record) == TYPE_DICTIONARY and not script_record.is_empty():
			return script_record
	if registry != null and registry.has_method("get_text_record"):
		var global_record = registry.get_text_record(text_label, "global")
		if typeof(global_record) == TYPE_DICTIONARY:
			return global_record
	return {}


func _get_movement_record(movement_label: String) -> Dictionary:
	var movements = _script_data.get("movements", {})
	if typeof(movements) == TYPE_DICTIONARY:
		var record = movements.get(movement_label, {})
		if typeof(record) == TYPE_DICTIONARY and not record.is_empty():
			return record

	var registry := _get_data_registry()
	if registry != null and registry.has_method("get_movement_record"):
		var global_record = registry.get_movement_record(movement_label)
		if typeof(global_record) == TYPE_DICTIONARY:
			return global_record
	return {}


func _get_game_state() -> Node:
	if _game_state != null:
		return _game_state
	if is_inside_tree():
		return get_node_or_null("/root/GameState")
	return null


func _get_data_registry() -> Node:
	if _data_registry != null:
		return _data_registry
	if is_inside_tree():
		return get_node_or_null("/root/DataRegistry")
	return null
