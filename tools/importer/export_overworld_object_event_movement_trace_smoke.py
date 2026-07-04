#!/usr/bin/env python3
"""Smoke checks for the overworld object-event movement trace report."""

import argparse
import sys
from pathlib import Path

from export_overworld_object_event_movement_trace import build_export
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
    _assert(exported["generated_by"].endswith("export_overworld_object_event_movement_trace.py"), "unexpected generator")
    _assert(stats["flow_count"] == 14, "unexpected flow count")
    _assert(stats["source_file_count"] == 21, "unexpected source file count")
    _assert(stats["missing_source_file_count"] == 0, "missing source files")
    _assert(stats["required_symbol_count"] >= 150, "unexpectedly low required symbol count")
    _assert(stats["missing_symbol_count"] == 0, "missing source symbols: %s" % stats["missing_symbols"])
    _assert(stats["unsupported_count"] == 17, "unexpected unsupported count")
    _assert(stats["status_counts"].get("metadata_only", 0) == 9, "unexpected metadata-only flow count")
    _assert(stats["status_counts"].get("first_pass", 0) == 5, "unexpected first-pass flow count")
    _assert(stats["unsupported_status_counts"].get("unsupported", 0) == 13, "unexpected unsupported gap count")
    _assert(stats["unsupported_status_counts"].get("first_pass", 0) == 2, "unexpected first-pass gap count")
    _assert(stats["unsupported_status_counts"].get("metadata_only", 0) == 2, "unexpected metadata-only gap count")

    fields = exported["object_event_struct_fields"]
    _assert("heldMovementActive" in fields["runtime_state_fields"], "missing held movement field")
    _assert("initialCoords/currentCoords/previousCoords" in fields["runtime_state_fields"], "missing object coord fields")
    _assert("reflectionPaletteTag" in fields["graphics_info_fields"], "missing reflection palette metadata")
    _assert("tracks" in fields["graphics_info_fields"], "missing tracks metadata")

    frame_order = exported["object_event_frame_order"]
    _assert(frame_order[0] == "DoGroundEffects_OnSpawn", "unexpected first frame step")
    _assert(
        frame_order.index("if heldMovementActive -> ObjectEventExecHeldMovementAction")
        < frame_order.index("else if not frozen -> run movement type callback while it returns true"),
        "held movement must take priority over movement type callbacks",
    )
    _assert(frame_order[-1] == "ObjectEventUpdateSubpriority", "subpriority should be last in traced frame order")

    spawn = exported["spawn_lifecycle_order"]
    _assert(spawn[0].startswith("ResetObjectEvents"), "unexpected spawn reset first step")
    _assert(any("MAP_OFFSET" in step for step in spawn), "missing MAP_OFFSET spawn rule")
    _assert(any("sMovementTypeCallbacks" in step for step in spawn), "missing callback binding spawn rule")

    movement_groups = {entry["group"]: entry for entry in exported["movement_type_groups"]}
    for group_id in [
        "idle_and_facing",
        "wander_and_range",
        "player_copy_and_follow",
        "special_visibility_and_in_place",
    ]:
        _assert(group_id in movement_groups, "missing movement type group %s" % group_id)
    _assert(
        "MOVEMENT_TYPE_FOLLOW_PLAYER" in " ".join(movement_groups["player_copy_and_follow"]["entries"]),
        "missing follow-player movement group note",
    )

    action_groups = {entry["group"]: entry for entry in exported["movement_action_groups"]}
    for group_id in [
        "face_and_stationary",
        "tile_steps",
        "jumps_slides_and_currents",
        "visibility_affine_reflection_priority",
        "acro_emote_and_field_specials",
    ]:
        _assert(group_id in action_groups, "missing movement action group %s" % group_id)
    _assert(
        "MOVEMENT_ACTION_HIDE_REFLECTION/SHOW_REFLECTION" in action_groups["visibility_affine_reflection_priority"]["entries"],
        "missing reflection action group note",
    )

    held_rules = exported["held_movement_rules"]
    _assert(any("sActionFuncId" in rule for rule in held_rules), "missing sActionFuncId held movement rule")
    _assert(any("sActionIdToCopyableMovement" in rule for rule in held_rules), "missing copyable movement rule")

    script_order = exported["script_movement_task_order"]
    _assert(script_order[0].startswith("ScriptMovement_StartObjectMovementScript"), "unexpected script movement first step")
    _assert(any("waitmovement" in step for step in script_order), "missing waitmovement task rule")

    collision = exported["collision_pipeline"]
    _assert(collision[0].startswith("GetCollisionAtCoords"), "unexpected collision first step")
    _assert(any("GetVanillaCollision" in step for step in collision), "missing vanilla collision rule")
    _assert(any("sideways-stair" in step for step in collision), "missing sideways stair collision rule")
    _assert(any("previousCoords" in step for step in collision), "missing previous-coordinate occupancy rule")

    elevation = exported["elevation_and_depth_rules"]
    _assert(any("sElevationToPriority" in step for step in elevation), "missing priority table rule")
    _assert(any("SetObjectSubpriorityByElevation" in step for step in elevation), "missing subpriority rule")

    ground = exported["ground_effect_rules"]
    _assert(any("tracks" in step for step in ground), "missing track ground effect rule")
    _assert(any("SetUpReflection" in step for step in ground), "missing reflection setup rule")
    _assert(any("Godot should use native" in step for step in ground), "missing Godot-native reflection policy")

    flows = {entry["id"]: entry for entry in exported["source_flows"]}
    for flow_id in [
        "object_event_data_model",
        "object_event_graphics_asset_model",
        "spawn_template_lifecycle",
        "camera_spawn_despawn",
        "per_frame_update_order",
        "movement_type_callback_table",
        "held_movement_action_queue",
        "movement_action_timing_and_animation",
        "script_movement_task_bridge",
        "collision_and_occupancy_pipeline",
        "elevation_priority_subpriority",
        "ground_effects_tracks_shadows_reflections",
        "freeze_lock_visibility",
        "godot_current_object_event_mapping",
    ]:
        _assert(flow_id in flows, "missing flow %s" % flow_id)

    symbols = exported["required_symbols"]
    _assert(_has_occurrence(symbols, "ObjectEvent", "include/global.fieldmap.h"), "missing ObjectEvent struct occurrence")
    _assert(_has_occurrence(symbols, "sMovementTypeCallbacks", "src/event_object_movement.c"), "missing movement callback table occurrence")
    _assert(_has_occurrence(symbols, "gMovementActionFuncs", "src/data/object_events/movement_action_func_tables.h"), "missing movement action table occurrence")
    _assert(_has_occurrence(symbols, "GetCollisionAtCoords", "src/event_object_movement.c"), "missing collision occurrence")
    _assert(_has_occurrence(symbols, "ScriptMovement_TakeStep", "src/script_movement.c"), "missing script movement occurrence")
    _assert(_has_occurrence(symbols, "SetUpReflection", "src/field_effect_helpers.c"), "missing reflection helper occurrence")

    unsupported_codes = {entry["code"] for entry in exported["unsupported"]}
    for code in [
        "object_event_runtime_struct_pending",
        "movement_type_callbacks_pending",
        "held_movement_action_queue_pending",
        "source_collision_pipeline_pending",
        "elevation_subpriority_depth_pending",
        "ground_effect_tracks_pending",
        "shadows_reflections_pending",
        "palette_affine_effects_godot_native",
        "audio_playback_pending",
    ]:
        _assert(code in unsupported_codes, "missing unsupported code %s" % code)

    owners = exported["godot_trace_owners"]
    _assert("scripts/autoload/map_runtime.gd" in owners["runtime"], "missing MapRuntime owner")
    _assert("scripts/overworld/object_event_placeholder.gd" in owners["presentation"], "missing object placeholder owner")
    _assert("tools/godot_smoke/map_runtime_smoke.gd" in owners["tests"], "missing map runtime smoke owner")

    policy = exported["visual_effect_policy"]
    _assert("Godot-native" in policy["palette_and_affine"], "missing Godot-native visual policy")
    _assert("metadata_only" in policy["audio"], "missing audio metadata-only policy")

    print("export_overworld_object_event_movement_trace_smoke: ok")
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
