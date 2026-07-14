extends SceneTree

const MapAnimationController = preload("res://scripts/platinum_map_animation_controller.gd")
const EPSILON := 0.0001

var _completion_result: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var controller := MapAnimationController.new()
	controller.name = "MapAnimationController"
	root.add_child(controller)
	controller.set_physics_process(false)

	var loop_fixture := _make_fixture("LoopProp", [
		{"name": "loop", "from": 0.0, "to": 1.0, "length": 7.0 / 60.0},
	])
	var loop_root := loop_fixture.root as Node3D
	root.add_child(loop_root)
	var loop_animation := loop_fixture.animations[0] as Animation
	var loop_result := controller.register_map_prop(
		&"cell_0_prop_0",
		loop_root,
		{"map_animation": _native_descriptor("automatic_loop", false, 0, [
			_native_slot(0, "loop", "loop", "nsbca", "native_gltf", 8),
		])}
	)
	if not bool(loop_result.get("ok", false)):
		_fail(String(loop_result.get("error", "Automatic MapProp registration failed.")))
		return

	controller._physics_process(1.0 / 60.0)
	if not is_equal_approx(float((loop_fixture.target as Node3D).position.x), 0.0):
		_fail("Automatic animation advanced before one 30 Hz source frame elapsed.")
		return
	controller._physics_process(1.0 / 60.0)
	var expected_loop_seek_time := 1.0 / 60.0
	var expected_loop_value := 1.0 / 7.0
	if (
		absf(float((loop_fixture.target as Node3D).position.x) - expected_loop_value) > EPSILON
		or absf(
			float((loop_fixture.player as AnimationPlayer).current_animation_position)
			- expected_loop_seek_time
		) > EPSILON
	):
		_fail("Automatic animation did not seek to the shared 30 Hz source frame.")
		return

	var delayed_fixture := _make_fixture("DelayedLoopProp", [
		{"name": "loop", "from": 0.0, "to": 1.0, "length": 7.0 / 60.0},
	])
	var delayed_root := delayed_fixture.root as Node3D
	root.add_child(delayed_root)
	var delayed_result := controller.register_map_prop(
		&"cell_0_prop_1",
		delayed_root,
		_native_descriptor("automatic_loop", false, 0, [
			_native_slot(0, "loop", "loop", "nsbca", "native_gltf", 8),
		])
	)
	if not bool(delayed_result.get("ok", false)):
		_fail(String(delayed_result.get("error", "Delayed MapProp registration failed.")))
		return
	if absf(
		float((delayed_fixture.target as Node3D).position.x)
		- float((loop_fixture.target as Node3D).position.x)
	) > EPSILON:
		_fail("A delayed automatic MapProp did not join the global animation phase.")
		return
	for frame in 7:
		controller._physics_process(1.0 / 30.0)
	if (
		not (loop_fixture.target as Node3D).position.is_zero_approx()
		or not (delayed_fixture.target as Node3D).position.is_zero_approx()
	):
		_fail("Automatic MapProp animation did not wrap by source_frame_count.")
		return

	var door_fixture := _make_fixture("DoorProp", [
		{"name": "open", "from": 0.0, "to": 1.0, "length": 3.0 / 60.0},
		{"name": "close", "from": 1.0, "to": 0.0, "length": 3.0 / 60.0},
	])
	var door_root := door_fixture.root as Node3D
	root.add_child(door_root)
	var door_result := controller.register_map_prop(
		&"cell_0_door_0",
		door_root,
		_native_descriptor("deferred", true, -1, [
			_native_slot(0, "open", "open", "nsbca", "native_gltf", 4),
			_native_slot(1, "close", "close", "nsbca", "native_gltf", 4),
		])
	)
	if not bool(door_result.get("ok", false)):
		_fail(String(door_result.get("error", "Door MapProp registration failed.")))
		return

	var json_fixture := _make_fixture("JsonDoorProp", [
		{"name": "open", "from": 0.0, "to": 1.0, "length": 3.0 / 60.0},
		{"name": "close", "from": 1.0, "to": 0.0, "length": 3.0 / 60.0},
	])
	var json_root := json_fixture.root as Node3D
	root.add_child(json_root)
	var json_descriptor_value: Variant = JSON.parse_string(JSON.stringify(
		_native_descriptor("deferred", true, -1, [
			_native_slot(0, "open", "open", "nsbca", "native_gltf", 4),
			_native_slot(1, "close", "close", "nsbca", "native_gltf", 4),
		])
	))
	if not json_descriptor_value is Dictionary:
		_fail("MapProp JSON descriptor fixture did not round-trip as a dictionary.")
		return
	var json_result := controller.register_map_prop(
		&"cell_0_json_door_0",
		json_root,
		json_descriptor_value as Dictionary
	)
	if not bool(json_result.get("ok", false)):
		_fail(String(json_result.get("error", "JSON MapProp registration failed.")))
		return
	controller.unregister_map_prop(&"cell_0_json_door_0")
	json_root.queue_free()

	var fractional_fixture := _make_fixture("FractionalProp", [
		{"name": "loop", "from": 0.0, "to": 1.0, "length": 7.0 / 60.0},
	])
	var fractional_root := fractional_fixture.root as Node3D
	root.add_child(fractional_root)
	var fractional_descriptor := _native_descriptor("automatic_loop", false, 0, [
		_native_slot(0, "loop", "loop", "nsbca", "native_gltf", 8),
	])
	(fractional_descriptor.slots as Array)[0].source_frame_count = 8.5
	var fractional_result := controller.register_map_prop(
		&"cell_0_fractional_0",
		fractional_root,
		fractional_descriptor
	)
	if String(fractional_result.get("reason", "")) != "invalid_source_frames":
		_fail("MapProp animation accepted a fractional JSON integer field.")
		return
	fractional_root.queue_free()
	var open_result := controller.play_one_shot(&"cell_0_door_0", 0)
	if not bool(open_result.get("ok", false)) or typeof(open_result.get("completion")) != TYPE_SIGNAL:
		_fail("Door open did not return a usable completion signal.")
		return
	(open_result.completion as Signal).connect(_record_completion)
	for frame in 2:
		controller._physics_process(1.0 / 30.0)
	if not _completion_result.is_empty():
		_fail("Door one-shot completed before all source frames were displayed.")
		return
	controller._physics_process(1.0 / 30.0)
	if (
		not bool(_completion_result.get("ok", false))
		or String(_completion_result.get("status", "")) != "completed"
		or int(_completion_result.get("slot", -1)) != 0
		or absf(float((door_fixture.target as Node3D).position.x) - 1.0) > EPSILON
	):
		_fail("Door open one-shot did not finish at its final source frame.")
		return

	_completion_result = {}
	var close_result := controller.play_one_shot(&"cell_0_door_0", 1)
	if not bool(close_result.get("ok", false)):
		_fail(String(close_result.get("error", "Door close did not start.")))
		return
	(close_result.completion as Signal).connect(_record_completion)
	for frame in 3:
		controller._physics_process(1.0 / 30.0)
	if (
		not bool(_completion_result.get("ok", false))
		or int(_completion_result.get("slot", -1)) != 1
		or absf(float((door_fixture.target as Node3D).position.x)) > EPSILON
	):
		_fail("Door close one-shot did not finish at its final source frame.")
		return

	var unsupported_fixture := _make_fixture("UnsupportedProp", [
		{"name": "unused", "from": 0.0, "to": 1.0, "length": 3.0 / 60.0},
	])
	var unsupported_root := unsupported_fixture.root as Node3D
	root.add_child(unsupported_root)
	var unsupported_result := controller.register_map_prop(
		&"cell_0_unsupported_0",
		unsupported_root,
		_native_descriptor("deferred", true, -1, [
			_native_slot(0, "open", "unused", "nsbta", "unsupported_deferred", 4),
			{
				"slot": 1,
				"archive_id": 1,
				"role": "close",
				"animation_name": "unused",
				"source_frame_count": 4,
				"gltf_fps": 60,
				"duration_seconds": 4.0 / 30.0,
				"magic": "BTP0",
				"runtime_support": "unsupported_deferred",
			},
		])
	)
	if (
		String(unsupported_result.get("status", "")) != "unsupported"
		or String(unsupported_result.get("reason", "")) != "unsupported_bta"
	):
		_fail("Unsupported door descriptor was not indexed explicitly.")
		return
	var bta_result := controller.play_one_shot(&"cell_0_unsupported_0", 0)
	var btp_result := controller.play_one_shot(&"cell_0_unsupported_0", 1)
	if (
		String(bta_result.get("status", "")) != "unsupported"
		or String(bta_result.get("reason", "")) != "unsupported_bta"
		or String(btp_result.get("status", "")) != "unsupported"
		or String(btp_result.get("reason", "")) != "unsupported_btp"
		or not (unsupported_fixture.target as Node3D).position.is_zero_approx()
	):
		_fail("BTA/BTP MapProp animations were not rejected explicitly.")
		return
	var unsupported_auto_fixture := _make_fixture("UnsupportedAutoProp", [
		{"name": "unused", "from": 0.0, "to": 1.0, "length": 3.0 / 60.0},
	])
	var unsupported_auto_root := unsupported_auto_fixture.root as Node3D
	root.add_child(unsupported_auto_root)
	var unsupported_auto_result := controller.register_map_prop(
		&"cell_0_unsupported_auto_0",
		unsupported_auto_root,
		_native_descriptor("automatic_loop", false, -1, [
			_native_slot(0, "loop", "unused", "nsbta", "unsupported_deferred", 4),
		], "deferred")
	)
	if (
		String(unsupported_auto_result.get("status", "")) != "unsupported"
		or String(unsupported_auto_result.get("reason", "")) != "unsupported_bta"
		or not (unsupported_auto_fixture.target as Node3D).position.is_zero_approx()
	):
		_fail("An unsupported automatic slot was not retained as an explicit no-op.")
		return

	var loop_position_before_unregister := float((loop_fixture.target as Node3D).position.x)
	var unregister_result := controller.unregister_map_prop(&"cell_0_prop_0")
	controller._physics_process(1.0 / 30.0)
	if (
		not bool(unregister_result.get("ok", false))
		or absf(float((loop_fixture.target as Node3D).position.x) - loop_position_before_unregister) > EPSILON
	):
		_fail("Unregistered MapProp animation continued to advance.")
		return

	var delayed_weak_ref: WeakRef = weakref(delayed_root)
	delayed_root.free()
	controller._physics_process(1.0 / 30.0)
	if delayed_weak_ref.get_ref() != null:
		_fail("MapProp controller retained a released root strongly.")
		return
	var stats := controller.get_stats()
	if (
		int(stats.get("registered", -1)) != 3
		or int(stats.get("automatic_loops", -1)) != 0
		or int(stats.get("active_one_shots", -1)) != 0
		or int(stats.get("unsupported_slots", -1)) != 3
		or int(stats.get("pruned", -1)) < 1
	):
		_fail("MapProp animation stats did not reflect unregister, pruning, or unsupported slots.")
		return
	if (
		not is_equal_approx(loop_animation.length, 7.0 / 60.0)
		or loop_animation.track_get_key_value(0, 1) != 1.0
	):
		_fail("MapProp controller mutated a shared Animation resource.")
		return

	var clear_result := controller.clear()
	if not bool(clear_result.get("ok", false)) or int(controller.get_stats().registered) != 0:
		_fail("MapProp animation controller did not clear all registrations.")
		return
	print("MAP_PROP_ANIMATION_OK ", JSON.stringify({
		"source_frame": int(stats.get("source_frame", -1)),
		"global_loop_seek_time": expected_loop_seek_time,
		"door_slots": 2,
		"unsupported_slots": 2,
		"weak_root_released": true,
		"json_integral_numbers": true,
		"world_scan_per_frame": false,
	}))
	controller.queue_free()
	loop_root.queue_free()
	door_root.queue_free()
	unsupported_root.queue_free()
	unsupported_auto_root.queue_free()
	quit(0)


func _make_fixture(fixture_name: String, animation_specs: Array[Dictionary]) -> Dictionary:
	var fixture_root := Node3D.new()
	fixture_root.name = fixture_name
	var target := Node3D.new()
	target.name = "Animated"
	fixture_root.add_child(target)
	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	fixture_root.add_child(player)
	var library := AnimationLibrary.new()
	var animations: Array[Animation] = []
	for spec in animation_specs:
		var animation := Animation.new()
		animation.length = float(spec.length)
		var track := animation.add_track(Animation.TYPE_VALUE)
		animation.track_set_path(track, NodePath("Animated:position:x"))
		animation.track_set_interpolation_type(track, Animation.INTERPOLATION_LINEAR)
		animation.track_insert_key(track, 0.0, float(spec.from))
		animation.track_insert_key(track, animation.length, float(spec.to))
		library.add_animation(StringName(spec.name), animation)
		animations.append(animation)
	player.add_animation_library(&"", library)
	return {
		"root": fixture_root,
		"target": target,
		"player": player,
		"animations": animations,
	}


func _native_descriptor(
	playback: String,
	is_door: bool,
	auto_play_slot: int,
	slots: Array,
	runtime_playback: String = ""
) -> Dictionary:
	var effective_runtime_playback := playback if runtime_playback.is_empty() else runtime_playback
	return {
		"schema_version": 1,
		"model_id": 1,
		"playback": playback,
		"runtime_playback": effective_runtime_playback,
		"is_door": is_door,
		"auto_play_slot": auto_play_slot,
		"slots": slots,
	}


func _native_slot(
	slot: int,
	role: String,
	animation_name: String,
	source_format: String,
	runtime_support: String,
	source_frame_count: int
) -> Dictionary:
	return {
		"slot": slot,
		"archive_id": slot,
		"role": role,
		"animation_name": animation_name,
		"source_format": source_format,
		"runtime_support": runtime_support,
		"source_frame_count": source_frame_count,
		"gltf_fps": 60,
		"duration_seconds": (
			float(source_frame_count) / 30.0
			if role == "loop"
			else float(source_frame_count - 1) / 30.0
		),
	}


func _record_completion(result: Dictionary) -> void:
	_completion_result = result


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
