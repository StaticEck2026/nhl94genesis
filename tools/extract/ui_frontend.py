#!/usr/bin/env python3
"""Export the NHL '94 front end (Game Setup menu, Matchups, playoff bracket strings) for the
Godot port.

Offline only. The game never reads the ROM; it loads what this writes under
godot/assets/ui/frontend/. Usage:
  python3 tools/extract/ui_frontend.py [lst/nhl94.bin] [godot/assets/ui/frontend] [--preview DIR]
Spec: docs/specs/ui_frontend.md. Art already exported elsewhere is not repeated:
  ../menus/team_logos_idx.png + palettes.json team_logos  the 6x6 team logos ($F86F2, $FF462)
  ../menus/photos_idx.png + photos.json                   the player photos ($C63F8, $F92F4)
  ../menus/stats_bg_idx.png + palettes.json stats          the SPORTS background ($54E24)
  ../menus/font_stats_idx.png + font.json                  the $AAC52 font, raw (Matchups font 0)
  ../bigfont_idx.png (ui_overlay.py)                       the printbig glyph sheet

Index textures as in assets.py / ui_menus.py: R = colour index * 17, G = palette line * 85,
A = 255 where drawn. Every image keeps the palette line of its own map words. Where the
game adds or XORs an attribute when drawing, frontend.json says so (Framer and printbig add
printa to the map word; dobitmap XORs printa & $F800 into it). Full-screen backgrounds are
opaque (colour 0 written as line 0 colour 0).

Writes:
  frontend.json                 flow, screens, layouts, every string and table (see the spec)
  setup_bg_idx.png              Game Setup background, plane B ($4B7A0, 40x28, line 0)
  setup_header_idx.png          the "<visitor> AT <home>" bar, plane A ($4DEEE, 40x4)
  setup_panel_idx.png           the option panel, plane A ($BEFB8, 38x13)
  setup_framer_idx.png          Framer 3x3 (framermap $55B7E) over the $BF54A tiles through
                                remap 03 56 75 64 89 AB CD EF (the cursor box)
  font_setup_idx.png            the alternate font $BE26A (labels and values), 16 tiles a row
  logo_frame_home_idx.png       8x8 logo frame $BF702 (raw: home, team colours 1-2)
  logo_frame_visitor_idx.png    the same through remap 03 41 45 67 89 AB CD EF (colours 3-4)
  team_plates_home_idx.png      team-name plates $AFE12 (11x2 cells a team, 28 teams), raw
  team_plates_visitor_idx.png   the same through remap 03 41 25 67 89 AB CD EF
  ron_barr_idx.png              Matchups portrait $B389C (8x9, line 3)
  matchups_title_idx.png        "MATCHUPS" in printbig ($A9A10 through 05 43 15 67 79 AB CD EF)
  font_matchups_alt_idx.png     $AAC5A through remap 0A 23 45 67 89 AB CD EF (font 1)
  framer_matchups_idx.png       Framer 3x3 over $55B86 through remap 05 42 25 61 89 AB CD EF
  hot_idx.png, cold_idx.png     the HOT ($F5AF6, 6x2) and COLD ($F5D1C, 6x3) badges

The run is deterministic. With --preview DIR it also composes the default Game Setup screen
(Los Angeles at Montreal) and the Matchups "Overall" page from the exported data, for
comparison with emulator screenshots.
"""
import json
import os
import sys
import zlib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from assets import ROM_CRC, Canvas  # noqa: E402
from ui_menus import (R, Jim, Screen, draw_cells, remap, sheet, image, plain, team_names,  # noqa: E402
                      FRAMER, FONT, BIGFONT, BIG_CHARTAB, STATS_BG, TEAM_LOGOS, LOGO_PALS)

# --- addresses ---------------------------------------------------------------------------
SETUP_BG = 0x4B7A0        # setoptions (L962234) dobitmap plane B, lines 0, 2, 3
SETUP_HEADER = 0x4DEEE    # plane A (0,0) 40x4, no palette
SETUP_PANEL = 0xBEFB8     # plane A (1,14) 38x13, no palette; also redrawn by sub_F76D4
SETUP_FRAMER_TILES = 0xBF542   # jim; setoptions loads its tiles ($BF54A) at framercset
SETUP_FONT = 0xBE26A      # word_FFBF52, the print2 alternate font (word_FFC2F8 bit 3)
LOGO_FRAME = 0xBF702      # sub_F8762..sub_F878C (L962751-962792), 8x8
PLATES = 0xAFE12          # sub_17B78 (L54625): 11 x 2 cells per team, row 2*team
TEAM_COLOURS = 0xF8BF4    # 64 bytes a team: two CRAM lines (sub_17AF4 L54595)
OPT_LABELS = 0xF80D4      # sub_F8070 (L962050), 9 print2 strings
OPT_VALUES = 0xF7D04      # GameSetUp_4 (L960985): 9 word offsets, then the lists
OPT_COUNTS = 0xF791E      # unk_F791E (L960750): values per row, 2-pad
OPT_COUNTS_4WAY = 0xF7930  # unk_F7930: the same with the 4 Way Play adapter
DEFMENUOPTIONS = 0x17C8E  # defmenuoptions (L54847)
NOPLIST = 0x17FE6         # _noplist (L55157): OptNOP -> cont1team, cont2team
POJOYLIST = 0x17F52       # _pojoylist (L55091, playoffs, 2 pads)
POJOYLIST2 = 0x17F72      # _pojoylist2 (L55108, playoffs, 4 Way Play)
BARR = 0xB389C            # sub_FCC76 (L969615): plane A (1,1), lines 2-3
HOT = 0xF5AF6             # sub_FF8DE (L976600) badge maps; tiles loaded from +8 at $F5AFE
COLD = 0xF5D1C
MESSAGES = 0x4B5C0        # unk_4B5C0 (L261838), read by sub_17730 (L54260): CR-separated commentary texts
CATEGORIES = 0xFCFFA      # sub_FD1FE: matchup page 0 label list (only entry 9 is printed)
POSITIONS = 0xFD400       # sub_FD1FE: pages 1-6 labels
POS_SLOTS = 0xFD4B8       # sub_FD492: page -> byte of the starting line (team record + 6)
ARROWS_HOME = 0xFD548     # sub_FD4CA: 6 pointers, home rating higher
ARROWS_VIS = 0xFD560      # visitor higher
ARROWS_EVEN = 0xFD5A8
HOME_VIS = 0xFD5E4        # sub_FD5AE: "Home" / "Visitors" for a team with no nickname
TEAM_RATING = 0xFE18E     # sub_FE172 (L973164)
TEAMS = 0x30E
PO_LABELS = 0x176DE       # unk_176DE (L54190), PlayoffScreen (L53888): heading by gamelevel
PO_PAGE = 0x174F0         # printz2 inline: $CD $0A $01 "Press [ or ] to page"

REMAP_SETUP_FRAMER = bytes.fromhex("0356756489ABCDEF")   # inline at $F81DC
REMAP_SETUP_FONT0 = bytes.fromhex("0FC0456789ABCDEF")    # inline at $F81F4 ($AAC5A, word_FFB012)
REMAP_FRAME_VIS = bytes.fromhex("034145 6789ABCDEF".replace(" ", ""))  # inline at $F82E0
REMAP_PLATES_VIS = bytes.fromhex("0341256789ABCDEF")     # inline at $F84EE
REMAP_MU_BIG = bytes.fromhex("05431567 79ABCDEF".replace(" ", ""))  # inline at $FCD00
REMAP_MU_FONT1 = bytes.fromhex("0A23456789ABCDEF")       # inline at $FCD1E
REMAP_MU_FRAMER = bytes.fromhex("05422561 89ABCDEF".replace(" ", ""))  # inline at $FCD36

ROW_RAM = ["OptPlayMode", "OptNOP", "Opt1Team", "Opt2Team", "OptPerLen", "OptGoalie", "OptUserRec",
           "OptPen", "OptLine"]


def pstr_list(rom, a, count):
    out = []
    for _ in range(count):
        n, t = plain(rom, a)
        out.append(t)
        a += n
    return out, a


def jim_pal(j):
    return [list(p) for p in j.pal]


def save(c, out, name):
    c.save(os.path.join(out, name))


def framer_canvas(rom, tiles):
    """Framer (L45261) 3x3: cell k = framermap[k] + printa + framercset (map words carry
    line 1). Drawn here with the map line; the caller adds the attribute line."""
    fm = Jim(rom, FRAMER)
    c = Canvas(24, 24)
    for i, v in enumerate(fm.cells):
        draw_cells(c, tiles, [v], 1, 1, 1, (i % 3) * 8, (i // 3) * 8)
    return c, fm.cells


def big_title(rom, text, tiles):
    """printbig (L45804): unk_1916A[c - $20] = signed byte v; v < 0: 1-cell glyph at map
    column -v, else 2 cells from column v; rows 0/1 of the 77x2 map of $A9A10."""
    mp = BIGFONT + rom.u32(BIGFONT + 4)
    w = rom.u16(mp)
    cells = [rom.u16(mp + 4 + 2 * i) for i in range(w * 2)]
    cols = []
    for ch in text.upper():
        v = rom.s8(BIG_CHARTAB + ord(ch) - 0x20)
        width, col = (1, -v) if v < 0 else (2, v)
        cols += [col + k for k in range(width)]
    c = Canvas(8 * len(cols), 16)
    for x, col in enumerate(cols):
        draw_cells(c, tiles, [cells[col], cells[w + col]], 1, 2, 1, 8 * x, 0)
    return c, len(cols)


def font_map(rom, base):
    gm = base + rom.u32(base + 4)
    return {str(c): rom.u16(gm + 4 + 2 * c) & 0x7FF for c in range(0x80)}


def teams(rom):
    out = []
    names = team_names(rom)
    for t in range(28):
        p = rom.u32(TEAMS + 4 * t)
        a = p + rom.u16(p + 4)
        strs, _ = pstr_list(rom, a, 4)
        out.append({"id": t, "city": strs[0], "abbr": strs[1], "nickname": strs[2], "arena": strs[3],
                    "rating": rom.b[TEAM_RATING + t],
                    "colours": [[rom.u16(TEAM_COLOURS + 64 * t + 32 * k + 2 * i) for i in range(16)]
                                for k in range(2)]})
        assert names[t]["city"] == strs[0]
    return out


def messages(rom):
    out, a = {}, MESSAGES
    for i in range(0x24):
        e = rom.b.index(b"\r", a)
        s = rom.b[a:e].decode("latin-1")
        if s:
            out["%02X" % i] = s
        a = e + 1
    return out


def setup_section(rom):
    labels = []
    a = OPT_LABELS
    for _ in range(9):
        n, t = plain(rom, a)
        labels.append(t.rstrip())
        a += n
    offs = [rom.u16(OPT_VALUES + 2 * i) for i in range(9)]
    # value lists: walk from each row's offset (GameSetUp_4: dbf d3 over word lengths)
    lists = {}
    spans = {"play_mode": (0x12, 6), "players": (0x80, 8), "players_4way": (0x80 + 0xB0, 12),
             "period_length": (0x238, 4), "goalies": (0x290, 2), "penalties": (0x2BC, 3),
             "user_records": (0x2FE, 2), "line_changes": (0x32A, 3)}
    for k, (o, n) in spans.items():
        vals, _ = pstr_list(rom, OPT_VALUES + o, n)
        lists[k] = [v.rstrip() for v in vals]
    counts = [rom.u16(OPT_COUNTS + 2 * i) for i in range(9)]
    counts4 = [rom.u16(OPT_COUNTS_4WAY + 2 * i) for i in range(9)]
    defaults = [rom.u16(DEFMENUOPTIONS + 2 * i) for i in range(9)]
    noplist = [[rom.u16(NOPLIST + 4 * i), rom.u16(NOPLIST + 4 * i + 2)] for i in range(7)]
    pojoy = [[rom.u16(POJOYLIST + 4 * i), rom.u16(POJOYLIST + 4 * i + 2)] for i in range(8)]
    pojoy2 = [[rom.u16(POJOYLIST2 + 4 * i), rom.u16(POJOYLIST2 + 4 * i + 2)] for i in range(5)]
    _, na = plain(rom, 0xF7CEE)
    _, nyi = plain(rom, 0xF7CB2)
    _, nyr = plain(rom, 0xF7CC6)
    rows = []
    value_key = ["play_mode", "players", None, None, "period_length", "goalies", "user_records", "penalties",
                 "line_changes"]
    for i in range(9):
        rows.append({"row": i, "label": labels[i], "ram": "$FFD0%02X" % (0x48 + 2 * i), "name": ROW_RAM[i],
                     "values": value_key[i] or "teams", "values_offset": "$%X" % offs[i],
                     "count": counts[i], "count_4way": counts4[i], "default": defaults[i]})
    bg = Jim(rom, SETUP_BG)
    return {
        "routines": {
            "Opening2": "L53868 $172FA", "GameSetUp": "L960187 $F739E", "setoptions": "L962234 $F8168",
            "GameSetUp_2 (input loop)": "L962336 $F82EE", "sub_F76D4 (move cursor)": "L960512 $F76D4",
            "GameSetUp_3 (change value)": "L960788 $F7942", "sub_F78A2 (redraw)": "L960715 $F78A2",
            "sub_F7B20 / GameSetUp_4 (print rows)": "L960958 / L960985", "sub_F8070 (labels)": "L962050",
            "sub_17AF4 (plates)": "L54595", "sub_F85B0 / sub_F8608 (logos)": "L962531 / L962557",
            "sub_F87EA / sub_F8868 (player showcase)": "L962807 / L962842", "FigureJoy": "L55005 $17E42",
            "LoadDefMenuOptions": "L54836", "start (loc_F843E)": "L962423 $F843E", "demo (loc_F8418)": "L962415 $F8418"},
        "screen": {"mode": "H40", "size": [320, 224], "plane_a": "$E000 64x32", "plane_b": "$C000 64x32",
                   "window": "off", "sprites": "$B400 (unused here)", "music": "song $78 keeps playing from the title "
                   "(GameOver plays $78 again before Opening2)"},
        "vram_tiles": {"plates_home": 2, "plates_visitor": "$190 (word_FFD43A)", "framer": "$31E (framercset)",
                       "font0": "$327 (word_FFB012, $AAC5A remap 0F C0 45 67..: not seen on screen)",
                       "font_alt": "$385 (word_FFBF52, $BE26A raw)", "bg": "$3E3",
                       "logo_visitor": "$4D3 (word_FFD432, 36 tiles)", "header": "$4F7",
                       "panel": "$514 (word_FFD426)", "logo_home": "$51D (word_FFD430, 36 tiles)",
                       "frame_home": "$541 (word_FFD436)", "frame_visitor": "$547 (word_FFD438)"},
        "layers": [
            {"what": "background", "image": "setup_bg_idx.png", "plane": "B", "at": [0, 0], "cells": [40, 28],
             "note": "palette lines 0, 2, 3 of $4B7A0 (line 2 is then replaced by the visitor logo)"},
            {"what": "header", "image": "setup_header_idx.png", "plane": "A", "at": [0, 0], "cells": [40, 4]},
            {"what": "visitor plate", "image": "team_plates_visitor_idx.png", "plane": "A", "at": [7, 1],
             "cells": [11, 2], "src_row": "2*VisTeam", "line": 1, "priority": True},
            {"what": "home plate", "image": "team_plates_home_idx.png", "plane": "A", "at": [22, 1],
             "cells": [11, 2], "src_row": "2*HomeTeam", "line": 1, "priority": True},
            {"what": "visitor logo frame", "image": "logo_frame_visitor_idx.png", "plane": "A", "at": [8, 5],
             "cells": [8, 8]},
            {"what": "home logo frame", "image": "logo_frame_home_idx.png", "plane": "A", "at": [24, 5],
             "cells": [8, 8]},
            {"what": "visitor logo", "image": "../menus/team_logos_idx.png", "plane": "A", "at": [9, 6],
             "cells": [6, 6], "line": 2, "palette": "team_logos[VisTeam] -> line 2 (dobitmap mask 4); the cells show "
                                                   "line 2 on the emulator"},
            {"what": "home logo", "image": "../menus/team_logos_idx.png", "plane": "A", "at": [25, 6],
             "cells": [6, 6], "line": 1, "palette": "team_logos[HomeTeam] -> line 1, then colours 1-5 overwritten "
                                                   "(see palette.line1)"},
            {"what": "panel", "image": "setup_panel_idx.png", "plane": "A", "at": [1, 14], "cells": [38, 13]},
            {"what": "labels", "font": "font_setup_idx.png", "plane": "A", "x": 3, "y": "15 + 2*(row - top)",
             "attr": "$0000 (line 0)", "width": 13},
            {"what": "values", "font": "font_setup_idx.png", "plane": "A", "x": 17, "y": "15 + 2*(row - top)",
             "attr": "$8000 (line 0, priority)", "width": 20},
            {"what": "scroll arrows", "plane": "A", "at_up": [2, 15], "at_down": [2, 25],
             "glyphs": {"up": "{", "down": "}", "none": " "},
             "rule": "'{' when top > 0; '}' when top < 3 and not shootout; sub_F7BFA L961028"},
            {"what": "cursor box", "image": "setup_framer_idx.png", "plane": "A",
             "at": [16, "14 + 2*(row - top)"], "cells": [23, 3],
             "attr": "printa $6000 + map line 1 = line 0 with priority",
             "playoffs_team1": "23x5 (covers Team 1 and Team 2) when 2 <= OptPlayMode <= 3 and row == Team 1",
             "restore": "the old box area is redrawn from setup_panel ($BEFB8) before the new box"},
        ],
        "rows": rows,
        "visible_rows": 6, "top_max": 3, "row_pitch": 2,
        "value_lists": lists,
        "value_notes": {
            "play_mode": "count 5: Regular Season, Continue Playoffs (only selectable while a playoff is in "
                         "progress: gamelevel|bosgames != 0 after sub_17CA0), New Playoffs, New Playoffs/7 game, "
                         "Shootout; entry 5 'Demo' is never selectable",
            "players": "2 pads: OptNOP 0-4 in Regular Season (Demo, One - Home, One - Visitor, Two - Teammates, "
                       "Two - Head to Head), 5-7 in playoffs (Two - Head to Head, Two - Teammates, One), "
                       "Shootout: 0-4 without 3 (Two - Teammates). 4 Way Play (FourWayPlay $FFD046): list "
                       "players_4way, regular 0-6 adds Three, Four; playoffs 7-11 without 9-10",
            "period_length": "count 3; entry 3 '30 Seconds' only through the StartGame cheat (hold A+C+Start "
                             "on pad 1: OptPerlen = 3, L29756); Shootout prints 'N/A' and skips the row",
            "teams": "28 teams, the ROM team order (0 Anaheim .. 25 Winnipeg, 26 All Stars East, 27 All Stars "
                     "West); city string, except 13/14 'New York Islanders'/'New York Rangers'; New Playoffs "
                     "allow 26 (no All-Stars) for Team 1 and fix Team 2 (opponent from the bracket)",
            "goalies": "forced to Auto Control (and word_FFD05A/C = 1) while Players = Demo",
            "user_records": "0 = On, 1 = Off; forced Off for Demo and Shootout; skipped by the cursor "
                            "unless ValidSRAM >= 0",
            "penalties": "0 Off, 1 On, 2 On, Except Off-sides; Shootout forces Off",
            "line_changes": "0 On, 1 Off, 2 Auto; Shootout forces Off"},
        "special_strings": {"na": na.rstrip(), "ny_islanders": nyi, "ny_rangers": nyr},
        "players_to_pads": {
            "noplist": noplist,
            "noplist_note": "_noplist: OptNOP -> [cont1team, cont2team] (0 CPU, 1 home team, 2 visitor); "
                            "4 Way Play: OptNOP 5 'Three' also cont3team = cont1team; 6 'Four' cont3 = cont1, "
                            "cont4 = cont2",
            "pojoylist": pojoy, "pojoylist2": pojoy2,
            "pojoy_note": "playoffs: pojoy = 7 - OptNOP (11 - OptNOP with 4 Way Play, sub_17AC8); "
                          "index = pojoy + (0 when the user's team is home in its pairing, else 4 (5))"},
        "controls": {
            "up/down": "move the cursor (sub_F76D4); rows that do not apply are skipped (skip_rules); "
                       "auto-repeat sub_11318 (16 frames, then every 5)",
            "left/right": "previous/next value with wrap-around (GameSetUp_3, sub_F7B0A)",
            "C": "speeds up the player showcase (word_FFD43C = $53); nothing else",
            "A/B": "nothing",
            "Start": "start (loc_F843E)",
            "pads": "pads 1 and 2 (3 and 4 with 4 Way Play) all drive the menu",
            "idle": "$5460 frames (6 min) with no press -> demo game (loc_F8418)"},
        "skip_rules": [
            "down from Per. Length: +2 rows (skip Goalies) when Players = Demo; +3 (skip Goalies and User "
            "Records) when also not Shootout",
            "down from Team 2 in Shootout: skip Per. Length (or stop when Players = Demo)",
            "down from Goalies: stop in Shootout; skip User Records when ValidSRAM < 0",
            "up mirrors these (L960261-960298)",
            "Continue Playoffs: rows 1-3 (Players, Team 1, Team 2) are skipped",
            "New Playoffs (/7): Team 2 is skipped"],
        "showcase": {
            "start": "word_FFD440 = $B4 (180 frames) after a logo is drawn; then the logos give way to cards",
            "card": "alternating visitor / home every $AA frames ($53 with C): a Framer 25x8 (attr $6000) and "
                    "an 8x8 logo frame with the player photo (6x6, photo palette line 1)",
            "visitor_card": {"photo": [4, 6], "frame": [3, 5], "box": [11, 5], "name": [12, 6]},
            "home_card": {"photo": [29, 6], "frame": [28, 5], "box": [3, 5], "name": [4, 6]},
            "name": "'NN First Last' (d0toascii + full name) through print2 / font_setup, line 0",
            "player": "photos.json teams[team][k], k = word_FFD43E: +1 on each visitor card, wraps at 6",
            "records": "with ValidSRAM >= 0 and a record: up to 3 SRAM record lines below the name "
                       "(sub_F98C6, sub_F9A64, sub_F9AAC)",
            "stop": "a team change erases the card (sub_F84FC) and redraws both logos"},
        "palette": {
            "bg": jim_pal(bg),
            "line0": "bg line 0",
            "line1": "team_logos[HomeTeam]; colours 1-2 = teams[HomeTeam].colours[0][1..2], colours 3-4 = "
                     "teams[VisTeam].colours[1][3..4], colour 5 = $EEE (sub_17AF4)",
            "line2": "team_logos[VisTeam] (sub_F8608)",
            "line3": "bg line 3",
            "fade": "palcount $64 after a logo or plate change"},
    }


def matchups_section(rom):
    msgs = messages(rom)
    cats, _ = pstr_list(rom, CATEGORIES, 10)
    pos, _ = pstr_list(rom, POSITIONS, 6)

    def arrows(a):
        return [plain(rom, rom.u32(a + 4 * i))[1] for i in range(6)]
    _, home, = plain(rom, HOME_VIS)
    _, vis = plain(rom, HOME_VIS + 6)
    return {
        "routines": {"sub_FCC76": "L969615 $FCC76", "sub_FD46C (pick players)": "L970396",
                     "sub_FD084 (logos/photos)": "L970006", "sub_FD1FE (labels, ratings, names)": "L970128",
                     "sub_FD4CA (arrows)": "L970443", "sub_FD89A (names)": "L970971", "sub_17718 / sub_17730 (commentary)": "L54250 / L54260",
                     "$F7318 'Lately' check (labelled EASportsScreen in the listing)": "L960137",
                     "sub_F71A2 / sub_F71F0 (hot/cold)": "L959993 / L960015", "sub_FF8DE (HOT/COLD badge)": "L976589"},
        "when": "Opening2 after GameSetUp, sub_FBB88 and PlayoffScreen, unless word_FFC2FA bit 0 (Shootout)",
        "music": "song $7A",
        "screen": {"mode": "H40", "vbint": "loc_15E4C",
                   "vram_tiles": {"home_pic": 2, "visitor_pic": "$26", "bigfont": "$4A (word_FFB010)",
                                  "font0": "$CE (word_FFB012, $AAC5A raw)", "font1": "$12C (word_FFB014)",
                                  "framer": "$18A", "hot": "word_FFDEE4", "cold": "word_FFDEE6"}},
        "layers": [
            {"what": "background", "image": "../menus/stats_bg_idx.png", "plane": "B", "at": [0, 0],
             "palette": "$54E24 lines 0-1 (mask 3)"},
            {"what": "text box", "framer": "framer_matchups_idx.png", "plane": "B", "at": [6, 3], "cells": [33, 9],
             "attr": "$4000 (map line 1 + 2 = line 3)"},
            {"what": "visitor frame", "framer": "framer_matchups_idx.png", "plane": "B", "at": [1, 14],
             "cells": [8, 8], "attr": "$4000"},
            {"what": "home frame", "framer": "framer_matchups_idx.png", "plane": "B", "at": [31, 14],
             "cells": [8, 8], "attr": "$4000"},
            {"what": "Ron Barr", "image": "ron_barr_idx.png", "plane": "A", "at": [1, 1], "cells": [8, 9],
             "palette": "$B389C lines 2-3 (mask $C)"},
            {"what": "title", "image": "matchups_title_idx.png", "plane": "A", "at": [12, 13],
             "attr": "$4000 added to map line 1 -> line 3", "text": "MATCHUPS"},
            {"what": "ADVANTAGE:", "plane": "A", "at": [16, 17], "font": "font 0 (raw $AAC5A)", "attr": 0},
            {"what": "page label", "plane": "A", "at": [13, 19], "font": "font 1", "width": 16,
             "note": "page 0 'Overall' centred at x 22 - len/2 (13); pages 1-6 the position label at 13"},
            {"what": "visitor picture", "plane": "A", "at": [2, 15], "cells": [6, 6],
             "page0": "team logo, palette line 2 (dobitmap mask 4, printa $6000 XOR map line 1)",
             "pages1_6": "photo, photo palette line 1"},
            {"what": "home picture", "plane": "A", "at": [32, 15], "cells": [6, 6],
             "page0": "team logo, palette line 1", "pages1_6": "photo (palette already in line 1)"},
            {"what": "visitor rating", "plane": "A", "at": [4, 22], "font": "font 1", "digits": 2},
            {"what": "home rating", "plane": "A", "at": [34, 22], "font": "font 1", "digits": 2},
            {"what": "arrows", "plane": "A", "at": [19, 22], "font": "font 1", "width": 3},
            {"what": "names row", "plane": "A", "row": 23, "font": "font 0",
             "visitor": "x 0", "home": "x 35, moved left so the name ends by column 39 (sub_FD89A)",
             "form": "'NN Lastname' (sub_18B26)", "page0": "row cleared"},
            {"what": "HOT / COLD badge", "plane": "A", "visitor_at": [2, 25], "home_at": [32, 25],
             "images": ["hot_idx.png (6x2)", "cold_idx.png (6x3)"],
             "rule": "shown when the page's player is his team's hot (best form) or cold (worst) starter; "
                     "else the 8x3 area is erased"},
            {"what": "commentary", "plane": "A", "at": [9, 4], "lines": 7, "wrap": 29, "font": "font 0",
             "note": "typewriter, one word every 10 frames (+40 after ',' or '.'); the 7-line window "
                     "scrolls up (sub_179D2)"},
        ],
        "pages": {"count": 7, "labels": [cats[9].strip()] + [p.strip() for p in pos],
                  "label_strings": {"page0_list": cats, "positions": pos},
                  "slot_byte": list(rom.b[POS_SLOTS:POS_SLOTS + 7]),
                  "slot_note": "page k shows byte slot_byte[k] of each team's starting line (team record + 6: "
                               "G, LD, RD, LW, C, RW), roster slot = byte - 1",
                  "rating_page0": "teams[t].rating (sub_FE172, $FE18E)",
                  "rating_pages": "CalcAttrib with the Overall weights (dword_19420 skaters, dword_19582 "
                                  "goalies) * 100 / d1, then AttribAdjust (includes the hot/cold form)"},
        "arrows": {"home_higher": arrows(ARROWS_HOME), "visitor_higher": arrows(ARROWS_VIS),
                   "even": plain(rom, ARROWS_EVEN)[1],
                   "glyphs": {"]": "right arrow (towards the home side)", "[": "left arrow"},
                   "timing": "step every 7 frames: 0, 1, 2, 3 arrows, then stays at 3; restarts on a page change"},
        "script": {
            "order": ["1B", "1D", "1A", "1D", "22|23 if $F7318 >= 0", "1D (with it)", "1E", "1D",
                      "1F if HomeTeam != VisTeam", "1D", "20", "1D", "21"],
            "messages": msgs,
            "tokens": {"^": "home arena (team string 4)", ";": "visitor arena", "_": "home city",
                       "{": "home city", "+": "visitor city", "}": "visitor city",
                       "=": "home nickname (team string 3; 'Home' if empty)",
                       "*": "visitor nickname ('Visitors' if empty)",
                       "#": "home user name (User Records, word_FFD042)", "%": "visitor user name",
                       "[": "home goalie (getname of slot $26)", "]": "visitor goalie",
                       "<": "home hot player", ">": "visitor hot player", "|": "home cold player",
                       "\\": "visitor cold player", "@": "home arena crowd record in dB (SRAM, $50 when 0)",
                       "$": "city of the team with the better form"},
            "empty_nickname": {"home": home, "visitor": vis},
            "lately": "$F7318: |sum(visitor form) - sum(home form)| >= $5E -> message 22, >= $BD -> 23, "
                      "else none; '$' = the team with the higher sum",
            "end": "when the script ends: word_FFD5B6 = $1E0 (480 frames); then exit if Players = Demo, "
                   "else wait for Start"},
        "controls": {"Start": "begin the game (StartGame); holding A+C with it = 30-second periods",
                     "C": "next page", "A": "previous page", "down (held)": "text at full speed (asv)",
                     "auto": "next page every $10E (270) frames; a press of A/C resets the timers"},
        "form": {"table": "Create_HotCold_Table for both teams at sub_FCC76 entry (StartGame does it only for "
                          "Shootout)",
                 "score": "per starter (6): sum of the form bytes 3..15 of his 16, skipping 9 and 13 (sub_F71F0)",
                 "hot": "the highest score", "cold": "the lowest"},
    }


def playoffs_section(rom):
    labels, _ = pstr_list(rom, PO_LABELS, 5)
    n = rom.u16(PO_PAGE)
    page = rom.b[PO_PAGE + 5:PO_PAGE + n].replace(b"\x00", b"").decode("latin-1")
    return {"routine": "PlayoffScreen L53888 $17336 (returns at once when OptPlayMode = 0)",
            "when": ["Opening2 after GameSetUp and sub_FBB88, before the Matchups", "GameOver after Playoff Stats"],
            "music": "song $79",
            "headings": labels, "page_hint": page,
            "background": "$54E24 on plane B (XOR $6000), the cup ($F3098) and the 16 team plates; the user's "
                          "team flashes (word_FFBD6A ^= $EE every $18 frames)",
            "controls": {"Start (held, pad 1 or 2)": "leave", "left/right": "scroll to the later rounds "
                         "(gamelevel * $70 px)"},
            "port": "not applicable (no playoffs in MatchConfig)"}


def flow_section():
    return [
        {"step": "Begin", "line": "L29715", "what": "RAM clear, EASportsScreen, InitSaveRAM, HiScoreScreen, "
                                                     "LoadDefMenuOptions (defmenuoptions L54847), jmp Opening"},
        {"step": "Opening", "line": "L53865", "what": "KillCrowd; newTitleScreen (title_screen.md); song $78"},
        {"step": "Opening2", "line": "L53868", "what": "KillCrowd; clear RAM $FFB000-$FFD03E (the options at "
                                                       "$FFD048 survive); GameSetUp"},
        {"step": "GameSetUp", "line": "L960187", "what": "the Game Setup menu until Start (or the 6-minute "
                                                         "demo timeout)"},
        {"step": "start", "line": "L962423", "what": "goalie flags, pojoy, RNG seed; OptLine 2 -> 0 + "
                                                     "byte_FFC2FC bit 4; Shootout: OptPlayMode 0 + word_FFC2FA "
                                                     "bit 0 + sub_FC47C; MakeTree (FigureJoy: pads)"},
        {"step": "sub_FBB88", "line": "L967859", "what": "User Records On: Name Entry for each human pad "
                                                         "(loc_FB018), SRAM"},
        {"step": "PlayoffScreen", "line": "L53888", "what": "playoffs only: the bracket"},
        {"step": "sub_FCC76", "line": "L969615", "what": "Matchups (not in Shootout); Start leaves"},
        {"step": "StartGame", "line": "L29748", "what": "A+C+Start held: 30 s periods; OptPen 1 -> offsides; "
                                                        "clear stats; setupice; song $79; Intermission (gsp 0: "
                                                        "'Start Game' menu, ui_menus.md)"},
        {"step": "game", "what": "... PeriodOver/Intermission (ui_menus.md)"},
        {"step": "Exit Game", "line": "L53851", "what": "GameOver: playoff bookkeeping, Playoff Stats, "
                                                        "PlayoffScreen; song $78; Opening2 (no title); GameSetUp "
                                                        "restores OptLine from TmpOptLine2 and OptPlayMode "
                                                        "from TempOptPlayMode, so the menu shows the last "
                                                        "settings"},
    ]


def compose_setup(rom, assets, home=11, vis=10, opts=None):
    """Static preview of the Game Setup screen built from the exported pieces."""
    j = assets
    scr = Screen()
    bg = Jim(rom, SETUP_BG)
    cram = [list(bg.pal[0]), [0] * 16, [0] * 16, list(bg.pal[3])]
    lp = [[rom.u16(LOGO_PALS + 32 * t + 2 * i) for i in range(16)] for t in range(28)]
    cram[1] = list(lp[home])
    cram[2] = list(lp[vis])
    tc = j["teams"]
    cram[1][1], cram[1][2] = tc[home]["colours"][0][1], tc[home]["colours"][0][2]
    cram[1][3], cram[1][4] = tc[vis]["colours"][1][3], tc[vis]["colours"][1][4]
    cram[1][5] = 0xEEE
    scr.blit(j["bg"], 0, 0)
    scr.blit(j["header"], 0, 0)
    scr.blit(j["plates_vis"], 7 * 8, 8, 0, 16 * vis, 88, 16)
    scr.blit(j["plates_home"], 22 * 8, 8, 0, 16 * home, 88, 16)
    scr.blit(j["frame_vis"], 8 * 8, 5 * 8)
    scr.blit(j["frame_home"], 24 * 8, 5 * 8)
    logos = j["logos"]
    scr.blit(logos, 9 * 8, 6 * 8, (vis % 4) * 48, (vis // 4) * 48, 48, 48, line=2)
    scr.blit(logos, 25 * 8, 6 * 8, (home % 4) * 48, (home // 4) * 48, 48, 48, line=1)
    scr.blit(j["panel"], 8, 14 * 8)
    font, fmap = j["font"], j["font_map"]

    def text(s, x, y):
        for k, ch in enumerate(s):
            t = fmap[str(ord(ch))]
            scr.blit(font, (x + k) * 8, y * 8, (t % 16) * 8, (t // 16) * 8, 8, 8, line=0)
    fr = j["framer_setup"]
    for yy in range(3):
        for xx in range(23):
            sx = 0 if xx == 0 else (16 if xx == 22 else 8)
            sy = 0 if yy == 0 else (16 if yy == 2 else 8)
            scr.blit(fr, (16 + xx) * 8, (14 + yy) * 8, sx, sy, 8, 8, add=3)
    su = j["setup"]
    opts = opts or [r["default"] for r in su["rows"]]
    names = {r["id"]: r for r in j["teams"]}
    vl = su["value_lists"]
    for r in range(6):
        y = 15 + 2 * r
        text(su["rows"][r]["label"], 3, y)
        k = su["rows"][r]["values"]
        if k == "teams":
            t = opts[r]
            v = names[t]["city"] if t not in (13, 14) else (su["special_strings"]["ny_islanders"] if t == 13
                                                            else su["special_strings"]["ny_rangers"])
        else:
            v = vl[k][opts[r]]
        text(v, 17, y)
    text("}", 2, 25)
    return scr, cram


def compose_matchups(rom, assets, home=11, vis=10):
    j = assets
    scr = Screen()
    st = Jim(rom, STATS_BG)
    barr = Jim(rom, BARR)
    lp = [[rom.u16(LOGO_PALS + 32 * t + 2 * i) for i in range(16)] for t in range(28)]
    cram = [list(st.pal[0]), list(lp[home]), list(lp[vis]), list(barr.pal[3])]
    bgc, _ = image(rom, STATS_BG, opaque=True)
    scr.blit(bgc, 0, 0, line=None)
    # stats_bg cells use lines 0-1 only here
    fr = j["framer_mu"]
    for (x0, y0, w, h) in ((6, 3, 33, 9), (1, 14, 8, 8), (31, 14, 8, 8)):
        for yy in range(h):
            for xx in range(w):
                sx = 0 if xx == 0 else (16 if xx == w - 1 else 8)
                sy = 0 if yy == 0 else (16 if yy == h - 1 else 8)
                for py in range(8):   # same plane as the background: the cell replaces it
                    scr.idx[(y0 + yy) * 8 + py][(x0 + xx) * 8:(x0 + xx) * 8 + 8] = [(0, 0)] * 8
                scr.blit(fr, (x0 + xx) * 8, (y0 + yy) * 8, sx, sy, 8, 8, add=2)
    scr.blit(j["barr"], 8, 8)
    scr.blit(j["title"], 12 * 8, 13 * 8, add=2)
    logos = j["logos"]
    scr.blit(logos, 2 * 8, 15 * 8, (vis % 4) * 48, (vis // 4) * 48, 48, 48, line=2)
    scr.blit(logos, 32 * 8, 15 * 8, (home % 4) * 48, (home // 4) * 48, 48, 48, line=1)
    f0, f1, fmap = j["font0"], j["font1"], j["font0_map"]

    def text(f, s, x, y):
        for k, ch in enumerate(s):
            t = fmap[str(ord(ch))]
            scr.blit(f, (x + k) * 8, y * 8, (t % 16) * 8, (t // 16) * 8, 8, 8, line=0)
    text(f0, "ADVANTAGE:", 16, 17)
    text(f1, "    Overall     ", 13, 19)
    tm = {t["id"]: t for t in j["teams"]}
    text(f1, "%2d" % tm[vis]["rating"], 4, 22)
    text(f1, "%2d" % tm[home]["rating"], 34, 22)
    text(f1, "[[[" if tm[vis]["rating"] > tm[home]["rating"] else "]]]", 19, 22)
    return scr, cram


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    prev = None
    if "--preview" in sys.argv:
        prev = sys.argv[sys.argv.index("--preview") + 1]
        args = [a for a in args if a != prev]
    rom_path = args[0] if args else "lst/nhl94.bin"
    out = args[1] if len(args) > 1 else "godot/assets/ui/frontend"
    data = open(rom_path, "rb").read()
    assert zlib.crc32(data) & 0xFFFFFFFF == ROM_CRC, "unexpected ROM"
    rom = R(data)
    os.makedirs(out, exist_ok=True)
    A = {}

    # --- Game Setup art
    bg, _ = image(rom, SETUP_BG, opaque=True)
    save(bg, out, "setup_bg_idx.png")
    A["bg"] = bg
    hd, _ = image(rom, SETUP_HEADER)
    save(hd, out, "setup_header_idx.png")
    A["header"] = hd
    pn, _ = image(rom, SETUP_PANEL)
    save(pn, out, "setup_panel_idx.png")
    A["panel"] = pn
    ft = remap(Jim(rom, SETUP_FRAMER_TILES).tiles, REMAP_SETUP_FRAMER)
    fs, fcells = framer_canvas(rom, ft)
    save(fs, out, "setup_framer_idx.png")
    A["framer_setup"] = fs
    fj = Jim(rom, SETUP_FONT)
    fsheet = sheet(fj.tiles)
    save(fsheet, out, "font_setup_idx.png")
    A["font"], A["font_map"] = fsheet, font_map(rom, SETUP_FONT)
    frh, _ = image(rom, LOGO_FRAME)
    save(frh, out, "logo_frame_home_idx.png")
    lf = Jim(rom, LOGO_FRAME)
    frv, _ = image(rom, LOGO_FRAME, tiles=remap(lf.tiles, REMAP_FRAME_VIS))
    save(frv, out, "logo_frame_visitor_idx.png")
    A["frame_home"], A["frame_vis"] = frh, frv
    ph, pj = image(rom, PLATES)
    save(ph, out, "team_plates_home_idx.png")
    pv, _ = image(rom, PLATES, tiles=remap(pj.tiles, REMAP_PLATES_VIS))
    save(pv, out, "team_plates_visitor_idx.png")
    A["plates_home"], A["plates_vis"] = ph, pv

    # --- Matchups art
    br, bj = image(rom, BARR)
    save(br, out, "ron_barr_idx.png")
    A["barr"] = br
    bigt = remap(Jim(rom, BIGFONT).tiles, REMAP_MU_BIG)
    title, title_w = big_title(rom, "MATCHUPS", bigt)
    save(title, out, "matchups_title_idx.png")
    A["title"] = title
    f1 = sheet(remap(Jim(rom, FONT).tiles, REMAP_MU_FONT1))
    save(f1, out, "font_matchups_alt_idx.png")
    A["font1"], A["font0"] = f1, sheet(Jim(rom, FONT).tiles)
    A["font0_map"] = font_map(rom, FONT)
    fm, _ = framer_canvas(rom, remap(Jim(rom, FRAMER).tiles, REMAP_MU_FRAMER))
    save(fm, out, "framer_matchups_idx.png")
    A["framer_mu"] = fm
    hot, hj = image(rom, HOT)
    save(hot, out, "hot_idx.png")
    cold, cj = image(rom, COLD)
    save(cold, out, "cold_idx.png")

    tm = teams(rom)
    A["teams"] = tm
    su = setup_section(rom)
    A["setup"] = su
    doc = {
        "source": "lst/nhl94.bin (CRC32 9438F5DD); spec docs/specs/ui_frontend.md",
        "index_textures": "R = colour * 17, G = line * 85, A = 255 where drawn; images keep their map lines",
        "flow": flow_section(),
        "setup": su,
        "matchups": matchups_section(rom),
        "playoffs": playoffs_section(rom),
        "name_entry": {"routine": "sub_FBB88 L967859 -> loc_FB018 L966784",
                       "when": "OptUserRec = 0 (On): once for cont1team, once for cont2team if different",
                       "port": "not applicable (SRAM user records)"},
        "fonts": {"setup": {"image": "font_setup_idx.png", "address": "$BE26A", "per_row": 16,
                            "chars": A["font_map"],
                            "note": "differs from $AAC52 in '(' ')' / '{' '}' (swapped tiles) and in style"},
                  "matchups_font0": {"image": "../menus/font_stats_idx.png", "address": "$AAC52 raw"},
                  "matchups_font1": {"image": "font_matchups_alt_idx.png", "remap": REMAP_MU_FONT1.hex(),
                                     "chars": "same map as ../menus/font.json"}},
        "framers": {"map": [c & 0x7FF for c in fcells], "map_line": 1,
                    "order": "TL T TR / L C R / BL B BR (24x24 images)",
                    "setup": {"image": "setup_framer_idx.png", "tiles": "$BF54A", "remap": REMAP_SETUP_FRAMER.hex(),
                              "attr": "$6000 -> line 0 + priority"},
                    "matchups": {"image": "framer_matchups_idx.png", "tiles": "$55B86",
                                 "remap": REMAP_MU_FRAMER.hex(), "attr": "$4000 -> line 3"}},
        "images": {
            "setup_bg_idx.png": {"address": "$4B7A0", "cells": [40, 28]},
            "setup_header_idx.png": {"address": "$4DEEE", "cells": [40, 4]},
            "setup_panel_idx.png": {"address": "$BEFB8", "cells": [38, 13]},
            "logo_frame_home_idx.png": {"address": "$BF702", "cells": [8, 8]},
            "logo_frame_visitor_idx.png": {"address": "$BF702", "remap": REMAP_FRAME_VIS.hex()},
            "team_plates_home_idx.png": {"address": "$AFE12", "cells": [11, 56], "team_rows": 2},
            "team_plates_visitor_idx.png": {"address": "$AFE12", "remap": REMAP_PLATES_VIS.hex()},
            "ron_barr_idx.png": {"address": "$B389C", "cells": [8, 9], "palette": jim_pal(bj)},
            "matchups_title_idx.png": {"text": "MATCHUPS", "cells": [title_w, 2], "remap": REMAP_MU_BIG.hex(),
                                       "map_line": 1},
            "hot_idx.png": {"address": "$F5AF6", "cells": [6, 2], "palette_line3": jim_pal(hj)[3]},
            "cold_idx.png": {"address": "$F5D1C", "cells": [6, 3], "palette_line3": jim_pal(cj)[3]}},
        "teams": tm,
    }
    with open(os.path.join(out, "frontend.json"), "w") as f:
        json.dump(doc, f, indent=1)
        f.write("\n")
    if prev:
        os.makedirs(prev, exist_ok=True)
        lg = Canvas(4 * 48, 7 * 48)
        for t in range(28):
            jl = Jim(rom, rom.u32(TEAM_LOGOS + 4 * t))
            draw_cells(lg, jl.tiles, jl.cells, 6, 6, 6, (t % 4) * 48, (t // 4) * 48)
        A["logos"] = lg
        s, cram = compose_setup(rom, A)
        s.save(os.path.join(prev, "preview_setup.png"), cram)
        s, cram = compose_matchups(rom, A)
        s.save(os.path.join(prev, "preview_matchups.png"), cram)
    print("wrote frontend.json and %d images to %s" % (15, out))


if __name__ == "__main__":
    main()
