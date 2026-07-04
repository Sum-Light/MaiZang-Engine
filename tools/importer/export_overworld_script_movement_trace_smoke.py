#!/usr/bin/env python3
"""Smoke checks for the overworld script movement trace report."""

import argparse
import sys
from pathlib import Path

from export_overworld_script_movement_trace import build_export
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
    _assert(exported["generated_by"].endswith("export_overworld_script_movement_trace.py"), "unexpected generator")
    _assert(stats["flow_count"] == 12, "unexpected flow count")
    _assert(stats["source_file_count"] == 21, "unexpected source file count")
    _assert(stats["missing_source_file_count"] == 0, "missing source files")
    _assert(stats["required_symbol_count"] == 74, "unexpected required source symbol count")
    _assert(stats["missing_symbol_count"] == 0, "missing source symbols: %s" % stats["missing_symbols"])
    _assert(stats["unsupported_count"] == 13, "unexpected unsupported count")
    _assert(stats["movement_macro_count"] == 167, "unexpected movement macro count")
    _assert(stats["status_counts"].get("metadata_only", 0) == 8, "unexpected metadata-only flow count")
    _assert(stats["status_counts"].get("first_pass", 0) == 3, "unexpected first-pass flow count")
    _assert(stats["status_counts"].get("unsupported", 0) == 1, "unexpected unsupported flow count")
    _assert(stats["unsupported_status_counts"].get("unsupported", 0) == 10, "unexpected unsupported gap count")
    _assert(stats["unsupported_status_counts"].get("metadata_only", 0) == 2, "unexpected metadata-only gap count")

    layout_roles = {entry["role"] for entry in exported["task_data_layout"]}
    _assert("finished bitset" in layout_roles, "missing finished bitset layout")
    _assert("object-event id slots" in layout_roles, "missing object-event slot layout")
    _assert("movement script pointers" in layout_roles, "missing movement script pointer layout")

    apply_order = exported["scrcmd_applymovement_order"]
    _assert(apply_order[0].startswith("ScrCmd_applymovement reads a halfword target"), "unexpected applymovement first step")
    _assert(
        any("ClearObjectEventMovement" in step for step in apply_order),
        "missing follower/overworld-mon clear rule",
    )
    _assert(
        any("sMovingNpcId" in step for step in apply_order),
        "missing moving NPC target update",
    )

    target_rules = exported["target_resolution_rules"]
    _assert(
        any("waitmovement 0" in rule and "last moved object" in rule for rule in target_rules),
        "missing waitmovement 0 last-target rule",
    )
    _assert(
        any("object template index + 1" in rule for rule in target_rules),
        "missing generated local-id rule",
    )

    task_rules = exported["task_creation_and_add_rules"]
    _assert(
        any("priority 50" in rule for rule in task_rules),
        "missing task priority rule",
    )
    _assert(
        any("same object is already moving" in rule for rule in task_rules),
        "missing same-object replacement rule",
    )

    tick_order = exported["task_tick_order"]
    _assert(tick_order[0].startswith("ScriptMovement_MoveObjects runs once per task tick"), "unexpected tick first step")
    _assert(
        any("ObjectEventSetHeldMovement" in step for step in tick_order),
        "missing held movement queue step",
    )
    _assert(
        any("MOVEMENT_ACTION_STEP_END" in step for step in tick_order),
        "missing step-end completion rule",
    )

    wait_rules = exported["waitmovement_rules"]
    _assert(
        any("SetupNativeScript" in rule for rule in wait_rules),
        "missing native wait setup",
    )
    _assert(
        any("follower" in rule and "Pokeball" in rule for rule in wait_rules),
        "missing follower Pokeball wait rule",
    )

    simultaneous = exported["simultaneous_movement_rules"]
    _assert(
        any("progress concurrently" in rule for rule in simultaneous),
        "missing concurrent movement rule",
    )
    _assert(
        any("Script_waitmovementall" in rule for rule in simultaneous),
        "missing waitmovementall distinction",
    )

    _assert(
        _has_macro(exported["movement_macro_records"], "step_end", "MOVEMENT_ACTION_STEP_END"),
        "missing step_end movement macro",
    )
    _assert(
        _has_macro(exported["movement_macro_records"], "enter_pokeball", "MOVEMENT_ACTION_ENTER_POKEBALL"),
        "missing enter_pokeball movement macro",
    )

    flows = {entry["id"]: entry for entry in exported["source_flows"]}
    for flow_id in [
        "script_command_applymovement_entry",
        "script_command_applymovementat_entry",
        "movement_target_resolution",
        "movement_task_creation_and_slot_layout",
        "add_new_movement_replacement_rules",
        "per_tick_take_step_order",
        "movement_script_completion_and_freeze",
        "waitmovement_native_wait",
        "waitmovementat_and_waitmovementall",
        "simultaneous_movement_semantics",
        "follower_and_ow_mon_exceptions",
        "godot_current_script_movement_mapping",
    ]:
        _assert(flow_id in flows, "missing flow %s" % flow_id)
    _assert(
        flows["simultaneous_movement_semantics"]["status"] == "unsupported",
        "simultaneous movement should remain unsupported",
    )

    symbols = exported["required_symbols"]
    _assert(_has_occurrence(symbols, "ScrCmd_applymovement", "src/scrcmd.c"), "missing ScrCmd_applymovement occurrence")
    _assert(_has_occurrence(symbols, "ScrCmd_waitmovement", "src/scrcmd.c"), "missing ScrCmd_waitmovement occurrence")
    _assert(_has_occurrence(symbols, "ScriptMovement_TakeStep", "src/script_movement.c"), "missing ScriptMovement_TakeStep occurrence")
    _assert(_has_occurrence(symbols, "SetupNativeScript", "src/script.c"), "missing SetupNativeScript occurrence")
    _assert(_has_occurrence(symbols, "VarGet", "src/event_data.c"), "missing VarGet occurrence")
    _assert(_has_occurrence(symbols, "LOCALID_PLAYER", "include/constants/event_objects.h"), "missing LOCALID_PLAYER occurrence")

    unsupported_codes = {entry["code"] for entry in exported["unsupported"]}
    for code in [
        "script_movement_async_task_runtime_pending",
        "held_movement_queue_pending",
        "waitmovement_native_blocking_pending",
        "simultaneous_movement_timing_pending",
        "follower_pokeball_wait_pending",
        "palette_affine_effects_godot_native",
        "audio_playback_pending",
    ]:
        _assert(code in unsupported_codes, "missing unsupported code %s" % code)

    owners = exported["godot_trace_owners"]
    _assert("scripts/autoload/script_vm.gd" in owners["runtime"], "missing ScriptVM owner")
    _assert("scripts/autoload/map_runtime.gd" in owners["runtime"], "missing MapRuntime owner")
    _assert("tools/godot_smoke/script_vm_smoke.gd" in owners["tests"], "missing ScriptVM smoke owner")

    print("export_overworld_script_movement_trace_smoke: ok")
    return 0


def _has_occurrence(symbols, symbol, source_file):
    for occurrence in symbols.get(symbol, []):
        if occurrence.get("file") == source_file:
            return True
    return False


def _has_macro(records, macro, movement_action):
    for record in records:
        if record.get("macro") == macro and record.get("movement_action") == movement_action:
            return True
    return False


def _assert(condition, message):
    if not condition:
        raise AssertionError(message)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
