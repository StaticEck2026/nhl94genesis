#!/usr/bin/env python3
"""Export the stick hot-spot table (Hotlist, listing L626116) to JSON for the Godot port.

Offline only. The game never reads the ROM; it loads godot/data/hotlist.json.
Usage: python3 tools/extract/hotlist.py [lst/nhl94.bin] [godot/data/hotlist.json]

Format: 838 entries of two signed bytes (x, y) indexed by sprite frame number, at ROM
offset $A44C8 (verified in docs/specs/puck.md). Y is screen-down in the table; GetHot
negates it for rink coordinates unless the sprite is Y-flipped.
"""
import json
import sys

OFFSET = 0xA44C8
COUNT = 838


def s8(b: int) -> int:
    return b - 256 if b >= 128 else b


def main() -> None:
    rom_path = sys.argv[1] if len(sys.argv) > 1 else "lst/nhl94.bin"
    out_path = sys.argv[2] if len(sys.argv) > 2 else "godot/data/hotlist.json"
    with open(rom_path, "rb") as f:
        rom = f.read()
    raw = rom[OFFSET:OFFSET + COUNT * 2]
    pairs = [[s8(raw[2 * i]), s8(raw[2 * i + 1])] for i in range(COUNT)]
    with open(out_path, "w") as f:
        json.dump({"source": "Hotlist L626116, ROM $A44C8", "frames": pairs}, f, separators=(",", ":"))
    print(f"wrote {len(pairs)} hot spots to {out_path}")


if __name__ == "__main__":
    main()
