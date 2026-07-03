extends Node

signal debug_message_requested(lines: PackedStringArray)

var _script_data: Dictionary = {}


func _ready() -> void:
	var registry = get_node_or_null("/root/DataRegistry")
	if registry != null and registry.has_method("get_start_script_data"):
		configure_from_script_data(registry.get_start_script_data())


func configure_from_script_data(script_data: Dictionary) -> void:
	_script_data = script_data


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
	_append_script_preview(lines, script)
	debug_message_requested.emit(lines)


func _emit_bg_event(interaction: Dictionary, event_data: Dictionary) -> void:
	var script := String(interaction.get("script", event_data.get("script", "0x0")))
	var lines := PackedStringArray([
		"BG event: %s" % String(event_data.get("type", "unknown")),
		"Position: %s" % interaction.get("position", Vector2i.ZERO),
	])
	_append_script_preview(lines, script)
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


func _append_script_preview(lines: PackedStringArray, script: String) -> void:
	if script.is_empty() or script == "0x0":
		lines.append("Script: none")
		return

	lines.append("Script: %s" % script)
	var preview := get_script_preview(script)
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
