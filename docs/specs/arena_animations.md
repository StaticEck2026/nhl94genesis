# Arena sprite animations: crowd, penalty box, background animations, zamboni

This spec covers audit_animation.md gaps G5-G8. It describes how retail NHL '94 steps and draws four kinds of sprites, what the exported assets contain, and what the Godot port must add.

The four sprite kinds are:
- the crowd
- the penalty-box occupants
- the eight arena/bench background animations
- the intermission zamboni

Sources:
- listing: `lst/nhl94.bin.lst` (line numbers are written `Lnnnnn`)
- ROM: `lst/nhl94.bin`, CRC32 `$9438F5DD`
- assets: written by `tools/extract/arena.py` to `godot/assets/arena/`

The data formats below were checked by decoding the ROM. The renders listed in §7 were inspected by eye. Everything not confirmed that way is marked **UNRESOLVED**.

## 0. Assets and coordinate spaces

### 0.1 Files

| File | Source | Contents |
|---|---|---|
| `crowd_idx.png`, `crowd.json` | CrowdFrameList `$A4B54`, `$76` raw tiles | 62 frames. 152 assembled figures in a 512x128 sheet. Also the `_cd0` table (`$18CFC`) and the frame groups. |
| `bganim_idx.png`, `bganim.json` | table `unk_FE364` (`$FE364`) and frame files `$EA2EC`, `$EAB10`, `$EB816`, `$EC284`, `$ED1B0` | 8 ids, each with its script, end type, length, contents and trigger. The 5 files' frames. 166 assembled figures in a 512x256 sheet. The faceoff id table `unk_FECE6`. |
| `zamboni_idx.png`, `zamboni.json` | ZamFrameList `$A8922`, `$7D` raw tiles | 8 frames, each one assembled image in a 256x64 sheet. The wave table `unk_1615E`. |

The index textures use the same encoding as `assets.py`:
- R = colour index × 17
- G = palette line × 85
- A = 255 where a pixel is drawn

Colour 0 is transparent. Colour them with `shaders/palette.gdshader` and the game's CRAM. That is `game.palette_texture()`, or `palette_texture(true)` on the side view; its lines 0 and 1 are identical to the rink's. Never pass `away = true`: these sprites carry their own palette line, and retail does no line 2→3 swap for them (§0.3).

The export is deterministic: the packing order is stable and the JSON key order is fixed. Running the tool twice gives byte-identical files.

Command: `python3 tools/extract/arena.py [lst/nhl94.bin] [godot/assets/arena]`

### 0.2 File format and JSON schema

All seven ROM files share one header layout, which is also the layout of `ZamFrameList` and `CrowdFrameList`:

```
+0  long  offset to a 16-colour block (copied from the rink line 0; never loaded by the game)
+4  long  offset to the frame table: words w[0..n+1], w[0] = 0, w[1] = table size,
          frame f (1..n) = 8-byte pieces from table + w[f] to table + w[f+1], n = w[1]/2 - 2
+8  word  tile count (the loader sub_11738 receives this address; bit 15 would mean compressed)
+10 tiles
piece: +0 s16 x, +2 s16 y (top-left, +y down), +4 u16 first tile (column-major), +6 u16:
       bits 15-11 = VDP flags (15 priority, 14-13 palette line, 12 v-flip, 11 h-flip),
       bits 7-0 = VDP size byte (w = ((s >> 2) & 3) + 1, h = (s & 3) + 1 tiles)
```

The JSON files hold **assembled character sheets**, not hardware pieces:
- The extractor composites each frame's pieces in VDP link order (the first piece in front) into figures: one image per group of touching pieces (a fan, a camera flash, a seated player, a hat, a bench player), or the whole frame for the zamboni. Identical figures are stored once.
- `sprites[id]` holds a figure's sheet `rect` and the palette `lines` it uses.
- `frames[f].parts` is a list of `[x, y, sprite id]`: the figure's top-left in the frame's native space. Figures of one frame never overlap, so draw order inside a frame does not matter.
- `bbox` is the frame's extent in its native space. `lines` lists the palette lines the frame uses.

Why figures instead of whole frames: crowd frames 1-18 and the flash frames spread over the whole 384x680 arena, so a whole-frame image would be almost empty. The renders are pixel-identical to compositing the pieces at runtime (checked against the earlier piece-based view). Retail's piece-by-piece cull (§0.4) is not reproduced; the port clips by figure.

Other notes on the data:
- No piece in any of these files has the priority bit (bit 15) set (checked by the export).
- `$EA2EC` frames 14-15 and `$ED1B0` frame 1 each carry a blank 8x8 placeholder piece at (0,0). It draws nothing, but in retail it still takes a sprite link when it is in view.
- Frame counts: crowd 62 (not 63 as the audit says: the 64-word table ends with the sentinel), `$EA2EC` 15, `$EAB10` 28, `$EB816` 8, `$EC284` 23, `$ED1B0` 10, zamboni 8.

### 0.3 Spaces and conversions

The game draws every piece with:
- SAT attribute = `(word6 & $F800) + tile + VRAM base`
- no object flip XOR
- no away-team palette swap

The VRAM bases are `word_FFB01A` for the crowd (set by setupice L53063), `word_FFD6AC` for the bganims (L53066, with `$32` tiles reserved), and `ExtraChars` for the zamboni. The port can ignore the VRAM bases.

| Data | Native space | To screen (256x224) | To the port (HockeyGame-local, Godot axes) |
|---|---|---|---|
| crowd frames 1-31, all bganim frames | rink-map pixels (the same space as `rink/map.json`) | `(mx - (Hpos + 64), my - (256 - Vpos))` | `(mx - 192, my - 368)`. That is `origin_px` from map.json, and equals `Nhl94Units.rink_to_godot(mx - 192, 368 - my)`. |
| crowd frames 32-62 (horizontal mode) | screen pixels of the side view | as is | `(sx - 128, sy - 112)`. The side Sprite2D is centred on the origin, and RinkCamera sits at (0,0) in horizontal mode. |
| zamboni frames | pixels relative to the zamboni origin | origin = `((zamx >> 2) - 128, $12A - 128 = 170)` | origin = `((zamx >> 2) - 256, 58)` |

The relation map pixel ↔ rink is `mx = rink_x + 192`, `my = 368 - rink_y` (animation_assets.md §3.2). `Hpos`/`Vpos` is `HockeyWorld.camera`.

### 0.4 Culling and the sprite budget (sub_16246 L52221, identical code in sub_FD78A L970856)

```
for each piece p of frame f (link order):
    if Hpos + $30 <= p.x <= Hpos + $140 and $F0 - Vpos <= p.y <= $1E0 - Vpos:   ; signed words
        link it: SAT.y = p.y + Vpos - $80, SAT.x = p.x - Hpos + $40              ; VDP coords (+128)
        d6 += 1 ; if d6 == $40: stop everything (sprite table full)
```

- In screen terms, a piece is linked when its **top-left** satisfies -16 ≤ sx ≤ 256 and -16 ≤ sy ≤ 224. A piece wider than 16 px whose corner is further left or further up is dropped even though part of it would be visible. That is an edge effect only.
- In horizontal mode, showcrowd passes Hpos = -64 and Vpos = `$100`, so the screen-pixel frames 32-62 go through the same test.
- **Sprite budget:**
  - `setvideo` starts `d6` at 1. All layers share one 64-entry link table: H32 mode allows 64 sprites, 16 per scanline and 256 sprite pixels per line.
  - The crowd is linked **last**, so its pieces are the first to be cut when the earlier layers have used the table. The earlier layers are the faceoff close-up, the off-screen arrows, the sort objects, the pad stars, the zamboni and the bganim. Crowd frames 14-18 have 76-80 pieces.
  - The per-line limit can also drop pieces on busy lines.
  - The port draws without these limits. In crowded scenes it will therefore show more crowd than retail. Exact emulation would have to count the links of every earlier layer in setvideo order and stop the crowd at link 63. That is optional, and it is low priority.

## 1. Draw order (setvideo L51875)

`setvideo` links the sprite layers in this order. The first link is in front.

| # | Routine | Layer | Port today |
|---|---|---|---|
| 1 | checkfo | faceoff close-up | FaceoffWindow (UI) |
| 2 | checksso | off-screen arrows | missing (G2) |
| 3 | setsortcords | 16 sort objects | Skater2D / SortObjectView, z = screen Y within ±3000 |
| 4 | setffo | pad stars, gloves | GlovesView z = `Rink2D.Z_LOGO + 1` |
| 5 | showclock | clock (window tiles, not sprites) | HUD |
| 6 | **showzam** L52076 | zamboni | **new** |
| 7 | **sub_FD78A** | background animation | **new** |
| 8 | **showcrowd** L52175 | penalty box away (`$1A+n-1` … `$1A`), penalty box home (`$1D+n-1` … `$1D`), flash frame (crowdframe high byte), crowd frame (low byte) | **new** |
| 9 | showref | referee window (plane tiles) | RefWindow |

All arena pieces are low-priority sprites:
- They are drawn over plane B's low-priority cells and over the centre logo.
- They are drawn under the rink's high-priority cells: the near boards and glass (map rows 78-84) and the bench and box doors (rows 52, 53, 59, 60).
- The renders show this matters. Crowd pieces in the bottom corners and the legs of home-box frame `$1F` touch priority cells.

The side view has no priority cells.

Port placement:
- Put a single view under HockeyGame at `z_index = Rink2D.Z_LOGO + 1` with `z_as_relative = false`, the same z as GlovesView.
- Add it **before** GlovesView in `add_object_views()`, so that tree order puts the gloves over it.
- Inside the view, draw back to front: crowd, flash, home box, away box, bganim, zamboni. A frame's figures do not overlap.

Everything then stays under `Rink2D.Z_FRONT` (4000), so RinkFront covers it the way the VDP does. It also stays under every sort object.

## 2. Crowd (G5)

### 2.1 Frames

| Frames (normal / horizontal) | Group | What the render shows | Lines |
|---|---|---|---|
| 1-18 / 32-49 | crowd (crowdframe low byte) | Pieces over individual fans in the stands all round the rink: the top end (map y < 72), the left stands (x < 64) and the right stands (x ≥ 320), down to the bottom corners (y ≤ 688). Frames 1-13 are small moves (heads, arms; 22-33 pieces). Frames 14-18 have many fans standing (76-80 pieces). On the side view (32-49) they are the fans below the scoreboard (screen y 104-136). | 1 |
| 19-25 / 50-56 | flash (high byte, the "excited" frame) | Camera flashes: 16x16 white stars (tile 15) at 1-18 scattered seats. | 0 |
| 26-28 / 57-59 | away penalty box, one seated player per frame | Normal view: right-hand box, map x 336-352. Frame `$1A` is at y 306, `$1B` at y 295, `$1C` at y 286, each 32 px tall, so they stack upward. Side view: x 90 / 71 / 54, y 143. | jersey 3, legs 2 (data quirk: the away player's 8x16 leg piece uses line 2, the home colours); side view 3 |
| 29-31 / 60-62 | home penalty box | Normal view: x 336-352, y 375 / 384 / 394. Side view: x 150 / 165 / 185, y 143. | 2 |

Per-piece positions are in `crowd.json`. Previews: `crowd_frames_1-18.png`, `crowd_frame14_outlined.png` (every piece outlined), `crowd_flash_19-25.png`, `crowd_box_26-31.png`, `crowd_side_*.png`.

### 2.2 `_cd0` (L56543, ROM `$18CFC`): 4 rows × 16 `{frame, delay mask}`

| Row | crowdlevel | Frames for columns 0-15 | Mask | Frame duration (loops, d7 = 1) |
|---|---|---|---|---|
| 0 | `< $40` | 1 2 3 4 5 10 9 8 6 7 8 9 10 5 4 3 | `$C` | 13, 17, 21 or 25 |
| 1 | `$40-$7F` | 1 2 3 4 5 11 12 13 6 7 8 9 10 11 12 13 | 7 | 8-15 |
| 2 | `$80-$BF` | 14 15 16 17 18 11 12 13 18 17 16 15 14 13 12 11 | 7 | 8-15 |
| 3 | `≥ $C0` | same as row 2 | 3 | 4-7 |

### 2.3 Stepping: updatecrowdf (L30028)

Callers:
- `periodiceevents` (L29940), once per DoGameFrame with d7 = elapsed vblanks. This includes horizontal mode.
- `waitxsr` (L44352), once per vblank with d7 = 1, during the intermission.

It is not called during pause, during the instant-replay viewer (which plays back the recorded crowdframe word, see below) or on other menu screens.

```
updatecrowdf(d7):
    if crowdlevel >= $15E: crowdlevel -= 3                  ; extra decay when loud (signed compare)
    crowdlevel -= d7 ; if crowdlevel < 0: crowdlevel = 0
    crowdcnt -= d7
    if crowdcnt < 0:                                        ; a new base frame
        row = min(crowdlevel >> 1, $7F) & $60               ; byte offset 0/$20/$40/$60 = row 0..3
        crowdstep = (crowdstep + 2) & $1E                   ; next column, incremented BEFORE use
        crowdframe.lo = _cd0[row + crowdstep]               ; frame 1..$12
        mask = _cd0[row + crowdstep + 1]
        crowdcnt = mask + (VDP_CNTR & mask)                 ; HV counter as the random source
    crowdframe.hi = 0                                       ; EVERY call
    if crowdlevel > $118:                                   ; unsigned
        r = VDP_CNTR & $7F
        if $13 <= r <= $19: crowdframe.hi = r               ; a flash frame for this one loop
```

- crowdlevel comes from the many `addi #n,(crowdlevel)` sites (already ported) and is capped at `$258` at each faceoff (L42059).
- `CwdExciteLvl` does **not** affect the frames. It only feeds the crowd meter, the statistics and the PSG noise level.
- A flash appears on about 7/128 of loops while crowdlevel > 280 (`$118`). Each flash lasts exactly one loop, so flashes flicker.
- The instant replay records the crowdframe word and PBnum per frame (updatereplay L35311-35313) and restores them (SetRCords L35171-35173). The port has no replay.

### 2.4 Drawing: showcrowd (L52175) / sub_16226 (L52202) / sub_16246 (L52221)

```
showcrowd:
    if word_FFC2F4 bit 4 (reverse-angle replay): return
    (Hpos', Vpos') = horizontal (sflags bit 7) ? (-$40, $100) : (Hpos, Vpos)
    box(PBnum & $F, $1A)          ; away: assdopen adds 1 for away, $10 for home (L38119-38127)
    box(PBnum >> 4, $1D)          ; home
    draw(crowdframe.hi)           ; flash, 0 = none
    draw(crowdframe.lo)           ; crowd
box(n, base): n = min(n, 3) ; for k = n-1 down to 0: draw(base + k)
draw(f): if f == 0: return ; if horizontal: f += $1F ; if d6 >= $40: return ; link the pieces (§0.4)
```

The crowd is therefore visible in these places:
- in play;
- on the faceoff screen;
- on the horizontal penalty screen and the intermission, using frames 32-62;
- in the pause menu, which runs one setvideo at entry under SetHor (sub_7DCE L30275). The frames are frozen there.

It is hidden only in the reverse-angle replay.

### 2.5 Port

**Logic, in GameRules.updatecrowdf (game_rules.gd ~818):**
- Today it stores `crowd_frame = d0 + crowd_step`. That is the table offset, not the frame number.
- Replace it with `crowd_frame = CD0[d0 + crowd_step]` and `mask = CD0[d0 + crowd_step + 1]`. The table can be a const copied from `crowd.json` `cd0`, or loaded from that file. The current mask derivation already matches the table.
- Add `crowd_flash`. Clear it on every call, and when `w.crowd_level > 0x118` set it to `r = w.hv_rng.randi() & 0x7F` if r is in `$13..$19`.
- The call site `HockeyWorld.periodic_events` is already correct, including horizontal mode.
- Penalty box: `LineLogic.pbnum[1]` (away) → `$1A`, `pbnum[0]` (home) → `$1D` (line_logic.gd:55, 458, 470). That matches retail's nibbles.

**Drawing, in a new view under HockeyGame (§1 placement):**
- Each `stepped`, read `rules.crowd_frame`, `rules.crowd_flash` and `lines.pbnum`.
- Pick `+31` frames and side-view coordinates when `w.sflags & SF_HOR`.
- Convert positions as in §0.3.
- Optionally apply the §0.4 per-piece cull with `w.camera`. Viewport clipping alone differs only at the edges.

## 3. Penalty-box occupants (G6)

Covered by §2.4. The data and draw details:
- `n = min(nibble, 3)` seated figures per team.
- Frames `$1A+k` (away) and `$1D+k` (home) for k = 0..n-1. The highest k is linked first (in front).
- The figures are drawn at fixed rink-map positions inside the right-hand boxes. The away box is the upper one (map y 286-338, rink y 82..30). The home box is the lower one (map y 375-426, rink y -7..-58).
- In horizontal mode the figures sit at fixed screen positions on the side view's bench row.
- The boxed player's own sort object is hidden while it sits: assdopen sets `$34` negative and clears the frame.

The figures:
- carry no jersey number;
- are always the team uniform, line 3 for away and line 2 for home, with the away legs in line 2 as noted in §2.1;
- do not change with which player is boxed.

The port already counts `pbnum`. Only the view is missing.

## 4. Background animations (G7)

### 4.1 The eight ids (table `unk_FE364` L973520, ROM `$FE364`: {long script, long file})

| id | File (tiles) | Frames used | Script (frame, vblanks) | End | Length (vblanks) | Map area (px) | Lines | What it shows (render) | Started by |
|---|---|---|---|---|---|---|---|---|---|
| 0 | `$EA2EC` (31) | 1-15 | 1-14 at 10 each, 15 at 127 | `$FE` stop | 282 | x 112-279, y -1-102 (behind and below the top goal) | 1 | Hat trick. Fans behind the top goal stand with arms up (frames 1-4), hats fly over the top glass (5-12) and land on the ice around the top goal (13-15). When the animation ends, the hats vanish. | home skater's 3rd goal (§4.4) |
| 1 | `$EAB10` (36) | 1-14 | 1,2,3 at 8; 4 at 30; 5,6,7 at 8; 8 at 30; 5,6,7 at 8; 8 at 30; 9-14 at 8 | stop | 228 | x 112-136, y 16-66 (top end stands, left) | 0, 1 | A fan leaves his seat, comes down to the glass, waves both arms (4-8, twice), ducks (9) and climbs back to his seat (10-14). | faceoff |
| 2 | `$EAB10` | 15-28 | same pattern on 15-28 | stop | 228 | x 248-272, y 16-66 (top end stands, right) | 0, 1 | Id 1's fan on the right side. | faceoff |
| 3 | `$EB816` (50) | 1-8 | 1-8 at 8 | `$FF` loop | 72 per cycle | x 8-376, y 0-145 (top end stands and both upper corners) | 1 | Scattered fans jump up with arms raised, a different set each frame. | faceoff |
| 4 | `$EC284` (43) | 1-4 | 1, 2 at 8; then (3 at 60, 4 at 60) ×19; then 2, 1 at 8 | loop | 2354 per cycle | x -7-264, y -5-85 | 1 | Fans get up into the aisles of the upper-left corner and the top end stands, shift there, and go back. | **no caller** (§4.4) |
| 5 | `$EC284` | 1-23 | 1-23 at 10 | stop | 253 | x -7-264, y -7-90 | 0, 1 | Fans walk down the aisles (1-8). One comes down the top-right aisle to the front row behind the glass and walks right along it (9-23). | faceoff |
| 6 | `$ED1B0` (50) | 1-10 | 1-10 at 10 | loop | 110 per cycle | x 25-57, y 239-464 (both benches) | 2, 3 | The players on both benches stand up and lean over the boards in a ripple along the bench. The away bench (y 239-327, rink y 129..41) is drawn in line 3. The home bench (y 375-464, rink y -7..-96) is drawn in line 2. | faceoff at the left lower spots |
| 7 | `$ED1B0` | 1-10 | (1-10 at 10) ×3 | stop | 330 | as id 6 | 2, 3 | Id 6's ripple three times. | check over the left boards at the benches |

How the columns are counted:
- The "vblanks" value in a script is the counter preload. Each entry is shown for that value + 1 loops (§4.2).
- "Length" is the sum of those, from the start to removal (or one cycle for a loop).

All files fit the `$32`-tile VRAM slot. Previews: `bganim_id0..7.png` (each id's frames over the rink, with the near glass applied), `bganim_EB816_dim.png` and `bganim_EC284_dim.png` (frames over a dimmed rink), and `bganim_locator.png` (every frame's bbox).

### 4.2 Start, step, stop, draw

```
sub_FE510(d0 = id):                       ; START, L973950
    word_FFD6B4 = id                      ; current id (-1 = none)
    dword_FFD6B6 = 0 ; dword_FFD6BA = 0   ; script and file pointers: "not loaded yet"
    word_FFD6AE = 1                       ; frame (not drawn while the file pointer is 0)
    word_FFD6B0 = 0                       ; script index
    st word_FFD6BE                        ; high byte $FF: consumes any pending faceoff id

sub_FE2C8(d7):                            ; STEP, L973463: periodiceevents (every loop, also in
    if word_FFD6B4 < 0: return            ;   horizontal mode) and waitxsr (every intermission vblank)
    if dword_FFD6BA == 0:                 ; first step after a start
        script, file = unk_FE364[id]
        load file's tiles (file + 8) to VRAM tile word_FFD6AC
        index = 0 ; sub_FE326()
    else:
        counter -= d7
        if counter < 0: index += 1 ; sub_FE326()

sub_FE326:                                ; L973496
    frame = sext(script[2*index]) ; counter = sext(script[2*index + 1])
    if frame == -1 ($FF): index = 0 ; goto sub_FE326       ; loop
    if frame == -2 ($FE): sub_FE548()                     ; end

sub_FE548:                                ; STOP, L973971 (also at the puck drop, L42325)
    word_FFD6B4 = -1 ; byte_FFC2FC bit 0 = 0

sub_FD78A:                                ; DRAW, L970856 (from setvideo)
    if word_FFD6B4 < 0 or dword_FFD6BA == 0: return
    if word_FFC2F4 bit 4 (reverse-angle replay): return
    if sflags2 bit 3 (instant-replay viewer running: set L34508, cleared L34810): return
    if sflags bit 7 (horizontal mode: penalty screen, intermission, pause): return
    f = sext(low byte of word_FFD6AE) ; if f == 0 or d6 >= $40: return
    link frame f's pieces with the §0.4 cull, attribute (w6 & $F800) + tile + word_FFD6AC
```

Consequences:
- The first entry is shown from the starting loop, for `delay + 1` loops. Every later entry is also shown for `delay + 1` loops.
- A `$FE` end removes the sprites in the same loop. The last frame does not stay on screen.
- A new start always replaces the running animation.
- Suppression affects drawing only. In horizontal mode and during the intermission the script keeps advancing out of sight.
- There is no reverse-replay variant of the art. Retail simply hides it. There is no horizontal variant either.
- During the instant replay neither `periodiceevents` nor `sub_FE2C8` runs, so the animation is frozen and hidden.

### 4.3 Faceoff ids (puckfaceoff L41627, sub_FECAA L974897, puckfaceoff2 L42031)

```
puckfaceoff, first call (L41651-41661):
    if word_FFD6BE >= 0: d0 = word_FFD6BE               ; a pending id is reused
    else: d0 = sub_FECAA()
    if d0 >= 0: sub_FE53C(d0)                           ; byte_FFC2FC bit 0 = 1, word_FFD6BE = d0
sub_FECAA:
    d0 = unk_FECE6[randomd0($64) & 7]                   ; 3,5,3,1,5,2,3,3 (0-99 & 7: 0-3 slightly likelier)
    if fox <= -64 and foy <= 192: d0 = 6                ; signed; faceoff spot on the left (x <= -$40),
    return d0                                           ;   anywhere but the top end ($CE)
... line-change wait ...; L41800: word_FFD6C6 = -1 (a different, write-only word); assreplace $1C
puckfaceoff2, first call (setup):
    L42048-42052: if fox == 0 and foy == 0: word_FFD6BE = -1      ; no animation at centre ice
    L42209-42214: word_FFD6B4 = -1                                ; kill whatever runs (id 7, hat trick)
                  if byte_FFC2FC bit 0 and word_FFD6BE >= 0: sub_FE510(word_FFD6BE)
    L42271-42290: drop time = randomd0($78) + $B4 (180-299 loops);
                  if word_FFD6B4 in {0, 1, 5, 4, 2}: drop time = max(drop time, $10E)
puckfaceoff2 per loop (_nna L42322): if --drop time < 0: sub_FE548() ; Endfaceoff
```

- The `$10E` (270) minimum makes the one-shot ids 1, 2 and 5 (228-253 vblanks) finish before the puck drops.
- Ids 3 and 6 loop until the drop.
- So at faceoffs: ids 1, 2 and 5 are one-shots; id 3 is the most common (4/8); id 6 is forced for left-side spots outside the top end.
- Ids 1-5 play in the top end stands. When the faceoff is in the lower half of the rink, the camera cannot see them, but they still run.

**Quirk: a lost start.**
- An earlier animation (id 7 or the hat trick) may reach its `$FE` during the line-change wait, after puckfaceoff has picked an id. Its sub_FE548 then clears `byte_FFC2FC` bit 0.
- puckfaceoff2 therefore starts nothing.
- `word_FFD6BE` keeps the picked id, and the next stoppage reuses it instead of rolling a new one.

### 4.4 Other triggers

**Id 0, hat trick** (goal summary `loc_1889A` L55990, reached from SetPA L46552 when the referee message is `$E`, the goal):

```
rec = the latest ScoreSum record; team = rec away bit (2(a4) bit 7) ? AwShots : HmShots
if team.goals_in_game[rec.scorer] ($B4 + scorer) == 3          ; exactly the third
   and rec.scorer >= sub_9F40(team)                            ; not a goalie slot (see below)
   and team.teamindex ($28) == HomeTeam:                       ; home team only
    sub_FE510(0)
```

- `sub_9F40` counts the non-zero nibbles of the team data's `+$A` word. That is the goalie count: the goalie slots come first in the roster, and `$B4+pnum` holds goals against for a goalie. This reading is inferred.
- Quirk: when both teams are the same franchise, an away hat trick also passes the `HomeTeam` test.
- The "HAT TRICK" text is printed for both teams; the animation plays for the home team only.
- The animation is cut off at the next faceoff setup (L42209). How much of its 282 vblanks shows depends on the goal stoppage. **UNRESOLVED**: the typical time from SetPA `$E` to the puckfaceoff2 setup has not been measured.

**Id 7** (FallDown L49341-49352): the fall animation is `$18CC` (k = 6: |y| ≤ `$10C` and x < 0, i.e. checked into the left boards) and the checked player's Ypos is in -`$59`..`$59`. These are the benches. The player goes over the boards (SPA `$193E`/`$1A00`) while id 7 plays. It is cut off at the next faceoff setup.

**Id 4**: nothing starts it. The `$FE364` entry exists, and the drop-time minimum still lists 4. Ship the data and leave it unused.

**Resets**: StartGame (L29748) `st word_FFD6B4` stops any animation. StartPer (L29853) `st word_FFD6BE` drops any pending id.

### 4.5 Port

**Existing state:**
- `FaceoffLogic.overlay_request` is `word_FFD6BE`.
- `FaceoffLogic.overlay_shown` is `word_FFD6B4` at the drop test.
- The comment calls them a "stats overlay". They are this background animation.

**Port bug:**
- `faceoff_logic.gd:75` sets `overlay_request = -1` just before `assreplace(p, ASS_PUCKFACEOFF2)`.
- Retail L41800 writes `word_FFD6C6` there, not `word_FFD6BE`.
- As a result the port never has a pending id at `_setup`, `overlay_shown` is always -1, and the `$10E` drop minimum never applies.
- Fix: remove that line. It was left unchanged here because this task may not edit existing files.

**New logic:** add a small state object, e.g. `ArenaAnim` in HockeyWorld:

| Field | Retail word |
|---|---|
| `id` | B4 |
| `loaded` | BA != 0 |
| `index` | B0 |
| `counter` | B2 |
| `frame` | AE |
| `pending_ok` | `byte_FFC2FC` bit 0 |

Give it `start(id)`, `step(d7)`, `stop()` and the scripts from `bganim.json` `ids[].script` and `end`. Then hook it in:
- **Step:** `periodic_events` right after `rules.updatecrowdf(d7)`, which is retail's order. Also step it in the intermission loop (§5.4).
- **Faceoff:** `_first_call` sets `pending_ok`. In `_setup`, do `stop()`, then `start(overlay_request)` when `pending_ok` and the id is ≥ 0. Keep `overlay_shown = arena.id`. Call `stop()` where puckfaceoff2 counts out (line ~176).
- **Id 7:** connect `HockeyWorld.background_anim` (checking.gd:355 already emits 7) to `start`.
- **Hat trick:** in `GameRules.set_pa` when `id == PEN_GOAL`, test the last `w.score_summary` record against `stats[team].player_goals[scorer] == 3`, the scorer not being a goalie slot, and the home team. Then call `start(0)`. There is no hat-trick text in the port.
- **Start of game:** `start_game` → `stop()`. `start_per` → `overlay_request = -1`.

**Drawing:** the same view as the crowd. Draw while `id >= 0`, `loaded`, `frame > 0` and not `SF_HOR`. Use map-pixel coordinates and lines 0-3 from the game palette.

## 5. Intermission and zamboni (G8)

### 5.1 Flow (PeriodOver L53805 → Intermission L47613)

```
PeriodOver: gsp += 1, ...; forceblack; ResetClock; AllSndOff; song $79; UpdateScores
            (gsp == 4: AddPOStats); Intermission; gsp == 4 ? GameOver : StartPer
Intermission:
    if gsp == 4: gameclock = 0 ; sub_F9CDE            ; the end of the game uses it too
    sub_13056 (ResetBench, line resets)
    for the 16 sort objects: Xpos.hi = 0               ; in horizontal mode find3d gives dy = -$C5
                                                       ;   -> off screen: no players are drawn
    load ZamFrameList tiles (unk_A892A) to ExtraChars
    zamx = $140
    menu = unk_131CC[gsp + (OptPlayMode ? 5 : 0)]      ; word_FFC2FA b0 (shootout): unk_19A00
    sflags bit 0 = 1 ; sub_7E36(menu, sub_7DCE)        ; sub_7DCE: window over the whole screen
                                                       ;   ($9100/$921C), SetHor (side view,
                                                       ;   sflags b7), setvideo, KillCrowd, menu
                                                       ;   frame; palette fade-in ($18)
    TickerNum = GetShifter()
    while TickerNum >= 0:                              ; other series' scores (playoffs)
        NewTicker2 ; NewTicker3pt2 ; waitxsr($96) ; if chosen: break
        sub_134D8 (erase) ; waitxsr($3C) ; if chosen: break
    sub_1351C (highlights)
    repeat waitxsr($1E0) until chosen or (cont1team == 0 and cont2team == 0)
    zamx = $FFxx (st)                                  ; zamboni off
waitxsr(n) (L44352), per vblank until n vblanks or a menu choice:
    if zamx <= $708 (unsigned): zamx += 1              ; so zamx stops at $709
    updatecrowdf(1) ; sub_FE2C8(1)
    read pads 1-4; on input: sub_7E88 (menu) -> "chosen" sets d1 bit 7 and returns
    setvideo ; wait one vblank
```

- With a human playing, the intermission ends only when the player picks the menu's continue entry. With two CPU teams it ends after the `$1E0` (480) wait.
- `setupice` (L53044) and the end of the intermission set `zamx` negative, so `showzam` draws nothing at any other time.

### 5.2 showzam (L52076) and SetSframe (L52140)

```
showzam:
    if zamx < 0: return
    x = zamx >> 2 ; y = $12A                                   ; VDP coords
    SetSframe(1)                                               ; body
    SetSframe(2 + (x >> 1) % 3)                                ; wheels/chassis, frames 3-4 add snow spray
    if HmGoals <= AwGoals (unsigned): SetSframe(5) ; return    ; driver, hands on the wheel
    k = max(x - $DA, 0) >> 2
    SetSframe(unk_1615E[min(k, 12)])                           ; 5 6 7 8 7 8 7 8 7 8 7 6 5
SetSframe(f): if d6 >= $40: return ; link every piece of f (no cull):
    SAT = (x + p.x, y + p.y), attr = (w6 & $F800) + tile + ExtraChars ; stop at d6 == $40
```

All zamboni pieces use line 0, so they are the same on the side palette. Frames, from the renders:
- 1: the body, white with the EA logo.
- 2-4: the chassis and wheels, with a snow-spray piece in 3-4.
- 5: the driver with hands on the wheel.
- 6: one hand raised.
- 7: waving.
- 8: both hands up.

The pieces span x -51..+39 and y -24..+29 around the origin.

Timeline at 60 vblanks per second:

| zamx | vblanks from the start | Screen origin x | Event |
|---|---|---|---|
| `$140` | 0 | -48 | start, fully off-screen |
| `$168` | 40 | -38 | right edge enters |
| `$368` | 552 | 90 | wave starts (home leading only): frame changes every 16 vblanks; after 192 vblanks it stays on 5 |
| `$6CC` | 1420 | 307 | left edge leaves |
| `$709` | 1481 | 322 | stops, off-screen |

Other timing:
- The wheel frame changes every 8 vblanks.
- Origin y = 170 on the side view, so the zamboni rides on the ice in front of the boards. The side view's ice starts at about y 175.
- SAT x stays within 29..489, so the VDP's x = 0 sprite masking never triggers.

Previews: `zamboni_side.png` (10 zamx values on the side view, wave on), `zamboni_frames_1-8.png` (origin marked) and `zamboni_composed_driver5-8.png`.

### 5.3 Everything on the intermission screen

| Item | What is drawn |
|---|---|
| Plane B | the side view (SetHor: `icerinkmap`, the port's `rink/side_idx.png`), with side palette lines 0-1 and team lines 2-3 |
| Window plane | Covers the whole screen. It holds the menu box (Framer `$16`x6) and its text from `unk_131CC`. In playoff mode it also holds the ticker boxes (Framer `$1A`x5, NewTicker3pt2) and highlight prompts. In horizontal mode showclock prints the clock with `printz` unless shootout. **UNRESOLVED**: the menu and ticker contents, and whether their high-priority text tiles overlap the zamboni or the crowd; nothing in that layout was decoded. |
| Sprites, link order | 1. showzam (zamboni). 2. showcrowd in horizontal mode: away box `$39+…`, home box `$3C+…`, flash `$32-$38`, crowd `$20-$31`. |
| Not drawn | sort objects (Xpos cleared → off-screen); faceoff close-up (sflags b0); bganim (horizontal mode); referee window (sflags2 b1 is not set) |

The box nibbles are still those of the period that just ended. ResetBench (L51490), called by sub_13056 at the top of the intermission, recounts PBnum from the players still serving time.

### 5.4 Port

The current flow:
- `GameRules._period_break` emits `intermission(gsp)` and then runs `start_per()` at once. Retail runs Intermission before StartPer.
- `scenes/game.gd` `_on_intermission` sets `hold`, so HockeyGame stops stepping the world.
- `Rink2D._sync` shows the side view only while `SF_HOR` is set, and SF_HOR is not set during the port's intermission.

What to add:
- **State:** an intermission flag, e.g. on HockeyGame, set in `_on_intermission` (gsp ≥ 1) and in `_on_game_over`, and cleared in `_release`. While it is set:
  - `Rink2D` shows `side`;
  - the arena view draws the horizontal crowd and the box frames;
  - the zamboni is drawn.
- **Per vblank while held** (HockeyGame `_physics_process` hold branch, using `Nhl94Units.frames(delta)`), which is retail's `waitxsr`:
  - `if zamx <= 0x708: zamx += 1`, starting from `0x140` when the intermission begins;
  - `world.rules.updatecrowdf(1)`;
  - `world.arena.step(1)`.
- **Zamboni:**
  - the wave test uses `stats[0].goals > stats[1].goals` (the score at the intermission);
  - frames and the wave table come from `zamboni.json`;
  - position as in §0.3;
  - draw order: driver, then wheels, then body (the body is in front).
- **Menu:** the port's CPU-only hold of 480 frames matches retail. A human-only "Start" stands in for the retail menu.

## 6. Summary of what the port must add

**Status: all six items are ported** except the optional cull and budget (item 6). The faceoff bug (item 2) is fixed: `faceoff_logic.gd` no longer clears `overlay_request` before puckfaceoff2. The crowd flash draws from its own random stream (`GameRules.flash_rng`) so a purely visual read does not shift the gameplay draws from `hv_rng`, matching the VDP counter, whose reads do not disturb one another. Tests: `test_crowd_frames`, `test_arena_anim_scripts`, `test_arena_anim_hooks`, `test_intermission_zamboni`.

1. `game_rules.gd` updatecrowdf: store the `_cd0` frame, not the offset, and add `crowd_flash` (§2.5).
2. `faceoff_logic.gd:75`: remove `overlay_request = -1` (§4.5 bug).
3. A background-animation state machine with start, step and stop. Hook it to periodic events, the faceoff setup, the drop, `background_anim(7)`, the hat trick in `set_pa(PEN_GOAL)`, and the resets (§4.5).
4. An arena view under HockeyGame at `Z_LOGO + 1`, before GlovesView. It draws the crowd, flash, box, bganim and zamboni from the three atlases, with the game palette and no away swap (§0, §1).
5. Intermission: side view, zamx, crowd and bganim stepping per vblank while held, and the zamboni (§5.4).
6. Optional: the per-piece cull (§0.4) and the 64-link budget.

## 7. Verification renders

These renders were made from the exported files, not from the ROM, so they also check the export. The renderer is `/tmp/claude-0/-home-user/ef020377-92e3-57ff-8519-5d51b4a7df4d/scratchpad/arena/preview.py`. The files are in `/tmp/claude-0/-home-user/ef020377-92e3-57ff-8519-5d51b4a7df4d/scratchpad/arena/preview/`:
- `crowd_frames_1-18.png`, `crowd_frame14_outlined.png`, `crowd_flash_19-25.png`, `crowd_box_26-31.png`, `crowd_side_frames_32-49.png`, `crowd_side_flash_box_50-62.png`
- `bganim_id0.png` … `bganim_id7.png`, `bganim_EB816_dim.png`, `bganim_EC284_dim.png`, `bganim_locator.png`
- `zamboni_side.png`, `zamboni_frames_1-8.png`, `zamboni_composed_driver5-8.png`
- `screens_camera_culled.png`: four 256x224 camera views with the §0.4 cull and the near glass

## 8. Unresolved

1. How long the hat-trick animation is visible: it runs from SetPA `$E` until the next puckfaceoff2 setup kills it. The stoppage length was not measured.
2. The intermission window-plane layout: the `unk_131CC` menus, the playoff ticker and the highlights, and whether their text tiles have priority over the zamboni and crowd sprites.
3. `sub_9F40` read as the goalie count, for the hat trick's "not a goalie" test. This is inferred from the code shape, not confirmed by data.
4. The away penalty-box figures' leg piece uses line 2 (home colours). It is exported as retail draws it. Whether that was intended is unknown, and it does not matter for a faithful port.
5. The verbal descriptions of what each animation shows (§2.1, §4.1) come from reading the renders.
6. The sprite budget (64 links, 16 per line) is not emulated. Which crowd pieces retail drops in a given scene is not reproduced (§0.4).
7. `word_FFD6C6` (L41800) is write-only. Its purpose is unknown, but it does not affect these animations.
