extends Node

const OWNER_NAME := "TilesetAnimationPlayer"
const HEADER_REPORT_PATH := "res://data/generated/overworld/tileset_header_report.json"
const INITIALIZED_STATUS := "initialized_from_source_schedule_metadata"
const MISSING_REPORT_STATUS := "missing_tileset_header_report"
const MISSING_MAP_STATUS := "missing_map_data"
const RUNTIME_PLAYBACK_STATUS := "not_started_metadata_only_initialization"
const SOURCE_TRACE := [
	"src/overworld.c:InitMapView calls InitTilesetAnimations after map draw",
	"src/tileset_anims.c:InitTilesetAnimations resets primary and secondary callbacks",
	"src/tileset_anims.c:InitTilesetAnim_* selects counters and schedule callbacks",
	"src/overworld.c:OverworldBasic updates tileset animations each frame",
	"src/tileset_anims.c:TransferTilesetAnimsBuffer copies queued tile ranges",
	"data/generated/overworld/tileset_header_report.json",
]

var _data_registry: Node = null
var _map_runtime: Node = null
var _tileset_header_report: Dictionary = {}
var _headers_by_symbol: Dictionary = {}
var _tile_copy_appends_by_queue: Dictionary = {}
var _frame_strips_by_symbol: Dictionary = {}
var _last_initialization: Dictionary = {}
var _active_tileset_states: Array = []


func configure(data_registry: Node, map_runtime: Node = null) -> void:
	configure_data_registry(data_registry)
	if map_runtime != null:
		configure_map_runtime(map_runtime)


func configure_data_registry(data_registry: Node) -> void:
	_data_registry = data_registry
	_load_tileset_header_report()


func configure_map_runtime(map_runtime: Node) -> void:
	_map_runtime = map_runtime
	if _map_runtime == null or not _map_runtime.has_signal("map_changed"):
		return
	var callback := Callable(self, "_on_map_changed")
	if not _map_runtime.map_changed.is_connected(callback):
		_map_runtime.map_changed.connect(callback)


func initialize_for_map(
	map_data: Dictionary,
	tileset_data: Dictionary = {},
	map_size: Vector2i = Vector2i.ZERO
) -> Dictionary:
	_load_tileset_header_report()
	if map_data.is_empty():
		_last_initialization = _empty_initialization(MISSING_MAP_STATUS)
		_active_tileset_states = []
		return get_initialization_status()
	if _tileset_header_report.is_empty():
		_last_initialization = _empty_initialization(MISSING_REPORT_STATUS)
		_active_tileset_states = []
		return get_initialization_status()

	var map_info = map_data.get("map", {})
	if typeof(map_info) != TYPE_DICTIONARY:
		map_info = {}
	var layout_info = map_data.get("layout", {})
	if typeof(layout_info) != TYPE_DICTIONARY:
		layout_info = {}

	var resolved_size := map_size
	if resolved_size == Vector2i.ZERO:
		resolved_size = Vector2i(
			int(layout_info.get("width", 0)),
			int(layout_info.get("height", 0))
		)

	var primary_symbol := _tileset_symbol_for_role("primary", map_data, tileset_data)
	var secondary_symbol := _tileset_symbol_for_role("secondary", map_data, tileset_data)
	var roles := [
		_build_role_state("primary", primary_symbol),
		_build_role_state("secondary", secondary_symbol),
	]

	var initialized_count := 0
	var active_count := 0
	var schedule_event_count := 0
	var tile_copy_event_count := 0
	var tile_copy_append_count := 0
	var affected_tile_id_count := 0
	var affected_metatile_reference_count := 0
	var affected_unique_metatile_count := 0
	_active_tileset_states = []
	for role_state in roles:
		if typeof(role_state) != TYPE_DICTIONARY:
			continue
		if bool(role_state.get("initialized_on_map_load", false)):
			initialized_count += 1
		if bool(role_state.get("has_tile_animation_callback", false)):
			active_count += 1
			_active_tileset_states.append(role_state)
		schedule_event_count += int(role_state.get("schedule_event_count", 0))
		tile_copy_event_count += int(role_state.get("tile_copy_event_count", 0))
		tile_copy_append_count += int(role_state.get("tile_copy_append_count", 0))
		affected_tile_id_count += int(role_state.get("affected_tile_id_count", 0))
		affected_metatile_reference_count += int(role_state.get("affected_metatile_reference_count", 0))
		affected_unique_metatile_count += int(role_state.get("affected_unique_metatile_count", 0))

	_last_initialization = {
		"schema_version": 1,
		"owner": OWNER_NAME,
		"status": INITIALIZED_STATUS,
		"runtime_playback_status": RUNTIME_PLAYBACK_STATUS,
		"initialized_on_map_load": true,
		"source_equivalent_for_runtime_playback": false,
		"mutates_renderer": false,
		"mutates_map_data": false,
		"map_id": String(map_info.get("id", "")),
		"map_name": String(map_info.get("name", "")),
		"layout_id": String(layout_info.get("id", map_info.get("layout_id", ""))),
		"map_size": [resolved_size.x, resolved_size.y],
		"tileset_pair": {
			"primary": primary_symbol,
			"secondary": secondary_symbol,
		},
		"initialized_tileset_state_count": initialized_count,
		"active_tileset_state_count": active_count,
		"schedule_event_count": schedule_event_count,
		"tile_copy_event_count": tile_copy_event_count,
		"tile_copy_append_count": tile_copy_append_count,
		"affected_tile_id_count": affected_tile_id_count,
		"affected_metatile_reference_count": affected_metatile_reference_count,
		"affected_unique_metatile_count": affected_unique_metatile_count,
		"roles": roles,
		"unsupported": _unsupported_for_current_scope(active_count),
		"source_trace": SOURCE_TRACE,
	}
	return get_initialization_status()


func get_initialization_status() -> Dictionary:
	return _last_initialization.duplicate(true)


func get_active_tileset_states() -> Array:
	return _active_tileset_states.duplicate(true)


func get_tileset_state(role_or_symbol: String) -> Dictionary:
	var roles = _last_initialization.get("roles", [])
	if typeof(roles) != TYPE_ARRAY:
		return {}
	for role_state in roles:
		if typeof(role_state) != TYPE_DICTIONARY:
			continue
		if String(role_state.get("role", "")) == role_or_symbol:
			return role_state.duplicate(true)
		if String(role_state.get("tileset_symbol", "")) == role_or_symbol:
			return role_state.duplicate(true)
	return {}


func is_initialized() -> bool:
	return String(_last_initialization.get("status", "")) == INITIALIZED_STATUS


func _on_map_changed(map_data: Dictionary, tileset_data: Dictionary, map_size: Vector2i) -> void:
	initialize_for_map(map_data, tileset_data, map_size)


func _load_tileset_header_report() -> void:
	if not _tileset_header_report.is_empty():
		return
	if _data_registry != null and _data_registry.has_method("get_overworld_tileset_header_report"):
		var report = _data_registry.get_overworld_tileset_header_report()
		if typeof(report) == TYPE_DICTIONARY:
			_tileset_header_report = report
	if _tileset_header_report.is_empty() and FileAccess.file_exists(HEADER_REPORT_PATH):
		var file := FileAccess.open(HEADER_REPORT_PATH, FileAccess.READ)
		if file != null:
			var parsed = JSON.parse_string(file.get_as_text())
			if typeof(parsed) == TYPE_DICTIONARY:
				_tileset_header_report = parsed
	_index_report()


func _index_report() -> void:
	_headers_by_symbol = {}
	_tile_copy_appends_by_queue = {}
	_frame_strips_by_symbol = {}
	if _tileset_header_report.is_empty():
		return

	var headers = _tileset_header_report.get("tileset_headers", [])
	if typeof(headers) == TYPE_ARRAY:
		for header in headers:
			if typeof(header) != TYPE_DICTIONARY:
				continue
			var symbol := String(header.get("symbol", ""))
			if not symbol.is_empty():
				_headers_by_symbol[symbol] = header

	var schedule_trace = _tileset_header_report.get("tileset_animation_schedule_trace", {})
	if typeof(schedule_trace) == TYPE_DICTIONARY:
		var appends = schedule_trace.get("tile_copy_appends", [])
		if typeof(appends) == TYPE_ARRAY:
			for append_record in appends:
				if typeof(append_record) != TYPE_DICTIONARY:
					continue
				var queue_function := String(append_record.get("queue_function", ""))
				if queue_function.is_empty():
					continue
				if not _tile_copy_appends_by_queue.has(queue_function):
					_tile_copy_appends_by_queue[queue_function] = []
				_tile_copy_appends_by_queue[queue_function].append(append_record)

	var frame_strips = _tileset_header_report.get("tileset_animation_frame_strips", {})
	if typeof(frame_strips) == TYPE_DICTIONARY:
		var strips = frame_strips.get("strips", [])
		if typeof(strips) == TYPE_ARRAY:
			for strip in strips:
				if typeof(strip) != TYPE_DICTIONARY:
					continue
				var frame_symbol := String(strip.get("frame_symbol", ""))
				if not frame_symbol.is_empty():
					_frame_strips_by_symbol[frame_symbol] = strip


func _tileset_symbol_for_role(role: String, map_data: Dictionary, tileset_data: Dictionary) -> String:
	var layout_info = map_data.get("layout", {})
	if typeof(layout_info) == TYPE_DICTIONARY:
		var layout_symbol := String(layout_info.get("%s_tileset" % role, ""))
		if not layout_symbol.is_empty():
			return layout_symbol

	var map_tilesets = map_data.get("tilesets", {})
	var symbol := _tileset_symbol_from_bundle(map_tilesets, role)
	if not symbol.is_empty():
		return symbol

	var tileset_bundle = tileset_data.get("tilesets", {})
	symbol = _tileset_symbol_from_bundle(tileset_bundle, role)
	if not symbol.is_empty():
		return symbol
	return ""


func _tileset_symbol_from_bundle(bundle, role: String) -> String:
	if typeof(bundle) != TYPE_DICTIONARY:
		return ""
	var role_record = bundle.get(role, {})
	if typeof(role_record) == TYPE_DICTIONARY:
		return String(role_record.get("symbol", ""))
	return ""


func _build_role_state(role: String, tileset_symbol: String) -> Dictionary:
	var header = _headers_by_symbol.get(tileset_symbol, {})
	if typeof(header) != TYPE_DICTIONARY:
		header = {}
	var callback = header.get("callback", {})
	if typeof(callback) != TYPE_DICTIONARY:
		callback = {}
	var schedule_trace = callback.get("schedule_trace", {})
	if typeof(schedule_trace) != TYPE_DICTIONARY:
		schedule_trace = {}

	var event_records = callback.get("schedule_events", [])
	if typeof(event_records) != TYPE_ARRAY:
		event_records = []

	var schedule_events := []
	var tile_copy_append_count := 0
	var affected_tile_id_count := 0
	var affected_metatile_reference_count := 0
	var affected_unique_metatile_count := 0
	for event_record in event_records:
		if typeof(event_record) != TYPE_DICTIONARY:
			continue
		var event_state := _build_event_state(event_record)
		schedule_events.append(event_state)
		tile_copy_append_count += int(event_state.get("append_target_count", 0))
		affected_tile_id_count += int(event_state.get("affected_tile_id_count", 0))
		affected_metatile_reference_count += int(event_state.get("affected_metatile_reference_count", 0))
		affected_unique_metatile_count += int(event_state.get("affected_unique_metatile_count", 0))

	var has_callback := bool(callback.get("has_callback", false))
	var has_tile_animation_callback := bool(schedule_trace.get("has_tile_animation_callback", false))
	var event_callback := String(callback.get("schedule_event_callback_symbol", schedule_trace.get("callback_symbol", "")))
	if event_callback.is_empty():
		event_callback = String(schedule_trace.get("callback_symbol", ""))

	return {
		"role": role,
		"tileset_symbol": tileset_symbol,
		"header_found": not header.is_empty(),
		"callback_found": has_callback,
		"initialized_on_map_load": has_callback,
		"active_runtime_callback": false,
		"has_tile_animation_callback": has_tile_animation_callback,
		"runtime_playback_status": RUNTIME_PLAYBACK_STATUS,
		"init_function": String(callback.get("symbol", "")),
		"event_callback_symbol": event_callback,
		"counter_kind": String(schedule_trace.get("counter_kind", "")),
		"counter_symbol": String(schedule_trace.get("counter_symbol", "")),
		"counter_initial_expr": String(schedule_trace.get("counter_initial_expr", "")),
		"counter_initial_value": schedule_trace.get("counter_initial_value", null),
		"counter_max_symbol": String(schedule_trace.get("counter_max_symbol", "")),
		"counter_max_expr": String(schedule_trace.get("counter_max_expr", "")),
		"counter_max_value": schedule_trace.get("counter_max_value", null),
		"counter_max_source": String(schedule_trace.get("counter_max_source", "")),
		"wrap_behavior": String(schedule_trace.get("wrap_behavior", "")),
		"schedule_event_count": int(callback.get("schedule_event_count", schedule_events.size())),
		"tile_copy_event_count": int(callback.get("tile_copy_event_count", 0)),
		"tile_copy_append_count": tile_copy_append_count,
		"affected_tile_id_count": affected_tile_id_count,
		"affected_metatile_reference_count": affected_metatile_reference_count,
		"affected_unique_metatile_count": affected_unique_metatile_count,
		"schedule_events": schedule_events,
		"source": callback.get("source", {}),
	}


func _build_event_state(event_record: Dictionary) -> Dictionary:
	var queue_function := String(event_record.get("queue_function", ""))
	var append_targets := []
	var affected_tile_id_count := 0
	var affected_metatile_reference_count := 0
	var affected_unique_metatile_count := 0
	var append_records = _tile_copy_appends_by_queue.get(queue_function, [])
	if typeof(append_records) == TYPE_ARRAY:
		for append_record in append_records:
			if typeof(append_record) != TYPE_DICTIONARY:
				continue
			var append_state := _build_append_target_state(append_record)
			append_targets.append(append_state)
			affected_tile_id_count += int(append_state.get("affected_tile_id_count", 0))
			affected_metatile_reference_count += int(append_state.get("affected_metatile_reference_count", 0))
			affected_unique_metatile_count += int(append_state.get("affected_unique_metatile_count", 0))

	return {
		"callback": String(event_record.get("callback", "")),
		"event_index": int(event_record.get("event_index", -1)),
		"queue_function": queue_function,
		"kind": String(event_record.get("kind", "")),
		"trigger_modulo": int(event_record.get("trigger_modulo", 0)),
		"trigger_phase": int(event_record.get("trigger_phase", 0)),
		"duration_frames": int(event_record.get("duration_frames", 0)),
		"timer_argument_expr": String(event_record.get("timer_argument_expr", "")),
		"extra_argument_exprs": event_record.get("extra_argument_exprs", []),
		"source_append_count": int(event_record.get("append_count", 0)),
		"append_target_count": append_targets.size(),
		"affected_tile_id_count": affected_tile_id_count,
		"affected_metatile_reference_count": affected_metatile_reference_count,
		"affected_unique_metatile_count": affected_unique_metatile_count,
		"append_targets": append_targets,
	}


func _build_append_target_state(append_record: Dictionary) -> Dictionary:
	var affected = append_record.get("affected_metatiles", {})
	if typeof(affected) != TYPE_DICTIONARY:
		affected = {}
	var source_frame_symbols = append_record.get("source_frame_symbols", [])
	if typeof(source_frame_symbols) != TYPE_ARRAY:
		source_frame_symbols = []
	var tile_offsets = append_record.get("tile_offsets", [])
	if typeof(tile_offsets) != TYPE_ARRAY:
		tile_offsets = []
	var affected_tile_ids = affected.get("affected_tile_ids", [])
	if typeof(affected_tile_ids) != TYPE_ARRAY:
		affected_tile_ids = []

	return {
		"queue_function": String(append_record.get("queue_function", "")),
		"append_index": int(append_record.get("append_index", 0)),
		"source_array": String(append_record.get("source_array", "")),
		"source_expr": String(append_record.get("source_expr", "")),
		"source_frame_symbol_count": int(append_record.get("source_frame_symbol_count", source_frame_symbols.size())),
		"source_frame_symbols": source_frame_symbols.duplicate(true),
		"resolved_frame_strip_count": _resolved_frame_strip_count(source_frame_symbols),
		"dest_expr": String(append_record.get("dest_expr", "")),
		"dest_kind": String(append_record.get("dest_kind", "")),
		"vdest_array": append_record.get("vdest_array", null),
		"tile_offsets": tile_offsets.duplicate(true),
		"byte_count": int(append_record.get("byte_count", 0)),
		"tile_count": int(append_record.get("tile_count", 0)),
		"affected_tile_range_count": int(affected.get("affected_tile_range_count", 0)),
		"affected_tile_ranges": affected.get("affected_tile_ranges", []),
		"affected_tile_id_count": affected_tile_ids.size(),
		"affected_tile_ids_sample": _array_sample(affected_tile_ids, 16),
		"affected_metatile_reference_count": int(affected.get("affected_metatile_reference_count", 0)),
		"affected_unique_metatile_count": int(affected.get("affected_unique_metatile_count", 0)),
		"affected_metatile_samples": affected.get("samples", []),
	}


func _resolved_frame_strip_count(source_frame_symbols: Array) -> int:
	var resolved := 0
	for frame_symbol in source_frame_symbols:
		if _frame_strips_by_symbol.has(String(frame_symbol)):
			resolved += 1
	return resolved


func _array_sample(values: Array, limit: int) -> Array:
	var sample := []
	for index in range(min(limit, values.size())):
		sample.append(values[index])
	return sample


func _unsupported_for_current_scope(active_count: int) -> Array:
	var unsupported := [
		{
			"code": "tileset_animation_playback_pending",
			"status": "pending",
			"detail": "Map load initialization records source callbacks, events, frame strips, and copy targets; frame advancement is a later Section 6 task.",
			"active_callback_count": active_count,
		},
		{
			"code": "tileset_animation_independent_counters_pending",
			"status": "pending",
			"detail": "Primary and secondary counter advancement remains metadata-only until the next checklist item.",
		},
		{
			"code": "tileset_animation_transition_pause_reset_pending",
			"status": "pending",
			"detail": "Pause/reset rules across map transitions are not applied by this initializer.",
		},
		{
			"code": "tileset_animation_renderer_tile_update_pending",
			"status": "pending",
			"detail": "The initializer does not mutate atlases, TileMaps, or map data.",
		},
	]
	return unsupported


func _empty_initialization(status: String) -> Dictionary:
	return {
		"schema_version": 1,
		"owner": OWNER_NAME,
		"status": status,
		"runtime_playback_status": RUNTIME_PLAYBACK_STATUS,
		"initialized_on_map_load": false,
		"source_equivalent_for_runtime_playback": false,
		"mutates_renderer": false,
		"mutates_map_data": false,
		"roles": [],
		"unsupported": _unsupported_for_current_scope(0),
		"source_trace": SOURCE_TRACE,
	}
