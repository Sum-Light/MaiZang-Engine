extends SceneTree

const DATA_REGISTRY_SCRIPT := preload("res://scripts/autoload/data_registry.gd")
const MAP_RUNTIME_SCRIPT := preload("res://scripts/autoload/map_runtime.gd")
const TILESET_ANIMATION_PLAYER_SCRIPT := preload("res://scripts/overworld/tileset_animation_player.gd")
const START_MAP := "MAP_LITTLEROOT_TOWN"

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

	var player = TILESET_ANIMATION_PLAYER_SCRIPT.new()
	player.configure(registry, runtime)
	runtime.configure_from_data(map_data, tileset_data, _map_size_from_data(map_data))

	var snapshot: Dictionary = player.get_initialization_status()
	_assert(String(snapshot.get("owner", "")) == "TilesetAnimationPlayer", "expected owner")
	_assert(
		String(snapshot.get("status", "")) == "initialized_from_source_schedule_metadata",
		"expected source schedule initialization status"
	)
	_assert(String(snapshot.get("runtime_playback_status", "")) == "not_started_metadata_only_initialization", "expected playback to remain pending")
	_assert(bool(snapshot.get("initialized_on_map_load", false)), "expected map-load initialization")
	_assert(not bool(snapshot.get("source_equivalent_for_runtime_playback", true)), "expected playback to remain non-equivalent")
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
	_assert(bool(primary.get("initialized_on_map_load", false)), "expected General initialized on map load")
	_assert(bool(primary.get("has_tile_animation_callback", false)), "expected General animation callback")
	_assert(not bool(primary.get("active_runtime_callback", true)), "expected runtime callback to remain inactive until playback task")
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
	_assert(bool(secondary.get("initialized_on_map_load", false)), "expected Petalburg initialized on map load")
	_assert(not bool(secondary.get("has_tile_animation_callback", true)), "expected Petalburg no tile animation callback")
	_assert(int(secondary.get("schedule_event_count", -1)) == 0, "expected Petalburg no schedule events")

	var active_states: Array = player.get_active_tileset_states()
	_assert(active_states.size() == 1, "expected one active state")
	_assert(String(active_states[0].get("tileset_symbol", "")) == "gTileset_General", "expected General active state")

	var unsupported: Array = snapshot.get("unsupported", [])
	_assert(_has_unsupported_code(unsupported, "tileset_animation_playback_pending"), "expected playback pending marker")
	_assert(_has_unsupported_code(unsupported, "tileset_animation_independent_counters_pending"), "expected counter pending marker")
	_assert(_has_unsupported_code(unsupported, "tileset_animation_renderer_tile_update_pending"), "expected renderer update pending marker")

	if _failed:
		quit(1)
	else:
		print("Tileset animation player smoke passed")
		quit(0)


func _map_size_from_data(map_data: Dictionary) -> Vector2i:
	var layout = map_data.get("layout", {})
	if typeof(layout) != TYPE_DICTIONARY:
		return Vector2i.ZERO
	return Vector2i(int(layout.get("width", 0)), int(layout.get("height", 0)))


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
