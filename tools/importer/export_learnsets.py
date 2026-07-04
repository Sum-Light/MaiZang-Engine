#!/usr/bin/env python3
"""Export active pokeemerald-expansion level-up learnsets into generated JSON."""

import argparse
import json
import re
import sys
from pathlib import Path

from export_map import write_json, write_manifest
from export_species import (
    ExpressionEvaluator,
    _constant_record,
    _export_constant_group,
    _load_macro_expressions,
    _parse_enum_constants,
    _preprocess_records,
    _read_source_lines,
    _relative_source_location,
)
from source_probe import load_config, to_project_path


LEARNSET_START_RE = re.compile(r"static\s+const\s+struct\s+LevelUpMove\s+([A-Za-z_][A-Za-z0-9_]*)\[\]\s*=\s*\{")
LEVEL_UP_MOVE_RE = re.compile(r"LEVEL_UP_MOVE\s*\(\s*([^,]+?)\s*,\s*([^)]+?)\s*\)")


def _active_learnset_source(root, macros):
    evaluator = ExpressionEvaluator(macros)
    configured = evaluator.eval_int("P_LVL_UP_LEARNSETS")
    warnings = []
    if configured is None:
        warnings.append("could not resolve P_LVL_UP_LEARNSETS; defaulted to GEN_9 source file")
        return Path("src/data/pokemon/level_up_learnsets/gen_9.h"), "GEN_9", None, warnings

    for generation in range(9, 0, -1):
        generation_symbol = "GEN_{}".format(generation)
        threshold = evaluator.eval_int(generation_symbol)
        if threshold is not None and configured >= threshold:
            return (
                Path("src/data/pokemon/level_up_learnsets/gen_{}.h".format(generation)),
                generation_symbol,
                configured,
                warnings,
            )

    warnings.append("P_LVL_UP_LEARNSETS resolved below GEN_1; defaulted to GEN_1 source file")
    return Path("src/data/pokemon/level_up_learnsets/gen_1.h"), "GEN_1", configured, warnings


def _load_constants(root, macros):
    constants = {
        "moves": _parse_enum_constants(root / "include/constants/moves.h", "Move", macros),
        "evaluator": ExpressionEvaluator(macros),
    }
    return constants


def _parse_learnsets(root, records, constants):
    learnsets = {}
    order = []
    index = 0
    while index < len(records):
        start_match = LEARNSET_START_RE.search(records[index].text)
        if not start_match:
            index += 1
            continue

        label = start_match.group(1)
        start_record = records[index]
        moves = []
        warnings = []
        terminated = False
        index += 1

        while index < len(records):
            record = records[index]
            line = record.text
            if "LEVEL_UP_END" in line:
                terminated = True
            for move_match in LEVEL_UP_MOVE_RE.finditer(line):
                level_raw = move_match.group(1).strip()
                move_raw = move_match.group(2).strip()
                level = constants["evaluator"].eval_int(level_raw)
                if level is None:
                    warnings.append("could not evaluate level expression: {}".format(level_raw))
                move_warnings = []
                move_record = _constant_record(move_raw, constants["moves"], "MOVE_", constants["evaluator"], move_warnings)
                warnings.extend(move_warnings)
                moves.append({
                    "level": level,
                    "level_raw": level_raw,
                    "move": move_record,
                    "source": _relative_source_location(root, record),
                })
            if "};" in line:
                break
            index += 1

        if not terminated:
            warnings.append("missing LEVEL_UP_END terminator")

        learnsets[label] = {
            "label": label,
            "source": _relative_source_location(root, start_record),
            "moves": moves,
            "move_count": len(moves),
            "level_zero_move_count": sum(1 for move in moves if move.get("level") == 0),
            "warnings": sorted(set(warnings)),
            "evaluation_status": "partial" if warnings else "ok",
        }
        order.append(label)
        index += 1

    return learnsets, order


def export_learnsets(root):
    macros = _load_macro_expressions(root)
    active_source, active_generation, configured_value, source_warnings = _active_learnset_source(root, macros)
    constants = _load_constants(root, macros)
    source_records = _read_source_lines(root / active_source)
    preprocessed_records, preprocessor_report = _preprocess_records(source_records, macros)
    learnsets, learnset_order = _parse_learnsets(root, preprocessed_records, constants)

    warning_count = len(source_warnings) + len(preprocessor_report["warnings"])
    warning_count += sum(len(record.get("warnings", [])) for record in learnsets.values())
    move_entry_count = sum(record.get("move_count", 0) for record in learnsets.values())
    level_zero_move_count = sum(record.get("level_zero_move_count", 0) for record in learnsets.values())
    unresolved_move_count = 0
    for record in learnsets.values():
        for move in record.get("moves", []):
            move_record = move.get("move", {})
            if move_record.get("value") is None:
                unresolved_move_count += 1

    return {
        "schema_version": 1,
        "source": {
            "project": "pokeemerald-expansion",
            "selection": {
                "config": "include/config/pokemon.h:P_LVL_UP_LEARNSETS",
                "configured_value": configured_value,
                "active_generation": active_generation,
                "active_file": to_project_path(active_source),
            },
            "runtime_references": [
                "src/battle_main.c:CustomTrainerPartyAssignMoves",
                "src/pokemon.c:GiveBoxMonInitialMoveset",
                "src/pokemon.c:GetSpeciesLevelUpLearnset",
                "src/pokemon.c:GetMovePP",
            ],
            "struct_definition": "include/pokemon.h:struct LevelUpMove",
            "macro": "LEVEL_UP_MOVE(lvl, moveLearned)",
            "terminator": "LEVEL_UP_END",
            "constants": [
                "include/constants/moves.h",
            ],
            "config": [
                "include/config/general.h",
                "include/config/pokemon.h",
                "include/config/species_enabled.h",
            ],
            "preprocessor": preprocessor_report,
            "warnings": source_warnings,
        },
        "constants": {
            "moves": _export_constant_group(constants["moves"], "MOVE_"),
        },
        "learnset_order": learnset_order,
        "learnsets": learnsets,
        "stats": {
            "learnset_count": len(learnsets),
            "move_entry_count": move_entry_count,
            "level_zero_move_count": level_zero_move_count,
            "unresolved_move_count": unresolved_move_count,
            "preprocessor_decision_count": len(preprocessor_report["decisions"]),
            "preprocessor_warning_count": len(preprocessor_report["warnings"]),
            "warning_count": warning_count,
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

    exported = export_learnsets(source_root)
    learnsets_output = output_root / "pokemon" / "learnsets.json"
    write_json(learnsets_output, exported)

    stats = exported["stats"]
    manifest_entry = {
        "category": "learnsets",
        "path": to_project_path(learnsets_output),
        "active_generation": exported["source"]["selection"]["active_generation"],
        "learnset_count": stats["learnset_count"],
        "move_entry_count": stats["move_entry_count"],
        "level_zero_move_count": stats["level_zero_move_count"],
        "warning_count": stats["warning_count"],
        "unresolved_move_count": stats["unresolved_move_count"],
    }
    write_manifest(
        output_root / "import_manifest.json",
        exported_pokemon=[manifest_entry],
        generator="tools/importer/export_learnsets.py",
    )

    print(json.dumps({
        "exported": manifest_entry,
        "preprocessor_decision_count": stats["preprocessor_decision_count"],
    }, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
