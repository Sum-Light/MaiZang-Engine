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

var import_report: Dictionary = {}
var _manifest_data: Dictionary = {}
var _map_entries_by_id: Dictionary = {}
var _map_entries_by_name: Dictionary = {}
var _tileset_entries_by_map_name: Dictionary = {}
var _script_entries_by_map_name: Dictionary = {}
var _text_entries_by_category: Dictionary = {}
var _map_data_by_id: Dictionary = {}
var _tileset_data_by_map_id: Dictionary = {}
var _script_data_by_map_id: Dictionary = {}
var _text_data_by_category: Dictionary = {}
var _start_map_data: Dictionary = {}
var _start_tileset_data: Dictionary = {}
var _start_script_data: Dictionary = {}


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


func get_start_map_data() -> Dictionary:
	return _start_map_data


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


func get_map_data(map_id: String) -> Dictionary:
	if map_id == FIRST_SLICE_MAP_ID and _map_entries_by_id.is_empty() and not _start_map_data.is_empty():
		return _start_map_data

	if _map_data_by_id.has(map_id):
		var cached = _map_data_by_id[map_id]
		return cached if typeof(cached) == TYPE_DICTIONARY else {}

	var entry := _map_entry_for_id(map_id)
	if entry.is_empty():
		return {}

	var map_data := _load_json_object(_resource_path(String(entry.get("path", ""))), "generated map")
	_map_data_by_id[map_id] = map_data
	return map_data


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

	var script_data := _load_json_object(_resource_path(String(entry.get("path", ""))), "generated script")
	_script_data_by_map_id[map_id] = script_data
	return script_data


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
	_script_entries_by_map_name = {}
	_text_entries_by_category = {}
	_text_data_by_category = {}
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


func _map_entry_for_id(map_id: String) -> Dictionary:
	var entry = _map_entries_by_id.get(map_id, {})
	return entry if typeof(entry) == TYPE_DICTIONARY else {}


func _resource_path(project_path: String) -> String:
	var normalized := project_path.replace("\\", "/")
	if normalized.begins_with("res://"):
		return normalized
	while normalized.begins_with("/"):
		normalized = normalized.substr(1)
	return "res://%s" % normalized
