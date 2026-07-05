extends SceneTree

const DATA_REGISTRY_SCRIPT := preload("res://scripts/autoload/data_registry.gd")
const DEBUG_MAP_PLANE_SCRIPT := preload("res://scripts/overworld/debug_map_plane.gd")
const LAYER_RENDERER_SCRIPT := preload("res://scripts/overworld/layer_aware_map_renderer.gd")

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
		String(contract.get("runtime_status", "")) == "normal_covered_split_source_subpriority_first_pass",
		"expected normal+covered+split+source-subpriority layer runtime status"
	)
	_assert(not bool(contract.get("source_equivalent_for_runtime_layering", true)), "expected layer rendering to stay non-equivalent")
	_assert(bool(contract.get("debug_fallback_active", false)), "expected debug fallback to be active")
	_assert(
		String(status.get("status", "")) == "normal_covered_split_source_subpriority_first_pass",
		"expected runtime normal+covered+split+source-subpriority layer status"
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
	_assert_layer_draw_records(renderer, tileset_data, 0, "METATILE_LAYER_TYPE_NORMAL", "normal_layer_atlases")
	_assert_layer_draw_records(renderer, tileset_data, 1, "METATILE_LAYER_TYPE_COVERED", "covered_layer_atlases")
	_assert_layer_draw_records(renderer, tileset_data, 2, "METATILE_LAYER_TYPE_SPLIT", "split_layer_atlases")

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
