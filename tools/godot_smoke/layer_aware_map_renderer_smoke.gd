extends SceneTree

const DATA_REGISTRY_SCRIPT := preload("res://scripts/autoload/data_registry.gd")
const DEBUG_MAP_PLANE_SCRIPT := preload("res://scripts/overworld/debug_map_plane.gd")
const LAYER_RENDERER_SCRIPT := preload("res://scripts/overworld/layer_aware_map_renderer.gd")

const START_MAP := "MAP_LITTLEROOT_TOWN"


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
	_assert(String(contract.get("runtime_status", "")) == "owner_contract_only", "expected owner-contract runtime status")
	_assert(not bool(contract.get("source_equivalent_for_runtime_layering", true)), "expected layer rendering to stay non-equivalent")
	_assert(bool(contract.get("debug_fallback_active", false)), "expected debug fallback to be active")
	_assert(String(status.get("status", "")) == "owner_contract_only", "expected runtime owner-contract status")
	_assert(not bool(status.get("source_equivalent_for_runtime_layering", true)), "expected runtime status to stay non-equivalent")
	_assert(bool(status.get("debug_fallback_active", false)), "expected runtime status to expose active fallback")

	var layer_roles = contract.get("layer_roles", [])
	_assert(_has_id_record(layer_roles, "bottom"), "expected bottom layer role")
	_assert(_has_id_record(layer_roles, "middle"), "expected middle layer role")
	_assert(_has_id_record(layer_roles, "top"), "expected top layer role")
	_assert(_has_id_record(layer_roles, "object_depth"), "expected object-depth role")

	var required_inputs = contract.get("required_import_inputs", [])
	_assert(required_inputs.has("map_grid.raw"), "expected raw map-grid input requirement")
	_assert(required_inputs.has("border_grid"), "expected border-grid input requirement")
	_assert(required_inputs.has("connections"), "expected connection input requirement")
	_assert(required_inputs.has("metatile_entries.tile_entries"), "expected metatile entry input requirement")
	_assert(required_inputs.has("metatile_entries.attribute.layer_type"), "expected layer-type input requirement")
	_assert(required_inputs.has("door_animations"), "expected door animation input requirement")

	var layer_contract: Dictionary = contract.get("layer_rule_contract", {})
	_assert(String(layer_contract.get("normal", {}).get("top_source_slot_to_runtime_layer", "")) == "top", "expected normal top layer rule")
	_assert(String(layer_contract.get("covered", {}).get("top_source_slot_to_runtime_layer", "")) == "middle", "expected covered middle layer rule")
	_assert(String(layer_contract.get("split", {}).get("bottom_source_slot_to_runtime_layer", "")) == "bottom", "expected split bottom layer rule")

	var unsupported_codes := _unsupported_codes(contract.get("unsupported", []))
	_assert(unsupported_codes.has("source_equivalent_layer_renderer_pending"), "expected source-equivalent renderer gap")
	_assert(unsupported_codes.has("flattened_debug_atlas_not_source_equivalent"), "expected flattened atlas gap")
	_assert(unsupported_codes.has("object_depth_interleaving_pending"), "expected object-depth gap")
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
	quit(0)


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
	push_error(message)
	quit(1)
