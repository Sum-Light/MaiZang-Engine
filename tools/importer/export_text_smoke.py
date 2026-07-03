#!/usr/bin/env python3
"""Smoke checks for exporting global data/text labels."""

import argparse
import sys
from pathlib import Path

from export_text import build_export
from source_probe import load_config


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, help="JSON config with source root.")
    parser.add_argument("--source", type=Path, help="pokeemerald-expansion source root.")
    args = parser.parse_args(argv)

    config = load_config(args.config)
    source_root = args.source or Path(config.get("source_root", ""))
    exported = build_export(source_root)
    stats = exported["stats"]
    report = exported["report"]
    texts = exported["texts"]

    _assert(stats["source_file_count"] == 37, "unexpected data/text source file count")
    _assert(stats["label_count"] == 3454, "unexpected global text label count")
    _assert(stats["text_count"] == 3454, "unexpected global text record count")
    _assert(stats["standard_text_count"] == 3393, "unexpected standard text count")
    _assert(stats["braille_text_count"] == 61, "unexpected braille text count")
    _assert(stats["charmap_warning_count"] == 0, "expected no charmap warnings")
    _assert(stats["braille_warning_count"] == 0, "expected no braille warnings")
    _assert(stats["preprocessor_decision_count"] == 6, "expected IS_FRLG text decisions")
    _assert(stats["preprocessor_warning_count"] == 0, "expected no preprocessor warnings")
    _assert(stats["unsupported_directive_count"] == 0, "expected no unsupported directives")
    _assert(len(report["duplicate_labels"]) == 0, "expected no duplicate labels")
    _assert(len(report["orphan_strings"]) == 0, "expected no orphan strings")
    _assert(len(report["orphan_braille"]) == 0, "expected no orphan braille")

    confirm_save = texts["gText_ConfirmSave"]
    _assert(confirm_save["kind"] == "text", "expected confirm-save text kind")
    _assert(confirm_save["source"] == "data/text/save.inc", "unexpected confirm-save source")
    _assert(confirm_save["part_count"] == 2, "unexpected confirm-save part count")
    _assert(confirm_save["encoding"]["status"] == "ok", "expected confirm-save encoding")
    _assert(confirm_save["encoding"]["byte_count"] == 29, "unexpected confirm-save byte count")
    _assert(confirm_save["encoding"]["terminator_present"], "expected confirm-save terminator")
    _assert("\n" in confirm_save["display_text"], "expected confirm-save display newline")

    pc_transfer = texts["gText_PkmnTransferredLanettesPC"]
    _assert(pc_transfer["source"] == "data/text/pc_transfer.inc", "unexpected PC transfer source")
    _assert(pc_transfer["part_count"] == 3, "expected Emerald PC transfer branch")
    _assert(pc_transfer["encoding"]["byte_count"] == 47, "unexpected PC transfer byte count")

    braille = texts["Underwater_SealedChamber_Braille_GoUpHere"]
    _assert(braille["kind"] == "braille", "expected braille kind")
    _assert(braille["source_pointer_skip_bytes"] == 6, "expected brailleformat skip")
    _assert(braille["braille_format"]["values"] == [4, 6, 26, 13, 7, 9], "unexpected brailleformat values")
    _assert(braille["encoding"]["status"] == "ok", "expected braille encoding")
    _assert(braille["encoding"]["byte_count"] == 19, "unexpected braille byte count")
    _assert(braille["encoding"]["bytes"][0] == 0x39, "unexpected first braille byte")
    _assert(braille["encoding"]["bytes"][-1] == 0xFF, "expected final braille terminator")
    _assert(braille["source_bytes"]["combined"][6] == 0x39, "expected combined source byte after header")

    print("export_text_smoke: ok")
    return 0


def _assert(condition, message):
    if not condition:
        raise AssertionError(message)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
