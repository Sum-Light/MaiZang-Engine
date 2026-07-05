extends SceneTree

const OBJECT_EVENT_PLACEHOLDER := preload("res://scripts/overworld/object_event_placeholder.gd")
const DATA_REGISTRY_SCRIPT := preload("res://scripts/autoload/data_registry.gd")
const GAME_STATE_SCRIPT := preload("res://scripts/autoload/game_state.gd")
const SCRIPT_VM_SCRIPT := preload("res://scripts/autoload/script_vm.gd")

var _failed := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var registry = _install_root_node("DataRegistry", DATA_REGISTRY_SCRIPT.new())
	registry._ready()
	var game_state = _install_root_node("GameState", GAME_STATE_SCRIPT.new())
	var script_vm = _install_root_node("ScriptVM", SCRIPT_VM_SCRIPT.new())
	script_vm.configure_data_registry(registry)
	script_vm.configure_game_state(game_state)
	script_vm.configure_from_script_data(registry.get_start_script_data())

	var sprite_data = registry.get_object_event_sprite_data()
	var stats := _dict_field(sprite_data, "stats")
	_assert(int(stats.get("sprite_count", 0)) == 11, "expected eleven imported first-slice object event sprites")
	var variable_graphics := _dict_field(sprite_data, "variable_graphics")
	_assert(variable_graphics.has("OBJ_EVENT_GFX_VAR_0"), "expected VAR_0 object-event graphics metadata")
	var var_0 := _dict_field(variable_graphics, "OBJ_EVENT_GFX_VAR_0")
	_assert(String(var_0.get("source_var", "")) == "VAR_OBJ_GFX_ID_0", "expected source VAR_OBJ_GFX_ID_0 trace")
	var var_0_constants := _dict_field(var_0, "source_constant_values")
	_assert(int(var_0_constants.get("OBJ_EVENT_GFX_RIVAL_MAY_NORMAL", 0)) == 105, "expected source May rival graphics constant")
	_assert(int(var_0_constants.get("OBJ_EVENT_GFX_RIVAL_BRENDAN_NORMAL", 0)) == 100, "expected source Brendan rival graphics constant")

	var expected_standard_sprites := {
		"OBJ_EVENT_GFX_TWIN": "twin.png",
		"OBJ_EVENT_GFX_BOY_1": "boy_1.png",
		"OBJ_EVENT_GFX_BOY_2": "boy_2.png",
		"OBJ_EVENT_GFX_FAT_MAN": "fat_man.png",
		"OBJ_EVENT_GFX_PROF_BIRCH": "prof_birch.png",
		"OBJ_EVENT_GFX_MOM": "mom.png",
	}
	for graphics_id in expected_standard_sprites.keys():
		var standard_record: Dictionary = registry.get_object_event_sprite_record(graphics_id)
		_assert(not standard_record.is_empty(), "expected %s object event sprite record" % graphics_id)
		_assert(String(standard_record.get("image", "")).ends_with(String(expected_standard_sprites[graphics_id])), "expected %s generated sprite image" % graphics_id)
		_assert(int(standard_record.get("columns", 0)) == 9, "expected %s nine source frames" % graphics_id)
		_assert(int(standard_record.get("rows", 0)) == 1, "expected %s one source row" % graphics_id)
		_assert(_frame_size(standard_record) == Vector2i(16, 32), "expected %s 16x32 source frame size" % graphics_id)
		_assert(not bool(standard_record.get("inanimate", true)), "expected %s animated object-event source flag" % graphics_id)
		_assert(String(standard_record.get("tracks", "")) == "TRACKS_FOOT", "expected %s foot tracks source flag" % graphics_id)
		_assert(String(_dict_field(standard_record, "animation_table").get("source_symbol", "")) == "sAnimTable_Standard", "expected %s standard animation table" % graphics_id)
		_assert(_image_alpha_at(standard_record, Vector2i.ZERO) == 0, "expected %s palette index 0 to be transparent" % graphics_id)
		_assert(_transparency_rule(standard_record) == "gba_obj_palette_index_0_alpha_0", "expected %s source transparency metadata" % graphics_id)
		_assert(_unsupported_has(standard_record, "object_event_walk_animation_not_runtime_driven"), "expected %s runtime walk animation unsupported note" % graphics_id)

	var expected_player_sprites := {
		"OBJ_EVENT_GFX_BRENDAN_NORMAL": {
			"asset": "brendan_normal.png",
			"source_symbol": "gObjectEventPic_BrendanNormalRunning",
			"source_constant_value": 0,
		},
		"OBJ_EVENT_GFX_MAY_NORMAL": {
			"asset": "may_normal.png",
			"source_symbol": "gObjectEventPic_MayNormalRunning",
			"source_constant_value": 89,
		},
	}
	for graphics_id in expected_player_sprites.keys():
		var player_expected: Dictionary = expected_player_sprites[graphics_id]
		var player_record: Dictionary = registry.get_object_event_sprite_record(graphics_id)
		_assert(not player_record.is_empty(), "expected %s player object event sprite record" % graphics_id)
		_assert(String(player_record.get("image", "")).ends_with(String(player_expected.get("asset", ""))), "expected %s generated player sprite image" % graphics_id)
		_assert(String(player_record.get("source_symbol", "")) == String(player_expected.get("source_symbol", "")), "expected %s source pic symbol" % graphics_id)
		_assert(int(player_record.get("source_constant_value", -1)) == int(player_expected.get("source_constant_value", -1)), "expected %s source constant value" % graphics_id)
		_assert(int(player_record.get("columns", 0)) == 18, "expected %s walking+running source frames" % graphics_id)
		_assert(_image_size(player_record) == Vector2i(288, 32), "expected %s 288x32 stitched source image" % graphics_id)
		_assert(_frame_size(player_record) == Vector2i(16, 32), "expected %s 16x32 source frame size" % graphics_id)
		_assert(_image_alpha_at(player_record, Vector2i.ZERO) == 0, "expected %s palette index 0 to be transparent" % graphics_id)
		_assert(_transparency_rule(player_record) == "gba_obj_palette_index_0_alpha_0", "expected %s source transparency metadata" % graphics_id)
		_assert(_source_images_end_with(player_record, ["walking.png", "running.png"]), "expected %s walking+running source images" % graphics_id)
		_assert(_runtime_supported_has(player_record, "player_avatar_normal_walk_source_timed"), "expected %s source-timed normal player walk support note" % graphics_id)
		_assert(not _unsupported_has(player_record, "player_avatar_walk_animation_not_runtime_driven"), "expected %s normal player walk unsupported note to be retired" % graphics_id)
		_assert(_runtime_supported_has(player_record, "player_avatar_turn_in_place_source_timed"), "expected %s source-timed turn-in-place support note" % graphics_id)
		_assert(_unsupported_has(player_record, "player_avatar_run_continuous_fast_walk_spin_animation_not_runtime_driven"), "expected %s runtime run/continuous-fast/spin unsupported note" % graphics_id)

	var expected_rival_sprites := {
		"OBJ_EVENT_GFX_RIVAL_BRENDAN_NORMAL": {
			"asset": "rival_brendan_normal.png",
			"source_symbol": "gObjectEventPic_BrendanNormalRunning",
			"source_constant_value": 100,
		},
		"OBJ_EVENT_GFX_RIVAL_MAY_NORMAL": {
			"asset": "rival_may_normal.png",
			"source_symbol": "gObjectEventPic_MayNormalRunning",
			"source_constant_value": 105,
		},
	}
	for graphics_id in expected_rival_sprites.keys():
		var rival_expected: Dictionary = expected_rival_sprites[graphics_id]
		var rival_record: Dictionary = registry.get_object_event_sprite_record(graphics_id)
		_assert(not rival_record.is_empty(), "expected %s rival object event sprite record" % graphics_id)
		_assert(String(rival_record.get("image", "")).ends_with(String(rival_expected.get("asset", ""))), "expected %s generated stitched sprite image" % graphics_id)
		_assert(String(rival_record.get("source_symbol", "")) == String(rival_expected.get("source_symbol", "")), "expected %s source pic symbol" % graphics_id)
		_assert(int(rival_record.get("source_constant_value", 0)) == int(rival_expected.get("source_constant_value", 0)), "expected %s source constant value" % graphics_id)
		_assert(int(rival_record.get("columns", 0)) == 18, "expected %s walking+running source frames" % graphics_id)
		_assert(int(rival_record.get("rows", 0)) == 1, "expected %s one stitched source row" % graphics_id)
		_assert(_image_size(rival_record) == Vector2i(288, 32), "expected %s 288x32 stitched source image" % graphics_id)
		_assert(_frame_size(rival_record) == Vector2i(16, 32), "expected %s 16x32 source frame size" % graphics_id)
		_assert(_source_images_end_with(rival_record, ["walking.png", "running.png"]), "expected %s walking+running source images" % graphics_id)
		_assert(_unsupported_has(rival_record, "rival_running_spin_animation_not_runtime_driven"), "expected %s runtime run/spin unsupported note" % graphics_id)
		var rival_animation_table := _dict_field(rival_record, "animation_table")
		_assert(String(rival_animation_table.get("source_symbol", "")) == "sAnimTable_BrendanMayNormal", "expected %s Brendan/May animation table" % graphics_id)
		_assert(_frames(_dict_field(rival_animation_table, "run").get("down", [])) == [12, 9, 13, 9], "expected %s source south run cycle" % graphics_id)
		_assert(_frames(_dict_field(rival_animation_table, "spin").get("right", [])) == [2, 0, 2, 1], "expected %s source east spin cycle" % graphics_id)

	var record: Dictionary = registry.get_object_event_sprite_record("OBJ_EVENT_GFX_BOY_1")
	_assert(not record.is_empty(), "expected Boy1 object event sprite record")
	_assert(int(record.get("columns", 0)) == 9, "expected Boy1 nine source frames")
	_assert(_frame_for_direction(record, "down") == 0, "expected source south frame 0")
	_assert(_frame_for_direction(record, "up") == 1, "expected source north frame 1")
	_assert(_frame_for_direction(record, "left") == 2, "expected source west frame 2")
	_assert(_frame_for_direction(record, "right") == 2, "expected source east frame 2")
	_assert(_flip_for_direction(record, "right"), "expected source east frame hFlip")
	_assert(not _flip_for_direction(record, "left"), "expected source west frame unflipped")

	var animation_table := _dict_field(record, "animation_table")
	_assert(String(animation_table.get("source_symbol", "")) == "sAnimTable_Standard", "expected standard animation table")
	var walk_table := _dict_field(animation_table, "walk")
	_assert(_frames(walk_table.get("down", [])) == [3, 0, 4, 0], "expected source south walk cycle")
	_assert(_frames(walk_table.get("up", [])) == [5, 1, 6, 1], "expected source north walk cycle")
	_assert(_frames(walk_table.get("left", [])) == [7, 2, 8, 2], "expected source west walk cycle")
	_assert(_frames(walk_table.get("right", [])) == [7, 2, 8, 2], "expected source east walk cycle")
	_assert(_all_h_flipped(walk_table.get("right", [])), "expected source east walk cycle hFlip")

	var truck_record: Dictionary = registry.get_object_event_sprite_record("OBJ_EVENT_GFX_TRUCK")
	_assert(not truck_record.is_empty(), "expected Truck object event sprite record")
	_assert(String(truck_record.get("image", "")).ends_with("truck.png"), "expected Truck generated sprite image")
	_assert(int(truck_record.get("columns", 0)) == 1, "expected Truck one source frame")
	_assert(int(truck_record.get("rows", 0)) == 1, "expected Truck one source row")
	_assert(_frame_size(truck_record) == Vector2i(48, 48), "expected Truck 48x48 source frame size")
	_assert(bool(truck_record.get("inanimate", false)), "expected Truck inanimate source flag")
	_assert(String(truck_record.get("tracks", "")) == "TRACKS_NONE", "expected Truck no-tracks source flag")
	var truck_animation_table := _dict_field(truck_record, "animation_table")
	_assert(String(truck_animation_table.get("source_symbol", "")) == "sAnimTable_Inanimate", "expected Truck inanimate animation table")
	_assert(_frames(truck_animation_table.get("stay_still", [])) == [0, 0, 0, 0], "expected Truck stay-still frame loop")
	_assert(_image_alpha_at(truck_record, Vector2i.ZERO) == 0, "expected Truck palette index 0 to be transparent")

	game_state.set_player_gender("MALE")
	var male_rival_result = script_vm.run_script("Common_EventScript_SetupRivalGfxId")
	_assert(String(male_rival_result.get("status", "")) == "ok", "expected male rival graphics setup script to execute")
	_assert(game_state.get_var("VAR_OBJ_GFX_ID_0", 0) == 105, "expected male player source rival var to resolve to May")
	var male_resolution = registry.resolve_object_event_graphics_id("OBJ_EVENT_GFX_VAR_0", game_state)
	_assert(bool(male_resolution.get("resolved", false)), "expected male player VAR_0 graphics to resolve")
	_assert(String(male_resolution.get("graphics_id", "")) == "OBJ_EVENT_GFX_RIVAL_MAY_NORMAL", "expected male player VAR_0 graphics to use May")

	game_state.set_player_gender("FEMALE")
	var female_rival_result = script_vm.run_script("Common_EventScript_SetupRivalGfxId")
	_assert(String(female_rival_result.get("status", "")) == "ok", "expected female rival graphics setup script to execute")
	_assert(game_state.get_var("VAR_OBJ_GFX_ID_0", 0) == 100, "expected female player source rival var to resolve to Brendan")
	var female_resolution = registry.resolve_object_event_graphics_id("OBJ_EVENT_GFX_VAR_0", game_state)
	_assert(bool(female_resolution.get("resolved", false)), "expected female player VAR_0 graphics to resolve")
	_assert(String(female_resolution.get("graphics_id", "")) == "OBJ_EVENT_GFX_RIVAL_BRENDAN_NORMAL", "expected female player VAR_0 graphics to use Brendan")

	var placeholder = OBJECT_EVENT_PLACEHOLDER.new()
	get_root().add_child(placeholder)
	placeholder.configure({
		"graphics_id": "OBJ_EVENT_GFX_BOY_1",
		"position": Vector2i.ZERO,
		"facing_direction": "right",
	}, 16)
	await process_frame
	var right_snapshot: Dictionary = placeholder.get_sprite_snapshot()
	_assert(bool(right_snapshot.get("using_sprite", false)), "expected placeholder to use generated Boy1 sprite")
	_assert(_array_field(right_snapshot, "source_rect") == [32, 0, 16, 32], "expected east static source rect")
	_assert(_array_field(right_snapshot, "dest_rect") == [-8, -24, 16, 32], "expected 16x32 object source sprite bottom-of-tile dest rect")
	_assert(bool(right_snapshot.get("h_flip", false)), "expected east static frame hFlip")
	_assert(_array_field(right_snapshot, "world_position") == [8, 8], "expected placeholder to anchor at tile center")
	var right_depth := _dict_field(right_snapshot, "depth")
	_assert(int(right_depth.get("source_oam_priority", -1)) == 2, "expected default object source OAM priority")
	_assert(String(right_depth.get("runtime_layer_band", "")) == "between_middle_and_top", "expected object to render between middle and top layers")
	_assert(int(right_snapshot.get("z_index", 0)) == int(right_depth.get("godot_z_index", -1)), "expected placeholder z-index to match depth contract")
	_assert(int(right_depth.get("godot_z_index", 0)) < int(right_depth.get("top_layer_z_index", 0)), "expected placeholder below top layer")

	placeholder.configure({
		"graphics_id": "OBJ_EVENT_GFX_BOY_1",
		"position": Vector2i.ZERO,
		"facing_direction": "up",
	}, 16)
	await process_frame
	var up_snapshot: Dictionary = placeholder.get_sprite_snapshot()
	_assert(_array_field(up_snapshot, "source_rect") == [16, 0, 16, 32], "expected north static source rect")
	_assert(not bool(up_snapshot.get("h_flip", false)), "expected north static frame unflipped")

	placeholder.configure({
		"graphics_id": "OBJ_EVENT_GFX_TRUCK",
		"position": Vector2i.ZERO,
		"facing_direction": "down",
	}, 16)
	await process_frame
	var truck_snapshot: Dictionary = placeholder.get_sprite_snapshot()
	_assert(bool(truck_snapshot.get("using_sprite", false)), "expected placeholder to use generated Truck sprite")
	_assert(_array_field(truck_snapshot, "source_rect") == [0, 0, 48, 48], "expected Truck source rect")
	_assert(_array_field(truck_snapshot, "dest_rect") == [-24, -40, 48, 48], "expected Truck 48x48 point-drawn destination rect")
	_assert(not bool(truck_snapshot.get("h_flip", false)), "expected Truck static frame unflipped")
	var truck_depth := _dict_field(truck_snapshot, "depth")
	_assert(String(truck_depth.get("runtime_layer_band", "")) == "between_middle_and_top", "expected Truck to share default object depth band")

	placeholder.configure({
		"graphics_id": "OBJ_EVENT_GFX_VAR_0",
		"position": Vector2i.ZERO,
		"facing_direction": "up",
	}, 16)
	await process_frame
	var rival_snapshot: Dictionary = placeholder.get_sprite_snapshot()
	_assert(bool(rival_snapshot.get("using_sprite", false)), "expected placeholder to use resolved rival sprite")
	_assert(String(rival_snapshot.get("resolved_graphics_id", "")) == "OBJ_EVENT_GFX_RIVAL_BRENDAN_NORMAL", "expected resolved Brendan rival graphics")
	_assert(_array_field(rival_snapshot, "source_rect") == [16, 0, 16, 32], "expected resolved rival north static source rect")

	placeholder.queue_free()

	if _failed:
		return

	print(JSON.stringify({
		"object_event_sprite_smoke": "ok",
		"right_source_rect": right_snapshot.get("source_rect", []),
		"right_h_flip": right_snapshot.get("h_flip", false),
		"right_world_position": right_snapshot.get("world_position", []),
		"right_z_index": right_snapshot.get("z_index", 0),
		"truck_source_rect": truck_snapshot.get("source_rect", []),
		"rival_resolved_graphics_id": rival_snapshot.get("resolved_graphics_id", ""),
	}))
	quit(0)


func _install_root_node(node_name: String, node: Node):
	var existing := get_root().get_node_or_null(node_name)
	if existing != null:
		return existing
	node.name = node_name
	get_root().add_child(node)
	return node


func _frame_for_direction(record: Dictionary, direction: String) -> int:
	var static_frames := _dict_field(record, "static_frames")
	return int(static_frames.get(direction, -1))


func _flip_for_direction(record: Dictionary, direction: String) -> bool:
	var static_frame_flips := _dict_field(record, "static_frame_flips")
	var flip_info = static_frame_flips.get(direction, {})
	if typeof(flip_info) != TYPE_DICTIONARY:
		return false
	return bool(flip_info.get("h", false))


func _frames(value) -> Array:
	var result := []
	if typeof(value) != TYPE_ARRAY:
		return result
	for entry in value:
		if typeof(entry) == TYPE_DICTIONARY:
			result.append(int(entry.get("frame", -1)))
	return result


func _all_h_flipped(value) -> bool:
	if typeof(value) != TYPE_ARRAY or value.is_empty():
		return false
	for entry in value:
		if typeof(entry) != TYPE_DICTIONARY or not bool(entry.get("h_flip", false)):
			return false
	return true


func _frame_size(record: Dictionary) -> Vector2i:
	var frame_size_info := _dict_field(record, "frame_size")
	return Vector2i(
		int(frame_size_info.get("w", 0)),
		int(frame_size_info.get("h", 0))
	)


func _image_size(record: Dictionary) -> Vector2i:
	var image_size_info := _dict_field(record, "image_size")
	return Vector2i(
		int(image_size_info.get("w", 0)),
		int(image_size_info.get("h", 0))
	)


func _dict_field(record: Dictionary, key: String) -> Dictionary:
	var value = record.get(key, {})
	return value if typeof(value) == TYPE_DICTIONARY else {}


func _array_field(record: Dictionary, key: String) -> Array:
	var value = record.get(key, [])
	return value if typeof(value) == TYPE_ARRAY else []


func _image_alpha_at(record: Dictionary, position: Vector2i) -> int:
	var image_path := String(record.get("image", ""))
	if image_path.is_empty():
		return -1
	if image_path.begins_with("res://") or image_path.begins_with("user://"):
		image_path = ProjectSettings.globalize_path(image_path)
	var image := Image.new()
	if image.load(image_path) != OK:
		return -1
	return image.get_pixel(position.x, position.y).a8


func _transparency_rule(record: Dictionary) -> String:
	return String(_dict_field(record, "transparency").get("rule", ""))


func _source_images_end_with(record: Dictionary, endings: Array) -> bool:
	var source_images = record.get("source_images", [])
	if typeof(source_images) != TYPE_ARRAY or source_images.size() != endings.size():
		return false
	for i in range(endings.size()):
		if not String(source_images[i]).ends_with(String(endings[i])):
			return false
	return true


func _unsupported_has(record: Dictionary, code: String) -> bool:
	var unsupported = record.get("unsupported", [])
	if typeof(unsupported) != TYPE_ARRAY:
		return false
	for entry in unsupported:
		if typeof(entry) == TYPE_DICTIONARY and String(entry.get("code", "")) == code:
			return true
	return false


func _runtime_supported_has(record: Dictionary, code: String) -> bool:
	var runtime_supported = record.get("runtime_supported", [])
	if typeof(runtime_supported) != TYPE_ARRAY:
		return false
	for entry in runtime_supported:
		if typeof(entry) == TYPE_DICTIONARY and String(entry.get("code", "")) == code:
			return true
	return false


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)
	quit(1)
