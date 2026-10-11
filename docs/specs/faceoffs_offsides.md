# Faceoffs, offsides and icing: behavior spec

Source: `lst/nhl94.bin.lst` (IDA listing of NHL '94 Genesis). ROM bytes were checked against `lst/nhl94.bin`. Line numbers (Lnnnnn) refer to the listing. All coordinates use the port's rink convention: origin at center ice, +X right, +Y up the ice toward the top goal. The ROM uses the same values directly.

---

## 0. Overview: how the pieces fit together

**During play.** `pucknorm` is the puck's assignment ($18). It runs every loop for the puck object (SCnum 14):

1. If someone carries the puck, `a2touchpuck` runs for the carrier every loop. Other callers are `puckstick` (deflection), `puckbody` (puck hits a body) and `puckgoalie` (save). `a2touchpuck`:
   - records the last touch (`ltx`, `lty`, `ltplayer`);
   - updates scorer and assist bookkeeping;
   - calls `a2offsides`, which whistles offside if the toucher's team is flagged offside and the puck is deep in its attacking zone;
   - runs the icing state machine on `iflags`. If an opponent touches a puck that has been iced, icing is called. Otherwise the icing state is re-armed for this toucher.
2. If the puck is loose, `puckIChk` decides whether an armed icing has "crossed the goal line" (`ifcgl`) or is waived (the puck went in near the net).
3. `ChkOffsides` runs every loop:
   - it clears a team's offside flag once all of that team's players are back out of the zone (`sub_100A6`);
   - it sets the flag when the puck crosses a blue line while an attacker is already more than 10 px past it.

**Stoppages.** Every stoppage is entered as a "penalty" record through `AddPenalty` / `AddPenalty2`, into `PenBuf`. `checkfornewpen` then calls `Stop4Pen`. That routine stops the clock, computes the faceoff spot (`fox`, `foy`) from the stoppage type, snaps it to the dot grid, and calls `limitfo`. `limitfo` moves the spot out of the offending team's attacking zone. Only the first whistle of a stoppage sets the spot, because `Stop4Pen` skips the spot code when the clock is already stopped. When the referee sequence is done and `PenBuf` is empty, `InProgress` (L46187) gives the puck assignment $1B (`puckfaceoff`).

**Faceoff sequence.** The faceoff is driven by the puck's assignments:

1. **`puckfaceoff`** ($1B). On the first call it:
   - forces a center-ice spot after a penalty-shot or shootout goal;
   - picks a stats overlay;
   - checks for period or game end and a pending delayed penalty;
   - returns pulled goalies (`ReturnGoalies` / `CPgoalie`);
   - opens the manual line-change prompt for human-controlled teams;
   - picks the away CPU line (`CompLine`).

   Each later loop it waits for the human line-change timers. It then picks the home CPU line and switches the puck to $1C.
2. **`puckfaceoff2`** ($1C), first call (setup). It:
   - places the puck at (`fox`, `foy`) and parks the nets;
   - lines up every on-ice player from the tables `_apl` and `_ptab`;
   - gives the centers assignment $17 (`assfaceoffpl`) and everyone else $16 (`assfaceoff`);
   - picks the controlled players (`setchgplayer`);
   - opens the close-up window (`fodropx`, `fodropy`);
   - sets the drop countdown (puck `$40`) to 180..299 loops.
3. **`puckfaceoff2`**, later calls. Each loop the countdown drops by 1. `updatefaceoff` animates the referee in the close-up window. When the countdown goes below zero, **`Endfaceoff`**:
   - decides the faceoff winner from the two centers' close-up animation frames, set by button timing, plus a random number. **No player ratings are used.**
   - sends the puck off in the winner's pull direction (joystick or random) with a bias toward the winner's own end;
   - returns the puck to `pucknorm`.
4. **Centers.** While the faceoff is on, `assfaceoffpl` copies the center's animation frame into `fofdata`. For the CPU it also picks between a "ready" animation ($1014) and a "pull" animation ($FEA). A human center gets these animations from `faceoffinput` (the B button). Once the faceoff ends, each center gets `nopuck` = 20 and pops its assignment.
5. **Faceoff win stat.** The faceoff-won stat is credited later, by `puckstick:_glue`, to whichever team first gains possession.

---

## 1. Globals and tables used

### RAM globals
Addresses are from `src/stubinc/ram_addrs.inc`.

| Name | Address | Meaning |
|---|---|---|
| `fox`, `foy` | $FFBF94, $FFBF96 | Faceoff spot X and Y in rink pixels. |
| `fodir1`, `fodir2` | $FFBF98, $FFBF9A | Joystick word latched each loop by the human faceoff center. `fodir1` belongs to the team with pfgoal=0 (shoots at the bottom goal); `fodir2` to the team with pfgoal=1. -1 = none. The low nibble is the direction 0..7, or 8 for none; bits 4..7 are held buttons. |
| `fodropx`, `fodropy` | $FFB032, $FFB034 | **Screen** pixel origin of the faceoff close-up window (sprites are drawn at sprite offset + $80 + fodrop). These are not rink coordinates. |
| `fofdata` (`dword_FFBDA8`) | $FFBDA8 | 3 x {word frame, word VDP attribute}: +0 home center, +4 away center, +8 referee (`word_FFBDB0`). Drawn by `checkfo` (L52017) while `disflags` bit 4 is set. |
| `iflags` (byte) | $FFBF80 | Icing flags. bit0 `ifcgl` = crossed goal line; bit1 `ifdir` = 1 means the puck must cross the top line; bit2 `ifok` = icing armed. |
| `icingPlayer` (byte) | $FFBF81 | SCnum of the last touch that armed icing (the byte at `$53` = low byte of SCnum). |
| `ltx`, `lty`, `ltplayer` | $FFBF7C, $FFBF7E, $FFBF7A | Last touch X, Y and SCnum. |
| `gmode` | $FFC2EA | bit0 gmclock (play stopped), bit1 gmdir (0 = home attacks the top goal, i.e. home pfgoal=1), bit2 gmpen, bit3 gmpendel, bit4 gmhl (highlight), bit5 gmoffs (offsides on), bit6 (period-over request; jumps to PeriodOver). |
| `sflags2` | $FFC2EE | bit0 faceoff in progress, bit1 ref refresh, bit2 don't record, bit4 shot taken, bit5 power play, bit6 pp team. |
| `sflags3` | $FFC2F0 | bit0 line-change box shown, bit4 "faceoff just ended; credit the next possession", bit7 set at start of periods 1-2 (mid-period music trigger). |
| `byte_FFC2FE` | $FFC2FE | bit0 next faceoff at center (after a penalty-shot or shootout goal), bit4/bit6 music change pending, bit7 one-timer flag. |
| `byte_FFC2FC` | $FFC2FC | bit0 faceoff stats overlay pending, bit4 option: CPU picks lines for human teams too / no manual line prompt (UNRESOLVED name). |
| `word_FFD6BE` | $FFD6BE | Overlay id requested for the next faceoff (negative = none). |
| `word_FFD6B4` | $FFD6B4 | Overlay id currently shown (-1 = none). Affects drop time. |
| `PenBuf` | $FFC3A4 | Up to 32 words: byte0 = stoppage/penalty code, byte1 = SCnum (bit 7 = "called"). Zero-terminated. |
| `tmap` / `tmsize` | $FFC6F2 / $FFCA56 | Players on ice including the goalie (4..6) for home / away. These are team-struct offset `$24`. |
| `HmShots` / `AwShots` | $FFC6CE / $FFCA32 | Home / away team structs (away = home + $364). |
| puck `$40`/`$42`/`$44`/`$46` | $FFB78A.. | While `puckfaceoff` runs: home/away line-change timers and the SCnum of the player choosing. In `puckfaceoff2`: `$40` = drop countdown (`word_FFB78A`). |

### Team struct fields used
Offsets are from `HmShots`/`AwShots`:

| Offset | Meaning |
|---|---|
| `$0C` | Score. |
| `$0E` | Faceoffs won. |
| `$16` | tmline, the current line: 0 Sc1, 1 Sc2, 2 Chk, 3 PP1, 4 PP2, 5 PK1, 6 PK2. |
| `$18` | Word: pnum of the last toucher (the potential scorer). |
| `$1A` | Assist 1. |
| `$1C` | Assist 2. |
| `$22` | tmsort: address of the team's first player struct. |
| `$24` | tmap. |
| `$26` | tmgoalie ($FFxx = pulled). |
| `$30` | Flags: bit1 line change used this stoppage, bit3 "skip assist shift once", bit4 **team is offside**. |
| `$32+2*pnum` | Energy (via `getlinee`). |
| `$16A+8*line` | Line rosters. |

### Player struct fields beyond the preamble list (NHL94-specific)
- `$75` = Chk rating.
- `$76` = **handedness: 1 = left, 0 = right**. Set in `setplayer` at L51694-51696. Note: the preamble's "$74 handed" is not right for 94. `$74` holds the fight bits (Chk/Hnd byte & $E).
- `$5E` byte = `nopuck`: the player cannot pick up the puck while it is non-zero. It is decremented by d7 each loop in `updateplayers` (L35464).

### Tables dumped in full
The tables `_apl`, `_ptab` (puckfaceoff2), `_ftab` (Endfaceoff), `_hl1` and `_al1` (CompLine), `priolist`, `FaceOffsprites`, the faceoff SPA data, the overlay table `unk_FECE6` and `dirtab` are dumped in full in the routine sections below.

---

## 2. Offsides

### ChkOffsides (L42598)
- **Purpose:** set or clear each team's "offside" flag (team `$30` bit 4) from the puck crossing a blue line.
- **Caller:** `pucknorm` every loop (a3 = puck), right after `puckIChk`. This runs even when play is stopped, because the gmclock test in `pucknorm` comes later.
- **Inputs:** `gmode` bits 5 and 1, `BA_PS_flags` bit2, puck `$14` (Ypos high word) and `$20` (OldYpos high word), and both teams' player structs (position `$34`, Ypos `$14`).
- **Output:** team `$30` bit 4.

Logic:
```
if !(gmode.bit5 gmoffs) return
if BA_PS_flags.bit2 (breakaway/penalty-shot mode) return
a1 = HmShots; a2 = AwShots
sub_100A6(team = AWAY)            ; maybe clear away flag
sub_100A6(team = HOME)            ; maybe clear home flag   (after exg: a1=away, a2=home)
Y = puck.Y ; oldY = puck.OldY
if Y >= 84 ($54):                        ; signed
    if oldY >= 84: return                ; only when crossing upward this loop: oldY < 84 <= Y
    line = 94 ($5E)
    team = (gmdir==0) ? HOME : AWAY      ; the team attacking the TOP goal
    for each of the team's 6 structs (tmsort, +$80):
        if position < 0: continue
        if player.Y > 94 (signed; "cmp.w $14(a0),d0 / bge skip" i.e. skip if 94 >= Y):
            team.$30 |= bit4; return
    return
else (Y < 84):
    if Y > -84: return                   ; need Y <= -84
    if oldY <= -84: return               ; need oldY > -84  (crossing downward)
    line = -94
    team = (gmdir==1) ? HOME : AWAY      ; the team attacking the BOTTOM goal
    for each of 6 structs:
        if position < 0: continue
        if player.Y < -94 (skip if -94 <= Y): team.$30 |= bit4; return
    return
```
Notes:
- The blue line is at |y| = 84. A player must be more than 10 px past it (|y| > 94, strict) for the team to be flagged. "Past" is tested in absolute Y for the team attacking that end.
- The goalie slot (position 0) is included in the scan; it never qualifies in practice.
- The test fires on any puck crossing, carried or loose. The flag alone does not whistle anything; `a2offsides` does.
- The team offside flag is also read by the AI (`assdefo` L38402, L38485, L38635 and others) and cleared by `resetplstuff` (L53671), which runs at faceoff setup. The linesman "offside" signal (sflags2 bit 7) is handled separately by `checkob` (around L40500), which is out of scope.

### sub_100A6 (L42663)
- **Purpose:** clear team a2's offside flag once every on-ice player is back at or behind 88 px of attacking depth (the "tag up").
- **Input:** a2 = team struct.
- **Output:** team `$30` bit 4 cleared.
```
if !(team.$30 bit4) return
d1 = 5 ; a0 = team.tmsort
loop:
   if a0.position >= 0:
       d0 = a0.Y
       if a0.pfgoal == 0: d0 = -d0        ; d0 = depth toward this player's attacking goal
   ; (position < 0: d0 is NOT reloaded; keeps the previous value)
   a0 += $80
   if d0 > 88 ($58, signed): return       ; dbgt exits; the bgt that follows returns: still offside
   d1--; until d1 == -1
team.$30 &= ~bit4
```
- **Quirk:** for an off-ice slot the depth from the previous slot is reused. For the very first slot it is stale register content (whatever `d0` held in `pucknorm`). See UNRESOLVED.
- The clear threshold is 88. This differs from the set threshold (94) and the blue line (84). Port as-is.

### a2offsides (L42687)
- **Purpose:** whistle offside when a player of a flagged team touches the puck deep in its attacking zone.
- **Caller:** `a2touchpuck` on every touch, including every loop while carrying.
- **Inputs:** a2 = toucher, `pucky`, `gmode`.
```
if !(gmode.bit5) return
d = pucky; if a2.pfgoal == 0: d = -pucky          ; puck depth in toucher's attacking direction
if d < 104 ($68, signed) return
team = a2.pfteam ? AwShots : HmShots
if !(team.$30 bit4) return
if gmode.bit4 (highlight) return
AddPenalty(code $10 = Off-side, a3 = toucher)
```
`AddPenalty` (L45939) returns, so nothing happens, when any of these hold: the clock is already stopped; `OptPen` == 0 (penalties off also disables offside); the toucher's `$63` bit 2 is set. Otherwise, with gmoffs on, it goes to `AddPenalty2`, which appends `{$10, toucher SCnum}` to `PenBuf`. The record at code $10 is "Off-side" (byte0 delay 1, byte1 minutes 0).

---

## 3. Touch bookkeeping and icing

### a2touchpuck (L42716)
- **Purpose:** called whenever player a2 touches the puck. It records the last touch, does scorer/assist bookkeeping, checks offside, and runs icing.
- **Callers:** `pucknorm` (each loop for the carrier), `puckstick` (L50609), `puckbody` (L50774), `puckgoalie` (L50868).
- **Outputs:** `ltx`, `lty`, `ltplayer`; team `$18`/`$1A`/`$1C`; team `$30` bit 3; `byte_FFC2FE` bit 7; `sflags2` bit 4; `iflags`; `icingPlayer`. It may call `AddPenalty`.

```
ltx = a2.X ; lty = a2.Y ; ltplayer = a2.SCnum
team = a2.pfteam ? AwShots : HmShots
d0 = a2.pnum ($66, byte, zero-extended)
if a2.pflags3 bit3 (one-timer): byte_FFC2FE |= bit7
if team.$18 != d0:
    if (team.$30 bit3) was clear:       ; bclr #3 then bne
        team.$1C = team.$1A ; team.$1A = team.$18
    else: (bit3 now cleared; no shift)
    team.$18 = d0
    if team.$1C == d0: team.$1C high byte = $FF  ("st" = $FFxx, i.e. none)
sflags2 &= ~bit4 (shot taken)
a2offsides()
; ---- icing ----
if (iflags & ifok) && (iflags & ifcgl) && a2.position != 0 (not goalie):
    if iflags & ifdir:                  ; puck had to cross TOP goal line (icing team attacks top)
        if a2.pfgoal == 0 -> ICING      ; toucher attacks bottom = opponent
        else -> NOTICE
    else:
        if a2.pfgoal == 1 -> ICING
        else -> NOTICE
else -> NOTICE

ICING (_icing):
    a3 = SortCords + icingPlayer*128            ; the player whose touch armed icing
    AddPenalty(code $C = Icing, a3)             ; icing skips the OptPen gate
    return

NOTICE (_notice):                               ; re-arm icing for this toucher
    iflags(byte) = 0
    icingPlayer = a2.SCnum (low byte)
    if a2.pfgoal == 1: iflags |= ifdir ; d = -pucky
    else: d = pucky
    if d < 0: return          ; puck must be in toucher's own half (pucky>=0 when pfgoal=0, pucky<=0 when pfgoal=1; 0 counts)
    d = tmap(home) - tmap(away) ; if a2 is away: d = -d
    if d < 0: return          ; shorthanded team cannot ice
    iflags |= ifok
```
- When a goalie touches the puck while icing is pending, icing is waived: the code takes NOTICE and re-arms icing for the goalie.
- A touch by the icing team's own skater also re-arms icing (NOTICE).
- Flag semantics on the early returns: the N flag comes from `move.w pucky` or `neg.w`. `btst`/`bset` do not change N. On those returns `iflags` may be left as `ifdir` only, without `ifok`, which is harmless.
- Icing is checked every loop while carrying, so effectively "the last touch before the puck leaves the stick" arms it.

### puckIChk (L42796): support routine, needed for icing
- **Caller:** `pucknorm` every loop (just before `ChkOffsides`).
```
if !(iflags & ifok) return
if iflags & ifcgl return
if puckc >= 0 return                   ; puck must be loose
if iflags & ifdir:  if pucky < 264 ($108) return      ; needs pucky >= 264
else:               if pucky >= -264 return            ; needs pucky < -264 (strict; asymmetric with the top)
if puckx > 44 ($2C) or puckx < -44 ($FFD4):  iflags |= ifcgl     ; crossed goal line wide of the net: icing pending
else: iflags &= ~ifok                                               ; crossed between |x|<=44: icing waived
```
The `cmp`/`bgt`/`blt` comparisons are signed.

---

## 4. Where the next faceoff happens

### Stoppage codes
Each code is an even byte offset into `PenaltyList` (L56708, ROM $18E0C). Each record holds byte0 = delay before stopping (x32 into `Pencntdwn`), byte1 = penalty minutes (0 = whistle only), then text.

| Code | Record text | Raised by | a3 passed (used by limitfo) |
|---|---|---|---|
| 2 | "Period Over" | clockcont | |
| 4 | "Game Over" | clockcont | |
| 6 | "Face Off" (PenOOP) | `wallcollb2` L50134: puck out of play over the glass; a3 = `ltplayer`. Also `pucknorm` L42575: a loose puck stationary for 121 loops; a3 = **the puck**. | ltplayer / the puck |
| 8 | "Face Off" (PenGhold) | Goalie freeze: `assgoaliecpu` L39193, `assgoaliectrl` L39047 and L38982 (goalie out of range); also `CheckBump` L50086 | goalie / object |
| $A | (no text) | `sub_F2F4` L41595, end of a breakaway or penalty-shot sequence | |
| $C | "Icing" | `a2touchpuck` | the icing team's shooter |
| $E | (no text) = goal | `checkgoal` L49959 (a3 = first player of team a1) | |
| $10 | "Off-side" | `a2offsides` | offending toucher |
| $12..$3C | real penalties | checking code and `FallDown` (L49478: roughing, followed by an immediate `bra Stop4Pen`) | penalized player |
| $14 | (no text) | `FallDown` L49473: injury stoppage | |

### Flow from whistle to faceoff
- `checkfornewpen` (L46358) runs every loop. For each `PenBuf` entry: if gmpen is not yet set, a whistle (minutes 0) calls `Stop4Pen` at once. A real penalty calls `Stop4Pen` when the puck carrier is on the penalized team; otherwise it becomes a delayed penalty (gmpendel).
- After the referee animation, `InProgress` (L46187) pops the entries. When `PenBuf` is empty (`loc_123A2`):
  - it recomputes each team's `tmap` (`sub_123DE`: 6 minus the players serving non-coincidental penalties, minimum 4);
  - clears gmpen;
  - assigns the puck $1B (`puckfaceoff`), or $1E if `BA_PS_flags` bit 3 is set.

### Stop4Pen (L46411): scope limited to faceoff location
- **Input:** a0 = `PenBuf` entry + 2. So `-2(a0)` = code and `-1(a0)` = SCnum byte.
- **Callers:**
  - `checkfornewpen` (`_callit`);
  - `puckfaceoff` and ROM $ED32, only when gmpendel is set (the clock is already stopped there, so the spot code is skipped);
  - `FallDown` L49480. Here a0 is not a `PenBuf` pointer; see UNRESOLVED.

```
was_stopped = gmode.bit0 ; gmode.bit0 = 1
if was_stopped: goto skipfo                ; first whistle wins the spot
x = 0 ; y = 0
if code == $E (goal):            -> clamp
x = ltx ; y = lty
if code == 6 (OOP):              -> clamp
x = puckx ; y = pucky
if code == $C (icing):
    p = SortCords + sext8(-1(a0))*128     ; icing team's player (ext.w: if bit7 of the byte were set this would be negative)
    y = (p.pfgoal == 0) ? +600 : -600     ; $258: the icing team's own end
clamp:
  ox = x                                   ; original x saved (movem to stack; (sp) = x)
  if x >= 70 ($46):  x = 70
  if x <= -70 ($FFBA): x = -70
  if y >= 166 ($A6):  y = 206 ($CE);  x = (ox >= 0) ? 70 : -70
  if y <= -166 ($FF5A): y = -206 ($FF32); x = (ox >= 0) ? 70 : -70
  fox = x ; foy = y
  limitfo()
skipfo:
  Pencntdwn = 0 ; gmode.bit2 (gmpen) = 1 ; sub_1A304 ; sfx 3 (whistle) ; SetPA($A = PenWhistle)
```
- **Important:** if |y| < 166, `foy` is the raw y and `fox` is the clamped x. Neutral-zone faceoffs are not snapped to dots unless `limitfo` moves them.
- **Rounding:** none here, because whole pixels are used (high words).

### limitfo (L46482)
- **Purpose:** never hold a faceoff in the attacking zone of a team that caused a stoppage. Applies to any team that has an entry in `PenBuf`.
```
a0 = PenBuf
do:
   p = SortCords + (byte1 & $7F)*128
   if p.pfgoal == 1:           ; p attacks top
       if foy >= 88 ($58): foy = 65 ($41);  fox = (fox >= 0) ? 70 : -70
   else:
       if foy <= -88:        foy = -65 ($FFBF); fox = (fox >= 0) ? 70 : -70
   a0 += 2
while word(a0) != 0
```
- The first entry is processed unconditionally. The loop stops at the first zero word, which can be a cleared duplicate entry in the middle of the buffer.
- **Quirk:** a puck-idle stoppage (code 6 raised by `pucknorm`) has the **puck** (SCnum 14) as its "player", so its `$62` bit 7 is used as pfgoal. If that bit is 0 (assumed; nothing sets bit 7 on the puck), an idle-puck faceoff at foy <= -88 is moved to (±70, -65), but one at foy >= 88 is not.

### Faceoff dot coordinates
| Spot | (x, y) |
|---|---|
| Center ice | (0, 0) |
| End-zone dots | (±70, ±206) |
| Neutral-zone dots (only through limitfo) | (±70, ±65) |
| Anything else | (clamp(x,−70,70), y) with −166 < y < 166 |

### Next faceoff spot by stoppage type
| Stoppage | Spot |
|---|---|
| Period start | (0,0). `StartPer` L29867 clears `fox`/`foy` and assigns the puck $1B. |
| Goal (code $E) | (0,0). |
| Goal or end in penalty shot / shootout | `checkgoal` sets `byte_FFC2FE` bit0 and `puckfaceoff` clears `fox`/`foy` to (0,0). |
| Offside ($10) | Puck position at whistle time, clamped. Then limitfo with the offender: the puck is at depth >= 104 in the offender's attacking zone, so the spot always becomes the neutral dot (±70, ±65) on the attacking side, x sign = sign of the clamped puck x (x = 0 counts as +). |
| Icing ($C) | End-zone dot in the icing team's defensive zone: y = +206 if the icing team attacks the bottom, else −206. x = +70 if puckx >= 0 at whistle time, else −70. limitfo does not move it. |
| Penalty (called) | Clamped puck position at the moment `Stop4Pen` runs: immediately if the offender's team has the puck, otherwise when the delayed penalty is triggered. limitfo then moves it out of the penalized player's attacking zone (\|y\| >= 88) to (±70, ±65). |
| Puck out of play over the glass (6) | Clamped last-touch position (`ltx`, `lty`). limitfo uses `ltplayer`'s team. |
| Puck idle 121 loops (6) | Clamped `ltx`/`lty`. limitfo uses the puck object (quirk above). |
| Goalie freeze (8) | Clamped puck position. Usually \|y\| >= 166, giving the end-zone dot on the puck's x side (x >= 0 → +70). |
| Injury ($14) / roughing with immediate call | Clamped puck position (but see UNRESOLVED for the `FallDown` a0). |

---

## 5. Faceoff sequence

### puckfaceoff (L41627): puck assignment $1B
- **Purpose:** pre-faceoff bookkeeping and line changes.
- **a3:** the puck. Uses puck `$40`/`$42` (line-change timers) and `$44`/`$46` (the human player choosing).

Every call:
```
byte_FFC2FE &= ~bit4
if word_FFC2FA.bit0 (shootout):  puckvx = puckvy = 0 ; assreplace($1E puckshootout) ; return
if !bclr(puck.$62 bit1 pfna): goto WAIT          ; not the first call
```
First call only (pfna was set):
1. If `byte_FFC2FE` bit0 was set: clear it, and set `fox = foy = 0`.
2. Clear `byte_FFC2FC` bits 7, 6 and 2, `padcont`, `dword_FFBE7E` and `dword_FFBE82`. Call `sub_FECF8`, which is a no-op: its only branch, `bne.w *+4`, targets the next instruction.
3. **Stats overlay.** If `word_FFD6BE >= 0`, `d0 = word_FFD6BE`; else `d0 = sub_FECAA()`. Then `sub_FE53C(d0)`: set `byte_FFC2FC` bit0 and `word_FFD6BE = d0`. `sub_FECAA` (L974897):
   ```
   i = randomd0(100) & 7
   id = [3,5,3,1,5,2,3,3][i]              ; table unk_FECE6 (words)
   if fox <= -64 ($FFC0) and foy <= 192 ($C0): id = 6
   ```
   The overlay content is cosmetic; it only matters for the drop time (see `puckfaceoff2`).
4. Clear `word_FFC2F8` bit1 and `word_FFC2FA` bit1.
5. End checks:
   - `gameclock == 0` → `jmp PeriodOver`;
   - `gmode` bit6 → `PeriodOver`;
   - `gsp == 3` (overtime) and `HmGoals != AwGoals` → `loc_7B5C` (game end).
6. If gmpendel (`gmode` bit3) is set → `jmp Stop4Pen`. The clock is already stopped, so this only does the whistle, gmpen and `SetPA` without touching the spot. The penalty manager later re-assigns $1B.
7. **Mid-period music (cosmetic).** All of these must hold: `gameclock < PerTimeTotal>>1` (asr; unsigned compare), `gameclock >= 60`, `sflags3` bit7 was set (bclr), gmclock set, `byte_FFC2FE` bit6 clear. Then `HmTeam = HomeTeam`, `SongIndex = 2`, `ChooseSong`, and set `byte_FFC2FE` bit4.
8. `ReturnGoalies` (see below). Puck `$40` and `$42` = $FFxx (st; negative = inactive).
9. If `OptLine == 0` (line changes on):
   - Clear `$30` bit1 on both teams (`byte_FFC6FE`, `byte_FFCA62`). Clear pf2lcm (`$63` bit3) on all 12 skaters.
   - If `cont1team | cont2team` and horizontal mode (`sflags` bit7): `forceblack`, set `sflags` bit6, `ClrHor`, `palcount = $18`. Then, if `OptLine == 0` and `byte_FFC2FC` bit4: `palcount = 0`.
   - For `c1playernum` and `c2playernum` (if >= 0): `sub_F5C6`, below.
   - `sub_F590(d0 = 2, a2 = AwShots, a1 = HmShots)`: CPU away line.
10. Fall through to WAIT.

**sub_F5C6 (L41759).** a3 = player SCnum d0, a2 = puck.
```
clear pf2lcm
SetLCmode(player)           ; L36566: if OptLine!=0 or byte_FFC2FC.bit4 -> nothing;
                            ; if team.$30 bit1 already set -> nothing; else set it, set pf2lcm, draw line box
if pf2lcm now set:
   if player is away (pfteam): puck.$42 = $168 (360) ; puck.$46 = SCnum
   else:                       puck.$40 = $258 (600) ; puck.$44 = SCnum
```
**Quirk:** the home team gets 600 loops to choose a line and the away team gets 360.

**sub_F590 (L41740).** d0 = team id (1 home, 2 away); a2 = team to set; a1 = opponent.
```
if OptLine != 0 return
if !byte_FFC2FC.bit4: if d0 == cont1team or d0 == cont2team return     ; human team
CompLine(a2, a1) ; SetPersonel(a2) ; PrintScores1 ; word_FFC304 = $2710
```
**WAIT (`loc_F612`, L41786).** Runs on every call, including the first:
```
sub_F64E($40) ; sub_F64E($42)
if puck.$40 >= 0 or puck.$42 >= 0: return            ; a human is still choosing
sub_F590(d0 = 1, a2 = HmShots, a1 = AwShots)         ; CPU home line (sees away's new tmline)
word_FFD6C6 = $FFFF
assreplace($1C puckfaceoff2)
```
**sub_F64E(off) (L41805).**
```
if puck.off < 0 return
p = player puck.(off+4) ; team = p.pfteam ? AwShots : HmShots
if p.pf2lcm clear: puck.off = $FFxx ; sub_B92E (line-box UI) ; return
puck.off -= d7 ; if >= 0 return
if p.pf2lcm: lcfound(d2 = 0) ; sub_B92E      ; timeout picks choice 0 (getlchoice maps 0..2 to a line)
```
With no human selecting a line, the whole of `puckfaceoff` finishes in one loop.

### ReturnGoalies (L41876) / CPgoalie (L41898): only as called from puckfaceoff
```
for (team, opp, id) in [(Home, Away, 1), (Away, Home, 2)]:
   if team.$26 == $FFFF: continue          ; no goalie at all
   clr.b $26(team)            ; byte at $26 = HIGH byte of the word -> $00xx: goalie returns (done for human teams too)
   if id == cont1team or id == cont2team: continue
   CPgoalie(d1 = foy):
     if gsp != 2 (not 3rd period) return
     diff = opp.$0C - team.$0C ; if diff < 0 return ; if diff != 2 return     ; only when exactly 2 behind (cmp.w #2 / bne)
     if gameclock > 60 return
     if team's first struct pfgoal == 0: d1 = -d1
     if d1 < 0 return                      ; faceoff in own half
     team.$26 high byte = $FF (pull) ; SetPersonel(team)
```
The listing comment says "exit if behind by more than 2", but the code exits unless the team is behind by exactly 2.

### CompLine (L41923): CPU line choice
- **Inputs:** a2 = team to set, a1 = opponent.
- **Output:** a2.`$16` (tmline).
- `getlinee(line)` (L47394) returns the average energy (`$32+2*pnum`) of the skaters that line would put on ice. It uses `priolist` order over `tmap` entries and skips position 0. Unsigned `divu`; only the low word is used.

`priolist` (L57829, bytes): `0, 1, 2, 4, 3, 5, 6, $FF`. Positions in order of importance: G, LD, RD, C, LW, RW, extra attacker.

```
diff = a2.tmap - a1.tmap
if diff != 0:                         ; special teams
   L = (diff > 0) ? 3 (PP1) : 5 (PK1)
   a2.tmline = (getlinee(L) >= getlinee(L+1)) ? L : L+1        ; signed compare, tie -> first
   return
if a2 is HmShots ($C6CE):
   row = 0
   if gsp == 2 and a2.$0C != a1.$0C:  row = (a2.$0C > a1.$0C) ? 1 : 2     ; leading : trailing (3rd period)
   cand = _hl1[row*7 + a1.tmline]        ; react to opponent's current line
   if getlinee(cand) > $C00 (unsigned): a2.tmline = cand ; return
   ; else fall through to the away algorithm
AWAY:
   row = 0 ; if gsp == 2 and scores differ: row = (a2 leading) ? 1 : 2
   for i in 0..2: cand = _al1[row*3 + i]; if getlinee(cand) > $C00 (unsigned): break
   a2.tmline = cand                      ; the 3rd candidate if none qualifies
```
The comments mention 3/4 and 19/20 of $1000, but the code uses $C00 in both places.

Table `_hl1` (L41973, words), row = 7 entries indexed by the opponent's tmline (0 Sc1, 1 Sc2, 2 Chk, 3 PP1, 4 PP2, 5 PK1, 6 PK2):
| row | opp 0 | 1 | 2 | 3 | 4 | 5 | 6 |
|---|---|---|---|---|---|---|---|
| 0 (normal) | 0 | 1 | 2 | 0 | 1 | 0 | 1 |
| 1 (home leading, 3rd) | 2 | 0 | 1 | 2 | 0 | 2 | 0 |
| 2 (home trailing, 3rd) | 0 | 1 | 0 | 0 | 1 | 0 | 1 |

Table `_al1` (L42017, words), row = 3 candidates in order:
| row | c0 | c1 | c2 |
|---|---|---|---|
| 0 (normal) | 0 | 1 | 2 |
| 1 (leading, 3rd) | 0 | 2 | 1 |
| 2 (trailing, 3rd) | 0 | 1 | 0 |

Other caller: `sub_E1F4+60`, an in-play line change (out of scope).

### puckfaceoff2 (L42031): puck assignment $1C
**First call** (pfna set): the setup, done entirely within one loop.
1. Clear `BA_PS_flags` bits 2 and 5, `word_FFC2F4` bits 0 and 1, and `DelayedPen` bits 0, 1 and 2. Save registers, `forceblack`, wait until `disflags` bit0 is clear, save SR. Set `word_FFD412 = 60` (post-faceoff input timer, used by `doinput`; out of scope).
2. If `fox == 0 && foy == 0`: `word_FFD6BE = $FFFF` (no overlay at center ice). Otherwise `move #$2700,sr`, which disables interrupts until the setup ends.
3. `crowdlevel = min(crowdlevel, 600)`.
4. Flags:
   - `disflags` bit3 = 1;
   - `sflags` bit0 = 0 (unpause);
   - `sflags3` bit0 = 0;
   - `glovecords = 0`;
   - `iflags` byte = 0 (**no icing pending**);
   - `RefCnt = -1`;
   - `puckcross2 = puckcross6 = -1` (no goalie reactions);
   - `sflags2`: bit1 = 0, **bit0 = 1 (faceoff in progress)**, bit2 = 1;
   - `passplayer = onetimerplayer = -1`;
   - `disflags` bit4 = 1 (show the close-up sprites);
   - `ClrHor` (vertical rink);
   - `word_FFC304 = $2710`;
   - `Vpos = Hpos = 0`.
5. Puck:
   - `puckx = fox`, `pucky = foy` (high words);
   - `puckz` byte = $FF (negative: hidden);
   - `puckvx = puckvy = puckvz = 0`;
   - `puckc = -1`.
6. Nets (objects 12 and 13): Xvel = Yvel = 0, X = 0, Y = +268 ($10C) and −268 ($FEF4). Puck shadow (object 15): frame = $18A (SPFpuck), SPA = 0, attribute = 0. Puck attribute = 0.
7. Clear `sflags` bit6. Call `checkwindow` 101 times (`moveq #$64` + `dbf`) to scroll to the spot. `yleader = 60`.
8. `ResetBench`. `SetPersonel` and `forcepldata` for home, then for away. `resetplstuff`, which clears the team offside flags and `$63` of all players.
9. **Line-up loop** over objects 0..11:
```
X = -240 ($FF10) ; Y = 0 ; frame = 0           ; high words only
pos = $34 ; if pos < 0: continue (stays parked at (-240, 0))
if pos != 0 (not goalie):
   if pos == 4 (center):
       team = pfteam ? AwShots : HmShots          ; (listing comment says pfgoal, the code tests $62 bit6 = pfteam)
       team.$18 = pnum (word) ; byte_FFC2FE &= ~bit7 ; team.$1A, team.$1C high byte = $FF ; team.$30 &= ~bit3
       assinsert($17 assfaceoffpl)
   else: assinsert($16 assfaceoff)
row = 6 - (pfteam ? tmsize : tmap)            ; 0, 1 or 2
e = _apl[row*8 + pos]                          ; spot index 0..6
(dx, dy) = _ptab[e]
if pfgoal == 0: dx = -dx ; dy = -dy
if pos == 0 (goalie): X = dx ; Y = dy (absolute)
else:
   if e <= 2 (byte offset e*4 <= 8; LD/RD spots, also e=0):
       if (fox XOR dx) < 0:  dy -= foy >> 3     ; asr (floor); only when dx's sign differs from fox's sign (fox=0: when dx<0)
       dx -= fox >> 2                             ; asr (floor)
   X = dx + fox ; Y = dy + foy
Xvel = Yvel = 0
facedir(high word) = vtoa(puckx - X, pucky - Y)   ; face the puck
$63 bit2 (pf2unav) = 0 ; $62 bit5 (pfalock) = 0
SetSPA($50C SPAglide)
```
   The goalie keeps its existing assignment: no assinsert. Its SPA is also set to $50C.

   Table `_apl` (ROM $FCEE, L42328, bytes; 3 rows x 8, indexed by position 0..7):
   | row (tmap) | pos0 G | 1 LD | 2 RD | 3 LW | 4 C | 5 RW | 6 extra | 7 |
   |---|---|---|---|---|---|---|---|---|
   | 0 (6 on ice) | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 0 |
   | 1 (5 on ice) | 0 | 1 | 5 | 3 | 4 | 2 | 0 | 0 |
   | 2 (4 on ice) | 0 | 3 | 5 | 1 | 4 | 0 | 0 | 0 |

   Table `_ptab` (ROM $FD06, L42352, word pairs dx,dy; before the pfgoal flip, i.e. for a team attacking the top):
   | e | spot | dx | dy |
   |---|---|---|---|
   | 0 | goalie (absolute) | 0 | −250 ($FF06) |
   | 1 | LD | −35 ($FFDD) | −50 ($FFCE) |
   | 2 | RD | +35 ($23) | −50 |
   | 3 | LW | −50 ($FFCE) | −10 ($FFF6) |
   | 4 | C | 0 | −15 ($FFF1) |
   | 5 | RW | +50 ($32) | −10 |
   | 6 | extra attacker (position 6, goalie pulled) | 0 | −60 ($FFC4) |

   Who is on ice: `SetPlList` takes `priolist[0..tmap-1]`, or `priolist[1..tmap]` with no goalie.
   - **tmap 6:** G, LD, RD, C, LW, RW; or LD, RD, C, LW, RW, extra with no goalie.
   - **tmap 5:** G, LD, RD, C, LW. On row 1 the RD lines up on the **RW spot**.
   - **tmap 4:** G, LD, RD, C. On row 2 the LD takes the LW spot and the RD the RW spot.
   - Without a goalie at tmap 5/4, positions 3 and 5 map through the same rows (row1: pos5 → RD spot; row2: pos3 → LD spot).
   - Position 6 only occurs at tmap 6 without a goalie.

   A copy of both tables also exists at ROM $F2C0/$F2D8, used by `puckpenshot` (out of scope).

   Worked example at center ice, team attacking the top: G (0,−250), LD (−35,−50), RD (35,−50), LW (−50,−10), C (0,−15), RW (50,−10). The opponent mirrors this through the origin.
10. `SprSort`; `setchgplayer`.
11. Graphics loads: `sub_11738(unk_55BFE)`, `word_FFB01C = ExtraChars` base, `sub_11738(unk_A78B6)`. These are the close-up sprite tiles.
12. Overlay: `word_FFD6B4 = -1`. If `byte_FFC2FC` bit0 and `word_FFD6BE >= 0`: `sub_FE510(word_FFD6BE)` sets `word_FFD6B4 = id`, clears some overlay vars, and sets `word_FFD6BE` = $FFxx.
13. **Close-up window placement.**
    - `fodropx = (fox >= 0) ? $36 (54) : $BE (190)`. The window goes on the side of the screen opposite the dot.
    - `printx = (fodropx − $2E) >> 3` (asr), giving 1 or 18.
    - `fodropy = $5C (92)`; `printy = ($5C − $44) >> 3 = 3`.
    - Draw `FaceOffMap` (`dobitmap`, 12 x 10 characters).
    - If `OptLine == 0`, draw a 12 x 3 box with both line names from the `FaceOffsprites` strings. Top/bottom order: if gmdir == 0 the away line is printed first, then the home line at `printx + 4`; otherwise home first.
14. **Drop countdown:**
```
t = randomd0(120) + 180                ; 180..299
if word_FFD6B4 in {0, 1, 5, 4, 2}: t = max(t, 270 ($10E))   ; "cmp #$10E / bgt keep"
puck.$40 = t
```
    So center-ice faceoffs have no overlay and t = 180..299. Overlay ids 3 and 6 also impose no minimum.
15. `palcount = $18`.
16. **`fofdata` initialisation:**
    - home: frame 1, attr $8000;
    - away: frame 4, attr $A800;
    - referee: frame 7, attr $8000.
    - If gmdir == 0 (home attacks the top), XOR the home and away attributes with $800, giving home $8800 and away $A000.
    - So the center of the team attacking the top always has the H-flip bit ($800) set.
17. `fodir1 = fodir2 = $FFFF`.
18. `sub_FF7E2`: sets `sflags2` bit5 (power play) and bit6 (PP team) when `tmap(home) != tmap(away)`, and starts power-play music (cosmetic). Then, if `byte_FFC2FE` bit6 or bit4 was set (both cleared): `song(SongNum)`. `palcount = $18`. Restore SR and registers.

**Later calls** (`_nna`, L42356):
```
puck.$40 -= 1                     ; NOT scaled by d7
if puck.$40 >= 0: updatefaceoff ; return
sub_FE548: word_FFD6B4 = -1, byte_FFC2FC &= ~bit0
Endfaceoff
```
Timing: the setup happens in loop S. Centers first run `assfaceoffpl` in loop S+1, seeing countdown N. The drop (`Endfaceoff`) happens in loop S+1+N. Objects update in SCnum order 0..15, so in any loop the centers read the countdown before the puck decrements it. In the drop loop D the centers see 0.

### setchgplayer (L42370)
```
c1playernum = c2playernum = -1
if cont1team: changeplayer(d4 = 0)
if cont2team: changeplayer(d4 = 2)
if cont3team: save cont1team, c1playernum; cont1team = cont3team; c1playernum = -1; changeplayer(0);
              c3playernum = c1playernum; cont3team = cont1team; restore c1playernum, cont1team
if cont4team: the same with cont2team / c2playernum / d4 = 2 -> c4playernum
```
`changeplayer` jumps to `chgplayer` (L976652). It picks the controller team's available skater (position > 0, not pf2unav, not controlled by the other pad) nearest to (puckx + puckvx>>8, pucky + puckvy>>8). At a faceoff that point is (`fox`, `foy`), so the center (15 px from the dot) is normally chosen.

### assfaceoff (L38206): assignment $16, non-center skaters
```
if $62 bit5 (pfalock): return
if !(sflags2 bit0): assexit          ; faceoff over: pop back to the previous assignment
return                               ; otherwise stand still
```

### assfaceoffpl (L38218): assignment $17, the two centers
```
if pfalock: return
if !(sflags2 bit0):  nopuck($5E byte) = $14 (20) ; assexit ; return     ; runs once, the loop after the drop
if bclr(pfna): $40 = 0
slot = fofdata + (pfteam ? 4 : 0)
frame = (SPAnum($5A) lsr 2) + 1
if $76 == 0 (right-handed): frame += 3          ; lefty 1..3, righty 4..6
slot.frame = frame                                ; written EVERY loop, before any SPA change below
if $62 bit3 (pfjoycon, human): return
if bset($63 bit1 pf2aip) was already set: return  ; animation still running
d1 = $FEA (pull)
if puck.$40 (word_FFB78A) > 16 (unsigned; "cmpi #$10 / bls keep"):
    if randomd0(8) != 0: d1 = $1014 (ready)       ; 7/8 ready, 1/8 pull while far from the drop
set pf2aip ; SetSPA(d1)
```
The CPU always starts a pull ($FEA) once the countdown is <= 16 and its previous animation has ended.

### faceoffinput (L36529): human center
- **Caller:** `doinput+CA`, when `sflags2` bit0 is set. `doinput` is called only for the player a pad controls, so the c1..c4 player.
- **Inputs:** from `ReadJoyN`:
  - d0 = held direction (`jdtab`: 0..7, 8 = none) | held buttons (bits 4..7);
  - d1 = newly pressed buttons (bit4 = B per the listing comments).
```
if word_FFC2F6 bit6: return                     ; never set (per comment at chgplayer)
if asslist[assnum] != $17: return               ; only the faceoff center
(pfgoal ? fodir2 : fodir1) = d0 (word)          ; latched every loop
if $63 bit1 (pf2aip): return
if d1 bit4 (B newly pressed):  set pf2aip ; SetSPA($FEA)
else:                          SetSPA($1014)    ; no pf2aip; restarts only when the SPA differs, i.e. after it ended
```
The listing comment "branch if pressed" on `beq glb_B8E8` is inverted. `beq` is taken when bit 4 is clear, i.e. not pressed.

### Faceoff animations
Data at `SPAlist` + SPA, `SPAlist` = ROM $5B1C. Played by `updateanim` (L35703). Attribute word `$10` = 0 for both, so they do not loop.

**$FEA (pull), at $6B06.** Direction offsets: dir0 = $12, dirs 1..7 = $1E.

| idx | dir0 SPF | dirs 1-7 SPF | time |
|---|---|---|---|
| 0 | $0001 | $0015 | 2 |
| 1 | $0102 | $010A | 10 |
| 2 | $0101 | $0109 | −6 (last) |

**$1014 (ready), at $6B30.** dir0 = $12, others = $16. One entry: SPF $0001 (dir0) or $0015 (others), time −5 (last).

With d7 = 1, `updateanim` runs before input and the assignment. If the SPA is set (SetSPA) in loop s, the frame index `assfaceoffpl` writes at loop t is:

| Loops after s | Index | `_ftab` bonus |
|---|---|---|
| s .. s+3 | 0 (for a human press; for the CPU, loop s still shows the previous animation's index) | 0 |
| s+4 .. s+14 | 1 | 8 |
| s+15 .. s+21 | 2 | 16 |
| s+22 onward | animation over, SPA cleared, SPAnum 0 → index 0 | 0 |

At s+22 pf2aip is clear again. The ready animation $1014 occupies loops s..s+6 and its successor can start at s+7.

### updatefaceoff (L42414)
```
c = puck.$40                         ; after this loop's decrement
if c == 0: goto hide
d = (c + 6) lsr 3
if d > 2 (signed): return
word_FFBDB0 (referee frame) = 10 - d
hide (loc_FDDE, L42427):
   disflags &= ~bit4                 ; stop drawing the close-up sprites
   printz control string 00 06 BF 00 00 00 (mis-disassembled in the listing)
   printx = (fodropx - $2E) asr 3 ; printy = (fodropy - $44) asr 3
   eraser(width 12, height 13, tile $7FF)
```
(A dead `moveq #$64,d0` sits between `printx` and `printy`.)

Referee frame by countdown: c >= 18 → 7 (initial); 10..17 → 8; 2..9 → 9; 1 → 10; 0 → window erased. The drop happens the next loop.

### Endfaceoff (L42445)
**Purpose:** drop the puck, pick the winner and launch the puck.
```
sfx($2F)
sflags2 &= ~bit0                       ; faceoff over
word_FFD412 = 60
sub_11738(unk_5C410)                   ; restore tiles
sflags2 &= ~bit2 ; gmode &= ~bit0 (clock runs) ; puck.$63 &= ~bit0 ; word_FFC304 = 0
sflags3 |= bit4                        ; next possession gets the faceoff-won credit
; ---- winner ----
d3 = fodir1 ; d4 = +$800
a1 = fofdata (home entry)
d2 = 16
d2.b -= _ftab[home.frame - 1]
d2.b += _ftab[away.frame - 1]
r = randomd0(33)                       ; 0..32
if !(d2 <= r) (unsigned byte compare): a1 = away entry     ; HOME WINS iff r >= d2
if a1.attr bit 11 ($800, H-flip = the team attacking the top): d3 = fodir2 ; d4 = -$800
; ---- pull direction ----
if d3 bit3 set (no direction, or -1):              RANDOM
else: dir = d3 & 7 ; if (VDP HV counter word & 3) == 0: RANDOM else use dir   ; 3/4 joystick, 1/4 random
RANDOM: dir = (randomd0(5) - 2) & 7               ; {6,7,0,1,2}
        if d4 >= 0: dir ^= 4                       ; {2,3,4,5,6}
puck.Xvel = dirtab[dir].x << 5
puck.Yvel = (dirtab[dir].y << 5) + d4
puck.Zvel = randomd0($800)             ; 0..2047
puckz = 0 ; puck.$62 &= ~bit2 (pfnc)
assreplace($18 pucknorm)
```
`_ftab` (ROM $FF06, L42513, bytes, indexed by close-up frame − 1):

| frame | 1 | 2 | 3 | 4 | 5 | 6 |
|---|---|---|---|---|---|---|
| bonus | 0 | 8 | 16 | 0 | 8 | 16 |

`dirtab` (L43933; already ported) as (x, y), with the value after `<<5` in brackets:

| dir | x | y |
|---|---|---|
| 0 | 0 | 200 [6400] |
| 1 | 141 [4512] | 141 [4512] |
| 2 | 200 [6400] | 0 |
| 3 | 141 | −141 |
| 4 | 0 | −200 [−6400] |
| 5 | −141 | −141 |
| 6 | −200 | 0 |
| 7 | −141 | 141 |

`d4` = ±2048 ($800) is added to Yvel.

### Faceoff win formula (exact)
- `hb` and `ab` = `_ftab` bonus of the home and away center's close-up frame in the drop loop. Each is 0, 8 or 16 and depends only on the center's animation index at that moment.
- `d2 = 16 − hb + ab` (range 0..32). `r = randomd0(33)` is uniform over 0..32.
- **Home wins iff r >= d2.** P(home) = (33 − d2)/33.

| | hb=0 | hb=8 | hb=16 |
|---|---|---|---|
| **ab=0** | 17/33 | 25/33 | 33/33 |
| **ab=8** | 9/33 | 17/33 | 25/33 |
| **ab=16** | 1/33 | 9/33 | 17/33 |

- **No player ratings** (faceoff, Chk, Stk or other) are read by `assfaceoffpl`, `faceoffinput`, `puckfaceoff2` or `Endfaceoff`. Handedness only selects frames 1-3 versus 4-6, which carry the same bonuses. The only bias is the tie case: home wins 17/33 when bonuses are equal.

**Human timing.** Let k = countdown value the center sees in the loop where B is newly pressed. Equivalently, k loops remain before the drop loop. The animation must be free: not mid-$FEA.

| k | Index at drop | Bonus |
|---|---|---|
| 0..3 | 0 | 0 |
| 4..14 | 1 | 8 |
| 15..21 | 2 | **16** |
| >= 22 | animation finished | 0 (can press again) |

Referee cue: the frame on screen during loop D−k was set in the previous loop, from c = k after decrement. So:
- pressing while referee frame 7 shows means k >= 18 (k 18..21 → 16);
- frame 8 means k = 10..17 (k 15..17 → 16, k 10..14 → 8);
- frame 9 means k = 2..9 (k 4..9 → 8, k 2..3 → 0).

Not pressing at all leaves frame 1/4, bonus 0.

**CPU timing** (emerges from `assfaceoffpl`):
- While the countdown is > 16 it keeps choosing ready (7/8, 7 loops long) or pull (1/8, 22 loops long).
- At the first loop where it is free with countdown C <= 16, it starts a pull, which gives bonus 16 if C is 15..16 and 8 if C is 4..14.
- A pull begun at C in 17..21 gives 16. One begun at C in 22..25 ends at or just before the drop, giving 0.

The port should reproduce the per-loop mechanics rather than these summaries.

**Winner's pull.**
- `d4` pushes the puck toward the winner's own end: −Y for the team attacking the top.
- A human winner holding a direction sends the puck along that joystick direction (rink coordinates; vertical mode is forced) plus `d4`, 3 times out of 4.
- A CPU winner, or a human holding no direction, gets a random direction from the winner's **forward** half (−90°..+90° around its attacking direction) plus the backward `d4` bias. **Port as-is.** For example, dir 0 for the top-attacking winner gives Yvel = 6400 − 2048 = +4352.

**Hardware randomness.** The VDP HV counter test is a hardware read. Port as a uniform 2-bit random: 0 → random direction.

### After the drop
- The puck is loose (`puckc` = −1) and pops up (Zvel 0..2047). In the next loop each center's `assfaceoffpl` sets `nopuck` = 20 and pops back to its previous assignment. Because the puck object updates later in the same loop, **the centers cannot touch the puck for 20 loops** (`checkpuckcoll` L50317 requires `$5E` == 0). The other skaters' `assfaceoff` pops at once.
- **Faceoff-won stat** (`puckstick:_glue`, L50665). When a player gains possession (`puckc` set): `opp` = the other team. `opp.$1A` and `opp.$1C` = $FFxx, and `opp.$30` bit3 is set. If `sflags3` bit4 was set (bclr), then:
  - the possessing team's `$0E` (faceoffs won) += 1 and `crowdlevel` += 200;
  - the sound value becomes $C; if the possessing team is home, `CwdExciteLvl` += 10 and the value is $B (then `bsr song`).

  So the recorded faceoff winner is whoever first gets possession, not the `Endfaceoff` coin flip.

### FaceOffsprites (L57600): what it is
Despite the name, it is a table of 7 line-name strings, not sprite data. Each entry is 6 bytes: word $0006 (entry length), 3 ASCII characters, NUL. Iterated with `Adda1Offset`, so entry i is at +6i:

| i | 0 | 1 | 2 | 3 | 4 | 5 | 6 |
|---|---|---|---|---|---|---|---|
| name | "Sc1" | "Sc2" | "Chk" | "PP1" | "PP2" | "PK1" | "PK2" |

These are the names for tmline 0..6. They are printed in the faceoff window (`puckfaceoff2` step 13) and the line-change box (`sub_B92E`, `sub_85EE`). It is followed by `unk_191D0`: "LD", "RD", "LW", "C", "RW".

---

## 6. Quirks to port as-is
1. **Drop countdown speed.** The countdown decrements once per loop, but animation counters subtract d7. With d7 > 1 the button-timing windows shift.
2. **Neutral-zone spots.** Faceoffs with \|y\| < 166 use the raw y. Only x is clamped to ±70 unless `limitfo` snaps them to (±70, ±65).
3. **Puck-idle stoppage.** It uses the puck struct as the "player" in `limitfo`, so only the bottom zone gets moved.
4. **`puckIChk` asymmetry.** Top goal line `pucky >= 264`; bottom `pucky < −264`.
5. **Offside thresholds.** The flag sets at depth > 94 on a puck crossing at 84 and clears only when every player is at <= 88. `sub_100A6` reuses the previous depth for off-ice slots.
6. **Penalties-off disables offside.** `OptPen == 0` makes `AddPenalty` return before the offside path. Icing bypasses this gate.
7. **Line-change timeouts.** Home 600 loops, away 360 loops.
8. **`CPgoalie`.** Pulls only when exactly 2 behind, in the 3rd period, with <= 60 s left, and the faceoff is in the opponent's half. `ReturnGoalies` returns every pulled goalie at each faceoff, human teams included.
9. **Random pull direction.** The no-joystick pull lies in the winner's forward half while `d4` biases it backward.
10. **Faceoff-won stat.** It goes to the first team to gain possession, not to the `Endfaceoff` winner.
11. **Stop4Pen on an already-stopped clock** keeps the first spot. It still whistles, sets gmpen and calls `SetPA`.
12. **Interrupts during setup.** For non-center faceoffs the setup runs with interrupts disabled (`move #$2700,sr`). Not observable in a port.
13. **Music flag cleared while waiting.** `byte_FFC2FE` bit4 (music change) is cleared at the top of every `puckfaceoff` call. If a human takes more than one loop to choose a line, the mid-period music change set on the first call is lost before `puckfaceoff2` (cosmetic).

## 7. UNRESOLVED
1. **Initial `d0` in `sub_100A6`.** When the first tmsort slot is off-ice (position < 0), the depth compared is whatever `d0` held on entry from `pucknorm`: puckc, a GetHot-derived x, or ±264 from `puckIChk`. Recommendation: treat the missing value as "not deep" (0).
2. **`Stop4Pen` from `FallDown` (L49480).** a0 is not set to a `PenBuf` entry (traced back about 50 lines with no load), so `-2(a0)` and `-1(a0)` are arbitrary bytes. Assume the default branch: clamped puck position. `limitfo` still scans `PenBuf` correctly.
3. **Overlay ids.** The meaning of ids 0..6 in `word_FFD6BE`/`word_FFD6B4` and why ids {0,1,2,4,5} force a 270-loop minimum drop time were not traced into the overlay renderer (`sub_FE510` callers). The id selection rule is given exactly; the content is cosmetic.
4. **`byte_FFC2FC` bit4** (makes the CPU pick lines for human teams and suppresses the manual prompt): the option name or menu source was not traced.
5. **`word_FFD412`** (set to 60 at setup and at the drop): it gates `doinput`'s player-switch and goalie-switch code and writes $1111 to `word_FFBF06`/`word_FFBF08` on expiry. Its exact input effect is outside this scope.
6. **The `printz` control string `00 06 BF 00 00 00`** in `updatefaceoff` (also `00 06 FF 00 00 00` at puckfaceoff2 $FB58). Print-attribute codes, not decoded.
7. **`sub_1A304`** (called by `Stop4Pen` and `checkgoal`) was not identified.
