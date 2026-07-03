extends Node2D

const TRANSITION_SEQUENCE_PLAYER := preload("res://scripts/overworld/transition_sequence_player.gd")

@onready var debug_map = $World/DebugMap
@onready var object_events = $World/ObjectEvents
@onready var player = $World/Player
@onready var status_label: Label = $Hud/StatusLabel
@onready var dialogue_panel: PanelContainer = $Hud/DialoguePanel
@onready var dialogue_label: Label = $Hud/DialoguePanel/DialogueLabel

var _movement_note := ""
var _transition_overlay: ColorRect
var _transition_label: Label
var _transition_sequence_player: Node


func _ready() -> void:
	_create_transition_overlay()
	_transition_sequence_player = TRANSITION_SEQUENCE_PLAYER.new()
	add_child(_transition_sequence_player)
	_transition_sequence_player.configure(
		EventManager,
		MapRuntime,
		GameState,
		player,
		_transition_overlay,
		_transition_label,
		debug_map
	)
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
	if MapRuntime.has_signal("map_changed"):
		MapRuntime.map_changed.connect(_on_map_changed)
	if MapRuntime.has_signal("object_events_changed"):
		MapRuntime.object_events_changed.connect(_on_object_events_changed)
	if MapRuntime.has_signal("player_position_changed"):
		MapRuntime.player_position_changed.connect(_on_script_player_position_changed)
	EventManager.debug_message_requested.connect(_on_debug_message_requested)
	if EventManager.has_signal("transition_sequence_requested"):
		if EventManager.has_method("configure_transition_deferred"):
			EventManager.configure_transition_deferred(true)
		EventManager.transition_sequence_requested.connect(_on_transition_sequence_requested)

	_update_status()


func _on_player_moved(grid_position: Vector2i) -> void:
	_movement_note = ""
	_hide_dialogue()
	GameState.player_grid_position = grid_position
	var coord_event := MapRuntime.get_coord_event_target(grid_position, GameState)
	if not coord_event.is_empty():
		_movement_note = "coord %s" % grid_position
		EventManager.dispatch_interaction(coord_event)
		_update_status()
		return

	if MapRuntime.has_method("get_warp_event_target"):
		var warp_event := MapRuntime.get_warp_event_target(grid_position)
		if not warp_event.is_empty():
			_movement_note = "warp %s" % grid_position
			EventManager.dispatch_interaction(warp_event)
			_update_status()
			return
	_update_status()


func _on_player_movement_blocked(
	target_position: Vector2i,
	cell_info: Dictionary,
	facing_direction: Vector2i
) -> void:
	if facing_direction == Vector2i.UP and MapRuntime.has_method("get_warp_event_target"):
		var warp_event := MapRuntime.get_warp_event_target(target_position)
		if not warp_event.is_empty():
			warp_event["presentation"] = {
				"kind": "door",
				"entry_direction": "up",
				"source_position": [GameState.player_grid_position.x, GameState.player_grid_position.y],
				"trigger_position": [target_position.x, target_position.y],
			}
			_movement_note = "warp %s" % target_position
			EventManager.dispatch_interaction(warp_event)
			_update_status()
			return

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


func _on_transition_sequence_requested(sequence: Dictionary) -> void:
	if _transition_sequence_player != null and _transition_sequence_player.has_method("play"):
		_transition_sequence_player.play(sequence)


func _on_map_changed(map_data: Dictionary, tileset_data: Dictionary, _map_size: Vector2i) -> void:
	if debug_map.has_method("configure_from_map_data"):
		debug_map.configure_from_map_data(map_data, tileset_data)
	if object_events.has_method("configure_from_events"):
		object_events.configure_from_events(
			MapRuntime.get_object_events(),
			DataRegistry.TILE_SIZE
		)
	_update_status()


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


func _create_transition_overlay() -> void:
	var hud := $Hud
	_transition_overlay = ColorRect.new()
	_transition_overlay.name = "TransitionOverlay"
	_transition_overlay.visible = false
	_transition_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_transition_overlay.color = Color(0, 0, 0, 0.86)
	_transition_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.add_child(_transition_overlay)

	_transition_label = Label.new()
	_transition_label.name = "TransitionLabel"
	_transition_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_transition_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_transition_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_transition_overlay.add_child(_transition_label)


func _update_status() -> void:
	var map_id := GameState.current_map_id
	var source_label := "generated" if DataRegistry.has_map_data(map_id) else "fallback"
	var parts := PackedStringArray([
		map_id,
		DataRegistry.get_map_name(map_id),
		source_label,
		"grid %s" % GameState.player_grid_position,
		"objects %d" % MapRuntime.get_object_events().size(),
	])
	if not _movement_note.is_empty():
		parts.append(_movement_note)
	status_label.text = " | ".join(parts)
