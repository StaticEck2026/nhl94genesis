# NHL '94 (Genesis): title screen (`newTitleScreen`) and the 94_fight replacement

Source: `lst/nhl94.bin.lst` (IDA listing, no address column; line numbers written `Lnnnnn`) and `lst/nhl94.bin` (CRC32 `$9438F5DD`). ROM addresses are written `$xxxxx`. The listing mis-decodes most of the inline data in this routine. Every `printz` string, immediate operand and table below was therefore read from the ROM bytes, not from the listing. The patched variant is `/home/user/chaos81/nhl94-patches/94_fight/output/nhl94_fight_v1.01.bin` (3 MB). All five pointer patches, the remap-byte patch, `data/title_screen.bin` at `$11259C` and `data/scroll_text.bin` at `$5776` are present in it byte-for-byte. Inside `newTitleScreen` (`$FF040-$FF470`), the only bytes that differ from retail are those 17 bytes (§12.2). The code the title uses (`dobitmap`, `print`, `remap`, `cramfade`, the font at `$AAC52`) is identical in both ROMs.

A Python prototype rebuilds the screen from ROM data, frame by frame, for both ROMs (§13). Its renders match the known title screen, so the decoding below is confirmed and not just inferred.

---

## 0. Quick facts

- **The screen is H32: 256x224, not 320x224.** `newTitleScreen` sets `disflags` bit 1 (`df32c`), so `setvram` writes reg `$8C00` (32-cell mode) instead of `$8C81`. See §11 for how to show it in the 320x224 viewport.
- **Four layers:**
  - **Window plane:** the photo background, cell rows 0-22, screen lines 0-183. Static.
  - **Plane B:** three logos (NHL shield, NHLPA logo, "NHL HOCKEY 94" title) with high priority, which slide in using per-line H-scroll. Plane B also holds the bottom 5 rows of the background, static at lines 184-223.
  - **Plane A:** the credits text, palette line 1. It is visible only in lines 184-223, because the window replaces plane A above that. Plane A scrolls vertically.
  - **Backdrop:** black.
- **Timeline at 60 Hz:**
  - The palette fades in during frames 8-32.
  - The logos slide in during frames 82-115.
  - The first credits block (©/Licensed by/Sega) shows from frame 1 to 191.
  - After that, each further block scrolls up 40 px over 80 frames, then holds for 121 frames.
  - The routine returns by itself after the last block: frame 4211 retail, frame 4412 patched.
- **Exit:** only a **new Start press** on pad 1 or 2 (pads 1-4 in 4-way mode) exits, checked every frame. A/B/C do nothing. Song `$78` starts on frame 1 and keeps playing into the menus. On exit the next screen (`setoptions` → `setvram`) fades the frozen title to black in 25 frames.

---

## 1. Call path

| Step | Where | What |
|---|---|---|
| `Begin` | L29715 | Clears RAM `$FFB000-$FFDEF4` (so `SortCords` is all zero). Then `EASportsScreen`, `InitSaveRAM`, `sub_FE660`, `HiScoreScreen`, `LoadDefMenuOptions`, `orjoy` (latches pad edges), `jmp Opening`. |
| `Opening` | L53865, `$172F0` | `KillCrowd` (PSG off), `jsr newTitleScreen` (`$FF042`; the `rts` at `$FF040` ends the previous routine). |
| `newTitleScreen` | L975270, `$FF042-$FF2C7` | This spec. |
| `Opening2` | L53868, `$172FA` | `KillCrowd`, `sr=$2700`, clears RAM `$FFB000-$FFD03E`, `GameSetUp` (menus, L960187). |

The title is shown **only at boot**. After a game ends (`GameOver` L53851), the code plays song `$78` and jumps straight to `Opening2`, so it skips the title.

Routines used: `setvram` L44784, `Vmaddr` L44855, `dobitmap` L44878 (`$1169A`), `sub_1172C` L44933, `sub_1173C` L44948, `sub_1177A` L44975 (decompressor), `remap` L44006, `cramfade` L44101 (`$10FB6`), `forcefade` L44081, `xyVmMap` L45212, `eraser` L45234 (`$1197E`), `printz` L45500 (`$11B92`), `print` L45521, `orjoy` L44438 (`$112BC`), `ReadJoy1` L44509, `song` L44297 (`$11156`), `MusicVB` L61792 (`$1A50A`, also reads the pads via `ReadJoyData` L61633). Title-local routines: `sub_FF2C8` L975462 (print a credits block), `sub_FF318` L975491 (wait one frame + Start check), `loc_FF348` L975511 (VBlank handler), `sub_FF3B0` L975538 (line-scroll table init), `sub_FF3F8` L975563 (line-scroll animation).

### RAM used (from `src/stubinc/ram_addrs.inc` and the code bytes)

| Name | Address | Use here |
|---|---|---|
| `VSCRLPM`, `VSPRITES` | `$FFB000`, `$FFB002` | VRAM addresses of the H-scroll table (`$FC00`) and the sprite table (`$F800`) |
| `VmMap1/Map1col1` | `$FFB004/6` | plane A name table `$C000`, row shift 7 (128 cells per row) |
| `VmMap2/Map2col1` | `$FFB008/A` | plane B name table `$A000`, row shift 7 |
| `VmMap3/Map3col1` | `$FFB00C/E` | window name table `$F000`, row shift 5 (32 cells per row) |
| `word_FFB012` | `$FFB012` | font base tile (`print` adds it to each glyph) |
| `printx/printy/printa/printm` | `$FFB028/2A/2C/2E` | print cursor, attribute (`$F800` bits), map select (0=A, 4=B, 8=window) |
| `vbint` | `$FFB03A` | VBlank vector, set to `loc_FF348` |
| `vcount` | `$FFB03E` | incremented every VBlank |
| `SortCords` | `$FFB04A` | reused as the 224-line H-scroll table (224 longs: plane A word, plane B word) |
| `word_FFB8B2` | `$FFB8B2` | first-block hold counter (`$104`, -2 per frame) |
| `Hscroll` | `$FFBD1E` | reused as the slide speed (`$14` = 20 px/frame) |
| `Vscroll` | `$FFBD20` | plane A V-scroll (credits) |
| `palcount` | `$FFBD26` | fade counter (`cramfade`) |
| `palfadenew` | `$FFBD28` | 4x16 CRAM target colors |
| `word_FFBF12` | `$FFBF12` | saves `d4` (next free tile) across the second background call |
| `word_FFBF14` | `$FFBF14` | slide start delay (`$50` = 80 VBlanks) |
| `disflags` | `$FFBF78` | bit 1 `df32c` (H32 mode), bit 2 `dfng` (VBlank: skip DMA/fade) |
| `word_FFC2F8` | `$FFC2F8` | bit 0: `dobitmap` skips the tile upload. Bit 3 selects the alt font (clear here). |

Also set but never read by the title code: `word_FFB8AE=$120`, `word_FFB8B0=$D0`, `asv=0`, `DispAttribCtr ($FFD5AC)=$FFCE`, `dword_FFBDA8=0` and `word_FFBDAC=0` (the bytes right after `palfadenew`). Later screens use them, so a port of this screen can ignore them.

---

## 2. VDP setup

From `$FF042`, with interrupts off (`sr=$2700`):

1. Seed `RNGseed` from the HV counter. This only matters for the port's RNG. Set `vbint = loc_FF348` and set `disflags` bit 1 (H32).
2. Write the RAM VDP variables listed in §1: plane A `$C000`, plane B `$A000`, window `$F000`, sprites `$F800`, H-scroll `$FC00`, `Map1col1=Map2col1=7`, `Map3col1=5`.
3. `setvram(d0=0)`:
   - `palfadenew` = 64 zeros, `palcount=$18`, `forcefade`. This fades the previous screen's CRAM to black over 25 VBlanks and waits until it is done.
   - Clears all 64 KB of VRAM and sets auto-increment 2.
   - Mode registers: `$8C00` (H32, no shadow/interlace), `$8004`, `$8164` (display on, VInt on, mode 5).
   - `$9003`: plane size 128x32 cells, because `Map1col1 != 6`.
   - `$8230` (A=`$C000`), `$8405` (B=`$A000`), `$833C` (window `$F000`), `$857C` (sprites `$F800`), `$8D3F` (H-scroll `$FC00`).
   - `$9100`, `$9200`, `$8700` (backdrop = palette 0 color 0), `$8B00`.
   - VSRAM A and B = 0.
4. Then `newTitleScreen` writes:
   - `$9100`: window H = 0, so there is no horizontal window.
   - `$9217`: window from the top down to cell row `$17` = 23 → **lines 0-183, full width**. The window replaces plane A there.
   - `$8B03`: **H-scroll per line** (bits 0-1 = 3), V-scroll full screen.
5. `clr.w Vscroll`.

**VRAM map.** The window, sprite table and H-scroll table all live inside `$E000-$FFFF`. The free space for tiles is therefore `$0000-$9FFF` (1280 tiles) plus `$E000-$EFFF`. Tile `$7FF` (VRAM `$FFE0`) lies past the H-scroll table (`$FC00-$FF7F`) and is all zero. The erasers use it as the transparent blank tile.

| VRAM | Content |
|---|---|
| `$0000-` | tiles: background, shield, PA logo, title, font (§5.4) |
| `$A000-$BFFF` | plane B name table, 128x32 |
| `$C000-$DFFF` | plane A name table, 128x32 |
| `$F000-$F7FF` | window name table, 32x32 (H32 → 32-cell rows) |
| `$F800-` | sprite table (all zero → no sprites. `word_FFC2E8`=0, so the VBlank never DMAs `Satt`) |
| `$FC00-$FF7F` | H-scroll table, 224 lines x (A word, B word), DMA'd from `SortCords` every VBlank |

---

## 3. `newTitleScreen` step by step (ROM bytes decoded)

### 3.1 The `printz` inline strings

`printz` (`$11B92`) reads a string that follows the `jsr` and returns past it. The format is a word length L (counts itself), then L-2 bytes. In `print` (L45521) each byte means:

- `$00`: skipped. It does not use a column.
- `$80-$FF` (negative): a command. Let `v = -byte`. Then:
  - `printa = (v << 9) & $F800`, so bits 2-3 of v = h/v flip, bits 4-5 = palette, bit 6 = priority.
  - `printm = (v & 3) * 4 - 4`: 1 → plane A, 2 → plane B, 3 → window.
  - The next byte is `printx` and the one after is `printy` (both signed). The command uses 3 bytes in total.
- `'@'` ($40): writes the blank tile `$7FF`.
- `'^'` ($5E): advances `printx` by one column without writing.
- Any other byte c: writes the name-table word `fontmap[c] + word_FFB012 + printa` and advances `printx`.

| `jsr printz` at | inline bytes | decoded | followed by |
|---|---|---|---|
| `$FF0BC` | `00 06 FF 00 00 00` | plane A, attr 0, x=0 y=0 | `move.l #$80,d0; moveq #$20,d1; move.l #$7FF,d2; jsr eraser`. Fills **plane A** 128x32 with `$7FF`. IDA shows this as `ori.b` garbage. |
| `$FF0DC` | `00 06 FE 00 00 00` | plane B, attr 0, x=0 y=0 | same eraser: fills **plane B** 128x32 with `$7FF` |
| `$FF100` | `00 06 FD 00 00 00` | **window**, attr 0, x=0 y=0 | background, rows 0-22 |
| `$FF132` | `00 06 FE 00 17 00` | **plane B**, attr 0, x=0 y=23 | background, rows 23-27 |
| `$FF170` | `00 06 BE 01 01 00` | **plane B**, attr `$8000` (priority), x=1 y=1 | NHL shield |
| `$FF19C` | `00 06 BE 19 01 00` | **plane B**, attr `$8000`, x=25 y=1 | NHLPA logo |
| `$FF1C8` | `00 06 BE 01 0E 00` | **plane B**, attr `$8000`, x=1 y=14 | title |
| `$FF218` | `00 06 EF 00 00 00` | **plane A**, attr `$2000` (palette 1), x=0 y=0 | first credits block |
| `$FF284` | `00 06 EF 00 00 00` | same | credits loop |

### 3.2 The `dobitmap` calls

`dobitmap` takes these registers. Before the call, the caller sets `a0 = img + long0` (palette), `a1 = img + long1` (map) and `a2 = img + 8` (the tile-count word).

| Register | Meaning |
|---|---|
| `d0` | source column in the image map |
| `d1` | source row in the image map |
| `d2` | width in cells |
| `d3` | height in cells |
| `d4` | first VRAM tile (it is added to every map word, and returned increased by the tile count) |
| `d5` | palette-line mask |

The destination is (`printx`, `printy`) on map `printm`. Each written word = `(mapword + d4) XOR (printa & $F800)`.

| # | Image (retail / patched) | d0 | d1 | d2 | d3 | d4 | d5 | Destination | Palette / priority on screen |
|---|---|---|---|---|---|---|---|---|---|
| 1 | `TitleScreenImg` `$4E45C` / `$11259C` | 0 | 0 | map w (32) | `$17` (23) | 0 | `$F` (lines 0-3) | window (0,0): screen 0..255 x 0..183 | the map's own palette bits (retail lines 0/1/2, patched 0), low priority |
| 2 | same image, `word_FFC2F8` bit 0 set (no tile upload) | 0 | `$17` | 32 | 5 | 0 (the `d4` saved on the stack) | 0 | plane B (0,23): screen 0..255 x 184..223 | line 2 (retail) / 0 (patched), low priority. These lines' H-scroll stays 0. |
| 3 | `NHLShieldImg` `$52DAA` / `$119D2C` | 0 | 0 | w | h | `word_FFBF12` (= bg tile count) | 8 (line 3) | plane B (1,1): screen (8,8) | map's lines (retail 0/1, patched 1), **XOR → priority 1** |
| 4 | `PAlogoImg` `$5338C` / `$11A52A` | 0 | 0 | w | h | running | 0 | plane B (25,1): screen (200,8) | map's lines (retail 0/1, patched 2), priority 1 |
| 5 | `TitleImg` `$5394E` / `$11AC18` | 0 | 0 | w | h | running | 8 (line 3) | plane B (1,14): screen (8,112) | line 3, priority 1 |

Code fragments (ROM): `$FF10C movea.l #img,a0 / movea.l a0,a1 / movea.l a0,a2 / adda.l (a2)+,a0 / adda.l (a2)+,a1 / clr.w d0 / clr.w d1 / move.w (a1),d2 / move.w #$17,d3 / moveq #$F,d5 / jsr dobitmap / move.w d4,word_FFBF12 / move.w (sp)+,d4`. Calls 3-5 use `move.w 2(a1),d3`, so they draw the whole map. No map word in any of the 8 images has bit 15 set, so the XOR always sets priority.

### 3.3 After the bitmaps (`$FF1F4-$FF268`)

```
clr.w  palfadenew            ; line 0 color 0 (backdrop) = black
clr.l  $FFBDA8 / clr.w $FFBDAC
move.w d4,word_FFB012        ; font base tile = next free tile
movea.l #$AAC5A,a2           ; font tile-count word
jsr    sub_1172C             ; upload font through the 8-byte inline remap table at $FF210
  dc.b $0D,$10,$45,$67,$89,$AB,$CD,$EF   (patched: $0E,$F0,$45,...)
jsr printz  00 06 EF 00 00 00 ; plane A, palette 1, (0,0)
movea.l #$5776,a1 ; jsr sub_FF2C8   ; print block 0 (Vscroll = 0 → rows 28..)
addi.w #$20,Vscroll          ; Vscroll = 32
move.w #$104,word_FFB8B2     ; 260
move.w #$120,word_FFB8AE / move.w #$D0,word_FFB8B0 / clr.w asv / move.w #$FFCE,DispAttribCtr   ; unused here
move.w #$20,palcount         ; start the fade-in
move.w #$78,-(sp) ; jsr song ; title music
bsr sub_FF3B0                ; build the line-scroll table, slide delay 80
move #$2500,sr               ; VBlank on: everything below is frame-driven
```

### 3.4 Main loop (`$FF26A-$FF2C6`)

```
do { sub_FF318 } while (word_FFB8B2 != 0)       ; 130 frames
d3=$3C: dbf → sub_FF318 x 61                    ; 61 frames
printz 00 06 EF 00 00 00                        ; reset print state
a1 = $57B8
loop:
  sub_FF2C8                                      ; print a block (a1 → the separator)
  a1 += (a1).w                                   ; skip the 4-byte separator
  40 times: sub_FF318; sub_FF318; Vscroll += 1  ; 80 frames, 40 px
  d4=$78: dbf → sub_FF318 x 121                 ; 121 frames
  if (2(a1).w >= 0) goto loop
rts                                              ; → Opening2 → menus
```

`sub_FF318` (L975491) waits until `vcount` changes, so **one call = one frame**. It then does `word_FFB8B2 -= 2` (clamped at 0) and calls `orjoy`. If `d1` bit 7 (Start, new press) is set, it does `addq #4,sp`, so the `rts` returns straight to `Opening2` from whatever loop was running.

---

## 4. Screen composition (final, settled frame)

From back to front, by VDP priority (no sprites):

1. **Backdrop**: CRAM line 0 color 0 = `$000` (black). It shows only where every layer has color 0.
2. **Low priority**: plane A over plane B. Lines 0-183 show the **window** in place of plane A. Lines 184-223 show plane A, which holds the credits.
   - Lines 0-183: background rows 0-22 (window).
   - Lines 184-223: credits text (plane A) over background rows 23-27 (plane B).
3. **High priority**, plane B: shield, PA logo, title. Their color-0 pixels show the window/background through.

| Element | Screen rect when settled (H32 px) | Layer |
|---|---|---|
| background | (0,0)-(255,223), 32x28 cells | window rows 0-22 + plane B rows 23-27 |
| NHL shield | x 8..55, y 8..63 (retail 6x7) / x 8..63, y 8..71 (patched 7x8) | plane B hi |
| NHLPA logo | x 200..247, y 8..63 (6x7) / y 8..71 (6x8) | plane B hi |
| title | x 8..247, y 112..159 (30x6, both) | plane B hi |
| credits strip | y 184..223, clipped at 184 by the window | plane A lo, palette 1 |

---

## 5. Bitmap image format ("map.jim", same as the rink files)

```
+0  long  pal_off   offset from the image start to the palette  (= 10 + 32*tiles)
+4  long  map_off   offset to the map                          (= pal_off + palette bytes)
+8  word  count     tile count; bit 15 set = compressed tile stream follows (sub_1177A)
+10       tiles     count * 32 bytes, 4bpp 8x8, row-major, high nibble = left pixel
pal_off   palette   (map_off - pal_off) bytes = CRAM words, 16 per line (all 8 images: 128 bytes = 4 lines)
map_off   word w, word h, then w*h words (row-major): VDP name-table words
          bit 15 priority, 14-13 palette line, 12 v-flip, 11 h-flip, 10-0 tile (relative to the image)
```

`tools/extract/assets.py:jim()` parses exactly this header, but it asserts that the tiles are uncompressed.

### 5.1 Tile upload (`dobitmap` end → `sub_11738` → `sub_1173C`)

Unless `word_FFC2F8` bit 0 is set, `dobitmap` ends by clearing `dword_FFCF32` (no remap) and falling into `sub_1173C` with `a2` = the count word. The VRAM address is `d4*32`.

- **count = 0:** nothing.
- **count > 0:** `d4 += count`, then DMA `count*16` words. If `dword_FFCF32` ≠ 0, the tiles go through `remap` instead.
- **count < 0 (bit 15):** `d4 += count & $7FFF`, then `sub_1177A` decompresses. This is the 256-byte ring decoder already ported as `assets.py:decompress()`. `sub_11924` flushes each 256-byte ring chunk to VRAM, through `remap` too when `dword_FFCF32` ≠ 0.

None of the 8 title images and not the font is compressed (checked: bit 15 clear in all). An extractor should still accept compressed blobs through `decompress()`.

### 5.2 Palette load (`dobitmap` start)

`a0` = image palette, `a3` = `palfadenew`. The code shifts `d5` right once per line. If the carry is set, it copies 32 bytes to palfadenew line k. Either way, both pointers move on by 32. It stops when `d5` reaches 0. So bit k of `d5` copies **image palette line k → CRAM target line k**, at the same line index. Nothing is written to CRAM directly. `cramfade` moves CRAM toward `palfadenew` (§6).

Resulting `palfadenew` after setup (CRAM words `----BBB-GGG-RRR-`):

**Retail.**
- Lines 0-2 come from `TitleScreenImg` (`$52626`). Line 0 color 0 is then cleared.
- Line 3 comes from `TitleImg` line 3 (`$54C98`). Before that, `NHLShieldImg` line 3 had loaded a placeholder of all `$0E0`.
- `PAlogoImg`'s own palette (`$53876`) is **never loaded**. The PA logo draws with the background's lines 0/1.

```
L0: 000 EEE CCC AAA 888 666 444 222 446 48E 8AE 4AE 48A CCA 88C 026
L1: 000 EEE CCC AAA 888 666 444 222 04C 008 004 00A 00C 000 800 A22
L2: 000 EEE CCC AAA 888 666 444 222 008 004 00C 000 CCA EEC 08A 2CE
L3: 000 00E 00C 00A 008 006 004 002 EEE CCC AAA 888 666 444 222 000
```

**Patched.**
- Lines 0-2 come from the background palette at `$1195A6` (file offset `$700A`). The shield's colors are in line 1 and the PA logo's colors are in line 2.
- Line 3 comes from the title, at `$11C302` (file offset `$9D66`). The shield's own palette is a `$E0E` placeholder and is overwritten.
- Color 0 of lines 1-3 is `$0E0`. It is never displayed.

```
L0: 000 222 206 642 446 208 20A EE8 44A 668 46C 48C 88A AAC CCC EEE
L1: 0E0 EEE CCC 666 444 222 04C 008 004 E0E E0E E0E E0E E0E 000 EEE
L2: 0E0 EEE CCC AAA 888 666 444 222 000 CCE 008 00C 866 844 822 E0E
L3: 0E0 EEE CCC AAA 888 222 00E 00C 00A 008 006 004 000 E0E E0E E0E
```

RGB: 3 bits per channel, `c = ((w >> 1) & 7) / 7` etc. This is the same as `PaletteBank.cram()` (`godot/core/palette_bank.gd`).

### 5.3 The 8 images

| Image | Base | pal_off → abs | map_off → abs | Tiles (at base+10) | Map | Map palette bits |
|---|---|---|---|---|---|---|
| retail `TitleScreenImg` (L273770) | `$4E45C` | `$41CA` → `$52626` | `$424A` → `$526A6` | 526 | 32x28 | lines 0,1,2; some h-flips |
| retail `NHLShieldImg` (L292537) | `$52DAA` | `$50A` → `$532B4` | `$58A` → `$53334` | 40 | 6x7 | lines 0,1 |
| retail `PAlogoImg` (L294043) | `$5338C` | `$4EA` → `$53876` | `$56A` → `$538F6` | 39 | 6x7 | lines 0,1 |
| retail `TitleImg` (L295517) | `$5394E` | `$12EA` → `$54C38` | `$136A` → `$54CB8` | 151 | 30x6 | line 3; some h-flips |
| patched background | `$11259C` (file +`$0000`) | `$700A` | `$708A` | 896 (one per cell) | 32x28 | line 0 only |
| patched shield | `$119D2C` (file +`$7790`) | `$70A` | `$78A` | 56 | 7x8 | line 1 |
| patched PA logo | `$11A52A` (file +`$7F8E`) | `$60A` | `$68A` | 48 | 6x8 | line 2 |
| patched title | `$11AC18` (file +`$867C`) | `$168A` | `$170A` | 180 | 30x6 | line 3 |

The patched images end at `$11C48E` (file offset `$9EF2` = 40690 = file size). The 2 bytes at file offset `$778E` (ROM `$119D2A`, value `$03 $80`) between the background and the shield are padding and are never read.

### 5.4 VRAM tile allocation (`d4` chain)

| | Background | Shield | PA logo | Title | Font (94) | End |
|---|---|---|---|---|---|---|
| retail | 0-525 | 526-565 | 566-604 | 605-755 | 756-849 | 850 |
| patched | 0-895 | 896-951 | 952-999 | 1000-1179 | 1180-1273 | 1274 |

The patched set leaves only 6 spare tiles below plane B at `$A000` (1280 tiles). In Godot each image is simply its own texture, so this only matters if replacement art is ever put back into a ROM.

---

## 6. Palette fade (`cramfade` L44101, run from the VBlank)

Each VBlank whose `dfng` bit is clear calls `cramfade`. The title's VBlank handler always does, because the main thread never holds `dfng` across a VBlank.

```
if palcount < 0: return
if palcount == $64: copy palfadenew → CRAM, palcount = -1, return   (instant; not used here)
palcount -= 1; if palcount < 0: return
if palcount > 24: return                        ; delay
sh = (palcount % 3) * 4                          ; 0 = red bits 1-3, 4 = green bits 5-7, 8 = blue bits 9-11
for all 64 CRAM entries: move that one component one step (2<<sh) toward palfadenew
```

Fade-in: the start CRAM is all black (`setvram`'s `forcefade`), with `palcount = $20`.

- **Frames 1-7:** black (counter 31..25).
- **Frames 8-32:** one component step per frame, in the order R (24), B (23), G (22), R (21), ... ending on R (0). Red gets 9 steps, green and blue get 8 each. Every 3-bit level (max 7) is therefore reached by frame 32.
- **Frame 33:** the counter goes negative and the fade stops.

To match it exactly, implement this algorithm on a 4x16 array of CRAM words and rebuild the 16x4 palette texture each frame. Snapshot: at frame 20, R is 5 steps in, B and G 4 steps each.

---

## 7. Logo slide-in (per-line H-scroll)

### 7.1 Table (`sub_FF3B0` L975538)

Writes `SortCords` (`$FFB04A`) as longs: the high word is plane A H-scroll (always 0), the low word is plane B. `Hscroll = $14` (speed 20) and `word_FFBF14 = $50` (delay).

- **Lines 0-80:** B = `$FD80` minus 1 after each even `d0`, so `B(L) = -(640 + ceil(L/2))`: -640, -641, -641, -642, ..., line 80 = -680.
- **Lines 81-177:** `B(L) = 256 + 4*(L-81)`: 256 ... 640.
- **Lines 178-223:** not written. They stay 0, because `Begin` cleared that RAM and nothing on the boot path writes it. The first write there is in `setoptions`, `word_FFB366`, which runs after the title.

### 7.2 Per-VBlank update (`sub_FF3F8` L975563, called after the DMA)

`word_FFBF14 -= 1`. While the result is ≥ 0, nothing happens, for 80 VBlanks. After that, every VBlank does the following for lines 0-182 (`d0 = $DF-L > $28`):

- **L ≤ 80:** if B ≠ 0, `B += 20`. If `(B & $FC00) != $FC00`, B = 0. In practice `B = min(0, B+20)`.
- **81 ≤ L ≤ 182:** `B -= 20`. If the result is negative, B = 0.

The VBlank DMAs the table **before** updating it. Frame n (the picture after VBlank n) therefore shows `s = clamp(n - 81, 0, 34)` steps:

```
off(L, s) = min(0, -(640 + ((L+1)>>1)) + 20*s)     for L <= 80
          = max(0, 256 + 4*(L-81) - 20*s)          for 81 <= L <= 177
          = 0                                      otherwise
plane B pixel at plane column p appears at screen x = p + off(L, s)   (wrap 1024; never visible wrapped here)
```

How this looks:

- **Shield and PA logo** come in **from the left, moving right**. They shear slightly (the lower lines lag ½ px per line).
  - The PA logo shows first: frame 101 at the left edge. It then crosses the whole screen to x=200.
  - The shield shows from frame 111.
  - Both settle at frame 115.
- **Title** comes in **from the right, moving left**, strongly sheared at 4 px per line, so its bottom line lags its top line by 188 px.
  - Visible from frame 88. Top line settled at frame 100, bottom line at frame 110.
- **Everything is static from frame 115.**

Reference renders: `out/*_frame_0090/0096/0102.png` (§13).

---

## 8. Credits

### 8.1 Text data format (`$5776`)

The credits are a sequence of records: `word L` (counts itself, always even), then L-2 bytes. If the text has an odd length, a trailing `$00` pads it. `print` skips the pad without using a column.

- **Separator:** the record `$0004 $FF $00`. Any record whose first two data bytes form a negative word ends a block.
- **Block end** (`sub_FF2C8`): after printing a record, `tst.w 2(a1)` checks the next record. If its first data word is negative (a separator), the block is complete.
- **List end** (main loop): after skipping a separator, `tst.w 2(a1)` again. If the next record is **another** separator, the routine ends.

Both texts end with: last block, sep, `$0002` (an empty record, which makes one blank block), sep, sep.

- **First block:** `$5776-$57B3` (3 lines), then a separator at `$57B4`. It is printed during setup with `a1 = $5776`.
- **Loop:** starts at the **hard-coded** `$57B8` (the immediate at `$FF292`), not at the `a1` left by the first block.
  - In both ROMs the first block plus its separator ends exactly at `$57B8`. The patched `scroll_text.bin` keeps bytes `+$00..+$41` identical to retail.
  - If a replacement text changed the first block's length, the loop would start in the middle of a record. It would print garbage, or end at once if it hit a byte ≥ `$80`.
- **Patched text length:** 936 bytes, `$5776-$5B1D`. That is 2 bytes past retail's `$5B1C` (the start of retail `SPAList`). The fight patch relocated `SPAList`, so this is safe in that ROM.

Characters: `'$'` draws the font's © glyph (tile 11). `'O'` and `'0'` share glyph 22. The game draws `'@'` as blank and treats `'^'` as a column skip. Bytes ≥ `$80` are `print` commands. The credits use none of `@`, `^` or ≥ `$80`.

### 8.2 Block contents (x = start column, H32 cells)

**First block** (both ROMs): `[5] "$ 1993 Electronic Arts"`, `[10] "Licensed by"`, `[5] "Sega Enterprises Ltd."`

**Retail loop (20 blocks)**

1. `[7] Design adapted by`, `[9] Michael Brook`
2. `[9] Programmed by`, `[10] Mark Lesser`
3. `[10] Graphics by`, `[11] Doug Wike`
4. `[6] Based on NHLPA 93 by`, `[10] Jim Simmons`
5. `[7] Music and Sound by`, `[10] Rob Hubbard`
6. `[9] Organ Music by`, `[9] Dieter Ruehle`
7. `[7] Executive Producer`, `[11] Scott Orr`
8. `[10] Produced by`, `[9] Michael Brook`
9. `[7] Assistant Producer`, `[10] Kevin Hogan`
10. `[6] Technical Directors`, `[11] Rob Harris`, `[10] Lon Meinecke`
11. `[11] Testing by`, `[12] Yun Shin`, `[11] Ken Rogers`, `[11] Craig Wike`
12. `[11] Testing by`, `[10] John Boerio`, `[11] Jed Garvey`, `[11] Gabe Boys`
13. `[7] Player Ratings by`, `[9] Igor Kuperman`
14. `[5] Player Card Photos by`, `[9] Steve Babineau`
15. `[7] Special Thanks to`, `[11] Bob Borgen`, `[11] Dan Brook`, `[10] Julie Cressa`
16. `[7] Special Thanks to`, `[9] Randy Delucchi`, `[10] Jeff Fennel`, `[11] Chip Lange`
17. `[7] Special Thanks to`, `[9] Barry Melrose`, `[10] Scott Probin`, `[11] Ian Pulver`
18. `[7] Special Thanks to`, `[9] Mike Rubinelli`, `[11] Kyra Woody`
19. `[3] EA Hockey League Champion`, `[10] Kevin Hogan`
20. *(empty: one zero-length line)*

**Patched loop (21 blocks)**

- Block 1: `[6] "Fight Patch 1.01 by "`, `[10] "   chaos    "`
- Block 2: `[9] Menu Patch by`, `[12] McMarkis`
- Block 3: `[7] "Special Thanks to "`, `[4] the NHL94.com community`
- Blocks 4-19: retail blocks 2-17 (Programmed by ... Ian Pulver), unchanged
- Block 20: `[9] Enjoy the ROM!`
- Block 21: *(empty)*

The patched text drops retail blocks 1 (Design adapted by), 18 (Rubinelli/Woody) and 19 (EA Hockey League). The quoted lines keep their leading and trailing spaces. The spaces are drawn as blank cells and count in the centering.

### 8.3 Printing a block (`sub_FF2C8` L975462)

```
printy = ((Vscroll >> 3) + 28) & 31                ; 5 rows below the strip's top row
eraser: printx=0, 32 x 6 cells of $07FF from printy (rows wrap & 31)
for each record until the block ends:
    printx = 17 - (L >> 1)        ; L = record length incl. its 2-byte header and pad
    print (plane A, printa = $2000 → palette 1, low priority)
    printy = (printy + 1) & 31
```

Use the game's `x = 17 - L/2`. Do not recompute centering from the text: a padded odd-length line sits half a cell left of true center. Plane A is 128x32 cells. Its H-scroll is 0 on every line, so column c is at screen x = 8c.

### 8.4 Scrolling, clipping, timing

- Plane A cell row r is at screen y = `(8r - Vscroll) mod 256`. It is visible only for y in **184..223** (5 rows). Above line 184 the window hides plane A, which clips the text sharply at y=184. There is no sprite masking. The text pixels (palette 1) lie over the background strip (plane B rows 23-27, palette 2 retail / 0 patched). Color 0 is transparent.
- **Block 0:** printed at rows 28-30 with Vscroll 0. Then `Vscroll = 32`, so the lines sit at y = 192, 200, 208. The strip's top line (184) and line 216 are empty.
- **Each loop block:** printed at row `(V/8 + 28) & 31`, i.e. at y = 224, just below the screen. Then `Vscroll += 1` every 2 frames, 40 times. The new block rises 40 px into the strip, so its first line ends at y=184. Meanwhile the previous block rises under the window and disappears.
- **Only the current and the previous block** can be visible. The 6-row erase clears rows left over from 6 or more blocks earlier, since the 32-row plane wraps every 6.4 blocks.

`Vscroll` is written to VSRAM (plane A only) in the next VBlank, so it shows one frame after the main thread changes it.

| Phase | Frames (picture after VBlank n) |
|---|---|
| block 0 on screen, static | 1-191 (130 frames of `word_FFB8B2` `$104`/2, then 61 frames of `$3C` dbf) |
| block k (k = 1..N) printed (off screen) | right after VBlank `191 + 201(k-1)` |
| block k scrolls (Vscroll + 1 visible on frames…) | `194 + 201(k-1)`, `196 + …`, …, `272 + 201(k-1)` (40 steps) |
| block k holds | through VBlank `392 + 201(k-1)` |
| routine returns (no Start) | after VBlank `191 + 201N`: retail N=20 → **4211** (≈70.3 s NTSC), patched N=21 → **4412** (≈73.6 s) |

### 8.5 Font (`unk_AAC52` L652625 header, `unk_AAC5A` L652634 tile count)

The font uses the same file layout as §5:

- `+0` = `$FFFFFFFF` (no palette).
- `+4` = `$BCA` → glyph map at `$AB81C`: 32x4 = 128 words, indexed by character code.
- `+8` (`$AAC5A`) count = `$005E` = 94 uncompressed tiles at `$AAC5C-$AB81B`.

`print` uses `fontmap[c] = word at $AB820 + 2c`. The tiles use only color 1 (letter body) and color 2 (1-px drop shadow, right/bottom). Glyph indexes:

| Characters | Glyphs |
|---|---|
| `' '` | 0 (blank tile) |
| `! " # $ % '` | 8 9 10 11(©) 12 13 |
| `( )` | 92 93 |
| `* + , - . /` | 16-21 |
| `0-9` | 22-31 |
| `: ; < = ?` | 32-36 |
| `@` | 37 (but `print` writes blank `$7FF`) |
| `A-N` | 38-51 |
| `O` | 22 (same as zero) |
| `P-Z` | 52-62 |
| `[ ] _` | 63 64 65 |
| `a-z` | 66-91 |
| `{ }` | 14 15 |
| `&`, `>`, `\`, `^`, backtick, `\|`, `~`, and most control codes | 0 (blank) |

Codes `$12-$19` map to the special glyphs 1-7. `sub_1172C` uploads the font through `remap` (L44006) with the 8 bytes at `$FF210`. Color n becomes the high nibble of `table[n>>1]` if n is even, the low nibble if n is odd. The result keeps the pixel's position.

| | Table | 1 (body) → | 2 (shadow) → | 3 → | Result in palette line 1 |
|---|---|---|---|---|---|
| retail | `0D 10 45 67 89 AB CD EF` | `$D` | `$1` | 0 | body `$000` black, shadow `$EEE` white |
| patched | `0E F0 45 67 89 AB CD EF` | `$E` | `$F` | 0 | body `$000` black, shadow `$EEE` white (the patch moved the indexes because its new line 1 holds different colors at `$D`/`$1`) |

So the credits look the same in both ROMs: black letters with a white 1-px shadow, on palette line 1.

---

## 9. Input, music, exit

- **Input:** checked once per frame inside `sub_FF318`, from frame 1 (during the first-block hold too). `orjoy` = new presses of pad 1 OR pad 2 (OR pads 3/4 when `FourWayPlay`). The pads are read by `MusicVB` → `ReadJoyData` in every VBlank. Only **bit 7 = Start** (new press, not held) exits. Holding Start from the previous screen does nothing until it is released and pressed again.
- **Music:** `song($78)` (the title/menu theme, see `animation_assets.md` §5.2) starts just before VBlank is enabled, so it plays from frame 1. `MusicVB` steps it every VBlank. Nothing stops it on exit. `Opening2`'s RAM clear ends at `$FFD03E`, below the sound driver's RAM, and `KillCrowd` only silences PSG crowd noise. The menus (`GameSetUp`) keep the same song playing without a restart.
- **On exit** (Start, or the end of the credits):
  1. `newTitleScreen` returns. There is no fade of its own.
  2. `Opening2` clears RAM and calls `GameSetUp`.
  3. `setoptions` (L962234) sets a new VBlank handler and calls `setvram(0)`. Its `forcefade` sets the target to black with `palcount=$18`. The VBlank used during the fade (`loc_15E4C`) does only `cramfade` and `MusicVB`. So the **title stays on screen frozen**: no more slide or scroll steps, and the H-scroll/VSRAM values stay as they were. It fades to black in 25 frames: B, G, R component steps at counters 23..0, 8 each.
  4. Only then are the VDP registers rewritten (H40) and VRAM cleared, and the options menu appears.
- **Port:** freeze the title, run the same `cramfade` toward all-zero for 25 frames starting at `palcount=24`, then switch to the setup screen with the music still playing.

---

## 10. Master timeline (frame n = picture after VBlank n, 60 Hz)

| Frame | Event |
|---|---|
| 0 | setup done, CRAM black (not visible) |
| 1 | song `$78` running. Block 0 at y 192-215. Logos off screen. |
| 8-32 | fade-in (§6) |
| 82 | first slide step (s=1). The title enters from the right at frame 88, the PA logo from the left at 101, the shield at 111. |
| 115 | slide complete (s=34) |
| 191 | block 1 printed below the strip |
| 194-272 | block 1 scrolls up, 1 px per 2 frames |
| 273-392 | block 1 holds. Block 2 is printed after VBlank 392, and so on, every 201 frames. |
| 4211 / 4412 | retail / patched: returns after the blank last block |

---

## 11. Rebuilding it in Godot

**H32 in a 320x224 viewport.** The screen is 256 px wide. There are two options:

- **Option a, pixel-exact (recommended default):** draw the 256x224 screen at x = 32 with black side bars. At the project's 3x window (960x672) this is a clean 768-px-wide image. `out/*_final_320.png` shows this layout.
- **Option b, TV-faithful:** render into a 256x224 `SubViewport` and stretch it to 320x224 with nearest filtering. On hardware an H32 picture fills the same physical width as H40, so this matches what players saw, but the pixels become uneven (4 → 5).

Choose once. Both use the same 256x224 content.

**Layers** (one `Node2D`, back to front; all textures are index PNGs with `res://shaders/palette.gdshader` and a 16x4 palette texture that the fade code updates every frame):

1. Black `ColorRect`, 256x224. This is the backdrop, CRAM[0][0].
2. **Background** `Sprite2D`: the full 32x28 background map (rows 0-27) at (0,0), color 0 transparent. Window rows 0-22 and plane B rows 23-27 are both static at H-scroll 0, so one texture is exact.
3. **Credits**: a `Control` with `clip_contents`, rect (0,184)-(256,224), drawn above the background.
   - Keep a 32x32 cell buffer that emulates plane A. Run the same erase (6 rows from `printy`) and print (`x = 17 - L/2`, `printy` wrapping & 31).
   - Draw the 6 rows that can intersect the strip: cell row r at y = `(8r - Vscroll) mod 256`.
   - Draw glyph tiles from the remapped font sheet on palette line 1.
4. **Logos** (high priority, above everything): one 256x224 index texture of plane B's priority content, with the shield at (8,8), PA at (200,8) and title at (8,112), transparent elsewhere. Give it a shader with `uniform int step`:

   ```
   L = screen line of this fragment, 0..223 (e.g. int(UV.y * 224.0) on a 256x224 rect)
   off = L<=80 ? min(0, -(640 + ((L+1)>>1)) + 20*step) : (L<=177 ? max(0, 256 + 4*(L-81) - 20*step) : 0)
   sample at x - off; outside [0,256) → transparent
   ```

   `step = clamp(frame - 81, 0, 34)`. Equivalently, draw each logo as 1-px-high row slices offset per line.

**Tick:** one game frame per 1/60 s. The order per tick matches the VBlank:

1. Latch the H-scroll step for this frame (computed last tick).
2. Latch Vscroll.
3. `cramfade`.
4. Advance the slide step.
5. Run the main-thread state machine: hold counters, print, `Vscroll += 1` on every second frame of a scroll, Start check.

The prototype's `main_thread` generator (§13) is a line-for-line reference for that state machine.

---

## 12. Extraction recipe

### 12.1 What to write (suggested `tools/extract/title.py`, offline)

For each variant (`retail` from `lst/nhl94.bin`; `fight` from the patched ROM, or from `data/title_screen.bin` + `data/scroll_text.bin` at the offsets below):

1. **Images.** For the four bases in §5.3, read `pal_off`, `map_off`, `count` (`decompress()` if bit 15 is set), tiles, `w`, `h` and the map. Render the whole map to an index PNG, `w*8 x h*8`: R = color index × 17, G = map palette line × 85, A = 255 where the index is ≠ 0. That is the `assets.py` `Canvas` convention, honoring the h/v-flip bits. Use **the map's own palette line**, not the `dobitmap` mask. Keep the priority bit in the metadata. On screen it is the XOR'd value: background 0, logos 1.
2. **Palette.** The final `palfadenew` from §5.2, as 4x16 CRAM words: retail lines 0-2 from `$52626`, line 3 from `$54C98`, `[0][0]=0`; patched lines 0-2 from `$1195A6`, line 3 from `$11C302`, `[0][0]=0`. Rebuild it the way the code does, applying the masks `$F`, 8, 0, 8 in order and then clearing `[0][0]`, rather than hard-coding it.
3. **Font.** 94 tiles from `$AAC5C`, passed through the variant's remap table (`$FF210`, 8 bytes; retail `0D10456789ABCDEF`, patched `0EF0456789ABCDEF`). Write a 16-wide sheet on line 1, plus the 128-entry glyph map from `$AB820`. The font and glyph map are identical in both ROMs.
4. **Credits.** Parse from `$5776` (or `scroll_text.bin` +0) with the exact block/end rules of §8.1. Write `{"first": [[x, text], ...], "loop": [[[x, text], ...], ...]}` with `x = 17 - (L>>1)` and the text with the `$00` pads removed. Keep `'$'` as is (the renderer maps it to glyph 11). Check `first_end + 4 == $57B8` (file offset `$42`).
5. **Layout constants:** window rows 23; positions (8,8), (200,8), (8,112); strip y 184..223; slide constants (delay 80, speed 20, line groups 0-80 / 81-177, initial values); fade `palcount` 32; hold 130 + 61; scroll 40 × 2; hold 121; song `$78`.

### 12.2 Verified patch bytes in `nhl94_fight_v1.01.bin`

| Address | Retail | Patched |
|---|---|---|
| `$FF10C`, `$FF13E` | `movea.l #$4E45C,a0` | `#$11259C` |
| `$FF17C` | `#$52DAA` | `#$119D2C` |
| `$FF1A8` | `#$5338C` | `#$11A52A` |
| `$FF1D4` | `#$5394E` | `#$11AC18` |
| `$FF210-1` | `0D 10` | `0E F0` |
| `$11259C-$11C48D` | n/a | `data/title_screen.bin` (identical) |
| `$5776-$5B1D` | retail text to `$5B1B` | `data/scroll_text.bin` (identical) |

---

## 13. Prototype (proof of the decoding)

`/tmp/claude-0/-home-user/ef020377-92e3-57ff-8519-5d51b4a7df4d/scratchpad/title_research/title_proto.py` (Python 3, stdlib + zlib). It imports `Rom`, `Canvas` and `decompress` from `tools/extract/assets.py`.

What it does:

- Reads every pointer, `printz` string and the remap table from the ROM code.
- Builds the VRAM tiles, the three name tables, `palfadenew` and the line-scroll table.
- Runs the VBlank handler and the main loop (as a generator, one yield per `sub_FF318`) frame by frame.
- Composites the H32 screen with VDP priorities.

Run it with `python3 title_proto.py [out_dir]`. The default `out_dir` is `title_research/out/`. It writes, for `retail_` and `patched_`:

| File | Content |
|---|---|
| `*_frame_0020.png` | fade-in in progress |
| `*_frame_0090.png`, `*_frame_0096.png`, `*_frame_0102.png` | slide-in, showing the shear |
| `*_frame_0150.png` | settled screen with block 0 |
| `*_frame_0230.png` | block 1 halfway up, block 0 clipped at y=184 |
| `*_frame_0300.png`, `*_frame_0392.png` | block 1 settled |
| `*_final_320.png` | frame 150 pillarboxed into 320x224 |
| `*_img_{titlescreen,shield,palogo,title}_idx.png` | index PNGs per §12.1 |
| `*_font_idx.png` | remapped font sheet |
| `*_title.json` | decoded `printz` commands, image geometry and palettes, `palfadenew`, initial plane B H-scroll per line, font glyph map, credits blocks, event frames, exit frame (4211 / 4412) |

---

## 14. Unresolved / assumptions

1. **H32 presentation** in the 320-wide port is a design choice (§11). The game itself is 256 px wide.
2. **H-scroll for lines 178-223** is taken as 0 because `Begin` cleared that RAM and no code on the boot path writes it before the title. Only `setoptions` writes there, and it runs later. If it were not 0, the credits and the background strip would shift sideways. That is not the case on a normal boot.
3. **Color levels:** linear 3-bit → 8-bit (`v/7`), as in `PaletteBank`. The real VDP DAC is slightly non-linear. This is not modeled.
4. **Mid-frame VRAM writes:** the prints run right after a VBlank and finish long before line 184, so the model treats them as taking effect in that frame. The one-frame latency of `Vscroll` and of the H-scroll table is modeled.
5. **The song itself** (`$78`, sequence via `unk_2C648`) is not decoded here. It is the same title/menu theme listed in `animation_assets.md` §5.2.
6. **Not checked on an emulator.** The renders come from the prototype. The VDP rules it relies on are standard and the output matches the known screen: window union rule (H range empty, so V range = full-width rows), H-scroll sign (+ moves the plane right), plane A over plane B at equal priority.
7. **The second hard-coded credits pointer `$57B8`** means a replacement text must keep the first block at exactly 66 bytes including its separator. Both ROMs do.
