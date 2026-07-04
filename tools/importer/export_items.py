#!/usr/bin/env python3
"""Export pokeemerald-expansion item data into generated JSON."""

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
    _export_constant_group,
    _find_matching_brace,
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


ITEM_ENTRY_RE = re.compile(r"\[(ITEM_[A-Za-z0-9_]*)\]\s*=")
ITEM_EFFECT_ARRAY_RE = re.compile(r"(?:static\s+)?const\s+u8\s+([A-Za-z_][A-Za-z0-9_]*)\s*\[\s*([0-9]+)\s*\]\s*=")
TEXT_ENTRY_RE = re.compile(r"(?:static\s+)?const\s+u8\s+([A-Za-z_][A-Za-z0-9_]*)\[\]\s*=\s*(.*?);", re.S)
IDENTIFIER_RE = re.compile(r"\b[A-Za-z_][A-Za-z0-9_]*\b")
CAST_RE = re.compile(r"\(\s*(?:u8|u16|u32|u64|s8|s16|s32|s64|bool8|bool16|bool32|enum\s+[A-Za-z_][A-Za-z0-9_]*)\s*\)")

INTEGER_FIELDS = {
    "price": "price",
    "holdEffectParam": "hold_effect_param",
    "importance": "importance",
    "notConsumed": "not_consumed",
    "flingPower": "fling_power",
}

REFERENCE_FIELDS = {
    "fieldUseFunc": "field_use_func",
    "iconPic": "icon_pic",
    "iconPalette": "icon_palette",
}

DEFAULT_FIELD_VALUES = {
    "price": 0,
    "secondary_id": 0,
    "field_use_func": None,
    "description": None,
    "effect": None,
    "name": None,
    "plural_name": None,
    "hold_effect_param": 0,
    "importance": 0,
    "not_consumed": False,
    "fling_power": 0,
    "icon_pic": None,
    "icon_palette": None,
}

BEHAVIOR_REFERENCES = [
    "src/item.c",
    "src/item_menu.c",
    "src/item_use.c",
    "src/pokemon.c",
    "src/party_menu.c",
    "src/battle_ai_items.c",
    "src/battle_ai_main.c",
    "src/battle_ai_util.c",
    "src/battle_script_commands.c",
    "src/battle_util.c",
    "src/berry.c",
    "src/berry_tag_screen.c",
    "src/shop.c",
    "src/scrcmd.c",
    "src/field_specials.c",
    "src/sprays.c",
    "src/overworld.c",
    "src/pokeball.c",
    "src/battle_anim_throw.c",
]


def _load_item_macro_expressions(root):
    macros = {
        "TRUE": "1",
        "FALSE": "0",
        "NULL": "0",
    }
    config_files = [
        Path("include/gba/defines.h"),
        Path("include/config/general.h"),
        Path("include/config/battle.h"),
        Path("include/config/overworld.h"),
        Path("include/config/item.h"),
        Path("include/config/save.h"),
        Path("include/config/pokemon.h"),
        Path("include/constants/global.h"),
        Path("include/constants/pokemon.h"),
        Path("include/constants/item.h"),
        Path("include/constants/items.h"),
        Path("include/constants/item_effects.h"),
        Path("include/constants/hold_effects.h"),
    ]
    for relative_path in config_files:
        _read_defines_into(root / relative_path, macros)
    _normalize_numeric_macros(macros)
    return macros


def _load_item_constants(root, macros):
    constants = {}
    constants["items"] = _parse_enum_constants(root / "include/constants/items.h", "Item", macros)
    _repair_item_constants_from_explicit_assignments(root / "include/constants/items.h", constants["items"], macros)
    _add_tmhm_item_aliases(root, constants["items"], macros)
    constants["pockets"] = _parse_enum_constants(root / "include/constants/item.h", "Pocket", macros)
    constants["sort_types"] = _parse_named_enum_constants(root / "include/item.h", "ItemSortType", macros)
    constants["item_use_types"] = _parse_enum_constants(root / "include/constants/items.h", "ItemType", macros)
    constants["battle_usages"] = _parse_enum_constants(root / "include/constants/items.h", "EffectItem", macros)
    constants["hold_effects"] = _parse_enum_constants(root / "include/constants/hold_effects.h", "HoldEffect", macros)
    constants["pokeballs"] = _parse_enum_constants(root / "include/constants/pokeball.h", "PokeBall", macros)
    constants["types"] = _parse_enum_constants(root / "include/constants/pokemon.h", "Type", macros)
    constants["stats"] = _parse_enum_constants(root / "include/constants/pokemon.h", "Stat", macros)
    constants["moves"] = _parse_enum_constants(root / "include/constants/moves.h", "Move", macros)
    constants["natures"] = _parse_define_constants(root / "include/constants/pokemon.h", "NATURE_", macros)
    constants["item_effect_types"] = _parse_enum_constants(root / "include/constants/item_effects.h", "ItemEffectType", macros)
    constants["item_effect_values"] = _parse_define_constants_with_prefixes(
        root / "include/constants/item_effects.h",
        ["ITEM0_", "ITEM1_", "ITEM3_", "ITEM4_", "ITEM5_", "ITEM6_", "ITEM10_", "ITEM_EFFECT_ARG_START"],
        macros,
    )
    constants["secondary_id_values"] = _merge_constants(
        constants["pokeballs"],
        constants["types"],
        constants["stats"],
        constants["natures"],
        constants["items"],
    )
    constants["generic_values"] = _merge_constants(
        constants["items"],
        constants["pockets"],
        constants["sort_types"],
        constants["item_use_types"],
        constants["battle_usages"],
        constants["hold_effects"],
        constants["pokeballs"],
        constants["types"],
        constants["stats"],
        constants["moves"],
        constants["natures"],
        constants["item_effect_types"],
        constants["item_effect_values"],
    )
    constants["evaluator"] = ExpressionEvaluator(macros)
    return constants


def _parse_named_enum_constants(path, enum_name, macros):
    text = _strip_c_comments(path.read_text(encoding="utf-8"))
    pattern = re.compile(
        r"enum(?:\s+(?:__attribute__\s*\(\(packed\)\)|PACKED))*\s+"
        + re.escape(enum_name)
        + r"\s*\{"
    )
    match = pattern.search(text)
    if not match:
        return {}

    brace_start = text.find("{", match.start())
    brace_end = _find_matching_brace(text, brace_start)
    if brace_start == -1 or brace_end == -1:
        return {}

    evaluator = ExpressionEvaluator(macros)
    constants = {}
    current_value = 0
    body = text[brace_start + 1:brace_end]
    body = "\n".join(line for line in body.splitlines() if not line.strip().startswith("#"))
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
            value = evaluator.eval_int(_normalize_expression(expression))
            if value is None:
                value = current_value
        else:
            value = current_value
        constants[name] = value
        macros[name] = str(value)
        current_value = value + 1
    return constants


def _parse_define_constants_with_prefixes(path, prefixes, macros):
    raw_macros = {}
    _read_defines_into(path, raw_macros)
    for name, value in raw_macros.items():
        if any(name.startswith(prefix) for prefix in prefixes):
            macros[name] = _normalize_macro_value(value)

    evaluator = ExpressionEvaluator(macros)
    constants = {}
    for name in sorted(raw_macros.keys()):
        if not any(name.startswith(prefix) for prefix in prefixes):
            continue
        value = evaluator.eval_int(_normalize_expression(raw_macros[name]))
        if value is not None:
            constants[name] = value
            macros[name] = str(value)
    return constants


def _merge_constants(*groups):
    merged = {}
    for group in groups:
        merged.update(group)
    return merged


def _add_tmhm_item_aliases(root, item_constants, macros):
    tmhm_path = root / "include/constants/tms_hms.h"
    tm_names = _read_foreach_macro_entries(tmhm_path, "FOREACH_TM")
    hm_names = _read_foreach_macro_entries(tmhm_path, "FOREACH_HM")
    for index, name in enumerate(tm_names, start=1):
        numbered_symbol = "ITEM_TM{:02d}".format(index)
        alias_symbol = "ITEM_TM_{}".format(name)
        if numbered_symbol in item_constants:
            item_constants[alias_symbol] = item_constants[numbered_symbol]
            macros[alias_symbol] = str(item_constants[numbered_symbol])
    for index, name in enumerate(hm_names, start=1):
        numbered_symbol = "ITEM_HM{:02d}".format(index)
        alias_symbol = "ITEM_HM_{}".format(name)
        if numbered_symbol in item_constants:
            item_constants[alias_symbol] = item_constants[numbered_symbol]
            macros[alias_symbol] = str(item_constants[numbered_symbol])


def _repair_item_constants_from_explicit_assignments(path, item_constants, macros):
    text = _strip_c_comments(path.read_text(encoding="utf-8"))
    evaluator = ExpressionEvaluator(macros)
    for match in re.finditer(r"\b(ITEM_[A-Za-z0-9_]*)\s*=\s*([^,\n]+)", text):
        symbol = match.group(1)
        expression = match.group(2).strip()
        if "CAT(" in expression:
            continue
        value = evaluator.eval_int(_normalize_expression(expression))
        if value is None:
            continue
        item_constants[symbol] = value
        macros[symbol] = str(value)
        evaluator.cache.pop(symbol, None)


def _read_foreach_macro_entries(path, macro_name):
    if not path.exists():
        return []
    lines = path.read_text(encoding="utf-8").splitlines()
    entries = []
    collecting = False
    for line in lines:
        stripped = line.strip()
        if not collecting:
            if re.match(r"#\s*define\s+" + re.escape(macro_name) + r"\s*\(", stripped):
                collecting = True
            continue
        if stripped.startswith("#define "):
            break
        for match in re.finditer(r"\bF\s*\(\s*([A-Za-z_][A-Za-z0-9_]*)\s*\)", stripped):
            entries.append(match.group(1))
        if stripped and not stripped.endswith("\\"):
            break
    return entries


def _normalize_numeric_macros(macros):
    for name, value in list(macros.items()):
        macros[name] = _normalize_macro_value(value)


def _normalize_macro_value(value):
    normalized = _normalize_expression(value)
    if re.search(r"\(\s*u8\s*\)", str(value)):
        evaluator = ExpressionEvaluator({})
        integer = evaluator.eval_int(normalized)
        if integer is not None and integer < 0:
            return str(integer & 0xFF)
    return normalized


def _normalize_expression(value):
    expression = _compact_source(str(value))
    expression = _expand_item_index_macros(expression)
    expression = CAST_RE.sub("", expression)
    return expression


def _expand_item_index_macros(expression):
    output = str(expression)
    output = _replace_function_macro(output, "ITEM_TO_BERRY", lambda arg: "(({}) - FIRST_BERRY_INDEX + 1)".format(arg))
    output = _replace_function_macro(output, "ITEM_TO_MAIL", lambda arg: "(({}) - FIRST_MAIL_INDEX)".format(arg))
    output = _replace_function_macro(output, "ITEM_TO_MULCH", lambda arg: "(({}) - ITEM_GROWTH_MULCH + 1)".format(arg))
    return output


def _replace_function_macro(text, macro_name, replacer):
    pattern = re.compile(r"\b" + re.escape(macro_name) + r"\s*\(")
    search_start = 0
    output = str(text)
    while True:
        match = pattern.search(output, search_start)
        if not match:
            return output
        open_index = match.end() - 1
        close_index = _find_matching_paren(output, open_index)
        if close_index == -1:
            return output
        argument = output[open_index + 1:close_index].strip()
        output = output[:match.start()] + replacer(argument) + output[close_index + 1:]
        search_start = match.start() + 1


def _find_matching_paren(text, open_index):
    depth = 0
    in_string = False
    escaped = False
    for index in range(open_index, len(text)):
        char = text[index]
        if in_string:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
            continue
        if char == '"':
            in_string = True
        elif char == "(":
            depth += 1
        elif char == ")":
            depth -= 1
            if depth == 0:
                return index
    return -1


def _eval_item_int(value, evaluator, warnings):
    raw = _compact_source(value)
    normalized = _normalize_expression(raw)
    result = evaluator.eval_int(normalized)
    if result is None:
        warnings.append("could not evaluate integer expression: {}".format(raw))
    return result


def _parse_shared_text_entries(root, records, macros):
    symbol_sources = {}
    for record in records:
        match = re.search(r"(?:static\s+)?const\s+u8\s+([A-Za-z_][A-Za-z0-9_]*)\[\]\s*=", record.text)
        if match:
            symbol_sources[match.group(1)] = _relative_source_location(root, record)

    text = "\n".join(record.text for record in records)
    shared = {}
    for match in TEXT_ENTRY_RE.finditer(text):
        symbol = match.group(1)
        parsed = _parse_inline_text_value(_expand_string_macros(match.group(2), macros))
        parsed["symbol"] = symbol
        if symbol in symbol_sources:
            parsed["source"] = symbol_sources[symbol]
        shared[symbol] = parsed
    return shared


def _parse_inline_text_value(value):
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


def _parse_item_text_value(value, shared_text, macros):
    raw_value = _compact_source(value)
    if raw_value in {"NULL", "0"}:
        return {
            "kind": "null",
            "raw": raw_value,
        }

    expanded = _expand_string_macros(value, macros)
    raw = _extract_string_literals(expanded)
    if raw is not None:
        return {
            "kind": "inline",
            "source_text": raw,
            "display_text": display_text_from_source(raw),
        }

    symbol = raw_value
    if symbol in shared_text:
        resolved = dict(shared_text[symbol])
        resolved["kind"] = "reference"
        resolved["symbol"] = symbol
        return resolved

    return {
        "kind": "reference",
        "symbol": symbol,
        "raw": raw_value,
    }


def _expand_string_macros(value, macros):
    def replace_identifier(match):
        name = match.group(0)
        macro_value = macros.get(name)
        if isinstance(macro_value, str) and '"' in macro_value:
            return macro_value
        return name

    return IDENTIFIER_RE.sub(replace_identifier, value)


def _extract_string_literals(value):
    matches = re.findall(r'"((?:\\.|[^"\\])*)"', value, re.S)
    if not matches:
        return None
    return "".join(matches)


def _parse_item_effect_entries(root, records, constants):
    effects = {}
    order = []
    index = 0
    while index < len(records):
        match = ITEM_EFFECT_ARRAY_RE.search(records[index].text)
        if not match:
            index += 1
            continue

        symbol = match.group(1)
        length = int(match.group(2))
        start_record = records[index]
        initializer_lines = [records[index].text[match.end():]]
        end_index = index
        initializer_text = "\n".join(initializer_lines)
        stripped_initializer = initializer_text.lstrip()
        leading_offset = len(initializer_text) - len(stripped_initializer)
        open_index = leading_offset if stripped_initializer.startswith("{") else initializer_text.find("{")
        close_index = _find_matching_brace(initializer_text, open_index) if open_index != -1 else -1
        while close_index == -1 and end_index + 1 < len(records):
            end_index += 1
            initializer_lines.append(records[end_index].text)
            initializer_text = "\n".join(initializer_lines)
            stripped_initializer = initializer_text.lstrip()
            leading_offset = len(initializer_text) - len(stripped_initializer)
            open_index = leading_offset if stripped_initializer.startswith("{") else initializer_text.find("{")
            close_index = _find_matching_brace(initializer_text, open_index) if open_index != -1 else -1

        raw_initializer = initializer_text[open_index:close_index + 1] if close_index != -1 else initializer_text.strip()
        effects[symbol] = _build_item_effect_record(
            root,
            symbol,
            length,
            start_record,
            raw_initializer,
            constants,
        )
        order.append(symbol)
        index = end_index + 1
    return effects, order


def _build_item_effect_record(root, symbol, length, source_record, raw_initializer, constants):
    evaluator = constants["evaluator"]
    warnings = []
    values = [0 for _index in range(length)]
    byte_values = [0 for _index in range(length)]
    entries = []
    unsupported_entries = []
    next_index = 0
    body = raw_initializer[1:-1] if raw_initializer.startswith("{") and raw_initializer.endswith("}") else raw_initializer

    for entry in _split_top_level(_strip_c_comments(body), ","):
        raw_entry = entry.strip()
        if not raw_entry:
            continue

        expanded = _expand_item_effect_macro_entry(raw_entry, evaluator, warnings)
        if expanded:
            for array_index, raw_value in expanded:
                _assign_item_effect_value(array_index, raw_value, values, byte_values, entries, evaluator, warnings)
                next_index = max(next_index, array_index + 1)
            continue

        designated = re.match(r"\[\s*(.+?)\s*\]\s*=\s*(.+)$", raw_entry, re.S)
        if designated:
            array_index = _eval_item_int(designated.group(1), evaluator, warnings)
            if array_index is None:
                unsupported_entries.append(_compact_source(raw_entry))
                continue
            _assign_item_effect_value(array_index, designated.group(2), values, byte_values, entries, evaluator, warnings)
            next_index = max(next_index, array_index + 1)
        else:
            _assign_item_effect_value(next_index, raw_entry, values, byte_values, entries, evaluator, warnings)
            next_index += 1

    record = {
        "symbol": symbol,
        "length": length,
        "source": _relative_source_location(root, source_record),
        "raw_initializer": _compact_source(raw_initializer),
        "values": values,
        "byte_values": byte_values,
        "entries": entries,
    }
    if unsupported_entries:
        record["unsupported_entries"] = unsupported_entries
    if warnings:
        record["warnings"] = sorted(set(warnings))
    record["evaluation_status"] = "partial" if warnings or unsupported_entries else "ok"
    return record


def _expand_item_effect_macro_entry(raw_entry, evaluator, warnings):
    match = re.fullmatch(r"VITAMIN_FRIENDSHIP_CHANGE\s*\((.+)\)", raw_entry, re.S)
    if match:
        start = _eval_item_int(match.group(1), evaluator, warnings)
        if start is None:
            return []
        return [(start, "5"), (start + 1, "3"), (start + 2, "2")]

    match = re.fullmatch(r"FEATHER_FRIENDSHIP_CHANGE\s*\((.+)\)", raw_entry, re.S)
    if match:
        start = _eval_item_int(match.group(1), evaluator, warnings)
        if start is None:
            return []
        return [(start, "3"), (start + 1, "2"), (start + 2, "1")]

    if raw_entry == "EV_BERRY_FRIENDSHIP_CHANGE":
        return [(7, "10"), (8, "5"), (9, "2")]
    return []


def _assign_item_effect_value(array_index, raw_value, values, byte_values, entries, evaluator, warnings):
    value = _eval_item_int(raw_value, evaluator, warnings)
    byte_value = (int(value) & 0xFF) if value is not None else None
    entry = {
        "index": int(array_index),
        "raw": _compact_source(raw_value),
        "value": value,
        "byte_value": byte_value,
    }
    entries.append(entry)
    if 0 <= array_index < len(values):
        values[array_index] = value
        byte_values[array_index] = byte_value
    else:
        warnings.append("item effect index out of range: {}".format(array_index))


def _parse_item_entries(root, records, constants, shared_text, item_effects, macros):
    items = {}
    order = []
    index = 0
    while index < len(records):
        match = ITEM_ENTRY_RE.search(records[index].text)
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

        record = _build_item_record(
            root,
            symbol,
            start_record,
            initializer_kind,
            raw_initializer,
            fields,
            constants,
            shared_text,
            item_effects,
            macros,
        )
        items[symbol] = record
        order.append(symbol)
        index = end_index + 1

    order.sort(key=lambda item: (items[item].get("id") is None, items[item].get("id", 0), item))
    return items, order


def _build_item_record(root, symbol, source_record, initializer_kind, raw_initializer, fields, constants, shared_text, item_effects, macros):
    evaluator = constants["evaluator"]
    warnings = []
    defaulted_fields = []
    record = {
        "id": _constant_value(symbol, constants["items"]),
        "symbol": symbol,
        "name_key": _remove_prefix(symbol, "ITEM_").lower(),
        "source": _relative_source_location(root, source_record),
        "initializer_kind": initializer_kind,
    }

    if initializer_kind != "struct":
        record["raw_initializer"] = _compact_source(raw_initializer)
        record["evaluation_status"] = "partial"
        record["warnings"] = ["item initializer is not a struct initializer"]
        return record

    raw_fields = {field: _compact_source(value) for field, value in fields.items()}
    record["raw_fields"] = raw_fields

    if "name" in fields:
        record["name"] = _parse_item_text_value(fields["name"], shared_text, macros)
    else:
        record["name"] = DEFAULT_FIELD_VALUES["name"]
        defaulted_fields.append("name")

    if "pluralName" in fields:
        record["plural_name"] = _parse_item_text_value(fields["pluralName"], shared_text, macros)
    else:
        record["plural_name"] = DEFAULT_FIELD_VALUES["plural_name"]
        defaulted_fields.append("plural_name")

    if "description" in fields:
        record["description"] = _parse_item_text_value(fields["description"], shared_text, macros)
    else:
        record["description"] = DEFAULT_FIELD_VALUES["description"]
        defaulted_fields.append("description")

    for source_field, output_field in INTEGER_FIELDS.items():
        if source_field in fields:
            value = _eval_item_int(fields[source_field], evaluator, warnings)
            if output_field == "not_consumed":
                value = bool(value)
            record[output_field] = value
        else:
            record[output_field] = DEFAULT_FIELD_VALUES[output_field]
            defaulted_fields.append(output_field)

    if "price" in fields:
        record["sell_price"] = _sell_price(record.get("price"), evaluator, warnings)
    else:
        record["sell_price"] = 0

    record["consumable"] = not bool(record.get("not_consumed", False))

    if "secondaryId" in fields:
        record["secondary_id"] = _generic_value(
            fields["secondaryId"],
            constants["secondary_id_values"],
            evaluator,
            warnings,
            secondary_kind=_secondary_id_kind(fields["secondaryId"]),
        )
    else:
        record["secondary_id"] = {"raw": "0", "value": 0}
        defaulted_fields.append("secondary_id")

    if "pocket" in fields:
        record["pocket"] = _constant_record(fields["pocket"], constants["pockets"], "POCKET_", evaluator, warnings)
    else:
        record["pocket"] = _constant_record("POCKET_ITEMS", constants["pockets"], "POCKET_", evaluator, warnings)
        defaulted_fields.append("pocket")

    if "sortType" in fields:
        record["sort_type"] = _constant_record(fields["sortType"], constants["sort_types"], "ITEM_TYPE_", evaluator, warnings)
    else:
        record["sort_type"] = _constant_record("ITEM_TYPE_UNCATEGORIZED", constants["sort_types"], "ITEM_TYPE_", evaluator, warnings)
        defaulted_fields.append("sort_type")

    if "type" in fields:
        record["type"] = _constant_record(fields["type"], constants["item_use_types"], "ITEM_USE_", evaluator, warnings)
    else:
        record["type"] = _constant_record("ITEM_USE_MAIL", constants["item_use_types"], "ITEM_USE_", evaluator, warnings)
        defaulted_fields.append("type")

    if "battleUsage" in fields:
        record["battle_usage"] = _constant_record(fields["battleUsage"], constants["battle_usages"], "EFFECT_ITEM_", evaluator, warnings)
    else:
        record["battle_usage"] = {"raw": "0", "value": 0}
        defaulted_fields.append("battle_usage")

    if "holdEffect" in fields:
        record["hold_effect"] = _constant_record(fields["holdEffect"], constants["hold_effects"], "HOLD_EFFECT_", evaluator, warnings)
    else:
        record["hold_effect"] = _constant_record("HOLD_EFFECT_NONE", constants["hold_effects"], "HOLD_EFFECT_", evaluator, warnings)
        defaulted_fields.append("hold_effect")

    if "effect" in fields:
        record["effect"] = _reference_value(fields["effect"], macros)
        effect_symbol = record["effect"].get("symbol")
        if effect_symbol in item_effects:
            record["effect"]["source"] = item_effects[effect_symbol]["source"]
            record["effect"]["length"] = item_effects[effect_symbol]["length"]
    else:
        record["effect"] = DEFAULT_FIELD_VALUES["effect"]
        defaulted_fields.append("effect")

    for source_field, output_field in REFERENCE_FIELDS.items():
        if source_field in fields:
            record[output_field] = _reference_value(fields[source_field], macros)
        else:
            record[output_field] = DEFAULT_FIELD_VALUES[output_field]
            defaulted_fields.append(output_field)

    known_fields = {
        "name",
        "pluralName",
        "description",
        "price",
        "secondaryId",
        "fieldUseFunc",
        "effect",
        "holdEffect",
        "holdEffectParam",
        "importance",
        "notConsumed",
        "pocket",
        "sortType",
        "type",
        "battleUsage",
        "flingPower",
        "iconPic",
        "iconPalette",
    }
    unsupported = sorted(field for field in fields.keys() if field not in known_fields)
    if unsupported:
        record["unsupported_fields"] = unsupported

    if defaulted_fields:
        record["defaulted_fields"] = sorted(defaulted_fields)
    if warnings:
        record["warnings"] = sorted(set(warnings))
    record["evaluation_status"] = "partial" if warnings or unsupported else "ok"
    return record


def _sell_price(price, evaluator, warnings):
    if price is None:
        return None
    factor = _eval_item_int("ITEM_SELL_FACTOR", evaluator, warnings)
    if factor in (None, 0):
        return None
    return int(price) // int(factor)


def _secondary_id_kind(value):
    raw = _compact_source(value)
    if raw.startswith("BALL_"):
        return "pokeball"
    if raw.startswith("TYPE_"):
        return "type"
    if raw.startswith("NATURE_"):
        return "nature"
    if raw.startswith("ITEM_TO_BERRY"):
        return "berry_index"
    if raw.startswith("ITEM_TO_MAIL"):
        return "mail_index"
    if raw.startswith("ITEM_TO_MULCH"):
        return "mulch_index"
    return "generic"


def _constant_record(value, constants, prefix, evaluator, warnings):
    raw = _compact_source(value)
    parsed = _generic_value(raw, constants, evaluator, warnings)
    symbol = parsed.get("symbol")
    if symbol is not None:
        parsed["name"] = _constant_name(symbol, prefix)
    return parsed


def _generic_value(value, constants, evaluator, warnings=None, secondary_kind=None):
    raw = _compact_source(value)
    normalized = _normalize_expression(raw)
    result = {"raw": raw}
    if normalized != raw:
        result["normalized"] = normalized
    integer = evaluator.eval_int(normalized)
    if integer is not None:
        result["value"] = integer
        symbol = _find_symbol_for_value(constants, integer)
        if symbol is not None and re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", raw):
            result["symbol"] = symbol
    if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", raw):
        result["symbol"] = raw
        if raw in constants:
            result["value"] = constants[raw]
    if secondary_kind is not None:
        result["kind"] = secondary_kind
    if integer is None and warnings is not None:
        warnings.append("could not resolve constant expression: {}".format(raw))
    return result


def _reference_value(value, macros):
    raw = _compact_source(value)
    if raw in {"NULL", "0"}:
        return {
            "raw": raw,
            "symbol": None,
        }

    record = {
        "raw": raw,
        "symbol": raw,
    }
    macro_value = macros.get(raw)
    if isinstance(macro_value, str) and re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", macro_value):
        record["symbol"] = macro_value
        record["macro"] = raw
    return record


def _constant_value(symbol, constants):
    value = constants.get(symbol)
    return int(value) if isinstance(value, int) else None


def _find_symbol_for_value(constants, value):
    for symbol, constant_value in constants.items():
        if constant_value == value:
            return symbol
    return None


def _constant_name(symbol, prefix):
    if symbol is None:
        return None
    if symbol.startswith(prefix):
        return symbol[len(prefix):].lower()
    return symbol.lower()


def _combine_preprocessor_reports(*reports):
    decisions = []
    warnings = []
    for report in reports:
        decisions.extend(report.get("decisions", []))
        warnings.extend(report.get("warnings", []))
    return {
        "decisions": decisions,
        "warnings": sorted(set(warnings)),
        "items": reports[0] if len(reports) > 0 else {"decisions": [], "warnings": []},
        "item_effects": reports[1] if len(reports) > 1 else {"decisions": [], "warnings": []},
    }


def export_items(root):
    macros = _load_item_macro_expressions(root)
    constants = _load_item_constants(root, macros)

    source_records = _read_source_lines(root / "src/data/items.h")
    preprocessed_records, items_preprocessor_report = _preprocess_records(source_records, macros)
    _normalize_numeric_macros(macros)

    effect_source_records = _read_source_lines(root / "src/data/pokemon/item_effects.h")
    effect_preprocessed_records, effects_preprocessor_report = _preprocess_records(effect_source_records, macros)
    _normalize_numeric_macros(macros)

    constants["evaluator"] = ExpressionEvaluator(macros)
    shared_text = _parse_shared_text_entries(root, preprocessed_records, macros)
    item_effects, item_effect_order = _parse_item_effect_entries(root, effect_preprocessed_records, constants)
    items, item_order = _parse_item_entries(root, preprocessed_records, constants, shared_text, item_effects, macros)
    preprocessor_report = _combine_preprocessor_reports(items_preprocessor_report, effects_preprocessor_report)

    warning_count = len(preprocessor_report["warnings"])
    warning_count += sum(len(record.get("warnings", [])) for record in items.values())
    warning_count += sum(len(record.get("warnings", [])) for record in item_effects.values())
    unsupported_field_count = sum(len(record.get("unsupported_fields", [])) for record in items.values())
    item_ids = [record.get("id") for record in items.values() if record.get("id") is not None]
    item_count_constant = constants["items"].get("ITEMS_COUNT")

    return {
        "schema_version": 1,
        "source": {
            "project": "pokeemerald-expansion",
            "items_info": "src/data/items.h",
            "item_effects": "src/data/pokemon/item_effects.h",
            "struct_definition": "include/item.h",
            "constants": [
                "include/constants/items.h",
                "include/constants/item.h",
                "include/constants/item_effects.h",
                "include/constants/hold_effects.h",
                "include/constants/pokeball.h",
                "include/constants/pokemon.h",
                "include/constants/moves.h",
            ],
            "config": [
                "include/config/general.h",
                "include/config/battle.h",
                "include/config/overworld.h",
                "include/config/item.h",
                "include/config/save.h",
                "include/config/pokemon.h",
            ],
            "behavior_references": BEHAVIOR_REFERENCES,
            "preprocessor": preprocessor_report,
            "runtime_notes": [
                "GetItemName returns gQuestionMarksItemName when the item name pointer is NULL.",
                "GetItemEffect special-cases ITEM_ENIGMA_BERRY_E_READER through save data when FREE_ENIGMA_BERRY is FALSE.",
                "GetItemBattleUsage special-cases ITEM_ENIGMA_BERRY_E_READER by inspecting item effect type.",
                "GetItemConsumability returns the inverse of the notConsumed struct bit.",
                "GetItemSellPrice divides GetItemPrice by ITEM_SELL_FACTOR from include/constants/item.h.",
            ],
        },
        "constants": {
            "items": _export_constant_group(constants["items"], "ITEM_"),
            "pockets": _export_constant_group(constants["pockets"], "POCKET_"),
            "sort_types": _export_constant_group(constants["sort_types"], "ITEM_TYPE_"),
            "item_use_types": _export_constant_group(constants["item_use_types"], "ITEM_USE_"),
            "battle_usages": _export_constant_group(constants["battle_usages"], "EFFECT_ITEM_"),
            "hold_effects": _export_constant_group(constants["hold_effects"], "HOLD_EFFECT_"),
            "pokeballs": _export_constant_group(constants["pokeballs"], "BALL_"),
            "types": _export_constant_group(constants["types"], "TYPE_"),
            "stats": _export_constant_group(constants["stats"], "STAT_"),
            "moves": _export_constant_group(constants["moves"], "MOVE_"),
            "natures": _export_constant_group(constants["natures"], "NATURE_"),
            "item_effect_types": _export_constant_group(constants["item_effect_types"], "ITEM_EFFECT_"),
            "item_effect_values": _export_constant_group(constants["item_effect_values"], "ITEM"),
        },
        "shared_text": shared_text,
        "item_effect_order": item_effect_order,
        "item_effects": item_effects,
        "item_order": item_order,
        "items": items,
        "stats": {
            "item_count": len(items),
            "items_count_constant": item_count_constant,
            "highest_item_id": max(item_ids) if item_ids else None,
            "items_with_descriptions": sum(1 for record in items.values() if record.get("description") is not None),
            "items_with_effect_refs": sum(1 for record in items.values() if isinstance(record.get("effect"), dict) and record.get("effect", {}).get("symbol")),
            "resolved_item_effect_count": sum(1 for record in item_effects.values() if record.get("evaluation_status") == "ok"),
            "items_with_field_use_func": sum(1 for record in items.values() if isinstance(record.get("field_use_func"), dict) and record.get("field_use_func", {}).get("symbol")),
            "items_with_hold_effect": sum(1 for record in items.values() if record.get("hold_effect", {}).get("value", 0) != 0),
            "items_with_battle_usage": sum(1 for record in items.values() if record.get("battle_usage", {}).get("value", 0) != 0),
            "items_with_not_consumed": sum(1 for record in items.values() if bool(record.get("not_consumed", False))),
            "shared_text_count": len(shared_text),
            "item_effect_count": len(item_effects),
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

    exported = export_items(source_root)
    items_output = output_root / "pokemon" / "items.json"
    write_json(items_output, exported)

    stats = exported["stats"]
    manifest_entry = {
        "category": "items",
        "path": to_project_path(items_output),
        "item_count": stats["item_count"],
        "items_count_constant": stats["items_count_constant"],
        "items_with_effect_refs": stats["items_with_effect_refs"],
        "item_effect_count": stats["item_effect_count"],
        "warning_count": stats["warning_count"],
    }
    write_manifest(
        output_root / "import_manifest.json",
        exported_pokemon=[manifest_entry],
        generator="tools/importer/export_items.py",
    )

    print(json.dumps({
        "exported": manifest_entry,
        "preprocessor_decision_count": stats["preprocessor_decision_count"],
        "unsupported_field_count": stats["unsupported_field_count"],
    }, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
