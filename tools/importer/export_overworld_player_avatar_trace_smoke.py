#!/usr/bin/env python3
"""Smoke checks for the overworld player-avatar trace report."""

import argparse
import sys
from pathlib import Path

from export_overworld_player_avatar_trace import build_export
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
    _assert(exported["generated_by"].endswith("export_overworld_player_avatar_trace.py"), "unexpected generator")
    _assert(stats["flow_count"] == 12, "unexpected flow count")
    _assert(stats["source_file_count"] == 16, "unexpected source file count")
    _assert(stats["missing_source_file_count"] == 0, "missing source files")
    _assert(stats["required_symbol_count"] == 139, "unexpected required symbol count")
    _assert(stats["missing_symbol_count"] == 0, "missing source symbols: %s" % stats["missing_symbols"])
    _assert(stats["unsupported_count"] == 15, "unexpected unsupported count")
    _assert(stats["status_counts"].get("metadata_only", 0) == 8, "unexpected metadata-only flow count")
    _assert(stats["status_counts"].get("first_pass", 0) == 3, "unexpected first-pass flow count")
    _assert(stats["status_counts"].get("unsupported", 0) == 1, "unexpected unsupported flow count")

    states = {entry["state"]: entry for entry in exported["player_avatar_states"]}
    _assert(len(states) == 9, "unexpected avatar state count")
    _assert(states["PLAYER_AVATAR_STATE_NORMAL"]["male_graphics"] == "PLAYER_AVATAR_GFX_MALE_NORMAL", "unexpected normal male graphics")
    _assert(states["PLAYER_AVATAR_STATE_SURFING"]["state_flag"] == "PLAYER_AVATAR_FLAG_SURFING", "unexpected surfing flag")
    _assert(states["PLAYER_AVATAR_STATE_UNDERWATER"]["female_graphics"] == "PLAYER_AVATAR_GFX_FEMALE_UNDERWATER", "unexpected underwater female graphics")

    player_step_order = exported["player_step_order"]
    _assert(player_step_order[0] == "HideShowWarpArrow", "PlayerStep should update warp arrow first")
    _assert(
        player_step_order.index("DoPlayerAvatarTransition consumes pending transitionFlags")
        < player_step_order.index("TryDoMetatileBehaviorForcedMovement"),
        "avatar transition should run before forced movement",
    )
    _assert(
        player_step_order.index("TryDoMetatileBehaviorForcedMovement")
        < player_step_order.index("MovePlayerAvatarUsingKeypadInput"),
        "forced movement should run before keypad movement",
    )

    forced = exported["forced_movement_order"]
    _assert(forced[0].startswith("MetatileBehavior_IsTrickHouseSlipperyFloor"), "unexpected first forced movement")
    _assert("MetatileBehavior_IsMuddySlope -> ForcedMovement_MuddySlope" in forced, "missing muddy slope forced movement")
    _assert("MetatileBehavior_IsSpinDown -> ForcedMovement_SpinDown" in forced, "missing spin-down forced movement")

    non_bike = exported["non_bike_movement_order"]
    _assert(
        "TURN_DIRECTION -> WindUpSpinTimer(direction), PlayerTurnInPlace(direction)" in non_bike,
        "missing turn-in-place spin timer rule",
    )
    _assert(
        "successful running requires B held, FLAG_SYS_B_DASH, not underwater, running allowed, no follower door handoff, and no ORAS dowsing overlay" in non_bike,
        "missing running gate rule",
    )

    collision = exported["collision_pipeline"]
    _assert(
        "COLLISION_ELEVATION_MISMATCH can become COLLISION_STOP_SURFING through CanStopSurfing" in collision,
        "missing stop-surfing collision rule",
    )
    _assert(
        "COLLISION_NONE can become Acro Bike trick collisions for bumpy slopes and rails" in collision,
        "missing Acro collision rule",
    )

    transition_rules = exported["transition_rules"]
    _assert(
        "DoPlayerAvatarTransition scans transitionFlags bit-by-bit in PLAYER_AVATAR_STATE order" in transition_rules,
        "missing transition scan rule",
    )
    _assert(
        "Surfing transition sets surf graphics, masks state to surfing, starts FLDEFF_SURF_BLOB, and sets BOB_PLAYER_AND_MON" in transition_rules,
        "missing surf transition rule",
    )

    bike_rules = exported["bike_rules"]
    _assert(
        "GetPlayerSpeed returns Mach indexed speed, Acro faster speed, surfing/dash fast speed, or normal speed" in bike_rules,
        "missing player speed rule",
    )

    tile_rules = exported["tile_transition_rules"]
    _assert(
        "FieldGetPlayerInput consumes tileTransitionState and runningState to decide tookStep, wild checks, and button gates" in tile_rules,
        "missing field-input dependency rule",
    )

    flows = {entry["id"]: entry for entry in exported["source_flows"]}
    for flow_id in [
        "player_avatar_data_model",
        "player_step_main_loop_order",
        "forced_movement_table_order",
        "non_bike_input_state_machine",
        "collision_pipeline",
        "bike_dispatch_speed_and_music",
        "acro_bike_state_machine",
        "avatar_transition_graphics",
        "tile_transition_state",
        "movement_action_wrappers",
        "surf_underwater_and_special_avatar_modes",
        "godot_current_player_avatar_mapping",
    ]:
        _assert(flow_id in flows, "missing flow %s" % flow_id)

    symbols = exported["required_symbols"]
    _assert(_has_occurrence(symbols, "PlayerAvatar", "include/global.fieldmap.h"), "missing PlayerAvatar struct occurrence")
    _assert(_has_occurrence(symbols, "PlayerStep", "src/field_player_avatar.c"), "missing PlayerStep occurrence")
    _assert(_has_occurrence(symbols, "CheckForObjectEventCollision", "src/field_player_avatar.c"), "missing collision occurrence")
    _assert(_has_occurrence(symbols, "MovePlayerOnBike", "src/bike.c"), "missing bike dispatch occurrence")
    _assert(_has_occurrence(symbols, "GetPlayerSpeed", "src/bike.c"), "missing player speed occurrence")
    _assert(_has_occurrence(symbols, "GetCollisionAtCoords", "src/event_object_movement.c"), "missing object collision occurrence")

    unsupported_codes = {entry["code"] for entry in exported["unsupported"]}
    for code in [
        "player_avatar_state_struct_not_runtime_owned",
        "full_player_step_loop_pending",
        "forced_movement_state_machine_pending",
        "source_collision_pipeline_pending",
        "debug_avatar_switcher_pending",
        "palette_affine_effects_godot_native",
        "audio_playback_pending",
    ]:
        _assert(code in unsupported_codes, "missing unsupported code %s" % code)

    owners = exported["godot_trace_owners"]
    _assert("scripts/overworld/player_controller.gd" in owners["runtime"], "missing PlayerController owner")
    _assert("tools/godot_smoke/player_turn_input_smoke.gd" in owners["tests"], "missing player turn smoke owner")

    print("export_overworld_player_avatar_trace_smoke: ok")
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
