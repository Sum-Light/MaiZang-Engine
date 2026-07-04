#!/usr/bin/env python3
"""Export pokeemerald-expansion maps into generated Godot-friendly JSON."""

import argparse
import json
import sys
from collections import Counter
from pathlib import Path

from source_probe import load_config, path_status, symbol_to_tileset_dir, to_project_path

MAPGRID_METATILE_ID_MASK = 0x03FF
MAPGRID_COLLISION_MASK = 0x0C00
MAPGRID_ELEVATION_MASK = 0xF000
MAPGRID_COLLISION_SHIFT = 10
MAPGRID_ELEVATION_SHIFT = 12
MAP_OFFSET = 7
GENERATED_BY = "tools/importer/export_map.py"
BATCH_REPORT_RELATIVE_PATH = Path("overworld/map_batch_report.json")


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


def discover_map_folders(root):
    maps_root = root / "data/maps"
    return sorted(
        path.parent.name
        for path in maps_root.glob("*/map.json")
    )


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


def add_border_grid_metadata(border_grid, layout):
    layout_version = layout.get("layout_version", "")
    source_rule = "frlg_wrapped_border" if layout_version == "frlg" else "emerald_2x2_parity"
    width = int(layout.get("border_width", 0) or 0)
    height = int(layout.get("border_height", 0) or 0)
    if width <= 0:
        width = 2 if len(border_grid["raw"]) >= 2 else 1
    if height <= 0:
        height = max(1, len(border_grid["raw"]) // width)
        if len(border_grid["raw"]) % width != 0:
            height += 1

    enriched = dict(border_grid)
    enriched.update({
        "width": width,
        "height": height,
        "map_offset": MAP_OFFSET,
        "source_function": "src/fieldmap.c:GetBorderBlockAt",
        "source_header": "include/fieldmap.h",
        "source_index_rule": source_rule,
        "source_runtime_coordinate": "source x/y are Godot local cell coordinates plus MAP_OFFSET",
        "source_collision_mask": "MAPGRID_COLLISION_MASK" if layout_version == "frlg" else "MAPGRID_IMPASSABLE",
        "layout_version": layout_version,
    })
    return enriched


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


def _with_source_order(records):
    ordered = []
    for index, record in enumerate(records or []):
        enriched = dict(record)
        enriched["source_order_index"] = index
        ordered.append(enriched)
    return ordered


def _object_events_with_source_order(records):
    ordered = []
    for index, record in enumerate(records or []):
        enriched = dict(record)
        enriched["source_order_index"] = index
        enriched["source_numeric_local_id"] = index + 1
        enriched["source_numeric_local_id_rule"] = "tools/mapjson/mapjson.cpp object_event emits i + 1"
        ordered.append(enriched)
    return ordered


def _event_records(map_data):
    return {
        "connections": _with_source_order(map_data.get("connections", [])),
        "object_events": _object_events_with_source_order(map_data.get("object_events", [])),
        "warp_events": _with_source_order(map_data.get("warp_events", [])),
        "coord_events": _with_source_order(map_data.get("coord_events", [])),
        "bg_events": _with_source_order(map_data.get("bg_events", [])),
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
    border_grid = add_border_grid_metadata(unpack_map_grid_values(read_u16le_file(border_path)), layout)
    events = _event_records(map_data)

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
            "layout_id": map_data.get("layout"),
            "music": map_data.get("music"),
            "region_map_section": map_data.get("region_map_section"),
            "requires_flash": map_data.get("requires_flash"),
            "weather": map_data.get("weather"),
            "map_type": map_data.get("map_type"),
            "battle_scene": map_data.get("battle_scene"),
            "allow_cycling": map_data.get("allow_cycling"),
            "allow_escaping": map_data.get("allow_escaping"),
            "allow_running": map_data.get("allow_running"),
            "show_map_name": map_data.get("show_map_name"),
            "floor_number": map_data.get("floor_number"),
            "shared_events_map": map_data.get("shared_events_map"),
            "shared_scripts_map": map_data.get("shared_scripts_map"),
            "connections_no_include": map_data.get("connections_no_include"),
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
			"source_header": "include/fieldmap.h",
			"metatile_id_mask": MAPGRID_METATILE_ID_MASK,
			"collision_mask": MAPGRID_COLLISION_MASK,
			"elevation_mask": MAPGRID_ELEVATION_MASK,
			"collision_shift": MAPGRID_COLLISION_SHIFT,
			"elevation_shift": MAPGRID_ELEVATION_SHIFT,
			"map_offset": MAP_OFFSET,
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
        "connections": events["connections"],
        "block_id_stats": build_block_stats(map_grid["metatile_ids"]),
        "raw_block_value_stats": build_block_stats(map_grid["raw"]),
        "events": events,
    }


def map_output_slug(exported, map_folder):
    return camel_to_snake(exported["map"]["name"] or map_folder)


def _unique_output_path(output_root, exported, map_folder, used_slugs):
    base_slug = map_output_slug(exported, map_folder)
    slug = base_slug
    if slug in used_slugs:
        folder_slug = camel_to_snake(map_folder)
        slug = folder_slug
        suffix = 2
        while slug in used_slugs:
            slug = "{}_{}".format(folder_slug, suffix)
            suffix += 1
    used_slugs[slug] = used_slugs.get(slug, 0) + 1
    return output_root / "maps" / "{}.json".format(slug), base_slug, slug


def manifest_entry_for_map(exported, map_output):
    return {
        "id": exported["map"]["id"],
        "name": exported["map"]["name"],
        "path": to_project_path(map_output),
        "layout_id": exported["layout"]["id"],
        "width": exported["layout"]["width"],
        "height": exported["layout"]["height"],
    }


def _map_report_row(exported, map_folder, map_output, output_slug, base_slug):
    events = exported.get("events", {})
    map_grid = exported.get("map_grid", {})
    border_grid = exported.get("border_grid", {})
    return {
        "map_folder": map_folder,
        "id": exported["map"]["id"],
        "name": exported["map"]["name"],
        "path": to_project_path(map_output),
        "output_slug": output_slug,
        "base_slug": base_slug,
        "layout_id": exported["layout"]["id"],
        "layout_name": exported["layout"]["name"],
        "width": exported["layout"]["width"],
        "height": exported["layout"]["height"],
        "map_grid_entry_count": exported["block_id_stats"]["count"],
        "unique_metatile_id_count": exported["block_id_stats"]["unique_count"],
        "border_entry_count": len(border_grid.get("raw", [])),
        "source": exported["source"],
        "header": {
            "music": exported["map"].get("music"),
            "region_map_section": exported["map"].get("region_map_section"),
            "requires_flash": exported["map"].get("requires_flash"),
            "weather": exported["map"].get("weather"),
            "map_type": exported["map"].get("map_type"),
            "battle_scene": exported["map"].get("battle_scene"),
            "allow_cycling": exported["map"].get("allow_cycling"),
            "allow_escaping": exported["map"].get("allow_escaping"),
            "allow_running": exported["map"].get("allow_running"),
            "show_map_name": exported["map"].get("show_map_name"),
            "floor_number": exported["map"].get("floor_number"),
            "shared_events_map": exported["map"].get("shared_events_map"),
            "shared_scripts_map": exported["map"].get("shared_scripts_map"),
            "connections_no_include": exported["map"].get("connections_no_include"),
        },
        "event_counts": {
            "connections": len(events.get("connections", [])),
            "object_events": len(events.get("object_events", [])),
            "warp_events": len(events.get("warp_events", [])),
            "coord_events": len(events.get("coord_events", [])),
            "bg_events": len(events.get("bg_events", [])),
        },
        "grid_format": {
            "raw_rows": len(map_grid.get("raw", [])),
            "metatile_id_rows": len(map_grid.get("metatile_ids", [])),
            "collision_rows": len(map_grid.get("collision", [])),
            "elevation_rows": len(map_grid.get("elevation", [])),
        },
    }


def build_map_batch_export(source_root, output_root, write_outputs=False):
    map_folders = discover_map_folders(source_root)
    used_slugs = {}
    exported_entries = []
    rows = []
    failures = []
    event_totals = {
        "connections": 0,
        "object_events": 0,
        "warp_events": 0,
        "coord_events": 0,
        "bg_events": 0,
    }

    for map_folder in map_folders:
        try:
            exported = export_map(source_root, map_folder)
            map_output, base_slug, output_slug = _unique_output_path(
                output_root,
                exported,
                map_folder,
                used_slugs,
            )
            if write_outputs:
                write_json(map_output, exported)
            exported_entries.append(manifest_entry_for_map(exported, map_output))
            row = _map_report_row(exported, map_folder, map_output, output_slug, base_slug)
            rows.append(row)
            for key, value in row["event_counts"].items():
                event_totals[key] += value
        except Exception as error:
            failures.append({
                "map_folder": map_folder,
                "error": str(error),
            })

    ids = [entry.get("id") for entry in exported_entries if entry.get("id")]
    names = [entry.get("name") for entry in exported_entries if entry.get("name")]
    paths = [entry.get("path") for entry in exported_entries if entry.get("path")]
    layout_ids = [entry.get("layout_id") for entry in exported_entries if entry.get("layout_id")]
    duplicate_ids = sorted(key for key, value in Counter(ids).items() if value > 1)
    duplicate_names = sorted(key for key, value in Counter(names).items() if value > 1)
    duplicate_paths = sorted(key for key, value in Counter(paths).items() if value > 1)
    duplicate_base_slugs = sorted(key for key, value in Counter(row["base_slug"] for row in rows).items() if value > 1)

    source_layouts = load_json(source_root / "data/layouts/layouts.json").get("layouts", [])
    source_layout_ids = [
        layout.get("id")
        for layout in source_layouts
        if layout.get("id")
    ]
    exported_layout_ids = sorted(set(layout_ids))
    unexported_layout_ids = sorted(set(source_layout_ids) - set(exported_layout_ids))
    stats = {
        "source_map_count": len(map_folders),
        "exported_map_count": len(exported_entries),
        "failed_map_count": len(failures),
        "source_layout_count": len(source_layout_ids),
        "exported_unique_layout_count": len(exported_layout_ids),
        "unexported_source_layout_count": len(unexported_layout_ids),
        "duplicate_id_count": len(duplicate_ids),
        "duplicate_name_count": len(duplicate_names),
        "duplicate_output_path_count": len(duplicate_paths),
        "duplicate_base_slug_count": len(duplicate_base_slugs),
        "event_totals": event_totals,
    }

    report = {
        "schema_version": 1,
        "generated_by": GENERATED_BY,
        "source": {
            "project": "pokeemerald-expansion",
            "maps_root": "data/maps",
            "layouts_json": "data/layouts/layouts.json",
            "source_map_count": len(map_folders),
        },
        "source_behavior_trace": {
            "map_header_generation": "tools/mapjson/mapjson.cpp:generate_map_header_text",
            "event_generation": "tools/mapjson/mapjson.cpp:generate_map_events_text",
            "event_constant_generation": "tools/mapjson/mapjson.cpp:process_event_constants",
            "map_header_struct": "include/global.fieldmap.h:struct MapHeader",
            "map_grid_format": "include/fieldmap.h MAPGRID bit masks",
        },
        "godot_policy": {
            "runtime_gba_palette_or_vram_limits": "not_recreated",
            "palette_affine_effects": "preserve source-visible timing/effect with Godot-native materials/animation when implemented",
            "audio": "metadata_only",
        },
        "output": {
            "map_directory": to_project_path(output_root / "maps"),
            "report_path": to_project_path(output_root / BATCH_REPORT_RELATIVE_PATH),
            "manifest_path": to_project_path(output_root / "import_manifest.json"),
            "writes_enabled": bool(write_outputs),
        },
        "stats": stats,
        "duplicates": {
            "ids": duplicate_ids,
            "names": duplicate_names,
            "paths": duplicate_paths,
            "base_slugs": duplicate_base_slugs,
        },
        "layout_coverage": {
            "source_layout_ids": source_layout_ids,
            "exported_unique_layout_ids": exported_layout_ids,
            "unexported_source_layout_ids": unexported_layout_ids,
        },
        "failures": failures,
        "maps": rows,
        "unsupported": [
            {
                "code": "audio_metadata_only",
                "status": "metadata_only",
                "note": "Map music ids and sound intent are preserved as symbols; real audio playback remains out of scope.",
            },
            {
                "code": "runtime_tileset_layer_animation_pending",
                "status": "unsupported",
                "note": "This batch map export covers source map JSON/layout grid data only; tileset animation playback remains a separate runtime/presentation task.",
            },
            {
                "code": "standalone_layout_export_pending",
                "status": "unsupported",
                "note": "Layouts not referenced by any data/maps/*/map.json record are reported but not exported by the map batch entry point.",
            },
        ],
    }
    return report, exported_entries


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
    exported_pokemon=None,
    exported_battle=None,
    exported_map_overlays=None,
    exported_object_event_sprites=None,
    exported_overworld_reports=None,
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
    pokemon = (
        _merge_manifest_entries(existing.get("pokemon", []), exported_pokemon, ["category", "path"])
        if exported_pokemon is not None
        else existing.get("pokemon", [])
    )
    battle = (
        _merge_manifest_entries(existing.get("battle", []), exported_battle, ["category", "path"])
        if exported_battle is not None
        else existing.get("battle", [])
    )
    map_overlays = (
        _merge_manifest_entries(existing.get("map_overlays", []), exported_map_overlays, ["category", "path"])
        if exported_map_overlays is not None
        else existing.get("map_overlays", [])
    )
    object_event_sprites = (
        _merge_manifest_entries(
            existing.get("object_event_sprites", []),
            exported_object_event_sprites,
            ["category", "path"],
        )
        if exported_object_event_sprites is not None
        else existing.get("object_event_sprites", [])
    )
    overworld_reports = (
        _merge_manifest_entries(
            existing.get("overworld_reports", []),
            exported_overworld_reports,
            ["category", "path"],
        )
        if exported_overworld_reports is not None
        else existing.get("overworld_reports", [])
    )
    if maps:
        manifest["maps"] = maps
    if tilesets:
        manifest["tilesets"] = tilesets
    if scripts:
        manifest["scripts"] = scripts
    if texts:
        manifest["texts"] = texts
    if pokemon:
        manifest["pokemon"] = pokemon
    if battle:
        manifest["battle"] = battle
    if map_overlays:
        manifest["map_overlays"] = map_overlays
    if object_event_sprites:
        manifest["object_event_sprites"] = object_event_sprites
    if overworld_reports:
        manifest["overworld_reports"] = overworld_reports

    write_json(path, manifest)


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, help="JSON config with source and output roots.")
    parser.add_argument("--source", type=Path, help="pokeemerald-expansion source root.")
    parser.add_argument("--map", default=None, help="Map folder name to export.")
    parser.add_argument("--all", action="store_true", help="Export every data/maps/*/map.json record.")
    parser.add_argument("--output-root", type=Path, help="Generated data output root.")
    args = parser.parse_args(argv)

    config = load_config(args.config)
    source_root = args.source or Path(config.get("source_root", ""))
    map_folder = args.map or config.get("first_slice_map", "LittlerootTown")
    output_root = args.output_root or Path(config.get("generated_data_root", "data/generated"))

    if args.all:
        report, exported_entries = build_map_batch_export(
            source_root,
            output_root,
            write_outputs=True,
        )
        report_output = output_root / BATCH_REPORT_RELATIVE_PATH
        write_json(report_output, report)
        write_manifest(
            output_root / "import_manifest.json",
            exported_maps=exported_entries,
            exported_overworld_reports=[
                {
                    "category": "overworld_map_batch_report",
                    "path": to_project_path(report_output),
                    "source_map_count": report["stats"]["source_map_count"],
                    "exported_map_count": report["stats"]["exported_map_count"],
                    "failed_map_count": report["stats"]["failed_map_count"],
                    "source_layout_count": report["stats"]["source_layout_count"],
                    "exported_unique_layout_count": report["stats"]["exported_unique_layout_count"],
                },
            ],
            generator=GENERATED_BY,
        )
        print(json.dumps({
            "report": to_project_path(report_output),
            "stats": report["stats"],
        }, ensure_ascii=False, indent=2))
        return 1 if report["stats"]["failed_map_count"] else 0

    exported = export_map(source_root, map_folder)
    map_output = output_root / "maps" / "{}.json".format(map_output_slug(exported, map_folder))
    write_json(map_output, exported)

    manifest_entry = manifest_entry_for_map(exported, map_output)
    write_manifest(
        output_root / "import_manifest.json",
        exported_maps=[manifest_entry],
        generator=GENERATED_BY,
    )

    print(json.dumps({
        "exported": manifest_entry,
        "block_id_stats": exported["block_id_stats"],
    }, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
