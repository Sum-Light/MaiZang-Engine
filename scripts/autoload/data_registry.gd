extends Node

const TILE_SIZE := 16
const FIRST_SLICE_MAP_ID := "MAP_LITTLEROOT_TOWN"
const FIRST_SLICE_MAP_NAME := "LittlerootTown"
const FIRST_SLICE_LAYOUT_ID := "LAYOUT_LITTLEROOT_TOWN"
const FIRST_SLICE_MAP_SIZE := Vector2i(20, 20)
const FIRST_SLICE_PRIMARY_TILESET := "gTileset_General"
const FIRST_SLICE_SECONDARY_TILESET := "gTileset_Petalburg"
const GENERATED_MANIFEST_PATH := "res://data/generated/import_manifest.json"
const GENERATED_START_MAP_PATH := "res://data/generated/maps/littleroot_town.json"
const GENERATED_START_TILESET_PATH := "res://data/generated/tilesets/littleroot_town.json"
const GENERATED_START_SCRIPT_PATH := "res://data/generated/scripts/littleroot_town.json"
const DEFAULT_MAP_OVERLAY_CATEGORY := "debug_fixtures"
const DEFAULT_OBJECT_EVENT_SPRITE_CATEGORY := "object_events"
const DEFAULT_BATTLE_STRING_CATEGORY := "battle_strings"
const DEFAULT_BATTLE_SCRIPT_CATEGORY := "scripts"
const DEFAULT_BATTLE_MOVE_EFFECT_CATEGORY := "move_effects"
const DEFAULT_BATTLE_ENVIRONMENT_CATEGORY := "environments"
const DEFAULT_BATTLE_TRANSITION_CATEGORY := "transitions"
const DEFAULT_POKEMON_BATTLE_SPRITE_CATEGORY := "battle_sprites"
const DEFAULT_TRAINER_BATTLE_SPRITE_CATEGORY := "trainer_sprites"

var import_report: Dictionary = {}
var _manifest_data: Dictionary = {}
var _map_entries_by_id: Dictionary = {}
var _map_entries_by_name: Dictionary = {}
var _tileset_entries_by_map_name: Dictionary = {}
var _script_entries: Array = []
var _script_entries_by_map_name: Dictionary = {}
var _text_entries_by_category: Dictionary = {}
var _pokemon_entries_by_category: Dictionary = {}
var _battle_entries_by_category: Dictionary = {}
var _map_overlay_entries_by_category: Dictionary = {}
var _object_event_sprite_entries_by_category: Dictionary = {}
var _map_data_by_id: Dictionary = {}
var _tileset_data_by_map_id: Dictionary = {}
var _script_data_by_map_id: Dictionary = {}
var _script_data_by_path: Dictionary = {}
var _text_data_by_category: Dictionary = {}
var _pokemon_data_by_category: Dictionary = {}
var _battle_data_by_category: Dictionary = {}
var _map_overlay_data_by_category: Dictionary = {}
var _object_event_sprite_data_by_category: Dictionary = {}
var _species_records_by_symbol: Dictionary = {}
var _species_records_by_id: Dictionary = {}
var _pokemon_battle_sprite_records_by_symbol: Dictionary = {}
var _pokemon_battle_sprite_records_by_id: Dictionary = {}
var _trainer_battle_sprite_records_by_symbol: Dictionary = {}
var _trainer_battle_sprite_records_by_id: Dictionary = {}
var _trainer_front_sprite_records_by_symbol: Dictionary = {}
var _trainer_front_sprite_records_by_id: Dictionary = {}
var _trainer_back_sprite_records_by_symbol: Dictionary = {}
var _trainer_back_sprite_records_by_id: Dictionary = {}
var _move_records_by_symbol: Dictionary = {}
var _move_records_by_id: Dictionary = {}
var _type_records_by_symbol: Dictionary = {}
var _type_records_by_id: Dictionary = {}
var _ability_records_by_symbol: Dictionary = {}
var _ability_records_by_id: Dictionary = {}
var _item_records_by_symbol: Dictionary = {}
var _item_records_by_id: Dictionary = {}
var _wild_encounter_records_by_label: Dictionary = {}
var _wild_encounter_records_by_map: Dictionary = {}
var _trainer_records_by_symbol: Dictionary = {}
var _trainer_records_by_id: Dictionary = {}
var _learnset_records_by_label: Dictionary = {}
var _nature_records_by_symbol: Dictionary = {}
var _nature_records_by_id: Dictionary = {}
var _evolution_records_by_species_symbol: Dictionary = {}
var _evolution_records_by_species_id: Dictionary = {}
var _pre_evolution_records_by_target_symbol: Dictionary = {}
var _pre_evolution_records_by_target_id: Dictionary = {}
var _battle_string_records_by_symbol: Dictionary = {}
var _battle_string_records_by_id: Dictionary = {}
var _battle_text_records_by_label: Dictionary = {}
var _battle_script_records_by_label: Dictionary = {}
var _battle_script_commands_by_opcode: Dictionary = {}
var _battle_script_commands_by_macro: Dictionary = {}
var _battle_move_effect_records_by_symbol: Dictionary = {}
var _battle_move_effect_records_by_id: Dictionary = {}
var _battle_environment_records_by_symbol: Dictionary = {}
var _battle_environment_records_by_id: Dictionary = {}
var _battle_environment_by_map_scene: Dictionary = {}
var _battle_transition_records_by_symbol: Dictionary = {}
var _battle_transition_records_by_id: Dictionary = {}
var _start_map_data: Dictionary = {}
var _start_tileset_data: Dictionary = {}
var _start_script_data: Dictionary = {}
var _debug_map_overlays_enabled := false


func _ready() -> void:
	_manifest_data = _load_json_object(GENERATED_MANIFEST_PATH, "generated import manifest")
	_index_manifest()
	_start_map_data = get_map_data(FIRST_SLICE_MAP_ID)
	_start_tileset_data = get_tileset_data_for_map(FIRST_SLICE_MAP_ID)
	_start_script_data = get_script_data_for_map(FIRST_SLICE_MAP_ID)
	if _start_map_data.is_empty():
		_start_map_data = _load_json_object(GENERATED_START_MAP_PATH, "generated map")
	if _start_tileset_data.is_empty():
		_start_tileset_data = _load_json_object(GENERATED_START_TILESET_PATH, "generated tileset")
	if _start_script_data.is_empty():
		_start_script_data = _load_json_object(GENERATED_START_SCRIPT_PATH, "generated script")


func set_debug_map_overlays_enabled(value: bool) -> void:
	_debug_map_overlays_enabled = value


func get_start_map_id() -> String:
	if not _start_map_data.is_empty():
		var map_info = _start_map_data.get("map", {})
		if typeof(map_info) == TYPE_DICTIONARY:
			return String(map_info.get("id", FIRST_SLICE_MAP_ID))
	return FIRST_SLICE_MAP_ID


func get_start_map_name() -> String:
	if not _start_map_data.is_empty():
		var map_info = _start_map_data.get("map", {})
		if typeof(map_info) == TYPE_DICTIONARY:
			return String(map_info.get("name", FIRST_SLICE_MAP_NAME))
	return FIRST_SLICE_MAP_NAME


func get_start_map_size() -> Vector2i:
	if not _start_map_data.is_empty():
		var layout_info = _start_map_data.get("layout", {})
		if typeof(layout_info) == TYPE_DICTIONARY:
			return Vector2i(
				int(layout_info.get("width", FIRST_SLICE_MAP_SIZE.x)),
				int(layout_info.get("height", FIRST_SLICE_MAP_SIZE.y))
			)
	return FIRST_SLICE_MAP_SIZE


func get_start_map_data(options: Dictionary = {}) -> Dictionary:
	return _map_data_with_optional_overlays(FIRST_SLICE_MAP_ID, _start_map_data, options)


func get_start_tileset_data() -> Dictionary:
	return _start_tileset_data


func get_start_script_data() -> Dictionary:
	return _start_script_data


func get_start_block_ids() -> Array:
	return _start_map_data.get("block_ids", [])


func get_available_map_ids() -> PackedStringArray:
	var map_ids := PackedStringArray()
	for map_id in _map_entries_by_id.keys():
		map_ids.append(String(map_id))
	return map_ids


func has_map_data(map_id: String) -> bool:
	return not get_map_data(map_id).is_empty()


func get_map_data(map_id: String, options: Dictionary = {}) -> Dictionary:
	if map_id == FIRST_SLICE_MAP_ID and _map_entries_by_id.is_empty() and not _start_map_data.is_empty():
		return _map_data_with_optional_overlays(map_id, _start_map_data, options)

	if _map_data_by_id.has(map_id):
		var cached = _map_data_by_id[map_id]
		return _map_data_with_optional_overlays(map_id, cached, options) if typeof(cached) == TYPE_DICTIONARY else {}

	var entry := _map_entry_for_id(map_id)
	if entry.is_empty():
		return {}

	var map_data := _load_json_object(_resource_path(String(entry.get("path", ""))), "generated map")
	_map_data_by_id[map_id] = map_data
	return _map_data_with_optional_overlays(map_id, map_data, options)


func get_tileset_data_for_map(map_id: String) -> Dictionary:
	if map_id == FIRST_SLICE_MAP_ID and _tileset_entries_by_map_name.is_empty() and not _start_tileset_data.is_empty():
		return _start_tileset_data

	if _tileset_data_by_map_id.has(map_id):
		var cached = _tileset_data_by_map_id[map_id]
		return cached if typeof(cached) == TYPE_DICTIONARY else {}

	var map_name := get_map_name(map_id)
	var entry = _tileset_entries_by_map_name.get(map_name, {})
	if typeof(entry) != TYPE_DICTIONARY:
		return {}

	var tileset_data := _load_json_object(_resource_path(String(entry.get("path", ""))), "generated tileset")
	_tileset_data_by_map_id[map_id] = tileset_data
	return tileset_data


func get_script_data_for_map(map_id: String) -> Dictionary:
	if map_id == FIRST_SLICE_MAP_ID and _script_entries_by_map_name.is_empty() and not _start_script_data.is_empty():
		return _start_script_data

	if _script_data_by_map_id.has(map_id):
		var cached = _script_data_by_map_id[map_id]
		return cached if typeof(cached) == TYPE_DICTIONARY else {}

	var map_name := get_map_name(map_id)
	var entry = _script_entries_by_map_name.get(map_name, {})
	if typeof(entry) != TYPE_DICTIONARY:
		return {}

	var script_data := _script_data_for_entry(entry)
	_script_data_by_map_id[map_id] = script_data
	return script_data


func get_script_record(script_label: String) -> Dictionary:
	return _get_record_from_script_entries(script_label, "scripts")


func get_movement_record(movement_label: String) -> Dictionary:
	return _get_record_from_script_entries(movement_label, "movements")


func get_script_text_record(text_label: String) -> Dictionary:
	return _get_record_from_script_entries(text_label, "texts")


func get_text_data(category: String = "global") -> Dictionary:
	if _text_data_by_category.has(category):
		var cached = _text_data_by_category[category]
		return cached if typeof(cached) == TYPE_DICTIONARY else {}

	var entry = _text_entries_by_category.get(category, {})
	if typeof(entry) != TYPE_DICTIONARY:
		return {}

	var text_data := _load_json_object(_resource_path(String(entry.get("path", ""))), "generated text")
	_text_data_by_category[category] = text_data
	return text_data


func get_text_record(text_label: String, category: String = "global") -> Dictionary:
	var text_data := get_text_data(category)
	if text_data.is_empty():
		return {}

	var texts = text_data.get("texts", {})
	if typeof(texts) != TYPE_DICTIONARY:
		return {}

	var record = texts.get(text_label, {})
	return record if typeof(record) == TYPE_DICTIONARY else {}


func get_text_display_text(text_label: String, category: String = "global") -> String:
	var record := get_text_record(text_label, category)
	if record.is_empty():
		return ""
	return String(record.get("display_text", ""))


func get_battle_string_data() -> Dictionary:
	return get_text_data(DEFAULT_BATTLE_STRING_CATEGORY)


func get_battle_data(category: String) -> Dictionary:
	if _battle_data_by_category.has(category):
		var cached = _battle_data_by_category[category]
		return cached if typeof(cached) == TYPE_DICTIONARY else {}

	var entry = _battle_entries_by_category.get(category, {})
	if typeof(entry) != TYPE_DICTIONARY:
		return {}

	var battle_data := _load_json_object(_resource_path(String(entry.get("path", ""))), "generated battle data")
	_battle_data_by_category[category] = battle_data
	return battle_data


func get_battle_scripts_data() -> Dictionary:
	return get_battle_data(DEFAULT_BATTLE_SCRIPT_CATEGORY)


func get_battle_script_record(script_label: String) -> Dictionary:
	_ensure_battle_script_indexes()
	var record = _battle_script_records_by_label.get(script_label, {})
	return record if typeof(record) == TYPE_DICTIONARY else {}


func get_battle_script_command_record(opcode_or_macro) -> Dictionary:
	_ensure_battle_script_indexes()
	if typeof(opcode_or_macro) == TYPE_INT:
		var id_record = _battle_script_commands_by_opcode.get(int(opcode_or_macro), {})
		return id_record if typeof(id_record) == TYPE_DICTIONARY else {}
	if typeof(opcode_or_macro) == TYPE_FLOAT:
		var float_record = _battle_script_commands_by_opcode.get(int(opcode_or_macro), {})
		return float_record if typeof(float_record) == TYPE_DICTIONARY else {}

	var key := String(opcode_or_macro)
	if key.is_valid_int():
		var numeric_record = _battle_script_commands_by_opcode.get(int(key), {})
		return numeric_record if typeof(numeric_record) == TYPE_DICTIONARY else {}
	if _battle_script_commands_by_opcode.has(key):
		var opcode_record = _battle_script_commands_by_opcode.get(key, {})
		return opcode_record if typeof(opcode_record) == TYPE_DICTIONARY else {}
	if _battle_script_commands_by_macro.has(key):
		var macro_record = _battle_script_commands_by_macro.get(key, {})
		return macro_record if typeof(macro_record) == TYPE_DICTIONARY else {}
	var normalized := key
	if not normalized.begins_with("B_SCR_OP_"):
		normalized = "B_SCR_OP_%s" % normalized.to_upper()
	var normalized_record = _battle_script_commands_by_opcode.get(normalized, {})
	return normalized_record if typeof(normalized_record) == TYPE_DICTIONARY else {}


func get_battle_move_effects_data() -> Dictionary:
	return get_battle_data(DEFAULT_BATTLE_MOVE_EFFECT_CATEGORY)


func get_battle_environments_data() -> Dictionary:
	return get_battle_data(DEFAULT_BATTLE_ENVIRONMENT_CATEGORY)


func get_battle_transitions_data() -> Dictionary:
	return get_battle_data(DEFAULT_BATTLE_TRANSITION_CATEGORY)


func get_battle_environment_record(environment_id_or_symbol) -> Dictionary:
	if typeof(environment_id_or_symbol) == TYPE_INT:
		return get_battle_environment_record_by_id(int(environment_id_or_symbol))
	if typeof(environment_id_or_symbol) == TYPE_FLOAT:
		return get_battle_environment_record_by_id(int(environment_id_or_symbol))

	var key := String(environment_id_or_symbol)
	if key.is_valid_int():
		return get_battle_environment_record_by_id(int(key))
	return get_battle_environment_record_by_symbol(key)


func get_battle_environment_record_by_symbol(environment_symbol: String) -> Dictionary:
	_ensure_battle_environment_indexes()
	var normalized := _normalize_battle_environment_symbol(environment_symbol)
	var record = _battle_environment_records_by_symbol.get(normalized, {})
	return record if typeof(record) == TYPE_DICTIONARY else {}


func get_battle_environment_record_by_id(environment_id: int) -> Dictionary:
	_ensure_battle_environment_indexes()
	var record = _battle_environment_records_by_id.get(environment_id, {})
	return record if typeof(record) == TYPE_DICTIONARY else {}


func get_battle_environment_record_for_map_scene(map_scene_symbol: String) -> Dictionary:
	_ensure_battle_environment_indexes()
	var normalized := map_scene_symbol
	if not normalized.begins_with("MAP_BATTLE_SCENE_"):
		normalized = "MAP_BATTLE_SCENE_%s" % normalized.to_upper()
	var symbol = _battle_environment_by_map_scene.get(normalized, "")
	if String(symbol).is_empty():
		return {}
	return get_battle_environment_record_by_symbol(String(symbol))


func get_battle_transition_record(transition_id_or_symbol) -> Dictionary:
	if typeof(transition_id_or_symbol) == TYPE_INT:
		return get_battle_transition_record_by_id(int(transition_id_or_symbol))
	if typeof(transition_id_or_symbol) == TYPE_FLOAT:
		return get_battle_transition_record_by_id(int(transition_id_or_symbol))

	var key := String(transition_id_or_symbol)
	if key.is_valid_int():
		return get_battle_transition_record_by_id(int(key))
	return get_battle_transition_record_by_symbol(key)


func get_battle_transition_record_by_symbol(transition_symbol: String) -> Dictionary:
	_ensure_battle_transition_indexes()
	var normalized := _normalize_battle_transition_symbol(transition_symbol)
	var record = _battle_transition_records_by_symbol.get(normalized, {})
	return record if typeof(record) == TYPE_DICTIONARY else {}


func get_battle_transition_record_by_id(transition_id: int) -> Dictionary:
	_ensure_battle_transition_indexes()
	var record = _battle_transition_records_by_id.get(transition_id, {})
	return record if typeof(record) == TYPE_DICTIONARY else {}


func get_battle_move_effect_record(effect_id_or_symbol) -> Dictionary:
	if typeof(effect_id_or_symbol) == TYPE_INT:
		return get_battle_move_effect_record_by_id(int(effect_id_or_symbol))
	if typeof(effect_id_or_symbol) == TYPE_FLOAT:
		return get_battle_move_effect_record_by_id(int(effect_id_or_symbol))

	var key := String(effect_id_or_symbol)
	if key.is_valid_int():
		return get_battle_move_effect_record_by_id(int(key))
	return get_battle_move_effect_record_by_symbol(key)


func get_battle_move_effect_record_by_symbol(effect_symbol: String) -> Dictionary:
	_ensure_battle_move_effect_indexes()
	var normalized := effect_symbol
	if not normalized.begins_with("EFFECT_"):
		normalized = "EFFECT_%s" % normalized.to_upper()
	var record = _battle_move_effect_records_by_symbol.get(normalized, {})
	return record if typeof(record) == TYPE_DICTIONARY else {}


func get_battle_move_effect_record_by_id(effect_id: int) -> Dictionary:
	_ensure_battle_move_effect_indexes()
	var record = _battle_move_effect_records_by_id.get(effect_id, {})
	return record if typeof(record) == TYPE_DICTIONARY else {}


func get_trainer_sprites_data() -> Dictionary:
	return get_battle_data(DEFAULT_TRAINER_BATTLE_SPRITE_CATEGORY)


func get_trainer_sprite_record(trainer_id_or_symbol) -> Dictionary:
	if typeof(trainer_id_or_symbol) == TYPE_INT:
		return get_trainer_sprite_record_by_id(int(trainer_id_or_symbol))
	if typeof(trainer_id_or_symbol) == TYPE_FLOAT:
		return get_trainer_sprite_record_by_id(int(trainer_id_or_symbol))

	var key := String(trainer_id_or_symbol)
	if key.is_valid_int():
		return get_trainer_sprite_record_by_id(int(key))
	return get_trainer_sprite_record_by_symbol(key)


func get_trainer_sprite_record_by_symbol(trainer_symbol: String) -> Dictionary:
	_ensure_trainer_battle_sprite_indexes()
	var normalized := _normalize_trainer_symbol(trainer_symbol)
	var record = _trainer_battle_sprite_records_by_symbol.get(normalized, {})
	return record if typeof(record) == TYPE_DICTIONARY else {}


func get_trainer_sprite_record_by_id(trainer_id: int) -> Dictionary:
	_ensure_trainer_battle_sprite_indexes()
	var record = _trainer_battle_sprite_records_by_id.get(trainer_id, {})
	return record if typeof(record) == TYPE_DICTIONARY else {}


func get_trainer_front_sprite_record(pic_id_or_symbol) -> Dictionary:
	if typeof(pic_id_or_symbol) == TYPE_INT:
		return get_trainer_front_sprite_record_by_id(int(pic_id_or_symbol))
	if typeof(pic_id_or_symbol) == TYPE_FLOAT:
		return get_trainer_front_sprite_record_by_id(int(pic_id_or_symbol))

	var key := String(pic_id_or_symbol)
	if key.is_valid_int():
		return get_trainer_front_sprite_record_by_id(int(key))
	return get_trainer_front_sprite_record_by_symbol(key)


func get_trainer_front_sprite_record_by_symbol(pic_symbol: String) -> Dictionary:
	_ensure_trainer_battle_sprite_indexes()
	var normalized := _normalize_trainer_front_pic_symbol(pic_symbol)
	var record = _trainer_front_sprite_records_by_symbol.get(normalized, {})
	return record if typeof(record) == TYPE_DICTIONARY else {}


func get_trainer_front_sprite_record_by_id(pic_id: int) -> Dictionary:
	_ensure_trainer_battle_sprite_indexes()
	var record = _trainer_front_sprite_records_by_id.get(pic_id, {})
	return record if typeof(record) == TYPE_DICTIONARY else {}


func get_trainer_back_sprite_record(pic_id_or_symbol) -> Dictionary:
	if typeof(pic_id_or_symbol) == TYPE_INT:
		return get_trainer_back_sprite_record_by_id(int(pic_id_or_symbol))
	if typeof(pic_id_or_symbol) == TYPE_FLOAT:
		return get_trainer_back_sprite_record_by_id(int(pic_id_or_symbol))

	var key := String(pic_id_or_symbol)
	if key.is_valid_int():
		return get_trainer_back_sprite_record_by_id(int(key))
	return get_trainer_back_sprite_record_by_symbol(key)


func get_trainer_back_sprite_record_by_symbol(pic_symbol: String) -> Dictionary:
	_ensure_trainer_battle_sprite_indexes()
	var normalized := _normalize_trainer_back_pic_symbol(pic_symbol)
	var record = _trainer_back_sprite_records_by_symbol.get(normalized, {})
	return record if typeof(record) == TYPE_DICTIONARY else {}


func get_trainer_back_sprite_record_by_id(pic_id: int) -> Dictionary:
	_ensure_trainer_battle_sprite_indexes()
	var record = _trainer_back_sprite_records_by_id.get(pic_id, {})
	return record if typeof(record) == TYPE_DICTIONARY else {}


func get_battle_string_record(battle_string_id_or_symbol) -> Dictionary:
	if typeof(battle_string_id_or_symbol) == TYPE_INT:
		return get_battle_string_by_id(int(battle_string_id_or_symbol))
	if typeof(battle_string_id_or_symbol) == TYPE_FLOAT:
		return get_battle_string_by_id(int(battle_string_id_or_symbol))

	var key := String(battle_string_id_or_symbol)
	if key.is_valid_int():
		return get_battle_string_by_id(int(key))

	_ensure_battle_string_indexes()
	var text_record = _battle_text_records_by_label.get(key, {})
	if typeof(text_record) == TYPE_DICTIONARY and not text_record.is_empty():
		return text_record

	var normalized := _normalize_battle_string_symbol(key)
	var record = _battle_string_records_by_symbol.get(normalized, {})
	return record if typeof(record) == TYPE_DICTIONARY else {}


func get_battle_string_by_id(string_id: int) -> Dictionary:
	_ensure_battle_string_indexes()
	var record = _battle_string_records_by_id.get(string_id, {})
	return record if typeof(record) == TYPE_DICTIONARY else {}


func get_battle_text_record(text_label: String) -> Dictionary:
	_ensure_battle_string_indexes()
	var record = _battle_text_records_by_label.get(text_label, {})
	return record if typeof(record) == TYPE_DICTIONARY else {}


func format_battle_message(battle_message_id_or_symbol, context: Dictionary = {}) -> Dictionary:
	var record := get_battle_string_record(battle_message_id_or_symbol)
	if record.is_empty():
		return {
			"status": "missing_record",
			"text": "",
			"unexpanded_text": "",
			"message": battle_message_id_or_symbol,
			"substitutions": [],
			"unresolved_placeholders": [],
			"text_controls": [],
			"metadata_only": [],
			"unsupported": [{
				"reason": "battle_message_record_missing",
				"message": str(battle_message_id_or_symbol),
			}],
		}

	var expanded := String(record.get("display_text", ""))
	var substitutions := []
	var unresolved := []
	var placeholders = record.get("placeholders", [])
	if typeof(placeholders) == TYPE_ARRAY:
		for placeholder in placeholders:
			if typeof(placeholder) != TYPE_DICTIONARY:
				continue
			var token_name := String(placeholder.get("token", ""))
			var raw_token := String(placeholder.get("raw", "{%s}" % token_name))
			var value = _battle_message_context_value(context, token_name, raw_token)
			if value == null:
				unresolved.append(placeholder)
				continue
			expanded = expanded.replace(raw_token, String(value))
			substitutions.append({
				"token": token_name,
				"raw": raw_token,
				"value": String(value),
				"category": String(placeholder.get("category", "")),
				"semantic_tags": placeholder.get("semantic_tags", []),
			})

	var unsupported := []
	var record_unsupported = record.get("unsupported", [])
	if typeof(record_unsupported) == TYPE_ARRAY:
		unsupported.append_array(record_unsupported)
	var unsupported_tokens = record.get("unsupported_tokens", [])
	if typeof(unsupported_tokens) == TYPE_ARRAY:
		unsupported.append_array(unsupported_tokens)

	return {
		"status": "partial" if not unresolved.is_empty() or not unsupported.is_empty() else "ok",
		"text": expanded,
		"unexpanded_text": String(record.get("display_text", "")),
		"record": record,
		"substitutions": substitutions,
		"unresolved_placeholders": unresolved,
		"text_controls": record.get("text_controls", []),
		"metadata_only": record.get("metadata_only", []),
		"audio_cues": record.get("audio_cues", []),
		"unsupported": unsupported,
	}


func get_map_overlays_data(category: String = DEFAULT_MAP_OVERLAY_CATEGORY) -> Dictionary:
	if _map_overlay_data_by_category.has(category):
		var cached = _map_overlay_data_by_category[category]
		return cached if typeof(cached) == TYPE_DICTIONARY else {}

	var entry = _map_overlay_entries_by_category.get(category, {})
	if typeof(entry) != TYPE_DICTIONARY:
		return {}

	var overlay_data := _load_json_object(_resource_path(String(entry.get("path", ""))), "generated map overlay")
	_map_overlay_data_by_category[category] = overlay_data
	return overlay_data


func get_map_overlay_records_for_map(map_id: String, category: String = DEFAULT_MAP_OVERLAY_CATEGORY) -> Dictionary:
	var overlay_data := get_map_overlays_data(category)
	if overlay_data.is_empty():
		return {}

	var maps = overlay_data.get("maps", {})
	if typeof(maps) != TYPE_DICTIONARY:
		return {}

	var records = maps.get(map_id, {})
	return records if typeof(records) == TYPE_DICTIONARY else {}


func get_object_event_sprite_data(category: String = DEFAULT_OBJECT_EVENT_SPRITE_CATEGORY) -> Dictionary:
	if _object_event_sprite_data_by_category.has(category):
		var cached = _object_event_sprite_data_by_category[category]
		return cached if typeof(cached) == TYPE_DICTIONARY else {}

	var entry = _object_event_sprite_entries_by_category.get(category, {})
	if typeof(entry) != TYPE_DICTIONARY:
		return {}

	var sprite_data := _load_json_object(_resource_path(String(entry.get("path", ""))), "generated object event sprite data")
	_object_event_sprite_data_by_category[category] = sprite_data
	return sprite_data


func get_object_event_sprite_record(
	graphics_id: String,
	category: String = DEFAULT_OBJECT_EVENT_SPRITE_CATEGORY
) -> Dictionary:
	var sprite_data := get_object_event_sprite_data(category)
	if sprite_data.is_empty():
		return {}

	var sprites = sprite_data.get("sprites", {})
	if typeof(sprites) != TYPE_DICTIONARY:
		return {}

	var record = sprites.get(graphics_id, {})
	return record if typeof(record) == TYPE_DICTIONARY else {}


func get_object_event_variable_graphics_record(
	graphics_id: String,
	category: String = DEFAULT_OBJECT_EVENT_SPRITE_CATEGORY
) -> Dictionary:
	var sprite_data := get_object_event_sprite_data(category)
	if sprite_data.is_empty():
		return {}

	var variable_graphics = sprite_data.get("variable_graphics", {})
	if typeof(variable_graphics) != TYPE_DICTIONARY:
		return {}

	var record = variable_graphics.get(graphics_id, {})
	return record if typeof(record) == TYPE_DICTIONARY else {}


func resolve_object_event_graphics_id(
	graphics_id: String,
	game_state: Node = null,
	category: String = DEFAULT_OBJECT_EVENT_SPRITE_CATEGORY
) -> Dictionary:
	var direct_record := get_object_event_sprite_record(graphics_id, category)
	if not direct_record.is_empty():
		return {
			"resolved": true,
			"graphics_id": graphics_id,
			"source_graphics_id": graphics_id,
			"source": "direct_object_event_graphics_id",
		}

	var variable_record := get_object_event_variable_graphics_record(graphics_id, category)
	if variable_record.is_empty():
		return {
			"resolved": false,
			"graphics_id": graphics_id,
			"source_graphics_id": graphics_id,
			"unsupported_reason": "missing_object_event_sprite_record",
		}

	var source_var := String(variable_record.get("source_var", ""))
	var var_value := 0
	var var_is_set := false
	if game_state != null and game_state.has_method("get_var") and not source_var.is_empty():
		var_value = int(game_state.get_var(source_var, 0))
		var vars = game_state.get("vars")
		var_is_set = typeof(vars) == TYPE_DICTIONARY and vars.has(source_var)

	var candidate_constants = variable_record.get("source_constant_values", {})
	var candidates = variable_record.get("known_source_candidates", [])
	if typeof(candidate_constants) == TYPE_DICTIONARY and typeof(candidates) == TYPE_ARRAY:
		for candidate in candidates:
			var candidate_id := String(candidate)
			if int(candidate_constants.get(candidate_id, -1)) == var_value:
				return {
					"resolved": true,
					"graphics_id": candidate_id,
					"source_graphics_id": graphics_id,
					"source_var": source_var,
					"source_var_value": var_value,
					"source": String(variable_record.get("source_resolution", "")),
				}

	return {
		"resolved": false,
		"graphics_id": graphics_id,
		"source_graphics_id": graphics_id,
		"source_var": source_var,
		"source_var_value": var_value,
		"source_var_is_set": var_is_set,
		"unsupported_reason": "object_event_var_graphics_unresolved",
		"source_trace": variable_record.get("source_trace", []),
	}


func get_pokemon_data(category: String = "species") -> Dictionary:
	if _pokemon_data_by_category.has(category):
		var cached = _pokemon_data_by_category[category]
		return cached if typeof(cached) == TYPE_DICTIONARY else {}

	var entry = _pokemon_entries_by_category.get(category, {})
	if typeof(entry) != TYPE_DICTIONARY:
		return {}

	var pokemon_data := _load_json_object(_resource_path(String(entry.get("path", ""))), "generated pokemon")
	_pokemon_data_by_category[category] = pokemon_data
	return pokemon_data


func get_species_data() -> Dictionary:
	return get_pokemon_data("species")


func get_pokemon_battle_sprites_data() -> Dictionary:
	return get_pokemon_data(DEFAULT_POKEMON_BATTLE_SPRITE_CATEGORY)


func get_species_record(species_id_or_symbol) -> Dictionary:
	if typeof(species_id_or_symbol) == TYPE_INT:
		return get_species_record_by_id(int(species_id_or_symbol))
	if typeof(species_id_or_symbol) == TYPE_FLOAT:
		return get_species_record_by_id(int(species_id_or_symbol))

	var key := String(species_id_or_symbol)
	if key.is_valid_int():
		return get_species_record_by_id(int(key))
	return get_species_record_by_symbol(key)


func get_species_record_by_symbol(species_symbol: String) -> Dictionary:
	_ensure_species_indexes()
	var normalized := _normalize_species_symbol(species_symbol)
	var record = _species_records_by_symbol.get(normalized, {})
	return record if typeof(record) == TYPE_DICTIONARY else {}


func get_species_record_by_id(species_id: int) -> Dictionary:
	_ensure_species_indexes()
	var record = _species_records_by_id.get(species_id, {})
	return record if typeof(record) == TYPE_DICTIONARY else {}


func get_pokemon_battle_sprite_record(species_id_or_symbol) -> Dictionary:
	if typeof(species_id_or_symbol) == TYPE_INT:
		return get_pokemon_battle_sprite_record_by_id(int(species_id_or_symbol))
	if typeof(species_id_or_symbol) == TYPE_FLOAT:
		return get_pokemon_battle_sprite_record_by_id(int(species_id_or_symbol))

	var key := String(species_id_or_symbol)
	if key.is_valid_int():
		return get_pokemon_battle_sprite_record_by_id(int(key))
	return get_pokemon_battle_sprite_record_by_symbol(key)


func get_pokemon_battle_sprite_record_by_symbol(species_symbol: String) -> Dictionary:
	_ensure_pokemon_battle_sprite_indexes()
	var normalized := _normalize_species_symbol(species_symbol)
	var record = _pokemon_battle_sprite_records_by_symbol.get(normalized, {})
	return record if typeof(record) == TYPE_DICTIONARY else {}


func get_pokemon_battle_sprite_record_by_id(species_id: int) -> Dictionary:
	_ensure_pokemon_battle_sprite_indexes()
	var record = _pokemon_battle_sprite_records_by_id.get(species_id, {})
	return record if typeof(record) == TYPE_DICTIONARY else {}


func get_moves_data() -> Dictionary:
	return get_pokemon_data("moves")


func get_types_data() -> Dictionary:
	return get_pokemon_data("types")


func get_move_record(move_id_or_symbol) -> Dictionary:
	if typeof(move_id_or_symbol) == TYPE_INT:
		return get_move_record_by_id(int(move_id_or_symbol))
	if typeof(move_id_or_symbol) == TYPE_FLOAT:
		return get_move_record_by_id(int(move_id_or_symbol))

	var key := String(move_id_or_symbol)
	if key.is_valid_int():
		return get_move_record_by_id(int(key))
	return get_move_record_by_symbol(key)


func get_move_record_by_symbol(move_symbol: String) -> Dictionary:
	_ensure_move_indexes()
	var normalized := move_symbol
	if not normalized.begins_with("MOVE_"):
		normalized = "MOVE_%s" % normalized.to_upper()
	var record = _move_records_by_symbol.get(normalized, {})
	return record if typeof(record) == TYPE_DICTIONARY else {}


func get_move_record_by_id(move_id: int) -> Dictionary:
	_ensure_move_indexes()
	var record = _move_records_by_id.get(move_id, {})
	return record if typeof(record) == TYPE_DICTIONARY else {}


func get_type_record(type_id_or_symbol) -> Dictionary:
	if typeof(type_id_or_symbol) == TYPE_INT:
		return get_type_record_by_id(int(type_id_or_symbol))
	if typeof(type_id_or_symbol) == TYPE_FLOAT:
		return get_type_record_by_id(int(type_id_or_symbol))

	var key := String(type_id_or_symbol)
	if key.is_valid_int():
		return get_type_record_by_id(int(key))
	return get_type_record_by_symbol(key)


func get_type_record_by_symbol(type_symbol: String) -> Dictionary:
	_ensure_type_indexes()
	var normalized := type_symbol
	if not normalized.begins_with("TYPE_"):
		normalized = "TYPE_%s" % normalized.to_upper()
	var record = _type_records_by_symbol.get(normalized, {})
	return record if typeof(record) == TYPE_DICTIONARY else {}


func get_type_record_by_id(type_id: int) -> Dictionary:
	_ensure_type_indexes()
	var record = _type_records_by_id.get(type_id, {})
	return record if typeof(record) == TYPE_DICTIONARY else {}


func get_abilities_data() -> Dictionary:
	return get_pokemon_data("abilities")


func get_ability_record(ability_id_or_symbol) -> Dictionary:
	if typeof(ability_id_or_symbol) == TYPE_INT:
		return get_ability_record_by_id(int(ability_id_or_symbol))
	if typeof(ability_id_or_symbol) == TYPE_FLOAT:
		return get_ability_record_by_id(int(ability_id_or_symbol))

	var key := String(ability_id_or_symbol)
	if key.is_valid_int():
		return get_ability_record_by_id(int(key))
	return get_ability_record_by_symbol(key)


func get_ability_record_by_symbol(ability_symbol: String) -> Dictionary:
	_ensure_ability_indexes()
	var normalized := ability_symbol
	if not normalized.begins_with("ABILITY_"):
		normalized = "ABILITY_%s" % normalized.to_upper()
	var record = _ability_records_by_symbol.get(normalized, {})
	return record if typeof(record) == TYPE_DICTIONARY else {}


func get_ability_record_by_id(ability_id: int) -> Dictionary:
	_ensure_ability_indexes()
	var record = _ability_records_by_id.get(ability_id, {})
	return record if typeof(record) == TYPE_DICTIONARY else {}


func get_items_data() -> Dictionary:
	return get_pokemon_data("items")


func get_item_record(item_id_or_symbol) -> Dictionary:
	if typeof(item_id_or_symbol) == TYPE_INT:
		return get_item_record_by_id(int(item_id_or_symbol))
	if typeof(item_id_or_symbol) == TYPE_FLOAT:
		return get_item_record_by_id(int(item_id_or_symbol))

	var key := String(item_id_or_symbol)
	if key.is_valid_int():
		return get_item_record_by_id(int(key))
	return get_item_record_by_symbol(key)


func get_item_record_by_symbol(item_symbol: String) -> Dictionary:
	_ensure_item_indexes()
	var normalized := item_symbol
	if not normalized.begins_with("ITEM_"):
		normalized = "ITEM_%s" % normalized.to_upper()
	var record = _item_records_by_symbol.get(normalized, {})
	return record if typeof(record) == TYPE_DICTIONARY else {}


func get_item_record_by_id(item_id: int) -> Dictionary:
	_ensure_item_indexes()
	var record = _item_records_by_id.get(item_id, {})
	return record if typeof(record) == TYPE_DICTIONARY else {}


func get_wild_encounters_data() -> Dictionary:
	return get_pokemon_data("wild_encounters")


func get_wild_encounter_record(label_or_id: String) -> Dictionary:
	_ensure_wild_encounter_indexes()
	var record = _wild_encounter_records_by_label.get(label_or_id, {})
	return record if typeof(record) == TYPE_DICTIONARY else {}


func get_wild_encounter_records_for_map(map_symbol: String) -> Array:
	_ensure_wild_encounter_indexes()
	var normalized := _normalize_map_symbol(map_symbol)
	var records = _wild_encounter_records_by_map.get(normalized, [])
	return records if typeof(records) == TYPE_ARRAY else []


func get_wild_encounter_record_for_map(map_symbol: String, index: int = 0) -> Dictionary:
	var records := get_wild_encounter_records_for_map(map_symbol)
	if index < 0 or index >= records.size():
		return {}
	var record = records[index]
	return record if typeof(record) == TYPE_DICTIONARY else {}


func get_trainers_data() -> Dictionary:
	return get_pokemon_data("trainers")


func get_natures_data() -> Dictionary:
	return get_pokemon_data("natures")


func get_learnsets_data() -> Dictionary:
	return get_pokemon_data("learnsets")


func get_evolutions_data() -> Dictionary:
	return get_pokemon_data("evolutions")


func get_nature_record(nature_id_or_symbol) -> Dictionary:
	if typeof(nature_id_or_symbol) == TYPE_INT:
		return get_nature_record_by_id(int(nature_id_or_symbol))
	if typeof(nature_id_or_symbol) == TYPE_FLOAT:
		return get_nature_record_by_id(int(nature_id_or_symbol))

	var key := String(nature_id_or_symbol)
	if key.is_valid_int():
		return get_nature_record_by_id(int(key))
	return get_nature_record_by_symbol(key)


func get_nature_record_by_symbol(nature_symbol: String) -> Dictionary:
	_ensure_nature_indexes()
	var normalized := nature_symbol
	if not normalized.begins_with("NATURE_"):
		normalized = "NATURE_%s" % normalized.to_upper()
	var record = _nature_records_by_symbol.get(normalized, {})
	return record if typeof(record) == TYPE_DICTIONARY else {}


func get_nature_record_by_id(nature_id: int) -> Dictionary:
	_ensure_nature_indexes()
	var record = _nature_records_by_id.get(nature_id, {})
	return record if typeof(record) == TYPE_DICTIONARY else {}


func get_level_up_learnset_record(learnset_label: String) -> Dictionary:
	_ensure_learnset_indexes()
	var record = _learnset_records_by_label.get(learnset_label, {})
	return record if typeof(record) == TYPE_DICTIONARY else {}


func get_level_up_learnset_for_species(species_id_or_symbol) -> Dictionary:
	var species_record := get_species_record(species_id_or_symbol)
	if species_record.is_empty():
		return {}
	var learnset_label := String(species_record.get("level_up_learnset", ""))
	if learnset_label.is_empty():
		var source_references = species_record.get("source_references", {})
		if typeof(source_references) == TYPE_DICTIONARY:
			learnset_label = String(source_references.get("level_up_learnset", ""))
	if learnset_label.is_empty():
		return {}
	return get_level_up_learnset_record(learnset_label)


func get_evolution_record(species_id_or_symbol) -> Dictionary:
	if typeof(species_id_or_symbol) == TYPE_INT:
		return get_evolution_record_by_species_id(int(species_id_or_symbol))
	if typeof(species_id_or_symbol) == TYPE_FLOAT:
		return get_evolution_record_by_species_id(int(species_id_or_symbol))

	var key := String(species_id_or_symbol)
	if key.is_valid_int():
		return get_evolution_record_by_species_id(int(key))
	return get_evolution_record_by_species_symbol(key)


func get_evolution_record_by_species_symbol(species_symbol: String) -> Dictionary:
	_ensure_evolution_indexes()
	var normalized := _normalize_species_symbol(species_symbol)
	var record = _evolution_records_by_species_symbol.get(normalized, {})
	return record if typeof(record) == TYPE_DICTIONARY else {}


func get_evolution_record_by_species_id(species_id: int) -> Dictionary:
	_ensure_evolution_indexes()
	var record = _evolution_records_by_species_id.get(species_id, {})
	return record if typeof(record) == TYPE_DICTIONARY else {}


func get_evolutions_for_species(species_id_or_symbol) -> Array:
	var record := get_evolution_record(species_id_or_symbol)
	if record.is_empty():
		return []
	var evolutions = record.get("evolutions", [])
	return evolutions if typeof(evolutions) == TYPE_ARRAY else []


func get_pre_evolution_records_for_species(species_id_or_symbol) -> Array:
	if typeof(species_id_or_symbol) == TYPE_INT:
		return get_pre_evolution_records_for_species_id(int(species_id_or_symbol))
	if typeof(species_id_or_symbol) == TYPE_FLOAT:
		return get_pre_evolution_records_for_species_id(int(species_id_or_symbol))

	var key := String(species_id_or_symbol)
	if key.is_valid_int():
		return get_pre_evolution_records_for_species_id(int(key))
	return get_pre_evolution_records_for_species_symbol(key)


func get_pre_evolution_records_for_species_symbol(species_symbol: String) -> Array:
	_ensure_evolution_indexes()
	var normalized := _normalize_species_symbol(species_symbol)
	var records = _pre_evolution_records_by_target_symbol.get(normalized, [])
	return records if typeof(records) == TYPE_ARRAY else []


func get_pre_evolution_records_for_species_id(species_id: int) -> Array:
	_ensure_evolution_indexes()
	var records = _pre_evolution_records_by_target_id.get(species_id, [])
	return records if typeof(records) == TYPE_ARRAY else []


func get_trainer_record(trainer_id_or_symbol) -> Dictionary:
	if typeof(trainer_id_or_symbol) == TYPE_INT:
		return get_trainer_record_by_id(int(trainer_id_or_symbol))
	if typeof(trainer_id_or_symbol) == TYPE_FLOAT:
		return get_trainer_record_by_id(int(trainer_id_or_symbol))

	var key := String(trainer_id_or_symbol)
	if key.is_valid_int():
		return get_trainer_record_by_id(int(key))
	return get_trainer_record_by_symbol(key)


func get_trainer_record_by_symbol(trainer_symbol: String) -> Dictionary:
	_ensure_trainer_indexes()
	var normalized := trainer_symbol
	if not normalized.begins_with("TRAINER_"):
		normalized = "TRAINER_%s" % normalized.to_upper()
	var record = _trainer_records_by_symbol.get(normalized, {})
	return record if typeof(record) == TYPE_DICTIONARY else {}


func get_trainer_record_by_id(trainer_id: int) -> Dictionary:
	_ensure_trainer_indexes()
	var record = _trainer_records_by_id.get(trainer_id, {})
	return record if typeof(record) == TYPE_DICTIONARY else {}


func get_map_name(map_id: String) -> String:
	var entry := _map_entry_for_id(map_id)
	if not entry.is_empty():
		return String(entry.get("name", FIRST_SLICE_MAP_NAME))
	if map_id == FIRST_SLICE_MAP_ID:
		return get_start_map_name()
	return map_id


func get_map_size(map_id: String) -> Vector2i:
	var entry := _map_entry_for_id(map_id)
	if not entry.is_empty():
		return Vector2i(
			int(entry.get("width", FIRST_SLICE_MAP_SIZE.x)),
			int(entry.get("height", FIRST_SLICE_MAP_SIZE.y))
		)

	var map_data := get_map_data(map_id)
	if not map_data.is_empty():
		var layout_info = map_data.get("layout", {})
		if typeof(layout_info) == TYPE_DICTIONARY:
			return Vector2i(
				int(layout_info.get("width", FIRST_SLICE_MAP_SIZE.x)),
				int(layout_info.get("height", FIRST_SLICE_MAP_SIZE.y))
			)
	return FIRST_SLICE_MAP_SIZE if map_id == FIRST_SLICE_MAP_ID else Vector2i.ZERO


func get_map_id_for_name(map_name: String) -> String:
	var entry = _map_entries_by_name.get(map_name, {})
	if typeof(entry) == TYPE_DICTIONARY:
		return String(entry.get("id", ""))
	return ""


func _load_json_object(path: String, label: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("Could not open %s: %s" % [label, path])
		return {}

	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("%s is not a JSON object: %s" % [label.capitalize(), path])
		return {}

	return parsed


func _index_manifest() -> void:
	_map_entries_by_id = {}
	_map_entries_by_name = {}
	_tileset_entries_by_map_name = {}
	_script_entries = []
	_script_entries_by_map_name = {}
	_script_data_by_path = {}
	_text_entries_by_category = {}
	_text_data_by_category = {}
	_pokemon_entries_by_category = {}
	_pokemon_data_by_category = {}
	_battle_entries_by_category = {}
	_battle_data_by_category = {}
	_map_overlay_entries_by_category = {}
	_map_overlay_data_by_category = {}
	_object_event_sprite_entries_by_category = {}
	_object_event_sprite_data_by_category = {}
	_species_records_by_symbol = {}
	_species_records_by_id = {}
	_pokemon_battle_sprite_records_by_symbol = {}
	_pokemon_battle_sprite_records_by_id = {}
	_trainer_battle_sprite_records_by_symbol = {}
	_trainer_battle_sprite_records_by_id = {}
	_trainer_front_sprite_records_by_symbol = {}
	_trainer_front_sprite_records_by_id = {}
	_trainer_back_sprite_records_by_symbol = {}
	_trainer_back_sprite_records_by_id = {}
	_move_records_by_symbol = {}
	_move_records_by_id = {}
	_type_records_by_symbol = {}
	_type_records_by_id = {}
	_ability_records_by_symbol = {}
	_ability_records_by_id = {}
	_item_records_by_symbol = {}
	_item_records_by_id = {}
	_wild_encounter_records_by_label = {}
	_wild_encounter_records_by_map = {}
	_trainer_records_by_symbol = {}
	_trainer_records_by_id = {}
	_learnset_records_by_label = {}
	_nature_records_by_symbol = {}
	_nature_records_by_id = {}
	_evolution_records_by_species_symbol = {}
	_evolution_records_by_species_id = {}
	_pre_evolution_records_by_target_symbol = {}
	_pre_evolution_records_by_target_id = {}
	_battle_string_records_by_symbol = {}
	_battle_string_records_by_id = {}
	_battle_text_records_by_label = {}
	_battle_script_records_by_label = {}
	_battle_script_commands_by_opcode = {}
	_battle_script_commands_by_macro = {}
	_battle_move_effect_records_by_symbol = {}
	_battle_move_effect_records_by_id = {}
	_battle_environment_records_by_symbol = {}
	_battle_environment_records_by_id = {}
	_battle_environment_by_map_scene = {}
	_battle_transition_records_by_symbol = {}
	_battle_transition_records_by_id = {}
	if _manifest_data.is_empty():
		return

	var maps = _manifest_data.get("maps", [])
	if typeof(maps) == TYPE_ARRAY:
		for entry in maps:
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			var map_id := String(entry.get("id", ""))
			var map_name := String(entry.get("name", ""))
			if not map_id.is_empty():
				_map_entries_by_id[map_id] = entry
			if not map_name.is_empty():
				_map_entries_by_name[map_name] = entry

	var tilesets = _manifest_data.get("tilesets", [])
	if typeof(tilesets) == TYPE_ARRAY:
		for entry in tilesets:
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			var map_name := String(entry.get("map", ""))
			if not map_name.is_empty():
				_tileset_entries_by_map_name[map_name] = entry

	var scripts = _manifest_data.get("scripts", [])
	if typeof(scripts) == TYPE_ARRAY:
		for entry in scripts:
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			_script_entries.append(entry)
			var map_name := String(entry.get("map", ""))
			if not map_name.is_empty():
				_script_entries_by_map_name[map_name] = entry

	var texts = _manifest_data.get("texts", [])
	if typeof(texts) == TYPE_ARRAY:
		for entry in texts:
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			var category := String(entry.get("category", ""))
			if not category.is_empty():
				_text_entries_by_category[category] = entry

	var pokemon = _manifest_data.get("pokemon", [])
	if typeof(pokemon) == TYPE_ARRAY:
		for entry in pokemon:
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			var category := String(entry.get("category", ""))
			if not category.is_empty():
				_pokemon_entries_by_category[category] = entry

	var battle = _manifest_data.get("battle", [])
	if typeof(battle) == TYPE_ARRAY:
		for entry in battle:
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			var category := String(entry.get("category", ""))
			if not category.is_empty():
				_battle_entries_by_category[category] = entry

	var map_overlays = _manifest_data.get("map_overlays", [])
	if typeof(map_overlays) == TYPE_ARRAY:
		for entry in map_overlays:
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			var category := String(entry.get("category", ""))
			if not category.is_empty():
				_map_overlay_entries_by_category[category] = entry

	var object_event_sprites = _manifest_data.get("object_event_sprites", [])
	if typeof(object_event_sprites) == TYPE_ARRAY:
		for entry in object_event_sprites:
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			var category := String(entry.get("category", ""))
			if not category.is_empty():
				_object_event_sprite_entries_by_category[category] = entry


func _map_entry_for_id(map_id: String) -> Dictionary:
	var entry = _map_entries_by_id.get(map_id, {})
	return entry if typeof(entry) == TYPE_DICTIONARY else {}


func _get_record_from_script_entries(label: String, category: String) -> Dictionary:
	for entry in _script_entries:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var script_data := _script_data_for_entry(entry)
		var records = script_data.get(category, {})
		if typeof(records) != TYPE_DICTIONARY:
			continue
		var record = records.get(label, {})
		if typeof(record) == TYPE_DICTIONARY and not record.is_empty():
			return record

	if _script_entries.is_empty() and not _start_script_data.is_empty():
		var start_records = _start_script_data.get(category, {})
		if typeof(start_records) == TYPE_DICTIONARY:
			var start_record = start_records.get(label, {})
			if typeof(start_record) == TYPE_DICTIONARY:
				return start_record
	return {}


func _script_data_for_entry(entry: Dictionary) -> Dictionary:
	var path := String(entry.get("path", ""))
	if path.is_empty():
		return {}
	if _script_data_by_path.has(path):
		var cached = _script_data_by_path[path]
		return cached if typeof(cached) == TYPE_DICTIONARY else {}

	var script_data := _load_json_object(_resource_path(path), "generated script")
	_script_data_by_path[path] = script_data
	return script_data


func _ensure_battle_script_indexes() -> void:
	if (
		not _battle_script_records_by_label.is_empty()
		or not _battle_script_commands_by_opcode.is_empty()
		or not _battle_script_commands_by_macro.is_empty()
	):
		return

	var battle_scripts := get_battle_scripts_data()
	if battle_scripts.is_empty():
		return

	var scripts = battle_scripts.get("scripts", {})
	if typeof(scripts) == TYPE_DICTIONARY:
		for label in scripts.keys():
			var record = scripts[label]
			if typeof(record) != TYPE_DICTIONARY:
				continue
			var script_label := String(record.get("label", label))
			if not script_label.is_empty():
				_battle_script_records_by_label[script_label] = record

	var commands = battle_scripts.get("commands", {})
	if typeof(commands) == TYPE_DICTIONARY:
		for symbol in commands.keys():
			var command_record = commands[symbol]
			if typeof(command_record) != TYPE_DICTIONARY:
				continue
			var opcode_symbol := String(command_record.get("symbol", symbol))
			if not opcode_symbol.is_empty():
				_battle_script_commands_by_opcode[opcode_symbol] = command_record
			if command_record.has("opcode") and command_record.get("opcode") != null:
				_battle_script_commands_by_opcode[int(command_record.get("opcode"))] = command_record

	var command_macros = battle_scripts.get("command_macros", {})
	if typeof(command_macros) == TYPE_DICTIONARY:
		for macro_name in command_macros.keys():
			var macro_record = command_macros[macro_name]
			if typeof(macro_record) != TYPE_DICTIONARY:
				continue
			var source_macro := String(macro_record.get("macro", macro_name))
			if not source_macro.is_empty():
				_battle_script_commands_by_macro[source_macro] = macro_record


func _ensure_battle_move_effect_indexes() -> void:
	if not _battle_move_effect_records_by_symbol.is_empty() or not _battle_move_effect_records_by_id.is_empty():
		return

	var move_effects := get_battle_move_effects_data()
	if move_effects.is_empty():
		return

	var effects = move_effects.get("effects", {})
	if typeof(effects) != TYPE_DICTIONARY:
		return

	for symbol in effects.keys():
		var record = effects[symbol]
		if typeof(record) != TYPE_DICTIONARY:
			continue
		var effect_symbol := String(record.get("symbol", symbol))
		if not effect_symbol.is_empty():
			_battle_move_effect_records_by_symbol[effect_symbol] = record
		if record.has("id") and record.get("id") != null:
			_battle_move_effect_records_by_id[int(record.get("id"))] = record


func _ensure_battle_environment_indexes() -> void:
	if not _battle_environment_records_by_symbol.is_empty() or not _battle_environment_records_by_id.is_empty():
		return

	var environments_data := get_battle_environments_data()
	if environments_data.is_empty():
		return

	var environments = environments_data.get("environments", {})
	if typeof(environments) == TYPE_DICTIONARY:
		for symbol in environments.keys():
			var record = environments[symbol]
			if typeof(record) != TYPE_DICTIONARY:
				continue
			var environment_symbol := _normalize_battle_environment_symbol(String(record.get("symbol", symbol)))
			if not environment_symbol.is_empty():
				_battle_environment_records_by_symbol[environment_symbol] = record
			if record.has("numeric_id") and record.get("numeric_id") != null:
				_battle_environment_records_by_id[int(record.get("numeric_id"))] = record

	var mappings = environments_data.get("map_scene_mapping", [])
	if typeof(mappings) == TYPE_ARRAY:
		for mapping in mappings:
			if typeof(mapping) != TYPE_DICTIONARY:
				continue
			var map_scene := String(mapping.get("map_scene", ""))
			var environment := String(mapping.get("battle_environment", ""))
			if not map_scene.is_empty() and not environment.is_empty():
				_battle_environment_by_map_scene[map_scene] = environment


func _ensure_battle_transition_indexes() -> void:
	if not _battle_transition_records_by_symbol.is_empty() or not _battle_transition_records_by_id.is_empty():
		return

	var transitions_data := get_battle_transitions_data()
	if transitions_data.is_empty():
		return

	var transitions = transitions_data.get("transitions", {})
	if typeof(transitions) != TYPE_DICTIONARY:
		return

	for symbol in transitions.keys():
		var record = transitions[symbol]
		if typeof(record) != TYPE_DICTIONARY:
			continue
		var transition_symbol := _normalize_battle_transition_symbol(String(record.get("symbol", symbol)))
		if not transition_symbol.is_empty():
			_battle_transition_records_by_symbol[transition_symbol] = record
		if record.has("numeric_id") and record.get("numeric_id") != null:
			_battle_transition_records_by_id[int(record.get("numeric_id"))] = record


func _ensure_battle_string_indexes() -> void:
	if (
		not _battle_string_records_by_symbol.is_empty()
		or not _battle_string_records_by_id.is_empty()
		or not _battle_text_records_by_label.is_empty()
	):
		return

	var battle_data := get_battle_string_data()
	if battle_data.is_empty():
		return

	var string_ids = battle_data.get("string_ids", {})
	if typeof(string_ids) == TYPE_DICTIONARY:
		for symbol in string_ids.keys():
			var enum_record = string_ids[symbol]
			if typeof(enum_record) != TYPE_DICTIONARY:
				continue
			var enum_symbol := String(enum_record.get("symbol", symbol))
			if not enum_symbol.is_empty():
				_battle_string_records_by_symbol[enum_symbol] = enum_record
			if enum_record.has("id") and enum_record.get("id") != null:
				_battle_string_records_by_id[int(enum_record.get("id"))] = enum_record

	var table_records = battle_data.get("battle_strings_table", {})
	if typeof(table_records) == TYPE_DICTIONARY:
		for symbol in table_records.keys():
			var record = table_records[symbol]
			if typeof(record) != TYPE_DICTIONARY:
				continue
			var battle_symbol := String(record.get("symbol", symbol))
			if not battle_symbol.is_empty():
				_battle_string_records_by_symbol[battle_symbol] = record
			if record.has("id") and record.get("id") != null:
				_battle_string_records_by_id[int(record.get("id"))] = record

	var text_records = battle_data.get("texts", {})
	if typeof(text_records) == TYPE_DICTIONARY:
		for label in text_records.keys():
			var text_record = text_records[label]
			if typeof(text_record) != TYPE_DICTIONARY:
				continue
			var text_label := String(text_record.get("label", label))
			if not text_label.is_empty():
				_battle_text_records_by_label[text_label] = text_record


func _ensure_species_indexes() -> void:
	if not _species_records_by_symbol.is_empty() or not _species_records_by_id.is_empty():
		return

	var species_data := get_species_data()
	var species_records = species_data.get("species", {})
	if typeof(species_records) != TYPE_DICTIONARY:
		return

	for symbol in species_records.keys():
		var record = species_records[symbol]
		if typeof(record) != TYPE_DICTIONARY:
			continue
		var species_symbol := String(record.get("symbol", symbol))
		if not species_symbol.is_empty():
			_species_records_by_symbol[species_symbol] = record
		if record.has("id") and record.get("id") != null:
			_species_records_by_id[int(record.get("id"))] = record


func _ensure_pokemon_battle_sprite_indexes() -> void:
	if not _pokemon_battle_sprite_records_by_symbol.is_empty() or not _pokemon_battle_sprite_records_by_id.is_empty():
		return

	var battle_sprite_data := get_pokemon_battle_sprites_data()
	var sprite_records = battle_sprite_data.get("sprites", {})
	if typeof(sprite_records) != TYPE_DICTIONARY:
		return

	for symbol in sprite_records.keys():
		var record = sprite_records[symbol]
		if typeof(record) != TYPE_DICTIONARY:
			continue
		var species_symbol := String(record.get("species_symbol", symbol))
		species_symbol = _normalize_species_symbol(species_symbol)
		if not species_symbol.is_empty():
			_pokemon_battle_sprite_records_by_symbol[species_symbol] = record
		if record.has("numeric_id") and record.get("numeric_id") != null:
			_pokemon_battle_sprite_records_by_id[int(record.get("numeric_id"))] = record


func _ensure_trainer_battle_sprite_indexes() -> void:
	if not _trainer_battle_sprite_records_by_symbol.is_empty() or not _trainer_battle_sprite_records_by_id.is_empty():
		return

	var trainer_sprite_data := get_trainer_sprites_data()
	if trainer_sprite_data.is_empty():
		return

	var trainer_records = trainer_sprite_data.get("trainers", {})
	if typeof(trainer_records) == TYPE_DICTIONARY:
		for symbol in trainer_records.keys():
			var record = trainer_records[symbol]
			if typeof(record) != TYPE_DICTIONARY:
				continue
			var trainer_symbol := _normalize_trainer_symbol(String(record.get("trainer_symbol", symbol)))
			if not trainer_symbol.is_empty():
				_trainer_battle_sprite_records_by_symbol[trainer_symbol] = record
			if record.has("numeric_id") and record.get("numeric_id") != null:
				_trainer_battle_sprite_records_by_id[int(record.get("numeric_id"))] = record

	var front_records = trainer_sprite_data.get("front_sprites", {})
	if typeof(front_records) == TYPE_DICTIONARY:
		for symbol in front_records.keys():
			var record = front_records[symbol]
			if typeof(record) != TYPE_DICTIONARY:
				continue
			var pic_symbol := _normalize_trainer_front_pic_symbol(String(record.get("pic_symbol", symbol)))
			if not pic_symbol.is_empty():
				_trainer_front_sprite_records_by_symbol[pic_symbol] = record
			if record.has("numeric_id") and record.get("numeric_id") != null:
				_trainer_front_sprite_records_by_id[int(record.get("numeric_id"))] = record

	var back_records = trainer_sprite_data.get("back_sprites", {})
	if typeof(back_records) == TYPE_DICTIONARY:
		for symbol in back_records.keys():
			var record = back_records[symbol]
			if typeof(record) != TYPE_DICTIONARY:
				continue
			var pic_symbol := _normalize_trainer_back_pic_symbol(String(record.get("pic_symbol", symbol)))
			if not pic_symbol.is_empty():
				_trainer_back_sprite_records_by_symbol[pic_symbol] = record
			if record.has("numeric_id") and record.get("numeric_id") != null:
				_trainer_back_sprite_records_by_id[int(record.get("numeric_id"))] = record


func _ensure_move_indexes() -> void:
	if not _move_records_by_symbol.is_empty() or not _move_records_by_id.is_empty():
		return

	var moves_data := get_moves_data()
	var move_records = moves_data.get("moves", {})
	if typeof(move_records) != TYPE_DICTIONARY:
		return

	for symbol in move_records.keys():
		var record = move_records[symbol]
		if typeof(record) != TYPE_DICTIONARY:
			continue
		var move_symbol := String(record.get("symbol", symbol))
		if not move_symbol.is_empty():
			_move_records_by_symbol[move_symbol] = record
		if record.has("id") and record.get("id") != null:
			_move_records_by_id[int(record.get("id"))] = record


func _ensure_type_indexes() -> void:
	if not _type_records_by_symbol.is_empty() or not _type_records_by_id.is_empty():
		return

	var types_data := get_types_data()
	var type_records = types_data.get("types", {})
	if typeof(type_records) != TYPE_DICTIONARY:
		return

	for symbol in type_records.keys():
		var record = type_records[symbol]
		if typeof(record) != TYPE_DICTIONARY:
			continue
		var type_symbol := String(record.get("symbol", symbol))
		if not type_symbol.is_empty():
			_type_records_by_symbol[type_symbol] = record
		if record.has("id") and record.get("id") != null:
			_type_records_by_id[int(record.get("id"))] = record


func _ensure_ability_indexes() -> void:
	if not _ability_records_by_symbol.is_empty() or not _ability_records_by_id.is_empty():
		return

	var abilities_data := get_abilities_data()
	var ability_records = abilities_data.get("abilities", {})
	if typeof(ability_records) != TYPE_DICTIONARY:
		return

	for symbol in ability_records.keys():
		var record = ability_records[symbol]
		if typeof(record) != TYPE_DICTIONARY:
			continue
		var ability_symbol := String(record.get("symbol", symbol))
		if not ability_symbol.is_empty():
			_ability_records_by_symbol[ability_symbol] = record
		if record.has("id") and record.get("id") != null:
			_ability_records_by_id[int(record.get("id"))] = record


func _ensure_item_indexes() -> void:
	if not _item_records_by_symbol.is_empty() or not _item_records_by_id.is_empty():
		return

	var items_data := get_items_data()
	var item_records = items_data.get("items", {})
	if typeof(item_records) != TYPE_DICTIONARY:
		return

	for symbol in item_records.keys():
		var record = item_records[symbol]
		if typeof(record) != TYPE_DICTIONARY:
			continue
		var item_symbol := String(record.get("symbol", symbol))
		if not item_symbol.is_empty():
			_item_records_by_symbol[item_symbol] = record
		if record.has("id") and record.get("id") != null:
			_item_records_by_id[int(record.get("id"))] = record


func _ensure_wild_encounter_indexes() -> void:
	if not _wild_encounter_records_by_label.is_empty() or not _wild_encounter_records_by_map.is_empty():
		return

	var wild_data := get_wild_encounters_data()
	var records = wild_data.get("encounters", [])
	if typeof(records) != TYPE_ARRAY:
		return

	for record in records:
		if typeof(record) != TYPE_DICTIONARY:
			continue
		var record_id := String(record.get("id", ""))
		var label := String(record.get("label", ""))
		var shared_label := String(record.get("shared_label", ""))
		for key in [record_id, label, shared_label]:
			var lookup_key := str(key)
			if not lookup_key.is_empty() and not _wild_encounter_records_by_label.has(lookup_key):
				_wild_encounter_records_by_label[lookup_key] = record

		var map_info = record.get("map", {})
		if typeof(map_info) != TYPE_DICTIONARY:
			continue
		var map_symbol_value = map_info.get("symbol", "")
		if map_symbol_value == null:
			continue
		var map_symbol := str(map_symbol_value)
		if map_symbol.is_empty():
			continue
		if not _wild_encounter_records_by_map.has(map_symbol):
			_wild_encounter_records_by_map[map_symbol] = []
		var map_records = _wild_encounter_records_by_map[map_symbol]
		if typeof(map_records) == TYPE_ARRAY:
			map_records.append(record)


func _ensure_trainer_indexes() -> void:
	if not _trainer_records_by_symbol.is_empty() or not _trainer_records_by_id.is_empty():
		return

	var trainers_data := get_trainers_data()
	var trainer_records = trainers_data.get("trainers", {})
	if typeof(trainer_records) != TYPE_DICTIONARY:
		return

	for symbol in trainer_records.keys():
		var record = trainer_records[symbol]
		if typeof(record) != TYPE_DICTIONARY:
			continue
		var trainer_symbol := String(record.get("symbol", symbol))
		if not trainer_symbol.is_empty():
			_trainer_records_by_symbol[trainer_symbol] = record
		if record.has("id") and record.get("id") != null:
			_trainer_records_by_id[int(record.get("id"))] = record


func _ensure_learnset_indexes() -> void:
	if not _learnset_records_by_label.is_empty():
		return

	var learnsets_data := get_learnsets_data()
	var learnset_records = learnsets_data.get("learnsets", {})
	if typeof(learnset_records) != TYPE_DICTIONARY:
		return

	for label in learnset_records.keys():
		var record = learnset_records[label]
		if typeof(record) != TYPE_DICTIONARY:
			continue
		var learnset_label := String(record.get("label", label))
		if not learnset_label.is_empty():
			_learnset_records_by_label[learnset_label] = record


func _ensure_nature_indexes() -> void:
	if not _nature_records_by_symbol.is_empty() or not _nature_records_by_id.is_empty():
		return

	var natures_data := get_natures_data()
	var nature_records = natures_data.get("natures", {})
	if typeof(nature_records) != TYPE_DICTIONARY:
		return

	for symbol in nature_records.keys():
		var record = nature_records[symbol]
		if typeof(record) != TYPE_DICTIONARY:
			continue
		var nature_symbol := String(record.get("symbol", symbol))
		if not nature_symbol.is_empty():
			_nature_records_by_symbol[nature_symbol] = record
		if record.has("id") and record.get("id") != null:
			_nature_records_by_id[int(record.get("id"))] = record


func _ensure_evolution_indexes() -> void:
	if not _evolution_records_by_species_symbol.is_empty() or not _evolution_records_by_species_id.is_empty():
		return

	var evolutions_data := get_evolutions_data()
	var records = evolutions_data.get("evolutions_by_species", {})
	if typeof(records) != TYPE_DICTIONARY:
		return

	for symbol in records.keys():
		var record = records[symbol]
		if typeof(record) != TYPE_DICTIONARY:
			continue

		var species_info = record.get("species", {})
		var species_symbol := String(record.get("species_symbol", symbol))
		if species_symbol.is_empty() and typeof(species_info) == TYPE_DICTIONARY:
			species_symbol = String(species_info.get("symbol", ""))
		species_symbol = _normalize_species_symbol(species_symbol)
		if not species_symbol.is_empty():
			_evolution_records_by_species_symbol[species_symbol] = record
		if typeof(species_info) == TYPE_DICTIONARY and species_info.has("value") and species_info.get("value") != null:
			_evolution_records_by_species_id[int(species_info.get("value"))] = record

		var evolutions = record.get("evolutions", [])
		if typeof(evolutions) != TYPE_ARRAY:
			continue
		for evolution in evolutions:
			if typeof(evolution) != TYPE_DICTIONARY:
				continue
			var target = evolution.get("target_species", {})
			if typeof(target) != TYPE_DICTIONARY:
				continue
			var target_symbol := _normalize_species_symbol(String(target.get("symbol", "")))
			var pre_record := {
				"source_species": species_info,
				"source_species_symbol": species_symbol,
				"source_record": record,
				"evolution": evolution,
			}
			if not target_symbol.is_empty():
				if not _pre_evolution_records_by_target_symbol.has(target_symbol):
					_pre_evolution_records_by_target_symbol[target_symbol] = []
				var symbol_records = _pre_evolution_records_by_target_symbol[target_symbol]
				if typeof(symbol_records) == TYPE_ARRAY:
					symbol_records.append(pre_record)
			if target.has("value") and target.get("value") != null:
				var target_id := int(target.get("value"))
				if not _pre_evolution_records_by_target_id.has(target_id):
					_pre_evolution_records_by_target_id[target_id] = []
				var id_records = _pre_evolution_records_by_target_id[target_id]
				if typeof(id_records) == TYPE_ARRAY:
					id_records.append(pre_record)


func _normalize_species_symbol(species_symbol: String) -> String:
	var normalized := species_symbol
	if normalized.is_empty():
		return ""
	if not normalized.begins_with("SPECIES_"):
		normalized = "SPECIES_%s" % normalized.to_upper()
	return normalized


func _normalize_trainer_symbol(trainer_symbol: String) -> String:
	var normalized := trainer_symbol
	if normalized.is_empty():
		return ""
	if not normalized.begins_with("TRAINER_"):
		normalized = "TRAINER_%s" % normalized.to_upper()
	return normalized


func _normalize_trainer_front_pic_symbol(pic_symbol: String) -> String:
	var normalized := pic_symbol
	if normalized.is_empty():
		return ""
	if normalized.begins_with("TRAINER_PIC_FRONT_"):
		return normalized
	if normalized.begins_with("FRONT_"):
		return "TRAINER_PIC_%s" % normalized.to_upper()
	if normalized.begins_with("TRAINER_PIC_"):
		return normalized
	return "TRAINER_PIC_FRONT_%s" % normalized.to_upper()


func _normalize_trainer_back_pic_symbol(pic_symbol: String) -> String:
	var normalized := pic_symbol
	if normalized.is_empty():
		return ""
	if normalized.begins_with("TRAINER_PIC_BACK_"):
		return normalized
	if normalized.begins_with("BACK_"):
		return "TRAINER_PIC_%s" % normalized.to_upper()
	if normalized.begins_with("TRAINER_PIC_"):
		return normalized
	return "TRAINER_PIC_BACK_%s" % normalized.to_upper()


func _normalize_battle_string_symbol(battle_string_symbol: String) -> String:
	var normalized := battle_string_symbol
	if normalized.is_empty():
		return ""
	if not normalized.begins_with("STRINGID_"):
		normalized = "STRINGID_%s" % normalized.to_upper()
	return normalized


func _normalize_battle_environment_symbol(environment_symbol: String) -> String:
	var normalized := environment_symbol
	if normalized.is_empty():
		return ""
	if not normalized.begins_with("BATTLE_ENVIRONMENT_"):
		normalized = "BATTLE_ENVIRONMENT_%s" % normalized.to_upper()
	return normalized


func _normalize_battle_transition_symbol(transition_symbol: String) -> String:
	var normalized := transition_symbol
	if normalized.is_empty():
		return ""
	if not normalized.begins_with("B_TRANSITION_"):
		normalized = "B_TRANSITION_%s" % normalized.to_upper()
	return normalized


func _battle_message_context_value(context: Dictionary, token_name: String, raw_token: String):
	if context.has(token_name):
		return context.get(token_name)
	if context.has(raw_token):
		return context.get(raw_token)
	var lowercase := token_name.to_lower()
	if context.has(lowercase):
		return context.get(lowercase)
	return null


func _normalize_map_symbol(map_symbol: String) -> String:
	var normalized := map_symbol
	if normalized.is_empty():
		return ""
	if not normalized.begins_with("MAP_"):
		normalized = "MAP_%s" % normalized.to_upper()
	return normalized


func _apply_map_overlays(map_id: String, map_data: Dictionary) -> Dictionary:
	if map_data.is_empty():
		return map_data

	var overlay_records := get_map_overlay_records_for_map(map_id)
	if overlay_records.is_empty():
		return map_data

	var result := map_data.duplicate(true)
	var events = result.get("events", {})
	if typeof(events) != TYPE_DICTIONARY:
		events = {}
		result["events"] = events

	var object_events = events.get("object_events", [])
	if typeof(object_events) != TYPE_ARRAY:
		object_events = []
	events["object_events"] = object_events

	var existing_local_ids := {}
	for object_event in object_events:
		if typeof(object_event) != TYPE_DICTIONARY:
			continue
		var local_id := String(object_event.get("local_id", ""))
		if not local_id.is_empty():
			existing_local_ids[local_id] = true

	var overlay_object_events = overlay_records.get("object_events", [])
	if typeof(overlay_object_events) == TYPE_ARRAY:
		for overlay_object_event in overlay_object_events:
			if typeof(overlay_object_event) != TYPE_DICTIONARY:
				continue
			var overlay_local_id := String(overlay_object_event.get("local_id", ""))
			if not overlay_local_id.is_empty() and existing_local_ids.has(overlay_local_id):
				continue
			var merged_object_event: Dictionary = overlay_object_event.duplicate(true)
			merged_object_event["overlay"] = {
				"category": DEFAULT_MAP_OVERLAY_CATEGORY,
				"source": "data/overlays/map_debug_fixtures.json",
			}
			object_events.append(merged_object_event)
			if not overlay_local_id.is_empty():
				existing_local_ids[overlay_local_id] = true

	return result


func _map_data_with_optional_overlays(map_id: String, map_data: Dictionary, options: Dictionary = {}) -> Dictionary:
	if map_data.is_empty():
		return map_data
	var include_overlays := _debug_map_overlays_enabled
	if options.has("include_debug_overlays"):
		include_overlays = bool(options.get("include_debug_overlays", false))
	if not include_overlays:
		return map_data
	return _apply_map_overlays(map_id, map_data)


func _resource_path(project_path: String) -> String:
	var normalized := project_path.replace("\\", "/")
	if normalized.begins_with("res://"):
		return normalized
	while normalized.begins_with("/"):
		normalized = normalized.substr(1)
	return "res://%s" % normalized
