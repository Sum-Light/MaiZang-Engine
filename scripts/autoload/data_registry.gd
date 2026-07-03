extends Node

const TILE_SIZE := 16
const FIRST_SLICE_MAP_ID := "MAP_LITTLEROOT_TOWN"
const FIRST_SLICE_MAP_NAME := "LittlerootTown"
const FIRST_SLICE_LAYOUT_ID := "LAYOUT_LITTLEROOT_TOWN"
const FIRST_SLICE_MAP_SIZE := Vector2i(20, 20)
const FIRST_SLICE_PRIMARY_TILESET := "gTileset_General"
const FIRST_SLICE_SECONDARY_TILESET := "gTileset_Petalburg"

var import_report: Dictionary = {}


func get_start_map_id() -> String:
	return FIRST_SLICE_MAP_ID


func get_start_map_name() -> String:
	return FIRST_SLICE_MAP_NAME


func get_start_map_size() -> Vector2i:
	return FIRST_SLICE_MAP_SIZE
