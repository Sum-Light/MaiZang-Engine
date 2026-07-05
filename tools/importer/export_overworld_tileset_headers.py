#!/usr/bin/env python3
"""Export source tileset header coverage for overworld asset parity."""

import argparse
import json
import re
import sys
from pathlib import Path

try:
    from PIL import Image
except ImportError:  # pragma: no cover - import-time dependency check
    raise SystemExit("Pillow is required to export overworld tileset animation frame strips: pip install Pillow")

from export_map import MAPGRID_METATILE_ID_MASK, load_map_group_index, read_u16le_file, write_json, write_manifest
from export_overworld_metatile_behavior_trace import parse_metatile_constants, parse_tile_bit_attributes
from source_probe import load_config, path_status, symbol_to_tileset_dir, to_project_path


GENERATED_BY = "tools/importer/export_overworld_tileset_headers.py"
REPORT_PATH = Path("overworld/tileset_header_report.json")
TILESET_ANIMATION_ASSET_DIR = Path("tileset_anims")

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
    "include/constants/metatile_labels.h",
]
METATILE_LABEL_HEADER = Path("include/constants/metatile_labels.h")
LAYOUTS_JSON = Path("data/layouts/layouts.json")

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
FUNCTION_DEF_RE = re.compile(
    r"(?P<prefix>(?:static\s+)?void)\s+"
    r"(?P<name>(?:InitTilesetAnim|TilesetAnim|QueueAnimTiles|BlendAnimPalette)_[A-Za-z0-9_]+)"
    r"\s*\((?P<params>[^)]*)\)\s*\{",
    re.S,
)
ANIM_POINTER_ARRAY_RE = re.compile(
    r"(?:static\s+)?(?:const\s+)?u16\s*\*const\s+"
    r"(?P<symbol>(?:g|s)TilesetAnims_[A-Za-z0-9_]+)"
    r"\[\]\s*=\s*\{(?P<body>.*?)\};",
    re.S,
)
ANIM_VDEST_ARRAY_RE = re.compile(
    r"u16\s*\*const\s+"
    r"(?P<symbol>gTilesetAnims_[A-Za-z0-9_]+_VDests)"
    r"\[\]\s*=\s*\{(?P<body>.*?)\};",
    re.S,
)
PALETTE_DEFINE_RE = re.compile(
    r"#define\s+"
    r"(?P<name>NUM_PALS_IN_PRIMARY_FRLG|NUM_PALS_IN_PRIMARY|NUM_PALS_TOTAL)"
    r"\s+(?P<value>\d+)"
)
METATILE_LABEL_DEFINE_RE = re.compile(
    r"^\s*#define\s+"
    r"(?P<name>METATILE_[A-Za-z0-9_]+)"
    r"\s+(?P<value>0x[0-9A-Fa-f]+|\d+)\b"
)
METATILE_LABEL_COMMENT_RE = re.compile(r"^\s*//\s*(?P<group>.*?)\s*$")

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

METATILE_ATTRIBUTE_RULE_FUNCTIONS = [
    "ExtractMetatileAttribute",
    "GetAttributeByMetatileIdAndMapLayout",
    "MapGridGetMetatileAttributeAt",
    "MapGridGetMetatileBehaviorAt",
    "MapGridGetMetatileLayerTypeAt",
    "MapGridGetCollisionAt",
    "MapGridGetElevationAt",
]

NUM_TILES_IN_PRIMARY = 512
NUM_TILES_IN_PRIMARY_FRLG = 640
NUM_METATILES_IN_PRIMARY = 512
NUM_METATILES_IN_PRIMARY_FRLG = 640
NUM_METATILES_TOTAL = 1024
NUM_TILES_TOTAL = 1024
NUM_TILES_PER_METATILE = 8
TILE_SIZE_4BPP_BYTES = 32
TILE_SIZE_PIXELS = 8
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
TILE_ENTRY_INDEX_MASK = 0x03FF
TILE_ENTRY_HFLIP_MASK = 0x0400
TILE_ENTRY_VFLIP_MASK = 0x0800
TILE_ENTRY_PALETTE_SHIFT = 12
TILE_SOURCE_KIND_CODES = {
    "primary": 0,
    "secondary": 1,
}
METATILE_LABEL_RESOLUTION_CODES = {
    "source_group": 0,
    "label_prefix": 1,
    "frlg_suffix_alias": 2,
    "rs_prefix_alias": 3,
}
METATILE_ATTR_BEHAVIOR_MASK = 0x00FF
METATILE_ATTR_LAYER_MASK = 0xF000
METATILE_ATTR_BEHAVIOR_SHIFT = 0
METATILE_ATTR_LAYER_SHIFT = 12
METATILE_ATTR_BEHAVIOR_MASK_FRLG = 0x000001FF
METATILE_ATTR_BEHAVIOR_SHIFT_FRLG = 0
METATILE_ATTR_TERRAIN_MASK_FRLG = 0x00003E00
METATILE_ATTR_TERRAIN_SHIFT_FRLG = 9
METATILE_ATTR_ENCOUNTER_TYPE_MASK_FRLG = 0x07000000
METATILE_ATTR_ENCOUNTER_TYPE_SHIFT_FRLG = 24
METATILE_ATTR_LAYER_MASK_FRLG = 0x60000000
METATILE_ATTR_LAYER_SHIFT_FRLG = 29
METATILE_LAYER_TYPE_NAMES = {
    0: "METATILE_LAYER_TYPE_NORMAL",
    1: "METATILE_LAYER_TYPE_COVERED",
    2: "METATILE_LAYER_TYPE_SPLIT",
}
TILE_ENCOUNTER_TYPE_NAMES = {
    0: "TILE_ENCOUNTER_NONE",
    1: "TILE_ENCOUNTER_LAND",
    2: "TILE_ENCOUNTER_WATER",
}
TILE_TERRAIN_TYPE_NAMES = {
    0: "TILE_TERRAIN_NORMAL",
    1: "TILE_TERRAIN_GRASS",
    2: "TILE_TERRAIN_WATER",
    3: "TILE_TERRAIN_WATERFALL",
}
METATILE_AFFORDANCE_FLAG_CODES = {
    "has_encounters": 1,
    "surfable": 2,
    "land_encounter_affordance": 4,
    "water_encounter_affordance": 8,
    "unused_traversable_hint": 16,
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


def slugify_asset_name(value):
    slug = re.sub(r"[^A-Za-z0-9]+", "_", value).strip("_").lower()
    return slug or "asset"


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


def find_matching_brace(text, open_index):
    depth = 0
    for index in range(open_index, len(text)):
        char = text[index]
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return index
    return -1


def parse_tileset_anim_functions(text):
    functions = {}
    for match in FUNCTION_DEF_RE.finditer(text):
        open_index = text.find("{", match.end() - 1)
        close_index = find_matching_brace(text, open_index)
        if open_index < 0 or close_index < 0:
            continue
        functions[match.group("name")] = {
            "name": match.group("name"),
            "params": normalize_ws(match.group("params")),
            "body": text[open_index + 1:close_index],
            "source": {
                "path": "src/tileset_anims.c",
                "line": line_number(text, match.start()),
            },
        }
    return functions


def parse_anim_pointer_arrays(text):
    arrays = {}
    for match in ANIM_POINTER_ARRAY_RE.finditer(text):
        body = match.group("body")
        symbols = [
            value.strip()
            for value in re.split(r",", body)
            if value.strip()
        ]
        arrays[match.group("symbol")] = {
            "symbol": match.group("symbol"),
            "frame_symbols": symbols,
            "frame_count": len(symbols),
            "unique_frame_count": len(set(symbols)),
            "source": {
                "path": "src/tileset_anims.c",
                "line": line_number(text, match.start()),
            },
        }
    return arrays


def parse_tileset_anim_vdest_arrays(text):
    arrays = {}
    for match in ANIM_VDEST_ARRAY_RE.finditer(text):
        body = match.group("body")
        tile_offsets = [
            {
                "tile_offset_expr": offset.get("expr"),
                "tile_offset": offset.get("value"),
                "tile_source_kind": source_kind_for_tile_offset(offset.get("value")),
                "tile_local_id": local_tile_id_for_tile_offset(offset.get("value")),
            }
            for expr in re.findall(r"TILE_OFFSET_4BPP\((.*?)\)", body, flags=re.S)
            for offset in [parse_tile_offset_expr(expr)]
        ]
        arrays[match.group("symbol")] = {
            "symbol": match.group("symbol"),
            "tile_offsets": tile_offsets,
            "count": len(tile_offsets),
            "source": {
                "path": "src/tileset_anims.c",
                "line": line_number(text, match.start()),
            },
        }
    return arrays


def eval_tileset_anim_expr(expr):
    expr = normalize_ws(expr)
    expr = re.sub(r"\bNUM_TILES_IN_PRIMARY\b", str(NUM_TILES_IN_PRIMARY), expr)
    expr = re.sub(r"\bTILE_SIZE_4BPP\b", str(TILE_SIZE_4BPP_BYTES), expr)
    expr = re.sub(r"\bPLTT_SIZE_4BPP\b", "32", expr)
    if not re.fullmatch(r"[0-9xXa-fA-F+\-*/() ]+", expr):
        return None
    try:
        return int(eval(expr, {"__builtins__": {}}, {}))
    except (ArithmeticError, SyntaxError, ValueError):
        return None


def parse_tile_offset_expr(expr):
    value = eval_tileset_anim_expr(expr)
    return {
        "expr": normalize_ws(expr),
        "value": value,
    }


def parse_size_expr(expr):
    value = eval_tileset_anim_expr(expr)
    tile_count = None
    if value is not None and value % TILE_SIZE_4BPP_BYTES == 0:
        tile_count = value // TILE_SIZE_4BPP_BYTES
    return {
        "expr": normalize_ws(expr),
        "bytes": value,
        "tile_count": tile_count,
    }


def source_kind_for_tile_offset(tile_offset):
    if tile_offset is None:
        return None
    return "primary" if int(tile_offset) < NUM_TILES_IN_PRIMARY else "secondary"


def local_tile_id_for_tile_offset(tile_offset):
    if tile_offset is None:
        return None
    return int(tile_offset) if int(tile_offset) < NUM_TILES_IN_PRIMARY else int(tile_offset) - NUM_TILES_IN_PRIMARY


def compact_source_ref(source):
    return {
        "path": source.get("path"),
        "line": source.get("line"),
    }


def parse_init_function_details(functions):
    rows = []
    for name in sorted(functions):
        if not name.startswith("InitTilesetAnim_"):
            continue
        function = functions[name]
        body = function["body"]
        counter_kind = "primary" if "sPrimaryTilesetAnimCallback" in body else "secondary"
        counter_symbol = "sPrimaryTilesetAnimCounter" if counter_kind == "primary" else "sSecondaryTilesetAnimCounter"
        max_symbol = "{}Max".format(counter_symbol)
        callback_symbol = "sPrimaryTilesetAnimCallback" if counter_kind == "primary" else "sSecondaryTilesetAnimCallback"
        counter_match = re.search(r"%s\s*=\s*([^;]+);" % re.escape(counter_symbol), body)
        max_match = re.search(r"%s\s*=\s*([^;]+);" % re.escape(max_symbol), body)
        callback_match = re.search(r"%s\s*=\s*([^;]+);" % re.escape(callback_symbol), body)
        counter_expr = normalize_ws(counter_match.group(1)) if counter_match else None
        max_expr = normalize_ws(max_match.group(1)) if max_match else None
        callback_expr = normalize_ws(callback_match.group(1)) if callback_match else None
        rows.append({
            "function": name,
            "counter_kind": counter_kind,
            "counter_symbol": counter_symbol,
            "counter_initial_expr": counter_expr,
            "counter_initial_value": eval_tileset_anim_expr(counter_expr) if counter_expr else None,
            "counter_max_symbol": max_symbol,
            "counter_max_expr": max_expr,
            "counter_max_value": eval_tileset_anim_expr(max_expr) if max_expr else None,
            "counter_max_source": "inherits_primary_counter_max" if max_expr == "sPrimaryTilesetAnimCounterMax" else "literal_or_expression",
            "callback_symbol": callback_expr,
            "has_tile_animation_callback": callback_expr not in (None, "NULL"),
            "wrap_behavior": "if (++{counter} >= {max}) {counter} = 0".format(
                counter=counter_symbol,
                max=max_symbol,
            ),
            "source": compact_source_ref(function["source"]),
        })
    return rows


def parse_tileset_anim_callback_events(functions):
    rows = []
    for name in sorted(functions):
        if not name.startswith("TilesetAnim_"):
            continue
        body = functions[name]["body"]
        pattern = re.compile(
            r"if\s*\(\s*timer\s*%\s*(?P<mod>\d+)\s*==\s*(?P<phase>\d+)\s*\)\s*"
            r"(?P<block>\{.*?\}|[^{};]+;)",
            re.S,
        )
        events = []
        for match in pattern.finditer(body):
            block = match.group("block")
            for call in re.finditer(
                r"(?P<queue>(?:QueueAnimTiles|BlendAnimPalette)_[A-Za-z0-9_]+)\s*"
                r"\((?P<args>[^)]*)\)\s*;",
                block,
            ):
                args = [normalize_ws(arg) for arg in call.group("args").split(",") if arg.strip()]
                events.append({
                    "queue_function": call.group("queue"),
                    "trigger_modulo": int(match.group("mod")),
                    "trigger_phase": int(match.group("phase")),
                    "duration_frames": int(match.group("mod")),
                    "timer_argument_expr": args[0] if args else None,
                    "extra_argument_exprs": args[1:],
                    "source_kind": "palette_blend" if call.group("queue").startswith("BlendAnimPalette_") else "tile_copy",
                })
        rows.append({
            "callback": name,
            "source": compact_source_ref(functions[name]["source"]),
            "event_count": len(events),
            "events": events,
        })
    return rows


def parse_source_array_from_expr(expr):
    expr = normalize_ws(expr)
    match = re.match(r"(?P<array>(?:g|s)TilesetAnims_[A-Za-z0-9_]+)\s*\[", expr)
    return match.group("array") if match else None


def parse_vdest_array_from_expr(expr):
    expr = normalize_ws(expr)
    match = re.match(r"(?P<array>gTilesetAnims_[A-Za-z0-9_]+_VDests)\s*\[", expr)
    return match.group("array") if match else None


def parse_append_arguments(argument_text):
    args = []
    current = []
    depth = 0
    for char in argument_text:
        if char == "," and depth == 0:
            args.append(normalize_ws("".join(current)))
            current = []
            continue
        current.append(char)
        if char == "(":
            depth += 1
        elif char == ")":
            depth -= 1
    if current:
        args.append(normalize_ws("".join(current)))
    return args


def queue_append_records(function, pointer_arrays, vdest_arrays):
    rows = []
    for match in re.finditer(r"AppendTilesetAnimToBuffer\s*\((?P<args>.*?)\)\s*;", function["body"], re.S):
        args = parse_append_arguments(match.group("args"))
        if len(args) != 3:
            continue
        source_expr, dest_expr, size_expr = args
        source_array = parse_source_array_from_expr(source_expr)
        vdest_array = parse_vdest_array_from_expr(dest_expr)
        direct_offsets = re.findall(r"TILE_OFFSET_4BPP\((.*?)\)", dest_expr, flags=re.S)
        direct_offset = parse_tile_offset_expr(direct_offsets[0]) if direct_offsets else {"expr": None, "value": None}
        size = parse_size_expr(size_expr)
        tile_offsets = []
        if vdest_array and vdest_array in vdest_arrays:
            tile_offsets = vdest_arrays[vdest_array]["tile_offsets"]
        elif direct_offset.get("value") is not None:
            tile_offsets = [{
                "tile_offset_expr": direct_offset.get("expr"),
                "tile_offset": direct_offset.get("value"),
                "tile_source_kind": source_kind_for_tile_offset(direct_offset.get("value")),
                "tile_local_id": local_tile_id_for_tile_offset(direct_offset.get("value")),
            }]
        rows.append({
            "source_expr": source_expr,
            "source_array": source_array,
            "source_array_frame_count": pointer_arrays.get(source_array, {}).get("frame_count"),
            "dest_expr": dest_expr,
            "dest_kind": "vdest_array" if vdest_array else "direct_tile_offset",
            "vdest_array": vdest_array,
            "tile_offsets": tile_offsets,
            "size_expr": size["expr"],
            "byte_count": size["bytes"],
            "tile_count": size["tile_count"],
        })
    return rows


def queue_palette_records(function):
    rows = []
    if "CpuCopy16" not in function["body"] and "BlendPalette" not in function["body"]:
        return rows
    rows.append({
        "status": "source_color_animation_metadata_only",
        "uses_cpu_copy16": "CpuCopy16" in function["body"],
        "uses_blend_palette": "BlendPalette" in function["body"],
        "runtime_policy": "Use Godot-native Shader/Material/Animation parameters for visible color changes; do not expose GBA palette runtime.",
    })
    return rows


def affected_metatile_summary_for_targets(records, tile_offsets, tile_count):
    if not tile_offsets or tile_count is None:
        return {
            "status": "unresolved_target_or_size",
            "affected_tile_range_count": 0,
            "affected_metatile_reference_count": 0,
            "affected_unique_metatile_count": 0,
            "samples": [],
        }
    ranges = []
    for target in tile_offsets:
        start = target.get("tile_offset")
        if start is None:
            continue
        ranges.append((int(start), int(start) + int(tile_count) - 1))
    if not ranges:
        return {
            "status": "unresolved_target_or_size",
            "affected_tile_range_count": 0,
            "affected_metatile_reference_count": 0,
            "affected_unique_metatile_count": 0,
            "samples": [],
        }

    count = 0
    unique = {}
    samples = []
    for header in records:
        if not header.get("active_in_emerald"):
            continue
        for entry in iter_metatile_tile_entries(header):
            tile_id = int(entry["tile_id"])
            if not any(start <= tile_id <= end for start, end in ranges):
                continue
            count += 1
            key = (
                entry["owner_tileset_symbol"],
                entry["global_metatile_id"],
                entry["local_metatile_id"],
            )
            unique[key] = [
                entry["owner_tileset_symbol"],
                entry["global_metatile_id"],
                entry["local_metatile_id"],
            ]
            if len(samples) < 8:
                samples.append({
                    "tileset": entry["owner_tileset_symbol"],
                    "global_metatile_id": entry["global_metatile_id"],
                    "local_metatile_id": entry["local_metatile_id"],
                    "tile_entry_index": entry["tile_entry_index"],
                    "tile_id": tile_id,
                })
    return {
        "status": "decoded",
        "affected_tile_range_count": len(ranges),
        "affected_tile_ranges": [
            {
                "start_tile_id": start,
                "end_tile_id": end,
                "tile_count": end - start + 1,
            }
            for start, end in ranges
        ],
        "affected_tile_ids": sorted({
            tile_id
            for start, end in ranges
            for tile_id in range(start, end + 1)
        }),
        "affected_metatile_reference_count": count,
        "affected_unique_metatile_count": len(unique),
        "affected_metatile_ids": [
            unique[key]
            for key in sorted(unique)
        ],
        "compact_metatile_id_fields": [
            "tileset_symbol",
            "global_metatile_id",
            "local_metatile_id",
        ],
        "samples": samples,
    }


def build_tileset_animation_schedule_trace(source_root, records, animation_frames):
    path = Path(source_root) / "src/tileset_anims.c"
    if not path.exists():
        return {
            "status": "missing_source_file",
            "source": path_status(Path(source_root), Path("src/tileset_anims.c")),
            "init_function_count": 0,
            "callback_count": 0,
            "queue_function_count": 0,
            "tile_copy_queue_function_count": 0,
            "tile_copy_append_count": 0,
        }
    text = read_text(path)
    functions = parse_tileset_anim_functions(text)
    pointer_arrays = parse_anim_pointer_arrays(text)
    vdest_arrays = parse_tileset_anim_vdest_arrays(text)
    init_rows = parse_init_function_details(functions)
    callback_rows = parse_tileset_anim_callback_events(functions)
    frame_symbols = {frame["symbol"] for frame in animation_frames}

    queue_rows = []
    append_rows = []
    for name in sorted(functions):
        if not (name.startswith("QueueAnimTiles_") or name.startswith("BlendAnimPalette_")):
            continue
        function = functions[name]
        appends = queue_append_records(function, pointer_arrays, vdest_arrays)
        palettes = queue_palette_records(function)
        queue_rows.append({
            "function": name,
            "source": compact_source_ref(function["source"]),
            "kind": "palette_blend" if name.startswith("BlendAnimPalette_") else "tile_copy",
            "append_count": len(appends),
            "palette_record_count": len(palettes),
            "appends": appends,
            "palette_records": palettes,
        })
        for append_index, append in enumerate(appends):
            affected = affected_metatile_summary_for_targets(
                records,
                append.get("tile_offsets", []),
                append.get("tile_count"),
            )
            append_rows.append(dict(
                append,
                **{
                    "queue_function": name,
                    "append_index": append_index,
                    "source_frame_symbol_count": len(pointer_arrays.get(append.get("source_array"), {}).get("frame_symbols", [])),
                    "source_frame_symbols": [
                        symbol
                        for symbol in pointer_arrays.get(append.get("source_array"), {}).get("frame_symbols", [])
                        if symbol in frame_symbols
                    ],
                    "affected_metatiles": affected,
                },
            ))

    queue_by_name = {row["function"]: row for row in queue_rows}
    event_rows = []
    for callback in callback_rows:
        for event_index, event in enumerate(callback["events"]):
            queue = queue_by_name.get(event["queue_function"], {})
            event_rows.append({
                "callback": callback["callback"],
                "event_index": event_index,
                "queue_function": event["queue_function"],
                "kind": event["source_kind"],
                "trigger_modulo": event["trigger_modulo"],
                "trigger_phase": event["trigger_phase"],
                "duration_frames": event["duration_frames"],
                "timer_argument_expr": event["timer_argument_expr"],
                "extra_argument_exprs": event["extra_argument_exprs"],
                "append_count": queue.get("append_count", 0),
            })

    active_callback_symbols = sorted({
        row.get("callback", {}).get("symbol")
        for row in records
        if row.get("active_in_emerald") and row.get("callback", {}).get("has_callback")
    })
    active_init_rows = [
        row for row in init_rows
        if row["function"] in active_callback_symbols
    ]
    tile_copy_event_count = sum(1 for row in event_rows if row["kind"] == "tile_copy")
    palette_event_count = sum(1 for row in event_rows if row["kind"] == "palette_blend")
    return {
        "status": "decoded_source_schedule_metadata",
        "runtime_tileset_animation_required": False,
        "source_color_runtime_required": False,
        "source_palette_runtime_required": False,
        "source": path_status(Path(source_root), Path("src/tileset_anims.c")),
        "scheduler_source": {
            "update_order": [
                "ResetTilesetAnimBuffer",
                "++sPrimaryTilesetAnimCounter with wrap at sPrimaryTilesetAnimCounterMax",
                "++sSecondaryTilesetAnimCounter with wrap at sSecondaryTilesetAnimCounterMax",
                "sPrimaryTilesetAnimCallback(counter)",
                "sSecondaryTilesetAnimCallback(counter)",
                "TransferTilesetAnimsBuffer DmaCopy16 queued copies",
            ],
            "buffer_capacity": 20,
            "tile_size_4bpp_bytes": TILE_SIZE_4BPP_BYTES,
        },
        "init_function_count": len(init_rows),
        "active_init_function_count": len(active_init_rows),
        "callback_count": len(callback_rows),
        "event_count": len(event_rows),
        "tile_copy_event_count": tile_copy_event_count,
        "palette_event_count": palette_event_count,
        "queue_function_count": len(queue_rows),
        "tile_copy_queue_function_count": sum(1 for row in queue_rows if row["kind"] == "tile_copy"),
        "palette_queue_function_count": sum(1 for row in queue_rows if row["kind"] == "palette_blend"),
        "tile_copy_append_count": len(append_rows),
        "direct_tile_offset_append_count": sum(1 for row in append_rows if row["dest_kind"] == "direct_tile_offset"),
        "vdest_array_append_count": sum(1 for row in append_rows if row["dest_kind"] == "vdest_array"),
        "append_with_affected_metatile_count": sum(
            1
            for row in append_rows
            if row.get("affected_metatiles", {}).get("affected_unique_metatile_count", 0) > 0
        ),
        "affected_metatile_reference_count": sum(
            int(row.get("affected_metatiles", {}).get("affected_metatile_reference_count", 0))
            for row in append_rows
        ),
        "affected_unique_metatile_count_max_per_append": max(
            [int(row.get("affected_metatiles", {}).get("affected_unique_metatile_count", 0)) for row in append_rows] or [0]
        ),
        "pointer_array_count": len(pointer_arrays),
        "vdest_array_count": len(vdest_arrays),
        "init_functions": init_rows,
        "callbacks": callback_rows,
        "events": event_rows,
        "queue_functions": queue_rows,
        "tile_copy_appends": append_rows,
        "unsupported_or_metadata_only": [
            {
                "code": "battle_dome_palette_blend_metadata_only",
                "status": "metadata_only",
                "detail": "Battle Dome floor lights copy palette data and blend source colors; Godot runtime must use native Shader/Material/Animation color parameters instead of exposing GBA palette buffers.",
            }
        ] if palette_event_count else [],
    }


def tileset_callback_schedule_metadata(callback_symbol, schedule_init_by_function, schedule_events_by_callback):
    if callback_symbol == "NULL":
        return {}
    if not schedule_init_by_function and not schedule_events_by_callback:
        return {}
    schedule_trace = schedule_init_by_function.get(callback_symbol)
    event_callback_symbol = (
        schedule_trace.get("callback_symbol")
        if schedule_trace
        else callback_symbol
    )
    callback_schedule_events = []
    if event_callback_symbol != "NULL":
        callback_schedule_events = schedule_events_by_callback.get(event_callback_symbol, [])
    return {
        "schedule_trace": schedule_trace,
        "schedule_event_callback_symbol": event_callback_symbol,
        "schedule_event_count": len(callback_schedule_events),
        "tile_copy_event_count": sum(
            1 for event in callback_schedule_events if event.get("kind") == "tile_copy"
        ),
        "palette_event_count": sum(
            1 for event in callback_schedule_events if event.get("kind") == "palette_blend"
        ),
        "schedule_events": callback_schedule_events,
    }


def attach_tileset_animation_schedule_trace(records, animation_schedule_trace):
    schedule_init_by_function = {
        row["function"]: row
        for row in animation_schedule_trace.get("init_functions", [])
    }
    schedule_events_by_callback = {}
    for event in animation_schedule_trace.get("events", []):
        schedule_events_by_callback.setdefault(event.get("callback"), []).append(event)

    for row in records:
        callback = row.get("callback", {})
        callback_symbol = callback.get("symbol")
        callback.update(tileset_callback_schedule_metadata(
            callback_symbol,
            schedule_init_by_function,
            schedule_events_by_callback,
        ))


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


def parse_metatile_attribute_rules(source_root):
    global_fieldmap_path = source_root / "include/global.fieldmap.h"
    fieldmap_path = source_root / "src/fieldmap.c"
    global_fieldmap = read_text(global_fieldmap_path) if global_fieldmap_path.exists() else ""
    fieldmap_c = read_text(fieldmap_path) if fieldmap_path.exists() else ""
    behavior_context = metatile_behavior_context(source_root)

    return {
        "status": "decoded_import_metadata",
        "runtime_binary_metatile_attributes_required": False,
        "source_files": [
            path_status(source_root, Path("include/global.fieldmap.h")),
            path_status(source_root, Path("src/fieldmap.c")),
            path_status(source_root, Path("include/constants/metatile_behaviors.h")),
            path_status(source_root, Path("src/metatile_behavior.c")),
        ],
        "profiles": {
            "emerald": metatile_attribute_source_profile("emerald"),
            "frlg": metatile_attribute_source_profile("frlg"),
        },
        "behavior_names_by_id": behavior_context["behavior_names_by_id"],
        "behavior_affordances_by_name": behavior_context["behavior_affordances_by_name"],
        "behavior_affordance_source": behavior_context["summary"],
        "compact_metatile_attribute_encoding": metatile_attribute_compact_record_encoding(),
        "map_grid_block_fields": {
            "metatile_id": {
                "status": "map_grid_block_field",
                "raw_type": "u16 little-endian",
                "mask": "0x03FF",
                "shift": 0,
                "bits": "0-9",
                "source": source_define_ref(global_fieldmap, "include/global.fieldmap.h", "MAPGRID_METATILE_ID_MASK"),
            },
            "collision": {
                "status": "map_grid_block_field",
                "raw_type": "u16 little-endian",
                "mask": "0x0C00",
                "shift": 10,
                "bits": "10-11",
                "source": source_define_ref(global_fieldmap, "include/global.fieldmap.h", "MAPGRID_COLLISION_MASK"),
                "detail": "Collision is stored per layout map-grid block in data/layouts/*/map.bin, not per metatile attribute record.",
            },
            "elevation": {
                "status": "map_grid_block_field",
                "raw_type": "u16 little-endian",
                "mask": "0xF000",
                "shift": 12,
                "bits": "12-15",
                "source": source_define_ref(global_fieldmap, "include/global.fieldmap.h", "MAPGRID_ELEVATION_MASK"),
                "detail": "Elevation is stored per layout map-grid block in data/layouts/*/map.bin, not per metatile attribute record.",
            },
        },
        "attribute_enums": {
            "layer_type_names": enum_name_rows(METATILE_LAYER_TYPE_NAMES),
            "tile_encounter_type_names": enum_name_rows(TILE_ENCOUNTER_TYPE_NAMES),
            "tile_terrain_type_names": enum_name_rows(TILE_TERRAIN_TYPE_NAMES),
        },
        "source_functions": source_function_refs(
            fieldmap_c,
            "src/fieldmap.c",
            METATILE_ATTRIBUTE_RULE_FUNCTIONS,
        ),
        "runtime_policy": {
            "status": "decoded_import_metadata",
            "detail": (
                "Source metatile attribute records are decoded at import time. "
                "Godot runtime should consume behavior, layer type, encounter affordance, "
                "and map-grid collision/elevation metadata instead of raw GBA attribute binaries."
            ),
        },
    }


def metatile_behavior_context(source_root):
    constants_path = source_root / "include/constants/metatile_behaviors.h"
    behavior_path = source_root / "src/metatile_behavior.c"
    constants_text = read_text(constants_path) if constants_path.exists() else ""
    behavior_text = read_text(behavior_path) if behavior_path.exists() else ""
    constants = parse_metatile_constants(constants_text)
    bit_attrs = parse_tile_bit_attributes(behavior_text, constants["constant_by_name"])
    behavior_names_by_id = {
        str(row["id"]): row["name"]
        for row in constants.get("constants", [])
    }
    row_by_behavior = {
        row["behavior"]: row
        for row in bit_attrs.get("rows", [])
    }
    behavior_affordances_by_name = {
        name: {
            "flags": row.get("flags", []),
            "has_encounters": bool(row.get("has_encounters")),
            "surfable": bool(row.get("surfable")),
            "unused_traversable_hint": bool(row.get("unused_traversable_hint")),
        }
        for name, row in row_by_behavior.items()
    }
    return {
        "behavior_names_by_id": behavior_names_by_id,
        "behavior_rows_by_name": row_by_behavior,
        "behavior_affordances_by_name": behavior_affordances_by_name,
        "summary": {
            "constants_source": "include/constants/metatile_behaviors.h",
            "tile_bit_attributes_source": bit_attrs.get("source"),
            "constant_count": len(constants.get("constants", [])),
            "explicit_tile_bit_attribute_count": len(bit_attrs.get("explicit_rows", [])),
            "encounter_behavior_count": len(bit_attrs.get("encounter_behaviors", [])),
            "surfable_behavior_count": len(bit_attrs.get("surfable_behaviors", [])),
            "affordance_flag_codes": METATILE_AFFORDANCE_FLAG_CODES,
            "encounter_affordance_detail": (
                "Rows with TILE_FLAG_HAS_ENCOUNTERS are exported as encounter affordances; "
                "rows with both TILE_FLAG_HAS_ENCOUNTERS and TILE_FLAG_SURFABLE are water encounter affordances."
            ),
        },
    }


def source_define_ref(text, source_file, symbol):
    match = re.search(r"#define\s+%s\b" % re.escape(symbol), text)
    return {
        "path": source_file,
        "symbol": symbol,
        "line": line_number(text, match.start()) if match else None,
        "found": match is not None,
    }


def enum_name_rows(names_by_value):
    return [
        {
            "value": value,
            "name": name,
        }
        for value, name in sorted(names_by_value.items())
    ]


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


def metatile_attribute_source_profile(profile_name):
    if profile_name == "frlg":
        return dict(
            metatile_source_profile("frlg"),
            **{
                "record_raw_type": "u32 little-endian",
                "record_byte_count": 4,
                "source_runtime_pointer": "const u32 * cast from Tileset.metatileAttributes",
                "fields": {
                    "behavior": attribute_field(
                        "METATILE_ATTRIBUTE_BEHAVIOR",
                        METATILE_ATTR_BEHAVIOR_MASK_FRLG,
                        METATILE_ATTR_BEHAVIOR_SHIFT_FRLG,
                        "decoded",
                        "0-8",
                    ),
                    "terrain_type": attribute_field(
                        "METATILE_ATTRIBUTE_TERRAIN",
                        METATILE_ATTR_TERRAIN_MASK_FRLG,
                        METATILE_ATTR_TERRAIN_SHIFT_FRLG,
                        "decoded",
                        "9-13",
                    ),
                    "encounter_type": attribute_field(
                        "METATILE_ATTRIBUTE_ENCOUNTER_TYPE",
                        METATILE_ATTR_ENCOUNTER_TYPE_MASK_FRLG,
                        METATILE_ATTR_ENCOUNTER_TYPE_SHIFT_FRLG,
                        "decoded",
                        "24-26",
                    ),
                    "layer_type": attribute_field(
                        "METATILE_ATTRIBUTE_LAYER_TYPE",
                        METATILE_ATTR_LAYER_MASK_FRLG,
                        METATILE_ATTR_LAYER_SHIFT_FRLG,
                        "decoded",
                        "29-30",
                    ),
                },
            },
        )
    return dict(
        metatile_source_profile("emerald"),
        **{
            "record_raw_type": "u16 little-endian",
            "record_byte_count": 2,
            "source_runtime_pointer": "const u16 * Tileset.metatileAttributes",
            "fields": {
                "behavior": attribute_field(
                    "METATILE_ATTRIBUTE_BEHAVIOR",
                    METATILE_ATTR_BEHAVIOR_MASK,
                    METATILE_ATTR_BEHAVIOR_SHIFT,
                    "decoded",
                    "0-7",
                ),
                "terrain_type": attribute_field(
                    "METATILE_ATTRIBUTE_TERRAIN",
                    None,
                    None,
                    "not_encoded_in_emerald_attributes",
                    None,
                    "Emerald masks METATILE_ATTRIBUTE_TERRAIN with 0xFFFFFFFF, so no standalone terrain bitfield is encoded.",
                ),
                "encounter_type": attribute_field(
                    "METATILE_ATTRIBUTE_ENCOUNTER_TYPE",
                    None,
                    None,
                    "not_encoded_in_emerald_attributes",
                    None,
                    "Emerald masks METATILE_ATTRIBUTE_ENCOUNTER_TYPE with 0xFFFFFFFF, so encounter affordance is derived from behavior flags.",
                ),
                "layer_type": attribute_field(
                    "METATILE_ATTRIBUTE_LAYER_TYPE",
                    METATILE_ATTR_LAYER_MASK,
                    METATILE_ATTR_LAYER_SHIFT,
                    "decoded",
                    "12-15",
                ),
            },
        },
    )


def parse_metatile_label_rules(source_root):
    path = source_root / METATILE_LABEL_HEADER
    if not path.exists():
        return {
            "status": "missing_source_file",
            "source": path_status(source_root, METATILE_LABEL_HEADER),
            "label_count": 0,
            "source_group_count": 0,
            "source_tileset_group_count": 0,
            "non_tileset_group_count": 0,
            "groups": [],
            "labels": [],
            "labels_by_name": {},
            "compact_label_encoding": metatile_label_compact_record_encoding(),
            "compact_reverse_lookup_encoding": metatile_label_reverse_lookup_encoding(),
            "alias_policy": metatile_label_alias_policy(),
        }

    text = read_text(path)
    groups = []
    group_by_name = {}
    labels = []
    current_group = None
    current_group_line = None

    for line_index, raw_line in enumerate(text.splitlines(), 1):
        comment_match = METATILE_LABEL_COMMENT_RE.match(raw_line)
        if comment_match:
            comment = comment_match.group("group").strip()
            if comment:
                current_group = comment
                current_group_line = line_index
                if current_group not in group_by_name:
                    row = {
                        "name": current_group,
                        "source": {
                            "path": to_project_path(METATILE_LABEL_HEADER),
                            "line": current_group_line,
                        },
                        "source_tileset_symbol": (
                            current_group
                            if current_group.startswith("gTileset_")
                            else None
                        ),
                        "label_count": 0,
                        "label_names": [],
                    }
                    group_by_name[current_group] = row
                    groups.append(row)
            continue

        define_match = METATILE_LABEL_DEFINE_RE.match(raw_line)
        if not define_match:
            continue

        name = define_match.group("name")
        value_text = define_match.group("value")
        metatile_id = int(value_text, 0)
        if current_group is None:
            current_group = "Ungrouped"
            current_group_line = line_index
            if current_group not in group_by_name:
                row = {
                    "name": current_group,
                    "source": {
                        "path": to_project_path(METATILE_LABEL_HEADER),
                        "line": current_group_line,
                    },
                    "source_tileset_symbol": None,
                    "label_count": 0,
                    "label_names": [],
                }
                group_by_name[current_group] = row
                groups.append(row)

        group = group_by_name[current_group]
        label_prefix = metatile_label_prefix(name)
        candidates = metatile_label_header_symbol_candidates(label_prefix)
        source_tileset_symbol = group.get("source_tileset_symbol")
        if source_tileset_symbol:
            candidates = [
                {
                    "symbol": source_tileset_symbol,
                    "resolution": "source_group",
                }
            ] + [
                candidate
                for candidate in candidates
                if candidate["symbol"] != source_tileset_symbol
            ]

        label = {
            "name": name,
            "metatile_id": metatile_id,
            "value_text": value_text,
            "source": {
                "path": to_project_path(METATILE_LABEL_HEADER),
                "line": line_index,
            },
            "source_group": current_group,
            "source_group_line": current_group_line,
            "source_tileset_symbol": source_tileset_symbol,
            "label_prefix": label_prefix,
            "header_symbol_candidates": candidates,
        }
        labels.append(label)
        group["label_count"] += 1
        group["label_names"].append(name)

    labels_by_name = {
        label["name"]: {
            "metatile_id": label["metatile_id"],
            "source": label["source"],
            "source_group": label["source_group"],
            "source_tileset_symbol": label["source_tileset_symbol"],
            "label_prefix": label["label_prefix"],
            "header_symbol_candidates": label["header_symbol_candidates"],
        }
        for label in labels
    }

    return {
        "status": "decoded_import_metadata",
        "runtime_binary_metatile_labels_required": False,
        "source": path_status(source_root, METATILE_LABEL_HEADER),
        "label_count": len(labels),
        "source_group_count": sum(1 for group in groups if group["label_count"] > 0),
        "source_tileset_group_count": sum(
            1
            for group in groups
            if group["label_count"] > 0 and group.get("source_tileset_symbol")
        ),
        "non_tileset_group_count": sum(
            1
            for group in groups
            if group["label_count"] > 0 and not group.get("source_tileset_symbol")
        ),
        "groups": [
            group
            for group in groups
            if group["label_count"] > 0
        ],
        "labels": labels,
        "labels_by_name": labels_by_name,
        "compact_label_encoding": metatile_label_compact_record_encoding(),
        "compact_reverse_lookup_encoding": metatile_label_reverse_lookup_encoding(),
        "alias_policy": metatile_label_alias_policy(),
    }


def metatile_label_prefix(label_name):
    if not label_name.startswith("METATILE_"):
        return ""
    body = label_name[len("METATILE_"):]
    return body.split("_", 1)[0]


def metatile_label_header_symbol_candidates(label_prefix):
    if not label_prefix:
        return []
    candidates = [
        {
            "symbol": "gTileset_{}".format(label_prefix),
            "resolution": "label_prefix",
        }
    ]
    if label_prefix.endswith("Frlg"):
        candidates.append({
            "symbol": "gTileset_{}_Frlg".format(label_prefix[:-len("Frlg")]),
            "resolution": "frlg_suffix_alias",
        })
    if label_prefix.startswith("RS") and len(label_prefix) > 2:
        candidates.append({
            "symbol": "gTileset_{}".format(label_prefix[2:]),
            "resolution": "rs_prefix_alias",
        })
    return dedupe_symbol_candidates(candidates)


def dedupe_symbol_candidates(candidates):
    result = []
    seen = set()
    for candidate in candidates:
        symbol = candidate["symbol"]
        if symbol in seen:
            continue
        seen.add(symbol)
        result.append(candidate)
    return result


def metatile_label_alias_policy():
    return {
        "source_group": (
            "A // gTileset_* comment in include/constants/metatile_labels.h is treated "
            "as the primary source tileset binding for following labels."
        ),
        "label_prefix": (
            "For labels outside a tileset comment, the METATILE_<Prefix>_* prefix maps "
            "to gTileset_<Prefix> when that header exists."
        ),
        "frlg_suffix_alias": (
            "A label prefix ending in Frlg may map to a header ending in _Frlg, "
            "for example METATILE_GeneralFrlg_* -> gTileset_General_Frlg."
        ),
        "rs_prefix_alias": (
            "Legacy RS compatibility prefixes drop the leading RS when matching "
            "existing Emerald headers, for example RSCave -> gTileset_Cave."
        ),
        "other_group": (
            "The // Other group remains recorded as a non-tileset source group; "
            "only explicit prefix aliases attach its labels to headers or pairs."
        ),
    }


def metatile_label_compact_record_encoding():
    return {
        "version": "compact_metatile_label_v1",
        "detail": (
            "Each label row stores [name, metatile_id, local_metatile_id, source_line, "
            "resolution_code, in_range]. source_group and source_kind are carried by the "
            "containing header or pair row."
        ),
        "label_fields": [
            "name",
            "metatile_id",
            "local_metatile_id",
            "source_line",
            "resolution_code",
            "in_range",
        ],
        "resolution_codes": METATILE_LABEL_RESOLUTION_CODES,
    }


def metatile_label_reverse_lookup_encoding():
    return {
        "version": "compact_metatile_label_reverse_v1",
        "detail": (
            "Header reverse rows store [metatile_id, local_metatile_id, label_names, in_range]. "
            "Pair reverse rows store [metatile_id, source_kind_code, local_metatile_id, "
            "label_names, in_pair_range]."
        ),
        "header_reverse_fields": [
            "metatile_id",
            "local_metatile_id",
            "label_names",
            "in_range",
        ],
        "pair_reverse_fields": [
            "metatile_id",
            "source_kind_code",
            "local_metatile_id",
            "label_names",
            "in_pair_range",
        ],
        "source_kind_codes": TILE_SOURCE_KIND_CODES,
    }


def attribute_field(attribute_name, mask, shift, status, bits, detail=None):
    row = {
        "attribute": attribute_name,
        "status": status,
        "mask": None if mask is None else "0x{:08X}".format(mask),
        "shift": shift,
        "bits": bits,
    }
    if detail:
        row["detail"] = detail
    return row


def metatile_attribute_compact_record_encoding():
    return {
        "version": "compact_attribute_record_v1",
        "detail": (
            "Each attribute row stores [local_metatile_id, global_metatile_id, raw, behavior_id, "
            "layer_type, terrain_type, encounter_type, affordance_flags]. "
            "Behavior names and enum names are resolved through metatile_attribute_rules lookups."
        ),
        "attribute_record_fields": [
            "local_metatile_id",
            "global_metatile_id",
            "raw",
            "behavior_id",
            "layer_type",
            "terrain_type",
            "encounter_type",
            "affordance_flags",
        ],
        "affordance_flag_codes": METATILE_AFFORDANCE_FLAG_CODES,
        "derived_fields": {
            "behavior_name": "lookup behavior_id in metatile_attribute_rules.behavior_names_by_id",
            "layer_type_name": "lookup layer_type in metatile_attribute_rules.attribute_enums.layer_type_names",
            "terrain_type_name": "lookup terrain_type in metatile_attribute_rules.attribute_enums.tile_terrain_type_names when decoded",
            "encounter_type_name": "lookup encounter_type in metatile_attribute_rules.attribute_enums.tile_encounter_type_names when decoded",
            "has_encounters": "bool(affordance_flags & 1)",
            "surfable": "bool(affordance_flags & 2)",
            "land_encounter_affordance": "bool(affordance_flags & 4)",
            "water_encounter_affordance": "bool(affordance_flags & 8)",
            "unused_traversable_hint": "bool(affordance_flags & 16)",
        },
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


def metatile_attribute_decode_for_header(source_root, kind, branch, attribute_group, attribute_rules):
    profile_name = metatile_source_profile_for_branch(branch)
    profile = metatile_attribute_source_profile(profile_name)
    source_row = first_matching_status(
        attribute_group.get("editable_source_candidates", []) + attribute_group.get("incbin_paths", []),
        lambda path: path.endswith("/metatile_attributes.bin"),
    )

    base_row = {
        "runtime_binary_metatile_attributes_required": False,
        "source_rules_profile": profile_name,
        "source_kind": kind,
        "source_metatile_attributes_symbol": attribute_group.get("symbol"),
        "source_metatile_attributes_declaration_found": attribute_group.get("declaration_found", False),
        "source_metatile_attributes_declaration": attribute_group.get("declaration_source"),
        "source_profile": profile,
        "behavior_name_by_id_ref": "metatile_attribute_rules.behavior_names_by_id",
        "attribute_record_encoding_ref": "metatile_attribute_rules.compact_metatile_attribute_encoding",
        "attribute_record_encoding": metatile_attribute_compact_record_encoding(),
        "collision": {
            "status": "map_grid_block_field",
            "source_ref": "metatile_attribute_rules.map_grid_block_fields.collision",
            "detail": "Collision is decoded from layout map-grid blocks, not metatile_attributes.bin.",
        },
        "elevation": {
            "status": "map_grid_block_field",
            "source_ref": "metatile_attribute_rules.map_grid_block_fields.elevation",
            "detail": "Elevation is decoded from layout map-grid blocks, not metatile_attributes.bin.",
        },
        "terrain_type_status": profile["fields"]["terrain_type"]["status"],
        "encounter_type_status": profile["fields"]["encounter_type"]["status"],
    }

    if source_row is None:
        return dict(
            base_row,
            **{
                "status": "missing_source_binary",
                "source_binary": None,
                "metatile_attribute_count": 0,
                "record_byte_count": profile["record_byte_count"],
                "behavior_counts": {},
                "layer_type_counts": {},
                "terrain_type_counts": {},
                "encounter_type_counts": {},
                "encounter_affordance_count": 0,
                "surfable_affordance_count": 0,
                "land_encounter_affordance_count": 0,
                "water_encounter_affordance_count": 0,
                "unused_traversable_hint_count": 0,
                "missing_behavior_name_count": 0,
                "attributes": [],
            },
        )

    raw_values = read_little_endian_values(source_root / source_row["path"], profile["record_byte_count"])
    behavior_names_by_id = attribute_rules.get("behavior_names_by_id", {})
    behavior_affordances_by_name = attribute_rules.get("behavior_affordances_by_name", {})
    source_global_offset = 0 if kind == "primary" else profile["primary_metatile_count"]
    records = []
    behavior_counts = {}
    layer_counts = {}
    terrain_counts = {}
    encounter_type_counts = {}
    affordance_counts = {
        "encounter_affordance_count": 0,
        "surfable_affordance_count": 0,
        "land_encounter_affordance_count": 0,
        "water_encounter_affordance_count": 0,
        "unused_traversable_hint_count": 0,
    }
    missing_behavior_name_count = 0

    for local_metatile_id, raw_value in enumerate(raw_values):
        record = decode_metatile_attribute_record(
            raw_value,
            local_metatile_id,
            source_global_offset + local_metatile_id,
            profile_name,
            behavior_names_by_id,
            behavior_affordances_by_name,
        )
        behavior_counts[record["behavior_name"]] = behavior_counts.get(record["behavior_name"], 0) + 1
        layer_counts[record["layer_type_name"]] = layer_counts.get(record["layer_type_name"], 0) + 1
        if record["terrain_type_name"] is not None:
            terrain_counts[record["terrain_type_name"]] = terrain_counts.get(record["terrain_type_name"], 0) + 1
        if record["encounter_type_name"] is not None:
            encounter_type_counts[record["encounter_type_name"]] = encounter_type_counts.get(record["encounter_type_name"], 0) + 1
        for stat_key, record_key in [
            ("encounter_affordance_count", "has_encounters"),
            ("surfable_affordance_count", "surfable"),
            ("land_encounter_affordance_count", "land_encounter_affordance"),
            ("water_encounter_affordance_count", "water_encounter_affordance"),
            ("unused_traversable_hint_count", "unused_traversable_hint"),
        ]:
            if record[record_key]:
                affordance_counts[stat_key] += 1
        if record["behavior_name"].startswith("MB_UNKNOWN_"):
            missing_behavior_name_count += 1
        records.append(compact_metatile_attribute_record(record))

    return dict(
        base_row,
        **{
            "status": "decoded",
            "source_binary": source_row,
            "metatile_attribute_count": len(records),
            "record_byte_count": profile["record_byte_count"],
            "behavior_counts": dict(sorted(behavior_counts.items())),
            "layer_type_counts": dict(sorted(layer_counts.items())),
            "terrain_type_counts": dict(sorted(terrain_counts.items())),
            "encounter_type_counts": dict(sorted(encounter_type_counts.items())),
            "missing_behavior_name_count": missing_behavior_name_count,
            "attributes": records,
            **affordance_counts,
        },
    )


def read_little_endian_values(path, byte_count):
    data = path.read_bytes()
    if len(data) % byte_count != 0:
        raise ValueError("{} has {} bytes, not divisible by {}".format(path, len(data), byte_count))
    return [
        int.from_bytes(data[index:index + byte_count], "little")
        for index in range(0, len(data), byte_count)
    ]


def decode_metatile_attribute_record(
    raw,
    local_metatile_id,
    global_metatile_id,
    profile_name,
    behavior_names_by_id,
    behavior_affordances_by_name,
):
    profile = metatile_attribute_source_profile(profile_name)
    fields = profile["fields"]
    behavior_id = extract_attribute_field(raw, fields["behavior"])
    layer_type = extract_attribute_field(raw, fields["layer_type"])
    terrain_type = extract_attribute_field(raw, fields["terrain_type"])
    encounter_type = extract_attribute_field(raw, fields["encounter_type"])
    behavior_name = behavior_names_by_id.get(str(behavior_id), "MB_UNKNOWN_{:03d}".format(behavior_id))
    behavior_affordance = behavior_affordances_by_name.get(behavior_name, {})
    has_encounters = bool(behavior_affordance.get("has_encounters"))
    surfable = bool(behavior_affordance.get("surfable"))
    land_encounter = has_encounters and not surfable
    water_encounter = has_encounters and surfable
    unused_hint = bool(behavior_affordance.get("unused_traversable_hint"))
    return {
        "local_metatile_id": local_metatile_id,
        "global_metatile_id": global_metatile_id,
        "raw": raw,
        "behavior_id": behavior_id,
        "behavior_name": behavior_name,
        "layer_type": layer_type,
        "layer_type_name": METATILE_LAYER_TYPE_NAMES.get(
            layer_type,
            "METATILE_LAYER_TYPE_UNKNOWN_{}".format(layer_type),
        ),
        "terrain_type": terrain_type,
        "terrain_type_name": None if terrain_type is None else TILE_TERRAIN_TYPE_NAMES.get(
            terrain_type,
            "TILE_TERRAIN_UNKNOWN_{}".format(terrain_type),
        ),
        "encounter_type": encounter_type,
        "encounter_type_name": None if encounter_type is None else TILE_ENCOUNTER_TYPE_NAMES.get(
            encounter_type,
            "TILE_ENCOUNTER_UNKNOWN_{}".format(encounter_type),
        ),
        "has_encounters": has_encounters,
        "surfable": surfable,
        "land_encounter_affordance": land_encounter,
        "water_encounter_affordance": water_encounter,
        "unused_traversable_hint": unused_hint,
    }


def extract_attribute_field(raw, field):
    if field["status"] != "decoded":
        return None
    mask = int(field["mask"], 16)
    return (raw & mask) >> int(field["shift"])


def compact_metatile_attribute_record(record):
    flags = 0
    for name, code in METATILE_AFFORDANCE_FLAG_CODES.items():
        if record[name]:
            flags |= code
    return [
        record["local_metatile_id"],
        record["global_metatile_id"],
        record["raw"],
        record["behavior_id"],
        record["layer_type"],
        record["terrain_type"],
        record["encounter_type"],
        flags,
    ]


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


def build_tileset_animation_frame_strip_export(
    source_root,
    animation_frames,
    output_asset_root=None,
    write_assets=False,
):
    output_asset_root = Path(output_asset_root or "assets/generated")
    output_root = output_asset_root / TILESET_ANIMATION_ASSET_DIR
    strips = []
    missing_source_images = []
    invalid_source_images = []
    total_source_image_count = 0
    total_existing_source_image_count = 0
    total_written_count = 0
    total_width_pixels = 0
    total_height_pixels = 0

    for frame in animation_frames:
        source_images = []
        opened_images = []
        strip_width = 0
        strip_height = 0
        status = "exported"

        for candidate in frame.get("editable_source_candidates", []):
            total_source_image_count += 1
            source_path_text = candidate.get("path", "")
            source_path = source_root / source_path_text
            image_row = {
                "path": source_path_text,
                "exists": bool(candidate.get("exists")),
                "source_format": "indexed_png",
                "output_format": "rgba8",
                "source_rect": None,
                "strip_rect": None,
                "width": None,
                "height": None,
                "error": None,
            }
            if not image_row["exists"]:
                status = "missing_source_image"
                missing_source_images.append({
                    "frame_symbol": frame.get("symbol"),
                    "path": source_path_text,
                })
                source_images.append(image_row)
                continue

            try:
                with Image.open(source_path) as image:
                    rgba = image.convert("RGBA")
            except (OSError, ValueError) as error:
                status = "invalid_source_image"
                image_row["error"] = str(error)
                invalid_source_images.append({
                    "frame_symbol": frame.get("symbol"),
                    "path": source_path_text,
                    "error": str(error),
                })
                source_images.append(image_row)
                continue

            total_existing_source_image_count += 1
            width, height = rgba.size
            image_row["width"] = width
            image_row["height"] = height
            image_row["source_rect"] = {
                "x": 0,
                "y": 0,
                "w": width,
                "h": height,
            }
            image_row["strip_rect"] = {
                "x": strip_width,
                "y": 0,
                "w": width,
                "h": height,
            }
            strip_width += width
            strip_height = max(strip_height, height)
            opened_images.append((rgba, image_row["strip_rect"]))
            source_images.append(image_row)

        asset_name = "{}.png".format(slugify_asset_name(frame.get("symbol", "")))
        output_path = output_root / asset_name
        image_project_path = to_project_path(output_path)
        if status == "exported" and not opened_images:
            status = "missing_source_image"
        if status == "exported" and write_assets:
            output_path.parent.mkdir(parents=True, exist_ok=True)
            strip = Image.new("RGBA", (strip_width, strip_height), (0, 0, 0, 0))
            for image, rect in opened_images:
                strip.paste(image, (rect["x"], rect["y"]))
            strip.save(output_path)
            total_written_count += 1

        if status == "exported":
            total_width_pixels += strip_width
            total_height_pixels += strip_height

        strips.append({
            "frame_symbol": frame.get("symbol"),
            "status": status,
            "artifact_kind": "tileset_animation_rgba_frame_strip",
            "image": "res://{}".format(image_project_path),
            "image_project_path": image_project_path,
            "generated_path": image_project_path,
            "source": frame.get("source"),
            "source_bins": frame.get("source_bins", []),
            "source_bin_count": int(frame.get("source_bin_count", 0)),
            "tileset_base_paths": frame.get("tileset_base_paths", []),
            "source_image_count": len(source_images),
            "strip_source_image_count": len(opened_images),
            "pixel_format": "RGBA8",
            "conversion": "source_indexed_png_to_rgba_frame_strip",
            "strip_size": {
                "w": strip_width if status == "exported" else None,
                "h": strip_height if status == "exported" else None,
            },
            "source_images": source_images,
        })

    exported_strip_count = sum(1 for strip in strips if strip["status"] == "exported")
    return {
        "status": "exported_rgba_frame_strips",
        "artifact_kind": "tileset_animation_rgba_frame_strips",
        "runtime_tileset_animation_required": False,
        "source_color_runtime_required": False,
        "source_palette_runtime_required": False,
        "asset_root": to_project_path(output_root),
        "write_assets": bool(write_assets),
        "frame_declaration_count": len(animation_frames),
        "source_image_count": total_source_image_count,
        "existing_source_image_count": total_existing_source_image_count,
        "generated_strip_count": exported_strip_count,
        "written_strip_count": total_written_count,
        "missing_source_image_count": len(missing_source_images),
        "invalid_source_image_count": len(invalid_source_images),
        "total_strip_width_pixels": total_width_pixels,
        "total_strip_height_pixels": total_height_pixels,
        "strips": strips,
        "missing_source_images": missing_source_images,
        "invalid_source_images": invalid_source_images,
    }


def metatile_label_resolution_for_header(label, header_symbol):
    for candidate in label.get("header_symbol_candidates", []):
        if candidate.get("symbol") == header_symbol:
            return candidate.get("resolution", "label_prefix")
    return None


def metatile_label_records_for_header(label_rules, header_symbol):
    labels = label_rules.get("labels", [])
    return [
        (label, resolution)
        for label in labels
        for resolution in [metatile_label_resolution_for_header(label, header_symbol)]
        if resolution is not None
    ]


def local_metatile_id_for_kind(metatile_id, kind, profile):
    if kind == "primary":
        return metatile_id
    return metatile_id - profile["primary_metatile_count"]


def compact_metatile_label_record(label, local_metatile_id, resolution, in_range):
    return [
        label["name"],
        label["metatile_id"],
        local_metatile_id,
        label["source"]["line"],
        METATILE_LABEL_RESOLUTION_CODES[resolution],
        1 if in_range else 0,
    ]


def compact_pair_metatile_label_record(label, source_kind, local_metatile_id, resolution, in_range):
    return [
        label["name"],
        label["metatile_id"],
        TILE_SOURCE_KIND_CODES[source_kind],
        local_metatile_id,
        label["source"]["line"],
        METATILE_LABEL_RESOLUTION_CODES[resolution],
        1 if in_range else 0,
    ]


def metatile_label_pair_record_encoding():
    return {
        "version": "compact_metatile_pair_label_v1",
        "detail": (
            "Each pair label row stores [name, metatile_id, source_kind_code, local_metatile_id, "
            "source_line, resolution_code, in_pair_range]."
        ),
        "label_fields": [
            "name",
            "metatile_id",
            "source_kind_code",
            "local_metatile_id",
            "source_line",
            "resolution_code",
            "in_pair_range",
        ],
        "source_kind_codes": TILE_SOURCE_KIND_CODES,
        "resolution_codes": METATILE_LABEL_RESOLUTION_CODES,
    }


def metatile_label_lookup_for_header(kind, branch, symbol, metatile_binary_decode, label_rules):
    profile_name = metatile_source_profile_for_branch(branch)
    profile = metatile_source_profile(profile_name)
    metatile_count = int(metatile_binary_decode.get("metatile_count", 0))
    source_labels = metatile_label_records_for_header(label_rules, symbol)
    compact_labels = []
    reverse_by_id = {}
    resolution_counts = {}
    source_groups = sorted({
        label["source_group"]
        for label, _ in source_labels
    })

    for label, resolution in sorted(source_labels, key=lambda item: (item[0]["metatile_id"], item[0]["name"])):
        local_metatile_id = local_metatile_id_for_kind(label["metatile_id"], kind, profile)
        in_range = 0 <= local_metatile_id < metatile_count
        compact_labels.append(compact_metatile_label_record(
            label,
            local_metatile_id,
            resolution,
            in_range,
        ))
        reverse_by_id.setdefault(label["metatile_id"], []).append(label["name"])
        resolution_counts[resolution] = resolution_counts.get(resolution, 0) + 1

    reverse_lookup = []
    for metatile_id in sorted(reverse_by_id):
        local_metatile_id = local_metatile_id_for_kind(metatile_id, kind, profile)
        in_range = 0 <= local_metatile_id < metatile_count
        reverse_lookup.append([
            metatile_id,
            local_metatile_id,
            sorted(reverse_by_id[metatile_id]),
            1 if in_range else 0,
        ])

    out_of_range = [
        row
        for row in compact_labels
        if not row[5]
    ]
    return {
        "status": "decoded" if compact_labels else "no_source_labels",
        "runtime_binary_metatile_labels_required": False,
        "source": to_project_path(METATILE_LABEL_HEADER),
        "source_rules_profile": profile_name,
        "source_kind": kind,
        "source_tileset_symbol": symbol,
        "source_groups": source_groups,
        "label_count": len(compact_labels),
        "reverse_lookup_metatile_id_count": len(reverse_lookup),
        "out_of_range_label_count": len(out_of_range),
        "out_of_range_labels": out_of_range,
        "resolution_counts": dict(sorted(resolution_counts.items())),
        "label_record_encoding_ref": "metatile_label_rules.compact_label_encoding",
        "reverse_lookup_encoding_ref": "metatile_label_rules.compact_reverse_lookup_encoding",
        "labels": compact_labels,
        "reverse_lookup": reverse_lookup,
    }


def source_layout_tileset_pairs(source_root):
    path = source_root / LAYOUTS_JSON
    if not path.exists():
        return {
            "source": path_status(source_root, LAYOUTS_JSON),
            "layout_count": 0,
            "pairs": [],
        }

    data = json.loads(read_text(path))
    pairs = {}
    for layout in data.get("layouts", []):
        primary = layout.get("primary_tileset")
        secondary = layout.get("secondary_tileset")
        if not primary or not secondary:
            continue
        key = "{}+{}".format(primary, secondary)
        row = pairs.setdefault(key, {
            "pair_key": key,
            "primary_tileset": primary,
            "secondary_tileset": secondary,
            "layout_count": 0,
            "layout_ids": [],
            "layout_versions": {},
        })
        row["layout_count"] += 1
        row["layout_ids"].append(layout.get("id"))
        version = str(layout.get("layout_version"))
        row["layout_versions"][version] = row["layout_versions"].get(version, 0) + 1

    return {
        "source": path_status(source_root, LAYOUTS_JSON),
        "layout_count": len(data.get("layouts", [])),
        "pairs": [
            pairs[key]
            for key in sorted(pairs)
        ],
    }


def source_map_refs_by_layout(source_root):
    groups_path = Path("data/maps/map_groups.json")
    if not (source_root / groups_path).exists():
        return {
            "status": "missing_source_file",
            "source": path_status(source_root, groups_path),
            "map_count": 0,
            "layout_with_map_count": 0,
            "maps": [],
            "maps_by_layout": {},
        }

    index = load_map_group_index(source_root)
    maps_root = source_root / "data/maps"
    map_paths = sorted(maps_root.glob("*/map.json"), key=lambda path: path.parent.name)
    maps = []
    maps_by_layout = {}
    for map_path in map_paths:
        map_folder = map_path.parent.name
        metadata = index.get("by_folder", {}).get(map_folder, {})
        map_data = json.loads(read_text(map_path))
        layout_id = map_data.get("layout")
        row = {
            "map_id": map_data.get("id"),
            "map_name": map_data.get("name"),
            "map_folder": map_folder,
            "layout_id": layout_id,
            "region_map_section": map_data.get("region_map_section"),
            "map_group_symbol": metadata.get("map_group_symbol"),
            "map_group_index": metadata.get("map_group_index"),
            "map_num": metadata.get("map_num"),
            "map_constant_value": metadata.get("map_constant_value"),
            "source_grouped": map_folder in index.get("by_folder", {}),
        }
        maps.append(row)
        if layout_id:
            maps_by_layout.setdefault(layout_id, []).append(row)

    sort_key = lambda row: (
        row.get("map_group_index") if row.get("map_group_index") is not None else 9999,
        row.get("map_num") if row.get("map_num") is not None else 9999,
        row.get("map_folder") or "",
        row.get("map_id") or "",
    )
    for layout_id in maps_by_layout:
        maps_by_layout[layout_id] = sorted(maps_by_layout[layout_id], key=sort_key)
    return {
        "status": "decoded_import_metadata",
        "source": path_status(source_root, groups_path),
        "map_count": len(maps),
        "grouped_map_count": sum(1 for row in maps if row.get("source_grouped")),
        "ungrouped_map_count": sum(1 for row in maps if not row.get("source_grouped")),
        "ungrouped_map_folders": sorted(
            row["map_folder"]
            for row in maps
            if not row.get("source_grouped")
        ),
        "layout_with_map_count": len(maps_by_layout),
        "maps": sorted(maps, key=sort_key),
        "maps_by_layout": maps_by_layout,
    }


def tileset_callback_descriptor(header):
    if not header:
        return {
            "header_found": False,
            "kind": "missing",
            "active_in_emerald": False,
            "callback_symbol": None,
            "has_callback": False,
            "callback_status": "missing_header",
            "callback_source": None,
            "callback_source_found": False,
        }
    callback = header.get("callback", {})
    return {
        "header_found": True,
        "kind": header.get("kind"),
        "active_in_emerald": header.get("active_in_emerald"),
        "callback_symbol": callback.get("symbol") if callback.get("has_callback") else None,
        "has_callback": bool(callback.get("has_callback")),
        "callback_status": callback.get("status"),
        "callback_source": callback.get("source"),
        "callback_source_found": bool(callback.get("source_found")),
    }


def role_usage_template():
    return {
        "primary": 0,
        "secondary": 0,
    }


def sorted_set(values):
    return sorted(value for value in values if value is not None)


def build_tileset_callback_map_report(source_root, records):
    layouts = source_layout_rows(source_root)
    map_refs = source_map_refs_by_layout(source_root)
    maps_by_layout = map_refs.get("maps_by_layout", {})
    rows_by_symbol = {
        row["symbol"]: row
        for row in records
    }
    tilesets = {}
    callbacks = {}
    pairs = {}
    layout_rows = []
    role_count = 0
    primary_role_count = 0
    secondary_role_count = 0

    def ensure_tileset_row(symbol, header):
        descriptor = tileset_callback_descriptor(header)
        row = tilesets.setdefault(symbol, {
            "tileset": symbol,
            "header_found": descriptor["header_found"],
            "kind": descriptor["kind"],
            "active_in_emerald": descriptor["active_in_emerald"],
            "callback_symbol": descriptor["callback_symbol"],
            "has_callback": descriptor["has_callback"],
            "callback_status": descriptor["callback_status"],
            "callback_source": descriptor["callback_source"],
            "callback_source_found": descriptor["callback_source_found"],
            "role_usage_counts": role_usage_template(),
            "layout_ids": set(),
            "map_ids": set(),
            "layout_pair_keys": set(),
            "standalone_layout_ids": set(),
        })
        return row

    def ensure_callback_row(symbol, callback_source, callback_source_found):
        return callbacks.setdefault(symbol, {
            "callback_symbol": symbol,
            "source": callback_source,
            "source_found": callback_source_found,
            "role_usage_counts": role_usage_template(),
            "tilesets": {},
            "layout_ids": set(),
            "map_ids": set(),
            "layout_pair_keys": set(),
            "standalone_layout_ids": set(),
        })

    for layout in layouts:
        layout_id = layout.get("id")
        primary_symbol = layout.get("primary_tileset")
        secondary_symbol = layout.get("secondary_tileset")
        if not layout_id or not primary_symbol or not secondary_symbol:
            continue
        pair_key = "{}+{}".format(primary_symbol, secondary_symbol)
        layout_maps = maps_by_layout.get(layout_id, [])
        map_ids = sorted_set(row.get("map_id") for row in layout_maps)
        primary_header = rows_by_symbol.get(primary_symbol)
        secondary_header = rows_by_symbol.get(secondary_symbol)
        primary_descriptor = tileset_callback_descriptor(primary_header)
        secondary_descriptor = tileset_callback_descriptor(secondary_header)
        layout_rows.append({
            "layout_id": layout_id,
            "layout_name": layout.get("name"),
            "layout_version": layout.get("layout_version"),
            "primary_tileset": primary_symbol,
            "secondary_tileset": secondary_symbol,
            "primary_callback_symbol": primary_descriptor["callback_symbol"],
            "secondary_callback_symbol": secondary_descriptor["callback_symbol"],
            "primary_has_callback": primary_descriptor["has_callback"],
            "secondary_has_callback": secondary_descriptor["has_callback"],
            "map_count": len(map_ids),
            "map_ids": map_ids,
        })

        pair = pairs.setdefault(pair_key, {
            "pair_key": pair_key,
            "primary_tileset": primary_symbol,
            "secondary_tileset": secondary_symbol,
            "primary_callback_symbol": primary_descriptor["callback_symbol"],
            "secondary_callback_symbol": secondary_descriptor["callback_symbol"],
            "primary_has_callback": primary_descriptor["has_callback"],
            "secondary_has_callback": secondary_descriptor["has_callback"],
            "primary_header_found": primary_descriptor["header_found"],
            "secondary_header_found": secondary_descriptor["header_found"],
            "layout_ids": set(),
            "layout_versions": {},
            "map_ids": set(),
            "standalone_layout_ids": set(),
        })
        pair["layout_ids"].add(layout_id)
        if map_ids:
            pair["map_ids"].update(map_ids)
        else:
            pair["standalone_layout_ids"].add(layout_id)
        version = str(layout.get("layout_version"))
        pair["layout_versions"][version] = pair["layout_versions"].get(version, 0) + 1

        for role, symbol, header in [
            ("primary", primary_symbol, primary_header),
            ("secondary", secondary_symbol, secondary_header),
        ]:
            role_count += 1
            if role == "primary":
                primary_role_count += 1
            else:
                secondary_role_count += 1
            tileset_row = ensure_tileset_row(symbol, header)
            tileset_row["role_usage_counts"][role] += 1
            tileset_row["layout_ids"].add(layout_id)
            tileset_row["layout_pair_keys"].add(pair_key)
            if map_ids:
                tileset_row["map_ids"].update(map_ids)
            else:
                tileset_row["standalone_layout_ids"].add(layout_id)

            descriptor = tileset_callback_descriptor(header)
            if not descriptor["has_callback"]:
                continue
            callback_row = ensure_callback_row(
                descriptor["callback_symbol"],
                descriptor["callback_source"],
                descriptor["callback_source_found"],
            )
            callback_row["role_usage_counts"][role] += 1
            callback_row["layout_ids"].add(layout_id)
            callback_row["layout_pair_keys"].add(pair_key)
            if map_ids:
                callback_row["map_ids"].update(map_ids)
            else:
                callback_row["standalone_layout_ids"].add(layout_id)
            callback_tileset = callback_row["tilesets"].setdefault(symbol, {
                "tileset": symbol,
                "kind": descriptor["kind"],
                "active_in_emerald": descriptor["active_in_emerald"],
                "role_usage_counts": role_usage_template(),
                "layout_ids": set(),
                "map_ids": set(),
            })
            callback_tileset["role_usage_counts"][role] += 1
            callback_tileset["layout_ids"].add(layout_id)
            callback_tileset["map_ids"].update(map_ids)

    tileset_rows = []
    for symbol in sorted(tilesets):
        row = tilesets[symbol]
        layout_ids = sorted_set(row["layout_ids"])
        map_ids = sorted_set(row["map_ids"])
        standalone_layout_ids = sorted_set(row["standalone_layout_ids"])
        tileset_rows.append({
            "tileset": row["tileset"],
            "header_found": row["header_found"],
            "kind": row["kind"],
            "active_in_emerald": row["active_in_emerald"],
            "callback_symbol": row["callback_symbol"],
            "has_callback": row["has_callback"],
            "callback_status": row["callback_status"],
            "callback_source": row["callback_source"],
            "callback_source_found": row["callback_source_found"],
            "role_usage_counts": dict(row["role_usage_counts"]),
            "layout_count": len(layout_ids),
            "map_count": len(map_ids),
            "standalone_layout_count": len(standalone_layout_ids),
            "layout_ids": layout_ids,
            "map_ids": map_ids,
            "standalone_layout_ids": standalone_layout_ids,
            "layout_pair_keys": sorted_set(row["layout_pair_keys"]),
        })

    callback_rows = []
    for symbol in sorted(callbacks):
        row = callbacks[symbol]
        layout_ids = sorted_set(row["layout_ids"])
        map_ids = sorted_set(row["map_ids"])
        standalone_layout_ids = sorted_set(row["standalone_layout_ids"])
        callback_tilesets = []
        for tileset_symbol in sorted(row["tilesets"]):
            tileset_row = row["tilesets"][tileset_symbol]
            tileset_layout_ids = sorted_set(tileset_row["layout_ids"])
            tileset_map_ids = sorted_set(tileset_row["map_ids"])
            callback_tilesets.append({
                "tileset": tileset_symbol,
                "kind": tileset_row["kind"],
                "active_in_emerald": tileset_row["active_in_emerald"],
                "role_usage_counts": dict(tileset_row["role_usage_counts"]),
                "layout_count": len(tileset_layout_ids),
                "map_count": len(tileset_map_ids),
                "layout_ids": tileset_layout_ids,
                "map_ids": tileset_map_ids,
            })
        callback_rows.append({
            "callback_symbol": symbol,
            "source": row["source"],
            "source_found": row["source_found"],
            "role_usage_counts": dict(row["role_usage_counts"]),
            "tileset_count": len(callback_tilesets),
            "tilesets": callback_tilesets,
            "layout_count": len(layout_ids),
            "map_count": len(map_ids),
            "standalone_layout_count": len(standalone_layout_ids),
            "layout_ids": layout_ids,
            "map_ids": map_ids,
            "standalone_layout_ids": standalone_layout_ids,
            "layout_pair_keys": sorted_set(row["layout_pair_keys"]),
        })

    pair_rows = []
    for pair_key in sorted(pairs):
        row = pairs[pair_key]
        layout_ids = sorted_set(row["layout_ids"])
        map_ids = sorted_set(row["map_ids"])
        standalone_layout_ids = sorted_set(row["standalone_layout_ids"])
        pair_rows.append({
            "pair_key": row["pair_key"],
            "primary_tileset": row["primary_tileset"],
            "secondary_tileset": row["secondary_tileset"],
            "primary_callback_symbol": row["primary_callback_symbol"],
            "secondary_callback_symbol": row["secondary_callback_symbol"],
            "primary_has_callback": row["primary_has_callback"],
            "secondary_has_callback": row["secondary_has_callback"],
            "primary_header_found": row["primary_header_found"],
            "secondary_header_found": row["secondary_header_found"],
            "layout_count": len(layout_ids),
            "map_count": len(map_ids),
            "standalone_layout_count": len(standalone_layout_ids),
            "layout_ids": layout_ids,
            "map_ids": map_ids,
            "standalone_layout_ids": standalone_layout_ids,
            "layout_versions": dict(sorted(row["layout_versions"].items())),
        })

    layout_with_map_count = len({
        row["layout_id"]
        for row in layout_rows
        if row.get("map_count", 0) > 0
    })
    missing_header_tilesets = [
        row["tileset"]
        for row in tileset_rows
        if not row["header_found"]
    ]
    return {
        "status": "decoded_import_metadata" if layouts else "no_source_layouts",
        "runtime_tileset_animation_required": False,
        "source": {
            "headers": path_status(source_root, Path("src/data/tilesets/headers.h")),
            "layouts": path_status(source_root, LAYOUTS_JSON),
            "maps": map_refs.get("source"),
            "tileset_animation_callbacks": path_status(source_root, Path("src/tileset_anims.c")),
        },
        "source_trace": [
            {
                "path": "src/data/tilesets/headers.h",
                "symbols": ["struct Tileset.callback", "struct Tileset.isSecondary"],
            },
            {
                "path": "data/layouts/layouts.json",
                "fields": ["primary_tileset", "secondary_tileset"],
            },
            {
                "path": "data/maps/map_groups.json",
                "fields": ["map group order", "map folder order"],
            },
            {
                "path": "data/maps/*/map.json",
                "fields": ["id", "name", "layout", "region_map_section"],
            },
        ],
        "layout_count": len(layout_rows),
        "map_count": map_refs.get("map_count", 0),
        "grouped_map_count": map_refs.get("grouped_map_count", 0),
        "ungrouped_map_count": map_refs.get("ungrouped_map_count", 0),
        "ungrouped_map_folders": map_refs.get("ungrouped_map_folders", []),
        "layout_with_map_count": layout_with_map_count,
        "standalone_layout_count": len(layout_rows) - layout_with_map_count,
        "pair_count": len(pair_rows),
        "layout_role_count": role_count,
        "primary_layout_role_count": primary_role_count,
        "secondary_layout_role_count": secondary_role_count,
        "tileset_usage_count": len(tileset_rows),
        "primary_tileset_usage_count": len({
            row["primary_tileset"]
            for row in layout_rows
        }),
        "secondary_tileset_usage_count": len({
            row["secondary_tileset"]
            for row in layout_rows
        }),
        "tileset_with_callback_count": sum(1 for row in tileset_rows if row["has_callback"]),
        "null_callback_tileset_count": sum(
            1
            for row in tileset_rows
            if row["header_found"] and not row["has_callback"]
        ),
        "missing_header_tileset_count": len(missing_header_tilesets),
        "missing_header_tilesets": missing_header_tilesets,
        "callback_symbol_count": len(callback_rows),
        "callback_with_map_count": sum(1 for row in callback_rows if row["map_count"] > 0),
        "maps": map_refs.get("maps", []),
        "layouts": sorted(layout_rows, key=lambda row: row["layout_id"]),
        "layout_pairs": pair_rows,
        "tilesets": tileset_rows,
        "callbacks": callback_rows,
    }


def build_metatile_label_pair_lookup(source_root, records, label_rules):
    source_pairs = source_layout_tileset_pairs(source_root)
    rows_by_symbol = {
        row["symbol"]: row
        for row in records
    }
    pair_rows = []

    for source_pair in source_pairs["pairs"]:
        primary_symbol = source_pair["primary_tileset"]
        secondary_symbol = source_pair["secondary_tileset"]
        primary_header = rows_by_symbol.get(primary_symbol)
        secondary_header = rows_by_symbol.get(secondary_symbol)
        profile_name = (
            metatile_source_profile_for_branch(primary_header.get("branch"))
            if primary_header
            else "emerald"
        )
        profile = metatile_source_profile(profile_name)
        labels = []
        reverse_by_key = {}
        out_of_range = []

        for source_kind, symbol, header in [
            ("primary", primary_symbol, primary_header),
            ("secondary", secondary_symbol, secondary_header),
        ]:
            if not header:
                continue
            metatile_count = int(
                header.get("metatile_binary_decode", {}).get("metatile_count", 0)
            )
            for label, resolution in metatile_label_records_for_header(label_rules, symbol):
                local_metatile_id = local_metatile_id_for_kind(
                    label["metatile_id"],
                    source_kind,
                    profile,
                )
                in_range = 0 <= local_metatile_id < metatile_count
                row = compact_pair_metatile_label_record(
                    label,
                    source_kind,
                    local_metatile_id,
                    resolution,
                    in_range,
                )
                labels.append(row)
                if not in_range:
                    out_of_range.append(row)
                reverse_key = (
                    label["metatile_id"],
                    TILE_SOURCE_KIND_CODES[source_kind],
                    local_metatile_id,
                    1 if in_range else 0,
                )
                reverse_by_key.setdefault(reverse_key, []).append(label["name"])

        labels.sort(key=lambda row: (row[1], row[2], row[0]))
        reverse_lookup = [
            [
                metatile_id,
                source_kind_code,
                local_metatile_id,
                sorted(label_names),
                in_range,
            ]
            for (metatile_id, source_kind_code, local_metatile_id, in_range), label_names
            in sorted(reverse_by_key.items())
        ]

        primary_label_count = sum(1 for row in labels if row[2] == TILE_SOURCE_KIND_CODES["primary"])
        secondary_label_count = sum(1 for row in labels if row[2] == TILE_SOURCE_KIND_CODES["secondary"])
        pair_rows.append({
            "status": "decoded" if labels else "no_source_labels",
            "pair_key": source_pair["pair_key"],
            "primary_tileset": primary_symbol,
            "secondary_tileset": secondary_symbol,
            "source_rules_profile": profile_name,
            "primary_header_found": primary_header is not None,
            "secondary_header_found": secondary_header is not None,
            "layout_count": source_pair["layout_count"],
            "layout_ids": source_pair["layout_ids"],
            "layout_versions": dict(sorted(source_pair["layout_versions"].items())),
            "primary_label_count": primary_label_count,
            "secondary_label_count": secondary_label_count,
            "label_count": len(labels),
            "reverse_lookup_metatile_id_count": len(reverse_lookup),
            "out_of_pair_label_count": len(out_of_range),
            "out_of_pair_labels": out_of_range,
            "label_record_encoding_ref": "metatile_label_pair_lookup.compact_pair_label_encoding",
            "reverse_lookup_encoding_ref": "metatile_label_pair_lookup.compact_reverse_lookup_encoding",
            "labels": labels,
            "reverse_lookup": reverse_lookup,
        })

    return {
        "status": "decoded_import_metadata" if source_pairs["source"].get("exists") else "missing_source_file",
        "runtime_binary_metatile_labels_required": False,
        "source": source_pairs["source"],
        "source_layout_count": source_pairs["layout_count"],
        "pair_count": len(pair_rows),
        "compact_pair_label_encoding": metatile_label_pair_record_encoding(),
        "compact_reverse_lookup_encoding": metatile_label_reverse_lookup_encoding(),
        "pairs": pair_rows,
    }


def metatile_map_absent_record_encoding():
    return {
        "version": "compact_metatile_map_absent_v1",
        "detail": (
            "Each absent metatile row stores [metatile_id, source_kind_code, "
            "local_metatile_id, count, reason, samples]. Each sample stores "
            "[source_entry_index, x, y, raw_map_grid_value, metatile_id]."
        ),
        "absent_metatile_fields": [
            "metatile_id",
            "source_kind_code",
            "local_metatile_id",
            "count",
            "reason",
            "samples",
        ],
        "sample_fields": [
            "source_entry_index",
            "x",
            "y",
            "raw_map_grid_value",
            "metatile_id",
        ],
        "source_kind_codes": TILE_SOURCE_KIND_CODES,
        "reason_codes": [
            "primary_header_missing",
            "primary_metatile_absent",
            "secondary_header_missing",
            "secondary_metatile_absent",
        ],
    }


def metatile_count_for_header(header):
    if not header:
        return 0
    return int(header.get("metatile_binary_decode", {}).get("metatile_count", 0))


def metatile_pair_ranges(profile, primary_header, secondary_header):
    primary_count = metatile_count_for_header(primary_header)
    secondary_count = metatile_count_for_header(secondary_header)
    secondary_start = profile["primary_metatile_count"]
    return {
        "primary_global_start": 0,
        "primary_global_end": primary_count - 1 if primary_count else None,
        "primary_profile_capacity": profile["primary_metatile_count"],
        "primary_metatile_count": primary_count,
        "secondary_global_start": secondary_start,
        "secondary_global_end": secondary_start + secondary_count - 1 if secondary_count else None,
        "secondary_profile_capacity": profile["total_metatile_count"] - secondary_start,
        "secondary_metatile_count": secondary_count,
    }


def classify_metatile_reference(metatile_id, profile, primary_header, secondary_header):
    if metatile_id < profile["primary_metatile_count"]:
        source_kind = "primary"
        local_metatile_id = metatile_id
        header = primary_header
    else:
        source_kind = "secondary"
        local_metatile_id = metatile_id - profile["primary_metatile_count"]
        header = secondary_header

    if header is None:
        return {
            "status": "absent",
            "source_kind": source_kind,
            "source_kind_code": TILE_SOURCE_KIND_CODES[source_kind],
            "local_metatile_id": local_metatile_id,
            "reason": "{}_header_missing".format(source_kind),
        }

    metatile_count = metatile_count_for_header(header)
    if local_metatile_id >= metatile_count:
        return {
            "status": "absent",
            "source_kind": source_kind,
            "source_kind_code": TILE_SOURCE_KIND_CODES[source_kind],
            "local_metatile_id": local_metatile_id,
            "reason": "{}_metatile_absent".format(source_kind),
        }

    return {
        "status": "present",
        "source_kind": source_kind,
        "source_kind_code": TILE_SOURCE_KIND_CODES[source_kind],
        "local_metatile_id": local_metatile_id,
        "reason": None,
    }


def bump_counter(counter, key, count=1):
    counter[key] = counter.get(key, 0) + count


def add_absent_metatile(absent_by_key, metatile_id, classification, sample):
    key = (
        metatile_id,
        classification["source_kind_code"],
        classification["local_metatile_id"],
        classification["reason"],
    )
    row = absent_by_key.setdefault(key, {
        "metatile_id": metatile_id,
        "source_kind_code": classification["source_kind_code"],
        "local_metatile_id": classification["local_metatile_id"],
        "count": 0,
        "reason": classification["reason"],
        "samples": [],
    })
    row["count"] += 1
    if len(row["samples"]) < 5:
        row["samples"].append(sample)


def compact_absent_metatile_rows(absent_by_key):
    return [
        [
            row["metatile_id"],
            row["source_kind_code"],
            row["local_metatile_id"],
            row["count"],
            row["reason"],
            row["samples"],
        ]
        for row in sorted(
            absent_by_key.values(),
            key=lambda item: (
                item["reason"],
                item["source_kind_code"],
                item["metatile_id"],
                item["local_metatile_id"],
            ),
        )
    ]


def source_layout_rows(source_root):
    path = source_root / LAYOUTS_JSON
    if not path.exists():
        return []
    return json.loads(read_text(path)).get("layouts", [])


def build_metatile_map_reference_report(source_root, records):
    source_root = Path(source_root)
    source_status = path_status(source_root, LAYOUTS_JSON)
    if not source_status.get("exists"):
        return {
            "status": "missing_source_file",
            "source": source_status,
            "source_layout_count": 0,
            "checked_layout_count": 0,
            "pair_count": 0,
            "checked_cell_count": 0,
            "declared_cell_count": 0,
            "unique_metatile_id_count": 0,
            "absent_metatile_cell_count": 0,
            "absent_unique_reference_count": 0,
            "absent_global_metatile_id_count": 0,
            "layout_with_absent_metatile_count": 0,
            "pair_with_absent_metatile_count": 0,
            "missing_blockdata_layout_count": 0,
            "invalid_blockdata_layout_count": 0,
            "size_mismatch_layout_count": 0,
            "absent_reason_counts": {},
            "compact_absent_metatile_encoding": metatile_map_absent_record_encoding(),
            "layouts": [],
            "pairs": [],
        }

    rows_by_symbol = {
        row["symbol"]: row
        for row in records
    }
    layouts = source_layout_rows(source_root)
    layout_rows = []
    pair_rows = {}
    checked_layout_count = 0
    checked_cell_count = 0
    declared_cell_count = 0
    missing_blockdata_layout_count = 0
    invalid_blockdata_layout_count = 0
    size_mismatch_layout_count = 0
    absent_reason_counts = {}
    unique_metatile_ids = set()
    absent_global_metatile_ids = set()
    absent_unique_references = set()

    for layout in layouts:
        primary_symbol = layout.get("primary_tileset")
        secondary_symbol = layout.get("secondary_tileset")
        pair_key = "{}+{}".format(primary_symbol, secondary_symbol)
        primary_header = rows_by_symbol.get(primary_symbol)
        secondary_header = rows_by_symbol.get(secondary_symbol)
        profile_name = (
            metatile_source_profile_for_branch(primary_header.get("branch"))
            if primary_header
            else "emerald"
        )
        profile = metatile_source_profile(profile_name)
        ranges = metatile_pair_ranges(profile, primary_header, secondary_header)
        width = int(layout.get("width", 0) or 0)
        height = int(layout.get("height", 0) or 0)
        declared_count = width * height
        blockdata_path_text = layout.get("blockdata_filepath")
        blockdata_path = source_root / blockdata_path_text if blockdata_path_text else None

        pair_row = pair_rows.setdefault(pair_key, {
            "pair_key": pair_key,
            "primary_tileset": primary_symbol,
            "secondary_tileset": secondary_symbol,
            "source_rules_profile": profile_name,
            "primary_header_found": primary_header is not None,
            "secondary_header_found": secondary_header is not None,
            "primary_metatile_count": ranges["primary_metatile_count"],
            "secondary_metatile_count": ranges["secondary_metatile_count"],
            "primary_profile_capacity": ranges["primary_profile_capacity"],
            "secondary_profile_capacity": ranges["secondary_profile_capacity"],
            "layout_count": 0,
            "checked_layout_count": 0,
            "checked_cell_count": 0,
            "declared_cell_count": 0,
            "layout_ids": [],
            "affected_layout_ids": [],
            "layout_versions": {},
            "unique_metatile_ids": set(),
            "absent_by_key": {},
            "absent_reason_counts": {},
            "absent_cell_count": 0,
        })
        pair_row["layout_count"] += 1
        pair_row["layout_ids"].append(layout.get("id"))
        pair_row["declared_cell_count"] += declared_count
        version = str(layout.get("layout_version"))
        bump_counter(pair_row["layout_versions"], version)

        layout_status = "checked"
        values = []
        errors = []
        if not blockdata_path or not blockdata_path.exists():
            layout_status = "missing_blockdata"
            missing_blockdata_layout_count += 1
            errors.append("missing_blockdata")
        else:
            try:
                values = read_u16le_file(blockdata_path)
            except ValueError as error:
                layout_status = "invalid_blockdata"
                invalid_blockdata_layout_count += 1
                errors.append(str(error))

        source_entry_count = len(values)
        declared_cell_count += declared_count
        if layout_status == "checked":
            checked_layout_count += 1
            checked_cell_count += source_entry_count
            pair_row["checked_layout_count"] += 1
            pair_row["checked_cell_count"] += source_entry_count
            if source_entry_count != declared_count:
                size_mismatch_layout_count += 1
                errors.append("source_entry_count_mismatch")

        if source_entry_count != declared_count:
            layout_status = (
                "checked_size_mismatch"
                if layout_status == "checked"
                else layout_status
            )

        layout_absent = {}
        layout_reason_counts = {}
        layout_unique_ids = set()
        for index, raw_value in enumerate(values):
            metatile_id = raw_value & MAPGRID_METATILE_ID_MASK
            unique_metatile_ids.add(metatile_id)
            layout_unique_ids.add(metatile_id)
            pair_row["unique_metatile_ids"].add(metatile_id)
            classification = classify_metatile_reference(
                metatile_id,
                profile,
                primary_header,
                secondary_header,
            )
            if classification["status"] != "absent":
                continue
            sample = [
                index,
                index % width if width else None,
                index // width if width else None,
                raw_value,
                metatile_id,
            ]
            add_absent_metatile(layout_absent, metatile_id, classification, sample)
            add_absent_metatile(pair_row["absent_by_key"], metatile_id, classification, sample)
            bump_counter(layout_reason_counts, classification["reason"])
            bump_counter(pair_row["absent_reason_counts"], classification["reason"])
            bump_counter(absent_reason_counts, classification["reason"])
            pair_row["absent_cell_count"] += 1
            absent_global_metatile_ids.add(metatile_id)
            absent_unique_references.add((pair_key, metatile_id, classification["reason"]))

        absent_rows = compact_absent_metatile_rows(layout_absent)
        if absent_rows:
            pair_row["affected_layout_ids"].append(layout.get("id"))

        layout_rows.append({
            "status": layout_status,
            "layout_id": layout.get("id"),
            "name": layout.get("name"),
            "source": {
                "path": blockdata_path_text,
                "exists": bool(blockdata_path and blockdata_path.exists()),
            },
            "width": width,
            "height": height,
            "layout_version": layout.get("layout_version"),
            "primary_tileset": primary_symbol,
            "secondary_tileset": secondary_symbol,
            "pair_key": pair_key,
            "source_rules_profile": profile_name,
            "primary_header_found": primary_header is not None,
            "secondary_header_found": secondary_header is not None,
            "primary_metatile_count": ranges["primary_metatile_count"],
            "secondary_metatile_count": ranges["secondary_metatile_count"],
            "primary_profile_capacity": ranges["primary_profile_capacity"],
            "secondary_profile_capacity": ranges["secondary_profile_capacity"],
            "declared_cell_count": declared_count,
            "source_entry_count": source_entry_count,
            "unique_metatile_id_count": len(layout_unique_ids),
            "absent_metatile_cell_count": sum(row[3] for row in absent_rows),
            "absent_unique_reference_count": len(absent_rows),
            "absent_reason_counts": dict(sorted(layout_reason_counts.items())),
            "absent_metatile_ids": absent_rows,
            "warnings": errors,
        })

    pair_output_rows = []
    for pair_key in sorted(pair_rows):
        row = pair_rows[pair_key]
        absent_rows = compact_absent_metatile_rows(row["absent_by_key"])
        pair_output_rows.append({
            "pair_key": row["pair_key"],
            "primary_tileset": row["primary_tileset"],
            "secondary_tileset": row["secondary_tileset"],
            "source_rules_profile": row["source_rules_profile"],
            "primary_header_found": row["primary_header_found"],
            "secondary_header_found": row["secondary_header_found"],
            "primary_metatile_count": row["primary_metatile_count"],
            "secondary_metatile_count": row["secondary_metatile_count"],
            "primary_profile_capacity": row["primary_profile_capacity"],
            "secondary_profile_capacity": row["secondary_profile_capacity"],
            "layout_count": row["layout_count"],
            "checked_layout_count": row["checked_layout_count"],
            "checked_cell_count": row["checked_cell_count"],
            "declared_cell_count": row["declared_cell_count"],
            "layout_ids": row["layout_ids"],
            "affected_layout_ids": row["affected_layout_ids"],
            "layout_versions": dict(sorted(row["layout_versions"].items())),
            "unique_metatile_id_count": len(row["unique_metatile_ids"]),
            "absent_metatile_cell_count": row["absent_cell_count"],
            "absent_unique_reference_count": len(absent_rows),
            "absent_reason_counts": dict(sorted(row["absent_reason_counts"].items())),
            "absent_metatile_ids": absent_rows,
        })

    return {
        "status": "decoded_import_metadata",
        "runtime_binary_metatile_required": False,
        "source": source_status,
        "source_layout_count": len(layouts),
        "checked_layout_count": checked_layout_count,
        "pair_count": len(pair_output_rows),
        "checked_cell_count": checked_cell_count,
        "declared_cell_count": declared_cell_count,
        "unique_metatile_id_count": len(unique_metatile_ids),
        "absent_metatile_cell_count": sum(row["absent_metatile_cell_count"] for row in layout_rows),
        "absent_unique_reference_count": len(absent_unique_references),
        "absent_global_metatile_id_count": len(absent_global_metatile_ids),
        "layout_with_absent_metatile_count": sum(
            1 for row in layout_rows if row["absent_metatile_cell_count"] > 0
        ),
        "pair_with_absent_metatile_count": sum(
            1 for row in pair_output_rows if row["absent_metatile_cell_count"] > 0
        ),
        "missing_blockdata_layout_count": missing_blockdata_layout_count,
        "invalid_blockdata_layout_count": invalid_blockdata_layout_count,
        "size_mismatch_layout_count": size_mismatch_layout_count,
        "absent_reason_counts": dict(sorted(absent_reason_counts.items())),
        "compact_absent_metatile_encoding": metatile_map_absent_record_encoding(),
        "layouts": layout_rows,
        "pairs": pair_output_rows,
    }


def metatile_tile_image_absent_record_encoding():
    return {
        "version": "compact_metatile_tile_image_absent_v1",
        "detail": (
            "Each absent tile row stores [owner_tileset_symbol, target_tileset_symbol, "
            "source_tileset_kind_code, local_tile_id, source_image_tile_count, count, "
            "reason, samples]. Each sample stores [global_metatile_id, local_metatile_id, "
            "tile_entry_index, raw_tile_entry, tile_id]."
        ),
        "absent_tile_fields": [
            "owner_tileset_symbol",
            "target_tileset_symbol",
            "source_tileset_kind_code",
            "local_tile_id",
            "source_image_tile_count",
            "count",
            "reason",
            "samples",
        ],
        "sample_fields": [
            "global_metatile_id",
            "local_metatile_id",
            "tile_entry_index",
            "raw_tile_entry",
            "tile_id",
        ],
        "source_tileset_kind_codes": TILE_SOURCE_KIND_CODES,
        "reason_codes": [
            "source_header_missing",
            "source_image_missing",
            "source_image_invalid_png",
            "source_image_not_8px_aligned",
            "source_tile_absent",
        ],
    }


def read_png_dimensions(path):
    data = path.read_bytes()
    if len(data) < 24 or data[:8] != PNG_SIGNATURE or data[12:16] != b"IHDR":
        raise ValueError("{} is not a PNG with an IHDR chunk".format(path))
    return int.from_bytes(data[16:20], "big"), int.from_bytes(data[20:24], "big")


def tileset_image_binding(source_root, header):
    tiles_png = header.get("expected_source_directory", {}).get("tiles_png", {})
    path_text = tiles_png.get("path")
    row = {
        "status": "missing_source_image",
        "tileset_symbol": header.get("symbol"),
        "source_kind": header.get("kind"),
        "source_rules_profile": metatile_source_profile_for_branch(header.get("branch")),
        "source": tiles_png,
        "width": None,
        "height": None,
        "tile_width": None,
        "tile_height": None,
        "tile_count": 0,
    }
    if not path_text or not tiles_png.get("exists"):
        return row

    try:
        width, height = read_png_dimensions(source_root / path_text)
    except ValueError as error:
        row["status"] = "source_image_invalid_png"
        row["error"] = str(error)
        return row

    row["width"] = width
    row["height"] = height
    row["tile_width"] = width // TILE_SIZE_PIXELS
    row["tile_height"] = height // TILE_SIZE_PIXELS
    row["tile_count"] = row["tile_width"] * row["tile_height"]
    if width % TILE_SIZE_PIXELS != 0 or height % TILE_SIZE_PIXELS != 0:
        row["status"] = "source_image_not_8px_aligned"
    else:
        row["status"] = "decoded"
    return row


def source_kind_name_from_code(code):
    by_code = {
        value: key
        for key, value in TILE_SOURCE_KIND_CODES.items()
    }
    return by_code[int(code)]


def iter_metatile_tile_entries(header):
    decode = header.get("metatile_binary_decode", {})
    for metatile in decode.get("metatiles", []):
        local_metatile_id = metatile[0]
        global_metatile_id = metatile[1]
        for entry_index, entry in enumerate(metatile[2]):
            source_kind = source_kind_name_from_code(entry[4])
            yield {
                "owner_tileset_symbol": header.get("symbol"),
                "owner_source_kind": decode.get("source_kind"),
                "local_metatile_id": local_metatile_id,
                "global_metatile_id": global_metatile_id,
                "tile_entry_index": entry_index,
                "raw": entry[0],
                "tile_id": entry[1],
                "source_tileset_kind": source_kind,
                "source_tileset_kind_code": entry[4],
                "local_tile_id": entry[5],
                "out_of_range": bool(entry[6]),
            }


def classify_tile_image_reference(entry, target_header, target_image):
    if target_header is None:
        return "source_header_missing"
    if target_image.get("status") != "decoded":
        return target_image.get("status", "source_image_missing")
    if int(entry["local_tile_id"]) >= int(target_image.get("tile_count", 0)):
        return "source_tile_absent"
    return None


def add_absent_tile_image_reference(absent_by_key, entry, target_symbol, target_image, reason):
    key = (
        entry["owner_tileset_symbol"],
        target_symbol,
        entry["source_tileset_kind_code"],
        entry["local_tile_id"],
        target_image.get("tile_count", 0),
        reason,
    )
    row = absent_by_key.setdefault(key, {
        "owner_tileset_symbol": entry["owner_tileset_symbol"],
        "target_tileset_symbol": target_symbol,
        "source_tileset_kind_code": entry["source_tileset_kind_code"],
        "local_tile_id": entry["local_tile_id"],
        "source_image_tile_count": target_image.get("tile_count", 0),
        "count": 0,
        "reason": reason,
        "samples": [],
    })
    row["count"] += 1
    if len(row["samples"]) < 5:
        row["samples"].append([
            entry["global_metatile_id"],
            entry["local_metatile_id"],
            entry["tile_entry_index"],
            entry["raw"],
            entry["tile_id"],
        ])


def compact_absent_tile_image_rows(absent_by_key):
    return [
        [
            row["owner_tileset_symbol"],
            row["target_tileset_symbol"],
            row["source_tileset_kind_code"],
            row["local_tile_id"],
            row["source_image_tile_count"],
            row["count"],
            row["reason"],
            row["samples"],
        ]
        for row in sorted(
            absent_by_key.values(),
            key=lambda item: (
                item["reason"],
                item["target_tileset_symbol"] or "",
                item["owner_tileset_symbol"] or "",
                item["local_tile_id"],
            ),
        )
    ]


def build_metatile_tile_image_reference_report(source_root, records):
    source_root = Path(source_root)
    rows_by_symbol = {
        row["symbol"]: row
        for row in records
    }
    image_by_symbol = {
        row["symbol"]: tileset_image_binding(source_root, row)
        for row in records
    }
    unique_images = {}
    for image in image_by_symbol.values():
        path_text = image.get("source", {}).get("path")
        if path_text and image.get("status") == "decoded":
            unique_images[path_text] = image

    header_rows = []
    header_absent_total = 0
    header_checked_total = 0
    header_foreign_total = 0
    header_absent_unique = set()
    header_reason_counts = {}

    for symbol in sorted(rows_by_symbol):
        header = rows_by_symbol[symbol]
        image = image_by_symbol[symbol]
        checked = 0
        foreign = 0
        referenced_ids = set()
        absent_by_key = {}
        reason_counts = {}
        max_local_tile_id = None

        for entry in iter_metatile_tile_entries(header):
            if entry["source_tileset_kind"] != header["kind"]:
                foreign += 1
                continue
            checked += 1
            referenced_ids.add(entry["local_tile_id"])
            max_local_tile_id = (
                entry["local_tile_id"]
                if max_local_tile_id is None
                else max(max_local_tile_id, entry["local_tile_id"])
            )
            reason = classify_tile_image_reference(entry, header, image)
            if not reason:
                continue
            add_absent_tile_image_reference(absent_by_key, entry, symbol, image, reason)
            bump_counter(reason_counts, reason)
            bump_counter(header_reason_counts, reason)
            header_absent_unique.add((symbol, entry["local_tile_id"], reason))

        absent_rows = compact_absent_tile_image_rows(absent_by_key)
        header_checked_total += checked
        header_foreign_total += foreign
        header_absent_total += sum(row[5] for row in absent_rows)
        header_rows.append({
            "tileset_symbol": symbol,
            "source_kind": header["kind"],
            "source_rules_profile": metatile_source_profile_for_branch(header.get("branch")),
            "active_in_emerald": header.get("active_in_emerald"),
            "image": image,
            "checked_tile_entry_count": checked,
            "foreign_tile_entry_count": foreign,
            "referenced_local_tile_id_count": len(referenced_ids),
            "max_referenced_local_tile_id": max_local_tile_id,
            "absent_tile_entry_count": sum(row[5] for row in absent_rows),
            "absent_unique_tile_reference_count": len(absent_rows),
            "absent_reason_counts": dict(sorted(reason_counts.items())),
            "absent_tile_ids": absent_rows,
        })

    source_pairs = source_layout_tileset_pairs(source_root)
    pair_rows = []
    pair_checked_total = 0
    pair_absent_total = 0
    pair_absent_unique = set()
    pair_reason_counts = {}
    pair_missing_header_count = 0

    for source_pair in source_pairs["pairs"]:
        primary_symbol = source_pair["primary_tileset"]
        secondary_symbol = source_pair["secondary_tileset"]
        primary_header = rows_by_symbol.get(primary_symbol)
        secondary_header = rows_by_symbol.get(secondary_symbol)
        if primary_header is None or secondary_header is None:
            pair_missing_header_count += 1

        checked = 0
        referenced_ids = set()
        absent_by_key = {}
        reason_counts = {}

        for owner_header in [primary_header, secondary_header]:
            if owner_header is None:
                continue
            for entry in iter_metatile_tile_entries(owner_header):
                target_symbol = primary_symbol if entry["source_tileset_kind"] == "primary" else secondary_symbol
                target_header = rows_by_symbol.get(target_symbol)
                target_image = image_by_symbol.get(target_symbol, {
                    "status": "source_header_missing",
                    "source": {"path": None, "exists": False},
                    "tile_count": 0,
                })
                checked += 1
                referenced_ids.add((target_symbol, entry["local_tile_id"]))
                reason = classify_tile_image_reference(entry, target_header, target_image)
                if not reason:
                    continue
                add_absent_tile_image_reference(absent_by_key, entry, target_symbol, target_image, reason)
                bump_counter(reason_counts, reason)
                bump_counter(pair_reason_counts, reason)
                pair_absent_unique.add((source_pair["pair_key"], target_symbol, entry["local_tile_id"], reason))

        absent_rows = compact_absent_tile_image_rows(absent_by_key)
        pair_checked_total += checked
        pair_absent_total += sum(row[5] for row in absent_rows)
        pair_rows.append({
            "pair_key": source_pair["pair_key"],
            "primary_tileset": primary_symbol,
            "secondary_tileset": secondary_symbol,
            "primary_header_found": primary_header is not None,
            "secondary_header_found": secondary_header is not None,
            "primary_image": image_by_symbol.get(primary_symbol),
            "secondary_image": image_by_symbol.get(secondary_symbol),
            "layout_count": source_pair["layout_count"],
            "layout_ids": source_pair["layout_ids"],
            "layout_versions": dict(sorted(source_pair["layout_versions"].items())),
            "checked_tile_entry_count": checked,
            "referenced_tile_id_count": len(referenced_ids),
            "absent_tile_entry_count": sum(row[5] for row in absent_rows),
            "absent_unique_tile_reference_count": len(absent_rows),
            "absent_reason_counts": dict(sorted(reason_counts.items())),
            "absent_tile_ids": absent_rows,
        })

    return {
        "status": "decoded_import_metadata",
        "runtime_binary_tiles_required": False,
        "tile_size_pixels": TILE_SIZE_PIXELS,
        "source_header_count": len(records),
        "header_image_binding_count": len(image_by_symbol),
        "decoded_image_binding_count": sum(
            1 for image in image_by_symbol.values() if image.get("status") == "decoded"
        ),
        "unique_source_image_count": len(unique_images),
        "unique_source_image_tile_count": sum(int(image.get("tile_count", 0)) for image in unique_images.values()),
        "header_checked_tile_entry_count": header_checked_total,
        "header_foreign_tile_entry_count": header_foreign_total,
        "header_absent_tile_entry_count": header_absent_total,
        "header_absent_unique_tile_reference_count": len(header_absent_unique),
        "header_with_absent_tile_count": sum(
            1 for row in header_rows if row["absent_tile_entry_count"] > 0
        ),
        "header_absent_reason_counts": dict(sorted(header_reason_counts.items())),
        "pair_count": len(pair_rows),
        "pair_checked_tile_entry_count": pair_checked_total,
        "pair_absent_tile_entry_count": pair_absent_total,
        "pair_absent_unique_tile_reference_count": len(pair_absent_unique),
        "pair_with_absent_tile_count": sum(
            1 for row in pair_rows if row["absent_tile_entry_count"] > 0
        ),
        "pair_missing_header_count": pair_missing_header_count,
        "pair_absent_reason_counts": dict(sorted(pair_reason_counts.items())),
        "compact_absent_tile_encoding": metatile_tile_image_absent_record_encoding(),
        "headers": header_rows,
        "pairs": pair_rows,
    }


def parse_tileset_headers(
    source_root,
    animation_frames=None,
    init_functions=None,
    animation_schedule_trace=None,
    palette_rules=None,
    metatile_rules=None,
    metatile_attribute_rules=None,
    metatile_label_rules=None,
):
    headers_path = source_root / "src/data/tilesets/headers.h"
    text = read_text(headers_path)
    declarations = parse_asset_declarations(source_root)
    animation_frames = animation_frames or []
    animation_schedule_trace = animation_schedule_trace or {}
    palette_rules = palette_rules or parse_palette_slot_rules(source_root)
    metatile_rules = metatile_rules or parse_metatile_decode_rules(source_root)
    metatile_attribute_rules = metatile_attribute_rules or parse_metatile_attribute_rules(source_root)
    metatile_label_rules = metatile_label_rules or parse_metatile_label_rules(source_root)
    init_function_symbols = {
        row["function"]: row
        for row in (init_functions or [])
    }
    schedule_init_by_function = {
        row["function"]: row
        for row in animation_schedule_trace.get("init_functions", [])
    }
    schedule_events_by_callback = {}
    for event in animation_schedule_trace.get("events", []):
        schedule_events_by_callback.setdefault(event.get("callback"), []).append(event)
    rows = []

    for branch, active_in_emerald, section in split_header_sections(text):
        section_offset = text.find(section) if section else -1
        for match in HEADER_RE.finditer(section):
            body = match.group(2)
            symbol = match.group(1)
            is_secondary_expr = field_expr(body, "isSecondary")
            is_compressed_expr = field_expr(body, "isCompressed")
            callback_symbol = field_expr(body, "callback") or "NULL"
            callback_schedule = tileset_callback_schedule_metadata(
                callback_symbol,
                schedule_init_by_function,
                schedule_events_by_callback,
            )
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
            metatile_attribute_decode = metatile_attribute_decode_for_header(
                source_root,
                kind,
                branch,
                assets["metatile_attributes"],
                metatile_attribute_rules,
            )
            metatile_label_lookup = metatile_label_lookup_for_header(
                kind,
                branch,
                symbol,
                metatile_binary_decode,
                metatile_label_rules,
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
                    **callback_schedule,
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
                "metatile_attribute_decode": metatile_attribute_decode,
                "metatile_label_lookup": metatile_label_lookup,
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


def build_stats(
    source_files,
    records,
    animation_frames=None,
    animation_frame_strip_export=None,
    animation_schedule_trace=None,
    init_functions=None,
    metatile_label_rules=None,
    metatile_label_pair_lookup=None,
    metatile_map_reference_report=None,
    metatile_tile_image_reference_report=None,
    tileset_callback_map_report=None,
):
    animation_frames = animation_frames or []
    animation_frame_strip_export = animation_frame_strip_export or {}
    animation_schedule_trace = animation_schedule_trace or {}
    init_functions = init_functions or []
    metatile_label_rules = metatile_label_rules or {}
    metatile_label_pair_lookup = metatile_label_pair_lookup or {}
    metatile_map_reference_report = metatile_map_reference_report or {}
    metatile_tile_image_reference_report = metatile_tile_image_reference_report or {}
    tileset_callback_map_report = tileset_callback_map_report or {}
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
    metatile_attribute_decodes = [
        row.get("metatile_attribute_decode", {})
        for row in records
    ]
    active_metatile_attribute_decodes = [
        row.get("metatile_attribute_decode", {})
        for row in active
    ]
    metatile_label_lookups = [
        row.get("metatile_label_lookup", {})
        for row in records
    ]
    active_metatile_label_lookups = [
        row.get("metatile_label_lookup", {})
        for row in active
    ]
    unique_metatile_decodes = unique_metatile_decodes_by_source_binary(metatile_decodes)
    active_unique_metatile_decodes = unique_metatile_decodes_by_source_binary(active_metatile_decodes)
    unique_metatile_attribute_decodes = unique_metatile_decodes_by_source_binary(metatile_attribute_decodes)
    active_unique_metatile_attribute_decodes = unique_metatile_decodes_by_source_binary(
        active_metatile_attribute_decodes
    )
    missing_metatile_decodes = [
        {
            "tileset": row["symbol"],
            "metatiles_symbol": row.get("metatile_binary_decode", {}).get("source_metatiles_symbol"),
            "status": row.get("metatile_binary_decode", {}).get("status"),
        }
        for row in records
        if row.get("metatile_binary_decode", {}).get("status") != "decoded"
    ]
    missing_metatile_attribute_decodes = [
        {
            "tileset": row["symbol"],
            "metatile_attributes_symbol": row.get("metatile_attribute_decode", {}).get(
                "source_metatile_attributes_symbol"
            ),
            "status": row.get("metatile_attribute_decode", {}).get("status"),
        }
        for row in records
        if row.get("metatile_attribute_decode", {}).get("status") != "decoded"
    ]
    out_of_range_tile_entries = [
        dict({"tileset": row["symbol"]}, **entry)
        for row in records
        for entry in row.get("metatile_binary_decode", {}).get("out_of_range_tile_entries", [])
    ]
    out_of_range_metatile_labels = [
        {
            "tileset": row["symbol"],
            "label": label[0],
            "metatile_id": label[1],
            "local_metatile_id": label[2],
            "source_line": label[3],
            "resolution_code": label[4],
        }
        for row in records
        for label in row.get("metatile_label_lookup", {}).get("out_of_range_labels", [])
    ]
    header_symbols = {row["symbol"] for row in records}
    label_source_groups = [
        group
        for group in metatile_label_rules.get("groups", [])
        if group.get("source_tileset_symbol")
    ]
    unmatched_label_source_groups = [
        group["source_tileset_symbol"]
        for group in label_source_groups
        if group["source_tileset_symbol"] not in header_symbols
    ]
    pair_rows = metatile_label_pair_lookup.get("pairs", [])
    pair_missing_headers = [
        {
            "pair_key": row["pair_key"],
            "primary_header_found": row.get("primary_header_found"),
            "secondary_header_found": row.get("secondary_header_found"),
        }
        for row in pair_rows
        if not row.get("primary_header_found") or not row.get("secondary_header_found")
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
        "callback_map_layout_count": int(tileset_callback_map_report.get("layout_count", 0)),
        "callback_map_map_count": int(tileset_callback_map_report.get("map_count", 0)),
        "callback_map_grouped_map_count": int(tileset_callback_map_report.get("grouped_map_count", 0)),
        "callback_map_ungrouped_map_count": int(tileset_callback_map_report.get("ungrouped_map_count", 0)),
        "callback_map_layout_with_map_count": int(tileset_callback_map_report.get("layout_with_map_count", 0)),
        "callback_map_standalone_layout_count": int(tileset_callback_map_report.get("standalone_layout_count", 0)),
        "callback_map_pair_count": int(tileset_callback_map_report.get("pair_count", 0)),
        "callback_map_layout_role_count": int(tileset_callback_map_report.get("layout_role_count", 0)),
        "callback_map_primary_layout_role_count": int(
            tileset_callback_map_report.get("primary_layout_role_count", 0)
        ),
        "callback_map_secondary_layout_role_count": int(
            tileset_callback_map_report.get("secondary_layout_role_count", 0)
        ),
        "callback_map_tileset_usage_count": int(tileset_callback_map_report.get("tileset_usage_count", 0)),
        "callback_map_primary_tileset_usage_count": int(
            tileset_callback_map_report.get("primary_tileset_usage_count", 0)
        ),
        "callback_map_secondary_tileset_usage_count": int(
            tileset_callback_map_report.get("secondary_tileset_usage_count", 0)
        ),
        "callback_map_tileset_with_callback_count": int(
            tileset_callback_map_report.get("tileset_with_callback_count", 0)
        ),
        "callback_map_null_callback_tileset_count": int(
            tileset_callback_map_report.get("null_callback_tileset_count", 0)
        ),
        "callback_map_missing_header_tileset_count": int(
            tileset_callback_map_report.get("missing_header_tileset_count", 0)
        ),
        "callback_map_callback_symbol_count": int(tileset_callback_map_report.get("callback_symbol_count", 0)),
        "callback_map_callback_with_map_count": int(tileset_callback_map_report.get("callback_with_map_count", 0)),
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
        "metatile_attribute_decode_header_count": sum(
            1 for decode in metatile_attribute_decodes if decode.get("status") == "decoded"
        ),
        "active_metatile_attribute_decode_header_count": sum(
            1 for decode in active_metatile_attribute_decodes if decode.get("status") == "decoded"
        ),
        "missing_metatile_attribute_decode_header_count": len(missing_metatile_attribute_decodes),
        "missing_metatile_attribute_decodes": missing_metatile_attribute_decodes,
        "metatile_attribute_record_count": sum(
            int(decode.get("metatile_attribute_count", 0))
            for decode in metatile_attribute_decodes
        ),
        "active_metatile_attribute_record_count": sum(
            int(decode.get("metatile_attribute_count", 0))
            for decode in active_metatile_attribute_decodes
        ),
        "unique_metatile_attribute_source_binary_count": len(unique_metatile_attribute_decodes),
        "active_unique_metatile_attribute_source_binary_count": len(active_unique_metatile_attribute_decodes),
        "unique_metatile_attribute_record_count": sum(
            int(decode.get("metatile_attribute_count", 0))
            for decode in unique_metatile_attribute_decodes
        ),
        "active_unique_metatile_attribute_record_count": sum(
            int(decode.get("metatile_attribute_count", 0))
            for decode in active_unique_metatile_attribute_decodes
        ),
        "metatile_attribute_record_count_by_source_profile": merge_count_dicts(
            {
                decode.get("source_rules_profile"): int(decode.get("metatile_attribute_count", 0))
            }
            for decode in metatile_attribute_decodes
        ),
        "metatile_attribute_layer_type_counts": merge_count_dicts(
            decode.get("layer_type_counts", {})
            for decode in metatile_attribute_decodes
        ),
        "active_metatile_attribute_layer_type_counts": merge_count_dicts(
            decode.get("layer_type_counts", {})
            for decode in active_metatile_attribute_decodes
        ),
        "metatile_attribute_terrain_type_counts": merge_count_dicts(
            decode.get("terrain_type_counts", {})
            for decode in metatile_attribute_decodes
        ),
        "metatile_attribute_encounter_type_counts": merge_count_dicts(
            decode.get("encounter_type_counts", {})
            for decode in metatile_attribute_decodes
        ),
        "metatile_attribute_terrain_decoded_record_count": sum(
            int(decode.get("metatile_attribute_count", 0))
            for decode in metatile_attribute_decodes
            if decode.get("terrain_type_status") == "decoded"
        ),
        "metatile_attribute_terrain_not_encoded_record_count": sum(
            int(decode.get("metatile_attribute_count", 0))
            for decode in metatile_attribute_decodes
            if decode.get("terrain_type_status") == "not_encoded_in_emerald_attributes"
        ),
        "metatile_attribute_encounter_type_decoded_record_count": sum(
            int(decode.get("metatile_attribute_count", 0))
            for decode in metatile_attribute_decodes
            if decode.get("encounter_type_status") == "decoded"
        ),
        "metatile_attribute_encounter_type_not_encoded_record_count": sum(
            int(decode.get("metatile_attribute_count", 0))
            for decode in metatile_attribute_decodes
            if decode.get("encounter_type_status") == "not_encoded_in_emerald_attributes"
        ),
        "metatile_attribute_encounter_affordance_count": sum(
            int(decode.get("encounter_affordance_count", 0))
            for decode in metatile_attribute_decodes
        ),
        "active_metatile_attribute_encounter_affordance_count": sum(
            int(decode.get("encounter_affordance_count", 0))
            for decode in active_metatile_attribute_decodes
        ),
        "metatile_attribute_surfable_affordance_count": sum(
            int(decode.get("surfable_affordance_count", 0))
            for decode in metatile_attribute_decodes
        ),
        "active_metatile_attribute_surfable_affordance_count": sum(
            int(decode.get("surfable_affordance_count", 0))
            for decode in active_metatile_attribute_decodes
        ),
        "metatile_attribute_land_encounter_affordance_count": sum(
            int(decode.get("land_encounter_affordance_count", 0))
            for decode in metatile_attribute_decodes
        ),
        "metatile_attribute_water_encounter_affordance_count": sum(
            int(decode.get("water_encounter_affordance_count", 0))
            for decode in metatile_attribute_decodes
        ),
        "metatile_attribute_missing_behavior_name_count": sum(
            int(decode.get("missing_behavior_name_count", 0))
            for decode in metatile_attribute_decodes
        ),
        "metatile_label_source_label_count": int(metatile_label_rules.get("label_count", 0)),
        "metatile_label_source_group_count": int(metatile_label_rules.get("source_group_count", 0)),
        "metatile_label_source_tileset_group_count": int(
            metatile_label_rules.get("source_tileset_group_count", 0)
        ),
        "metatile_label_non_tileset_group_count": int(
            metatile_label_rules.get("non_tileset_group_count", 0)
        ),
        "metatile_label_source_group_with_header_count": sum(
            1
            for group in label_source_groups
            if group["source_tileset_symbol"] in header_symbols
        ),
        "metatile_label_unmatched_source_group_count": len(unmatched_label_source_groups),
        "metatile_label_unmatched_source_groups": unmatched_label_source_groups,
        "metatile_label_header_decode_count": sum(
            1 for lookup in metatile_label_lookups if lookup.get("label_count", 0) > 0
        ),
        "active_metatile_label_header_decode_count": sum(
            1 for lookup in active_metatile_label_lookups if lookup.get("label_count", 0) > 0
        ),
        "metatile_label_record_count": sum(
            int(lookup.get("label_count", 0))
            for lookup in metatile_label_lookups
        ),
        "active_metatile_label_record_count": sum(
            int(lookup.get("label_count", 0))
            for lookup in active_metatile_label_lookups
        ),
        "metatile_label_reverse_lookup_metatile_id_count": sum(
            int(lookup.get("reverse_lookup_metatile_id_count", 0))
            for lookup in metatile_label_lookups
        ),
        "active_metatile_label_reverse_lookup_metatile_id_count": sum(
            int(lookup.get("reverse_lookup_metatile_id_count", 0))
            for lookup in active_metatile_label_lookups
        ),
        "metatile_label_out_of_range_count": len(out_of_range_metatile_labels),
        "metatile_label_out_of_range_labels": out_of_range_metatile_labels,
        "metatile_label_pair_lookup_count": int(metatile_label_pair_lookup.get("pair_count", 0)),
        "metatile_label_pair_lookup_layout_count": int(
            metatile_label_pair_lookup.get("source_layout_count", 0)
        ),
        "metatile_label_pair_with_labels_count": sum(
            1 for row in pair_rows if int(row.get("label_count", 0)) > 0
        ),
        "metatile_label_pair_label_record_count": sum(
            int(row.get("label_count", 0))
            for row in pair_rows
        ),
        "metatile_label_pair_reverse_lookup_metatile_id_count": sum(
            int(row.get("reverse_lookup_metatile_id_count", 0))
            for row in pair_rows
        ),
        "metatile_label_pair_out_of_range_count": sum(
            int(row.get("out_of_pair_label_count", 0))
            for row in pair_rows
        ),
        "metatile_label_pair_missing_header_count": len(pair_missing_headers),
        "metatile_label_pair_missing_headers": pair_missing_headers,
        "metatile_map_reference_layout_count": int(
            metatile_map_reference_report.get("source_layout_count", 0)
        ),
        "metatile_map_reference_checked_layout_count": int(
            metatile_map_reference_report.get("checked_layout_count", 0)
        ),
        "metatile_map_reference_pair_count": int(
            metatile_map_reference_report.get("pair_count", 0)
        ),
        "metatile_map_reference_checked_cell_count": int(
            metatile_map_reference_report.get("checked_cell_count", 0)
        ),
        "metatile_map_reference_declared_cell_count": int(
            metatile_map_reference_report.get("declared_cell_count", 0)
        ),
        "metatile_map_reference_unique_metatile_id_count": int(
            metatile_map_reference_report.get("unique_metatile_id_count", 0)
        ),
        "metatile_map_reference_absent_cell_count": int(
            metatile_map_reference_report.get("absent_metatile_cell_count", 0)
        ),
        "metatile_map_reference_absent_unique_reference_count": int(
            metatile_map_reference_report.get("absent_unique_reference_count", 0)
        ),
        "metatile_map_reference_absent_global_metatile_id_count": int(
            metatile_map_reference_report.get("absent_global_metatile_id_count", 0)
        ),
        "metatile_map_reference_layout_with_absent_count": int(
            metatile_map_reference_report.get("layout_with_absent_metatile_count", 0)
        ),
        "metatile_map_reference_pair_with_absent_count": int(
            metatile_map_reference_report.get("pair_with_absent_metatile_count", 0)
        ),
        "metatile_map_reference_missing_blockdata_layout_count": int(
            metatile_map_reference_report.get("missing_blockdata_layout_count", 0)
        ),
        "metatile_map_reference_invalid_blockdata_layout_count": int(
            metatile_map_reference_report.get("invalid_blockdata_layout_count", 0)
        ),
        "metatile_map_reference_size_mismatch_layout_count": int(
            metatile_map_reference_report.get("size_mismatch_layout_count", 0)
        ),
        "metatile_map_reference_absent_reason_counts": metatile_map_reference_report.get(
            "absent_reason_counts",
            {},
        ),
        "metatile_tile_image_reference_header_count": int(
            metatile_tile_image_reference_report.get("source_header_count", 0)
        ),
        "metatile_tile_image_reference_header_image_binding_count": int(
            metatile_tile_image_reference_report.get("header_image_binding_count", 0)
        ),
        "metatile_tile_image_reference_decoded_image_binding_count": int(
            metatile_tile_image_reference_report.get("decoded_image_binding_count", 0)
        ),
        "metatile_tile_image_reference_unique_source_image_count": int(
            metatile_tile_image_reference_report.get("unique_source_image_count", 0)
        ),
        "metatile_tile_image_reference_unique_source_image_tile_count": int(
            metatile_tile_image_reference_report.get("unique_source_image_tile_count", 0)
        ),
        "metatile_tile_image_reference_header_checked_tile_entry_count": int(
            metatile_tile_image_reference_report.get("header_checked_tile_entry_count", 0)
        ),
        "metatile_tile_image_reference_header_foreign_tile_entry_count": int(
            metatile_tile_image_reference_report.get("header_foreign_tile_entry_count", 0)
        ),
        "metatile_tile_image_reference_header_absent_tile_entry_count": int(
            metatile_tile_image_reference_report.get("header_absent_tile_entry_count", 0)
        ),
        "metatile_tile_image_reference_header_absent_unique_tile_reference_count": int(
            metatile_tile_image_reference_report.get("header_absent_unique_tile_reference_count", 0)
        ),
        "metatile_tile_image_reference_header_with_absent_tile_count": int(
            metatile_tile_image_reference_report.get("header_with_absent_tile_count", 0)
        ),
        "metatile_tile_image_reference_header_absent_reason_counts": (
            metatile_tile_image_reference_report.get("header_absent_reason_counts", {})
        ),
        "metatile_tile_image_reference_pair_count": int(
            metatile_tile_image_reference_report.get("pair_count", 0)
        ),
        "metatile_tile_image_reference_pair_checked_tile_entry_count": int(
            metatile_tile_image_reference_report.get("pair_checked_tile_entry_count", 0)
        ),
        "metatile_tile_image_reference_pair_absent_tile_entry_count": int(
            metatile_tile_image_reference_report.get("pair_absent_tile_entry_count", 0)
        ),
        "metatile_tile_image_reference_pair_absent_unique_tile_reference_count": int(
            metatile_tile_image_reference_report.get("pair_absent_unique_tile_reference_count", 0)
        ),
        "metatile_tile_image_reference_pair_with_absent_tile_count": int(
            metatile_tile_image_reference_report.get("pair_with_absent_tile_count", 0)
        ),
        "metatile_tile_image_reference_pair_missing_header_count": int(
            metatile_tile_image_reference_report.get("pair_missing_header_count", 0)
        ),
        "metatile_tile_image_reference_pair_absent_reason_counts": (
            metatile_tile_image_reference_report.get("pair_absent_reason_counts", {})
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
        "animation_rgba_frame_strip_count": int(
            animation_frame_strip_export.get("generated_strip_count", 0)
        ),
        "animation_rgba_frame_strip_written_count": int(
            animation_frame_strip_export.get("written_strip_count", 0)
        ),
        "animation_rgba_frame_strip_source_image_count": int(
            animation_frame_strip_export.get("source_image_count", 0)
        ),
        "animation_rgba_frame_strip_existing_source_image_count": int(
            animation_frame_strip_export.get("existing_source_image_count", 0)
        ),
        "animation_rgba_frame_strip_missing_source_image_count": int(
            animation_frame_strip_export.get("missing_source_image_count", 0)
        ),
        "animation_rgba_frame_strip_invalid_source_image_count": int(
            animation_frame_strip_export.get("invalid_source_image_count", 0)
        ),
        "animation_rgba_frame_strip_total_width_pixels": int(
            animation_frame_strip_export.get("total_strip_width_pixels", 0)
        ),
        "animation_rgba_frame_strip_total_height_pixels": int(
            animation_frame_strip_export.get("total_strip_height_pixels", 0)
        ),
        "animation_schedule_init_function_count": int(
            animation_schedule_trace.get("init_function_count", 0)
        ),
        "animation_schedule_active_init_function_count": int(
            animation_schedule_trace.get("active_init_function_count", 0)
        ),
        "animation_schedule_callback_count": int(
            animation_schedule_trace.get("callback_count", 0)
        ),
        "animation_schedule_event_count": int(
            animation_schedule_trace.get("event_count", 0)
        ),
        "animation_schedule_tile_copy_event_count": int(
            animation_schedule_trace.get("tile_copy_event_count", 0)
        ),
        "animation_schedule_palette_event_count": int(
            animation_schedule_trace.get("palette_event_count", 0)
        ),
        "animation_schedule_queue_function_count": int(
            animation_schedule_trace.get("queue_function_count", 0)
        ),
        "animation_schedule_tile_copy_queue_function_count": int(
            animation_schedule_trace.get("tile_copy_queue_function_count", 0)
        ),
        "animation_schedule_palette_queue_function_count": int(
            animation_schedule_trace.get("palette_queue_function_count", 0)
        ),
        "animation_schedule_tile_copy_append_count": int(
            animation_schedule_trace.get("tile_copy_append_count", 0)
        ),
        "animation_schedule_direct_tile_offset_append_count": int(
            animation_schedule_trace.get("direct_tile_offset_append_count", 0)
        ),
        "animation_schedule_vdest_array_append_count": int(
            animation_schedule_trace.get("vdest_array_append_count", 0)
        ),
        "animation_schedule_append_with_affected_metatile_count": int(
            animation_schedule_trace.get("append_with_affected_metatile_count", 0)
        ),
        "animation_schedule_affected_metatile_reference_count": int(
            animation_schedule_trace.get("affected_metatile_reference_count", 0)
        ),
        "animation_schedule_affected_unique_metatile_count_max_per_append": int(
            animation_schedule_trace.get("affected_unique_metatile_count_max_per_append", 0)
        ),
        "animation_schedule_pointer_array_count": int(
            animation_schedule_trace.get("pointer_array_count", 0)
        ),
        "animation_schedule_vdest_array_count": int(
            animation_schedule_trace.get("vdest_array_count", 0)
        ),
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
        "callback_map_layout_count": stats["callback_map_layout_count"],
        "callback_map_map_count": stats["callback_map_map_count"],
        "callback_map_pair_count": stats["callback_map_pair_count"],
        "callback_map_callback_symbol_count": stats["callback_map_callback_symbol_count"],
        "callback_map_tileset_usage_count": stats["callback_map_tileset_usage_count"],
        "palette_slot_mapping_count": stats["palette_slot_mapping_count"],
        "palette_existing_editable_source_candidate_count": stats["palette_existing_editable_source_candidate_count"],
        "palette_missing_editable_source_candidate_count": stats["palette_missing_editable_source_candidate_count"],
        "metatile_record_count": stats["metatile_record_count"],
        "metatile_tile_entry_count": stats["metatile_tile_entry_count"],
        "unique_metatile_source_binary_count": stats["unique_metatile_source_binary_count"],
        "unique_metatile_record_count": stats["unique_metatile_record_count"],
        "unique_metatile_tile_entry_count": stats["unique_metatile_tile_entry_count"],
        "metatile_out_of_range_tile_entry_count": stats["metatile_out_of_range_tile_entry_count"],
        "metatile_attribute_record_count": stats["metatile_attribute_record_count"],
        "unique_metatile_attribute_source_binary_count": stats["unique_metatile_attribute_source_binary_count"],
        "unique_metatile_attribute_record_count": stats["unique_metatile_attribute_record_count"],
        "metatile_attribute_encounter_affordance_count": stats["metatile_attribute_encounter_affordance_count"],
        "metatile_attribute_missing_behavior_name_count": stats["metatile_attribute_missing_behavior_name_count"],
        "metatile_label_source_label_count": stats["metatile_label_source_label_count"],
        "metatile_label_record_count": stats["metatile_label_record_count"],
        "metatile_label_pair_lookup_count": stats["metatile_label_pair_lookup_count"],
        "metatile_label_pair_label_record_count": stats["metatile_label_pair_label_record_count"],
        "metatile_label_pair_out_of_range_count": stats["metatile_label_pair_out_of_range_count"],
        "metatile_map_reference_checked_layout_count": stats["metatile_map_reference_checked_layout_count"],
        "metatile_map_reference_checked_cell_count": stats["metatile_map_reference_checked_cell_count"],
        "metatile_map_reference_absent_cell_count": stats["metatile_map_reference_absent_cell_count"],
        "metatile_map_reference_layout_with_absent_count": stats[
            "metatile_map_reference_layout_with_absent_count"
        ],
        "metatile_map_reference_pair_with_absent_count": stats[
            "metatile_map_reference_pair_with_absent_count"
        ],
        "metatile_tile_image_reference_decoded_image_binding_count": stats[
            "metatile_tile_image_reference_decoded_image_binding_count"
        ],
        "metatile_tile_image_reference_header_absent_tile_entry_count": stats[
            "metatile_tile_image_reference_header_absent_tile_entry_count"
        ],
        "metatile_tile_image_reference_pair_absent_tile_entry_count": stats[
            "metatile_tile_image_reference_pair_absent_tile_entry_count"
        ],
        "metatile_tile_image_reference_pair_with_absent_tile_count": stats[
            "metatile_tile_image_reference_pair_with_absent_tile_count"
        ],
        "animation_frame_declaration_count": stats["animation_frame_declaration_count"],
        "animation_existing_editable_source_candidate_count": stats["animation_existing_editable_source_candidate_count"],
        "animation_rgba_frame_strip_count": stats["animation_rgba_frame_strip_count"],
        "animation_rgba_frame_strip_source_image_count": stats["animation_rgba_frame_strip_source_image_count"],
        "animation_rgba_frame_strip_missing_source_image_count": stats[
            "animation_rgba_frame_strip_missing_source_image_count"
        ],
        "animation_rgba_frame_strip_invalid_source_image_count": stats[
            "animation_rgba_frame_strip_invalid_source_image_count"
        ],
        "animation_schedule_event_count": stats["animation_schedule_event_count"],
        "animation_schedule_tile_copy_event_count": stats["animation_schedule_tile_copy_event_count"],
        "animation_schedule_palette_event_count": stats["animation_schedule_palette_event_count"],
        "animation_schedule_tile_copy_append_count": stats["animation_schedule_tile_copy_append_count"],
        "animation_schedule_vdest_array_append_count": stats["animation_schedule_vdest_array_append_count"],
        "animation_schedule_append_with_affected_metatile_count": stats[
            "animation_schedule_append_with_affected_metatile_count"
        ],
        "animation_schedule_affected_metatile_reference_count": stats[
            "animation_schedule_affected_metatile_reference_count"
        ],
        "missing_callback_source_count": stats["missing_callback_source_count"],
        "missing_asset_declaration_count": stats["missing_asset_declaration_count"],
    }


def build_export(source_root, output_asset_root=None, write_assets=False):
    source_root = Path(source_root)
    source_files = source_file_presence(source_root)
    animation_frames = parse_animation_frame_declarations(source_root)
    animation_frame_strip_export = build_tileset_animation_frame_strip_export(
        source_root,
        animation_frames,
        output_asset_root=output_asset_root,
        write_assets=write_assets,
    )
    init_functions = parse_init_function_symbols(source_root)
    palette_rules = parse_palette_slot_rules(source_root)
    metatile_rules = parse_metatile_decode_rules(source_root)
    metatile_attribute_rules = parse_metatile_attribute_rules(source_root)
    metatile_label_rules = parse_metatile_label_rules(source_root)
    records = parse_tileset_headers(
        source_root,
        animation_frames=animation_frames,
        init_functions=init_functions,
        palette_rules=palette_rules,
        metatile_rules=metatile_rules,
        metatile_attribute_rules=metatile_attribute_rules,
        metatile_label_rules=metatile_label_rules,
    )
    animation_schedule_trace = build_tileset_animation_schedule_trace(
        source_root,
        records,
        animation_frames,
    )
    attach_tileset_animation_schedule_trace(records, animation_schedule_trace)
    metatile_label_pair_lookup = build_metatile_label_pair_lookup(
        source_root,
        records,
        metatile_label_rules,
    )
    metatile_map_reference_report = build_metatile_map_reference_report(
        source_root,
        records,
    )
    metatile_tile_image_reference_report = build_metatile_tile_image_reference_report(
        source_root,
        records,
    )
    tileset_callback_map_report = build_tileset_callback_map_report(
        source_root,
        records,
    )
    stats = build_stats(
        source_files,
        records,
        animation_frames,
        animation_frame_strip_export,
        animation_schedule_trace,
        init_functions,
        metatile_label_rules,
        metatile_label_pair_lookup,
        metatile_map_reference_report,
        metatile_tile_image_reference_report,
        tileset_callback_map_report,
    )
    return {
        "schema_version": 1,
        "generated_by": GENERATED_BY,
        "source_root": str(source_root),
        "source_files": source_files,
        "palette_slot_rules": palette_rules,
        "metatile_decode_rules": metatile_rules,
        "metatile_attribute_rules": metatile_attribute_rules,
        "metatile_label_rules": metatile_label_rules,
        "metatile_label_pair_lookup": metatile_label_pair_lookup,
        "tileset_callback_map_report": tileset_callback_map_report,
        "metatile_map_reference_report": metatile_map_reference_report,
        "metatile_tile_image_reference_report": metatile_tile_image_reference_report,
        "tileset_headers": records,
        "tileset_animation_frames": animation_frames,
        "tileset_animation_frame_strips": animation_frame_strip_export,
        "tileset_animation_schedule_trace": animation_schedule_trace,
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
                "detail": "Header callback symbols, callback source bindings, animation frame image provenance, generated RGBA frame strips, and source schedule/copy-target metadata are exported, but no source-equivalent Godot tileset animation scheduler is implemented yet.",
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
    parser.add_argument("--output-asset-root", type=Path, help="Generated asset output root.")
    args = parser.parse_args(argv)

    config = load_config(args.config)
    source_root = args.source or Path(config.get("source_root", ""))
    output_root = args.output_root or Path(config.get("generated_data_root", "data/generated"))
    output_asset_root = args.output_asset_root or Path(config.get("generated_asset_root", "assets/generated"))
    output_path = output_root / REPORT_PATH

    exported = build_export(source_root, output_asset_root=output_asset_root, write_assets=True)
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
