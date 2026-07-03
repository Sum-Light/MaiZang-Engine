extends Node2D

@onready var debug_map = $World/DebugMap
@onready var player = $World/Player
@onready var status_label: Label = $Hud/StatusLabel


func _ready() -> void:
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

	_update_status()


func _on_player_moved(grid_position: Vector2i) -> void:
	GameState.player_grid_position = grid_position
	_update_status()


func _update_status() -> void:
	var source_label := "generated" if not DataRegistry.get_start_map_data().is_empty() else "fallback"
	status_label.text = "%s | %s | %s | grid %s | arrow keys move" % [
		DataRegistry.get_start_map_id(),
		DataRegistry.get_start_map_name(),
		source_label,
		GameState.player_grid_position,
	]
