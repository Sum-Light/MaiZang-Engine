#!/usr/bin/env python3
"""Charmap-backed source text helpers for generated script data."""

import re
from dataclasses import dataclass
from pathlib import Path


IDENTIFIER_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
DECIMAL_RE = re.compile(r"^[0-9]+[HW]?$")
HEX_RE = re.compile(r"^0x[0-9A-Fa-f]+$")


@dataclass(frozen=True)
class Charmap:
    chars: dict
    escapes: dict
    constants: dict


def load_charmap(path):
    chars = {}
    escapes = {}
    constants = {}

    for line_number, raw_line in enumerate(Path(path).read_text(encoding="utf-8").splitlines(), start=1):
        line = _remove_comment(raw_line)
        if not line.strip():
            continue

        lhs, rhs = _split_assignment(line, path, line_number)
        kind, key = _parse_lhs(lhs.strip(), path, line_number)
        sequence = _parse_byte_sequence(rhs.strip(), path, line_number)

        if kind == "char":
            if key in chars:
                raise ValueError("{}:{}: redefined char {!r}".format(path, line_number, key))
            chars[key] = sequence
        elif kind == "escape":
            if key in escapes:
                raise ValueError("{}:{}: redefined escape {!r}".format(path, line_number, key))
            escapes[key] = sequence
        else:
            if key in constants:
                raise ValueError("{}:{}: redefined constant {!r}".format(path, line_number, key))
            constants[key] = sequence

    return Charmap(chars=chars, escapes=escapes, constants=constants)


def encode_source_text(raw_text, charmap):
    encoder = _TextEncoder(raw_text, charmap)
    return encoder.encode()


def display_text_from_source(raw_text):
    output = []
    index = 0
    while index < len(raw_text):
        char = raw_text[index]
        if char != "\\":
            output.append(char)
            index += 1
            continue

        index += 1
        if index >= len(raw_text):
            output.append("\\")
            break

        escaped = raw_text[index]
        if escaped in {"n", "l"}:
            output.append("\n")
        elif escaped == "p":
            output.append("\n\n")
        elif escaped == "r":
            output.append("\r")
        elif escaped == "t":
            output.append("\t")
        elif escaped == "\\":
            output.append("\\")
        elif escaped == '"':
            output.append('"')
        else:
            output.append("\\" + escaped)
        index += 1

    if output and output[-1] == "$":
        output.pop()
    return "".join(output)


def _remove_comment(line):
    in_char = False
    escaped = False
    for index, char in enumerate(line):
        if in_char:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == "'":
                in_char = False
            continue
        if char == "'":
            in_char = True
        elif char == "@":
            return line[:index]
    return line


def _split_assignment(line, path, line_number):
    in_char = False
    escaped = False
    for index, char in enumerate(line):
        if in_char:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == "'":
                in_char = False
            continue
        if char == "'":
            in_char = True
        elif char == "=":
            return line[:index], line[index + 1:]
    raise ValueError("{}:{}: expected equals sign".format(path, line_number))


def _parse_lhs(lhs, path, line_number):
    if lhs.startswith("'"):
        if not lhs.endswith("'") or len(lhs) < 3:
            raise ValueError("{}:{}: malformed character literal".format(path, line_number))

        body = lhs[1:-1]
        is_escape = body.startswith("\\")
        if is_escape:
            body = body[1:]
        if len(body) != 1:
            raise ValueError("{}:{}: expected one character in literal".format(path, line_number))

        if is_escape and body not in {"'", "\\"}:
            return "escape", body
        return "char", body

    if IDENTIFIER_RE.match(lhs):
        return "constant", lhs

    raise ValueError("{}:{}: unsupported charmap lhs {!r}".format(path, line_number, lhs))


def _parse_byte_sequence(rhs, path, line_number):
    hex_digits = "".join(rhs.split())
    if not hex_digits or len(hex_digits) % 2 != 0:
        raise ValueError("{}:{}: expected even-length byte sequence".format(path, line_number))
    if any(char not in "0123456789abcdefABCDEF" for char in hex_digits):
        raise ValueError("{}:{}: expected hex byte sequence".format(path, line_number))
    return [
        int(hex_digits[index:index + 2], 16)
        for index in range(0, len(hex_digits), 2)
    ]


class _TextEncoder:
    def __init__(self, raw_text, charmap):
        self.raw_text = raw_text
        self.charmap = charmap
        self.bytes = []
        self.glyphs = []
        self.control_codes = []
        self.placeholders = []
        self.warnings = []

    def encode(self):
        index = 0
        while index < len(self.raw_text):
            char = self.raw_text[index]
            if char == "{":
                index = self._encode_braced(index)
            elif char == "\\":
                index = self._encode_escape(index)
            else:
                self._append_char(char, index)
                index += 1

        return {
            "status": "partial" if self.warnings else "ok",
            "byte_count": len(self.bytes),
            "bytes": self.bytes,
            "hex": " ".join("{:02X}".format(byte) for byte in self.bytes),
            "terminator_present": bool(self.bytes) and self.bytes[-1] == 0xFF,
            "glyphs": self.glyphs,
            "control_codes": self.control_codes,
            "placeholders": self.placeholders,
            "warnings": self.warnings,
        }

    def _append_char(self, char, offset):
        sequence = self.charmap.chars.get(char)
        if sequence is None:
            self._warn("unknown character {!r} at offset {}".format(char, offset))
            return
        byte_offset = len(self.bytes)
        self.bytes.extend(sequence)
        if char == "$":
            self.control_codes.append({
                "kind": "terminator",
                "token": "$",
                "offset": offset,
                "bytes": sequence,
            })
            return
        self.glyphs.append({
            "text": char,
            "source_offset": offset,
            "byte_offset": byte_offset,
            "byte_count": len(sequence),
            "bytes": sequence,
            "hex": " ".join("{:02X}".format(byte) for byte in sequence),
        })

    def _encode_escape(self, offset):
        if offset + 1 >= len(self.raw_text):
            self._warn("trailing escape at offset {}".format(offset))
            return offset + 1

        escaped = self.raw_text[offset + 1]
        token = "\\" + escaped
        if escaped in {'"', "\\"}:
            sequence = self.charmap.chars.get(escaped)
            kind = "escaped_char"
        else:
            sequence = self.charmap.escapes.get(escaped)
            kind = "escape"

        if sequence is None:
            self._warn("unknown escape {!r} at offset {}".format(token, offset))
            return offset + 2

        byte_offset = len(self.bytes)
        self.bytes.extend(sequence)
        control = {
            "kind": kind,
            "token": token,
            "offset": offset,
            "bytes": sequence,
        }
        display = _escape_display_name(escaped)
        if display:
            control["display"] = display
        if kind == "escaped_char":
            self.glyphs.append({
                "text": escaped,
                "source_offset": offset,
                "byte_offset": byte_offset,
                "byte_count": len(sequence),
                "bytes": sequence,
                "hex": " ".join("{:02X}".format(byte) for byte in sequence),
                "source_escape": token,
            })
        self.control_codes.append(control)
        return offset + 2

    def _encode_braced(self, offset):
        end = self.raw_text.find("}", offset + 1)
        if end == -1:
            self._warn("unterminated brace at offset {}".format(offset))
            return len(self.raw_text)

        content = self.raw_text[offset + 1:end]
        tokens = content.split()
        control = {
            "kind": "braced",
            "token": self.raw_text[offset:end + 1],
            "offset": offset,
            "bytes": [],
            "items": [],
        }
        if not tokens:
            self._warn("empty brace at offset {}".format(offset))
            self.control_codes.append(control)
            return end + 1

        for token in tokens:
            item = self._encode_braced_token(token, offset)
            if item is None:
                continue
            control["items"].append(item)
            control["bytes"].extend(item["bytes"])
            self.bytes.extend(item["bytes"])
            if item["kind"] == "constant" and _is_placeholder_constant(item["name"], item["bytes"]):
                self.placeholders.append({
                    "token": item["name"],
                    "offset": offset,
                    "bytes": item["bytes"],
                })

        self.control_codes.append(control)
        return end + 1

    def _encode_braced_token(self, token, offset):
        if IDENTIFIER_RE.match(token):
            sequence = self.charmap.constants.get(token)
            if sequence is None:
                self._warn("unknown constant {!r} at offset {}".format(token, offset))
                return None
            return {
                "kind": "constant",
                "name": token,
                "bytes": sequence,
            }

        if DECIMAL_RE.match(token) or HEX_RE.match(token):
            integer = _parse_integer_token(token)
            if integer.get("warning"):
                self._warn("{} at offset {}".format(integer["warning"], offset))
                return None
            return {
                "kind": "integer",
                "token": token,
                "value": integer["value"],
                "size": integer["size"],
                "bytes": _integer_bytes(integer["value"], integer["size"]),
            }

        self._warn("unexpected brace token {!r} at offset {}".format(token, offset))
        return None

    def _warn(self, message):
        self.warnings.append(message)


def _parse_integer_token(token):
    if token.startswith("0x"):
        digits = token[2:]
        if len(digits) == 2:
            size = 1
        elif len(digits) == 4:
            size = 2
        elif len(digits) == 8:
            size = 4
        else:
            return {"warning": "hex integer {!r} is not 2, 4, or 8 digits".format(token)}
        return {
            "value": int(digits, 16),
            "size": size,
        }

    suffix = token[-1] if token[-1] in {"H", "W"} else ""
    digits = token[:-1] if suffix else token
    value = int(digits, 10)
    if value > 0xFFFFFFFF:
        return {"warning": "integer {!r} is too large".format(token)}
    if suffix == "H":
        if value >= 0x10000:
            return {"warning": "integer {!r} is too large for a halfword".format(token)}
        size = 2
    elif suffix == "W":
        size = 4
    elif value >= 0x10000:
        size = 4
    elif value >= 0x100:
        size = 2
    else:
        size = 1
    return {
        "value": value,
        "size": size,
    }


def _integer_bytes(value, size):
    return [
        (value >> (8 * index)) & 0xFF
        for index in range(size)
    ]


def _escape_display_name(char):
    if char in {"n", "l"}:
        return "newline"
    if char == "p":
        return "paragraph"
    if char == "r":
        return "carriage_return"
    if char == "t":
        return "tab"
    return ""


def _is_placeholder_constant(name, sequence):
    return name == "PLAYER" or name.startswith("STR_VAR_") or bool(sequence and sequence[0] == 0xFD)
