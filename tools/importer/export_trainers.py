#!/usr/bin/env python3
"""Export trainer party data from pokeemerald-expansion into Godot JSON."""

import argparse
import re
from pathlib import Path

from export_items import _load_item_constants, _load_item_macro_expressions
from export_map import write_json, write_manifest
from export_moves import _load_move_constants
from export_species import (
    ExpressionEvaluator,
    _parse_define_constants,
    _parse_enum_constants,
    _read_defines_into,
    _strip_c_comments,
    load_species_constants,
)
from source_probe import load_config, to_project_path
from text_codec import display_text_from_source


TRAINER_FIELDS = {
    "AI",
    "Items",
    "Class",
    "Music",
    "Gender",
    "Pic",
    "Name",
    "Double Battle",
    "Battle Type",
    "Mugshot",
    "Starting Status",
    "Difficulty",
    "Party Size",
    "Pool Rules",
    "Pool Pick Functions",
    "Pool Prune",
    "Copy Pool",
    "Macro",
    "Back Pic",
}

POKEMON_FIELDS = {
    "EVs",
    "IVs",
    "Ability",
    "Level",
    "Ball",
    "Happiness",
    "Nature",
    "Shiny",
    "Dynamax Level",
    "Gigantamax",
    "Tera Type",
    "Tags",
}

STAT_LABELS = {
    "HP": "hp",
    "Atk": "attack",
    "Def": "defense",
    "Spe": "speed",
    "SpA": "sp_attack",
    "SpD": "sp_defense",
}

STAT_ORDER = ["hp", "attack", "defense", "speed", "sp_attack", "sp_defense"]
EV_STRUCT_ORDER = ["hp", "attack", "defense", "sp_attack", "sp_defense", "speed"]
DEFAULT_IVS = {name: 31 for name in STAT_ORDER}
ZERO_STATS = {name: 0 for name in STAT_ORDER}

GENDERED_SPECIES = {
    "Basculegion": {"M": "Basculegion-M", "F": "Basculegion-F"},
    "Indeedee": {"M": "Indeedee-M", "F": "Indeedee-F"},
    "Oinkologne": {"M": "Oinkologne-M", "F": "Oinkologne-F"},
    "Meowstic": {"M": "Meowstic-M", "F": "Meowstic-F"},
    "Nidoran": {"M": "Nidoran-M", "F": "Nidoran-F"},
}

ITEMED_SPECIES = {
    "Arceus-Bug": ("Arceus", "Insect Plate"),
    "Arceus-Dark": ("Arceus", "Dread Plate"),
    "Arceus-Dragon": ("Arceus", "Draco Plate"),
    "Arceus-Electric": ("Arceus", "Zap Plate"),
    "Arceus-Fairy": ("Arceus", "Pixie Plate"),
    "Arceus-Fighting": ("Arceus", "Fist Plate"),
    "Arceus-Fire": ("Arceus", "Flame Plate"),
    "Arceus-Flying": ("Arceus", "Sky Plate"),
    "Arceus-Ghost": ("Arceus", "Spooky Plate"),
    "Arceus-Grass": ("Arceus", "Meadow Plate"),
    "Arceus-Ground": ("Arceus", "Earth Plate"),
    "Arceus-Ice": ("Arceus", "Icicle Plate"),
    "Arceus-Poison": ("Arceus", "Toxic Plate"),
    "Arceus-Psychic": ("Arceus", "Mind Plate"),
    "Arceus-Rock": ("Arceus", "Stone Plate"),
    "Arceus-Steel": ("Arceus", "Iron Plate"),
    "Arceus-Water": ("Arceus", "Splash Plate"),
    "Genesect-Burn": ("Genesect", "Burn Drive"),
    "Genesect-Chill": ("Genesect", "Chill Drive"),
    "Genesect-Douse": ("Genesect", "Douse Drive"),
    "Genesect-Shock": ("Genesect", "Shock Drive"),
    "Ogerpon-Cornerstone": ("Ogerpon", "Cornerstone Mask"),
    "Ogerpon-Hearthflame": ("Ogerpon", "Hearthflame Mask"),
    "Ogerpon-Wellspring": ("Ogerpon", "Wellspring Mask"),
    "Silvally-Bug": ("Silvally", "Bug Memory"),
    "Silvally-Dark": ("Silvally", "Dark Memory"),
    "Silvally-Dragon": ("Silvally", "Dragon Memory"),
    "Silvally-Electric": ("Silvally", "Electric Memory"),
    "Silvally-Fairy": ("Silvally", "Fairy Memory"),
    "Silvally-Fighting": ("Silvally", "Fighting Memory"),
    "Silvally-Fire": ("Silvally", "Fire Memory"),
    "Silvally-Flying": ("Silvally", "Flying Memory"),
    "Silvally-Ghost": ("Silvally", "Ghost Memory"),
    "Silvally-Grass": ("Silvally", "Grass Memory"),
    "Silvally-Ground": ("Silvally", "Ground Memory"),
    "Silvally-Ice": ("Silvally", "Ice Memory"),
    "Silvally-Poison": ("Silvally", "Poison Memory"),
    "Silvally-Psychic": ("Silvally", "Psychic Memory"),
    "Silvally-Rock": ("Silvally", "Rock Memory"),
    "Silvally-Steel": ("Silvally", "Steel Memory"),
    "Silvally-Water": ("Silvally", "Water Memory"),
}


def export_trainers(root):
    root = Path(root)
    constants = _load_trainer_constants(root)
    parsed = _parse_trainers_party(root / "src/data/trainers.party")
    trainers = {}
    trainer_order = []
    reports = {
        "warnings": list(parsed["warnings"]),
        "unresolved_constants": [],
        "unsupported_fields": [],
        "source_rewrites": [],
    }

    for raw_trainer in parsed["trainers"]:
        trainer = _build_trainer_record(raw_trainer, constants, reports)
        trainers[trainer["symbol"]] = trainer
        trainer_order.append(trainer["symbol"])

    stats = _build_stats(trainers, reports, constants)
    source = {
        "project": "pokeemerald-expansion",
        "trainer_party": "src/data/trainers.party",
        "generated_header": "src/data/trainers.h",
        "generated_header_rule": "trainer_rules.mk",
        "generated_header_tool": "tools/trainerproc/main.c",
        "struct_definition": "include/data.h",
        "runtime_references": [
            "src/battle_main.c",
            "src/battle_setup.c",
            "src/trainer_pools.c",
            "include/data.h",
            "include/trainer_pools.h",
        ],
        "constant_references": [
            "include/constants/opponents.h",
            "include/constants/trainers.h",
            "include/constants/battle_ai.h",
            "include/constants/battle.h",
            "include/constants/difficulty.h",
            "include/constants/pokemon.h",
            "include/constants/pokeball.h",
            "include/battle_transition.h",
            "include/trainer_pools.h",
        ],
        "preprocessor": {
            "directives": parsed["directives"],
            "warnings": parsed["pragma_warnings"],
            "decisions": [
                "No C preprocessor branches were active in src/data/trainers.party during this export.",
            ],
        },
    }

    return {
        "schema_version": 1,
        "source": source,
        "config": _build_config(constants),
        "constants": _export_constants(constants),
        "trainer_order": trainer_order,
        "trainers": trainers,
        "stats": stats,
        "reports": reports,
    }


def _parse_trainers_party(path):
    trainers = []
    warnings = []
    directives = []
    pragma_warnings = []
    current = None
    current_mon = None
    mode = "outside"
    defaults = {
        "ivs": dict(DEFAULT_IVS),
        "level": 100,
        "ivs_explicit_required": False,
        "level_explicit_required": False,
    }

    lines = path.read_text(encoding="utf-8").splitlines()
    for line_number, raw_line in enumerate(lines, start=1):
        stripped = raw_line.strip()
        section = re.match(r"^===\s+(TRAINER_[A-Za-z0-9_]+)\s+===$", stripped)
        if section:
            if current is not None:
                trainers.append(current)
            current = {
                "symbol": section.group(1),
                "source": _source("src/data/trainers.party", line_number),
                "fields": [],
                "pokemon": [],
                "warnings": [],
            }
            current_mon = None
            mode = "trainer"
            continue

        pragma = _parse_trainerproc_pragma(stripped, line_number, defaults)
        if pragma is not None:
            directives.append(pragma)
            if pragma.get("warning"):
                pragma_warnings.append(pragma["warning"])
            continue

        if current is None:
            continue

        if not stripped or stripped.startswith("//"):
            if mode == "trainer":
                mode = "pokemon"
            current_mon = None
            continue

        trainer_field = _parse_field(stripped, TRAINER_FIELDS)
        if mode == "trainer" and trainer_field is not None:
            key, value = trainer_field
            current["fields"].append(_field(key, value, line_number))
            continue

        mode = "pokemon"
        pokemon_field = _parse_field(stripped, POKEMON_FIELDS)
        if pokemon_field is not None:
            if current_mon is None:
                current["warnings"].append(
                    _warning("pokemon_attribute_without_header", stripped, line_number)
                )
                continue
            key, value = pokemon_field
            current_mon["fields"].append(_field(key, value, line_number))
            continue

        nature_shorthand = _parse_nature_shorthand(stripped)
        if nature_shorthand is not None:
            if current_mon is None:
                current["warnings"].append(
                    _warning("nature_without_header", stripped, line_number)
                )
                continue
            current_mon["fields"].append(_field("Nature", nature_shorthand, line_number))
            continue

        if stripped.startswith("-"):
            if current_mon is None:
                current["warnings"].append(_warning("move_without_header", stripped, line_number))
                continue
            current_mon["moves"].append(
                {
                    "raw": stripped[1:].strip(),
                    "source": _source("src/data/trainers.party", line_number),
                }
            )
            continue

        current_mon = {
            "raw_header": stripped,
            "source": _source("src/data/trainers.party", line_number),
            "fields": [],
            "moves": [],
        }
        current["pokemon"].append(current_mon)

    if current is not None:
        trainers.append(current)

    return {
        "trainers": trainers,
        "defaults": defaults,
        "warnings": warnings + [warning for trainer in trainers for warning in trainer["warnings"]],
        "directives": directives,
        "pragma_warnings": pragma_warnings,
    }


def _parse_trainerproc_pragma(stripped, line_number, defaults):
    if not stripped.startswith("#pragma"):
        return None
    match = re.match(r"^#pragma\s+trainerproc\s+([A-Za-z_][A-Za-z0-9_]*)\s*(.*)$", stripped)
    if not match:
        return {
            "kind": "unsupported_pragma",
            "text": stripped,
            "source": _source("src/data/trainers.party", line_number),
            "warning": "unsupported pragma in trainers.party: {}".format(stripped),
        }

    key = match.group(1)
    value = match.group(2).strip()
    record = {
        "kind": key,
        "value": value,
        "source": _source("src/data/trainers.party", line_number),
    }
    if key == "ivs":
        if value == "explicit":
            defaults["ivs_explicit_required"] = True
        else:
            defaults["ivs"] = _parse_stats(value, dict(DEFAULT_IVS), [])
    elif key == "level":
        if value == "explicit":
            defaults["level_explicit_required"] = True
        else:
            try:
                defaults["level"] = int(value)
            except ValueError:
                record["warning"] = "invalid trainerproc level pragma: {}".format(value)
    else:
        record["warning"] = "unsupported trainerproc pragma: {}".format(stripped)
    return record


def _parse_field(line, known_fields):
    if ":" not in line:
        return None
    key, value = line.split(":", 1)
    key = key.strip()
    if key not in known_fields:
        return None
    return key, value.strip()


def _parse_nature_shorthand(line):
    match = re.match(r"^([A-Za-z][A-Za-z0-9_ '\\-]*)\s+Nature$", line)
    if not match:
        return None
    return match.group(1).strip()


def _field(key, value, line_number):
    return {
        "key": key,
        "value": value,
        "source": _source("src/data/trainers.party", line_number),
    }


def _build_trainer_record(raw, constants, reports):
    fields = _fields_by_key(raw["fields"])
    warnings = list(raw.get("warnings", []))
    symbol = raw["symbol"]
    trainer_id = constants["trainer_ids"].get(symbol)
    party_records = []

    for index, mon in enumerate(raw["pokemon"]):
        party_records.append(_build_pokemon_record(mon, index, constants, reports, warnings))

    is_copy_pool = "Copy Pool" in fields
    explicit_party_size = _int_field(fields.get("Party Size"))
    party_size = explicit_party_size if explicit_party_size is not None else (None if is_copy_pool else len(party_records))
    explicit_battle_type = "Double Battle" in fields or "Battle Type" in fields

    trainer = {
        "symbol": symbol,
        "id": trainer_id,
        "name_key": _constant_name(symbol, "TRAINER_"),
        "source": raw["source"],
        "difficulty": _constant_record(
            _field_value(fields, "Difficulty", "Normal"),
            constants["difficulties"],
            "DIFFICULTY",
            reports,
            _field_source(fields, "Difficulty", _default_source()),
            defaulted="Difficulty" not in fields,
        ),
        "name": _text_record(_field_value(fields, "Name", ""), _field_source(fields, "Name")),
        "trainer_class": _constant_record(
            _field_value(fields, "Class", "PkMn Trainer 1"),
            constants["trainer_classes"],
            "TRAINER_CLASS",
            reports,
            _field_source(fields, "Class"),
            defaulted="Class" not in fields,
        ),
        "pic": _constant_record(
            _field_value(fields, "Pic", ""),
            constants["trainer_pics"],
            "TRAINER_PIC_FRONT",
            reports,
            _field_source(fields, "Pic"),
            required=bool(fields.get("Pic")),
        ),
        "back_pic": _trainer_back_pic_record(fields, constants, reports),
        "gender": _constant_record(
            _field_value(fields, "Gender", "Male"),
            constants["trainer_genders"],
            "TRAINER_GENDER",
            reports,
            _field_source(fields, "Gender"),
            defaulted="Gender" not in fields,
        ),
        "encounter_music": _constant_record(
            _field_value(fields, "Music", "Male"),
            constants["encounter_music"],
            "TRAINER_ENCOUNTER_MUSIC",
            reports,
            _field_source(fields, "Music"),
            defaulted="Music" not in fields,
        ),
        "items": _trainer_items(fields, constants, reports),
        "battle_type": _battle_type_record(fields, constants),
        "ai_flags": _constant_records(
            _human_list(_field_value(fields, "AI", "")),
            constants["ai_flags"],
            "AI_FLAG",
            reports,
            _field_source(fields, "AI"),
        ),
        "mugshot": _constant_record(
            _field_value(fields, "Mugshot", "None"),
            constants["mugshots"],
            "MUGSHOT_COLOR",
            reports,
            _field_source(fields, "Mugshot", _default_source()),
            defaulted="Mugshot" not in fields,
        ),
        "starting_statuses": _starting_status_records(fields, constants, reports),
        "party_size": {
            "value": party_size,
            "explicit": explicit_party_size is not None,
            "source": _field_source(fields, "Party Size", _default_source()),
        },
        "pool": _pool_record(fields, constants, reports, len(party_records)),
        "macro": _raw_optional_field(fields, "Macro"),
        "party": party_records,
        "raw_fields": {field["key"]: field["value"] for field in raw["fields"]},
        "warnings": warnings,
    }
    trainer["ai_flags_mask"] = _mask_from_records(trainer["ai_flags"])
    trainer["battle_type"]["explicit"] = explicit_battle_type
    trainer["evaluation_status"] = "partial" if warnings else "ok"
    return trainer


def _build_pokemon_record(raw, index, constants, reports, trainer_warnings):
    fields = _fields_by_key(raw["fields"])
    header = _parse_pokemon_header(raw["raw_header"])
    rewrites = []
    species_raw = header["species"]
    gender_raw = header["gender"]
    item_raw = header["item"]

    if species_raw in GENDERED_SPECIES and gender_raw in {"M", "F"}:
        rewritten_species = GENDERED_SPECIES[species_raw][gender_raw]
        rewrites.append(
            {
                "kind": "gendered_species",
                "from_species": species_raw,
                "from_gender": gender_raw,
                "to_species": rewritten_species,
                "source": raw["source"],
            }
        )
        species_raw = rewritten_species
        gender_raw = None

    if species_raw in ITEMED_SPECIES and not item_raw:
        rewritten_species, rewritten_item = ITEMED_SPECIES[species_raw]
        rewrites.append(
            {
                "kind": "itemed_species",
                "from_species": species_raw,
                "to_species": rewritten_species,
                "to_item": rewritten_item,
                "source": raw["source"],
            }
        )
        species_raw = rewritten_species
        item_raw = rewritten_item

    reports["source_rewrites"].extend(rewrites)

    explicit_level = "Level" in fields
    explicit_ivs = "IVs" in fields
    explicit_evs = "EVs" in fields
    iv_values = _parse_stats(_field_value(fields, "IVs", ""), dict(DEFAULT_IVS), trainer_warnings) if explicit_ivs else dict(DEFAULT_IVS)
    ev_values = _parse_stats(_field_value(fields, "EVs", ""), dict(ZERO_STATS), trainer_warnings) if explicit_evs else None
    move_records = _constant_records(
        [move["raw"] for move in raw["moves"]],
        constants["moves"],
        "MOVE",
        reports,
        None,
    )
    for record, move in zip(move_records, raw["moves"]):
        record["source"] = move["source"]

    dynamax_explicit = "Dynamax Level" in fields
    gmax_explicit = "Gigantamax" in fields
    tera_explicit = "Tera Type" in fields
    should_dynamax = bool(dynamax_explicit or gmax_explicit)

    record = {
        "index": index,
        "source": raw["source"],
        "raw_header": raw["raw_header"],
        "nickname": _nickname_record(header["nickname"]),
        "source_species": _raw_optional_value(header["species"]),
        "species": _constant_record(species_raw, constants["species"], "SPECIES", reports, raw["source"]),
        "gender": _pokemon_gender_record(gender_raw, constants),
        "held_item": _constant_record(
            item_raw or "None",
            constants["items"],
            "ITEM",
            reports,
            raw["source"],
            defaulted=not bool(item_raw),
        ),
        "level": {
            "value": _int_field(fields.get("Level"), 100),
            "explicit": explicit_level,
            "defaulted": not explicit_level,
            "source": _field_source(fields, "Level", _default_source()),
        },
        "ivs": _stats_record(iv_values, "TRAINER_PARTY_IVS", explicit_ivs, not explicit_ivs, _field_source(fields, "IVs", _default_source())),
        "evs": _stats_record(ev_values, "TRAINER_PARTY_EVS", True, False, _field_source(fields, "EVs")) if explicit_evs else None,
        "ability": _constant_record(
            _field_value(fields, "Ability", "None"),
            constants["abilities"],
            "ABILITY",
            reports,
            _field_source(fields, "Ability", _default_source()),
            defaulted="Ability" not in fields,
        ),
        "ball": _ball_record(fields, constants, reports),
        "friendship": {
            "value": _int_field(fields.get("Happiness"), 0),
            "explicit": "Happiness" in fields,
            "source": _field_source(fields, "Happiness", _default_source()),
        },
        "nature": _constant_record(
            _field_value(fields, "Nature", "Hardy"),
            constants["natures"],
            "NATURE",
            reports,
            _field_source(fields, "Nature", _default_source()),
            defaulted="Nature" not in fields,
        ),
        "is_shiny": {
            "value": _bool_field(fields.get("Shiny"), False),
            "explicit": "Shiny" in fields,
            "source": _field_source(fields, "Shiny", _default_source()),
        },
        "dynamax_level": {
            "value": _int_field(fields.get("Dynamax Level"), constants["special_values"].get("MAX_DYNAMAX_LEVEL")),
            "explicit": dynamax_explicit,
            "defaulted": not dynamax_explicit,
            "symbol": "MAX_DYNAMAX_LEVEL" if not dynamax_explicit else None,
            "source": _field_source(fields, "Dynamax Level", _default_source()),
        },
        "gigantamax_factor": {
            "value": _bool_field(fields.get("Gigantamax"), False),
            "explicit": gmax_explicit,
            "source": _field_source(fields, "Gigantamax", _default_source()),
        },
        "should_use_dynamax": should_dynamax,
        "tera_type": _constant_record(
            _field_value(fields, "Tera Type", ""),
            constants["types"],
            "TYPE",
            reports,
            _field_source(fields, "Tera Type"),
            required=tera_explicit,
        ) if tera_explicit else None,
        "tags": _constant_records(
            _human_list(_field_value(fields, "Tags", "")),
            constants["pool_tags"],
            "MON_POOL_TAG",
            reports,
            _field_source(fields, "Tags"),
        ),
        "moves": move_records,
        "move_source_behavior": {
            "kind": "explicit" if move_records else "level_up_default",
            "source": "src/battle_main.c:CustomTrainerPartyAssignMoves",
        },
        "source_rewrites": rewrites,
        "raw_fields": {field["key"]: field["value"] for field in raw["fields"]},
    }
    record["tags_mask"] = _mask_from_records(record["tags"])
    return record


def _parse_pokemon_header(line):
    item = None
    if "@" in line:
        line, item = line.split("@", 1)
        item = item.strip()

    head = line.strip()
    groups = []
    while head.endswith(")"):
        open_index = head.rfind("(")
        if open_index == -1:
            break
        groups.insert(0, head[open_index + 1:-1].strip())
        head = head[:open_index].strip()

    nickname = None
    species = head
    gender = None
    if len(groups) == 1:
        if groups[0] in {"M", "F", "Male", "Female"}:
            gender = _gender_token(groups[0])
        else:
            nickname = head
            species = groups[0]
    elif len(groups) >= 2:
        nickname = head
        species = groups[0]
        gender = _gender_token(groups[1])

    return {
        "nickname": nickname,
        "species": species.strip(),
        "gender": gender,
        "item": item,
    }


def _gender_token(raw):
    if raw in {"M", "Male"}:
        return "M"
    if raw in {"F", "Female"}:
        return "F"
    return raw


def _load_trainer_constants(root):
    macros = _load_item_macro_expressions(root)
    for relative_path in [
        Path("include/constants/global.h"),
        Path("include/constants/opponents.h"),
        Path("include/constants/trainers.h"),
        Path("include/constants/battle.h"),
        Path("include/constants/battle_ai.h"),
        Path("include/constants/difficulty.h"),
        Path("include/constants/pokeball.h"),
        Path("include/trainer_pools.h"),
        Path("include/battle_transition.h"),
    ]:
        _read_defines_into(root / relative_path, macros)

    species_constants = load_species_constants(root, macros)
    move_constants = _load_move_constants(root, macros)
    item_constants = _load_item_constants(root, macros)
    trainer_ids = _parse_define_constants(root / "include/constants/opponents.h", "TRAINER_", macros)
    evaluator = ExpressionEvaluator(macros, unknown_as_zero=True)
    pool_rules = _parse_enum_constants(root / "include/trainer_pools.h", "PoolRulesets", macros)
    pool_pick_functions = _parse_enum_constants(root / "include/trainer_pools.h", "PoolPickFunctions", macros)
    pool_prune_options = _parse_enum_constants(root / "include/trainer_pools.h", "PoolPruneOptions", macros)
    _parse_enum_constants(root / "include/trainer_pools.h", "PoolTags", macros)

    return {
        "macros": macros,
        "evaluator": evaluator,
        "species": species_constants["species"],
        "moves": move_constants["moves"],
        "items": item_constants["items"],
        "abilities": species_constants["abilities"],
        "types": species_constants["types"],
        "natures": item_constants["natures"],
        "balls": item_constants["pokeballs"],
        "trainer_ids": trainer_ids,
        "trainer_pics": _parse_enum_constants(root / "include/constants/trainers.h", "TrainerPicID", macros),
        "trainer_classes": _parse_enum_constants(root / "include/constants/trainers.h", "TrainerClassID", macros),
        "encounter_music": _parse_define_constants(root / "include/constants/trainers.h", "TRAINER_ENCOUNTER_MUSIC_", macros),
        "trainer_genders": _parse_define_constants(root / "include/constants/trainers.h", "TRAINER_GENDER_", macros),
        "trainer_mon_genders": _parse_define_constants(root / "include/constants/trainers.h", "TRAINER_MON_", macros),
        "ai_flags": _parse_ai_flags(root, macros),
        "mugshots": _parse_enum_constants(root / "include/battle_transition.h", "MugshotColor", macros),
        "difficulties": _parse_enum_constants(root / "include/constants/difficulty.h", "DifficultyLevel", macros),
        "starting_statuses": _parse_starting_statuses(root),
        "pool_rules": pool_rules,
        "pool_pick_functions": pool_pick_functions,
        "pool_prune_options": pool_prune_options,
        "pool_tags": _parse_define_constants(root / "include/trainer_pools.h", "MON_POOL_TAG_", macros),
        "battle_types": {
            "TRAINER_BATTLE_TYPE_SINGLES": 0,
            "TRAINER_BATTLE_TYPE_DOUBLES": 1,
        },
        "special_values": {
            "PARTY_SIZE": evaluator.eval_int("PARTY_SIZE"),
            "MAX_MON_MOVES": evaluator.eval_int("MAX_MON_MOVES"),
            "TRAINER_NAME_LENGTH": evaluator.eval_int("TRAINER_NAME_LENGTH"),
            "TRAINERS_COUNT": evaluator.eval_int("TRAINERS_COUNT"),
            "MAX_TRAINERS_COUNT": evaluator.eval_int("MAX_TRAINERS_COUNT"),
            "MAX_DYNAMAX_LEVEL": evaluator.eval_int("MAX_DYNAMAX_LEVEL"),
            "POKEBALL_COUNT": _parse_enum_constants(root / "include/constants/pokeball.h", "PokeBall", macros).get("POKEBALL_COUNT"),
            "B_TRAINER_MON_RANDOM_ABILITY": evaluator.eval_int("B_TRAINER_MON_RANDOM_ABILITY"),
            "B_TRAINER_CLASS_POKE_BALLS": evaluator.eval_int("B_TRAINER_CLASS_POKE_BALLS"),
            "IS_FRLG": evaluator.eval_int("IS_FRLG"),
        },
    }


def _parse_ai_flags(root, macros):
    text = _strip_c_comments((root / "include/constants/battle_ai.h").read_text(encoding="utf-8"))
    raw_expressions = {}
    constants = {}
    for line in text.splitlines():
        match = re.match(r"^\s*#\s*define\s+(AI_FLAG_[A-Za-z0-9_]+)\s+(.+?)\s*$", line)
        if not match:
            continue
        name, expression = match.group(1), match.group(2).strip()
        raw_expressions[name] = expression
        flag_match = re.fullmatch(r"AI_FLAG\((\d+)\)", expression)
        if flag_match:
            value = 1 << int(flag_match.group(1))
            constants[name] = value
            macros[name] = str(value)

    evaluator = ExpressionEvaluator(macros)
    for name, expression in raw_expressions.items():
        if name in constants:
            continue
        value = evaluator.eval_int(expression)
        if value is not None:
            constants[name] = value
            macros[name] = str(value)
    return constants


def _parse_starting_statuses(root):
    text = _strip_c_comments((root / "include/constants/battle.h").read_text(encoding="utf-8"))
    constants = {}
    for value, match in enumerate(
        re.finditer(r"F\(\s*(STARTING_STATUS_[A-Za-z0-9_]+)\s*,\s*([A-Za-z_][A-Za-z0-9_]*)", text)
    ):
        constants[match.group(1)] = {
            "value": value,
            "field": match.group(2),
        }
    return constants


def _trainer_back_pic_record(fields, constants, reports):
    if "Back Pic" in fields:
        return _constant_record(
            _field_value(fields, "Back Pic", ""),
            constants["trainer_pics"],
            "TRAINER_PIC_BACK",
            reports,
            _field_source(fields, "Back Pic"),
            required=True,
        )
    return _constant_record(
        _field_value(fields, "Pic", ""),
        constants["trainer_pics"],
        "TRAINER_PIC_FRONT",
        reports,
        _field_source(fields, "Pic", _default_source()),
        defaulted=True,
    )


def _trainer_items(fields, constants, reports):
    items = _constant_records(
        _human_list(_field_value(fields, "Items", "")),
        constants["items"],
        "ITEM",
        reports,
        _field_source(fields, "Items"),
    )
    padded = list(items)
    while len(padded) < 4:
        padded.append(
            _constant_record(
                "None",
                constants["items"],
                "ITEM",
                reports,
                _default_source(),
                defaulted=True,
            )
        )
    return {
        "explicit": items,
        "padded_to_max": padded[:4],
        "max_items": 4,
    }


def _battle_type_record(fields, constants):
    if "Battle Type" in fields:
        raw_value = fields["Battle Type"]["value"]
        is_double = raw_value.lower() in {"double", "doubles"}
        source = fields["Battle Type"]["source"]
    elif "Double Battle" in fields:
        raw_value = fields["Double Battle"]["value"]
        is_double = _bool_field(fields["Double Battle"], False)
        source = fields["Double Battle"]["source"]
    else:
        raw_value = "Singles"
        is_double = False
        source = _default_source()

    symbol = "TRAINER_BATTLE_TYPE_DOUBLES" if is_double else "TRAINER_BATTLE_TYPE_SINGLES"
    return {
        "raw": raw_value,
        "symbol": symbol,
        "value": constants["battle_types"][symbol],
        "name": _constant_name(symbol, "TRAINER_BATTLE_TYPE_"),
        "is_double": is_double,
        "source": source,
    }


def _starting_status_records(fields, constants, reports):
    statuses = []
    for raw in _human_list(_field_value(fields, "Starting Status", "")):
        symbol = _constant_symbol("STARTING_STATUS", raw)
        definition = constants["starting_statuses"].get(symbol)
        record = {
            "raw": raw,
            "symbol": symbol,
            "name": _constant_name(symbol, "STARTING_STATUS_"),
            "source": _field_source(fields, "Starting Status"),
        }
        if definition is None:
            record["value"] = None
            reports["unresolved_constants"].append(
                {"kind": "starting_status", "raw": raw, "symbol": symbol, "source": record["source"]}
            )
        else:
            record["value"] = definition["value"]
            record["field"] = definition["field"]
        statuses.append(record)
    return statuses


def _pool_record(fields, constants, reports, pokemon_count):
    copy_pool = _raw_optional_field(fields, "Copy Pool")
    return {
        "rules": _constant_record(
            _field_value(fields, "Pool Rules", "Basic"),
            constants["pool_rules"],
            "POOL_RULESET",
            reports,
            _field_source(fields, "Pool Rules", _default_source()),
            defaulted="Pool Rules" not in fields,
        ),
        "pick_functions": _constant_record(
            _field_value(fields, "Pool Pick Functions", "Default"),
            constants["pool_pick_functions"],
            "POOL_PICK",
            reports,
            _field_source(fields, "Pool Pick Functions", _default_source()),
            defaulted="Pool Pick Functions" not in fields,
        ),
        "prune": _constant_record(
            _field_value(fields, "Pool Prune", "None"),
            constants["pool_prune_options"],
            "POOL_PRUNE",
            reports,
            _field_source(fields, "Pool Prune", _default_source()),
            defaulted="Pool Prune" not in fields,
        ),
        "copy_pool": copy_pool,
        "pool_size": None if copy_pool is not None else pokemon_count,
    }


def _ball_record(fields, constants, reports):
    if "Ball" in fields:
        return _constant_record(
            _field_value(fields, "Ball", ""),
            constants["balls"],
            "BALL",
            reports,
            _field_source(fields, "Ball"),
            required=True,
        )
    symbol = "POKEBALL_COUNT"
    value = constants["special_values"].get(symbol)
    return {
        "raw": symbol,
        "symbol": symbol,
        "value": value,
        "name": "default_by_trainer_class",
        "source": _default_source(),
        "defaulted": True,
    }


def _pokemon_gender_record(raw, constants):
    if raw == "M":
        symbol = "TRAINER_MON_MALE"
    elif raw == "F":
        symbol = "TRAINER_MON_FEMALE"
    else:
        symbol = "TRAINER_MON_RANDOM_GENDER"
    return {
        "raw": raw,
        "symbol": symbol,
        "value": constants["trainer_mon_genders"].get(symbol),
        "name": _constant_name(symbol, "TRAINER_MON_"),
        "defaulted": raw is None,
    }


def _constant_records(values, constants, prefix, reports, source):
    records = []
    for raw in values:
        records.append(_constant_record(raw, constants, prefix, reports, source, required=True))
    return records


def _constant_record(raw, constants, prefix, reports, source=None, defaulted=False, required=False):
    if raw is None or raw == "":
        if not required:
            return None
        symbol = ""
    elif prefix == "SPECIES":
        symbol = _species_symbol(raw)
    else:
        symbol = _constant_symbol(prefix, raw)
    value = constants.get(symbol)
    record = {
        "raw": raw,
        "symbol": symbol,
        "value": value,
        "name": _constant_name(symbol, prefix + "_"),
        "source": source,
        "defaulted": bool(defaulted),
    }
    if value is None and (required or raw not in {None, ""}):
        reports["unresolved_constants"].append(
            {"kind": prefix.lower(), "raw": raw, "symbol": symbol, "source": source}
        )
        record["status"] = "unresolved"
    else:
        record["status"] = "ok"
    return record


def _constant_symbol(prefix, raw):
    text = str(raw).strip()
    if not text.startswith(prefix + "_"):
        text = prefix + "_" + text
    output = []
    for char in text:
        if "A" <= char <= "Z" or char.isdigit() or char == "_":
            output.append(char)
        elif "a" <= char <= "z":
            output.append(char.upper())
        elif char == "'":
            continue
        else:
            output.append("_")
    return "".join(output)


def _species_symbol(raw):
    text = str(raw).strip()
    if text.startswith("SPECIES_"):
        return _constant_symbol("SPECIES", text)
    text = "SPECIES_" + text
    output = []
    pending_underscore = False
    for char in text:
        if "A" <= char <= "Z" or char.isdigit() or char == "_":
            if pending_underscore and output and output[-1] != "_":
                output.append("_")
            pending_underscore = False
            output.append(char)
        elif "a" <= char <= "z":
            if pending_underscore and output and output[-1] != "_":
                output.append("_")
            pending_underscore = False
            output.append(char.upper())
        elif char in {"'", "%", "\u2019"}:
            continue
        elif char in {"\u2642"}:
            if output and output[-1] != "_":
                output.append("_")
            output.append("M")
            pending_underscore = False
        elif char in {"\u2640"}:
            if output and output[-1] != "_":
                output.append("_")
            output.append("F")
            pending_underscore = False
        elif char in {"\u00e9", "\u00c9"}:
            if pending_underscore and output and output[-1] != "_":
                output.append("_")
            pending_underscore = False
            output.append("E")
        else:
            pending_underscore = True
    return "".join(output)


def _constant_name(symbol, prefix):
    if symbol is None:
        return ""
    text = str(symbol)
    if text.startswith(prefix):
        text = text[len(prefix):]
    return text.lower()


def _fields_by_key(fields):
    result = {}
    for field in fields:
        result[field["key"]] = field
    return result


def _field_value(fields, key, default=None):
    field = fields.get(key)
    if field is None:
        return default
    return field.get("value", default)


def _field_source(fields, key, default=None):
    field = fields.get(key)
    if field is None:
        return default
    return field.get("source", default)


def _raw_optional_field(fields, key):
    if key not in fields:
        return None
    return {
        "raw": fields[key]["value"],
        "source": fields[key]["source"],
    }


def _raw_optional_value(value):
    if value is None:
        return None
    return {"raw": value}


def _text_record(raw, source):
    return {
        "raw": raw,
        "display_text": display_text_from_source(raw or ""),
        "source": source,
    }


def _nickname_record(raw):
    if raw is None:
        return None
    return {
        "raw": raw,
        "display_text": display_text_from_source(raw),
    }


def _human_list(value):
    if value is None or str(value).strip() == "":
        return []
    return [part.strip() for part in str(value).split("/") if part.strip()]


def _parse_stats(raw, defaults, warnings):
    values = dict(defaults)
    if raw is None:
        return values
    for part in str(raw).split("/"):
        stripped = part.strip()
        if not stripped:
            continue
        match = re.match(r"^([0-9]+)\s+([A-Za-z]+)$", stripped)
        if not match:
            warnings.append({"kind": "invalid_stats_part", "text": stripped})
            continue
        value = int(match.group(1))
        stat = STAT_LABELS.get(match.group(2))
        if stat is None:
            warnings.append({"kind": "unknown_stat_label", "text": stripped})
            continue
        values[stat] = value
    return values


def _stats_record(values, macro, explicit, defaulted, source):
    record = {
        "values": dict(values),
        "order": STAT_ORDER,
        "explicit": bool(explicit),
        "defaulted": bool(defaulted),
        "source_macro": macro,
        "source": source,
    }
    if macro == "TRAINER_PARTY_IVS":
        record["packed_value"] = _pack_ivs(values)
    else:
        record["struct_order"] = EV_STRUCT_ORDER
    return record


def _pack_ivs(values):
    return (
        int(values["hp"])
        | (int(values["attack"]) << 5)
        | (int(values["defense"]) << 10)
        | (int(values["speed"]) << 15)
        | (int(values["sp_attack"]) << 20)
        | (int(values["sp_defense"]) << 25)
    )


def _int_field(field, default=None):
    if field is None:
        return default
    value = field.get("value") if isinstance(field, dict) else field
    try:
        return int(str(value).strip(), 0)
    except (TypeError, ValueError):
        return default


def _bool_field(field, default=False):
    if field is None:
        return default
    value = field.get("value") if isinstance(field, dict) else field
    text = str(value).strip().lower()
    if text in {"yes", "true", "1", "double", "doubles"}:
        return True
    if text in {"no", "false", "0", "single", "singles"}:
        return False
    return default


def _mask_from_records(records):
    mask = 0
    for record in records:
        if not isinstance(record, dict):
            continue
        value = record.get("value")
        if value is not None:
            mask |= int(value)
    return mask


def _build_config(constants):
    special = constants["special_values"]
    return {
        "target": {
            "is_frlg": bool(special.get("IS_FRLG")),
            "trainers_count": special.get("TRAINERS_COUNT"),
            "max_trainers_count": special.get("MAX_TRAINERS_COUNT"),
        },
        "party": {
            "party_size": special.get("PARTY_SIZE"),
            "max_mon_moves": special.get("MAX_MON_MOVES"),
            "trainer_name_length": special.get("TRAINER_NAME_LENGTH"),
        },
        "battle": {
            "trainer_mon_random_ability": bool(special.get("B_TRAINER_MON_RANDOM_ABILITY")),
            "trainer_class_poke_balls": special.get("B_TRAINER_CLASS_POKE_BALLS"),
            "max_dynamax_level": special.get("MAX_DYNAMAX_LEVEL"),
        },
    }


def _export_constants(constants):
    return {
        "trainer_ids": _export_constant_group(constants["trainer_ids"], "TRAINER_"),
        "trainer_classes": _export_constant_group(constants["trainer_classes"], "TRAINER_CLASS_"),
        "trainer_pics": _export_constant_group(constants["trainer_pics"], "TRAINER_PIC_"),
        "encounter_music": _export_constant_group(constants["encounter_music"], "TRAINER_ENCOUNTER_MUSIC_"),
        "trainer_genders": _export_constant_group(constants["trainer_genders"], "TRAINER_GENDER_"),
        "trainer_mon_genders": _export_constant_group(constants["trainer_mon_genders"], "TRAINER_MON_"),
        "ai_flags": _export_constant_group(constants["ai_flags"], "AI_FLAG_"),
        "mugshots": _export_constant_group(constants["mugshots"], "MUGSHOT_COLOR_"),
        "difficulties": _export_constant_group(constants["difficulties"], "DIFFICULTY_"),
        "battle_types": _export_constant_group(constants["battle_types"], "TRAINER_BATTLE_TYPE_"),
        "pool_rules": _export_constant_group(constants["pool_rules"], "POOL_RULESET_"),
        "pool_pick_functions": _export_constant_group(constants["pool_pick_functions"], "POOL_PICK_"),
        "pool_prune_options": _export_constant_group(constants["pool_prune_options"], "POOL_PRUNE_"),
        "pool_tags": _export_constant_group(constants["pool_tags"], "MON_POOL_TAG_"),
        "special_values": constants["special_values"],
        "external_reference_counts": {
            "species": len(constants["species"]),
            "moves": len(constants["moves"]),
            "items": len(constants["items"]),
            "abilities": len(constants["abilities"]),
            "types": len(constants["types"]),
            "natures": len(constants["natures"]),
            "balls": len(constants["balls"]),
        },
    }


def _export_constant_group(constants, prefix):
    exported = {}
    for symbol, value in sorted(constants.items(), key=lambda item: (item[1] if isinstance(item[1], int) else 0, item[0])):
        if isinstance(value, dict):
            record = dict(value)
            record["name"] = _constant_name(symbol, prefix)
        else:
            record = {
                "value": value,
                "name": _constant_name(symbol, prefix),
            }
        exported[symbol] = record
    return exported


def _build_stats(trainers, reports, constants):
    party_mon_count = sum(len(record.get("party", [])) for record in trainers.values())
    move_mon_count = 0
    default_move_mon_count = 0
    held_item_mon_count = 0
    unique_species = set()
    unique_moves = set()
    for trainer in trainers.values():
        for mon in trainer.get("party", []):
            species = mon.get("species") or {}
            if species.get("symbol"):
                unique_species.add(species["symbol"])
            if (mon.get("held_item") or {}).get("symbol") != "ITEM_NONE":
                held_item_mon_count += 1
            moves = mon.get("moves", [])
            if moves:
                move_mon_count += 1
            else:
                default_move_mon_count += 1
            for move in moves:
                if move.get("symbol"):
                    unique_moves.add(move["symbol"])

    return {
        "trainer_count": len(trainers),
        "trainers_count_constant": constants["special_values"].get("TRAINERS_COUNT"),
        "highest_trainer_id": max((record.get("id") or 0 for record in trainers.values()), default=0),
        "party_mon_count": party_mon_count,
        "double_battle_count": sum(1 for record in trainers.values() if (record.get("battle_type") or {}).get("is_double")),
        "trainer_with_items_count": sum(1 for record in trainers.values() if (record.get("items") or {}).get("explicit")),
        "trainer_with_ai_flags_count": sum(1 for record in trainers.values() if record.get("ai_flags")),
        "trainer_with_mugshot_count": sum(1 for record in trainers.values() if not (record.get("mugshot") or {}).get("defaulted")),
        "explicit_move_mon_count": move_mon_count,
        "default_move_mon_count": default_move_mon_count,
        "held_item_mon_count": held_item_mon_count,
        "unique_species_count": len(unique_species),
        "unique_move_count": len(unique_moves),
        "source_rewrite_count": len(reports["source_rewrites"]),
        "warning_count": len(reports["warnings"]),
        "unsupported_field_count": len(reports["unsupported_fields"]),
        "unresolved_constant_count": len(reports["unresolved_constants"]),
    }


def _source(file_name, line_number):
    return {
        "file": file_name,
        "line": line_number,
    }


def _default_source():
    return {
        "file": "tools/trainerproc/main.c",
        "line": 2157,
    }


def _warning(kind, text, line_number):
    return {
        "kind": kind,
        "text": text,
        "source": _source("src/data/trainers.party", line_number),
    }


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, help="JSON config with source and output roots.")
    parser.add_argument("--source", type=Path, help="pokeemerald-expansion source root.")
    parser.add_argument("--output-root", type=Path, help="Generated data output root.")
    args = parser.parse_args(argv)

    config = load_config(args.config)
    source_root = args.source or Path(config.get("source_root", ""))
    output_root = args.output_root or Path(config.get("generated_data_root", "data/generated"))

    exported = export_trainers(source_root)
    output_path = output_root / "pokemon" / "trainers.json"
    write_json(output_path, exported)

    manifest_entry = {
        "category": "trainers",
        "path": to_project_path(output_path),
        "trainer_count": exported["stats"]["trainer_count"],
        "party_mon_count": exported["stats"]["party_mon_count"],
        "trainer_with_mugshot_count": exported["stats"]["trainer_with_mugshot_count"],
        "warning_count": exported["stats"]["warning_count"],
        "unresolved_constant_count": exported["stats"]["unresolved_constant_count"],
    }
    write_manifest(
        output_root / "import_manifest.json",
        exported_pokemon=[manifest_entry],
        generator="tools/importer/export_trainers.py",
    )
    print(
        "Exported {trainer_count} trainers, {party_mon_count} party mons to {path}".format(
            path=to_project_path(output_path),
            **exported["stats"],
        )
    )


if __name__ == "__main__":
    main()
