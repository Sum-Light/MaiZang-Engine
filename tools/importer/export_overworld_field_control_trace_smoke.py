#!/usr/bin/env python3
"""Smoke checks for the overworld field-control trace report."""

import argparse
import sys
from pathlib import Path

from export_overworld_field_control_trace import build_export
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
    _assert(exported["generated_by"].endswith("export_overworld_field_control_trace.py"), "unexpected generator")
    _assert(stats["flow_count"] == 12, "unexpected flow count")
    _assert(stats["source_file_count"] == 32, "unexpected source file count")
    _assert(stats["missing_source_file_count"] == 0, "missing source files")
    _assert(stats["required_symbol_count"] == 76, "unexpected source symbol count")
    _assert(stats["missing_symbol_count"] == 0, "missing source symbols: %s" % stats["missing_symbols"])
    _assert(stats["unsupported_count"] == 15, "unexpected unsupported count")
    _assert(stats["status_counts"].get("metadata_only", 0) == 6, "unexpected metadata-only flow count")
    _assert(stats["status_counts"].get("first_pass", 0) == 5, "unexpected first-pass flow count")
    _assert(stats["status_counts"].get("unsupported", 0) == 1, "unexpected unsupported flow count")

    flag_names = [entry["field"] for entry in exported["field_input_flags"]]
    for field_name in [
        "pressedAButton",
        "checkStandardWildEncounter",
        "heldDirection2",
        "tookStep",
        "pressedRButton",
        "input_field_1_2",
        "dpadDirection",
    ]:
        _assert(field_name in flag_names, "missing FieldInput flag %s" % field_name)

    process_order = exported["process_player_field_input_order"]
    _assert(
        process_order.index("CheckForTrainersWantingBattle")
        < process_order.index("TryRunOnFrameMapScript"),
        "trainer check should run before OnFrame",
    )
    _assert(
        process_order.index("pressed A -> TryStartInteractionScript")
        < process_order.index("heldDirection2 and same-facing dpad -> TryDoorWarp"),
        "A interaction should run before door warp",
    )
    _assert(
        process_order.index("pressed SELECT -> UseRegisteredKeyItemOnField")
        < process_order.index("pressed R -> TryStartDexNavSearch"),
        "registered item should run before R DexNav search",
    )

    step_order = exported["step_based_script_order"]
    for step in [
        "TryStartCoordEventScript",
        "TryStartWarpEventScript",
        "TryStartMiscWalkingScripts",
        "TryStartStepCountScript",
        "OnStep_DexNavSearch",
    ]:
        _assert(step in step_order, "missing step-based order entry %s" % step)
    _assert(
        step_order.index("TryStartCoordEventScript")
        < step_order.index("TryStartWarpEventScript"),
        "coord events should run before step warps",
    )

    interaction_order = exported["interaction_resolution_order"]
    expected_interaction_order = [
        "GetInteractedObjectEventScript",
        "GetInteractedBackgroundEventScript",
        "GetInteractedMetatileScript",
        "GetInteractedWaterScript",
    ]
    _assert(
        interaction_order[:4] == expected_interaction_order,
        "unexpected interaction resolution order",
    )

    door_rules = exported["door_arrow_rules"]
    _assert(
        "TryDoorWarp only runs for the front cell when direction == DIR_NORTH" in door_rules,
        "missing north-only door rule",
    )
    _assert(
        "directional stair warp clears bike transition flags to on-foot and inserts a 12-frame delay when needed" in door_rules,
        "missing directional stair bike delay rule",
    )

    flows = {entry["id"]: entry for entry in exported["source_flows"]}
    for flow_id in [
        "field_input_sampling",
        "process_player_field_input_priority",
        "step_based_script_order",
        "interaction_resolution_order",
        "object_and_background_interaction_rules",
        "metatile_water_dive_interaction_scripts",
        "coord_event_and_step_warp_rules",
        "door_and_arrow_warp_rules",
        "standard_wild_tail_order",
        "walk_into_signpost_and_cancel_rules",
        "debug_and_spin_evolution_tail",
        "godot_current_field_control_mapping",
    ]:
        _assert(flow_id in flows, "missing flow %s" % flow_id)
    _assert(
        "sWildEncounterImmunitySteps counts from 0 up to four steps before StandardWildEncounter can run"
        in flows["standard_wild_tail_order"]["critical_order"],
        "standard wild flow should record four-step immunity",
    )
    _assert(
        "debug menu plays SE_WIN_OPEN, freezes object events, then calls Debug_ShowMainMenu"
        in flows["debug_and_spin_evolution_tail"]["critical_order"],
        "debug flow should record source debug menu tail",
    )

    symbols = exported["required_symbols"]
    _assert(_has_occurrence(symbols, "ProcessPlayerFieldInput", "src/field_control_avatar.c"), "missing ProcessPlayerFieldInput occurrence")
    _assert(_has_occurrence(symbols, "TryDoorWarp", "src/field_control_avatar.c"), "missing TryDoorWarp occurrence")
    _assert(_has_occurrence(symbols, "StandardWildEncounter", "src/wild_encounter.c"), "missing StandardWildEncounter occurrence")
    _assert(_has_occurrence(symbols, "TryRunOnFrameMapScript", "src/script.c"), "missing TryRunOnFrameMapScript occurrence")
    _assert(_has_occurrence(symbols, "Debug_ShowMainMenu", "src/debug.c"), "missing Debug_ShowMainMenu occurrence")
    _assert(_has_occurrence(symbols, "CanTriggerSpinEvolution", "src/field_player_avatar.c"), "missing CanTriggerSpinEvolution occurrence")

    unsupported_codes = {entry["code"] for entry in exported["unsupported"]}
    for code in [
        "field_input_sampling_not_source_shaped",
        "interaction_resolution_order_pending",
        "arrow_warp_directional_stair_pending",
        "overworld_debug_toolkit_pending",
        "audio_playback_pending",
    ]:
        _assert(code in unsupported_codes, "missing unsupported code %s" % code)

    owners = exported["godot_trace_owners"]
    _assert("scripts/autoload/event_manager.gd" in owners["runtime"], "missing EventManager owner")
    _assert("scripts/overworld/player_controller.gd" in owners["presentation_input"], "missing PlayerController owner")
    _assert("wiki/overworld-parity-todo.md:Godot-only overworld debug toolkit" in owners["debug_lane"], "missing debug toolkit owner")

    print("export_overworld_field_control_trace_smoke: ok")
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
