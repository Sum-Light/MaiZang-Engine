extends Control

signal battle_finished(result: Dictionary)

const VIEWPORT_SIZE := Vector2(240, 160)
const FONT_SIZE := 8
const HP_GREEN := Color(0.26, 0.74, 0.30, 1.0)
const HP_YELLOW := Color(0.88, 0.76, 0.24, 1.0)
const HP_RED := Color(0.88, 0.25, 0.22, 1.0)
const PRESENTATION_STATUS := "first_slice_not_source_equivalent"

var _sequence: Dictionary = {}
var _battle_state: Dictionary = {}
var _battle_engine: Node = null
var _game_state: Node = null
var _built := false
var _move_buttons: Array = []
var _message_lines: Array = []
var _last_result: Dictionary = {}

var _opponent_name_label: Label
var _opponent_hp_label: Label
var _opponent_hp_fill: ColorRect
var _player_name_label: Label
var _player_hp_label: Label
var _player_hp_fill: ColorRect
var _message_label: Label
var _finish_button: Button


func _ready() -> void:
	_ensure_ui()


func configure(sequence: Dictionary, battle_engine: Node, game_state: Node = null) -> void:
	_ensure_ui()
	_sequence = sequence.duplicate(true)
	_battle_state = _dictionary_value(_sequence.get("battle_state", {})).duplicate(true)
	_battle_engine = battle_engine
	_game_state = game_state
	_last_result = {}
	_message_lines = [_battle_opening_message()]
	_finish_button.visible = false
	_refresh()


func configure_battle_engine(battle_engine: Node) -> void:
	_battle_engine = battle_engine


func load_battle_state(battle_state: Dictionary) -> void:
	configure({
		"battle_state": battle_state,
		"trainer": battle_state.get("trainer", {}),
	}, _battle_engine, _game_state)


func play_player_move(move_slot: int) -> Dictionary:
	_on_move_pressed(move_slot)
	return {
		"status": "ok" if not _last_result.is_empty() else "blocked",
		"battle_state": _battle_state.duplicate(true),
		"battle_result": _last_result.duplicate(true),
		"messages": _message_lines.duplicate(true),
		"outcome": String(_last_result.get("outcome", "")),
	}


func get_battle_state() -> Dictionary:
	return _battle_state.duplicate(true)


func get_battle_result() -> Dictionary:
	return _last_result.duplicate(true)


func get_ui_snapshot() -> Dictionary:
	var move_labels: Array = []
	for button in _move_buttons:
		if button is Button:
			move_labels.append(button.text)
	return {
		"player_name": _player_name_label.text if _player_name_label != null else "",
		"opponent_name": _opponent_name_label.text if _opponent_name_label != null else "",
		"player_hp": _player_hp_label.text if _player_hp_label != null else "",
		"opponent_hp": _opponent_hp_label.text if _opponent_hp_label != null else "",
		"moves": move_labels,
		"message": _message_label.text if _message_label != null else "",
		"outcome": String(_last_result.get("outcome", "")),
		"presentation_status": PRESENTATION_STATUS,
	}


func _ensure_ui() -> void:
	if _built:
		return
	_built = true
	name = "BattleScene"
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)
	custom_minimum_size = VIEWPORT_SIZE

	var background := ColorRect.new()
	background.color = Color(0.55, 0.74, 0.61, 1.0)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	_add_rect(Rect2(0, 92, 240, 68), Color(0.93, 0.91, 0.79, 1.0))
	_add_rect(Rect2(104, 8, 128, 34), Color(0.98, 0.98, 0.91, 1.0))
	_add_rect(Rect2(8, 66, 128, 34), Color(0.98, 0.98, 0.91, 1.0))
	_add_rect(Rect2(12, 28, 48, 28), Color(0.35, 0.46, 0.40, 1.0))
	_add_rect(Rect2(176, 66, 48, 28), Color(0.35, 0.46, 0.40, 1.0))

	_opponent_name_label = _add_label(Rect2(110, 10, 116, 10), "")
	_opponent_hp_label = _add_label(Rect2(110, 28, 116, 10), "")
	_opponent_hp_fill = _add_hp_bar(Rect2(142, 23, 78, 4))
	_player_name_label = _add_label(Rect2(14, 68, 116, 10), "")
	_player_hp_label = _add_label(Rect2(14, 86, 116, 10), "")
	_player_hp_fill = _add_hp_bar(Rect2(46, 81, 78, 4))
	_message_label = _add_label(Rect2(10, 106, 110, 44), "")
	_message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	for index in range(4):
		var button := Button.new()
		button.position = Vector2(128, 104 + index * 13)
		button.size = Vector2(104, 12)
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_font_size_override("font_size", FONT_SIZE)
		button.pressed.connect(_on_move_pressed.bind(index))
		add_child(button)
		_move_buttons.append(button)

	_finish_button = Button.new()
	_finish_button.position = Vector2(128, 148)
	_finish_button.size = Vector2(104, 10)
	_finish_button.text = "Return"
	_finish_button.focus_mode = Control.FOCUS_NONE
	_finish_button.add_theme_font_size_override("font_size", FONT_SIZE)
	_finish_button.pressed.connect(_on_finish_pressed)
	add_child(_finish_button)


func _on_move_pressed(move_slot: int) -> void:
	if _battle_engine == null or not _battle_engine.has_method("use_move"):
		_message_lines = ["BattleEngine unavailable."]
		_refresh()
		return
	if not _last_result.is_empty():
		return

	var player_party := _array_value(_battle_state.get("player_party", []))
	var opponent_party := _array_value(_battle_state.get("opponent_party", []))
	var active := _dictionary_value(_battle_state.get("active", {}))
	var player_index := int(active.get("player", 0))
	var opponent_index := int(active.get("opponent", 0))
	if player_index < 0 or player_index >= player_party.size() or opponent_index < 0 or opponent_index >= opponent_party.size():
		_message_lines = ["Invalid active battler."]
		_refresh()
		return

	var player_mon: Dictionary = player_party[player_index]
	var opponent_mon: Dictionary = opponent_party[opponent_index]
	var messages: Array = []
	var player_result = _battle_engine.use_move(player_mon, opponent_mon, move_slot, {"damage_roll_percent": 100})
	if typeof(player_result) != TYPE_DICTIONARY:
		_message_lines = ["Invalid move result."]
		_refresh()
		return
	messages.append_array(_message_texts(player_result.get("messages", [])))
	player_party[player_index] = player_result.get("attacker", player_mon)
	opponent_party[opponent_index] = player_result.get("defender", opponent_mon)

	var outcome := "in_progress"
	if bool(_dictionary_value(opponent_party[opponent_index]).get("fainted", false)):
		outcome = "player_won"
	else:
		var opponent_slot := _first_usable_move_slot(_dictionary_value(opponent_party[opponent_index]))
		if opponent_slot >= 0:
			var opponent_result = _battle_engine.use_move(
				_dictionary_value(opponent_party[opponent_index]),
				_dictionary_value(player_party[player_index]),
				opponent_slot,
				{"damage_roll_percent": 100}
			)
			if typeof(opponent_result) == TYPE_DICTIONARY:
				messages.append_array(_message_texts(opponent_result.get("messages", [])))
				opponent_party[opponent_index] = opponent_result.get("attacker", opponent_party[opponent_index])
				player_party[player_index] = opponent_result.get("defender", player_party[player_index])
		if bool(_dictionary_value(player_party[player_index]).get("fainted", false)):
			outcome = "opponent_won"

	_battle_state["player_party"] = player_party
	_battle_state["opponent_party"] = opponent_party
	_battle_state["turn"] = int(_battle_state.get("turn", 0)) + 1
	_battle_state["outcome"] = outcome
	_battle_state["last_turn"] = {
		"status": "ok",
		"actor": "round_demo",
		"player_move_slot": move_slot,
		"messages": messages,
		"source": "scripts/battle/battle_scene.gd:first_pass_debug_round_not_source_equivalent",
		"presentation_status": PRESENTATION_STATUS,
	}
	_message_lines = messages
	if outcome == "in_progress":
		_message_lines.append("Debug round complete.")
	elif outcome == "player_won":
		_message_lines.append("You won the battle.")
	elif outcome == "opponent_won":
		_message_lines.append("You lost the battle.")
	_last_result = _build_result_contract(outcome)
	_finish_button.visible = true
	_refresh()


func _on_finish_pressed() -> void:
	var result := _last_result
	if result.is_empty():
		result = _build_result_contract("debug_cancelled")
	battle_finished.emit(result)


func _refresh() -> void:
	var player_mon := _active_mon("player")
	var opponent_mon := _active_mon("opponent")
	_player_name_label.text = _mon_title(player_mon)
	_player_hp_label.text = _hp_text(player_mon)
	_set_hp_fill(_player_hp_fill, player_mon)
	_opponent_name_label.text = _mon_title(opponent_mon)
	_opponent_hp_label.text = _hp_text(opponent_mon)
	_set_hp_fill(_opponent_hp_fill, opponent_mon)
	_message_label.text = "\n".join(_message_lines.slice(max(0, _message_lines.size() - 4), _message_lines.size()))
	_refresh_move_buttons(player_mon)


func _refresh_move_buttons(player_mon: Dictionary) -> void:
	var moves := _array_value(player_mon.get("moves", []))
	for index in range(_move_buttons.size()):
		var button: Button = _move_buttons[index]
		if index >= moves.size():
			button.disabled = true
			button.text = "-"
			continue
		var move = moves[index]
		if typeof(move) != TYPE_DICTIONARY:
			button.disabled = true
			button.text = "-"
			continue
		button.disabled = int(move.get("current_pp", 0)) <= 0 or not _last_result.is_empty()
		button.text = "%s %d/%d" % [
			_short_text(String(move.get("name", move.get("symbol", "Move"))), 10),
			int(move.get("current_pp", 0)),
			int(move.get("max_pp", 0)),
		]


func _build_result_contract(outcome: String) -> Dictionary:
	var result := {}
	if _battle_engine != null and _battle_engine.has_method("build_battle_result"):
		result = _battle_engine.build_battle_result(_battle_state, {"outcome": outcome})
	if typeof(result) != TYPE_DICTIONARY or result.is_empty():
		result = {
			"status": "ok",
			"outcome": outcome,
			"player_party": _array_value(_battle_state.get("player_party", [])),
			"opponent_party": _array_value(_battle_state.get("opponent_party", [])),
			"unsupported": [],
		}
	result["outcome"] = outcome
	result["battle_state"] = _battle_state.duplicate(true)
	result["statistics"] = _sequence.get("statistics", {})
	result["presentation_status"] = PRESENTATION_STATUS
	var debug_player_party := _dictionary_value(_sequence.get("debug_player_party", _battle_state.get("debug_player_party", {})))
	result["debug_player_party"] = debug_player_party.duplicate(true)
	var source_trace := _array_value(result.get("source_trace", []))
	for trace in _battle_scene_source_trace():
		if not source_trace.has(trace):
			source_trace.append(trace)
	result["source_trace"] = source_trace
	var post_battle = result.get("post_battle", {})
	post_battle = post_battle if typeof(post_battle) == TYPE_DICTIONARY else {}
	post_battle["return_to_field"] = true
	post_battle["field_resume"] = {
		"source_map": String(_sequence.get("source_map", "")),
		"source_position": _sequence.get("source_position", Vector2i.ZERO),
		"callback": "CB2_EndTrainerBattle",
	}
	post_battle["pending_game_state_party_write"] = not bool(debug_player_party.get("temporary", false))
	post_battle["debug_player_party_temporary"] = bool(debug_player_party.get("temporary", false))
	result["post_battle"] = post_battle
	var unsupported := _array_value(result.get("unsupported", []))
	unsupported.append_array(_battle_scene_unsupported())
	if bool(debug_player_party.get("temporary", false)):
		unsupported.append({
			"code": "debug_player_party_not_persisted",
			"source": "Godot-only debug fixture overlay",
			"detail": "The temporary debug party exists only to enter this battle before the starter flow is ported; Main must not persist it as the player's source party.",
		})
	result["unsupported"] = unsupported
	return result


func _battle_scene_source_trace() -> Array:
	return [
		"src/battle_main.c:CB2_InitBattle",
		"src/battle_main.c:BattleMainCB2",
		"src/battle_interface.c",
		"src/battle_controller_player.c",
		"src/battle_message.c",
		"src/battle_setup.c:CB2_EndTrainerBattle",
	]


func _battle_scene_unsupported() -> Array:
	return [{
		"code": "battle_scene_not_source_equivalent",
		"source": "src/battle_main.c:CB2_InitBattle",
		"detail": "This scene is a debug vertical slice. It does not recreate the source battle tilemaps, palette setup, battler sprites, healthbox sprites, window graphics, audio, or exact callback/task flow.",
	}, {
		"code": "battle_ui_windows_not_source_backed",
		"source": "src/battle_interface.c; src/battle_controller_player.c; src/battle_message.c",
		"detail": "The visible panels, move buttons, HP bars, trainer opening text, and message pacing are Godot controls, not imported source windows/tilemaps/text printers.",
	}, {
		"code": "debug_battle_scene_single_round",
		"source": "scripts/battle/battle_scene.gd",
		"detail": "The first BattleScene slice returns to field after one deterministic round unless a faint happens first.",
	}, {
		"code": "battle_turn_loop_first_slice",
		"source": "src/battle_main.c:BattleMainCB2",
		"detail": "Speed order, battle controller command queues, trainer AI, accuracy, priority, switching, items, abilities, status, rewards, EXP, and full move effects are not implemented in this scene.",
	}, {
		"code": "trainer_post_battle_flow_incomplete",
		"source": "src/battle_setup.c:CB2_EndTrainerBattle",
		"detail": "Trainer defeat text, money/reward flow, post-battle event scripts, object-event trainer flags, and full field callback restoration remain future source-backed work.",
	}]


func _active_mon(side: String) -> Dictionary:
	var party_key := "player_party" if side == "player" else "opponent_party"
	var active_key := "player" if side == "player" else "opponent"
	var party := _array_value(_battle_state.get(party_key, []))
	var active := _dictionary_value(_battle_state.get("active", {}))
	var index := int(active.get(active_key, 0))
	if index >= 0 and index < party.size() and typeof(party[index]) == TYPE_DICTIONARY:
		return party[index]
	return {}


func _first_usable_move_slot(mon: Dictionary) -> int:
	var moves := _array_value(mon.get("moves", []))
	for index in range(moves.size()):
		var move = moves[index]
		if typeof(move) == TYPE_DICTIONARY and int(move.get("current_pp", 0)) > 0:
			return index
	return -1


func _battle_opening_message() -> String:
	var trainer = _sequence.get("trainer", {})
	if typeof(trainer) == TYPE_DICTIONARY:
		var trainer_name := String(trainer.get("name", trainer.get("symbol", "Trainer")))
		return "%s wants to battle!" % trainer_name
	return "Battle started!"


func _mon_title(mon: Dictionary) -> String:
	if mon.is_empty():
		return "-"
	return "%s Lv.%d" % [_short_text(String(mon.get("name", mon.get("species", "Pokemon"))), 14), int(mon.get("level", 1))]


func _hp_text(mon: Dictionary) -> String:
	if mon.is_empty():
		return "HP -/-"
	return "HP %d/%d" % [int(mon.get("hp", 0)), int(mon.get("max_hp", 1))]


func _set_hp_fill(fill: ColorRect, mon: Dictionary) -> void:
	var max_hp: int = max(1, int(mon.get("max_hp", 1)))
	var hp: int = clampi(int(mon.get("hp", 0)), 0, max_hp)
	var ratio: float = float(hp) / float(max_hp)
	fill.size.x = roundi(78.0 * ratio)
	if ratio <= 0.2:
		fill.color = HP_RED
	elif ratio <= 0.5:
		fill.color = HP_YELLOW
	else:
		fill.color = HP_GREEN


func _message_texts(messages) -> Array:
	var result: Array = []
	if typeof(messages) != TYPE_ARRAY:
		return result
	for message in messages:
		if typeof(message) == TYPE_DICTIONARY:
			var text := String(message.get("text", ""))
			if not text.is_empty():
				result.append(text)
	return result


func _add_label(rect: Rect2, text: String) -> Label:
	var label := Label.new()
	label.position = rect.position
	label.size = rect.size
	label.text = text
	label.clip_text = true
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	add_child(label)
	return label


func _add_rect(rect: Rect2, color: Color) -> ColorRect:
	var color_rect := ColorRect.new()
	color_rect.position = rect.position
	color_rect.size = rect.size
	color_rect.color = color
	add_child(color_rect)
	return color_rect


func _add_hp_bar(rect: Rect2) -> ColorRect:
	_add_rect(Rect2(rect.position - Vector2(1, 1), rect.size + Vector2(2, 2)), Color(0.16, 0.16, 0.16, 1.0))
	return _add_rect(rect, HP_GREEN)


func _short_text(value: String, max_length: int) -> String:
	if value.length() <= max_length:
		return value
	return value.substr(0, max(0, max_length - 1)) + "."


func _array_value(value) -> Array:
	return value if typeof(value) == TYPE_ARRAY else []


func _dictionary_value(value) -> Dictionary:
	return value if typeof(value) == TYPE_DICTIONARY else {}
