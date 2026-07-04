#!/usr/bin/env python3
"""Build trainer battle data/asset completeness coverage."""

import argparse
import json
from collections import Counter
from pathlib import Path


MAGMA_TRAINER_CLASSES = {
    "TRAINER_CLASS_TEAM_MAGMA",
    "TRAINER_CLASS_MAGMA_LEADER",
    "TRAINER_CLASS_MAGMA_ADMIN",
}

AQUA_TRAINER_CLASSES = {
    "TRAINER_CLASS_TEAM_AQUA",
    "TRAINER_CLASS_AQUA_LEADER",
    "TRAINER_CLASS_AQUA_ADMIN",
}

UNSUPPORTED_CODE_REGISTRY = {
    "trainer_asset_import_pending": "A trainer battle front sprite or import-only source color record is missing.",
    "trainer_source_color_provenance_pending": "A trainer source color provenance record is missing or unresolved.",
    "trainer_party_species_asset_pending": "A trainer party Pokemon does not resolve to a generated Pokemon battle asset coverage row.",
    "trainer_ai_pending": "Trainer AI flags are generated as metadata, but source AI execution is not implemented.",
    "trainer_intro_defeat_text_pending": "Trainer intro/defeat/post-battle text references are not exported into trainer coverage yet.",
    "trainer_reward_flow_pending": "Trainer reward money, rematch, and post-battle mutation flow remain pending.",
    "trainer_double_battle_runtime_pending": "Double battle flags are generated, but the current battle runtime is single-battler only.",
    "trainer_slide_runtime_pending": "Trainer draw/slide metadata is generated, but source-timed playback is not implemented.",
    "trainer_mugshot_runtime_pending": "Mugshot color/source metadata is generated, but mugshot transition playback is not implemented.",
    "trainer_transition_magma_runtime_pending": "Team Magma special transition selection is generated, but playback is not implemented.",
    "trainer_transition_aqua_runtime_pending": "Team Aqua special transition selection is generated, but playback is not implemented.",
    "battle_animation_runtime_pending": "Trainer sprite/back-sprite animation metadata is generated, but source-timed playback is not implemented.",
    "battle_audio_playback_pending": "Trainer encounter music and battle sounds remain metadata-only until audio scope opens.",
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


def _dict(value):
    return value if isinstance(value, dict) else {}


def _array(value):
    return value if isinstance(value, list) else []


def _int_value(value, default=-1):
    if value is None or value == "":
        return default
    return int(value)


def _symbol(record):
    record = _dict(record)
    return str(record.get("symbol", ""))


def _source_ref(record):
    record = _dict(record)
    source = record.get("source", {})
    return source if isinstance(source, dict) else {}


def _asset_summary(asset, project_root, required=True):
    asset = _dict(asset)
    source_symbol = str(asset.get("source_symbol", ""))
    required = bool(required or source_symbol)
    status = str(asset.get("status", "unsupported"))
    if not required and not source_symbol:
        status = "not_required"
    project_path = str(asset.get("image_project_path", ""))
    return {
        "status": status,
        "required": required,
        "source_symbol": source_symbol,
        "image_project_path": project_path,
        "image_exists": bool(project_path and (project_root / project_path).exists()),
        "image_size": _dict(asset.get("image_size", {})),
        "source_image_path": str(asset.get("source_image_path", "")),
        "source_binary_path": str(asset.get("source_binary_path", "")),
        "transparency": _dict(asset.get("transparency", {})),
    }


def _source_color_summary(record):
    record = _dict(record)
    source_symbol = str(record.get("source_symbol", ""))
    if not source_symbol:
        status = str(record.get("status", "not_required"))
        if status not in ("metadata_only", "not_used", "unsupported"):
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


def _mugshot_summary(sprite_record):
    mugshot = _dict(sprite_record.get("mugshot", {}))
    color = _dict(mugshot.get("color", {}))
    color_symbol = str(color.get("symbol", "MUGSHOT_COLOR_NONE") or "MUGSHOT_COLOR_NONE")
    palette_ref = _dict(mugshot.get("palette_ref", {}))
    source_color = _source_color_summary(_dict(palette_ref.get("palette", {})))
    if color_symbol == "MUGSHOT_COLOR_NONE":
        source_color["status"] = "not_used"
    return {
        "color_symbol": color_symbol,
        "color_value": int(color.get("value", 0) or 0),
        "transition_status": str(mugshot.get("transition_status", "not_used")),
        "runtime_status": str(mugshot.get("runtime_status", "not_used")),
        "source_color_provenance": source_color,
        "trainer_sprite_coords": _dict(mugshot.get("trainer_sprite_coords", {})),
        "unsupported": _array(mugshot.get("unsupported", [])),
    }


def _transition_summary(trainer_record):
    trainer_class = _symbol(trainer_record.get("trainer_class", {}))
    mugshot = _dict(trainer_record.get("mugshot", {}))
    mugshot_symbol = str(mugshot.get("symbol", "MUGSHOT_COLOR_NONE") or "MUGSHOT_COLOR_NONE")
    if mugshot_symbol != "MUGSHOT_COLOR_NONE":
        return {
            "status": "selected_unsupported_placeholder",
            "selected": "B_TRANSITION_MUGSHOT",
            "kind": "mugshot",
            "transition_type": "TRANSITION_TYPE_SPECIAL",
            "selection_source": "src/battle_setup.c:GetTrainerBattleTransition -> DoesTrainerHaveMugshot",
            "runtime_status": "unsupported",
            "unsupported": ["trainer_mugshot_runtime_pending"],
        }
    if trainer_class in MAGMA_TRAINER_CLASSES:
        return {
            "status": "selected_unsupported_placeholder",
            "selected": "B_TRANSITION_MAGMA",
            "kind": "team_magma",
            "transition_type": "TRANSITION_TYPE_SPECIAL",
            "selection_source": "src/battle_setup.c:GetTrainerBattleTransition Team Magma trainer class branch",
            "runtime_status": "unsupported",
            "unsupported": ["trainer_transition_magma_runtime_pending"],
        }
    if trainer_class in AQUA_TRAINER_CLASSES:
        return {
            "status": "selected_unsupported_placeholder",
            "selected": "B_TRANSITION_AQUA",
            "kind": "team_aqua",
            "transition_type": "TRANSITION_TYPE_SPECIAL",
            "selection_source": "src/battle_setup.c:GetTrainerBattleTransition Team Aqua trainer class branch",
            "runtime_status": "unsupported",
            "unsupported": ["trainer_transition_aqua_runtime_pending"],
        }
    return {
        "status": "metadata_only",
        "selected": "",
        "kind": "trainer_transition_table",
        "transition_type": "map_context_dependent",
        "transition_table": "sBattleTransitionTable_Trainer",
        "selection_source": "src/battle_setup.c:GetTrainerBattleTransition",
        "runtime_status": "unsupported",
        "unsupported": [],
    }


def _music_summary(trainer_record):
    music = _dict(trainer_record.get("encounter_music", {}))
    symbol = str(music.get("symbol", ""))
    return {
        "status": "metadata_only" if symbol else "unsupported",
        "audio_status": "metadata_only" if symbol else "unsupported",
        "source_symbol": symbol,
        "name": str(music.get("name", "")),
        "source": _source_ref(music),
    }


def _text_refs_summary(trainer_record):
    has_party = int(_dict(trainer_record.get("party_size", {})).get("value", 0) or 0) > 0
    status = "unsupported" if has_party else "not_required"
    return {
        "status": status,
        "intro_text": {"status": status, "source": "trainerbattle event scripts"},
        "defeat_text": {"status": status, "source": "trainerbattle event scripts"},
        "post_battle_text": {"status": status, "source": "BattleSetup_GetTrainerPostBattleScript"},
        "unsupported": ["trainer_intro_defeat_text_pending"] if has_party else [],
    }


def _reward_summary(trainer_record):
    has_party = int(_dict(trainer_record.get("party_size", {})).get("value", 0) or 0) > 0
    status = "unsupported" if has_party else "not_required"
    trainer_class = _dict(trainer_record.get("trainer_class", {}))
    return {
        "status": status,
        "trainer_class_symbol": str(trainer_class.get("symbol", "")),
        "money_table_status": "not_exported" if has_party else "not_required",
        "post_battle_mutation_status": status,
        "source": "src/battle_setup.c / trainerbattle event scripts",
        "unsupported": ["trainer_reward_flow_pending"] if has_party else [],
    }


def _party_mon_summary(mon, pokemon_rows):
    species = _dict(mon.get("species", {}))
    species_symbol = str(species.get("symbol", ""))
    pokemon_row = pokemon_rows.get(species_symbol, {})
    if pokemon_row:
        sprite_status = str(_dict(pokemon_row.get("normal_assets", {})).get("pair_status", "unsupported"))
        asset_status = str(pokemon_row.get("asset_status", "unsupported"))
    else:
        sprite_status = "missing_species_asset_row"
        asset_status = "unsupported"
    moves = _array(mon.get("moves", []))
    held_item = _dict(mon.get("held_item", {}))
    return {
        "index": _int_value(mon.get("index"), -1),
        "species_symbol": species_symbol,
        "species_status": str(species.get("status", "")),
        "level": int(_dict(mon.get("level", {})).get("value", 0) or 0),
        "held_item": str(held_item.get("symbol", "ITEM_NONE") or "ITEM_NONE"),
        "move_source_kind": str(_dict(mon.get("move_source_behavior", {})).get("kind", "")),
        "explicit_move_count": len(moves),
        "battle_sprite_status": sprite_status,
        "pokemon_asset_status": asset_status,
        "source": _source_ref(mon),
    }


def _party_summary(trainer_record, pokemon_rows):
    party = _array(trainer_record.get("party", []))
    mons = [_party_mon_summary(mon, pokemon_rows) for mon in party]
    if not mons:
        status = "not_required"
    elif all(mon["battle_sprite_status"] == "first_pass" for mon in mons):
        status = "first_pass"
    else:
        status = "unsupported"
    return {
        "status": status,
        "declared_party_size": int(_dict(trainer_record.get("party_size", {})).get("value", 0) or 0),
        "party_mon_count": len(mons),
        "unique_species_count": len({mon["species_symbol"] for mon in mons if mon["species_symbol"]}),
        "held_item_count": sum(1 for mon in mons if mon["held_item"] != "ITEM_NONE"),
        "explicit_move_mon_count": sum(1 for mon in mons if mon["explicit_move_count"] > 0),
        "default_move_mon_count": sum(1 for mon in mons if mon["move_source_kind"] == "level_up_default"),
        "missing_species_asset_count": sum(1 for mon in mons if mon["battle_sprite_status"] == "missing_species_asset_row"),
        "pokemon": mons,
    }


def _build_row(trainer_symbol, trainer_record, sprite_record, pokemon_rows, project_root):
    trainer_class_symbol = _symbol(trainer_record.get("trainer_class", {}))
    front_asset = _asset_summary(sprite_record.get("front", {}), project_root, required=True)
    front_source_color = _source_color_summary(sprite_record.get("palette", {}))
    mugshot = _mugshot_summary(sprite_record)
    transition = _transition_summary(trainer_record)
    party = _party_summary(trainer_record, pokemon_rows)
    text_refs = _text_refs_summary(trainer_record)
    reward = _reward_summary(trainer_record)
    coverage = _dict(sprite_record.get("coverage", {}))
    battle_type = _dict(trainer_record.get("battle_type", {}))

    unsupported = []
    unsupported.extend(_array(sprite_record.get("unsupported", [])))
    unsupported.extend(_array(mugshot.get("unsupported", [])))
    unsupported.extend(_array(transition.get("unsupported", [])))
    unsupported.extend(_array(text_refs.get("unsupported", [])))
    unsupported.extend(_array(reward.get("unsupported", [])))
    if front_asset["status"] != "imported":
        unsupported.append("trainer_asset_import_pending")
    if front_source_color["status"] != "metadata_only":
        unsupported.append("trainer_source_color_provenance_pending")
    if party["status"] == "unsupported":
        unsupported.append("trainer_party_species_asset_pending")
    if int(party.get("party_mon_count", 0)) > 0:
        unsupported.append("trainer_ai_pending")
        unsupported.append("trainer_slide_runtime_pending")
    if bool(battle_type.get("is_double", False)):
        unsupported.append("trainer_double_battle_runtime_pending")
    unsupported = sorted(set(unsupported))

    asset_status = "first_pass" if (
        front_asset["status"] == "imported"
        and front_source_color["status"] == "metadata_only"
    ) else "unsupported"

    return {
        "id": trainer_symbol,
        "trainer_symbol": trainer_symbol,
        "numeric_id": _int_value(trainer_record.get("id", sprite_record.get("numeric_id", -1)), -1),
        "trainer_data": {
            "status": str(trainer_record.get("evaluation_status", "unsupported")),
            "name": _dict(trainer_record.get("name", {})),
            "trainer_class": trainer_record.get("trainer_class", {}),
            "pic": trainer_record.get("pic", {}),
            "gender": trainer_record.get("gender", {}),
            "difficulty": trainer_record.get("difficulty", {}),
            "battle_type": battle_type,
            "ai_flag_count": len(_array(trainer_record.get("ai_flags", []))),
            "item_count": len(_array(_dict(trainer_record.get("items", {})).get("explicit", []))),
            "starting_status_count": len(_array(trainer_record.get("starting_statuses", []))),
            "pool": trainer_record.get("pool", {}),
        },
        "front_sprite": front_asset,
        "source_color_provenance": {
            "front": front_source_color,
            "mugshot_background": mugshot["source_color_provenance"],
        },
        "mugshot": mugshot,
        "slide": {
            "status": str(coverage.get("slide_status", "unsupported")),
            "metadata": _dict(sprite_record.get("slide", {})),
            "runtime_status": "unsupported",
        },
        "transition": transition,
        "music": _music_summary(trainer_record),
        "party_sprite_requirements": party,
        "text_refs": text_refs,
        "reward_metadata": reward,
        "asset_status": asset_status,
        "party_status": party["status"],
        "runtime_status": "unsupported",
        "audio_status": "metadata_only",
        "unsupported": unsupported,
        "source": _source_ref(trainer_record),
        "source_trace": [
            "src/data/trainers.party",
            "src/data/graphics/trainers.h",
            "src/battle_setup.c:GetTrainerBattleTransition",
            "src/battle_main.c:CustomTrainerPartyAssignMoves",
        ],
    }


def _status_count(counts, prefix, status):
    counts["%s_%s_count" % (prefix, status)] += 1


def _build_stats(rows, trainer_order, trainer_sprites_data):
    counts = Counter()
    for row in rows:
        counts["coverage_row_count"] += 1
        _status_count(counts, "asset_status", row["asset_status"])
        _status_count(counts, "party_status", row["party_status"])
        _status_count(counts, "front_sprite", _dict(row["front_sprite"]).get("status", ""))
        _status_count(counts, "front_source_color", _dict(row["source_color_provenance"]["front"]).get("status", ""))
        _status_count(counts, "mugshot_transition", _dict(row["mugshot"]).get("transition_status", ""))
        _status_count(counts, "mugshot_source_color", _dict(row["source_color_provenance"]["mugshot_background"]).get("status", ""))
        _status_count(counts, "transition_kind", _dict(row["transition"]).get("kind", ""))
        _status_count(counts, "music_audio", _dict(row["music"]).get("audio_status", ""))
        _status_count(counts, "text_refs", _dict(row["text_refs"]).get("status", ""))
        _status_count(counts, "reward", _dict(row["reward_metadata"]).get("status", ""))
        if _dict(row["trainer_data"].get("battle_type", {})).get("is_double"):
            counts["double_battle_count"] += 1
        if row["trainer_data"].get("ai_flag_count", 0) > 0:
            counts["trainer_with_ai_flags_count"] += 1
        if row["trainer_data"].get("item_count", 0) > 0:
            counts["trainer_with_items_count"] += 1
        party = _dict(row.get("party_sprite_requirements", {}))
        counts["party_mon_count"] += int(party.get("party_mon_count", 0) or 0)
        counts["party_missing_species_asset_count"] += int(party.get("missing_species_asset_count", 0) or 0)
        counts["party_held_item_mon_count"] += int(party.get("held_item_count", 0) or 0)
        counts["party_explicit_move_mon_count"] += int(party.get("explicit_move_mon_count", 0) or 0)
        counts["party_default_move_mon_count"] += int(party.get("default_move_mon_count", 0) or 0)
        if row["unsupported"]:
            counts["rows_with_unsupported_count"] += 1
    counts["trainer_count"] = len(trainer_order)
    sprite_stats = _dict(trainer_sprites_data.get("stats", {}))
    counts["front_sprite_definition_count"] = int(sprite_stats.get("front_sprite_count", 0) or 0)
    counts["front_textures_imported_count"] = int(sprite_stats.get("front_textures_imported", 0) or 0)
    counts["unique_front_sprite_used_count"] = int(sprite_stats.get("unique_front_sprite_used_count", 0) or 0)
    counts["back_sprite_definition_count"] = int(sprite_stats.get("back_sprite_count", 0) or 0)
    counts["back_textures_imported_count"] = int(sprite_stats.get("back_textures_imported", 0) or 0)
    return dict(sorted(counts.items()))


def build_report(project_root, output_root):
    pokemon_root = output_root / "pokemon"
    battle_root = output_root / "battle"
    reports_root = output_root / "reports"
    trainers_data = load_json(pokemon_root / "trainers.json")
    trainer_sprites_data = load_json(battle_root / "trainer_sprites.json")
    pokemon_asset_report = load_json(reports_root / "pokemon_battle_asset_coverage.json")

    pokemon_rows = {
        row.get("species_symbol", row.get("id", "")): row
        for row in _array(pokemon_asset_report.get("coverage_rows", []))
        if isinstance(row, dict)
    }
    trainers = _dict(trainers_data.get("trainers", {}))
    sprite_records = _dict(trainer_sprites_data.get("trainers", {}))

    rows = []
    seen = set()
    for trainer_symbol in _array(trainers_data.get("trainer_order", [])):
        if trainer_symbol in seen:
            continue
        seen.add(trainer_symbol)
        rows.append(_build_row(
            trainer_symbol,
            _dict(trainers.get(trainer_symbol, {})),
            _dict(sprite_records.get(trainer_symbol, {})),
            pokemon_rows,
            project_root,
        ))

    stats = _build_stats(rows, [row["trainer_symbol"] for row in rows], trainer_sprites_data)
    return {
        "schema_version": 1,
        "generated_by": "tools/report_trainer_battle_assets.py",
        "source_files": [
            "src/data/trainers.party",
            "src/data/graphics/trainers.h",
            "src/battle_setup.c",
            "src/battle_transition.c",
            "include/battle_transition.h",
            "src/battle_main.c",
            "data/generated/pokemon/trainers.json",
            "data/generated/battle/trainer_sprites.json",
            "data/generated/reports/pokemon_battle_asset_coverage.json",
        ],
        "runtime_color_policy": {
            "status": "no_runtime_palette",
            "rule": "Source color files and slots are import-only provenance. Trainer source color variants require distinct RGBA assets; runtime color effects use Godot Shader/Material/Animation parameters.",
            "audio_status": "metadata_only",
        },
        "unsupported_code_registry": [
            {"code": code, "description": description}
            for code, description in sorted(UNSUPPORTED_CODE_REGISTRY.items())
        ],
        "stats": stats,
        "coverage_rows": rows,
    }


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
    output_path = output_root / "reports" / "trainer_battle_asset_coverage.json"
    write_json(output_path, report)
    print(json.dumps({
        "report": to_project_path(maybe_relative_to(output_path, project_root)),
        "coverage_rows": report["stats"].get("coverage_row_count", 0),
        "asset_status_first_pass_count": report["stats"].get("asset_status_first_pass_count", 0),
        "party_missing_species_asset_count": report["stats"].get("party_missing_species_asset_count", 0),
        "transition_kind_mugshot_count": report["stats"].get("transition_kind_mugshot_count", 0),
        "transition_kind_team_magma_count": report["stats"].get("transition_kind_team_magma_count", 0),
        "transition_kind_team_aqua_count": report["stats"].get("transition_kind_team_aqua_count", 0),
    }, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
