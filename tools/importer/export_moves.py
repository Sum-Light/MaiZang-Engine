#!/usr/bin/env python3
"""Export pokeemerald-expansion move data into generated JSON."""

import argparse
import json
import re
import sys
from pathlib import Path

from export_map import write_json, write_manifest
from export_species import (
    ExpressionEvaluator,
    SourceLine,
    _clean_expression,
    _compact_source,
    _constant_record,
    _eval_field_int,
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


MOVE_ENTRY_RE = re.compile(r"\[(MOVE_[A-Za-z0-9_]*)\]\s*=")
IDENTIFIER_RE = re.compile(r"\b[A-Za-z_][A-Za-z0-9_]*\b")
BATTLE_MOVE_EFFECTS_PATH = Path("src/data/battle_move_effects.h")
BATTLE_MOVE_EFFECT_ENTRY_RE = re.compile(r"\[(EFFECT_[A-Za-z0-9_]+)\]\s*=")

CORE_INTEGER_FIELDS = {
    "power": "power",
    "accuracy": "accuracy",
    "pp": "pp",
    "priority": "priority",
    "strikeCount": "strike_count",
    "criticalHitStage": "critical_hit_stage",
    "numAdditionalEffects": "num_additional_effects",
}

CORE_BOOLEAN_FIELDS = {
    "multiHit": "multi_hit",
    "explosion": "explosion",
    "alwaysCriticalHit": "always_critical_hit",
}

MOVE_FLAG_FIELDS = [
    "makesContact",
    "ignoresProtect",
    "magicCoatAffected",
    "snatchAffected",
    "ignoresKingsRock",
    "punchingMove",
    "bitingMove",
    "pulseMove",
    "soundMove",
    "ballisticMove",
    "powderMove",
    "danceMove",
    "windMove",
    "slicingMove",
    "healingMove",
    "minimizeDoubleDamage",
    "ignoresTargetAbility",
    "ignoresTargetDefenseEvasionStages",
    "damagesUnderground",
    "damagesUnderwater",
    "damagesAirborne",
    "damagesAirborneDoubleDamage",
    "ignoreTypeIfFlyingAndUngrounded",
    "thawsUser",
    "ignoresSubstitute",
    "forcePressure",
    "cantUseTwice",
    "alwaysHitsInRain",
    "accuracy50InSun",
    "alwaysHitsInHailSnow",
    "alwaysHitsOnSameType",
    "noAffectOnSameTypeTarget",
    "accIncreaseByTenOnSameType",
]

BAN_FLAG_FIELDS = [
    "gravityBanned",
    "mirrorMoveBanned",
    "meFirstBanned",
    "mimicBanned",
    "metronomeBanned",
    "copycatBanned",
    "assistBanned",
    "sleepTalkBanned",
    "instructBanned",
    "encoreBanned",
    "parentalBondBanned",
    "skyBattleBanned",
    "sketchBanned",
    "dampBanned",
    "validApprenticeMove",
]

ADDITIONAL_EFFECT_BOOLEAN_FIELDS = {
    "self",
    "onlyIfTargetRaisedStats",
    "onChargeTurnOnly",
    "sheerForceOverride",
    "preAttackEffect",
}


def _load_move_macro_expressions(root):
    macros = {
        "TRUE": "1",
        "FALSE": "0",
        "NULL": "0",
    }
    config_files = [
        Path("include/gba/defines.h"),
        Path("include/config/general.h"),
        Path("include/config/battle.h"),
        Path("include/config/contest.h"),
        Path("include/config/overworld.h"),
        Path("include/config/pokemon.h"),
        Path("include/config/item.h"),
        Path("include/constants/pokemon.h"),
    ]
    for relative_path in config_files:
        _read_defines_into(root / relative_path, macros)
    return macros


def _parse_all_enum_constants_with_prefixes(path, prefixes, macros):
    text = _strip_c_comments(path.read_text(encoding="utf-8"))
    constants = {}
    evaluator = ExpressionEvaluator(macros)
    pattern = re.compile(r"enum(?:\s+__attribute__\s*\(\(packed\)\))?(?:\s+[A-Za-z_][A-Za-z0-9_]*)?\s*\{")
    for match in pattern.finditer(text):
        brace_start = text.find("{", match.start())
        brace_end = _find_matching_brace(text, brace_start)
        if brace_start == -1 or brace_end == -1:
            continue
        body = text[brace_start + 1:brace_end]
        body = "\n".join(line for line in body.splitlines() if not line.strip().startswith("#"))
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
            macros[name] = str(value)
            if any(name.startswith(prefix) for prefix in prefixes):
                constants[name] = value
            current_value = value + 1
    return constants


def _merge_constants(*groups):
    merged = {}
    for group in groups:
        merged.update(group)
    return merged


def _load_move_constants(root, macros):
    constants = {}
    constants["moves"] = _parse_enum_constants(root / "include/constants/moves.h", "Move", macros)
    constants["effects"] = _parse_enum_constants(root / "include/constants/battle_move_effects.h", "BattleMoveEffects", macros)
    constants["types"] = _parse_enum_constants(root / "include/constants/pokemon.h", "Type", macros)
    constants["damage_categories"] = _parse_enum_constants(root / "include/constants/pokemon.h", "DamageCategory", macros)
    constants["targets"] = _parse_enum_constants(root / "include/constants/battle.h", "MoveTarget", macros)
    constants["move_effects"] = _parse_enum_constants(root / "include/constants/battle.h", "MoveEffect", macros)
    constants["z_effects"] = _parse_enum_constants(root / "include/constants/battle_z_move_effects.h", "ZEffect", macros)
    constants["contest_categories"] = _parse_enum_constants(root / "include/constants/global.h", "ContestCategories", macros)
    constants["protect_methods"] = _parse_enum_constants(root / "include/move.h", "ProtectMethod", macros)
    constants["contest_effects"] = _parse_define_constants(root / "include/constants/contest.h", "CONTEST_EFFECT_", macros)
    constants["combo_starters"] = _parse_all_enum_constants_with_prefixes(
        root / "include/constants/contest.h",
        ["COMBO_STARTER_"],
        macros,
    )
    constants["battle_strings"] = _parse_all_enum_constants_with_prefixes(
        root / "include/constants/battle_string_ids.h",
        ["STRINGID_"],
        macros,
    )
    constants["battle_states"] = _parse_all_enum_constants_with_prefixes(
        root / "include/constants/battle.h",
        ["STATE_"],
        macros,
    )
    constants["battle_weather"] = _parse_all_enum_constants_with_prefixes(
        root / "include/constants/battle.h",
        ["BATTLE_WEATHER_"],
        macros,
    )
    constants["weather_flags"] = _parse_define_constants(root / "include/constants/battle.h", "B_WEATHER_", macros)
    constants["status_flags"] = _parse_define_constants(root / "include/constants/battle.h", "STATUS1_", macros)
    constants["hold_effects"] = _parse_all_enum_constants_with_prefixes(
        root / "include/constants/hold_effects.h",
        ["HOLD_EFFECT_"],
        macros,
    )
    constants["abilities"] = _parse_enum_constants(root / "include/constants/abilities.h", "Ability", macros)
    constants["species"] = _parse_define_constants(root / "include/constants/species.h", "SPECIES_", macros)

    frostbite_enabled = ExpressionEvaluator(macros).eval_int("B_USE_FROSTBITE == TRUE")
    freeze_alias = "MOVE_EFFECT_FROSTBITE" if frostbite_enabled else "MOVE_EFFECT_FREEZE"
    if freeze_alias in constants["move_effects"]:
        constants["move_effects"]["MOVE_EFFECT_FREEZE_OR_FROSTBITE"] = constants["move_effects"][freeze_alias]
        macros["MOVE_EFFECT_FREEZE_OR_FROSTBITE"] = freeze_alias

    constants["generic_argument_constants"] = _merge_constants(
        constants["move_effects"],
        constants["types"],
        constants["damage_categories"],
        constants["battle_strings"],
        constants["battle_states"],
        constants["battle_weather"],
        constants["weather_flags"],
        constants["status_flags"],
        constants["protect_methods"],
        constants["hold_effects"],
        constants["abilities"],
        constants["species"],
    )
    constants["evaluator"] = ExpressionEvaluator(macros)
    return constants


def _parse_designated_field_assignments(body):
    body = _strip_c_comments(body)
    fields = {}
    index = 0
    paren_depth = 0
    brace_depth = 0
    bracket_depth = 0
    in_string = False
    escaped = False

    while index < len(body):
        char = body[index]
        if in_string:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
            index += 1
            continue
        if char == '"':
            in_string = True
            index += 1
            continue
        if char == "(":
            paren_depth += 1
        elif char == ")":
            paren_depth -= 1
        elif char == "{":
            brace_depth += 1
        elif char == "}":
            brace_depth -= 1
        elif char == "[":
            bracket_depth += 1
        elif char == "]":
            bracket_depth -= 1

        if char == "." and paren_depth == 0 and brace_depth == 0 and bracket_depth == 0:
            match = re.match(r"\.([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*)\s*=", body[index:])
            if match:
                field_name = match.group(1)
                value_start = index + match.end()
                value_end = _find_top_level_comma(body, value_start)
                value = body[value_start:value_end if value_end != -1 else len(body)].strip()
                fields[field_name] = value
                index = value_end + 1 if value_end != -1 else len(body)
                continue
        index += 1
    return fields


def _find_top_level_comma(text, start):
    paren_depth = 0
    brace_depth = 0
    bracket_depth = 0
    in_string = False
    escaped = False
    for index in range(start, len(text)):
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
            paren_depth += 1
        elif char == ")":
            paren_depth -= 1
        elif char == "{":
            brace_depth += 1
        elif char == "}":
            brace_depth -= 1
        elif char == "[":
            bracket_depth += 1
        elif char == "]":
            bracket_depth -= 1
        elif char == "," and paren_depth == 0 and brace_depth == 0 and bracket_depth == 0:
            return index
    return -1


def _source_location(relative_path, line):
    return {
        "file": relative_path.as_posix(),
        "line": int(line),
    }


def _load_battle_effect_script_links(root):
    path = root / BATTLE_MOVE_EFFECTS_PATH
    text = _strip_c_comments(path.read_text(encoding="utf-8"))
    table_match = re.search(r"gBattleMoveEffects\s*\[\s*NUM_BATTLE_MOVE_EFFECTS\s*\]\s*=", text)
    if not table_match:
        return {}
    brace_start = text.find("{", table_match.end())
    brace_end = _find_matching_brace(text, brace_start)
    if brace_start == -1 or brace_end == -1:
        return {}

    body = text[brace_start + 1:brace_end]
    links = {}
    matches = list(BATTLE_MOVE_EFFECT_ENTRY_RE.finditer(body))
    for index, match in enumerate(matches):
        effect_symbol = match.group(1)
        initializer_start = match.end()
        initializer_end = matches[index + 1].start() if index + 1 < len(matches) else len(body)
        initializer = body[initializer_start:initializer_end].strip().rstrip(",").strip()
        fields = {}
        if initializer.startswith("{"):
            close_index = _find_matching_brace(initializer, 0)
            if close_index != -1:
                fields = _parse_designated_field_assignments(initializer[1:close_index])
        raw_fields = {field: _compact_source(value) for field, value in fields.items()}
        line = text.count("\n", 0, brace_start + 1 + match.start()) + 1
        battle_script = str(raw_fields.get("battleScript", ""))
        links[effect_symbol] = {
            "effect_symbol": effect_symbol,
            "battle_script": battle_script,
            "source": _source_location(BATTLE_MOVE_EFFECTS_PATH, line),
            "raw_fields": raw_fields,
            "status": "resolved" if battle_script else "missing_battle_script_field",
        }
    return links


def _parse_shared_text_entries(root, records, macros):
    symbol_sources = {}
    for record in records:
        match = re.search(r"(?:static\s+)?const\s+u8\s+([A-Za-z_][A-Za-z0-9_]*)\[\]\s*=", record.text)
        if match:
            symbol_sources[match.group(1)] = _relative_source_location(root, record)

    text = "\n".join(record.text for record in records)
    shared = {}
    pattern = re.compile(r"(?:static\s+)?const\s+u8\s+([A-Za-z_][A-Za-z0-9_]*)\[\]\s*=\s*(.*?);", re.S)
    for match in pattern.finditer(text):
        symbol = match.group(1)
        value = _expand_string_macros(match.group(2), macros)
        parsed = _parse_inline_text_value(value)
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


def _parse_move_text_value(value, shared_text, macros):
    expanded = _expand_string_macros(value, macros)
    raw = _extract_string_literals(expanded)
    if raw is not None:
        return {
            "kind": "inline",
            "source_text": raw,
            "display_text": display_text_from_source(raw),
        }

    symbol = _compact_source(value)
    if symbol in shared_text:
        resolved = dict(shared_text[symbol])
        resolved["kind"] = "reference"
        resolved["symbol"] = symbol
        return resolved
    return {
        "kind": "reference",
        "symbol": symbol,
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


def _parse_move_entries(root, records, constants, shared_text, macros, battle_effect_links):
    moves = {}
    order = []
    index = 0
    while index < len(records):
        match = MOVE_ENTRY_RE.search(records[index].text)
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
        record = _build_move_record(
            root,
            symbol,
            start_record,
            initializer_kind,
            raw_initializer,
            fields,
            constants,
            shared_text,
            macros,
            battle_effect_links,
        )
        moves[symbol] = record
        order.append(symbol)
        index = end_index + 1

    order.sort(key=lambda item: (moves[item].get("id") is None, moves[item].get("id", 0), item))
    return moves, order


def _build_move_record(
    root,
    symbol,
    source_record,
    initializer_kind,
    raw_initializer,
    fields,
    constants,
    shared_text,
    macros,
    battle_effect_links,
):
    evaluator = constants["evaluator"]
    warnings = []
    record = {
        "id": _constant_value(symbol, constants["moves"]),
        "symbol": symbol,
        "name_key": _remove_prefix(symbol, "MOVE_").lower(),
        "source": _relative_source_location(root, source_record),
        "initializer_kind": initializer_kind,
    }

    if initializer_kind != "struct":
        record["raw_initializer"] = _compact_source(raw_initializer)
        record["evaluation_status"] = "partial"
        record["warnings"] = ["move initializer is not a struct initializer"]
        return record

    raw_fields = {field: _compact_source(value) for field, value in fields.items()}
    record["raw_fields"] = raw_fields

    if "name" in fields:
        record["name"] = _parse_move_text_value(fields["name"], shared_text, macros)
    if "description" in fields:
        record["description"] = _parse_move_text_value(fields["description"], shared_text, macros)
    if "effect" in fields:
        record["effect"] = _constant_record(fields["effect"], constants["effects"], "EFFECT_", evaluator, warnings)
        effect_symbol = str(record["effect"].get("symbol", ""))
        effect_link = battle_effect_links.get(effect_symbol, {})
        battle_script = str(effect_link.get("battle_script", ""))
        record["battle_effect_script"] = battle_script
        record["battle_effect_source"] = {
            "effect_symbol": effect_symbol,
            "effect_id": record["effect"].get("value"),
            "source": effect_link.get("source", {}),
            "status": str(effect_link.get("status", "missing_effect_route")),
        }
    if "type" in fields:
        record["type"] = _constant_record(fields["type"], constants["types"], "TYPE_", evaluator, warnings)
    if "category" in fields:
        record["category"] = _constant_record(fields["category"], constants["damage_categories"], "DAMAGE_CATEGORY_", evaluator, warnings)
    if "target" in fields:
        record["target"] = _constant_record(fields["target"], constants["targets"], "TARGET_", evaluator, warnings)

    for source_field, output_field in CORE_INTEGER_FIELDS.items():
        if source_field in fields:
            record[output_field] = _eval_field_int(fields[source_field], evaluator, warnings)

    for source_field, output_field in CORE_BOOLEAN_FIELDS.items():
        if source_field in fields:
            record[output_field] = bool(_eval_field_int(fields[source_field], evaluator, warnings))

    flags = _parse_boolean_field_group(fields, MOVE_FLAG_FIELDS, evaluator, warnings)
    if flags:
        record["flags"] = flags

    ban_flags = _parse_boolean_field_group(fields, BAN_FLAG_FIELDS, evaluator, warnings)
    if ban_flags:
        record["ban_flags"] = ban_flags

    if "zMove" in fields:
        record["z_move"] = _parse_z_move(fields["zMove"], constants, evaluator, warnings)

    argument = _parse_argument(fields, constants, evaluator)
    if argument:
        record["argument"] = argument

    if "additionalEffects" in fields:
        additional_effects = _parse_additional_effects(fields["additionalEffects"], constants, evaluator, warnings)
        record["additional_effects"] = additional_effects
        record["num_additional_effects"] = len(additional_effects)

    contest = _parse_contest(fields, constants, evaluator, warnings)
    if contest:
        record["contest"] = contest

    if "battleAnimScript" in fields:
        record["battle_anim_script"] = _compact_source(fields["battleAnimScript"])

    known_fields = {
        "name",
        "description",
        "effect",
        "type",
        "category",
        "power",
        "accuracy",
        "target",
        "pp",
        "zMove",
        "priority",
        "strikeCount",
        "multiHit",
        "explosion",
        "criticalHitStage",
        "alwaysCriticalHit",
        "numAdditionalEffects",
        "argument",
        "additionalEffects",
        "contestEffect",
        "contestCategory",
        "contestComboStarterId",
        "contestComboMoves",
        "battleAnimScript",
    }
    known_fields.update(MOVE_FLAG_FIELDS)
    known_fields.update(BAN_FLAG_FIELDS)
    known_fields.update(field for field in fields if field.startswith("argument."))
    unsupported = sorted(field for field in fields.keys() if field not in known_fields)
    if unsupported:
        record["unsupported_fields"] = unsupported

    if warnings:
        record["warnings"] = sorted(set(warnings))
    record["evaluation_status"] = "partial" if warnings or unsupported else "ok"
    return record


def _parse_boolean_field_group(fields, field_names, evaluator, warnings):
    parsed = {}
    for source_field in field_names:
        if source_field in fields:
            parsed[_camel_to_snake(source_field)] = bool(_eval_field_int(fields[source_field], evaluator, warnings))
    return parsed


def _parse_z_move(value, constants, evaluator, warnings):
    raw = _compact_source(value)
    record = {"raw": raw}
    if value.strip().startswith("{") and value.strip().endswith("}"):
        fields = _parse_designated_field_assignments(value.strip()[1:-1])
        if "effect" in fields:
            record["effect"] = _constant_record(fields["effect"], constants["z_effects"], "Z_EFFECT_", evaluator, warnings)
        if "powerOverride" in fields:
            record["power_override"] = _eval_field_int(fields["powerOverride"], evaluator, warnings)
    else:
        record["value"] = _parse_generic_value(value, constants["generic_argument_constants"], evaluator)
    return record


def _parse_argument(fields, constants, evaluator):
    raw_argument_fields = {}
    for field, value in fields.items():
        if field == "argument":
            inner = value.strip()
            if inner.startswith("{") and inner.endswith("}"):
                for nested_field, nested_value in _parse_designated_field_assignments(inner[1:-1]).items():
                    raw_argument_fields[nested_field] = nested_value
            else:
                raw_argument_fields["value"] = value
        elif field.startswith("argument."):
            raw_argument_fields[field[len("argument."):]] = value

    if not raw_argument_fields:
        return {}

    parsed = {
        "raw_fields": {field: _compact_source(value) for field, value in raw_argument_fields.items()},
        "fields": {},
    }
    for field, value in raw_argument_fields.items():
        _assign_nested(parsed["fields"], field.split("."), _parse_generic_value(value, constants["generic_argument_constants"], evaluator))
    return parsed


def _assign_nested(target, path, value):
    current = target
    for part in path[:-1]:
        existing = current.get(part)
        if not isinstance(existing, dict):
            existing = {}
            current[part] = existing
        current = existing
    current[path[-1]] = value


def _parse_generic_value(value, constants, evaluator):
    raw = _compact_source(value)
    result = {"raw": raw}
    integer = evaluator.eval_int(raw)
    if integer is not None:
        result["value"] = integer
        symbol = _find_symbol_for_value(constants, integer)
        if symbol is not None and re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", raw):
            result["symbol"] = symbol
    if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", raw):
        result["symbol"] = raw
        if raw in constants:
            result["value"] = constants[raw]
    return result


def _parse_additional_effects(value, constants, evaluator, warnings):
    raw = _compact_source(value)
    macro_match = re.fullmatch(r"ADDITIONAL_EFFECTS\s*\((.*)\)", raw, re.S)
    if not macro_match:
        return [{"raw": raw, "status": "unparsed"}]

    effects = []
    for effect_value in _split_top_level(macro_match.group(1), ","):
        effect_raw = effect_value.strip()
        if not effect_raw:
            continue
        record = {"raw": _compact_source(effect_raw)}
        if effect_raw.startswith("{") and effect_raw.endswith("}"):
            fields = _parse_designated_field_assignments(effect_raw[1:-1])
            raw_fields = {field: _compact_source(field_value) for field, field_value in fields.items()}
            if raw_fields:
                record["raw_fields"] = raw_fields
            for field, field_value in fields.items():
                if field == "moveEffect":
                    record["move_effect"] = _constant_record(field_value, constants["move_effects"], "MOVE_EFFECT_", evaluator, warnings)
                elif field == "chance":
                    record["chance"] = _eval_field_int(field_value, evaluator, warnings)
                elif field in ADDITIONAL_EFFECT_BOOLEAN_FIELDS:
                    record[_camel_to_snake(field)] = bool(_eval_field_int(field_value, evaluator, warnings))
                else:
                    _assign_nested(record, field.split("."), _parse_generic_value(field_value, constants["generic_argument_constants"], evaluator))
        effects.append(record)
    return effects


def _parse_contest(fields, constants, evaluator, warnings):
    contest = {}
    if "contestEffect" in fields:
        contest["effect"] = _constant_record(fields["contestEffect"], constants["contest_effects"], "CONTEST_EFFECT_", evaluator, warnings)
    if "contestCategory" in fields:
        contest["category"] = _constant_record(fields["contestCategory"], constants["contest_categories"], "CONTEST_CATEGORY_", evaluator, warnings)
    if "contestComboStarterId" in fields:
        contest["combo_starter"] = _constant_record(fields["contestComboStarterId"], constants["combo_starters"], "COMBO_STARTER_", evaluator, warnings)
    if "contestComboMoves" in fields:
        contest["combo_moves"] = _parse_constant_list(fields["contestComboMoves"], constants["combo_starters"], "COMBO_STARTER_", evaluator, warnings)
    return contest


def _parse_constant_list(value, constants, prefix, evaluator, warnings):
    raw = _compact_source(value)
    if raw.startswith("{") and raw.endswith("}"):
        items = [_compact_source(item) for item in _split_top_level(raw[1:-1], ",") if item.strip()]
    else:
        items = [raw]
    return [_constant_record(item, constants, prefix, evaluator, warnings) for item in items]


def _constant_value(symbol, constants):
    value = constants.get(symbol)
    return int(value) if isinstance(value, int) else None


def _find_symbol_for_value(constants, value):
    for symbol, constant_value in constants.items():
        if constant_value == value:
            return symbol
    return None


def _camel_to_snake(value):
    chars = []
    for index, char in enumerate(value):
        if char.isupper() and index > 0:
            chars.append("_")
        chars.append(char.lower())
    return "".join(chars)


def export_moves(root):
    macros = _load_move_macro_expressions(root)
    constants = _load_move_constants(root, macros)
    source_records = _read_source_lines(root / "src/data/moves_info.h")
    preprocessed_records, preprocessor_report = _preprocess_records(source_records, macros)
    shared_text = _parse_shared_text_entries(root, preprocessed_records, macros)
    battle_effect_links = _load_battle_effect_script_links(root)
    moves, move_order = _parse_move_entries(
        root,
        preprocessed_records,
        constants,
        shared_text,
        macros,
        battle_effect_links,
    )

    core_fields = {"effect", "type", "category", "power", "accuracy", "pp", "target"}
    core_battle_count = sum(1 for record in moves.values() if core_fields.issubset(record.get("raw_fields", {}).keys()))
    additional_effect_move_count = sum(1 for record in moves.values() if record.get("additional_effects"))
    battle_effect_script_count = sum(1 for record in moves.values() if record.get("battle_effect_script"))
    missing_battle_effect_script_count = len(moves) - battle_effect_script_count
    warning_count = len(preprocessor_report["warnings"])
    warning_count += sum(len(record.get("warnings", [])) for record in moves.values())
    unsupported_field_count = sum(len(record.get("unsupported_fields", [])) for record in moves.values())

    return {
        "schema_version": 1,
        "source": {
            "project": "pokeemerald-expansion",
            "moves_info": "src/data/moves_info.h",
            "struct_definition": "include/move.h",
            "constants": [
                "include/constants/moves.h",
                "include/constants/battle_move_effects.h",
                "include/constants/battle.h",
                "include/constants/pokemon.h",
                "include/constants/contest.h",
                "include/constants/global.h",
                "include/constants/battle_z_move_effects.h",
            ],
            "config": [
                "include/config/general.h",
                "include/config/battle.h",
                "include/config/contest.h",
                "include/config/overworld.h",
                "include/config/pokemon.h",
                "include/config/item.h",
            ],
            "preprocessor": preprocessor_report,
        },
        "constants": {
            "moves": _export_constant_group(constants["moves"], "MOVE_"),
            "effects": _export_constant_group(constants["effects"], "EFFECT_"),
            "types": _export_constant_group(constants["types"], "TYPE_"),
            "damage_categories": _export_constant_group(constants["damage_categories"], "DAMAGE_CATEGORY_"),
            "targets": _export_constant_group(constants["targets"], "TARGET_"),
            "move_effects": _export_constant_group(constants["move_effects"], "MOVE_EFFECT_"),
            "z_effects": _export_constant_group(constants["z_effects"], "Z_EFFECT_"),
            "contest_effects": _export_constant_group(constants["contest_effects"], "CONTEST_EFFECT_"),
            "contest_categories": _export_constant_group(constants["contest_categories"], "CONTEST_CATEGORY_"),
            "combo_starters": _export_constant_group(constants["combo_starters"], "COMBO_STARTER_"),
        },
        "shared_text": shared_text,
        "move_order": move_order,
        "moves": moves,
        "stats": {
            "move_count": len(moves),
            "moves_with_core_battle_fields": core_battle_count,
            "moves_with_additional_effects": additional_effect_move_count,
            "moves_with_battle_effect_scripts": battle_effect_script_count,
            "missing_battle_effect_script_count": missing_battle_effect_script_count,
            "shared_text_count": len(shared_text),
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

    exported = export_moves(source_root)
    moves_output = output_root / "pokemon" / "moves.json"
    write_json(moves_output, exported)

    stats = exported["stats"]
    manifest_entry = {
        "category": "moves",
        "path": to_project_path(moves_output),
        "move_count": stats["move_count"],
        "moves_with_core_battle_fields": stats["moves_with_core_battle_fields"],
        "moves_with_additional_effects": stats["moves_with_additional_effects"],
        "moves_with_battle_effect_scripts": stats["moves_with_battle_effect_scripts"],
        "missing_battle_effect_script_count": stats["missing_battle_effect_script_count"],
        "warning_count": stats["warning_count"],
    }
    write_manifest(
        output_root / "import_manifest.json",
        exported_pokemon=[manifest_entry],
        generator="tools/importer/export_moves.py",
    )

    print(json.dumps({
        "exported": manifest_entry,
        "preprocessor_decision_count": stats["preprocessor_decision_count"],
        "unsupported_field_count": stats["unsupported_field_count"],
    }, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
