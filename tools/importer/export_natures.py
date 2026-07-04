#!/usr/bin/env python3
"""Export pokeemerald-expansion nature data into generated JSON."""

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
    _constant_record,
    _eval_field_int,
    _export_constant_group,
    _find_matching_brace,
    _load_macro_expressions,
    _parse_define_constants,
    _parse_enum_constants,
    _preprocess_records,
    _read_defines_into,
    _read_source_lines,
    _relative_source_location,
    _remove_prefix,
    _split_top_level,
    _strip_c_comments,
)
from source_probe import load_config, to_project_path
from text_codec import display_text_from_source


NATURE_ENTRY_RE = re.compile(r"\[(NATURE_[A-Za-z0-9_]*)\]\s*=")
PALACE_STYLE_RE = re.compile(r"PALACE_STYLE\s*\((.*)\)$", re.S)

KNOWN_NATURE_FIELDS = {
    "name",
    "statUp",
    "statDown",
    "backAnim",
    "pokeBlockAnim",
    "battlePalacePercents",
    "battlePalaceFlavorText",
    "battlePalaceSmokescreen",
    "natureGirlMessage",
}


def _load_nature_macro_expressions(root):
    macros = _load_macro_expressions(root)
    _read_defines_into(root / "include/pokemon.h", macros)
    return macros


def _load_nature_constants(root, macros):
    constants = {
        "natures": _parse_define_constants(root / "include/constants/pokemon.h", "NATURE_", macros),
        "stats": _parse_enum_constants(root / "include/constants/pokemon.h", "Stat", macros),
        "pokeblock_anims": _parse_define_constants(root / "include/pokemon.h", "ANIM_", macros),
        "affines": _parse_anonymous_enum_constants(root / "include/pokemon.h", "AFFINE_NONE", macros),
        "battle_palace_flavor_text": _parse_enum_constants(
            root / "include/constants/battle_string_ids.h",
            "BattlePalaceFlavorTextID",
            macros,
        ),
        "battle_palace_targets": _parse_define_constants(root / "include/pokemon.h", "PALACE_TARGET_", macros),
    }
    constants["poke_block_anim"] = dict(constants["pokeblock_anims"])
    constants["poke_block_anim"].update(constants["affines"])
    constants["evaluator"] = ExpressionEvaluator(macros)
    return constants


def _parse_anonymous_enum_constants(path, required_symbol, macros):
    text = _strip_c_comments(path.read_text(encoding="utf-8"))
    constants = {}
    for match in re.finditer(r"enum\s*\{", text):
        brace_start = text.find("{", match.start())
        brace_end = _find_matching_brace(text, brace_start)
        if brace_end == -1:
            continue
        body = text[brace_start + 1:brace_end]
        if required_symbol not in body:
            continue
        evaluator = ExpressionEvaluator(macros)
        current_value = 0
        for entry in _split_top_level(body, ","):
            item = entry.strip()
            if not item:
                continue
            name_match = re.match(r"([A-Za-z_][A-Za-z0-9_]*)(?:\s*=\s*(.+))?$", item, re.S)
            if not name_match:
                continue
            name = name_match.group(1)
            expression = name_match.group(2)
            if expression is not None:
                value = evaluator.eval_int(expression)
                if value is None:
                    value = current_value
            else:
                value = current_value
            constants[name] = value
            macros[name] = str(value)
            current_value = value + 1
        return constants
    return constants


def _parse_nature_entries(root, records, constants):
    natures = {}
    order = []
    index = 0
    while index < len(records):
        match = NATURE_ENTRY_RE.search(records[index].text)
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

        record = _build_nature_record(root, symbol, start_record, initializer_kind, raw_initializer, fields, constants)
        natures[symbol] = record
        order.append(symbol)
        index = end_index + 1

    order.sort(key=lambda item: (natures[item].get("id") is None, natures[item].get("id", 0), item))
    return natures, order


def _nature_table_records(records):
    start_index = -1
    for index, record in enumerate(records):
        if "const struct NatureInfo gNaturesInfo" in record.text:
            start_index = index
            break
    if start_index == -1:
        return records

    saw_table_body = False
    for index in range(start_index, len(records)):
        line = records[index].text.strip()
        if line.startswith("{"):
            saw_table_body = True
        if saw_table_body and line == "};":
            return records[start_index:index + 1]
    return records[start_index:]


def _build_nature_record(root, symbol, source_record, initializer_kind, raw_initializer, fields, constants):
    evaluator = constants["evaluator"]
    warnings = []
    record = {
        "id": _constant_value(symbol, constants["natures"]),
        "symbol": symbol,
        "name_key": _remove_prefix(symbol, "NATURE_").lower(),
        "source": _relative_source_location(root, source_record),
        "initializer_kind": initializer_kind,
    }

    if initializer_kind != "struct":
        record["raw_initializer"] = _compact_source(raw_initializer)
        record["evaluation_status"] = "partial"
        record["warnings"] = ["nature initializer is not a struct initializer"]
        return record

    record["raw_fields"] = {field: _compact_source(value) for field, value in fields.items()}

    if "name" in fields:
        record["name"] = _parse_nature_text_value(fields["name"])

    stat_up = _constant_record(fields.get("statUp", "STAT_HP"), constants["stats"], "STAT_", evaluator, warnings)
    stat_down = _constant_record(fields.get("statDown", "STAT_HP"), constants["stats"], "STAT_", evaluator, warnings)
    record["stat_up"] = stat_up
    record["stat_down"] = stat_down
    record["neutral"] = stat_up.get("value") == stat_down.get("value")
    record["stat_modifier"] = {
        "source": "src/pokemon.c:ModifyStatByNature",
        "up_multiplier": {"numerator": 110, "denominator": 100},
        "down_multiplier": {"numerator": 90, "denominator": 100},
        "integer_division": True,
    }

    if "backAnim" in fields:
        record["back_anim"] = {
            "raw": _compact_source(fields["backAnim"]),
            "value": _eval_field_int(fields["backAnim"], evaluator, warnings),
        }
    if "pokeBlockAnim" in fields:
        record["poke_block_anim"] = _parse_constant_array(
            fields["pokeBlockAnim"],
            constants["poke_block_anim"],
            "",
            evaluator,
            warnings,
        )
    if "battlePalacePercents" in fields:
        record["battle_palace_percents"] = _parse_battle_palace_percents(fields["battlePalacePercents"], evaluator, warnings)
    if "battlePalaceFlavorText" in fields:
        record["battle_palace_flavor_text"] = _constant_record(
            fields["battlePalaceFlavorText"],
            constants["battle_palace_flavor_text"],
            "B_MSG_",
            evaluator,
            warnings,
        )
    if "battlePalaceSmokescreen" in fields:
        record["battle_palace_smokescreen"] = _constant_record(
            fields["battlePalaceSmokescreen"],
            constants["battle_palace_targets"],
            "PALACE_TARGET_",
            evaluator,
            warnings,
        )
    if "natureGirlMessage" in fields:
        record["nature_girl_message"] = {
            "symbol": _compact_source(fields["natureGirlMessage"]),
            "source": "data/scripts/battle_frontier_lounge.inc",
        }

    unsupported = sorted(field for field in fields.keys() if field not in KNOWN_NATURE_FIELDS)
    if unsupported:
        record["unsupported_fields"] = unsupported
    if warnings:
        record["warnings"] = sorted(set(warnings))
    record["evaluation_status"] = "partial" if warnings or unsupported else "ok"
    return record


def _parse_nature_text_value(value):
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


def _parse_constant_array(value, constants, prefix, evaluator, warnings):
    raw = _compact_source(value)
    if raw.startswith("{") and raw.endswith("}"):
        items = [_compact_source(item) for item in _split_top_level(raw[1:-1], ",") if item.strip()]
    else:
        items = [raw]
    return [_constant_record(item, constants, prefix, evaluator, warnings) for item in items]


def _parse_battle_palace_percents(value, evaluator, warnings):
    raw = _compact_source(value)
    match = PALACE_STYLE_RE.fullmatch(raw)
    if match:
        args = [_compact_source(item) for item in _split_top_level(match.group(1), ",") if item.strip()]
        if len(args) == 4:
            values = [_eval_field_int(arg, evaluator, warnings) for arg in args]
            if all(item is not None for item in values):
                high_attack, high_defense, low_attack, low_defense = values
                cumulative = [
                    high_attack,
                    high_attack + high_defense,
                    low_attack,
                    low_attack + low_defense,
                ]
                return {
                    "raw": raw,
                    "macro": "PALACE_STYLE",
                    "stored_cumulative": cumulative,
                    "high_hp": {
                        "attack": high_attack,
                        "defense": high_defense,
                        "support": 100 - cumulative[1],
                    },
                    "low_hp": {
                        "attack": low_attack,
                        "defense": low_defense,
                        "support": 100 - cumulative[3],
                    },
                    "source": "src/pokemon.c:PALACE_STYLE",
                }
        warnings.append("could not parse PALACE_STYLE expression: {}".format(raw))
        return {"raw": raw, "macro": "PALACE_STYLE", "stored_cumulative": []}

    values = []
    if raw.startswith("{") and raw.endswith("}"):
        items = [_compact_source(item) for item in _split_top_level(raw[1:-1], ",") if item.strip()]
    else:
        items = [raw]
    for item in items:
        values.append(_eval_field_int(item, evaluator, warnings))
    return {
        "raw": raw,
        "stored_cumulative": values,
        "source": "src/pokemon.c:gNaturesInfo",
    }


def _constant_value(symbol, constants):
    value = constants.get(symbol)
    return int(value) if isinstance(value, int) else None


def export_natures(root):
    macros = _load_nature_macro_expressions(root)
    constants = _load_nature_constants(root, macros)
    source_records = _nature_table_records(_read_source_lines(root / "src/pokemon.c"))
    preprocessed_records, preprocessor_report = _preprocess_records(source_records, macros)
    natures, nature_order = _parse_nature_entries(root, preprocessed_records, constants)

    neutral_count = sum(1 for record in natures.values() if bool(record.get("neutral", False)))
    non_neutral_count = len(natures) - neutral_count
    warning_count = len(preprocessor_report["warnings"])
    warning_count += sum(len(record.get("warnings", [])) for record in natures.values())
    unsupported_field_count = sum(len(record.get("unsupported_fields", [])) for record in natures.values())
    unresolved_stat_count = 0
    for record in natures.values():
        for field in ["stat_up", "stat_down"]:
            stat_record = record.get(field, {})
            if not isinstance(stat_record, dict) or stat_record.get("value") is None:
                unresolved_stat_count += 1

    return {
        "schema_version": 1,
        "source": {
            "project": "pokeemerald-expansion",
            "natures_info": "src/pokemon.c:gNaturesInfo",
            "struct_definition": "include/pokemon.h:struct NatureInfo",
            "constants": [
                "include/constants/pokemon.h",
                "include/pokemon.h",
                "include/constants/battle_string_ids.h",
            ],
            "runtime_references": [
                "src/pokemon.c:CalculateMonStats",
                "src/pokemon.c:ModifyStatByNature",
                "src/pokemon.c:GetNature",
                "src/pokemon.c:GetNatureFromPersonality",
                "src/pokemon_summary_screen.c",
                "src/battle_palace.c",
            ],
            "stat_modifier": {
                "source": "src/pokemon.c:ModifyStatByNature",
                "excludes": ["STAT_HP", "STAT_ACC", "STAT_EVASION"],
                "neutral_rule": "statUp == statDown",
                "up_multiplier": {"numerator": 110, "denominator": 100},
                "down_multiplier": {"numerator": 90, "denominator": 100},
                "integer_division": True,
            },
            "preprocessor": preprocessor_report,
        },
        "constants": {
            "natures": _export_constant_group(constants["natures"], "NATURE_"),
            "stats": _export_constant_group(constants["stats"], "STAT_"),
            "pokeblock_anims": _export_constant_group(constants["pokeblock_anims"], "ANIM_"),
            "affines": _export_constant_group(constants["affines"], "AFFINE_"),
            "battle_palace_flavor_text": _export_constant_group(constants["battle_palace_flavor_text"], "B_MSG_"),
            "battle_palace_targets": _export_constant_group(constants["battle_palace_targets"], "PALACE_TARGET_"),
        },
        "nature_order": nature_order,
        "natures": natures,
        "stats": {
            "nature_count": len(natures),
            "neutral_nature_count": neutral_count,
            "non_neutral_nature_count": non_neutral_count,
            "preprocessor_decision_count": len(preprocessor_report["decisions"]),
            "preprocessor_warning_count": len(preprocessor_report["warnings"]),
            "warning_count": warning_count,
            "unsupported_field_count": unsupported_field_count,
            "unresolved_stat_count": unresolved_stat_count,
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

    exported = export_natures(source_root)
    natures_output = output_root / "pokemon" / "natures.json"
    write_json(natures_output, exported)

    stats = exported["stats"]
    manifest_entry = {
        "category": "natures",
        "path": to_project_path(natures_output),
        "nature_count": stats["nature_count"],
        "neutral_nature_count": stats["neutral_nature_count"],
        "non_neutral_nature_count": stats["non_neutral_nature_count"],
        "warning_count": stats["warning_count"],
        "unresolved_stat_count": stats["unresolved_stat_count"],
    }
    write_manifest(
        output_root / "import_manifest.json",
        exported_pokemon=[manifest_entry],
        generator="tools/importer/export_natures.py",
    )

    print(json.dumps({
        "exported": manifest_entry,
        "preprocessor_decision_count": stats["preprocessor_decision_count"],
        "unsupported_field_count": stats["unsupported_field_count"],
    }, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
