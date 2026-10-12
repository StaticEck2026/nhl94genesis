#!/usr/bin/env python3
"""Export NHL '94's arena sprite animations as loose files for the Godot port.

Offline only. The game never reads the ROM; it loads what this writes under
godot/assets/arena/. Usage: python3 tools/extract/arena.py [lst/nhl94.bin] [godot/assets/arena]
Spec (stepping, triggers, positions, draw order): docs/specs/arena_animations.md.

Three sprite "anim" files, each drawn piece by piece (SetSframe L52164, sub_16246
L52223, sub_FD78A L970856), never through frameSprData:
  crowd     CrowdFrameList $A4B54 (showcrowd L52175): the crowd, camera flashes and the
            penalty-box occupants. Frames 1-31 are in rink-map pixels, 32-62 (= 1-31 + $1F,
            horizontal mode) in screen pixels of the 256x224 side view.
  bganim    the 5 frame files of the 8 background animations (table unk_FE364, sub_FE2C8
            L973464), in rink-map pixels, plus each id's {frame, vblanks} script.
  zamboni   ZamFrameList $A8922 (showzam L52076): 8 frames relative to the zamboni's
            origin, drawn on the intermission's side view.

File layout (all five bganim files, the crowd and the zamboni share it):
  +0 long  palette offset (a 16-colour block; never loaded by the game)
  +4 long  frame-table offset; word w[i] (i = 0..n+1), w[0] = 0, w[1] = table size,
           frame f (1..n) = pieces at table + w[f] .. table + w[f+1], n = w[1]/2 - 2
  +8 word  tile count (bit 15: compressed, sub_1177A); the loader gets this address
  +10      tiles (32 bytes each)
  piece    +0 s16 x, +2 s16 y (top-left, +y down), +4 u16 tile, +6 u16: bits 15-11 VDP
           flags (priority, palette line, v-flip, h-flip), bits 7-0 VDP size byte.

The game draws each piece as one hardware sprite with attribute (word6 & $F800) + tile +
VRAM base; nothing is XORed in (no object flip, no away-palette swap).

Writes assembled character sheets, index textures as in assets.py (R = colour index * 17,
G = palette line * 85, A = 255 where drawn, colour 0 transparent):
  crowd_idx.png + crowd.json       the crowd's figures, the _cd0 table, frame groups
  bganim_idx.png + bganim.json     the figures of the 5 bganim files, per-id scripts and triggers
  zamboni_idx.png + zamboni.json   the zamboni's 8 frames, the unk_1615E wave table

The hardware pieces are assembled offline: each frame's pieces are composited in the game's
VDP link order (the first piece is in front) into figures, one per group of touching pieces
(a fan, a camera flash, a seated player, a hat; the zamboni frames whole). Identical figures
are stored once. JSON: "sprites" lists each figure's sheet rect; each frame lists its
figures as "parts" [x, y, sprite id], x, y the figure's top-left in the file's native space
("space"). Figures of one frame never overlap, so their order does not matter. "bbox" is
the frame's extent. The arena-wide crowd frames would be mostly empty as single images,
hence one figure per group. Output is deterministic (stable packing order, fixed JSON key
order).
"""
import json
import os
import sys
import zlib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from assets import ROM_CRC, BytesRom, Canvas, Rom, decompress, pack  # noqa: E402

CROWD = 0xA4B54          # CrowdFrameList: showcrowd's movea.l #CrowdFrameList (L52178)
CROWD_TILES = 0x76       # unk_A4B5C, loaded to word_FFB01A by setupice (L53061)
ZAM = 0xA8922            # ZamFrameList: showzam (L52079); tiles unk_A892A -> ExtraChars
ZAM_TILES = 0x7D
CD0 = 0x18CFC            # _cd0 (updatecrowdf L30050): 4 rows x 16 {frame, delay mask}
ZAM_WAVE = 0x1615E       # unk_1615E (showzam L52114): 13 words, frames 5-8
BG_TABLE = 0xFE364       # unk_FE364 (sub_FE2C8 L973476): 8 x {long script, long file}
FO_IDS = 0xFECE6         # unk_FECE6 (sub_FECAA L974897): 8 faceoff ids, then $FFFF
# File start -> the next data (the files are packed back to back).
FILE_END = {CROWD: 0xA78AE, ZAM: 0xA9A10, 0xEA2EC: 0xEAB10, 0xEAB10: 0xEB816,
            0xEB816: 0xEC284, 0xEC284: 0xED1B0, 0xED1B0: 0xEDE8A}
HOR = 0x1F               # sub_16246: horizontal mode adds $1F to the crowd frame

# What each background animation shows (read off the renders) and what starts it.
BG_INFO = [
    ("hat trick: fans behind the top goal stand with arms up (frames 1-4), hats fly over the "
     "top glass (5-12) and land on the ice around the top goal (13-15); plays once",
     "a home skater's third goal of the game (goal summary loc_1889A, L56031-56045)"),
    ("a fan in the top end stands (map x 113-135) leaves his seat, comes down to the glass, "
     "waves both arms there (frames 4-8), ducks (9) and climbs back to his seat (10-14); once",
     "faceoff (sub_FECAA table)"),
    ("id 1's fan sequence on the right of the top end stands (map x 248-264, frames 15-28); once",
     "faceoff (sub_FECAA table)"),
    ("scattered fans in the top end stands and both upper corners jump up with arms raised, a "
     "different set each frame; loops",
     "faceoff (sub_FECAA table)"),
    ("fans get up into the aisles of the upper-left corner and the top end stands (frames 1-2), "
     "shift there (3/4 alternating every 61 vblanks, 19 times) and go back (2, 1); loops",
     "none: no retail code starts id 4 (only the faceoff drop minimum tests it)"),
    ("fans walk down the aisles of the upper-left corner and the top end stands (frames 1-8); "
     "one comes down the top-right aisle to the front row behind the glass and walks right "
     "along it (9-23); once",
     "faceoff (sub_FECAA table)"),
    ("the players on both benches stand up and lean over the boards in a ripple along the "
     "bench (away bench map y 239-327 in line 3, home bench y 375-464 in line 2); loops",
     "faceoff at fox <= -64 and foy <= 192 (left lower dots, benches in view)"),
    ("id 6's bench ripple three times (30 entries), then it ends",
     "a skater checked over the left boards at -$59 <= y <= $59 (FallDown L49352)"),
]


def anim_file(rom, base):
    """Header, tiles (a Rom over bytes) and frames of a sprite "anim" file."""
    ft = base + rom.u32(base + 4)
    count = rom.u16(base + 8)
    if count & 0x8000:
        tiles = decompress(rom, base + 8)
    else:
        tiles = rom.b[base + 10:base + 10 + 32 * count]
    count &= 0x7FFF
    assert base + 10 + 32 * count <= base + rom.u32(base) <= ft, hex(base)
    assert rom.u16(ft) == 0
    n = rom.u16(ft + 2) // 2 - 2
    end = ft + rom.u16(ft + 2 * (n + 1))
    assert end == FILE_END[base], (hex(base), hex(end))
    frames = []
    for f in range(1, n + 1):
        a0, a1 = ft + rom.u16(ft + 2 * f), ft + rom.u16(ft + 2 * f + 2)
        assert a1 > a0 and (a1 - a0) % 8 == 0
        pieces = []
        for a in range(a0, a1, 8):
            w6 = rom.u16(a + 6)
            size = w6 & 0xFF
            assert size < 16 and w6 & 0x700 == 0
            p = {"x": rom.s16(a), "y": rom.s16(a + 2), "tile": rom.u16(a + 4),
                 "w": ((size >> 2) & 3) + 1, "h": (size & 3) + 1, "hf": bool(w6 & 0x800),
                 "vf": bool(w6 & 0x1000), "pal": (w6 >> 13) & 3, "prio": bool(w6 & 0x8000)}
            assert p["tile"] + p["w"] * p["h"] <= count
            pieces.append(p)
        frames.append(pieces)
    return {"base": base, "tiles": BytesRom(tiles), "count": count, "frames": frames,
            "palette": [rom.u16(base + rom.u32(base) + 2 * i) for i in range(16)]}


def piece_canvas(tiles, p):
    """One piece as the VDP draws it: tiles column-major, the piece's own flips."""
    c = Canvas(8 * p["w"], 8 * p["h"])
    for col in range(p["w"]):
        for row in range(p["h"]):
            t = p["tile"] + col * p["h"] + row
            dc = p["w"] - 1 - col if p["hf"] else col
            dr = p["h"] - 1 - row if p["vf"] else row
            c.tile(tiles, 32 * t, 8 * dc, 8 * dr, p["pal"], p["hf"], p["vf"])
    return c


class PieceSet:
    """Distinct piece images of one or more files, in first-seen order."""

    def __init__(self):
        self.keys = {}
        self.items = []

    def add(self, src, p):
        key = (src["base"], p["tile"], p["w"], p["h"], p["hf"], p["vf"], p["pal"])
        if key not in self.keys:
            c = piece_canvas(src["tiles"], p)
            self.keys[key] = len(self.items)
            self.items.append({"canvas": c, "key": key, "blank": not any(c.px[3::4])})
        return self.keys[key]

    def frames(self, src):
        out = {}
        for f, pieces in enumerate(src["frames"], 1):
            sprites = [[p["x"], p["y"], self.add(src, p)] for p in pieces]
            # The bounding box leaves out blank pieces (all colour 0: placeholders at 0,0).
            seen = [p for p, s in zip(pieces, sprites) if not self.items[s[2]]["blank"]]
            x0 = min(p["x"] for p in seen)
            y0 = min(p["y"] for p in seen)
            x1 = max(p["x"] + 8 * p["w"] for p in seen)
            y1 = max(p["y"] + 8 * p["h"] for p in seen)
            out[str(f)] = {"bbox": [x0, y0, x1 - x0, y1 - y0],
                           "lines": sorted({p["pal"] for p in seen}),
                           "sprites": sprites}
            if any(p["prio"] for p in pieces):
                out[str(f)]["priority"] = True
        return out

    def atlas(self, width):
        atlas = pack(self.items, width)
        meta = []
        for it in self.items:
            base, tile, w, h, hf, vf, pal = it["key"]
            e = {"rect": [it["atlas"][0], it["atlas"][1], 8 * w, 8 * h], "file": "%05X" % base,
                 "tile": tile, "line": pal, "hf": hf, "vf": vf}
            if it["blank"]:
                e["blank"] = True
            meta.append(e)
        return atlas, meta


class FigureSet:
    """Assembled figures of one or more files: each frame's pieces composited, in VDP link
    order, into one image per group of touching pieces (or the whole frame), deduplicated."""

    def __init__(self, whole=False):
        self.whole = whole
        self.keys = {}
        self.items = []
        self.pieces = PieceSet()

    def _groups(self, rects):
        parent = list(range(len(rects)))

        def find(i):
            while parent[i] != i:
                parent[i] = parent[parent[i]]
                i = parent[i]
            return i
        for i, a in enumerate(rects):
            for j in range(i):
                b = rects[j]
                if self.whole or (a[0] <= b[2] and b[0] <= a[2] and a[1] <= b[3] and b[1] <= a[3]):
                    parent[find(i)] = find(j)
        groups = {}
        for i in range(len(rects)):
            groups.setdefault(find(i), []).append(i)
        return sorted(groups.values(), key=lambda g: (rects[g[0]][1], rects[g[0]][0]))

    def _add(self, canvas):
        key = (canvas.w, canvas.h, bytes(canvas.px))
        if key not in self.keys:
            self.keys[key] = len(self.items)
            self.items.append({"canvas": canvas})
        return self.keys[key]

    def frames(self, src):
        out = {}
        for f, pieces in enumerate(src["frames"], 1):
            drawn = []
            for p in pieces:
                pid = self.pieces.add(src, p)
                if not self.pieces.items[pid]["blank"]:
                    drawn.append((p, self.pieces.items[pid]["canvas"]))
            # Touching counts: rects are inclusive of their right/bottom edge here.
            rects = [(p["x"], p["y"], p["x"] + 8 * p["w"], p["y"] + 8 * p["h"]) for p, _ in drawn]
            parts = []
            for g in self._groups(rects):
                x0 = min(rects[i][0] for i in g)
                y0 = min(rects[i][1] for i in g)
                x1 = max(rects[i][2] for i in g)
                y1 = max(rects[i][3] for i in g)
                c = Canvas(x1 - x0, y1 - y0)
                # Link order: the first piece is in front, so it is painted last.
                for i in sorted(g, reverse=True):
                    p, pc = drawn[i]
                    for yy in range(pc.h):
                        for xx in range(pc.w):
                            o = (yy * pc.w + xx) * 4
                            if pc.px[o + 3]:
                                d = ((p["y"] - y0 + yy) * c.w + (p["x"] - x0 + xx)) * 4
                                c.px[d:d + 4] = pc.px[o:o + 4]
                parts.append([x0, y0, self._add(c)])
            bx0 = min(r[0] for r in rects)
            by0 = min(r[1] for r in rects)
            out[str(f)] = {"bbox": [bx0, by0, max(r[2] for r in rects) - bx0,
                                    max(r[3] for r in rects) - by0],
                           "lines": sorted({p["pal"] for p, _ in drawn}),
                           "parts": parts}
        return out

    def atlas(self, width):
        atlas = pack(self.items, width)
        meta = []
        for it in self.items:
            c = it["canvas"]
            lines = sorted({c.px[o + 1] // 85 for o in range(0, len(c.px), 4) if c.px[o + 3]})
            meta.append({"rect": [it["atlas"][0], it["atlas"][1], c.w, c.h], "lines": lines})
        return atlas, meta


def write_json(path, obj):
    with open(path, "w") as f:
        json.dump(obj, f, indent=1, sort_keys=False)
        f.write("\n")


def crowd(rom, out):
    src = anim_file(rom, CROWD)
    assert src["count"] == CROWD_TILES and len(src["frames"]) == 2 * HOR
    ps = FigureSet()
    frames = ps.frames(src)
    atlas, pieces = ps.atlas(512)
    atlas.save(os.path.join(out, "crowd_idx.png"))
    cd0 = [[[rom.u8(CD0 + 32 * r + 2 * k), rom.u8(CD0 + 32 * r + 2 * k + 1)] for k in range(16)]
           for r in range(4)]
    write_json(os.path.join(out, "crowd.json"), {
        "source": "CrowdFrameList $A4B54 (showcrowd L52175, sub_16246 L52223), %d raw tiles" % src["count"],
        "space": {"1-31": "rink map pixels (rink/map.json; map_px = rink_x + 192, 368 - rink_y)",
                  "32-62": "screen pixels of the 256x224 side view (horizontal mode, sflags bit 7)"},
        "order": "parts are assembled figures (pieces composited in VDP link order); they do not overlap",
        "atlas": [atlas.w, atlas.h],
        "sprites": pieces,
        "groups": {"crowd": list(range(1, 0x13)), "flash": list(range(0x13, 0x1A)),
                   "box_away": [0x1A, 0x1B, 0x1C], "box_home": [0x1D, 0x1E, 0x1F]},
        "group_notes": {
            "crowd": "crowdframe low byte: fans over the stands all round the rink; 1-13 small "
                     "moves (22-33 hardware sprites), 14-18 many fans standing (76-80)",
            "flash": "crowdframe high byte: camera flashes (2x2-tile stars, line 0) at scattered seats",
            "box_away": "PBnum low nibble n: frames $1A..$1A+n-1, one seated player each "
                        "(right-hand box, map y 286-338; jersey line 3, legs line 2)",
            "box_home": "PBnum high nibble n: frames $1D..$1D+n-1 (box map y 375-426, line 2)"},
        "horizontal_offset": HOR,
        "cd0": cd0,
        "cd0_note": "updatecrowdf: row = (min(crowdlevel >> 1, $7F) & $60) / $20, column = crowdstep / 2; "
                    "[frame, delay mask], crowdcnt = mask + (VDP counter & mask)",
        "frames": frames})
    return src, frames, pieces


def bganim(rom, out):
    ps = FigureSet()
    files = {}
    srcs = {}
    ids = []
    for i in range(8):
        script_a, file_a = rom.u32(BG_TABLE + 8 * i), rom.u32(BG_TABLE + 8 * i + 4)
        if file_a not in srcs:
            srcs[file_a] = anim_file(rom, file_a)
        script = []
        a = script_a
        while True:
            fr, d = rom.s8(a), rom.s8(a + 1)
            a += 2
            if fr in (-1, -2):
                break
            assert 1 <= fr <= len(srcs[file_a]["frames"]) and d >= 0
            script.append([fr, d])
        ids.append({"id": i, "file": "%05X" % file_a, "script_address": "%05X" % script_a,
                    "script": script, "end": "loop" if fr == -1 else "stop",
                    "vblanks": sum(d + 1 for _, d in script),
                    "shows": BG_INFO[i][0], "trigger": BG_INFO[i][1]})
    for file_a in sorted(srcs):
        src = srcs[file_a]
        assert src["count"] <= 0x32, "more tiles than the $32 reserved at word_FFD6AC"
        files["%05X" % file_a] = {"tiles": src["count"], "frames": ps.frames(src)}
    atlas, pieces = ps.atlas(512)
    atlas.save(os.path.join(out, "bganim_idx.png"))
    fo = []
    a = FO_IDS
    while rom.u16(a) != 0xFFFF:
        fo.append(rom.u16(a))
        a += 2
    write_json(os.path.join(out, "bganim.json"), {
        "source": "unk_FE364 (sub_FE2C8 L973464, sub_FE326, sub_FD78A L970856); tiles at file + 8 "
                  "loaded to word_FFD6AC ($32 tiles reserved)",
        "space": "rink map pixels (rink/map.json; map_px = rink_x + 192, 368 - rink_y)",
        "order": "parts are assembled figures (pieces composited in VDP link order); they do not overlap",
        "atlas": [atlas.w, atlas.h],
        "sprites": pieces,
        "faceoff_ids": fo,
        "faceoff_left_low_id": 6,
        "ids": ids,
        "files": files})
    return srcs, files, ids, pieces


def zamboni(rom, out):
    src = anim_file(rom, ZAM)
    assert src["count"] == ZAM_TILES and len(src["frames"]) == 8
    ps = FigureSet(whole=True)
    frames = ps.frames(src)
    atlas, pieces = ps.atlas(256)
    atlas.save(os.path.join(out, "zamboni_idx.png"))
    wave = [rom.u16(ZAM_WAVE + 2 * k) for k in range(13)]
    write_json(os.path.join(out, "zamboni.json"), {
        "source": "ZamFrameList $A8922 (showzam L52076, SetSframe L52164), %d raw tiles at $A892C "
                  "loaded to ExtraChars by Intermission" % src["count"],
        "space": "pixels relative to the zamboni origin; the origin is at side-view screen pixel "
                 "((zamx >> 2) - 128, $12A - 128 = 170)",
        "order": "each frame is one assembled image; showzam links frame 1 (body), then 2-4 "
                 "(wheels), then 5-8 (driver): the body is in front",
        "atlas": [atlas.w, atlas.h],
        "sprites": pieces,
        "zamx_start": 0x140, "zamx_last": 0x709, "y": 0x12A,
        "body": 1, "wheels": [2, 3, 4], "driver": [5, 6, 7, 8],
        "wave": wave,
        "wave_note": "home leading: k = clamp((zamx >> 2) - $DA, 0) >> 2, frame = wave[min(k, 12)]; "
                     "otherwise frame 5",
        "frames": frames})
    return src, frames, pieces


def main():
    rom_path = sys.argv[1] if len(sys.argv) > 1 else "lst/nhl94.bin"
    out = sys.argv[2] if len(sys.argv) > 2 else "godot/assets/arena"
    with open(rom_path, "rb") as f:
        data = f.read()
    assert zlib.crc32(data) & 0xFFFFFFFF == ROM_CRC, "unexpected ROM"
    rom = Rom(data)
    os.makedirs(out, exist_ok=True)
    _, cf, cp = crowd(rom, out)
    _, bf, ids, bp = bganim(rom, out)
    _, zf, zp = zamboni(rom, out)
    print("wrote crowd (%d frames, %d figures), bganim (%d ids, %d files, %d figures), zamboni (%d frames, "
          "%d figures) to %s" % (len(cf), len(cp), len(ids), len(bf), len(bp), len(zf), len(zp), out))


if __name__ == "__main__":
    main()
