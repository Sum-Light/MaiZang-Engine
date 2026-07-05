extends Node2D

const OWNER_NAME := "LayerAwareMapRenderer"
const LEGACY_RENDERER_NAME := "DebugMapPlane"
const RUNTIME_STATUS := "normal_covered_split_layer_rendering_first_pass"
const DEFAULT_TILE_SIZE := 16
const NORMAL_LAYER_TYPE := 0
const COVERED_LAYER_TYPE := 1
const SPLIT_LAYER_TYPE := 2
const IMPLEMENTED_LAYER_TYPES := [NORMAL_LAYER_TYPE, COVERED_LAYER_TYPE, SPLIT_LAYER_TYPE]
const IMPLEMENTED_LAYER_TYPE_NAMES := [
	"METATILE_LAYER_TYPE_NORMAL",
	"METATILE_LAYER_TYPE_COVERED",
	"METATILE_LAYER_TYPE_SPLIT",
]
const LAYER_ROLE_IDS := ["bottom", "middle", "top"]

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
var _layer_textures: Dictionary = {}
var _layer_atlas_info: Dictionary = {}
var _metatile_layer_types: Dictionary = {}
var _normal_layer_metatile_count := 0
var _covered_layer_metatile_count := 0
var _split_layer_metatile_count := 0
var _flattened_atlas_texture: Texture2D = null
var _flattened_atlas_tile_size := DEFAULT_TILE_SIZE
var _flattened_atlas_columns := 0
var _flattened_atlas_total_metatiles := 0


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
	_configure_layer_rendering(_tileset_data)
	_configure_flattened_atlas(_tileset_data)
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


func get_normal_layer_rendering_status() -> Dictionary:
	return _metatile_layer_rendering_status()


func get_metatile_layer_rendering_status() -> Dictionary:
	return _metatile_layer_rendering_status()


func get_layer_draw_records_for_cell(cell: Vector2i) -> Dictionary:
	var block_id := _local_block_id(cell)
	if block_id < 0:
		return {
			"cell": [cell.x, cell.y],
			"block_id": block_id,
			"runtime_layer_path": "empty",
			"records": [],
		}

	if _runtime_layer_rendering_available() and _is_implemented_layer_block(block_id):
		var records := []
		for role in LAYER_ROLE_IDS:
			records.append(_layer_draw_record_for_role(role, block_id))
		var source_layer_type_name := _source_layer_type_name(block_id)
		return {
			"cell": [cell.x, cell.y],
			"block_id": block_id,
			"source_layer_type": source_layer_type_name,
			"source_layer_type_value": int(_metatile_layer_types.get(block_id, -1)),
			"runtime_layer_path": "%s_layer_atlases" % _source_layer_type_slug(source_layer_type_name),
			"records": records,
		}

	return {
		"cell": [cell.x, cell.y],
		"block_id": block_id,
		"source_layer_type": _source_layer_type_name(block_id),
		"source_layer_type_value": int(_metatile_layer_types.get(block_id, -1)),
		"runtime_layer_path": "flattened_fallback_or_pending",
		"records": [],
	}


func get_renderer_contract() -> Dictionary:
	return {
		"schema_version": 1,
		"owner": OWNER_NAME,
		"replaces_or_wraps": LEGACY_RENDERER_NAME,
		"runtime_status": RUNTIME_STATUS,
		"source_equivalent_for_runtime_layering": false,
		"normal_layer_rendering": _metatile_layer_rendering_status(),
		"metatile_layer_rendering": _metatile_layer_rendering_status(),
		"implemented_layer_types": IMPLEMENTED_LAYER_TYPE_NAMES.duplicate(),
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
			"get_normal_layer_rendering_status",
			"get_metatile_layer_rendering_status",
			"get_layer_draw_records_for_cell",
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
		"normal_layer_rendering": _metatile_layer_rendering_status(),
		"metatile_layer_rendering": _metatile_layer_rendering_status(),
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
			"status": "partially_implemented",
			"source": "src/field_camera.c:DrawMetatile",
			"detail": "Normal, covered, and split metatiles consume exported bottom/middle/top render data; source-equivalent object-depth interleave is still pending.",
		},
		{
			"code": UNSUPPORTED_FLATTENED_ATLAS,
			"status": "partial_fallback",
			"source": "tools/importer/export_tilesets.py",
			"detail": "No-layer-data fallback drawing still uses flattened debug atlas tiles when DebugMapPlane is not active.",
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
			"implementation_status": "implemented_first_pass_runtime_rendering",
		},
		"covered": {
			"source_layer_type": "METATILE_LAYER_TYPE_COVERED",
			"value": 1,
			"source_comment": "Metatile uses bottom and middle bg layers",
			"bottom_source_slot_to_runtime_layer": "bottom",
			"top_source_slot_to_runtime_layer": "middle",
			"object_depth_effect": "object-event/player presentation can draw over the top half",
			"implementation_status": "implemented_first_pass_runtime_rendering",
		},
		"split": {
			"source_layer_type": "METATILE_LAYER_TYPE_SPLIT",
			"value": 2,
			"source_comment": "Metatile uses bottom and top bg layers",
			"bottom_source_slot_to_runtime_layer": "bottom",
			"top_source_slot_to_runtime_layer": "top",
			"object_depth_effect": "top half covers object-event/player presentation",
			"implementation_status": "implemented_first_pass_runtime_rendering",
		},
		"door_animation": {
			"source_rule": "DrawDoorMetatileAt draws frames as METATILE_LAYER_TYPE_COVERED",
			"implementation_status": "pending_render_implementation",
		},
	}


func _draw() -> void:
	var has_layer_rendering := _runtime_layer_rendering_available()
	var should_draw_flattened_fallback := _debug_fallback == null
	if not has_layer_rendering and not should_draw_flattened_fallback:
		return

	for y in range(map_size.y):
		for x in range(map_size.x):
			var rect := Rect2(x * tile_size, y * tile_size, tile_size, tile_size)
			var block_id := _local_block_id(Vector2i(x, y))
			if has_layer_rendering and _is_implemented_layer_block(block_id):
				if _draw_layered_metatile(block_id, rect):
					if _grid_visible:
						draw_rect(rect, Color(0.22, 0.31, 0.24, 0.55), false, 1.0)
					continue
			if should_draw_flattened_fallback:
				if not _draw_flattened_tile(block_id, rect):
					draw_rect(rect, _fallback_tile_color(block_id, x, y), true)
				if _grid_visible:
					draw_rect(rect, Color(0.22, 0.31, 0.24, 0.55), false, 1.0)

	if should_draw_flattened_fallback:
		var border := Rect2(Vector2.ZERO, Vector2(map_size.x * tile_size, map_size.y * tile_size))
		draw_rect(border, Color(0.08, 0.12, 0.10, 0.95), false, 2.0)


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


func _configure_layer_rendering(source_tileset_data: Dictionary) -> void:
	_layer_textures.clear()
	_layer_atlas_info.clear()
	_metatile_layer_types.clear()
	_normal_layer_metatile_count = 0
	_covered_layer_metatile_count = 0
	_split_layer_metatile_count = 0

	var layer_rendering = source_tileset_data.get("layer_rendering", {})
	if typeof(layer_rendering) != TYPE_DICTIONARY:
		return
	var layer_atlases = layer_rendering.get("layer_atlases", {})
	if typeof(layer_atlases) != TYPE_DICTIONARY:
		return

	for role in LAYER_ROLE_IDS:
		var atlas_record = layer_atlases.get(role, {})
		if typeof(atlas_record) != TYPE_DICTIONARY:
			continue
		var texture := _texture_from_image_record(atlas_record)
		if texture == null:
			continue
		_layer_textures[role] = texture
		_layer_atlas_info[role] = {
			"tile_size": max(1, int(atlas_record.get("tile_size", tile_size))),
			"columns": int(atlas_record.get("columns", 0)),
			"total_metatiles": int(atlas_record.get("total_metatiles", 0)),
		}

	var metatile_entries = source_tileset_data.get("metatile_entries", [])
	if typeof(metatile_entries) != TYPE_ARRAY:
		return
	for entry in metatile_entries:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var metatile_id := int(entry.get("id", -1))
		if metatile_id < 0:
			continue
		var attribute = entry.get("attribute", {})
		if typeof(attribute) != TYPE_DICTIONARY:
			continue
		var layer_type := int(attribute.get("layer_type", -1))
		_metatile_layer_types[metatile_id] = layer_type
		if layer_type == NORMAL_LAYER_TYPE:
			_normal_layer_metatile_count += 1
		elif layer_type == COVERED_LAYER_TYPE:
			_covered_layer_metatile_count += 1
		elif layer_type == SPLIT_LAYER_TYPE:
			_split_layer_metatile_count += 1


func _configure_flattened_atlas(source_tileset_data: Dictionary) -> void:
	_flattened_atlas_texture = null
	_flattened_atlas_tile_size = tile_size
	_flattened_atlas_columns = 0
	_flattened_atlas_total_metatiles = 0

	var atlas_info = source_tileset_data.get("atlas", {})
	if typeof(atlas_info) != TYPE_DICTIONARY:
		return
	_flattened_atlas_tile_size = max(1, int(atlas_info.get("tile_size", tile_size)))
	_flattened_atlas_columns = int(atlas_info.get("columns", 0))
	_flattened_atlas_total_metatiles = int(atlas_info.get("total_metatiles", 0))
	_flattened_atlas_texture = _texture_from_image_record(atlas_info)


func _metatile_layer_rendering_status() -> Dictionary:
	return {
		"status": "implemented_first_pass" if _runtime_layer_rendering_available() else "missing_generated_layer_data",
		"source_layer_types": IMPLEMENTED_LAYER_TYPE_NAMES.duplicate(),
		"source_layer_type_values": IMPLEMENTED_LAYER_TYPES.duplicate(),
		"drawn_roles": _loaded_layer_roles(),
		"required_roles": LAYER_ROLE_IDS.duplicate(),
		"normal_metatile_count": _normal_layer_metatile_count,
		"covered_metatile_count": _covered_layer_metatile_count,
		"split_metatile_count": _split_layer_metatile_count,
		"implemented_metatile_count": (
			_normal_layer_metatile_count
			+ _covered_layer_metatile_count
			+ _split_layer_metatile_count
		),
		"normal_runtime_path_active": _runtime_layer_rendering_available(),
		"covered_runtime_path_active": _runtime_layer_rendering_available(),
		"split_runtime_path_active": _runtime_layer_rendering_available(),
		"object_depth_interleave": "pending",
	}


func _runtime_layer_rendering_available() -> bool:
	if (
		_normal_layer_metatile_count <= 0
		and _covered_layer_metatile_count <= 0
		and _split_layer_metatile_count <= 0
	):
		return false
	for role in LAYER_ROLE_IDS:
		if not _layer_textures.has(role):
			return false
	return true


func _loaded_layer_roles() -> Array:
	var roles := []
	for role in LAYER_ROLE_IDS:
		if _layer_textures.has(role):
			roles.append(role)
	return roles


func _is_implemented_layer_block(block_id: int) -> bool:
	if block_id < 0 or not _metatile_layer_types.has(block_id):
		return false
	return IMPLEMENTED_LAYER_TYPES.has(int(_metatile_layer_types[block_id]))


func _draw_layered_metatile(block_id: int, rect: Rect2) -> bool:
	for role in LAYER_ROLE_IDS:
		if not _draw_layer_atlas_tile(role, block_id, rect):
			return false
	return true


func _draw_layer_atlas_tile(role: String, block_id: int, rect: Rect2) -> bool:
	var texture = _layer_textures.get(role, null)
	if not texture is Texture2D:
		return false
	var source_rect := _layer_source_rect(role, block_id)
	if source_rect.size == Vector2.ZERO:
		return false
	draw_texture_rect_region(texture, rect, source_rect)
	return true


func _draw_flattened_tile(block_id: int, rect: Rect2) -> bool:
	return _draw_texture_atlas_tile(
		_flattened_atlas_texture,
		block_id,
		rect,
		_flattened_atlas_tile_size,
		_flattened_atlas_columns,
		_flattened_atlas_total_metatiles
	)


func _draw_texture_atlas_tile(
	texture: Texture2D,
	block_id: int,
	rect: Rect2,
	atlas_tile_size: int,
	atlas_columns: int,
	total_metatiles: int
) -> bool:
	if texture == null or atlas_columns <= 0 or block_id < 0:
		return false
	if total_metatiles > 0 and block_id >= total_metatiles:
		return false
	var atlas_column := block_id % atlas_columns
	var atlas_row := int(floor(float(block_id) / float(atlas_columns)))
	var source_rect := Rect2(
		atlas_column * atlas_tile_size,
		atlas_row * atlas_tile_size,
		atlas_tile_size,
		atlas_tile_size
	)
	draw_texture_rect_region(texture, rect, source_rect)
	return true


func _layer_draw_record_for_role(role: String, block_id: int) -> Dictionary:
	var source_rect := _layer_source_rect(role, block_id)
	return {
		"role": role,
		"source_bg_equivalent": _source_bg_equivalent(role),
		"source_rect": {
			"x": int(source_rect.position.x),
			"y": int(source_rect.position.y),
			"w": int(source_rect.size.x),
			"h": int(source_rect.size.y),
		},
		"texture_loaded": _layer_textures.has(role),
	}


func _layer_source_rect(role: String, block_id: int) -> Rect2:
	var atlas_info = _layer_atlas_info.get(role, {})
	if typeof(atlas_info) != TYPE_DICTIONARY:
		return Rect2()
	var atlas_tile_size := int(atlas_info.get("tile_size", tile_size))
	var atlas_columns := int(atlas_info.get("columns", 0))
	var total_metatiles := int(atlas_info.get("total_metatiles", 0))
	if atlas_tile_size <= 0 or atlas_columns <= 0 or block_id < 0:
		return Rect2()
	if total_metatiles > 0 and block_id >= total_metatiles:
		return Rect2()
	return Rect2(
		(block_id % atlas_columns) * atlas_tile_size,
		int(floor(float(block_id) / float(atlas_columns))) * atlas_tile_size,
		atlas_tile_size,
		atlas_tile_size
	)


func _source_bg_equivalent(role: String) -> String:
	match role:
		"bottom":
			return "BG3"
		"middle":
			return "BG2"
		"top":
			return "BG1"
	return ""


func _source_layer_type_name(block_id: int) -> String:
	match int(_metatile_layer_types.get(block_id, -1)):
		0:
			return "METATILE_LAYER_TYPE_NORMAL"
		1:
			return "METATILE_LAYER_TYPE_COVERED"
		2:
			return "METATILE_LAYER_TYPE_SPLIT"
	return "UNKNOWN"


func _source_layer_type_slug(source_layer_type_name: String) -> String:
	var slug := source_layer_type_name.to_lower()
	slug = slug.replace("metatile_layer_type_", "")
	return slug


func _texture_from_image_record(record: Dictionary) -> Texture2D:
	var image_path := String(record.get("image", ""))
	if image_path.is_empty():
		return null
	var loaded_resource := load(image_path)
	if loaded_resource is Texture2D:
		return loaded_resource

	var load_path := image_path
	if load_path.begins_with("res://") or load_path.begins_with("user://"):
		load_path = ProjectSettings.globalize_path(load_path)
	var image := Image.new()
	if image.load(load_path) != OK:
		push_warning("Could not load layer-aware map texture: %s" % image_path)
		return null
	return ImageTexture.create_from_image(image)


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


func _fallback_tile_color(block_id: int, x: int, y: int) -> Color:
	var fallback_colors := [
		Color(0.44, 0.68, 0.36, 1.0),
		Color(0.58, 0.76, 0.42, 1.0),
		Color(0.72, 0.66, 0.45, 1.0),
		Color(0.43, 0.58, 0.72, 1.0),
		Color(0.55, 0.46, 0.70, 1.0),
		Color(0.70, 0.52, 0.42, 1.0),
		Color(0.45, 0.70, 0.62, 1.0),
		Color(0.68, 0.70, 0.50, 1.0),
	]
	if block_id >= 0:
		return fallback_colors[block_id % fallback_colors.size()]
	return Color(0.64, 0.78, 0.50, 1.0) if (x + y) % 2 == 0 else Color(0.56, 0.72, 0.45, 1.0)


func _debug_fallback_script_path() -> String:
	if _debug_fallback == null:
		return ""
	var script_resource = _debug_fallback.get_script()
	if script_resource == null:
		return ""
	return String(script_resource.resource_path)
