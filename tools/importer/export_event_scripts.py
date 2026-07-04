#!/usr/bin/env python3
"""Export map event scripts into generated Godot-friendly JSON."""

import argparse
import json
import re
import sys
from collections import Counter
from pathlib import Path

from export_map import camel_to_snake, discover_map_folders, load_json, write_json, write_manifest
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

GENERATED_BY = "tools/importer/export_event_scripts.py"
SCRIPT_BATCH_REPORT_RELATIVE_PATH = Path("overworld/script_batch_report.json")
SHARED_SCRIPT_BATCH_REPORT_RELATIVE_PATH = Path("overworld/shared_script_batch_report.json")
EXISTING_GROUPED_SHARED_SCRIPT_FILES = {
    Path("data/scripts/movement.inc"),
    Path("data/scripts/players_house.inc"),
    Path("data/scripts/rival_graphics.inc"),
}
EVENT_SCRIPTS_DIRECT_IGNORED_OPS = {".include"}


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


def read_script_file(path, source_file=None, label_filter=None, ignored_ops=None):
    labels = {}
    order = []
    current_label = None
    orphan_instructions = []
    ignored_ops = set(ignored_ops or [])

    for line_number, raw_line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        code = strip_comment(raw_line).strip()
        if not code:
            continue

        label_match = LABEL_RE.match(code)
        if label_match:
            candidate_label = label_match.group(1)
            if label_filter is not None and not label_filter(candidate_label, line_number):
                current_label = None
                continue
            current_label = candidate_label
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
        if instruction["op"] in ignored_ops:
            continue
        if source_file is not None:
            instruction["source_file"] = source_file
        if current_label is None:
            if label_filter is None:
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


def build_export_from_files(root, script_paths, source, label_filter=None, ignored_ops=None):
    charmap_path = root / "charmap.txt"
    charmap = load_charmap(charmap_path)

    labels = {}
    order = []
    orphan_instructions = []
    for script_path in script_paths:
        if not script_path.exists():
            raise FileNotFoundError(script_path)
        source_file = to_project_path(script_path.relative_to(root))
        file_labels, file_order, file_orphans = read_script_file(
            script_path,
            source_file,
            label_filter=label_filter,
            ignored_ops=ignored_ops,
        )
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
    map_path = root / "data/maps" / map_folder / "map.json"
    source = {
        "map_folder": map_folder,
        "map_script": to_project_path(script_path.relative_to(root)),
    }
    if map_path.exists():
        map_data = load_json(map_path)
        source["map_json"] = to_project_path(map_path.relative_to(root))
        source["map_id"] = map_data.get("id")
        source["map_name"] = map_data.get("name")
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


def _last_map_include_line(path):
    last_line = 0
    for line_number, raw_line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        if '.include "data/maps/' in raw_line:
            last_line = line_number
    return last_line


def build_event_scripts_direct_export(root, shared_name="shared_event_scripts_direct"):
    script_path = root / "data/event_scripts.s"
    direct_start_line = _last_map_include_line(script_path) + 1

    def direct_label_filter(_label, line_number):
        return line_number >= direct_start_line

    source = {
        "scope": "shared",
        "name": shared_name,
        "script_files": [to_project_path(script_path.relative_to(root))],
        "label_filter": {
            "kind": "direct_labels_after_map_includes",
            "start_line": direct_start_line,
            "ignored_ops": sorted(EVENT_SCRIPTS_DIRECT_IGNORED_OPS),
        },
    }
    return build_export_from_files(
        root,
        [script_path],
        source,
        label_filter=direct_label_filter,
        ignored_ops=EVENT_SCRIPTS_DIRECT_IGNORED_OPS,
    )


def shared_name_for_script_path(script_path):
    return "shared_{}".format(script_path.stem)


def output_slug_for_script(map_folder, used_slugs):
    base_slug = camel_to_snake(map_folder)
    slug = base_slug
    if slug in used_slugs:
        suffix = 2
        while "{}_{}".format(base_slug, suffix) in used_slugs:
            suffix += 1
        slug = "{}_{}".format(base_slug, suffix)
    used_slugs[slug] = used_slugs.get(slug, 0) + 1
    return base_slug, slug


def manifest_entry_for_map_script(exported, script_output):
    source = exported.get("source", {})
    stats = exported.get("stats", {})
    return {
        "map": source.get("map_folder"),
        "map_id": source.get("map_id"),
        "map_name": source.get("map_name"),
        "path": to_project_path(script_output),
        "source_file": source.get("map_script"),
        "label_count": stats.get("label_count"),
        "script_count": stats.get("script_count"),
        "movement_count": stats.get("movement_count"),
        "text_count": stats.get("text_count"),
        "charmap_warning_count": stats.get("charmap_warning_count"),
        "orphan_instruction_count": stats.get("orphan_instruction_count"),
    }


def manifest_entry_for_shared_script(exported, script_output, shared_name):
    stats = exported.get("stats", {})
    return {
        "scope": "shared",
        "name": shared_name,
        "path": to_project_path(script_output),
        "source_files": exported.get("source", {}).get("script_files", []),
        "label_count": stats.get("label_count"),
        "script_count": stats.get("script_count"),
        "movement_count": stats.get("movement_count"),
        "text_count": stats.get("text_count"),
        "charmap_warning_count": stats.get("charmap_warning_count"),
        "orphan_instruction_count": stats.get("orphan_instruction_count"),
    }


def _sum_counter_dict(total, values):
    for key, value in values.items():
        total[key] += value


def _script_report_row(map_folder, exported, script_output, base_slug, output_slug):
    source = exported.get("source", {})
    stats = exported.get("stats", {})
    runtime_preview = exported.get("runtime_preview", {})
    unsupported_ops = runtime_preview.get("unsupported_op_counts", {})
    return {
        "map_folder": map_folder,
        "map_id": source.get("map_id"),
        "map_name": source.get("map_name"),
        "path": to_project_path(script_output),
        "output_slug": output_slug,
        "base_slug": base_slug,
        "source": {
            "map_json": source.get("map_json"),
            "map_script": source.get("map_script"),
        },
        "label_count": stats.get("label_count", 0),
        "script_count": stats.get("script_count", 0),
        "movement_count": stats.get("movement_count", 0),
        "text_count": stats.get("text_count", 0),
        "encoded_text_count": stats.get("encoded_text_count", 0),
        "text_source_byte_count": stats.get("text_source_byte_count", 0),
        "charmap_warning_count": stats.get("charmap_warning_count", 0),
        "orphan_instruction_count": stats.get("orphan_instruction_count", 0),
        "runtime_preview_unsupported_op_count": sum(
            value for value in unsupported_ops.values() if isinstance(value, int)
        ),
        "op_counts": stats.get("op_counts", {}),
        "unsupported_preview_ops": unsupported_ops,
    }


def _shared_report_row(shared_name, exported, script_output, source_kind):
    source = exported.get("source", {})
    stats = exported.get("stats", {})
    runtime_preview = exported.get("runtime_preview", {})
    unsupported_ops = runtime_preview.get("unsupported_op_counts", {})
    return {
        "name": shared_name,
        "source_kind": source_kind,
        "path": to_project_path(script_output),
        "source": {
            "script_files": source.get("script_files", []),
            "label_filter": source.get("label_filter"),
        },
        "label_count": stats.get("label_count", 0),
        "script_count": stats.get("script_count", 0),
        "movement_count": stats.get("movement_count", 0),
        "text_count": stats.get("text_count", 0),
        "encoded_text_count": stats.get("encoded_text_count", 0),
        "text_source_byte_count": stats.get("text_source_byte_count", 0),
        "charmap_warning_count": stats.get("charmap_warning_count", 0),
        "orphan_instruction_count": stats.get("orphan_instruction_count", 0),
        "runtime_preview_unsupported_op_count": sum(
            value for value in unsupported_ops.values() if isinstance(value, int)
        ),
        "op_counts": stats.get("op_counts", {}),
        "unsupported_preview_ops": unsupported_ops,
    }


def build_map_script_batch_export(source_root, output_root, write_outputs=False):
    map_folders = discover_map_folders(source_root)
    script_folders = [
        map_folder for map_folder in map_folders
        if (source_root / "data/maps" / map_folder / "scripts.inc").exists()
    ]
    script_folder_set = set(script_folders)
    used_slugs = {}
    exported_entries = []
    rows = []
    failures = []
    missing_source_scripts = []
    total_op_counts = Counter()
    total_unsupported_preview_ops = Counter()

    totals = Counter()
    label_owners = {}
    duplicate_labels = []

    for map_folder in map_folders:
        if map_folder not in script_folder_set:
            map_path = source_root / "data/maps" / map_folder / "map.json"
            map_data = load_json(map_path) if map_path.exists() else {}
            missing_source_scripts.append({
                "map_folder": map_folder,
                "map_id": map_data.get("id"),
                "map_name": map_data.get("name"),
                "map_json": to_project_path(map_path.relative_to(source_root)) if map_path.exists() else None,
                "missing_source_file": to_project_path(Path("data/maps") / map_folder / "scripts.inc"),
            })
            continue

        try:
            exported = build_export(source_root, map_folder)
            base_slug, output_slug = output_slug_for_script(map_folder, used_slugs)
            script_output = output_root / "scripts" / "{}.json".format(output_slug)
            if write_outputs:
                write_json(script_output, exported)
            exported_entries.append(manifest_entry_for_map_script(exported, script_output))
            rows.append(_script_report_row(map_folder, exported, script_output, base_slug, output_slug))

            stats = exported.get("stats", {})
            totals["label_count"] += int(stats.get("label_count", 0))
            totals["script_count"] += int(stats.get("script_count", 0))
            totals["movement_count"] += int(stats.get("movement_count", 0))
            totals["text_count"] += int(stats.get("text_count", 0))
            totals["encoded_text_count"] += int(stats.get("encoded_text_count", 0))
            totals["text_source_byte_count"] += int(stats.get("text_source_byte_count", 0))
            totals["charmap_warning_count"] += int(stats.get("charmap_warning_count", 0))
            totals["orphan_instruction_count"] += int(stats.get("orphan_instruction_count", 0))
            _sum_counter_dict(total_op_counts, stats.get("op_counts", {}))
            _sum_counter_dict(
                total_unsupported_preview_ops,
                exported.get("runtime_preview", {}).get("unsupported_op_counts", {}),
            )

            for label in exported.get("labels", {}):
                previous_owner = label_owners.get(label)
                if previous_owner is not None:
                    duplicate_labels.append({
                        "label": label,
                        "first_map": previous_owner,
                        "duplicate_map": map_folder,
                    })
                else:
                    label_owners[label] = map_folder
        except Exception as error:
            failures.append({
                "map_folder": map_folder,
                "error": str(error),
            })

    duplicate_base_slugs = sorted(
        slug for slug, count in Counter(row["base_slug"] for row in rows).items()
        if count > 1
    )
    duplicate_output_paths = sorted(
        path for path, count in Counter(entry["path"] for entry in exported_entries).items()
        if count > 1
    )
    runtime_preview_unsupported_op_count = sum(total_unsupported_preview_ops.values())

    stats = {
        "source_map_count": len(map_folders),
        "source_map_script_file_count": len(script_folders),
        "missing_source_script_file_count": len(missing_source_scripts),
        "exported_map_script_bundle_count": len(exported_entries),
        "failed_map_script_bundle_count": len(failures),
        "label_count": totals["label_count"],
        "unique_label_count": len(label_owners),
        "duplicate_label_count": len(duplicate_labels),
        "script_count": totals["script_count"],
        "movement_count": totals["movement_count"],
        "text_count": totals["text_count"],
        "encoded_text_count": totals["encoded_text_count"],
        "text_source_byte_count": totals["text_source_byte_count"],
        "charmap_warning_count": totals["charmap_warning_count"],
        "orphan_instruction_count": totals["orphan_instruction_count"],
        "runtime_preview_unsupported_op_count": runtime_preview_unsupported_op_count,
        "unique_op_count": len(total_op_counts),
        "unsupported_preview_unique_op_count": len(total_unsupported_preview_ops),
        "duplicate_base_slug_count": len(duplicate_base_slugs),
        "duplicate_output_path_count": len(duplicate_output_paths),
    }

    return {
        "schema_version": 1,
        "generated_by": GENERATED_BY,
        "source": {
            "project": "pokeemerald-expansion",
            "maps_root": "data/maps",
            "source_map_count": len(map_folders),
            "source_map_script_file_count": len(script_folders),
            "script_macro_source": "asm/macros/event.inc",
            "map_script_macro_source": "asm/macros/map.inc",
            "charmap": "charmap.txt",
        },
        "godot_policy": {
            "runtime_gba_palette_or_vram_limits": "not_recreated",
            "palette_affine_effects": "preserve source-visible timing/effect with Godot-native materials/animation when implemented",
            "audio": "metadata_only",
        },
        "output": {
            "script_directory": to_project_path(output_root / "scripts"),
            "report_path": to_project_path(output_root / SCRIPT_BATCH_REPORT_RELATIVE_PATH),
            "manifest_path": to_project_path(output_root / "import_manifest.json"),
            "writes_enabled": bool(write_outputs),
        },
        "stats": stats,
        "op_counts": dict(sorted(total_op_counts.items())),
        "unsupported_preview_ops": dict(sorted(total_unsupported_preview_ops.items())),
        "duplicates": {
            "labels": duplicate_labels,
            "base_slugs": duplicate_base_slugs,
            "output_paths": duplicate_output_paths,
        },
        "missing_source_scripts": missing_source_scripts,
        "failures": failures,
        "maps": rows,
        "unsupported": [
            {
                "code": "script_runtime_semantics_partial",
                "status": "unsupported",
                "note": "The importer preserves all parsed instructions, but runtime ScriptVM semantics are implemented incrementally after source tracing.",
            },
            {
                "code": "audio_metadata_only",
                "status": "metadata_only",
                "note": "Script sound/music/fanfare operands are preserved as symbols; real audio playback remains out of scope.",
            },
        ],
        "notes": [
            "Maps without scripts.inc are reported separately and do not block batch export.",
            "Shared data/scripts/*.inc bundles remain explicit shared exports until include ownership is expanded.",
        ],
    }, exported_entries


def build_shared_script_batch_export(source_root, output_root, write_outputs=False):
    script_files = sorted((source_root / "data/scripts").glob("*.inc"))
    skipped_existing = []
    exported_entries = []
    rows = []
    failures = []
    total_op_counts = Counter()
    total_unsupported_preview_ops = Counter()
    totals = Counter()
    label_owners = {}
    duplicate_labels = []

    def add_export(shared_name, exported, script_output, source_kind):
        if write_outputs:
            write_json(script_output, exported)
        exported_entries.append(manifest_entry_for_shared_script(exported, script_output, shared_name))
        rows.append(_shared_report_row(shared_name, exported, script_output, source_kind))

        stats = exported.get("stats", {})
        totals["label_count"] += int(stats.get("label_count", 0))
        totals["script_count"] += int(stats.get("script_count", 0))
        totals["movement_count"] += int(stats.get("movement_count", 0))
        totals["text_count"] += int(stats.get("text_count", 0))
        totals["encoded_text_count"] += int(stats.get("encoded_text_count", 0))
        totals["text_source_byte_count"] += int(stats.get("text_source_byte_count", 0))
        totals["charmap_warning_count"] += int(stats.get("charmap_warning_count", 0))
        totals["orphan_instruction_count"] += int(stats.get("orphan_instruction_count", 0))
        _sum_counter_dict(total_op_counts, stats.get("op_counts", {}))
        _sum_counter_dict(
            total_unsupported_preview_ops,
            exported.get("runtime_preview", {}).get("unsupported_op_counts", {}),
        )

        for label in exported.get("labels", {}):
            previous_owner = label_owners.get(label)
            if previous_owner is not None:
                duplicate_labels.append({
                    "label": label,
                    "first_bundle": previous_owner,
                    "duplicate_bundle": shared_name,
                })
            else:
                label_owners[label] = shared_name

    for script_path in script_files:
        relative_path = script_path.relative_to(source_root)
        if relative_path in EXISTING_GROUPED_SHARED_SCRIPT_FILES:
            skipped_existing.append(to_project_path(relative_path))
            continue
        shared_name = shared_name_for_script_path(script_path)
        script_output = output_root / "scripts" / "{}.json".format(camel_to_snake(shared_name))
        try:
            exported = build_shared_export(source_root, shared_name, [relative_path])
            add_export(shared_name, exported, script_output, "data_scripts_include")
        except Exception as error:
            failures.append({
                "name": shared_name,
                "source_file": to_project_path(relative_path),
                "error": str(error),
            })

    event_scripts_name = "shared_event_scripts_direct"
    event_scripts_output = output_root / "scripts" / "{}.json".format(camel_to_snake(event_scripts_name))
    try:
        exported = build_event_scripts_direct_export(source_root, event_scripts_name)
        add_export(event_scripts_name, exported, event_scripts_output, "event_scripts_direct")
    except Exception as error:
        failures.append({
            "name": event_scripts_name,
            "source_file": "data/event_scripts.s",
            "error": str(error),
        })

    duplicate_output_paths = sorted(
        path for path, count in Counter(entry["path"] for entry in exported_entries).items()
        if count > 1
    )
    runtime_preview_unsupported_op_count = sum(total_unsupported_preview_ops.values())

    stats = {
        "source_shared_script_file_count": len(script_files),
        "skipped_existing_shared_source_file_count": len(skipped_existing),
        "exported_shared_script_bundle_count": len(exported_entries),
        "failed_shared_script_bundle_count": len(failures),
        "event_scripts_direct_bundle_count": sum(1 for row in rows if row["source_kind"] == "event_scripts_direct"),
        "label_count": totals["label_count"],
        "unique_label_count": len(label_owners),
        "duplicate_label_count": len(duplicate_labels),
        "script_count": totals["script_count"],
        "movement_count": totals["movement_count"],
        "text_count": totals["text_count"],
        "encoded_text_count": totals["encoded_text_count"],
        "text_source_byte_count": totals["text_source_byte_count"],
        "charmap_warning_count": totals["charmap_warning_count"],
        "orphan_instruction_count": totals["orphan_instruction_count"],
        "runtime_preview_unsupported_op_count": runtime_preview_unsupported_op_count,
        "unique_op_count": len(total_op_counts),
        "unsupported_preview_unique_op_count": len(total_unsupported_preview_ops),
        "duplicate_output_path_count": len(duplicate_output_paths),
    }

    return {
        "schema_version": 1,
        "generated_by": GENERATED_BY,
        "source": {
            "project": "pokeemerald-expansion",
            "shared_scripts_root": "data/scripts",
            "event_scripts": "data/event_scripts.s",
            "script_macro_source": "asm/macros/event.inc",
            "charmap": "charmap.txt",
        },
        "godot_policy": {
            "runtime_gba_palette_or_vram_limits": "not_recreated",
            "palette_affine_effects": "preserve source-visible timing/effect with Godot-native materials/animation when implemented",
            "audio": "metadata_only",
        },
        "output": {
            "script_directory": to_project_path(output_root / "scripts"),
            "report_path": to_project_path(output_root / SHARED_SCRIPT_BATCH_REPORT_RELATIVE_PATH),
            "manifest_path": to_project_path(output_root / "import_manifest.json"),
            "writes_enabled": bool(write_outputs),
        },
        "stats": stats,
        "op_counts": dict(sorted(total_op_counts.items())),
        "unsupported_preview_ops": dict(sorted(total_unsupported_preview_ops.items())),
        "duplicates": {
            "labels": duplicate_labels,
            "output_paths": duplicate_output_paths,
        },
        "skipped_existing_shared_source_files": skipped_existing,
        "failures": failures,
        "shared_scripts": rows,
        "unsupported": [
            {
                "code": "script_runtime_semantics_partial",
                "status": "unsupported",
                "note": "The importer preserves parsed shared/common instructions, but runtime ScriptVM semantics are implemented incrementally after source tracing.",
            },
            {
                "code": "audio_metadata_only",
                "status": "metadata_only",
                "note": "Script sound/music/fanfare operands are preserved as symbols; real audio playback remains out of scope.",
            },
        ],
        "notes": [
            "Grouped first-slice shared bundles remain in the manifest; their source files are skipped here to avoid duplicate labels.",
            "data/event_scripts.s is exported as direct top-level labels after the map include block, with .include proxy lines ignored.",
        ],
    }, exported_entries


def _is_preview_supported_op(op):
    return op in PREVIEW_SUPPORTED_OPS


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, help="JSON config with source and output roots.")
    parser.add_argument("--source", type=Path, help="pokeemerald-expansion source root.")
    parser.add_argument("--map", default=None, help="Map folder name to export.")
    parser.add_argument("--all-maps", action="store_true", help="Export every source data/maps/*/scripts.inc bundle.")
    parser.add_argument("--all-shared", action="store_true", help="Export every shared data/scripts/*.inc bundle not covered by grouped shared exports.")
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

    if args.all_maps and args.all_shared:
        parser.error("--all-maps cannot be combined with --all-shared")

    if args.all_maps:
        if args.shared_name or args.include_script:
            parser.error("--all-maps cannot be combined with --shared-name or --include-script")
        report, exported_entries = build_map_script_batch_export(
            source_root,
            output_root,
            write_outputs=True,
        )
        report_output = output_root / SCRIPT_BATCH_REPORT_RELATIVE_PATH
        write_json(report_output, report)
        write_manifest(
            output_root / "import_manifest.json",
            exported_scripts=exported_entries,
            exported_overworld_reports=[
                {
                    "category": "overworld_script_batch_report",
                    "path": to_project_path(report_output),
                    "source_map_count": report["stats"]["source_map_count"],
                    "source_map_script_file_count": report["stats"]["source_map_script_file_count"],
                    "missing_source_script_file_count": report["stats"]["missing_source_script_file_count"],
                    "exported_map_script_bundle_count": report["stats"]["exported_map_script_bundle_count"],
                    "failed_map_script_bundle_count": report["stats"]["failed_map_script_bundle_count"],
                    "script_count": report["stats"]["script_count"],
                    "movement_count": report["stats"]["movement_count"],
                    "text_count": report["stats"]["text_count"],
                    "charmap_warning_count": report["stats"]["charmap_warning_count"],
                    "orphan_instruction_count": report["stats"]["orphan_instruction_count"],
                },
            ],
            generator=GENERATED_BY,
        )
        print(json.dumps({
            "report": to_project_path(report_output),
            "stats": report["stats"],
        }, ensure_ascii=False, indent=2))
        return 1 if report["stats"]["failed_map_script_bundle_count"] else 0

    if args.all_shared:
        if args.shared_name or args.include_script:
            parser.error("--all-shared cannot be combined with --shared-name or --include-script")
        report, exported_entries = build_shared_script_batch_export(
            source_root,
            output_root,
            write_outputs=True,
        )
        report_output = output_root / SHARED_SCRIPT_BATCH_REPORT_RELATIVE_PATH
        write_json(report_output, report)
        write_manifest(
            output_root / "import_manifest.json",
            exported_scripts=exported_entries,
            exported_overworld_reports=[
                {
                    "category": "overworld_shared_script_batch_report",
                    "path": to_project_path(report_output),
                    "source_shared_script_file_count": report["stats"]["source_shared_script_file_count"],
                    "skipped_existing_shared_source_file_count": report["stats"]["skipped_existing_shared_source_file_count"],
                    "exported_shared_script_bundle_count": report["stats"]["exported_shared_script_bundle_count"],
                    "failed_shared_script_bundle_count": report["stats"]["failed_shared_script_bundle_count"],
                    "script_count": report["stats"]["script_count"],
                    "movement_count": report["stats"]["movement_count"],
                    "text_count": report["stats"]["text_count"],
                    "charmap_warning_count": report["stats"]["charmap_warning_count"],
                    "orphan_instruction_count": report["stats"]["orphan_instruction_count"],
                },
            ],
            generator=GENERATED_BY,
        )
        print(json.dumps({
            "report": to_project_path(report_output),
            "stats": report["stats"],
        }, ensure_ascii=False, indent=2))
        return 1 if report["stats"]["failed_shared_script_bundle_count"] else 0

    if args.shared_name:
        if not args.include_script:
            parser.error("--shared-name requires at least one --include-script")
        exported = build_shared_export(source_root, args.shared_name, [Path(path) for path in args.include_script])
        script_slug = camel_to_snake(args.shared_name)
        script_output = output_root / "scripts" / "{}.json".format(script_slug)
        manifest_entry = manifest_entry_for_shared_script(exported, script_output, args.shared_name)
    else:
        exported = build_export(source_root, map_folder)
        script_slug = camel_to_snake(map_folder)
        script_output = output_root / "scripts" / "{}.json".format(script_slug)
        manifest_entry = manifest_entry_for_map_script(exported, script_output)
    write_json(script_output, exported)

    write_manifest(
        output_root / "import_manifest.json",
        exported_scripts=[manifest_entry],
        generator=GENERATED_BY,
    )

    print(json.dumps({
        "exported": manifest_entry,
        "stats": exported["stats"],
        "unsupported_preview_ops": exported["runtime_preview"]["unsupported_op_counts"],
    }, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
