extends RefCounted

const MAP_BASE_Z_INDEX := 0
const SPRITE_INTERLEAVE_Z_INDEX := 1024
const TOP_LAYER_Z_INDEX := 2048
const SPRITE_ABOVE_TOP_Z_INDEX := 3072
const CANVAS_ITEM_Z_MIN := -4096
const CANVAS_ITEM_Z_MAX := 4096

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
	var source_priority := elevation_to_priority(elevation)
	var source_subpriority_base := elevation_to_subpriority(elevation)
	var layer_band := sprite_layer_band_for_source_priority(source_priority)
	var row_sort: int = maxi(0, cell.y) * 2
	var local_sort: int = clampi(local_order, 0, 1)
	return {
		"schema_version": 1,
		"cell": [cell.x, cell.y],
		"elevation": normalized_elevation(elevation),
		"source_oam_priority": source_priority,
		"source_subpriority_base": source_subpriority_base,
		"source_subpriority_model": "SetObjectSubpriorityByElevation_first_pass_row_sort",
		"runtime_layer_band": layer_band,
		"godot_z_index": _sprite_z_index(layer_band, row_sort, local_sort),
		"row_sort": row_sort,
		"local_sort": local_sort,
		"top_layer_z_index": TOP_LAYER_Z_INDEX,
		"sprite_interleave_z_index": SPRITE_INTERLEAVE_Z_INDEX,
		"sprite_above_top_z_index": SPRITE_ABOVE_TOP_Z_INDEX,
		"source_trace": SOURCE_TRACE.duplicate(),
		"unsupported": [
			{
				"code": "exact_oam_subpriority_pixel_sort_pending",
				"status": "first_pass",
				"source": "src/event_object_movement.c:SetObjectSubpriorityByElevation",
				"detail": "Godot z-index uses source elevation priority plus tile-row order; exact camera-offset and per-pixel OAM subpriority sorting remains future object-runtime work.",
			},
		],
	}


static func sprite_depth_record_for_event(event_data: Dictionary, fallback_cell := Vector2i.ZERO) -> Dictionary:
	return sprite_depth_record(
		event_position(event_data, fallback_cell),
		int(event_data.get("elevation", DEFAULT_ELEVATION)),
		event_local_order(event_data)
	)


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
		"runtime_z_bands": {
			"map_bottom_middle": MAP_BASE_Z_INDEX,
			"between_middle_and_top": SPRITE_INTERLEAVE_Z_INDEX,
			"top": TOP_LAYER_Z_INDEX,
			"above_top": SPRITE_ABOVE_TOP_Z_INDEX,
		},
		"implemented_scope": "static_player_and_object_event_nodes",
		"source_trace": SOURCE_TRACE.duplicate(),
		"unsupported": [
			{
				"code": "exact_oam_subpriority_pixel_sort_pending",
				"status": "first_pass",
				"source": "src/event_object_movement.c:SetObjectSubpriorityByElevation",
				"detail": "First-pass z bands follow source elevation priority; exact per-frame OAM subpriority, bridge subsprites, shadows, reflections, and movement-task priority updates remain future work.",
			},
		],
	}


static func _sprite_z_index(layer_band: String, row_sort: int, local_sort: int) -> int:
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
	return clampi(base + row_sort + local_sort, CANVAS_ITEM_Z_MIN, max_z)
