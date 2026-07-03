#!/usr/bin/env python3
"""Export global data/text strings into generated Godot-friendly JSON."""

import argparse
import json
import re
import sys
from collections import Counter
from pathlib import Path

from export_map import write_json, write_manifest
from source_probe import load_config, to_project_path
from text_codec import display_text_from_source, encode_source_text, load_charmap


LABEL_RE = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)(::|:)$")
C_DEFINE_RE = re.compile(r"^#define\s+([A-Za-z_][A-Za-z0-9_]*)\s+(.+)$")
IGNORED_DIRECTIVES = {
    ".align",
    ".balign",
    ".global",
    ".include",
    ".section",
    ".syntax",
}

TEXT_ENCODING_TRACE = {
    "source": [
        "tools/preproc/charmap.cpp:CharmapReader",
        "tools/preproc/string_parser.cpp:StringParser::ParseString",
        "tools/preproc/c_file.cpp:CFile::TryConvertString",
        "tools/preproc/asm_file.cpp:AsmFile::ReadBraille",
        "asm/macros/event.inc:brailleformat",
        "src/scrcmd.c:ScrCmd_braillemessage",
    ],
    "godot_status": "utf8_display_text_with_source_charmap_byte_validation",
}

TEXT_PREPROCESSOR_SYMBOLS = {
    "IS_FRLG": False,
}

BRAILLE_FORMAT_FIELDS = [
    "win_left",
    "win_top",
    "win_right",
    "win_bottom",
    "text_left",
    "text_top",
]

BRAILLE_CHAR_TOKENS = {
    **{chr(ord("A") + index): "BRAILLE_CHAR_{}".format(chr(ord("A") + index)) for index in range(26)},
    **{chr(ord("a") + index): "BRAILLE_CHAR_{}".format(chr(ord("A") + index)) for index in range(26)},
    **{str(index): "BRAILLE_CHAR_{}".format(index) for index in range(10)},
    " ": "BRAILLE_CHAR_SPACE",
    ",": "BRAILLE_CHAR_COMMA",
    ".": "BRAILLE_CHAR_PERIOD",
    "?": "BRAILLE_CHAR_QUESTION_MARK",
    "!": "BRAILLE_CHAR_EXCL_MARK",
    ":": "BRAILLE_CHAR_COLON",
    ";": "BRAILLE_CHAR_SEMICOLON",
    "-": "BRAILLE_CHAR_HYPHEN",
    "/": "BRAILLE_CHAR_SLASH",
    "(": "BRAILLE_CHAR_PAREN",
    ")": "BRAILLE_CHAR_PAREN",
    "'": "BRAILLE_CHAR_APOSTROPHE",
    "#": "BRAILLE_CHAR_NUMBER",
    "$": "EOS",
}


def strip_comment(line):
    in_string = False
    escaped = False
    for index, char in enumerate(line):
        if escaped:
            escaped = False
            continue
        if char == "\\" and in_string:
            escaped = True
            continue
        if char == '"':
            in_string = not in_string
            continue
        if char == "@" and not in_string:
            return line[:index]
    return line


def parse_string_literal(value):
    value = value.strip()
    if not value.startswith('"'):
        return value

    chars = []
    escaped = False
    for char in value[1:]:
        if escaped:
            chars.append("\\" + char)
            escaped = False
            continue
        if char == "\\":
            escaped = True
            continue
        if char == '"':
            break
        chars.append(char)
    return "".join(chars)


def parse_braille_format(code):
    raw_values = [value.strip() for value in code[len("brailleformat"):].strip().split(",")]
    result = {
        "raw": code,
        "value_count": len(raw_values),
        "values": [],
        "fields": {},
        "warnings": [],
    }
    if len(raw_values) != len(BRAILLE_FORMAT_FIELDS):
        result["warnings"].append("expected 6 brailleformat values")

    for index, raw_value in enumerate(raw_values):
        try:
            value = int(raw_value, 0)
        except ValueError:
            result["warnings"].append("invalid brailleformat integer {!r}".format(raw_value))
            continue

        result["values"].append(value)
        if index < len(BRAILLE_FORMAT_FIELDS):
            result["fields"][BRAILLE_FORMAT_FIELDS[index]] = value

    result["status"] = "partial" if result["warnings"] else "ok"
    return result


def load_character_constants(root):
    constants = {}
    path = root / "include/constants/characters.h"
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = _strip_c_comment(raw_line).strip()
        match = C_DEFINE_RE.match(line)
        if not match:
            continue

        name, value = match.groups()
        token = value.strip().split(None, 1)[0]
        if token in constants:
            constants[name] = constants[token]
            continue

        try:
            constants[name] = int(token, 0)
        except ValueError:
            continue
    return constants


def encode_braille_text(raw_text, constants):
    encoded = []
    warnings = []
    byte_values = []
    in_number = False
    index = 0

    def append_token(token, source, offset):
        value = constants.get(token)
        item = {
            "token": token,
            "source": source,
            "offset": offset,
        }
        if value is None:
            warnings.append("unknown braille constant {!r} at offset {}".format(token, offset))
        else:
            item["value"] = value
            item["hex"] = "{:02X}".format(value)
            byte_values.append(value)
        encoded.append(item)

    while index < len(raw_text):
        char = raw_text[index]
        if char == "\\" and index + 1 < len(raw_text) and raw_text[index + 1] == "n":
            append_token("CHAR_NEWLINE", "\\n", index)
            index += 2
            continue

        token = BRAILLE_CHAR_TOKENS.get(char)
        if token is None:
            warnings.append("character {!r} not valid in braille string at offset {}".format(char, index))
            index += 1
            continue

        if not in_number and char.isdigit():
            in_number = True
            append_token("BRAILLE_CHAR_NUMBER", "number_indicator", index)
        elif in_number and token == "BRAILLE_CHAR_SPACE":
            in_number = False

        append_token(token, char, index)
        index += 1

    return {
        "status": "partial" if warnings else "ok",
        "byte_count": len(byte_values),
        "bytes": byte_values,
        "hex": " ".join("{:02X}".format(byte) for byte in byte_values),
        "terminator_present": 0xFF in byte_values,
        "first_terminator_index": byte_values.index(0xFF) if 0xFF in byte_values else -1,
        "encoded": encoded,
        "warnings": warnings,
    }


def display_braille_text_from_source(raw_text):
    display_text = display_text_from_source(raw_text)
    terminator = display_text.find("$")
    if terminator != -1:
        return display_text[:terminator]
    return display_text


def _strip_c_comment(line):
    return line.split("//", 1)[0].split("/*", 1)[0]


def evaluate_preprocessor_condition(expression):
    expression = expression.strip()
    if expression in TEXT_PREPROCESSOR_SYMBOLS:
        return TEXT_PREPROCESSOR_SYMBOLS[expression], []
    if expression.startswith("!"):
        value, warnings = evaluate_preprocessor_condition(expression[1:])
        return (not value) if value is not None else None, warnings
    if expression in {"0", "FALSE", "false"}:
        return False, []
    if expression in {"1", "TRUE", "true"}:
        return True, []
    return None, ["unsupported preprocessor condition {!r}".format(expression)]


def preprocessor_stack_active(stack):
    return all(frame["active"] for frame in stack)


def handle_preprocessor_directive(code, stack):
    if code.startswith("#if "):
        expression = code[len("#if "):].strip()
        parent_active = preprocessor_stack_active(stack)
        value, warnings = evaluate_preprocessor_condition(expression)
        active_value = bool(value) if value is not None else False
        frame = {
            "expression": expression,
            "condition_value": value,
            "parent_active": parent_active,
            "active": parent_active and active_value,
            "else_seen": False,
            "warnings": warnings,
        }
        stack.append(frame)
        return {
            "directive": "#if",
            "expression": expression,
            "condition_value": value,
            "active": frame["active"],
            "warnings": warnings,
        }

    if code == "#else":
        if not stack:
            return {
                "directive": "#else",
                "active": preprocessor_stack_active(stack),
                "warnings": ["#else without #if"],
            }
        frame = stack[-1]
        frame["else_seen"] = True
        frame["active"] = frame["parent_active"] and not bool(frame["condition_value"])
        return {
            "directive": "#else",
            "expression": frame["expression"],
            "condition_value": frame["condition_value"],
            "active": frame["active"],
            "warnings": [],
        }

    if code == "#endif":
        if not stack:
            return {
                "directive": "#endif",
                "active": preprocessor_stack_active(stack),
                "warnings": ["#endif without #if"],
            }
        frame = stack.pop()
        return {
            "directive": "#endif",
            "expression": frame["expression"],
            "condition_value": frame["condition_value"],
            "active": preprocessor_stack_active(stack),
            "warnings": [],
        }

    return None


def _directive_name(code):
    return code.split(None, 1)[0] if code else ""


def _text_files(root, selected_files):
    text_root = root / "data/text"
    if selected_files:
        return [text_root / value for value in selected_files]
    return sorted(text_root.glob("*.inc"))


def read_text_files(root, selected_files=None):
    labels = {}
    order = []
    files = {}
    report = {
        "duplicate_labels": [],
        "orphan_strings": [],
        "orphan_braille": [],
        "invalid_braille_formats": [],
        "preprocessor_decisions": [],
        "preprocessor_warnings": [],
        "unsupported_directives": [],
    }

    for path in _text_files(root, selected_files or []):
        if not path.exists():
            raise FileNotFoundError(path)

        relative_path = to_project_path(path.relative_to(root))
        files[relative_path] = {
            "path": relative_path,
            "label_count": 0,
            "text_count": 0,
            "braille_count": 0,
            "charmap_warning_count": 0,
            "braille_warning_count": 0,
        }
        current_label = None
        preprocessor_stack = []

        for line_number, raw_line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
            code = strip_comment(raw_line).strip()
            if not code:
                continue

            preprocessor = handle_preprocessor_directive(code, preprocessor_stack)
            if preprocessor is not None:
                decision = {
                    "label": current_label or "",
                    "source": relative_path,
                    "line": line_number,
                    "raw": code,
                    **preprocessor,
                }
                report["preprocessor_decisions"].append(decision)
                if preprocessor["warnings"]:
                    report["preprocessor_warnings"].append(decision)
                continue

            if code.startswith("#"):
                report["preprocessor_warnings"].append({
                    "label": current_label or "",
                    "source": relative_path,
                    "line": line_number,
                    "raw": code,
                    "warnings": ["unsupported preprocessor directive"],
                })
                continue

            if not preprocessor_stack_active(preprocessor_stack):
                continue

            label_match = LABEL_RE.match(code)
            if label_match:
                current_label = label_match.group(1)
                files[relative_path]["label_count"] += 1
                if current_label in labels:
                    report["duplicate_labels"].append({
                        "label": current_label,
                        "source": relative_path,
                        "line": line_number,
                        "first_source": labels[current_label]["source"],
                        "first_line": labels[current_label]["line"],
                    })
                    continue

                labels[current_label] = {
                    "label": current_label,
                    "source": relative_path,
                    "line": line_number,
                    "parts": [],
                    "braille_parts": [],
                    "braille_format": None,
                }
                order.append(current_label)
                continue

            if code.startswith(".string"):
                part = {
                    "line": line_number,
                    "raw": code,
                    "text": parse_string_literal(code[len(".string"):].strip()),
                }
                if current_label is None or current_label not in labels:
                    report["orphan_strings"].append({
                        "source": relative_path,
                        "line": line_number,
                        "raw": code,
                    })
                    continue

                labels[current_label]["parts"].append(part)
                files[relative_path]["text_count"] += 1
                continue

            if code.startswith("brailleformat"):
                braille_format = parse_braille_format(code)
                braille_format["line"] = line_number
                if current_label is None or current_label not in labels:
                    report["orphan_braille"].append({
                        "source": relative_path,
                        "line": line_number,
                        "raw": code,
                    })
                    continue

                labels[current_label]["braille_format"] = braille_format
                if braille_format["warnings"]:
                    report["invalid_braille_formats"].append({
                        "label": current_label,
                        "source": relative_path,
                        "line": line_number,
                        "raw": code,
                        "warnings": braille_format["warnings"],
                    })
                continue

            if code.startswith(".braille"):
                part = {
                    "line": line_number,
                    "raw": code,
                    "text": parse_string_literal(code[len(".braille"):].strip()),
                }
                if current_label is None or current_label not in labels:
                    report["orphan_braille"].append({
                        "source": relative_path,
                        "line": line_number,
                        "raw": code,
                    })
                    continue

                labels[current_label]["braille_parts"].append(part)
                files[relative_path]["braille_count"] += 1
                continue

            directive = _directive_name(code)
            if directive in IGNORED_DIRECTIVES:
                continue

            report["unsupported_directives"].append({
                "label": current_label or "",
                "source": relative_path,
                "line": line_number,
                "raw": code,
            })

        if preprocessor_stack:
            report["preprocessor_warnings"].append({
                "source": relative_path,
                "line": 0,
                "raw": "",
                "warnings": ["unterminated preprocessor conditional"],
            })

    return labels, order, files, report


def build_export(root, selected_files=None):
    charmap_path = root / "charmap.txt"
    charmap = load_charmap(charmap_path)
    character_constants = load_character_constants(root)
    labels, order, files, report = read_text_files(root, selected_files)

    texts = {}
    label_index = {}
    text_encoding_status_counts = Counter()
    braille_encoding_status_counts = Counter()
    text_encoding_warning_count = 0
    braille_encoding_warning_count = 0
    text_source_byte_count = 0
    braille_source_byte_count = 0
    non_text_label_count = 0
    standard_text_count = 0
    braille_text_count = 0

    for label in order:
        record = labels[label]
        raw_parts = [part["text"] for part in record["parts"]]
        braille_parts = [part["text"] for part in record["braille_parts"]]
        if raw_parts:
            kind = "text"
        elif braille_parts:
            kind = "braille"
        else:
            kind = "non_text"

        label_index[label] = {
            "source": record["source"],
            "line": record["line"],
            "part_count": len(raw_parts) if raw_parts else len(braille_parts),
            "kind": kind,
        }

        if raw_parts:
            raw_text = "".join(raw_parts)
            encoding = encode_source_text(raw_text, charmap)
            text_encoding_status_counts[encoding["status"]] += 1
            text_encoding_warning_count += len(encoding["warnings"])
            text_source_byte_count += encoding["byte_count"]
            files[record["source"]]["charmap_warning_count"] += len(encoding["warnings"])
            standard_text_count += 1

            texts[label] = {
                "label": label,
                "kind": "text",
                "source": record["source"],
                "line": record["line"],
                "part_count": len(raw_parts),
                "part_lines": [part["line"] for part in record["parts"]],
                "raw_text": raw_text,
                "display_text": display_text_from_source(raw_text),
                "encoding": encoding,
            }
            continue

        if braille_parts:
            raw_text = "".join(braille_parts)
            encoding = encode_braille_text(raw_text, character_constants)
            format_record = record["braille_format"] or {
                "status": "missing",
                "warnings": ["missing brailleformat header"],
                "values": [],
                "fields": {},
            }
            format_warning_count = len(format_record.get("warnings", []))
            braille_encoding_status_counts[encoding["status"]] += 1
            braille_encoding_warning_count += len(encoding["warnings"]) + format_warning_count
            braille_source_byte_count += encoding["byte_count"]
            files[record["source"]]["braille_warning_count"] += len(encoding["warnings"]) + format_warning_count
            braille_text_count += 1

            format_bytes = format_record.get("values", [])
            texts[label] = {
                "label": label,
                "kind": "braille",
                "source": record["source"],
                "line": record["line"],
                "part_count": len(braille_parts),
                "part_lines": [part["line"] for part in record["braille_parts"]],
                "raw_text": raw_text,
                "display_text": display_braille_text_from_source(raw_text),
                "source_display_text": display_text_from_source(raw_text),
                "source_pointer_skip_bytes": len(BRAILLE_FORMAT_FIELDS),
                "braille_format": format_record,
                "encoding": encoding,
                "source_bytes": {
                    "format_header": format_bytes,
                    "text": encoding["bytes"],
                    "combined": format_bytes + encoding["bytes"],
                },
            }
            continue

        non_text_label_count += 1

    return {
        "schema_version": 1,
        "source": {
            "project": "pokeemerald-expansion",
            "text_root": "data/text",
            "files": sorted(files.keys()),
            "charmap": to_project_path(charmap_path.relative_to(root)),
            "character_constants": "include/constants/characters.h",
            "encoding": "utf-8",
            "preprocessor": {
                "symbols": TEXT_PREPROCESSOR_SYMBOLS,
                "trace": [
                    "include/constants/global.h:65-75",
                ],
            },
            "text_encoding_trace": TEXT_ENCODING_TRACE,
        },
        "files": files,
        "labels": label_index,
        "texts": texts,
        "report": report,
        "stats": {
            "source_file_count": len(files),
            "label_count": len(labels),
            "text_count": len(texts),
            "standard_text_count": standard_text_count,
            "braille_text_count": braille_text_count,
            "non_text_label_count": non_text_label_count,
            "encoded_text_count": sum(text_encoding_status_counts.values()),
            "encoded_braille_text_count": sum(braille_encoding_status_counts.values()),
            "text_source_byte_count": text_source_byte_count,
            "braille_source_byte_count": braille_source_byte_count,
            "charmap_warning_count": text_encoding_warning_count,
            "braille_warning_count": braille_encoding_warning_count,
            "charmap_status_counts": dict(sorted(text_encoding_status_counts.items())),
            "braille_status_counts": dict(sorted(braille_encoding_status_counts.items())),
            "duplicate_label_count": len(report["duplicate_labels"]),
            "orphan_string_count": len(report["orphan_strings"]),
            "orphan_braille_count": len(report["orphan_braille"]),
            "invalid_braille_format_count": len(report["invalid_braille_formats"]),
            "preprocessor_decision_count": len(report["preprocessor_decisions"]),
            "preprocessor_warning_count": len(report["preprocessor_warnings"]),
            "unsupported_directive_count": len(report["unsupported_directives"]),
        },
    }


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, help="JSON config with source and output roots.")
    parser.add_argument("--source", type=Path, help="pokeemerald-expansion source root.")
    parser.add_argument("--output-root", type=Path, help="Generated data output root.")
    parser.add_argument(
        "--file",
        action="append",
        default=[],
        help="Optional data/text relative .inc file to export; may be repeated.",
    )
    args = parser.parse_args(argv)

    config = load_config(args.config)
    source_root = args.source or Path(config.get("source_root", ""))
    output_root = args.output_root or Path(config.get("generated_data_root", "data/generated"))

    exported = build_export(source_root, args.file)
    text_output = output_root / "text" / "global_text.json"
    write_json(text_output, exported)

    manifest_entry = {
        "category": "global",
        "path": to_project_path(text_output),
        "source_file_count": exported["stats"]["source_file_count"],
        "label_count": exported["stats"]["label_count"],
        "text_count": exported["stats"]["text_count"],
        "standard_text_count": exported["stats"]["standard_text_count"],
        "braille_text_count": exported["stats"]["braille_text_count"],
        "charmap_warning_count": exported["stats"]["charmap_warning_count"],
        "braille_warning_count": exported["stats"]["braille_warning_count"],
    }
    write_manifest(
        output_root / "import_manifest.json",
        exported_texts=[manifest_entry],
        generator="tools/importer/export_text.py",
    )

    print(json.dumps({
        "exported": manifest_entry,
        "stats": exported["stats"],
    }, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
