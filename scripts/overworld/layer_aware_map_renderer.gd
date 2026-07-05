extends Node2D

const OWNER_NAME := "LayerAwareMapRenderer"
const LEGACY_RENDERER_NAME := "DebugMapPlane"
const RUNTIME_STATUS := "owner_contract_only"
const DEFAULT_TILE_SIZE := 16

const UNSUPPORTED_SOURCE_EQUIVALENT := "source_equivalent_layer_renderer_pending"
const UNSUPPORTED_FLATTENED_ATLAS := "flattened_debug_atlas_not_source_equivalent"
const UNSUPPORTED_OBJECT_DEPTH := "object_depth_interleaving_pending"
const UNSUPPORTED_DOOR_LAYER := "door_forced_covered_layer_pending"
const UNSUPPORTED_LAYER_UPDATES := "per_layer_redraw_cache_pending"

var map_size := Vector2i.ZERO
var tile_size := DEFAULT_TILE_SIZE
var _map_data: Dictionary = {}
var _tileset_data: Dictionary = {}
var _data_registry: Node = null
var _debug_fallback: Node = null
var _grid_visible := false


func configure_data_registry(data_registry: Node) -> void:
	_data_registry = data_registry
	if _debug_fallback != null and _debug_fallback.has_method("configure_data_registry"):
		_debug_fallback.configure_data_registry(data_registry)


func configure_debug_fallback(renderer: Node) -> void:
	_debug_fallback = renderer
	if _debug_fallback == null:
		return
	if _data_registry != null and _debug_fallback.has_method("configure_data_registry"):
		_debug_fallback.configure_data_registry(_data_registry)
	if not _map_data.is_empty() and _debug_fallback.has_method("configure_from_map_data"):
		_debug_fallback.configure_from_map_data(_map_data, _tileset_data)
	if _debug_fallback.has_method("set_grid_visible"):
		_debug_fallback.set_grid_visible(_grid_visible)


func configure_from_map_data(new_map_data: Dictionary, new_tileset_data: Dictionary = {}) -> void:
	_map_data = new_map_data.duplicate(true)
	_tileset_data = new_tileset_data.duplicate(true)
	tile_size = _tile_size_from_tileset(_tileset_data)
	map_size = _map_size_from_map_data(_map_data)
	clear_door_animations()
	if _debug_fallback != null and _debug_fallback.has_method("configure_from_map_data"):
		_debug_fallback.configure_from_map_data(_map_data, _tileset_data)
	queue_redraw()


func set_grid_visible(value: bool) -> void:
	_grid_visible = value
	if _debug_fallback != null and _debug_fallback.has_method("set_grid_visible"):
		_debug_fallback.set_grid_visible(value)
	queue_redraw()


func is_grid_visible() -> bool:
	if _debug_fallback != null and _debug_fallback.has_method("is_grid_visible"):
		return bool(_debug_fallback.is_grid_visible())
	return _grid_visible


func set_door_animation_frame(position: Vector2i, animation: Dictionary, frame_index: int) -> bool:
	if _debug_fallback != null and _debug_fallback.has_method("set_door_animation_frame"):
		return bool(_debug_fallback.set_door_animation_frame(position, animation, frame_index))
	return false


func clear_door_animation(position: Vector2i) -> void:
	if _debug_fallback != null and _debug_fallback.has_method("clear_door_animation"):
		_debug_fallback.clear_door_animation(position)


func clear_door_animations() -> void:
	if _debug_fallback != null and _debug_fallback.has_method("clear_door_animations"):
		_debug_fallback.clear_door_animations()


func get_door_animation_overlay_count() -> int:
	if _debug_fallback != null and _debug_fallback.has_method("get_door_animation_overlay_count"):
		return int(_debug_fallback.get_door_animation_overlay_count())
	return 0


func get_render_block_id(cell: Vector2i) -> int:
	if _debug_fallback != null and _debug_fallback.has_method("get_render_block_id"):
		return int(_debug_fallback.get_render_block_id(cell))
	return _local_block_id(cell)


func get_renderer_contract() -> Dictionary:
	return {
		"schema_version": 1,
		"owner": OWNER_NAME,
		"replaces_or_wraps": LEGACY_RENDERER_NAME,
		"runtime_status": RUNTIME_STATUS,
		"source_equivalent_for_runtime_layering": false,
		"debug_fallback_active": _debug_fallback != null,
		"debug_fallback_script": _debug_fallback_script_path(),
		"compatible_methods": [
			"configure_data_registry",
			"configure_from_map_data",
			"set_grid_visible",
			"is_grid_visible",
			"get_render_block_id",
			"set_door_animation_frame",
			"clear_door_animation",
			"clear_door_animations",
			"get_door_animation_overlay_count",
		],
		"source_trace": [
			"include/global.fieldmap.h:METATILE_LAYER_TYPE_*",
			"src/field_camera.c:DrawMetatile",
			"src/field_camera.c:CurrentMapDrawMetatileAt",
			"src/fieldmap.c:MapGridSetMetatileIdAt",
			"src/field_door.c:DrawDoorMetatileAt",
			"src/event_object_movement.c:sElevationToPriority",
			"data/generated/overworld/layer_rules_trace.json",
		],
		"required_import_inputs": get_required_import_inputs(),
		"layer_roles": get_layer_roles(),
		"layer_rule_contract": _layer_rule_contract(),
		"responsibilities": [
			"Own map presentation layer nodes or caches for bottom, middle, and top roles.",
			"Consume generated map, border, connection, metatile entry, attribute, and door animation data.",
			"Preserve the current DebugMapPlane-compatible API while the scene migrates.",
			"Route source-traced door frames into layer updates in a later implementation slice.",
			"Report non-equivalent runtime layering until bottom/middle/top drawing and sprite interleave are implemented.",
		],
		"non_responsibilities": [
			"Source parsing and generated asset production.",
			"Collision, elevation, event dispatch, flags, vars, and script execution.",
			"Object-event lifecycle state and player movement rules.",
			"Audio playback.",
		],
		"migration_steps": [
			"Wrap DebugMapPlane so Main and TransitionSequencePlayer keep their renderer API.",
			"Build or export separate bottom, middle, and top render records.",
			"Render normal, covered, and split metatile layer rules from generated entries.",
			"Interleave player and object-event presentation at source visual depth.",
			"Move setmetatile, door, border, and connection redraws onto the same layer-aware path.",
		],
		"unsupported": get_unsupported(),
	}


func get_runtime_layer_status() -> Dictionary:
	return {
		"owner": OWNER_NAME,
		"status": RUNTIME_STATUS,
		"map_size": [map_size.x, map_size.y],
		"tile_size": tile_size,
		"debug_fallback_active": _debug_fallback != null,
		"source_equivalent_for_runtime_layering": false,
		"unsupported": get_unsupported(),
	}


func get_required_import_inputs() -> Array:
	return [
		"map_grid.raw",
		"block_ids",
		"border_grid",
		"connections",
		"layer_rendering.layer_atlases",
		"metatile_entries.tile_entries",
		"metatile_entries.render_layers",
		"metatile_entries.attribute.layer_type",
		"metatile_entries.attribute.behavior_name",
		"object_events",
		"door_animations",
	]


func get_layer_roles() -> Array:
	return [
		{
			"id": "bottom",
			"source_bg_equivalent": "BG3",
			"draw_intent": "below ordinary object-event/player presentation",
		},
		{
			"id": "middle",
			"source_bg_equivalent": "BG2",
			"draw_intent": "middle map layer used by normal bottom halves and covered top halves",
		},
		{
			"id": "top",
			"source_bg_equivalent": "BG1",
			"draw_intent": "above object-event/player presentation for normal and split top halves",
		},
		{
			"id": "object_depth",
			"source_bg_equivalent": "object-event priority and subpriority",
			"draw_intent": "player/object interleave against top map coverage",
		},
	]


func get_unsupported() -> Array:
	return [
		{
			"code": UNSUPPORTED_SOURCE_EQUIVALENT,
			"status": "pending",
			"source": "src/field_camera.c:DrawMetatile",
			"detail": "The owner contract exists, but separate bottom/middle/top runtime rendering is not implemented yet.",
		},
		{
			"code": UNSUPPORTED_FLATTENED_ATLAS,
			"status": "pending",
			"source": "tools/importer/export_tilesets.py",
			"detail": "The current fallback still draws flattened debug atlas tiles and is not source-equivalent for runtime layering.",
		},
		{
			"code": UNSUPPORTED_OBJECT_DEPTH,
			"status": "pending",
			"source": "src/event_object_movement.c:sElevationToPriority",
			"detail": "Player and object-event presentation is not yet interleaved with top map coverage.",
		},
		{
			"code": UNSUPPORTED_DOOR_LAYER,
			"status": "pending",
			"source": "src/field_door.c:DrawDoorMetatileAt",
			"detail": "Door frames still delegate to fallback overlays instead of applying forced-covered layer updates.",
		},
		{
			"code": UNSUPPORTED_LAYER_UPDATES,
			"status": "pending",
			"source": "src/field_camera.c:CurrentMapDrawMetatileAt",
			"detail": "Single-cell layer redraws for setmetatile, borders, connections, and animation frames are not implemented yet.",
		},
	]


func _layer_rule_contract() -> Dictionary:
	return {
		"normal": {
			"source_layer_type": "METATILE_LAYER_TYPE_NORMAL",
			"value": 0,
			"source_comment": "Metatile uses middle and top bg layers",
			"bottom_source_slot_to_runtime_layer": "middle",
			"top_source_slot_to_runtime_layer": "top",
			"object_depth_effect": "top half covers object-event/player presentation",
			"implementation_status": "pending_render_implementation",
		},
		"covered": {
			"source_layer_type": "METATILE_LAYER_TYPE_COVERED",
			"value": 1,
			"source_comment": "Metatile uses bottom and middle bg layers",
			"bottom_source_slot_to_runtime_layer": "bottom",
			"top_source_slot_to_runtime_layer": "middle",
			"object_depth_effect": "object-event/player presentation can draw over the top half",
			"implementation_status": "pending_render_implementation",
		},
		"split": {
			"source_layer_type": "METATILE_LAYER_TYPE_SPLIT",
			"value": 2,
			"source_comment": "Metatile uses bottom and top bg layers",
			"bottom_source_slot_to_runtime_layer": "bottom",
			"top_source_slot_to_runtime_layer": "top",
			"object_depth_effect": "top half covers object-event/player presentation",
			"implementation_status": "pending_render_implementation",
		},
		"door_animation": {
			"source_rule": "DrawDoorMetatileAt draws frames as METATILE_LAYER_TYPE_COVERED",
			"implementation_status": "pending_render_implementation",
		},
	}


func _map_size_from_map_data(source_map_data: Dictionary) -> Vector2i:
	var layout_info = source_map_data.get("layout", {})
	if typeof(layout_info) != TYPE_DICTIONARY:
		return Vector2i.ZERO
	return Vector2i(
		int(layout_info.get("width", 0)),
		int(layout_info.get("height", 0))
	)


func _tile_size_from_tileset(source_tileset_data: Dictionary) -> int:
	var atlas_info = source_tileset_data.get("atlas", {})
	if typeof(atlas_info) != TYPE_DICTIONARY:
		return DEFAULT_TILE_SIZE
	return max(1, int(atlas_info.get("tile_size", DEFAULT_TILE_SIZE)))


func _local_block_id(cell: Vector2i) -> int:
	var block_ids = _map_data.get("block_ids", [])
	if typeof(block_ids) != TYPE_ARRAY:
		return -1
	if cell.y < 0 or cell.y >= block_ids.size():
		return -1
	var row = block_ids[cell.y]
	if typeof(row) != TYPE_ARRAY:
		return -1
	if cell.x < 0 or cell.x >= row.size():
		return -1
	return int(row[cell.x])


func _debug_fallback_script_path() -> String:
	if _debug_fallback == null:
		return ""
	var script_resource = _debug_fallback.get_script()
	if script_resource == null:
		return ""
	return String(script_resource.resource_path)
