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
LAYOUT_OUTPUT_DIRECTORY = Path("layouts")
SCRIPT_REFERENCE_EVENT_KINDS = ("object_events", "coord_events", "bg_events")
DYNAMIC_WARP_DESTINATION_MAPS = {"MAP_DYNAMIC"}
DYNAMIC_WARP_DESTINATION_IDS = {"WARP_ID_DYNAMIC", "WARP_ID_SECRET_BASE"}
CONNECTION_DIRECTIONS = {
    "down": {"constant": "CONNECTION_SOUTH", "value": 2},
    "up": {"constant": "CONNECTION_NORTH", "value": 3},
    "left": {"constant": "CONNECTION_WEST", "value": 4},
    "right": {"constant": "CONNECTION_EAST", "value": 5},
    "dive": {"constant": "CONNECTION_DIVE", "value": 6},
    "emerge": {"constant": "CONNECTION_EMERGE", "value": 7},
}


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


def load_source_layouts(root):
    return load_json(root / "data/layouts/layouts.json").get("layouts", [])


def discover_map_folders(root):
    maps_root = root / "data/maps"
    return sorted(
        path.parent.name
        for path in maps_root.glob("*/map.json")
    )


def load_map_group_index(root):
    groups_path = root / "data/maps/map_groups.json"
    groups_data = load_json(groups_path)
    by_id = {}
    by_folder = {}
    for group_index, group_symbol in enumerate(groups_data.get("group_order", [])):
        for map_num, map_folder in enumerate(groups_data.get(group_symbol, [])):
            map_path = root / "data/maps" / map_folder / "map.json"
            map_data = load_json(map_path)
            map_id = map_data.get("id")
            metadata = {
                "map_id": map_id,
                "map_folder": map_folder,
                "map_name": map_data.get("name"),
                "layout_id": map_data.get("layout"),
                "region_map_section": map_data.get("region_map_section"),
                "map_group_symbol": group_symbol,
                "map_group_index": group_index,
                "map_num": map_num,
                "map_constant_value": map_num | (group_index << 8),
                "source": {
                    "map_groups_json": "data/maps/map_groups.json",
                    "map_json": to_project_path(map_path.relative_to(root)),
                    "mapjson_generator": "tools/mapjson/mapjson.cpp:generate_map_constants_header_text",
                },
            }
            if map_id:
                by_id[map_id] = metadata
            by_folder[map_folder] = metadata
    return {
        "by_id": by_id,
        "by_folder": by_folder,
        "group_order": groups_data.get("group_order", []),
    }


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
    return grid_from_sized_flat(values, width)


def grid_from_sized_flat(values, width):
    return [
        values[row_start:row_start + width]
        for row_start in range(0, len(values), width)
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


def grid_map_values(unpacked, width, height, label, allow_mismatch=False):
    expected = width * height
    actual = len(unpacked["raw"])
    if actual != expected and not allow_mismatch:
        raise ValueError("{} has {} entries, expected {}".format(label, actual, expected))

    sized = {}
    overflow = {}
    missing_count = max(0, expected - actual)
    for key, values in unpacked.items():
        clipped = list(values[:expected])
        if len(clipped) < expected:
            clipped.extend([None] * (expected - len(clipped)))
        sized[key] = grid_from_sized_flat(clipped, width)
        if actual > expected:
            overflow[key] = values[expected:]

    result = {
        "raw": sized["raw"],
        "metatile_ids": sized["metatile_ids"],
        "collision": sized["collision"],
        "elevation": sized["elevation"],
        "source_entry_count": actual,
        "declared_cell_count": expected,
        "is_rectangular_exact": actual == expected,
    }
    if overflow:
        result["overflow_entries"] = overflow
        result["overflow_entry_count"] = actual - expected
    if missing_count:
        result["missing_entry_count"] = missing_count
    if actual != expected:
        result["warnings"] = [
            {
                "code": "layout_blockdata_size_mismatch",
                "status": "source_data_mismatch_preserved",
                "message": "{} has {} u16 entries but layout declares {}x{} = {} cells".format(
                    label,
                    actual,
                    width,
                    height,
                    expected,
                ),
            },
        ]
    return result


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


def export_layout(root, layout, allow_grid_mismatch=False):
    width = int(layout["width"])
    height = int(layout["height"])
    blockdata_path = root / layout["blockdata_filepath"]
    border_path = root / layout["border_filepath"]

    map_grid = unpack_map_grid_values(read_u16le_file(blockdata_path))
    border_grid = add_border_grid_metadata(unpack_map_grid_values(read_u16le_file(border_path)), layout)
    grid_values = grid_map_values(
        map_grid,
        width,
        height,
        layout["blockdata_filepath"],
        allow_mismatch=allow_grid_mismatch,
    )
    warnings = grid_values.pop("warnings", [])

    return {
        "schema_version": 1,
        "source": {
            "project": "pokeemerald-expansion",
            "layouts_json": "data/layouts/layouts.json",
            "blockdata": to_project_path(layout["blockdata_filepath"]),
            "border": to_project_path(layout["border_filepath"]),
        },
        "layout": {
            "id": layout.get("id"),
            "name": layout.get("name"),
            "width": width,
            "height": height,
            "layout_version": layout.get("layout_version"),
            "primary_tileset": layout.get("primary_tileset"),
            "secondary_tileset": layout.get("secondary_tileset"),
            "border_width": layout.get("border_width"),
            "border_height": layout.get("border_height"),
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
        "block_ids": grid_values["metatile_ids"],
        "map_grid": grid_values,
        "border_block_ids": border_grid["metatile_ids"],
        "border_grid": border_grid,
        "block_id_stats": build_block_stats(map_grid["metatile_ids"]),
        "raw_block_value_stats": build_block_stats(map_grid["raw"]),
        "warnings": warnings,
    }


def _with_source_order(records):
    ordered = []
    for index, record in enumerate(records or []):
        enriched = dict(record)
        enriched["source_order_index"] = index
        ordered.append(enriched)
    return ordered


def _connection_events_with_source_order(records, map_group_index):
    ordered = []
    by_id = map_group_index.get("by_id", {}) if isinstance(map_group_index, dict) else {}
    for index, record in enumerate(records or []):
        enriched = dict(record)
        enriched["source_order_index"] = index
        enriched["source_macro"] = "asm/macros/map.inc:connection direction, offset, map"
        enriched["source_struct"] = "include/global.fieldmap.h:struct MapConnection"
        direction = record.get("direction")
        direction_info = CONNECTION_DIRECTIONS.get(direction)
        if direction_info:
            enriched["source_direction_constant"] = direction_info["constant"]
            enriched["source_direction_value"] = direction_info["value"]
        target_map_id = record.get("map")
        enriched["target_map_id"] = target_map_id
        target_metadata = by_id.get(target_map_id)
        if target_metadata:
            enriched["target_lookup_status"] = "resolved"
            enriched["target_map_folder"] = target_metadata["map_folder"]
            enriched["target_map_name"] = target_metadata["map_name"]
            enriched["target_map_section"] = target_metadata["region_map_section"]
            enriched["target_layout_id"] = target_metadata["layout_id"]
            enriched["target_map_group_symbol"] = target_metadata["map_group_symbol"]
            enriched["target_map_group_index"] = target_metadata["map_group_index"]
            enriched["target_map_num"] = target_metadata["map_num"]
            enriched["target_map_constant_value"] = target_metadata["map_constant_value"]
            enriched["source_struct_fields"] = {
                "direction": direction_info["constant"] if direction_info else direction,
                "offset": record.get("offset"),
                "mapGroup": target_metadata["map_group_index"],
                "mapNum": target_metadata["map_num"],
            }
        else:
            enriched["target_lookup_status"] = "missing_target_map_id"
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


def _event_records(map_data, map_group_index):
    return {
        "connections": _connection_events_with_source_order(map_data.get("connections", []), map_group_index),
        "object_events": _object_events_with_source_order(map_data.get("object_events", [])),
        "warp_events": _with_source_order(map_data.get("warp_events", [])),
        "coord_events": _with_source_order(map_data.get("coord_events", [])),
        "bg_events": _with_source_order(map_data.get("bg_events", [])),
    }


def export_map(root, map_folder, map_group_index=None):
    layouts_path = root / "data/layouts/layouts.json"
    map_path = root / "data/maps" / map_folder / "map.json"
    script_path = root / "data/maps" / map_folder / "scripts.inc"

    layouts_data = {"layouts": load_source_layouts(root)}
    map_data = load_json(map_path)
    layout = find_layout(layouts_data.get("layouts", []), map_data.get("layout"))
    layout_export = export_layout(root, layout)
    if map_group_index is None:
        map_group_index = load_map_group_index(root)
    events = _event_records(map_data, map_group_index)

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
        "layout": layout_export["layout"],
        "tilesets": layout_export["tilesets"],
        "map_grid_format": layout_export["map_grid_format"],
        "block_ids": layout_export["block_ids"],
        "map_grid": layout_export["map_grid"],
        "border_block_ids": layout_export["border_block_ids"],
        "border_grid": layout_export["border_grid"],
        "connections": events["connections"],
        "block_id_stats": layout_export["block_id_stats"],
        "raw_block_value_stats": layout_export["raw_block_value_stats"],
        "events": events,
    }


def map_output_slug(exported, map_folder):
    return camel_to_snake(exported["map"]["name"] or map_folder)


def layout_output_slug(exported_layout):
    layout = exported_layout["layout"]
    return camel_to_snake(layout.get("name") or layout.get("id") or "layout")


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


def _unique_layout_output_path(output_root, exported_layout, used_slugs):
    base_slug = layout_output_slug(exported_layout)
    slug = base_slug
    if slug in used_slugs:
        layout_id_slug = camel_to_snake(exported_layout["layout"].get("id") or base_slug)
        slug = layout_id_slug
        suffix = 2
        while slug in used_slugs:
            slug = "{}_{}".format(layout_id_slug, suffix)
            suffix += 1
    used_slugs[slug] = used_slugs.get(slug, 0) + 1
    return output_root / LAYOUT_OUTPUT_DIRECTORY / "{}.json".format(slug), base_slug, slug


def manifest_entry_for_map(exported, map_output):
    return {
        "id": exported["map"]["id"],
        "name": exported["map"]["name"],
        "path": to_project_path(map_output),
        "layout_id": exported["layout"]["id"],
        "width": exported["layout"]["width"],
        "height": exported["layout"]["height"],
    }


def manifest_entry_for_layout(exported_layout, layout_output, referenced_maps):
    layout = exported_layout["layout"]
    referenced_maps = list(referenced_maps or [])
    return {
        "id": layout["id"],
        "name": layout["name"],
        "path": to_project_path(layout_output),
        "width": layout["width"],
        "height": layout["height"],
        "layout_version": layout.get("layout_version"),
        "primary_tileset": layout.get("primary_tileset"),
        "secondary_tileset": layout.get("secondary_tileset"),
        "referenced_map_count": len(referenced_maps),
        "referenced_maps": referenced_maps,
    }


def _map_report_row(exported, map_folder, map_output, output_slug, base_slug):
    events = exported.get("events", {})
    map_grid = exported.get("map_grid", {})
    border_grid = exported.get("border_grid", {})
    connections = events.get("connections", [])
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
            "connections": len(connections),
            "object_events": len(events.get("object_events", [])),
            "warp_events": len(events.get("warp_events", [])),
            "coord_events": len(events.get("coord_events", [])),
            "bg_events": len(events.get("bg_events", [])),
        },
        "connection_validation": {
            "missing_target_count": sum(
                1 for connection in connections if connection.get("target_lookup_status") != "resolved"
            ),
            "directions": sorted(
                set(connection.get("source_direction_constant") for connection in connections)
                - {None}
            ),
        },
        "grid_format": {
            "raw_rows": len(map_grid.get("raw", [])),
            "metatile_id_rows": len(map_grid.get("metatile_ids", [])),
            "collision_rows": len(map_grid.get("collision", [])),
            "elevation_rows": len(map_grid.get("elevation", [])),
        },
    }


def _map_context(exported):
    return {
        "map_id": exported["map"].get("id"),
        "map_name": exported["map"].get("name"),
        "map_folder": exported.get("source", {}).get("map_folder"),
        "path": exported.get("source", {}).get("map_json"),
    }


def _event_reference_context(exported, event_kind, event):
    record = _map_context(exported)
    record["event_kind"] = event_kind
    for key in (
        "source_order_index",
        "x",
        "y",
        "elevation",
        "type",
        "local_id",
        "source_numeric_local_id",
    ):
        if key in event:
            record[key] = event.get(key)
    return record


def _parse_source_int(value):
    if isinstance(value, bool) or value is None:
        return False, None
    if isinstance(value, int):
        return True, value
    text = str(value).strip()
    if not text:
        return False, None
    try:
        base = 16 if text.lower().startswith("0x") else 10
        return True, int(text, base)
    except ValueError:
        return False, None


def _resolve_generated_path(path_text, output_root):
    path = Path(path_text)
    if path.is_absolute():
        return path
    resolved_output_root = output_root.resolve()
    candidates = [
        Path.cwd() / path,
        resolved_output_root.parent.parent / path,
        resolved_output_root / path,
    ]
    for candidate in candidates:
        if candidate.exists():
            return candidate
    return candidates[0]


def _load_generated_script_label_index(output_root):
    manifest_path = output_root / "import_manifest.json"
    labels = {}
    bundles = []
    warnings = []

    if not manifest_path.exists():
        return {
            "labels": labels,
            "bundles": bundles,
            "warnings": [{
                "code": "missing_import_manifest",
                "path": to_project_path(manifest_path),
            }],
        }

    manifest = load_json(manifest_path)
    for entry in manifest.get("scripts", []):
        path_text = entry.get("path")
        bundle_record = {
            "map": entry.get("map"),
            "scope": entry.get("scope"),
            "name": entry.get("name"),
            "path": path_text,
            "script_count": entry.get("script_count"),
            "movement_count": entry.get("movement_count"),
            "text_count": entry.get("text_count"),
        }
        bundles.append(bundle_record)
        if not path_text:
            warnings.append({
                "code": "script_bundle_missing_path",
                "bundle": bundle_record,
            })
            continue
        bundle_path = _resolve_generated_path(path_text, output_root)
        if not bundle_path.exists():
            warnings.append({
                "code": "script_bundle_file_missing",
                "path": path_text,
                "resolved_path": to_project_path(bundle_path),
                "bundle": bundle_record,
            })
            continue
        try:
            bundle_data = load_json(bundle_path)
        except Exception as error:
            warnings.append({
                "code": "script_bundle_load_failed",
                "path": path_text,
                "error": str(error),
            })
            continue
        scripts = bundle_data.get("scripts", {})
        if not isinstance(scripts, dict):
            warnings.append({
                "code": "script_bundle_scripts_not_dictionary",
                "path": path_text,
            })
            continue
        for label in scripts:
            label_record = labels.setdefault(label, {
                "label": label,
                "bundles": [],
            })
            label_record["bundles"].append({
                "map": entry.get("map"),
                "scope": entry.get("scope"),
                "name": entry.get("name"),
                "path": path_text,
            })

    return {
        "labels": labels,
        "bundles": bundles,
        "warnings": warnings,
    }


def _iter_script_references(exported_maps):
    for exported in exported_maps:
        events = exported.get("events", {})
        for event_kind in SCRIPT_REFERENCE_EVENT_KINDS:
            for event in events.get(event_kind, []):
                script_label = event.get("script")
                if script_label is None:
                    continue
                script_label = str(script_label).strip()
                if script_label in ("", "0", "0x0", "NULL"):
                    continue
                record = _event_reference_context(exported, event_kind, event)
                record["script_label"] = script_label
                yield record


def _validate_script_label_references(exported_maps, output_root):
    label_index = _load_generated_script_label_index(output_root)
    script_labels = label_index["labels"]
    references = list(_iter_script_references(exported_maps))
    missing_references = [
        reference for reference in references
        if reference["script_label"] not in script_labels
    ]
    unique_checked_labels = sorted(set(reference["script_label"] for reference in references))
    unique_missing_labels = sorted(set(reference["script_label"] for reference in missing_references))
    resolved_unique_labels = sorted(set(unique_checked_labels) - set(unique_missing_labels))

    return {
        "stats": {
            "generated_bundle_count": len(label_index["bundles"]),
            "generated_script_label_count": len(script_labels),
            "checked_reference_count": len(references),
            "unique_checked_label_count": len(unique_checked_labels),
            "resolved_reference_count": len(references) - len(missing_references),
            "resolved_unique_label_count": len(resolved_unique_labels),
            "missing_reference_count": len(missing_references),
            "missing_unique_label_count": len(unique_missing_labels),
            "bundle_warning_count": len(label_index["warnings"]),
        },
        "bundles": label_index["bundles"],
        "missing_labels": unique_missing_labels,
        "missing_references": missing_references,
        "load_warnings": label_index["warnings"],
        "notes": [
            "Only generated script labels from data/generated/import_manifest.json script bundles are treated as resolved.",
            "Missing labels usually mean the source map's scripts.inc or shared script file has not been exported yet.",
        ],
    }


def _map_records_by_id(exported_maps):
    return {
        exported["map"].get("id"): exported
        for exported in exported_maps
        if exported["map"].get("id")
    }


def _is_dynamic_or_special_warp(dest_map, dest_warp_id):
    return (
        dest_map in DYNAMIC_WARP_DESTINATION_MAPS
        or str(dest_warp_id) in DYNAMIC_WARP_DESTINATION_IDS
    )


def _validate_warp_destinations(exported_maps, map_group_index):
    maps_by_id = _map_records_by_id(exported_maps)
    source_map_ids = set(map_group_index.get("by_id", {}))
    valid_static_count = 0
    missing_targets = []
    invalid_warp_ids = []
    dynamic_or_special = []
    checked_count = 0

    for exported in exported_maps:
        for event in exported.get("events", {}).get("warp_events", []):
            checked_count += 1
            dest_map = event.get("dest_map")
            dest_warp_id = event.get("dest_warp_id")
            record = _event_reference_context(exported, "warp_events", event)
            record["dest_map"] = dest_map
            record["dest_warp_id"] = dest_warp_id

            if _is_dynamic_or_special_warp(dest_map, dest_warp_id):
                dynamic_record = dict(record)
                dynamic_record["status"] = "dynamic_or_special_destination"
                dynamic_record["reason"] = (
                    "Source uses dynamic warp state or secret-base warp ids; static map/warp-id validation is not applicable."
                )
                dynamic_or_special.append(dynamic_record)
                continue

            target_map = maps_by_id.get(dest_map)
            if target_map is None:
                missing_record = dict(record)
                missing_record["status"] = (
                    "not_yet_generated_target_map"
                    if dest_map in source_map_ids
                    else "missing_target_map_id"
                )
                missing_targets.append(missing_record)
                continue

            parsed, warp_id = _parse_source_int(dest_warp_id)
            if not parsed:
                invalid_record = dict(record)
                invalid_record["status"] = "invalid_dest_warp_id"
                invalid_record["reason"] = "non_numeric_dest_warp_id"
                invalid_warp_ids.append(invalid_record)
                continue

            target_warp_count = len(target_map.get("events", {}).get("warp_events", []))
            if warp_id < 0 or warp_id >= target_warp_count:
                invalid_record = dict(record)
                invalid_record["status"] = "invalid_dest_warp_id"
                invalid_record["reason"] = "dest_warp_id_out_of_range"
                invalid_record["parsed_dest_warp_id"] = warp_id
                invalid_record["target_warp_count"] = target_warp_count
                invalid_warp_ids.append(invalid_record)
                continue

            valid_static_count += 1

    not_yet_generated_count = sum(
        1 for target in missing_targets
        if target.get("status") == "not_yet_generated_target_map"
    )
    missing_target_count = sum(
        1 for target in missing_targets
        if target.get("status") == "missing_target_map_id"
    )

    return {
        "stats": {
            "checked_count": checked_count,
            "static_checked_count": checked_count - len(dynamic_or_special),
            "valid_static_count": valid_static_count,
            "dynamic_or_special_count": len(dynamic_or_special),
            "not_yet_generated_target_count": not_yet_generated_count,
            "missing_target_map_count": missing_target_count,
            "invalid_warp_id_count": len(invalid_warp_ids),
        },
        "missing_targets": missing_targets,
        "invalid_warp_ids": invalid_warp_ids,
        "dynamic_or_special_warps": dynamic_or_special,
    }


def _connection_overlap_length(offset, source_span, target_span):
    source_start = max(0, offset)
    target_start = max(0, -offset)
    return max(0, min(source_span - source_start, target_span - target_start))


def _validate_connections(exported_maps, map_group_index):
    maps_by_id = _map_records_by_id(exported_maps)
    source_map_ids = set(map_group_index.get("by_id", {}))
    checked_count = 0
    valid_count = 0
    dive_or_emerge_count = 0
    missing_targets = []
    invalid_offsets = []
    unsupported_directions = []

    for exported in exported_maps:
        source_width = exported["layout"].get("width")
        source_height = exported["layout"].get("height")
        for connection in exported.get("events", {}).get("connections", []):
            checked_count += 1
            direction = connection.get("direction")
            target_map_id = connection.get("target_map_id") or connection.get("map")
            offset_value = connection.get("offset")
            record = _event_reference_context(exported, "connections", connection)
            record["direction"] = direction
            record["source_direction_constant"] = connection.get("source_direction_constant")
            record["target_map_id"] = target_map_id
            record["offset"] = offset_value

            target_map = maps_by_id.get(target_map_id)
            if target_map is None:
                missing_record = dict(record)
                missing_record["status"] = (
                    "not_yet_generated_target_map"
                    if target_map_id in source_map_ids
                    else "missing_target_map_id"
                )
                missing_targets.append(missing_record)
                continue

            parsed, offset = _parse_source_int(offset_value)
            if not parsed:
                invalid_record = dict(record)
                invalid_record["status"] = "invalid_offset"
                invalid_record["reason"] = "non_numeric_offset"
                invalid_offsets.append(invalid_record)
                continue

            if direction in ("dive", "emerge"):
                dive_or_emerge_count += 1
                valid_count += 1
                continue

            if direction not in ("up", "down", "left", "right"):
                unsupported_record = dict(record)
                unsupported_record["status"] = "unsupported_connection_direction"
                unsupported_directions.append(unsupported_record)
                continue

            if direction in ("up", "down"):
                source_span = source_width
                target_span = target_map["layout"].get("width")
                axis = "x"
            else:
                source_span = source_height
                target_span = target_map["layout"].get("height")
                axis = "y"
            overlap_length = _connection_overlap_length(offset, source_span, target_span)
            if overlap_length <= 0:
                invalid_record = dict(record)
                invalid_record["status"] = "invalid_offset"
                invalid_record["reason"] = "no_edge_overlap"
                invalid_record["axis"] = axis
                invalid_record["source_span"] = source_span
                invalid_record["target_span"] = target_span
                invalid_record["overlap_length"] = overlap_length
                invalid_offsets.append(invalid_record)
                continue

            valid_count += 1

    not_yet_generated_count = sum(
        1 for target in missing_targets
        if target.get("status") == "not_yet_generated_target_map"
    )
    missing_target_count = sum(
        1 for target in missing_targets
        if target.get("status") == "missing_target_map_id"
    )

    return {
        "stats": {
            "checked_count": checked_count,
            "valid_count": valid_count,
            "dive_or_emerge_count": dive_or_emerge_count,
            "cardinal_edge_offset_checked_count": checked_count - dive_or_emerge_count - len(missing_targets),
            "not_yet_generated_target_count": not_yet_generated_count,
            "missing_target_count": missing_target_count,
            "invalid_offset_count": len(invalid_offsets),
            "unsupported_direction_count": len(unsupported_directions),
        },
        "missing_targets": missing_targets,
        "invalid_offsets": invalid_offsets,
        "unsupported_directions": unsupported_directions,
        "notes": [
            "North/south/east/west connection offsets are validated for numeric value and non-empty edge overlap.",
            "Dive/emerge connections are target-validated and offset-type validated; they do not use an edge-overlap strip.",
        ],
    }


def _validate_object_local_ids(exported_maps):
    checked_count = 0
    source_symbol_count = 0
    missing_numeric_aliases = []
    numeric_alias_mismatches = []
    duplicate_numeric_local_ids = []
    duplicate_source_local_id_symbols = []

    for exported in exported_maps:
        object_events = exported.get("events", {}).get("object_events", [])
        numeric_counts = Counter()
        symbol_counts = Counter()
        context = _map_context(exported)
        for event_index, event in enumerate(object_events):
            checked_count += 1
            parsed_order, source_order_index = _parse_source_int(event.get("source_order_index"))
            expected_numeric_local_id = (source_order_index + 1) if parsed_order else (event_index + 1)
            parsed_numeric, numeric_local_id = _parse_source_int(event.get("source_numeric_local_id"))

            if not parsed_numeric:
                record = dict(context)
                record["event_kind"] = "object_events"
                record["source_order_index"] = event.get("source_order_index")
                record["local_id"] = event.get("local_id")
                record["status"] = "missing_source_numeric_local_id"
                missing_numeric_aliases.append(record)
            else:
                numeric_counts[numeric_local_id] += 1
                if numeric_local_id != expected_numeric_local_id:
                    record = dict(context)
                    record["event_kind"] = "object_events"
                    record["source_order_index"] = event.get("source_order_index")
                    record["local_id"] = event.get("local_id")
                    record["source_numeric_local_id"] = numeric_local_id
                    record["expected_source_numeric_local_id"] = expected_numeric_local_id
                    record["status"] = "source_numeric_local_id_mismatch"
                    numeric_alias_mismatches.append(record)

            source_local_id = event.get("local_id")
            if source_local_id:
                source_symbol_count += 1
                symbol_counts[source_local_id] += 1

        for local_id, count in sorted(numeric_counts.items()):
            if count > 1:
                record = dict(context)
                record["source_numeric_local_id"] = local_id
                record["duplicate_count"] = count
                duplicate_numeric_local_ids.append(record)
        for local_id, count in sorted(symbol_counts.items()):
            if count > 1:
                record = dict(context)
                record["local_id"] = local_id
                record["duplicate_count"] = count
                duplicate_source_local_id_symbols.append(record)

    return {
        "stats": {
            "map_count": len(exported_maps),
            "checked_object_event_count": checked_count,
            "source_local_id_symbol_count": source_symbol_count,
            "missing_numeric_alias_count": len(missing_numeric_aliases),
            "numeric_alias_mismatch_count": len(numeric_alias_mismatches),
            "duplicate_numeric_local_id_count": len(duplicate_numeric_local_ids),
            "duplicate_source_local_id_symbol_count": len(duplicate_source_local_id_symbols),
        },
        "missing_numeric_aliases": missing_numeric_aliases,
        "numeric_alias_mismatches": numeric_alias_mismatches,
        "duplicate_numeric_local_ids": duplicate_numeric_local_ids,
        "duplicate_source_local_id_symbols": duplicate_source_local_id_symbols,
        "source_numeric_local_id_rule": "tools/mapjson/mapjson.cpp object_event emits i + 1",
    }


def build_map_batch_validation(exported_maps, map_group_index, output_root):
    return {
        "schema_version": 1,
        "source_behavior_trace": {
            "script_labels": "tools/mapjson/mapjson.cpp event records preserve script labels; generated bundles come from tools/importer/export_event_scripts.py",
            "warps": "tools/mapjson/mapjson.cpp:generate_map_events_text warp_events",
            "connections": "asm/macros/map.inc:connection direction, offset, map + include/global.fieldmap.h:struct MapConnection",
            "object_local_ids": "tools/mapjson/mapjson.cpp process_event_constants emits object local ids as source order + 1",
        },
        "script_labels": _validate_script_label_references(exported_maps, output_root),
        "warps": _validate_warp_destinations(exported_maps, map_group_index),
        "connections": _validate_connections(exported_maps, map_group_index),
        "object_local_ids": _validate_object_local_ids(exported_maps),
    }


def _layout_report_row(exported_layout, layout_output, output_slug, base_slug, referenced_maps):
    layout = exported_layout["layout"]
    map_grid = exported_layout.get("map_grid", {})
    border_grid = exported_layout.get("border_grid", {})
    referenced_maps = list(referenced_maps or [])
    return {
        "id": layout["id"],
        "name": layout["name"],
        "path": to_project_path(layout_output),
        "output_slug": output_slug,
        "base_slug": base_slug,
        "width": layout["width"],
        "height": layout["height"],
        "layout_version": layout.get("layout_version"),
        "primary_tileset": layout.get("primary_tileset"),
        "secondary_tileset": layout.get("secondary_tileset"),
        "map_grid_entry_count": exported_layout["block_id_stats"]["count"],
        "unique_metatile_id_count": exported_layout["block_id_stats"]["unique_count"],
        "border_entry_count": len(border_grid.get("raw", [])),
        "warning_count": len(exported_layout.get("warnings", [])),
        "warnings": exported_layout.get("warnings", []),
        "referenced_map_count": len(referenced_maps),
        "referenced_maps": referenced_maps,
        "source": exported_layout["source"],
        "grid_format": {
            "raw_rows": len(map_grid.get("raw", [])),
            "metatile_id_rows": len(map_grid.get("metatile_ids", [])),
            "collision_rows": len(map_grid.get("collision", [])),
            "elevation_rows": len(map_grid.get("elevation", [])),
        },
    }


def _map_layout_references(rows):
    references = {}
    for row in rows:
        layout_id = row.get("layout_id")
        map_id = row.get("id")
        if not layout_id or not map_id:
            continue
        references.setdefault(layout_id, []).append(map_id)
    for layout_id in references:
        references[layout_id] = sorted(references[layout_id])
    return references


def build_layout_batch_export(source_root, output_root, referenced_maps_by_layout=None, write_outputs=False):
    source_layouts = load_source_layouts(source_root)
    referenced_maps_by_layout = referenced_maps_by_layout or {}
    used_slugs = {}
    exported_entries = []
    rows = []
    failures = []

    for layout in source_layouts:
        layout_id = layout.get("id")
        try:
            exported_layout = export_layout(source_root, layout, allow_grid_mismatch=True)
            layout_output, base_slug, output_slug = _unique_layout_output_path(
                output_root,
                exported_layout,
                used_slugs,
            )
            if write_outputs:
                write_json(layout_output, exported_layout)
            referenced_maps = referenced_maps_by_layout.get(layout_id, [])
            exported_entries.append(manifest_entry_for_layout(exported_layout, layout_output, referenced_maps))
            rows.append(_layout_report_row(exported_layout, layout_output, output_slug, base_slug, referenced_maps))
        except Exception as error:
            failures.append({
                "layout_id": layout_id,
                "layout_name": layout.get("name"),
                "error": str(error),
            })

    ids = [entry.get("id") for entry in exported_entries if entry.get("id")]
    paths = [entry.get("path") for entry in exported_entries if entry.get("path")]
    duplicate_ids = sorted(key for key, value in Counter(ids).items() if value > 1)
    duplicate_paths = sorted(key for key, value in Counter(paths).items() if value > 1)
    duplicate_base_slugs = sorted(key for key, value in Counter(row["base_slug"] for row in rows).items() if value > 1)
    referenced_layout_ids = sorted(set(referenced_maps_by_layout) & set(ids))
    standalone_layout_ids = sorted(set(ids) - set(referenced_layout_ids))
    unexported_layout_ids = sorted(
        set(layout.get("id") for layout in source_layouts if layout.get("id")) - set(ids)
    )

    stats = {
        "source_layout_count": len([layout for layout in source_layouts if layout.get("id")]),
        "exported_layout_count": len(exported_entries),
        "failed_layout_count": len(failures),
        "map_referenced_layout_count": len(referenced_layout_ids),
        "standalone_layout_count": len(standalone_layout_ids),
        "unexported_source_layout_count": len(unexported_layout_ids),
        "layout_warning_count": sum(row.get("warning_count", 0) for row in rows),
        "duplicate_id_count": len(duplicate_ids),
        "duplicate_output_path_count": len(duplicate_paths),
        "duplicate_base_slug_count": len(duplicate_base_slugs),
    }

    return {
        "stats": stats,
        "duplicates": {
            "ids": duplicate_ids,
            "paths": duplicate_paths,
            "base_slugs": duplicate_base_slugs,
        },
        "coverage": {
            "source_layout_ids": [layout.get("id") for layout in source_layouts if layout.get("id")],
            "exported_layout_ids": sorted(ids),
            "map_referenced_layout_ids": referenced_layout_ids,
            "standalone_layout_ids": standalone_layout_ids,
            "unexported_source_layout_ids": unexported_layout_ids,
        },
        "failures": failures,
        "layouts": rows,
    }, exported_entries


def build_map_batch_export(source_root, output_root, write_outputs=False):
    map_folders = discover_map_folders(source_root)
    map_group_index = load_map_group_index(source_root)
    used_slugs = {}
    exported_entries = []
    exported_maps = []
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
            exported = export_map(source_root, map_folder, map_group_index=map_group_index)
            map_output, base_slug, output_slug = _unique_output_path(
                output_root,
                exported,
                map_folder,
                used_slugs,
            )
            if write_outputs:
                write_json(map_output, exported)
            exported_entries.append(manifest_entry_for_map(exported, map_output))
            exported_maps.append(exported)
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
    duplicate_ids = sorted(key for key, value in Counter(ids).items() if value > 1)
    duplicate_names = sorted(key for key, value in Counter(names).items() if value > 1)
    duplicate_paths = sorted(key for key, value in Counter(paths).items() if value > 1)
    duplicate_base_slugs = sorted(key for key, value in Counter(row["base_slug"] for row in rows).items() if value > 1)
    missing_connection_target_count = sum(
        row["connection_validation"]["missing_target_count"]
        for row in rows
    )
    validation = build_map_batch_validation(exported_maps, map_group_index, output_root)

    map_references_by_layout = _map_layout_references(rows)
    layout_report, exported_layout_entries = build_layout_batch_export(
        source_root,
        output_root,
        referenced_maps_by_layout=map_references_by_layout,
        write_outputs=write_outputs,
    )
    layout_stats = layout_report["stats"]
    source_layout_ids = layout_report["coverage"]["source_layout_ids"]
    exported_layout_ids = layout_report["coverage"]["exported_layout_ids"]
    map_referenced_layout_ids = layout_report["coverage"]["map_referenced_layout_ids"]
    standalone_layout_ids = layout_report["coverage"]["standalone_layout_ids"]
    unexported_layout_ids = layout_report["coverage"]["unexported_source_layout_ids"]
    script_label_stats = validation["script_labels"]["stats"]
    warp_validation_stats = validation["warps"]["stats"]
    connection_validation_stats = validation["connections"]["stats"]
    object_local_id_stats = validation["object_local_ids"]["stats"]

    stats = {
        "source_map_count": len(map_folders),
        "exported_map_count": len(exported_entries),
        "failed_map_count": len(failures),
        "source_layout_count": layout_stats["source_layout_count"],
        "exported_layout_count": layout_stats["exported_layout_count"],
        "exported_unique_layout_count": len(exported_layout_ids),
        "failed_layout_count": layout_stats["failed_layout_count"],
        "map_referenced_layout_count": len(map_referenced_layout_ids),
        "standalone_layout_count": len(standalone_layout_ids),
        "unexported_source_layout_count": len(unexported_layout_ids),
        "layout_warning_count": layout_stats["layout_warning_count"],
        "duplicate_id_count": len(duplicate_ids),
        "duplicate_name_count": len(duplicate_names),
        "duplicate_output_path_count": len(duplicate_paths),
        "duplicate_base_slug_count": len(duplicate_base_slugs),
        "duplicate_layout_id_count": layout_stats["duplicate_id_count"],
        "duplicate_layout_output_path_count": layout_stats["duplicate_output_path_count"],
        "duplicate_layout_base_slug_count": layout_stats["duplicate_base_slug_count"],
        "missing_connection_target_count": missing_connection_target_count,
        "missing_script_label_reference_count": script_label_stats["missing_reference_count"],
        "missing_unique_script_label_count": script_label_stats["missing_unique_label_count"],
        "invalid_warp_target_count": (
            warp_validation_stats["not_yet_generated_target_count"]
            + warp_validation_stats["missing_target_map_count"]
            + warp_validation_stats["invalid_warp_id_count"]
        ),
        "dynamic_or_special_warp_count": warp_validation_stats["dynamic_or_special_count"],
        "invalid_connection_count": (
            connection_validation_stats["not_yet_generated_target_count"]
            + connection_validation_stats["missing_target_count"]
            + connection_validation_stats["invalid_offset_count"]
            + connection_validation_stats["unsupported_direction_count"]
        ),
        "invalid_object_local_id_count": (
            object_local_id_stats["missing_numeric_alias_count"]
            + object_local_id_stats["numeric_alias_mismatch_count"]
            + object_local_id_stats["duplicate_numeric_local_id_count"]
            + object_local_id_stats["duplicate_source_local_id_symbol_count"]
        ),
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
            "connection_macro": "asm/macros/map.inc:connection direction, offset, map",
            "connection_generation": "tools/mapjson/mapjson.cpp:generate_map_connections_text",
            "map_group_constants": "tools/mapjson/mapjson.cpp:generate_map_constants_header_text",
            "map_header_struct": "include/global.fieldmap.h:struct MapHeader",
            "map_connection_struct": "include/global.fieldmap.h:struct MapConnection",
            "map_grid_format": "include/fieldmap.h MAPGRID bit masks",
        },
        "godot_policy": {
            "runtime_gba_palette_or_vram_limits": "not_recreated",
            "palette_affine_effects": "preserve source-visible timing/effect with Godot-native materials/animation when implemented",
            "audio": "metadata_only",
        },
        "output": {
            "map_directory": to_project_path(output_root / "maps"),
            "layout_directory": to_project_path(output_root / LAYOUT_OUTPUT_DIRECTORY),
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
            "exported_layout_ids": exported_layout_ids,
            "exported_unique_layout_ids": exported_layout_ids,
            "map_referenced_layout_ids": map_referenced_layout_ids,
            "standalone_layout_ids": standalone_layout_ids,
            "unexported_source_layout_ids": unexported_layout_ids,
        },
        "validation": validation,
        "failures": {
            "maps": failures,
            "layouts": layout_report["failures"],
        },
        "maps": rows,
        "layouts": layout_report["layouts"],
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
        ],
        "notes": [
            "All source layouts are exported independently under data/generated/layouts; map JSON records keep embedded layout grid data for current runtime compatibility.",
            "Standalone layouts are exported even when no data/maps/*/map.json header references them.",
        ],
    }
    return report, exported_entries, exported_layout_entries


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
    exported_layouts=None,
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
    layouts = (
        _merge_manifest_entries(existing.get("layouts", []), exported_layouts, ["id", "name", "path"])
        if exported_layouts is not None
        else existing.get("layouts", [])
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
    if layouts:
        manifest["layouts"] = layouts
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
        report, exported_entries, exported_layout_entries = build_map_batch_export(
            source_root,
            output_root,
            write_outputs=True,
        )
        report_output = output_root / BATCH_REPORT_RELATIVE_PATH
        write_json(report_output, report)
        write_manifest(
            output_root / "import_manifest.json",
            exported_maps=exported_entries,
            exported_layouts=exported_layout_entries,
            exported_overworld_reports=[
                {
                    "category": "overworld_map_batch_report",
                    "path": to_project_path(report_output),
                    "source_map_count": report["stats"]["source_map_count"],
                    "exported_map_count": report["stats"]["exported_map_count"],
                    "failed_map_count": report["stats"]["failed_map_count"],
                    "source_layout_count": report["stats"]["source_layout_count"],
                    "exported_unique_layout_count": report["stats"]["exported_unique_layout_count"],
                    "exported_layout_count": report["stats"]["exported_layout_count"],
                    "map_referenced_layout_count": report["stats"]["map_referenced_layout_count"],
                    "standalone_layout_count": report["stats"]["standalone_layout_count"],
                    "failed_layout_count": report["stats"]["failed_layout_count"],
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
