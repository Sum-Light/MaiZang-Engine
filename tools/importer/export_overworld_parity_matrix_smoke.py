#!/usr/bin/env python3
"""Smoke checks for the overworld parity matrix export."""

import argparse
import sys
from pathlib import Path

from export_overworld_parity_matrix import STATUS_VALUES, build_export
from source_probe import load_config


REQUIRED_FIELDS = {
    "id",
    "area",
    "status",
    "source",
    "godot",
    "unsupported",
    "notes",
}

REQUIRED_GODOT_FIELDS = {
    "importers",
    "generated_artifacts",
    "runtime_owners",
    "presentation_owners",
    "verification",
}


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, help="JSON config with source root.")
    parser.add_argument("--source", type=Path, help="pokeemerald-expansion source root.")
    args = parser.parse_args(argv)

    config = load_config(args.config)
    source_root = args.source or Path(config.get("source_root", ""))
    exported = build_export(source_root)
    entries = exported["entries"]
    stats = exported["stats"]

    _assert(exported["schema_version"] == 1, "unexpected schema version")
    _assert(exported["status_values"] == STATUS_VALUES, "unexpected status value contract")
    _assert(stats["entry_count"] == 15, "unexpected parity entry count")
    _assert(stats["status_counts"]["first_pass"] == 10, "unexpected first-pass count")
    _assert(stats["status_counts"]["unsupported"] == 3, "unexpected unsupported count")
    _assert(stats["status_counts"]["metadata_only"] == 1, "unexpected metadata-only count")
    _assert(stats["status_counts"]["untraced"] == 1, "unexpected untraced count")
    _assert(stats["missing_registry_codes"] == [], "expected every unsupported code to be registered")
    _assert(stats["missing_source_file_count"] == 0, "expected all referenced source files to exist")

    ids = set()
    registry_codes = {
        entry["code"]
        for entry in exported["unsupported_code_registry"]
    }
    _assert(len(registry_codes) >= 10, "expected a meaningful unsupported-code registry")

    for entry in entries:
        missing_fields = REQUIRED_FIELDS.difference(entry.keys())
        _assert(not missing_fields, "entry {} missing fields {}".format(entry.get("id"), sorted(missing_fields)))
        _assert(entry["id"] not in ids, "duplicate entry id {}".format(entry["id"]))
        ids.add(entry["id"])
        _assert(entry["status"] in STATUS_VALUES, "invalid status for {}".format(entry["id"]))
        _assert(isinstance(entry["source"].get("files", []), list), "source files should be a list")
        _assert(isinstance(entry["source"].get("symbols", []), list), "source symbols should be a list")
        _assert(REQUIRED_GODOT_FIELDS.issubset(entry["godot"].keys()), "missing Godot owner fields")
        for code in entry.get("unsupported", []):
            _assert(code in registry_codes, "unregistered unsupported code {}".format(code))

    _assert("map_lifecycle" in ids, "expected map lifecycle row")
    _assert("metatile_layer_rendering" in ids, "expected layer rendering row")
    _assert("door_animation" in ids, "expected door animation row")
    _assert("tileset_animation" in ids, "expected tileset animation row")
    _assert("debug_overworld_toolkit" in ids, "expected debug toolkit row")

    layer_row = _entry(entries, "metatile_layer_rendering")
    _assert(layer_row["status"] == "unsupported", "layer rendering should remain unsupported")
    _assert("layer_split_pending" in layer_row["unsupported"], "expected layer split unsupported code")

    door_row = _entry(entries, "door_animation")
    _assert(door_row["status"] == "first_pass", "door row should be first-pass")
    _assert("door_overlay_not_source_equivalent" in door_row["unsupported"], "expected door overlay unsupported code")

    debug_row = _entry(entries, "debug_overworld_toolkit")
    _assert(debug_row["status"] == "unsupported", "debug toolkit should start unsupported")
    _assert("debug_toolkit_pending" in debug_row["unsupported"], "expected debug toolkit unsupported code")
    _assert("tools/godot_smoke/overworld_debug_tools_smoke.gd" in debug_row["godot"]["verification"], "expected future debug smoke owner")

    print("export_overworld_parity_matrix_smoke: ok")
    return 0


def _entry(entries, entry_id):
    for entry in entries:
        if entry["id"] == entry_id:
            return entry
    raise AssertionError("missing entry {}".format(entry_id))


def _assert(condition, message):
    if not condition:
        raise AssertionError(message)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
