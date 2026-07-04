#!/usr/bin/env python3
"""Smoke checks for the overworld fieldmap grid trace report."""

import argparse
import sys
from pathlib import Path

from export_overworld_fieldmap_grid_trace import build_export
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
    _assert(exported["generated_by"].endswith("export_overworld_fieldmap_grid_trace.py"), "unexpected generator")
    _assert(stats["flow_count"] == 8, "unexpected flow count")
    _assert(stats["missing_source_file_count"] == 0, "missing source files")
    _assert(stats["missing_symbol_count"] == 0, "missing source symbols")
    _assert(stats["unsupported_count"] == 6, "unexpected unsupported count")
    _assert(stats["status_counts"].get("ported_import", 0) == 1, "unexpected ported import count")
    _assert(stats["status_counts"].get("first_pass", 0) == 5, "unexpected first-pass count")
    _assert(stats["status_counts"].get("unsupported", 0) == 1, "unexpected unsupported flow count")
    _assert(stats["status_counts"].get("first_pass_metadata", 0) == 1, "unexpected metadata flow count")

    bit_layout = exported["bit_layout"]
    _assert(bit_layout["map_grid_block_bits"] == 16, "unexpected map-grid bit width")
    _assert(bit_layout["metatile_id"]["mask"] == "0x03FF", "unexpected metatile mask")
    _assert(bit_layout["collision"]["mask"] == "0x0C00", "unexpected collision mask")
    _assert(bit_layout["elevation"]["mask"] == "0xF000", "unexpected elevation mask")

    flows = {entry["id"]: entry for entry in exported["source_flows"]}
    for flow_id in [
        "map_grid_bit_layout",
        "backup_map_layout_initialization",
        "border_fallback",
        "connection_copy_strips",
        "map_grid_accessors",
        "saved_map_view",
        "camera_connection_movement",
        "camera_focus_coordinate_offset",
    ]:
        _assert(flow_id in flows, "missing flow %s" % flow_id)

    _assert(
        "set backup width to map width + MAP_OFFSET_W" in flows["backup_map_layout_initialization"]["critical_order"],
        "backup flow should record width offset",
    )
    _assert(
        "Emerald border chooses one of four border tiles by x/y parity" in flows["border_fallback"]["critical_order"],
        "border flow should record Emerald parity fallback",
    )
    _assert(
        "east copies MAP_OFFSET + 1 columns from the connected map's left edge" in flows["connection_copy_strips"]["critical_order"],
        "connection flow should record east width asymmetry",
    )
    _assert(
        "MapGridSetMetatileIdAt preserves existing elevation bits while replacing metatile id and collision bits"
        in flows["map_grid_accessors"]["critical_order"],
        "accessor flow should record setmetatile elevation preservation",
    )
    _assert(
        "SaveMapView stores a MAP_OFFSET_W x MAP_OFFSET_H view window from sBackupMapData at save-block position"
        in flows["saved_map_view"]["critical_order"],
        "saved map view flow should record view size",
    )
    _assert(
        "CameraMove saves mapView before crossing a connection" in flows["camera_connection_movement"]["critical_order"],
        "camera flow should record SaveMapView order",
    )

    symbols = exported["required_symbols"]
    _assert(_has_occurrence(symbols, "MAP_OFFSET", "include/fieldmap.h"), "missing MAP_OFFSET header occurrence")
    _assert(_has_occurrence(symbols, "MAPGRID_METATILE_ID_MASK", "include/global.fieldmap.h"), "missing mapgrid mask occurrence")
    _assert(_has_occurrence(symbols, "InitMapLayoutData", "src/fieldmap.c"), "missing InitMapLayoutData occurrence")
    _assert(_has_occurrence(symbols, "GetBorderBlockAt", "src/fieldmap.c"), "missing GetBorderBlockAt occurrence")
    _assert(_has_occurrence(symbols, "MapGridSetMetatileIdAt", "src/fieldmap.c"), "missing MapGridSetMetatileIdAt occurrence")
    _assert(_has_occurrence(symbols, "CameraMove", "src/fieldmap.c"), "missing CameraMove occurrence")

    unsupported_codes = {entry["code"] for entry in exported["unsupported"]}
    for code in [
        "backup_map_buffer_runtime_pending",
        "connection_fill_exact_pending",
        "saved_map_view_restore_pending",
        "source_camera_movement_pending",
        "mapgrid_impassability_runtime_pending",
        "fieldmap_layer_rules_pending",
    ]:
        _assert(code in unsupported_codes, "missing unsupported code %s" % code)

    print("export_overworld_fieldmap_grid_trace_smoke: ok")
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
