#!/usr/bin/env python3
"""Smoke checks for the overworld event-object lock trace report."""

import argparse
import sys
from pathlib import Path

from export_overworld_event_object_lock_trace import build_export
from source_probe import load_config


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, help="JSON config with source and output roots.")
    parser.add_argument("--source", type=Path, help="pokeemerald-expansion source root.")
    args = parser.parse_args(argv)

    config = load_config(args.config)
    source_root = args.source or Path(config.get("source_root", ""))
    exported = build_export(source_root)
    stats = exported["stats"]

    _assert(exported["schema_version"] == 1, "unexpected schema version")
    _assert(exported["generated_by"].endswith("export_overworld_event_object_lock_trace.py"), "unexpected generator")
    _assert(stats["flow_count"] == 11, "unexpected flow count")
    _assert(stats["source_file_count"] == 28, "unexpected source file count")
    _assert(stats["missing_source_file_count"] == 0, "missing source files")
    _assert(stats["required_symbol_count"] == 75, "unexpected required source symbol count")
    _assert(stats["missing_symbol_count"] == 0, "missing source symbols: %s" % stats["missing_symbols"])
    _assert(stats["unsupported_count"] == 13, "unexpected unsupported count")
    _assert(stats["status_counts"].get("metadata_only", 0) == 8, "unexpected metadata-only flow count")
    _assert(stats["status_counts"].get("first_pass", 0) == 2, "unexpected first-pass flow count")
    _assert(stats["status_counts"].get("unsupported", 0) == 1, "unexpected unsupported flow count")
    _assert(stats["unsupported_status_counts"].get("unsupported", 0) == 10, "unexpected unsupported gap count")
    _assert(stats["unsupported_status_counts"].get("first_pass", 0) == 1, "unexpected first-pass gap count")
    _assert(stats["unsupported_status_counts"].get("metadata_only", 0) == 2, "unexpected metadata-only gap count")

    lockall_order = exported["lockall_order"]
    _assert(lockall_order[0].startswith("ScrCmd_lockall requests"), "unexpected lockall first step")
    _assert(any("Task_FreezePlayer" in step for step in lockall_order), "missing player freeze task")
    _assert(any("FLAG_SAFE_FOLLOWER_MOVEMENT" in step for step in lockall_order), "missing lockall follower rule")

    lock_selected_order = exported["lock_selected_order"]
    _assert(any("gSelectedObjectEvent" in step for step in lock_selected_order), "missing selected-object lock rule")
    _assert(any("singleMovementActive" in step for step in lock_selected_order), "missing selected movement wait")

    player_rules = exported["player_freeze_rules"]
    _assert(any("T_TILE_TRANSITION" in rule for rule in player_rules), "missing tile transition rule")
    _assert(any("StopPlayerAvatar" in rule for rule in player_rules), "missing StopPlayerAvatar rule")

    freeze_rules = exported["object_freeze_rules"]
    _assert(any("animPaused" in rule for rule in freeze_rules), "missing anim pause backup rule")
    _assert(any("FreezeObjectEventsExceptTwo" in rule for rule in freeze_rules), "missing two-trainer freeze rule")
    _assert(any("affineAnimPaused" in rule for rule in freeze_rules), "missing affine pause restore rule")

    release_order = exported["release_order"]
    _assert(release_order[0].startswith("ScrCmd_releaseall and ScrCmd_release"), "unexpected release first step")
    _assert(any("ScriptMovement_UnfreezeObjectEvents" in step for step in release_order), "missing script movement unfreeze")
    _assert(any("gMsgBoxIsCancelable" in step for step in release_order), "missing message cancel reset")

    faceplayer_order = exported["faceplayer_order"]
    _assert(any("DetermineFollowerNPCDirection" in step for step in faceplayer_order), "missing follower faceplayer branch")
    _assert(any("ObjectEventFaceOppositeDirection" in step for step in faceplayer_order), "missing ordinary faceplayer branch")
    _assert(any("GetOppositeDirection" in step for step in faceplayer_order), "missing opposite direction rule")

    selected_rules = exported["selected_object_rules"]
    _assert(selected_rules[0].startswith("gSelectedObjectEvent"), "unexpected selected-object first rule")
    _assert(any("OBJECT_EVENTS_COUNT" in rule for rule in selected_rules), "missing object-event sentinel")

    trainer_rules = exported["trainer_lock_rules"]
    _assert(any("ScrCmd_lockfortrainer" in rule for rule in trainer_rules), "missing lockfortrainer rule")
    _assert(any("MOVEMENT_ACTION_FACE_PLAYER" in rule for rule in trainer_rules), "missing trainer face-player movement")
    _assert(any("priorities 80 and 81" in rule for rule in trainer_rules), "missing two-trainer task priority")

    flows = {entry["id"]: entry for entry in exported["source_flows"]}
    for flow_id in [
        "script_command_lockall_entry",
        "script_command_lock_selected_entry",
        "player_freeze_wait_and_stop",
        "object_event_freeze_and_unfreeze",
        "release_and_unfreeze_order",
        "faceplayer_selected_object",
        "selected_object_event_resolution",
        "follower_lock_exceptions",
        "trainer_lockfortrainer_path",
        "native_script_wait_loop",
        "godot_current_event_object_lock_mapping",
    ]:
        _assert(flow_id in flows, "missing flow %s" % flow_id)
    _assert(flows["native_script_wait_loop"]["status"] == "unsupported", "native wait should remain unsupported")
    _assert(flows["selected_object_event_resolution"]["status"] == "first_pass", "selected object should be first pass")

    symbols = exported["required_symbols"]
    _assert(_has_occurrence(symbols, "ScrCmd_lock", "src/scrcmd.c"), "missing ScrCmd_lock occurrence")
    _assert(_has_occurrence(symbols, "ScrCmd_faceplayer", "src/scrcmd.c"), "missing ScrCmd_faceplayer occurrence")
    _assert(_has_occurrence(symbols, "FreezeObjects_WaitForPlayerAndSelected", "src/event_object_lock.c"), "missing selected freeze occurrence")
    _assert(_has_occurrence(symbols, "FreezeObjectEvent", "src/event_object_movement.c"), "missing FreezeObjectEvent occurrence")
    _assert(_has_occurrence(symbols, "PlayerFreeze", "src/field_player_avatar.c"), "missing PlayerFreeze occurrence")
    _assert(_has_occurrence(symbols, "GetCurrentApproachingTrainerObjectEventId", "src/trainer_see.c"), "missing trainer selector occurrence")
    _assert(_has_occurrence(symbols, "OBJ_EVENT_ID_FOLLOWER", "include/constants/event_objects.h"), "missing follower id occurrence")

    unsupported_codes = {entry["code"] for entry in exported["unsupported"]}
    for code in [
        "event_object_lock_native_task_pending",
        "selected_object_runtime_state_pending",
        "object_freeze_flags_pending",
        "sprite_anim_pause_restore_pending",
        "player_freeze_stop_pending",
        "faceplayer_held_movement_pending",
        "release_unfreeze_runtime_pending",
        "follower_lock_exception_pending",
        "lockfortrainer_trainer_see_pending",
        "native_wait_blocking_pending",
        "palette_affine_effects_godot_native",
        "audio_playback_pending",
    ]:
        _assert(code in unsupported_codes, "missing unsupported code %s" % code)

    policy = exported["visual_effect_policy"]
    _assert("Godot-native" in policy["palette_and_affine"], "missing Godot-native visual policy")
    _assert("metadata_only" in policy["audio"], "missing audio metadata-only policy")

    owners = exported["godot_trace_owners"]
    _assert("scripts/autoload/script_vm.gd" in owners["runtime"], "missing ScriptVM owner")
    _assert("scripts/overworld/object_event_spawner.gd" in owners["presentation"], "missing object sprite owner")
    _assert("tools/godot_smoke/script_vm_smoke.gd" in owners["tests"], "missing ScriptVM smoke owner")

    print("export_overworld_event_object_lock_trace_smoke: ok")
    return 0


def _has_occurrence(symbols, symbol, source_file):
    for occurrence in symbols.get(symbol, []):
        if occurrence.get("file") == source_file:
            return True
    return False


def _assert(condition, message):
    if not condition:
        raise AssertionError(message)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
