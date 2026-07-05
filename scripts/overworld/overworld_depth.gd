extends RefCounted

const MAP_BASE_Z_INDEX := 0
const SPRITE_INTERLEAVE_Z_INDEX := 1024
const TOP_LAYER_Z_INDEX := 2048
const SPRITE_ABOVE_TOP_Z_INDEX := 3072
const CANVAS_ITEM_Z_MIN := -4096
const CANVAS_ITEM_Z_MAX := 4096
const DEFAULT_TILE_SIZE := 16
const DEFAULT_CENTER_TO_CORNER_VEC_Y := -16
const DEFAULT_SOURCE_SUBPRIORITY_ARG := 1
const SOURCE_SUBPRIORITY_MAX := 255

const SOURCE_BG_PRIORITIES := {
	"BG1": 1,
	"BG2": 2,
	"BG3": 3,
}

const ELEVATION_TO_SUBPRIORITY := [
	115, 115, 83, 115, 83, 115, 83, 115, 83, 115, 83, 115, 83, 0, 0, 115,
]

const ELEVATION_TO_PRIORITY := [
	2, 2, 2, 2, 1, 2, 1, 2, 1, 2, 1, 2, 1, 0, 0, 2,
]

const DEFAULT_ELEVATION := 3
const SOURCE_TRACE := [
	"src/overworld.c:sOverworldBgTemplates",
	"src/event_object_movement.c:sElevationToPriority",
	"src/event_object_movement.c:sElevationToSubpriority",
	"src/event_object_movement.c:SetObjectSubpriorityByElevation",
	"src/event_object_movement.c:ObjectEventUpdateSubpriority",
]


static func sprite_depth_record(cell: Vector2i, elevation: int = DEFAULT_ELEVATION, local_order: int = 0) -> Dictionary:
	return sprite_depth_record_with_options(cell, elevation, local_order)


static func sprite_depth_record_with_options(
	cell: Vector2i,
	elevation: int = DEFAULT_ELEVATION,
	local_order: int = 0,
	options: Dictionary = {}
) -> Dictionary:
	var source_priority := elevation_to_priority(elevation)
	var layer_band := sprite_layer_band_for_source_priority(source_priority)
	var subpriority_record := source_subpriority_record(cell, elevation, options)
	var local_sort: int = clampi(local_order, 0, 1)
	return {
		"schema_version": 1,
		"cell": [cell.x, cell.y],
		"elevation": normalized_elevation(elevation),
		"source_oam_priority": source_priority,
		"source_subpriority_base": subpriority_record.get("source_subpriority_base", 0),
		"source_subpriority_arg": subpriority_record.get("source_subpriority_arg", DEFAULT_SOURCE_SUBPRIORITY_ARG),
		"source_subpriority_model": "SetObjectSubpriorityByElevation_pixel_y_formula",
		"source_sprite_y": subpriority_record.get("source_sprite_y", 0),
		"source_center_to_corner_vec_y": subpriority_record.get("source_center_to_corner_vec_y", DEFAULT_CENTER_TO_CORNER_VEC_Y),
		"source_camera_offset_y": subpriority_record.get("source_camera_offset_y", 0),
		"source_subpriority_adjusted_y": subpriority_record.get("source_subpriority_adjusted_y", 0),
		"source_y_sort_bucket": subpriority_record.get("source_y_sort_bucket", 0),
		"source_row_subpriority_component": subpriority_record.get("source_row_subpriority_component", 0),
		"source_oam_subpriority": subpriority_record.get("source_oam_subpriority", 0),
		"source_subpriority_draw_sort": subpriority_record.get("source_subpriority_draw_sort", 0),
		"runtime_layer_band": layer_band,
		"godot_z_index": _sprite_z_index(layer_band, int(subpriority_record.get("source_subpriority_draw_sort", 0)), local_sort),
		"row_sort": subpriority_record.get("source_subpriority_draw_sort", 0),
		"local_sort": local_sort,
		"top_layer_z_index": TOP_LAYER_Z_INDEX,
		"sprite_interleave_z_index": SPRITE_INTERLEAVE_Z_INDEX,
		"sprite_above_top_z_index": SPRITE_ABOVE_TOP_Z_INDEX,
		"source_trace": SOURCE_TRACE.duplicate(),
		"unsupported": _sprite_depth_unsupported(),
	}


static func sprite_depth_record_for_event(
	event_data: Dictionary,
	fallback_cell := Vector2i.ZERO,
	options: Dictionary = {}
) -> Dictionary:
	return sprite_depth_record_with_options(
		event_position(event_data, fallback_cell),
		int(event_data.get("elevation", DEFAULT_ELEVATION)),
		event_local_order(event_data),
		options
	)


static func source_subpriority_record(
	cell: Vector2i,
	elevation: int = DEFAULT_ELEVATION,
	options: Dictionary = {}
) -> Dictionary:
	var normalized := normalized_elevation(elevation)
	var world_position := _world_position_for_cell(cell, options)
	var source_sprite_y := int(round(world_position.y))
	var center_to_corner_vec_y := int(options.get("center_to_corner_vec_y", DEFAULT_CENTER_TO_CORNER_VEC_Y))
	var camera_offset_y := int(options.get("camera_offset_y", 0))
	var source_subpriority_arg := int(options.get("source_subpriority_arg", DEFAULT_SOURCE_SUBPRIORITY_ARG))
	var adjusted_y := (source_sprite_y - center_to_corner_vec_y) + camera_offset_y
	var y_sort_bucket := int(((adjusted_y + 8) & 0xFF) >> 4)
	var row_subpriority_component := (16 - y_sort_bucket) * 2
	var source_oam_subpriority := (
		row_subpriority_component
		+ int(ELEVATION_TO_SUBPRIORITY[normalized])
		+ source_subpriority_arg
	)
	return {
		"cell": [cell.x, cell.y],
		"world_position": [world_position.x, world_position.y],
		"elevation": normalized,
		"source_subpriority_base": int(ELEVATION_TO_SUBPRIORITY[normalized]),
		"source_subpriority_arg": source_subpriority_arg,
		"source_sprite_y": source_sprite_y,
		"source_center_to_corner_vec_y": center_to_corner_vec_y,
		"source_camera_offset_y": camera_offset_y,
		"source_subpriority_adjusted_y": adjusted_y,
		"source_y_sort_bucket": y_sort_bucket,
		"source_row_subpriority_component": row_subpriority_component,
		"source_oam_subpriority": source_oam_subpriority,
		"source_subpriority_draw_sort": clampi(SOURCE_SUBPRIORITY_MAX - source_oam_subpriority, 0, SOURCE_SUBPRIORITY_MAX),
		"source_trace": SOURCE_TRACE.duplicate(),
	}


static func event_position(event_data: Dictionary, fallback_cell := Vector2i.ZERO) -> Vector2i:
	var position = event_data.get("position", null)
	if typeof(position) == TYPE_VECTOR2I:
		return position
	if typeof(position) == TYPE_ARRAY and position.size() >= 2:
		return Vector2i(int(position[0]), int(position[1]))
	return Vector2i(
		int(event_data.get("x", fallback_cell.x)),
		int(event_data.get("y", fallback_cell.y))
	)


static func event_local_order(event_data: Dictionary) -> int:
	if event_data.has("source_order_index"):
		return int(event_data.get("source_order_index", 0)) % 2
	if event_data.has("index"):
		return int(event_data.get("index", 0)) % 2
	return 1


static func elevation_to_priority(elevation: int) -> int:
	var normalized := normalized_elevation(elevation)
	return int(ELEVATION_TO_PRIORITY[normalized])


static func elevation_to_subpriority(elevation: int) -> int:
	var normalized := normalized_elevation(elevation)
	return int(ELEVATION_TO_SUBPRIORITY[normalized])


static func normalized_elevation(elevation: int) -> int:
	return clampi(elevation, 0, ELEVATION_TO_PRIORITY.size() - 1)


static func sprite_layer_band_for_source_priority(source_priority: int) -> String:
	if source_priority <= SOURCE_BG_PRIORITIES["BG1"]:
		return "above_top"
	if source_priority == SOURCE_BG_PRIORITIES["BG2"]:
		return "between_middle_and_top"
	return "below_middle"


static func object_depth_contract() -> Dictionary:
	return {
		"schema_version": 1,
		"status": "implemented_first_pass",
		"source_bg_priorities": SOURCE_BG_PRIORITIES.duplicate(),
		"elevation_to_priority": ELEVATION_TO_PRIORITY.duplicate(),
		"elevation_to_subpriority": ELEVATION_TO_SUBPRIORITY.duplicate(),
		"source_subpriority_model": "SetObjectSubpriorityByElevation_pixel_y_formula",
		"source_subpriority_max": SOURCE_SUBPRIORITY_MAX,
		"runtime_z_bands": {
			"map_bottom_middle": MAP_BASE_Z_INDEX,
			"between_middle_and_top": SPRITE_INTERLEAVE_Z_INDEX,
			"top": TOP_LAYER_Z_INDEX,
			"above_top": SPRITE_ABOVE_TOP_Z_INDEX,
		},
		"implemented_scope": "player_and_object_event_nodes_with_pixel_y_source_subpriority",
		"source_trace": SOURCE_TRACE.duplicate(),
		"unsupported": _sprite_depth_unsupported(),
	}


static func _sprite_z_index(layer_band: String, source_subpriority_draw_sort: int, local_sort: int) -> int:
	var base := SPRITE_INTERLEAVE_Z_INDEX
	var max_z := TOP_LAYER_Z_INDEX - 1
	match layer_band:
		"above_top":
			base = SPRITE_ABOVE_TOP_Z_INDEX
			max_z = CANVAS_ITEM_Z_MAX
		"below_middle":
			base = MAP_BASE_Z_INDEX + 1
			max_z = SPRITE_INTERLEAVE_Z_INDEX - 1
		_:
			base = SPRITE_INTERLEAVE_Z_INDEX
			max_z = TOP_LAYER_Z_INDEX - 1
	return clampi(base + source_subpriority_draw_sort * 2 + local_sort, CANVAS_ITEM_Z_MIN, max_z)


static func _world_position_for_cell(cell: Vector2i, options: Dictionary) -> Vector2:
	var explicit_position = options.get("world_position", null)
	if typeof(explicit_position) == TYPE_VECTOR2:
		return explicit_position
	if typeof(explicit_position) == TYPE_VECTOR2I:
		return Vector2(explicit_position.x, explicit_position.y)
	if typeof(explicit_position) == TYPE_ARRAY and explicit_position.size() >= 2:
		return Vector2(float(explicit_position[0]), float(explicit_position[1]))

	var source_tile_size := float(options.get("tile_size", DEFAULT_TILE_SIZE))
	return Vector2(
		float(cell.x) * source_tile_size + source_tile_size * 0.5,
		float(cell.y) * source_tile_size + source_tile_size * 0.5
	)


static func _sprite_depth_unsupported() -> Array:
	return [
		{
			"code": "bridge_shadow_reflection_priority_pending",
			"status": "pending",
			"source": "src/event_object_movement.c:UpdateObjectEventElevationAndPriority",
			"detail": "Source SetObjectSubpriorityByElevation y-sort is modeled for player/object z bands; bridge subsprites, shadows, reflections, fixed-priority object events, and movement-task priority side effects remain future object-runtime work.",
		},
	]
