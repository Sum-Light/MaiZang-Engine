extends Node

const OWNER_NAME := "TilesetAnimationPlayer"
const HEADER_REPORT_PATH := "res://data/generated/overworld/tileset_header_report.json"
const INITIALIZED_STATUS := "initialized_from_source_schedule_metadata"
const MISSING_REPORT_STATUS := "missing_tileset_header_report"
const MISSING_MAP_STATUS := "missing_map_data"
const RUNTIME_PLAYBACK_STATUS := "counter_playback_metadata_only_no_renderer_updates"
const RENDERER_UPDATE_STATUS := "renderer_tile_updates_pending"
const SOURCE_TRACE := [
	"src/overworld.c:InitMapView calls InitTilesetAnimations after map draw",
	"src/tileset_anims.c:InitTilesetAnimations resets primary and secondary callbacks",
	"src/tileset_anims.c:InitTilesetAnim_* selects counters and schedule callbacks",
	"src/overworld.c:OverworldBasic updates tileset animations each frame",
	"src/tileset_anims.c:UpdateTilesetAnimations increments primary and secondary counters before callbacks",
	"src/tileset_anims.c:TransferTilesetAnimsBuffer copies queued tile ranges",
	"data/generated/overworld/tileset_header_report.json",
]
const COUNTER_STATUS := "source_order_independent_counters"

var _data_registry: Node = null
var _map_runtime: Node = null
var _tileset_header_report: Dictionary = {}
var _headers_by_symbol: Dictionary = {}
var _tile_copy_appends_by_queue: Dictionary = {}
var _frame_strips_by_symbol: Dictionary = {}
var _last_initialization: Dictionary = {}
var _last_frame_update: Dictionary = {}
var _active_tileset_states: Array = []
var _runtime_frames_elapsed := 0
var _current_map_key := ""


func _process(_delta: float) -> void:
	if is_initialized():
		advance_frame()


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
	_resolve_role_runtime_counters(roles)

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

	_runtime_frames_elapsed = 0
	_last_frame_update = {}
	_current_map_key = _map_key_for(map_data, tileset_data)
	_last_initialization = {
		"schema_version": 1,
		"owner": OWNER_NAME,
		"status": INITIALIZED_STATUS,
		"runtime_playback_status": RUNTIME_PLAYBACK_STATUS,
		"counter_status": COUNTER_STATUS,
		"runtime_frames_elapsed": _runtime_frames_elapsed,
		"initialized_on_map_load": true,
		"source_equivalent_for_runtime_playback": false,
		"source_equivalent_for_runtime_counter_order": true,
		"mutates_renderer": false,
		"mutates_map_data": false,
		"map_key": _current_map_key,
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
		"runtime_counters": _build_counter_status_from_roles(roles),
		"last_frame_update": {},
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


func get_counter_status() -> Dictionary:
	var status = _last_initialization.get("runtime_counters", {})
	return status.duplicate(true) if typeof(status) == TYPE_DICTIONARY else {}


func get_last_frame_update() -> Dictionary:
	return _last_frame_update.duplicate(true)


func advance_frame() -> Dictionary:
	return _advance_one_frame()


func advance_frames(frame_count: int) -> Dictionary:
	if frame_count <= 0:
		return {
			"status": "no_op",
			"frames_advanced": 0,
			"runtime_frames_elapsed": _runtime_frames_elapsed,
			"counter_status": get_counter_status(),
			"last_frame_update": get_last_frame_update(),
		}

	var event_frame_count := 0
	var total_event_count := 0
	var total_tile_copy_request_count := 0
	var first_event_frame := {}
	var last_event_frame := {}
	for _index in range(frame_count):
		var frame_update := _advance_one_frame()
		var event_count := int(frame_update.get("event_count", 0))
		if event_count > 0:
			event_frame_count += 1
			total_event_count += event_count
			total_tile_copy_request_count += int(frame_update.get("tile_copy_request_count", 0))
			if first_event_frame.is_empty():
				first_event_frame = frame_update
			last_event_frame = frame_update

	return {
		"status": "advanced",
		"frames_advanced": frame_count,
		"runtime_frames_elapsed": _runtime_frames_elapsed,
		"event_frame_count": event_frame_count,
		"total_event_count": total_event_count,
		"total_tile_copy_request_count": total_tile_copy_request_count,
		"first_event_frame": first_event_frame,
		"last_event_frame": last_event_frame,
		"last_frame_update": get_last_frame_update(),
		"counter_status": get_counter_status(),
	}


func is_initialized() -> bool:
	return String(_last_initialization.get("status", "")) == INITIALIZED_STATUS


func _on_map_changed(map_data: Dictionary, tileset_data: Dictionary, map_size: Vector2i) -> void:
	var next_map_key := _map_key_for(map_data, tileset_data)
	if is_initialized() and not next_map_key.is_empty() and next_map_key == _current_map_key:
		_last_initialization["last_map_changed_status"] = "same_map_update_preserved_tileset_animation_counters"
		return
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


func _map_key_for(map_data: Dictionary, tileset_data: Dictionary) -> String:
	var map_info = map_data.get("map", {})
	if typeof(map_info) != TYPE_DICTIONARY:
		map_info = {}
	var layout_info = map_data.get("layout", {})
	if typeof(layout_info) != TYPE_DICTIONARY:
		layout_info = {}
	var map_id := String(map_info.get("id", ""))
	var layout_id := String(layout_info.get("id", map_info.get("layout_id", "")))
	var primary_symbol := _tileset_symbol_for_role("primary", map_data, tileset_data)
	var secondary_symbol := _tileset_symbol_for_role("secondary", map_data, tileset_data)
	return "%s|%s|%s|%s" % [map_id, layout_id, primary_symbol, secondary_symbol]


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
		"active_runtime_callback": has_tile_animation_callback,
		"has_tile_animation_callback": has_tile_animation_callback,
		"runtime_playback_status": RUNTIME_PLAYBACK_STATUS,
		"renderer_update_status": RENDERER_UPDATE_STATUS,
		"init_function": String(callback.get("symbol", "")),
		"event_callback_symbol": event_callback,
		"counter_kind": String(schedule_trace.get("counter_kind", "")),
		"counter_symbol": String(schedule_trace.get("counter_symbol", "")),
		"counter_initial_expr": String(schedule_trace.get("counter_initial_expr", "")),
		"counter_initial_value": schedule_trace.get("counter_initial_value", null),
		"runtime_counter_initial_value": null,
		"runtime_counter_value": null,
		"counter_max_symbol": String(schedule_trace.get("counter_max_symbol", "")),
		"counter_max_expr": String(schedule_trace.get("counter_max_expr", "")),
		"counter_max_value": schedule_trace.get("counter_max_value", null),
		"runtime_counter_max_value": null,
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


func _resolve_role_runtime_counters(roles: Array) -> void:
	var primary_state := _role_state_for(roles, "primary")
	var primary_initial := _literal_or_default(primary_state.get("counter_initial_value", null), 0)
	var primary_max := _literal_or_default(primary_state.get("counter_max_value", null), 0)
	if not primary_state.is_empty():
		primary_state["runtime_counter_initial_value"] = primary_initial
		primary_state["runtime_counter_value"] = primary_initial
		primary_state["runtime_counter_max_value"] = primary_max
		primary_state["counter_resolved_from"] = "literal_or_expression"
		primary_state["counter_wrap_enabled"] = primary_max > 0

	for role_state in roles:
		if typeof(role_state) != TYPE_DICTIONARY or String(role_state.get("role", "")) == "primary":
			continue
		var initial_expr := String(role_state.get("counter_initial_expr", ""))
		var max_expr := String(role_state.get("counter_max_expr", ""))
		var initial_value := _literal_or_default(role_state.get("counter_initial_value", null), 0)
		var max_value := _literal_or_default(role_state.get("counter_max_value", null), 0)
		var resolved_from := "literal_or_expression"
		if initial_expr == "sPrimaryTilesetAnimCounter":
			initial_value = primary_initial
			resolved_from = "inherits_primary_counter"
		if max_expr == "sPrimaryTilesetAnimCounterMax":
			max_value = primary_max
			resolved_from = "inherits_primary_counter_max"
		role_state["runtime_counter_initial_value"] = initial_value
		role_state["runtime_counter_value"] = initial_value
		role_state["runtime_counter_max_value"] = max_value
		role_state["counter_resolved_from"] = resolved_from
		role_state["counter_wrap_enabled"] = max_value > 0


func _role_state_for(roles: Array, role: String) -> Dictionary:
	for role_state in roles:
		if typeof(role_state) == TYPE_DICTIONARY and String(role_state.get("role", "")) == role:
			return role_state
	return {}


func _literal_or_default(value, fallback: int) -> int:
	if value == null:
		return fallback
	if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
		return int(value)
	return fallback


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
		"source_callback_order": "primary_then_secondary",
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


func _advance_one_frame() -> Dictionary:
	if not is_initialized():
		_last_frame_update = {
			"status": "not_initialized",
			"runtime_frames_elapsed": _runtime_frames_elapsed,
			"events": [],
			"source_trace": SOURCE_TRACE,
		}
		return get_last_frame_update()

	var roles = _last_initialization.get("roles", [])
	if typeof(roles) != TYPE_ARRAY:
		roles = []
	_runtime_frames_elapsed += 1

	var frame_events := []
	var tile_copy_request_count := 0
	var role_counter_updates := []
	for role_state in roles:
		if typeof(role_state) != TYPE_DICTIONARY:
			continue
		var before := int(role_state.get("runtime_counter_value", 0))
		var counter_max := int(role_state.get("runtime_counter_max_value", 0))
		var after := before + 1
		var wrapped := false
		if counter_max > 0 and after >= counter_max:
			after = 0
			wrapped = true
		role_state["runtime_counter_value"] = after
		role_state["last_counter_before_increment"] = before
		role_state["last_counter_after_increment"] = after
		role_state["last_counter_wrapped"] = wrapped
		role_state["runtime_frames_elapsed"] = _runtime_frames_elapsed
		role_counter_updates.append({
			"role": String(role_state.get("role", "")),
			"tileset_symbol": String(role_state.get("tileset_symbol", "")),
			"counter_before_increment": before,
			"counter_after_increment": after,
			"counter_max_value": counter_max,
			"wrapped": wrapped,
			"has_tile_animation_callback": bool(role_state.get("has_tile_animation_callback", false)),
		})
	for role_state in roles:
		if typeof(role_state) != TYPE_DICTIONARY:
			continue
		if bool(role_state.get("has_tile_animation_callback", false)):
			var triggered := _triggered_events_for_role(role_state, int(role_state.get("runtime_counter_value", 0)))
			for event_update in triggered:
				frame_events.append(event_update)
				tile_copy_request_count += int(event_update.get("tile_copy_request_count", 0))

	_last_frame_update = {
		"schema_version": 1,
		"owner": OWNER_NAME,
		"status": "advanced_frame",
		"runtime_playback_status": RUNTIME_PLAYBACK_STATUS,
		"renderer_update_status": RENDERER_UPDATE_STATUS,
		"runtime_frames_elapsed": _runtime_frames_elapsed,
		"source_update_order": "reset_buffer_increment_primary_increment_secondary_call_primary_call_secondary",
		"source_equivalent_for_runtime_counter_order": true,
		"source_equivalent_for_renderer_updates": false,
		"mutates_renderer": false,
		"mutates_map_data": false,
		"event_count": frame_events.size(),
		"tile_copy_request_count": tile_copy_request_count,
		"role_counter_updates": role_counter_updates,
		"events": frame_events,
		"counter_status": _build_counter_status_from_roles(roles),
		"source_trace": SOURCE_TRACE,
	}
	_last_initialization["runtime_frames_elapsed"] = _runtime_frames_elapsed
	_last_initialization["runtime_counters"] = _last_frame_update["counter_status"].duplicate(true)
	_last_initialization["last_frame_update"] = _last_frame_update.duplicate(true)
	return get_last_frame_update()


func _triggered_events_for_role(role_state: Dictionary, counter_value: int) -> Array:
	var triggered := []
	var schedule_events = role_state.get("schedule_events", [])
	if typeof(schedule_events) != TYPE_ARRAY:
		return triggered
	for event_state in schedule_events:
		if typeof(event_state) != TYPE_DICTIONARY:
			continue
		var trigger_modulo := int(event_state.get("trigger_modulo", 0))
		if trigger_modulo <= 0:
			continue
		var trigger_phase := int(event_state.get("trigger_phase", 0))
		if counter_value % trigger_modulo != trigger_phase:
			continue
		triggered.append(_build_runtime_event_update(role_state, event_state, counter_value))
	return triggered


func _build_runtime_event_update(role_state: Dictionary, event_state: Dictionary, counter_value: int) -> Dictionary:
	var timer_argument := _source_timer_argument(counter_value, event_state)
	var append_targets = event_state.get("append_targets", [])
	if typeof(append_targets) != TYPE_ARRAY:
		append_targets = []
	var tile_copy_requests := []
	for append_target in append_targets:
		if typeof(append_target) != TYPE_DICTIONARY:
			continue
		tile_copy_requests.append({
			"queue_function": String(append_target.get("queue_function", "")),
			"append_index": int(append_target.get("append_index", 0)),
			"source_array": String(append_target.get("source_array", "")),
			"source_expr": String(append_target.get("source_expr", "")),
			"timer_argument": timer_argument,
			"selected_source_frame_index": _selected_source_frame_index(timer_argument, append_target),
			"source_frame_symbol_count": int(append_target.get("source_frame_symbol_count", 0)),
			"resolved_frame_strip_count": int(append_target.get("resolved_frame_strip_count", 0)),
			"dest_expr": String(append_target.get("dest_expr", "")),
			"dest_kind": String(append_target.get("dest_kind", "")),
			"tile_offsets": append_target.get("tile_offsets", []),
			"tile_count": int(append_target.get("tile_count", 0)),
			"byte_count": int(append_target.get("byte_count", 0)),
			"affected_tile_ranges": append_target.get("affected_tile_ranges", []),
			"affected_unique_metatile_count": int(append_target.get("affected_unique_metatile_count", 0)),
			"renderer_update_status": RENDERER_UPDATE_STATUS,
			"metadata_only_no_renderer_mutation": true,
		})

	return {
		"role": String(role_state.get("role", "")),
		"tileset_symbol": String(role_state.get("tileset_symbol", "")),
		"init_function": String(role_state.get("init_function", "")),
		"event_callback_symbol": String(role_state.get("event_callback_symbol", "")),
		"runtime_counter_value": counter_value,
		"counter_max_value": int(role_state.get("runtime_counter_max_value", 0)),
		"event_index": int(event_state.get("event_index", -1)),
		"queue_function": String(event_state.get("queue_function", "")),
		"trigger_modulo": int(event_state.get("trigger_modulo", 0)),
		"trigger_phase": int(event_state.get("trigger_phase", 0)),
		"timer_argument": timer_argument,
		"timer_argument_expr": String(event_state.get("timer_argument_expr", "")),
		"duration_frames": int(event_state.get("duration_frames", 0)),
		"tile_copy_request_count": tile_copy_requests.size(),
		"tile_copy_requests": tile_copy_requests,
		"metadata_only_no_renderer_mutation": true,
	}


func _source_timer_argument(counter_value: int, event_state: Dictionary) -> int:
	var expr := String(event_state.get("timer_argument_expr", ""))
	var modulo := int(event_state.get("trigger_modulo", 0))
	if expr == "timer":
		return counter_value
	if expr == "timer / 2":
		return floori(float(counter_value) / 2.0)
	if expr == "timer / 4":
		return floori(float(counter_value) / 4.0)
	if expr == "timer / 8":
		return floori(float(counter_value) / 8.0)
	if expr == "timer / 10":
		return floori(float(counter_value) / 10.0)
	if expr == "timer / 12":
		return floori(float(counter_value) / 12.0)
	if expr == "timer / 16":
		return floori(float(counter_value) / 16.0)
	if expr == "timer / 64":
		return floori(float(counter_value) / 64.0)
	if modulo > 0:
		return floori(float(counter_value) / float(modulo))
	return counter_value


func _selected_source_frame_index(timer_argument: int, append_target: Dictionary) -> int:
	var source_frame_count := int(append_target.get("source_frame_symbol_count", 0))
	if source_frame_count <= 0:
		return 0
	return timer_argument % source_frame_count


func _build_counter_status_from_roles(roles: Array) -> Dictionary:
	var role_statuses := []
	for role_state in roles:
		if typeof(role_state) != TYPE_DICTIONARY:
			continue
		role_statuses.append({
			"role": String(role_state.get("role", "")),
			"tileset_symbol": String(role_state.get("tileset_symbol", "")),
			"init_function": String(role_state.get("init_function", "")),
			"event_callback_symbol": String(role_state.get("event_callback_symbol", "")),
			"has_tile_animation_callback": bool(role_state.get("has_tile_animation_callback", false)),
			"counter_symbol": String(role_state.get("counter_symbol", "")),
			"counter_kind": String(role_state.get("counter_kind", "")),
			"counter_initial_value": role_state.get("runtime_counter_initial_value", null),
			"counter_value": role_state.get("runtime_counter_value", null),
			"counter_max_value": role_state.get("runtime_counter_max_value", null),
			"counter_max_source": String(role_state.get("counter_max_source", "")),
			"counter_resolved_from": String(role_state.get("counter_resolved_from", "")),
			"counter_wrap_enabled": bool(role_state.get("counter_wrap_enabled", false)),
			"last_counter_wrapped": bool(role_state.get("last_counter_wrapped", false)),
			"runtime_frames_elapsed": int(role_state.get("runtime_frames_elapsed", _runtime_frames_elapsed)),
		})
	return {
		"status": COUNTER_STATUS,
		"runtime_playback_status": RUNTIME_PLAYBACK_STATUS,
		"runtime_frames_elapsed": _runtime_frames_elapsed,
		"source_update_order": "primary_counter_then_secondary_counter_then_primary_callback_then_secondary_callback",
		"source_equivalent_for_runtime_counter_order": true,
		"role_count": role_statuses.size(),
		"roles": role_statuses,
	}


func _array_sample(values: Array, limit: int) -> Array:
	var sample := []
	for index in range(min(limit, values.size())):
		sample.append(values[index])
	return sample


func _unsupported_for_current_scope(active_count: int) -> Array:
	var unsupported := [
		{
			"code": "tileset_animation_transition_pause_reset_pending",
			"status": "pending",
			"detail": "Map-load initialization and per-frame counters are implemented; pause/reset rules across map transitions remain a later Section 6 task.",
		},
		{
			"code": "tileset_animation_renderer_tile_update_pending",
			"status": "pending",
			"detail": "Counter playback emits metadata-only tile-copy requests and does not mutate atlases, TileMaps, or map data.",
			"active_callback_count": active_count,
		},
	]
	return unsupported


func _empty_initialization(status: String) -> Dictionary:
	return {
		"schema_version": 1,
		"owner": OWNER_NAME,
		"status": status,
		"runtime_playback_status": RUNTIME_PLAYBACK_STATUS,
		"counter_status": "not_initialized",
		"runtime_frames_elapsed": _runtime_frames_elapsed,
		"initialized_on_map_load": false,
		"source_equivalent_for_runtime_playback": false,
		"source_equivalent_for_runtime_counter_order": false,
		"mutates_renderer": false,
		"mutates_map_data": false,
		"roles": [],
		"runtime_counters": {},
		"last_frame_update": {},
		"unsupported": _unsupported_for_current_scope(0),
		"source_trace": SOURCE_TRACE,
	}
