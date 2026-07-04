#!/usr/bin/env python3
"""Smoke-test shared/common event script batch export without writing generated files."""

import argparse
import sys
from pathlib import Path

from export_event_scripts import build_shared_script_batch_export
from source_probe import load_config


EXPECTED_SOURCE_SHARED_SCRIPT_FILE_COUNT = 84
EXPECTED_SKIPPED_EXISTING_SHARED_SOURCE_FILE_COUNT = 3
EXPECTED_EXPORTED_SHARED_SCRIPT_BUNDLE_COUNT = 82
EXPECTED_EVENT_SCRIPTS_DIRECT_BUNDLE_COUNT = 1
EXPECTED_LABEL_COUNT = 3572
EXPECTED_SCRIPT_COUNT = 2649
EXPECTED_MOVEMENT_COUNT = 136
EXPECTED_TEXT_COUNT = 787
EXPECTED_TEXT_SOURCE_BYTE_COUNT = 39281
EXPECTED_ORPHAN_INSTRUCTION_COUNT = 15
EXPECTED_RUNTIME_PREVIEW_UNSUPPORTED_OP_COUNT = 8850
EXPECTED_UNIQUE_OP_COUNT = 308
EXPECTED_UNSUPPORTED_PREVIEW_UNIQUE_OP_COUNT = 298


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def find_row(report, name):
    for row in report.get("shared_scripts", []):
        if row.get("name") == name:
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

    report, exported_entries = build_shared_script_batch_export(
        source_root,
        output_root,
        write_outputs=False,
    )
    stats = report["stats"]

    require(
        stats["source_shared_script_file_count"] == EXPECTED_SOURCE_SHARED_SCRIPT_FILE_COUNT,
        "unexpected source shared script file count",
    )
    require(
        stats["skipped_existing_shared_source_file_count"] == EXPECTED_SKIPPED_EXISTING_SHARED_SOURCE_FILE_COUNT,
        "unexpected skipped grouped shared source file count",
    )
    require(
        stats["exported_shared_script_bundle_count"] == EXPECTED_EXPORTED_SHARED_SCRIPT_BUNDLE_COUNT,
        "unexpected exported shared bundle count",
    )
    require(stats["failed_shared_script_bundle_count"] == 0, "shared batch export reported failures")
    require(
        stats["event_scripts_direct_bundle_count"] == EXPECTED_EVENT_SCRIPTS_DIRECT_BUNDLE_COUNT,
        "event_scripts direct bundle count changed",
    )
    require(len(exported_entries) == EXPECTED_EXPORTED_SHARED_SCRIPT_BUNDLE_COUNT, "manifest entry count mismatch")
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
    require(stats["duplicate_output_path_count"] == 0, "duplicate shared output paths")
    require(report["godot_policy"]["audio"] == "metadata_only", "audio policy was not preserved")
    require(
        "data/scripts/movement.inc" in report["skipped_existing_shared_source_files"],
        "grouped movement source file should be skipped",
    )
    require(
        "data/scripts/players_house.inc" in report["skipped_existing_shared_source_files"],
        "grouped players house source file should be skipped",
    )
    require(
        "data/scripts/rival_graphics.inc" in report["skipped_existing_shared_source_files"],
        "grouped rival graphics source file should be skipped",
    )

    item_ball_frlg = find_row(report, "shared_item_ball_scripts_frlg")
    require(item_ball_frlg is not None, "FRLG item ball shared script row missing")
    require(item_ball_frlg["script_count"] == 168, "FRLG item ball script count changed")

    trainers_frlg = find_row(report, "shared_trainers_frlg")
    require(trainers_frlg is not None, "FRLG trainers shared script row missing")
    require(trainers_frlg["script_count"] == 468, "FRLG trainers script count changed")

    direct = find_row(report, "shared_event_scripts_direct")
    require(direct is not None, "event_scripts direct row missing")
    require(direct["script_count"] == 62, "event_scripts direct script count changed")
    require(direct["movement_count"] == 2, "event_scripts direct movement count changed")
    require(direct["text_count"] == 34, "event_scripts direct text count changed")
    require(
        direct["source"]["label_filter"]["kind"] == "direct_labels_after_map_includes",
        "event_scripts direct label filter changed",
    )

    unsupported_ops = report["unsupported_preview_ops"]
    require(int(unsupported_ops.get("setvar", 0)) > 0, "setvar unsupported preview count missing")
    require(int(unsupported_ops.get("trainerbattle_single", 0)) > 0, "trainerbattle_single unsupported preview count missing")

    print(
        "ok: exported {} shared script bundles, {} scripts, {} movement labels, {} local text labels".format(
            stats["exported_shared_script_bundle_count"],
            stats["script_count"],
            stats["movement_count"],
            stats["text_count"],
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
