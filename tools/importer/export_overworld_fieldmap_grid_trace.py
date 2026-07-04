#!/usr/bin/env python3
"""Export source-traced fieldmap grid, border, connection, and camera coverage."""

import argparse
import json
import re
import sys
from pathlib import Path

from export_map import write_json, write_manifest
from source_probe import load_config, to_project_path


GENERATED_BY = "tools/importer/export_overworld_fieldmap_grid_trace.py"
REPORT_PATH = Path("overworld/fieldmap_grid_trace.json")

SOURCE_FILES = [
    "src/fieldmap.c",
    "include/fieldmap.h",
    "include/global.fieldmap.h",
]

REQUIRED_SYMBOLS = [
    "MAP_OFFSET",
    "MAP_OFFSET_W",
    "MAP_OFFSET_H",
    "MAPGRID_METATILE_ID_MASK",
    "MAPGRID_COLLISION_MASK",
    "MAPGRID_ELEVATION_MASK",
    "MAPGRID_UNDEFINED",
    "MAPGRID_IMPASSABLE",
    "sBackupMapData",
    "gBackupMapLayout",
    "InitMapLayoutData",
    "InitBackupMapLayoutData",
    "InitBackupMapLayoutConnections",
    "FillSouthConnection",
    "FillNorthConnection",
    "FillWestConnection",
    "FillEastConnection",
    "GetBorderBlockAt",
    "GetMapGridBlockAt",
    "MapGridGetElevationAt",
    "MapGridGetCollisionAt",
    "MapGridGetMetatileIdAt",
    "MapGridGetMetatileBehaviorAt",
    "MapGridGetMetatileLayerTypeAt",
    "MapGridSetMetatileIdAt",
    "MapGridSetMetatileEntryAt",
    "MapGridSetMetatileImpassabilityAt",
    "SaveMapView",
    "LoadSavedMapView",
    "MoveMapViewToBackup",
    "GetMapBorderIdAt",
    "CanCameraMoveInDirection",
    "CameraMove",
    "GetIncomingConnection",
    "SetCameraFocusCoords",
    "GetCameraFocusCoords",
]

BIT_LAYOUT = {
    "map_grid_block_bits": 16,
    "metatile_id": {"mask": "0x03FF", "shift": 0, "bits": "0-9"},
    "collision": {"mask": "0x0C00", "shift": 10, "bits": "10-11"},
    "elevation": {"mask": "0xF000", "shift": 12, "bits": "12-15"},
    "undefined": "MAPGRID_METATILE_ID_MASK",
    "manual_impassable": "MAPGRID_COLLISION_MASK",
}

UNSUPPORTED = [
    {
        "code": "backup_map_buffer_runtime_pending",
        "status": "unsupported",
        "source": "src/fieldmap.c:sBackupMapData/gBackupMapLayout",
        "detail": "Godot reads generated map/border/connection data directly and does not yet model the source backup-map staging buffer as a runtime owner.",
    },
    {
        "code": "connection_fill_exact_pending",
        "status": "first_pass",
        "source": "src/fieldmap.c:FillNorthConnection/FillSouthConnection/FillWestConnection/FillEastConnection",
        "detail": "Godot can query generated connected-map fallback cells, but it does not yet reproduce the exact source copy windows and edge dimensions.",
    },
    {
        "code": "saved_map_view_restore_pending",
        "status": "unsupported",
        "source": "src/fieldmap.c:SaveMapView/LoadSavedMapView/MoveMapViewToBackup",
        "detail": "Source save/restore of the 15x14 view window, including long-grass repair, is not implemented in Godot save or transition paths.",
    },
    {
        "code": "source_camera_movement_pending",
        "status": "first_pass",
        "source": "src/fieldmap.c:CanCameraMoveInDirection/CameraMove",
        "detail": "Godot has first-pass map-connection transitions, but not the exact source camera active flag, incoming-connection search, saved-view shift, and post-move camera offset behavior.",
    },
    {
        "code": "mapgrid_impassability_runtime_pending",
        "status": "unsupported",
        "source": "src/fieldmap.c:MapGridSetMetatileImpassabilityAt",
        "detail": "Godot supports first-pass setmetatile grid mutation, but not the separate source helper that toggles all collision bits in-place.",
    },
    {
        "code": "fieldmap_layer_rules_pending",
        "status": "unsupported",
        "source": "include/global.fieldmap.h:METATILE_LAYER_TYPE_*",
        "detail": "Layer-type metadata is generated, but source-equivalent split/covered/normal rendering and player/object interleaving remain future presentation work.",
    },
]


def read_text(path):
    with path.open("r", encoding="utf-8") as handle:
        return handle.read()


def line_occurrences(text, symbol):
    pattern = re.compile(r"\b%s\b" % re.escape(symbol))
    return [
        index
        for index, line in enumerate(text.splitlines(), start=1)
        if pattern.search(line)
    ]


def source_file_presence(source_root):
    return [
        {
            "path": path,
            "exists": (source_root / path).exists(),
        }
        for path in SOURCE_FILES
    ]


def symbol_locations(source_root):
    result = {}
    file_texts = {}
    for path in SOURCE_FILES:
        full_path = source_root / path
        file_texts[path] = read_text(full_path) if full_path.exists() else ""

    for symbol in REQUIRED_SYMBOLS:
        occurrences = []
        for path, text in file_texts.items():
            for line in line_occurrences(text, symbol):
                occurrences.append({"file": path, "line": line})
        result[symbol] = occurrences
    return result


def source_flow_rows():
    return [
        {
            "id": "map_grid_bit_layout",
            "source_entry": "include/global.fieldmap.h:MAPGRID_*",
            "status": "ported_import",
            "critical_order": [
                "layout map.bin stores each block as u16",
                "bits 0-9 are metatile id",
                "bits 10-11 are collision",
                "bits 12-15 are elevation",
                "MAPGRID_UNDEFINED has all metatile-id bits set",
                "MAPGRID_IMPASSABLE sets all collision bits",
            ],
            "godot_current": [
                "tools/importer/export_map.py decodes raw u16 map.bin into raw, metatile id, collision, and elevation grids.",
                "MapRuntime exposes metatile id, collision, elevation, behavior, and layer-type lookups.",
            ],
            "gaps": [
                "MapRuntime does not yet expose every source helper that mutates collision bits independently.",
            ],
        },
        {
            "id": "backup_map_layout_initialization",
            "source_entry": "src/fieldmap.c:InitMapLayoutData/InitBackupMapLayoutData",
            "status": "first_pass",
            "critical_order": [
                "fill sBackupMapData with MAPGRID_UNDEFINED",
                "assign gBackupMapLayout.map to sBackupMapData",
                "set backup width to map width + MAP_OFFSET_W",
                "set backup height to map height + MAP_OFFSET_H",
                "copy source map rows into backup at y=MAP_OFFSET and x=MAP_OFFSET",
                "copy each source row then skip MAP_OFFSET_W cells of backup padding",
                "initialize connection strips if backup dimensions fit MAX_MAP_DATA_SIZE",
            ],
            "godot_current": [
                "Generated map data preserves source width/height and raw grid values.",
                "MapRuntime keeps the current map as direct generated grids with border/connection fallback helpers.",
            ],
            "gaps": [
                "Godot runtime does not own a source-shaped backup buffer or staged copy lifecycle.",
            ],
        },
        {
            "id": "border_fallback",
            "source_entry": "src/fieldmap.c:GetBorderBlockAt/GetMapGridBlockAt",
            "status": "first_pass",
            "critical_order": [
                "GetMapGridBlockAt reads gBackupMapLayout when coordinates are in bounds",
                "out-of-bounds coordinates fall back to GetBorderBlockAt",
                "FRLG border wraps by border width/height after subtracting MAP_OFFSET",
                "Emerald border chooses one of four border tiles by x/y parity",
                "border fallback always forces impassable collision bits",
            ],
            "godot_current": [
                "tools/importer/export_map.py exports border_grid metadata.",
                "MapRuntime falls back to border_grid when a cell is outside current map bounds and no generated connection cell is available.",
            ],
            "gaps": [
                "Godot uses generated border metadata instead of source backup-buffer coordinates; exact FRLG wrapping remains metadata/future coverage.",
            ],
        },
        {
            "id": "connection_copy_strips",
            "source_entry": "src/fieldmap.c:InitBackupMapLayoutConnections/Fill*Connection",
            "status": "first_pass",
            "critical_order": [
                "iterate map header connections in source order",
                "resolve connected map header from connection map group/num",
                "south copies MAP_OFFSET rows below current map starting at offset + MAP_OFFSET",
                "north copies the connected map's last MAP_OFFSET rows into backup top rows",
                "west copies MAP_OFFSET columns from the connected map's right edge",
                "east copies MAP_OFFSET + 1 columns from the connected map's left edge",
                "connection flags mark which borders can be crossed",
            ],
            "godot_current": [
                "MapRuntime indexes generated map connections and can resolve fallback values from generated connected-map data when available.",
                "transition sequences include a first-pass map-connection handoff.",
            ],
            "gaps": [
                "Exact source copy rectangles, MAP_OFFSET + 1 east width, and backup-map flag semantics are not yet modeled as runtime data.",
            ],
        },
        {
            "id": "map_grid_accessors",
            "source_entry": "src/fieldmap.c:MapGridGet*/MapGridSet*",
            "status": "first_pass",
            "critical_order": [
                "MapGridGetElevationAt returns 0 for MAPGRID_UNDEFINED, otherwise unpacks elevation",
                "MapGridGetCollisionAt returns TRUE for MAPGRID_UNDEFINED, otherwise unpacks collision",
                "MapGridGetMetatileIdAt uses border fallback when block is MAPGRID_UNDEFINED, otherwise unpacks metatile id",
                "MapGridGetMetatileAttributeAt resolves metatile id through current map layout attributes",
                "MapGridSetMetatileIdAt preserves existing elevation bits while replacing metatile id and collision bits",
                "MapGridSetMetatileEntryAt writes the full u16 entry",
                "MapGridSetMetatileImpassabilityAt toggles all collision bits without touching metatile or elevation",
            ],
            "godot_current": [
                "MapRuntime exposes get_metatile_id_at/get_collision_at/get_elevation_at/get_metatile_behavior_at/get_metatile_layer_type_at.",
                "MapRuntime.apply_script_field_effects handles first-pass setmetatile by updating metatile id, collision, raw value, and generated map data while preserving elevation.",
            ],
            "gaps": [
                "MapGridSetMetatileEntryAt and MapGridSetMetatileImpassabilityAt are not separate Godot runtime APIs yet.",
            ],
        },
        {
            "id": "saved_map_view",
            "source_entry": "src/fieldmap.c:SaveMapView/LoadSavedMapView/MoveMapViewToBackup",
            "status": "unsupported",
            "critical_order": [
                "SaveMapView stores a MAP_OFFSET_W x MAP_OFFSET_H view window from sBackupMapData at save-block position",
                "LoadSavedMapView restores non-empty saved view windows after InitMapFromSavedGame",
                "LoadSavedMapView skips selected long-grass repair cells through SkipCopyingMetatileFromSavedMap",
                "LoadSavedMapView fixes top/bottom long-grass windows after restore",
                "MoveMapViewToBackup shifts the saved window into backup data after camera connection movement",
                "MoveMapViewToBackup trims one row/column depending on connection direction",
            ],
            "godot_current": [
                "SaveService stores current map id, player position, object-event runtime state, flags, vars, and party.",
                "MapRuntime can export/apply object-event runtime state but not a source-shaped mapView window.",
            ],
            "gaps": [
                "Godot does not yet serialize or restore source mapView data or long-grass repair behavior.",
            ],
        },
        {
            "id": "camera_connection_movement",
            "source_entry": "src/fieldmap.c:GetMapBorderIdAt/CanCameraMoveInDirection/CameraMove",
            "status": "first_pass_metadata",
            "critical_order": [
                "GetMapBorderIdAt rejects MAPGRID_UNDEFINED cells",
                "east border begins at backup width - (MAP_OFFSET + 1)",
                "west border is x < MAP_OFFSET",
                "south border is y >= backup height - MAP_OFFSET",
                "north border is y < MAP_OFFSET",
                "CanCameraMoveInDirection checks the next focus coordinate plus MAP_OFFSET",
                "CameraMove saves mapView before crossing a connection",
                "CameraMove resolves incoming connection, rewrites save-block position, loads the new map by camera transition, sets gCamera.active and camera delta, applies movement, then moves saved view into backup",
            ],
            "godot_current": [
                "MapRuntime can identify generated map connections and TransitionSequencePlayer records a first-pass edge-step/load/unlock sequence.",
                "EventManager request_map_connection_transition can hand off to generated destination map data.",
            ],
            "gaps": [
                "Exact gCamera active/delta state, incoming-connection search, save-block coordinate rewrite, and mapView shift are not source-equivalent.",
            ],
        },
        {
            "id": "camera_focus_coordinate_offset",
            "source_entry": "src/fieldmap.c:SetCameraFocusCoords/GetCameraFocusCoords",
            "status": "first_pass",
            "critical_order": [
                "SetCameraFocusCoords stores focus x/y minus MAP_OFFSET in save-block position",
                "GetCameraFocusCoords reads save-block position plus MAP_OFFSET",
                "GetCameraCoords exposes raw save-block position",
            ],
            "godot_current": [
                "GameState.player_grid_position stores visible gameplay grid position directly.",
                "MapRuntime source reports and debug dumps preserve MAP_OFFSET metadata where generated data needs it.",
            ],
            "gaps": [
                "Godot does not maintain separate source focus coordinates and backup-buffer coordinates.",
            ],
        },
    ]


def manifest_entry_for(exported, output_path):
    stats = exported["stats"]
    return {
        "category": "overworld_fieldmap_grid_trace",
        "path": to_project_path(output_path),
        "entry_count": stats["flow_count"],
        "source_file_count": stats["source_file_count"],
        "missing_source_file_count": stats["missing_source_file_count"],
        "required_symbol_count": stats["required_symbol_count"],
        "missing_symbol_count": stats["missing_symbol_count"],
        "unsupported_count": stats["unsupported_count"],
    }


def build_export(source_root):
    source_root = Path(source_root)
    presence = source_file_presence(source_root)
    locations = symbol_locations(source_root)
    missing_symbols = sorted(
        symbol
        for symbol, occurrences in locations.items()
        if not occurrences
    )
    flows = source_flow_rows()
    status_counts = {}
    for row in flows:
        status = row["status"]
        status_counts[status] = status_counts.get(status, 0) + 1
    stats = {
        "flow_count": len(flows),
        "source_file_count": len(SOURCE_FILES),
        "missing_source_file_count": sum(1 for item in presence if not item["exists"]),
        "required_symbol_count": len(REQUIRED_SYMBOLS),
        "missing_symbol_count": len(missing_symbols),
        "missing_symbols": missing_symbols,
        "status_counts": status_counts,
        "unsupported_count": len(UNSUPPORTED),
    }
    return {
        "schema_version": 1,
        "generated_by": GENERATED_BY,
        "source_root": str(source_root),
        "source_files": presence,
        "required_symbols": locations,
        "bit_layout": BIT_LAYOUT,
        "source_flows": flows,
        "godot_trace_owners": {
            "importers": [
                "tools/importer/export_map.py",
                "tools/importer/export_tilesets.py",
            ],
            "runtime": [
                "scripts/autoload/map_runtime.gd",
                "scripts/autoload/event_manager.gd",
                "scripts/autoload/save_service.gd",
            ],
            "presentation": [
                "scripts/overworld/debug_map_plane.gd",
                "scripts/overworld/transition_sequence_player.gd",
            ],
            "tests": [
                "tools/godot_smoke/map_runtime_smoke.gd",
                "tools/godot_smoke/transition_presentation_smoke.gd",
                "tools/godot_smoke/save_service_smoke.gd",
            ],
        },
        "unsupported": UNSUPPORTED,
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
    output_path = output_root / REPORT_PATH

    exported = build_export(source_root)
    write_json(output_path, exported)
    manifest_entry = manifest_entry_for(exported, output_path)
    write_manifest(
        output_root / "import_manifest.json",
        exported_overworld_reports=[manifest_entry],
        generator=GENERATED_BY,
    )

    print(json.dumps({"exported": manifest_entry, "stats": exported["stats"]}, ensure_ascii=False, indent=2))
    return 0 if exported["stats"]["missing_source_file_count"] == 0 and exported["stats"]["missing_symbol_count"] == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
