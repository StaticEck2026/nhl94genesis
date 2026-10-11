# NHL '94 (Genesis) behavior spec: assignment framework and positional skater AI

Source: `lst/nhl94.bin.lst` (line numbers are listing lines, `Lnnnnn`). ROM addresses are given as `$xxxxx` where they were verified against `lst/nhl94.bin`.
Coordinates are rink coordinates (origin center ice, +X right, +Y toward the top goal). Directions 0-7 come from `vtoa` (0 = +Y, clockwise, 8 = zero vector).

---

## 1. Overview: how the pieces fit

1. Every game loop, `updateplayers` (L35329) walks the 16 sort objects. For each object with `position($34) >= 0`, it does save old pos, drag, move, Z, then (if this object is the one a controller drives) `doinput`, and then **always** the object's current assignment:
   `asstab[ asslist[assnum] ]` (L35666-35672), with `a2` = own team struct and `a1` = other team struct (`loadTeamStruct`).
2. An object's assignments are an 8-entry circular stack (`asslist`, bytes `$38..$3F`) indexed by `assnum` (`$36`). `assinsert` pushes a new assignment above the current one, `assexit` pops back to the one below, and `assreplace` overwrites the current one. Each of them sets `pfna` (`pflags` bit 1). The assignment routine sees `pfna` on its next call, clears it, and runs its init code.
3. Each skater's base assignment comes from its position (`Setplass` and `_alist`): D starts on `assdefd`, wingers on `asswingd`, the C on `asscenterd`, and the goalie on `assgoaliecpu`. Each positional routine checks, on a reaction timer, whether its team has the puck. It then swaps itself (`assreplace`) between the defensive and offensive variant: `assdefd`<->`assdefo`, `asswingd`<->`asswingo`, `asscenterd`<->`asscentero`.
4. Each team keeps one extra "puck chaser" assignment, `assnearest`, inserted above the base assignment. The C gets it at each faceoff (`forcepldata`). On its reaction timer, the holder looks for the teammate nearest the predicted puck. When that is someone else, it hands `assnearest` to him (`assinsert` on him, `assexit` on itself). When the holder becomes the puck carrier, `asspuckc` is inserted above it.
5. All positional routines pick a target point `(d0,d1)` and call `skateto`. `assnearest` uses `skatetopuck` or `skateto`. These convert the target into a virtual stick direction 0-7, 8 (glide) or 9 (stop), cached in `temp2` low byte and re-aimed every 12 frames (`skateto`) or 10 frames (`skatetopuck`). Both avoid the nets (`avdgoal`) and optionally sidestep the puck carrier (`EvadePC`). Every frame they call `doplayeracc(dir)`, which is already ported.
6. `check4check` (after `assdefd` and `assnearest`) randomly throws a body check (`burst`) or a hold (`Acheck`) at an opponent in front of the player.
7. `setSlotBit` (called once per `DoGameFrame`, **after** `updateplayers`) sets the global "puck carrier is in the slot" bit. The AI reads it on the next loop: it halves defensive reaction timers, gives a leg-speed boost, makes checks more likely and forces holds.
8. Celebrations: `assscore` after goals or at the end of a game, and `assstanley` for the cup winner.

### Globals used (RAM unless noted)

| Name | Address | Use here |
|---|---|---|
| `SortCords` | `$FFB04A` | 16 x 128-byte object structs. Home skaters are SCnum 0-5 (`SortCords`), away are 6-11 (`SortCords+$300`). |
| `puckx/pucky/puckvx/puckvy` | puck struct (`SortCords+14*$80`) `$00/$14/$28/$2A` | puck position/velocity. `move.b (puckvx)` reads the **high byte** of the velocity word. |
| `puckc` | `$FFB7AA` (puck struct `$60`) | puck carrier SCnum, negative = none. |
| `puck_pflags2` | puck struct `$63` | bit 0 tested by `skateto` (IDA: pf2fight). |
| `gmode` | `$FFC2EA` | bit 0 gmclock (play stopped), bit 5 offside rule on. |
| `sflags2` | | bit 2 "do not record replay", bit 5 power play active, bit 6 power-play team (0 home / 1 away). |
| `word_FFC2F8` (byte at `$FFC2F8`) | | **bit 5 = slot bit** (puck carrier in his offensive slot). |
| `word_FFC2F6` | | bit 2 = "`breakaway` ran" flag (set by `breakaway` L39775, consumed by `assnearest`/`asspuckc`). |
| `word_FFC2FA` | | bit 0 = shootout mode. |
| `byte_FFC2FC` | | bit 6 = crowd meter >= crowd record, recomputed at the top of every `updateplayers`. |
| `byte_FFC2FE` | | bit 1 is set unconditionally every `updateplayers` (`set_bit1_C2FE` L975179 is `bra _set`). |
| `BA_PS_flags` | | bit 2 (breakaway/penalty-shot mode; "cleared on faceoffs"), bit 5. |
| `TempLegSpd` | `$FFBF1E` (byte) | saved `legspd` during the slot boost. |
| `OptPen` | word | penalties option (non-zero = on). |
| `RNGseed` | long | `randomd0` state. |
| `VDP_CNTR` | `$C00008` (hardware HV counter) | read as a cheap random number. |
| `Hpos`, `Vpos` | words | camera center in rink coords (Hpos clamped -60..60, Vpos -200..256). |
| `xc1`, `yc1` | words | camera "scroll lock" point (set to the injured player's position on injury, L49504). |
| `shotplayer` | word | SCnum of the last shooter (scorer for `assscore`). |
| `word_FFDED0` | word | shootout replay-stop countdown (set to `$60` at L970651). |
| `CwdExciteLvl`, `crowdlevel` | words | crowd excitement. |
| Team structs | home `$FFC6CE` (`HmShots`), away `$FFCA32` (= home + `$364`) | `a2` = own, `a1` = other. Offsets: `$22` word = address of the team's first sort object (`tmsort`); `$26` word = goalie pulled when negative (`ReadGoaliePulled`); `$2A` long = squared distance of the team's nearest eligible skater to the predicted puck (written by `assnearest`); `$30` byte = team flags (bit 4 = team offside, bit 2 = see UNRESOLVED); `$358` word = breakaway attempts stat. |

Per-object fields used (beyond the preamble list): `$75` = **checking rating** ("Chk", max `$1E` = 30). `$63` bit 2 is used as **"unavailable"** in 94 (set by `check4bench`, `asspenalty` and injuries). The 93 equate list calls bit 2 `pf2dw` and bit 4 `pf2unav`, but every 94 site in scope uses bit 2. `$63` bit 4 is "player has a penalty pending" in 94 (L45993, L48809). `$64` bit 1 = breakaway, bit 3 = one-timer in progress.

Timer/temp usage by the positional routines:
- `temp1` (`$40`): only the **high byte** `$40` is used, as a signed byte. It is the reaction timer, counted down by `d7` and reloaded from `aioff($6A)` or `aidef($6B)`. `assscore` uses all of `temp1` as a word.
- `temp2` (`$42`): **high byte `$42`** = re-aim countdown for `skateto`/`skatetopuck`. **Low byte `$43`** = cached stick direction. Init `move.w #8,$42` gives hi = 0 and lo = 8.
- `temp3` (`$44`), `temp4` (`$46`): stored target X/Y (or the `assnearest` chase timer in `temp3`).
- `temp5` (`$48`): last zone index (`asswingo`/`asscentero`). Init uses `st $48(a3)`, which sets only the **high byte** to `$FF`, so the word can never equal 0/8/16/24.

### Tables in this spec
`asstab` (sec. 2.3), `_alist` (sec. 2.5), `asswingo _dedata` and `asscentero _dedata` (sec. 5), `Hotlist` (sec. 4.5, used by `GetHot`). `assdefo`, `assdefd`, `asswingd` and `asscenterd` have no data table; their constants are inline (summarized in sec. 9).

---

## 2. Assignment framework

### 2.1 updateplayers assignment call (L35666-35672)
- Purpose: dispatch the current assignment for object `a3`.
- Context: by this point `d6` = SCnum and `d7` = vblanks since the last loop. Objects with `position($34) < 0` skip the whole block, including the assignment call (`_top2: tst.w $34(a3); bmi _nf1`). Controlled players (`c1playernum`..`c4playernum`) had `doinput` called just before.
- Logic:
  1. `d0 = assnum ($36)` (word); `d1 = asslist[d0]` = byte at `$38 + d0` (zero-extended).
  2. `a0 = asstab[d1]` (long table, index * 4).
  3. `loadTeamStruct` (L47539): `a2 = $FFC6CE` (home), `a1 = a2+$364` (away). If `pflags` bit 6 (pfteam) is set, swap them. So **a2 = own team, a1 = other team**.
  4. `jsr (a0)`.
  5. After return: clear `Wallcos($4E)` and `Wallsin($50)`. If the position changed vs old, call `checkcoll`. Then impact decay (`impact -= 2*d7`, floored at 0; `limpact = impact`).
- Registers at the call (assignment code relies on these): `a3` = object, `a2`/`a1` = team structs, `d7` = elapsed frames, `d6` = SCnum. `d2` is stale. In the normal path it is the drag shift left by updateplayers: 6, or 9 if `pfdoff`, set only when `Zpos == 0` (see the `assnearest` quirk).

### 2.2 asslist / assnum semantics
- `assnum` (`$36`, word) always holds 0..7. `asslist` = 8 bytes at `$38..$3F`. The current assignment is `asslist[assnum]`.
- Initial state: `defaultsprites2` (L53407) clears the struct (assnum = 0) and loads `asslist[0]` from its sprite init list. Skaters get their positional assignment through `Setplass`.
- The stack grows **downward** (`assinsert` decrements `assnum`) and wraps modulo 8. There is no overflow check: a 9th insert silently overwrites the oldest entry.

### assexit (L43192)
- Purpose: leave the current assignment and resume the one below it.
- Logic: `assnum = (assnum + 1) & 7`; `bset #1,$62(a3)` (pfna); `rts`. The `asslist` entry is not cleared.

### assinsert (L43202)
- Purpose: push assignment `d0.b` on top of the current one.
- Logic: `assnum = (assnum - 1) & 7`, then **falls through into `assreplace`**: `asslist[assnum] = d0.b`; set pfna; `rts`.

### assreplace (L43210)
- Purpose: overwrite the current assignment with `d0.b`.
- Logic: save `d1`; `asslist[assnum] = d0.b`; `bset #1,$62(a3)`; restore `d1`; `rts`. Callers often use it as a tail jump (`bne.w assreplace`, `bra.w assreplace`), so the calling assignment ends this frame.

### 2.3 asstab (L56671, ROM `$18D7C`): full dump
36 long entries (index = asslist byte). Entry 36 onward is `PenaltyList`, which is not part of the table.

| idx | hex | routine | ROM | listing line |
|---|---|---|---|---|
| 0 | $00 | `rtss2` (a bare `rts`; null assignment) | $15464 | L50810 |
| 1 | $01 | assdefo | $0CD00 | L38375 |
| 2 | $02 | assdefd | $0CDE0 | L38447 |
| 3 | $03 | asswingd | $0CF9A | L38591 |
| 4 | $04 | asswingo | $0D09C | L38682 |
| 5 | $05 | asscenterd | $0D1E8 | L38800 |
| 6 | $06 | asscentero | $0D294 | L38856 |
| 7 | $07 | assscore | $0CC4E | L38315 |
| 8 | $08 | assstanley | $0CBFA | L38287 |
| 9 | $09 | assben | $0C882 | L37993 |
| 10 | $0A | assepen | $0CA50 | L38135 |
| 11 | $0B | assbench | $0C710 | L37886 |
| 12 | $0C | asspenalty | $0C8F0 | L38026 |
| 13 | $0D | assdopen | $0CA2A | L38119 |
| 14 | $0E | assgoaliecpu | $0D51C | L39072 |
| 15 | $0F | assgoalietopuck | $0DD2E | L39731 |
| 16 | $10 | asspuckc | $0DF18 | L39901 |
| 17 | $11 | assnearest | $0E6F4 | L40574 |
| 18 | $12 | assshoot | $0EC82 | L41029 |
| 19 | $13 | asspassrec | $0EB84 | L40938 |
| 20 | $14 | assfight (`rts`) | $0CBE0 | L38266 |
| 21 | $15 | assfwatch (`rts`) | $0CBE2 | L38269 |
| 22 | $16 | assfaceoff | $0CB3A | L38206 |
| 23 | $17 | assfaceoffpl | $0CB50 | L38218 |
| 24 | $18 | pucknorm | $0FF0C | L42526 |
| 25 | $19 | puckshadow | $102EC | L42862 |
| 26 | $1A | puckunflip | $102A8 | L42831 |
| 27 | $1B | puckfaceoff | $0F3E4 | L41627 |
| 28 | $1C | puckfaceoff2 | $0F88E | L42031 |
| 29 | $1D | assgoaliectrl | $0D3C6 | L38963 |
| 30 | $1E | puckshootout | $0ECB6 | L41046 |
| 31 | $1F | puckpenshot | $0EF92 | L41276 |
| 32 | $20 | assgoaliebreakwait | $0CAE0 | L38175 |
| 33 | $21 | chkpuckc | $0DEEE | L39886 |
| 34 | $22 | assbreakaway | $0E6CE | L40557 |
| 35 | $23 | assonetimer | $F693E | L959091 |

Note: the code comment "#$18 ; #pucknothing" at L30089 refers to index `$18` = `pucknorm` in 94.

### 2.4 Who changes assignments (sites relevant to skater AI)
- `Setplass` (L51533): `assreplace(_alist[position])`. Called by `check4bench`, `forcepldata` (faceoffs), penalty shot/shootout setup and `sub_FEFF0` (one-timer cleanup).
- `forcepldata` (L51446, faceoffs; once per team): for each of the 6 objects, set `position = newpos` and run `Setplass`. If `position == 4` (C), also `assinsert($11 assnearest)`.
- Positional routines swap themselves: `assdefo`->2, `assdefd`->1, `asswingd`->4, `asswingo`->3, `asscenterd`->6, `asscentero`->5.
- `check4bench` -> `assreplace($0B assbench)`.
- `assnearest`: hands itself to a teammate (`assinsert($11)` on the teammate, `assexit` on itself). On the carrier it calls `assinsert($10 asspuckc)`, and it can `assreplace($22 assbreakaway)`. `assbreakaway` -> `assreplace($11)` when not the carrier.
- `passto` (L37074): `assinsert($13 asspassrec)` on the pass recipient.
- `doinput` (sec. 2.6): `assreplace($23 assonetimer)`.
- `setass` (L49965, from `checkgoal`): after a goal (not in shootout mode, `word_FFC2FA` bit 0 clear), each skater of the scoring team (`a2`) with `position > 0` and not fighting (`$63` bit 0 clear) gets: clear `pfnc` (`$62` bit 2); if `$64` bit 3 (one-timer) was set, clear it and call `sub_FEFF0`; then `assinsert(7 assscore)`.
- `clockcont` (L30074, period clock hits 0): if `gsp >= 2` (end of game) and the score is not tied, each winning-team object with `position > 0` gets `assinsert(d0)`. `d0` is 7 (`assscore`), except in the Stanley Cup clinch case: `gamelevel == 3`, and either `bosgames == 7` or the winning side's stored series-win word in the current `gsstruct` entry (`4(a0,d3)`, `gspotwins`/`gspobwins` chosen by the flipped flag and by who won) equals 3. There `d0 = 8` for the **first** eligible player only, because `move.l #7,d0` executes right after the first `assinsert` (L30133). Exactly one player gets `assstanley` and the rest get `assscore`. In the cup case all 12 skater objects first get `pfjoycon` cleared.

### 2.5 Setplass `_alist` (L51542): full dump
`Setplass`: if `position < 0` -> `rts` (via `rtss2`). Else `assreplace(_alist[position])`.

| position | byte | assignment |
|---|---|---|
| 0 goalie | $0E | assgoaliecpu |
| 1 L.def | $02 | assdefd |
| 2 R.def | $02 | assdefd |
| 3 L.wing | $03 | asswingd |
| 4 center | $05 | asscenterd |
| 5 R.wing | $03 | asswingd |
| 6 (unused?) | $05 | asscenterd |
| 7 | $FF | (terminator/pad) |

### 2.6 doinput and non-controlled teammates (L35886)
`doinput` only drives players with `pfjoycon` set. It returns at once (`rtss15`) when `pfjoycon` is clear, so AI teammates are never steered by `doinput`. It touches teammates' assignments in three places:
1. **One-timer setup for the pass receiver** (L35958-35985). The check runs before the controlled player's normal input handling. The conditions are: this controlled player is `lastplayer` (the passer), `passplayer >= 0`, `onetimerplayer < 0`, and the C button is newly pressed (`d1` bit 5). If so, set `a3 = SortCords + passplayer*$80` (the receiver). The receiver must also have `position != 0`, `sub_F6C44` must return non-zero (one-timer feasibility, not in scope), the receiver must have `pfjoycon` clear and `$64` bit 3 clear. When everything holds: `inputjoy = d4` (pad index), `TmpJoyPuckCarrier = joypuckcarrier`, `assreplace($23 assonetimer)` **on the receiver**, then `rts` (no other input processed this frame). If any check fails, normal processing continues.
2. **One-timer for the controlled player himself** (`loc_B6BA`, L36372-36404, for a controlled non-carrier). If `$64` bit 3 is set, `rts`. If C is not newly pressed, `doplayeracc(stick)`. If C is pressed, he gets the one-timer only when `lastplayer` is not a goalie, he is `passplayer`, there is no puck carrier and `sub_F6C44 != 0`. Then `assreplace($23)` on `a3` itself. Otherwise the C press throws `burst` (body check).
3. **Passing**: `passmode` -> `passto` (L37074) does `exg a0,a3; assinsert($13 asspassrec); exg` on the recipient. If the passer is controlled and the recipient is not, `setc1player`/`setc2player` moves joystick control to the recipient (`$64` bit 6 set on the recipient).

`faceoffinput` (L36529) only reads `asslist[assnum]` to check for `$17` (assfaceoffpl) and writes nothing.

---

## 3. Shared helpers

### randomd0 (L44190)
- Returns `d0.w` in `0..range-1` (range = `d0.w` on entry). Preserves `d1`, `d2`.
- Logic: `seed = (seed * $BB40E62D + 1) mod 2^32`. The code computes this as `lo*$E62D + ((lo*$BB40 + hi*$E62D) & $FFFF) << 16`, which is the same value.
  `result = ( ((seed >> 8) & $FFFF) * range ) >> 16` (unsigned 16x16 multiply, upper word). `range = 0` returns 0.
### randomd0s (L44178)
- `randomd0(range*2) - range`, giving a value in `-range .. range-1`. `range*2` is `asl.w #1` (word).

### check4bench (L37838)
- Purpose: start line changes and position resets. Called by all six positional routines right after the gmclock test.
- Logic: return (`rts`) if any of: `BA_PS_flags` bit 2; `pfjoycon`; `$63` bit 4 (penalty pending). If `newpos($60).b < 0` **and** `newpnum($61).b < 0`, return.
  - If `newpnum == pnum($66)`: pop the caller's return address (`addq #4,sp`, so the calling assignment ends when this path returns). Clear `$63` bit 2 and `$62` bit 2 (pfnc). Set `newpnum = $FF` and `newpos = $FF`. Then `tst.b $60` is always negative because it was just set to `$FF`, so it always does `jmp Setplass` with the **unchanged** position. The `loc_C700` path (`position = newpos`) is dead code (quirk: port as-is).
  - Else (a different roster player is requested): return if the current assignment is already `$0B`, or if `a3` is `puckc`. Otherwise pop the caller's return address, set `$63` bit 2 (unavailable), `temp1 = 0`, and `assreplace($0B assbench)`.

### chkpk (L40159) / chkpk2 (L40168)
- `chkpk`: Z flag set = this player's team is killing a penalty. If `sflags2` bit 5 (power play) is clear, it returns Z clear. Otherwise it falls into `chkpk2`.
- `chkpk2`: `Z = Z(btst #6,sflags2) XOR Z(btst #6,pflags)`. Z is set when the power-play team bit differs from `pfteam`, which means a3's team is short-handed. Preserves `d0`, `d1`.

### ReadGoaliePulled (L975229)
- Uses a3's own team struct (`$FFC6CE` or `$FFCA32`) and does `tst.w $26(team)`. The N flag is set when the own goalie is pulled. Preserves `a1`.

### 3.1 Reaction-timer reload (shared pattern)
All six positional routines and `assnearest` do this:
```
if (pfna was set) { temp1.w = 0; temp2.w = 8; [asswingo/asscentero: temp5.hi = $FF] }
temp1.hi -= d7            (byte)
if (temp1.hi >= 0) goto NO_REEVAL      (bpl)
temp1.hi = rating          (assdefo, assnearest: aioff $6A; all others: aidef $6B)
[assdefo, assnearest only]  if (own goalie pulled) { temp1.hi -= 1; goto DONE }   // even from 0 -> $FF (-1)
if ((byte_FFC2FC & $40) && temp1.hi != 0) temp1.hi -= 1     // crowd record broken: faster reactions (both teams)
DONE: ... re-evaluate (assignment swap test) ...
```
With `d7 = 1`, re-evaluation happens every `rating+1` frames. A rating of 0 re-evaluates every frame. A reload value of -1 (goalie-pulled bonus applied to rating 0) is already negative, so the next frame re-evaluates as well.

"Same team" test used everywhere: `((puckc-6) XOR (SCnum-6)) < 0` (as words) means different teams.

---

## 4. Movement core

### skateto (L42953)
- Purpose: steer `a3` toward point `(d0,d1)`, re-aiming every 12 frames; produces the virtual stick direction for `doplayeracc`.
- Inputs: `d0/d1` target X/Y, `a0` = extra routine (`EvadePC` or a bare `rts`: `rtss2`, `rtss21`, `rtss11`), `d7`. Reads `temp2`, Xpos/Ypos/Xvel/Yvel, facedir, puck pos, `puck_pflags2`, `xc1/yc1`.
- Outputs: `temp2` hi/lo, possibly `facedir` high word. Tail-calls `doplayeracc` with the cached direction.
- Logic:
  1. `temp2.hi -= d7` (byte). If the result is `>= 0` (bpl), go to step 9.
  2. `temp2.hi += 12` (`addi.b #$C`).
  3. `(d0,d1) = avdgoal(d0,d1)`.
  4. `dx = d0 - (Xvel asr 8) - Xpos`; `dy = d1 - (Yvel asr 8) - Ypos` (words; `asr.w #8`).
  5. If `-12 <= dx <= 12` **and** `-12 <= dy <= 12` (signed, inclusive), then `dir = 9` (arrived/stop). Otherwise `dir = vtoa(dx,dy)`.
  6. `jsr (a0)` with `d0 = dir`. The routine may replace `d0`. `EvadePC` uses `d1`, `d2`.
  7. `temp2.lo = d0.b`.
  8. If `d0 > 7` (signed word, i.e. 8 or 9) **and** `(Xvel | Yvel) == 0`, turn one step toward the puck:
     - `(tx,ty) = (puckx,pucky)`. If `puck_pflags2` bit 0 is set, use `(xc1,yc1)` instead.
     - `t = vtoa(tx - Xpos, ty - Ypos)`; `diff = t - facedir.w`. If `diff == 0`, go to step 9.
     - `step = (((-diff) & 4) >> 1) - 1`, giving +1 or -1. `facedir.w = (facedir.w + step) & 7`. Only the high word of the 16.16 facedir is written.
  9. `d0 = temp2.lo` (zero-extended byte) -> `bra doplayeracc`.
- Direction codes into `doplayeracc` (already ported): 0-7 accelerate that way; 8 = no input (glide animation `$50C`, or `$A60` if skating backwards); 9 = brake (`dostop`) if moving, otherwise behave as 8.
- Notes: a new assignment sets `temp2 = 8` (hi = 0, lo = 8), so the first call re-aims immediately. Between re-aims, the cached direction (including 9) is re-sent every frame. When the target is reached the player stops and turns 45 degrees toward the puck on each re-aim.

### avdgoal (L43026)
- Purpose: bend the target so the straight path from the player does not cross a net. Called by `skateto` and `skatetopuck`.
- Inputs: `d0/d1` target, a3 position. Uses `d2,d3,d4` as scratch. Outputs: adjusted `d0/d1`, globals `deltax`, `deltay`.
- Constants actually used (the source comments `.xr=80 .yr=30 .ye=30 .gl=258` do not match the code): goal line `gl = $FE (254)`, half-width `xr = $50 (80)`, band `35`.
- Logic:
  1. `deltax = 0; deltay = 0`. If `position == 0` (goalie), return `d0/d1` unchanged.
  2. **Crossing x = 0 near a net (Y correction).** Only if `(Xpos XOR d0) < 0`, meaning the path crosses x = 0:
     `yc = Ypos + ((d1 - Ypos) * Xpos) / (Xpos - d0)` (`muls.w`, `divs.w` truncating toward zero, word results).
     - If `219 ($DB) <= yc <= 289 ($121)`: `ref = 324 ($144)` if `yc > 254`, `184 ($B8)` if `yc < 254`, and if `yc == 254` then `324` when `Ypos > 254` else `184`. `deltay = ref - yc`.
     - Else if `-289 ($FEDF) <= yc <= -219 ($FF25)`: `ref = -184 ($FF48)` if `yc > -254 ($FF02)`, `-324 ($FEBC)` if `yc < -254`, and if equal then `-184` when `Ypos > -254` else `-324`. `deltay = ref - yc`.
     - Otherwise no Y change.
  3. **Crossing a goal line near a net (X correction):** call `ch1` with `d3 = d1 - 254, d2 = Ypos - 254`, then `ch1` with `d3 = d1 + 254, d2 = Ypos + 254`.
  4. `d0 += deltax; d1 += deltay; rts`.
- No division overflow is possible: the operands have opposite signs, so the divisor magnitude is at least the factor magnitude. There is no divide by zero.

### ch1 (L43093) (inside avdgoal)
- Inputs: `d2` = Ypos - gy, `d3` = targetY - gy for goal-line `gy = +-254`.
- Logic: if `(d3 XOR d2) >= 0` (no crossing), return. Otherwise
  `xc = Xpos + ((d0 - Xpos) * d2) / (d2 - d3)` (muls/divs, truncating).
  If `xc > 80` or `xc < -80`, return. Else `ref = +80`, negated when `xc < 0` (or when `xc == 0` and `Xpos < 0`). `deltax = ref - xc`.
- Quirk: both calls write the same `deltax`, so if the path crosses both goal lines the second call (`y = -254`) wins.

### skatetopuckinit (L43123)
- Returns the predicted puck point:
  `d0 = puckx + ((puckvx high byte, signed) asr 1)` = `puckx + (puckvx >> 9)` (arithmetic shift)
  `d1 = pucky + (puckvy >> 9)`.

### skatetopuck (L43138)
- Purpose: chase the puck (the stick blade is aimed at the predicted puck). Ends with a poke/sweep check when close and facing it. Callers: `assnearest` (`_topuck`), `assgoalietopuck`.
- Logic:
  1. `(d0,d1) = skatetopuckinit()` (every call).
  2. `temp2.hi -= d7`. If `>= 0`, go to step 8.
  3. `temp2.hi += 10` (`$A`). `(d0,d1) = avdgoal(d0,d1)`.
  4. `(hx,hy) = GetHot(a3)` (stick hot spot of the current frame).
  5. `dx = sext8( (-hx) - (Xvel>>8) ) + d0 - Xpos`; `dy = sext8( (-hy) - (Yvel>>8) ) + d1 - Ypos`. The byte negate and byte subtract use the high byte of the velocity word, wrap at 8 bits, and are then sign-extended. `temp2.lo = vtoa(dx,dy)` (0-8, never 9).
  6. If `position == 0` (goalie), go to step 8.
  7. Sweep test:
     - `a = vtoa(puckvx, puckvy) XOR 4`. If `a == facedir.w`, go to step 8 (the puck is moving toward the player's face). A stationary puck gives `8^4 = 12`, which never matches.
     - `dx = puckx - Xpos, dy = pucky - Ypos`. If `vtoa(dx,dy) != facedir.w`, go to step 8.
     - `dist2 = dx*dx + dy*dy` (signed 16x16 products, long sum, compared **unsigned**). If `dist2 <= 900 ($384)`, go to step 8. If `dist2 <= 1444 ($5A4)`, `bra Sweepcheck` (L37296: set `pfalock`, `SetSPA($B24)`, return **without** calling doplayeracc this frame).
  8. `doplayeracc(temp2.lo)`.

### GetHot (L43282)
- Called as `move.l obj,-(sp); bsr GetHot`. The routine pops its argument. Returns `d0/d1` = stick hot-spot offset of `obj`'s current sprite frame; `a0/a1` are preserved.
- If `frame($06) <= 0`, returns (0,0). Otherwise `x = Hotlist[frame*2]`, `y = Hotlist[frame*2+1]` (signed bytes).
  `x = -x` if `attribute($04)` bit 3 (xflip) is set. **`y = -y` if attribute bit 4 is clear** (screen Y down vs rink Y up). In horizontal mode (`sflags` bit 7): swap, then negate the new `d1` (not needed for the port's vertical rink).

### 4.5 Hotlist (ROM `$A44C8`, L626116-L627791, 1676 bytes = 838 frames): full dump
Raw stored bytes `x,y` (signed), before GetHot's flips. Each row starts at the frame number shown.
```
  0: 8,5 -4,-20 -1,-24 -2,-28 -1,-25 1,-25 16,-8 23,-10 19,-8 21,-11 14,-4 17,3
 12: 21,3 21,2 21,3 18,3 14,6 17,14 17,10 19,11 17,10 2,16 1,20 4,15
 24: 4,20 0,20 -8,6 -13,11 -14,12 -17,14 -15,12 -13,3 -20,1 -14,3 -15,2 -13,3
 36: -14,-8 -15,-7 -14,-7 -15,-8 -13,-9 1,-13 1,-11 1,-12 0,-12 1,-13 11,-6 12,-7
 48: 12,-6 10,-6 10,-7 17,0 22,2 22,1 20,1 18,1 11,12 13,14 12,11 10,12
 60: 11,11 0,13 1,15 1,12 0,14 2,12 -9,11 -9,10 -10,9 -13,10 -11,10 -16,0
 72: -17,-1 -17,0 -16,2 -14,2 -9,-10 -12,-8 -10,-6 -9,-5 -10,-6 -6,-5 14,-5 20,0
 84: 18,6 9,6 -16,11 -24,-4 -22,-7 1,-7 15,-9 22,3 14,5 -2,7 -22,6 -22,-6
 96: -14,-14 -6,-12 -6,-12 -6,-12 -6,-12 -6,-12 -6,-12 14,-12 14,-12 14,-12 14,-12 14,-12
108: 14,-12 19,2 19,2 19,2 19,2 19,2 19,2 15,7 15,7 15,7 15,7 15,7
120: 15,7 8,14 8,14 8,14 6,11 8,14 8,14 -10,12 -10,12 -10,12 -10,12 -10,12
132: -10,12 -16,7 -17,7 -17,7 -17,7 -17,7 -17,7 -18,-4 -18,-4 -18,-4 -18,-4 -18,-4
144: -18,-4 -1,-19 -1,-19 16,-7 16,-7 17,-1 17,-1 11,8 11,8 -6,8 -6,8 -15,7
156: -15,7 -12,-5 -12,-5 -11,-9 -11,-9 -2,-19 -10,-16 -3,-16 17,-18 14,-11 6,-10 24,1
168: 24,-4 18,-3 11,8 15,3 14,4 -4,9 2,9 8,8 -18,4 -14,6 -8,6 -25,-2
180: -18,1 -15,-1 -21,-13 -15,-9 -14,-2 0,0 0,0 0,0 0,0 0,0 0,0 0,0
192: 0,0 0,0 0,0 0,0 0,0 0,0 0,0 0,0 0,0 12,-10 2,-13 19,-3
204: 16,-6 18,8 18,7 9,10 10,12 -14,9 -8,11 -18,1 -15,4 -13,-3 -18,-2 -8,-7
216: -9,-9 -2,-5 6,-5 7,-2 4,7 -1,9 -9,3 -12,1 -10,-5 -17,-1 -10,-5 25,2
228: 20,6 9,13 -8,12 -23,4 -16,7 -17,-4 -9,-8 27,-5 29,2 14,14 2,16 -22,5
240: -23,4 -15,-10 19,-10 30,-8 29,8 8,11 -28,7 -29,2 -24,-8 -21,0 -15,-1 15,-8
252: 12,-2 17,0 2,8 -12,7 -14,5 -8,-24 -10,-28 19,-7 23,-13 26,6 33,6 20,13
264: 32,13 9,16 7,26 -17,9 -26,17 -30,4 -36,1 -23,-8 -24,-11 0,0 12,7 2,31
276: 15,-13 0,0 5,3 -20,26 12,2 12,4 2,3 -32,-5 6,8 -3,4 -7,5 -26,-19
288: -1,8 0,0 0,0 1,-25 -14,5 -15,-3 -2,5 18,-24 -16,-7 -18,-2 -5,3 31,-1
300: 3,-4 -9,-8 3,3 28,20 2,-7 2,-20 -10,-21 -11,-24 -8,-18 12,-11 17,-22 18,-31
312: 18,-15 25,4 34,2 41,-7 29,-3 17,8 27,17 31,16 19,18 -3,14 -2,33 4,36
324: 2,31 -25,10 -27,21 -28,21 -21,21 -32,2 -39,4 -41,5 -27,6 -15,-4 -28,-12 -28,-15
336: -20,-16 12,-4 16,-1 13,7 8,7 -14,4 -20,0 -17,-1 -7,-11 13,-7 19,-1 25,5
348: 13,11 -7,11 -20,7 -19,0 -15,-6 0,0 6,-2 7,0 7,0 7,0 7,0 7,-1
360: 7,-1 7,-1 7,-1 7,-1 7,-1 7,-1 7,-1 7,-1 -9,-2 -22,-1 -32,-4 -24,-4
372: -24,-4 -24,-4 -24,-4 -24,-4 -24,-4 -20,6 -3,-2 -1,0 -29,2 2,5 2,2 -3,2
384: 0,0 0,0 0,0 0,0 0,0 0,0 0,0 0,0 0,0 0,0 0,0 0,0
396: 0,0 0,0 0,0 0,0 0,0 0,0 0,0 0,0 0,0 0,0 0,0 0,-7
408: 7,-4 -6,-8 4,-6 11,1 1,-9 11,0 8,2 10,-9 11,4 1,5 3,3 1,6
420: -4,1 4,5 -7,7 -8,-2 -7,8 -10,4 -10,0 -10,2 -6,-1 -5,-6 -11,-5 2,-10
432: 3,-11 13,-9 13,-9 23,-1 23,-1 15,5 16,4 4,13 4,14 -16,10 -16,10 -22,3
444: -23,-2 -18,-8 -19,-9 4,-4 7,-1 -1,-3 10,0 5,5 -2,8 1,5 -10,-1 -12,3
456: -14,-4 -6,-4 7,-8 -1,-8 -10,-5 -1,-7 -1,-5 11,4 11,-8 -3,6 12,3 2,7
468: 2,5 -11,-1 -14,0 7,-14 -10,-3 19,-10 3,-13 21,-2 4,-13 8,8 13,-4 -9,5
480: 9,2 -19,5 4,5 -18,-8 -8,6 -12,-15 -13,-3 -2,-8 1,-7 7,-3 2,-5 17,-3
492: 15,-2 17,-3 16,-1 12,0 14,2 19,5 17,1 7,4 5,6 9,9 13,12 2,10
504: -1,11 -11,15 -8,11 -9,8 -3,8 -17,5 -15,7 -11,-2 -11,4 -17,3 -16,0 -10,-7
516: -9,-3 -13,-8 -14,-7 -1,-30 -1,-26 18,-21 16,-22 34,-5 25,-7 26,6 19,7 0,29
528: 1,22 -20,13 -19,10 -30,4 -24,-1 -21,-21 -18,-21 -20,-1 -20,-1 20,0 20,0 -1,-8
540: -1,-8 -1,-9 4,-8 4,-8 4,-8 10,-2 10,-2 10,-2 9,2 9,2 9,2 1,4
552: 1,4 1,4 -8,4 -7,5 -7,5 -10,1 -10,3 -10,3 -6,-4 -6,-4 -6,-4 0,0
564: 0,0 0,0 0,0 0,0 0,0 0,0 0,0 0,0 0,0 0,0 0,0 0,0
576: 0,0 -7,-5 6,-3 -1,-3 7,0 5,-3 5,2 6,-2 -3,2 7,1 -4,0 1,4
588: -6,-2 -7,1 -5,-2 -7,-1 -4,-5 0,-35 4,-26 15,-6 8,-11 15,-1 17,-9 15,4
600: 16,-5 -1,8 5,3 -13,5 -17,1 -19,1 -21,-10 -18,-12 -12,-17 0,-10 0,-9 0,-11
612: 8,-9 8,-9 8,-8 12,-2 13,-3 13,-3 10,6 10,6 10,5 0,11 1,10 1,10
624: -11,6 -11,6 -11,6 -12,-1 -12,-1 -20,-1 -12,-8 -14,-7 -13,-8 3,-2 3,-2 3,-2
636: 6,-2 -3,3 -3,3 -3,3 -3,3 2,3 2,3 2,3 2,3 2,2 1,2 -26,14
648: -26,14 -26,14 -26,14 -26,14 -26,14 0,0 0,0 0,0 0,0 0,0 9,-14 -9,-14
660: 12,-10 -6,-17 2,-9 6,-21 -7,-10 10,-15 -10,-15 10,-14 -9,-15 8,-9 -3,-18 2,-10
672: 7,-19 -12,-14 5,-7 9,-7 -6,-7 -9,-7 8,-5 13,-1 2,-9 0,-5 17,5 21,8
684: 15,-2 16,-1 7,6 8,9 17,0 22,-1 -8,6 -15,7 10,5 19,7 -12,4 -17,3
696: 0,8 -2,12 -8,-2 -12,-2 -16,4 -18,8 0,-8 -1,-6 -9,-1 -22,1 0,0 0,0
708: 0,0 0,0 0,0 0,0 0,0 0,0 -16,1 -17,-5 -17,-24 -12,-4 -5,-10 -2,-25
720: -4,-14 9,-14 16,-22 9,-8 15,0 23,-17 16,-2 14,5 14,-13 17,3 7,8 6,-18
732: 5,6 -9,6 -22,-23 -12,3 -18,0 -21,-26 -8,-6 -13,-6 -7,-32 25,-15 22,-7 35,-11
744: 30,-1 28,-2 -17,-22 -30,-25 -14,7 11,25 -23,-7 -37,-10 -35,-4 -26,1 -10,-26 -2,-29
756: -12,-27 -10,-16 14,-2 6,-1 9,4 6,8 -1,10 4,7 6,12 9,19 -19,-19 -16,-24
768: -18,-27 -25,-12 -6,-30 3,-34 -12,-26 -9,-17 23,-6 34,-9 33,-5 27,-4 -11,3 -24,-4
780: -27,-8 -32,3 -22,-6 -34,-10 -33,-5 -26,0 8,-25 1,-30 -11,-27 -10,-17 18,-19 17,-27
792: 13,-11 5,9 0,10 -5,8 5,12 9,19 -14,-5 -6,-2 -18,-11 -27,-12 -3,-9 -22,-7
804: -16,11 -19,5 -25,1 -19,5 -28,-4 5,-16 -19,-21 -19,5 -14,-21 -11,-25 -15,-5 -19,-8
816: -3,-9 22,-6 14,12 17,5 24,3 18,5 25,-3 17,-9 15,-3 -12,-35 28,-29 25,-10
828: 25,-28 20,-30 -17,-26 -5,-25 19,-23 27,-19 19,-11 -4,-6 -15,-6 -29,-18
```
(Verified byte-for-byte: listing `dc.b` values == ROM `$A44C8..$A4B53`.)

### EvadePC (L40442, ROM `$E594`)
- Purpose: the extra routine for `skateto`. When the player is about to run into the puck carrier, it overrides the stick direction to move away from him. Used by assdefo, assdefd (as `movea.l #$E594,a0`), asswingo and asscentero.
- Input `d0` = direction from skateto. Output `d0`. Scratch `d1,d2`.
- Logic:
  1. If `puckc < 0`, return `d0` unchanged.
  2. `ex = sext8( (Xvel>>8) - (puckvx>>8) )` (byte subtract of the velocity high bytes, wraps). `ex += Xpos - puckx`. If `ex > 40 ($28)` or `ex < -40`, return.
  3. Same for Y: `ey = sext8((Yvel>>8)-(puckvy>>8)) + Ypos - pucky`. If outside `[-40,40]`, return.
  4. `d0 = vtoa(Xpos - puckx, Ypos - pucky)` (directly away from the puck).
  5. If `gmode` bit 5 (offside rule on) is clear, return.
  6. `y = Ypos`, negated if `pfgoal` = 0 (normalized to attack +Y). `y -= 88 ($58)`. If `y > 10` or `y < -50` (i.e. normalized Ypos outside `38..98`, near the offensive blue line), return `d0`.
  7. Return `2` (+X) if `Xpos > puckx`, else `6` (-X). Near the blue line the player sidesteps instead of backing out over the line.
- Applies to **any** carrier, teammate or opponent.

### assnothing (L38275)
- Purpose: idle (whistle). Called by all positional routines when `gmode` bit 0 (gmclock) is set.
- Logic: if `pfalock` -> `rts`; if `pfjoycon` -> `rts`; else `doplayeracc(8)` (glide, no acceleration).

---

## 5. Positional routines: common prologue
- Callers: `updateplayers` via `asstab` (indices 1-6), once per loop per on-ice object.
- Inputs: a3 `pflags`/`pflags2`, `position($34)`, `SCnum($52)`, `aioff($6A)`/`aidef($6B)`, temp1-temp5, X/Y/vel; globals `puckc`, `puckx/pucky/puckvy`, `gmode`, `byte_FFC2FC`, `sflags2`; own team flags `$30(a2)`; opponents' structs (assdefd); `d7`.
- Outputs: temp1-temp5, `asslist` (via assreplace), `pfna`, then everything `skateto`/`doplayeracc` writes (`temp2`, facedir, velocity, SPA).
Every one of assdefo, assdefd, asswingd, asswingo, asscenterd and asscentero starts:
1. If `pfalock` (`$62` bit 5), `rts`.
2. If `gmode` bit 0 (clock stopped), `bra assnothing`.
3. `bsr check4bench` (may end the routine, see sec. 3).
4. If `pfjoycon` (`$62` bit 3), `rts`.
5. `bclr #1,$62` (pfna). If it was set: `temp1.w = 0`, `temp2.w = 8`, and for asswingo/asscentero also `st temp5.hi`.
6. Reaction timer (sec. 3.1). Not expired: jump to that routine's `_nodec` (movement only). Expired: reload and run the routine's swap test, then fall into the movement code (or `_de0` for wing/center offense).

Normalization used below: `N = +1` if `pfgoal` (`$62` bit 7) is set (team attacks the top goal), `N = -1` otherwise. "Normalized y" = `N*y`.

### assdefo (L38375): defenseman on offense (asstab 1)
- Timer rating: **aioff `$6A`**, with the goalie-pulled bonus.
- On timer expiry (swap test, `d0 = 2`):
  1. If own team offside (`$30(a2)` bit 4), `assreplace(2)`.
  2. `yn = N*pucky` (current position, no velocity). If `yn < 93 ($5D)` (signed), `assreplace(2)`.
  3. If `puckc < 0`, go to `_nodec`. If the carrier is on the other team, `assreplace(2)`.
- `_nodec` (every frame):
  1. `lane = +80 ($50)` if `position == 2` (RD), else `-80` (LD). `y = 98 ($62)`. If `N = -1`, negate both. (Normalized: RD at +80, LD at -80, y = 98.)
  2. If `(puckx XOR lane) >= 0` (puck on this D's X half, or `puckx == 0` with a positive lane), `x = puckx`. Else `x = lane + (puckx asr 1)`.
  3. `skateto(x, y, EvadePC)`.
- No `check4check`.

### assdefd (L38447): defenseman on defense (asstab 2)
- Timer rating: aidef `$6B` (crowd bonus only).
- On timer expiry:
  1. Swap test (`d0 = 1`): `yn = N*pucky`; `vn = N*(puckvy asr 6)`, clamped to `>= 0`; `p = yn + vn`. Swap to `assdefo` only if all of: `p >= 88 ($58)`; not team offside (`$30(a2)` bit 4 clear); `puckc >= 0`; **not** killing a penalty (`chkpk` Z clear); carrier on the same team. Then `assreplace(1)`.
  2. Compute the new target (`_de0`), stored in temp3/temp4:
     - `temp3 = +65 ($41)` if `position == 2` (RD), else `-65`.
     - `a0` = the opponents' first object: `SortCords+$300` if a3 is home (SCnum < 6), else `SortCords`. Loop over the 6 opponent objects. Skip any with `$63` bit 2 (unavailable) or `position < 0`. **Goalies are not skipped.**
     - If `N = +1` (defending the bottom goal), `best = +1000`. For each opponent: `v = Yvel` if `Yvel < 0` else 0; `py = (v asr 4) + Ypos`; if `py <= best`, then `best = py` (minimum Y, the deepest attacker toward the bottom goal). Then `best -= 50 ($32)`. If `best <= -190 ($FF42)`, `best = -220 ($FF24)`. `temp4 = best`. temp3 keeps its sign.
     - If `N = -1` (defending the top goal), `best = -1000 ($FC18)`. For each opponent: `v = Yvel` if `Yvel > 0` else 0; `py = (v asr 4) + Ypos`; if `py >= best`, then `best = py`. Then `best += 50`. If `best >= 190 ($BE)`, `best = 220 ($DC)`. `temp4 = best`. **`temp3 = -temp3`**.
     - In both cases, if `(puckx XOR temp3) < 0` (puck on the other X half), `temp3 = 0`.
- `_nodec` (every frame): `skateto(temp3, temp4, EvadePC [$E594])`, then **`bra check4check`**.
- Meaning: the D stays 50 px goal-side of the deepest opposing skater (velocity look-ahead toward his own goal only). Once that point is within 190 of center, he collapses to 220 (near the crease). Laterally he holds the +-65 lane, or the middle when the puck is on the far side. Normalized: RD +65, LD -65.
- Quirk: if every opponent is skipped, `temp4 = +-950` (off the rink toward the far end).

### asswingd (L38591): winger on defense (asstab 3)
- Timer rating: aidef `$6B`.
- On expiry: if `puckc >= 0` and the carrier is on the same team, `assreplace(4 asswingo)`.
- `_nodec` (every frame):
  1. `lane = +100 ($64)`, negated if `position == 5` (RW). `y = $9E (158)`.
  2. If `N = +1`: negate lane and y (`y = -158`). `d2 = -78 ($FFB2)`. Then:
     - If team offside: `y = -78`.
     - Else if `pucky < -78`: if `pucky > -264 ($FEF8)`, `y = -158`; else `y = -264`.
     - Else `y = pucky`.
  3. If `N = -1`: `d2 = 78 ($4E)`. Then:
     - If team offside: `y = 78`.
     - Else if `pucky > 78`: if `pucky < 264 ($108)`, `y = 158`; else `y = 264`.
     - Else `y = pucky`.
  4. `x = lane` if `(puckx XOR lane) < 0`, else `x = puckx`.
  5. `skateto(x, y, rts)` (no EvadePC).
- Normalized: RW lane +100, LW -100. Y tracks the puck while the puck is outside the own zone (normalized `y >= -78`). With the puck in the own zone, y = -158. With the puck at or behind the own goal line (`<= -264`), y = -264. When own team is offside, y = -78. No `check4check`.

### asswingo (L38682): winger on offense (asstab 4)
- Timer rating: aidef `$6B`. On new assignment `temp5.hi = $FF`.
- On expiry:
  1. If `puckc >= 0` and the carrier is on the other team, `assreplace(3 asswingd)`. (`puckc < 0` falls through.)
  2. `_de0`: zone selection. `yn = N*pucky`, `pn = N*(pucky + (puckvy asr 6))`:
     - `zone = 0` if `pn < -88 ($FFA8)`.
     - else `zone = 8` if `yn < 88 ($58)` (**uses current yn, not pn**), or if team offside (`$30(a2)` bit 4).
     - else `zone = 16` if `pn < 264 ($108)`.
     - else `zone = 24`.
  3. If `zone == temp5` **and** `(VDP_CNTR & $7F) != 0`, skip to `_nodec` (keep the old target). The HV counter gives roughly a 1/128 chance per expiry of re-rolling in the same zone.
  4. `temp5 = zone`. `temp3 = randomd0s(tab[zone+2]) + tab[zone+0]`, then (second RNG call) `temp4 = randomd0s(tab[zone+6]) + tab[zone+4]`.
- `_nodec` (every frame): `x = temp3`, negated unless `position == 5` (RW). `y = temp4`. If `N = -1`, negate both. `skateto(x, y, EvadePC)`.
- `_dedata` (words; per zone: Xbase, Xrange, Ybase, Yrange; normalized, RW side +X):

| zone (offset) | puck location | Xbase | Xrange | Ybase | Yrange | resulting X | resulting Y |
|---|---|---|---|---|---|---|---|
| 0 | defensive zone | $0050 (80) | $0014 (20) | $FFBA (-70) | $000A (10) | 60..99 | -80..-61 |
| 8 | neutral zone | $0064 (100) | $0014 (20) | $003A (58) | $0005 (5) | 80..119 | 53..62 |
| 16 | offensive zone | $003C (60) | $0032 (50) | $00E6 (230) | $0014 (20) | 10..109 | 210..249 |
| 24 | past goal line | $0050 (80) | $001E (30) | $00FA (250) | $0014 (20) | 50..109 | 230..269 |

### asscenterd (L38800): center on defense (asstab 5)
- Timer rating: aidef `$6B`.
- On expiry: if `puckc >= 0` and the carrier is on the same team, `assreplace(6 asscentero)`.
- `_nodec` (every frame):
  1. `x = puckx asr 1`.
  2. `yn = N*pucky`. `y = -128 ($FF80)`. If `yn >= -88 ($FFA8)`, `y = (-128 + pucky) asr 1`. **This uses the raw world `pucky`, not `yn`.**
  3. If `N = -1`, `y = -y`.
  4. `skateto(x, y, rts)`. No EvadePC, no check4check.
- Quirk (port as-is): for `N = +1` the C sits halfway between the puck and normalized y = -128. For `N = -1` the result is `-((pucky-128) asr 1)`. In normalized terms that is `(-yn-128)/2`, so the C retreats as the puck goes deeper into his offensive end, the mirror image of the `N = +1` behavior. With the puck in his own zone (`yn < -88`), both teams use normalized y = -128.

### asscentero (L38856): center on offense (asstab 6)
- Timer rating: aidef `$6B`. On new assignment `temp5.hi = $FF`.
- On expiry:
  1. If `puckc >= 0` and the carrier is on the other team, `assreplace(5 asscenterd)`.
  2. `_de0`: zone from `yn = N*pucky` (no velocity): `0` if `yn < -88`; `8` if `yn < 88` or team offside; `16` if `yn < 264`; else `24`.
  3. Same `temp5`/`VDP_CNTR & $7F` rule as asswingo. `temp3 = randomd0s(tab[z+2]) + tab[z]`; `temp4 = randomd0s(tab[z+6]) + tab[z+4]`.
- `_nodec` (every frame): `x = temp3` (**never mirrored**). `y = temp4`, negated if `N = -1`. `skateto(x, y, EvadePC)`.
- `_dedata` (Xbase, Xrange, Ybase, Yrange; normalized):

| zone | puck location | Xbase | Xrange | Ybase | Yrange | X | Y |
|---|---|---|---|---|---|---|---|
| 0 | defensive zone | 0 | $003C (60) | $FFBA (-70) | $000A (10) | -60..59 | -80..-61 |
| 8 | neutral zone | 0 | $003C (60) | $003C (60) | $000A (10) | -60..59 | 50..69 |
| 16 | offensive zone | 0 | $0028 (40) | $00AA (170) | $001E (30) | -40..39 | 140..199 |
| 24 | below off. goal line | 0 | $0050 (80) | $00AA (170) | $0014 (20) | -80..79 | 150..189 |

---

## 6. assnearest (L40574-L40877): nearest-to-puck chaser (asstab $11)
- Callers: `updateplayers` via `asstab[$11]`. `assbreakaway` (L40557) always ends up in this code. When a3 is not the carrier or `breakaway` returns negative, it does `assreplace($11)` and then `bra assnearest`. When `breakaway` returns `>= 0` it **falls through** into `assnearest` (no `rts` between them). In that case a3 is the carrier with `$64` bit 1 set, so step 4 below does `assinsert($10 asspuckc)`.
- Inputs: a3 struct (incl. `aioff`, `Chk $75`, `legspd $69`, temp1-temp3), the own team's 6 structs, `puckc`, puck pos/vel, slot bit, `sflags2`, `gmode`, `BA_PS_flags`, `word_FFC2F6`, `byte_FFC2FC/FE`, `$26/$30(a2)`.
- Outputs: temp1-temp3, asslist of a3 and of the teammate it hands off to, `$64` bit 1, `$2A(a2)`, `$358(team)`, `CwdExciteLvl`, `crowdlevel`, temporary `legspd`/`Chk` changes (restored), and movement via `skateto`/`skatetopuck`.

### Entry / breakaway handling
1. `bclr #2,word_FFC2F6`. If the bit was clear, also clear a3's breakaway bit (`$64` bit 1).
2. If a3 is `puckc`, and `$64` bit 1 is clear, and `BA_PS_flags` bit 2 is clear, and `BreakawayOffsidesFlagSet()` returns Z clear: `assreplace($22 assbreakaway)` and continue (`bra.w *+4` is a no-op jump to `_chkbreak`).
   `BreakawayOffsidesFlagSet` (L39808, summary): on pfna it clears `$64` bits 0 and 1. It returns Z clear and sets `$64` bit 1 when the player is between the offensive blue line and the goal line and no non-goalie object is deeper than him. Its `movem` restore clobbers `d0`; only the Z flag is meaningful.
3. `_chkbreak`: `bclr pfna`. If it was set:
   - If `$64` bit 1 (breakaway): `sfx(1)` (ding), the own team struct's `$358` word += 1 (breakaway attempts), `CwdExciteLvl += $14 (20)`, `crowdlevel += $C8 (200)`.
   - `temp3 = 0; temp2 = 8; temp1 = 0`.
   - Quirk: in step 2 `assreplace` has just set pfna, so this init block (and the ding) runs in the same call.
4. `_nna`: if a3 is `puckc`: if `position == 0`, `bra assgoaliecpu`. Else if not `pfjoycon`, `assinsert($10 asspuckc)` (tail). Else `rts`.

### Re-evaluation (`_nopc`, on the reaction timer)
5. `temp1.hi -= d7`. If `>= 0`, go to `_nodec` (step 10).
6. Reload `temp1.hi = aioff ($6A)`. If own goalie pulled, `temp1 -= 1`. Else if crowd-record bit set and `temp1 != 0`, `temp1 -= 1`.
7. **Slot halving**: if the slot bit is set and the carrier is an **opponent** of a3, then `temp1.hi = (sext temp1) asr 1`, and if the result is 0 set it to 1. The opponent test is: `puckc <= 5` with a3 away, or `puckc > 5` with a3 home. Note that `-1 asr 1 = -1`.
8. `$2A(a2).l = 0`.
   - If `puckc >= 0` and the carrier is on a3's team (pfteam bits equal): `a1 = carrier`, go to SWITCH. `d2` is not set on this path; see the quirk.
   - Else (no carrier, or an opponent has it): find the nearest eligible teammate. `best = $FFFFFFFF`. Loop over the 6 own-team objects starting at `$22(a2)`. Skip if `position <= 0`, `nopuck($5E).b != 0`, `$63` bit 2 (unavailable), or current assignment `== $13` (asspassrec). For each candidate:
     `(hx,hy) = GetHot(obj)`;
     `dx = hx + X - puckx - (puckvx asr 6)`; `dy = hy + Y - pucky - (puckvy asr 6)`;
     `d = dx*dx + dy*dy` (long). If `d <= best` (**unsigned**, ties go to the later object), set `best = d` and `a1 = obj`.
     After the loop: if `best` is negative as a long (no candidate), go to step 9b with `d2 = $FFFFFFFF`. Else `$2A(a2).l = best` and go to SWITCH.
   - **SWITCH**: if `a1 == a3`, or clock stopped (gmode bit 0), or `a1` has `$63` bit 2, or `a1` has `$64` bit 3 (one-timer): go to step 9b. Otherwise hand off: on `a1` clear `pfdoff` (`$62` bit 0) and `assinsert($11)`; on a3 `bra assexit` (return; a3 does nothing else this frame). The receiver can be joystick-controlled; then his assnearest only runs this evaluation logic and never moves him.
9. **Pressure decision** (`_de1`; `d2` = best squared distance, or stale):
   a. If `pfalock`, `rts`.
   b. `sh = 2`. If `d2.w <= $190` (**word, unsigned** compare; 400 = 20^2): `sh = 0`, and if `position <= 2` (unsigned: G or D) go to `_nodec` with no pressure roll.
   c. If power play (`sflags2` bit 5): `sh -= 2`. Then if killing (chkpk2 Z set), `sh += 4`.
   d. `r = randomd0( (($28 - Chk) & $FF) << (sh mod 64) )`. `Chk` is `$75`; the subtract is a byte subtract on `$0028`. A shift of `sh = -2` (power-play team, close forward) becomes 62, which gives range 0, and `randomd0(0) = 0`.
   e. If `r <= 2` (unsigned), `temp3 = $F0` (240 frames of direct pressure).
   - Resulting odds of setting pressure per evaluation, with `R = 40 - Chk`:

     | situation | far (`d2.w > 400`) | close forward |
     |---|---|---|
     | even strength | 3/(4R) | 3/R |
     | a3's team on PP | 3/R | always |
     | a3's team on PK | 3/(16R) | 3/(4R) |

     A close G/D never rolls. When `R <= 3` the result is always pressure.

### Movement (`_nodec`, every frame)
10. If `pfalock`, `rts`.
11. If `BA_PS_flags` bit 2 is set and bit 5 is clear, skip to step 12. Otherwise, if gmode bit 0 (clock stopped), `bra assnothing`.
12. If `pfjoycon`, `rts`.
13. If team flag `$30(a2)` bit 2 is set, go to CONTAIN. If `puckc < 0`, go to CHASE. `temp3 -= d7` (word): if `>= 0`, go to CHASE; else `temp3 = 0` and go to CONTAIN.
14. **CHASE** (`_topuck`): `bsr skatetopuck`, then fall through into `check4check` (the routine ends there).
15. **CONTAIN** (`_nodec22`): `(fx,fy) = skatetopuckinit()`.
    - `N = -1` (defending top): `x = ((-fx) asr 1) + fx`; `y = ((244 - fy) asr 1) + fy`, where `244 = $F4`.
    - `N = +1`: `y = ((-fy + 244 - 488) asr 1) + fy = ((-fy - 244) asr 1) + fy`. X is the same.
    - This is approximately the midpoint between the predicted puck and the point (0, +-244), which is 20 px in front of the own goal line.
    - If team flag `$30(a2)` bit 2 is set (see UNRESOLVED): when `N = +1` and `y >= 83 ($53)`, `y = 68 ($44)`. When `N = -1` and `y <= -83 ($FFAD)`, `y = -68 ($FFBC)`.
16. **Speed boost** (`_spdboost`): if the slot bit is set:
    - `TempLegSpd = legspd($69)`; `legspd += 6`. If `byte_FFC2FE` bit 1 (always set) or the crowd-record bit is set, `legspd += 2`, so effectively **+8**. **`_spdlimit`**: if `legspd > 30 ($1E)` (signed byte), `legspd = 30`.
    - `skateto(x, y, rts)`, then `legspd = TempLegSpd`.
    - Else: `skateto(x, y, rts)` with no boost.
    - The boost is only active during this skateto/doplayeracc call, so it affects this frame's acceleration and max speed (MaxSpeed reads legspd).
17. **Goal-side check gate** (`_chkslot`): if the slot bit is clear, `bra check4check`. Otherwise (`_pospuck`):
    - `p = pucky`, `q = Ypos`. If `p < 0`, negate both (mirror so the puck is in +Y).
    - If `q - p < 10`, `rts` (no check this frame).
    - If `|Xpos - puckx| >= 15`, `rts`.
    - Otherwise the player is at least 10 px deeper than the puck and within 15 px in X (goal-side). He then calls `check4check` with `Chk` temporarily set to `min(2*Chk, 30)` (byte arithmetic, `cmp.b #$1E; blt`) and restores `Chk` afterwards.
- Output also: team `$2A(a2)` (nearest distance^2; 0 when a teammate has the puck), read by `assgoalietopuck` (L39768, `$640`) and L39515 (`$9C4`).

### check4check (L40878)
- Purpose: random body check or hold against an opponent directly in front.
- Logic:
  1. If `position == 0`, `rts`.
  2. `R = ($28 - Chk)` (byte subtract into `$0028`). If `OptPen != 0`, `R <<= 1` (word). If `randomd0(R) > 6` (unsigned), `rts`. So the per-call chance is `7/R`.
  3. Opponents: `a0 = SortCords+$300` if a3 is home, else `SortCords`. For each of the 6: skip if `position == 0` (goalie only; **off-ice players are not skipped**), `pfalock`, or fighting (`$63` bit 0).
  4. `dx = a0.X - a3.X`, `dy = a0.Y - a3.Y`. Each must be in `[-30,30]` (signed, inclusive). `vtoa(dx,dy)` must equal `facedir.w`.
  5. On the first match: if the slot bit is set, `bra Acheck`. Else if `(VDP_CNTR & 3) != 0`, `bra burst` (3/4). Else `bra Acheck`. The target is passed in `a0`.
- `burst` (L36830, summary): body check. Push = `(energy >> 7)` along `dirtab[facedir]` (energy cost `$CC` unless the line-change option is set). Sets `pfalock` and `SetSPA($C5E)`.
- `Acheck` (L36872, summary): hold/hook. Sets `pfalock`. The animation is `$1122`, or `$C90` (stick in the air) when `impact($32) != 0` and `N*(target.Y - a3.Y) >= 0` (the target is level with or ahead of the checker in the checker's attack direction). `SetSPA`.
- Called from: `assdefd` (every frame), `assnearest` (every frame along the chase path, and the non-slot contain path), and the goal-side slot case with doubled Chk.

---

## 7. Slot bit (the only AI "grid")

### setSlotBit (L963062)
- Called once per `DoGameFrame` (L29932), **after** `updateplayers`. AI reads therefore lag one loop.
- Logic: clear `word_FFC2F8` bit 5. If `puckc < 0`, return. `c = SortCords + puckc*$80`. `yn = c.Y`, negated if the carrier's `pfgoal` is 0. Set bit 5 only if `yn >= 88 ($58)` **and** `-71 <= c.X <= 71` (`$47` / `$FFB9`, inclusive).
- The slot is the carrier's **offensive** zone (beyond his attacking blue line) within `|x| <= 71`, all the way to the end boards. Its meaning is the same for either team.
- Users:
  - `assnearest`: reaction timer halved for the defending team (step 7); legspd +8 capped at 30 (step 16); goal-side gate and doubled Chk for `check4check` (step 17).
  - `check4check`: always `Acheck` (hold) instead of the random `burst`.
  - `puckstick` (L50552, L50580; out of scope): steal radius^2 `$40` instead of `$24`, and steal odds `<= 4` instead of `<= 2`.
- There is no other tactical grid. Zone logic elsewhere is the hard-coded normalized Y thresholds listed in sec. 9.

---

## 8. Celebrations

### assscore (L38315): celebrate (asstab 7)
- Callers: inserted by `setass` (after a goal) and `clockcont` (winning team at the end of the game); see sec. 2.4.
- Inputs: `Hpos`, `Vpos`, `shotplayer`, `word_FFC2FA`, `word_FFDED0`, temp1-temp4. Outputs: temp1-temp4, `pfalock`, SPA, `word_FFDED0`, `sflags2` bit 2.
1. If `pfalock`, `rts`.
2. `bclr pfna`. If it was set: `temp1 = randomd0(120 ($78))`, `temp2 = 8`, `temp3 = +90 ($5A)` (or `-90` if `Hpos < 0`), `temp4 = Vpos`. The target is the camera center Y, at x = +-90 on the camera's side.
3. `a0 = rtss2` (no evade). `d0 = temp3`, `d1 = temp4`.
4. Shootout mode only (`word_FFC2FA` bit 0, the "code not in 92" block):
   - If `word_FFDED0 != 0`: decrement it (once per call, not by `d7`). If it reaches 0, set `sflags2` bit 2 (stop replay recording).
   - If `Xpos > 136 ($88)` or `Xpos <= -136 ($FF78)`, `d1 = 0`.
5. `temp1 -= d7` (**word**). If `>= 0`: if not `pfjoycon`, `skateto(d0,d1,rts)`; else `rts`.
6. Else (timer ran out): set `pfalock`. `d1 = $E8A` (celebration animation), or `$EFC` (arm pump) if `shotplayer == SCnum`. `SetSPA(d1)`. Then `temp1 = randomd0(120)`; `rts` (no acceleration this frame).
- Effect: the player skates toward (+-90, Vpos). Every 0-119 frames he plays a locked celebration animation; the scorer plays the arm pump.

### assstanley (L38287): skate with the Stanley Cup (asstab 8)
- Callers: inserted by `clockcont` for one player of the cup winner (sec. 2.4).
- Inputs: `Hpos`, `Vpos`, temp3/temp4. Outputs: temp3/temp4, facedir high word, SPA, velocity via `playeracc`.
1. If `pfalock`, `rts`. (No gmclock or pfjoycon checks.)
2. `bclr pfna`. If it was set: `temp3 = +90` (or `-90` if `Hpos < 0`), `temp4 = Vpos`, `SetSPA($109E)` (cup overhead).
3. `dir = vtoa(temp3 - Xpos, temp4 - Ypos)`. If `dir > 7` (exactly on target), `rts`.
4. `facedir.w = dir` (instant facing). `playeracc(d2 = dir)` (already ported; no turn logic and no arrival braking).

---

## 9. How each position picks its target (normalized: own team attacks +Y; RW/RD on +X)

Zone thresholds used: own blue line `-88`, `-78` (asswingd), offensive blue line `+88`, `+93` (assdefo stay-on-offense), goal lines `+-264`, D pinch point `y = 98`, slot `yn >= 88, |x| <= 71`.

| Role | Offense/defense switch (on reaction timer) | Target X | Target Y |
|---|---|---|---|
| D, offense (assdefo) | Goes to defense if team offside, `yn < 93`, or the carrier is an opponent. Stays on offense when the puck is loose. | `puckx` if the puck is on his half, else `lane + puckx/2` (lane RD +80, LD -80) | 98 |
| D, defense (assdefd) | Goes to offense if predicted `yn >= 88`, not offside, a teammate carries, and not short-handed | lane RD +65 / LD -65, or 0 if the puck is on the other half | deepest opponent (Y + toward-own-goal Yvel/16) - 50, collapsed to -220 if `<= -190` |
| W, defense (asswingd) | Goes to offense when a teammate carries | lane RW +100 / LW -100, or `puckx` if the puck is on his side | `pucky` if `yn >= -78`; -158 if puck in own zone; -264 if puck at or behind own goal line; -78 if team offside |
| W, offense (asswingo) | Goes to defense when an opponent carries | `_dedata` X (mirrored for LW) | `_dedata` Y by zone (0 def / 8 neutral or offside / 16 offensive / 24 past goal line) |
| C, defense (asscenterd) | Goes to offense when a teammate carries | `puckx/2` | -128 if puck in own zone, else `(pucky_raw - 128)/2` (mirror bug for N = -1) |
| C, offense (asscentero) | Goes to defense when an opponent carries | `_dedata` X (centered, unmirrored) | `_dedata` Y by zone |
| Nearest (assnearest) | Handed to the teammate nearest the predicted puck (stick hot spot to puck + v/64) | CHASE: predicted puck (`skatetopuck`). CONTAIN: midpoint of the predicted puck and (0,-244) | same |

Re-aim cadence: positional targets are recomputed every frame (`_nodec`). For asswingo/asscentero, temp3/temp4 are re-rolled on a zone change or with a 1/128 chance at each timer expiry. The stick direction is only re-aimed every 12 frames (`skateto`) or 10 frames (`skatetopuck`).

How the stick direction is produced: target minus (position + velocity/256), or minus (position + stick hot spot + velocity/256) for skatetopuck. That vector goes through `vtoa`, giving 0-7. A target within a 12 px box gives 9 (stop). EvadePC can override the result with "away from carrier" or a sideways 2/6. The direction is cached in `temp2.lo` and fed each frame to `doplayeracc(d0)`. `assstanley` alone calls `playeracc(d2)` directly with an instantly snapped facedir.

---

## 10. Quirks to port as-is
1. `assnearest` step 9b compares only the **low word** of the 32-bit squared distance (`cmp.w #$190,d2`). A distance^2 of 65536+k with `k <= 400` counts as "close".
2. `assnearest`, SWITCH path refused for a same-team carrier: `_de1` uses a **stale `d2`**. On the normal path this is the drag shift `6` (or `9` with `pfdoff`) left by updateplayers when `Zpos == 0`, which counts as "close". Port: use `d2 = 9 if pfdoff else 6` there. Strictly, it is whatever updateplayers left in `d2`.
3. In the same routine, a negative shift count (`sh = -2`) gives range 0, so a close forward on the PP team always sets the 240-frame pressure.
4. The `asscenterd` Y formula uses raw `pucky` (asymmetric between the two attack directions).
5. In `asswingo`, the zone-8 test uses the current puck Y while the other tests use the predicted Y. `asscentero` uses no prediction.
6. `asscentero` never mirrors X. `asswingo` mirrors X for any non-RW position.
7. `check4bench` same-player path: `newpos` is overwritten with `$FF` before it is tested, so `position = newpos` never happens there.
8. `check4check` does not skip off-ice opponents (only goalies).
9. `assdefd` includes goalies in the deepest-opponent search, and gives a `+-950` target if every opponent is skipped.
10. In `avdgoal` both `ch1` calls write `deltax`; the second wins.
11. The goalie-pulled bonus can make `temp1 = -1` (immediate re-evaluation next frame). The crowd-record bonus applies to **both** teams.
12. `assnearest`'s breakaway `assreplace` runs the init block (ding and stats) in the same call.
13. `clockcont` gives `assstanley` to the first eligible skater only.
14. `setSlotBit` runs after the AI, so AI slot reads are one loop old.

## 11. UNRESOLVED
1. **Team flag `$30(a2)` bit 2** (forces CONTAIN and the blue-line clamp in assnearest). The only `bset` found is L34286. It sits in a region that disassembles as `printz` strings and data (pause-menu text), so it is probably never set in play. Searched every `#2,$30(a` site. Port the code path but expect it to stay dormant.
2. **`VDP_CNTR` reads** (asswingo/asscentero `& $7F`, check4check `& 3`). These read the VDP HV counter, which depends on hardware timing. Port with an independent RNG: `rand(128) != 0` and `rand(4) != 0`. Do not draw from `RNGseed`, so the `randomd0` sequence stays intact.
3. **`puck_pflags2` bit 0** (skateto faces `xc1/yc1` instead of the puck). No setter was located: no direct references besides two `btst`, and 94 has no fights. It is probably never set.
4. **`_alist` entry 6** (`$05`): no code sets `position = 6` (grepped `#6,$34(a`). Its purpose is unknown.
5. Exact semantics of `BA_PS_flags` bits 2/5 and of `BreakawayOffsidesFlagSet`, `breakaway`, `burst`, `Acheck` and `sub_F6C44` are only summarized here. They belong to the breakaway, input and check specs.
