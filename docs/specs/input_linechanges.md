# Joypad input, player switching and line changes (NHL '94 Genesis)

Behavior spec for the port. Source: `lst/nhl94.bin.lst` (line numbers `Lnnnnn`), ROM bytes checked in `lst/nhl94.bin`, RAM names from `src/stubinc/ram_addrs.inc`. Coordinates use the port convention (origin center ice, +Y = top goal, directions 0-7 clockwise from +Y, 8 = none).

## 0. Overview

### 0.1 How the pieces fit

1. **Sampling (vblank).** `MusicVB` calls `ReadJoyData` (L61633). It reads the pads into one active-low byte per pad: `byte_FFBEF6` (pad 1), `byte_FFBEF7` (pad 2), `byte_FFBEF8`/`byte_FFBEF9` (pads 3/4, 4-way adapter only). Bit layout after reading is `S A C B R L D U` (bit 7 down to bit 0). Opposite directions are resolved here with table `unk_1A4DE`.
2. **Decoding (game loop).** `ReadJoy1..4` turn the raw byte into direction 0-8 (`jdtab`) plus held, new and changed button masks. `lj1..lj4` hold last loop's byte for edge detection.
3. **Dispatch.** `updateplayers` (L35329) walks the 16 sort objects. For each object whose `$34` (position) is `>= 0` it runs physics. Then, at L35556-35666, it runs `doinput` for the object if a controller owns it (`c1playernum..c4playernum`). It then runs the object's AI assignment (`asstab`) whether or not the object is joypad-controlled. Objects with `$34 < 0` (off the ice, in the box) skip all of it, `doinput` included.
4. **`doinput`** (L35886) maps buttons to actions. Section 0.3 has the full mapping.
5. **Switching.** `changeplayer` jumps to `chgplayer` (L976652), which picks the teammate nearest the puck. `setc1player`/`setc2player` move the controller, and `restorep1` moves the `pfjoycon` flag from the old player to the new one.
6. **Line changes.**
   - The menu opens through `SetLCmode` (A held 15 loops with the puck, or automatically at a stoppage). `sub_B92E`, `setlccords` and `getlchoice` draw it.
   - While it is open, `lineinput` reads A/B/C. `lcfound` writes the team's current line (`$16(team)`) and calls `SetPersonel`.
   - `SetPersonel`/`SetPlList` write `newpos`/`newpnum` into the team's six structs.
   - The AI assignments call `check4bench` every loop. A player being replaced gets `assbench` (skate to the bench at x=-144 and hop off). Then `setplayer` loads the new roster player into the same struct and inserts `assben` (hop on at x=-136).
   - Penalties: `asspenalty`, then `assdopen`; the return trip is `assepen`.
   - At faceoffs, `ResetBench`, `SetPersonel` and `forcepldata` apply the change instantly.

### 0.2 Globals, RAM and tables

| Name | Address | Size | Meaning (as used here) |
|---|---|---|---|
| `byte_FFBEF6..F9` | FFBEF6-F9 | byte x4 | Raw pad byte per pad, active low. Bits 7..0 = Start, A, C, B, Right, Left, Down, Up. Written each vblank by `ReadJoyData`. |
| `lj1..lj4` | FFBEEE-F4 | word x4 | Previous decoded (active-high) byte, for edge detection. |
| `c1playernum..c4playernum` | FFC320-26 | word x4 | SCnum controlled by pad 1..4, negative = none. |
| `cont1team..cont4team` | FFC328-2E | word x4 | Team of pad 1..4: 0 none, 1 home, 2 away. `cont3team`/`cont4team` are non-zero only in 4-way play. |
| `FourWayPlay` | FFD046 | word | Non-zero = 4-way adapter play. |
| `joypuckcarrier` | FFC318 | word | Misnamed. It says which pad `doinput` is serving: `$FFFF` = pad 1 or 2, `0` = pad 3, `1` = pad 4. |
| `word_FFBF06` | FFBF06 | 2 bytes | B-button countdown. High byte = pad 1 (d4=0), low byte = pad 2 (d4=2). Reloaded to `$11`. |
| `word_FFBF08` | FFBF08 | 2 bytes | Same as `word_FFBF06` for pads 3 (high) and 4 (low). It is swapped into `word_FFBF06` around their `doinput`. |
| `word_FFD41E` | FFD41E | 2 bytes | A-button hold timer while carrying the puck. High = pad 1, low = pad 2. Reloaded to `$0F`. |
| `word_FFD420` | FFD420 | 2 bytes | Same as `word_FFD41E` for pads 3/4 (swapped in). |
| `word_FFD412` | FFD412 | word | Faceoff grace countdown. Set to `$3C` (60) by `puckfaceoff2` L42047 and `Endfaceoff` L42449. When it runs out, both B counters reset to `$1111`. |
| `word_FFBF12` | FFBF12 | word | This loop's pad direction (0-8), saved before the horizontal-mode rotation. |
| `word_FFBE78` | FFBE78 | word | Marker nibbles for the graphics. Bits 0-3 = puck carrier SCnum (`$F` = none), bits 4-7 = pad-1 player, bits 8-11 = pad-2 player, bits 12-15 set elsewhere (UI). |
| `word_FFBE86` | FFBE86 | word | Same as `word_FFBE78` for pads 3/4 (swapped in). |
| `word_FFBF0A/0C/0E/10` | | word | Swapped around the pad-3/4 calls (`0A` to `0E`, `0C` to `10`). Nothing else in the listing reads them, so the swap has no effect. |
| `word_FFD05A`, `word_FFD05C` | FFD05A/C | word | Auto-goalie flag, non-zero = "Auto Goalie". `doinput` indexes them by pad (d4 0 to `D05A`, d4 2 to `D05C`). `restorep1` indexes them by team (home `D05A`, away `D05C`). Game setup copies `OptGoalie` into both (L962424). The pause menu text at L30483 shows "Manual Goalie"/"Auto Goalie" by `sflags` bit 1. |
| `OptLine` | FFD058 | word | 0 = line changes on, non-zero = off. Setup turns value 2 into 0 and sets `byte_FFC2FC` bit 4 (L962431). |
| `byte_FFC2FC` bit 4 | | bit | "Auto lines" mode (from `OptLine` = 2). Disables the manual menu, forces energy to `$1000` in `burst` and `makepde`, and has the CPU pick lines for human teams too (`sub_F590`). |
| `word_FFC2F6` | | bits | Bit 3: flip-pass request, consumed by `passmode`/`dopass`. Bit 6: tested by `doinput`, `faceoffinput` and `chgplayer` but never set anywhere in the listing (always 0). |
| `word_FFC2FA` | | bits | Bit 0: shootout. Bit 7: penalty-shot/shootout intro screen up (set by `sub_187B8` L55906). |
| `BA_PS_flags` | FFC2F2 | bits | Bit 0: cleared by the manual-goalie C. Bit 1: scratch for the manual goalie box. Bit 2: penalty shot or shootout in progress. Bit 5: PS first pass/shot used. |
| `word_FFC31A` | | word | Penalty-shot/shootout intro countdown (`$190` or `$64`, L41481). |
| `lastplayer`, `passplayer`, `onetimerplayer` | FFBEDA, FFBEE0, FFBF6C | word | Last toucher; pass target (negative = none); one-timer shooter (negative = none). |
| `inputjoy`, `TmpJoyPuckCarrier` | FFDED8, FFDEDA | word | Pad (`d4`) and `joypuckcarrier` saved for `assonetimer`, so it can hand that pad the shooter (L959106). |
| `fodir1`, `fodir2` | FFBF98/9A | word | Faceoff pull direction for the player shooting at the bottom goal (`fodir1`) and the top goal (`fodir2`). Reset to -1 at L42305. |
| `PBnum` | FFC3EA | byte | Players in the penalty boxes. High nibble = home, low nibble = away. |
| `PlList` | FFCF14 | 12 bytes | `SetPlList` output. `[0..5]` = roster slot + 1 (0 = empty), `[6..11]` = position code for the same index. |
| `HmShots` | FFC6CE | team | Home team struct. Away = `HmShots + $364` (`AwShots` FFCA32). |

Team struct fields used here (a2 = team struct):

| Offset | Meaning |
|---|---|
| `$12` | Pass attempts (stat). |
| `$16` | Current line, 0-6: 0 Scoring 1, 1 Scoring 2, 2 Checking, 3 Power Play 1, 4 Power Play 2, 5 Penalty Kill 1, 6 Penalty Kill 2. Names are ROM strings. |
| `$1E` | Long pointer to team data (roster records). |
| `$22` | Word address of the team's first SCstruct (`tmsort`: `$B04A` home, `$B34A` away). |
| `$24` | `tmap`, active player count (4-6). |
| `$26` | `tmgoalie`, goalie roster slot (negative = goalie pulled). |
| `$2E` | Last line-menu choice (0-2). |
| `$30` | Flags byte. Bit 0 = redraw the line box (set when a penalty ends, L46794). Bit 1 = line-change menu open. Bit 4 = offside. |
| `$32 + 2*slot` | Energy of roster slot (`tmpde`), full = `$1000`. |
| `$66 + 2*slot` | Status of roster slot (`tmpdst`): `-1` on ice, `-2` bench, `-3` (`$FFFD`) injured for period, `-4` (`$FFFC`) injured for game, `> 0` in penalty box. |
| `$16A + 8*line + pos` | Line table, 7 lines x 8 bytes. Byte `pos` (position code 0-6) holds roster slot + 1 (0 = empty). |

SCstruct flag bits **as this code uses them** (some differ from the 93 equates):
- `$62` (`pflags`): 1 `pfna`, 2 `pfnc`, 3 `pfjoycon`, 5 `pfalock`, 6 `pfteam`, 7 `pfgoal`. Unchanged.
- `$63` (`pflags2`): bit 0 fighting, bit 1 anim in progress.
  - **Bit 2 = unavailable** (`pf2unav` in 94; the 93 equate says bit 4).
  - **Bit 3 = line-change menu open on this controlled player.** `restorep1` calls it `pfnp`.
  - **Bit 4 = player committed a penalty** (`pf2pen` in 94).
  - **Bit 5 = no player collision** (set in `asspenalty`).
  - **Bit 7 = goalie C-hold flag.** Never set anywhere, so its code is dead.
- `$64` (`pflags3`): bit 1 breakaway, **bit 3 = shooting a one-timer** (set by `assonetimer` L959094).
  - **Bit 6 = B-release lockout.** Set when a player is given control, or on a B+C press. While set, the next B release is swallowed.
- `$76`: handedness byte in 94, set by `setplayer` L51694 as `(byte4 & 1) ^ 1`.

Button bit numbers (decoded, active high): 0 Up, 1 Down, 2 Left, 3 Right, **4 B, 5 C, 6 A, 7 Start**.

### 0.3 Button map quick reference

"Loop" means one `doinput` call: once per game loop per controlled player, not scaled by `d7`. "New" means pressed this loop (`d1`). "Held" means down now (`d3`). "Changed" means toggled since last loop (`d2`).

Highest priority first. Each context ends `doinput` unless stated.

| Context | A | B | C | Start | D-pad |
|---|---|---|---|---|---|
| Always first | | B and C both **new** in the same loop: the B press is dropped and its release is swallowed (lockout bit 6). | | **new** pauses (any context) | Penalty-shot intro up: any non-8 direction (any held button also counts) cuts the intro countdown to 2. |
| Faceoff (player has `assfaceoffpl`) | ignored | **new** plays faceoff swipe `$FEA`. Otherwise `$1014` is set every loop while no anim runs. | ignored | pause | Stored every loop as the pull direction (`fodir1`/`fodir2`). |
| Line-change menu open | **new** picks row 0 | **new** picks row 1 | **new** picks row 2 (invalid on special teams) | pause | Skates (if joycon, not locked, not fighting). |
| Skater **with puck** | **new**: timer = 15. Release before it expires: flip pass. Held 15 loops: flip pass, plus the line-change menu if allowed. | **new** enters pass mode. The pass fires on B release, or at once if a direction is held (`passmode`). | **new** enters shot mode (`SetShotMode`). Holding winds up, release swings (`ShotMode`). | pause | Skate (`doplayeracc`). |
| Goalie **with puck** | same as skater | same as skater | nothing (skates) | pause | Skate. Nothing at all while an anim is in progress. |
| Puck carrier, animation-locked (`pfalock`, not one-timing) | ignored | ignored | ignored | pause | ignored. Step 10 sends him to `loc_B81A`, which returns at once for the carrier. |
| Skater **without puck**, animation-locked | ignored | **new** switches at once to the teammate nearest the puck and sets lockout on the new player. | ignored | pause | ignored |
| Skater **without puck** | **new** (not one-timing) hold/hook: anim `$1122`, or `$C90` "stick in air". | Tap (released within 17 loops) switches to the teammate nearest the puck, or plays sweep check `$B24` if this player is already nearest. Held 17 loops with Manual Goalie: control goes to own goalie. Disabled in penalty shot/shootout. | **new** one-timer if this player is the loose puck's pass target in the offensive half. Otherwise speed burst/check (`burst`, anim `$C5E`, costs `$CC` energy). | pause | Skate (`doplayeracc`), unless one-timing. |
| Passer after a pass (still controlled) | | | **new** while the pass is in flight makes the AI receiver one-time it, and the receiver gets this pad. | | |
| Manual goalie **without puck** | **new** with a direction: dive that way (`$2F4`). | Tap switches to the nearest skater. In Auto Goalie, control is taken away at once. | **new** save attempt toward the puck (`goaliesave`). | pause | Skate, kept to `\|x\| <= 36` and not toward center inside `\|y\| <= 231`. |
| Fighting | nothing (`fightinput` = `rts`) | nothing | nothing | pause | nothing |

## 1. Pad reading

### ReadJoyData (L61633), sub_1A470 (L61725), table unk_1A4DE (L61763) — context, vblank side
- Purpose: sample the pads every vblank (called from `MusicVB`).
- If `FourWayPlay != 0`, the four adapter ports go through `sub_1A3B2`, `sub_1A3DC`, `sub_1A406` and `sub_1A430` into `byte_FFBEF6..F9`. Otherwise port 1 (`$A10003`) goes to `byte_FFBEF6` and port 2 (`$A10005`) to `byte_FFBEF7`.
- Per port (L61745-61761):
  1. Write 0 to the port and read `d0` (TH low: bit 5 Start, bit 4 A, bits 1/0 Down/Up).
  2. Write `$40` and read `d1` (TH high: bit 5 C, bit 4 B, bits 3-0 R L D U).
  3. `d0 = ((d0 << 2) & $C0) | (d1 & $3F)` gives the byte `S A C B R L D U`, active low.
  4. Invert both. `d0 &= $F0`, then `d0 |= unk_1A4DE[d1 & $F]`.
  5. Invert again and store (active low).
- `unk_1A4DE`, indexed by active-high RLDU (bit0 U, bit1 D, bit2 L, bit3 R). It cleans up opposite directions:

| idx | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | A | B | C | D | E | F |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| out | 0 | 1 | 2 | **1** | 4 | 5 | 6 | **6** | 8 | 9 | A | **A** | **8** | **9** | **A** | **0** |

- Quirk (port as-is): U+D gives Up, but U+D+L gives D+L and U+D+R gives D+R. L+R gives Right. All four give nothing.

### ReadJoy (L44566) and jdtab (L44581)
- Purpose: convert one raw pad byte into direction plus buttons. Called only through `ReadJoy1..4`. `sub_164D6` also uses `jdtab`, for off-screen arrows.
- Input: `d0.b` = raw active-low byte.
- Output: `d0.w = (held & $F0) | jdtab[held & $0F]`, so bits 0-3 = direction 0-8 and bits 4-7 = **held** buttons (B, C, A, Start). `d1.w` = full active-high byte (0-$FF). Clobbers `a0`.
- Steps: `not.b d0`; `d1 = d0` (zero-extended); `d0 &= $F0`; `d0 |= jdtab[d1 & $F]`.
- `jdtab` (16 bytes, index = RLDU active-high):

| idx | 0 | 1 U | 2 D | 3 UD | 4 L | 5 LU | 6 LD | 7 | 8 R | 9 RU | A RD | B | C | D | E | F |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| dir | 8 | 0 | 4 | 8 | 6 | 7 | 5 | 8 | 2 | 1 | 3 | 8 | 8 | 8 | 8 | 8 |

  So Up = 0 (+Y), Up-Right = 1, Right = 2, Down-Right = 3, Down = 4, Down-Left = 5, Left = 6, Up-Left = 7, none = 8. Entries 3, 7 and B-F cannot happen with real pads, because `unk_1A4DE` has already cleaned the bits.
- **Direction value 9 never comes from the pad.** `jdtab` only produces 0-8. The 9 that `doplayeracc` treats as "brake" comes from `skateto` (L42953, `moveq #9,d0` at L42978). `skateto` sets it when its lead-compensated target is within +-12 px on both axes (`cmp #$C` / `#$FFF4`, L42970-42979), and passes it to `doplayeracc` through `$43(a3)`. (`setlccords` also does `moveq #9,d0`, but that is a box width, unrelated.)
- Quirk: the listing comment says bits 4-7 are "new button presses". They are **held** buttons. New presses are in `d1` from `ReadJoyN`.

### ReadJoy1, ReadJoy2, ReadJoy3, ReadJoy4 (L44509-44566)
- Purpose: decode pad N with edge detection.
- Inputs: raw `byte_FFBEF6+N-1`, previous `ljN`.
- Outputs: `d0` = dir | held<<4 (from `ReadJoy`). `d1` = **new presses** (`held & (held ^ ljN)`), all 8 bits, so new d-pad presses are included. `d2` = **changed** bits (`held ^ ljN`). `d3` = **held** (8 bits). Writes `ljN = held`.
- Steps: `ReadJoy`; `d2 = ljN`; `ljN = d1`; `d3 = d1`; `d2 ^= d1`; `d1 &= d2`.
- A release shows up as: bit set in `d2`, clear in `d3`.
- Quirk: `ljN` only updates when `ReadJoyN` is called. In play that happens once per loop, and only when pad N's player is on ice (`$34 >= 0`) and visited by `updateplayers`. If the pad's player is off ice, or `cNplayernum < 0`, edges are measured against the last time it was read.

### getpzjoy (L34828)
- Purpose: read the pad that paused the game (pause menu, `_rjoy`).
- If `FourWayPlay == 0` or `word_FFC316 == 0`: `ReadJoy2` if `sflags` bit 1 is set, else `ReadJoy1`. Otherwise `ReadJoy3` if `word_FFC316 == 3`, else `ReadJoy4`.
- `word_FFC316` and `sflags` bit 1 are written by the Start handling in `doinput` (see step 4 there).

## 2. Dispatch in updateplayers (L35556-35666)

Runs inside the per-object loop, after physics and Z gravity, for objects with `$34 >= 0` (L35455: `tst.w $34(a3); bmi _nf1` skips all of it). `d6 = SCnum` of the object, `a3` = object.

1. `_done` (L35556): if `SCnum == puckc`, the player is not fighting (`$63` bit 0) and not in horizontal mode (`sflags` bit 7), then `d4 = -2` and `sub_C656` writes the puck-carrier nibble. Bits 0-3 of `word_FFBE78` were preset to `$F` at L35332.
2. `_tp` (L35567): if not faceoff (`sflags2` bit 0 clear) and `word_FFD412 != 0`:
   - `word_FFD412 -= 1`.
   - If it hit 0 or went negative: `word_FFD412 = 0`, `word_FFBF06 = $1111`, `word_FFBF08 = $1111`.
   - This runs **once per processed object**, so up to 16 times per loop. 60 lasts about 4 loops.
3. `_tp2` (L35581):
   - If `c1playernum == d6`: `ReadJoy1`, `d4 = 0`, `joypuckcarrier = $FFFF`, `doinput`, then go to step 4. Pad 2 is not checked for this object.
   - Else if `c2playernum == d6`: `ReadJoy2`, `d4 = 2`, `joypuckcarrier = $FFFF`, `doinput`.
4. `_t1` (L35597): if `d6 > 11` skip to step 6.
   - If `cont3team != 0` and `c3playernum == d6`:
     1. `ReadJoy3`, then `d4 = 0` (`clr.l`), `joypuckcarrier = 0`.
     2. Push and swap: `cont1team <- cont3team`, `c1playernum <- c3playernum`, `word_FFBF06 <- word_FFBF08`, `word_FFBF0E <- word_FFBF0A`, `word_FFD41E <- word_FFD420`, `word_FFBE78 <- word_FFBE86`.
     3. `doinput`.
     4. Copy back the other way (`word_FFBE86 <- word_FFBE78`, ..., `c3playernum <- c1playernum`, `cont3team <- cont1team`) and pop the originals.
5. Same for pad 4 (L35629): `cont4team`/`c4playernum`, `ReadJoy4`, `d4 = 2`, `joypuckcarrier = 1`. It swaps `cont2team <- cont4team`, `c2playernum <- c4playernum`, `word_FFBF06 <- word_FFBF08`, `word_FFBF10 <- word_FFBF0C`, `word_FFD41E <- word_FFD420`, `word_FFBE78 <- word_FFBE86`.
   - Pad 3 uses the high bytes of `word_FFBF08` and `word_FFD420` (d4 = 0); pad 4 uses the low bytes (d4 = 2).
   - Pads 3/4 use the pad-1/pad-2 auto-goalie flags (`word_FFD05A`/`word_FFD05C` by d4).
6. `_t1cont` (L35666): run the assignment `asstab[asslist[assnum]]` (after `loadTeamStruct`) for **every** processed object, joypad-controlled ones included. Most assignments do nothing for `pfjoycon` players (e.g. `assnothing`).

Quirk: `chgplayer` running for pad 3 (d4 = 0, with `cont1team`/`c1playernum` swapped) treats `c2playernum` as "the other controller", not pad 4. Players held by pad 4 are still excluded, because they have `pfjoycon`.

## 3. doinput (L35886-36508)

- Purpose: per-loop input for one joypad-controlled object.
- Callers: `updateplayers` only (above).
- Inputs:
  - `d0` = dir | held buttons<<4, `d1` = new, `d2` = changed, `d3` = held, `d4` = 0 (pad 1/3) or 2 (pad 2/4), `d6` = SCnum, `a3` = player.
  - Globals: as listed in 0.2.
- Exits: every path ends in `rts` or a tail jump. "Return" below means leave `doinput`.

Steps:

1. **B+C combo / B-release lockout** (L35888-35913):
   - If `d1` has B **and** C (both new this loop):
     - `d1 &= ~B`.
     - Set `$64` bit 6.
     - Go to step 2. `d2` keeps its B bit.
   - Otherwise:
     - If `d1 & B`: clear `$64` bit 6.
     - If `d2 & B`: clear `$64` bit 6. If it **was** set, the B counter for this pad = `$11` (`word_FFBF06` high byte if `d4 == 0`, else low byte), and `d2 &= ~B`.
   - Net effect: when lockout is set, the next B release does not reach the switch logic or `passmode`.
2. **Penalty-shot intro skip** (L35915): if `word_FFC2FA` bit 7 and `d0.b != 8`, call `sub_FE1AA`.
   - The compare is on the whole low byte (dir | held), so any held button with no direction also triggers it.
   - `sub_FE1AA` (L973204): if `cont2team == 0` **or** the player is the puck carrier, and `word_FFC31A > 2` (signed), then `word_FFC31A = 2`.
3. `word_FFBF12 = d0 & $F` (direction 0-8). Then `sub_C656` (with this `d4`) writes this player's SCnum into the pad's marker nibble.
4. **Start** (L35927): if `d1` bit 7:
   - If `joypuckcarrier < 0`:
     - `d4 == 0`: `startpause1`: `word_FFC316 = 0`, clear `sflags` bit 1, set `sflags` bit 0.
     - Otherwise: `startpause2`: `word_FFC316 = 0`, set `sflags` bit 1, set `sflags` bit 0.
   - Else:
     - `joypuckcarrier == 0`: `loc_7CDC`: `word_FFC316 = 3`, clear `sflags` bit 1, set pause.
     - Otherwise: `loc_7CEA`: `word_FFC316 = 4`, set `sflags` bit 1, set pause.
   - Return. The second `btst #7,d1` at L35937 is redundant.
5. **Horizontal mode** (L35942): if `sflags` bit 7 and `d0` bit 3 is clear (dir 0-7): `d0 = (d0 + 2) & 7`. This also drops the button bits.
   - `word_FFBF12` keeps the **unrotated** direction. Quirk: paths that read `word_FFBF12` (non-carrier skating, goalie dive, manual goalie skating) ignore the rotation.
6. If `sflags2` bit 0 (faceoff): go to `faceoffinput`.
7. If `$63` bit 3 (line-change menu open): go to `lineinput`.
8. If `pfjoycon` (`$62` bit 3) is clear: return.
9. **Passer's one-timer trigger** (L35962-35986). Save `d0-d2/a0/a3`. All of these must hold:
   - `lastplayer == SCnum`
   - `passplayer >= 0`
   - `onetimerplayer < 0`
   - `d1 & C`

   Then let `a3 = struct[passplayer]` and also require:
   - its `$34 != 0` (not a goalie)
   - `sub_F6C44()` gives "ne" (puck in the offensive half, below)
   - its `pfjoycon` is clear
   - its `$64` bit 3 is clear (not already one-timing)

   If all pass:
   - `inputjoy = d4`
   - `TmpJoyPuckCarrier = joypuckcarrier`
   - `assreplace($23 = assonetimer)` on the receiver
   - restore, return

   Otherwise restore and continue.
   - `sub_F6C44` (L959337): `y = pucky`, negated if `pfgoal == 0`. Returns Z clear ("ne") if `y >= 0`, Z set if `y < 0`. `d0`/`d1` are preserved, so only CCR is the result. The code between `_cont` and `_0` is dead.
10. **Locked** (L35987): if `$64` bit 3 is clear and `pfalock` is set, go to `loc_B81A` (step 21).
11. If fighting (`$63` bit 0): go to `fightinput` (`rts`).
12. If `puckc == SCnum`: go to `loc_B72E` (step 18, offense).
13. **No puck: A = hold.**
   - If `$34 != 0` (skater) and `$64` bit 3 is clear, and `d1 & A`: go to `holdplayer` (section 4).
   - Goalies and one-timing skaters skip this.
14. **Choose B handling** (L36009):
    - Skater:
      - If `BA_PS_flags` bit 2 (penalty shot/shootout): go to `loc_B42E` (step 16). B is ignored.
      - Otherwise: B logic (step 15).
    - Goalie:
      - `word_FFC2F6` bit 6 (never set) would go to B logic.
      - Otherwise, if the auto-goalie flag for this pad is non-zero (`word_FFD05A` for `d4 == 0`, `word_FFD05C` for `d4 == 2`), go to `changeplayer`. Taking away control happens every loop the goalie is controlled without the puck. The puck-carrier compare at L36030 is always false here.
      - Else: B logic.
15. **B logic** (`loc_B2DA`, L36036-36150). `cnt` = this pad's byte of `word_FFBF06`. `auto` = the auto-goalie flag for this pad (as in step 14).
    1. If B is **held** (`d3` bit 4) and `word_FFD412 == 0`:
       - If `cnt == 0`: go to step 16 (`loc_B42E`), skipping the press/release checks below.
       - `cnt -= 1`, clamped at 0.
       - If `cnt == 0` now:
         - `auto == 0`: go to "switch to goalie" (15.4).
         - Otherwise fall to 15.2.
       - If `cnt != 0`, fall to 15.2.
       - (Pad 1 and pad 2 branches are written differently, L36044-36080, but behave the same.)
    2. (`loc_B35C`) If `d1 & B` (new): `cnt = $11`, go to step 16.
    3. (`loc_B37E`) Else if `d2 & B` and B is not held (released):
       - Let `old` = this pad's byte of `word_FFBF06`, read before reloading. Then `cnt = $11`.
       - If `old != 0` (tap): `changeplayer`.
       - Else (counter had run out): `changeplayer` if `auto != 0`, else "switch to goalie".
       - Otherwise (no press, no release): go to step 16.
    4. **Switch to goalie** (`loc_B3E4`, L36129):
       - If `word_FFD412 != 0`: `changeplayer`.
       - `d0 = 5` if `d6 <= 5`, else `$B`.
       - `d0 = getGoalieSCnum(d0)`. If `d0 < 0`, return.
       - If `struct[d0]` has `pfjoycon`, return.
       - Otherwise `setc1player(d0)` (`d4 == 0`) or `setc2player(d0)`. Tail jump; return.
    - Timing:
      - On the press loop `cnt` is set to `$11`.
      - Each later held loop decrements it, so the 17th held loop after the press reaches 0 and switches to the goalie (Manual Goalie only).
      - A release on any of loops 1..17 after the press is a tap: `changeplayer`.
      - After the goalie switch, `cnt` stays 0 while held. The release then hits "switch to goalie" again, which returns because the goalie already has `pfjoycon`.
      - Counters are `$11` at play start because `word_FFD412` runs out after each faceoff.
16. **Non-carrier, after B** (`loc_B42E`, L36152): if `$34 != 0` (skater), go to step 17. **Goalie without puck:**
    1. **Dive.** If `d1 & A` and `word_FFBF12.b != 8`:
       - `$54.w` (facedir integer) = dir
       - `$5E.b` (nopuck) = 8
       - `SetSPA($2F4)` (goalie dive)
       - set `$63` bit 1 and `pfalock`
       - `crowdlevel += $96`
       - return
    2. If `d1 & C`: go to 16.4.
    3. If C is not held: clear `$63` bit 7, go to 16.5.
       - If C is held but `$63` bit 7 is clear: go to 16.5.
       - Otherwise (dead, bit 7 is never set): compute the anim frame pointer and discard it. If `$5B.b` (low byte of SPAnum) is negative, `SPAcnt = $A`. Return either way.
    4. **Save** (`loc_B4D0`, L36202):
       1. If `pfalock`: go to 16.5.
       2. `$54.w = vtoa(puckx - x, pucky - y)` (face the puck).
       3. Clear `BA_PS_flags` bit 0.
       4. **Dead arithmetic** (L36215-36261). Its results are overwritten inside `goaliesave` before being read:
          - `d0 = ((word at gameclock & 7) << 4) + $A0`, minus `$40` if `pucky > $DB` or `pucky <= $FF25`.
          - Predicted `x = puckx + (d0*puckvx >> 16)` and `y = pucky + (d0*puckvy >> 16)`.
          - `sub_B5D8` clamps y to `[$FEFD, $103]` and subtracts `d3` (held buttons). A `sroot` scaling follows when `x^2 + y^2 > $384`.
          - The `cmpi` lines at L36263-36268 have no branches.
       5. `bset #1,$63(a3)`. If anim-in-progress was already set, go to 16.5 (which returns).
       6. Call `goaliesave` with `a0 = puckcross` (`$BEE6`) and `d3 = $108`, or `a0 = puckcross+4` and `d3 = -$108` if `pfgoal` is set. All registers are saved and restored around the call. Return.
       - `goaliesave` (L39598, goalie spec) picks a save anim from `_saveanim`: `$146, $178, $250, $2A2, $1EC, $21E, $148E, $14C0, $14F2, $1544`.
       - Twenty unreferenced bytes at ROM `$B602` (L36301-36320) are an identical copy of that table (dead).
    5. **Goalie skate** (`loc_B616`, L36322):
       1. If `$63` bit 1 (anim in progress): return.
       2. If `$34 != 0`: `doplayeracc` (unreachable for skaters).
       3. Clear `BA_PS_flags` bit 1.
       4. If `x > $24` (36) and `Xvel > 0`: set bit 1, `Xvel = 0`.
       5. If `x < -$24` (`$FFDC`) and `Xvel < 0`: set bit 1, `Xvel = 0`.
       6. If `-231 < y <= 231` (`cmpi #$E7` `bgt` skip; `cmpi #$FF19` `ble` skip): when `(y XOR Yvel) < 0` (moving toward center) and `Yvel != 0`, set bit 1 and `Yvel = 0`.
       7. If bit 1 is set: return (no acceleration this loop).
       8. Otherwise `d0 = word_FFBF12`, then `doplayeracc`.
17. **Skater without puck** (`loc_B6BA`, L36373):
    1. `d0 = word_FFBF12`.
    2. If `$64` bit 3 (one-timing): return.
    3. If not `d1 & C`: `doplayeracc` (skate).
    4. **C pressed.** Go to `burst` if any of these holds:
       - `struct[lastplayer].$34 == 0` (last toucher was a goalie)
       - `SCnum != passplayer`
       - `puckc >= 0` (puck carried)
       - `sub_F6C44()` gives "eq" (puck in own half)
    5. Otherwise:
       - `inputjoy = d4`
       - `TmpJoyPuckCarrier = joypuckcarrier`
       - `assreplace($23 assonetimer)` on self
       - return
    - Quirk: `lastplayer` is used as an index without a sign check (`asl #7`).
18. **Offense, with puck** (`loc_B72E`, L36404):
    1. `checkob` (offside-signal check, L40493).
    2. If goalie and `$63` bit 1: return.
    3. If `sflags` bit 2: go to `passmode`. If `sflags` bit 3: go to `ShotMode`.
    4. If `d1 & B`: `sub_FEE60()`, then go to `setpassmode`.
    5. If `d1 & A`: A timer for this pad (`word_FFD41E` high byte if `d4 == 0`, else low byte) = `$0F`.
    6. If A is held:
       - `timer -= 1`, clamped at 0.
       - If `timer == 0`: set `word_FFC2F6` bit 3 (flip request), call `setpassmode`, go to `SetLCmode`.
    7. (`loc_B7E2`) If A is not held and `d2 & A` (released): set `word_FFC2F6` bit 3, go to `setpassmode`.
    8. (`loc_B7FC`) If goalie: `doplayeracc`.
    9. If `d1 & C`: `sub_FEE60()`, then go to `SetShotMode`.
    10. `doplayeracc` (d0 = rotated dir | buttons; `doplayeracc` masks with `$F`).
    - A timing:
      - The press loop sets the timer to 15 and decrements it to 14 in the same loop.
      - Held, it reaches 0 on the 14th loop after the press (15 loops counting the press). Release before that means flip on release.
      - Quirk: the timer is only reloaded by a new A press **while carrying**. If A is already held when the puck is gained and the timer is 0, the flip (and line menu) fires at once.
    - `sub_FEE60` (L975053), user-record stats:
      - If the clock is running (`gmode` bit 0 clear): `a0 = $FFDEA4` (`d4 == 0`) or `$FFDEAC`.
      - `(a0).l += 1`.
      - If `word_FFBF12 != 8` and `word_FFBF12 != $54.w` (facing): `4(a0).l += 1`.
19. `getGoalieSCnum` (L36508):
    - In: `d0` = SCnum of the team's last struct (5 or 11).
    - Scans `struct[d0], struct[d0-1], ..., struct[d0-5]` and returns the SCnum of the first with `$34 == 0`. Returns `$FFFF` if none.
    - Preserves `d1/a0`.
20. **faceoffinput** (L36529):
    1. If `word_FFC2F6` bit 6 (never): return.
    2. `d4 = assnum`. If `asslist[d4] != $17` (`assfaceoffpl`): return.
    3. `a0 = &fodir1`, or `&fodir2` if `pfgoal`. Then `*a0 = d0` (whole word: dir, after horizontal rotation, plus held-button bits; the consumer `Endfaceoff` tests only bit 3 and masks with 7).
    4. If `$63` bit 1: return.
    5. If `d1 & B`: `SetSPA($FEA)` (faceoff swipe) and set `$63` bit 1. Otherwise `SetSPA($1014)` (faceoff ready).
    - The listing comment "branch if pressed" at L36551 is wrong: the branch is taken when B is **not** new.
21. **Animation-locked, no puck** (`loc_B81A`, L36478):
    1. If `puckc == SCnum`: return.
    2. If not `d1 & B`: return.
    3. If `word_FFC2F6` bit 6 (never): return.
    4. `bsr changeplayer`.
    5. `d0 = c1playernum` (`d4 == 0`) or `c2playernum`. If `d0 >= 0`, set `struct[d0].$64` bit 6 (lockout, so the coming B release does nothing).
    6. Return.

Calls that live in other specs (summaries so the button map is complete):
- `setpassmode` (L36893): `passdir = $54.w & 7`.
  - In a penalty shot (`BA_PS_flags` bit 2): clear `word_FFC2FA` bit 2. Test-and-set `BA_PS_flags` bit 5; if it was already set, return **without** entering pass mode (only one PS pass/shot). Clear `word_FFC2FA` bit 5. `word_FFC31C = $64`.
  - Set `sflags` bit 2.
- `passmode` (L36913):
  - Goes to `dopass` if B changed (`d2` bit 4) or `word_FFC2F6` bit 3 is set.
  - Otherwise, if `d0` bit 3 (no direction), return and keep waiting.
  - Otherwise `passdir = d0 & 7` and fall into `dopass`.
  - So a pass fires on B release, or on the first loop after the press that has a direction held.
  - `dopass`:
    - Clears pass mode. `puckc = -1`. `nopuck = $10`. `lastplayer = SCnum`.
    - If `word_FFC2F6` bit 3 was set (cleared here), it is a **flip pass**: `sub_F67E4` picks the target into `word_FFD414`/`word_FFD416`, `word_FFD418 = $12` (or `$3A` if `word_FFC2F8` bit 2), and `sub_F6778` launches with `puckflip`.
    - Otherwise a normal pass: best receiver, `passto`.
    - Then the swing anim (`$366` goalie, `$718` forehand, `$78A` backhand) and pass sfx.
  - `passto` (L37074) moves control only when the passer is a joypad-controlled **goalie**:
    - The receiver gets lockout bit 6.
    - Co-op (`cont1team == cont2team`): the passer's pad gets the receiver.
    - Otherwise: the pad whose team matches.
    - Skater passes do not switch control. Control follows the puck at pickup (`puckstick` L50534-50771).
- `SetShotMode` (L37411) / `ShotMode` (L37444):
  - Shot mode sets `passdir = 8`, `passspeed = $F`, and anim `$7FC` (forehand) or `$92E` (backhand).
  - While `SPAnum < $10`: `passspeed += d7`, and the d-pad aims (`passdir`).
  - The swing starts when C changes (released). If `shotspd $6C < $14`, it also starts automatically once `SPAnum > 8`.
  - At `SPAnum >= $1C`: `prepshot`, then `doshot`.

## 4. Defensive button actions

### holdplayer (L36863) / Acheck (L36872)
- Purpose: A on defense, hold/hook. `doinput` step 13 jumps here. The CPU (`check4check`) enters at `Acheck` with `a0` already set.
- Steps:
  1. Set `pfalock`. `d1 = $1122` (normal hold).
  2. If `impact $32 == 0`: `SetSPA($1122)`; return.
  3. `a0 = struct[impactp $2E]`.
  4. (`Acheck`) Set `pfalock`, `d1 = $1122`. If `impact == 0`: `SetSPA($1122)`.
  5. `d = y(a3) - y(a0)`. If `pfgoal` is set, `d = -d`.
     - The `bmi` reads N from the `sub` when `pfgoal == 0` (`btst` does not change N), and from the `neg` otherwise.
  6. If `d < 0`: `SetSPA($1122)`. Otherwise `SetSPA($C90)` (hold, stick in air).
  - In words: the other player is level with or ahead of me toward the goal I attack: `$C90`.

### burst (L36830)
- Purpose: C on defense, speed burst/check.
- Steps:
  1. `d0 = getpde()` = energy of `pnum`. Sets `a2` = team and `d1 = 2*pnum`.
  2. If `OptLine == 0`:
     - `d0 -= $CC` (204), then `setpde(d0)`, which clamps `d0` to `>= 0` in the register too and stores it.
     - If `byte_FFC2FC` bit 4: `d0 = $1000`.
  3. `d0 = d0 >> 7` (`lsr`, unsigned): `$1000` gives 32.
  4. `d1 = d0`.
  5. `dir = $54.w` (facing integer). Take the `dirtab` entry for `dir` (4 bytes: x word at +0, y word at +2). `Xvel += low16(dirtab.x * d0)` and `Yvel += low16(dirtab.y * d1)` (`muls`). Full energy gives 200*32 = 6400 on a straight axis.
  6. Set `pfalock`. `SetSPA($C5E)` (burst/check).
  - With line changes off, energy is not reduced and is used as stored.

### fightinput (L36560)
- `rts`. Fighting input does nothing in 94 (`assfight` and `assfwatch` are `rts` too).

### sub_C656 (L37819)
- Purpose: write SCnum into a nibble of `word_FFBE78`.
- In: `d4` (-2 puck carrier, 0 pad 1, 2 pad 2), `a3`.
- Steps:
  1. `s = (2 + d4) * 2` (0, 4 or 8).
  2. `word_FFBE78 &= rol($FFF0, s)`.
  3. `word_FFBE78 |= SCnum << s`.
- Also called by `asspenalty` with `d4 = -2`, which puts the penalized player in the carrier nibble.

## 5. Player switching

### changeplayer (L37216)
- `jmp chgplayer`. The code after it, L37220-37295, is the old 93 version and is unreachable (dead).
- Callers: `doinput` (B tap, Auto Goalie, locked B), `asspenalty._clrplayer`, `setchgplayer` (faceoff setup L42370, sets `cNplayernum = -1` first).

### chgplayer (L976652)
- Purpose: give pad `d4` the teammate nearest the puck.
- Inputs:
  - `d4` (0/2)
  - `d6`: caller's value. It is used as the fallback when no candidate is found; from `doinput` it is the current SCnum.
  - `cont1team`/`cont2team`, `c1playernum`/`c2playernum`, `puckx/y`, `puckvx/vy`, `BA_PS_flags`, `BA_Sktr_SCnum`, `BA_Goalie_SCnum`.
- Steps:
  1. If `word_FFC2F6` bit 6 (never): return.
  2. Save `d0-d6/a0-a1`.
  3. Target `T = (puckx + (puckvx asr 8), pucky + (puckvy asr 8))`.
  4. `d3 = d4 ^ 2` (the other pad). `d5 = $FFFFFFFF` (best distance).
  5. `a0` = home structs if `contXteam[d4] == 1`, else away (+`$300`).
  6. For the 6 team structs, skip a struct when any of these holds:
     - `$34 <= 0` (goalie or off ice)
     - `$63` bit 2 (unavailable)
     - its SCnum is not this pad's current player and it has `pfjoycon`
     - `BA_PS_flags` bit 2 is set and its SCnum is neither `BA_Sktr_SCnum` nor `BA_Goalie_SCnum`
     - `pfalock`
     - `dist = (Tx - x)^2 + (Ty - y)^2` (16x16 `muls`, 32-bit sum) is greater than `d5` (unsigned `bhi`)
     - its SCnum is the other pad's player

     Otherwise `d5 = dist`, `d6 = SCnum`. A tie goes to the later struct.
  7. Push the return to `_ex`, which restores and returns.
     - If `d6 == contXplayernum[d4]` (this player is nearest, or no candidate and `d6` = current): go to `Sweepcheck` on `a3`.
     - Else `d0 = d6`, then `setc1player` (`d4 == 0`) or `setc2player`.
- Quirk: `d6` is never initialized. With no candidate, the switch target is whatever the caller had in `d6`. From `asspenalty` that is the penalized player's SCnum, so pad 2 could be given the player being sent off when `d4 = 2` (see `asspenalty`).

### swpchk (L976734)
- `jmp Sweepcheck`. The local `setc1player`/`setc2player` stubs at L976737/L976740 jump to the real ones.

### Sweepcheck (L37296)
- Set `pfalock`, `SetSPA($B24)` (sweep/poke check anim) on `a3`.
- Also used by the CPU (`skatetopuck`).

### setc1player (L37305), setc2player (L37320)
- In: `d0` = new SCnum.
- If `d0 == c1playernum` (`c2playernum`): return.
- Otherwise `restorep1(d1 = old)`, then `cNplayernum = d0`. `d0` may have been changed by `restorep1`. `d1/a0/a1` are preserved.

### restorep1 (L37335)
- In: `d1` = old SCnum, `d0` = new SCnum. Out: `d0` = SCnum to store.
- Steps:
  1. If `0 <= d1 <= 11`:
     - If `old.$63` bit 3 (line menu open): `d0 = d1` (refuse the switch; the stored value stays old) and return.
     - Clear `old.pfjoycon`.
     - If `old.$64` bit 3 is clear (not one-timing): set `old.pfna`, so the AI assignment restarts.
  2. If `0 <= d0 <= 11`:
     - If (`BA_PS_flags` bit 2 or `word_FFC2FA` bit 0) and `new.$34 == 0` (goalie): `flag = word_FFD05C` if `new.pfteam`, else `word_FFD05A`. If `flag != 0`, set `d0 = 6` (away) or `0` (home) and return **without** setting `pfjoycon`.
     - Set `new.pfjoycon`.
- Quirks:
  - `doinput` indexes the auto-goalie flags by pad, but this routine indexes them by team.
  - The PS/shootout goalie case stores SCnum 0 or 6 (the team's first struct, not necessarily the goalie) and leaves `pfjoycon` clear.

## 6. Line-change menu

### SetLCmode (L36566) → falls into sub_B92E (L36584)
- Purpose: open the line-change menu on player `a3`.
- Callers: `doinput` step 18 (A held 15 loops), `sub_F5C6` (stoppage, L41767).
- Steps:
  1. Return if `OptLine != 0` or `byte_FFC2FC` bit 4 (auto lines).
  2. `loadTeamStruct` (a2 = own team).
  3. Test-and-set `team.$30` bit 1. If it was already set: return.
  4. If `word_FFC2F6` bit 3 is clear: clear `sflags` bit 2 (cancel pass mode). With a pending flip request, pass mode is kept so the flip still fires.
  5. Clear `sflags` bit 3 (cancel shot mode).
  6. Set `$63` bit 3 (menu open; `doinput` now goes to `lineinput`).
  7. Fall through to `sub_B92E` (draw).
- `sub_B92E` (draw, UI only):
  1. `setlccords`. If `printy >= $F`: set `sflags3` bit 0 (box is at the bottom). Else call `box` (erases a 19x8 tile area at tile (11,2)) and `setlccords` again.
  2. `Framer` draws a frame of `d0 x d1` tiles. Then `printy -= 2`, `printx += 1`.
  3. For `d4 = 2, 1, 0`:
     - `c = getlchoice(d4)`. If `c < 0`, skip the row (`printy` unchanged).
     - If `team.$30` bit 1 is clear (menu closed; this redraw shows the result), draw only the row `d4 == team.$2E`, and draw it with `c = team.$16`.
     - Draw: the label `"A "+d4` (the string is the pointer value `$00044120` itself: length 4, `'A'+d4`, `' '`); the line name (string `c` from the list at `FaceOffsprites`, `sub_13508`); and an energy bar `sub_12E66(c)` with fill `min(getlinee(c)/256, 15)`.
     - `printx -= 5`, `printy -= 1`.
     - Rows go up the screen from C to A, so A is the top row (inferred from `printy` decreasing).
  4. Print a team-data string (`$1E(team)` + offsets) with `printx += 2`.

### setlccords (L36634)
- Purpose: place the line box.
- In: `a2` = team. Out: `printx`, `printy`, `printa`, `printm` set; `d0 = 9` (width); `d1 = 6` or `5` (height).
- Steps:
  1. `d0 = $16` if `a2 == $C6CE` (home), else 0.
  2. If `gmode` bit 1: `d0 ^= $16`.
  3. `printz` with inline string `00 06 BF 16 00 00` (verified ROM `$B9E2`): sets `printa = $8000`, `printm = 0`, `printx = $16` (22), `printy = 0`. No characters.
  4. `printy += d0` (0 = top, 22 = bottom).
  5. `d1 = 6`. If `getlchoice(2) < 0` (only two choices): `d1 = 5` and `printy += 1`.
  6. `d0 = 9`.

### getlchoice (L36661), getlchoice2 (L36668), _tab (L36688)
- Purpose: map menu row 0-2 (A/B/C) to a line number 0-6, or -1.
- In: `d0` = row, `a2` = team. Out: `d0.w` = line, sign-extended (`$FF` gives -1). Clobbers `a0`, preserves `d1/d2`.
- Steps:
  1. `other = word $388(a2)` if `a2 == $C6CE` (that is `away.$24`), else `word -$340(a2)` (`home.$24`).
  2. `diff = other - my.$24` (tmap).
  3. `base = 0` if `diff == 0`, `$15` if `diff < 0` (I have more: power play), `$2A` if `diff > 0` (shorthanded).
  4. `d0 = _tab[row + base + 3*team.$16]`.
- `_tab` (64 bytes, ROM `$BA48`), rows by current line:

| base | line 0 | line 1 | line 2 | line 3 | line 4 | line 5 | line 6 |
|---|---|---|---|---|---|---|---|
| `$00` even | 0,1,2 | 1,2,0 | 2,0,1 | 0,1,2 | 0,1,2 | 0,1,2 | 0,1,2 |
| `$15` PP | 3,4,FF | 3,4,FF | 3,4,FF | 3,4,FF | 4,3,FF | 3,4,FF | 3,4,FF |
| `$2A` PK | 5,6,FF | 5,6,FF | 5,6,FF | 5,6,FF | 5,6,FF | 5,6,FF | 6,5,FF |

  The 64th byte is `FF` (padding).
  - At even strength A/B/C = Scoring 1 / Scoring 2 / Checking, rotated so A is the current line when it is 0-2.
  - On the power play A/B = PP1/PP2 (swapped when the current line is PP2).
  - Shorthanded A/B = PK1/PK2 (swapped when the current line is PK2).
  - C gives -1 on special teams.

### lineinput (L36756)
- Purpose: input while the menu is open (`$63` bit 3). Runs before the `pfjoycon` check.
- Steps:
  1. If `word_FFC2F6` bit 3 (flip pending): save all registers, `passmode`, restore. This is the loop where the A-hold flip actually fires.
  2. `a2 = $C6CE`, or `+$364` if `pfteam`.
  3. Test-and-clear `team.$30` bit 0. If it was set: `lcfound2` (erase), then `sub_B92E` (redraw).
  4. `d2 = 0`. If `d1 & A`: `lcfound`. Then `d2 = 1` and `d1 & B`: `lcfound`. Then `d2 = 2` and `d1 & C`: `lcfound`. Priority A > B > C.
  5. If `pfjoycon` and not `pfalock` and not fighting: `doplayeracc(d0)`. Otherwise return.
- Note: the B press that picks a row does not touch the B counter. The B release that follows, if the player has no puck, is a B tap and switches player.

### lcfound (L36797) → falls into lcfound2
- In: `d2` = row 0-2, `a2` = team.
- Steps:
  1. `d0 = d2`; `team.$2E = d2`.
  2. `d0 = getlchoice(d0)`. If `d0 < 0`: return (menu stays open).
  3. Clear `$63` bit 3. Set `pfjoycon`.
  4. `loadTeamStruct`. Clear `team.$30` bit 1. `team.$16 = d0`.
  5. `SetPersonel`.
  6. Fall into `lcfound2`.

### lcfound2 (L36813)
- Purpose: erase the box.
- Steps:
  1. If `sflags` bit 7 (horizontal): return.
  2. `setlccords`. If `printy >= $F`: clear `sflags3` bit 0.
  3. `d1 += 1`; `eraser(d0 = 9, d1, d2 = $7FF)`.
  4. Go to `PrintScores1` (redraw the score bar).

### Context: menu at stoppages (puckfaceoff L41694-41835; outside the listed scope, summarized)
When `OptLine == 0`:
1. Clear `$30` bit 1 of both teams and `$63` bit 3 of structs 0-11.
2. For `c1playernum` and `c2playernum` (if `>= 0`), call `sub_F5C6`: clear `$63` bit 3, then `SetLCmode`. If the menu opened, store a timer and the SCnum in the faceoff puck struct:
   - home: `$40 = $258` (600), `$44 = SCnum`
   - away: `$42 = $168` (360), `$46 = SCnum`

   These fields start as `st` bytes (negative).
3. `sub_F64E` ticks each timer:
   - Menu closed: set the timer negative and redraw the result.
   - Otherwise `timer -= d7`. On expiry: `lcfound(row 0 = A)` and redraw.
4. Once both timers are negative, `sub_F590` runs `CompLine` + `SetPersonel` for non-human teams (or every team when `byte_FFC2FC` bit 4), then the faceoff proceeds (`assreplace($1C)`).

## 7. Getting players on and off the ice

### SetPersonel (L51236)
- Purpose: decide which roster players should be on the ice for team `a2`, and tag the six structs.
- Callers: `lcfound`, `sub_F590`, `ChkGoalies` (goalie pull), faceoff/penalty code (L41333, L42111-42115, L48381), L34359.
- Writes: `$60` (newpos) and `$61` (newpnum) of the team's six structs; `PlList`.
- Steps:
  1. For the 6 structs from `team.$22`: `newpos = $FF`, `newpnum = $FF`.
  2. `SetPlList`.
  3. Pass 1 (keep players already in a struct). For `i = 5..0`:
     - `s = PlList[i]`. If `s == 0`, skip.
     - `s -= 1`. Find the first struct with `pnum $66 == s` (`dbeq`).
     - If found: `newpos = PlList[6+i]`, `newpnum = s`, `PlList[i] = 0`.
  4. Pass 2 (place the rest). For `i = 5..0` with `PlList[i] != 0` (`s = PlList[i] - 1`), scan from the first struct:
     - Look for a struct with `newpnum < 0` (`dbmi`). If found, remember it in `a0`.
     - If that struct's `$34 < 0` (off ice), keep scanning (`dbpl`). The last remembered struct is used when `$34 >= 0` is hit or the count runs out.
     - Then `a0.newpos = PlList[6+i]`, `a0.newpnum = s`, `PlList[i] = 0`.
  - Quirks:
    - If the scan ends on a struct with `newpnum >= 0` and `$34 < 0`, the `dbpl` makes the counter go past -1 and the scan runs into the next team's structs (counter at -2, about 65k iterations).
    - If no free struct was ever found, `a0` is stale: it holds the last value from the previous iteration or the caller.

### SetPlList (L51300)
- Purpose: build `PlList` from the current line.
- In: `a2` = team.
- Steps:
  1. Clear `PlList[0..5]`. `PlList[6..11]` is not cleared.
  2. `a0 = priolist`, or `priolist + 1` if `tmgoalie < 0` (goalie pulled).
  3. `a1 = team + $16A + 8*team.$16` (current line).
  4. For `i = tmap-1 .. 0`:
     - `p = a0[i]`.
     - `PlList[i] = a1[p]`. `PlList[6+i] = p`.
     - If `p == 0` (goalie slot): `PlList[i] = 1 + tmgoalie`.
  5. For `i = 5..0`, if `v = PlList[i] != 0`, check the status `w = team.$66[2*(v-1)]`:
     - Unavailable when `w == -3`, `w == -4` or `w > 0`. `w <= 0` otherwise is fine (-1, -2 and 0 are available).
     - If unavailable:
       - `a1 = team + $16A` (line 0 base, all lines).
       - `a0 = sublist + sublist_word[PlList[6+i]]`.
       - Read bytes `b` from `a0` until one is negative (the final `$FF`) or `findAvailablePlayer(a1[b])` succeeds.
       - On the `$FF` (`_error`): `N = sub_9F9A()` (roster count: number of player records before the word `2`). Try `findAvailablePlayer(v)` for `v = N, N-1, ..., 1`. If none works, `PlList[i]` keeps the unavailable player.
- `priolist` (ROM `$19286`, 8 bytes): `0, 1, 2, 4, 3, 5, 6, FF`. Position codes: 0 G, 1 LD, 2 RD, 3 LW, 4 C, 5 RW, 6 extra attacker.
  - With goalie, tmap 6: G, LD, RD, C, LW, RW.
  - tmap 5 drops RW; tmap 4 drops LW and RW.
  - No goalie: LD, RD, C, LW, RW, 6.
- `sublist` (ROM `$1921C`, 106 bytes, verified). Seven word offsets from the table start, indexed by position code: `$000E, $000E, $001C, $002A, $0054, $003F, $0054`. Then 13 runs of 7 bytes, then `$FF`. A byte is `8*line + pos` into the line table, and the runs are **not** terminated individually, so the search continues into the following runs:

| offset | bytes | meaning |
|---|---|---|
| `$0E` | 01 09 11 19 21 29 31 | LD of lines 0-6 |
| `$15` | 02 0A 12 1A 22 2A 32 | RD |
| `$1C` | 02 0A 12 1A 22 2A 32 | RD |
| `$23` | 01 09 11 19 21 29 31 | LD |
| `$2A` | 03 0B 13 1B 23 2B 33 | LW |
| `$31` | 05 0D 15 1D 25 2D 35 | RW |
| `$38` | 04 0C 14 1C 24 2C 34 | C |
| `$3F` | 05 0D 15 1D 25 2D 35 | RW |
| `$46` | 03 0B 13 1B 23 2B 33 | LW |
| `$4D` | 04 0C 14 1C 24 2C 34 | C |
| `$54` | 04 0C 14 1C 24 2C 34 | C |
| `$5B` | 03 0B 13 1B 23 2B 33 | LW |
| `$62` | 05 0D 15 1D 25 2D 35 | RW |
| `$69` | FF | end |

  Search order per position:
  - G and LD start at `$0E`: LD, RD, RD, LD, LW, RW, C, RW, LW, C, C, LW, RW. The goalie slot falls back to defensemen.
  - RD starts at `$1C`.
  - LW starts at `$2A`.
  - RW starts at `$3F`.
  - C and extra attacker start at `$54`: C, LW, RW.

### findAvailablePlayer (L51375)
- In: `d0` = roster slot + 1, `d4` = PlList index, `a2` = team, `a4 = PlList`.
- Out: Z clear on success (`PlList[d4]` written), Z set on failure (`d1 = 0`).
- Steps:
  1. `d1 = d0`. `w = team.$66[2*(d0-1)]`.
  2. Fail if `w > 0`, `w == -3` or `w == -4`.
  3. Fail if `d1` already appears in `PlList[0..5]`.
  4. Otherwise `PlList[d4] = d1` and return with Z clear (from the `move.b` of a non-zero value).
- Quirk: `d0 = 0` (empty line slot) reads `team.$64`, the last energy word. If that passes, it stores 0 in `PlList[d4]`.

### Setplass (L51533), table _alist (L51542)
- `d0 = $34`. If negative: return. Otherwise `assreplace(_alist[$34])`.
- `_alist`: `$0E, 2, 2, 3, 5, 3, 5, $FF`.
  - pos 0 → `assgoaliecpu` (`$E`)
  - 1, 2 → `assdefd` (2)
  - 3 → `asswingd` (3)
  - 4 → `asscenterd` (5)
  - 5 → `asswingd` (3)
  - 6 → `asscenterd` (5)
- Assignment numbers (`asstab` L56671): 0 `$15464`, 1 assdefo, 2 assdefd, 3 asswingd, 4 asswingo, 5 asscenterd, 6 asscentero, 7 assscore, 8 assstanley, 9 assben, A assepen, B assbench, C asspenalty, D assdopen, E assgoaliecpu, F assgoalietopuck, 10 asspuckc, 11 assnearest, 12 assshoot, 13 asspassrec, 14 assfight, 15 assfwatch, 16 assfaceoff, 17 assfaceoffpl, 18 pucknorm, 19 puckshadow, 1A puckunflip, 1B puckfaceoff, 1C puckfaceoff2, 1D assgoaliectrl, 1E puckshootout, 1F puckpenshot, 20 assgoaliebreakwait, 21 chkpuckc, 22 assbreakaway, 23 assonetimer.

### forcepldata (L51446)
- Purpose: apply `newpos`/`newpnum` instantly, with no skating on or off. Used at faceoffs: `puckfaceoff2` L42109-42115 runs `ResetBench`, then `SetPersonel` + `forcepldata` for each team.
- Steps, for the team's 6 structs:
  1. `d0 = sext(newpos)`.
  2. If `$34 == 0` and `d0 != 0`: set `SCnum = $F`, call `nullsub_2` (`rts`), restore SCnum. No effect.
  3. `$34 = d0`. If `d0 < 0`, go to step 6.
  4. `Setplass`. If `$34 == 4`, also `assinsert($11 assnearest)`.
  5. `d3 = newpnum` (0-255). `team.$66[2*d3] = -1` (on ice). `setplayer(d3)`. This loads ratings and inserts `assepen`/`assben` per the old status; status -1 inserts nothing.
  6. `newpnum = newpos = $FF`.

### ResetBench (L51490)
- Purpose: at faceoffs/intermission, put everyone who is not in the box on the bench, and recount `PBnum`.
- Steps:
  1. `PBnum = 0`.
  2. For home (`d1 = $10`, `a0 = $C6CE`), then away (`d1 = 1`, `a0 = $CA32`), for slot `j = 25..0` (`d0 = 2j`, from `$32` down by 2):
     1. `PBnum += d1`.
     2. `w = a0.$66[2j]`.
     3. If `w <= 0`:
        - `PBnum -= d1`.
        - If `w` is not -3 or -4: `w = -2` (bench).
     4. Else (`w > 0`): if bit 4 of the **high byte** of `w` (word bit 12) is set and `(w & $7FF) == 0`: `PBnum -= d1`. Players with `w > 0` keep their status.
- Quirk: the listing comments swap the -3/-4 labels. The code compares `$FFFD` and `$FFFC`.

### check4bench (L37838)
- Purpose: called at the top of the AI assignments every loop. Starts a pending line change for this struct.
- Return trick: when it acts, it does `addq #4,sp`, which drops the caller's return, so the AI assignment does not run on that loop.
- Steps:
  1. Return if any of these holds:
     - `BA_PS_flags` bit 2
     - `pfjoycon` (a controlled player is never auto-benched)
     - `$63` bit 4 (penalized)
     - `newpos < 0` and `newpnum < 0` (nothing pending)
  2. If `newpnum == pnum` (same player stays):
     1. Drop the caller's return.
     2. Clear `$63` bit 2 and `pfnc`.
     3. `newpnum = newpos = $FF`.
     4. `d0 = $34`. Test `newpos`, which was just set to `$FF`, so the test is always negative.
     5. `jmp Setplass` with the **old** position.
     - **Bug (port as-is):** the position update path `loc_C700` is unreachable. A player who stays on but is listed at a new position keeps his old `$34`.
  3. Else:
     - If the current assignment is `$B` (`assbench`) or the player carries the puck: return.
     - Otherwise drop the caller's return, set `$63` bit 2 (unavailable), `temp1 $40 = 0`, then `assreplace($B assbench)`.

### assbench (L37886) — assignment $B
- Purpose: skate to the bench and hop off. Then the incoming player is loaded into this struct.
- Steps:
  1. If `pfalock`: return. If `temp1 == $64`: go to `_done`.
  2. `check4bench`. It returns normally here: the current assignment is `$B`. If `newpnum == pnum` again, it cancels and `jmp Setplass` instead.
  3. If `$63` bit 4 (penalized meanwhile): `assexit`.
  4. If `pfna` (test-and-clear): `temp2 $42 = 8`, `temp4 $46 = -$50` (home) or `+$50` (away), `temp3 $44 = -$88 - 8 = -144`, `temp1 = 0`.
  5. If `newpnum == pnum`: `_nobench` (clear `$63` bit 2, then `_nobench2`).
  6. `temp1 -= d7`. If `temp1 >= 0`: go to `_nodec`.
  7. `temp1 += 8`.
  8. If `|y - temp4| > 40` (`$28`), or `x - temp3 > 32` (`$20`): go to `_nodec`.
  9. Hop sequence:
     1. `SetSPA($50C)`, or `SetSPA($0002)` for a goalie (`$34 == 0`). Set `pfnc`.
     2. If `$54.w != 4`: `$54.w = ($54.w + 1) & 7`.
     3. `Yvel = 0`, `Xvel = $F800`.
     4. If `x - temp3 > 16`: return.
     5. `Xvel = 0`. If `$54.w != 4`: return.
     6. `Xvel = $F800`, `$54.w = 2`, `SetSPA($FAC)` (board hop), set `pfalock`, `temp1 = $64`. Return.
  10. `_nodec`: if `pfnc`: return. Otherwise `skateto(temp3, temp4, a0 = $E594 EvadePC)`.
  11. `_done` (after the hop anim ends):
      1. `frame $06 = 0` (hidden).
      2. `team.$66[2*pnum] = -2` (bench).
      3. `d3 = newpnum`.
      4. `_nobench2`: `$34 = sext(newpos)`, `Setplass`, `newpnum = newpos = $FF`.
      5. `jmp setplayer(d3)`. Loads the new roster player into this struct. Because his status was -2 he gets `assben`, or `assepen` if `>= 0`. His status becomes -1.

### assben (L37993) — assignment $9
- Purpose: hop onto the ice from the bench.
- Steps:
  1. If `pfalock`: return.
  2. If `pfna` (test-and-clear):
     - `Xvel = Yvel = 0`.
     - `d0 = SCnum - 6`; if `d0 >= 0`, `d0 += 1`. `y.w = d0 * $E`: home SCnum 0-5 gives -84..-14, away 6-11 gives 14..84.
     - `x.w = -$88`.
     - `$54.w = 2`. Set `pfalock`. `SetSPA($F6E)` (board hop). Return.
  3. Else:
     - `$54.w = 4`.
     - Clear `pfnc`, `$63` bit 5 and `$63` bit 2.
     - `SPA = 0`. `Xvel = $1000`.
     - `assexit` (`assnum = (assnum + 1) & 7`, set `pfna`).

### asspenalty (L38026) — assignment $C
- Purpose: skate to the penalty box and hop in.
- Steps:
  1. If `pfalock`: return.
  2. If `pfna` (test-and-clear):
     1. Set `$63` bit 2.
     2. `_clrplayer`: if `pfjoycon`, `d4 = 0` if `SCnum == c1playernum`, else `d4 = 2`, then `changeplayer` (`bsr`, returns here).
     3. `d4 = -2`; `sub_C656`.
     4. `temp2 = 8`.
     5. `n` = home count (`PBnum >> 4`) with `d0 = -$B`, or away count (`PBnum & $F`) with `d0 = +$B`.
     6. `n = min(n & $F, 2)` (unsigned), then `+3`.
     7. `temp4 = d0 * n` (±33, ±44, ±55).
     8. `temp3 = $88`. `temp1 = 0`. Set `$63` bit 5. `$4E = $50 = 0`.
  3. `dy = y - temp4`. If `dy > $C` or `dy < -$C`: `_st`. `dx = x - temp3`. If `dx < -$18` (-24): `_st`.
  4. `temp1 -= d7`. If `temp1 >= 0`: return. Otherwise `temp1 += 8`.
  5. Set `pfnc`. `SetSPA($50C)`. `d2 = 6` if `$76 == 0`, else `2`.
  6. If `$54.w != d2`: `$54.w = ($54.w + 1) & 7`.
  7. `Yvel = 0`, `Xvel = $1000`. If `dx < -8`: return.
  8. `Xvel = 0`. If `$54.w != d2`: return.
  9. Set `pfalock`, `$54.w = 2`, `SetSPA($F6E)`, clear `$63` bit 4, `assreplace($D assdopen)`.
  10. `_st`: `skateto(temp3, temp4, a0 = rtss2)` (no extra routine).
- Quirks:
  - `_clrplayer` picks `d4 = 2` for any controlled player that is not pad 1's, including pad 3/4 players.
  - `chgplayer`'s fallback `d6` is this player's SCnum, so with no candidate pad 2 could be handed this player.

### assdopen (L38119) — assignment $D
- Purpose: the player is now in the box.
- Steps:
  1. If `pfalock`: return.
  2. `PBnum += $10` (home) or `1` (away).
  3. `st $34` writes the **high byte only**, so `$34 = $FF00 | old position` (negative).
  4. `frame = 0`.
  - From now on `updateplayers` skips the struct (`$34 < 0`).

### assepen (L38135) — assignment $A
- Purpose: come out of the box.
- Steps:
  1. If `pfalock`: return.
  2. If `pfna` (test-and-clear):
     - Set `pfnc` and `$63` bit 2.
     - `PBnum -= $10` (home) or `1` (away).
     - `y.w = -60` (home) or `+60` (away). `Xvel = Yvel = 0`. `x.w = $86` (134).
     - `$54.w = 2`. Set `pfalock`. `SetSPA($FAC)`. `jmp SprSort`.
  3. Else:
     - `$54.w = 4`. `newpnum = newpos = $FF`.
     - Clear `pfjoycon` (!), `pfnc`, `$63` bit 5, `$63` bit 2.
     - `Xvel = $F000`. `assexit`.

### getlinee (L47394)
- Purpose: average energy of line `d0` for team `a2` (menu bars, `CompLine`).
- Steps:
  1. `a1 = team + $16A + 8*d0`. Sum and count start at 0.
  2. For `i = tmap-1 .. 0` with `p = priolist[i]`, skipping `p == 0`:
     - `v = a1[p]`.
     - `sum += word team.$30[2*v]`, which is `energy[v-1]`.
     - `count += 1`.
  3. `d0.l = divu(sum, count)`: low word = average, high word = remainder.
- Quirks:
  - Always uses the with-goalie `priolist`.
  - An empty slot (`v = 0`) adds the word at `team.$30` (flags byte plus the next byte).
  - `count == 0` would divide by zero (not reachable with tmap >= 2).

## 8. Quirks (all: port as-is)
1. **B+C together:** a C press with the B ignored, its release included (lockout).
2. **Direction 9 never comes from the pad.** It is `skateto`'s "arrived" code.
3. **Unrotated `word_FFBF12`.** In horizontal mode, paths that read it use the unrotated direction.
4. **Unscaled timers.** `word_FFD412` counts down once per processed object (up to 16 per loop). The B counter (`$11`) and A timer (`$0F`) count `doinput` calls, not vblanks.
5. **A held when the puck arrives.** If the A timer is already 0, the flip pass fires at once (plus the line menu).
6. **Dead goalie C-hold.** `$63` bit 7 is never set, so the goalie "C held" branch is dead.
7. **Dead goalie save math.** The manual-goalie save prediction (`sub_B5D8`, the `sroot` scaling, `cmpi`s with no branch) is computed and thrown away. The table copy at `$B602` is unreferenced.
8. **Never-set bit.** `word_FFC2F6` bit 6 is tested in 4 places and never set.
9. **`check4bench`.** A player who stays on with a new position keeps his old position.
10. **`SetPersonel` pass 2** can run past the team's 6 structs in a corner case, or use a stale `a0`.
11. **`assdopen`** uses `st` (byte), so the position becomes `$FFxx`.
12. **`restorep1`** indexes the auto-goalie flags by team, while `doinput` indexes them by pad. Its PS/shootout goalie case stores SCnum 0 or 6 without `pfjoycon`.
13. **`chgplayer`** leaves `d6` uninitialized. Ties go to the later struct.
14. **Unused swap.** `word_FFBF0A..10` are swapped for pads 3/4 but never read.
15. **Opposite directions.** U+D gives U, U+D+L gives D+L, L+R gives R (vblank cleanup).
16. **`assepen`** clears `pfjoycon`.

## 9. UNRESOLVED
- **Animation names.** `$F6E` and `$FAC` are the two board-hop animations: `$F6E` in `assben` and `asspenalty`, `$FAC` in `assbench` and `assepen`. Which visual is which is not named in the listing. `SetSPA($0002)` for a goalie in `assbench` is quoted as-is; it was not checked against the SPA table.
- **`sflags` bit 7.** "Horizontal mode" is honored here, but I did not confirm when 94 gameplay enables it. `SetHor`/`ClrHor` exist; `puckfaceoff` clears it before the line menu.
- **Penalty box status format.** In `tmpdst` (`> 0`), word bit 12 and the low 11 bits are only interpreted from `ResetBench`. The penalty-timer code that writes them was not read.
- **Line-menu row order.** A on top is inferred from `printy` decreasing as rows go C → A. `Framer`/`box` drawing was not traced.
- **Flip-pass targets.** `sub_F67E4` and `sub_F6778` (L958922-959010) belong to the passing spec. Their tables (`word_F68DE`, `word_F68FE`, `word_F691E`, 8 (x,y) pairs each) were seen but not specced here.
- **`$34` of the puck, nets and shadow** (objects 12-15). It decides whether `updateplayers` visits them (and so how fast `word_FFD412` drains). Not checked.
