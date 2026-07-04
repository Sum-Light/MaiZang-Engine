#!/usr/bin/env python3
"""Smoke checks for the overworld layer rules trace report."""

import argparse
import sys
from pathlib import Path

from export_overworld_layer_rules_trace import build_export
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
    _assert(exported["generated_by"].endswith("export_overworld_layer_rules_trace.py"), "unexpected generator")
    _assert(stats["flow_count"] == 10, "unexpected flow count")
    _assert(stats["source_file_count"] == 8, "unexpected source file count")
    _assert(stats["missing_source_file_count"] == 0, "missing source files")
    _assert(stats["required_symbol_count"] == 34, "unexpected source symbol count")
    _assert(stats["missing_symbol_count"] == 0, "missing source symbols")
    _assert(stats["unsupported_count"] == 7, "unexpected unsupported count")
    _assert(stats["status_counts"].get("ported", 0) == 2, "unexpected ported count")
    _assert(stats["status_counts"].get("metadata_only", 0) == 6, "unexpected metadata-only count")
    _assert(stats["status_counts"].get("first_pass", 0) == 1, "unexpected first-pass count")
    _assert(stats["status_counts"].get("unsupported", 0) == 1, "unexpected unsupported flow count")

    layout = exported["attribute_layout"]
    _assert(layout["emerald"]["layer_type"]["mask"] == "0xF000", "unexpected Emerald layer mask")
    _assert(layout["emerald"]["layer_type"]["shift"] == 12, "unexpected Emerald layer shift")
    _assert(layout["frlg"]["layer_type"]["mask"] == "0x60000000", "unexpected FRLG layer mask")
    _assert(layout["frlg"]["layer_type"]["shift"] == 29, "unexpected FRLG layer shift")

    layer_types = {entry["symbol"]: entry for entry in exported["layer_types"]}
    _assert(layer_types["METATILE_LAYER_TYPE_NORMAL"]["id"] == 0, "unexpected NORMAL id")
    _assert(layer_types["METATILE_LAYER_TYPE_COVERED"]["id"] == 1, "unexpected COVERED id")
    _assert(layer_types["METATILE_LAYER_TYPE_SPLIT"]["id"] == 2, "unexpected SPLIT id")
    _assert(
        layer_types["METATILE_LAYER_TYPE_NORMAL"]["draw_mapping"]["bg2"] == "tiles[0..3], source metatile bottom layer",
        "NORMAL should put bottom half on BG2",
    )
    _assert(
        layer_types["METATILE_LAYER_TYPE_NORMAL"]["draw_mapping"]["bg1"] == "tiles[4..7], source metatile top layer",
        "NORMAL should put top half on BG1",
    )
    _assert(
        layer_types["METATILE_LAYER_TYPE_COVERED"]["draw_mapping"]["bg1"] == "transparent tile 0 in all 2x2 cells",
        "COVERED should clear BG1",
    )
    _assert(
        layer_types["METATILE_LAYER_TYPE_SPLIT"]["draw_mapping"]["bg2"] == "transparent tile 0 in all 2x2 cells",
        "SPLIT should clear BG2",
    )

    flows = {entry["id"]: entry for entry in exported["source_flows"]}
    for flow_id in [
        "attribute_bit_layout",
        "layer_enum_semantics",
        "source_metatile_tile_entry_halves",
        "normal_layer_draw_mapping",
        "covered_layer_draw_mapping",
        "split_layer_draw_mapping",
        "door_animation_layer_override",
        "runtime_redraw_and_vram_schedule",
        "object_depth_dependency",
        "buy_menu_layer_snapshot",
    ]:
        _assert(flow_id in flows, "missing flow %s" % flow_id)

    _assert(
        "DrawDoorMetatileAt calls DrawMetatile with METATILE_LAYER_TYPE_COVERED"
        in flows["door_animation_layer_override"]["critical_order"],
        "door flow should record forced covered layer",
    )
    _assert(
        "DrawMetatile schedules BG1, BG2, and BG3 tilemap copies after writing layer data"
        in flows["runtime_redraw_and_vram_schedule"]["critical_order"],
        "runtime redraw flow should record BG copy scheduling",
    )
    _assert(
        "object-event sprites update OAM priority from previous elevation"
        in flows["object_depth_dependency"]["critical_order"],
        "object depth flow should record priority source",
    )

    symbols = exported["required_symbols"]
    _assert(_has_occurrence(symbols, "METATILE_LAYER_TYPE_NORMAL", "include/global.fieldmap.h"), "missing layer enum occurrence")
    _assert(_has_occurrence(symbols, "DrawMetatile", "src/field_camera.c"), "missing DrawMetatile occurrence")
    _assert(_has_occurrence(symbols, "DrawDoorMetatileAt", "src/field_camera.c"), "missing DrawDoorMetatileAt occurrence")
    _assert(_has_occurrence(symbols, "sOverworldBgTemplates", "src/overworld.c"), "missing BG template occurrence")
    _assert(_has_occurrence(symbols, "sElevationToPriority", "src/event_object_movement.c"), "missing object priority occurrence")
    _assert(_has_occurrence(symbols, "BuyMenuDrawMapMetatile", "src/shop.c"), "missing shop layer occurrence")

    unsupported_codes = {entry["code"] for entry in exported["unsupported"]}
    for code in [
        "source_layered_renderer_pending",
        "flattened_debug_atlas_not_source_equivalent",
        "object_depth_interleave_pending",
        "current_map_draw_layer_cache_pending",
        "frlg_u32_layer_attributes_pending",
        "door_forced_covered_layer_pending",
        "invalid_layer_type_validation_pending",
    ]:
        _assert(code in unsupported_codes, "missing unsupported code %s" % code)

    print("export_overworld_layer_rules_trace_smoke: ok")
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
