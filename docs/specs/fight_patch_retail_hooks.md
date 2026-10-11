# Fight patch: retail '94 behaviour at every hook the patch touches

Scope: what the **unpatched** NHL '94 engine does around the code that `chaos81/nhl94-patches/94_fight/scripts/fight_patch.asm` (v1.01) hooks or calls. With this, the port can run the patch's fight code (fightinput, checkfight, ChkFightValue, SF, assfight, chkhit, CwdFight, FightFall, clear, assfwatch, banner, addinfo, upgloves) on top of the retail logic.

Sources: `lst/nhl94.bin.lst` (Lnnnnn = listing line). ROM addresses were checked by disassembling `lst/nhl94.bin` with capstone (the listing has no address column). Every routine address the patch's equates name was confirmed at its first instructions: playeracc $10BC2, SetSPA $1073A, assinsert $10658, AddPenalty2 $11F62, setd0player $15322, assnothing $CBE4, getpde $1575A, randomd0 $11086, sfx $11132, printz $11B92, eraser $1197E, setInjuryType $144AC, skateto $103C8, check4check $EACE, sroot $110BE, box $18A56, lcfound2 $BB36, Framer $119B8, print $11BA4, getname $18A90, appstring $11D9E, appendz $11D96, checkint $13BD6, checkcheck $13CC4.

Units: **vblank** = one 60 Hz VBlank. **d7** = vblanks since the previous DoGameFrame (>= 1). A "game second" in periodiceevents = 24 vblanks (`lldisp`). Bit tests on memory (`btst #n,(x).w`) are byte operations.

Cross-references: `rules_clock_penalties.md` (penalty queue, tmpdst, PenaltyList dump), `collisions_checking.md` (checkcx, FallDown, setInjuryType), `input_linechanges.md` (doinput), `animation_assets.md` (updateanim, addframe, draw order, sfx ids).

---

## 0. Hook map

| Patch site | Retail bytes there | Retail meaning |
|---|---|---|
| doinput `$B258` (10 bytes) | `btst #0,$63(a3)` / `bne.w $B8F0` (L35995-35996) | Fighting players branch to `fightinput` (L36560) = a bare `rts`. The patch's `jmp chkfightinput` + 2 `nop` keeps the same test and falls back to `$B25E` (nops) then `$B262`, so the retail flow is unchanged. |
| checkcx `$13B16` (12 bytes) | `bsr checkint` / `bsr checkcheck` / `bsr $1454A` (L48694-48696) | `$1454A` = `checkfight` (L49544) = bare `rts`. The patch's `cxchecks` calls the same three in the same order. Resumes at `$13B22` (`move.w d1,d4`). |
| asstab `$18DCC` / `$18DD0` | `dc.l $CBE0` / `dc.l $CBE2` (asstab base $18D7C, L56671) | Assignments $14 and $15 both point at bare `rts` (L38268 "assfight", L38270 "assfwatch"). |
| uppads `$16648` (38 bytes) | uppads head, L52666-52679 | Glove sprite placement (section 3). |
| Begin `$76C6` | `cmpa.w #$DEF4,a0` | Boot RAM clear `$FFB000..$FFDEF3` (clr.l). The patch extends it to `$FFDF01` to cover `OptFight` ($FFDF00). |
| `$16E7C` (sprite_patch) | `dc.w $0161` (L53401) | Frame word of the gloves object in `_listffo` (section 3). |
| `$A724/$A77C/$A784` | `cmp.w #$34E,d2` / `#$162` / `#$179` | SetRCords (reverse-angle replay): valid-frame limit and the frame range $162..$178 whose X flip is toggled. |
| `$17C86` | tail of LoadDefMenuOptions copy loop | Default menu options. |

Confirmed RAM addresses (from instruction bytes): PenBuf $FFC3A4, Pencntdwn $FFC3E6, InjCntDown $FFC3EC, PerTimeTotal $FFC46C, ChkCnt $FFC46E, glovecords $FFBEE2, glove object $FFBE5C, puck struct $FFB74A (pflags2 = $FFB7AD), xc1 $FFBF8E, yc1 $FFBF90, sflags $FFC2EC, gmode $FFC2EA, team structs $FFC6CE / $FFCA32.

---

## 1. Penalties $26 / $28 / $2A through the retail queue

### 1.1 PenaltyList records (ROM $18E0C + offset)

| id | record | delay byte | minutes | text | ref script |
|---|---|---|---|---|---|
| $26 PenFighting | $190D0 | $28 → Pencntdwn candidate $28<<5 = $500 = 1280 vblanks (21.3 s) | 5 | "Fighting" | roughing script (00/32 0D/8 0E/8 x4 01/8), 104 vblanks |
| $28 PenFighting* | $190F0 | $28 (1280) | 5 | "Fighting *" | same |
| $2A PenInst | $19112 | $28 (1280) | 2 | "Fight Instigator" | same |

$26 and $28 differ **only in the text** (and so in the PenSum id). No retail code queues any of the three (rules spec U1).

### 1.2 AddPenalty2 (L45954, $11F62). Called by the patch with a3 = the player, d0 = id.

```
if sflags bit7 (horizontal): return                  ; NO OptPen gate here (AddPenalty has it, L45939)
if d0 >= $E:                                         ; L45960: true for $26/$28/$2A
    crowdlevel += $C8
    j = $C ; if a3 away: CwdExciteLvl += $14 ; j = $B
    song(j)                                          ; music/jingle routine, not sfx
slot = first zero word of PenBuf[0..31]; none: return
PenBuf[slot] = (d0 << 8) | a3.SCnum (byte $53)
if PenaltyList[d0].minutes <= 0: return               ; L45982 (entry stays, it is a stoppage)
DelayedPen |= (a3 away ? 4 : 2)                      ; L45987/45991
if a3.pflags2 bit4 already set: PenBuf[slot] = 0      ; L45993-45995: one queued penalty per player
a3.pflags2 bit4 = 1
```
- Consequence: fights queue 5-minute majors even with **penalties off** (OptPen = 0). Only the patch's own instigator code checks OptPen.
- PenBuf full: nothing is queued. The patch's FightFall search (1.9) then runs off the buffer.

### 1.3 checkfornewpen (L46358): call or delay

```
if sflags bit7: return
for each entry e (a0 = past it) until a zero word:
    if gmode bit2 (gmpen): goto iscalled
    if rec.minutes == 0: goto callit
    if puckc < 0: goto delayed                                        ; L46375-46376
    if ((puckc - 6) XOR (sext(e.lo) - 6)) < 0: goto delayed           ; L46381-46382: other team has puck
callit:   Stop4Pen
iscalled: if bit7 of e.lo already set: continue ; set it              ; L46386
          d1 = rec.delay << 5 ; if d1 > Pencntdwn (signed): Pencntdwn = d1   ; L46393-46397
delayed:  if gmode bit3 not yet set: set it; SetPA($2C "Penalty")
```
For a fight: checkfight sets `puckc = a3.SCnum` before SF, so the first fight (or instigator) entry is on the puck team's side and is **called at once** on the next PenaltyManager pass (next DoGameFrame, because checkfight runs inside updateplayers which comes after periodiceevents). All entries are then marked called and `Pencntdwn = $500`. An older delayed entry that was skipped earlier in the same pass is marked on the following frame (its delay 128 < 1280 changes nothing).

### 1.4 Stop4Pen (L46411)

```
if gmode bit0 was clear (bset):           ; first whistle of this stoppage
    (x,y) = (puckx, pucky)                ; ids $26/$2A are not $E/$6/$C
    clamp x to +-$46; |y| >= $A6 -> y = +-$CE, x = +-$46 (sign of the unclamped x)
    fox,foy = x,y ; limitfo               ; per entry: no faceoff in that player's attacking zone
Pencntdwn = 0 ; gmode bit2 = 1 ; sub_1A304 ; sfx(3) whistle ; SetPA($A)
```
With one fighter from each team, limitfo pushes an end-zone spot back to the neutral-zone dots (+-$46, +-$41).

### 1.5 Pencntdwn ($FFC3E6, word, vblanks)

| Writer | Line | Value |
|---|---|---|
| Stop4Pen | L46472 | 0 |
| checkfornewpen | L46397 | max(Pencntdwn, delay*32) |
| chkprogress | L46059 | -= d7, only while gmode bit2 |
| sub_FF88E (end-of-game wipe) | L976561 | 0 |
| Begin RAM clear | - | 0 |

- `>= 0` with gmpen set: whistle-to-presentation countdown. Play continues on screen and the clock is stopped.
- `< 0` with gmpen set: presentation running (chkprogress → InProgress every frame).
- **It is never reset after a stoppage.** After InProgress finishes, Pencntdwn stays negative through live play until the next Stop4Pen. So on the frame a fight starts, Pencntdwn is negative if any stoppage with a delay has already happened this game, otherwise 0. The patch's `assfight` (jmp assnothing when negative) and `fightinput` (rts when negative) therefore do nothing for any fighter whose object runs later in that same updateplayers pass. From the next frame on it is $500.
- The patch's FightFall overwrites it with $3C (60 vblanks = 1 s) or $B4 (180 = 3 s). That replaces whatever remains of the 1280, so the presentation starts 1 s or 3 s after the knockdown. FightFall cannot run once it is negative, because assfight no longer calls chkhit then.

### 1.6 chkprogress at expiry (L46053-46098)

```
if !gmode bit2: return
if Pencntdwn < 0: goto InProgress
Pencntdwn -= d7 ; if >= 0: return
gmode bit3 = 0
if no PenBuf entry has rec.minutes > 0: return      ; (fights always have one)
sflags2 bit2 = 1; forceblack; SetHor; ref graphics; NewTicker; NewTicker3pt2
puckc = $FFxx (st)                                  ; L46084
puck: assinsert($1A puckunflip); puck.temp1 = $1C20 ; L46086-46088
RefStep = $FFxx; RefCnt = 0; UpdatePA; RefCnt = $32; PushRef(0); palcount = $18
```

### 1.7 InProgress (L46187): assessment of the fight entries

Runs once the ref animation is idle. It takes the **newest** entry first. Queue order after a fight: `[older..., PenInst(teammate)?, $26(a3), $26(a2)]` (ChkFightValue queues the instigator before SF; SF runs for a3 then a2). So the order is a2, then a3, then the instigator.

```
if PenBuf[0] == 0: finish
e = last non-zero entry
if bit7 of e.lo was clear (bclr, L46201):        ; second visit, after assessment
    if SortCords[e.lo].position >= 0: return     ; wait until he reaches the box (asspenalty)
    PenBuf entry = 0 ; return
rec = PenaltyList[e.hi] ; word_FFC2F6 bit5 = 0
m = rec.minutes (L46222); m == 5 -> word_FFC2F6 bit5 = 1
PenSum record (time, id|$80 if away, pnum)   ; full list ($EC): the last record is overwritten
team.penalties += 1 ; team.PIM += m ; team[$102+pnum] += m ; TempPlOffset = ($8000 if away)|pnum
v = m*60 | $2000                                  ; L46264-46265
if team.tmpdst[pnum] >= 0 and bit12 set: v |= $1000    ; L46270
team.tmpdst[pnum] = v ; v &= $EFFF
for d1 = $32 down to 0 step 2 (opp slots 25..0):      ; L46275
    if (opp.tmpdst[d1] & $EFFF) == v and FFC2F6 bit5:
        opp.tmpdst[d1] |= $4000 ; team.tmpdst[pnum] |= $4000 ; break   ; L46286-46287
append pnum*2 to team box list ($9A)
player: assreplace($C asspenalty)                 ; L46298
SetPA(id) ; sub_12DA6
finish (L46313): recount both teams (sub_123DE); gmode bit2 = 0; puck: assreplace($1B puckfaceoff, or $1E)
```

Results:

| Player | tmpdst after assessment | after sub_123DE | Counts against strength | Box time |
|---|---|---|---|---|
| uninjured fighter | $612C (5:00, coincidental) | $412C | no (bit14) | ticks every second; at expiry ($3FFF, bit12 set) → 0 (served). No return-to-ice, no beep that second (quirk Q17). Bench at next faceoff. |
| fight-injured fighter (FightFall wrote $112C) | $712C | $512C | no (bit14, bit12) | ticks; expiry at $4FFF (bit12 clear) → **$1000**: out for the rest of the game, shown "Injury G" (L32100 status display, strings at L32115: tmpdst >= 0 with bit12 → "Injury G"). Intermission keeps $1000. ResetBench leaves $1000 alone and does not count it in PBnum. |
| instigator's teammate ($2A) | $2078 (2:00) | $0078 | yes | normal minor: power play for the other team |

- The two fighting majors **always** pair as coincidental. When the second fighter is assessed, the first one's `tmpdst & $EFFF` is $212C (whether or not bit12 was carried). A pair only fails to match if one of the fighters already had an unrelated $212C partner on the other team in the same stoppage.
- "Who goes to the box": every entry with minutes > 0 gets `asspenalty` and must physically reach the box before the next entry is processed. The fight-injured player skates there at max speed / sqrt(8) with the $11E6 skate animation (section 7), which delays the presentation.
- A stoppage entry (minutes 0) in horizontal mode is dropped silently.

### 1.8 Does the puck carrier being a fighter matter?

- **Call timing:** no. checkfight overwrites `puckc = a3.SCnum`, so the whistle is always immediate (1.3).
- `updateplayers` L35557-35563: the puck-carrier star (`sub_C656`, d4 = -2) is skipped when `puckc` is fighting.
- The puck is on puckunflip (section 2). The real carrier loses it because pucknorm, which carries it, no longer runs.
- playeracc's puck-carrier halving (acceleration L43751-43759, max speed L43814-43822) applies **only to goalies** (`tst.w $34(a3); bne` skips it), so it never touches a fighter.
- doplayeracc's $53E "skate with puck" animation keys on puckc. That matters only for the a3 fighter skating through doplayeracc, which does not happen before puckc is cleared at the presentation (L46084).

### 1.9 The patch's FightFall rewrite: whose entry becomes $28

Register trace. assfight calls chkhit with a3 = the assfight player and a0 = its impactp opponent. chkhit's hit branches fire on **a3's** punch frame (SPFfight+6/+11 high, +7/+12 low), then `exg a0,a3`. After that, a3 = the player who was hit and a0 = the puncher. `subq #1,$44(a3)` takes the point off the victim, and `bmi .FightFall`. Inside FightFall, the PenBuf scan compares `$52(a0)`, which is the **puncher (the winner)**. So "Fighting *" goes to the fighter who landed the last blow, not the loser. The same register sets the winner's temp3 to -1, and the winner's Chk ($75) is the injury roll's threshold. Everything else (SPAffall/SPAbfall, toddle bit, setInjuryType, $112C) is applied to the victim (a3).

- The scan (`a1 = PenBuf-2; loop: a1 += 2; until byte(a1) == $26 and (byte(a1+1) & $F) == a0.SCnum`) has **no bound**. The `moveq #$1F,d0` is dead because d0 is overwritten. If the entry is missing, it reads past PenBuf. A port should bound it to 32 entries.
- `& $F` strips the called bit (bit7) from the SCnum byte.

### 1.10 Port (`game_rules.gd`) against retail

Matches: `add_penalty2` (gates, crowd/jingle, one-per-player, no OptPen gate), `checkfornewpen` (call/delay test, max delay), `stop4pen` (spot, limitfo, Pencntdwn = 0), `chkprogress` (expiry, puckunflip insert, temp1 $1C20, puckc = -1), `in_progress`/`_assess` (newest first, bit12 carry, coincidental test against `& $EFFF`, asspenalty, wait for position < 0), `recount` (bit14/bit12 skip), `_tick_box` (coincidental expiry → 0 or $1000), `PENALTY_LIST` $26/$28/$2A. `pencntdwn` is not reset at `_finish`, so the stale-negative behaviour (1.5) reproduces.

Lacks or differs: see section 13 (tmpdst write in `set_injury_type`, PenSum and box-list overflow details).

---

## 2. Puck pflags2 bit 0 ($FFB7AD bit 0, "pf2fight")

| Access | Where | Line / ROM |
|---|---|---|
| set | **nowhere in retail** (only the patch's checkfight `bset #0,$63(puck)`) | - |
| clear | `Endfaceoff` (`bclr #0,$63(a3)`, a3 = puck, reached from puckfaceoff2's per-frame path) | L42455 |
| clear | `defaultsprites2` zeroes all 16 sort structs (setupice at StartGame; setoptions) | L53416-53419 |
| clear | Begin RAM clear | - |
| **not** cleared | `resetplstuff` (L53659) clears `$63` only on the 12 skater structs (via tmsort); the puck keeps the bit | |
| read | `skateto` `_nf` (L42994, ROM $10444): a stopped skater (dir > 7 and zero velocity) turns one step toward (xc1,yc1) instead of the puck | |
| read | injury message `loc_1871C` (L55894, ROM $18796): prints "the game" at (20,6), turning "Out for period"/"Out for game" into "Out for the game" | |

Other pflags2 bit 0 uses (skater structs, all retail): checkcx keeps a fighter's impactp (L48675-48681); updateplayers skips the carrier star (L35560); lineinput doplayeracc gate (L36788); check4check skips fighters (L40905); holdcheck / Bcheck skip fighters (L49043, L49108); setass skips fighters (L49972); Endfaceoff clears it on the puck only.

### puckunflip ($1A, L42831) as the puck's assignment

```
puckunflip (a3 = puck), every frame:
    if 8 <= SPAnum < $18 (signed): facedir ^= 2
    facedir |= 4 ; SPAnum = 0 ; SPAcnt = $FFxx (st)       ; stops the spin animation
    rts                                                     ; never exits by itself
```
- Physics continue in updateplayers: velocity integration, drag (puck pflags bit0 pfdoff → `v -= v>>9`), gravity and bounce, and `checkcoll` against the boards. Player pick-up (`checkpuckcoll` → `puckstick`) is only called from pucknorm (L50247 xrefs), so nobody can take the puck.
- Stack (`assinsert` = `assnum = (assnum-1)&7; asslist[assnum] = d0; pflags bit1 = 1`, L43202). Fight start: `[pucknorm, puckunflip]`. Presentation (1.6) pushes a second puckunflip. InProgress finish `assreplace`s the top slot with $1B puckfaceoff; puckfaceoff `assreplace`s $1C puckfaceoff2; Endfaceoff `assreplace`s $18 pucknorm and clears the fight bit. Nothing on these paths calls `assexit` on the puck, so the two older slots of the 8-slot ring are simply abandoned.

---

## 3. glovecords ($FFBEE2) and the glove object ($FFBE5C)

### 3.1 Every access in retail

| Access | Routine | Line | ROM |
|---|---|---|---|
| write `move.w (a0)+,glovecords` | SetRCords (replay playback) | L35172 | $A81E |
| read `move.w glovecords,(a0)+` | updatereplay (recorded every frame) | L35312 | $A9BA |
| `clr.w` | puckpenshot | L41295 | $EFE4 |
| `clr.w` "no fighting gloves" | puckfaceoff2 setup | L42066 | $F91A |
| `clr.w` | sub_1354C (intermission highlight game setup) | L48252 | $13642 |
| read X byte / Y byte | uppads | L52669, L52671 | $16650, $16658 |
| clear | Begin RAM clear | - | - |

Nothing in retail writes a non-zero value, so the glove sprite never shows in '94. The only other reference to `glovestruct` is uppads (L52667). `defaultsprites` initialises it.

### 3.2 The glove object

- It is `ffo` object 6 of 7. The base `pads` is $FFBDB4 with stride $1C, so object 6 = $FFBE5C. Fields: +0 X, +2 SAT X adjust (setffo), +4 attribute, +6 frame, +8 old frame, +$12 VRChar, +$14 Y, +$18 Z.
- Init (`defaultsprites` `_listffo`, L53361; gloves entry L53398-53403): X=0, Y=0, Z=$FFFF (hidden), **frame $0161** (word at ROM $16E7C, "SPFgloves", 353), attribute 0, VRAM char budget 5. `st 8(a3)` forces a tile DMA on first draw. setupice preloads only ffo 0-5.
- Retail frame 353 is a placeholder: 1 sprite piece, 1x1 tile $EA5 at (0,0). That tile is blank except one pixel. sprite_patch sets the word to $34E (846), the new gloves-and-stick frame.

### 3.3 Original uppads head ($16648-$1666D, 38 bytes, L52666-52679)

```
a0 = $FFBE5C
byte Z(+$18) = $FF                    ; st: Z word negative -> hidden
d0 = byte glovecords ; if 0: goto $1666E
d1 = byte glovecords+1
X = sext(d0) * 4 ; Y = sext(d1) * 4 ; Z = 0
$1666E: (pads/star placement for ffo 0-5 continues)
```
The patch's `upgloves` is identical, plus: it clears attribute X flip (byte 4 bit 3) every frame, and in reverse-angle replay (`word_FFC2F4` bit 4) it negates X and Y and sets the X flip.

### 3.4 When shown, coordinates, draw order

- Shown when `glovecords` X byte != 0 and `addframe` succeeds: Z >= 0 (L52797) and `find3d` is not off screen. Hidden from the next puckfaceoff2 / puckpenshot (or never shown in retail).
- Rink coordinates (X, Y, Z = 0), drawn like any rink object: `screen_x = 128 + (X - Hpos) + piece.x`, `screen_y = 112 - (Y - Vpos) + piece.y` (animation_assets.md L314). In horizontal mode find3d applies its rotated mapping.
- Draw order, from setvideo (L51875): checkfo, checksso, setsortcords (the 16 sort objects in SprSort order), **setffo** (ffo 0..5 stars/pads, then **gloves last**), clock, zamboni, crowd, ref. The earliest sprite in the VDP link list is in front, so the gloves are **behind every player, the puck, the nets and the pad stars**, and in front of the clock, zamboni, crowd and ref sprites. Attribute 0: palette 0, low priority.

---

## 4. Scroll lock: xc1 ($FFBF8E), yc1 ($FFBF90), sflags bit 6

checkwindow (L35783, once per DoGameFrame after updateplayers):
```
d2 = yc1 ; d3 = xc1
if !sflags bit6:
    a3 = puckc >= 0 ? SortCords[puckc] : puck
    if puckc >= 0: yleader += 2*d7 toward a3's attacking end, clamp +-$32
    d2 = (a3.Yvel asr 7) + a3.Y + yleader ; d3 = a3.X ; yc1 = d2 ; xc1 = d3
; locked: xc1/yc1 are used as they are
Vpos: dead zone +-10; target = clamp(d2 -+ 10, -$C8 .. $100); step = (target-Vpos) asr 4, at least 1 if non-zero
Hpos: dead zone +-40; target = clamp(d3 -+ 40, -$3C .. $3C); same easing
```
The port's `HockeyWorld.checkwindow` / `scroll_lock` / `SF_SLOCK` / `freezewindow` match this line for line (scroll_lock = (xc1,yc1); freezewindow copies (Hpos,Vpos)).

sflags bit 6:
- Set by: freezewindow (L35774; called by clockcont, L41601, L49815), puckfaceoff (L41714), setInjuryType (L49506), L50083 (CheckBump net), wallcollb2 (L50120).
- Cleared by: puckfaceoff2 (L42103, before it scrolls to the dot), puckpenshot (L41325), sub_1354C `clr.b sflags` (L48247). The pause save/restore of the sflags word (L30225/30249) leaves it as it was.
- So a fight lock lasts until the faceoff after the presentation. setInjuryType moves the lock to the injured player's position (both coordinates), and from then on the patch no longer writes xc1, because temp3 is negative for both fighters.

---

## 5. setInjuryType (L49497, $144AC) and InjCntDown

```
in:  a2 = injured, a3 = "checker"     (FightFall: a2 = a3 = victim)
push d0
a2.pflags2 bit2 = 1 (unavailable)
crowdlevel += $12C ; CwdExciteLvl += $1E ; sfx($D)
xc1 = a2.X ; yc1 = a2.Y ; sflags bit6 = 1
a0 = HmShots ($FFC6CE) ; d1 = 0 ; if a2 away: d1 = $8000 ; a0 += $364
d1.b = a2.pnum ($66) ; TempPlOffset = d1 ; d1 = sext.b(pnum) * 2
f = a3.$74 >> 2   (getFgtbyte runs after exg a2,a3, so it reads the CHECKER)   ; L974883
f == 0                     -> byte_FFC2FC bit5 = 0 ; tmpdst = $FFFD (injured, period)
f == 3                     -> game
else: bit5 = 0 ; tmpdst = $FFFD ; if a2.$74 bit1 (chkFgtBit1, the INJURED): game
game: byte_FFC2FC bit5 = 1 ; tmpdst = $FFFC (injured, game)
pop d0 ; rts
out: a0 = injured player's team struct, d1 = pnum*2, d0 preserved
```
- So the patch's `move.w #$112C,$66(a0,d1.w)` overwrites **the injured player's tmpdst** (team +$66 + 2*pnum), replacing the $FFFD/$FFFC just written. $112C = bit12 ($1000, "not counted against strength / Injury G") | $12C (300 s). Section 1.7 shows how InProgress turns it into a coincidental major that expires to $1000 (out for the game). Until the presentation, tmpdst > 0 already makes him "unavailable" for the line logic, and he is still on the ice.
- With a2 = a3 (FightFall), the period/game choice uses the victim's own $74. The choice still sets byte_FFC2FC bit5, which the message uses. The patch's "the game" overprint (section 2) makes the final text "Out for the game" either way.

InjCntDown ($FFC3EC, word):
- Set to 4 by FallDown (L49472). The patch sets 3.
- `loc_79EA` (L29958) runs in the once-per-24-vblank block of periodiceevents. That block is skipped in horizontal mode and runs whether or not the clock runs. It does `InjCntDown -= 1`, and when the result is exactly 0 it calls `loc_1871C` (L55851). Below 0 it keeps counting down without effect.
- With 3, the message appears 49-72 vblanks after FightFall, before the 180-vblank Pencntdwn expires.

Injury message `loc_1871C` (overlay map 0, tile coordinates, text attribute $8000):
```
Framer 18x5 at (11,3)
"Injury to:" at (12,4)
byte_FFC2FC bit5 ? "Out for game" : "Out for period"  at (12,6)
name of TempPlOffset (sub_18AC6) at (12,5)
if puck pflags2 bit0: "the game" at (20,6)          ; -> "Out for the game"
```

Port `checking.gd set_injury_type` matches the flags, crowd, sfx $D, scroll lock, TempPlOffset and the period/game decision. It differs: it writes `TeamStats.player_status[pn]` (an array nothing reads) instead of `tmpdst[pn]`, and it does not return the team struct (section 13).

---

## 6. doinput around $B240-$B270 and the fightinput registers

Retail (L35982-36010):
```
loc_B240: restore d0-d2/a0/a3 (saved around the one-timer check)
if a3.pflags3 bit3 (one-timer) == 0 and a3.pflags bit5 (anim lock): goto loc_B81A (locked: B = change player)
$B258: if a3.pflags2 bit0: goto fightinput ($B8F0 = rts -> returns to updateplayers)
$B262: if puckc == a3.SCnum: goto loc_B72E (carrier input)
       if goalie: goto loc_B28C
       if one-timer bit: goto loc_B28C
       if A new press (d1 bit6): goto holdplayer
loc_B28C: auto-goalie / B (change player, goalie hold) / C / stick skating (input_linechanges.md steps 13-17)
```
When fightinput is entered (doinput called from updateplayers L35586-35653 for c1..c4playernum, then the object's assignment runs in the same pass):
- **d0** = ReadJoy direction in bits 0-3: 0 up, 1 up-right, 2 right, 3 down-right, 4 down, 5 down-left, 6 left, 7 up-left, **8 = none** (jdtab L44581). Bits 4-7 hold the held buttons. In horizontal mode, doinput already rotated a real direction by +2 and masked it to 0-7 (L35944-35950). `btst #3,d0` set means no direction.
- **d1** = newly pressed buttons: bit4 **B**, bit5 **C**, bit6 **A**, bit7 Start. If B and C are pressed in the same frame, B's bit is cleared and pflags3 bit6 is set (L35888-35894).
- **d2** = changed buttons. B's change bit may have been cleared by the B-release logic.
- **d3** = held buttons.
- **d4** = 0 for pad 1 (and pad 3 via swap), 2 for pad 2 (and pad 4).
- d6 = SCnum, d7 = elapsed vblanks, a3 = player.
- Paths that run before the fight branch and can take the frame from a fighter: Start (pause), faceoffinput, lineinput (pflags2 bit3), not joypad-controlled (rts), and the passer's one-timer C press (when lastplayer == a3, passplayer >= 0 and no one-timer is pending, C makes the receiver one-time and returns).
- Port `input_logic.gd doinput`: its local `d0/d1/d2/d3` equal the retail registers at that point. `if a3.fighting(): return` sits at the retail branch position, so the patch's `fightinput(a3, d0, d1, d7)` belongs there. PadState bit constants match (B=$10, C=$20, A=$40).
- setd0player ($15322, the `_setd0player` tail of puckstick, L50706): if no pad already controls SCnum d0, the pad of that player's team switches to him (setc1player/setc2player). The patch calls it for each fighter, so a human team's pad takes over its fighter.

---

## 7. playeracc, getpde, randomd0, sfx

playeracc (L43705, $10BC2). In: d2 = direction 0-7, a3, d7.
```
acc = dirtab[d2] ; drop an axis that pushes into the last board normal ($4E/$50)
k = (64 - wgt/4 + agl (+2 crowd boost) [+agl+$10 goalie]) / 2 ; acc = acc*k >>5 * d7
[goalie && joypad && puckc == self: acc /= 2]
v' = vel + acc
max2 = MaxSpeed[energy-scaled speed] (getpde; $1000 if byte_FFC2FC bit4)
if a3.pflags2 bit6: max2 >>= 3                    ; L43811-43813 fight injury: top speed / sqrt(8)
[goalie && puckc == self: max2 >>= 1]
if |v'|^2 <= max2: vel = v'
energy drain when OptLine == 0 and (HV & $7F) == 0
```
- playeracc **never changes the SPA**. Animation choice is done by doplayeracc (L43331): forward skating = $5D0, **$11E6 if pflags2 bit6** (L43681-43685), $53E if puck carrier, $A92 backwards, and only when pflags2 bit1 (anim in progress) is clear. The patch's fightinput calls playeracc directly, so a fighter keeps his fight frame while moving.
- Clobbers d0-d3, a0, a2 (getpde loads a2 = team struct), and the TempRawSpd/TempEnergySpd/TempMaxSpd globals.
- pflags2 bit6: set only by the patch. Cleared by resetplstuff (every faceoff, `clr.b $63`) and setplayer (L51558).

getpde (L51207): `a2 = team struct (by $62 bit6); d1 = sext(pnum)*2; d0 = team.energy[pnum]` (word at team+$32+2*pnum). Range 0..$1000: $1000 is rested, and setpde clamps negatives to 0. It does not apply the auto-lines $1000 override. Energy only drains when OptLine == 0.

randomd0 (L44190): `RNGseed = RNGseed * $BB40E62D + 1` (32-bit), then returns `d0.w = (((RNGseed >> 8) & $FFFF) * n) >> 16`, uniform in **0..n-1** for unsigned n. It preserves d1/d2. The high word of d0 is garbage.

sfx (L44279): one word on the stack, popped by the callee. Negative ids are ignored. Sets `lastsfx`, then `p_initfx` (ids > $7A ignored, ids >= $30 stop other effects first). Ids the patch uses (sequence table $2C648):

| id | retail callers | sequence | note |
|---|---|---|---|
| 9 | none | instrument $67, note $3C, 30 ticks | same instrument as body checks $1C-$1F, so a punch thud |
| $A | none | instrument $67, note $41, 30 ticks | punch thud, higher note |
| $B | none (as sfx) | instrument $6D, note $43, 240 ticks | not the '94 crowd cheer, which is `song($B)` |
| $C | none (as sfx) | instrument $6B, note $41, 90 ticks | not the '94 crowd boo, which is `song($C)` |
| $D | setInjuryType | instrument $6C, note $46 | injury |

The patch's FightFall plays **sfx** $B/$C (the '93 numbering, where those were crowd cheer/boo). Retail FallDown plays `song($B/$C)` for the same event. A faithful port of the patched ROM plays sfx $B/$C.

---

## 8. ChkCnt ($FFC46E) and team ChksFor (+$11C)

- Writers: StartGame `clr.w` (L29781, once per game; not per period), AddChktoPlayerStats in FallDown (L49217 `+1`, L49220 `+2` more when the hitter's `$74 == 0`), Begin RAM clear. There are no retail readers. The listing's "ChkCnt" at L47469/L55774/L56000 is `ScoreSum - 6` used as a record base ($FFC46E + ScoreSumbytes).
- ChksFor = team struct +$11C + pnum (byte; $FFC7EA home, $FFCB4E away = HmChksFor + $364). Its only writer is `addq.b #1,$11C(a0)` (L49216), for the **hitter** (a3) of a FallDown that passed the gate and was not a stagger, and only when the hitter is not a goalie. Bytes wrap at 256. Cleared with the team stats at game start.
- Port: `checking.gd _add_check_stats` (L313-320) does `checks += 1`, `player_checks[pnum] += 1`, `chk_cnt += 1 (+2 when hf == 0)`, and `start_game` clears `chk_cnt`. This matches.

---

## 9. HUD pieces: lcfound2, box, Framer, print; banner layout

The game screen is H32 (256x224, 32x28 tiles; setvram L44805, disflags bit1). Text goes to map 0 = plane A at VRAM $E000, 64 tiles per row (setupice L53031). setupice fills it with $7FF (blank). All coordinates below are tiles on that plane.

- print string format (L45521): word = byte length including the word. A negative byte `c` is a command `n = -c`: `printa = (n<<9) & $F800`, `printm = ((n&3)<<2)-4`, followed by x and y bytes. A zero byte is skipped. '@' is blank $7FF, '^' skips a column. `$BF` → printa $8000 (high priority, palette 0), map 0. `$FF` → printa 0, map 0.
- eraser (L45234): fills d0 x d1 tiles from (printx,printy) with the word d2. It ignores printa, and printy wraps &$1F.
- Framer (L45261): border box d0 x d1 from (printx,printy) using framermap + printa + framercset. Top row, d1-2 middle rows, bottom row.
- lcfound2 ($BB36, L36813): returns at once in horizontal mode. Otherwise it erases team a2's line-change menu (setlccords: x = $16, y = 0 or $16 by team and gmdir; 9 wide, 6 or 7 rows), clears sflags3 bit0 if the menu was at the bottom, and redraws the score box (PrintScores1: Framer 9x5 at (0,23)).
- box ($18A56, L56167): printz `$FF,11,2`, then eraser 19x8 of $7FF, which blanks cols 11-29 and rows 2-9 (the area of the injury box).

Patch banner, as the retail routines render it (drawn once):
```
lcfound2(home); lcfound2(away); box
L = fighter of the newest PenBuf entry (orig a2), P = second newest (orig a3)
string(s) = JNo (2 chars, tens digit 0 -> space) + " " + name + " " + team abbreviation
len(s) = its length word (chars + 2, rounded up to even); W = max(len(L), len(P))
printz $BF,15,1 ; printx = 15 - W/2 ; Framer W x 5            -> box cols 15-W/2 .. 14+W/2, rows 1..5
row for L = 2 if Fgt(L) > Fgt(P) (signed $74 bytes) else 4; P gets the other row (ties: P on row 2)
each name printed at x = 16 - len/2 on its row, attribute $8000
"vs" at (15,3)
```
- Trigger: the fighter with facedir == 2 (the left one) sets temp4 = 90 when assfight starts. The other gets $FFFF, which effectively never triggers. The banner is drawn when temp4 borrows, about 90 vblanks after his assfight first runs. This happens even if the fight has already ended, as long as Pencntdwn is still >= 0.
- `clear` (injury path only): printz `$BF,0,1`, then eraser 40x5 of $7FF. That blanks rows 1-5, cols 0-39 (cols 32-39 are off screen), and erases the banner. Otherwise the banner stays until the screen is rebuilt for the horizontal presentation.

---

## 10. SetSPA, the anim lock and "anim in progress"

- SetSPA (L43319): `if d1 == SPA: rts` (no restart). Otherwise `SPAnum = 0; SPA = d1; SPAcnt = $FFxx`. It does **not** touch `$62 bit5` (lock) or `$63 bit1` (AIP). Callers set those themselves (burst, holdplayer, FallDown `_2`, dostop's `bset #1,$63`). The patch never sets the lock and always sets AIP itself.
- updateanim (L35703), every frame, before the input and the assignment:
  - `SPA == 0`: clear the lock and AIP, rts. The frame stays where it was.
  - Otherwise it shows `d2 = frame at SPAnum`, which is read **before** the step, so frame changes appear one frame late. `SPAcnt -= d7`; when it goes negative, `SPAnum += 4`. If the previous entry's time was negative (it was the last entry): `SPAnum = 0`, clear the lock, AIP and pflags3 bit5 (L35741-35748), and if the SPA's attribute bit0 (loop) is clear, `SPA = 0`. A looping SPA clears the lock and AIP on every wrap.
  - Frame writes are rate-limited by the `$65` glitch counter (4 vblanks).
- All nine fight SPAs in the patched SPAList are non-looping. So AIP drops at the end of each move. After SPAfight's last frame the SPA becomes 0 and the stance frame (850/855) stays.
- `8(a3)` (old frame), which chkhit compares with `6(a3)`, is written only by `addframe2` when the object is actually drawn in setvideo. That happens after updateplayers. So chkhit sees each new frame once, in the same pass in which updateanim set it. An object that is not drawn (off screen, Z < 0) keeps re-triggering.

---

## 11. PerTimeTotal ($FFC46C)

Written only by ResetClock (L29828): the period length in game seconds from `_timetab[OptPerLen]`. Regular-season OT (gsp >= 3, OptPlayMode 0) is $258.

| OptPerLen | PerTimeTotal | chkcnttab index (>= $4B0 → 6; > $1A4 → 4; > $78 → 2; else 0) | chkftab index (same, but the last case uses **2**) |
|---|---|---|---|
| 0 (5:00) | $12C = 300 | 2 → 30 | 2 → 8 |
| 1 (10:00) | $258 = 600 | 4 → 40 | 4 → 16 |
| 2 (20:00) | $4B0 = 1200 | 6 → 40 | 6 → 16 |
| 3 (0:30) | $1E = 30 | 0 → 20 | 2 → 8 (`moveq #2,d0`) |
| OT (regular season) | 600 | 4 | 4 (fights are blocked in OT by `gsp > 2`) |

Other readers: puckfaceoff music cue (L41677), checkgoal (L49995), PenSum time (sub_14A94).

---

## 12. asstab $14/$15 and assnothing

- `asstab[$14]` = $CBE0, `asstab[$15]` = $CBE2. Both are bare `rts`. $CBE2 is also the early-exit target of assnothing, assstanley and others, so the patch repoints the table entries and leaves the code alone. The port's `asstab` has no entry for either id, which also does nothing.
- assnothing ($CBE4, L38275):
```
if a3.pflags bit5 (lock) or bit3 (joypad): rts
d0 = 8 ; doplayeracc        ; goalie -> goalieacc; skater: no direction -> if !AIP: SetSPA($50C glide / $A60 back)
```
Velocity then decays through the generic drag. In the patch, assfight jumps here whenever Pencntdwn < 0. A CPU fighter glides without breaking a running fight animation, because AIP blocks the glide SPA. A pad fighter does nothing.

---

## 13. Port gaps (hooks the patch needs that the current port lacks or gets wrong)

1. **`Checking.set_injury_type` writes `TeamStats.player_status[pn]` instead of `tmpdst[pn]`.** Retail writes $FFFD/$FFFC to tmpdst ($66 + 2*pnum). The line logic reads tmpdst -3/-4, so retail injuries do not take players out in the port either. The patch's `$112C` overwrite must go to `tmpdst[pnum]` of the victim's team. `set_injury_type` returns `pn*2` but not the team (a0). The new `fight_logic.gd injure()` (written in parallel, not reviewed in full) calls `set_injury_type(loser, loser)` and never writes $112C. Without that, the injured fighter is assessed as a plain coincidental major and returns at the end of it.
2. No old-frame field (`8(a3)`, updated only when drawn) on `SimObject` for chkhit's once-per-frame test (section 10).
3. No glovecords state or glove sprite object: no clears at puckfaceoff2/puckpenshot/highlight setup, no replay record, no drawing behind all sort objects and the stars (section 3).
4. The injury message (`HockeyWorld.injury_message` signal) is not rendered, including the "the game" overprint when the puck's fight bit is set. There is also no "Injury G" / " C" status text for tmpdst bit12/bit14 (L32100, strings L32115: Ice, Bench, Injury P, Injury G, time + blank, time + " C").
5. There is no overlay text layer for the banner (Framer box, names, "vs"), for `clear`, or for `box`/`lcfound2` erasing (section 9).
6. Collisions: the `checkfight` call belongs in `collisions.gd` checkcx right after `checking.checkcheck(...)` and before the `collflag` test. The patch sets collflag, which skips the momentum exchange.
7. asstab $14/$15 registration, and the doinput hook at `input_logic.gd` `if a3.fighting(): return`.
8. SfxBank has no names or files for sfx 9, $A, $B, $C. The patch uses sfx (not song) $B/$C.
9. Minor retail deviations outside fights: when PenSum is full, retail overwrites the last record (the port stops appending); the box-list overflow rule (scan 25 bytes for the terminator) is not mirrored.

Already matching (no work): the penalty pipeline (1.10), checkwindow/scroll lock, skateto's fight-centre facing, Endfaceoff clearing the puck bit, resetplstuff leaving the puck alone, the playeracc pflags2 bit6 speed cut and $11E6 skate animation, setplayer clearing bit6, ChkCnt/ChksFor counting, InjCntDown countdown, `per_time_total`, puckunflip.

---

## 14. UNRESOLVED

- The actual sounds of sfx 9/$A/$B/$C. Only the sequence headers (instrument, note, duration) were decoded from the table at $2C648. Instruments $67/$6B/$6D were not traced to patches.
- Plane A's scroll offset during play was not traced (`updatescroll`). The HUD coordinates above assume plane A is screen-fixed, as the score box at (0,23) and ref box at (3,2) imply.
- Whether the gloves object is meaningful in horizontal mode (find3d's rotated mapping was not checked for ffo objects).
