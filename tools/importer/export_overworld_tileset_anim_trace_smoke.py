#!/usr/bin/env python3
"""Smoke checks for the overworld tileset-animation trace report."""

import argparse
import sys
from pathlib import Path

from export_overworld_tileset_anim_trace import build_export
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
    _assert(exported["generated_by"].endswith("export_overworld_tileset_anim_trace.py"), "unexpected generator")
    _assert(stats["flow_count"] == 10, "unexpected flow count")
    _assert(stats["source_file_count"] == 19, "unexpected source file count")
    _assert(stats["missing_source_file_count"] == 0, "missing source files")
    _assert(stats["required_symbol_count"] == 135, "unexpected required symbol count")
    _assert(stats["missing_symbol_count"] == 0, "missing source symbols: %s" % stats["missing_symbols"])
    _assert(stats["unsupported_count"] == 9, "unexpected unsupported count")
    _assert(stats["status_counts"].get("metadata_only", 0) == 6, "unexpected metadata-only flow count")
    _assert(stats["status_counts"].get("unsupported", 0) == 3, "unexpected unsupported flow count")
    _assert(stats["status_counts"].get("first_pass", 0) == 1, "unexpected first-pass flow count")
    _assert(stats["unsupported_status_counts"].get("unsupported", 0) == 5, "unexpected unsupported gap count")
    _assert(stats["unsupported_status_counts"].get("metadata_only", 0) == 4, "unexpected metadata-only gap count")

    _assert(stats["init_function_count"] == 31, "unexpected init function count")
    _assert(stats["emerald_init_function_count"] == 25, "unexpected Emerald init count")
    _assert(stats["frlg_init_function_count"] == 6, "unexpected FRLG init count")
    _assert(stats["runtime_enabled_init_function_count"] == 26, "unexpected enabled init count")
    _assert(stats["null_callback_init_function_count"] == 5, "unexpected NULL callback init count")
    _assert(stats["tileset_callback_function_count"] == 27, "unexpected tileset callback count")
    _assert(stats["queue_function_count"] == 36, "unexpected queue function count")
    _assert(stats["append_call_count"] == 41, "unexpected append call count")
    _assert(stats["palette_function_count"] == 2, "unexpected palette function count")
    _assert(stats["frame_declaration_count"] == 174, "unexpected frame declaration count")
    _assert(stats["frame_source_bin_count"] == 182, "unexpected frame source bin count")
    _assert(stats["pointer_table_count"] == 40, "unexpected pointer table count")
    _assert(stats["active_emerald_header_count"] == 75, "unexpected Emerald header count")
    _assert(stats["active_emerald_header_callback_count"] == 25, "unexpected Emerald callback binding count")
    _assert(stats["frlg_header_count"] == 64, "unexpected FRLG header count")
    _assert(stats["frlg_header_callback_count"] == 6, "unexpected FRLG callback binding count")
    _assert(stats["header_callback_symbol_count_all_branches"] == 31, "unexpected callback symbol count")

    inits = {entry["function"]: entry for entry in exported["init_functions"]}
    _assert(inits["InitTilesetAnim_General"]["target"] == "primary", "General should initialize primary")
    _assert(inits["InitTilesetAnim_General"]["counter_max_expr"] == "256", "General max should be 256")
    _assert(inits["InitTilesetAnim_General"]["callback"] == "TilesetAnim_General", "General callback mismatch")
    _assert(inits["InitTilesetAnim_Petalburg"]["target"] == "secondary", "Petalburg should initialize secondary")
    _assert(inits["InitTilesetAnim_Petalburg"]["callback"] == "NULL", "Petalburg should clear callback")
    _assert(not inits["InitTilesetAnim_Petalburg"]["runtime_callback_enabled"], "Petalburg callback should be disabled")
    _assert(inits["InitTilesetAnim_Mauville"]["counter_init_expr"] == "sPrimaryTilesetAnimCounter", "Mauville counter sync mismatch")
    _assert(inits["InitTilesetAnim_BattleDome"]["callback"] == "TilesetAnim_BattleDome", "Battle Dome callback mismatch")
    _assert(inits["InitTilesetAnim_General_Frlg"]["branch"] == "frlg_metadata", "FRLG General branch mismatch")
    _assert(inits["InitTilesetAnim_General_Frlg"]["counter_max_expr"] == "640", "FRLG General max should be 640")

    callbacks = {entry["function"]: entry for entry in exported["tileset_callbacks"]}
    general_calls = callbacks["TilesetAnim_General"]["calls"]
    _assert(callbacks["TilesetAnim_General"]["call_count"] == 5, "General callback should queue 5 phases")
    _assert([call["timer_equals"] for call in general_calls] == [0, 1, 2, 3, 4], "General phase order mismatch")
    _assert(all(call["timer_modulus"] == 16 for call in general_calls), "General phases should use timer % 16")
    _assert(callbacks["TilesetAnim_Building"]["calls"][0]["timer_modulus"] == 8, "Building TV phase mismatch")
    _assert(callbacks["TilesetAnim_BattleDome"]["calls"][0]["function"] == "BlendAnimPalette_BattleDome_FloorLights", "Battle Dome should blend palette")

    queues = {entry["function"]: entry for entry in exported["queue_functions"]}
    _assert(_first_dest(queues, "QueueAnimTiles_General_Water") == "432", "General water destination mismatch")
    _assert(_first_size(queues, "QueueAnimTiles_General_Water") == "30 * TILE_SIZE_4BPP", "General water size mismatch")
    _assert(queues["QueueAnimTiles_Lavaridge_Steam"]["append_count"] == 2, "Lavaridge steam should append twice")
    _assert(
        queues["QueueAnimTiles_Lavaridge_Steam"]["append_calls"][1]["destination_tile_expr"] == "NUM_TILES_IN_PRIMARY + 292",
        "Lavaridge steam second destination mismatch",
    )
    _assert(_first_dest(queues, "QueueAnimTiles_Sootopolis_StormyWater") == "NUM_TILES_IN_PRIMARY + 240", "Sootopolis stormy destination mismatch")
    _assert(_first_size(queues, "QueueAnimTiles_Sootopolis_StormyWater") == "96 * TILE_SIZE_4BPP", "Sootopolis stormy size mismatch")
    _assert(_first_dest(queues, "QueueAnimTiles_BattlePyramid_Torch") == "NUM_TILES_IN_PRIMARY + 151", "Battle Pyramid torch destination mismatch")

    palette_functions = {entry["function"]: entry for entry in exported["palette_functions"]}
    _assert(palette_functions["BlendAnimPalette_BattleDome_FloorLights"]["switches_callback"], "Battle Dome blend should switch callback during battle intro")
    _assert(palette_functions["BlendAnimPalette_BattleDome_FloorLightsNoBlend"]["changes_counter_max"], "Battle Dome no-blend should change counter max")

    headers = exported["tileset_header_bindings"]
    active_callbacks = {row["tileset"]: row["callback"] for row in headers["active_emerald"] if row["has_callback"]}
    _assert(active_callbacks["gTileset_General"] == "InitTilesetAnim_General", "General header callback mismatch")
    _assert(active_callbacks["gTileset_Petalburg"] == "InitTilesetAnim_Petalburg", "Petalburg header callback mismatch")
    _assert(active_callbacks["gTileset_BattleDome"] == "InitTilesetAnim_BattleDome", "Battle Dome header callback mismatch")
    frlg_callbacks = {row["tileset"]: row["callback"] for row in headers["frlg_metadata"] if row["has_callback"]}
    _assert(frlg_callbacks["gTileset_General_Frlg"] == "InitTilesetAnim_General_Frlg", "FRLG General callback mismatch")
    _assert(frlg_callbacks["gTileset_CeladonCity"] == "InitTilesetAnim_CeladonCity", "FRLG Celadon callback mismatch")

    frames = {entry["symbol"]: entry for entry in exported["tileset_animation_frame_declarations"]}
    _assert(frames["gTilesetAnims_Sootopolis_StormyWater_Frame0"]["source_bin_count"] == 2, "Sootopolis stormy frame should have two source bins")
    _assert(frames["gTilesetAnims_General_Water_Frame0"]["source_bin_count"] == 1, "General water frame should have one source bin")

    flows = {entry["id"]: entry for entry in exported["source_flows"]}
    for flow_id in [
        "tileset_header_callback_binding",
        "init_primary_secondary_callbacks",
        "per_frame_counter_and_callback_order",
        "transfer_buffer_and_vblank_copy",
        "map_load_and_secondary_reload_hooks",
        "emerald_tile_copy_callbacks",
        "battle_dome_palette_animation",
        "frlg_tileset_animation_branch",
        "godot_current_tileset_animation_gap",
        "visual_effect_policy_for_godot",
    ]:
        _assert(flow_id in flows, "missing flow %s" % flow_id)
    _assert(flows["battle_dome_palette_animation"]["status"] == "unsupported", "Battle Dome palette flow should be unsupported")
    _assert(flows["godot_current_tileset_animation_gap"]["status"] == "first_pass", "Godot current gap should be first-pass")
    _assert(
        "UpdateTilesetAnimations clears the pending transfer buffer before incrementing both primary and secondary counters."
        in flows["per_frame_counter_and_callback_order"]["critical_order"],
        "missing counter reset rule",
    )

    symbols = exported["required_symbols"]
    _assert(_has_occurrence(symbols, "InitTilesetAnimations", "src/tileset_anims.c"), "missing InitTilesetAnimations occurrence")
    _assert(_has_occurrence(symbols, "TransferTilesetAnimsBuffer", "src/tileset_anims.c"), "missing transfer occurrence")
    _assert(_has_occurrence(symbols, "InitSecondaryTilesetAnimation", "src/overworld.c"), "missing overworld secondary init occurrence")
    _assert(_has_occurrence(symbols, "CopyMapTilesetsToVram", "src/fieldmap.c"), "missing fieldmap copy occurrence")
    _assert(_has_occurrence(symbols, "DmaCopy16", "include/gba/macro.h"), "missing DmaCopy16 macro")
    _assert(_has_occurrence(symbols, "BG_VRAM", "include/gba/defines.h"), "missing BG_VRAM define")
    _assert(_has_occurrence(symbols, "BlendPalette", "src/util.c"), "missing BlendPalette implementation")

    unsupported_codes = {entry["code"] for entry in exported["unsupported"]}
    for code in [
        "tileset_animation_runtime_pending",
        "animated_tile_atlas_import_pending",
        "tile_copy_region_renderer_pending",
        "primary_secondary_counter_runtime_pending",
        "battle_dome_palette_animation_pending",
        "frlg_tileset_animation_metadata_only",
        "gba_vram_dma_godot_native",
        "palette_bank_runtime_godot_native",
        "audio_playback_metadata_only",
    ]:
        _assert(code in unsupported_codes, "missing unsupported code %s" % code)

    godot_current = exported["godot_current"]
    _assert(godot_current["generated_tileset_animation_count"] == 0, "Godot should still have 0 generated tileset animations")
    _assert(godot_current["source_tileset_animation_callback_count"] == 31, "source callback coverage count mismatch")
    _assert(godot_current["tileset_animation_callback_coverage_percent"] == 0.0, "coverage percent mismatch")
    _assert(
        any(
            row["map"] == "LittlerootTown"
            and row["primary_tileset"] == "gTileset_General"
            and row["secondary_tileset"] == "gTileset_Petalburg"
            for row in godot_current["generated_tileset_records"]
        ),
        "missing Littleroot current tileset record",
    )

    policy = exported["visual_effect_policy"]
    _assert("Godot-native" in policy["palette_and_affine"], "missing Godot-native visual policy")
    _assert("metadata_only" in policy["audio"], "missing audio metadata-only policy")

    print("export_overworld_tileset_anim_trace_smoke: ok")
    return 0


def _first_dest(queues, function_name):
    return queues[function_name]["append_calls"][0]["destination_tile_expr"]


def _first_size(queues, function_name):
    return queues[function_name]["append_calls"][0]["size_expr"]


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
