#!/usr/bin/env python3
"""Bake one map's tilesets into Godot-friendly RGBA metatile atlases."""

import argparse
import json
import math
import sys
from pathlib import Path

try:
    from PIL import Image
except ImportError as error:
    raise SystemExit(
        "Pillow is required for tileset export. Install it with `python -m pip install Pillow`."
    ) from error

from export_map import find_layout, load_json, read_u16le_file, write_json, write_manifest
from source_probe import path_status, symbol_to_tileset_dir, to_project_path, load_config


TILE_SIZE = 8
METATILE_SIZE = 16
NUM_TILES_IN_PRIMARY = 512
NUM_METATILES_IN_PRIMARY = 512
NUM_PALS_IN_PRIMARY = 6
NUM_PALS_TOTAL = 13
NUM_TILES_PER_METATILE = 8

TILE_INDEX_MASK = 0x03FF
TILE_HFLIP_MASK = 0x0400
TILE_VFLIP_MASK = 0x0800
TILE_PALETTE_SHIFT = 12

METATILE_ATTR_BEHAVIOR_MASK = 0x00FF
METATILE_ATTR_LAYER_MASK = 0xF000
METATILE_ATTR_LAYER_SHIFT = 12

FLIP_LEFT_RIGHT = Image.Transpose.FLIP_LEFT_RIGHT if hasattr(Image, "Transpose") else Image.FLIP_LEFT_RIGHT
FLIP_TOP_BOTTOM = Image.Transpose.FLIP_TOP_BOTTOM if hasattr(Image, "Transpose") else Image.FLIP_TOP_BOTTOM


def camel_to_snake(value):
    chars = []
    for index, char in enumerate(value):
        if char.isupper() and index > 0:
            chars.append("_")
        chars.append(char.lower())
    return "".join(chars)


def read_jasc_palette(path):
    lines = [
        line.strip()
        for line in path.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]
    if len(lines) < 3 or lines[0] != "JASC-PAL":
        raise ValueError("unsupported palette format: {}".format(path))

    color_count = int(lines[2])
    colors = []
    for line in lines[3:3 + color_count]:
        red, green, blue = [int(part) for part in line.split()]
        colors.append((red, green, blue, 255))

    while len(colors) < 16:
        colors.append((0, 0, 0, 255))
    colors[0] = (colors[0][0], colors[0][1], colors[0][2], 0)
    return colors[:16]


def read_palettes(tileset_dir):
    palette_dir = tileset_dir / "palettes"
    palettes = []
    for index in range(16):
        path = palette_dir / "{:02}.pal".format(index)
        if path.exists():
            palettes.append(read_jasc_palette(path))
        else:
            palettes.append([(0, 0, 0, 0)] * 16)
    return palettes


def build_global_palettes(primary_palettes, secondary_palettes):
    palettes = []
    for index in range(16):
        if index < NUM_PALS_IN_PRIMARY:
            palettes.append(primary_palettes[index])
        elif index < NUM_PALS_TOTAL:
            palettes.append(secondary_palettes[index])
        elif index < len(secondary_palettes):
            palettes.append(secondary_palettes[index])
        else:
            palettes.append([(0, 0, 0, 0)] * 16)
    return palettes


def load_indexed_tiles(path):
    image = Image.open(path)
    if image.mode != "P":
        raise ValueError("{} must be an indexed PNG, got mode {}".format(path, image.mode))
    if image.width % TILE_SIZE != 0 or image.height % TILE_SIZE != 0:
        raise ValueError("{} dimensions are not aligned to {}px tiles".format(path, TILE_SIZE))
    return image


def tile_count(image):
    return (image.width // TILE_SIZE) * (image.height // TILE_SIZE)


def read_metatiles(path):
    values = read_u16le_file(path)
    if len(values) % NUM_TILES_PER_METATILE != 0:
        raise ValueError("{} has {} u16 entries, not divisible by {}".format(
            path,
            len(values),
            NUM_TILES_PER_METATILE,
        ))
    return [
        values[index:index + NUM_TILES_PER_METATILE]
        for index in range(0, len(values), NUM_TILES_PER_METATILE)
    ]


def read_metatile_attributes(path):
    values = read_u16le_file(path)
    attributes = []
    for value in values:
        attributes.append({
            "raw": value,
            "behavior": value & METATILE_ATTR_BEHAVIOR_MASK,
            "layer_type": (value & METATILE_ATTR_LAYER_MASK) >> METATILE_ATTR_LAYER_SHIFT,
        })
    return attributes


def unpack_tile_entry(raw):
    return {
        "raw": raw,
        "tile_id": raw & TILE_INDEX_MASK,
        "hflip": bool(raw & TILE_HFLIP_MASK),
        "vflip": bool(raw & TILE_VFLIP_MASK),
        "palette": (raw >> TILE_PALETTE_SHIFT) & 0x0F,
    }


def tile_source_for_id(tile_id, primary_image, secondary_image):
    if tile_id < NUM_TILES_IN_PRIMARY:
        return primary_image, tile_id, "primary"
    return secondary_image, tile_id - NUM_TILES_IN_PRIMARY, "secondary"


def render_tile(tile_entry, primary_image, secondary_image, global_palettes):
    image, local_tile_id, source_kind = tile_source_for_id(
        tile_entry["tile_id"],
        primary_image,
        secondary_image,
    )
    if local_tile_id < 0 or local_tile_id >= tile_count(image):
        return Image.new("RGBA", (TILE_SIZE, TILE_SIZE), (0, 0, 0, 0)), {
            "type": "tile_index_out_of_range",
            "tile_id": tile_entry["tile_id"],
            "local_tile_id": local_tile_id,
            "source_kind": source_kind,
        }

    tiles_wide = image.width // TILE_SIZE
    source_x = (local_tile_id % tiles_wide) * TILE_SIZE
    source_y = (local_tile_id // tiles_wide) * TILE_SIZE
    indexed_tile = image.crop((source_x, source_y, source_x + TILE_SIZE, source_y + TILE_SIZE))

    palette = global_palettes[tile_entry["palette"]]
    rendered = Image.new("RGBA", (TILE_SIZE, TILE_SIZE), (0, 0, 0, 0))
    pixels_in = indexed_tile.load()
    pixels_out = rendered.load()
    for y in range(TILE_SIZE):
        for x in range(TILE_SIZE):
            color_index = pixels_in[x, y]
            pixels_out[x, y] = palette[color_index] if color_index < len(palette) else (0, 0, 0, 0)

    if tile_entry["hflip"]:
        rendered = rendered.transpose(FLIP_LEFT_RIGHT)
    if tile_entry["vflip"]:
        rendered = rendered.transpose(FLIP_TOP_BOTTOM)
    return rendered, None


def image_region_is_opaque(image, position):
    pixels = image.load()
    left, top = position
    for y in range(TILE_SIZE):
        for x in range(TILE_SIZE):
            if pixels[left + x, top + y][3] < 255:
                return False
    return True


def render_metatile(
    metatile_id,
    source_kind,
    local_id,
    raw_entries,
    primary_image,
    secondary_image,
    global_palettes,
    warnings,
    coverage_notes,
):
    output = Image.new("RGBA", (METATILE_SIZE, METATILE_SIZE), (0, 0, 0, 0))
    positions = [
        (0, 0),
        (TILE_SIZE, 0),
        (0, TILE_SIZE),
        (TILE_SIZE, TILE_SIZE),
        (0, 0),
        (TILE_SIZE, 0),
        (0, TILE_SIZE),
        (TILE_SIZE, TILE_SIZE),
    ]
    tile_entries = [unpack_tile_entry(raw) for raw in raw_entries]
    tile_issues = []
    for tile_index, (tile_entry, position) in enumerate(zip(tile_entries, positions)):
        rendered_tile, issue = render_tile(
            tile_entry,
            primary_image,
            secondary_image,
            global_palettes,
        )
        if issue is not None:
            issue.update({
                "metatile_id": metatile_id,
                "metatile_source_kind": source_kind,
                "metatile_local_id": local_id,
                "tile_entry_index": tile_index,
                "metatile_layer": "bottom" if tile_index < 4 else "top",
                "position": {
                    "x": position[0],
                    "y": position[1],
                },
                "palette": tile_entry["palette"],
            })
            tile_issues.append(issue)
        output.alpha_composite(rendered_tile, position)

    for issue in tile_issues:
        position = issue["position"]
        if (
            issue["metatile_layer"] == "bottom"
            and image_region_is_opaque(output, (position["x"], position["y"]))
        ):
            note = dict(issue)
            note["type"] = "covered_{}".format(issue["type"])
            coverage_notes.append(note)
        else:
            warnings.append(issue)
    return output, tile_entries


def metatile_attribute(attributes, local_id):
    if local_id < len(attributes):
        return attributes[local_id]
    return {
        "raw": 0,
        "behavior": 0,
        "layer_type": 0,
    }


def used_metatile_ids_from_layout(root, layout):
    block_values = read_u16le_file(root / layout["blockdata_filepath"])
    return sorted({value & 0x03FF for value in block_values})


def build_tileset_record(root, kind, symbol):
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
            "palettes": path_status(root, base / "palettes"),
        },
    }


def export_tilesets(root, map_folder, output_data_root, output_asset_root):
    layouts_path = root / "data/layouts/layouts.json"
    map_path = root / "data/maps" / map_folder / "map.json"
    layouts_data = load_json(layouts_path)
    map_data = load_json(map_path)
    layout = find_layout(layouts_data.get("layouts", []), map_data.get("layout"))

    primary_symbol = layout.get("primary_tileset")
    secondary_symbol = layout.get("secondary_tileset")
    primary_dir = root / "data/tilesets/primary" / symbol_to_tileset_dir(primary_symbol)
    secondary_dir = root / "data/tilesets/secondary" / symbol_to_tileset_dir(secondary_symbol)

    primary_image = load_indexed_tiles(primary_dir / "tiles.png")
    secondary_image = load_indexed_tiles(secondary_dir / "tiles.png")
    global_palettes = build_global_palettes(
        read_palettes(primary_dir),
        read_palettes(secondary_dir),
    )

    primary_metatiles = read_metatiles(primary_dir / "metatiles.bin")
    secondary_metatiles = read_metatiles(secondary_dir / "metatiles.bin")
    primary_attributes = read_metatile_attributes(primary_dir / "metatile_attributes.bin")
    secondary_attributes = read_metatile_attributes(secondary_dir / "metatile_attributes.bin")

    total_metatiles = NUM_METATILES_IN_PRIMARY + len(secondary_metatiles)
    columns = 32
    rows = int(math.ceil(total_metatiles / float(columns)))
    atlas = Image.new("RGBA", (columns * METATILE_SIZE, rows * METATILE_SIZE), (0, 0, 0, 0))
    metatile_entries = []
    warnings = []
    coverage_notes = []

    for metatile_id in range(total_metatiles):
        if metatile_id < NUM_METATILES_IN_PRIMARY:
            source_kind = "primary"
            local_id = metatile_id
            raw_entries = primary_metatiles[local_id] if local_id < len(primary_metatiles) else [0] * NUM_TILES_PER_METATILE
            attribute = metatile_attribute(primary_attributes, local_id)
        else:
            source_kind = "secondary"
            local_id = metatile_id - NUM_METATILES_IN_PRIMARY
            raw_entries = secondary_metatiles[local_id]
            attribute = metatile_attribute(secondary_attributes, local_id)

        rendered, tile_entries = render_metatile(
            metatile_id,
            source_kind,
            local_id,
            raw_entries,
            primary_image,
            secondary_image,
            global_palettes,
            warnings,
            coverage_notes,
        )
        atlas_x = (metatile_id % columns) * METATILE_SIZE
        atlas_y = (metatile_id // columns) * METATILE_SIZE
        atlas.alpha_composite(rendered, (atlas_x, atlas_y))
        metatile_entries.append({
            "id": metatile_id,
            "source_kind": source_kind,
            "local_id": local_id,
            "atlas": {
                "x": atlas_x,
                "y": atlas_y,
                "w": METATILE_SIZE,
                "h": METATILE_SIZE,
            },
            "attribute": attribute,
            "tile_entries": tile_entries,
        })

    map_slug = camel_to_snake(map_data.get("name") or map_folder)
    atlas_path = output_asset_root / "tilesets" / "{}_metatiles.png".format(map_slug)
    atlas_path.parent.mkdir(parents=True, exist_ok=True)
    atlas.save(atlas_path)

    data_path = output_data_root / "tilesets" / "{}.json".format(map_slug)
    data = {
        "schema_version": 1,
        "generated_by": "tools/importer/export_tilesets.py",
        "source": {
            "project": "pokeemerald-expansion",
            "map_folder": map_folder,
            "map_json": to_project_path(map_path.relative_to(root)),
            "layouts_json": "data/layouts/layouts.json",
            "layout_id": layout.get("id"),
        },
        "palette_baking": {
            "runtime_palette_required": False,
            "primary_palette_slots": "0-5 from primary tileset",
            "secondary_palette_slots": "6-12 from secondary tileset",
            "transparent_color_index": 0,
        },
        "tilesets": {
            "primary": build_tileset_record(root, "primary", primary_symbol),
            "secondary": build_tileset_record(root, "secondary", secondary_symbol),
        },
        "atlas": {
            "image": "res://{}".format(to_project_path(atlas_path)),
            "image_project_path": to_project_path(atlas_path),
            "tile_size": METATILE_SIZE,
            "columns": columns,
            "rows": rows,
            "total_metatiles": total_metatiles,
            "primary_metatile_count": NUM_METATILES_IN_PRIMARY,
            "secondary_metatile_count": len(secondary_metatiles),
        },
        "used_metatile_ids": used_metatile_ids_from_layout(root, layout),
        "metatile_entries": metatile_entries,
        "coverage_notes": coverage_notes,
        "warnings": warnings,
    }
    write_json(data_path, data)

    manifest_entry = {
        "map": map_data.get("name"),
        "path": to_project_path(data_path),
        "atlas_image": to_project_path(atlas_path),
        "primary_tileset": primary_symbol,
        "secondary_tileset": secondary_symbol,
        "total_metatiles": total_metatiles,
    }
    write_manifest(
        output_data_root / "import_manifest.json",
        exported_tilesets=[manifest_entry],
        generator="tools/importer/export_tilesets.py",
    )
    return manifest_entry, data


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, help="JSON config with source and output roots.")
    parser.add_argument("--source", type=Path, help="pokeemerald-expansion source root.")
    parser.add_argument("--map", default=None, help="Map folder name to export.")
    parser.add_argument("--output-data-root", type=Path, help="Generated data output root.")
    parser.add_argument("--output-asset-root", type=Path, help="Generated asset output root.")
    args = parser.parse_args(argv)

    config = load_config(args.config)
    source_root = args.source or Path(config.get("source_root", ""))
    map_folder = args.map or config.get("first_slice_map", "LittlerootTown")
    output_data_root = args.output_data_root or Path(config.get("generated_data_root", "data/generated"))
    output_asset_root = args.output_asset_root or Path(config.get("generated_asset_root", "assets/generated"))

    manifest_entry, data = export_tilesets(
        source_root,
        map_folder,
        output_data_root,
        output_asset_root,
    )
    print(json.dumps({
        "exported": manifest_entry,
        "atlas": data["atlas"],
        "used_metatile_count": len(data["used_metatile_ids"]),
        "coverage_note_count": len(data["coverage_notes"]),
        "warning_count": len(data["warnings"]),
    }, ensure_ascii=False, indent=2))
    return 0 if not data["warnings"] else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
