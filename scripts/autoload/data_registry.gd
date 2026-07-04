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
var _script_entries: Array = []
var _script_entries_by_map_name: Dictionary = {}
var _text_entries_by_category: Dictionary = {}
var _pokemon_entries_by_category: Dictionary = {}
var _map_data_by_id: Dictionary = {}
var _tileset_data_by_map_id: Dictionary = {}
var _script_data_by_map_id: Dictionary = {}
var _script_data_by_path: Dictionary = {}
var _text_data_by_category: Dictionary = {}
var _pokemon_data_by_category: Dictionary = {}
var _species_records_by_symbol: Dictionary = {}
var _species_records_by_id: Dictionary = {}
var _move_records_by_symbol: Dictionary = {}
var _move_records_by_id: Dictionary = {}
var _ability_records_by_symbol: Dictionary = {}
var _ability_records_by_id: Dictionary = {}
var _item_records_by_symbol: Dictionary = {}
var _item_records_by_id: Dictionary = {}
var _wild_encounter_records_by_label: Dictionary = {}
var _wild_encounter_records_by_map: Dictionary = {}
var _trainer_records_by_symbol: Dictionary = {}
var _trainer_records_by_id: Dictionary = {}
var _learnset_records_by_label: Dictionary = {}
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
	var normalized := species_symbol
	if not normalized.begins_with("SPECIES_"):
		normalized = "SPECIES_%s" % normalized.to_upper()
	var record = _species_records_by_symbol.get(normalized, {})
	return record if typeof(record) == TYPE_DICTIONARY else {}


func get_species_record_by_id(species_id: int) -> Dictionary:
	_ensure_species_indexes()
	var record = _species_records_by_id.get(species_id, {})
	return record if typeof(record) == TYPE_DICTIONARY else {}


func get_moves_data() -> Dictionary:
	return get_pokemon_data("moves")


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


func get_learnsets_data() -> Dictionary:
	return get_pokemon_data("learnsets")


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
	_species_records_by_symbol = {}
	_species_records_by_id = {}
	_move_records_by_symbol = {}
	_move_records_by_id = {}
	_ability_records_by_symbol = {}
	_ability_records_by_id = {}
	_item_records_by_symbol = {}
	_item_records_by_id = {}
	_wild_encounter_records_by_label = {}
	_wild_encounter_records_by_map = {}
	_trainer_records_by_symbol = {}
	_trainer_records_by_id = {}
	_learnset_records_by_label = {}
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


func _normalize_map_symbol(map_symbol: String) -> String:
	var normalized := map_symbol
	if normalized.is_empty():
		return ""
	if not normalized.begins_with("MAP_"):
		normalized = "MAP_%s" % normalized.to_upper()
	return normalized


func _resource_path(project_path: String) -> String:
	var normalized := project_path.replace("\\", "/")
	if normalized.begins_with("res://"):
		return normalized
	while normalized.begins_with("/"):
		normalized = normalized.substr(1)
	return "res://%s" % normalized
