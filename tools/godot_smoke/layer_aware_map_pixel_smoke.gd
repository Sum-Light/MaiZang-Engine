extends SceneTree

const DATA_REGISTRY_SCRIPT := preload("res://scripts/autoload/data_registry.gd")
const LAYER_RENDERER_SCRIPT := preload("res://scripts/overworld/layer_aware_map_renderer.gd")

const MAP_LITTLEROOT := "MAP_LITTLEROOT_TOWN"
const MAP_ROUTE101 := "MAP_ROUTE101"
const MAP_BRENDAN_HOUSE_1F := "MAP_LITTLEROOT_TOWN_BRENDANS_HOUSE_1F"
const TILE_SIZE := 16
const NORMAL_LAYER_TYPE := 0
const SPLIT_LAYER_TYPE := 2
const PROBE_COLOR := Color(1.0, 0.0, 1.0, 1.0)
const COLOR_EPSILON := 0.035

var _failed := false
var _registry: Node = null
var _case_summaries := []
var _image_cache := {}


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_registry = DATA_REGISTRY_SCRIPT.new()
	_registry._ready()

	var cases := [
		_cell_top_cover_case(
			MAP_LITTLEROOT,
			"littleroot_house_roof_top",
			Vector2i(3, 4),
			"roof",
			"top layer must cover sprites"
		),
		_bg_event_middle_case(
			MAP_LITTLEROOT,
			"littleroot_sign_middle",
			"sign",
			"sign/event metatile should stay below sprites in this source map"
		),
		_behavior_middle_case(
			MAP_ROUTE101,
			"route101_tall_grass_middle",
			["MB_TALL_GRASS"],
			"grass_cover",
			"tall grass base pixels must not be promoted to top layer"
		),
		_synthetic_split_top_case(
			MAP_LITTLEROOT,
			"split_bridge_like_top",
			"bridge_like_split",
			"split metatile top half must cover sprites"
		),
		_cell_top_cover_case(
			MAP_BRENDAN_HOUSE_1F,
			"brendan_house_indoor_top_object",
			Vector2i(4, 3),
			"indoor_top_object",
			"indoor top layer must cover sprites"
		),
	]
	if _failed:
		return

	for case in cases:
		_assert_case_pixels(case)
		if _failed:
			return
		_case_summaries.append(_case_summary(case))

	print(JSON.stringify({
		"layer_aware_map_pixel_smoke": "ok",
		"case_count": _case_summaries.size(),
		"cases": _case_summaries,
		"pixel_path": "headless_layer_atlas_composition",
		"source_trace": [
			"src/field_camera.c:DrawMetatile",
			"include/global.fieldmap.h:METATILE_LAYER_TYPE_*",
		],
	}))
	_registry.free()
	quit(0)


func _assert_case_pixels(case: Dictionary) -> void:
	_assert_renderer_depth_contract(case)
	var expectation := String(case.get("expectation", ""))
	var all_pixel := _compose_case_pixel(case, "all", true)
	var top_pixel := _compose_case_pixel(case, "top", true)
	var middle_pixel := _compose_case_pixel(case, "middle", true)
	var bottom_pixel := _compose_case_pixel(case, "bottom", true)

	if expectation == "top_covers_sprite":
		_assert(not _colors_close(all_pixel, PROBE_COLOR), "%s expected all-layer pixel to be top layer, not probe" % case.get("id", "case"))
		_assert(not _colors_close(top_pixel, PROBE_COLOR), "%s expected top-only pixel to cover probe" % case.get("id", "case"))
		_assert(_colors_close(middle_pixel, PROBE_COLOR), "%s expected middle-only pixel to leave probe visible" % case.get("id", "case"))
		_assert(_colors_close(bottom_pixel, PROBE_COLOR), "%s expected bottom-only pixel to leave probe visible" % case.get("id", "case"))
		_assert(_colors_close(all_pixel, top_pixel), "%s expected all-layer and top-only pixels to match" % case.get("id", "case"))
		return

	if expectation == "sprite_visible_over_middle":
		var middle_without_probe := _compose_case_pixel(case, "middle", false)
		_assert(_colors_close(all_pixel, PROBE_COLOR), "%s expected all-layer pixel to leave probe over middle role" % case.get("id", "case"))
		_assert(_colors_close(top_pixel, PROBE_COLOR), "%s expected top-only pixel to have no top cover" % case.get("id", "case"))
		_assert(_colors_close(middle_pixel, PROBE_COLOR), "%s expected middle-only pixel to leave probe visible" % case.get("id", "case"))
		_assert(_colors_close(bottom_pixel, PROBE_COLOR), "%s expected bottom-only pixel to leave probe visible" % case.get("id", "case"))
		_assert(not _colors_close(middle_without_probe, PROBE_COLOR), "%s expected middle role to render a real source pixel without probe" % case.get("id", "case"))
		_assert(middle_without_probe.a > 0.1, "%s expected middle role source pixel to be opaque" % case.get("id", "case"))
		return

	_assert(false, "%s has unsupported pixel expectation %s" % [case.get("id", "case"), expectation])


func _assert_renderer_depth_contract(case: Dictionary) -> void:
	var renderer = LAYER_RENDERER_SCRIPT.new()
	renderer.configure_data_registry(_registry)
	renderer.configure_from_map_data(case.get("map_data", {}), case.get("tileset_data", {}))
	var cell: Vector2i = case.get("cell", Vector2i.ZERO)
	var depth: Dictionary = renderer.get_sprite_depth_record(cell, 3, 0)
	var object_depth: Dictionary = renderer.get_object_depth_interleave_status()
	var runtime_z_bands: Dictionary = object_depth.get("runtime_z_bands", {})
	_assert(
		int(depth.get("godot_z_index", 0)) > int(runtime_z_bands.get("between_middle_and_top", 0)),
		"%s expected probe z-index above bottom/middle band" % case.get("id", "case")
	)
	_assert(
		int(depth.get("godot_z_index", 0)) < int(runtime_z_bands.get("top", 0)),
		"%s expected probe z-index below top band" % case.get("id", "case")
	)
	var contract: Dictionary = renderer.get_renderer_contract()
	var overlay: Dictionary = contract.get("top_layer_overlay", {})
	_assert(
		int(overlay.get("godot_z_index", 0)) == int(runtime_z_bands.get("top", 0)),
		"%s expected renderer top overlay z-index to match top band" % case.get("id", "case")
	)
	renderer.free()


func _compose_case_pixel(case: Dictionary, layer_mode: String, include_probe: bool) -> Color:
	var sample: Vector2i = case.get("sample", Vector2i.ZERO)
	var pixel := Color(0.0, 0.0, 0.0, 0.0)
	for role in _visible_base_roles(layer_mode):
		pixel = _blend_over(_role_pixel(case, role, sample), pixel)
	if include_probe:
		pixel = _blend_over(PROBE_COLOR, pixel)
	if _role_visible(layer_mode, "top"):
		pixel = _blend_over(_role_pixel(case, "top", sample), pixel)
	return pixel


func _visible_base_roles(layer_mode: String) -> Array:
	if layer_mode == "all":
		return ["bottom", "middle"]
	if layer_mode == "bottom":
		return ["bottom"]
	if layer_mode == "middle":
		return ["middle"]
	return []


func _role_visible(layer_mode: String, role: String) -> bool:
	return layer_mode == "all" or layer_mode == role


func _role_pixel(case: Dictionary, role: String, sample: Vector2i) -> Color:
	var tileset_data: Dictionary = case.get("tileset_data", {})
	var entry := _metatile_entry(tileset_data, int(case.get("metatile_id", -1)))
	var rect := _role_atlas_rect(entry, role)
	if rect.size == Vector2i.ZERO:
		return Color(0.0, 0.0, 0.0, 0.0)
	var images := _load_layer_images(tileset_data)
	var image: Image = images.get(role, null)
	if image == null:
		return Color(0.0, 0.0, 0.0, 0.0)
	return image.get_pixel(rect.position.x + sample.x, rect.position.y + sample.y)


func _blend_over(source: Color, destination: Color) -> Color:
	if source.a <= 0.0:
		return destination
	if source.a >= 1.0:
		return source
	var out_alpha := source.a + destination.a * (1.0 - source.a)
	if out_alpha <= 0.0:
		return Color(0.0, 0.0, 0.0, 0.0)
	return Color(
		(source.r * source.a + destination.r * destination.a * (1.0 - source.a)) / out_alpha,
		(source.g * source.a + destination.g * destination.a * (1.0 - source.a)) / out_alpha,
		(source.b * source.a + destination.b * destination.a * (1.0 - source.a)) / out_alpha,
		out_alpha
	)


func _cell_top_cover_case(
	map_id: String,
	case_id: String,
	cell: Vector2i,
	focus: String,
	note: String
) -> Dictionary:
	var pair := _load_pair(map_id)
	var metatile_id := _metatile_at_cell(pair.get("map_data", {}), cell)
	var images := _load_layer_images(pair.get("tileset_data", {}))
	var sample := _first_role_sample(pair.get("tileset_data", {}), images, metatile_id, "top")
	_assert(not sample.is_empty(), "%s expected an opaque top-layer source pixel" % case_id)
	return _case_record(pair, case_id, cell, metatile_id, sample, "top_covers_sprite", focus, note, false)


func _bg_event_middle_case(map_id: String, case_id: String, focus: String, note: String) -> Dictionary:
	var pair := _load_pair(map_id)
	var map_data: Dictionary = pair.get("map_data", {})
	var tileset_data: Dictionary = pair.get("tileset_data", {})
	var images := _load_layer_images(tileset_data)
	var bg_events = map_data.get("events", {}).get("bg_events", [])
	if typeof(bg_events) == TYPE_ARRAY:
		for event_data in bg_events:
			if typeof(event_data) != TYPE_DICTIONARY:
				continue
			var cell := Vector2i(int(event_data.get("x", -1)), int(event_data.get("y", -1)))
			var metatile_id := _metatile_at_cell(map_data, cell)
			var sample := _first_role_sample(tileset_data, images, metatile_id, "middle", ["top"])
			if not sample.is_empty():
				return _case_record(pair, case_id, cell, metatile_id, sample, "sprite_visible_over_middle", focus, note, false)
	_assert(false, "%s expected a BG/sign event metatile with middle pixels and no top pixel at sample" % case_id)
	return {}


func _behavior_middle_case(
	map_id: String,
	case_id: String,
	behavior_names: Array,
	focus: String,
	note: String
) -> Dictionary:
	var pair := _load_pair(map_id)
	var map_data: Dictionary = pair.get("map_data", {})
	var tileset_data: Dictionary = pair.get("tileset_data", {})
	var images := _load_layer_images(tileset_data)
	var rows = map_data.get("block_ids", [])
	if typeof(rows) == TYPE_ARRAY:
		for y in range(rows.size()):
			var row = rows[y]
			if typeof(row) != TYPE_ARRAY:
				continue
			for x in range(row.size()):
				var metatile_id := int(row[x])
				var entry := _metatile_entry(tileset_data, metatile_id)
				var behavior := String(entry.get("attribute", {}).get("behavior_name", ""))
				if not behavior_names.has(behavior):
					continue
				var sample := _first_role_sample(tileset_data, images, metatile_id, "middle", ["top"])
				if not sample.is_empty():
					return _case_record(pair, case_id, Vector2i(x, y), metatile_id, sample, "sprite_visible_over_middle", focus, note, false)
	_assert(false, "%s expected a behavior-backed middle-layer metatile" % case_id)
	return {}


func _synthetic_split_top_case(map_id: String, case_id: String, focus: String, note: String) -> Dictionary:
	var pair := _load_pair(map_id)
	var tileset_data: Dictionary = pair.get("tileset_data", {})
	var images := _load_layer_images(tileset_data)
	var entries = tileset_data.get("metatile_entries", [])
	if typeof(entries) == TYPE_ARRAY:
		for entry in entries:
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			var metatile_id := int(entry.get("id", -1))
			var layer_type := int(entry.get("attribute", {}).get("layer_type", -1))
			if layer_type != SPLIT_LAYER_TYPE:
				continue
			var sample := _first_role_sample(tileset_data, images, metatile_id, "top")
			if sample.is_empty():
				continue
			var synthetic_pair := pair.duplicate(true)
			synthetic_pair["map_data"] = {
				"schema_version": 1,
				"map": {
					"id": "%s_SYNTHETIC_SPLIT_PIXEL_SMOKE" % map_id,
					"source_map_id": map_id,
				},
				"layout": {
					"width": 1,
					"height": 1,
				},
				"block_ids": [
					[metatile_id],
				],
			}
			return _case_record(synthetic_pair, case_id, Vector2i.ZERO, metatile_id, sample, "top_covers_sprite", focus, note, true)
	_assert(false, "%s expected a split metatile with opaque top-layer pixels" % case_id)
	return {}


func _case_record(
	pair: Dictionary,
	case_id: String,
	cell: Vector2i,
	metatile_id: int,
	sample: Dictionary,
	expectation: String,
	focus: String,
	note: String,
	is_synthetic: bool
) -> Dictionary:
	var tileset_data: Dictionary = pair.get("tileset_data", {})
	var entry := _metatile_entry(tileset_data, metatile_id)
	return {
		"id": case_id,
		"map_id": pair.get("map_id", ""),
		"map_data": pair.get("map_data", {}),
		"tileset_data": tileset_data,
		"cell": cell,
		"metatile_id": metatile_id,
		"sample": Vector2i(int(sample.get("x", 0)), int(sample.get("y", 0))),
		"sample_role": String(sample.get("role", "")),
		"expectation": expectation,
		"focus": focus,
		"note": note,
		"synthetic_map": is_synthetic,
		"behavior_name": String(entry.get("attribute", {}).get("behavior_name", "")),
		"source_layer_type": int(entry.get("attribute", {}).get("layer_type", -1)),
		"labels": _label_names_for_metatile(tileset_data, metatile_id),
	}


func _case_summary(case: Dictionary) -> Dictionary:
	var sample: Vector2i = case.get("sample", Vector2i.ZERO)
	var cell: Vector2i = case.get("cell", Vector2i.ZERO)
	return {
		"id": String(case.get("id", "")),
		"map_id": String(case.get("map_id", "")),
		"cell": [cell.x, cell.y],
		"metatile_id": int(case.get("metatile_id", -1)),
		"source_layer_type": int(case.get("source_layer_type", -1)),
		"behavior_name": String(case.get("behavior_name", "")),
		"focus": String(case.get("focus", "")),
		"sample": [sample.x, sample.y],
		"sample_role": String(case.get("sample_role", "")),
		"expectation": String(case.get("expectation", "")),
		"synthetic_map": bool(case.get("synthetic_map", false)),
		"labels": case.get("labels", []),
	}


func _load_pair(map_id: String) -> Dictionary:
	var map_data: Dictionary = _registry.get_map_data(map_id, {
		"include_debug_overlays": true,
	})
	var tileset_data: Dictionary = _registry.get_tileset_data_for_map(map_id)
	_assert(not map_data.is_empty(), "expected map data for %s" % map_id)
	_assert(not tileset_data.is_empty(), "expected tileset data for %s" % map_id)
	return {
		"map_id": map_id,
		"map_data": map_data,
		"tileset_data": tileset_data,
	}


func _load_layer_images(tileset_data: Dictionary) -> Dictionary:
	var result := {}
	var layer_atlases = tileset_data.get("layer_rendering", {}).get("layer_atlases", {})
	_assert(typeof(layer_atlases) == TYPE_DICTIONARY, "expected layer atlas metadata")
	for role in ["bottom", "middle", "top"]:
		var record = layer_atlases.get(role, {})
		_assert(typeof(record) == TYPE_DICTIONARY, "expected %s layer atlas record" % role)
		var path := _image_record_path(record)
		if not _image_cache.has(path):
			var image := Image.new()
			var err := image.load(path)
			_assert(err == OK, "expected %s layer atlas image to load" % role)
			_image_cache[path] = image
		result[role] = _image_cache[path]
	return result


func _image_record_path(record: Dictionary) -> String:
	var path := String(record.get("image", ""))
	if path.is_empty():
		path = String(record.get("image_project_path", ""))
	if path.begins_with("res://"):
		return ProjectSettings.globalize_path(path)
	return ProjectSettings.globalize_path("res://%s" % path.replace("\\", "/"))


func _metatile_at_cell(map_data: Dictionary, cell: Vector2i) -> int:
	var rows = map_data.get("block_ids", [])
	if typeof(rows) != TYPE_ARRAY or cell.y < 0 or cell.y >= rows.size():
		return -1
	var row = rows[cell.y]
	if typeof(row) != TYPE_ARRAY or cell.x < 0 or cell.x >= row.size():
		return -1
	return int(row[cell.x])


func _metatile_entry(tileset_data: Dictionary, metatile_id: int) -> Dictionary:
	var entries = tileset_data.get("metatile_entries", [])
	if typeof(entries) != TYPE_ARRAY:
		return {}
	if metatile_id >= 0 and metatile_id < entries.size():
		var indexed = entries[metatile_id]
		if typeof(indexed) == TYPE_DICTIONARY and int(indexed.get("id", -1)) == metatile_id:
			return indexed
	for entry in entries:
		if typeof(entry) == TYPE_DICTIONARY and int(entry.get("id", -1)) == metatile_id:
			return entry
	return {}


func _first_role_sample(
	tileset_data: Dictionary,
	images: Dictionary,
	metatile_id: int,
	role: String,
	absent_roles: Array = []
) -> Dictionary:
	var entry := _metatile_entry(tileset_data, metatile_id)
	if entry.is_empty():
		return {}
	var rect := _role_atlas_rect(entry, role)
	if rect.size == Vector2i.ZERO:
		return {}
	var image: Image = images.get(role, null)
	if image == null:
		return {}
	for y in range(rect.size.y):
		for x in range(rect.size.x):
			var pixel := image.get_pixel(rect.position.x + x, rect.position.y + y)
			if pixel.a <= 0.01:
				continue
			if not _roles_absent_at_local(entry, images, absent_roles, Vector2i(x, y)):
				continue
			return {
				"x": x,
				"y": y,
				"role": role,
				"atlas_pixel_rgba": [pixel.r, pixel.g, pixel.b, pixel.a],
			}
	return {}


func _roles_absent_at_local(entry: Dictionary, images: Dictionary, roles: Array, local: Vector2i) -> bool:
	for role in roles:
		var rect := _role_atlas_rect(entry, String(role))
		if rect.size == Vector2i.ZERO:
			continue
		var image: Image = images.get(String(role), null)
		if image == null:
			continue
		if image.get_pixel(rect.position.x + local.x, rect.position.y + local.y).a > 0.01:
			return false
	return true


func _role_atlas_rect(entry: Dictionary, role: String) -> Rect2i:
	var atlas = entry.get("render_layers", {}).get("layers", {}).get(role, {}).get("atlas", {})
	if typeof(atlas) != TYPE_DICTIONARY:
		return Rect2i()
	return Rect2i(
		int(atlas.get("x", 0)),
		int(atlas.get("y", 0)),
		int(atlas.get("w", 0)),
		int(atlas.get("h", 0))
	)


func _label_names_for_metatile(tileset_data: Dictionary, metatile_id: int) -> Array:
	var result := []
	var entries = tileset_data.get("metatile_labels", {}).get("entries", [])
	if typeof(entries) != TYPE_ARRAY:
		return result
	for record in entries:
		if typeof(record) != TYPE_DICTIONARY:
			continue
		if int(record.get("id", -1)) == metatile_id:
			result.append(String(record.get("name", "")))
	return result


func _colors_close(a: Color, b: Color) -> bool:
	return (
		abs(a.r - b.r) <= COLOR_EPSILON
		and abs(a.g - b.g) <= COLOR_EPSILON
		and abs(a.b - b.b) <= COLOR_EPSILON
		and abs(a.a - b.a) <= COLOR_EPSILON
	)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true
	quit(1)
