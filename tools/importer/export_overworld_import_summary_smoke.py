#!/usr/bin/env python3
"""Smoke checks for the overworld import summary export."""

import argparse
import sys
from pathlib import Path

from export_overworld_import_summary import build_export
from source_probe import load_config


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, help="JSON config with source and output roots.")
    parser.add_argument("--source", type=Path, help="pokeemerald-expansion source root.")
    parser.add_argument("--output-root", type=Path, help="Generated data output root.")
    args = parser.parse_args(argv)

    config = load_config(args.config)
    source_root = args.source or Path(config.get("source_root", ""))
    output_root = args.output_root or Path(config.get("generated_data_root", "data/generated"))
    exported = build_export(source_root, output_root)
    source = exported["source_counts"]
    generated = exported["generated_counts"]
    coverage = exported["coverage"]

    _assert(exported["schema_version"] == 1, "unexpected schema version")
    _assert(exported["generated_by"].endswith("export_overworld_import_summary.py"), "unexpected generator")

    _assert(source["map_count"] == 939, "unexpected source map count")
    _assert(source["map_script_file_count"] == 887, "unexpected source map script count")
    _assert(source["layout_count"] == 785, "unexpected source layout count")
    _assert(source["layout_blockdata_entry_count"] == 564213, "unexpected source layout blockdata count")
    _assert(source["layout_blockdata_missing_file_count"] == 0, "unexpected missing source layout blockdata count")
    _assert(source["layout_blockdata_invalid_file_count"] == 0, "unexpected invalid source layout blockdata count")
    _assert(source["primary_tileset_image_count"] == 5, "unexpected source primary tileset count")
    _assert(source["secondary_tileset_image_count"] == 127, "unexpected source secondary tileset count")
    _assert(source["tileset_tile_image_count"] == 138, "unexpected recursive source tile image count")
    _assert(source["tileset_tile_image_tile_count"] == 39376, "unexpected recursive source tile image tile count")
    _assert(source["tileset_invalid_tile_image_count"] == 0, "unexpected invalid source tile image count")
    _assert(source["tileset_header_count"] == 139, "unexpected source tileset header count")
    _assert(source["tileset_callback_count"] == 31, "unexpected source tileset callback count")
    _assert(source["tileset_anim_init_function_count"] == 31, "unexpected source tileset anim init count")
    _assert(source["tileset_anim_source_frame_count"] == 182, "unexpected source tileset anim frame source count")
    _assert(source["tileset_anim_source_group_count"] == 174, "unexpected source tileset anim group count")
    _assert(source["tileset_palette_reference_count"] == 2224, "unexpected source tileset palette ref count")
    _assert(source["tileset_unique_palette_reference_count"] == 2208, "unexpected unique palette ref count")
    _assert(source["tileset_palette_array_symbol_count"] == 139, "unexpected palette array symbol count")
    _assert(source["tileset_metatile_binary_count"] == 134, "unexpected source metatile binary count")
    _assert(source["tileset_metatile_record_count"] == 27593, "unexpected source metatile record count")
    _assert(source["tileset_metatile_tile_entry_count"] == 220744, "unexpected source metatile tile entry count")
    _assert(source["tileset_invalid_metatile_binary_count"] == 0, "unexpected invalid metatile binary count")
    _assert(source["tileset_metatile_attribute_binary_count"] == 134, "unexpected source attribute binary count")
    _assert(source["tileset_metatile_attribute_record_count"] == 27593, "unexpected source attribute record count")
    _assert(
        source["tileset_metatile_attribute_binary_count_by_source_profile"] == {"emerald_u16": 70, "frlg_u32": 64},
        "unexpected source attribute profile count",
    )
    _assert(
        source["tileset_invalid_metatile_attribute_binary_count"] == 0,
        "unexpected invalid attribute binary count",
    )
    _assert(source["tileset_metatile_label_count"] == 924, "unexpected source metatile label count")
    _assert(
        source["tileset_metatile_label_source_group_count"] == 77,
        "unexpected source metatile label group count",
    )
    _assert(source["layout_tileset_pair_count"] == 137, "unexpected source layout tileset pair count")
    _assert(source["layout_tileset_pair_layout_count"] == 785, "unexpected source pair layout count")
    _assert(source["door_animation_table_entry_count"] == 53, "unexpected active Emerald door table count")
    _assert(source["object_event_graphics_info_count"] == 393, "unexpected source object-event graphics count")

    _assert(generated["map_count"] == 939, "unexpected generated map count")
    _assert(generated["layout_count"] == 785, "unexpected generated layout count")
    _assert(generated["map_referenced_layout_count"] == 711, "unexpected map-referenced layout count")
    _assert(generated["standalone_layout_count"] == 74, "unexpected standalone layout count")
    _assert(generated["missing_layout_file_count"] == 0, "expected zero missing generated layouts")
    _assert(generated["layout_map_grid_entry_count"] > generated["map_count"], "layout grid totals missing")
    _assert(generated["layout_border_entry_count"] >= 785, "layout border totals missing")
    _assert(generated["layout_warning_count"] == 20, "unexpected layout warning count")
    _assert(generated["tileset_record_count"] == 4, "unexpected generated tileset record count")
    _assert(generated["unique_primary_tileset_count"] == 2, "unexpected generated primary tileset count")
    _assert(generated["unique_secondary_tileset_count"] == 2, "unexpected generated secondary tileset count")
    _assert(generated["tileset_flattened_debug_atlas_count"] == 4, "unexpected debug atlas count")
    _assert(
        generated["tileset_runtime_layering_non_equivalent_atlas_count"] == 4,
        "unexpected non-equivalent runtime layering atlas count",
    )
    _assert(
        generated["tileset_runtime_layering_source_equivalent_atlas_count"] == 0,
        "flattened atlases must not be marked source-equivalent for runtime layering",
    )
    _assert(
        generated["tileset_runtime_layering_metadata_missing_count"] == 0,
        "missing generated atlas runtime-layering metadata",
    )
    _assert(generated["tileset_header_report_count"] == 1, "missing tileset header report")
    _assert(generated["tileset_header_record_count"] == 139, "unexpected generated tileset header count")
    _assert(
        generated["active_emerald_tileset_header_record_count"] == 75,
        "unexpected active Emerald tileset header count",
    )
    _assert(
        generated["tileset_animation_frame_declaration_count"] == 174,
        "unexpected generated animation frame declaration count",
    )
    _assert(generated["tileset_animation_source_image_count"] == 182, "unexpected animation source image count")
    _assert(generated["tileset_palette_slot_mapping_count"] == 2224, "unexpected palette slot mapping count")
    _assert(
        generated["active_emerald_tileset_palette_slot_mapping_count"] == 1200,
        "unexpected active palette slot mapping count",
    )
    _assert(
        generated["tileset_loaded_palette_slot_mapping_count"] == 908,
        "unexpected loaded palette slot mapping count",
    )
    _assert(
        generated["active_emerald_tileset_loaded_palette_slot_mapping_count"] == 522,
        "unexpected active loaded palette slot mapping count",
    )
    _assert(generated["tileset_palette_source_candidate_count"] == 2224, "unexpected palette candidate count")
    _assert(
        generated["tileset_existing_palette_source_candidate_count"] == 2224,
        "unexpected existing palette candidate count",
    )
    _assert(
        generated["tileset_missing_palette_source_candidate_count"] == 0,
        "unexpected missing palette candidate count",
    )
    _assert(
        generated["tileset_header_missing_callback_source_count"] == 0,
        "unexpected missing tileset callback source count",
    )
    _assert(generated["tileset_header_metatile_decode_count"] == 139, "unexpected header metatile decode count")
    _assert(
        generated["active_emerald_tileset_header_metatile_decode_count"] == 75,
        "unexpected active header metatile decode count",
    )
    _assert(generated["tileset_header_metatile_record_count"] == 29213, "unexpected header-expanded metatile count")
    _assert(
        generated["active_emerald_tileset_header_metatile_record_count"] == 18318,
        "unexpected active header-expanded metatile count",
    )
    _assert(generated["tileset_header_metatile_tile_entry_count"] == 233704, "unexpected header-expanded tile entry count")
    _assert(
        generated["active_emerald_tileset_header_metatile_tile_entry_count"] == 146544,
        "unexpected active header-expanded tile entry count",
    )
    _assert(
        generated["tileset_header_unique_metatile_source_binary_count"] == 134,
        "unexpected unique generated metatile binary count",
    )
    _assert(generated["tileset_header_unique_metatile_record_count"] == 27593, "unexpected unique generated metatile count")
    _assert(
        generated["tileset_header_unique_metatile_tile_entry_count"] == 220744,
        "unexpected unique generated tile entry count",
    )
    _assert(
        generated["tileset_header_metatile_out_of_range_tile_entry_count"] == 0,
        "unexpected out-of-range metatile tile refs",
    )
    _assert(
        generated["tileset_header_metatile_attribute_decode_count"] == 139,
        "unexpected header attribute decode count",
    )
    _assert(
        generated["active_emerald_tileset_header_metatile_attribute_decode_count"] == 75,
        "unexpected active header attribute decode count",
    )
    _assert(
        generated["tileset_header_metatile_attribute_record_count"] == 29213,
        "unexpected header-expanded attribute record count",
    )
    _assert(
        generated["active_emerald_tileset_header_metatile_attribute_record_count"] == 18318,
        "unexpected active header-expanded attribute count",
    )
    _assert(
        generated["tileset_header_unique_metatile_attribute_source_binary_count"] == 134,
        "unexpected unique generated attribute binary count",
    )
    _assert(
        generated["tileset_header_unique_metatile_attribute_record_count"] == 27593,
        "unexpected unique generated attribute record count",
    )
    _assert(
        generated["tileset_header_metatile_attribute_encounter_affordance_count"] == 2023,
        "unexpected generated attribute encounter affordance count",
    )
    _assert(
        generated["active_emerald_tileset_header_metatile_attribute_encounter_affordance_count"] == 1009,
        "unexpected active generated attribute encounter affordance count",
    )
    _assert(
        generated["tileset_header_metatile_attribute_missing_behavior_name_count"] == 0,
        "unexpected generated missing behavior name count",
    )
    _assert(
        generated["tileset_header_metatile_label_source_label_count"] == 924,
        "unexpected generated metatile label source count",
    )
    _assert(
        generated["tileset_header_metatile_label_source_group_count"] == 77,
        "unexpected generated metatile label group count",
    )
    _assert(
        generated["tileset_header_metatile_label_decode_count"] == 77,
        "unexpected generated metatile label header count",
    )
    _assert(
        generated["active_emerald_tileset_header_metatile_label_decode_count"] == 46,
        "unexpected active generated metatile label header count",
    )
    _assert(
        generated["tileset_header_metatile_label_record_count"] == 924,
        "unexpected generated metatile label record count",
    )
    _assert(
        generated["active_emerald_tileset_header_metatile_label_record_count"] == 698,
        "unexpected active generated metatile label record count",
    )
    _assert(
        generated["tileset_header_metatile_label_pair_lookup_count"] == 137,
        "unexpected generated metatile label pair count",
    )
    _assert(
        generated["tileset_header_metatile_label_pair_lookup_layout_count"] == 785,
        "unexpected generated metatile label pair layout count",
    )
    _assert(
        generated["tileset_header_metatile_label_pair_label_record_count"] == 3960,
        "unexpected generated pair label record count",
    )
    _assert(
        generated["tileset_header_metatile_label_pair_out_of_range_count"] == 1620,
        "unexpected generated pair out-of-range label count",
    )
    _assert(
        generated["tileset_header_metatile_map_reference_layout_count"] == 785,
        "unexpected generated map reference layout count",
    )
    _assert(
        generated["tileset_header_metatile_map_reference_checked_layout_count"] == 785,
        "unexpected generated checked map reference layout count",
    )
    _assert(
        generated["tileset_header_metatile_map_reference_pair_count"] == 137,
        "unexpected generated map reference pair count",
    )
    _assert(
        generated["tileset_header_metatile_map_reference_checked_cell_count"] == 564213,
        "unexpected generated checked map reference cell count",
    )
    _assert(
        generated["tileset_header_metatile_map_reference_declared_cell_count"] == 564193,
        "unexpected generated declared map reference cell count",
    )
    _assert(
        generated["tileset_header_metatile_map_reference_unique_metatile_id_count"] == 1021,
        "unexpected generated map reference unique metatile count",
    )
    _assert(
        generated["tileset_header_metatile_map_reference_absent_cell_count"] == 1607,
        "unexpected generated absent map reference cell count",
    )
    _assert(
        generated["tileset_header_metatile_map_reference_absent_unique_reference_count"] == 129,
        "unexpected generated absent map reference unique count",
    )
    _assert(
        generated["tileset_header_metatile_map_reference_absent_global_metatile_id_count"] == 129,
        "unexpected generated absent map reference global id count",
    )
    _assert(
        generated["tileset_header_metatile_map_reference_layout_with_absent_count"] == 5,
        "unexpected generated map reference layout-with-absent count",
    )
    _assert(
        generated["tileset_header_metatile_map_reference_pair_with_absent_count"] == 3,
        "unexpected generated map reference pair-with-absent count",
    )
    _assert(
        generated["tileset_header_metatile_map_reference_missing_blockdata_layout_count"] == 0,
        "unexpected generated missing map reference blockdata count",
    )
    _assert(
        generated["tileset_header_metatile_map_reference_invalid_blockdata_layout_count"] == 0,
        "unexpected generated invalid map reference blockdata count",
    )
    _assert(
        generated["tileset_header_metatile_map_reference_size_mismatch_layout_count"] == 20,
        "unexpected generated map reference size mismatch count",
    )
    _assert(
        generated["tileset_header_tile_image_reference_header_count"] == 139,
        "unexpected generated tile image reference header count",
    )
    _assert(
        generated["tileset_header_tile_image_reference_header_image_binding_count"] == 139,
        "unexpected generated tile image binding count",
    )
    _assert(
        generated["tileset_header_tile_image_reference_decoded_image_binding_count"] == 139,
        "unexpected generated decoded tile image binding count",
    )
    _assert(
        generated["tileset_header_tile_image_reference_unique_source_image_count"] == 138,
        "unexpected generated unique tile image count",
    )
    _assert(
        generated["tileset_header_tile_image_reference_unique_source_image_tile_count"] == 39376,
        "unexpected generated unique tile image tile count",
    )
    _assert(
        generated["tileset_header_tile_image_reference_header_checked_tile_entry_count"] == 128122,
        "unexpected generated header checked tile image entry count",
    )
    _assert(
        generated["tileset_header_tile_image_reference_header_foreign_tile_entry_count"] == 105582,
        "unexpected generated header foreign tile image entry count",
    )
    _assert(
        generated["tileset_header_tile_image_reference_header_absent_tile_entry_count"] == 44,
        "unexpected generated header absent tile image entry count",
    )
    _assert(
        generated["tileset_header_tile_image_reference_header_absent_unique_tile_reference_count"] == 22,
        "unexpected generated header absent tile image unique count",
    )
    _assert(
        generated["tileset_header_tile_image_reference_header_with_absent_tile_count"] == 3,
        "unexpected generated header-with-absent tile image count",
    )
    _assert(
        generated["tileset_header_tile_image_reference_pair_count"] == 137,
        "unexpected generated pair tile image reference count",
    )
    _assert(
        generated["tileset_header_tile_image_reference_pair_checked_tile_entry_count"] == 674424,
        "unexpected generated pair checked tile image entry count",
    )
    _assert(
        generated["tileset_header_tile_image_reference_pair_absent_tile_entry_count"] == 3782,
        "unexpected generated pair absent tile image entry count",
    )
    _assert(
        generated["tileset_header_tile_image_reference_pair_absent_unique_tile_reference_count"] == 1629,
        "unexpected generated pair absent tile image unique count",
    )
    _assert(
        generated["tileset_header_tile_image_reference_pair_with_absent_tile_count"] == 30,
        "unexpected generated pair-with-absent tile image count",
    )
    _assert(
        generated["tileset_header_tile_image_reference_pair_missing_header_count"] == 1,
        "unexpected generated pair missing header tile image count",
    )
    _assert(generated["script_bundle_count"] == 971, "unexpected generated script bundle count")
    _assert(generated["map_script_bundle_count"] == 887, "unexpected generated map script bundle count")
    _assert(generated["shared_script_bundle_count"] == 84, "unexpected generated shared script bundle count")
    _assert(generated["script_count"] == 13000, "unexpected generated script count")
    _assert(generated["movement_label_count"] == 1489, "unexpected movement label count")
    _assert(generated["movement_action_count"] == 9848, "unexpected movement action count")
    _assert(generated["movement_action_count_excluding_step_end"] == 8376, "unexpected non-terminal movement action count")
    _assert(generated["script_runtime_preview_unsupported_op_count"] == 45218, "unexpected script preview unsupported op count")
    _assert(generated["door_animation_count"] == 2, "unexpected generated door animation count")
    _assert(generated["door_animation_frame_count"] == 6, "unexpected generated door frame count")
    _assert(generated["tileset_animation_count"] == 0, "tileset animations should remain ungenerated")
    _assert(generated["object_event_graphic_count"] == 11, "unexpected generated object-event graphics count")
    _assert(generated["object_event_count"] == 4426, "unexpected generated object-event count")
    _assert(generated["warp_event_count"] == 2607, "unexpected generated warp-event count")
    _assert(generated["coord_event_count"] == 603, "unexpected generated coord-event count")
    _assert(generated["bg_event_count"] == 1422, "unexpected generated BG-event count")
    _assert(generated["connection_count"] == 266, "unexpected generated connection count")
    _assert(generated["missing_map_file_count"] == 0, "expected zero missing generated maps")
    _assert(generated["warning_count"] == 20, "unexpected generated warning count")
    _assert(generated["parity_matrix_unsupported_entry_count"] == 15, "unexpected parity unsupported entry count")
    _assert(generated["object_event_sprite_unsupported_note_count"] == 15, "unexpected object sprite unsupported note count")
    _assert(generated["explicit_summary_unsupported_count"] == 5, "unexpected explicit unsupported summary count")

    _assert(coverage["maps"]["percent"] == 100.0, "unexpected map coverage percent")
    _assert(coverage["layouts"]["percent"] == 100.0, "unexpected layout coverage percent")
    _assert(coverage["tileset_headers"]["percent"] == 100.0, "unexpected tileset header coverage percent")
    _assert(coverage["tileset_animation_callbacks"]["generated"] == 0, "expected no generated tileset anims")
    _assert(
        coverage["tileset_animation_source_images"]["percent"] == 100.0,
        "unexpected tileset animation source image coverage percent",
    )
    _assert(coverage["tileset_palette_sources"]["generated"] == 2224, "unexpected palette coverage generated count")
    _assert(coverage["tileset_palette_sources"]["source"] == 2224, "unexpected palette coverage source count")
    _assert(coverage["tileset_palette_sources"]["percent"] == 100.0, "unexpected palette coverage percent")
    _assert(coverage["tileset_metatile_binaries"]["generated"] == 134, "unexpected metatile binary coverage count")
    _assert(coverage["tileset_metatile_binaries"]["source"] == 134, "unexpected metatile binary source count")
    _assert(coverage["tileset_metatile_binaries"]["percent"] == 100.0, "unexpected metatile binary coverage percent")
    _assert(coverage["tileset_metatile_records"]["generated"] == 27593, "unexpected metatile record coverage count")
    _assert(coverage["tileset_metatile_records"]["source"] == 27593, "unexpected metatile record source count")
    _assert(coverage["tileset_metatile_records"]["percent"] == 100.0, "unexpected metatile record coverage percent")
    _assert(coverage["tileset_metatile_tile_entries"]["generated"] == 220744, "unexpected tile entry coverage count")
    _assert(coverage["tileset_metatile_tile_entries"]["source"] == 220744, "unexpected tile entry source count")
    _assert(coverage["tileset_metatile_tile_entries"]["percent"] == 100.0, "unexpected tile entry coverage percent")
    _assert(
        coverage["tileset_metatile_attribute_binaries"]["generated"] == 134,
        "unexpected attribute binary coverage count",
    )
    _assert(
        coverage["tileset_metatile_attribute_binaries"]["source"] == 134,
        "unexpected attribute binary source count",
    )
    _assert(
        coverage["tileset_metatile_attribute_binaries"]["percent"] == 100.0,
        "unexpected attribute binary coverage percent",
    )
    _assert(
        coverage["tileset_metatile_attribute_records"]["generated"] == 27593,
        "unexpected attribute record coverage count",
    )
    _assert(
        coverage["tileset_metatile_attribute_records"]["source"] == 27593,
        "unexpected attribute record source count",
    )
    _assert(
        coverage["tileset_metatile_attribute_records"]["percent"] == 100.0,
        "unexpected attribute record coverage percent",
    )
    _assert(coverage["tileset_metatile_labels"]["generated"] == 924, "unexpected label coverage count")
    _assert(coverage["tileset_metatile_labels"]["source"] == 924, "unexpected label coverage source count")
    _assert(coverage["tileset_metatile_labels"]["percent"] == 100.0, "unexpected label coverage percent")
    _assert(coverage["tileset_metatile_label_pairs"]["generated"] == 137, "unexpected pair coverage count")
    _assert(coverage["tileset_metatile_label_pairs"]["source"] == 137, "unexpected pair coverage source count")
    _assert(coverage["tileset_metatile_label_pairs"]["percent"] == 100.0, "unexpected pair coverage percent")
    _assert(
        coverage["tileset_metatile_map_reference_layouts"]["generated"] == 785,
        "unexpected map reference layout coverage count",
    )
    _assert(
        coverage["tileset_metatile_map_reference_layouts"]["source"] == 785,
        "unexpected map reference layout coverage source",
    )
    _assert(
        coverage["tileset_metatile_map_reference_layouts"]["percent"] == 100.0,
        "unexpected map reference layout coverage percent",
    )
    _assert(
        coverage["tileset_metatile_map_reference_cells"]["generated"] == 564213,
        "unexpected map reference cell coverage count",
    )
    _assert(
        coverage["tileset_metatile_map_reference_cells"]["source"] == 564213,
        "unexpected map reference cell coverage source",
    )
    _assert(
        coverage["tileset_metatile_map_reference_cells"]["percent"] == 100.0,
        "unexpected map reference cell coverage percent",
    )
    _assert(coverage["tileset_tile_images"]["generated"] == 138, "unexpected tile image coverage count")
    _assert(coverage["tileset_tile_images"]["source"] == 138, "unexpected tile image coverage source")
    _assert(coverage["tileset_tile_images"]["percent"] == 100.0, "unexpected tile image coverage percent")
    _assert(coverage["tileset_tile_image_tiles"]["generated"] == 39376, "unexpected tile image tile coverage")
    _assert(coverage["tileset_tile_image_tiles"]["source"] == 39376, "unexpected tile image tile source")
    _assert(coverage["tileset_tile_image_tiles"]["percent"] == 100.0, "unexpected tile image tile coverage percent")
    _assert(
        coverage["tileset_tile_image_header_bindings"]["generated"] == 139,
        "unexpected tile image binding coverage count",
    )
    _assert(
        coverage["tileset_tile_image_header_bindings"]["source"] == 139,
        "unexpected tile image binding coverage source",
    )
    _assert(
        coverage["tileset_tile_image_header_bindings"]["percent"] == 100.0,
        "unexpected tile image binding coverage percent",
    )
    _assert(
        coverage["tileset_metatile_tile_image_pairs"]["generated"] == 137,
        "unexpected metatile tile image pair coverage count",
    )
    _assert(
        coverage["tileset_metatile_tile_image_pairs"]["source"] == 137,
        "unexpected metatile tile image pair coverage source",
    )
    _assert(
        coverage["tileset_metatile_tile_image_pairs"]["percent"] == 100.0,
        "unexpected metatile tile image pair coverage percent",
    )

    unsupported_codes = {entry["code"] for entry in exported["unsupported"]}
    _assert("tileset_animation_runtime_pending" in unsupported_codes, "missing tileset animation unsupported code")
    _assert("audio_playback_pending" in unsupported_codes, "missing audio unsupported code")
    _assert("object_event_sprite_coverage_pending" in unsupported_codes, "missing object sprite coverage code")
    _assert("door_overlay_not_source_equivalent" in unsupported_codes, "missing door unsupported code")
    _assert(
        "flattened_debug_atlas_not_source_equivalent" in unsupported_codes,
        "missing flattened atlas unsupported code",
    )

    map_names = {entry["name"] for entry in exported["details"]["maps"]}
    _assert("LittlerootTown" in map_names, "missing Littleroot summary")
    _assert("Route101" in map_names, "missing Route101 summary")
    layout_ids = {entry["id"] for entry in exported["details"]["layouts"]}
    _assert("LAYOUT_LITTLEROOT_TOWN" in layout_ids, "missing Littleroot layout summary")
    _assert(
        "LAYOUT_LITTLEROOT_TOWN_PROFESSOR_BIRCHS_LAB_WITH_TABLE" in layout_ids,
        "missing standalone layout summary",
    )
    _assert(exported["details"]["movement_op_counts"]["step_end"] == 1472, "unexpected step_end count")
    for tileset in exported["details"]["tilesets"]:
        _assert(
            tileset["atlas_artifact_kind"] == "flattened_metatile_debug_atlas",
            "expected flattened debug atlas artifact kind",
        )
        _assert(bool(tileset["atlas_debug_only"]), "expected debug-only atlas")
        _assert(
            tileset["atlas_source_equivalent_for_runtime_layering"] is False,
            "expected non-equivalent atlas runtime-layering metadata",
        )
        _assert(
            tileset["atlas_runtime_layering_status"] == "not_source_equivalent",
            "expected non-equivalent runtime-layering status",
        )
        _assert(
            tileset["atlas_unsupported_code"] == "flattened_debug_atlas_not_source_equivalent",
            "expected flattened atlas unsupported code",
        )

    print("export_overworld_import_summary_smoke: ok")
    return 0


def _assert(condition, message):
    if not condition:
        raise AssertionError(message)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
