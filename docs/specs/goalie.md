# Goalie behavior spec (NHL '94 Genesis)

Source: `lst/nhl94.bin.lst` (Lnnnnn = listing line), ROM `lst/nhl94.bin` (checked where the listing is mis-decoded). ROM addresses are given as `$xxxx` where useful. All coordinates are raw game words (pixels, high word of the 16.16 position), in the port convention (origin center ice, +Y = top goal).

## 1. Overview

How the pieces fit together:

1. **Assignment.** A goalie's base assignment is `$0E` = `assgoaliecpu` (`Setplass` table `_alist[0] = $0E`, L51542). `updateplayers` calls `asstab[asslist[assnum]]` every loop with `a3` = goalie, `a2` = own team struct, `a1` = opponent team struct (`loadTeamStruct` L47539: `a2=HmShots ($FFC6CE)`, `a1=AwShots ($FFCA32)`, swapped for the away team). Assignment ids used here (`asstab` L56671): `$0E assgoaliecpu`, `$0F assgoalietopuck`, `$1D assgoaliectrl`, `$20 assgoaliebreakwait`, `$0B assbench`, `$18 pucknorm`.
2. **Human goalie** (`pfjoycon` set): `assgoaliecpu` immediately branches to `assgoaliectrl`, which only runs the "goalie out of range" whistle, the hold-puck whistle timer and an off-camera check. Movement comes from `doinput` → `doplayeracc` → `goalieacc` (joystick direction in `d0`). Save button handling is in `doinput` (it calls `goaliesave` too). If the human goalie is far off camera, `assgoaliectrl` jumps into the CPU logic (`_checkanim`).
3. **CPU goalie** (`assgoaliecpu`), per loop:
   - goal-against reaction animation (`$1596`/`$1684`) once per goal;
   - if outside its crease box → `skateto` back to (±4, ±228) through `doplayeracc` → `goalieacc` (turn-then-skate, SPA `$3D8`);
   - inside the box: SPA `2` (ready stance), hold-puck whistle timer, then a **decision** every time the byte timer `temp1` runs out (reload = `aidef >> 2`, i.e. every 2-4 vblanks). A decision picks a target point (net-centered, offset toward a predicted puck position), turns `facedir` one step toward the puck (`sub_DB68`), may dive on a loose rebound, may pass (`chk4pass`), may start a save (`goaliesave`) from the `puckcross` prediction, or may insert `assgoalietopuck` to chase a puck rimmed wide of the net. Between decisions the goalie keeps accelerating (`playeracc`) in the last chosen direction or decelerates (`stopna`).
4. **puckcross** (4 words at `$FFBEE6`) is the predicted crossing of the two goal lines (x and time), written by `findpc` every 5 vblanks from `pucknorm`; both time words are decremented by `d7` every `pucknorm` call.
5. **Pulling the goalie**: `ChkGoalies` (from `periodiceevents`, once per `$18` vblanks while the clock runs), `ReturnGoalies` (at faceoffs), `CPgoalie` (the decision), `ReadGoaliePulled` (query used by skater AI and `doshot`).
6. **Misc**: `chkgoalie` (part of `restorep1`: auto-goalie redirect when control switches to a goalie in a penalty shot/shootout), `getGoalieSCnum` (find a team's goalie slot), `assgoaliebreakwait` (parks non-participants during penalty shot/shootout).

### 1.1 Globals and tables used

| Name | Address | Meaning |
|---|---|---|
| `SortCords` | `$FFB04A` | 16 object structs, `$80` bytes each. Home goalie normally SCnum 5, away goalie SCnum 11 (`puckpenshot` uses `$FFB5CA` = SCnum 11 as "away goalie"). |
| `puckx/pucky/puckz` | `$FFB74A/$FFB75E/$FFB762` | puck position words |
| `puckvx/puckvy/puckvz` | `$FFB772/$FFB774/$FFB776` | puck velocity words |
| `puckc` | `$FFB7AA` | puck carrier SCnum, negative = none |
| `puckcross` | `$FFBEE6` | 4 words: `+0` x at top goal line (y=+$108), `+2` time to top line, `+4` x at bottom line (y=-$108), `+6` time to bottom line. See section 4. |
| `puckcross2`, `puckcross6` | `$FFBEE8`, `$FFBEEC` | the **high bytes** of the two time words. `st` (byte) on them at faceoffs/goals = "no goalie moves". |
| `TmpPuckX` | `$FFDEB6` | goalie's working puck X (written by each CPU goalie every call) |
| `threat` | word | set to 1 by the goalie before `chk4pass` (skips chk4pass's random gate) |
| `passdir` | word | written by `chk4pass` |
| `word_FFC2F4` | word | bit0 = goal just scored (set in `checkgoal` L49803, cleared in `puckfaceoff2` L42036); bit1 = goal-against reaction already played (cleared L42037); bit3 = (dead) sfx-played flag; bit2 = unused debug flag |
| `word_FFC2FA` | word | bit0 = shootout |
| `BA_PS_flags` | word | bit2 = penalty-shot/shootout attempt active; bit4 = set when the PS goalie holds the puck too long |
| `BA_Goalie_SCnum` | word | SCnum of the goalie being shot on in PS/SO |
| `gmode` | word | bit0 clock stopped, bit3 delayed penalty (`gmpendel`), bit5 offsides rule on |
| `sflags` | word | bit3 = shot in flight (`SetShotMode` sets it, puck touch clears it); bit7 = horizontal mode |
| `iflags` | word | bit2 = icing pending |
| `gameclock` | word | seconds left in period (decremented by 1 per second, L51791) |
| `gsp` | word | period, 0-based (2 = 3rd) |
| `foy` | word | faceoff Y |
| `byte_FFC2FC` | byte | bit6 = crowd meter "broken" (boost) |
| `crowdlevel`, `CwdExciteLvl` | `$FFB89C`, `$FFB8A2` | crowd noise accumulators |
| `Hpos`, `Vpos` | words | camera center in rink coords (tracked in `checkwindow` L35779, updates at L35843/L35873) |
| `word_FFD05A`, `word_FFD05C` | words | home / away **Auto Goalie** flag (copy of `OptGoalie`, L962424; menu text at `$8050` "Manual Goalie" / `$8064` "Auto Goalie"); nonzero = auto |
| `cont1team`, `cont2team` | words | team on controller 1/2 (0 none, 1 home, 2 away) |
| Team struct (`HmShots $FFC6CE`, `AwShots = +$364 = $FFCA32`) | | `$0C` score (word), `$22` SortCords address of team's first object (word), `$26` goalie word (high byte `$FF` = pulled; `$FFFF` = no goalie), `$2A` (long) = squared distance of that team's nearest available skater to the (lead-adjusted) puck, written by `assnearest` L40663/L40713; 0 when that team has the puck or no skater qualifies |

Tables dumped in this file: `_saveanim` (under goaliesave), the `sub_DB68` facing masks, `asstab` ids (above), `Setplass _alist` (7.4), `puckgoalie _list` rating offsets (1.2), `PenaltyList` entry used (`+8 = $94 PenFO`), SPA list (8.1).

### 1.2 Goalie rating bytes in '94 (correction)

The task names (`GGSright $6D, GSSleft $70, GGSleft $71, GSSright $72`) are the '93 equates in `src/ram94.asm` L205-213. '94 `setplayer` (L51620-51750) fills `$6D` (roster byte 5 low nibble), `$6E` (byte 7 high), `$70` (byte 6 low), `$71` (byte 5 high), `$72` (byte 6 high), `$73` (byte 7 low, masked to 0-15) and `$76` (hand). The '94 save code reads `$73/$6E/$70/$72`, not `$6D/$71`. `puckgoalie` (L50818, out of scope; it decides whether a shot is stopped) uses this table at `$15630` (L50959):

| index (`d2`) | offset | listing name |
|---|---|---|
| 0 | `$73` | GGSleft (glove, puck high, one side) |
| 2 | `$6E` | GGSright (glove, other side) |
| 4 | `$70` | GSSleft (stick, puck low) |
| 6 | `$72` | GSSright (stick, other side) |

save odds = rating byte + `$F`. So in '94 the glove ratings are `$73` and `$6E`, not `$71` and `$6D`.

Ratings read by the routines **in this spec**:
- `$6B` aidef: reaction/decision timer for `assgoaliecpu`, `assgoaliectrl`, `assgoalietopuck`. setplayer: `aidef = (((DfA' >> 1) ^ $F) + $F) >> 1` where DfA' = AttributeCalc(roster byte 3 high nibble), clamped to 0..30. Range 7..15; **higher = slower**. Timer reload = `aidef >> 2` (1..3), or `(aidef-1) >> 2` when `byte_FFC2FC` bit6 and `aidef != 0`.
- `$73`: glove rating (GGSleft); `goaliesave` upgrades the glove save to the reach-out glove save when `$73 >= 11`.
- `$76` bit0: handedness (setplayer: roster byte 4 bit0 XOR 1). `goaliesave` pad-stack side flip.
- attribute word `$04` bit3 (sprite xflip; setplayer sets it when `$76 == 0`): flips left/right save choice in `goaliesave`.
- `$70`: only in `chk4pass`'s random gate, which the goalie skips (`threat = 1`). So not used by the goalie.
- `$68` agility / `$69` speed / `$67` weight: through `playeracc` (already ported; goalie gets agility twice + `$10`).

Note: '94 uses `$63` (pflags2) **bit 2** as "unavailable" (`check4bench` L37861 sets it), not bit 4 as in the '93 equates.

---

## 2. CPU goalie

### assgoaliecpu (L39072-39540, ROM `$D51C`)
- Purpose: assignment `$0E`, the goalie brain. Callers: `asstab` (`updateplayers`), `assnearest` L40622 (`beq assgoaliecpu` when the goalie is the puck carrier), `assgoaliectrl` (jumps to `_checkanim` when the human goalie is off camera).
- Inputs: `a3` goalie, `d7` vblanks, struct fields `$00,$14,$28,$2A,$06 (frame),$34,$40-$48 (temps),$52,$54,$58,$62,$63,$64,$6B`; globals `puckx/y/vx/vy`, `puckc`, `puckcross`, `gmode`, `sflags`, `word_FFC2F4`, `word_FFC2FA`, `BA_PS_flags`, `gameclock`, `iflags`, team struct `$2A`, HV counter (`VDP_CNTR` = `$C00008`, `src/stubinc/ports.inc`).
- Outputs: `$54` facedir, `$43` (temp2 low byte) = chosen direction, `$40` decision timer (byte), `$46` temp4, `$48` temp5, velocity (via `playeracc`/`stopna`/`skateto`), SPA via `SetSPA`, `$63` bit1 `pf2aip`, `$5E` nopuck, `TmpPuckX`, `threat`, `crowdlevel`, `word_FFC2F4` bits 1/3, asslist (via `assinsert`).

Temps used (word unless noted):
- `$40` (byte) temp1 = decision countdown.
- `$42` (byte) = skateto countdown, `$43` (byte) = current direction (0-7 move, 8 stop, 9 arrived).
- `$46` temp4 = "rebound dive window" counter (normally negative; `puckgoalie` sets it to 4 when the puck bounces off the goalie, L50897).
- `$48` temp5 = hold-puck countdown (`_glue` L50702 sets `$8C` (140), or 5 if the goalie got the puck during the dive SPA `$2F4`).

Note on `st`: `st $46(a3)` and `st $48(a3)` are byte stores to the **high byte** of the word (verified: `50 EB 00 46`). The word becomes `$FFxx`, i.e. negative. Port as "set high byte to $FF".

Exact logic:

**A. Joystick check** (L39074)
1. If `$62` bit3 (pfjoycon) set → `goto assgoaliectrl`.

**B. `_checkanim`: goal-against reaction** (L39076-39114)
2. `TmpPuckX = puckx` (every call).
3. If `word_FFC2F4` bit0 (goal scored) is 0 → step 5.
4. If `pf2aip` (`$63` bit1) set → step 5. Otherwise:
   - If `word_FFC2F4` bit1 set: if bit3 clear **and** `frame($06) == $2C4` **and** `frame == $2C8` → set bit3, `sfx($1C)`. The two `bne` tests make this unreachable (verified bytes `0C6B 02C4 0006 6600` / `0C6B 02C8 0006 6600`). Port as dead code. → step 5.
   - Else (bit1 clear): if `sign(pucky) == sign(Y)` (`eor.w`, result >= 0) and `-20 < X <= 20` (`cmpi #$14 bgt` skip, `cmpi #$FFEC ble` skip): set `word_FFC2F4` bit1, clear bit3, `SetSPA($1596)` if pfgoal (bit7 of `$62`) = 0, else `SetSPA($1684)`; set `pf2aip`.

**C. `_assstart`: assignment setup** (L39115-39124)
5. If `$62` bit5 (pfalock) → return.
6. `check4bench` (L37838). For a CPU goalie that is to be changed (e.g. pulled by `SetPersonel`), it replaces the assignment (assbench `$0B`, or `Setplass`) and pops this routine's return address, so nothing below runs. Otherwise it returns.
7. `bclr` pfna (`$62` bit1); if it was set: `temp1 word ($40) = 0`, `temp2 word ($42) = 8` (so `$42=0`, `$43=8`), byte `$46 = $FF`.

**D. Crease box test** (L39125-39137)
8. In box iff `-52 <= X <= 52` (`$34`/`$FFCC`), `-270 <= Y <= 270` (`$10E`/`$FEF2`), and (`Y > 210` (`$D2`) or `Y < -210` (`$FF2E`)). The test does not check which end.
9. If not in box (`_nna2`): `a0 = rtss2` (no extra avoidance), `tx = 4` if `X >= 0` else `-4`, `ty = $E4` (228) if pfgoal = 0 else `-$E4`; `goto skateto(tx, ty)` (see 7.1). Note: runs even during `pf2aip` and with the clock stopped; `goalieacc` then calls `SetSPA($3D8)` and can overwrite a running animation.

**E. `_noskate`: in the box** (L39152-39172)
10. If `pf2aip` → return.
11. If `word_FFC2F4` bit0: if `frame == $2C5` → `facedir = 0`; else if `frame == $2C9` → `facedir = 4`. (These frames are inside the reaction SPAs `$1596`/`$1684`.)
12. `SetSPA(2)` (SPAgready, every call).
13. If `BA_PS_flags` bit2 clear and `gmode` bit0 (clock stopped) → return.

**F. Hold-puck whistle** (`_noskate4`, L39175-39194)
14. If temp5 (`$48`, signed word) < 0 → step 16.
15. If `puckc == SCnum`: `temp5 -= d7`; if `temp5 >= 0` → step 16. Else: if `BA_PS_flags` bit2 → set `BA_PS_flags` bit4; else `AddPenalty2(d0=8)` (whistle → faceoff, `PenaltyList+8 = $94 PenFO`). Continue to step 16.
    If `puckc != SCnum`: byte `$48 = $FF`.

**G. Decision timer** (`_nofo`, L39195-39213)
16. `temp1.b ($40) -= d7`. If result >= 0 (signed byte, `bpl`) → **`_nodec`** (step 39).
17. `d0 = aidef ($6B)`; if `d0 != 0` and `byte_FFC2FC` bit6 → `d0 -= 1`. `temp1.b = d0 >> 2` (`lsr.b`).
18. If pfjoycon set and `$64` bit2 clear → `assinsert($1D)` and return. Unreachable in practice (pfjoycon here implies entry from `assgoaliectrl`, which requires `$64` bit2 set). Port as-is.

**H. `_nocontrol`: puck in the other half** (L39215-39226)
19. If `sign(pucky) != sign(Y)` (`eor.w` negative): `tx = 0`, `ty = $F4` (244) if pfgoal = 0 else `-$F4` → **`_de5`** (step 36). Facing is not updated, and no dive/pass/save checks run.

**I. Same half** (L39228-39317)
20. `temp4 -= 1`; if the result is negative → `temp4 = $FFFF`.
21. If `puckc == SCnum` (goalie has the puck):
    - If `temp5 < 0` → `temp5 = $5A` (90).
    - Byte `$46 = $FF`.
    - If `temp5 > $5A` (signed) → `_de1`. (Right after pickup temp5 = 140, so no pass until it has counted down to 90.)
    - If `HVcounter & 3 != 0` → `_de1` (pass look happens 1 time in 4).
    - Opponent scan: `a0 = SortCords + $300` (SCnum 6..11) if the goalie is home (`$62` bit6 = 0), else `SortCords` (0..5). For 6 objects: skip if `$63` bit2 (unavailable); `ddy = pucky - oY`; skip unless `-28 <= ddy <= 28` (`$1C`); `ddx = puckx - oX`; skip if `ddx > 25` (`$19`); if `ddx > -25` (`$FFE7`) → opponent is close → `_de1` (no pass). (Opponent goalie included.)
    - No close opponent: `threat = 1`; `chk4pass` (7.3); → `_de1`.
22. Else (`_notpuckc`), **rebound dive / cover**. All must hold, otherwise → `_de1`:
    - `temp4 == 0` (only on the 4th decision after `puckgoalie` set temp4 = 4);
    - `puckc < 0`;
    - `dx = puckx - X` in `[-20, 20]` (`$14`);
    - `-264 <= pucky <= 264` (`$108`/`$FEF8`);
    - `dy = pucky - Y` in `[-30, 30]` (`$1E`);
    - `|puckvx| + |puckvy| <= $1000` (signed compare, `bgt` fails).
    Then: `facedir = vtoa(dx, dy)` (can be 8 if dx=dy=0; port as-is); byte `$5E` (nopuck) = 8; `SetSPA($2F4)` (dive); set `pf2aip`; `crowdlevel += $96`; **return** (no movement this loop).

**J. `_de1`: positioning target** (L39318-39465)
23. `a0 = puckcross+0`, `d3 = $104` (260); if pfgoal = 1: `a0 = puckcross+4`, `d3 = -$104`.
24. If `Y > 260` or `Y <= -260` (`cmpi #$104 bgt`; `cmpi #$FEFC bgt` = normal): goalie is at or behind the goal line (`loc_D8AA`):
    `ty = 0`; `tx = 0` if `X > 44` or `X < -44` (`$2C`/`$FFD4`); else `tx = $88` (136) if `X >= 0`, `-136` if `X < 0` → `_de5`.
25. Normal (`loc_D8CE`): if `puckc >= 0` and `puckc != SCnum`: `TmpPuckX = cX + asr(puckx - cX, 1)` with `cX` = carrier X (floor halving).
26. `(vx, vy) = sub_DB3E(TmpPuckX, pucky)` (below), the vector from the net point `(0, d3)` to the puck. `dir = vtoa(vx, vy)`; `sub_DB68(dir)` (below): turn one step toward the puck.
27. Lookahead factor `f = (gameclock & 7) * 16 + $A0` (160..272). If `pucky > $DB` (219) or `pucky <= -219` (`$FF25`, `bgt` = keep) → `f -= $40`.
28. `px = hi16(f * puckvx) + TmpPuckX`, `py = hi16(f * puckvy) + pucky` (`muls.w` then `swap`: the high word of the signed 32-bit product, i.e. floor division by 65536).
29. `(Vx, Vy) = sub_DB3E(px, py)`.
30. `D = Vx*Vx + Vy*Vy` (32-bit). If `D <= $384` (900, unsigned) → offset = `(Vx, Vy)`. Else: `s = sroot(D)`; `n = 1 + s`; `ry = $12` (18), or `$1A` (26) if `sflags` bit3 (shot in flight); `rx = ry + 8` (26 or 34); `Vy' = (Vy * ry) / n`, `Vx' = (Vx * rx) / n` (`divs.w`, truncation toward zero).
31. `ty = Vy' + d3`; `tx = Vx'`. (Keep `ty` in `d2`; `d3` and `a0` stay live.)

**K. Save / reaction decision** (L39413-39465)
32. Early-shot test: if shootout (`word_FFC2FA` bit0) or PS (`BA_PS_flags` bit2) or no shot in flight (`sflags` bit3 = 0) → step 33. Else if `pucky > $D0` (208) or `pucky < -208` (`$FF30`): if `-20 <= X <= 20` (`$14`/`$FFEC`) and `(gameclock & 2) == 0` (bit1 of the low byte) → **step 34 directly**, skipping all `puckcross` checks; otherwise step 33. Else (`|pucky| <= 208`) → step 33.
33. `puckcross` checks (`loc_D9EE`; `t = (a0+2)`, `cx = (a0)`):
    - `t > $22` (34) **unsigned** → `_de5` (just position; negative/"no crossing" times are huge unsigned).
    - `cx > $18` (24) or `cx < -24` (signed) → `loc_DAB6` (step 35).
    - `t > $0C` (12) unsigned → step 34b (no save yet).
34. (`loc_DA12`) If `-264 <= pucky <= 264`: `bset pf2aip`; if it was clear → `goaliesave` (`a0`, `d3` = ±260). (`goaliesave` clobbers `d3`/`d0`/`d1`, not `d2`.)
    34b. (`loc_DA36`) `tx = cx`; if `pucky > $FC` (252) or `pucky <= -252` (`$FF04`, `bgt` = keep): `tx = $18` (24) if `TmpPuckX >= 0` else `-24`. → `_de5` with `ty` unchanged.
35. (`loc_DAB6`) Puck will cross wide of the net. Chase it? All must hold, otherwise → `_de5`:
    - `puckc < 0`; `iflags` bit2 (icing pending) clear;
    - own team `$2A` (long) >= `$1324` (4900 = 70²) and opponent `$2A` >= `$9C4` (2500 = 50²) (signed `cmpi.l`/`blt`);
    - `pucky > $E0` (224) or `pucky <= -224` (`$FF20`);
    - puck moving toward this goalie's end: pfgoal = 0: `puckvy >= 0`; pfgoal = 1: `puckvy < 0` (`tst`, then `eori #8,ccr` flips N for pfgoal = 1, `bmi` skip). Asymmetry: `vy == 0` passes for pfgoal 0 only;
    - `|puckvy| >= |puckvx|`.
    Then `assinsert($0F)` (assgoalietopuck) and return.

**L. `_de5`: steer toward target** (L39466-39493)
36. `dx = tx - sext(Xvel.hi) - X`, `dy = ty - sext(Yvel.hi) - Y`, where `Xvel.hi` is the byte at `$28` (equal to `Xvel asr 8`).
37. If `-4 <= dx <= 4` and `-4 <= dy <= 4` → `dx = dy = 0`.
38. `$43 = vtoa(dx, dy)` (8 when zero).

**M. `_nodec`: apply** (L39494-39500)
39. `d2 = sext($43)`; if `d2 <= 7` → `playeracc(d2)` (accelerate in that absolute direction; facing unchanged); else `stopna` (each axis moves `$96` toward 0).

Quirks:
- The `$2C4 && $2C8` frame test is unreachable; `sfx $1C` is never played from here.
- The step 18 `assinsert($1D)` is unreachable.
- The box test (step 8) and the behind-goal test (step 24) use `|Y|` at either end.
- Step 32's early save fires whenever a shot is in flight, the puck is deep in this half and the goalie is centered on alternating 2-second windows, even if the puck is not heading at the net. `goaliesave` then reads a possibly stale `puckcross` x.
- In the "other half" path (step 19) and the "behind goal line" path (step 24) `facedir` is not updated.
- CPU movement uses `playeracc` directly, so the goalie moves in any of 8 directions independent of facing. Only skate-back (`skateto` → `goalieacc`) turns first.

### sub_DB3E (L39543-39560, ROM `$DB3E`)
- Purpose: build the vector from the net point (0, `d3`) to a puck point. Called only by `assgoaliecpu` (twice). `doinput` has an identical copy, `sub_B5D8` L36283.
- In: `d0` x, `d1` y, `d3` ±260, `a3`. Out: `d0`, `d1`. Uses `d2`.
1. If `puckc == SCnum` → `d0 = 0`.
2. If `d1 >= $103` (259) → `d1 = $103`. If `d1 <= -$103` (`$FEFD`) → `d1 = -$103`.
3. `d1 -= d3`. Return (`d0` unchanged except step 1).

### sub_DB68 (L39563-39591, ROM `$DB68`; listing mis-decoded, decoded from bytes)
- Purpose: turn `facedir` one 45° step toward `d0`. For the CPU, never turn through "facing into own net". Callers: `assgoaliecpu` (L39367), `goalieacc` (L43523, L43532).
- Raw bytes: `322B0054 9041 670078F4 4440 02400004 E248 5340 082B00030062 6600002A 033C0042 67000022 D240 082B00070062 6600000A 033C0083 60000006 033C0038 67000008 4440 D240 D240 02410007 37410054 4E75`. `033C xx` = `btst d1,#imm` (bit number = `d1 mod 8` of the immediate byte).
- In: `d0` target dir (0-7; may be 8 from vtoa), `a3`. Out: word `$54`. Clobbers `d0`, `d1`.

```
f = word $54
diff = d0 - f                       ; 16-bit
if diff == 0: return
step = ((f - d0) & 4) ? +1 : -1     ; neg, and #4, lsr #1, subq #1
if pfjoycon ($62 bit3) set:          goto simple
if f not in {1, 6}  (mask $42):     goto simple
n = f + step
if pfgoal ($62 bit7) == 0: bad = {0, 1, 7}   (mask $83)
else:                      bad = {3, 4, 5}   (mask $38)
if n in bad: n = f - step           ; turn the other way
$54 = n & 7; return
simple: $54 = (f + step) & 7
```
- Tie (target exactly opposite): `(f - d0) & 4` is 4, so step = +1 (clockwise).
- Quirk: the restriction is only checked from facings 1 and 6. For pfgoal = 0 that blocks 1→0 and 6→7. For pfgoal = 1 only 6→5 is ever blocked (1±1 never hits {3,4,5}), and 2→3 is allowed. Port as-is.
- Writes only the integer word of the 16.16 facedir.

### goaliesave (L39598-39718, ROM `$DBBA`)
- Purpose: pick and start a save animation from the predicted crossing point. Callers: `assgoaliecpu` (L39453, `d3 = ±$104`), `doinput` human save button (L36277, `d3 = ±$108`). Both callers set `pf2aip` first.
- In: `a3` goalie, `a0` = `puckcross` entry (`(a0)` = x at line, `2(a0)` = time), `d3` = goal line Y; globals `puckz`, `puckvz`, `puckc`. Out: SPA, `$28/$2A` velocity, `X` (pad stack), `crowdlevel`, `CwdExciteLvl`. Clobbers `d0`, `d1`, `d3`, `a1`.

```
rel = (vtoa(cx - X, d3 - Y) - facedir) & 7     ; 0 ahead, 1-3 right(cw), 4 behind, 5-7 left
d3 = rel
i = rel >> 2                                     ; 0 for rel 0-3, 1 for rel 4-7
if attribute($04) bit3 (xflip): i ^= 1
if puckz > 8 or puckvz > $800 (signed):          ; HIGH
    if -16 <= X - cx <= 16: i += 6               ; high shoulder
    ; else i stays 0/1 (blocker/glove)
else:                                            ; LOW
    i += 4                                       ; kick / butterfly
    if t <= 8 (unsigned):
        if (X - cx) > 16 or (X - cx) <= -16: i += 4   ; stick save (8/9)
        ; strict on the low side: -16 < X-cx <= 16 keeps 4/5
    else if facedir == 2 or facedir == 6: (keep)
    else if puckc < 0: (keep)
    else:                                         ; puck carried, t > 8: PAD STACK
        i = (pfgoal == 1) ? 3 : 2                 ; (i-2)|1, then ^1 if pfgoal==0
        Xvel = $1000; Xvel = -$1000 (always negated here); dX = -6
        if X < 0: Xvel = +$1000; dX = +6; i ^= 1
        X += dX                                   ; word add to Xpos (instant 6 px toward center)
        if $76 bit0 set: i ^= 1
spa = _saveanim[i]
if spa == $178 and (rel & 3) != 0 and (signed byte)$73 >= 11: spa = $1AA
SetSPA(spa)
crowdlevel += $96; CwdExciteLvl += $0A
Xvel = asr(Xvel, 2); Yvel = asr(Yvel, 2)          ; two asr.w #1 each (floor)
```
- `vtoa` returns 8 for a zero vector; `(8 - facedir) & 7` is then used as-is.
- Pad stack leaves `Xvel = ±$1000 >> 2 = ±$400` toward center.
- No sound, no random.

`_saveanim` (L39717, ROM `$DD1A`, 10 words; an unused duplicate sits in `doinput` at `$B602`):

| i | SPA | listing comment |
|---|---|---|
| 0 | `$0146` | blocker save |
| 1 | `$0178` | glove save |
| 2 | `$0250` | pad stack right |
| 3 | `$02A2` | pad stack left |
| 4 | `$01EC` | kick save |
| 5 | `$021E` | blocking butterfly save |
| 6 | `$148E` | high shoulder save right |
| 7 | `$14C0` | high shoulder save left |
| 8 | `$14F2` | (no comment; stick save right, the pair of 9) |
| 9 | `$1544` | stick save left |
| extra | `$01AA` | reach-out glove save |

### assgoalietopuck (L39731-39771, ROM `$DD2E`)
- Purpose: assignment `$0F`, chase a loose puck rimmed wide of the net. Inserted by `assgoaliecpu` step 35. On exit (`assexit`) the next asslist entry, the original `$0E`, resumes.
- In: `a3`, `d7`, `$6B`, `puckc`, `puckvy`, team structs `$2A`. Out: `$40`, `$42/$43`, velocity, facing.
1. If pfjoycon or clock stopped (`gmode` bit0) → `assexit`.
2. `check4bench`.
3. If `bclr pfna` was set → `temp1 word = 0`.
4. `temp1.b -= d7`; if >= 0 → step 7.
5. Reload `temp1.b = aidef' >> 2` (same as assgoaliecpu step 17).
6. Re-validate (any failure → `assexit`): `puckc < 0`; puck moving toward own end (pfgoal 0: `puckvy >= 0`; pfgoal 1: `puckvy < 0`; same `eori #8,ccr` trick); own team `$2A >= $E10` (3600 = 60²); opponent `$2A >= $640` (1600 = 40²) (signed long compares; `a1/a2` re-derived from `HmShots/AwShots` and `$62` bit6).
7. `goto skatetopuck` (7.2).
- There is no distance-from-net limit. The chase ends only through step 6 on a decision frame, or when the goalie gets the puck (`puckc >= 0` → `assexit`).

---

## 3. Human goalie

### assgoaliectrl (L38963-39068, ROM `$D3C6`)
- Purpose: assignment `$1D` and the direct target of `assgoaliecpu` when pfjoycon is set. Whistles and timers for the joypad goalie; hands the AI back control when the goalie is off camera.
- In: `a3`, `d7`, `Hpos`, `Vpos`, `gmode`, `puckc`, `BA_PS_flags`, `$6B`. Out: `$64` bit2, temps, `AddPenalty2` calls.
1. If pfjoycon clear → `assexit`.
2. If pfna set → step 5.
3. Range whistle: if `-$AA <= Y <= $AA` (-170..170) and clock running → `AddPenalty2(d0=8)` (L38983, "clock stoppage due to goalie out of range").
4. Off-camera test: `dx = X - Hpos`, `dy = Y - Vpos`. Clear `$64` bit2, then set it if `dx >= $74` (116) or `dx <= -116` or `dy >= $64` (100) or `dy <= -100`. If set → `goto assgoaliecpu._checkanim` (CPU logic drives the goalie this loop).
5. `_na`: if pfalock → return. `check4bench` (returns at once for joystick players). If `bclr pfna` was set: `temp1 word = 0`, `temp2 word = 8`, byte `$46 = $FF`.
6. If `pf2aip` → return. If clock stopped → return.
7. Hold-puck whistle, the same as assgoaliecpu step 14-15 (`temp5`, `$48`; `AddPenalty2(8)` or `BA_PS_flags` bit4).
8. `temp1.b -= d7`; if >= 0 → return. Reload `temp1.b = aidef' >> 2`.
9. `if puckc == SCnum: beq *+4`: the branch target is the next instruction (`$D51A rts`, verified `6700 0002`), so it is a no-op. Return.
- Quirk: the listing comment "jump to assgoaliecpu" is wrong; the ROM branch is a no-op.

### goalieacc (L43477-43642, ROM `$1090A`)
- Purpose: the goalie branch of `doplayeracc` (`$34 == 0`). Handles joystick input for a human goalie, and the turn-then-skate movement for a CPU goalie driven by `skateto`/`skatetopuck`.
- In: `d0` requested direction (human: joystick 0-7, 8 = neutral; CPU: `$43` byte 0-255, masked to 4 bits), `a3`, puck globals, `word_FFC2F4`. Out: facing, SPA, velocity via `playeracc`/`stopna`/`stopna2`.

```
; ---- human goalie in his crease box ----
if pfjoycon and puckc != SCnum
   and -48 <= X <= 48                                   ; $30 / $FFD0
   and ( -262 <= Y <= -192  or  192 <= Y <= 262 ):      ; $FEFA..$FF40 / $C0..$106
    dx = puckx - X; dy = pucky - Y
    if -16 <= dx <= 16 and -16 <= dy <= 16: t = facedir
    else: t = vtoa(dx, dy)
    if word_FFC2F4 bit0 == 0: sub_DB68(t)      ; face the puck (unrestricted, pfjoycon set)
    elif d0 != 8:             sub_DB68(d0)     ; after a goal: face the stick direction
    if pf2aip: return
    SetSPA(2)
    if d0 != 8: playeracc(d0); return           ; strafe in stick direction
    ; neutral stick ($34==0 and pfjoycon checks always pass)
    stopna2()                                   ; both sub-branches (deep / not deep) do the same
    playeracc(8)                                ; dirtab[8] = (0,0)
    return
; ---- loc_10A42 ----
d1 = 2
if not pfjoycon: goto CPU
if pfnc ($62 bit2): goto cgl
if d0 != 8: goto turn
y = pfgoal ? -Y : Y
if y >= $D8 (216) and -32 <= X <= 32: stopna()  ; $20 / $FFE0
goto cgl
CPU (_goalieacc2):
d0 &= $F
if d0 <= 7: goto turn
if d0 == 9 and (Xvel | Yvel) != 0: stopna2(); return
cgl: if not pf2aip: SetSPA(d1 = 2)
return
turn (_d1):
if d0 != facedir: facedir = (facedir + (((facedir - d0) & 4) ? +1 : -1)) & 7
SetSPA($3D8)                                     ; even if pf2aip is set
playeracc(facedir)                               ; accelerate along the facing, not along d0
```
- `stopna2` (L959753, ROM `$F6F8C`): per axis, `vel` moves `$7D0` (2000) toward 0 and clamps at 0 (not scaled by `d7`). Its fall-through structure (`clr` then `subi` then `clr`) still gives 0 in the crossing case.
- Quirk: outside the box the human goalie skates along `facedir`, turning one step per loop toward the stick. Inside the box he strafes in the stick direction while facing tracks the puck.

---

## 4. Puck crossing prediction

### pucknorm (part) (L42526-42545)
- Purpose here: maintain `puckcross`. pucknorm is the puck's assignment `$18` in normal play (rest of pucknorm is out of scope).
1. On new assignment (`bclr pfna` was set): puck `temp1 word ($40) = 0`, `temp2 = $78`.
2. Every call: `puckcross+2 -= d7`; `puckcross+6 -= d7` (16-bit wrap).
3. `puck.temp1 -= d7` (word); if result < 0: `temp1 += 5`; `findpc()`. findpc therefore runs about every 5 vblanks, and on the first call.

### findpc (L42894-42946, ROM `$10346`)
- Purpose: predict where and when the puck crosses each goal line.
- In: `pucky`, `puckx`, `puckvx`, `puckvy`. Out: `puckcross[0..3]`.

```
for (entry, L) in ((puckcross+0, +$108), (puckcross+4, -$108)):
    dy = L - pucky                                   ; word
    if puckvy == 0: entry.t = $FFFF; continue        ; x left stale
    q = divs16((dy << 16) asr 4, puckvy)             ; = trunc(dy*4096 / puckvy)
    if q < 0 (bit15 set): entry.t = $FFFF; continue  ; moving away
    entry.t = q
    x = divs16(dy * puckvx /*muls 32-bit*/, puckvy)  ; trunc
    if overflow (V): entry.t = $FFFF; continue       ; x left stale
    x = x + puckx                                    ; 16-bit
    if x >= 136 ($88):  x = 408 - x                  ; neg, add $88 three times
    if x <= -136:       x = -408 - x
    entry.x = x
```
- Units: `t` is in "vblanks" computed as `dy*4096/vy`. With the position integrator `pos += vel*17/65536 px` per vblank, the true time is `dy*3855/vy`, so `t` is about 6% too long. Port the formula exactly.
- Quirk (verified bytes `D041 D041 D041`): the side-board "mirror" uses three additions (408 - x) instead of two (272 - x), so a reflected x lands far outside the rink. Port as-is.
- The x is only relevant to the goalie via the `|cx| <= 24` net test and `goaliesave`.
- At faceoffs and goals (`puckfaceoff2` L42069, L48255, `checkgoal` L49948) the code does `st puckcross2` / `st puckcross6`, setting the **high byte** of both time words to `$FF` (time = `$FFxx`, negative/huge unsigned) = "no goalie moves".
- UNRESOLVED: `divs.w` overflow on the time divide (`|dy*4096/vy| > 32767`, i.e. `|puckvy| < |dy|/8`, slow pucks). The 68000 leaves `d2` unchanged and sets V; N is documented as undefined. If N reads 1 (MAME/Genesis Plus GX-style "N set on overflow") → `bmi` → `t = $FFFF`. If N keeps the `asr.l` result's sign, `t` gets the garbage low word `(dy << 12) & $FFFF` (0 when dy is a multiple of 16) when `dy >= 0`. Recommendation: treat overflow as "no crossing" (`t = $FFFF`). I could not verify real-hardware N on DIVS overflow from the listing.

How the goalie reads it: entry `puckcross+0` (top line, +264) for a pfgoal = 0 goalie (defends top); `puckcross+4` for pfgoal = 1. Thresholds (unsigned on t): react window `t <= 34`, net `-24 <= x <= 24`, save `t <= 12`; `goaliesave` stick/kick split uses `t <= 8`.

---

## 5. Pulling the goalie

### ChkGoalies (L41839-41872, ROM `$F6AA`)
- Purpose: pull a goalie for an extra attacker. Called from `periodiceevents` (L29951) only when not in horizontal mode (`sflags` bit7), and only when `lldisp` (decremented by `d7`, reloaded `+$18`) expires, i.e. about every 24 vblanks.
1. If clock stopped → return.
2. `a2 = HmShots`, `a1 = AwShots`, `d0 = 1`, run `_chkgoalie`; then `d0 = 2`, swap `a1/a2`, run `_chkgoalie` for away.
3. `_chkgoalie`:
   - If `$26(a2)` < 0 (already pulled / none) → return.
   - If `puckc < 0` → return.
   - Team has the puck? Home: `puckc - 6 < 0`. Away: `not(puckc - 6) < 0`, i.e. `puckc > 5`. Otherwise return.
   - If `gmode` bit3 (delayed penalty): byte `$26(a2) = $FF` (high byte) → `goto SetPersonel` (out of scope; rebuilds the on-ice list). This applies to human teams too.
   - Else: if `d0 == cont1team` or `d0 == cont2team` → return (human team). `d1 = pucky` → `goto CPgoalie`.
- Quirk: `cont3team`/`cont4team` are not checked.

### ReturnGoalies (L41876-41893, ROM `$F712`)
- Purpose: put pulled goalies back at a faceoff. Callers: L41104 (`ROM:$EDA4`, game/period start path) and `puckfaceoff` L41695.
1. For home (`d0=1`, `a2=HmShots`, `a1=AwShots`), then away (`d0=2`, swapped):
   - If `$26(a2) == $FFFF` → skip (no goalie at all).
   - `clr.b $26(a2)` (clear the high byte → restores the goalie index in the low byte). Done for every team, human or CPU.
   - If the team is on controller 1 or 2 → skip.
   - `d1 = foy` → fall into `CPgoalie`. The CPU may immediately re-pull for this faceoff.

### CPgoalie (L41898-41920, ROM `$F746`)
- Purpose: CPU decision to pull. In: `a2` own team, `a1` opponent, `d1` = y to test (pucky or foy).
1. If `gsp != 2` (not the 3rd period; OT excluded) → return.
2. `diff = score(a1) - score(a2)` (`$0C` words). If `diff < 0` (leading) → return. If `diff != 2` → return. Verified `B07C 0002 6600`: the CPU pulls **only when down by exactly 2**. Port as-is (listing comment says "more than 2").
3. If `gameclock > $3C` (60 s, signed) → return.
4. `a0 = $22(a2)` (team's first object). If that object's pfgoal (`$62` bit7) = 0 → `d1 = -d1`.
5. If `d1 < 0` (defensive half) → return. `d1 == 0` passes.
6. Byte `$26(a2) = $FF`; `goto SetPersonel`.

### ReadGoaliePulled (L975229-975240, ROM `$FEFCC`)
- Purpose: flags-only query. Returns N set iff the goalie word `$26` of **a3's own team** is negative.
- `a1 = $FFC6CE` (home) or `$FFCA32` if `$62(a3)` bit6; `tst.w $26(a1)`; `movem` restore (flags kept); `rts`.
- Callers: `doshot` L37600 (shooter's **own** goalie pulled → perfect shot; probably meant the defending team, a quirk of `doshot`, not of this routine), `assdefo` L38391, `asspuckc` L39964, `assnearest` L40632 (own goalie pulled → reaction timer −1).

---

## 6. Misc routines in scope

### chkgoalie (L37366-37390, inside restorep1 L37335)
- Context: `setc1player`/`setc2player` (L37305/L37320) call `restorep1` with `d1` = old SCnum and `d0` = new SCnum, then store the **returned `d0`** as `c1playernum`/`c2playernum`. `restorep1` first returns the old player to CPU (clears its pfjoycon and sets pfna unless `$64` bit3; if the old player has `$63` bit3 (pf2np) it returns `d0 = old` and keeps control). Then for new `d0` in 0..11 (`d1 = d0*128`): if `BA_PS_flags` bit2 → `chkgoalie`; else if `word_FFC2FA` bit0 (shootout) → `chkgoalie`; else set pfjoycon on the new player. So chkgoalie only runs in penalty shot/shootout.
- chkgoalie:
  1. If the new player's position `$34 != 0` (not a goalie) → set pfjoycon on it, return.
  2. Auto-goalie flag: away (`$62` bit6) → `word_FFD05C`, else `word_FFD05A`. If 0 (manual) → set pfjoycon, return.
  3. Auto goalie: `d0 = 0` (home) or `6` (away) and return **without** setting pfjoycon on anyone. Control is redirected to SCnum 0/6.
- Quirk: SCnum 0/6 is neither checked for being on the ice nor given pfjoycon here.

### getGoalieSCnum (L36508-36528, ROM `$B86A`)
- Purpose: find a team's goalie. In: `d0` = the team's **last** SCnum (5 home, 11 away; callers `doinput` L36138, `prepshot`, L46150). Out: `d0` = goalie SCnum or `$FFFF`.
- `a0 = SortCords + d0*128`; repeat 6 times: if word `$34(a0) == 0` → return `$52(a0)`; `a0 -= $80`. None → `d0 = $FFFF`. Preserves `d1/a0`.

### assgoaliebreakwait (L38175-38202, ROM `$CAE0`)
- Purpose: assignment `$20`, park every non-participant (not only goalies) off the ice during a penalty shot/shootout. Inserted by `puckpenshot` L41350 (after setting `X = $FF10` (-240), `Y = 0`, `frame = 0`) and `sub_1592C` L51413.
1. If pfalock → return.
2. If `BA_PS_flags` bit2 clear and `word_FFC2FA` bit0 clear → `nop`, `assexit`.
3. `Xvel = Yvel = 0`. `Y (word) = $191` (401) if the object `BA_Goalie_SCnum` has pfgoal = 1, else `$FE6F` (-401). Return.

---

## 7. Dependencies (summaries; spec'd elsewhere unless noted)

### 7.1 skateto (L42953-43023): used by the CPU goalie skate-back
`$42.b -= d7`; if >= 0 → reuse `$43`. Else `$42 += $C`; `avdgoal` (adjusts target around nets); `dx = tx - (Xvel asr 8) - X`, `dy` likewise; if both within ±12 → `d0 = 9`, else `vtoa`; `jsr (a0)` (goalie: `rtss2`, no-op); `$43 = d0`. If `d0 > 7` and velocity is zero → turn one step toward the puck (`xc1/yc1` if the puck's `$63` bit0). Then `doplayeracc(zero-extended $43)` → `goalieacc`.

### 7.2 skatetopuck (L43138-43188) / skatetopuckinit (L43123): used by assgoalietopuck
Target = `puck + (vel.hi asr 1)` per axis (`move.b` high byte, `asr.b #1`). `$42.b -= d7`; if expired `+= $A`, `avdgoal`; `dx = target - GetHot.x - Xvel.hi - X` (byte math, sign-extended), `dy` likewise; `$43 = vtoa`. Goalies skip the sweep-check part (`tst $34; beq _ex`). Then `doplayeracc($43)` → `goalieacc` (turn-then-skate, SPA `$3D8`).

### 7.3 chk4pass (L40337-40455): goalie path (`threat = 1`, `$34 == 0`)
1. Random gate skipped (`threat != 0`). The skater gate would be `randomd0(16 + $70) > 12` → no pass.
2. `c = randomd0(6)` (0..5); `+6` if goalie SCnum >= 6. The goalie skips the puck-zone test.
3. No pass if: `c == SCnum`; `$34(c) <= 0`; `$63(c)` bit2; `$62(c)` bit5.
4. `ry = Y(c)`, `py = Y(goalie)`; negate both if the goalie's pfgoal = 0.
5. If `gmode` bit5 (offsides on) and `sign(ry - $58) != sign(py - $58)` → no pass.
6. If `ry <= $58` (88) and `ry - py < -15` (`$FFF1`) → no pass.
7. `passdir = vtoa(X(c) - puckx, Y(c) - pucky)`; `R = dx² + dy²`.
8. For the 6 opponent objects (`SortCords` if goalie SCnum >= 6, else `+$300`; no availability check): if `O² <= R` (unsigned) and `vtoa(O) == passdir` → no pass.
9. `dopass`; the goalie returns normally (`beq rtss2`) to `assgoaliecpu`, which continues at `_de1`.

### 7.4 check4bench (L37838-37876)
Returns at once if PS active, pfjoycon, `$63` bit4, or (`$60 < 0` and `$61 < 0`). If `$61 != $66` (another roster player should take this slot) and the current assignment is not assbench and the player is not the puck carrier: pop the caller's return, set `$63` bit2, `temp1 = 0`, `assreplace($0B assbench)`. If `$61 == $66`: pop the caller, clear `$63` bit2 and `$62` bit2, `$60 = $61 = $FF`, then `Setplass`. The "position = `$60` if `$60` >= 0" branch that follows is dead, because `$60` was just set to `$FF`. `Setplass` table (`_alist`: `$0E,$02,$02,$03,$05,$03,$05,$FF` by position 0..6).

### 7.5 Others
`SetSPA` (L43319: if `d1 != SPA` → `SPA = d1`, `SPAnum = 0`, `SPAcnt.b = $FF`), `playeracc` L43705, `stopna` L43908 (`$96` per axis per call), `vtoa` L43222, `sroot` L44215 (integer sqrt: exact floor for `D <= $640`, Newton/binary search above), `randomd0` L44190, `AddPenalty2` L45954, `SetPersonel` L51236, `dopass`, `avdgoal` L43026, `GetHot` L43282, `assinsert` L43202 (`assnum = (assnum-1)&7; asslist[assnum] = d0; set pfna`), `assexit` L43192 (`assnum = (assnum+1)&7; set pfna`), `puckgoalie` L50818 (save success and the `temp4 = 4` rebound window), `_glue` L50665 (goalie pickup: `temp5 = $8C`, or 5 after a dive).

---

## 8. Reference lists

### 8.1 SPA ids (byte offsets into SPAList, ROM `$5B1C`)

| SPA | Use | first frames (dir 0) |
|---|---|---|
| `$0002` | SPAgready (ready stance), CPU in box every loop, human in crease | `$197`… |
| `$03D8` | goalie skating (goalieacc turn-and-skate) | `$1E7-$1EA` |
| `$02F4` | dive / cover the puck (CPU rebound dive; human dive button) | `$207-$20A` |
| `$1596` | goal-against reaction, pfgoal = 0 goalie | `$2C2-$2C5` |
| `$1684` | goal-against reaction, pfgoal = 1 goalie | … `$2C6`-`$2C9` |
| `$0146` `$0178` `$0250` `$02A2` `$01EC` `$021E` `$148E` `$14C0` `$14F2` `$1544` `$01AA` | save animations (see `_saveanim`) | |

Frames tested: `$2C4`, `$2C8` (dead sfx check), `$2C5` (→ facedir 0), `$2C9` (→ facedir 4).

### 8.2 Sound
- `sfx($1C)`: `assgoaliecpu`, unreachable. No other sfx or song in the in-scope routines. `AddPenalty2(8)` plays nothing (`d0 < $E`). The puck-goalie contact sounds (`sfx $24`, song `$B`/`$D`) are in `puckgoalie`.
- Crowd: dive `crowdlevel += $96`; goaliesave `crowdlevel += $96`, `CwdExciteLvl += $0A`.

### 8.3 Random / pseudo-random inputs
- `HVcounter ($C00008) & 3 == 0`: 1-in-4 pass look per decision while holding the puck.
- `randomd0(6)`: pass receiver pick in `chk4pass`.
- `gameclock & 7` (seconds): lookahead factor 160..272 (step 27).
- `gameclock & 2`: early-shot save gate (step 32).
- `goaliesave` itself has no randomness.

## 9. UNRESOLVED / caveats
1. `findpc` time divide overflow flags (section 4): recommend "no crossing".
2. AttributeCalc (hot/cold) for `aidef` and the save ratings: not in scope; the port's setplayer should supply `$6B`, `$73`, `$76`.
3. The exact semantics of attribute bit3 (xflip) vs handedness for goalies are taken from setplayer comments only; `goaliesave` uses the raw bit.
4. `chkgoalie` redirect to SCnum 0/6 without pfjoycon: behavior is certain, intent unknown.
