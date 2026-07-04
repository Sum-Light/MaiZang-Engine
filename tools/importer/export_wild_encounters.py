#!/usr/bin/env python3
"""Export pokeemerald-expansion wild encounter tables into generated JSON."""

import argparse
import json
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

from export_map import write_json, write_manifest
from export_species import (
    ExpressionEvaluator,
    _export_constant_group,
    _load_macro_expressions,
    _parse_define_constants,
    _parse_enum_constants,
    _read_defines_into,
)
from source_probe import load_config, to_project_path


FIELD_DEFINITIONS = {
    "land_mons": {
        "source_member": "landMonsInfo",
        "area_symbol": "WILD_AREA_LAND",
        "slot_count_symbol": "LAND_WILD_COUNT",
        "selector": "ChooseWildMonIndex_Land",
        "slot_rates": [20, 20, 10, 10, 10, 10, 5, 5, 4, 4, 1, 1],
    },
    "water_mons": {
        "source_member": "waterMonsInfo",
        "area_symbol": "WILD_AREA_WATER",
        "slot_count_symbol": "WATER_WILD_COUNT",
        "selector": "ChooseWildMonIndex_WaterRock",
        "slot_rates": [60, 30, 5, 4, 1],
    },
    "rock_smash_mons": {
        "source_member": "rockSmashMonsInfo",
        "area_symbol": "WILD_AREA_ROCKS",
        "slot_count_symbol": "ROCK_WILD_COUNT",
        "selector": "ChooseWildMonIndex_WaterRock",
        "slot_rates": [60, 30, 5, 4, 1],
    },
    "fishing_mons": {
        "source_member": "fishingMonsInfo",
        "area_symbol": "WILD_AREA_FISHING",
        "slot_count_symbol": "FISH_WILD_COUNT",
        "selector": "ChooseWildMonIndex_Fishing",
        "slot_rates": [70, 30, 60, 20, 20, 40, 40, 15, 4, 1],
        "rod_groups": {
            "old_rod": [0, 1],
            "good_rod": [2, 3, 4],
            "super_rod": [5, 6, 7, 8, 9],
        },
    },
    "hidden_mons": {
        "source_member": "hiddenMonsInfo",
        "area_symbol": "WILD_AREA_HIDDEN",
        "slot_count_symbol": "HIDDEN_WILD_COUNT",
        "selector": "DexNav hidden encounter selection",
        "slot_rates": [100, 0, 0],
    },
}

RUNTIME_REFERENCES = [
    "src/wild_encounter.c",
    "include/wild_encounter.h",
    "tools/wild_encounters/wild_encounters_to_header.py",
    "src/field_control_avatar.c",
    "src/metatile_behavior.c",
    "src/dexnav.c",
    "src/pokedex_area_screen.c",
    "src/match_call.c",
    "src/fishing.c",
    "src/fldeff_sweetscent.c",
    "src/battle_setup.c",
    "src/roamer.c",
    "src/battle_pike.c",
    "src/battle_pyramid.c",
]

CONSTANT_REFERENCES = [
    "include/constants/wild_encounter.h",
    "include/constants/rtc.h",
    "include/config/overworld.h",
    "include/config/dexnav.h",
    "include/constants/species.h",
    "include/wild_encounter.h",
    "data/maps/map_groups.json",
    "tools/mapjson/required_map_defines.json",
]


def load_json(path):
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def _cumulative(values):
    total = 0
    result = []
    for value in values:
        total += int(value)
        result.append(total)
    return result


def _constant_name(symbol, prefix):
    if symbol and symbol.startswith(prefix):
        return symbol[len(prefix):].lower()
    return str(symbol).lower()


def _constant_record(symbol, constants, prefix=""):
    if not symbol:
        return {
            "symbol": symbol,
            "value": None,
            "name": "",
        }
    value = constants.get(symbol)
    return {
        "symbol": symbol,
        "value": int(value) if isinstance(value, int) else None,
        "name": _constant_name(symbol, prefix),
    }


def _parse_selected_defines(path, names, macros):
    raw_macros = {}
    _read_defines_into(path, raw_macros)
    for name, value in raw_macros.items():
        if name in names:
            macros[name] = value

    evaluator = ExpressionEvaluator(macros)
    constants = {}
    for name in names:
        if name not in raw_macros:
            continue
        value = evaluator.eval_int(raw_macros[name])
        if value is not None:
            constants[name] = int(value)
            macros[name] = str(int(value))
    return constants


def _parse_raw_defines(path, names):
    raw_macros = {}
    _read_defines_into(path, raw_macros)
    return {name: raw_macros.get(name) for name in names if name in raw_macros}


def _bool_macro(raw_value):
    if raw_value is None:
        return None
    normalized = str(raw_value).strip()
    if normalized == "TRUE":
        return True
    if normalized == "FALSE":
        return False
    evaluator = ExpressionEvaluator({"TRUE": "1", "FALSE": "0"}, unknown_as_zero=True)
    value = evaluator.eval_int(normalized)
    return bool(value) if value is not None else None


def _load_constants(root):
    macros = _load_macro_expressions(root)
    _read_defines_into(root / "include/config/dexnav.h", macros)
    _read_defines_into(root / "include/constants/wild_encounter.h", macros)
    _read_defines_into(root / "include/constants/rtc.h", macros)

    wild_counts = _parse_selected_defines(
        root / "include/constants/wild_encounter.h",
        [
            "LAND_WILD_COUNT",
            "WATER_WILD_COUNT",
            "ROCK_WILD_COUNT",
            "FISH_WILD_COUNT",
            "HIDDEN_WILD_COUNT",
            "NUM_ALTERING_CAVE_TABLES",
        ],
        macros,
    )
    species = _parse_define_constants(root / "include/constants/species.h", "SPECIES_", macros)
    time_of_day = _parse_enum_constants(root / "include/constants/rtc.h", "TimeOfDay", macros)
    wild_areas = _parse_enum_constants(root / "include/wild_encounter.h", "WildPokemonArea", macros)
    config_raw = _parse_raw_defines(
        root / "include/config/overworld.h",
        [
            "OW_TIME_OF_DAY_ENCOUNTERS",
            "OW_TIME_OF_DAY_DISABLE_FALLBACK",
            "OW_TIME_OF_DAY_FALLBACK",
            "OW_FLAG_NO_ENCOUNTER",
        ],
    )
    dexnav_raw = _parse_raw_defines(root / "include/config/dexnav.h", ["DEXNAV_ENABLED"])

    evaluator = ExpressionEvaluator(macros, unknown_as_zero=True)
    return {
        "macros": macros,
        "evaluator": evaluator,
        "species": species,
        "time_of_day": time_of_day,
        "wild_areas": wild_areas,
        "wild_counts": wild_counts,
        "config_raw": config_raw,
        "dexnav_raw": dexnav_raw,
    }


def _time_display_names(time_constants):
    names = {}
    for symbol in sorted(time_constants.keys(), key=lambda item: time_constants[item]):
        if symbol == "TIMES_OF_DAY_COUNT":
            continue
        display_source = symbol[len("TIME_"):] if symbol.startswith("TIME_") else symbol
        display = display_source.title().replace("_", "")
        names[symbol] = display
    return names


def _time_config(constants):
    config = constants["config_raw"]
    time_constants = constants["time_of_day"]
    time_encounters = _bool_macro(config.get("OW_TIME_OF_DAY_ENCOUNTERS"))
    disable_fallback = _bool_macro(config.get("OW_TIME_OF_DAY_DISABLE_FALLBACK"))
    fallback_symbol = config.get("OW_TIME_OF_DAY_FALLBACK", "TIME_MORNING")
    default_value = constants["evaluator"].eval_int("TIME_OF_DAY_DEFAULT")
    generated_times = []

    if time_encounters:
        generated_times = [
            symbol
            for symbol in sorted(time_constants.keys(), key=lambda item: time_constants[item])
            if symbol != "TIMES_OF_DAY_COUNT"
        ]
    else:
        generated_times = [fallback_symbol]

    return {
        "time_of_day_encounters": bool(time_encounters),
        "disable_time_fallback": bool(disable_fallback),
        "fallback": _constant_record(fallback_symbol, time_constants, "TIME_"),
        "runtime_default_time": {
            "symbol": "TIME_OF_DAY_DEFAULT",
            "value": int(default_value) if default_value is not None else None,
            "name": "of_day_default",
        },
        "generated_header_times": [
            _constant_record(symbol, time_constants, "TIME_")
            for symbol in generated_times
        ],
        "all_times": [
            _constant_record(symbol, time_constants, "TIME_")
            for symbol in sorted(time_constants.keys(), key=lambda item: time_constants[item])
        ],
    }


def _load_map_constants(root):
    groups_data = load_json(root / "data/maps/map_groups.json")
    result = {}
    group_order = groups_data.get("group_order", [])
    for group_index, group_name in enumerate(group_order):
        folders = groups_data.get(group_name, [])
        if not isinstance(folders, list):
            continue
        for map_index, folder in enumerate(folders):
            map_path = root / "data/maps" / folder / "map.json"
            if not map_path.exists():
                continue
            map_data = load_json(map_path)
            symbol = map_data.get("id")
            if not symbol:
                continue
            result[symbol] = {
                "symbol": symbol,
                "value": int(map_index | (group_index << 8)),
                "group": group_index,
                "num": map_index,
                "group_symbol": group_name,
                "folder": folder,
                "name": map_data.get("name"),
                "source": to_project_path(map_path.relative_to(root)),
            }

    required_path = root / "tools/mapjson/required_map_defines.json"
    if required_path.exists():
        required = load_json(required_path).get("required_maps", [])
        map_index = 0
        previous_group = None
        for item in required:
            if not isinstance(item, list) or len(item) < 2:
                continue
            symbol = item[0]
            group_index = int(item[1])
            if previous_group != group_index:
                map_index = 0
            else:
                map_index += 1
            if symbol not in result:
                result[symbol] = {
                    "symbol": symbol,
                    "value": int(map_index | (group_index << 8)),
                    "group": group_index,
                    "num": map_index,
                    "group_symbol": None,
                    "folder": None,
                    "name": None,
                    "source": "tools/mapjson/required_map_defines.json",
                    "required_define_only": True,
                }
            previous_group = group_index

    return {
        "maps": result,
        "group_order": group_order,
    }


def _field_definitions(constants, encountered_field_types):
    wild_counts = constants["wild_counts"]
    wild_areas = constants["wild_areas"]
    fields = {}
    for field_name, definition in FIELD_DEFINITIONS.items():
        if field_name not in encountered_field_types and field_name != "hidden_mons":
            continue
        slot_rates = definition["slot_rates"]
        record = {
            "source_field": field_name,
            "source_member": definition["source_member"],
            "area": _constant_record(definition["area_symbol"], wild_areas, "WILD_AREA_"),
            "slot_count_constant": _constant_record(definition["slot_count_symbol"], wild_counts),
            "selector": definition["selector"],
            "slot_rates": [
                {
                    "slot": index,
                    "rate": int(rate),
                    "cumulative_threshold": threshold,
                }
                for index, (rate, threshold) in enumerate(zip(slot_rates, _cumulative(slot_rates)))
            ],
            "total_rate": int(sum(slot_rates)),
        }
        if "rod_groups" in definition:
            groups = {}
            for group_name, indices in definition["rod_groups"].items():
                rates = [slot_rates[index] for index in indices]
                groups[group_name] = {
                    "indices": indices,
                    "rates": rates,
                    "cumulative_thresholds": _cumulative(rates),
                    "total_rate": int(sum(rates)),
                }
            record["rod_groups"] = groups
            record["global_slot_thresholds_are_not_used_for_rod_groups"] = True
        fields[field_name] = record
    return fields


def _record_id(base_label, seen):
    count = seen[base_label]
    seen[base_label] += 1
    return base_label if count == 0 else "{}__{}".format(base_label, count + 1)


def _version_from_label(label):
    if "LeafGreen" in label:
        return "leaf_green"
    if "FireRed" in label:
        return "fire_red"
    return None


def _shared_label_and_time(base_label, time_names, fallback_symbol):
    shared_label = base_label
    time_symbol = fallback_symbol
    for candidate_symbol, display_name in time_names.items():
        marker = "_" + display_name
        if marker in base_label:
            time_symbol = candidate_symbol
            shared_label = shared_label.replace(marker, "")
            break
    return shared_label, time_symbol


def _slot_record(slot_index, raw_slot, species_constants, warnings):
    species_symbol = raw_slot.get("species")
    species = _constant_record(species_symbol, species_constants, "SPECIES_")
    if species.get("value") is None:
        warnings.append("could not resolve species constant: {}".format(species_symbol))
    return {
        "slot": slot_index,
        "min_level": int(raw_slot.get("min_level", 0)),
        "max_level": int(raw_slot.get("max_level", 0)),
        "species": species,
    }


def _table_record(field_name, base_label, raw_table, species_constants, warnings):
    slots = [
        _slot_record(index, raw_slot, species_constants, warnings)
        for index, raw_slot in enumerate(raw_table.get("mons", []))
    ]
    return {
        "field": field_name,
        "encounter_rate": int(raw_table.get("encounter_rate", 0)),
        "source_info_label": "{}_{}Info".format(base_label, field_name.title().replace("_", "")),
        "source_mons_label": "{}_{}".format(base_label, field_name.title().replace("_", "")),
        "slots": slots,
    }


def _battle_map_record(map_counter):
    return {
        "symbol": None,
        "value": int(map_counter),
        "group": 0,
        "num": int(map_counter),
        "generated_counter": True,
    }


def _missing_map_record(symbol):
    return {
        "symbol": symbol,
        "value": None,
        "group": None,
        "num": None,
        "missing": True,
    }


def _build_encounters(root, raw_data, constants, map_constants, time_config):
    species_constants = constants["species"]
    maps = map_constants["maps"]
    warnings = []
    unsupported_fields = set()
    encountered_field_types = set()
    seen_record_ids = Counter()
    time_names = _time_display_names(constants["time_of_day"])
    fallback_symbol = time_config["fallback"]["symbol"]
    records = []
    groups = {}
    encounters_by_map = defaultdict(list)
    encounters_by_label = defaultdict(list)
    unique_species = set()
    table_counts = Counter()
    slot_counts = Counter()
    time_labeled_record_count = 0

    for group_index, group in enumerate(raw_data.get("wild_encounter_groups", [])):
        label = group.get("label", "wild_encounter_group_{}".format(group_index))
        for_maps = bool(group.get("for_maps", False))
        group_records = []
        map_counter = 1
        for encounter_index, raw_encounter in enumerate(group.get("encounters", [])):
            base_label = raw_encounter.get("base_label", "{}_{}".format(label, encounter_index))
            shared_label, time_symbol = _shared_label_and_time(base_label, time_names, fallback_symbol)
            if shared_label != base_label:
                time_labeled_record_count += 1
            record_id = _record_id(base_label, seen_record_ids)

            if for_maps:
                map_symbol = raw_encounter.get("map")
                map_info = dict(maps.get(map_symbol, _missing_map_record(map_symbol)))
                if map_info.get("missing"):
                    warnings.append("could not resolve map constant: {}".format(map_symbol))
            else:
                map_symbol = None
                map_info = _battle_map_record(map_counter)

            tables = {}
            for field_name, raw_table in raw_encounter.items():
                if not field_name.endswith("_mons"):
                    continue
                if field_name not in FIELD_DEFINITIONS:
                    unsupported_fields.add(field_name)
                    continue
                encountered_field_types.add(field_name)
                table = _table_record(field_name, base_label, raw_table, species_constants, warnings)
                expected_slots = FIELD_DEFINITIONS[field_name]["slot_rates"]
                if len(table["slots"]) != len(expected_slots):
                    warnings.append(
                        "{} {} has {} slots, expected {}".format(
                            base_label,
                            field_name,
                            len(table["slots"]),
                            len(expected_slots),
                        )
                    )
                tables[field_name] = table
                table_counts[field_name] += 1
                slot_counts[field_name] += len(table["slots"])
                for slot in table["slots"]:
                    species_symbol = slot.get("species", {}).get("symbol")
                    if species_symbol:
                        unique_species.add(species_symbol)

            record = {
                "id": record_id,
                "label": base_label,
                "shared_label": shared_label,
                "header_label": label,
                "header_group_index": group_index,
                "header_index": encounter_index,
                "source_index": encounter_index,
                "source_map_symbol": map_symbol,
                "map": map_info,
                "version": _version_from_label(base_label),
                "source_time": _constant_record(time_symbol, constants["time_of_day"], "TIME_"),
                "runtime_time": {
                    "symbol": "TIME_OF_DAY_DEFAULT",
                    "value": time_config["runtime_default_time"]["value"],
                    "name": "of_day_default",
                },
                "tables": tables,
                "source": {
                    "file": "src/data/wild_encounters.json",
                    "group_label": label,
                    "group_index": group_index,
                    "encounter_index": encounter_index,
                },
            }
            if not for_maps:
                record["header_map_counter"] = map_counter
            records.append(record)
            group_records.append(record["id"])
            encounters_by_label[base_label].append(record["id"])
            if map_symbol:
                encounters_by_map[map_symbol].append(record["id"])
            map_counter += 1

        groups[label] = {
            "label": label,
            "group_index": group_index,
            "for_maps": for_maps,
            "encounter_count": len(group_records),
            "record_ids": group_records,
            "fields": group.get("fields", []),
        }

    return {
        "records": records,
        "groups": groups,
        "encounters_by_map": {
            key: value
            for key, value in sorted(encounters_by_map.items())
        },
        "encounters_by_label": {
            key: value
            for key, value in sorted(encounters_by_label.items())
        },
        "encountered_field_types": sorted(encountered_field_types),
        "unsupported_fields": sorted(unsupported_fields),
        "warnings": sorted(set(warnings)),
        "stats": {
            "encounter_record_count": len(records),
            "map_encounter_count": sum(1 for record in records if record.get("source_map_symbol")),
            "group_count": len(groups),
            "table_counts": dict(sorted(table_counts.items())),
            "slot_counts": dict(sorted(slot_counts.items())),
            "mon_slot_count": sum(slot_counts.values()),
            "unique_species_count": len(unique_species),
            "duplicate_label_count": sum(max(0, count - 1) for count in seen_record_ids.values()),
            "time_labeled_record_count": time_labeled_record_count,
            "warning_count": len(set(warnings)),
            "unsupported_field_count": len(unsupported_fields),
        },
    }


def _special_cases(constants, records):
    altering_records = [
        record["id"]
        for record in records
        if record.get("source_map_symbol") == "MAP_ALTERING_CAVE"
    ]
    return {
        "altering_cave": {
            "source": "src/wild_encounter.c:GetCurrentMapWildMonHeaderId",
            "map": "MAP_ALTERING_CAVE",
            "variable": "VAR_ALTERING_CAVE_WILD_SET",
            "table_count_constant": _constant_record(
                "NUM_ALTERING_CAVE_TABLES",
                constants["wild_counts"],
            ),
            "record_ids": altering_records,
            "table_count": len(altering_records),
            "selection_rule": "header id is offset by VAR_ALTERING_CAVE_WILD_SET when it is below NUM_ALTERING_CAVE_TABLES",
        }
    }


def export_wild_encounters(root):
    raw_path = root / "src/data/wild_encounters.json"
    raw_data = load_json(raw_path)
    constants = _load_constants(root)
    map_constants = _load_map_constants(root)
    time_config = _time_config(constants)
    built = _build_encounters(root, raw_data, constants, map_constants, time_config)
    field_definitions = _field_definitions(constants, built["encountered_field_types"])

    stats = dict(built["stats"])
    stats.update({
        "field_definition_count": len(field_definitions),
        "map_constant_count": len(map_constants["maps"]),
        "active_generated_time_count": len(time_config["generated_header_times"]),
    })

    return {
        "schema_version": 1,
        "source": {
            "project": "pokeemerald-expansion",
            "wild_encounters_json": "src/data/wild_encounters.json",
            "generated_header": "src/data/wild_encounters.h",
            "generated_header_tool": "tools/wild_encounters/wild_encounters_to_header.py",
            "runtime_references": RUNTIME_REFERENCES,
            "constant_references": CONSTANT_REFERENCES,
        },
        "config": {
            "time": time_config,
            "dexnav_enabled": _bool_macro(constants["dexnav_raw"].get("DEXNAV_ENABLED")),
            "ow_flag_no_encounter": constants["config_raw"].get("OW_FLAG_NO_ENCOUNTER"),
            "gba_storage_limits_ignored_at_runtime": True,
            "godot_runtime_uses_decoded_source_assets": True,
        },
        "field_definitions": field_definitions,
        "groups": built["groups"],
        "encounters": built["records"],
        "encounters_by_map": built["encounters_by_map"],
        "encounters_by_label": built["encounters_by_label"],
        "special_cases": _special_cases(constants, built["records"]),
        "constants": {
            "wild_counts": _export_constant_group(constants["wild_counts"], ""),
            "wild_areas": _export_constant_group(constants["wild_areas"], "WILD_AREA_"),
            "times_of_day": _export_constant_group(constants["time_of_day"], "TIME_"),
            "species": _export_constant_group(constants["species"], "SPECIES_"),
            "maps_used": {
                symbol: map_constants["maps"][symbol]
                for symbol in sorted(built["encounters_by_map"].keys())
                if symbol in map_constants["maps"]
            },
        },
        "stats": stats,
        "reports": {
            "warnings": built["warnings"],
            "unsupported_fields": built["unsupported_fields"],
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

    exported = export_wild_encounters(source_root)
    output_path = output_root / "pokemon" / "wild_encounters.json"
    write_json(output_path, exported)

    stats = exported["stats"]
    manifest_entry = {
        "category": "wild_encounters",
        "path": to_project_path(output_path),
        "encounter_record_count": stats["encounter_record_count"],
        "map_encounter_count": stats["map_encounter_count"],
        "mon_slot_count": stats["mon_slot_count"],
        "unique_species_count": stats["unique_species_count"],
        "warning_count": stats["warning_count"],
    }
    write_manifest(
        output_root / "import_manifest.json",
        exported_pokemon=[manifest_entry],
        generator="tools/importer/export_wild_encounters.py",
    )

    print(json.dumps({
        "exported": manifest_entry,
        "table_counts": stats["table_counts"],
        "slot_counts": stats["slot_counts"],
    }, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
