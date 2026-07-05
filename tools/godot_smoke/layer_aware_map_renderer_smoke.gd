extends SceneTree

const DATA_REGISTRY_SCRIPT := preload("res://scripts/autoload/data_registry.gd")
const DEBUG_MAP_PLANE_SCRIPT := preload("res://scripts/overworld/debug_map_plane.gd")
const LAYER_RENDERER_SCRIPT := preload("res://scripts/overworld/layer_aware_map_renderer.gd")
const MAP_RUNTIME_SCRIPT := preload("res://scripts/autoload/map_runtime.gd")
const TILESET_ANIMATION_PLAYER_SCRIPT := preload("res://scripts/overworld/tileset_animation_player.gd")

const START_MAP := "MAP_LITTLEROOT_TOWN"
const TILE_SIZE := 16

var _failed := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var registry = DATA_REGISTRY_SCRIPT.new()
	registry._ready()

	var map_data: Dictionary = registry.get_map_data(START_MAP, {
		"include_debug_overlays": true,
	})
	var tileset_data: Dictionary = registry.get_tileset_data_for_map(START_MAP)
	_assert(not map_data.is_empty(), "expected LittlerootTown map data")
	_assert(not tileset_data.is_empty(), "expected LittlerootTown tileset data")

	var debug_renderer = DEBUG_MAP_PLANE_SCRIPT.new()
	var renderer = LAYER_RENDERER_SCRIPT.new()
	get_root().add_child(debug_renderer)
	get_root().add_child(renderer)

	renderer.configure_data_registry(registry)
	renderer.configure_debug_fallback(debug_renderer)
	renderer.configure_from_map_data(map_data, tileset_data)

	var contract: Dictionary = renderer.get_renderer_contract()
	var status: Dictionary = renderer.get_runtime_layer_status()
	_assert(String(contract.get("owner", "")) == "LayerAwareMapRenderer", "expected layer-aware owner name")
	_assert(String(contract.get("replaces_or_wraps", "")) == "DebugMapPlane", "expected DebugMapPlane wrapper contract")
	_assert(
		String(contract.get("runtime_status", "")) == "normal_covered_split_border_connection_source_subpriority_first_pass",
		"expected normal+covered+split+border+connection+source-subpriority layer runtime status"
	)
	_assert(not bool(contract.get("source_equivalent_for_runtime_layering", true)), "expected layer rendering to stay non-equivalent")
	_assert(bool(contract.get("debug_fallback_active", false)), "expected debug fallback to be active")
	_assert(
		String(status.get("status", "")) == "normal_covered_split_border_connection_source_subpriority_first_pass",
		"expected runtime normal+covered+split+border+connection+source-subpriority layer status"
	)
	_assert(not bool(status.get("source_equivalent_for_runtime_layering", true)), "expected runtime status to stay non-equivalent")
	_assert(bool(status.get("debug_fallback_active", false)), "expected runtime status to expose active fallback")
	_assert(_array_has_string(contract.get("implemented_layer_types", []), "METATILE_LAYER_TYPE_NORMAL"), "expected normal layer implementation marker")
	_assert(_array_has_string(contract.get("implemented_layer_types", []), "METATILE_LAYER_TYPE_COVERED"), "expected covered layer implementation marker")
	_assert(_array_has_string(contract.get("implemented_layer_types", []), "METATILE_LAYER_TYPE_SPLIT"), "expected split layer implementation marker")

	var layer_status: Dictionary = renderer.get_metatile_layer_rendering_status()
	_assert(String(layer_status.get("status", "")) == "implemented_first_pass", "expected metatile layer status")
	_assert(bool(layer_status.get("normal_runtime_path_active", false)), "expected active normal layer path")
	_assert(bool(layer_status.get("covered_runtime_path_active", false)), "expected active covered layer path")
	_assert(bool(layer_status.get("split_runtime_path_active", false)), "expected active split layer path")
	_assert(int(layer_status.get("normal_metatile_count", 0)) == 369, "expected Littleroot normal metatile count")
	_assert(int(layer_status.get("covered_metatile_count", 0)) == 277, "expected Littleroot covered metatile count")
	_assert(int(layer_status.get("split_metatile_count", 0)) == 10, "expected Littleroot split metatile count")
	_assert(int(layer_status.get("implemented_metatile_count", 0)) == 656, "expected implemented metatile count")
	_assert(_array_has_string(layer_status.get("drawn_roles", []), "bottom"), "expected bottom role loaded")
	_assert(_array_has_string(layer_status.get("drawn_roles", []), "middle"), "expected middle role loaded")
	_assert(_array_has_string(layer_status.get("drawn_roles", []), "top"), "expected top role loaded")
	_assert(String(layer_status.get("object_depth_interleave", "")) == "implemented_first_pass", "expected object-depth first-pass status")
	var border_connection_status: Dictionary = renderer.get_border_connection_layer_status()
	_assert(String(border_connection_status.get("status", "")) == "implemented_first_pass", "expected border/connection first-pass status")
	_assert(int(border_connection_status.get("map_offset", 0)) == 7, "expected source MAP_OFFSET")
	_assert(int(border_connection_status.get("map_offset_w", 0)) == 15, "expected source MAP_OFFSET_W")
	_assert(int(border_connection_status.get("map_offset_h", 0)) == 14, "expected source MAP_OFFSET_H")
	_assert(bool(border_connection_status.get("has_border_grid", false)), "expected border grid in status")
	_assert(int(border_connection_status.get("connection_count", 0)) == 1, "expected Littleroot north connection")
	_assert(_array_has_string(border_connection_status.get("connection_directions", []), "north"), "expected north connection direction")
	var source_backup_draw_rect: Dictionary = border_connection_status.get("source_backup_draw_rect", {})
	_assert(int(source_backup_draw_rect.get("x", 0)) == -7, "expected backup draw rect x")
	_assert(int(source_backup_draw_rect.get("y", 0)) == -7, "expected backup draw rect y")
	_assert(int(source_backup_draw_rect.get("w", 0)) == 35, "expected backup draw rect width")
	_assert(int(source_backup_draw_rect.get("h", 0)) == 34, "expected backup draw rect height")
	_assert(not bool(border_connection_status.get("mutates_map_data", true)), "expected border/connection rendering not to mutate map data")
	_assert(not bool(border_connection_status.get("mutates_collision_or_elevation", true)), "expected border/connection rendering not to mutate collision/elevation")

	var object_depth: Dictionary = renderer.get_object_depth_interleave_status()
	_assert(String(object_depth.get("status", "")) == "implemented_first_pass", "expected object-depth contract implementation")
	var runtime_z_bands: Dictionary = object_depth.get("runtime_z_bands", {})
	_assert(int(runtime_z_bands.get("between_middle_and_top", 0)) > int(runtime_z_bands.get("map_bottom_middle", 0)), "expected sprite z band above bottom/middle")
	_assert(int(runtime_z_bands.get("top", 0)) > int(runtime_z_bands.get("between_middle_and_top", 0)), "expected top layer above default sprite band")
	_assert(int(runtime_z_bands.get("above_top", 0)) > int(runtime_z_bands.get("top", 0)), "expected high-priority object band above top layer")
	var default_depth: Dictionary = renderer.get_sprite_depth_record(Vector2i(10, 10), 3, 0)
	_assert(int(default_depth.get("source_oam_priority", -1)) == 2, "expected source elevation 3 object priority")
	_assert(String(default_depth.get("source_subpriority_model", "")) == "SetObjectSubpriorityByElevation_pixel_y_formula", "expected source y-sort subpriority model")
	_assert(int(default_depth.get("source_oam_subpriority", -1)) >= 0, "expected source OAM subpriority value")
	_assert(String(default_depth.get("runtime_layer_band", "")) == "between_middle_and_top", "expected default sprite interleave band")
	_assert(
		int(default_depth.get("godot_z_index", 0)) > int(runtime_z_bands.get("between_middle_and_top", 0))
		and int(default_depth.get("godot_z_index", 0)) < int(runtime_z_bands.get("top", 0)),
		"expected default sprite z-index between middle and top"
	)
	var upper_depth: Dictionary = renderer.get_sprite_depth_record(Vector2i(4, 2), 3, 0)
	var lower_depth: Dictionary = renderer.get_sprite_depth_record(Vector2i(4, 5), 3, 0)
	_assert(
		int(lower_depth.get("source_oam_subpriority", 0)) < int(upper_depth.get("source_oam_subpriority", 0)),
		"expected lower screen sprite to have lower source subpriority"
	)
	_assert(
		int(lower_depth.get("godot_z_index", 0)) > int(upper_depth.get("godot_z_index", 0)),
		"expected lower screen sprite to draw above upper sprite"
	)
	var overlay_status: Dictionary = contract.get("top_layer_overlay", {})
	_assert(String(overlay_status.get("status", "")) == "active", "expected active top layer overlay")
	_assert(int(overlay_status.get("godot_z_index", 0)) == int(runtime_z_bands.get("top", 0)), "expected overlay z to match top layer band")
	_assert(bool(overlay_status.get("drawn_after_sprite_interleave", false)), "expected top overlay after default sprite interleave")
	_assert(bool(overlay_status.get("role_visible", false)), "expected top overlay visible in all-layer mode")

	_assert_layer_debug_view(renderer, map_data, tileset_data)

	var layer_roles = contract.get("layer_roles", [])
	_assert(_has_id_record(layer_roles, "bottom"), "expected bottom layer role")
	_assert(_has_id_record(layer_roles, "middle"), "expected middle layer role")
	_assert(_has_id_record(layer_roles, "top"), "expected top layer role")
	_assert(_has_id_record(layer_roles, "object_depth"), "expected object-depth role")

	var required_inputs = contract.get("required_import_inputs", [])
	_assert(required_inputs.has("map_grid.raw"), "expected raw map-grid input requirement")
	_assert(required_inputs.has("border_grid"), "expected border-grid input requirement")
	_assert(required_inputs.has("connections"), "expected connection input requirement")
	_assert(required_inputs.has("layer_rendering.layer_atlases"), "expected layer-atlas input requirement")
	_assert(required_inputs.has("metatile_entries.tile_entries"), "expected metatile entry input requirement")
	_assert(required_inputs.has("metatile_entries.render_layers"), "expected metatile render-layer input requirement")
	_assert(required_inputs.has("metatile_entries.attribute.layer_type"), "expected layer-type input requirement")
	_assert(required_inputs.has("door_animations"), "expected door animation input requirement")
	_assert(required_inputs.has("tileset_animation_frame_strips"), "expected tileset animation frame-strip input requirement")
	_assert(required_inputs.has("tileset_animation_schedule_trace.tile_copy_appends"), "expected tileset animation schedule input requirement")

	var layer_contract: Dictionary = contract.get("layer_rule_contract", {})
	_assert(String(layer_contract.get("normal", {}).get("top_source_slot_to_runtime_layer", "")) == "top", "expected normal top layer rule")
	_assert(
		String(layer_contract.get("normal", {}).get("implementation_status", "")) == "implemented_first_pass_runtime_rendering",
		"expected normal rule to be implemented"
	)
	_assert(String(layer_contract.get("covered", {}).get("top_source_slot_to_runtime_layer", "")) == "middle", "expected covered middle layer rule")
	_assert(
		String(layer_contract.get("covered", {}).get("implementation_status", "")) == "implemented_first_pass_runtime_rendering",
		"expected covered rule to be implemented"
	)
	_assert(String(layer_contract.get("split", {}).get("bottom_source_slot_to_runtime_layer", "")) == "bottom", "expected split bottom layer rule")
	_assert(
		String(layer_contract.get("split", {}).get("implementation_status", "")) == "implemented_first_pass_runtime_rendering",
		"expected split rule to be implemented"
	)

	var unsupported_codes := _unsupported_codes(contract.get("unsupported", []))
	_assert(unsupported_codes.has("source_equivalent_layer_renderer_pending"), "expected source-equivalent renderer gap")
	_assert(unsupported_codes.has("flattened_debug_atlas_not_source_equivalent"), "expected flattened atlas gap")
	_assert(not unsupported_codes.has("object_depth_interleaving_pending"), "expected old object-depth pending gap to be retired")
	_assert(not unsupported_codes.has("exact_oam_subpriority_pixel_sort_pending"), "expected old exact-subpriority pending gap to be retired")
	_assert(unsupported_codes.has("bridge_shadow_reflection_priority_pending"), "expected bridge/shadow/reflection priority gap")
	_assert(unsupported_codes.has("door_forced_covered_layer_pending"), "expected door layer gap")
	_assert(not unsupported_codes.has("per_layer_redraw_cache_pending"), "expected setmetatile redraw cache pending gap to be retired")
	_assert(not unsupported_codes.has("border_connection_animation_redraw_cache_pending"), "expected border/connection redraw cache gap to be retired")
	_assert(not unsupported_codes.has("door_tileset_animation_redraw_cache_pending"), "expected combined door/tileset animation redraw gap to be retired")
	_assert(unsupported_codes.has("door_layer_redraw_cache_pending"), "expected door redraw cache gap")

	_assert_no_disallowed_runtime_keys(contract)
	_assert_no_disallowed_runtime_keys(status)

	renderer.set_grid_visible(true)
	_assert(renderer.is_grid_visible(), "expected owner grid state to turn on")
	_assert(debug_renderer.is_grid_visible(), "expected fallback grid state to turn on")

	var probe_cell := Vector2i(10, 10)
	_assert(
		renderer.get_render_block_id(probe_cell) == debug_renderer.get_render_block_id(probe_cell),
		"expected owner block query to delegate to fallback"
	)
	_assert_setmetatile_layer_redraw_cache(renderer, debug_renderer, map_data, tileset_data)
	_assert_tileset_animation_layer_atlas_update(renderer, registry, map_data, tileset_data)
	_assert_layer_draw_records(renderer, tileset_data, 0, "METATILE_LAYER_TYPE_NORMAL", "normal_layer_atlases")
	_assert_layer_draw_records(renderer, tileset_data, 1, "METATILE_LAYER_TYPE_COVERED", "covered_layer_atlases")
	_assert_layer_draw_records(renderer, tileset_data, 2, "METATILE_LAYER_TYPE_SPLIT", "split_layer_atlases")
	_assert_border_connection_layer_draw_records(renderer, debug_renderer, map_data, tileset_data)

	var animation := _first_door_animation(tileset_data)
	_assert(not animation.is_empty(), "expected generated door animation")
	_assert(
		renderer.set_door_animation_frame(Vector2i(14, 7), animation, 0),
		"expected owner to delegate door frame overlay to fallback"
	)
	_assert(renderer.get_door_animation_overlay_count() == 1, "expected delegated door overlay count")
	renderer.clear_door_animation(Vector2i(14, 7))
	_assert(renderer.get_door_animation_overlay_count() == 0, "expected delegated door overlay clear")

	print(JSON.stringify({
		"layer_aware_map_renderer_smoke": "ok",
		"owner": contract.get("owner", ""),
		"runtime_status": status.get("status", ""),
		"tileset_animation_status": renderer.get_tileset_animation_update_status().get("status", ""),
		"unsupported_count": unsupported_codes.size(),
	}))

	renderer.free()
	debug_renderer.free()
	registry.free()
	quit(1 if _failed else 0)


func _assert_layer_draw_records(
	renderer: Node,
	tileset_data: Dictionary,
	layer_type: int,
	expected_layer_type_name: String,
	expected_runtime_path: String
) -> void:
	var metatile_id := _first_metatile_id_for_layer_type(tileset_data, layer_type)
	_assert(metatile_id >= 0, "expected a %s metatile id" % expected_layer_type_name)
	var map_data := {
		"layout": {
			"width": 1,
			"height": 1,
		},
		"block_ids": [
			[metatile_id],
		],
	}
	renderer.configure_from_map_data(map_data, tileset_data)
	var draw_plan: Dictionary = renderer.get_layer_draw_records_for_cell(Vector2i.ZERO)
	_assert(String(draw_plan.get("runtime_layer_path", "")) == expected_runtime_path, "expected %s draw path" % expected_layer_type_name)
	_assert(int(draw_plan.get("block_id", -1)) == metatile_id, "expected draw-plan metatile id")
	_assert(String(draw_plan.get("source_layer_type", "")) == expected_layer_type_name, "expected source layer type")
	var records = draw_plan.get("records", [])
	_assert(typeof(records) == TYPE_ARRAY and records.size() == 3, "expected bottom/middle/top draw records")
	for role in ["bottom", "middle", "top"]:
		var record := _draw_record_for_role(records, role)
		_assert(not record.is_empty(), "expected %s draw record" % role)
		_assert(bool(record.get("texture_loaded", false)), "expected %s texture to be loaded" % role)
		_assert(
			String(record.get("source_bg_equivalent", "")) == _expected_bg_for_role(role),
			"expected %s source BG equivalent" % role
		)
		_assert(
			_rect_dict(record.get("source_rect", {})) == _generated_render_layer_rect(tileset_data, metatile_id, role),
			"expected %s draw rect to match generated render_layers atlas rect" % role
		)


func _assert_setmetatile_layer_redraw_cache(
	renderer: Node,
	debug_renderer: Node,
	map_data: Dictionary,
	tileset_data: Dictionary
) -> void:
	var runtime = MAP_RUNTIME_SCRIPT.new()
	runtime.configure_from_data(map_data, tileset_data, _map_size_from_data(map_data))
	var emitted := [{
		"map_data": {},
		"tileset_data": {},
		"map_size": Vector2i.ZERO,
	}]
	runtime.map_changed.connect(func(changed_map_data: Dictionary, changed_tileset_data: Dictionary, changed_size: Vector2i) -> void:
		emitted[0]["map_data"] = changed_map_data
		emitted[0]["tileset_data"] = changed_tileset_data
		emitted[0]["map_size"] = changed_size
	)

	var target_cell := Vector2i(10, 10)
	var previous_metatile_id := runtime.get_metatile_id_at(target_cell)
	var previous_layer_type := runtime.get_metatile_layer_type_at(target_cell)
	var metatile_id := _first_metatile_id_for_layer_type_excluding(tileset_data, 1, previous_metatile_id)
	_assert(metatile_id >= 0, "expected covered metatile id for setmetatile cache probe")
	var expected_layer_type_name := _layer_type_name_for_metatile(tileset_data, metatile_id)
	var summary := runtime.apply_script_field_effects([{
		"op": "setmetatile",
		"position": [target_cell.x, target_cell.y],
		"metatile_id": metatile_id,
		"collision": 3,
		"line": 777,
		"source_function": "ScrCmd_setmetatile",
	}])

	_assert(bool(summary.get("map_changed", false)), "expected setmetatile to emit map changed")
	_assert(_summary_count(summary, "layer_updates") == 1, "expected one layer update from setmetatile")
	_assert(bool(summary.get("renderer_cache_invalidated", false)), "expected setmetatile to invalidate renderer cache")
	var runtime_status := runtime.get_runtime_layer_update_status()
	_assert(
		String(runtime_status.get("status", "")) == "setmetatile_layer_updates_applied",
		"expected runtime setmetatile layer metadata"
	)
	_assert(int(runtime_status.get("affected_cell_count", 0)) == 1, "expected one affected layer cell")
	_assert(not bool(runtime_status.get("mutates_generated_files", true)), "expected runtime metadata not to mutate generated files")
	var emitted_map_data = emitted[0].get("map_data", {})
	_assert(typeof(emitted_map_data) == TYPE_DICTIONARY and not emitted_map_data.is_empty(), "expected emitted map data")

	renderer.configure_from_map_data(emitted_map_data, tileset_data)
	var cache_status: Dictionary = renderer.get_layer_redraw_cache_status()
	_assert(
		String(cache_status.get("status", "")) == "setmetatile_layer_redraw_cache_first_pass",
		"expected renderer setmetatile redraw cache status"
	)
	_assert(int(cache_status.get("cached_cell_count", 0)) == 1, "expected one cached redraw cell")
	_assert(bool(cache_status.get("updates_from_setmetatile", false)), "expected cache to identify setmetatile source")
	_assert(not bool(cache_status.get("mutates_map_data", true)), "expected renderer cache not to mutate map data")
	_assert(not bool(cache_status.get("mutates_collision_or_elevation", true)), "expected renderer cache not to mutate collision/elevation")
	var redraw_record: Dictionary = renderer.get_layer_redraw_record_for_cell(target_cell)
	_assert(not redraw_record.is_empty(), "expected redraw record for setmetatile cell")
	_assert(int(redraw_record.get("previous_metatile_id", -1)) == previous_metatile_id, "expected previous metatile id")
	_assert(int(redraw_record.get("metatile_id", -1)) == metatile_id, "expected redraw metatile id")
	_assert(int(redraw_record.get("block_id", -1)) == metatile_id, "expected redraw block id")
	_assert(int(redraw_record.get("previous_layer_type", -1)) == previous_layer_type, "expected previous layer type")
	_assert(String(redraw_record.get("source_layer_type", "")) == expected_layer_type_name, "expected redraw source layer type")
	_assert(String(redraw_record.get("runtime_layer_path", "")) == _runtime_layer_path_for_layer_type_name(expected_layer_type_name), "expected redraw runtime layer path")
	_assert(redraw_record.get("records", []).size() == 3, "expected redraw draw records")
	_assert(renderer.get_render_block_id(target_cell) == metatile_id, "expected renderer block id to update")
	_assert(debug_renderer.get_render_block_id(target_cell) == metatile_id, "expected fallback block id to update")
	runtime.free()


func _assert_tileset_animation_layer_atlas_update(
	renderer: Node,
	registry: Node,
	map_data: Dictionary,
	tileset_data: Dictionary
) -> void:
	renderer.configure_from_map_data(map_data, tileset_data)
	var player = TILESET_ANIMATION_PLAYER_SCRIPT.new()
	player.configure(registry, null, renderer)
	player.initialize_for_map(map_data, tileset_data, _map_size_from_data(map_data))
	var frame_update: Dictionary = player.advance_frame()
	_assert(bool(frame_update.get("mutates_renderer", false)), "expected tileset animation player to mutate renderer")
	_assert(String(frame_update.get("renderer_update_status", "")) == "tileset_animation_layer_atlas_updates_applied", "expected tileset animation renderer update status")
	_assert(bool(frame_update.get("source_equivalent_for_renderer_updates", false)), "expected renderer update to be source-backed")
	var renderer_update: Dictionary = renderer.get_tileset_animation_update_status()
	_assert(String(renderer_update.get("status", "")) == "tileset_animation_layer_atlas_updates_applied", "expected renderer atlas update status")
	_assert(int(renderer_update.get("tile_copy_request_count", 0)) == 1, "expected one first-frame tile-copy request")
	_assert(int(renderer_update.get("updated_metatile_count", 0)) > 0, "expected renderer to update affected metatile atlas regions")
	_assert(int(renderer_update.get("patched_slot_count", 0)) > 0, "expected renderer to patch atlas slots")
	_assert(not bool(renderer_update.get("rebuilds_full_map", true)), "expected atlas patch path not to rebuild full map")
	_assert(not bool(renderer_update.get("mutates_generated_files", true)), "expected atlas patch path not to mutate generated files")
	var sample_ids: Array = renderer_update.get("updated_metatile_ids_sample", [])
	_assert(not sample_ids.is_empty(), "expected updated metatile id sample")
	var redraw_record: Dictionary = renderer.get_tileset_animation_redraw_record_for_metatile(int(sample_ids[0]))
	_assert(not redraw_record.is_empty(), "expected renderer animation redraw record")
	_assert(int(redraw_record.get("patch_count", 0)) > 0, "expected redraw record patches")
	_assert_no_disallowed_runtime_keys(renderer_update)
	player.free()


func _assert_border_connection_layer_draw_records(
	renderer: Node,
	debug_renderer: Node,
	map_data: Dictionary,
	tileset_data: Dictionary
) -> void:
	var source_block_ids = map_data.get("block_ids", []).duplicate(true)
	renderer.configure_from_map_data(map_data, tileset_data)
	var north_connection_cell := Vector2i(10, -1)
	var connection_plan: Dictionary = renderer.get_layer_draw_records_for_cell(north_connection_cell)
	_assert(String(connection_plan.get("source_cell_region", "")) == "connection", "expected north edge cell to draw from connection")
	_assert(String(connection_plan.get("source_connection_direction", "")) == "north", "expected north connection direction")
	_assert(String(connection_plan.get("source_connection_map", "")) == "MAP_ROUTE101", "expected Route101 connection map")
	_assert(
		connection_plan.get("source_connection_destination_cell", []) == [10, 19],
		"expected source connection destination cell from Route101 bottom strip"
	)
	_assert(
		int(connection_plan.get("block_id", -1)) == debug_renderer.get_render_block_id(north_connection_cell),
		"expected connection block id to match fallback lookup"
	)
	_assert(int(connection_plan.get("block_id", -1)) >= 0, "expected connection block id")
	_assert(connection_plan.get("records", []).size() == 3, "expected connection bottom/middle/top draw records")
	_assert(String(connection_plan.get("runtime_layer_path", "")) != "flattened_fallback_or_pending", "expected connection to use layer atlas path")

	var border_cell := Vector2i(-1, -1)
	var border_plan: Dictionary = renderer.get_layer_draw_records_for_cell(border_cell)
	_assert(String(border_plan.get("source_cell_region", "")) == "border", "expected corner edge cell to draw from border")
	_assert(int(border_plan.get("source_border_index", -1)) == 3, "expected Emerald 2x2 border index")
	_assert(
		int(border_plan.get("block_id", -1)) == debug_renderer.get_render_block_id(border_cell),
		"expected border block id to match fallback lookup"
	)
	_assert(int(border_plan.get("block_id", -1)) >= 0, "expected border block id")
	_assert(border_plan.get("records", []).size() == 3, "expected border bottom/middle/top draw records")
	_assert(String(border_plan.get("runtime_layer_path", "")) != "flattened_fallback_or_pending", "expected border to use layer atlas path")
	_assert(map_data.get("block_ids", []) == source_block_ids, "expected border/connection query not to mutate map data")


func _assert_layer_debug_view(renderer: Node, map_data: Dictionary, tileset_data: Dictionary) -> void:
	var source_block_ids = map_data.get("block_ids", []).duplicate(true)
	var source_tileset_entries = tileset_data.get("metatile_entries", []).duplicate(true)
	var debug_status: Dictionary = renderer.get_layer_debug_view_status()
	_assert(String(debug_status.get("mode", "")) == "all", "expected all-layer debug view by default")
	_assert(debug_status.get("available_modes", []) == ["all", "bottom", "middle", "top"], "expected layer debug modes")
	_assert(debug_status.get("visible_roles", []) == ["bottom", "middle", "top"], "expected all visible roles")
	_assert(bool(debug_status.get("mutates_gameplay_data", true)) == false, "expected debug view to avoid gameplay mutation")
	_assert(bool(debug_status.get("mutates_map_data", true)) == false, "expected debug view to avoid map mutation")
	_assert(bool(debug_status.get("mutates_collision_or_elevation", true)) == false, "expected debug view to avoid collision/elevation mutation")

	renderer.set_layer_debug_view("bottom")
	debug_status = renderer.get_layer_debug_view_status()
	_assert(String(debug_status.get("mode", "")) == "bottom", "expected bottom-only debug mode")
	_assert(debug_status.get("visible_roles", []) == ["bottom"], "expected bottom-only visible role")
	_assert(debug_status.get("hidden_roles", []) == ["middle", "top"], "expected middle/top hidden in bottom mode")
	var top_overlay_status: Dictionary = renderer.get_runtime_layer_status().get("top_layer_overlay", {})
	_assert(not bool(top_overlay_status.get("role_visible", true)), "expected top overlay hidden in bottom mode")

	_assert(String(renderer.cycle_layer_debug_view()) == "middle", "expected bottom -> middle cycle")
	_assert(String(renderer.cycle_layer_debug_view()) == "top", "expected middle -> top cycle")
	top_overlay_status = renderer.get_runtime_layer_status().get("top_layer_overlay", {})
	_assert(bool(top_overlay_status.get("role_visible", false)), "expected top overlay visible in top mode")
	_assert(String(renderer.cycle_layer_debug_view()) == "all", "expected top -> all cycle")
	renderer.set_layer_debug_view("invalid")
	_assert(String(renderer.get_layer_debug_view_status().get("mode", "")) == "all", "expected invalid mode to normalize to all")

	_assert(map_data.get("block_ids", []) == source_block_ids, "expected debug view not to mutate map block ids")
	_assert(tileset_data.get("metatile_entries", []) == source_tileset_entries, "expected debug view not to mutate tileset entries")


func _metatile_atlas_rect(tileset_data: Dictionary, role: String, metatile_id: int) -> Rect2i:
	var layer_rendering = tileset_data.get("layer_rendering", {})
	var layer_atlases = layer_rendering.get("layer_atlases", {}) if typeof(layer_rendering) == TYPE_DICTIONARY else {}
	var atlas_record = layer_atlases.get(role, {}) if typeof(layer_atlases) == TYPE_DICTIONARY else {}
	if typeof(atlas_record) != TYPE_DICTIONARY:
		return Rect2i()
	var columns := int(atlas_record.get("columns", 0))
	var tile_size := int(atlas_record.get("tile_size", TILE_SIZE))
	if columns <= 0 or tile_size <= 0:
		return Rect2i()
	return Rect2i(
		(metatile_id % columns) * tile_size,
		int(floor(float(metatile_id) / float(columns))) * tile_size,
		tile_size,
		tile_size
	)


func _generated_render_layer_rect(tileset_data: Dictionary, metatile_id: int, role: String) -> Dictionary:
	var entries = tileset_data.get("metatile_entries", [])
	if typeof(entries) != TYPE_ARRAY:
		return {}
	for entry in entries:
		if typeof(entry) != TYPE_DICTIONARY or int(entry.get("id", -1)) != metatile_id:
			continue
		var render_layers = entry.get("render_layers", {})
		if typeof(render_layers) != TYPE_DICTIONARY:
			return {}
		var layers = render_layers.get("layers", {})
		if typeof(layers) != TYPE_DICTIONARY:
			return {}
		var layer_record = layers.get(role, {})
		if typeof(layer_record) != TYPE_DICTIONARY:
			return {}
		return _rect_dict(layer_record.get("atlas", {}))
	return {}


func _first_metatile_id_for_layer_type(tileset_data: Dictionary, expected_layer_type: int) -> int:
	var entries = tileset_data.get("metatile_entries", [])
	if typeof(entries) != TYPE_ARRAY:
		return -1
	for entry in entries:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var attribute = entry.get("attribute", {})
		if typeof(attribute) != TYPE_DICTIONARY:
			continue
		if int(attribute.get("layer_type", -1)) == expected_layer_type:
			return int(entry.get("id", -1))
	return -1


func _first_metatile_id_for_layer_type_excluding(
	tileset_data: Dictionary,
	expected_layer_type: int,
	excluded_metatile_id: int
) -> int:
	var entries = tileset_data.get("metatile_entries", [])
	if typeof(entries) != TYPE_ARRAY:
		return -1
	for entry in entries:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var metatile_id := int(entry.get("id", -1))
		if metatile_id == excluded_metatile_id:
			continue
		var attribute = entry.get("attribute", {})
		if typeof(attribute) != TYPE_DICTIONARY:
			continue
		if int(attribute.get("layer_type", -1)) == expected_layer_type:
			return metatile_id
	return -1


func _layer_type_name_for_metatile(tileset_data: Dictionary, metatile_id: int) -> String:
	var entries = tileset_data.get("metatile_entries", [])
	if typeof(entries) != TYPE_ARRAY:
		return "UNKNOWN"
	for entry in entries:
		if typeof(entry) != TYPE_DICTIONARY or int(entry.get("id", -1)) != metatile_id:
			continue
		var attribute = entry.get("attribute", {})
		if typeof(attribute) != TYPE_DICTIONARY:
			return "UNKNOWN"
		match int(attribute.get("layer_type", -1)):
			0:
				return "METATILE_LAYER_TYPE_NORMAL"
			1:
				return "METATILE_LAYER_TYPE_COVERED"
			2:
				return "METATILE_LAYER_TYPE_SPLIT"
	return "UNKNOWN"


func _runtime_layer_path_for_layer_type_name(layer_type_name: String) -> String:
	match layer_type_name:
		"METATILE_LAYER_TYPE_NORMAL":
			return "normal_layer_atlases"
		"METATILE_LAYER_TYPE_COVERED":
			return "covered_layer_atlases"
		"METATILE_LAYER_TYPE_SPLIT":
			return "split_layer_atlases"
	return "flattened_fallback_or_pending"


func _map_size_from_data(map_data: Dictionary) -> Vector2i:
	var layout_info = map_data.get("layout", {})
	if typeof(layout_info) != TYPE_DICTIONARY:
		return Vector2i.ZERO
	return Vector2i(
		int(layout_info.get("width", 0)),
		int(layout_info.get("height", 0))
	)


func _first_door_animation(tileset_data: Dictionary) -> Dictionary:
	var door_animations = tileset_data.get("door_animations", {})
	if typeof(door_animations) != TYPE_DICTIONARY:
		return {}
	var animations = door_animations.get("animations", [])
	if typeof(animations) != TYPE_ARRAY or animations.is_empty():
		return {}
	var animation = animations[0]
	if typeof(animation) != TYPE_DICTIONARY:
		return {}
	return animation


func _has_id_record(records, expected_id: String) -> bool:
	if typeof(records) != TYPE_ARRAY:
		return false
	for record in records:
		if typeof(record) == TYPE_DICTIONARY and String(record.get("id", "")) == expected_id:
			return true
	return false


func _array_has_string(records, expected: String) -> bool:
	if typeof(records) != TYPE_ARRAY:
		return false
	for record in records:
		if String(record) == expected:
			return true
	return false


func _draw_record_for_role(records, role: String) -> Dictionary:
	if typeof(records) != TYPE_ARRAY:
		return {}
	for record in records:
		if typeof(record) == TYPE_DICTIONARY and String(record.get("role", "")) == role:
			return record
	return {}


func _expected_bg_for_role(role: String) -> String:
	match role:
		"bottom":
			return "BG3"
		"middle":
			return "BG2"
		"top":
			return "BG1"
	return ""


func _rect_dict(value) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	return {
		"x": int(value.get("x", 0)),
		"y": int(value.get("y", 0)),
		"w": int(value.get("w", 0)),
		"h": int(value.get("h", 0)),
	}


func _unsupported_codes(records) -> Array:
	var result := []
	if typeof(records) != TYPE_ARRAY:
		return result
	for record in records:
		if typeof(record) == TYPE_DICTIONARY:
			result.append(String(record.get("code", "")))
	return result


func _summary_count(summary: Dictionary, key: String) -> int:
	var entries = summary.get(key, [])
	return entries.size() if typeof(entries) == TYPE_ARRAY else 0


func _assert_no_disallowed_runtime_keys(value, path := "root") -> void:
	if typeof(value) == TYPE_DICTIONARY:
		for key in value.keys():
			var key_text := String(key).to_lower()
			_assert(key_text.find("palette") == -1, "unexpected runtime key at %s.%s" % [path, String(key)])
			_assert(key_text.find("source_color") == -1, "unexpected runtime key at %s.%s" % [path, String(key)])
			_assert(key_text.find("source_palette") == -1, "unexpected runtime key at %s.%s" % [path, String(key)])
			_assert_no_disallowed_runtime_keys(value[key], "%s.%s" % [path, String(key)])
	elif typeof(value) == TYPE_ARRAY:
		for index in range(value.size()):
			_assert_no_disallowed_runtime_keys(value[index], "%s[%d]" % [path, index])


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)
