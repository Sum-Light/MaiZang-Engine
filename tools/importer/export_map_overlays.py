#!/usr/bin/env python3
"""Export Godot-only map overlay fixtures into generated data."""

import argparse
import json
import sys
from pathlib import Path

from export_map import load_json, to_project_path, write_json, write_manifest
from source_probe import load_config


DEFAULT_OVERLAY_SOURCE = Path("data/overlays/map_debug_fixtures.json")


def _count_overlay_object_events(maps):
    count = 0
    if not isinstance(maps, dict):
        return count
    for map_overlay in maps.values():
        if not isinstance(map_overlay, dict):
            continue
        object_events = map_overlay.get("object_events", [])
        if isinstance(object_events, list):
            count += len(object_events)
    return count


def export_map_overlays(source_path):
    overlay_data = load_json(source_path)
    maps = overlay_data.get("maps", {})
    category = overlay_data.get("category", "debug_fixtures")
    return {
        "schema_version": 1,
        "category": category,
        "source": {
            "kind": "godot_only_overlay",
            "path": to_project_path(source_path),
            "description": overlay_data.get("description", ""),
        },
        "maps": maps if isinstance(maps, dict) else {},
        "stats": {
            "map_count": len(maps) if isinstance(maps, dict) else 0,
            "object_event_count": _count_overlay_object_events(maps),
        },
    }


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, help="JSON config with output roots.")
    parser.add_argument("--source-file", type=Path, default=DEFAULT_OVERLAY_SOURCE)
    parser.add_argument("--output-root", type=Path, help="Generated data output root.")
    args = parser.parse_args(argv)

    config = load_config(args.config)
    output_root = args.output_root or Path(config.get("generated_data_root", "data/generated"))
    source_path = args.source_file
    exported = export_map_overlays(source_path)
    output_path = output_root / "maps" / "debug_overlays.json"
    write_json(output_path, exported)

    manifest_entry = {
        "category": exported["category"],
        "path": to_project_path(output_path),
        "source": to_project_path(source_path),
        "map_count": exported["stats"]["map_count"],
        "object_event_count": exported["stats"]["object_event_count"],
    }
    write_manifest(
        output_root / "import_manifest.json",
        exported_map_overlays=[manifest_entry],
        generator="tools/importer/export_map_overlays.py",
    )

    print(json.dumps({"exported": manifest_entry}, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
