# Player-vs-player collisions and body checking (NHL '94 Genesis)

Source: `lst/nhl94.bin.lst`. Line numbers (Lnnnnn) are listing lines. All values are hex unless shown as decimal.
Struct offsets follow the SCstruct table in the spec preamble. `a3` is the object being updated, `a2` is the other object.
"facedir" always means the **high word** of the long at `$54` (0-7). The asm reads it with `.w` accesses at `$54`.

## Overview

```
updateplayers (per object, L35329)
  |- [falling-down pinning, L35375-35452 + sub_FEB54]      (see "updateplayers falling-down block")
  |- updateanim / move / assignment ...
  |- if pixel X or Y changed: checkcoll (L48484)
  |     |- wall checks: checkwallcoll2 body + stick tip            (already ported)
  |     |- checkplcoll (L48570): walk OOlist neighbours within 16 px of Y
  |     |     '- checkcx (L48617) per neighbour
  |     |          |- circle test, dist^2 <= 256
  |     |          |- relative normal speed V1n
  |     |          |- if opposing teams: impact += d4, impactp, newcheck (sfx $1C-$1F),
  |     |          |     checkint -> checkint_ci x2 -> FallDown / AddPenalty(Interference)
  |     |          |     checkcheck -> CCStart x2 -> holdcheck | Bcheck | body check
  |     |          |                    body check -> checkagr, PenShotChk, AddPenalty,
  |     |          |                                  wallcollduringcheck, FallDown
  |     |          |     checkfight (rts)
  |     |          '- momentum exchange (only first pair per checkcoll call), collflag = $FF
  |     '- collflag != 0 ? restore Xpos/Ypos high words from Old : re-sort OOlist, Ylist
  '- impact -= 2*d7 (clamped at 0); limpact = impact
```

How a check starts (input side, documented for context):
- Body check: `burst` (L36830) sets SPA `$C5E` and pfalock. Humans use button C (doinput, L36370-36395). CPU uses `check4check` (L40878). The check resolves when the bursting player touches an opponent (CCStart).
- Hold: human button A while not carrying the puck goes to `holdplayer` (L36863). CPU uses `check4check` and jumps to `Acheck` (L36872). These set SPA `$1122` or `$C90`. The hold resolves on contact (holdcheck).
- Sweep check: `Sweepcheck` (L37296) sets SPA `$B24` and pfalock. Humans use button B while already controlling the nearest player (L37284). CPU uses skatetopuck (L43183) when facing the puck and 30^2 < dist^2 <= 38^2. The sweep resolves on contact (Bcheck).
- Net bump: `CheckBump` (L50048) runs from checkgoalp when a player overlaps a net ellipse.

FallDown is also called by `puckbody` (L50800) when a fast airborne puck hits a player (a3 = the puck). That caller is out of scope, but FallDown has to handle a non-player a3.

## Globals, tables and fields used

RAM globals:
| name | use |
|---|---|
| `collflag` (word) | Cleared at the start of checkcoll. Set with `st` (byte $FF, so the word reads $FFxx and is negative) by a momentum exchange, holdcheck or Bcheck. Nonzero after checkplcoll means restore the old position. Negative inside checkcx means skip any further momentum exchange. |
| `evalue` (word) | Elasticity e*16 (0-16 per the comment). The only write in the ROM is `move.w #0,(evalue).w` at L48644, so it is always 0 (see "evalue"). |
| `ltack` (word) | Last tackle sound, 0-3 (newcheck). |
| `PlayerChked`, `PlayerChking` (long struct pointers) | Remember the last (faller, hitter) pair that got past FallDown's animation filter. The ROM never clears them; only FallDown writes them. |
| `FallXPos`, `FallYPos` (word) | Faller X/Y when a board animation (FallList) is chosen. FallXPos is read by the pinning code. FallYPos is written but never read. |
| `ChkCnt` (word) | Check counter. Incremented by 1, or by 3 when the hitter's `$74` byte is 0. Read by stats code (L55774, L56000). |
| `crowdlevel`, `CwdExciteLvl` (word) | Crowd noise and excitement accumulators. |
| `InjCntDown` (word) | Set to 4 on injury. |
| `DelayedPen` (byte) | bit1 = home team has a delayed penalty, bit2 = away team has one (set by AddPenalty). |
| `OptPen` (word) | 0 = penalties off. |
| `cont1team`, `cont2team` (word) | 0 none, 1 home, 2 away: which team each joypad controls. |
| `gmode` | bit0 gmclock (play stopped), bit4 gmhl (highlight replay). |
| `sflags` | bit3 shot-direction mode, bit6 scroll lock, bit7 horizontal mode. |
| `byte_FFC2FC` | bit5 = this injury lasts the game (set/cleared by setInjuryType). bit6 = crowd record broken (recomputed every frame in updateplayers). |
| `byte_FFC2FE` | bit1 is set every frame by `set_bit1_C2FE` (L975179; the clear path is dead code), so treat it as always 1. |
| `word_FFC2F8` | bit4: when set, wallcoll consumes it and does not set the player's wall bit (pflags3 bit4). |
| `word_FFBF12` | Temp word in CCStart that holds `Chk/2`. |
| `wcradiusx`, `wcradiusy` | Wall-check radii (shared with the wall code). |
| `xc1`, `yc1` | Scroll centre (set on injury). |
| `TempPlOffset` | Set on injury: `$8000` if the injured player is away, OR'd with the roster slot byte. |
| `HmShots` | Home team stats block. The away block is at `HmShots+$364`. Team checks word at `+$10`; per-player checks byte at `+$11C+pnum`; per-player status word at `+$66+pnum*2`. |
| `OOlist` (16 bytes), `OOlistpos` (16 words), `Ylist` (16 words) | Sprite Y-sort structures. OOlist holds object numbers*2 in ascending Ylist order. OOlistpos[obj] is that object's index in OOlist. Ylist[obj] is its sort Y. |
| `puckc`, `puckx`, `pucky` | Puck carrier SCnum (negative = none) and puck position. |
| `RNGseed` | Used through randomd0. |
| HV counter `$C00008` (`VDP_CNTR`) | Read directly as a cheap random source; it does not advance RNGseed (see "Random sources"). |

Struct fields beyond the preamble list:
- `$75` = Chk (checking rating, byte). check4check says its maximum is $1E (30).
- `$74` = the "H/F" byte. bit0 = handedness. `($74 & $FF) >> 2` is the fight rating (getFgtbyte). bit1 is tested by chkFgtBit1.
- `$5E` and `$5F` are the two `nopuck` bytes. Both count down by d7 each loop in updateplayers and are clamped at 0.
- pflags2 `$63` in '94: bit2 = player unavailable (setInjuryType sets it; passmode tests it). bit4 = has committed a penalty (AddPenalty sets it with `bset #4,$63(a3)`). bit5 = line change / no player collision (tested in checkplcoll and checkcx). bit0 = fighting. These differ from the '93 equates in ram94.asm, and the listing comments disagree with each other. Use the bit numbers given here.
- pflags3 `$64`: bit1 breakaway, bit3 one-timer in progress, bit4 wall collision, bit5 falling down.

ROM tables (dumped in full in their sections): `checkinglist` (L48956), `FallList` (L49396), penalty ids from `PenaltyList` (L56708, see "Penalty ids used here"), and vtoa `_dt` (already ported).

Helper semantics the port needs:
- `randomd0(n)`, L44190: returns `((((seed*$BB40E62D + 1) mod 2^32) >> 8) & $FFFF) * (n & $FFFF) >> 16`, which is 0..n-1. **n = 0 returns 0.** Preserves d1-d2.
- `vtoa(dx,dy)` returns 0-7, or 8 for (0,0). It clobbers d1: on return d1 = |dy| (bit 15 lost). It preserves d2.
- `SetSPA(a3, d1)` (L43319): if `SPA == d1` do nothing. Otherwise SPAnum = 0, SPA = d1, SPAcnt = $FFxx (st byte, which restarts the animation). Clobbers nothing.
- `sfx(id)` and `song(id)` (L44279, L44297): word id passed on the stack. They preserve all registers. Both go to `p_initfx`; sfx also stores `lastsfx`.
- `AddPenalty(d0=id, a3=offender)` (L45939): returns if gmclock is set. Id $C goes straight to AddPenalty2. Returns if OptPen = 0, or if `$63(a3)` bit2 is set. While `gmode` bit5 (offsides) is set it goes to AddPenalty2; otherwise id $10 returns. Then falls into AddPenalty2.
- `AddPenalty2` (L45954) is the forced version: if id >= $E it bumps the crowd, plays song $C (offender home) or song $B (offender away; also CwdExciteLvl += $14), queues the penalty in PenBuf, sets DelayedPen and offender pflags2 bit4. It preserves d1/a0/a1. It belongs to the penalty spec.
- `PenShotChk(d0=id, a2=fouled player)` (L46100): may replace d0 with a penalty-shot variant when a2 is on a breakaway. It preserves d1-d3/a0. It belongs to the penalty spec.

## Random sources

- `randomd0` (seeded RNG): newcheck, checkint_ci, CCStart, checkagr, Bcheck, FallDown injury roll, check4check.
- HV counter (`$C00008`):
  - `move.b (VDP_CNTR).l` reads the **V counter** byte. CCStart uses `& 2` to pick the penalty id variant.
  - `move.w (VDP_CNTR).l` reads the word, whose low byte is the H counter. FallDown stagger uses `& $F`, CheckBump uses `& $1F`, check4check uses `& 3`.

For the port, draw HV-counter values from a separate uniform RNG (bits uniform), not from RNGseed. Keep randomd0 calls in exactly the order given below, because they advance the shared seed.

---

## Routines

The collision pass: checkcoll and the collision response.

### checkcoll (L48484)
- Purpose: per-object collision pass after movement. Only caller: `updateplayers:_cc` (L35685), and only when the pixel X or pixel Y differs from the old value.
- Inputs: a3. d2 = Xpos high word, d3 = Ypos high word (set by updateplayers right before the call). sflags bit7.
- Outputs: collflag. Position may be restored. OOlist, OOlistpos and Ylist are updated.

Steps:
1. `collflag = 0`.
2. If sflags bit7 (horizontal mode): swap d2 and d3. From here on, d3 is the sort axis (Y in normal vertical mode). The port can assume vertical mode; the Y-sort and collision code still uses d2/d3 as captured here.
3. If pflags bit2 (pfnc, no collision): skip to step 6.
4. Wall checks (already ported): checkwallcoll2 around (Xpos, Ypos) with radii `$4A`/`$4C`. If no wall contact (wallcos|wallsin = 0) and SCnum <= $B, check again at the stick tip (Xpos+hotX, Ypos+hotY from GetHot) with radius 1.
   All registers d0-d7 are restored afterwards, so **d2/d3 keep their pre-wall-check values even if the wall code moved the object**.
5. `checkplcoll(d2, d3)`.
6. If `collflag != 0` (any nonzero word): `Xpos.hi = OldXpos.hi` and `Ypos.hi = OldYpos.hi` (word moves only; **the fractional low words are not restored**, and Z is not touched). Return. The sprite sort and the Ylist update are skipped.
7. Sprite sort (summary): bubble this object's entry in OOlist so OOlist stays in ascending Ylist order, using d3 as this object's key.
   - First move up while not at index $F and `d3 > Ylist[next]` (signed). Each step swaps the two OOlist bytes and does `OOlistpos[self]++`, `OOlistpos[next]--`.
   - Then move down while index > 0 and `d3 < Ylist[prev]`.
   - Finally `Ylist[self] = d3`.

### checkplcoll (L48570)
- Purpose: find objects whose sort-Y is within 16 px and run checkcx on each.
- Inputs: a3, d2/d3 from checkcoll. Uses OOlist, OOlistpos, Ylist.

Steps:
1. If `$63(a3)` bit5 (line-change / no-collide): return. If `SCnum(a3) > $B`: return. Only skaters and goalies run this.
2. `d1 = OOlistpos[self]`.
3. Upward pass: while `d1 != $F`:
   - `d4 = OOlist[d1+1]` (object number * 2) and `d5 = Ylist[d4] - d3`.
   - If `d5 > $10` (signed): stop the upward pass.
   - Otherwise call `checkcx(d4, d5)` and do `d1++`.
4. Downward pass: `d1 = OOlistpos[self]`. If `d1 == 0`, return. Loop:
   - `d4 = OOlist[d1-1]` and `d5 = d3 - Ylist[d4]`.
   - If `d5 > $10`, return.
   - Otherwise call `checkcx(d4, d5)`, do `d1--`, and repeat while `d1 != 0`.
- Notes:
  - Ylist holds each object's Y from its last sort, so it may be stale. The list is not re-sorted for self before this walk. A walk stops at the first neighbour beyond 16 px even when a farther neighbour is closer because of staleness.
  - Order matters: only the **first** pair that reaches the momentum exchange gets one per checkcoll call (collflag). Port the same OOlist and walk order, or the same pair order.

### checkcx (L48617, momentum part through L48756)
- Purpose: circle collision test with one other object, impact bookkeeping, check events, and velocity exchange.
- Inputs: a3 (self). d4 = other object number * 2, so `a2 = SortCords + d4*64`. d2 = self X (sort-perpendicular axis) and d5 = delta on the sort axis from checkplcoll. Reads `$62`, `$63`, `$52`, Xpos, Ypos, Xvel, Yvel, `$67` and `$32` of both objects, plus puckc and collflag.
- Outputs: Xvel/Yvel of both objects, impact `$32` and impactp `$2E` of both, collflag, plus the side effects of the sub-calls.
- Saves and restores d0-d7/a0-a3.

```
a2 = SortCords + objnum*128
if a2.pflags bit2 (pfnc)        -> return
if a2.pflags2 bit5              -> return
if a2.SCnum > $B (signed)       -> return
d0 = a2.Xpos.hi  (horizontal mode: a2.Ypos.hi)
d0 = d0 - d2                                  ; word
if d0 < -$10 or d0 > $10 (signed)             -> return
if (d5*d5 + d0*d0) > $100 (32-bit signed, muls) -> return   ; dist^2 <= 256 collides
evalue = 0
teamsDiffer = ((a3.pflags XOR a2.pflags) bit 6)
Vx = a3.Xvel - a2.Xvel   (word wrap)          ; relative velocity of a3
Vy = a3.Yvel - a2.Yvel
Dx = a2.Xpos.hi - a3.Xpos.hi  (word)          ; computed as -(a3.X - a2.X); uses CURRENT positions
Dy = a2.Ypos.hi - a3.Ypos.hi                  ; (no horizontal swap here)
P  = Vx*Dx + Vy*Dy        (32-bit; each product muls.w 16x16)
if P < 0 -> return (no exchange, no impact, collflag untouched)   ; P == 0 continues
V1n32 = P asr 4           (arithmetic shift of the 32-bit value)
if teamsDiffer:
    d4 = (V1n32 & $FFFF) >> 8          ; lsr.w on the low word, so 0..255
    if d4 <= 5: d4 = 5                 ; "cmp #5; bgt keep"
    a3.impact += d4 ; a2.impact += d4  ; word adds
    if a2.pflags2 bit0 (fight) == 0: a2.impactp = a3.SCnum
    if a3.pflags2 bit0 == 0:         a3.impactp = a2.SCnum
    if d4 >= $14 (signed) and (puckc == a3.SCnum or puckc == a2.SCnum): newcheck()
    checkint()          ; see quirk Q1: may clobber d1 (=V1n)
    checkcheck()        ; uses d4 = impact value; preserves d0-d4/a0-a3
    checkfight()        ; rts
V1n = low word of d1   ; == low16(V1n32) unless Q1
(Vx, Vy restored from the stack)
if collflag < 0 (word, signed) -> return      ; exchange already done this checkcoll, or holdcheck/Bcheck fired
<momentum exchange, see "Momentum exchange (exact)">
collflag = $FF.. (st)
```
Same-team pairs skip all impact and check logic, but still exchange momentum.

#### Momentum exchange (exact)
All products are `muls.w` (signed 16x16 → 32). `asr.l #4` is an arithmetic shift of 32 bits, i.e. floor(x/16). `.w` means keep the low 16 bits.
```
V1t  = low16( (Vx*Dy - Vy*Dx) asr 4 )           ; tangential, 16-bit
m1   = a3.weight($67, unsigned byte) + $8C      ; +140
m2   = a2.weight + $8C
d7   = low16(evalue * m2) lsr 4                 ; mulu.w, then lsr.w #4      (e=0 -> 0)
num  = m1 - d7                                  ; word
den  = m1 + m2
V1n' = divs( V1n * num , den )                  ; 32/16 signed divide, quotient truncated toward 0, low word
t    = low16(evalue * V1n)  asr 4               ; muls.w then asr.w #4 on the LOW WORD only (e=0 -> 0)
V2n' = low16(V1n' + t)
a3.Xvel = low16( (V1t*Dy + V1n'*Dx) asr 4 ) + a2.Xvel   ; a2.Xvel = value before this exchange
a3.Yvel = low16( (V1n'*Dy - V1t*Dx) asr 4 ) + a2.Yvel
a2.Xvel = a2.Xvel + low16( (V2n'*Dx) asr 4 )
a2.Yvel = a2.Yvel + low16( (V2n'*Dy) asr 4 )
```
Write order: a3.Xvel, a3.Yvel, a2.Xvel, a2.Yvel.

Interpretation, for understanding only; port the integer code:
- V1n = (V·D)/16 and V1t = (V×D)/16, where D is unnormalised (|D| ≤ 16).
- The reconstruction divides by 16 again (/256 in total) instead of by |D|². The relative velocity that comes out is therefore scaled by `k = |D|²/256 ≤ 1`. The deeper the overlap, the more speed is lost.
- With e = 0 this gives `V2n' = V1n' = V1n*m1/(m1+m2)`. Along the normal the collision is perfectly plastic: a3 keeps the fraction m1/(m1+m2) of its relative normal speed, and a2 gains the same normal velocity. The tangential relative velocity is kept, scaled by k.
- Momentum is conserved exactly only when |D|² = 256.
- If Dx = Dy = 0 (same pixel): P = 0, the code continues with V1n = 0, the opposing-team impact is 5, and a3 simply takes a2's velocity.

The general formula, for e ≠ 0, as commented in the asm: `V1n' = V1n(m1 - m2·e)/(m1+m2)` and `V2n' = V1n' + V1n·e`.

#### evalue
- Read at L48713 (`d7 = evalue`) and L48720 (`d1 = evalue`).
- Written only at L48644, `move.w #0,(evalue).w`, every time checkcx passes the distance test.
- No other routine writes it. ram94.asm comments it as "elasticity value (parameter of collisions)".
- For the port, e = 0 is a constant. Keep the general form only if wanted.

#### Interaction with the next checkcx
After an exchange the relative normal velocity of the pair is about 0. When the other player is updated and runs its own checkcoll in the same or the next loop, the pair is tested again with P ≈ 0 ≥ 0, so it passes. Each time, opposing players still get the minimum impact of 5 (or more) and run checkint/checkcheck again. This is how impact builds up during sustained contact.

#### Quirk Q1: checkint clobbers V1n
`checkint` saves only d0. When `checkint_ci` calls FallDown and FallDown gets past its one-timer tests (FallDown step 5), FallDown loads d1 with animation ids, and vtoa also changes d1. The momentum exchange then uses `V1n = low16(d1)` as FallDown left it:

| FallDown exit path | V1n used |
|---|---|
| early returns (steps 1-5) | the real V1n |
| stagger | `$11E6` |
| normal fall | the SPA id passed at `_2`: one of `$DD8`, `$D26`, `$136A`, `$1776`, `$17E8`, `$185A`, `$18CC`, `$193E`, `$1A00` |
| injury, period | `$1AF4` |
| injury, game | `sext(pnum byte)*2` |

d2/d3 (Dx/Dy), d4 and the stacked Vx/Vy are not affected. This only happens when one of the pair is a goalie (see checkint_ci). Port it as-is: have the FallDown port return its "d1 out" value and feed it into the exchange.

### newcheck (L48758)
- Purpose: play a check sound without repeating the last one. Called from checkcx and tail-jumped from FallDown.
- `r = randomd0(3) + 1` (1..3). `ltack = (ltack + r) & 3`. `sfx($1C + ltack)`, so sfx $1C..$1F, always different from the previous one.
- Preserves all registers (d0 is saved; randomd0 and sfx preserve the rest).

---

### checkint (L48778)
- Purpose: goalie contact and interference test, in both directions.
- Sequence: `checkint_ci(a2, a3)`, swap a2/a3, `checkint_ci`, swap back. Saves and restores d0 only (Q1).

### checkint_ci (L48790)
- Inputs: a2 = candidate goalie, a3 = the other player. Reads gmode, puckc, impacts, pflags, pflags2, cont1team, cont2team, the goalie's position and pfgoal, aggress `$73`.
- Outputs: may call FallDown, where **the non-goalie a3 falls and the goalie is the hitter**. May call AddPenalty($22 Interference) on a3.

```
if a2.position != 0         -> return              ; a2 must be a goalie
if gmode bit0 (gmclock)     -> return
if puckc != a3.SCnum:
    if a3.impact <= $19 (signed) -> return         ; needs impact > 25 unless carrying the puck
if a3.impact <= 2           -> return
FallDown(faller = a3, hitter = a2)                 ; via exg; the skater falls
if a2.impact (goalie) <= $1E -> return
if a3.pflags2 bit4 (already penalised) -> return
if a2.position != 0         -> return
team = (a3.pfteam ? 2 : 1)
if cont1team == team or cont2team == team:         ; a3's team has a human
    if a3.pflags bit3 (pfjoycon) == 0 -> return    ; only the controlled skater draws it
y = a2.Ypos.hi ; if a2.pfgoal (bit7) set: y = -y   ; distance toward the goalie's own goal
if y < $EF or y > $10A (signed)  -> return         ; 239..266
if a2.Xpos.hi > $14 or < -$14    -> return         ; |x| <= 20
r = randomd0( ($28 - a3.aggress) as byte, upper byte 0 )   ; byte subtract wraps
if r > 4 (unsigned)         -> return
if gmode bit4 (highlight)   -> return
AddPenalty($22 Interference) with a3 = offender (tail jump)
```

### checkcheck (L48854)
Saves d0-d4/a0-a3, runs `CCStart(a2, a3)`, swaps a2/a3, runs `CCStart`, then restores. d4 (the impact value from checkcx) is visible to both calls.

### CCStart (L48864), including PlayerControlled and CheckingCalc (L48907-48956)
- Inputs: a2, a3, d4 = impact value from checkcx. Reads SPA, facedir, attribute xflip, position, pflags bit3, weights, impact, `$75`, pflags3 bit4, gmode.
- Roles:
  - If a2 is holding (`$C90`/`$1122`): holdcheck(holder = a2, target = a3).
  - If a2 is sweep-checking (`$B24`): Bcheck(sweeper = a2, target = a3).
  - If a3 is bursting (`$C5E`): body check by checker a3 on target a2.

```
if a2.SPA == $C90 or a2.SPA == $1122 -> holdcheck   (tail)
if a2.SPA == $B24                     -> Bcheck      (tail)
if a3.SPA != $C5E                     -> return
if gmode bit0 (play stopped): a3.impact = $100 ; a2.impact = $100   ; after-whistle hit always floors
; --- checker animation ---
dir = vtoa(a2.X - a3.X, a2.Y - a3.Y)          ; direction checker -> target (8 if same pixel)
r   = (dir - a3.facedir) & 7
if a3.attribute bit3 (xflip): r = (8 - r) & 7  ; neg, +8, &7
a3.pflags bit5 (pfalock) = 1
SetSPA(a3, checkinglist[r])
; --- does the target fall? ---
if a2.position == 0 (goalie)  -> return        ; goalies are never floored by a body check
if d4 < $14 (signed)          -> return
d0 = $78 (120)
if a3.pflags bit3 (joystick): d0 = $F0 (240)   ; PlayerControlled
; CheckingCalc (byte arithmetic on the low byte, upper byte stays 0)
d0.b = d0.b - a3.weight ; d0.b = d0.b + a2.weight      ; wraps mod 256
d0 = d0.w lsr 1                                         ; 0..127
wallcollduringcheck(a3 = checker)      ; asm: exg; call with a2=checker; exg back
d0 = d0 - a2.impact (word)
if d0 <= 0                    -> DOWN
if a3.pflags3 bit4 (checker against the wall, just recomputed) -> DOWN
r = randomd0(d0)
half = (a3.Chk($75) & $FF) lsr 1
if (signed byte) r <= half    -> DOWN
; check failed: the target stays up, but a charging/slashing call is possible
p = checkagr(checker a3, target a2)
if p > 4 (unsigned)           -> return
if gmode bit4 (highlight)     -> return
id = $16 + (Vcounter & 2)     ; $16 Charging or $18 Slashing
id = PenShotChk(id)           ; a2 = fouled player
AddPenalty(id) (a3 offender)  ; tail
DOWN:
p = checkagr(a3, a2)
if p <= 3 and gmode bit4 == 0:
    id = $1A + (Vcounter & 2)   ; $1A Roughing or $1C Cross Check
    id = PenShotChk(id)
    AddPenalty(id)
FallDown(faller a2, hitter a3)  ; tail
```
- Probability: the target falls when `d0 <= 0`, when the checker touches the wall, or with chance `(half+1)/d0` otherwise (half < d0).
  - A heavier checker, a lighter target and a higher target impact all raise the chance.
  - **Human checkers use base 240, so their checks floor less often than CPU checks.**
- Quirk: the checker's wall test calls `wallcollduringcheck` on the **checker**. That runs the real `wallcoll` with radius +23 on the checker, which can reflect the checker's velocity and set wallcos/wallsin (see wallcollduringcheck).
- Quirk: in the failed-check branch, a penalty can be called even though nobody fell.

### checkinglist (L48956)
Indexed by r (relative direction of the target, 0 = straight ahead, clockwise):

| r | SPA | name in comments |
|---|---|---|
| 0 | `$B96` | SPAshoulderchkl |
| 1 | `$BC8` | SPAshoulderchkr |
| 2 | `$C2C` | SPAhipchkr |
| 3 | `$C2C` | SPAhipchkr |
| 4 | `$C2C` | SPAhipchkr |
| 5 | `$BFA` | SPAhipchkl |
| 6 | `$BFA` | SPAhipchkl |
| 7 | `$B96` | SPAshoulderchkl |

### checkagr (L48971)
- Purpose: penalty roll for an aggressive play. The caller compares the result with a threshold: penalty if `result <= threshold`.
- Thresholds: charging 4, roughing 3, holding 6, tripping 4.
- Inputs: a3 = offender, a2 = victim. Output: d0. Clobbers d1.

```
d0 = $0028 ; d0.b -= a3.aggress($73) ; d0.b = d0.b lsr 1 ; d0 = d0.w * 13   (mulu.w)
if a3.pflags bit3 (joystick): d0 = d0 << 1                  (asl.w)
dx = a3.X - puckx ; dy = a3.Y - pucky
if -$28 <= dx <= $28 and -$28 <= dy <= $28: d0 = d0 asr 1   ; near the puck: smaller range, more penalties
d0 = randomd0(d0)
if a2.pflags3 bit1 (victim on breakaway):
    y = |a2.Ypos.hi|            ; tst/bpl/neg: y = 0 counts as positive
    dist = $108 - y             ; distance to the nearest goal line (ignores which goal)
    n = 8 ; if dist <= $75: n = 7 ; if dist <= $3A: n = 4 ; if dist <= $2C: n = 3   (all signed >)
    d0 = randomd0(n)            ; replaces the earlier roll; the RNG still advanced twice
if a3 is home (pfteam 0): if DelayedPen bit2 (away already has a delayed penalty): d0 = $7F
else (away):              if DelayedPen bit1 (home already has one):            d0 = $7F
return d0
```
- With aggress = $28, the range is 0, so randomd0 returns 0 and the penalty always fires. Values above $28 wrap through the byte arithmetic.
- The `$7F` override means no new penalty for a team while the **opponent** has a delayed penalty pending.

### holdcheck (L49037)
- Inputs: a2 = holder (SPA `$C90` or `$1122`), a3 = target.

```
if a3.pflags bit5 (pfalock)   -> return
if a3.position == 0 (goalie)  -> return
if a3.pflags2 bit0 (fighting) -> return
dir = vtoa(a3.X - a2.X, a3.Y - a2.Y)
if ((dir - a2.facedir + 1) & 7) > 2 (unsigned) -> return    ; target within +-1 dir of holder facing
if puckc == a3.SCnum: sflags bit3 = 0                         ; cancels the target's shot-direction mode
avgX = (a3.Xvel + a2.Xvel) asr 1  (word add, may wrap) ; a3.Xvel = a2.Xvel = avgX
avgY = (a3.Yvel + a2.Yvel) asr 1                        ; a3.Yvel = a2.Yvel = avgY
a3.pfalock = 1 ; SetSPA(a3, $CF4)                       ; target: SPAFlail
a2.pfalock = 1 ; SetSPA(a2, a2.SPA == $C90 ? $CC2 : $1154)   ; holder: SPAHold2 / $1154
p = checkagr(offender = holder, victim = target)
if p <= 6 and gmode bit4 == 0:
    id = (holder.SPA == $CC2) ? $24 (Holding) : $1E (Hooking)
    id = PenShotChk(id) (a2 = target) ; AddPenalty(id) (a3 = holder)
collflag = $FF..                                        ; suppresses this pair's momentum exchange
```
- Note: the listing comments name $24 and $1E the other way round. The PenaltyList strings confirm `$1E = Hooking` and `$24 = Holding`.

### Bcheck (L49103)
- Inputs: a2 = sweep-checker (SPA `$B24`), a3 = target.

```
if a3.pfalock -> return ; if a3.position == 0 -> return ; if a3.pflags2 bit0 -> return
if OptPen == 0 and a2.pflags bit3 (human sweeper):        ; roll only with penalties OFF
    d0 = $0020 ; d0.b += a2.Chk($75) ; d0.b -= a3.legstr($68)   ; byte wrap
    if byte_FFC2FE bit1 or byte_FFC2FC bit6: d0.b -= 2       ; FFC2FE bit1 is always set, so always -2
    if randomd0(d0) < $18 (signed) -> return                 ; sweep failed
dir = vtoa(a3.X - a2.X, a3.Y - a2.Y)
if ((dir - a2.facedir + 1) & 7) > 2 -> return
FallDown(faller = a3 target, hitter = a2 sweeper)
p = checkagr(offender = sweeper, victim = target)
if p <= 4: id = PenShotChk($20 Tripping) ; AddPenalty(id)    ; NO highlight check here
collflag = $FF..
```
- With penalties on, or for a CPU sweeper, there is no success roll: the direction test alone decides.

### FallDown (L49156): faller a2, hitter a3

Inputs: a2, a3, HV counter, puckc, gmode, OptPen. The outputs are listed in each step. Steps 1-5 are the gate. CmpPlayerStk (L49189) is step 7. AddChktoPlayerStats (L49211) is step 8.

1. If `a2.SCnum > $B` (signed): return.
2. If a2.SPA is one of `$145C`, `$1AF4`, `$11E6`, `$D26`, `$DD8`, `$136A`: return (already down, staggering or injured). The board animations are **not** in this list.
3. If `a2 == PlayerChked` **and** `a3 == PlayerChking`: return.
4. Set `PlayerChked = a2` and `PlayerChking = a3`.
5. If `a2.pflags3` bit3 or `a3.pflags3` bit3 (one-timer in progress): return. The pair from step 4 stays recorded.
6. `d1 = $11E6`. If `a3.pflags3` bit4 (hitter wall bit): go to step 8.
7. **CmpPlayerStk (stagger instead of fall):**
   - If `a2.stickhand($71) < $18` (signed byte), go to step 8.
   - If `a2.$5F != 0`, go to step 8.
   - `t = (HVword & $F) + $10` (16..31). If `t <= a2.impact` (signed word), go to step 8.
   - Otherwise set `a2.$5F = $3C` and go to step 13 with `d1 = $11E6` (stagger).
8. **Stats (AddChktoPlayerStats):** skipped if `a3.position == 0`. A goalie hitter, and the puck as hitter if its `$34` is 0 (UNRESOLVED U2), skips stats and goes to step 9. Otherwise, with `S = HmShots`, plus `$364` if a3 is away:
   - `S+$10` word += 1 (team checks).
   - `S+$11C+a3.pnum` byte += 1 (player checks).
   - `ChkCnt += 1`, and a further `+= 2` if `a3.$74` byte == 0.
9. `_chkpos`:
   - `a2.$5E = $78`.
   - `d0 = vtoa(a3.X - a2.X, a3.Y - a2.Y)` (direction faller → hitter).
   - If `a2.position == 0` (faller is a goalie), go to step 11.
   - Run `wallcollduringcheck(a2)`. This is the real wall bounce with radius +23 on the **faller** (see wallcollduringcheck).
   - If `a2.pflags3` bit4 is clear, go to step 11.
   - Otherwise do the **board test**. The asm computes |a2.Xvel| and |a2.Yvel| into d1/d2 and never uses them (dead code, popped). Let `d3 = a2.X - a3.X` and `d4 = a2.Y - a3.Y`. Away = the faller is on the boards side of the hitter:
     - `a3.Y > $108` (hitter behind the top goal line): away if `d4 >= 0`.
     - else `a3.Y < -$108`: away if `d4 < 0`.
     - else `a3.X >= 0`: away if `d3 >= 3`.
     - else (`a3.X < 0`): away if `d3 <= -3`.
   - If not away, go to step 11.
   - If away (`_playerpos`): if `-$10C <= a2.Y <= $10C` and `-$68 <= a2.X <= $68` (faller in the middle region), go to step 11. Otherwise go to step 10 (board check).
10. **Board check (`_chkawayfrommiddle` + `_getchkanim`):**
    - If `a3.SCnum <= $B`: `CwdExciteLvl += $A`, `crowdlevel += $96`, `a3.$40` (temp1 high byte) = 0, `a3.glitch($65)` = 0, `SetSPA(a3, $1AC2)` (hitter's board-check animation; pfalock **not** set, no goalie test), `a3.Xvel = a3.Yvel = 0`.
    - Choose the side index k: `a2.Y > $10C` → 0. Else `a2.Y < -$10C` → 4. Else `a2.X < 0` → 6. Else → 2.
    - `d1 = FallList[k]`. `FallYPos = a2.Y`, `FallXPos = a2.X`.
    - If `d1 == $18CC` (left boards) and `-$59 <= a2.Y <= $59`: call `sub_FE510(7)` (starts background tile animation #7, presumably the bench; it sets word_FFD6B4 = 7 and resets its state words), then `d1 = a2.xflip ? $1A00 : $193E`.
    - Else if `d1 == $17E8` (right boards) and `-$38 <= a2.Y <= $38`: `d1 = a2.xflip ? $193E : $1A00`. sub_FE510 is not called.
    - Else if `a2.xflip`: swap `$17E8` ↔ `$18CC` (other ids unchanged).
    - Then `a2.Xvel = a2.Yvel = 0`, `a2.pflags3` bit5 (falling) = 1, `a2.pflags` bit0 (pfdoff) = 1, and go to step 12.
11. **Normal fall (`loc_14378`):** `d1 = $DD8`. If `((d0 - a2.facedir + 1) & 7) <= 2` (hitter within ±1 of the faller's facing, so hit from the front), go to step 13. Otherwise `d1 = $D26` and continue to step 12.
12. **Big-hit upgrade (`loc_14392`):** if `(a2.facedir & 3) == 0` (facing straight up or down) and `a3.Chk >= $14` (signed byte) and `a3.SCnum <= $B` and `a2.pflags3` bit5 is clear (so not after a board animation), then `d1 = $136A`.
13. **`_2`:** `a2.pfalock = 1` and `SetSPA(a2, d1)`. If neither a3 nor a2 is a goalie (position != 0 for both): `crowdlevel += $12C` and `CwdExciteLvl += $F`.
14. **`_21`:** if `puckc < 0` or `puckc != a2.SCnum`, tail-call newcheck (sfx $1C-$1F) and return. Otherwise the faller had the puck: `puckc = $FF..` (st byte, now no carrier).
15. Injury test. Each failure goes to step 16.
    - Highlight (`gmode` bit4) must be off.
    - `a2.SPA` must be `$DD8`.
    - `(a2.facedir & 3)` must be 0.
    - `a2.pflags2` bit4 must be clear.
    - `r = randomd0($A0)`; fail if `r > a2.impact` (signed). So P = (impact+1)/160.
    - `gmode` bit0 must be clear.
    - On pass: `SetSPA(a2, $145C)`, then `setInjuryType`.
    - If `byte_FFC2FC` bit5 is clear (period injury): `SetSPA(a2, $1AF4)`.
    - `InjCntDown = 4`.
    - If `a3.position == 0` or `OptPen == 0`: `AddPenalty2($14)` (stoppage with no text), tail, return.
    - Else `AddPenalty2($12 Roughing)`, then tail into `Stop4Pen` (U3).
16. **`_22`:** `song($B)` (crowd cheer) if a2 is away, `song($C)` (crowd boo) if a2 is home. Return. The faller had the puck, so there is no newcheck sound here.

d1 on exit (needed for Q1): see the table under Q1.

### FallList (L49396)
Word table: `$1776, $1776, $17E8, $17E8, $185A, $185A, $18CC, $18CC`. Only indices 0, 2, 4 and 6 are used.

| k | SPA | side |
|---|---|---|
| 0 | `$1776` | top end boards (faller Y > $10C) |
| 2 | `$17E8` | right boards |
| 4 | `$185A` | bottom end boards |
| 6 | `$18CC` | left boards |

`$193E` and `$1A00` are the side-board "over the boards" variants near centre ice.

### setInjuryType (L49497)
- Inputs: a2 = injured player, a3 = checker. Preserves d0. Clobbers d1 and a0.

```
a2.pflags2 bit2 = 1 (unavailable)
crowdlevel += $12C ; CwdExciteLvl += $1E
sfx($D)
xc1 = a2.X ; yc1 = a2.Y ; sflags bit6 = 1 (scroll lock)
a0 = HmShots (+$364 if a2 away) ; d1 = (a2 away ? $8000 : 0) | a2.pnum byte
TempPlOffset = d1 ; d1 = sext(pnum byte) * 2
f = (a3.$74 & $FF) >> 2          ; getFgtbyte on the CHECKER
if f == 0:   byte_FFC2FC bit5 = 0 ; status[a0+$66+d1] = $FFFD           ; period injury
elif f == 3: game
else:        byte_FFC2FC bit5 = 0 ; status = $FFFD
             if a2.$74 bit1 (chkFgtBit1 on the INJURED player) set: game
game:        byte_FFC2FC bit5 = 1 ; status = $FFFC                       ; game injury
```
- Quirk: the fight byte comes from the checker, but bit1 comes from the injured player. Port as-is.
- If f > 3, it takes the "else" branch.

### checkfight (L49544)
Just `rts`, so it does nothing.

### CheckBump (L50048)
- Purpose: a player knocks the net off its moorings. Caller: checkgoalp (L50000) after the player (a3, SCnum <= $B, Z <= $A, pflags2 bit5 clear) passes the net ellipse test (|dx| ≤ 32, dy semi-axis ≈ 11). a2 = net struct.

```
if (HVword & $1F) != 0                         -> return     ; 1-in-32 chance per contact frame
if pucky - a2.Y > $28 or < -$28 (signed)       -> return     ; puck within 40 px of the net in Y
if -$2000 <= a3.Xvel <= $2000 and -$2000 <= a3.Yvel <= $2000 -> return
; dislodge:
pop the saved d0-d1 AND CheckBump's return address (adda #$C,sp): control returns to
  checkgoal's caller, skipping checkgoalp's net-bounce response
a2.Xvel = a3.Xvel asr 2 ; a2.Yvel = a3.Yvel asr 2           ; net gets 1/4 of the player's velocity
a3.Xvel = 0 ; a3.Yvel = 0
sflags bit6 = 1 (scroll lock)
if gmode bit0 -> return
AddPenalty2(8)            ; id 8 = "Face Off" stoppage (tail)
```

### wallcollduringcheck (L963039)
- Inputs: a2 = the player to test. Saves and restores d0-d7/a0-a6.
- If `a2.position == 0` (goalie): return. **pflags3 bit4 is not touched.**
- Otherwise: `wcradiusx = a2.$4A + $17`, `wcradiusy = a2.$4C + $17`, d2 = a2.X, d3 = a2.Y, then call `checkwallcoll` (L959783) with a3 = a2.
- `checkwallcoll` matches `checkwallcoll2` (already ported) except that it does **not** call `checkgoal`, so there are no net collisions:
  - Clear pflags3 bit4.
  - Corner circle test against radius 64 with `.radius^2 = $1000`, using `sideline $88 - wcradiusx` and `ywall $12A - wcradiusy`.
  - Then, only if wallcos|wallsin == 0, the straight walls.
  - Each hit calls `wallcollb2` → `wallcoll` (ported). That sets wallcos/wallsin and reflects the velocity. For a player with normal speed d2 <= 1000, it also sets pflags3 bit4 unless `word_FFC2F8` bit4 was set (that bit is consumed), and plays sfx $20 when `d2 <= -$1000` and impact >= $A.
- Quirks for the port:
  - The bounce really changes the tested player's velocity during a check.
  - If that player already has nonzero wallcos/wallsin from its own update this loop, the straight-wall test is skipped. Bit4 was just cleared, so only a corner hit can set it again.

### Findhittype (L37396)
IDA mis-decoded this routine. The code below is decoded from ROM bytes $C198-$C1B9.
```
4440            neg.w  d0
D06B 0054       add.w  $54(a3),d0      ; d0 = facedir - launchdir
0240 0007       andi.w #7,d0
082B 0003 0004  btst   #3,4(a3)        ; xflip
6700 0008       beq.w  $C1B2
013C 00F0       btst   d0,#$F0          ; flipped
4E75            rts
013C 001E $C1B2: btst  d0,#$1E          ; not flipped
4E75            rts
```
- Input: d0 = launch direction (vtoa result, 0-8). Output: d0 = `(facedir - dir) & 7`, plus the Z flag.
- Z = 1 (forehand) when the tested bit is 0.
  - Not flipped: **backhand** when d0 ∈ {1,2,3,4}, forehand when d0 ∈ {0,5,6,7}.
  - Flipped: backhand when d0 ∈ {4,5,6,7}, forehand when d0 ∈ {0,1,2,3}.
- Callers:
  - SetShotMode (L37434): forehand `$7FC` SPAshotf, backhand `$92E` SPAshotb; passspeed = $F either way.
  - passmode (L37052): forehand `$718` SPApassf, backhand `$78A` SPApassb, goalie `$366` SPAgswing without calling Findhittype.

### holdplayer / Acheck (L36863 / L36872), with check4check context (L40878)

holdplayer (human A button, doinput+$1A0, when not carrying the puck, not in a one-timer, and a skater):
```
a3.pfalock = 1
if a3.impact == 0: SetSPA(a3, $1122) ; return
a0 = SortCords + a3.impactp*128              ; last impact partner
fall into Acheck
```
Acheck (also the CPU entry, with a0 = the opponent found by check4check):
```
a3.pfalock = 1 ; d1 = $1122
if a3.impact != 0:
    d = a3.Y - a0.Y ; if a3.pfgoal (bit7): d = -d
    if d >= 0: d1 = $C90                      ; "hold, stick in air"
SetSPA(a3, d1)
```
check4check (CPU; a3 = would-be checker):
```
if a3.position == 0 -> return
n = $28 - Chk (byte) ; if OptPen != 0: n <<= 1 (word)
if randomd0(n) > 6 (unsigned) -> return
for each of the 6 opponents a0 (home checker scans SortCords+$300, away scans SortCords):
    skip goalie, pfalock, fighting
    dx = a0.X - a3.X ; dy = a0.Y - a3.Y ; skip unless -$1E <= dx <= $1E and -$1E <= dy <= $1E
    skip unless vtoa(dx,dy) == a3.facedir (word compare)
    if word_FFC2F8 bit5 (puck carrier in the slot) -> Acheck
    if (HVword & 3) != 0 -> burst (SPA $C5E)     ; 3/4 body check
    else -> Acheck                               ; 1/4 hold
```
- From assnearest (L40855) the call runs with Chk temporarily doubled (capped at $1E) when the carrier is in the slot.
- burst (L36830): uses energy to add a speed impulse along facedir, then sets pfalock and SPA `$C5E`. Out of scope here.

### updateplayers falling-down block (L35375-35452) and sub_FEB54 (L974766)
Runs per object at `_top`, right after saving OldX/OldY/OldZ:
```
if pflags3 bit5 (falling):
    Xvel = 0 ; Yvel = 0                      ; every loop while falling
    if SPAnum ($5A) == 0:  sub_FEB54()       ; first animation frame: ease halfway to the boards
    else:                  snap()            ; later frames: pin to the boards
```
SPAnum stays 0 for the whole first frame of an animation (SetSPA clears it; updateanim advances it by 4 only when that frame's time runs out).

Targets (`xf` = attribute bit3):

| SPA | axis | target |
|---|---|---|
| `$193E` | X | xf ? `$88` : `$FF78` (-136) |
| `$1A00` | X | xf ? `$FF78` : `$88` |
| `$18CC` | X | xf ? `$82` : `$FF7E` (-130) |
| `$17E8` | X | xf ? `$FF7E` : `$82` |
| `$1776` | Y | `$116` (278) if FallXPos > $56 or FallXPos <= -$56, else `$124` (292) |
| `$185A` | Y | `$FEEA` (-278) if FallXPos > $56 or FallXPos <= -$56, else `$FEDC` (-292) |
| other | n/a | nothing |

FallXPos rule exactly: `if FallXPos > $56 -> corner value; elif FallXPos > -$56 ($FFAA) -> centre value; else corner value`.

- snap(): set that position **high word** to the target. Fractions are untouched.
- sub_FEB54() (ease), with `delta = target - pos.hi` (word):
  - X animations: always `pos.hi += delta asr 1`.
  - `$1776`: if `delta < 0`, no change; else `Y.hi += delta asr 1`.
  - `$185A`: if `delta >= 0`, no change; else `Y.hi += delta asr 1` (arithmetic, rounds toward -inf).

The falling bit (and pfalock) is cleared by updateanim when the animation ends (L35745).

Impact decay (end of the per-object body, L35686-35694; it applies to every on-ice object whether or not checkcoll ran):
```
impact -= 2*d7 ; if result < 0: impact = 0 (bpl keeps 0) ; limpact = impact
```
Objects with position < 0 skip the decay but still copy `limpact = impact`.

---

## Animation ids (SPA) used by collisions and checking
| SPA | meaning | set by |
|---|---|---|
| `$C5E` | SPAburst, body-check charge (trigger) | burst |
| `$B96` / `$BC8` | shoulder check left / right | CCStart via checkinglist |
| `$C2C` / `$BFA` | hip check right / left | CCStart via checkinglist |
| `$1122` | hold (normal) | holdplayer, Acheck |
| `$C90` | hold, stick in air | Acheck |
| `$CC2` | SPAHold2, holder after `$C90` contact | holdcheck |
| `$1154` | holder after `$1122` contact | holdcheck |
| `$CF4` | SPAFlail, held target | holdcheck |
| `$B24` | sweep check | Sweepcheck |
| `$11E6` | stagger ("toddle"); also the injured-skater glide at L43683 | FallDown step 7 |
| `$DD8` | fall, hit from the front (±1 dir) | FallDown |
| `$D26` | fall, hit from side or behind | FallDown |
| `$136A` | big-hit fall (faller facing straight up/down, checker Chk >= $14) | FallDown |
| `$1776` | pinned to top end boards | FallDown/FallList |
| `$17E8` | pinned to right boards (xflip variant pins to left) | FallDown/FallList |
| `$185A` | pinned to bottom end boards | FallDown/FallList |
| `$18CC` | pinned to left boards | FallDown/FallList |
| `$193E` / `$1A00` | side boards near centre ice, "over the boards" variants | FallDown |
| `$1AC2` | hitter's board-check animation | FallDown step 10 |
| `$145C` | injured lying (stays for a game injury) | FallDown step 15 |
| `$1AF4` | injured lying (period injury) | FallDown step 15 |

FallDown also refuses to act when the faller already has `$145C`, `$1AF4`, `$11E6`, `$D26`, `$DD8` or `$136A`.

Related, outside collisions:
- Shots and passes: `$7FC`, `$92E`, `$718`, `$78A`, `$366` (see Findhittype).
- puckbody: `$10D0`.

## Sound ids
| id | call | where |
|---|---|---|
| `$1C`-`$1F` | sfx | newcheck: rotating check / tackle sounds |
| `$D` | sfx | setInjuryType: injury |
| `$20` | sfx | wallcoll, player hits the wall hard (can fire inside wallcollduringcheck) |
| `$B` | song | crowd cheer: FallDown when the away carrier is floored; AddPenalty2 when an away player is penalised |
| `$C` | song | crowd boo: FallDown when the home carrier is floored; AddPenalty2 when a home player is penalised |

## Penalty ids used here
Ids are PenaltyList byte offsets; the names were checked against the ROM text.

| id | penalty | where |
|---|---|---|
| `$08` | Face Off (stoppage) | CheckBump |
| `$12` | Roughing | injury with penalties on, forced via AddPenalty2 + Stop4Pen |
| `$14` | no text (stoppage) | injury by a goalie or with penalties off |
| `$16` | Charging | CCStart, check failed |
| `$18` | Slashing | CCStart, check failed (alternate) |
| `$1A` | Roughing | CCStart, target floored |
| `$1C` | Cross Check | CCStart, target floored (alternate) |
| `$1E` | Hooking | holdcheck, holder from `$1122` |
| `$20` | Tripping | Bcheck |
| `$22` | Interference | checkint_ci |
| `$24` | Holding | holdcheck, holder from `$C90` |

PenShotChk can turn the `$16`-`$24` calls into the penalty-shot variants (`$2E`+) when the victim is on a breakaway.

## Quirks summary (port as-is)
1. Q1: the momentum exchange uses FallDown's leftover d1 when checkint floored someone.
2. Only one momentum exchange per checkcoll call, in OOlist walk order. Impact and check events still run for later pairs.
3. Reconstructed velocities are scaled by |D|²/256, so deep overlap damps speed.
4. Position restore copies only the pixel words; fractions and Z keep their new values.
5. evalue is always 0.
6. Human body-checkers use base 240 versus 120 for CPU, so their checks floor less often.
7. wallcollduringcheck bounces the checker (CCStart) and the faller (FallDown) off walls with radius +23. The goalie is excluded.
8. Bcheck rolls for success only when penalties are **off** and the sweeper is human. Its tripping call skips the highlight test.
9. FallDown records PlayerChked/PlayerChking before the one-timer test. The same pair cannot fall twice in a row until another pair goes through FallDown.
10. `_chkawayfrommiddle` gives the hitter `$1AC2` even if the hitter is a goalie (checkint path), and does not set pfalock.
11. setInjuryType mixes the checker's fight byte with the injured player's bit1.
12. The checkagr breakaway distance uses |Y| for either goal.
13. The CCStart, checkagr and Bcheck formulas use byte arithmetic that can wrap for ratings above about $28.

## UNRESOLVED
- U1: The real ranges of weight `$67`, aggress `$73`, Chk `$75` and the `$74` byte were not confirmed, so it is unclear whether the byte wraps in CCStart, checkagr and Bcheck can happen in practice. GODOT_TODO lists rating ranges as open. I looked at AttribWgtList (L966313) but did not decode the roster.
- U2: When the puck is the hitter (puckbody → FallDown), FallDown's goalie tests read the puck struct's `$34`. I found no write to it (SetRCords only initialises SCnum 0-11). It is probably 0, which would make the puck count as a "goalie" (no stats, no crowd, AddPenalty2($14) on injury). Not verified.
- U3: The injury path with penalties on tail-jumps to `Stop4Pen` with a0 = the injured team's stats base (left there by setInjuryType), not a PenBuf pointer. Stop4Pen then reads the penalty type from `-2(a0)` and `-1(a0)`, which is unrelated RAM. The effect on the face-off spot belongs to the penalty spec.
- U4: The meaning of `sub_FE510(7)` (background animation #7 through `unk_FE364`) is inferred as the bench or boards animation. Only its state writes were traced.
