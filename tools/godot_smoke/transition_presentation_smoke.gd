extends SceneTree

const DATA_REGISTRY_SCRIPT := preload("res://scripts/autoload/data_registry.gd")
const DEBUG_MAP_PLANE_SCRIPT := preload("res://scripts/overworld/debug_map_plane.gd")
const EVENT_MANAGER_SCRIPT := preload("res://scripts/autoload/event_manager.gd")
const GAME_STATE_SCRIPT := preload("res://scripts/autoload/game_state.gd")
const GRID_MOVER_SCRIPT := preload("res://scripts/overworld/grid_mover.gd")
const MAP_RUNTIME_SCRIPT := preload("res://scripts/autoload/map_runtime.gd")
const SCRIPT_VM_SCRIPT := preload("res://scripts/autoload/script_vm.gd")
const TRANSITION_SEQUENCE_PLAYER_SCRIPT := preload("res://scripts/overworld/transition_sequence_player.gd")

const START_MAP := "MAP_LITTLEROOT_TOWN"
const BRENDANS_HOUSE_1F := "MAP_LITTLEROOT_TOWN_BRENDANS_HOUSE_1F"
const MAYS_HOUSE_1F := "MAP_LITTLEROOT_TOWN_MAYS_HOUSE_1F"


class FakeDoorRenderer:
	extends Node

	var calls := []
	var overlays := {}

	func set_door_animation_frame(position: Vector2i, animation: Dictionary, frame_index: int) -> bool:
		calls.append({
			"op": "set",
			"position": position,
			"frame_index": frame_index,
			"metatile_id": int(animation.get("metatile_id", -1)),
		})
		overlays[_cell_key(position)] = frame_index
		return true

	func clear_door_animation(position: Vector2i) -> void:
		calls.append({
			"op": "clear",
			"position": position,
			"frame_index": -1,
		})
		overlays.erase(_cell_key(position))

	func clear_door_animations() -> void:
		calls.append({"op": "clear_all"})
		overlays.clear()

	func get_door_animation_overlay_count() -> int:
		return overlays.size()

	func frame_indices_at(position: Vector2i) -> Array:
		var result := []
		for call in calls:
			if typeof(call) != TYPE_DICTIONARY:
				continue
			var op := String(call.get("op", ""))
			if op != "set" and op != "clear":
				continue
			if call.get("position", Vector2i.ZERO) == position:
				result.append(int(call.get("frame_index", -999)))
		return result

	func set_metatile_ids_at(position: Vector2i) -> Array:
		var result := []
		for call in calls:
			if typeof(call) != TYPE_DICTIONARY or String(call.get("op", "")) != "set":
				continue
			if call.get("position", Vector2i.ZERO) == position:
				result.append(int(call.get("metatile_id", -1)))
		return result

	func _cell_key(position: Vector2i) -> String:
		return "%d,%d" % [position.x, position.y]


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var registry = DATA_REGISTRY_SCRIPT.new()
	registry._ready()
	_verify_debug_map_door_renderer(registry)
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
	var door_renderer := FakeDoorRenderer.new()
	get_root().add_child(overlay)
	overlay.add_child(label)
	get_root().add_child(door_renderer)

	var sequence_player = TRANSITION_SEQUENCE_PLAYER_SCRIPT.new()
	get_root().add_child(sequence_player)
	sequence_player.configure(manager, runtime, game_state, player, overlay, label, door_renderer)
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
	_assert(runtime.get_metatile_id_at(Vector2i(5, 4)) == 624, "expected Brendan OnLoad open moving-box metatile")
	_assert(runtime.get_metatile_id_at(Vector2i(5, 2)) == 616, "expected Brendan OnLoad closed moving-box metatile")
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

	door_renderer.calls.clear()
	runtime.set_player_grid_position(Vector2i(14, 9), game_state)
	var may_house_door_warp := runtime.get_warp_event_target(Vector2i(14, 8))
	_assert(may_house_door_warp.get("type", "") == "warp_event", "expected May house door warp target")
	may_house_door_warp["presentation"] = {
		"kind": "door",
		"entry_direction": "up",
		"source_position": [14, 9],
		"trigger_position": [14, 8],
	}
	manager.dispatch_interaction(may_house_door_warp)
	await create_timer(1.35).timeout

	var door_animation_position := Vector2i(14, 7)
	_assert(game_state.current_map_id == MAYS_HOUSE_1F, "expected deferred door warp to load May house")
	_assert(game_state.player_grid_position == Vector2i(2, 8), "expected May house warp-id destination")
	_assert(runtime.get_metatile_id_at(Vector2i(5, 4)) == 624, "expected May OnLoad open moving-box metatile")
	_assert(runtime.get_metatile_id_at(Vector2i(5, 2)) == 616, "expected May OnLoad closed moving-box metatile")
	_assert(
		door_renderer.frame_indices_at(door_animation_position) == [-1, 0, 1, 2, 2, 1, 0, -1],
		"expected source door open/close frame order to reach renderer"
	)
	var door_animation_metatile_ids := door_renderer.set_metatile_ids_at(door_animation_position)
	_assert(not door_animation_metatile_ids.is_empty(), "expected renderer to receive door animation frames")
	_assert(_all_ints_equal(door_animation_metatile_ids, 584), "expected renderer to receive Littleroot door animation frames")
	_assert(door_renderer.get_door_animation_overlay_count() == 0, "expected door overlay cleared after close")
	_assert(not overlay.visible, "expected transition overlay hidden after door playback")

	print(JSON.stringify({
		"transition_presentation_smoke": "ok",
		"current_map": game_state.current_map_id,
		"player_position": _vector_to_array(game_state.player_grid_position),
		"player_visible": player.visible,
	}))
	sequence_player.free()
	door_renderer.free()
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


func _verify_debug_map_door_renderer(registry: Node) -> void:
	var tileset_data: Dictionary = registry.get_start_tileset_data()
	var door_animations = tileset_data.get("door_animations", {})
	var animations = door_animations.get("animations", []) if typeof(door_animations) == TYPE_DICTIONARY else []
	_assert(typeof(animations) == TYPE_ARRAY and not animations.is_empty(), "expected generated door animation data")
	var animation = animations[0]
	_assert(typeof(animation) == TYPE_DICTIONARY, "expected generated door animation dictionary")

	var renderer = DEBUG_MAP_PLANE_SCRIPT.new()
	get_root().add_child(renderer)
	_assert(
		renderer.set_door_animation_frame(Vector2i(14, 7), animation, 0),
		"expected DebugMapPlane to load generated door animation frame"
	)
	_assert(renderer.get_door_animation_overlay_count() == 1, "expected DebugMapPlane door overlay")
	renderer.clear_door_animation(Vector2i(14, 7))
	_assert(renderer.get_door_animation_overlay_count() == 0, "expected DebugMapPlane door overlay clear")
	renderer.free()


func _all_ints_equal(values: Array, expected: int) -> bool:
	for value in values:
		if int(value) != expected:
			return false
	return true
