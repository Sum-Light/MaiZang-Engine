#!/usr/bin/env python3
"""Export battle script metadata and move-effect script routing."""

import argparse
import json
import re
import sys
from pathlib import Path

from export_map import write_json, write_manifest
from export_species import ExpressionEvaluator, _find_matching_brace, _split_top_level, _strip_c_comments
from source_probe import load_config, to_project_path


BATTLE_SCRIPT_FILES = [
    Path("data/battle_scripts_1.s"),
    Path("data/battle_scripts_2.s"),
]
BATTLE_SCRIPT_MACROS_PATH = Path("asm/macros/battle_script.inc")
BATTLE_SCRIPT_COMMANDS_HEADER = Path("include/constants/battle_script_commands.h")
BATTLE_SCRIPT_COMMANDS_C = Path("src/battle_script_commands.c")
BATTLE_MOVE_EFFECTS_HEADER = Path("include/constants/battle_move_effects.h")
BATTLE_MOVE_EFFECTS_C = Path("src/data/battle_move_effects.h")

IDENTIFIER_RE = re.compile(r"\b[A-Za-z_][A-Za-z0-9_]*\b")
LABEL_RE = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)(::?)$")
MACRO_RE = re.compile(r"^\s*\.macro\s+([A-Za-z_][A-Za-z0-9_]*)(?:\s+(.*))?$")
TABLE_HANDLER_RE = re.compile(r"\[(B_SCR_OP_[A-Za-z0-9_]+)\]\s*=\s*(Cmd_[A-Za-z0-9_]+)")
MOVE_EFFECT_ENTRY_RE = re.compile(r"\[(EFFECT_[A-Za-z0-9_]+)\]\s*=")


def _project_path(path):
    return path.as_posix()


def _source_location(relative_path, line):
    return {
        "file": _project_path(relative_path),
        "line": int(line),
    }


def _compact_source(value):
    return re.sub(r"\s+", " ", value.strip())


def _strip_asm_comment(line):
    in_string = False
    escaped = False
    for index, char in enumerate(line):
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
        elif char == "@":
            return line[:index]
    return line


def _split_args(value):
    raw = value.strip()
    if not raw:
        return []
    return [_compact_source(part) for part in _split_top_level(raw, ",") if part.strip()]


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


def _parse_enum_records(path, enum_name, prefixes, exact_names=None, macros=None):
    exact_names = set(exact_names or [])
    macros = macros if macros is not None else {}
    text = _strip_c_comments(path.read_text(encoding="utf-8"))
    evaluator = ExpressionEvaluator(macros)
    pattern = re.compile(
        r"enum(?:\s+__attribute__\s*\(\(packed\)\))?\s+%s\s*\{" % re.escape(enum_name)
    )
    match = pattern.search(text)
    if not match:
        return {}, []

    brace_start = text.find("{", match.start())
    brace_end = _find_matching_brace(text, brace_start)
    if brace_start == -1 or brace_end == -1:
        return {}, []

    body = text[brace_start + 1:brace_end]
    current_value = 0
    records = {}
    order = []
    search_start = 0
    for entry in _split_top_level(body, ","):
        item = entry.strip()
        if not item or item.startswith("#"):
            continue
        entry_index = body.find(entry, search_start)
        if entry_index == -1:
            entry_index = search_start
        search_start = entry_index + len(entry)
        name_match = re.match(r"([A-Za-z_][A-Za-z0-9_]*)(?:\s*=\s*(.+))?$", item, re.S)
        if not name_match:
            continue
        symbol = name_match.group(1)
        expression = name_match.group(2)
        if expression is not None:
            value = evaluator.eval_int(expression)
            if value is None:
                value = current_value
        else:
            value = current_value
        macros[symbol] = str(value)
        current_value = value + 1
        if not any(symbol.startswith(prefix) for prefix in prefixes) and symbol not in exact_names:
            continue
        line = text.count("\n", 0, brace_start + 1 + entry_index) + 1
        name = symbol
        for prefix in prefixes:
            if symbol.startswith(prefix):
                name = symbol[len(prefix):].lower()
                break
        records[symbol] = {
            "id": int(value),
            "symbol": symbol,
            "name": name,
            "source": _source_location(path, line),
        }
        order.append(symbol)
    return records, order


def _parse_command_handlers(root):
    path = root / BATTLE_SCRIPT_COMMANDS_C
    handlers = {}
    for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        match = TABLE_HANDLER_RE.search(line)
        if not match:
            continue
        opcode_symbol = match.group(1)
        handlers[opcode_symbol] = {
            "handler": match.group(2),
            "source": _source_location(BATTLE_SCRIPT_COMMANDS_C, line_number),
        }
    return handlers


def _parse_macro_args(args_text):
    args = []
    for raw_arg in _split_args(args_text or ""):
        required = raw_arg.endswith(":req") or ":req" in raw_arg
        default_value = ""
        name_part = raw_arg
        if "=" in name_part:
            name_part, default_value = name_part.split("=", 1)
        if ":" in name_part:
            name_part = name_part.split(":", 1)[0]
        name = name_part.strip()
        if not name:
            continue
        args.append({
            "name": name,
            "raw": raw_arg,
            "required": required,
            "default": _compact_source(default_value) if default_value else "",
        })
    return args


def _parse_encoding(body_lines):
    encoding = []
    for line in body_lines:
        stripped = line.strip()
        match = re.match(r"^(\.(?:byte|2byte|4byte|word))\s+(.+)$", stripped)
        if not match:
            continue
        encoding.append({
            "directive": match.group(1),
            "args": _split_args(match.group(2)),
        })
    return encoding


def _classify_side_effect_tags(name, body_lines):
    text = " ".join([name] + [line.strip() for line in body_lines]).lower()
    tag_keywords = [
        ("control_flow", ["goto", "jump", "call", "return", "end", "branch"]),
        ("wait", ["wait", "pause", "delay"]),
        ("text", ["print", "message", "string", "buff", "textbox"]),
        ("animation", ["animation", "anim", "slide", "visible", "hitanimation", "healthbar", "datahp", "draw", "hide"]),
        ("audio", ["playse", "fanfare", "cry", "sound", "music", "volume"]),
        ("battle_state", ["damage", "stat", "status", "volatile", "weather", "ability", "item", "switch", "faint", "hp", "move", "type", "effect"]),
        ("party", ["party", "mon", "pokemon", "exp", "learn", "level"]),
        ("battle_mode", ["trainer", "safari", "link", "arena", "palace", "battle"]),
    ]
    tags = []
    for tag, keywords in tag_keywords:
        if any(keyword in text for keyword in keywords):
            tags.append(tag)
    return tags


def _parse_command_macros(root):
    path = root / BATTLE_SCRIPT_MACROS_PATH
    lines = path.read_text(encoding="utf-8").splitlines()
    macros = {}
    order = []
    index = 0
    while index < len(lines):
        match = MACRO_RE.match(lines[index])
        if not match:
            index += 1
            continue
        name = match.group(1)
        args_text = match.group(2) or ""
        start_line = index + 1
        body_lines = []
        index += 1
        while index < len(lines):
            if lines[index].strip() == ".endm":
                break
            body_lines.append(lines[index])
            index += 1
        opcode_symbols = []
        for body_line in body_lines:
            for opcode_match in re.finditer(r"\bB_SCR_OP_[A-Za-z0-9_]+\b", body_line):
                opcode = opcode_match.group(0)
                if opcode not in opcode_symbols:
                    opcode_symbols.append(opcode)
        side_effect_tags = _classify_side_effect_tags(name, body_lines)
        record = {
            "macro": name,
            "args": _parse_macro_args(args_text),
            "source": _source_location(BATTLE_SCRIPT_MACROS_PATH, start_line),
            "opcode_symbol": opcode_symbols[0] if opcode_symbols else "",
            "referenced_opcode_symbols": opcode_symbols,
            "encoding": _parse_encoding(body_lines),
            "side_effect_tags": side_effect_tags,
            "audio_status": "metadata_only" if "audio" in side_effect_tags else "",
            "runtime_status": "pending_vm",
            "raw_body": [_compact_source(line) for line in body_lines if line.strip()],
        }
        macros[name] = record
        order.append(name)
        index += 1
    return macros, order


def _build_command_records(opcode_records, opcode_order, handlers, command_macros):
    macros_by_opcode = {}
    for macro_name, macro_record in command_macros.items():
        opcode_symbol = macro_record.get("opcode_symbol", "")
        if not opcode_symbol:
            continue
        macros_by_opcode.setdefault(opcode_symbol, []).append(macro_name)

    commands = {}
    for opcode_symbol in opcode_order:
        enum_record = opcode_records[opcode_symbol]
        handler_record = handlers.get(opcode_symbol, {})
        macro_names = macros_by_opcode.get(opcode_symbol, [])
        side_effect_tags = []
        for macro_name in macro_names:
            macro_tags = command_macros[macro_name].get("side_effect_tags", [])
            for tag in macro_tags:
                if tag not in side_effect_tags:
                    side_effect_tags.append(tag)
        record = {
            "opcode": int(enum_record.get("id", -1)),
            "symbol": opcode_symbol,
            "name": str(enum_record.get("name", "")),
            "handler": str(handler_record.get("handler", "")),
            "handler_source": handler_record.get("source", {}),
            "enum_source": enum_record.get("source", {}),
            "macro_names": macro_names,
            "primary_macro": macro_names[0] if macro_names else "",
            "side_effect_tags": side_effect_tags,
            "audio_status": "metadata_only" if "audio" in side_effect_tags else "",
            "runtime_status": "pending_vm",
            "unsupported": [{
                "reason": "battle_script_vm_not_implemented",
                "source_opcode": opcode_symbol,
            }],
        }
        commands[opcode_symbol] = record
    return commands


def _parse_script_instruction(line, macro_records, command_records):
    stripped = line.strip()
    if not stripped:
        return {}
    if stripped.startswith("."):
        parts = stripped.split(None, 1)
        directive = parts[0]
        args = _split_args(parts[1]) if len(parts) > 1 else []
        return {
            "kind": "directive",
            "directive": directive,
            "args": args,
            "raw": stripped,
        }

    parts = stripped.split(None, 1)
    macro_name = parts[0]
    args = _split_args(parts[1]) if len(parts) > 1 else []
    macro_record = macro_records.get(macro_name, {})
    if macro_record:
        opcode_symbol = str(macro_record.get("opcode_symbol", ""))
        command_record = command_records.get(opcode_symbol, {})
        return {
            "kind": "command" if opcode_symbol else "macro",
            "macro": macro_name,
            "opcode_symbol": opcode_symbol,
            "opcode": int(command_record.get("opcode", -1)) if command_record else -1,
            "handler": str(command_record.get("handler", "")) if command_record else "",
            "args": args,
            "side_effect_tags": macro_record.get("side_effect_tags", []),
            "audio_status": macro_record.get("audio_status", ""),
            "runtime_status": "pending_vm",
            "raw": stripped,
        }

    return {
        "kind": "statement",
        "statement": macro_name,
        "args": args,
        "raw": stripped,
        "runtime_status": "unclassified",
    }


def _parse_battle_scripts(root, macro_records, command_records):
    scripts = {}
    order = []
    current_label = ""
    label_sources = {}
    for relative_path in BATTLE_SCRIPT_FILES:
        path = root / relative_path
        for line_number, raw_line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
            clean = _strip_asm_comment(raw_line).strip()
            if not clean:
                continue
            label_match = LABEL_RE.match(clean)
            if label_match:
                current_label = label_match.group(1)
                scripts[current_label] = {
                    "label": current_label,
                    "source": _source_location(relative_path, line_number),
                    "global": label_match.group(2) == "::",
                    "instructions": [],
                    "command_macros": [],
                    "referenced_labels": [],
                    "unresolved_label_references": [],
                    "runtime_status": "pending_vm",
                }
                label_sources[current_label] = relative_path
                order.append(current_label)
                continue
            if not current_label:
                continue
            instruction = _parse_script_instruction(clean, macro_records, command_records)
            if not instruction:
                continue
            instruction["source"] = _source_location(relative_path, line_number)
            scripts[current_label]["instructions"].append(instruction)
            macro_name = str(instruction.get("macro", ""))
            if macro_name and macro_name not in scripts[current_label]["command_macros"]:
                scripts[current_label]["command_macros"].append(macro_name)

    label_set = set(scripts.keys())
    for script in scripts.values():
        referenced = []
        unresolved = []
        for instruction in script.get("instructions", []):
            tokens = []
            for arg in instruction.get("args", []):
                tokens.extend(IDENTIFIER_RE.findall(str(arg)))
            if instruction.get("kind") == "directive":
                tokens.extend(IDENTIFIER_RE.findall(str(instruction.get("raw", ""))))
            for token in tokens:
                if token in label_set and token not in referenced:
                    referenced.append(token)
                elif token.startswith("BattleScript_") and token not in label_set and token not in unresolved:
                    unresolved.append(token)
        script["referenced_labels"] = referenced
        script["unresolved_label_references"] = unresolved
        script["instruction_count"] = len(script.get("instructions", []))
        script["command_instruction_count"] = sum(
            1 for instruction in script.get("instructions", []) if instruction.get("kind") == "command"
        )
    for index, label in enumerate(order):
        script = scripts[label]
        next_label = order[index + 1] if index + 1 < len(order) else ""
        script["next_label"] = next_label
        if next_label and _script_can_fall_through(script):
            script["fallthrough_label"] = next_label
        else:
            script["fallthrough_label"] = ""
    return scripts, order


def _script_can_fall_through(script):
    instructions = script.get("instructions", [])
    if not instructions:
        return True
    last = instructions[-1]
    macro_name = str(last.get("macro", ""))
    directive = str(last.get("directive", ""))
    if directive in [".end"]:
        return False
    if macro_name in ["end", "end2", "end3", "return", "goto"]:
        return False
    return True


def _parse_move_effect_table(root):
    path = root / BATTLE_MOVE_EFFECTS_C
    text = _strip_c_comments(path.read_text(encoding="utf-8"))
    table_match = re.search(r"gBattleMoveEffects\s*\[\s*NUM_BATTLE_MOVE_EFFECTS\s*\]\s*=", text)
    if not table_match:
        return {}
    brace_start = text.find("{", table_match.end())
    brace_end = _find_matching_brace(text, brace_start)
    if brace_start == -1 or brace_end == -1:
        return {}
    body = text[brace_start + 1:brace_end]
    entries = {}
    matches = list(MOVE_EFFECT_ENTRY_RE.finditer(body))
    for index, match in enumerate(matches):
        symbol = match.group(1)
        initializer_start = match.end()
        initializer_end = matches[index + 1].start() if index + 1 < len(matches) else len(body)
        initializer = body[initializer_start:initializer_end].strip().rstrip(",").strip()
        fields = {}
        if initializer.startswith("{"):
            close_index = _find_matching_brace(initializer, 0)
            if close_index != -1:
                fields = _parse_designated_field_assignments(initializer[1:close_index])
        line = text.count("\n", 0, brace_start + 1 + match.start()) + 1
        entries[symbol] = {
            "source": _source_location(BATTLE_MOVE_EFFECTS_C, line),
            "raw_initializer": _compact_source(initializer),
            "raw_fields": {field: _compact_source(value) for field, value in fields.items()},
        }
    return entries


def _parse_bool(value):
    raw = _compact_source(value)
    if raw == "TRUE":
        return True
    if raw == "FALSE":
        return False
    return bool(raw)


def _build_move_effect_records(root, script_records):
    macros = {"TRUE": "1", "FALSE": "0", "NULL": "0"}
    effects, effect_order = _parse_enum_records(
        root / BATTLE_MOVE_EFFECTS_HEADER,
        "BattleMoveEffects",
        ["EFFECT_"],
        exact_names=["NUM_BATTLE_MOVE_EFFECTS"],
        macros=macros,
    )
    table_entries = _parse_move_effect_table(root)
    evaluator = ExpressionEvaluator(macros)
    records = {}
    unsupported = []
    for symbol in effect_order:
        if symbol == "NUM_BATTLE_MOVE_EFFECTS":
            continue
        enum_record = effects[symbol]
        table_entry = table_entries.get(symbol, {})
        raw_fields = table_entry.get("raw_fields", {}) if table_entry else {}
        battle_script = str(raw_fields.get("battleScript", ""))
        resolved = bool(battle_script and battle_script in script_records)
        record = {
            "id": int(enum_record.get("id", -1)),
            "symbol": symbol,
            "name": str(enum_record.get("name", "")),
            "enum_source": enum_record.get("source", {}),
            "table_source": table_entry.get("source", {}),
            "raw_fields": raw_fields,
            "battle_script": battle_script,
            "battle_script_resolved": resolved,
            "battle_script_instruction_count": int(script_records.get(battle_script, {}).get("instruction_count", 0)) if resolved else 0,
            "runtime_status": "pending_vm",
            "unsupported": [],
        }
        if "battleTvScore" in raw_fields:
            score = evaluator.eval_int(raw_fields["battleTvScore"])
            record["battle_tv_score"] = int(score) if score is not None else raw_fields["battleTvScore"]
        if "battleFactoryStyle" in raw_fields:
            record["battle_factory_style"] = raw_fields["battleFactoryStyle"]
        if "encourageEncore" in raw_fields:
            record["encourage_encore"] = _parse_bool(raw_fields["encourageEncore"])
        if not table_entry:
            note = {"reason": "missing_gBattleMoveEffects_entry", "effect_symbol": symbol}
            record["unsupported"].append(note)
            unsupported.append(note)
        elif not battle_script:
            note = {"reason": "missing_battle_script_field", "effect_symbol": symbol}
            record["unsupported"].append(note)
            unsupported.append(note)
        elif not resolved:
            note = {
                "reason": "battle_script_label_unresolved",
                "effect_symbol": symbol,
                "battle_script": battle_script,
            }
            record["unsupported"].append(note)
            unsupported.append(note)
        records[symbol] = record
    return {
        "records": records,
        "order": [symbol for symbol in effect_order if symbol != "NUM_BATTLE_MOVE_EFFECTS"],
        "constants": effects,
        "unsupported": unsupported,
    }


def export_battle_scripts(root):
    macros = {"TRUE": "1", "FALSE": "0", "NULL": "0"}
    opcode_records, opcode_order = _parse_enum_records(
        root / BATTLE_SCRIPT_COMMANDS_HEADER,
        "BattleScriptOpcode",
        ["B_SCR_OP_"],
        macros=macros,
    )
    command_macros, macro_order = _parse_command_macros(root)
    handlers = _parse_command_handlers(root)
    commands = _build_command_records(opcode_records, opcode_order, handlers, command_macros)
    scripts, script_order = _parse_battle_scripts(root, command_macros, commands)
    move_effect_data = _build_move_effect_records(root, scripts)

    script_instruction_count = sum(record.get("instruction_count", 0) for record in scripts.values())
    command_instruction_count = sum(record.get("command_instruction_count", 0) for record in scripts.values())
    fallthrough_script_count = sum(1 for record in scripts.values() if record.get("fallthrough_label"))
    unresolved_label_references = [
        {
            "script": script.get("label", ""),
            "labels": script.get("unresolved_label_references", []),
            "source": script.get("source", {}),
        }
        for script in scripts.values()
        if script.get("unresolved_label_references", [])
    ]
    audio_macro_count = sum(1 for record in command_macros.values() if record.get("audio_status") == "metadata_only")
    scripts_output = {
        "schema_version": 1,
        "generated_by": "tools/importer/export_battle_scripts.py",
        "source": {
            "project": "pokeemerald-expansion",
            "script_files": [_project_path(path) for path in BATTLE_SCRIPT_FILES],
            "macro_file": _project_path(BATTLE_SCRIPT_MACROS_PATH),
            "command_header": _project_path(BATTLE_SCRIPT_COMMANDS_HEADER),
            "command_handlers": _project_path(BATTLE_SCRIPT_COMMANDS_C),
        },
        "script_order": script_order,
        "scripts": scripts,
        "command_order": opcode_order,
        "commands": commands,
        "command_macro_order": macro_order,
        "command_macros": command_macros,
        "stats": {
            "script_count": len(scripts),
            "script_instruction_count": script_instruction_count,
            "command_instruction_count": command_instruction_count,
            "directive_instruction_count": script_instruction_count - command_instruction_count,
            "opcode_count": len(opcode_records),
            "command_handler_count": len(handlers),
            "command_macro_count": len(command_macros),
            "audio_metadata_only_command_macro_count": audio_macro_count,
            "pending_vm_opcode_count": len(commands),
            "fallthrough_script_count": fallthrough_script_count,
            "unresolved_label_reference_count": sum(
                len(item.get("labels", [])) for item in unresolved_label_references
            ),
        },
        "unsupported": {
            "runtime": [{
                "reason": "battle_script_vm_not_implemented",
                "opcode_count": len(commands),
                "status": "pending_vm",
            }],
            "unresolved_label_references": unresolved_label_references,
        },
    }

    move_effect_records = move_effect_data["records"]
    missing_script_count = sum(
        1
        for record in move_effect_records.values()
        if record.get("battle_script") and not bool(record.get("battle_script_resolved", False))
    )
    move_effects_output = {
        "schema_version": 1,
        "generated_by": "tools/importer/export_battle_scripts.py",
        "source": {
            "project": "pokeemerald-expansion",
            "effect_header": _project_path(BATTLE_MOVE_EFFECTS_HEADER),
            "effect_table": _project_path(BATTLE_MOVE_EFFECTS_C),
            "script_files": [_project_path(path) for path in BATTLE_SCRIPT_FILES],
        },
        "effect_order": move_effect_data["order"],
        "effects": move_effect_records,
        "constants": move_effect_data["constants"],
        "stats": {
            "effect_count": len(move_effect_records),
            "table_entry_count": sum(1 for record in move_effect_records.values() if record.get("table_source")),
            "unique_battle_script_count": len(set(
                record.get("battle_script", "")
                for record in move_effect_records.values()
                if record.get("battle_script")
            )),
            "resolved_battle_script_count": sum(1 for record in move_effect_records.values() if record.get("battle_script_resolved")),
            "missing_table_entry_count": sum(1 for record in move_effect_records.values() if not record.get("table_source")),
            "missing_battle_script_label_count": missing_script_count,
            "pending_vm_effect_count": len(move_effect_records),
        },
        "unsupported": move_effect_data["unsupported"],
    }
    return scripts_output, move_effects_output


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, help="JSON config with source and output roots.")
    parser.add_argument("--source", type=Path, help="pokeemerald-expansion source root.")
    parser.add_argument("--output-root", type=Path, help="Generated data output root.")
    args = parser.parse_args(argv)

    config = load_config(args.config)
    source_root = args.source or Path(config.get("source_root", ""))
    output_root = args.output_root or Path(config.get("generated_data_root", "data/generated"))

    scripts_output, move_effects_output = export_battle_scripts(source_root)
    scripts_path = output_root / "battle" / "scripts.json"
    move_effects_path = output_root / "battle" / "move_effects.json"
    write_json(scripts_path, scripts_output)
    write_json(move_effects_path, move_effects_output)

    scripts_stats = scripts_output["stats"]
    effects_stats = move_effects_output["stats"]
    manifest_entries = [
        {
            "category": "scripts",
            "path": to_project_path(scripts_path),
            "script_count": scripts_stats["script_count"],
            "opcode_count": scripts_stats["opcode_count"],
            "command_macro_count": scripts_stats["command_macro_count"],
            "pending_vm_opcode_count": scripts_stats["pending_vm_opcode_count"],
            "audio_status": "metadata_only",
        },
        {
            "category": "move_effects",
            "path": to_project_path(move_effects_path),
            "effect_count": effects_stats["effect_count"],
            "resolved_battle_script_count": effects_stats["resolved_battle_script_count"],
            "missing_battle_script_label_count": effects_stats["missing_battle_script_label_count"],
            "runtime_status": "pending_vm",
        },
    ]
    write_manifest(
        output_root / "import_manifest.json",
        exported_battle=manifest_entries,
        generator="tools/importer/export_battle_scripts.py",
    )

    print(json.dumps({
        "exported": manifest_entries,
        "script_instruction_count": scripts_stats["script_instruction_count"],
        "unresolved_label_reference_count": scripts_stats["unresolved_label_reference_count"],
        "move_effect_unsupported_count": len(move_effects_output["unsupported"]),
    }, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
