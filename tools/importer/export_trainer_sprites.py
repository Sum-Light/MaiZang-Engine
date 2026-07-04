#!/usr/bin/env python3
"""Export first-pass trainer battle sprite metadata and PNG assets."""

import argparse
import json
import re
import sys
from pathlib import Path

from export_map import to_project_path, write_json, write_manifest
from source_probe import load_config


GRAPHICS_SOURCE = Path("src/data/graphics/trainers.h")
TRAINER_CONSTANTS_SOURCE = Path("include/constants/trainers.h")
BATTLE_TRANSITION_HEADER = Path("include/battle_transition.h")
BATTLE_TRANSITION_SOURCE = Path("src/battle_transition.c")
ASSET_CATEGORY = "trainer_sprites"
ASSET_OUTPUT_DIR = "trainers"

BINARY_ASSET_EXTENSIONS = [
    (".4bpp.smol", ".png"),
    (".4bpp.lz", ".png"),
    (".4bpp", ".png"),
    (".gbapal", ".pal"),
]


def _read_json(path):
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def _strip_comment(line):
    return line.split("//", 1)[0].strip()


def _parse_int_expr(value, constants=None, default=None):
    text = str(value).strip()
    constants = constants or {}
    while text.startswith("(") and text.endswith(")"):
        text = text[1:-1].strip()
    if text in constants:
        return constants[text]["value"] if isinstance(constants[text], dict) else constants[text]
    try:
        return int(text, 0)
    except ValueError:
        pass
    match = re.match(r"^(\w+)\s*-\s*(\w+)$", text)
    if match is not None:
        left, right = match.groups()
        if left in constants and right in constants:
            left_value = constants[left]["value"] if isinstance(constants[left], dict) else constants[left]
            right_value = constants[right]["value"] if isinstance(constants[right], dict) else constants[right]
            return int(left_value) - int(right_value)
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
                value = parsed_value + 1
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


def _parse_graphics_definitions(source_root, relative_path):
    source_path = source_root / relative_path
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
                "source_file": to_project_path(relative_path),
                "source_line": line_no,
                "source_trace": "{}:{}".format(to_project_path(relative_path), symbol),
            }
    return definitions


def _source_asset_path(binary_path):
    text = to_project_path(binary_path)
    for old_ext, new_ext in BINARY_ASSET_EXTENSIONS:
        if text.endswith(old_ext):
            return Path(text[: -len(old_ext)] + new_ext)
    return Path(text)


def _open_source_image(image_module, source_path):
    image = image_module.open(source_path)
    if image.mode == "P":
        alpha = image_module.new("L", image.size, 255)
        alpha.putdata([0 if pixel == 0 else 255 for pixel in image.getdata()])
        converted = image.convert("RGBA")
        converted.putalpha(alpha)
        image.close()
        return converted
    return image.convert("RGBA")


def _write_png_asset(source_path, output_path):
    from PIL import Image

    output_path.parent.mkdir(parents=True, exist_ok=True)
    image = _open_source_image(Image, source_path)
    try:
        image.save(output_path)
        return {"w": int(image.width), "h": int(image.height)}
    finally:
        image.close()


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


def _read_png_palette(path, limit=16):
    from PIL import Image

    image = Image.open(path)
    try:
        if image.mode == "P":
            raw_palette = image.getpalette() or []
            colors = []
            for index in range(0, min(len(raw_palette), limit * 3), 3):
                colors.append({
                    "r": int(raw_palette[index]),
                    "g": int(raw_palette[index + 1]),
                    "b": int(raw_palette[index + 2]),
                })
            return colors
        converted = image.convert("RGBA")
        seen = []
        for pixel in converted.getdata():
            rgb = {"r": int(pixel[0]), "g": int(pixel[1]), "b": int(pixel[2])}
            if rgb not in seen:
                seen.append(rgb)
            if len(seen) >= limit:
                break
        return seen
    finally:
        image.close()


def _split_macro_args(argument_text):
    args = []
    current = []
    depth = 0
    for char in argument_text:
        if char == "(":
            depth += 1
        elif char == ")":
            depth -= 1
        if char == "," and depth == 0:
            args.append("".join(current).strip())
            current = []
            continue
        current.append(char)
    if current:
        args.append("".join(current).strip())
    return args


def _parse_macro_rows(source_root, macro_name):
    source_path = source_root / GRAPHICS_SOURCE
    pattern = re.compile(r"\b%s\((.*)\)\s*,?" % re.escape(macro_name))
    rows = []
    with source_path.open("r", encoding="utf-8", errors="replace") as handle:
        for line_no, line in enumerate(handle, start=1):
            if line.lstrip().startswith("#define"):
                continue
            match = pattern.search(line)
            if match is None:
                continue
            args = _split_macro_args(match.group(1))
            rows.append({
                "args": args,
                "source": {
                    "file": to_project_path(GRAPHICS_SOURCE),
                    "line": line_no,
                },
                "source_line": line.strip(),
            })
    return rows


def _build_texture(kind, source_symbol, definitions, source_root, output_dir, output_name):
    entry = {
        "kind": kind,
        "source_symbol": source_symbol,
        "status": "missing_source_reference",
    }
    if not source_symbol:
        return entry
    definition = definitions.get(source_symbol)
    if definition is None:
        entry["status"] = "missing_source_definition"
        return entry
    source_image_rel = _source_asset_path(definition["source_binary_path"])
    source_image_path = source_root / source_image_rel
    entry.update({
        "source_binary_path": definition["source_binary_path"],
        "source_image_path": to_project_path(source_image_rel),
        "source_file": definition["source_file"],
        "source_line": definition["source_line"],
        "source_trace": [definition["source_trace"]],
    })
    if not source_image_path.exists():
        entry["status"] = "missing_source_png"
        return entry
    output_path = output_dir / output_name
    image_size = _write_png_asset(source_image_path, output_path)
    entry.update({
        "status": "imported",
        "image": "res://{}".format(to_project_path(output_path)),
        "image_project_path": to_project_path(output_path),
        "image_size": image_size,
        "transparency": {
            "source_palette_index": 0,
            "rule": "gba_obj_or_trainer_palette_index_0_alpha_0",
        },
    })
    return entry


def _build_palette(kind, source_symbol, definitions, source_root):
    entry = {
        "kind": kind,
        "source_symbol": source_symbol,
        "status": "missing_source_reference",
    }
    if not source_symbol:
        return entry
    definition = definitions.get(source_symbol)
    if definition is None:
        entry["status"] = "missing_source_definition"
        return entry
    source_palette_rel = _source_asset_path(definition["source_binary_path"])
    source_palette_path = source_root / source_palette_rel
    entry.update({
        "source_binary_path": definition["source_binary_path"],
        "source_palette_path": to_project_path(source_palette_rel),
        "source_file": definition["source_file"],
        "source_line": definition["source_line"],
        "source_trace": [definition["source_trace"]],
    })
    if not source_palette_path.exists():
        fallback_image_rel = Path(str(source_palette_rel.with_suffix(".png")))
        fallback_image_path = source_root / fallback_image_rel
        if not fallback_image_path.exists():
            entry["status"] = "missing_source_palette"
            return entry
        colors = _read_png_palette(fallback_image_path)
        entry.update({
            "status": "metadata_only",
            "color_count": len(colors),
            "colors_rgb": colors,
            "source_palette_fallback_image_path": to_project_path(fallback_image_rel),
            "fallback_rule": "source .gbapal has no checked-in .pal companion; extracted first 16 PNG palette entries for Godot metadata",
            "runtime_note": "Stored as Godot-side palette metadata; palette swaps/blends are later Godot-native material tasks.",
        })
        return entry
    colors = _read_jasc_palette(source_palette_path)
    entry.update({
        "status": "metadata_only",
        "color_count": len(colors),
        "colors_rgb": colors,
        "runtime_note": "Stored as Godot-side palette metadata; palette swaps/blends are later Godot-native material tasks.",
    })
    return entry


def _asset_name_from_definition(definitions, source_symbol, fallback_symbol):
    definition = definitions.get(source_symbol)
    if definition is not None:
        return _source_asset_path(definition["source_binary_path"]).stem
    name = fallback_symbol
    for prefix in ("TRAINER_PIC_FRONT_", "TRAINER_PIC_BACK_"):
        if name.startswith(prefix):
            name = name[len(prefix):]
    return re.sub(r"[^A-Za-z0-9]+", "_", name).strip("_").lower() or "unknown"


def _build_front_sprites(source_root, output_asset_root, definitions, pic_constants):
    output_dir = output_asset_root / ASSET_OUTPUT_DIR / "front_pics"
    sprites = {}
    order = []
    for row in _parse_macro_rows(source_root, "TRAINER_SPRITE"):
        args = row["args"]
        if len(args) < 3:
            continue
        pic_symbol, pic_source_symbol, palette_source_symbol = args[:3]
        asset_name = _asset_name_from_definition(definitions, pic_source_symbol, pic_symbol)
        texture = _build_texture(
            "front",
            pic_source_symbol,
            definitions,
            source_root,
            output_dir,
            "{}.png".format(asset_name),
        )
        palette = _build_palette("front", palette_source_symbol, definitions, source_root)
        if row["source"]:
            texture.setdefault("source_trace", []).append("{}:{}".format(row["source"]["file"], row["source"]["line"]))
            palette.setdefault("source_trace", []).append("{}:{}".format(row["source"]["file"], row["source"]["line"]))
        mugshot_x = _parse_int_expr(args[3], default=0) if len(args) > 3 else 0
        mugshot_y = _parse_int_expr(args[4], default=0) if len(args) > 4 else 0
        mugshot_rotation = _parse_int_expr(args[5], default=0x200) if len(args) > 5 else 0x200
        imported = texture.get("status") == "imported"
        palette_ready = palette.get("status") == "metadata_only"
        record = {
            "pic_symbol": pic_symbol,
            "numeric_id": int(pic_constants.get(pic_symbol, {}).get("value", -1)),
            "asset_name": asset_name,
            "front": texture,
            "palette": palette,
            "mugshot": {
                "status": "metadata_only",
                "coords": {
                    "x": int(mugshot_x),
                    "y": int(mugshot_y),
                    "source_defaults": len(args) <= 3,
                },
                "rotation_scale": int(mugshot_rotation),
                "source": row["source"],
            },
            "slide": {
                "status": "metadata_only",
                "opponent_draw_trainer_pic": {
                    "y": 40,
                    "x_single": 176,
                    "x_multi_first": 200,
                    "x_multi_second": 152,
                    "x2_initial": -240,
                    "speed_x": 2,
                    "source_function": "OpponentHandleDrawTrainerPic -> BtlController_HandleDrawTrainerPic",
                },
                "trainer_slide": {
                    "x": 176,
                    "y": 40,
                    "x2_initial": 96,
                    "x_add_after_create": 32,
                    "speed_x": -2,
                    "source_function": "BtlController_HandleTrainerSlide",
                },
            },
            "coverage": {
                "asset_status": "first_pass" if imported and palette_ready else "unsupported",
                "palette_status": "metadata_only" if palette_ready else "unsupported",
                "mugshot_status": "metadata_only",
                "slide_status": "metadata_only",
                "runtime_status": "unsupported",
            },
            "trainers": [],
            "trainer_count": 0,
            "source": row["source"],
            "source_line": row["source_line"],
            "unsupported": [] if imported and palette_ready else ["trainer_asset_import_pending"],
        }
        sprites[pic_symbol] = record
        order.append(pic_symbol)
    return sprites, order


def _build_back_sprites(source_root, output_asset_root, definitions, pic_constants):
    output_dir = output_asset_root / ASSET_OUTPUT_DIR / "back_pics"
    sprites = {}
    order = []
    for row in _parse_macro_rows(source_root, "TRAINER_BACK_SPRITE"):
        args = row["args"]
        if len(args) < 5:
            continue
        pic_symbol, y_offset_expr, pic_source_symbol, palette_source_symbol, anim_symbol = args[:5]
        asset_name = _asset_name_from_definition(definitions, pic_source_symbol, pic_symbol)
        texture = _build_texture(
            "back",
            pic_source_symbol,
            definitions,
            source_root,
            output_dir,
            "{}.png".format(asset_name),
        )
        palette = _build_palette("back", palette_source_symbol, definitions, source_root)
        if row["source"]:
            texture.setdefault("source_trace", []).append("{}:{}".format(row["source"]["file"], row["source"]["line"]))
            palette.setdefault("source_trace", []).append("{}:{}".format(row["source"]["file"], row["source"]["line"]))
        y_offset = _parse_int_expr(y_offset_expr, default=0)
        imported = texture.get("status") == "imported"
        palette_ready = palette.get("status") == "metadata_only"
        record = {
            "pic_symbol": pic_symbol,
            "numeric_id": int(pic_constants.get(pic_symbol, {}).get("value", -1)),
            "asset_name": asset_name,
            "back": texture,
            "palette": palette,
            "animation": {
                "status": "metadata_only",
                "source_symbol": anim_symbol,
                "runtime_status": "unsupported",
                "unsupported": ["battle_animation_runtime_pending"],
            },
            "coordinates": {
                "size": 8,
                "y_offset": int(y_offset),
                "source_y_position_expression": "(8 - coordinates.size) * 4 + 80",
                "source_y_position_value": (8 - 8) * 4 + 80,
            },
            "slide": {
                "status": "metadata_only",
                "player_trainer_slide": {
                    "x": 80,
                    "y_expression": "(8 - gTrainerBacksprites[trainerPicId].coordinates.size) * 4 + 80",
                    "y": 80,
                    "x2_initial": -96,
                    "speed_x": 2,
                    "source_function": "BtlController_HandleTrainerSlide",
                },
                "player_draw_trainer_pic": {
                    "x2_initial": 240,
                    "speed_x": -2,
                    "source_function": "BtlController_HandleDrawTrainerPic",
                },
            },
            "coverage": {
                "asset_status": "first_pass" if imported and palette_ready else "unsupported",
                "palette_status": "metadata_only" if palette_ready else "unsupported",
                "animation_status": "metadata_only",
                "slide_status": "metadata_only",
                "runtime_status": "unsupported",
            },
            "source": row["source"],
            "source_line": row["source_line"],
            "unsupported": ["battle_animation_runtime_pending"] + ([] if imported and palette_ready else ["trainer_asset_import_pending"]),
        }
        sprites[pic_symbol] = record
        order.append(pic_symbol)
    return sprites, order


def _parse_mugshot_palette_table(source_root, transition_definitions, mugshot_constants):
    mapping_re = re.compile(r"\[(MUGSHOT_COLOR_\w+)\]\s*=\s*(sMugshotPal_\w+)")
    records = {}
    source_path = source_root / BATTLE_TRANSITION_SOURCE
    with source_path.open("r", encoding="utf-8", errors="replace") as handle:
        for line_no, line in enumerate(handle, start=1):
            match = mapping_re.search(line)
            if match is None:
                continue
            color_symbol, palette_symbol = match.groups()
            palette = _build_palette("mugshot_bg", palette_symbol, transition_definitions, source_root)
            palette.setdefault("source_trace", []).append("{}:{}".format(to_project_path(BATTLE_TRANSITION_SOURCE), line_no))
            records[color_symbol] = {
                "color_symbol": color_symbol,
                "numeric_id": int(mugshot_constants.get(color_symbol, {}).get("value", -1)),
                "palette": palette,
                "status": "metadata_only" if palette.get("status") == "metadata_only" else "unsupported",
                "source": {
                    "file": to_project_path(BATTLE_TRANSITION_SOURCE),
                    "line": line_no,
                },
            }
    records["MUGSHOT_COLOR_NONE"] = {
        "color_symbol": "MUGSHOT_COLOR_NONE",
        "numeric_id": int(mugshot_constants.get("MUGSHOT_COLOR_NONE", {}).get("value", 0)),
        "palette": {
            "kind": "mugshot_bg",
            "status": "not_used",
            "source_symbol": "",
        },
        "status": "metadata_only",
        "source": mugshot_constants.get("MUGSHOT_COLOR_NONE", {}).get("source", {}),
    }
    return records


def _build_trainer_records(trainers_data, front_sprites, mugshot_palettes):
    trainers = {}
    for trainer_symbol in trainers_data.get("trainer_order", []):
        trainer = trainers_data.get("trainers", {}).get(trainer_symbol, {})
        pic = trainer.get("pic", {}) if isinstance(trainer.get("pic"), dict) else {}
        back_pic = trainer.get("back_pic", {}) if isinstance(trainer.get("back_pic"), dict) else {}
        mugshot = trainer.get("mugshot", {}) if isinstance(trainer.get("mugshot"), dict) else {}
        pic_symbol = str(pic.get("symbol", ""))
        sprite = front_sprites.get(pic_symbol, {})
        mugshot_symbol = str(mugshot.get("symbol", "MUGSHOT_COLOR_NONE") or "MUGSHOT_COLOR_NONE")
        mugshot_palette = mugshot_palettes.get(mugshot_symbol, mugshot_palettes.get("MUGSHOT_COLOR_NONE", {}))
        first_pass = (
            isinstance(sprite, dict)
            and sprite.get("coverage", {}).get("asset_status") == "first_pass"
        )
        unsupported = ["battle_animation_runtime_pending", "battle_audio_playback_pending"]
        if not first_pass:
            unsupported.append("trainer_asset_import_pending")
        record = {
            "trainer_symbol": trainer_symbol,
            "numeric_id": int(trainer.get("id", -1)),
            "trainer_class": trainer.get("trainer_class", {}),
            "pic": pic,
            "back_pic": back_pic,
            "sprite_ref": {
                "pic_symbol": pic_symbol,
                "numeric_id": int(pic.get("value", -1)) if pic.get("value") is not None else -1,
                "resolved": first_pass,
            },
            "front": sprite.get("front", {}) if isinstance(sprite, dict) else {},
            "palette": sprite.get("palette", {}) if isinstance(sprite, dict) else {},
            "mugshot": {
                "color": mugshot,
                "palette_ref": mugshot_palette,
                "trainer_sprite_coords": sprite.get("mugshot", {}) if isinstance(sprite, dict) else {},
                "transition_status": "metadata_only" if mugshot_symbol != "MUGSHOT_COLOR_NONE" else "not_used",
                "runtime_status": "unsupported" if mugshot_symbol != "MUGSHOT_COLOR_NONE" else "not_used",
                "unsupported": ["battle_animation_runtime_pending", "battle_audio_playback_pending"] if mugshot_symbol != "MUGSHOT_COLOR_NONE" else [],
            },
            "slide": sprite.get("slide", {}) if isinstance(sprite, dict) else {},
            "coverage": {
                "asset_status": "first_pass" if first_pass else "unsupported",
                "palette_status": "metadata_only" if first_pass else "unsupported",
                "mugshot_status": "metadata_only",
                "slide_status": "metadata_only" if first_pass else "unsupported",
                "runtime_status": "unsupported",
                "audio_status": "metadata_only",
            },
            "source": trainer.get("source", {}),
            "unsupported": sorted(set(unsupported)),
        }
        trainers[trainer_symbol] = record
        if isinstance(sprite, dict) and sprite:
            sprite.setdefault("trainers", []).append(trainer_symbol)
            sprite["trainer_count"] = len(sprite["trainers"])
    return trainers


def _build_stats(front_sprites, back_sprites, trainers, mugshot_palettes, definition_count):
    used_front = {
        record.get("sprite_ref", {}).get("pic_symbol")
        for record in trainers.values()
        if record.get("sprite_ref", {}).get("pic_symbol")
    }
    return {
        "trainer_count": len(trainers),
        "front_sprite_count": len(front_sprites),
        "front_textures_imported": sum(1 for record in front_sprites.values() if record.get("front", {}).get("status") == "imported"),
        "front_palette_metadata_count": sum(1 for record in front_sprites.values() if record.get("palette", {}).get("status") == "metadata_only"),
        "unique_front_sprite_used_count": len(used_front),
        "trainer_records_with_sprite": sum(1 for record in trainers.values() if record.get("coverage", {}).get("asset_status") == "first_pass"),
        "trainer_records_missing_sprite": sum(1 for record in trainers.values() if record.get("coverage", {}).get("asset_status") != "first_pass"),
        "first_pass_asset_trainer_count": sum(1 for record in trainers.values() if record.get("coverage", {}).get("asset_status") == "first_pass"),
        "mugshot_trainer_count": sum(1 for record in trainers.values() if record.get("mugshot", {}).get("transition_status") == "metadata_only"),
        "mugshot_palette_metadata_count": sum(1 for record in mugshot_palettes.values() if record.get("status") == "metadata_only" and record.get("color_symbol") != "MUGSHOT_COLOR_NONE"),
        "back_sprite_count": len(back_sprites),
        "back_textures_imported": sum(1 for record in back_sprites.values() if record.get("back", {}).get("status") == "imported"),
        "back_palette_metadata_count": sum(1 for record in back_sprites.values() if record.get("palette", {}).get("status") == "metadata_only"),
        "graphics_definition_count": definition_count,
    }


def export_trainer_sprites(source_root, output_data_root, output_asset_root):
    trainers_data = _read_json(output_data_root / "pokemon" / "trainers.json")
    graphics_definitions = _parse_graphics_definitions(source_root, GRAPHICS_SOURCE)
    transition_definitions = _parse_graphics_definitions(source_root, BATTLE_TRANSITION_SOURCE)
    pic_constants, pic_order = _parse_enum_constants(
        source_root / TRAINER_CONSTANTS_SOURCE,
        "enum __attribute__((packed)) TrainerPicID",
        "TRAINER_PIC_",
    )
    mugshot_constants, mugshot_order = _parse_enum_constants(
        source_root / BATTLE_TRANSITION_HEADER,
        "enum MugshotColor",
        "MUGSHOT_COLOR_",
    )
    output_asset_root.mkdir(parents=True, exist_ok=True)
    front_sprites, front_order = _build_front_sprites(source_root, output_asset_root, graphics_definitions, pic_constants)
    back_sprites, back_order = _build_back_sprites(source_root, output_asset_root, graphics_definitions, pic_constants)
    mugshot_palettes = _parse_mugshot_palette_table(source_root, transition_definitions, mugshot_constants)
    trainers = _build_trainer_records(trainers_data, front_sprites, mugshot_palettes)
    stats = _build_stats(
        front_sprites,
        back_sprites,
        trainers,
        mugshot_palettes,
        len(graphics_definitions),
    )

    data = {
        "schema_version": 1,
        "category": ASSET_CATEGORY,
        "source": {
            "project": "pokeemerald-expansion",
            "kind": "first_pass_trainer_battle_sprites",
            "graphics_source": to_project_path(GRAPHICS_SOURCE),
            "trainer_constants": to_project_path(TRAINER_CONSTANTS_SOURCE),
            "battle_transition_source": to_project_path(BATTLE_TRANSITION_SOURCE),
            "trainers_source": "data/generated/pokemon/trainers.json",
            "runtime_references": [
                "src/battle_controller_opponent.c:OpponentHandleDrawTrainerPic",
                "src/battle_controllers.c:BtlController_HandleDrawTrainerPic",
                "src/battle_controllers.c:BtlController_HandleTrainerSlide",
                "src/battle_transition.c:Task_Mugshot",
                "src/battle_transition.c:Mugshots_CreateTrainerPics",
            ],
            "audio_status": "metadata_only",
            "runtime_status": "unsupported",
        },
        "pic_constant_order": pic_order,
        "mugshot_constant_order": mugshot_order,
        "front_sprite_order": front_order,
        "front_sprites": front_sprites,
        "back_sprite_order": back_order,
        "back_sprites": back_sprites,
        "mugshot_palettes": mugshot_palettes,
        "trainer_order": trainers_data.get("trainer_order", []),
        "trainers": trainers,
        "stats": stats,
    }
    output_path = output_data_root / "battle" / "trainer_sprites.json"
    write_json(output_path, data)
    return output_path, data


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, help="JSON config with source and output roots.")
    parser.add_argument("--source", type=Path, help="pokeemerald-expansion source root.")
    parser.add_argument("--output-data-root", type=Path, help="Generated data output root.")
    parser.add_argument("--output-asset-root", type=Path, help="Generated asset output root.")
    args = parser.parse_args(argv)

    config = load_config(args.config)
    source_root = args.source or Path(config.get("source_root", ""))
    output_data_root = args.output_data_root or Path(config.get("generated_data_root", "data/generated"))
    output_asset_root = args.output_asset_root or Path(config.get("generated_asset_root", "assets/generated"))

    output_path, data = export_trainer_sprites(source_root, output_data_root, output_asset_root)
    stats = data["stats"]
    manifest_entry = {
        "category": data["category"],
        "path": to_project_path(output_path),
        "trainer_count": stats["trainer_count"],
        "front_sprite_count": stats["front_sprite_count"],
        "front_texture_count": stats["front_textures_imported"],
        "back_sprite_count": stats["back_sprite_count"],
        "back_texture_count": stats["back_textures_imported"],
        "first_pass_asset_trainer_count": stats["first_pass_asset_trainer_count"],
        "mugshot_trainer_count": stats["mugshot_trainer_count"],
        "audio_status": "metadata_only",
    }
    write_manifest(
        output_data_root / "import_manifest.json",
        exported_battle=[manifest_entry],
        generator="tools/importer/export_trainer_sprites.py",
    )
    print(json.dumps({"exported": manifest_entry}, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
