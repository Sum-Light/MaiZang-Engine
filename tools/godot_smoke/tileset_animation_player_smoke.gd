extends SceneTree

const DATA_REGISTRY_SCRIPT := preload("res://scripts/autoload/data_registry.gd")
const MAP_RUNTIME_SCRIPT := preload("res://scripts/autoload/map_runtime.gd")
const LAYER_RENDERER_SCRIPT := preload("res://scripts/overworld/layer_aware_map_renderer.gd")
const TILESET_ANIMATION_PLAYER_SCRIPT := preload("res://scripts/overworld/tileset_animation_player.gd")
const START_MAP := "MAP_LITTLEROOT_TOWN"
const MAUVILLE_MAP := "MAP_MAUVILLE_CITY"
const UNDERWATER_MAP := "MAP_UNDERWATER_ROUTE124"

var _failed := false


func _init() -> void:
	var registry = DATA_REGISTRY_SCRIPT.new()
	registry._ready()
	var map_data: Dictionary = registry.get_map_data(START_MAP, {
		"include_debug_overlays": true,
	})
	var tileset_data: Dictionary = registry.get_tileset_data_for_map(START_MAP)
	_assert(not map_data.is_empty(), "expected LittlerootTown map data")
	_assert(not tileset_data.is_empty(), "expected LittlerootTown tileset data")
	_assert(not registry.get_overworld_tileset_header_report().is_empty(), "expected tileset header report")

	var runtime = MAP_RUNTIME_SCRIPT.new()
	runtime.configure_data_registry(registry)

	var renderer = LAYER_RENDERER_SCRIPT.new()
	get_root().add_child(renderer)
	renderer.configure_data_registry(registry)
	renderer.configure_from_map_data(map_data, tileset_data)

	var player = TILESET_ANIMATION_PLAYER_SCRIPT.new()
	player.configure(registry, runtime, renderer)
	runtime.configure_from_data(map_data, tileset_data, _map_size_from_data(map_data))

	var snapshot: Dictionary = player.get_initialization_status()
	_assert(String(snapshot.get("owner", "")) == "TilesetAnimationPlayer", "expected owner")
	_assert(
		String(snapshot.get("status", "")) == "initialized_from_source_schedule_metadata",
		"expected source schedule initialization status"
	)
	_assert(String(snapshot.get("runtime_playback_status", "")) == "counter_playback_with_renderer_tile_updates", "expected renderer-backed counter playback")
	_assert(String(snapshot.get("counter_status", "")) == "source_order_independent_counters", "expected independent counter status")
	_assert(bool(snapshot.get("initialized_on_map_load", false)), "expected map-load initialization")
	_assert(not bool(snapshot.get("source_equivalent_for_runtime_playback", true)), "expected playback to remain non-equivalent")
	_assert(bool(snapshot.get("source_equivalent_for_runtime_counter_order", false)), "expected source counter order equivalence")
	_assert(bool(snapshot.get("source_equivalent_for_renderer_updates", false)), "expected renderer update source equivalence when renderer is configured")
	_assert(not bool(snapshot.get("mutates_renderer", true)), "expected initializer not to mutate renderer")
	_assert(not bool(snapshot.get("mutates_map_data", true)), "expected initializer not to mutate map data")
	_assert(String(snapshot.get("map_id", "")) == START_MAP, "expected LittlerootTown map id")
	_assert(String(snapshot.get("layout_id", "")) == "LAYOUT_LITTLEROOT_TOWN", "expected Littleroot layout id")

	var tileset_pair: Dictionary = snapshot.get("tileset_pair", {})
	_assert(String(tileset_pair.get("primary", "")) == "gTileset_General", "expected General primary tileset")
	_assert(String(tileset_pair.get("secondary", "")) == "gTileset_Petalburg", "expected Petalburg secondary tileset")
	_assert(int(snapshot.get("initialized_tileset_state_count", 0)) == 2, "expected both source callbacks to initialize")
	_assert(int(snapshot.get("active_tileset_state_count", 0)) == 1, "expected only General to have a tile animation callback")
	_assert(int(snapshot.get("schedule_event_count", 0)) == 5, "expected General event count")
	_assert(int(snapshot.get("tile_copy_event_count", 0)) == 5, "expected General tile-copy event count")
	_assert(int(snapshot.get("tile_copy_append_count", 0)) == 5, "expected one append target per General event")

	var primary: Dictionary = player.get_tileset_state("primary")
	_assert(String(primary.get("tileset_symbol", "")) == "gTileset_General", "expected primary state lookup")
	_assert(String(primary.get("init_function", "")) == "InitTilesetAnim_General", "expected General init callback")
	_assert(String(primary.get("event_callback_symbol", "")) == "TilesetAnim_General", "expected General schedule callback")
	_assert(String(primary.get("counter_kind", "")) == "primary", "expected General primary counter")
	_assert(int(primary.get("counter_initial_value", -1)) == 0, "expected General counter initial value")
	_assert(int(primary.get("counter_max_value", -1)) == 256, "expected General counter max")
	_assert(int(primary.get("runtime_counter_initial_value", -1)) == 0, "expected General runtime counter seed")
	_assert(int(primary.get("runtime_counter_max_value", -1)) == 256, "expected General runtime counter max")
	_assert(bool(primary.get("initialized_on_map_load", false)), "expected General initialized on map load")
	_assert(bool(primary.get("has_tile_animation_callback", false)), "expected General animation callback")
	_assert(bool(primary.get("active_runtime_callback", false)), "expected runtime counter callback to be active")
	_assert(int(primary.get("schedule_event_count", 0)) == 5, "expected General schedule events")

	var events: Array = primary.get("schedule_events", [])
	_assert(events.size() == 5, "expected five General schedule event records")
	_assert(_event_queue(events, 0) == "QueueAnimTiles_General_Flower", "expected flower queue")
	_assert(_event_queue(events, 1) == "QueueAnimTiles_General_Water", "expected water queue")
	_assert(_event_queue(events, 2) == "QueueAnimTiles_General_SandWaterEdge", "expected sand/water edge queue")
	_assert(_event_queue(events, 3) == "QueueAnimTiles_General_Waterfall", "expected waterfall queue")
	_assert(_event_queue(events, 4) == "QueueAnimTiles_General_LandWaterEdge", "expected land/water edge queue")
	for index in range(events.size()):
		var event: Dictionary = events[index]
		_assert(int(event.get("trigger_modulo", 0)) == 16, "expected modulo 16 trigger")
		_assert(int(event.get("trigger_phase", -1)) == index, "expected source trigger phase")
		_assert(int(event.get("duration_frames", 0)) == 16, "expected source frame duration")
		_assert(int(event.get("append_target_count", 0)) == 1, "expected one append target")

	var flower_target: Dictionary = _first_append_target(events, 0)
	_assert(int(flower_target.get("tile_count", 0)) == 4, "expected flower target tile count")
	_assert(int(flower_target.get("source_frame_symbol_count", 0)) == 4, "expected flower source frame count")
	_assert(int(flower_target.get("resolved_frame_strip_count", 0)) == 4, "expected flower frame strips to resolve")
	_assert(int(flower_target.get("affected_unique_metatile_count", 0)) == 33, "expected flower affected metatile count")
	var flower_ranges: Array = flower_target.get("affected_tile_ranges", [])
	_assert(not flower_ranges.is_empty(), "expected flower tile range")
	var flower_range: Dictionary = flower_ranges[0]
	_assert(int(flower_range.get("start_tile_id", 0)) == 508, "expected flower start tile")
	_assert(int(flower_range.get("end_tile_id", 0)) == 511, "expected flower end tile")

	var water_target: Dictionary = _first_append_target(events, 1)
	_assert(int(water_target.get("tile_count", 0)) == 30, "expected water target tile count")
	_assert(int(water_target.get("source_frame_symbol_count", 0)) == 8, "expected water source frame count")
	_assert(int(water_target.get("resolved_frame_strip_count", 0)) == 8, "expected water frame strips to resolve")
	_assert(int(water_target.get("affected_unique_metatile_count", 0)) == 1300, "expected water affected metatile count")
	var water_ranges: Array = water_target.get("affected_tile_ranges", [])
	_assert(not water_ranges.is_empty(), "expected water tile range")
	var water_range: Dictionary = water_ranges[0]
	_assert(int(water_range.get("start_tile_id", 0)) == 432, "expected water start tile")
	_assert(int(water_range.get("end_tile_id", 0)) == 461, "expected water end tile")

	var secondary: Dictionary = player.get_tileset_state("gTileset_Petalburg")
	_assert(String(secondary.get("role", "")) == "secondary", "expected secondary lookup by symbol")
	_assert(String(secondary.get("init_function", "")) == "InitTilesetAnim_Petalburg", "expected Petalburg init callback")
	_assert(String(secondary.get("event_callback_symbol", "")) == "NULL", "expected Petalburg null callback")
	_assert(String(secondary.get("counter_kind", "")) == "secondary", "expected Petalburg secondary counter")
	_assert(int(secondary.get("runtime_counter_initial_value", -1)) == 0, "expected Petalburg runtime counter seed")
	_assert(int(secondary.get("runtime_counter_max_value", -1)) == 256, "expected Petalburg inherited runtime counter max")
	_assert(bool(secondary.get("initialized_on_map_load", false)), "expected Petalburg initialized on map load")
	_assert(not bool(secondary.get("has_tile_animation_callback", true)), "expected Petalburg no tile animation callback")
	_assert(int(secondary.get("schedule_event_count", -1)) == 0, "expected Petalburg no schedule events")

	var first_frame := player.advance_frame()
	_assert(int(first_frame.get("runtime_frames_elapsed", 0)) == 1, "expected first runtime frame")
	_assert(int(first_frame.get("event_count", -1)) == 1, "expected one first-frame General event")
	_assert(int(first_frame.get("tile_copy_request_count", -1)) == 1, "expected one first-frame tile copy request")
	_assert(String(first_frame.get("source_update_order", "")) == "reset_buffer_increment_primary_increment_secondary_call_primary_call_secondary", "expected source update order")
	_assert(bool(first_frame.get("mutates_renderer", false)), "expected first frame to mutate renderer atlas textures")
	_assert(String(first_frame.get("renderer_update_status", "")) == "tileset_animation_layer_atlas_updates_applied", "expected renderer atlas update status")
	_assert(bool(first_frame.get("source_equivalent_for_renderer_updates", false)), "expected source-backed renderer update")
	var first_events: Array = first_frame.get("events", [])
	_assert(_event_queue(first_events, 0) == "QueueAnimTiles_General_Water", "expected first frame to trigger General water")
	_assert(int(first_events[0].get("runtime_counter_value", -1)) == 1, "expected General first callback timer 1")
	_assert(int(first_events[0].get("timer_argument", -1)) == 0, "expected General first water timer argument 0")
	var first_counters := player.get_counter_status()
	_assert(_counter_value(first_counters, "primary") == 1, "expected primary counter at 1")
	_assert(_counter_value(first_counters, "secondary") == 1, "expected secondary counter at 1")

	var first_water_request: Dictionary = _first_tile_copy_request(first_events, 0)
	_assert(int(first_water_request.get("selected_source_frame_index", -1)) == 0, "expected first water source frame")
	_assert(String(first_water_request.get("selected_source_frame_symbol", "")) == "gTilesetAnims_General_Water_Frame0", "expected first water source frame symbol")
	_assert(String(first_water_request.get("selected_source_frame_image", "")).ends_with("gtilesetanims_general_water_frame0.png"), "expected first water RGBA frame image")
	_assert(not bool(first_water_request.get("metadata_only_no_renderer_mutation", true)), "expected renderer-backed tile copy")
	var renderer_update: Dictionary = first_frame.get("renderer_update", {})
	_assert(not bool(renderer_update.get("rebuilds_full_map", true)), "expected renderer update not to rebuild full map")
	_assert(not bool(renderer_update.get("mutates_generated_files", true)), "expected renderer update not to mutate generated files")
	_assert(int(renderer_update.get("tile_copy_request_count", 0)) == 1, "expected one renderer tile-copy request")
	_assert(int(renderer_update.get("patched_slot_count", 0)) > 0, "expected renderer to patch atlas slots")
	_assert(int(renderer_update.get("updated_metatile_count", 0)) > 0, "expected renderer to update metatile atlas records")
	var renderer_status: Dictionary = renderer.get_tileset_animation_update_status()
	_assert(String(renderer_status.get("status", "")) == "tileset_animation_layer_atlas_updates_applied", "expected renderer status accessor to expose atlas updates")

	var to_sixteen := player.advance_frames(15)
	_assert(int(to_sixteen.get("runtime_frames_elapsed", 0)) == 16, "expected runtime frame 16")
	var frame_16: Dictionary = to_sixteen.get("last_event_frame", {})
	_assert(_event_queue(frame_16.get("events", []), 0) == "QueueAnimTiles_General_Flower", "expected frame 16 to trigger General flower")
	_assert(_counter_value(to_sixteen.get("counter_status", {}), "primary") == 16, "expected primary counter at 16")
	_assert(_counter_value(to_sixteen.get("counter_status", {}), "secondary") == 16, "expected secondary counter at 16")

	var wrap_update := player.advance_frames(240)
	_assert(int(wrap_update.get("runtime_frames_elapsed", 0)) == 256, "expected runtime frame 256")
	_assert(_counter_value(wrap_update.get("counter_status", {}), "primary") == 0, "expected primary counter wrap at 256")
	_assert(_counter_value(wrap_update.get("counter_status", {}), "secondary") == 0, "expected secondary inherited counter wrap at 256")

	var active_states: Array = player.get_active_tileset_states()
	_assert(active_states.size() == 1, "expected one active state")
	_assert(String(active_states[0].get("tileset_symbol", "")) == "gTileset_General", "expected General active state")

	var unsupported: Array = snapshot.get("unsupported", [])
	_assert(not _has_unsupported_code(unsupported, "tileset_animation_playback_pending"), "did not expect playback pending marker")
	_assert(not _has_unsupported_code(unsupported, "tileset_animation_independent_counters_pending"), "did not expect counter pending marker")
	_assert(not _has_unsupported_code(unsupported, "tileset_animation_transition_pause_reset_pending"), "did not expect transition reset pending marker")
	_assert(not _has_unsupported_code(unsupported, "tileset_animation_renderer_tile_update_pending"), "did not expect renderer update pending marker")

	var transition_sequence := {
		"id": 901,
		"type": "map_transition",
		"presentation": "normal",
		"source_map": START_MAP,
		"destination_map": MAUVILLE_MAP,
		"steps": [{"op": "load_map"}],
	}
	var pause_status := player.pause_for_transition(transition_sequence)
	_assert(bool(pause_status.get("transition_pause_active", false)), "expected transition pause active")
	_assert(bool(player.is_transition_paused()), "expected player transition paused")
	var paused_counter_before := _counter_value(player.get_counter_status(), "primary")
	var paused_frame := player.advance_frame()
	_assert(String(paused_frame.get("status", "")) == "paused_for_source_load_map_callback", "expected paused frame status")
	_assert(int(paused_frame.get("runtime_frames_elapsed", -1)) == 256, "expected paused frame not to advance runtime frames")
	_assert(int(paused_frame.get("event_count", -1)) == 0, "expected no events while paused")
	_assert(_counter_value(player.get_counter_status(), "primary") == paused_counter_before, "expected paused primary counter unchanged")
	var paused_many := player.advance_frames(5)
	_assert(String(paused_many.get("status", "")) == "paused_for_source_load_map_callback", "expected paused bulk advance status")
	_assert(int(paused_many.get("frames_advanced", -1)) == 0, "expected paused bulk advance to report zero advanced frames")
	_assert(_counter_value(player.get_counter_status(), "primary") == paused_counter_before, "expected paused bulk counter unchanged")

	var mauville := _configure_map(player, registry, runtime, MAUVILLE_MAP, renderer)
	_assert(String(mauville.get("map_id", "")) == MAUVILLE_MAP, "expected Mauville map id")
	_assert(bool(player.is_transition_paused()), "expected map load reset to keep transition pause active until resume")
	_assert(_counter_value(player.get_counter_status(), "primary") == 0, "expected transition map load to reset primary counter")
	_assert(_counter_value(player.get_counter_status(), "secondary") == 0, "expected transition map load to reset secondary counter")
	var transition_reset: Dictionary = mauville.get("last_transition_reset", {})
	_assert(String(transition_reset.get("status", "")) == "source_map_load_reinitialized_tileset_animation_counters", "expected transition reset status")
	_assert(bool(transition_reset.get("active_during_reset", false)), "expected reset while transition pause active")
	var resume_status := player.resume_after_transition(transition_sequence)
	_assert(not bool(resume_status.get("transition_pause_active", true)), "expected transition pause cleared after resume")
	_assert(not bool(player.is_transition_paused()), "expected player transition resumed")
	var mauville_resume: Dictionary = player.get_initialization_status().get("last_transition_resume", {})
	_assert(String(mauville_resume.get("status", "")) == "resumed_after_source_load_map_callback", "expected transition resume status")
	_assert(int(mauville.get("active_tileset_state_count", 0)) == 2, "expected Mauville primary and secondary active callbacks")
	var mauville_secondary := player.get_tileset_state("gTileset_Mauville")
	_assert(String(mauville_secondary.get("role", "")) == "secondary", "expected Mauville secondary role")
	_assert(String(mauville_secondary.get("event_callback_symbol", "")) == "TilesetAnim_Mauville", "expected Mauville callback")
	_assert(String(mauville_secondary.get("counter_resolved_from", "")) == "inherits_primary_counter_max", "expected Mauville to inherit primary counter max")
	_assert(int(mauville_secondary.get("runtime_counter_max_value", -1)) == 256, "expected Mauville runtime max 256")
	var mauville_advance := player.advance_frames(16)
	_assert(_counter_value(mauville_advance.get("counter_status", {}), "primary") == 16, "expected Mauville primary counter 16")
	_assert(_counter_value(mauville_advance.get("counter_status", {}), "secondary") == 16, "expected Mauville secondary counter 16")
	var mauville_frame: Dictionary = mauville_advance.get("last_event_frame", {})
	var mauville_events: Array = mauville_frame.get("events", [])
	_assert(mauville_events.size() == 2, "expected frame 16 General plus Mauville events")
	_assert(_has_event_queue(mauville_events, "QueueAnimTiles_General_Flower"), "expected General flower event")
	_assert(_has_event_queue(mauville_events, "QueueAnimTiles_Mauville_Flowers"), "expected Mauville flowers event")
	_assert(_event_role_for_queue(mauville_events, "QueueAnimTiles_Mauville_Flowers") == "secondary", "expected Mauville event on secondary counter")

	var same_map_update := player.advance_frame()
	var same_map_counter_before := _counter_value(same_map_update.get("counter_status", {}), "primary")
	runtime.configure_from_data(mauville.get("map_data", {}), mauville.get("tileset_data", {}), _map_size_from_data(mauville.get("map_data", {})))
	_assert(_counter_value(player.get_counter_status(), "primary") == same_map_counter_before, "expected same-map map_changed to preserve counters")
	_assert(String(player.get_initialization_status().get("last_map_changed_status", "")) == "same_map_update_preserved_tileset_animation_counters", "expected same-map preservation status")

	var underwater := _configure_map(player, registry, runtime, UNDERWATER_MAP, renderer)
	_assert(String(underwater.get("map_id", "")) == UNDERWATER_MAP, "expected Underwater map id")
	var underwater_secondary := player.get_tileset_state("gTileset_Underwater")
	_assert(String(underwater_secondary.get("counter_resolved_from", "")) == "literal_or_expression", "expected Underwater literal counter max")
	_assert(int(underwater_secondary.get("runtime_counter_max_value", -1)) == 128, "expected Underwater secondary max 128")
	var underwater_wrap := player.advance_frames(128)
	_assert(_counter_value(underwater_wrap.get("counter_status", {}), "primary") == 128, "expected Underwater primary still at 128")
	_assert(_counter_value(underwater_wrap.get("counter_status", {}), "secondary") == 0, "expected Underwater secondary wrap at 128")
	var underwater_last: Dictionary = underwater_wrap.get("last_event_frame", {})
	var underwater_last_events: Array = underwater_last.get("events", [])
	_assert(_has_event_queue(underwater_last_events, "QueueAnimTiles_General_Flower"), "expected General flower event in Underwater run")
	_assert(_has_event_queue(underwater_last_events, "QueueAnimTiles_Underwater_Seaweed"), "expected Underwater seaweed event")

	if _failed:
		player.free()
		renderer.free()
		runtime.free()
		registry.free()
		quit(1)
	else:
		print("Tileset animation player smoke passed")
		player.free()
		renderer.free()
		runtime.free()
		registry.free()
		quit(0)


func _map_size_from_data(map_data: Dictionary) -> Vector2i:
	var layout = map_data.get("layout", {})
	if typeof(layout) != TYPE_DICTIONARY:
		return Vector2i.ZERO
	return Vector2i(int(layout.get("width", 0)), int(layout.get("height", 0)))


func _configure_map(player: Node, registry: Node, runtime: Node, map_id: String, renderer: Node = null) -> Dictionary:
	var map_data: Dictionary = registry.get_map_data(map_id, {
		"include_debug_overlays": true,
	})
	var tileset_data: Dictionary = registry.get_tileset_data_for_map(map_id)
	_assert(not map_data.is_empty(), "expected map data for %s" % map_id)
	if renderer != null and renderer.has_method("configure_from_map_data"):
		renderer.configure_from_map_data(map_data, tileset_data)
	runtime.configure_from_data(map_data, tileset_data, _map_size_from_data(map_data))
	var snapshot: Dictionary = player.get_initialization_status()
	snapshot["map_data"] = map_data
	snapshot["tileset_data"] = tileset_data
	return snapshot


func _event_queue(events: Array, index: int) -> String:
	if index < 0 or index >= events.size() or typeof(events[index]) != TYPE_DICTIONARY:
		return ""
	return String(events[index].get("queue_function", ""))


func _first_append_target(events: Array, index: int) -> Dictionary:
	if index < 0 or index >= events.size() or typeof(events[index]) != TYPE_DICTIONARY:
		return {}
	var targets = events[index].get("append_targets", [])
	if typeof(targets) != TYPE_ARRAY or targets.is_empty() or typeof(targets[0]) != TYPE_DICTIONARY:
		return {}
	return targets[0]


func _first_tile_copy_request(events: Array, index: int) -> Dictionary:
	if index < 0 or index >= events.size() or typeof(events[index]) != TYPE_DICTIONARY:
		return {}
	var requests = events[index].get("tile_copy_requests", [])
	if typeof(requests) != TYPE_ARRAY or requests.is_empty() or typeof(requests[0]) != TYPE_DICTIONARY:
		return {}
	return requests[0]


func _counter_value(counter_status: Dictionary, role: String) -> int:
	var roles = counter_status.get("roles", [])
	if typeof(roles) != TYPE_ARRAY:
		return -1
	for role_status in roles:
		if typeof(role_status) == TYPE_DICTIONARY and String(role_status.get("role", "")) == role:
			return int(role_status.get("counter_value", -1))
	return -1


func _has_event_queue(events: Array, queue_function: String) -> bool:
	return not _event_for_queue(events, queue_function).is_empty()


func _event_role_for_queue(events: Array, queue_function: String) -> String:
	return String(_event_for_queue(events, queue_function).get("role", ""))


func _event_for_queue(events: Array, queue_function: String) -> Dictionary:
	for event in events:
		if typeof(event) == TYPE_DICTIONARY and String(event.get("queue_function", "")) == queue_function:
			return event
	return {}


func _has_unsupported_code(unsupported: Array, code: String) -> bool:
	for entry in unsupported:
		if typeof(entry) == TYPE_DICTIONARY and String(entry.get("code", "")) == code:
			return true
	return false


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)
