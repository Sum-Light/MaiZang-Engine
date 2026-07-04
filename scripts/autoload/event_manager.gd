extends Node

signal debug_message_requested(lines: PackedStringArray)
signal transition_sequence_requested(sequence: Dictionary)
signal battle_start_sequence_requested(sequence: Dictionary)

const WARP_ID_NONE_VALUE := -1
const LOCALID_NONE_VALUE := 0
const LOCALID_CAMERA_VALUE := 127
const LOCALID_FOLLOWING_POKEMON_VALUE := 254
const LOCALID_PLAYER_VALUE := 255
const MAP_SCRIPT_ON_LOAD := "MAP_SCRIPT_ON_LOAD"
const MAP_SCRIPT_ON_TRANSITION := "MAP_SCRIPT_ON_TRANSITION"
const MAP_SCRIPT_ON_FRAME_TABLE := "MAP_SCRIPT_ON_FRAME_TABLE"
const DOOR_ANIM_FRAME_TIME := 4
const DOOR_ANIM_FRAME_COUNT := 4
const DOOR_ANIM_TOTAL_FRAMES := DOOR_ANIM_FRAME_TIME * DOOR_ANIM_FRAME_COUNT
const WALK_NORMAL_TILE_FRAMES := 16
const FADE_DELAY_DEFAULT := 0
const MAP_SCRIPT_SOURCE_TRACE := [
	"src/script.c:MapHeaderGetScriptTable/MapHeaderRunScriptType",
	"include/constants/map_scripts.h",
]
const WARP_EXIT_DOOR_BEHAVIORS := {
	"MB_PETALBURG_GYM_DOOR": true,
	"MB_ANIMATED_DOOR": true,
}
const WARP_EXIT_DIRECTIONAL_STAIR_BEHAVIORS := {
	"MB_UP_RIGHT_STAIR_WARP": true,
	"MB_UP_LEFT_STAIR_WARP": true,
	"MB_DOWN_RIGHT_STAIR_WARP": true,
	"MB_DOWN_LEFT_STAIR_WARP": true,
}
const WARP_EXIT_NON_ANIM_DOOR_BEHAVIORS := {
	"MB_NON_ANIMATED_DOOR": true,
	"MB_WATER_DOOR": true,
	"MB_DEEP_SOUTH_WARP": true,
}
const STANDARD_WILD_ENCOUNTER_SOURCE_TRACE := [
	"src/field_control_avatar.c:FieldGetPlayerInput",
	"src/field_control_avatar.c:ProcessPlayerFieldInput",
	"src/field_control_avatar.c:TryStartStepBasedScript",
	"src/field_control_avatar.c:CheckStandardWildEncounter",
	"src/wild_encounter.c:StandardWildEncounter",
	"src/metatile_behavior.c:MetatileBehavior_IsLandWildEncounter",
	"src/metatile_behavior.c:MetatileBehavior_IsWaterWildEncounter",
]
const PLAYER_STEP_SOURCE_TRACE := [
	"src/field_control_avatar.c:ProcessPlayerFieldInput",
	"src/field_control_avatar.c:TryStartStepBasedScript",
	"src/field_control_avatar.c:TryStartMiscWalkingScripts",
	"src/field_control_avatar.c:TryStartStepCountScript",
	"src/wild_encounter.c:UpdateRepelCounter",
	"src/dexnav.c:OnStep_DexNavSearch",
	"src/field_control_avatar.c:CheckStandardWildEncounter",
]
const PLAYER_STEP_SOURCE_ORDER := [
	"IncrementGameStat(GAME_STAT_STEPS)",
	"IncrementBirthIslandRockStepCount",
	"TryStartCoordEventScript",
	"TryStartWarpEventScript",
	"TryStartMiscWalkingScripts",
	"TryStartStepCountScript",
	"UpdateRepelCounter",
	"OnStep_DexNavSearch",
	"CheckStandardWildEncounter",
]
const WILD_ENCOUNTER_IMMUNITY_STEPS := 4
const BATTLE_TRANSITION_STUB_FRAMES := 24
const REPEL_LURE_MASK := 1 << 15
const NO_ENCOUNTER_FLAGS := {
	"OW_FLAG_NO_ENCOUNTER": true,
	"FLAG_NO_ENCOUNTER": true,
}
const MISC_WALKING_SCRIPT_BEHAVIORS := {
	"MB_CRACKED_FLOOR_HOLE": {
		"script": "EventScript_FallDownHole",
		"source": "src/field_control_avatar.c:TryStartMiscWalkingScripts",
	},
	"MB_BATTLE_PYRAMID_WARP": {
		"script": "BattlePyramid_WarpToNextFloor",
		"source": "src/field_control_avatar.c:TryStartMiscWalkingScripts",
	},
}
const MISC_WALKING_CONTINUE_BEHAVIORS := {
	"MB_SECRET_BASE_GLITTER_MAT": "DoSecretBaseGlitterMatSparkle",
	"MB_SECRET_BASE_SOUND_MAT": "PlaySecretBaseMusicNoteMatSound",
}
const STEP_COUNT_SOURCE_ORDER := [
	"IncrementRematchStepCounter",
	"UpdateFriendshipStepCounter",
	"UpdateFarawayIslandStepCounter",
	"UpdateFollowerStepCounter",
	"UpdatePoisonStepCounter",
	"ShouldEggHatch",
	"AbnormalWeatherHasExpired",
	"ShouldDoBrailleRegicePuzzle",
	"ShouldDoWallyCall",
	"ShouldDoScottFortreeCall",
	"ShouldDoScottBattleFrontierCall",
	"ShouldDoRoxanneCall",
	"ShouldDoRivalRayquazaCall",
	"UpdateVsSeekerStepCounter",
	"SafariZoneTakeStep",
	"CountSSTidalStep",
	"TryStartMatchCall",
]

var _script_data: Dictionary = {}
var _script_vm: Node = null
var _map_runtime: Node = null
var _game_state: Node = null
var _data_registry: Node = null
var _encounter_engine: Node = null
var _battle_engine: Node = null
var _party_runtime: Node = null
var _defer_transition_apply := false
var _next_transition_sequence_id := 1
var _pending_transitions := {}
var _wild_encounter_immunity_steps := 0
var _previous_wild_metatile_behavior := ""


func _ready() -> void:
	_script_vm = get_node_or_null("/root/ScriptVM")
	_map_runtime = get_node_or_null("/root/MapRuntime")
	_game_state = get_node_or_null("/root/GameState")
	_data_registry = get_node_or_null("/root/DataRegistry")
	_encounter_engine = get_node_or_null("/root/EncounterEngine")
	_battle_engine = get_node_or_null("/root/BattleEngine")
	_party_runtime = get_node_or_null("/root/PartyRuntime")
	if _data_registry != null and _data_registry.has_method("get_start_script_data"):
		configure_from_script_data(_data_registry.get_start_script_data())
	_configure_script_vm_dependencies()
	_configure_encounter_engine_dependencies()
	_configure_battle_engine_dependencies()


func configure_from_script_data(script_data: Dictionary) -> void:
	_script_data = script_data
	if _script_vm != null and _script_vm.has_method("configure_from_script_data"):
		_script_vm.configure_from_script_data(script_data)


func configure_script_vm(script_vm: Node) -> void:
	_script_vm = script_vm
	if _script_vm != null and _script_vm.has_method("configure_from_script_data"):
		_script_vm.configure_from_script_data(_script_data)
	_configure_script_vm_dependencies()


func configure_map_runtime(map_runtime: Node) -> void:
	_map_runtime = map_runtime


func configure_game_state(game_state: Node) -> void:
	_game_state = game_state
	_configure_script_vm_dependencies()
	_configure_encounter_engine_dependencies()


func configure_data_registry(data_registry: Node) -> void:
	_data_registry = data_registry
	_configure_script_vm_dependencies()
	_configure_encounter_engine_dependencies()
	_configure_battle_engine_dependencies()


func configure_encounter_engine(encounter_engine: Node) -> void:
	_encounter_engine = encounter_engine
	_configure_encounter_engine_dependencies()


func configure_battle_engine(battle_engine: Node) -> void:
	_battle_engine = battle_engine
	_configure_battle_engine_dependencies()


func configure_party_runtime(party_runtime: Node) -> void:
	_party_runtime = party_runtime


func configure_transition_deferred(value: bool) -> void:
	_defer_transition_apply = value
	if not _defer_transition_apply:
		_pending_transitions.clear()


func has_pending_transition(sequence_id: int) -> bool:
	return _pending_transitions.has(sequence_id)


func apply_deferred_transition(sequence_id: int) -> Dictionary:
	var pending = _pending_transitions.get(sequence_id, {})
	if typeof(pending) != TYPE_DICTIONARY or pending.is_empty():
		return {
			"status": "missing_pending_transition",
			"id": sequence_id,
			"position_applied": false,
		}

	_pending_transitions.erase(sequence_id)
	return _apply_transition_payload(pending)


func reset_wild_encounter_immunity_steps() -> void:
	_wild_encounter_immunity_steps = 0


func get_wild_encounter_dispatch_state() -> Dictionary:
	return {
		"immunity_steps": _wild_encounter_immunity_steps,
		"previous_metatile_behavior": _previous_wild_metatile_behavior,
		"source": "src/field_control_avatar.c:sWildEncounterImmunitySteps/sPrevMetatileBehavior",
	}


func dispatch_interaction(interaction: Dictionary) -> void:
	if interaction.is_empty():
		debug_message_requested.emit(PackedStringArray(["Nothing to interact with."]))
		return

	var event = interaction.get("event", {})
	if typeof(event) != TYPE_DICTIONARY:
		debug_message_requested.emit(PackedStringArray(["Unsupported interaction target."]))
		return

	var event_data: Dictionary = event
	var interaction_type := String(interaction.get("type", ""))
	match interaction_type:
		"object_event":
			_emit_object_event(interaction, event_data)
		"bg_event":
			_emit_bg_event(interaction, event_data)
		"warp_event":
			_emit_warp_event(interaction, event_data)
		"map_connection":
			_emit_map_connection(interaction, event_data)
		"coord_event":
			_emit_coord_event(interaction, event_data)
		_:
			debug_message_requested.emit(PackedStringArray([
				"Interaction: %s" % interaction_type,
				"Source event type is not handled yet.",
			]))


func try_dispatch_standard_wild_encounter(cell: Vector2i, options: Dictionary = {}) -> Dictionary:
	var summary := _check_standard_wild_encounter(cell, options)
	if bool(summary.get("encounter_requested", false)):
		_emit_standard_wild_encounter(summary)
	return summary


func request_map_connection_transition(request: Dictionary) -> Dictionary:
	var destination_position = request.get("dest_position", Vector2i(-1, -1))
	if typeof(destination_position) != TYPE_VECTOR2I:
		destination_position = _transition_vector(request, "dest_position", Vector2i(-1, -1))
	var source_position = request.get("source_position", _current_player_position())
	if typeof(source_position) != TYPE_VECTOR2I:
		source_position = _transition_vector(request, "source_position", _current_player_position())
	var trigger_position = request.get("trigger_position", source_position)
	if typeof(trigger_position) != TYPE_VECTOR2I:
		trigger_position = _transition_vector(request, "trigger_position", source_position)

	return _apply_transition_effects([
		{
			"op": "map_connection",
			"line": 0,
			"map": String(request.get("dest_map", request.get("map", ""))),
			"position": destination_position,
			"has_explicit_position": true,
			"uses_warp_id": false,
			"style": "connection",
			"presentation": "connection",
			"source_position": [source_position.x, source_position.y],
			"trigger_position": [trigger_position.x, trigger_position.y],
			"source": "src/fieldmap.c:MapConnection",
		},
	])


func request_trainer_battle_start(request: Dictionary) -> Dictionary:
	if _battle_engine == null or not _battle_engine.has_method("create_trainer_battle_state"):
		return {
			"status": "missing_battle_engine",
			"source": "src/battle_setup.c:BattleSetup_StartTrainerBattle",
		}

	var trainer_id := String(request.get("trainer_id", request.get("trainer", "")))
	if trainer_id.is_empty():
		return {
			"status": "missing_trainer_id",
			"detail": "Trainer battle requests must provide the source trainer id or symbol; the bridge does not guess a default trainer.",
			"source": "src/scrcmd.c:ScrCmd_trainerbattle",
			"unsupported": [{
				"code": "trainer_battle_request_missing_trainer_id",
				"source": "src/scrcmd.c:ScrCmd_trainerbattle -> TrainerBattleLoadArgs",
				"detail": "Source trainerbattle reads the trainer id from script args. Godot debug requests must pass trainer_id explicitly.",
			}],
		}
	var player_party_result := _player_party_for_trainer_battle(request)
	var player_party_status := String(player_party_result.get("status", ""))
	if player_party_status == "error" or player_party_status == "unsupported_empty_player_party":
		return player_party_result
	var player_party = player_party_result.get("battle_party", [])
	if typeof(player_party) != TYPE_ARRAY:
		player_party = []

	var map_id := String(request.get("map", _current_map_id()))
	var position = request.get("position", _current_player_position())
	if typeof(position) != TYPE_VECTOR2I:
		position = _transition_vector(request, "position", _current_player_position())
	var battle_options := {
		"battle_origin": String(request.get("battle_origin", "debug_trainer_npc")),
		"map": map_id,
		"map_type": _current_map_type(map_id),
		"metatile_behavior": String(request.get("metatile_behavior", _current_metatile_behavior_name(position))),
		"player_active": _current_player_active_battle_index(player_party),
		"debug_player_party": player_party_result,
	}
	var battle_state = _battle_engine.create_trainer_battle_state(trainer_id, player_party, battle_options)
	if typeof(battle_state) != TYPE_DICTIONARY:
		return {
			"status": "invalid_battle_state",
			"source": "src/battle_setup.c:BattleSetup_StartTrainerBattle",
		}
	var battle_status := String(battle_state.get("status", ""))
	if battle_status != "ok":
		return {
			"status": battle_status,
			"battle_state": battle_state,
			"source": "src/battle_setup.c:BattleSetup_StartTrainerBattle",
		}
	battle_state["debug_fixture"] = bool(request.get("debug_fixture", false))
	battle_state["debug_player_party"] = player_party_result.duplicate(true)
	var battle_unsupported = battle_state.get("unsupported", [])
	if typeof(battle_unsupported) != TYPE_ARRAY:
		battle_unsupported = []
	battle_unsupported.append_array(_array_value(player_party_result.get("unsupported", [])))
	battle_state["unsupported"] = battle_unsupported
	if String(battle_state.get("battle_type", "")) != "single":
		return {
			"status": "unsupported_trainer_battle_type",
			"battle_state": battle_state,
			"source": "src/battle_setup.c:GetTrainerBattleType",
			"unsupported": [{
				"code": "trainer_double_battle_not_supported",
				"source": "src/battle_setup.c:GetTrainerBattleTransition",
				"detail": "The debug BattleScene is single-battle only. Double, multi, and partner trainer battles are recorded as metadata but are not handed off to the scene yet.",
			}],
		}

	var sequence_id := _next_transition_sequence_id
	_next_transition_sequence_id += 1
	var battle_setup := {
		"status": "state_created",
		"battle_state": battle_state,
		"trainer_id": trainer_id,
		"player_party_count": player_party.size(),
		"opponent_party_count": _result_array_count(battle_state, "opponent_party"),
		"debug_player_party": player_party_result,
		"source": "src/battle_setup.c:BattleSetup_StartTrainerBattle",
	}
	var statistics := _increment_trainer_battle_stats()
	var sequence := _build_trainer_battle_start_sequence(
		sequence_id,
		request,
		battle_setup,
		battle_state,
		statistics
	)
	battle_start_sequence_requested.emit(sequence)
	return {
		"status": "sequence_requested",
		"id": sequence_id,
		"sequence": sequence,
		"battle_setup": battle_setup,
		"statistics": statistics,
		"source": "src/battle_setup.c:DoTrainerBattle -> CreateBattleStartTask",
	}


func dispatch_player_step(cell: Vector2i, options: Dictionary = {}) -> Dictionary:
	var behavior_name := _current_metatile_behavior_name(cell)
	var forced_move := bool(options.get("forced_move", false))
	var forced_movement_tile := _is_forced_movement_behavior(behavior_name)
	var summary := {
		"status": "no_step_event",
		"consumed": false,
		"consumed_by": "",
		"reason": "",
		"map": _current_map_id(),
		"position": cell,
		"current_metatile_behavior": behavior_name,
		"forced_move": forced_move,
		"forced_movement_tile": forced_movement_tile,
		"source_order": PLAYER_STEP_SOURCE_ORDER.duplicate(),
		"source_trace": PLAYER_STEP_SOURCE_TRACE.duplicate(),
		"game_stat_steps": _increment_game_stat("GAME_STAT_STEPS"),
		"birth_island_rock": {
			"status": "future",
			"source": "src/field_control_avatar.c:IncrementBirthIslandRockStepCount",
		},
		"coord_event": {},
		"warp_event": {},
		"misc_walking": {},
		"step_count": {},
		"repel": {},
		"dexnav": {},
		"wild_encounter": {},
	}

	var coord_event := _step_coord_event_target(cell)
	summary["coord_event"] = _interaction_step_summary(coord_event)
	if not coord_event.is_empty():
		dispatch_interaction(coord_event)
		return _finish_player_step(summary, "coord_event", "coord_event")

	var warp_event := _step_warp_event_target(cell)
	summary["warp_event"] = _interaction_step_summary(warp_event)
	if not warp_event.is_empty():
		dispatch_interaction(warp_event)
		return _finish_player_step(summary, "warp_event", "warp_event")

	var misc_summary := _evaluate_misc_walking_scripts(cell, behavior_name)
	summary["misc_walking"] = misc_summary
	if bool(misc_summary.get("consumes_step", false)):
		_emit_pending_player_step_script("Misc walking script", misc_summary)
		return _finish_player_step(summary, "misc_walking", String(misc_summary.get("reason", "misc_walking_script")))

	var step_count_summary := _evaluate_step_count_scripts(behavior_name, forced_move, forced_movement_tile, options)
	summary["step_count"] = step_count_summary
	if bool(step_count_summary.get("consumes_step", false)):
		_emit_pending_player_step_script("Step-count script", step_count_summary)
		return _finish_player_step(summary, "step_count", String(step_count_summary.get("reason", "step_count_script")))

	if not forced_move and not forced_movement_tile:
		var repel_summary := _update_repel_counter()
		summary["repel"] = repel_summary
		if bool(repel_summary.get("consumes_step", false)):
			_emit_pending_player_step_script("Repel/Lure wore off", repel_summary)
			return _finish_player_step(summary, "repel", String(repel_summary.get("reason", "repel_counter")))
	else:
		summary["repel"] = {
			"status": "skipped_forced_movement",
			"source": "src/field_control_avatar.c:TryStartStepBasedScript",
		}

	var dexnav_summary := _evaluate_dexnav_step()
	summary["dexnav"] = dexnav_summary
	if bool(dexnav_summary.get("consumes_step", false)):
		_emit_pending_player_step_script("DexNav step search", dexnav_summary)
		return _finish_player_step(summary, "dexnav", String(dexnav_summary.get("reason", "dexnav_step")))

	var wild_summary := try_dispatch_standard_wild_encounter(cell, options)
	summary["wild_encounter"] = wild_summary
	if bool(wild_summary.get("encounter_requested", false)):
		return _finish_player_step(summary, "standard_wild_encounter", "standard_wild_encounter")

	summary["reason"] = String(wild_summary.get("reason", "no_step_event"))
	return summary


func _emit_object_event(interaction: Dictionary, event_data: Dictionary) -> void:
	var debug_action := _object_event_debug_action(event_data)
	if debug_action == "trainer_battle":
		_emit_trainer_battle_object_event(interaction, event_data)
		return

	var script := String(interaction.get("script", event_data.get("script", "0x0")))
	var lines := PackedStringArray([
		"Object event",
		"Position: %s" % interaction.get("position", Vector2i.ZERO),
		"Graphics: %s" % String(event_data.get("graphics_id", "unknown")),
	])
	_append_script_output(lines, script, {
		"interaction_type": "object_event",
		"event": event_data,
	})
	debug_message_requested.emit(lines)


func _emit_trainer_battle_object_event(interaction: Dictionary, event_data: Dictionary) -> void:
	var metadata = event_data.get("metadata", {})
	metadata = metadata if typeof(metadata) == TYPE_DICTIONARY else {}
	var position = interaction.get("position", _current_player_position())
	if typeof(position) != TYPE_VECTOR2I:
		position = _current_player_position()
	var trainer_id := String(metadata.get("trainer_id", event_data.get("trainer_id", "")))
	var battle_request := {
		"battle_origin": "debug_trainer_npc",
		"trainer_id": trainer_id,
		"debug_fixture": true,
		"debug_allow_empty_party_fallback": true,
		"map": _current_map_id(),
		"position": position,
		"object_event": event_data,
		"source": "Godot-only debug fixture overlay",
	}
	var result := request_trainer_battle_start(battle_request)
	var lines := PackedStringArray([
		"Debug trainer battle",
		"Trainer: %s" % trainer_id,
		"Position: %s" % position,
		"Request: %s" % String(result.get("status", "")),
	])
	var sequence = result.get("sequence", {})
	if typeof(sequence) == TYPE_DICTIONARY and not sequence.is_empty():
		var transition = sequence.get("battle_transition", {})
		if typeof(transition) == TYPE_DICTIONARY:
			lines.append("Transition: %s" % String(transition.get("selected", "")))
	if result.has("detail"):
		lines.append(String(result.get("detail", "")))
	debug_message_requested.emit(lines)


func _object_event_debug_action(event_data: Dictionary) -> String:
	var metadata = event_data.get("metadata", {})
	if typeof(metadata) == TYPE_DICTIONARY:
		var action := String(metadata.get("action", ""))
		if not action.is_empty():
			return action
	return String(event_data.get("action", ""))


func _emit_bg_event(interaction: Dictionary, event_data: Dictionary) -> void:
	var script := String(interaction.get("script", event_data.get("script", "0x0")))
	var lines := PackedStringArray([
		"BG event: %s" % String(event_data.get("type", "unknown")),
		"Position: %s" % interaction.get("position", Vector2i.ZERO),
	])
	_append_script_output(lines, script, {
		"interaction_type": "bg_event",
		"event": event_data,
	})
	debug_message_requested.emit(lines)


func _emit_coord_event(interaction: Dictionary, event_data: Dictionary) -> void:
	var script := String(interaction.get("script", event_data.get("script", "0x0")))
	var lines := PackedStringArray([
		"Coord event",
		"Position: %s" % interaction.get("position", Vector2i.ZERO),
		"Trigger: %s == %s" % [
			str(event_data.get("var", event_data.get("trigger", ""))),
			str(event_data.get("var_value", event_data.get("index", ""))),
		],
	])
	_append_script_output(lines, script, {
		"interaction_type": "coord_event",
		"event": event_data,
	})
	debug_message_requested.emit(lines)


func _emit_warp_event(interaction: Dictionary, event_data: Dictionary) -> void:
	var lines := PackedStringArray([
		"Warp event",
		"Position: %s" % interaction.get("position", Vector2i.ZERO),
		"Destination: %s / warp %s" % [
			str(event_data.get("dest_map", "unknown")),
			str(event_data.get("dest_warp_id", "?")),
		],
	])
	var transition_summary := _apply_map_warp_event(interaction, event_data)
	lines.append("Warp effects: %d applied, %d skipped" % [
		_movement_summary_count(transition_summary, "applied"),
		_movement_summary_count(transition_summary, "skipped"),
	])
	debug_message_requested.emit(lines)


func _emit_map_connection(interaction: Dictionary, event_data: Dictionary) -> void:
	var lines := PackedStringArray([
		"Map connection",
		"Position: %s" % interaction.get("position", Vector2i.ZERO),
		"Destination: %s @ %s" % [
			str(event_data.get("dest_map", event_data.get("map", "unknown"))),
			str(event_data.get("dest_position", Vector2i(-1, -1))),
		],
	])
	var transition_summary := request_map_connection_transition(event_data)
	lines.append("Connection effects: %d applied, %d skipped" % [
		_movement_summary_count(transition_summary, "applied"),
		_movement_summary_count(transition_summary, "skipped"),
	])
	debug_message_requested.emit(lines)


func _check_standard_wild_encounter(cell: Vector2i, options: Dictionary = {}) -> Dictionary:
	var behavior_name := _current_metatile_behavior_name(cell)
	var previous_behavior := _previous_wild_metatile_behavior
	var summary := {
		"status": "no_encounter",
		"encounter_requested": false,
		"reason": "",
		"map": _current_map_id(),
		"position": cell,
		"current_metatile_behavior": behavior_name,
		"previous_metatile_behavior": previous_behavior,
		"immunity_steps_before": _wild_encounter_immunity_steps,
		"immunity_required_steps": WILD_ENCOUNTER_IMMUNITY_STEPS,
		"source_order": [
			"ProcessPlayerFieldInput",
			"TryStartStepBasedScript: coord -> warp -> misc -> step-count -> repel -> DexNav",
			"CheckStandardWildEncounter",
			"StandardWildEncounter",
		],
		"unsupported": _standard_wild_dispatch_unsupported(),
		"source_trace": STANDARD_WILD_ENCOUNTER_SOURCE_TRACE.duplicate(),
	}

	var disabled_flag := _wild_encounters_disabled_flag()
	if not disabled_flag.is_empty():
		summary["reason"] = "no_encounter_flag"
		summary["disabled_flag"] = disabled_flag
		summary["immunity_steps_after"] = _wild_encounter_immunity_steps
		return summary

	if _wild_encounter_immunity_steps < WILD_ENCOUNTER_IMMUNITY_STEPS:
		_wild_encounter_immunity_steps += 1
		_previous_wild_metatile_behavior = behavior_name
		summary["reason"] = "immunity_steps"
		summary["immunity_steps_after"] = _wild_encounter_immunity_steps
		return summary

	if _encounter_engine == null or not _encounter_engine.has_method("try_standard_encounter_for_behavior"):
		summary["status"] = "missing_encounter_engine"
		summary["reason"] = "missing_encounter_engine"
		summary["immunity_steps_after"] = _wild_encounter_immunity_steps
		return summary

	var encounter_options := options.duplicate(true)
	if _game_state != null and not encounter_options.has("game_state"):
		encounter_options["game_state"] = _game_state
	var result = _encounter_engine.try_standard_encounter_for_behavior(
		String(summary.get("map", "")),
		behavior_name,
		previous_behavior,
		encounter_options
	)
	if typeof(result) != TYPE_DICTIONARY:
		result = {
			"status": "error",
			"error": "invalid_encounter_result",
		}

	summary["encounter_result"] = result
	summary["metatile_routing"] = result.get("metatile_routing", {})
	_previous_wild_metatile_behavior = behavior_name
	if String(result.get("status", "")) != "ok":
		summary["reason"] = _encounter_result_reason(result)
		summary["immunity_steps_after"] = _wild_encounter_immunity_steps
		return summary

	_wild_encounter_immunity_steps = 0
	summary["status"] = "encounter_requested"
	summary["encounter_requested"] = true
	summary["reason"] = "standard_wild_encounter"
	summary["species"] = String(result.get("species", ""))
	summary["species_id"] = int(result.get("species_id", 0))
	summary["level"] = int(result.get("level", 0))
	summary["area"] = String(result.get("area", ""))
	summary["record_label"] = String(result.get("record_label", ""))
	var battle_setup := _create_standard_wild_battle_state(summary)
	summary["battle_setup"] = battle_setup
	if String(battle_setup.get("status", "")) == "state_created":
		summary["battle_start_sequence"] = _request_standard_wild_battle_start(summary, battle_setup)
	summary["immunity_steps_after"] = _wild_encounter_immunity_steps
	return summary


func _emit_standard_wild_encounter(summary: Dictionary) -> void:
	var result = summary.get("encounter_result", {})
	var encounter_check := {}
	if typeof(result) == TYPE_DICTIONARY:
		var check = result.get("encounter_check", {})
		encounter_check = check if typeof(check) == TYPE_DICTIONARY else {}
	var lines := PackedStringArray([
		"Wild encounter",
		"Position: %s" % summary.get("position", Vector2i.ZERO),
		"Metatile: %s" % String(summary.get("current_metatile_behavior", "")),
		"Area: %s" % String(summary.get("area", "")),
		"Species: %s Lv.%d" % [
			String(summary.get("species", "")),
			int(summary.get("level", 0)),
		],
	])
	if not encounter_check.is_empty():
		lines.append("Encounter check: %d < %d / %d" % [
			int(encounter_check.get("roll", 0)),
			int(encounter_check.get("adjusted_rate", 0)),
			int(encounter_check.get("max_rate", 0)),
		])
	var battle_setup = summary.get("battle_setup", {})
	if typeof(battle_setup) == TYPE_DICTIONARY and not battle_setup.is_empty():
		lines.append("Battle setup: %s" % String(battle_setup.get("status", "")))
		var battle_state = battle_setup.get("battle_state", {})
		if typeof(battle_state) == TYPE_DICTIONARY:
			lines.append("Battle kind: %s" % String(battle_state.get("battle_kind", "")))
			var opponent_party = battle_state.get("opponent_party", [])
			if typeof(opponent_party) == TYPE_ARRAY and not opponent_party.is_empty():
				var opponent = opponent_party[0]
				if typeof(opponent) == TYPE_DICTIONARY:
					lines.append("Enemy party[0]: %s Lv.%d" % [
						String(opponent.get("species", "")),
						int(opponent.get("level", 0)),
					])
		var battle_start = summary.get("battle_start_sequence", {})
		if typeof(battle_start) == TYPE_DICTIONARY and not battle_start.is_empty():
			lines.append("Battle start: %s" % String(battle_start.get("status", "")))
	else:
		lines.append("Battle setup: missing")
	debug_message_requested.emit(lines)


func get_script_preview(script: String) -> Dictionary:
	if script.is_empty() or script == "0x0":
		return {}

	var result := run_script(script)
	var messages = result.get("messages", [])
	if typeof(messages) == TYPE_ARRAY and not messages.is_empty():
		var message = messages[0]
		if typeof(message) == TYPE_DICTIONARY:
			return {
				"script_label": script,
				"text_label": String(message.get("text_label", "")),
				"mode": String(message.get("mode", "")),
				"op": String(message.get("op", "msgbox")),
				"line": int(message.get("line", 0)),
				"text": String(message.get("text", "")),
				"status": String(message.get("status", "ok")),
				"text_source": String(message.get("text_source", "")),
				"text_kind": String(message.get("text_kind", "text")),
				"encoding_status": String(message.get("encoding_status", "")),
				"source_byte_count": int(message.get("source_byte_count", 0)),
				"terminator_present": bool(message.get("terminator_present", false)),
				"vm_status": String(result.get("status", "")),
			}

	if not result.is_empty() and String(result.get("status", "")) != "vm_unavailable":
		return {
			"script_label": script,
			"status": "no_preview_message",
			"vm_status": String(result.get("status", "")),
		}

	return _get_direct_script_preview(script)


func run_script(script: String, context: Dictionary = {}) -> Dictionary:
	if _script_vm != null and _script_vm.has_method("run_script"):
		return _script_vm.run_script(script, context)
	return {
		"script_label": script,
		"status": "vm_unavailable",
		"finished": true,
		"messages": [],
		"movements": [],
		"object_effects": [],
		"field_effects": [],
		"ui_effects": [],
		"special_effects": [],
		"audio_effects": [],
		"transition_effects": [],
		"player_effects": [],
		"effects": [],
		"unsupported_ops": [],
		"trace": [],
		"string_vars": {
			"STR_VAR_1": "",
			"STR_VAR_2": "",
			"STR_VAR_3": "",
		},
		"wait_buttonpress": false,
		"wait_movement": false,
		"wait_ui": false,
		"wait_state": false,
		"wait_audio": false,
		"step_count": 0,
	}


func run_map_script_type(script_type: String, context: Dictionary = {}) -> Dictionary:
	if script_type == MAP_SCRIPT_ON_FRAME_TABLE:
		return try_run_on_frame_map_script(context)

	var labels := _map_script_labels_for_type(script_type)
	var summary := {
		"script_type": script_type,
		"status": "missing_map_script" if labels.is_empty() else "ok",
		"scripts": [],
		"runtime_summaries": [],
		"source_trace": _map_script_source_trace(script_type),
	}
	for label in labels:
		var script_context := context.duplicate(true)
		script_context["map_script_type"] = script_type
		script_context["source_function"] = _map_script_source_function(script_type)
		var result := run_script(label, script_context)
		var runtime_summary := {}
		if not result.is_empty() and String(result.get("status", "")) != "vm_unavailable":
			runtime_summary = _apply_runtime_result(result)
		summary["runtime_summaries"].append(runtime_summary)
		summary["scripts"].append({
			"label": label,
			"status": String(result.get("status", "")),
			"field_effect_count": _result_array_count(result, "field_effects"),
			"movement_count": _result_array_count(result, "movements"),
			"object_effect_count": _result_array_count(result, "object_effects"),
			"transition_effect_count": _result_array_count(result, "transition_effects"),
			"template_object_targets": _template_position_targets_from_runtime_summary(runtime_summary),
			"runtime": runtime_summary,
		})
		if String(result.get("status", "")) != "ok":
			summary["status"] = String(result.get("status", "script_error"))
	return summary


func dispatch_on_frame_map_script(context: Dictionary = {}) -> Dictionary:
	var summary := try_run_on_frame_map_script(context)
	if not bool(summary.get("matched", false)):
		return summary

	var lines := PackedStringArray([
		"OnFrame map script",
		"Table: %s" % String(summary.get("table_label", "")),
		"Script: %s" % String(summary.get("selected_script", "")),
	])
	var result = summary.get("result", {})
	if typeof(result) == TYPE_DICTIONARY and not result.is_empty():
		lines.append("ScriptVM: %s" % String(result.get("status", "")))
	else:
		lines.append("ScriptVM: unavailable")

	var runtime_summary = summary.get("runtime", {})
	if typeof(runtime_summary) == TYPE_DICTIONARY:
		_append_runtime_summary_lines(lines, runtime_summary)
	if typeof(result) == TYPE_DICTIONARY:
		_append_result_content_lines(lines, result)

	debug_message_requested.emit(lines)
	return summary


func try_run_on_frame_map_script(context: Dictionary = {}) -> Dictionary:
	var labels := _map_script_labels_for_type(MAP_SCRIPT_ON_FRAME_TABLE)
	var entries := []
	var summary := {
		"script_type": MAP_SCRIPT_ON_FRAME_TABLE,
		"status": "missing_map_script" if labels.is_empty() else "no_matching_map_script",
		"matched": false,
		"table_label": "",
		"selected_script": "",
		"entry_count": 0,
		"terminal_found": false,
		"entries": entries,
		"script": {},
		"runtime": {},
		"result": {},
		"source_trace": _map_script_source_trace(MAP_SCRIPT_ON_FRAME_TABLE),
	}
	if labels.is_empty():
		return summary

	var table_label := String(labels[0])
	summary["table_label"] = table_label
	var table_record := _get_script_record(table_label)
	if table_record.is_empty():
		summary["status"] = "missing_table_script"
		return summary
	if String(table_record.get("kind", "")) != "map_script_table":
		summary["status"] = "invalid_map_script_table"
		return summary

	var instructions = table_record.get("instructions", [])
	if typeof(instructions) != TYPE_ARRAY:
		summary["status"] = "invalid_map_script_table"
		return summary

	for instruction in instructions:
		if typeof(instruction) != TYPE_DICTIONARY:
			continue

		var op := String(instruction.get("op", ""))
		var args = instruction.get("args", [])
		if op == ".2byte":
			if typeof(args) == TYPE_ARRAY and args.size() >= 1 and _map_script_table_value(String(args[0])).get("value", 0) == 0:
				summary["terminal_found"] = true
				break
			continue
		if op != "map_script_2":
			continue
		if typeof(args) != TYPE_ARRAY or args.size() < 3:
			entries.append({
				"status": "invalid_map_script_2",
				"line": int(instruction.get("line", 0)),
				"raw": String(instruction.get("raw", "")),
			})
			summary["entry_count"] = entries.size()
			continue

		var var_token := String(args[0])
		var compare_token := String(args[1])
		var target_label := String(args[2])
		var var_value := _map_script_table_value(var_token)
		var compare_value := _map_script_table_value(compare_token)
		var condition_matched := int(var_value.get("value", 0)) == int(compare_value.get("value", 0))
		var entry := {
			"var_token": var_token,
			"compare_token": compare_token,
			"var_value": int(var_value.get("value", 0)),
			"compare_value": int(compare_value.get("value", 0)),
			"var_source": String(var_value.get("source", "")),
			"compare_source": String(compare_value.get("source", "")),
			"script_label": target_label,
			"line": int(instruction.get("line", 0)),
			"condition_matched": condition_matched,
			"matched": false,
		}
		entries.append(entry)
		summary["entry_count"] = entries.size()
		if not condition_matched:
			continue
		if _script_label_has_no_effect(target_label):
			entry["no_effect"] = true
			continue

		entry["matched"] = true
		summary["matched"] = true
		summary["selected_script"] = target_label
		var script_context := context.duplicate(true)
		script_context["map_script_type"] = MAP_SCRIPT_ON_FRAME_TABLE
		script_context["map_script_lifecycle"] = "on_frame"
		script_context["map_script_table_label"] = table_label
		script_context["source_function"] = _map_script_source_function(MAP_SCRIPT_ON_FRAME_TABLE)
		var result := run_script(target_label, script_context)
		summary["result"] = result
		var runtime_summary := {}
		if not result.is_empty() and String(result.get("status", "")) != "vm_unavailable":
			runtime_summary = _apply_runtime_result(result)
		summary["runtime"] = runtime_summary
		summary["script"] = {
			"label": target_label,
			"status": String(result.get("status", "")),
			"message_count": _result_array_count(result, "messages"),
			"field_effect_count": _result_array_count(result, "field_effects"),
			"movement_count": _result_array_count(result, "movements"),
			"object_effect_count": _result_array_count(result, "object_effects"),
			"transition_effect_count": _result_array_count(result, "transition_effects"),
			"runtime": runtime_summary,
		}
		summary["status"] = String(result.get("status", "script_error"))
		return summary

	return summary


func run_map_load_scripts(context: Dictionary = {}) -> Dictionary:
	var map_load_context := context.duplicate(true)
	map_load_context["map_script_lifecycle"] = "map_load"
	var transition_summary := run_map_script_type(MAP_SCRIPT_ON_TRANSITION, map_load_context)
	var template_sync_summary := _sync_map_load_object_templates(
		_template_position_targets_from_map_script_summary(transition_summary)
	)
	var load_summary := run_map_script_type(MAP_SCRIPT_ON_LOAD, map_load_context)
	return {
		"status": _map_load_script_status(transition_summary, load_summary),
		"order": [MAP_SCRIPT_ON_TRANSITION, MAP_SCRIPT_ON_LOAD],
		"on_transition": transition_summary,
		"object_template_sync": template_sync_summary,
		"on_load": load_summary,
		"source_trace": [
			"src/overworld.c:LoadMapFromWarp/LoadMapFromCameraTransition",
			"src/script.c:RunOnTransitionMapScript",
			"src/fieldmap.c:InitMap/InitMapFromSavedGame",
			"src/script.c:RunOnLoadMapScript",
		],
	}


func _get_direct_script_preview(script: String) -> Dictionary:
	var script_record := _get_script_record(script)
	if script_record.is_empty():
		return {}

	var msgbox := _first_msgbox(script_record)
	if msgbox.is_empty():
		return {
			"script_label": script,
			"status": "no_preview_message",
		}

	var text_label := String(msgbox.get("text_label", ""))
	var text_record := _get_text_record(text_label)
	var encoding = text_record.get("encoding", {})
	var encoding_status := ""
	var source_byte_count := 0
	var terminator_present := false
	if typeof(encoding) == TYPE_DICTIONARY:
		encoding_status = String(encoding.get("status", ""))
		source_byte_count = int(encoding.get("byte_count", 0))
		terminator_present = bool(encoding.get("terminator_present", false))
	return {
		"script_label": script,
		"text_label": text_label,
		"mode": String(msgbox.get("mode", "")),
		"op": String(msgbox.get("op", "msgbox")),
		"line": int(msgbox.get("line", 0)),
		"text": String(text_record.get("display_text", "")),
		"status": "ok" if not text_record.is_empty() else "missing_text",
		"text_source": String(text_record.get("source", "")),
		"text_kind": String(text_record.get("kind", "text")),
		"encoding_status": encoding_status,
		"source_byte_count": source_byte_count,
		"terminator_present": terminator_present,
	}


func _append_script_output(lines: PackedStringArray, script: String, context: Dictionary) -> void:
	if script.is_empty() or script == "0x0":
		lines.append("Script: none")
		return

	lines.append("Script: %s" % script)
	var result := run_script(script, context)
	if result.is_empty():
		lines.append("ScriptVM: unavailable")
		return

	var vm_status := String(result.get("status", ""))
	if vm_status == "vm_unavailable":
		_append_direct_preview_output(lines, script)
		return

	lines.append("ScriptVM: %s" % vm_status)
	var runtime_summary := _apply_runtime_result(result)
	_append_runtime_summary_lines(lines, runtime_summary)
	_append_result_content_lines(lines, result)


func _append_runtime_summary_lines(lines: PackedStringArray, runtime_summary: Dictionary) -> void:
	var movement_summary = runtime_summary.get("movements", {})
	if typeof(movement_summary) == TYPE_DICTIONARY and not movement_summary.is_empty():
		lines.append("Movement effects: %d applied, %d skipped" % [
			_movement_summary_count(movement_summary, "applied"),
			_movement_summary_count(movement_summary, "skipped"),
		])

	var object_effect_summary = runtime_summary.get("object_effects", {})
	if typeof(object_effect_summary) == TYPE_DICTIONARY and not object_effect_summary.is_empty():
		lines.append("Object effects: %d applied, %d skipped" % [
			_movement_summary_count(object_effect_summary, "applied"),
			_movement_summary_count(object_effect_summary, "skipped"),
		])

	var field_effect_summary = runtime_summary.get("field_effects", {})
	if typeof(field_effect_summary) == TYPE_DICTIONARY and not field_effect_summary.is_empty():
		lines.append("Field effects: %d applied, %d skipped" % [
			_movement_summary_count(field_effect_summary, "applied"),
			_movement_summary_count(field_effect_summary, "skipped"),
		])

	var transition_summary = runtime_summary.get("transition_effects", {})
	if typeof(transition_summary) == TYPE_DICTIONARY and not transition_summary.is_empty():
		lines.append("Transition effects: %d applied, %d skipped" % [
			_movement_summary_count(transition_summary, "applied"),
			_movement_summary_count(transition_summary, "skipped"),
		])


func _append_result_content_lines(lines: PackedStringArray, result: Dictionary) -> void:
	var messages = result.get("messages", [])
	if typeof(messages) == TYPE_ARRAY and not messages.is_empty():
		for message in messages:
			if typeof(message) != TYPE_DICTIONARY:
				continue
			lines.append("Text label: %s" % String(message.get("text_label", "")))
			lines.append("Mode: %s" % String(message.get("mode", "")))
			lines.append("")
			lines.append(String(message.get("text", "")))
		return

	var unsupported_ops = result.get("unsupported_ops", [])
	if typeof(unsupported_ops) == TYPE_ARRAY and not unsupported_ops.is_empty():
		var unsupported = unsupported_ops[0]
		if typeof(unsupported) == TYPE_DICTIONARY:
			lines.append("Unsupported op: %s" % String(unsupported.get("op", "")))
			lines.append("Line: %d" % int(unsupported.get("line", 0)))
		return

	lines.append("No message emitted")


func _apply_runtime_result(result: Dictionary) -> Dictionary:
	var summary := {}
	if _map_runtime == null:
		return {}

	var movements = result.get("movements", [])
	if typeof(movements) == TYPE_ARRAY and not movements.is_empty() and _map_runtime.has_method("apply_script_movements"):
		summary["movements"] = _map_runtime.apply_script_movements(movements, _game_state)

	var object_effects = result.get("object_effects", [])
	if typeof(object_effects) == TYPE_ARRAY and not object_effects.is_empty() and _map_runtime.has_method("apply_script_object_effects"):
		summary["object_effects"] = _map_runtime.apply_script_object_effects(object_effects, _game_state)

	var field_effects = result.get("field_effects", [])
	if typeof(field_effects) == TYPE_ARRAY and not field_effects.is_empty() and _map_runtime.has_method("apply_script_field_effects"):
		var field_summary = _map_runtime.apply_script_field_effects(field_effects)
		if _movement_summary_count(field_summary, "applied") > 0 or _movement_summary_count(field_summary, "skipped") > 0:
			summary["field_effects"] = field_summary

	var transition_effects = result.get("transition_effects", [])
	if typeof(transition_effects) == TYPE_ARRAY and not transition_effects.is_empty():
		summary["transition_effects"] = _apply_transition_effects(transition_effects)

	return summary


func _apply_transition_effects(transition_effects: Array) -> Dictionary:
	var summary := {
		"applied": [],
		"skipped": [],
	}
	for transition_effect in transition_effects:
		if typeof(transition_effect) != TYPE_DICTIONARY:
			_record_skipped_transition(summary, "invalid_transition_effect", "", "", Vector2i.ZERO)
			continue

		var effect: Dictionary = transition_effect
		var op := String(effect.get("op", ""))
		var map_id := String(effect.get("map", ""))
		var position := _transition_position(effect)
		var position_source := "explicit" if bool(effect.get("has_explicit_position", false)) else "unset"
		var source_map_id := _current_map_id()
		var source_position := _transition_vector(effect, "source_position", _current_player_position())
		var trigger_position := _transition_vector(effect, "trigger_position", source_position)
		if map_id.is_empty():
			_record_skipped_transition(summary, "missing_map", map_id, op, position)
			continue
		if _data_registry == null or not _data_registry.has_method("has_map_data"):
			_record_skipped_transition(summary, "missing_data_registry", map_id, op, position)
			continue
		if not _data_registry.has_map_data(map_id):
			_record_skipped_transition(summary, "missing_generated_map", map_id, op, position)
			continue
		if _map_runtime == null or not _map_runtime.has_method("configure_from_data"):
			_record_skipped_transition(summary, "missing_map_runtime", map_id, op, position)
			continue

		var map_data: Dictionary = _data_registry.get_map_data(map_id)
		if not bool(effect.get("has_explicit_position", false)):
			var warp_id_info := _warp_id_from_value(effect.get("warp_id", WARP_ID_NONE_VALUE))
			if not bool(warp_id_info.get("valid", false)):
				_record_skipped_transition(summary, String(warp_id_info.get("reason", "invalid_warp_id")), map_id, op, position)
				continue
			var destination_position := _destination_position_for_warp_id(map_data, int(warp_id_info.get("value", WARP_ID_NONE_VALUE)))
			position = destination_position.get("position", Vector2i(-1, -1))
			position_source = String(destination_position.get("source", "warp_id"))

		var tileset_data: Dictionary = _data_registry.get_tileset_data_for_map(map_id)
		var map_size: Vector2i = _data_registry.get_map_size(map_id)
		var sequence_id := _next_transition_sequence_id
		_next_transition_sequence_id += 1
		var sequence := _build_transition_sequence(
			effect,
			sequence_id,
			source_map_id,
			source_position,
			trigger_position,
			map_id,
			position,
			position_source,
			map_data,
			tileset_data
		)
		if not sequence.is_empty():
			transition_sequence_requested.emit(sequence)

		var script_data: Dictionary = _data_registry.get_script_data_for_map(map_id)
		var pending_transition := {
			"id": sequence_id,
			"op": op,
			"map": map_id,
			"map_data": map_data,
			"tileset_data": tileset_data,
			"map_size": map_size,
			"script_data": script_data,
			"position": position,
			"position_source": position_source,
			"style": String(effect.get("style", "")),
			"presentation": String(effect.get("presentation", _default_transition_presentation(effect))),
			"sequence": sequence,
		}
		if _defer_transition_apply:
			_pending_transitions[sequence_id] = pending_transition
			summary["applied"].append(_transition_summary_from_payload(pending_transition, false, true))
		else:
			summary["applied"].append(_apply_transition_payload(pending_transition))
	return summary


func _apply_map_warp_event(interaction: Dictionary, event_data: Dictionary) -> Dictionary:
	var presentation = interaction.get("presentation", {})
	var presentation_kind := "normal"
	var entry_direction := ""
	var source_position := _current_player_position()
	var trigger_position := _interaction_position(interaction, source_position)
	if typeof(presentation) == TYPE_DICTIONARY:
		presentation_kind = String(presentation.get("kind", presentation_kind))
		entry_direction = String(presentation.get("entry_direction", entry_direction))
		source_position = _transition_vector(presentation, "source_position", source_position)
		trigger_position = _transition_vector(presentation, "trigger_position", trigger_position)

	return _apply_transition_effects([
		{
			"op": "map_warp",
			"line": 0,
			"map": String(event_data.get("dest_map", "")),
			"warp_id": event_data.get("dest_warp_id", WARP_ID_NONE_VALUE),
			"position": [-1, -1],
			"has_explicit_position": false,
			"uses_warp_id": true,
			"style": "normal",
			"presentation": presentation_kind,
			"entry_direction": entry_direction,
			"source_position": [source_position.x, source_position.y],
			"trigger_position": [trigger_position.x, trigger_position.y],
		},
	])


func _transition_position(transition_effect: Dictionary) -> Vector2i:
	var position = transition_effect.get("position", [])
	if typeof(position) == TYPE_VECTOR2I:
		return position
	if typeof(position) == TYPE_ARRAY and position.size() >= 2:
		return Vector2i(int(position[0]), int(position[1]))
	return Vector2i(-1, -1)


func _transition_vector(source: Dictionary, key: String, default_value: Vector2i) -> Vector2i:
	var value = source.get(key, default_value)
	if typeof(value) == TYPE_VECTOR2I:
		return value
	if typeof(value) == TYPE_ARRAY and value.size() >= 2:
		return Vector2i(int(value[0]), int(value[1]))
	if typeof(value) == TYPE_DICTIONARY:
		return Vector2i(int(value.get("x", default_value.x)), int(value.get("y", default_value.y)))
	return default_value


func _interaction_position(interaction: Dictionary, default_value: Vector2i) -> Vector2i:
	var position = interaction.get("position", default_value)
	if typeof(position) == TYPE_VECTOR2I:
		return position
	return default_value


func _destination_position_for_warp_id(map_data: Dictionary, warp_id: int) -> Dictionary:
	var events = map_data.get("events", {})
	var warp_events = events.get("warp_events", []) if typeof(events) == TYPE_DICTIONARY else []
	if warp_id >= 0 and typeof(warp_events) == TYPE_ARRAY and warp_id < warp_events.size():
		var warp_event = warp_events[warp_id]
		if typeof(warp_event) == TYPE_DICTIONARY:
			return {
				"position": Vector2i(
					int(warp_event.get("x", -1)),
					int(warp_event.get("y", -1))
				),
				"source": "warp_id",
			}

	var map_size := _map_size_from_map_data(map_data)
	if map_size == Vector2i.ZERO:
		return {
			"position": Vector2i(-1, -1),
			"source": "unresolved",
		}
	return {
		"position": Vector2i(map_size.x / 2, map_size.y / 2),
		"source": "center_fallback",
	}


func _map_size_from_map_data(map_data: Dictionary) -> Vector2i:
	var layout_info = map_data.get("layout", {})
	if typeof(layout_info) != TYPE_DICTIONARY:
		return Vector2i.ZERO
	return Vector2i(
		int(layout_info.get("width", 0)),
		int(layout_info.get("height", 0))
	)


func _warp_id_from_value(value) -> Dictionary:
	match typeof(value):
		TYPE_INT:
			return {"valid": true, "value": int(value)}
		TYPE_FLOAT:
			return {"valid": true, "value": int(value)}

	var text := String(value).strip_edges()
	if text.is_empty():
		return {"valid": true, "value": WARP_ID_NONE_VALUE}
	if text == "WARP_ID_NONE":
		return {"valid": true, "value": WARP_ID_NONE_VALUE}
	if text == "WARP_ID_DYNAMIC":
		return {"valid": false, "reason": "unsupported_dynamic_warp_id"}
	if text.is_valid_int():
		return {"valid": true, "value": int(text)}
	return {"valid": false, "reason": "invalid_warp_id"}


func _build_transition_sequence(
	effect: Dictionary,
	sequence_id: int,
	source_map_id: String,
	source_position: Vector2i,
	trigger_position: Vector2i,
	destination_map_id: String,
	destination_position: Vector2i,
	position_source: String,
	destination_map_data: Dictionary,
	destination_tileset_data: Dictionary
) -> Dictionary:
	var presentation := String(effect.get("presentation", _default_transition_presentation(effect)))
	var exit_task := _warp_exit_task(destination_map_data, destination_tileset_data, destination_position)
	var steps := []
	if presentation == "connection":
		exit_task = {}
		steps = _connection_transition_steps(source_position, trigger_position, destination_map_id, destination_position)
	elif presentation == "door":
		steps = _door_warp_steps(
			source_position,
			trigger_position,
			destination_map_id,
			destination_position,
			exit_task,
			_source_door_animation(trigger_position)
		)
	else:
		steps = _normal_warp_steps(destination_map_id, destination_position, exit_task)

	return {
		"id": sequence_id,
		"type": "map_transition",
		"presentation": presentation,
		"style": String(effect.get("style", "normal")),
		"source_map": source_map_id,
		"source_position": source_position,
		"trigger_position": trigger_position,
		"destination_map": destination_map_id,
		"destination_position": destination_position,
		"position_source": position_source,
		"exit_task": exit_task,
		"frame_basis": "60fps",
		"source_trace": [
			"src/field_control_avatar.c:TryDoorWarp/TryStartWarpEventScript",
			"src/field_screen_effect.c:DoWarp/DoDoorWarp/Task_DoDoorWarp/FieldCB_DefaultWarpExit",
			"src/field_door.c:sDoorOpenAnimFrames/sDoorCloseAnimFrames",
			"src/event_object_movement.c:MOVE_SPEED_NORMAL",
			"src/metatile_behavior.c:MetatileBehavior_IsDoor/IsDirectionalStairWarp/IsNonAnimDoor",
			"src/fieldmap.c:CameraMove/SetPositionFromConnection",
			"src/overworld.c:LoadMapFromCameraTransition",
		],
		"steps": steps,
		"unsupported": _transition_sequence_unsupported(presentation),
	}


func _default_transition_presentation(effect: Dictionary) -> String:
	if String(effect.get("style", "")) == "connection":
		return "connection"
	if String(effect.get("style", "")) == "silent":
		return "silent"
	return "normal"


func _door_warp_steps(
	source_position: Vector2i,
	trigger_position: Vector2i,
	destination_map_id: String,
	destination_position: Vector2i,
	exit_task: Dictionary,
	door_animation: Dictionary
) -> Array:
	var door_position := trigger_position + Vector2i.UP
	return [
		{"op": "lock_controls", "source": "DoDoorWarp"},
		{"op": "freeze_object_events", "source": "Task_DoDoorWarp"},
		{
			"op": "play_se",
			"sound": String(door_animation.get("sound_effect", "SE_DOOR")),
			"sound_source": "GetDoorSoundEffect",
			"position": door_position,
			"source": "Task_DoDoorWarp",
			"status": "metadata_only",
		},
		_door_step("door_open", door_position, "FieldAnimateDoorOpen", door_animation),
		{
			"op": "player_step",
			"movement_action": "MOVEMENT_ACTION_WALK_NORMAL_UP",
			"from": source_position,
			"to": trigger_position,
			"duration_frames": WALK_NORMAL_TILE_FRAMES,
			"source": "ObjectEventSetHeldMovement",
		},
		{"op": "hide_player", "visible": false, "source": "SetPlayerVisibility(FALSE)"},
		_door_step("door_close", door_position, "FieldAnimateDoorClose", door_animation),
		{"op": "fade_out", "color": "black_or_white_by_map_pair", "delay": FADE_DELAY_DEFAULT, "source": "WarpFadeOutScreen"},
		{"op": "load_map", "map": destination_map_id, "position": destination_position, "source": "WarpIntoMap"},
		{"op": "fade_in", "color": "black_or_white_by_map_pair", "delay": FADE_DELAY_DEFAULT, "source": "WarpFadeInScreen"},
		_exit_task_step(exit_task),
		{
			"op": "conditional_exit_door_player_step",
			"condition": "destination_metatile_behavior_is_door",
			"condition_result": String(exit_task.get("task", "")) == "Task_ExitDoor",
			"movement_action": "MOVEMENT_ACTION_WALK_NORMAL_DOWN",
			"from": destination_position,
			"to": destination_position + Vector2i.DOWN,
			"duration_frames": WALK_NORMAL_TILE_FRAMES,
			"source": "Task_ExitDoor",
		},
		{"op": "unlock_controls", "source": "Task_ExitDoor/Task_ExitNonDoor"},
	]


func _normal_warp_steps(
	destination_map_id: String,
	destination_position: Vector2i,
	exit_task: Dictionary
) -> Array:
	return [
		{"op": "lock_controls", "source": "DoWarp"},
		{"op": "fade_out", "color": "black_or_white_by_map_pair", "delay": FADE_DELAY_DEFAULT, "source": "WarpFadeOutScreen"},
		{"op": "load_map", "map": destination_map_id, "position": destination_position, "source": "WarpIntoMap"},
		{"op": "fade_in", "color": "black_or_white_by_map_pair", "delay": FADE_DELAY_DEFAULT, "source": "WarpFadeInScreen"},
		_exit_task_step(exit_task),
		{
			"op": "conditional_exit_door_player_step",
			"condition": "destination_metatile_behavior_is_door",
			"condition_result": String(exit_task.get("task", "")) == "Task_ExitDoor",
			"movement_action": "MOVEMENT_ACTION_WALK_NORMAL_DOWN",
			"from": destination_position,
			"to": destination_position + Vector2i.DOWN,
			"duration_frames": WALK_NORMAL_TILE_FRAMES,
			"source": "Task_ExitDoor",
		},
		{"op": "unlock_controls", "source": "Task_ExitDoor/Task_ExitNonDoor"},
	]


func _connection_transition_steps(
	source_position: Vector2i,
	trigger_position: Vector2i,
	destination_map_id: String,
	destination_position: Vector2i
) -> Array:
	return [
		{"op": "lock_controls", "source": "CameraMove"},
		{
			"op": "player_step",
			"movement_action": "MOVEMENT_ACTION_WALK_NORMAL",
			"from": source_position,
			"to": trigger_position,
			"duration_frames": WALK_NORMAL_TILE_FRAMES,
			"source": "src/event_object_movement.c:MOVE_SPEED_NORMAL; src/fieldmap.c:CameraMove",
		},
		{
			"op": "load_map",
			"map": destination_map_id,
			"position": destination_position,
			"source": "LoadMapFromCameraTransition",
		},
		{"op": "unlock_controls", "source": "CameraMove"},
	]


func _transition_sequence_unsupported(presentation: String) -> Array:
	var unsupported: Array = []
	if presentation == "connection":
		unsupported.append({
			"code": "map_connection_camera_backup_not_source_equivalent",
			"source": "src/fieldmap.c:CameraMove/MoveMapViewToBackup/LoadMapFromCameraTransition",
			"detail": "The sequence now preserves the 16-frame edge step before loading the connected map, but exact camera scrolling, backup-map copy timing, object-event carryover, and MAP_OFFSET-sized streaming behavior are still not source-equivalent.",
		})
	if presentation == "door":
		unsupported.append({
			"code": "door_warp_audio_metadata_only",
			"source": "src/field_screen_effect.c:Task_DoDoorWarp -> PlaySE(GetDoorSoundEffect(...))",
			"detail": "The sequence records the source door sound effect but TransitionSequencePlayer does not play audio yet.",
		})
	return unsupported


func _door_step(op: String, position: Vector2i, source: String, door_animation: Dictionary) -> Dictionary:
	var step := {
		"op": op,
		"position": position,
		"frame_time": DOOR_ANIM_FRAME_TIME,
		"frame_count": DOOR_ANIM_FRAME_COUNT,
		"duration_frames": DOOR_ANIM_TOTAL_FRAMES,
		"source": source,
	}
	step["frame_indices"] = [-1, 0, 1, 2] if op == "door_open" else [2, 1, 0, -1]
	if not door_animation.is_empty():
		step["animation"] = door_animation
	return step


func _source_door_animation(position: Vector2i) -> Dictionary:
	if _map_runtime == null or not _map_runtime.has_method("get_door_animation_at"):
		return {}

	var animation = _map_runtime.get_door_animation_at(position)
	return animation if typeof(animation) == TYPE_DICTIONARY else {}


func _exit_task_step(exit_task: Dictionary) -> Dictionary:
	return {
		"op": "exit_task_select",
		"source": "SetUpWarpExitTask",
		"branches": ["Task_ExitDoor", "Task_ExitStairs", "Task_ExitNonAnimDoor", "Task_ExitNonDoor"],
		"selected": String(exit_task.get("task", "Task_ExitNonDoor")),
		"behavior": int(exit_task.get("behavior", -1)),
		"behavior_name": String(exit_task.get("behavior_name", "")),
	}


func _warp_exit_task(map_data: Dictionary, tileset_data: Dictionary, position: Vector2i) -> Dictionary:
	var behavior_info := _metatile_behavior_info(map_data, tileset_data, position)
	var behavior_name := String(behavior_info.get("behavior_name", ""))
	var task := "Task_ExitNonDoor"
	if WARP_EXIT_DOOR_BEHAVIORS.has(behavior_name):
		task = "Task_ExitDoor"
	elif WARP_EXIT_DIRECTIONAL_STAIR_BEHAVIORS.has(behavior_name):
		task = "Task_ExitStairs"
	elif WARP_EXIT_NON_ANIM_DOOR_BEHAVIORS.has(behavior_name):
		task = "Task_ExitNonAnimDoor"

	return {
		"task": task,
		"behavior": int(behavior_info.get("behavior", -1)),
		"behavior_name": behavior_name,
		"position": position,
		"stairs_movement_disabled": false,
		"source": "SetUpWarpExitTask",
	}


func _metatile_behavior_info(map_data: Dictionary, tileset_data: Dictionary, position: Vector2i) -> Dictionary:
	var metatile_id := _metatile_id_from_map_data(map_data, position)
	if metatile_id < 0:
		return {"behavior": -1, "behavior_name": "", "metatile_id": metatile_id}

	var entries = tileset_data.get("metatile_entries", [])
	if typeof(entries) != TYPE_ARRAY:
		return {"behavior": -1, "behavior_name": "", "metatile_id": metatile_id}

	for entry in entries:
		if typeof(entry) != TYPE_DICTIONARY or int(entry.get("id", -1)) != metatile_id:
			continue
		var attribute = entry.get("attribute", {})
		if typeof(attribute) != TYPE_DICTIONARY:
			return {"behavior": -1, "behavior_name": "", "metatile_id": metatile_id}
		return {
			"behavior": int(attribute.get("behavior", -1)),
			"behavior_name": String(attribute.get("behavior_name", "")),
			"metatile_id": metatile_id,
		}

	return {"behavior": -1, "behavior_name": "", "metatile_id": metatile_id}


func _metatile_id_from_map_data(map_data: Dictionary, position: Vector2i) -> int:
	var block_ids = map_data.get("block_ids", [])
	if typeof(block_ids) != TYPE_ARRAY or position.y < 0 or position.y >= block_ids.size():
		return -1

	var row = block_ids[position.y]
	if typeof(row) != TYPE_ARRAY or position.x < 0 or position.x >= row.size():
		return -1
	return int(row[position.x])


func _step_coord_event_target(cell: Vector2i) -> Dictionary:
	if _map_runtime == null or not _map_runtime.has_method("get_coord_event_target"):
		return {}
	var target = _map_runtime.get_coord_event_target(cell, _game_state)
	return target if typeof(target) == TYPE_DICTIONARY else {}


func _step_warp_event_target(cell: Vector2i) -> Dictionary:
	if _map_runtime == null or not _map_runtime.has_method("get_warp_event_target"):
		return {}
	var target = _map_runtime.get_warp_event_target(cell)
	return target if typeof(target) == TYPE_DICTIONARY else {}


func _interaction_step_summary(interaction: Dictionary) -> Dictionary:
	if interaction.is_empty():
		return {
			"status": "none",
			"matched": false,
		}
	return {
		"status": "matched",
		"matched": true,
		"type": String(interaction.get("type", "")),
		"position": interaction.get("position", Vector2i.ZERO),
		"script": String(interaction.get("script", "")),
		"event": interaction.get("event", {}),
	}


func _finish_player_step(summary: Dictionary, consumed_by: String, reason: String) -> Dictionary:
	summary["status"] = "consumed"
	summary["consumed"] = true
	summary["consumed_by"] = consumed_by
	summary["reason"] = reason
	return summary


func _emit_pending_player_step_script(title: String, detail: Dictionary) -> void:
	var lines := PackedStringArray([
		"Player step",
		title,
		"Script: %s" % String(detail.get("script", "pending")),
		"Source: %s" % String(detail.get("source", "")),
		"Runtime: pending",
	])
	debug_message_requested.emit(lines)


func _evaluate_misc_walking_scripts(cell: Vector2i, behavior_name: String) -> Dictionary:
	var summary := {
		"status": "none",
		"consumes_step": false,
		"position": cell,
		"behavior_name": behavior_name,
		"source": "src/field_control_avatar.c:TryStartMiscWalkingScripts",
	}
	if MISC_WALKING_SCRIPT_BEHAVIORS.has(behavior_name):
		var record: Dictionary = MISC_WALKING_SCRIPT_BEHAVIORS[behavior_name]
		summary["status"] = "script_pending"
		summary["consumes_step"] = true
		summary["reason"] = "misc_walking_script_pending"
		summary["script"] = String(record.get("script", ""))
		summary["source"] = String(record.get("source", summary.get("source", "")))
		summary["unsupported"] = [{
			"code": "misc_walking_script_runtime_pending",
			"detail": "The source consumes this step before step-count, Repel, DexNav, and wild encounter checks. Godot records the request until the field effect/script presentation is implemented.",
		}]
		return summary
	if MISC_WALKING_CONTINUE_BEHAVIORS.has(behavior_name):
		summary["status"] = "side_effect_pending"
		summary["side_effect"] = String(MISC_WALKING_CONTINUE_BEHAVIORS[behavior_name])
		summary["unsupported"] = [{
			"code": "misc_walking_nonblocking_effect_pending",
			"detail": "The source plays this secret-base mat effect and continues the step pipeline.",
		}]
	return summary


func _evaluate_step_count_scripts(
	behavior_name: String,
	forced_move: bool,
	forced_movement_tile: bool,
	options: Dictionary
) -> Dictionary:
	var summary := {
		"status": "recorded_pending_systems",
		"consumes_step": false,
		"behavior_name": behavior_name,
		"forced_move": forced_move,
		"forced_movement_tile": forced_movement_tile,
		"source_order": STEP_COUNT_SOURCE_ORDER.duplicate(),
		"source": "src/field_control_avatar.c:TryStartStepCountScript",
		"counter_updates": [
			{"name": "IncrementRematchStepCounter", "status": "future", "source": "src/battle_setup.c"},
			{"name": "UpdateFriendshipStepCounter", "status": "future", "source": "src/field_control_avatar.c"},
			{"name": "UpdateFarawayIslandStepCounter", "status": "future", "source": "src/faraway_island.c"},
			{"name": "UpdateFollowerStepCounter", "status": "future", "source": "src/field_control_avatar.c"},
		],
		"consuming_checks": [],
		"unsupported": [],
	}
	if bool(options.get("in_union_room", false)):
		summary["status"] = "skipped_union_room"
		return summary

	if not forced_move and not forced_movement_tile:
		summary["consuming_checks"] = [
			"UpdatePoisonStepCounter -> EventScript_FieldPoison",
			"ShouldEggHatch -> EventScript_EggHatch",
			"AbnormalWeatherHasExpired -> AbnormalWeather_EventScript_EndEventAndCleanup_1",
			"ShouldDoBrailleRegicePuzzle -> IslandCave_EventScript_OpenRegiEntrance",
			"ShouldDoWallyCall -> MauvilleCity_EventScript_RegisterWallyCall",
			"ShouldDoScottFortreeCall -> Route119_EventScript_ScottWonAtFortreeGymCall",
			"ShouldDoScottBattleFrontierCall -> LittlerootTown_ProfessorBirchsLab_EventScript_ScottAboardSSTidalCall",
			"ShouldDoRoxanneCall -> RustboroCity_Gym_EventScript_RegisterRoxanne",
			"ShouldDoRivalRayquazaCall -> MossdeepCity_SpaceCenter_2F_EventScript_RivalRayquazaCall",
			"UpdateVsSeekerStepCounter -> EventScript_VsSeekerChargingDone",
		]
	else:
		summary["forced_skip_checks"] = [
			"UpdatePoisonStepCounter",
			"ShouldEggHatch",
			"AbnormalWeatherHasExpired",
			"ShouldDo*Call",
			"UpdateVsSeekerStepCounter",
		]

	summary["post_forced_checks"] = [
		"SafariZoneTakeStep -> SafariZone_EventScript_TimesUp",
		"CountSSTidalStep -> SSTidalCorridor_EventScript_ReachedStepCount",
		"TryStartMatchCall -> StartMatchCall",
	]
	summary["unsupported"] = [{
		"code": "step_count_systems_pending",
		"detail": "The source order is recorded, but party friendship, poison, egg hatch, abnormal weather, story calls, Safari, S.S. Tidal, and Match Call side effects need dedicated source-backed runtime slices.",
	}]
	return summary


func _update_repel_counter() -> Dictionary:
	var raw_value := _get_game_var("VAR_REPEL_STEP_COUNT")
	var steps := raw_value & (REPEL_LURE_MASK - 1)
	var is_lure := (raw_value & REPEL_LURE_MASK) != 0
	var summary := {
		"status": "inactive",
		"consumes_step": false,
		"var": "VAR_REPEL_STEP_COUNT",
		"raw_before": raw_value,
		"steps_before": steps,
		"is_lure": is_lure,
		"source": "src/wild_encounter.c:UpdateRepelCounter",
		"unsupported": [{
			"code": "spray_wore_off_presentation_pending",
			"detail": "When the counter reaches 0, Godot records the source script request; the spray-wore-off message/UI flow is still pending.",
		}],
	}
	if steps <= 0:
		return summary

	steps -= 1
	var raw_after := steps | (REPEL_LURE_MASK if is_lure else 0)
	_set_game_var("VAR_REPEL_STEP_COUNT", raw_after)
	summary["status"] = "decremented"
	summary["raw_after"] = raw_after
	summary["steps_after"] = steps
	if steps == 0:
		summary["status"] = "script_pending"
		summary["consumes_step"] = true
		summary["reason"] = "repel_lure_wore_off"
		summary["script"] = "EventScript_SprayWoreOff"
	return summary


func _evaluate_dexnav_step() -> Dictionary:
	var searching := _game_state != null and _game_state.has_method("is_flag_set") and bool(_game_state.is_flag_set("DN_FLAG_SEARCHING"))
	return {
		"status": "searching_pending" if searching else "inactive",
		"consumes_step": false,
		"flag": "DN_FLAG_SEARCHING",
		"source": "src/dexnav.c:OnStep_DexNavSearch",
		"unsupported": [{
			"code": "dexnav_step_search_pending",
			"detail": "Proximity updates, lost-signal/moved-too-fast scripts, hidden search reveal, and DexNav battle setup need a dedicated source-backed runtime slice.",
		}] if searching else [],
	}


func _increment_game_stat(stat_name: String) -> Dictionary:
	return _increment_game_stat_from(stat_name, "src/field_control_avatar.c:ProcessPlayerFieldInput")


func _increment_game_stat_from(stat_name: String, source: String) -> Dictionary:
	var before := 0
	if _game_state != null and _game_state.has_method("get_game_stat"):
		before = int(_game_state.get_game_stat(stat_name, 0))
	if _game_state != null and _game_state.has_method("increment_game_stat"):
		var after := int(_game_state.increment_game_stat(stat_name, 1))
		return {
			"status": "incremented",
			"stat": stat_name,
			"before": before,
			"after": after,
			"source": source,
		}
	return {
		"status": "missing_game_state",
		"stat": stat_name,
		"before": before,
		"after": before,
		"source": source,
	}


func _set_game_var(var_name: String, value: int) -> void:
	if _game_state != null and _game_state.has_method("set_var"):
		_game_state.set_var(var_name, value)


func _is_forced_movement_behavior(behavior_name: String) -> bool:
	if behavior_name in [
		"MB_EASTWARD_CURRENT",
		"MB_WESTWARD_CURRENT",
		"MB_NORTHWARD_CURRENT",
		"MB_SOUTHWARD_CURRENT",
		"MB_MUDDY_SLOPE",
		"MB_CRACKED_FLOOR",
		"MB_WATERFALL",
		"MB_ICE",
		"MB_SECRET_BASE_JUMP_MAT",
		"MB_SECRET_BASE_SPIN_MAT",
		"MB_SPIN_RIGHT",
		"MB_SPIN_LEFT",
		"MB_SPIN_UP",
		"MB_SPIN_DOWN",
	]:
		return true
	return behavior_name.begins_with("MB_WALK_") or behavior_name.begins_with("MB_SLIDE_")


func _current_map_id() -> String:
	if _game_state != null:
		return String(_game_state.current_map_id)
	if _map_runtime != null and _map_runtime.has_method("get_current_map_id"):
		return String(_map_runtime.get_current_map_id())
	return ""


func _current_map_type(map_id: String = "") -> String:
	var resolved_map_id := map_id
	if resolved_map_id.is_empty():
		resolved_map_id = _current_map_id()
	if _data_registry == null or not _data_registry.has_method("get_map_data") or resolved_map_id.is_empty():
		return ""
	var map_data = _data_registry.get_map_data(resolved_map_id)
	if typeof(map_data) != TYPE_DICTIONARY:
		return ""
	var map_info = map_data.get("map", {})
	if typeof(map_info) != TYPE_DICTIONARY:
		return ""
	return String(map_info.get("map_type", map_info.get("mapType", "")))


func _current_player_position() -> Vector2i:
	if _game_state != null:
		return _game_state.player_grid_position
	return Vector2i.ZERO


func _current_player_party() -> Array:
	if _game_state != null and _game_state.has_method("get_player_party"):
		return _game_state.get_player_party()
	return []


func _current_player_battle_party() -> Array:
	var party := _current_player_party()
	if _party_runtime != null and _party_runtime.has_method("build_battle_party"):
		var battle_party = _party_runtime.build_battle_party(party)
		return battle_party if typeof(battle_party) == TYPE_ARRAY else party
	return party


func _current_player_active_battle_index(battle_party: Array) -> int:
	if _party_runtime != null and _party_runtime.has_method("first_live_mon_index"):
		var live_index := int(_party_runtime.first_live_mon_index(battle_party))
		if live_index >= 0 and live_index < battle_party.size():
			return live_index
	for index in range(battle_party.size()):
		var mon = battle_party[index]
		if typeof(mon) != TYPE_DICTIONARY:
			continue
		var species := String(mon.get("species", ""))
		if species.is_empty() or species == "SPECIES_NONE":
			continue
		if bool(mon.get("is_egg", false)):
			continue
		if int(mon.get("hp", 0)) > 0 and not bool(mon.get("fainted", false)):
			return index
	return 0


func _current_metatile_behavior_name(cell: Vector2i) -> String:
	if _map_runtime == null:
		return ""
	if _map_runtime.has_method("get_metatile_behavior_name_at"):
		return String(_map_runtime.get_metatile_behavior_name_at(cell))
	if _map_runtime.has_method("get_cell_info"):
		var cell_info = _map_runtime.get_cell_info(cell)
		if typeof(cell_info) == TYPE_DICTIONARY:
			return String(cell_info.get("behavior_name", ""))
	return ""


func _apply_transition_payload(payload: Dictionary) -> Dictionary:
	var map_id := String(payload.get("map", ""))
	var map_data = payload.get("map_data", {})
	var tileset_data = payload.get("tileset_data", {})
	var map_size = payload.get("map_size", Vector2i.ZERO)
	var position = payload.get("position", Vector2i(-1, -1))
	if typeof(map_data) != TYPE_DICTIONARY or typeof(tileset_data) != TYPE_DICTIONARY:
		return _transition_summary_from_payload(payload, false, false, "invalid_transition_payload")

	if typeof(map_size) != TYPE_VECTOR2I:
		map_size = _map_size_from_map_data(map_data)
	if typeof(position) != TYPE_VECTOR2I:
		position = Vector2i(-1, -1)

	_map_runtime.configure_from_data(map_data, tileset_data, map_size)
	if _game_state != null:
		_game_state.current_map_id = map_id

	reset_wild_encounter_immunity_steps()
	var position_applied := false
	if position != Vector2i(-1, -1):
		position_applied = (
			_map_runtime.has_method("set_player_grid_position")
			and _map_runtime.set_player_grid_position(position, _game_state)
		)

	var script_data = payload.get("script_data", {})
	configure_from_script_data(script_data if typeof(script_data) == TYPE_DICTIONARY else {})
	var map_script_summary := run_map_load_scripts({
		"trigger": "transition_load",
		"map": map_id,
		"position": [position.x, position.y],
	})
	return _transition_summary_from_payload(payload, position_applied, false, "ok", map_script_summary)


func _transition_summary_from_payload(
	payload: Dictionary,
	position_applied: bool,
	deferred: bool,
	status := "ok",
	map_script_summary: Dictionary = {}
) -> Dictionary:
	return {
		"id": int(payload.get("id", 0)),
		"status": status,
		"op": String(payload.get("op", "")),
		"map": String(payload.get("map", "")),
		"position": payload.get("position", Vector2i(-1, -1)),
		"position_applied": position_applied,
		"position_source": String(payload.get("position_source", "")),
		"style": String(payload.get("style", "")),
		"presentation": String(payload.get("presentation", _default_transition_presentation({}))),
		"deferred": deferred,
		"sequence": payload.get("sequence", {}),
		"map_scripts": map_script_summary,
	}


func _record_skipped_transition(
	summary: Dictionary,
	reason: String,
	map_id: String,
	op: String,
	position: Vector2i
) -> void:
	summary["skipped"].append({
		"reason": reason,
		"op": op,
		"map": map_id,
		"position": position,
	})


func _movement_summary_count(summary: Dictionary, key: String) -> int:
	var entries = summary.get(key, [])
	return entries.size() if typeof(entries) == TYPE_ARRAY else 0


func _create_standard_wild_battle_state(summary: Dictionary) -> Dictionary:
	if _battle_engine == null or not _battle_engine.has_method("create_wild_battle_state"):
		return {
			"status": "missing_battle_engine",
			"source": "src/battle_setup.c:BattleSetup_StartWildBattle",
		}
	var encounter = summary.get("encounter_result", {})
	if typeof(encounter) != TYPE_DICTIONARY or encounter.is_empty():
		return {
			"status": "missing_encounter_result",
			"source": "src/wild_encounter.c:StandardWildEncounter",
		}
	var player_party := _current_player_battle_party()
	var battle_options := {
		"battle_origin": "standard_wild_encounter",
		"map": String(summary.get("map", "")),
		"map_type": _current_map_type(String(summary.get("map", ""))),
		"metatile_behavior": String(summary.get("current_metatile_behavior", "")),
		"player_active": _current_player_active_battle_index(player_party),
	}
	var battle_state = _battle_engine.create_wild_battle_state(encounter, player_party, battle_options)
	if typeof(battle_state) != TYPE_DICTIONARY:
		return {
			"status": "invalid_battle_state",
			"source": "src/battle_setup.c:BattleSetup_StartWildBattle",
		}
	return {
		"status": "state_created" if String(battle_state.get("status", "")) == "ok" else String(battle_state.get("status", "error")),
		"battle_state": battle_state,
		"player_party_count": player_party.size(),
		"opponent_party_count": _result_array_count(battle_state, "opponent_party"),
		"source": "src/wild_encounter.c:StandardWildEncounter -> src/battle_setup.c:BattleSetup_StartWildBattle",
	}


func _request_standard_wild_battle_start(summary: Dictionary, battle_setup: Dictionary) -> Dictionary:
	var battle_state = battle_setup.get("battle_state", {})
	if typeof(battle_state) != TYPE_DICTIONARY or battle_state.is_empty():
		return {
			"status": "missing_battle_state",
			"source": "src/battle_setup.c:DoStandardWildBattle",
		}

	var sequence_id := _next_transition_sequence_id
	_next_transition_sequence_id += 1
	var statistics := _increment_standard_wild_battle_stats()
	var sequence := _build_standard_wild_battle_start_sequence(
		sequence_id,
		summary,
		battle_setup,
		battle_state,
		statistics
	)
	battle_start_sequence_requested.emit(sequence)
	return {
		"status": "sequence_requested",
		"id": sequence_id,
		"sequence": sequence,
		"statistics": statistics,
		"source": "src/battle_setup.c:DoStandardWildBattle -> CreateBattleStartTask",
	}


func _build_standard_wild_battle_start_sequence(
	sequence_id: int,
	summary: Dictionary,
	battle_setup: Dictionary,
	battle_state: Dictionary,
	statistics: Dictionary
) -> Dictionary:
	var setup = battle_state.get("battle_setup", {})
	setup = setup if typeof(setup) == TYPE_DICTIONARY else {}
	var transition = setup.get("battle_transition", {})
	transition = transition if typeof(transition) == TYPE_DICTIONARY else {}
	var battle_type_flags = battle_state.get("battle_type_flags", [])
	battle_type_flags = battle_type_flags if typeof(battle_type_flags) == TYPE_ARRAY else []
	return {
		"id": sequence_id,
		"type": "battle_start",
		"battle_kind": "wild",
		"presentation": "wild_battle_start",
		"source_map": String(summary.get("map", "")),
		"source_position": summary.get("position", Vector2i.ZERO),
		"species": String(summary.get("species", "")),
		"level": int(summary.get("level", 0)),
		"battle_state": battle_state,
		"battle_setup_status": String(battle_setup.get("status", "")),
		"battle_transition": transition,
		"battle_type_flags": battle_type_flags.duplicate(true),
		"statistics": statistics,
		"frame_basis": "60fps",
		"source_order": [
			"LockPlayerFieldControls",
			"FreezeObjectEvents",
			"StopPlayerAvatar",
			"gMain.savedCallback = CB2_EndWildBattle",
			"gBattleTypeFlags = 0",
			"CreateBattleStartTask(GetWildBattleTransition(), 0)",
			"IncrementGameStat(GAME_STAT_TOTAL_BATTLES)",
			"IncrementGameStat(GAME_STAT_WILD_BATTLES)",
			"IncrementDailyWildBattles",
			"TryUpdateGymLeaderRematchFromWild",
			"Task_BattleStart: wait until !FldEffPoison_IsActive()",
			"BattleTransition_StartOnField",
			"ClearMirageTowerPulseBlendEffect",
			"Task_BattleStart: wait until IsBattleTransitionDone()",
			"PrepareForFollowerNPCBattle",
			"CleanupOverworldWindowsAndTilemaps",
			"SetMainCallback2(CB2_InitBattle)",
			"RestartWildEncounterImmunitySteps",
			"ClearPoisonStepCounter",
		],
		"source_trace": [
			"src/wild_encounter.c:StandardWildEncounter",
			"src/battle_setup.c:BattleSetup_StartWildBattle",
			"src/battle_setup.c:DoStandardWildBattle",
			"src/battle_setup.c:CreateBattleStartTask",
			"src/battle_setup.c:Task_BattleStart",
			"src/battle_transition.c:BattleTransition_StartOnField",
			"src/battle_main.c:CB2_InitBattle",
		],
		"steps": _standard_wild_battle_start_steps(transition, battle_type_flags),
		"unsupported": _standard_wild_battle_start_unsupported(),
	}


func _standard_wild_battle_start_steps(transition: Dictionary, battle_type_flags: Array) -> Array:
	return [
		{
			"op": "lock_controls",
			"source": "src/battle_setup.c:DoStandardWildBattle -> src/script.c:LockPlayerFieldControls",
			"side_effects": ["lock input", "end DexNav search"],
		},
		{
			"op": "freeze_object_events",
			"source": "src/battle_setup.c:DoStandardWildBattle -> src/event_object_movement.c:FreezeObjectEvents",
			"scope": "active object events except player",
			"side_effects": ["pause sprite animations", "pause affine animations"],
			"status": "metadata_only",
		},
		{
			"op": "stop_player_avatar",
			"source": "src/battle_setup.c:DoStandardWildBattle -> src/field_player_avatar.c:StopPlayerAvatar",
			"side_effects": ["stop held movement", "snap facing", "reset bike speed"],
			"status": "metadata_only",
		},
		{"op": "set_saved_callback", "callback": "CB2_EndWildBattle", "source": "src/battle_setup.c:DoStandardWildBattle"},
		{"op": "set_battle_type_flags", "flags": battle_type_flags.duplicate(true), "source": "src/battle_setup.c:DoStandardWildBattle"},
		{
			"op": "create_battle_start_task",
			"task": "Task_BattleStart",
			"priority": 1,
			"transition": String(transition.get("selected", "")),
			"transition_type": String(transition.get("transition_type", "")),
			"transition_comparison": String(transition.get("comparison", "")),
			"source": "src/battle_setup.c:CreateBattleStartTask",
		},
		{
			"op": "play_bgm",
			"function": "PlayMapChosenOrBattleBGM",
			"song": 0,
			"song_meaning": "choose map wild battle BGM",
			"wild_bgm_candidates": ["MUS_VS_WILD", "MUS_RG_VS_WILD"],
			"source": "src/battle_setup.c:CreateBattleStartTask",
			"status": "metadata_only",
		},
		{"op": "wait_poison_clear", "condition": "!FldEffPoison_IsActive()", "source": "src/battle_setup.c:Task_BattleStart"},
		{
			"op": "battle_transition_start",
			"transition": String(transition.get("selected", "")),
			"transition_type": String(transition.get("transition_type", "")),
			"comparison": String(transition.get("comparison", "")),
			"duration_frames": BATTLE_TRANSITION_STUB_FRAMES,
			"presentation_stub": true,
			"source": "src/battle_setup.c:Task_BattleStart -> BattleTransition_StartOnField",
		},
		{
			"op": "clear_mirage_tower_pulse_blend",
			"source": "src/battle_setup.c:Task_BattleStart -> ClearMirageTowerPulseBlendEffect",
			"status": "metadata_only",
		},
		{"op": "wait_battle_transition_done", "condition": "IsBattleTransitionDone()", "source": "src/battle_setup.c:Task_BattleStart"},
		{"op": "prepare_follower_npc_battle", "source": "src/battle_setup.c:Task_BattleStart", "status": "metadata_only"},
		{"op": "cleanup_overworld_windows_tilemaps", "source": "src/battle_setup.c:Task_BattleStart", "status": "metadata_only"},
		{
			"op": "set_main_callback",
			"callback": "CB2_InitBattle",
			"source": "src/battle_setup.c:Task_BattleStart",
			"status": "battle_scene_pending",
		},
		{"op": "restart_wild_encounter_immunity_steps", "source": "src/battle_setup.c:Task_BattleStart"},
		{"op": "clear_poison_step_counter", "var": "VAR_POISON_STEP_COUNTER", "source": "src/battle_setup.c:Task_BattleStart"},
	]


func _build_trainer_battle_start_sequence(
	sequence_id: int,
	request: Dictionary,
	battle_setup: Dictionary,
	battle_state: Dictionary,
	statistics: Dictionary
) -> Dictionary:
	var setup = battle_state.get("battle_setup", {})
	setup = setup if typeof(setup) == TYPE_DICTIONARY else {}
	var transition = setup.get("battle_transition", {})
	transition = transition if typeof(transition) == TYPE_DICTIONARY else {}
	var battle_type_flags = battle_state.get("battle_type_flags", [])
	battle_type_flags = battle_type_flags if typeof(battle_type_flags) == TYPE_ARRAY else []
	var trainer = battle_state.get("trainer", {})
	trainer = trainer if typeof(trainer) == TYPE_DICTIONARY else {}
	return {
		"id": sequence_id,
		"type": "battle_start",
		"battle_kind": "trainer",
		"presentation": "trainer_battle_start",
		"enable_battle_scene_handoff": true,
		"source_map": String(request.get("map", _current_map_id())),
		"source_position": request.get("position", _current_player_position()),
		"trainer": trainer,
		"trainer_id": String(request.get("trainer_id", trainer.get("symbol", ""))),
		"battle_state": battle_state,
		"debug_fixture": bool(request.get("debug_fixture", false)),
		"debug_player_party": battle_setup.get("debug_player_party", {}),
		"battle_setup_status": String(battle_setup.get("status", "")),
		"battle_transition": transition,
		"battle_type_flags": battle_type_flags.duplicate(true),
		"statistics": statistics,
		"frame_basis": "60fps",
		"source_order": [
			"Godot debug fixture dispatches a structured trainer battle request",
			"Source trainerbattle path normally runs trainer_battle.inc approach/intro scripts before dotrainerbattle",
			"gBattleTypeFlags |= BATTLE_TYPE_TRAINER",
			"CreateBattleStartTask(GetTrainerBattleTransition(), 0)",
			"IncrementGameStat(GAME_STAT_TOTAL_BATTLES)",
			"IncrementGameStat(GAME_STAT_TRAINER_BATTLES)",
			"Task_BattleStart: wait until !FldEffPoison_IsActive()",
			"BattleTransition_StartOnField",
			"ClearMirageTowerPulseBlendEffect",
			"Task_BattleStart: wait until IsBattleTransitionDone()",
			"PrepareForFollowerNPCBattle",
			"CleanupOverworldWindowsAndTilemaps",
			"SetMainCallback2(CB2_InitBattle)",
			"RestartWildEncounterImmunitySteps",
			"ClearPoisonStepCounter",
		],
		"source_trace": [
			"src/battle_setup.c:BattleSetup_StartTrainerBattle",
			"src/battle_setup.c:DoTrainerBattle",
			"src/battle_setup.c:GetTrainerBattleTransition",
			"src/battle_setup.c:CreateBattleStartTask",
			"src/battle_setup.c:Task_BattleStart",
			"src/battle_transition.c:BattleTransition_StartOnField",
			"src/battle_main.c:CB2_InitBattle",
		],
		"steps": _trainer_battle_start_steps(transition, battle_type_flags),
		"unsupported": _trainer_battle_start_unsupported(),
	}


func _trainer_battle_start_steps(transition: Dictionary, battle_type_flags: Array) -> Array:
	return [
		{
			"op": "lock_controls",
			"source": "data/scripts/trainer_battle.inc:EventScript_TryDoNormalTrainerBattle -> src/scrcmd.c:ScrCmd_lock",
			"side_effects": ["lock input", "end DexNav search"],
			"status": "debug_bridge_first_slice",
		},
		{
			"op": "freeze_object_events",
			"source": "data/scripts/trainer_battle.inc:EventScript_StartTrainerApproach -> src/scrcmd.c:ScrCmd_lockfortrainer",
			"scope": "active object events except player",
			"status": "debug_bridge_metadata_only",
		},
		{
			"op": "stop_player_avatar",
			"source": "data/scripts/trainer_battle.inc:EventScript_TrainerApproach -> special DoTrainerApproach/waitstate",
			"status": "debug_bridge_metadata_only",
		},
		{"op": "set_saved_callback", "callback": "CB2_EndTrainerBattle", "source": "src/battle_setup.c:BattleSetup_StartTrainerBattle"},
		{"op": "set_battle_type_flags", "flags": battle_type_flags.duplicate(true), "source": "src/battle_setup.c:BattleSetup_StartTrainerBattle"},
		{
			"op": "create_battle_start_task",
			"task": "Task_BattleStart",
			"priority": 1,
			"transition": String(transition.get("selected", "")),
			"transition_type": String(transition.get("transition_type", "")),
			"transition_comparison": String(transition.get("comparison", "")),
			"source": "src/battle_setup.c:CreateBattleStartTask",
		},
		{
			"op": "play_bgm",
			"function": "PlayTrainerEncounterMusic",
			"song_meaning": "choose trainer battle BGM",
			"trainer_bgm_candidates": ["MUS_VS_TRAINER", "MUS_VS_AQUA_MAGMA"],
			"source": "src/battle_setup.c:BattleSetup_StartTrainerBattle",
			"status": "metadata_only",
		},
		{"op": "wait_poison_clear", "condition": "!FldEffPoison_IsActive()", "source": "src/battle_setup.c:Task_BattleStart"},
		{
			"op": "battle_transition_start",
			"transition": String(transition.get("selected", "")),
			"transition_type": String(transition.get("transition_type", "")),
			"comparison": String(transition.get("comparison", "")),
			"duration_frames": BATTLE_TRANSITION_STUB_FRAMES,
			"presentation_stub": true,
			"source": "src/battle_setup.c:Task_BattleStart -> BattleTransition_StartOnField",
		},
		{
			"op": "clear_mirage_tower_pulse_blend",
			"source": "src/battle_setup.c:Task_BattleStart -> ClearMirageTowerPulseBlendEffect",
			"status": "metadata_only",
		},
		{"op": "wait_battle_transition_done", "condition": "IsBattleTransitionDone()", "source": "src/battle_setup.c:Task_BattleStart"},
		{"op": "prepare_follower_npc_battle", "source": "src/battle_setup.c:Task_BattleStart", "status": "metadata_only"},
		{"op": "cleanup_overworld_windows_tilemaps", "source": "src/battle_setup.c:Task_BattleStart", "status": "metadata_only"},
		{
			"op": "set_main_callback",
			"callback": "CB2_InitBattle",
			"source": "src/battle_setup.c:Task_BattleStart",
			"status": "battle_scene_first_slice_not_source_equivalent",
			"unsupported_reason": "battle_scene_not_source_equivalent",
		},
		{"op": "restart_wild_encounter_immunity_steps", "source": "src/battle_setup.c:Task_BattleStart"},
		{"op": "clear_poison_step_counter", "var": "VAR_POISON_STEP_COUNTER", "source": "src/battle_setup.c:Task_BattleStart"},
	]


func _player_party_for_trainer_battle(request: Dictionary) -> Dictionary:
	var party := _current_player_party()
	var battle_party := _current_player_battle_party()
	if not battle_party.is_empty():
		return {
			"status": "existing_party",
			"party": party,
			"battle_party": battle_party,
			"debug_fallback_created": false,
		}
	if not bool(request.get("debug_allow_empty_party_fallback", false)):
		return {
			"status": "unsupported_empty_player_party",
			"party": [],
			"battle_party": [],
			"debug_fallback_created": false,
			"source": "src/battle_setup.c:BattleSetup_StartTrainerBattle",
			"unsupported": [{
				"code": "empty_player_party_no_debug_fallback",
				"source": "src/battle_setup.c:BattleSetup_StartTrainerBattle",
				"detail": "Source trainer battles require a usable player party. Only the Godot debug fixture may request a temporary Torchic fallback.",
			}],
		}
	if _party_runtime == null or not _party_runtime.has_method("create_party_mon"):
		return {
			"status": "error",
			"error": "missing_party_runtime",
			"detail": "PartyRuntime is required to create the debug Torchic fallback.",
			"source": "Godot debug trainer battle fixture",
		}

	var torchic = _party_runtime.create_party_mon("SPECIES_TORCHIC", 5, {
		"nickname": "Debug Torchic",
		"moves": ["MOVE_SCRATCH", "MOVE_EMBER"],
		"debug_only": true,
		"met_location": String(request.get("map", _current_map_id())),
	})
	if typeof(torchic) != TYPE_DICTIONARY or String(torchic.get("status", "")) != "ok":
		return torchic if typeof(torchic) == TYPE_DICTIONARY else {
			"status": "error",
			"error": "debug_torchic_create_failed",
	}
	torchic["debug_only"] = true
	torchic["debug_source"] = "debug trainer battle vertical slice fallback"
	var resolved_party := [torchic]
	var resolved_battle_party := resolved_party
	if _party_runtime.has_method("build_battle_party"):
		var built = _party_runtime.build_battle_party(resolved_party)
		if typeof(built) == TYPE_ARRAY and not built.is_empty():
			resolved_battle_party = built
	return {
		"status": "debug_fallback_created",
		"party": resolved_party,
		"battle_party": resolved_battle_party,
		"debug_fallback_created": true,
		"temporary": true,
		"species": "SPECIES_TORCHIC",
		"level": 5,
		"unsupported": [{
			"code": "debug_only_temporary_player_party",
			"source": "Godot-only debug fixture overlay",
			"detail": "A Lv5 Torchic is created for this battle request only because the starter flow is not implemented. It is not a source trainerbattle behavior.",
		}],
	}


func _increment_trainer_battle_stats() -> Dictionary:
	var increments := [
		_increment_game_stat_from("GAME_STAT_TOTAL_BATTLES", "src/battle_setup.c:DoTrainerBattle"),
		_increment_game_stat_from("GAME_STAT_TRAINER_BATTLES", "src/battle_setup.c:DoTrainerBattle"),
	]
	var all_incremented := true
	for entry in increments:
		if String(entry.get("status", "")) != "incremented":
			all_incremented = false
			break
	return {
		"status": "incremented" if all_incremented else "partial",
		"increments": increments,
		"source": "src/battle_setup.c:DoTrainerBattle",
	}


func _trainer_battle_start_unsupported() -> Array:
	return [{
		"code": "trainer_script_approach_intro_not_executed",
		"source": "data/scripts/trainer_battle.inc; src/scrcmd.c:ScrCmd_trainerbattle",
		"detail": "The debug NPC enters through a Godot-only request and does not execute source trainer approach, reveal movement, intro text, trainer flag checks, or dotrainerbattle script flow yet.",
	}, {
		"code": "trainer_battle_transition_visual_stub",
		"source": "src/battle_transition.c:BattleTransition_StartOnField",
		"detail": "The sequence records the selected trainer transition and plays the generic first-pass overlay. Exact source graphics, task timing, palette effects, screen effects, BGM, trainer intro text, and mugshot/team variants are not source-equivalent yet.",
	}, {
		"code": "battle_scene_not_source_equivalent",
		"source": "src/battle_main.c:CB2_InitBattle",
		"detail": "The handoff opens a debug BattleScene, not the source battle scene. Source tilemaps, windows, text printer timing, battler/healthbox sprites, audio, callbacks, controller command queues, trainer AI, rewards, EXP, party switching, and post-battle scripts remain future work.",
	}]


func _increment_standard_wild_battle_stats() -> Dictionary:
	var increments := [
		_increment_game_stat_from("GAME_STAT_TOTAL_BATTLES", "src/battle_setup.c:DoStandardWildBattle"),
		_increment_game_stat_from("GAME_STAT_WILD_BATTLES", "src/battle_setup.c:DoStandardWildBattle"),
	]
	var all_incremented := true
	for entry in increments:
		if String(entry.get("status", "")) != "incremented":
			all_incremented = false
			break
	return {
		"status": "incremented" if all_incremented else "partial",
		"increments": increments,
		"daily_wild_battles": {
			"status": "future",
			"source": "src/battle_setup.c:IncrementDailyWildBattles",
		},
		"gym_leader_rematch": {
			"status": "future",
			"source": "src/battle_setup.c:TryUpdateGymLeaderRematchFromWild",
			"trigger_rule": "GAME_STAT_WILD_BATTLES % 60 == 0",
		},
	}


func _standard_wild_battle_start_unsupported() -> Array:
	return [{
		"code": "battle_transition_visual_stub",
		"source": "src/battle_transition.c:BattleTransition_StartOnField",
		"detail": "The sequence records the selected transition and plays only a generic first-pass overlay stub; exact transition graphics, task timing, Mirage Tower blend cleanup, and palette/screen effects remain future presentation work.",
	}, {
		"code": "battle_scene_handoff_pending",
		"source": "src/battle_setup.c:Task_BattleStart -> CB2_InitBattle",
		"detail": "The sequence records the SetMainCallback2(CB2_InitBattle) handoff but does not switch to a real battle scene yet.",
	}, {
		"code": "field_freeze_audio_cleanup_metadata_only",
		"source": "src/battle_setup.c:DoStandardWildBattle/Task_BattleStart",
		"detail": "Object-event freeze, StopPlayerAvatar, BGM playback, follower preparation, window/tilemap cleanup, and poison-step reset are recorded as source-ordered metadata until those presentation/runtime systems exist.",
	}]


func _encounter_result_reason(result: Dictionary) -> String:
	var reason := String(result.get("reason", ""))
	if not reason.is_empty():
		return reason
	var error := String(result.get("error", ""))
	if not error.is_empty():
		return error
	return String(result.get("status", "no_encounter"))


func _wild_encounters_disabled_flag() -> String:
	if _game_state == null or not _game_state.has_method("is_flag_set"):
		return ""
	for flag_name in NO_ENCOUNTER_FLAGS.keys():
		if bool(_game_state.is_flag_set(String(flag_name))):
			return String(flag_name)
	return ""


func _standard_wild_dispatch_unsupported() -> Array:
	return [{
		"code": "step_count_scripts_before_encounter_incomplete",
		"source": "src/field_control_avatar.c:TryStartStepBasedScript",
		"detail": "Coordinate events, current-cell generated warps, first-pass misc walking script requests, and Repel/Lure counter decrement now live in the player-step dispatcher; fuller step-count scripts, Repel presentation, and DexNav step search remain future traced work.",
	}, {
		"code": "walk_into_signpost_and_arrow_warp_order_not_integrated",
		"source": "src/field_control_avatar.c:ProcessPlayerFieldInput",
		"detail": "Walk-into-signpost checks, arrow warps, and front-cell door warp ordering need a fuller field-input loop; blocked front-cell door warp remains handled by the current Godot movement-blocked path.",
	}, {
		"code": "wild_battle_presentation_not_started",
		"source": "src/wild_encounter.c:StandardWildEncounter -> src/battle_setup.c",
		"detail": "This dispatch now creates a first-pass source-backed wild battle state and battle-start sequence request when BattleEngine is available, but exact object freezing, transition graphics/timing, audio, and battle scene presentation remain future traced work.",
	}]


func _append_direct_preview_output(lines: PackedStringArray, script: String) -> void:
	var preview := _get_direct_script_preview(script)
	if preview.is_empty():
		lines.append("Preview: script data unavailable")
		return

	var status := String(preview.get("status", ""))
	if status == "no_preview_message":
		lines.append("Preview: no msgbox/message found")
		return
	if status == "missing_text":
		lines.append("Preview: text label missing")
		lines.append("Text label: %s" % String(preview.get("text_label", "")))
		return

	lines.append("Text label: %s" % String(preview.get("text_label", "")))
	lines.append("Mode: %s" % String(preview.get("mode", "")))
	lines.append("")
	lines.append(String(preview.get("text", "")))


func _get_script_record(script: String) -> Dictionary:
	var scripts = _script_data.get("scripts", {})
	if typeof(scripts) != TYPE_DICTIONARY:
		return {}
	var record = scripts.get(script, {})
	return record if typeof(record) == TYPE_DICTIONARY else {}


func _map_script_labels_for_type(script_type: String) -> Array:
	var labels := []
	var scripts = _script_data.get("scripts", {})
	if typeof(scripts) != TYPE_DICTIONARY:
		return labels

	for script_key in scripts.keys():
		var record = scripts.get(script_key, {})
		if typeof(record) != TYPE_DICTIONARY:
			continue
		if String(record.get("kind", "")) != "map_script_table":
			continue
		var instructions = record.get("instructions", [])
		if typeof(instructions) != TYPE_ARRAY:
			continue
		for instruction in instructions:
			if typeof(instruction) != TYPE_DICTIONARY:
				continue
			if String(instruction.get("op", "")) != "map_script":
				continue
			var args = instruction.get("args", [])
			if typeof(args) != TYPE_ARRAY or args.size() < 2:
				continue
			if String(args[0]) != script_type:
				continue
			var label := String(args[1])
			if not label.is_empty() and label != "0x0":
				labels.append(label)
			return labels
	return labels


func _map_script_source_function(script_type: String) -> String:
	if script_type == MAP_SCRIPT_ON_LOAD:
		return "RunOnLoadMapScript"
	if script_type == MAP_SCRIPT_ON_TRANSITION:
		return "RunOnTransitionMapScript"
	if script_type == MAP_SCRIPT_ON_FRAME_TABLE:
		return "TryRunOnFrameMapScript"
	return "MapHeaderRunScriptType"


func _map_script_source_trace(script_type: String) -> Array:
	var trace := MAP_SCRIPT_SOURCE_TRACE.duplicate()
	if script_type == MAP_SCRIPT_ON_LOAD:
		trace.append("src/fieldmap.c:InitMap/InitMapFromSavedGame")
		trace.append("src/script.c:RunOnLoadMapScript")
	elif script_type == MAP_SCRIPT_ON_TRANSITION:
		trace.append("src/overworld.c:LoadMapFromWarp/LoadMapFromCameraTransition")
		trace.append("src/script.c:RunOnTransitionMapScript")
	elif script_type == MAP_SCRIPT_ON_FRAME_TABLE:
		trace.append("src/field_control_avatar.c:ProcessPlayerFieldInput")
		trace.append("src/script.c:TryRunOnFrameMapScript/MapHeaderCheckScriptTable")
		trace.append("src/event_data.c:VarGet")
		trace.append("asm/macros/map.inc:map_script_2")
	return trace


func _map_script_table_value(token: String) -> Dictionary:
	var value := token.strip_edges()
	if value.begins_with("VAR_"):
		return {
			"resolved": true,
			"value": _get_game_var(value),
			"source": "src/event_data.c:VarGet/GameState",
		}

	var constant := _map_script_constant_value(value)
	if bool(constant.get("resolved", false)):
		return constant

	if value.is_valid_int():
		return {
			"resolved": true,
			"value": int(value),
			"source": "src/event_data.c:VarGet literal passthrough",
		}
	return {
		"resolved": false,
		"value": int(value),
		"source": "unresolved_token_int_fallback",
	}


func _map_script_constant_value(value: String) -> Dictionary:
	match value:
		"MALE":
			return {"resolved": true, "value": 0, "source": "constant:MALE"}
		"FEMALE":
			return {"resolved": true, "value": 1, "source": "constant:FEMALE"}
		"TRUE", "YES":
			return {"resolved": true, "value": 1, "source": "constant:%s" % value}
		"FALSE", "NO":
			return {"resolved": true, "value": 0, "source": "constant:%s" % value}
		"WARP_ID_NONE":
			return {"resolved": true, "value": WARP_ID_NONE_VALUE, "source": "constant:WARP_ID_NONE"}
		"LOCALID_NONE":
			return {"resolved": true, "value": LOCALID_NONE_VALUE, "source": "include/constants/event_objects.h"}
		"LOCALID_CAMERA":
			return {"resolved": true, "value": LOCALID_CAMERA_VALUE, "source": "include/constants/event_objects.h"}
		"LOCALID_FOLLOWING_POKEMON":
			return {"resolved": true, "value": LOCALID_FOLLOWING_POKEMON_VALUE, "source": "include/constants/event_objects.h"}
		"LOCALID_PLAYER":
			return {"resolved": true, "value": LOCALID_PLAYER_VALUE, "source": "include/constants/event_objects.h"}

	if value.begins_with("LOCALID_"):
		return _map_object_local_id_value(value)
	return {"resolved": false, "value": 0, "source": ""}


func _map_object_local_id_value(local_id: String) -> Dictionary:
	if _map_runtime != null and _map_runtime.has_method("get_object_event_by_local_id"):
		var object_event = _map_runtime.get_object_event_by_local_id(local_id, true)
		if typeof(object_event) == TYPE_DICTIONARY and not object_event.is_empty():
			return {
				"resolved": true,
				"value": int(object_event.get("index", -1)) + 1,
				"source": "tools/mapjson/mapjson.cpp local_id i+1",
			}

	var map_data := _current_map_data_for_local_ids()
	var events = map_data.get("events", {})
	var object_events = events.get("object_events", []) if typeof(events) == TYPE_DICTIONARY else []
	if typeof(object_events) == TYPE_ARRAY:
		for index in range(object_events.size()):
			var object_event = object_events[index]
			if typeof(object_event) == TYPE_DICTIONARY and String(object_event.get("local_id", "")) == local_id:
				return {
					"resolved": true,
					"value": index + 1,
					"source": "tools/mapjson/mapjson.cpp local_id i+1",
				}
	return {
		"resolved": false,
		"value": 0,
		"source": "unresolved_local_id",
	}


func _current_map_data_for_local_ids() -> Dictionary:
	if _data_registry == null:
		return {}
	var map_id := _current_map_id()
	if not map_id.is_empty() and _data_registry.has_method("get_map_data"):
		var map_data = _data_registry.get_map_data(map_id)
		if typeof(map_data) == TYPE_DICTIONARY and not map_data.is_empty():
			return map_data
	if _data_registry.has_method("get_start_map_data"):
		var start_map_data = _data_registry.get_start_map_data()
		return start_map_data if typeof(start_map_data) == TYPE_DICTIONARY else {}
	return {}


func _get_game_var(var_name: String) -> int:
	if _game_state != null and _game_state.has_method("get_var"):
		return int(_game_state.get_var(var_name, 0))
	return 0


func _script_label_has_no_effect(label: String) -> bool:
	var script_label := label.strip_edges()
	return script_label.is_empty() or script_label == "0x0" or script_label == "NULL"


func _template_position_targets_from_runtime_summary(runtime_summary: Dictionary) -> Array:
	var targets := []
	var object_summary = runtime_summary.get("object_effects", {})
	if typeof(object_summary) != TYPE_DICTIONARY:
		return targets

	var applied = object_summary.get("applied", [])
	if typeof(applied) != TYPE_ARRAY:
		return targets

	for entry in applied:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if String(entry.get("op", "")) != "setobjectxyperm":
			continue
		var target := String(entry.get("target", ""))
		if target.is_empty() or targets.has(target):
			continue
		targets.append(target)
	return targets


func _template_position_targets_from_map_script_summary(summary: Dictionary) -> Array:
	var targets := []
	var scripts = summary.get("scripts", [])
	if typeof(scripts) != TYPE_ARRAY:
		return targets

	for script in scripts:
		if typeof(script) != TYPE_DICTIONARY:
			continue
		var script_targets = script.get("template_object_targets", [])
		if typeof(script_targets) != TYPE_ARRAY:
			continue
		for target_value in script_targets:
			var target := String(target_value)
			if target.is_empty() or targets.has(target):
				continue
			targets.append(target)
	return targets


func _sync_map_load_object_templates(targets: Array) -> Dictionary:
	if _map_runtime == null or not _map_runtime.has_method("sync_object_events_to_templates_for_map_load"):
		return {
			"status": "missing_map_runtime",
			"targets": targets.duplicate(),
			"applied": [],
			"skipped": [],
			"unchanged": [],
			"object_events_changed": false,
		}
	return _map_runtime.sync_object_events_to_templates_for_map_load(targets)


func _map_load_script_status(transition_summary: Dictionary, load_summary: Dictionary) -> String:
	for summary in [transition_summary, load_summary]:
		var status := String(summary.get("status", "ok"))
		if status != "ok" and status != "missing_map_script":
			return status
	return "ok"


func _result_array_count(result: Dictionary, key: String) -> int:
	var value = result.get(key, [])
	return value.size() if typeof(value) == TYPE_ARRAY else 0


func _array_value(value) -> Array:
	return value if typeof(value) == TYPE_ARRAY else []


func _configure_script_vm_dependencies() -> void:
	if _script_vm == null:
		return
	if _game_state != null and _script_vm.has_method("configure_game_state"):
		_script_vm.configure_game_state(_game_state)
	if _data_registry != null and _script_vm.has_method("configure_data_registry"):
		_script_vm.configure_data_registry(_data_registry)


func _configure_encounter_engine_dependencies() -> void:
	if _encounter_engine == null:
		return
	if _game_state != null and _encounter_engine.has_method("configure_game_state"):
		_encounter_engine.configure_game_state(_game_state)
	if _data_registry != null and _encounter_engine.has_method("configure_registry"):
		_encounter_engine.configure_registry(_data_registry)


func _configure_battle_engine_dependencies() -> void:
	if _battle_engine == null:
		return
	if _data_registry != null and _battle_engine.has_method("configure_registry"):
		_battle_engine.configure_registry(_data_registry)


func _get_text_record(text_label: String) -> Dictionary:
	var texts = _script_data.get("texts", {})
	if typeof(texts) == TYPE_DICTIONARY:
		var record = texts.get(text_label, {})
		if typeof(record) == TYPE_DICTIONARY and not record.is_empty():
			return record

	if _data_registry != null and _data_registry.has_method("get_text_record"):
		var global_record = _data_registry.get_text_record(text_label, "global")
		if typeof(global_record) == TYPE_DICTIONARY:
			return global_record
	return {}


func _first_msgbox(script_record: Dictionary) -> Dictionary:
	var msgboxes = script_record.get("msgboxes", [])
	if typeof(msgboxes) != TYPE_ARRAY or msgboxes.is_empty():
		return {}
	var first = msgboxes[0]
	return first if typeof(first) == TYPE_DICTIONARY else {}
