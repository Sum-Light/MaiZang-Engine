#!/usr/bin/env python3
"""Export a generated overworld import coverage summary."""

import argparse
import json
import re
import sys
from pathlib import Path

from export_map import write_json, write_manifest
from source_probe import load_config, to_project_path


GENERATED_BY = "tools/importer/export_overworld_import_summary.py"
SUMMARY_PATH = Path("overworld/import_summary.json")


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


def count_source_layouts(source_root):
    path = source_root / "data/layouts/layouts.json"
    if not path.exists():
        return 0
    return len(read_json(path).get("layouts", []))


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
    source_frames = re.findall(r'INCBIN_U16\("data/tilesets/.+?/anim/', text)
    source_groups = set(re.findall(r"(?:g|s)TilesetAnims_[A-Za-z0-9_]+(?=\s*\[\])", text))
    return {
        "tileset_anim_init_function_count": len(init_functions),
        "tileset_anim_source_frame_count": len(source_frames),
        "tileset_anim_source_group_count": len(source_groups),
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
        summary = {
            "map": entry.get("map"),
            "path": entry.get("path"),
            "primary_tileset": primary_symbol,
            "secondary_tileset": secondary_symbol,
            "total_metatiles": int(entry.get("total_metatiles", 0)),
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
    counts.update(door_info)
    return counts


def build_export(source_root, output_root):
    output_root = output_root.resolve()
    project_root = output_root.parent.parent
    manifest_path = output_root / "import_manifest.json"
    manifest = read_json(manifest_path) if manifest_path.exists() else {}
    source_counts = build_source_counts(source_root)

    map_entries = manifest.get("maps", [])
    tileset_entries = manifest.get("tilesets", [])
    script_entries = manifest.get("scripts", [])
    object_sprite_entries = manifest.get("object_event_sprites", [])
    map_script_bundle_count = sum(1 for entry in script_entries if entry.get("map"))
    shared_script_bundle_count = sum(1 for entry in script_entries if entry.get("scope") == "shared")

    map_event_totals, map_summaries = count_generated_maps(project_root, map_entries)
    tileset_totals, tileset_summaries = count_generated_tilesets(project_root, tileset_entries)
    script_totals, script_summaries = sum_script_bundles(project_root, script_entries)

    unique_layouts = sorted({
        entry.get("layout_id")
        for entry in map_entries
        if entry.get("layout_id")
    })

    object_sprite_data = None
    object_sprite_count = 0
    object_sprite_unsupported_count = 0
    if object_sprite_entries:
        object_sprite_data = load_generated_json(project_root, object_sprite_entries[0].get("path", ""))
    if isinstance(object_sprite_data, dict):
        object_sprite_count = int(object_sprite_data.get("stats", {}).get("sprite_count", 0))
        object_sprite_unsupported_count = count_object_sprite_unsupported(object_sprite_data)

    parity_matrix = load_generated_json(project_root, "data/generated/overworld/parity_matrix.json") or {}
    parity_stats = parity_matrix.get("stats", {})

    manifest_warning_count = count_manifest_warning_fields(
        manifest.get("scripts", [])
        + manifest.get("tilesets", [])
        + manifest.get("object_event_sprites", [])
    )
    generated_warning_array_count = tileset_totals["warning_array_count"]
    if object_sprite_data:
        generated_warning_array_count += count_recursive_warning_arrays(object_sprite_data)
    warning_count = manifest_warning_count + generated_warning_array_count

    explicit_unsupported = build_explicit_unsupported(
        source_counts,
        {
            "door_animation_count": tileset_totals["door_animation_count"],
            "tileset_animation_count": tileset_totals["tileset_animation_count"],
            "object_event_graphic_count": object_sprite_count,
        },
    )

    generated_counts = {
        "map_count": len(map_entries),
        "layout_count": len(unique_layouts),
        "tileset_record_count": tileset_totals["tileset_record_count"],
        "unique_primary_tileset_count": tileset_totals["unique_primary_tileset_count"],
        "unique_secondary_tileset_count": tileset_totals["unique_secondary_tileset_count"],
        "metatile_record_count": tileset_totals["metatile_record_count"],
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
        "door_animations": ratio(
            generated_counts["door_animation_count"],
            source_counts["door_animation_table_entry_count"],
        ),
        "tileset_animation_callbacks": ratio(
            generated_counts["tileset_animation_count"],
            source_counts["tileset_callback_count"],
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
        source_root / "src/data/object_events/object_event_graphics_info.h",
        manifest_path,
    ]
    for section in ["maps", "tilesets", "scripts", "object_event_sprites", "overworld_reports"]:
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
        "generated_tileset_record_count": generated["tileset_record_count"],
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
