class_name PlatinumCollisionMap
extends Resource

const CELL_SIZE := 32
const TILE_COUNT := 32
const TILE_RECORD_BYTES := 2
const ATTRIBUTES_BYTES := TILE_COUNT * TILE_COUNT * TILE_RECORD_BYTES
const COLLISION_MASK := 0x8000
const BEHAVIOR_MASK := 0x00FF
const FX32_SCALE := 4096.0
const SOURCE_UNITS_PER_WORLD_UNIT := 16.0
const FX32_PER_WORLD_UNIT := FX32_SCALE * SOURCE_UNITS_PER_WORLD_UNIT
const MAX_HEIGHT_CANDIDATES := 10
const MAX_STEP_HEIGHT := 20.0 / SOURCE_UNITS_PER_WORLD_UNIT

const BLOCK_EAST := {
	0x30: true, 0x34: true, 0x36: true, 0x4A: true,
}
const BLOCK_WEST := {
	0x31: true, 0x35: true, 0x37: true, 0x4A: true,
}
const BLOCK_NORTH := {
	0x32: true, 0x34: true, 0x35: true, 0x49: true,
}
const BLOCK_SOUTH := {
	0x33: true, 0x36: true, 0x37: true, 0x49: true,
}
const WATER_BEHAVIORS := {0x10: true, 0x13: true, 0x15: true}
const JUMP_DIRECTIONS := {
	0x38: Vector2i.RIGHT,
	0x39: Vector2i.LEFT,
	0x3A: Vector2i.UP,
	0x3B: Vector2i.DOWN,
}
const JUMP_TWO_DIRECTIONS := {
	0x5A: Vector2i.UP,
	0x5B: Vector2i.DOWN,
	0x5C: Vector2i.LEFT,
	0x5D: Vector2i.RIGHT,
}
const SLIDE_DIRECTIONS := {
	0x40: Vector2i.RIGHT,
	0x41: Vector2i.LEFT,
	0x42: Vector2i.UP,
	0x43: Vector2i.DOWN,
}
const CURRENT_TRANSITION_DIRECTIONS := {
	0x5E: Vector2i.RIGHT,
	0x5F: Vector2i.LEFT,
	0x62: Vector2i.RIGHT,
	0x63: Vector2i.LEFT,
	0x65: Vector2i.DOWN,
	0x6C: Vector2i.RIGHT,
	0x6D: Vector2i.LEFT,
	0x6F: Vector2i.DOWN,
}
const CURRENT_AUTOMATIC_TRANSITIONS := {
	0x64: true,
	0x67: true,
	0x6A: true,
	0x6B: true,
	0x6E: true,
}
const TRANSITION_BEHAVIORS := {
	0x5E: true, 0x5F: true,
	0x62: true, 0x63: true, 0x64: true, 0x65: true,
	0x67: true, 0x69: true, 0x6A: true, 0x6B: true,
	0x6C: true, 0x6D: true, 0x6E: true, 0x6F: true,
}
const DYNAMIC_BEHAVIORS := {0x56: true, 0x57: true, 0x58: true, 0x59: true}
const BIKE_RAMP_BEHAVIORS := {0xD7: true, 0xD8: true, 0xD9: true, 0xDA: true, 0xDB: true}
const UNSUPPORTED_BEHAVIORS := {0x3C: true, 0x3D: true, 0x3E: true, 0x3F: true, 0x60: true, 0x8F: true}
const BRIDGE_START := 0x70
const BRIDGE_END := 0x7D
const BRIDGE_OVER_WATER := 0x73
const BIKE_BRIDGE_START := 0x76
const BIKE_BRIDGE_WATER := {0x78: true, 0x7C: true}
const BIKE_BRIDGE_GROUND_PASSABLE := {0x77: true, 0x79: true, 0x7B: true, 0x7D: true}

var _cells: Dictionary = {}
var _sources: Dictionary = {}
var _map_props_by_world_tile: Dictionary = {}
var _decoded: Dictionary = {}
var _failed_keys: Dictionary = {}
var _decoded_bytes := 0
var _decode_failures := 0


func configure(manifest: Dictionary) -> String:
	clear()
	if int(manifest.get("schema_version", -1)) != 4:
		return "Collision runtime requires destination manifest schema 4."
	var format: Dictionary = manifest.get("collision_format", {})
	if (
		int(format.get("schema_version", -1)) != 1
		or int(format.get("terrain_width", -1)) != TILE_COUNT
		or int(format.get("terrain_height", -1)) != TILE_COUNT
		or String(format.get("terrain_order", "")) != "row_major"
		or int(format.get("collision_mask", -1)) != COLLISION_MASK
		or int(format.get("behavior_mask", -1)) != BEHAVIOR_MASK
		or int(format.get("fx32_fraction_bits", -1)) != 12
		or int(format.get("source_units_per_world_unit", -1)) != 16
		or String(format.get("bdhc_origin", "")) != "map_center"
	):
		return "Collision manifest format is missing or unsupported."

	for source_value: Variant in manifest.get("collision_assets", []):
		if not source_value is Dictionary:
			return "Collision manifest contains a non-object asset."
		var source := source_value as Dictionary
		var key := String(source.get("key", ""))
		var map_id := int(source.get("map_id", -1))
		if key != "map_%04d_collision" % map_id or _sources.has(key):
			return "Collision manifest contains an invalid or duplicate asset: %s" % key
		_sources[key] = source

	for cell_value: Variant in manifest.get("cells", []):
		if not cell_value is Dictionary:
			return "Collision manifest contains a non-object cell."
		var cell := cell_value as Dictionary
		var coordinate := Vector2i(int(cell.get("x", -1)), int(cell.get("y", -1)))
		var collision_key := String(cell.get("collision_asset_key", ""))
		if _cells.has(coordinate) or not _sources.has(collision_key):
			return "Cell %s has a duplicate coordinate or missing collision asset." % coordinate
		var source: Dictionary = _sources[collision_key]
		if int(source.get("map_id", -1)) != int(cell.get("map_id", -2)):
			return "Cell %s collision asset does not match its map ID." % coordinate
		_cells[coordinate] = cell

	if _cells.is_empty() or _sources.is_empty():
		return "Collision manifest has no cells or assets."
	_index_map_props()
	return ""


func clear() -> void:
	_cells.clear()
	_sources.clear()
	_map_props_by_world_tile.clear()
	_decoded.clear()
	_failed_keys.clear()
	_decoded_bytes = 0
	_decode_failures = 0


func prepare_region(center: Vector2i, radius: int) -> void:
	var retained: Dictionary = {}
	for z in range(center.y - radius, center.y + radius + 1):
		for x in range(center.x - radius, center.x + radius + 1):
			var coordinate := Vector2i(x, z)
			if not _cells.has(coordinate):
				continue
			var cell: Dictionary = _cells[coordinate]
			var key := String(cell.get("collision_asset_key", ""))
			retained[key] = true
			_decode_asset(key)
	for key_value: Variant in _decoded.keys():
		var key := String(key_value)
		if retained.has(key):
			continue
		var record: Dictionary = _decoded[key]
		_decoded_bytes -= int(record.get("byte_length", 0))
		_decoded.erase(key)


func get_stats() -> Dictionary:
	return {
		"source_assets": _sources.size(),
		"decoded_assets": _decoded.size(),
		"decoded_bytes": _decoded_bytes,
		"decode_failures": _decode_failures,
		"cells": _cells.size(),
	}


func get_tile_attributes(matrix_cell: Vector2i, map_tile: Vector2i) -> Variant:
	if not _is_valid_tile(map_tile) or not _cells.has(matrix_cell):
		return null
	var cell: Dictionary = _cells[matrix_cell]
	var record: Variant = _decode_asset(String(cell.get("collision_asset_key", "")))
	if record == null:
		return null
	var attributes: PackedByteArray = (record as Dictionary).attributes
	return attributes.decode_u16((map_tile.y * TILE_COUNT + map_tile.x) * TILE_RECORD_BYTES)


func get_tile_behavior(matrix_cell: Vector2i, map_tile: Vector2i) -> Variant:
	var attributes: Variant = get_tile_attributes(matrix_cell, map_tile)
	return null if attributes == null else int(attributes) & BEHAVIOR_MASK


func resolve_cell_tile_world_position(
	matrix_cell: Vector2i,
	map_tile: Vector2i,
	reference_height: float = NAN
) -> Variant:
	if not _is_valid_tile(map_tile) or not _cells.has(matrix_cell):
		return null
	var world_position := Vector3(
		matrix_cell.x * CELL_SIZE + map_tile.x + 0.5,
		0.0,
		matrix_cell.y * CELL_SIZE + map_tile.y + 0.5
	)
	var cell: Dictionary = _cells[matrix_cell]
	var height_reference := reference_height
	if is_nan(height_reference):
		height_reference = float(cell.get("altitude", 0)) * 0.5
	var height: Variant = sample_ground_height(world_position, height_reference)
	if height == null:
		return null
	world_position.y = float(height)
	return world_position


func sample_ground_height(world_position: Vector3, reference_height: float) -> Variant:
	var matrix_cell := world_to_cell(world_position)
	if not _cells.has(matrix_cell):
		return null
	var cell: Dictionary = _cells[matrix_cell]
	var record_value: Variant = _decode_asset(String(cell.get("collision_asset_key", "")))
	if record_value == null:
		return null
	var record := record_value as Dictionary
	var bdhc: PackedByteArray = record.bdhc
	var local_x := world_position.x - (matrix_cell.x * CELL_SIZE + CELL_SIZE * 0.5)
	var local_z := world_position.z - (matrix_cell.y * CELL_SIZE + CELL_SIZE * 0.5)
	var query_x_fx32 := roundi(local_x * FX32_PER_WORLD_UNIT)
	var query_z_fx32 := roundi(local_z * FX32_PER_WORLD_UNIT)
	var strip_index := _find_strip(record, query_z_fx32)
	if strip_index < 0:
		return null

	var strips_offset := int(record.strips_offset)
	var strip_offset := strips_offset + strip_index * 8
	var element_count := bdhc.decode_u16(strip_offset + 4)
	var start_index := bdhc.decode_u16(strip_offset + 6)
	var access_offset := int(record.access_offset)
	var plates_offset := int(record.plates_offset)
	var points_offset := int(record.points_offset)
	var normals_offset := int(record.normals_offset)
	var constants_offset := int(record.constants_offset)
	var source_x := float(query_x_fx32) / FX32_SCALE
	var source_z := float(query_z_fx32) / FX32_SCALE
	var candidate_count := 0
	var selected_height := 0.0
	var selected_distance := INF
	for access_index in element_count:
		var plate_index := bdhc.decode_u16(access_offset + (start_index + access_index) * 2)
		var plate_offset := plates_offset + plate_index * 8
		var first_point := bdhc.decode_u16(plate_offset)
		var second_point := bdhc.decode_u16(plate_offset + 2)
		var normal_index := bdhc.decode_u16(plate_offset + 4)
		var constant_index := bdhc.decode_u16(plate_offset + 6)
		var first_offset := points_offset + first_point * 8
		var second_offset := points_offset + second_point * 8
		var first_x := bdhc.decode_s32(first_offset)
		var first_z := bdhc.decode_s32(first_offset + 4)
		var second_x := bdhc.decode_s32(second_offset)
		var second_z := bdhc.decode_s32(second_offset + 4)
		if (
			query_x_fx32 < mini(first_x, second_x)
			or query_x_fx32 > maxi(first_x, second_x)
			or query_z_fx32 < mini(first_z, second_z)
			or query_z_fx32 > maxi(first_z, second_z)
		):
			continue
		var normal_offset := normals_offset + normal_index * 12
		var normal_x := float(bdhc.decode_s32(normal_offset)) / FX32_SCALE
		var normal_y := float(bdhc.decode_s32(normal_offset + 4)) / FX32_SCALE
		var normal_z := float(bdhc.decode_s32(normal_offset + 8)) / FX32_SCALE
		if is_zero_approx(normal_y):
			continue
		var constant := float(bdhc.decode_s32(constants_offset + constant_index * 4)) / FX32_SCALE
		var source_height := -(normal_x * source_x + normal_z * source_z + constant) / normal_y
		var world_height := source_height / SOURCE_UNITS_PER_WORLD_UNIT
		var distance := absf(world_height - reference_height)
		if candidate_count == 0 or distance < selected_distance:
			selected_height = world_height
			selected_distance = distance
		candidate_count += 1
		if candidate_count >= MAX_HEIGHT_CANDIDATES:
			break
	if candidate_count == 0:
		return null
	return selected_height


func resolve_step(
	origin: Vector3,
	direction: Vector2i,
	context: Dictionary = {},
	ignore_current_transition: bool = false
) -> Dictionary:
	var next_context := _normalized_step_context(context)
	if absi(direction.x) + absi(direction.y) != 1:
		return _blocked_step(origin, "invalid_direction", -1, -1, 0.0, next_context)
	var current_cell := world_to_cell(origin)
	var current_tile := world_to_tile(origin, current_cell)
	var target_probe := origin + Vector3(direction.x, 0.0, direction.y)
	var target_cell := world_to_cell(target_probe)
	var target_tile := world_to_tile(target_probe, target_cell)
	var current_attributes: Variant = get_tile_attributes(current_cell, current_tile)
	var target_attributes: Variant = get_tile_attributes(target_cell, target_tile)
	if current_attributes == null or target_attributes == null:
		return _blocked_step(origin, "missing_collision_data", -1, -1, 0.0, next_context)
	var current_behavior := int(current_attributes) & BEHAVIOR_MASK
	var target_behavior := int(target_attributes) & BEHAVIOR_MASK
	var special := _resolve_special_behavior(
		origin,
		direction,
		current_behavior,
		target_behavior,
		int(target_attributes),
		next_context,
		ignore_current_transition
	)
	if not special.is_empty():
		return special
	if int(target_attributes) & COLLISION_MASK:
		return _blocked_step(
			origin, "tile_collision", int(target_attributes), target_behavior, 0.0, next_context
		)
	if _behavior_blocks(current_behavior, direction) or _behavior_blocks(target_behavior, -direction):
		return _blocked_step(
			origin, "directional_behavior", int(target_attributes), target_behavior, 0.0, next_context
		)
	var target: Variant = resolve_cell_tile_world_position(target_cell, target_tile, origin.y)
	if target == null:
		return _blocked_step(
			origin, "missing_height", int(target_attributes), target_behavior, 0.0, next_context
		)
	var target_position := target as Vector3
	var height_delta := absf(target_position.y - origin.y)
	if height_delta >= MAX_STEP_HEIGHT:
		return _blocked_step(
			origin,
			"height_discontinuity",
			int(target_attributes),
			target_behavior,
			height_delta,
			next_context
		)
	return {
		"ok": true,
		"blocked": false,
		"disposition": "allow",
		"action": "none",
		"reason": "",
		"target": target_position,
		"landing_target": target_position,
		"attributes": int(target_attributes),
		"behavior": target_behavior,
		"height_delta": height_delta,
		"next_context": next_context,
	}


func find_map_props_at_tile(matrix_cell: Vector2i, map_tile: Vector2i) -> Array[Dictionary]:
	var matches: Array[Dictionary] = []
	if not _is_valid_tile(map_tile):
		return matches
	var world_tile := matrix_cell * CELL_SIZE + map_tile
	for building_value: Variant in _map_props_by_world_tile.get(world_tile, []):
		matches.append((building_value as Dictionary).duplicate(true))
	return matches


func _index_map_props() -> void:
	_map_props_by_world_tile.clear()
	for owner_cell_value: Variant in _cells.keys():
		var owner_cell := owner_cell_value as Vector2i
		var cell: Dictionary = _cells[owner_cell]
		for building_value: Variant in cell.get("buildings", []):
			if not building_value is Dictionary:
				continue
			var building := building_value as Dictionary
			var position := _dictionary_to_vector3(building.get("position", {}))
			var world_position := Vector3(
				owner_cell.x * CELL_SIZE + CELL_SIZE * 0.5 + position.x,
				position.y,
				owner_cell.y * CELL_SIZE + CELL_SIZE * 0.5 + position.z
			)
			var world_tile := Vector2i(floori(world_position.x), floori(world_position.z))
			var indexed_prop := building.duplicate(true)
			indexed_prop["owner_cell"] = owner_cell
			indexed_prop["world_position"] = world_position
			if not _map_props_by_world_tile.has(world_tile):
				_map_props_by_world_tile[world_tile] = []
			(_map_props_by_world_tile[world_tile] as Array).append(indexed_prop)


func world_to_cell(world_position: Vector3) -> Vector2i:
	return Vector2i(floori(world_position.x / CELL_SIZE), floori(world_position.z / CELL_SIZE))


func world_to_tile(world_position: Vector3, matrix_cell: Vector2i = Vector2i(1 << 20, 1 << 20)) -> Vector2i:
	var cell := matrix_cell
	if cell.x == 1 << 20:
		cell = world_to_cell(world_position)
	return Vector2i(
		floori(world_position.x - cell.x * CELL_SIZE),
		floori(world_position.z - cell.y * CELL_SIZE)
	)


func _decode_asset(key: String) -> Variant:
	if _decoded.has(key):
		return _decoded[key]
	if _failed_keys.has(key) or not _sources.has(key):
		return null
	var source: Dictionary = _sources[key]
	var attributes_source: Dictionary = source.get("terrain_attributes", {})
	var bdhc_source: Dictionary = source.get("bdhc", {})
	var attributes := Marshalls.base64_to_raw(String(attributes_source.get("data_base64", "")))
	var bdhc := Marshalls.base64_to_raw(String(bdhc_source.get("data_base64", "")))
	var validation: Dictionary = _validate_packed_bdhc(bdhc)
	if (
		attributes.size() != ATTRIBUTES_BYTES
		or attributes.size() != int(attributes_source.get("byte_length", -1))
		or bdhc.size() != int(bdhc_source.get("byte_length", -1))
		or not bool(validation.get("ok", false))
	):
		_failed_keys[key] = true
		_decode_failures += 1
		return null
	validation["attributes"] = attributes
	validation["bdhc"] = bdhc
	validation["byte_length"] = attributes.size() + bdhc.size()
	_decoded[key] = validation
	_decoded_bytes += int(validation.byte_length)
	return validation


func _validate_packed_bdhc(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < 16 or bytes.slice(0, 4).get_string_from_ascii() != "BDHC":
		return {"ok": false}
	var points_count := bytes.decode_u16(4)
	var normals_count := bytes.decode_u16(6)
	var constants_count := bytes.decode_u16(8)
	var plates_count := bytes.decode_u16(10)
	var strips_count := bytes.decode_u16(12)
	var access_count := bytes.decode_u16(14)
	var points_offset := 16
	var normals_offset := points_offset + points_count * 8
	var constants_offset := normals_offset + normals_count * 12
	var plates_offset := constants_offset + constants_count * 4
	var strips_offset := plates_offset + plates_count * 8
	var access_offset := strips_offset + strips_count * 8
	if access_offset + access_count * 2 != bytes.size():
		return {"ok": false}
	for plate_index in plates_count:
		var offset := plates_offset + plate_index * 8
		var first_point := bytes.decode_u16(offset)
		var second_point := bytes.decode_u16(offset + 2)
		var normal := bytes.decode_u16(offset + 4)
		var constant := bytes.decode_u16(offset + 6)
		if (
			first_point >= points_count
			or second_point >= points_count
			or normal >= normals_count
			or constant >= constants_count
			or bytes.decode_s32(normals_offset + normal * 12 + 4) == 0
		):
			return {"ok": false}
	var previous_scanline := -9223372036854775807
	for strip_index in strips_count:
		var offset := strips_offset + strip_index * 8
		var scanline := bytes.decode_s32(offset)
		var count := bytes.decode_u16(offset + 4)
		var start := bytes.decode_u16(offset + 6)
		if scanline < previous_scanline or start + count > access_count:
			return {"ok": false}
		previous_scanline = scanline
	for access_index in access_count:
		if bytes.decode_u16(access_offset + access_index * 2) >= plates_count:
			return {"ok": false}
	return {
		"ok": true,
		"points_offset": points_offset,
		"normals_offset": normals_offset,
		"constants_offset": constants_offset,
		"plates_offset": plates_offset,
		"strips_offset": strips_offset,
		"access_offset": access_offset,
		"strips_count": strips_count,
	}


func _find_strip(record: Dictionary, scanline_fx32: int) -> int:
	var strips_count := int(record.strips_count)
	if strips_count == 0:
		return -1
	var bdhc: PackedByteArray = record.bdhc
	var strips_offset := int(record.strips_offset)
	var low := 0
	var high := strips_count
	while low < high:
		var middle := (low + high) >> 1
		if bdhc.decode_s32(strips_offset + middle * 8) <= scanline_fx32:
			low = middle + 1
		else:
			high = middle
	return mini(low, strips_count - 1)


func _resolve_special_behavior(
	origin: Vector3,
	direction: Vector2i,
	current_behavior: int,
	target_behavior: int,
	target_attributes: int,
	next_context: Dictionary,
	ignore_current_transition: bool
) -> Dictionary:
	if not ignore_current_transition and CURRENT_TRANSITION_DIRECTIONS.has(current_behavior):
		var transition_direction: Vector2i = CURRENT_TRANSITION_DIRECTIONS[current_behavior]
		if direction == transition_direction:
			return _special_step(
				origin, "transition", target_attributes, target_behavior, next_context
			)
	if not ignore_current_transition and CURRENT_AUTOMATIC_TRANSITIONS.has(current_behavior):
		return _special_step(origin, "transition", target_attributes, target_behavior, next_context)

	var jump_action := ""
	var jump_direction := Vector2i.ZERO
	if JUMP_DIRECTIONS.has(target_behavior):
		jump_action = "jump"
		jump_direction = JUMP_DIRECTIONS[target_behavior]
	elif JUMP_TWO_DIRECTIONS.has(target_behavior):
		jump_action = "jump_two"
		jump_direction = JUMP_TWO_DIRECTIONS[target_behavior]
	if not jump_action.is_empty():
		if direction != jump_direction:
			return _blocked_step(
				origin,
				"ledge_wrong_direction",
				target_attributes,
				target_behavior,
				0.0,
				next_context
			)
		var landing_target: Variant = _resolve_offset_position(origin, direction, 2)
		return _special_step(
			origin,
			jump_action,
			target_attributes,
			target_behavior,
			next_context,
			landing_target
		)

	if TRANSITION_BEHAVIORS.has(target_behavior):
		return _special_step(origin, "transition", target_attributes, target_behavior, next_context)
	if WATER_BEHAVIORS.has(target_behavior):
		return _special_step(origin, "requires_surf", target_attributes, target_behavior, next_context)
	if target_behavior == 0x4B or target_behavior == 0x4C:
		return _special_step(
			origin, "requires_rock_climb", target_attributes, target_behavior, next_context
		)
	if DYNAMIC_BEHAVIORS.has(target_behavior):
		return _special_step(
			origin, "requires_dynamic_feature", target_attributes, target_behavior, next_context
		)
	if target_behavior == 0x20:
		return _special_step(origin, "forced_move_ice", target_attributes, target_behavior, next_context)
	if SLIDE_DIRECTIONS.has(target_behavior):
		return _special_step(
			origin,
			"forced_move",
			target_attributes,
			target_behavior,
			next_context,
			null,
			SLIDE_DIRECTIONS[target_behavior]
		)
	if BIKE_RAMP_BEHAVIORS.has(target_behavior):
		return _special_step(origin, "requires_bike", target_attributes, target_behavior, next_context)
	if UNSUPPORTED_BEHAVIORS.has(target_behavior):
		return _special_step(
			origin, "unsupported_behavior", target_attributes, target_behavior, next_context
		)

	var bridge_layer := String(next_context.get("bridge_layer", "unknown"))
	var current_is_bridge := current_behavior >= BRIDGE_START and current_behavior <= BRIDGE_END
	var target_is_bridge := target_behavior >= BRIDGE_START and target_behavior <= BRIDGE_END
	if bridge_layer == "unknown" and current_is_bridge:
		return _special_step(
			origin,
			"requires_bridge_context",
			target_attributes,
			target_behavior,
			next_context
		)
	if not current_is_bridge:
		bridge_layer = "ground"
		next_context["bridge_layer"] = bridge_layer
	if current_behavior == BRIDGE_START:
		bridge_layer = "elevated"
	if target_is_bridge:
		if target_behavior == BRIDGE_START:
			bridge_layer = "elevated"
		elif target_behavior < BIKE_BRIDGE_START:
			if target_behavior == BRIDGE_OVER_WATER and bridge_layer != "elevated":
				return _special_step(
					origin, "requires_surf", target_attributes, target_behavior, next_context
				)
		elif bridge_layer == "ground" and BIKE_BRIDGE_GROUND_PASSABLE.has(target_behavior):
			pass
		elif bridge_layer == "ground" and BIKE_BRIDGE_WATER.has(target_behavior):
			return _special_step(
				origin, "requires_surf", target_attributes, target_behavior, next_context
			)
		else:
			return _special_step(
				origin, "requires_bike", target_attributes, target_behavior, next_context
			)
		next_context["bridge_layer"] = bridge_layer
	elif current_is_bridge:
		next_context["bridge_layer"] = "ground"
	return {}


func _resolve_offset_position(origin: Vector3, direction: Vector2i, distance: int) -> Variant:
	var probe := origin + Vector3(direction.x, 0.0, direction.y) * distance
	var cell := world_to_cell(probe)
	var tile := world_to_tile(probe, cell)
	return resolve_cell_tile_world_position(cell, tile, origin.y)


func _normalized_step_context(context: Dictionary) -> Dictionary:
	var bridge_layer := String(context.get("bridge_layer", "unknown"))
	if bridge_layer not in ["ground", "elevated", "unknown"]:
		bridge_layer = "unknown"
	return {
		"locomotion": String(context.get("locomotion", "walk")),
		"bridge_layer": bridge_layer,
	}


func _behavior_blocks(behavior: int, direction: Vector2i) -> bool:
	if direction.x > 0:
		return BLOCK_EAST.has(behavior)
	if direction.x < 0:
		return BLOCK_WEST.has(behavior)
	if direction.y < 0:
		return BLOCK_NORTH.has(behavior)
	return BLOCK_SOUTH.has(behavior)


func _blocked_step(
	origin: Vector3,
	reason: String,
	attributes: int = -1,
	behavior: int = -1,
	height_delta: float = 0.0,
	next_context: Dictionary = {}
) -> Dictionary:
	return {
		"ok": true,
		"blocked": true,
		"disposition": "blocked",
		"action": "none",
		"reason": reason,
		"target": origin,
		"landing_target": null,
		"attributes": attributes,
		"behavior": behavior,
		"height_delta": height_delta,
		"next_context": next_context,
	}


func _special_step(
	origin: Vector3,
	action: String,
	attributes: int,
	behavior: int,
	next_context: Dictionary,
	landing_target: Variant = null,
	forced_direction: Variant = null
) -> Dictionary:
	return {
		"ok": true,
		"blocked": true,
		"disposition": "special",
		"action": action,
		"reason": "special_behavior",
		"target": origin,
		"landing_target": landing_target,
		"forced_direction": forced_direction,
		"attributes": attributes,
		"behavior": behavior,
		"height_delta": 0.0,
		"next_context": next_context,
	}


func _is_valid_tile(tile: Vector2i) -> bool:
	return tile.x >= 0 and tile.x < TILE_COUNT and tile.y >= 0 and tile.y < TILE_COUNT


func _dictionary_to_vector3(value: Variant) -> Vector3:
	if not value is Dictionary:
		return Vector3.ZERO
	var dictionary := value as Dictionary
	return Vector3(
		float(dictionary.get("x", 0.0)),
		float(dictionary.get("y", 0.0)),
		float(dictionary.get("z", 0.0))
	)
