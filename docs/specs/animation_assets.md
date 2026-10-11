# NHL '94 (Genesis): animation, sprite, rink, palette and sound assets

Source: `lst/nhl94.bin.lst` (IDA LST, no address column) and `lst/nhl94.bin` (CRC32 `$9438F5DD`). Line numbers are written `Lnnnnn`. ROM addresses are written `$xxxxx`. Every ROM address given for a data table below was checked by searching for its bytes in `nhl94.bin`, or by following the pointer that the code uses. Then the data was decoded and rendered to PNG in a scratch probe: player sprites, rink, center-ice logo and priority layer. The renders matched the game's look, so the formats below are confirmed. They are not inferred.

## 0. Overview

How the pieces fit together, per game loop (`DoGameFrame` L29914):

1. **Game logic picks an animation.** Code calls `SetSPA` (L43319) with an animation id ("SPA") in `d1` for object `a3`. `SetSPA` stores the id in `$58` and restarts the animation unless that id is already playing. Some callers also set `pf2aip` (`$63` bit 1, animation in progress) or `pfalock` (`$62` bit 5) to block other animation changes until the animation ends.
2. **`updateanim` (L35703) steps the animation.** `updateplayers` calls it once per loop for every object whose position word `$34` is non-negative (L35463, `_top3`, near the top of the per-object loop, after the old position is saved). It finds the SPA entry in `SPAList`, then the frame list for the object's facing direction (mirrored if the object is x-flipped). It counts the frame timer `$5C` down by `d7`, advances the frame index `$5A`, and handles the end of the list (loop, or clear the SPA). It writes the frame number to `$06`, limited by a "de-glitch" counter in `$65`.
3. **Frame becomes hardware sprites.** `setvideo` (L51875) → `setsortcords` (L52631) walks the objects in Y-sorted order (`SprSort` L53612) and calls `addframe` (L52792) on each. `addframe` projects the object position to the screen (`find3d` L52947), then `addframe2` (L52814) reads the frame's sprite pieces from `frameSprData` (`$9E724`). For each piece it queues a DMA of the piece's tiles from `Spritetiles` (`$5DE84`) into VRAM and writes one VDP sprite-table entry. The entry carries position, size (`sizetab`), flips, palette (with the away-team palette swap) and priority.
4. **Stick hot spot.** `GetHot` (L43282) returns the stick-blade offset for the object's current frame from `Hotlist` (`$A44C8`). It handles flips.
5. **Rink.** `setupice` (L53024) and `sub_9CDC` (L34247) load the rink tiles (`Rinktiles`, or `RevRinkTiles` for reverse-angle replays) into VRAM from tile 0. They overwrite the last 24 rink tiles with the home team's center-ice logo (`sub_FEA52` L974600). They copy rink palette lines 0-1 (`sub_16C96` L53189) and load team palette lines 2-3 (`SetTeamColors` L53781). Each loop, `checkwindow` (L35779) moves the camera (`Vpos`/`Hpos`) toward the puck or puck carrier. `updatescroll` (L51912) sets the plane-B scroll registers and DMAs any newly exposed rows of the 48x113 rink map into the 64x32 plane.
6. **Sound.** `sfx` (L44279) and `song` (L44297) take one word on the stack and call `p_initfx` (L61549). That is a 68000-side sequencer: ids 0..`$7A`, and ids ≥ `$30` stop the current music first. FM voices are written by the 68000 through the Z80. "Instruments" ≥ `$60` play 8-bit PCM samples on the YM2612 DAC through a small Z80 driver (`unk_1AD90`). Those samples can be exported to `.wav` offline (§5.4).

### Global variables and tables used

| Name | Where | What |
|---|---|---|
| `SPAList` | `$5B1C` (L22741) | Animation table: 66 entries, ids `$0002`..`$1AF4`, ends at `$76B2` |
| `off_5DE7A` (sprite "anim" file) | `$5DE7A` (L337807) | Header for the player/puck/net sprite set |
| `Spritetiles` | `$5DE84` (L337811) | 8257 (`$2041`) 4bpp 8x8 tiles, 32 bytes each, ends `$9E6A4` |
| (anim palette block) | `$9E6A4` | 128 bytes. No code reads it (see §2.1) |
| `frameSprData` | `$9E724` (L602163) | Frame offset table (847 words) followed by 8-byte sprite pieces |
| `Hotlist` | `$A44C8` (L626116) | 2 signed bytes (x, y) per frame, frames 0..837 |
| `sizetab` | `$16???` (L57705) | 16 bytes: tile count per VDP sprite size |
| `revframetbl` | `$F600E` (L957106) | 846 words: frame → reverse-angle frame |
| `TeamList` | `$30E` (absolute) | 28 longs: team data pointers (team index = `HomeTeam`/`VisTeam`) |
| `unk_FEA74` | `$FEA74` (L974614) | 28 longs: center-ice logo tile blobs, by home team index |
| `Rinktilelist` / `Rinktiles` | `$5605A` / `$56062` (L305515/305524) | Normal rink ".map.jim": 454 tiles + 4 palettes + 48x113 map |
| `RevRinkTilelist` / `RevRinkTiles` | `$B5180` / `$B5188` (L694916/694925) | Reverse-angle rink: 452 tiles + palettes + 48x113 map |
| `icerinkmap` | `$BC064` (L723306) | Tiles of the PauseScreen ".map.jim" (`$BC05C`): horizontal-mode side view |
| `palfadenew` | RAM `$FFBD28` | 4 palette lines x 16 colors. Target of `cramfade`. Line 2 at `$FFBD68`, line 3 at `$FFBD88` |
| `Vpos`, `Hpos` | RAM | Rink coordinates (Y up) of the screen center |
| `Vscroll`, `Hscroll`, `Oldrow`, `yc1`, `xc1`, `yleader` | RAM | Scroll state |
| `sflags` bit 6 / bit 7 | RAM | Scroll lock / horizontal (side-view) mode |
| `word_FFC2F4` bit 4 | RAM | Reverse-angle replay |
| `unk_2C648` | `$2C648` | 123 longs: sound id → sequence pointer |
| `unk_1B01C` | `$1B01C` (L63791) | 15 x 8 bytes: DAC sample table for instruments `$60`..`$6E` |
| `unk_1AD90` | `$1AD90` (L63139) | Z80 sample-player driver, `$295` bytes |

Struct fields (SCstruct, `a3`): `$04` attribute (bit 11 = byte-4 bit 3 = x-flip, bit 12 = y-flip, bits 13-14 palette, bit 15 priority, **bit 0 = away-team palette swap**), `$06` frame, `$08` oldframe (VRAM cache), `$0A..$0F` VRoffs (per-piece VRAM offsets), `$10` VRsize, `$12` VRchar (VRAM tile base), `$18` Zpos, `$52` SCnum, `$54` facedir (high word 0..7 used), `$58` SPA, `$5A` SPAnum (byte index into the frame list, steps of 4), `$5C` SPAcnt (frame timer), `$62`/`$63`/`$64` flags, `$65` glitch (byte).

---

## 1. Animations

### SetSPA (L43319)

- Purpose: start animation `d1` on object `a3`. Called from all over the game logic. Main callers: `doplayeracc` (glide `$50C`, glide back `$A60`, turns `$662`/`$694`), skate selection at `$10B76` (L43674-43693), `dostop` (stop `$6C6`), passing (`$718`/`$78A`), shooting (`SetShotMode` `$7FC`/`$92E`), checks, goalie code, injuries and falls.
- Inputs: `d1.w` = SPA id (byte offset into `SPAList`), `a3`.
- Outputs: `$58` SPA, `$5A` SPAnum, the high byte of `$5C`.

```
SetSPA:
  if d1 == $58(a3): return            ; same animation keeps running, no restart
  $5A(a3).w = 0                        ; SPAnum
  $58(a3).w = d1                       ; SPA
  $5C(a3).b = $FF                      ; "st $5C(a3)": only the HIGH byte -> word is negative
  return
```

- `SetSPA` never touches `pf2aip`/`pfalock`. Callers set them before the call when the animation must not be interrupted. Examples: `dostop` L43897 `bset #1,$63(a3)` then `SPAstop`. `doplayeracc` L43459 `bset #1,$63(a3)` then a turn animation. `doshot` sets `pfalock`.
- Quirk: `st` writes only byte `$5C`, so SPAcnt becomes `$FFxx`. Only the sign is tested, so any `$FFxx` behaves as "load the first frame now".
- A call with the id that is already running does not restart it, even after it has finished, unless `updateanim` has cleared `$58` to 0. A finished one-shot clears `$58` (see below), so calling `SetSPA` again with the same id then restarts it.

### updateanim (L35703)

- Purpose: step the current animation of `a3` and set its frame. Called from `updateplayers` (`_top3` L35463) once per loop for each of the 16 objects with `$34(a3) >= 0`.
- Inputs: `$58` SPA, `$5A` SPAnum, `$5C` SPAcnt, `$54` facedir (word = integer direction 0..7), `$04` attribute bit 11 (x-flip, tested as `btst #3,4(a3)`), `$52` SCnum, `sflags` bit 7, `d7` = vblanks since the last loop, `$65` glitch, `$06` frame.
- Outputs: `$06` frame, `$5A`, `$5C`, `$58` (cleared at the end of a one-shot), `$65`, `$62` bit 5 (`pfalock`), `$63` bit 1 (`pf2aip`), `$64` bit 5 (falling down).

```
updateanim:
  if SPA == 0:
      clear $62 bit5 (pfalock); clear $63 bit1 (pf2aip); return       ; frame is left as is
  a0  = $5B1C + SPA                       ; SPA entry
  d1  = word a0[$10]                      ; entry attribute; bit 0 = loop
  dir = facedir.w                         ; 0..7
  if (sflags bit7 /*horizontal mode*/) and SCnum < 12:                ; signed compare, players only
      dir = (dir - 2) & 7
  if attribute bit 11 (x-flip):
      dir = (8 - dir) & 7                  ; neg, +8, and #7: mirror the direction
  a0 += word a0[dir*2]                     ; frame list for this direction (offset relative to the entry)
  idx = SPAnum                             ; byte index, multiple of 4
  d2  = word a0[idx]                       ; frame to show THIS loop (read before any advance)
  if SPAcnt < 0:                           ; just started (SetSPA) -> load the first timer
      goto LOAD
  SPAcnt -= d7
  if SPAcnt >= 0: goto CFRAME              ; "bpl": 0 still counts as running
  SPAnum += 4; idx += 4
  if word a0[idx-2] >= 0: goto LOAD        ; time of the frame that just finished; >= 0 means not last
  ; end of list
  idx = 0; SPAnum = 0
  clear $62 bit5 (pfalock); clear $63 bit1 (pf2aip); clear $64 bit5 (falling down)
  if (d1 & 1) == 0: SPA = 0               ; one-shot: animation cleared
  ; loop animations restart at index 0
LOAD:
  t = word a0[idx+2]; if t < 0: t = -t
  SPAcnt = t
CFRAME:
  glitch.b -= d7                            ; byte arithmetic
  if glitch.b >= 0: return                  ; "bpl": 0 still blocks
  glitch.b = 0
  if frame == d2: return
  frame = d2
  glitch.b = 4
```

Behaviour that must be kept exactly:

- **One-loop lag.** `d2` is read from the index *before* the advance. On the loop where a frame's timer runs out, the old frame is still written. The new frame appears on the next loop. At the end of a one-shot, the last frame stays in `$06` after `SPA` is cleared (a later `SetSPA` replaces it).
- **Frame duration** with `d7 = 1`: the first frame (index 0) is shown for `|T0| + 2` loops, counting the `SetSPA` loop. Every later frame k is shown for `|Tk| + 1` loops. In general a frame advances on the first loop where the running sum of `d7` exceeds `T`.
- **Time sign.** A negative time marks the **last** frame of the list. Its absolute value is the duration. The loop/one-shot choice is bit 0 of the entry's attribute word, not the sign.
- **pf2aip/pfalock/falling** are cleared when any list reaches its end, **including looping animations** (after one pass), and whenever `SPA == 0`.
- **De-glitch.** After a frame change, `glitch = 4`. With `d7 = 1` the next change is allowed 5 loops later (4,3,2,1,0 block, -1 allows). With `d7 = 2` it is allowed 3 loops later. Timers keep running while a change is blocked, so short frames can be skipped visually.
- At the end of a one-shot, `LOAD` still runs with `idx = 0` and writes `|T0|` into SPAcnt. This is harmless, because `SetSPA` makes SPAcnt negative again.
- External code also edits `SPAnum`. `ShotMode` (L37444) checks `$5A >= $1C` to release the shot, checks `$5A >= $10`/`> 8` to stop the wind-up, and does `SPAnum = $1C - SPAnum` (L37464-37465, `neg` then `addi #$1C`) to jump from the wind-up to the mirrored swing frame. `updateplayers` (L35389-35400) pins positions while one of the "fall over boards" animations (`$1776 $17E8 $185A $18CC $193E $1A00`) is running and `$64` bit 5 is set.

### SPAList (L22741, ROM `$5B1C`..`$76B2`)

Format (all words big-endian):

```
SPAList+0      : $0000  (unused; SPA id 0 means "no animation")
entry at SPAList+id  (id is even, >= 2):
  +$00..+$0E   : 8 words, dir 0..7: byte offset of that direction's frame list, relative to the ENTRY start
  +$10         : attribute word; bit 0 = loop (1) / one-shot (0). All 66 entries use only 0 or 1.
  +$12...      : frame lists, each = repeated { word frame, word time }, the last pair has time < 0
```

- Direction selection is described above: `facedir` 0..7 (0 = +Y up the ice, clockwise), mirrored when the object is x-flipped.
- Frame words in `SPAList` never use the flag bits `$F800`. All values are 1..837 (`$345`). The sprite flag bits that `addframe2` accepts in `$06` are therefore not used by the animation table.
- Every direction has its own frames. The table never mirrors with flip bits. Mirroring comes only from the object's attribute bit 11, which is set for one handedness (see "x-flip" below).
- Times are in vblanks (1/60 s), counted with `d7`.
- Two entries have a direction offset that points past their own data. `$F6E` and `$FAC` have dir 7 = `$3E`, which lands on the next entry's header. Running dir 7 would read header words as `{frame,time}` pairs: frame `$12` / time `$1E`, frame `$1E` / time `$2E`, and so on. Port as-is (these are goalie-only animations and probably never run with facing 7), or treat as UNRESOLVED.
- Entry `$46A` (`SPApflip`, the puck flipping in the air) has times of -4096 for dirs 4-7.

#### Entries requested in full

`abs` = ROM address of the entry. `frame/time` pairs, times in decimal.

**`$5D0` SPAskate** (abs `$60EC`, attr 0 = one-shot; restarted every loop by the skate code). Comment "SPAskate" at L24179:

| dir | list |
|---|---|
| 0 | `$2A/10 $2B/10 $2C/10 $2D/-10` |
| 1 | `$2F/10 $30/10 $31/10 $32/-10` |
| 2 | `$34/10 $35/10 $36/10 $37/-10` |
| 3 | `$39/10 $3A/10 $3B/10 $3C/-10` |
| 4 | `$3E/10 $3F/10 $40/10 $41/-10` |
| 5 | `$43/10 $44/10 $45/10 $46/-10` |
| 6 | `$48/10 $49/10 $4A/10 $4B/-10` |
| 7 | `$4D/10 $4E/10 $4F/10 $50/-10` |

**`$50C` SPAglide** (abs `$6028`, attr 0): one frame per dir, time -8. Dir 0..7 frames = `$01 $06 $0B $10 $15 $1A $1F $24`.

**`$694` SPAturnr** (abs `$61B0`, attr 0): dir 0..7 frames `$59 $5A $5B $5C $5D $5E $5F $60`, each time -8.

**`$662` SPAturnl** (abs `$617E`, attr 0): dir 0..7 frames `$51 $52 $53 $54 $55 $56 $57 $58`, each time -8. (`$662 = $694 XOR $FFCE`: `doplayeracc` L43452-43458 builds the id as `($FFCE if left) XOR ($FFCE if x-flipped) + $694`.)

**`$6C6` SPAstop** (abs `$61E2`, attr **1 = loop**): dir d = `{$91+2d}/4, {$92+2d}/-4`. Dir 0 `$91/4 $92/-4`, dir 1 `$93/4 $94/-4`, … dir 7 `$9F/4 $A0/-4`.

**`$A60` SPAglideback** (abs `$657C`, attr 0): dir 0..7 frames `$A1 $A4 $A7 $AA $AD $B0 $B3 $B6`, each time -8.

**`$A92` skate backwards** (abs `$65AE`, attr 0; chosen at L43674 when `pfrev`):

| dir | list |
|---|---|
| 0 | `$A1/10 $A2/10 $A1/10 $A3/-10` |
| 1 | `$A4/10 $A5/10 $A4/10 $A6/-10` |
| 2 | `$A7/10 $A8/10 $A7/10 $A9/-10` |
| 3 | `$AA/10 $AB/10 $AA/10 $AC/-10` |
| 4 | `$AD/10 $AE/10 $AD/10 $AF/-10` |
| 5 | `$B0/10 $B1/10 $B0/10 $B2/-10` |
| 6 | `$B3/10 $B4/10 $B3/10 $B5/-10` |
| 7 | `$B6/10 $B7/10 $B6/10 $B8/-10` |

**`$53E` skate with puck** (abs `$605A`, attr 0; chosen when the object is the puck carrier, L43688-43693):

| dir | list |
|---|---|
| 0 | `$02/10 $03/10 $04/10 $05/-10` |
| 1 | `$07/10 $08/10 $09/10 $0A/-10` |
| 2 | `$0C/10 $0D/10 $0E/10 $0F/-10` |
| 3 | `$11/10 $12/10 $13/10 $14/-10` |
| 4 | `$16/10 $17/10 $18/10 $19/-10` |
| 5 | `$1B/10 $1C/10 $1D/10 $1E/-10` |
| 6 | `$20/10 $21/10 $22/10 $23/-10` |
| 7 | `$25/10 $26/10 $27/10 $28/-10` |

**`$11E6` skate while `$63` bit 6 is set** (injured in a fight; abs `$6D02`, attr 0; L43686-43690. The puck-carrier choice `$53E` overrides it):

| dir | list |
|---|---|
| 0 | `$261/6 $262/6 $263/8 $262/6 $261/-6` |
| 1 | `$264/6 $265/6 $266/8 $265/6 $264/-6` |
| 2 | `$267/6 $268/6 $269/8 $268/6 $267/-6` |
| 3 | `$26A/6 $26B/6 $26C/8 $26B/6 $26A/-6` |
| 4 | `$26D/6 $26E/6 $26F/8 $26E/6 $26D/-6` |
| 5 | `$270/6 $271/6 $272/8 $271/6 $270/-6` |
| 6 | `$273/6 $274/6 $275/8 $274/6 $273/-6` |
| 7 | `$276/6 $277/6 $278/8 $277/6 $276/-6` |

Skate selection (L43674-43695, for reference): `d1 = $A92` if `pfrev`. Otherwise `$5D0`, then `$11E6` if `$63` bit 6, then `$53E` if puck carrier. `SetSPA(d1)` only if `pf2aip` is clear. The full table of all 66 entries is in **Appendix A**.

#### SPA ids with names in the listing

`$2` SPAgready (goalie ready, loop; L39169) · `$1AA` reach-out glove save · `$250`/`$2A2` goalie pad stack right/left · `$2F4` goalie dive · `$366` SPAgswing · `$46A` SPApflip (puck flip, loop) · `$50C` SPAglide · `$53E` skate with puck · `$5D0` SPAskate · `$662` SPAturnl · `$694` SPAturnr · `$6C6` SPAstop (loop) · `$718` SPApassf · `$78A` SPApassb · `$7FC` SPAshotf · `$92E` SPAshotb · `$A60` SPAglideback · `$A92` skate backwards · `$B96` SPAshoulderchkl · `$BC8` SPAshoulderchkr · `$BFA` SPAhipchkl · `$C2C` SPAhipchkr · `$C5E` SPAburst · `$C90` hold check, stick in air · `$CC2` SPAHold2 · `$CF4` SPAFlail · `$DD8` (player who is checked, L49447) · `$FEA` SPAfaceoff · `$1122` normal hold check · `$11E6` injured skate · `$145C`/`$1AF4` injury · `$1776 $17E8 $185A $18CC $193E $1A00` fall over boards/glass (left/right of center variants, L49344-49386). The other ids have no name in the listing (the callers are listed in Appendix A notes).

#### x-flip (attribute bit 11) and handedness

- `setplayer` (L51556, L51693-51699) clears attribute bit 11, then **sets it when the roster byte 4 bit 0 (Hnd) is 1**. The listing comment there calls the result "R" ("L will be a 1 and R will be a 0" in the struct copy at `$76`). So the art is drawn for one hand, and the other hand is drawn mirrored. The direction mirror in `updateanim` keeps the facing correct: an x-flipped object facing dir 2 uses the dir-6 frames, and the hardware flips them.
- `doplayeracc` swaps turn-left/right when x-flipped (L43456). The code at `$10B48` turns facedir by +1, or by -1 when x-flipped. `GetHot` negates the hot-spot X when x-flipped.
- `SetRCords` (replay, L35038) sets bits 11-12 from replay data. In a reverse-angle replay it also toggles bit 11 for frames `$162..$178` ("old fight frames", L35116-35122).

#### revframetbl (L957106, ROM `$F600E`)

- Purpose: used by `SetRCords` (replay playback) when `word_FFC2F4` bit 4 (reverse angle) is set. Maps each frame number to the frame that shows the same pose seen from the other end of the rink. Example: frame 1 (glide dir 0) → `$15` (glide dir 4).
- Format: 846 words indexed by frame (`move.w (a6,d2.w),d2` with `d2 = frame*2`, frame masked `& $3FF`). Entry 0 = `$018F` (unused). An entry of 0 (72 frames) or outside `1..$34D` means "keep the original frame" (L35130-35136: `cmp #1` / `cmp #$34E`, then fall back to the recorded frame). The table is not a perfect involution (17 frames map to a frame that does not map back).
- Puck shadow: in reverse angle, if the object is SCnum 15 and the mapped frame ≠ `$18A`, its Ypos is set to `$FC00`. Glass-shatter frames `$28D..$291` in reverse angle get Ypos `$190`.
- The port should export it as JSON (§6). The replay feature is out of scope here.

---

## 2. Sprites

### 2.1 Sprite "anim" file (header `off_5DE7A`, L337807, ROM `$5DE7A`)

```
$5DE7A  long  $0004082A   offset (from $5DE7A) to a 128-byte palette block  -> $9E6A4
$5DE7E  long  $000408AA   offset (from $5DE7A) to frame data               -> $9E724 = frameSprData
$5DE82  word  $2041       number of tiles (8257)
$5DE84  tiles             Spritetiles: $2041 * 32 bytes = $40820 -> ends at $9E6A4
$9E6A4  128 bytes         4 x 16 colours. No game code reads it. Only addframe2 reads this header, and it
                          uses offset +4 only. The contents look like a placeholder ramp
                          ($0CEE $08EE ...). Do NOT use it.
$9E724  frameSprData      offset table + sprite pieces
$A44C8  Hotlist           (2 bytes before the end of the last frame's pieces; see 2.5)
$A4B54  end               (CrowdFrameList, the crowd anim file, starts here)
```

Tile format (all tile sets in this ROM): 8x8 pixels, 4 bits per pixel, 32 bytes per tile. 4 bytes per row, top row first. In each byte the **high nibble is the left pixel**. Pixel value 0 is transparent for sprites. For plane tiles, value 0 shows the backdrop colour.

### 2.2 frameSprData (L602163, ROM `$9E724`)

```
FS = $9E724
word w[i] = FS + 2*i, i = 0..846 ; w[0] = 0, w[1] = $069E (= table size in bytes), w[846] = $5DA6 (end sentinel)
frame f (1..845):  pieces at FS + w[f] .. FS + w[f+1], 8 bytes each, count = (w[f+1]-w[f]) / 8 (1..8 pieces)
piece:  +0 s16 x   offset of the piece's top-left pixel from the frame origin, screen pixels, +x right
        +2 s16 y   same, +y DOWN (screen)
        +4 u16 tile  first tile index into Spritetiles (0..$2040)
        +6 u16       bits 15..11 = VDP flags of the piece: 15 priority (never set in data), 14..13 palette line,
                     12 v-flip, 11 h-flip; bits 10..8 = 0; bits 7..0 = VDP size byte (index into sizetab, < 16)
```

- Piece size: width `w = ((size >> 2) & 3) + 1` tiles, height `h = (size & 3) + 1` tiles. The tiles of one piece are `tile, tile+1, …`, stored **column-major** (VDP order): tile `tile + col*h + row`. Confirmed by rendering.
- Palette line use in the data: line 2 (team) in 2623 pieces, line 0 in 128, line 1 in 40. Line 0/1 pieces use the rink palette colours (puck, nets, joypad stars/arrows, parts of some frames).
- Totals: 845 frames, 2785 pieces, at most 8 pieces per frame. All 8257 tiles are used. The largest frame bounding box is 70x72 px. The extent of all frames relative to the origin is x -47..44, y -64..39.
- Named frames: `$161` SPFgloves · `$186`/`$187`/`$188`/`$189` joypad 1 star / joypad 2 star / puck-possession star / replay cursor · `$34C`/`$34D` joypad 3/4 star · `$18A` (puck; the comment at L42099 says `#SPFpuck`) · `$18B`..`$194` puck in flight (used by `$46A`) · `$195`/`$196` goal nets top/bottom (`defaultsprites2` L53446) · `$197` SPFgoalie (first goalie frame, L50856) · frames 838..845 are off-screen pointer arrows/stars (no hot spot).

### 2.3 Spritetiles (L337811, ROM `$5DE84`)

8257 tiles in the format of §2.1. They are DMA'd straight from ROM to VRAM (`addframe2` L52867: `source = tile*32 + Spritetiles`, `length = tilecount*16` words). They are not compressed.

### 2.4 sizetab (L57705)

16 bytes, indexed by the VDP size byte (`(w-1)*4 + (h-1)`), giving the tile count `w*h`:
`1 2 3 4 2 4 6 8 3 6 9 12 4 8 12 16` (the listing comments label them 1x1, 1x2, … 4x4 as WxH).

### 2.5 Hotlist (L626116, ROM `$A44C8`) and GetHot (L43282)

- Format: 2 signed bytes per frame, indexed by frame number (`Hotlist + 2*frame`): `+0 = hot X`, `+1 = hot Y`, both in **screen pixels relative to the frame origin (+y down)**. A render puts the point on the stick blade, for example frames 6..16. The table covers frames 0..837 (`$A44C8`..`$A4B54`). Every SPA frame (max 837) has an entry. Frames 838..845 would read into the next file, but no code calls `GetHot` for them. Entry 0 (`$08,$05`) overlaps the last 2 bytes of frame 845's last piece and is never used (`GetHot` exits for frame ≤ 0).
- `GetHot` calling convention: the caller pushes the struct address (`move.l a0,-(sp)`) and calls. `GetHot` reads it at `$C(sp)` and removes it on return (`move.l (sp)+,(sp)`). Output `d0`/`d1` = hot offset in **rink units, Y up**. The caller adds it to Xpos/Ypos (for example `passto` L37127-37130).

```
GetHot(obj):
  d0 = d1 = 0
  if obj.frame (word, signed) <= 0: return       ; note: uses the full word, no & $7FF
  d1 = sext(Hotlist[frame*2+1]); d0 = sext(Hotlist[frame*2])
  if obj.attribute bit 11 (x-flip): d0 = -d0
  if obj.attribute bit 12 (y-flip) is CLEAR: d1 = -d1      ; listing comment says the opposite; the code negates when NOT flipped
  if sflags bit 7 (horizontal mode): swap d0,d1; d1 = -d1
  return d0, d1
```

- Quirk: flipping does not account for the piece-width correction used when drawing (§2.6). The hot spot mirrors about the origin, which is correct for a pixel point.

### 2.6 addframe (L52792), find3d (L52947), addframe2 (L52814)

- Purpose: draw one object (`a3`) as hardware sprites. `addframe` is called for the 16 sort objects (`setsortcords` L52631) and for the 7 "ffo" pad/star objects (`setffo`). `addframe2` is also called directly at setup (L53132-53142) with `d0`/`d1` = 0.
- Inputs: `a3` struct (`$00` X, `$14` Y, `$18` Z, `$04` attribute, `$06` frame, `$08` oldframe, `$12` VRchar), `Vpos`/`Hpos`, `sflags` bit 7, `a5` DMA list, `a6` sprite table pointer, `d6` link counter.
- Outputs: sprite-table entries at `a6` (8 bytes each), DMA list entries at `a5`, `$08` oldframe, VRoffs bytes `$0A+n`. `d6`/`a6`/`a5` are advanced.

```
addframe(a3):
  if Zpos.hi < 0: return                     ; "bmi" on the high word: hidden object
  (sx, sy) = find3d(Xpos.hi, Ypos.hi, Zpos.hi)
  if sy == $4E20 (osflag): return
  addframe2(a3, sx, sy)

find3d(x, y, z):                             ; returns VDP sprite coordinates (128 offset included)
  if sflags bit7 (horizontal): (dx, dy) = (-y, x - $C5)          ; exg d0,d1 ; neg d0 ; subi #$C5,d1
  else: dx = x - Hpos ; dy = y - Vpos
  if dx > $90 or dx < -$90 : off                 ; signed, 144
  sx = dx + $100
  dy = dy + z + (z asr 1)                         ; height raises the sprite by 1.5 z
  if dy > $90 or dy < -$90 : off
  sy = $F0 - dy
  return (sx, sy)                                 ; off -> sy = $4E20
```

So on the 256x224 screen, `screen_x = 128 + (x - Hpos) + piece.x` and `screen_y = 112 - (y - Vpos) - (z + z>>1) + piece.y`.

```
addframe2(a3, d0=sx, d1=sy):
  push attribute
  f = frame.w ; if f <= 0: exit (restore attribute)
  attribute ^= (f & $F800)                        ; frame flag bits act like attribute flips/palette/priority for this draw
  f &= $7FF
  a2 = frameSprData                              ; via header: $5DE7A + long[$5DE7E]
  if f*2 >= w[1] ($69E): exit                    ; signed compare; frame 846 passes this test but its data is garbage (quirk)
  n = (w[f+1]-w[f])/8 ; a2 += w[f]
  for each piece p (n pieces, loop counter d5 = n-1 .. 0):
     ; VRAM upload (only when frame != oldframe): DMA p.tile*32+Spritetiles, sizetab[p.size]*16 words,
     ;   to VRAM tile VRchar + (running tile count). Consecutive pieces whose tile ranges overlap the
     ;   previous piece's range reuse its VRAM ("_dup"). oldframe = frame when the last piece is done.
     ;   The port does not need this; it only manages VRAM.
     y = p.y
     if attribute bit12 (y-flip): y = -((p.size & 3) + 1)*8 - p.y
     SAT.y = sy + y
     x = p.x
     if attribute bit11 (x-flip): x = -(((p.size & $C) + 4) * 2) - p.x          ; = -8*w - p.x
     SAT.x = sx + x
     SAT.size = p.size ; SAT.link = d6
     flags = (p.word6 ^ attribute) & $F800        ; piece flips XOR object flips; palette/priority XOR too
     if (attribute bit 0) and (flags bit 14): flags |= bit 13       ; away team: palette 2 -> 3
     SAT.attr = flags | (VRchar + VRoffs[piece])
     d6++, a6 += 8, a2 += 8
  exit: restore attribute (the frame-flag XOR is temporary)
```

The port's equivalent: draw the frame image with its origin at the projected point. Mirror the whole frame about origin x = 0 when attribute bit 11 is set (a pixel column `px` maps to `-px-1`). Mirror about y = 0 when bit 12 is set. Use team palette line 3 instead of line 2 for away objects (attribute bit 0 = 1). `defaultsprites2` sets attribute 1 for the 6 visitor skaters and 0 for home, nets and puck (L53446).

**Draw order:** `SprSort` (L53612) bubble-sorts the 16 objects by `Ypos` ascending (by Xpos in horizontal mode; equal keys keep their order). `setsortcords` adds them in that order. The first sprite in the VDP link list is drawn on top, so **smaller rink Y (lower on screen) is in front**. Face-off sprites (`checkfo`) and `sso` objects are added before the players (in front). Pads/stars (`setffo`), clock, zamboni, crowd and ref come after (behind).

**Priority vs. rink:** no sprite piece has the priority bit. Objects get it only through their attribute: `$8000` is set at L42884 and L50124 (`wallcollb2`), and `$8000` on the replay-cursor pad. Plane-B rink cells with the priority bit (§3.3) therefore cover every normal sprite.

### 2.7 sublist (L57723) and priolist (L57829): not sprite tables

They belong to the line-change code (`SetPlList` L51300-51370, `getlinee`, `sub_129D2`), not to graphics. Dumped here because the task asked:
- `priolist` = bytes `0 1 2 4 3 5 6 $FF`: "positions in order of importance". `SetPlList` starts at `priolist+1` when the team has no goalie.
- `sublist` = 7 words `$000E $000E $001C $002A $0054 $003F $0054`: byte offsets (from `sublist`) of `$FF`-free substitution lists, indexed by position*2. The byte lists from `sublist+$0E`: `01 09 11 19 21 29 31 | 02 0A 12 1A 22 2A 32 | 02 0A 12 1A 22 2A 32 | 01 09 11 19 21 29 31 | 03 0B 13 1B 23 2B 33 | 05 0D 15 1D 25 2D 35 | 04 0C 14 1C 24 2C 34 | 05 0D 15 1D 25 2D 35 | 03 0B 13 1B 23 2B 33 | 04 0C 14 1C 24 2C 34 | 04 0C 14 1C 24 2C 34 | 03 0B 13 1B 23 2B 33 | 05 0D 15 1D 25 2D 35 $FF`. These are indexes into the 8-byte-per-line list at team `$16A`. `SetPlList` reads until a negative byte (only one `$FF`, at the very end).

### 2.8 Palettes: SetTeamColors (L53781) and the CRAM layout

```
SetTeamColors:
  sub_1721C(a0 = HmShots, d1 = 0)                ; home team -> palette line 2
  sub_1721C(a0 = HmShots + $364 (AwShots), d1 = $20)   ; falls through: away team -> palette line 3
sub_1721C(a0, d1):
  a2 = long $1E(a0)                               ; team data pointer (TeamList[team], set by sub_171BE L53748)
  a2 += word 2(a2)                                ; Palettedata offset
  a2 += d1                                        ; home uses the team's FIRST 16 colours ("h"), away its SECOND ("v")
  copy 8 longs (16 colours) to palfadenew + $40 + d1   ; $FFBD68 (line 2) or $FFBD88 (line 3)
```

- Callers: `sub_9CDC` (end, L34319), `setupice` (L53113), `sub_16BAC`, the playoff screen.
- CRAM in game (targets in `palfadenew` `$FFBD28`; `cramfade` L44101 fades CRAM toward them):
  - line 0 = rink palette 0, line 1 = rink palette 1 (`sub_16C96` copies the first **16 longs = 2 lines** of the rink file's palette block). The rink file has 4 lines, but lines 2-3 of it are never loaded.
  - line 2 = home team "home" palette. Line 3 = away team "visitor" palette.
- Team data: `TeamList` at ROM `$30E`, 28 longs. Team index: 0 Anaheim, 1 Boston, 2 Buffalo, 3 Calgary, 4 Chicago, 5 Dallas, 6 Detroit, 7 Edmonton, 8 Florida, 9 Hartford, 10 Los Angeles, 11 Montreal, 12 New Jersey, 13 NY Islanders, 14 NY Rangers, 15 Ottawa, 16 Philadelphia, 17 Pittsburgh, 18 Quebec, 19 San Jose, 20 St. Louis, 21 Tampa Bay, 22 Toronto, 23 Vancouver, 24 Washington, 25 Winnipeg, 26 All Stars East, 27 All Stars West. Each team block starts with word offsets: `+0 Playerdata, +2 Palettedata, +4 Teamname, +6 ScoutReport, +8 LineSets, +10 ScoreOdds` (`src/teamdata94.asm`). At `+Palettedata` there are 64 bytes: home palette (16 words), then visitor palette (16 words). All 28 are dumped in **Appendix B**.
- Rink palettes (file `$5605A`, block at `$59924`):
  - line 0: `0EE8 0EEE 0EEC 0CCC 0000 0AAA 0666 0444 0AAC 088E 064C 0C86 02AC 0EA8 0222 0EC8`
  - line 1: `0EE8 0CCC 0888 0444 0222 008C 006A 0000 0822 0600 0042 0020 004A 0006 066A 0246`
  - (lines 2, 3 in the file are green ramps, unused): `0EE8 0080 0480 …`, `0EE8 00C0 04C0 …`
  - The reverse rink file (`$B8A0A`) has the same 4 lines.
- Colour word: `----BBB-GGG-RRR-` (bits 9-11 blue, 5-7 green, 1-3 red, 3 bits each). Convert with `c8 = v3 * 255 / 7` (v3 = 0..7), or with a measured Mega Drive DAC curve if wanted. Colour index 0 of every line is transparent for sprites.
- Other palette writers that matter: `cramfade` fades in and out. The playoff screen flashes `$FFBD6A` (`sub_175D8`, not in game).

---

## 3. Rink

### 3.1 ".map.jim" layout (Rinktilelist L305515 `$5605A`, Rinktiles L305524 `$56062`)

```
+0  long  offset to palette block (from file start)   $38CA -> $59924 (4 lines x 16 colours = 128 bytes)
+4  long  offset to map (from file start)             $394A -> $599A4
+8  word  tile count; bit 15 set = compressed (see 3.6); $01C6 = 454 raw tiles
+10 tiles (32 bytes each)                             ends exactly at the palette block
map: word W (= 48), word H (= 113), then W*H words row-major, top row first
```

`Rinktiles` is the `+8` word, which is what the tile loader (`sub_11738`/`sub_1173C` L44942) receives. The loader puts raw tiles in VRAM starting at tile `d4`, here `rinkvrcset = 0`, and advances `d4` by the count.

Map cell word = VDP name-table entry: bits 0-10 tile index (+ `rinkvrcset` = 0), bit 11 h-flip, bit 12 v-flip, bits 13-14 palette line, bit 15 priority (drawn over low-priority sprites). Counts in the normal rink: 3662 plain, 539 h-flip, 161 v-flip, 213 both, 571 line-1 cells, 50 line-2 cells, 26 line-3 cells, 201 priority cells.

### 3.2 Rink geometry and the rink↔map pixel mapping

Map = 48x113 cells = **384x904 px**. Derived from `updatescroll` and `find3d`, and checked against the drawn lines:

```
map_px_x = rink_x + 192          ; rink x = 0 at the centre column; sidelines +-136 -> px 56 / 328
map_px_y = 368 - rink_y          ; rink y = 0 (red line) at px 368; goal lines +-264 -> px 104 / 632;
                                 ; end boards +-298 -> px 70 / 666
```

- Rows 0..84 (px 0..679) are the only rows the camera can show (`Vpos` ∈ [-200, 256] → visible px rows `256 - Vpos .. 479 - Vpos`). Rows 85..112 hold replay-panel pieces and leftovers. Crop them out, or keep them and never show them.
- Visible columns: `Hpos` ∈ [-60, 60] → map px x `Hpos + 64 .. Hpos + 319` (4..379).
- Visible rink rectangle for a camera at (`Hpos`, `Vpos`): x ∈ [Hpos-128, Hpos+127], y ∈ [Vpos-111, Vpos+112].
- Team-palette cells (normal rink):
  - Line 2 (home colours), 50 cells: the center-ice logo (rows 44-47, cols 21-26, tiles 430..453 in row-major order), the home bench (rows 47-58, cols 4-5) and the right penalty box (rows 49-51, col 43).
  - Line 3 (away colours), 26 cells: the away bench (rows 30-41, cols 4-5) and the right penalty box (rows 38-40, col 43).
- Priority cells: the near (bottom) end boards and glass (map rows 78-84) and four bench/penalty-door cells (rows 52-53, 59-60). Sprites go behind them.

### 3.3 Center-ice logo (`sub_FEA52` L974600)

```
sub_FEA52 (called right after the rink tiles are loaded, d4 = rinkvrcset + tilecount):
  d4 -= $18                                  ; overwrite the LAST 24 rink tiles
  a2 = long unk_FEA74[HomeTeam] + 8          ; skip an 8-byte jim header (both longs are 0)
  load tiles (word $0018 = 24 raw tiles, then 24*32 bytes)
```

- `unk_FEA74` (ROM `$FEA74`), 28 pointers: `$EDE8A $F2A84 $EE194 $EE49E $EE7A8 $EEAB2 $EEDBC $EF0C6 $EF3D0 $EF6DA $EF9E4 $EFCEE $EFFF8 $F0302 $F060C $F0916 $F0C20 $F0F2A $F1234 $F153E $F1848 $F1B52 $F1E5C $F2166 $F2470 $F277A $F2D8E $F2D8E` (both All-Star teams share one).
- Normal rink: the logo tiles become tiles 430..453. They sit at rows 44-47 × cols 21-26 in row-major order with palette line 2: a 48x32 px image whose top-left is map px (168, 352), i.e. rink x -24..23, y 16..-15.
- Reverse rink (452 tiles): tiles 428..451 at the same cells, in reverse order (451 at top-left). Use the cell words, which carry the flip bits.
- The logo is always drawn in the **home** team's palette.

### 3.4 RevRinkTiles (L694925, file `RevRinkTilelist` `$B5180`)

Same layout: palette offset `$388A` → `$B8A0A`, map offset `$390A` → `$B8A8A`, `$01C4` = 452 raw tiles, map 48x113. It is used instead of the normal rink when `word_FFC2F4` bit 4 (reverse-angle replay) is set, in `setupice`, `sub_9CDC`, `sub_A448` and `updatescroll`.

### 3.5 icerinkmap (L723306, ROM `$BC064`)

This is the tile blob (`$00D4` = 212 raw tiles) of the PauseScreen ".map.jim" at `$BC05C` (palette offset `$1A8A`, map offset `$1B0A`, map 32x28). `SetHor` (L47101) loads these tiles over the rink tiles (from `rinkvrcset`) and draws the 32x28 map with `dobitmap`. The result is the **horizontal mode** (`sflags` bit 7): the scoreboard/penalty screen with a side view of the ice (render checked). `ClrHor` (L47073) reloads the rink. The IDA decode of `SetHor` between `printz` and `movea.l #icerinkmap` is inline print data plus a hidden `adda.l 4(a1),a1`. The listing is garbled there, but the data is consistent.

### 3.6 Compressed tile blobs

The tile loader treats a count word with bit 15 set as compressed: tile count = `& $7FFF`, unpacked by `sub_1177A` (L44975). That is an LZ-style byte-code with a 256-byte ring, and the command is the high nibble of each byte. Known handlers: `$0x/$1x` literal run of `(c&$1F)+1` bytes; `$2x` `(c&$F)+1` zero bytes; `$3x` `(c&$F)+3` copies of the next byte; `$4x-$7x` copy `(c&7)+2` bytes from distance `((c>>3)&7)+1`; `$8x` copy `(c&$F)+3` bytes, distance = next byte; `$9x` count `((c<<1 | n>>7)&$1F)+3`, distance `(n&$7F)+1`; `$Ax` count `(((c<<8|n)>>6)&$3F)+3`, distance `(n&$3F)+1`; `$Bx` (handler at `$1189E`, mis-decoded as data in the listing) count `(((c<<8|n)>>5)&$7F)+3`, distance `(n&$1F)+1`. `$Cx-$Fx` (`$118B8`, `$118EA`, `$1190A`) and the ring flush `sub_11924` were not read.

**None of the assets in this spec's scope are compressed.** Rink, reverse rink, sprite tiles, logos, crowd anim (`$A4B54`, `$76` raw tiles) and pause screen are all raw. Compressed blobs are: `$5C408` (`ExtraChars`, pause graphics), `$5CF64`, `$A78AE` face-off close-up anim (`checkfo`), `$AB920`, `$B3530`. UNRESOLVED: the `$Cx-$Fx` commands and the flush/remap, needed only to export those.

### 3.7 updatescroll (L51912)

- Purpose: set the plane-B (rink) scroll registers and stream newly exposed map rows into the 64x32-cell plane. Called first in `setvideo` (L51875) each loop. The VBlank (`sub_15EA4` L51863) writes `Hscroll` to the plane-B horizontal scroll entry and `Vscroll` to plane-B VSRAM.
- Inputs: `Vpos`, `Hpos`, `Oldrow`, `sflags` bit 7, `word_FFC2F4` bit 4, `VmMap2` (= `$C000`), `a5` DMA list.
- Outputs: `Hscroll`, `Vscroll`, `Oldrow`, DMA entries (`long src, word len (words), word VRAM dst`).

```
updatescroll:
  if sflags bit7: return
  Hscroll = -$40 - Hpos
  Vscroll = -Vpos
  old = Oldrow ; new = Vpos asr 3 (floor) ; Oldrow = new
  if new == old: return
  map = (reverse ? RevRinkTilelist : Rinktilelist) ; map += long map[4]   ; -> W, H, cells
  n = 32 (d3 = $1F with dbeq)
  if new < old (camera moved DOWN the ice, Vpos decreased):            ; flags from cmp new,old
      r = new
      repeat: DMA map row (61 - r) -> plane row ((29 - r) & 31), W words ; r += 1 ; until r == old or n rows done
  else (camera moved UP):
      r = new
      repeat: DMA map row (30 - r) -> plane row ((30 - r) & 31), W words ; r -= 1 ; until r == old or n rows done
```

- Map row `m` always goes to plane row `m & 31`. The plane row for VRAM is `VmMap2 + row*128`. Rows are loaded 2 rows beyond the screen edge.
- At startup `Oldrow = $7D0` forces a 32-row fill (`setupice` L53046).
- Quirk: the `blt` that picks the direction tests the flags of `cmp.w d4,d1`. The `btst`/`movea`/`adda.l` in between leave N and V alone. Behaviour is as described.
- Map row 30 - r can be negative when `Vpos` > 247 (rows -1, -2). Those rows then read from before the map data, but they are never on screen. No horizontal streaming exists: all 48 columns are always in the 64-wide plane.
- For the port, `updatescroll` reduces to: draw the 384x680 rink image so that rink (`Hpos`, `Vpos`) is at the screen centre (`screen = (128 + x - Hpos, 112 - (y - Vpos))`).

### 3.8 checkwindow (L35779): how Vpos/Hpos move

- Called each loop from `DoGameFrame` (+$42) and a few stoppage routines. `freezewindow` (L35770) sets `yc1 = Vpos`, `xc1 = Hpos` and `sflags` bit 6 (scroll lock).

```
checkwindow:
  ty = yc1 ; tx = xc1
  if not (sflags bit6):
     o = puck struct
     if puckc >= 0:
        o = carrier struct
        if carrier pfgoal (shoots at top): yleader = min(yleader + 2*d7, 50)   ; $32
        else:                              yleader = max(yleader - 2*d7, -50)  ; $FFCE
     ty = (o.Yvel asr 7) + o.Ypos + yleader ; tx = o.Xpos
     yc1 = ty ; xc1 = tx
  ; vertical, dead zone +-10
  d = ty - Vpos
  if d < -10:      t = max(ty + 10, -200)          ; $FF38; "bgt" keeps t if t > -200
  elif d > 10:     t = min(ty - 10, 255)           ; "blt #$100" keeps t if t < 256, else t = 256  (max is 256)
  else: skip vertical
  s = t - Vpos ; if s != 0: s = s asr 4 ; if s == 0: s = 1 ; Vpos += s
  ; horizontal, dead zone +-40
  d = tx - Hpos
  if d < -40:      t = max(tx + 40, -60)           ; $FFC4 ("bge")
  elif d > 40:     t = min(tx - 40, 60)            ; $3C ("ble")
  else: return
  s = t - Hpos ; if s != 0: s = s asr 4 ; if s == 0: s = 1 ; Hpos += s
```

- Corrections to the inline notes: the vertical clamp is [-200, **256**]. The `s == 0 → 1` fix only happens for 0 < |t - pos| < 16 with a positive difference. A small negative difference already gives -1 from `asr`.
- `yleader` is set to `$3C` (60) at face-offs (L41330, L42108), which is above the ±50 clamp until it is next updated.

---

## 4. extractAssets94.js and package.json (current state)

- `package.json`: `npm run extractassets` → `node extractAssets94.js lst/nhl94.bin`. The only devDependency is `crc-32`. There is no `node_modules` in the repo, so the script fails at `require('crc-32')` until `npm install` is run.
- What it does: checks the ROM CRC32 against `0x9438F5DD` (matches `lst/nhl94.bin`; the error text wrongly says `3B6BF8BF`), then writes **raw byte slices** of 27 hard-coded ranges to `<out>/NHL94/Graphics/*.map.jim|*.anim`. The default `<out>` is `Extracted` in the current directory. Options: `-o dir`, `-v`. It does not decode anything: no PNG, no palettes, no maps, no sound.
- Ran it read-only with a `crc-32` shim on `NODE_PATH` and output to scratch: `node extractAssets94.js lst/nhl94.bin -o <scratch>/extracted -v`. Result: 27 files, 532 KB: `GameSetUp94-1/2`, `Title94-1..4`, `unknown5/6/7/9`, `IceRink94` (`$5605A-$5C408`, correct), `Sprites94.anim` (`$5C408-$A4B54`, 296,780 bytes), `BigFont94`, `TeamBlocks94`, `RonBarrCompressed`, `IceRink94Reverse` (`$B5180-$BB4EE`, correct), `ReplayOptions`, `PauseScreen` (`$BC05C-$BE26A`), `SmallFont94`, `GameSetupBkgd1/2`, `GameSetupLogoBorder`, `logoANA/BOS/BUF/CGY/CHI`.
- Problems:
  1. `Sprites94.anim` starts at `$5C408`, but the anim file starts at `$5DE7A`. The first `$1A72` bytes are two compressed tile blobs (`$5C408` ExtraChars, `$5CF64`). Its offsets are therefore not relative to the file start.
  2. The `logo*` ranges overlap each other (for example logoANA ends `$BFD9A` > logoBOS start `$BFD66`).
  3. All palette and sound entries are commented out and use **NHL 93** offsets (`Bruinsh.pal $11DA`, `Hockey.snd $F4C8`). They are wrong for 94.
  4. `src/teamdata94.asm` `incbin`s `..\Extracted\Graphics\Pals\*.pal`, but the script writes to `Extracted/NHL94/Graphics`.
  5. The help text says NHL 92.
- Needed for PNG output: tile decoding (§2.1), sprite piece assembly (§2.2), the rink map renderer (§3), palette conversion (§2.8), a PNG writer (zlib `deflateSync` + CRC is enough; no npm package needed), WAV writing for DAC samples (§5.4), and corrected ranges and addresses (§6). That is better done as a new script (§6) than as a patch to the slicer.

---

## 5. Sound

### 5.1 sfx (L44279) / song (L44297)

```
caller:  move.w #id,-(sp) ; bsr sfx        (or song)
sfx:   save d0-d7/a0-a6 ; d0 = stack word (at $40(sp)) ; if d0 < 0 (signed): skip
       lastsfx = d0 ; p_initfx(d0)
       restore ; move.l (sp),2(sp) ; addq #2,sp ; rts       ; pops the argument
song:  same, but does not write lastsfx
p_initfx (L61549):
       if d0 > $7A (unsigned): return
       if d0 >= $30: sub_1A304 (stop current music)       ; ids $30..$7A are music
       pick the free / oldest of 8 sequence slots (unk_FFD3D4, 6 bytes each)
       slot.ptr = long unk_2C648[d0] ; slot.time = 0 ; slot.pri = first byte of the sequence
       reset 8 channel records (unk_FFD1A4 + slot*8, stride $40): volume $7F
```

- Many callers push the id and then overwrite it with `move.w #x,(sp)` before the call (the id actually played is the last value written).
- `MusicVB` (L61792), run from VBlank, steps the sequences.

### 5.2 SFX ids as used by NHL 94 (from call sites)

The equates in `src/ram94.asm` (lines 28-63) are **NHL 93 values and do not match 94**. Examples: 93 `SFXwhistle = 10`, `SFXhorn = 24`, but 94 plays whistle 3 and horn 4 with those labels in the comments. The 93 list for reference: siren 0, beep1 1, beep2 2, stdef 5, puckbody 5, puckwall1 7, puckget 8, puckice 8, puckpost 9, whistle 10, pass 11, shotbh 12, shotfh 13, shotwiff 14, playerwall 15, check 18, check2 3, hithigh 21, hitlow 23, horn 24, crowdcheer 25, crowdboo 26, puckwall2 29, puckwall3 30, oooh 31, skatestop -1; songs Title 1, EOP 0, EOG 3, PO 4.

94 ids found at call sites:

| id | via | where (line) | meaning (from code/comments) |
|---|---|---|---|
| 0 | sfx | `checkgoal` L49814 | after a goal (93: siren) |
| 1 | sfx | `breakaway` L39781, L39940, `assnearest` L40599, `updatepentime` L46877 | "ding" (breakaway); penalty-time tick |
| 2 | sfx | `updatepentime` L46877, L51797 (`gameclock` = 60..61) | penalty over / one minute left |
| 3 | sfx | `Stop4Pen` L46476 | whistle |
| 4 | sfx | `clockcont` L30082 | horn (end of period) |
| 5 | sfx | `doshot` L37524 (wiff), `checkpuckcoll` L50242, L50528 | shot wiff / puck contact |
| 6 | sfx | `puckstick` L50608 | stick deflection |
| 8 / `$25` | sfx | `checkgoal` L49726 | puck hits the net frame: 8 while play is live (+ crowd), `$25` when the clock is stopped |
| `$D` | sfx | `setInjuryType` L49503 | injury |
| `$E` | sfx | `wallcollb2` L50115 | puck over/at the glass |
| `$10..$13` | sfx | pass L37066 | `$10 + ((… - puckvz) >> 2 & 3)` |
| `$14..$17` | sfx | `doshot` | backhand shot, `+ strength 0..3` |
| `$18..$1B` | sfx | `doshot` | forehand shot, `+ strength 0..3` |
| `$1C..$1F` | sfx | `newcheck` L48769 | body check, `$1C + ltack (0..3 cycling)` |
| `$1C` | sfx | `assgoaliecpu` L39092 | goalie frame `$2C8` event |
| `$20` | sfx | L50205 | player hits the boards (`#SFXplayerwall`) |
| `$24` | sfx | `puckbody` L50776, `puckgoalie` L50882 | puck hits a body / goalie |
| `$28..$2B` | sfx | `wallcoll` L50184 | puck hits the boards, `+ (d0 & 3)` |
| `$2C..$2F` | sfx | `updateplayers` L35554 | puck lands on the ice: `$2C + clamp(5 - Zvel.b, 0..)` if ≤ 3 |
| `$2F` | sfx | `Endfaceoff` L42447 | puck drop |
| `$B` | song | `AddPenalty` L45970, `FallDown` L49489, `puckstick` L50690, `puckgoalie` L50879 | crowd cheer (away player penalised or fallen, home save) |
| `$C` | song | `AddPenalty`, `FallDown` | crowd boo (home player penalised or fallen) |
| `$D` | song | `puckgoalie` L50879 | "away song" (away goalie save) |
| `$F` | song | L55725 | when home leads (after the game) |
| `$78` | song | `PeriodOver`/game over L53862, `newTitleScreen` L975422 | title / game-over music |
| `$79` | song | `PeriodOver` L53840, L48340, `PlayoffScreen` L54022 | period over / intermission |
| `$7A` | song | `sub_FCC76` L969620 | post-setup |
| `SongNum` | song | L29895, L41087, L42314 | organ tune chosen by `ChooseSong` (L973979): per-home-team table `unk_FE5B0` (6 bytes per team, by `SongIndex`), else a random pick from the 8 bytes at `unk_FE658` (`randomd0(8)`) |

### 5.3 Crowd noise is PSG, not samples (`updatesound` L52982)

Called from `periodiceevents`.

```
target = min(crowdlevel*8 + $400, $EFF)          ; unsigned (bls)
diff = target - asv
if diff > $28:       asv += $28
elif diff < -$28:    asv -= $28 ; if asv < 0: asv = 0
PSG <- $C8, $01                                    ; tone channel 2 period = $018 (the noise source)
PSG <- $F0 | ((asv >> 8) ^ $F)                     ; noise channel attenuation = 15 - high byte of asv
```

`move.b (asv).w,d0` reads the high byte of the word. The port can use a looped noise sample on the `Crowd` bus, with linear gain `(asv >> 8) / 15` (attenuation steps are 2 dB each on the real chip).

### 5.4 DAC (PCM) samples: exportable

- The Z80 driver (`unk_1AD90`, `$295` bytes, copied to Z80 RAM by `Z80_LoadROM` L63070) runs a sample loop. The 68000 also builds 29 volume tables in Z80 RAM `$1300..$1FFF` (table k: `out = (i - $80)*8/(8+k) + $80`, entry 0 forced to 0; `$1F00` is unity).
- The playback loop (Z80 `$007D..$0095`, decoded by hand): write YM2612 reg `$2A`; `a = voltab[(hl)]`; if `a == 0` jump to the "next pointer" (Z80 RAM `$26..$28`; 0 → parks on ROM byte 0 = silence); write `a` to `$4001`; `c += step` (operand at Z80 `$8E`); `hl += carry` (and `de = 0`); loop. It costs 117 Z80 T-states per iteration. Output rate is therefore `3,579,545 / 117 × step / 256 ≈ 119.5 × step` Hz, minus 68000-bus wait states.
- Sample data: **unsigned 8-bit mono PCM, ended by a `$00` byte.** The tables built by the 68000 map input 0 to 0, which is the stop test.
- Start: when a channel's instrument byte is ≥ `$60` (`sub_1A6xx`, L61985-62010), the 68000 writes the 24-bit address from `unk_1B01C[(instr-$60)*8]` to Z80 `$23..$25`, the second long (always 0) to `$26..$28`, and `$29,$00` to `$96..$97` (jump vector, which restarts the driver at `$0029`). Pitch: `sub_1A7D8` (L62057) writes `step = freq[note % 12] >> (8 - note/12)` (low byte) to Z80 `$8E`. `freq` = `unk_1A890` = `$146 $159 $16E $184 $19B $1B3 $1CD $1E8 $205 $224 $245 $268`. Volume selects the table: Z80 `$83` = `max(vol >> 2, 3)` (`sub_1ABAA` L62918).

Sample table `unk_1B01C` (ROM `$1B01C`, 15 entries x {long address, long 0}):

| instr | address | bytes to first `$00` | note |
|---|---|---|---|
| `$60` | `$2BFE8` | 604 | |
| `$61` | `$1B288` | 3369 | |
| `$62` | `$1B094` | 3869 | runs on into `$61`'s data (500-byte prefix) |
| `$63` | `$2B430` | 3604 | runs on into `$60` (3000-byte prefix) |
| `$64` | `$2A4AA` | 2603 | |
| `$65` | `$21748` | 8014 | |
| `$66` | `$29FFA` | 3803 | runs on into `$64` (1200-byte prefix) |
| `$67` | `$2AEDA` | 1362 | |
| `$68` | 0 | 0 | empty |
| `$69` | 0 | 0 | empty |
| `$6A` | `$2AEDA` | 1362 | same as `$67` |
| `$6B` | `$1F1FA` | 9545 | |
| `$6C` | `$1BFB6` | 12864 | |
| `$6D` | `$2369A` | 26971 | runs on into `$6E` (12000-byte prefix) |
| `$6E` | `$2657A` | 14971 | |

All samples lie in `$1B094..$2C247`. Music and SFX sequence data is at `$2C248..$4B7A0` (FM; not exported, no synthesis attempted).

---

## 6. Extraction plan (offline Node script, never used at runtime)

A new script, for example `tools/extract_godot_assets.js`. It uses plain Node 18+ with only `fs`, `path`, `zlib`, and needs no npm packages. Invoke it as `node tools/extract_godot_assets.js lst/nhl94.bin godot/assets`. Every step reads only the addresses below. Steps 1-7 were prototyped in the scratch probe, and their renders matched the game.

**Step 0. Load and verify.** Read the ROM (1,048,576 bytes). Check that CRC32 = `0x9438F5DD` (write the CRC with the zlib polynomial `0xEDB88320`). Helpers: `u8, s8, u16be, s16be, u32be`. `color(w) → [((w>>1)&7)*255/7, ((w>>5)&7)*255/7, ((w>>9)&7)*255/7]`. `tile(addr)` → 64 indexes (row-major, high nibble = left pixel). PNG writer: RGBA, colour type 6, filter 0 per row, `zlib.deflateSync`. Add an 8-bit grayscale writer (colour type 0) for index textures.

**Step 1. Palettes → `palettes.json`.**
- `rink`: 4 lines from `$59924` (raw words + `#RRGGBB`). Only lines 0-1 are used in game.
- `rink_reverse`: from `$B8A0A`.
- `teams[28]`: for i in 0..27: `p = u32($30E + 4i)`, `pd = p + u16(p+2)`, `home = 16 words at pd`, `away = 16 words at pd+32`. Name: Pascal-ish strings at `p + u16(p+4)` (as found: city, abbreviation, nickname, arena).
- Also write `cram_layout`: line 0 = rink 0, line 1 = rink 1, line 2 = home team `home`, line 3 = away team `away`. Index 0 of each line is transparent for sprites.

**Step 2. Sprite frames.**
- `A = $5DE7A`, `FS = A + u32(A+4)` (= `$9E724`), `T = A + 10` (= `$5DE84`), `N = u16(A+8)` (= 8257).
- For f in 1..845: read pieces `FS + u16(FS+2f) .. FS + u16(FS+2f+2)`, 8 bytes each (§2.2). Compute the bbox: x0 = min(p.x), y0 = min(p.y), x1 = max(p.x + 8w), y1 = max(p.y + 8h). Allocate a (x1-x0)×(y1-y0) image.
- For each piece, for col 0..w-1 and row 0..h-1: tile = `p.tile + col*h + row`. The destination cell is `dc = hf ? w-1-col : col`, `dr = vf ? h-1-row : row`. Draw at `(p.x - x0 + 8dc, p.y - y0 + 8dr)`, mirroring the tile's pixels when hf/vf. Skip pixel value 0. Draw pieces in table order: later pieces overwrite earlier ones. Because hardware sprites earlier in the link list are in front, draw **in reverse piece order** (or only fill pixels that are still empty) to match the VDP. The probe drew in forward order and showed no visible difference.
- Write two images per frame:
  - (a) **index texture** `sprites/idx/f%04d.png`: R = colour index × 17, G = palette line × 85, A = 255 where the pixel is not 0. Use it with a palette-lookup shader that does the team swap: line 2 → 3 for away.
  - (b) **preview RGBA** `sprites/rgba/f%04d.png`: lines 0/1 from the rink palettes, line 2 from a chosen team's home palette.
- Optionally pack all frames into one atlas (total area ≈ 852k px, fits 1024×1024 with shelf packing) and write `sprites/atlas_idx.png` + `atlas_rgba.png`.
- Sidecar `sprites/frames.json`, one object per frame: `{ "frame": f, "w":…, "h":…, "origin": [-x0, -y0], "hot": [hx, hy] | null, "palette_lines": [..], "pieces": [{x,y,tile,w,h,hf,vf,pal}], "atlas": [ax, ay] }`.
  - `origin` = pixel of the image that sits on the object's projected position.
  - `hot` = `[s8(Hotlist + 2f), s8(Hotlist + 2f + 1)]` for f ≤ 837, else null. It is in screen pixels from the origin (+y down). The game's `GetHot` returns `(hx, -hy)` in rink units, with the sign rules of §2.5.
- In Godot, place the image at `origin` offset. For x-flip, use `flip_h` with offset `x = -(w - origin.x)` so that pixel column px maps to -px-1 about the origin. Do the same for y.

**Step 3. Animation tables → `anims.json`.**
- Walk `SPAList` (`$5B1C`): id = 2; loop while `u16($5B1C+id) == $12`. dirs = 8 words, attr = word +$10. Parse lists starting at entry+$12, back to back. Each list = `{frame,time}` pairs until time < 0. Stop parsing lists at the first offset that is not one of the 8 dir offsets, or that starts a new header (first word `$12`, 8 even words in `$12..$200`, attr ≤ 1). Next id = end of the last list. This gives 66 entries ending at `$76B2` (checked).
- Emit `{ "id": "0x50C", "loop": attr&1, "dirs": [[ [frame,time], … ] × 8] }`. Keep the raw dir offsets too, so the two entries whose dir 7 points at the next header (`$F6E`, `$FAC`) are reproduced exactly (resolve them by reading through the ROM, as the game does).
- Add `revframetbl`: 846 words from `$F600E`.

**Step 4. Rink → tiles atlas, map, layers.**
- For `base` in {`$5605A` (normal), `$B5180` (reverse)}:
  - `pal = base + u32(base)`, `map = base + u32(base+4)`, `n = u16(base+8)` (assert bit 15 clear), tiles at `base+10`.
  - Write `rink/tiles_idx.png`: n tiles in a 16-tile-wide grid (128 px wide), index texture as in step 2 (R = index×17, A = 255 for all pixels, because plane tiles are opaque and index 0 = colour 0 of the line).
  - Write `rink/map.json`: `{ "w":48, "h":113, "crop_rows":85, "origin_px":[192,368], "cells":[u16 …] }`. Raw cell words, plus decoded arrays `tile`, `hflip`, `vflip`, `pal`, `prio` if handy.
- Pre-render two RGBA layers 384×680 (rows 0..84):
  - `rink/rink_base.png` (cells with bit 15 clear) and `rink/rink_front.png` (cells with bit 15 set, transparent elsewhere). Use lines 0/1 from the file and the chosen home/away team for lines 2/3.
  - Because benches, penalty boxes and the logo use lines 2/3, either render those layers per team at load time from the index atlas with a shader, or keep the index form (`rink_base_idx.png`, `rink_front_idx.png` with G = line) and colour them with the same palette shader as the sprites.
- Logos: for t in 0..27, `L = u32($FEA74 + 4t) + 8`, assert `u16(L) == 24`. Tiles at L+2. Write `rink/logo_%02d.png` (48×32, tiles row-major 6 across × 4 down, line 2 = team t home palette) plus an index version. In game, draw it at map px (168, 352), which is rink (-24 .. +23, +16 .. -15), over tiles 430..453. For the reverse rink, use the reverse map's cell words (tiles 428..451 with flips) and substitute logo tile `k` for rink tile `428+k`.

**Step 5. Horizontal side view (optional).** Render the PauseScreen jim (`$BC05C`: palette `+$1A8A`, map `+$1B0A`, 32×28, 212 raw tiles) to `rink/pause_side.png` the same way.

**Step 6. DAC samples → WAV.** For each row of the table in §5.4 with a non-zero address: read bytes from the address up to (not including) the first `$00`. Write `audio/dac/instr_%02X.wav` (PCM, 1 channel, 8-bit unsigned, so the data is used as-is). Use a nominal 10,000 Hz rate in the header, and record `nominal_rate` and `rate_formula: "119.5*step Hz, step = freq[note%12] >> (8-octave)"` in `audio/dac/samples.json`. Which SFX use which instrument and note is UNRESOLVED, so rates need tuning by ear or one emulator capture.

**Step 7. Sound id list → `audio/sfx_ids.json`** from the §5.2 table, with the 93 equates kept separately as `legacy93`.

**Validation checks the script should assert:**
- the CRC
- `u16($5DE82) == $2041`
- `FS + w[846] == $A44CA` and `Hotlist == $A44C8`
- every piece tile + size ≤ 8257
- SPA walk ends at `$76B2` with 66 entries
- map 48×113 and `map + 4 + 2*48*113 == $5C408` (normal) / `$BB4EE` (reverse)
- logo count 24 for all 28

---

## UNRESOLVED

1. Direction 7 of SPA `$F6E` and `$FAC` points into the next entry's header (would read junk pairs). Unknown whether it can happen in play. Port as data.
2. Names of the SPA ids not commented in the listing (Appendix A).
3. Sample rate and the instrument-to-SFX mapping for the DAC samples. The sequence format at `unk_2C648` was not decoded (the note per SFX gives the step). The Z80 loop timing gives an upper-bound rate of ≈ 119.5 × step Hz, before wait states.
4. Decompressor `$Cx-$Fx` commands and the ring flush/`remap` (`sub_1177A`, `sub_11924`, L44975-45200). Needed only for the face-off close-up (`$A78AE`), ExtraChars/pause graphics and two other blobs, none of which are in this scope.
5. The listing's `SetHor` decode is garbled between `printz` and the `icerinkmap` load. The described behaviour (tiles of `$BC05C`, map 32x28) comes from the data and a render.
6. `setplayer`'s handedness: the code sets x-flip when roster byte 4 bit 0 = 1. Whether that bit means left or right comes only from the listing comment ("R"). Not checked against a known player.
7. The anim palette block at `$9E6A4` is not read by any code found. Its purpose is unknown, so it is ignored.

---

## Appendix A: all SPAList entries

Columns: id (= offset from `SPAList` `$5B1C`), absolute ROM address, attr (1 = loop), frame lists as `frame/time`. Where every direction has the same times and dir d's frames are dir 0's frames + d·k, only dir 0 and k are shown. Otherwise all 8 directions are listed (`dN(=dN-1)` means the same list as the previous direction).

| id | abs | attr | lists |
|---|---|---|---|
