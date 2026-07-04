#!/usr/bin/env python3
"""Export battle string ids and battle-message text into generated JSON."""

import argparse
import json
import re
import sys
from collections import Counter
from pathlib import Path

from export_map import write_json, write_manifest
from source_probe import load_config, to_project_path
from text_codec import display_text_from_source, encode_source_text, load_charmap


BATTLE_STRING_IDS_PATH = Path("include/constants/battle_string_ids.h")
BATTLE_MESSAGE_PATH = Path("src/battle_message.c")
BATTLE_STRING_TABLE_NAME = "gBattleStringsTable"
BATTLE_STRINGS_CATEGORY = "battle_strings"

TEXT_DECL_RE = re.compile(
    r"(?:(?:static)\s+)?const\s+u8\s+([A-Za-z_][A-Za-z0-9_]*)\s*\[\s*\]\s*=\s*",
    re.MULTILINE,
)
STRING_ID_RE = re.compile(r"\bSTRINGID_[A-Za-z0-9_]+\b")
TOKEN_RE = re.compile(r"\{([^{}]+)\}")
ESCAPE_RE = re.compile(r"\\([nlprt\"\\])")

KNOWN_BRACED_CONTROLS = {
    "ACCENT",
    "BACKGROUND",
    "BLINK",
    "BUFFER",
    "CLEAR",
    "CLEAR_TO",
    "COLOR",
    "COLOR_HIGHLIGHT_SHADOW",
    "COLOR_HIGHLIGHT_SHADOW_SKIP",
    "DYNAMIC",
    "ESCAPE",
    "EXT_CTRL_CODE_BEGIN",
    "FONT",
    "FONT_FEMALE",
    "FONT_MALE",
    "FONT_NORMAL",
    "HIGHLIGHT",
    "LEFT_ARROW",
    "PALETTE",
    "PAUSE",
    "PAUSE_UNTIL_PRESS",
    "PLAY_BGM",
    "PLAY_SE",
    "RIGHT_ARROW",
    "SHADOW",
    "SKIP",
    "TEXT_COLORS",
    "UP_ARROW",
    "WAIT_BUTTON",
    "WAIT_SE",
}
AUDIO_CONTROL_PREFIXES = {"PLAY_SE", "WAIT_SE", "PLAY_BGM", "PLAY_FANFARE", "STOP_BGM", "FADE_BGM"}
UI_TEXT_LABELS = [
    "gText_WhatWillPkmnDo",
    "gText_WhatWillPkmnDo2",
    "gText_WhatWillWallyDo",
    "gText_BattleMenu",
    "gText_SafariZoneMenu",
    "gText_SafariZoneMenuFrlg",
    "gText_MoveInterfacePP",
    "gText_MoveInterfaceType",
    "gText_MoveInterfacePpType",
    "gText_MoveInterfaceDynamicColors",
    "gText_BattleYesNoChoice",
    "gText_BattleSwitchWhich",
    "gText_BattleSwitchWhich2",
    "gText_BattleSwitchWhich3",
    "gText_BattleSwitchWhich4",
    "gText_BattleSwitchWhich5",
    "gText_PlayerMon1Name",
    "gText_OpponentMon1Name",
    "gText_Judgment",
]
BATTLE_TEXT_BUFF_FAMILIES = [
    {
        "source_symbol": "B_BUFF_STRING",
        "category": "battle_string",
        "semantic_tags": ["battle_string"],
        "runtime_source": "src/battle_message.c:ExpandBattleTextBuffPlaceholders",
    },
    {
        "source_symbol": "B_BUFF_NUMBER",
        "category": "number",
        "semantic_tags": ["number"],
        "runtime_source": "src/battle_message.c:ExpandBattleTextBuffPlaceholders",
    },
    {
        "source_symbol": "B_BUFF_MOVE",
        "category": "move",
        "semantic_tags": ["move"],
        "runtime_source": "src/battle_message.c:ExpandBattleTextBuffPlaceholders",
    },
    {
        "source_symbol": "B_BUFF_TYPE",
        "category": "type",
        "semantic_tags": ["type"],
        "runtime_source": "src/battle_message.c:ExpandBattleTextBuffPlaceholders",
    },
    {
        "source_symbol": "B_BUFF_MON_NICK_WITH_PREFIX",
        "category": "pokemon_nickname",
        "semantic_tags": ["pokemon_nickname", "side"],
        "runtime_source": "src/battle_message.c:ExpandBattleTextBuffPlaceholders",
    },
    {
        "source_symbol": "B_BUFF_MON_NICK_WITH_PREFIX_LOWER",
        "category": "pokemon_nickname",
        "semantic_tags": ["pokemon_nickname", "side"],
        "runtime_source": "src/battle_message.c:ExpandBattleTextBuffPlaceholders",
    },
    {
        "source_symbol": "B_BUFF_STAT",
        "category": "stat",
        "semantic_tags": ["stat"],
        "runtime_source": "src/battle_message.c:ExpandBattleTextBuffPlaceholders",
    },
    {
        "source_symbol": "B_BUFF_SPECIES",
        "category": "species",
        "semantic_tags": ["pokemon_species"],
        "runtime_source": "src/battle_message.c:ExpandBattleTextBuffPlaceholders",
    },
    {
        "source_symbol": "B_BUFF_MON_NICK",
        "category": "pokemon_nickname",
        "semantic_tags": ["pokemon_nickname", "side"],
        "runtime_source": "src/battle_message.c:ExpandBattleTextBuffPlaceholders",
    },
    {
        "source_symbol": "B_BUFF_NEGATIVE_FLAVOR",
        "category": "flavor",
        "semantic_tags": ["pokeblock", "flavor"],
        "runtime_source": "src/battle_message.c:ExpandBattleTextBuffPlaceholders",
    },
    {
        "source_symbol": "B_BUFF_ABILITY",
        "category": "ability",
        "semantic_tags": ["ability"],
        "runtime_source": "src/battle_message.c:ExpandBattleTextBuffPlaceholders",
    },
    {
        "source_symbol": "B_BUFF_ITEM",
        "category": "item",
        "semantic_tags": ["item"],
        "runtime_source": "src/battle_message.c:ExpandBattleTextBuffPlaceholders",
    },
]


def _strip_c_comments(text):
    output = []
    index = 0
    in_string = False
    in_char = False
    escaped = False
    while index < len(text):
        char = text[index]
        next_char = text[index + 1] if index + 1 < len(text) else ""

        if escaped:
            output.append(char)
            escaped = False
            index += 1
            continue

        if in_string:
            output.append(char)
            if char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
            index += 1
            continue

        if in_char:
            output.append(char)
            if char == "\\":
                escaped = True
            elif char == "'":
                in_char = False
            index += 1
            continue

        if char == '"':
            in_string = True
            output.append(char)
            index += 1
            continue
        if char == "'":
            in_char = True
            output.append(char)
            index += 1
            continue
        if char == "/" and next_char == "/":
            while index < len(text) and text[index] != "\n":
                index += 1
            continue
        if char == "/" and next_char == "*":
            index += 2
            while index + 1 < len(text) and not (text[index] == "*" and text[index + 1] == "/"):
                if text[index] == "\n":
                    output.append("\n")
                index += 1
            index += 2
            continue

        output.append(char)
        index += 1
    return "".join(output)


def _line_number_at(text, offset):
    return text.count("\n", 0, offset) + 1


def _find_matching(text, open_index, open_char, close_char):
    depth = 0
    in_string = False
    in_char = False
    escaped = False
    for index in range(open_index, len(text)):
        char = text[index]
        if escaped:
            escaped = False
            continue
        if in_string:
            if char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
            continue
        if in_char:
            if char == "\\":
                escaped = True
            elif char == "'":
                in_char = False
            continue
        if char == '"':
            in_string = True
            continue
        if char == "'":
            in_char = True
            continue
        if char == open_char:
            depth += 1
            continue
        if char == close_char:
            depth -= 1
            if depth == 0:
                return index
    return -1


def _skip_ws(text, index):
    while index < len(text) and text[index].isspace():
        index += 1
    return index


def _parse_source_string_token(token):
    body = token[1:-1]
    chars = []
    index = 0
    while index < len(body):
        char = body[index]
        if char != "\\":
            chars.append(char)
            index += 1
            continue
        if index + 1 >= len(body):
            chars.append("\\")
            index += 1
            continue
        escaped = body[index + 1]
        if escaped == "x":
            hex_digits = []
            scan = index + 2
            while scan < len(body) and body[scan] in "0123456789abcdefABCDEF":
                hex_digits.append(body[scan])
                scan += 1
            if hex_digits:
                try:
                    chars.append(chr(int("".join(hex_digits), 16)))
                except ValueError:
                    chars.append("\\x" + "".join(hex_digits))
                index = scan
                continue
        if escaped in {"n", "l", "p", "r", "t", '"', "\\"}:
            chars.append("\\" + escaped)
        else:
            chars.append("\\" + escaped)
        index += 2
    return "".join(chars)


def _string_literal_parts(expression):
    parts = []
    index = 0
    while index < len(expression):
        if expression[index] != '"':
            index += 1
            continue
        end = index + 1
        escaped = False
        while end < len(expression):
            char = expression[end]
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                end += 1
                break
            end += 1
        parts.append(_parse_source_string_token(expression[index:end]))
        index = end
    return parts


def _extract_macro_text(expression):
    stripped = expression.strip()
    for macro in ["COMPOUND_STRING", "_"]:
        prefix = macro + "("
        if stripped.startswith(prefix):
            open_index = stripped.find("(")
            close_index = _find_matching(stripped, open_index, "(", ")")
            inner = stripped[open_index + 1:close_index] if close_index != -1 else stripped[open_index + 1:]
            parts = _string_literal_parts(inner)
            if parts:
                return "".join(parts)
    parts = _string_literal_parts(stripped)
    return "".join(parts) if parts else None


def parse_string_id_enum(root):
    path = root / BATTLE_STRING_IDS_PATH
    text = path.read_text(encoding="utf-8")
    without_comments = _strip_c_comments(text)
    enum_match = re.search(r"enum\s+StringID\s*\{(.*?)\};", without_comments, re.DOTALL)
    if enum_match is None:
        raise ValueError("enum StringID not found in {}".format(path))

    enum_body = enum_match.group(1)
    records = []
    by_symbol = {}
    by_id = []
    value = 0
    for raw_entry in enum_body.split(","):
        entry = raw_entry.strip()
        if not entry:
            continue
        parts = [part.strip() for part in entry.split("=", 1)]
        symbol = parts[0]
        if not STRING_ID_RE.fullmatch(symbol):
            continue
        if len(parts) == 2:
            value = _eval_simple_int(parts[1], value)
        offset = text.find(symbol)
        line = _line_number_at(text, offset) if offset != -1 else 0
        record = {
            "id": value,
            "symbol": symbol,
            "short_symbol": symbol[len("STRINGID_"):],
            "source": to_project_path(BATTLE_STRING_IDS_PATH),
            "line": line,
            "table_marker": symbol == "STRINGID_TABLE_START",
            "table_backed": False,
        }
        records.append(record)
        by_symbol[symbol] = record
        by_id.append(record)
        value += 1

    return {
        "records": records,
        "by_symbol": by_symbol,
        "by_id": by_id,
    }


def _eval_simple_int(expression, current_value):
    clean = expression.strip()
    if clean.startswith("(") and clean.endswith(")"):
        clean = clean[1:-1].strip()
    try:
        return int(clean, 0)
    except ValueError:
        pass
    if clean.endswith("+ 1") or clean.endswith("+1"):
        lhs = clean.rsplit("+", 1)[0].strip()
        if lhs == "":
            return current_value + 1
    return current_value


def parse_text_declarations(root, charmap):
    path = root / BATTLE_MESSAGE_PATH
    text = path.read_text(encoding="utf-8")
    records = {}
    for match in TEXT_DECL_RE.finditer(text):
        label = match.group(1)
        expr_start = _skip_ws(text, match.end())
        statement_end = _find_statement_end(text, expr_start)
        if statement_end == -1:
            continue
        expression = text[expr_start:statement_end]
        raw_text = _extract_macro_text(expression)
        if raw_text is None:
            continue
        line = _line_number_at(text, match.start())
        records[label] = build_text_record(
            label,
            raw_text,
            BATTLE_MESSAGE_PATH,
            line,
            charmap,
            record_type="declared_text",
            expression=expression.strip(),
        )
    return records


def _find_statement_end(text, start):
    in_string = False
    in_char = False
    escaped = False
    paren_depth = 0
    brace_depth = 0
    bracket_depth = 0
    for index in range(start, len(text)):
        char = text[index]
        if escaped:
            escaped = False
            continue
        if in_string:
            if char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
            continue
        if in_char:
            if char == "\\":
                escaped = True
            elif char == "'":
                in_char = False
            continue
        if char == '"':
            in_string = True
            continue
        if char == "'":
            in_char = True
            continue
        if char == "(":
            paren_depth += 1
            continue
        if char == ")":
            paren_depth -= 1
            continue
        if char == "{":
            brace_depth += 1
            continue
        if char == "}":
            brace_depth -= 1
            continue
        if char == "[":
            bracket_depth += 1
            continue
        if char == "]":
            bracket_depth -= 1
            continue
        if char == ";" and paren_depth == 0 and brace_depth == 0 and bracket_depth == 0:
            return index
    return -1


def parse_battle_string_table(root, string_id_records, text_records, charmap):
    path = root / BATTLE_MESSAGE_PATH
    text = path.read_text(encoding="utf-8")
    parse_text = _strip_c_comments(text)
    table_start = parse_text.find(BATTLE_STRING_TABLE_NAME)
    if table_start == -1:
        raise ValueError("{} not found in {}".format(BATTLE_STRING_TABLE_NAME, path))
    open_brace = parse_text.find("{", table_start)
    close_brace = _find_matching(parse_text, open_brace, "{", "}")
    if open_brace == -1 or close_brace == -1:
        raise ValueError("{} initializer braces not found".format(BATTLE_STRING_TABLE_NAME))

    body = parse_text[open_brace + 1:close_brace]
    entries = _split_top_level_commas(body)
    table = {}
    unsupported = []
    for entry in entries:
        stripped = entry.strip()
        if not stripped:
            continue
        match = re.match(r"\[\s*(STRINGID_[A-Za-z0-9_]+)\s*\]\s*=\s*(.+)$", stripped, re.DOTALL)
        if match is None:
            unsupported.append({
                "kind": "unsupported_table_entry",
                "raw": stripped[:180],
            })
            continue
        symbol, expression = match.groups()
        relative_offset = body.find(entry)
        line = _line_number_at(parse_text, open_brace + 1 + relative_offset) if relative_offset != -1 else 0
        record = _build_table_record(
            symbol,
            expression.strip(),
            text_records,
            BATTLE_MESSAGE_PATH,
            line,
            charmap,
        )
        enum_record = string_id_records.get(symbol)
        if enum_record:
            record["id"] = int(enum_record.get("id", -1))
            enum_record["table_backed"] = True
            enum_record["table_line"] = line
        table[symbol] = record

    return table, unsupported


def _split_top_level_commas(text):
    parts = []
    start = 0
    in_string = False
    in_char = False
    escaped = False
    paren_depth = 0
    brace_depth = 0
    bracket_depth = 0
    for index, char in enumerate(text):
        if escaped:
            escaped = False
            continue
        if in_string:
            if char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
            continue
        if in_char:
            if char == "\\":
                escaped = True
            elif char == "'":
                in_char = False
            continue
        if char == '"':
            in_string = True
            continue
        if char == "'":
            in_char = True
            continue
        if char == "(":
            paren_depth += 1
            continue
        if char == ")":
            paren_depth -= 1
            continue
        if char == "{":
            brace_depth += 1
            continue
        if char == "}":
            brace_depth -= 1
            continue
        if char == "[":
            bracket_depth += 1
            continue
        if char == "]":
            bracket_depth -= 1
            continue
        if char == "," and paren_depth == 0 and brace_depth == 0 and bracket_depth == 0:
            parts.append(text[start:index])
            start = index + 1
    parts.append(text[start:])
    return parts


def _build_table_record(symbol, expression, text_records, source_path, line, charmap):
    raw_text = _extract_macro_text(expression)
    if raw_text is not None:
        record = build_text_record(
            symbol,
            raw_text,
            source_path,
            line,
            charmap,
            record_type="battle_string_table",
            expression=expression,
        )
        record["symbol"] = symbol
        record["table_expression_kind"] = "inline_text"
        return record

    label_match = re.match(r"^([A-Za-z_][A-Za-z0-9_]*)$", expression)
    if label_match:
        text_label = label_match.group(1)
        linked = text_records.get(text_label, {})
        record = {
            "symbol": symbol,
            "label": symbol,
            "record_type": "battle_string_table",
            "source": to_project_path(source_path),
            "line": line,
            "table_expression": expression,
            "table_expression_kind": "text_label",
            "text_label": text_label,
            "status": "ok" if linked else "unresolved_text_label",
        }
        if linked:
            for key in [
                "source_text",
                "display_text",
                "encoding",
                "placeholders",
                "text_controls",
                "unsupported_tokens",
                "metadata_only",
                "audio_cues",
            ]:
                record[key] = linked.get(key, [] if key.endswith("s") else "")
        return record

    return {
        "symbol": symbol,
        "label": symbol,
        "record_type": "battle_string_table",
        "source": to_project_path(source_path),
        "line": line,
        "table_expression": expression,
        "table_expression_kind": "unsupported_expression",
        "status": "unsupported_expression",
        "unsupported": [{
            "reason": "unsupported_battle_string_expression",
            "expression": expression,
        }],
    }


def build_text_record(label, raw_text, source_path, line, charmap, record_type, expression=""):
    encoding = encode_source_text(raw_text, charmap)
    controls, placeholders, unsupported_tokens, metadata_only, audio_cues = analyze_text_controls(raw_text)
    return {
        "label": label,
        "record_type": record_type,
        "source": to_project_path(source_path),
        "line": line,
        "source_text": raw_text,
        "display_text": display_text_from_source(raw_text),
        "encoding": encoding,
        "placeholders": placeholders,
        "text_controls": controls,
        "unsupported_tokens": unsupported_tokens,
        "metadata_only": metadata_only,
        "audio_cues": audio_cues,
        "status": "partial" if encoding.get("warnings") or unsupported_tokens else "ok",
        "expression": expression,
    }


def analyze_text_controls(raw_text):
    controls = []
    placeholders = []
    unsupported = []
    metadata_only = []
    audio_cues = []
    for match in ESCAPE_RE.finditer(raw_text):
        escaped = match.group(1)
        kind = {
            "n": "newline",
            "l": "line_feed",
            "p": "paragraph",
            "r": "carriage_return",
            "t": "tab",
            '"': "escaped_quote",
            "\\": "escaped_backslash",
        }.get(escaped, "escape")
        controls.append({
            "kind": kind,
            "token": "\\" + escaped,
            "offset": match.start(),
            "status": "ok",
        })

    for match in TOKEN_RE.finditer(raw_text):
        token_content = match.group(1).strip()
        parts = token_content.split()
        command = parts[0] if parts else ""
        token = "{" + token_content + "}"
        category = classify_placeholder(command)
        semantic_tags = semantic_tags_for_placeholder(command, category)
        control = {
            "kind": "braced",
            "token": token,
            "command": command,
            "args": parts[1:],
            "offset": match.start(),
            "category": category,
            "semantic_tags": semantic_tags,
            "status": "ok",
        }
        if _is_audio_control(command):
            control["status"] = "metadata_only"
            metadata_only.append({
                "kind": "audio",
                "token": token,
                "command": command,
                "args": parts[1:],
                "offset": match.start(),
                "unsupported_reason": "audio_playback_deferred",
            })
            audio_cues.append({
                "token": token,
                "command": command,
                "args": parts[1:],
                "offset": match.start(),
                "playback_status": "metadata_only",
            })
        elif category == "unknown":
            control["status"] = "unsupported_token"
            unsupported.append({
                "token": token,
                "command": command,
                "offset": match.start(),
                "unsupported_reason": "unknown_battle_text_token",
            })
        controls.append(control)

        if category != "text_control" and category != "unknown":
            placeholders.append({
                "token": command,
                "raw": token,
                "offset": match.start(),
                "category": category,
                "semantic_tags": semantic_tags,
            })

    return controls, placeholders, unsupported, metadata_only, audio_cues


def _is_audio_control(command):
    return command in AUDIO_CONTROL_PREFIXES


def classify_placeholder(command):
    if command == "":
        return "unknown"
    if command.startswith("B_"):
        return _classify_battle_placeholder(command)
    if command == "POKEBLOCK":
        return "item"
    if command.startswith("STR_VAR_") or command in {"PLAYER", "RIVAL", "KUN"}:
        return "string_var"
    if command in KNOWN_BRACED_CONTROLS:
        return "text_control"
    if command.startswith("DYNAMIC_COLOR"):
        return "text_control"
    if command.startswith("SE_") or command.startswith("MUS_"):
        return "audio_symbol"
    return "unknown"


def _classify_battle_placeholder(command):
    if "MOVE" in command:
        return "move"
    if "ITEM" in command:
        return "item"
    if "ABILITY" in command:
        return "ability"
    if "TYPE" in command:
        return "type"
    if "STAT" in command:
        return "stat"
    if "TEAM" in command or "SIDE" in command or "OPPONENT" in command or "PARTNER" in command:
        return "side"
    if "TRAINER" in command:
        return "trainer"
    if "MON" in command or "PKMN" in command or "NAME" in command:
        return "pokemon_nickname"
    if command.startswith("B_ATK"):
        return "attacker"
    if command.startswith("B_DEF"):
        return "target"
    if command.startswith("B_SCR"):
        return "scripting"
    if command.startswith("B_EFF"):
        return "effect_battler"
    if command.startswith("B_BUFF"):
        return "battle_buffer"
    if command == "B_PLAYER_NAME":
        return "player"
    return "battle_placeholder"


def semantic_tags_for_placeholder(command, category):
    tags = []
    if category not in {"", "text_control", "unknown"}:
        tags.append(category)
    if command.startswith("B_ATK"):
        tags.append("attacker")
    if command.startswith("B_DEF"):
        tags.append("target")
    if command.startswith("B_SCR"):
        tags.append("scripting")
    if command.startswith("B_EFF"):
        tags.append("effect_battler")
    if command.startswith("B_BUFF"):
        tags.append("battle_buffer")
    if command in {"B_PLAYER_NAME", "PLAYER"}:
        tags.append("player")
    if "TRAINER" in command:
        tags.append("trainer")
    if "MOVE" in command:
        tags.append("move")
    if "ITEM" in command or command == "POKEBLOCK":
        tags.append("item")
    if "ABILITY" in command:
        tags.append("ability")
    if "STAT" in command:
        tags.append("stat")
    if "TYPE" in command:
        tags.append("type")
    if "SIDE" in command or "TEAM" in command or "OPPONENT" in command or "PARTNER" in command:
        tags.append("side")
    if "NAME" in command or "MON" in command or "PKMN" in command:
        tags.append("pokemon_nickname")
    return sorted(set(tags))


def build_export(root):
    charmap = load_charmap(root / "charmap.txt")
    string_ids = parse_string_id_enum(root)
    text_records = parse_text_declarations(root, charmap)
    table, unsupported_table = parse_battle_string_table(
        root,
        string_ids["by_symbol"],
        text_records,
        charmap,
    )
    by_id = []
    for record in string_ids["by_id"]:
        symbol = record["symbol"]
        table_record = table.get(symbol, {})
        record["table_status"] = StringStatus.table_status(record, table_record)
        by_id.append({
            "id": record["id"],
            "symbol": symbol,
            "table_backed": bool(record.get("table_backed", False)),
            "table_status": record["table_status"],
        })

    ui_texts = {
        label: text_records[label]
        for label in UI_TEXT_LABELS
        if label in text_records
    }
    source_files = {
        to_project_path(BATTLE_STRING_IDS_PATH): _file_record(root, BATTLE_STRING_IDS_PATH),
        to_project_path(BATTLE_MESSAGE_PATH): _file_record(root, BATTLE_MESSAGE_PATH),
        "charmap.txt": _file_record(root, Path("charmap.txt")),
    }
    stats = _build_stats(string_ids, table, text_records, ui_texts, unsupported_table)
    return {
        "schema_version": 1,
        "generated_by": "tools/importer/export_battle_strings.py",
        "source_trace": {
            "string_ids": "include/constants/battle_string_ids.h:enum StringID",
            "battle_strings_table": "src/battle_message.c:gBattleStringsTable",
            "placeholder_runtime": [
                "src/battle_message.c:BattleStringExpandPlaceholders",
                "src/battle_message.c:ExpandBattleTextBuffPlaceholders",
                "src/battle_message.c:BattleStringExpandPlaceholdersToDisplayedString",
            ],
            "text_encoding": [
                "tools/preproc/charmap.cpp:CharmapReader",
                "tools/preproc/string_parser.cpp:StringParser::ParseString",
                "tools/preproc/c_file.cpp:CFile::TryConvertString",
            ],
            "audio_scope": "metadata_only",
        },
        "placeholder_runtime_families": BATTLE_TEXT_BUFF_FAMILIES,
        "source_files": source_files,
        "stats": stats,
        "string_ids": {
            record["symbol"]: record
            for record in string_ids["records"]
        },
        "string_ids_by_id": by_id,
        "battle_strings_table": table,
        "texts": text_records,
        "ui_texts": ui_texts,
        "unsupported": unsupported_table + _unsupported_text_records(text_records, table),
    }


class StringStatus:
    @staticmethod
    def table_status(enum_record, table_record):
        if enum_record["symbol"] == "STRINGID_TABLE_START":
            return "table_marker"
        if enum_record["symbol"] == "STRINGID_COUNT":
            return "enum_count_marker"
        if enum_record["id"] < 8:
            return "controller_or_runtime_string"
        if table_record:
            return StringStatus.record_status(table_record)
        return "missing_table_entry"

    @staticmethod
    def record_status(record):
        return str(record.get("status", "ok"))


def _file_record(root, relative_path):
    path = root / relative_path
    return {
        "path": to_project_path(relative_path),
        "exists": path.exists(),
        "size": path.stat().st_size if path.exists() and path.is_file() else None,
    }


def _unsupported_text_records(text_records, table):
    rows = []
    for record in list(text_records.values()) + list(table.values()):
        unsupported_tokens = record.get("unsupported_tokens", [])
        for item in unsupported_tokens if isinstance(unsupported_tokens, list) else []:
            row = dict(item)
            row["label"] = record.get("label", record.get("symbol", ""))
            rows.append(row)
        if record.get("status") == "unsupported_expression":
            rows.append({
                "label": record.get("label", record.get("symbol", "")),
                "unsupported_reason": "unsupported_battle_string_expression",
                "expression": record.get("table_expression", ""),
            })
    return rows


def _build_stats(string_ids, table, text_records, ui_texts, unsupported_table):
    placeholder_categories = Counter()
    placeholder_semantic_tags = Counter()
    audio_cue_count = 0
    metadata_only_count = 0
    control_count = 0
    unsupported_token_count = 0
    for record in list(text_records.values()) + list(table.values()):
        for placeholder in record.get("placeholders", []):
            placeholder_categories[str(placeholder.get("category", ""))] += 1
            for tag in placeholder.get("semantic_tags", []):
                placeholder_semantic_tags[str(tag)] += 1
        audio_cue_count += len(record.get("audio_cues", []))
        metadata_only_count += len(record.get("metadata_only", []))
        control_count += len(record.get("text_controls", []))
        unsupported_token_count += len(record.get("unsupported_tokens", []))

    return {
        "string_id_count": len(string_ids["records"]),
        "table_entry_count": len(table),
        "declared_text_count": len(text_records),
        "ui_text_count": len(ui_texts),
        "table_backed_string_id_count": sum(1 for record in string_ids["records"] if record.get("table_backed")),
        "controller_or_runtime_string_id_count": 7,
        "table_marker_count": 1,
        "control_token_count": control_count,
        "placeholder_count": sum(placeholder_categories.values()),
        "placeholder_categories": dict(sorted(placeholder_categories.items())),
        "placeholder_semantic_tags": dict(sorted(placeholder_semantic_tags.items())),
        "audio_cue_count": audio_cue_count,
        "metadata_only_count": metadata_only_count,
        "unsupported_table_entry_count": len(unsupported_table),
        "unsupported_token_count": unsupported_token_count,
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

    exported = build_export(source_root)
    output_path = output_root / "battle" / "strings.json"
    write_json(output_path, exported)

    manifest_entry = {
        "category": BATTLE_STRINGS_CATEGORY,
        "path": to_project_path(output_path),
        "string_id_count": exported["stats"]["string_id_count"],
        "table_entry_count": exported["stats"]["table_entry_count"],
        "declared_text_count": exported["stats"]["declared_text_count"],
        "ui_text_count": exported["stats"]["ui_text_count"],
        "audio_status": "metadata_only",
    }
    write_manifest(
        output_root / "import_manifest.json",
        exported_texts=[manifest_entry],
        generator="tools/importer/export_battle_strings.py",
    )

    print(json.dumps({
        "exported": manifest_entry,
        "stats": exported["stats"],
    }, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
