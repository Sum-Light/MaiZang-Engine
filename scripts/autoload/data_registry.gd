extends Node

const TILE_SIZE := 16
const FIRST_SLICE_MAP_ID := "MAP_LITTLEROOT_TOWN"
const FIRST_SLICE_MAP_NAME := "LittlerootTown"
const FIRST_SLICE_LAYOUT_ID := "LAYOUT_LITTLEROOT_TOWN"
const FIRST_SLICE_MAP_SIZE := Vector2i(20, 20)
const FIRST_SLICE_PRIMARY_TILESET := "gTileset_General"
const FIRST_SLICE_SECONDARY_TILESET := "gTileset_Petalburg"
const GENERATED_START_MAP_PATH := "res://data/generated/maps/littleroot_town.json"

var import_report: Dictionary = {}
var _start_map_data: Dictionary = {}


func _ready() -> void:
	_load_start_map_data()


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


func get_start_block_ids() -> Array:
	return _start_map_data.get("block_ids", [])


func _load_start_map_data() -> void:
	if not FileAccess.file_exists(GENERATED_START_MAP_PATH):
		return

	var file := FileAccess.open(GENERATED_START_MAP_PATH, FileAccess.READ)
	if file == null:
		push_warning("Could not open generated map: %s" % GENERATED_START_MAP_PATH)
		return

	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("Generated map is not a JSON object: %s" % GENERATED_START_MAP_PATH)
		return

	_start_map_data = parsed
