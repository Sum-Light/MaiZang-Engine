extends Node

signal debug_message_requested(lines: PackedStringArray)

var _script_data: Dictionary = {}
var _script_vm: Node = null
var _map_runtime: Node = null
var _game_state: Node = null
var _data_registry: Node = null


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
	debug_message_requested.emit(PackedStringArray([
		"Warp placeholder",
		"Position: %s" % interaction.get("position", Vector2i.ZERO),
		"Destination: %s / warp %s" % [
			String(event_data.get("dest_map", "unknown")),
			String(event_data.get("dest_warp_id", "?")),
		],
	]))


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
	return {
		"script_label": script,
		"text_label": text_label,
		"mode": String(msgbox.get("mode", "")),
		"op": String(msgbox.get("op", "msgbox")),
		"line": int(msgbox.get("line", 0)),
		"text": String(text_record.get("display_text", "")),
		"status": "ok" if not text_record.is_empty() else "missing_text",
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
		var tileset_data: Dictionary = _data_registry.get_tileset_data_for_map(map_id)
		var map_size: Vector2i = _data_registry.get_map_size(map_id)
		_map_runtime.configure_from_data(map_data, tileset_data, map_size)
		if _game_state != null:
			_game_state.current_map_id = map_id

		var position_applied := false
		if bool(effect.get("has_explicit_position", false)):
			position_applied = (
				_map_runtime.has_method("set_player_grid_position")
				and _map_runtime.set_player_grid_position(position, _game_state)
			)

		var script_data: Dictionary = _data_registry.get_script_data_for_map(map_id)
		configure_from_script_data(script_data)
		summary["applied"].append({
			"op": op,
			"map": map_id,
			"position": position,
			"position_applied": position_applied,
			"style": String(effect.get("style", "")),
		})
	return summary


func _transition_position(transition_effect: Dictionary) -> Vector2i:
	var position = transition_effect.get("position", [])
	if typeof(position) == TYPE_VECTOR2I:
		return position
	if typeof(position) == TYPE_ARRAY and position.size() >= 2:
		return Vector2i(int(position[0]), int(position[1]))
	return Vector2i(-1, -1)


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
	if typeof(texts) != TYPE_DICTIONARY:
		return {}
	var record = texts.get(text_label, {})
	return record if typeof(record) == TYPE_DICTIONARY else {}


func _first_msgbox(script_record: Dictionary) -> Dictionary:
	var msgboxes = script_record.get("msgboxes", [])
	if typeof(msgboxes) != TYPE_ARRAY or msgboxes.is_empty():
		return {}
	var first = msgboxes[0]
	return first if typeof(first) == TYPE_DICTIONARY else {}
