#!/usr/bin/env python3
"""Smoke checks for the overworld field-door trace report."""

import argparse
import sys
from pathlib import Path

from export_overworld_field_door_trace import build_export
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
    _assert(exported["generated_by"].endswith("export_overworld_field_door_trace.py"), "unexpected generator")
    _assert(stats["flow_count"] == 10, "unexpected flow count")
    _assert(stats["source_file_count"] == 26, "unexpected source file count")
    _assert(stats["missing_source_file_count"] == 0, "missing source files")
    _assert(stats["required_symbol_count"] == 86, "unexpected required symbol count")
    _assert(stats["missing_symbol_count"] == 0, "missing source symbols: %s" % stats["missing_symbols"])
    _assert(stats["unsupported_count"] == 12, "unexpected unsupported count")
    _assert(stats["status_counts"].get("first_pass", 0) == 3, "unexpected first-pass flow count")
    _assert(stats["status_counts"].get("metadata_only", 0) == 6, "unexpected metadata-only flow count")
    _assert(stats["status_counts"].get("unsupported", 0) == 1, "unexpected unsupported flow count")
    _assert(stats["unsupported_status_counts"].get("first_pass", 0) == 1, "unexpected first-pass gap count")
    _assert(stats["unsupported_status_counts"].get("metadata_only", 0) == 4, "unexpected metadata-only gap count")
    _assert(stats["unsupported_status_counts"].get("unsupported", 0) == 7, "unexpected unsupported gap count")

    _assert(stats["frame_table_count"] == 8, "unexpected frame table count")
    _assert(stats["active_emerald_graphics_entry_count"] == 53, "unexpected Emerald door table count")
    _assert(stats["frlg_graphics_entry_count"] == 32, "unexpected FRLG door table count")
    _assert(stats["active_emerald_runtime_matchable_entry_count"] == 52, "unexpected matchable Emerald row count")
    _assert(stats["active_emerald_size_counts"].get("1") == 52, "unexpected size 1 Emerald row count")
    _assert(stats["active_emerald_size_counts"].get("2") == 1, "unexpected size 2 Emerald row count")
    _assert(stats["active_emerald_sound_counts"].get("DOOR_SOUND_NORMAL") == 25, "unexpected normal sound count")
    _assert(stats["active_emerald_sound_counts"].get("DOOR_SOUND_SLIDING") == 27, "unexpected sliding sound count")
    _assert(stats["active_emerald_sound_counts"].get("DOOR_SOUND_ARENA") == 1, "unexpected arena sound count")
    _assert(stats["tile_declaration_count"] == 85, "unexpected tile declaration count")
    _assert(stats["palette_declaration_count"] == 83, "unexpected palette declaration count")

    frame_tables = exported["door_frame_tables"]
    _assert(_offsets(frame_tables, "sDoorOpenAnimFrames") == [-1, 0, 0x100, 0x200, 0], "bad small open offsets")
    _assert(_offsets(frame_tables, "sDoorCloseAnimFrames") == [0x200, 0x100, 0, -1, 0], "bad small close offsets")
    _assert(_offsets(frame_tables, "sBigDoorOpenAnimFrames") == [-1, 0, 0x200, 0x400, 0], "bad big open offsets")
    _assert(_offsets(frame_tables, "sBigDoorCloseAnimFrames") == [0x400, 0x200, 0, -1, 0], "bad big close offsets")
    _assert(frame_tables["sDoorOpenAnimFrames"]["frames"][0]["closed_sentinel"], "missing open closed sentinel")
    _assert(frame_tables["sDoorCloseAnimFrames"]["frames"][3]["closed_sentinel"], "missing close closed sentinel")
    _assert(frame_tables["sDoorAnimFrames_OpenLargeFrlg"]["non_terminal_count"] == 4, "bad FRLG large open frame count")

    emerald_rows = exported["door_graphics_table"]["emerald"]
    _assert(emerald_rows[0]["metatile"] == "METATILE_General_Door", "unexpected first Emerald row")
    _assert(emerald_rows[0]["sound_effect"] == "SE_DOOR", "bad first Emerald sound")
    _assert(any(row["metatile"] == "0x3B0" and not row["runtime_matchable"] for row in emerald_rows), "missing unused NULL door row")
    _assert(
        any(row["metatile"] == "METATILE_BattleFrontier_Door_MultiCorridor" and row["size"] == 2 for row in emerald_rows),
        "missing Multi Corridor size 2 door row",
    )
    _assert(
        any(row["sound_type"] == "DOOR_SOUND_ARENA" and row["sound_effect"] == "SE_REPEL" for row in emerald_rows),
        "missing arena sound mapping",
    )

    sound_map = exported["sound_effect_map"]
    _assert(sound_map["DOOR_SOUND_NORMAL"] == "SE_DOOR", "bad normal sound effect")
    _assert(sound_map["DOOR_SOUND_SLIDING"] == "SE_SLIDING_DOOR", "bad sliding sound effect")
    _assert(sound_map["DOOR_SOUND_ARENA"] == "SE_REPEL", "bad arena sound effect")

    flows = {entry["id"]: entry for entry in exported["source_flows"]}
    for flow_id in [
        "door_graphics_table_lookup",
        "door_frame_tables_and_task_timing",
        "door_tiles_palette_and_layer_draw",
        "public_door_api_behavior_gate",
        "script_door_commands_and_wait",
        "door_sound_resolution",
        "door_warp_transition_usage",
        "battle_tower_multi_corridor_partner_door",
        "follower_door_interaction",
        "godot_current_door_mapping",
    ]:
        _assert(flow_id in flows, "missing flow %s" % flow_id)
    _assert(flows["battle_tower_multi_corridor_partner_door"]["status"] == "unsupported", "multi corridor should be unsupported")
    _assert(flows["door_warp_transition_usage"]["status"] == "first_pass", "door warp transition should be first-pass")
    _assert(
        "AnimateDoorFrame draws only when tCounter is zero" in flows["door_frame_tables_and_task_timing"]["critical_order"][-1],
        "missing AnimateDoorFrame timing rule",
    )

    symbols = exported["required_symbols"]
    _assert(_has_occurrence(symbols, "sDoorAnimGraphicsTable", "src/field_door.c"), "missing door graphics table occurrence")
    _assert(_has_occurrence(symbols, "Task_AnimateDoor", "src/field_door.c"), "missing door task occurrence")
    _assert(_has_occurrence(symbols, "ScrCmd_waitdooranim", "src/scrcmd.c"), "missing waitdooranim occurrence")
    _assert(_has_occurrence(symbols, "DrawDoorMetatileAt", "src/field_camera.c"), "missing door layer draw occurrence")
    _assert(_has_occurrence(symbols, "Task_DoDoorWarp", "src/field_screen_effect.c"), "missing door warp task occurrence")
    _assert(_has_occurrence(symbols, "FLAG_ENABLE_MULTI_CORRIDOR_DOOR", "include/constants/flags.h"), "missing multi corridor flag")

    unsupported_codes = {entry["code"] for entry in exported["unsupported"]}
    for code in [
        "full_door_graphics_table_import_pending",
        "door_layer_redraw_runtime_pending",
        "door_animation_task_runtime_pending",
        "script_waitdooranim_async_pending",
        "standalone_script_door_animation_pending",
        "big_door_size2_runtime_pending",
        "multi_corridor_partner_door_pending",
        "frlg_door_branch_metadata_only",
        "door_vram_copy_godot_native",
        "door_palette_slots_godot_native",
        "door_sound_audio_metadata_only",
        "follower_door_handoff_pending",
    ]:
        _assert(code in unsupported_codes, "missing unsupported code %s" % code)

    godot_current = exported["godot_current"]
    _assert(godot_current["generated_door_animation_count"] == 2, "unexpected current generated door animation count")
    _assert(
        any(row["metatile_label"] == "METATILE_Petalburg_Door_Littleroot" for row in godot_current["generated_door_animations"]),
        "missing Littleroot generated door",
    )

    owners = exported["godot_trace_owners"]
    _assert("tools/importer/export_tilesets.py" in owners["importer"], "missing tileset importer owner")
    _assert("scripts/autoload/map_runtime.gd" in owners["runtime"], "missing MapRuntime owner")
    _assert("scripts/overworld/debug_map_plane.gd" in owners["presentation"], "missing DebugMapPlane owner")

    policy = exported["visual_effect_policy"]
    _assert("Godot-native" in policy["palette_and_affine"], "missing Godot-native visual policy")
    _assert("metadata_only" in policy["audio"], "missing audio metadata-only policy")

    print("export_overworld_field_door_trace_smoke: ok")
    return 0


def _offsets(frame_tables, table_name):
    return [
        frame.get("normalized_offset") if not frame.get("closed_sentinel") else -1
        for frame in frame_tables[table_name]["frames"]
    ]


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
