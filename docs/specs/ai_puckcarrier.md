# CPU puck carrier AI and breakaways (asspuckc family)

Source: `lst/nhl94.bin.lst`, lines 39775-40556, plus the helpers named below. All line numbers refer to that listing.
Coordinates follow the port conventions: X right, Y up, the top goal is +Y. "attackY" in this spec means `Y` when the player shoots at the top goal (`pflags $62` bit 7 `pfgoal` = 1) and `-Y` when he shoots at the bottom goal (pfgoal = 0). With attackY, +264 is the attacked goal line and +88 is the attacked blue line.

## 1. Overview: how the routines fit together

Assignment ids are indexes into `asstab` (L56671; full dump in section 2.4). The ids used here are $10 `asspuckc`, $11 `assnearest`, $12 `assshoot`, $0E `assgoaliecpu`, $21 `chkpuckc` and $22 `assbreakaway`.

1. `assnearest` ($11) runs for the skater nearest the puck. When that skater becomes the puck carrier, three cases apply:
   - A goalie jumps to `assgoaliecpu`.
   - A CPU skater (pflags bit 3 `pfjoycon` = 0) gets `assinsert($10)`, which pushes `asspuckc` on top of `assnearest`.
   - A human carrier stays in `assnearest`.
   `assnearest` also detects breakaways for human carriers and swaps itself to `assbreakaway` ($22).
2. `asspuckc` ($10) is the CPU carrier's brain. It runs every frame:
   - **Breakaway detection.** It calls `BreakawayOffsidesFlagSet`. If a breakaway starts, it does `assreplace($21 chkpuckc)`, plays the "ding", and updates stats and crowd.
   - **Decision tick.** Every `aioff+1` frames (fewer when the own goalie is pulled or the crowd record is broken), it calls these in order: `checkob` (delayed-offside ref) -> `sub_E1F4` (tired line: CPU line change plus dump-in shot) -> `chk4shot` (shoot, PK clear, or flip-clear pass) -> `chk4pass` (pass to a random teammate). A shot ends the assignment through `compshoot`. A pass ends it through `dopass` + `assexit`.
   - **Movement**, every frame that did not end the assignment. `skateto` steers toward one of 4 spots in front of the attacked net (`_postab2[6..9]`, chosen randomly when the assignment starts). While the delayed-offside signal is up, it steers to a neutral-zone spot (`_postab2[position]`) instead. Every 12 frames `skateto` calls the evade callback `loc_E12C`. That callback counts nearby opponents into the global `threat` and turns the carrier's direction away from the last opponent found.
3. `chkpuckc` ($21) is the CPU carrier's assignment during a breakaway. Each frame `breakaway()` tests that the carrier still skates toward the end he is in (sign of Ypos XOR Yvel). If so, `asspuckc`'s body runs with the breakaway bit kept. If not, the bit is cleared, the slot reverts to $10 and `asspuckc` runs. A carrier on a breakaway always runs `chk4shot`. `chk4shot` makes him shoot once |pucky| > 130+rand(30).
4. `assbreakaway` ($22) is the human carrier's breakaway assignment: `breakaway()` + `assnearest`.
5. Shooting: `compshoot` stores the windup length (frames) in temp2 and `assreplace($12 assshoot)`. `assshoot` then drives `SetShotMode` / `ShotMode` (holds the windup until temp2 < 0, then releases the "C button") -> `prepshot` -> `doshot`. This spec does not cover those.
6. Passing: `dopass` (L36924, the body of `passmode`) -> `passto`. With `word_FFC2F6` bit 3 set, `dopass` does a flip / clear lob instead: `sub_F67E4` picks the target and `sub_F6778` computes the velocity and calls `puckflip`.
7. `EvadePC` is the skateto callback that **teammates** use (assdefo, assdefd, asswingo, asscentero) to get out of the carrier's way. It is unrelated to the carrier's own evade callback `loc_E12C`.
8. `getBAplayerInfo` (via `PenShotChk`) records who was fouled on a breakaway, so that a penalty shot can be awarded.
9. Penalty shot (BA_PS_flags bit 2) and shootout (`word_FFC2FA` bit 0) modes reuse `asspuckc` with the decisions replaced by `sub_FE8EC` (shoot or not) and the target replaced by a scripted waypoint path (`sub_FE864`). There is no evasion and no passing in these modes. A shootout spec should cover them; this spec gives only enough to port `asspuckc`'s branches.

### 1.1 Behaviour summary (what the CPU carrier does)

**Decision timing.**
- `temp1` (byte $40) counts down by d7. When it goes negative, the carrier makes one decision and temp1 reloads to `aioff`, minus 1 when the own goalie is pulled, or minus 1 when the crowd record is broken and temp1 != 0.
- The first decision happens on the first frame of the assignment.

**Shoots** (every case goes through `compshoot` -> `assshoot`):
- **(a) Penalty-kill clear.** All of these hold:
  - his team is killing a penalty;
  - `threat` != 0;
  - (HV & 3) == 0;
  - his own attackY > -88 (he is not in his defensive zone).
- **(b) Breakaway.** The breakaway bit is set and |pucky| > 130 + randomd0(30), so the threshold is 130..159. Before shooting, facedir gets a random -2..+1 added.
- **(c) Normal.** randomd0(N) <= 7 when spodds is odd, or <= 8 when spodds is even.
  - N = (32 - spodds/2) * 16 when the puck is more than 100 px from the attacked goal-line centre (0, 264).
  - Otherwise N = (32 - spodds/2) * 2^k, where k is the number of opposing non-goalies whose direction from the puck equals the puck->goal direction.
  - N = 1 (always shoot) if the opposing goalie has "anim in progress" ($63 bit 1).
  - Extra conditions: puck attackY in [0, 264], and the offside-signal flag is not up.
  - For an all-CPU team, `chk4shot` runs only on frames where vcount bit 1 == 0. This gate is skipped on a breakaway or when a human controller is on the team.
- **(d) Dump for a line change.** All of these hold:
  - auto-line-change flag clear (byte_FFC2FC bit 4);
  - puck attackY in [0, 88];
  - (HV & 3) == 0;
  - $63 bit 3 clear;
  - average energy of the team's on-ice skaters <= $C00.
  In that case the CPU calls `CompLine` / `SetPersonel` / `PrintScores1` and then shoots.
- **Windup length** in temp2: min((264 - puck attackY) >> 3 (logical shift), 20) frames.

**Passes:**
- **(a) PK flip clear.** Same gate as shoot case (a), but when his own attackY <= -88 (in his own zone). The flip is `dopass` with the flip flag. Afterwards `chk4pass` still runs in the same frame and may pass again (quirk).
- **(b) Normal (`chk4pass`).**
  - Gate: if `threat` == 0, only when randomd0(16 + spodds) <= 12. If `threat` != 0, always.
  - Receiver: a random slot of his own team, randomd0(6).
  - The pass is rejected when any of these hold:
    - the slot is the carrier himself;
    - the receiver is a goalie or off the ice;
    - the receiver has $63 bit 2 or pfalock set;
    - the puck is within |x| <= 40 and |y| > 204 (either end);
    - offsides are on and the receiver and carrier are on different sides of the attacked blue line;
    - the receiver is at attackY <= 88 and more than 15 px behind the carrier;
    - an opponent at the same or shorter distance lies in the same 8-way direction from the puck.
  - Otherwise `dopass` is called with `passdir` = direction to the receiver, then `assexit`.

**Skates** (every frame), using `skateto`:
- The target is `_postab2[6 + temp3]` (temp3 = HV & 3, picked once when the assignment starts), negated when attacking the bottom goal. The 4 spots are (-40,240), (0,220), (20,230), (30,230) in attack coordinates.
- While the delayed-offside ref is up (sflags2 bit 7), the target is `_postab2[position]` instead (neutral-zone spots).
- `skateto` recomputes the heading every 12 frames.

**Evades:**
- At each 12-frame heading update, `loc_E12C` checks each of the 6 opposing objects.
- Collision test: opponent position + (vel >> 8) against puck position + (carrier vel >> 8). An opponent is counted when it is within ±20 px on both axes.
- For each counted opponent, `threat` += 1 and the heading becomes the 8-way direction from that opponent to the carrier.
- If the carrier is facing straight at that opponent (facedir ^ 4 == that direction), the heading is rotated by +0 or +1 at random.
- The last counted opponent wins.

## 2. Globals, ratings and tables

### 2.1 Globals read/written

| Name | Meaning in these routines |
|---|---|
| `puckc` (word) | carrier SCnum, negative = none. `dopass` writes $FFFF. |
| `puckx`, `pucky`, `puckvx`, `puckvy` | puck struct fields. `.b` reads of `puckvx`/`puckvy` take the **high byte**. |
| `threat` (word) | count of opponents near the carrier. Cleared and counted by `loc_E12C`. Set to 1 by `assgoaliecpu` (L39271) before it calls `chk4pass`. Read by `chk4shot` and `chk4pass`. |
| `passdir` (word) | pass direction 0-7. Written by `chk4pass`, read by `dopass`. |
| `sflags2` | bit 5 power play in progress, bit 6 PP team (0 home, 1 away), bit 7 `sf2offsig` (delayed offside "little ref" shown) |
| `gmode` | bit 0 clock stopped, bit 5 offsides rule on |
| `BA_PS_flags` | bit 2 penalty shot in progress (also used for "PS or SO"), bit 3 penalty-shot info pending (set by `getBAplayerInfo`) |
| `word_FFC2F6` | bit 2: "this frame's asspuckc/assnearest was entered from `breakaway()`". Set by `breakaway`, consumed with `bclr` by `asspuckc` and `assnearest`. Bit 3: next `dopass` is a flip / clear (consumed by `dopass`). |
| `word_FFC2FA` | bit 0 shootout mode, bit 1 shootout/PS attempt live |
| `byte_FFC2FC` | bit 3 PS/SO waypoint path at final node. Bit 4 set at game start when `OptLine` == 2 (the third line-change option; OptLine is then forced to 0). Bit 6 current crowd meter >= crowd record. |
| `word_FFC31A` | penalty-shot start countdown (frames) |
| `word_FFD454` | PS/SO shot clock (starts at $19 = 25) |
| `word_FFDA16` / `word_FFDA18` | PS/SO waypoint X / Y. High byte $80 in DA16 = path finished. |
| `word_FFDA1C` | PS/SO "close enough to shoot" radius |
| `cont1team`, `cont2team` | team (1 home, 2 away, 0 none) of controllers 1 and 2. `cont3team` and `cont4team` are **not** checked. |
| `vcount` | vblank counter; bit 1 of its low byte is used as a coin flip |
| `VDP_CNTR` ($C00008) | HV counter, read as a cheap random number. The port should use a uniform random of the same width (`& 3` -> 0..3, `& 1` -> 0..1). |
| `CwdExciteLvl`, `crowdlevel` | crowd excitement; += $14 and += $C8 when a breakaway starts |
| team struct (`$FFFFC6CE` home, `$FFFFCA32` away, size $364) | +$26 goalie in net ($FFFF = none or pulled), +$358 breakaway-attempts stat, +$22 low word of the first SCstruct pointer, +$32 + 2*pnum energy per roster slot |
| `RefCnt` | referee graphic state; `PushRef` is called only when it is negative |
| `OptPen` | penalties option (0 = off) |
| `BA_Sktr_SCnum`, `BA_Team`, `BA_Skater_Offset`, `BA_Goalie_SCnum`, `BA_Goalie_Offset`, `BA_Checker_Offset` | written by `getBAplayerInfo` |

### 2.2 Per-object fields used

- $00 Xpos, $14 Ypos, $28 Xvel, $2A Yvel.
- $34 position.
- $36 assnum, $38 asslist.
- `temp1` $40, `temp2` $42, `temp3` $44:
  - temp1: decision countdown in its **high byte** $40.
  - temp2: skateto countdown in its high byte $42 and stored heading in its low byte $43. `assshoot` uses temp2 as a whole word for the windup frames.
  - temp3: target spot 0-3.
- $52 SCnum, $54 facedir (integer part = high word).
- $62 pflags: bit 1 pfna, bit 3 pfjoycon, bit 5 pfalock, bit 6 pfteam, bit 7 pfgoal.
- $63 pflags2: bit 1 anim in progress, bit 2 (93 equate name `pf2dw`; the 94 listing comments in dopass call it "player unavailable"), bit 3 (93 equate `pf2np`, "no joystick pad").
- $64 pflags3: bit 0 "was outside the attack zone" (named offside flag), bit 1 breakaway.
- $66 pnum.
- Ratings $6A, $6E, $70 (section 2.3).

### 2.3 Ratings

All ratings come from `setplayer` L51556 and are clamped to 0..30 ($1E) by `checkattriblimits`, except where stated.

| Field | 94 meaning | Used here |
|---|---|---|
| $6A `aioff` | `((((OfA + PP + PK + HomeAway + 3rdPeriod bonuses, clamped 0..30) >> 1) ^ $F) + $F) >> 1`, so the range is **7..15**. A higher Offensive Awareness gives a smaller number. | Reload value of the decision countdown in `asspuckc` (and in `assnearest` for non-carriers). |
| $70 `spodds` | "PS Bias" (pass/shoot bias), 0..30, with a double 3rd-period bonus | `chk4shot`: `32 - spodds/2` base, and bit 0 picks the 7/8 threshold. `chk4pass`: gate range `16 + spodds`. Higher values mean more shots and fewer passes. |
| $6E `passacc` | Pas, 0..30 | Not read here. `dopass` reads it: `passspeed = ((passacc*4)>>1) + $A0`, plus `>>4` of that when passacc is odd. |
| $6C `shotspd` | ShP, 0..30 | Not read here. `ShotMode` (L37444) reads it: if shotspd < 20 ($14) and SPAnum > 8, the windup releases automatically. |
| $71 `stickhand` | Stk | **Not read by any routine in this spec.** It is used by the collision / puck-strip code (L49190, L50567-50639). |

### 2.4 Tables

**`_postab2`** (L40102, 10 entries of (X, Y) words, read by `asspuckc`; target = entry, negated when pfgoal = 0):

| idx | X | Y | used when |
|---|---|---|---|
| 0 | $FF9C = -100 | $FFEC = -20 | never (position 0 = goalie never runs asspuckc) |
| 1 | $0064 = 100 | $FFEC = -20 | offside signal, position 1 (L.def) |
| 2 | $FF88 = -120 | $0028 = 40 | offside signal, position 2 (R.def) |
| 3 | $0014 = 20 | $0028 = 40 | offside signal, position 3 (L.wing) |
| 4 | $0078 = 120 | $0028 = 40 | offside signal, position 4 (center) |
| 5 | $FFEC = -20 | $0028 = 40 | offside signal, position 5 (R.wing) |
| 6 | $FFD8 = -40 | $00F0 = 240 | normal, temp3 = 0 |
| 7 | $0000 = 0 | $00DC = 220 | normal, temp3 = 1 |
| 8 | $0014 = 20 | $00E6 = 230 | normal, temp3 = 2 |
| 9 | $001E = 30 | $00E6 = 230 | normal, temp3 = 3 |

**`asstab`** (L56671, longword jump table; the dispatcher in `updateplayers` L35669 calls `asstab[asslist[assnum]]` once per object per frame):

| id | routine | id | routine | id | routine |
|---|---|---|---|---|---|
| $00 | $15464 | $0C | asspenalty | $18 | pucknorm |
| $01 | assdefo | $0D | assdopen | $19 | puckshadow |
| $02 | assdefd | $0E | assgoaliecpu | $1A | puckunflip |
| $03 | asswingd | $0F | assgoalietopuck | $1B | puckfaceoff |
| $04 | asswingo | $10 | asspuckc ($DF18) | $1C | puckfaceoff2 |
| $05 | asscenterd | $11 | assnearest ($E6F4) | $1D | assgoaliectrl |
| $06 | asscentero | $12 | assshoot | $1E | puckshootout |
| $07 | assscore | $13 | asspassrec | $1F | puckpenshot |
| $08 | assstanley | $14 | assfight | $20 | assgoaliebreakwait |
| $09 | assben | $15 | assfwatch | $21 | chkpuckc |
| $0A | assepen | $16 | assfaceoff | $22 | assbreakaway |
| $0B | assbench | $17 | assfaceoffpl | $23 | assonetimer |

**`unk_1913A`** (L57492, 24 words, read by `PenShotChk`, the caller of `getBAplayerInfo`; indexed by d0 = the byte offset of a penalty in `PenaltyList`):

| offset | value | | offset | value |
|---|---|---|---|---|
| $00-$12 (10 words) | $FFFF each | | $1C | $002E |
| $14 | $0038 | | $1E | $0030 |
| $16 | $003C | | $20 | $0034 |
| $18 | $0036 | | $22-$2E (7 words) | $FFFF each |
| $1A | $003A | | | |

A value >= 0 is the `PenaltyList` offset of the penalty-shot version of that penalty, and $FFFF means no penalty shot. See the UNRESOLVED note in `getBAplayerInfo`.

**`vtoa._dt`** (L43262) is already ported. vtoa preserves d2/a0, clobbers d1, and does not touch d3-d5.

### 2.5 Random helpers

- `randomd0` (L44190): returns 0..d0-1.
  - Seed update: `seed = seed * $BB40E62D + 1` (32-bit, at `RNGseed`).
  - Result: `(((seed >> 8) & $FFFF) * range) >> 16`.
- `randomd0s` (L44178): `randomd0(2*d0) - d0`, which is -d0..d0-1.

## 3. Routines

### breakaway (L39775)

- **Purpose:** each frame, check that a breakaway carrier is still skating toward the end he is in. On the first frame of a new assignment it also does the breakaway "ding", stat and crowd update.
- **Callers:** `chkpuckc`+$14 (bsr) and `assbreakaway` (jsr).
- **Inputs:** a3 (Ypos $14, Yvel $2A, pflags $62).
- **Outputs:**
  - `word_FFC2F6` bit 2 set.
  - pflags bit 1 cleared.
  - Possibly the team stat +$358, `CwdExciteLvl` and `crowdlevel`.
  - Return: **N flag**. N=0 means continue the breakaway; N=1 means end it. d0 = Ypos XOR Yvel, or Ypos when Yvel = 0. d1 is preserved.

```
set bit 2 of word_FFC2F6
if bclr(pflags bit1 pfna) was set:            ; new assignment
    sfx(1)                                    ; "ding"
    team = (pflags bit6 == 0) ? $FFFFC6CE : $FFFFCA32
    team.$358 += 1                            ; breakaway attempts
    CwdExciteLvl += $14 (20)
    crowdlevel   += $C8 (200)
if Yvel == 0: return N=1                      ; (move.w #$FFFF,d1)
d0 = Ypos XOR Yvel ; return N = sign(d0)      ; i.e. N=1 when Ypos and Yvel have opposite signs
```

- **Quirks:**
  - Ypos = 0 counts as positive.
  - The test ignores pfgoal and relies on the carrier already being in the attack zone.
  - A stopped carrier (Yvel = 0) ends the breakaway.
  - `movem.w (sp)+,d1` does not change the flags, so N comes from `eor` or `move.w #$FFFF`.

### BreakawayOffsidesFlagSet (L39808)

- **Purpose:** maintain pflags3 bit 0 ("outside the attack zone") and detect the moment a carrier enters the attack zone with no non-goalie skater ahead of him. That moment is a breakaway.
- **Callers:** `asspuckc`+$44 and `assnearest`+$30 (jsr). Both call it only when the carrier's breakaway bit is clear and BA_PS bit 2 is clear.
- **Inputs:** a3; all 12 skater objects (objects 0-11).
- **Outputs:**
  - pflags3 ($64) bits 0 and 1.
  - Return: **Z flag**. Z=1 means no new breakaway; Z=0 means the breakaway bit was just set.
  - d0, d1 and a0 are preserved. The internal `move.w #1/#0,d0` exists only to set Z, and `movem` restores d0.

```
if pflags bit1 (pfna) set: clear pflags3 bit0 and bit1
if |Ypos| >= $108 (264): return Z=1                  ; at/behind a goal line (signed compare)
if pfgoal == 1: inZone = (Ypos >  $58)               ; > 88
else:           inZone = (Ypos <= -$58)              ; <= -88   (note: asymmetric at exactly 88)
if !inZone: set pflags3 bit0; return Z=1
; inZone:
wasOutside = pflags3 bit0; clear pflags3 bit0
if !wasOutside: return Z=1                           ; only the crossing frame counts
for obj = object 11 down to object 0 ($FFFFB5CA, step -$80, 12 iterations):
    if Ypos(a3) >= 0:   ahead = obj.Ypos > Ypos(a3)
    else:               ahead = obj.Ypos < Ypos(a3)
    if ahead and obj.position != 0: return Z=1       ; any non-goalie ahead (either team, incl. position<0)
set pflags3 bit1 (breakaway); return Z=0
```

- **Quirks:**
  - The "ahead" test uses the sign of the carrier's Ypos, not pfgoal.
  - Teammates ahead also cancel the breakaway.
  - Objects with a negative position (off ice) count as blockers.
  - The carrier himself is never "ahead".
  - A carrier who gets the puck already inside the zone (bit 0 clear) gets no breakaway.

### chkpuckc (L39886, assignment $21)

- **Purpose:** the CPU carrier's assignment while on a breakaway.
- **Callers:** dispatcher (asstab $21). Only `asspuckc` installs it.

```
if word_FFC2FA bit0 (shootout) or BA_PS_flags bit2 (pen. shot): goto revert
call breakaway()
if N == 0: goto asspuckc            ; keep $21; asspuckc sees word_FFC2F6 bit2 and keeps the breakaway bit
revert:
clear pflags3 bit1 (breakaway)
assreplace($10)                     ; sets pfna -> asspuckc re-inits temps this same frame
fall through into asspuckc
```

### asspuckc (L39901, assignment $10; entry $DF18)

- **Purpose:** CPU puck carrier logic.
- **Callers:** dispatcher (installed by `assnearest` via `assinsert`), and fall-through or branch from `chkpuckc`.
- **Inputs:**
  - a3 and its fields.
  - d7 (elapsed vblanks).
  - Globals listed above.
- **Outputs:**
  - Assignment changes.
  - temp1, temp2 and temp3.
  - `threat`.
  - Player acceleration through `skateto` / `doplayeracc`.
  - Stats.

Steps:

1. If `bclr(word_FFC2F6 bit2)` finds the bit clear, clear pflags3 bit 1 (breakaway). The breakaway bit therefore survives only when this call came through `breakaway()`.
2. If `puckc != SCnum`: `assexit` and return.
3. If BA_PS bit 2 is set and `word_FFC31A > 1` (signed): return. This waits for the penalty-shot start.
4. If the breakaway bit is clear and BA_PS bit 2 is clear:
   - call `BreakawayOffsidesFlagSet`;
   - if it returns Z=0, `assreplace($21 chkpuckc)`. This sets pfna.
   - `bra.w *+4` is a no-op that jumps to step 5.
5. If pflags bit 5 (pfalock) is set: return. This exit does not consume pfna.
6. If BA_PS bit 2 is clear and gmode bit 0 (clock stopped) is set: `assnothing` and return. `assnothing` calls `doplayeracc(8)` unless pfalock or pfjoycon is set. This exit does not consume pfna.
7. If pfjoycon is set: `assexit` and return.
8. If `bclr(pfna)` was set (new assignment):
   - if the breakaway bit is set: `sfx(1)`; team.$358 += 1; `CwdExciteLvl` += $14; `crowdlevel` += $C8. The two tests are separate but use the same condition.
   - `temp1` (word) = 0;
   - `temp2` (word) = 8, so the $42 byte = 0 (skateto updates this frame) and the $43 byte = 8 (glide);
   - `temp3` (word) = `VDP_CNTR & 3`.
9. Decision countdown:
   - `temp1.b -= d7`. If the result is >= 0 (bpl): go to step 12 (movement).
   - Otherwise reload `temp1.b = aioff ($6A)`.
   - If `ReadGoaliePulled` returns N=1 (own team struct +$26 negative, meaning own goalie pulled): `temp1.b -= 1`.
   - Else if byte_FFC2FC bit 6 (crowd record broken) is set and `temp1.b != 0`: `temp1.b -= 1`.
   - The effective decision period is (temp1 + 1) frames when d7 = 1.
10. Decision. If BA_PS bit 2 or FFC2FA bit 0 is set, go to step 11. Otherwise:
    - a. `bsr checkob`.
    - b. `bsr sub_E1F4`. It may not return: it can end in `compshoot`.
    - c. Re-test FFC2FA bit 0 and BA_PS bit 2. If either is set, go to step 11.
    - d. Decide whether to call `chk4shot`:
      - If the breakaway bit is set: call `chk4shot`.
      - Else let `t = 1` if pfteam = 0 (home), or `t = 2` if away. If `cont1team == t` or `cont2team == t`: call `chk4shot`.
      - Else (all-CPU team): if bit 1 of `vcount` low byte is set, skip `chk4shot`; otherwise call it.
      - `chk4shot` may not return (shot), or may return after a flip pass.
    - e. `bsr chk4pass`. It may not return (pass + assexit).
    - f. Go to step 12.
11. PS/SO decision:
    - `jsr sub_FE8EC`. If it returns Z=0: go to step 12, with **no pass check**.
    - Otherwise `jsr compshoot`, which never returns here.
12. Movement (every frame that reaches here):

```
idx = 6 + temp3
if sflags2 bit7 (offside ref up): idx = position ($34)
d0 = _postab2[idx].X ; d1 = _postab2[idx].Y          ; asl.w #2 index, words
if BA_PS bit2 or FFC2FA bit0:
    jsr sub_FE864            ; d0/d1 = current waypoint (raw, attack-top frame) unless path finished
    if word_FFDA16.hibyte == $80: return              ; no skateto / no doplayeracc this frame
if pfgoal == 0: d0 = -d0; d1 = -d1
callback = loc_E12C (evade), or a bare rts (locret_E1CA) in PS/SO modes
skateto(d0, d1, callback)                            ; tail jump; skateto ends in doplayeracc
```

- **Quirks:**
  - `threat` is consumed by `chk4shot` / `chk4pass` before this frame's callback recomputes it. The decision always sees the value from the last callback run (up to 12 frames old), or `assgoaliecpu`'s `threat = 1` when the goalie passed and no callback ran since then. On the first frame of the assignment, the decision runs before the first callback.
  - When step 4 does `assreplace($21)` and then exits at step 5 or 6, pfna stays set. On the next frame `chkpuckc` -> `breakaway()` consumes it and plays the ding and stats instead. The temps are then **not** reset.
  - When step 4 does `assreplace($21)` and then exits at step 7 (human control), `assexit` increments assnum past the slot that was just replaced.
  - `_postab2` is indexed directly by position (1..5). Entry 0 is unused, and the X signs look one slot off (L.def gets +100). See UNRESOLVED 1.

### loc_E12C, the carrier's evade callback (L40046; not a separate routine)

- **Purpose:** the `a0` callback that `skateto` passes when it recomputes the heading, which happens every 12 frames. It counts threats and turns the heading away from opponents.
- **Inputs:**
  - d0 = skateto heading: 0-7, 8 = zero vector, or 9 = within 12 px of the target.
  - a3.
  - The opposing team's 6 objects: `SortCords` if a3.SCnum >= 6, else `SortCords + $300`.
- **Outputs:**
  - d0 = new heading.
  - `threat` = count.
  - d1-d4 and a0 are clobbered (skateto does not rely on them).

```
d0 = ext.w(d0)                                        ; no-op
cx = hibyte(a3.Xvel) (signed) + puckx                 ; move.b $28(a3) = Xvel>>8, floor
cy = hibyte(a3.Yvel) + pucky
threat = 0
for each of the 6 opposing objects o (no position filter; goalie and off-ice included):
    dx = hibyte(o.Xvel) + o.Xpos - cx ; if dx > 20 or dx < -20: continue   ; $14 / $FFEC, inclusive window
    dy = hibyte(o.Yvel) + o.Ypos - cy ; if dy > 20 or dy < -20: continue
    threat += 1
    d0 = vtoa(a3.Xpos - o.Xpos, a3.Ypos - o.Ypos)     ; away from the opponent (8 if same spot)
    if (a3.facedir ^ 4) == d0:                       ; carrier faces the opponent
        d0 = (d0 + (VDP_CNTR & 1)) & 7
return d0
```

- **Quirks:**
  - The carrier's original heading is replaced outright (not blended) by the last counted opponent's escape direction.
  - With 0 threats, d0 is unchanged.

### sub_E1F4, CPU tired-line dump (L40124)

- **Purpose:** when the on-ice skaters are tired and the puck is in the attacking half of the neutral zone, change lines and dump the puck.
- **Callers:** `asspuckc` step 10b (bsr).

```
if byte_FFC2FC bit4: return
y = pucky; if pfgoal == 0: y = -y
if y < 0: return ; if y > $58 (88): return            ; signed
if (VDP_CNTR & 3) != 0: return
if a3.$63 bit3: return
a2 = own team struct, a1 = other team struct          ; HmShots base, +$364; exg if pfteam=1
avg = sub_12EF6()        ; mean of team.$32+2*pnum (energy) over the team's 6 objects with position > 0; 0 if none
if avg > $C00 (unsigned): return
CompLine ; SetPersonel ; PrintScores1                 ; CPU picks/sends the new line (not specced here)
goto compshoot                                        ; pops asspuckc's return; shot assignment
```

- **Quirk:** this routine does not test `OptLine` itself.

### chkpk (L40159) and chkpk2 (L40168)

- **Purpose:** return **Z=1 when a3's team is killing a penalty**, and Z=0 otherwise.
- **Callers:** `chk4shot` and `assdefd`+$96 (chkpk); `assnearest`+$244 and `setplayer` (chkpk2).

```
chkpk:  if sflags2 bit5 (power play) == 0: return Z=0   ; btst gives Z=1, then eori #4,ccr flips it
        else goto chkpk2
chkpk2: Z = (sflags2 bit6) XOR (pflags bit6 pfteam)     ; Z=1 when they differ
        ; implemented as: btst; move sr,d0; btst; move sr,d1; eor d1,d0; move d0,ccr
        ; result CCR: only Z may be set; N, V, C and X are 0. d0/d1 preserved.
```

- Interpreting sflags2 bit 6 as "team on the power play (0 home, 1 away)": Z=1 means a3 is not on the PP team, so a3 is short-handed.

### chk4shot (L40183)

- **Purpose:** the CPU carrier's shot decision, plus the penalty-kill clear.
- **Callers:** `asspuckc` step 10d (bsr). It either returns, ends in `compshoot` (which pops this return so the assignment is done), or tail-jumps to `dopass` (which returns to `asspuckc`, which then runs `chk4pass`).

```
if chkpk() returns Z=0 (NOT killing a penalty): goto normal      ; label "_pkill" is misnamed
if threat == 0: goto normal
if (VDP_CNTR & 3) != 0: goto normal
; --- penalty kill clear, threatened, 1 in 4 ---
if pfgoal == 1: if Ypos > -$58 (-88): goto compshoot ; else flip
else:           if Ypos <  $58 (88):  goto compshoot ; else flip
flip: set word_FFC2F6 bit3 ; jmp dopass       ; dopass does the flip / clear lob, returns to asspuckc
      ; (followed by 4 unreachable bytes $60 $00 $01 $30 = bra.w +$130, never executed)

normal (L "_pkill"):
if pflags3 bit1 (breakaway):
    t = randomd0($1E) + $82                    ; 130..159
    if pucky > t or pucky < -t: goto bshoot    ; signed, strict
    ; else fall to eval
    goto eval
bshoot:
    a3.facedir(hi word) = (facedir + randomd0s(2)) & 7     ; +(-2..1)
    goto compshoot                             ; no zone / offside checks on this path

eval:
d4 = (($20 - (spodds >> 1)) & $FF) << 4        ; moveq #$20; sub.b; asl.w #4 -> (32 - s/2)*16 = 272..512
gx = 0 - puckx ; gy = (pfgoal ? $108 : -$108) - pucky
if gx*gx + gy*gy > $2710 (10000, unsigned): goto roll     ; puck more than 100 px from goal-line centre
d4 >>= 4                                       ; lsr.w -> 32 - s/2 = 17..32
gdir = vtoa(gx, gy)
for each of the 6 opposing objects o, in SCnum order (stop early, see below):
    if o.position == 0:                        ; goalie
        if o.$63 bit1 (anim in progress): d4 = 1; stop loop
    else:                                      ; any other value, including negative (off ice)
        if vtoa(o.X - puckx, o.Y - pucky) == gdir: d4 <<= 1     ; no distance limit
roll:
r = randomd0(d4)
if spodds bit0 == 1: if r > 7: return
else:                if r > 8: return
y = pfgoal ? pucky : -pucky
if y < 0: return                               ; puck in own half
if $108 - y < 0: return                        ; puck behind attacked goal line
if sflags2 bit7 (offside ref up): return
fall through into compshoot
```

- **Notes:**
  - The returns go back to `asspuckc` and on to `chk4pass`.
  - A breakaway carrier who fails the depth test still gets the normal evaluation.
- **Quirks:**
  - The odd/even spodds threshold (8 vs 9 outcomes).
  - Off-ice opponents can double d4.
  - Opponents behind the goal in the same octant double d4.
  - The goal "centre" is the goal line Y ±264, not the net Y ±268.

### compshoot (L40316, listed as `compshoot?`)

- **Purpose:** start a CPU shot.
- **Entry:** must be entered with exactly one return address on the stack, the bsr/jsr from `asspuckc`. Entered via `chk4shot` (branch or fall-through), `sub_E1F4` (bra), and `asspuckc` (jsr in PS/SO mode).

```
pop 4 bytes (discard return into asspuckc)
y = pfgoal ? pucky : -pucky
d1 = ($108 - y) >> 3        ; lsr.w: logical shift, so a negative difference becomes a large positive number
if d1 >= $14 (signed compare): d1 = $14 (20)
temp2 (word $42) = d1       ; windup frames for assshoot
assreplace($12 assshoot); rts  (returns to updateplayers)
```

- `assshoot` (L41029) behaves as follows:
  - On pfna it calls `SetShotMode`.
  - Then each frame it does `temp2 -= d7` and calls `ShotMode` with d2 = 0 while the result is >= 0. Once the result is < 0 it passes d2 = bit 5 (C button released).
  - If sflags bit 3 (shot-direction mode) is clear, it calls `assexit`.
  - `ShotMode` -> `prepshot` -> `doshot` performs the shot. The shot direction comes from `passdir` / facedir inside those routines, which are not covered here.

### chk4pass (L40337)

- **Purpose:** random pass decision for a CPU carrier. `assgoaliecpu` also uses it after setting `threat = 1`.
- **Callers:** `asspuckc` step 10e (bsr) and `assgoaliecpu`+$2C4 (bsr).

```
if threat == 0:
    if randomd0(16 + spodds) > 12: return         ; moveq #$10; add.b $70 -> range 16..46
n = randomd0(6); if a3.SCnum >= 6: n += 6         ; random object of own team
if a3.position != 0:                              ; goalies skip this test
    if -40 <= puckx <= 40 and (pucky > $CC or pucky < -$CC): return     ; $28/$FFD8, 204
if n == a3.SCnum: return
r = object n
if r.position <= 0: return                        ; goalie or off ice
if r.$63 bit2: return                             ; "unavailable"
if r.pflags bit5 (pfalock): return
ry = r.Ypos, cy = a3.Ypos; if pfgoal == 0: negate both
if gmode bit5 (offsides on):
    if ((ry - $58) XOR (cy - $58)) < 0: return    ; on opposite sides of the attacked blue line
if ry <= $58:                                     ; receiver not deep in attack zone
    if ry - cy < -15 ($FFF1): return              ; no pass more than 15 px backward
dx = r.X - puckx ; dy = r.Y - pucky
passdir = vtoa(dx, dy)
rd2 = dx*dx + dy*dy
for each of the 6 opposing objects o (no position filter):
    ox = o.X - puckx ; oy = o.Y - pucky
    if ox*ox + oy*oy > rd2 (unsigned): continue
    if vtoa(ox, oy) == passdir: return            ; lane blocked
dopass()                                          ; normal pass toward passdir (passacc used inside)
if a3.position == 0: return                       ; goalie: back to assgoaliecpu
pop asspuckc's return; assexit                    ; assignment done
```

- **Quirk:** `chk4pass` does not check `puckc`. After `chk4shot`'s flip-clear `dopass` returns, `chk4pass` runs in the same frame, with `threat` != 0 so the random gate is skipped. It can call `dopass` again, and the normal pass then overwrites the flip.

### dopass / passmode (L36913, named only)

- `dopass` (L36924) does the following:
  - clears sflags bit 2;
  - sets `puckc = $FFFF` and `nopuck ($5E) = $10`;
  - sets `lastplayer = SCnum`.
- If `word_FFC2F6` bit 3 was set, it clears the bit and takes the flip path (`sub_F67E4` + `sub_F6778` -> `puckflip`). Otherwise it computes `passspeed` from passacc and chooses the receiver nearest `passdir` (`passto`). If there is none, it hits the puck along `passdir`.
- It then sets the pass animation (SPA $718 forward or $78A backhand; $366 for a goalie), sets pfalock and plays sfx $10..$13. It returns normally.

### EvadePC (L40442)

- **Purpose:** skateto callback for **non-carrier** skaters (`assdefo`, `assdefd`, `asswingo`, `asscentero`) so they move out of the puck's way.
- **Inputs:** d0 = skateto heading, a3, the puck.
- **Output:** d0, which is the input unchanged unless the player is near the puck.

```
if puckc < 0: return d0
dx = ext.w( hibyte(a3.Xvel) - hibyte(puckvx) )  (8-bit subtract, wraps)  + a3.Xpos - puckx
if dx > 40 or dx < -40: return d0                 ; $28 / $FFD8
dy = ext.w( hibyte(a3.Yvel) - hibyte(puckvy) ) + a3.Ypos - pucky
if dy > 40 or dy < -40: return d0
d0 = vtoa(a3.Xpos - puckx, a3.Ypos - pucky)       ; away from the puck
if gmode bit5 (offsides on):
    t = (pfgoal ? a3.Ypos : -a3.Ypos) - $58
    if -50 <= t <= 10:                            ; $FFCE..$A, i.e. attackY 38..98 (near attacked blue line)
        d0 = (a3.Xpos > puckx) ? 2 : 6            ; move sideways, not across the line
return d0
```

- Despite its header comment, it never checks which team holds the puck.

### checkob (L40493)

- **Purpose:** show or hide the delayed-offside "little ref" (sflags2 bit 7).
- **Callers:** `asspuckc` step 10a, and `doinput` (loc_B72E, human carrier).

```
if gmode bit5 == 0 (offsides off): return
if BA_PS bit2: return
line = pfgoal ? $5C (92) : -$5C
if puck already past the line into the attack zone (pfgoal: pucky > 92 ; else pucky < -92): goto clear
for each of own team's 6 objects with position >= 0 (bmi skips negatives):
    if object is past the line (pfgoal: Ypos > 92 ; else Ypos < -92): goto set
goto clear
set:   if bset(sflags2 bit7) was already set: return
       if RefCnt < 0: PushRef(6)                  ; draw offside-arm ref
       return
clear: if bclr(sflags2 bit7) was set and RefCnt < 0: PushRef($40)   ; $40 = clear ref graphic
       return
```

- Uses 92 ($5C), not 88. Registers d0, d1 and a0 are preserved.

### assbreakaway (L40557, assignment $22) and the assnearest carrier branch (L40574-40626)

- **Purpose:** breakaway handling while the carrier is not run by `asspuckc` (human carriers).

```
assbreakaway:
if SCnum == puckc:
    breakaway(); if N == 0: fall into assnearest     ; keeps $22
clear pflags3 bit1; assreplace($11); goto assnearest

assnearest (only the carrier-relevant head):
if bclr(word_FFC2F6 bit2) was clear: clear pflags3 bit1
if SCnum == puckc and breakaway bit clear and BA_PS bit2 clear:
    if BreakawayOffsidesFlagSet() returns Z=0: assreplace($22)    ; then bra *+4 (no-op)
if bclr(pfna) was set:
    if breakaway bit: sfx(1); team.$358 += 1; CwdExciteLvl += $14; crowdlevel += $C8
    temp3 = 0; temp2 = 8; temp1 = 0
if SCnum == puckc:
    if position == 0: goto assgoaliecpu
    if pfjoycon == 0: assinsert($10 asspuckc); return       ; CPU carrier -> asspuckc next frame
    return                                                    ; human carrier
(non-carrier part, _nopc onward, is not covered by this spec)
```

### Assignment stack helpers (L43192-43222)

- `assexit`: `assnum = (assnum + 1) & 7`; set pfna. Execution resumes with the entry below.
- `assinsert(d0)`: `assnum = (assnum - 1) & 7`, then `assreplace`.
- `assreplace(d0)`: `asslist[assnum] = d0.b`; set pfna.
- The new assignment runs on the next frame's dispatch, unless code branches to it directly, as `chkpuckc` and `assbreakaway` do.

### skateto (L42953, context only)

`asspuckc` tail-jumps here with d0/d1 = target and a0 = callback.

```
temp2.hi -= d7 ; if >= 0: goto ex                         ; heading recomputed every 12 frames
temp2.hi += 12
(d0,d1) = avdgoal(d0,d1)                                   ; adds a detour so the path avoids the nets
dx = d0 - Xpos - (Xvel asr 8) ; dy = d1 - Ypos - (Yvel asr 8)
d0 = (|dx| <= 12 and |dy| <= 12) ? 9 : vtoa(dx, dy)
d0 = callback(d0) ; temp2.lo = d0
if d0 > 7 and Xvel == 0 and Yvel == 0:
    turn facedir one step (±1, chosen by bit 2 of -(dir - facedir)) toward the puck
    (or toward xc1/yc1 when puck pflags2 bit0 is set)
ex: doplayeracc(temp2.lo)        ; 8 = glide, 9 = dostop when moving
```

### getBAplayerInfo (L46136)

- **Purpose:** when a player on a breakaway is fouled, record the penalty-shot participants.
- **Caller:** `PenShotChk` (L46100). `PenShotChk` is called from the checking code (CCStart, e.g. L48936) with a2 = the fouled player, a3 = the checker and d0 = penalty offset.
- **Inputs:** d0 = SCnum of the fouled skater, a3 = the checker.
- **Outputs:** N flag (N=0 means OK) and the BA_* globals.

```
if OptPen == 0: return N=1      ; penalties off (move.w #$FFFF,d1 sets N; movem then restores d1)
set BA_PS_flags bit3
scan = (d0 > 5) ? 5 : $B                                 ; opposing team's highest SCnum
g = getGoalieSCnum(scan)    ; scans scan, scan-1, ... scan-5 for position == 0; -1 if none
if g < 0: clear BA_PS_flags bit3; return N=1             ; empty net (N comes from tst.w d0)
BA_Sktr_SCnum     = d0
BA_Team           = pfteam of object d0 (0 home, 1 away)
BA_Skater_Offset  = object d0's pnum ($66), zero-extended
BA_Goalie_SCnum   = g
BA_Goalie_Offset  = goalie's pnum
BA_Checker_Offset = a3's pnum
return N = bit 7 of a3.pnum (normally 0)
```

`PenShotChk` (context). It saves and restores d1-d3/a0, so its only output is d0, the penalty to call:
- If the fouled player (a2) has no breakaway bit, or BA_PS bit 3 is already set: d0 is unchanged.
- Else `v = unk_1913A[d0]`. If v < 0: d0 is unchanged.
- Else call `getBAplayerInfo(a2.SCnum)`. On N=1: clear BA_PS bit 3; d0 is unchanged.
- On N=0: `word_FFD410 = v`, `d0 = v` (the penalty is replaced by its penalty-shot variant).

The caller then branches to or calls `AddPenalty` with that d0.

## 4. UNRESOLVED

1. **`_postab2` index for the offside wait.** The code indexes by `position` directly (1..5). The resulting spots are LD (100,-20), RD (-120,40), LW (20,40), C (120,40), RW (-20,40). Entry 0 (-100,-20) is never used. With `position - 1` the table would read as a sensible LD/RD/LW/C/RW formation. I found no other user of the table. Port it as-is.
2. **`unk_1913A` mapping.** With the listing's `PenaltyList` comment names, the mapped values look shifted by one entry:
   - $16 PenCharging -> $3C "PenSlashing2";
   - $18 PenSlashing -> $36 "PenRoughing3";
   - and so on.
   A version without the shift would read Charging->Charging2, Slashing->Slashing2. Either the listing's comment names are off by one, or the table is. The values themselves are exact.
3. **Bit meanings.**
   - `$63` bit 2 is named `pf2dw` by the 93 equates but is used as "unavailable" in 94.
   - `$63` bit 3 is named `pf2np` (no joystick pad) by the 93 equates; its 94 meaning was not verified.
   - The listing comment says `OptLine` value 2 is the auto line-change mode; I did not trace the options menu text to confirm that.
4. **HV counter.** `VDP_CNTR & 3` and `& 1` come from the hardware HV counter. Their real distribution depends on when in the scanline the code runs. The port should treat them as uniform random values.
