#!/usr/bin/env python3
"""Smoke-test batch map export coverage without writing generated map files."""

import argparse
import sys
from pathlib import Path

from export_map import build_map_batch_export, export_map
from source_probe import load_config


EXPECTED_SOURCE_MAP_COUNT = 939
EXPECTED_SOURCE_LAYOUT_COUNT = 785
EXPECTED_MAP_REFERENCED_LAYOUT_COUNT = 711
EXPECTED_STANDALONE_LAYOUT_COUNT = 74
EXPECTED_UNEXPORTED_LAYOUT_COUNT = 0
EXPECTED_LAYOUT_WARNING_COUNT = 20
EXPECTED_GENERATED_SCRIPT_BUNDLE_COUNT = 889
EXPECTED_GENERATED_SCRIPT_LABEL_COUNT = 10351
EXPECTED_SCRIPT_REFERENCE_COUNT = 5314
EXPECTED_RESOLVED_SCRIPT_REFERENCE_COUNT = 3804
EXPECTED_MISSING_SCRIPT_REFERENCE_COUNT = 1510
EXPECTED_MISSING_UNIQUE_SCRIPT_LABEL_COUNT = 582
EXPECTED_DYNAMIC_OR_SPECIAL_WARP_COUNT = 64
EXPECTED_DIVE_OR_EMERGE_CONNECTION_COUNT = 14


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def find_row(report, map_name):
    for row in report.get("maps", []):
        if row.get("name") == map_name:
            return row
    return None


def find_layout_row(report, layout_id):
    for row in report.get("layouts", []):
        if row.get("id") == layout_id:
            return row
    return None


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, help="JSON config with source and output roots.")
    parser.add_argument("--source", type=Path, help="pokeemerald-expansion source root.")
    parser.add_argument("--output-root", type=Path, help="Generated data output root.")
    args = parser.parse_args(argv)

    config = load_config(args.config)
    source_root = args.source or Path(config.get("source_root", ""))
    output_root = args.output_root or Path(config.get("generated_data_root", "data/generated"))

    report, exported_entries, exported_layout_entries = build_map_batch_export(
        source_root,
        output_root,
        write_outputs=False,
    )
    stats = report["stats"]

    require(stats["source_map_count"] == EXPECTED_SOURCE_MAP_COUNT, "unexpected source map count")
    require(stats["exported_map_count"] == EXPECTED_SOURCE_MAP_COUNT, "not every source map exported")
    require(stats["failed_map_count"] == 0, "batch map export reported failures")
    require(stats["source_layout_count"] == EXPECTED_SOURCE_LAYOUT_COUNT, "unexpected source layout count")
    require(stats["exported_layout_count"] == EXPECTED_SOURCE_LAYOUT_COUNT, "not every source layout exported")
    require(stats["failed_layout_count"] == 0, "batch layout export reported failures")
    require(
        stats["map_referenced_layout_count"] == EXPECTED_MAP_REFERENCED_LAYOUT_COUNT,
        "unexpected map-referenced layout count",
    )
    require(
        stats["standalone_layout_count"] == EXPECTED_STANDALONE_LAYOUT_COUNT,
        "unexpected standalone layout count",
    )
    require(
        stats["unexported_source_layout_count"] == EXPECTED_UNEXPORTED_LAYOUT_COUNT,
        "unexpected unexported layout count",
    )
    require(stats["layout_warning_count"] == EXPECTED_LAYOUT_WARNING_COUNT, "unexpected layout warning count")
    require(stats["duplicate_output_path_count"] == 0, "duplicate map output paths")
    require(stats["duplicate_id_count"] == 0, "duplicate map ids")
    require(stats["duplicate_layout_output_path_count"] == 0, "duplicate layout output paths")
    require(stats["duplicate_layout_id_count"] == 0, "duplicate layout ids")
    require(stats["missing_connection_target_count"] == 0, "connection target map metadata missing")
    require(len(exported_entries) == EXPECTED_SOURCE_MAP_COUNT, "manifest entry count mismatch")
    require(len(exported_layout_entries) == EXPECTED_SOURCE_LAYOUT_COUNT, "layout manifest entry count mismatch")
    require(report["godot_policy"]["audio"] == "metadata_only", "audio policy was not preserved")
    require(
        len(report["layout_coverage"]["standalone_layout_ids"]) == EXPECTED_STANDALONE_LAYOUT_COUNT,
        "standalone layout id coverage mismatch",
    )
    require(
        "LAYOUT_LITTLEROOT_TOWN_PROFESSOR_BIRCHS_LAB_WITH_TABLE"
        in report["layout_coverage"]["standalone_layout_ids"],
        "known standalone layout missing from coverage report",
    )
    birch_table_layout = find_layout_row(report, "LAYOUT_LITTLEROOT_TOWN_PROFESSOR_BIRCHS_LAB_WITH_TABLE")
    require(birch_table_layout is not None, "standalone Birch lab layout row missing")
    require(birch_table_layout["warning_count"] == 1, "standalone size-mismatch warning missing")
    require(
        birch_table_layout["warnings"][0]["code"] == "layout_blockdata_size_mismatch",
        "unexpected standalone layout warning code",
    )

    littleroot = find_row(report, "LittlerootTown")
    require(littleroot is not None, "LittlerootTown row missing")
    require(littleroot["event_counts"]["object_events"] == 8, "LittlerootTown object event count changed")
    require(littleroot["event_counts"]["warp_events"] == 3, "LittlerootTown warp count changed")
    require(littleroot["header"]["requires_flash"] is False, "LittlerootTown requires_flash changed")
    require(littleroot["grid_format"]["raw_rows"] == 20, "LittlerootTown raw grid row count changed")

    littleroot_export = export_map(source_root, "LittlerootTown")
    first_object = littleroot_export["events"]["object_events"][0]
    first_warp = littleroot_export["events"]["warp_events"][0]
    require(first_object["source_order_index"] == 0, "object source_order_index missing")
    require(first_object["source_numeric_local_id"] == 1, "object numeric local-id alias missing")
    require(first_warp["source_order_index"] == 0, "warp source_order_index missing")

    frontier_east_export = export_map(source_root, "BattleFrontier_OutsideEast")
    first_connection = frontier_east_export["events"]["connections"][0]
    require(first_connection["target_lookup_status"] == "resolved", "connection target was not resolved")
    require(
        first_connection["target_map_id"] == "MAP_BATTLE_FRONTIER_OUTSIDE_WEST",
        "connection target map id changed",
    )
    require(first_connection["target_map_section"] == "MAPSEC_BATTLE_FRONTIER", "target map section missing")
    require(first_connection["source_direction_constant"] == "CONNECTION_WEST", "connection direction missing")
    require(isinstance(first_connection["target_map_group_index"], int), "connection map group missing")
    require(isinstance(first_connection["target_map_num"], int), "connection map num missing")
    require(
        first_connection["source_struct_fields"]["mapGroup"] == first_connection["target_map_group_index"],
        "connection struct mapGroup mismatch",
    )

    celadon_roof = find_row(report, "CeladonCity_DepartmentStore_Roof_Frlg")
    require(celadon_roof is not None, "Celadon department store roof row missing")
    require(celadon_roof["header"]["floor_number"] == 127, "FRLG floor_number metadata missing")

    event_totals = stats["event_totals"]
    require(event_totals["object_events"] > 0, "object event total missing")
    require(event_totals["warp_events"] > 0, "warp event total missing")
    require(event_totals["coord_events"] > 0, "coord event total missing")
    require(event_totals["bg_events"] > 0, "BG event total missing")

    validation = report.get("validation", {})
    script_validation = validation.get("script_labels", {})
    script_stats = script_validation.get("stats", {})
    require(
        script_stats["generated_bundle_count"] == EXPECTED_GENERATED_SCRIPT_BUNDLE_COUNT,
        "generated overworld script bundle count changed",
    )
    require(
        script_stats["generated_script_label_count"] == EXPECTED_GENERATED_SCRIPT_LABEL_COUNT,
        "generated overworld script label count changed",
    )
    require(
        script_stats["checked_reference_count"] == EXPECTED_SCRIPT_REFERENCE_COUNT,
        "script reference validation count changed",
    )
    require(
        script_stats["resolved_reference_count"] == EXPECTED_RESOLVED_SCRIPT_REFERENCE_COUNT,
        "resolved script reference count changed",
    )
    require(
        script_stats["missing_reference_count"] == EXPECTED_MISSING_SCRIPT_REFERENCE_COUNT,
        "missing script reference count changed",
    )
    require(
        script_stats["missing_unique_label_count"] == EXPECTED_MISSING_UNIQUE_SCRIPT_LABEL_COUNT,
        "missing unique script label count changed",
    )
    require(script_stats["bundle_warning_count"] == 0, "script bundle load warnings changed")
    require(
        stats["missing_script_label_reference_count"] == EXPECTED_MISSING_SCRIPT_REFERENCE_COUNT,
        "top-level missing script reference count mismatch",
    )
    require(
        "Common_EventScript_FindItem" in script_validation.get("missing_labels", []),
        "known not-yet-exported common script label should be reported missing",
    )
    require(
        "LittlerootTown_EventScript_Twin" not in script_validation.get("missing_labels", []),
        "generated Littleroot script label should resolve",
    )

    warp_validation = validation.get("warps", {})
    warp_stats = warp_validation.get("stats", {})
    require(warp_stats["checked_count"] == event_totals["warp_events"], "warp validation count mismatch")
    require(warp_stats["static_checked_count"] == 2543, "static warp validation count changed")
    require(warp_stats["valid_static_count"] == 2543, "valid static warp count changed")
    require(
        warp_stats["dynamic_or_special_count"] == EXPECTED_DYNAMIC_OR_SPECIAL_WARP_COUNT,
        "dynamic/special warp count changed",
    )
    require(warp_stats["missing_target_map_count"] == 0, "static warp target map missing")
    require(warp_stats["not_yet_generated_target_count"] == 0, "static warp target not generated")
    require(warp_stats["invalid_warp_id_count"] == 0, "invalid static warp id reported")
    require(stats["invalid_warp_target_count"] == 0, "top-level invalid warp target count mismatch")
    require(
        stats["dynamic_or_special_warp_count"] == EXPECTED_DYNAMIC_OR_SPECIAL_WARP_COUNT,
        "top-level dynamic/special warp count mismatch",
    )

    connection_validation = validation.get("connections", {})
    connection_stats = connection_validation.get("stats", {})
    require(
        connection_stats["checked_count"] == event_totals["connections"],
        "connection validation count mismatch",
    )
    require(connection_stats["valid_count"] == event_totals["connections"], "valid connection count changed")
    require(
        connection_stats["dive_or_emerge_count"] == EXPECTED_DIVE_OR_EMERGE_CONNECTION_COUNT,
        "dive/emerge connection count changed",
    )
    require(connection_stats["missing_target_count"] == 0, "connection target missing")
    require(connection_stats["not_yet_generated_target_count"] == 0, "connection target not generated")
    require(connection_stats["invalid_offset_count"] == 0, "connection offset validation failed")
    require(connection_stats["unsupported_direction_count"] == 0, "unsupported connection direction reported")
    require(stats["invalid_connection_count"] == 0, "top-level invalid connection count mismatch")

    object_local_id_validation = validation.get("object_local_ids", {})
    object_local_id_stats = object_local_id_validation.get("stats", {})
    require(
        object_local_id_stats["checked_object_event_count"] == event_totals["object_events"],
        "object local-id validation count mismatch",
    )
    require(object_local_id_stats["source_local_id_symbol_count"] == 741, "source local-id symbol count changed")
    require(object_local_id_stats["missing_numeric_alias_count"] == 0, "missing numeric local-id alias")
    require(object_local_id_stats["numeric_alias_mismatch_count"] == 0, "numeric local-id alias mismatch")
    require(
        object_local_id_stats["duplicate_numeric_local_id_count"] == 0,
        "duplicate numeric local ids reported",
    )
    require(
        object_local_id_stats["duplicate_source_local_id_symbol_count"] == 0,
        "duplicate source local-id symbols reported",
    )
    require(stats["invalid_object_local_id_count"] == 0, "top-level invalid object local-id count mismatch")

    print(
        "ok: exported {}/{} maps, exported {} layouts ({} map-referenced, {} standalone), {} object events".format(
            stats["exported_map_count"],
            stats["source_map_count"],
            stats["exported_layout_count"],
            stats["map_referenced_layout_count"],
            stats["standalone_layout_count"],
            event_totals["object_events"],
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
