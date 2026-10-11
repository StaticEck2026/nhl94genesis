#!/usr/bin/env python3
"""Export NHL '94 graphics and DAC samples as loose files for the Godot port.

Offline only. The game never reads the ROM; it loads what this writes under
godot/assets/. Usage: python3 tools/extract/assets.py [lst/nhl94.bin] [godot/assets]

Layout and addresses: docs/specs/animation_assets.md sections 2, 3, 5.4 and 6.

Index textures: R = colour index * 17, G = palette line * 85, A = 255 where drawn
(sprites leave colour 0 transparent; plane tiles are opaque). The game colours them
with res://shaders/palette.gdshader from the CRAM words in palettes.json.

Writes:
  palettes.json                 rink lines 0-3 (normal, reverse), side view, 28 teams
  sprites/atlas_idx.png         every sprite frame 1..845, shelf-packed
  sprites/frames.json           per frame: atlas rect, origin, hot spot, pieces
  rink/rink_base_idx.png        48x85-cell normal rink, low-priority cells (384x680)
  rink/rink_front_idx.png       the priority cells (end boards and glass, doors)
  rink/rink_reverse_*_idx.png   the reverse-angle rink, same split
  rink/tiles_idx.png            unique (tile, palette line) pairs for the TileMapLayer
  rink/map.json                 per cell [atlas tile, flip/priority flags], raw words, geometry
  rink/logos_idx.png            28 centre-ice logos (48x32 each, 4 per row)
  rink/side_idx.png             the horizontal penalty-screen view (256x224)
  sprites/faceoff_idx.png       the face-off close-up frames 1-10 (centres, referee)
  sprites/faceoff_window_idx.png  the close-up window (FaceOffMap, 96x80)
  audio/dac/instr_XX.wav        the Z80 driver's PCM samples (8-bit unsigned)
"""
import json
import os
import struct
import sys
import zlib

ROM_CRC = 0x9438F5DD
ANIM = 0x5DE7A
HOTLIST = 0xA44C8
RINK = 0x5605A
RINK_REV = 0xB5180
SIDE = 0xBC05C
LOGOS = 0xFEA74
TEAMS = 0x30E
DAC_TABLE = 0x1B01C
SIZETAB = [1, 2, 3, 4, 2, 4, 6, 8, 3, 6, 9, 12, 4, 8, 12, 16]
VISIBLE_ROWS = 85


class Rom:
    def __init__(self, data: bytes):
        self.b = data

    def u8(self, a):
        return self.b[a]

    def s8(self, a):
        v = self.b[a]
        return v - 256 if v >= 128 else v

    def u16(self, a):
        return (self.b[a] << 8) | self.b[a + 1]

    def s16(self, a):
        v = self.u16(a)
        return v - 0x10000 if v >= 0x8000 else v

    def u32(self, a):
        return (self.u16(a) << 16) | self.u16(a + 2)

    def tile(self, a):
        """64 colour indexes, row-major; the high nibble is the left pixel."""
        out = []
        for y in range(8):
            for x in range(4):
                v = self.b[a + y * 4 + x]
                out.append(v >> 4)
                out.append(v & 15)
        return out


def png(path, w, h, rgba):
    raw = bytearray()
    stride = w * 4
    for y in range(h):
        raw.append(0)
        raw += rgba[y * stride:(y + 1) * stride]

    def chunk(t, d):
        c = struct.pack(">I", len(d)) + t + d
        return c + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)

    ihdr = struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)
    data = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(bytes(raw), 9)) + chunk(b"IEND", b"")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(data)


class Canvas:
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.px = bytearray(w * h * 4)

    def put(self, x, y, idx, line, opaque=False, only_empty=False):
        if x < 0 or y < 0 or x >= self.w or y >= self.h:
            return
        if idx == 0 and not opaque:
            return
        o = (y * self.w + x) * 4
        if only_empty and self.px[o + 3]:
            return
        self.px[o] = idx * 17
        self.px[o + 1] = line * 85
        self.px[o + 2] = 0
        self.px[o + 3] = 255

    def tile(self, rom, addr, x0, y0, line, hf=False, vf=False, opaque=False, only_empty=False):
        t = rom.tile(addr)
        for y in range(8):
            for x in range(8):
                self.put(x0 + (7 - x if hf else x), y0 + (7 - y if vf else y), t[y * 8 + x], line, opaque, only_empty)

    def blit(self, other, x0, y0):
        for y in range(other.h):
            s = y * other.w * 4
            d = ((y0 + y) * self.w + x0) * 4
            self.px[d:d + other.w * 4] = other.px[s:s + other.w * 4]

    def save(self, path):
        png(path, self.w, self.h, self.px)


def cram_list(rom, a, n=16):
    return [rom.u16(a + 2 * i) for i in range(n)]


def pstr(rom, a):
    n = rom.u16(a)
    return rom.b[a + 2:a + n].rstrip(b"\x00").decode("latin-1"), a + n


# --- compressed tiles -----------------------------------------------------------------------

def decompress(rom, a):
    """sub_1177A (L44975): the tile count word has bit 15 set; the stream is byte codes
    over a 256-byte ring, high nibble = command. Returns the tile bytes (count * 32)."""
    n = rom.u16(a)
    assert n & 0x8000, "not compressed"
    n &= 0x7FFF
    p = a + 2
    ring = bytearray(256)
    out = bytearray()
    w = 0

    def put(b):
        nonlocal w
        ring[w] = b
        out.append(b)
        w = (w + 1) & 0xFF

    def copy(count, dist, reverse):
        src = (w - dist) & 0xFF
        for _ in range(count):
            put(ring[src])
            src = (src - 1) & 0xFF if reverse else (src + 1) & 0xFF

    while True:
        c = rom.b[p]
        p += 1
        h = c >> 4
        if h <= 1:  # literal run
            for _ in range((c & 0x1F) + 1):
                put(rom.b[p])
                p += 1
        elif h == 2:  # zeros
            for _ in range((c & 0xF) + 1):
                put(0)
        elif h == 3:  # repeated byte
            v = rom.b[p]
            p += 1
            for _ in range((c & 0xF) + 3):
                put(v)
        elif h <= 7:  # short back reference
            copy((c & 7) + 2, ((c >> 3) & 7) + 1, False)
        elif h == 8:
            dist = rom.b[p]
            p += 1
            copy((c & 0xF) + 3, dist, False)
        elif h in (9, 0xF):
            nb = rom.b[p]
            p += 1
            copy((((c << 1) | (nb >> 7)) & 0x1F) + 3, (nb & 0x7F) + 1, h == 0xF)
        elif h == 0xA:
            nb = rom.b[p]
            p += 1
            copy(((((c << 8) | nb) >> 6) & 0x3F) + 3, (nb & 0x3F) + 1, False)
        elif h == 0xB:
            nb = rom.b[p]
            p += 1
            copy(((((c << 8) | nb) >> 5) & 0x7F) + 3, (nb & 0x1F) + 1, False)
        elif h <= 0xD:  # short back reference, copied backwards
            copy((c & 3) + 2, ((c >> 2) & 7) + 1, True)
        else:  # $Ex: backwards copy, or the end with distance 0
            dist = rom.b[p]
            p += 1
            if dist == 0:
                break
            copy((c & 0xF) + 3, dist, True)
    assert len(out) == n * 32, (hex(a), len(out), n * 32)
    return bytes(out)


class BytesRom(Rom):
    """A tile source over decompressed bytes, so the Canvas helpers can draw from it."""


# --- palettes ---------------------------------------------------------------------------

def jim(rom, base):
    pal = base + rom.u32(base)
    mp = base + rom.u32(base + 4)
    n = rom.u16(base + 8)
    assert n & 0x8000 == 0, "compressed tile blob"
    return pal, mp, n, base + 10


def palettes(rom):
    out = {}
    for name, base in (("rink", RINK), ("rink_reverse", RINK_REV), ("side", SIDE)):
        pal, _, _, _ = jim(rom, base)
        out[name] = [cram_list(rom, pal + 32 * k) for k in range(4)]
    teams = []
    for t in range(28):
        p = rom.u32(TEAMS + 4 * t)
        pd = p + rom.u16(p + 2)
        a = p + rom.u16(p + 4)
        city, a = pstr(rom, a)
        abbr, a = pstr(rom, a)
        teams.append({"index": t, "abbr": abbr, "city": city,
                      "home": cram_list(rom, pd), "away": cram_list(rom, pd + 32)})
    out["teams"] = teams
    out["cram_layout"] = ["rink line 0", "rink line 1", "home team home", "away team away"]
    return out


# --- sprites ------------------------------------------------------------------------------

def sprite_frames(rom):
    fs = ANIM + rom.u32(ANIM + 4)
    tiles = ANIM + 10
    ntiles = rom.u16(ANIM + 8)
    assert ntiles == 0x2041
    assert fs + rom.u16(fs + 2 * 846) == HOTLIST + 2
    frames = []
    for f in range(1, 846):
        a0 = fs + rom.u16(fs + 2 * f)
        a1 = fs + rom.u16(fs + 2 * f + 2)
        pieces = []
        for a in range(a0, a1, 8):
            x, y = rom.s16(a), rom.s16(a + 2)
            tile = rom.u16(a + 4)
            w6 = rom.u16(a + 6)
            size = w6 & 0xFF
            pw, ph = ((size >> 2) & 3) + 1, (size & 3) + 1
            assert tile + SIZETAB[size] <= ntiles
            pieces.append({"x": x, "y": y, "tile": tile, "w": pw, "h": ph,
                           "hf": bool(w6 & 0x800), "vf": bool(w6 & 0x1000), "pal": (w6 >> 13) & 3,
                           "prio": bool(w6 & 0x8000)})
        x0 = min(p["x"] for p in pieces)
        y0 = min(p["y"] for p in pieces)
        x1 = max(p["x"] + 8 * p["w"] for p in pieces)
        y1 = max(p["y"] + 8 * p["h"] for p in pieces)
        c = Canvas(x1 - x0, y1 - y0)
        # Piece 0 is in front on the VDP, so fill only pixels still empty, in table order.
        for p in pieces:
            for col in range(p["w"]):
                for row in range(p["h"]):
                    t = p["tile"] + col * p["h"] + row
                    dc = p["w"] - 1 - col if p["hf"] else col
                    dr = p["h"] - 1 - row if p["vf"] else row
                    c.tile(rom, tiles + 32 * t, p["x"] - x0 + 8 * dc, p["y"] - y0 + 8 * dr, p["pal"],
                           p["hf"], p["vf"], only_empty=True)
        hot = [rom.s8(HOTLIST + 2 * f), rom.s8(HOTLIST + 2 * f + 1)] if f <= 837 else None
        frames.append({"frame": f, "canvas": c, "origin": [-x0, -y0], "hot": hot,
                       "lines": sorted({p["pal"] for p in pieces}), "pieces": pieces})
    return frames


FACEOFF = 0xA78AE        # close-up animation: header, compressed tiles at +8, frames
FACEOFF_MAP = 0x55BF6    # FaceOffMap: header, compressed tiles at +8, 12x10 map


def piece_frames(rom, tiles, ft, first, last):
    """Frames in the frameSprData piece format, drawn from `tiles` (a Rom over bytes)."""
    frames = []
    for f in range(first, last + 1):
        a0 = ft + rom.u16(ft + 2 * f)
        a1 = ft + rom.u16(ft + 2 * f + 2)
        pieces = []
        for a in range(a0, a1, 8):
            w6 = rom.u16(a + 6)
            size = w6 & 0xFF
            pieces.append({"x": rom.s16(a), "y": rom.s16(a + 2), "tile": rom.u16(a + 4),
                           "w": ((size >> 2) & 3) + 1, "h": (size & 3) + 1,
                           "hf": bool(w6 & 0x800), "vf": bool(w6 & 0x1000), "pal": (w6 >> 13) & 3})
        x0 = min(p["x"] for p in pieces)
        y0 = min(p["y"] for p in pieces)
        x1 = max(p["x"] + 8 * p["w"] for p in pieces)
        y1 = max(p["y"] + 8 * p["h"] for p in pieces)
        c = Canvas(x1 - x0, y1 - y0)
        for p in pieces:
            for col in range(p["w"]):
                for row in range(p["h"]):
                    t = p["tile"] + col * p["h"] + row
                    dc = p["w"] - 1 - col if p["hf"] else col
                    dr = p["h"] - 1 - row if p["vf"] else row
                    c.tile(tiles, 32 * t, p["x"] - x0 + 8 * dc, p["y"] - y0 + 8 * dr, p["pal"],
                           p["hf"], p["vf"], only_empty=True)
        frames.append({"frame": f, "canvas": c, "origin": [-x0, -y0], "hot": None,
                       "lines": sorted({p["pal"] for p in pieces}), "pieces": pieces})
    return frames


def faceoff_closeup(rom):
    tiles = BytesRom(decompress(rom, FACEOFF + 8))
    ft = FACEOFF + rom.u32(FACEOFF + 4)
    frames = piece_frames(rom, tiles, ft, 1, 10)
    mt = BytesRom(decompress(rom, FACEOFF_MAP + 8))
    m = FACEOFF_MAP + rom.u32(FACEOFF_MAP + 4)
    w, h = rom.u16(m), rom.u16(m + 2)
    win = Canvas(w * 8, h * 8)
    for r in range(h):
        for col in range(w):
            v = rom.u16(m + 4 + 2 * (r * w + col))
            win.tile(mt, 32 * (v & 0x7FF), col * 8, r * 8, (v >> 13) & 3, bool(v & 0x800), bool(v & 0x1000))
    return frames, win


def pack(frames, width=1024):
    """Shelf packing, tallest first, 1 px gutters."""
    order = sorted(frames, key=lambda f: (-f["canvas"].h, -f["canvas"].w))
    x = y = shelf = 0
    for f in order:
        c = f["canvas"]
        if x + c.w > width:
            x = 0
            y += shelf + 1
            shelf = 0
        f["atlas"] = [x, y]
        x += c.w + 1
        shelf = max(shelf, c.h)
    h = y + shelf
    h2 = 1
    while h2 < h:
        h2 <<= 1
    atlas = Canvas(width, h2)
    for f in frames:
        atlas.blit(f["canvas"], f["atlas"][0], f["atlas"][1])
    return atlas


# --- rink ------------------------------------------------------------------------------------

def rink_layers(rom, base, rows=VISIBLE_ROWS):
    _, mp, n, tiles = jim(rom, base)
    w, h = rom.u16(mp), rom.u16(mp + 2)
    assert (w, h) == (48, 113)
    cells = [rom.u16(mp + 4 + 2 * i) for i in range(w * h)]
    back = Canvas(w * 8, rows * 8)
    front = Canvas(w * 8, rows * 8)
    for r in range(rows):
        for col in range(w):
            v = cells[r * w + col]
            t = v & 0x7FF
            layer = front if v & 0x8000 else back
            layer.tile(rom, tiles + 32 * t, col * 8, r * 8, (v >> 13) & 3, bool(v & 0x800), bool(v & 0x1000),
                       opaque=True)
    return back, front, {"w": w, "h": h, "tiles": n, "cells": cells, "end": mp + 4 + 2 * w * h}


def rink_tileset(rom, base, rows=VISIBLE_ROWS):
    """Unique (tile, palette line) pairs as an 8x8 atlas, 16 tiles wide, and per cell:
    [atlas index, flags] with flags bit 0 h-flip, bit 1 v-flip, bit 2 priority (front)."""
    _, mp, n, tiles = jim(rom, base)
    w = rom.u16(mp)
    ids = {}
    cells = []
    for r in range(rows):
        for col in range(w):
            v = rom.u16(mp + 4 + 2 * (r * w + col))
            key = (v & 0x7FF, (v >> 13) & 3)
            if key not in ids:
                ids[key] = len(ids)
            cells.append([ids[key], (1 if v & 0x800 else 0) | (2 if v & 0x1000 else 0) | (4 if v & 0x8000 else 0)])
    cols = 16
    sheet = Canvas(cols * 8, ((len(ids) + cols - 1) // cols) * 8)
    for (t, line), i in ids.items():
        sheet.tile(rom, tiles + 32 * t, (i % cols) * 8, (i // cols) * 8, line, opaque=True)
    return sheet, cells, [[t, line] for (t, line) in sorted(ids, key=lambda k: ids[k])]


def logos(rom):
    sheet = Canvas(48 * 4, 32 * 7)
    for t in range(28):
        a = rom.u32(LOGOS + 4 * t) + 8
        assert rom.u16(a) == 24
        for k in range(24):
            col, row = k % 6, k // 6
            sheet.tile(rom, a + 2 + 32 * k, (t % 4) * 48 + col * 8, (t // 4) * 32 + row * 8, 2, opaque=True)
    return sheet


def side_view(rom):
    pal, mp, n, tiles = jim(rom, SIDE)
    w, h = rom.u16(mp), rom.u16(mp + 2)
    c = Canvas(w * 8, h * 8)
    for r in range(h):
        for col in range(w):
            v = rom.u16(mp + 4 + 2 * (r * w + col))
            c.tile(rom, tiles + 32 * (v & 0x7FF), col * 8, r * 8, (v >> 13) & 3, bool(v & 0x800), bool(v & 0x1000),
                   opaque=True)
    return c


# --- DAC samples ---------------------------------------------------------------------------

def dac(rom, out_dir):
    os.makedirs(out_dir, exist_ok=True)
    meta = []
    for k in range(15):
        addr = rom.u32(DAC_TABLE + 8 * k)
        instr = 0x60 + k
        if addr == 0:
            meta.append({"instr": instr, "address": 0, "bytes": 0})
            continue
        end = addr
        while rom.b[end] != 0:
            end += 1
        data = rom.b[addr:end]
        rate = 10000
        with open(os.path.join(out_dir, "instr_%02X.wav" % instr), "wb") as f:
            f.write(b"RIFF" + struct.pack("<I", 36 + len(data)) + b"WAVE")
            f.write(b"fmt " + struct.pack("<IHHIIHH", 16, 1, 1, rate, rate, 1, 8))
            f.write(b"data" + struct.pack("<I", len(data)) + data)
        meta.append({"instr": instr, "address": addr, "bytes": len(data)})
    with open(os.path.join(out_dir, "samples.json"), "w") as f:
        json.dump({"nominal_rate": 10000,
                   "rate_formula": "119.5 * step Hz, step = freq[note % 12] >> (8 - octave)",
                   "freq": [0x146, 0x159, 0x16E, 0x184, 0x19B, 0x1B3, 0x1CD, 0x1E8, 0x205, 0x224, 0x245, 0x268],
                   "samples": meta}, f, indent=1)


def main():
    rom_path = sys.argv[1] if len(sys.argv) > 1 else "lst/nhl94.bin"
    out = sys.argv[2] if len(sys.argv) > 2 else "godot/assets"
    with open(rom_path, "rb") as f:
        data = f.read()
    assert zlib.crc32(data) & 0xFFFFFFFF == ROM_CRC, "unexpected ROM"
    rom = Rom(data)
    os.makedirs(out, exist_ok=True)
    with open(os.path.join(out, "palettes.json"), "w") as f:
        json.dump(palettes(rom), f, indent=1)

    frames = sprite_frames(rom)
    atlas = pack(frames)
    atlas.save(os.path.join(out, "sprites/atlas_idx.png"))
    meta = {}
    for fr in frames:
        c = fr["canvas"]
        meta[str(fr["frame"])] = {"rect": [fr["atlas"][0], fr["atlas"][1], c.w, c.h], "origin": fr["origin"],
                                  "hot": fr["hot"], "lines": fr["lines"]}
    with open(os.path.join(out, "sprites/frames.json"), "w") as f:
        json.dump({"source": "frameSprData $9E724, Spritetiles $5DE84, Hotlist $A44C8",
                   "atlas": [atlas.w, atlas.h], "frames": meta}, f, separators=(",", ":"))

    back, front, m = rink_layers(rom, RINK)
    assert m["end"] == 0x5C408
    back.save(os.path.join(out, "rink/rink_base_idx.png"))
    front.save(os.path.join(out, "rink/rink_front_idx.png"))
    rb, rf, mr = rink_layers(rom, RINK_REV)
    assert mr["end"] == 0xBB4EE
    rb.save(os.path.join(out, "rink/rink_reverse_base_idx.png"))
    rf.save(os.path.join(out, "rink/rink_reverse_front_idx.png"))
    sheet, tcells, keys = rink_tileset(rom, RINK)
    sheet.save(os.path.join(out, "rink/tiles_idx.png"))
    with open(os.path.join(out, "rink/map.json"), "w") as f:
        json.dump({"w": 48, "h": 113, "rows": VISIBLE_ROWS, "origin_px": [192, 368],
                   "logo_px": [168, 352], "tiles_per_row": 16, "atlas_keys": keys,
                   "tilemap": tcells, "cells": m["cells"]}, f, separators=(",", ":"))
    logos(rom).save(os.path.join(out, "rink/logos_idx.png"))
    fo_frames, window = faceoff_closeup(rom)
    fo_atlas = pack(fo_frames, 256)
    fo_atlas.save(os.path.join(out, "sprites/faceoff_idx.png"))
    window.save(os.path.join(out, "sprites/faceoff_window_idx.png"))
    with open(os.path.join(out, "sprites/faceoff.json"), "w") as f:
        json.dump({"source": "face-off close-up $A78AE (compressed tiles), FaceOffMap $55BF6",
                   "atlas": [fo_atlas.w, fo_atlas.h],
                   "frames": {str(fr["frame"]): {"rect": [fr["atlas"][0], fr["atlas"][1], fr["canvas"].w,
                                                          fr["canvas"].h], "origin": fr["origin"],
                                                 "hot": None, "lines": fr["lines"]} for fr in fo_frames}},
                  f, separators=(",", ":"))
    side_view(rom).save(os.path.join(out, "rink/side_idx.png"))
    dac(rom, os.path.join(out, "audio/dac"))
    print("wrote %d sprite frames (atlas %dx%d), rink layers, logos, side view, DAC samples to %s"
          % (len(frames), atlas.w, atlas.h, out))


if __name__ == "__main__":
    main()
