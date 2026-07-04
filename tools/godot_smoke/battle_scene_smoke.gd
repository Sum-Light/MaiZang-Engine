extends SceneTree

const DATA_REGISTRY_SCRIPT := preload("res://scripts/autoload/data_registry.gd")
const BATTLE_ENGINE_SCRIPT := preload("res://scripts/autoload/battle_engine.gd")
const BATTLE_SCENE := preload("res://scenes/battle/battle_scene.tscn")

var _failed := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var registry = DATA_REGISTRY_SCRIPT.new()
	registry._ready()

	var engine = BATTLE_ENGINE_SCRIPT.new()
	engine.configure_registry(registry)

	var mudkip := engine.create_battle_mon("SPECIES_MUDKIP", 30, {
		"moves": ["MOVE_WATER_GUN", "MOVE_TACKLE"],
	})
	var battle_state := engine.create_trainer_battle_state("TRAINER_SAWYER_1", [mudkip], {
		"map_transition_type": "normal",
	})
	_assert(String(battle_state.get("status", "")) == "ok", "expected trainer battle state for scene")

	var scene = BATTLE_SCENE.instantiate()
	scene.configure_battle_engine(engine)
	get_root().add_child(scene)
	await create_timer(0.05).timeout
	scene.load_battle_state(battle_state)
	await create_timer(0.05).timeout

	var before: Dictionary = scene.get_ui_snapshot()
	var before_moves := _array_value(before.get("moves", []))
	_assert(not String(before.get("player_name", "")).is_empty(), "expected player name label")
	_assert(not String(before.get("opponent_name", "")).is_empty(), "expected opponent name label")
	_assert(String(before.get("player_hp", "")).begins_with("HP "), "expected player HP label")
	_assert(String(before.get("opponent_hp", "")).begins_with("HP "), "expected opponent HP label")
	_assert(before_moves.size() == 4, "expected four move button slots")
	_assert(String(before_moves[0]).contains("25/25"), "expected first move PP before turn")
	_assert(String(before.get("message", "")).contains("wants to battle"), "expected trainer intro message")
	_assert(
		String(before.get("presentation_status", "")) == "first_slice_not_source_equivalent",
		"expected battle scene to expose non-source-equivalent status"
	)

	var turn_result: Dictionary = scene.play_player_move(0)
	await create_timer(0.05).timeout
	var after: Dictionary = scene.get_ui_snapshot()
	var after_moves := _array_value(after.get("moves", []))
	var result_contract: Dictionary = scene.get_battle_result()
	_assert(String(turn_result.get("status", "")) == "ok", "expected scene move turn")
	_assert(String(result_contract.get("outcome", "")) == "player_won", "expected scene result outcome")
	_assert(_has_unsupported(result_contract, "battle_scene_not_source_equivalent"), "expected battle scene source-equivalence unsupported note")
	_assert(_has_unsupported(result_contract, "battle_turn_loop_first_slice"), "expected battle turn loop unsupported note")
	_assert(String(after.get("opponent_hp", "")).begins_with("HP 0/"), "expected opponent HP to reach zero")
	_assert(String(after_moves[0]).contains("24/25"), "expected first move PP after turn")
	_assert(String(after.get("message", "")).contains("You won the battle."), "expected win message")

	if _failed:
		return

	print(JSON.stringify({
		"battle_scene_smoke": "ok",
		"outcome": String(result_contract.get("outcome", "")),
		"opponent_hp": String(after.get("opponent_hp", "")),
	}))
	scene.queue_free()
	engine.free()
	registry.free()
	quit(0)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true
	quit(1)


func _array_value(value) -> Array:
	return value if typeof(value) == TYPE_ARRAY else []


func _has_unsupported(record: Dictionary, code: String) -> bool:
	var unsupported = record.get("unsupported", [])
	if typeof(unsupported) != TYPE_ARRAY:
		return false
	for item in unsupported:
		if typeof(item) == TYPE_DICTIONARY and String(item.get("code", "")) == code:
			return true
	return false
