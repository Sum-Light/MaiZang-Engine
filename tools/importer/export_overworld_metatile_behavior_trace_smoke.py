#!/usr/bin/env python3
"""Smoke checks for the overworld metatile-behavior trace report."""

import argparse
import sys
from pathlib import Path

from export_overworld_metatile_behavior_trace import build_export
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
    _assert(exported["generated_by"].endswith("export_overworld_metatile_behavior_trace.py"), "unexpected generator")
    _assert(stats["flow_count"] == 12, "unexpected flow count")
    _assert(stats["source_file_count"] == 29, "unexpected source file count")
    _assert(stats["missing_source_file_count"] == 0, "missing source files")
    _assert(stats["required_symbol_count"] == 68, "unexpected required symbol count")
    _assert(stats["missing_symbol_count"] == 0, "missing source symbols: %s" % stats["missing_symbols"])
    _assert(stats["unsupported_count"] == 11, "unexpected unsupported count")
    _assert(stats["status_counts"].get("first_pass", 0) == 4, "unexpected first-pass flow count")
    _assert(stats["status_counts"].get("unsupported", 0) == 4, "unexpected unsupported flow count")
    _assert(stats["status_counts"].get("metadata_only", 0) == 4, "unexpected metadata-only flow count")
    _assert(stats["unsupported_status_counts"].get("unsupported", 0) == 6, "unexpected unsupported gap count")
    _assert(stats["unsupported_status_counts"].get("metadata_only", 0) == 5, "unexpected metadata-only gap count")

    _assert(stats["metatile_behavior_constant_count"] == 240, "unexpected metatile behavior count")
    _assert(stats["num_metatile_behaviors_value"] == 240, "unexpected NUM_METATILE_BEHAVIORS value")
    _assert(stats["last_metatile_behavior_id"] == 239, "unexpected last behavior id")
    _assert(stats["explicit_tile_bit_attribute_count"] == 129, "unexpected tile bit attribute count")
    _assert(stats["encounter_flag_behavior_count"] == 15, "unexpected encounter flag count")
    _assert(stats["surfable_flag_behavior_count"] == 18, "unexpected surfable flag count")
    _assert(stats["unused_hint_behavior_count"] == 128, "unexpected unused hint count")
    _assert(stats["metatile_behavior_function_count"] == 194, "unexpected helper definition count")
    _assert(stats["declared_function_count"] == 188, "unexpected declared function count")
    _assert(stats["unprototyped_function_count"] == 6, "unexpected unprototyped function count")
    _assert(stats["external_helper_definition_count"] == 1, "unexpected external helper count")
    _assert(stats["called_helper_count"] == 159, "unexpected called helper count")
    _assert(stats["call_site_file_count"] == 24, "unexpected call-site file count")
    _assert(stats["called_but_not_defined_in_trace_count"] == 0, "unexpected missing helper definitions")

    constants = {entry["name"]: entry["id"] for entry in exported["metatile_behavior_constants"]["constants"]}
    _assert(constants["MB_NORMAL"] == 0, "MB_NORMAL should be 0")
    _assert(constants["MB_ROCK_CLIMB"] == 239, "MB_ROCK_CLIMB should be last concrete behavior")
    _assert(exported["metatile_behavior_constants"]["mb_invalid_expr"] == "UCHAR_MAX", "MB_INVALID expression mismatch")

    attrs = exported["tile_bit_attributes"]
    _assert("MB_TALL_GRASS" in attrs["encounter_behaviors"], "missing tall grass encounter flag")
    _assert("MB_CAVE" in attrs["encounter_behaviors"], "missing cave encounter flag")
    _assert("MB_OCEAN_WATER" in attrs["surfable_behaviors"], "missing ocean surfable flag")
    _assert("MB_WATER_DOOR" in attrs["surfable_behaviors"], "missing water-door surfable flag")

    funcs = {entry["function"]: entry for entry in exported["helper_functions"]}
    forced = funcs["MetatileBehavior_IsForcedMovementTile"]
    _assert(
        {"variable": "metatileBehavior", "from": "MB_WALK_EAST", "to": "MB_TRICK_HOUSE_PUZZLE_8_FLOOR"} in forced["range_checks"],
        "missing walk/slide forced-movement range",
    )
    _assert(
        {"variable": "metatileBehavior", "from": "MB_EASTWARD_CURRENT", "to": "MB_SOUTHWARD_CURRENT"} in forced["range_checks"],
        "missing water-current forced-movement range",
    )
    _assert("MB_SECRET_BASE_SPIN_MAT" in forced["referenced_metatile_behaviors"], "missing secret-base spin mat")
    _assert("MB_WATERFALL" in forced["referenced_metatile_behaviors"], "missing waterfall forced movement")

    bridge = funcs["MetatileBehavior_GetBridgeType"]
    _assert(
        {"variable": "metatileBehavior", "from": "MB_BRIDGE_OVER_OCEAN", "to": "MB_BRIDGE_OVER_POND_HIGH"} in bridge["range_checks"],
        "missing bridge type base range",
    )
    _assert(
        {"variable": "metatileBehavior", "from": "MB_BRIDGE_OVER_POND_MED_EDGE_1", "to": "MB_BRIDGE_OVER_POND_MED_EDGE_2"} in bridge["range_checks"],
        "missing pond-med bridge edge range",
    )
    _assert(
        {"variable": "metatileBehavior", "from": "MB_BRIDGE_OVER_POND_HIGH_EDGE_1", "to": "MB_BRIDGE_OVER_POND_HIGH_EDGE_2"} in bridge["range_checks"],
        "missing pond-high bridge edge range",
    )

    unable = funcs["MetatileBehavior_IsUnableToEmerge"]
    _assert("BUGFIX" in unable["preprocessor_gates"], "missing BUGFIX branch metadata")
    _assert("MB_WATER_DOOR" in unable["referenced_metatile_behaviors"], "missing BUGFIX water-door no-emerge metadata")

    tv = funcs["MetatileBehavior_IsPlayerFacingTVScreen"]
    _assert(tv["direction_gates"] == ["DIR_NORTH"], "TV interaction should gate on DIR_NORTH")
    east_block = funcs["MetatileBehavior_IsEastBlocked"]
    _assert("MB_SECRET_BASE_BREAKABLE_DOOR" in east_block["referenced_metatile_behaviors"], "missing breakable-door east block")
    unref_arrow = funcs["Unref_MetatileBehavior_IsArrowWarp"]
    _assert("MetatileBehavior_IsNorthArrowWarp" in unref_arrow["called_helpers"], "missing unref arrow helper composition")

    external = {entry["function"]: entry for entry in exported["external_helper_functions"]}
    seafoam = external["MetatileBehavior_IsSurfableInSeafoamIslands"]
    _assert(seafoam["source_file"] == "src/overworld.c", "Seafoam helper source mismatch")
    _assert("MetatileBehavior_IsSurfableWaterOrUnderwater" in seafoam["called_helpers"], "Seafoam helper should call surfable helper")
    _assert(stats["external_called_helpers"] == ["MetatileBehavior_IsSurfableInSeafoamIslands"], "unexpected external called helpers")

    call_files = {entry["file"]: entry for entry in exported["call_sites"]["files"]}
    _assert(call_files["src/field_control_avatar.c"]["call_count"] == 99, "field_control_avatar call count mismatch")
    _assert(call_files["src/event_object_movement.c"]["unique_function_count"] == 26, "event_object_movement unique count mismatch")
    top_helpers = {entry["symbol"]: entry for entry in exported["call_sites"]["helpers"]}
    _assert(top_helpers["MetatileBehavior_IsSurfableWaterOrUnderwater"]["call_count"] == 12, "surfable helper call count mismatch")
    _assert(top_helpers["MetatileBehavior_IsLongGrass"]["call_count"] == 8, "long grass helper call count mismatch")

    flows = {entry["id"]: entry for entry in exported["source_flows"]}
    for flow_id in [
        "behavior_constants_and_import_ids",
        "tile_bit_attributes",
        "encounter_area_classification",
        "movement_collision_blocking",
        "forced_movement_tiles",
        "warps_doors_and_transitions",
        "terrain_field_effects",
        "interaction_sign_furniture",
        "bridge_and_elevation_helpers",
        "seafoam_external_helper",
        "godot_current_helper_table_gap",
        "visual_effect_and_audio_policy",
    ]:
        _assert(flow_id in flows, "missing flow %s" % flow_id)
    _assert(flows["movement_collision_blocking"]["status"] == "unsupported", "collision flow should be unsupported")
    _assert(flows["encounter_area_classification"]["status"] == "first_pass", "encounter flow should be first-pass")

    unsupported_codes = {entry["code"] for entry in exported["unsupported"]}
    for code in [
        "metatile_behavior_runtime_table_pending",
        "directional_blocking_runtime_pending",
        "forced_movement_runtime_pending",
        "terrain_field_effect_runtime_pending",
        "interaction_helper_table_pending",
        "bridge_elevation_runtime_pending",
        "bugfix_branch_metadata_only",
        "seafoam_external_helper_split_metadata",
        "palette_affine_effects_godot_native",
        "gba_runtime_limits_not_recreated",
        "audio_playback_metadata_only",
    ]:
        _assert(code in unsupported_codes, "missing unsupported code %s" % code)

    godot_current = exported["godot_current"]
    _assert(godot_current["generated_tileset_record_count"] == 4, "unexpected generated tileset count")
    _assert(godot_current["generated_metatile_entry_count"] == 2728, "unexpected generated metatile entry count")
    _assert(godot_current["declared_behavior_name_count"] == 240, "unexpected declared behavior names")
    _assert(godot_current["used_behavior_name_count"] == 46, "unexpected used behavior name count")
    _assert(godot_current["runtime_status"] == "first_pass_behavior_ids_names_only", "unexpected Godot runtime status")

    policy = exported["visual_effect_policy"]
    _assert("Godot-native" in policy["palette_and_affine"], "missing Godot-native visual policy")
    _assert("metadata_only" in policy["audio"], "missing audio metadata-only policy")

    print("export_overworld_metatile_behavior_trace_smoke: ok")
    return 0


def _assert(condition, message):
    if not condition:
        raise AssertionError(message)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
