#!/usr/bin/env python3
"""Export generated overworld script reference coverage."""

import argparse
import json
import re
import sys
from collections import Counter
from pathlib import Path

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
    output_root = output_root.resolve()
    project_root = output_root.parent.parent
    manifest_path = output_root / "import_manifest.json"
    manifest = read_json(manifest_path)

    script_entries = manifest.get("scripts", [])
    text_entries = manifest.get("texts", [])
    script_labels = {}
    movement_labels = {}
    script_text_labels = {}
    global_text_labels = {}
    bundle_rows = []
    map_rows = []
    failures = []
    references = []

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
        bundle_data = load_generated_json(project_root, path_text)
        if not isinstance(bundle_data, dict):
            continue

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
        },
        "stats": stats,
        "reference_counts": reference_counts,
        "missing_reference_counts": missing_counts,
        "excluded_reference_counts": excluded_counts,
        "missing_references": missing_references,
        "excluded_references": excluded_references,
        "duplicates": {
            "script_labels": duplicate_label_details(script_labels),
            "movement_labels": duplicate_label_details(movement_labels),
            "script_text_labels": duplicate_label_details(script_text_labels),
            "global_text_labels": duplicate_label_details(global_text_labels),
        },
        "failures": failures,
        "maps": map_rows,
        "bundles": bundle_rows,
        "notes": [
            "movement references are the second operand of applymovement/applymovementat, matching source event macros and ScrCmd handlers.",
            "gStringVar* and NULL text operands are dynamic/null references and are counted as excluded rather than missing text labels.",
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
