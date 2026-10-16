#!/usr/bin/env python3
"""Export NHL '94's playoff mode data, the battery-save (SRAM) record formats and the
reverse-angle replay table for the Godot port.

Offline only. The game never reads the ROM; it loads what this writes under
godot/assets/ui/playoffs/. Usage:
  python3 tools/extract/playoffs.py [lst/nhl94.bin] [godot/assets/ui/playoffs] [--preview DIR]
Spec: docs/specs/playoffs_records.md.

Writes (index textures as in assets.py: R = colour index * 17, G = palette line * 85,
A = 255 where drawn, colour 0 transparent):
  playoffs.json         the 32 seedings ($5576, NewPO L54902), the PlayoffScreen layout table
                        (unk_1928E, L53953) per gamelevel 0..4 (plates, bracket strips,
                        series-score spots), its round labels (unk_176DE), page text, scroll
                        and sprite constants, the CRAM lines it builds, the ticker headings
                        (unk_13488), the highlight caption, the setup menu's Play Mode and
                        Players strings, FigureJoy's pad tables (_pojoylist, _pojoylist2,
                        _noplist), the playoff save-state radices (sub_18192 / sub_1803E),
                        the packed playoff-stat bit widths (unk_18336, AddPOStats) and
                        the menu tables that differ in playoffs
  records.json          the SRAM map (byte offsets in the 8 KB battery RAM) and the record
                        formats: player best games, team records, user records, user names,
                        the $FFD076 block, the checksum; the per-team roster offsets
                        (unk_F9CA4); every record string (Player Cards, Record Holders, the
                        setup-screen card, the Crowd Meter) with the layout columns
  replay_reverse.json   revframetbl ($F600E, 846 words) and the other reverse-angle rules
                        (SetRCords L35038, sub_A528 L34928, sub_A88C L35209)
  cup_idx.png           the Stanley Cup sprite (unk_F3098: 1 frame, 10 pieces, 64x152, line 0)
  bracket_idx.png       the bracket connector strips (unk_B3640: 12x23 cells, map line 1);
                        strip k = columns 2k, 2k+1
The cup's palette is CRAM line 0 of the PlayoffScreen (playoffs.json "cram"); the stats
background is ui/menus/stats_bg_idx.png and the plates are ui/team_plates_idx.png.

With --preview DIR it also writes a 1024x224 RGB render of plane A for each gamelevel
(plates, strips, labels; a fixed sample seeding, the cup at the centre) for checking.
The output is deterministic (fixed key order, no timestamps).
"""
import json
import os
import sys
import zlib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from assets import ROM_CRC, BytesRom, Canvas, Rom  # noqa: E402

SEEDINGS = 0x5576          # NewPO (L54908): 32 x 16 team bytes
PO_LAYOUT = 0x1928E        # PlayoffScreen (L53953): word offsets by gamelevel 0..4
PO_LABELS = 0x176DE        # unk_176DE (L54001): "Playoffs" .. "Champions"
PO_PAGE_TEXT = 0x174F0     # printz after tst gamelevel (L54010): "Press [ or ] to page"
TICKER_HEADS = 0x13488     # unk_13488 (L48032)
PERIOD_LABELS = 0x191E4    # unk_191E4: "1ST" "2ND" "3RD" "OT" " F"
HIGHLIGHT_TEXT = 0x13590   # sub_1354C (L48198): "Highlight from game:"
CUP = 0xF3098              # cup sprite file: palette, frame table, tiles (+8)
BRACKET = 0xB3640          # dobitmap image (no palette) for sub_17626 (L54127)
STATS_BG = 0x54E24         # PlayoffScreen's background (and every stats page's)
POJOY = 0x17F52            # _pojoylist (L55091), 8 x {cont1team, cont2team}
POJOY4 = 0x17F72           # _pojoylist2 (L55108), four-way
NOPLIST = 0x17FE6          # _noplist (L55157), 7 x {cont1team, cont2team}
SETUP_STRINGS = 0xF7D04    # word offsets per menu row (GameSetUp_4 L961003)
STAT_WIDTHS = 0x18336      # unk_18336 (L55500): 4 bit widths
ROSTER_BASE = 0xF9CA4      # unk_F9CA4 (sub_F9B94 L964849): 29 words
REVFRAME = 0xF600E         # revframetbl (L957106), 846 words
TEAMS = 0x30E


class R(Rom):
    def bytes_(self, a, n):
        return self.b[a:a + n]


def plain(rom, a):
    """A length-prefixed string (word length including itself), trailing zeros dropped."""
    n = rom.u16(a)
    s = rom.b[a + 2:a + n]
    return s.rstrip(b"\0").decode("latin-1")


def ptext(rom, a):
    """The text of an inline printz string (L45500): a byte >= $80 starts a 3-byte position
    command, 0 is padding."""
    n = rom.u16(a)
    b = rom.b[a + 2:a + n]
    out, i = [], 0
    while i < len(b):
        if b[i] >= 0x80:
            i += 3
            continue
        if b[i]:
            out.append(chr(b[i]))
        i += 1
    return "".join(out)


def chain(rom, a, count):
    out = []
    for _ in range(count):
        out.append(plain(rom, a))
        a += rom.u16(a)
    return out


def team_abbr(rom):
    out = []
    for t in range(28):
        p = rom.u32(TEAMS + 4 * t)
        a = p + rom.u16(p + 4)
        city = plain(rom, a)
        a += rom.u16(a)
        out.append({"city": city, "abbr": plain(rom, a)})
    return out


def layout(rom):
    levels = []
    for lv in range(5):
        a = PO_LAYOUT + rom.u16(PO_LAYOUT + 2 * lv)
        n = rom.u8(a) + 1
        a += 1
        plates = [[rom.u8(a + 2 * i), rom.u8(a + 2 * i + 1)] for i in range(n)]
        a += 2 * n
        n = rom.u8(a) + 1
        a += 1
        strips = [{"x": rom.u8(a + 2 * i), "src_col": rom.u8(a + 2 * i + 1)} for i in range(n)]
        a += 2 * n
        n = rom.u8(a)
        a += 1
        scores = []
        if n < 0x80:
            scores = [[rom.u8(a + 2 * i), rom.u8(a + 2 * i + 1)] for i in range(n + 1)]
        levels.append({"gamelevel": lv, "plates": plates, "strips": strips, "series_scores": scores})
    return levels


def cram_line(rom, base, k):
    p = base + rom.u32(base)
    return [rom.u16(p + 32 * k + 2 * i) for i in range(16)]


def cup_sprite(rom):
    ft = CUP + rom.u32(CUP + 4)
    count = rom.u16(CUP + 8) & 0x7FFF
    tiles = BytesRom(rom.b[CUP + 10:CUP + 10 + 32 * count])
    a0, a1 = ft + rom.u16(ft + 2), ft + rom.u16(ft + 4)
    pieces = []
    for a in range(a0, a1, 8):
        w6 = rom.u16(a + 6)
        size = w6 & 0xFF
        pieces.append({"x": rom.s16(a), "y": rom.s16(a + 2), "tile": rom.u16(a + 4),
                       "w": ((size >> 2) & 3) + 1, "h": (size & 3) + 1,
                       "hf": bool(w6 & 0x800), "vf": bool(w6 & 0x1000), "pal": (w6 >> 13) & 3})
    x0 = min(p["x"] for p in pieces)
    y0 = min(p["y"] for p in pieces)
    w = max(p["x"] + 8 * p["w"] for p in pieces) - x0
    h = max(p["y"] + 8 * p["h"] for p in pieces) - y0
    c = Canvas(w, h)
    # VDP link order: the first piece is in front, so fill only empty pixels in order.
    for p in pieces:
        for col in range(p["w"]):
            for row in range(p["h"]):
                t = p["tile"] + col * p["h"] + row
                dc = p["w"] - 1 - col if p["hf"] else col
                dr = p["h"] - 1 - row if p["vf"] else row
                c.tile(tiles, 32 * t, p["x"] - x0 + 8 * dc, p["y"] - y0 + 8 * dr, p["pal"],
                       p["hf"], p["vf"], only_empty=True)
    return c, {"file": "cup_idx.png", "size": [w, h], "origin": [x0, y0], "pieces": len(pieces),
               "tiles": count, "line": 0, "priority": True,
               "screen_px": [0x100 - 128, 0xA0 - 128],
               "note": "sub_FED2A (L974956) draws frame 1 every frame with SetSframe at sprite "
                       "x = word_FFB8AE, y = word_FFB8B0 ($A0): x = $100 + DispAttribCtr while "
                       "that is within $40..$200, else hidden (sub_17572)"}


def bracket(rom):
    mo = rom.u32(BRACKET + 4)
    n = rom.u16(BRACKET + 8)
    tiles = BytesRom(rom.b[BRACKET + 10:BRACKET + 10 + 32 * (n & 0x7FFF)])
    m = BRACKET + mo
    w, h = rom.u16(m), rom.u16(m + 2)
    cells = [rom.u16(m + 4 + 2 * i) for i in range(w * h)]
    c = Canvas(8 * w, 8 * h)
    for r in range(h):
        for k in range(w):
            v = cells[r * w + k]
            t = v & 0x7FF
            if t >= (n & 0x7FFF):
                continue
            c.tile(tiles, 32 * t, 8 * k, 8 * r, (v >> 13) & 3, bool(v & 0x800), bool(v & 0x1000))
    return c, {"file": "bracket_idx.png", "cells": [w, h], "line": 1, "tiles": n & 0x7FFF,
               "note": "sub_17626: dobitmap of columns src_col, src_col+1 (2 x 23 cells) to "
                       "plane A (x, 2); the cells carry their own flips; tiles loaded to ExtraChars"}


def seedings(rom, names):
    out = []
    for i in range(32):
        b = rom.b[SEEDINGS + 16 * i:SEEDINGS + 16 * i + 16]
        out.append({"teams": list(b), "abbr": [names[t]["abbr"] for t in b]})
    return out


def word_pairs(rom, a, n):
    return [[rom.u16(a + 4 * i), rom.u16(a + 4 * i + 2)] for i in range(n)]


def setup_rows(rom, row, count):
    a = SETUP_STRINGS + rom.s16(SETUP_STRINGS + row)
    return [s.rstrip() for s in chain(rom, a, count)]


def playoffs_json(rom, names):
    widths = [rom.u8(STAT_WIDTHS + i) for i in range(4)]
    po_text = ptext(rom, PO_PAGE_TEXT)
    return {
        "source": "lst/nhl94.bin (CRC32 %08X); docs/specs/playoffs_records.md" % ROM_CRC,
        "teams": names,
        "seedings": {
            "address": SEEDINGS, "line": 54908,
            "note": "NewPO: a seeding holding Opt1Team (All-Star teams 26/27 search as 25) is "
                    "picked by randomd0(32)+1 and stepping +1 (mod 32). Pairs (2k, 2k+1) meet in "
                    "round 1; 0-7 East, 8-15 West; the second of a pair has home ice",
            "list": seedings(rom, names)},
        "screen": {
            "routine": "PlayoffScreen", "line": 53890,
            "planes": {"A": "$E000, 128 x 32 cells (VDP reg 16 = $03): plates, strips, scores, round "
                            "label; horizontally scrolled",
                       "B": "$C000: stats background $54E24 (ui/menus/stats_bg_idx.png) at (0,0)",
                       "window": "rows 0-1 ($9202): the 'Press [ or ] to page' line"},
            "hscroll_A": "$FEA0 + DispAttribCtr (view starts at plane column 44 when 0)",
            "view_col0": 44,
            "page_step_px": 0x70,
            "scroll_px_per_frame": 2,
            "scroll_limit_px": "+-$70 * min(gamelevel, 3)",
            "pad": "right: DispAttribCtr -= 2 a frame until a multiple of $70; left: += 2; "
                   "Start (pad 1 or 2): exit",
            "cram": {"line0": cram_line(rom, CUP, 0), "line1": cram_line(rom, STATS_BG, 1),
                     "line2": cram_line(rom, STATS_BG, 1), "line3": cram_line(rom, STATS_BG, 0),
                     "flash": "sub_175D8: every 24 frames line 2 colour 1 ^= $0EE (the user's "
                              "plates; $CCC <-> $C22)"},
            "plate": {"image": "ui/team_plates_idx.png", "cells": [11, 2],
                      "line_other": 1, "line_user": 2,
                      "note": "sub_17652: plate of tree byte k at (x, y); a plate whose team is the "
                              "user's (tree[potreeteam]) is drawn with printa $6000 and lands in line 2"},
            "plate_order": "plate i shows tree byte i of $FFCEF4 (MakeTree): 0-15 seeds, 16-23 "
                           "round-1 winners, 24-27 QF winners, 28-29 SF winners, 30 champion",
            "series_score": "sub_175FC: '<+4>-<+6>' of gsstruct series i (first-listed team's wins "
                            "first) printed at the spot in attr $2000; skipped when bosgames == 7",
            "round_label": {"strings": chain(rom, PO_LABELS, 5), "plane": "A", "x_centre": 65, "y": 26,
                            "attr": "$2000 (printz2 amxy 1,1)", "index": "gamelevel"},
            "page_text": {"text": po_text, "plane": "window", "at": [10, 1], "attr": "$6000",
                          "when": "gamelevel != 0", "glyphs": "'[' and ']' are the arrow glyphs"},
            "song": 0x79,
            "levels": layout(rom)},
        "ticker": {
            "headings": chain(rom, TICKER_HEADS, 4),
            "index": "OptPlayMode ? 1 + gamelevel : 0 (gamelevel 3 has no other series)",
            "period_labels": chain(rom, PERIOD_LABELS, 5),
            "highlight_caption": ptext(rom, HIGHLIGHT_TEXT),
            "rows": "visitor (gsstruct +2, score +$C) first, then home (+0, score +$A)"},
        "setup_menu": {
            "play_mode": setup_rows(rom, 0, 5),
            "play_mode_note": "OptPlayMode 0 Regular Season, 1 Continue Playoffs (offered only when a "
                              "saved playoff exists), 2 New Playoffs (one game a round, bosgames = 7), "
                              "3 New Playoffs/7 game, 4 Shootout",
            "players": setup_rows(rom, 2, 12),
            "players_playoffs": "OptNOP 7 One, 6 Two - Teammates, 5 Two - Head to Head (2 pads); "
                                "pojoy = 7 - OptNOP (11 - OptNOP four-way)"},
        "figurejoy": {
            "pojoylist": word_pairs(rom, POJOY, 8),
            "pojoylist4": word_pairs(rom, POJOY4, 8),
            "noplist": word_pairs(rom, NOPLIST, 7),
            "note": "index = (user is team1 ? 0 : 4 (5 four-way)) + pojoy; {cont1team, cont2team}: "
                    "1 = home, 2 = away, 0 = none. _noplist by OptNOP outside playoffs"},
        "save_state": {
            "ram": "$FFD088, 5 words, one 80-bit big-endian integer",
            "encode": "sub_18192 (L55309): N = 0; for (value, radix) in order: N = N * radix + value",
            "order": [["postarts", 32], ["bosgames", 8], ["gamelevel", 4], ["potreeteam", 16],
                      ["pojoy", 8], ["bracket_bits $CEF2", 0x4000]] +
                     [["series %d wins +%d" % (s, o), 5] for s in range(8) for o in (4, 6)],
            "decode": "sub_1803E (L55206): reverse order, value = N mod radix, N /= radix; a series "
                      "with 4 wins gets flags bit 2 (series over); pojoy 1/2 become 4 with 2 pads"},
        "playoff_stats": {
            "ram": "$FFCD96 + 2*(26*category + slot): words, categories goals, assists, SOG, PIM "
                   "(team struct bytes $B4, $CE, $E8, $102)",
            "packed": "$FFD0DC..$FFD173 (inside the saved $FFD076 block): entry i = 0..103 in "
                      "order, width widths[(103 - i) & 3] bits, values clamped to 2^width - 1",
            "widths": widths,
            "entry_width_by_i_mod_4": [widths[3], widths[2], widths[1], widths[0]]},
        "menus": {
            "intermission_pregame_playoffs": "ui/menus/menus.json table of that name (adds Playoff Stats)",
            "intermission_final_playoffs": "the same rows as intermission_final"},
    }


def records_json(rom):
    roster = [rom.u16(ROSTER_BASE + 2 * i) for i in range(29)]
    strings = {
        "card_record": plain(rom, 0xF9950), "card_goals": plain(rom, 0xF995A),
        "card_goal": plain(rom, 0xF9962), "card_saves": plain(rom, 0xF996A),
        "card_save": plain(rom, 0xF9972), "card_by": plain(rom, 0xF9AA6), "card_vs": plain(rom, 0xF9ADE),
        "crowd_suffix": plain(rom, 0xFA6F6), "saves_": plain(rom, 0xFA734), "save_": plain(rom, 0xFA73E),
        "saves_by": plain(rom, 0xFA746), "save_by": plain(rom, 0xFA752), "goals_": plain(rom, 0xFA788),
        "goal_": plain(rom, 0xFA792), "goals_by": plain(rom, 0xFA79A), "goal_by": plain(rom, 0xFA7A6),
        "vs": plain(rom, 0xFA876), "holders_by": plain(rom, 0xFC128), "holders_vs": plain(rom, 0xFC12E)}
    return {
        "source": "lst/nhl94.bin (CRC32 %08X); docs/specs/playoffs_records.md" % ROM_CRC,
        "sram": {
            "size": 0x2000, "bus": "byte k at $200001 + 2k (odd bytes; WriteSRAM/ReadSRAM L61470/L61513)",
            "valid": "ValidateSRAM (L61391): byte $1FFF = sum of bytes 0..$1FFD (mod 256), byte $1FFE = "
                     "its complement; ValidSRAM ($FFD458) = 0 valid, $FF.. invalid",
            "boot": "InitSaveRAM (L61322): read 8 KB to $FF0000, validate; invalid -> ClearSRAM (zero, "
                    "$1FFE = $FF, byte 0 = 1, checksum) and validate again",
            "map": [
                {"at": 0x0000, "size": 4 * roster[28], "what": "player best games, 4 bytes, index "
                 "roster_base[team] + roster slot"},
                {"at": 0x0B60, "size": 16 * 28, "what": "team records, 16 bytes a team"},
                {"at": 0x0D20, "size": 16 * 8, "what": "user records, 16 bytes, users 0-7"},
                {"at": 0x0DA0, "size": 0x80, "what": "user names: RAM $FFD45A, 12 bytes a user at "
                 "12 * id (id 1-7; 0 = no name)"},
                {"at": 0x1EF6, "size": 0x100, "what": "RAM $FFD076..$FFD175 (saved line, playoff "
                 "state, packed playoff stats)"},
                {"at": 0x1FFE, "size": 2, "what": "checksum"}]},
        "roster_base": roster,
        "player_record": {"bytes": ["best (skater: goals in a game; goalie: saves = shots against "
                                    "- goals against)", "own user id", "opponent team",
                                    "opponent user id"],
                          "update": "sub_F9F50 (L965216): strictly greater replaces; any result"},
        "team_record": {"bytes": {"0": "most goals by the team in a game", "1": "own user",
                                  "2": "opponent team", "3": "opponent user",
                                  "4": "most saves by one of its goalies", "5": "own user",
                                  "6": "opponent team", "7": "opponent user",
                                  "8": "crowd record dB (home games only; 0 reads as $50)",
                                  "9": "own user", "10": "opponent team", "11": "opponent user",
                                  "12-15": "unused"},
                        "update": "sub_F9EAA (L965158): strictly greater replaces; any result"},
        "user_record": {"bytes": {"0": "most goals in a won game", "1": "own team", "2": "opponent team",
                                  "3": "opponent user", "4": "most saves (opponent shots - goals) in "
                                  "a won game", "5": "own team", "6": "opponent team",
                                  "7": "opponent user", "8-9": "wins (word)", "10-11": "games (word, "
                                  "stops at 9000)", "12-13": "ties (word)", "14-15": "unused"},
                        "update": "sub_F9DDA (L965084): games += 1 unless >= 9000, then wins or "
                                  "ties; goals/saves records only when the user's team won"},
        "strings": strings,
        "record_holders": {
            "rows": "plane B y = 10, 12 .. 22, x = 2: '<rank>. <name>'; users 1-7 sorted; a row "
                    "with no games (page 0) or a zero record (pages 1-2) prints blank",
            "page0": {"cols": {"win_pct": [19, 3], "wins": [26, 4], "losses": [31, 4], "ties": [36, 3]},
                      "sort": "win% = wins*100/games (0 without games) desc, then ties desc, then "
                              "games desc (bubble sort, sub_FC184)"},
            "page1": {"cols": {"goals": [18, 3], "teams": [25, None]},
                      "text": "'by <own abbr> vs. <opp abbr>'", "sort": "byte 0 desc (sub_FC282)"},
            "page2": {"cols": {"saves": [18, 3], "teams": [25, None]}, "sort": "byte 4 desc"},
            "clear": "A+C on page 0: sub_FE6D2 zeroes bytes 8-11 (wins, games) of the 8 user "
                     "records and writes them back; ties (12-13) are kept"},
        "player_cards": {
            "team_card": "Records: Goals (team +0), Saves (+4), ' dB Crowd Level' (+8)",
            "player_card": "Records: Goals (skater) or Saves (goalie) from the player record",
            "format": ["'<n> Goals by' ('Goal' when n = 1; no 'by' with user 0)", "'<own user> vs.'",
                       "'<opp user> <opp team abbr>'"],
            "empty": "nothing when the value is 0"},
        "crowd": {"arena_record": "LoadCrowdRec (L959665): team record +8 of HomeTeam, 0 -> $50",
                  "league_record": "sub_FEC5E (L974860): the largest team record +8 of the 28 teams "
                                   "(0 -> $50), first team from 27 down on ties"},
    }


def replay_json(rom):
    tbl = [rom.u16(REVFRAME + 2 * i) for i in range(846)]
    return {
        "source": "lst/nhl94.bin (CRC32 %08X); docs/specs/playoffs_records.md" % ROM_CRC,
        "flag": "byte $FFC2F4 bit 4 (word $1000): reverse angle on; bit 6: toggle request; bit 7: "
                "set by RevReplayAdj for the redraw call",
        "revframetbl": tbl,
        "frame_rule": "f' = revframetbl[f & $3FF]; keep f when f' < 1 or f' >= $34E",
        "flip_rule": "flips come from the record; in reverse, frames $162..$178 toggle h-flip",
        "position_rule": "x' = -x, y' = -y for all 16 objects; the 16th (index 15) gets y' + 2",
        "hide_rules": ["object SCnum $F with mapped frame != $18A: y = $FC00 (off screen)",
                       "mapped frames $28D..$291: y = $190"],
        "camera": "Hpos' = -Hpos, Vpos' = -Vpos, then clamped to -60..60 and -200..256 (sub_A88C)",
        "rink": "RevRinkTilelist / RevRinkTiles (rink/rink_reverse_*); the crowd sprites "
                "(showcrowd) and the arena animations (sub_FD78A) are not drawn",
        "toggle": "sub_A528: bchg bit 4; forceblack2; reload tiles (sub_9CDC); Oldrow = $7D0 "
                  "(full map redraw); setvideo twice at Hpos = Vpos = 0 and twice at the saved "
                  "camera; RevReplayAdj (re-apply the current record); redraw the button panel "
                  "(sub_A448); palcount = $64 (fade in)"}


def preview(rom, out, names, levels):
    """RGB render of plane A's used part (columns 0..127, rows 0..27) for each gamelevel with
    seeding 0 and every first-listed team winning: strips, plates, scores '0-0', no label
    font. For checking positions against the emulator."""
    from assets import decompress, png
    from ui_overlay import PLATES, blob, jim_map
    br, _ = bracket(rom)
    pl_tiles = BytesRom(blob(rom, PLATES))
    pw, ph, pcells = jim_map(rom, PLATES)
    cram = {0: cram_line(rom, CUP, 0), 1: cram_line(rom, STATS_BG, 1),
            2: cram_line(rom, STATS_BG, 1), 3: cram_line(rom, STATS_BG, 0)}
    seed = [rom.u8(SEEDINGS + i) for i in range(16)]
    tree = list(seed)
    for k in range(15):
        tree.append(tree[2 * k])
    for lv in levels:
        c = Canvas(1024, 224)
        for s in lv["strips"]:
            for y in range(23 * 8):
                for x in range(16):
                    o = (y * br.w + 8 * s["src_col"] + x) * 4
                    if br.px[o + 3]:
                        d = ((16 + y) * c.w + 8 * s["x"] + x) * 4
                        c.px[d:d + 4] = br.px[o:o + 4]
        for i, (x, y) in enumerate(lv["plates"]):
            t = tree[i]
            for r in range(2):
                for k in range(11):
                    v = pcells[(2 * t + r) * pw + k]
                    line = 2 if i == 1 else 1
                    c.tile(pl_tiles, 32 * (v & 0x7FF), 8 * (x + k), 8 * (y + r), line,
                           bool(v & 0x800), bool(v & 0x1000))
        rgb = bytearray()
        for y in range(224):
            for x in range(1024):
                o = (y * 1024 + x) * 4
                if c.px[o + 3]:
                    cw = cram[c.px[o + 1] // 85][c.px[o] // 17]
                else:
                    cw = cram[1][0]
                rgb += bytes((((cw >> 1) & 7) * 36, ((cw >> 5) & 7) * 36, ((cw >> 9) & 7) * 36, 255))
        png(os.path.join(out, "preview_level%d.png" % lv["gamelevel"]), 1024, 224, bytes(rgb))


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    prev = None
    if "--preview" in sys.argv:
        prev = sys.argv[sys.argv.index("--preview") + 1]
        args = [a for a in args if a != prev]
    rom_path = args[0] if args else "lst/nhl94.bin"
    out = args[1] if len(args) > 1 else "godot/assets/ui/playoffs"
    with open(rom_path, "rb") as f:
        data = f.read()
    assert zlib.crc32(data) & 0xFFFFFFFF == ROM_CRC, "unexpected ROM"
    rom = R(data)
    os.makedirs(out, exist_ok=True)

    def dump(name, obj):
        with open(os.path.join(out, name), "w") as f:
            json.dump(obj, f, indent=1, sort_keys=True)
            f.write("\n")

    names = team_abbr(rom)
    po = playoffs_json(rom, names)
    cup, cup_meta = cup_sprite(rom)
    cup.save(os.path.join(out, "cup_idx.png"))
    br, br_meta = bracket(rom)
    br.save(os.path.join(out, "bracket_idx.png"))
    po["screen"]["cup"] = cup_meta
    po["screen"]["bracket"] = br_meta
    dump("playoffs.json", po)
    dump("records.json", records_json(rom))
    dump("replay_reverse.json", replay_json(rom))
    if prev:
        os.makedirs(prev, exist_ok=True)
        preview(rom, prev, names, po["screen"]["levels"])


if __name__ == "__main__":
    main()
