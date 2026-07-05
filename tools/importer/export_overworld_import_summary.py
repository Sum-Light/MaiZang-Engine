#!/usr/bin/env python3
"""Export a generated overworld import coverage summary."""

import argparse
import json
import re
import sys
from pathlib import Path

from export_map import read_u16le_file, write_json, write_manifest
from source_probe import load_config, to_project_path


GENERATED_BY = "tools/importer/export_overworld_import_summary.py"
SUMMARY_PATH = Path("overworld/import_summary.json")
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
TILE_SIZE_PIXELS = 8
METATILE_LABEL_RE = re.compile(
    r"^\s*#define\s+(METATILE_[A-Za-z0-9_]+)\s+(0x[0-9A-Fa-f]+|\d+)\b"
)


def read_json(path):
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def read_text(path):
    with path.open("r", encoding="utf-8") as handle:
        return handle.read()


def count_files(root, pattern):
    if not root.exists():
        return 0
    return len(list(root.glob(pattern)))


def read_png_dimensions(path):
    data = path.read_bytes()
    if len(data) < 24 or data[:8] != PNG_SIGNATURE or data[12:16] != b"IHDR":
        raise ValueError("{} is not a PNG with an IHDR chunk".format(path))
    return int.from_bytes(data[16:20], "big"), int.from_bytes(data[20:24], "big")


def count_source_layouts(source_root):
    path = source_root / "data/layouts/layouts.json"
    if not path.exists():
        return 0
    return len(read_json(path).get("layouts", []))


def count_source_layout_blockdata_entries(source_root):
    path = source_root / "data/layouts/layouts.json"
    if not path.exists():
        return {
            "layout_blockdata_entry_count": 0,
            "layout_blockdata_missing_file_count": 0,
            "layout_blockdata_invalid_file_count": 0,
        }

    total = 0
    missing = 0
    invalid = 0
    for layout in read_json(path).get("layouts", []):
        blockdata = layout.get("blockdata_filepath")
        blockdata_path = source_root / blockdata if blockdata else None
        if not blockdata_path or not blockdata_path.exists():
            missing += 1
            continue
        try:
            total += len(read_u16le_file(blockdata_path))
        except ValueError:
            invalid += 1

    return {
        "layout_blockdata_entry_count": total,
        "layout_blockdata_missing_file_count": missing,
        "layout_blockdata_invalid_file_count": invalid,
    }


def count_source_layout_tileset_pairs(source_root):
    path = source_root / "data/layouts/layouts.json"
    if not path.exists():
        return {
            "layout_tileset_pair_count": 0,
            "layout_tileset_pair_layout_count": 0,
        }
    layouts = read_json(path).get("layouts", [])
    pairs = {
        (layout.get("primary_tileset"), layout.get("secondary_tileset"))
        for layout in layouts
        if layout.get("primary_tileset") and layout.get("secondary_tileset")
    }
    return {
        "layout_tileset_pair_count": len(pairs),
        "layout_tileset_pair_layout_count": len(layouts),
    }


def parse_tileset_headers(source_root):
    path = source_root / "src/data/tilesets/headers.h"
    if not path.exists():
        return {
            "tileset_header_count": 0,
            "tileset_callback_count": 0,
            "tileset_null_callback_count": 0,
            "callback_symbols": [],
        }
    callbacks = [
        item.strip()
        for item in re.findall(r"\.callback\s*=\s*([^,]+)", read_text(path))
    ]
    callback_symbols = sorted({item for item in callbacks if item != "NULL"})
    return {
        "tileset_header_count": len(callbacks),
        "tileset_callback_count": len(callback_symbols),
        "tileset_null_callback_count": sum(1 for item in callbacks if item == "NULL"),
        "callback_symbols": callback_symbols,
    }


def parse_tileset_anim_sources(source_root):
    path = source_root / "src/tileset_anims.c"
    if not path.exists():
        return {
            "tileset_anim_init_function_count": 0,
            "tileset_anim_source_frame_count": 0,
            "tileset_anim_source_group_count": 0,
        }
    text = read_text(path)
    init_functions = set(re.findall(r"void\s+(InitTilesetAnim_[A-Za-z0-9_]+)\s*\(", text))
    frame_declarations = re.findall(
        r"(?:static\s+)?const\s+u16\s+((?:g|s)TilesetAnims_[A-Za-z0-9_]+)"
        r"\[\]\s*=\s*INCBIN_U16\((.*?)\);",
        text,
        re.S,
    )
    source_frames = [
        path_text
        for _, body in frame_declarations
        for path_text in re.findall(r'"([^"]+)"', body)
    ]
    return {
        "tileset_anim_init_function_count": len(init_functions),
        "tileset_anim_source_frame_count": len(source_frames),
        "tileset_anim_source_group_count": len({symbol for symbol, _ in frame_declarations}),
    }


def parse_tileset_palette_sources(source_root):
    source_files = [
        "src/data/tilesets/graphics.h",
        "src/graphics.c",
    ]
    texts = []
    for source_file in source_files:
        path = source_root / source_file
        if path.exists():
            texts.append(read_text(path))
    text = "\n".join(texts)
    palette_refs = re.findall(r'"(data/tilesets/[^"]+/palettes/\d+\.gbapal)"', text)
    palette_arrays = re.findall(
        r"const\s+u16\s+(?:ALIGNED\(\d+\)\s+)?"
        r"(gTilesetPalettes_[A-Za-z0-9_]+)"
        r"\s*\[\]\[16\]\s*=\s*\{",
        text,
    )
    return {
        "tileset_palette_reference_count": len(palette_refs),
        "tileset_unique_palette_reference_count": len(set(palette_refs)),
        "tileset_palette_array_symbol_count": len(set(palette_arrays)),
    }


def count_source_tileset_tile_images(source_root):
    paths = sorted(source_root.glob("data/tilesets/**/tiles.png"))
    tile_count = 0
    invalid = 0
    for path in paths:
        try:
            width, height = read_png_dimensions(path)
        except ValueError:
            invalid += 1
            continue
        if width % TILE_SIZE_PIXELS != 0 or height % TILE_SIZE_PIXELS != 0:
            invalid += 1
            continue
        tile_count += (width // TILE_SIZE_PIXELS) * (height // TILE_SIZE_PIXELS)
    return {
        "tileset_tile_image_count": len(paths),
        "tileset_tile_image_tile_count": tile_count,
        "tileset_invalid_tile_image_count": invalid,
    }


def count_source_tileset_metatile_binaries(source_root):
    paths = sorted(source_root.glob("data/tilesets/*/*/metatiles.bin"))
    metatile_count = 0
    tile_entry_count = 0
    invalid_paths = []
    for path in paths:
        byte_count = path.stat().st_size
        if byte_count % 16 != 0:
            invalid_paths.append(to_project_path(path.relative_to(source_root)))
            continue
        file_metatile_count = byte_count // 16
        metatile_count += file_metatile_count
        tile_entry_count += file_metatile_count * 8
    return {
        "tileset_metatile_binary_count": len(paths),
        "tileset_metatile_record_count": metatile_count,
        "tileset_metatile_tile_entry_count": tile_entry_count,
        "tileset_invalid_metatile_binary_count": len(invalid_paths),
        "tileset_invalid_metatile_binary_paths": invalid_paths,
    }


def count_source_tileset_metatile_attribute_binaries(source_root):
    paths = sorted(source_root.glob("data/tilesets/*/*/metatile_attributes.bin"))
    attribute_count = 0
    invalid_paths = []
    profile_counts = {
        "emerald_u16": 0,
        "frlg_u32": 0,
    }
    for path in paths:
        byte_count = path.stat().st_size
        record_byte_count = metatile_attribute_record_byte_count_for_path(path)
        profile_key = "frlg_u32" if record_byte_count == 4 else "emerald_u16"
        profile_counts[profile_key] += 1
        if byte_count % record_byte_count != 0:
            invalid_paths.append(to_project_path(path.relative_to(source_root)))
            continue
        attribute_count += byte_count // record_byte_count
    return {
        "tileset_metatile_attribute_binary_count": len(paths),
        "tileset_metatile_attribute_record_count": attribute_count,
        "tileset_metatile_attribute_binary_count_by_source_profile": profile_counts,
        "tileset_invalid_metatile_attribute_binary_count": len(invalid_paths),
        "tileset_invalid_metatile_attribute_binary_paths": invalid_paths,
    }


def metatile_attribute_record_byte_count_for_path(path):
    tileset_dir = path.parent.name
    return 4 if tileset_dir.endswith("_frlg") else 2


def count_source_metatile_labels(source_root):
    path = source_root / "include/constants/metatile_labels.h"
    if not path.exists():
        return {
            "tileset_metatile_label_count": 0,
            "tileset_metatile_label_source_group_count": 0,
        }
    groups = {}
    current_group = None
    for line_index, raw_line in enumerate(read_text(path).splitlines(), 1):
        comment_match = re.match(r"^\s*//\s*(.*?)\s*$", raw_line)
        if comment_match:
            current_group = comment_match.group(1).strip() or None
            if current_group:
                groups.setdefault(current_group, {
                    "line": line_index,
                    "label_count": 0,
                })
            continue
        if not METATILE_LABEL_RE.match(raw_line):
            continue
        if current_group is None:
            current_group = "Ungrouped"
            groups.setdefault(current_group, {
                "line": line_index,
                "label_count": 0,
            })
        groups[current_group]["label_count"] += 1
    return {
        "tileset_metatile_label_count": sum(group["label_count"] for group in groups.values()),
        "tileset_metatile_label_source_group_count": sum(
            1
            for group in groups.values()
            if group["label_count"] > 0
        ),
    }


def parse_active_emerald_door_table(source_root):
    path = source_root / "src/field_door.c"
    if not path.exists():
        return {
            "door_animation_table_entry_count": 0,
            "door_animation_source_image_count": 0,
        }
    text = read_text(path)
    source_images = re.findall(r'INCBIN_U8\("graphics/door_anims/[^"]+\.4bpp"\)', text)
    active_block = _active_emerald_block(text, "static const struct DoorGraphics sDoorAnimGraphicsTable[]")
    active_rows = [
        line
        for line in active_block.splitlines()
        if re.match(r"\s*\{[^}]", line) and not re.match(r"\s*\{\s*\}", line)
    ]
    return {
        "door_animation_table_entry_count": len(active_rows),
        "door_animation_source_image_count": len(source_images),
    }


def _active_emerald_block(text, marker):
    start = text.find(marker)
    if start < 0:
        return ""
    table = text[start:]
    end = table.find("};")
    if end >= 0:
        table = table[:end]
    marker_index = table.find("#if !IS_FRLG")
    if marker_index < 0:
        return table
    table = table[marker_index + len("#if !IS_FRLG"):]
    else_index = table.find("#else")
    if else_index >= 0:
        table = table[:else_index]
    return table


def count_source_object_event_graphics(source_root):
    path = source_root / "src/data/object_events/object_event_graphics_info.h"
    if not path.exists():
        return 0
    return len(re.findall(r"const struct ObjectEventGraphicsInfo\s+gObjectEventGraphicsInfo_", read_text(path)))


def resolve_project_path(project_root, path_text):
    path = Path(path_text)
    if path.is_absolute():
        return path
    return project_root / path


def load_generated_json(project_root, path_text):
    path = resolve_project_path(project_root, path_text)
    if not path.exists():
        return None
    return read_json(path)


def load_overworld_report(project_root, manifest, category):
    for entry in manifest.get("overworld_reports", []):
        if entry.get("category") != category:
            continue
        return load_generated_json(project_root, entry.get("path", ""))
    return None


def count_recursive_warning_arrays(value):
    if isinstance(value, dict):
        total = 0
        for key, child in value.items():
            if key == "warnings" and isinstance(child, list):
                total += len(child)
            else:
                total += count_recursive_warning_arrays(child)
        return total
    if isinstance(value, list):
        return sum(count_recursive_warning_arrays(item) for item in value)
    return 0


def count_manifest_warning_fields(entries):
    total = 0
    for entry in entries:
        if not isinstance(entry, dict):
            continue
        for key, value in entry.items():
            if key.endswith("warning_count") and isinstance(value, int):
                total += value
    return total


def count_object_sprite_unsupported(data):
    if not isinstance(data, dict):
        return 0
    return sum(len(sprite.get("unsupported", [])) for sprite in data.get("sprites", {}).values())


def len_list(value):
    return len(value) if isinstance(value, list) else 0


def count_script_bundle(data):
    movements = data.get("movements", {}) if isinstance(data, dict) else {}
    movement_action_count = 0
    movement_step_end_count = 0
    movement_op_counts = {}
    for movement in movements.values():
        instructions = movement.get("instructions", [])
        movement_action_count += len(instructions)
        for instruction in instructions:
            op = instruction.get("op")
            if op is None:
                continue
            movement_op_counts[op] = movement_op_counts.get(op, 0) + 1
            if op == "step_end":
                movement_step_end_count += 1
    stats = data.get("stats", {}) if isinstance(data, dict) else {}
    runtime_preview = data.get("runtime_preview", {}) if isinstance(data, dict) else {}
    unsupported_op_counts = runtime_preview.get("unsupported_op_counts", {})
    return {
        "script_count": int(stats.get("script_count", 0)),
        "movement_label_count": len(movements),
        "movement_action_count": movement_action_count,
        "movement_step_end_count": movement_step_end_count,
        "movement_action_count_excluding_step_end": movement_action_count - movement_step_end_count,
        "text_count": int(stats.get("text_count", 0)),
        "charmap_warning_count": int(stats.get("charmap_warning_count", 0)),
        "orphan_instruction_count": int(stats.get("orphan_instruction_count", 0)),
        "runtime_preview_unsupported_op_count": sum(
            value for value in unsupported_op_counts.values() if isinstance(value, int)
        ),
        "movement_op_counts": movement_op_counts,
    }


def sum_script_bundles(project_root, script_entries):
    totals = {
        "script_bundle_count": len(script_entries),
        "script_count": 0,
        "movement_label_count": 0,
        "movement_action_count": 0,
        "movement_step_end_count": 0,
        "movement_action_count_excluding_step_end": 0,
        "text_count": 0,
        "charmap_warning_count": 0,
        "orphan_instruction_count": 0,
        "runtime_preview_unsupported_op_count": 0,
        "movement_op_counts": {},
        "missing_script_bundle_count": 0,
    }
    bundles = []
    for entry in script_entries:
        data = load_generated_json(project_root, entry.get("path", ""))
        if data is None:
            totals["missing_script_bundle_count"] += 1
            continue
        summary = count_script_bundle(data)
        bundles.append({
            "name": entry.get("map") or entry.get("name"),
            "scope": entry.get("scope", "map"),
            "path": entry.get("path"),
            "script_count": summary["script_count"],
            "movement_label_count": summary["movement_label_count"],
            "movement_action_count": summary["movement_action_count"],
            "movement_action_count_excluding_step_end": summary["movement_action_count_excluding_step_end"],
            "runtime_preview_unsupported_op_count": summary["runtime_preview_unsupported_op_count"],
        })
        for key in [
            "script_count",
            "movement_label_count",
            "movement_action_count",
            "movement_step_end_count",
            "movement_action_count_excluding_step_end",
            "text_count",
            "charmap_warning_count",
            "orphan_instruction_count",
            "runtime_preview_unsupported_op_count",
        ]:
            totals[key] += summary[key]
        for op, count in summary["movement_op_counts"].items():
            totals["movement_op_counts"][op] = totals["movement_op_counts"].get(op, 0) + count
    totals["movement_op_counts"] = dict(sorted(totals["movement_op_counts"].items()))
    return totals, bundles


def count_generated_maps(project_root, map_entries):
    event_totals = {
        "object_event_count": 0,
        "warp_event_count": 0,
        "coord_event_count": 0,
        "bg_event_count": 0,
        "connection_count": 0,
        "missing_map_file_count": 0,
    }
    map_summaries = []
    for entry in map_entries:
        data = load_generated_json(project_root, entry.get("path", ""))
        if data is None:
            event_totals["missing_map_file_count"] += 1
            continue
        events = data.get("events", {})
        summary = {
            "id": entry.get("id"),
            "name": entry.get("name"),
            "layout_id": entry.get("layout_id"),
            "path": entry.get("path"),
            "map_type": data.get("map", {}).get("map_type"),
            "weather": data.get("map", {}).get("weather"),
            "music": data.get("map", {}).get("music"),
            "object_event_count": len_list(events.get("object_events")),
            "warp_event_count": len_list(events.get("warp_events")),
            "coord_event_count": len_list(events.get("coord_events")),
            "bg_event_count": len_list(events.get("bg_events")),
            "connection_count": len_list(events.get("connections")),
        }
        map_summaries.append(summary)
        for key in [
            "object_event_count",
            "warp_event_count",
            "coord_event_count",
            "bg_event_count",
            "connection_count",
        ]:
            event_totals[key] += summary[key]
    return event_totals, map_summaries


def count_generated_layouts(project_root, layout_entries):
    totals = {
        "layout_count": len(layout_entries),
        "missing_layout_file_count": 0,
        "map_grid_entry_count": 0,
        "border_entry_count": 0,
        "warning_array_count": 0,
    }
    layout_summaries = []
    for entry in layout_entries:
        data = load_generated_json(project_root, entry.get("path", ""))
        if data is None:
            totals["missing_layout_file_count"] += 1
            continue
        layout = data.get("layout", {})
        block_stats = data.get("block_id_stats", {})
        border_grid = data.get("border_grid", {})
        warning_count = count_recursive_warning_arrays(data)
        summary = {
            "id": entry.get("id") or layout.get("id"),
            "name": entry.get("name") or layout.get("name"),
            "path": entry.get("path"),
            "width": layout.get("width"),
            "height": layout.get("height"),
            "layout_version": layout.get("layout_version"),
            "primary_tileset": layout.get("primary_tileset"),
            "secondary_tileset": layout.get("secondary_tileset"),
            "map_grid_entry_count": int(block_stats.get("count", 0)),
            "border_entry_count": len_list(border_grid.get("raw")),
            "referenced_map_count": int(entry.get("referenced_map_count", 0)),
            "warning_array_count": warning_count,
        }
        layout_summaries.append(summary)
        totals["map_grid_entry_count"] += summary["map_grid_entry_count"]
        totals["border_entry_count"] += summary["border_entry_count"]
        totals["warning_array_count"] += warning_count
    return totals, layout_summaries


def count_generated_tilesets(project_root, tileset_entries):
    totals = {
        "tileset_record_count": len(tileset_entries),
        "unique_primary_tileset_count": 0,
        "unique_secondary_tileset_count": 0,
        "metatile_record_count": 0,
        "door_animation_count": 0,
        "door_animation_frame_count": 0,
        "tileset_animation_count": 0,
        "warning_array_count": 0,
        "missing_tileset_file_count": 0,
        "flattened_debug_atlas_count": 0,
        "runtime_layering_source_equivalent_atlas_count": 0,
        "runtime_layering_non_equivalent_atlas_count": 0,
        "runtime_layering_metadata_missing_count": 0,
        "layer_rendering_tileset_count": 0,
        "layer_rendering_missing_count": 0,
        "layer_rendering_atlas_count": 0,
        "layer_rendering_missing_atlas_image_count": 0,
        "layer_rendering_metatile_count": 0,
        "layer_rendering_missing_metatile_record_count": 0,
    }
    primary = set()
    secondary = set()
    tileset_summaries = []
    for entry in tileset_entries:
        data = load_generated_json(project_root, entry.get("path", ""))
        if data is None:
            totals["missing_tileset_file_count"] += 1
            continue
        primary_symbol = entry.get("primary_tileset")
        secondary_symbol = entry.get("secondary_tileset")
        if primary_symbol:
            primary.add(primary_symbol)
        if secondary_symbol:
            secondary.add(secondary_symbol)
        door_animations = data.get("door_animations", {})
        animations = door_animations.get("animations", [])
        frame_count = sum(len(animation.get("frames", [])) for animation in animations)
        warning_count = count_recursive_warning_arrays(data)
        atlas_info = data.get("atlas", {})
        if not isinstance(atlas_info, dict):
            atlas_info = {}
        atlas_artifact_kind = str(
            atlas_info.get("artifact_kind", entry.get("atlas_artifact_kind", ""))
        )
        atlas_debug_only = bool(atlas_info.get("debug_only", entry.get("atlas_debug_only", False)))
        source_equivalent = atlas_info.get(
            "source_equivalent_for_runtime_layering",
            entry.get("atlas_source_equivalent_for_runtime_layering"),
        )
        runtime_layering_status = str(
            atlas_info.get("runtime_layering_status", entry.get("atlas_runtime_layering_status", ""))
        )
        atlas_unsupported_code = str(
            atlas_info.get("unsupported_code", entry.get("atlas_unsupported_code", ""))
        )
        if atlas_artifact_kind == "flattened_metatile_debug_atlas" and atlas_debug_only:
            totals["flattened_debug_atlas_count"] += 1
        if source_equivalent is True:
            totals["runtime_layering_source_equivalent_atlas_count"] += 1
        elif source_equivalent is False:
            totals["runtime_layering_non_equivalent_atlas_count"] += 1
        else:
            totals["runtime_layering_metadata_missing_count"] += 1
        layer_rendering = data.get("layer_rendering", {})
        if not isinstance(layer_rendering, dict) or not layer_rendering:
            totals["layer_rendering_missing_count"] += 1
            layer_rendering_status = ""
            layer_rendering_atlas_count = 0
            layer_rendering_metatile_count = 0
            layer_rendering_missing_records = 0
            missing_layer_atlas_images = 0
        else:
            totals["layer_rendering_tileset_count"] += 1
            policy = layer_rendering.get("policy", {})
            if not isinstance(policy, dict):
                policy = {}
            layer_rendering_status = str(policy.get(
                "runtime_layering_status",
                entry.get("layer_rendering_status", ""),
            ))
            layer_atlases = layer_rendering.get("layer_atlases", {})
            if not isinstance(layer_atlases, dict):
                layer_atlases = {}
            layer_rendering_atlas_count = len(layer_atlases)
            missing_layer_atlas_images = 0
            for atlas_record in layer_atlases.values():
                if not isinstance(atlas_record, dict):
                    missing_layer_atlas_images += 1
                    continue
                image_path = atlas_record.get("image_project_path", "")
                if not image_path or not resolve_project_path(project_root, image_path).exists():
                    missing_layer_atlas_images += 1
            layer_summary = layer_rendering.get("summary", {})
            if not isinstance(layer_summary, dict):
                layer_summary = {}
            layer_rendering_metatile_count = int(layer_summary.get("metatile_count", 0))
            layer_rendering_missing_records = int(
                layer_summary.get("missing_render_layer_record_count", 0)
            )
            totals["layer_rendering_atlas_count"] += layer_rendering_atlas_count
            totals["layer_rendering_missing_atlas_image_count"] += missing_layer_atlas_images
            totals["layer_rendering_metatile_count"] += layer_rendering_metatile_count
            totals["layer_rendering_missing_metatile_record_count"] += layer_rendering_missing_records
        summary = {
            "map": entry.get("map"),
            "path": entry.get("path"),
            "primary_tileset": primary_symbol,
            "secondary_tileset": secondary_symbol,
            "total_metatiles": int(entry.get("total_metatiles", 0)),
            "atlas_artifact_kind": atlas_artifact_kind,
            "atlas_debug_only": atlas_debug_only,
            "atlas_source_equivalent_for_runtime_layering": source_equivalent,
            "atlas_runtime_layering_status": runtime_layering_status,
            "atlas_unsupported_code": atlas_unsupported_code,
            "layer_rendering_status": layer_rendering_status,
            "layer_rendering_atlas_count": layer_rendering_atlas_count,
            "layer_rendering_missing_atlas_image_count": missing_layer_atlas_images,
            "layer_rendering_metatile_count": layer_rendering_metatile_count,
            "layer_rendering_missing_metatile_record_count": layer_rendering_missing_records,
            "door_animation_count": len(animations),
            "door_animation_frame_count": frame_count,
            "warning_array_count": warning_count,
        }
        tileset_summaries.append(summary)
        totals["metatile_record_count"] += int(entry.get("total_metatiles", 0))
        totals["door_animation_count"] += len(animations)
        totals["door_animation_frame_count"] += frame_count
        totals["warning_array_count"] += warning_count
    totals["unique_primary_tileset_count"] = len(primary)
    totals["unique_secondary_tileset_count"] = len(secondary)
    return totals, tileset_summaries


def ratio(generated, source):
    if not source:
        return {
            "generated": generated,
            "source": source,
            "percent": None,
        }
    return {
        "generated": generated,
        "source": source,
        "percent": round((generated / float(source)) * 100.0, 2),
    }


def build_source_counts(source_root):
    tileset_header_info = parse_tileset_headers(source_root)
    tileset_anim_info = parse_tileset_anim_sources(source_root)
    tileset_palette_info = parse_tileset_palette_sources(source_root)
    door_info = parse_active_emerald_door_table(source_root)
    counts = {
        "map_count": count_files(source_root, "data/maps/*/map.json"),
        "map_script_file_count": count_files(source_root, "data/maps/*/scripts.inc"),
        "layout_count": count_source_layouts(source_root),
        "primary_tileset_image_count": count_files(source_root, "data/tilesets/primary/*/tiles.png"),
        "secondary_tileset_image_count": count_files(source_root, "data/tilesets/secondary/*/tiles.png"),
        "object_event_graphics_info_count": count_source_object_event_graphics(source_root),
    }
    counts.update(tileset_header_info)
    counts.update(tileset_anim_info)
    counts.update(tileset_palette_info)
    counts.update(count_source_layout_blockdata_entries(source_root))
    counts.update(count_source_layout_tileset_pairs(source_root))
    counts.update(count_source_tileset_tile_images(source_root))
    counts.update(count_source_tileset_metatile_binaries(source_root))
    counts.update(count_source_tileset_metatile_attribute_binaries(source_root))
    counts.update(count_source_metatile_labels(source_root))
    counts.update(door_info)
    return counts


def build_export(source_root, output_root):
    output_root = output_root.resolve()
    project_root = output_root.parent.parent
    manifest_path = output_root / "import_manifest.json"
    manifest = read_json(manifest_path) if manifest_path.exists() else {}
    source_counts = build_source_counts(source_root)

    map_entries = manifest.get("maps", [])
    layout_entries = manifest.get("layouts", [])
    tileset_entries = manifest.get("tilesets", [])
    script_entries = manifest.get("scripts", [])
    object_sprite_entries = manifest.get("object_event_sprites", [])
    map_script_bundle_count = sum(1 for entry in script_entries if entry.get("map"))
    shared_script_bundle_count = sum(1 for entry in script_entries if entry.get("scope") == "shared")

    map_event_totals, map_summaries = count_generated_maps(project_root, map_entries)
    layout_totals, layout_summaries = count_generated_layouts(project_root, layout_entries)
    tileset_totals, tileset_summaries = count_generated_tilesets(project_root, tileset_entries)
    script_totals, script_summaries = sum_script_bundles(project_root, script_entries)

    unique_layouts = sorted({
        entry.get("layout_id")
        for entry in map_entries
        if entry.get("layout_id")
    })
    generated_layout_count = layout_totals["layout_count"] if layout_entries else len(unique_layouts)

    object_sprite_data = None
    object_sprite_count = 0
    object_sprite_unsupported_count = 0
    if object_sprite_entries:
        object_sprite_data = load_generated_json(project_root, object_sprite_entries[0].get("path", ""))
    if isinstance(object_sprite_data, dict):
        object_sprite_count = int(object_sprite_data.get("stats", {}).get("sprite_count", 0))
        object_sprite_unsupported_count = count_object_sprite_unsupported(object_sprite_data)

    tileset_header_report = load_overworld_report(
        project_root,
        manifest,
        "overworld_tileset_header_report",
    )
    tileset_header_stats = (
        tileset_header_report.get("stats", {})
        if isinstance(tileset_header_report, dict)
        else {}
    )
    tileset_header_report_count = 1 if isinstance(tileset_header_report, dict) else 0
    tileset_header_record_count = int(tileset_header_stats.get("total_header_count", 0))
    active_tileset_header_record_count = int(tileset_header_stats.get("active_emerald_header_count", 0))
    tileset_animation_frame_declaration_count = int(
        tileset_header_stats.get("animation_frame_declaration_count", 0)
    )
    tileset_animation_source_image_count = int(
        tileset_header_stats.get("animation_existing_editable_source_candidate_count", 0)
    )
    tileset_palette_slot_mapping_count = int(
        tileset_header_stats.get("palette_slot_mapping_count", 0)
    )
    active_tileset_palette_slot_mapping_count = int(
        tileset_header_stats.get("active_palette_slot_mapping_count", 0)
    )
    tileset_loaded_palette_slot_mapping_count = int(
        tileset_header_stats.get("loaded_palette_slot_mapping_count", 0)
    )
    active_tileset_loaded_palette_slot_mapping_count = int(
        tileset_header_stats.get("active_loaded_palette_slot_mapping_count", 0)
    )
    tileset_palette_source_candidate_count = int(
        tileset_header_stats.get("palette_editable_source_candidate_count", 0)
    )
    tileset_existing_palette_source_candidate_count = int(
        tileset_header_stats.get("palette_existing_editable_source_candidate_count", 0)
    )
    tileset_missing_palette_source_candidate_count = int(
        tileset_header_stats.get("palette_missing_editable_source_candidate_count", 0)
    )
    tileset_header_missing_callback_source_count = int(
        tileset_header_stats.get("missing_callback_source_count", 0)
    )
    tileset_callback_map_layout_count = int(
        tileset_header_stats.get("callback_map_layout_count", 0)
    )
    tileset_callback_map_map_count = int(
        tileset_header_stats.get("callback_map_map_count", 0)
    )
    tileset_callback_map_grouped_map_count = int(
        tileset_header_stats.get("callback_map_grouped_map_count", 0)
    )
    tileset_callback_map_ungrouped_map_count = int(
        tileset_header_stats.get("callback_map_ungrouped_map_count", 0)
    )
    tileset_callback_map_layout_with_map_count = int(
        tileset_header_stats.get("callback_map_layout_with_map_count", 0)
    )
    tileset_callback_map_standalone_layout_count = int(
        tileset_header_stats.get("callback_map_standalone_layout_count", 0)
    )
    tileset_callback_map_pair_count = int(
        tileset_header_stats.get("callback_map_pair_count", 0)
    )
    tileset_callback_map_tileset_usage_count = int(
        tileset_header_stats.get("callback_map_tileset_usage_count", 0)
    )
    tileset_callback_map_tileset_with_callback_count = int(
        tileset_header_stats.get("callback_map_tileset_with_callback_count", 0)
    )
    tileset_callback_map_callback_symbol_count = int(
        tileset_header_stats.get("callback_map_callback_symbol_count", 0)
    )
    tileset_callback_map_callback_with_map_count = int(
        tileset_header_stats.get("callback_map_callback_with_map_count", 0)
    )
    tileset_callback_map_missing_header_tileset_count = int(
        tileset_header_stats.get("callback_map_missing_header_tileset_count", 0)
    )
    tileset_header_metatile_decode_count = int(
        tileset_header_stats.get("metatile_decode_header_count", 0)
    )
    tileset_header_active_metatile_decode_count = int(
        tileset_header_stats.get("active_metatile_decode_header_count", 0)
    )
    tileset_header_metatile_record_count = int(
        tileset_header_stats.get("metatile_record_count", 0)
    )
    tileset_header_active_metatile_record_count = int(
        tileset_header_stats.get("active_metatile_record_count", 0)
    )
    tileset_header_metatile_tile_entry_count = int(
        tileset_header_stats.get("metatile_tile_entry_count", 0)
    )
    tileset_header_unique_metatile_source_binary_count = int(
        tileset_header_stats.get("unique_metatile_source_binary_count", 0)
    )
    tileset_header_unique_metatile_record_count = int(
        tileset_header_stats.get("unique_metatile_record_count", 0)
    )
    tileset_header_unique_metatile_tile_entry_count = int(
        tileset_header_stats.get("unique_metatile_tile_entry_count", 0)
    )
    tileset_header_active_metatile_tile_entry_count = int(
        tileset_header_stats.get("active_metatile_tile_entry_count", 0)
    )
    tileset_header_metatile_out_of_range_tile_entry_count = int(
        tileset_header_stats.get("metatile_out_of_range_tile_entry_count", 0)
    )
    tileset_header_metatile_attribute_decode_count = int(
        tileset_header_stats.get("metatile_attribute_decode_header_count", 0)
    )
    tileset_header_active_metatile_attribute_decode_count = int(
        tileset_header_stats.get("active_metatile_attribute_decode_header_count", 0)
    )
    tileset_header_metatile_attribute_record_count = int(
        tileset_header_stats.get("metatile_attribute_record_count", 0)
    )
    tileset_header_active_metatile_attribute_record_count = int(
        tileset_header_stats.get("active_metatile_attribute_record_count", 0)
    )
    tileset_header_unique_metatile_attribute_source_binary_count = int(
        tileset_header_stats.get("unique_metatile_attribute_source_binary_count", 0)
    )
    tileset_header_unique_metatile_attribute_record_count = int(
        tileset_header_stats.get("unique_metatile_attribute_record_count", 0)
    )
    tileset_header_metatile_attribute_encounter_affordance_count = int(
        tileset_header_stats.get("metatile_attribute_encounter_affordance_count", 0)
    )
    tileset_header_active_metatile_attribute_encounter_affordance_count = int(
        tileset_header_stats.get("active_metatile_attribute_encounter_affordance_count", 0)
    )
    tileset_header_metatile_attribute_missing_behavior_name_count = int(
        tileset_header_stats.get("metatile_attribute_missing_behavior_name_count", 0)
    )
    tileset_header_metatile_label_source_label_count = int(
        tileset_header_stats.get("metatile_label_source_label_count", 0)
    )
    tileset_header_metatile_label_source_group_count = int(
        tileset_header_stats.get("metatile_label_source_group_count", 0)
    )
    tileset_header_metatile_label_decode_count = int(
        tileset_header_stats.get("metatile_label_header_decode_count", 0)
    )
    tileset_header_active_metatile_label_decode_count = int(
        tileset_header_stats.get("active_metatile_label_header_decode_count", 0)
    )
    tileset_header_metatile_label_record_count = int(
        tileset_header_stats.get("metatile_label_record_count", 0)
    )
    tileset_header_active_metatile_label_record_count = int(
        tileset_header_stats.get("active_metatile_label_record_count", 0)
    )
    tileset_header_metatile_label_pair_lookup_count = int(
        tileset_header_stats.get("metatile_label_pair_lookup_count", 0)
    )
    tileset_header_metatile_label_pair_lookup_layout_count = int(
        tileset_header_stats.get("metatile_label_pair_lookup_layout_count", 0)
    )
    tileset_header_metatile_label_pair_label_record_count = int(
        tileset_header_stats.get("metatile_label_pair_label_record_count", 0)
    )
    tileset_header_metatile_label_pair_out_of_range_count = int(
        tileset_header_stats.get("metatile_label_pair_out_of_range_count", 0)
    )
    tileset_header_metatile_map_reference_layout_count = int(
        tileset_header_stats.get("metatile_map_reference_layout_count", 0)
    )
    tileset_header_metatile_map_reference_checked_layout_count = int(
        tileset_header_stats.get("metatile_map_reference_checked_layout_count", 0)
    )
    tileset_header_metatile_map_reference_pair_count = int(
        tileset_header_stats.get("metatile_map_reference_pair_count", 0)
    )
    tileset_header_metatile_map_reference_checked_cell_count = int(
        tileset_header_stats.get("metatile_map_reference_checked_cell_count", 0)
    )
    tileset_header_metatile_map_reference_declared_cell_count = int(
        tileset_header_stats.get("metatile_map_reference_declared_cell_count", 0)
    )
    tileset_header_metatile_map_reference_unique_metatile_id_count = int(
        tileset_header_stats.get("metatile_map_reference_unique_metatile_id_count", 0)
    )
    tileset_header_metatile_map_reference_absent_cell_count = int(
        tileset_header_stats.get("metatile_map_reference_absent_cell_count", 0)
    )
    tileset_header_metatile_map_reference_absent_unique_reference_count = int(
        tileset_header_stats.get("metatile_map_reference_absent_unique_reference_count", 0)
    )
    tileset_header_metatile_map_reference_absent_global_metatile_id_count = int(
        tileset_header_stats.get("metatile_map_reference_absent_global_metatile_id_count", 0)
    )
    tileset_header_metatile_map_reference_layout_with_absent_count = int(
        tileset_header_stats.get("metatile_map_reference_layout_with_absent_count", 0)
    )
    tileset_header_metatile_map_reference_pair_with_absent_count = int(
        tileset_header_stats.get("metatile_map_reference_pair_with_absent_count", 0)
    )
    tileset_header_metatile_map_reference_missing_blockdata_layout_count = int(
        tileset_header_stats.get("metatile_map_reference_missing_blockdata_layout_count", 0)
    )
    tileset_header_metatile_map_reference_invalid_blockdata_layout_count = int(
        tileset_header_stats.get("metatile_map_reference_invalid_blockdata_layout_count", 0)
    )
    tileset_header_metatile_map_reference_size_mismatch_layout_count = int(
        tileset_header_stats.get("metatile_map_reference_size_mismatch_layout_count", 0)
    )
    tileset_header_tile_image_reference_header_count = int(
        tileset_header_stats.get("metatile_tile_image_reference_header_count", 0)
    )
    tileset_header_tile_image_reference_header_image_binding_count = int(
        tileset_header_stats.get("metatile_tile_image_reference_header_image_binding_count", 0)
    )
    tileset_header_tile_image_reference_decoded_image_binding_count = int(
        tileset_header_stats.get("metatile_tile_image_reference_decoded_image_binding_count", 0)
    )
    tileset_header_tile_image_reference_unique_source_image_count = int(
        tileset_header_stats.get("metatile_tile_image_reference_unique_source_image_count", 0)
    )
    tileset_header_tile_image_reference_unique_source_image_tile_count = int(
        tileset_header_stats.get("metatile_tile_image_reference_unique_source_image_tile_count", 0)
    )
    tileset_header_tile_image_reference_header_checked_tile_entry_count = int(
        tileset_header_stats.get("metatile_tile_image_reference_header_checked_tile_entry_count", 0)
    )
    tileset_header_tile_image_reference_header_foreign_tile_entry_count = int(
        tileset_header_stats.get("metatile_tile_image_reference_header_foreign_tile_entry_count", 0)
    )
    tileset_header_tile_image_reference_header_absent_tile_entry_count = int(
        tileset_header_stats.get("metatile_tile_image_reference_header_absent_tile_entry_count", 0)
    )
    tileset_header_tile_image_reference_header_absent_unique_tile_reference_count = int(
        tileset_header_stats.get("metatile_tile_image_reference_header_absent_unique_tile_reference_count", 0)
    )
    tileset_header_tile_image_reference_header_with_absent_tile_count = int(
        tileset_header_stats.get("metatile_tile_image_reference_header_with_absent_tile_count", 0)
    )
    tileset_header_tile_image_reference_pair_count = int(
        tileset_header_stats.get("metatile_tile_image_reference_pair_count", 0)
    )
    tileset_header_tile_image_reference_pair_checked_tile_entry_count = int(
        tileset_header_stats.get("metatile_tile_image_reference_pair_checked_tile_entry_count", 0)
    )
    tileset_header_tile_image_reference_pair_absent_tile_entry_count = int(
        tileset_header_stats.get("metatile_tile_image_reference_pair_absent_tile_entry_count", 0)
    )
    tileset_header_tile_image_reference_pair_absent_unique_tile_reference_count = int(
        tileset_header_stats.get("metatile_tile_image_reference_pair_absent_unique_tile_reference_count", 0)
    )
    tileset_header_tile_image_reference_pair_with_absent_tile_count = int(
        tileset_header_stats.get("metatile_tile_image_reference_pair_with_absent_tile_count", 0)
    )
    tileset_header_tile_image_reference_pair_missing_header_count = int(
        tileset_header_stats.get("metatile_tile_image_reference_pair_missing_header_count", 0)
    )

    parity_matrix = load_generated_json(project_root, "data/generated/overworld/parity_matrix.json") or {}
    parity_stats = parity_matrix.get("stats", {})

    manifest_warning_count = count_manifest_warning_fields(
        manifest.get("scripts", [])
        + manifest.get("tilesets", [])
        + manifest.get("object_event_sprites", [])
    )
    generated_warning_array_count = layout_totals["warning_array_count"] + tileset_totals["warning_array_count"]
    if object_sprite_data:
        generated_warning_array_count += count_recursive_warning_arrays(object_sprite_data)
    warning_count = manifest_warning_count + generated_warning_array_count

    explicit_unsupported = build_explicit_unsupported(
        source_counts,
        {
            "tileset_record_count": tileset_totals["tileset_record_count"],
            "tileset_flattened_debug_atlas_count": tileset_totals["flattened_debug_atlas_count"],
            "tileset_layer_rendering_tileset_count": tileset_totals["layer_rendering_tileset_count"],
            "door_animation_count": tileset_totals["door_animation_count"],
            "tileset_animation_count": tileset_totals["tileset_animation_count"],
            "object_event_graphic_count": object_sprite_count,
        },
    )

    generated_counts = {
        "map_count": len(map_entries),
        "layout_count": generated_layout_count,
        "map_referenced_layout_count": len(unique_layouts),
        "standalone_layout_count": max(0, generated_layout_count - len(unique_layouts)),
        "missing_layout_file_count": layout_totals["missing_layout_file_count"],
        "layout_map_grid_entry_count": layout_totals["map_grid_entry_count"],
        "layout_border_entry_count": layout_totals["border_entry_count"],
        "layout_warning_count": layout_totals["warning_array_count"],
        "tileset_record_count": tileset_totals["tileset_record_count"],
        "unique_primary_tileset_count": tileset_totals["unique_primary_tileset_count"],
        "unique_secondary_tileset_count": tileset_totals["unique_secondary_tileset_count"],
        "tileset_header_report_count": tileset_header_report_count,
        "tileset_header_record_count": tileset_header_record_count,
        "active_emerald_tileset_header_record_count": active_tileset_header_record_count,
        "tileset_animation_frame_declaration_count": tileset_animation_frame_declaration_count,
        "tileset_animation_source_image_count": tileset_animation_source_image_count,
        "tileset_palette_slot_mapping_count": tileset_palette_slot_mapping_count,
        "active_emerald_tileset_palette_slot_mapping_count": active_tileset_palette_slot_mapping_count,
        "tileset_loaded_palette_slot_mapping_count": tileset_loaded_palette_slot_mapping_count,
        "active_emerald_tileset_loaded_palette_slot_mapping_count": active_tileset_loaded_palette_slot_mapping_count,
        "tileset_palette_source_candidate_count": tileset_palette_source_candidate_count,
        "tileset_existing_palette_source_candidate_count": tileset_existing_palette_source_candidate_count,
        "tileset_missing_palette_source_candidate_count": tileset_missing_palette_source_candidate_count,
        "tileset_header_missing_callback_source_count": tileset_header_missing_callback_source_count,
        "tileset_callback_map_layout_count": tileset_callback_map_layout_count,
        "tileset_callback_map_map_count": tileset_callback_map_map_count,
        "tileset_callback_map_grouped_map_count": tileset_callback_map_grouped_map_count,
        "tileset_callback_map_ungrouped_map_count": tileset_callback_map_ungrouped_map_count,
        "tileset_callback_map_layout_with_map_count": tileset_callback_map_layout_with_map_count,
        "tileset_callback_map_standalone_layout_count": tileset_callback_map_standalone_layout_count,
        "tileset_callback_map_pair_count": tileset_callback_map_pair_count,
        "tileset_callback_map_tileset_usage_count": tileset_callback_map_tileset_usage_count,
        "tileset_callback_map_tileset_with_callback_count": tileset_callback_map_tileset_with_callback_count,
        "tileset_callback_map_callback_symbol_count": tileset_callback_map_callback_symbol_count,
        "tileset_callback_map_callback_with_map_count": tileset_callback_map_callback_with_map_count,
        "tileset_callback_map_missing_header_tileset_count": tileset_callback_map_missing_header_tileset_count,
        "tileset_header_metatile_decode_count": tileset_header_metatile_decode_count,
        "active_emerald_tileset_header_metatile_decode_count": tileset_header_active_metatile_decode_count,
        "tileset_header_metatile_record_count": tileset_header_metatile_record_count,
        "active_emerald_tileset_header_metatile_record_count": tileset_header_active_metatile_record_count,
        "tileset_header_metatile_tile_entry_count": tileset_header_metatile_tile_entry_count,
        "active_emerald_tileset_header_metatile_tile_entry_count": tileset_header_active_metatile_tile_entry_count,
        "tileset_header_unique_metatile_source_binary_count": tileset_header_unique_metatile_source_binary_count,
        "tileset_header_unique_metatile_record_count": tileset_header_unique_metatile_record_count,
        "tileset_header_unique_metatile_tile_entry_count": tileset_header_unique_metatile_tile_entry_count,
        "tileset_header_metatile_out_of_range_tile_entry_count": tileset_header_metatile_out_of_range_tile_entry_count,
        "tileset_header_metatile_attribute_decode_count": tileset_header_metatile_attribute_decode_count,
        "active_emerald_tileset_header_metatile_attribute_decode_count": (
            tileset_header_active_metatile_attribute_decode_count
        ),
        "tileset_header_metatile_attribute_record_count": tileset_header_metatile_attribute_record_count,
        "active_emerald_tileset_header_metatile_attribute_record_count": (
            tileset_header_active_metatile_attribute_record_count
        ),
        "tileset_header_unique_metatile_attribute_source_binary_count": (
            tileset_header_unique_metatile_attribute_source_binary_count
        ),
        "tileset_header_unique_metatile_attribute_record_count": (
            tileset_header_unique_metatile_attribute_record_count
        ),
        "tileset_header_metatile_attribute_encounter_affordance_count": (
            tileset_header_metatile_attribute_encounter_affordance_count
        ),
        "active_emerald_tileset_header_metatile_attribute_encounter_affordance_count": (
            tileset_header_active_metatile_attribute_encounter_affordance_count
        ),
        "tileset_header_metatile_attribute_missing_behavior_name_count": (
            tileset_header_metatile_attribute_missing_behavior_name_count
        ),
        "tileset_header_metatile_label_source_label_count": (
            tileset_header_metatile_label_source_label_count
        ),
        "tileset_header_metatile_label_source_group_count": (
            tileset_header_metatile_label_source_group_count
        ),
        "tileset_header_metatile_label_decode_count": tileset_header_metatile_label_decode_count,
        "active_emerald_tileset_header_metatile_label_decode_count": (
            tileset_header_active_metatile_label_decode_count
        ),
        "tileset_header_metatile_label_record_count": tileset_header_metatile_label_record_count,
        "active_emerald_tileset_header_metatile_label_record_count": (
            tileset_header_active_metatile_label_record_count
        ),
        "tileset_header_metatile_label_pair_lookup_count": (
            tileset_header_metatile_label_pair_lookup_count
        ),
        "tileset_header_metatile_label_pair_lookup_layout_count": (
            tileset_header_metatile_label_pair_lookup_layout_count
        ),
        "tileset_header_metatile_label_pair_label_record_count": (
            tileset_header_metatile_label_pair_label_record_count
        ),
        "tileset_header_metatile_label_pair_out_of_range_count": (
            tileset_header_metatile_label_pair_out_of_range_count
        ),
        "tileset_header_metatile_map_reference_layout_count": (
            tileset_header_metatile_map_reference_layout_count
        ),
        "tileset_header_metatile_map_reference_checked_layout_count": (
            tileset_header_metatile_map_reference_checked_layout_count
        ),
        "tileset_header_metatile_map_reference_pair_count": (
            tileset_header_metatile_map_reference_pair_count
        ),
        "tileset_header_metatile_map_reference_checked_cell_count": (
            tileset_header_metatile_map_reference_checked_cell_count
        ),
        "tileset_header_metatile_map_reference_declared_cell_count": (
            tileset_header_metatile_map_reference_declared_cell_count
        ),
        "tileset_header_metatile_map_reference_unique_metatile_id_count": (
            tileset_header_metatile_map_reference_unique_metatile_id_count
        ),
        "tileset_header_metatile_map_reference_absent_cell_count": (
            tileset_header_metatile_map_reference_absent_cell_count
        ),
        "tileset_header_metatile_map_reference_absent_unique_reference_count": (
            tileset_header_metatile_map_reference_absent_unique_reference_count
        ),
        "tileset_header_metatile_map_reference_absent_global_metatile_id_count": (
            tileset_header_metatile_map_reference_absent_global_metatile_id_count
        ),
        "tileset_header_metatile_map_reference_layout_with_absent_count": (
            tileset_header_metatile_map_reference_layout_with_absent_count
        ),
        "tileset_header_metatile_map_reference_pair_with_absent_count": (
            tileset_header_metatile_map_reference_pair_with_absent_count
        ),
        "tileset_header_metatile_map_reference_missing_blockdata_layout_count": (
            tileset_header_metatile_map_reference_missing_blockdata_layout_count
        ),
        "tileset_header_metatile_map_reference_invalid_blockdata_layout_count": (
            tileset_header_metatile_map_reference_invalid_blockdata_layout_count
        ),
        "tileset_header_metatile_map_reference_size_mismatch_layout_count": (
            tileset_header_metatile_map_reference_size_mismatch_layout_count
        ),
        "tileset_header_tile_image_reference_header_count": (
            tileset_header_tile_image_reference_header_count
        ),
        "tileset_header_tile_image_reference_header_image_binding_count": (
            tileset_header_tile_image_reference_header_image_binding_count
        ),
        "tileset_header_tile_image_reference_decoded_image_binding_count": (
            tileset_header_tile_image_reference_decoded_image_binding_count
        ),
        "tileset_header_tile_image_reference_unique_source_image_count": (
            tileset_header_tile_image_reference_unique_source_image_count
        ),
        "tileset_header_tile_image_reference_unique_source_image_tile_count": (
            tileset_header_tile_image_reference_unique_source_image_tile_count
        ),
        "tileset_header_tile_image_reference_header_checked_tile_entry_count": (
            tileset_header_tile_image_reference_header_checked_tile_entry_count
        ),
        "tileset_header_tile_image_reference_header_foreign_tile_entry_count": (
            tileset_header_tile_image_reference_header_foreign_tile_entry_count
        ),
        "tileset_header_tile_image_reference_header_absent_tile_entry_count": (
            tileset_header_tile_image_reference_header_absent_tile_entry_count
        ),
        "tileset_header_tile_image_reference_header_absent_unique_tile_reference_count": (
            tileset_header_tile_image_reference_header_absent_unique_tile_reference_count
        ),
        "tileset_header_tile_image_reference_header_with_absent_tile_count": (
            tileset_header_tile_image_reference_header_with_absent_tile_count
        ),
        "tileset_header_tile_image_reference_pair_count": (
            tileset_header_tile_image_reference_pair_count
        ),
        "tileset_header_tile_image_reference_pair_checked_tile_entry_count": (
            tileset_header_tile_image_reference_pair_checked_tile_entry_count
        ),
        "tileset_header_tile_image_reference_pair_absent_tile_entry_count": (
            tileset_header_tile_image_reference_pair_absent_tile_entry_count
        ),
        "tileset_header_tile_image_reference_pair_absent_unique_tile_reference_count": (
            tileset_header_tile_image_reference_pair_absent_unique_tile_reference_count
        ),
        "tileset_header_tile_image_reference_pair_with_absent_tile_count": (
            tileset_header_tile_image_reference_pair_with_absent_tile_count
        ),
        "tileset_header_tile_image_reference_pair_missing_header_count": (
            tileset_header_tile_image_reference_pair_missing_header_count
        ),
        "metatile_record_count": tileset_totals["metatile_record_count"],
        "tileset_flattened_debug_atlas_count": tileset_totals["flattened_debug_atlas_count"],
        "tileset_runtime_layering_source_equivalent_atlas_count": (
            tileset_totals["runtime_layering_source_equivalent_atlas_count"]
        ),
        "tileset_runtime_layering_non_equivalent_atlas_count": (
            tileset_totals["runtime_layering_non_equivalent_atlas_count"]
        ),
        "tileset_runtime_layering_metadata_missing_count": (
            tileset_totals["runtime_layering_metadata_missing_count"]
        ),
        "tileset_layer_rendering_tileset_count": tileset_totals["layer_rendering_tileset_count"],
        "tileset_layer_rendering_missing_count": tileset_totals["layer_rendering_missing_count"],
        "tileset_layer_rendering_atlas_count": tileset_totals["layer_rendering_atlas_count"],
        "tileset_layer_rendering_missing_atlas_image_count": (
            tileset_totals["layer_rendering_missing_atlas_image_count"]
        ),
        "tileset_layer_rendering_metatile_count": tileset_totals["layer_rendering_metatile_count"],
        "tileset_layer_rendering_missing_metatile_record_count": (
            tileset_totals["layer_rendering_missing_metatile_record_count"]
        ),
        "script_bundle_count": script_totals["script_bundle_count"],
        "map_script_bundle_count": map_script_bundle_count,
        "shared_script_bundle_count": shared_script_bundle_count,
        "script_count": script_totals["script_count"],
        "movement_label_count": script_totals["movement_label_count"],
        "movement_action_count": script_totals["movement_action_count"],
        "movement_step_end_count": script_totals["movement_step_end_count"],
        "movement_action_count_excluding_step_end": script_totals["movement_action_count_excluding_step_end"],
        "script_text_count": script_totals["text_count"],
        "script_runtime_preview_unsupported_op_count": script_totals["runtime_preview_unsupported_op_count"],
        "door_animation_count": tileset_totals["door_animation_count"],
        "door_animation_frame_count": tileset_totals["door_animation_frame_count"],
        "tileset_animation_count": tileset_totals["tileset_animation_count"],
        "object_event_graphic_count": object_sprite_count,
        "warning_count": warning_count,
        "parity_matrix_unsupported_entry_count": int(parity_stats.get("unsupported_entry_count", 0)),
        "parity_matrix_unsupported_code_count": int(parity_stats.get("unsupported_code_count", 0)),
        "object_event_sprite_unsupported_note_count": object_sprite_unsupported_count,
        "explicit_summary_unsupported_count": len(explicit_unsupported),
        "total_reported_unsupported_count": (
            int(parity_stats.get("unsupported_entry_count", 0))
            + object_sprite_unsupported_count
            + len(explicit_unsupported)
        ),
    }
    generated_counts.update(map_event_totals)

    coverage = {
        "maps": ratio(generated_counts["map_count"], source_counts["map_count"]),
        "map_script_files": ratio(generated_counts["script_bundle_count"], source_counts["map_script_file_count"]),
        "map_scoped_script_files": ratio(
            generated_counts["map_script_bundle_count"],
            source_counts["map_script_file_count"],
        ),
        "layouts": ratio(generated_counts["layout_count"], source_counts["layout_count"]),
        "primary_tilesets": ratio(
            generated_counts["unique_primary_tileset_count"],
            source_counts["primary_tileset_image_count"],
        ),
        "secondary_tilesets": ratio(
            generated_counts["unique_secondary_tileset_count"],
            source_counts["secondary_tileset_image_count"],
        ),
        "tileset_headers": ratio(
            generated_counts["tileset_header_record_count"],
            source_counts["tileset_header_count"],
        ),
        "door_animations": ratio(
            generated_counts["door_animation_count"],
            source_counts["door_animation_table_entry_count"],
        ),
        "tileset_animation_callbacks": ratio(
            generated_counts["tileset_animation_count"],
            source_counts["tileset_callback_count"],
        ),
        "tileset_animation_source_images": ratio(
            generated_counts["tileset_animation_source_image_count"],
            source_counts["tileset_anim_source_frame_count"],
        ),
        "tileset_callback_maps": ratio(
            generated_counts["tileset_callback_map_map_count"],
            source_counts["map_count"],
        ),
        "tileset_callback_layouts": ratio(
            generated_counts["tileset_callback_map_layout_count"],
            source_counts["layout_count"],
        ),
        "tileset_callback_layout_pairs": ratio(
            generated_counts["tileset_callback_map_pair_count"],
            source_counts["layout_tileset_pair_count"],
        ),
        "tileset_callback_symbols": ratio(
            generated_counts["tileset_callback_map_callback_symbol_count"],
            source_counts["tileset_callback_count"],
        ),
        "tileset_palette_sources": ratio(
            generated_counts["tileset_existing_palette_source_candidate_count"],
            source_counts["tileset_palette_reference_count"],
        ),
        "tileset_metatile_binaries": ratio(
            generated_counts["tileset_header_unique_metatile_source_binary_count"],
            source_counts["tileset_metatile_binary_count"],
        ),
        "tileset_metatile_records": ratio(
            generated_counts["tileset_header_unique_metatile_record_count"],
            source_counts["tileset_metatile_record_count"],
        ),
        "tileset_metatile_tile_entries": ratio(
            generated_counts["tileset_header_unique_metatile_tile_entry_count"],
            source_counts["tileset_metatile_tile_entry_count"],
        ),
        "tileset_metatile_attribute_binaries": ratio(
            generated_counts["tileset_header_unique_metatile_attribute_source_binary_count"],
            source_counts["tileset_metatile_attribute_binary_count"],
        ),
        "tileset_metatile_attribute_records": ratio(
            generated_counts["tileset_header_unique_metatile_attribute_record_count"],
            source_counts["tileset_metatile_attribute_record_count"],
        ),
        "tileset_metatile_labels": ratio(
            generated_counts["tileset_header_metatile_label_source_label_count"],
            source_counts["tileset_metatile_label_count"],
        ),
        "tileset_metatile_label_pairs": ratio(
            generated_counts["tileset_header_metatile_label_pair_lookup_count"],
            source_counts["layout_tileset_pair_count"],
        ),
        "tileset_metatile_map_reference_layouts": ratio(
            generated_counts["tileset_header_metatile_map_reference_checked_layout_count"],
            source_counts["layout_count"],
        ),
        "tileset_metatile_map_reference_cells": ratio(
            generated_counts["tileset_header_metatile_map_reference_checked_cell_count"],
            source_counts["layout_blockdata_entry_count"],
        ),
        "tileset_tile_images": ratio(
            generated_counts["tileset_header_tile_image_reference_unique_source_image_count"],
            source_counts["tileset_tile_image_count"],
        ),
        "tileset_tile_image_tiles": ratio(
            generated_counts["tileset_header_tile_image_reference_unique_source_image_tile_count"],
            source_counts["tileset_tile_image_tile_count"],
        ),
        "tileset_tile_image_header_bindings": ratio(
            generated_counts["tileset_header_tile_image_reference_decoded_image_binding_count"],
            source_counts["tileset_header_count"],
        ),
        "tileset_metatile_tile_image_pairs": ratio(
            generated_counts["tileset_header_tile_image_reference_pair_count"],
            source_counts["layout_tileset_pair_count"],
        ),
        "object_event_graphics": ratio(
            generated_counts["object_event_graphic_count"],
            source_counts["object_event_graphics_info_count"],
        ),
    }

    return {
        "schema_version": 1,
        "generated_by": GENERATED_BY,
        "source_root": str(source_root),
        "manifest_path": to_project_path(manifest_path),
        "source_counts": source_counts,
        "generated_counts": generated_counts,
        "coverage": coverage,
        "warnings": {
            "total": warning_count,
            "manifest_warning_count_fields": manifest_warning_count,
            "generated_warning_array_count": generated_warning_array_count,
        },
        "unsupported": explicit_unsupported,
        "details": {
            "maps": map_summaries,
            "layouts": layout_summaries,
            "tilesets": tileset_summaries,
            "scripts": script_summaries,
            "movement_op_counts": script_totals["movement_op_counts"],
        },
        "inputs": build_inputs(source_root, project_root, manifest_path, manifest),
        "notes": [
            "GBA palette/VRAM/OAM limits are import-time concerns; runtime assets remain Godot-friendly RGBA/data.",
            "Palette-change, tint, blend, scale, rotation, and affine-style effects should be implemented with Godot-native presentation systems while preserving source timing and visible rhythm.",
            "Audio remains metadata_only/unsupported; sound and music symbols are counted or preserved elsewhere but playback is not implemented.",
        ],
    }


def build_explicit_unsupported(source_counts, generated_counts):
    return [
        {
            "code": "tileset_animation_runtime_pending",
            "status": "unsupported",
            "source_count": source_counts["tileset_callback_count"],
            "generated_count": generated_counts["tileset_animation_count"],
            "detail": "Source tileset animation callbacks exist, but no generated tileset animation runtime records are exported yet.",
        },
        {
            "code": "door_overlay_not_source_equivalent",
            "status": "first_pass",
            "source_count": source_counts["door_animation_table_entry_count"],
            "generated_count": generated_counts["door_animation_count"],
            "detail": "Only used first-slice door animation atlases are generated, and runtime playback is still overlay-based instead of source layer mutation.",
        },
        {
            "code": "flattened_debug_atlas_not_source_equivalent",
            "status": "first_pass",
            "source_count": generated_counts["tileset_record_count"],
            "generated_count": generated_counts["tileset_flattened_debug_atlas_count"],
            "detail": "Generated metatile atlases are temporary debug-only flattened RGBA previews and are not source-equivalent for runtime BG layer ordering.",
        },
        {
            "code": "source_equivalent_layer_renderer_pending",
            "status": "first_pass",
            "source_count": generated_counts["tileset_record_count"],
            "generated_count": generated_counts["tileset_layer_rendering_tileset_count"],
            "detail": "Generated bottom/middle/top RGBA layer render data exists for first-slice tilesets, but the runtime layer renderer does not consume it yet.",
        },
        {
            "code": "object_event_sprite_coverage_pending",
            "status": "first_pass",
            "source_count": source_counts["object_event_graphics_info_count"],
            "generated_count": generated_counts["object_event_graphic_count"],
            "detail": "Only the first Littleroot/debug/player object-event sprite slice is generated.",
        },
        {
            "code": "audio_playback_pending",
            "status": "metadata_only",
            "source_count": None,
            "generated_count": 0,
            "detail": "Audio symbols and timing intent stay in metadata; real playback remains out of scope.",
        },
    ]


def build_inputs(source_root, project_root, manifest_path, manifest):
    paths = [
        source_root / "data/layouts/layouts.json",
        source_root / "src/data/tilesets/headers.h",
        source_root / "src/tileset_anims.c",
        source_root / "src/field_door.c",
        source_root / "include/constants/metatile_labels.h",
        source_root / "src/data/object_events/object_event_graphics_info.h",
        manifest_path,
    ]
    for section in ["maps", "layouts", "tilesets", "scripts", "object_event_sprites", "overworld_reports"]:
        for entry in manifest.get(section, []):
            path_text = entry.get("path")
            if path_text:
                paths.append(Path(path_text))
    result = []
    for path in paths:
        resolved = path if path.is_absolute() else project_root / path
        result.append({
            "path": to_project_path(path),
            "exists": resolved.exists(),
        })
    return result


def manifest_entry_for(exported, output_path):
    generated = exported["generated_counts"]
    source = exported["source_counts"]
    return {
        "category": "overworld_import_summary",
        "path": to_project_path(output_path),
        "source_map_count": source["map_count"],
        "generated_map_count": generated["map_count"],
        "generated_layout_count": generated["layout_count"],
        "map_referenced_layout_count": generated["map_referenced_layout_count"],
        "standalone_layout_count": generated["standalone_layout_count"],
        "missing_layout_file_count": generated["missing_layout_file_count"],
        "generated_tileset_record_count": generated["tileset_record_count"],
        "generated_tileset_header_record_count": generated["tileset_header_record_count"],
        "generated_tileset_animation_source_image_count": generated["tileset_animation_source_image_count"],
        "generated_tileset_callback_map_layout_count": generated["tileset_callback_map_layout_count"],
        "generated_tileset_callback_map_map_count": generated["tileset_callback_map_map_count"],
        "generated_tileset_callback_map_pair_count": generated["tileset_callback_map_pair_count"],
        "generated_tileset_callback_map_callback_symbol_count": generated[
            "tileset_callback_map_callback_symbol_count"
        ],
        "generated_tileset_palette_slot_mapping_count": generated["tileset_palette_slot_mapping_count"],
        "generated_tileset_palette_source_candidate_count": generated["tileset_existing_palette_source_candidate_count"],
        "generated_tileset_metatile_attribute_record_count": generated["tileset_header_metatile_attribute_record_count"],
        "generated_unique_tileset_metatile_attribute_record_count": (
            generated["tileset_header_unique_metatile_attribute_record_count"]
        ),
        "generated_tileset_metatile_label_source_label_count": (
            generated["tileset_header_metatile_label_source_label_count"]
        ),
        "generated_tileset_metatile_label_pair_lookup_count": (
            generated["tileset_header_metatile_label_pair_lookup_count"]
        ),
        "generated_tileset_metatile_map_reference_checked_layout_count": (
            generated["tileset_header_metatile_map_reference_checked_layout_count"]
        ),
        "generated_tileset_metatile_map_reference_checked_cell_count": (
            generated["tileset_header_metatile_map_reference_checked_cell_count"]
        ),
        "generated_tileset_metatile_map_reference_absent_cell_count": (
            generated["tileset_header_metatile_map_reference_absent_cell_count"]
        ),
        "generated_tileset_metatile_map_reference_layout_with_absent_count": (
            generated["tileset_header_metatile_map_reference_layout_with_absent_count"]
        ),
        "generated_tileset_tile_image_reference_decoded_image_binding_count": (
            generated["tileset_header_tile_image_reference_decoded_image_binding_count"]
        ),
        "generated_tileset_tile_image_reference_unique_source_image_count": (
            generated["tileset_header_tile_image_reference_unique_source_image_count"]
        ),
        "generated_tileset_tile_image_reference_header_absent_tile_entry_count": (
            generated["tileset_header_tile_image_reference_header_absent_tile_entry_count"]
        ),
        "generated_tileset_tile_image_reference_pair_absent_tile_entry_count": (
            generated["tileset_header_tile_image_reference_pair_absent_tile_entry_count"]
        ),
        "generated_tileset_flattened_debug_atlas_count": generated["tileset_flattened_debug_atlas_count"],
        "generated_tileset_runtime_layering_non_equivalent_atlas_count": (
            generated["tileset_runtime_layering_non_equivalent_atlas_count"]
        ),
        "generated_tileset_runtime_layering_source_equivalent_atlas_count": (
            generated["tileset_runtime_layering_source_equivalent_atlas_count"]
        ),
        "generated_tileset_runtime_layering_metadata_missing_count": (
            generated["tileset_runtime_layering_metadata_missing_count"]
        ),
        "generated_tileset_layer_rendering_tileset_count": (
            generated["tileset_layer_rendering_tileset_count"]
        ),
        "generated_tileset_layer_rendering_atlas_count": (
            generated["tileset_layer_rendering_atlas_count"]
        ),
        "generated_tileset_layer_rendering_missing_count": (
            generated["tileset_layer_rendering_missing_count"]
        ),
        "generated_tileset_layer_rendering_missing_atlas_image_count": (
            generated["tileset_layer_rendering_missing_atlas_image_count"]
        ),
        "generated_tileset_layer_rendering_missing_metatile_record_count": (
            generated["tileset_layer_rendering_missing_metatile_record_count"]
        ),
        "tileset_missing_palette_source_candidate_count": generated["tileset_missing_palette_source_candidate_count"],
        "tileset_header_missing_callback_source_count": generated["tileset_header_missing_callback_source_count"],
        "generated_script_count": generated["script_count"],
        "generated_movement_action_count": generated["movement_action_count"],
        "generated_door_animation_count": generated["door_animation_count"],
        "generated_tileset_animation_count": generated["tileset_animation_count"],
        "generated_object_event_graphic_count": generated["object_event_graphic_count"],
        "warning_count": generated["warning_count"],
        "total_reported_unsupported_count": generated["total_reported_unsupported_count"],
    }


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, help="JSON config with source and output roots.")
    parser.add_argument("--source", type=Path, help="pokeemerald-expansion source root.")
    parser.add_argument("--output-root", type=Path, help="Generated data output root.")
    args = parser.parse_args(argv)

    config = load_config(args.config)
    source_root = args.source or Path(config.get("source_root", ""))
    output_root = args.output_root or Path(config.get("generated_data_root", "data/generated"))
    output_path = output_root / SUMMARY_PATH

    exported = build_export(source_root, output_root)
    write_json(output_path, exported)
    manifest_entry = manifest_entry_for(exported, output_path)
    write_manifest(
        output_root / "import_manifest.json",
        exported_overworld_reports=[manifest_entry],
        generator=GENERATED_BY,
    )

    print(json.dumps({"exported": manifest_entry, "generated_counts": exported["generated_counts"]}, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
