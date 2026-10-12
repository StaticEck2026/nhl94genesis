#!/usr/bin/env python3
"""Export the pause / intermission menus and the stats pages of NHL '94 for the Godot port.

Offline only. The game never reads the ROM; it loads what this writes under
godot/assets/ui/menus/. Usage:
  python3 tools/extract/ui_menus.py [lst/nhl94.bin] [godot/assets/ui/menus] [--preview DIR]
Spec: docs/specs/ui_menus.md. The in-game overlay art (in-game font, printbig font, the
in-game Framer tiles, the team-name plates) is exported by tools/extract/ui_overlay.py into
godot/assets/ui/ and is not repeated here; pages.json names those files where a page uses
them.

Index textures as in assets.py: R = colour index * 17, G = palette line * 85, A = 255 where
drawn. Fonts are drawn with line 0 (print adds the attribute: the cell's line is the
attribute's). Framer tiles and logos keep their map line (1); Framer and printbig add the
attribute to the map word, so their line is map line + attribute line (mod 4). Full-screen
backgrounds are opaque: a colour-0 pixel is written as colour 0 of line 0, the VDP backdrop
($8700: line 0 colour 0).

Writes:
  menus.json            the menu tables run by sub_7E36/sub_7E46/sub_7EF2/sub_7E88 (pause,
                        intermission, shootout, Line Editor exit menu): labels, handler
                        addresses and ids, the two attribute strings, the box geometry
  pages.json            per page: handler, listing line, screen setup, every inline string
                        decoded into print ops, the string tables and data tables it reads,
                        scroll geometry and the controls
  palettes.json         CRAM lines of the stats pages ($54E24), the Player Cards page,
                        the 28 team-logo lines ($FF462) and the photo line ($C63F8)
  font_stats_idx.png    $AAC52 font, raw (stats pages print font 0, word_FFB012)
  font_stats_alt_idx.png  the same through remap D1 23 45 67 89 AB CD EF (font 1,
                        word_FFB014: colour 0 -> 13, an opaque background)
  font_cards_idx.png    the same through remap 05 23 41 67 89 AB CD EF (Player Cards)
  font.json             char -> tile map (128 codes) shared by the three sheets
  framer_stats_idx.png  Framer's 3x3 tiles ($55B7E) through remap 91 23 45 67 89 AB CD EF
  stats_bg_idx.png      the SPORTS background of every stats page ($54E24, 40x28 cells)
  cards_bg_idx.png      the Player Cards background ($E6632, 40x28 cells)
  hockey_night_idx.png  the "HOCKEY NIGHT" title of Other Scores ($B3E74, 19x2 cells)
  logo_nhl_idx.png      NHL shield ($E9A80, 6x6 cells), logo_nhlpa_idx.png ($E9ED6)
  team_logos_idx.png    the 28 team logos of Period Stats / Player Cards ($F86F2, 6x6
                        cells each, 4 to a row, map line 1; colours in palettes.json)
  photos_idx.png        the Player Cards photos ($F92F4 lists, 3 bpp packed, 6x6 cells,
                        16 to a row); photos.json maps (team, roster slot) -> photo
  replay_panel_idx.png  the instant-replay panel: rink map cols 32-39, rows 85-88 (sub_A448)
  replay_prompt_idx.png the instant-replay button card ($BB4EE, 16x11 cells, sub_A4A8), drawn
                        with the in-game rink palette (no palette load)

With --preview DIR it also writes static previews of every page (background, frames, big
titles and fixed labels, no live numbers) built from the same data, for checking.
"""
import json
import os
import sys
import zlib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from assets import ROM_CRC, BytesRom, Canvas, Rom, decompress, png  # noqa: E402

FONT = 0xAAC52            # .map.jim: tiles at +10 (94), glyph map 32x4 via the long at +4
BIGFONT = 0xA9A10         # printbig tiles/map (exported by ui_overlay.py as ui/bigfont_idx.png)
BIG_CHARTAB = 0x1916A
FRAMER = 0x55B7E          # framermap: map 3x3, compressed tiles at +8 ($55B86)
STATS_BG = 0x54E24        # sub_9BD8 (L34170)
CARDS_BG = 0xE6632        # Player Cards (L965357)
HOCKEY_NIGHT = 0xB3E74    # Other Scores (L30615)
LOGO_NHL = 0xE9A80
LOGO_NHLPA = 0xE9ED6
TEAM_LOGOS = 0xF86F2      # 28 longs -> .map.jim (no palette)
LOGO_PALS = 0xFF462       # 32 bytes a team (one CRAM line)
PHOTO_BASE = 0xC63F8      # shared palette and 6x6 map of the photos
PHOTO_LISTS = 0xF92F4     # 28 longs -> {long photo, word roster slot}..., long 0
PHOTO_GENERIC = (0xC682E, 0xC6B98, 0xC6F02, 0xC726C)
RINK = 0x5605A
TEAMS = 0x30E
REPLAY_PROMPT = 0xBB4EE   # sub_A4A8 (L34880): 16x11 cells at window (2,0), tiles at word_FFB026

REMAP_STATS_ALT = bytes.fromhex("D123456789ABCDEF")    # $9CAE (sub_9BD8, font 1)
REMAP_FRAMER_STATS = bytes.fromhex("9123456789ABCDEF")  # $9C34 (sub_9BD8)
REMAP_CARDS_FONT = bytes.fromhex("0523416789ABCDEF")    # $FA0F4 (Player Cards)

HANDLER_IDS = {
    0x15464: "close",            # rtss2: a bare rts; row 0 closes the menu (sub_7E88)
    0x9FD0: "instant_replay",
    0x9DE6: "change_goalie",
    0x82DA: "edit_lines",
    0xFDC5A: "game_stats",
    0x945A: "player_stats",
    0x9428: "playoff_stats",
    0x8EB0: "scoring_summary",
    0x9142: "penalty_summary",
    0x89AC: "team_roster",
    0x80D4: "other_scores",
    0x9A2A: "crowd_meter",
    0x9D7A: "timeout",
    0xFA07E: "player_cards",
    0xFBC14: "record_holders",
    0xFD90C: "period_stats",
    0xFE1D8: "goalie_control_toggle",
    0xFC620: "shootout_setup",
    0x171CE: "lines_set_original",
    0x8928: "lines_save_team",
    0x88C8: "lines_load_team",
}

# Listing lines (first instruction) of the handlers, from lst/nhl94.bin.lst.
HANDLER_LINES = {
    0x15464: 50812, 0x9FD0: 34505, 0x9DE6: 34315, 0x82DA: 30809, 0xFDC5A: 971880,
    0x945A: 33268, 0x9428: 33252, 0x8EB0: 32247, 0x9142: 32544, 0x89AC: 31609,
    0x80D4: 30583, 0x9A2A: 33980, 0x9D7A: 34285, 0xFA07E: 965326, 0xFBC14: 967908,
    0xFD90C: 971034, 0xFE1D8: 973221, 0xFC620: 968926, 0x171CE: 53754, 0x8928: 31535,
    0x88C8: 31438,
}

MENU_TABLES = [
    # name, address, listing line of the data, where it is used
    ("pause", 0x19700, 58935, "PauseMode L30217: normal"),
    ("pause_timeout_used", 0x1988C, None, "PauseMode L30235: the pausing team's $30 bit 2 is set"),
    ("pause_shootout", 0x19664, None, "PauseMode L30229: word_FFC2FA bit 0 (shootout mode)"),
    ("intermission_pregame", 0x19A84, None, "unk_131CC[0]: gsp 0, OptPlayMode 0"),
    ("intermission_pregame_playoffs", 0x19B38, None, "unk_131CC[5]: gsp 0, OptPlayMode != 0"),
    ("intermission_period", 0x19C04, None, "unk_131CC[1..3] and [6..8]: gsp 1-3"),
    ("intermission_final", 0x19D60, None, "unk_131CC[4]: gsp 4, OptPlayMode 0"),
    ("intermission_final_playoffs", 0x19E74, None, "unk_131CC[9]: gsp 4, OptPlayMode != 0"),
    ("intermission_shootout", 0x19A00, None, "Intermission L47638: word_FFC2FA bit 0"),
    ("line_editor_exit", 0x19F88, None, "Edit Lines $8812 (L31383): a saved line set exists for this team"),
    ("line_editor_exit_nosave", 0x19FF8, None, "Edit Lines $8812: no saved set (byte $FFD076 != team + 1)"),
]
INTERMISSION_PTRS = 0x131CC   # unk_131CC (L47683), 10 longs


class R(Rom):
    def s8(self, a):
        v = self.b[a]
        return v - 256 if v >= 128 else v


def s8(v):
    return v - 256 if v >= 128 else v


def remap(raw, table):
    """remap (L44006): colour n -> high nibble of table[n/2] for even n, else the low."""
    def m(n):
        t = table[n >> 1]
        return t >> 4 if n % 2 == 0 else t & 15
    return bytes((m(v >> 4) << 4) | m(v & 15) for v in raw)


class Jim:
    """A dobitmap image: long palette offset ($FFFFFFFF: none), long map offset, word tile
    count (bit 15: compressed, sub_1177A), tiles; the map is w, h, then w*h words."""

    def __init__(self, rom, base, tiles=None):
        self.base = base
        po, mo = rom.u32(base), rom.u32(base + 4)
        n = rom.u16(base + 8)
        if tiles is not None:
            self.tiles = tiles
        elif n & 0x8000:
            self.tiles = decompress(rom, base + 8)
        else:
            self.tiles = rom.b[base + 10:base + 10 + 32 * n]
        self.pal = []
        if po != 0xFFFFFFFF and mo > po:
            p = base + po
            self.pal = [[rom.u16(p + 32 * k + 2 * i) for i in range(16)] for k in range((mo - po) // 32)]
        m = base + mo
        self.w, self.h = rom.u16(m), rom.u16(m + 2)
        self.cells = [rom.u16(m + 4 + 2 * i) for i in range(self.w * self.h)]


def draw_cells(c, tiles, cells, w, rows, cols, x0=0, y0=0, col0=0, row0=0, opaque=False, xor=0):
    src = BytesRom(tiles)
    n = len(tiles) // 32
    for r in range(rows):
        for k in range(cols):
            v = cells[(row0 + r) * w + col0 + k] ^ xor
            t = v & 0x7FF
            if t >= n:
                continue
            line = (v >> 13) & 3
            px = src.tile(32 * t)
            hf, vf = bool(v & 0x800), bool(v & 0x1000)
            for y in range(8):
                for x in range(8):
                    i = px[y * 8 + x]
                    xx = x0 + 8 * k + (7 - x if hf else x)
                    yy = y0 + 8 * r + (7 - y if vf else y)
                    if i == 0:
                        if opaque:
                            c.put(xx, yy, 0, 0, opaque=True)
                        continue
                    c.put(xx, yy, i, line)


def sheet(tiles, per_row=16, line=0):
    src = BytesRom(tiles)
    n = len(tiles) // 32
    c = Canvas(per_row * 8, ((n + per_row - 1) // per_row) * 8)
    for i in range(n):
        c.tile(src, 32 * i, (i % per_row) * 8, (i // per_row) * 8, line)
    return c


# --- print strings -----------------------------------------------------------------------

P2_NAMES = {0xFF: "plane", 0xFE: "attr", 0xFD: "x", 0xFC: "y", 0xFB: "dx", 0xFA: "dy", 0xF9: "font"}


def decode(rom, a, flavour):
    """An inline print string as ops. flavour "print" (printz/print L45521, printbig
    L45806): byte 0 skipped; a negative byte b gives v = -b: attr = (v << 9) & $F800,
    plane = v & 3 (1 A, 2 B, 3 window), then x and y bytes. "print2" (printz2/print2
    L45338): $FF plane, $FE attr ((b & 7) ror 3), $FD x, $FC y, $FB dx, $FA dy, $F9 font
    (word_FFB012 + 2n), $F8 attr+plane+x+y; byte 0 calls asstab[0] = rts. Both: '@' is the
    blank tile $7FF, '^' skips a column."""
    n = rom.u16(a)
    b = rom.b[a + 2:a + n]
    ops, text, i = [], "", 0

    def flush():
        nonlocal text
        if text:
            ops.append({"text": text})
            text = ""
    while i < len(b):
        c = b[i]
        if flavour == "print":
            if c == 0:
                i += 1
                continue
            if c >= 0x80:
                flush()
                v = 256 - c
                ops.append({"at": [s8(b[i + 1]), s8(b[i + 2])], "plane": "?ABW"[v & 3],
                            "attr": (v << 9) & 0xF800})
                i += 3
                continue
        else:
            if c == 0:
                i += 1
                continue
            if c >= 0xF8:
                flush()
                if c == 0xF8:
                    at, pl, x, y = b[i + 1], b[i + 2], b[i + 3], b[i + 4]
                    ops.append({"at": [x, y], "plane": "?ABW"[pl & 3], "attr": ((at & 7) << 13) & 0xFFFF})
                    i += 5
                    continue
                k = P2_NAMES[c]
                v = b[i + 1]
                if k == "plane":
                    v = "?ABW"[v & 3]
                elif k == "attr":
                    v = ((v & 7) << 13) & 0xFFFF
                elif k in ("dx", "dy"):
                    v = s8(v)
                ops.append({k: v})
                i += 2
                continue
        text += chr(c)
        i += 1
    flush()
    return n, ops


def plain(rom, a):
    n = rom.u16(a)
    return n, rom.b[a + 2:a + n].replace(b"\x00", b"").decode("latin-1")


def string_list(rom, a, count, flavour=None):
    out = []
    for _ in range(count):
        if flavour:
            n, ops = decode(rom, a, flavour)
            out.append({"address": a, "ops": ops})
        else:
            n, t = plain(rom, a)
            out.append({"address": a, "text": t})
        a += n
    return out


def inline(rom, a, flavour, note="", line=None):
    """An inline string after jsr printz / printz2 / sub_11DE2 (printbig); a note starting
    with "big" marks printbig (same command bytes as print, 2-cell glyphs, upper case)."""
    n, ops = decode(rom, a, flavour)
    d = {"address": a, "kind": {"print": "printz", "print2": "printz2"}[flavour], "ops": ops}
    if note.startswith("big"):
        d["kind"] = "printbig"
    if note:
        d["note"] = note
    if line:
        d["line"] = line
    return d


# --- menus -------------------------------------------------------------------------------

def menu_table(rom, a):
    """sub_7EF2 (L30393): string 0 is the row attribute, string 1 the cursor-row attribute;
    then rows {print2 string, long handler} until a word whose second word is negative
    (the terminator $0004 $FF00)."""
    n0, a0ops = decode(rom, a, "print2")
    n1, a1ops = decode(rom, a + n0, "print2")
    p = a + n0 + n1
    items = []
    while True:
        n = rom.u16(p)
        raw = rom.b[p + 2:p + n].decode("latin-1")
        h = rom.u32(p + n)
        toggle = raw[:1] == "x"   # sub_8008: prints $8050 / $8064 instead (the current setting)
        items.append({"label": raw[1:].strip() if toggle else raw.strip(), "raw": raw, "handler": h,
                      "id": HANDLER_IDS.get(h, "?"), "toggle": toggle})
        p += n + 4
        if rom.u16(p + 2) & 0x8000:
            break
    return {"address": a, "row_attr": a0ops, "cursor_attr": a1ops, "items": items, "end": p}


def menus(rom):
    tables = {}
    for name, a, line, note in MENU_TABLES:
        t = menu_table(rom, a)
        t["used"] = note
        if line:
            t["line"] = line
        tables[name] = t
    ptrs = [rom.u32(INTERMISSION_PTRS + 4 * i) for i in range(10)]
    by_addr = {t["address"]: k for k, t in tables.items()}
    _, manual = plain(rom, 0x8050)
    _, auto = plain(rom, 0x8064)
    return {
        "source": "lst/nhl94.bin (CRC32 %08X); docs/specs/ui_menus.md" % ROM_CRC,
        "engine": {
            "routines": {"sub_7E36": 30312, "sub_7E46": 30321, "sub_7E72": 30337, "sub_7E88": 30347,
                         "sub_7EF2": 30393, "sub_8008": 30477, "sub_7DCE": 30277, "PauseMode": 30217,
                         "sub_11318": 44487},
            "screen": "H32 window plane over the side view (sub_7DCE: $9100/$921C, SetHor, erase 32x28 "
                      "with $7FF); on the H40 stats pages the same engine runs at printx 9",
            "box": {"x": 5, "x_h40": 9, "y": 12, "w": 22, "h": 6, "framer_attr": 0x8000},
            "rows": {"x": 7, "x_h40": 11, "y0": 13, "visible": 4, "chars": 18},
            "up_arrow": {"x": 6, "y": 13, "char": "{", "attr": 0xA000, "when": "top row > 0"},
            "down_arrow": {"x": 6, "y": 16, "char": "}", "attr": 0xA000, "when": "rows remain below"},
            "clear_columns": {"x": [6, 25], "rows": [13, 16], "string": 0x7F56},
            "fade_in": 0x18,
            "repeat": {"first_delay": 16, "every": 5, "note": "sub_11318: a held direction repeats (counter $F, then 4)"},
            "buttons": {"up": "cursor - 1", "down": "cursor + 1", "C": "run the row's handler",
                        "Start": "close (same as row 0)", "A/B": "nothing"},
        },
        "goalie_toggle": {"char": "x", "manual": {"address": 0x8050, "text": manual},
                          "auto": {"address": 0x8064, "text": auto},
                          "flag": "word_FFD05A (pad 1) / word_FFD05C (pad 2, sflags bit 1); non-zero = Auto",
                          "note": "the row shows the current setting: Manual when the word is 0"},
        "intermission_index": {"address": INTERMISSION_PTRS, "line": 47683,
                               "formula": "gsp + (OptPlayMode != 0 ? 5 : 0); shootout: unk_19A00",
                               "tables": [by_addr.get(p, p) for p in ptrs]},
        "handlers": {"%X" % k: {"id": v, "line": HANDLER_LINES.get(k)} for k, v in sorted(HANDLER_IDS.items())},
        "tables": tables,
    }


# --- graphics ----------------------------------------------------------------------------

def font_sheets(rom):
    count = rom.u16(FONT + 8)
    raw = rom.b[FONT + 10:FONT + 10 + 32 * count]
    gm = FONT + rom.u32(FONT + 4)
    w, h = rom.u16(gm), rom.u16(gm + 2)
    chars = {str(c): rom.u16(gm + 4 + 2 * c) & 0x7FF for c in range(w * h)}
    return raw, chars


def framer(rom, table):
    j = Jim(rom, FRAMER)
    tiles = remap(j.tiles, table)
    c = Canvas(24, 24)
    for i, v in enumerate(j.cells):
        draw_cells(c, tiles, [v], 1, 1, 1, (i % 3) * 8, (i // 3) * 8)
    return c, j


def image(rom, base, opaque=False, tiles=None):
    j = Jim(rom, base, tiles)
    c = Canvas(j.w * 8, j.h * 8)
    draw_cells(c, j.tiles, j.cells, j.w, j.h, j.w, opaque=opaque)
    return c, j


def photo_tiles(rom, p):
    """sub_FE98A (L974538): word count, then 3 bytes per pixel row of a tile: eight 3-bit
    values, high bits first, each stored as colour value + 5."""
    n = rom.u16(p + 8)
    a = p + 10
    out = bytearray()
    for _ in range(n * 8):
        v = (rom.b[a] << 16) | (rom.b[a + 1] << 8) | rom.b[a + 2]
        a += 3
        row = 0
        for k in range(8):
            row = (row << 4) | (((v >> (21 - 3 * k)) & 7) + 5)
        out += row.to_bytes(4, "big")
    return bytes(out)


def photos(rom):
    base = Jim(rom, PHOTO_BASE)
    order, index, teams = [], {}, []

    def add(p):
        if p not in index:
            index[p] = len(order)
            order.append(p)
        return index[p]
    for g in PHOTO_GENERIC:
        add(g)
    for t in range(28):
        a = rom.u32(PHOTO_LISTS + 4 * t)
        ent = []
        while rom.u32(a):
            ent.append({"slot": rom.u16(a + 4), "photo": add(rom.u32(a))})
            a += 6
        teams.append(ent)
    per_row = 16
    c = Canvas(per_row * 48, ((len(order) + per_row - 1) // per_row) * 48)
    for i, p in enumerate(order):
        tiles = photo_tiles(rom, p)
        # The photo's own map offset is 0: sub_FAEBC then uses $C63F8's map.
        cells = base.cells if rom.u32(p + 4) == 0 else Jim(rom, p, tiles).cells
        draw_cells(c, tiles, cells, 6, 6, 6, (i % per_row) * 48, (i // per_row) * 48)
    return c, order, teams, base


def team_logos(rom):
    c = Canvas(4 * 48, 7 * 48)
    for t in range(28):
        j = Jim(rom, rom.u32(TEAM_LOGOS + 4 * t))
        assert (j.w, j.h) == (6, 6)
        draw_cells(c, j.tiles, j.cells, 6, 6, 6, (t % 4) * 48, (t // 4) * 48)
    pals = [[rom.u16(LOGO_PALS + 32 * t + 2 * i) for i in range(16)] for t in range(28)]
    return c, pals


def replay_panel(rom):
    """sub_A448 (L34848): dobitmap of the rink map (Rinktilelist $5605A) from cell (32, 85),
    8 x 4 cells, to window (2, 2) with tile base word_FFB018 (the rink tiles)."""
    pal_off, map_off, n = rom.u32(RINK), rom.u32(RINK + 4), rom.u16(RINK + 8)
    tiles = rom.b[RINK + 10:RINK + 10 + 32 * n]
    m = RINK + map_off
    w = rom.u16(m)
    cells = [rom.u16(m + 4 + 2 * i) for i in range(w * rom.u16(m + 2))]
    c = Canvas(64, 32)
    draw_cells(c, tiles, cells, w, 4, 8, col0=32, row0=85, opaque=True)
    return c


# --- pages ---------------------------------------------------------------------------------

def team_names(rom):
    out = []
    for t in range(28):
        p = rom.u32(TEAMS + 4 * t)
        a = p + rom.u16(p + 4)
        _, city = plain(rom, a)
        a += rom.u16(a)
        _, abbr = plain(rom, a)
        out.append({"city": city, "abbr": abbr})
    return out


def game_stats_rows(rom, a, n):
    """$FDFAA / $FE098 (sub_FDE24 L972338, sub_FDEB4 L972482): label, word field, word
    second field ($FFFF none). Field $FFFF = shooting %, $352 and $A print m:ss, $14 adds
    ' (' pct '%)'. Fields are team-struct offsets."""
    port = {0x0C: "goals", 0x00: "shots", 0x02: "pp_goals", 0x04: "power_plays", 0x352: "pp_time",
            0x354: "pp_shots", 0x356: "shorthanded_goals", 0x35A: "breakaway_goals",
            0x358: "breakaway_attempts", 0x35E: "onetimer_goals", 0x35C: "onetimer_attempts",
            0x362: "penalty_shot_goals", 0x360: "ps_attempts", 0x0E: "faceoffs_won", 0x10: "checks",
            0x06: "penalties", 0x08: "penalty_minutes", 0x0A: "attack_time", 0x14: "passes",
            0x12: "pass_attempts"}
    rows = []
    for _ in range(n):
        ln, label = plain(rom, a)
        f1, f2 = rom.u16(a + ln), rom.u16(a + ln + 2)
        if f1 == 0xFFFF:
            fmt = "goals*100/shots then '%'"
        elif f1 in (0x352, 0x0A):
            fmt = "PushTime m:ss"
        elif f1 == 0x14:
            fmt = "n/m (pct%)"
        elif f2 != 0xFFFF:
            fmt = "n/m"
        else:
            fmt = "n"
        rows.append({"address": a, "len": ln, "label": label, "field": f1 if f1 != 0xFFFF else None,
                     "field2": f2 if f2 != 0xFFFF else None, "format": fmt,
                     "port": [port.get(f1, "goals/shots" if f1 == 0xFFFF else "?")] +
                             ([port.get(f2, "?")] if f2 != 0xFFFF else []),
                     "label_x": 0x15 - (ln >> 1)})
        a += ln + 4
    return rows


def attrib_columns(rom, a):
    """PAttribColumns $193F8 / GAttribColumns $1955A: print2 header string, long d4.
    d4 low word: 0 status, 2 energy, 4 handed / glove hand, 6 weight, $A rating; high word:
    the attribute mask CalcAttrib (L966171) sums. Ends at a negative word."""
    out = []
    while rom.u16(a) < 0x8000:
        n, ops = decode(rom, a, "print2")
        d4 = rom.u32(a + n)
        out.append({"address": a, "ops": ops, "d4": d4, "kind": {0: "status", 2: "energy", 4: "handed",
                                                                    6: "weight", 0xA: "rating"}.get(d4 & 0xFFFF, "?"),
                    "mask": d4 >> 16})
        a += n + 4
    return out


def pages(rom):
    teams = team_names(rom)
    P = {}
    stats_setup = "sub_9BD8 (L34170): forceblack; H40 ($8C81), window map 64 wide, full-screen window " \
                  "($921C stays from the pause screen), stats Framer tiles (remap 91..) at framercset, " \
                  "font 0 raw at word_FFB012, window = stats_bg with priority, rows d0..d1-1 redrawn " \
                  "without priority (where plane B text shows), font 1 (remap D1..) at word_FFB014, " \
                  "plane B cleared to $7FF; fade in ($18)"
    exit_note = "Start (held, d3 bit 7) -> $9CD8 (L34244): forceblack, back to H32 and the in-game VRAM, " \
                "then sub_7E46 redraws the pause menu (the pause loop re-enters at the same row)"

    P["game_stats"] = {
        "handler": 0xFDC5A, "line": 971880, "setup": {"routine": "sub_9BD8", "d0": 9, "d1": 0x1A, "note": stats_setup},
        "static": [
            inline(rom, 0xFDC6A, "print", "window (4,1): box", 971890),
            {"op": "framer", "at": [4, 1], "w": 0x20, "h": 6, "attr": 0x8000, "line": 971906},
            inline(rom, 0xFDC80, "print", "big title", 971912),
            {"op": "plate", "team": "away", "at": [7, 1], "routine": "sub_8078 d0=$2C", "line": 971946},
            {"op": "plate", "team": "home", "at": [22, 1], "routine": "sub_8078 d0=0", "line": 971958},
            inline(rom, 0xFDE2A, "print", "window (2,7): away plate", 972338),
            {"op": "plate", "team": "away", "at": [2, 7]},
            inline(rom, 0xFDE40, "print", "window (26,7): home plate", 972360),
            {"op": "plate", "team": "home", "at": [26, 7]},
        ],
        "arrows": [inline(rom, a, "print2", n) for a, n in
                   ((0xFDDC6, "up arrow when scrolled"), (0xFDDDA, "erase up arrow"),
                    (0xFDDF6, "down arrow when more below"), (0xFDE0A, "erase down arrow"))],
        "rows_with_penalties": game_stats_rows(rom, 0xFDFAA, 15),
        "rows_without_penalties": game_stats_rows(rom, 0xFE098, 11),
        "append": {"pct": "%", "slash": "/", "open": " (", "close": "%)", "addresses": [0xFDEF0, 0xFDF3A, 0xFDF5C, 0xFDF8A]},
        "layout": {"plane": "B", "attr": 0x8000, "row0": 0, "row_step": 2, "away_center_x": 9,
                   "home_center_x": 0x22, "label_x": "0x15 - len/2 (len = the string's length word)",
                   "value_x": "center - len/2 of the built string"},
        "scroll": {"vscroll_b": "$FFB0 + d5ae (plane row 0 at screen row 10)", "step_px": 2,
                   "stop_every_px": 16, "max": "$70 with OptPen, else $30"},
        "controls": {"up/down (held)": "scroll 2 px a frame until a 16 px step", "Start": exit_note},
    }
    P["player_stats"] = {
        "handler": 0x945A, "line": 33268, "setup": {"routine": "sub_9BD8", "d0": 0xD, "d1": 0x16},
        "static": [
            inline(rom, 0x9476, "print", "window (5,1): box", 33280),
            {"op": "framer", "at": [5, 1], "w": 0x1E, "h": 6, "attr": 0x8000},
            inline(rom, 0x94B2, "print2", "'A - Switch Teams' (not in Playoff Stats)", 33297),
            inline(rom, 0x94D4, "print", "big title", 33308),
            {"op": "plate", "team": "shown", "at": [14, 1], "routine": "sub_8078"},
            inline(rom, 0x9620, "print2", "column header 'Player' (sub_961A)", 33434),
            inline(rom, 0x966C, "print2", "category box (9,7)", 33457),
            {"op": "framer", "at": [9, 7], "w": 0x16, "h": 3, "attr": 0xC000},
            inline(rom, 0x9684, "print", "category text at (10,8), attr $E000", 33464),
        ],
        "headers_goalie": string_list(rom, 0x990E, 1, "print2"),
        "headers_skater": string_list(rom, 0x9924, 5, "print2"),
        "categories": string_list(rom, 0x9942, 6, "print2"),
        "category_index": "d5ac: -1 Goalie Saves, 0 Goals, 1 Assists, 2 Points, 3 Shots On Goal, 4 Penalty Minutes",
        "fields": {"address": 0x98FA, "per_category": [[0xB4, None], [0xCE, None], [0xB4, 0xCE], [0xE8, None], [0x102, None]],
                   "note": "team-struct byte arrays + pnum: $B4 goals, $CE assists, $E8 shots, $102 PIM; points = "
                           "goals + assists; Playoff Stats (d7 = 1) reads word arrays at $FFCD96/$FFCDCA/$FFCDFE/$FFCE32 "
                           "($98E6) instead",
                   "port": {"0xB4": "player_goals", "0xCE": "player_assists", "0xE8": "player_shots", "0x102": "player_pim"}},
        "arrows": string_list(rom, 0x9A02, 4, "print2"),
        "layout": {"plane": "B", "row_step": 2, "rank_x": 1, "rank_width": 2, "rank_attr": 0xE000, "name_x": 4,
                   "name": "sub_18B26: number + ' ' + last name", "values_x": 0x11, "value_width": 4,
                   "selected_column_attr": 0xC000, "other_attr": 0x8000, "rows_visible": 6,
                   "goalie_columns": "saves = shots - goals against, shots against, save % (%d%%)"},
        "sort": "sub_961A (L33434): the roster minus goalies (or the goalies only for Goalie Saves) by the "
                "category value, larger first; ties keep the lower roster slot ($FF - slot as low byte); the list "
                "is stored at Satt $FFC018, terminated by $FF",
        "scroll": {"vscroll_b": "$FF98 + d5ae", "row_px": 16, "step_px": 2},
        "controls": {"left/right": "category -1..4 (redraws, sub_961A)", "up/down (held)": "scroll",
                     "A": "switch teams (not in Playoff Stats)", "Start": exit_note},
    }
    P["scoring_summary"] = {
        "handler": 0x8EB0, "line": 32247, "setup": {"routine": "sub_9BD8", "d0": 0xA, "d1": 0x1A},
        "static": [
            inline(rom, 0x8EBE, "print", "window (4,1): box", 32250),
            {"op": "framer", "at": [4, 1], "w": 0x20, "h": 6, "attr": 0x8000},
            inline(rom, 0x8ED4, "print", "big title", 32262),
            {"op": "plate", "team": "away", "at": [7, 1]}, {"op": "plate", "team": "home", "at": [22, 1]},
            inline(rom, 0x8F04, "print2", "column headers, font 1, line 2", 32294),
        ],
        "strength": string_list(rom, 0x912A, 5),
        "strength_index": "byte 2 of the record & $7F = 2 + scorer.tmap - other.tmap: 0 SH2, 1 SH, 2 even, 3 PP, 4 PP2",
        "periods": string_list(rom, 0x11C92, 4),
        "arrows": string_list(rom, 0x9400, 4, "print2"),
        "arrows_at": "sub_93C4 (L33189), shared with Penalty Summary",
        "record": "ScoreSum $FFC474, 6 bytes: word time ((gsp << 14) + seconds into the period), byte strength "
                  "| $80 away, byte scorer, byte assist 1, byte assist 2 ($FF none); ScoreSumbytes $FFC472",
        "layout": {"plane": "B", "entry_rows": 4, "period_x": 1, "time_x": 3, "team_x": 0xC, "team": "abbreviation",
                   "scorer_x": 0x10, "assist_x": 0x12, "assist_attr": 0xE000, "strength_x": 0x23,
                   "name": "sub_18AE8: number, ' ', initial, '. ', last name", "visible_entries": 4},
        "scroll": {"vscroll_b": "$FFB0 + d5ae", "entry_px": 32, "step_px": 2,
                   "start": "d5ae = entries * 32, then scrolls up to max(entries*32 - $80, 0) at 2 px a frame"},
        "controls": {"up/down (held)": "scroll", "Start": exit_note},
    }
    P["penalty_summary"] = {
        "handler": 0x9142, "line": 32544, "setup": {"routine": "sub_9BD8", "d0": 0xA, "d1": 0x19},
        "static": [
            inline(rom, 0x9150, "print", "window (4,1): box", 32552),
            {"op": "framer", "at": [4, 1], "w": 0x20, "h": 6, "attr": 0x8000},
            inline(rom, 0x9166, "print", "big title", 32574),
            {"op": "plate", "team": "away", "at": [7, 1]}, {"op": "plate", "team": "home", "at": [22, 1]},
            inline(rom, 0x9196, "print2", "column headers", 32622),
        ],
        "record": "PenSum $FFC5DE, 4 bytes: word time, byte PenaltyList id | $80 away, byte pnum; PenSumLength $FFC5DC",
        "penalty_names": "PenaltyList $18E0C (ui/messages.json penalty_list): byte 1 = minutes, then the text",
        "layout": {"plane": "B", "entry_rows": 3, "period_x": 1, "time_x": 3, "team_x": 0xC, "minutes_x": 0x23,
                   "player_x": 0x10, "penalty_x": 0x13, "penalty_attr": 0xE000, "visible_entries": 5},
        "arrows": string_list(rom, 0x9400, 4, "print2"),
        "arrows_at": "sub_93C4 (L33189): printz2 window (4,9) attr $8000 font 1, then the table entry",
        "scroll": {"vscroll_b": "$FFB0 + d5ae", "entry_px": 24, "step_px": 2,
                   "start": "d5ae = entries * 24, scrolls up to max(entries*24 - $78, 0)"},
        "controls": {"up/down (held)": "scroll", "Start": exit_note},
    }
    P["team_roster"] = {
        "handler": 0x89AC, "line": 31609, "setup": {"routine": "sub_9BD8", "d0": 0xD, "d1": 0x17},
        "static": [
            inline(rom, 0x89C8, "print", "window (7,1): box", 31618),
            {"op": "framer", "at": [7, 1], "w": 0x1A, "h": 6, "attr": 0x8000},
            inline(rom, 0x89DE, "print", "big title", 31624),
            {"op": "plate", "team": "shown", "at": [14, 1]},
            inline(rom, 0x8A0A, "print2", "headers and 'A - Switch Teams'", 31639),
            inline(rom, 0x8A44, "print", "line box (1,8)", 31660),
            {"op": "framer", "at": [1, 8], "w": 0x12, "h": 3, "attr": 0x8000},
            inline(rom, 0x8A5A, "print", "attribute box (21,8)", 31660),
            {"op": "framer", "at": [21, 8], "w": 0x12, "h": 3, "attr": 0x8000},
            inline(rom, 0x8BAC, "print2", "line name at (2,9), font 1, attr $E000", 31795),
            inline(rom, 0x8BD0, "print2", "attribute name at (22,9)", 31812),
        ],
        "line_names": string_list(rom, 0x8CBE, 8, "print2"),
        "skater_columns": attrib_columns(rom, 0x193F8),
        "goalie_columns": attrib_columns(rom, 0x1955A),
        "status": string_list(rom, 0x8DEC, 6),
        "handed": string_list(rom, 0x8E7A, 2),
        "positions": "RAM line slots LD RD LW C RW (G for the goalie line), from the line-name order",
        "value_formats": {"status": "tmpdst: -1 Ice, -2 Bench, -3 Injury P, -4 Injury G; >= 0 in the box: "
                                    "m:ss of bits 0-11, 'Injury G' if bit 12, ' C  ' if bit 14",
                          "energy": "energy / $28, at most 100", "weight": "value * 8 + $8C, ' lb  '",
                          "rating": "CalcAttrib (L966171) + AttribAdjust (L975195)", "handed": "Righty / Lefty"},
        "scroll": {"vscroll_b": "$FF90 + d5ae", "line_px": 0x80, "step_px": 2, "range": "0..$380"},
        "controls": {"up/down": "previous / next line (scrolls $80 px)", "left/right": "attribute column",
                     "A": "switch teams", "Start": exit_note},
    }
    P["other_scores"] = {
        "handler": 0x80D4, "line": 30583, "setup": {"routine": "sub_9BD8", "d0": 6, "d1": 0x1A},
        "static": [
            inline(rom, 0x80E2, "print", "window (5,0): box", 30586),
            {"op": "framer", "at": [5, 0], "w": 0x1E, "h": 6, "attr": 0x8000},
            inline(rom, 0x80F8, "print", "big 'Scores' at (14,3), then the cursor to (11,1)", 30598),
            {"op": "image", "name": "hockey_night", "at": [11, 1], "palette": "none (d5 = 0)", "line": 30623},
            inline(rom, 0x812C, "print2", "list origin plane B (4,0)", 30624),
        ],
        "period_labels": string_list(rom, 0x191E4, 5, "print2"),
        "arrows": string_list(rom, 0x82BC, 3, "print2"),
        "layout": {"plane": "B", "game_rows": 3, "team_x": 6, "team": "city", "score_x": 0x18, "score_width": 2,
                   "period_x": 0x1C, "period": "unk_191E4[gsper - 1] (1st 2nd 3rd OT F)",
                   "order": "team 2 (+2, score +$C) on the first row, team 1 (+0, score +$A) on the second"},
        "data": "gsstruct $FFCE66, 16 bytes a series (rules_clock_penalties.md 0.6), GetShifter() + 1 games; "
                "skips gamenum, flags bit 1 (held for a highlight) and bit 2 (series over)",
        "scroll": {"vscroll_b": "$FFD0 + d5ae", "step_px": 2, "game_px": 24, "max": "(rows - $15) * 8"},
        "controls": {"up/down (held)": "scroll", "Start": exit_note},
        "quirk": "the arrow table has 3 strings; index 3 (both arrows) would read the Edit Lines code at $82DA. "
                 "With 8 games the range is one 24 px step, so both arrows never show",
    }
    P["crowd_meter"] = {
        "handler": 0x9A2A, "line": 33980, "setup": {"routine": "sub_9BD8", "d0": 9, "d1": 0x1C},
        "static": [
            inline(rom, 0x9A38, "print", "window (6,1): box", 33983),
            {"op": "framer", "at": [6, 1], "w": 0x1C, "h": 6, "attr": 0x8000},
            inline(rom, 0x9A4C, "print", "big title", 33995),
            {"op": "plate", "team": "away", "at": [7, 1]}, {"op": "plate", "team": "home", "at": [22, 1]},
            inline(rom, 0x9A88, "print2", "row 1", 34032),
            inline(rom, 0x9AAA, "print2", "row 2", 34059),
            inline(rom, 0x9AD0, "print2", "row 3", 34072),
            inline(rom, 0x9B1E, "print2", "row 4 (only when ValidSRAM >= 0)", 34095),
            inline(rom, 0x9B7C, "print2", "row 5 (only when ValidSRAM >= 0)", 34128),
            inline(rom, 0x9BD0, "print", "unit after each value", 34161),
        ],
        "values": {"current": "sroot(CwdExciteLvl $FFB8A2 * 4) + $41",
                   "average": "sroot((SumCwdExciteLvl $FFB8A8 / NumCwdExciteLvl $FFB8A6) * 4) + $41",
                   "peak": "sroot(MaxCwdExciteLvl $FFB8A4 * 4) + $41",
                   "arena_record": "SRAM record of HomeTeam, byte 8 of the $FFCF36 block, $50 when 0",
                   "league_record": "the same for sub_FEC5E's team (league best), $50 when 0",
                   "width": 3, "x": 28, "row_step": 2, "first_row": 12},
        "controls": {"Start (new press)": "exit ($9CD8)"},
    }
    P["period_stats"] = {
        "handler": 0xFD90C, "line": 971034, "setup": {"routine": "sub_9BD8", "d0": 0, "d1": 0x1C},
        "static": [
            inline(rom, 0xFD924, "print", "logo box (1,11)", 971052),
            {"op": "framer", "at": [1, 11], "w": 8, "h": 8, "attr": 0x8000},
            inline(rom, 0xFD93E, "print", "logo box (1,19)", 971078),
            {"op": "framer", "at": [1, 19], "w": 8, "h": 8, "attr": 0x8000},
            inline(rom, 0xFD958, "print", "away logo at (2,12), attr $C000", 971104),
            {"op": "team_logo", "team": "away", "at": [2, 12], "line": "map 1 ^ 2 = 3 (the away line is "
             "copied from 2 to 3 after loading, L971172)"},
            inline(rom, 0xFD9B2, "print", "home logo at (2,20), attr $E000", 971194),
            {"op": "team_logo", "team": "home", "at": [2, 20], "line": "map 1 ^ 3 = 2"},
            inline(rom, 0xFD9F6, "print", "window (4,1): box", 971262),
            {"op": "framer", "at": [4, 1], "w": 0x20, "h": 6, "attr": 0x8000},
            inline(rom, 0xFDA0C, "print", "big title", 971284),
        ],
        "headers_with_ot": [inline(rom, 0xFDA34, "print", "byte_FFC2FC bit 1 set"), inline(rom, 0xFDA56, "print")],
        "headers": [inline(rom, 0xFDA7C, "print"), inline(rom, 0xFDA98, "print")],
        "mode_goals": inline(rom, 0xFDB3C, "print", "d598 = 0"),
        "mode_shots": inline(rom, 0xFDB1C, "print", "d598 = -1"),
        "layout": {"plane": "B", "away_row": 14, "home_row": 22, "columns_x": [0xB, 0x10, 0x15, 0x1A],
                   "total_x": 0x21, "width": "2, or 3 when >= 100", "fields": {"goals": 0x342, "shots": 0x34A},
                   "periods": "printed while gsp > column; OT only when byte_FFC2FC bit 1"},
        "port": {"0x342": "period_goals[gsp]", "0x34A": "period_shots[gsp]"},
        "controls": {"right": "shots", "left": "goals", "Start (new press)": "exit"},
    }
    P["edit_lines"] = {
        "handler": 0x82DA, "line": 30809, "setup": {"routine": "sub_9BD8", "d0": 0, "d1": 0x1C,
                                                     "note": "sets the team's $30 bit 0 (line menu redraw) first"},
        "static": [
            inline(rom, 0x8706, "print", "header (sub_86F8 L31199): window redrawn with stats_bg", 31201),
            inline(rom, 0x8738, "print", "plane B (7,1) box", 31221),
            {"op": "framer", "at": [7, 1], "w": 0x1A, "h": 6, "attr": 0x8000},
            inline(rom, 0x874E, "print", "big title", 31227),
            {"op": "plate", "team": "editing", "at": [14, 1]},
            inline(rom, 0x85A6, "print2", "name box (8,7)", 31096),
            {"op": "framer", "at": [8, 7], "w": 0x18, "h": 3, "attr": 0xC000},
            inline(rom, 0x85C0, "print2", "selected player centred on x 21, row 8", 31103),
            inline(rom, 0x8692, "print2", "position labels (sub_868C)", 31174),
            inline(rom, 0x86D4, "print2", "LD RD LW C RW at x 1, rows 14-22 (from $879E/$87A0, or $8798)", 31187),
            inline(rom, 0x8626, "print2", "' Line' after each line name", 31141),
        ],
        "line_names": string_list(rom, 0x191A6, 7, "print2"),
        "columns": {"address": 0x879E, "entries": [[rom.u16(0x879E + 6 * k), rom.u16(0x87A0 + 6 * k),
                                                    rom.u16(0x87A2 + 6 * k)] for k in range(7)],
                    "note": "per line (Sc1 Sc2 Chk PP1 PP2 PK1 PK2): x, y of the header, slots - 1; "
                            "with OptLine != 0 the table starts one entry earlier ($8798)"},
        "pages": {"address": 0x85E6, "bytes": list(rom.b[0x85E6:0x85EE]),
                  "note": "bit mask of the lines shown, indexed by (d5b8 >> 3) [- 1 with OptLine]: Sc1+Sc2+Chk, "
                          "PP1+PP2, PK1+PK2"},
        "cursor_moves": {"address": 0x87CA, "bytes": list(rom.b[0x87CA:0x87E2]),
                         "note": "d5b8 = line * 8 + slot (1-based); up/down +-1, left/right +-8"},
        "select_player": {
            "static": [inline(rom, 0x83E4, "print2", "plane W (1,0) box", 30907),
                       {"op": "framer", "at": [1, 0], "w": 0x12, "h": 3},
                       inline(rom, 0x83FC, "print2", "(21,0) attribute box"),
                       {"op": "framer", "at": [21, 0], "w": 0x12, "h": 3},
                       inline(rom, 0x8412, "print2", "'{Select Player}'", 30915),
                       inline(rom, 0x84D4, "print", "attribute header at (22,1)", 30988),
                       inline(rom, 0x8528, "print2", "row blank + cursor", 31025)],
            "rows": "6 visible, from d5b0; name via getNameandAttrib (L32055); the cursor row in the "
                    "selected attribute (d7)",
            "controls": {"up/down": "player", "left/right": "attribute column (PAttribColumns)",
                         "C": "put him in the slot; if he is already on that line the two trade places (sub_8898)",
                         "Start": "back to the editor"}},
        "exit_menu": "menus.json line_editor_exit / line_editor_exit_nosave (Exit, Set Original lines, "
                     "Save Team Line, Load Team Line); C or Start chooses; Exit returns to the pause menu",
        "controls": {"up/down": "slot", "left/right": "line (+-8)", "C": "Select Player list",
                     "Start": "exit menu (sub_7E36 with the H40 box at (9,12))"},
    }
    P["change_goalie"] = {
        "handler": 0x9DE6, "line": 34315, "screen": "pause screen (H32 window over the side view)",
        "static": [inline(rom, 0x9DFA, "print", "box (4,12) w $18, h 3 + goalies", 34319),
                   inline(rom, 0x9EB0, "print", "row blank (22 spaces) at x 5", 34376),
                   inline(rom, 0x9ED8, "print", "row 0 at x 11", 34391)],
        "rows": "row 0 'no goalie' (x 11); row k (k >= 1): goalie k-1: number (2 BCD digits of the player record "
                "byte 0) at x 5, name (getname) at x 8; rows from y 13; attr $8000 on the cursor row, $A000 others",
        "cursor_start": "goalie word $26 + 1, 0 when pulled",
        "controls": {"up/down": "row (clamped)", "C or Start": "row 0: $26 = $FFFF (kept unless already pulled "
                     "by the CPU); row k: $26 = k-1; then SetPersonel", "after": "returns to the pause menu"},
    }
    P["timeout"] = {
        "handler": 0x9D7A, "line": 34285, "screen": "pause screen",
        "static": [inline(rom, 0x9D96, "print", "box (5,12) 22x6", 34289),
                   inline(rom, 0x9DA8, "print", "'Timeout' then the team city centred on x 17, row 15", 34294)],
        "effect": "menu table becomes unk_1988C (cursor and top - 1), team $30 bit 2, sub_13098 on both teams "
                  "(energy $1000), waitx($78), then the pause menu is redrawn",
    }
    P["player_cards"] = {
        "handler": 0xFA07E, "line": 965326,
        "requires": "ValidSRAM ($FFD458) >= 0, else the row does nothing",
        "setup": "own: H40, sub_F9FC0/sub_F9FEA (SRAM records into $FFCF36..), font 0 remap 05 23 41.., window = "
                 "cards_bg (palette lines 0, 2, 3), NHL shield at B (1,1) (line 3 palette), NHLPA at B (33,1)",
        "static": [inline(rom, 0xFA102, "print", "window (0,0)", 965355),
                   {"op": "image", "name": "cards_bg", "at": [0, 0]},
                   inline(rom, 0xFA160, "print", "plane B (1,1)", 965383),
                   {"op": "image", "name": "logo_nhl", "at": [1, 1]},
                   inline(rom, 0xFA18C, "print", "plane B (33,1)", 965397),
                   {"op": "image", "name": "logo_nhlpa", "at": [33, 1]}],
        "strings": [inline(rom, a, "print2") for a in (0xFA430, 0xFA44A, 0xFA472, 0xFA48E, 0xFA8C0, 0xFA8D8,
                                                         0xFA978, 0xFAB9E, 0xFABB2, 0xFABC6, 0xFABF0, 0xFAC04,
                                                         0xFAD24, 0xFAD5A, 0xFADBC, 0xFADEC)],
        "cards": "index 0 = the team card (team name, Team Rating, Records, Starting Line G LD RD LW C RW), "
                 "then one card a player: photo (6x6 at B (1,8), line 2 = photo palette), number and "
                 "' Goalie' / ' Forward' / ' Defenseman', Overall Rating, Records (season, from SRAM), "
                 "This Game (Goals/Assists or Saves/Save %); team logo 6x6 at B (33,8) (line 1)",
        "team_rating": {"address": 0xFE18E, "routine": "sub_FE172 (L973164): byte table by team number",
                        "values": list(rom.b[0xFE18E:0xFE18E + 28])},
        "controls": {"left/right": "previous / next card (wraps)", "C": "next card", "A": "other team",
                     "Start": "exit ($9CD8)"},
    }
    P["record_holders"] = {
        "handler": 0xFBC14, "line": 967908, "setup": {"routine": "sub_9BD8", "d0": 0, "d1": 0x1A},
        "static": [inline(rom, 0xFBC28, "print", "plane B (1,1)"), {"op": "image", "name": "logo_nhl", "at": [1, 1]},
                   inline(rom, 0xFBC54, "print", "plane B (33,1)"), {"op": "image", "name": "logo_nhlpa", "at": [33, 1]},
                   inline(rom, 0xFBC80, "print", "window (11,1) box"),
                   {"op": "framer", "at": [11, 1], "w": 0x12, "h": 7, "attr": 0x8000},
                   inline(rom, 0xFBC9A, "print", "big 'Record' / 'Holders'"),
                   inline(rom, 0xFBCB8, "print2", "'Name' header")],
        "pages": [{"address": a, "ops": decode(rom, a, "print2")[1]} for a in (0xFBDB2, 0xFBE04, 0xFBE54)],
        "data": "SRAM user records (win %, most goals, most saves); A+C on page 0 clears the win records "
                "(sub_FE6D2)",
        "controls": {"left/right": "page 0..2", "A+C (page 0)": "clear ALL win records", "Start": "exit"},
    }
    P["shootout_setup"] = {
        "handler": 0xFC620, "line": 968926, "setup": {"routine": "sub_9BD8", "d0": 0, "d1": 0x1C},
        "static": [inline(rom, 0xFC9C6, "print", "plane B (7,1) box"),
                   {"op": "framer", "at": [7, 1], "w": 0x1A, "h": 6, "attr": 0x8000},
                   inline(rom, 0xFC9DC, "print", "big title"),
                   inline(rom, 0xFCA46, "print2", "'Shooters'"),
                   inline(rom, 0xFCA5A, "print2"), inline(rom, 0xFCA6A, "print2"), inline(rom, 0xFCA7A, "print2"),
                   inline(rom, 0xFCA8A, "print2"), inline(rom, 0xFCA9A, "print2"),
                   inline(rom, 0xFCAAA, "print2", "'Goalie'"),
                   inline(rom, 0xFCABE, "print2", "name box (8,7)"),
                   inline(rom, 0xFC77A, "print2", "'{Select Player}' (list mode)")],
        "controls": {"up/down": "shooter 1-5 / goalie", "C": "Select Player list (as Edit Lines)",
                     "Start": "back to the intermission menu"},
    }
    P["instant_replay"] = {
        "handler": 0x9FD0, "line": 34505, "describe_only": True,
        "panel": "sub_A448 (L34848): replay_panel_idx.png at window (2,2) for $F0 frames, then erased (sub_A48A)",
        "controls": "docs/specs/ui_menus.md section 14: C play/stop, A rewind, B slow forward, d-pad picks the "
                    "camera target, Start opens the prompt (Start back to play, B pause menu, C reverse angle)",
    }
    return {"source": "lst/nhl94.bin (CRC32 %08X); docs/specs/ui_menus.md" % ROM_CRC,
            "screen": {"stats": [40, 28], "pause": [32, 28]},
            "assets": {"in_game": "res://assets/ui/ (ui_overlay.py): font_idx.png (pause menu text), "
                                  "bigfont_idx.png (printbig on every page), framer_idx.png (pause boxes), "
                                  "team_plates_idx.png (sub_8078 plates, 11x2 cells)",
                       "fonts": {"0": "font_stats_idx.png", "1": "font_stats_alt_idx.png"}},
            "attr_lines": {"0x8000": "line 0 cyan ($EE2)", "0xA000": "line 1 white ($CCC)",
                           "0xC000": "line 2 yellow ($0EE)", "0xE000": "line 3 green ($0E0)"},
            "teams": teams, "pages": P}


# --- preview -----------------------------------------------------------------------------

def rgb(cw):
    return (((cw >> 1) & 7) * 36, ((cw >> 5) & 7) * 36, ((cw >> 9) & 7) * 36)


class Screen:
    def __init__(self, w=320, h=224):
        self.w, self.h = w, h
        self.idx = [[(0, 0)] * w for _ in range(h)]

    def blit(self, canvas, x0, y0, sx=0, sy=0, w=None, h=None, line=None, add=0):
        w = w or canvas.w
        h = h or canvas.h
        for y in range(h):
            for x in range(w):
                o = ((sy + y) * canvas.w + sx + x) * 4
                if canvas.px[o + 3]:
                    X, Y = x0 + x, y0 + y
                    if 0 <= X < self.w and 0 <= Y < self.h:
                        ln = (canvas.px[o + 1] // 85 + add) & 3 if line is None else line
                        self.idx[Y][X] = (canvas.px[o] // 17, ln)

    def save(self, path, cram):
        raw = bytearray()
        for y in range(self.h):
            for x in range(self.w):
                i, ln = self.idx[y][x]
                raw += bytes(rgb(cram[ln][i]))
        rgba = bytearray()
        for k in range(0, len(raw), 3):
            rgba += raw[k:k + 3] + b"\xff"
        png(path, self.w, self.h, rgba)


def preview(rom, out, assets, pg):
    """Static previews from the exported data (fonts, frames, big titles, labels)."""
    os.makedirs(out, exist_ok=True)
    stats_pal = assets["stats_bg_jim"].pal
    font0, font1, chars = assets["font0"], assets["font1"], assets["chars"]
    framer_c = assets["framer_stats"]
    bj = Jim(rom, BIGFONT, remap(Jim(rom, BIGFONT).tiles, bytes.fromhex("7123456789ABCDEF")))
    plates = Jim(rom, 0xABA14)

    def big(scr, x, y, s, attr):
        """printbig (L45806) / sub_11E8E: (c - $20) -> signed map column, negative = 1 cell."""
        for ch in s.upper():
            v = rom.s8(BIG_CHARTAB + ord(ch) - 0x20)
            w, col = (1, -v) if v < 0 else (2, v)
            for k in range(w):
                for half in range(2):
                    cv = bj.cells[half * bj.w + col + k]
                    c = Canvas(8, 8)
                    draw_cells(c, bj.tiles, [cv], 1, 1, 1)
                    scr.blit(c, (x + k) * 8, (y + half) * 8, add=(attr >> 13) & 3)
            x += w
        return x

    def plate(scr, team, x, y):
        c = Canvas(88, 16)
        draw_cells(c, plates.tiles, plates.cells, 11, 2, 11, row0=2 * team)
        scr.blit(c, x * 8, y * 8)

    def text(scr, x, y, s, attr, font):
        for ch in s:
            t = chars.get(str(ord(ch)), 0)
            if ch == "^":
                x += 1
                continue
            scr.blit(font, x * 8, y * 8, (t % 16) * 8, (t // 16) * 8, 8, 8, line=(attr >> 13) & 3)
            x += 1
        return x

    def run(scr, ops, flavour, cur):
        for op in ops:
            if "at" in op:
                cur["x"], cur["y"] = op["at"]
                cur["attr"] = op["attr"]
            for k in ("x", "y"):
                if k in op:
                    cur[k] = op[k]
            if "dx" in op:
                cur["x"] += op["dx"]
            if "dy" in op:
                cur["y"] += op["dy"]
            if "attr" in op and "at" not in op:
                cur["attr"] = op["attr"]
            if "font" in op:
                cur["font"] = op["font"]
            if "text" in op:
                if flavour == "printbig":
                    cur["x"] = big(scr, cur["x"], cur["y"], op["text"], cur["attr"])
                else:
                    cur["x"] = text(scr, cur["x"], cur["y"], op["text"], cur["attr"], font1 if cur["font"] else font0)

    for name, p in pg["pages"].items():
        if "static" not in p or name in ("change_goalie", "timeout", "player_cards"):
            continue
        scr = Screen()
        scr.blit(assets["stats_bg"], 0, 0)
        cur = {"x": 0, "y": 0, "attr": 0x8000, "font": 0}
        for op in p["static"]:
            kind = op.get("kind")
            if kind:
                run(scr, op["ops"], kind, cur)
            elif op.get("op") == "framer":
                x0, y0 = op["at"]
                w, h = op["w"], op["h"]
                for y in range(h):
                    for x in range(w):
                        i = (0 if y == 0 else (6 if y == h - 1 else 3)) + (0 if x == 0 else (2 if x == w - 1 else 1))
                        scr.blit(framer_c, (x0 + x) * 8, (y0 + y) * 8, (i % 3) * 8, (i // 3) * 8, 8, 8,
                                 add=(op.get("attr", 0x8000) >> 13) & 3)
            elif op.get("op") == "plate":
                plate(scr, {"away": 10, "home": 11}.get(op["team"], 11), op["at"][0], op["at"][1])
            elif op.get("op") == "image" and op["name"] in assets:
                scr.blit(assets[op["name"]], op["at"][0] * 8, op["at"][1] * 8)
        scr.save(os.path.join(out, "%s.png" % name), stats_pal)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    prev = None
    if "--preview" in sys.argv:
        prev = sys.argv[sys.argv.index("--preview") + 1]
        args = [a for a in args if a != prev]
    rom_path = args[0] if args else "lst/nhl94.bin"
    out = args[1] if len(args) > 1 else "godot/assets/ui/menus"
    with open(rom_path, "rb") as f:
        data = f.read()
    assert zlib.crc32(data) & 0xFFFFFFFF == ROM_CRC, "unexpected ROM"
    rom = R(data)
    os.makedirs(out, exist_ok=True)

    def dump(name, obj):
        with open(os.path.join(out, name), "w") as f:
            json.dump(obj, f, indent=1, sort_keys=True)

    m = menus(rom)
    dump("menus.json", m)
    pg = pages(rom)
    dump("pages.json", pg)

    assets = {}
    raw, chars = font_sheets(rom)
    assets["chars"] = chars
    for name, table in (("font_stats", None), ("font_stats_alt", REMAP_STATS_ALT), ("font_cards", REMAP_CARDS_FONT)):
        c = sheet(remap(raw, table) if table else raw)
        c.save(os.path.join(out, name + "_idx.png"))
        assets[{"font_stats": "font0", "font_stats_alt": "font1", "font_cards": "font_cards"}[name]] = c
    dump("font.json", {"source": "font $AAC52 (94 tiles), glyph map 32x4", "per_row": 16, "chars": chars,
                       "sheets": {"font_stats_idx.png": "raw (colour 0 transparent): font 0 of the stats pages",
                                  "font_stats_alt_idx.png": "remap D1 23 45 67 89 AB CD EF: font 1 (colour 0 -> 13)",
                                  "font_cards_idx.png": "remap 05 23 41 67 89 AB CD EF: Player Cards"},
                       "special": {"{": "up arrow", "}": "down arrow", "[": "left arrow", "]": "right arrow",
                                   "<": "underline", "\u0012": "ST", "\u0013": "ND", "\u0014": "RD",
                                   "@": "blank tile $7FF", "^": "skip a column"}})
    c, j = framer(rom, REMAP_FRAMER_STATS)
    c.save(os.path.join(out, "framer_stats_idx.png"))
    assets["framer_stats"] = c
    bg, jbg = image(rom, STATS_BG, opaque=True)
    bg.save(os.path.join(out, "stats_bg_idx.png"))
    assets["stats_bg"], assets["stats_bg_jim"] = bg, jbg
    cb, jcb = image(rom, CARDS_BG, opaque=True)
    cb.save(os.path.join(out, "cards_bg_idx.png"))
    hn, jhn = image(rom, HOCKEY_NIGHT)
    hn.save(os.path.join(out, "hockey_night_idx.png"))
    assets["hockey_night"] = hn
    nhl, jnhl = image(rom, LOGO_NHL)
    nhl.save(os.path.join(out, "logo_nhl_idx.png"))
    nhlpa, jnhlpa = image(rom, LOGO_NHLPA)
    nhlpa.save(os.path.join(out, "logo_nhlpa_idx.png"))
    tl, tpals = team_logos(rom)
    tl.save(os.path.join(out, "team_logos_idx.png"))
    ph, order, pteams, pbase = photos(rom)
    ph.save(os.path.join(out, "photos_idx.png"))
    dump("photos.json", {"source": "sub_FAE26 (L966584) lists at $F92F4, photos 3 bpp (sub_FE98A L974538), "
                                   "map and palette of $C63F8",
                         "per_row": 16, "size": [48, 48], "count": len(order),
                         "addresses": order,
                         "generic": {"0": "$C682E", "1": "$C6B98", "2": "$C6F02", "3": "$C726C",
                                     "rule": "no entry for the slot: slot < goalie count -> $C6F02 if the player "
                                             "record byte 4 bit 0 else $C726C; otherwise $C6B98 if bit 0 else $C682E"},
                         "teams": pteams})
    replay_panel(rom).save(os.path.join(out, "replay_panel_idx.png"))
    rp, _ = image(rom, REPLAY_PROMPT)
    rp.save(os.path.join(out, "replay_prompt_idx.png"))
    dump("palettes.json", {
        "source": "CRAM words (0BBB0GGG0RRR0)",
        "stats": jbg.pal,
        "stats_note": "sub_9BD8 loads lines 0, 2, 3 (mask $D); line 1 keeps the in-game line 1 (equal to $54E24 "
                      "line 1 except colour 0)",
        "cards": {"line0": jcb.pal[0], "line1": "team_logos[team] (sub_FA66E, mask 2)",
                  "line2": "photo (when a photo is up) else cards_bg line 2", "line3": jnhl.pal[3],
                  "cards_bg": jcb.pal},
        "team_logos": tpals,
        "photo": pbase.pal[1],
        "logo_nhl": jnhl.pal, "logo_nhlpa": jnhlpa.pal,
        "pause": "palettes.json (assets root): side lines 0-1, home team line 2, away team line 3",
    })
    if prev:
        preview(rom, prev, assets, pg)
    print("wrote %d menu tables, %d pages, %d photos, fonts, frames, backgrounds and logos to %s"
          % (len(m["tables"]), len(pg["pages"]), len(order), out))


if __name__ == "__main__":
    main()
