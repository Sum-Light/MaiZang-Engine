extends Node

const MAIN_SCENE := preload("res://scenes/main.tscn")

var _failed := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var main = MAIN_SCENE.instantiate()
	get_tree().root.add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame

	GameState.clear_player_party()
	GameState.current_map_id = "MAP_LITTLEROOT_TOWN"
	GameState.player_grid_position = Vector2i(10, 13)
	var player = main.get_node("World/Player")
	player.set_grid_position(Vector2i(10, 13))
	player.facing_direction = Vector2i.UP

	var interaction := MapRuntime.get_interaction_target(Vector2i(10, 13), Vector2i.UP)
	_assert(interaction.get("type", "") == "object_event", "expected debug NPC interaction target")
	_assert(
		String(interaction.get("event", {}).get("local_id", "")) == "LOCALID_DEBUG_BATTLE_NPC",
		"expected debug battle NPC"
	)
	main._on_player_interaction_requested(Vector2i(10, 13), Vector2i(10, 12), Vector2i.UP, interaction)

	var battle_scene: Node = null
	for _index in range(80):
		await get_tree().create_timer(0.05).timeout
		battle_scene = main.get_node_or_null("Hud/BattleScene")
		if battle_scene != null:
			break
	_assert(battle_scene != null, "expected BattleScene handoff")
	_assert(not main.get_node("World").visible, "expected field hidden during battle")
	_assert(GameState.get_player_party_count() == 0, "expected debug Torchic fallback not to persist before battle")

	var before: Dictionary = battle_scene.get_ui_snapshot()
	_assert(String(before.get("message", "")).contains("wants to battle"), "expected trainer intro message")
	_assert(String(before.get("presentation_status", "")) == "first_slice_not_source_equivalent", "expected debug battle scene parity status")
	var battle_state: Dictionary = battle_scene.get_battle_state()
	var debug_player_party = battle_state.get("debug_player_party", {})
	_assert(typeof(debug_player_party) == TYPE_DICTIONARY and bool(debug_player_party.get("temporary", false)), "expected temporary debug player party metadata")
	var turn_result: Dictionary = battle_scene.play_player_move(0)
	await get_tree().process_frame
	_assert(String(turn_result.get("status", "")) == "ok", "expected debug move round")
	var battle_result: Dictionary = battle_scene.get_battle_result()
	_assert(not battle_result.is_empty(), "expected battle result contract")
	_assert(_has_unsupported(battle_result, "debug_player_party_not_persisted"), "expected result to mark debug party as non-persistent")
	battle_scene._on_finish_pressed()
	await get_tree().process_frame
	await get_tree().process_frame

	_assert(main.get_node("World").visible, "expected field restored after battle")
	_assert(main.get_node_or_null("Hud/BattleScene") == null, "expected BattleScene removed after finish")
	_assert(GameState.get_player_party_count() == 0, "expected debug fallback party to remain non-persistent after battle")
	_assert(not player.input_locked, "expected field input unlocked after battle")

	if _failed:
		return

	print(JSON.stringify({
		"main_debug_battle_smoke": "ok",
		"outcome": String(battle_result.get("outcome", "")),
		"party_count": GameState.get_player_party_count(),
	}))
	main.queue_free()
	get_tree().quit(0)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true
	get_tree().quit(1)


func _has_unsupported(record: Dictionary, code: String) -> bool:
	var unsupported = record.get("unsupported", [])
	if typeof(unsupported) != TYPE_ARRAY:
		return false
	for item in unsupported:
		if typeof(item) == TYPE_DICTIONARY and String(item.get("code", "")) == code:
			return true
	return false
