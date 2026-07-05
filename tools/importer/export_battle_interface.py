#!/usr/bin/env python3
"""Export battle interface HUD metadata and Godot-friendly PNG assets."""

import argparse
import json
import math
import re
import struct
import sys
from pathlib import Path

from export_map import to_project_path, write_json, write_manifest
from source_probe import load_config


ASSET_CATEGORY = "interface"
ASSET_OUTPUT_DIR = "battle_interface"
COMPOSITE_OUTPUT_DIR = "battle_interface/composites"
FONT_ATLAS_OUTPUT_DIR = "battle_fonts"
VISIBLE_VIEWPORT = {"w": 240, "h": 160}
TILE_SIZE = 8
FONT_GLYPH_CELL_SIZE = 16

BATTLE_INTERFACE_DIR = Path("graphics/battle_interface")
FONT_GRAPHICS_DIR = Path("graphics/fonts")
GRAPHICS_SOURCE = Path("src/graphics.c")
BATTLE_BG_SOURCE = Path("src/battle_bg.c")
BATTLE_MESSAGE_SOURCE = Path("src/battle_message.c")
TEXT_SOURCE = Path("src/text.c")
CHINESE_TEXT_SOURCE = Path("src/chinese_text.c")
FONTS_SOURCE = Path("src/fonts.c")
TEXT_HEADER_SOURCE = Path("include/text.h")
BATTLE_INTERFACE_SOURCE = Path("src/battle_interface.c")
BATTLE_SCRIPT_COMMANDS_SOURCE = Path("src/battle_script_commands.c")
GIMMICKS_SOURCE = Path("src/data/graphics/gimmicks.h")
BATTLE_CONFIG_SOURCE = Path("include/config/battle.h")
TEXT_CONFIG_SOURCE = Path("include/config/text.h")
GLOBAL_CONSTANTS_SOURCE = Path("include/constants/global.h")

BINARY_ASSET_EXTENSIONS = [
    (".4bpp.smol", ".png"),
    (".4bpp.lz", ".png"),
    (".4bpp", ".png"),
    (".bin.smolTM", ".bin"),
    (".bin.lz", ".bin"),
    (".gbapal", ".pal"),
]

HEALTHBOX_ELEMENT_TEXTURES = [
    "hpbar",
    "expbar",
    "status",
    "misc",
    "hpbar_anim",
    "misc_frameend",
    "ball_display",
    "ball_caught_indicator",
    "status2",
    "status3",
    "status4",
    "healthbox_doubles_frameend",
    "healthbox_doubles_frameend_bar",
]

HEALTHBOX_FRAME_TEXTURES = [
    "healthbox_singles_player",
    "healthbox_singles_opponent",
    "healthbox_doubles_player",
    "healthbox_doubles_opponent",
    "healthbox_safari",
]

GIMMICK_TRIGGER_TEXTURES = [
    "mega_trigger",
    "z_move_trigger",
    "burst_trigger",
    "dynamax_trigger",
    "tera_trigger",
]

GIMMICK_INDICATOR_TEXTURES = [
    "mega_indicator",
    "alpha_indicator",
    "omega_indicator",
    "dynamax_indicator",
    "normal_indicator",
    "fighting_indicator",
    "flying_indicator",
    "poison_indicator",
    "ground_indicator",
    "rock_indicator",
    "bug_indicator",
    "ghost_indicator",
    "steel_indicator",
    "fire_indicator",
    "water_indicator",
    "grass_indicator",
    "electric_indicator",
    "psychic_indicator",
    "ice_indicator",
    "dragon_indicator",
    "dark_indicator",
    "fairy_indicator",
    "stellar_indicator",
]

ROLE_OVERRIDES = {
    "ability_pop_up": ("ability_popup", "ability_popup_frame"),
    "ball_caught_indicator": ("party_summary", "caught_ball_icon"),
    "ball_display": ("party_summary", "party_ball_icon"),
    "ball_status_bar": ("party_summary", "party_status_bar"),
    "enemy_mon_shadow": ("enemy_shadow", "small_shadow"),
    "enemy_mon_shadows_sized": ("enemy_shadow", "sized_shadow_sheet"),
    "expbar": ("healthbox_element", "exp_bar"),
    "healthbox_doubles_frameend": ("healthbox_element", "doubles_frame_end"),
    "healthbox_doubles_frameend_bar": ("healthbox_element", "doubles_frame_end_bar"),
    "healthbox_doubles_opponent": ("healthbox_frame", "doubles_opponent_frame"),
    "healthbox_doubles_player": ("healthbox_frame", "doubles_player_frame"),
    "healthbox_safari": ("healthbox_frame", "safari_frame"),
    "healthbox_singles_opponent": ("healthbox_frame", "singles_opponent_frame"),
    "healthbox_singles_player": ("healthbox_frame", "singles_player_frame"),
    "hpbar": ("healthbox_element", "hp_bar"),
    "hpbar_anim": ("healthbox_element", "hp_bar_animation"),
    "hpbar_anim_unused": ("healthbox_element", "hp_bar_animation_unused"),
    "hpbar_unused": ("healthbox_element", "hp_bar_unused"),
    "last_used_ball_l": ("last_used_ball", "left_static_window"),
    "last_used_ball_l_cycle": ("last_used_ball", "left_cycle_window"),
    "last_used_ball_r": ("last_used_ball", "right_static_window"),
    "last_used_ball_r_cycle": ("last_used_ball", "right_cycle_window"),
    "level_up_banner": ("level_up", "level_up_banner"),
    "misc": ("healthbox_element", "misc_healthbox_tiles"),
    "misc_frameend": ("healthbox_element", "frame_end"),
    "move_info_window_l": ("move_info", "left_window"),
    "move_info_window_r": ("move_info", "right_window"),
    "numbers1": ("healthbox_text", "numbers_sheet_1"),
    "numbers2": ("healthbox_text", "numbers_sheet_2"),
    "status": ("healthbox_element", "status_sheet_player"),
    "status2": ("healthbox_element", "status_sheet_partner_1"),
    "status3": ("healthbox_element", "status_sheet_partner_2"),
    "status4": ("healthbox_element", "status_sheet_partner_3"),
    "textbox": ("textbox", "textbox_tiles"),
    "unused_status_summary": ("party_summary", "unused_status_summary"),
    "unused_window": ("window", "unused_window_1"),
    "unused_window2": ("window", "unused_window_2"),
    "unused_window2bar": ("window", "unused_window_2_bar"),
    "unused_window3": ("window", "unused_window_3"),
    "unused_window4": ("window", "unused_window_4"),
}

TEXTBOX_COMPOSITE_WINDOW_Y = {
    "B_WIN_MSG": 120,
    "B_WIN_ACTION_PROMPT": 216,
    "B_WIN_ACTION_MENU": 216,
    "B_WIN_MOVE_NAME_1": 56,
    "B_WIN_MOVE_NAME_2": 56,
    "B_WIN_PP": 56,
    "B_WIN_PP_REMAINING": 56,
    "B_WIN_MOVE_NAME_3": 72,
    "B_WIN_MOVE_NAME_4": 72,
    "B_WIN_MOVE_TYPE": 72,
}

TEXTBOX_COMPOSITE_WINDOW_STATUS = "first_pass_generated_textbox_map_preview_rows"
TEXTBOX_COMPOSITE_WINDOW_SOURCE_TRACE = [
    "src/battle_bg.c:LoadBattleTextboxAndBackground",
    "src/battle_bg.c:sStandardBattleWindowTemplates",
]

FONT_WIDTH_SYMBOLS = {
    "FONT_SMALL": "gFontSmallLatinGlyphWidths",
    "FONT_NORMAL": "gFontNormalLatinGlyphWidths",
    "FONT_SHORT": "gFontShortLatinGlyphWidths",
    "FONT_SHORT_COPY_1": "gFontShortLatinGlyphWidths",
    "FONT_SHORT_COPY_2": "gFontShortLatinGlyphWidths",
    "FONT_SHORT_COPY_3": "gFontShortLatinGlyphWidths",
    "FONT_NARROW": "gFontNarrowLatinGlyphWidths",
    "FONT_SMALL_NARROW": "gFontSmallNarrowLatinGlyphWidths",
    "FONT_NARROWER": "gFontNarrowerLatinGlyphWidths",
    "FONT_SMALL_NARROWER": "gFontSmallNarrowerLatinGlyphWidths",
    "FONT_SHORT_NARROW": "gFontShortNarrowLatinGlyphWidths",
    "FONT_SHORT_NARROWER": "gFontShortNarrowerLatinGlyphWidths",
}

FONT_LATIN_ATLAS_PNG = {
    "FONT_SMALL": "latin_small.png",
    "FONT_NORMAL": "latin_normal.png",
    "FONT_SHORT": "latin_short.png",
    "FONT_SHORT_COPY_1": "latin_short.png",
    "FONT_SHORT_COPY_2": "latin_short.png",
    "FONT_SHORT_COPY_3": "latin_short.png",
    "FONT_NARROW": "latin_narrow.png",
    "FONT_SMALL_NARROW": "latin_small_narrow.png",
    "FONT_NARROWER": "latin_narrower.png",
    "FONT_SMALL_NARROWER": "latin_small_narrower.png",
    "FONT_SHORT_NARROW": "latin_short_narrow.png",
    "FONT_SHORT_NARROWER": "latin_short_narrower.png",
}

FONT_CHINESE_ATLAS_PNG = {
    "small": "chinese_small.png",
    "normal": "chinese_normal.png",
}

FONT_ATLAS_SOURCE_TRACE = [
    "src/fonts.c:gFont*LatinGlyphs",
    "src/chinese_text.c:gFontSmallChineseGlyphs",
    "src/chinese_text.c:gFontNormalChineseGlyphs",
    "src/chinese_text.c:DecompressGlyph_Chinese",
    "src/text.c:DecompressGlyphTile",
    "graphics/fonts/*.png",
]

CHINESE_ENCODING_RULE = {
    "double_byte_high_min": 0x01,
    "double_byte_high_max": 0x1E,
    "excluded_high_bytes": [0x06, 0x1B],
    "low_byte_max": 0xF6,
    "single_byte_punctuation": [0x30] + [value for value in range(0x36, 0x40) if value != 0x38],
    "glyph_index_rule": "adjust high byte down after skipped 0x06/0x1B, then (hi - 1) << 8 | low",
    "source_trace": [
        "src/chinese_text.c:IsChineseChar",
        "src/chinese_text.c:IsChinesePunctuation",
        "src/chinese_text.c:DecompressGlyph_Chinese",
        "src/chinese_text.c:GetChineseFontWidthFunc",
    ],
}

CHINESE_WIDTH_RULE = {
    "small_font_ids": ["FONT_SMALL", "FONT_SMALL_NARROW", "FONT_SMALL_NARROWER"],
    "small_default_width": 10,
    "small_punctuation_widths": {
        "0x30": 5,
        "0x37": 6,
        "0x39": 7,
        "0x3A": 5,
        "0x3B": 5,
        "0x3C": 5,
        "0x3D": 5,
        "0x3E": 5,
        "0x3F": 7,
    },
    "small_height": 13,
    "large_default_width": 12,
    "large_punctuation_widths": {"0x30": 7},
    "large_height": 15,
}


def _strip_comment(line):
    return line.split("//", 1)[0].strip()


def _parse_int_expr(value):
    value = str(value).strip()
    if not value:
        return None
    if value == "TRUE":
        return 1
    if value == "FALSE":
        return 0
    try:
        return int(value, 0)
    except ValueError:
        return None


def _extract_initializer_block(text, start):
    brace_start = text.find("{", start)
    if brace_start < 0:
        return "", start, start
    depth = 0
    for index in range(brace_start, len(text)):
        char = text[index]
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return text[brace_start + 1:index], brace_start + 1, index
    return "", brace_start + 1, brace_start + 1


def _parse_define_values_from_files(source_root, source_files):
    values = {}
    for relative_path in source_files:
        source_path = source_root / relative_path
        if not source_path.exists():
            continue
        for line_no, line in enumerate(source_path.read_text(encoding="utf-8", errors="replace").splitlines(), start=1):
            match = re.match(r"\s*#define\s+(\w+)\s+(.+)$", line)
            if match is None:
                continue
            name, raw = match.groups()
            raw = _strip_comment(raw)
            parsed = _parse_int_expr(raw)
            if parsed is None and raw in values:
                parsed = values[raw].get("value")
            values[name] = {
                "value": parsed if parsed is not None else raw,
                "raw": raw,
                "source": {"file": to_project_path(relative_path), "line": line_no},
            }
    return values


def _resolve_int_expr(value, defines):
    raw = str(value).strip()
    parsed = _parse_int_expr(raw)
    if parsed is not None:
        return parsed
    if raw in defines and isinstance(defines[raw].get("value"), int):
        return int(defines[raw]["value"])
    ternary_match = re.match(r"(.+?)\?\s*(.+?)\s*:\s*(.+)$", raw)
    if ternary_match is not None:
        condition, truthy, falsey = [part.strip() for part in ternary_match.groups()]
        condition_value = _resolve_condition(condition, defines)
        if condition_value is not None:
            return _resolve_int_expr(truthy if condition_value else falsey, defines)
    return None


def _resolve_condition(condition, defines):
    match = re.match(r"(.+?)\s*(!=|==)\s*(.+)$", condition)
    if match is None:
        return None
    left, op, right = [part.strip() for part in match.groups()]
    left_value = _resolve_int_expr(left, defines)
    right_value = _resolve_int_expr(right, defines)
    if left_value is None or right_value is None:
        return None
    if op == "!=":
        return left_value != right_value
    if op == "==":
        return left_value == right_value
    return None


def _parse_pixel_fill(expr):
    match = re.match(r"PIXEL_FILL\((.+)\)", str(expr).strip())
    if match is None:
        return None
    return _parse_int_expr(match.group(1))


def _source_asset_path(binary_path):
    text = to_project_path(binary_path)
    for old_ext, new_ext in BINARY_ASSET_EXTENSIONS:
        if text.endswith(old_ext):
            return Path(text[: -len(old_ext)] + new_ext)
    return Path(text)


def _read_jasc_color_file(path):
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


def _read_png_color_table(image):
    if image.mode != "P":
        return []
    raw = image.getpalette() or []
    colors = []
    for index in range(0, len(raw), 3):
        if index + 2 >= len(raw):
            break
        colors.append({"r": int(raw[index]), "g": int(raw[index + 1]), "b": int(raw[index + 2])})
    return colors


def _alpha_summary(image):
    has_opaque = False
    has_transparent = False
    for _r, _g, _b, alpha in image.getdata():
        if alpha <= 2:
            has_transparent = True
        elif alpha >= 253:
            has_opaque = True
        else:
            has_opaque = True
            has_transparent = True
        if has_opaque and has_transparent:
            break
    return {"has_opaque": has_opaque, "has_transparent": has_transparent}


def _convert_png_asset(source_path, output_path):
    from PIL import Image

    output_path.parent.mkdir(parents=True, exist_ok=True)
    image = Image.open(source_path)
    try:
        source_mode = image.mode
        source_colors = _read_png_color_table(image)
        if image.mode == "P":
            alpha = Image.new("L", image.size, 255)
            alpha.putdata([0 if int(pixel) == 0 else 255 for pixel in image.getdata()])
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
                "source_png_color_count": len(source_colors),
                "transparent_zero": source_mode == "P",
                "transparency": {
                    "source_transparent_index": 0 if source_mode == "P" else None,
                    "alpha_policy": "source_index_zero" if source_mode == "P" else "opaque_source",
                },
                "alpha": _alpha_summary(converted),
                "conversion": "source_png_to_rgba",
            }
        finally:
            converted.close()
    finally:
        image.close()


def _texture_role(asset_id):
    if asset_id in ROLE_OVERRIDES:
        group, role = ROLE_OVERRIDES[asset_id]
        return group, role
    if asset_id.endswith("_indicator"):
        return "gimmick_indicator", asset_id
    if asset_id.endswith("_trigger"):
        return "gimmick_trigger", asset_id
    return "misc", asset_id


def _parse_graphics_definitions(source_root):
    definitions = {}
    source_files = [GRAPHICS_SOURCE, BATTLE_INTERFACE_SOURCE, BATTLE_SCRIPT_COMMANDS_SOURCE, GIMMICKS_SOURCE]
    for relative_path in source_files:
        source_path = source_root / relative_path
        if not source_path.exists():
            continue
        text = source_path.read_text(encoding="utf-8", errors="replace")
        statements = []
        current = []
        current_line = 1
        for line_no, line in enumerate(text.splitlines(), start=1):
            if "INCBIN_" in line and not current:
                current_line = line_no
            if current or "INCBIN_" in line:
                current.append(line)
                if ";" in line:
                    statements.append((current_line, "\n".join(current)))
                    current = []
        for line_no, statement in statements:
            if "graphics/battle_interface/" not in statement:
                continue
            preamble = statement.split("=", 1)[0]
            symbol_match = re.search(r"(\w+)\s*(?:\[\s*\]\s*)+(?:\[[^\]]+\]\s*)*$", preamble.strip())
            if symbol_match is None:
                symbol_match = re.search(r"(\w+)\s*(?:\[\s*\])", preamble.strip())
            if symbol_match is None:
                continue
            symbol = symbol_match.group(1)
            asset_refs = []
            for binary_path in re.findall(r'"(graphics/battle_interface/[^"]+)"', statement):
                source_asset_path = _source_asset_path(binary_path)
                asset_refs.append({
                    "source_binary_path": binary_path,
                    "source_asset_path": to_project_path(source_asset_path),
                    "source_asset_exists": (source_root / source_asset_path).exists(),
                })
            if not asset_refs:
                continue
            definitions[symbol] = {
                "symbol": symbol,
                "source_file": to_project_path(relative_path),
                "source_line": line_no,
                "asset_refs": asset_refs,
            }
    return definitions


def _parse_window_templates(source_root):
    source_path = source_root / BATTLE_BG_SOURCE
    text = source_path.read_text(encoding="utf-8", errors="replace")
    start = text.find("static const struct WindowTemplate sStandardBattleWindowTemplates[]")
    if start < 0:
        return {}
    end = text.find("DUMMY_WIN_TEMPLATE", start)
    if end < 0:
        return {}
    block = text[start:end]
    templates = {}
    for match in re.finditer(r"\[(B_WIN_[A-Z0-9_]+)\]\s*=\s*\{(?P<body>.*?)\n\s*\}", block, re.S):
        symbol = match.group(1)
        body = match.group("body")
        fields = {}
        for field_match in re.finditer(r"\.(\w+)\s*=\s*([^,\n]+)", body):
            field_name = field_match.group(1)
            field_value = _strip_comment(field_match.group(2))
            parsed = _parse_int_expr(field_value)
            fields[field_name] = parsed if parsed is not None else field_value
        style_slot = int(fields.get("paletteNum", 0) or 0)
        templates[symbol] = {
            "symbol": symbol,
            "bg": int(fields.get("bg", 0) or 0),
            "tilemap_left": int(fields.get("tilemapLeft", 0) or 0),
            "tilemap_top": int(fields.get("tilemapTop", 0) or 0),
            "width": int(fields.get("width", 0) or 0),
            "height": int(fields.get("height", 0) or 0),
            "style_id": _window_style_id(style_slot),
            "base_block": int(fields.get("baseBlock", 0) or 0),
            "source": {
                "file": to_project_path(BATTLE_BG_SOURCE),
                "line": text[: start + match.start()].count("\n") + 1,
            },
            "runtime_status": "metadata_only",
        }
    return templates


def _attach_textbox_composite_window_rects(window_templates, tilemaps):
    textbox_map = tilemaps.get("textbox_map", {})
    composite = textbox_map.get("tilemap_composite", {}) if isinstance(textbox_map, dict) else {}
    if not isinstance(composite, dict) or not composite:
        return 0

    count = 0
    for symbol, source_y in TEXTBOX_COMPOSITE_WINDOW_Y.items():
        record = window_templates.get(symbol, {})
        if not isinstance(record, dict) or not record:
            continue
        rect = {
            "tilemap": "textbox_map",
            "composite_id": "textbox_map",
            "x": int(record.get("tilemap_left", 0)) * TILE_SIZE,
            "y": int(source_y),
            "w": int(record.get("width", 0)) * TILE_SIZE,
            "h": int(record.get("height", 0)) * TILE_SIZE,
            "status": TEXTBOX_COMPOSITE_WINDOW_STATUS,
            "source_texture": "graphics/battle_interface/textbox.png",
            "source_tilemap_path": "graphics/battle_interface/textbox_map.bin",
            "source_trace": TEXTBOX_COMPOSITE_WINDOW_SOURCE_TRACE,
        }
        record["tilemap_composite_rect"] = rect
        count += 1

    composite["window_rect_status"] = TEXTBOX_COMPOSITE_WINDOW_STATUS
    composite["window_rect_count"] = count
    return count


def _parse_battle_window_text_info(source_root):
    source_path = source_root / BATTLE_MESSAGE_SOURCE
    if not source_path.exists():
        return {}, {}
    text = source_path.read_text(encoding="utf-8", errors="replace")
    start = text.find("static const struct BattleWindowText sTextOnWindowsInfo_Normal[]")
    if start < 0:
        return {}, {}
    block, block_start, _block_end = _extract_initializer_block(text, start)
    defines = _parse_define_values_from_files(source_root, [
        BATTLE_CONFIG_SOURCE,
        TEXT_CONFIG_SOURCE,
        GLOBAL_CONSTANTS_SOURCE,
    ])
    font_metrics = _parse_source_font_metrics(source_root)
    records = {}
    for match in re.finditer(r"\[(B_WIN_[A-Z0-9_]+|ARENA_WIN_[A-Z0-9_]+)\]\s*=\s*\{(?P<body>.*?)\n\s*\}", block, re.S):
        symbol = match.group(1)
        body = match.group("body")
        fields = {}
        raw_fields = {}
        for field_match in re.finditer(r"\.(fillValue|fontId|x|y|speed|letterSpacing|lineSpacing)\s*=\s*([^,\n]+)", body):
            field_name = field_match.group(1)
            raw_value = _strip_comment(field_match.group(2))
            raw_fields[field_name] = raw_value
            if field_name == "fillValue":
                parsed = _parse_pixel_fill(raw_value)
            elif field_name == "fontId":
                parsed = raw_value
            else:
                parsed = _resolve_int_expr(raw_value, defines)
            fields[field_name] = parsed if parsed is not None else raw_value

        color_indices = {}
        color_raw = {}
        for color_match in re.finditer(r"\.color\.(foreground|background|accent|shadow)\s*=\s*([^,\n]+)", body):
            color_name = color_match.group(1)
            raw_value = _strip_comment(color_match.group(2))
            color_raw[color_name] = raw_value
            parsed = _resolve_int_expr(raw_value, defines)
            color_indices[color_name] = parsed if parsed is not None else raw_value

        fill_index = fields.get("fillValue", 0)
        font_id = str(fields.get("fontId", "FONT_NORMAL"))
        table_speed = int(fields.get("speed", 0) or 0)
        record = {
            "symbol": symbol,
            "status": "generated_from_sTextOnWindowsInfo_Normal",
            "fill_value_index": int(fill_index) if isinstance(fill_index, int) else fill_index,
            "fill_style": _text_fill_style(fill_index),
            "panel_style": _text_fill_style(fill_index),
            "font_id": font_id,
            "font_size": _font_size_for_source_font(font_id),
            "font_metrics": _font_metrics_summary(font_metrics, font_id),
            "text_x": int(fields.get("x", 0) or 0),
            "text_y": int(fields.get("y", 0) or 0),
            "letter_spacing": int(fields.get("letterSpacing", 0) or 0),
            "line_spacing": int(fields.get("lineSpacing", 0) or 0),
            "table_speed": table_speed,
            "source_speed": table_speed,
            "effective_speed_source": "table_speed",
            "can_ab_speed_up_print": False,
            "text_material_id": _text_material_id(symbol, fill_index, color_indices),
            "text_color_indices": color_indices,
            "raw_fields": raw_fields,
            "raw_color_fields": color_raw,
            "source": {
                "file": to_project_path(BATTLE_MESSAGE_SOURCE),
                "line": text[: block_start + match.start()].count("\n") + 1,
            },
        }
        if symbol in ["B_WIN_MSG", "ARENA_WIN_JUDGMENT_TEXT", "B_WIN_OAK_OLD_MAN"]:
            record["source_speed"] = "player_text_speed_delay"
            record["effective_speed_source"] = "BattlePutTextOnWindow:GetPlayerTextSpeedDelay_or_recorded_speed"
            record["can_ab_speed_up_print"] = True
        if re.match(r"B_WIN_MOVE_NAME_[1-4]$", symbol):
            record["source_fit_width_px"] = 64
            record["source_fit_width_rule"] = "BattlePutTextOnWindow:GetFontIdToFit"
            if symbol == "B_WIN_MOVE_NAME_1":
                record["zmove_source_fit_width_px"] = 128
        records[symbol] = record

    printer = {
        "status": "metadata_only",
        "normal_window_text_info_count": len(records),
        "source_trace": [
            "src/battle_message.c:sTextOnWindowsInfo_Normal",
            "src/battle_message.c:sBattleTextOnWindowsInfo",
            "src/battle_message.c:BattlePutTextOnWindow",
            "src/text.c:GetPlayerTextSpeedDelay",
            "src/text.c:AddTextPrinter",
        ],
        "normal_windows_type": "B_WIN_TYPE_NORMAL",
        "message_speed_windows": ["B_WIN_MSG", "ARENA_WIN_JUDGMENT_TEXT", "B_WIN_OAK_OLD_MAN"],
        "message_effective_speed_source": "GetPlayerTextSpeedDelay unless link/recorded battle overrides apply",
        "recorded_battle_text_speeds": _parse_recorded_battle_text_speeds(text),
        "player_text_speed": _parse_player_text_speed_metadata(source_root),
        "font_metrics": font_metrics,
        "copy_to_vram_rule": "B_WIN_COPYTOVRAM skips FillWindowPixelBuffer and final PutWindowTilemap/CopyWindowToVram; normal calls fill then copy full window",
        "runtime_status": "metadata_only",
        "unsupported": ["battle_text_glyph_bitmap_renderer_pending"],
    }
    return records, printer


def _attach_battle_window_text_info(window_templates, text_info_records):
    count = 0
    for symbol, record in window_templates.items():
        if symbol not in text_info_records:
            continue
        record["text_info"] = text_info_records[symbol]
        count += 1
    return count


def _text_fill_style(fill_index):
    if fill_index == 15:
        return "message_panel"
    if fill_index == 14:
        return "menu_panel"
    if fill_index == 0:
        return "transparent_or_banner"
    return "source_fill_%s" % str(fill_index)


def _font_size_for_source_font(font_id):
    return 8


def _parse_source_font_metrics(source_root):
    font_infos = _parse_source_font_infos(source_root)
    latin_widths = _parse_source_latin_font_widths(source_root)
    fonts = {}
    for font_id, info in font_infos.items():
        widths_symbol = FONT_WIDTH_SYMBOLS.get(font_id, "")
        widths = latin_widths.get(widths_symbol, []) if widths_symbol else []
        font_record = {
            "font_id": font_id,
            "source_font_function": info.get("font_function", ""),
            "max_letter_width": int(info.get("max_letter_width", 0)),
            "max_letter_height": int(info.get("max_letter_height", 0)),
            "letter_spacing": int(info.get("letter_spacing", 0)),
            "line_spacing": int(info.get("line_spacing", 0)),
            "line_advance": int(info.get("max_letter_height", 0)) + int(info.get("line_spacing", 0)),
            "latin_glyph_height": _latin_glyph_height_for_font(font_id),
            "latin_width_table": widths_symbol,
            "latin_width_count": len(widths),
            "latin_widths": widths,
            "source": info.get("source", {}),
        }
        if font_id in FONT_WIDTH_SYMBOLS:
            font_record["chinese_width_rule"] = _font_chinese_width_rule(font_id)
        fonts[font_id] = font_record
    return {
        "status": "generated_from_text_c_font_tables",
        "font_count": len(fonts),
        "fonts": fonts,
        "chinese_encoding": CHINESE_ENCODING_RULE,
        "source_trace": [
            "src/text.c:sFontInfos",
            "src/text.c:PrintGlyph",
            "src/text.c:GetStringWidth",
            "src/fonts.c:gFont*LatinGlyphWidths",
            "src/chinese_text.c:IsChineseChar",
            "src/chinese_text.c:GetChineseFontWidthFunc",
        ],
    }


def _build_source_font_atlases(source_root, output_asset_root):
    records = {}
    atlas_sources = sorted(set(FONT_LATIN_ATLAS_PNG.values()) | set(FONT_CHINESE_ATLAS_PNG.values()))
    for filename in atlas_sources:
        source_path = source_root / FONT_GRAPHICS_DIR / filename
        atlas_id = Path(filename).stem
        output_path = output_asset_root / FONT_ATLAS_OUTPUT_DIR / filename
        record = {
            "id": atlas_id,
            "source": to_project_path(FONT_GRAPHICS_DIR / filename),
            "kind": "source_font_atlas",
            "runtime_asset_model": "ordinary_rgba_texture",
            "source_trace": FONT_ATLAS_SOURCE_TRACE,
        }
        if not source_path.exists():
            record["status"] = "missing_source_png"
            records[atlas_id] = record
            continue
        asset = _convert_png_asset(source_path, output_path)
        record.update(asset)
        record.update({
            "status": "generated_rgba_from_source_png",
            "glyph_cell": {"w": FONT_GLYPH_CELL_SIZE, "h": FONT_GLYPH_CELL_SIZE},
            "columns": int(asset["size"]["w"] // FONT_GLYPH_CELL_SIZE),
            "rows": int(asset["size"]["h"] // FONT_GLYPH_CELL_SIZE),
            "glyph_capacity": int(asset["size"]["w"] // FONT_GLYPH_CELL_SIZE) * int(asset["size"]["h"] // FONT_GLYPH_CELL_SIZE),
            "text_color_status": "source_png_preview_colors",
            "note": "The source PNG glyph pixels are baked to RGBA for Godot. Exact source text colors still come from RenderText color controls and remain separate presentation work.",
        })
        records[atlas_id] = record
    return records


def _font_uses_small_chinese_atlas(font_id):
    return font_id in {"FONT_SMALL", "FONT_SMALL_NARROW", "FONT_SMALL_NARROWER"}


def _glyph_atlas_binding_for_font(font_id, font_record, font_atlases):
    latin_filename = FONT_LATIN_ATLAS_PNG.get(font_id, "")
    latin_atlas_id = Path(latin_filename).stem if latin_filename else ""
    chinese_atlas_id = "chinese_small" if _font_uses_small_chinese_atlas(font_id) else "chinese_normal"
    latin_atlas = font_atlases.get(latin_atlas_id, {})
    chinese_atlas = font_atlases.get(chinese_atlas_id, {})
    binding = {
        "status": "source_font_atlas_preview",
        "runtime_asset_model": "ordinary_rgba_texture",
        "glyph_cell": {"w": FONT_GLYPH_CELL_SIZE, "h": FONT_GLYPH_CELL_SIZE},
        "latin_atlas_id": latin_atlas_id,
        "latin_image": latin_atlas.get("image", ""),
        "latin_columns": int(latin_atlas.get("columns", 0)),
        "latin_rows": int(latin_atlas.get("rows", 0)),
        "latin_glyph_capacity": int(latin_atlas.get("glyph_capacity", 0)),
        "latin_glyph_count": int(font_record.get("latin_width_count", 0)),
        "latin_index_rule": "glyph byte value indexes 16x16 cells left-to-right, top-to-bottom",
        "chinese_atlas_id": chinese_atlas_id,
        "chinese_image": chinese_atlas.get("image", ""),
        "chinese_columns": int(chinese_atlas.get("columns", 0)),
        "chinese_rows": int(chinese_atlas.get("rows", 0)),
        "chinese_glyph_capacity": int(chinese_atlas.get("glyph_capacity", 0)),
        "chinese_index_rule": CHINESE_ENCODING_RULE["glyph_index_rule"],
        "chinese_punctuation_source": "latin_atlas",
        "source_trace": FONT_ATLAS_SOURCE_TRACE,
        "unsupported": [
            "exact_render_text_color_controls_pending",
            "exact_control_code_pixel_side_effects_pending",
        ],
    }
    if not latin_atlas_id:
        binding["status"] = "no_latin_atlas_for_font"
    elif not latin_atlas or not chinese_atlas:
        binding["status"] = "missing_source_font_atlas"
    return binding


def _attach_font_atlas_bindings(font_metrics, font_atlases):
    if not isinstance(font_metrics, dict):
        return 0
    fonts = font_metrics.get("fonts", {})
    if not isinstance(fonts, dict):
        return 0
    count = 0
    for font_id, record in fonts.items():
        if not isinstance(record, dict) or font_id not in FONT_WIDTH_SYMBOLS:
            continue
        binding = _glyph_atlas_binding_for_font(font_id, record, font_atlases)
        record["glyph_atlas"] = binding
        count += 1
    return count


def _font_metrics_summary(font_metrics, font_id):
    fonts = font_metrics.get("fonts", {}) if isinstance(font_metrics, dict) else {}
    record = fonts.get(font_id, {}) if isinstance(fonts, dict) else {}
    if not isinstance(record, dict) or not record:
        return {}
    return {
        "status": font_metrics.get("status", ""),
        "font_id": font_id,
        "max_letter_width": record.get("max_letter_width", 0),
        "max_letter_height": record.get("max_letter_height", 0),
        "letter_spacing": record.get("letter_spacing", 0),
        "line_spacing": record.get("line_spacing", 0),
        "line_advance": record.get("line_advance", 0),
        "latin_glyph_height": record.get("latin_glyph_height", 0),
        "latin_width_table": record.get("latin_width_table", ""),
        "latin_width_count": record.get("latin_width_count", 0),
        "chinese_width_rule": record.get("chinese_width_rule", {}),
        "glyph_atlas": record.get("glyph_atlas", {}),
    }


def _parse_source_font_infos(source_root):
    source_path = source_root / TEXT_SOURCE
    if not source_path.exists():
        return {}
    text = source_path.read_text(encoding="utf-8", errors="replace")
    start = text.find("static const struct FontInfo sFontInfos[]")
    if start < 0:
        return {}
    block, block_start, _block_end = _extract_initializer_block(text, start)
    result = {}
    for match in re.finditer(r"\[(FONT_[A-Z0-9_]+)\]\s*=\s*\{(?P<body>.*?)\n\s*\}", block, re.S):
        font_id = match.group(1)
        body = match.group("body")
        function_match = re.search(r"\.fontFunction\s*=\s*([^,\n]+)", body)
        record = {
            "font_function": _strip_comment(function_match.group(1)) if function_match is not None else "",
            "source": {
                "file": to_project_path(TEXT_SOURCE),
                "line": text[: block_start + match.start()].count("\n") + 1,
            },
        }
        for field_name, key in [
            ("maxLetterWidth", "max_letter_width"),
            ("maxLetterHeight", "max_letter_height"),
            ("letterSpacing", "letter_spacing"),
            ("lineSpacing", "line_spacing"),
        ]:
            field_match = re.search(r"\.%s\s*=\s*([^,\n]+)" % field_name, body)
            parsed = _parse_int_expr(_strip_comment(field_match.group(1))) if field_match is not None else None
            record[key] = parsed if parsed is not None else 0
        result[font_id] = record
    return result


def _parse_source_latin_font_widths(source_root):
    source_path = source_root / FONTS_SOURCE
    if not source_path.exists():
        return {}
    text = source_path.read_text(encoding="utf-8", errors="replace")
    result = {}
    for symbol in sorted(set(FONT_WIDTH_SYMBOLS.values())):
        match = re.search(r"const u8 %s\[\]\s*=\s*\{" % re.escape(symbol), text)
        if match is None:
            continue
        block, _block_start, _block_end = _extract_initializer_block(text, match.start())
        widths = []
        for value in re.findall(r"\b(?:0x[0-9A-Fa-f]+|\d+)\b", block):
            parsed = _parse_int_expr(value)
            if parsed is not None:
                widths.append(parsed)
        result[symbol] = widths
    return result


def _font_chinese_width_rule(font_id):
    if font_id in CHINESE_WIDTH_RULE["small_font_ids"]:
        return {
            "default_width": CHINESE_WIDTH_RULE["small_default_width"],
            "height": CHINESE_WIDTH_RULE["small_height"],
            "punctuation_widths": CHINESE_WIDTH_RULE["small_punctuation_widths"],
        }
    return {
        "default_width": CHINESE_WIDTH_RULE["large_default_width"],
        "height": CHINESE_WIDTH_RULE["large_height"],
        "punctuation_widths": CHINESE_WIDTH_RULE["large_punctuation_widths"],
    }


def _latin_glyph_height_for_font(font_id):
    if font_id in ["FONT_SMALL", "FONT_SMALL_NARROWER"]:
        return 13 if font_id == "FONT_SMALL" else 15
    if font_id == "FONT_SMALL_NARROW":
        return 12
    if font_id in ["FONT_SHORT", "FONT_SHORT_COPY_1", "FONT_SHORT_COPY_2", "FONT_SHORT_COPY_3", "FONT_SHORT_NARROW", "FONT_SHORT_NARROWER"]:
        return 14
    if font_id in ["FONT_NORMAL", "FONT_NARROW", "FONT_NARROWER"]:
        return 15
    if font_id == "FONT_BRAILLE":
        return 16
    if font_id == "FONT_BOLD":
        return 12
    return 0


def _text_material_id(symbol, fill_index, color_indices):
    if symbol == "B_WIN_PP_REMAINING" or (
        color_indices.get("foreground") == 12 and color_indices.get("shadow") == 11
    ):
        return "battle_pp_numeric"
    if fill_index == 15:
        return "battle_text_primary"
    return "battle_text_menu"


def _parse_recorded_battle_text_speeds(text):
    match = re.search(r"static const u8 sRecordedBattleTextSpeeds\[\]\s*=\s*\{(?P<body>[^}]+)\}", text, re.S)
    if match is None:
        return []
    result = []
    for value in match.group("body").split(","):
        parsed = _parse_int_expr(value.strip())
        if parsed is not None:
            result.append(parsed)
    return result


def _parse_player_text_speed_metadata(source_root):
    source_path = source_root / TEXT_SOURCE
    if not source_path.exists():
        return {}
    text = source_path.read_text(encoding="utf-8", errors="replace")
    defines = _parse_define_values_from_files(source_root, [
        TEXT_CONFIG_SOURCE,
        GLOBAL_CONSTANTS_SOURCE,
    ])
    return {
        "frame_delays": _parse_indexed_u8_array(text, "sTextSpeedFrameDelays", defines),
        "modifiers": _parse_indexed_u8_array(text, "sTextSpeedModifiers", defines),
        "scroll_speeds": _parse_indexed_u8_array(text, "sTextScrollSpeeds", defines),
        "source": {"file": to_project_path(TEXT_SOURCE)},
    }


def _parse_indexed_u8_array(text, name, defines):
    start = text.find("static const u8 %s[]" % name)
    if start < 0:
        return {}
    block, _block_start, _block_end = _extract_initializer_block(text, start)
    result = {}
    for match in re.finditer(r"\[(OPTIONS_TEXT_SPEED_[A-Z_]+)\]\s*=\s*([^,\n]+)", block):
        key = match.group(1)
        parsed = _resolve_int_expr(match.group(2).strip(), defines)
        if parsed is not None:
            result[key] = parsed
    return result


def _window_style_id(style_slot):
    if style_slot == 0:
        return "battle_message_text"
    if style_slot == 5:
        return "battle_menu_text"
    if style_slot == 6:
        return "battle_level_up_banner"
    return "battle_window_style_%d" % style_slot


def _parse_healthbox_coords(source_root):
    source_path = source_root / BATTLE_INTERFACE_SOURCE
    coords = {}
    current_group = ""
    in_table = False
    for line_no, line in enumerate(source_path.read_text(encoding="utf-8", errors="replace").splitlines(), start=1):
        if "sBattlerHealthboxCoords" in line:
            in_table = True
            continue
        if not in_table:
            continue
        if line.startswith("};"):
            break
        group_match = re.search(r"\[(BATTLE_COORDS_[A-Z0-9_]+)\]\s*=", line)
        if group_match is not None:
            current_group = group_match.group(1)
            coords.setdefault(current_group, {})
            continue
        coord_match = re.search(r"\[(B_POSITION_[A-Z0-9_]+)\]\s*=\s*\{\s*(-?\d+),\s*(-?\d+)\s*\}", line)
        if coord_match is not None and current_group:
            position, x_value, y_value = coord_match.groups()
            coords[current_group][position] = {
                "x": int(x_value),
                "y": int(y_value),
                "source": {"file": to_project_path(BATTLE_INTERFACE_SOURCE), "line": line_no},
            }
    return coords


def _parse_ability_popup_coords(source_root):
    source_path = source_root / BATTLE_INTERFACE_SOURCE
    text = source_path.read_text(encoding="utf-8", errors="replace")
    result = {}
    for symbol in ["sAbilityPopUpCoordsDoubles", "sAbilityPopUpCoordsSingles"]:
        start = text.find(symbol)
        if start < 0:
            continue
        end = text.find("};", start)
        block = text[start:end]
        pairs = []
        for pair in re.findall(r"\{\s*(-?\d+),\s*(-?\d+)\s*\}", block):
            pairs.append({"x": int(pair[0]), "y": int(pair[1])})
        result[symbol] = {
            "coords": pairs,
            "source": {"file": to_project_path(BATTLE_INTERFACE_SOURCE), "line": text[:start].count("\n") + 1},
        }
    return result


def _parse_define_values(source_root, names):
    source_path = source_root / BATTLE_INTERFACE_SOURCE
    values = {}
    for line_no, line in enumerate(source_path.read_text(encoding="utf-8", errors="replace").splitlines(), start=1):
        match = re.match(r"\s*#define\s+(\w+)\s+(.+)$", line)
        if match is None:
            continue
        name, raw = match.groups()
        if name not in names:
            continue
        raw = _strip_comment(raw)
        parsed = _parse_int_expr(raw)
        values[name] = {
            "value": parsed if parsed is not None else raw,
            "source": {"file": to_project_path(BATTLE_INTERFACE_SOURCE), "line": line_no},
        }
    return values


def _read_tilemap(path):
    data = path.read_bytes()
    entry_count = len(data) // 2
    if entry_count <= 0:
        return []
    return list(struct.unpack("<%dH" % entry_count, data[: entry_count * 2]))


def _tilemap_dimensions(entry_count):
    if entry_count == 2048:
        return 64, 32
    if entry_count == 1024:
        return 32, 32
    if entry_count == 640:
        return 32, 20
    side = int(math.sqrt(entry_count))
    if side * side == entry_count:
        return side, side
    if entry_count % 32 == 0:
        return 32, entry_count // 32
    return entry_count, 1


def _compose_textbox_tilemap(source_root, output_asset_root):
    from PIL import Image

    tile_source = source_root / BATTLE_INTERFACE_DIR / "textbox.png"
    tilemap_source = source_root / BATTLE_INTERFACE_DIR / "textbox_map.bin"
    if not tile_source.exists() or not tilemap_source.exists():
        return {}, ["missing_textbox_tilemap_source"]

    source_image = Image.open(tile_source)
    try:
        if source_image.mode == "P":
            alpha = Image.new("L", source_image.size, 255)
            alpha.putdata([0 if int(pixel) == 0 else 255 for pixel in source_image.getdata()])
            tile_image = source_image.convert("RGBA")
            tile_image.putalpha(alpha)
        else:
            tile_image = source_image.convert("RGBA")
        try:
            entries = _read_tilemap(tilemap_source)
            width_tiles, height_tiles = _tilemap_dimensions(len(entries))
            output = Image.new("RGBA", (width_tiles * TILE_SIZE, height_tiles * TILE_SIZE), (0, 0, 0, 0))
            atlas_width_tiles = tile_image.width // TILE_SIZE
            atlas_height_tiles = tile_image.height // TILE_SIZE
            atlas_tile_count = atlas_width_tiles * atlas_height_tiles
            missing_tiles = 0
            for index, entry in enumerate(entries):
                tile_index = int(entry) & 0x03FF
                hflip = bool(int(entry) & 0x0400)
                vflip = bool(int(entry) & 0x0800)
                if tile_index >= atlas_tile_count:
                    missing_tiles += 1
                    continue
                sx = (tile_index % atlas_width_tiles) * TILE_SIZE
                sy = (tile_index // atlas_width_tiles) * TILE_SIZE
                tile = tile_image.crop((sx, sy, sx + TILE_SIZE, sy + TILE_SIZE))
                if hflip:
                    tile = tile.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
                if vflip:
                    tile = tile.transpose(Image.Transpose.FLIP_TOP_BOTTOM)
                dx = (index % width_tiles) * TILE_SIZE
                dy = (index // width_tiles) * TILE_SIZE
                output.alpha_composite(tile, (dx, dy))
                tile.close()
            output_path = output_asset_root / COMPOSITE_OUTPUT_DIR / "textbox_map.png"
            output_path.parent.mkdir(parents=True, exist_ok=True)
            output.save(output_path)
            try:
                alpha = _alpha_summary(output)
                return {
                    "id": "textbox_map",
                    "status": "first_pass",
                    "image": "res://%s" % to_project_path(output_path),
                    "image_project_path": to_project_path(output_path),
                    "size": {"w": int(output.width), "h": int(output.height)},
                    "source_tile_texture": "textbox",
                    "source_tilemap_path": to_project_path(tilemap_source.relative_to(source_root)),
                    "width_tiles": width_tiles,
                    "height_tiles": height_tiles,
                    "entry_count": len(entries),
                    "missing_tile_count": missing_tiles,
                    "alpha": alpha,
                    "conversion": "source_tilemap_to_rgba_preview",
                }, []
            finally:
                output.close()
        finally:
            tile_image.close()
    finally:
        source_image.close()


def _build_texture_inventory(source_root, output_asset_root, definitions):
    textures = {}
    texture_order = []
    png_paths = sorted((source_root / BATTLE_INTERFACE_DIR).glob("*.png"))
    refs_by_asset = {}
    symbols_by_asset = {}
    for definition in definitions.values():
        for ref in definition.get("asset_refs", []):
            source_asset_path = str(ref.get("source_asset_path", ""))
            if not source_asset_path.endswith(".png"):
                continue
            asset_id = Path(source_asset_path).stem
            refs_by_asset.setdefault(asset_id, []).append(ref)
            symbols_by_asset.setdefault(asset_id, []).append(definition.get("symbol", ""))

    for source_path in png_paths:
        asset_id = source_path.stem
        group, role = _texture_role(asset_id)
        output_path = output_asset_root / ASSET_OUTPUT_DIR / source_path.name
        asset = _convert_png_asset(source_path, output_path)
        asset.update({
            "id": asset_id,
            "asset_id": asset_id,
            "group": group,
            "role": role,
            "status": "imported",
            "asset_status": "first_pass",
            "source_png_path": to_project_path(source_path.relative_to(source_root)),
            "source_asset_refs": refs_by_asset.get(asset_id, []),
            "source_symbols": sorted(symbol for symbol in set(symbols_by_asset.get(asset_id, [])) if symbol),
        })
        textures[asset_id] = asset
        texture_order.append(asset_id)
    return textures, texture_order


def _build_source_color_provenance(source_root):
    records = {}
    order = []
    for path in sorted((source_root / BATTLE_INTERFACE_DIR).glob("*.pal")):
        colors = _read_jasc_color_file(path)
        record_id = path.stem
        records[record_id] = {
            "id": record_id,
            "source_path": to_project_path(path.relative_to(source_root)),
            "color_count": len(colors),
            "status": "metadata_only",
            "import_only": True,
        }
        order.append(record_id)
    return records, order


def _build_tilemaps(source_root, output_asset_root):
    records = {}
    order = []
    for path in sorted((source_root / BATTLE_INTERFACE_DIR).glob("*.bin")):
        data = path.read_bytes()
        entry_count = len(data) // 2
        width_tiles, height_tiles = _tilemap_dimensions(entry_count)
        record_id = path.stem
        records[record_id] = {
            "id": record_id,
            "source_path": to_project_path(path.relative_to(source_root)),
            "byte_size": len(data),
            "entry_count_16bit": entry_count,
            "width_tiles": width_tiles,
            "height_tiles": height_tiles,
            "status": "metadata_only",
        }
        order.append(record_id)

    composite, warnings = _compose_textbox_tilemap(source_root, output_asset_root)
    if composite:
        records.setdefault("textbox_map", {}).update({"tilemap_composite": composite})
    return records, order, warnings


def _texture_refs(textures, names):
    return [name for name in names if name in textures]


def _build_interface_sections(source_root, textures):
    ability_defines = _parse_define_values(source_root, [
        "ABILITY_POP_UP_POS_X_DIFF",
        "ABILITY_POP_UP_POS_X_SLIDE",
        "ABILITY_POP_UP_POS_X_SPEED",
        "ABILITY_POP_UP_WIN_WIDTH",
        "ABILITY_POP_UP_WAIT_FRAMES",
    ])
    return {
        "textbox": {
            "texture": "textbox" if "textbox" in textures else "",
            "tilemap": "textbox_map",
            "runtime_status": "unsupported",
            "unsupported": ["battle_interface_runtime_pending"],
        },
        "healthbox": {
            "frame_textures": _texture_refs(textures, HEALTHBOX_FRAME_TEXTURES),
            "element_textures": _texture_refs(textures, HEALTHBOX_ELEMENT_TEXTURES),
            "coords": _parse_healthbox_coords(source_root),
            "bar_width_px": 48,
            "runtime_status": "metadata_only",
            "unsupported": ["battle_hud_runtime_pending"],
        },
        "party_summary": {
            "textures": _texture_refs(textures, [
                "ball_status_bar",
                "ball_display",
                "ball_caught_indicator",
                "unused_status_summary",
            ]),
            "runtime_status": "metadata_only",
            "unsupported": ["battle_hud_runtime_pending"],
        },
        "ability_popup": {
            "texture": "ability_pop_up" if "ability_pop_up" in textures else "",
            "coords": _parse_ability_popup_coords(source_root),
            "motion": {
                "x_diff": ability_defines.get("ABILITY_POP_UP_POS_X_DIFF", {}),
                "x_slide": ability_defines.get("ABILITY_POP_UP_POS_X_SLIDE", {}),
                "x_speed_px_per_frame": ability_defines.get("ABILITY_POP_UP_POS_X_SPEED", {}),
                "idle_frames": ability_defines.get("ABILITY_POP_UP_WAIT_FRAMES", {}),
                "audio_cue": {"symbol": "SE_BALL_TRAY_ENTER", "status": "metadata_only"},
            },
            "runtime_status": "metadata_only",
            "unsupported": ["battle_hud_runtime_pending", "battle_audio_playback_pending"],
        },
        "last_used_ball": {
            "textures": _texture_refs(textures, [
                "last_used_ball_l",
                "last_used_ball_l_cycle",
                "last_used_ball_r",
                "last_used_ball_r_cycle",
            ]),
            "runtime_status": "metadata_only",
            "unsupported": ["battle_hud_runtime_pending"],
        },
        "move_info_window": {
            "textures": _texture_refs(textures, ["move_info_window_l", "move_info_window_r"]),
            "runtime_status": "metadata_only",
            "unsupported": ["battle_hud_runtime_pending"],
        },
        "gimmick_triggers": {
            "textures": _texture_refs(textures, GIMMICK_TRIGGER_TEXTURES),
            "source_anim_frames": {"off": 0, "on": 16},
            "runtime_status": "metadata_only",
            "unsupported": ["battle_hud_runtime_pending"],
        },
        "gimmick_indicators": {
            "textures": _texture_refs(textures, GIMMICK_INDICATOR_TEXTURES),
            "runtime_status": "metadata_only",
            "unsupported": ["battle_hud_runtime_pending"],
        },
    }


def export_battle_interface(source_root, output_data_root, output_asset_root):
    definitions = _parse_graphics_definitions(source_root)
    textures, texture_order = _build_texture_inventory(source_root, output_asset_root, definitions)
    source_colors, source_color_order = _build_source_color_provenance(source_root)
    tilemaps, tilemap_order, tilemap_warnings = _build_tilemaps(source_root, output_asset_root)
    font_atlases = _build_source_font_atlases(source_root, output_asset_root)
    window_templates = _parse_window_templates(source_root)
    window_template_composite_rect_count = _attach_textbox_composite_window_rects(window_templates, tilemaps)
    window_text_info, text_printer = _parse_battle_window_text_info(source_root)
    source_font_atlas_binding_count = _attach_font_atlas_bindings(text_printer.get("font_metrics", {}), font_atlases)
    battle_window_text_info_count = _attach_battle_window_text_info(window_templates, window_text_info)
    sections = _build_interface_sections(source_root, textures)

    stats = {
        "texture_count": len(texture_order),
        "source_png_asset_count": len(list((source_root / BATTLE_INTERFACE_DIR).glob("*.png"))),
        "source_color_file_count": len(source_color_order),
        "source_binary_tilemap_count": len(tilemap_order),
        "tilemap_composite_count": sum(
            1 for record in tilemaps.values()
            if isinstance(record, dict) and isinstance(record.get("tilemap_composite"), dict)
        ),
        "window_template_count": len(window_templates),
        "window_template_composite_rect_count": window_template_composite_rect_count,
        "battle_window_text_info_count": battle_window_text_info_count,
        "source_font_metric_count": int(text_printer.get("font_metrics", {}).get("font_count", 0)),
        "source_font_atlas_count": len(font_atlases),
        "source_font_atlas_binding_count": source_font_atlas_binding_count,
        "latin_width_table_count": len([
            record for record in text_printer.get("font_metrics", {}).get("fonts", {}).values()
            if isinstance(record, dict) and record.get("latin_width_count", 0)
        ]),
        "healthbox_coord_group_count": len(sections["healthbox"].get("coords", {})),
        "healthbox_frame_texture_count": len(sections["healthbox"].get("frame_textures", [])),
        "healthbox_element_texture_count": len(sections["healthbox"].get("element_textures", [])),
        "gimmick_trigger_texture_count": len(sections["gimmick_triggers"].get("textures", [])),
        "gimmick_indicator_texture_count": len(sections["gimmick_indicators"].get("textures", [])),
        "missing_texture_count": len([
            name for name in HEALTHBOX_FRAME_TEXTURES + HEALTHBOX_ELEMENT_TEXTURES + GIMMICK_TRIGGER_TEXTURES + GIMMICK_INDICATOR_TEXTURES
            if name not in textures
        ]),
        "tilemap_warning_count": len(tilemap_warnings),
    }

    data = {
        "schema_version": 1,
        "generated_by": "tools/importer/export_battle_interface.py",
        "source_files": [
            to_project_path(BATTLE_INTERFACE_DIR),
            to_project_path(GRAPHICS_SOURCE),
            to_project_path(BATTLE_BG_SOURCE),
            to_project_path(BATTLE_MESSAGE_SOURCE),
            to_project_path(TEXT_SOURCE),
            to_project_path(CHINESE_TEXT_SOURCE),
            to_project_path(FONTS_SOURCE),
            to_project_path(TEXT_HEADER_SOURCE),
            to_project_path(BATTLE_INTERFACE_SOURCE),
            to_project_path(BATTLE_SCRIPT_COMMANDS_SOURCE),
            to_project_path(GIMMICKS_SOURCE),
            to_project_path(BATTLE_CONFIG_SOURCE),
            to_project_path(TEXT_CONFIG_SOURCE),
            to_project_path(GLOBAL_CONSTANTS_SOURCE),
        ],
        "runtime_color_policy": {
            "status": "no_runtime_palette",
            "source_color_files": "import_only_provenance",
            "variant_rule": "distinct visible color variants must be exported as distinct RGBA images",
            "effect_rule": "source-visible color changes, flashes, fades, blends, scaling, rotation, and affine motion use Godot Shader, Material, Animation, or resource parameters",
        },
        "rendering_notes": {
            "gba_hardware_constraints": "decoded_at_import_time",
            "godot_runtime_asset_model": "ordinary RGBA textures plus source metadata",
            "visible_viewport": VISIBLE_VIEWPORT,
            "hud_runtime_status": "unsupported",
            "shader_material_status": "planned",
            "audio_status": "metadata_only",
        },
        "texture_order": texture_order,
        "textures": textures,
        "source_font_atlases": font_atlases,
        "source_graphics_definitions": definitions,
        "source_color_order": source_color_order,
        "source_color_provenance": source_colors,
        "tilemap_order": tilemap_order,
        "tilemaps": tilemaps,
        "window_template_order": sorted(window_templates.keys()),
        "window_templates": window_templates,
        "window_text_info_order": sorted(window_text_info.keys()),
        "window_text_info": window_text_info,
        "text_printer": text_printer,
        "sections": sections,
        "unsupported": [
            {
                "code": "battle_interface_runtime_pending",
                "status": "unsupported",
                "note": "Source interface graphics, tilemap metadata, windows, and coordinates are imported; source-equivalent HUD rendering and interaction sequencing are not implemented yet.",
            },
            {
                "code": "battle_hud_runtime_pending",
                "status": "unsupported",
                "note": "Healthbox, party summary, ability popup, last-used-ball, move-info, and gimmick indicator playback remain future presentation work.",
            },
            {
                "code": "battle_audio_playback_pending",
                "status": "metadata_only",
                "note": "Interface sound cue symbols and timing intent are preserved as metadata only.",
            },
        ],
        "warnings": tilemap_warnings,
        "stats": stats,
    }

    output_path = output_data_root / "battle" / "interface.json"
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

    output_path, data = export_battle_interface(source_root, output_data_root, output_asset_root)
    manifest_entry = {
        "category": ASSET_CATEGORY,
        "path": to_project_path(output_path),
        "texture_count": int(data["stats"]["texture_count"]),
        "window_template_count": int(data["stats"]["window_template_count"]),
        "tilemap_composite_count": int(data["stats"]["tilemap_composite_count"]),
    }
    write_manifest(
        output_data_root / "import_manifest.json",
        exported_battle=[manifest_entry],
        generator="tools/importer/export_battle_interface.py",
    )
    print(json.dumps({"exported": manifest_entry, "stats": data["stats"]}, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
