#!/usr/bin/env python3
"""Export pokeemerald-expansion ability data into generated JSON."""

import argparse
import json
import re
import sys
from pathlib import Path

from export_map import write_json, write_manifest
from export_moves import _parse_designated_field_assignments
from export_species import (
    ExpressionEvaluator,
    _compact_source,
    _eval_field_int,
    _export_constant_group,
    _find_matching_brace,
    _parse_enum_constants,
    _preprocess_records,
    _read_defines_into,
    _read_source_lines,
    _relative_source_location,
    _remove_prefix,
)
from source_probe import load_config, to_project_path
from text_codec import display_text_from_source


ABILITY_ENTRY_RE = re.compile(r"\[(ABILITY_[A-Za-z0-9_]*)\]\s*=")

ABILITY_FLAG_FIELDS = [
    "cantBeCopied",
    "cantBeSwapped",
    "cantBeTraced",
    "cantBeSuppressed",
    "cantBeOverwritten",
    "breakable",
    "failsOnImposter",
]


def _load_ability_macro_expressions(root):
    macros = {
        "TRUE": "1",
        "FALSE": "0",
        "NULL": "0",
    }
    config_files = [
        Path("include/gba/defines.h"),
        Path("include/config/general.h"),
        Path("include/config/battle.h"),
        Path("include/constants/global.h"),
    ]
    for relative_path in config_files:
        _read_defines_into(root / relative_path, macros)
    return macros


def _load_ability_constants(root, macros):
    constants = {
        "abilities": _parse_enum_constants(root / "include/constants/abilities.h", "Ability", macros),
    }
    constants["evaluator"] = ExpressionEvaluator(macros)
    return constants


def _parse_ability_entries(root, records, constants):
    abilities = {}
    order = []
    index = 0
    while index < len(records):
        match = ABILITY_ENTRY_RE.search(records[index].text)
        if not match:
            index += 1
            continue

        symbol = match.group(1)
        start_record = records[index]
        initializer_lines = [records[index].text[match.end():]]
        end_index = index

        while end_index + 1 < len(records) and not "".join(initializer_lines).strip():
            end_index += 1
            initializer_lines.append(records[end_index].text)

        initializer_text = "\n".join(initializer_lines)
        stripped_initializer = initializer_text.lstrip()
        leading_offset = len(initializer_text) - len(stripped_initializer)
        raw_initializer = initializer_text.strip()
        fields = {}
        initializer_kind = "unknown"

        if stripped_initializer.startswith("{"):
            initializer_kind = "struct"
            open_index = leading_offset
            close_index = _find_matching_brace(initializer_text, open_index)
            while close_index == -1 and end_index + 1 < len(records):
                end_index += 1
                initializer_text += "\n" + records[end_index].text
                close_index = _find_matching_brace(initializer_text, open_index)
            if close_index != -1:
                raw_initializer = initializer_text[open_index:close_index + 1]
                fields = _parse_designated_field_assignments(raw_initializer[1:-1])

        record = _build_ability_record(root, symbol, start_record, initializer_kind, raw_initializer, fields, constants)
        abilities[symbol] = record
        order.append(symbol)
        index = end_index + 1

    order.sort(key=lambda item: (abilities[item].get("id") is None, abilities[item].get("id", 0), item))
    return abilities, order


def _build_ability_record(root, symbol, source_record, initializer_kind, raw_initializer, fields, constants):
    evaluator = constants["evaluator"]
    warnings = []
    defaulted_fields = []
    record = {
        "id": _constant_value(symbol, constants["abilities"]),
        "symbol": symbol,
        "name_key": _remove_prefix(symbol, "ABILITY_").lower(),
        "source": _relative_source_location(root, source_record),
        "initializer_kind": initializer_kind,
    }

    if initializer_kind != "struct":
        record["raw_initializer"] = _compact_source(raw_initializer)
        record["evaluation_status"] = "partial"
        record["warnings"] = ["ability initializer is not a struct initializer"]
        return record

    raw_fields = {field: _compact_source(value) for field, value in fields.items()}
    record["raw_fields"] = raw_fields

    if "name" in fields:
        record["name"] = _parse_ability_text_value(fields["name"])
    if "description" in fields:
        record["description"] = _parse_ability_text_value(fields["description"])

    if "aiRating" in fields:
        record["ai_rating"] = _eval_field_int(fields["aiRating"], evaluator, warnings)
    else:
        record["ai_rating"] = 0
        defaulted_fields.append("ai_rating")

    flags = {}
    raw_flag_fields = {}
    for source_field in ABILITY_FLAG_FIELDS:
        output_field = _camel_to_snake(source_field)
        if source_field in fields:
            flags[output_field] = bool(_eval_field_int(fields[source_field], evaluator, warnings))
            raw_flag_fields[output_field] = _compact_source(fields[source_field])
        else:
            flags[output_field] = False
            defaulted_fields.append(output_field)
    record["flags"] = flags
    if raw_flag_fields:
        record["raw_flag_fields"] = raw_flag_fields

    known_fields = {"name", "description", "aiRating"}
    known_fields.update(ABILITY_FLAG_FIELDS)
    unsupported = sorted(field for field in fields.keys() if field not in known_fields)
    if unsupported:
        record["unsupported_fields"] = unsupported

    if defaulted_fields:
        record["defaulted_fields"] = sorted(defaulted_fields)
    if warnings:
        record["warnings"] = sorted(set(warnings))
    record["evaluation_status"] = "partial" if warnings or unsupported else "ok"
    return record


def _parse_ability_text_value(value):
    raw = _extract_string_literals(value)
    if raw is None:
        return {
            "kind": "reference",
            "raw": _compact_source(value),
        }
    return {
        "kind": "inline",
        "source_text": raw,
        "display_text": display_text_from_source(raw),
    }


def _extract_string_literals(value):
    matches = re.findall(r'"((?:\\.|[^"\\])*)"', value, re.S)
    if not matches:
        return None
    return "".join(matches)


def _constant_value(symbol, constants):
    value = constants.get(symbol)
    return int(value) if isinstance(value, int) else None


def _camel_to_snake(value):
    chars = []
    for index, char in enumerate(value):
        if char.isupper() and index > 0:
            chars.append("_")
        chars.append(char.lower())
    return "".join(chars)


def export_abilities(root):
    macros = _load_ability_macro_expressions(root)
    constants = _load_ability_constants(root, macros)
    source_records = _read_source_lines(root / "src/data/abilities.h")
    preprocessed_records, preprocessor_report = _preprocess_records(source_records, macros)
    abilities, ability_order = _parse_ability_entries(root, preprocessed_records, constants)

    ability_with_present_ai_rating_count = sum(1 for record in abilities.values() if "aiRating" in record.get("raw_fields", {}))
    ability_with_any_true_flag_count = sum(1 for record in abilities.values() if any(record.get("flags", {}).values()))
    ability_with_any_present_flag_count = sum(1 for record in abilities.values() if record.get("raw_flag_fields"))
    warning_count = len(preprocessor_report["warnings"])
    warning_count += sum(len(record.get("warnings", [])) for record in abilities.values())
    unsupported_field_count = sum(len(record.get("unsupported_fields", [])) for record in abilities.values())

    return {
        "schema_version": 1,
        "source": {
            "project": "pokeemerald-expansion",
            "abilities_info": "src/data/abilities.h",
            "struct_definition": "include/pokemon.h",
            "constants": [
                "include/constants/abilities.h",
                "include/constants/global.h",
            ],
            "config": [
                "include/config/general.h",
                "include/config/battle.h",
            ],
            "behavior_references": [
                "src/battle_ai_main.c",
                "src/battle_ai_util.c",
                "src/battle_interface.c",
                "src/battle_message.c",
                "src/battle_script_commands.c",
                "src/battle_util.c",
                "src/dexnav.c",
                "src/ow_abilities.c",
                "src/party_menu.c",
                "src/pokedex_plus_hgss.c",
                "src/pokemon.c",
                "src/pokemon_summary_screen.c",
                "src/wild_encounter.c",
            ],
            "preprocessor": preprocessor_report,
        },
        "constants": {
            "abilities": _export_constant_group(constants["abilities"], "ABILITY_"),
        },
        "ability_order": ability_order,
        "abilities": abilities,
        "stats": {
            "ability_count": len(abilities),
            "abilities_with_present_ai_rating": ability_with_present_ai_rating_count,
            "abilities_with_any_present_flag": ability_with_any_present_flag_count,
            "abilities_with_any_true_flag": ability_with_any_true_flag_count,
            "preprocessor_decision_count": len(preprocessor_report["decisions"]),
            "preprocessor_warning_count": len(preprocessor_report["warnings"]),
            "warning_count": warning_count,
            "unsupported_field_count": unsupported_field_count,
        },
    }


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, help="JSON config with source and output roots.")
    parser.add_argument("--source", type=Path, help="pokeemerald-expansion source root.")
    parser.add_argument("--output-root", type=Path, help="Generated data output root.")
    args = parser.parse_args(argv)

    config = load_config(args.config)
    source_root = args.source or Path(config.get("source_root", ""))
    output_root = args.output_root or Path(config.get("generated_data_root", "data/generated"))

    exported = export_abilities(source_root)
    abilities_output = output_root / "pokemon" / "abilities.json"
    write_json(abilities_output, exported)

    stats = exported["stats"]
    manifest_entry = {
        "category": "abilities",
        "path": to_project_path(abilities_output),
        "ability_count": stats["ability_count"],
        "abilities_with_present_ai_rating": stats["abilities_with_present_ai_rating"],
        "abilities_with_any_present_flag": stats["abilities_with_any_present_flag"],
        "abilities_with_any_true_flag": stats["abilities_with_any_true_flag"],
        "warning_count": stats["warning_count"],
    }
    write_manifest(
        output_root / "import_manifest.json",
        exported_pokemon=[manifest_entry],
        generator="tools/importer/export_abilities.py",
    )

    print(json.dumps({
        "exported": manifest_entry,
        "preprocessor_decision_count": stats["preprocessor_decision_count"],
        "unsupported_field_count": stats["unsupported_field_count"],
    }, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
