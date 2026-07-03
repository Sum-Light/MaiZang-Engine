extends Node2D

@onready var debug_map = $World/DebugMap
@onready var player = $World/Player
@onready var status_label: Label = $Hud/StatusLabel

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

	if player.has_signal("moved"):
		player.moved.connect(_on_player_moved)
	if player.has_signal("movement_blocked"):
		player.movement_blocked.connect(_on_player_movement_blocked)

	_update_status()


func _on_player_moved(grid_position: Vector2i) -> void:
	_movement_note = ""
	GameState.player_grid_position = grid_position
	_update_status()


func _on_player_movement_blocked(target_position: Vector2i, cell_info: Dictionary) -> void:
	_movement_note = "blocked %s collision %d" % [
		target_position,
		int(cell_info.get("collision", MapRuntime.COLLISION_IMPASSABLE)),
	]
	_update_status()


func _update_status() -> void:
	var source_label := "generated" if not DataRegistry.get_start_map_data().is_empty() else "fallback"
	var parts := PackedStringArray([
		DataRegistry.get_start_map_id(),
		DataRegistry.get_start_map_name(),
		source_label,
		"grid %s" % GameState.player_grid_position,
	])
	if not _movement_note.is_empty():
		parts.append(_movement_note)
	status_label.text = " | ".join(parts)
