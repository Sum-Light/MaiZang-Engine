#!/usr/bin/env python3
"""Smoke checks for the overworld map-load trace report."""

import argparse
import sys
from pathlib import Path

from export_overworld_map_load_trace import build_export
from source_probe import load_config


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, help="JSON config with source and output roots.")
    parser.add_argument("--source", type=Path, help="pokeemerald-expansion source root.")
    args = parser.parse_args(argv)

    config = load_config(args.config)
    source_root = args.source or Path(config.get("source_root", ""))
    exported = build_export(source_root)
    stats = exported["stats"]

    _assert(exported["schema_version"] == 1, "unexpected schema version")
    _assert(exported["generated_by"].endswith("export_overworld_map_load_trace.py"), "unexpected generator")
    _assert(stats["flow_count"] == 6, "unexpected flow count")
    _assert(stats["missing_source_file_count"] == 0, "missing source files")
    _assert(stats["missing_symbol_count"] == 0, "missing source symbols")
    _assert(stats["unsupported_count"] == 7, "unexpected unsupported count")
    _assert(stats["status_counts"].get("first_pass", 0) == 3, "unexpected first-pass count")
    _assert(stats["status_counts"].get("first_pass_metadata", 0) == 3, "unexpected metadata first-pass count")

    flows = {entry["id"]: entry for entry in exported["source_flows"]}
    for flow_id in [
        "camera_transition_load",
        "warp_load_core",
        "local_step_loader",
        "layout_onload_script",
        "map_script_dispatch_helpers",
        "field_callback_setup",
    ]:
        _assert(flow_id in flows, "missing flow %s" % flow_id)

    _assert(
        "RunOnTransitionMapScript" in flows["warp_load_core"]["critical_order"],
        "warp load should record OnTransition order",
    )
    _assert(
        any("InitMap" in item for item in flows["warp_load_core"]["critical_order"]),
        "warp load should record InitMap order",
    )
    _assert(
        "case 2: ResumeMap, including StartWeather/ResumePausedWeather/RunOnResumeMapScript"
        in flows["local_step_loader"]["critical_order"],
        "local step loader should record ResumeMap hook",
    )
    _assert(
        "RunOnLoadMapScript" in flows["layout_onload_script"]["critical_order"],
        "InitMap should record OnLoad hook",
    )
    _assert(
        "RunFieldCallback prefers gFieldCallback2, otherwise runs gFieldCallback or FieldCB_DefaultWarpExit, then clears callbacks"
        in flows["field_callback_setup"]["critical_order"],
        "field callback setup should record callback priority",
    )

    symbols = exported["required_symbols"]
    _assert(_has_occurrence(symbols, "LoadMapFromWarp", "src/overworld.c"), "missing LoadMapFromWarp occurrence")
    _assert(_has_occurrence(symbols, "InitMap", "src/fieldmap.c"), "missing InitMap occurrence")
    _assert(_has_occurrence(symbols, "RunOnTransitionMapScript", "src/script.c"), "missing RunOnTransition occurrence")
    _assert(_has_occurrence(symbols, "RunOnLoadMapScript", "src/script.c"), "missing RunOnLoad occurrence")

    unsupported_codes = {entry["code"] for entry in exported["unsupported"]}
    for code in [
        "resume_map_script_pending",
        "warp_into_map_table_pending",
        "field_callback_pipeline_pending",
        "weather_palette_load_pending",
        "tileset_animation_runtime_pending",
        "audio_playback_pending",
        "camera_backup_streaming_pending",
    ]:
        _assert(code in unsupported_codes, "missing unsupported code %s" % code)

    print("export_overworld_map_load_trace_smoke: ok")
    return 0


def _has_occurrence(symbols, symbol, source_file):
    for occurrence in symbols.get(symbol, []):
        if occurrence.get("file") == source_file:
            return True
    return False


def _assert(condition, message):
    if not condition:
        raise AssertionError(message)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
