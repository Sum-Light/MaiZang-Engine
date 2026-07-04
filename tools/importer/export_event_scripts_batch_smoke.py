#!/usr/bin/env python3
"""Smoke-test all-map event script batch export without writing generated files."""

import argparse
import sys
from pathlib import Path

from export_event_scripts import build_map_script_batch_export
from source_probe import load_config


EXPECTED_SOURCE_MAP_COUNT = 939
EXPECTED_SOURCE_MAP_SCRIPT_FILE_COUNT = 887
EXPECTED_MISSING_SOURCE_SCRIPT_FILE_COUNT = 52
EXPECTED_LABEL_COUNT = 18984
EXPECTED_SCRIPT_COUNT = 10293
EXPECTED_MOVEMENT_COUNT = 1280
EXPECTED_TEXT_COUNT = 7411
EXPECTED_TEXT_SOURCE_BYTE_COUNT = 413452
EXPECTED_ORPHAN_INSTRUCTION_COUNT = 44
EXPECTED_RUNTIME_PREVIEW_UNSUPPORTED_OP_COUNT = 35865
EXPECTED_UNIQUE_OP_COUNT = 447
EXPECTED_UNSUPPORTED_PREVIEW_UNIQUE_OP_COUNT = 437


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def find_row(report, map_folder):
    for row in report.get("maps", []):
        if row.get("map_folder") == map_folder:
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

    report, exported_entries = build_map_script_batch_export(
        source_root,
        output_root,
        write_outputs=False,
    )
    stats = report["stats"]

    require(stats["source_map_count"] == EXPECTED_SOURCE_MAP_COUNT, "unexpected source map count")
    require(
        stats["source_map_script_file_count"] == EXPECTED_SOURCE_MAP_SCRIPT_FILE_COUNT,
        "unexpected source map script file count",
    )
    require(
        stats["missing_source_script_file_count"] == EXPECTED_MISSING_SOURCE_SCRIPT_FILE_COUNT,
        "unexpected missing source script file count",
    )
    require(stats["exported_map_script_bundle_count"] == EXPECTED_SOURCE_MAP_SCRIPT_FILE_COUNT, "not every script file exported")
    require(stats["failed_map_script_bundle_count"] == 0, "batch script export reported failures")
    require(len(exported_entries) == EXPECTED_SOURCE_MAP_SCRIPT_FILE_COUNT, "script manifest entry count mismatch")
    require(stats["label_count"] == EXPECTED_LABEL_COUNT, "unexpected label count")
    require(stats["unique_label_count"] == EXPECTED_LABEL_COUNT, "unexpected unique label count")
    require(stats["duplicate_label_count"] == 0, "duplicate labels reported")
    require(stats["script_count"] == EXPECTED_SCRIPT_COUNT, "unexpected script count")
    require(stats["movement_count"] == EXPECTED_MOVEMENT_COUNT, "unexpected movement count")
    require(stats["text_count"] == EXPECTED_TEXT_COUNT, "unexpected text count")
    require(stats["encoded_text_count"] == EXPECTED_TEXT_COUNT, "unexpected encoded text count")
    require(stats["text_source_byte_count"] == EXPECTED_TEXT_SOURCE_BYTE_COUNT, "unexpected source text byte count")
    require(stats["charmap_warning_count"] == 0, "unexpected charmap warnings")
    require(stats["orphan_instruction_count"] == EXPECTED_ORPHAN_INSTRUCTION_COUNT, "unexpected orphan instruction count")
    require(
        stats["runtime_preview_unsupported_op_count"] == EXPECTED_RUNTIME_PREVIEW_UNSUPPORTED_OP_COUNT,
        "unexpected unsupported preview op count",
    )
    require(stats["unique_op_count"] == EXPECTED_UNIQUE_OP_COUNT, "unexpected unique op count")
    require(
        stats["unsupported_preview_unique_op_count"] == EXPECTED_UNSUPPORTED_PREVIEW_UNIQUE_OP_COUNT,
        "unexpected unsupported preview unique op count",
    )
    require(stats["duplicate_base_slug_count"] == 0, "duplicate output base slugs")
    require(stats["duplicate_output_path_count"] == 0, "duplicate script output paths")
    require(report["godot_policy"]["audio"] == "metadata_only", "audio policy was not preserved")

    missing_folders = {entry["map_folder"] for entry in report["missing_source_scripts"]}
    require("BattlePyramidSquare02" in missing_folders, "known no-script map missing from report")
    require("ContestHallBeauty" in missing_folders, "known contest no-script map missing from report")

    littleroot = find_row(report, "LittlerootTown")
    require(littleroot is not None, "LittlerootTown script row missing")
    require(littleroot["map_id"] == "MAP_LITTLEROOT_TOWN", "LittlerootTown map id changed")
    require(littleroot["script_count"] == 78, "LittlerootTown script count changed")
    require(littleroot["movement_count"] == 34, "LittlerootTown movement count changed")
    require(littleroot["text_count"] == 18, "LittlerootTown text count changed")
    require(littleroot["charmap_warning_count"] == 0, "LittlerootTown charmap warning changed")

    route101 = find_row(report, "Route101")
    require(route101 is not None, "Route101 script row missing")
    require(route101["script_count"] == 14, "Route101 script count changed")
    require(route101["movement_count"] == 13, "Route101 movement count changed")
    require(route101["text_count"] == 7, "Route101 text count changed")

    unsupported_ops = report["unsupported_preview_ops"]
    require(int(unsupported_ops.get("setvar", 0)) > 0, "setvar unsupported preview count missing")
    require(int(unsupported_ops.get("playse", 0)) > 0, "playse unsupported preview count missing")

    print(
        "ok: exported {} map script bundles, {} scripts, {} movement labels, {} local text labels".format(
            stats["exported_map_script_bundle_count"],
            stats["script_count"],
            stats["movement_count"],
            stats["text_count"],
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
