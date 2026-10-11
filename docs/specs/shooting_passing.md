# Shooting and passing: behavior spec (NHL '94 Genesis)

Source: `lst/nhl94.bin.lst` (IDA listing), cross-checked against the ROM bytes in `lst/nhl94.bin` where the listing is wrong or unclear (Findhittype, passmode's fall-through, doshot, passto, puckvzadj, setonetimeranim). Line numbers are listing lines (Lnnnnn). ROM addresses are given as `$xxxxx`.

---

## 1. Overview

The player actions that put the puck in motion:

| Action | Trigger | Path |
|---|---|---|
| Pass (human) | B pressed with puck | doinput → `setpassmode` (enter pass-aim mode). Next loops: `passmode`. The pass fires on B release, or at once if a d-pad direction is held → `dopass` → `passto`/`passtoa0` (to a teammate) or `_nopp` (into empty ice). |
| Flip/dump pass (human, 94 only) | A tapped (released within 15 loops) or held 15 loops, with puck | doinput sets `word_FFC2F6` bit 3 and calls `setpassmode`. Next `passmode` → `dopass` takes the flip branch → `sub_F67E4` (choose a target spot) + `sub_F6778` (lob velocity). |
| Pass (CPU) | `chk4pass` (asspuckc / assgoaliecpu) | sets `passdir` = direction to the chosen receiver, then `bsr dopass` directly (no setpassmode). |
| Shot (human) | C pressed with puck | doinput → `SetShotMode` (windup anim, passspeed = 15). Next loops: `ShotMode` charges passspeed by elapsed vblanks during the windup. Releasing C (or a weak shooter's forced release) starts the swing. When the anim index reaches $1C: `prepshot` → `doshot`. |
| Shot (CPU) | `compshoot?` → assignment `assshoot` ($12) | Same as the human shot. `assshoot` simulates the C release when the countdown temp2 expires. |
| Pass reception | `passtoa0` inserts assignment `asspassrec` ($13) on the receiver | The receiver glides with no deceleration until a timer runs out or someone has the puck. The CPU may convert this into a one-timer. |
| One-timer | Human: C pressed while the pass is in flight (passer or receiver). CPU: `asspassrec`. | assignment `assonetimer` ($23): windup anim timed to the puck's arrival. The puck reaching the stick (`puckstick`) calls `onetimershot` → `doshot`. |
| Speed burst | C pressed without the puck (human). CPU: `check4check` "throw check". | `burst` |
| Hold | A pressed without the puck (human). CPU: `check4check` → `Acheck`. | `holdplayer` / `Acheck` |

`doshot` builds the shot as follows:
1. Take an aim point on the goal line from `shotsets[passdir]` (x offset and height).
2. For a non-perfect shot, perturb dx, dy and z with random terms scaled by distance, speed and shotacc.
3. Set horizontal velocity = passspeed·68·(dx,dy)/dist and vertical velocity from the height/gravity formula, optionally replaced by the "top-shelf float" in `puckvzadj`.

The CPU and every one-timer (CPU or human) get `passdir` from `shotdiradj`, which aims away from the goalie, unless penalty-shot/shootout script directions apply.

### 1.1 General notes that matter for an exact port

- **Bit operations on memory are byte-sized.** `btst/bset/bclr #n,(word_X).w` act on the byte at address X, the HIGH byte of a word variable. Every access to a given flag word uses the same form, so the port can treat them as independent flag bits. Only the `.w` reads and writes (`clr.w`, `move.w`) touch both bytes.
- **`st (var).w` is `st.b`.** It writes $FF to the high byte only. `st (puckc).w` therefore leaves `puckc = $FF00 | old_low_byte`, which is negative. The same applies to `passplayer` and `onetimerplayer`. Every reader in this scope only tests the sign (`tst.w`/`bmi`/`bpl`) or compares the full word with an SCnum (0..15), which a negative value can never equal.
- **`move.b dX,(puckvz).w` writes only the HIGH byte of puckvz** (passto). The low byte keeps its old value.
- **Flags survive `movem`, `jsr`/`bsr`, `rts`, `bra` and `dbcc`.** Several routines return a result only in the CCR (Z or N): Findhittype, noidea, sub_F6C44, ReadGoaliePulled. This is called out per routine.
- `muls.w`/`mulu.w` use only the low 16 bits of both operands. `divs.w`/`divu.w` put the quotient in the low word and the remainder in the high word. **On overflow (quotient does not fit in 16 bits) the destination is left unchanged**, and the code then usually stores its low word. These cases are noted where they can plausibly occur.
- `randomd0(n)` (L44190) returns 0..n-1 (0 when n = 0). `randomd0s(n)` (L44178) returns `randomd0(2n) − n`, i.e. −n..n−1 (the listing comment "−range<d0<range" is slightly wrong at the top end). See §5.
- Ratings in SCstruct: `shotspd $6C`, `shotacc $6D`, `passacc $6E` and `spodds $70` are bytes 0..30 (setplayer/AttributeCalc: nibble·5 + hot/cold/3, plus bonuses, clamped to 0..$1E). Energy (tmpde) is a word 0..$1000 ($1000 = full).
- One loop = one DoGameFrame. `d7` = vblanks since the last loop. Within `updateplayers`, each object runs `updateanim` (advances SPAnum) BEFORE its input or assignment call (L35462 `_top3`). `ShotMode`, `assonetimer` and the others therefore see the SPAnum already advanced this loop.

### 1.2 Global variables

| Name | Address | Meaning / writers / readers (in this scope unless noted) |
|---|---|---|
| `passdir` | $FFBEDC (w) | Pass/shot direction 0..7, or 8 = none (shot only). Written by setpassmode (facedir&7), passmode (d-pad), SetShotMode (8), ShotMode (d-pad, or assnum for the CPU, see quirk), shotdiradj (0/2/6/8), PSandSOpassdir, onetimershot (4, overwritten at once), chk4pass (vtoa toward the receiver). Read by dopass, prepshot, doshot. |
| `passspeed` | $FFBEDE (w) | Pass: "pix/sec" speed 160..~233. Shot: raw charge 15+vblanks, then the scaled shot speed. Written by dopass, SetShotMode, ShotMode, doshot. Read by passtoa0, `_nopp`, doshot. |
| `lastplayer` | $FFBEDA (w) | SCnum of the last player to pass or shoot (also written by puckstick on a steal). Written by dopass and doshot. Read by doinput (one-timer triggers), puckstick (controller switching). |
| `shotplayer` | $FFBED8 (w) | SCnum of the last shooter (also set on a whiffed shot). Written by doshot. Read by ChkShotStat (shots-on-goal stat, L47496) and assscore (scorer "pump" anim $EFC vs $E8A). |
| `passplayer` | $FFBEE0 (w) | SCnum of the pass receiver; negative = none. Written by passtoa0. Cleared (st.b) by assonetimer and elsewhere (L41299, L42074). Read by doinput one-timer triggers. |
| `onetimerplayer` | $FFBF6C (w) | SCnum of the player doing a one-timer; negative = none. Set by assonetimer, cleared (st) by sub_FEFF0 and others. |
| `threat` | $FFBEE4 (w) | CPU puck-carrier danger count. `asspuckc` clears it, then adds 1 per opponent whose (pos + Xvel_hi/Yvel_hi bytes) is within ±$14 (20) px on both axes of (puck + carrier's Xvel_hi/Yvel_hi bytes) (L40054-40078). `assgoaliecpu` sets it to 1 when no opponent is within ±$19/±$1C of the puck (L39271). Readers: `chk4shot` (no CPU shot if 0), `chk4pass` (if 0, a pass needs randomd0($10+spodds) ≤ $C; if non-zero, no gate). Not used by the routines in this spec. |
| `puckc` | $FFB7AA (w) | Puck carrier SCnum, or negative. dopass and doshot write `st.b`. |
| puck struct | $FFB74A | SCnum 14. puckx $B74A, pucky $B75E, puckz $B762, puckvx $B772, puckvy $B774, puckvz $B776; puck `$5E` byte = `puckx_nopuck` $B7A8. |
| `sflags` | (byte) | bit 2 = pass-aim mode (`sfspdir`), bit 3 = shot-aim mode (`sfssdir`), bit 7 = horizontal rink. One global copy for all players. |
| `sflags2` | | bit 4 = shot taken (set by doshot). |
| `gmode` | $FFC2EA | bit 0 clock stopped, bit 4 highlight (every shot is perfect). |
| `BA_PS_flags` | $FFC2F2 | bit 2 = penalty shot in progress; bit 5 = PS attempt already started. |
| `word_FFC2F6` | | bit 3 = flip-pass request (set by doinput on A; consumed by dopass). bit 4 = "in-close top shelf" (set by prepshot, consumed by doshot). |
| `word_FFC2F8` | | bit 1 = set by onetimershot; bit 2 = flip pass is the high dump ($3A); bit 5 = "puck carrier in slot" (read by check4check/puckstick, not written here). |
| `word_FFC2FA` | | bit 0 = shootout mode; bit 2/bit 5 cleared by setpassmode/SetShotMode in PS; bit 4 = the current shot is a breakaway shot (written by doshot). |
| `byte_FFC2FC` | | bit 4 = no fatigue (energy forced to $1000). Set at game setup when OptLine was 2. |
| `byte_FFC2FE` | | bit 5 cleared at one-timer start; bit 7 = one-timer contact / shot (set by puckstick and onetimershot, cleared by assonetimer abort). |
| `word_FFC31C` | | set to $64 (100) at the first pass/shot of a penalty shot (a PS timer; consumer not in scope). |
| `word_FFBF76` | | One-timer state. bit 0 = shot done, bit 1 = holding at the hit pose (entry 6), bit 2 = swing started. Cleared at one-timer start/end. |
| `word_FFBF6E` | | One-timer windup vblank accumulator. Written, never read (dead). |
| `word_FFD414/416/418` | | Flip-pass target x, target y, apex height. |
| `word_FFDA1A` | | Penalty-shot/shootout CPU script shot direction (from sub_FE7FC). |
| `inputjoy` $FFDED8, `TmpJoyPuckCarrier` $FFDEDA | | Controller that requested the one-timer (−1 = CPU), copied from doinput d4/joypuckcarrier. |
| `OptLine` $FFD058 | | 0 = line changes on (burst drains energy only when 0). |

### 1.3 Tables

`dirtab` (L43933): (x, y) per direction, runspeed 200. Already ported.
`0:(0,200) 1:(141,141) 2:(200,0) 3:(141,-141) 4:(0,-200) 5:(-141,-141) 6:(-200,0) 7:(-141,141) 8:(0,0)`

`shotsets` (ROM $C542, L37697). Per passdir: (aim X offset from rink center, height z in pixels). Verified from bytes `0000 000c 0010 000c 0010 0006 0010 0000 0000 0000 fff0 0000 fff0 0006 fff0 000c 0000 0006`:

| passdir | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 (default) |
|---|---|---|---|---|---|---|---|---|---|
| x | 0 | +16 | +16 | +16 | 0 | −16 | −16 | −16 | 0 |
| z | 12 | 12 | 6 | 0 | 0 | 0 | 6 | 12 | 6 |

The aim X is absolute screen/rink X: "right" aims at +X for both goals. Aim Y is the goal line ±$108.

`passdirlist` (L974252): `0,7,6,5,4,3,2,1,8` (index 0..8). This mirrors a direction left-to-right.

Flip-pass target tables (ROM $F68DE, $F68FE, $F691E). Entries are (x, y) words indexed by direction 0..7:
- `word_F68DE` (dump from own/neutral zone): dirs 0-3 = ($74, $C2) = (116, 194); dirs 4-7 = (−116, 194).
- `word_F68FE` (offensive zone): all 8 = ($FFFB, $AB) = (−5, 171).
- `word_F691E` (goalie): 0:(−5,−9) 1:(50,−9) 2:(50,−9) 3:(50,−9) 4:(−5,−9) 5:(−50,−9) 6:(−50,−9) 7:(−50,−9).

### 1.4 Animation ids (SPA) used

| SPA | Name (listing) | Use |
|---|---|---|
| $C5E | SPAburst | burst. 1 entry/dir, frames $29+5·dir, time 24 (final). |
| $1122 | hold check (normal) | holdplayer/Acheck. Frames $251+2·dir, time 30. |
| $C90 | hold check, stick in air | holdplayer/Acheck. Frames $159+dir, time 30. |
| $366 | SPAgswing | goalie pass. Per dir: $1AF+2d/5, $1B0+2d/8, $1AF+2d/16 (final). |
| $718 | SPApassf | forehand pass. dir0: $64/4 $65/4 $66/20; other dirs: frames +6·dir. |
| $78A | SPApassb | backhand pass. dir0: $64/4 $63/4 $62/20; +6·dir. |
| $7FC | SPAshotf | forehand shot. dir0 frames (time 4 each, last 20): $64 $63 $62 $61 $62 $63 $64 $65 $66; +6·dir. |
| $92E | SPAshotb | backhand shot. dir0: $64 $65 $66 $66 $66 $65 $64 $63 $62 (4 each, last 20); +6·dir. |
| $46A | SPApflip | puck spin, set by puckflip on the puck (flip pass). |
| $50C | SPAglide | set when a one-timer ends (sub_FEFF0). |
| $250 / $2A2 | goalie pad stack right / left | read by prepshot. |

Animation record layout (SPAList at ROM $5B1C + SPA): 8 word offsets (one per facing dir, after x-flip remap), then attributes at +$10. Each list is (frame word, time word) pairs, so SPAnum steps by 4. A negative time marks the last entry. With d7 = 1, an entry of time 4 lasts 5 loops (SPAcnt 4,3,2,1,0, then −1 advances). For both shot anims: entries 0-3 (SPAnum 0..$C) are the windup, entry 4 ($10) starts the forward swing, entry 6 ($18) is the one-timer "ready" pose, entry 7 ($1C) is contact (the puck is launched), entry 8 ($20) is the follow-through.

### 1.5 Sound effects (sfx word ids)

| id | Name | Where |
|---|---|---|
| $05 | SFXshotwiff | doshot with no puck |
| $10..$13 | SFXpass (+0..3) | dopass. Offset from the high byte of puckvz, see dopass step 7. |
| $14..$17 | SFXshotbh (+0..3) | doshot, backhand |
| $18..$1B | SFXshotfh (+0..3) | doshot, forehand. Offset = max(0, 3 − (speed>>4)). |
| ($06 SFXstdef, $07 SFXpuckget, $2C..$2F puck-on-ice) | | context only (puckstick/updateplayers) |

---

## 2. Input dispatch context (doinput, not re-specced, needed to wire callers)

doinput registers: d0 = d-pad (0-7, bit 3 set = none; in horizontal mode the direction gets +2 & 7), d1 = newly pressed buttons, d2 = changed buttons (used as "released" while held), d3 = held buttons, d4 = controller 0/2. Button bits: 4 = B, 5 = C, 6 = A, 7 = Start.

- **Controlled player is the puck carrier** (loc_B72E, after `checkob`; a non-goalie with pf2aip returns):
  1. If sflags bit 2 → `passmode`. Else if sflags bit 3 → `ShotMode`.
  2. Else B new → `sub_FEE60` (input stats only: per-controller counters at $FFDEA4/$FFDEAC) then `setpassmode`.
  3. A: on A-new, the per-controller byte counter `word_FFD41E` (+1 for controller 2) = $F. While A is held, the counter is decremented by 1 per call (clamped at 0). When it hits 0: set `word_FFC2F6` bit 3, `setpassmode`, then `bra SetLCmode`. If A is not held but changed (released) → set `word_FFC2F6` bit 3, `bra setpassmode`.
  4. Else a goalie → doplayeracc (goalies cannot shoot). Else C new → `sub_FEE60`, then `SetShotMode`. Else doplayeracc.
- **Controlled player without the puck** (loc_B258…): A new (and not goalie, not one-timer) → `holdplayer`. In the skating path (loc_B6BA): if in a one-timer (pflags3 bit 3) → return. If C not new → doplayeracc. If C new, `burst`, unless ALL of the following hold, in which case `assreplace(a3, $23 assonetimer)` with `inputjoy = d4`, `TmpJoyPuckCarrier = joypuckcarrier`:
  - the player struct indexed by `lastplayer` is not a goalie,
  - `a3.SCnum == passplayer`,
  - `puckc < 0`,
  - `sub_F6C44(a3)` says yes.
- **Passer one-timer trigger** (doinput start, L35959). Applies to any joystick player with C new when:
  - `lastplayer == a3.SCnum`, `passplayer >= 0` and `onetimerplayer < 0`;
  - receiver R = SortCords[passplayer] is not a goalie;
  - `sub_F6C44(R)` says yes;
  - R is not pfjoycon and R pflags3 bit 3 is clear.

  Then: `inputjoy = d4`, `TmpJoyPuckCarrier = joypuckcarrier`, `assreplace(R, $23)`, and doinput returns.

---

## 3. Routines

### burst (L36830)
- Purpose: speed burst in the facing direction (C without the puck), also used as the CPU "throw check" from check4check (when `VDP_CNTR & 3 != 0` and the carrier is not in the slot).
- Inputs: a3 player; facedir high word `$54`; team energy via getpde; `OptLine`; `byte_FFC2FC` bit 4.
- Outputs: Xvel `$28` and Yvel `$2A` (added), the energy table entry (decremented), pfalock, SPA.
- Logic:
  1. `E = getpde()` (word energy, see §5; also leaves a2 = team struct and d1 = pnum·2).
  2. If `OptLine == 0` (line changes on):
     - `E = E − $CC` (204), then `setpde(E)`. setpde clamps a negative value to 0 in BOTH the stored value and d0, so `E = max(0, E−204)`.
     - Then, only inside this branch, if `byte_FFC2FC` bit 4 is set: `E = $1000`.

     If OptLine != 0, E is the unmodified current energy, with no drain and no override.
  3. `k = E >> 7` (lsr.w, unsigned; 0..32).
  4. `dir = facedir.hi`; `Xvel += (dirtab[dir].x * k)` and `Yvel += (dirtab[dir].y * k)`, using the low 16 bits of the muls product (add.w, wraps). Max added = 200·32 = 6400 rvu.
  5. Set pfalock (`$62` bit 5). `SetSPA($C5E)` (tail call).
- Quirks: no speed cap is applied here; the facedir high word is used without masking (assumed 0..7).

### holdplayer (L36863) / Acheck (L36874)
- Purpose: hold / hook animation. Human (A without the puck) enters at holdplayer. The CPU (check4check, with a0 = the opponent being checked) enters at Acheck.
- Inputs: a3; impact `$32`; impactp `$2E`; Ypos of a3 and a0; pfgoal.
- Outputs: pfalock, SPA.
- Logic (holdplayer):
  1. Set pfalock. `d1 = $1122`. If `a3.impact == 0` → `SetSPA($1122)`, return.
  2. `a0 = SortCords + a3.impactp*128` (the last player who caused an impact). Fall into Acheck.
- Logic (Acheck):
  1. Set pfalock. `d1 = $1122`. If `impact == 0` → SetSPA(d1).
  2. `rel = a3.Y − a0.Y` (word). If pfgoal (`$62` bit 7) is set, `rel = −rel`.
  3. If `rel < 0` (sign of the word result) → SetSPA($1122). Else (rel ≥ 0) → SetSPA($C90).
- Note: no velocity or impact effect here. The effect of a hold is elsewhere (collision code).

### setpassmode (L36893)
- Purpose: enter pass-aim mode with the default direction = facing.
- Inputs: facedir; BA_PS_flags.
- Outputs: passdir, sflags bit 2, PS flags.
- Logic:
  1. `passdir = facedir.hi & 7`.
  2. If `BA_PS_flags` bit 2 (penalty shot):
     - clear `word_FFC2FA` bit 2;
     - test-and-set `BA_PS_flags` bit 5. If it was already set → return WITHOUT entering pass mode (only one attempt);
     - otherwise clear `word_FFC2FA` bit 5 and set `word_FFC31C = $64`.
  3. Set `sflags` bit 2. Return.

### passmode (L36913)
- Purpose: per-loop pass-aim handling for the human carrier while sflags bit 2 is set.
- Inputs: d0 d-pad, d2 changed buttons, `word_FFC2F6` bit 3.
- Logic (verified from bytes at $BC40):
  1. If d2 bit 4 (B changed, i.e. released) → `dopass`.
  2. If `word_FFC2F6` bit 3 → `dopass`.
  3. If d0 bit 3 (no direction) → return.
  4. `passdir = d0 & 7`, then **fall through into dopass** (`bset #3,d0` precedes it but d0 is saved/restored by dopass, so it has no effect).

  So with B held and a d-pad direction pressed, the pass fires immediately in that direction. With no direction it waits for the B release and uses the default facedir.

### dopass (L36924-L37069; label inside passmode)
- Purpose: release the puck as a pass: flip pass, pass to the best teammate, or a blind pass in passdir. Then set the passer's anim and sfx.
- Callers: passmode (human), chk4pass (CPU, `bsr dopass` with passdir already set).
- Saves and restores d0-d5/a0-a1 (a2 is clobbered by passtoa0/loadTeamStruct).
- Inputs: a3 passer; passdir; passacc `$6E`; position `$34`; teammates' structs; puck pos/vel.
- Outputs: sflags bit 2 cleared, puckc, passer nopuck, lastplayer, puckvx/vy/vz, the receiver's assignment and fields (via passto), passer SPA, pfalock, sfx.
- Logic:
  1. Clear `sflags` bit 2. `st.b puckc` (puckc becomes negative). `a3.$5E` (nopuck byte) = $10. `lastplayer = a3.SCnum`.
  2. **Flip branch**: if `bclr #3,word_FFC2F6` found the bit set:
     - `sub_F67E4()` (target, see below);
     - `word_FFD418 = $12`; if `word_FFC2F8` bit 2 is set, `word_FFD418 = $3A`;
     - `sub_F6778()` (velocity);
     - go to step 6.
  3. **_LoadPassAttribForPassStart / pass speed**:
     - `d0 = 8` if goalie (position == 0), else `d0 = passacc` (byte, 0..30);
     - `v = ((d0 << 2) >> 1) + $A0`, i.e. `2·d0 + 160` (goalie: 176). `passspeed = v`;
     - if `a3.$6E` bit 0 is set (odd passacc; for a goalie it tests the goalie's own $6E byte): `passspeed += v >> 4` (asr.w).

     Results: passacc 30 → 220, 29 → 218+13 = 231, 0 → 160.
  4. **_findplayer**: choose the receiver. `best = $FFFFFFFF` (unsigned). a1 = the first struct of the passer's team: SCnum 0, or 6 if `a3.SCnum >= 6` (away). If away AND `BA_PS_flags` bit 2 → skip directly to `_nopp` (this check exists only for the away team; see quirks). For each of the 6 structs a1:
     - skip if a1 == a3 (self), if `a1.position == 0` (goalie; note negative/off-ice positions are NOT skipped), or if `a1.$63` bit 2 is set (listing: "unavailable");
     - `dX = a1.X − puckx`, `dY = a1.Y − pucky` (words). `dir = vtoa(dX, dY)` (8 if both are zero);
     - `diff = (dir − passdir) & 7`. Angle penalty: `p = (sign_extend_byte((diff << 5) & $FF) << 3)`, so diff 0..7 gives 0, 256, 512, 768, −1024, −768, −512, −256. `pen = p*p` (long). If `pen > 65536` (unsigned) → skip. Only diff 0 (pen 0) and diff ±1 (pen 65536) survive;
     - `score = dX*dX + dY*dY + pen` (32-bit). If `score <= best` (unsigned; ties replace, so a later struct wins a tie) → `best = score`, `a0 = a1`.

     If best is still negative (`tst.l; bmi`, i.e. no candidate) → `_nopp`. Else `passto(a0)` (§ passto), then step 6.
  5. **_nopp** (no receiver; hit the puck in passdir):
     - `puckvy = (((dirtab[passdir].y * passspeed) << 10) / $BB8) + a3.Yvel`, using signed 32/16 division (quotient word; $BB8 = 3000 = runspeed·15);
     - `puckvx` likewise with `.x` and `a3.Xvel`;
     - `puckvz = randomd0($1000)` (0..4095, word).

     For a cardinal direction this is ≈ passspeed·68.27 rvu plus the passer's velocity.
  6. **_exit**: for a goalie passer (position == 0), force the pass up-ice: if pfgoal = 1 and `puckvy < 0` → negate it. If pfgoal = 0 and `puckvy >= 0` → negate it (0 stays 0). (The N flag from `tst.w puckvy` survives the `btst`.)
  7. Anim and sound:
     - `ld = vtoa(puckvx, puckvy)`. Goalie: SPA $366. Skater: `$718`, but `$78A` if `Findhittype(ld)` returns NE. Then `SetSPA`, set pfalock;
     - sfx = `$10 + (((byte)($0C − puckvz_hi) >> 2) & 3)`, where puckvz_hi is the HIGH byte of puckvz (`sub.b (puckvz).w`) and the subtraction is 8-bit then zero-extended to a word before `lsr.w #2`;
     - for passto passes (puckvz_hi = min(t,12), t = 1..24): hi 9..12 → $10, 5..8 → $11, 1..4 → $12;
     - for `_nopp` (hi 0..15): hi 0 → $13, 1..4 → $12, 5..8 → $11, 9..12 → $10, 13..15 → $13 (byte wrap).
  8. Restore registers, rts.
- Quirks:
  - The PS skip in step 4 applies only to the away team.
  - Off-ice players (negative position) can be chosen as receivers.
  - The odd-passacc bonus applies to passes (unlike shots, see doshot).
  - A CPU pass (chk4pass) also takes the flip branch if `word_FFC2F6` bit 3 happens to be set.

#### sub_F67E4 (L958958): flip-pass target (94 only)
- Inputs: a3 passer (position, X, Y, facedir, pfgoal). Outputs: `word_FFD414` (target x), `word_FFD416` (target y), `word_FFC2F8` bit 2.
- Logic:
  1. Clear `word_FFC2F8` bit 2.
  2. If goalie: `T = word_F691E`. Else:
     - `yr = a3.Y`, negated if pfgoal = 0 (so yr > 0 is toward the attacked goal);
     - set `word_FFC2F8` bit 2 and `T = word_F68DE`;
     - if `yr >= $58` (88, signed): `T = word_F68FE` and clear bit 2.
  3. `i = facedir.hi`. If pfgoal = 0: `i = (i + 4) & 7`. `(tx, ty) = T[i]`.
  4. If `T == word_F68FE`, `|a3.Y| >= $8A` (138) and `|a3.X| <= $37` (55) → `ty = $103` (259). The comparisons are signed `blt`/`bgt`.
  5. If pfgoal = 0: `tx = −tx`, `ty = −ty`.
  6. `tx += randomd0(10)`, `ty += randomd0(10)` (each 0..9). `word_FFD414 = tx`.
  7. If not a goalie, keep at least 60 px of X separation from the passer:
     - `d = tx − a3.X`;
     - if `d >= 0`: if `d − 60 < 0` → `word_FFD414 += 60 − d` (target x becomes X+60);
     - else (d < 0): if `d + 60 >= 0` → `word_FFD414 −= d + 60` (target x becomes X−60).
  8. `word_FFD416 = ty`.

#### sub_F6778 (L958922): flip-pass velocity
- Inputs: `word_FFD414/416/418`, puck pos. Outputs: puckvz, puckvx, puckvy, puck facedir/SPA (via puckflip).
- Logic:
  1. `vz = sroot((($C * word_FFD418) & $FFFF) << 16)`. The `mulu`, `swap` and `andi.l #$FFFF0000` give `(12h) << 16`, so `vz ≈ 256·sqrt(12h)`. `puckvz = vz`.
  2. `t = vz / 3` (divu.w of ext.l). If `t == 0` → 1.
  3. `puckvx = ((word_FFD414 − puckx) << 16) / t` (the word difference placed in the high word, low word 0, divs.w; quotient word, overflow leaves the low word = 0).
  4. `puckvy = ((word_FFD416 − pucky) << 16) / t`.
  5. `puckflip(a3 = puck struct $FFB74A, d0 = puckvz)`: `puck.facedir.hi ^= (d0 & 1)`, then `&= 3`; `puck.SPAcnt = $FF..`; `SetSPA($46A)`. a3 is restored afterwards.
- Physics note (derived, for checking the port): with gravity 102 rvu/vblank (updateplayers), the apex height is ≈ h px (h = $12 → 18 px, a low flip into the slot; $3A → 58 px, a high dump), and the puck lands at the target after ≈ vz/51 vblanks.

### Findhittype (L37396; listing mis-disassembled, decoded from ROM $C198)
Bytes: `4440 d06b0054 02400007 082b00030004 67000008 013c00f0 4e75 | 013c001e 4e75`

```
neg.w  d0
add.w  $54(a3),d0      ; facedir hi word
andi.w #7,d0           ; rel = (facedir - launchdir) & 7
btst   #3,4(a3)        ; attribute word bit 11 = x-flip
beq.w  .nf
btst   d0,#$F0         ; Z = bit rel of $F0 clear
rts
.nf: btst d0,#$1E      ; Z = bit rel of $1E clear
rts
```
The listing shows garbage after the `beq`. The bytes show that the beq at $C1A8 (taken when x-flip is CLEAR) jumps to $C1B2 (`btst d0,#$1E`), and the fall-through at $C1AC (`btst d0,#$F0`) runs when x-flip is SET (`btst d0,#imm` tests bit `rel` of the immediate byte). The resulting table:
- x-flip clear (bit 11 = 0): backhand (NE) for rel ∈ {1,2,3,4}, forehand (EQ) for rel ∈ {0,5,6,7}.
- x-flip set: backhand for rel ∈ {4,5,6,7}, forehand for rel ∈ {0,1,2,3}.

Returns the result in Z only: EQ = forehand, NE = backhand. Callers: dopass (launch dir = vtoa(puckv)), SetShotMode (dir to the far boards).
(Check: `beq.w` at $C1A8 with displacement $0008 targets $C1AA+8 = $C1B2.)

### passto (L37074)
- Purpose: controller hand-off when a human-controlled GOALIE passes, then passtoa0.
- Inputs: a3 passer, a0 receiver.
- Logic:
  1. If passer is not pfjoycon → passtoa0. If passer position != 0 (**skater**) → passtoa0. Only a joystick-controlled goalie continues (verified: `4a6b 0034 6600`).
  2. If the receiver is already pfjoycon → passtoa0.
  3. Set receiver `$64` bit 6.
  4. If `cont1team == cont2team` (co-op): `setc1player(receiver)` if the passer is `c1playernum`, else `setc2player(receiver)`.
  5. Else: `team = 1` (home) or 2 (away, passer `$62` bit 6). `setc1player(receiver)` if `cont1team == team`, else `setc2player(receiver)`.
  6. Fall into passtoa0.
- (setcNplayer: if d0 != current → `restorep1(old)`: the old player loses pfjoycon and gets pfna unless pflags3 bit 3; the new player gets pfjoycon, with special goalie cases. Not in scope.)

### passtoa0 (L37114-L37216): lead pass to receiver a0
- Inputs: a3 passer, a0 receiver; passspeed; receiver X/Y, Xvel/Yvel, current frame (hot spot); puck pos.
- Outputs: passer team stat `$12` += 1; passplayer; the receiver's assignment ($13 asspassrec inserted, pfna); receiver temp1 high byte `$40`, temp3 `$44`, temp4 `$46`; puck `$5E` byte; puckvz high byte; puckvx; puckvy.
- Logic (all intermediate values are 16-bit words unless stated):
  1. `a2 = loadTeamStruct(a3)`; `a2.$12 += 1` (pass attempts).
  2. `passplayer = a0.SCnum`.
  3. `s = passspeed >> 2` (asr.w; "pixels per 1/4 s").
  4. On the receiver: `assinsert($13)`, i.e. `assnum = (assnum − 1) & 7`, `asslist[assnum] = $13`, set pfna (assinsert falls into assreplace).
  5. `(hx, hy) = GetHot(receiver)` (stick hot-spot offset of the receiver's current frame; x negated if x-flip; y negated unless y-flip; (0,0) if frame <= 0; swapped in horizontal mode). Already used by pucknorm.
  6. `Ax = hx + a0.X − puckx`, `Ay = hy + a0.Y − pucky` (target = receiver's stick). `ax = Ax >> 2`, `ay = Ay >> 2` (asr.w).
  7. `vx = (a0.Xvel * $F0) >> 16` and `vy = (a0.Yvel * $F0) >> 16` (signed muls, high word = floor; "pixels per 1/4 s").
  8. `j = (word)((word)(vx*ax + vy*ay) << 1)`. The two products are added with `add.w` (16-bit) and then doubled as a word.
  9. `k = vx*vx + vy*vy − s*s` (32-bit).
  10. `a2sq = ax*ax + ay*ay` (32-bit). `q = (int16)k * (int16)a2sq` (muls.w uses the LOW WORDS of both), then `q <<= 2` (asl.l). `D = j*j − q` (32-bit). `r = sroot(D)` (sroot treats D as unsigned).
  11. `kd = (int16)(k.lo) >> 2` (asr.w on the low word only); if `kd == 0` → `kd = 1`.
  12. Root search (at most 2 tries):
      ```
      try +r:  t = (int32)(int16)(r - j) / kd   (divs.w; quotient word)
               if t >= 0 (N clear) -> done
      try -r:  t = (int32)(int16)(-r - j) / kd
      ```
      (The code: `d2 = d0; d0 = −d0; d2 −= j; ext.l d2; divs.w d5,d2; dbpl d3,loop` with d3 = 1.) After the loop, if the Z flag from the last divs is set (t == 0) → `t = 1`.
  13. If `t > $18` as **unsigned** (so negatives too) → `t = $18`. t is the flight time in 1/8 s (≤ 3 s).
  14. `puckvz.hi_byte = t`; if `t >= $C` (signed) → `puckvz.hi_byte = $C`. **Only the high byte of puckvz is written** (`move.b`, verified `11c2 b776`). puckvz ≈ min(t,12)·256 + old low byte.
  15. `w = t*8 − $A`; `receiver.$40` (temp1 high byte) = (byte)w. `w −= 6`; puck `$5E` byte ($B7A8) = (byte)w, i.e. t·8 − 16. Both can be negative bytes when t is small.
  16. `ix = ((vx * t) >> 1) + Ax` (muls, asr.l, add.w). `receiver.$44 = puckx + ix` (intercept x).
  17. `iy = ((vy * t) >> 1) + Ay`. `receiver.$46 = pucky + iy` (intercept y).
  18. `den = t * $78` (120). `puckvx = ((ix << 16) | hiword_garbage) / den`.

      Exact: `swap d0` makes the high word = ix and the low word = the high word of the step-16 long, which is the high word of `(vx*t)>>1` (0 or $FFFF for a small product). `divs.w den`, quotient word to puckvx. On overflow puckvx = that low word.
  19. `puckvy` likewise with iy.
- Derivation (for review only): solves `|A + V·τ| = s·τ` with A scaled /4 and τ in quarter seconds, giving `t = 2τ` (eighths). Velocity = intercept distance / (t·7.5 vblanks), using 16/65536 px per rvu per vblank (the 93 constant; the engine actually moves 17/65536). Port the integer math literally.
- Quirk: asspassrec overwrites receiver temp4 (`$46`) with $FFFE on its first run, so the intercept Y is lost and temp3 is unused. The 94 receiver does not skate to the intercept point (see asspassrec).

### SetShotMode (L37411)
- Purpose: begin a shot windup. Callers: doinput (C new with puck), assshoot (new assignment).
- Logic:
  1. PS handling identical to setpassmode step 2: if `BA_PS_flags` bit 2, clear `word_FFC2FA` bit 2; if `BA_PS_flags` bit 5 was already set → return (no shot mode); else clear `word_FFC2FA` bit 5 and set `word_FFC31C = $64`.
  2. `passdir = 8`. Set `sflags` bit 3.
  3. `ld = vtoa(0 − a3.X, (pfgoal ? $128 : −$128) − a3.Y)`, the direction to the center of the far end boards (y = ±296).
  4. `passspeed = $F` (15). `d1 = $7FC`.
  5. If `Findhittype(ld)` returns NE: `d1 = $92E` (passspeed is set to $F again).
  6. `SetSPA(d1)` (tail call). pfalock is NOT set here.

### ShotMode (L37444)
- Purpose: per-loop windup/charge while sflags bit 3 is set. Human: from doinput with the real d0/d2. CPU: from assshoot with **d0 = the player's assnum (0..7)** (the dispatcher leaves `$36` in d0, and loadTeamStruct does not touch it) and d2 = 0 or bit 5.
- Logic:
  1. If `SPAnum >= $1C` (signed) → `prepshot` (launch).
  2. If d0 bit 3 is clear → `passdir = d0 & 7` (aim with the d-pad; no direction keeps the previous value, default 8).
  3. If `SPAnum >= $10` → return (windup over; no more charge, button ignored).
  4. `passspeed += d7` (the charge is in elapsed vblanks).
  5. If `(int8)shotspd < $14` (20) and `SPAnum > 8` → step 7 (forced release for weak shooters).
  6. If d2 bit 5 (C changed/released) is clear → return.
  7. `SPAnum = $1C − SPAnum` (`neg.w`, `addi.w #$1C`). This jumps to the mirrored point of the forward swing: 0 → $1C (immediate contact next loop), 4 → $18, 8 → $14, $C → $10.
- Charge results (derived, d7 = 1 at 60 Hz): each windup entry lasts 5 loops, so a full windup (C held until SPAnum reaches $10) gives `passspeed ≈ 15 + 20 = 35`. A weak shooter (shotspd < 20) is forced at the first loop with SPAnum = $C: ≈ 15 + 16 = 31. A tap (released the next loop) gives ≈ 16. This is a timed charge; there is no separate power meter.
- Quirk: for the CPU, passdir is overwritten each windup loop with assnum & 7. It matters only for prepshot's top-shelf test, because doshot→shotdiradj recomputes passdir for CPU shooters.

### prepshot (L37473)
- Purpose: set the "in-close top shelf" flag, then fall into doshot (`bra.w *+4` = doshot).
- Logic:
  1. Clear `word_FFC2F6` bit 4.
  2. `g = getGoalieSCnum(a3 home ? $B : 5)`. getGoalieSCnum scans SCnum d0, d0−1, …, d0−5 for position == 0 and returns its SCnum or $FFFF.
  3. If g < 0 (no goalie) → step 4. Else if `goalie.SPA` is $250 or $2A2 (pad stack) → step 4. Else → doshot. (The Z flag from the cmpi survives `movem.l (sp)+,a0`.)
  4. If passdir (signed) <= 1 (i.e. 0 or 1) or passdir == 7: `yr = pucky`, negated if pfgoal = 0. If `yr >= $D8` (216, signed) → set `word_FFC2F6` bit 4.
  5. doshot.

### doshot (L37514-L37697; ROM $C2F2, verified byte-for-byte)
- Purpose: launch the shot. Callers: prepshot (normal shot), onetimershot.
- Saves d0-d7/a0-a3. One sfx word is pushed on the stack and played at exit (`sfx` pops its argument).
- Inputs: a3 shooter; passspeed (raw charge); passdir; SPA; shotspd `$6C`; shotacc `$6D`; energy; pflags3 bits 1 and 3; puck pos; gmode; shootout; tmgoalie.
- Outputs: shotplayer, sflags bit 3 cleared, pfalock, sflags2 bit 4, passspeed (final), puckc, nopuck, lastplayer, puckvx/vy/vz, `word_FFC2FA` bit 4, sfx.
- Logic:
  1. Clear `word_FFC2FA` bit 4; if pflags3 bit 1 (breakaway) → set it.
  2. `shotdiradj()` (may rewrite passdir).
  3. `sfx = $05` (whiff). `shotplayer = a3.SCnum`. Clear `sflags` bit 3. Set pfalock.
  4. If NOT a one-timer (pflags3 bit 3 clear) and `puckc != a3.SCnum` → play sfx $05 and return. **Whiff**: no puck launch; shotplayer is still set.
  5. `sfx = $18` (forehand). Set `sflags2` bit 4 (shot taken).
  6. If `a3.SPA == $92E` (backhand): `sfx = $14`; `passspeed −= passspeed >> 2` (lsr.w; −25%).
  7. If a one-timer: `passspeed = $1F` (31), overriding step 6.
  8. **Shot power**:
     ```
     k   = shotspd >> 1                       ; byte, unsigned (0..15)
     k   = makepde(k)                         ; floor(k * E / 4096), E = energy 0..$1000 ($1000 if byte_FFC2FC bit 4)
     k  += $14                                ; +20  -> 20..35
     p   = (uint16)(k * passspeed)            ; mulu.w; low 16 bits used next
     passspeed = (p * $5249) >> 16            ; mulu.w, swap: * 21065/65536 (= 9/28 approx 0.3214)
     ```
     Examples (full energy): raw 35 & shotspd 30 → 35·35 = 1225 → 393. Raw 35 & shotspd 0 → 225. One-timer (31) & shotspd 30 → 348. Tap (16) & 30 → 180.
  9. **Sound variant** (does NOT change the speed):
     ```
     v = passspeed
     if (shotspd & 1) v = (v >> 4) + passspeed     ; asr.w then add.w  (odd-rating bonus is sfx-only!)
     off = 3 - (v >> 4)  (lsr.w);  if off < 0: off = 0
     sfx += off          ; $18..$1B forehand, $14..$17 backhand
     ```
  10. `st.b puckc`. `a3.$5E = $10` (nopuck). `lastplayer = a3.SCnum`.
  11. **Aim**:
      - `gy = pfgoal ? $108 : −$108`;
      - `(ox, z) = shotsets[passdir]`;
      - `dx = ox − puckx`, `dy = gy − pucky`;
      - `dist = sroot(dx*dx + dy*dy)` (muls, 32-bit add); if `dist == 0` → 1;
      - keep dx, dy and z as the mutable "aim vector" (they live on the stack).
  12. **Perfect-shot test** (any true → skip the error, go to step 14):
      - `gmode` bit 4 (highlight) → perfect;
      - if `dist > $C8` (200, unsigned) → NOT perfect (go to step 13; no roll);
      - `ReadGoaliePulled()` returns N (the SHOOTER's own team tmgoalie `$26` is negative, i.e. own goalie pulled) → perfect;
      - shootout (`word_FFC2FA` bit 0) → perfect;
      - `r = randomd0($10 + shotacc)` (byte add); if `r > $E` (signed, i.e. r ≥ 15) → perfect.

        P(perfect | dist ≤ 200) = (shotacc+1)/(shotacc+16): 1/16 at 0, 31/46 at 30.
  13. **Accuracy error** (_notperf):
      ```
      e  = (passspeed >> 4)                          ; lsr.w, word
      e.lo_byte = (uint8)(e.lo_byte - (shotacc >> 1) + $10)   ; sub.b / addi.b: 8-bit wrap, high byte of the word kept
      e  = (uint16)(e * dist) >> 6                    ; mulu.w, then lsr.w on the LOW word only
      if dist <= $FA (250, unsigned): e >>= 1          ; lsr.w
      if (int16)e >= $88: e = $88                      ; cap 136
      dx += randomd0s(e)                               ; -e..e-1
      ey = e; if ey > $3C (unsigned): ey = $3C          ; cap 60 (this capped value is what is popped below)
      ey2 = ey; if dy < 0 (signed): ey2 >>= 1           ; halve Y error when dy is negative (shots at the bottom goal from in front of it)
      dy += randomd0s(ey2)
      z  += randomd0(ey >> 1)                          ; 0..ey/2-1 (z only goes up)
      ```
      dist is NOT recomputed after the perturbation. Errors in dx/dy therefore change the speed as well as the direction.
  14. **Velocity** (_perf):
      ```
      m = (int16)(passspeed * $44)                     ; muls.w #$44 (68 = 1024/15); low word used next
      puckvx = (int32)(m * dx) / dist                  ; divs.w; quotient word; on overflow puckvx = low word of m*dx
      puckvy = (int32)(m * dy) / dist                  ; same
      ```
      A straight shot moves at ≈ passspeed·68 rvu (393 → 26724 rvu ≈ 6.9 px/vblank).
  15. **Direction guard** (uses the word just stored in puckvy):
      - top goal (pfgoal = 1): if `puckvy < 0` → `puckvy = $3810` (14352);
      - bottom goal: if `puckvy >= 0` → `puckvy = $C7F0` (−14352).

      (`d1 = $8000` or 0; `eor.w d2,d1; bpl ok`.) puckvx is not touched.
  16. **Elevation**: if `z == 0` → skip to the exit (**puckvz is not written**; it keeps its previous value). Else:
      ```
      a = (uint16)(z * passspeed) * $44                ; mulu.w, mulu.w (low word of z*ps used)
      a = (uint32)a / dist   -> low word (divu.w; overflow keeps low word of a)
      b = (uint32)(dist * $B33) / passspeed -> low word ; $B33 = 2867 = 1024*42/15 (divu.w)
      vz = (uint16)(a + b); if vz > $1800 (unsigned): vz = $1800
      puckvz = vz
      ```
      Physics (derived): with gravity 102 rvu/vblank this makes the puck reach height z at the goal line.
  17. **Top-shelf float**: `bclr #4,word_FFC2F6`. If it was set and this is NOT a one-timer → `puckvzadj()` (overrides puckvz). The bit is cleared in either case on this path.
  18. Play sfx (the pushed word), restore registers, rts.
- Quirks to keep:
  - The odd-shotspd "+1/16" only alters the sfx choice.
  - The Y error is halved only when dy < 0.
  - dist is not renormalized after the error.
  - ReadGoaliePulled checks the shooter's own team.
  - z == 0 leaves puckvz stale.
  - `passspeed*$44` exceeds 16 bits signed if passspeed > 481 (unreachable with ratings ≤ 30 and normal frame pacing).
  - The direction guard can push a puck behind the goal line (dy < 0 while shooting at the top goal) out toward the end boards at $3810.

### shotsets (L37697)
See §1.3 (9 entries × (x, z) words, indexed by passdir 0..8).

### shotdiradj (L37721)
- Purpose: choose passdir for CPU shooters and for ALL one-timers: aim at the side of the net away from the goalie.
- Inputs: a3 shooter (pflags3 bit 3, pfjoycon, pfteam, pfgoal); the opposing goalie's X, Y and the high bytes of Xvel/Yvel; puck pos; PS/SO flags.
- Outputs: passdir.
- Logic:
  1. If not a one-timer and pfjoycon (human) → return (keep the human's passdir).
  2. `d0 = 8`. Find the opposing goalie: scan the opponent's 6 structs (away SCnum 6-11 if the shooter is home, else 0-5) in order. The first with position == 0 is G. If none → `passdir = 8`, go to step 7.
  3. `gx = sign_extend(byte at G+$28) >> 1` (asr.w; the HIGH byte of Xvel, ≈ Xvel/512 px). `dx = gx + G.X − puckx`. Likewise `dy = (sign_extend(byte G+$2A) >> 1) + G.Y − pucky`.
  4. `gd = sroot(dx*dx + dy*dy + 1)`.
  5. `gl = pfgoal ? $108 : −$108`. `s1 = shotdirmath(dx, dy, gd, $12, gl)`. `s2 = shotdirmath(dx, dy, gd, −$12, gl)`. `s = (int16)(s1 + s2)`.
  6. `d0 = 0`. If `s > $2C` (44) or `s < −$2C` (signed) → `passdir = 0`. Else:
     - if pfgoal = 1 → `s = −s`;
     - `passdir = (s >= 0) ? 2 : 6`.
  7. If `BA_PS_flags` bit 2 or `word_FFC2FA` bit 0 (penalty shot or shootout) → `PSandSOpassdir()`.
- Result set: passdir ∈ {0, 2, 6, 8} (or a script value in PS/SO): 0 = center high (goalie well off the puck→goal line), 2 = right post side mid height, 6 = left post side mid height.

### shotdirmath (L37806-L37838)
- Inputs: d0 = dx (goalie − puck), d1 = dy, d2 = gd (distance), d3 = post X, d4 = goal line Y. Output: d4.
- Logic: `px = d3 − puckx`; `py = d4 − pucky`; `d4 = (int32)(dx*py) − (int32)(dy*px)` (muls.w each); `d4 = d4 / gd` (divs.w; quotient word, remainder in the high word, which callers ignore).
- Meaning: the signed perpendicular distance of the post from the puck→goalie line.

### puckvzadj (L958869; verified from ROM $F66EE)
- Purpose: "float" the puck for an in-close top-shelf shot over a pad-stacking or absent goalie. Called by doshot.
- Inputs: pucky, puckvy; `word_FFD06E` (never set, so the constant is 17). Output: puckvz.
- Logic:
  1. `dist = | |pucky| − $108 |` (distance to the NEARER goal line by |pucky|).
  2. If `puckvy == 0` → return (puckvz unchanged).
  3. `v = |puckvy|`. `c = 17` ($11; $16 if `word_FFD06E` != 0).
  4. `T = ((dist << 16) / v) & $FFFF` (divu.w; on overflow d0 is unchanged, so the low word is 0). `T = T / c` (divu.w, low word). If `T == 0` → `T = 1`. T = vblanks until the puck reaches the goal line.
  5. `a = $A0000 / (T * c)` (divu.w; uses the low word of the quotient).
  6. `b = 3*c*T` (= 51·T). If `b >= $7FFF` (signed long compare) → `b = $7FFF` (low word).
  7. `vz = (int16)(a + b)`; if negative → `$7FFF`. `puckvz = vz`.
- Physics: makes the puck be at height 10 px when it reaches the goal line (`vz = 10·65536/(17T) + 51T`).

### PSandSOpassdir (L974238) and passdirlist (L974252)
- Inputs: `word_FFDA1A` (CPU penalty-shot/shootout script direction, set by sub_FE7FC from the move scripts at unk_FE788); pfgoal. Output: passdir.
- Logic: `d = word_FFDA1A`. If pfgoal = 1 → `passdir = d`. Else `passdir = passdirlist[d]` = `{0,7,6,5,4,3,2,1,8}[d]` (left-right mirror).
- Note: this is called only from shotdiradj, so it affects CPU shooters and one-timers in PS/SO. A human shooter in PS/SO keeps their own aim (and their shots are perfect in a shootout).

### asspassrec (L40938), assignment $13
- Purpose: pass receiver behaviour, plus the CPU's decision to one-time the pass.
- Inputs: a3 receiver; temp1 high byte `$40` (set by passtoa0 = t·8−10); puckc; onetimerplayer; cont1team/cont2team; position; Y; d7.
- Logic:
  1. If pfalock → return.
  2. If `gmode` bit 0 (clock stopped) → `assnothing` (pfalock/joycon → nothing; else `doplayeracc(8)`, i.e. decelerate).
  3. If pfjoycon → `assexit` (`assnum = (assnum+1)&7`, set pfna).
  4. If pfna was set (bclr):
     - set pfdoff (`$62` bit 0: deceleration off, so the receiver glides);
     - `$43` (temp2 low byte) = 8, `$42` = 0;
     - `$46` (temp4) = $FFFE (−2). This overwrites passtoa0's intercept Y.
  5. If `puckc >= 0` (someone has the puck) → step 10.
  6. `temp4 += 1`. If the result is > 0 → step 9. (Result 0 or negative → step 7.)
  7. One-timer decision. If `onetimerplayer >= 0` → step 9. If position == 0 (goalie) → step 9. Otherwise:
     - `temp4 = 0` (so only one decision);
     - `team = home ? 1 : 2`. If `cont1team == team` or `cont2team == team` → step 9 (human teams use the button instead);
     - if `sub_F6C44()` says no (Z set) → step 9;
     - `yr = Y`, negated if pfgoal = 0. If `$58 <= yr <= $108` (88..264, signed) → attack zone, step 8. Else `randomd0(8)`: if non-zero → step 9; if 0 (1 in 8) → step 8.
  8. `inputjoy = $FFFF`; `assreplace($23 assonetimer)`; return.
  9. `temp1.hi_byte −= d7` (sub.b). If the result is ≥ 0 (bpl) → return.
  10. Clear pfdoff; `assexit`.
- Note: the decision window is the first 1-2 calls (temp4 −1 and 0) unless step 7 runs, which zeroes temp4.
- Dead code: the 16 bytes after the routine (`302B 0044 322B 0046 41FA 67E8 6000 1748`: move temp3,d0; move temp4,d1; lea …; bra …) are unreachable. They look like the 93 "skate to intercept" tail. Do not port.

### assshoot (L41029), assignment $12
- Purpose: CPU shot driver. The assigner `compshoot?` (L40316) sets `temp2 = min(20, ($108 − yr) >> 3)` (lsr.w; yr = pucky toward the attacked goal; behind the goal line the unsigned shift makes it large, so 20), then `assreplace($12)`.
- Logic:
  1. If pfalock → return.
  2. If pfna was set (bclr) → `SetShotMode` (tail).
  3. If `sflags` bit 3 is clear → `assexit`.
  4. `d2 = 0`. `temp2 −= d7` (word). If ≥ 0 → `ShotMode` (keep winding). Else set d2 bit 5 (simulated C release) → `ShotMode`.
  5. d0 = assnum on entry (see the ShotMode quirk).
- Result: the CPU winds up for `temp2` vblanks (≤ 20, shorter close to the goal line) or until the forced release for shotspd < 20, then swings.

### assonetimer (L959091), assignment $23
- Purpose: one-timer windup timed to the puck's arrival; abort if the puck is caught by someone or moves away; clean up after the shot.
- Inputs: a3; pfna; pflags3 bit 3; `word_FFBF76`; puck pos/vel; puckc; SPAnum `$5A`; SPAcnt `$5C`; pf2aip `$63` bit 1; gmode; inputjoy; TmpJoyPuckCarrier.
- Logic:
  1. **Start** (pfna was set AND pflags3 bit 3 was clear before bset; the bset happens here):
     - clear `byte_FFC2FE` bit 5;
     - `word_FFBF76 = 0`, `word_FFBF6E = 0`, `st.b passplayer`;
     - `onetimerplayer = a3.SCnum`.
     - **Controller grab**: if a3 is not pfjoycon and `inputjoy >= 0`:
       - `inputjoy == 0` → controller 1: `setc1player(a3)`, but if `TmpJoyPuckCarrier == 0` the cont3/c3playernum pair is swapped in and out around the call (4-player tap);
       - `inputjoy > 0` → controller 2: `setc2player(a3)`, with the cont4/c4playernum swap if `TmpJoyPuckCarrier == 1`.
     - `d1 = setonetimeranim()` ($7FC or $92E); `SPAnum = 0`; `SetSPA(d1)`; set pfalock; set pf2aip. Return.

     If pfna was set but pflags3 bit 3 was already set, fall through to step 2 (pfna is consumed).
  2. **Proximity / direction check** (skipped if `word_FFBF76` bit 0, shot done → step 3):
     - `dx = puckx − X`. If `−60 < dx <= 60` (signed: `dx > $3C` → far; `dx > −$3C` → near) → check Y. Else (far in X): if `sign(dx) != sign(puckvx)` (`eor`, N set) → check Y; else → ABORT (puck moving away in X);
     - check Y: `dy = pucky − Y`. If `−60 < dy <= 60` → step 3. Else if `sign(dy) == sign(puckvy)` (eor ≥ 0) → ABORT; else → step 3.
     - Note: a zero puck velocity counts as "positive" in the eor test.
  3. If `puckc >= 0` → ABORT.
  4. If `gmode` bit 0 → END.
  5. If `SPAnum < $10` and `word_FFBF76` bit 2 is clear (**still in the windup**):
     - `ax = |X − puckx|`, `ay = |Y − pucky|`;
     - if `puckvx != 0` and `ay <= ax` → `(d, v) = (ax, puckvx)`; else `(d, v) = (ay, puckvy)`;
     - `v = |v|`, or 1 if 0. `T = (((d << 16) / v) & $FFFF) / 17` (divu.w twice; the second quotient is the low word; 17 = $11, or $16 if `word_FFD06E`). T = vblanks until the puck arrives;
     - `W = (6 − (SPAnum >> 2)) * 4`;
     - if `T > W` (signed) → `word_FFBF6E += d7` (unused), go to step 7;
     - else → `SPAnum = $18 − SPAnum` (start the swing at the mirrored frame), go to step 9.
  6. **Else (swing phase)**:
     - set `word_FFBF76` bit 2;
     - if bit 1 is clear and `SPAnum == $18` → `SPAcnt += $30` (hold the ready pose 48 extra vblanks) and set bit 1.
  7. If bit 1 is set, `SPAnum > $18` and bit 0 is clear (the pose passed without contact) → END.
  8. If bit 0 is set, `SPAnum == $18` and `SPAcnt > 1` (signed) → `SPAcnt = 1` (finish quickly after the shot).
  9. If pf2aip is clear (anim finished) → END. Else: if bit 0 is set → clear pfalock. Return.
  - **ABORT**: clear `byte_FFC2FE` bit 7, then END.
  - **END**: `sub_FEFF0()` then return.
- The shot itself happens in puckstick (context, L50610-50660) when the puck touches a player with pflags3 bit 3:
  - if dist² ≤ $64 (100): force SPAnum to $18 if it is < $18, and set `byte_FFC2FE` bit 7;
  - if dist² is in ($64, $144]: only force SPAnum to $18;
  - if dist² > $144: no contact this loop.

  Then, unless `sflags2` bit 4 (a shot was already taken) is set, the one-timer player calls `onetimershot` with no stick-strength check.

### setonetimeranim (L959316) and noidea (L959407); verified from ROM $F6C0A/$F6D22
- Purpose: choose a forehand or backhand one-timer animation.
- Logic:
  1. `d1 = $7FC`. `dir = vtoa(−X, (pfgoal ? $108 : −$108) − Y)` (direction to the goal center).
  2. `noidea(dir)`: `rel = (facedir.hi + ((8 − dir) & 7)) & 7`. If `rel <= 4` (signed): `Z = ((~attr) & $800) == 0`, i.e. Z set iff x-flip is set. Else: `Z = (attr & $800) == 0`, i.e. Z set iff x-flip is clear. noidea restores d0/d1, but **the Z flag from its last `andi.w` survives** `movem` and `rts`. The listing comment ("doesn't do anything") is wrong.
  3. setonetimeranim: `movem.w (sp)+,d0-d1` (d1 = $7FC; flags unchanged). If Z → keep $7FC (forehand), else `d1 = $92E` (backhand).
- Table: x-flip clear → rel 0..4 = backhand, 5..7 = forehand. x-flip set → rel 0..4 = forehand, 5..7 = backhand. This is Findhittype's split except at one relative direction each: x-flip clear, rel 0 (Findhittype gives forehand, noidea backhand); x-flip set, rel 4 (Findhittype backhand, noidea forehand). The direction here is to the goal center, not the launch direction. Port as is.

### sub_F6C44 (L959336)
- Purpose: one-timer gate. Is the puck in the player's attacking half?
- Logic: `yr = pucky`, negated if pfgoal = 0. If `yr >= 0` → `d0 = 1` (Z clear = yes), else `d0 = 0` (Z set = no). d0/d1 are then restored by movem; **the result is only in Z** (set by the `move.w #imm,d0`). The code between the `bra` and `_0` is unreachable.

### onetimershot (L959386)
- Purpose: perform the one-timer shot and record stats. Called from puckstick with a3 = the one-timer player.
- Logic:
  1. `passdir = 4` (always overwritten by doshot→shotdiradj because pflags3 bit 3 is set).
  2. `doshot()`. Takes the one-timer paths: no puck-carrier check, raw speed 31, no puckvzadj; the backhand sfx still applies if the SPA is $92E.
  3. Team stats `a0 = $FFC6CE` (home) or `$FFCA32` (away): `a0.$1C = a0.$1A`; `a0.$1A = a0.$18`; `a0.$18 = a3.pnum` (shift the "last touch / assist" chain).
  4. Set `byte_FFC2FE` bit 7. `crowdlevel += $96`. `CwdExciteLvl += $A`. `a0.$35C += 1` (one-timer attempts).
  5. Set `word_FFBF76` bit 0 (shot done), set pf2aip, set `word_FFC2F8` bit 1.

### sub_FEFF0 (L975250): end a one-timer
- Clear pflags3 bit 3, pfalock and pf2aip. `word_FFBF76 = 0`. `st onetimerplayer`.
- `SetSPA($50C)`.
- If position >= 0 → `Setplass` (reassign AI), else `assexit`.
- `SPAnum = 0`, `SPAcnt = $FF..` (st). Preserves d0/d1/a0.

---

## 4. Rating and button summary (what the port must reproduce)

**Shot speed (rvu)**, with `raw` = 15 + vblanks charged during the windup (§ShotMode). Backhand: `raw −= raw>>2`. One-timer: `raw = 31`.
```
k   = floor(((shotspd>>1) * E) / 4096) + 20        ; E energy 0..4096 (4096 if no-fatigue)
ps  = ((k*raw) & $FFFF) * $5249 >> 16
V   = (int16)(ps*68)                               ; base speed in rvu
puckvx = V*dx'/dist, puckvy = V*dy'/dist           ; dx',dy' = aim vector after error; dist before error
puckvz = min($1800, (z'*ps*68)/dist + dist*2867/ps)    (z'=0 -> unchanged; top-shelf -> puckvzadj)
```
- **Aim**: target = (shotsets[passdir].x, ±264) and height shotsets[passdir].z.
  - Human: passdir = the last d-pad direction during the windup, else 8.
  - CPU/one-timer: shotdiradj (0/2/6/8) or the PS/SO script.
- **shotacc**: P(perfect) = (acc+1)/(acc+16) within 200 px (every shot is perfect in highlights, in a shootout, or with the shooter's own goalie pulled). Otherwise error magnitude `e = (((ps>>4) − (acc>>1) + 16) · dist) >> 6`, halved within 250 px, capped at 136. X ± e, Y ± min(e,60) (halved if dy<0), Z + 0..min(e,60)/2−1.
- **Pass speed**: `160 + 2·passacc`, plus `(that)>>4` when passacc is odd (goalie: 176, +11 if its `$6E` is odd). passacc does not affect pass accuracy: target choice is purely geometric (±45° cone, distance² + 65536 penalty for 45°).
- **Pass Zvel**: lead pass = high byte min(t,12) (t = flight time in 1/8 s); blind pass = randomd0($1000); flip = 256·sqrt(12·h), h = 18 or 58.
- **Held button**:
  - B: hold to aim. Release (or a d-pad press while held) fires. No charge.
  - C with puck: hold to wind up; the charge = elapsed vblanks until the anim reaches entry 4 (≈ +20). shotspd < 20 is forced to release at entry 3.
  - C without puck: burst. Second C during a teammate's pass in flight: one-timer.
  - A with puck: tap or hold 15 loops → flip pass.

---

## 5. Helper routines used above (exact, since the formulas depend on them)

### makepde (L51186) / getpde (L51207) / setpde (L51224)
- `getpde`: `a2 = $HmShots` (+$364 if away); `d1 = (int8)pnum * 2`; `d0 = word[a2 + $32 + d1]` (energy).
- `setpde(d0)`: if `d0 < 0` → `d0 = 0`; `word[a2+$32+d1] = d0`.
- `makepde(d0 byte)`: `x = sign_extend_byte(d0)`. `E = getpde()` (for the player in a0); if `byte_FFC2FC` bit 4 → `E = $1000`. `d0 = (int16)(((x*E) << 4) >> 16)` (muls, asl.l #4, swap, ext.l), i.e. `floor(x·E/4096)`.

### sroot (L44215): integer square root of an unsigned long
- 0 → 0.
- `n <= $640`: `d1 = −1; do { d1 += 2; n.w −= d1 } while no borrow; return d1 >> 1` (floor sqrt).
- `n > $F00000` (unsigned): bisection, `lo = 0`, `hi = $FFFF`:
  ```
  loop:
    mid = (lo + hi) >> 1     ; 17-bit add via roxr
    if mid == lo: return lo
    if n >= mid*mid: lo = mid   ; unsigned
    else: hi = mid
  ```
- Else: Newton.
  ```
  g = (n >> 8) + 2           ; word
  repeat up to 10 times:
    p = g
    g = ((n / p).lo + p) >> 1  ; divu.w, add.w, lsr.w
    if g == p: break
  return g
  ```
  This is not always exactly floor.

### randomd0 (L44190) / randomd0s (L44178)
- `seed = seed * $BB40E62D + 1` (32-bit; RNGseed long, high word at RNGseed). Result `= (((seed >> 8) & $FFFF) * n) >> 16`, so 0..n−1. `randomd0s(n) = randomd0((2n) & $FFFF) − n`.

### Others (reference only)
- `SetSPA(d1)`: if `SPA == d1` → no-op. Else `SPAnum = 0`, `SPA = d1`, `SPAcnt.hi = $FF` (restart).
- `assinsert(d0)` (L43202): `assnum = (assnum−1)&7`, then `assreplace`: `asslist[assnum] = d0`, set pfna.
- `assexit` (L43192): `assnum = (assnum+1)&7`, set pfna.
- `sfx`: the word argument is on the stack (callee pops it); a negative id = none.
- `ReadGoaliePulled` (L975229): N flag of `tst.w team.$26` (tmgoalie; $FFxx = no goalie) for the team of a3.
- `getGoalieSCnum` (L36508): described in prepshot.
- `GetHot` (L43282): described in passtoa0 step 5.

---

## 6. Quirks list (port as is)

1. passmode falls into dopass as soon as a d-pad direction is pressed while in pass mode (verified in the ROM bytes).
2. In dopass, the BA_PS skip of target selection exists only for the away team. Off-ice players (negative position) are not excluded as receivers.
3. passto switches controllers only when a human GOALIE passes.
4. passtoa0 writes only the high byte of puckvz. Its intercept Y is destroyed by asspassrec's init (temp4 = $FFFE).
5. In doshot the odd-shotspd bonus changes only the sfx. In dopass the odd-passacc bonus changes the speed.
6. doshot: dist is not renormalized after the random error; the Y error is halved only when dy < 0; z == 0 leaves puckvz stale.
7. ReadGoaliePulled tests the shooter's own team (own goalie pulled → perfect shots).
8. CPU ShotMode writes passdir = assnum & 7 during the windup (affects only prepshot's top-shelf test).
9. Findhittype's listing is mis-disassembled; use the decoded byte behaviour (x-flip clear → mask $1E, x-flip set → mask $F0).
10. noidea/setonetimeranim and sub_F6C44 return results in the Z flag only; their listing comments are misleading.
11. `st` on word variables (puckc, passplayer, onetimerplayer) writes only the high byte.
12. puckvzadj measures distance to the goal line nearer by |pucky|, not necessarily the target goal.

---

## 7. UNRESOLVED

- **puckvz when doshot skips the Z step (z == 0 after aim/error).** It keeps whatever the carried puck had. pucknorm does not write Zvel, and the updateplayers Z step leaves Zvel unchanged when Zpos = 0 and Zvel = 0. It is probably 0 for a puck on the ice, but this was not traced through every path (e.g. a pick-up of a still-bouncing puck).
- **Exact windup charge totals.** They depend on the per-loop d7 pattern and on updateanim's ordering. The ≈35 / ≈31 / ≈16 figures are derived for d7 = 1. The rule itself is exact: +d7 per ShotMode call while SPAnum < $10.
- **Semantics of `$63` bit 2 skipped as "unavailable" by dopass/chk4pass.** The preamble lists bit 2 as pf2dw; the listing comment says "unavailable". The behaviour is the same either way: skip the receiver.
- **`Setplass` (called by sub_FEFF0), `SetLCmode` (doinput A-hold) and the consumer of `word_FFC31C`** were not read; they are outside this scope.
- **One-timer contact geometry (puckstick: the meaning of d0 = dist² from the stick hot spot, its caller checkpuckcoll)** is summarized only. It belongs to the puck-collision spec.
