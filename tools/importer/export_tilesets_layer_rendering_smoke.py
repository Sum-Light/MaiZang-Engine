#!/usr/bin/env python3
"""Smoke checks for generated bottom/middle/top overworld layer render data."""

import argparse
import json
import sys
from pathlib import Path

from source_probe import load_config


EXPECTED_TILESETS = [
    "littleroot_town.json",
    "route101.json",
    "littleroot_town_brendans_house_1_f.json",
    "littleroot_town_mays_house_1_f.json",
]
LAYER_ROLES = ["bottom", "middle", "top"]
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, help="JSON config with generated roots.")
    parser.add_argument("--output-root", type=Path, help="Generated data output root.")
    parser.add_argument("--asset-root", type=Path, help="Generated asset output root.")
    args = parser.parse_args(argv)

    config = load_config(args.config)
    output_root = args.output_root or Path(config.get("generated_data_root", "data/generated"))
    asset_root = args.asset_root or Path(config.get("generated_asset_root", "assets/generated"))
    project_root = Path.cwd()

    total_metatiles = 0
    total_layer_atlases = 0
    found_layer_types = set()
    for filename in EXPECTED_TILESETS:
        path = output_root / "tilesets" / filename
        require(path.exists(), "missing generated tileset {}".format(path))
        data = read_json(path)
        atlas = data.get("atlas", {})
        total_metatiles += int(atlas.get("total_metatiles", 0))
        entries = data.get("metatile_entries", [])
        require(len(entries) == int(atlas.get("total_metatiles", -1)), "metatile entry count mismatch in {}".format(filename))

        layer_rendering = data.get("layer_rendering", {})
        require(isinstance(layer_rendering, dict), "missing layer_rendering in {}".format(filename))
        policy = layer_rendering.get("policy", {})
        require(policy.get("artifact_kind") == "layer_metatile_rgba_atlas", "unexpected layer artifact kind")
        require(
            policy.get("runtime_layering_status") == "layer_render_data_exported_renderer_pending",
            "unexpected layer renderer status",
        )
        require(policy.get("source_equivalent_for_runtime_layering") is False, "layer data must keep runtime parity pending")

        layer_atlases = layer_rendering.get("layer_atlases", {})
        require(sorted(layer_atlases.keys()) == LAYER_ROLES, "expected bottom/middle/top layer atlases")
        total_layer_atlases += len(layer_atlases)
        expected_width = int(atlas.get("columns", 0)) * int(atlas.get("tile_size", 0))
        expected_height = int(atlas.get("rows", 0)) * int(atlas.get("tile_size", 0))
        for role in LAYER_ROLES:
            atlas_record = layer_atlases[role]
            require(atlas_record.get("artifact_kind") == "layer_metatile_rgba_atlas", "unexpected role atlas kind")
            require(atlas_record.get("role") == role, "unexpected role atlas record")
            image_path = project_root / atlas_record.get("image_project_path", "")
            require(image_path.exists(), "missing layer atlas image {}".format(image_path))
            width, height = read_png_dimensions(image_path)
            require((width, height) == (expected_width, expected_height), "unexpected layer atlas dimensions")

        summary = layer_rendering.get("summary", {})
        require(summary.get("metatile_count") == len(entries), "unexpected layer summary metatile count")
        require(summary.get("atlas_count") == 3, "unexpected layer summary atlas count")
        require(summary.get("missing_render_layer_record_count") == 0, "missing render layer records")
        require(summary.get("source_fill_layer_count", 0) > 0, "expected normal bottom source-fill records")

        for layer_type in [0, 1, 2]:
            entry = find_entry_for_layer_type(entries, layer_type)
            if entry is not None:
                found_layer_types.add(layer_type)
                check_layer_rules(entry, layer_type)

        assert_no_disallowed_runtime_keys(layer_rendering)

    require(found_layer_types == {0, 1, 2}, "expected generated data to cover normal/covered/split layer types")
    print(json.dumps({
        "export_tilesets_layer_rendering_smoke": "ok",
        "tileset_count": len(EXPECTED_TILESETS),
        "total_metatiles": total_metatiles,
        "layer_atlas_count": total_layer_atlases,
    }, indent=2))


def check_layer_rules(entry, layer_type):
    render_layers = entry.get("render_layers", {})
    layers = render_layers.get("layers", {})
    if layer_type == 0:
        require(layers["bottom"]["operation"] == "source_fill_tile", "normal bottom should preserve source fill")
        require(layers["middle"]["source_tile_indexes"] == [0, 1, 2, 3], "normal middle should draw bottom slots")
        require(layers["top"]["source_tile_indexes"] == [4, 5, 6, 7], "normal top should draw top slots")
    elif layer_type == 1:
        require(layers["bottom"]["source_tile_indexes"] == [0, 1, 2, 3], "covered bottom should draw bottom slots")
        require(layers["middle"]["source_tile_indexes"] == [4, 5, 6, 7], "covered middle should draw top slots")
        require(layers["top"]["operation"] == "clear", "covered top should clear")
    elif layer_type == 2:
        require(layers["bottom"]["source_tile_indexes"] == [0, 1, 2, 3], "split bottom should draw bottom slots")
        require(layers["middle"]["operation"] == "clear", "split middle should clear")
        require(layers["top"]["source_tile_indexes"] == [4, 5, 6, 7], "split top should draw top slots")


def find_entry_for_layer_type(entries, layer_type):
    for entry in entries:
        attribute = entry.get("attribute", {})
        if int(attribute.get("layer_type", -1)) == layer_type:
            return entry
    return None


def assert_no_disallowed_runtime_keys(value):
    if isinstance(value, dict):
        for key, child in value.items():
            key_text = str(key).lower()
            require("palette" not in key_text, "unexpected runtime key {}".format(key))
            require("source_color" not in key_text, "unexpected runtime key {}".format(key))
            require("source_palette" not in key_text, "unexpected runtime key {}".format(key))
            assert_no_disallowed_runtime_keys(child)
    elif isinstance(value, list):
        for child in value:
            assert_no_disallowed_runtime_keys(child)


def read_json(path):
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def read_png_dimensions(path):
    data = path.read_bytes()
    require(len(data) >= 24 and data[:8] == PNG_SIGNATURE and data[12:16] == b"IHDR", "{} is not a PNG".format(path))
    return int.from_bytes(data[16:20], "big"), int.from_bytes(data[20:24], "big")


def require(condition, message):
    if not condition:
        raise AssertionError(message)


if __name__ == "__main__":
    try:
        main(sys.argv[1:])
    except AssertionError as error:
        print("export_tilesets_layer_rendering_smoke: FAIL: {}".format(error), file=sys.stderr)
        raise SystemExit(1)
