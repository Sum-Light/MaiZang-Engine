extends SceneTree

const DATA_REGISTRY_SCRIPT := preload("res://scripts/autoload/data_registry.gd")
const MAP_RUNTIME_SCRIPT := preload("res://scripts/autoload/map_runtime.gd")
const LAYER_RENDERER_SCRIPT := preload("res://scripts/overworld/layer_aware_map_renderer.gd")
const TILESET_ANIMATION_PLAYER_SCRIPT := preload("res://scripts/overworld/tileset_animation_player.gd")
const START_MAP := "MAP_LITTLEROOT_TOWN"
const MAUVILLE_MAP := "MAP_MAUVILLE_CITY"
const UNDERWATER_MAP := "MAP_UNDERWATER_ROUTE124"
const PACIFIDLOG_MAP := "MAP_PACIFIDLOG_TOWN"
const LAVARIDGE_MAP := "MAP_LAVARIDGE_TOWN"

var _failed := false


func _init() -> void:
	var registry = DATA_REGISTRY_SCRIPT.new()
	var metadata_runtime = null
	var metadata_player = null
	var missing_data_runtime = null
	var missing_data_player = null
	var missing_data_renderer = null
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
	_assert_append_target(events, 2, "QueueAnimTiles_General_SandWaterEdge", 10, 8, 464, 473)
	_assert_append_target(events, 3, "QueueAnimTiles_General_Waterfall", 6, 4, 496, 501)
	_assert_append_target(events, 4, "QueueAnimTiles_General_LandWaterEdge", 10, 4, 480, 489)

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
	_assert_runtime_queue_request(first_frame, "QueueAnimTiles_General_Water", "primary", 30, 0, 432, 461, "direct_tile_offset")
	_assert_renderer_patch_for_queue(first_frame, "QueueAnimTiles_General_Water")
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

	var second_frame: Dictionary = player.advance_frame()
	_assert(int(second_frame.get("runtime_frames_elapsed", 0)) == 2, "expected runtime frame 2")
	_assert_runtime_queue_request(second_frame, "QueueAnimTiles_General_SandWaterEdge", "primary", 10, 0, 464, 473, "direct_tile_offset")
	_assert_renderer_patch_for_queue(second_frame, "QueueAnimTiles_General_SandWaterEdge")

	var third_frame: Dictionary = player.advance_frame()
	_assert(int(third_frame.get("runtime_frames_elapsed", 0)) == 3, "expected runtime frame 3")
	_assert_runtime_queue_request(third_frame, "QueueAnimTiles_General_Waterfall", "primary", 6, 0, 496, 501, "direct_tile_offset")
	_assert_renderer_patch_for_queue(third_frame, "QueueAnimTiles_General_Waterfall")

	var fourth_frame: Dictionary = player.advance_frame()
	_assert(int(fourth_frame.get("runtime_frames_elapsed", 0)) == 4, "expected runtime frame 4")
	_assert_runtime_queue_request(fourth_frame, "QueueAnimTiles_General_LandWaterEdge", "primary", 10, 0, 480, 489, "direct_tile_offset")
	_assert_renderer_idle_for_queue(fourth_frame, "QueueAnimTiles_General_LandWaterEdge")

	var to_sixteen := player.advance_frames(12)
	_assert(int(to_sixteen.get("runtime_frames_elapsed", 0)) == 16, "expected runtime frame 16")
	var frame_16: Dictionary = to_sixteen.get("last_event_frame", {})
	_assert(_event_queue(frame_16.get("events", []), 0) == "QueueAnimTiles_General_Flower", "expected frame 16 to trigger General flower")
	_assert_runtime_queue_request(frame_16, "QueueAnimTiles_General_Flower", "primary", 4, 1, 508, 511, "direct_tile_offset")
	_assert_renderer_patch_for_queue(frame_16, "QueueAnimTiles_General_Flower")
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
	_assert_mauville_flower_requests(mauville_frame, 2, 0)

	var same_map_update := player.advance_frame()
	var same_map_counter_before := _counter_value(same_map_update.get("counter_status", {}), "primary")
	runtime.configure_from_data(mauville.get("map_data", {}), mauville.get("tileset_data", {}), _map_size_from_data(mauville.get("map_data", {})))
	_assert(_counter_value(player.get_counter_status(), "primary") == same_map_counter_before, "expected same-map map_changed to preserve counters")
	_assert(String(player.get_initialization_status().get("last_map_changed_status", "")) == "same_map_update_preserved_tileset_animation_counters", "expected same-map preservation status")

	missing_data_runtime = MAP_RUNTIME_SCRIPT.new()
	missing_data_runtime.configure_data_registry(registry)
	missing_data_renderer = LAYER_RENDERER_SCRIPT.new()
	get_root().add_child(missing_data_renderer)
	missing_data_renderer.configure_data_registry(registry)
	missing_data_player = TILESET_ANIMATION_PLAYER_SCRIPT.new()
	missing_data_player.configure(registry, missing_data_runtime, missing_data_renderer)
	missing_data_runtime.configure_from_data(map_data, tileset_data, _map_size_from_data(map_data))
	var missing_renderer_data_first: Dictionary = missing_data_player.advance_frame()
	_assert_metadata_only_renderer_update(
		missing_renderer_data_first,
		"QueueAnimTiles_General_Water",
		"tileset_animation_callback_metadata_only_missing_renderer_data",
		"missing_tileset_animation_renderer_data"
	)

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
	_assert_runtime_queue_request(underwater_last, "QueueAnimTiles_Underwater_Seaweed", "secondary", 4, 0, 1008, 1011, "direct_tile_offset")

	metadata_runtime = MAP_RUNTIME_SCRIPT.new()
	metadata_runtime.configure_data_registry(registry)
	metadata_player = TILESET_ANIMATION_PLAYER_SCRIPT.new()
	metadata_player.configure(registry, metadata_runtime)

	var pacifidlog: Dictionary = _configure_map(metadata_player, registry, metadata_runtime, PACIFIDLOG_MAP)
	_assert(String(pacifidlog.get("map_id", "")) == PACIFIDLOG_MAP, "expected Pacifidlog map id")
	var pacifidlog_secondary: Dictionary = metadata_player.get_tileset_state("gTileset_Pacifidlog")
	_assert(String(pacifidlog_secondary.get("event_callback_symbol", "")) == "TilesetAnim_Pacifidlog", "expected Pacifidlog callback")
	var pacifidlog_first: Dictionary = metadata_player.advance_frame()
	_assert_runtime_queue_request(pacifidlog_first, "QueueAnimTiles_Pacifidlog_WaterCurrents", "secondary", 8, 0, 1008, 1015, "direct_tile_offset", true)
	_assert_metadata_only_renderer_update(pacifidlog_first, "QueueAnimTiles_Pacifidlog_WaterCurrents")

	var lavaridge: Dictionary = _configure_map(metadata_player, registry, metadata_runtime, LAVARIDGE_MAP)
	_assert(String(lavaridge.get("map_id", "")) == LAVARIDGE_MAP, "expected Lavaridge map id")
	var lavaridge_secondary: Dictionary = metadata_player.get_tileset_state("gTileset_Lavaridge")
	_assert(String(lavaridge_secondary.get("event_callback_symbol", "")) == "TilesetAnim_Lavaridge", "expected Lavaridge callback")
	var lavaridge_first: Dictionary = metadata_player.advance_frame()
	_assert_runtime_queue_request(lavaridge_first, "QueueAnimTiles_Lavaridge_Lava", "secondary", 4, 0, 672, 675, "direct_tile_offset", true)
	_assert_metadata_only_renderer_update(lavaridge_first, "QueueAnimTiles_Lavaridge_Lava")

	if _failed:
		if missing_data_renderer != null:
			missing_data_renderer.free()
		if missing_data_player != null:
			missing_data_player.free()
		if missing_data_runtime != null:
			missing_data_runtime.free()
		if metadata_player != null:
			metadata_player.free()
		if metadata_runtime != null:
			metadata_runtime.free()
		player.free()
		renderer.free()
		runtime.free()
		registry.free()
		quit(1)
	else:
		print("Tileset animation player smoke passed")
		if metadata_player != null:
			metadata_player.free()
		if metadata_runtime != null:
			metadata_runtime.free()
		if missing_data_renderer != null:
			missing_data_renderer.free()
		if missing_data_player != null:
			missing_data_player.free()
		if missing_data_runtime != null:
			missing_data_runtime.free()
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


func _assert_append_target(
	events: Array,
	index: int,
	queue_function: String,
	expected_tile_count: int,
	expected_frame_count: int,
	expected_start_tile: int,
	expected_end_tile: int
) -> void:
	_assert(_event_queue(events, index) == queue_function, "expected %s schedule queue" % queue_function)
	var target := _first_append_target(events, index)
	_assert(int(target.get("tile_count", 0)) == expected_tile_count, "expected %s target tile count" % queue_function)
	_assert(int(target.get("source_frame_symbol_count", 0)) == expected_frame_count, "expected %s source frame count" % queue_function)
	_assert(int(target.get("resolved_frame_strip_count", 0)) == expected_frame_count, "expected %s frame strips to resolve" % queue_function)
	var ranges: Array = target.get("affected_tile_ranges", [])
	_assert(not ranges.is_empty(), "expected %s affected tile range" % queue_function)
	if ranges.is_empty() or typeof(ranges[0]) != TYPE_DICTIONARY:
		return
	var range_record: Dictionary = ranges[0]
	_assert(int(range_record.get("start_tile_id", -1)) == expected_start_tile, "expected %s start tile" % queue_function)
	_assert(int(range_record.get("end_tile_id", -1)) == expected_end_tile, "expected %s end tile" % queue_function)


func _assert_runtime_queue_request(
	frame_update: Dictionary,
	queue_function: String,
	expected_role: String,
	expected_tile_count: int,
	expected_source_frame_index: int,
	expected_start_tile: int,
	expected_end_tile: int,
	expected_dest_kind: String,
	expect_metadata_only: bool = false
) -> void:
	var events: Array = frame_update.get("events", [])
	var event := _event_for_queue(events, queue_function)
	_assert(not event.is_empty(), "expected runtime event for %s" % queue_function)
	if event.is_empty():
		return
	_assert(String(event.get("role", "")) == expected_role, "expected %s role" % queue_function)
	_assert(int(event.get("tile_copy_request_count", 0)) > 0, "expected %s tile copy request" % queue_function)
	_assert(bool(event.get("metadata_only_no_renderer_mutation", false)) == expect_metadata_only, "expected %s metadata-only flag" % queue_function)
	var request := _first_tile_copy_request_for_queue(events, queue_function)
	_assert(not request.is_empty(), "expected request for %s" % queue_function)
	if request.is_empty():
		return
	_assert(String(request.get("queue_function", "")) == queue_function, "expected request queue for %s" % queue_function)
	_assert(String(request.get("dest_kind", "")) == expected_dest_kind, "expected %s dest kind" % queue_function)
	_assert(int(request.get("tile_count", 0)) == expected_tile_count, "expected %s tile count" % queue_function)
	_assert(int(request.get("selected_source_frame_index", -1)) == expected_source_frame_index, "expected %s source frame index" % queue_function)
	_assert(String(request.get("selected_source_frame_symbol", "")) != "", "expected %s selected frame symbol" % queue_function)
	_assert(String(request.get("selected_source_frame_image", "")).ends_with(".png"), "expected %s RGBA frame image" % queue_function)
	_assert(int(request.get("resolved_frame_strip_count", 0)) > 0, "expected %s resolved frame strips" % queue_function)
	_assert(bool(request.get("metadata_only_no_renderer_mutation", false)) == expect_metadata_only, "expected %s request metadata-only flag" % queue_function)
	var effective_ranges: Array = request.get("effective_tile_ranges", [])
	_assert(not effective_ranges.is_empty(), "expected %s effective tile range" % queue_function)
	if effective_ranges.is_empty() or typeof(effective_ranges[0]) != TYPE_DICTIONARY:
		return
	var range_record: Dictionary = effective_ranges[0]
	_assert(int(range_record.get("start_tile_id", -1)) == expected_start_tile, "expected %s effective start tile" % queue_function)
	_assert(int(range_record.get("end_tile_id", -1)) == expected_end_tile, "expected %s effective end tile" % queue_function)
	_assert(int(range_record.get("tile_count", 0)) == expected_tile_count, "expected %s effective tile count" % queue_function)


func _assert_renderer_patch_for_queue(frame_update: Dictionary, queue_function: String) -> void:
	_assert(bool(frame_update.get("mutates_renderer", false)), "expected %s to mutate renderer" % queue_function)
	_assert(_unsupported_for_queue(frame_update.get("unsupported", []), queue_function).is_empty(), "did not expect unsupported marker for %s" % queue_function)
	var renderer_update: Dictionary = frame_update.get("renderer_update", {})
	_assert(String(renderer_update.get("status", "")) == "tileset_animation_layer_atlas_updates_applied", "expected %s renderer update status" % queue_function)
	_assert(not bool(renderer_update.get("rebuilds_full_map", true)), "expected %s not to rebuild full map" % queue_function)
	_assert(not bool(renderer_update.get("mutates_generated_files", true)), "expected %s not to mutate generated files" % queue_function)
	_assert(not bool(renderer_update.get("mutates_map_data", true)), "expected %s not to mutate map data" % queue_function)
	_assert(not bool(renderer_update.get("mutates_collision_or_elevation", true)), "expected %s not to mutate collision/elevation" % queue_function)
	_assert(int(renderer_update.get("failed_request_count", 0)) == 0, "expected %s renderer requests to apply" % queue_function)
	var summary := _renderer_summary_for_queue(renderer_update, queue_function)
	_assert(not summary.is_empty(), "expected renderer summary for %s" % queue_function)
	if summary.is_empty():
		return
	_assert(bool(summary.get("applied", false)), "expected renderer summary applied for %s" % queue_function)
	_assert(int(summary.get("patched_slot_count", 0)) > 0, "expected patched atlas slots for %s" % queue_function)
	var updated_metatiles: Array = summary.get("updated_metatile_ids", [])
	_assert(not updated_metatiles.is_empty(), "expected updated metatiles for %s" % queue_function)


func _assert_renderer_idle_for_queue(frame_update: Dictionary, queue_function: String) -> void:
	_assert(not bool(frame_update.get("mutates_renderer", true)), "expected %s not to mutate renderer without visible slots" % queue_function)
	var renderer_update: Dictionary = frame_update.get("renderer_update", {})
	_assert(String(renderer_update.get("status", "")) == "tileset_animation_layer_atlas_updates_idle", "expected %s renderer idle status" % queue_function)
	_assert(not bool(renderer_update.get("rebuilds_full_map", true)), "expected %s not to rebuild full map" % queue_function)
	_assert(not bool(renderer_update.get("mutates_generated_files", true)), "expected %s not to mutate generated files" % queue_function)
	_assert(not bool(renderer_update.get("mutates_map_data", true)), "expected %s not to mutate map data" % queue_function)
	_assert(not bool(renderer_update.get("mutates_collision_or_elevation", true)), "expected %s not to mutate collision/elevation" % queue_function)
	_assert(int(renderer_update.get("failed_request_count", 0)) == 1, "expected %s to report one unmatched renderer request" % queue_function)
	var summary := _renderer_summary_for_queue(renderer_update, queue_function)
	_assert(not summary.is_empty(), "expected idle renderer summary for %s" % queue_function)
	if summary.is_empty():
		return
	_assert(not bool(summary.get("applied", true)), "expected renderer summary idle for %s" % queue_function)
	_assert(String(summary.get("status", "")) == "no_matching_metatile_slots", "expected no visible metatile slots for %s" % queue_function)
	_assert(int(summary.get("patched_slot_count", -1)) == 0, "expected no patched atlas slots for %s" % queue_function)
	_assert_unsupported_for_queue(
		frame_update,
		queue_function,
		"tileset_animation_callback_not_rendered",
		"no_matching_metatile_slots"
	)


func _assert_metadata_only_renderer_update(
	frame_update: Dictionary,
	queue_function: String = "",
	expected_code: String = "tileset_animation_callback_metadata_only_renderer_not_configured",
	expected_renderer_status: String = "renderer_not_configured_metadata_only"
) -> void:
	_assert(not bool(frame_update.get("mutates_renderer", true)), "expected metadata-only animation not to mutate renderer")
	_assert(String(frame_update.get("renderer_update_status", "")) == expected_renderer_status, "expected metadata-only renderer status")
	var renderer_update: Dictionary = frame_update.get("renderer_update", {})
	_assert(String(renderer_update.get("status", "")) == expected_renderer_status, "expected metadata-only renderer update")
	_assert(not bool(renderer_update.get("rebuilds_full_map", true)), "expected metadata-only update not to rebuild map")
	if not queue_function.is_empty():
		_assert_unsupported_for_queue(frame_update, queue_function, expected_code, expected_renderer_status)


func _assert_mauville_flower_requests(frame_update: Dictionary, expected_source_frame_index: int, expected_range_index: int) -> void:
	var events: Array = frame_update.get("events", [])
	var event := _event_for_queue(events, "QueueAnimTiles_Mauville_Flowers")
	_assert(not event.is_empty(), "expected Mauville flowers runtime event")
	if event.is_empty():
		return
	_assert(int(event.get("tile_copy_request_count", 0)) == 4, "expected four Mauville flower tile-copy requests")
	_assert(int(event.get("destination_tile_range_index", -1)) == expected_range_index, "expected Mauville VDest range index")
	var requests: Array = event.get("tile_copy_requests", [])
	_assert(requests.size() == 4, "expected four Mauville flower request records")
	var expected_ranges := [
		[608, 611],
		[640, 643],
		[608, 611],
		[640, 643],
	]
	var expected_arrays := [
		"gTilesetAnims_Mauville_Flower1",
		"gTilesetAnims_Mauville_Flower2",
		"gTilesetAnims_Mauville_Flower1_B",
		"gTilesetAnims_Mauville_Flower2_B",
	]
	for index in range(requests.size()):
		var request: Dictionary = requests[index]
		_assert(String(request.get("dest_kind", "")) == "vdest_array", "expected Mauville flowers VDest request")
		_assert(String(request.get("source_array", "")) == expected_arrays[index], "expected Mauville source array")
		_assert(int(request.get("destination_tile_range_index", -1)) == expected_range_index, "expected Mauville request VDest range index")
		_assert(int(request.get("tile_count", 0)) == 4, "expected Mauville flower tile count")
		_assert(int(request.get("selected_source_frame_index", -1)) == expected_source_frame_index, "expected Mauville source frame index")
		var effective_ranges: Array = request.get("effective_tile_ranges", [])
		_assert(effective_ranges.size() == 1, "expected one selected Mauville VDest range")
		if effective_ranges.is_empty() or typeof(effective_ranges[0]) != TYPE_DICTIONARY:
			continue
		var range_record: Dictionary = effective_ranges[0]
		_assert(int(range_record.get("start_tile_id", -1)) == expected_ranges[index][0], "expected Mauville VDest start tile")
		_assert(int(range_record.get("end_tile_id", -1)) == expected_ranges[index][1], "expected Mauville VDest end tile")


func _first_tile_copy_request_for_queue(events: Array, queue_function: String) -> Dictionary:
	var event := _event_for_queue(events, queue_function)
	if event.is_empty():
		return {}
	var requests = event.get("tile_copy_requests", [])
	if typeof(requests) != TYPE_ARRAY or requests.is_empty() or typeof(requests[0]) != TYPE_DICTIONARY:
		return {}
	return requests[0]


func _renderer_summary_for_queue(renderer_update: Dictionary, queue_function: String) -> Dictionary:
	var summaries = renderer_update.get("request_summaries", [])
	if typeof(summaries) != TYPE_ARRAY:
		return {}
	for summary in summaries:
		if typeof(summary) == TYPE_DICTIONARY and String(summary.get("queue_function", "")) == queue_function:
			return summary
	return {}


func _assert_unsupported_for_queue(
	frame_update: Dictionary,
	queue_function: String,
	expected_code: String,
	expected_renderer_status: String
) -> void:
	var unsupported = frame_update.get("unsupported", [])
	_assert(typeof(unsupported) == TYPE_ARRAY, "expected unsupported list for %s" % queue_function)
	if typeof(unsupported) != TYPE_ARRAY:
		return
	_assert(int(frame_update.get("unsupported_count", -1)) == unsupported.size(), "expected unsupported count to match list")
	var entry := _unsupported_for_queue(unsupported, queue_function)
	_assert(not entry.is_empty(), "expected unsupported marker for %s" % queue_function)
	if entry.is_empty():
		return
	_assert(String(entry.get("code", "")) == expected_code, "expected unsupported code for %s" % queue_function)
	_assert(String(entry.get("status", "")) == "unsupported", "expected unsupported status for %s" % queue_function)
	_assert(String(entry.get("renderer_request_status", "")) == expected_renderer_status, "expected renderer request status for %s" % queue_function)
	_assert(String(entry.get("event_callback_symbol", "")) != "", "expected event callback symbol for %s" % queue_function)
	_assert(not bool(entry.get("source_equivalent_for_runtime_rendering", true)), "expected non-equivalent runtime rendering marker for %s" % queue_function)


func _unsupported_for_queue(unsupported: Array, queue_function: String) -> Dictionary:
	for entry in unsupported:
		if typeof(entry) == TYPE_DICTIONARY and String(entry.get("queue_function", "")) == queue_function:
			return entry
	return {}


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
