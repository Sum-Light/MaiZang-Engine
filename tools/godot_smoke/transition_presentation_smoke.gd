extends SceneTree

const DATA_REGISTRY_SCRIPT := preload("res://scripts/autoload/data_registry.gd")
const EVENT_MANAGER_SCRIPT := preload("res://scripts/autoload/event_manager.gd")
const GAME_STATE_SCRIPT := preload("res://scripts/autoload/game_state.gd")
const GRID_MOVER_SCRIPT := preload("res://scripts/overworld/grid_mover.gd")
const MAP_RUNTIME_SCRIPT := preload("res://scripts/autoload/map_runtime.gd")
const SCRIPT_VM_SCRIPT := preload("res://scripts/autoload/script_vm.gd")
const TRANSITION_SEQUENCE_PLAYER_SCRIPT := preload("res://scripts/overworld/transition_sequence_player.gd")

const START_MAP := "MAP_LITTLEROOT_TOWN"
const BRENDANS_HOUSE_1F := "MAP_LITTLEROOT_TOWN_BRENDANS_HOUSE_1F"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var registry = DATA_REGISTRY_SCRIPT.new()
	registry._ready()
	var game_state = GAME_STATE_SCRIPT.new()
	var runtime = MAP_RUNTIME_SCRIPT.new()
	runtime.configure_from_data(
		registry.get_start_map_data(),
		registry.get_start_tileset_data(),
		registry.get_start_map_size()
	)
	var vm = SCRIPT_VM_SCRIPT.new()
	vm.configure_from_script_data(registry.get_start_script_data())
	vm.configure_game_state(game_state)
	var manager = EVENT_MANAGER_SCRIPT.new()
	manager.configure_from_script_data(registry.get_start_script_data())
	manager.configure_script_vm(vm)
	manager.configure_map_runtime(runtime)
	manager.configure_game_state(game_state)
	manager.configure_data_registry(registry)
	manager.configure_transition_deferred(true)

	var player = GRID_MOVER_SCRIPT.new()
	player.tile_size = 16
	player.set_grid_position(game_state.player_grid_position)
	get_root().add_child(player)
	runtime.player_position_changed.connect(func(grid_position: Vector2i) -> void:
		player.set_grid_position(grid_position)
	)

	var overlay := ColorRect.new()
	var label := Label.new()
	get_root().add_child(overlay)
	overlay.add_child(label)

	var sequence_player = TRANSITION_SEQUENCE_PLAYER_SCRIPT.new()
	get_root().add_child(sequence_player)
	sequence_player.configure(manager, runtime, game_state, player, overlay, label)
	manager.transition_sequence_requested.connect(func(sequence: Dictionary) -> void:
		sequence_player.play(sequence)
	)

	manager.dispatch_interaction({
		"type": "coord_event",
		"script": "LittlerootTown_EventScript_StepOffTruckMale",
		"position": Vector2i(0, 0),
		"event": {
			"script": "LittlerootTown_EventScript_StepOffTruckMale",
		},
	})
	await create_timer(0.75).timeout
	_assert(game_state.current_map_id == BRENDANS_HOUSE_1F, "expected deferred truck transition to load Brendan house")
	_assert(game_state.player_grid_position == Vector2i(8, 8), "expected truck transition destination")
	_assert(player.grid_position == Vector2i(8, 8), "expected player node at truck destination")
	_assert(player.visible, "expected player visible after non-door transition")
	_assert(not overlay.visible, "expected overlay hidden after truck transition")

	var brendan_exit_warp := runtime.get_warp_event_target(Vector2i(8, 8))
	_assert(brendan_exit_warp.get("type", "") == "warp_event", "expected Brendan house exit warp")
	manager.dispatch_interaction(brendan_exit_warp)
	await create_timer(1.1).timeout

	_assert(game_state.current_map_id == START_MAP, "expected deferred house exit to load LittlerootTown")
	_assert(game_state.player_grid_position == Vector2i(5, 9), "expected Task_ExitDoor to finish one tile below door")
	_assert(player.grid_position == Vector2i(5, 9), "expected player node one tile below door")
	_assert(player.visible, "expected player visible after Task_ExitDoor")
	_assert(not overlay.visible, "expected transition overlay hidden after playback")

	print(JSON.stringify({
		"transition_presentation_smoke": "ok",
		"current_map": game_state.current_map_id,
		"player_position": _vector_to_array(game_state.player_grid_position),
		"player_visible": player.visible,
	}))
	sequence_player.free()
	overlay.free()
	player.free()
	manager.free()
	game_state.free()
	runtime.free()
	vm.free()
	registry.free()
	quit(0)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	quit(1)


func _vector_to_array(value: Vector2i) -> Array:
	return [value.x, value.y]
