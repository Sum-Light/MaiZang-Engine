#!/usr/bin/env python3
"""Build Pokemon battle data/asset completeness coverage."""

import argparse
import json
from collections import Counter
from pathlib import Path


UNSUPPORTED_CODE_REGISTRY = {
    "pokemon_asset_import_pending": "The generated species/form lacks a complete first-pass front/back battle sprite import.",
    "pokemon_normal_battle_sprite_pending": "A normal front/back battle sprite required by source metadata is not imported.",
    "pokemon_battle_icon_pending": "A battle-facing Pokemon icon reference is not imported.",
    "pokemon_female_asset_pending": "A source-referenced female battle/image variant is not fully imported.",
    "pokemon_distinct_shiny_asset_pending": "A shiny source color variant exists, but the required distinct RGBA battle image asset is not generated yet.",
    "pokemon_distinct_female_shiny_asset_pending": "A female shiny source color variant exists, but the required distinct RGBA battle image asset is not generated yet.",
    "pokemon_source_color_provenance_pending": "Source color provenance is missing or unresolved for a source-referenced Pokemon asset.",
    "battle_animation_runtime_pending": "Front animation metadata is generated, but source-timed battle sprite animation playback is not implemented.",
    "battle_audio_playback_pending": "Pokemon cry symbols and timing intent are metadata-only until audio scope opens.",
}


def load_json(path):
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def write_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="\n") as handle:
        json.dump(data, handle, ensure_ascii=False, indent=2)
        handle.write("\n")


def to_project_path(value):
    return str(value).replace("\\", "/")


def maybe_relative_to(path, root):
    try:
        return path.relative_to(root)
    except ValueError:
        return path


def source_ref(record):
    if not isinstance(record, dict):
        return {}
    source = record.get("source", {})
    return source if isinstance(source, dict) else {}


def _dict(value):
    return value if isinstance(value, dict) else {}


def _array(value):
    return value if isinstance(value, list) else []


def _asset_summary(asset, project_root, required=True):
    asset = _dict(asset)
    source_symbol = str(asset.get("source_symbol", ""))
    required = bool(required or source_symbol)
    status = str(asset.get("status", "unsupported"))
    if not required and not source_symbol:
        status = "not_required"
    project_path = str(asset.get("image_project_path", ""))
    exists = bool(project_path and (project_root / project_path).exists())
    return {
        "status": status,
        "required": required,
        "source_symbol": source_symbol,
        "source_reference_key": str(asset.get("source_reference_key", "")),
        "image_project_path": project_path,
        "image_exists": exists,
        "image_size": _dict(asset.get("image_size", {})),
        "frame_size": _dict(asset.get("frame_size", {})),
        "source_image_path": str(asset.get("source_image_path", "")),
    }


def _source_color_summary(record):
    record = _dict(record)
    source_symbol = str(record.get("source_symbol", ""))
    if not source_symbol:
        status = "not_required"
    else:
        status = str(record.get("status", "unsupported"))
    return {
        "status": status,
        "source_symbol": source_symbol,
        "source_color_kind": str(record.get("kind", "")),
        "source_color_path": str(record.get("source_palette_path", "")),
        "color_count": int(record.get("color_count", 0) or 0),
    }


def _distinct_color_variant(base_asset, source_color):
    base_asset = _dict(base_asset)
    source_color = _dict(source_color)
    source_symbol = str(source_color.get("source_symbol", ""))
    if not source_symbol:
        return {
            "status": "not_required",
            "base_image_status": str(base_asset.get("status", "unsupported")),
            "source_color_status": "not_required",
            "image_project_path": "",
            "reason": "no_source_color_variant",
        }
    source_status = str(source_color.get("status", "unsupported"))
    base_status = str(base_asset.get("status", "unsupported"))
    if source_status != "metadata_only":
        status = "blocked_source_color_unavailable"
        reason = source_status
    elif base_status != "imported":
        status = "blocked_base_image_unavailable"
        reason = base_status
    else:
        status = "pending_distinct_asset"
        reason = "source_color_variant_requires_baked_rgba_image"
    return {
        "status": status,
        "base_image_status": base_status,
        "source_color_status": source_status,
        "source_color_symbol": source_symbol,
        "image_project_path": "",
        "reason": reason,
    }


def _status_pair(front, back):
    if front.get("status") == "imported" and back.get("status") == "imported":
        return "first_pass"
    if front.get("status") == "not_required" and back.get("status") == "not_required":
        return "not_required"
    return "unsupported"


def _required_asset_status(assets):
    required_assets = [
        _dict(assets.get(key, {}))
        for key in ["front", "back", "icon"]
        if _dict(assets.get(key, {})).get("required")
    ]
    if not required_assets:
        return "not_required"
    if all(asset.get("status") == "imported" for asset in required_assets):
        return "first_pass"
    return "unsupported"


def _species_data_summary(species_record):
    refs = _dict(species_record.get("source_references", {}))
    return {
        "initializer_kind": str(species_record.get("initializer_kind", "")),
        "evaluation_status": str(species_record.get("evaluation_status", "")),
        "base_stats_status": "metadata_only" if _dict(species_record.get("base_stats", {})) else "unsupported",
        "typing_status": "metadata_only" if _array(species_record.get("types", [])) else "unsupported",
        "abilities_status": "metadata_only" if _array(species_record.get("abilities", [])) else "unsupported",
        "learnset_status": "metadata_only" if refs.get("level_up_learnset") else "unsupported",
        "evolution_refs_status": "metadata_only" if refs.get("evolutions") else "not_required",
        "form_species_table": str(refs.get("form_species_id_table", "")),
        "form_change_table": str(refs.get("form_change_table", "")),
        "gender_ratio": species_record.get("gender_ratio", {}),
    }


def _placement_summary(sprite_record):
    placement = _dict(sprite_record.get("placement", {}))
    return {
        "status": "metadata_only" if placement else "unsupported",
        "front_pic_y_offset": placement.get("front_pic_y_offset"),
        "back_pic_y_offset": placement.get("back_pic_y_offset"),
        "pokemon_offset": placement.get("pokemon_offset"),
        "pokemon_scale": placement.get("pokemon_scale"),
        "front_pic_size": _dict(placement.get("front_pic_size", {})),
        "back_pic_size": _dict(placement.get("back_pic_size", {})),
        "front_pic_size_female": _dict(placement.get("front_pic_size_female", {})),
        "back_pic_size_female": _dict(placement.get("back_pic_size_female", {})),
        "shadow_status": str(_dict(placement.get("shadow", {})).get("status", "unsupported")),
    }


def _animation_summary(sprite_record):
    animation = _dict(sprite_record.get("animation", {}))
    return {
        "status": str(animation.get("status", "unsupported")),
        "runtime_status": str(animation.get("runtime_status", "unsupported")),
        "front_anim_id": str(animation.get("front_anim_id", "")),
        "back_anim_id": str(animation.get("back_anim_id", "")),
        "front_frame_count": len(_array(animation.get("front_frames", []))),
        "front_anim_delay": animation.get("front_anim_delay"),
    }


def _cry_summary(sprite_record):
    cry = _dict(sprite_record.get("cry", {}))
    return {
        "status": str(cry.get("status", "unsupported")),
        "source_symbol": str(cry.get("source_symbol", "")),
        "audio_status": str(cry.get("audio_status", "unsupported")),
    }


def _append_variant_unsupported(unsupported, variant_assets, code):
    for value in variant_assets.values():
        if _dict(value).get("status") == "pending_distinct_asset":
            unsupported.append(code)
            return


def _build_row(species_symbol, species_record, sprite_record, project_root):
    sprite_record = _dict(sprite_record)
    female = _dict(sprite_record.get("female", {}))
    source_colors = _dict(sprite_record.get("palettes", {}))
    species_refs = _dict(species_record.get("source_references", {}))

    normal_assets = {
        "front": _asset_summary(sprite_record.get("front", {}), project_root, required=True),
        "back": _asset_summary(sprite_record.get("back", {}), project_root, required=True),
        "icon": _asset_summary(sprite_record.get("icon", {}), project_root, required=bool(species_refs.get("icon_sprite"))),
    }
    normal_assets["pair_status"] = _status_pair(normal_assets["front"], normal_assets["back"])

    female_assets = {
        "front": _asset_summary(female.get("front", {}), project_root, required=bool(species_refs.get("front_pic_female"))),
        "back": _asset_summary(female.get("back", {}), project_root, required=bool(species_refs.get("back_pic_female"))),
        "icon": _asset_summary(female.get("icon", {}), project_root, required=bool(species_refs.get("icon_sprite_female"))),
    }
    female_assets["variant_status"] = _required_asset_status(female_assets)

    source_color_provenance = {
        "normal": _source_color_summary(source_colors.get("normal", {})),
        "shiny": _source_color_summary(source_colors.get("shiny", {})),
        "female_normal": _source_color_summary(female.get("normal_palette", {})),
        "female_shiny": _source_color_summary(female.get("shiny_palette", {})),
    }

    shiny_assets = {
        "front": _distinct_color_variant(sprite_record.get("front", {}), source_colors.get("shiny", {})),
        "back": _distinct_color_variant(sprite_record.get("back", {}), source_colors.get("shiny", {})),
        "icon": {
            "status": "not_required",
            "reason": "source battle icon data does not define a shiny icon image",
        },
    }
    female_shiny_assets = {
        "front": _distinct_color_variant(female.get("front", {}), female.get("shiny_palette", {})),
        "back": _distinct_color_variant(female.get("back", {}), female.get("shiny_palette", {})),
        "icon": {
            "status": "not_required",
            "reason": "source battle icon data does not define a female shiny icon image",
        },
    }

    unsupported = list(_array(sprite_record.get("unsupported", [])))
    if normal_assets["front"]["status"] != "imported" or normal_assets["back"]["status"] != "imported":
        unsupported.append("pokemon_normal_battle_sprite_pending")
    if normal_assets["icon"]["status"] not in ("imported", "not_required"):
        unsupported.append("pokemon_battle_icon_pending")
    for key in ["front", "back", "icon"]:
        if female_assets[key]["status"] not in ("imported", "not_required"):
            unsupported.append("pokemon_female_asset_pending")
            break
    for key in ["normal", "shiny"]:
        if source_color_provenance[key]["status"] not in ("metadata_only", "not_required"):
            unsupported.append("pokemon_source_color_provenance_pending")
    _append_variant_unsupported(unsupported, shiny_assets, "pokemon_distinct_shiny_asset_pending")
    _append_variant_unsupported(unsupported, female_shiny_assets, "pokemon_distinct_female_shiny_asset_pending")
    unsupported = sorted(set(unsupported))

    pending_distinct_count = sum(
        1
        for bucket in [shiny_assets, female_shiny_assets]
        for value in bucket.values()
        if _dict(value).get("status") == "pending_distinct_asset"
    )

    if normal_assets["pair_status"] != "first_pass":
        asset_status = "unsupported"
    elif pending_distinct_count:
        asset_status = "first_pass_with_variant_gaps"
    else:
        asset_status = "first_pass"

    return {
        "id": species_symbol,
        "species_symbol": species_symbol,
        "numeric_id": int(species_record.get("id", sprite_record.get("numeric_id", -1)) or -1),
        "species_data": _species_data_summary(species_record),
        "normal_assets": normal_assets,
        "female_assets": female_assets,
        "distinct_color_variant_assets": {
            "shiny": shiny_assets,
            "female_shiny": female_shiny_assets,
        },
        "source_color_provenance": source_color_provenance,
        "animation": _animation_summary(sprite_record),
        "placement": _placement_summary(sprite_record),
        "cry": _cry_summary(sprite_record),
        "asset_status": asset_status,
        "pending_distinct_color_variant_count": pending_distinct_count,
        "unsupported": unsupported,
        "source": source_ref(species_record),
    }


def _count_status(counter, prefix, assets):
    for key, value in assets.items():
        if key in ("pair_status", "variant_status"):
            continue
        status = _dict(value).get("status", "")
        counter["%s_%s_%s_count" % (prefix, key, status)] += 1


def _build_stats(rows, species_order):
    counts = Counter()
    for row in rows:
        counts["coverage_row_count"] += 1
        counts["species_data_%s_count" % row["species_data"]["evaluation_status"]] += 1
        counts["asset_status_%s_count" % row["asset_status"]] += 1
        if row["normal_assets"]["pair_status"] == "first_pass":
            counts["normal_pair_first_pass_count"] += 1
        counts["female_variant_%s_count" % row["female_assets"]["variant_status"]] += 1
        _count_status(counts, "normal", row["normal_assets"])
        _count_status(counts, "female", row["female_assets"])
        for variant_name, bucket in row["distinct_color_variant_assets"].items():
            _count_status(counts, variant_name, bucket)
        for key, value in row["source_color_provenance"].items():
            counts["source_color_%s_%s_count" % (key, value["status"])] += 1
        if row["animation"]["status"] == "metadata_only":
            counts["front_animation_metadata_count"] += 1
        if row["cry"]["audio_status"] == "metadata_only":
            counts["cry_metadata_only_count"] += 1
        if row["pending_distinct_color_variant_count"] > 0:
            counts["rows_with_pending_distinct_color_variants"] += 1
            counts["pending_distinct_color_variant_count"] += row["pending_distinct_color_variant_count"]
        if row["unsupported"]:
            counts["rows_with_unsupported_count"] += 1
    counts["species_count"] = len(species_order)
    return dict(sorted(counts.items()))


def build_report(project_root, output_root):
    pokemon_root = output_root / "pokemon"
    species_data = load_json(pokemon_root / "species.json")
    battle_sprites_data = load_json(pokemon_root / "battle_sprites.json")
    species_records = _dict(species_data.get("species", {}))
    sprite_records = _dict(battle_sprites_data.get("sprites", {}))

    rows = []
    seen = set()
    for species_symbol in species_data.get("species_order", []):
        if species_symbol in seen:
            continue
        seen.add(species_symbol)
        rows.append(_build_row(
            species_symbol,
            _dict(species_records.get(species_symbol, {})),
            _dict(sprite_records.get(species_symbol, {})),
            project_root,
        ))

    stats = _build_stats(rows, [row["species_symbol"] for row in rows])
    report = {
        "schema_version": 1,
        "generated_by": "tools/report_pokemon_battle_assets.py",
        "source_files": [
            "src/data/graphics/pokemon.h",
            "src/pokemon_animation.c",
            "src/data/pokemon/species_info.h",
            "data/generated/pokemon/species.json",
            "data/generated/pokemon/battle_sprites.json",
        ],
        "runtime_color_policy": {
            "status": "no_runtime_palette",
            "rule": "Source color files and slots are import-only provenance. Shiny and other source color variants require distinct RGBA assets; runtime color effects use Godot Shader/Material/Animation parameters.",
            "audio_status": "metadata_only",
        },
        "unsupported_code_registry": [
            {"code": code, "description": description}
            for code, description in sorted(UNSUPPORTED_CODE_REGISTRY.items())
        ],
        "stats": stats,
        "coverage_rows": rows,
    }
    return report


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-root", default=".", help="Godot project root.")
    parser.add_argument("--output-root", default="data/generated", help="Generated data root.")
    parser.add_argument("--source", default="", help="Accepted for workflow symmetry; report uses generated data.")
    args = parser.parse_args(argv)

    project_root = Path(args.project_root).resolve()
    output_root = Path(args.output_root)
    if not output_root.is_absolute():
        output_root = project_root / output_root
    report = build_report(project_root, output_root)
    output_path = output_root / "reports" / "pokemon_battle_asset_coverage.json"
    write_json(output_path, report)
    print(json.dumps({
        "report": to_project_path(maybe_relative_to(output_path, project_root)),
        "coverage_rows": report["stats"].get("coverage_row_count", 0),
        "normal_pair_first_pass_count": report["stats"].get("normal_pair_first_pass_count", 0),
        "pending_distinct_color_variant_count": report["stats"].get("pending_distinct_color_variant_count", 0),
        "rows_with_pending_distinct_color_variants": report["stats"].get("rows_with_pending_distinct_color_variants", 0),
    }, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
