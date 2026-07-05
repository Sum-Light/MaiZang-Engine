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
    rules = exported["palette_slot_rules"]
    attribute_rules = exported["metatile_attribute_rules"]
    rows = {row["symbol"]: row for row in exported["tileset_headers"]}

    _assert(exported["schema_version"] == 1, "unexpected schema version")
    _assert(exported["generated_by"].endswith("export_overworld_tileset_headers.py"), "unexpected generator")
    _assert(exported["runtime_policy"]["runtime_palette_required"] is False, "runtime palette must stay disabled")
    _assert(exported["runtime_policy"]["audio"]["status"] == "metadata_only", "audio policy changed")

    _assert(stats["source_file_count"] == 9, "unexpected source file count")
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
    _assert(stats["palette_slot_mapping_count"] == 2224, "unexpected palette slot mapping count")
    _assert(stats["active_palette_slot_mapping_count"] == 1200, "unexpected active palette slot mapping count")
    _assert(stats["loaded_palette_slot_mapping_count"] == 908, "unexpected loaded palette slot mapping count")
    _assert(
        stats["active_loaded_palette_slot_mapping_count"] == 522,
        "unexpected active loaded palette slot mapping count",
    )
    _assert(stats["not_loaded_palette_slot_mapping_count"] == 1316, "unexpected unloaded palette slot count")
    _assert(stats["active_not_loaded_palette_slot_mapping_count"] == 678, "unexpected active unloaded palette count")
    _assert(stats["palette_source_incbin_count"] == 2224, "unexpected palette source incbin count")
    _assert(stats["palette_existing_source_incbin_count"] == 0, "source .gbapal files should not be required")
    _assert(stats["palette_editable_source_candidate_count"] == 2224, "unexpected palette source candidate count")
    _assert(
        stats["palette_existing_editable_source_candidate_count"] == 2224,
        "missing palette source candidates",
    )
    _assert(
        stats["palette_missing_editable_source_candidate_count"] == 0,
        "unexpected missing palette source candidates",
    )
    _assert(stats["palette_slot_count_by_source_profile"]["emerald"] == 1200, "unexpected Emerald palette slots")
    _assert(stats["palette_slot_count_by_source_profile"]["frlg"] == 1024, "unexpected FRLG palette slots")
    _assert(stats["palette_loaded_slot_count_by_source_profile"]["emerald"] == 522, "unexpected Emerald loaded slots")
    _assert(stats["palette_loaded_slot_count_by_source_profile"]["frlg"] == 386, "unexpected FRLG loaded slots")
    _assert(stats["metatile_decode_header_count"] == 139, "unexpected metatile decode header count")
    _assert(stats["active_metatile_decode_header_count"] == 75, "unexpected active metatile decode count")
    _assert(stats["missing_metatile_decode_header_count"] == 0, "missing metatile decodes")
    _assert(stats["metatile_record_count"] == 29213, "unexpected header-expanded metatile count")
    _assert(stats["active_metatile_record_count"] == 18318, "unexpected active header-expanded metatile count")
    _assert(stats["metatile_tile_entry_count"] == 233704, "unexpected header-expanded tile entry count")
    _assert(stats["active_metatile_tile_entry_count"] == 146544, "unexpected active tile entry count")
    _assert(stats["unique_metatile_source_binary_count"] == 134, "unexpected unique metatile binary count")
    _assert(stats["active_unique_metatile_source_binary_count"] == 70, "unexpected active unique metatile binary count")
    _assert(stats["unique_metatile_record_count"] == 27593, "unexpected unique metatile count")
    _assert(stats["active_unique_metatile_record_count"] == 16698, "unexpected active unique metatile count")
    _assert(stats["unique_metatile_tile_entry_count"] == 220744, "unexpected unique tile entry count")
    _assert(stats["active_unique_metatile_tile_entry_count"] == 133584, "unexpected active unique tile entry count")
    _assert(stats["metatile_out_of_range_tile_entry_count"] == 0, "unexpected out-of-range tile refs")
    _assert(stats["metatile_tile_source_kind_counts"]["primary"] == 119350, "unexpected primary tile ref count")
    _assert(stats["metatile_tile_source_kind_counts"]["secondary"] == 114354, "unexpected secondary tile ref count")
    _assert(stats["metatile_source_layer_slot_counts"]["bottom"] == 116852, "unexpected bottom layer slot count")
    _assert(stats["metatile_source_layer_slot_counts"]["top"] == 116852, "unexpected top layer slot count")
    _assert(stats["metatile_record_count_by_source_profile"]["emerald"] == 18318, "unexpected Emerald metatile count")
    _assert(stats["metatile_record_count_by_source_profile"]["frlg"] == 10895, "unexpected FRLG metatile count")
    _assert(stats["metatile_attribute_decode_header_count"] == 139, "unexpected attribute decode header count")
    _assert(
        stats["active_metatile_attribute_decode_header_count"] == 75,
        "unexpected active attribute decode header count",
    )
    _assert(stats["missing_metatile_attribute_decode_header_count"] == 0, "missing attribute decodes")
    _assert(stats["metatile_attribute_record_count"] == 29213, "unexpected header-expanded attribute count")
    _assert(
        stats["active_metatile_attribute_record_count"] == 18318,
        "unexpected active header-expanded attribute count",
    )
    _assert(
        stats["unique_metatile_attribute_source_binary_count"] == 134,
        "unexpected unique attribute binary count",
    )
    _assert(
        stats["active_unique_metatile_attribute_source_binary_count"] == 70,
        "unexpected active unique attribute binary count",
    )
    _assert(
        stats["unique_metatile_attribute_record_count"] == 27593,
        "unexpected unique attribute record count",
    )
    _assert(
        stats["active_unique_metatile_attribute_record_count"] == 16698,
        "unexpected active unique attribute record count",
    )
    _assert(
        stats["metatile_attribute_record_count_by_source_profile"]["emerald"] == 18318,
        "unexpected Emerald attribute count",
    )
    _assert(
        stats["metatile_attribute_record_count_by_source_profile"]["frlg"] == 10895,
        "unexpected FRLG attribute count",
    )
    _assert(
        stats["metatile_attribute_layer_type_counts"]["METATILE_LAYER_TYPE_NORMAL"] == 14623,
        "unexpected normal layer type count",
    )
    _assert(
        stats["metatile_attribute_layer_type_counts"]["METATILE_LAYER_TYPE_COVERED"] == 14556,
        "unexpected covered layer type count",
    )
    _assert(
        stats["metatile_attribute_layer_type_counts"]["METATILE_LAYER_TYPE_SPLIT"] == 34,
        "unexpected split layer type count",
    )
    _assert(
        stats["metatile_attribute_terrain_decoded_record_count"] == 10895,
        "unexpected terrain decoded record count",
    )
    _assert(
        stats["metatile_attribute_terrain_not_encoded_record_count"] == 18318,
        "unexpected Emerald terrain not-encoded count",
    )
    _assert(
        stats["metatile_attribute_encounter_type_decoded_record_count"] == 10895,
        "unexpected encounter-type decoded record count",
    )
    _assert(
        stats["metatile_attribute_encounter_affordance_count"] == 2023,
        "unexpected encounter affordance count",
    )
    _assert(
        stats["active_metatile_attribute_encounter_affordance_count"] == 1009,
        "unexpected active encounter affordance count",
    )
    _assert(stats["metatile_attribute_surfable_affordance_count"] == 1013, "unexpected surfable count")
    _assert(stats["active_metatile_attribute_surfable_affordance_count"] == 590, "unexpected active surfable count")
    _assert(stats["metatile_attribute_land_encounter_affordance_count"] == 1181, "unexpected land encounter count")
    _assert(stats["metatile_attribute_water_encounter_affordance_count"] == 842, "unexpected water encounter count")
    _assert(stats["metatile_attribute_missing_behavior_name_count"] == 0, "unexpected missing behavior names")
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
    _assert(rules["status"] == "import_metadata_only", "palette rules should be import metadata")
    _assert(rules["runtime_palette_required"] is False, "palette rules must not require runtime palettes")
    _assert(rules["constants"]["NUM_PALS_IN_PRIMARY"]["value"] == 6, "unexpected Emerald primary palette count")
    _assert(rules["constants"]["NUM_PALS_IN_PRIMARY_FRLG"]["value"] == 7, "unexpected FRLG primary palette count")
    _assert(rules["constants"]["NUM_PALS_TOTAL"]["value"] == 13, "unexpected total BG palette count")
    _assert(rules["profiles"]["emerald"]["primary_loaded_palette_count"] == 6, "Emerald primary rule mismatch")
    _assert(rules["profiles"]["emerald"]["secondary_loaded_local_slot_start"] == 6, "Emerald secondary start mismatch")
    _assert(rules["profiles"]["emerald"]["secondary_loaded_palette_count"] == 7, "Emerald secondary count mismatch")
    _assert(rules["profiles"]["frlg"]["primary_loaded_palette_count"] == 7, "FRLG primary rule mismatch")
    _assert(rules["profiles"]["frlg"]["secondary_loaded_local_slot_start"] == 7, "FRLG secondary start mismatch")
    _assert(rules["profiles"]["frlg"]["secondary_loaded_palette_count"] == 6, "FRLG secondary count mismatch")
    _assert(_source_function_found(rules, "LoadTilesetPalette"), "LoadTilesetPalette trace missing")
    _assert(_source_function_found(rules, "LoadSecondaryTilesetPalette"), "LoadSecondaryTilesetPalette trace missing")

    metatile_rules = exported["metatile_decode_rules"]
    _assert(metatile_rules["status"] == "decoded_import_metadata", "metatile rules status mismatch")
    _assert(
        metatile_rules["runtime_binary_metatile_required"] is False,
        "runtime binary metatiles should stay disabled",
    )
    _assert(
        metatile_rules["constants"]["NUM_TILES_PER_METATILE"]["value"] == 8,
        "unexpected source tile entries per metatile",
    )
    _assert(
        metatile_rules["tile_entry_format"]["tile_id_bits"] == "0-9",
        "unexpected tile id bit range",
    )
    _assert(
        metatile_rules["tile_entry_format"]["palette_slot_bits"] == "12-15",
        "unexpected palette slot bit range",
    )
    _assert(
        metatile_rules["source_layer_slots"][0]["tile_entry_indices"] == [0, 1, 2, 3],
        "bottom source layer slot mismatch",
    )
    _assert(
        metatile_rules["source_layer_slots"][1]["tile_entry_indices"] == [4, 5, 6, 7],
        "top source layer slot mismatch",
    )
    _assert(_source_function_found(metatile_rules, "DrawMetatile"), "DrawMetatile trace missing")

    _assert(attribute_rules["status"] == "decoded_import_metadata", "attribute rules status mismatch")
    _assert(
        attribute_rules["runtime_binary_metatile_attributes_required"] is False,
        "runtime binary attributes should stay disabled",
    )
    _assert(attribute_rules["profiles"]["emerald"]["record_byte_count"] == 2, "Emerald attribute size mismatch")
    _assert(attribute_rules["profiles"]["frlg"]["record_byte_count"] == 4, "FRLG attribute size mismatch")
    _assert(
        attribute_rules["profiles"]["emerald"]["fields"]["terrain_type"]["status"]
        == "not_encoded_in_emerald_attributes",
        "Emerald terrain status mismatch",
    )
    _assert(attribute_rules["map_grid_block_fields"]["collision"]["status"] == "map_grid_block_field", "collision source mismatch")
    _assert(attribute_rules["map_grid_block_fields"]["elevation"]["shift"] == 12, "elevation shift mismatch")
    _assert(attribute_rules["behavior_affordance_source"]["encounter_behavior_count"] == 15, "encounter behavior count mismatch")
    _assert(attribute_rules["behavior_affordance_source"]["surfable_behavior_count"] == 18, "surfable behavior count mismatch")
    _assert(_source_function_found(attribute_rules, "ExtractMetatileAttribute"), "ExtractMetatileAttribute trace missing")

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
    _assert(general["palette_slot_mapping"]["source_rules_profile"] == "emerald", "General palette profile mismatch")
    _assert(general["palette_slot_mapping"]["declared_palette_slot_count"] == 16, "General palette slot count mismatch")
    _assert(general["palette_slot_mapping"]["loaded_palette_slot_count"] == 6, "General loaded palette count mismatch")
    _assert(general["palette_slot_mapping"]["loaded_global_bg_palette_slots"] == [0, 1, 2, 3, 4, 5], "General loaded slots mismatch")
    general_slot_0 = _palette_slot(general, 0)
    _assert(general_slot_0["loaded_by_source_map_palette_copy"], "General slot 0 should be loaded")
    _assert(general_slot_0["global_bg_palette_slot"] == 0, "General slot 0 global slot mismatch")
    _assert(general_slot_0["source_incbin"]["path"] == "data/tilesets/primary/general/palettes/00.gbapal", "General slot 0 incbin mismatch")
    _assert(_slot_has_candidate(general_slot_0, "data/tilesets/primary/general/palettes/00.pal"), "General slot 0 source candidate missing")
    general_slot_6 = _palette_slot(general, 6)
    _assert(not general_slot_6["loaded_by_source_map_palette_copy"], "General slot 6 should not be loaded")
    _assert(general_slot_6["global_bg_palette_slot"] is None, "General slot 6 should not map to a global slot")
    _assert(general_slot_6["source_role"] == "declared_global_slot_owned_by_secondary", "General slot 6 role mismatch")
    _assert(_palette_slot(general, 13)["source_role"] == "declared_beyond_bg_palette_total_not_loaded", "General slot 13 role mismatch")
    _assert(general["metatile_binary_decode"]["status"] == "decoded", "General metatile decode missing")
    _assert(general["metatile_binary_decode"]["source_rules_profile"] == "emerald", "General metatile profile mismatch")
    _assert(general["metatile_binary_decode"]["source_binary"]["path"] == "data/tilesets/primary/general/metatiles.bin", "General metatile source mismatch")
    _assert(general["metatile_binary_decode"]["metatile_count"] == 512, "General metatile count mismatch")
    _assert(general["metatile_binary_decode"]["tile_entry_count"] == 4096, "General tile entry count mismatch")
    _assert(general["metatile_binary_decode"]["tile_source_kind_counts"] == {"primary": 4096}, "General tile source count mismatch")
    _assert(general["metatile_binary_decode"]["source_layer_slot_counts"] == {"bottom": 2048, "top": 2048}, "General layer count mismatch")
    _assert(general["metatile_binary_decode"]["out_of_range_tile_entry_count"] == 0, "General out-of-range tile ref")
    _assert(general["metatile_attribute_decode"]["status"] == "decoded", "General attribute decode missing")
    _assert(general["metatile_attribute_decode"]["source_rules_profile"] == "emerald", "General attribute profile mismatch")
    _assert(
        general["metatile_attribute_decode"]["source_binary"]["path"]
        == "data/tilesets/primary/general/metatile_attributes.bin",
        "General attribute source mismatch",
    )
    _assert(general["metatile_attribute_decode"]["record_byte_count"] == 2, "General attribute byte size mismatch")
    _assert(general["metatile_attribute_decode"]["metatile_attribute_count"] == 512, "General attribute count mismatch")
    _assert(general["metatile_attribute_decode"]["encounter_affordance_count"] == 75, "General encounter count mismatch")
    _assert(general["metatile_attribute_decode"]["terrain_type_status"] == "not_encoded_in_emerald_attributes", "General terrain status mismatch")
    _assert(general["metatile_attribute_decode"]["collision"]["status"] == "map_grid_block_field", "General collision source mismatch")
    general_first_attr = _metatile_attribute_record(exported, general, 0)
    _assert(general_first_attr["raw"] == 0, "General first attribute raw mismatch")
    _assert(general_first_attr["behavior_id"] == 0, "General first behavior id mismatch")
    _assert(general_first_attr["behavior_name"] == "MB_NORMAL", "General first behavior name mismatch")
    _assert(general_first_attr["layer_type_name"] == "METATILE_LAYER_TYPE_NORMAL", "General first layer mismatch")
    _assert(general_first_attr["terrain_type"] is None, "General terrain should not be decoded")
    _assert(general_first_attr["has_encounters"] is False, "General first encounter flag mismatch")
    _assert(general_first_attr["unused_traversable_hint"] is True, "General first unused hint mismatch")
    general_first_tile = _metatile_tile_entry(general, 0, 0)
    _assert(general_first_tile["raw"] == 0, "General first tile raw mismatch")
    _assert(general_first_tile["tile_id"] == 0, "General first tile id mismatch")
    _assert(general_first_tile["palette_slot"] == 0, "General first palette mismatch")
    _assert(general_first_tile["hflip"] is False and general_first_tile["vflip"] is False, "General first flip mismatch")
    _assert(general_first_tile["source_layer_slot"] == "bottom", "General first layer mismatch")
    _assert(general_first_tile["source_tileset_kind"] == "primary", "General first source kind mismatch")
    _assert(general_first_tile["local_tile_id"] == 0, "General first local tile mismatch")
    _assert(_metatile_tile_entry(general, 0, 4)["source_layer_slot"] == "top", "General top layer slot mismatch")
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
    _assert(petalburg["palette_slot_mapping"]["source_rules_profile"] == "emerald", "Petalburg palette profile mismatch")
    _assert(petalburg["palette_slot_mapping"]["declared_palette_slot_count"] == 16, "Petalburg palette slot count mismatch")
    _assert(petalburg["palette_slot_mapping"]["loaded_palette_slot_count"] == 7, "Petalburg loaded palette count mismatch")
    _assert(petalburg["palette_slot_mapping"]["loaded_global_bg_palette_slots"] == [6, 7, 8, 9, 10, 11, 12], "Petalburg loaded slots mismatch")
    _assert(_palette_slot(petalburg, 0)["source_role"] == "declared_global_slot_owned_by_primary", "Petalburg slot 0 role mismatch")
    petalburg_slot_6 = _palette_slot(petalburg, 6)
    _assert(petalburg_slot_6["loaded_by_source_map_palette_copy"], "Petalburg slot 6 should be loaded")
    _assert(petalburg_slot_6["global_bg_palette_slot"] == 6, "Petalburg slot 6 global slot mismatch")
    _assert(petalburg_slot_6["source_incbin"]["path"] == "data/tilesets/secondary/petalburg/palettes/06.gbapal", "Petalburg slot 6 incbin mismatch")
    _assert(_slot_has_candidate(petalburg_slot_6, "data/tilesets/secondary/petalburg/palettes/06.pal"), "Petalburg slot 6 source candidate missing")
    _assert(_palette_slot(petalburg, 12)["global_bg_palette_slot"] == 12, "Petalburg slot 12 global slot mismatch")
    _assert(_palette_slot(petalburg, 13)["source_role"] == "declared_beyond_bg_palette_total_not_loaded", "Petalburg slot 13 role mismatch")
    _assert(petalburg["metatile_binary_decode"]["source_binary"]["path"] == "data/tilesets/secondary/petalburg/metatiles.bin", "Petalburg metatile source mismatch")
    _assert(petalburg["metatile_binary_decode"]["metatile_count"] == 144, "Petalburg metatile count mismatch")
    _assert(petalburg["metatile_binary_decode"]["tile_entry_count"] == 1152, "Petalburg tile entry count mismatch")
    _assert(
        petalburg["metatile_binary_decode"]["tile_source_kind_counts"] == {"primary": 738, "secondary": 414},
        "Petalburg tile source counts mismatch",
    )
    _assert(_metatile_record(petalburg, 0)["global_metatile_id"] == 512, "Petalburg global metatile offset mismatch")
    _assert(petalburg["metatile_attribute_decode"]["metatile_attribute_count"] == 144, "Petalburg attribute count mismatch")
    _assert(
        petalburg["metatile_attribute_decode"]["layer_type_counts"]
        == {"METATILE_LAYER_TYPE_COVERED": 25, "METATILE_LAYER_TYPE_NORMAL": 119},
        "Petalburg attribute layer counts mismatch",
    )
    petalburg_second_attr = _metatile_attribute_record(exported, petalburg, 1)
    _assert(petalburg_second_attr["global_metatile_id"] == 513, "Petalburg attribute global offset mismatch")
    _assert(petalburg_second_attr["raw"] == 4096, "Petalburg second attribute raw mismatch")
    _assert(petalburg_second_attr["layer_type_name"] == "METATILE_LAYER_TYPE_COVERED", "Petalburg layer decode mismatch")
    _assert(_metatile_tile_entry(petalburg, 0, 0)["source_tileset_kind"] == "primary", "Petalburg primary tile ref missing")
    _assert(
        _metatile_tile_entry(petalburg, 0, 0)["source_tileset_kind_matches_metatile"] is False,
        "Petalburg cross-tileset tile ref should be preserved",
    )
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
    _assert(frlg_general["palette_slot_mapping"]["source_rules_profile"] == "frlg", "FRLG General palette profile mismatch")
    _assert(frlg_general["palette_slot_mapping"]["loaded_palette_slot_count"] == 7, "FRLG General loaded palette count mismatch")
    _assert(_palette_slot(frlg_general, 6)["global_bg_palette_slot"] == 6, "FRLG General slot 6 global mismatch")
    _assert(_palette_slot(frlg_general, 7)["source_role"] == "declared_global_slot_owned_by_secondary", "FRLG General slot 7 role mismatch")
    _assert(frlg_general["metatile_binary_decode"]["source_rules_profile"] == "frlg", "FRLG metatile profile mismatch")
    _assert(frlg_general["metatile_binary_decode"]["metatile_count"] == 640, "FRLG General metatile count mismatch")
    _assert(frlg_general["metatile_binary_decode"]["tile_entry_count"] == 5120, "FRLG General tile entry count mismatch")
    _assert(_metatile_record(frlg_general, -1)["global_metatile_id"] == 639, "FRLG General global metatile end mismatch")
    _assert(frlg_general["metatile_attribute_decode"]["source_rules_profile"] == "frlg", "FRLG attribute profile mismatch")
    _assert(frlg_general["metatile_attribute_decode"]["record_byte_count"] == 4, "FRLG attribute byte size mismatch")
    _assert(frlg_general["metatile_attribute_decode"]["metatile_attribute_count"] == 640, "FRLG attribute count mismatch")
    _assert(frlg_general["metatile_attribute_decode"]["terrain_type_status"] == "decoded", "FRLG terrain status mismatch")
    _assert(frlg_general["metatile_attribute_decode"]["encounter_type_status"] == "decoded", "FRLG encounter type status mismatch")
    _assert(
        frlg_general["metatile_attribute_decode"]["terrain_type_counts"]["TILE_TERRAIN_WATER"] == 122,
        "FRLG water terrain count mismatch",
    )
    _assert(
        frlg_general["metatile_attribute_decode"]["encounter_type_counts"]["TILE_ENCOUNTER_WATER"] == 125,
        "FRLG water encounter type count mismatch",
    )
    frlg_third_attr = _metatile_attribute_record(exported, frlg_general, 2)
    _assert(frlg_third_attr["raw"] == 536870941, "FRLG third attribute raw mismatch")
    _assert(frlg_third_attr["behavior_id"] == 29, "FRLG third behavior id mismatch")
    _assert(frlg_third_attr["layer_type_name"] == "METATILE_LAYER_TYPE_COVERED", "FRLG third layer mismatch")
    _assert(frlg_third_attr["terrain_type_name"] == "TILE_TERRAIN_NORMAL", "FRLG third terrain mismatch")
    _assert(frlg_third_attr["encounter_type_name"] == "TILE_ENCOUNTER_NONE", "FRLG third encounter type mismatch")
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
    _assert("metatile_attribute_detail_pending" not in unsupported_codes, "metatile attributes should be decoded now")
    _assert("source_equivalent_layer_renderer_pending" in unsupported_codes, "missing layer renderer pending code")
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


def _palette_slot(header, local_slot):
    return header["palette_slot_mapping"]["slots"][local_slot]


def _metatile_record(header, local_metatile_id):
    record = header["metatile_binary_decode"]["metatiles"][local_metatile_id]
    if isinstance(record, dict):
        return record
    return {
        "local_metatile_id": record[0],
        "global_metatile_id": record[1],
        "tile_entries": record[2],
    }


def _metatile_tile_entry(header, local_metatile_id, tile_entry_index):
    record = _metatile_record(header, local_metatile_id)
    entry = record["tile_entries"][tile_entry_index]
    if isinstance(entry, dict):
        return entry
    encoding = header["metatile_binary_decode"].get("metatile_entry_encoding", {})
    kind_codes = encoding.get("source_tileset_kind_codes", {})
    source_kind_by_code = {
        int(value): key
        for key, value in kind_codes.items()
    }
    flip_flags = int(entry[3])
    source_kind = source_kind_by_code.get(int(entry[4]), "unknown")
    layer_slots = encoding.get("source_layer_slot_by_tile_entry_index", [])
    positions = encoding.get("source_layer_position_by_tile_entry_index", [])
    return {
        "raw": entry[0],
        "tile_id": entry[1],
        "palette_slot": entry[2],
        "hflip": bool(flip_flags & 1),
        "vflip": bool(flip_flags & 2),
        "source_tileset_kind": source_kind,
        "local_tile_id": entry[5],
        "out_of_range": bool(entry[6]),
        "tile_entry_index": tile_entry_index,
        "source_layer_slot": layer_slots[tile_entry_index],
        "source_layer_position": positions[tile_entry_index],
        "source_tileset_kind_matches_metatile": source_kind == header["metatile_binary_decode"]["source_kind"],
    }


def _metatile_attribute_record(exported, header, local_metatile_id):
    record = header["metatile_attribute_decode"]["attributes"][local_metatile_id]
    if isinstance(record, dict):
        return record
    rules = exported["metatile_attribute_rules"]
    encoding = header["metatile_attribute_decode"].get("attribute_record_encoding", {})
    flag_codes = encoding.get("affordance_flag_codes", {})
    flags = int(record[7])
    layer_names = _enum_lookup(rules, "layer_type_names")
    terrain_names = _enum_lookup(rules, "tile_terrain_type_names")
    encounter_names = _enum_lookup(rules, "tile_encounter_type_names")
    return {
        "local_metatile_id": record[0],
        "global_metatile_id": record[1],
        "raw": record[2],
        "behavior_id": record[3],
        "behavior_name": rules["behavior_names_by_id"].get(str(record[3])),
        "layer_type": record[4],
        "layer_type_name": layer_names.get(record[4]),
        "terrain_type": record[5],
        "terrain_type_name": None if record[5] is None else terrain_names.get(record[5]),
        "encounter_type": record[6],
        "encounter_type_name": None if record[6] is None else encounter_names.get(record[6]),
        "has_encounters": bool(flags & flag_codes["has_encounters"]),
        "surfable": bool(flags & flag_codes["surfable"]),
        "land_encounter_affordance": bool(flags & flag_codes["land_encounter_affordance"]),
        "water_encounter_affordance": bool(flags & flag_codes["water_encounter_affordance"]),
        "unused_traversable_hint": bool(flags & flag_codes["unused_traversable_hint"]),
    }


def _enum_lookup(rules, enum_key):
    return {
        row["value"]: row["name"]
        for row in rules["attribute_enums"][enum_key]
    }


def _slot_has_candidate(slot, path):
    return any(
        row.get("path") == path and row.get("exists")
        for row in slot.get("editable_source_candidates", [])
    )


def _source_function_found(rules, symbol):
    return any(
        row.get("symbol") == symbol and row.get("found")
        for row in rules.get("source_functions", [])
    )


def _assert(condition, message):
    if not condition:
        raise AssertionError(message)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
