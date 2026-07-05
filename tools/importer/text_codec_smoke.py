#!/usr/bin/env python3
"""Smoke checks for charmap-backed source text encoding."""

import argparse
import sys
from pathlib import Path

from source_probe import load_config
from text_codec import display_text_from_source, encode_source_text, load_charmap


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, help="JSON config with source root.")
    parser.add_argument("--source", type=Path, help="pokeemerald-expansion source root.")
    args = parser.parse_args(argv)

    config = load_config(args.config)
    source_root = args.source or Path(config.get("source_root", ""))
    charmap = load_charmap(source_root / "charmap.txt")

    _assert(charmap.escapes["n"] == [0xFE], "expected newline escape byte")
    _assert(charmap.escapes["p"] == [0xFB], "expected paragraph escape byte")
    _assert(charmap.escapes["l"] == [0xFA], "expected line escape byte")
    _assert(charmap.chars["$"] == [0xFF], "expected string terminator byte")
    _assert(charmap.chars["\u4e00"] == [0x0F, 0x0B], "expected mapped CJK byte sequence")

    controls = encode_source_text("\\n\\p\\l$", charmap)
    _assert(controls["status"] == "ok", "expected control escape encoding")
    _assert(controls["bytes"] == [0xFE, 0xFB, 0xFA, 0xFF], "unexpected control bytes")
    _assert(controls["terminator_present"], "expected terminator metadata")
    _assert(controls["glyphs"] == [], "expected no visible glyphs for source control escapes")

    glyphs = encode_source_text("\u4e00$", charmap)
    _assert(glyphs["status"] == "ok", "expected visible glyph encoding")
    _assert(len(glyphs["glyphs"]) == 1, "expected one visible glyph span")
    _assert(glyphs["glyphs"][0]["text"] == "\u4e00", "expected glyph text metadata")
    _assert(glyphs["glyphs"][0]["byte_offset"] == 0, "expected glyph byte offset")
    _assert(glyphs["glyphs"][0]["byte_count"] == 2, "expected mapped CJK glyph byte count")
    _assert(glyphs["glyphs"][0]["bytes"] == [0x0F, 0x0B], "expected mapped CJK glyph bytes")

    constants = encode_source_text("{STR_VAR_1}{PAUSE 96}$", charmap)
    _assert(constants["status"] == "ok", "expected braced constants encoding")
    _assert(constants["bytes"] == [0xFD, 0x02, 0xFC, 0x08, 0x60, 0xFF], "unexpected constant bytes")
    _assert(constants["placeholders"][0]["token"] == "STR_VAR_1", "expected placeholder metadata")

    display = display_text_from_source("A\\nB\\pC$")
    _assert(display == "A\nB\n\nC", "unexpected display text conversion")

    print("text_codec_smoke: ok")
    return 0


def _assert(condition, message):
    if not condition:
        raise AssertionError(message)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
