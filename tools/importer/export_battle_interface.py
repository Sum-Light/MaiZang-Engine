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
VISIBLE_VIEWPORT = {"w": 240, "h": 160}
TILE_SIZE = 8

BATTLE_INTERFACE_DIR = Path("graphics/battle_interface")
GRAPHICS_SOURCE = Path("src/graphics.c")
BATTLE_BG_SOURCE = Path("src/battle_bg.c")
BATTLE_INTERFACE_SOURCE = Path("src/battle_interface.c")
BATTLE_SCRIPT_COMMANDS_SOURCE = Path("src/battle_script_commands.c")
GIMMICKS_SOURCE = Path("src/data/graphics/gimmicks.h")

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


def _strip_comment(line):
    return line.split("//", 1)[0].strip()


def _parse_int_expr(value):
    value = str(value).strip()
    if not value:
        return None
    try:
        return int(value, 0)
    except ValueError:
        return None


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
    window_templates = _parse_window_templates(source_root)
    window_template_composite_rect_count = _attach_textbox_composite_window_rects(window_templates, tilemaps)
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
            to_project_path(BATTLE_INTERFACE_SOURCE),
            to_project_path(BATTLE_SCRIPT_COMMANDS_SOURCE),
            to_project_path(GIMMICKS_SOURCE),
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
        "source_graphics_definitions": definitions,
        "source_color_order": source_color_order,
        "source_color_provenance": source_colors,
        "tilemap_order": tilemap_order,
        "tilemaps": tilemaps,
        "window_template_order": sorted(window_templates.keys()),
        "window_templates": window_templates,
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
