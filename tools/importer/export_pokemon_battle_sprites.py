#!/usr/bin/env python3
"""Export first-pass Pokemon battle sprite metadata and PNG assets."""

import argparse
import json
import re
import sys
from pathlib import Path

from export_map import to_project_path, write_json, write_manifest
from source_probe import load_config


GRAPHICS_SOURCE = Path("src/data/graphics/pokemon.h")
ASSET_CATEGORY = "battle_sprites"
ASSET_OUTPUT_DIR = "pokemon_battle"

IMAGE_ASSETS = [
    ("front", "front_pic", "frontPicSize", "front.png"),
    ("back", "back_pic", "backPicSize", "back.png"),
    ("female_front", "front_pic_female", "frontPicSizeFemale", "female_front.png"),
    ("female_back", "back_pic_female", "backPicSizeFemale", "female_back.png"),
    ("icon", "icon_sprite", "", "icon.png"),
    ("female_icon", "icon_sprite_female", "", "female_icon.png"),
]
PALETTE_ASSETS = [
    ("normal", "palette"),
    ("shiny", "shiny_palette"),
    ("female_normal", "palette_female"),
    ("female_shiny", "shiny_palette_female"),
]
BINARY_ASSET_EXTENSIONS = [
    (".4bpp.smol", ".png"),
    (".4bpp.lz", ".png"),
    (".4bpp", ".png"),
    (".1bpp", ".png"),
    (".gbapal", ".pal"),
]


def _read_json(path):
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def _species_asset_dir(species_symbol):
    name = species_symbol
    if name.startswith("SPECIES_"):
        name = name[len("SPECIES_"):]
    name = re.sub(r"[^A-Za-z0-9]+", "_", name).strip("_").lower()
    return name or "unknown"


def _definition_score(path):
    lower = path.lower()
    score = 0
    if "_gba" in lower:
        score += 100
    if "/overworld" in lower:
        score += 10
    return score


def _parse_graphics_definitions(source_root):
    source_path = source_root / GRAPHICS_SOURCE
    definition_re = re.compile(
        r'^\s*const\s+\w+\s+(\w+)\[\]\s*=\s*INCBIN_\w+\("([^"]+)"\)'
    )
    definitions = {}
    duplicate_count = 0
    with source_path.open("r", encoding="utf-8", errors="replace") as handle:
        for line_no, line in enumerate(handle, start=1):
            match = definition_re.search(line)
            if match is None:
                continue
            symbol, binary_path = match.groups()
            record = {
                "symbol": symbol,
                "source_binary_path": binary_path,
                "source_file": to_project_path(GRAPHICS_SOURCE),
                "source_line": line_no,
                "source_trace": "{}:{}".format(to_project_path(GRAPHICS_SOURCE), symbol),
            }
            previous = definitions.get(symbol)
            if previous is not None:
                duplicate_count += 1
            if previous is None or _definition_score(binary_path) < _definition_score(previous["source_binary_path"]):
                definitions[symbol] = record
    return definitions, {
        "source_file": to_project_path(GRAPHICS_SOURCE),
        "definition_count": len(definitions),
        "duplicate_symbol_count": duplicate_count,
        "selection_rule": "prefer non-_gba source PNG/palette paths when both modern and GBA branches define the same symbol",
    }


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


def _strip_outer_parens(expr):
    text = expr.strip()
    while text.startswith("(") and text.endswith(")"):
        depth = 0
        encloses = True
        for index, char in enumerate(text):
            if char == "(":
                depth += 1
            elif char == ")":
                depth -= 1
                if depth == 0 and index != len(text) - 1:
                    encloses = False
                    break
        if not encloses:
            break
        text = text[1:-1].strip()
    return text


def _split_top_level_ternary(expr):
    depth = 0
    question_index = -1
    for index, char in enumerate(expr):
        if char == "(":
            depth += 1
        elif char == ")":
            depth -= 1
        elif char == "?" and depth == 0 and question_index < 0:
            question_index = index
        elif char == ":" and depth == 0 and question_index >= 0:
            return (
                expr[:question_index].strip(),
                expr[question_index + 1 : index].strip(),
                expr[index + 1 :].strip(),
            )
    return None


def _select_modern_expr(value):
    if value is None:
        return ""
    text = _strip_outer_parens(str(value))
    split = _split_top_level_ternary(text)
    if split is None:
        return text
    condition, true_expr, false_expr = split
    normalized_condition = condition.replace(" ", "")
    if normalized_condition in {
        "P_GBA_STYLE_SPECIES_GFX",
        "P_GBA_STYLE_SPECIES_ICONS",
        "P_GBA_STYLE_SPECIES_FOOTPRINTS",
    }:
        return _select_modern_expr(false_expr)
    if normalized_condition in {
        "!P_GBA_STYLE_SPECIES_GFX",
        "!P_GBA_STYLE_SPECIES_ICONS",
        "!P_GBA_STYLE_SPECIES_FOOTPRINTS",
    }:
        return _select_modern_expr(true_expr)
    return text


def _parse_int_expr(value, default=None):
    selected = _select_modern_expr(value)
    if selected == "":
        return default
    try:
        return int(selected, 0)
    except ValueError:
        return default


def _parse_mon_coords(value):
    expression = "" if value is None else str(value)
    selected = _select_modern_expr(expression)
    match = re.search(r"MON_COORDS_SIZE\(\s*(\d+)\s*,\s*(\d+)\s*\)", selected)
    result = {
        "source_expression": expression,
        "selected_expression": selected,
    }
    if match is not None:
        result.update({
            "w": int(match.group(1)),
            "h": int(match.group(2)),
            "status": "metadata_only",
        })
    elif selected:
        result["status"] = "unparsed"
    else:
        result["status"] = "missing"
    return result


def _parse_front_anim_frames(value):
    text = "" if value is None else str(value)
    frames = []
    for match in re.finditer(r"ANIMCMD_FRAME\(\s*([^,]+)\s*,\s*([^)]+)\)", text):
        frame = _parse_int_expr(match.group(1))
        duration = _parse_int_expr(match.group(2))
        frames.append({
            "frame": frame,
            "duration_frames": duration,
            "source": match.group(0),
        })
    return frames


def _build_image_asset(kind, ref_key, raw_size_key, asset_name, refs, raw_fields, definitions, source_root, output_dir, species_dir):
    source_symbol = str(refs.get(ref_key, "") or "")
    entry = {
        "kind": kind,
        "source_reference_key": ref_key,
        "source_symbol": source_symbol,
        "status": "missing_source_reference",
    }
    if raw_size_key:
        entry["frame_size"] = _parse_mon_coords(raw_fields.get(raw_size_key, ""))
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

    asset_path = output_dir / species_dir / asset_name
    image_size = _write_png_asset(source_image_path, asset_path)
    entry.update({
        "status": "imported",
        "image": "res://{}".format(to_project_path(asset_path)),
        "image_project_path": to_project_path(asset_path),
        "image_size": image_size,
        "transparency": {
            "source_palette_index": 0,
            "rule": "gba_obj_or_mon_palette_index_0_alpha_0",
        },
    })
    return entry


def _build_palette(kind, ref_key, refs, definitions, source_root):
    source_symbol = str(refs.get(ref_key, "") or "")
    entry = {
        "kind": kind,
        "source_reference_key": ref_key,
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
        entry["status"] = "missing_source_palette"
        return entry

    colors = _read_jasc_palette(source_palette_path)
    entry.update({
        "status": "metadata_only",
        "color_count": len(colors),
        "colors_rgb": colors,
        "runtime_note": "Import-only source color provenance. Runtime must use distinct RGBA image variants or Godot Shader/Material parameters, not indexed-color remaps.",
    })
    return entry


def _build_animation(record, refs, raw_fields):
    frames_expr = str(refs.get("front_anim_frames", "") or raw_fields.get("frontAnimFrames", "") or "")
    front_anim_expr = str(refs.get("front_anim_id", "") or raw_fields.get("frontAnimId", "") or "")
    back_anim_expr = str(refs.get("back_anim_id", "") or raw_fields.get("backAnimId", "") or "")
    front_anim_id = _select_modern_expr(front_anim_expr)
    back_anim_id = _select_modern_expr(back_anim_expr)
    frames = _parse_front_anim_frames(frames_expr)
    has_metadata = bool(frames_expr or front_anim_id or back_anim_id)
    return {
        "status": "metadata_only" if has_metadata else "missing_source_reference",
        "front_frames_source": frames_expr,
        "front_frames": frames,
        "front_anim_id_source": front_anim_expr,
        "front_anim_id": front_anim_id,
        "front_anim_delay": _parse_int_expr(raw_fields.get("frontAnimDelay", record.get("front_anim_delay"))),
        "back_anim_id_source": back_anim_expr,
        "back_anim_id": back_anim_id,
        "runtime_status": "unsupported",
        "unsupported": ["battle_animation_runtime_pending"] if has_metadata else [],
    }


def _build_placement(record, raw_fields):
    return {
        "front_pic_y_offset": _parse_int_expr(raw_fields.get("frontPicYOffset", record.get("front_pic_y_offset"))),
        "back_pic_y_offset": _parse_int_expr(raw_fields.get("backPicYOffset", record.get("back_pic_y_offset"))),
        "pokemon_offset": _parse_int_expr(raw_fields.get("pokemonOffset", record.get("pokemon_offset"))),
        "pokemon_scale": _parse_int_expr(raw_fields.get("pokemonScale", record.get("pokemon_scale"))),
        "front_pic_size": _parse_mon_coords(raw_fields.get("frontPicSize", "")),
        "back_pic_size": _parse_mon_coords(raw_fields.get("backPicSize", "")),
        "front_pic_size_female": _parse_mon_coords(raw_fields.get("frontPicSizeFemale", "")),
        "back_pic_size_female": _parse_mon_coords(raw_fields.get("backPicSizeFemale", "")),
        "shadow": {
            "status": "metadata_only",
            "runtime_status": "unsupported",
            "note": "Placement offsets are exported; exact battle shadow material/animation rules are implemented in a later asset runtime slice.",
        },
    }


def _build_cry(raw_fields):
    cry_id = str(raw_fields.get("cryId", "") or "")
    return {
        "source_symbol": cry_id,
        "status": "metadata_only" if cry_id else "missing_source_reference",
        "audio_status": "metadata_only" if cry_id else "unsupported",
        "unsupported": ["battle_audio_playback_pending"] if cry_id else [],
    }


def _coverage_status(front, back, palettes, animation, cry):
    front_imported = front.get("status") == "imported"
    back_imported = back.get("status") == "imported"
    palette_ready = (
        palettes.get("normal", {}).get("status") == "metadata_only"
        and palettes.get("shiny", {}).get("status") == "metadata_only"
    )
    return {
        "asset_status": "first_pass" if front_imported and back_imported else "unsupported",
        "palette_status": "metadata_only" if palette_ready else "unsupported",
        "animation_status": "metadata_only" if animation.get("status") == "metadata_only" else "unsupported",
        "audio_status": cry.get("audio_status", "unsupported"),
        "runtime_status": "unsupported",
    }


def _record_unsupported(record, images, palettes, animation, cry, coverage):
    unsupported = []
    if coverage["asset_status"] != "first_pass":
        unsupported.append("pokemon_asset_import_pending")
    if animation.get("unsupported"):
        unsupported.extend(animation["unsupported"])
    if cry.get("unsupported"):
        unsupported.extend(cry["unsupported"])
    if record.get("initializer_kind") == "macro_call" and coverage["asset_status"] != "first_pass":
        unsupported.append("pokemon_asset_import_pending")
    for asset in list(images.values()) + list(palettes.values()):
        if str(asset.get("status", "")).startswith("missing_") and asset.get("source_symbol"):
            unsupported.append("pokemon_asset_import_pending")
            break
    return sorted(set(unsupported))


def export_pokemon_battle_sprites(source_root, output_data_root, output_asset_root):
    species_data = _read_json(output_data_root / "pokemon" / "species.json")
    species_records = species_data.get("species", {})
    definitions, definition_stats = _parse_graphics_definitions(source_root)
    output_dir = output_asset_root / ASSET_OUTPUT_DIR
    output_dir.mkdir(parents=True, exist_ok=True)

    sprites = {}
    sprite_order = []
    seen = set()
    stats = {
        "species_count": 0,
        "struct_initializer_count": 0,
        "macro_initializer_count": 0,
        "front_textures_imported": 0,
        "back_textures_imported": 0,
        "female_front_textures_imported": 0,
        "female_back_textures_imported": 0,
        "icon_textures_imported": 0,
        "female_icon_textures_imported": 0,
        "normal_palette_metadata_count": 0,
        "shiny_palette_metadata_count": 0,
        "front_animation_metadata_count": 0,
        "cry_metadata_count": 0,
        "first_pass_asset_records": 0,
        "unsupported_record_count": 0,
        "missing_image_asset_count": 0,
        "missing_palette_asset_count": 0,
    }

    for species_symbol in species_data.get("species_order", []):
        if species_symbol in seen:
            continue
        seen.add(species_symbol)
        record = species_records.get(species_symbol, {})
        refs = record.get("source_references", {}) if isinstance(record.get("source_references"), dict) else {}
        raw_fields = record.get("raw_fields", {}) if isinstance(record.get("raw_fields"), dict) else {}
        species_dir = _species_asset_dir(species_symbol)

        images = {}
        for kind, ref_key, raw_size_key, asset_name in IMAGE_ASSETS:
            images[kind] = _build_image_asset(
                kind,
                ref_key,
                raw_size_key,
                asset_name,
                refs,
                raw_fields,
                definitions,
                source_root,
                output_dir,
                species_dir,
            )

        palettes = {}
        for kind, ref_key in PALETTE_ASSETS:
            palettes[kind] = _build_palette(kind, ref_key, refs, definitions, source_root)

        animation = _build_animation(record, refs, raw_fields)
        cry = _build_cry(raw_fields)
        coverage = _coverage_status(images["front"], images["back"], palettes, animation, cry)
        unsupported = _record_unsupported(record, images, palettes, animation, cry, coverage)

        sprite_record = {
            "species_symbol": species_symbol,
            "numeric_id": int(record.get("id", -1)),
            "initializer_kind": str(record.get("initializer_kind", "")),
            "evaluation_status": str(record.get("evaluation_status", "")),
            "source": record.get("source", {}),
            "source_references": refs,
            "front": images["front"],
            "back": images["back"],
            "icon": images["icon"],
            "female": {
                "front": images["female_front"],
                "back": images["female_back"],
                "icon": images["female_icon"],
                "normal_palette": palettes["female_normal"],
                "shiny_palette": palettes["female_shiny"],
            },
            "palettes": {
                "normal": palettes["normal"],
                "shiny": palettes["shiny"],
            },
            "placement": _build_placement(record, raw_fields),
            "animation": animation,
            "cry": cry,
            "coverage": coverage,
            "unsupported": unsupported,
        }
        sprites[species_symbol] = sprite_record
        sprite_order.append(species_symbol)

        stats["species_count"] += 1
        if sprite_record["initializer_kind"] == "struct":
            stats["struct_initializer_count"] += 1
        elif sprite_record["initializer_kind"] == "macro_call":
            stats["macro_initializer_count"] += 1
        for stat_key, image_key in [
            ("front_textures_imported", "front"),
            ("back_textures_imported", "back"),
            ("female_front_textures_imported", "female_front"),
            ("female_back_textures_imported", "female_back"),
            ("icon_textures_imported", "icon"),
            ("female_icon_textures_imported", "female_icon"),
        ]:
            if images[image_key].get("status") == "imported":
                stats[stat_key] += 1
            elif images[image_key].get("source_symbol") and str(images[image_key].get("status", "")).startswith("missing_"):
                stats["missing_image_asset_count"] += 1
        if palettes["normal"].get("status") == "metadata_only":
            stats["normal_palette_metadata_count"] += 1
        elif palettes["normal"].get("source_symbol") and str(palettes["normal"].get("status", "")).startswith("missing_"):
            stats["missing_palette_asset_count"] += 1
        if palettes["shiny"].get("status") == "metadata_only":
            stats["shiny_palette_metadata_count"] += 1
        elif palettes["shiny"].get("source_symbol") and str(palettes["shiny"].get("status", "")).startswith("missing_"):
            stats["missing_palette_asset_count"] += 1
        if animation.get("status") == "metadata_only":
            stats["front_animation_metadata_count"] += 1
        if cry.get("audio_status") == "metadata_only":
            stats["cry_metadata_count"] += 1
        if coverage["asset_status"] == "first_pass":
            stats["first_pass_asset_records"] += 1
        if unsupported:
            stats["unsupported_record_count"] += 1

    stats["graphics_definition_count"] = definition_stats["definition_count"]
    stats["graphics_duplicate_symbol_count"] = definition_stats["duplicate_symbol_count"]

    data = {
        "schema_version": 1,
        "category": ASSET_CATEGORY,
        "source": {
            "project": "pokeemerald-expansion",
            "kind": "first_pass_pokemon_battle_sprites",
            "graphics_source": to_project_path(GRAPHICS_SOURCE),
            "species_source": "data/generated/pokemon/species.json",
            "selection_rule": definition_stats["selection_rule"],
            "audio_status": "metadata_only",
        },
        "sprite_order": sprite_order,
        "sprites": sprites,
        "stats": stats,
    }
    output_path = output_data_root / "pokemon" / "battle_sprites.json"
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

    output_path, data = export_pokemon_battle_sprites(source_root, output_data_root, output_asset_root)
    stats = data["stats"]
    manifest_entry = {
        "category": data["category"],
        "path": to_project_path(output_path),
        "species_count": stats["species_count"],
        "front_texture_count": stats["front_textures_imported"],
        "back_texture_count": stats["back_textures_imported"],
        "icon_texture_count": stats["icon_textures_imported"],
        "first_pass_asset_records": stats["first_pass_asset_records"],
        "audio_status": "metadata_only",
    }
    write_manifest(
        output_data_root / "import_manifest.json",
        exported_pokemon=[manifest_entry],
        generator="tools/importer/export_pokemon_battle_sprites.py",
    )

    print(json.dumps({"exported": manifest_entry}, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
