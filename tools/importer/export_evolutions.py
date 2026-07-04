#!/usr/bin/env python3
"""Export pokeemerald-expansion species evolution data into generated JSON."""

import argparse
import json
import re
import sys
from pathlib import Path

from export_map import load_json, write_json, write_manifest
from export_species import (
    ExpressionEvaluator,
    _compact_source,
    _constant_record,
    _eval_field_int,
    _expand_species_info_includes,
    _export_constant_group,
    _load_macro_expressions,
    _parse_define_constants,
    _parse_enum_constants,
    _parse_species_entries,
    _preprocess_records,
    _read_defines_into,
    _relative_source_location,
    _split_top_level,
)
from export_wild_encounters import _load_map_constants
from source_probe import load_config, to_project_path


EVOLUTION_PARAM_FIELDS = ["arg1", "arg2", "arg3"]

METHOD_RUNTIME_MODES = {
    "EVO_LEVEL": ["EVO_MODE_NORMAL", "EVO_MODE_BATTLE_ONLY"],
    "EVO_LEVEL_BATTLE_ONLY": ["EVO_MODE_BATTLE_ONLY"],
    "EVO_TRADE": ["EVO_MODE_TRADE"],
    "EVO_ITEM": ["EVO_MODE_ITEM_USE", "EVO_MODE_ITEM_CHECK"],
    "EVO_BATTLE_END": ["EVO_MODE_BATTLE_SPECIAL"],
    "EVO_SPIN": ["EVO_MODE_OVERWORLD_SPECIAL"],
    "EVO_SCRIPT_TRIGGER": ["EVO_MODE_SCRIPT_TRIGGER"],
}

METHOD_RUNTIME_HANDLERS = {
    "EVO_NONE": ["offspring_or_sentinel"],
    "EVO_SPLIT_FROM_EVO": ["src/evolution_scene.c:TryCreateSplitEvoMon"],
}

METHOD_PARAM_KINDS = {
    "EVO_LEVEL": "level",
    "EVO_LEVEL_BATTLE_ONLY": "level",
    "EVO_ITEM": "item",
    "EVO_SPIN": "spin_direction",
    "EVO_SPLIT_FROM_EVO": "species",
}

CONDITION_ARG_KINDS = {
    "IF_GENDER": ["gender", "number", "number"],
    "IF_TIME": ["time_of_day", "number", "number"],
    "IF_NOT_TIME": ["time_of_day", "number", "number"],
    "IF_MIN_FRIENDSHIP": ["friendship", "number", "number"],
    "IF_ATK_GT_DEF": ["number", "number", "number"],
    "IF_ATK_EQ_DEF": ["number", "number", "number"],
    "IF_ATK_LT_DEF": ["number", "number", "number"],
    "IF_HOLD_ITEM": ["item", "number", "number"],
    "IF_PID_UPPER_MODULO_10_GT": ["number", "number", "number"],
    "IF_PID_UPPER_MODULO_10_EQ": ["number", "number", "number"],
    "IF_PID_UPPER_MODULO_10_LT": ["number", "number", "number"],
    "IF_MIN_BEAUTY": ["contest_condition", "number", "number"],
    "IF_MIN_COOLNESS": ["contest_condition", "number", "number"],
    "IF_MIN_SMARTNESS": ["contest_condition", "number", "number"],
    "IF_MIN_TOUGHNESS": ["contest_condition", "number", "number"],
    "IF_MIN_CUTENESS": ["contest_condition", "number", "number"],
    "IF_SPECIES_IN_PARTY": ["species", "number", "number"],
    "IF_IN_MAP": ["map", "number", "number"],
    "IF_IN_MAPSEC": ["map_section", "number", "number"],
    "IF_KNOWS_MOVE": ["move", "number", "number"],
    "IF_TRADE_PARTNER_SPECIES": ["species", "number", "number"],
    "IF_TYPE_IN_PARTY": ["type", "number", "number"],
    "IF_WEATHER": ["weather", "number", "number"],
    "IF_KNOWS_MOVE_TYPE": ["type", "number", "number"],
    "IF_NATURE": ["nature", "number", "number"],
    "IF_AMPED_NATURE": ["number", "number", "number"],
    "IF_LOW_KEY_NATURE": ["number", "number", "number"],
    "IF_RECOIL_DAMAGE_GE": ["battle_tracker", "number", "number"],
    "IF_CURRENT_DAMAGE_GE": ["damage_threshold", "number", "number"],
    "IF_CRITICAL_HITS_GE": ["battle_tracker", "number", "number"],
    "IF_USED_MOVE_X_TIMES": ["move", "count", "number"],
    "IF_DEFEAT_X_WITH_ITEMS": ["species", "item", "count"],
    "IF_PID_MODULO_100_GT": ["number", "number", "number"],
    "IF_PID_MODULO_100_EQ": ["number", "number", "number"],
    "IF_PID_MODULO_100_LT": ["number", "number", "number"],
    "IF_MIN_OVERWORLD_STEPS": ["step_count", "number", "number"],
    "IF_BAG_ITEM_COUNT": ["item", "count", "number"],
    "IF_REGION": ["region", "number", "number"],
    "IF_NOT_REGION": ["region", "number", "number"],
}


def _load_evolution_macro_expressions(root):
    macros = _load_macro_expressions(root)
    _read_defines_into(root / "include/constants/moves.h", macros)
    _read_defines_into(root / "include/constants/items.h", macros)
    _read_defines_into(root / "include/constants/weather.h", macros)
    _read_defines_into(root / "include/constants/regions.h", macros)
    _read_defines_into(root / "include/constants/rtc.h", macros)
    _read_defines_into(root / "src/pokemon.c", macros)
    return macros


def _load_evolution_constants(root, macros):
    species_constants = _load_species_constants_for_evolutions(root, macros)
    map_constants = _load_map_constants(root)
    constants = dict(species_constants)
    constants.update({
        "evolution_conditions": _parse_enum_constants(root / "include/constants/pokemon.h", "EvolutionConditions", macros),
        "evolution_methods": _parse_enum_constants(root / "include/constants/pokemon.h", "EvolutionMethods", macros),
        "evolution_modes": _parse_enum_constants(root / "include/constants/pokemon.h", "EvolutionMode", macros),
        "spin_directions": _parse_enum_constants(root / "include/constants/pokemon.h", "EvoSpinDirections", macros),
        "moves": _parse_enum_constants(root / "include/constants/moves.h", "Move", macros),
        "natures": _parse_define_constants(root / "include/constants/pokemon.h", "NATURE_", macros),
        "time_of_day": _parse_enum_constants(root / "include/constants/rtc.h", "TimeOfDay", macros),
        "weather": _parse_define_constants(root / "include/constants/weather.h", "WEATHER_", macros),
        "regions": _parse_enum_constants(root / "include/constants/regions.h", "Region", macros),
        "map_sections": _load_map_section_constants(root),
        "maps": {symbol: record["value"] for symbol, record in map_constants["maps"].items()},
        "map_records": map_constants["maps"],
        "map_group_order": map_constants["group_order"],
        "evaluator": ExpressionEvaluator(macros),
    })
    return constants


def _load_species_constants_for_evolutions(root, macros):
    from export_species import load_species_constants

    return load_species_constants(root, macros)


def _load_map_section_constants(root):
    path = root / "src/data/region_map/region_map_sections.json"
    data = load_json(path)
    constants = {}
    sections = data.get("map_sections", [])
    if isinstance(sections, list):
        for index, section in enumerate(sections):
            if not isinstance(section, dict):
                continue
            symbol = section.get("id")
            if symbol:
                constants[symbol] = int(index)
    constants["MAPSEC_NONE"] = len(constants)
    constants["MAPSEC_COUNT"] = len(constants)
    return constants


def _parse_macro_arguments(raw, macro_name):
    compact = _compact_source(raw)
    match = re.match(r"{}\s*\(".format(re.escape(macro_name)), compact)
    if not match:
        return None
    open_index = compact.find("(", match.start())
    close_index = _find_matching_delimiter(compact, open_index, "(", ")")
    if close_index == -1:
        return None
    body = compact[open_index + 1:close_index]
    return [_compact_source(item) for item in _split_top_level(body, ",") if item.strip()]


def _find_matching_delimiter(text, open_index, open_char, close_char):
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
        elif char == open_char:
            depth += 1
        elif char == close_char:
            depth -= 1
            if depth == 0:
                return index
    return -1


def _strip_outer_braces(raw):
    compact = _compact_source(raw)
    if not compact.startswith("{") or not compact.endswith("}"):
        return None
    close_index = _find_matching_delimiter(compact, 0, "{", "}")
    if close_index != len(compact) - 1:
        return None
    return compact[1:-1]


def _parse_evolution_entry(raw, index, constants):
    warnings = []
    compact = _compact_source(raw)
    body = _strip_outer_braces(compact)
    if body is None:
        return {
            "index": index,
            "raw": compact,
            "evaluation_status": "partial",
            "warnings": ["evolution entry is not a brace initializer"],
        }

    fields = [_compact_source(item) for item in _split_top_level(body, ",")]
    if len(fields) < 3:
        return {
            "index": index,
            "raw": compact,
            "fields": fields,
            "evaluation_status": "partial",
            "warnings": ["evolution entry has fewer than 3 fields"],
        }

    evaluator = constants["evaluator"]
    method = _constant_record(fields[0], constants["evolution_methods"], "EVO_", evaluator, warnings)
    method_symbol = method.get("symbol")
    param = _parse_typed_value(fields[1], _method_param_kind(method_symbol), constants, warnings)
    target_species = _constant_record(fields[2], constants["species"], "SPECIES_", evaluator, warnings)
    conditions = []
    for extra in fields[3:]:
        extra_compact = _compact_source(extra)
        if extra_compact.startswith("CONDITIONS"):
            conditions.extend(_parse_conditions(extra_compact, constants, warnings))
        elif extra_compact not in {"0", "NULL"}:
            warnings.append("unsupported evolution extra field: {}".format(extra_compact))

    record = {
        "index": index,
        "raw": compact,
        "method": method,
        "param": param,
        "target_species": target_species,
        "conditions": conditions,
        "condition_count": len(conditions),
        "runtime_modes": METHOD_RUNTIME_MODES.get(method_symbol, []),
        "runtime_handlers": METHOD_RUNTIME_HANDLERS.get(method_symbol, []),
        "source_runtime_rule": _source_runtime_rule(method_symbol),
        "preserves_source_order": True,
    }
    if warnings:
        record["warnings"] = sorted(set(warnings))
    record["evaluation_status"] = "partial" if warnings else "ok"
    return record


def _method_param_kind(method_symbol):
    return METHOD_PARAM_KINDS.get(method_symbol, "number")


def _source_runtime_rule(method_symbol):
    if method_symbol == "EVO_SPLIT_FROM_EVO":
        return "src/evolution_scene.c:TryCreateSplitEvoMon checks param against the post-evolution species."
    if method_symbol == "EVO_NONE":
        return "Sentinel or non-runtime evolution method."
    return "src/pokemon.c:GetEvolutionTargetSpecies checks the primary method before additional conditions."


def _parse_conditions(raw, constants, warnings):
    args = _parse_macro_arguments(raw, "CONDITIONS")
    if args is None:
        warnings.append("could not parse CONDITIONS expression: {}".format(raw))
        return []

    result = []
    for index, item in enumerate(args):
        result.append(_parse_condition_entry(item, index, constants, warnings))
    return result


def _parse_condition_entry(raw, index, constants, parent_warnings):
    warnings = []
    compact = _compact_source(raw)
    body = _strip_outer_braces(compact)
    if body is None:
        return {
            "index": index,
            "raw": compact,
            "evaluation_status": "partial",
            "warnings": ["condition entry is not a brace initializer"],
        }

    fields = [_compact_source(item) for item in _split_top_level(body, ",")]
    if not fields or not fields[0]:
        return {
            "index": index,
            "raw": compact,
            "evaluation_status": "partial",
            "warnings": ["condition entry has no condition field"],
        }

    evaluator = constants["evaluator"]
    condition = _constant_record(fields[0], constants["evolution_conditions"], "IF_", evaluator, warnings)
    condition_symbol = condition.get("symbol")
    kinds = CONDITION_ARG_KINDS.get(condition_symbol, ["number", "number", "number"])
    raw_args = list(fields[1:])
    while len(raw_args) < len(EVOLUTION_PARAM_FIELDS):
        raw_args.append("0")

    arg_records = []
    for arg_index, field_name in enumerate(EVOLUTION_PARAM_FIELDS):
        kind = kinds[arg_index] if arg_index < len(kinds) else "number"
        raw_arg = raw_args[arg_index] if arg_index < len(raw_args) else "0"
        record = _parse_typed_value(raw_arg, kind, constants, warnings)
        record["field"] = field_name
        if arg_index >= len(fields) - 1:
            record["defaulted"] = True
        arg_records.append(record)

    record = {
        "index": index,
        "raw": compact,
        "condition": condition,
        "args": arg_records,
        "arg1": arg_records[0],
        "arg2": arg_records[1],
        "arg3": arg_records[2],
        "source_runtime_rule": "src/pokemon.c:DoesMonMeetAdditionalConditions",
    }
    if warnings:
        record["warnings"] = sorted(set(warnings))
        parent_warnings.extend(warnings)
    record["evaluation_status"] = "partial" if warnings else "ok"
    return record


def _parse_typed_value(raw, kind, constants, warnings):
    compact = _compact_source(raw)
    evaluator = constants["evaluator"]
    if kind == "species":
        return _typed_constant_record(compact, kind, constants["species"], "SPECIES_", evaluator, warnings)
    if kind == "item":
        return _typed_constant_record(compact, kind, constants["items"], "ITEM_", evaluator, warnings)
    if kind == "move":
        return _typed_constant_record(compact, kind, constants["moves"], "MOVE_", evaluator, warnings)
    if kind == "type":
        return _typed_constant_record(compact, kind, constants["types"], "TYPE_", evaluator, warnings)
    if kind == "gender":
        return _typed_constant_record(compact, kind, constants["genders"], "MON_", evaluator, warnings)
    if kind == "time_of_day":
        return _typed_constant_record(compact, kind, constants["time_of_day"], "TIME_", evaluator, warnings)
    if kind == "weather":
        return _typed_constant_record(compact, kind, constants["weather"], "WEATHER_", evaluator, warnings)
    if kind == "nature":
        return _typed_constant_record(compact, kind, constants["natures"], "NATURE_", evaluator, warnings)
    if kind == "region":
        return _typed_constant_record(compact, kind, constants["regions"], "REGION_", evaluator, warnings)
    if kind == "map_section":
        return _typed_constant_record(compact, kind, constants["map_sections"], "MAPSEC_", evaluator, warnings)
    if kind == "map":
        record = _typed_constant_record(compact, kind, constants["maps"], "MAP_", evaluator, warnings)
        map_record = constants["map_records"].get(record.get("symbol"))
        if isinstance(map_record, dict):
            record["group"] = map_record.get("group")
            record["num"] = map_record.get("num")
            record["folder"] = map_record.get("folder")
            record["source"] = map_record.get("source")
        return record
    if kind == "spin_direction":
        return _typed_constant_record(compact, kind, constants["spin_directions"], "SPIN_", evaluator, warnings)

    value = _eval_field_int(compact, evaluator, warnings)
    return {
        "kind": kind,
        "raw": compact,
        "value": value,
    }


def _typed_constant_record(raw, kind, constants, prefix, evaluator, warnings):
    record = _constant_record(raw, constants, prefix, evaluator, warnings)
    record["kind"] = kind
    return record


def _build_species_evolution_record(root, species_symbol, species_record, evolution_raw, constants):
    warnings = []
    args = _parse_macro_arguments(evolution_raw, "EVOLUTION")
    if args is None:
        return {
            "species": _constant_record(species_symbol, constants["species"], "SPECIES_", constants["evaluator"], warnings),
            "species_symbol": species_symbol,
            "source": species_record.get("source", {}),
            "raw": _compact_source(evolution_raw),
            "evolutions": [],
            "evolution_count": 0,
            "evaluation_status": "partial",
            "warnings": ["could not parse EVOLUTION expression"],
        }

    evolutions = []
    for index, item in enumerate(args):
        evolutions.append(_parse_evolution_entry(item, index, constants))

    for evolution in evolutions:
        warnings.extend(evolution.get("warnings", []))

    record = {
        "species": _constant_record(species_symbol, constants["species"], "SPECIES_", constants["evaluator"], warnings),
        "species_symbol": species_symbol,
        "source": species_record.get("source", {}),
        "raw": _compact_source(evolution_raw),
        "evolutions": evolutions,
        "evolution_count": len(evolutions),
        "condition_count": sum(evolution.get("condition_count", 0) for evolution in evolutions),
        "preserves_source_order": True,
    }
    if warnings:
        record["warnings"] = sorted(set(warnings))
    record["evaluation_status"] = "partial" if warnings else "ok"
    return record


def _build_pre_evolution_index(evolutions_by_species):
    result = {}
    for species_symbol, record in evolutions_by_species.items():
        source_species = record.get("species", {})
        for evolution in record.get("evolutions", []):
            target = evolution.get("target_species", {})
            target_symbol = target.get("symbol")
            if not target_symbol:
                continue
            result.setdefault(target_symbol, []).append({
                "source_species": source_species,
                "source_species_symbol": species_symbol,
                "evolution_index": evolution.get("index"),
                "method": evolution.get("method", {}),
                "param": evolution.get("param", {}),
                "condition_count": evolution.get("condition_count", 0),
            })
    return {
        symbol: records
        for symbol, records in sorted(
            result.items(),
            key=lambda item: (
                records_min_source_id(item[1]),
                item[0],
            ),
        )
    }


def records_min_source_id(records):
    values = []
    for record in records:
        source = record.get("source_species", {})
        if isinstance(source, dict) and source.get("value") is not None:
            values.append(int(source.get("value")))
    return min(values) if values else 999999


def _collect_stats(species, evolutions_by_species, preprocessor_report):
    method_counts = {}
    condition_counts = {}
    entry_count = 0
    condition_entry_count = 0
    species_with_conditions = 0
    warning_count = len(preprocessor_report["warnings"])
    unresolved_value_count = 0
    split_evolution_count = 0
    sentinel_or_none_count = 0

    for record in evolutions_by_species.values():
        warning_count += len(record.get("warnings", []))
        if record.get("condition_count", 0) > 0:
            species_with_conditions += 1
        for evolution in record.get("evolutions", []):
            entry_count += 1
            method_symbol = evolution.get("method", {}).get("symbol", "")
            if method_symbol:
                method_counts[method_symbol] = method_counts.get(method_symbol, 0) + 1
            if method_symbol == "EVO_SPLIT_FROM_EVO":
                split_evolution_count += 1
            if method_symbol == "EVO_NONE" or evolution.get("target_species", {}).get("symbol") == "SPECIES_NONE":
                sentinel_or_none_count += 1
            unresolved_value_count += _count_unresolved_values(evolution)
            for condition in evolution.get("conditions", []):
                condition_entry_count += 1
                condition_symbol = condition.get("condition", {}).get("symbol", "")
                if condition_symbol:
                    condition_counts[condition_symbol] = condition_counts.get(condition_symbol, 0) + 1

    return {
        "active_species_count": len(species),
        "species_with_evolutions_count": len(evolutions_by_species),
        "evolution_entry_count": entry_count,
        "condition_entry_count": condition_entry_count,
        "species_with_condition_count": species_with_conditions,
        "split_evolution_count": split_evolution_count,
        "sentinel_or_none_target_count": sentinel_or_none_count,
        "method_counts": dict(sorted(method_counts.items())),
        "condition_counts": dict(sorted(condition_counts.items())),
        "preprocessor_decision_count": len(preprocessor_report["decisions"]),
        "preprocessor_warning_count": len(preprocessor_report["warnings"]),
        "warning_count": warning_count,
        "unresolved_value_count": unresolved_value_count,
    }


def _count_unresolved_values(value):
    if isinstance(value, dict):
        count = 0
        if "value" in value and value.get("value") is None:
            count += 1
        for item in value.values():
            count += _count_unresolved_values(item)
        return count
    if isinstance(value, list):
        return sum(_count_unresolved_values(item) for item in value)
    return 0


def export_evolutions(root):
    macros = _load_evolution_macro_expressions(root)
    constants = _load_evolution_constants(root, macros)
    source_records = _expand_species_info_includes(root, Path("src/data/pokemon/species_info.h"))
    preprocessed_records, preprocessor_report = _preprocess_records(source_records, macros)
    species, species_order = _parse_species_entries(root, preprocessed_records, constants)

    evolutions_by_species = {}
    evolution_species_order = []
    for species_symbol in species_order:
        species_record = species[species_symbol]
        source_references = species_record.get("source_references", {})
        if not isinstance(source_references, dict):
            continue
        evolution_raw = source_references.get("evolutions")
        if not evolution_raw:
            continue
        record = _build_species_evolution_record(root, species_symbol, species_record, evolution_raw, constants)
        evolutions_by_species[species_symbol] = record
        evolution_species_order.append(species_symbol)

    pre_evolutions_by_species = _build_pre_evolution_index(evolutions_by_species)
    stats = _collect_stats(species, evolutions_by_species, preprocessor_report)

    return {
        "schema_version": 1,
        "source": {
            "project": "pokeemerald-expansion",
            "species_info": "src/data/pokemon/species_info.h and included src/data/pokemon/species_info/*.h",
            "macro_definitions": {
                "EVOLUTION": "src/data/pokemon/species_info.h",
                "CONDITIONS": "src/data/pokemon/species_info.h",
            },
            "struct_definitions": [
                "include/pokemon.h:struct Evolution",
                "include/pokemon.h:struct EvolutionParam",
                "include/pokemon.h:struct SpeciesInfo.evolutions",
            ],
            "constants": [
                "include/constants/pokemon.h",
                "include/constants/species.h",
                "include/constants/items.h",
                "include/constants/moves.h",
                "include/constants/rtc.h",
                "include/constants/weather.h",
                "include/constants/regions.h",
                "src/data/region_map/region_map_sections.json",
                "data/maps/map_groups.json",
            ],
            "runtime_references": [
                "src/pokemon.c:GetSpeciesEvolutions",
                "src/pokemon.c:GetEvolutionTargetSpecies",
                "src/pokemon.c:DoesMonMeetAdditionalConditions",
                "src/pokemon.c:GetSpeciesPreEvolution",
                "src/pokemon.c:IsMonPastEvolutionLevel",
                "src/pokemon.c:TryScriptEvolution",
                "src/pokemon.c:TrySpecialOverworldEvo",
                "src/battle_main.c:TryEvolvePokemon",
                "src/evolution_scene.c",
                "src/evolution_scene.c:TryCreateSplitEvoMon",
                "src/party_menu.c",
                "src/trade.c",
                "src/battle_util.c:TryUpdateEvolutionTracker",
                "src/move_relearner.c",
                "src/pokedex_plus_hgss.c",
            ],
            "source_behavior_notes": [
                "GetEvolutionTargetSpecies preserves source order and stops at the first matching evolution.",
                "DoesMonMeetAdditionalConditions may remove held or bag items when evoState is DO_EVO.",
                "Everstone prevention and Gigantamax exceptions are runtime behavior, not data filtering.",
                "EVO_SPLIT_FROM_EVO is handled by the evolution scene after another evolution succeeds.",
            ],
            "preprocessor": preprocessor_report,
        },
        "constants": {
            "evolution_methods": _export_constant_group(constants["evolution_methods"], "EVO_"),
            "evolution_conditions": _export_constant_group(constants["evolution_conditions"], "IF_"),
            "evolution_modes": _export_constant_group(constants["evolution_modes"], "EVO_MODE_"),
            "spin_directions": _export_constant_group(constants["spin_directions"], "SPIN_"),
            "map_sections": _export_constant_group(constants["map_sections"], "MAPSEC_"),
            "regions": _export_constant_group(constants["regions"], "REGION_"),
            "time_of_day": _export_constant_group(constants["time_of_day"], "TIME_"),
        },
        "map_constants": constants["map_records"],
        "evolution_species_order": evolution_species_order,
        "evolutions_by_species": evolutions_by_species,
        "pre_evolutions_by_species": pre_evolutions_by_species,
        "stats": stats,
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

    exported = export_evolutions(source_root)
    evolutions_output = output_root / "pokemon" / "evolutions.json"
    write_json(evolutions_output, exported)

    stats = exported["stats"]
    manifest_entry = {
        "category": "evolutions",
        "path": to_project_path(evolutions_output),
        "species_with_evolutions_count": stats["species_with_evolutions_count"],
        "evolution_entry_count": stats["evolution_entry_count"],
        "condition_entry_count": stats["condition_entry_count"],
        "warning_count": stats["warning_count"],
        "unresolved_value_count": stats["unresolved_value_count"],
    }
    write_manifest(
        output_root / "import_manifest.json",
        exported_pokemon=[manifest_entry],
        generator="tools/importer/export_evolutions.py",
    )

    print(json.dumps({
        "exported": manifest_entry,
        "method_counts": stats["method_counts"],
        "condition_counts": stats["condition_counts"],
        "preprocessor_decision_count": stats["preprocessor_decision_count"],
    }, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
