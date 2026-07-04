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
INCBIN_RE = re.compile(r'INCBIN_[A-Z0-9_]+\("([^"]+)"\)')


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
            incbin_paths = INCBIN_RE.findall(match.group("body"))
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
    if path_text.endswith("/metatiles.bin") or path_text.endswith("/metatile_attributes.bin"):
        candidates.append(path_text)
    return candidates


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


def parse_tileset_headers(source_root):
    headers_path = source_root / "src/data/tilesets/headers.h"
    text = read_text(headers_path)
    declarations = parse_asset_declarations(source_root)
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
            expected_base = Path("data/tilesets") / kind / expected_directory
            assets = {
                name: asset_group(source_root, asset_symbol, declarations)
                for name, asset_symbol in field_symbols.items()
            }
            header_line = line_number(text, (section_offset if section_offset >= 0 else 0) + match.start())

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
                },
                "expected_source_directory": {
                    "kind": kind,
                    "directory": expected_directory,
                    "base_path": to_project_path(expected_base),
                    "tiles_png": path_status(source_root, expected_base / "tiles.png"),
                    "palettes_dir": path_status(source_root, expected_base / "palettes"),
                    "metatiles_bin": path_status(source_root, expected_base / "metatiles.bin"),
                    "metatile_attributes_bin": path_status(source_root, expected_base / "metatile_attributes.bin"),
                },
                "asset_provenance": assets,
                "asset_source_directories": asset_source_directories(assets),
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


def build_stats(source_files, records):
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
        "missing_asset_declaration_count": stats["missing_asset_declaration_count"],
    }


def build_export(source_root):
    source_root = Path(source_root)
    source_files = source_file_presence(source_root)
    records = parse_tileset_headers(source_root)
    stats = build_stats(source_files, records)
    return {
        "schema_version": 1,
        "generated_by": GENERATED_BY,
        "source_root": str(source_root),
        "source_files": source_files,
        "tileset_headers": records,
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
                "detail": "Header callback symbols are exported, but no source-equivalent Godot tileset animation scheduler is implemented yet.",
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
