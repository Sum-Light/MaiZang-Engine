extends Node2D

@onready var debug_map = $World/DebugMap
@onready var object_events = $World/ObjectEvents
@onready var player = $World/Player
@onready var status_label: Label = $Hud/StatusLabel
@onready var dialogue_panel: PanelContainer = $Hud/DialoguePanel
@onready var dialogue_label: Label = $Hud/DialoguePanel/DialogueLabel

var _movement_note := ""


func _ready() -> void:
	MapRuntime.configure_from_data(
		DataRegistry.get_start_map_data(),
		DataRegistry.get_start_tileset_data(),
		DataRegistry.get_start_map_size()
	)

	if debug_map.has_method("configure_from_map_data"):
		debug_map.configure_from_map_data(
			DataRegistry.get_start_map_data(),
			DataRegistry.get_start_tileset_data()
		)
	else:
		debug_map.map_size = DataRegistry.get_start_map_size()
		debug_map.tile_size = DataRegistry.TILE_SIZE
		debug_map.queue_redraw()

	if object_events.has_method("configure_from_events"):
		object_events.configure_from_events(
			MapRuntime.get_object_events(),
			DataRegistry.TILE_SIZE
		)

	if player.has_signal("moved"):
		player.moved.connect(_on_player_moved)
	if player.has_signal("movement_blocked"):
		player.movement_blocked.connect(_on_player_movement_blocked)
	if player.has_signal("interaction_requested"):
		player.interaction_requested.connect(_on_player_interaction_requested)
	if MapRuntime.has_signal("object_events_changed"):
		MapRuntime.object_events_changed.connect(_on_object_events_changed)
	if MapRuntime.has_signal("player_position_changed"):
		MapRuntime.player_position_changed.connect(_on_script_player_position_changed)
	EventManager.debug_message_requested.connect(_on_debug_message_requested)

	_update_status()


func _on_player_moved(grid_position: Vector2i) -> void:
	_movement_note = ""
	_hide_dialogue()
	GameState.player_grid_position = grid_position
	_update_status()


func _on_player_movement_blocked(target_position: Vector2i, cell_info: Dictionary) -> void:
	_movement_note = "blocked %s collision %d" % [
		target_position,
		int(cell_info.get("collision", MapRuntime.COLLISION_IMPASSABLE)),
	]
	_update_status()


func _on_player_interaction_requested(
	_origin_position: Vector2i,
	target_position: Vector2i,
	_facing_direction: Vector2i,
	interaction: Dictionary
) -> void:
	if dialogue_panel.visible:
		_hide_dialogue()
		_movement_note = ""
		_update_status()
		return

	_movement_note = "interact %s" % target_position
	EventManager.dispatch_interaction(interaction)
	_update_status()


func _on_debug_message_requested(lines: PackedStringArray) -> void:
	dialogue_label.text = "\n".join(lines)
	dialogue_panel.visible = true


func _on_object_events_changed(updated_object_events: Array) -> void:
	if object_events.has_method("configure_from_events"):
		object_events.configure_from_events(updated_object_events, DataRegistry.TILE_SIZE)
	_update_status()


func _on_script_player_position_changed(grid_position: Vector2i) -> void:
	if player.has_method("set_grid_position"):
		player.set_grid_position(grid_position)
	_update_status()


func _hide_dialogue() -> void:
	dialogue_panel.visible = false
	dialogue_label.text = ""


func _update_status() -> void:
	var source_label := "generated" if not DataRegistry.get_start_map_data().is_empty() else "fallback"
	var parts := PackedStringArray([
		DataRegistry.get_start_map_id(),
		DataRegistry.get_start_map_name(),
		source_label,
		"grid %s" % GameState.player_grid_position,
		"objects %d" % MapRuntime.get_object_events().size(),
	])
	if not _movement_note.is_empty():
		parts.append(_movement_note)
	status_label.text = " | ".join(parts)
