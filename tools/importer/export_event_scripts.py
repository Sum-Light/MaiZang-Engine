#!/usr/bin/env python3
"""Export one map's event scripts into generated Godot-friendly JSON."""

import argparse
import json
import re
import sys
from collections import Counter
from pathlib import Path

from export_map import camel_to_snake, write_json, write_manifest
from source_probe import load_config, to_project_path


LABEL_RE = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)(::|:)$")

PREVIEW_SUPPORTED_OPS = {
    "call",
    "end",
    "goto",
    "lock",
    "lockall",
    "message",
    "msgbox",
    "release",
    "releaseall",
    "return",
}

MOVEMENT_TERMINATORS = {"step_end"}

SOURCE_BEHAVIOR_TRACES = {
    "message": {
        "source": [
            "src/scrcmd.c:ScrCmd_message",
            "ShowFieldMessage(msg)",
        ],
        "godot_status": "preview_displays_text_only",
    },
    "msgbox": {
        "source": [
            "data/event_scripts.s:gStdScripts",
            "data/scripts/std_msgbox.inc:Std_MsgboxNPC",
            "data/scripts/std_msgbox.inc:Std_MsgboxSign",
            "data/scripts/std_msgbox.inc:Std_MsgboxDefault",
            "src/scrcmd.c:ScrCmd_message",
        ],
        "godot_status": "preview_resolves_first_msgbox_text_only",
    },
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


def split_args(value):
    args = []
    current = []
    in_string = False
    escaped = False
    for char in value:
        if escaped:
            current.append(char)
            escaped = False
            continue
        if char == "\\" and in_string:
            current.append(char)
            escaped = True
            continue
        if char == '"':
            current.append(char)
            in_string = not in_string
            continue
        if char == "," and not in_string:
            arg = "".join(current).strip()
            if arg:
                args.append(arg)
            current = []
            continue
        current.append(char)

    arg = "".join(current).strip()
    if arg:
        args.append(arg)
    return args


def parse_instruction(code, line_number):
    if not code:
        return None

    if code.startswith(".string"):
        return {
            "op": ".string",
            "args": [parse_string_literal(code[len(".string"):].strip())],
            "line": line_number,
            "raw": code,
        }

    parts = code.split(None, 1)
    op = parts[0]
    args = split_args(parts[1]) if len(parts) > 1 else []
    return {
        "op": op,
        "args": args,
        "line": line_number,
        "raw": code,
    }


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


def display_text(raw_text):
    output = []
    index = 0
    while index < len(raw_text):
        char = raw_text[index]
        if char != "\\":
            output.append(char)
            index += 1
            continue

        index += 1
        if index >= len(raw_text):
            output.append("\\")
            break

        escaped = raw_text[index]
        if escaped == "n" or escaped == "l":
            output.append("\n")
        elif escaped == "p":
            output.append("\n\n")
        elif escaped == "r":
            output.append("\r")
        elif escaped == "t":
            output.append("\t")
        elif escaped == "\\":
            output.append("\\")
        elif escaped == '"':
            output.append('"')
        else:
            output.append("\\" + escaped)
        index += 1

    if output and output[-1] == "$":
        output.pop()
    return "".join(output)


def read_script_file(path):
    labels = {}
    order = []
    current_label = None
    orphan_instructions = []

    for line_number, raw_line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        code = strip_comment(raw_line).strip()
        if not code:
            continue

        label_match = LABEL_RE.match(code)
        if label_match:
            current_label = label_match.group(1)
            if current_label not in labels:
                labels[current_label] = {
                    "label": current_label,
                    "line": line_number,
                    "instructions": [],
                }
                order.append(current_label)
            continue

        instruction = parse_instruction(code, line_number)
        if instruction is None:
            continue
        if current_label is None:
            orphan_instructions.append(instruction)
            continue
        labels[current_label]["instructions"].append(instruction)

    return labels, order, orphan_instructions


def infer_kind(label, instructions):
    ops = [instruction["op"] for instruction in instructions]
    if ".string" in ops:
        return "text"
    if label.endswith("_MapScripts") or any(op.startswith("map_script") for op in ops):
        return "map_script_table"
    if "_Movement_" in label or any(op in MOVEMENT_TERMINATORS for op in ops):
        return "movement"
    return "script"


def first_msgboxes(instructions):
    messages = []
    for instruction in instructions:
        op = instruction["op"]
        if op not in {"msgbox", "message"}:
            continue
        args = instruction["args"]
        if not args:
            continue
        messages.append({
            "op": op,
            "text_label": args[0],
            "mode": args[1] if len(args) > 1 else "",
            "line": instruction["line"],
        })
    return messages


def branch_targets(instructions):
    targets = []
    for instruction in instructions:
        op = instruction["op"]
        args = instruction["args"]
        if op in {"call", "goto"} and args:
            targets.append({
                "op": op,
                "target": args[0],
                "line": instruction["line"],
            })
        elif (op.startswith("call_if_") or op.startswith("goto_if_")) and args:
            targets.append({
                "op": op,
                "target": args[-1],
                "line": instruction["line"],
            })
    return targets


def build_export(root, map_folder):
    script_path = root / "data/maps" / map_folder / "scripts.inc"
    if not script_path.exists():
        raise FileNotFoundError(script_path)

    labels, order, orphan_instructions = read_script_file(script_path)
    op_counts = Counter()
    unsupported_preview_ops = Counter()
    scripts = {}
    movements = {}
    texts = {}
    label_index = {}

    for label in order:
        record = labels[label]
        instructions = record["instructions"]
        kind = infer_kind(label, instructions)
        for instruction in instructions:
            op = instruction["op"]
            if op.startswith("."):
                continue
            op_counts[op] += 1
            if not _is_preview_supported_op(op):
                unsupported_preview_ops[op] += 1

        label_index[label] = {
            "kind": kind,
            "line": record["line"],
            "instruction_count": len(instructions),
        }

        if kind == "text":
            raw_parts = [
                instruction["args"][0]
                for instruction in instructions
                if instruction["op"] == ".string" and instruction["args"]
            ]
            raw_text = "".join(raw_parts)
            texts[label] = {
                "label": label,
                "line": record["line"],
                "raw_text": raw_text,
                "display_text": display_text(raw_text),
            }
            continue

        script_record = {
            "label": label,
            "kind": kind,
            "line": record["line"],
            "instructions": instructions,
            "msgboxes": first_msgboxes(instructions),
            "branch_targets": branch_targets(instructions),
        }
        if kind == "movement":
            movements[label] = script_record
        else:
            scripts[label] = script_record

    return {
        "schema_version": 1,
        "source": {
            "project": "pokeemerald-expansion",
            "map_folder": map_folder,
            "map_script": to_project_path(script_path.relative_to(root)),
            "encoding": "utf-8",
        },
        "labels": label_index,
        "scripts": scripts,
        "movements": movements,
        "texts": texts,
        "runtime_preview": {
            "supported_ops": sorted(PREVIEW_SUPPORTED_OPS),
            "unsupported_op_counts": dict(sorted(unsupported_preview_ops.items())),
            "source_behavior_traces": SOURCE_BEHAVIOR_TRACES,
        },
        "stats": {
            "label_count": len(labels),
            "script_count": len(scripts),
            "movement_count": len(movements),
            "text_count": len(texts),
            "orphan_instruction_count": len(orphan_instructions),
            "op_counts": dict(sorted(op_counts.items())),
        },
    }


def _is_preview_supported_op(op):
    return op in PREVIEW_SUPPORTED_OPS


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, help="JSON config with source and output roots.")
    parser.add_argument("--source", type=Path, help="pokeemerald-expansion source root.")
    parser.add_argument("--map", default=None, help="Map folder name to export.")
    parser.add_argument("--output-root", type=Path, help="Generated data output root.")
    args = parser.parse_args(argv)

    config = load_config(args.config)
    source_root = args.source or Path(config.get("source_root", ""))
    map_folder = args.map or config.get("first_slice_map", "LittlerootTown")
    output_root = args.output_root or Path(config.get("generated_data_root", "data/generated"))

    exported = build_export(source_root, map_folder)
    map_slug = camel_to_snake(map_folder)
    script_output = output_root / "scripts" / "{}.json".format(map_slug)
    write_json(script_output, exported)

    manifest_entry = {
        "map": map_folder,
        "path": to_project_path(script_output),
        "script_count": exported["stats"]["script_count"],
        "movement_count": exported["stats"]["movement_count"],
        "text_count": exported["stats"]["text_count"],
    }
    write_manifest(
        output_root / "import_manifest.json",
        exported_scripts=[manifest_entry],
        generator="tools/importer/export_event_scripts.py",
    )

    print(json.dumps({
        "exported": manifest_entry,
        "stats": exported["stats"],
        "unsupported_preview_ops": exported["runtime_preview"]["unsupported_op_counts"],
    }, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
