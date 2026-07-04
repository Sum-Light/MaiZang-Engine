#!/usr/bin/env python3
"""Export battle transition metadata and first-pass PNG assets."""

import argparse
import json
import re
import sys
from pathlib import Path

from export_map import to_project_path, write_json, write_manifest
from source_probe import load_config


BATTLE_TRANSITION_HEADER = Path("include/battle_transition.h")
BATTLE_TRANSITION_SOURCE = Path("src/battle_transition.c")
BATTLE_TRANSITION_FRONTIER_HEADER = Path("include/battle_transition_frontier.h")
BATTLE_TRANSITION_FRONTIER_SOURCE = Path("src/battle_transition_frontier.c")
BATTLE_SETUP_SOURCE = Path("src/battle_setup.c")
BATTLE_TRANSITION_ASSET_DIR = Path("graphics/battle_transitions")
FIELD_POKEBALL_PALETTE = Path("graphics/field_effects/palettes/pokeball.pal")
ASSET_CATEGORY = "transitions"
ASSET_OUTPUT_DIR = "battle_transitions"

BINARY_ASSET_EXTENSIONS = [
    (".4bpp.smol", ".png"),
    (".4bpp.lz", ".png"),
    (".4bpp", ".png"),
    (".bin.smolTM", ".bin"),
    (".bin.lz", ".bin"),
    (".gbapal", ".pal"),
]

TRANSITION_ASSET_HINTS = {
    "B_TRANSITION_BLUR": [],
    "B_TRANSITION_SWIRL": [],
    "B_TRANSITION_SHUFFLE": [],
    "B_TRANSITION_BIG_POKEBALL": [
        "graphics/battle_transitions/big_pokeball.png",
        "graphics/battle_transitions/big_pokeball_map.bin",
    ],
    "B_TRANSITION_POKEBALLS_TRAIL": [
        "graphics/battle_transitions/pokeball_trail.png",
        "graphics/battle_transitions/pokeball.png",
        "graphics/field_effects/palettes/pokeball.pal",
    ],
    "B_TRANSITION_CLOCKWISE_WIPE": [],
    "B_TRANSITION_RIPPLE": [],
    "B_TRANSITION_WAVE": [],
    "B_TRANSITION_SLICE": [],
    "B_TRANSITION_WHITE_BARS_FADE": [],
    "B_TRANSITION_GRID_SQUARES": [],
    "B_TRANSITION_ANGLED_WIPES": [],
    "B_TRANSITION_MUGSHOT": [
        "graphics/battle_transitions/elite_four_bg.png",
        "graphics/battle_transitions/elite_four_bg_map.bin",
        "graphics/battle_transitions/purple_bg.pal",
        "graphics/battle_transitions/green_bg.pal",
        "graphics/battle_transitions/pink_bg.pal",
        "graphics/battle_transitions/blue_bg.pal",
        "graphics/battle_transitions/yellow_bg.pal",
        "graphics/battle_transitions/brendan_bg.pal",
        "graphics/battle_transitions/may_bg.pal",
    ],
    "B_TRANSITION_AQUA": [
        "graphics/battle_transitions/team_aqua.png",
        "graphics/battle_transitions/team_aqua.bin",
        "graphics/battle_transitions/evil_team.pal",
    ],
    "B_TRANSITION_MAGMA": [
        "graphics/battle_transitions/team_magma.png",
        "graphics/battle_transitions/team_magma.bin",
        "graphics/battle_transitions/evil_team.pal",
    ],
    "B_TRANSITION_REGICE": [
        "graphics/battle_transitions/regis.png",
        "graphics/battle_transitions/regice.bin",
        "graphics/battle_transitions/regice.pal",
    ],
    "B_TRANSITION_REGISTEEL": [
        "graphics/battle_transitions/regis.png",
        "graphics/battle_transitions/registeel.bin",
        "graphics/battle_transitions/registeel.pal",
    ],
    "B_TRANSITION_REGIROCK": [
        "graphics/battle_transitions/regis.png",
        "graphics/battle_transitions/regirock.bin",
        "graphics/battle_transitions/regirock.pal",
    ],
    "B_TRANSITION_KYOGRE": [
        "graphics/battle_transitions/kyogre.png",
        "graphics/battle_transitions/kyogre.bin",
        "graphics/battle_transitions/kyogre_pt1.pal",
        "graphics/battle_transitions/kyogre_pt2.pal",
    ],
    "B_TRANSITION_GROUDON": [
        "graphics/battle_transitions/groudon.png",
        "graphics/battle_transitions/groudon.bin",
        "graphics/battle_transitions/groudon_pt1.pal",
        "graphics/battle_transitions/groudon_pt2.pal",
    ],
    "B_TRANSITION_RAYQUAZA": [
        "graphics/battle_transitions/rayquaza.png",
        "graphics/battle_transitions/rayquaza.bin",
        "graphics/battle_transitions/rayquaza.pal",
    ],
    "B_TRANSITION_SHRED_SPLIT": ["graphics/battle_transitions/shrinking_box.png"],
    "B_TRANSITION_BLACKHOLE": [],
    "B_TRANSITION_BLACKHOLE_PULSATE": [],
    "B_TRANSITION_RECTANGULAR_SPIRAL": [],
    "B_TRANSITION_FRONTIER_LOGO_WIGGLE": [
        "graphics/battle_transitions/frontier_logo.png",
        "graphics/battle_transitions/frontier_logo.bin",
    ],
    "B_TRANSITION_FRONTIER_LOGO_WAVE": [
        "graphics/battle_transitions/frontier_logo.png",
        "graphics/battle_transitions/frontier_logo.bin",
    ],
    "B_TRANSITION_FRONTIER_SQUARES": [
        "graphics/battle_transitions/frontier_squares_1.png",
        "graphics/battle_transitions/frontier_squares_2.png",
        "graphics/battle_transitions/frontier_squares_3.png",
        "graphics/battle_transitions/frontier_squares_4.png",
        "graphics/battle_transitions/frontier_squares_blanktiles.png",
        "graphics/battle_transitions/frontier_squares.bin",
    ],
    "B_TRANSITION_FRONTIER_SQUARES_SCROLL": [
        "graphics/battle_transitions/frontier_squares_1.png",
        "graphics/battle_transitions/frontier_squares_2.png",
        "graphics/battle_transitions/frontier_squares_3.png",
        "graphics/battle_transitions/frontier_squares_4.png",
        "graphics/battle_transitions/frontier_squares_blanktiles.png",
        "graphics/battle_transitions/frontier_squares.bin",
    ],
    "B_TRANSITION_FRONTIER_SQUARES_SPIRAL": [
        "graphics/battle_transitions/frontier_squares_1.png",
        "graphics/battle_transitions/frontier_squares_2.png",
        "graphics/battle_transitions/frontier_squares_3.png",
        "graphics/battle_transitions/frontier_squares_4.png",
        "graphics/battle_transitions/frontier_squares_blanktiles.png",
        "graphics/battle_transitions/frontier_squares.bin",
    ],
}

FRONTIER_CIRCLE_ASSETS = [
    "graphics/battle_transitions/frontier_logo_center.png",
    "graphics/battle_transitions/frontier_logo_center.bin",
    "graphics/battle_transitions/frontier_logo_circles.png",
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
                "source": {"file": to_project_path(path), "line": line_no},
            }
            order.append(symbol)
            value = int(parsed_value) + 1
    return constants, order


def _source_asset_path(binary_path):
    text = to_project_path(binary_path)
    for old_ext, new_ext in BINARY_ASSET_EXTENSIONS:
        if text.endswith(old_ext):
            result = text[: -len(old_ext)] + new_ext
            if "frontier_square_" in result:
                result = result.replace("frontier_square_", "frontier_squares_")
            return Path(result)
    return Path(text)


def _parse_graphics_definitions(source_root):
    definition_re = re.compile(
        r'^\s*(?:static\s+)?const\s+\w+\s+(\w+)\[\]\s*=\s*INCBIN_\w+\("([^"]+)"\)'
    )
    definitions = {}
    for relative_path in [BATTLE_TRANSITION_SOURCE, BATTLE_TRANSITION_FRONTIER_SOURCE]:
        source_path = source_root / relative_path
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
                    "source_file": to_project_path(relative_path),
                    "source_line": line_no,
                }
    return definitions


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
            colors.append({"r": int(parts[0]), "g": int(parts[1]), "b": int(parts[2])})
        except ValueError:
            continue
    return colors


def _read_png_palette(image):
    if image.mode != "P":
        return []
    raw_palette = image.getpalette() or []
    colors = []
    for index in range(0, len(raw_palette), 3):
        colors.append({
            "r": int(raw_palette[index]),
            "g": int(raw_palette[index + 1]),
            "b": int(raw_palette[index + 2]),
        })
    return colors


def _convert_png_asset(source_path, output_path):
    from PIL import Image

    output_path.parent.mkdir(parents=True, exist_ok=True)
    image = Image.open(source_path)
    try:
        palette_colors = _read_png_palette(image)
        source_mode = image.mode
        if image.mode == "P":
            alpha = Image.new("L", image.size, 255)
            alpha.putdata([0 if pixel == 0 else 255 for pixel in image.getdata()])
            converted = image.convert("RGBA")
            converted.putalpha(alpha)
        else:
            converted = image.convert("RGBA")
        try:
            converted.save(output_path)
            return {
                "image": "res://%s" % to_project_path(output_path),
                "image_project_path": to_project_path(output_path),
                "size": {"w": int(converted.width), "h": int(converted.height)},
                "source_mode": source_mode,
                "source_palette_color_count": len(palette_colors),
                "transparent_zero": source_mode == "P",
                "conversion": "source_png_to_rgba",
            }
        finally:
            converted.close()
    finally:
        image.close()


def _asset_kind(path):
    suffix = path.suffix.lower()
    if suffix == ".png":
        return "texture"
    if suffix == ".pal":
        return "palette"
    if suffix == ".bin":
        return "tilemap_or_binary"
    return "source_asset"


def _build_asset_inventory(source_root, output_asset_root, definitions):
    asset_records = {}
    asset_order = []
    transition_dir = source_root / BATTLE_TRANSITION_ASSET_DIR
    source_assets = list(sorted(transition_dir.glob("*.png")))
    source_assets.extend(sorted(transition_dir.glob("*.pal")))
    source_assets.extend(sorted(transition_dir.glob("*.bin")))
    field_pokeball = source_root / FIELD_POKEBALL_PALETTE
    if field_pokeball.exists():
        source_assets.append(field_pokeball)

    definition_by_asset_path = {}
    for definition in definitions.values():
        definition_by_asset_path.setdefault(definition["source_asset_path"], []).append(definition)

    for source_path in source_assets:
        relative_path = to_project_path(source_path.relative_to(source_root))
        kind = _asset_kind(source_path)
        record = {
            "id": relative_path,
            "kind": kind,
            "source_asset_path": relative_path,
            "source_binary_paths": [
                definition.get("source_binary_path", "")
                for definition in definition_by_asset_path.get(relative_path, [])
            ],
            "source_symbols": [
                definition.get("symbol", "")
                for definition in definition_by_asset_path.get(relative_path, [])
            ],
        }
        if kind == "texture":
            texture_path = output_asset_root / ASSET_OUTPUT_DIR / source_path.name
            record.update(_convert_png_asset(source_path, texture_path))
            record["asset_status"] = "first_pass"
        elif kind == "palette":
            colors = _read_jasc_palette(source_path)
            record.update({
                "color_count": len(colors),
                "palette_bank_count": (len(colors) + 15) // 16 if colors else 0,
                "colors": colors,
                "asset_status": "metadata_only",
            })
        elif kind == "tilemap_or_binary":
            record.update({
                "byte_size": int(source_path.stat().st_size),
                "u16_count": int(source_path.stat().st_size // 2),
                "asset_status": "metadata_only",
            })
        asset_records[relative_path] = record
        asset_order.append(relative_path)

    return asset_records, asset_order


def _extract_initializer_block(text, marker):
    start = text.find(marker)
    if start < 0:
        return ""
    brace = text.find("{", start)
    if brace < 0:
        return ""
    depth = 0
    for index in range(brace, len(text)):
        char = text[index]
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return text[brace + 1 : index]
    return ""


def _parse_task_mapping(source_root):
    text = (source_root / BATTLE_TRANSITION_SOURCE).read_text(encoding="utf-8", errors="replace")
    body = _extract_initializer_block(text, "sTasks_Main")
    mapping = {}
    for match in re.finditer(r"\[(B_TRANSITION_\w+)\]\s*=\s*(Task_\w+)", body):
        mapping[match.group(1)] = match.group(2)
    return mapping


def _parse_transition_function_arrays(source_root):
    arrays = {}
    array_re = re.compile(
        r"static\s+const\s+TransitionStateFunc\s+(s\w+_Funcs)\[\]\s*=\s*\{(.*?)\};",
        re.S,
    )
    for relative_path in [BATTLE_TRANSITION_SOURCE, BATTLE_TRANSITION_FRONTIER_SOURCE]:
        text = (source_root / relative_path).read_text(encoding="utf-8", errors="replace")
        for match in array_re.finditer(text):
            name = match.group(1)
            body = match.group(2)
            functions = []
            for raw_line in body.splitlines():
                line = _strip_comment(raw_line).rstrip(",").strip()
                if not line:
                    continue
                functions.append(line.lstrip("&"))
            arrays[name] = {
                "name": name,
                "functions": functions,
                "source": {
                    "file": to_project_path(relative_path),
                    "line": text.count("\n", 0, match.start()) + 1,
                },
            }
    return arrays


def _func_array_for_task(task_name, function_arrays):
    if not task_name.startswith("Task_"):
        return {}
    key = "s%s_Funcs" % task_name[len("Task_") :]
    return function_arrays.get(key, {})


def _parse_transition_type_constants(source_root):
    source_path = source_root / BATTLE_SETUP_SOURCE
    constants = {}
    order = []
    text = source_path.read_text(encoding="utf-8", errors="replace")
    body = _extract_initializer_block(text, "enum TransitionType")
    value = 0
    for raw_line in body.splitlines():
        line = _strip_comment(raw_line).rstrip(",").strip()
        if not line:
            continue
        if "=" in line:
            symbol, expr = [part.strip() for part in line.split("=", 1)]
            value = int(_parse_int_expr(expr, constants, value))
        else:
            symbol = line
        constants[symbol] = {"symbol": symbol, "value": value}
        order.append(symbol)
        value += 1
    return constants, order


def _parse_two_column_transition_table(source_root, table_name, transition_type_constants):
    source_path = source_root / BATTLE_SETUP_SOURCE
    text = source_path.read_text(encoding="utf-8", errors="replace")
    body = _extract_initializer_block(text, table_name)
    rows = []
    for match in re.finditer(r"\[(TRANSITION_TYPE_\w+)\]\s*=\s*\{\s*(B_TRANSITION_\w+)\s*,\s*(B_TRANSITION_\w+)\s*\}", body):
        transition_type, lower, equal_or_higher = match.groups()
        rows.append({
            "transition_type": transition_type,
            "transition_type_id": int(transition_type_constants.get(transition_type, {}).get("value", -1)),
            "enemy_lower": lower,
            "enemy_equal_or_higher": equal_or_higher,
            "source": {"file": to_project_path(BATTLE_SETUP_SOURCE), "symbol": table_name},
        })
    return rows


def _parse_linear_transition_table(source_root, table_name):
    source_path = source_root / BATTLE_SETUP_SOURCE
    text = source_path.read_text(encoding="utf-8", errors="replace")
    body = _extract_initializer_block(text, table_name)
    transitions = re.findall(r"\b(B_TRANSITION_\w+)\b", body)
    return {
        "table": table_name,
        "transitions": transitions,
        "count": len(transitions),
        "source": {"file": to_project_path(BATTLE_SETUP_SOURCE), "symbol": table_name},
    }


def _build_selection_tables(source_root):
    transition_type_constants, transition_type_order = _parse_transition_type_constants(source_root)
    return {
        "transition_type_order": transition_type_order,
        "transition_type_constants": transition_type_constants,
        "wild": _parse_two_column_transition_table(source_root, "sBattleTransitionTable_Wild", transition_type_constants),
        "trainer": _parse_two_column_transition_table(source_root, "sBattleTransitionTable_Trainer", transition_type_constants),
        "battle_frontier": _parse_linear_transition_table(source_root, "sBattleTransitionTable_BattleFrontier"),
        "battle_pyramid": _parse_linear_transition_table(source_root, "sBattleTransitionTable_BattlePyramid"),
        "battle_dome": _parse_linear_transition_table(source_root, "sBattleTransitionTable_BattleDome"),
        "special_groups": {
            "lower_level_fixed": {
                "B_TRANSITION_GROUP_TRAINER_HILL": "B_TRANSITION_POKEBALLS_TRAIL",
                "B_TRANSITION_GROUP_SECRET_BASE": "B_TRANSITION_POKEBALLS_TRAIL",
                "B_TRANSITION_GROUP_E_READER": "B_TRANSITION_POKEBALLS_TRAIL",
            },
            "equal_or_higher_fixed": {
                "B_TRANSITION_GROUP_TRAINER_HILL": "B_TRANSITION_BIG_POKEBALL",
                "B_TRANSITION_GROUP_SECRET_BASE": "B_TRANSITION_BIG_POKEBALL",
                "B_TRANSITION_GROUP_E_READER": "B_TRANSITION_BIG_POKEBALL",
            },
            "random_tables": {
                "B_TRANSITION_GROUP_B_PYRAMID": "sBattleTransitionTable_BattlePyramid",
                "B_TRANSITION_GROUP_B_DOME": "sBattleTransitionTable_BattleDome",
                "frontier_default": "sBattleTransitionTable_BattleFrontier",
            },
            "source": {"file": to_project_path(BATTLE_SETUP_SOURCE), "function": "GetSpecialBattleTransition"},
        },
    }


def _transition_asset_paths(symbol):
    if symbol.startswith("B_TRANSITION_FRONTIER_CIRCLES_"):
        return list(FRONTIER_CIRCLE_ASSETS)
    return list(TRANSITION_ASSET_HINTS.get(symbol, []))


def _transition_record(symbol, numeric_id, constants, task_mapping, function_arrays, assets):
    main_task = task_mapping.get(symbol, "")
    function_array = _func_array_for_task(main_task, function_arrays)
    asset_paths = _transition_asset_paths(symbol)
    texture_refs = []
    palette_refs = []
    binary_refs = []
    missing_assets = []
    for path in asset_paths:
        asset = assets.get(path, {})
        if not asset:
            missing_assets.append(path)
            continue
        kind = asset.get("kind")
        if kind == "texture":
            texture_refs.append(path)
        elif kind == "palette":
            palette_refs.append(path)
        else:
            binary_refs.append(path)

    has_static_assets = bool(asset_paths)
    asset_status = "first_pass" if texture_refs else ("metadata_only" if not has_static_assets and not missing_assets else "partial")
    unsupported = ["battle_transition_runtime_pending", "battle_audio_playback_pending"]
    if missing_assets:
        unsupported.append("battle_transition_asset_pending")
    return {
        "symbol": symbol,
        "numeric_id": int(numeric_id),
        "main_task": main_task,
        "intro_task": "Task_Intro",
        "function_array": function_array.get("name", ""),
        "function_sequence": function_array.get("functions", []),
        "texture_refs": texture_refs,
        "palette_refs": palette_refs,
        "binary_refs": binary_refs,
        "missing_asset_refs": missing_assets,
        "coverage": {
            "asset_status": asset_status,
            "texture_status": "first_pass" if texture_refs else ("not_required" if not has_static_assets else "unsupported"),
            "task_metadata_status": "metadata_only" if main_task else "unsupported",
            "selection_status": "metadata_only",
            "runtime_status": "unsupported",
            "audio_status": "metadata_only",
        },
        "unsupported": unsupported,
        "source": constants.get(symbol, {}).get("source", {}),
    }


def export_battle_transitions(source_root, output_data_root, output_asset_root):
    transition_constants, transition_order = _parse_enum_constants(
        source_root / BATTLE_TRANSITION_HEADER,
        "enum BattleTransition",
        "B_TRANSITION_",
    )
    if transition_order and transition_order[-1] == "B_TRANSITION_COUNT":
        transition_order = transition_order[:-1]
    group_constants, group_order = _parse_enum_constants(
        source_root / BATTLE_TRANSITION_HEADER,
        "enum BattleTransitionGroup",
        "B_TRANSITION_GROUP_",
    )
    definitions = _parse_graphics_definitions(source_root)
    assets, asset_order = _build_asset_inventory(source_root, output_asset_root, definitions)
    task_mapping = _parse_task_mapping(source_root)
    function_arrays = _parse_transition_function_arrays(source_root)
    selection_tables = _build_selection_tables(source_root)

    transitions = {}
    for symbol in transition_order:
        numeric_id = transition_constants.get(symbol, {}).get("value", len(transitions))
        transitions[symbol] = _transition_record(
            symbol,
            numeric_id,
            transition_constants,
            task_mapping,
            function_arrays,
            assets,
        )

    stats = {
        "transition_count": len(transition_order),
        "transition_group_count": len(group_order),
        "graphics_definition_count": len(definitions),
        "source_png_asset_count": sum(1 for record in assets.values() if record.get("kind") == "texture"),
        "source_palette_asset_count": sum(1 for record in assets.values() if record.get("kind") == "palette"),
        "source_binary_asset_count": sum(1 for record in assets.values() if record.get("kind") == "tilemap_or_binary"),
        "texture_count": sum(1 for record in assets.values() if record.get("kind") == "texture" and record.get("asset_status") == "first_pass"),
        "transition_with_texture_count": sum(1 for record in transitions.values() if record.get("texture_refs")),
        "transition_without_static_texture_count": sum(1 for record in transitions.values() if not record.get("texture_refs")),
        "wild_transition_table_count": len(selection_tables["wild"]),
        "trainer_transition_table_count": len(selection_tables["trainer"]),
        "battle_frontier_transition_count": int(selection_tables["battle_frontier"].get("count", 0)),
        "battle_pyramid_transition_count": int(selection_tables["battle_pyramid"].get("count", 0)),
        "battle_dome_transition_count": int(selection_tables["battle_dome"].get("count", 0)),
        "missing_asset_ref_count": sum(len(record.get("missing_asset_refs", [])) for record in transitions.values()),
    }
    data = {
        "schema_version": 1,
        "generated_by": "tools/importer/export_battle_transitions.py",
        "source_files": [
            to_project_path(BATTLE_TRANSITION_HEADER),
            to_project_path(BATTLE_TRANSITION_SOURCE),
            to_project_path(BATTLE_TRANSITION_FRONTIER_HEADER),
            to_project_path(BATTLE_TRANSITION_FRONTIER_SOURCE),
            to_project_path(BATTLE_SETUP_SOURCE),
        ],
        "rendering_notes": {
            "gba_hardware_constraints": "decoded_at_import_time",
            "godot_runtime_asset_model": "RGBA PNG textures plus source task/table metadata",
            "runtime_status": "unsupported",
            "audio_status": "metadata_only",
            "detail": "Palette fades, HBlank/VBlank effects, window masks, scanline offsets, affine transforms, and transition task playback remain future Godot-native presentation work.",
        },
        "transition_order": transition_order,
        "transitions": transitions,
        "transition_group_order": group_order,
        "transition_groups": group_constants,
        "selection_tables": selection_tables,
        "asset_order": asset_order,
        "assets": assets,
        "graphics_definitions": definitions,
        "stats": stats,
    }
    output_path = output_data_root / "battle" / "transitions.json"
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

    output_path, data = export_battle_transitions(source_root, output_data_root, output_asset_root)
    manifest_entry = {
        "category": ASSET_CATEGORY,
        "path": to_project_path(output_path),
        "transition_count": int(data["stats"]["transition_count"]),
        "texture_count": int(data["stats"]["texture_count"]),
        "runtime_status": "pending_presentation",
        "audio_status": "metadata_only",
    }
    write_manifest(
        output_data_root / "import_manifest.json",
        exported_battle=[manifest_entry],
        generator="tools/importer/export_battle_transitions.py",
    )
    print(json.dumps({"exported": manifest_entry, "stats": data["stats"]}, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
