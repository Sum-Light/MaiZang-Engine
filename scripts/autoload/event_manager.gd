extends Node

signal debug_message_requested(lines: PackedStringArray)
signal transition_sequence_requested(sequence: Dictionary)

const WARP_ID_NONE_VALUE := -1
const DOOR_ANIM_FRAME_TIME := 4
const DOOR_ANIM_FRAME_COUNT := 4
const DOOR_ANIM_TOTAL_FRAMES := DOOR_ANIM_FRAME_TIME * DOOR_ANIM_FRAME_COUNT
const WALK_NORMAL_TILE_FRAMES := 16
const FADE_DELAY_DEFAULT := 0
const WARP_EXIT_DOOR_BEHAVIORS := {
	"MB_PETALBURG_GYM_DOOR": true,
	"MB_ANIMATED_DOOR": true,
}
const WARP_EXIT_DIRECTIONAL_STAIR_BEHAVIORS := {
	"MB_UP_RIGHT_STAIR_WARP": true,
	"MB_UP_LEFT_STAIR_WARP": true,
	"MB_DOWN_RIGHT_STAIR_WARP": true,
	"MB_DOWN_LEFT_STAIR_WARP": true,
}
const WARP_EXIT_NON_ANIM_DOOR_BEHAVIORS := {
	"MB_NON_ANIMATED_DOOR": true,
	"MB_WATER_DOOR": true,
	"MB_DEEP_SOUTH_WARP": true,
}

var _script_data: Dictionary = {}
var _script_vm: Node = null
var _map_runtime: Node = null
var _game_state: Node = null
var _data_registry: Node = null
var _defer_transition_apply := false
var _next_transition_sequence_id := 1
var _pending_transitions := {}


func _ready() -> void:
	_script_vm = get_node_or_null("/root/ScriptVM")
	_map_runtime = get_node_or_null("/root/MapRuntime")
	_game_state = get_node_or_null("/root/GameState")
	_data_registry = get_node_or_null("/root/DataRegistry")
	if _data_registry != null and _data_registry.has_method("get_start_script_data"):
		configure_from_script_data(_data_registry.get_start_script_data())


func configure_from_script_data(script_data: Dictionary) -> void:
	_script_data = script_data
	if _script_vm != null and _script_vm.has_method("configure_from_script_data"):
		_script_vm.configure_from_script_data(script_data)


func configure_script_vm(script_vm: Node) -> void:
	_script_vm = script_vm
	if _script_vm != null and _script_vm.has_method("configure_from_script_data"):
		_script_vm.configure_from_script_data(_script_data)


func configure_map_runtime(map_runtime: Node) -> void:
	_map_runtime = map_runtime


func configure_game_state(game_state: Node) -> void:
	_game_state = game_state


func configure_data_registry(data_registry: Node) -> void:
	_data_registry = data_registry


func configure_transition_deferred(value: bool) -> void:
	_defer_transition_apply = value
	if not _defer_transition_apply:
		_pending_transitions.clear()


func has_pending_transition(sequence_id: int) -> bool:
	return _pending_transitions.has(sequence_id)


func apply_deferred_transition(sequence_id: int) -> Dictionary:
	var pending = _pending_transitions.get(sequence_id, {})
	if typeof(pending) != TYPE_DICTIONARY or pending.is_empty():
		return {
			"status": "missing_pending_transition",
			"id": sequence_id,
			"position_applied": false,
		}

	_pending_transitions.erase(sequence_id)
	return _apply_transition_payload(pending)


func dispatch_interaction(interaction: Dictionary) -> void:
	if interaction.is_empty():
		debug_message_requested.emit(PackedStringArray(["Nothing to interact with."]))
		return

	var event = interaction.get("event", {})
	if typeof(event) != TYPE_DICTIONARY:
		debug_message_requested.emit(PackedStringArray(["Unsupported interaction target."]))
		return

	var event_data: Dictionary = event
	var interaction_type := String(interaction.get("type", ""))
	match interaction_type:
		"object_event":
			_emit_object_event(interaction, event_data)
		"bg_event":
			_emit_bg_event(interaction, event_data)
		"warp_event":
			_emit_warp_event(interaction, event_data)
		"coord_event":
			_emit_coord_event(interaction, event_data)
		_:
			debug_message_requested.emit(PackedStringArray([
				"Interaction: %s" % interaction_type,
				"Source event type is not handled yet.",
			]))


func _emit_object_event(interaction: Dictionary, event_data: Dictionary) -> void:
	var script := String(interaction.get("script", event_data.get("script", "0x0")))
	var lines := PackedStringArray([
		"Object event",
		"Position: %s" % interaction.get("position", Vector2i.ZERO),
		"Graphics: %s" % String(event_data.get("graphics_id", "unknown")),
	])
	_append_script_output(lines, script, {
		"interaction_type": "object_event",
		"event": event_data,
	})
	debug_message_requested.emit(lines)


func _emit_bg_event(interaction: Dictionary, event_data: Dictionary) -> void:
	var script := String(interaction.get("script", event_data.get("script", "0x0")))
	var lines := PackedStringArray([
		"BG event: %s" % String(event_data.get("type", "unknown")),
		"Position: %s" % interaction.get("position", Vector2i.ZERO),
	])
	_append_script_output(lines, script, {
		"interaction_type": "bg_event",
		"event": event_data,
	})
	debug_message_requested.emit(lines)


func _emit_coord_event(interaction: Dictionary, event_data: Dictionary) -> void:
	var script := String(interaction.get("script", event_data.get("script", "0x0")))
	var lines := PackedStringArray([
		"Coord event",
		"Position: %s" % interaction.get("position", Vector2i.ZERO),
		"Trigger: %s == %s" % [
			String(event_data.get("var", event_data.get("trigger", ""))),
			String(event_data.get("var_value", event_data.get("index", ""))),
		],
	])
	_append_script_output(lines, script, {
		"interaction_type": "coord_event",
		"event": event_data,
	})
	debug_message_requested.emit(lines)


func _emit_warp_event(interaction: Dictionary, event_data: Dictionary) -> void:
	var lines := PackedStringArray([
		"Warp event",
		"Position: %s" % interaction.get("position", Vector2i.ZERO),
		"Destination: %s / warp %s" % [
			String(event_data.get("dest_map", "unknown")),
			String(event_data.get("dest_warp_id", "?")),
		],
	])
	var transition_summary := _apply_map_warp_event(interaction, event_data)
	lines.append("Warp effects: %d applied, %d skipped" % [
		_movement_summary_count(transition_summary, "applied"),
		_movement_summary_count(transition_summary, "skipped"),
	])
	debug_message_requested.emit(lines)


func get_script_preview(script: String) -> Dictionary:
	if script.is_empty() or script == "0x0":
		return {}

	var result := run_script(script)
	var messages = result.get("messages", [])
	if typeof(messages) == TYPE_ARRAY and not messages.is_empty():
		var message = messages[0]
		if typeof(message) == TYPE_DICTIONARY:
			return {
				"script_label": script,
				"text_label": String(message.get("text_label", "")),
				"mode": String(message.get("mode", "")),
				"op": String(message.get("op", "msgbox")),
				"line": int(message.get("line", 0)),
				"text": String(message.get("text", "")),
				"status": String(message.get("status", "ok")),
				"text_source": String(message.get("text_source", "")),
				"text_kind": String(message.get("text_kind", "text")),
				"encoding_status": String(message.get("encoding_status", "")),
				"source_byte_count": int(message.get("source_byte_count", 0)),
				"terminator_present": bool(message.get("terminator_present", false)),
				"vm_status": String(result.get("status", "")),
			}

	if not result.is_empty() and String(result.get("status", "")) != "vm_unavailable":
		return {
			"script_label": script,
			"status": "no_preview_message",
			"vm_status": String(result.get("status", "")),
		}

	return _get_direct_script_preview(script)


func run_script(script: String, context: Dictionary = {}) -> Dictionary:
	if _script_vm != null and _script_vm.has_method("run_script"):
		return _script_vm.run_script(script, context)
	return {
		"script_label": script,
		"status": "vm_unavailable",
		"finished": true,
		"messages": [],
		"movements": [],
		"object_effects": [],
		"field_effects": [],
		"audio_effects": [],
		"transition_effects": [],
		"player_effects": [],
		"effects": [],
		"unsupported_ops": [],
		"trace": [],
		"wait_buttonpress": false,
		"wait_movement": false,
		"wait_state": false,
		"wait_audio": false,
		"step_count": 0,
	}


func _get_direct_script_preview(script: String) -> Dictionary:
	var script_record := _get_script_record(script)
	if script_record.is_empty():
		return {}

	var msgbox := _first_msgbox(script_record)
	if msgbox.is_empty():
		return {
			"script_label": script,
			"status": "no_preview_message",
		}

	var text_label := String(msgbox.get("text_label", ""))
	var text_record := _get_text_record(text_label)
	var encoding = text_record.get("encoding", {})
	var encoding_status := ""
	var source_byte_count := 0
	var terminator_present := false
	if typeof(encoding) == TYPE_DICTIONARY:
		encoding_status = String(encoding.get("status", ""))
		source_byte_count = int(encoding.get("byte_count", 0))
		terminator_present = bool(encoding.get("terminator_present", false))
	return {
		"script_label": script,
		"text_label": text_label,
		"mode": String(msgbox.get("mode", "")),
		"op": String(msgbox.get("op", "msgbox")),
		"line": int(msgbox.get("line", 0)),
		"text": String(text_record.get("display_text", "")),
		"status": "ok" if not text_record.is_empty() else "missing_text",
		"text_source": String(text_record.get("source", "")),
		"text_kind": String(text_record.get("kind", "text")),
		"encoding_status": encoding_status,
		"source_byte_count": source_byte_count,
		"terminator_present": terminator_present,
	}


func _append_script_output(lines: PackedStringArray, script: String, context: Dictionary) -> void:
	if script.is_empty() or script == "0x0":
		lines.append("Script: none")
		return

	lines.append("Script: %s" % script)
	var result := run_script(script, context)
	if result.is_empty():
		lines.append("ScriptVM: unavailable")
		return

	var vm_status := String(result.get("status", ""))
	if vm_status == "vm_unavailable":
		_append_direct_preview_output(lines, script)
		return

	lines.append("ScriptVM: %s" % vm_status)
	var runtime_summary := _apply_runtime_result(result)
	var movement_summary = runtime_summary.get("movements", {})
	if typeof(movement_summary) == TYPE_DICTIONARY and not movement_summary.is_empty():
		lines.append("Movement effects: %d applied, %d skipped" % [
			_movement_summary_count(movement_summary, "applied"),
			_movement_summary_count(movement_summary, "skipped"),
		])

	var object_effect_summary = runtime_summary.get("object_effects", {})
	if typeof(object_effect_summary) == TYPE_DICTIONARY and not object_effect_summary.is_empty():
		lines.append("Object effects: %d applied, %d skipped" % [
			_movement_summary_count(object_effect_summary, "applied"),
			_movement_summary_count(object_effect_summary, "skipped"),
		])

	var transition_summary = runtime_summary.get("transition_effects", {})
	if typeof(transition_summary) == TYPE_DICTIONARY and not transition_summary.is_empty():
		lines.append("Transition effects: %d applied, %d skipped" % [
			_movement_summary_count(transition_summary, "applied"),
			_movement_summary_count(transition_summary, "skipped"),
		])

	var messages = result.get("messages", [])
	if typeof(messages) == TYPE_ARRAY and not messages.is_empty():
		for message in messages:
			if typeof(message) != TYPE_DICTIONARY:
				continue
			lines.append("Text label: %s" % String(message.get("text_label", "")))
			lines.append("Mode: %s" % String(message.get("mode", "")))
			lines.append("")
			lines.append(String(message.get("text", "")))
		return

	var unsupported_ops = result.get("unsupported_ops", [])
	if typeof(unsupported_ops) == TYPE_ARRAY and not unsupported_ops.is_empty():
		var unsupported = unsupported_ops[0]
		if typeof(unsupported) == TYPE_DICTIONARY:
			lines.append("Unsupported op: %s" % String(unsupported.get("op", "")))
			lines.append("Line: %d" % int(unsupported.get("line", 0)))
		return

	lines.append("No message emitted")


func _apply_runtime_result(result: Dictionary) -> Dictionary:
	var summary := {}
	if _map_runtime == null:
		return {}

	var movements = result.get("movements", [])
	if typeof(movements) == TYPE_ARRAY and not movements.is_empty() and _map_runtime.has_method("apply_script_movements"):
		summary["movements"] = _map_runtime.apply_script_movements(movements, _game_state)

	var object_effects = result.get("object_effects", [])
	if typeof(object_effects) == TYPE_ARRAY and not object_effects.is_empty() and _map_runtime.has_method("apply_script_object_effects"):
		summary["object_effects"] = _map_runtime.apply_script_object_effects(object_effects, _game_state)

	var transition_effects = result.get("transition_effects", [])
	if typeof(transition_effects) == TYPE_ARRAY and not transition_effects.is_empty():
		summary["transition_effects"] = _apply_transition_effects(transition_effects)

	return summary


func _apply_transition_effects(transition_effects: Array) -> Dictionary:
	var summary := {
		"applied": [],
		"skipped": [],
	}
	for transition_effect in transition_effects:
		if typeof(transition_effect) != TYPE_DICTIONARY:
			_record_skipped_transition(summary, "invalid_transition_effect", "", "", Vector2i.ZERO)
			continue

		var effect: Dictionary = transition_effect
		var op := String(effect.get("op", ""))
		var map_id := String(effect.get("map", ""))
		var position := _transition_position(effect)
		var position_source := "explicit" if bool(effect.get("has_explicit_position", false)) else "unset"
		var source_map_id := _current_map_id()
		var source_position := _transition_vector(effect, "source_position", _current_player_position())
		var trigger_position := _transition_vector(effect, "trigger_position", source_position)
		if map_id.is_empty():
			_record_skipped_transition(summary, "missing_map", map_id, op, position)
			continue
		if _data_registry == null or not _data_registry.has_method("has_map_data"):
			_record_skipped_transition(summary, "missing_data_registry", map_id, op, position)
			continue
		if not _data_registry.has_map_data(map_id):
			_record_skipped_transition(summary, "missing_generated_map", map_id, op, position)
			continue
		if _map_runtime == null or not _map_runtime.has_method("configure_from_data"):
			_record_skipped_transition(summary, "missing_map_runtime", map_id, op, position)
			continue

		var map_data: Dictionary = _data_registry.get_map_data(map_id)
		if not bool(effect.get("has_explicit_position", false)):
			var warp_id_info := _warp_id_from_value(effect.get("warp_id", WARP_ID_NONE_VALUE))
			if not bool(warp_id_info.get("valid", false)):
				_record_skipped_transition(summary, String(warp_id_info.get("reason", "invalid_warp_id")), map_id, op, position)
				continue
			var destination_position := _destination_position_for_warp_id(map_data, int(warp_id_info.get("value", WARP_ID_NONE_VALUE)))
			position = destination_position.get("position", Vector2i(-1, -1))
			position_source = String(destination_position.get("source", "warp_id"))

		var tileset_data: Dictionary = _data_registry.get_tileset_data_for_map(map_id)
		var map_size: Vector2i = _data_registry.get_map_size(map_id)
		var sequence_id := _next_transition_sequence_id
		_next_transition_sequence_id += 1
		var sequence := _build_transition_sequence(
			effect,
			sequence_id,
			source_map_id,
			source_position,
			trigger_position,
			map_id,
			position,
			position_source,
			map_data,
			tileset_data
		)
		if not sequence.is_empty():
			transition_sequence_requested.emit(sequence)

		var script_data: Dictionary = _data_registry.get_script_data_for_map(map_id)
		var pending_transition := {
			"id": sequence_id,
			"op": op,
			"map": map_id,
			"map_data": map_data,
			"tileset_data": tileset_data,
			"map_size": map_size,
			"script_data": script_data,
			"position": position,
			"position_source": position_source,
			"style": String(effect.get("style", "")),
			"presentation": String(effect.get("presentation", _default_transition_presentation(effect))),
			"sequence": sequence,
		}
		if _defer_transition_apply:
			_pending_transitions[sequence_id] = pending_transition
			summary["applied"].append(_transition_summary_from_payload(pending_transition, false, true))
		else:
			summary["applied"].append(_apply_transition_payload(pending_transition))
	return summary


func _apply_map_warp_event(interaction: Dictionary, event_data: Dictionary) -> Dictionary:
	var presentation = interaction.get("presentation", {})
	var presentation_kind := "normal"
	var entry_direction := ""
	var source_position := _current_player_position()
	var trigger_position := _interaction_position(interaction, source_position)
	if typeof(presentation) == TYPE_DICTIONARY:
		presentation_kind = String(presentation.get("kind", presentation_kind))
		entry_direction = String(presentation.get("entry_direction", entry_direction))
		source_position = _transition_vector(presentation, "source_position", source_position)
		trigger_position = _transition_vector(presentation, "trigger_position", trigger_position)

	return _apply_transition_effects([
		{
			"op": "map_warp",
			"line": 0,
			"map": String(event_data.get("dest_map", "")),
			"warp_id": event_data.get("dest_warp_id", WARP_ID_NONE_VALUE),
			"position": [-1, -1],
			"has_explicit_position": false,
			"uses_warp_id": true,
			"style": "normal",
			"presentation": presentation_kind,
			"entry_direction": entry_direction,
			"source_position": [source_position.x, source_position.y],
			"trigger_position": [trigger_position.x, trigger_position.y],
		},
	])


func _transition_position(transition_effect: Dictionary) -> Vector2i:
	var position = transition_effect.get("position", [])
	if typeof(position) == TYPE_VECTOR2I:
		return position
	if typeof(position) == TYPE_ARRAY and position.size() >= 2:
		return Vector2i(int(position[0]), int(position[1]))
	return Vector2i(-1, -1)


func _transition_vector(source: Dictionary, key: String, default_value: Vector2i) -> Vector2i:
	var value = source.get(key, default_value)
	if typeof(value) == TYPE_VECTOR2I:
		return value
	if typeof(value) == TYPE_ARRAY and value.size() >= 2:
		return Vector2i(int(value[0]), int(value[1]))
	if typeof(value) == TYPE_DICTIONARY:
		return Vector2i(int(value.get("x", default_value.x)), int(value.get("y", default_value.y)))
	return default_value


func _interaction_position(interaction: Dictionary, default_value: Vector2i) -> Vector2i:
	var position = interaction.get("position", default_value)
	if typeof(position) == TYPE_VECTOR2I:
		return position
	return default_value


func _destination_position_for_warp_id(map_data: Dictionary, warp_id: int) -> Dictionary:
	var events = map_data.get("events", {})
	var warp_events = events.get("warp_events", []) if typeof(events) == TYPE_DICTIONARY else []
	if warp_id >= 0 and typeof(warp_events) == TYPE_ARRAY and warp_id < warp_events.size():
		var warp_event = warp_events[warp_id]
		if typeof(warp_event) == TYPE_DICTIONARY:
			return {
				"position": Vector2i(
					int(warp_event.get("x", -1)),
					int(warp_event.get("y", -1))
				),
				"source": "warp_id",
			}

	var map_size := _map_size_from_map_data(map_data)
	if map_size == Vector2i.ZERO:
		return {
			"position": Vector2i(-1, -1),
			"source": "unresolved",
		}
	return {
		"position": Vector2i(map_size.x / 2, map_size.y / 2),
		"source": "center_fallback",
	}


func _map_size_from_map_data(map_data: Dictionary) -> Vector2i:
	var layout_info = map_data.get("layout", {})
	if typeof(layout_info) != TYPE_DICTIONARY:
		return Vector2i.ZERO
	return Vector2i(
		int(layout_info.get("width", 0)),
		int(layout_info.get("height", 0))
	)


func _warp_id_from_value(value) -> Dictionary:
	match typeof(value):
		TYPE_INT:
			return {"valid": true, "value": int(value)}
		TYPE_FLOAT:
			return {"valid": true, "value": int(value)}

	var text := String(value).strip_edges()
	if text.is_empty():
		return {"valid": true, "value": WARP_ID_NONE_VALUE}
	if text == "WARP_ID_NONE":
		return {"valid": true, "value": WARP_ID_NONE_VALUE}
	if text == "WARP_ID_DYNAMIC":
		return {"valid": false, "reason": "unsupported_dynamic_warp_id"}
	if text.is_valid_int():
		return {"valid": true, "value": int(text)}
	return {"valid": false, "reason": "invalid_warp_id"}


func _build_transition_sequence(
	effect: Dictionary,
	sequence_id: int,
	source_map_id: String,
	source_position: Vector2i,
	trigger_position: Vector2i,
	destination_map_id: String,
	destination_position: Vector2i,
	position_source: String,
	destination_map_data: Dictionary,
	destination_tileset_data: Dictionary
) -> Dictionary:
	var presentation := String(effect.get("presentation", _default_transition_presentation(effect)))
	var exit_task := _warp_exit_task(destination_map_data, destination_tileset_data, destination_position)
	var steps := []
	if presentation == "door":
		steps = _door_warp_steps(
			source_position,
			trigger_position,
			destination_map_id,
			destination_position,
			exit_task,
			_source_door_animation(trigger_position)
		)
	else:
		steps = _normal_warp_steps(destination_map_id, destination_position, exit_task)

	return {
		"id": sequence_id,
		"type": "map_transition",
		"presentation": presentation,
		"style": String(effect.get("style", "normal")),
		"source_map": source_map_id,
		"source_position": source_position,
		"trigger_position": trigger_position,
		"destination_map": destination_map_id,
		"destination_position": destination_position,
		"position_source": position_source,
		"exit_task": exit_task,
		"frame_basis": "60fps",
		"source_trace": [
			"src/field_control_avatar.c:TryDoorWarp/TryStartWarpEventScript",
			"src/field_screen_effect.c:DoWarp/DoDoorWarp/Task_DoDoorWarp/FieldCB_DefaultWarpExit",
			"src/field_door.c:sDoorOpenAnimFrames/sDoorCloseAnimFrames",
			"src/event_object_movement.c:MOVE_SPEED_NORMAL",
			"src/metatile_behavior.c:MetatileBehavior_IsDoor/IsDirectionalStairWarp/IsNonAnimDoor",
		],
		"steps": steps,
	}


func _default_transition_presentation(effect: Dictionary) -> String:
	if String(effect.get("style", "")) == "silent":
		return "silent"
	return "normal"


func _door_warp_steps(
	source_position: Vector2i,
	trigger_position: Vector2i,
	destination_map_id: String,
	destination_position: Vector2i,
	exit_task: Dictionary,
	door_animation: Dictionary
) -> Array:
	var door_position := trigger_position + Vector2i.UP
	return [
		{"op": "lock_controls", "source": "DoDoorWarp"},
		{"op": "freeze_object_events", "source": "Task_DoDoorWarp"},
		{
			"op": "play_se",
			"sound": String(door_animation.get("sound_effect", "SE_DOOR")),
			"sound_source": "GetDoorSoundEffect",
			"position": door_position,
			"source": "Task_DoDoorWarp",
		},
		_door_step("door_open", door_position, "FieldAnimateDoorOpen", door_animation),
		{
			"op": "player_step",
			"movement_action": "MOVEMENT_ACTION_WALK_NORMAL_UP",
			"from": source_position,
			"to": trigger_position,
			"duration_frames": WALK_NORMAL_TILE_FRAMES,
			"source": "ObjectEventSetHeldMovement",
		},
		{"op": "hide_player", "visible": false, "source": "SetPlayerVisibility(FALSE)"},
		_door_step("door_close", door_position, "FieldAnimateDoorClose", door_animation),
		{"op": "fade_out", "color": "black_or_white_by_map_pair", "delay": FADE_DELAY_DEFAULT, "source": "WarpFadeOutScreen"},
		{"op": "load_map", "map": destination_map_id, "position": destination_position, "source": "WarpIntoMap"},
		{"op": "fade_in", "color": "black_or_white_by_map_pair", "delay": FADE_DELAY_DEFAULT, "source": "WarpFadeInScreen"},
		_exit_task_step(exit_task),
		{
			"op": "conditional_exit_door_player_step",
			"condition": "destination_metatile_behavior_is_door",
			"condition_result": String(exit_task.get("task", "")) == "Task_ExitDoor",
			"movement_action": "MOVEMENT_ACTION_WALK_NORMAL_DOWN",
			"from": destination_position,
			"to": destination_position + Vector2i.DOWN,
			"duration_frames": WALK_NORMAL_TILE_FRAMES,
			"source": "Task_ExitDoor",
		},
		{"op": "unlock_controls", "source": "Task_ExitDoor/Task_ExitNonDoor"},
	]


func _normal_warp_steps(
	destination_map_id: String,
	destination_position: Vector2i,
	exit_task: Dictionary
) -> Array:
	return [
		{"op": "lock_controls", "source": "DoWarp"},
		{"op": "fade_out", "color": "black_or_white_by_map_pair", "delay": FADE_DELAY_DEFAULT, "source": "WarpFadeOutScreen"},
		{"op": "load_map", "map": destination_map_id, "position": destination_position, "source": "WarpIntoMap"},
		{"op": "fade_in", "color": "black_or_white_by_map_pair", "delay": FADE_DELAY_DEFAULT, "source": "WarpFadeInScreen"},
		_exit_task_step(exit_task),
		{
			"op": "conditional_exit_door_player_step",
			"condition": "destination_metatile_behavior_is_door",
			"condition_result": String(exit_task.get("task", "")) == "Task_ExitDoor",
			"movement_action": "MOVEMENT_ACTION_WALK_NORMAL_DOWN",
			"from": destination_position,
			"to": destination_position + Vector2i.DOWN,
			"duration_frames": WALK_NORMAL_TILE_FRAMES,
			"source": "Task_ExitDoor",
		},
		{"op": "unlock_controls", "source": "Task_ExitDoor/Task_ExitNonDoor"},
	]


func _door_step(op: String, position: Vector2i, source: String, door_animation: Dictionary) -> Dictionary:
	var step := {
		"op": op,
		"position": position,
		"frame_time": DOOR_ANIM_FRAME_TIME,
		"frame_count": DOOR_ANIM_FRAME_COUNT,
		"duration_frames": DOOR_ANIM_TOTAL_FRAMES,
		"source": source,
	}
	step["frame_indices"] = [-1, 0, 1, 2] if op == "door_open" else [2, 1, 0, -1]
	if not door_animation.is_empty():
		step["animation"] = door_animation
	return step


func _source_door_animation(position: Vector2i) -> Dictionary:
	if _map_runtime == null or not _map_runtime.has_method("get_door_animation_at"):
		return {}

	var animation = _map_runtime.get_door_animation_at(position)
	return animation if typeof(animation) == TYPE_DICTIONARY else {}


func _exit_task_step(exit_task: Dictionary) -> Dictionary:
	return {
		"op": "exit_task_select",
		"source": "SetUpWarpExitTask",
		"branches": ["Task_ExitDoor", "Task_ExitStairs", "Task_ExitNonAnimDoor", "Task_ExitNonDoor"],
		"selected": String(exit_task.get("task", "Task_ExitNonDoor")),
		"behavior": int(exit_task.get("behavior", -1)),
		"behavior_name": String(exit_task.get("behavior_name", "")),
	}


func _warp_exit_task(map_data: Dictionary, tileset_data: Dictionary, position: Vector2i) -> Dictionary:
	var behavior_info := _metatile_behavior_info(map_data, tileset_data, position)
	var behavior_name := String(behavior_info.get("behavior_name", ""))
	var task := "Task_ExitNonDoor"
	if WARP_EXIT_DOOR_BEHAVIORS.has(behavior_name):
		task = "Task_ExitDoor"
	elif WARP_EXIT_DIRECTIONAL_STAIR_BEHAVIORS.has(behavior_name):
		task = "Task_ExitStairs"
	elif WARP_EXIT_NON_ANIM_DOOR_BEHAVIORS.has(behavior_name):
		task = "Task_ExitNonAnimDoor"

	return {
		"task": task,
		"behavior": int(behavior_info.get("behavior", -1)),
		"behavior_name": behavior_name,
		"position": position,
		"stairs_movement_disabled": false,
		"source": "SetUpWarpExitTask",
	}


func _metatile_behavior_info(map_data: Dictionary, tileset_data: Dictionary, position: Vector2i) -> Dictionary:
	var metatile_id := _metatile_id_from_map_data(map_data, position)
	if metatile_id < 0:
		return {"behavior": -1, "behavior_name": "", "metatile_id": metatile_id}

	var entries = tileset_data.get("metatile_entries", [])
	if typeof(entries) != TYPE_ARRAY:
		return {"behavior": -1, "behavior_name": "", "metatile_id": metatile_id}

	for entry in entries:
		if typeof(entry) != TYPE_DICTIONARY or int(entry.get("id", -1)) != metatile_id:
			continue
		var attribute = entry.get("attribute", {})
		if typeof(attribute) != TYPE_DICTIONARY:
			return {"behavior": -1, "behavior_name": "", "metatile_id": metatile_id}
		return {
			"behavior": int(attribute.get("behavior", -1)),
			"behavior_name": String(attribute.get("behavior_name", "")),
			"metatile_id": metatile_id,
		}

	return {"behavior": -1, "behavior_name": "", "metatile_id": metatile_id}


func _metatile_id_from_map_data(map_data: Dictionary, position: Vector2i) -> int:
	var block_ids = map_data.get("block_ids", [])
	if typeof(block_ids) != TYPE_ARRAY or position.y < 0 or position.y >= block_ids.size():
		return -1

	var row = block_ids[position.y]
	if typeof(row) != TYPE_ARRAY or position.x < 0 or position.x >= row.size():
		return -1
	return int(row[position.x])


func _current_map_id() -> String:
	if _game_state != null:
		return String(_game_state.current_map_id)
	return ""


func _current_player_position() -> Vector2i:
	if _game_state != null:
		return _game_state.player_grid_position
	return Vector2i.ZERO


func _apply_transition_payload(payload: Dictionary) -> Dictionary:
	var map_id := String(payload.get("map", ""))
	var map_data = payload.get("map_data", {})
	var tileset_data = payload.get("tileset_data", {})
	var map_size = payload.get("map_size", Vector2i.ZERO)
	var position = payload.get("position", Vector2i(-1, -1))
	if typeof(map_data) != TYPE_DICTIONARY or typeof(tileset_data) != TYPE_DICTIONARY:
		return _transition_summary_from_payload(payload, false, false, "invalid_transition_payload")

	if typeof(map_size) != TYPE_VECTOR2I:
		map_size = _map_size_from_map_data(map_data)
	if typeof(position) != TYPE_VECTOR2I:
		position = Vector2i(-1, -1)

	_map_runtime.configure_from_data(map_data, tileset_data, map_size)
	if _game_state != null:
		_game_state.current_map_id = map_id

	var position_applied := false
	if position != Vector2i(-1, -1):
		position_applied = (
			_map_runtime.has_method("set_player_grid_position")
			and _map_runtime.set_player_grid_position(position, _game_state)
		)

	var script_data = payload.get("script_data", {})
	configure_from_script_data(script_data if typeof(script_data) == TYPE_DICTIONARY else {})
	return _transition_summary_from_payload(payload, position_applied, false)


func _transition_summary_from_payload(
	payload: Dictionary,
	position_applied: bool,
	deferred: bool,
	status := "ok"
) -> Dictionary:
	return {
		"id": int(payload.get("id", 0)),
		"status": status,
		"op": String(payload.get("op", "")),
		"map": String(payload.get("map", "")),
		"position": payload.get("position", Vector2i(-1, -1)),
		"position_applied": position_applied,
		"position_source": String(payload.get("position_source", "")),
		"style": String(payload.get("style", "")),
		"presentation": String(payload.get("presentation", _default_transition_presentation({}))),
		"deferred": deferred,
		"sequence": payload.get("sequence", {}),
	}


func _record_skipped_transition(
	summary: Dictionary,
	reason: String,
	map_id: String,
	op: String,
	position: Vector2i
) -> void:
	summary["skipped"].append({
		"reason": reason,
		"op": op,
		"map": map_id,
		"position": position,
	})


func _movement_summary_count(summary: Dictionary, key: String) -> int:
	var entries = summary.get(key, [])
	return entries.size() if typeof(entries) == TYPE_ARRAY else 0


func _append_direct_preview_output(lines: PackedStringArray, script: String) -> void:
	var preview := _get_direct_script_preview(script)
	if preview.is_empty():
		lines.append("Preview: script data unavailable")
		return

	var status := String(preview.get("status", ""))
	if status == "no_preview_message":
		lines.append("Preview: no msgbox/message found")
		return
	if status == "missing_text":
		lines.append("Preview: text label missing")
		lines.append("Text label: %s" % String(preview.get("text_label", "")))
		return

	lines.append("Text label: %s" % String(preview.get("text_label", "")))
	lines.append("Mode: %s" % String(preview.get("mode", "")))
	lines.append("")
	lines.append(String(preview.get("text", "")))


func _get_script_record(script: String) -> Dictionary:
	var scripts = _script_data.get("scripts", {})
	if typeof(scripts) != TYPE_DICTIONARY:
		return {}
	var record = scripts.get(script, {})
	return record if typeof(record) == TYPE_DICTIONARY else {}


func _get_text_record(text_label: String) -> Dictionary:
	var texts = _script_data.get("texts", {})
	if typeof(texts) == TYPE_DICTIONARY:
		var record = texts.get(text_label, {})
		if typeof(record) == TYPE_DICTIONARY and not record.is_empty():
			return record

	if _data_registry != null and _data_registry.has_method("get_text_record"):
		var global_record = _data_registry.get_text_record(text_label, "global")
		if typeof(global_record) == TYPE_DICTIONARY:
			return global_record
	return {}


func _first_msgbox(script_record: Dictionary) -> Dictionary:
	var msgboxes = script_record.get("msgboxes", [])
	if typeof(msgboxes) != TYPE_ARRAY or msgboxes.is_empty():
		return {}
	var first = msgboxes[0]
	return first if typeof(first) == TYPE_DICTIONARY else {}
