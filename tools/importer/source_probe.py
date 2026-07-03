#!/usr/bin/env python3
"""Probe a pokeemerald-expansion source tree before building importers."""

import argparse
import json
import sys
from pathlib import Path


REQUIRED_SOURCE_FILES = [
    "data/layouts/layouts.json",
    "src/data/wild_encounters.json",
    "src/data/trainers.party",
    "src/data/pokemon/species_info.h",
    "src/data/moves_info.h",
    "src/data/items.h",
    "charmap.txt",
]


def load_config(path):
    if path is None:
        return {}
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def symbol_to_tileset_dir(symbol):
    prefix = "gTileset_"
    name = symbol[len(prefix):] if symbol.startswith(prefix) else symbol
    chars = []
    for index, char in enumerate(name):
        if char.isupper() and index > 0:
            chars.append("_")
        chars.append(char.lower())
    return "".join(chars)


def to_project_path(value):
    if isinstance(value, Path):
        return value.as_posix()
    return str(value).replace("\\", "/")


def count_files(root, pattern):
    return len(list(root.glob(pattern)))


def path_status(root, relative_path):
    path = root / relative_path
    return {
        "path": to_project_path(relative_path),
        "exists": path.exists(),
        "size": path.stat().st_size if path.exists() and path.is_file() else None,
    }


def find_layout(layouts, layout_id):
    for layout in layouts:
        if layout.get("id") == layout_id:
            return layout
    return None


def probe_source(root, first_slice_map):
    report = {
        "source_root": str(root),
        "source_exists": root.exists(),
        "first_slice_map": first_slice_map,
        "counts": {},
        "required_files": [],
        "first_slice": {},
        "missing": [],
    }

    if not root.exists():
        report["missing"].append(str(root))
        return report

    report["counts"] = {
        "map_json": count_files(root, "data/maps/*/map.json"),
        "map_scripts": count_files(root, "data/maps/*/scripts.inc"),
        "primary_tilesets": count_files(root, "data/tilesets/primary/*/tiles.png"),
        "secondary_tilesets": count_files(root, "data/tilesets/secondary/*/tiles.png"),
    }

    for relative_path in REQUIRED_SOURCE_FILES:
        status = path_status(root, relative_path)
        report["required_files"].append(status)
        if not status["exists"]:
            report["missing"].append(relative_path)

    layouts_path = root / "data/layouts/layouts.json"
    map_path = root / "data/maps" / first_slice_map / "map.json"
    script_path = root / "data/maps" / first_slice_map / "scripts.inc"

    if not layouts_path.exists() or not map_path.exists():
        if not layouts_path.exists():
            report["missing"].append("data/layouts/layouts.json")
        if not map_path.exists():
            report["missing"].append(to_project_path(map_path.relative_to(root)))
        return report

    with layouts_path.open("r", encoding="utf-8") as handle:
        layouts_data = json.load(handle)
    with map_path.open("r", encoding="utf-8") as handle:
        map_data = json.load(handle)

    layout = find_layout(layouts_data.get("layouts", []), map_data.get("layout"))
    first_slice = {
        "map_id": map_data.get("id"),
        "map_name": map_data.get("name"),
        "map_json": to_project_path(map_path.relative_to(root)),
        "script": to_project_path(script_path.relative_to(root)),
        "script_exists": script_path.exists(),
        "layout_id": map_data.get("layout"),
        "layout_found": layout is not None,
        "object_event_count": len(map_data.get("object_events", [])),
        "warp_event_count": len(map_data.get("warp_events", [])),
        "coord_event_count": len(map_data.get("coord_events", [])),
        "connection_count": len(map_data.get("connections", [])),
    }

    if layout is not None:
        first_slice.update({
            "width": layout.get("width"),
            "height": layout.get("height"),
            "primary_tileset": layout.get("primary_tileset"),
            "secondary_tileset": layout.get("secondary_tileset"),
            "blockdata": path_status(root, layout.get("blockdata_filepath")),
            "border": path_status(root, layout.get("border_filepath")),
            "primary_tileset_dir": symbol_to_tileset_dir(layout.get("primary_tileset", "")),
            "secondary_tileset_dir": symbol_to_tileset_dir(layout.get("secondary_tileset", "")),
        })

        tileset_checks = []
        for kind, symbol in [
            ("primary", layout.get("primary_tileset", "")),
            ("secondary", layout.get("secondary_tileset", "")),
        ]:
            directory = symbol_to_tileset_dir(symbol)
            base = Path("data/tilesets") / kind / directory
            for filename in ["tiles.png", "metatiles.bin", "metatile_attributes.bin"]:
                tileset_checks.append(path_status(root, base / filename))
        first_slice["tileset_files"] = tileset_checks
        for status in tileset_checks:
            if not status["exists"]:
                report["missing"].append(status["path"])

    report["first_slice"] = first_slice
    return report


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, help="JSON config with a source_root field.")
    parser.add_argument("--source", type=Path, help="pokeemerald-expansion source root.")
    parser.add_argument("--map", default=None, help="First-slice map folder name.")
    parser.add_argument("--write-report", type=Path, help="Optional UTF-8 JSON report path.")
    args = parser.parse_args(argv)

    config = load_config(args.config)
    source_root = args.source or Path(config.get("source_root", ""))
    first_slice_map = args.map or config.get("first_slice_map", "LittlerootTown")

    report = probe_source(source_root, first_slice_map)
    output = json.dumps(report, ensure_ascii=False, indent=2)
    print(output)

    if args.write_report is not None:
        args.write_report.parent.mkdir(parents=True, exist_ok=True)
        with args.write_report.open("w", encoding="utf-8", newline="\n") as handle:
            handle.write(output + "\n")

    return 0 if not report["missing"] else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
