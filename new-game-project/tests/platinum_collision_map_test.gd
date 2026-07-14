extends SceneTree

const CollisionMap := preload("res://scripts/platinum_collision_map.gd")


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--real-manifest="):
			_run_real_manifest(argument.trim_prefix("--real-manifest="))
			return
	var collision_map := CollisionMap.new() as PlatinumCollisionMap
	var manifest := _make_manifest()
	var error := collision_map.configure(manifest)
	if not error.is_empty():
		_fail("Synthetic collision manifest failed to configure: %s" % error)
		return

	if int(collision_map.get_tile_attributes(Vector2i.ZERO, Vector2i.ZERO)) != 0x8015:
		_fail("Packed attributes did not retain the static collision bit.")
		return
	if int(collision_map.get_tile_behavior(Vector2i.ZERO, Vector2i.ZERO)) != 0x15:
		_fail("Packed attributes did not retain the behavior byte.")
		return

	var low_position: Variant = collision_map.resolve_cell_tile_world_position(
		Vector2i.ZERO, Vector2i(15, 16), 1.0
	)
	if low_position == null or not is_equal_approx((low_position as Vector3).y, 1.0):
		_fail("BDHC low plate height was not resolved.")
		return
	var high_position: Variant = collision_map.resolve_cell_tile_world_position(
		Vector2i.ZERO, Vector2i(16, 16), 1.0
	)
	if high_position == null or not is_equal_approx((high_position as Vector3).y, 2.25):
		_fail("BDHC high plate height was not resolved.")
		return
	var lower_overlap: Variant = collision_map.resolve_cell_tile_world_position(
		Vector2i(0, 1), Vector2i(16, 16), 1.1
	)
	var upper_overlap: Variant = collision_map.resolve_cell_tile_world_position(
		Vector2i(0, 1), Vector2i(16, 16), 2.9
	)
	var tied_overlap: Variant = collision_map.resolve_cell_tile_world_position(
		Vector2i(0, 1), Vector2i(16, 16), 2.0
	)
	if (
		lower_overlap == null
		or upper_overlap == null
		or tied_overlap == null
		or not is_equal_approx((lower_overlap as Vector3).y, 1.0)
		or not is_equal_approx((upper_overlap as Vector3).y, 3.0)
		or not is_equal_approx((tied_overlap as Vector3).y, 1.0)
	):
		_fail("Overlapping BDHC plates did not select the nearest layer with stable ties.")
		return
	var blocked_height := collision_map.resolve_step(low_position as Vector3, Vector2i.RIGHT)
	if not bool(blocked_height.blocked) or String(blocked_height.reason) != "height_discontinuity":
		_fail("The exact 1.25-world-unit height threshold did not block movement.")
		return

	var collision_origin := Vector3(1.5, 1.0, 3.5)
	var collision_step := collision_map.resolve_step(collision_origin, Vector2i.LEFT)
	if not bool(collision_step.blocked) or String(collision_step.reason) != "tile_collision":
		_fail("The target tile collision bit did not block movement.")
		return
	var directional_origin := Vector3(1.5, 1.0, 1.5)
	var directional_step := collision_map.resolve_step(directional_origin, Vector2i.RIGHT)
	if not bool(directional_step.blocked) or String(directional_step.reason) != "directional_behavior":
		_fail("Current-tile directional behavior did not block movement.")
		return
	var water_step := collision_map.resolve_step(Vector3(2.5, 1.0, 1.5), Vector2i.RIGHT)
	if (
		not bool(water_step.blocked)
		or String(water_step.disposition) != "special"
		or String(water_step.action) != "requires_surf"
	):
		_fail("Walk movement did not fail closed on a passable-bit water behavior.")
		return
	var jump_step := collision_map.resolve_step(Vector3(3.5, 1.0, 2.5), Vector2i.RIGHT)
	if (
		not bool(jump_step.blocked)
		or String(jump_step.action) != "jump"
		or jump_step.landing_target == null
		or not (jump_step.landing_target as Vector3).is_equal_approx(Vector3(5.5, 1.0, 2.5))
	):
		_fail("A directional ledge did not override its collision bit with a jump action and landing.")
		return
	var unknown_step := collision_map.resolve_step(Vector3(5.5, 1.0, 2.5), Vector2i.RIGHT)
	if not bool(unknown_step.blocked) or String(unknown_step.action) != "unsupported_behavior":
		_fail("An unknown passable-bit behavior did not fail closed.")
		return
	var puddle_step := collision_map.resolve_step(Vector3(7.5, 1.0, 2.5), Vector2i.RIGHT)
	if bool(puddle_step.blocked) or String(puddle_step.disposition) != "allow":
		_fail("Ordinary walkable shallow-water behavior was incorrectly blocked.")
		return
	var ice_step := collision_map.resolve_step(Vector3(9.5, 1.0, 2.5), Vector2i.RIGHT)
	if not bool(ice_step.blocked) or String(ice_step.action) != "forced_move_ice":
		_fail("Ice did not expose its unsupported forced-movement action.")
		return
	var bridge_start := collision_map.resolve_step(
		Vector3(11.5, 1.0, 2.5), Vector2i.RIGHT, {"bridge_layer": "ground"}
	)
	var elevated_bridge := collision_map.resolve_step(
		Vector3(12.5, 1.0, 2.5), Vector2i.RIGHT, bridge_start.next_context
	)
	var unknown_water_bridge := collision_map.resolve_step(
		Vector3(14.5, 1.0, 2.5), Vector2i.RIGHT, {"bridge_layer": "unknown"}
	)
	var ambiguous_inner_bridge := collision_map.resolve_step(
		Vector3(16.5, 2.25, 2.5), Vector2i.RIGHT, {"bridge_layer": "unknown"}
	)
	var explicit_elevated_bridge := collision_map.resolve_step(
		Vector3(16.5, 2.25, 2.5), Vector2i.RIGHT, {"bridge_layer": "elevated"}
	)
	var stale_elevated_context := collision_map.resolve_step(
		Vector3(18.5, 2.25, 2.5), Vector2i.RIGHT, {"bridge_layer": "elevated"}
	)
	if (
		bool(bridge_start.blocked)
		or String(bridge_start.next_context.bridge_layer) != "elevated"
		or bool(elevated_bridge.blocked)
		or not bool(unknown_water_bridge.blocked)
		or String(unknown_water_bridge.action) != "requires_surf"
		or not bool(ambiguous_inner_bridge.blocked)
		or String(ambiguous_inner_bridge.disposition) != "special"
		or String(ambiguous_inner_bridge.action) != "requires_bridge_context"
		or String(ambiguous_inner_bridge.next_context.bridge_layer) != "unknown"
		or bool(explicit_elevated_bridge.blocked)
		or String(explicit_elevated_bridge.next_context.bridge_layer) != "elevated"
		or bool(stale_elevated_context.blocked)
		or String(stale_elevated_context.next_context.bridge_layer) != "ground"
	):
		_fail("Bridge layer context did not distinguish elevated walking from water below: %s" % JSON.stringify({
			"start": bridge_start,
			"elevated": elevated_bridge,
			"unknown": unknown_water_bridge,
			"ambiguous_inner": ambiguous_inner_bridge,
			"explicit_inner": explicit_elevated_bridge,
			"stale_elevated": stale_elevated_context,
		}))
		return
	var boundary_origin := Vector3(31.5, 2.25, 2.5)
	var target_directional_step := collision_map.resolve_step(boundary_origin, Vector2i.RIGHT)
	if (
		not bool(target_directional_step.blocked)
		or String(target_directional_step.reason) != "directional_behavior"
	):
		_fail("Target-tile opposite behavior did not block movement across a cell boundary.")
		return
	var boundary_step := collision_map.resolve_step(
		Vector3(31.5, 2.25, 3.5), Vector2i.RIGHT
	)
	if (
		bool(boundary_step.blocked)
		or not (boundary_step.target as Vector3).is_equal_approx(Vector3(32.5, 2.25, 3.5))
	):
		_fail("An open step did not cross the 32-tile cell boundary correctly.")
		return
	var negative_position := Vector3(-0.5, 2.25, 3.5)
	if (
		collision_map.world_to_cell(negative_position) != Vector2i(-1, 0)
		or collision_map.world_to_tile(negative_position) != Vector2i(31, 3)
	):
		_fail("Negative world coordinates did not use floor-based cell and tile indexing.")
		return

	var prop_matches := collision_map.find_map_props_at_tile(Vector2i.ZERO, Vector2i.ZERO)
	if prop_matches.size() != 1 or int(prop_matches[0].model_id) != 99:
		_fail("Map-prop anchor lookup did not remain available outside visual chunks.")
		return
	var cross_cell_props := collision_map.find_map_props_at_tile(Vector2i(1, 0), Vector2i(4, 0))
	if (
		cross_cell_props.size() != 1
		or int(cross_cell_props[0].model_id) != 100
		or cross_cell_props[0].owner_cell != Vector2i.ZERO
	):
		_fail("Map-prop anchor lookup did not index props that extend into an adjacent cell.")
		return
	var empty_cell_props := collision_map.find_map_props_at_tile(Vector2i(1, 1), Vector2i(4, 0))
	if empty_cell_props.size() != 1 or int(empty_cell_props[0].model_id) != 101:
		_fail("Map-prop anchor lookup incorrectly required the anchor's target cell to be occupied.")
		return

	collision_map.prepare_region(Vector2i.ZERO, 0)
	var first_stats := collision_map.get_stats()
	if int(first_stats.decoded_assets) != 1:
		_fail("Collision retention did not decode only the requested map.")
		return
	collision_map.prepare_region(Vector2i(1, 0), 0)
	var second_stats := collision_map.get_stats()
	if int(second_stats.decoded_assets) != 1 or int(second_stats.decode_failures) != 0:
		_fail("Collision retention did not prune independently from visual chunks.")
		return
	var reloaded_attributes: Variant = collision_map.get_tile_attributes(Vector2i.ZERO, Vector2i.ZERO)
	if reloaded_attributes == null or int(reloaded_attributes) != 0x8015:
		_fail("A pruned collision asset could not be decoded again on demand.")
		return
	for automatic_x in [18, 20]:
		var automatic_origin := Vector3(automatic_x + 0.5, 2.25, 4.5)
		var automatic_result := collision_map.resolve_step(automatic_origin, Vector2i.RIGHT)
		var escape_result := collision_map.resolve_step(
			automatic_origin, Vector2i.RIGHT, {}, true
		)
		if (
			String(automatic_result.get("action", "")) != "transition"
			or bool(escape_result.get("blocked", true))
			or String(escape_result.get("disposition", "")) != "allow"
		):
			_fail("Automatic Warp behavior could not be bypassed for one arrival tile: %s" % JSON.stringify({
				"automatic": automatic_result,
				"escape": escape_result,
			}))
			return

	print("PLATINUM_COLLISION_MAP_OK ", JSON.stringify(collision_map.get_stats()))
	quit(0)


func _run_real_manifest(path: String) -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		_fail("Real collision manifest is not a JSON object: %s" % path)
		return
	var collision_map := CollisionMap.new() as PlatinumCollisionMap
	var error := collision_map.configure(parsed as Dictionary)
	if not error.is_empty():
		_fail("Real collision manifest failed to configure: %s" % error)
		return
	var position: Variant = collision_map.resolve_cell_tile_world_position(
		Vector2i(1, 1), Vector2i(31, 31)
	)
	if position == null:
		_fail("Real collision manifest did not resolve the requested tile.")
		return
	print("PLATINUM_COLLISION_REAL_OK ", JSON.stringify({
		"position": position,
		"stats": collision_map.get_stats(),
	}))
	quit(0)


func _make_manifest() -> Dictionary:
	var attributes_a := PackedByteArray()
	attributes_a.resize(2048)
	attributes_a.encode_u16(0, 0x8015)
	attributes_a.encode_u16((1 * 32 + 1) * 2, 0x0034)
	attributes_a.encode_u16((3 * 32) * 2, 0x8000)
	attributes_a.encode_u16((1 * 32 + 3) * 2, 0x0015)
	attributes_a.encode_u16((2 * 32 + 4) * 2, 0x8038)
	attributes_a.encode_u16((2 * 32 + 6) * 2, 0x003C)
	attributes_a.encode_u16((2 * 32 + 8) * 2, 0x0016)
	attributes_a.encode_u16((2 * 32 + 10) * 2, 0x0020)
	attributes_a.encode_u16((2 * 32 + 12) * 2, 0x0070)
	attributes_a.encode_u16((2 * 32 + 13) * 2, 0x0073)
	attributes_a.encode_u16((2 * 32 + 15) * 2, 0x0073)
	attributes_a.encode_u16((2 * 32 + 16) * 2, 0x0071)
	attributes_a.encode_u16((2 * 32 + 17) * 2, 0x0071)
	attributes_a.encode_u16((4 * 32 + 18) * 2, 0x0067)
	attributes_a.encode_u16((4 * 32 + 20) * 2, 0x006E)
	var attributes_b := PackedByteArray()
	attributes_b.resize(2048)
	attributes_b.encode_u16((2 * 32) * 2, 0x0031)
	var bdhc_a := _make_split_height_bdhc(16.0, 36.0)
	var bdhc_b := _make_split_height_bdhc(36.0, 36.0)
	var bdhc_c := _make_overlapping_height_bdhc(16.0, 48.0)
	return {
		"schema_version": 4,
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
			_make_asset("map_0007_collision", 7, attributes_a, bdhc_a),
			_make_asset("map_0008_collision", 8, attributes_b, bdhc_b),
			_make_asset("map_0009_collision", 9, attributes_b, bdhc_c),
		],
		"field_features": {
			"schema_version": 1,
			"source_selection": "first_warp_id_at_tile",
			"default_header_id": null,
			"header_ids": [],
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
				"x": 0,
				"y": 0,
				"map_id": 7,
				"altitude": 4,
				"collision_asset_key": "map_0007_collision",
				"buildings": [{
					"model_id": 99,
					"position": {"x": -15.5, "y": 1.0, "z": -15.5},
				}, {
					"model_id": 100,
					"position": {"x": 20.5, "y": 1.0, "z": -15.5},
				}],
			},
			{
				"x": 1,
				"y": 0,
				"map_id": 8,
				"altitude": 9,
				"collision_asset_key": "map_0008_collision",
				"buildings": [],
			},
			{
				"x": -1,
				"y": 0,
				"map_id": 8,
				"altitude": 9,
				"collision_asset_key": "map_0008_collision",
				"buildings": [],
			},
			{
				"x": 0,
				"y": 1,
				"map_id": 9,
				"altitude": 0,
				"collision_asset_key": "map_0009_collision",
				"buildings": [{
					"model_id": 101,
					"position": {"x": 20.5, "y": 1.0, "z": -15.5},
				}],
			},
		],
	}


func _make_asset(
	key: String,
	map_id: int,
	attributes: PackedByteArray,
	bdhc: PackedByteArray
) -> Dictionary:
	return {
		"key": key,
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


func _make_split_height_bdhc(left_height: float, right_height: float) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(96)
	for index in 4:
		bytes[index] = [66, 68, 72, 67][index]
	bytes.encode_u16(4, 4)
	bytes.encode_u16(6, 1)
	bytes.encode_u16(8, 2)
	bytes.encode_u16(10, 2)
	bytes.encode_u16(12, 1)
	bytes.encode_u16(14, 2)
	var points := [
		Vector2i(-256 * 4096, -256 * 4096),
		Vector2i(0, 256 * 4096),
		Vector2i(0, -256 * 4096),
		Vector2i(256 * 4096, 256 * 4096),
	]
	var offset := 16
	for point in points:
		bytes.encode_s32(offset, point.x)
		bytes.encode_s32(offset + 4, point.y)
		offset += 8
	bytes.encode_s32(offset, 0)
	bytes.encode_s32(offset + 4, 4096)
	bytes.encode_s32(offset + 8, 0)
	offset += 12
	bytes.encode_s32(offset, roundi(-left_height * 4096.0))
	bytes.encode_s32(offset + 4, roundi(-right_height * 4096.0))
	offset += 8
	for plate_index in 2:
		bytes.encode_u16(offset, plate_index * 2)
		bytes.encode_u16(offset + 2, plate_index * 2 + 1)
		bytes.encode_u16(offset + 4, 0)
		bytes.encode_u16(offset + 6, plate_index)
		offset += 8
	bytes.encode_s32(offset, 256 * 4096)
	bytes.encode_u16(offset + 4, 2)
	bytes.encode_u16(offset + 6, 0)
	offset += 8
	bytes.encode_u16(offset, 0)
	bytes.encode_u16(offset + 2, 1)
	return bytes


func _make_overlapping_height_bdhc(first_height: float, second_height: float) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(80)
	for index in 4:
		bytes[index] = [66, 68, 72, 67][index]
	bytes.encode_u16(4, 2)
	bytes.encode_u16(6, 1)
	bytes.encode_u16(8, 2)
	bytes.encode_u16(10, 2)
	bytes.encode_u16(12, 1)
	bytes.encode_u16(14, 2)
	var offset := 16
	for point in [Vector2i(-256 * 4096, -256 * 4096), Vector2i(256 * 4096, 256 * 4096)]:
		bytes.encode_s32(offset, point.x)
		bytes.encode_s32(offset + 4, point.y)
		offset += 8
	bytes.encode_s32(offset, 0)
	bytes.encode_s32(offset + 4, 4096)
	bytes.encode_s32(offset + 8, 0)
	offset += 12
	bytes.encode_s32(offset, roundi(-first_height * 4096.0))
	bytes.encode_s32(offset + 4, roundi(-second_height * 4096.0))
	offset += 8
	for constant_index in 2:
		bytes.encode_u16(offset, 0)
		bytes.encode_u16(offset + 2, 1)
		bytes.encode_u16(offset + 4, 0)
		bytes.encode_u16(offset + 6, constant_index)
		offset += 8
	bytes.encode_s32(offset, 256 * 4096)
	bytes.encode_u16(offset + 4, 2)
	bytes.encode_u16(offset + 6, 0)
	offset += 8
	bytes.encode_u16(offset, 0)
	bytes.encode_u16(offset + 2, 1)
	return bytes


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
