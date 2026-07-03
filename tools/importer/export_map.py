#!/usr/bin/env python3
"""Export one pokeemerald-expansion map into generated Godot-friendly JSON."""

import argparse
import json
import sys
from pathlib import Path

from source_probe import load_config, path_status, symbol_to_tileset_dir, to_project_path

MAPGRID_METATILE_ID_MASK = 0x03FF
MAPGRID_COLLISION_MASK = 0x0C00
MAPGRID_ELEVATION_MASK = 0xF000
MAPGRID_COLLISION_SHIFT = 10
MAPGRID_ELEVATION_SHIFT = 12


def camel_to_snake(value):
    chars = []
    for index, char in enumerate(value):
        if char == "_":
            if chars and chars[-1] != "_":
                chars.append("_")
            continue
        if char.isupper() and index > 0 and chars and chars[-1] != "_":
            chars.append("_")
        chars.append(char.lower())
    return "".join(chars)


def load_json(path):
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def find_layout(layouts, layout_id):
    for layout in layouts:
        if layout.get("id") == layout_id:
            return layout
    raise ValueError("layout not found: {}".format(layout_id))


def read_u16le_file(path):
    data = path.read_bytes()
    if len(data) % 2 != 0:
        raise ValueError("{} has odd byte length {}".format(path, len(data)))
    return [
        data[index] | (data[index + 1] << 8)
        for index in range(0, len(data), 2)
    ]


def grid_from_flat(values, width, height, label):
    expected = width * height
    if len(values) != expected:
        raise ValueError("{} has {} entries, expected {}".format(label, len(values), expected))
    return [
        values[row_start:row_start + width]
        for row_start in range(0, expected, width)
    ]


def unpack_map_grid_values(values):
    return {
        "raw": values,
        "metatile_ids": [
            value & MAPGRID_METATILE_ID_MASK
            for value in values
        ],
        "collision": [
            (value & MAPGRID_COLLISION_MASK) >> MAPGRID_COLLISION_SHIFT
            for value in values
        ],
        "elevation": [
            (value & MAPGRID_ELEVATION_MASK) >> MAPGRID_ELEVATION_SHIFT
            for value in values
        ],
    }


def grid_map_values(unpacked, width, height, label):
    return {
        "raw": grid_from_flat(unpacked["raw"], width, height, label),
        "metatile_ids": grid_from_flat(unpacked["metatile_ids"], width, height, label),
        "collision": grid_from_flat(unpacked["collision"], width, height, label),
        "elevation": grid_from_flat(unpacked["elevation"], width, height, label),
    }


def tileset_record(root, kind, symbol):
    directory = symbol_to_tileset_dir(symbol)
    base = Path("data/tilesets") / kind / directory
    return {
        "symbol": symbol,
        "kind": kind,
        "directory": directory,
        "files": {
            "tiles": path_status(root, base / "tiles.png"),
            "metatiles": path_status(root, base / "metatiles.bin"),
            "metatile_attributes": path_status(root, base / "metatile_attributes.bin"),
        },
    }


def build_block_stats(block_values):
    unique_ids = sorted(set(block_values))
    return {
        "count": len(block_values),
        "unique_count": len(unique_ids),
        "min": min(block_values) if block_values else None,
        "max": max(block_values) if block_values else None,
        "unique_ids": unique_ids,
    }


def export_map(root, map_folder):
    layouts_path = root / "data/layouts/layouts.json"
    map_path = root / "data/maps" / map_folder / "map.json"
    script_path = root / "data/maps" / map_folder / "scripts.inc"

    layouts_data = load_json(layouts_path)
    map_data = load_json(map_path)
    layout = find_layout(layouts_data.get("layouts", []), map_data.get("layout"))

    width = int(layout["width"])
    height = int(layout["height"])
    blockdata_path = root / layout["blockdata_filepath"]
    border_path = root / layout["border_filepath"]

    map_grid = unpack_map_grid_values(read_u16le_file(blockdata_path))
    border_grid = unpack_map_grid_values(read_u16le_file(border_path))

    return {
        "schema_version": 1,
        "source": {
            "project": "pokeemerald-expansion",
            "map_folder": map_folder,
            "map_json": to_project_path(map_path.relative_to(root)),
            "map_script": to_project_path(script_path.relative_to(root)),
            "layouts_json": "data/layouts/layouts.json",
            "blockdata": to_project_path(layout["blockdata_filepath"]),
            "border": to_project_path(layout["border_filepath"]),
        },
        "map": {
            "id": map_data.get("id"),
            "name": map_data.get("name"),
            "music": map_data.get("music"),
            "region_map_section": map_data.get("region_map_section"),
            "weather": map_data.get("weather"),
            "map_type": map_data.get("map_type"),
            "battle_scene": map_data.get("battle_scene"),
            "allow_cycling": map_data.get("allow_cycling"),
            "allow_escaping": map_data.get("allow_escaping"),
            "allow_running": map_data.get("allow_running"),
            "show_map_name": map_data.get("show_map_name"),
        },
        "layout": {
            "id": layout.get("id"),
            "name": layout.get("name"),
            "width": width,
            "height": height,
            "layout_version": layout.get("layout_version"),
            "primary_tileset": layout.get("primary_tileset"),
            "secondary_tileset": layout.get("secondary_tileset"),
        },
        "tilesets": {
            "primary": tileset_record(root, "primary", layout.get("primary_tileset")),
            "secondary": tileset_record(root, "secondary", layout.get("secondary_tileset")),
        },
        "map_grid_format": {
            "source_header": "include/global.fieldmap.h",
            "metatile_id_mask": MAPGRID_METATILE_ID_MASK,
            "collision_mask": MAPGRID_COLLISION_MASK,
            "elevation_mask": MAPGRID_ELEVATION_MASK,
            "collision_shift": MAPGRID_COLLISION_SHIFT,
            "elevation_shift": MAPGRID_ELEVATION_SHIFT,
        },
        "block_ids": grid_map_values(
            map_grid,
            width,
            height,
            layout["blockdata_filepath"],
        )["metatile_ids"],
        "map_grid": grid_map_values(
            map_grid,
            width,
            height,
            layout["blockdata_filepath"],
        ),
        "border_block_ids": border_grid["metatile_ids"],
        "border_grid": border_grid,
        "block_id_stats": build_block_stats(map_grid["metatile_ids"]),
        "raw_block_value_stats": build_block_stats(map_grid["raw"]),
        "events": {
            "connections": map_data.get("connections", []),
            "object_events": map_data.get("object_events", []),
            "warp_events": map_data.get("warp_events", []),
            "coord_events": map_data.get("coord_events", []),
            "bg_events": map_data.get("bg_events", []),
        },
    }


def write_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    text = json.dumps(data, ensure_ascii=False, indent=2)
    with path.open("w", encoding="utf-8", newline="\n") as handle:
        handle.write(text + "\n")


def _manifest_generators(existing, generator):
    generators = []
    existing_generators = existing.get("generators", [])
    if isinstance(existing_generators, list):
        generators.extend(existing_generators)

    old_generator = existing.get("generated_by")
    if isinstance(old_generator, str) and old_generator not in generators:
        generators.append(old_generator)

    if generator is not None and generator not in generators:
        generators.append(generator)
    return generators


def _manifest_entry_key(entry, preferred_fields):
    if not isinstance(entry, dict):
        return ("invalid", "")
    for field in preferred_fields:
        value = entry.get(field)
        if value is not None and str(value) != "":
            return (field, str(value))
    return ("path", str(entry.get("path", "")))


def _merge_manifest_entries(existing_entries, exported_entries, preferred_fields):
    result = []
    positions = {}
    if isinstance(existing_entries, list):
        for entry in existing_entries:
            key = _manifest_entry_key(entry, preferred_fields)
            positions[key] = len(result)
            result.append(entry)

    if isinstance(exported_entries, list):
        for entry in exported_entries:
            key = _manifest_entry_key(entry, preferred_fields)
            if key in positions:
                result[positions[key]] = entry
            else:
                positions[key] = len(result)
                result.append(entry)
    return result


def write_manifest(
    path,
    exported_maps=None,
    exported_tilesets=None,
    exported_scripts=None,
    exported_texts=None,
    generator=None,
):
    existing = {}
    if path.exists():
        try:
            existing = load_json(path)
        except json.JSONDecodeError:
            existing = {}

    manifest = {
        "schema_version": 1,
        "generators": _manifest_generators(existing, generator),
    }

    maps = (
        _merge_manifest_entries(existing.get("maps", []), exported_maps, ["id", "name", "path"])
        if exported_maps is not None
        else existing.get("maps", [])
    )
    tilesets = (
        _merge_manifest_entries(existing.get("tilesets", []), exported_tilesets, ["map", "path"])
        if exported_tilesets is not None
        else existing.get("tilesets", [])
    )
    scripts = (
        _merge_manifest_entries(existing.get("scripts", []), exported_scripts, ["map", "path"])
        if exported_scripts is not None
        else existing.get("scripts", [])
    )
    texts = (
        _merge_manifest_entries(existing.get("texts", []), exported_texts, ["category", "path"])
        if exported_texts is not None
        else existing.get("texts", [])
    )
    if maps:
        manifest["maps"] = maps
    if tilesets:
        manifest["tilesets"] = tilesets
    if scripts:
        manifest["scripts"] = scripts
    if texts:
        manifest["texts"] = texts

    write_json(path, manifest)


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, help="JSON config with source and output roots.")
    parser.add_argument("--source", type=Path, help="pokeemerald-expansion source root.")
    parser.add_argument("--map", default=None, help="Map folder name to export.")
    parser.add_argument("--output-root", type=Path, help="Generated data output root.")
    args = parser.parse_args(argv)

    config = load_config(args.config)
    source_root = args.source or Path(config.get("source_root", ""))
    map_folder = args.map or config.get("first_slice_map", "LittlerootTown")
    output_root = args.output_root or Path(config.get("generated_data_root", "data/generated"))

    exported = export_map(source_root, map_folder)
    map_slug = camel_to_snake(exported["map"]["name"] or map_folder)
    map_output = output_root / "maps" / "{}.json".format(map_slug)
    write_json(map_output, exported)

    manifest_entry = {
        "id": exported["map"]["id"],
        "name": exported["map"]["name"],
        "path": to_project_path(map_output),
        "layout_id": exported["layout"]["id"],
        "width": exported["layout"]["width"],
        "height": exported["layout"]["height"],
    }
    write_manifest(
        output_root / "import_manifest.json",
        exported_maps=[manifest_entry],
        generator="tools/importer/export_map.py",
    )

    print(json.dumps({
        "exported": manifest_entry,
        "block_id_stats": exported["block_id_stats"],
    }, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
