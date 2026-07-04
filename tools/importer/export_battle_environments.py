#!/usr/bin/env python3
"""Export battle environment metadata and palette-baked PNG assets."""

import argparse
import json
import math
import re
import struct
import sys
from pathlib import Path

from export_map import to_project_path, write_json, write_manifest
from source_probe import load_config


ENVIRONMENT_GRAPHICS_SOURCE = Path("src/data/graphics/battle_environment.h")
ENVIRONMENT_DATA_SOURCE = Path("src/data/battle_environment.h")
BATTLE_CONSTANTS_SOURCE = Path("include/constants/battle.h")
MAP_TYPES_SOURCE = Path("include/constants/map_types.h")
BATTLE_SETUP_SOURCE = Path("src/battle_setup.c")
BATTLE_BG_SOURCE = Path("src/battle_bg.c")
ASSET_CATEGORY = "environments"
ASSET_OUTPUT_DIR = "battle_environment"
VISIBLE_VIEWPORT = {"w": 240, "h": 160}
TILE_SIZE = 8

BINARY_ASSET_EXTENSIONS = [
    (".4bpp.smol", ".png"),
    (".4bpp.lz", ".png"),
    (".4bpp", ".png"),
    (".bin.smolTM", ".bin"),
    (".bin.lz", ".bin"),
    (".gbapal", ".pal"),
]


def _strip_comment(line):
    return line.split("//", 1)[0].strip()


def _parse_int_expr(value, constants=None, default=None):
    text = str(value).strip()
    constants = constants or {}
    while text.startswith("(") and text.endswith(")"):
        text = text[1:-1].strip()
    if text in constants:
        constant = constants[text]
        return constant["value"] if isinstance(constant, dict) else constant
    try:
        return int(text, 0)
    except ValueError:
        return default


def _parse_enum_constants(path, enum_marker, symbol_prefix):
    constants = {}
    order = []
    in_enum = False
    value = 0
    with path.open("r", encoding="utf-8", errors="replace") as handle:
        for line_no, raw_line in enumerate(handle, start=1):
            line = _strip_comment(raw_line)
            if not in_enum:
                if enum_marker in line:
                    in_enum = True
                continue
            if "{" in line:
                continue
            if "};" in line:
                break
            if not line:
                continue
            line = line.rstrip(",").strip()
            if not line:
                continue
            if "=" in line:
                symbol, expr = [part.strip() for part in line.split("=", 1)]
                parsed_value = _parse_int_expr(expr, constants, value)
            else:
                symbol = line.strip()
                parsed_value = value
            if not symbol.startswith(symbol_prefix):
                value = int(parsed_value) + 1
                continue
            constants[symbol] = {
                "symbol": symbol,
                "value": int(parsed_value),
                "source": {
                    "file": to_project_path(path),
                    "line": line_no,
                },
            }
            order.append(symbol)
            value = int(parsed_value) + 1
    return constants, order


def _parse_graphics_definitions(source_root):
    source_path = source_root / ENVIRONMENT_GRAPHICS_SOURCE
    definition_re = re.compile(
        r'^\s*(?:static\s+)?const\s+\w+\s+(\w+)\[\]\s*=\s*INCBIN_\w+\("([^"]+)"\)'
    )
    definitions = {}
    with source_path.open("r", encoding="utf-8", errors="replace") as handle:
        for line_no, line in enumerate(handle, start=1):
            match = definition_re.search(line)
            if match is None:
                continue
            symbol, binary_path = match.groups()
            definitions[symbol] = {
                "symbol": symbol,
                "source_binary_path": binary_path,
                "source_asset_path": to_project_path(_source_asset_path(binary_path)),
                "source_file": to_project_path(ENVIRONMENT_GRAPHICS_SOURCE),
                "source_line": line_no,
                "source_trace": "{}:{}".format(to_project_path(ENVIRONMENT_GRAPHICS_SOURCE), symbol),
            }
    return definitions


def _source_asset_path(binary_path):
    text = to_project_path(binary_path)
    for old_ext, new_ext in BINARY_ASSET_EXTENSIONS:
        if text.endswith(old_ext):
            return Path(text[: -len(old_ext)] + new_ext)
    return Path(text)


def _extract_braced_initializer(text, start_index):
    brace_index = text.find("{", start_index)
    if brace_index < 0:
        return "", -1
    depth = 0
    for index in range(brace_index, len(text)):
        char = text[index]
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return text[brace_index + 1 : index], index + 1
    return "", -1


def _parse_environment_table(source_root):
    source_path = source_root / ENVIRONMENT_DATA_SOURCE
    text = source_path.read_text(encoding="utf-8", errors="replace")
    table_start = text.find("gBattleEnvironmentInfo")
    table_body, _ = _extract_braced_initializer(text, table_start)
    entries = {}
    entry_order = []
    offset = 0
    designator_re = re.compile(r"\[(BATTLE_ENVIRONMENT_\w+)\]\s*=")
    while True:
        match = designator_re.search(table_body, offset)
        if match is None:
            break
        symbol = match.group(1)
        initializer, end_index = _extract_braced_initializer(table_body, match.end())
        if end_index < 0:
            break
        source_line = text.count("\n", 0, table_start + match.start()) + 1
        entries[symbol] = _parse_environment_entry(symbol, initializer, source_line)
        entry_order.append(symbol)
        offset = end_index
    return entries, entry_order


def _parse_environment_entry(symbol, initializer, source_line):
    raw_fields = {}
    for field in [
        "name",
        "naturePower",
        "secretPowerAnimation",
        "secretPowerEffect",
        "camouflageType",
        "camouflageBlend",
        "battleIntroSlide",
        "palette",
    ]:
        match = re.search(r"\.%s\s*=\s*([^,\n]+)" % re.escape(field), initializer)
        if match is not None:
            raw_fields[field] = match.group(1).strip()

    entry_asset = None
    entry_match = re.search(r"\.entry\s*=\s*ENVIRONMENT_ENTRY\((\w+)\)", initializer)
    if entry_match is not None:
        entry_asset = entry_match.group(1)

    background_asset = None
    background_match = re.search(r"\.background\s*=\s*ENVIRONMENT_BACKGROUND\((\w+)\)", initializer)
    if background_match is not None:
        background_asset = background_match.group(1)

    return {
        "symbol": symbol,
        "name_expression": raw_fields.get("name", ""),
        "nature_power": raw_fields.get("naturePower", ""),
        "secret_power_animation": raw_fields.get("secretPowerAnimation", ""),
        "secret_power_effect": raw_fields.get("secretPowerEffect", ""),
        "camouflage_type": raw_fields.get("camouflageType", ""),
        "camouflage_blend": raw_fields.get("camouflageBlend", ""),
        "battle_intro_slide": raw_fields.get("battleIntroSlide", ""),
        "background_asset": background_asset,
        "entry_asset": entry_asset,
        "palette_symbol": raw_fields.get("palette", ""),
        "source": {
            "file": to_project_path(ENVIRONMENT_DATA_SOURCE),
            "line": source_line,
            "symbol": "gBattleEnvironmentInfo[%s]" % symbol,
        },
    }


def _parse_map_scene_mapping(source_root, map_scene_constants, environment_constants):
    source_path = source_root / ENVIRONMENT_DATA_SOURCE
    text = source_path.read_text(encoding="utf-8", errors="replace")
    mapping_start = text.find("sMapBattleSceneMapping")
    mapping_body, _ = _extract_braced_initializer(text, mapping_start)
    rows = []
    for match in re.finditer(r"\{\s*(MAP_BATTLE_SCENE_\w+)\s*,\s*(BATTLE_ENVIRONMENT_\w+)\s*\}", mapping_body):
        map_scene, environment = match.groups()
        source_line = text.count("\n", 0, mapping_start + match.start()) + 1
        rows.append({
            "map_scene": map_scene,
            "map_scene_id": int(map_scene_constants.get(map_scene, {}).get("value", -1)),
            "battle_environment": environment,
            "battle_environment_id": int(environment_constants.get(environment, {}).get("value", -1)),
            "source": {
                "file": to_project_path(ENVIRONMENT_DATA_SOURCE),
                "line": source_line,
                "symbol": "sMapBattleSceneMapping",
            },
        })
    return rows


def _read_jasc_palette(path):
    lines = [
        line.strip()
        for line in path.read_text(encoding="utf-8", errors="replace").splitlines()
        if line.strip()
    ]
    colors = []
    if len(lines) >= 3 and lines[0] == "JASC-PAL":
        try:
            expected_count = int(lines[2])
        except ValueError:
            expected_count = 0
        color_lines = lines[3 : 3 + expected_count] if expected_count > 0 else lines[3:]
    else:
        color_lines = lines
    for line in color_lines:
        parts = line.split()
        if len(parts) != 3:
            continue
        try:
            colors.append((int(parts[0]), int(parts[1]), int(parts[2]), 255))
        except ValueError:
            continue
    return colors


def _read_png_palette(path):
    from PIL import Image

    image = Image.open(path)
    try:
        if image.mode != "P":
            return []
        raw_palette = image.getpalette() or []
        colors = []
        for index in range(0, len(raw_palette), 3):
            colors.append((
                int(raw_palette[index]),
                int(raw_palette[index + 1]),
                int(raw_palette[index + 2]),
                255,
            ))
        return colors
    finally:
        image.close()


def _palette_metadata(symbol, definitions, source_root):
    definition = definitions.get(symbol, {})
    if not definition:
        return {}
    source_palette = source_root / definition["source_asset_path"]
    colors = _read_jasc_palette(source_palette) if source_palette.exists() else []
    return {
        "source_symbol": symbol,
        "source_binary_path": definition.get("source_binary_path", ""),
        "source_asset_path": definition.get("source_asset_path", ""),
        "color_count": len(colors),
        "palette_bank_count": int(math.ceil(len(colors) / 16.0)) if colors else 0,
        "colors": [
            {"r": int(r), "g": int(g), "b": int(b)}
            for r, g, b, _a in colors
        ],
        "source": {
            "file": definition.get("source_file", ""),
            "line": int(definition.get("source_line", 0)),
            "symbol": symbol,
        },
    }


def _tilemap_dimensions(entry_count):
    if entry_count == 2048:
        return 64, 32
    if entry_count == 1024:
        return 32, 32
    if entry_count % 64 == 0:
        return 64, entry_count // 64
    if entry_count % 32 == 0:
        return 32, entry_count // 32
    side = int(math.sqrt(entry_count))
    if side * side == entry_count:
        return side, side
    return entry_count, 1


def _read_tilemap(path):
    data = path.read_bytes()
    entry_count = len(data) // 2
    entries = list(struct.unpack("<%dH" % entry_count, data[: entry_count * 2]))
    width, height = _tilemap_dimensions(entry_count)
    return entries, width, height


def _make_slug(symbol):
    return symbol.replace("BATTLE_ENVIRONMENT_", "").lower()


def _definition_symbols_for_asset(kind, asset_name):
    if kind == "background":
        return (
            "gBattleEnvironmentTiles_%s" % asset_name,
            "gBattleEnvironmentTilemap_%s" % asset_name,
        )
    return (
        "gBattleEnvironmentAnimTiles_%s" % asset_name,
        "gBattleEnvironmentAnimTilemap_%s" % asset_name,
    )


def _compose_layer(kind, asset_name, palette_symbol, definitions, source_root, output_dir, output_name):
    from PIL import Image

    tiles_symbol, tilemap_symbol = _definition_symbols_for_asset(kind, asset_name)
    tiles_definition = definitions.get(tiles_symbol, {})
    tilemap_definition = definitions.get(tilemap_symbol, {})
    palette_definition = definitions.get(palette_symbol, {})
    missing = [
        label
        for label, definition in [
            (tiles_symbol, tiles_definition),
            (tilemap_symbol, tilemap_definition),
            (palette_symbol, palette_definition),
        ]
        if not definition
    ]
    if missing:
        return {}, missing

    tiles_source_path = source_root / tiles_definition["source_asset_path"]
    tilemap_source_path = source_root / tilemap_definition["source_asset_path"]
    palette_source_path = source_root / palette_definition["source_asset_path"]
    if not tiles_source_path.exists():
        missing.append(to_project_path(tiles_source_path))
    if not tilemap_source_path.exists():
        missing.append(to_project_path(tilemap_source_path))
    if not palette_source_path.exists():
        missing.append(to_project_path(palette_source_path))
    if missing:
        return {}, missing

    palette_colors = _read_jasc_palette(palette_source_path)
    image_palette = _read_png_palette(tiles_source_path)
    if not palette_colors:
        palette_colors = image_palette

    tilemap_entries, width_tiles, height_tiles = _read_tilemap(tilemap_source_path)
    tiles_image = Image.open(tiles_source_path)
    output_image = Image.new("RGBA", (width_tiles * TILE_SIZE, height_tiles * TILE_SIZE), (0, 0, 0, 0))
    tile_sheet_size = {"w": int(tiles_image.width), "h": int(tiles_image.height)}
    tile_sheet_width = tiles_image.width // TILE_SIZE
    tile_count = (tiles_image.width // TILE_SIZE) * (tiles_image.height // TILE_SIZE)
    missing_tiles = 0
    transparent_zero = kind == "entry"

    try:
        tiles_pixels = tiles_image.load()
        out_pixels = output_image.load()
        for entry_index, entry in enumerate(tilemap_entries):
            tile_id = entry & 0x03FF
            hflip = bool(entry & 0x0400)
            vflip = bool(entry & 0x0800)
            palette_bank = (entry >> 12) & 0x0F
            if tile_id >= tile_count:
                missing_tiles += 1
                continue
            source_tile_x = (tile_id % tile_sheet_width) * TILE_SIZE
            source_tile_y = (tile_id // tile_sheet_width) * TILE_SIZE
            dest_tile_x = (entry_index % width_tiles) * TILE_SIZE
            dest_tile_y = (entry_index // width_tiles) * TILE_SIZE
            for y in range(TILE_SIZE):
                sample_y = TILE_SIZE - 1 - y if vflip else y
                for x in range(TILE_SIZE):
                    sample_x = TILE_SIZE - 1 - x if hflip else x
                    palette_index = int(tiles_pixels[source_tile_x + sample_x, source_tile_y + sample_y])
                    if transparent_zero and palette_index == 0:
                        out_pixels[dest_tile_x + x, dest_tile_y + y] = (0, 0, 0, 0)
                        continue
                    color_index = palette_bank * 16 + (palette_index & 0x0F)
                    if color_index >= len(palette_colors):
                        color_index = palette_index if palette_index < len(palette_colors) else 0
                    out_pixels[dest_tile_x + x, dest_tile_y + y] = palette_colors[color_index]

        output_dir.mkdir(parents=True, exist_ok=True)
        output_path = output_dir / output_name
        output_image.save(output_path)
    finally:
        tiles_image.close()
        output_image.close()

    return {
        "kind": kind,
        "asset_name": asset_name,
        "image": "res://%s" % to_project_path(output_path),
        "image_project_path": to_project_path(output_path),
        "size": {"w": width_tiles * TILE_SIZE, "h": height_tiles * TILE_SIZE},
        "tilemap": {
            "source_symbol": tilemap_symbol,
            "source_binary_path": tilemap_definition.get("source_binary_path", ""),
            "source_asset_path": tilemap_definition.get("source_asset_path", ""),
            "tile_count": len(tilemap_entries),
            "width_tiles": width_tiles,
            "height_tiles": height_tiles,
            "tile_size": TILE_SIZE,
            "missing_tile_count": missing_tiles,
        },
        "tiles": {
            "source_symbol": tiles_symbol,
            "source_binary_path": tiles_definition.get("source_binary_path", ""),
            "source_asset_path": tiles_definition.get("source_asset_path", ""),
            "tile_sheet_size": tile_sheet_size,
        },
        "palette_source_symbol": palette_symbol,
        "transparent_zero": transparent_zero,
        "conversion": "palette_baked_png_from_source_tilemap",
        "source": {
            "graphics_file": to_project_path(ENVIRONMENT_GRAPHICS_SOURCE),
            "tiles_symbol": tiles_symbol,
            "tilemap_symbol": tilemap_symbol,
            "palette_symbol": palette_symbol,
        },
    }, []


def _compose_layer_safe(kind, asset_name, palette_symbol, definitions, source_root, output_dir, output_name):
    try:
        return _compose_layer(kind, asset_name, palette_symbol, definitions, source_root, output_dir, output_name)
    except Exception as exc:
        return {}, ["%s:%s:%s" % (kind, asset_name, exc)]


def _build_selection_rules(map_scene_mapping):
    return {
        "base_environment_source": {
            "function": "BattleSetup_GetEnvironmentId",
            "source": {"file": to_project_path(BATTLE_SETUP_SOURCE)},
            "rules": [
                "Tall grass -> BATTLE_ENVIRONMENT_GRASS.",
                "Long grass -> BATTLE_ENVIRONMENT_LONG_GRASS.",
                "Sand/deep sand, Route 113, or saved sandstorm weather -> BATTLE_ENVIRONMENT_SAND.",
                "Underwater maps -> BATTLE_ENVIRONMENT_UNDERWATER.",
                "Ocean route surfable water -> BATTLE_ENVIRONMENT_WATER; non-water ocean route -> BATTLE_ENVIRONMENT_PLAIN.",
                "Underground maps use BUILDING for indoor encounter, POND for surfable/underwater behavior, otherwise CAVE.",
                "Indoor and secret-base map types -> BATTLE_ENVIRONMENT_BUILDING.",
                "Deep/ocean water -> WATER; ordinary surfable/underwater/bridge-over-water outside ocean -> POND.",
                "Mountain tile behavior -> BATTLE_ENVIRONMENT_MOUNTAIN.",
                "Fallback -> BATTLE_ENVIRONMENT_PLAIN.",
            ],
        },
        "override_source": {
            "function": "GetBattleEnvironmentOverride",
            "source": {"file": to_project_path(BATTLE_BG_SOURCE)},
            "rules": [
                "Forced test-runner environment can override when background tileset/tilemap is present.",
                "Battle Frontier, link, recorded-link, and e-Reader trainer contexts use BATTLE_ENVIRONMENT_FRONTIER.",
                "Groudon, Kyogre, and Rayquaza wild battle species use their special environments.",
                "Trainer class LEADER -> BATTLE_ENVIRONMENT_LEADER; trainer class CHAMPION -> BATTLE_ENVIRONMENT_CHAMPION.",
                "MAP_BATTLE_SCENE_NORMAL keeps the base gBattleEnvironment.",
                "Other map battle scenes use sMapBattleSceneMapping and fall back to PLAIN if unmapped.",
            ],
        },
        "map_scene_mapping": map_scene_mapping,
        "runtime_boundary": {
            "status": "metadata_only",
            "detail": "B7.3 exports source-backed environment data/assets only. Runtime battle background selection and presentation playback remain pending.",
        },
        "audio": {
            "status": "metadata_only",
            "detail": "Audio playback is intentionally out of scope for this slice.",
        },
    }


def _environment_record(symbol, numeric_id, source_record, definitions, source_root, output_asset_root):
    slug = _make_slug(symbol)
    palette_symbol = source_record.get("palette_symbol", "")
    output_dir = output_asset_root / ASSET_OUTPUT_DIR / slug
    missing_assets = []
    background = {}
    entry = {}
    if source_record.get("background_asset") and palette_symbol:
        background, missing = _compose_layer_safe(
            "background",
            source_record["background_asset"],
            palette_symbol,
            definitions,
            source_root,
            output_dir,
            "background.png",
        )
        missing_assets.extend(missing)
    if source_record.get("entry_asset") and palette_symbol:
        entry, missing = _compose_layer_safe(
            "entry",
            source_record["entry_asset"],
            palette_symbol,
            definitions,
            source_root,
            output_dir,
            "entry.png",
        )
        missing_assets.extend(missing)

    palette = _palette_metadata(palette_symbol, definitions, source_root) if palette_symbol else {}
    asset_status = "first_pass" if background and palette else "unsupported"
    entry_status = "first_pass" if entry else ("unsupported" if source_record.get("entry_asset") else "not_applicable")
    unsupported = []
    if asset_status != "first_pass":
        unsupported.append("battle_environment_asset_pending")
    unsupported.append("battle_environment_runtime_pending")

    coverage = {
        "asset_status": asset_status,
        "background_status": "first_pass" if background else "unsupported",
        "entry_status": entry_status,
        "palette_status": "metadata_only" if palette else "unsupported",
        "selection_status": "metadata_only",
        "runtime_status": "unsupported",
        "audio_status": "metadata_only",
    }
    return {
        "symbol": symbol,
        "numeric_id": int(numeric_id),
        "slug": slug,
        "name_expression": source_record.get("name_expression", ""),
        "nature_power": source_record.get("nature_power", ""),
        "secret_power_animation": source_record.get("secret_power_animation", ""),
        "secret_power_effect": source_record.get("secret_power_effect", ""),
        "camouflage_type": source_record.get("camouflage_type", ""),
        "camouflage_blend": source_record.get("camouflage_blend", ""),
        "battle_intro_slide": source_record.get("battle_intro_slide", ""),
        "source_assets": {
            "background_asset": source_record.get("background_asset"),
            "entry_asset": source_record.get("entry_asset"),
            "palette_symbol": palette_symbol,
        },
        "background": background,
        "entry": entry,
        "palette": palette,
        "coverage": coverage,
        "unsupported": unsupported,
        "warnings": missing_assets,
        "source": source_record.get("source", {}),
    }


def export_battle_environments(source_root, output_data_root, output_asset_root):
    environment_constants, environment_order = _parse_enum_constants(
        source_root / BATTLE_CONSTANTS_SOURCE,
        "enum BattleEnvironments",
        "BATTLE_ENVIRONMENT_",
    )
    if environment_order and environment_order[-1] == "BATTLE_ENVIRONMENT_COUNT":
        environment_order = environment_order[:-1]
    map_scene_constants, _map_scene_order = _parse_enum_constants(
        source_root / MAP_TYPES_SOURCE,
        "enum MapBattleScene",
        "MAP_BATTLE_SCENE_",
    )
    graphics_definitions = _parse_graphics_definitions(source_root)
    environment_table, source_order = _parse_environment_table(source_root)
    map_scene_mapping = _parse_map_scene_mapping(source_root, map_scene_constants, environment_constants)

    environments = {}
    environment_asset_order = []
    for symbol in environment_order:
        source_record = environment_table.get(symbol, {"symbol": symbol, "source": {}})
        numeric_id = environment_constants.get(symbol, {}).get("value", len(environment_asset_order))
        record = _environment_record(symbol, numeric_id, source_record, graphics_definitions, source_root, output_asset_root)
        environments[symbol] = record
        environment_asset_order.append(symbol)

    stats = {
        "environment_count": len(environment_asset_order),
        "source_table_environment_count": len(source_order),
        "graphics_definition_count": len(graphics_definitions),
        "background_texture_count": sum(1 for row in environments.values() if row.get("background")),
        "entry_texture_count": sum(1 for row in environments.values() if row.get("entry")),
        "palette_metadata_count": sum(1 for row in environments.values() if row.get("palette")),
        "first_pass_asset_environment_count": sum(
            1 for row in environments.values()
            if row.get("coverage", {}).get("asset_status") == "first_pass"
        ),
        "unsupported_asset_environment_count": sum(
            1 for row in environments.values()
            if row.get("coverage", {}).get("asset_status") != "first_pass"
        ),
        "map_scene_mapping_count": len(map_scene_mapping),
        "warning_count": sum(len(row.get("warnings", [])) for row in environments.values()),
    }
    output_path = output_data_root / "battle" / "environments.json"
    data = {
        "schema_version": 1,
        "generated_by": "tools/importer/export_battle_environments.py",
        "source_files": [
            to_project_path(ENVIRONMENT_GRAPHICS_SOURCE),
            to_project_path(ENVIRONMENT_DATA_SOURCE),
            to_project_path(BATTLE_CONSTANTS_SOURCE),
            to_project_path(MAP_TYPES_SOURCE),
            to_project_path(BATTLE_SETUP_SOURCE),
            to_project_path(BATTLE_BG_SOURCE),
        ],
        "rendering_notes": {
            "gba_hardware_constraints": "decoded_at_import_time",
            "godot_runtime_asset_model": "palette-baked PNG textures plus source metadata",
            "visible_viewport": VISIBLE_VIEWPORT,
            "background_full_tilemap_note": "Source BG3 environment maps are exported at their full 64x32 tilemap size when present; presentation should crop/scroll to the 240x160 battle viewport.",
            "entry_overlay_note": "Entry overlays use palette index 0 transparency in the generated PNG.",
            "audio_status": "metadata_only",
        },
        "gba_bg_templates": {
            "entry": {"bg": 1, "charBaseIndex": 1, "mapBaseIndex": 28, "screenSize": 2, "priority": 0},
            "background": {"bg": 3, "charBaseIndex": 2, "mapBaseIndex": 26, "screenSize": 1, "priority": 3},
        },
        "selection_rules": _build_selection_rules(map_scene_mapping),
        "environment_order": environment_asset_order,
        "environments": environments,
        "map_scene_mapping": map_scene_mapping,
        "stats": stats,
    }
    write_json(output_path, data)
    return output_path, data


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, help="JSON config with source and output roots.")
    parser.add_argument("--source", type=Path, help="pokeemerald-expansion source root.")
    parser.add_argument("--output-data-root", type=Path, help="Generated data root.")
    parser.add_argument("--output-asset-root", type=Path, help="Project asset output root.")
    args = parser.parse_args(argv)

    config = load_config(args.config)
    source_root = args.source or Path(config.get("source_root", ""))
    output_data_root = args.output_data_root or Path(config.get("generated_data_root", "data/generated"))
    output_asset_root = args.output_asset_root or Path(config.get("generated_asset_root", "assets/generated"))

    output_path, data = export_battle_environments(source_root, output_data_root, output_asset_root)
    manifest_entry = {
        "category": ASSET_CATEGORY,
        "path": to_project_path(output_path),
        "environment_count": int(data["stats"]["environment_count"]),
        "background_texture_count": int(data["stats"]["background_texture_count"]),
        "entry_texture_count": int(data["stats"]["entry_texture_count"]),
    }
    write_manifest(
        output_data_root / "import_manifest.json",
        exported_battle=[manifest_entry],
        generator="tools/importer/export_battle_environments.py",
    )
    print(json.dumps({
        "exported": manifest_entry,
        "stats": data["stats"],
    }, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
