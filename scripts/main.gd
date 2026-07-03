extends Node2D

@onready var debug_map = $World/DebugMap
@onready var player = $World/Player
@onready var status_label: Label = $Hud/StatusLabel


func _ready() -> void:
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
	status_label.text = "%s | %s | grid %s | arrow keys move" % [
		DataRegistry.get_start_map_id(),
		DataRegistry.get_start_map_name(),
		GameState.player_grid_position,
	]
