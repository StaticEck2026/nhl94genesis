# Game rules: clock, periods, stoppages, penalties, power play (NHL '94 Genesis)

Source: `lst/nhl94.bin.lst`. Lnnnnn are listing line numbers. Values are hex (`$`) unless marked decimal.
RAM addresses marked "confirmed" were read from instruction bytes in `lst/nhl94.bin`. All other addresses are unknown and the routines refer to the variables by name.
`btst/bset/bclr #n,(var).w` on memory is a **byte** operation on the first byte of `var` (big-endian high byte of a word). So "gmode bit 0" means bit 0 of the byte at `gmode`. On a data register the bit number refers to the full word (`btst #$E,d2` is bit 14 of the word).
`st (x).w` sets only the first byte to $FF, so a word becomes $FFxx (negative). `rtss2`, `rtss8` are plain `rts`.

---

## 0. Overview

### 0.1 Time units (exact)

| Unit | Definition |
|---|---|
| vblank (jiffy) | One VBlank interrupt, 60 Hz on NTSC. `vcount` += 1 in the VBlank handler. |
| d7 | Vblanks since the previous `DoGameFrame`: `d7 = vcount - oldvcount`, always >= 1. Every countdown below that says "-= d7" counts vblanks. |
| game second (clock tick) | `gameclock` (word, seconds) has a 16-bit fraction word right after it (`word_FFC46A`). Each vblank, if the clock may run, the VBlank handler does `frac -= $AAA` (2730 decimal). When that subtraction borrows (unsigned frac < $AAA before it), `gameclock -= 1`. So 1 game second = 65536/2730 = 24.0059 vblanks. In practice the gap is 24 vblanks, and a 25-vblank gap comes about every 170 ticks. A 5:00 period lasts 300 ticks = about 7202 vblanks = about 120.0 s of real time at 60 Hz. |
| jps = $18 = 24 | "Jiffies per second". The other once-per-game-second timers (`Penaltytimer`, `lldisp`) are plain vblank countdowns reloaded with +24. They are not tied to the clock fraction, so they drift slowly (24 against 24.0059) relative to `gameclock`. |
| Ref-animation tick | One ref script step lasts `(low byte) * 8` vblanks (`RefCnt`). |
| Penalty call delay | `Pencntdwn = PenaltyList.byte0 * 32` vblanks. |

`gameclock` holds the seconds left in the period. `PushTime` (L45632) prints it as `M:SS` (d0/10 remainder = seconds digit, then /6 remainder = tens-of-seconds digit, then the quotient is minutes). The fraction word is never reset by `ResetClock`. Only the seconds word is written, so the first tick of a period comes after between 1 and 24 vblanks.

### 0.2 Frame structure

```
GameLoop (L29902): forever { DoGameFrame; demoread; if sflags.pause: PauseMode }
DoGameFrame (L29914): wait until vcount != oldvcount; d7 = vcount-oldvcount; oldvcount = vcount
    periodiceevents (L29940)
        PenaltyManager (L46005): updatepentime -> checkfornewpen -> chkprogress -> UpdatePA
        updatecrowdf, sub_FE2C8 (overlay anim driver), updatesound
        clockcont (L30074)            ; detects clock == 0 while running -> end of period/game
        if not horizontal mode: every 24 vblanks (lldisp):
            ChkGoalies, UpdateCwdExcite, sub_7A34 (3rd-period music), bench energy recovery,
            InjCntDown, updatepwrplay
    updateplayers                      ; all object assignments (AI/input/puck), collisions, checkgoal
    goal-song delay (word_FFDECC), setSlotBit, checkwindow, updatereplay, setvideo
VBlank handler (loc_15D9A, L51766): decrements gameclock (or the shot clock word_FFD454), vcount += 1
```

### 0.3 Game state machine

The game has no single state variable. The state comes from `gsp` (period), the `gmode` bits, the puck's current assignment and `sflags` bit 7 (horizontal penalty screen).

| gsp | Meaning |
|---|---|
| 0, 1, 2 | Regulation periods 1-3 |
| 3 | Overtime. Regular season (`OptPlayMode == 0`): one 10:00 ($258) OT, sudden death, and a tie stands. Playoffs (`OptPlayMode != 0`): repeated OT periods of normal length until someone scores. |
| 4 | Game over |

`gmode` bits (byte): 0 `gmclock` (play stopped and clock stopped), 1 `gmdir` (0 = home attacks +Y/top; toggled every period), 2 `gmpen` (a stoppage is being processed), 3 `gmpendel` (delayed penalty pending), 4 `gmhl` (highlight/replay), 5 `gmoffs` (offsides rule on), 6 (94-only) game-over flag set by `clockcont _eog`.

```
StartGame --jmp--> PeriodOver.loc_17278 (ResetClock, UpdateScores, Intermission[pre-game menu])
   --> StartPer: setupice, ResetClock (gmclock=1), puck assignment = puckfaceoff ($1B) [shootout: $1E]
   --> GameLoop
FACEOFF SETUP: puckfaceoff (L41627, first call) runs the end checks:
        gameclock==0 or gmode.6 -> PeriodOver
        gsp==3 and HmGoals!=AwGoals -> clockcont.loc_7B5C (OT winner: celebrate, EOG)
        gmpendel -> Stop4Pen
      then puckfaceoff2 ($1C): ResetBench, place puck at (fox,foy), drop
      Endfaceoff (L42445): bclr gmclock  ==> PLAY
PLAY (gmclock=0): clock ticks; AddPenalty accepted; delayed penalty (gmpendel)
      infraction/goal/icing/offside/out-of-play/goalie-freeze/clock==0  -> PenBuf entry
      checkfornewpen -> Stop4Pen: gmclock=1, gmpen=1, whistle, faceoff spot ==> STOPPAGE
STOPPAGE (gmpen=1, Pencntdwn>=0): play animation continues, clock stopped, Pencntdwn -= d7
      Pencntdwn<0: if any real penalty in PenBuf -> horizontal penalty screen (SetHor)
PRESENTATION (Pencntdwn<0): InProgress, one PenBuf entry at a time, LIFO, each waits for the
      ref animation to end (RefCnt<0 && RefStep<0) and the penalized player to leave the ice
      PenBuf empty -> recount tmap, bclr gmpen, puck assignment = puckfaceoff (or $1E penalty shot)
      ==> FACEOFF SETUP
END OF PERIOD: clock hits 0 while running -> clockcont: horn, AddPenalty2(PenEOP or PenEOG)
      -> normal stoppage path -> puckfaceoff sees gameclock==0/gmode.6 -> PeriodOver
PeriodOver: gsp++, gmdir^=1, OT/game-over decision, Intermission, StartPer or GameOver
GameOver: playoff bookkeeping, PlayoffScreen, Opening2 (back to menus / next game)
```

Shootout mode (`OptPlayMode == 4`, `word_FFC2FA` bit 0) and in-game penalty shots (`BA_PS_flags` bit 3) use the assignment `$1E` (puckshootout) and a separate 25-second attempt clock `word_FFD454` (see the VBlank handler). They are touched here only where they cross these routines.

### 0.4 Penalty lifecycle (summary)

1. **Infraction** (checking/hold/hook/trip/interference code, out of scope) calls `AddPenalty(d0=id, a3=offender)`. Non-penalty stoppages call `AddPenalty2` directly. An entry `(id<<8)|SCnum` goes into `PenBuf` (32 slots). For a real penalty (minutes byte > 0), `DelayedPen` bit 1 (home) or bit 2 (away) is set and the offender gets pflags2 bit 4 ("penalized", which blocks a second penalty and line changes).
2. **Call / delayed call**: `checkfornewpen` runs every frame in vertical mode. An entry with minutes == 0 (a stoppage) is called at once. A real penalty is called at once only if the puck carrier is on the offender's team. Otherwise (opponent has the puck, or the puck is loose) it is **delayed**: `gmpendel` is set, the "Penalty" ref animation shows, and `ChkGoalies` pulls the goalie of the team with the puck at the next per-second tick. "Called" = `Stop4Pen` (whistle, clock stopped, faceoff spot). Every entry in `PenBuf` is then marked called (bit 7 of the SCnum byte), and `Pencntdwn = max(byte0*32)`.
3. **Assessment** (`InProgress`, on the horizontal penalty screen): processed newest-first. Each one adds stats and a `PenSum` record, sets the player's `tmpdst` to `minutes*60 | $2000`, flags coincidental 5-minute majors (bit 14 on both players), appends the player to the team's box list, gives him `asspenalty`, and plays the ref animation. After the buffer is empty, `sub_123DE` recounts `tmap` (players on ice) = 6 - min(2, #non-coincidental penalized players).
4. **Serving**: `updatepentime`, every 24 vblanks while the clock runs, decrements the first **two** non-coincidental box-list entries of each team, plus every coincidental entry. When a coincidental major expires, that team's pass for that second stops there. Beeps (sfx 1) in the last 5 s. At 0 the player is removed from the list, re-enters (`sub_129D2`: tmap+1, put on ice with `assepen`) and sfx 2 plays.
5. **Power-play goal** (`sub_1284A`): if the scoring team had more players, the first non-coincidental player in the scored-on team's box list is released (tmpdst=0, tmap+1). If the scored-on team was at full strength (tmap == 6), the whole `PenBuf` is cleared, which cancels delayed penalties.
6. **Power-play state**: `updatepwrplay` (per game second) compares `tmap` of the two teams. If they differ, `sflags2` bit 5 (PP on) and bit 6 (0 = home on PP, 1 = away on PP) are set, and the PP team's `tmPwrPlays` is incremented at the start of each PP. If they are equal, the PP flag is cleared. `updatePPTeamTime` adds 1 to the PP team's PP-seconds stat on every penalty-timer second.

### 0.5 Globals used

| Name | Address | Type | Meaning |
|---|---|---|---|
| gameclock | $FFC468 (confirmed) | word | seconds left in the period |
| word_FFC46A | $FFC46A (confirmed) | word | clock fraction, -$AAA per vblank |
| gsp | $FFC466 (confirmed) | word | period 0..4 |
| PerTimeTotal | ? | word | period length in seconds (set by ResetClock) |
| word_FFB048 | ? | word | 3rd-period music trigger time (set by ResetClock, used by sub_7A34) |
| OptPerlen | ? | word | period-length option 0..3 (index into `_timetab`) |
| OptPen | ? | word | 0 = penalties off; 1 = on with offsides (sets gmoffs); any other value = on, offsides not called |
| OptLine | ? | word | 0 = line changes on |
| OptPlayMode | ? | word | 0 regular season, 1 continue playoffs, 2 new playoffs (best of 7), 3 new playoffs (single game), 4 shootout |
| gamelevel, bosgames, gamenum | ? | word | playoff round 0-3, game of series 0-6 or 7 = not best-of-7, index of the current game in gsstruct |
| gmode | $FFC2EA (confirmed) | byte | see 0.3 |
| sflags | ? | byte | bit0 pause, bit6 scroll lock (freezewindow), bit7 horizontal (penalty screen) mode |
| sflags2 | ? | byte | bit0 faceoff in progress, bit1 ref refresh, bit2 disable replay recording, bit4 shot taken, bit5 power play on, bit6 PP team (0 home, 1 away) |
| sflags3 | $FFC2F0 (confirmed) | byte | bit3 intermission skipped, bit4 set at Endfaceoff, bit6 "penalty-timer second" (set only on the tick frame), bit7 mid-period music cue armed (periods 1-2) |
| word_FFC2FA | ? | byte | bit0 shootout mode, bit1 attempt clock running (shootout/penalty shot), bit2 clock runs even with gmclock set (penalty shot), bit3 shootout ref-speed flag, bit4 breakaway goal, bit7 freezes the attempt clock |
| PenBuf | $FFC3A4 (confirmed) | 33 words | penalty/stoppage queue, 32 usable + terminator |
| Pencntdwn | $FFC3E6 (confirmed) | word | vblanks until presentation; negative = presentation running |
| Penaltytimer | $FFC3E8 (confirmed) | word | 24-vblank countdown for box time |
| PBnum | $FFC3EA | byte (high byte of word) | $HV: H = home players in box, V = away (written by ResetBench) |
| RefCnt / RefStep / RefPen | $FFC3F0 (confirmed) / $FFC3F2 / $FFC3F4 | word | ref animation countdown (vblanks), script index (byte offset; negative = last step running/done), current PenaltyList id |
| word_FFC3EE | ? | word | ref-message blink countdown (display) |
| RefRamMap | $FFC3F6 (confirmed) | 56 words | ref window tiles |
| DelayedPen | ? | byte | bit0 = PP goal released a player (display), bit1 = home has a penalty pending, bit2 = away has a penalty pending. Cleared at puckfaceoff2. |
| BA_PS_flags | ? | byte | bit2 penalty-shot/BA sequence active, bit3 penalty shot awarded, bit4 attempt over, bit5, bit6 attempt-over penalty queued, bit7 |
| PenSum / PenSumLength | ? | 4-byte records / word | penalty summary (max $EC offset = 60 records) |
| ScoreSum / ScoreSumbytes | $FFC474 / $FFC472 (confirmed) | 6-byte records / word | scoring summary (max $168 = 60 records) |
| lldisp | $FFB046 (confirmed) | word | 24-vblank countdown for the once-per-second block |
| crowdlevel, crowdcnt, crowdstep, crowdframe | ? | word | crowd noise and animation |
| CwdExciteLvl, MaxCwdExciteLvl, SumCwdExciteLvl (long), NumCwdExciteLvl, CurCrowdMeter | ? | | crowd excitement stats |
| fox, foy | ? | word | next faceoff spot (pixels) |
| puckc | puck struct $60 | word | puck carrier SCnum or negative |
| InjCntDown | ? | word | per-second countdown to the injury message |
| gsstruct | $FFCE66 (confirmed) | 8 x 16 bytes | other games / playoff series |
| HmShots / AwShots | $FFC6CE / $FFCA32 (confirmed) | $364 bytes each | team structs (below) |
| HmGoals / AwGoals | $FFC6DA / $FFCA3E | word | = team struct +$C |

### 0.6 Team struct (94 layout, size $364; a2/a1/a3 = team pointers)

| Off | Meaning (as used in scope) |
|---|---|
| $000 | shots on goal |
| $002 | PP goals (incremented by `sub_1284A` when a PP goal releases a player) |
| $004 | power plays (opportunities) |
| $006 | penalties (count) |
| $008 | penalty minutes |
| $00A | attack time of possession (game seconds) |
| $00C | goals (score) = HmGoals/AwGoals |
| $014 | passes completed |
| $016 | tmline: current line (0-2 regular, 3-4 PP lines, 5-6 PK lines) |
| $018,$01A,$01C | scorer / assist pnums for checkgoal (out of scope) |
| $01E | long: team data pointer |
| $022 | word: address of the team's first SortCords object (tmsort) |
| $024 | tmap: players on ice incl. goalie, 4..6 |
| $026 | goalie: low byte = goalie pnum. High byte $FF = goalie pulled (`st`). Word $FFFF = no goalie. |
| $032 + 2*i | energy of roster slot i (i = 0..25), max $1000 |
| $066 + 2*i | tmpdst of roster slot i (see below) |
| $09A | box list: bytes `pnum*2` in assessment order, terminated by a negative byte |
| $0B4 + pnum | per-player goals (goalie: goals against), byte |
| $0CE + pnum | per-player assists, byte |
| $0E8 + pnum | per-player shots (goalie: shots against), byte |
| $102 + pnum | per-player penalty minutes, byte |
| $342 + 2*gsp | goals per period |
| $34A + 2*gsp | shots per period |
| $352 | PP time (game seconds) |
| $354 | PP shots |
| $356 | PP goals (stat used by checkgoal) |
| $35A | breakaway goals |
| $360 | penalty-shot/shootout attempts |
| $362 | shorthanded goals |

**tmpdst encoding (word):**
- $FFFF (-1) on ice, $FFFE (-2) on bench, $FFFD (-3) injured for the period, $FFFC (-4) injured for the game.
- >= 0: in the penalty box (or just released).
  - bits 0-11: seconds left (ResetBench masks bits 0-10, $7FF; the display masks $FFF).
  - bit 12 ($1000): "not counted against strength". The status display shows it as "Injury G" (L32085: `btst #$C,d0` -> status 3). See quirk Q7.
  - bit 13 ($2000): assessed during the current stoppage (cleared by `sub_123DE`).
  - bit 14 ($4000): coincidental major. Not counted against strength. Always ticks.
  - 0 means served: removed from the box list. If `sub_129D2` did not return him to the ice, the next `ResetBench` sets him to -2.

**PenBuf entry (word):** high byte = PenaltyList id (even, $02..$3C). Low byte = SCnum of the a3 object passed in (low byte of SCstruct $52). Bit 7 of the low byte = "called" (set by checkfornewpen, cleared by InProgress). 0 = empty slot.

**PenSum record (4 bytes):** word time = `(gsp<<14) + (PerTimeTotal - gameclock)` (sub_14A94); byte = id | $80 if the offender is on the away team; byte = offender pnum.

**ScoreSum record (6 bytes, written by checkgoal, read by ChkShotStat):** word time; byte = (2 + scorerTeam.tmap - otherTeam.tmap) | $80 if away; byte scorer pnum; byte assist1; byte assist2 (initialized $FFFF).

**gsstruct record (16 bytes):** +0 team1, +2 team2, +4 gspotwins, +6 gspobwins, +8 gsper (period count), +$A score1, +$C score2, +$E flags (bit0 teams flipped, bit1 close-game/"hilite" flag, bit2 series over).

---

## 1. Tables (full dumps)

### 1.1 `_timetab` (L29848), indexed by OptPerlen

| OptPerlen | value | period length |
|---|---|---|
| 0 | $012C | 300 s = 5:00 |
| 1 | $0258 | 600 s = 10:00 |
| 2 | $04B0 | 1200 s = 20:00 |
| 3 | $001E | 30 s = 0:30 (debug: forced when joypad 1 held byte == $E0 at StartGame) |

Regular-season OT length is the constant $258 = 600 s (10:00) for every option (ResetClock).

### 1.2 `PenaltyList` (L56708, ROM $18E0C)

The first part is 31 words, indexed by id (byte offset = id). Each word is an offset from `PenaltyList` to a variable-length record:

```
rec+0  byte  delay   : Pencntdwn candidate = delay*32 vblanks (checkfornewpen)
rec+1  byte  minutes : 0 = stoppage (not a player penalty); 2 / 5 = minutes; $FF (negative) = penalty-shot
                       variant (never assessed as a penalty)
rec+2  word  off     : ref script address = rec+2+off. Text = the bytes rec+4 .. rec+2+off-1 (off-2 chars;
                       off==2 means no text). The text may end without a NUL, because the first byte of the
                       script word ($00) acts as the terminator.
rec+2+off  words     : ref animation script: each word = (refFrame<<8) | dur. RefCnt = dur*8 vblanks.
                       A negative word is the last step: its value is negated first.
                       refFrame $40 = clear the ref window.
```

Full dump (script step = `frame/vblanks`, `*` = last step; "total" = sum of steps in vblanks):

| id | rec off | delay (vblanks) | min | text | ref script | total | raised by / meaning |
|---|---|---|---|---|---|---|---|
| $00 | $000 | 0 (0) | 0 | (reads the offset table itself) | junk | - | unused |
| $02 | $03E | 1 (32) | 0 | "Period Over" | 05/128* | 128 | PenEOP, clockcont |
| $04 | $050 | 1 (32) | 0 | "Game Over" | 05/128 40/768* | 896 | PenEOG, clockcont |
| $06 | $094 | 1 (32) | 0 | "Face Off" | 05/80* | 80 | PenOOP: puck out of play (L50134), puck stuck still too long (pucknorm L42579) |
| $08 | $094 | 1 (32) | 0 | "Face Off" | 05/80* | 80 | goalie covers puck / goalie out of range (L38983, L39048, L39194, L50087) |
| $0A | $0C2 | 0 (0) | 0 | (none) | 05/80* | 80 | PenWhistle: the ref anim of every Stop4Pen. Also queued by sub_F2F4 when a penalty-shot/shootout attempt ends. |
| $0C | $072 | 1 (32) | 0 | "Icing" | 00/16 01/8 02/48* | 72 | icing (L42765), always allowed |
| $0E | $062 | 1 (32) | 0 | (none) | 05/80 40/192* | 272 | PenGoal (checkgoal L49959) |
| $10 | $082 | 1 (32) | 0 | "Off-side" | 00/16 03/8 04/120* | 144 | offside (L42708), only if gmoffs |
| $12 | $190 | $0A (320) | 2 | "Roughing" | 00/32 0D/8 0E/8 0D/8 0E/8 0D/8 0E/8 0D/8 0E/8 01/8* | 104 | injury-causing check (L49478, via AddPenalty2) |
| $14 | $06A | 1 (32) | 0 | (none) | 05/128 40/192* | 320 | injury stoppage when the victim is a goalie or penalties are off (L49473-49477) |
| $16 | $0C8 | 4 (128) | 2 | "Charging" | 00/32 01/8 0A/8 0B/8 0A/8 0B/8 0A/8 0B/8 0A/8 0B/8 01/8* | 112 | body check (CCStart, $16 + (HV counter & 2)) |
| $18 | $10C | 4 (128) | 2 | "Slashing" | 00/32 01/8 02/8 03/8 02/8 03/8 02/8 03/8 02/8 03/8 01/8* | 112 | body check (as above) |
| $1A | $1B0 | 4 (128) | 2 | "Roughing" | 00/32 0D/8 0E/8 0D/8 0E/8 0D/8 0E/8 0D/8 0E/8 01/8* | 104 | check that knocks down ($1A + (HV & 2)) |
| $1C | $234 | 4 (128) | 2 | "Cross Check" | 00/32 06/8 0F/8 10/8 0F/8 10/8 0F/8 10/8 0F/8 10/8 01/8* | 112 | (as above) |
| $1E | $1F0 | 4 (128) | 2 | "Hooking" | 00/32 01/8 09/8 08/8 09/8 08/8 09/8 08/8 09/8 08/8 01/8* | 112 | holdcheck (L49089; the listing comment "PenHolding" is wrong) |
| $20 | $150 | 4 (128) | 2 | "Tripping" | 00/32 04/8 05/8 04/8 05/8 04/8 05/8 04/8 05/8 01/8* | 104 | L49144 |
| $22 | $280 | 4 (128) | 2 | "Interference" | 00/32 01/8 0C/48 01/8* | 96 | L48847 |
| $24 | $2B0 | 4 (128) | 2 | "Holding" | 00/32 01/8 07/48 01/8* | 96 | holdcheck when SPA == $CC2 (L49086) |
| $26 | $2C4 | $28 (1280) | 5 | "Fighting" | 00/32 0D/8 0E/8 0D/8 0E/8 0D/8 0E/8 0D/8 0E/8 01/8* | 104 | no caller found |
| $28 | $2E4 | $28 (1280) | 5 | "Fighting *" | (same as $26) | 104 | no caller found |
| $2A | $306 | $28 (1280) | 2 | "Fight Instigator" | (same as $26) | 104 | no caller found |
| $2C | $0B0 | 0 (0) | 0 | "Penalty" | 00/24 03/8 04/120* | 152 | PenDelay: SetPA only (delayed-penalty signal) |
| $2E | $212 | 4 (128) | -1 | "Hooking" | (as $1E) | 112 | penalty-shot variant |
| $30 | $170 | 4 (128) | -1 | "Tripping" | (as $20) | 104 | penalty-shot variant |
| $32 | $0A2 | 0 (0) | 0 | "Face Off" | 05/80* | 80 | no caller found |
| $34 | $298 | 4 (128) | -1 | "Interference" | (as $22) | 96 | penalty-shot variant |
| $36 | $1D0 | 4 (128) | -1 | "Roughing" | (as $1A) | 104 | penalty-shot variant |
| $38 | $0EA | 4 (128) | -1 | "Charging" | (as $16) | 112 | penalty-shot variant |
| $3A | $25A | 4 (128) | -1 | "Cross Check" | (as $1C) | 112 | penalty-shot variant |
| $3C | $12E | 4 (128) | -1 | "Slashing" | (as $18) | 112 | penalty-shot variant |

The listing's comments on the offset table (PenCharging at $0A, PenIcing at $0C, ...) are partly wrong. The text column above is read from the ROM bytes. Code constants agree with the texts: Stop4Pen uses $E = PenGoal, $6 = PenOOP, $C = PenIcing. checkfornewpen uses $2C = PenDelay. clockcont uses 2/4 = EOP/EOG.
SetPA ignores ids >= $2E (no ref animation, no text).
Search for callers of $26/$28/$2A/$32: grep for immediate loads `#$26,d0`, `#$28,d0`, `#$2A,d0` and `#$32,d0` found none in game code. Fighting appears to be unused in '94.

### 1.3 `unk_1913A` (L57492, ROM $1913A): penalty-shot map used by PenShotChk, indexed by id

| id | value | | id | value |
|---|---|---|---|---|
| $00-$12 | $FFFF | | $1C (Cross Check) | $2E ("Hooking", -1) |
| $14 | $38 ("Charging", -1) | | $1E (Hooking) | $30 ("Tripping", -1) |
| $16 (Charging) | $3C ("Slashing", -1) | | $20 (Tripping) | $34 ("Interference", -1) |
| $18 (Slashing) | $36 ("Roughing", -1) | | $22-$2E | $FFFF |
| $1A (Roughing) | $3A ("Cross Check", -1) | | | |

The record texts confirm the map is shifted by one entry: a charging foul on a breakaway becomes the "Slashing" penalty-shot variant, and so on (quirk Q1). The map is only used for the text/RefPen of the variant, and the variant is never assessed. Port it as-is.

### 1.4 `_cd0` crowd animation (L56543, ROM $18CFC), 64 pairs (frame, countMask)

Index = `(min(crowdlevel>>1, $7F) & $60) + crowdstep` (crowdstep 0..$1E, even).

| base | pairs (frame,mask) for crowdstep 0,2,...,$1E |
|---|---|
| $00 | (1,0C)(2,0C)(3,0C)(4,0C)(5,0C)(10,0C)(9,0C)(8,0C)(6,0C)(7,0C)(8,0C)(9,0C)(10,0C)(5,0C)(4,0C)(3,0C) |
| $20 | (1,07)(2,07)(3,07)(4,07)(5,07)(11,07)(12,07)(13,07)(6,07)(7,07)(8,07)(9,07)(10,07)(11,07)(12,07)(13,07) |
| $40 | (14,07)(15,07)(16,07)(17,07)(18,07)(11,07)(12,07)(13,07)(18,07)(17,07)(16,07)(15,07)(14,07)(13,07)(12,07)(11,07) |
| $60 | (14,03)(15,03)(16,03)(17,03)(18,03)(11,03)(12,03)(13,03)(18,03)(17,03)(16,03)(15,03)(14,03)(13,03)(12,03)(11,03) |

(frames are decimal, masks hex)

### 1.5 `sctab` (L47843, ROM $13338): other-game scoring weights, 8 rows x 4 words (weights for 0,1,2,3 goals in a period)

| row | w0 | w1 | w2 | w3 |
|---|---|---|---|---|
| 0 | 43 | 30 | 23 | 4 |
| 1 | 39 | 32 | 24 | 5 |
| 2 | 35 | 33 | 26 | 6 |
| 3 | 30 | 34 | 30 | 6 |
| 4 | 26 | 36 | 30 | 8 |
| 5 | 22 | 37 | 31 | 10 |
| 6 | 19 | 38 | 31 | 12 |
| 7 | 15 | 38 | 32 | 15 |

(decimal)

### 1.6 `priolist` (L57829): positions in order of importance

`0 (G), 1 (LD), 2 (RD), 4 (C), 3 (LW), 5 (RW), 6, $FF`

### 1.7 `_alist` (Setplass, L51542): initial assignment by position

`pos 0 -> $0E assgoaliecpu, 1 -> $02 assdefd, 2 -> $02, 3 -> $03 asswingd, 4 -> $05 asscenterd, 5 -> $03, 6 -> $05, $FF`

### 1.8 `unk_131CC` (L47683): intermission menu pointers (long), index = gsp + (OptPlayMode != 0 ? 5 : 0)

| idx | ptr | content |
|---|---|---|
| 0 | $19A84 | "Start Game / Change Goalie ..." |
| 1,2,3 | $19C04 | "Resume Game / Game Stats ..." |
| 4 | $19D60 | "Exit Game / Game Stats ..." |
| 5 | $19B38 | "Start Game / Change Goalie ..." (playoffs) |
| 6,7,8 | $19C04 | "Resume Game / Game Stats ..." |
| 9 | $19E74 | "Exit Game / Game Stats ..." |
| shootout | $19A00 | "Start Shootout / Shootout SetUp ..." |

### 1.9 Assignment ids used here (asstab, L56671)

$07 assscore, $08 assstanley, $09 assben, $0A assepen (leave penalty box), $0B assbench, $0C asspenalty (go to box), $0D assdopen, $11 assnearest, $18 pucknorm (the listing comments call it "pucknothing"), $1A puckunflip, $1B puckfaceoff, $1C puckfaceoff2, $1E puckshootout, $1F puckpenshot, $20 assgoaliebreakwait.

---

## 2. Game flow and clock routines

### StartGame (L29748)
- Purpose: new-game init, then the pre-game intermission and period 1. Reached from `PeriodOver.loc_17332` after the menus.
- Steps:
  1. `word_FFD6B4 = $FFxx` (st). Clear the longs dword_FFDEA4/AC/A8/B0.
  2. `ReadJoy1`. If the held-buttons byte d3 == $E0 (cmp.b): `OptPerlen = 3` (30-second periods).
  3. `gmode = 0` (clr.b). If `OptPen == 1`: set gmode bit 5 (gmoffs).
  4. If `OptPlayMode > 1` (signed): `sub_77E4` (clear $E4 words from unk_FFD092).
  5. `clearTeamStats` (zero both team structs, keep word $26 and the hot/cold tables, set box lists $9A to $FF). If shootout (word_FFC2FA bit0): `Create_HotCold_Table` for $FFC6CE and $FFCA32.
  6. Clear ScoreSumbytes, PenSumLength, gsp, ChkCnt. `restoreteams`, `InitScores`, `setupice`, `LoadCrowdRec`.
  7. `jmp loc_17278` (inside PeriodOver: ResetClock ... Intermission ... StartPer).

### sub_77E4 (L29790)
Clears 228 ($E4) words starting at unk_FFD092.

### restoreteams (L29800)
- For each team struct (Home $FFC6CE, Away +$364): `tmap ($24) = 6`; `tmpdst[i] = $FFFE` for i = 25..0 (d0 = $32 down to 0 step 2).
- Callers: StartGame, sub_1354C.

### ResetClock (L29817)
- Purpose: set the period length and stop the clock. Callers: StartPer (`bsr.s`), PeriodOver.loc_17278, ROM $788A.
- Steps:
  1. `d0 = ClockLength()`.
  2. If `gsp >= 3` (signed `blt` skips) and `OptPlayMode == 0`: `d0 = $258`.
  3. `gameclock = d0`; `PerTimeTotal = d0`; `word_FFB048 = d0`.
  4. `word_FFB048 -= randomd0(d0 asr 1)` (randomd0 returns 0..n-1). So the trigger time lies in (d0 - d0/2, d0].
  5. Set gmode bit 0 (clock stopped).
- Note: the clock fraction word (word_FFC46A) is not touched.

### ClockLength (L29839)
`d0 = _timetab[OptPerlen]` (word index: OptPerlen*2). Uses a0. Also called from setplayer+C2 (out of scope).

### StartPer (L29853)
- Purpose: start a period. Reached from PeriodOver (`jmp (StartPer).w`). Resets the stack pointer.
- Steps:
  1. If `gsp == 3`: set byte_FFC2FC bit 1 (overtime flag).
  2. `word_FFD6BE = $FFxx`; `sp = Stack`; `AllSndOff`; `setupice`; `ResetClock`.
  3. `word_FFBE78 |= $F000`; `c1playernum = c2playernum = $FFxx` (no controlled players).
  4. a3 = puck; `fox = foy = 0`.
  5. If shootout (word_FFC2FA bit0): `d0 = $1E`, `BA_Skater_Offset = 8`, `BA_Goalie_SCnum = $B`. Else `d0 = $1B` (puckfaceoff). `assreplace(d0)` on the puck.
  6. Set sflags2 bit2 (no replay record); clear sflags bit4; `lastsfx = $FFFF`; `recbpr = $FFFF0000`.
  7. `oldvcount = vcount`; `DoGameFrame`; `palcount = $FFFF`; `DoGameFrame`.
  8. `CwdExciteLvl = gamelevel << 4`; `CurCrowdMeter = 0`; `HmTeam = HomeTeam`; `SongIndex = 0`; `ChooseSong`; `song(SongNum)`.
  9. If `gsp < 2`: set sflags3 bit 7 (arms the mid-period music cue). Fall into GameLoop.

### GameLoop (L29902)
`loop { DoGameFrame; demoread; if sflags bit0 (pause): PauseMode }`. Never returns. Period changes leave it with jumps (PeriodOver -> StartPer resets sp).

### DoGameFrame (L29914)
1. Busy-wait while `vcount == oldvcount`. Then `d7 = vcount - oldvcount`; `oldvcount = vcount`.
2. `periodiceevents` (d7 preserved). Then `updateplayers`.
3. If `word_FFDECC > 0` (signed; 0 and negative skip): decrement it. When it reaches 0: `sub_1A304`; `song(word_FFDECE)`. This is the delayed goal song: checkgoal sets FFDECC = $78 (120 **frames**, not vblanks) for home-team goals only.
4. `setSlotBit`, `checkwindow`, `updatereplay`, `jmp setvideo`.

### periodiceevents (L29940-30009)
- Purpose: everything that runs once per frame or once per game second. d7 = elapsed vblanks.
- Steps:
  1. `PenaltyManager`; `updatecrowdf`; `sub_FE2C8`; `updatesound`; `clockcont`.
  2. If sflags bit 7 (horizontal mode): return. **Nothing below runs during the horizontal penalty screen.**
  3. `lldisp -= d7`; if `lldisp >= 0` return; `lldisp += $18` (24).
  4. `ChkGoalies`; `UpdateCwdExcite`; `sub_7A34`; `loc_79F8`; `loc_79EA`; `jmp updatepwrplay`.
- **loc_79F8 (bench recovery)**: if `OptLine != 0` return. For each team and each slot i = 25..0: if `tmpdst[i] == $FFFE` (on bench): `energy[i] += 9`. If `energy[i] >= $1000` (signed): `energy[i] = $1000`.
- **loc_79EA (injury message)**: `InjCntDown -= 1`. If the result is exactly 0: `jmp loc_1871C` (injury message display, out of scope). It keeps going negative after that. The injury code sets it to 4.
- **sub_7A34 (3rd-period music, L29987)**: if `gsp == 2` and gmode bit4 clear and `gameclock <= word_FFB048` (signed): `word_FFB048 = $FFxx` (one-shot), `HmTeam = HomeTeam`, `SongIndex = 5`, `ChooseSong`, `song(SongNum)`.

### UpdateCwdExcite (L30009)
Called once per game second.
```
d0 = CwdExciteLvl
if d0 > MaxCwdExciteLvl (unsigned): MaxCwdExciteLvl = d0
SumCwdExciteLvl (long) += sign_extend(d0); NumCwdExciteLvl += 1
CwdExciteLvl -= 1; if CwdExciteLvl < 0: CwdExciteLvl = 0     ; (comment says "<= 0", code clears only when negative)
```
Adders seen in scope: +$14 when an away player is penalized or a home goal is scored (AddPenalty2). +$A per counted shot (ChkShotStat). StartPer sets `gamelevel*16`.

### updatecrowdf (L30028)
Called every frame (also from waitxsr).
```
if crowdlevel >= $15E (signed): crowdlevel -= 3
crowdlevel -= d7; if negative: crowdlevel = 0
crowdcnt -= d7
if crowdcnt < 0:
    d0 = crowdlevel lsr 1; if d0 > $7F (unsigned): d0 = $7F
    d0 &= $60
    crowdstep = (crowdstep + 2) & $1E
    d0 += crowdstep
    crowdframe.lowbyte = _cd0[d0]
    mask = _cd0[d0+1]
    crowdcnt = mask + (VDP_HVcounter & mask)       ; pseudo-random 0..mask extra
crowdframe.highbyte = 0
if crowdlevel <= $118 (unsigned): return
r = VDP_HVcounter & $7F
if $13 <= r <= $19 (signed): crowdframe.highbyte = r
```
Port: use your RNG in place of the HV counter. Adders seen in scope: AddPenalty2 +$C8 (ids >= $E), goal +$1F4, shot +$64, end of game +$3E8. puckfaceoff2 caps it at $258.

### VBlank clock tick (loc_15D9A, L51766-51830)
- Purpose: the only place `gameclock` decrements.
```
(after fade/DMA work)
if sflags bit0 (paused): goto done
if word_FFC2FA bit2 == 0 and gmode bit0 (clock stopped): goto done
if word_FFC2FA bit1:                         ; shootout / penalty-shot attempt clock
    if word_FFD454 == 0: goto done
    word_FFD456 -= $AAA; if no borrow: goto done
    set disflags bit3 (clock display refresh)
    if word_FFC2FA bit7: goto done           ; attempt clock frozen while intro text shows
    word_FFD454 -= 1                         ; set to $19 (25 s) by puckshootout
    goto done
if gameclock == 0: goto done
word_FFC46A -= $AAA; if no borrow (bcc): goto done
set disflags bit3
gameclock -= 1
if 60 <= gameclock <= 61 (signed): sfx(2)    ; plays twice: on reaching 1:01 and on reaching 1:00
done: vcount += 1; MusicVB
```

### clockcont (L30074-30159)
- Purpose: when the running clock reaches 0, end the period or the game. Called every frame from periodiceevents.
- Inputs: gmode, gameclock, gsp, HmGoals/AwGoals, OptPlayMode, gamelevel, bosgames, gamenum, gsstruct.
```
if gmode bit0: return
if gameclock != 0: return
set disflags bit3; sub_1A304; sfx(4) (horn); freezewindow
loc_7B5C:                                   ; also entered from puckfaceoff when an OT goal was scored
a3 = puck; assinsert($18 pucknorm)          ; listing comment calls it "pucknothing"
if gsp < 2: goto _eop
d0 = 7 (assscore); a3 = SortCords (object 0)
if gamelevel == 3:                          ; Stanley Cup final
    if bosgames == 7: goto _sc              ; single game
    a0 = gsstruct + 16*gamenum
    d3 = 0; if a0.flags bit0 (teams flipped): d3 ^= 2
    if HmGoals - AwGoals < 0: d3 ^= 2        ; a tie counts as "home" here
    if word(a0 + 4 + d3) == 3: goto _sc      ; winner already has 3 series wins
    goto _t3
_sc: d0 = 8 (assstanley); clear pflags bit3 (pfjoycon) on objects 0..11; a3 = SortCords
_t3:
d1 = HmGoals - AwGoals
if d1 == 0: goto _eop
if d1 < 0: a3 += $300                        ; away objects 6..11
for 6 objects: if position ($34) > 0 (signed; skips goalie and off-ice):
                   assinsert(d0); d0 = 7     ; only the first skater gets assstanley
_eog:
clrPenBuf; crowdlevel += $3E8
set gmode bit0 and gmode bit6 (game over)
sub_FF88E                                    ; wipes penalties: PBnum, Penaltytimer, Pencntdwn, PenBuf, all tmpdst=-2, box lists empty
AddPenalty2(4 PenEOG) and return
_eop:
if gsp == 3 and OptPlayMode == 0: goto _eog  ; regular-season OT ran out: game ends (tie)
AddPenalty2(2 PenEOP) and return
```
- Quirks: the EOP path does not set gmclock. The next frame's checkfornewpen (which runs before clockcont) calls Stop4Pen, and that stops the clock, so the horn/EOP happens once. In the `_sc` path with a tie (bosgames == 7), pfjoycon is cleared and then `_eop` is taken. For the AddPenalty2 calls, a3 is whatever the code left in it (puck, object 0, or the object after the loop). Only its SCnum (and, for ids >= $E, its team) is used.

### puckfaceoff (L41627): end-of-period hub (excerpt only)
On its first call (pfna, bit 1 of `$62`, was set), after unrelated setup (shootout redirect to $1E, byte_FFC2FE bit0 -> center faceoff, overlay/music):
```
bclr word_FFC2F8 bit1; bclr word_FFC2FA bit1 (stop attempt clock)
if gameclock == 0: jmp PeriodOver
if gmode bit6: jmp PeriodOver
if gsp == 3 and HmGoals != AwGoals: jmp clockcont.loc_7B5C          ; OT winner
if gmode bit3 (gmpendel): jmp Stop4Pen                              ; a0 is stale but unused (gmclock already set)
if (PerTimeTotal asr 1) > gameclock (unsigned) and gameclock >= 60 and bclr(sflags3 bit7) was set
   and gmode bit0 and !byte_FFC2FE bit6: HmTeam=HomeTeam; SongIndex=2; ChooseSong; set byte_FFC2FE bit4
ReturnGoalies; puck temp1/temp2 = $FFxx; line-change setup (CompLine/SetPersonel for CPU teams)...
```
Then (after the line-change timers $40/$42 of the puck expire) `assreplace($1C puckfaceoff2)`.

### PeriodOver (L53805)
- Purpose: advance the period. Reached by `jmp` from puckfaceoff (twice).
```
gsp += 1
gmode bit1 ^= 1 (bchg)                       ; teams switch ends
if gsp < 3: goto L1
if gsp == 3: goto L0
gsp = 3                                      ; gsp was 4 (an OT period ended)
if OptPlayMode == 0: gsp = 4
L0: if HmGoals != AwGoals: gsp = 4
L1: forceblack
loc_17278:                                   ; StartGame enters here
ResetClock
wait one vblank; AllSndOff; wait one vblank
song($79)
UpdateScores
if gsp == 4: AddPOStats
Intermission
if gsp == 4: goto GameOver
jmp StartPer
```
- Result: after regulation, a tie -> OT (gsp 3) and otherwise game over. After an OT period, regular season -> game over (a tie is possible). In playoffs another OT follows unless the score differs. (In practice an OT goal reaches here through `gmode bit6`, with gsp 3 -> 4.)
- Note: ResetClock also runs before the game-over intermission. One extra word stays on the stack (two pushes, one pop). It is harmless because StartPer resets sp.

### GameOver (L53851)
```
sub_180FC                                    ; playoff tree bookkeeping (OptNOP != 0 and 1 <= OptPlayMode <= 3);
                                             ; may rewrite OptPlayMode to 1/2/3
if OptPlayMode != 0: clear sflags bit1; sub_9428
PlayoffScreen
song($78)
Opening2: KillCrowd; clear RAM VSCRLPM..$FFD03E; GameSetUp; sub_FBB88; PlayoffScreen;
          if !shootout: sub_FCC76; jmp StartGame
```

### Intermission (L47613) (summary)
1. If `gsp == 4`: `gameclock = 0`; `sub_F9CDE` (end-of-game screen).
2. `sub_13056`: `ResetBench`. For Home (a2) / Away (a3), then swapped: `sub_13068`:
   - `sub_130BE(a2)`: for each slot: if tmpdst != -4: energy = $1000. If tmpdst == -3 (injured for the period): tmpdst = -2.
   - `a3.tmline = 0`. If `OptLine == 0` and `a3.tmap != a2.tmap`: `a3.tmline = 3` if a3 has more players, 5 if fewer.
3. Clear Xpos of all 16 objects. Load the intermission graphics. `zamx = $140`.
4. Menu text pointer = `unk_131CC[gsp + (OptPlayMode ? 5 : 0)]` (shootout: unk_19A00). Set sflags bit0 (pause) and call sub_7E36 (menu).
5. `TickerNum = GetShifter()`. While `TickerNum >= 0`: NewTicker2, NewTicker3pt2, `waitxsr(150)`. If Start pressed: break (set sflags3 bit3). Then sub_134D8, `waitxsr(60)`. If Start pressed: break (set bit3).
6. `sub_1351C`. If sflags3 bit3 was set (bclr), finish. Otherwise repeat `waitxsr(480)` until Start is pressed. If no team is human-controlled (cont1team == cont2team == 0), stop after one wait.
7. `zamx = $FFxx`.

### InitScores (L47726)
- Purpose: set up the other games for the ticker. Called by StartGame.
```
if gamelevel > 1 (signed): return
d1 = GetShifter()                            ; number of series this round - 1
a0 = gsstruct + 16*d1
loop d1 down to 0:
    if d1 != gamenum and !(a0.flags bit2 series over):
        a0.gsper = 0
        k = randomd0(3)                       ; 0..2
        repeat k times: SetScore(a0)          ; other games start 0-2 periods in
    a0 -= 16
```
- Scores ($A/$C) are not cleared here.

### UpdateScores (L47757)
```
d1 = GetShifter(); TickerNum = d1; a0 = gsstruct + 16*d1
loop d1 down to 0:
    if d1 != gamenum:
        clear a0.flags bit1
        if !(a0.flags bit2): SetScore(a0)
    a0 -= 16
```
Called by PeriodOver (also at game start, through StartGame's jump into loc_17278). So other games advance one period per real period, plus one at game start.

### SetScore (L47780)
```
if a0.gsper >= 4 (signed): return
if a0.gsper == 3:
    a0.gsper = 5                              ; final
    diff = score1 - score2
    if diff > 1 or diff < -1: return
    a0.gsper = 3; set a0.flags bit1           ; close game: stays "3rd", flagged
    return
a0.gsper += 1
score1 += getscore(team1, team2)
score2 += getscore(team2, team1)
```
Quirk: a game within one goal at gsper 3 never reaches final here, because every later call re-flags it. Resolution is left to other playoff code (out of scope).

### getscore (L47815) and sub_10EB4 (L43979)
```
getscore(d0 = teamA, d1 = teamB):
  pA = teamptr[teamA] (long table at ROM $30E); ratingA = byte at pA + word(pA+8)
  w[0..3] = sctab[(ratingA & $70) >> 4]       ; offense nibble (bits 4-6)
  pB = teamptr[teamB]; ratingB = same byte
  w[0..3] += sctab[ratingB & 7]               ; defense nibble (bits 0-2)
  return sub_10EB4(4)
sub_10EB4: total = w0+w1+w2+w3; r = randomd0(total)
  k = 3; loop: r -= w[k]; if r < 0 return k; k -= 1   ; i.e. P(k goals) = w[k]/total
```

### GetShifter (L55429)
`d2 = -16; d1 = 16; repeat (gamelevel+1) times { d2 += d1; d1 >>= 1 }; d1 -= 1.` Results: gamelevel 0 -> d1 = 7 (8 series), 1 -> 3, 2 -> 1, 3 -> 0. d2 = tree offset (0, 8, 12, 14).

---

## 3. Penalty and stoppage routines

### AddPenalty (L45939) / AddPenalty2 (L45954)
- Purpose: queue an infraction (AddPenalty) or a forced stoppage (AddPenalty2). d0 = id, a3 = offending player (for stoppages: any object; its SCnum is stored).
```
AddPenalty:
  if gmode bit0 (play stopped): return              ; no penalties during stoppages
  if d0 == $C (icing): goto AddPenalty2             ; icing ignores OptPen
  if OptPen == 0: return
  if a3.pflags2 bit2 ("unavailable"): return
  if gmode bit5 (offsides on): goto AddPenalty2
  if d0 == $10 (offside): return
AddPenalty2:
  if sflags bit7 (horizontal mode): return
  if d0 >= $E (signed):
      crowdlevel += $C8
      jingle = $C
      if a3 is away (pflags bit6): CwdExciteLvl += $14; jingle = $B
      song(jingle)
  scan PenBuf words 0..31 for the first 0; if none: return
  entry.hi = d0; entry.lo = a3.SCnum low byte ($53)
  rec = PenaltyList[d0]
  if rec.minutes == 0 or negative: return
  set DelayedPen bit1 (a3 home) or bit2 (a3 away)
  if a3.pflags2 bit4 was already set: clear this entry   ; one pending penalty per player
  set a3.pflags2 bit4
```
- Callers: see the PenaltyList table. CCStart/holdcheck pass d0 through PenShotChk first.
- Note: `song` here is the music/jingle routine (stack argument), not `sfx`.

### PenaltyManager (L46005)
`updatepentime; checkfornewpen; chkprogress; bra UpdatePA` (every frame, d7 = elapsed vblanks).

### updatepentime (L46819) (+ loc_1298C list delete, sub_129D2 return to ice)
- Purpose: once per 24 vblanks of running clock: possession stat, PP time stat, box time.
```
clear sflags3 bit6
if gmode bit0: return                       ; box time only runs with the clock
Penaltytimer -= d7; if >= 0: return
Penaltytimer += $18
set sflags3 bit6
chkatop
updatePPTeamTime
for a2 in (Home, Away):
    a0 = a2+$9A; mes = []; d1 = 2
    loop:
        d0 = *a0++; if negative: break
        if tmpdst[d0] bit14 (coincidental):
            tmpdst[d0] -= 1
            if tmpdst[d0] bit11 set (the seconds underflowed past 0):
                if bit12 clear: tmpdst[d0] = $1000      ; see Q7
                else:           tmpdst[d0] = 0
                delete *(a0-1) from list (shift the rest down, a0 -= 1)
                RETURN from this team's processing     ; `bra loc_1298C` ends in rts: the rest of this team's
                                                       ; list does not tick and no beep check is done this
                                                       ; second (for Away this returns from updatepentime)
            continue
        d1 -= 1; if d1 < 0: continue                     ; only the first two serve time
        mes.append(d0)                                   ; mesarea words
        tmpdst[d0] -= 1
        if tmpdst[d0] == 0: delete from list (a0 -= 1)
    ; after the list:
    if d1 == 1: beep(mes[0])
    elif d1 == 0: beep(mes[0]); beep(mes[1])
    elif d1 == -1: beep(mes[1])                          ; quirk: 3 penalized -> only the 2nd is checked
    (d1 == 2 or d1 <= -2: nothing)
beep(d0):
    if tmpdst[d0] > 5 (signed): return
    if tmpdst[d0] == 0: sub_129D2(d0); sfx(2)          ; penalty expired: player returns
    else: sfx(1)                                        ; last-5-seconds beep
```
- **loc_1298C** (list delete): `i = -1; do { i++; a0[i-1] = a0[i] } while (a0[i-1] >= 0); a0 -= 1`. This copies the terminator too.
- **sub_129D2 (L46924)**, d0 = pnum*2, a2 = team:
  1. a3 = first object of the team (from tmsort $22) whose position ($34) is negative. The scan does not stop at 6 objects; see Q6.
  2. `d3 = d0 >> 1`; `d1 = tmap`; `tmap += 1`; set byte_FFC6FE bit0 and byte_FFCA62 bit0 (line refresh flags of both teams).
  3. `idx = d1 + (goalie pulled, i.e. word $26 < 0 ? 1 : 0)`; `position = priolist[idx]` (word: high byte 0).
  4. `Setplass` (assignment from `_alist[position]`). `setplayer(d3)`: he was in the box, so he gets assinsert($0A assepen), and tmpdst becomes -1. Set pflags2 bit2.
- Coincidental majors expire after `secs+1` ticks (the bit-11 test fires on the tick after reaching $4000). Non-coincidental penalties expire after `secs` ticks.
- Non-coincidental deletion uses `bsr loc_1298C` and the loop goes on with the entry that shifted into place. Coincidental deletion jumps into loc_1298C, whose `rts` ends that team's pass (quirk Q17).

### chkatop (L46904)
```
if pucky > $58 (signed):  t = Home
elif pucky < -$57 (i.e. -pucky >= $58): t = Away
else: return
if gmode bit1 (gmdir): swap t
t.ATOP ($A) += 1
```
Note the asymmetry: the top zone needs y >= 89, the bottom zone y <= -88.

### updatePPTeamTime (L973148)
`if sflags2 bit5: (sflags2 bit6 ? Away : Home).$352 += 1`.

### checkfornewpen (L46358)
- Purpose: call stoppages and penalties, or mark them delayed. Every frame.
```
if sflags bit7 (horizontal): return
a0 = PenBuf
loop:
    e = *a0++ ; if e == 0: return                ; a0 now points past the entry
    if gmode bit2 (gmpen): goto iscalled
    rec = PenaltyList[e.hi]
    if rec.minutes == 0: goto callit
    if puckc < 0: goto delayed                   ; loose puck keeps the penalty delayed
    if ((puckc - 6) XOR (sext(e.lo) - 6)) < 0: goto delayed   ; other team has the puck
callit:
    Stop4Pen
iscalled:
    if bit7 of e.lo already set: continue        ; (bset)
    set bit7 of e.lo
    d1 = rec.delay << 5
    if d1 > Pencntdwn (signed): Pencntdwn = d1
    continue
delayed:
    if gmode bit3 already set: continue          ; (bset)
    set gmode bit3; SetPA($2C "Penalty")
    continue
```
Notes: after Stop4Pen, gmpen is set, so every remaining entry in this loop (and any added later in the stoppage) goes straight to `iscalled`. While a delayed penalty is pending, a later stoppage entry (icing, offside, goal ...) calls all of them.

### Stop4Pen (L46411)
- Purpose: blow the whistle. a0 = PenBuf entry + 2 (so -2(a0) = id, -1(a0) = SCnum).
```
if gmode bit0 already set (bset): goto skipfo
(d0,d1) = (0,0)                                      if id == $E (goal)
        = (ltx, lty)                                 if id == $6 (out of play; last puck position)
        = (puckx, $258 or -$258)                     if id == $C (icing): -600 if offender.pflags bit7 (pfgoal) else +600
        = (puckx, pucky)                             otherwise
sx = d0 (pre-clamp x, saved)
if d0 >= $46: d0 = $46;  if d0 <= -$46: d0 = -$46    ; signed
if d1 >= $A6:  d1 = $CE;  d0 = (sx >= 0 ? $46 : -$46)
if d1 <= -$A6: d1 = -$CE; d0 = (sx >= 0 ? $46 : -$46)
fox = d0; foy = d1
limitfo
skipfo:
Pencntdwn = 0
set gmode bit2 (gmpen)
sub_1A304; sfx(3) (whistle)
SetPA($A)
```
- In the neutral strip (|y| < $A6) the faceoff spot is the stop location with x clamped to +-70. In the end zones it is the dot at (+-70, +-206). Callers: checkfornewpen, puckfaceoff+BC, puckshootout (both when gmpendel).

### limitfo (L46482)
- Purpose: no faceoff in the offending team's attacking zone.
```
a0 = PenBuf
do:
    p = SortCords[(byte(a0+1) & $7F)]
    if p.pfgoal (attacks +Y):
        if foy >= $58: foy = $41;  fox = (fox >= 0 ? $46 : -$46)
    else:
        if foy <= -$58: foy = -$41; fox = (fox >= 0 ? $46 : -$46)
    a0 += 2
while word(a0) != 0
```
- It is applied to **every** entry, including stoppage entries (their SCnum may be the puck, a net, etc.). The first entry is processed even if it is 0 (do-while). Comparisons: `cmp foy,$58; bgt` -> return when $58 > foy, and mirror.

### chkprogress (L46014)
- Purpose: drive the stoppage after the whistle.
```
if BA_PS_flags bit2:                                     ; penalty-shot / shootout intro text
    if BA_PS_flags bit7: sub_187B8; clear bit7; return
    if word_FFC31A >= 0:
        word_FFC31A -= 1 (per frame, not d7); if >= 0: return
        clear sflags2 bit2; clear word_FFC2FA bit7; erase the message rows (8, or $C in shootout); return
_cont:
if !gmode bit2: return
if Pencntdwn < 0: goto InProgress
Pencntdwn -= d7; if >= 0: return
clear gmode bit3 (gmpendel)
scan PenBuf for an entry whose rec.minutes > 0 (skips 0 and negative); none found: return
; real penalty -> horizontal penalty screen
set sflags2 bit2; forceblack with vcount preserved (the blackout time is not counted in d7)
SetHor; load ref graphics (unk_5CF6C); NewTicker; NewTicker3pt2
puckc = $FFxx; puck: assinsert($1A puckunflip); puck.temp1 ($40) = $1C20
RefStep = $FFxx; RefCnt = 0; UpdatePA; RefCnt = $32; PushRef(0); palcount = $18
```
The ref stands in frame 0 for about 50 vblanks, then the window is cleared. InProgress starts after that.

### InProgress (L46187-46358)
- Purpose: assess the queued entries one at a time, newest first. Runs while gmpen is set and Pencntdwn < 0.
```
if RefCnt >= 0 or RefStep >= 0: return               ; wait for the ref animation
top:
if PenBuf[0] == 0: goto finish
a0 = last nonzero entry
if bit7 of a0.lo was clear (bclr):                    ; already assessed, or never called
    p = SortCords[a0.lo]
    if p.position >= 0: return                        ; wait until the player is off the ice (in the box)
    clear entry; return
rec = PenaltyList[a0.hi]; clear word_FFC2F6 bit5
m = rec.minutes
if m == 0 or m < 0: goto nonpen
if m == 5: set word_FFC2F6 bit5
; --- assess ---
t = sub_14A94()                                       ; (gsp<<14) + elapsed seconds
PenSum[PenSumLength] = {t, id, -} ; if PenSumLength != $EC: PenSumLength += 4
p = SortCords[a0.lo]; pen = Home; opp = Away
if p away: PenSum.id |= $80; swap pen/opp
pen.penalties ($6) += 1; pen.PIM ($8) += m
PenSum.byte3 = p.pnum; TempPlOffset = ($8000 if away) | pnum
pen[$102 + pnum] += m (byte)
d0 = pnum*2
v = m*60 | $2000
if pen.tmpdst[d0] >= 0 and (pen.tmpdst[d0] & $1000): v |= $1000
pen.tmpdst[d0] = v
v &= $EFFF
for d1 = $32 down to 0 step 2:                        ; coincidental major check
    if (opp.tmpdst[d1] & $EFFF) == v and word_FFC2F6 bit5:
        opp.tmpdst[d1] |= $4000; pen.tmpdst[d0] |= $4000; break
append d0 to pen box list ($9A): first negative byte within 25 bytes (if none, the 25th byte), then $FF after it
p: assreplace($0C asspenalty)
SetPA(id); sub_12DA6 (redraw scores and box times)
return
nonpen:
clear entry
if sflags bit7 (horizontal): goto top                 ; stoppage entries are dropped silently on the penalty screen
SetPA(id); return                                     ; vertical: show "Icing", "Off-side", "Period Over", ...
finish:                                               ; loc_123A2
sub_123DE(Home); sub_123DE(Away)
clear gmode bit2
clear BA_PS_flags bit6
puck: assreplace(BA_PS_flags bit3 ? $1E puckshootout : $1B puckfaceoff)
```
- The "bit7 clear" branch makes the second visit to each assessed entry wait for the penalized player to skate to the box. asspenalty takes him off the ice, which makes the position negative. That is the only place where real-penalty entries are removed.
- Coincidental only applies when both players were assessed in the **same** stoppage (bit 13 must match), with the same seconds, and the penalty being assessed is a 5-minute one.

### sub_123DE (L46333): recount players on ice
```
d1 = 6
for d0 = $32 down to 0 step 2:
    if tmpdst[d0] <= 0: continue
    clear bit13
    if bit14 or bit12: continue
    if d1 == 4: continue
    d1 -= 1
tmap ($24) = d1
```

### UpdatePA (L46523)
```
if RefCnt < 0: return
RefCnt -= d7; if RefCnt < 0: setPA2
if RefPen == 4 (Game Over): sub_1850A (every frame while animating)
word_FFC3EE -= d7; if < 0: word_FFC3EE = $7FFF; blank line + reprint the message (display)
```

### SetPA (L46552) / setPA2 (L46580)
```
SetPA(d0):
  RefPen = d0
  if d0 >= $2E: return                                ; penalty-shot variants: no animation
  RefStep = 0
  prefmes(d0)                                         ; print the text (centered; horizontal: other row)
  if d0 == $E: loc_1889A (goal message)
  if shootout and word_FFC2FA bit3: sub_FC5AE
  word_FFC3EE = $7FFF; if horizontal: word_FFC3EE = $3C
  fall into setPA2
setPA2:
  if RefStep < 0: PushRef($40) (clear window); return          ; RefCnt stays negative => done
  w = script(RefPen)[RefStep]; RefStep += 2
  if w < 0: w = -w; RefStep = $FFxx
  RefCnt = (w & $FF) * 8
  if shootout and word_FFC2FA bit3: RefCnt *= 2
  PushRef(w >> 8)
```
- PushRef(frame): frame $40 clears the 56-tile ref window. Otherwise it copies tiles `RefsMap + frame*$70` (another map in horizontal mode). Display only.
- A full script lasts sum(dur*8) vblanks plus one vblank per step: each step ends when RefCnt goes **negative**.

### PenShotChk (L46100)
- Purpose: turn a foul on a breakaway skater into a penalty shot. a2 = fouled player, a3 = offender, d0 = id. Preserves d1-d3/a0. Output: d0.
```
if !(a2.pflags3 bit1 breakaway) or BA_PS_flags bit3: return d0
v = unk_1913A[d0]; if v < 0: return d0
getBAplayerInfo(a2.SCnum)          ; on failure (N=1): clear BA_PS_flags bit3; return d0
word_FFD410 = v; return v
```
- getBAplayerInfo (L46136): if OptPen == 0 -> fail. Set BA_PS_flags bit3. Find the opposing goalie (`getGoalieSCnum(5 or $B)`); none -> clear bit3 and fail. Record BA_Sktr_SCnum, BA_Team, BA_Skater_Offset (fouled pnum), BA_Goalie_SCnum, BA_Goalie_Offset, BA_Checker_Offset (a3 pnum). Success = N clear (from the last move.b of a3's pnum).
- Effect on the rules: the variant has minutes $FF. AddPenalty queues it but sets no DelayedPen/pflags2 bit. It is called or delayed like a penalty (minutes != 0) and never assessed. At `finish`, BA_PS_flags bit3 selects `$1E` (penalty shot) instead of a faceoff. The fouling player is **not** penalized (no box time). This matches NHL rules for a penalty shot on a minor.

### CalcPenTime (L46955)
- Purpose: PP time-remaining number for the PP banner (display). a2 = shorthanded team, a3 = PP team. Output d0.
```
d0 = 0; d3 = 0
for each b in a2 box list: t = a2.tmpdst[b]; if t bit14: continue
    t -= d3; d0 += t; d3 = t
if a3.tmap == 6: return d0
d0 -= d3
for each b in a3 box list: if a3.tmpdst[b] bit14: continue
    if d0 < a3.tmpdst[b] (signed): return d0
    return d0 + d3            ; only the first non-coincidental entry is looked at
return d0                     ; list empty
```
Port verbatim. The accumulation is odd (for lists t1,t2 it gives t2; for t1,t2,t3 it gives t1+t3).

### updatepwrplay (L46991-47073)
- Purpose: once per game second (not in horizontal mode), keep the PP flags and banner.
```
if word_FFC2FA bit1: return
a2 = Home; a3 = Away
d = Home.tmap - Away.tmap
if d == 0: goto clr (and return)
if d < 0:                                 ; away on PP
    if !sflags2 bit6: clr(); set sflags2 bit6
else:                                     ; home on PP
    swap a2,a3                            ; a2 = shorthanded, a3 = PP team
    if sflags2 bit6: clr(); clear sflags2 bit6
if sflags2 bit5 was clear (bset): a3.tmPwrPlays ($4) += 1       ; new power play
print PP banner tiles; PushTime(CalcPenTime(a2,a3)); print a3's team name
clr: if sflags2 bit5 was set (bclr): sub_12D70 (restore the score display)
```

### sub_1284A (L46773): power-play goal / cancel delayed penalties
- Called by checkgoal after a goal (a2 = scoring team, a1 = scored-on team).
```
if a1.tmap == 6: clrPenBuf                 ; clears ALL queued entries (both teams)
if a2.tmap <= a1.tmap (signed): return
for each b in a1 box list:
    if a1.tmpdst[b] bit14: continue
    a1.tmpdst[b] = 0; delete b from list
    set DelayedPen bit0
    a1.tmap += 1
    a2.PwrGoals ($2) += 1
    set byte_FFC6FE bit0, byte_FFCA62 bit0
    return
```
The released player is not put on the ice here. tmpdst 0 makes ResetBench send him to the bench at the faceoff.

### clrPenBuf (L46804)
Clears PenBuf words 0..31.

### sub_FF88E (L976557) / clrTmPdst (L976577): end-of-game wipe
`PBnum = 0; Penaltytimer = 0; Pencntdwn = 0`. Clear 17 longs from $FFC3A4 (PenBuf + Pencntdwn). For each team: tmpdst[0..25] = $FFFE, then word at $9A = $FFFF (empty box list).

### ResetBench (L51490): faceoff bench reset (context)
Called by puckfaceoff2 and puckpenshot. `PBnum.hi = 0`. For each team (home adds $10, away adds 1 per slot) and each slot 25..0:
- If tmpdst > 0, it counts in PBnum, except when bit12 is set and `(tmpdst & $7FF) == 0`.
- If tmpdst <= 0: not counted. Unless it is -3 or -4, tmpdst = -2 (bench). This turns served players (0) and every on-ice player (-1) into bench players. forcepldata then puts the faceoff players back to -1.

### ChkGoalies (L41839), ReturnGoalies (L41876), CPgoalie (L41898): goalie pull
- ChkGoalies runs once per game second while the clock runs. For each team (Home d0 = 1, Away d0 = 2):
```
if team.goalie ($26) < 0: skip (already pulled)
if puckc < 0 or the puck carrier is not on this team: skip
if gmode bit3 (delayed penalty): team.goalie.hi = $FF; SetPersonel      ; any team, human or CPU
else if team is not human (d0 != cont1team and d0 != cont2team): CPgoalie(d1 = pucky)
```
- ReturnGoalies (at puckfaceoff): for each team, if `goalie == $FFFF` skip. Else `goalie.hi = 0` (goalie back). Then, for CPU teams, `CPgoalie(d1 = foy)`.
- CPgoalie: only if `gsp == 2` and `opp.score - team.score == 2` exactly (**bne** at ROM $F764; the comment says "behind by more than 2") and `gameclock <= 60`. Negate d1 if the team's first object does not attack +Y. If d1 >= 0 (puck/faceoff in the attacking half): `goalie.hi = $FF`; SetPersonel.

### Endfaceoff (L42445) (context)
`sfx($2F)`; clear sflags2 bit0 and bit2; **clear gmode bit0** (play and clock resume); set sflags3 bit4; then decide who wins the draw (out of scope). puckfaceoff2 earlier clears DelayedPen bits 0-2, word_FFC2F4 bits 0/1, caps crowdlevel at $258 and calls `resetplstuff` (pflags2 = 0 for all on-ice objects).

---

## 4. Shots on goal

### ChkShotStat (L47451)
- Purpose: count a shot on goal. Callers: checkgoal (puck hits the net frame, L49718 `_deflectsf`; goal L49805 and L49918), puckstick when a goalie gets the puck (L50701), puckgoalie (L50867).
```
if gmode bit0 or gmode bit4: return
if sflags2 bit4 (shot taken) was set (bclr):
    crowdlevel += $64; CwdExciteLvl += $A
    s = shotplayer; goto add
if !(word_FFC2F4 bit0): return              ; bit0 = "goal just scored" (set by checkgoal)
if byte_FFC2FE bit3 was clear (bclr): set it; return
; second call during a goal that had no shot flag: credit the scorer
r = ScoreSum + ScoreSumbytes - 6          ; last scoring record
team = (r.byte2 bit7) ? Away : Home
find the object among team's 6 (from tmsort) with pnum == r.byte3; none: return
s = its SCnum
add:
p = SortCords[s]; (a2 = p's team, a1 = other)  ; loadTeamStruct
a2.shots ($0) += 1
if sflags2 bit5 and (PP team == p's team): a2.PPshots ($354) += 1
a2[$34A + 2*gsp] += 1
a2[$E8 + p.pnum] += 1 (byte)
if a1.goalie ($26) >= 0: a1[$E8 + a1.goalie] += 1 (byte; goalie shots against)
```
- So one shot is counted per shot attempt that reaches the net/goalie (the flag is cleared on count), and every goal counts one shot: the shooter's if the flag was set, otherwise the scorer's (checkgoal calls it twice around writing the ScoreSum record, and clears byte_FFC2FE bit3 before the first call).

### loadTeamStruct (L47539)
`a2 = Home, a1 = Away; if a3 away: swap.`

---

## 5. Quirks (port as-is)

- Q1. `unk_1913A` is shifted one entry relative to the PenaltyList texts (Charging -> "Slashing" variant, Slashing -> "Roughing", Roughing -> "Cross Check", Cross Check -> "Hooking", Hooking -> "Tripping", Tripping -> "Interference", id $14 -> "Charging"). Only the displayed RefPen/text of an unanimated variant is affected (SetPA ignores ids >= $2E). Holding ($24) and Interference ($22) never give a penalty shot.
- Q2. The one-minute sound sfx(2) plays twice (on reaching 61 and 60 seconds). The same id is used for "player leaves the box".
- Q3. Regular-season OT is 10:00 ($258) regardless of OptPerlen. Playoff OT uses the normal period length.
- Q4. A loose puck (puckc < 0) keeps a penalty delayed. Only possession by the offending team (or another stoppage) calls it.
- Q5. With 3 or more non-coincidental penalized players, only the 2nd one's beep/return is checked (d1 == -1). An expiring 1st player is not returned to the ice. He becomes tmpdst 0 and goes to the bench at the next faceoff. tmap is not raised for him. If the 2nd expires, he does return and tmap += 1 even though another player is still in the box.
- Q6. sub_129D2 searches for an off-ice object with no bound. If all objects from tmsort onward have position >= 0, it runs past the team's 6 objects.
- Q7. tmpdst bit12: InProgress keeps it when re-penalizing a player with tmpdst >= 0 and bit12. A coincidental expiry sets $1000 when bit12 is clear. A player at $1000 is not in any list, never ticks, is unavailable (tmpdst > 0) and shows "Injury G". Because coincidental tmpdst = $4000|secs, the expiry test sees $3FFF (bit12 set) and writes 0. So $1000 is reachable only from a $5xxx value, which needs bit12 already set. In practice bit12 should never be set. Port the logic as-is.
- Q8. A PP goal releases a 5-minute (non-coincidental) major too. There is no major/minor distinction.
- Q9. clrPenBuf on a goal against a full-strength team wipes **all** queued entries, including the scoring team's own delayed penalties. pflags2 bit4 stays set on those players until the next faceoff (resetplstuff).
- Q10. CPU goalie pull needs exactly a 2-goal deficit (bne).
- Q11. chkatop top/bottom thresholds are asymmetric (y > 88 against y <= -88).
- Q12. clockcont's `_sc` branch (single-game final) clears pfjoycon for all skaters even when the score is tied, then goes to OT.
- Q13. limitfo uses the pfgoal of every PenBuf entry's object (including the puck/nets for stoppages), and processes slot 0 even if it is empty.
- Q14. InitScores does not clear other games' scores. SetScore keeps a game within one goal at gsper 3 forever.
- Q15. The `cmp.w #$E,d0; blt` in AddPenalty2 means the goal ($E) and every player penalty make crowd noise and a jingle. For the goal, a3 is the scored-on team's first object, so a home goal gives jingle $B and excitement +$14.
- Q16. The VBlank stops the clock while paused (sflags bit0). Intermission sets that bit.
- Q17. In updatepentime, a coincidental major's expiry returns early (see updatepentime): later box-list entries of that team skip this second's decrement, and no beep or return-to-ice check runs for that team that second.

## 6. UNRESOLVED

- U1. Callers of PenaltyList ids $26/$28/$2A (fighting) and $32 ("Face Off", delay 0): a grep for immediate loads into d0 found none. They are probably unused in '94.
- U2. The joypad byte $E0 tested by StartGame is the held-buttons byte returned by ReadJoy1 in d3 (bit7 = Start per demoread). Bits 5 and 6 most likely map to two of A/B/C. The exact button names were not traced into ReadJoy.
- U3. The exact meanings of DelayedPen bit0 (used by the goal display at L56024 to choose a "PP goal" text table), sflags3 bit6 consumers, byte_FFC6FE/byte_FFCA62 bit0 (line-refresh flags) and gsstruct flags bit1. These are display or line logic outside this scope.
- U4. sub_1A304 (called at every whistle/horn and by the goal-song timer) manages sound slots. Not analysed.
- U5. Where gmpendel can still be set at puckfaceoff (chkprogress clears it whenever a stoppage's Pencntdwn expires). The check looks defensive. It is ported as-is.
