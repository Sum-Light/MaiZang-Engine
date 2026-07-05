#!/usr/bin/env python3
"""Export source tileset header coverage for overworld asset parity."""

import argparse
import json
import re
import sys
from pathlib import Path

from export_map import read_u16le_file, write_json, write_manifest
from source_probe import load_config, path_status, symbol_to_tileset_dir, to_project_path


GENERATED_BY = "tools/importer/export_overworld_tileset_headers.py"
REPORT_PATH = Path("overworld/tileset_header_report.json")

SOURCE_FILES = [
    "src/data/tilesets/headers.h",
    "src/data/tilesets/graphics.h",
    "src/data/tilesets/metatiles.h",
    "src/graphics.c",
    "src/fieldmap.c",
    "src/field_camera.c",
    "src/tileset_anims.c",
    "include/fieldmap.h",
    "include/global.fieldmap.h",
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
PALETTE_DEFINE_RE = re.compile(
    r"#define\s+"
    r"(?P<name>NUM_PALS_IN_PRIMARY_FRLG|NUM_PALS_IN_PRIMARY|NUM_PALS_TOTAL)"
    r"\s+(?P<value>\d+)"
)

PALETTE_RULE_FUNCTIONS = [
    "GetNumPalsInPrimary",
    "LoadTilesetPalette",
    "LoadPrimaryTilesetPalette",
    "LoadSecondaryTilesetPalette",
    "LoadMapTilesetPalettes",
]

METATILE_RULE_FUNCTIONS = [
    "DrawMetatileAt",
    "DrawDoorMetatileAt",
    "DrawMetatile",
]

NUM_TILES_IN_PRIMARY = 512
NUM_TILES_IN_PRIMARY_FRLG = 640
NUM_METATILES_IN_PRIMARY = 512
NUM_METATILES_IN_PRIMARY_FRLG = 640
NUM_METATILES_TOTAL = 1024
NUM_TILES_TOTAL = 1024
NUM_TILES_PER_METATILE = 8
TILE_ENTRY_INDEX_MASK = 0x03FF
TILE_ENTRY_HFLIP_MASK = 0x0400
TILE_ENTRY_VFLIP_MASK = 0x0800
TILE_ENTRY_PALETTE_SHIFT = 12
TILE_SOURCE_KIND_CODES = {
    "primary": 0,
    "secondary": 1,
}

METATILE_ENTRY_POSITIONS = [
    {"x": 0, "y": 0},
    {"x": 1, "y": 0},
    {"x": 0, "y": 1},
    {"x": 1, "y": 1},
    {"x": 0, "y": 0},
    {"x": 1, "y": 0},
    {"x": 0, "y": 1},
    {"x": 1, "y": 1},
]


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


def parse_palette_slot_rules(source_root):
    fieldmap_h_path = source_root / "include/fieldmap.h"
    fieldmap_c_path = source_root / "src/fieldmap.c"
    fieldmap_h = read_text(fieldmap_h_path) if fieldmap_h_path.exists() else ""
    fieldmap_c = read_text(fieldmap_c_path) if fieldmap_c_path.exists() else ""

    constants = {}
    for match in PALETTE_DEFINE_RE.finditer(fieldmap_h):
        constants[match.group("name")] = {
            "value": int(match.group("value")),
            "source": {
                "path": "include/fieldmap.h",
                "line": line_number(fieldmap_h, match.start()),
            },
        }

    total = constants.get("NUM_PALS_TOTAL", {}).get("value", 0)
    emerald_primary = constants.get("NUM_PALS_IN_PRIMARY", {}).get("value", 0)
    frlg_primary = constants.get("NUM_PALS_IN_PRIMARY_FRLG", {}).get("value", 0)

    return {
        "status": "import_metadata_only",
        "runtime_palette_required": False,
        "source_files": [
            path_status(source_root, Path("include/fieldmap.h")),
            path_status(source_root, Path("src/fieldmap.c")),
        ],
        "constants": constants,
        "profiles": {
            "emerald": palette_rule_profile("emerald", False, emerald_primary, total),
            "frlg": palette_rule_profile("frlg", True, frlg_primary, total),
        },
        "source_functions": source_function_refs(fieldmap_c, "src/fieldmap.c", PALETTE_RULE_FUNCTIONS),
        "source_logic": [
            {
                "symbol": "LoadPrimaryTilesetPalette",
                "detail": "Primary tileset palettes are copied from local slot 0 into global BG palette slot 0 for GetNumPalsInPrimary(mapLayout) slots.",
            },
            {
                "symbol": "LoadSecondaryTilesetPalette",
                "detail": "Secondary tileset palettes are copied starting at local slot GetNumPalsInPrimary(mapLayout) into the same-numbered global BG palette slots through NUM_PALS_TOTAL - 1.",
            },
            {
                "symbol": "LoadTilesetPalette",
                "detail": "Primary slot 0 is forced to RGB_BLACK after copy; this remains source-color provenance, not a Godot runtime palette API.",
            },
        ],
        "runtime_policy": {
            "status": "import_metadata_only",
            "detail": "Palette slot numbers and source .pal/.gbapal paths are preserved for provenance and bake-time decoding only. Godot runtime rendering consumes RGBA textures and Godot-native Shader/Material/Animation parameters.",
        },
    }


def palette_rule_profile(name, is_frlg, primary_count, total_count):
    secondary_count = max(0, total_count - primary_count)
    return {
        "name": name,
        "is_frlg": is_frlg,
        "total_bg_palette_slot_count": total_count,
        "primary_global_slot_start": 0,
        "primary_loaded_palette_count": primary_count,
        "primary_loaded_local_slot_start": 0,
        "primary_loaded_local_slot_end_exclusive": primary_count,
        "secondary_global_slot_start": primary_count,
        "secondary_loaded_palette_count": secondary_count,
        "secondary_loaded_local_slot_start": primary_count,
        "secondary_loaded_local_slot_end_exclusive": total_count,
    }


def source_function_refs(text, source_path, names):
    rows = []
    for name in names:
        match = re.search(r"\b(?:static\s+)?(?:void|u32)\s+%s\s*\(" % re.escape(name), text)
        rows.append({
            "symbol": name,
            "source": {
                "path": source_path,
                "line": line_number(text, match.start()) if match else None,
            },
            "found": match is not None,
        })
    return rows


def palette_source_profile_for_branch(branch):
    return "frlg" if branch == "frlg_metadata" else "emerald"


def palette_slot_mapping_for_header(source_root, kind, branch, palette_group, palette_rules):
    profile_name = palette_source_profile_for_branch(branch)
    profile = palette_rules.get("profiles", {}).get(profile_name, {})
    slots = []
    for local_slot, incbin_row in enumerate(palette_group.get("incbin_paths", [])):
        path_text = incbin_row.get("path", "")
        editable_candidates = [
            status_for_path(source_root, candidate)
            for candidate in candidate_paths_for_incbin(path_text)
        ]
        loaded, global_slot, role = palette_slot_load_state(kind, local_slot, profile)
        slots.append({
            "local_palette_slot": local_slot,
            "global_bg_palette_slot": global_slot,
            "loaded_by_source_map_palette_copy": loaded,
            "source_role": role,
            "source_profile": profile_name,
            "source_kind": kind,
            "palette_entry_count": 16,
            "source_incbin": incbin_row,
            "editable_source_candidates": editable_candidates,
            "existing_editable_source_candidate_count": sum(1 for row in editable_candidates if row["exists"]),
            "runtime_policy": {
                "status": "import_metadata_only",
                "runtime_palette_required": False,
                "detail": "This slot is source provenance for RGBA baking or later Godot-native color effects; it is not a runtime palette bank.",
            },
        })

    loaded_slots = [slot for slot in slots if slot["loaded_by_source_map_palette_copy"]]
    return {
        "status": "import_metadata_only",
        "runtime_palette_required": False,
        "source_rules_profile": profile_name,
        "source_palette_symbol": palette_group.get("symbol"),
        "source_palette_declaration_found": palette_group.get("declaration_found", False),
        "source_palette_declaration": palette_group.get("declaration_source"),
        "source_kind": kind,
        "declared_palette_slot_count": len(slots),
        "loaded_palette_slot_count": len(loaded_slots),
        "not_loaded_palette_slot_count": len(slots) - len(loaded_slots),
        "total_bg_palette_slot_count": profile.get("total_bg_palette_slot_count"),
        "primary_loaded_palette_count": profile.get("primary_loaded_palette_count"),
        "secondary_loaded_palette_count": profile.get("secondary_loaded_palette_count"),
        "secondary_loaded_local_slot_start": profile.get("secondary_loaded_local_slot_start"),
        "loaded_global_bg_palette_slots": [
            slot["global_bg_palette_slot"]
            for slot in loaded_slots
        ],
        "slots": slots,
    }


def palette_slot_load_state(kind, local_slot, profile):
    primary_end = int(profile.get("primary_loaded_local_slot_end_exclusive", 0) or 0)
    secondary_start = int(profile.get("secondary_loaded_local_slot_start", 0) or 0)
    secondary_end = int(profile.get("secondary_loaded_local_slot_end_exclusive", 0) or 0)
    total = int(profile.get("total_bg_palette_slot_count", 0) or 0)

    if kind == "primary":
        if 0 <= local_slot < primary_end:
            return True, local_slot, "primary_loaded_bg_palette"
        if local_slot < total:
            return False, None, "declared_global_slot_owned_by_secondary"
        return False, None, "declared_beyond_bg_palette_total_not_loaded"

    if kind == "secondary":
        if secondary_start <= local_slot < secondary_end:
            return True, local_slot, "secondary_loaded_bg_palette"
        if local_slot < secondary_start:
            return False, None, "declared_global_slot_owned_by_primary"
        return False, None, "declared_beyond_bg_palette_total_not_loaded"

    return False, None, "unknown_tileset_kind_not_loaded"


def parse_metatile_decode_rules(source_root):
    fieldmap_h_path = source_root / "include/fieldmap.h"
    field_camera_path = source_root / "src/field_camera.c"
    fieldmap_h = read_text(fieldmap_h_path) if fieldmap_h_path.exists() else ""
    field_camera = read_text(field_camera_path) if field_camera_path.exists() else ""

    constants = {}
    for name in [
        "NUM_TILES_IN_PRIMARY_FRLG",
        "NUM_TILES_IN_PRIMARY",
        "NUM_METATILES_IN_PRIMARY_FRLG",
        "NUM_METATILES_IN_PRIMARY",
        "NUM_METATILES_TOTAL",
        "NUM_TILES_TOTAL",
        "NUM_TILES_PER_METATILE",
    ]:
        match = re.search(r"#define\s+%s\s+(\d+)" % re.escape(name), fieldmap_h)
        constants[name] = {
            "value": int(match.group(1)) if match else None,
            "source": {
                "path": "include/fieldmap.h",
                "line": line_number(fieldmap_h, match.start()) if match else None,
            },
            "found": match is not None,
        }

    return {
        "status": "decoded_import_metadata",
        "runtime_binary_metatile_required": False,
        "source_files": [
            path_status(source_root, Path("include/fieldmap.h")),
            path_status(source_root, Path("src/field_camera.c")),
        ],
        "constants": constants,
        "tile_entry_format": {
            "raw_type": "u16 little-endian",
            "tile_id_bits": "0-9",
            "hflip_bit": 10,
            "vflip_bit": 11,
            "palette_slot_bits": "12-15",
            "source": {
                "path": "include/fieldmap.h",
                "symbol": "NUM_TILES_PER_METATILE",
            },
        },
        "compact_metatile_entry_encoding": metatile_compact_entry_encoding(),
        "source_layer_slots": [
            {
                "source_layer_slot": "bottom",
                "tile_entry_indices": [0, 1, 2, 3],
                "positions": METATILE_ENTRY_POSITIONS[:4],
            },
            {
                "source_layer_slot": "top",
                "tile_entry_indices": [4, 5, 6, 7],
                "positions": METATILE_ENTRY_POSITIONS[4:],
            },
        ],
        "draw_layer_rules": [
            {
                "layer_type": "METATILE_LAYER_TYPE_NORMAL",
                "value": 0,
                "bottom_source_slot_to_bg": "Bg2",
                "top_source_slot_to_bg": "Bg1",
                "bg3_fill": "0x3014 source garbage/filler tile",
            },
            {
                "layer_type": "METATILE_LAYER_TYPE_COVERED",
                "value": 1,
                "bottom_source_slot_to_bg": "Bg3",
                "top_source_slot_to_bg": "Bg2",
                "bg1_fill": "transparent tile 0",
            },
            {
                "layer_type": "METATILE_LAYER_TYPE_SPLIT",
                "value": 2,
                "bottom_source_slot_to_bg": "Bg3",
                "top_source_slot_to_bg": "Bg1",
                "bg2_fill": "transparent tile 0",
            },
        ],
        "source_functions": source_function_refs(field_camera, "src/field_camera.c", METATILE_RULE_FUNCTIONS),
        "runtime_policy": {
            "status": "decoded_import_metadata",
            "detail": "Source metatile binary entries are decoded into Godot-friendly metadata. Godot runtime should consume generated layer/tile data, not raw GBA metatile binaries or palette banks.",
        },
    }


def metatile_source_profile_for_branch(branch):
    return "frlg" if branch == "frlg_metadata" else "emerald"


def metatile_source_profile(profile_name):
    if profile_name == "frlg":
        return {
            "name": "frlg",
            "primary_tile_count": NUM_TILES_IN_PRIMARY_FRLG,
            "primary_metatile_count": NUM_METATILES_IN_PRIMARY_FRLG,
            "total_tile_count": NUM_TILES_TOTAL,
            "total_metatile_count": NUM_METATILES_TOTAL,
        }
    return {
        "name": "emerald",
        "primary_tile_count": NUM_TILES_IN_PRIMARY,
        "primary_metatile_count": NUM_METATILES_IN_PRIMARY,
        "total_tile_count": NUM_TILES_TOTAL,
        "total_metatile_count": NUM_METATILES_TOTAL,
    }


def metatile_compact_entry_encoding():
    return {
        "version": "compact_tile_entry_v1",
        "detail": (
            "Each metatile row stores [local_metatile_id, global_metatile_id, tile_entries]. "
            "Each tile entry row stores decoded fields without repeated JSON keys; "
            "tile_entry_index, source layer slot, and source layer position are derived from array index 0-7."
        ),
        "metatile_fields": [
            "local_metatile_id",
            "global_metatile_id",
            "tile_entries",
        ],
        "tile_entry_fields": [
            "raw",
            "tile_id",
            "palette_slot",
            "flip_flags",
            "source_tileset_kind_code",
            "local_tile_id",
            "out_of_range",
        ],
        "raw_hex_format": "0x{:04X}",
        "flip_flags": {
            "hflip": 1,
            "vflip": 2,
        },
        "source_tileset_kind_codes": TILE_SOURCE_KIND_CODES,
        "source_layer_slot_by_tile_entry_index": [
            "bottom" if index < 4 else "top"
            for index in range(NUM_TILES_PER_METATILE)
        ],
        "source_layer_position_by_tile_entry_index": METATILE_ENTRY_POSITIONS,
        "derived_fields": {
            "tile_entry_index": "implicit tile entry array index 0-7",
            "raw_hex": "format raw using raw_hex_format",
            "hflip": "bool(flip_flags & 1)",
            "vflip": "bool(flip_flags & 2)",
            "source_layer_slot": "lookup by tile_entry_index",
            "source_layer_position": "lookup by tile_entry_index",
            "source_tileset_kind": "lookup source_tileset_kind_code",
            "source_tileset_kind_matches_metatile": "source_tileset_kind == metatile_binary_decode.source_kind",
        },
    }


def metatile_binary_decode_for_header(source_root, kind, branch, metatile_group, metatile_rules):
    profile_name = metatile_source_profile_for_branch(branch)
    profile = metatile_source_profile(profile_name)
    source_row = first_matching_status(
        metatile_group.get("editable_source_candidates", []) + metatile_group.get("incbin_paths", []),
        lambda path: path.endswith("/metatiles.bin"),
    )

    if source_row is None:
        return {
            "status": "missing_source_binary",
            "runtime_binary_metatile_required": False,
            "source_rules_profile": profile_name,
            "source_kind": kind,
            "source_metatiles_symbol": metatile_group.get("symbol"),
            "source_metatiles_declaration_found": metatile_group.get("declaration_found", False),
            "source_metatiles_declaration": metatile_group.get("declaration_source"),
            "source_binary": None,
            "metatile_count": 0,
            "tile_entry_count": 0,
            "source_layer_slot_counts": {},
            "tile_source_kind_counts": {},
            "out_of_range_tile_entry_count": 0,
            "out_of_range_tile_entries": [],
            "metatile_entry_encoding_ref": "metatile_decode_rules.compact_metatile_entry_encoding",
            "metatiles": [],
        }

    source_path = source_root / source_row["path"]
    raw_values = read_u16le_file(source_path)
    if len(raw_values) % NUM_TILES_PER_METATILE != 0:
        raise ValueError("{} has {} u16 entries, not divisible by {}".format(
            source_path,
            len(raw_values),
            NUM_TILES_PER_METATILE,
        ))

    metatiles = []
    out_of_range = []
    tile_source_counts = {}
    layer_counts = {}
    source_global_offset = 0 if kind == "primary" else profile["primary_metatile_count"]
    for local_metatile_id, start in enumerate(range(0, len(raw_values), NUM_TILES_PER_METATILE)):
        entries = [
            decode_metatile_tile_entry(
                raw_value,
                entry_index,
                kind,
                profile,
            )
            for entry_index, raw_value in enumerate(raw_values[start:start + NUM_TILES_PER_METATILE])
        ]
        for entry in entries:
            tile_source_counts[entry["source_tileset_kind"]] = tile_source_counts.get(entry["source_tileset_kind"], 0) + 1
            layer_counts[entry["source_layer_slot"]] = layer_counts.get(entry["source_layer_slot"], 0) + 1
            if entry["out_of_range"]:
                out_of_range.append({
                    "local_metatile_id": local_metatile_id,
                    "global_metatile_id": source_global_offset + local_metatile_id,
                    "tile_entry_index": entry["tile_entry_index"],
                    "tile_id": entry["tile_id"],
                    "source_tileset_kind": entry["source_tileset_kind"],
                    "local_tile_id": entry["local_tile_id"],
                })
        metatiles.append([
            local_metatile_id,
            source_global_offset + local_metatile_id,
            [compact_metatile_tile_entry(entry) for entry in entries],
        ])

    return {
        "status": "decoded",
        "runtime_binary_metatile_required": False,
        "source_rules_profile": profile_name,
        "source_kind": kind,
        "source_metatiles_symbol": metatile_group.get("symbol"),
        "source_metatiles_declaration_found": metatile_group.get("declaration_found", False),
        "source_metatiles_declaration": metatile_group.get("declaration_source"),
        "source_binary": source_row,
        "source_profile": profile,
        "tile_entry_format": metatile_rules.get("tile_entry_format", {}),
        "draw_layer_rules_ref": "metatile_decode_rules.draw_layer_rules",
        "metatile_count": len(metatiles),
        "tile_entry_count": len(raw_values),
        "source_layer_slot_counts": dict(sorted(layer_counts.items())),
        "tile_source_kind_counts": dict(sorted(tile_source_counts.items())),
        "out_of_range_tile_entry_count": len(out_of_range),
        "out_of_range_tile_entries": out_of_range,
        "metatile_entry_encoding_ref": "metatile_decode_rules.compact_metatile_entry_encoding",
        "metatile_entry_encoding": metatile_compact_entry_encoding(),
        "metatiles": metatiles,
    }


def compact_metatile_tile_entry(entry):
    flip_flags = 0
    if entry["hflip"]:
        flip_flags |= 1
    if entry["vflip"]:
        flip_flags |= 2
    return [
        entry["raw"],
        entry["tile_id"],
        entry["palette_slot"],
        flip_flags,
        TILE_SOURCE_KIND_CODES[entry["source_tileset_kind"]],
        entry["local_tile_id"],
        1 if entry["out_of_range"] else 0,
    ]


def decode_metatile_tile_entry(raw, entry_index, source_kind, profile):
    tile_id = raw & TILE_ENTRY_INDEX_MASK
    source_tileset_kind, local_tile_id = tile_source_for_tile_id(tile_id, profile)
    position = METATILE_ENTRY_POSITIONS[entry_index]
    return {
        "tile_entry_index": entry_index,
        "raw": raw,
        "raw_hex": "0x{:04X}".format(raw),
        "tile_id": tile_id,
        "palette_slot": (raw >> TILE_ENTRY_PALETTE_SHIFT) & 0x0F,
        "hflip": bool(raw & TILE_ENTRY_HFLIP_MASK),
        "vflip": bool(raw & TILE_ENTRY_VFLIP_MASK),
        "source_layer_slot": "bottom" if entry_index < 4 else "top",
        "source_layer_position": {
            "x": position["x"],
            "y": position["y"],
        },
        "source_tileset_kind": source_tileset_kind,
        "local_tile_id": local_tile_id,
        "source_tileset_kind_matches_metatile": source_tileset_kind == source_kind,
        "out_of_range": tile_id >= profile["total_tile_count"],
    }


def tile_source_for_tile_id(tile_id, profile):
    if tile_id < profile["primary_tile_count"]:
        return "primary", tile_id
    return "secondary", tile_id - profile["primary_tile_count"]


def frames_for_tileset_base(animation_frames, base_path):
    if not base_path:
        return []
    return [
        frame
        for frame in animation_frames
        if base_path in frame.get("tileset_base_paths", [])
    ]


def parse_tileset_headers(
    source_root,
    animation_frames=None,
    init_functions=None,
    palette_rules=None,
    metatile_rules=None,
):
    headers_path = source_root / "src/data/tilesets/headers.h"
    text = read_text(headers_path)
    declarations = parse_asset_declarations(source_root)
    animation_frames = animation_frames or []
    palette_rules = palette_rules or parse_palette_slot_rules(source_root)
    metatile_rules = metatile_rules or parse_metatile_decode_rules(source_root)
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
            palette_slot_mapping = palette_slot_mapping_for_header(
                source_root,
                kind,
                branch,
                assets["palettes"],
                palette_rules,
            )
            metatile_binary_decode = metatile_binary_decode_for_header(
                source_root,
                kind,
                branch,
                assets["metatiles"],
                metatile_rules,
            )

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
                "palette_slot_mapping": palette_slot_mapping,
                "metatile_binary_decode": metatile_binary_decode,
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


def merge_count_dicts(dicts):
    result = {}
    for values in dicts:
        for key, value in values.items():
            result[key] = result.get(key, 0) + int(value)
    return dict(sorted(result.items()))


def unique_metatile_decodes_by_source_binary(decodes):
    unique = {}
    for decode in decodes:
        source_path = decode.get("source_binary", {}).get("path")
        if not source_path or source_path in unique:
            continue
        unique[source_path] = decode
    return [
        unique[path]
        for path in sorted(unique)
    ]


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
    palette_slots = [
        slot
        for row in records
        for slot in row.get("palette_slot_mapping", {}).get("slots", [])
    ]
    active_palette_slots = [
        slot
        for row in active
        for slot in row.get("palette_slot_mapping", {}).get("slots", [])
    ]
    loaded_palette_slots = [
        slot
        for slot in palette_slots
        if slot.get("loaded_by_source_map_palette_copy")
    ]
    active_loaded_palette_slots = [
        slot
        for slot in active_palette_slots
        if slot.get("loaded_by_source_map_palette_copy")
    ]
    missing_palette_source_candidates = [
        {
            "tileset": row["symbol"],
            "local_palette_slot": slot["local_palette_slot"],
            "path": candidate["path"],
        }
        for row in records
        for slot in row.get("palette_slot_mapping", {}).get("slots", [])
        for candidate in slot.get("editable_source_candidates", [])
        if not candidate.get("exists")
    ]
    metatile_decodes = [
        row.get("metatile_binary_decode", {})
        for row in records
    ]
    active_metatile_decodes = [
        row.get("metatile_binary_decode", {})
        for row in active
    ]
    unique_metatile_decodes = unique_metatile_decodes_by_source_binary(metatile_decodes)
    active_unique_metatile_decodes = unique_metatile_decodes_by_source_binary(active_metatile_decodes)
    missing_metatile_decodes = [
        {
            "tileset": row["symbol"],
            "metatiles_symbol": row.get("metatile_binary_decode", {}).get("source_metatiles_symbol"),
            "status": row.get("metatile_binary_decode", {}).get("status"),
        }
        for row in records
        if row.get("metatile_binary_decode", {}).get("status") != "decoded"
    ]
    out_of_range_tile_entries = [
        dict({"tileset": row["symbol"]}, **entry)
        for row in records
        for entry in row.get("metatile_binary_decode", {}).get("out_of_range_tile_entries", [])
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
        "palette_slot_mapping_count": len(palette_slots),
        "active_palette_slot_mapping_count": len(active_palette_slots),
        "loaded_palette_slot_mapping_count": len(loaded_palette_slots),
        "active_loaded_palette_slot_mapping_count": len(active_loaded_palette_slots),
        "not_loaded_palette_slot_mapping_count": len(palette_slots) - len(loaded_palette_slots),
        "active_not_loaded_palette_slot_mapping_count": len(active_palette_slots) - len(active_loaded_palette_slots),
        "palette_source_incbin_count": len(palette_slots),
        "palette_existing_source_incbin_count": sum(
            1
            for slot in palette_slots
            if slot.get("source_incbin", {}).get("exists")
        ),
        "palette_editable_source_candidate_count": sum(
            len(slot.get("editable_source_candidates", []))
            for slot in palette_slots
        ),
        "palette_existing_editable_source_candidate_count": sum(
            slot.get("existing_editable_source_candidate_count", 0)
            for slot in palette_slots
        ),
        "palette_missing_editable_source_candidate_count": len(missing_palette_source_candidates),
        "palette_missing_editable_source_candidates": missing_palette_source_candidates,
        "palette_slot_count_by_source_profile": count_by(
            [
                {"source_profile": slot.get("source_profile")}
                for slot in palette_slots
            ],
            "source_profile",
        ),
        "palette_loaded_slot_count_by_source_profile": count_by(
            [
                {"source_profile": slot.get("source_profile")}
                for slot in loaded_palette_slots
            ],
            "source_profile",
        ),
        "metatile_decode_header_count": sum(
            1 for decode in metatile_decodes if decode.get("status") == "decoded"
        ),
        "active_metatile_decode_header_count": sum(
            1 for decode in active_metatile_decodes if decode.get("status") == "decoded"
        ),
        "missing_metatile_decode_header_count": len(missing_metatile_decodes),
        "missing_metatile_decodes": missing_metatile_decodes,
        "metatile_record_count": sum(int(decode.get("metatile_count", 0)) for decode in metatile_decodes),
        "active_metatile_record_count": sum(
            int(decode.get("metatile_count", 0))
            for decode in active_metatile_decodes
        ),
        "metatile_tile_entry_count": sum(int(decode.get("tile_entry_count", 0)) for decode in metatile_decodes),
        "active_metatile_tile_entry_count": sum(
            int(decode.get("tile_entry_count", 0))
            for decode in active_metatile_decodes
        ),
        "unique_metatile_source_binary_count": len(unique_metatile_decodes),
        "active_unique_metatile_source_binary_count": len(active_unique_metatile_decodes),
        "unique_metatile_record_count": sum(
            int(decode.get("metatile_count", 0))
            for decode in unique_metatile_decodes
        ),
        "active_unique_metatile_record_count": sum(
            int(decode.get("metatile_count", 0))
            for decode in active_unique_metatile_decodes
        ),
        "unique_metatile_tile_entry_count": sum(
            int(decode.get("tile_entry_count", 0))
            for decode in unique_metatile_decodes
        ),
        "active_unique_metatile_tile_entry_count": sum(
            int(decode.get("tile_entry_count", 0))
            for decode in active_unique_metatile_decodes
        ),
        "metatile_out_of_range_tile_entry_count": len(out_of_range_tile_entries),
        "metatile_out_of_range_tile_entries": out_of_range_tile_entries,
        "metatile_tile_source_kind_counts": merge_count_dicts(
            decode.get("tile_source_kind_counts", {})
            for decode in metatile_decodes
        ),
        "active_metatile_tile_source_kind_counts": merge_count_dicts(
            decode.get("tile_source_kind_counts", {})
            for decode in active_metatile_decodes
        ),
        "metatile_source_layer_slot_counts": merge_count_dicts(
            decode.get("source_layer_slot_counts", {})
            for decode in metatile_decodes
        ),
        "active_metatile_source_layer_slot_counts": merge_count_dicts(
            decode.get("source_layer_slot_counts", {})
            for decode in active_metatile_decodes
        ),
        "metatile_record_count_by_source_profile": merge_count_dicts(
            {
                decode.get("source_rules_profile"): int(decode.get("metatile_count", 0))
            }
            for decode in metatile_decodes
        ),
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
        "palette_slot_mapping_count": stats["palette_slot_mapping_count"],
        "palette_existing_editable_source_candidate_count": stats["palette_existing_editable_source_candidate_count"],
        "palette_missing_editable_source_candidate_count": stats["palette_missing_editable_source_candidate_count"],
        "metatile_record_count": stats["metatile_record_count"],
        "metatile_tile_entry_count": stats["metatile_tile_entry_count"],
        "unique_metatile_source_binary_count": stats["unique_metatile_source_binary_count"],
        "unique_metatile_record_count": stats["unique_metatile_record_count"],
        "unique_metatile_tile_entry_count": stats["unique_metatile_tile_entry_count"],
        "metatile_out_of_range_tile_entry_count": stats["metatile_out_of_range_tile_entry_count"],
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
    palette_rules = parse_palette_slot_rules(source_root)
    metatile_rules = parse_metatile_decode_rules(source_root)
    records = parse_tileset_headers(source_root, animation_frames, init_functions, palette_rules, metatile_rules)
    stats = build_stats(source_files, records, animation_frames, init_functions)
    return {
        "schema_version": 1,
        "generated_by": GENERATED_BY,
        "source_root": str(source_root),
        "source_files": source_files,
        "palette_slot_rules": palette_rules,
        "metatile_decode_rules": metatile_rules,
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
                "code": "metatile_attribute_detail_pending",
                "status": "unsupported",
                "detail": "Per-8x8 metatile tile entries are decoded, but the next Section 4 task still needs richer attribute/terrain/encounter metadata beyond the existing behavior/layer provenance.",
            },
            {
                "code": "source_equivalent_layer_renderer_pending",
                "status": "unsupported",
                "detail": "Decoded source layer slots and DrawMetatile placement rules are exported, but Godot still needs a source-equivalent layer renderer to consume them.",
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
