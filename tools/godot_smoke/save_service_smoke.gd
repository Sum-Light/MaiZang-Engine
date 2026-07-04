extends SceneTree

const DATA_REGISTRY_SCRIPT := preload("res://scripts/autoload/data_registry.gd")
const BATTLE_ENGINE_SCRIPT := preload("res://scripts/autoload/battle_engine.gd")
const EVOLUTION_ENGINE_SCRIPT := preload("res://scripts/autoload/evolution_engine.gd")
const PARTY_RUNTIME_SCRIPT := preload("res://scripts/autoload/party_runtime.gd")
const GAME_STATE_SCRIPT := preload("res://scripts/autoload/game_state.gd")
const SAVE_SERVICE_SCRIPT := preload("res://scripts/autoload/save_service.gd")
const MAP_RUNTIME_SCRIPT := preload("res://scripts/autoload/map_runtime.gd")

var _failed := false


func _init() -> void:
	var registry = DATA_REGISTRY_SCRIPT.new()
	registry._ready()

	var battle_engine = BATTLE_ENGINE_SCRIPT.new()
	battle_engine.configure_registry(registry)

	var evolution_engine = EVOLUTION_ENGINE_SCRIPT.new()
	evolution_engine.configure_registry(registry)

	var party_runtime = PARTY_RUNTIME_SCRIPT.new()
	party_runtime.configure_registry(registry)
	party_runtime.configure_battle_engine(battle_engine)
	party_runtime.configure_evolution_engine(evolution_engine)

	var runtime = MAP_RUNTIME_SCRIPT.new()
	runtime.configure_from_data(
		registry.get_start_map_data(),
		registry.get_start_tileset_data(),
		registry.get_start_map_size()
	)

	var game_state = GAME_STATE_SCRIPT.new()
	game_state.set_player_name("SAVE")
	game_state.set_player_gender("FEMALE")
	game_state.current_map_id = runtime.get_current_map_id()
	game_state.player_grid_position = Vector2i(10, 10)
	game_state.set_flag("FLAG_RECEIVED_RUNNING_SHOES", true)
	game_state.set_var("VAR_LITTLEROOT_INTRO_STATE", 3)
	game_state.increment_game_stat("GAME_STAT_STEPS", 42)

	var party_result := party_runtime.create_party([
		{"species": "SPECIES_TORCHIC", "level": 5, "personality": 0},
		{"species": "SPECIES_BULBASAUR", "level": 16, "personality": 0x20},
	])
	_assert(String(party_result.get("status", "")) == "ok", "expected party creation")
	game_state.set_player_party(_array_field(party_result, "party"))

	var object_apply := runtime.apply_script_object_effects([
		{"op": "setobjectxy", "target": "LOCALID_LITTLEROOT_RIVAL", "position": [6, 10], "line": 0},
		{"op": "setobjectxyperm", "target": "LOCALID_LITTLEROOT_TWIN", "position": [10, 1], "line": 0},
		{
			"op": "setobjectmovementtype",
			"target": "LOCALID_LITTLEROOT_TWIN",
			"movement_type": "MOVEMENT_TYPE_FACE_UP",
			"line": 0,
		},
		{"op": "hideobject", "target": "LOCALID_LITTLEROOT_MOM", "line": 0},
	], game_state)
	_assert(_summary_count(object_apply, "applied") == 4, "expected save setup object effects")

	var save_service = SAVE_SERVICE_SCRIPT.new()
	save_service.configure_game_state(game_state)
	save_service.configure_map_runtime(runtime)
	var save_path := "user://save_service_smoke_%d.json" % [Time.get_ticks_usec()]
	var save_result := save_service.save_game(game_state, save_path, {"slot_id": "smoke"})
	_assert(String(save_result.get("status", "")) == "ok", "expected save ok")
	_assert(int(save_result.get("save_status_value", 0)) == SAVE_SERVICE_SCRIPT.SAVE_STATUS_OK, "expected OK save status")
	var snapshot := _dict_field(save_result, "snapshot")
	_assert(String(snapshot.get("schema", "")) == SAVE_SERVICE_SCRIPT.SCHEMA_NAME, "expected save schema")
	_assert(int(snapshot.get("save_counter", 0)) == 1, "expected first save counter")
	var snapshot_state := _dict_field(snapshot, "game_state")
	_assert(int(snapshot_state.get("player_party_count", 0)) == 2, "expected saved party count")
	_assert(int(_dict_field(snapshot_state, "game_stats").get("GAME_STAT_STEPS", 0)) == 42, "expected saved step stat")
	_assert(_flow_has_label(_dict_field(snapshot, "save_flow"), "gText_ConfirmSave"), "expected confirm-save flow label")
	_assert(_flow_has_label(_dict_field(snapshot, "save_flow"), "gText_PlayerSavedGame"), "expected success-save flow label")
	var map_runtime_state := _dict_field(snapshot, "map_runtime")
	_assert(String(map_runtime_state.get("status", "")) == "ok", "expected object runtime snapshot")
	_assert(int(map_runtime_state.get("object_events_count", 0)) == 8, "expected saved object event count")
	_assert(
		_event_position(_object_record(map_runtime_state, "LOCALID_LITTLEROOT_RIVAL")) == Vector2i(6, 10),
		"expected saved Rival position"
	)
	_assert(
		_template_position(_object_record(map_runtime_state, "LOCALID_LITTLEROOT_TWIN")) == Vector2i(10, 1),
		"expected saved Twin template position"
	)
	_assert(
		String(_object_record(map_runtime_state, "LOCALID_LITTLEROOT_TWIN").get("movement_type", "")) == "MOVEMENT_TYPE_FACE_UP",
		"expected saved Twin movement type"
	)
	_assert(
		bool(_object_record(map_runtime_state, "LOCALID_LITTLEROOT_MOM").get("runtime_hidden", false)),
		"expected saved Mom hidden state"
	)

	game_state.set_player_name("BROKEN")
	game_state.set_player_gender("MALE")
	game_state.current_map_id = "MAP_LITTLEROOT_TOWN"
	game_state.player_grid_position = Vector2i(1, 2)
	game_state.clear_flag("FLAG_RECEIVED_RUNNING_SHOES")
	game_state.set_var("VAR_LITTLEROOT_INTRO_STATE", 0)
	game_state.set_game_stat("GAME_STAT_STEPS", 0)
	game_state.clear_player_party()

	var fresh_runtime = MAP_RUNTIME_SCRIPT.new()
	fresh_runtime.configure_from_data(
		registry.get_start_map_data(),
		registry.get_start_tileset_data(),
		registry.get_start_map_size()
	)

	var load_result := save_service.load_game(save_path, game_state, fresh_runtime)
	_assert(String(load_result.get("status", "")) == "ok", "expected load ok")
	_assert(game_state.get_player_name() == "SAVE", "expected restored player name")
	_assert(game_state.get_player_gender() == "FEMALE", "expected restored player gender")
	_assert(game_state.current_map_id == "MAP_LITTLEROOT_TOWN", "expected restored map")
	_assert(game_state.player_grid_position == Vector2i(10, 10), "expected restored position")
	_assert(game_state.is_flag_set("FLAG_RECEIVED_RUNNING_SHOES"), "expected restored flag")
	_assert(game_state.get_var("VAR_LITTLEROOT_INTRO_STATE", 0) == 3, "expected restored var")
	_assert(game_state.get_game_stat("GAME_STAT_STEPS", 0) == 42, "expected restored step stat")
	_assert(game_state.calculate_player_party_count() == 2, "expected restored party")
	var map_apply_result := _dict_field(_dict_field(load_result, "apply_result"), "map_runtime_result")
	_assert(String(map_apply_result.get("status", "")) == "ok", "expected object runtime apply")
	_assert(_summary_count(map_apply_result, "applied") == 8, "expected all object events restored")
	_assert(
		_event_position(fresh_runtime.get_object_event_by_local_id("LOCALID_LITTLEROOT_RIVAL", true)) == Vector2i(6, 10),
		"expected restored Rival position"
	)
	_assert(
		_template_position(fresh_runtime.get_object_event_by_local_id("LOCALID_LITTLEROOT_TWIN", true)) == Vector2i(10, 1),
		"expected restored Twin template position"
	)
	_assert(
		String(fresh_runtime.get_object_event_by_local_id("LOCALID_LITTLEROOT_TWIN", true).get("movement_type", "")) == "MOVEMENT_TYPE_FACE_UP",
		"expected restored Twin movement type"
	)
	_assert(fresh_runtime.get_object_event_by_local_id("LOCALID_LITTLEROOT_MOM").is_empty(), "expected restored hidden Mom to be invisible")
	_assert(fresh_runtime.is_cell_occupied(Vector2i(6, 10)), "expected restored Rival occupancy")

	var second_save := save_service.save_game(game_state, save_path, {"slot_id": "smoke"})
	_assert(String(second_save.get("status", "")) == "ok", "expected second save ok")
	_assert(int(second_save.get("save_counter", 0)) == 2, "expected incremented save counter")

	var empty_result := save_service.load_game("user://missing_save_service_smoke_%d.json" % [Time.get_ticks_usec()], game_state)
	_assert(String(empty_result.get("status", "")) == "empty", "expected missing save to report empty")
	_assert(int(empty_result.get("save_status_value", -1)) == SAVE_SERVICE_SCRIPT.SAVE_STATUS_EMPTY, "expected empty save status")

	if _failed:
		return

	print(JSON.stringify({
		"save_service_smoke": "ok",
		"save_counter": int(second_save.get("save_counter", 0)),
		"map": game_state.current_map_id,
		"party_count": game_state.calculate_player_party_count(),
	}))
	save_service.free()
	fresh_runtime.free()
	runtime.free()
	party_runtime.free()
	evolution_engine.free()
	battle_engine.free()
	registry.free()
	game_state.free()
	quit(0)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true
	quit(1)


func _array_field(record: Dictionary, field_name: String) -> Array:
	var value = record.get(field_name, [])
	return value if typeof(value) == TYPE_ARRAY else []


func _dict_field(record: Dictionary, field_name: String) -> Dictionary:
	var value = record.get(field_name, {})
	return value if typeof(value) == TYPE_DICTIONARY else {}


func _flow_has_label(flow: Dictionary, text_label: String) -> bool:
	for step in _array_field(flow, "steps"):
		if typeof(step) == TYPE_DICTIONARY and String(step.get("text_label", "")) == text_label:
			return true
	return false


func _summary_count(summary: Dictionary, key: String) -> int:
	var records = summary.get(key, [])
	return records.size() if typeof(records) == TYPE_ARRAY else 0


func _object_record(snapshot: Dictionary, local_id: String) -> Dictionary:
	for record in _array_field(snapshot, "object_events"):
		if typeof(record) == TYPE_DICTIONARY and String(record.get("local_id", "")) == local_id:
			return record
	return {}


func _event_position(object_event: Dictionary) -> Vector2i:
	return _position_field(object_event, "position", "x", "y")


func _template_position(object_event: Dictionary) -> Vector2i:
	return _position_field(object_event, "template_position", "template_x", "template_y")


func _position_field(record: Dictionary, field_name: String, x_name: String, y_name: String) -> Vector2i:
	var position = record.get(field_name, {})
	if typeof(position) == TYPE_VECTOR2I:
		return position
	if typeof(position) == TYPE_DICTIONARY:
		return Vector2i(int(position.get("x", 0)), int(position.get("y", 0)))
	if typeof(position) == TYPE_ARRAY and position.size() >= 2:
		return Vector2i(int(position[0]), int(position[1]))
	return Vector2i(int(record.get(x_name, 0)), int(record.get(y_name, 0)))
