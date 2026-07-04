#!/usr/bin/env python3
"""Export generated overworld script reference coverage."""

import argparse
import json
import re
import sys
from collections import Counter
from pathlib import Path

from export_event_scripts import EVENT_SCRIPTS_DIRECT_IGNORED_OPS, _last_map_include_line, read_script_file
from export_map import write_json, write_manifest
from source_probe import load_config, to_project_path


GENERATED_BY = "tools/importer/export_overworld_script_reference_report.py"
REPORT_PATH = Path("overworld/script_reference_report.json")
SYMBOL_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
SCRIPT_REFERENCE_OPS = {"call", "goto"}
MOVEMENT_REFERENCE_OPS = {"applymovement", "applymovementat"}
TEXT_REFERENCE_OPS = {"message", "msgbox", "braillemessage"}
TEXT_REFERENCE_DYNAMIC_TARGETS = {
    "NULL",
    "gStringVar1",
    "gStringVar2",
    "gStringVar3",
    "gStringVar4",
}
DIRECTIVE_PREFIXES = (".", "#")
SUPPORTED_TEXT_DIRECTIVES = {".string"}
MACRO_DEFINITION_RE = re.compile(r"^\s*\.macro\s+([A-Za-z_][A-Za-z0-9_]*)", re.MULTILINE)
MOVEMENT_ACTION_MACRO_RE = re.compile(
    r"^\s*create_movement_action\s+([A-Za-z_][A-Za-z0-9_]*)\s*,",
    re.MULTILINE,
)


def read_json(path):
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def resolve_project_path(project_root, path_text):
    path = Path(path_text)
    if path.is_absolute():
        return path
    return project_root / path


def load_generated_json(project_root, path_text):
    path = resolve_project_path(project_root, path_text)
    if not path.exists():
        return None
    return read_json(path)


def read_text(path):
    with path.open("r", encoding="utf-8") as handle:
        return handle.read()


def load_source_macro_names(source_root):
    macro_root = source_root / "asm/macros"
    names = set()
    sources = {}
    if not macro_root.exists():
        return names, sources
    for path in sorted(macro_root.rglob("*.inc")):
        text = read_text(path)
        source_file = to_project_path(path.relative_to(source_root))
        for name in MACRO_DEFINITION_RE.findall(text):
            names.add(name)
            sources.setdefault(name, source_file)
        for name in MOVEMENT_ACTION_MACRO_RE.findall(text):
            names.add(name)
            sources.setdefault(name, source_file)
    return names, sources


def add_label(label_index, label, kind, owner):
    record = label_index.setdefault(label, {
        "label": label,
        "kind": kind,
        "owners": [],
    })
    record["owners"].append(owner)


def owner_from_entry(entry):
    return {
        "map": entry.get("map"),
        "map_id": entry.get("map_id"),
        "map_name": entry.get("map_name"),
        "scope": entry.get("scope", "map" if entry.get("map") else ""),
        "name": entry.get("name"),
        "path": entry.get("path"),
    }


def owner_name(owner):
    return owner.get("map") or owner.get("name") or owner.get("path") or ""


def runtime_unsupported_op_count(bundle_data):
    unsupported = bundle_data.get("runtime_preview", {}).get("unsupported_op_counts", {})
    return sum(value for value in unsupported.values() if isinstance(value, int))


def bundle_source_files(bundle_data):
    source = bundle_data.get("source", {})
    if source.get("map_script"):
        return [source.get("map_script")]
    return list(source.get("script_files", []))


def iter_bundle_records(bundle_data):
    for collection_name, count_key in [
        ("scripts", "script_count"),
        ("movements", "movement_count"),
        ("texts", "text_count"),
    ]:
        records = bundle_data.get(collection_name, {})
        if not isinstance(records, dict):
            continue
        for label, record in records.items():
            yield collection_name, count_key, label, record


def iter_bundle_instructions(bundle_data):
    for collection_name, _count_key, label, record in iter_bundle_records(bundle_data):
        instructions = record.get("instructions", [])
        if not isinstance(instructions, list):
            continue
        for instruction in instructions:
            if isinstance(instruction, dict):
                yield collection_name, label, record, instruction


def local_macro_name(instruction):
    if instruction.get("op") != ".macro":
        return ""
    args = instruction.get("args", [])
    if args:
        candidate = str(args[0]).strip().split()[0]
    else:
        candidate = str(instruction.get("raw", "")).replace(".macro", "", 1).strip().split()[0]
    return candidate if SYMBOL_RE.match(candidate) else ""


def collect_local_macros_by_file(bundle_data):
    result = {}
    for _collection_name, _label, record, instruction in iter_bundle_instructions(bundle_data):
        name = local_macro_name(instruction)
        if not name:
            continue
        source_file = instruction.get("source_file") or record.get("source_file") or ""
        if not source_file:
            continue
        result.setdefault(source_file, set()).add(name)
    return result


def empty_file_diagnostic(source_file):
    return {
        "source_file": source_file,
        "bundle_count": 0,
        "bundles": [],
        "script_count": 0,
        "movement_count": 0,
        "text_count": 0,
        "orphan_instruction_count": 0,
        "unknown_macro_count": 0,
        "unsupported_directive_count": 0,
        "unresolved_label_count": 0,
        "missing_script_reference_count": 0,
        "missing_movement_reference_count": 0,
        "missing_text_label_count": 0,
        "unknown_macros": {},
        "unsupported_directives": {},
        "unknown_macro_details": [],
        "orphan_instructions": [],
        "missing_references": [],
    }


def ensure_file_diagnostic(diagnostics, source_file):
    if not source_file:
        source_file = "<unknown>"
    if source_file not in diagnostics:
        diagnostics[source_file] = empty_file_diagnostic(source_file)
    return diagnostics[source_file]


def diagnostic_owner(owner):
    return {
        "name": owner_name(owner),
        "scope": owner.get("scope"),
        "map": owner.get("map"),
        "map_id": owner.get("map_id"),
        "path": owner.get("path"),
    }


def add_diagnostic_owner(row, owner):
    owner_record = diagnostic_owner(owner)
    if owner_record not in row["bundles"]:
        row["bundles"].append(owner_record)
        row["bundle_count"] = len(row["bundles"])


def increment_counter_dict(row, key, value):
    counts = row.setdefault(key, {})
    counts[value] = int(counts.get(value, 0)) + 1


def instruction_detail(instruction, owner=None, script_label=None):
    detail = {
        "op": instruction.get("op"),
        "line": instruction.get("line"),
        "raw": instruction.get("raw"),
        "source_file": instruction.get("source_file"),
    }
    if script_label is not None:
        detail["script_label"] = script_label
    if owner is not None:
        detail["bundle"] = owner_name(owner)
        detail["bundle_path"] = owner.get("path")
    return detail


def add_bundle_file_baseline(diagnostics, owner, bundle_data):
    for source_file in bundle_source_files(bundle_data):
        if source_file:
            add_diagnostic_owner(ensure_file_diagnostic(diagnostics, source_file), owner)
    for _collection_name, count_key, _label, record in iter_bundle_records(bundle_data):
        source_file = record.get("source_file")
        row = ensure_file_diagnostic(diagnostics, source_file)
        add_diagnostic_owner(row, owner)
        row[count_key] += 1


def add_instruction_diagnostics(diagnostics, owner, bundle_data, known_macro_names, local_macros_by_file):
    for _collection_name, label, record, instruction in iter_bundle_instructions(bundle_data):
        source_file = instruction.get("source_file") or record.get("source_file")
        row = ensure_file_diagnostic(diagnostics, source_file)
        add_diagnostic_owner(row, owner)
        op = instruction.get("op", "")
        if not op:
            continue
        if op.startswith(DIRECTIVE_PREFIXES):
            if op not in SUPPORTED_TEXT_DIRECTIVES:
                row["unsupported_directive_count"] += 1
                increment_counter_dict(row, "unsupported_directives", op)
            continue
        if op in known_macro_names or op in local_macros_by_file.get(source_file, set()):
            continue
        row["unknown_macro_count"] += 1
        increment_counter_dict(row, "unknown_macros", op)
        row["unknown_macro_details"].append(instruction_detail(instruction, owner=owner, script_label=label))


def add_orphan_instruction_diagnostics(source_root, diagnostics, owner, bundle_data):
    source = bundle_data.get("source", {})
    script_files = bundle_source_files(bundle_data)
    label_filter = None
    ignored_ops = None
    label_filter_record = source.get("label_filter", {})
    if label_filter_record.get("kind") == "direct_labels_after_map_includes":
        start_line = int(label_filter_record.get("start_line", 0))
        if start_line <= 0 and script_files:
            start_line = _last_map_include_line(source_root / script_files[0]) + 1

        def direct_label_filter(_label, line_number):
            return line_number >= start_line

        label_filter = direct_label_filter
        ignored_ops = set(label_filter_record.get("ignored_ops") or EVENT_SCRIPTS_DIRECT_IGNORED_OPS)

    for source_file in script_files:
        path = source_root / source_file
        if not path.exists():
            continue
        _labels, _order, orphan_instructions = read_script_file(
            path,
            source_file,
            label_filter=label_filter,
            ignored_ops=ignored_ops,
        )
        if not orphan_instructions:
            continue
        row = ensure_file_diagnostic(diagnostics, source_file)
        add_diagnostic_owner(row, owner)
        row["orphan_instruction_count"] += len(orphan_instructions)
        row["orphan_instructions"].extend(
            instruction_detail(instruction, owner=owner)
            for instruction in orphan_instructions
        )


def add_missing_reference_diagnostics(diagnostics, references):
    for reference in references:
        row = ensure_file_diagnostic(diagnostics, reference.get("source_file"))
        row["missing_references"].append(reference)
        if reference["kind"] == "text":
            row["missing_text_label_count"] += 1
        elif reference["kind"] == "script":
            row["unresolved_label_count"] += 1
            row["missing_script_reference_count"] += 1
        elif reference["kind"] == "movement":
            row["unresolved_label_count"] += 1
            row["missing_movement_reference_count"] += 1


def sorted_file_diagnostics(diagnostics):
    rows = []
    for row in diagnostics.values():
        row = dict(row)
        row["unknown_macros"] = dict(sorted(row["unknown_macros"].items()))
        row["unsupported_directives"] = dict(sorted(row["unsupported_directives"].items()))
        row["bundles"] = sorted(row["bundles"], key=lambda item: (item.get("path") or "", item.get("name") or ""))
        rows.append(row)
    return sorted(rows, key=lambda item: item["source_file"])


def count_rows_with(rows, key):
    return sum(1 for row in rows if int(row.get(key, 0)) > 0)


def script_reference_target(instruction):
    op = instruction.get("op")
    args = instruction.get("args", [])
    if op in SCRIPT_REFERENCE_OPS and args:
        return args[0]
    if (op or "").startswith("call_if_") and args:
        return args[-1]
    if (op or "").startswith("goto_if_") and args:
        return args[-1]
    if op == "case" and len(args) >= 2:
        return args[-1]
    return None


def movement_reference_target(instruction):
    op = instruction.get("op")
    args = instruction.get("args", [])
    if op in MOVEMENT_REFERENCE_OPS and len(args) >= 2:
        return args[1]
    return None


def text_reference_target(instruction):
    op = instruction.get("op")
    args = instruction.get("args", [])
    if op in TEXT_REFERENCE_OPS and args:
        return args[0]
    return None


def reference_context(owner, script_label, instruction, kind, target, status="checked"):
    return {
        "kind": kind,
        "target": target,
        "status": status,
        "op": instruction.get("op"),
        "line": instruction.get("line"),
        "source_file": instruction.get("source_file"),
        "script_label": script_label,
        "bundle": owner_name(owner),
        "bundle_path": owner.get("path"),
        "map": owner.get("map"),
        "map_id": owner.get("map_id"),
        "scope": owner.get("scope"),
    }


def is_symbol_reference(target):
    return isinstance(target, str) and SYMBOL_RE.match(target) is not None


def should_exclude_text_reference(target):
    return target in TEXT_REFERENCE_DYNAMIC_TARGETS


def iter_references(owner, bundle_data):
    for script_label, script_record in bundle_data.get("scripts", {}).items():
        for instruction in script_record.get("instructions", []):
            script_target = script_reference_target(instruction)
            if is_symbol_reference(script_target):
                yield reference_context(owner, script_label, instruction, "script", script_target)

            movement_target = movement_reference_target(instruction)
            if is_symbol_reference(movement_target):
                yield reference_context(owner, script_label, instruction, "movement", movement_target)

            text_target = text_reference_target(instruction)
            if not is_symbol_reference(text_target):
                continue
            if should_exclude_text_reference(text_target):
                yield reference_context(owner, script_label, instruction, "text", text_target, "excluded_dynamic")
            else:
                yield reference_context(owner, script_label, instruction, "text", text_target)


def count_duplicate_labels(label_index):
    return sum(1 for record in label_index.values() if len(record["owners"]) > 1)


def duplicate_label_details(label_index, limit=50):
    duplicates = []
    for label, record in sorted(label_index.items()):
        if len(record["owners"]) <= 1:
            continue
        duplicates.append({
            "label": label,
            "kind": record["kind"],
            "owners": record["owners"],
        })
        if len(duplicates) >= limit:
            break
    return duplicates


def build_export(source_root, output_root):
    source_root = source_root.resolve()
    output_root = output_root.resolve()
    project_root = output_root.parent.parent
    manifest_path = output_root / "import_manifest.json"
    manifest = read_json(manifest_path)

    known_macro_names, known_macro_sources = load_source_macro_names(source_root)
    script_entries = manifest.get("scripts", [])
    text_entries = manifest.get("texts", [])
    script_bundle_cache = {}
    script_labels = {}
    movement_labels = {}
    script_text_labels = {}
    global_text_labels = {}
    bundle_rows = []
    map_rows = []
    failures = []
    references = []
    file_diagnostics = {}
    local_macros_by_file = {}

    for text_entry in text_entries:
        if text_entry.get("category") != "global":
            continue
        text_data = load_generated_json(project_root, text_entry.get("path", ""))
        if not isinstance(text_data, dict):
            continue
        owner = {
            "scope": "global_text",
            "name": text_entry.get("category"),
            "path": text_entry.get("path"),
        }
        for label in text_data.get("texts", {}):
            add_label(global_text_labels, label, "global_text", owner)

    for entry in script_entries:
        owner = owner_from_entry(entry)
        path_text = entry.get("path", "")
        bundle_data = load_generated_json(project_root, path_text)
        if not isinstance(bundle_data, dict):
            failures.append({
                "code": "script_bundle_missing_or_invalid",
                "path": path_text,
                "bundle": owner,
            })
            continue
        script_bundle_cache[path_text] = bundle_data
        add_bundle_file_baseline(file_diagnostics, owner, bundle_data)
        for source_file, names in collect_local_macros_by_file(bundle_data).items():
            local_macros_by_file.setdefault(source_file, set()).update(names)
        for label in bundle_data.get("scripts", {}):
            add_label(script_labels, label, "script", owner)
        for label in bundle_data.get("movements", {}):
            add_label(movement_labels, label, "movement", owner)
        for label in bundle_data.get("texts", {}):
            add_label(script_text_labels, label, "script_text", owner)

    text_labels = {}
    text_labels.update(global_text_labels)
    text_labels.update(script_text_labels)
    label_indexes = {
        "script": script_labels,
        "movement": movement_labels,
        "text": text_labels,
    }

    for entry in script_entries:
        owner = owner_from_entry(entry)
        path_text = entry.get("path", "")
        bundle_data = script_bundle_cache.get(path_text)
        if not isinstance(bundle_data, dict):
            continue
        add_instruction_diagnostics(
            file_diagnostics,
            owner,
            bundle_data,
            known_macro_names,
            local_macros_by_file,
        )
        add_orphan_instruction_diagnostics(source_root, file_diagnostics, owner, bundle_data)

        bundle_references = list(iter_references(owner, bundle_data))
        references.extend(bundle_references)
        bundle_missing = []
        bundle_excluded = []
        for reference in bundle_references:
            if reference["status"] == "excluded_dynamic":
                bundle_excluded.append(reference)
                continue
            if reference["target"] not in label_indexes[reference["kind"]]:
                bundle_missing.append(reference)
        add_missing_reference_diagnostics(file_diagnostics, bundle_missing)

        row = {
            "name": owner_name(owner),
            "scope": owner.get("scope"),
            "map": owner.get("map"),
            "map_id": owner.get("map_id"),
            "map_name": owner.get("map_name"),
            "path": path_text,
            "script_count": len(bundle_data.get("scripts", {})),
            "movement_count": len(bundle_data.get("movements", {})),
            "text_count": len(bundle_data.get("texts", {})),
            "runtime_preview_unsupported_op_count": runtime_unsupported_op_count(bundle_data),
            "orphan_instruction_count": int(bundle_data.get("stats", {}).get("orphan_instruction_count", 0)),
            "reference_counts": count_references(bundle_references),
            "excluded_reference_count": len(bundle_excluded),
            "missing_reference_count": len(bundle_missing),
            "missing_references": bundle_missing,
        }
        bundle_rows.append(row)
        if owner.get("map"):
            map_rows.append(row)

    checked_references = [reference for reference in references if reference["status"] == "checked"]
    excluded_references = [reference for reference in references if reference["status"] != "checked"]
    missing_references = [
        reference for reference in checked_references
        if reference["target"] not in label_indexes[reference["kind"]]
    ]
    reference_counts = count_references(checked_references)
    missing_counts = count_references(missing_references)
    excluded_counts = count_references(excluded_references)
    file_diagnostic_rows = sorted_file_diagnostics(file_diagnostics)
    unknown_macro_counts = Counter()
    unsupported_directive_counts = Counter()
    for row in file_diagnostic_rows:
        unknown_macro_counts.update(row.get("unknown_macros", {}))
        unsupported_directive_counts.update(row.get("unsupported_directives", {}))

    stats = {
        "script_bundle_count": len(script_entries),
        "map_script_bundle_count": sum(1 for entry in script_entries if entry.get("map")),
        "shared_script_bundle_count": sum(1 for entry in script_entries if entry.get("scope") == "shared"),
        "script_label_count": len(script_labels),
        "movement_label_count": len(movement_labels),
        "script_text_label_count": len(script_text_labels),
        "global_text_label_count": len(global_text_labels),
        "duplicate_script_label_count": count_duplicate_labels(script_labels),
        "duplicate_movement_label_count": count_duplicate_labels(movement_labels),
        "duplicate_script_text_label_count": count_duplicate_labels(script_text_labels),
        "duplicate_global_text_label_count": count_duplicate_labels(global_text_labels),
        "checked_reference_count": len(checked_references),
        "missing_reference_count": len(missing_references),
        "excluded_reference_count": len(excluded_references),
        "script_reference_count": reference_counts["script"],
        "movement_reference_count": reference_counts["movement"],
        "text_reference_count": reference_counts["text"],
        "missing_script_reference_count": missing_counts["script"],
        "missing_movement_reference_count": missing_counts["movement"],
        "missing_text_reference_count": missing_counts["text"],
        "excluded_script_reference_count": excluded_counts["script"],
        "excluded_movement_reference_count": excluded_counts["movement"],
        "excluded_text_reference_count": excluded_counts["text"],
        "failed_bundle_count": len(failures),
        "map_rows_with_missing_references": sum(1 for row in map_rows if row["missing_reference_count"] > 0),
        "bundle_rows_with_missing_references": sum(1 for row in bundle_rows if row["missing_reference_count"] > 0),
        "script_file_diagnostic_count": len(file_diagnostic_rows),
        "script_file_orphan_instruction_count": sum(row["orphan_instruction_count"] for row in file_diagnostic_rows),
        "script_files_with_orphan_instructions": count_rows_with(file_diagnostic_rows, "orphan_instruction_count"),
        "unknown_macro_count": sum(unknown_macro_counts.values()),
        "unknown_macro_unique_count": len(unknown_macro_counts),
        "script_files_with_unknown_macros": count_rows_with(file_diagnostic_rows, "unknown_macro_count"),
        "unsupported_directive_count": sum(unsupported_directive_counts.values()),
        "unsupported_directive_unique_count": len(unsupported_directive_counts),
        "script_files_with_unsupported_directives": count_rows_with(file_diagnostic_rows, "unsupported_directive_count"),
        "unresolved_label_count": sum(row["unresolved_label_count"] for row in file_diagnostic_rows),
        "script_files_with_unresolved_labels": count_rows_with(file_diagnostic_rows, "unresolved_label_count"),
        "script_files_with_missing_text_labels": count_rows_with(file_diagnostic_rows, "missing_text_label_count"),
    }

    return {
        "schema_version": 1,
        "generated_by": GENERATED_BY,
        "source_root": str(source_root),
        "manifest_path": to_project_path(manifest_path),
        "source_trace": {
            "movement_reference_macro": "asm/macros/event.inc:applymovement localId, movements, map",
            "movement_reference_runtime": [
                "src/scrcmd.c:ScrCmd_applymovement",
                "src/scrcmd.c:ScrCmd_applymovementat",
                "src/script_movement.c:ScriptMovement_StartObjectMovementScript",
            ],
            "text_reference_dynamic_targets": sorted(TEXT_REFERENCE_DYNAMIC_TARGETS),
            "macro_sources": {
                "macro_root": "asm/macros",
                "source_macro_count": len(known_macro_names),
                "local_source_macro_count": sum(len(names) for names in local_macros_by_file.values()),
                "movement_action_macro_pattern": "asm/macros/movement.inc:create_movement_action",
                "sample_macro_sources": {
                    name: known_macro_sources[name]
                    for name in sorted(known_macro_sources)[:20]
                },
            },
        },
        "stats": stats,
        "reference_counts": reference_counts,
        "missing_reference_counts": missing_counts,
        "excluded_reference_counts": excluded_counts,
        "unknown_macro_counts": dict(sorted(unknown_macro_counts.items())),
        "unsupported_directive_counts": dict(sorted(unsupported_directive_counts.items())),
        "missing_references": missing_references,
        "excluded_references": excluded_references,
        "duplicates": {
            "script_labels": duplicate_label_details(script_labels),
            "movement_labels": duplicate_label_details(movement_labels),
            "script_text_labels": duplicate_label_details(script_text_labels),
            "global_text_labels": duplicate_label_details(global_text_labels),
        },
        "failures": failures,
        "script_file_diagnostics": file_diagnostic_rows,
        "maps": map_rows,
        "bundles": bundle_rows,
        "notes": [
            "movement references are the second operand of applymovement/applymovementat, matching source event macros and ScrCmd handlers.",
            "gStringVar* and NULL text operands are dynamic/null references and are counted as excluded rather than missing text labels.",
            "unknown_macro_count excludes source macros from asm/macros/**/*.inc, create_movement_action-generated movement macros, and local .macro definitions found in source script files.",
            "unsupported_directive_count reports preserved assembler/preprocessor directives such as .byte/.2byte/#ifdef that are not semantic script commands.",
            "Audio remains metadata_only/unsupported; this report validates labels and generated references only.",
        ],
    }


def count_references(references):
    counts = Counter()
    for reference in references:
        counts[reference["kind"]] += 1
    return {
        "script": counts["script"],
        "movement": counts["movement"],
        "text": counts["text"],
    }


def manifest_entry_for(exported, output_path):
    stats = exported["stats"]
    return {
        "category": "overworld_script_reference_report",
        "path": to_project_path(output_path),
        "script_bundle_count": stats["script_bundle_count"],
        "map_script_bundle_count": stats["map_script_bundle_count"],
        "shared_script_bundle_count": stats["shared_script_bundle_count"],
        "script_label_count": stats["script_label_count"],
        "movement_label_count": stats["movement_label_count"],
        "checked_reference_count": stats["checked_reference_count"],
        "missing_reference_count": stats["missing_reference_count"],
        "missing_movement_reference_count": stats["missing_movement_reference_count"],
        "excluded_reference_count": stats["excluded_reference_count"],
        "script_file_diagnostic_count": stats["script_file_diagnostic_count"],
        "script_file_orphan_instruction_count": stats["script_file_orphan_instruction_count"],
        "unknown_macro_count": stats["unknown_macro_count"],
        "unsupported_directive_count": stats["unsupported_directive_count"],
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
    output_path = output_root / REPORT_PATH

    exported = build_export(source_root, output_root)
    write_json(output_path, exported)
    manifest_entry = manifest_entry_for(exported, output_path)
    write_manifest(
        output_root / "import_manifest.json",
        exported_overworld_reports=[manifest_entry],
        generator=GENERATED_BY,
    )

    print(json.dumps({"exported": manifest_entry, "stats": exported["stats"]}, ensure_ascii=False, indent=2))
    return 0 if exported["stats"]["missing_reference_count"] == 0 and exported["stats"]["failed_bundle_count"] == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
