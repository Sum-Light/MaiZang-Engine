#!/usr/bin/env python3
"""Export pokeemerald-expansion type metadata into generated JSON."""

import argparse
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
    _parse_enum_constants,
    _preprocess_records,
    _read_source_lines,
    _relative_source_location,
    _remove_prefix,
    _split_top_level,
    _strip_c_comments,
)
from source_probe import load_config, to_project_path
from text_codec import display_text_from_source


TYPE_ENTRY_RE = re.compile(r"\[(TYPE_[A-Za-z0-9_]*)\]\s*=")

KNOWN_TYPE_FIELDS = {
    "name",
    "generic",
    "palette",
    "zMove",
    "maxMove",
    "teraTypeRGBValue",
    "damageCategory",
    "paletteTMHM",
    "useSecondTypeIconPalette",
    "isSpecialCaseType",
    "isHiddenPowerType",
}


def _load_type_constants(root, macros):
    constants = {
        "types": _parse_enum_constants(root / "include/constants/pokemon.h", "Type", macros),
        "moves": _parse_enum_constants(root / "include/constants/moves.h", "Move", macros),
        "damage_categories": _parse_enum_constants(root / "include/constants/pokemon.h", "DamageCategory", macros),
        "evaluator": ExpressionEvaluator(macros),
    }
    return constants


def _type_table_records(records):
    start_index = -1
    for index, record in enumerate(records):
        if "const struct TypeInfo gTypesInfo" in record.text:
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


def _parse_type_entries(root, records, constants):
    types = {}
    order = []
    index = 0
    while index < len(records):
        match = TYPE_ENTRY_RE.search(records[index].text)
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

        record = _build_type_record(root, symbol, start_record, initializer_kind, raw_initializer, fields, constants)
        types[symbol] = record
        order.append(symbol)
        index = end_index + 1

    order.sort(key=lambda item: (types[item].get("id") is None, types[item].get("id", 0), item))
    return types, order


def _build_type_record(root, symbol, source_record, initializer_kind, raw_initializer, fields, constants):
    evaluator = constants["evaluator"]
    warnings = []
    record = {
        "id": _constant_value(symbol, constants["types"]),
        "symbol": symbol,
        "name_key": _remove_prefix(symbol, "TYPE_").lower(),
        "source": _relative_source_location(root, source_record),
        "initializer_kind": initializer_kind,
    }

    if initializer_kind != "struct":
        record["raw_initializer"] = _compact_source(raw_initializer)
        record["evaluation_status"] = "partial"
        record["warnings"] = ["type initializer is not a struct initializer"]
        return record

    record["raw_fields"] = {field: _compact_source(value) for field, value in fields.items()}

    if "name" in fields:
        record["name"] = _parse_type_text_value(fields["name"])
    if "generic" in fields:
        record["generic"] = _parse_type_text_value(fields["generic"])
    if "palette" in fields:
        record["palette"] = _eval_field_int(fields["palette"], evaluator, warnings)
    if "zMove" in fields:
        record["z_move"] = _constant_record(fields["zMove"], constants["moves"], "MOVE_", evaluator, warnings)
    if "maxMove" in fields:
        record["max_move"] = _constant_record(fields["maxMove"], constants["moves"], "MOVE_", evaluator, warnings)
    if "teraTypeRGBValue" in fields:
        record["tera_type_rgb_value"] = _parse_rgb_value(fields["teraTypeRGBValue"], evaluator, warnings)
    if "damageCategory" in fields:
        record["damage_category"] = _constant_record(
            fields["damageCategory"],
            constants["damage_categories"],
            "DAMAGE_CATEGORY_",
            evaluator,
            warnings,
        )
    if "paletteTMHM" in fields:
        record["palette_tmhm"] = {
            "symbol": _compact_source(fields["paletteTMHM"]),
            "source": "src/type_icons.c; src/item_icon.c",
        }

    for source_field, output_field in [
        ("useSecondTypeIconPalette", "use_second_type_icon_palette"),
        ("isSpecialCaseType", "is_special_case_type"),
        ("isHiddenPowerType", "is_hidden_power_type"),
    ]:
        if source_field in fields:
            record[output_field] = _parse_bool_value(fields[source_field], evaluator, warnings)

    unsupported = sorted(field for field in fields.keys() if field not in KNOWN_TYPE_FIELDS)
    if unsupported:
        record["unsupported_fields"] = unsupported
    if warnings:
        record["warnings"] = sorted(set(warnings))
    record["evaluation_status"] = "partial" if warnings or unsupported else "ok"
    return record


def _parse_type_text_value(value):
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


def _parse_rgb_value(value, evaluator, warnings):
    raw = _compact_source(value)
    if raw == "RGB_WHITE":
        return {
            "raw": raw,
            "components_5bit": [31, 31, 31],
            "source": "include/gba/types.h:RGB_WHITE",
        }
    match = re.fullmatch(r"RGB\s*\((.*)\)", raw, re.S)
    if match:
        args = [_compact_source(item) for item in _split_top_level(match.group(1), ",") if item.strip()]
        if len(args) == 3:
            components = [_eval_field_int(arg, evaluator, warnings) for arg in args]
            if all(item is not None for item in components):
                return {
                    "raw": raw,
                    "components_5bit": components,
                    "source": "include/gba/types.h:RGB",
                }
    evaluated = _eval_field_int(raw, evaluator, warnings)
    return {
        "raw": raw,
        "value": evaluated,
    }


def _parse_bool_value(value, evaluator, warnings):
    raw = _compact_source(value)
    if raw == "TRUE":
        return True
    if raw == "FALSE":
        return False
    evaluated = _eval_field_int(raw, evaluator, warnings)
    if evaluated is None:
        return None
    return evaluated != 0


def _constant_value(symbol, constants):
    value = constants.get(symbol)
    return int(value) if isinstance(value, int) else None


def export_types(root):
    macros = _load_macro_expressions(root)
    macros.update({
        "TRUE": "1",
        "FALSE": "0",
        "NULL": "0",
        "RGB_WHITE": str((31 << 0) | (31 << 5) | (31 << 10)),
    })
    constants = _load_type_constants(root, macros)
    source_records = _type_table_records(_read_source_lines(root / "src/data/types_info.h"))
    preprocessed_records, preprocessor_report = _preprocess_records(source_records, macros)
    types, type_order = _parse_type_entries(root, preprocessed_records, constants)

    warning_count = len(preprocessor_report["warnings"])
    warning_count += sum(len(record.get("warnings", [])) for record in types.values())
    unsupported_field_count = sum(len(record.get("unsupported_fields", [])) for record in types.values())
    unresolved_name_count = sum(
        1
        for record in types.values()
        if not isinstance(record.get("name"), dict) or not record["name"].get("display_text")
    )

    return {
        "schema_version": 1,
        "source": {
            "project": "pokeemerald-expansion",
            "types_info": "src/data/types_info.h:gTypesInfo",
            "struct_definition": "include/data.h:struct TypeInfo",
            "constants": [
                "include/constants/pokemon.h:enum Type",
                "include/constants/pokemon.h:enum DamageCategory",
                "include/constants/moves.h:enum Move",
            ],
            "runtime_references": [
                "src/battle_controller_player.c:MoveSelectionDisplayMoveType",
                "src/type_icons.c",
                "src/item_icon.c",
                "src/battle_main.c:gTypesInfo",
            ],
            "preprocessor": preprocessor_report,
        },
        "constants": {
            "types": _export_constant_group(constants["types"], "TYPE_"),
            "damage_categories": _export_constant_group(constants["damage_categories"], "DAMAGE_CATEGORY_"),
        },
        "type_order": type_order,
        "types": types,
        "stats": {
            "type_count": len(types),
            "preprocessor_decision_count": len(preprocessor_report["decisions"]),
            "preprocessor_warning_count": len(preprocessor_report["warnings"]),
            "warning_count": warning_count,
            "unsupported_field_count": unsupported_field_count,
            "unresolved_name_count": unresolved_name_count,
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

    exported = export_types(source_root)
    types_output = output_root / "pokemon" / "types.json"
    write_json(types_output, exported)

    stats = exported["stats"]
    manifest_entry = {
        "category": "types",
        "path": to_project_path(types_output),
        "type_count": stats["type_count"],
        "warning_count": stats["warning_count"],
        "unsupported_field_count": stats["unsupported_field_count"],
        "unresolved_name_count": stats["unresolved_name_count"],
    }
    write_manifest(
        output_root / "import_manifest.json",
        exported_pokemon=[manifest_entry],
        generator="tools/importer/export_types.py",
    )

    print(
        "Exported {type_count} type records to {path}".format(
            type_count=stats["type_count"],
            path=types_output,
        )
    )
    if stats["warning_count"] or stats["unsupported_field_count"] or stats["unresolved_name_count"]:
        print(
            "Warnings: {warnings}; unsupported fields: {unsupported}; unresolved names: {unresolved}".format(
                warnings=stats["warning_count"],
                unsupported=stats["unsupported_field_count"],
                unresolved=stats["unresolved_name_count"],
            )
        )


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
