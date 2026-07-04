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
from text_codec import display_text_from_source, encode_source_text, load_charmap


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

TEXT_ENCODING_TRACE = {
    "source": [
        "tools/preproc/charmap.cpp:CharmapReader",
        "tools/preproc/string_parser.cpp:StringParser::ParseString",
        "tools/preproc/c_file.cpp:CFile::TryConvertString",
    ],
    "godot_status": "utf8_display_text_with_source_charmap_byte_validation",
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


def read_script_file(path, source_file=None):
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
                    "source_file": source_file if source_file is not None else str(path),
                    "instructions": [],
                }
                order.append(current_label)
            continue

        instruction = parse_instruction(code, line_number)
        if instruction is None:
            continue
        if source_file is not None:
            instruction["source_file"] = source_file
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


def build_export_from_files(root, script_paths, source):
    charmap_path = root / "charmap.txt"
    charmap = load_charmap(charmap_path)

    labels = {}
    order = []
    orphan_instructions = []
    for script_path in script_paths:
        if not script_path.exists():
            raise FileNotFoundError(script_path)
        source_file = to_project_path(script_path.relative_to(root))
        file_labels, file_order, file_orphans = read_script_file(script_path, source_file)
        for label in file_order:
            if label in labels:
                raise ValueError("Duplicate event script label: {}".format(label))
            labels[label] = file_labels[label]
            order.append(label)
        orphan_instructions.extend(file_orphans)

    op_counts = Counter()
    unsupported_preview_ops = Counter()
    text_encoding_status_counts = Counter()
    text_encoding_warning_count = 0
    text_source_byte_count = 0
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
            "source_file": record.get("source_file", ""),
            "instruction_count": len(instructions),
        }

        if kind == "text":
            raw_parts = [
                instruction["args"][0]
                for instruction in instructions
                if instruction["op"] == ".string" and instruction["args"]
            ]
            raw_text = "".join(raw_parts)
            encoding = encode_source_text(raw_text, charmap)
            text_encoding_status_counts[encoding["status"]] += 1
            text_encoding_warning_count += len(encoding["warnings"])
            text_source_byte_count += encoding["byte_count"]
            texts[label] = {
                "label": label,
                "line": record["line"],
                "source_file": record.get("source_file", ""),
                "raw_text": raw_text,
                "display_text": display_text_from_source(raw_text),
                "encoding": encoding,
            }
            continue

        script_record = {
            "label": label,
            "kind": kind,
            "line": record["line"],
            "source_file": record.get("source_file", ""),
            "instructions": instructions,
            "msgboxes": first_msgboxes(instructions),
            "branch_targets": branch_targets(instructions),
        }
        if kind == "movement":
            movements[label] = script_record
        else:
            scripts[label] = script_record

    source_record = {
        "project": "pokeemerald-expansion",
        "charmap": to_project_path(charmap_path.relative_to(root)),
        "encoding": "utf-8",
        "text_encoding_trace": TEXT_ENCODING_TRACE,
    }
    source_record.update(source)
    return {
        "schema_version": 1,
        "source": source_record,
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
            "encoded_text_count": sum(text_encoding_status_counts.values()),
            "text_source_byte_count": text_source_byte_count,
            "charmap_warning_count": text_encoding_warning_count,
            "charmap_status_counts": dict(sorted(text_encoding_status_counts.items())),
            "orphan_instruction_count": len(orphan_instructions),
            "op_counts": dict(sorted(op_counts.items())),
        },
    }


def build_export(root, map_folder):
    script_path = root / "data/maps" / map_folder / "scripts.inc"
    source = {
        "map_folder": map_folder,
        "map_script": to_project_path(script_path.relative_to(root)),
    }
    return build_export_from_files(root, [script_path], source)


def build_shared_export(root, shared_name, include_scripts):
    script_paths = [root / include_script for include_script in include_scripts]
    source = {
        "scope": "shared",
        "name": shared_name,
        "script_files": [
            to_project_path(script_path.relative_to(root))
            for script_path in script_paths
        ],
    }
    return build_export_from_files(root, script_paths, source)


def _is_preview_supported_op(op):
    return op in PREVIEW_SUPPORTED_OPS


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, help="JSON config with source and output roots.")
    parser.add_argument("--source", type=Path, help="pokeemerald-expansion source root.")
    parser.add_argument("--map", default=None, help="Map folder name to export.")
    parser.add_argument("--shared-name", help="Shared script bundle name to export.")
    parser.add_argument(
        "--include-script",
        action="append",
        default=[],
        help="Source-relative .inc file to include in a shared script bundle.",
    )
    parser.add_argument("--output-root", type=Path, help="Generated data output root.")
    args = parser.parse_args(argv)

    config = load_config(args.config)
    source_root = args.source or Path(config.get("source_root", ""))
    map_folder = args.map or config.get("first_slice_map", "LittlerootTown")
    output_root = args.output_root or Path(config.get("generated_data_root", "data/generated"))

    if args.shared_name:
        if not args.include_script:
            parser.error("--shared-name requires at least one --include-script")
        exported = build_shared_export(source_root, args.shared_name, [Path(path) for path in args.include_script])
        script_slug = camel_to_snake(args.shared_name)
        script_output = output_root / "scripts" / "{}.json".format(script_slug)
        manifest_entry = {
            "scope": "shared",
            "name": args.shared_name,
            "path": to_project_path(script_output),
            "source_files": exported["source"]["script_files"],
            "script_count": exported["stats"]["script_count"],
            "movement_count": exported["stats"]["movement_count"],
            "text_count": exported["stats"]["text_count"],
            "charmap_warning_count": exported["stats"]["charmap_warning_count"],
        }
    else:
        exported = build_export(source_root, map_folder)
        script_slug = camel_to_snake(map_folder)
        script_output = output_root / "scripts" / "{}.json".format(script_slug)
        manifest_entry = {
            "map": map_folder,
            "path": to_project_path(script_output),
            "script_count": exported["stats"]["script_count"],
            "movement_count": exported["stats"]["movement_count"],
            "text_count": exported["stats"]["text_count"],
            "charmap_warning_count": exported["stats"]["charmap_warning_count"],
        }
    write_json(script_output, exported)

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
