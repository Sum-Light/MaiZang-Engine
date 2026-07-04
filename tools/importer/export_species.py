#!/usr/bin/env python3
"""Export pokeemerald-expansion species data into generated JSON."""

import argparse
import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path

from export_map import write_json, write_manifest
from source_probe import load_config, to_project_path
from text_codec import display_text_from_source


IDENTIFIER_RE = re.compile(r"\b[A-Za-z_][A-Za-z0-9_]*\b")
DEFINE_RE = re.compile(r"^\s*#\s*define\s+([A-Za-z_][A-Za-z0-9_]*)(.*)$")
SPECIES_ENTRY_RE = re.compile(r"\[(SPECIES_[A-Za-z0-9_]*)\]\s*=")

STAT_FIELDS = {
    "baseHP": "hp",
    "baseAttack": "attack",
    "baseDefense": "defense",
    "baseSpeed": "speed",
    "baseSpAttack": "sp_attack",
    "baseSpDefense": "sp_defense",
}

EV_FIELDS = {
    "evYield_HP": "hp",
    "evYield_Attack": "attack",
    "evYield_Defense": "defense",
    "evYield_Speed": "speed",
    "evYield_SpAttack": "sp_attack",
    "evYield_SpDefense": "sp_defense",
}

INTEGER_FIELDS = {
    "catchRate": "catch_rate",
    "expYield": "exp_yield",
    "eggCycles": "egg_cycles",
    "friendship": "friendship",
    "height": "height",
    "weight": "weight",
    "safariZoneFleeRate": "safari_zone_flee_rate",
    "pokemonScale": "pokemon_scale",
    "pokemonOffset": "pokemon_offset",
    "trainerScale": "trainer_scale",
    "trainerOffset": "trainer_offset",
    "frontPicYOffset": "front_pic_y_offset",
    "backPicYOffset": "back_pic_y_offset",
    "frontAnimDelay": "front_anim_delay",
    "iconPalIndex": "icon_palette_index",
    "enemyMonElevation": "enemy_mon_elevation",
    "enemyShadowXOffset": "enemy_shadow_x_offset",
    "enemyShadowYOffset": "enemy_shadow_y_offset",
    "suppressEnemyShadow": "suppress_enemy_shadow",
}

REFERENCE_FIELDS = {
    "frontPic": "front_pic",
    "backPic": "back_pic",
    "palette": "palette",
    "shinyPalette": "shiny_palette",
    "iconSprite": "icon_sprite",
    "frontPicFemale": "front_pic_female",
    "backPicFemale": "back_pic_female",
    "paletteFemale": "palette_female",
    "shinyPaletteFemale": "shiny_palette_female",
    "iconSpriteFemale": "icon_sprite_female",
    "footprint": "footprint",
    "frontAnimFrames": "front_anim_frames",
    "frontAnimId": "front_anim_id",
    "backAnimId": "back_anim_id",
    "pokemonJumpType": "pokemon_jump_type",
    "enemyShadowSize": "enemy_shadow_size",
    "perfectIVCount": "perfect_iv_count",
    "eggId": "egg_id",
    "levelUpLearnset": "level_up_learnset",
    "teachableLearnset": "teachable_learnset",
    "eggMoveLearnset": "egg_move_learnset",
    "evolutions": "evolutions",
    "formSpeciesIdTable": "form_species_id_table",
    "formChangeTable": "form_change_table",
}

FLAG_FIELDS = [
    "noFlip",
    "isRestrictedLegendary",
    "isSubLegendary",
    "isMythical",
    "isUltraBeast",
    "isParadox",
    "isTotem",
    "isMegaEvolution",
    "isPrimalReversion",
    "isUltraBurst",
    "isGigantamax",
    "isTeraForm",
    "isAlolanForm",
    "isGalarianForm",
    "isHisuianForm",
    "isPaldeanForm",
    "cannotBeTraded",
    "dexForceRequired",
    "isFrontierBanned",
    "isSkyBattleBanned",
]


@dataclass(frozen=True)
class SourceLine:
    path: Path
    line_number: int
    text: str


@dataclass
class ConditionalFrame:
    parent_active: bool
    branch_taken: bool
    active: bool


class ExpressionEvaluator:
    def __init__(self, macros, unknown_as_zero=False):
        self.macros = macros
        self.unknown_as_zero = unknown_as_zero
        self.cache = {}
        self.warnings = []

    def eval_int(self, expression):
        value = self._eval_int(expression, [])
        if value is None:
            return None
        return int(value)

    def eval_bool(self, expression):
        value = self.eval_int(expression)
        return bool(value)

    def _eval_int(self, expression, resolving):
        if expression is None:
            return None
        expr = _clean_expression(str(expression))
        if not expr:
            return 1
        expr = _strip_outer_parens(expr)

        ternary = _split_ternary(expr)
        if ternary is not None:
            condition, true_expr, false_expr = ternary
            return self._eval_int(true_expr, resolving) if self._eval_int(condition, resolving) else self._eval_int(false_expr, resolving)

        percent = re.fullmatch(r"PERCENT_FEMALE\s*\((.+)\)", expr)
        if percent:
            raw_percent = self._eval_numeric_raw(percent.group(1), resolving)
            if raw_percent is None:
                return None
            return min(254, int((float(raw_percent) * 255) / 100))

        return self._eval_numeric(expr, resolving)

    def _eval_numeric(self, expression, resolving):
        value = self._eval_numeric_raw(expression, resolving)
        if value is None:
            return None
        try:
            return int(value)
        except (TypeError, ValueError):
            self._warn_once("expression did not produce an integer: {}".format(expression))
            return None

    def _eval_numeric_raw(self, expression, resolving):
        expr = _clean_expression(str(expression))
        expr = re.sub(r"\b([0-9]+)[uUlL]+\b", r"\1", expr)
        expr = expr.replace("&&", " and ")
        expr = expr.replace("||", " or ")
        expr = re.sub(r"!(?!=)", " not ", expr)
        unresolved = []

        def replace_identifier(match):
            name = match.group(0)
            if name in {"and", "or", "not", "min", "max"}:
                return name
            value = self._resolve_identifier(name, resolving)
            if value is None:
                self._warn_once("unknown identifier in expression: {}".format(name))
                unresolved.append(name)
                return "0"
            return str(value)

        translated = IDENTIFIER_RE.sub(replace_identifier, expr)
        if unresolved and not self.unknown_as_zero:
            return None
        if not re.fullmatch(r"[0-9A-Fa-fxX\.\s\+\-\*/%<>=!&\|\^\(\)~,]+|.*\b(?:and|or|not|min|max)\b.*", translated):
            self._warn_once("unsupported expression syntax: {}".format(expression))
            return None
        try:
            value = eval(translated, {"__builtins__": {}}, {"min": min, "max": max})
        except Exception:
            self._warn_once("could not evaluate expression: {}".format(expression))
            return None
        try:
            return value
        except (TypeError, ValueError):
            self._warn_once("expression did not produce a numeric value: {}".format(expression))
            return None

    def _resolve_identifier(self, name, resolving):
        if name in self.cache:
            return self.cache[name]
        if name in resolving:
            self._warn_once("recursive macro expression: {}".format(name))
            return None
        if name not in self.macros:
            return None

        value = self._eval_int(self.macros[name], resolving + [name])
        if value is not None:
            self.cache[name] = value
        return value

    def _warn_once(self, message):
        if message not in self.warnings:
            self.warnings.append(message)


def _clean_expression(expression):
    expression = _strip_c_comments(expression)
    expression = expression.strip()
    if expression.endswith(","):
        expression = expression[:-1].strip()
    return expression


def _strip_outer_parens(expression):
    expr = expression.strip()
    while expr.startswith("(") and expr.endswith(")") and _matching_outer_parens(expr):
        expr = expr[1:-1].strip()
    return expr


def _matching_outer_parens(expression):
    depth = 0
    for index, char in enumerate(expression):
        if char == "(":
            depth += 1
        elif char == ")":
            depth -= 1
            if depth == 0 and index != len(expression) - 1:
                return False
    return depth == 0


def _split_ternary(expression):
    question = _find_top_level_char(expression, "?")
    if question == -1:
        return None

    depth = 0
    nested_ternary = 0
    for index in range(question + 1, len(expression)):
        char = expression[index]
        if char in "([{":
            depth += 1
        elif char in ")]}":
            depth -= 1
        elif depth == 0 and char == "?":
            nested_ternary += 1
        elif depth == 0 and char == ":":
            if nested_ternary == 0:
                return (
                    expression[:question].strip(),
                    expression[question + 1:index].strip(),
                    expression[index + 1:].strip(),
                )
            nested_ternary -= 1
    return None


def _find_top_level_char(text, target):
    depth = 0
    in_string = False
    escaped = False
    for index, char in enumerate(text):
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
        elif char in "([{":
            depth += 1
        elif char in ")]}":
            depth -= 1
        elif depth == 0 and char == target:
            return index
    return -1


def _strip_c_comments(text):
    output = []
    index = 0
    in_string = False
    in_char = False
    escaped = False
    while index < len(text):
        char = text[index]
        next_char = text[index + 1] if index + 1 < len(text) else ""

        if in_string or in_char:
            output.append(char)
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif in_string and char == '"':
                in_string = False
            elif in_char and char == "'":
                in_char = False
            index += 1
            continue

        if char == '"':
            in_string = True
            output.append(char)
            index += 1
        elif char == "'":
            in_char = True
            output.append(char)
            index += 1
        elif char == "/" and next_char == "/":
            while index < len(text) and text[index] != "\n":
                index += 1
        elif char == "/" and next_char == "*":
            index += 2
            while index + 1 < len(text) and not (text[index] == "*" and text[index + 1] == "/"):
                if text[index] == "\n":
                    output.append("\n")
                index += 1
            index += 2
        else:
            output.append(char)
            index += 1
    return "".join(output)


def _define_parts(line):
    match = DEFINE_RE.match(_strip_c_comments(line))
    if not match:
        return None
    name = match.group(1)
    tail = match.group(2)
    if tail.startswith("("):
        return None
    value = tail.strip() or "1"
    return name, value


def _read_source_lines(path):
    lines = []
    for line_number, raw_line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        lines.append(SourceLine(path=path, line_number=line_number, text=raw_line))
    return lines


def _expand_species_info_includes(root, relative_path, seen=None):
    if seen is None:
        seen = set()
    path = root / relative_path
    if path in seen:
        return []
    seen.add(path)

    records = []
    for record in _read_source_lines(path):
        include = re.match(r'\s*#\s*include\s+"(species_info/[^"]+)"', record.text)
        if include:
            include_path = Path("src/data/pokemon") / include.group(1)
            records.extend(_expand_species_info_includes(root, include_path, seen))
        else:
            records.append(record)
    return records


def _load_macro_expressions(root):
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
        Path("include/config/pokemon.h"),
        Path("include/config/species_enabled.h"),
        Path("include/constants/pokemon.h"),
    ]
    for relative_path in config_files:
        _read_defines_into(root / relative_path, macros)
    return macros


def _read_defines_into(path, macros):
    if not path.exists():
        return
    continuing = False
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        if continuing:
            continuing = raw_line.rstrip().endswith("\\")
            continue
        parts = _define_parts(raw_line)
        if parts is not None:
            macros[parts[0]] = parts[1].rstrip("\\").strip()
        continuing = raw_line.rstrip().endswith("\\")


def _preprocess_records(records, macros):
    evaluator = ExpressionEvaluator(macros, unknown_as_zero=True)
    frames = []
    output = []
    decisions = []
    skipping_define = False

    def current_active():
        return frames[-1].active if frames else True

    for record in records:
        stripped = record.text.strip()

        if skipping_define:
            skipping_define = record.text.rstrip().endswith("\\")
            continue

        directive = re.match(r"^#\s*([A-Za-z_][A-Za-z0-9_]*)\b(.*)$", stripped)
        if directive:
            keyword = directive.group(1)
            argument = directive.group(2).strip()
            if keyword == "if":
                parent = current_active()
                active = evaluator.eval_bool(argument) if parent else False
                frames.append(ConditionalFrame(parent_active=parent, branch_taken=active, active=active))
                decisions.append(_decision_record(record, "if", argument, active))
            elif keyword == "ifdef":
                parent = current_active()
                active = bool(parent and argument in macros)
                frames.append(ConditionalFrame(parent_active=parent, branch_taken=active, active=active))
                decisions.append(_decision_record(record, "ifdef", argument, active))
            elif keyword == "ifndef":
                parent = current_active()
                active = bool(parent and argument not in macros)
                frames.append(ConditionalFrame(parent_active=parent, branch_taken=active, active=active))
                decisions.append(_decision_record(record, "ifndef", argument, active))
            elif keyword == "elif" and frames:
                frame = frames[-1]
                if frame.parent_active and not frame.branch_taken:
                    active = evaluator.eval_bool(argument)
                    frame.active = active
                    frame.branch_taken = active
                else:
                    active = False
                    frame.active = False
                decisions.append(_decision_record(record, "elif", argument, active))
            elif keyword == "else" and frames:
                frame = frames[-1]
                active = bool(frame.parent_active and not frame.branch_taken)
                frame.active = active
                frame.branch_taken = frame.branch_taken or active
                decisions.append(_decision_record(record, "else", argument, active))
            elif keyword == "endif":
                if frames:
                    frames.pop()
            elif keyword == "define":
                if current_active():
                    parts = _define_parts(record.text)
                    if parts is not None:
                        macros[parts[0]] = parts[1].rstrip("\\").strip()
                        evaluator.cache.pop(parts[0], None)
                skipping_define = record.text.rstrip().endswith("\\")
            else:
                pass
            continue

        if current_active():
            output.append(record)

    return output, {
        "decisions": decisions,
        "warnings": evaluator.warnings,
    }


def _decision_record(record, kind, expression, active):
    return {
        "kind": kind,
        "expression": expression,
        "active": bool(active),
        "source": _source_location(record),
    }


def _source_location(record):
    return {
        "file": to_project_path(record.path),
        "line": record.line_number,
    }


def _relative_source_location(root, record):
    try:
        relative = record.path.relative_to(root)
    except ValueError:
        relative = record.path
    return {
        "file": to_project_path(relative),
        "line": record.line_number,
    }


def _parse_enum_constants(path, enum_name, macros):
    text = _strip_c_comments(path.read_text(encoding="utf-8"))
    pattern = re.compile(r"enum(?:\s+__attribute__\s*\(\(packed\)\))?\s+" + re.escape(enum_name) + r"\s*\{")
    match = pattern.search(text)
    if not match:
        return {}

    brace_start = text.find("{", match.start())
    brace_end = _find_matching_brace(text, brace_start)
    if brace_end == -1:
        return {}

    body = text[brace_start + 1:brace_end]
    body = "\n".join(line for line in body.splitlines() if not line.strip().startswith("#"))
    entries = _split_top_level(body, ",")
    evaluator = ExpressionEvaluator(macros)
    constants = {}
    current_value = 0
    for entry in entries:
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


def _parse_define_constants(path, prefix, macros):
    raw_macros = {}
    _read_defines_into(path, raw_macros)
    for name, value in raw_macros.items():
        if name.startswith(prefix):
            macros[name] = value

    evaluator = ExpressionEvaluator(macros)
    constants = {}
    for name in sorted(raw_macros.keys()):
        if not name.startswith(prefix):
            continue
        value = evaluator.eval_int(raw_macros[name])
        if value is not None:
            constants[name] = value
            macros[name] = str(value)
    return constants


def _find_matching_brace(text, open_index):
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
        elif char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return index
    return -1


def _split_top_level(text, separator):
    parts = []
    start = 0
    paren_depth = 0
    brace_depth = 0
    bracket_depth = 0
    in_string = False
    escaped = False
    for index, char in enumerate(text):
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
        elif (
            char == separator
            and paren_depth == 0
            and brace_depth == 0
            and bracket_depth == 0
        ):
            parts.append(text[start:index])
            start = index + 1
    parts.append(text[start:])
    return parts


def _parse_field_assignments(body):
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
            match = re.match(r"\.([A-Za-z_][A-Za-z0-9_]*)\s*=", body[index:])
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
        elif (
            char == ","
            and paren_depth == 0
            and brace_depth == 0
            and bracket_depth == 0
        ):
            return index
    return -1


def _parse_species_entries(root, records, constants):
    species = {}
    order = []
    index = 0
    while index < len(records):
        match = SPECIES_ENTRY_RE.search(records[index].text)
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
        initializer_kind = "macro_call"
        raw_initializer = ""
        fields = {}

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
                fields = _parse_field_assignments(raw_initializer[1:-1])
            else:
                raw_initializer = initializer_text.strip()
        else:
            end_index = _collect_macro_initializer(records, end_index, initializer_lines)
            initializer_text = "\n".join(initializer_lines)
            raw_initializer = initializer_text.strip().rstrip(",")

        record = _build_species_record(
            root,
            symbol,
            start_record,
            initializer_kind,
            raw_initializer,
            fields,
            constants,
        )
        species[symbol] = record
        order.append(symbol)
        index = end_index + 1

    order.sort(key=lambda item: (species[item].get("id") is None, species[item].get("id", 0), item))
    return species, order


def _collect_macro_initializer(records, start_index, initializer_lines):
    text = "\n".join(initializer_lines)
    end_index = start_index
    while _find_top_level_comma(text, 0) == -1 and end_index + 1 < len(records):
        end_index += 1
        initializer_lines.append(records[end_index].text)
        text = "\n".join(initializer_lines)
    return end_index


def _build_species_record(root, symbol, source_record, initializer_kind, raw_initializer, fields, constants):
    evaluator = constants["evaluator"]
    warnings = []
    record = {
        "id": _constant_value(symbol, constants["species"]),
        "symbol": symbol,
        "name_key": _remove_prefix(symbol, "SPECIES_").lower(),
        "source": _relative_source_location(root, source_record),
        "initializer_kind": initializer_kind,
    }

    if initializer_kind != "struct":
        record["raw_initializer"] = raw_initializer
        record["macro_call"] = _parse_macro_call(raw_initializer)
        record["evaluation_status"] = "partial"
        record["warnings"] = ["macro initializer is preserved but not expanded by this first species exporter"]
        return record

    raw_fields = {field: _compact_source(value) for field, value in fields.items()}
    record["raw_fields"] = raw_fields

    base_stats = {}
    for source_field, output_field in STAT_FIELDS.items():
        if source_field in fields:
            base_stats[output_field] = _eval_field_int(fields[source_field], evaluator, warnings)
    if base_stats:
        record["base_stats"] = base_stats

    ev_yield = {stat: 0 for stat in EV_FIELDS.values()}
    for source_field, output_field in EV_FIELDS.items():
        if source_field in fields:
            ev_yield[output_field] = _eval_field_int(fields[source_field], evaluator, warnings) or 0
    if any(value != 0 for value in ev_yield.values()):
        record["ev_yield"] = ev_yield

    for source_field, output_field in INTEGER_FIELDS.items():
        if source_field in fields:
            record[output_field] = _eval_field_int(fields[source_field], evaluator, warnings)

    if "speciesName" in fields:
        record["species_name"] = _parse_source_text_value(fields["speciesName"])
    if "categoryName" in fields:
        record["category_name"] = _parse_source_text_value(fields["categoryName"])
    if "description" in fields:
        record["description"] = _parse_description_value(fields["description"])

    if "types" in fields:
        record["types"] = _parse_constant_array_value(fields["types"], constants["types"], "TYPE_", evaluator, warnings)
    if "forceTeraType" in fields:
        record["force_tera_type"] = _constant_record(fields["forceTeraType"], constants["types"], "TYPE_", evaluator, warnings)
    if "growthRate" in fields:
        record["growth_rate"] = _constant_record(fields["growthRate"], constants["growth_rates"], "GROWTH_", evaluator, warnings)
    if "eggGroups" in fields:
        record["egg_groups"] = _parse_constant_array_value(fields["eggGroups"], constants["egg_groups"], "EGG_GROUP_", evaluator, warnings)
    if "abilities" in fields:
        record["abilities"] = _parse_constant_array_value(fields["abilities"], constants["abilities"], "ABILITY_", evaluator, warnings)
    if "bodyColor" in fields:
        record["body_color"] = _constant_record(fields["bodyColor"], constants["body_colors"], "BODY_COLOR_", evaluator, warnings)
    if "natDexNum" in fields:
        record["national_dex"] = _constant_record(fields["natDexNum"], constants["national_dex"], "NATIONAL_DEX_", evaluator, warnings)
    if "cryId" in fields:
        record["cry"] = _constant_record(fields["cryId"], constants["cries"], "CRY_", evaluator, warnings)
    if "itemCommon" in fields or "itemRare" in fields:
        record["held_items"] = {
            "common": _constant_record(fields.get("itemCommon", "ITEM_NONE"), constants["items"], "ITEM_", evaluator, warnings),
            "rare": _constant_record(fields.get("itemRare", "ITEM_NONE"), constants["items"], "ITEM_", evaluator, warnings),
        }

    if "genderRatio" in fields:
        gender_value = _eval_field_int(fields["genderRatio"], evaluator, warnings)
        record["gender_ratio"] = {
            "raw": _compact_source(fields["genderRatio"]),
            "value": gender_value,
            "kind": _gender_ratio_kind(fields["genderRatio"], gender_value),
        }

    references = {}
    for source_field, output_field in REFERENCE_FIELDS.items():
        if source_field in fields:
            references[output_field] = _compact_source(fields[source_field])
    if references:
        record["source_references"] = references

    flags = {}
    for flag in FLAG_FIELDS:
        if flag in fields:
            flags[_camel_to_snake(flag)] = bool(_eval_field_int(fields[flag], evaluator, warnings))
    if flags:
        record["flags"] = flags

    known_fields = set(STAT_FIELDS.keys()) | set(EV_FIELDS.keys()) | set(INTEGER_FIELDS.keys())
    known_fields.update(REFERENCE_FIELDS.keys())
    known_fields.update(FLAG_FIELDS)
    known_fields.update({
        "speciesName",
        "categoryName",
        "description",
        "types",
        "forceTeraType",
        "growthRate",
        "eggGroups",
        "abilities",
        "bodyColor",
        "natDexNum",
        "cryId",
        "itemCommon",
        "itemRare",
        "genderRatio",
    })
    unsupported = sorted(field for field in fields.keys() if field not in known_fields)
    if unsupported:
        record["unsupported_fields"] = unsupported

    if warnings:
        record["warnings"] = sorted(set(warnings))
    record["evaluation_status"] = "partial" if warnings or unsupported else "ok"
    return record


def _constant_value(symbol, constants):
    value = constants.get(symbol)
    return int(value) if isinstance(value, int) else None


def _eval_field_int(value, evaluator, warnings):
    result = evaluator.eval_int(value)
    if result is None:
        warnings.append("could not evaluate integer expression: {}".format(_compact_source(value)))
    return result


def _constant_record(value, constants, prefix, evaluator, warnings):
    raw = _compact_source(value)
    symbol_match = re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", raw)
    symbol = raw if symbol_match else None
    integer = evaluator.eval_int(raw)
    if symbol is None and integer is not None:
        symbol = _find_symbol_for_value(constants, integer)
    if symbol is not None and symbol in constants:
        integer = constants[symbol]
    if integer is None:
        warnings.append("could not resolve constant: {}".format(raw))
    return {
        "symbol": symbol or raw,
        "value": integer,
        "name": _constant_name(symbol or raw, prefix),
        "raw": raw,
    }


def _parse_constant_array_value(value, constants, prefix, evaluator, warnings):
    raw = _compact_source(value)
    if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", raw) and raw in evaluator.macros:
        raw = _compact_source(evaluator.macros[raw])
    macro_match = re.fullmatch(r"(MON_TYPES|MON_EGG_GROUPS)\s*\((.*)\)", raw, re.S)
    if macro_match:
        items = [_compact_source(item) for item in _split_top_level(macro_match.group(2), ",") if item.strip()]
        if len(items) == 1:
            items.append(items[0])
    elif raw.startswith("{") and raw.endswith("}"):
        items = [_compact_source(item) for item in _split_top_level(raw[1:-1], ",") if item.strip()]
    else:
        items = [raw]
    return [_constant_record(item, constants, prefix, evaluator, warnings) for item in items]


def _find_symbol_for_value(constants, value):
    for symbol, constant_value in constants.items():
        if constant_value == value:
            return symbol
    return None


def _constant_name(symbol, prefix):
    if symbol.startswith(prefix):
        return symbol[len(prefix):].lower()
    return symbol.lower()


def _remove_prefix(value, prefix):
    if value.startswith(prefix):
        return value[len(prefix):]
    return value


def _parse_source_text_value(value):
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


def _parse_description_value(value):
    raw = _extract_string_literals(value)
    if raw is None:
        return {
            "kind": "reference",
            "symbol": _compact_source(value),
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


def _gender_ratio_kind(raw_value, value):
    raw = _compact_source(raw_value)
    if raw == "MON_MALE" or value == 0x00:
        return "always_male"
    if raw == "MON_FEMALE" or value == 0xFE:
        return "always_female"
    if raw == "MON_GENDERLESS" or value == 0xFF:
        return "genderless"
    if raw.startswith("PERCENT_FEMALE"):
        return "percent_female"
    return "ratio"


def _parse_macro_call(value):
    raw = _compact_source(value)
    match = re.match(r"([A-Za-z_][A-Za-z0-9_]*)\s*\((.*)\)$", raw, re.S)
    if not match:
        return {
            "raw": raw,
        }
    return {
        "name": match.group(1),
        "args": [_compact_source(arg) for arg in _split_top_level(match.group(2), ",")],
    }


def _compact_source(value):
    return " ".join(str(value).strip().split())


def _camel_to_snake(value):
    chars = []
    for index, char in enumerate(value):
        if char.isupper() and index > 0:
            chars.append("_")
        chars.append(char.lower())
    return "".join(chars)


def _export_constant_group(constants, prefix):
    return {
        symbol: {
            "value": value,
            "name": _constant_name(symbol, prefix),
        }
        for symbol, value in sorted(constants.items(), key=lambda item: (item[1], item[0]))
    }


def load_species_constants(root, macros):
    constants = {}
    constants["species"] = _parse_define_constants(root / "include/constants/species.h", "SPECIES_", macros)
    constants["types"] = _parse_enum_constants(root / "include/constants/pokemon.h", "Type", macros)
    constants["growth_rates"] = _parse_enum_constants(root / "include/constants/pokemon.h", "GrowthRate", macros)
    constants["body_colors"] = _parse_enum_constants(root / "include/constants/pokemon.h", "BodyColor", macros)
    constants["abilities"] = _parse_enum_constants(root / "include/constants/abilities.h", "Ability", macros)
    constants["items"] = _parse_enum_constants(root / "include/constants/items.h", "Item", macros)
    constants["cries"] = _parse_enum_constants(root / "include/constants/cries.h", "PokemonCry", macros)
    constants["national_dex"] = _parse_enum_constants(root / "include/constants/pokedex.h", "NationalDexOrder", macros)
    constants["egg_groups"] = _parse_define_constants(root / "include/constants/pokemon.h", "EGG_GROUP_", macros)
    constants["genders"] = {
        name: value
        for name, value in _parse_define_constants(root / "include/constants/pokemon.h", "MON_", macros).items()
        if name in {"MON_MALE", "MON_FEMALE", "MON_GENDERLESS"}
    }
    constants["evaluator"] = ExpressionEvaluator(macros)
    return constants


def export_species(root):
    macros = _load_macro_expressions(root)
    constants = load_species_constants(root, macros)
    source_records = _expand_species_info_includes(root, Path("src/data/pokemon/species_info.h"))
    preprocessed_records, preprocessor_report = _preprocess_records(source_records, macros)
    species, species_order = _parse_species_entries(root, preprocessed_records, constants)

    struct_count = sum(1 for record in species.values() if record.get("initializer_kind") == "struct")
    macro_count = sum(1 for record in species.values() if record.get("initializer_kind") == "macro_call")
    core_stats_count = sum(1 for record in species.values() if len(record.get("base_stats", {})) == len(STAT_FIELDS))
    warning_count = len(preprocessor_report["warnings"])
    warning_count += sum(len(record.get("warnings", [])) for record in species.values())
    unsupported_field_count = sum(len(record.get("unsupported_fields", [])) for record in species.values())

    return {
        "schema_version": 1,
        "source": {
            "project": "pokeemerald-expansion",
            "species_info": "src/data/pokemon/species_info.h",
            "included_species_info_files": sorted(
                {
                    to_project_path(record.path.relative_to(root))
                    for record in source_records
                    if "src\\data\\pokemon\\species_info" in str(record.path) or "src/data/pokemon/species_info" in str(record.path)
                }
            ),
            "constants": [
                "include/constants/species.h",
                "include/constants/pokemon.h",
                "include/constants/abilities.h",
                "include/constants/items.h",
                "include/constants/cries.h",
                "include/constants/pokedex.h",
            ],
            "config": [
                "include/config/general.h",
                "include/config/battle.h",
                "include/config/overworld.h",
                "include/config/pokemon.h",
                "include/config/species_enabled.h",
            ],
            "preprocessor": preprocessor_report,
        },
        "constants": {
            "species": _export_constant_group(constants["species"], "SPECIES_"),
            "types": _export_constant_group(constants["types"], "TYPE_"),
            "growth_rates": _export_constant_group(constants["growth_rates"], "GROWTH_"),
            "body_colors": _export_constant_group(constants["body_colors"], "BODY_COLOR_"),
            "abilities": _export_constant_group(constants["abilities"], "ABILITY_"),
            "items": _export_constant_group(constants["items"], "ITEM_"),
            "cries": _export_constant_group(constants["cries"], "CRY_"),
            "national_dex": _export_constant_group(constants["national_dex"], "NATIONAL_DEX_"),
            "egg_groups": _export_constant_group(constants["egg_groups"], "EGG_GROUP_"),
            "genders": _export_constant_group(constants["genders"], "MON_"),
        },
        "species_order": species_order,
        "species": species,
        "stats": {
            "species_count": len(species),
            "struct_initializer_count": struct_count,
            "macro_initializer_count": macro_count,
            "species_with_core_stats": core_stats_count,
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

    exported = export_species(source_root)
    species_output = output_root / "pokemon" / "species.json"
    write_json(species_output, exported)

    stats = exported["stats"]
    manifest_entry = {
        "category": "species",
        "path": to_project_path(species_output),
        "species_count": stats["species_count"],
        "struct_initializer_count": stats["struct_initializer_count"],
        "macro_initializer_count": stats["macro_initializer_count"],
        "species_with_core_stats": stats["species_with_core_stats"],
        "warning_count": stats["warning_count"],
    }
    write_manifest(
        output_root / "import_manifest.json",
        exported_pokemon=[manifest_entry],
        generator="tools/importer/export_species.py",
    )

    print(json.dumps({
        "exported": manifest_entry,
        "preprocessor_decision_count": stats["preprocessor_decision_count"],
        "unsupported_field_count": stats["unsupported_field_count"],
    }, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
