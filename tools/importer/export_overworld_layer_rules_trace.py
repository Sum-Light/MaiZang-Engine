#!/usr/bin/env python3
"""Export source-traced overworld metatile layer rule coverage."""

import argparse
import json
import re
import sys
from pathlib import Path

from export_map import write_json, write_manifest
from source_probe import load_config, to_project_path


GENERATED_BY = "tools/importer/export_overworld_layer_rules_trace.py"
REPORT_PATH = Path("overworld/layer_rules_trace.json")

SOURCE_FILES = [
    "include/global.fieldmap.h",
    "include/field_camera.h",
    "src/fieldmap.c",
    "src/field_camera.c",
    "src/overworld.c",
    "src/event_object_movement.c",
    "src/shop.c",
    "src/field_door.c",
]

REQUIRED_SYMBOLS = [
    "METATILE_ATTR_BEHAVIOR_MASK",
    "METATILE_ATTR_LAYER_MASK",
    "METATILE_ATTR_LAYER_SHIFT",
    "METATILE_ATTR_BEHAVIOR_MASK_FRLG",
    "METATILE_ATTR_LAYER_MASK_FRLG",
    "METATILE_ATTR_LAYER_SHIFT_FRLG",
    "METATILE_LAYER_TYPE_NORMAL",
    "METATILE_LAYER_TYPE_COVERED",
    "METATILE_LAYER_TYPE_SPLIT",
    "METATILE_ATTRIBUTE_LAYER_TYPE",
    "sMetatileAttrMasks",
    "sMetatileAttrShifts",
    "sMetatileAttrMasksEmerald",
    "sMetatileAttrShiftsEmerald",
    "ExtractMetatileAttribute",
    "GetAttributeByMetatileIdAndMapLayout",
    "MapGridGetMetatileLayerTypeAt",
    "DrawWholeMapView",
    "DrawMetatileAt",
    "DrawMetatile",
    "DrawDoorMetatileAt",
    "CurrentMapDrawMetatileAt",
    "MapPosToBgTilemapOffset",
    "gOverworldTilemapBuffer_Bg1",
    "gOverworldTilemapBuffer_Bg2",
    "gOverworldTilemapBuffer_Bg3",
    "sOverworldBgTemplates",
    "InitOverworldBgs",
    "InitOverworldGraphicsRegisters",
    "sElevationToPriority",
    "sElevationToSubpriority",
    "ObjectEventUpdateElevation",
    "SetObjectSubpriorityByElevation",
    "BuyMenuDrawMapMetatile",
]

ATTRIBUTE_LAYOUT = {
    "emerald": {
        "storage": "u16 metatile_attributes.bin entries",
        "behavior": {"mask": "0x00FF", "shift": 0, "bits": "0-7"},
        "layer_type": {"mask": "0xF000", "shift": 12, "bits": "12-15"},
        "unused": {"bits": "8-11"},
    },
    "frlg": {
        "storage": "u32 metatile_attributes.bin entries",
        "behavior": {"mask": "0x000001FF", "shift": 0, "bits": "0-8"},
        "layer_type": {"mask": "0x60000000", "shift": 29, "bits": "29-30"},
        "other_attributes": [
            {"name": "terrain", "mask": "0x00003E00", "shift": 9},
            {"name": "encounter_type", "mask": "0x07000000", "shift": 24},
        ],
    },
}

LAYER_TYPES = [
    {
        "id": 0,
        "symbol": "METATILE_LAYER_TYPE_NORMAL",
        "source_comment": "Metatile uses middle and top bg layers",
        "draw_mapping": {
            "bg3": "fill 2x2 cells with tile 0x3014",
            "bg2": "tiles[0..3], source metatile bottom layer",
            "bg1": "tiles[4..7], source metatile top layer",
        },
        "object_depth_effect": "BG1 carries the top layer, so source comments mark it as covering object event sprites.",
    },
    {
        "id": 1,
        "symbol": "METATILE_LAYER_TYPE_COVERED",
        "source_comment": "Metatile uses bottom and middle bg layers",
        "draw_mapping": {
            "bg3": "tiles[0..3], source metatile bottom layer",
            "bg2": "tiles[4..7], source metatile top layer",
            "bg1": "transparent tile 0 in all 2x2 cells",
        },
        "object_depth_effect": "The top metatile half is behind normal object-event priority because BG1 is cleared.",
    },
    {
        "id": 2,
        "symbol": "METATILE_LAYER_TYPE_SPLIT",
        "source_comment": "Metatile uses bottom and top bg layers",
        "draw_mapping": {
            "bg3": "tiles[0..3], source metatile bottom layer",
            "bg2": "transparent tile 0 in all 2x2 cells",
            "bg1": "tiles[4..7], source metatile top layer",
        },
        "object_depth_effect": "BG1 carries the top layer, matching bridge/roof-style coverage over sprites.",
    },
]

UNSUPPORTED = [
    {
        "code": "source_layered_renderer_pending",
        "status": "unsupported",
        "source": "src/field_camera.c:DrawMetatile",
        "detail": "Godot does not yet render separate bottom/middle/top map layers from source metatile entries.",
    },
    {
        "code": "flattened_debug_atlas_not_source_equivalent",
        "status": "unsupported",
        "source": "tools/importer/export_tilesets.py:render_metatile",
        "detail": "The current generated atlas alpha-composites all 8 tile entries into one 16x16 debug image, so it cannot express covered/split BG placement.",
    },
    {
        "code": "object_depth_interleave_pending",
        "status": "unsupported",
        "source": "src/field_camera.c:DrawMetatile + src/event_object_movement.c:sElevationToPriority",
        "detail": "Godot does not yet reproduce source BG1/BG2/BG3 priority interaction with object-event OAM priority, elevation, subsprite mode, and subpriority.",
    },
    {
        "code": "current_map_draw_layer_cache_pending",
        "status": "unsupported",
        "source": "src/field_camera.c:CurrentMapDrawMetatileAt",
        "detail": "Godot setmetatile currently updates logical grid data and the debug map plane; it does not yet redraw per-layer renderer caches with source offset wrapping.",
    },
    {
        "code": "frlg_u32_layer_attributes_pending",
        "status": "unsupported",
        "source": "src/fieldmap.c:GetAttributeByMetatileIdAndMapLayoutFrlg",
        "detail": "The current tileset importer decodes Emerald u16 attributes; FRLG u32 layer and terrain fields remain future import coverage.",
    },
    {
        "code": "door_forced_covered_layer_pending",
        "status": "first_pass",
        "source": "src/field_camera.c:DrawDoorMetatileAt",
        "detail": "Godot door overlays use generated frame atlases, but the source rule that door animation frames are drawn as METATILE_LAYER_TYPE_COVERED is not yet a layer-renderer primitive.",
    },
    {
        "code": "invalid_layer_type_validation_pending",
        "status": "unsupported",
        "source": "src/field_camera.c:DrawMetatile",
        "detail": "The source switch has no default draw mapping for invalid layer values; Godot import currently preserves layer_type but does not validate every source metatile against the valid enum range.",
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
            "id": "attribute_bit_layout",
            "source_entry": "include/global.fieldmap.h:METATILE_ATTR_*",
            "status": "ported",
            "critical_order": [
                "Emerald metatile attributes are u16 values from metatile_attributes.bin",
                "Emerald behavior uses bits 0-7",
                "Emerald layer type uses bits 12-15",
                "FRLG metatile attributes are u32 values",
                "FRLG behavior uses bits 0-8",
                "FRLG layer type uses bits 29-30",
            ],
            "godot_current": [
                "tools/importer/export_tilesets.py decodes Emerald behavior and layer_type into generated metatile entry attributes.",
                "MapRuntime indexes generated metatile attributes by global metatile id.",
            ],
            "gaps": [
                "FRLG u32 metatile attribute parsing is not implemented in the Godot importer.",
            ],
        },
        {
            "id": "layer_enum_semantics",
            "source_entry": "include/global.fieldmap.h:METATILE_LAYER_TYPE_*",
            "status": "ported",
            "critical_order": [
                "METATILE_LAYER_TYPE_NORMAL is value 0 and uses middle and top BG layers",
                "METATILE_LAYER_TYPE_COVERED is value 1 and uses bottom and middle BG layers",
                "METATILE_LAYER_TYPE_SPLIT is value 2 and uses bottom and top BG layers",
                "MapGridGetMetatileLayerTypeAt resolves the current metatile id through METATILE_ATTRIBUTE_LAYER_TYPE",
            ],
            "godot_current": [
                "Generated tileset records preserve layer_type as source enum numbers.",
                "MapRuntime exposes get_metatile_layer_type_at(cell).",
            ],
            "gaps": [
                "The renderer still consumes flattened debug atlas cells instead of separate source layer data.",
            ],
        },
        {
            "id": "source_metatile_tile_entry_halves",
            "source_entry": "src/field_camera.c:DrawMetatile",
            "status": "metadata_only",
            "critical_order": [
                "Each source metatile has 8 tile entries",
                "tiles[0] and tiles[1] are the top row of the source bottom half",
                "tiles[2] and tiles[3] are the bottom row of the source bottom half",
                "tiles[4] and tiles[5] are the top row of the source top half",
                "tiles[6] and tiles[7] are the bottom row of the source top half",
                "Each metatile is written into a 2x2 region of the 32x32 BG tilemap",
            ],
            "godot_current": [
                "tools/importer/export_tilesets.py preserves tile_entries with raw tile id, palette, hflip, vflip, and source layer note.",
                "The temporary atlas composites both halves into one RGBA tile.",
            ],
            "gaps": [
                "Godot does not yet expose independent per-BG layer render data for each metatile cell.",
            ],
        },
        {
            "id": "normal_layer_draw_mapping",
            "source_entry": "src/field_camera.c:DrawMetatile:METATILE_LAYER_TYPE_NORMAL",
            "status": "metadata_only",
            "critical_order": [
                "write 0x3014 into BG3 for all four cells",
                "write tiles[0..3] into BG2",
                "write tiles[4..7] into BG1",
                "BG1 top layer covers object event sprites per source comment",
            ],
            "godot_current": [
                "Layer type 0 is preserved in generated metadata.",
            ],
            "gaps": [
                "The current map plane cannot place the two source halves onto BG2 and BG1 independently.",
            ],
        },
        {
            "id": "covered_layer_draw_mapping",
            "source_entry": "src/field_camera.c:DrawMetatile:METATILE_LAYER_TYPE_COVERED",
            "status": "metadata_only",
            "critical_order": [
                "write tiles[0..3] into BG3",
                "write tiles[4..7] into BG2",
                "write transparent tile 0 into BG1",
                "object events can draw over the metatile top half because BG1 is clear",
            ],
            "godot_current": [
                "Layer type 1 is preserved in generated metadata.",
            ],
            "gaps": [
                "The current map plane cannot separate covered ground/cover placement from sprite depth.",
            ],
        },
        {
            "id": "split_layer_draw_mapping",
            "source_entry": "src/field_camera.c:DrawMetatile:METATILE_LAYER_TYPE_SPLIT",
            "status": "metadata_only",
            "critical_order": [
                "write tiles[0..3] into BG3",
                "write transparent tile 0 into BG2",
                "write tiles[4..7] into BG1",
                "the split top half covers object events like roofs or bridge tops",
            ],
            "godot_current": [
                "Layer type 2 is preserved in generated metadata when present.",
            ],
            "gaps": [
                "No first-slice renderer uses the split placement rule yet.",
            ],
        },
        {
            "id": "door_animation_layer_override",
            "source_entry": "src/field_camera.c:DrawDoorMetatileAt + src/field_door.c:DrawCurrentDoorAnimFrame",
            "status": "first_pass",
            "critical_order": [
                "door animation frame code builds temporary 8-entry metatile tile arrays",
                "DrawDoorMetatileAt calls DrawMetatile with METATILE_LAYER_TYPE_COVERED",
                "door frame graphics therefore draw bottom half on BG3, top half on BG2, and clear BG1",
                "closed-door redraw returns to CurrentMapDrawMetatileAt for source layer type",
            ],
            "godot_current": [
                "Generated door animation frame atlases preserve frame order and timing intent.",
                "TransitionSequencePlayer can play first-pass door overlays for generated door transitions.",
            ],
            "gaps": [
                "Door frames are not yet emitted through a source-shaped layer renderer that forces covered placement.",
            ],
        },
        {
            "id": "runtime_redraw_and_vram_schedule",
            "source_entry": "src/field_camera.c:CurrentMapDrawMetatileAt/DrawMetatile",
            "status": "metadata_only",
            "critical_order": [
                "MapPosToBgTilemapOffset rejects cells outside the 16x16 camera tile window",
                "the offset uses x/y tile offsets modulo the 32x32 BG tilemap",
                "CurrentMapDrawMetatileAt redraws one metatile only when it is in the current view",
                "DrawMetatile schedules BG1, BG2, and BG3 tilemap copies after writing layer data",
            ],
            "godot_current": [
                "MapRuntime emits map_changed after setmetatile effects.",
                "DebugMapPlane rebuilds visible debug cells from flattened generated data.",
            ],
            "gaps": [
                "Godot does not yet maintain per-layer renderer cache regions with source camera wrapping.",
            ],
        },
        {
            "id": "object_depth_dependency",
            "source_entry": "src/event_object_movement.c:sElevationToPriority/sElevationToSubpriority",
            "status": "unsupported",
            "critical_order": [
                "object-event sprites update OAM priority from previous elevation",
                "subpriority is derived from screen y position and elevation subpriority table",
                "multi-level elevation uses subsprite priority handling for bridges",
                "layer type and object elevation together determine visible over/under relationships",
            ],
            "godot_current": [
                "ObjectEventSpawner renders visible source-backed object sprites on the debug map.",
            ],
            "gaps": [
                "Godot does not yet model source OAM priority, subsprite mode, y-derived subpriority, or bridge underpass rules.",
            ],
        },
        {
            "id": "buy_menu_layer_snapshot",
            "source_entry": "src/shop.c:BuyMenuDrawMapMetatile",
            "status": "metadata_only",
            "critical_order": [
                "buy-menu map snapshots reuse the same NORMAL/COVERED/SPLIT semantic split",
                "NORMAL draws source bottom half to buffer 3 and top half to buffer 1",
                "COVERED draws source bottom half to buffer 2 and top half to buffer 3",
                "SPLIT draws source bottom half to buffer 2 and top half to buffer 1",
                "cells hidden under the menu background are forced to METATILE_LAYER_TYPE_COVERED",
            ],
            "godot_current": [
                "No source-equivalent shop map snapshot renderer exists yet.",
            ],
            "gaps": [
                "Future menu work needs to reuse the layer-rule metadata rather than the flattened atlas.",
            ],
        },
    ]


def manifest_entry_for(exported, output_path):
    stats = exported["stats"]
    return {
        "category": "overworld_layer_rules_trace",
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
    flow_rows = source_flow_rows()
    status_counts = {}
    for row in flow_rows:
        status = row["status"]
        status_counts[status] = status_counts.get(status, 0) + 1
    unsupported_status_counts = {}
    for row in UNSUPPORTED:
        status = row["status"]
        unsupported_status_counts[status] = unsupported_status_counts.get(status, 0) + 1
    stats = {
        "flow_count": len(flow_rows),
        "source_file_count": len(SOURCE_FILES),
        "missing_source_file_count": sum(1 for item in presence if not item["exists"]),
        "required_symbol_count": len(REQUIRED_SYMBOLS),
        "missing_symbol_count": len(missing_symbols),
        "missing_symbols": missing_symbols,
        "status_counts": status_counts,
        "unsupported_count": len(UNSUPPORTED),
        "unsupported_status_counts": unsupported_status_counts,
    }
    return {
        "schema_version": 1,
        "generated_by": GENERATED_BY,
        "source_root": str(source_root),
        "source_files": presence,
        "required_symbols": locations,
        "attribute_layout": ATTRIBUTE_LAYOUT,
        "layer_types": LAYER_TYPES,
        "bg_priorities": {
            "source": "src/overworld.c:sOverworldBgTemplates",
            "bg0": 0,
            "bg1": 1,
            "bg2": 2,
            "bg3": 3,
        },
        "source_flows": flow_rows,
        "godot_trace_owners": {
            "importers": [
                "tools/importer/export_tilesets.py",
                "tools/importer/export_map.py",
            ],
            "runtime": [
                "scripts/autoload/map_runtime.gd",
            ],
            "presentation": [
                "scripts/overworld/debug_map_plane.gd",
                "scripts/overworld/object_event_spawner.gd",
                "scripts/overworld/transition_sequence_player.gd",
            ],
            "tests": [
                "tools/godot_smoke/map_runtime_smoke.gd",
                "tools/godot_smoke/transition_presentation_smoke.gd",
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
