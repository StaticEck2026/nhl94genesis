#!/usr/bin/env python3
"""Export the in-game overlay art and text of NHL '94 (plane A / plane B HUD) for the Godot port.

Offline only. The game never reads the ROM; it loads what this writes under godot/assets/ui/.
Usage: python3 tools/extract/ui_overlay.py [lst/nhl94.bin] [godot/assets/ui]
Spec: docs/specs/ui_ingame.md.

In play the window plane is off; every overlay is a plane-A cell (64x32 map at VRAM $E000,
never scrolled, so cell (c, r) is screen (8c, 8r) on the 256x224 H32 screen). On the
sideways penalty screen the clock, period and scores go to plane B (the side view).

Index textures as in assets.py: R = colour index * 17, G = palette line * 85, A = 255 where
drawn. Colour 0 is transparent (A = 0), as on a VDP plane. The game colours them with the
CRAM words in ui.json ("cram": in-game lines 0 and 1, the rink palette).

Writes (all 8x8 tile sheets are 16 tiles to a row unless noted):
  font_idx.png        the in-game print font: $AAC52 tiles through setupice's remap table
                      43 43 45 67 89 AB CD EF (colour 0 -> 4, 1 -> 3, 2 -> 4), so every
                      glyph cell is opaque (text $CCC on $000 in line 0); 94 tiles
  bigfont_idx.png     printbig's font: $A9A10 tiles through the remap 71 23 45 67 89 AB CD
                      EF (colour 0 -> 7), palette line 1 (from its map); 132 tiles
  framer_idx.png      Framer's nine border tiles ($55B7E, compressed), 3 to a row in
                      framermap order (TL T TR / L C R / BL B BR), palette line 1
  ea_logo_idx.png     the 7x2 bitmap sub_12D70 puts in the score box when there is no power
                      play ($B3530, compressed, remap 0 -> 7), palette line 1, 56x16
  team_plates_idx.png the 28 11x2 team-name plates of the penalty screen ($ABA14,
                      sub_16D18), 88x16 each, stacked by team index (88x448), line 1
  energy_idx.png      the line-menu energy bar map ($AB920, sub_12E66): 16 rows of 2 cells,
                      row k = bar state k (row 15 - fill), 16x128
  ui.json             cram, glyph maps (font and printbig), framer order, sheet geometry
  messages.json       every in-game text the overlays print, with ids, ROM addresses and the
                      decoded print commands: PenaltyList, goal headers, period labels, line
                      names, playoff ticker headings, the inline printz strings
"""
import json
import os
import sys
import zlib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from assets import ROM_CRC, BytesRom, Canvas, Rom, decompress  # noqa: E402

FONT = 0xAAC52          # .map.jim, raw tiles, map 32x4 (char -> tile)
BIGFONT = 0xA9A10       # .map.jim, raw tiles, map 77x2
BIG_CHARTAB = 0x1916A   # printbig (sub_11E8E): (c - $20) -> signed column; negative = 1 cell wide
FRAMER = 0x55B7E        # framermap: .map.jim, compressed tiles, map 3x3
EA_LOGO = 0xB3530       # sub_12D70 / sub_16CAC
PLATES = 0xABA14        # sub_16D18: 11x2 plates, 28 teams, map 11x56
ENERGY = 0xAB920        # sub_12E66
PENALTY_LIST = 0x18E0C
RINK = 0x5605A          # CRAM lines 0-1 in play (sub_16C96)
REMAP_FONT = bytes.fromhex("4343456789ABCDEF")   # inline after jsr sub_1172C at $16AD8
REMAP_BIG = bytes.fromhex("7123456789ABCDEF")    # inline after jsr sub_1172C at $16AEE / $16CB6


def blob(rom, base):
    """Tile bytes of a .map.jim (+8 count word; bit 15 = compressed)."""
    n = rom.u16(base + 8)
    if n & 0x8000:
        return decompress(rom, base + 8)
    return rom.b[base + 10:base + 10 + 32 * n]


def remap(raw, table):
    """remap (L44006): colour n -> high nibble of table[n/2] when n is even, else the low."""
    def m(n):
        t = table[n >> 1]
        return t >> 4 if n % 2 == 0 else t & 15
    return bytes((m(v >> 4) << 4) | m(v & 15) for v in raw)


def jim_map(rom, base):
    mp = base + rom.u32(base + 4)
    w, h = rom.u16(mp), rom.u16(mp + 2)
    return w, h, [rom.u16(mp + 4 + 2 * i) for i in range(w * h)]


def sheet(tiles, line, per_row=16):
    src = BytesRom(tiles)
    n = len(tiles) // 32
    c = Canvas(per_row * 8, ((n + per_row - 1) // per_row) * 8)
    for i in range(n):
        c.tile(src, 32 * i, (i % per_row) * 8, (i // per_row) * 8, line)
    return c


def draw_map(c, tiles, cells, w, x0, y0, rows, col0=0, row0=0, cols=None):
    src = BytesRom(tiles)
    cols = cols or w
    for r in range(rows):
        for k in range(cols):
            v = cells[(row0 + r) * w + col0 + k]
            c.tile(src, 32 * (v & 0x7FF), x0 + 8 * k, y0 + 8 * r, (v >> 13) & 3, bool(v & 0x800), bool(v & 0x1000))


def cell(v):
    """A name-table word as [tile, flags, line]; flags bit 0 h-flip, bit 1 v-flip, bit 2 priority."""
    return [v & 0x7FF, (1 if v & 0x800 else 0) | (2 if v & 0x1000 else 0) | (4 if v & 0x8000 else 0), (v >> 13) & 3]


# --- print strings -----------------------------------------------------------------------

def s8(v):
    return v - 256 if v >= 128 else v


def decode_print(rom, a, flavour="print"):
    """A print/printbig string (word length L counting itself, then L-2 bytes) as ops.
    print / printbig: byte 0 skipped; negative byte b: v = -b, printa = (v << 9) & $F800,
    printm = (v & 3) * 4 - 4 (1 = plane A, 2 = plane B, 3 = window), then x and y bytes;
    '@' = the blank tile $7FF; '^' = skip a column. print2 (printz2) has another command set."""
    n = rom.u16(a)
    b = rom.b[a + 2:a + n]
    ops, text, i = [], "", 0
    while i < len(b):
        c = b[i]
        if c == 0:
            i += 1
            continue
        if c >= 0x80 and flavour != "print2":
            if text:
                ops.append({"text": text})
                text = ""
            v = (256 - c) & 0xFF
            plane = ["?", "A", "B", "W"][v & 3]
            x = s8(b[i + 1]) if i + 1 < len(b) else 0
            y = s8(b[i + 2]) if i + 2 < len(b) else 0
            ops.append({"at": [x, y], "plane": plane, "attr": (v << 9) & 0xF800})
            i += 3
            continue
        if c >= 0x80:
            if text:
                ops.append({"text": text})
                text = ""
            v = (256 - c) & 0xFF
            arg = b[i + 1] if i + 1 < len(b) else 0
            names = {1: "map", 2: "attr", 3: "x", 4: "y", 5: "dx", 6: "dy", 7: "font"}
            if v in names:
                val = s8(arg) if v in (5, 6) else arg
                if v == 1:
                    val = ["?", "A", "B", "W"][arg & 3]
                if v == 2:
                    val = ((arg & 7) << 13) & 0xFFFF
                ops.append({names[v]: val})
                i += 2
            else:
                ops.append({"cmd": c})
                i += 1
            continue
        text += chr(c)
        i += 1
    if text:
        ops.append({"text": text})
    return n, ops


def plain(rom, a):
    n = rom.u16(a)
    return n, rom.b[a + 2:a + n].replace(b"\x00", b"").decode("latin-1")


def string_list(rom, a, count):
    out = []
    for i in range(count):
        n, t = plain(rom, a)
        out.append({"id": i, "address": a, "text": t})
        a += n
    return out


# Inline printz / printbig strings the in-game overlays use: (address, routine, listing line,
# kind, purpose). The address is the string right after the jsr/bsr (word length first).
INLINE = [
    (0x12C26, "PrintScores1", 47145, "print", "score box frame origin (Framer 9x5)"),
    (0x12C3E, "PrintScores1", 47159, "print", "period label / clock row"),
    (0x12C78, "PrintScores1", 47179, "print", "team box frame origin (Framer 8x5)"),
    (0x12C8A, "PrintScores1", 47185, "print", "home abbreviation and goals"),
    (0x12C9C, "PrintScores1", 47190, "print", "away abbreviation and goals"),
    (0x12CB4, "PrintScores1", 47199, "print", "horizontal: period label (centred)"),
    (0x12CE6, "PrintScores1", 47215, "print", "horizontal: home plate and goals"),
    (0x12CFA, "PrintScores1", 47221, "print", "horizontal: away plate and goals"),
    (0x12D7E, "sub_12D70", 47274, "print", "EA logo origin (no power play)"),
    (0x12DB8, "sub_12DA6", 47295, "print", "horizontal: home penalty box list"),
    (0x12DCA, "sub_12DA6", 47301, "print", "horizontal: away penalty box list"),
    (0x12AEC, "updatepwrplay", 47024, "print", "power-play banner: Pwr Play glyphs, time row"),
    (0x12B1A, "updatepwrplay", 47054, "print", "power-play banner: team abbreviation (appendz)"),
    (0x1631A, "showclock", 52296, "print", "horizontal clock origin"),
    (0x1637C, "showclock", 52329, "print", "horizontal clock: print state reset"),
    (0x12792, "prefmes", 46676, "print", "erase the referee message (eraser 13x3)"),
    (0x127AC, "prefmes", 46685, "print", "referee message box origin (vertical)"),
    (0x12804, "prefmes", 46718, "print", "referee message (horizontal, centred)"),
    (0x1282C, "sub_12828", 46733, "print", "horizontal: blank the message row"),
    (0x12622, "UpdatePA", 46539, "print", "horizontal: the penalized player's name (centred)"),
    (0x188CE, "loc_1889A", 56002, "print", "goal box frame origin (Framer 19 x 5/7/8)"),
    (0x189BE, "loc_1889A", 56071, "print", "goal box: Assist by:"),
    (0x189F0, "loc_1889A", 56086, "print", "goal box: second assist row"),
    (0xFEAEE, "sub_FEAE4", 974731, "print", "goal box: count opener"),
    (0xFEB04, "sub_FEAFA", 974740, "print", "goal box: count opener"),
    (0xFEB40, "sub_FEAFA", 974757, "print", "goal box: count closer"),
    (0x18A5A, "box", 56165, "print", "erase the goal / injury box area (eraser 19x8)"),
    (0x18724, "loc_1871C", 55853, "print", "injury box frame origin (Framer 18x5)"),
    (0x18740, "loc_1871C", 55861, "print", "injury text, out for period"),
    (0x1876C, "loc_1871C", 55877, "print", "injury text, out for game"),
    (0x187A4, "loc_1871C", 55896, "print", "injury text: fight overprint"),
    (0x187E0, "sub_187B8", 55918, "print", "penalty-shot intro frame origin (Framer 27x8)"),
    (0x1882A, "sub_187B8", 55943, "print", "penalty-shot intro: penalty row"),
    (0x18852, "sub_187B8", 55953, "print", "penalty-shot intro: by"),
    (0x1203A, "chkprogress", 46026, "print", "erase the intro box (eraser 27 x 8/12)"),
    (0xFC334, "loc_FC320", 968693, "print", "shootout intro frame origin (Framer 27x12)"),
    (0xFC388, "loc_FC320", 968712, "print", "shootout intro: vs."),
    (0xFC3CC, "loc_FC320", 968729, "print", "shootout intro: home row"),
    (0xFC406, "loc_FC320", 968741, "print", "shootout intro: away row"),
    (0xFC440, "loc_FC320", 968754, "print", "shootout intro: Round"),
    (0xFC5B8, "sub_FC5AE", 968892, "print", "shootout winner frame origin (Framer 30x6)"),
    (0x1853E, "sub_1850A", 55679, "print", "stars box frame origin (Framer 28x9)"),
    (0x18550, "sub_1850A", 55685, "print", "Stars of the Game"),
    (0x0B9E2, "setlccords", 36644, "print", "line menu origin"),
    (0x134E8, "sub_134E4", 48119, "print", "playoff ticker origin (window when paused)"),
    (0x134FC, "sub_134E4", 48129, "print", "playoff ticker origin (plane A)"),
    (0x133DA, "NewTicker3pt2", 47954, "print", "playoff ticker: blank heading row"),
    (0x0FB58, "puckfaceoff2", 42215, "print", "face-off window origin"),
    (0x0FBC2, "puckfaceoff2", 42251, "print2", "face-off line box (Framer 12x3)"),
    (0x0FBE8, "puckfaceoff2", 42261, "print2", "face-off line names"),
    (0x0FDE8, "loc_FDDE", 42429, "print", "erase the face-off window (eraser 12x13)"),
    (0x18A14, "loc_1889A", 56022, "printbig", "goal header"),
    (0x18A22, "loc_1889A", 56039, "printbig", "goal header, hat trick"),
    (0x18A34, "loc_1889A", 56026, "printbig", "power-play goal header"),
    (0x18A44, "loc_1889A", 56039, "printbig", "power-play goal header, hat trick"),
    (0x18884, "sub_187B8", 55924, "printbig", "penalty-shot intro header"),
    (0xFC466, "loc_FC320", 968698, "printbig", "shootout intro header"),
    (0xFC5D2, "sub_FC5AE", 968904, "printbig", "shootout winner header"),
]


def penalty_list(rom):
    first = PENALTY_LIST + rom.u16(PENALTY_LIST + 2)
    out = []
    for i in range((first - PENALTY_LIST) // 2):
        off = rom.u16(PENALTY_LIST + 2 * i)
        if off == 0:
            continue
        e = PENALTY_LIST + off
        n, text = plain(rom, e + 2)
        a = e + 2 + n
        script = []
        while True:
            v = rom.u16(a)
            a += 2
            script.append(v)
            if v & 0x8000:
                break
        out.append({"id": 2 * i, "address": e, "delay": rom.u8(e), "minutes": rom.s8(e + 1),
                    "text": text, "text_bytes": n, "ref_script": script})
    return out


def messages(rom):
    inline = []
    for a, routine, line, kind, what in INLINE:
        n, ops = decode_print(rom, a, "print2" if kind == "print2" else "print")
        inline.append({"address": a, "routine": routine, "line": line, "kind": kind, "purpose": what,
                       "bytes": n, "ops": ops})
    digits = []
    for d in range(10):
        n, t = plain(rom, 0x16396 + 4 * d)
        digits.append(t)
    return {
        "source": "lst/nhl94.bin; see docs/specs/ui_ingame.md",
        "penalty_list": penalty_list(rom),
        "period_labels": string_list(rom, 0x191E4, 5),
        "period_labels_alt": string_list(rom, 0x191F8, 5),
        "line_names": string_list(rom, 0x191A6, 7),
        "ticker_headings": string_list(rom, 0x13488, 4),
        "clock_digits": {"address": 0x16396, "strings": digits},
        "special_chars": {"0x12": "ST", "0x13": "ND", "0x14": "RD", "0x16-0x19": "Pwr Play (4 cells)"},
        "inline": inline,
    }


# --- tile art ------------------------------------------------------------------------------

def bigfont_glyphs(rom):
    w, h, cells = jim_map(rom, BIGFONT)
    assert (w, h) == (77, 2)
    glyphs = {}
    for k in range(0x5C - 0x20):
        v = rom.s8(BIG_CHARTAB + k)
        width, col = (1, -v) if v < 0 else (2, v)
        glyphs[str(0x20 + k)] = {"w": width, "col": col,
                                 "top": [cell(cells[col + i]) for i in range(width)],
                                 "bottom": [cell(cells[w + col + i]) for i in range(width)]}
    return glyphs


def export(rom, out):
    os.makedirs(out, exist_ok=True)
    meta = {"source": "lst/nhl94.bin (CRC32 %08X); docs/specs/ui_ingame.md" % ROM_CRC,
            "screen": {"cells": [32, 28], "port_x0": 32},
            "cram": [[rom.u16(RINK + rom.u32(RINK) + 32 * k + 2 * i) for i in range(16)] for k in range(2)]}

    # print font
    font = remap(blob(rom, FONT), REMAP_FONT)
    s = sheet(font, 0)
    s.save(os.path.join(out, "font_idx.png"))
    fw, fh, fcells = jim_map(rom, FONT)
    meta["font"] = {"file": "font_idx.png", "tiles": len(font) // 32, "per_row": 16, "line": 0,
                    "remap": REMAP_FONT.hex().upper(), "chars": {str(c): fcells[c] & 0x7FF for c in range(min(fw * fh, 0x80))},
                    "blank_char": 64, "skip_char": 94,
                    "note": "print adds printa ($8000 in play: line 0, priority); '@' writes tile $7FF (transparent), '^' skips a cell, byte 0 is ignored"}

    # printbig font
    big = remap(blob(rom, BIGFONT), REMAP_BIG)
    sheet(big, 1).save(os.path.join(out, "bigfont_idx.png"))
    meta["bigfont"] = {"file": "bigfont_idx.png", "tiles": len(big) // 32, "per_row": 16, "line": 1,
                       "remap": REMAP_BIG.hex().upper(), "chartab": BIG_CHARTAB, "first_char": 0x20,
                       "last_char": 0x5B, "glyphs": bigfont_glyphs(rom),
                       "note": "printbig upper-cases a-z; each glyph is 2 rows; the cursor moves by w; "
                               "the cell word is map + printa + word_FFB010 (map line 1, so line 1 with printa $8000)"}

    # Framer
    fr = blob(rom, FRAMER)
    w, h, cells = jim_map(rom, FRAMER)
    assert (w, h) == (3, 3) and len(fr) == 9 * 32
    c = Canvas(24, 24)
    draw_map(c, fr, cells, 3, 0, 0, 3)
    c.save(os.path.join(out, "framer_idx.png"))
    meta["framer"] = {"file": "framer_idx.png", "per_row": 3, "line": 1,
                      "order": ["TL", "T", "TR", "L", "C", "R", "BL", "B", "BR"],
                      "map": [cell(v) for v in cells],
                      "note": "Framer(w, h): row 0 = TL, T x (w-2), TR; rows 1..h-2 = L, C x (w-2), R; row h-1 = BL, B x (w-2), BR. "
                              "Cell word = map + printa + framercset; printy ends at y + h"}

    # EA logo (score box, no power play)
    ea = remap(blob(rom, EA_LOGO), REMAP_BIG)
    w, h, cells = jim_map(rom, EA_LOGO)
    c = Canvas(w * 8, h * 8)
    draw_map(c, ea, cells, w, 0, 0, h)
    c.save(os.path.join(out, "ea_logo_idx.png"))
    meta["ea_logo"] = {"file": "ea_logo_idx.png", "cells": [w, h], "line": 1, "remap": REMAP_BIG.hex().upper()}

    # team plates (penalty screen)
    pl = blob(rom, PLATES)
    w, h, cells = jim_map(rom, PLATES)
    assert (w, h) == (11, 56)
    c = Canvas(88, 16 * 28)
    draw_map(c, pl, cells, w, 0, 0, 56)
    c.save(os.path.join(out, "team_plates_idx.png"))
    meta["team_plates"] = {"file": "team_plates_idx.png", "cells": [11, 2], "teams": 28, "line": 1,
                           "note": "plate t is rows 2t, 2t+1 of the map (sub_16D64: $2C bytes a team)"}

    # energy bars (line menu)
    en = blob(rom, ENERGY)
    w, h, cells = jim_map(rom, ENERGY)
    assert (w, h) == (2, 16)
    c = Canvas(16, 128)
    draw_map(c, en, cells, w, 0, 0, 16)
    c.save(os.path.join(out, "energy_idx.png"))
    meta["energy"] = {"file": "energy_idx.png", "cells": [2, 16], "map": [cell(v) for v in cells],
                      "note": "sub_12E66 draws map row 15 - min(getlinee / 256, 15)"}

    with open(os.path.join(out, "ui.json"), "w") as f:
        json.dump(meta, f, indent=1, sort_keys=True)
    with open(os.path.join(out, "messages.json"), "w") as f:
        json.dump(messages(rom), f, indent=1, sort_keys=True)


def main():
    rom_path = sys.argv[1] if len(sys.argv) > 1 else "lst/nhl94.bin"
    out = sys.argv[2] if len(sys.argv) > 2 else "godot/assets/ui"
    with open(rom_path, "rb") as f:
        data = f.read()
    assert zlib.crc32(data) & 0xFFFFFFFF == ROM_CRC, "unexpected ROM"
    export(Rom(data), out)
    print("wrote the in-game overlay fonts, frame, logo, plates, energy bars and messages to %s" % out)


if __name__ == "__main__":
    main()
