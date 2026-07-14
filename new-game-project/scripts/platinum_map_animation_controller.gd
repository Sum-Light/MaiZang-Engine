class_name PlatinumMapAnimationController
extends Node

const SOURCE_FPS := 30.0
const SOURCE_FRAME_SECONDS := 1.0 / SOURCE_FPS
const LOOP_PLAYBACK := &"automatic_loop"
const NATIVE_GLTF_SUPPORT := &"native_gltf"


class PlaybackTicket:
	extends RefCounted

	signal completed(result: Dictionary)

	var token: int

	func _init(next_token: int) -> void:
		token = next_token

	func finish(result: Dictionary) -> void:
		completed.emit(result)


var _entries: Dictionary = {}
var _root_owners: Dictionary = {}
var _source_frame := 0
var _source_accumulator := 0.0
var _next_token := 1
var _pruned_entries := 0


func _physics_process(delta: float) -> void:
	if delta <= 0.0 or not is_finite(delta):
		return
	_source_accumulator += delta
	var elapsed_frames := int(floor(_source_accumulator / SOURCE_FRAME_SECONDS))
	if elapsed_frames <= 0:
		return
	_source_accumulator -= float(elapsed_frames) * SOURCE_FRAME_SECONDS
	_source_frame += elapsed_frames
	if not _entries.is_empty():
		_advance_registered_animations(elapsed_frames)


func register_map_prop(
	stable_id: StringName,
	root: Node3D,
	descriptor: Dictionary
) -> Dictionary:
	if String(stable_id).is_empty():
		return _error_result("invalid_stable_id", "MapProp animation stable ID is empty.")
	if root == null or not is_instance_valid(root):
		return _error_result("invalid_root", "MapProp animation root is unavailable.")

	if _entries.has(stable_id):
		unregister_map_prop(stable_id)
	var root_instance_id := root.get_instance_id()
	if _root_owners.has(root_instance_id):
		return _error_result(
			"duplicate_root",
			"MapProp animation root is already registered as %s." % _root_owners[root_instance_id]
		)

	var map_descriptor := descriptor
	var nested_descriptor_value: Variant = descriptor.get("map_animation", null)
	if nested_descriptor_value is Dictionary:
		map_descriptor = nested_descriptor_value as Dictionary
	var schema_result := _parse_integral_number(map_descriptor.get("schema_version", null))
	if not bool(schema_result.get("ok", false)) or int(schema_result.value) != 1:
		return _error_result("invalid_schema", "MapProp animation descriptor schema is not 1.")
	var source_playback := StringName(String(map_descriptor.get("playback", "")))
	if source_playback not in [LOOP_PLAYBACK, &"deferred"]:
		return _error_result("invalid_playback", "MapProp source playback mode is invalid.")
	var playback := StringName(String(map_descriptor.get("runtime_playback", "")))
	if playback not in [LOOP_PLAYBACK, &"deferred"]:
		return _error_result("invalid_playback", "MapProp runtime playback mode is invalid.")
	if playback == LOOP_PLAYBACK and source_playback != LOOP_PLAYBACK:
		return _error_result("invalid_playback", "Deferred source animation cannot auto-play.")
	var is_door_value: Variant = map_descriptor.get("is_door", null)
	if typeof(is_door_value) != TYPE_BOOL:
		return _error_result("invalid_door_flag", "MapProp animation descriptor has no boolean is_door.")
	var is_door := bool(is_door_value)
	var auto_play_slot_value: Variant = map_descriptor.get("auto_play_slot", null)
	var auto_play_slot_result := _parse_integral_number(auto_play_slot_value)
	if not bool(auto_play_slot_result.get("ok", false)):
		return _error_result("invalid_auto_play_slot", "MapProp animation descriptor has no integer auto_play_slot.")
	var auto_play_slot := int(auto_play_slot_result.value)
	if (
		(playback == LOOP_PLAYBACK and (is_door or auto_play_slot not in [-1, 0]))
		or (playback == &"deferred" and auto_play_slot != -1)
	):
		return _error_result(
			"invalid_playback_contract",
			"MapProp animation playback, door, and auto-play fields disagree."
		)
	var slots_value: Variant = map_descriptor.get("slots", null)
	if not slots_value is Array:
		return _error_result("invalid_slots", "MapProp animation descriptor has no slot array.")

	var entry := {
		"root_ref": weakref(root),
		"root_instance_id": root_instance_id,
		"playback": playback,
		"is_door": is_door,
		"auto_play_slot": auto_play_slot,
		"slots": {},
		"unsupported_slots": {},
		"player_states": [],
		"one_shot": {},
	}
	var slots := entry.slots as Dictionary
	var unsupported_slots := entry.unsupported_slots as Dictionary
	var player_states := entry.player_states as Array

	for slot_value in slots_value as Array:
		if not slot_value is Dictionary:
			_restore_players(player_states)
			return _error_result("invalid_slot", "MapProp animation slot is not a dictionary.")
		var slot_descriptor := slot_value as Dictionary
		var slot_number_value: Variant = slot_descriptor.get("slot", null)
		var slot_number_result := _parse_integral_number(slot_number_value)
		if not bool(slot_number_result.get("ok", false)):
			_restore_players(player_states)
			return _error_result("invalid_slot", "MapProp animation slot has no integer index.")
		var slot_number := int(slot_number_result.value)
		if slot_number < 0 or slots.has(slot_number) or unsupported_slots.has(slot_number):
			_restore_players(player_states)
			return _error_result("invalid_slot", "MapProp animation slot index is invalid or duplicated.")

		var unsupported_reason := _unsupported_slot_reason(slot_descriptor)
		if not unsupported_reason.is_empty():
			unsupported_slots[slot_number] = unsupported_reason
			continue
		var slot_result := _resolve_native_slot(root, slot_descriptor)
		if not bool(slot_result.get("ok", false)):
			_restore_players(player_states)
			return slot_result
		var slot := slot_result.slot as Dictionary
		slots[slot_number] = slot
		_prepare_player(slot.player_ref as WeakRef, player_states)

	if playback == LOOP_PLAYBACK:
		if auto_play_slot == -1:
			if unsupported_slots.has(0):
				_store_entry(stable_id, entry)
				return _unsupported_result(stable_id, 0, String(unsupported_slots[0]))
			_restore_players(player_states)
			return _error_result(
				"invalid_auto_play_slot",
				"Automatic MapProp animation has no supported or explicitly unsupported slot 0."
			)
		if unsupported_slots.has(auto_play_slot):
			_store_entry(stable_id, entry)
			return _unsupported_result(
				stable_id,
				auto_play_slot,
				String(unsupported_slots[auto_play_slot])
			)
		if not slots.has(auto_play_slot):
			_restore_players(player_states)
			return _error_result("missing_loop_slot", "Automatic MapProp animation has no slot 0.")
		var loop_slot := slots[auto_play_slot] as Dictionary
		if StringName(loop_slot.role) != &"loop":
			_restore_players(player_states)
			return _error_result("invalid_loop_role", "Automatic MapProp slot 0 is not a loop role.")
		if not _seek_slot(loop_slot, _loop_seek_time(loop_slot)):
			_restore_players(player_states)
			return _error_result("animation_player_unavailable", "Automatic animation player was released.")

	if slots.is_empty() and not unsupported_slots.is_empty():
		var unsupported_slot_numbers := unsupported_slots.keys()
		unsupported_slot_numbers.sort()
		var first_unsupported_slot := int(unsupported_slot_numbers[0])
		_store_entry(stable_id, entry)
		return _unsupported_result(
			stable_id,
			first_unsupported_slot,
			String(unsupported_slots[first_unsupported_slot])
		)

	_store_entry(stable_id, entry)
	return {
		"ok": true,
		"status": "registered",
		"stable_id": stable_id,
		"native_slots": slots.size(),
		"unsupported_slots": unsupported_slots.keys(),
		"automatic_loop": playback == LOOP_PLAYBACK,
		"door_one_shot": is_door,
	}


func unregister_map_prop(stable_id: StringName) -> Dictionary:
	if not _entries.has(stable_id):
		return _error_result("not_registered", "MapProp animation is not registered.")
	_remove_entry(stable_id, "unregistered", false)
	return {
		"ok": true,
		"status": "unregistered",
		"stable_id": stable_id,
	}


func play_one_shot(stable_id: StringName, slot: int) -> Dictionary:
	if not _entries.has(stable_id):
		return _error_result("not_registered", "MapProp animation is not registered.")
	var entry := _entries[stable_id] as Dictionary
	if not _entry_root_is_alive(entry):
		_remove_entry(stable_id, "root_released", true)
		return _error_result("root_released", "MapProp animation root was released.")
	if not bool(entry.is_door) or slot not in [0, 1]:
		return _error_result("unsupported_trigger", "Only door slots 0 and 1 support one-shot playback.")
	var unsupported_slots := entry.unsupported_slots as Dictionary
	if unsupported_slots.has(slot):
		return _unsupported_result(stable_id, slot, String(unsupported_slots[slot]))
	var slots := entry.slots as Dictionary
	if not slots.has(slot):
		return _error_result("missing_slot", "MapProp animation slot %d is unavailable." % slot)
	var expected_role := &"open" if slot == 0 else &"close"
	if StringName((slots[slot] as Dictionary).role) != expected_role:
		return _error_result("invalid_door_role", "Door animation slot does not match its open/close role.")
	var current_one_shot := entry.one_shot as Dictionary
	if not current_one_shot.is_empty():
		return _error_result("busy", "MapProp animation already has an active one-shot.")

	var native_slot := slots[slot] as Dictionary
	if not _seek_slot(native_slot, 0.0):
		_remove_entry(stable_id, "animation_player_released", true)
		return _error_result("animation_player_released", "MapProp animation player was released.")
	var token := _next_token
	_next_token += 1
	var ticket := PlaybackTicket.new(token)
	entry.one_shot = {
		"slot": slot,
		"token": token,
		"elapsed_ticks": 0,
		"total_ticks": int(native_slot.source_frame_count) - 1,
		"ticket": ticket,
	}
	_entries[stable_id] = entry
	return {
		"ok": true,
		"status": "started",
		"stable_id": stable_id,
		"slot": slot,
		"token": token,
		"completion": ticket.completed,
	}


func clear() -> Dictionary:
	var removed := _entries.size()
	for stable_id_value in _entries.keys():
		_remove_entry(StringName(stable_id_value), "cleared", false)
	return {
		"ok": true,
		"status": "cleared",
		"removed": removed,
	}


func get_stats() -> Dictionary:
	_prune_released_entries()
	var automatic_loops := 0
	var active_one_shots := 0
	var unsupported_slots := 0
	for entry_value in _entries.values():
		var entry := entry_value as Dictionary
		if StringName(entry.playback) == LOOP_PLAYBACK and (entry.slots as Dictionary).has(0):
			automatic_loops += 1
		if not (entry.one_shot as Dictionary).is_empty():
			active_one_shots += 1
		unsupported_slots += (entry.unsupported_slots as Dictionary).size()
	return {
		"registered": _entries.size(),
		"automatic_loops": automatic_loops,
		"active_one_shots": active_one_shots,
		"unsupported_slots": unsupported_slots,
		"source_frame": _source_frame,
		"pruned": _pruned_entries,
	}


func _advance_registered_animations(elapsed_frames: int) -> void:
	for stable_id_value in _entries.keys():
		var stable_id := StringName(stable_id_value)
		if not _entries.has(stable_id):
			continue
		var entry := _entries[stable_id] as Dictionary
		if not _entry_root_is_alive(entry):
			_remove_entry(stable_id, "root_released", true)
			continue
		var slots := entry.slots as Dictionary
		if StringName(entry.playback) == LOOP_PLAYBACK and slots.has(0):
			var loop_slot := slots[0] as Dictionary
			if not _seek_slot(loop_slot, _loop_seek_time(loop_slot)):
				_remove_entry(stable_id, "animation_player_released", true)
				continue
		var one_shot := entry.one_shot as Dictionary
		if one_shot.is_empty():
			continue
		var one_shot_slot_number := int(one_shot.slot)
		if not slots.has(one_shot_slot_number):
			_remove_entry(stable_id, "animation_slot_released", true)
			continue
		one_shot.elapsed_ticks = mini(
			int(one_shot.total_ticks),
			int(one_shot.elapsed_ticks) + elapsed_frames
		)
		var one_shot_slot := slots[one_shot_slot_number] as Dictionary
		var source_frame_index := mini(
			int(one_shot_slot.source_frame_count) - 1,
			maxi(0, int(one_shot.elapsed_ticks))
		)
		var playback_time := float(source_frame_index) / float(one_shot_slot.gltf_fps)
		if not _seek_slot(one_shot_slot, playback_time):
			_remove_entry(stable_id, "animation_player_released", true)
			continue
		if int(one_shot.elapsed_ticks) >= int(one_shot.total_ticks):
			_finish_one_shot(stable_id, entry, true, "completed", "")


func _resolve_native_slot(root: Node3D, slot_descriptor: Dictionary) -> Dictionary:
	var animation_name_value: Variant = slot_descriptor.get("animation_name", null)
	if typeof(animation_name_value) not in [TYPE_STRING, TYPE_STRING_NAME]:
		return _error_result("invalid_animation_name", "Native glTF slot has no animation name.")
	var animation_name := StringName(String(animation_name_value))
	if String(animation_name).is_empty():
		return _error_result("invalid_animation_name", "Native glTF animation name is empty.")

	var player: AnimationPlayer = null
	var candidates := root.find_children("*", "AnimationPlayer", true, false)
	if candidates.size() == 1:
		player = candidates[0] as AnimationPlayer
	if player == null:
		return _error_result(
			"animation_player_not_found",
			"Native glTF slot does not resolve exactly one AnimationPlayer."
		)
	if not player.has_animation(animation_name):
		return _error_result(
			"animation_not_found",
			"AnimationPlayer does not contain animation %s." % animation_name
		)
	var animation := player.get_animation(animation_name)
	if animation == null or not is_finite(animation.length) or animation.length < 0.0:
		return _error_result("invalid_animation", "Native glTF animation has no finite duration.")
	var source_frame_count_value: Variant = slot_descriptor.get("source_frame_count", null)
	var source_frame_count_result := _parse_integral_number(source_frame_count_value)
	if (
		not bool(source_frame_count_result.get("ok", false))
		or int(source_frame_count_result.value) <= 0
	):
		return _error_result("invalid_source_frames", "Native glTF slot has no positive source_frame_count.")
	var source_frame_count := int(source_frame_count_result.value)
	var gltf_fps_value: Variant = slot_descriptor.get("gltf_fps", null)
	var gltf_fps_result := _parse_integral_number(gltf_fps_value)
	if not bool(gltf_fps_result.get("ok", false)) or int(gltf_fps_result.value) != 60:
		return _error_result("invalid_gltf_fps", "Native glTF slot must use the probed 60 Hz key timeline.")
	var gltf_fps := int(gltf_fps_result.value)
	var role_value: Variant = slot_descriptor.get("role", null)
	if typeof(role_value) not in [TYPE_STRING, TYPE_STRING_NAME] or String(role_value).is_empty():
		return _error_result("invalid_role", "Native glTF slot has no role.")
	var role := StringName(String(role_value))
	var duration_value: Variant = slot_descriptor.get("duration_seconds", null)
	if typeof(duration_value) not in [TYPE_FLOAT, TYPE_INT]:
		return _error_result("invalid_duration", "Native glTF slot has no numeric duration_seconds.")
	var duration_seconds := float(duration_value)
	var expected_duration := (
		float(source_frame_count) / SOURCE_FPS
		if role == &"loop"
		else float(source_frame_count - 1) / SOURCE_FPS
	)
	if (
		not is_finite(duration_seconds)
		or duration_seconds <= 0.0
		or absf(duration_seconds - expected_duration) > 0.000001
	):
		return _error_result("invalid_duration", "Native glTF slot wall-clock duration is inconsistent.")
	var last_gltf_key_time := float(source_frame_count - 1) / float(gltf_fps)
	if last_gltf_key_time > animation.length + 0.000001:
		return _error_result("invalid_animation", "Native glTF animation is shorter than its last source key.")
	return {
		"ok": true,
		"slot": {
			"player_ref": weakref(player),
			"animation_name": animation_name,
			"source_frame_count": source_frame_count,
			"gltf_fps": gltf_fps,
			"duration_seconds": duration_seconds,
			"role": role,
		},
	}


func _unsupported_slot_reason(slot_descriptor: Dictionary) -> String:
	var slot_support := StringName(String(slot_descriptor.get("runtime_support", NATIVE_GLTF_SUPPORT)))
	var source_format := String(slot_descriptor.get("source_format", "")).to_lower()
	var magic := String(slot_descriptor.get("magic", "")).to_upper()
	if source_format == "nsbta" or magic == "BTA0":
		return "unsupported_bta"
	if source_format == "nsbtp" or magic == "BTP0":
		return "unsupported_btp"
	if slot_support != NATIVE_GLTF_SUPPORT:
		return "runtime_support_%s" % String(slot_support)
	return ""


func _parse_integral_number(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_INT:
		return {"ok": true, "value": int(value)}
	if typeof(value) != TYPE_FLOAT:
		return {"ok": false}
	var numeric_value := float(value)
	if (
		not is_finite(numeric_value)
		or numeric_value != floor(numeric_value)
		or numeric_value < -2147483648.0
		or numeric_value > 2147483647.0
	):
		return {"ok": false}
	return {"ok": true, "value": int(numeric_value)}


func _prepare_player(player_ref: WeakRef, player_states: Array) -> void:
	var player := player_ref.get_ref() as AnimationPlayer
	if player == null or not is_instance_valid(player):
		return
	var instance_id := player.get_instance_id()
	for state_value in player_states:
		var state := state_value as Dictionary
		if int(state.instance_id) == instance_id:
			return
	player_states.append({
		"player_ref": weakref(player),
		"instance_id": instance_id,
		"callback_mode_process": int(player.callback_mode_process),
		"active": player.active,
	})
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	player.active = true


func _restore_players(player_states: Array) -> void:
	for state_value in player_states:
		var state := state_value as Dictionary
		var player := (state.player_ref as WeakRef).get_ref() as AnimationPlayer
		if player == null or not is_instance_valid(player):
			continue
		player.stop(true)
		player.callback_mode_process = int(state.callback_mode_process)
		player.active = bool(state.active)


func _seek_slot(slot: Dictionary, playback_time: float) -> bool:
	var player := (slot.player_ref as WeakRef).get_ref() as AnimationPlayer
	if player == null or not is_instance_valid(player):
		return false
	var animation_name := StringName(slot.animation_name)
	if not player.has_animation(animation_name):
		return false
	if player.assigned_animation != animation_name:
		player.play(animation_name)
		player.pause()
	player.seek(playback_time, true, true)
	return true


func _loop_seek_time(slot: Dictionary) -> float:
	var source_frame_count := int(slot.source_frame_count)
	if source_frame_count <= 0:
		return 0.0
	return float(_source_frame % source_frame_count) / float(slot.gltf_fps)


func _entry_root_is_alive(entry: Dictionary) -> bool:
	var root := (entry.root_ref as WeakRef).get_ref() as Node3D
	return root != null and is_instance_valid(root)


func _store_entry(stable_id: StringName, entry: Dictionary) -> void:
	_entries[stable_id] = entry
	_root_owners[int(entry.root_instance_id)] = stable_id


func _remove_entry(stable_id: StringName, reason: String, pruned: bool) -> void:
	if not _entries.has(stable_id):
		return
	var entry := _entries[stable_id] as Dictionary
	if not (entry.one_shot as Dictionary).is_empty():
		_finish_one_shot(stable_id, entry, false, "cancelled", reason)
	_restore_players(entry.player_states as Array)
	_root_owners.erase(int(entry.root_instance_id))
	_entries.erase(stable_id)
	if pruned:
		_pruned_entries += 1


func _finish_one_shot(
	stable_id: StringName,
	entry: Dictionary,
	ok: bool,
	status: String,
	reason: String
) -> void:
	var one_shot := entry.one_shot as Dictionary
	if one_shot.is_empty():
		return
	var result := {
		"ok": ok,
		"status": status,
		"reason": reason,
		"stable_id": stable_id,
		"slot": int(one_shot.slot),
		"token": int(one_shot.token),
	}
	var ticket := one_shot.ticket as PlaybackTicket
	entry.one_shot = {}
	if _entries.has(stable_id):
		_entries[stable_id] = entry
	ticket.finish(result)


func _prune_released_entries() -> void:
	for stable_id_value in _entries.keys():
		var stable_id := StringName(stable_id_value)
		if _entries.has(stable_id) and not _entry_root_is_alive(_entries[stable_id] as Dictionary):
			_remove_entry(stable_id, "root_released", true)


func _unsupported_result(stable_id: StringName, slot: int, reason: String) -> Dictionary:
	return {
		"ok": false,
		"status": "unsupported",
		"reason": reason,
		"stable_id": stable_id,
		"slot": slot,
	}


func _error_result(reason: String, message: String) -> Dictionary:
	return {
		"ok": false,
		"status": "error",
		"reason": reason,
		"error": message,
	}
