# Puck behavior spec (NHL '94 Genesis)

Source: `lst/nhl94.bin.lst`. Line numbers are listing lines. All coordinates are rink pixels (high word of the 16.16 position longs): origin center ice, +X right, +Y up the ice (top goal). "rvu" = raw Xvel/Yvel/Zvel word units. "loop" = one DoGameFrame pass; `d7` = vblanks since the last loop.

Byte-sized operations on word fields matter on the 68000 (big-endian): `$5E(a)` is the HIGH byte of the `nopuck` word, `$5F(a)` the low byte; `tst.b $2C(a)` tests the HIGH byte of Zvel; `st (word).w` writes $FF to the HIGH byte only (the word becomes `$FFxx`, which is negative). The port can treat `st` on `puckc`, `collflag`, `passplayer`, assist slots and `puckcross+2/+6` as "set to -1" because every reader only tests the sign or compares against 0..25.

## 1. Overview: how the puck routines fit together

Objects (SCnum, struct address `SortCords + SCnum*$80`, SortCords = `$FFB04A`):
- 0-5 home skaters/goalie, 6-11 away. 12 = top net (`$FFB64A`, starts at (0, +$10C)), 13 = bottom net (`$FFB6CA`, (0, -$10C)), 14 = puck (`$FFB74A`), 15 = puck shadow (`$FFB7CA`).
- Initial puck object (defaultsprites2 L53407 table, L53588-53597): pos (0,0,0), frame $18B, attribute 0, radius (5,5), asslist[0] = $18 (pucknorm), pflags = 1 (pfdoff, so on-ice drag uses shift 9). Shadow: frame $18A, radius (3,3), asslist $19 (puckshadow), pflags 4 (pfnc).
- Puck-related entries of `asstab` (L56671): $18 pucknorm, $19 puckshadow, $1A puckunflip, $1B puckfaceoff, $1C puckfaceoff2, $1E puckshootout, $1F puckpenshot. Assignment 7 = assscore (goal celebration, given by setass).

Per loop (updateplayers L35329, objects processed 0..15 in SCnum order):
1. Before the object loop: puck Z stall counter (section 3.1).
2. For the puck (object 14), in updateplayers order: save old pos (X,Y,Z longs) -> `updateanim` -> decrement nopuck bytes -> drag (only when Zpos hi word == 0) -> X/Y move -> Z gravity / ice bounce / bounce sound (3.2) -> assignment call (`pucknorm` in normal play) -> clear Wallcos/Wallsin -> `checkcoll` only if the pixel X or Y changed -> impact decay.
3. `pucknorm` (normal play): penalty-shot/shootout end check, puck-crossing prediction every 5 vblanks (`findpc`), carrier bungee (puck pulled 1/4 of the way to the carrier's stick hot spot, carrier velocity copied), stats/icing/offside hooks (`a2touchpuck`, `puckIChk`, `ChkOffsides`), stalled-puck whistle, `puckunflip` when resting, then `checkpuckcoll` (puck vs sticks, skater bodies, goalies).
4. `checkcoll` (L48484, ported) calls `checkwallcoll2` (ported) with the puck's radius. When the puck is in an end zone between the corners (|X| <= 136-5-64 = 67 and |Y| >= 298-5-64 = 229), `checkwallcoll2` calls `checkgoal` with a2 = the net at that end. `checkgoal` handles net box collisions, posts/crossbar, the top of the net and goal detection. Board hits go through `wallcollb2` (puck over the glass) then `wallcoll` (ported). If `checkgoal` set `collflag`, `checkcoll` restores X/Y pixel words to OldX/OldY (fractions kept).
5. Object 15 runs `puckshadow` after the puck.

Carrier lifecycle (`puckc`, word at puck struct $60; negative = loose):
- Only `_glue` (inside `puckstick`, L50665) sets `puckc` to a player (a listing-wide grep for writes to `(puckc).w` finds no other; the struct clear in defaultsprites2 leaves it 0 until a faceoff routine sets it -1). It is reached from a stick touch on a loose puck slow enough to control, or from `puckgoalie` when the goalie covers the puck.
- Released (`st puckc`) by: dopass L36928 (passer nopuck=$10), doshot L37571 (shooter nopuck=$10), FallDown L49444 (checked carrier), `checkgoal` _nod L49665 (carrier skates puck into a net box, carrier nopuck=8), `puckgoalie` L50885 (carrier's puck touches goalie body, carrier nopuck=$14), `deflect` L51171 (steals and failed receptions), faceoff/PS resets (L41309, L42087, L46084).
- While carried, `pucknorm` drags the puck to the carrier's stick hot spot every loop and calls `a2touchpuck` for the carrier every loop.

Pickup rules summary (details in checkpuckcoll / puckstick / puckgoalie):
- A player can touch the puck only if his `nopuck` high byte ($5E) is 0, he is not in pfnc mode, and (in PS/SO) he is the shooter or the goalie.
- Stick contact needs puck Z <= 5, Zvel <= $200 and stick-tip distance^2 <= $C4 (14 px), or <= $31 (7 px) while the puck's own nopuck byte is positive (set by passto while a pass is in flight).
- Loose puck on a stick: glued if speed^2 <= (Stk*350 + 13000)^2 (or 13000^2 when a shot is in flight); otherwise the puck is deflected randomly and the player gets nopuck=8. Goalie sticks need distance^2 <= $40. One-timer players call `onetimershot` instead.
- Carried puck vs an opponent stick: distance^2 <= $24 (<= $40 when the carrier is in the slot), then randomd0(c - k + 36) <= 2 (<= 4 in slot), where c, k are energy-scaled Stk/2 of carrier and challenger. Goalies always win that roll; nobody can steal from a goalie. A steal knocks the puck loose (`deflect`) and sets both players' nopuck to Stk/2(energy) + $14.
- Body (skater): distance^2 <= $40 within 8 px; low pucks (Z <= 8) only when distance^2 is a multiple of 16. Ricochet velocity = (puck - player offset) in the high byte.
- Goalie body: radius from agility table `_cbg`; covers the puck if |vx| and |vy| <= a random threshold from the goalie's $6C rating, else ricochet.

Goal detection summary (`checkgoal` _goal): the puck must be inside the net box (|dx| <= 21, |dy| <= 7 relative to the net, Z <= 13), have come from Z < 13 the previous loop, enter through the net's mouth face (moving up into the top net or down into the bottom net), cross that face at |dx| <= 20, have Z != 13, and play must be running (`gmode` bit0 clear), or a penalty shot / shootout attempt must be live and the puck must be in the correct net. Then stats, sounds, score summary, celebration assignments, the puck is placed in the back of the net (±6, ±$110) with Zvel $600, its assignment becomes puckunflip, the shadow becomes the goal siren ($102E) and event $E is queued via AddPenalty2.

## 2. Globals and tables used

| Name | Address / where | Meaning in this code |
|---|---|---|
| `puckc` | puck struct $60 (word) | carrier SCnum or negative |
| `puckx/pucky/puckz`, `puckvx/vy/vz` | puck struct $00/$14/$18, $28/$2A/$2C | aliases |
| `puckx_nopuck` | puck struct $5E (byte) | puck's own nopuck byte; set by passto L37192 (`time*8 - 16`) |
| `puckcross` | 4 words | [0] X at top goal line crossing, [1] loops until it, [2] X at bottom goal line, [3] loops until it (-1 = none). Read by goalie AI. `puckcross2`/`puckcross6` = the two time words |
| `PuckZCntr`, `TmpPuckZ` | words | puck Z stall counter |
| `collflag` | word | set by checkgoal: checkcoll restores old X/Y |
| `ltx`, `lty`, `ltplayer` | words | last touch position / SCnum (a2touchpuck) |
| `lastplayer` | word | SCnum of last carrier who lost the puck (steal, goalie strip, pass, shot) |
| `passplayer` | word | intended pass receiver; credited in _glue |
| `iflags` (byte at iflags) | bits 0 ifcgl crossed goal line, 1 ifdir must cross top line, 2 ifok icing armed | icing |
| `icingPlayer` | byte iflags+1 | SCnum of last toucher (icing candidate) |
| `gmode` | bit0 clock/play stopped, bit1 gmdir (0 = home attacks top), bit4 highlight/replay, bit5 offsides enabled | |
| `sflags` | bit2 pass-dir mode, bit3 shot-dir mode, bit6 scroll lock (`freezewindow`), bit7 horizontal mode | |
| `sflags2` | bit4 shot taken, bit5 power play, bit6 PP team (0 = home on PP) | |
| `sflags3` | bit4 faceoff-win pending (credited in _glue) | |
| `BA_PS_flags` | bit2 PS/shootout live, bit4 attempt over, bit5 shot/pass released, bit6 end event sent | penalty shot / shootout |
| `BA_Sktr_SCnum`, `BA_Goalie_SCnum` | words | PS/SO shooter and goalie |
| `word_FFC2FA` | bit0 shootout (vs penalty shot), bit4 breakaway pending, bit5 puck released in PS | |
| `word_FFC2F4` | bit0 goal scored, bit2 "puck hit" sound flag (only set in dead code), bit5 PS goal | |
| `word_FFC2F8` | bit1 one-timer shot just taken (set by onetimershot, cleared by updateplayers while someone carries), bit4 "net collision" (suppresses wall bit in wallcoll), bit5 carrier in slot (setSlotBit L963062: carrier relative Y >= $58 and abs X <= $47) | |
| `byte_FFC2FE` | bit0 PS goal, bit1 always set each loop (set_bit1_C2FE), bit3 goal shot toggle, bit7 one-timer touch | |
| `byte_FFC2FC` | bit4 ignore energy (makepde), bit6 crowd meter at record | |
| `word_FFC31C` | word | PS/SO loose-puck countdown, $64 after shot/pass |
| `word_FFD454` | word | PS/SO clock |
| `word_FFD594`, `word_FFD574`, `word_FFD576` | words | shootout side selector and per-side SO goal counters |
| `crowdlevel`, `CwdExciteLvl` | words | crowd noise / excitement |
| `ChkBodyG`, `NegChkBodyG`, `ChkBodySqG` | word, word, long | goalie body box half-size, its negative, radius^2 |
| `OOlist` (bytes, SCnum*2 sorted by Y ascending), `OOlistpos` (word per object), `Ylist` (word per object, rink Y at last sort) | | neighbor search |
| `wcradiusx/y` | words | wall-collision radius of the object being checked |
| `HmShots` = `$FFC6CE` (home), `$FFCA32` = HmShots+$364 (away) | team stats struct | see below |
| `ScoreSum`, `ScoreSumbytes` | buffer, word | scoring summary, 6 bytes per goal, max $168 bytes |
| `c1playernum`..`c4playernum`, `cont1team`..`cont4team` | words | human control |
| `VDP_CNTR` ($C00008) | HV counter | used as a cheap random source (CheckBump, puckgoalie dead code) |
| `RNGseed` | long | randomd0 |

Team stats struct fields touched here (offsets from HmShots / away): $00 shots, $02 PP goals (sub_1284A), $0C goals, $0E faceoffs won, $14 passes completed, $18 current toucher pnum (word), $1A assist-1 pnum (word, negative = none), $1C assist-2 pnum, $22 word pointer to the team's first SCstruct, $24 players on ice, $26 goalie pnum on ice (negative = none), $30 flags (bit3 possession lost -> restart assist chain, bit4 team offside), $32+2*pnum energy, $B4+pnum player goals (byte; goalie row = goals against), $CE+pnum player assists (byte), $E8+pnum player shots (byte), $342+2*period goals per period, $34A+2*period shots per period, $354 PP shots, $356 (incremented for a goal by the team NOT on the power play, i.e. short-handed goal), $35A breakaway goals, $35C one-timer attempts, $35E one-timer goals, $362 (listing comment "SH Goals", but it is incremented when `word_FFC2F4` bit5 (PS goal) is set and it is not a shootout: most likely penalty-shot goals).

AddPenalty2 event ids used (byte offset into `PenaltyList` L56708): 6 -> entry $94 "Face Off" (stalled puck, puck out of play), 8 -> entry $94 "Face Off" (net knocked off), $A -> entry $C2 (no text; PS/SO attempt over), $E -> entry $62 (no text; goal). AddPenalty2 (L45954) ignores everything in horizontal mode (sflags bit7); ids >= $E also add $C8 to crowdlevel and play song $C (or $B and CwdExciteLvl += $14 when `$62(a3)` bit6 is set).

Helpers (already-known semantics, listed for exactness):
- `randomd0` L44190: seed = seed * $BB40E62D + 1 (mod 2^32); returns `(((seed >> 8) & $FFFF) * range_u16) >> 16`, i.e. 0..range-1. `randomd0s` L44178: `randomd0(2*d0) - d0`, i.e. -d0..d0-1.
- `makepde` L51186: d0 = rating (byte, sign-extended) * energy(a0's player, word at stats $32+2*pnum; forced to $1000 if `byte_FFC2FC` bit4) `<< 4 >> 16` = rating*energy/4096 (truncated toward -inf), sign-extended to long. Uses a0 as the player.
- `sfx(id)` / `song(id)`: both call `p_initfx(id)`; sfx also stores `lastsfx`. Negative id = none.
- `SetSPA(a3, d1)` L43319: if SPA == d1 return; else SPAnum = 0, SPA = d1, SPAcnt high byte = $FF.
- `assreplace(d0)` L43210: asslist[assnum] = d0, set pfna. `assinsert(d0)` L43202: assnum = (assnum - 1) & 7 then assreplace.

## 3. updateplayers puck parts

### 3.1 Puck Z stall counter (L35335-35352)
- Purpose: a puck stuck in the air (e.g. resting on top of a net) sinks 1 px every 17 loops.
- Runs once per loop before the object loop, skipped entirely in horizontal mode (`sflags` bit7). Not scaled by d7.
- Inputs/outputs: `puckz` (Zpos high word), `TmpPuckZ`, `PuckZCntr`.

```
if puckz <= 5 (signed):            PuckZCntr = 0
elif TmpPuckZ != puckz:            TmpPuckZ = puckz; PuckZCntr = 0
else:
    PuckZCntr += 1
    if PuckZCntr >= $10:           PuckZCntr = 0; puckz -= 1
```
- Quirk: TmpPuckZ is not refreshed while puckz <= 5. After a decrement the next loop sees a mismatch and resets, so the period is 17 loops after the first 16.

### 3.2 Drag, motion, Z gravity, bounce sound (L35490-35560), as applied to the puck
Already ported for skaters; puck specifics:
```
k = 17 * d7            (22 * d7 if word_FFD06E != 0)
if Zpos.hi == 0:                       # drag only on the ice (negative Zpos also skips drag)
    sh = 9 if pflags.bit0 (pfdoff) else 6     # the puck has pfdoff set -> 9
    for v in (Xvel, Yvel): if v != 0: dv = v >> sh (asr); if dv == 0: dv = 1; v -= dv
Xpos.l += Xvel * k ; Ypos.l += Yvel * k        (muls, skipped when vel == 0)
# Z (L35531-35545):
if Zpos.hi < 0: done                   # e.g. puckz = $FFFF "no visible puck" at faceoffs: no gravity
if Zpos.hi == 0 and Zvel == 0: done
Zvel -= 2k ; Zvel -= 4k                # total -6k = -102*d7
Zpos.l += Zvel * k                     # d4 is shifted <<1, <<1, then >>2, so the factor is k, NOT k/4
if Zpos.l >= 0: done
Zpos.l = 0
Zvel = -Zvel ; Zvel = Zvel >> 1 (asr)  # bounce with half speed
# _chkpuck (L35549-35560):
d0 = 5 - (Zvel >> 8)        (byte subtraction on the HIGH byte of Zvel)
if that byte result is negative: d0 = 0
if d0 <= 3 (unsigned): sfx($2C + d0)  # $2C hard landing ... $2F soft; high byte <= 1 -> no sound
```
- Note: the GODOT_TODO fact table says `Zpos += Zvel * 17 * d7 / 4`. The listing gives `Zpos += Zvel * 17 * d7` (same scale as X/Y). Fix the port fact.
- Quirk (port as-is): after landing, a slow puck never reaches Zvel 0. With d7 = 1, Zvel converges to about 34 (Zvel' = (102 - Zvel)/2), so gravity keeps running with Zpos.hi staying 0. Code that checks "resting" uses the high byte of Zvel (0..255 counts as resting).
- Also per loop for every object: `nopuck` high byte ($5E) and low byte ($5F) each `sub.b d7`, cleared when the byte result is negative (so values must stay below $80; a value >= $80 would be cleared on the first decrement).

## 4. Routines

### pucknorm (L42526)
- Purpose: the puck's assignment in normal play (asstab $18). Called by updateplayers via asslist.
- Inputs: a3 = puck, d7, `puckc`, `BA_PS_flags`, `gmode`, carrier struct. Outputs: puck pos/vel, temp1 ($40), temp2 ($42), `puckcross` times, side effects of callees.
```
1. if BA_PS_flags.bit2: sub_F2F4()                       # PS/SO attempt-over check
2. if bclr(pflags.bit1 pfna) was set: temp1 = 0; temp2 = $78
3. puckcross[1] -= d7; puckcross[3] -= d7               # word sub, no floor
4. temp1 -= d7; if temp1 < 0: temp1 += 5; findpc()       # about every 5 vblanks
5. if puckc >= 0:
       a2 = SortCords + puckc*$80
       a2touchpuck(a2)                                   # every loop while carried
       (hx, hy) = GetHot(a2)
       d0 = (hx + a2.X - puck.X) >> 2 (asr); puck.X += d0      # word ops on pixel words
       d1 = (hy + a2.Y - puck.Y) >> 2 (asr); puck.Y += d1
       puck.Xvel = a2.Xvel; puck.Yvel = a2.Yvel
6. puckIChk(); ChkOffsides()
7. if gmode.bit0 == 0:                                   # play running
       if puckc < 0 and puck.X.hi == OldX.hi and puck.Y.hi == OldY.hi:
           temp2 -= 1                                    # per loop, not d7
           if temp2 < 0: AddPenalty2(d0 = 6)             # "Face Off": puck stalled; a3 = puck
       else:
           temp2 = $78
8. if (Zvel high byte) == 0 and Zpos.hi == 0: puckunflip()
9. tail-jump checkpuckcoll()
```
- Quirk: step 7 calls AddPenalty2(6) on every loop while temp2 stays negative and play has not been stopped yet; temp2 is not reset there. The listing comment calls $42 "temp3"; it is temp2.
- Quirk: step 8 tests the high byte of Zvel, so Zvel in 0..255 counts as "not moving vertically".

### sub_F2F4 (L41556) and its fall-through sub_F37C (L41600)
- Purpose: in a penalty shot or shootout, decide when the attempt is over and stop play once. Called only from pucknorm when `BA_PS_flags` bit2 is set.
```
over = false
if puckc == BA_Goalie_SCnum: over = true
elif BA_PS_flags.bit5 (shot/pass released):
    if not word_FFC2FA.bit5:
        if puckc >= 0: goto countdown
        word_FFC2FA.bit5 = 1                      # puck has been released
    if puckc >= 0: over = true                    # someone picked it up after release
    else:
      countdown:
        if word_FFC31C < 0: over = true
        else: word_FFC31C -= 1                    # per loop; set to $64 when the shot/pass starts
if over: BA_PS_flags.bit4 = 1
if word_FFD454 == 0: BA_PS_flags.bit4 = 1          # PS/SO clock ran out
if not BA_PS_flags.bit4: return
if BA_PS_flags.bit6: return                        # already ended
BA_PS_flags.bit6 = 1
AddPenalty2(d0 = $A)
# falls through (no rts) into sub_F37C:
freezewindow()                                     # camera lock: yc1 = Vpos, xc1 = Hpos, sflags.bit6 = 1
if not word_FFC2FA.bit0 (penalty shot, not shootout): word_FFDEF0 = $A; sflags2.bit2 = 1
gmode.bit0 = 1                                     # play stopped
word_FFC2FA.bit2 = 0
BA_PS_flags bits 2,3,5,4,6 = 0
SortCords[BA_Sktr_SCnum].$61 (newpnum) = byte_FFC31E
sub_FC516()                                        # out of scope
```
- Note: when the shooter still has the puck after BA_PS_flags bit5 is set, the countdown runs too (same path).

### a2touchpuck (L42716)
- Purpose: bookkeeping whenever player a2 touches the puck: last-touch globals, assist chain, shot flag, offside call, icing call/arming. Callers: pucknorm (carrier, every loop), puckstick (_stdef), puckbody, puckgoalie.
- Inputs: a2 = player, `pucky`, `iflags`, stats struct, `tmap` (home players on ice), `tmsize` (IDA name; away players on ice). Outputs: `ltx`, `lty`, `ltplayer`, stats $18/$1A/$1C/$30, `sflags2` bit4, `byte_FFC2FE` bit7, `iflags`, `icingPlayer`.
```
ltx = a2.X; lty = a2.Y; ltplayer = a2.SCnum
a0 = stats of a2's team (pflags bit6: 0 home, 1 away)
d0 = a2.pnum (byte, zero-extended)
if a2.pflags3.bit3 (one-timer): byte_FFC2FE.bit7 = 1
if d0 != a0.$18:
    if bclr(a0.$30.bit3) was clear:            # normal: shift the chain
        a0.$1C = a0.$1A ; a0.$1A = a0.$18
    a0.$18 = d0
    if d0 == a0.$1C: a0.$1C = -1 (st byte)
sflags2.bit4 = 0                               # shot no longer "in flight"
a2offsides()
if iflags.bit2 and iflags.bit0 and a2.$34 != 0 (not goalie):
    if iflags.bit1:  icing = (a2.pflags.bit7 == 0)       # puck iced toward top; toucher defends top
    else:            icing = (a2.pflags.bit7 == 1)
    if icing:
        AddPenalty(d0 = $C) with a3 = SortCords[icingPlayer]   # icing whistle
        return                                           # iflags left as is
# _notice: re-arm for this toucher
iflags(byte) = 0
icingPlayer = a2.SCnum (low byte of $52)
d0 = pucky
if a2.pflags.bit7: iflags.bit1 = 1; d0 = -d0
if d0 < 0: return                      # toucher is past center (in his attacking half)
d0 = tmap - tmsize ; if a2 is away: d0 = -d0
if d0 < 0: return                      # toucher's team short-handed: icing allowed
iflags.bit2 = 1                        # icing armed
```
- Note: the listing comment says icingPlayer gets "SCnum+1"; `$53` is the low byte of the SCnum word, so it is the SCnum.

### a2offsides (L42687)
- Purpose: whistle offside when a player of a flagged team touches the puck in the attacking zone. Called by a2touchpuck.
```
if gmode.bit5 == 0: return
d0 = pucky ; if a2.pflags.bit7 == 0: d0 = -d0
if d0 < $68: return
if stats(a2 team).$30.bit4 == 0: return
if gmode.bit4: return
AddPenalty(d0 = $10) with a3 = a2
```

### ChkOffsides (L42598) and sub_100A6 (L42663)
- Purpose: set/clear each team's offside flag (stats $30 bit4). Called every loop by pucknorm (a3 = puck).
```
if gmode.bit5 == 0 or BA_PS_flags.bit2: return
sub_100A6(away stats); sub_100A6(home stats)           # clear flags of teams that are all back
if puck.Y >= $54:
    if puck.OldY >= $54: return                        # only on the loop the puck crosses +84 going up
    team = home if gmode.bit1 == 0 else away           # team attacking the top
    for its 6 structs (from team.$22): if $34 >= 0 and Y > $5E (94): team.$30.bit4 = 1; return
else:
    if puck.Y > -$54: return
    if puck.OldY <= -$54: return                       # only on the crossing loop going down
    team = away if gmode.bit1 == 0 else home
    for its 6 structs: if $34 >= 0 and Y < -$5E: team.$30.bit4 = 1; return

sub_100A6(team):
    if team.$30.bit4 == 0: return
    for each of 6 structs: if $34 >= 0: d0 = Y if pflags.bit7 else -Y   (else d0 keeps its previous value)
        if d0 > $58: return                              # someone still in the zone
    team.$30.bit4 = 0
```
- Quirk: in sub_100A6 an off-ice struct reuses the previous d0, and if the first struct is off ice d0 is whatever the caller left in it. Port: skip off-ice players (UNRESOLVED exact garbage value).

### puckIChk (L42796)
- Purpose: detect the armed icing puck crossing the far goal line. Called by pucknorm.
```
if iflags.bit2 == 0 or iflags.bit0 == 1 or puckc >= 0: return
if iflags.bit1: if pucky < $108: return          # must cross top goal line (y >= 264)
else:           if pucky >= -$108: return        # must cross bottom line (y < -264)
if -$2C <= puckx <= $2C: iflags.bit2 = 0          # through the crease/goal mouth: icing waved off
else:                   iflags.bit0 = 1           # crossed: icing pending until a2touchpuck
```

### puckunflip (L42831)
- Purpose: stop the puck spin animation (puck lies flat). Called from pucknorm when resting; also asstab $1A (the puck's assignment after a goal).
```
if 8 <= SPAnum < $18: facedir.hi ^= 2
facedir.hi |= 4
SPAnum = 0 ; SPAcnt high byte = $FF
```

### puckflip (L42849)
- Purpose: start the puck spin animation. Callers: checkgoal (_deflectsf), wallcoll (ported), puckbody, puckgoalie, deflect, sub_F6778.
- Input: d0 (only bit0 used).
```
facedir.hi ^= (d0 & 1) ; facedir.hi &= 3
SPAcnt high byte = $FF
SetSPA($46A)            # SPApflip; no restart if already playing
```

### puckshadow (L42862)
- Purpose: assignment of object 15. Normally the shadow under the puck; after a goal (or the glass easter egg) its animation is the goal siren, placed behind the net.
```
if shadow.frame == $18A:                     # normal shadow frame
    shadow.X = puck.X.hi ; shadow.Y = puck.Y.hi ; shadow.Z.hi = 0
    shadow.Y += 1        (shadow.X += 1 in horizontal mode)
else:
    if frame == 0: return                    # hidden (wallcollb2 clears it)
    shadow.X = 0 ; shadow.Y = $12C ; shadow.Z.hi = $E
    if puck.Y < 0: attribute = $8000 ; shadow.Y = -$12C ; shadow.Z.hi = $D
```
- Only the high (pixel) words are written; fractions are left alone.

### findpc (L42894)
- Purpose: predict where and when the loose puck crosses each goal line, for goalie AI. Called from pucknorm every ~5 vblanks.
- Inputs: puckx, pucky, puckvx, puckvy. Outputs: `puckcross[0..3]`. Preserves d0-d4/a1-a2.
```
for (slot, line) in ((0, +$108), (2, -$108)):
    dy = line - pucky
    if puckvy == 0: puckcross[slot+1] = -1; continue
    t = ((dy << 16) >> 4) / puckvy        # asr.l #4 then divs.w; = dy*4096/vy loops (approx; real is dy*65536/(17*vy))
    if t < 0: puckcross[slot+1] = -1; continue        # moving away
    puckcross[slot+1] = t (low word)
    x = dy * puckvx / puckvy               # muls.w then divs.w
    if divs overflowed: puckcross[slot+1] = -1; continue
    x += puckx
    if x >= $88:  x = -x + 3*$88           # = 408 - x
    if x <= -$88: x = -x - 3*$88           # = -408 - x
    puckcross[slot] = x
```
- Quirk: the side-board reflection uses 3*136 instead of 2*136. Port as-is.
- UNRESOLVED: if the first `divs.w` overflows (|dy*4096/vy| > 32767, i.e. a slow puck far from the line), the 68000 leaves d2 unchanged, sets V and leaves N officially undefined; the code only checks `bmi`. The stored time would be the low word of `dy << 12`. Recommend the port treat overflow as "no crossing" (-1); not verified on hardware.

### GetHot (L43282) and Hotlist (L626116)
- Purpose: stick hot-spot offset of an object from its current sprite frame. Callers: pucknorm, checkcoll, checkpuckcoll, puckbody, puckgoalie, passto, assnearest, others.
- Calling convention: the object pointer is pushed on the stack (`move.l a2,-(sp); bsr GetHot`); GetHot pops it. Returns d0 = X offset, d1 = Y offset (rink orientation). a0/a1 preserved.
```
f = obj.frame (word at $06)
if f <= 0 (signed): return (0, 0)
x = (int8) Hotlist[2*f] ; y = (int8) Hotlist[2*f + 1]
if attribute.bit3 (X flip): x = -x
if attribute.bit4 == 0 (no Y flip): y = -y      # table Y is screen-down; rink Y is up
if sflags.bit7 (horizontal mode): (x, y) = (y, -x)
return (x, y)
```
- Hotlist format: 838 entries of 2 signed bytes (X, Y), indexed directly by sprite frame number 0..837, 1676 bytes total, ROM file offset $A44C8 to $A4B53 (verified by byte search in `lst/nhl94.bin`; listing lines L626116-L627791). Entry 0 (8, 5) is never used. First entries: frame 1 = ($FC,$EC) = (-4,-20), frame 2 = ($FF,$E8), frame 3 = ($FE,$E4). The Godot port should export the table offline (e.g. via extractAssets94.js) as 838 (x, y) pairs.

### checkpuckcoll (L50247)
- Purpose: puck vs players (sticks, skater bodies, goalies). Tail-called by pucknorm (a3 = puck).
- Inputs: puck struct, `OOlist`, `OOlistpos`, `Ylist`, player structs. Outputs: through puckstick, puckbody, puckgoalie.
```
if puck.Y > $190 or puck.Y <= -$190: puck.Yvel = 0      # puck far out of the rink (over the glass)
if puck.Z > $10:                                          # too high for anyone
    if bclr(word_FFC2F4.bit2) was set: sfx(5)             # _sfx stub L50239; bit2 is only set in dead code
    return
i = OOlistpos[14]
while i != 15:                                            # walk up (higher Y)
    n = OOlist[i+1] ; if Ylist[n] - puck.Y > $16: break   # signed; $16 = cbody 8 + cstick 14
    ccx(n) ; i += 1
i = OOlistpos[14]
while i != 0:                                             # walk down
    n = OOlist[i-1] ; if puck.Y - Ylist[n] > $16: break
    ccx(n) ; i -= 1
```
`ccx(n)` (_ccx, all registers preserved around it; `n` is SCnum*2):
```
p = n / 2
if p == puckc or p > 11: return
a2 = SortCords + p*$80
if BA_PS_flags.bit2 and p != BA_Sktr_SCnum and p != BA_Goalie_SCnum: return
if a2.pflags.bit2 (pfnc): return
if a2.nopuck_hi ($5E) != 0: return
stick = not a2.pflags2.bit2 (pf2unav in 94) and puck.Z <= 5 and puck.Zvel <= $200   (signed)
if stick:
    (hx, hy) = GetHot(a2)
    dx = hx + a2.X - puck.X ; dy = hy + a2.Y - puck.Y
    if -$E <= dx <= $E and -$E <= dy <= $E:
        d = dx*dx + dy*dy
        lim = $C4 ; if (int8) puck.nopuck_hi > 0: lim = $C4 >> 2 = $31
        if d <= lim (unsigned): puckstick(a2, d0 = d); return
# _chkbody
if a2.$34 == 0: goto chkgoalie
if a2.pflags3.bit3 (one-timer): return
dx = a2.X - puck.X ; dy = a2.Y - puck.Y
if |dx| > 8 or |dy| > 8: return                            (signed compares against ±8)
d = dx*dx + dy*dy ; if d > $40: return
puckbody(a2, d0 = d)
```
`chkgoalie` (L50425):
```
d0 = a2.legstr ($68, agility byte)
if byte_FFC2FE.bit1 (always set) or byte_FFC2FC.bit6: d0 = (d0 + 2) & $FF
d0 >>= 1
if a2.pflags.bit3 (pfjoycon, human goalie): d0 = $F
d0 *= 2
if word_FFC2FA.bit0 (shootout) and d0 != 0: d0 -= 2
if d0 >= $1E: d0 = $1E
ChkBodyG = _cbg[d0/2] ; ChkBodySqG = _cbgsq[d0/2] ; NegChkBodyG = -ChkBodyG
if word_FFC2F8.bit1 (one-timer shot): ChkBodyG = $C ; ChkBodySqG = $90 ; NegChkBodyG = -$C
if a2.SPA == $250 or a2.SPA == $2A2 (pad stack): ChkBodyG = $12 ; ChkBodySqG = $144 ; NegChkBodyG = -$12
if puckz > $F: goto exit2
gx = a2.X
if a2.SPA == $250: off = -6 elif a2.SPA == $2A2: off = +6 else off = none
if off: if a2.pflags.bit7 == 0: off = -off ; if a2.$76.bit0 (94 handedness byte): off = -off ; gx += off
dx = gx - puck.X ; dy = a2.Y - puck.Y
if dx > ChkBodyG or dx < NegChkBodyG or dy > ChkBodyG or dy < NegChkBodyG: goto exit2
if dx*dx + dy*dy > ChkBodySqG (unsigned): goto exit2
puckgoalie(a2, d0 = dx, d1 = dy) ; return
exit2:
if bclr(word_FFC2F4.bit2) was set and puckc != a2.SCnum: sfx(5)       # effectively dead
```
Tables (dump in full, 20 words each, index = d0/2 = 0..15 reachable):
- `_cbg` L50382: `$C,$C,$D,$D,$D,$D,$D,$D,$D,$D,$E,$E,$E,$E,$F,$F,$F,$F,$F,$F`
- `_cbgsq` L50403: `$90,$90,$A9,$A9,$A9,$A9,$A9,$A9,$A9,$A9,$C4,$C4,$C4,$C4,$E1,$E1,$E1,$E1,$E1,$E1` (the squares of `_cbg`)
- With ratings 0..$1E, a CPU goalie uses entry min((agl + 2) >> 1, 15); a human goalie always entry 15 (14 in a shootout).

Quirks:
- The neighbor walk uses `Ylist` (Y as of each object's last sort, i.e. last `checkcoll` that moved it), not the live Y.
- The puck can touch several players in one loop: after a glue, the new carrier is skipped (== puckc), but later candidates get the steal check in the same loop.
- In 94, pflags2 bit2 ($63) is "player unavailable" (set at L37861, L49499, L51412), not the 93 `pf2dw`; such players get only the body/goalie check.

### puckstick (L50534) including CheckStkForContactWithSkater (L50566), PlayerPassOrLoosePuckStkLoad (L50638), _glue (L50665)
- Purpose: puck touches player a2's stick: steal attempt, pickup, deflection, one-timer. Called by checkpuckcoll with d0 = stick distance^2 (long).
```
if a2.$34 == 0 and gmode.bit4 (highlight): return        # replay: goalie stick ignored
a2.pflags.bit0 (pfdoff) = 0                              # listing comment says "offside bit"; it is pfdoff
if puckc >= 0:
    a0 = carrier
    if (a0.pflags ^ a2.pflags).bit6 == 0: return          # teammate: no steal
    if word_FFC2F8.bit5 (carrier in slot): if d0 > $40: return
    else:                                  if d0 > $24: return
    if a2.$34 == 0: goto steal                            # goalie always takes it
    if a0.$34 == 0: return                                # nobody steals from a goalie
    # CheckStkForContactWithSkater
    c = makepde(a0, a0.Stk($71) >> 1)
    k = makepde(a2, a2.Stk >> 1)
    r = randomd0(c - k + $24)
    if word_FFC2F8.bit5: if r > 4: return
    else:                if r > 2: return
  steal:
    a0.nopuck_hi = makepde(a0, a0.Stk >> 1) + $14         # byte
    a2.nopuck_hi = makepde(a2, a2.Stk >> 1) + $14
    lastplayer = a0.SCnum
    sflags.bit2 = 0 ; sflags.bit3 = 0
  stdef:
    sfx(6) ; a2touchpuck(a2) ; goto deflect               # puck knocked loose, nobody gets it
# _nosteal (loose puck)
if a2.$34 == 0 and d0 > $40: return                        # goalie stick needs a closer touch
if a2.pflags3.bit3 (one-timer in progress):
    if d0 > $64:
        if d0 <= $144 and a2.SPAnum < $18: a2.SPAnum = $18
        return
    if a2.SPAnum < $18: a2.SPAnum = $18 ; byte_FFC2FE.bit7 = 1
# _nosteal2
s = puckvx^2 + puckvy^2            (muls, long)
if sflags2.bit4 (shot taken):      t = $32C8
elif a2.pflags3.bit3:              exg a2,a3 ; onetimershot() (a3 = player) ; exg back ; return
else:                              t = a2.Stk * $15E + $32C8     # PlayerPassOrLoosePuckStkLoad
if s <= t*t (mulu.w, unsigned):    goto glue
a2.nopuck_hi = 8 ; goto stdef
```
`_glue` (also entered from puckgoalie):
```
snd = 7
puckc = a2.SCnum
a1 = stats of a2's team ; a0 = opponent stats
a0.$1A = -1 ; a0.$1C = -1 (st byte) ; a0.$30.bit3 = 1          # opponent's assist chain restarts
if bclr(sflags3.bit4) was set:                                   # first touch after a faceoff
    a1.$0E += 1 ; crowdlevel += $C8 ; snd = $C
    if a1 is home: CwdExciteLvl += $A ; snd = $B
song(snd)
if a2.SCnum == passplayer: a1.$14 += 1                           # completed pass
passplayer = -1 (st byte)
sflags.bit2 = 0 ; sflags.bit3 = 0
if a2.$34 == 0 (goalie):
    ChkShotStat()                                                # shot-on-goal bookkeeping
    a2.temp5 ($48) = $8C ; if a2.SPA == $2F4 (dive): a2.temp5 = 5
# hand human control to the new carrier
d0 = a2.SCnum
if d0 == c1playernum or d0 == c2playernum: return
if cont3team and d0 == c3playernum: return
if cont4team and d0 == c4playernum: return
if (cont3team or cont4team) and a2.$34 == 0 and a2.pflags.bit3: return
team = 1 if d0 < 6 else 2
if lastplayer != c2playernum and cont1team == team: jmp setc1player
if cont2team == team: jmp setc2player
if cont1team == team: jmp setc1player
return
```
- Ratings are 0..$1E, so the steal range c - k + 36 is 21..51 and the glue speed limit is 13000..23500 rvu.
- Steal odds per contact: 3/(c-k+36) normally, 5/(c-k+36) when the carrier is in the slot.
- Quirk: a successful steal does not give the stealer the puck; `deflect` sends it in a random direction and both players are locked out for Stk/2 + 20 vblanks.
- `onetimershot` (L959386, out of scope): calls doshot with passdir 4, shifts the assist chain, sets byte_FFC2FE bit7, adds $96 crowdlevel and $A excitement, stats $35C += 1, sets pf2aip and word_FFC2F8 bit1.

### puckbody (L50765)
- Purpose: puck hits a skater's body. Called by checkpuckcoll with d0 = distance^2.
```
if a2.pflags3.bit3: return
if puck.Z <= 8 and (d0 & $F) != 0: return          # low puck: only when dist^2 is a multiple of 16
a2touchpuck(a2)
sfx($24)
puck.Zvel = 0
a2.nopuck_hi = 8
dx = puck.X - a2.X ; dy = puck.Y - a2.Y
if dy == 0: (dx, dy) = GetHot(a2)                  # offsets only, positions not added
ovx = puck.Xvel ; ovy = puck.Yvel
puck.Xvel.highbyte = dx & $FF ; puck.Yvel.highbyte = dy & $FF     # low bytes keep old values
puckflip(d0 = dx)
if puck.Z <= 8: return
if ovx^2 + ovy^2 > $9000000 (unsigned; speed > $3000):
    if puck.Z > $C: FallDown(a2 = player, a3 = puck)  # a hard high shot knocks the skater down
    return
if bset(a2.pflags.bit5 pfalock) was already set: return
SetSPA(a2, $10D0)                                     # hit-by-puck animation
```
- Quirk: the ricochet velocity is "pixel offset * 256" plus the old low byte, not a reflection.

### puckgoalie (L50818)
- Purpose: puck hits a goalie's body box. Called by checkpuckcoll with d0 = goalie.X(+pad offset) - puck.X, d1 = goalie.Y - puck.Y.
```
if gmode.bit4 (highlight): return
# --- dead computation (results never used in 94) ---
region = 0 if puck.Z > 8 else 2
dir = (vtoa(-d0, -d1) - facedir.hi) & 7            # direction goalie -> puck, relative to facing
if dir & 3 == 0: dir = VDP_CNTR                     # straight ahead/behind: random bit
side = ((dir & 4) >> 2) ^ 1
d2 = (region + side) * 2                            # 0 glove L, 2 glove R, 4 stick L, 6 stick R
odds = a2[_list[d2/2]] + $F                         # never used
if a2.attribute.bit3: d2 ^= 2
f = a2.frame ; base, tab = ($197, _list2) if f < $233 else ($292, _list3)
quad = (tab[f - base] >> d2) & 3                    # never used (d0 is overwritten by a2touchpuck)
# --- live code ---
word_FFC2F4.bit2 = 0
ChkShotStat() ; a2touchpuck(a2)
if puckvy > $3000 or puckvy <= -$3000: song($B if goalie is home else $D)   # crowd reaction to a hard shot
sfx($24)
if puckc >= 0:                                      # carrier's puck runs into the goalie
    a0 = carrier ; puckc = -1 ; a0.nopuck_hi = $14 ; lastplayer = a0.SCnum
    sflags.bit2 = 0 ; sflags.bit3 = 0
    goto bounceoff
if a2.SPA == $2F4 (dive): goto bounceoff
lim = (randomd0((2 + a2.$6C) << 9) + $C00) * 2      # word; if the result is negative: lim = $7FFF
if not a2.pflags2.bit1 (pf2aip) and |puck.X| <= $2C and |puck.Y| <= $10E and |puck.Y| > $D2:
    lim >>= 2 (asr)                                  # puck in the crease area: harder to cover
if puckvx > lim or puckvy > lim or puckvx < -lim or puckvy < -lim: goto bounceoff
if a2.pflags2.bit2 (unavailable): goto bounceoff
puck.Zvel = 0 ; goto _glue                          # goalie covers the puck
bounceoff:
puck.Zvel = 0
a2.nopuck_hi = $A ; a2.temp4 ($46) = 4
dx = puck.X - a2.X ; dy = puck.Y - a2.Y
if dy == 0: (dx, dy) = GetHot(a2)
puck.Xvel.highbyte = dx & $FF ; puck.Yvel.highbyte = dy & $FF
tail-jump puckflip(d0 = dx)
```
The crease test in asm order: skip if pf2aip; skip if X > $2C or X < -$2C or Y > $10E or Y < -$10E; then reduce if Y > $D2, else skip if Y > -$D2, else reduce.
- `$6C` is the ShP byte loaded at L51682 (labelled "puck control" for goalies), 0..$1E, so the random range is $400..$4000 before adding $C00 and doubling.
- Dead code after `bra puckflip`: `bset #2,(word_FFC2F4).w; rts` (L50910) is unreachable.
- Quirk (port as-is or omit, no effect): in 94 the glove/stick save ratings and the `_list2/_list3` quadrant tables are computed but never used. The only goalie ratings that matter here are agility (body size via `_cbg`) and $6C (cover threshold).
- Tables, dumped in full:
  - `_list` L50959 (words, struct offsets of the save rating per region): `$73` (comment GGSleft), `$6E` (GGSright), `$70` (GSSleft), `$72` (GSSright).
  - `_list2` L50964, 156 bytes, index = frame - $197 (frames $197..$232):
    ```
      0: 55 9D 67 55 9D 67 55 9D 67 55 9D 67 55 9D 67 55
     16: 9D 67 55 9D 67 55 9D 67 55 55 55 55 55 55 55 55
     32: 55 55 55 55 55 55 55 55 55 F0 55 F0 55 F0 55 F0
     48: 55 F0 55 F0 55 F0 55 F0 55 F0 55 F0 55 F0 55 F0
     64: D5 75 D5 75 D5 75 D5 75 D5 75 D5 75 D5 75 D5 75
     80: 55 55 55 55 55 55 55 55 55 55 55 55 55 55 55 55
     96: 55 55 55 55 55 55 55 55 55 55 55 55 55 55 55 55
    112: F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0 F0
    128: 57 57 57 57 A5 A5 A5 A5 A5 A5 A5 A5 A5 A5 A5 A5
    144: A5 A5 A5 A5 A5 A5 A5 A5 A5 A5 A5 A5
    ```
  - `_list3` L51121, 48 bytes, index = frame - $292 (frames $292..$2C1):
    ```
      0: 9D 67 9D 67 9D 67 9D 67 9D 67 9D 67 9D 67 9D 67
     16: D5 D5 75 75 D5 D5 75 75 D5 D5 75 75 D5 D5 75 75
     32: D5 D5 75 75 D5 D5 75 75 D5 D5 75 75 D5 D5 75 75
    ```
  - Each byte holds four 2-bit quadrant values (bits 0-1 glove L, 2-3 glove R, 4-5 stick L, 6-7 stick R). Frames $233..$291 would index before `_list3`.

### deflect (L51170)
- Purpose: knock the puck loose in a random direction. Reached from puckstick (steal or failed reception).
```
puckc = -1
puck.Yvel = randomd0s($1000)        # -$1000..$FFF
puck.Xvel = randomd0s($1000)
puck.Zvel = randomd0($1000)         # 0..$FFF (always up)
puckflip(d0 = that Zvel value)
```

### checkgoal (L49633)
- Purpose: collisions with a net box and goal detection. Called by checkwallcoll2 (L49549, ported) for any object inside an end zone between the corners: |X| <= 136 - rx - 64 and |Y| >= 298 - ry - 64, with a2 = top net ($FFB64A) when Y > 0 side, bottom net ($FFB6CA) otherwise. For players it is called once with the body (radius rx, ry) and, by checkcoll, again with the stick tip (radius 1,1) when the body pass recorded no wall normal.
- Inputs: a3 = object, a2 = net, d2 = object X, d3 = object Y, `wcradiusx/y`. Outputs: puck pos/vel/Z, `collflag`, `puckc`, stats, sounds, events.
```
if obj.Z.hi > $D (signed): return                    # above the net
if obj.SCnum != $E: goto checkgoalp
dx = d2 - net.X ; xs = $10 + wcradiusx               # 21 for the puck
if dx > xs or dx < -xs: return
dy = d3 - net.Y ; ys = 2 + wcradiusy                 # 7 for the puck
if dy > ys or dy < -ys: return
collflag = -1 (st byte)                              # checkcoll will restore OldX/OldY pixel words
if obj.OldZ.hi >= $D:                                # came from above: lands on top of the net
    obj.Z.hi = obj.OldZ.hi
    Zvel = |Zvel|        (neg; if result < 0 neg back)
    return
# _nod
puck.pflags.bit7 = 0
if puckc >= 0:                                       # carrier skated the puck into the box
    c = carrier ; puckc = -1 ; c.nopuck_hi = 8
    t = pucky if c.pflags.bit7 else -pucky
    if t < 0: puck.pflags.bit7 = 1                   # this is the carrier's own net
# _nocon
my = (Y.l - OldY.l) >> 8 (asr.l, word)               # 1/256 px
if my == 0: goto sideentry
if my > 0: ny = +$100 ; pen = dy + 7     else: ny = -$100 ; pen = dy - 7     # (7 = ys)
mx = (X.l - OldX.l) >> 8
back = pen * mx / my                                 # muls.w, divs.w; on overflow goto sideentry
cx = dx - back                                       # X where the puck crossed the entry face
if cx < -21 or cx > 21: goto sideentry               # (xs)
if sign(obj.Y.hi) != sign(ny): wallcoll(ny, 0)       # entered through the back of the net: bounce
ny = -ny
if puck.pflags.bit7: wallcoll(ny, 0)                 # own-net carry: normal reversed -> no velocity change
if obj.Z.hi == $D: goto deflectsf                    # crossbar
if cx > 20 or cx < -20: goto deflectsf               # post (exactly ±21)
goto goal
deflectsf:
    ChkShotStat()
    snd = $25
    if gmode.bit0 == 0: snd = 8 ; crowdlevel += $12C ; CwdExciteLvl += $28
    sfx(snd)
    r = randomd0($1000) ; puck.Yvel = r if puck.Y < 0 else -r     # always away from the net
    puck.Xvel = randomd0s($1000)
    puck.Zvel = randomd0s($1000)
    tail-jump puckflip(d0 = last random)
sideentry:
    if X.hi - OldX.hi < 0: wallcoll(0, $100)  else: wallcoll(0, -$100)
```
`wallcoll(c, s)` is the ported board bounce (L50143): it treats (-s, c) as the direction into the wall and only reacts when the velocity points into it. So `(ny=+$100, 0)` acts like a wall above the puck and `(0, ±$100)` like a wall to the left/right.

`goal` (L49758):
```
if BA_PS_flags.bit2:                                   # penalty shot or shootout
    if not word_FFC2FA.bit0:                           # penalty shot
        want_top = SortCords[BA_Sktr_SCnum].pflags.bit7
    else:                                              # shootout
        want_top = (word_FFD594 == 0)
    if want_top and pucky < 0: return
    if not want_top and pucky >= 0: return
    word_FFC2F4.bit5 = 1
    if word_FFD594 != 0: word_FFD576 += 1  else: word_FFD574 += 1
    byte_FFC2FE.bit0 = 1
    sub_F37C()                                         # stop play, end the attempt (see sub_F2F4)
else:
    if gmode.bit0: return                              # no goals after the whistle (puck stays outside: collflag)
word_FFC2F4.bit0 = 1 ; byte_FFC2FE.bit3 = 0
ChkShotStat() ; sub_1A304()                            # sub_1A304: sound-driver channel reset
wait until vcount changes (one vblank)
sfx(0)                                                 # goal siren
freezewindow()
crowdlevel += $1F4
a2 = home stats, a1 = away stats ; swap if puck.Y < 0 ; swap again if gmode.bit1
                                                       # a2 = scoring team, a1 = conceding team
a2.$0C += 1
if word_FFC2F4.bit5 and not word_FFC2FA.bit0: a2.$362 += 1
if bclr(word_FFC2FA.bit4) was set: a2.$35A += 1        # breakaway goal
if sflags2.bit5 (power play):
    if (not sflags2.bit6 and a2 is away) or (sflags2.bit6 and a2 is home): a2.$356 += 1
a2[$342 + 2*gsp] += 1
if bclr(byte_FFC2FE.bit7) was set: a2.$35E += 1        # one-timer goal
if a2 is home: HmTeam = HomeTeam ; SongIndex = 3 ; ChooseSong() ; word_FFDECC = $78 ; word_FFDECE = SongNum
if ScoreSumbytes == $168: ScoreSumbytes -= 6           # buffer full: overwrite the last entry
e = ScoreSum + ScoreSumbytes ; ScoreSumbytes += 6
e.w[0] = sub_14A94()                                   # ((gsp << 14) | PerTimeTotal) - gameclock, word
e.b[2] = 2 + a2.$24 - a1.$24                           # skater difference: 1 SH, 2 even, 3 PP ...
CwdExciteLvl += $1E
if a2 is away: CwdExciteLvl -= $14 ; e.b[2] |= $80
e.b[3] = a2.$18 (scorer pnum) ; e.w[2] = $FFFF
a2[$B4 + scorer] += 1
if a2.$1A >= 0 and a2.$1A != scorer:
    e.b[4] = a2.$1A ; a2[$CE + a2.$1A] += 1
    if a2.$1C >= 0 and a2.$1C != scorer: e.b[5] = a2.$1C ; a2[$CE + a2.$1C] += 1
if a1.$26 >= 0: a1[$B4 + a1.$26] += 1                  # conceding goalie's row
ChkShotStat() ; sub_1284A()                            # sub_1284A: PP goal releases a penalized player, a2.$02 += 1
BA_PS_flags.bit3 = 0 ; PrintScores1()
word_FFC304 = $2710
if not word_FFC2FA.bit0: setass(a2, 7)                 # scorers celebrate (assscore)
collflag = 0                                           # keep the new puck position
puck.Xvel = 0 ; puck.Yvel = 0
puck.X.hi = +6 if puck.X >= 0 else -6
puck.Y.hi = +$110 if puck.Y >= 0 else -$110            # back of the net
puck.Zvel = $600 ; puck.Z.hi = 0
puckcross[1] = puckcross[3] = -1 (st byte)
puck.pflags.bit2 (pfnc) = 1                            # no more wall/net collisions
assreplace(puck, $1A)                                  # puck assignment = puckunflip
SetSPA(shadow, $102E)                                  # shadow becomes the goal siren
AddPenalty2(d0 = $E) with a3 = first struct of the conceding team (a1.$22)
```
Quirks (port as-is):
- The goal box is the puck's center within 21 px in X and 7 px in Y of the net center; the mouth is the face toward center ice. The posts are exactly the X = ±21 crossing columns and the crossbar is exactly Z == 13. A puck at Z 0..12 crossing at |cx| <= 20 scores.
- Own-net carry: on the loop the carrier is stripped at his own net, the puck cannot score; on later loops `pflags.bit7` is cleared again at `_nod`, so a puck still moving in can score (own goal).
- When the box check passes but no goal/deflection/bounce changes the velocity, the puck's X/Y pixel words are still restored by `checkcoll` (collflag), so it hovers at the face.
- The post deflection uses `randomd0s` for Zvel (may be negative), unlike `deflect`.
- `ChkShotStat` in `deflectsf` means a post hit with the shot flag set counts as a shot.
- The vcount busy-wait and `sub_1A304` are hardware sound/timing details; the port can drop the wait.

### setass (L49965)
- Purpose: give every on-ice skater of team a2 assignment d0 (7 = assscore). Called by checkgoal.
```
for each of 6 structs from a2.$22:
    if $34 <= 0: skip                    # goalie or off ice
    if pflags2.bit0 (fighting): skip
    pflags.bit2 (pfnc) = 0
    if bclr(pflags3.bit3) was set: sub_FEFF0()   # cancel one-timer: clears pflags3.bit3, pflags.bit5, pflags2.bit1, word_FFBF76, onetimerplayer = -1, SetSPA $50C, assexit or Setplass, SPAnum = 0, SPAcnt hi = $FF
    assinsert(d0)
```

### checkgoalp (L50000) and CheckBump (L50048)
- Purpose: players (SCnum <= 11) vs the net, as an ellipse, and knocking the net off. Entered from checkgoal for non-puck objects (d2/d3 = body or stick-tip position).
```
if a3.pflags2.bit5: return               # line change mode
if a3.Z.hi > $A: return
if a3.SCnum > $B: return
dy = d3 - net.Y ; dx = d2 - net.X
ex = ((dx << 4)^2) / $400                # word shift, muls, divu.w -> quotient word = dx^2/4
if ex > $100 (unsigned): return
ey = ((dy << 4)^2) / $79                 # = 256*dy^2/121
if ex + ey > $100 (unsigned word add): return       # ellipse: half-width 32, half-height 11
CheckBump()                              # may not return here (see below)
nx = net.Y - d3 ; ny = d2 - net.X        # (d0, d1)
r = sroot(nx*nx + ny*ny) + 1
c = (nx << 8) / r ; s = (ny << 8) / r    # divs.w
word_FFC2F8.bit4 = 1
wallcoll(c, s)                           # pushes the player away from the net center; bit4 stops wallcoll setting pflags3.bit4
word_FFC2F8.bit4 = 0
```
CheckBump:
```
if (VDP_CNTR & $1F) != 0: return         # about 1 in 32, from the HV counter
t = pucky - net.Y ; if t > $28 or t < -$28: return     # puck within 40 px (in Y) of this net
if -$2000 <= a3.Xvel <= $2000 and -$2000 <= a3.Yvel <= $2000: return
# bump: pops its saved regs AND checkgoalp's return address, so it returns straight to checkwallcoll2
net.Xvel = a3.Xvel >> 2 ; net.Yvel = a3.Yvel >> 2       # asr; the net slides
a3.Xvel = 0 ; a3.Yvel = 0
sflags.bit6 = 1
if gmode.bit0: return
AddPenalty2(d0 = 8) with a3 = player     # "Face Off" whistle
```
- UNRESOLVED: `VDP_CNTR` is the hardware HV counter; the port needs a stand-in (e.g. a random 1-in-32 from a non-gameplay RNG or the frame counter). Not deterministic on hardware.
- Quirk: after a bump the code skips the rest of checkgoalp and checkgoal (no wallcoll), so d0/d1 are left as the shifted velocities.

### wallcollb2 (L50092)
- Purpose: entry to the board bounce; for the puck, decides if it flies over the glass. Called by checkwallcoll2 for straight boards and corners (d0/d1 = wall cos/sin).
```
if a3.SCnum != $E: tail-jump wallcoll
if puck.Z.hi > $1D (signed): goto out                  # above all glass
if puck.Z.hi <= $12 (unsigned): tail-jump wallcoll     # below the glass top: normal bounce
# 18 < Z <= 29 (or Z negative, which is > $12 unsigned)
if puck.Y < $118: goto out                             # everywhere except the top end wall: out
if puck.X < $D or puck.X > $F or puck.Yvel < $FA0 (signed): tail-jump wallcoll   # taller glass at the top end
# easter egg: puck hits the goal light above the top glass (X 13..15, Yvel >= 4000)
puck.Yvel >>= 1 (asr)
SetSPA(shadow, $1078)                                  # shadow plays the light/siren animation
sfx($E) ; crowdlevel += $258 ; CwdExciteLvl += $F
out:
sflags.bit6 = 1                                        # scroll lock
puck.pflags.bit2 (pfnc) = 1                            # no more collisions
if puck.Y < 0: puck.attribute |= $8000                 # draw over the near boards
shadow.frame = 0                                       # hide the shadow (puckshadow returns early)
if gmode.bit0: return
AddPenalty2(d0 = 6) with a3 = SortCords[ltplayer]      # "Face Off": puck out of play
```
- Quirk: asymmetric glass. Above the side boards, corners and the bottom end, any Z > 18 leaves the rink; only the top end (Y >= 280) has glass up to Z 29. A puck with negative Zpos also leaves.
- After `out`, the puck keeps moving with pfnc set; checkpuckcoll zeroes Yvel once |Y| >= 400.

### puckvzadj (L958869)
- Purpose: set puckvz so a shot floats up to about 10 px high at the goal line ("top shelf" over a pad stack or into an empty net). Called by doshot L37689 when `word_FFC2F6` bit4 (in-close top shelf) was set and the shooter is not doing a one-timer. Saves/restores all registers.
```
dy = | |pucky| - $108 |
if puckvy == 0: return (puckvz unchanged)
vy = |puckvy|
k = 17 (22 if word_FFD06E != 0; never set)
q = (dy << 16) / vy        # divu.w; on overflow (dy << 16)/vy > $FFFF the 68000 leaves the dividend, low word 0 -> q = 0
n = (q & $FFFF) / k        # divu.w, quotient word
if n == 0: n = 1           # loops until the goal line
v1 = $A0000 / (n * k)      # divu.w by the low word of n*k; on overflow v1 = 0 (dividend low word)
v2 = 3 * k * n             # mulu; if >= $7FFF (signed long compare): v2 = $7FFF
vz = (v1 + v2) & $FFFF
if vz is negative as a word: vz = $7FFF
puckvz = vz
```
- Meaning: with Z += Zvel*k and Zvel -= 6k per loop, this reaches Z = 10 px ($A0000) after n loops.
- Quirk: n = 1 (very close or very slow shots, including the divu overflow case) gives v1 = 38550, v1 + 51 is negative as a word, so vz = $7FFF.

## 5. UNRESOLVED / notes for the port

1. findpc first `divs.w` overflow: the N flag is undefined on the 68000; recommended "no crossing" (-1). Not verified on hardware.
2. CheckBump and the puckgoalie dead code read the VDP HV counter (`VDP_CNTR`) as a random source. CheckBump's 1-in-32 gate is live and needs a stand-in.
3. sub_100A6 (offside clearing) uses a stale d0 for off-ice structs; the exact stale value depends on the caller's registers. Recommended: skip off-ice players.
4. Names of team stats offsets $356 and $362 come from listing comments and usage. $356 counts goals by the team not on the power play (short-handed); $362 counts goals with `word_FFC2F4` bit5 (set only by the penalty-shot path) outside shootouts. The listing comment calls $362 "SH Goals".
5. 94 struct offsets differ from the 93 equates in the preamble: handedness is `$76` bit0 (L51694-51696, 1 = left after the XOR), `$74` is the fight byte, `$75` checking, `$6C` ShP ("puck control" for goalies), `$71` Stk; pflags2 bit2 is "unavailable" (pf2unav), pflags3 bit3 is "one-timer in progress".
6. The goalie save-rating tables (`_list`, `_list2`, `_list3`) are dumped for completeness, but in 94 their results never affect play (section puckgoalie). If a later finding shows doshot uses them, revisit.
7. GODOT_TODO's Z-gravity fact (`/4` on the Z step) disagrees with the listing (section 3.2).
