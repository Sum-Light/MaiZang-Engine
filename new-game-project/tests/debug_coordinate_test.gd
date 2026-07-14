extends SceneTree

const START_CELL := Vector2i(5, 26)
const TARGET_CELL := Vector2i(4, 25)
const TARGET_TILE := Vector2i(28, 30)
const EXPECTED_START := Vector3(160.5, 1.0, 832.5)
const EXPECTED_TARGET := Vector3(156.5, 0.0, 830.5)
const TEST_VARIANT := "matrix_9999_test"
const TEST_HEADER_ID := 999
const TEST_CATALOG_PATH := "user://debug_coordinate_catalog.json"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if not _write_test_catalog():
		_fail("Synthetic matrix catalog could not be written.")
		return
	var streamer := PlatinumWorldStreamer.new()
	streamer._matrix_id = 9999
	streamer._area_data_id = -1
	streamer.catalog_path = TEST_CATALOG_PATH
	if not streamer._apply_manifest(_make_manifest()):
		_fail("Synthetic collision manifest could not be loaded.")
		streamer.free()
		_cleanup_test_catalog()
		return

	var start_position: Variant = streamer.resolve_cell_tile_world_position(START_CELL, Vector2i.ZERO)
	if start_position == null or not (start_position as Vector3).is_equal_approx(EXPECTED_START):
		_fail("Synthetic start position is incorrect: %s" % start_position)
		streamer.free()
		_cleanup_test_catalog()
		return
	var target_position: Variant = streamer.resolve_cell_tile_world_position(TARGET_CELL, TARGET_TILE)
	if target_position == null or not (target_position as Vector3).is_equal_approx(EXPECTED_TARGET):
		_fail("Absolute BDHC tile position is incorrect: %s" % target_position)
		streamer.free()
		_cleanup_test_catalog()
		return
	var offset_position: Variant = streamer.resolve_offset_grid_world_position(
		start_position as Vector3, Vector2(-4.0, -2.0)
	)
	if offset_position == null or not (offset_position as Vector3).is_equal_approx(EXPECTED_TARGET):
		_fail("Cross-cell offset did not adopt the destination BDHC height: %s" % offset_position)
		streamer.free()
		_cleanup_test_catalog()
		return
	if streamer.resolve_cell_tile_world_position(TARGET_CELL, Vector2i(32, 0)) != null:
		_fail("Out-of-range map tile was accepted.")
		streamer.free()
		_cleanup_test_catalog()
		return
	var automatic_step := streamer.resolve_player_step(start_position as Vector3, Vector2i.RIGHT)
	if (
		String(automatic_step.get("disposition", "")) != "special"
		or String(automatic_step.get("action", "")) != "transition"
	):
		_fail("An ordinary 0x67 tile did not retain automatic transition behavior.")
		streamer.free()
		_cleanup_test_catalog()
		return
	streamer._arrival_escape_world_tile = START_CELL * 32
	var escape_step := streamer.resolve_player_step(start_position as Vector3, Vector2i.RIGHT)
	if (
		not bool(escape_step.get("ok", false))
		or bool(escape_step.get("blocked", true))
		or String(escape_step.get("disposition", "")) != "allow"
	):
		_fail("An automatic Warp arrival could not leave its suppression tile.")
		streamer.free()
		_cleanup_test_catalog()
		return
	var escaped_position := escape_step.get("target", Vector3.INF) as Vector3
	streamer.resolve_player_step(escaped_position, Vector2i.RIGHT)
	if streamer._arrival_escape_world_tile != null:
		_fail("Automatic Warp arrival bypass survived after leaving its source tile.")
		streamer.free()
		_cleanup_test_catalog()
		return
	if (
		streamer._transition_source_world_tile(
			Vector2i(6, 2), Vector2i(7, 2), 0x00, Vector2i.RIGHT
		) != Vector2i(7, 2)
		or streamer._transition_source_world_tile(
			Vector2i(6, 2), Vector2i(6, 3), 0x65, Vector2i.DOWN
		) != Vector2i(6, 2)
		or streamer._transition_source_world_tile(
			Vector2i(6, 2), Vector2i(7, 2), 0x65, Vector2i.RIGHT
		) != Vector2i(7, 2)
		or streamer._transition_source_world_tile(
			Vector2i(6, 2), Vector2i(7, 2), 0x64, Vector2i.RIGHT
		) != Vector2i(6, 2)
	):
		_fail("Warp source selection does not mirror Platinum's directional ordering.")
		streamer.free()
		_cleanup_test_catalog()
		return

	print("DEBUG_COORDINATE_OK ", JSON.stringify({
		"start": EXPECTED_START,
		"target_cell": TARGET_CELL,
		"target_tile": TARGET_TILE,
		"target": EXPECTED_TARGET,
	}))
	streamer.free()
	_cleanup_test_catalog()
	quit(0)


func _make_manifest() -> Dictionary:
	var attributes := PackedByteArray()
	attributes.resize(2048)
	attributes.encode_u16(0, 0x0067)
	return {
		"schema_version": 4,
		"matrix": {"id": 9999, "variant": TEST_VARIANT, "area_data_id": null},
		"assets": {
			"terrain": [{"key": "synthetic_terrain", "output_glbs": ["synthetic.glb"]}],
			"buildings": [],
		},
		"collision_format": {
			"schema_version": 1,
			"terrain_width": 32,
			"terrain_height": 32,
			"terrain_order": "row_major",
			"collision_mask": 0x8000,
			"behavior_mask": 0x00FF,
			"fx32_fraction_bits": 12,
			"source_units_per_world_unit": 16,
			"bdhc_origin": "map_center",
		},
		"collision_assets": [
			_make_collision_asset(1, attributes, _make_flat_bdhc(16.0)),
			_make_collision_asset(2, attributes, _make_flat_bdhc(0.0)),
		],
		"field_features": {
			"schema_version": 1,
			"source_selection": "first_warp_id_at_tile",
			"default_header_id": TEST_HEADER_ID,
			"header_ids": [TEST_HEADER_ID],
			"warp_count": 0,
			"ordinary_warp_count": 0,
			"special_return_count": 0,
			"dynamic_warp_count": 0,
			"warps": [],
		},
		"map_animation_format": {
			"schema_version": 1,
			"source_fps": 30,
			"native_format": "nsbca",
			"unsupported_formats": ["nsbta", "nsbtp"],
			"playback_scope": "automatic_loops_and_warp_doors",
		},
		"cells": [
			{
				"x": START_CELL.x,
				"y": START_CELL.y,
				"altitude": 0,
				"map_id": 1,
				"header_id": TEST_HEADER_ID,
				"terrain_asset_key": "synthetic_terrain",
				"collision_asset_key": "map_0001_collision",
				"buildings": [],
			},
			{
				"x": TARGET_CELL.x,
				"y": TARGET_CELL.y,
				"altitude": 2,
				"map_id": 2,
				"header_id": TEST_HEADER_ID,
				"terrain_asset_key": "synthetic_terrain",
				"collision_asset_key": "map_0002_collision",
				"buildings": [],
			},
		],
	}


func _write_test_catalog() -> bool:
	var catalog := {
		"schema_version": 3,
		"destinations": [{
			"key": TEST_VARIANT,
			"matrix_id": 9999,
			"area_data_id": null,
		}],
		"headers": [{
			"header_id": TEST_HEADER_ID,
			"destination_key": TEST_VARIANT,
			"matrix_id": 9999,
			"area_data_id": null,
		}],
	}
	var file := FileAccess.open(TEST_CATALOG_PATH, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(catalog))
	file.close()
	return true


func _cleanup_test_catalog() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_CATALOG_PATH))


func _make_collision_asset(
	map_id: int,
	attributes: PackedByteArray,
	bdhc: PackedByteArray
) -> Dictionary:
	return {
		"key": "map_%04d_collision" % map_id,
		"map_id": map_id,
		"terrain_attributes": {
			"byte_length": attributes.size(),
			"data_base64": Marshalls.raw_to_base64(attributes),
		},
		"bdhc": {
			"byte_length": bdhc.size(),
			"data_base64": Marshalls.raw_to_base64(bdhc),
		},
	}


func _make_flat_bdhc(height_source_units: float) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(66)
	for index in 4:
		bytes[index] = [66, 68, 72, 67][index]
	for entry in [[4, 2], [6, 1], [8, 1], [10, 1], [12, 1], [14, 1]]:
		bytes.encode_u16(entry[0], entry[1])
	var offset := 16
	for point in [Vector2i(-256 * 4096, -256 * 4096), Vector2i(256 * 4096, 256 * 4096)]:
		bytes.encode_s32(offset, point.x)
		bytes.encode_s32(offset + 4, point.y)
		offset += 8
	bytes.encode_s32(offset, 0)
	bytes.encode_s32(offset + 4, 4096)
	bytes.encode_s32(offset + 8, 0)
	offset += 12
	bytes.encode_s32(offset, roundi(-height_source_units * 4096.0))
	offset += 4
	for value in [0, 1, 0, 0]:
		bytes.encode_u16(offset, value)
		offset += 2
	bytes.encode_s32(offset, 256 * 4096)
	bytes.encode_u16(offset + 4, 1)
	bytes.encode_u16(offset + 6, 0)
	offset += 8
	bytes.encode_u16(offset, 0)
	return bytes


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
