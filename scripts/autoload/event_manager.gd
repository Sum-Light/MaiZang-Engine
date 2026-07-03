extends Node

signal debug_message_requested(lines: PackedStringArray)


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
	var lines := PackedStringArray([
		"Object event",
		"Position: %s" % interaction.get("position", Vector2i.ZERO),
		"Graphics: %s" % String(event_data.get("graphics_id", "unknown")),
	])
	_append_script_line(lines, String(interaction.get("script", event_data.get("script", "0x0"))))
	debug_message_requested.emit(lines)


func _emit_bg_event(interaction: Dictionary, event_data: Dictionary) -> void:
	var lines := PackedStringArray([
		"BG event: %s" % String(event_data.get("type", "unknown")),
		"Position: %s" % interaction.get("position", Vector2i.ZERO),
	])
	_append_script_line(lines, String(interaction.get("script", event_data.get("script", "0x0"))))
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


func _append_script_line(lines: PackedStringArray, script: String) -> void:
	if script.is_empty() or script == "0x0":
		lines.append("Script: none")
		return

	lines.append("Script: %s" % script)
