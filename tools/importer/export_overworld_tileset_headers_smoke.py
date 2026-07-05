#!/usr/bin/env python3
"""Smoke checks for the overworld tileset header report export."""

import argparse
import sys
from pathlib import Path

from export_overworld_tileset_headers import build_export
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
    rows = {row["symbol"]: row for row in exported["tileset_headers"]}

    _assert(exported["schema_version"] == 1, "unexpected schema version")
    _assert(exported["generated_by"].endswith("export_overworld_tileset_headers.py"), "unexpected generator")
    _assert(exported["runtime_policy"]["runtime_palette_required"] is False, "runtime palette must stay disabled")
    _assert(exported["runtime_policy"]["audio"]["status"] == "metadata_only", "audio policy changed")

    _assert(stats["missing_source_file_count"] == 0, "missing source files")
    _assert(stats["total_header_count"] == 139, "unexpected total tileset header count")
    _assert(stats["active_emerald_header_count"] == 75, "unexpected active Emerald header count")
    _assert(stats["frlg_metadata_header_count"] == 64, "unexpected FRLG metadata header count")
    _assert(stats["header_count_by_branch"]["preprocessor_shared"] == 2, "unexpected shared header count")
    _assert(stats["header_count_by_branch"]["emerald_active"] == 73, "unexpected Emerald branch count")
    _assert(stats["header_count_by_branch"]["frlg_metadata"] == 64, "unexpected FRLG branch count")
    _assert(stats["primary_header_count"] == 5, "unexpected primary header count")
    _assert(stats["secondary_header_count"] == 134, "unexpected secondary header count")
    _assert(stats["active_primary_header_count"] == 3, "unexpected active primary header count")
    _assert(stats["active_secondary_header_count"] == 72, "unexpected active secondary header count")
    _assert(stats["callback_symbol_count"] == 31, "unexpected callback symbol count")
    _assert(stats["callback_binding_count"] == 31, "unexpected callback binding count")
    _assert(stats["callback_source_found_count"] == 31, "unexpected callback source count")
    _assert(stats["missing_callback_source_count"] == 0, "missing callback sources")
    _assert(stats["null_callback_count"] == 108, "unexpected null callback count")
    _assert(stats["active_callback_symbol_count"] == 25, "unexpected active callback symbol count")
    _assert(stats["active_callback_binding_count"] == 25, "unexpected active callback binding count")
    _assert(stats["asset_field_count"] == 556, "unexpected asset field count")
    _assert(stats["missing_asset_declaration_count"] == 0, "missing asset declarations")
    _assert(stats["init_function_count"] == 31, "unexpected init function count")
    _assert(stats["animation_frame_declaration_count"] == 174, "unexpected animation frame declaration count")
    _assert(stats["animation_source_bin_count"] == 182, "unexpected animation source binary count")
    _assert(stats["animation_existing_source_bin_count"] == 0, "source .4bpp files should not be required")
    _assert(stats["animation_editable_source_candidate_count"] == 182, "unexpected animation source image count")
    _assert(
        stats["animation_existing_editable_source_candidate_count"] == 182,
        "missing animation source image candidates",
    )
    _assert(
        stats["animation_missing_editable_source_candidate_count"] == 0,
        "unexpected missing animation source images",
    )
    _assert(stats["animation_tileset_base_count"] == 27, "unexpected animation tileset base count")
    _assert(
        stats["headers_with_animation_image_provenance_count"] == 26,
        "unexpected header animation provenance count",
    )
    _assert(
        stats["active_headers_with_animation_image_provenance_count"] == 21,
        "unexpected active header animation provenance count",
    )
    _assert(stats["orphan_animation_tileset_base_count"] == 1, "unexpected orphan animation base count")
    _assert(
        stats["orphan_animation_tileset_base_paths"] == ["data/tilesets/secondary/silph_co_frlg"],
        "unexpected orphan animation base path",
    )
    _assert(len(exported["tileset_animation_frames"]) == 174, "unexpected top-level animation frame count")
    _assert(len(exported["tileset_animation_init_functions"]) == 31, "unexpected top-level init function count")

    general = rows["gTileset_General"]
    _assert(general["active_in_emerald"], "General should be active")
    _assert(general["kind"] == "primary", "General should be primary")
    _assert(general["is_compressed"] is True, "General should be compressed")
    _assert(general["callback"]["symbol"] == "InitTilesetAnim_General", "General callback mismatch")
    _assert(general["callback"]["source_found"], "General callback source missing")
    _assert(general["callback"]["source"]["path"] == "src/tileset_anims.c", "General callback source path mismatch")
    _assert(general["asset_provenance"]["tiles"]["declaration_found"], "General tile declaration missing")
    _assert(
        _has_existing_candidate(general["asset_provenance"]["tiles"], "data/tilesets/primary/general/tiles.png"),
        "General tiles.png candidate missing",
    )
    _assert(
        _has_existing_candidate(general["asset_provenance"]["palettes"], "data/tilesets/primary/general/palettes/00.pal"),
        "General palette source candidate missing",
    )
    _assert(general["animation_image_provenance"]["frame_declaration_count"] == 26, "General anim count mismatch")
    _assert(
        general["animation_image_provenance"]["existing_editable_source_candidate_count"] == 26,
        "General animation image candidates missing",
    )
    _assert(
        _has_existing_animation_candidate(general, "data/tilesets/primary/general/anim/flower/1.png"),
        "General flower animation image missing",
    )

    petalburg = rows["gTileset_Petalburg"]
    _assert(petalburg["active_in_emerald"], "Petalburg should be active")
    _assert(petalburg["kind"] == "secondary", "Petalburg should be secondary")
    _assert(petalburg["callback"]["symbol"] == "InitTilesetAnim_Petalburg", "Petalburg callback mismatch")
    _assert(petalburg["callback"]["source_found"], "Petalburg callback source missing")
    _assert(petalburg["animation_image_provenance"]["frame_declaration_count"] == 0, "Petalburg should have no frame images")
    _assert(
        _has_existing_candidate(petalburg["asset_provenance"]["tiles"], "data/tilesets/secondary/petalburg/tiles.png"),
        "Petalburg tiles.png candidate missing",
    )

    rustboro = rows["gTileset_Rustboro"]
    _assert(rustboro["callback"]["symbol"] == "InitTilesetAnim_Rustboro", "Rustboro callback mismatch")
    _assert(rustboro["callback"]["source_found"], "Rustboro callback source missing")
    _assert(rustboro["animation_image_provenance"]["frame_declaration_count"] == 10, "Rustboro anim count mismatch")
    _assert(
        _has_existing_animation_candidate(rustboro, "data/tilesets/secondary/rustboro/anim/windy_water/0.png"),
        "Rustboro windy water animation image missing",
    )

    sootopolis = rows["gTileset_Sootopolis"]
    _assert(sootopolis["animation_image_provenance"]["frame_declaration_count"] == 8, "Sootopolis anim count mismatch")
    _assert(sootopolis["animation_image_provenance"]["source_bin_count"] == 16, "Sootopolis multi-source anim count mismatch")
    _assert(
        _has_existing_animation_candidate(
            sootopolis,
            "data/tilesets/secondary/sootopolis/anim/stormy_water/0_kyogre.png",
        ),
        "Sootopolis Kyogre stormy water image missing",
    )
    _assert(
        _has_existing_animation_candidate(
            sootopolis,
            "data/tilesets/secondary/sootopolis/anim/stormy_water/0_groudon.png",
        ),
        "Sootopolis Groudon stormy water image missing",
    )

    secret_base = rows["gTileset_SecretBase"]
    _assert(secret_base["branch"] == "preprocessor_shared", "SecretBase branch mismatch")
    _assert(secret_base["active_in_emerald"], "SecretBase should be active")
    _assert(secret_base["kind"] == "primary", "SecretBase should be primary")
    _assert(secret_base["is_compressed"] is False, "SecretBase should be uncompressed")
    _assert(secret_base["callback"]["has_callback"] is False, "SecretBase callback should be null")

    frlg_general = rows["gTileset_General_Frlg"]
    _assert(frlg_general["branch"] == "frlg_metadata", "FRLG General branch mismatch")
    _assert(frlg_general["active_in_emerald"] is False, "FRLG General should be metadata-only")
    _assert(frlg_general["callback"]["status"] == "metadata_only", "FRLG callback status mismatch")
    _assert(frlg_general["callback"]["source_found"], "FRLG General callback source missing")
    _assert(
        frlg_general["animation_image_provenance"]["frame_declaration_count"] == 21,
        "FRLG General anim count mismatch",
    )
    _assert(
        _has_existing_animation_candidate(frlg_general, "data/tilesets/primary/general_frlg/anim/flower/0.png"),
        "FRLG General flower animation image missing",
    )

    unused_1 = rows["gTileset_Unused1"]
    _assert(
        unused_1["expected_source_directory"]["resolved_from_asset_provenance"],
        "Unused1 should resolve source directory from asset provenance",
    )
    _assert(unused_1["expected_source_directory"]["base_path"] == "data/tilesets/secondary/unused_1", "Unused1 base mismatch")
    _assert(unused_1["animation_image_provenance"]["frame_declaration_count"] == 4, "Unused1 anim count mismatch")
    _assert(
        _has_existing_animation_candidate(unused_1, "data/tilesets/secondary/unused_1/0.png"),
        "Unused1 animation image missing",
    )

    unsupported_codes = {entry["code"] for entry in exported["unsupported"]}
    _assert("tileset_animation_runtime_pending" in unsupported_codes, "missing animation pending code")
    _assert("metatile_layer_decode_pending" in unsupported_codes, "missing metatile decode pending code")
    _assert("audio_playback_pending" in unsupported_codes, "missing audio pending code")

    print("export_overworld_tileset_headers_smoke: ok")
    return 0


def _has_existing_candidate(group, path):
    return any(
        row.get("path") == path and row.get("exists")
        for row in group.get("editable_source_candidates", [])
    )


def _has_existing_animation_candidate(header, path):
    return any(
        candidate.get("path") == path and candidate.get("exists")
        for frame in header["animation_image_provenance"].get("frames", [])
        for candidate in frame.get("editable_source_candidates", [])
    )


def _assert(condition, message):
    if not condition:
        raise AssertionError(message)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
