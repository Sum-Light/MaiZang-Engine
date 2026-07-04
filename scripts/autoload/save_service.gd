extends Node

const SCHEMA_NAME := "pokeemerald-godot-save"
const SCHEMA_VERSION := 1
const DEFAULT_SLOT_ID := "slot_0"

const SAVE_STATUS_EMPTY := 0
const SAVE_STATUS_OK := 1
const SAVE_STATUS_CORRUPT := 2
const SAVE_STATUS_NO_FLASH := 4
const SAVE_STATUS_ERROR := 0xFF

const SAVE_NORMAL := "SAVE_NORMAL"
const SAVE_LINK := "SAVE_LINK"
const SAVE_HALL_OF_FAME := "SAVE_HALL_OF_FAME"
const SAVE_OVERWRITE_DIFFERENT_FILE := "SAVE_OVERWRITE_DIFFERENT_FILE"

const SOURCE_TRACE := [
	"data/scripts/std_msgbox.inc:Common_EventScript_SaveGame",
	"data/text/save.inc:gText_ConfirmSave/gText_AlreadySavedFile/gText_SavingDontTurnOff/gText_PlayerSavedGame/gText_DifferentSaveFile/gText_SaveError",
	"include/save.h:SAVE_STATUS_*/SAVE_*",
	"include/config/save.h:SKIP_SAVE_CONFIRMATION",
	"src/start_menu.c:SaveGame",
	"src/start_menu.c:SaveConfirmSaveCallback",
	"src/start_menu.c:SaveDoSaveCallback",
	"src/start_menu.c:SaveSuccessCallback",
	"src/start_menu.c:SaveErrorCallback",
	"src/save.c:TrySavingData",
	"src/save.c:HandleSavingData",
	"src/save.c:LoadGameSave",
	"src/load_save.c:CopyPartyAndObjectsToSave",
	"src/load_save.c:CopyPartyAndObjectsFromSave",
	"src/load_save.c:SavePlayerParty",
	"src/load_save.c:LoadPlayerParty",
	"src/load_save.c:SaveObjectEvents",
	"src/load_save.c:LoadObjectEvents",
]

var _game_state: Node = null


func configure_game_state(game_state: Node) -> void:
	_game_state = game_state


func get_default_save_path(slot_id: String = DEFAULT_SLOT_ID) -> String:
	return "user://%s_%s.json" % [SCHEMA_NAME, _normalize_slot_id(slot_id)]


func describe_save_flow(options: Dictionary = {}) -> Dictionary:
	var existing_save := bool(options.get("existing_save", false))
	var different_save_file := bool(options.get("different_save_file", false))
	var skip_save_confirmation := bool(options.get("skip_save_confirmation", false))
	var steps: Array = [
		{
			"kind": "message_yes_no",
			"text_label": "gText_ConfirmSave",
			"default_choice": "YES",
			"source": "src/start_menu.c:SaveConfirmSaveCallback -> SaveYesNoCallback",
		},
	]
	if existing_save and not skip_save_confirmation:
		steps.append({
			"kind": "message_yes_no",
			"text_label": "gText_DifferentSaveFile" if different_save_file else "gText_AlreadySavedFile",
			"default_choice": "NO" if different_save_file else "YES",
			"source": "src/start_menu.c:SaveFileExistsCallback",
		})
	steps.append_array([
		{
			"kind": "message",
			"text_label": "gText_SavingDontTurnOff",
			"source": "src/start_menu.c:SaveSavingMessageCallback",
		},
		{
			"kind": "write_snapshot",
			"save_type": SAVE_OVERWRITE_DIFFERENT_FILE if different_save_file else String(options.get("save_type", SAVE_NORMAL)),
			"source": "src/start_menu.c:SaveDoSaveCallback -> src/save.c:TrySavingData",
		},
		{
			"kind": "success_message",
			"text_label": "gText_PlayerSavedGame",
			"audio": "SE_SAVE",
			"source": "src/start_menu.c:SaveSuccessCallback",
		},
		{
			"kind": "error_message",
			"text_label": "gText_SaveError",
			"audio": "SE_BOO",
			"source": "src/start_menu.c:SaveErrorCallback",
		},
	])
	return {
		"status": "ok",
		"steps": steps,
		"source_trace": SOURCE_TRACE.duplicate(),
		"unsupported": _unsupported_notes(),
	}


func build_snapshot(game_state: Node = null, options: Dictionary = {}) -> Dictionary:
	var resolved_game_state := _get_game_state(game_state)
	if resolved_game_state == null:
		return _error_result("missing_game_state", "GameState is required to build a save snapshot.")
	var save_counter := int(options.get("save_counter", 0))
	var slot_id := String(options.get("slot_id", DEFAULT_SLOT_ID))
	var save_type := String(options.get("save_type", SAVE_NORMAL))
	var state := _snapshot_game_state(resolved_game_state)
	return {
		"schema": SCHEMA_NAME,
		"schema_version": SCHEMA_VERSION,
		"slot_id": slot_id,
		"save_type": save_type,
		"save_status": "SAVE_STATUS_OK",
		"save_status_value": SAVE_STATUS_OK,
		"save_counter": save_counter,
		"created_unix_time": int(Time.get_unix_time_from_system()),
		"game_state": state,
		"source_save_blocks": _source_save_block_summary(state),
		"save_flow": describe_save_flow(options),
		"source_trace": SOURCE_TRACE.duplicate(),
		"unsupported": _unsupported_notes(),
	}


func save_game(game_state: Node = null, save_path: String = "", options: Dictionary = {}) -> Dictionary:
	var resolved_game_state := _get_game_state(game_state)
	if resolved_game_state == null:
		return _error_result("missing_game_state", "GameState is required to save.")
	var path := save_path if not save_path.is_empty() else get_default_save_path(String(options.get("slot_id", DEFAULT_SLOT_ID)))
	var existing_save := FileAccess.file_exists(path)
	var save_counter := int(options.get("save_counter", _read_existing_save_counter(path) + 1))
	var snapshot_options := options.duplicate(true)
	snapshot_options["save_counter"] = save_counter
	snapshot_options["existing_save"] = existing_save
	var snapshot := build_snapshot(resolved_game_state, snapshot_options)
	if String(snapshot.get("status", "")) == "error":
		return snapshot
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return _error_result("open_failed", "Could not open save file for writing.", {
			"path": path,
			"save_status": "SAVE_STATUS_ERROR",
			"save_status_value": SAVE_STATUS_ERROR,
			"open_error": FileAccess.get_open_error(),
		})
	file.store_string(JSON.stringify(snapshot, "\t"))
	file = null
	return {
		"status": "ok",
		"save_status": "SAVE_STATUS_OK",
		"save_status_value": SAVE_STATUS_OK,
		"path": path,
		"save_counter": save_counter,
		"snapshot": snapshot,
		"save_flow": snapshot.get("save_flow", {}),
		"source_trace": SOURCE_TRACE.duplicate(),
	}


func load_game(save_path: String = "", game_state: Node = null) -> Dictionary:
	var path := save_path if not save_path.is_empty() else get_default_save_path()
	if not FileAccess.file_exists(path):
		return {
			"status": "empty",
			"save_status": "SAVE_STATUS_EMPTY",
			"save_status_value": SAVE_STATUS_EMPTY,
			"path": path,
			"source_trace": SOURCE_TRACE.duplicate(),
		}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _error_result("open_failed", "Could not open save file for reading.", {
			"path": path,
			"save_status": "SAVE_STATUS_ERROR",
			"save_status_value": SAVE_STATUS_ERROR,
			"open_error": FileAccess.get_open_error(),
		})
	var text := file.get_as_text()
	file = null
	var json := JSON.new()
	var parse_error := json.parse(text)
	if parse_error != OK:
		return _error_result("parse_failed", json.get_error_message(), {
			"path": path,
			"save_status": "SAVE_STATUS_CORRUPT",
			"save_status_value": SAVE_STATUS_CORRUPT,
			"error_line": json.get_error_line(),
		})
	var snapshot = json.data
	if typeof(snapshot) != TYPE_DICTIONARY:
		return _error_result("invalid_snapshot", "Save file did not contain a dictionary snapshot.", {
			"path": path,
			"save_status": "SAVE_STATUS_CORRUPT",
			"save_status_value": SAVE_STATUS_CORRUPT,
		})
	var validation := validate_snapshot(snapshot)
	if String(validation.get("status", "")) != "ok":
		validation["path"] = path
		return validation
	var apply_result := apply_snapshot(snapshot, game_state)
	return {
		"status": "ok" if String(apply_result.get("status", "")) == "ok" else "loaded_unapplied",
		"save_status": "SAVE_STATUS_OK",
		"save_status_value": SAVE_STATUS_OK,
		"path": path,
		"save_counter": int(snapshot.get("save_counter", 0)),
		"snapshot": snapshot,
		"apply_result": apply_result,
		"source_trace": SOURCE_TRACE.duplicate(),
	}


func validate_snapshot(snapshot: Dictionary) -> Dictionary:
	if String(snapshot.get("schema", "")) != SCHEMA_NAME:
		return _error_result("schema_mismatch", "Snapshot schema is not supported.", {
			"save_status": "SAVE_STATUS_CORRUPT",
			"save_status_value": SAVE_STATUS_CORRUPT,
		})
	if int(snapshot.get("schema_version", 0)) != SCHEMA_VERSION:
		return _error_result("schema_version_mismatch", "Snapshot schema version is not supported.", {
			"save_status": "SAVE_STATUS_CORRUPT",
			"save_status_value": SAVE_STATUS_CORRUPT,
		})
	if typeof(snapshot.get("game_state", {})) != TYPE_DICTIONARY:
		return _error_result("missing_game_state_snapshot", "Snapshot is missing game_state data.", {
			"save_status": "SAVE_STATUS_CORRUPT",
			"save_status_value": SAVE_STATUS_CORRUPT,
		})
	return {"status": "ok", "source_trace": SOURCE_TRACE.duplicate()}


func apply_snapshot(snapshot: Dictionary, game_state: Node = null) -> Dictionary:
	var resolved_game_state := _get_game_state(game_state)
	if resolved_game_state == null:
		return _error_result("missing_game_state", "GameState is required to apply a save snapshot.")
	var state := _dict_field(snapshot, "game_state")
	resolved_game_state.current_map_id = String(state.get("current_map_id", resolved_game_state.current_map_id))
	resolved_game_state.player_grid_position = _vector2i_from_save(state.get("player_grid_position", {}), resolved_game_state.player_grid_position)
	if resolved_game_state.has_method("set_player_gender"):
		resolved_game_state.set_player_gender(String(state.get("player_gender", resolved_game_state.player_gender)))
	else:
		resolved_game_state.player_gender = String(state.get("player_gender", resolved_game_state.player_gender))
	if resolved_game_state.has_method("set_player_name"):
		resolved_game_state.set_player_name(String(state.get("player_name", resolved_game_state.player_name)))
	else:
		resolved_game_state.player_name = String(state.get("player_name", resolved_game_state.player_name))
	resolved_game_state.flags = _bool_dictionary(state.get("flags", {}))
	resolved_game_state.vars = _int_dictionary(state.get("vars", {}))
	var party := _array_field(state, "player_party")
	if resolved_game_state.has_method("set_player_party"):
		resolved_game_state.set_player_party(party)
	else:
		resolved_game_state.player_party = party.duplicate(true)
	return {
		"status": "ok",
		"current_map_id": resolved_game_state.current_map_id,
		"player_grid_position": _vector2i_to_save(resolved_game_state.player_grid_position),
		"party_count": _party_count(resolved_game_state),
		"source_trace": [
			"src/save.c:LoadGameSave",
			"src/load_save.c:CopyPartyAndObjectsFromSave",
		],
	}


func _snapshot_game_state(game_state: Node) -> Dictionary:
	return {
		"current_map_id": String(game_state.current_map_id),
		"player_grid_position": _vector2i_to_save(game_state.player_grid_position),
		"player_name": game_state.get_player_name() if game_state.has_method("get_player_name") else String(game_state.player_name),
		"player_gender": game_state.get_player_gender() if game_state.has_method("get_player_gender") else String(game_state.player_gender),
		"flags": _bool_dictionary(game_state.flags),
		"vars": _int_dictionary(game_state.vars),
		"player_party": game_state.get_player_party() if game_state.has_method("get_player_party") else game_state.player_party.duplicate(true),
		"player_party_count": _party_count(game_state),
	}


func _source_save_block_summary(state: Dictionary) -> Dictionary:
	return {
		"save_block1": {
			"current_map_id": state.get("current_map_id", ""),
			"player_grid_position": state.get("player_grid_position", {}),
			"flags_count": _dict_field(state, "flags").size(),
			"vars_count": _dict_field(state, "vars").size(),
			"source": "struct SaveBlock1 plus src/load_save.c:SaveObjectEvents",
		},
		"save_block2": {
			"player_name": state.get("player_name", ""),
			"player_gender": state.get("player_gender", ""),
			"player_party_count": int(state.get("player_party_count", 0)),
			"source": "struct SaveBlock2 plus src/load_save.c:SavePlayerParty",
		},
		"pokemon_storage": {
			"status": "future",
			"source": "struct PokemonStorage sectors in include/save.h",
		},
		"save_block3": {
			"status": "future",
			"source": "struct SaveBlock3 chunks in include/save.h",
		},
	}


func _read_existing_save_counter(path: String) -> int:
	if not FileAccess.file_exists(path):
		return 0
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return 0
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return 0
	if typeof(json.data) != TYPE_DICTIONARY:
		return 0
	return int(json.data.get("save_counter", 0))


func _get_game_state(game_state: Node) -> Node:
	if game_state != null:
		return game_state
	if _game_state != null:
		return _game_state
	if has_node("/root/GameState"):
		_game_state = get_node("/root/GameState")
	return _game_state


func _unsupported_notes() -> Array:
	return [
		{
			"code": "gba_flash_sector_format_not_recreated",
			"source": "src/save.c + include/save.h",
			"detail": "Godot first pass writes a normal JSON snapshot instead of GBA flash sectors, signatures, checksums, and rotating dual slots.",
		},
		{
			"code": "save_menu_presentation_future",
			"source": "src/start_menu.c:SaveGameTask",
			"detail": "Save confirmation windows, text printer timing, YES/NO menu task, SE_SAVE/SE_BOO playback, and timer waits are represented as metadata only.",
		},
		{
			"code": "partial_save_blocks",
			"source": "src/load_save.c:CopyPartyAndObjectsToSave",
			"detail": "Current snapshot covers GameState profile/location/flags/vars and player party; object event persistence, bag, PC storage, mail, options, stats, time, and special sectors remain future work.",
		},
	]


func _party_count(game_state: Node) -> int:
	if game_state.has_method("calculate_player_party_count"):
		return int(game_state.calculate_player_party_count())
	if game_state.has_method("get_player_party_count"):
		return int(game_state.get_player_party_count())
	return _array_field(game_state, "player_party").size()


func _vector2i_to_save(value: Vector2i) -> Dictionary:
	return {"x": value.x, "y": value.y}


func _vector2i_from_save(value, default_value: Vector2i) -> Vector2i:
	if typeof(value) == TYPE_DICTIONARY:
		return Vector2i(int(value.get("x", default_value.x)), int(value.get("y", default_value.y)))
	if typeof(value) == TYPE_ARRAY and value.size() >= 2:
		return Vector2i(int(value[0]), int(value[1]))
	return default_value


func _dict_field(record, field_name: String) -> Dictionary:
	if typeof(record) != TYPE_DICTIONARY:
		return {}
	var value = record.get(field_name, {})
	return value if typeof(value) == TYPE_DICTIONARY else {}


func _array_field(record, field_name: String) -> Array:
	if typeof(record) != TYPE_DICTIONARY:
		return []
	var value = record.get(field_name, [])
	return value if typeof(value) == TYPE_ARRAY else []


func _bool_dictionary(value) -> Dictionary:
	var source = value if typeof(value) == TYPE_DICTIONARY else {}
	var result := {}
	for key in source.keys():
		result[String(key)] = bool(source.get(key))
	return result


func _int_dictionary(value) -> Dictionary:
	var source = value if typeof(value) == TYPE_DICTIONARY else {}
	var result := {}
	for key in source.keys():
		result[String(key)] = int(source.get(key))
	return result


func _normalize_slot_id(slot_id: String) -> String:
	var normalized := slot_id.strip_edges().to_lower()
	if normalized.is_empty():
		return DEFAULT_SLOT_ID
	var safe := ""
	for index in range(normalized.length()):
		var code := normalized.unicode_at(index)
		var ch := normalized.substr(index, 1)
		if (code >= 97 and code <= 122) or (code >= 48 and code <= 57) or ch == "_" or ch == "-":
			safe += ch
		else:
			safe += "_"
	return safe


func _error_result(code: String, detail: String, extra: Dictionary = {}) -> Dictionary:
	var result := {
		"status": "error",
		"error": code,
		"detail": detail,
		"source_trace": SOURCE_TRACE.duplicate(),
	}
	for key in extra.keys():
		result[key] = extra[key]
	return result
