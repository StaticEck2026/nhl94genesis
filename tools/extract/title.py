#!/usr/bin/env python3
"""Export the title screen (newTitleScreen, $FF042) as loose files for the Godot port.

Offline only. The game never reads a ROM; it loads godot/assets/title/<edition>/.
Usage: python3 tools/extract/title.py [nhl94-patches checkout] [godot/assets/title]

Editions: "retail" from lst/nhl94.bin; "fight" from the fight patch's built ROM
(94_fight/output/nhl94_fight_v1.01.bin in a checkout of github.com/Chaos81/nhl94-patches,
MIT), whose title_patch.asm and credits_patch.asm swap in a new photo, shield, NHLPA logo
and title, a font colour remap and new credits. Every parameter is read from the ROM
(the image pointers in the code, the printz strings, the remap bytes at $FF210, the
credits addresses), so one decoder serves both. Spec: docs/specs/title_screen.md.

The screen is H32 (256x224). Writes per edition, index textures as in assets.py
(R = colour * 17, G = palette line * 85, A = 0 for colour 0):
  win_lo_idx.png, win_hi_idx.png   the window plane (photo rows 0-22, lines 0-183),
                                   split by tile priority
  b_lo_idx.png, b_hi_idx.png       plane B (photo rows 23-27, the shield, NHLPA logo
                                   and title), split by priority; it is line-scrolled
  font_idx.png                     the 94 font tiles after the remap table, 16 a row
  title.json                       the faded-in CRAM (palfadenew), plane B's initial
                                   line scroll, the glyph map and the credits blocks
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from assets import Canvas, Rom, decompress  # noqa: E402

FIGHT_ROM = "94_fight/output/nhl94_fight_v1.01.bin"
FONT = 0xAAC52          # the font's "jim" header: tiles at +10, glyph map via the long at +4
W, H = 256, 224
WIN_ROWS = 0x17         # VDP reg $92 = $17: the window covers rows 0-22 (lines 0-183)
# movea.l #imm,a0 operands in newTitleScreen, and the printz strings it uses.
BG_PTR, BG_PTR2, SHIELD_PTR, PA_PTR, TITLE_PTR = 0xFF10E, 0xFF140, 0xFF17E, 0xFF1AA, 0xFF1D6
SHIELD_PZ, PA_PZ, TITLE_PZ, CREDITS_PZ = 0xFF176, 0xFF1A2, 0xFF1CE, 0xFF28A
REMAP = 0xFF210
TEXT_FIRST_PTR, TEXT_LOOP_PTR = 0xFF226, 0xFF292


def s16(v):
    return v - 0x10000 if v & 0x8000 else v


class Img:
    """A dobitmap image: long palette offset, long map offset, word tile count (bit 15:
    compressed), tiles, palette lines, map (w, h, entries)."""

    def __init__(self, rom, base):
        self.base = base
        pal_off = rom.u32(base)
        map_off = rom.u32(base + 4)
        n = rom.u16(base + 8)
        self.count = n & 0x7FFF
        self.tiles = decompress(rom, base + 8) if n & 0x8000 else rom.b[base + 10:base + 10 + 32 * self.count]
        p = base + pal_off
        self.pal = [[rom.u16(p + 32 * k + 2 * i) for i in range(16)] for k in range((map_off - pal_off) // 32)]
        m = base + map_off
        self.w, self.h = rom.u16(m), rom.u16(m + 2)
        self.cells = [rom.u16(m + 4 + 2 * i) for i in range(self.w * self.h)]


def tile_pixels(buf, off):
    out = []
    for y in range(8):
        for x in range(4):
            v = buf[off + y * 4 + x]
            out += [v >> 4, v & 15]
    return out


def printz(rom, a):
    """The command form of a printz string: (printa, x, y)."""
    c = rom.b[a + 2]
    v = (-s16(0xFF00 | c)) & 0x7F
    return (v << 9) & 0xF800, rom.b[a + 3], rom.b[a + 4]


def credits(rom, first, loop):
    """The first block and the loop's blocks as [printx, text] lines (sub_FF2C8: a line
    starts at column $11 - length/2; a negative second word ends a block or the list)."""
    def block(a):
        lines = []
        while True:
            n = rom.u16(a)
            text = rom.b[a + 2:a + n].replace(b"\x00", b"").decode("latin-1")
            lines.append([0x11 - (s16(n) >> 1), text])
            a += n
            if s16(rom.u16(a + 2)) < 0:
                return lines, a
    b0, _ = block(first)
    blocks = []
    a = loop
    while True:
        b, a = block(a)
        blocks.append(b)
        a += rom.u16(a)
        if s16(rom.u16(a + 2)) < 0:
            break
    return b0, blocks


def edition(rom, out):
    bg = Img(rom, rom.u32(BG_PTR))
    assert rom.u32(BG_PTR2) == bg.base
    logos = [(Img(rom, rom.u32(SHIELD_PTR)), printz(rom, SHIELD_PZ)),
             (Img(rom, rom.u32(PA_PTR)), printz(rom, PA_PZ)),
             (Img(rom, rom.u32(TITLE_PTR)), printz(rom, TITLE_PZ))]
    layers = {k: Canvas(W, H) for k in ("win_lo", "win_hi", "b_lo", "b_hi")}

    def draw(img, sx, sy, w, h, x0, y0, xor, plane):
        for r in range(h):
            for c in range(w):
                e = img.cells[(sy + r) * img.w + sx + c] ^ xor
                px = tile_pixels(img.tiles, 32 * (e & 0x7FF))
                cv = layers[plane + ("_hi" if e & 0x8000 else "_lo")]
                for yy in range(8):
                    for xx in range(8):
                        cv.put((x0 + c) * 8 + (7 - xx if e & 0x800 else xx),
                               (y0 + r) * 8 + (7 - yy if e & 0x1000 else yy), px[yy * 8 + xx], (e >> 13) & 3)

    # dobitmap: the photo's rows 0-22 to the window, rows 23-27 to plane B at row 23.
    draw(bg, 0, 0, bg.w, WIN_ROWS, 0, 0, 0, "win")
    draw(bg, 0, WIN_ROWS, bg.w, bg.h - WIN_ROWS, 0, WIN_ROWS, 0, "b")
    for img, (printa, x, y) in logos:
        draw(img, 0, 0, img.w, img.h, x, y, printa, "b")
    os.makedirs(out, exist_ok=True)
    for k, cv in layers.items():
        cv.save(os.path.join(out, "%s_idx.png" % k))

    # palfadenew: the dobitmap palette masks are $F (photo), 8 (shield), 0 (logo), 8
    # (title); then clr.w palfadenew (the backdrop colour).
    target = [[0] * 16 for _ in range(4)]
    for img, mask in ((bg, 0xF), (logos[0][0], 8), (logos[1][0], 0), (logos[2][0], 8)):
        for k in range(4):
            if mask >> k & 1:
                target[k] = list(img.pal[k])
    target[0][0] = 0

    # The font through the remap table (remap L44006: colour n -> a nibble of table[n/2]).
    table = rom.b[REMAP:REMAP + 8]
    count = rom.u16(FONT + 8)
    font = Canvas(16 * 8, ((count + 15) // 16) * 8)
    printa, _, _ = printz(rom, CREDITS_PZ)
    line = (printa >> 13) & 3
    for t in range(count):
        px = tile_pixels(rom.b, FONT + 10 + 32 * t)
        for i, n in enumerate(px):
            m = (table[n >> 1] >> 4) if n % 2 == 0 else (table[n >> 1] & 15)
            font.put((t % 16) * 8 + i % 8, (t // 16) * 8 + i // 8, m, line)
    font.save(os.path.join(out, "font_idx.png"))
    gm = FONT + rom.u32(FONT + 4)
    gw, gh = rom.u16(gm), rom.u16(gm + 2)
    glyphs = {str(c): rom.u16(gm + 4 + 2 * c) for c in range(gw * gh) if c < 0x80}

    # sub_FF3B0: plane B's initial line scroll (the logos start off screen).
    hs = [0] * H
    d1 = 0xFD80
    for i, d0 in enumerate(range(0x50, -1, -1)):
        hs[i] = s16(d1)
        if d0 & 1 == 0:
            d1 = (d1 - 1) & 0xFFFF
    for j in range(0x61):
        hs[0x51 + j] = 0x100 + 4 * j
    first, blocks = credits(rom, rom.u32(TEXT_FIRST_PTR), rom.u32(TEXT_LOOP_PTR))
    meta = {
        "source": "newTitleScreen $FF042; photo $%X, shield $%X, NHLPA logo $%X, title $%X, credits $%X"
                  % (bg.base, logos[0][0].base, logos[1][0].base, logos[2][0].base, rom.u32(TEXT_FIRST_PTR)),
        "size": [W, H],
        "window_rows": WIN_ROWS,
        "cram": target,
        "hscroll_b": hs,
        "font": {"line": line, "glyphs": glyphs, "blank": 0x7FF},
        "credits_first": first,
        "credits_loop": blocks,
    }
    with open(os.path.join(out, "title.json"), "w") as f:
        json.dump(meta, f, separators=(",", ":"))
    return len(blocks)


def main():
    out = sys.argv[2] if len(sys.argv) > 2 else "godot/assets/title"
    n = edition(Rom(open("lst/nhl94.bin", "rb").read()), os.path.join(out, "retail"))
    print("retail title: %d credit blocks" % n)
    if len(sys.argv) > 1:
        n = edition(Rom(open(os.path.join(sys.argv[1], FIGHT_ROM), "rb").read()), os.path.join(out, "fight"))
        print("fight patch title: %d credit blocks" % n)


if __name__ == "__main__":
    main()
