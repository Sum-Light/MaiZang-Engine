extends Node

signal debug_message_requested(lines: PackedStringArray)

var _script_data: Dictionary = {}
var _script_vm: Node = null
var _map_runtime: Node = null
var _game_state: Node = null


func _ready() -> void:
	_script_vm = get_node_or_null("/root/ScriptVM")
	_map_runtime = get_node_or_null("/root/MapRuntime")
	_game_state = get_node_or_null("/root/GameState")
	var registry = get_node_or_null("/root/DataRegistry")
	if registry != null and registry.has_method("get_start_script_data"):
		configure_from_script_data(registry.get_start_script_data())


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
		"effects": [],
		"unsupported_ops": [],
		"trace": [],
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
	if not runtime_summary.is_empty():
		lines.append("Movement effects: %d applied, %d skipped" % [
			_movement_summary_count(runtime_summary, "applied"),
			_movement_summary_count(runtime_summary, "skipped"),
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
	if _map_runtime == null or not _map_runtime.has_method("apply_script_movements"):
		return {}

	var movements = result.get("movements", [])
	if typeof(movements) != TYPE_ARRAY or movements.is_empty():
		return {}

	return _map_runtime.apply_script_movements(movements, _game_state)


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
