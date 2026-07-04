#!/usr/bin/env python3
"""Smoke checks for generated overworld script reference coverage."""

import argparse
import sys
from pathlib import Path

from export_overworld_script_reference_report import build_export
from source_probe import load_config


EXPECTED_SCRIPT_BUNDLE_COUNT = 971
EXPECTED_MAP_SCRIPT_BUNDLE_COUNT = 887
EXPECTED_SHARED_SCRIPT_BUNDLE_COUNT = 84
EXPECTED_SCRIPT_LABEL_COUNT = 13000
EXPECTED_MOVEMENT_LABEL_COUNT = 1489
EXPECTED_SCRIPT_TEXT_LABEL_COUNT = 8198
EXPECTED_GLOBAL_TEXT_LABEL_COUNT = 3454
EXPECTED_CHECKED_REFERENCE_COUNT = 21389
EXPECTED_EXCLUDED_REFERENCE_COUNT = 28
EXPECTED_SCRIPT_REFERENCE_COUNT = 10946
EXPECTED_MOVEMENT_REFERENCE_COUNT = 2776
EXPECTED_TEXT_REFERENCE_COUNT = 7667
EXPECTED_SCRIPT_FILE_DIAGNOSTIC_COUNT = 972
EXPECTED_SCRIPT_FILE_ORPHAN_INSTRUCTION_COUNT = 59
EXPECTED_SCRIPT_FILES_WITH_ORPHAN_INSTRUCTIONS = 30
EXPECTED_UNKNOWN_MACRO_COUNT = 2
EXPECTED_UNKNOWN_MACRO_UNIQUE_COUNT = 1
EXPECTED_SCRIPT_FILES_WITH_UNKNOWN_MACROS = 1
EXPECTED_UNSUPPORTED_DIRECTIVE_COUNT = 1908
EXPECTED_UNSUPPORTED_DIRECTIVE_UNIQUE_COUNT = 15
EXPECTED_SCRIPT_FILES_WITH_UNSUPPORTED_DIRECTIVES = 904


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def find_map_row(report, map_name):
    for row in report.get("maps", []):
        if row.get("map") == map_name:
            return row
    return None


def find_file_diagnostic(report, source_file):
    for row in report.get("script_file_diagnostics", []):
        if row.get("source_file") == source_file:
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

    report = build_export(source_root, output_root)
    stats = report["stats"]

    require(stats["script_bundle_count"] == EXPECTED_SCRIPT_BUNDLE_COUNT, "unexpected script bundle count")
    require(stats["map_script_bundle_count"] == EXPECTED_MAP_SCRIPT_BUNDLE_COUNT, "unexpected map bundle count")
    require(stats["shared_script_bundle_count"] == EXPECTED_SHARED_SCRIPT_BUNDLE_COUNT, "unexpected shared bundle count")
    require(stats["script_label_count"] == EXPECTED_SCRIPT_LABEL_COUNT, "unexpected script label count")
    require(stats["movement_label_count"] == EXPECTED_MOVEMENT_LABEL_COUNT, "unexpected movement label count")
    require(stats["script_text_label_count"] == EXPECTED_SCRIPT_TEXT_LABEL_COUNT, "unexpected script text label count")
    require(stats["global_text_label_count"] == EXPECTED_GLOBAL_TEXT_LABEL_COUNT, "unexpected global text label count")
    require(stats["duplicate_script_label_count"] == 0, "duplicate script labels reported")
    require(stats["duplicate_movement_label_count"] == 0, "duplicate movement labels reported")
    require(stats["duplicate_script_text_label_count"] == 0, "duplicate script text labels reported")
    require(stats["duplicate_global_text_label_count"] == 0, "duplicate global text labels reported")
    require(stats["checked_reference_count"] == EXPECTED_CHECKED_REFERENCE_COUNT, "unexpected checked reference count")
    require(stats["excluded_reference_count"] == EXPECTED_EXCLUDED_REFERENCE_COUNT, "unexpected excluded reference count")
    require(stats["missing_reference_count"] == 0, "missing generated references reported")
    require(stats["missing_script_reference_count"] == 0, "missing script references reported")
    require(stats["missing_movement_reference_count"] == 0, "missing movement references reported")
    require(stats["missing_text_reference_count"] == 0, "missing text references reported")
    require(stats["failed_bundle_count"] == 0, "script bundle load failures reported")
    require(stats["map_rows_with_missing_references"] == 0, "map rows with missing references reported")
    require(stats["bundle_rows_with_missing_references"] == 0, "bundle rows with missing references reported")
    require(
        stats["script_file_diagnostic_count"] == EXPECTED_SCRIPT_FILE_DIAGNOSTIC_COUNT,
        "unexpected script file diagnostic count",
    )
    require(
        stats["script_file_orphan_instruction_count"] == EXPECTED_SCRIPT_FILE_ORPHAN_INSTRUCTION_COUNT,
        "unexpected script file orphan count",
    )
    require(
        stats["script_files_with_orphan_instructions"] == EXPECTED_SCRIPT_FILES_WITH_ORPHAN_INSTRUCTIONS,
        "unexpected script files with orphans",
    )
    require(stats["unknown_macro_count"] == EXPECTED_UNKNOWN_MACRO_COUNT, "unexpected unknown macro count")
    require(stats["unknown_macro_unique_count"] == EXPECTED_UNKNOWN_MACRO_UNIQUE_COUNT, "unexpected unique unknown macro count")
    require(
        stats["script_files_with_unknown_macros"] == EXPECTED_SCRIPT_FILES_WITH_UNKNOWN_MACROS,
        "unexpected script files with unknown macros",
    )
    require(
        stats["unsupported_directive_count"] == EXPECTED_UNSUPPORTED_DIRECTIVE_COUNT,
        "unexpected unsupported directive count",
    )
    require(
        stats["unsupported_directive_unique_count"] == EXPECTED_UNSUPPORTED_DIRECTIVE_UNIQUE_COUNT,
        "unexpected unique unsupported directive count",
    )
    require(
        stats["script_files_with_unsupported_directives"] == EXPECTED_SCRIPT_FILES_WITH_UNSUPPORTED_DIRECTIVES,
        "unexpected script files with unsupported directives",
    )
    require(stats["unresolved_label_count"] == 0, "unresolved script/movement labels reported")
    require(stats["script_files_with_unresolved_labels"] == 0, "script files with unresolved labels reported")
    require(stats["script_files_with_missing_text_labels"] == 0, "script files with missing text labels reported")

    require(report["reference_counts"]["script"] == EXPECTED_SCRIPT_REFERENCE_COUNT, "unexpected script refs")
    require(report["reference_counts"]["movement"] == EXPECTED_MOVEMENT_REFERENCE_COUNT, "unexpected movement refs")
    require(report["reference_counts"]["text"] == EXPECTED_TEXT_REFERENCE_COUNT, "unexpected text refs")
    require(report["excluded_reference_counts"]["text"] == EXPECTED_EXCLUDED_REFERENCE_COUNT, "unexpected excluded text refs")
    require(report["missing_references"] == [], "missing reference detail should be empty")
    require(report["unknown_macro_counts"] == {"/*": 2}, "unexpected unknown macro detail")
    require(report["unsupported_directive_counts"][".byte"] == 888, "unexpected .byte directive count")
    require(report["unsupported_directive_counts"][".2byte"] == 714, "unexpected .2byte directive count")
    require(report["unsupported_directive_counts"]["#ifdef"] == 32, "unexpected #ifdef directive count")

    littleroot = find_map_row(report, "LittlerootTown")
    require(littleroot is not None, "LittlerootTown coverage row missing")
    require(littleroot["script_count"] == 78, "LittlerootTown script count changed")
    require(littleroot["movement_count"] == 34, "LittlerootTown movement count changed")
    require(littleroot["text_count"] == 18, "LittlerootTown text count changed")
    require(littleroot["runtime_preview_unsupported_op_count"] == 507, "LittlerootTown unsupported op count changed")
    require(littleroot["missing_reference_count"] == 0, "LittlerootTown missing references reported")
    require(littleroot["reference_counts"]["movement"] == 60, "LittlerootTown movement refs changed")

    route101 = find_map_row(report, "Route101")
    require(route101 is not None, "Route101 coverage row missing")
    require(route101["script_count"] == 14, "Route101 script count changed")
    require(route101["movement_count"] == 13, "Route101 movement count changed")
    require(route101["text_count"] == 7, "Route101 text count changed")
    require(route101["missing_reference_count"] == 0, "Route101 missing references reported")

    brendans_house = find_map_row(report, "LittlerootTown_BrendansHouse_1F")
    require(brendans_house is not None, "Brendan house coverage row missing")
    require(brendans_house["script_count"] == 26, "Brendan house script count changed")
    require(brendans_house["movement_count"] == 11, "Brendan house movement count changed")
    require(brendans_house["text_count"] == 29, "Brendan house text count changed")
    require(brendans_house["missing_reference_count"] == 0, "Brendan house missing references reported")

    route101_file = find_file_diagnostic(report, "data/maps/Route101/scripts.inc")
    require(route101_file is not None, "Route101 file diagnostic missing")
    require(route101_file["script_count"] == 14, "Route101 file script count changed")
    require(route101_file["movement_count"] == 13, "Route101 file movement count changed")
    require(route101_file["text_count"] == 7, "Route101 file text count changed")
    require(route101_file["orphan_instruction_count"] == 0, "Route101 orphan diagnostics changed")
    require(route101_file["unknown_macro_count"] == 0, "Route101 unknown macro diagnostics changed")
    require(route101_file["unsupported_directive_count"] == 2, "Route101 directive diagnostics changed")
    require(route101_file["unresolved_label_count"] == 0, "Route101 unresolved labels reported")
    require(route101_file["missing_text_label_count"] == 0, "Route101 missing text labels reported")

    trainer_tower_file = find_file_diagnostic(report, "data/scripts/trainer_tower.inc")
    require(trainer_tower_file is not None, "trainer_tower file diagnostic missing")
    require(trainer_tower_file["orphan_instruction_count"] == 7, "trainer_tower orphan diagnostics changed")
    require(trainer_tower_file["unsupported_directive_count"] == 1, "trainer_tower directive diagnostics changed")
    require(len(trainer_tower_file["orphan_instructions"]) == 7, "trainer_tower orphan detail count changed")

    cable_club_file = find_file_diagnostic(report, "data/scripts/cable_club.inc")
    require(cable_club_file is not None, "cable_club file diagnostic missing")
    require(cable_club_file["unknown_macro_count"] == 2, "cable_club unknown macro diagnostics changed")
    require(cable_club_file["unknown_macros"] == {"/*": 2}, "cable_club unknown macro counts changed")
    require(len(cable_club_file["unknown_macro_details"]) == 2, "cable_club unknown macro details changed")

    secret_base_file = find_file_diagnostic(report, "data/scripts/secret_base.inc")
    require(secret_base_file is not None, "secret_base file diagnostic missing")
    require(secret_base_file["unsupported_directives"] == {".include": 1}, "secret_base directive diagnostics changed")

    excluded_targets = {entry["target"] for entry in report["excluded_references"]}
    require("gStringVar4" in excluded_targets, "dynamic gStringVar4 text refs should be excluded")
    require("NULL" in excluded_targets, "NULL text refs should be excluded")

    print(
        "export_overworld_script_reference_report_smoke: ok ({} checked refs, {} movement refs)".format(
            stats["checked_reference_count"],
            stats["movement_reference_count"],
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
