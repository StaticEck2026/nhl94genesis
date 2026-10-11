# On-ice indicators, sprite order and plane priority (retail NHL '94)

Scope: how the unpatched game draws every on-ice indicator (pad stars, the puck-carrier star with the player's number, the off-screen arrows, the replay cursor), in what order and with which priority. It also covers how the rink planes, the backdrop and sprite priority combine, including the near-end ("bottom") glass. The last sections list what the Godot port must change.

Sources: `lst/nhl94.bin.lst` (Lnnnnn = listing line), `lst/nhl94.bin` (tile and map pixels read with `tools/extract/assets.py` helpers), and the RAM symbols in `src/stubinc/ram_addrs.inc`. Frame numbers are decimal with hex in brackets.

Conventions:
- Retail screen: H32, **256x224**. VDP sprite coordinates = screen + 128 on both axes. The port renders 320x224, so its screen x = retail screen x + 32 when the camera centre stays at the screen centre.
- Rink axes: x to the right, y up (toward the top net). `Hpos`/`Vpos` = camera centre in rink coordinates.
- `find3d` (L52947), vertical mode: `screen = (128 + (x - Hpos), 112 - (y - Vpos) - (z + z>>1))`. The object is culled when `|x - Hpos| > 144` or `|y - Vpos + z + z>>1| > 144`. Horizontal mode (`sflags` bit 7, penalty screen): `dx = -y`, `dy = x - $C5`, so `screen = (128 - y, 309 - x - 1.5z)`, with the same ±144 culls.
- A "loop" is one `DoGameFrame` (d7 vblanks).

---

## A. Indicators

### A.0 Summary

| Indicator | Object (RAM) | Frame | Attr | Shown when | Where |
|---|---|---|---|---|---|
| Puck-carrier star + number | ffo 0 `pads` $FFBDB4 | 392 ($188) | 0 | nibble 0 of `word_FFBE78` = carrier SCnum (set every loop) | carrier X,Y on the ice (Z = 0) |
| Penalized-player star + number (penalty screen) | ffo 0 (same) | 392 ($188) | 0 | `asspenalty` sets nibble 0. In horizontal mode nothing clears it. | penalized player, rotated mapping |
| Pad 1 star + number | ffo 1 `Joy1Struct` $FFBDD0 | 390 ($186) | 0 | nibble 1 = player controlled by pad 1 | that player's X,Y, Z = 0 |
| Pad 2 star + number | ffo 2 $FFBDEC | 391 ($187) | 0 | nibble 2 = pad 2 player | ″ |
| Replay cursor + number | ffo 3 `ReplayStarStruct` $FFBE08 | 393 ($189) | **$8000** | instant replay only (nibble 3) | snapped player, or its own X,Y |
| Pad 3 star + number | ffo 4 `Joy3Struct` $FFBE24 | 844 ($34C) | 0 | `word_FFBE86` bits 4-7 | ″ |
| Pad 4 star + number | ffo 5 `Joy4Struct` $FFBE40 | 845 ($34D) | 0 | `word_FFBE86` bits 8-11 | ″ |
| Gloves (fight patch) | ffo 6 `glovestruct` $FFBE5C | 353 ($161) | 0 | never in retail | `fight_patch_retail_hooks.md` §3 |
| Off-screen arrow, pad 1/2/3/4 | sso 0-3 `sso` $FFBE88, stride $14 | 384-386 / 387-389 / 838-840 / 841-843 | flips only | the pad star is visible and its player is beyond the screen edge margin; vertical mode only | clamped to 12 px from the screen edge |

Not present in retail '94: no pass or one-timer target marker, no arrow for the puck or the puck carrier, no on-ice face-off or line-change marker, no separate goalie-control marker (a manually controlled goalie gets the normal pad star), no blinking or animation of any indicator (A.9).

### A.1 Sprite list order (`setvideo` L51875)

```
setvideo:
  updatescroll                    ; plane B scroll (vertical mode only)
  a6 = Satt ; d6 = 1              ; sprite table, link counter
  checkfo        L51885  face-off close-up sprites (attr $8000 / $A800)
  checksso       L51886  off-screen arrows, pad 1, 2, 3, 4
  setsortcords   L51887  16 sort objects in OOlist order (SprSort: rink Y ascending, X in horizontal mode)
  setffo         L51888  ffo 0..6: puck star, pad 1, pad 2, replay cursor, pad 3, pad 4, gloves
  showclock      L51889  NOT sprites: DMA of plane-A map cells (vertical), printz text (horizontal)
  showzam        L51890  zamboni sprites
  sub_FD78A      L51891  rink-fixed overlay animation sprites (A.9)
  showcrowd      L51892  penalty-box occupants and crowd sprites
  showref        L51893  NOT sprites: DMA of the referee window into plane A
```

The first sprite in the link list is drawn in front. So from front to back: face-off close-up, then the arrows (pad 1 in front of pad 2, 3, 4), then every sort object (players, nets, puck, puck shadow), then the puck-carrier star, the pad 1 star, the pad 2 star, the replay cursor, the pad 3 star, the pad 4 star, the gloves, the zamboni, the overlay animation and the crowd/box sprites. **Every star is behind every sort object**, not only behind its own player. **Every arrow is in front of every sort object.**

Correction to `fight_patch_retail_hooks.md` §3.4 and `animation_assets.md` §2.6: the clock and the ref window are plane-A cells, not sprites. In vertical mode `showclock` (L52387-52464) writes digit tiles with `$8000` into plane A row 24, and `PushRef` (L46622) builds `RefRamMap` with `$8000` in vertical mode only (L46638-46640).

### A.2 Objects and state

ffo objects (`defaultsprites` `_listffo` L53361-53403, stride $1C, fields: +0 X, +2 SAT X adjust, +4 attribute, +6 frame, +8 old frame, +$12 VRchar, +$14 Y, +$18 Z). Every ffo starts with Z = $FFFF (hidden). The VRAM budget is 7 tiles each (5 for the gloves). `setupice` preloads the tiles of ffo 0-5 with `addframe2` (L53103-53115; `sub_16BAC` again at L53163-53175; the listing's comments there are wrong).

sso objects (`_listsso` L53340, stride $14, fields +0 VDP X, +2 VDP Y, +4 attr, +6 frame, +8 old frame, +$12 VRchar): a VRAM budget of 9 tiles each (a 3x3 arrow).

Marker nibbles:

| Word | Bits 0-3 | Bits 4-7 | Bits 8-11 | Bits 12-15 |
|---|---|---|---|---|
| `word_FFBE78` | ffo 0 puck-carrier / penalized player | ffo 1 pad 1 | ffo 2 pad 2 | ffo 3 replay cursor |
| `word_FFBE86` | unused (kept $F) | ffo 4 pad 3 | ffo 5 pad 4 | unused (kept $F) |

Nibble value: 0..13 = the SortCords index (SCnum) of the object to mark. In practice only 0..11 (players) occur. **$E** = keep the ffo struct's own X/Y/Z (used by the free replay cursor). **$F** = hidden.

`padcont` ($FFBE7A, 6 words, one per ffo 0..5) caches the text key last uploaded for that ffo: `(position << 8) | jersey`, or $F.

### A.3 Who sets the nibbles

```
sub_C656(a3 = object, d4 = slot):            ; L37819-37835
  s = 2 * (2 + d4)                           ; d4 -2 -> 0, 0 -> 4, 2 -> 8, 4 -> 12
  word_FFBE78 = (word_FFBE78 & rol16($FFF0, s)) | (SCnum(a3) << s)
```

| Writer | Line | Effect |
|---|---|---|
| `updateplayers` head, vertical mode only | L35330-35332 | `word_FFBE78 |= $000F`: the puck-carrier star is hidden at the start of every loop |
| `updateplayers` `_done`, per object | L35557-35565 | if `SCnum == puckc` and not fighting (`$63` bit 0) and not horizontal: `sub_C656(d4 = -2)`. Only objects with `$34 >= 0` (on ice) get here (L35455-35456) |
| `doinput` for the pad-controlled player | L35923-35926 | `sub_C656(d4)`: d4 = 0 for pad 1, 2 for pad 2 (L35584, L35593). Pads 3/4 run doinput with `word_FFBE78` and `word_FFBE86` swapped (L35617-35621, L35651-35655), so they write nibble 1/2 of `word_FFBE86` |
| `asspenalty`, first call | L38033-38034 | `sub_C656(d4 = -2)` on the penalized player ("so graphics know who it is") |
| replay cursor snap | L34642-34643 | `sub_C656(d4 = 4)` |
| replay cursor free move | L34673-34674 | nibble 3 = $E |
| replay B+A, replay end | L34738-34748, L34804 | nibble 3 = $E, then $F |
| `SetRCords` (replay playback) | L35166-35178 | nibbles 0-2 from the recording (nibble 3 kept). `word_FFBE86 = (rec << 4) | $F00F` |
| `updatereplay` (recording) | L35310, L35315-35317 | stores `word_FFBE78` and `word_FFBE86 >> 4` (one byte) every loop |
| `setupice`, `sub_16BAC` | L53092-53098, L53151-53157 | both words = $FFFF, padcont = 0, c1/c2playernum = -1 |
| `StartPer` | L29863 | nibble 3 = $F |
| `Begin` | L29735 | `word_FFBE86 = $FFFF` |

So, per indicator:
- **Puck-carrier star.** In vertical mode it is hidden every loop, then put on the puck carrier (human or CPU, either team) if he is on the ice and not fighting. There is no star while the puck is loose. In horizontal mode neither step runs.
- **Penalized player.** `InProgress` gives the penalized player `asspenalty` (L46298) while the penalty screen is up (`chkprogress` calls `SetHor` at L46078 first). The first asspenalty call sets nibble 0 to him. In horizontal mode nothing resets it, so the filled star with his number and position follows him to the box for the whole penalty screen. It is cleared by the first vertical-mode `updateplayers` after `ClrHor`. If asspenalty ever started in vertical mode, the marker would last one loop.
- **Pad stars.** The nibble is rewritten every loop for the player whose SCnum equals `cNplayernum`, while he is on the ice. Nothing clears it when control ends. The star stays on (and keeps following) the last controlled player until the next doinput moves it. At `setupice`/`StartPer` it is $F (hidden) until the first face-off hands out control. A pad without a team keeps $F. A goalie under manual control gets the ordinary pad star. Because his position code is 0, the text is only his number (A.5).

### A.4 `uppads` (L52666), every `setvideo`

```
uppads:                                       ; called by setffo, after the glove head (fight_patch_retail_hooks.md 3.3)
  d3 = word_FFBE78
  for k in 0..5:                              ; ffo k, d4 = 5-k
     if k == 4: d3 = word_FFBE86 >> 4         ; L52686-52689 (pads 3/4 read FFBE86 nibbles 1, 2)
     n = d3 & $F ; key = $F
     if n != $E:
        ffo[k].Z = -1                         ; st
        if n == $F: goto next                 ; hidden; text untouched
        p = SortCords[n]
        ffo[k].X = p.X.hi ; ffo[k].Y = p.Y.hi ; ffo[k].Z = 0     ; on the ice, whatever p.Z is
        key = (p.byte$35 << 8) | p.byte$6F    ; position code, jersey (packed BCD)
     ; n == $E: X, Y, Z are left as they are; key = $F (blank text)
     if padcont[k] != key: padcont[k] = key ; settext(ffo[k], key)   ; sub_166E6
   next:
     d3 >>= 4
```

### A.5 The number and position text (`sub_166E6` L52724, `sub_1674A` L52761)

Frames 390-393, 844 and 845 all start with two "text" pieces: piece 0 is 2x1 tiles at (-12, +11) and piece 1 is 1x1 at (+6, +11). In the ROM their tiles (3860-3861, 2862) are blank. `addframe2` gives them VRAM tiles VRchar+0..+2. The star halves follow at VRchar+3..+6. `settext` overwrites the three tiles with font glyphs:

```
settext(o, key):                              ; sub_166E6
  o.adj = 0                                   ; +2 field, added by setffo to the X of the first TWO sprite entries
  t = (key >> 4) & $F                         ; tens digit
  if t == 0: ch0 = ' ' ; o.adj -= 4 else ch0 = '0' + t
  u = key & $F ; ch1 = (u == $F) ? ' ' : '0' + u
  p = (byte_FFC2FC bit 7) ? 0 : (key >> 8) & 7      ; bit 7 = penalty shot / shootout (puckshootout L41049)
  if p == 0: o.adj += 4
  ch2 = " DDLCRX"[p]                          ; unk_1677A L52779: 0 G -> blank, 1 LD/2 RD -> D, 3 L, 4 C, 5 R, 6 X
  upload glyph(ch0) -> VRchar+0, glyph(ch1) -> VRchar+1, glyph(ch2) -> VRchar+2

glyph(c):                                     ; sub_1674A
  font = $AAC52 (.map.jim: +4 long map offset, +$A tiles)
  tile = map[c] & $7FF ; source = $AAC52 + $A + 32*tile   ; RAW ROM tile (no colour remap)
```

- Glyph colours: the text pieces use palette line 1, so font colour 1 = line 1[1] = **$0CCC** (light grey) and colour 2 = line 1[2] = **$0888** (grey shadow). The remapped font that `print` uses for plane-A text is a different upload (`setupice` `sub_1172C`). The pad text never uses it.
- Map and tiles: ' ' → tile 0 (blank), '0'..'9' → tiles 22..31, 'C' 40, 'D' 41, 'L' 49, 'R' 54, 'X' 60.
- Layout relative to the object's ground point, with s = `o.adj`:

| Case | s | Tens slot | Units slot | Letter slot |
|---|---|---|---|---|
| skater, 2-digit number | 0 | x -12..-5 | -4..3 | 6..13 |
| skater, 1-digit number | -4 | blank | -8..-1 | 2..9 |
| goalie (pos 0), or PS/SO, 2-digit | +4 | -8..-1 | 0..7 | blank |
| goalie, or PS/SO, 1-digit | 0 | blank | -4..3 | blank |
| blank key $F ($E cursor) | 0 | blank | blank | blank |

  Rows are y +11..+18 (below the star). The text is therefore centred under the star.
- `padcont` is cleared at the face-off start (`puckfaceoff` L41645-41647, which also clears `byte_FFC2FC` bit 7), at `puckshootout` (L41050-41052, which sets bit 7) and at the replay start (L34530-34532). This forces a re-upload when the letter rule changes.
- Quirk: a key of 0 (goalie wearing #00) equals the cleared cache, so no upload happens and the blank ROM tiles show.
- Quirk, not verified as reachable: a marked object with position byte $FF ($34 < 0) gives letter index 7 → char $FF → `map[$FF]`, which is outside the 128-entry map, so a garbage glyph would show.

### A.6 Drawing the ffo objects (`setffo` L52646)

```
setffo:
  uppads
  for k in 0..6:
     first = a6
     addframe(ffo[k])                         ; skipped if Z < 0 or find3d culls it
     if a6 != first:                          ; something was drawn
        SAT[first+0].x += ffo[k].adj ; SAT[first+1].x += ffo[k].adj   ; only the two text pieces move
```

- Position: `find3d(X, Y, 0)`. In vertical mode the frame origin is at screen `(128 + X - Hpos, 112 - (Y - Vpos))`, which is the player's ground point (the player's own height is ignored).
- Star frames 390/391/392/844/845: origin (16, 5), 31x24 box. The star outline is a flattened five-point star (perspective) spanning x -16..14, y -5..10. The text row is at y +11..18.
- Replay cursor frame 393: origin (19, 9). Four inward-pointing triangles at y -9..-5 (top), y +3..+7 (bottom) and x -19..-15 / +14..+18 (sides), plus the same two text pieces at y +11..+18.
- Away-palette swap: attribute bit 0 is 0 for every ffo, so line-2 art would stay line 2. The indicator art uses only lines 0 and 1.
- Colours (CRAM words, `----BBB-GGG-RRR-`):

| Frame(s) | Line / index | CRAM | Look |
|---|---|---|---|
| 390 pad 1 star, 384-386 arrows | 1 / 9 | $0600 | dark blue |
| 391 pad 2 star, 387-389 | 0 / 10 | $064C | red-pink |
| 844 pad 3 star, 838-840 | 1 / 10 | $0042 | dark green |
| 845 pad 4 star, 841-843 | 0 / 12 | $02AC | gold |
| 392 puck star (filled) | 0 / 11, 13, 15, 3, 2 | $0C86 $0EA8 $0EC8 $0CCC $0EEC | light blue |
| 393 replay cursor | 1 / 5, 6 | $008C $006A | orange |
| text pieces | 1 / 1, 2 | $0CCC $0888 | greys |

- No blinking: no code touches ffo Z or frame on a timer. The frames never change, so their tiles are uploaded once (`setupice`). Only the three text tiles are re-uploaded, and only when the key changes.

### A.7 Off-screen arrows (`checksso` L52455, `sub_164D6` L52480)

```
checksso:
  if sflags bit7: return                      ; L52456: no arrows on the penalty screen
  arrow(star = ffo1, s = sso[0], base = $180)                 ; pad 1
  arrow(star = ffo2, s = sso[1], base = $183)                 ; pad 2
  if cont3team == 0: return
  arrow(star = ffo4, s = sso[2], base = $346)                 ; pad 3
  if cont4team == 0: return                   ; quirk: pad 4 also needs a pad-3 team
  arrow(star = ffo5, s = sso[3], base = $349)                 ; falls through into sub_164D6

arrow(star, s, base):                         ; sub_164D6
  if star.Z < 0: return                       ; L52482: no star -> no arrow
  s.frame.hi = $FF
  x = star.X ; y = star.Y                     ; set by the PREVIOUS loop's uppads (checksso runs before setffo)
  if word_FFC2FA bit0 or sflags2 bit3 or BA_PS_flags bit2:    ; shootout, replay, penalty shot (L52486-52491)
      if |x| >= $A6 (166): return             ; parked players (SO/PS park at X = -240) and bench/box
  dx = x - Hpos ; dy = y - Vpos               ; (a horizontal-mode branch exists at L52508-52513 but is unreachable)
  m = 0
  if dx >= 116: m |= 8                        ; right   (cmp #$74)
  if dx <= -116: m |= 4                       ; left    (cmp #$FF8C)
  if dy >= 100: m |= 1                        ; up      (cmp #$64)
  if dy <= -100: m |= 2                       ; down    (cmp #$FF9C)
  if m == 0: return
  dir = jdtab[m]                              ; L44581: 0 up, 1 up-right, 2 right, 3 down-right, 4 down, 5 down-left, 6 left, 7 up-left
  (cx, cy, fadd, attr) = ARROW[dir]           ; unk_165BC L52561
  if cx != 0: dx = cx
  if cy != 0: dy = cy
  s.X = dx + $100 ; s.Y = $F0 - dy ; s.frame = base + fadd ; s.attr = attr
  addframe2(s)                                ; origin at screen (128 + dx, 112 - dy)
```

| dir | Triggers | cx | cy | Frame | Attr | Origin on screen | Retail screen box |
|---|---|---|---|---|---|---|---|
| 0 up | dy ≥ 100 | keep | 100 | base+0 | 0 | (128+dx, 12) | x-13..x+10, y 5..28 |
| 1 up-right | both | 116 | 100 | base+1 | 0 | (244, 12) | 225..248, 7..30 |
| 2 right | dx ≥ 116 | 116 | keep | base+2 | 0 | (244, 112-dy) | 226..249, y-12..y+11 |
| 3 down-right | both | 116 | -100 | base+1 | $1000 V | (244, 212) | 225..248, 193..216 |
| 4 down | dy ≤ -100 | keep | -100 | base+0 | $1000 V | (128+dx, 212) | x-13..x+10, 195..218 |
| 5 down-left | both | -116 | -100 | base+1 | $1800 HV | (12, 212) | 7..30, 193..216 |
| 6 left | dx ≤ -116 | -116 | keep | base+2 | $0800 H | (12, 112-dy) | 6..29, y-12..y+11 |
| 7 up-left | both | -116 | 100 | base+1 | $0800 H | (12, 12) | 7..30, 7..30 |

- Arrow frames (24x24, one 3x3 piece): base+0 = straight arrow pointing up, origin (13, 7). base+1 = diagonal pointing up-right, origin (19, 5). base+2 = arrow pointing right, origin (18, 12). The flips mirror about the origin as `addframe2` does (piece x' = -8w - x, y' = -8h - y). Pads: 1 → 384-386, 2 → 387-389, 3 → 838-840, 4 → 841-843 (A.11).
- "Keep" means that axis follows the player, unclamped. It is inside ±115 / ±99 by construction.
- The arrow appears once the player's ground point is within 12 px of a screen edge (or beyond it). The player may still be partly visible. Its star is still drawn until find3d culls it at 144.
- Attributes carry flips only: low priority, palette from the art. The arrows are in front of all sort objects. They can still be covered by high-priority rink cells, for example a down arrow (screen y 195..218) overlaps the near glass/boards band once `Vpos` <= -150 (B.3).
- One-loop lag: X/Y come from the previous loop's `uppads`. `Hpos`/`Vpos` are current.
- Shootout/penalty-shot/replay: the |X| ≥ 166 test hides arrows for parked or benched controlled players. Nothing else changes.
- Horizontal mode: no arrows.

### A.8 Replay cursor (instant replay loop, ROM $A058, L34540-34720)

```
each replay loop:
  read pad (getpzjoy): dir (0-7, 8 none), new presses, held buttons
  if playing (word_FFC2F6 bit0): dir = none, no buttons
  c = ffo3 (ReplayStarStruct)
  if sflags3 bit5 (locked) and no NEW d-pad press: goto idle
  if dir == none: goto idle
  if c.X <= -160: c.X = 0 ; if c.Y <= -304: c.Y = 0          ; L34574-34582
  if not sflags bit5: sflags bit5 = 1 ; c.X = Hpos ; c.Y = Vpos  ; L34585-34588: appears at screen centre
  skip = locked ? c.$16 : -1 ; clear sflags3 bit5
  best = 256                                  ; dist^2 limit: snaps only within 16 px
  for SC in 0..11, SC != skip:                ; L34601-34636
     v = c - player ; a = vtoa(v) ; if none: continue
     if ((a - (dir ^ 4) + 1) & 7) > 2: continue          ; player within ±45° of the pressed direction
     d2 = |v|^2 ; if d2 <= 4 or d2 > best: continue
     best = d2 ; c.$16 = SC ; sflags3 bit5 = 1
  if sflags3 bit5:                            ; snapped
     sub_C656(player, 4)                      ; nibble 3 = SC: cursor follows him, shows his number
     sub_A616(player)                         ; c.X,Y = player ; Hpos = clamp(X,-60,60) ; Vpos = clamp(Y,-200,256)
  else:                                       ; free, 2 px per loop: STEP = (0,2)(2,2)(2,0)(2,-2)(0,-2)(-2,-2)(-2,0)(-2,2)
     move c.X if it stays in -136..136, c.Y if it stays in -294..294
     c.Z = 0 ; nibble 3 = $E ; sub_A616(c)    ; camera centred on the cursor
idle:  c.Z = -1                               ; L34714
```

- Visible: while locked, always (uppads sets Z = 0 each loop). While free, only on loops with a direction held (the $E nibble keeps the Z from the loop above).
- Text: the locked player's number and position. When free it is blank.
- Attribute **$8000**: it is drawn over high-priority plane cells, including the near glass, but in sprite order it is behind every sort object and behind ffo 0-2 (B.2 explains what that means where it overlaps a player).
- B+A held (L34738-34748) unlocks: sflags3/sflags bit 5 cleared, nibble 3 = $E, so it is hidden. Replay end (L34804) sets nibble 3 = $F.
- The other replay controls are out of scope.

### A.9 What does not exist, and related non-indicator sprites

- The sprite list (A.1) is exhaustive. There is no pass or one-timer target marker, no puck or puck-carrier arrow, and no on-ice face-off or line-change marker. On a pass, the pad star simply moves when `cNplayernum` changes (`input_linechanges.md`).
- Face-off close-up (`checkfo` L52017): sprites in front of everything, with attributes from `fofdata` ($8000 / $A800 / $8000, high priority), over the plane-A window. The port draws them in the HUD.
- `showcrowd` (L52175): penalty-box occupants (frames $1A+n home, $1D+n away, from `PBnum`) and crowd frames. They are rink-fixed, low priority, and last in the list. The two small priority blocks of the rink (B.3) cover parts of them.
- `sub_FD78A` (L970856): a rink-fixed overlay animation started by `sub_FE510` (from FallDown L49352 for fall SPA $18CC with |Y| <= 89, from puckfaceoff2 L42214, and from L56045). It is low priority and is not drawn in replay, reverse angle or horizontal mode. Content not identified (U6).

### A.10 Horizontal mode (penalty screen, `SetHor` L47101) differences

- No arrows (`checksso` returns).
- The puck-carrier nibble is neither cleared nor set each loop. This is how the penalized player's star works (A.3).
- Pad nibbles still update (`doinput` still runs). `uppads` and `setffo` still run, so stars and text are drawn with find3d's rotated mapping: origin at screen `(128 - Y, 309 - X)`. They are visible only for |Y| ≤ 144 and 53 ≤ X ≤ 341, i.e. players near the right-side boxes. The star art is not rotated.
- No replay cursor (the replay runs in vertical mode; `ClrHor` at L34510).

### A.11 Frame catalogue

| Frame | Hex | Use | Origin | Pieces / lines |
|---|---|---|---|---|
| 353 | $161 | gloves placeholder (retail) | (0,0) | 1 tile, line 0 |
| 384 / 385 / 386 | $180-$182 | pad 1 arrow: up / up-right / right | (13,7) / (19,5) / (18,12) | 3x3, line 1 |
| 387 / 388 / 389 | $183-$185 | pad 2 arrow | same | 3x3, line 0 |
| 390 | $186 | pad 1 star | (16,5) | text 2x1 + 1x1 (line 1), star 2x2 + mirrored 2x2 (line 1) |
| 391 | $187 | pad 2 star | (16,5) | text line 1, star line 0 |
| 392 | $188 | puck-carrier star (filled) | (16,5) | text line 1, star line 0 |
| 393 | $189 | replay cursor | (19,9) | text line 1, four 1x1 triangles line 1 |
| 838 / 839 / 840 | $346-$348 | pad 3 arrow | as 384-386 | 3x3, line 1 (same tiles as 387-389) |
| 841 / 842 / 843 | $349-$34B | pad 4 arrow | as 384-386 | 3x3, line 0 |
| 844 | $34C | pad 3 star | (16,5) | text line 1, star line 1 |
| 845 | $34D | pad 4 star | (16,5) | text line 1, star line 0 |

Correction to `animation_assets.md` §2.2: frames 838..845 are the pad 3/4 arrows (838-843) and the pad 3/4 stars (844-845). The pad 1/2 arrows are 384-389.

---

## B. Rink plane priority and transparency ("the bottom glass")

### B.1 VDP configuration during play

- `setupice` (L53024) and `setvram` (L44784): plane B = rink at $C000, scrolled by `updatescroll` (`Hscroll = -$40 - Hpos`, `Vscroll = -Vpos`). Plane A = $E000, filled with tile $7FF (L53045-53048). That tile is VRAM $FFE0, which is zero after setvram's VRAM clear, so it is transparent. Plane A scroll is never changed, so plane A is a fixed overlay. The window plane is off ($9100/$9200, L44841-44842). It is turned on only outside play: the pause screen (`$921C`, L30279) and the CPU-exception screen (`$9206`, L56512).
- Mode register 12: `$8C00` (H32) via `disflags` bit 1 (`setupice` L53027, `setvram` L44805-44813). The other writes are `$8C81` (H40, other screens, L34180, L965339) and `$8C00` (L34258). **Shadow/highlight (bit 3) is never set.** The "8 for shadow mode" at L44805 is only a comment. The `$8CA0` at L969753 is a counter value, not a register write.
- Background colour register 7 = `$8700` (L44843): **the backdrop is CRAM entry 0 = palette line 0 colour 0 = $0EE8** (R4 G7 B7, pale cyan; port `PaletteBank.cram` gives (0.571, 1, 1)). Colour 0 of every line in play is also $0EE8: rink lines 0-3, reverse rink, side view, and the home and away palettes of all 28 teams (checked in `palettes.json`).
- **The ice surface itself is colour 0.** 51.3% of the visible low-priority rink pixels (127266 / 248192) are colour 0, so on hardware the ice is the backdrop showing through plane B.

### B.2 Per-pixel composition (no shadow/highlight)

```
pixel(x, y):
  s = the first sprite in link order with a non-zero pixel here     ; sprite vs sprite = link order only
  A = plane A pixel (colour, prio) ; B = plane B pixel (colour, prio)  ; colour 0 = transparent
  for layer in [s if s.prio, A if A.prio, B if B.prio,
                s if not s.prio, A if not A.prio, B if not B.prio]:
     if layer exists and layer.colour != 0: return CRAM[layer]
  return CRAM[0]                                                    ; backdrop = $0EE8
```

Consequences (VDP behaviour; U1):
- A high-priority rink cell covers low-priority sprites only with its **non-zero** pixels. Where its pixel is colour 0, the sprite shows. With no sprite there, the backdrop shows. It is not the low plane, because plane B has a single pixel per position.
- Sprite masking: sprites are resolved against each other first. A low-priority sprite in front (earlier in the link list) of a high-priority sprite hides it, and the pair then goes behind any non-zero high-priority plane pixel. This can affect the replay cursor (behind every sort object, high priority), the puck after it leaves over the glass, and the bottom goal light, wherever a low sprite in front overlaps them on the glass band.

### B.3 Priority cells (what is "in front of the players")

Normal rink (`Rinktilelist` $5605A, map 48x113, only rows 0-84 visible): **202 priority cells, all in the visible rows**, mostly palette line 0.

| Map rows | Columns | Rink coords | Cells | Colour-0 pixels | What |
|---|---|---|---|---|---|
| 78 | 4-7, 40-43 | y -256..-263 | 8 | 38 / 512 (7.4%) | near corner boards |
| 79 | 4-13, 34-43 | y -264..-271 | 20 | 578 / 1280 (45.2%) | corner glass and boards |
| 80 | 6-41 | y -272..-279 | 36 | 1266 / 2304 (54.9%) | near end glass |
| 81 | 7-40 | y -280..-287 | 34 | 1148 / 2176 (52.8%) | glass |
| 82 | 8-39 | y -288..-295 | 32 | 1110 / 2048 (54.2%) | glass |
| 83 | 9-38 | y -296..-303 | 30 | 0 / 1920 (0%) | dasher board top (opaque) |
| 84 | 9-38 | y -304..-311 | 30 | 0 / 1920 (0%) | board (opaque; a few line-1 cells) |
| 52-53 | 42-44 | x 144..167, y -48..-63 | 6 | 95 / 384 | near wall of the right (home) penalty box (box at rows 49-51) |
| 59-60 | 3-5 | x -168..-145, y -104..-119 | 6 | 122 / 384 | near end wall of the left (home) bench (rows 47-58) |
| total | | | 202 | **4357 / 12928 (33.7%)** | |

- The glass rows 79-82 are 4102 / 7808 = **52.5% colour 0**. This is not a checkerboard dither. The panes are drawn as sparse art on colour 0: diagonal reflection streaks in colour 2 ($0EEC), the top rail in colour 1 ($0EEE), and stanchions and corner caps in colours 4/14 ($0000/$0222) and 6 ($0666). Players behind the near net therefore show through the glass between the streaks. The boards (rows 83-84) hide them completely.
- The away bench and away box near walls are not priority cells.
- Visibility: the band (map px rows 624-679) is on screen only when `Vpos` ≤ -145. At `Vpos` = -200 it covers screen rows 168-223.
- Reverse rink (`RevRinkTilelist` $B5180, reverse-angle replays): 159 priority cells, rows 78-84 only, no door cells. 3970 / 10176 = 39.0% colour 0. Not left-right symmetric: column 31 is low priority in rows 81-84.
- Side view (`icerinkmap` / PauseScreen map $BC05C, 32x28, drawn by `SetHor` with `printa` = 0 and `printm` = plane B): **no priority cells**. 9341 / 57344 pixels are colour 0 (backdrop). Sprites are always in front of it.
- Centre-ice logo cells (rows 44-47): low priority.

### B.4 Which sprites use the priority bit

- **No sprite piece** has bit 15 (0 of 2785 pieces in frames 1-845). No SPA frame word carries flag bits (the only $F800 values are the known junk direction-7 entries of $F6E/$FAC). So players, goalies, nets, the puck in flight, the shadow and the gloves are all low priority. Depth among them comes only from `SprSort` order. Players behind the near net are in front of it (smaller Y). The near goalie is behind the near net (net Y -268 < goalie Y). There is no special case.
- Object attributes with $8000 (`addframe2` L52918-52931: `(piece.flags ^ attr) & $F800`):

| Object | Set | Cleared | Why |
|---|---|---|---|
| puck (SC 14) | `wallcollb2` L50122-50124, when the puck leaves the rink over the boards (Z > $1D, or the glass-shatter case) **and Y < 0** | `puckfaceoff2` L42102 (`clr word_FFB74E`), `puckpenshot` L41324 | it flies over the near glass toward the viewer |
| puck shadow (SC 15) when it is the goal light (SPA $102E, frames 563+, set by `checkgoal` L49954-49956) | `puckshadow` `_siren` L42882-42886: puck Y < 0 → attr = $8000, Y = -300, Z = 13 (else Y = +300, Z = 14, attr unchanged) | `puckfaceoff2` L42101, `puckpenshot` L41323 | the bottom goal light sits on the near glass |
| replay cursor (ffo 3) | `_listffo` L53384 (constant) | never | visible over the near glass |
| face-off close-up sprites | `fofdata` attrs | n/a | over the plane-A face-off window |

- The glass-shatter animation (SPA $1078, frames 653-657, listing L35101-35103 "glass shatter frames") also runs on the shadow through the same `_siren` path. It happens only at the top end (Y ≥ $118), so it never gets the priority bit.
- Replay: `SetRCords` restores only the flip bits (`andi #$E7FF / or`, L35112-35114). Each object keeps whatever priority bit it had when the replay began.

### B.5 Plane A overlays

- Vertical mode: the score/clock box (`PrintScores1` string `$BF` → `printa` = $8000, rows 23-27 at the left; `showclock` digits with `$8000`), the ref window (`PushRef` `ori #$8000`, L46640), and the face-off window (`dobitmap` XORs the current `printa`; U5). All are high priority, so they are above every low sprite and above the glass, and below high-priority sprites.
- Horizontal mode: the ref window has **no** priority bit (L46636-46640 skips the `ori`), so low sprites are drawn over it.

### B.6 Port comparison

Port state:
- `tools/extract/assets.py` `rink_layers`/`rink_tileset`/`side_view` export every plane tile with `opaque=True`. `rink.gd` builds `RinkBase` (z -4000) from the low cells and `RinkFront` (z 4000) from the priority cells, both with the **same** `PaletteBank` material. So colour 0 is opaque $0EE8 in both.
- The sprites (`Skater2D`, `SortObjectView`) use `z = clamp(screen_y, -3000, 3000)` and ignore `attribute` bit 15. `GlovesView` is at -3998 and `DebugOverlay` at 4001. `project.godot` sets no clear colour (Godot default grey).
- The port has no indicator views at all (no stars, text, arrows or replay cursor).

Effects:
- Base layer: colour 0 → $0EE8 = backdrop. This **matches** hardware.
- Front layer: its 4357 colour-0 pixels (52.5% of the glass rows) are painted as opaque ice-coloured blocks over every sprite in the band. Players skating behind the near net disappear behind a pale wall instead of showing through the glass. This is wrong.
- The puck that leaves over the near glass, the bottom goal light, and the replay cursor should be drawn over the front layer. Today they are under it.

What the port must do to match hardware:

1. **Colour 0 transparent in the front layer only.** Add `uniform bool zero_transparent = false;` to `shaders/palette.gdshader`, with `if (zero_transparent && idx == 0) { discard; }`. Give `front_layer` its own `PaletteBank.material(...)` with the flag set. `tiles_idx.png` can stay as is, because colour 0 is encoded as R = 0 with A = 255.
2. **A backdrop under the transparent pixels.** The base layer has no tile under priority cells. Either (a) also put every priority cell in `base_layer` (opaque), which gives CRAM colour 0 = $0EE8 exactly as the hardware backdrop does, since every line's colour 0 is $0EE8; or (b) add a backdrop rect at z -4096 coloured from palette texel (0, 0), so palette fades apply. A more general option is to make the plane shader map index 0 to texel (0, line 0) for every line.
3. **Priority sprites above the front layer.** When `obj.attribute & SimObject.ATTR_PRIORITY`, give the view `z = Z_FRONT + 1 + k`, keeping their mutual order by screen y. That covers the puck (`puck_logic.gd` L807) and the shadow (`puckshadow` L282), and the replay cursor if one is added. Move `DebugOverlay` above that range (for example 4090). Godot `z_index` is limited to ±4096.
4. **Sprite masking (optional).** z order cannot express "low sprite in front of a high sprite, both behind the glass" (B.2). An exact version needs the sprite layer rendered separately: a SubViewport with a per-pixel priority channel, then plane B low, low sprites, plane B high, high sprites composited in that order. Otherwise accept the difference. It only shows where a priority sprite overlaps a lower-Y sprite on the glass band.
5. **Plane A overlays.** The HUD `CanvasLayer` is above everything. That matches the vertical-mode high-priority boxes, except that retail high-priority sprites (B.4) would be drawn over them. On the penalty screen retail draws low sprites over the ref window. Both differences are minor.
6. **Reverse-angle rink** (if reverse replays are added): build the layers from `RevRinkTilelist` with the same rules (159 priority cells, colour 0 transparent in the front layer, logo rotated 180°). The exported `rink_reverse_front_idx.png` is opaque too.
7. **Side view**: no change needed. It has no priority cells, and its colour 0 equals the backdrop.
8. Plane-on-plane: there is nothing else to order. Plane A is blank outside the HUD boxes, and the window plane is off in play.

---

## Port changes needed (checklist)

Rink and priority (Part B):
- [ ] `shaders/palette.gdshader`: `zero_transparent` uniform; discard index 0 when set.
- [ ] `nodes/rink.gd`: a separate material for `front_layer` with `zero_transparent = true`.
- [ ] `nodes/rink.gd`: priority cells also in `base_layer` (or a $0EE8 backdrop at z -4096 from palette texel (0,0)), so the transparent glass pixels show the backdrop, not Godot's clear colour.
- [ ] `nodes/sort_object_view.gd` (and `skater.gd` for completeness): z above `Rink2D.Z_FRONT` when `attribute & ATTR_PRIORITY`. Keep the screen-y order inside that range.
- [ ] `nodes/debug_overlay.gd`: move above the priority-sprite range.
- [ ] Optional: exact sprite-masking compositor (B.6 item 4).
- [ ] If reverse replays are added: reverse-rink layers with the same split (159 cells) and transparency.
- [ ] `tools/extract/assets.py`: the docstring says "plane tiles are opaque". Note that front-layer colour 0 must be transparent at draw time. Export `rink_front_idx.png` / `rink_reverse_front_idx.png` with `opaque=False` if anything is ever going to use them (nothing does today).

Indicators (Part A):
- [ ] World state: `marks` = 6 nibbles (ffo 0-5, $F = hidden, $E = own position) and `padcont[6]`. Write them as A.3 describes: reset nibble 0 to $F at the start of each `updateplayers` (vertical only). Set it to puckc after the carrier checks (on ice, not fighting, not horizontal). Pad k → its controlled player on every doinput. `asspenalty` first call → nibble 0. Period start / `setupice` → all $F.
- [ ] `byte_FFC2FC` bit 7 equivalent (set by `puckshootout`, cleared by `puckfaceoff`) for the blank position letter in PS/SO. Clear the text cache at those two points and at the replay start.
- [ ] Extractor: export the raw font glyphs from `$AAC52` (tiles through the 32x4 char map, **no colour remap**, drawn with palette line 1). At least ' ', '0'-'9', 'C', 'D', 'L', 'R', 'X'. `tools/extract/title.py` only exports the remapped title font.
- [ ] A pad-marker view: for ffo 0..5 draw frame 392/390/391/393/844/845 at the marked object's (X, Y) with Z = 0 (find3d without height; rotated mapping in horizontal mode). Draw the three glyphs at (-12+s, 11), (-4+s, 11), (6+s, 11) relative to the origin, with s from A.5.
- [ ] Z for the stars: behind **every** sort object and above the logo and the gloves, in ffo order (ffo 0 front-most): for example ffo0 -3990, ffo1 -3991, ffo2 -3992, ffo4 -3994, ffo5 -3995. The gloves stay at -3998. Low priority, so the front layer covers them.
- [ ] An arrow view (`checksso`): vertical mode only. For pads 1, 2, (3 if a pad-3 team), (4 if pad-3 and pad-4 teams). Hidden when the pad star is hidden. Use the |X| ≥ 166 suppression in SO/PS/replay, the thresholds, clamps, frames and flips from the A.7 table, and the previous loop's star position. Z in front of every sort object and below the front layer (for example 3001-3004, pad 1 front-most).
- [ ] Port decision: the retail edge rule is relative to a 256-wide screen (`|dx| ≥ 116`, clamp to ±116). On the 320-wide port either keep it (arrows at port x 44/276) or widen it to `half_width - 12` = 148 (arrows at 12/308). The vertical values (±100, y 12/212) are exact as they are.
- [ ] Replay cursor (only if instant replay is ported): A.8, attribute $8000.
- [ ] Penalty screen: keep the nibble-0 marker on the penalized player while `SF_HOR` is set. No arrows.

Side finding: `godot/logic/puck_logic.gd` names SPA $1078 `SPA_GOAL_LIGHT` and comments "goal light above the top glass". $1078 is the **glass-shatter** animation (frames 653-657, listing L35101-35103). The goal light is SPA $102E (frames 563+, `checkgoal` L49956). The mechanism (the shadow plays it through `_siren`) is the same.

---

## Unresolved

- U1. The composition rules in B.2 (backdrop through transparent high-priority pixels, sprite masking by link order) are standard VDP behaviour. They are not something the listing shows, and they were not checked on an emulator here.
- U2. The garbage position glyph for a marked object with `$34` = -1 (A.5) was not shown to be reachable.
- U3. The penalized-player star in the side view (A.3, A.10) follows from the code. It was not confirmed with a render.
- U4. Sprite limits are not modelled: in H32, 64 sprites per frame and 16 sprites / 256 px per line. `addframe2` does not check them, while `SetSframe`, `sub_16246` and `sub_FD78A` stop at 64. On crowded lines the stars, being late in the list, are the first to drop on hardware.
- U5. The face-off window's plane-A priority depends on `printa` at the time `dobitmap` runs (L42236-42250). It was not traced.
- U6. What `sub_FD78A`'s overlay animation (table `unk_FE364`, started via `sub_FE510`) shows.
- U7. Replay controls other than the cursor (A.8) are not documented.
