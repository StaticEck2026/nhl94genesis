#!/usr/bin/env python3
"""Export the animation table (SPAList, listing L22741, ROM $5B1C) to JSON.

Offline only; the game loads godot/data/spalist.json.
Usage: python3 tools/extract/spalist.py [lst/nhl94.bin] [godot/data/spalist.json]

Entry at $5B1C + id: 8 words (per facing direction, byte offset of the frame list from
the entry start), an attribute word (bit 0 = loop), then frame lists of (frame, time)
word pairs. A negative time marks the last pair; its absolute value is the duration.
Spec: docs/specs/animation_assets.md section 1.
"""
import json
import struct
import sys

BASE = 0x5B1C
SPA_IDS = [0x2, 0x114, 0x146, 0x178, 0x1AA, 0x1EC, 0x21E, 0x250, 0x2A2, 0x2F4, 0x366, 0x3D8,
           0x46A, 0x50C, 0x53E, 0x5D0, 0x662, 0x694, 0x6C6, 0x718, 0x78A, 0x7FC, 0x92E, 0xA60,
           0xA92, 0xB24, 0xB96, 0xBC8, 0xBFA, 0xC2C, 0xC5E, 0xC90, 0xCC2, 0xCF4, 0xD26, 0xDD8,
           0xE8A, 0xEFC, 0xF6E, 0xFAC, 0xFEA, 0x1014, 0x102E, 0x1078, 0x109E, 0x10D0, 0x1122,
           0x1154, 0x11E6, 0x1298, 0x136A, 0x145C, 0x148E, 0x14C0, 0x14F2, 0x1544, 0x1596,
           0x1684, 0x1776, 0x17E8, 0x185A, 0x18CC, 0x193E, 0x1A00, 0x1AC2, 0x1AF4]
# A list that never ends (a direction offset pointing into the next header, $F6E/$FAC
# dir 7) is cut here; retail would keep reading words as pairs.
MAX_PAIRS = 32


def w(rom: bytes, a: int) -> int:
    return struct.unpack(">h", rom[a:a + 2])[0]


def parse(rom: bytes, base: int, ids: list) -> dict:
    """The entries `ids` of an SPAList at `base` (the fight patch moves it)."""
    out = {}
    for spa in ids:
        e = base + spa
        dirs = []
        for d in range(8):
            a = e + w(rom, e + 2 * d)
            pairs = []
            for _ in range(MAX_PAIRS):
                frame, time = w(rom, a), w(rom, a + 2)
                pairs.append([frame, time])
                a += 4
                if time < 0:
                    break
            dirs.append(pairs)
        out["%d" % spa] = {"loop": bool(w(rom, e + 0x10) & 1), "dirs": dirs}
    return out


def main() -> None:
    rom_path = sys.argv[1] if len(sys.argv) > 1 else "lst/nhl94.bin"
    out_path = sys.argv[2] if len(sys.argv) > 2 else "godot/data/spalist.json"
    rom = open(rom_path, "rb").read()
    out = parse(rom, BASE, SPA_IDS)
    json.dump({"source": "SPAList L22741, ROM $5B1C", "anims": out}, open(out_path, "w"), separators=(",", ":"))
    print("wrote %d animations to %s" % (len(out), out_path))


if __name__ == "__main__":
    main()
