#!/usr/bin/env python3
"""Export source tileset header coverage for overworld asset parity."""

import argparse
import json
import re
import sys
from pathlib import Path

from export_map import write_json, write_manifest
from source_probe import load_config, path_status, symbol_to_tileset_dir, to_project_path


GENERATED_BY = "tools/importer/export_overworld_tileset_headers.py"
REPORT_PATH = Path("overworld/tileset_header_report.json")

SOURCE_FILES = [
    "src/data/tilesets/headers.h",
    "src/data/tilesets/graphics.h",
    "src/data/tilesets/metatiles.h",
    "src/graphics.c",
    "src/tileset_anims.c",
    "include/fieldmap.h",
]

HEADER_RE = re.compile(
    r"const\s+struct\s+Tileset\s+(gTileset_[A-Za-z0-9_]+)\s*=\s*\{(.*?)\};",
    re.S,
)
ASSET_DECL_RE = re.compile(
    r"const\s+(?:u8|u16|u32)\s+(?:ALIGNED\(\d+\)\s+)?"
    r"(?P<symbol>g[A-Za-z0-9_]+)(?:\s*\[[^\]]*\])+"
    r"\s*=\s*(?P<body>.*?);",
    re.S,
)
INCBIN_CALL_RE = re.compile(r"INCBIN_[A-Z0-9_]+\((?P<body>.*?)\)", re.S)
STRING_LITERAL_RE = re.compile(r'"([^"]+)"')
ANIM_FRAME_DECL_RE = re.compile(
    r"(?:static\s+)?const\s+u16\s+"
    r"(?P<symbol>(?:g|s)TilesetAnims_[A-Za-z0-9_]+)"
    r"\[\]\s*=\s*INCBIN_U16\(.*?\);",
    re.S,
)
INIT_FUNCTION_RE = re.compile(r"\bvoid\s+(InitTilesetAnim_[A-Za-z0-9_]+)\s*\(")


def read_text(path):
    return path.read_text(encoding="utf-8")


def normalize_ws(value):
    return re.sub(r"\s+", " ", value.strip())


def bool_value(expr):
    if expr == "TRUE":
        return True
    if expr == "FALSE":
        return False
    return None


def line_number(text, offset):
    return text.count("\n", 0, offset) + 1


def incbin_paths_from_text(text):
    paths = []
    for match in INCBIN_CALL_RE.finditer(text):
        paths.extend(STRING_LITERAL_RE.findall(match.group("body")))
    return paths


def split_header_sections(text):
    start = text.find("#if !IS_FRLG")
    else_index = text.find("#else", start) if start >= 0 else -1
    endif = text.find("#endif", else_index) if else_index >= 0 else -1
    if start < 0 or else_index < 0 or endif < 0:
        return [
            ("active_emerald", True, text),
        ]
    return [
        ("preprocessor_shared", True, text[:start]),
        ("emerald_active", True, text[start + len("#if !IS_FRLG"):else_index]),
        ("frlg_metadata", False, text[else_index + len("#else"):endif]),
    ]


def field_expr(body, field_name):
    match = re.search(r"\.%s\s*=\s*([^,]+)" % re.escape(field_name), body)
    return normalize_ws(match.group(1)) if match else ""


def parse_asset_declarations(source_root):
    declarations = {}
    for source_file in ["src/data/tilesets/graphics.h", "src/data/tilesets/metatiles.h", "src/graphics.c"]:
        path = source_root / source_file
        if not path.exists():
            continue
        text = read_text(path)
        for match in ASSET_DECL_RE.finditer(text):
            symbol = match.group("symbol")
            incbin_paths = incbin_paths_from_text(match.group("body"))
            if not incbin_paths:
                continue
            declarations[symbol] = {
                "symbol": symbol,
                "source_file": source_file,
                "line": line_number(text, match.start()),
                "incbin_paths": incbin_paths,
            }
    return declarations


def status_for_path(source_root, path_text):
    return path_status(source_root, Path(path_text))


def candidate_paths_for_incbin(path_text):
    candidates = []
    if path_text.endswith(".gbapal"):
        candidates.append(path_text[:-len(".gbapal")] + ".pal")
    if "/tiles." in path_text:
        candidates.append(path_text.split("/tiles.", 1)[0] + "/tiles.png")
    if path_text.startswith("data/tilesets/") and path_text.endswith(".4bpp"):
        candidates.append(path_text[:-len(".4bpp")] + ".png")
    if path_text.endswith("/metatiles.bin") or path_text.endswith("/metatile_attributes.bin"):
        candidates.append(path_text)
    return candidates


def tileset_base_from_asset_path(path_text):
    parts = path_text.replace("\\", "/").split("/")
    if len(parts) < 4 or parts[:2] != ["data", "tilesets"]:
        return ""
    return "/".join(parts[:4])


def dedupe_status_rows(rows):
    result = []
    seen = set()
    for row in rows:
        key = row.get("path")
        if key in seen:
            continue
        seen.add(key)
        result.append(row)
    return result


def asset_group(source_root, symbol, declarations):
    declaration = declarations.get(symbol)
    if declaration is None:
        return {
            "symbol": symbol,
            "declaration_found": False,
            "incbin_path_count": 0,
            "existing_incbin_path_count": 0,
            "editable_source_candidate_count": 0,
            "existing_editable_source_candidate_count": 0,
            "incbin_paths": [],
            "editable_source_candidates": [],
        }

    incbin_status = [status_for_path(source_root, path_text) for path_text in declaration["incbin_paths"]]
    candidate_status = []
    for path_text in declaration["incbin_paths"]:
        for candidate in candidate_paths_for_incbin(path_text):
            candidate_status.append(status_for_path(source_root, candidate))
    candidate_status = dedupe_status_rows(candidate_status)

    return {
        "symbol": symbol,
        "declaration_found": True,
        "declaration_source": {
            "path": declaration["source_file"],
            "line": declaration["line"],
        },
        "incbin_path_count": len(incbin_status),
        "existing_incbin_path_count": sum(1 for row in incbin_status if row["exists"]),
        "editable_source_candidate_count": len(candidate_status),
        "existing_editable_source_candidate_count": sum(1 for row in candidate_status if row["exists"]),
        "incbin_paths": incbin_status,
        "editable_source_candidates": candidate_status,
    }


def asset_source_directories(asset_groups):
    directories = set()
    for group in asset_groups.values():
        for row in group.get("incbin_paths", []) + group.get("editable_source_candidates", []):
            path_text = row.get("path", "")
            if "/" in path_text:
                directories.add(path_text.rsplit("/", 1)[0])
    return sorted(directories)


def expected_base_path_from_assets(asset_groups, fallback_path):
    base_counts = {}
    for group in asset_groups.values():
        for row in group.get("incbin_paths", []) + group.get("editable_source_candidates", []):
            base_path = tileset_base_from_asset_path(row.get("path", ""))
            if base_path:
                base_counts[base_path] = base_counts.get(base_path, 0) + 1
    if not base_counts:
        return fallback_path
    return sorted(base_counts.items(), key=lambda item: (-item[1], item[0]))[0][0]


def path_status_from_project_path(source_root, path_text):
    return path_status(source_root, Path(path_text))


def first_matching_status(rows, predicate):
    for row in rows:
        if predicate(row.get("path", "")):
            return row
    return None


def asset_status_or_fallback(source_root, group, fallback_path, predicate):
    row = first_matching_status(
        group.get("editable_source_candidates", []) + group.get("incbin_paths", []),
        predicate,
    )
    if row is not None:
        return row
    return path_status_from_project_path(source_root, fallback_path)


def asset_directory_status_or_fallback(source_root, group, fallback_path, predicate):
    row = first_matching_status(
        group.get("editable_source_candidates", []) + group.get("incbin_paths", []),
        predicate,
    )
    if row is not None and "/" in row.get("path", ""):
        return path_status_from_project_path(source_root, row["path"].rsplit("/", 1)[0])
    return path_status_from_project_path(source_root, fallback_path)


def parse_animation_frame_declarations(source_root):
    path = source_root / "src/tileset_anims.c"
    if not path.exists():
        return []
    text = read_text(path)
    rows = []
    for match in ANIM_FRAME_DECL_RE.finditer(text):
        source_bins = incbin_paths_from_text(match.group(0))
        bin_status = [status_for_path(source_root, path_text) for path_text in source_bins]
        image_candidates = []
        for path_text in source_bins:
            for candidate in candidate_paths_for_incbin(path_text):
                image_candidates.append(status_for_path(source_root, candidate))
        image_candidates = dedupe_status_rows(image_candidates)
        rows.append({
            "symbol": match.group("symbol"),
            "source": {
                "path": "src/tileset_anims.c",
                "line": line_number(text, match.start()),
            },
            "source_bins": bin_status,
            "source_bin_count": len(bin_status),
            "existing_source_bin_count": sum(1 for row in bin_status if row["exists"]),
            "editable_source_candidates": image_candidates,
            "existing_editable_source_candidate_count": sum(1 for row in image_candidates if row["exists"]),
            "tileset_base_paths": sorted({
                tileset_base_from_asset_path(row["path"])
                for row in image_candidates + bin_status
                if tileset_base_from_asset_path(row["path"])
            }),
        })
    return rows


def parse_init_function_symbols(source_root):
    path = source_root / "src/tileset_anims.c"
    if not path.exists():
        return []
    text = read_text(path)
    return [
        {
            "function": match.group(1),
            "source": {
                "path": "src/tileset_anims.c",
                "line": line_number(text, match.start()),
            },
        }
        for match in INIT_FUNCTION_RE.finditer(text)
    ]


def frames_for_tileset_base(animation_frames, base_path):
    if not base_path:
        return []
    return [
        frame
        for frame in animation_frames
        if base_path in frame.get("tileset_base_paths", [])
    ]


def parse_tileset_headers(source_root, animation_frames=None, init_functions=None):
    headers_path = source_root / "src/data/tilesets/headers.h"
    text = read_text(headers_path)
    declarations = parse_asset_declarations(source_root)
    animation_frames = animation_frames or []
    init_function_symbols = {
        row["function"]: row
        for row in (init_functions or [])
    }
    rows = []

    for branch, active_in_emerald, section in split_header_sections(text):
        section_offset = text.find(section) if section else -1
        for match in HEADER_RE.finditer(section):
            body = match.group(2)
            symbol = match.group(1)
            is_secondary_expr = field_expr(body, "isSecondary")
            is_compressed_expr = field_expr(body, "isCompressed")
            callback_symbol = field_expr(body, "callback") or "NULL"
            field_symbols = {
                "tiles": field_expr(body, "tiles"),
                "palettes": field_expr(body, "palettes"),
                "metatiles": field_expr(body, "metatiles"),
                "metatile_attributes": field_expr(body, "metatileAttributes"),
            }
            kind = "secondary" if bool_value(is_secondary_expr) else "primary"
            expected_directory = symbol_to_tileset_dir(symbol)
            assets = {
                name: asset_group(source_root, asset_symbol, declarations)
                for name, asset_symbol in field_symbols.items()
            }
            guessed_base = Path("data/tilesets") / kind / expected_directory
            guessed_base_path = to_project_path(guessed_base)
            expected_base_path = expected_base_path_from_assets(assets, guessed_base_path)
            header_line = line_number(text, (section_offset if section_offset >= 0 else 0) + match.start())
            animation_frame_rows = frames_for_tileset_base(animation_frames, expected_base_path)
            callback_source = init_function_symbols.get(callback_symbol)

            rows.append({
                "symbol": symbol,
                "short_name": symbol[len("gTileset_"):],
                "branch": branch,
                "active_in_emerald": active_in_emerald,
                "source": {
                    "path": "src/data/tilesets/headers.h",
                    "line": header_line,
                },
                "kind": kind,
                "is_secondary": bool_value(is_secondary_expr),
                "is_secondary_expr": is_secondary_expr,
                "is_compressed": bool_value(is_compressed_expr),
                "is_compressed_expr": is_compressed_expr,
                "header_fields": {
                    "tiles": field_symbols["tiles"],
                    "palettes": field_symbols["palettes"],
                    "metatiles": field_symbols["metatiles"],
                    "metatileAttributes": field_symbols["metatile_attributes"],
                    "callback": callback_symbol,
                },
                "callback": {
                    "symbol": callback_symbol,
                    "has_callback": callback_symbol != "NULL",
                    "status": "metadata_only" if callback_symbol != "NULL" else "none",
                    "source": callback_source["source"] if callback_source else None,
                    "source_found": callback_source is not None if callback_symbol != "NULL" else True,
                },
                "expected_source_directory": {
                    "kind": kind,
                    "directory": expected_directory,
                    "guessed_base_path": guessed_base_path,
                    "base_path": expected_base_path,
                    "resolved_from_asset_provenance": expected_base_path != guessed_base_path,
                    "tiles_png": asset_status_or_fallback(
                        source_root,
                        assets["tiles"],
                        expected_base_path + "/tiles.png",
                        lambda path: path.endswith(".png"),
                    ),
                    "palettes_dir": asset_directory_status_or_fallback(
                        source_root,
                        assets["palettes"],
                        expected_base_path + "/palettes",
                        lambda path: path.endswith(".pal"),
                    ),
                    "metatiles_bin": asset_status_or_fallback(
                        source_root,
                        assets["metatiles"],
                        expected_base_path + "/metatiles.bin",
                        lambda path: path.endswith("/metatiles.bin"),
                    ),
                    "metatile_attributes_bin": asset_status_or_fallback(
                        source_root,
                        assets["metatile_attributes"],
                        expected_base_path + "/metatile_attributes.bin",
                        lambda path: path.endswith("/metatile_attributes.bin"),
                    ),
                },
                "asset_provenance": assets,
                "asset_source_directories": asset_source_directories(assets),
                "animation_image_provenance": {
                    "frame_declaration_count": len(animation_frame_rows),
                    "source_bin_count": sum(row["source_bin_count"] for row in animation_frame_rows),
                    "existing_source_bin_count": sum(row["existing_source_bin_count"] for row in animation_frame_rows),
                    "editable_source_candidate_count": sum(
                        len(row["editable_source_candidates"])
                        for row in animation_frame_rows
                    ),
                    "existing_editable_source_candidate_count": sum(
                        row["existing_editable_source_candidate_count"]
                        for row in animation_frame_rows
                    ),
                    "frame_symbols": [row["symbol"] for row in animation_frame_rows],
                    "frames": animation_frame_rows,
                },
            })
    return rows


def source_file_presence(source_root):
    return [
        path_status(source_root, Path(source_file))
        for source_file in SOURCE_FILES
    ]


def count_by(rows, field):
    result = {}
    for row in rows:
        key = str(row.get(field))
        result[key] = result.get(key, 0) + 1
    return result


def build_stats(source_files, records, animation_frames=None, init_functions=None):
    animation_frames = animation_frames or []
    init_functions = init_functions or []
    active = [row for row in records if row["active_in_emerald"]]
    callbacks = [row["callback"]["symbol"] for row in records if row["callback"]["has_callback"]]
    active_callbacks = [row["callback"]["symbol"] for row in active if row["callback"]["has_callback"]]
    asset_groups = [
        group
        for row in records
        for group in row["asset_provenance"].values()
    ]
    missing_declarations = [
        {"tileset": row["symbol"], "field": field, "symbol": group["symbol"]}
        for row in records
        for field, group in row["asset_provenance"].items()
        if not group["declaration_found"]
    ]
    missing_callback_sources = [
        {
            "tileset": row["symbol"],
            "callback": row["callback"]["symbol"],
        }
        for row in records
        if row["callback"]["has_callback"] and not row["callback"].get("source_found")
    ]
    missing_animation_image_candidates = [
        {
            "frame_symbol": frame["symbol"],
            "path": candidate["path"],
        }
        for frame in animation_frames
        for candidate in frame.get("editable_source_candidates", [])
        if not candidate.get("exists")
    ]
    animation_base_paths = sorted({
        base_path
        for frame in animation_frames
        for base_path in frame.get("tileset_base_paths", [])
    })
    header_base_paths = sorted({
        row["expected_source_directory"]["base_path"]
        for row in records
    })
    orphan_animation_base_paths = [
        base_path
        for base_path in animation_base_paths
        if base_path not in header_base_paths
    ]
    orphan_animation_frames = [
        {
            "base_path": base_path,
            "frame_symbols": [
                frame["symbol"]
                for frame in animation_frames
                if base_path in frame.get("tileset_base_paths", [])
            ],
        }
        for base_path in orphan_animation_base_paths
    ]
    return {
        "source_file_count": len(source_files),
        "missing_source_file_count": sum(1 for row in source_files if not row["exists"]),
        "total_header_count": len(records),
        "active_emerald_header_count": len(active),
        "frlg_metadata_header_count": sum(1 for row in records if row["branch"] == "frlg_metadata"),
        "header_count_by_branch": count_by(records, "branch"),
        "primary_header_count": sum(1 for row in records if row["kind"] == "primary"),
        "secondary_header_count": sum(1 for row in records if row["kind"] == "secondary"),
        "active_primary_header_count": sum(1 for row in active if row["kind"] == "primary"),
        "active_secondary_header_count": sum(1 for row in active if row["kind"] == "secondary"),
        "compressed_header_count": sum(1 for row in records if row["is_compressed"] is True),
        "uncompressed_header_count": sum(1 for row in records if row["is_compressed"] is False),
        "callback_symbol_count": len(set(callbacks)),
        "callback_binding_count": len(callbacks),
        "callback_source_found_count": sum(
            1 for row in records if row["callback"]["has_callback"] and row["callback"].get("source_found")
        ),
        "missing_callback_source_count": len(missing_callback_sources),
        "missing_callback_sources": missing_callback_sources,
        "null_callback_count": sum(1 for row in records if not row["callback"]["has_callback"]),
        "active_callback_symbol_count": len(set(active_callbacks)),
        "active_callback_binding_count": len(active_callbacks),
        "asset_field_count": len(asset_groups),
        "missing_asset_declaration_count": len(missing_declarations),
        "missing_asset_declarations": missing_declarations,
        "editable_source_candidate_count": sum(group["editable_source_candidate_count"] for group in asset_groups),
        "existing_editable_source_candidate_count": sum(
            group["existing_editable_source_candidate_count"]
            for group in asset_groups
        ),
        "incbin_path_count": sum(group["incbin_path_count"] for group in asset_groups),
        "existing_incbin_path_count": sum(group["existing_incbin_path_count"] for group in asset_groups),
        "init_function_count": len(init_functions),
        "animation_frame_declaration_count": len(animation_frames),
        "animation_source_bin_count": sum(frame["source_bin_count"] for frame in animation_frames),
        "animation_existing_source_bin_count": sum(
            frame["existing_source_bin_count"]
            for frame in animation_frames
        ),
        "animation_editable_source_candidate_count": sum(
            len(frame.get("editable_source_candidates", []))
            for frame in animation_frames
        ),
        "animation_existing_editable_source_candidate_count": sum(
            frame["existing_editable_source_candidate_count"]
            for frame in animation_frames
        ),
        "animation_missing_editable_source_candidate_count": len(missing_animation_image_candidates),
        "animation_missing_editable_source_candidates": missing_animation_image_candidates,
        "animation_tileset_base_count": len(animation_base_paths),
        "animation_tileset_base_paths": animation_base_paths,
        "orphan_animation_tileset_base_count": len(orphan_animation_base_paths),
        "orphan_animation_tileset_base_paths": orphan_animation_base_paths,
        "orphan_animation_frames": orphan_animation_frames,
        "headers_with_animation_image_provenance_count": sum(
            1
            for row in records
            if row["animation_image_provenance"]["frame_declaration_count"] > 0
        ),
        "active_headers_with_animation_image_provenance_count": sum(
            1
            for row in active
            if row["animation_image_provenance"]["frame_declaration_count"] > 0
        ),
    }


def manifest_entry_for(exported, output_path):
    stats = exported["stats"]
    return {
        "category": "overworld_tileset_header_report",
        "path": to_project_path(output_path),
        "total_header_count": stats["total_header_count"],
        "active_emerald_header_count": stats["active_emerald_header_count"],
        "primary_header_count": stats["primary_header_count"],
        "secondary_header_count": stats["secondary_header_count"],
        "callback_symbol_count": stats["callback_symbol_count"],
        "animation_frame_declaration_count": stats["animation_frame_declaration_count"],
        "animation_existing_editable_source_candidate_count": stats["animation_existing_editable_source_candidate_count"],
        "missing_callback_source_count": stats["missing_callback_source_count"],
        "missing_asset_declaration_count": stats["missing_asset_declaration_count"],
    }


def build_export(source_root):
    source_root = Path(source_root)
    source_files = source_file_presence(source_root)
    animation_frames = parse_animation_frame_declarations(source_root)
    init_functions = parse_init_function_symbols(source_root)
    records = parse_tileset_headers(source_root, animation_frames, init_functions)
    stats = build_stats(source_files, records, animation_frames, init_functions)
    return {
        "schema_version": 1,
        "generated_by": GENERATED_BY,
        "source_root": str(source_root),
        "source_files": source_files,
        "tileset_headers": records,
        "tileset_animation_frames": animation_frames,
        "tileset_animation_init_functions": init_functions,
        "runtime_policy": {
            "runtime_palette_required": False,
            "palette_and_color": "Source palette paths and slots are import-only provenance. Godot runtime should consume RGBA textures plus Shader/Material/Animation parameters for color changes, fades, tints, cycling, scale, rotation, and affine-like effects.",
            "gba_storage": "Compressed tiles, metatile binaries, palette files, and VRAM/OAM-style details are decoded or baked at import time, not recreated as runtime limits.",
            "audio": {
                "status": "metadata_only",
                "detail": "Tileset headers do not play audio directly; any later linked sound/music/fanfare symbols stay metadata_only/unsupported until audio scope is reopened.",
            },
        },
        "unsupported": [
            {
                "code": "tileset_animation_runtime_pending",
                "status": "unsupported",
                "detail": "Header callback symbols, callback source bindings, and animation frame image provenance are exported, but no source-equivalent Godot tileset animation scheduler is implemented yet.",
            },
            {
                "code": "metatile_layer_decode_pending",
                "status": "unsupported",
                "detail": "This report indexes header asset symbols; full per-8x8 metatile layer decode remains a later Section 4 task.",
            },
            {
                "code": "audio_playback_pending",
                "status": "metadata_only",
                "detail": "Audio playback remains out of scope for overworld work; source audio intent must stay metadata_only/unsupported.",
            },
        ],
        "stats": stats,
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
    output_path = output_root / REPORT_PATH

    exported = build_export(source_root)
    write_json(output_path, exported)
    manifest_entry = manifest_entry_for(exported, output_path)
    write_manifest(
        output_root / "import_manifest.json",
        exported_overworld_reports=[manifest_entry],
        generator=GENERATED_BY,
    )

    print(json.dumps({"exported": manifest_entry, "stats": exported["stats"]}, ensure_ascii=False, indent=2))
    ok = (
        exported["stats"]["missing_source_file_count"] == 0
        and exported["stats"]["total_header_count"] > 0
        and exported["stats"]["missing_asset_declaration_count"] == 0
    )
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
