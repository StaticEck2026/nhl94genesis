# Penalty shot and shootout spec (NHL '94 Genesis)

Source: `lst/nhl94.bin.lst` (Lnnnnn = listing line), ROM `lst/nhl94.bin`. Every routine in sections 3-7 was checked against the ROM bytes; RAM addresses marked "confirmed" were read from instruction bytes.

Conventions (same as `rules_clock_penalties.md` and `goalie.md`):
- `btst/bset/bclr #n,(var).w` on memory is a **byte** operation on the first byte (the high byte) of a word variable. "`word_FFC2FA` bit 3" means bit 3 of the byte at `$FFC2FA`.
- `st (x).w` / `st $nn(a3)` sets only that byte to `$FF`, so a word becomes `$FFxx` (negative).
- "Frame" = one `DoGameFrame` = one call of every object's assignment. "Vblank" = 1/60 s. `d7` = vblanks since the previous frame (>= 1). Counters marked "per frame" ignore `d7`.
- Coordinates are raw pixels (high word of the 16.16 position). Origin is center ice, +Y is the top goal. Goal lines are at y = ±$108 (264), nets at y = ±$10C (268).
- Directions (`vtoa`, `facedir $54`): 0 = +Y, 1 = +X+Y, 2 = +X, 3 = +X-Y, 4 = -Y, 5 = -X-Y, 6 = -X, 7 = -X+Y, 8 = no direction (`vtoa(0,0)`). Checked against `vtoa _dt` (L43222): `vtoa(0,+229) = 0`, `vtoa(0,-229) = 4`.
- `pfgoal` = `$62` bit 7 of an object. A skater with pfgoal = 1 attacks the +Y net; the goalie of that team (pfgoal = 1) defends the -Y net (`goalie.md`).
- `randomd0(n)` returns 0..n-1. `randomd0s(n)` = `randomd0(2n) - n`. HV counter = `VDP_CNTR` ($C00008).

---

## 1. Overview

### 1.1 The two modes

- **Penalty shot (PS)**, in a regular game. A checking foul on a skater who has the breakaway bit (`$64` bit 1) is turned by `PenShotChk` into a penalty-shot "variant" id (PenaltyList minutes byte = $FF). `getBAplayerInfo` sets `BA_PS_flags` bit 3 and records the players. The stoppage is called and presented as usual. The variant is never assessed, so nobody goes to the box. When the presentation ends, `InProgress` gives the puck assignment `$1E` (`puckshootout`) instead of `$1B` (`puckfaceoff`). One attempt is played, then the game resumes with a normal faceoff.
- **Shootout (SO)**, the main-menu play mode `OptPlayMode == 4`. `GameSetUp` turns it into `OptPlayMode = 0` plus `word_FFC2FA` bit 0, and calls `sub_FC47C` (shootout init). The whole game is a sequence of attempts that use the same machinery. `puckfaceoff` always redirects to `$1E`. The game clock never runs, and there are no periods. The game ends when `sub_FC516` finds a winner. The next `puckshootout` then jumps straight back to the menus.

Both modes set `BA_PS_flags` bit 2 for the duration of an attempt. Most game code tests only that bit ("PS or SO"). Shootout-only behaviour tests `word_FFC2FA` bit 0.

### 1.2 Frame-by-frame flow of one attempt

```
(PS) foul: PenShotChk -> AddPenalty(variant) -> ... InProgress finish: BA_PS.3 ? $1E : $1B
(SO) StartPer: puck = $1E. Every later puckfaceoff call: puck = $1E.

frame A    puck $1E puckshootout, first call (pfna set):
           SO: sub_FC4C0 (game over -> menus; else next shooter/goalie); PS: team.$360 += 1
           clear BA_PS 2,4,5,6; C2F8.1 = 1; music; gmode.0 = 1; C2FA.1 = 1;
           puck vel = 0; word_FFD454 = 25; ReturnGoalies
           (every call) BA_PS.2 = 1; sub_EE58 picks the shooter; check the goalie;
           assreplace($1F)   (failure: BA_PS.2 = 0, assreplace($1B))
frame A+1  puck $1F puckpenshot, first call: screen/puck/nets reset, ResetBench, SetPersonel +
           sub_1592C per team, resetplstuff, park the 10 non-participants, place the shooter
           (0,±16) and goalie (0,∓250), give pads, goalie = $0E, BA_PS.7 = 1, intro timer
           word_FFC31A = 400 (100 if no pad is in use)
frame A+2  chkprogress: BA_PS.7 -> intro text (sub_187B8 / loc_FC320), C2FA.7 = 1
           puck $1F second call: C2FA.2 = 1, puck -> $18 pucknorm
A+3 ...    chkprogress: word_FFC31A -= 1 per frame. Pad input cuts it to 2.
           CPU shooter waits in asspuckc while word_FFC31A > 1.
           word_FFC31A reaches -1: intro box erased, C2FA.7 = 0 -> the VBlank runs the 25 s clock
           pucknorm -> sub_F2F4 every frame (attempt over?)
           CPU shooter: asspuckc -> sub_FE864 (waypoints) every frame,
                        sub_FE8EC (shoot?) on decision frames -> compshoot -> assshoot
           shot/pass press (SetShotMode / setpassmode): BA_PS.5 = 1, C2FA.2 = 0 (clock frozen),
                        word_FFC31C = 100 (release/rebound countdown)
end        goal (checkgoal PS branch): SO goal counter += 1, byte_FFC2FE.0 = 1, sub_F37C,
                        normal goal handling, AddPenalty2($E PenGoal)
           otherwise sub_F2F4: BA_PS.6 = 1, AddPenalty2($A PenWhistle), falls into sub_F37C
           sub_F37C: freeze camera, gmode.0 = 1, C2FA.2 = 0, clear BA_PS 2-6, restore the
                     shooter's $61, sub_FC516 (SO alternation / rounds / winner)
           presentation -> InProgress finish -> $1B puckfaceoff
           PS: normal faceoff (center after a goal, otherwise the spot of the original call)
           SO: puckfaceoff -> $1E -> next attempt, or game over
```

### 1.3 Globals

| ROM name | Address | Size | Port name | Meaning |
|---|---|---|---|---|
| `BA_PS_flags` | `$FFC2F2` (confirmed) | byte (word var) | `ba_ps_flags` | see 1.4 |
| `word_FFC2FA` | `$FFC2FA` (confirmed) | byte (word var) | `f_c2fa` | see 1.4 |
| `word_FFC2F4` | `$FFC2F4` (confirmed) | byte | `f_c2f4` | bit 0 goal just scored; bit 5 (`C2F4_PS_GOAL`) = PS/SO goal (stat and "no assists" display flag) |
| `word_FFC2F8` | `$FFC2F8` (confirmed) | byte | | bit 1 = one-timer catch box (set by `puckshootout`, see 3.1) |
| `byte_FFC2FC` | `$FFC2FC` | byte | | bit 3 = CPU script: last waypoint loaded; bit 7 = PS/SO display flag (set by `puckshootout`, cleared by a normal `puckfaceoff`) |
| `byte_FFC2FE` | `$FFC2FE` | byte | | bit 0 = next faceoff at center (set by a PS/SO goal) |
| `BA_Team` | `$FFD404` (confirmed) | word | | shooting team, 0 home / 1 away |
| `BA_Sktr_SCnum` | `$FFD406` (confirmed) | word | `ba_sktr` | shooter's object. getBAplayerInfo writes the fouled object; `sub_EE58` overwrites it with 0 (home) or 6 (away) |
| `BA_Goalie_SCnum` | `$FFD408` (confirmed) | word | `ba_goalie` | goalie's object |
| `BA_Skater_Offset` | `$FFD40A` (confirmed) | word | | shooter's roster slot (pnum) |
| `BA_Goalie_Offset` | `$FFD40C` (confirmed) | word | | goalie's roster slot at the time of the foul (written, never read) |
| `BA_Checker_Offset` | `$FFD40E` (confirmed via `sub_187B8`) | word | | offender's roster slot (intro text "... by <name>") |
| `word_FFD410` | `$FFD410` (confirmed) | word | | PS variant id (intro text) |
| `word_FFC31A` | `$FFC31A` (confirmed) | word | `ps_intro` | intro countdown, per frame |
| `word_FFC31C` | `$FFC31C` (confirmed) | word | `ps_timer` | release/rebound countdown after the shot/pass press, per frame |
| `byte_FFC31E` | `$FFC31E` (confirmed) | byte | | the shooter object's `$61` (newpnum), saved by `sub_1592C`, restored by `sub_F37C` |
| `word_FFD454` | `$FFD454` (confirmed) | word | (new: `ps_clock`) | attempt clock, seconds left (set to 25) |
| `word_FFD456` | `$FFD456` | word | (new: `ps_clock_frac`) | its fraction (-$AAA per vblank). Never reset. |
| `word_FFD574` / `word_FFD576` | `$FFD574` / `$FFD576` | word | `shootout_goals[0]` / `[1]` | SO goals, home / away (also counted on regular-game PS goals, see Q4) |
| `word_FFD578` | `$FFD578` | word | (new: `so_round`) | SO round number, 1-based |
| `word_FFD586` | `$FFD586` | word | (new: `so_shooter_idx`) | SO shooter index 0..4 |
| `word_FFD594` | `$FFD594` | word | `shootout_side` | SO side to shoot: 0 home, 1 away |
| shooter lists | `$FFD57A` (home), `$FFD588` (away) | 6 words each | (new: `so_list[2][6]`) | roster slots: [0..4] shooters, [5] goalie (see 1.5.5) |
| `byte_FFD585` / `byte_FFD593` | low bytes of `$FFD584` / `$FFD592` | byte | | SO goalie slot, home / away (= list entry [5]) |
| `word_FFDA12` | `$FFDA12` | word | (new: `ps_path`) | CPU script path 0..6 |
| `word_FFDA14` | `$FFDA14` | word | (new: `ps_wp_idx`) | waypoint index (starts at -1) |
| `word_FFDA16` / `word_FFDA18` | `$FFDA16` / `$FFDA18` | word | (new: `ps_wp_x/ps_wp_y`) | current waypoint (attack-top frame). High byte of `DA16` == $80 = path finished |
| `word_FFDA1A` | `$FFDA1A` | word | `ps_script_dir` | CPU shot direction (passdir) of the path |
| `word_FFDA1C` | `$FFDA1C` | word | (new: `ps_shoot_tol`) | CPU shoot tolerance, pixels |
| `word_FFDED0` | `$FFDED0` | word | `so_replay_stop` | SO winner celebration countdown (assscore) |
| `word_FFDEF0` | `$FFDEF0` | word | | replay frames still recorded after a PS ends (10) |
| `cont1team` / `cont2team` | `$FFC328` / `$FFC32A` (confirmed) | word | `cont_team[0/1]` | 0 none, 1 home, 2 away |
| `c1playernum` / `c2playernum` | | word | | object each pad drives |
| `word_FFD05A` / `word_FFD05C` | | word | | Auto Goalie flag, home / away team (copy of `OptGoalie`, both equal) |
| `OptPen` | `$FFD056` (confirmed) | word | | 0 = penalties off: no penalty shots |
| `gmode` | `$FFC2EA` (confirmed) | byte | `gmode` | bit 0 clock stopped (set for the whole attempt), bit 1 gmdir, bit 3 gmpendel |
| `sflags2` | `$FFC2EE` (confirmed) | byte | | bit 2 = replay recording off |
| `puckx/pucky/puckvx/puckvy/puckc` | `$FFB74A/$FFB75E/$FFB772/$FFB774/$FFB7AA` (confirmed) | word | | puck = object 14 at `$FFB74A`; puck `$62` = `$FFB7AC` |
| `passdir` | `$FFBEDC` (confirmed) | word | | shot/pass direction |

### 1.4 Bit maps

**`BA_PS_flags` (`$FFC2F2`)**

| bit | port const | set by | cleared by | meaning |
|---|---|---|---|---|
| 0 | | | doinput goalie save | manual-goalie scratch (input spec) |
| 1 | | doinput goalie skate | doinput | manual-goalie scratch (input spec) |
| 2 | `BA_LIVE` | `puckshootout` (every call) | `puckshootout` (first call, then set again; and on failure), `sub_F37C`, `puckfaceoff2` | attempt active (PS or SO) |
| 3 | `BA_AWARDED` | `getBAplayerInfo` | getBAplayerInfo/PenShotChk failure, `sub_F37C`, `checkgoal` L49920 | penalty shot awarded: `InProgress` gives `$1E` |
| 4 | `BA_GOALIE_HELD` | `sub_F2F4`; CPU goalie hold timer (`assgoaliecpu` L39187-39189). `assgoaliectrl` L39041-39043 has the same code but it sits behind a `gmode` bit 0 exit, so it never fires during an attempt. | `puckshootout`, `sub_F37C` | **attempt over** (any cause; the port name is narrower than the ROM meaning) |
| 5 | `BA_STARTED` | `SetShotMode`, `setpassmode` (test-and-set) | `puckshootout`, `sub_F37C`, `puckfaceoff2` | the one shot/pass of the attempt has been pressed |
| 6 | | `sub_F2F4` | `puckshootout`, `sub_F37C`, `InProgress` finish | attempt-over whistle already queued |
| 7 | | `puckpenshot` | `chkprogress` | intro text request |

**`word_FFC2FA` (`$FFC2FA`)**

| bit | port const | set by | cleared by | meaning |
|---|---|---|---|---|
| 0 | `C2FA_SHOOTOUT` | GameSetUp (L962440) | `sub_FD73C` (game setup) | shootout game |
| 1 | | `puckshootout` first call | `puckfaceoff` first call (never runs in SO) | attempt clock mode: the VBlank decrements `word_FFD454`, not `gameclock` |
| 2 | | `puckpenshot` second call | `SetShotMode`, `setpassmode` (PS/SO), `sub_F37C` | clock runs although `gmode` bit 0 is set |
| 3 | | `sub_FC516` (winner found) | `sub_FC47C` | shootout decided |
| 4 | `C2FA_BREAKAWAY` | `doshot` | `checkgoal`, `updateplayers` | breakaway-shot stat flag (not PS-specific) |
| 5 | | `sub_F2F4` | `SetShotMode`, `setpassmode` | puck has left the shooter's stick after the press |
| 7 | `C2FA_PS_INTRO` | `sub_187B8` | `puckshootout` first call, `chkprogress` | intro text up: attempt clock frozen, pad input skips the intro |

### 1.5 Tables (full dumps)

#### 1.5.1 `unk_1913A` (L57492, ROM `$1913A`), 24 words, read by PenShotChk with `d0` = id (byte offset)

| id | value | | id | value |
|---|---|---|---|---|
| $00..$12 | $FFFF | | $1C Cross Check | $002E ("Hooking" variant) |
| $14 | $0038 ("Charging" variant) | | $1E Hooking | $0030 ("Tripping" variant) |
| $16 Charging | $003C ("Slashing" variant) | | $20 Tripping | $0034 ("Interference" variant) |
| $18 Slashing | $0036 ("Roughing" variant) | | $22..$2E | $FFFF |
| $1A Roughing | $003A ("Cross Check" variant) | | | |

The shift by one entry is quirk Q1 of `rules_clock_penalties.md`. Only the intro text and `RefPen` show it.

#### 1.5.2 CPU path tables (pointer list `unk_FE788`, L974280, ROM `$FE788`)

Seven long pointers: `$FE7A4, $FE7B0, $FE7C0, $FE7CC, $FE7D8, $FE7E4, $FE7F0`, indexed by `word_FFDA12` (0..6). Each path is a list of 4-byte waypoints (word X, word Y) in the **attack-top frame** (shooter attacking +Y). The last waypoint is followed by a 4-byte terminator: byte `$80`, byte `tol`, word `dir`.

| path | ROM | waypoints (X, Y) decimal | terminator: tol (`word_FFDA1C`), dir (`word_FFDA1A`) |
|---|---|---|---|
| 0 | `$FE7A4` | (16, 226), (16, 208) | `$80 $20 $0005`: tol 32, dir 5 |
| 1 | `$FE7B0` | (-55, 160), (-1, 200), (-32, 208) | `$80 $20 $0005`: tol 32, dir 5 |
| 2 | `$FE7C0` | (-80, 64), (26, 188) | `$80 $20 $0005`: tol 32, dir 5 |
| 3 | `$FE7CC` | (-50, 88), (20, 208) | `$80 $2C $0005`: tol 44, dir 5 |
| 4 | `$FE7D8` | (-50, 8), (32, 208) | `$80 $28 $0006`: tol 40, dir 6 |
| 5 | `$FE7E4` | (28, 244), (8, 224) | `$80 $20 $0006`: tol 32, dir 6 |
| 6 | `$FE7F0` | (-26, 248), (0, 224) | `$80 $20 $0002`: tol 32, dir 2 |

Raw bytes `$FE788-$FE7FB`:
```
000F E7A4 000F E7B0 000F E7C0 000F E7CC 000F E7D8 000F E7E4 000F E7F0
0010 00E2 0010 00D0 8020 0005
FFC9 00A0 FFFF 00C8 FFE0 00D0 8020 0005
FFB0 0040 001A 00BC 8020 0005
FFCE 0058 0014 00D0 802C 0005
FFCE 0008 0020 00D0 8028 0006
001C 00F4 0008 00E0 8020 0006
FFE6 00F8 0000 00E0 8020 0002
```
When the terminator itself is loaded as a waypoint, `DA16 = $80tt` and `DA18 = dir`. Its `+4` byte is the first byte of the next path (or `$48` of code after path 6), never `$80`.

#### 1.5.3 `passdirlist` (L974252, ROM `$FE744`), 9 words, used for a bottom-net shooter

`0, 7, 6, 5, 4, 3, 2, 1, 8`: the left-right mirror of passdir (`d -> (8-d) & 7` for 0..7, 8 -> 8). Path dirs map 5 -> 3, 6 -> 2, 2 -> 6.

#### 1.5.4 `shotsets` (L37697, ROM `$C542`), (x offset, z) per passdir, used by `doshot`

| passdir | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 |
|---|---|---|---|---|---|---|---|---|---|
| x | 0 | 16 | 16 | 16 | 0 | -16 | -16 | -16 | 0 |
| z | 12 | 12 | 6 | 0 | 0 | 0 | 6 | 12 | 6 |

The aim point is (x, ±$108) at height z. The scripted shots use dirs 2, 3, 5 and 6: low or mid shots at a post.

#### 1.5.5 Shootout shooter lists (RAM)

`sub_FC570` fills them from line 1 of the team's line table (`LN = T + word[T+6]`, bytes G, LD, RD, LW, C, RW are 1-based roster slots, see `data_attributes.md` 1.4). It writes each `slot-1` as a word, **backwards** from the list end:

| entry (word index) | home address | away address | default content |
|---|---|---|---|
| 0 (shooter 1) | `$FFD57A` | `$FFD588` | RW |
| 1 | `$FFD57C` | `$FFD58A` | C |
| 2 | `$FFD57E` | `$FFD58C` | LW |
| 3 | `$FFD580` | `$FFD58E` | RD |
| 4 | `$FFD582` | `$FFD590` | LD |
| 5 (goalie) | `$FFD584` (`byte_FFD585`) | `$FFD592` (`byte_FFD593`) | G |

The "Shootout SetUp" menu (ROM `$FC620`..., uses `word_FFD5B8` 0..5 as the cursor) edits these 6 entries. That menu is out of scope.

#### 1.5.6 `_alist` (Setplass, L51542)

Position 0..6 -> `$0E assgoaliecpu, $02, $02, $03, $05, $03, $05`, terminated by `$FF`. `Setplass` returns without a change when `$34 < 0`.

#### 1.5.7 Dead data after `puckpenshot` (ROM `$F2C0-$F2F3`, L41500-41555)

An unreferenced byte-for-byte copy of the faceoff tables `_apl` (`$FCEE`, 24 bytes) and `_ptab` (`$FD06`, 28 bytes): `00 01 02 03 04 05 06 00 | 00 01 05 03 04 02 00 00 | 00 03 05 01 04 00 00 00 | 0000 FF06 FFDD FFCE 0023 FFCE FFCE FFF6 0000 FFF1 0032 FFF6 0000 FFC4`. No code reads it. Do not port it.

#### 1.5.8 Intro texts (display only)

- PS (`sub_187B8`, ROM `$187B8`): framed box: "PENALTY SHOT!" (big, `unk_18884`), then the shooter's name (`$66` of `BA_Sktr_SCnum`, team `BA_Team`), then the PenaltyList text of `word_FFD410`, " by " and the name of slot `BA_Checker_Offset` of the other team.
- SO (`loc_FC320`, L968689): "SHOOTOUT MODE" (big, `unk_FC466`), then `<shooter name of BA_Skater_Offset> vs. <goalie name>`, the home abbreviation with `word_FFD574` (3 digits), the away abbreviation with `word_FFD576`, and "Round " `word_FFD578` (2 digits).
- SO winner (`sub_FC5AE`, L968890, from `SetPA` when C2FA bits 0 and 3 are set): "SHOOTOUT WON BY" + the home team name if `FFD574 > FFD576` (signed), else the away team name.

---

## 2. Awarding a penalty shot

### PenShotChk (L46100-46130, ROM `$1211A`)
- Purpose: turn a foul on a breakaway skater into a penalty shot. Already summarised in `rules_clock_penalties.md` section 3. Port: `pen_shot_chk(id, victim)`.
- Callers: the checking code (`CCStart` body checks, holding/hooking, tripping, interference; see `collisions_checking.md`). In: `d0` = PenaltyList id, `a2` = fouled player, `a3` = offender. Out: `d0`. Saves and restores `d1-d3/a0`.
```
PenShotChk(id, a2, a3):
    if a2.$64 bit1 == 0: return id                 ; no breakaway
    if BA_PS_flags bit3: return id                 ; a penalty shot is already pending
    v = unk_1913A[id]                              ; word at byte offset id
    if v < 0 (bmi): return id
    getBAplayerInfo(d0 = a2.$52)
    ; movem.w (sp)+,d0-d1 does not touch the flags: the next bpl tests getBAplayerInfo's N
    if N == 1: clear BA_PS_flags bit3; return id
    word_FFD410 = v
    return v
```

### getBAplayerInfo (L46136-46185, ROM `$12174`)
- Caller: PenShotChk only. In: `d0` = fouled SCnum, `a3` = offender. Out: N flag (0 = success) and the BA globals. Saves `d1-d3/a1`.
```
getBAplayerInfo(d0, a3):
    if OptPen == 0: d1 = $FFFF; return N=1            ; bit3 untouched
    set BA_PS_flags bit3
    if d0 > 5 (signed): g = getGoalieSCnum(5)          ; fouled skater is away: home goalie
    else:               g = getGoalieSCnum($B)         ; away goalie
    if g < 0: clear BA_PS_flags bit3; return N=1       ; empty net: no penalty shot (N from tst.w g)
    BA_Sktr_SCnum     = d0
    BA_Team           = SortCords[d0].$62 bit6 ? 1 : 0
    BA_Skater_Offset  = $00xx, xx = SortCords[d0].$66  ; move.w #0 then move.b into the low byte
    BA_Goalie_SCnum   = g
    BA_Goalie_Offset  = $00xx, xx = SortCords[g].$66
    BA_Checker_Offset = $00xx, xx = a3.$66
    return N = bit7 of a3.$66                          ; 0 for every roster slot 0..25
```
`getGoalieSCnum(last)` scans `last, last-1, ..., last-5` and returns the first SCnum whose position word `$34 == 0`, else `$FFFF` (`goalie.md`).

### What happens to the variant (context; `rules_clock_penalties.md`)
The variant (minutes `$FF`) is queued by `AddPenalty` without `DelayedPen`/pflags2 bits. It is called or delayed like a penalty, presented without a ref animation (`SetPA` ignores ids >= `$2E`), and never assessed. `InProgress` finish (L46314-46325):
```
sub_123DE(home); sub_123DE(away); clear gmode bit2
a3 = puck; clear BA_PS_flags bit6
assreplace(BA_PS_flags bit3 ? $1E : $1B)
```

---

## 3. Attempt setup

### 3.1 puckshootout (puck assignment `$1E`, L41046-41165, ROM `$ECB6`)
- Callers: `asstab[$1E]` for the puck (a3 = puck, object 14). Assigned by `InProgress` finish (PS), `StartPer` (SO game start, L29869-29875) and `puckfaceoff` (SO, every faceoff, L41629-41636).
- Port: puck assignment `ASS_PUCKSHOOTOUT`.
```
puckshootout(a3 = puck):
  if bclr(a3.$62 bit1 pfna) was set:                     ; first call
      set byte_FFC2FC bit7                                ; display flag
      padcont = 0 (long); dword_FFBE7E = 0; dword_FFBE82 = 0   ; drop pad state
      clear word_FFC2FA bit7
      if word_FFC2FA bit0:                                ; shootout
          sub_FC4C0()                                     ; 7.2; may jmp to the menus (never returns)
      else:
          sub_FE756()                                     ; random CPU path (5.3)
          t = BA_Team ? AwShots : HmShots
          t.$360 += 1                                     ; penalty-shot attempts stat
      clear BA_PS_flags bits 2, 4, 5, 6
      set word_FFC2F8 bit1                                ; one-timer catch box until someone has the puck
      if gmode bit3 (gmpendel): goto Stop4Pen             ; bne.w, not a call: see Q12
      clear a3 pfna                                       ; already clear
      if word_FFC2FA bit0:
          if word_FFD594 != 0 or word_FFD586 != 0: goto clk   ; SO: music only for home's shooter 1
      HmTeam = HomeTeam; SongIndex = 2; ChooseSong; song(SongNum)
    clk:
      set gmode bit0                                      ; clock stopped for the whole attempt
      set word_FFC2FA bit1                                ; VBlank runs the attempt clock
      puckvx = 0; puckvy = 0
      word_FFD454 = $19                                   ; 25 seconds
      ReturnGoalies                                       ; pulled goalies back; CPU teams may re-pull (CPgoalie)
      st a3.$40; st a3.$42                                ; puck temps: high bytes = $FF
  ; every call
  set BA_PS_flags bit2
  if sub_EE58() returns N (no shooter):                   ; 3.2
      clear BA_PS_flags bit2; assreplace($1B puckfaceoff); return
  g = SortCords[BA_Goalie_SCnum]
  if g.$34 != 0 or g.$63 bit2:                            ; not a goalie any more, or unavailable
      d0 = BA_Goalie_SCnum
      repeat 6 times:                                     ; d2 = 6; subq; bmi -> fail
          d0 -= 1; if d0 < 0: d0 = 5                      ; wrap inside the same team:
          else if d0 == 5: d0 = $B                        ;   5..0 -> 5, 11..6 -> 11
          o = SortCords[d0]
          if o.$34 == 0 and o.$63 bit2 == 0: BA_Goalie_SCnum = d0; goto ok
      clear BA_PS_flags bit2; assreplace($1B); return     ; (the original object is the 6th try)
ok:
  a2 = HmShots (movea.w sign-extends $C6CE)               ; harmless
  assreplace($1F puckpenshot)
```
Notes:
- The non-first-call path (pfna clear) only re-runs the shooter pick and goalie check. It is reached only after the `Stop4Pen` exit, because `assreplace($1F)` always ends the first call.
- `word_FFC2F8` bit 1 makes `checkpuckcoll` use the one-timer catch box (`ChkBodyG = $C`, `ChkBodySqG = $90`) until `updateplayers` sees `puckc >= 0` (L35364). The shooter's first pickup uses that box.
- `sub_EE58` and `sub_FE756` run with `a3 = puck`. This matters for the waypoint mirroring (Q2).

### 3.2 sub_EE58 (L41167-41274, ROM `$EE58`): pick the shooter
- Caller: `puckshootout`. Out: **N flag** only (N=1 = no shooter), plus `BA_Skater_Offset` and `BA_Sktr_SCnum`. All registers are restored (`movem.l (sp)+` keeps the flags of the final `move.w #1,d0` / `move.w #$FFFF,d0`). The `a3` it loads is discarded.
```
sub_EE58():
  T = BA_Team ? AwShots : HmShots
  best = -1 (d6); pick = -1 (d5)
  rec = T.$1E (team data); rec += word[rec]               ; player list P0
  for slot = 0 .. 25:
      if word[rec] == 2: break                            ; end of list
      attrs = rec + word[rec]                             ; skip the name
      if (attrs[5] & $F) <= 1 (signed byte compare): goto next   ; Shot Accuracy <= 1 (all goalies)
      if word_FFC2FA bit0: goto chosen                    ; SO: keep BA_Skater_Offset from sub_FC4C0
      td = T.tmpdst[slot] ($66 + 2*slot)
      if td != $FFFE and td != $FFFF: goto next           ; must be on the bench (-2) or on ice (-1)
      s = (A1&$F) + (A2&$F) + (A2>>4) + (A3&$F) + (A3>>4) + (A5&$F) + (A5>>4) + (A6>>4) + (A7>>4)
          ; agility, off. awareness, speed, shot power, def. awareness, shot accuracy,
          ; stick handling, endurance, pass accuracy (data_attributes.md 1.3)
      if slot == BA_Skater_Offset: s = $7FFF              ; the fouled player always wins if eligible
      if s >= best (signed): best = s; pick = slot        ; ties go to the later slot
    next:
      rec = attrs + 8
  if pick < 0: return N=1
  BA_Skater_Offset = pick
chosen:
  BA_Sktr_SCnum = BA_Team ? 6 : 0
  return N=0
```
- In SO the loop exits at the first record with Shot Accuracy > 1 (normally slot 1). It fails only if no such record exists.
- PS: injured (-3/-4) and penalized (>= 0) players cannot shoot. If the foul injured the fouled player, the best other skater shoots.

### 3.3 puckpenshot (puck assignment `$1F`, L41276-41499, ROM `$EF92`)
- Caller: `asstab[$1F]` for the puck, after `puckshootout`. Two calls: setup (pfna set), then the hand-off to `pucknorm`.
```
puckpenshot(a3 = puck):
  if bclr(pfna) was clear:                                ; second call (loc_F2A8, L41493)
      set word_FFC2FA bit2                                ; attempt clock may run (it is still frozen by bit7)
      assreplace($18 pucknorm)
      puckvx = 0; puckvy = 0                              ; a3.$28/$2A
      return
  save all registers
  forceblack; wait while disflags bit0
  if crowdlevel > $258 (unsigned): crowdlevel = $258; CwdExciteLvl += $14
  sub_11738(a2 = unk_5C410, d4 = ExtraChars)              ; graphics
  set disflags bit3 (clock redraw); clear sflags bit0 (pause); clear sflags3 bit0
  glovecords = 0; iflags.b = 0; st RefCnt (high byte); clear sflags2 bit1; st passplayer
  ClrHor                                                  ; back to vertical mode
  Vpos = 0; Hpos = 0
  puckx = 0; pucky = 0; puckz = 0; puckvx = puckvy = puckvz = 0; st puckc
  net 12 ($FFB64A): X = 0, Xvel = Yvel = 0, Y = $10C      ; nets back in place
  net 13 ($FFB6CA): X = 0, Xvel = Yvel = 0, Y = $FEF4
  puck shadow (object 15, $FFB7CA): frame ($06) = $18A, SPA ($58) = 0, attribute ($04) = 0
  word_FFB74E (puck attribute) = 0
  clear sflags bit6 (camera unlock)
  checkwindow x 101                                       ; dbf from $64: settle the camera
  yleader = $3C
  ResetBench                                              ; all non-box, non-injured tmpdst -> -2
  a2 = HmShots: SetPersonel; sub_1592C                    ; 3.4
  a2 = AwShots: SetPersonel; sub_1592C
  resetplstuff                                            ; for all 12: clr.b $63 (also clears the
                                                          ; unavailable bit sub_1592C just set, Q9);
                                                          ; if $34 >= 0: SetSPA($50C), $32 = 0,
                                                          ; $5E.b = 0, $62 &= $C2
  push a3
  for d2 = 11 down to 0 (a3 = SortCords[d2]):
      if d2 == BA_Sktr_SCnum:                             ; shooter
          if a3.$34 < 0 and bclr(a3.$63 bit2) was set:    ; dead: sub_1592C set $34 = 4
              setplayer(d3 = a3.$66)
          X = puckx - 0
          if pfgoal == 0: Y = pucky + 16; facedir ($54) = 4   ; attacks -Y, starts on the +Y side
          else:           Y = pucky - 16; facedir = 0
          Xvel = Yvel = Zvel ($28,$2A,$2C) = 0
          assinsert($11 assnearest)                       ; skate to the puck
      else if d2 == BA_Goalie_SCnum:                      ; goalie
          if word_FFC2FA bit0:                            ; SO: the list goalie
              a3.$66 = byte_FFD593                        ; away goalie when home shoots
              if word_FFD594 != 0: a3.$66 = byte_FFD585   ; home goalie when away shoots
              setplayer(d3 = a3.$66)                      ; if that slot's tmpdst is -2 (not the slot
                                                          ; sub_1592C just set to -1), setplayer
                                                          ; inserts assben; assreplace($0E) below
                                                          ; replaces it
          else if a3.$34 < 0 and bclr(a3.$63 bit2) was set:   ; dead: $34 = 0 here
              setplayer(d3 = a3.$66)
          clear a3.$63 bit2
          X = 0
          Ytmp = (pfgoal == 1) ? $E5 : $FF1B              ; +229 / -229: the WRONG end (Q8)
          Y = Ytmp; Xvel = Yvel = 0; Zpos ($18) = 0
          facedir = vtoa(puckx - 0, pucky - Ytmp)         ; = vtoa(0, -Ytmp): faces away from center
          clear a3.$63 bit2; clear pfalock ($62 bit5)
          SetSPA($50C)
      else:                                               ; the 10 others
          X = $FF10 (-240); Y = 0; frame ($06) = 0
          assinsert($20 assgoaliebreakwait)
  SprSort
  pop a3 (puck)
  setchgplayer                                            ; 3.6: pads get the nearest participant
  g = SortCords[BA_Goalie_SCnum]
  g.X = 0
  g.Y = (g.pfgoal == 1) ? $FF06 : $FA                     ; -250 / +250: the defended net
  t = (g.$62 bit6) ? 2 : 1                                ; goalie's team as a cont value
  if cont1team == t: setc1player(BA_Goalie_SCnum)
  else if cont2team == t: setc2player(BA_Goalie_SCnum)
  a3 = g; assreplace($0E assgoaliecpu)                    ; (human goalie: branches to assgoaliectrl)
  set BA_PS_flags bit7                                    ; intro text request
  set sflags2 bit2                                        ; no replay recording during the intro
  word_FFC31A = $190                                      ; 400 frames
  if cont1team == 0 and cont2team == 0: word_FFC31A = $64 ; 100 frames (CPU vs CPU, demo)
  palcount = $18
  restore registers; return
```
Result on the ice:
- Shooter: object 0 (home) or 6 (away), roster slot `BA_Skater_Offset`, position 4. Starts at (0, ±16), 16 px behind the puck, facing the attacked net. Assignment stack: `assnearest` on top of `Setplass(old position)`.
- Goalie: object `BA_Goalie_SCnum`, position 0, at (0, -250) for pfgoal = 1 or (0, +250) for pfgoal = 0. Assignment `$0E`. Initially faces his own boards (Q8).
- Everyone else: X = -240, assignment `$20` twice (`sub_1592C` replaced and `puckpenshot` inserted), parked at Y = ±401 by `assgoaliebreakwait`.
- Puck at (0, 0), loose.

### 3.4 sub_1592C (L51401-51440, ROM `$1592C`): one team's roles
- Caller: `puckpenshot` (twice, `a2` = team struct, after `SetPersonel`, which computed `$60`/`$61` (newpos/newpnum) for each object). Saves `d0-d5/a0-a3`.
```
for the team's 6 objects a3 (from a2.$22):
    if a3.$52 == BA_Sktr_SCnum:
        Setplass                                          ; uses the OLD $34 (Q11)
        byte_FFC31E = a3.$61                              ; save SetPersonel's choice
        a3.$61 = low byte of BA_Skater_Offset
        a3.$34 = 4
        goto put
    else if a3.$52 == BA_Goalie_SCnum:
        Setplass
        a3.$34 = 0
put:    d3 = zero-extended a3.$61
        a2.tmpdst[d3] = $FFFF                             ; on ice
        setplayer(d3)                                     ; tmpdst is -1 now: no assben/assepen insert
    else:
        set a3.$63 bit2 (unavailable)                     ; wiped by resetplstuff right after (Q9)
        assreplace($20)
    st a3.$61; st a3.$60                                  ; no pending line change
```

### 3.5 assgoaliebreakwait (assignment `$20`, L38175-38202, ROM `$CAE0`)
Already in `goalie.md`:
```
if pfalock: return
if BA_PS_flags bit2 == 0 and word_FFC2FA bit0 == 0: assexit; return
Xvel = 0; Yvel = 0
Y = (SortCords[BA_Goalie_SCnum].pfgoal == 1) ? $191 : $FE6F      ; +401 / -401
```
The parked players sit behind the end the shooter starts from, beyond the boards. X stays -240. Between shootout attempts they stay parked. After a regular-game PS they `assexit` twice (two `$20` entries) back to their normal assignment.

### 3.6 Who controls what (pads)

1. `setchgplayer` (L42370): `c1playernum = c2playernum = -1`. Then, for each pad in use (`cont1team`, `cont2team`; pads 3/4 through the swap code), `changeplayer` -> `chgplayer` (L976652).
2. `chgplayer` in PS/SO (L976687-976698): of the pad's team's 6 objects, a candidate must have `$34 > 0`, `$63` bit 2 clear, not be driven by another pad (`pfjoycon`), **be `BA_Sktr_SCnum` or `BA_Goalie_SCnum`**, not have pfalock, and not be the other pad's player. The nearest one to the lead-adjusted puck wins.
   - Shooting team's pad: the shooter (the goalie has `$34 = 0`, so he is never a candidate).
   - Defending team's pad: no candidate. The result is the caller's `d6` (UNRESOLVED U1). Step 3 overrides it for one pad.
   - Two pads on the shooting team: the second pad finds no candidate either (the shooter belongs to pad 1).
3. `puckpenshot`: if `cont1team` is the goalie's team -> `setc1player(BA_Goalie_SCnum)`. **Else** if `cont2team` is -> `setc2player(...)`. Only one pad gets the goalie.
4. `setcNplayer` -> `restorep1` (L37335): the old object loses `pfjoycon` (and gets pfna unless `$64` bit 3). Because `BA_PS_flags` bit 2 is set, the new object goes through **`chkgoalie`** (L37366):
```
chkgoalie(new):
    if new.$34 != 0: set new.pfjoycon; return new                  ; the shooter
    auto = (new.$62 bit6) ? word_FFD05C : word_FFD05A              ; indexed by TEAM
    if auto == 0: set new.pfjoycon; return new                     ; Manual Goalie: human goalie
    return (new.$62 bit6) ? 6 : 0                                  ; Auto Goalie: pad points at object 0/6,
                                                                   ; no pfjoycon anywhere: CPU goalie
```
   The stored `cNplayernum` is the returned value. With Auto Goalie the defending human drives nothing. `doinput` is still called for object 0/6 (`updateplayers` matches `cNplayernum`), so that pad can still pause and skip the intro. Without `pfjoycon`, `doinput` returns before any movement.
5. During the attempt:
   - Human shooter: B (switch player) is ignored (`doinput`, `BA_PS_flags` bit 2 -> `loc_B42E`). C = shot (`SetShotMode`), B = pass and A = flip pass (`setpassmode`). Only the first of these per attempt does anything (5.8).
   - Human goalie: the normal goalie controls. A B tap with Manual Goalie calls `changeplayer`. That finds no candidate, and with `d6` = current SCnum it runs `Sweepcheck` on the goalie (input spec; Q13).
6. In SO the teams alternate, so a human drives his team's shooter on his team's turns and his goalie (or nothing, with Auto Goalie) on the other team's turns.

---

## 4. Intro and clocks

### 4.1 chkprogress PS branch (L46014-46063)
Runs every frame from `PenaltyManager` (`periodiceevents`), before `updateplayers`.
```
chkprogress():
  if BA_PS_flags bit2:
      if BA_PS_flags bit7:
          sub_187B8()                         ; set word_FFC2FA bit7; draw the PS / SO intro box (1.5.8)
          clear BA_PS_flags bit7
          return
      if word_FFC31A >= 0:
          word_FFC31A -= 1                    ; per frame
          if word_FFC31A >= 0: return
          ; reached -1
          clear sflags2 bit2                  ; replay recording back on
          clear word_FFC2FA bit7              ; attempt clock unfrozen
          erase the box (eraser: d0 = $1B, d1 = 8, or $C in SO, d2 = $7FF)
          return
  ; normal stoppage processing (gmpen / Pencntdwn / InProgress)
```
While the intro runs, stoppage processing (`_cont`) is skipped. After it, whistles queued during the attempt are processed normally.

### 4.2 Intro skip: sub_FE1AA (L973204-973222)
Called from `doinput` step 2 (input spec) when `word_FFC2FA` bit 7 is set and the pad byte `d0.b != 8` (any direction or held button):
```
if cont2team == 0 or a3.$52 == puckc:
    if word_FFC31A > 2 (signed): word_FFC31A = 2
```
The intro then ends 3 frames later. With one pad, any input from that pad skips it, even from the defending side.

### 4.3 CPU shooter wait
`asspuckc` (L39911): if `BA_PS_flags` bit 2 and `word_FFC31A > 1` (signed) -> return, before any decision or movement. The shooter coasts (no `doplayeracc`). `assnearest` has no such wait, so the CPU shooter picks the puck up during the intro. A human shooter may skate, shoot or pass during the intro. The attempt clock is frozen then, but `word_FFC31C` and the goalie checks are live.

### 4.4 VBlank attempt clock (loc_15D9A, L51766-51830)
```
if sflags bit0 (paused): skip
if word_FFC2FA bit2 == 0 and gmode bit0: skip               ; bit2 is cleared at the shot/pass press:
                                                            ; the attempt clock freezes there
if word_FFC2FA bit1:                                        ; attempt clock instead of gameclock
    if word_FFD454 == 0: skip
    word_FFD456 -= $AAA; if no borrow: skip                 ; 1 tick per 65536/2730 = 24.006 vblanks
    set disflags bit3
    if word_FFC2FA bit7: skip                               ; intro up: tick absorbed, value kept
    word_FFD454 -= 1
    skip
(gameclock path, not used during an attempt)
skip: vcount += 1; MusicVB
```
- The fraction `word_FFD456` is never reset, so the first second of an attempt lasts 1..24 vblanks.
- During the intro the fraction keeps borrowing but no second is taken.
- `showclock` (L52402-52404) displays `word_FFD454` instead of `gameclock` while bit 1 is set. `PrintScores1` shows a blank period label (`unk_191F8` index 4).
- `gameclock` never runs during an attempt. In SO bit 1 is never cleared (the `puckfaceoff` body never runs), so `gameclock` never runs at all and the period never ends.

---

## 5. During the attempt

### 5.1 Puck handling restrictions
- `checkpuckcoll` (L50306-50312): while `BA_PS_flags` bit 2 is set, only `BA_Sktr_SCnum` and `BA_Goalie_SCnum` can collide with or pick up the puck.
- `ChkOffsides` (L42601), `checkob` (L40497), `BreakawayOffsidesFlagSet` callers, `check4bench` (L37840) and the asspuckc breakaway code return early or are skipped while `BA_PS_flags` bit 2 is set.
- `assnearest` (L40760-40765): while bit 2 is set and bit 5 is clear, it ignores `gmode` bit 0 (keeps skating). After the shot/pass press (bit 5), a CPU non-carrier with `gmode` bit 0 set goes to `assnothing`: the CPU shooter does not chase his rebound.
- `assgoaliecpu` (`goalie.md`): step 13 does not stop on `gmode` bit 0 when bit 2 is set. Step 15 sets `BA_PS_flags` bit 4 instead of `AddPenalty2(8)` when the hold timer runs out. Step 32 skips the early-save shortcut in PS/SO.
- `assgoaliectrl` (L38963-39050): its out-of-range whistle and hold timer require the clock running, so they never fire during an attempt. `sub_F2F4` ends the attempt as soon as the goalie has the puck.

### 5.2 asspuckc for a CPU shooter (L39901-40045; full spec in `ai_puckcarrier.md`)
In PS/SO, the decision step is:
```
if sub_FE8EC() returns Z = 1: compshoot()      ; never returns here
; Z = 0: no pass check, go to movement
```
The movement step runs every frame:
```
(d0, d1) = _postab2 entry                       ; never used in PS/SO (overwritten, or we return)
(d0, d1) = sub_FE864()                          ; raw waypoint (attack-top frame)
if high byte of word_FFDA16 == $80: return      ; path finished: no skateto, no doplayeracc
if pfgoal == 0: d0 = -d0; d1 = -d1
skateto(d0, d1, callback = rts)                 ; no evasion callback
```
The decision runs only when `temp1.b` (reload `aioff $6A`, -1 with own goalie pulled or crowd boost) expires. The movement runs every frame.

### 5.3 sub_FE756: script init (L974263-974278, ROM `$FE756`)
- Callers: `puckshootout` (PS), `sub_FC4C0` (SO). `a3` = puck. Saves all registers.
```
do: p = randomd0(7) while p > 6                 ; never repeats: uniform 0..6
word_FFDA12 = p
clear byte_FFC2FC bit3
word_FFDA14 = $FFFF
word_FFDA16 = 0
sub_FE7FC()                                     ; load waypoint 0 (mirror test on PUCK.$76 = 0: Q2)
```

### 5.4 sub_FE7FC: load the next waypoint (L974398-974427, ROM `$FE7FC`)
- Callers: `sub_FE756`, `sub_FE864`. Saves all registers.
```
if high byte of word_FFDA16 == $80: return           ; finished
word_FFDA14 += 1
e = path[word_FFDA12] + 4 * word_FFDA14
word_FFDA16 = word e[0]                               ; X
if a3.$76 bit0: word_FFDA16 = -word_FFDA16            ; neg.w; shooter lefty ($76 = 1) mirrors X
word_FFDA18 = word e[2]                               ; Y
if byte e[4] == $80:                                  ; next entry is the terminator
    set byte_FFC2FC bit3                              ; shoot zone armed
    word_FFDA1C = byte e[5] (zero-extended)           ; tolerance
    word_FFDA1A = word e[6]                           ; script shot direction
```
`$76` is the handedness byte (`setplayer`: roster A4 bit 0 XOR 1, so 1 = Lefty). The puck object's `$76` is 0: `defaultsprites2` clears every object at `setupice`, and only `setplayer` writes `$76`.

### 5.5 sub_FE864: waypoint target (L974429-974479, ROM `$FE864`)
- Port hook: `ps_waypoint(o)`. Caller: `asspuckc` movement step, every frame. In: `a3` shooter, `d0/d1` = caller's default target. Out: `d0/d1`. Saves `d2-d7/a0-a6`.
```
if high byte of word_FFDA16 == $80: return (d0, d1 unchanged)
tx = word_FFDA16; ty = word_FFDA18
if pfgoal == 0: tx = -tx; ty = -ty                    ; mirrored for the test only
dx = tx - X; if dx < 0: dx = -dx                      ; word, neg of $8000 stays $8000
still = (Xvel word == 0 and Yvel word == 0)
xok = still ? (dx <= 18) : (dx <= 10)                 ; signed; a stopped skater with dx > 18
                                                      ; falls to the 10 test and fails too
if xok:
    dy = |ty - Y|; yok = still ? (dy <= 18) : (dy <= 10)
    if yok: sub_FE7FC()                               ; advance (mirror test on THIS shooter's $76)
d0 = word_FFDA16; d1 = word_FFDA18                    ; RAW, not mirrored: asspuckc mirrors
return
```
After the last real waypoint is reached, the terminator is loaded: `DA16 = $80tt`, so the path is finished and asspuckc stops steering. For a lefty it becomes `-$80tt = $7Fxx`, so "finished" is never seen (Q1).

### 5.6 sub_FE8EC: shoot or not (L974481-974540, ROM `$FE8EC`)
- Port hook: `ps_should_shoot(o)`. Caller: `asspuckc` decision step (PS/SO). Out: **Z flag** (Z = 1 shoot). `d0` is restored by the final `movem.l`, so only the flags survive.
```
if word_FFC2FA bit1 == 0: return Z=0                  ; attempt clock not set up
if a3.$52 != puckc: return Z=0
if word_FFD454 <= 3 (signed): return Z=1              ; 3 seconds or less left
if high byte of word_FFDA16 == $80: return Z=1        ; path finished
if byte_FFC2FC bit3:                                  ; last waypoint (or a lefty's $7Fxx) loaded
    tx = word_FFDA16; ty = word_FFDA18
    if pfgoal == 0: tx = -tx; ty = -ty
    dx = |tx - X|; dy = |ty - Y|
    if dx > word_FFDA1C or dy > word_FFDA1C (signed): return Z=0
    return Z=1                                        ; inside the shoot box
if puckvx != 0 or puckvy != 0: return Z=0
if word_FFD454 < 15 (signed): return Z=1              ; puck still and less than 15 s left
return Z=0
```
The shoot box (32-44 px, both axes) is larger than the advance box (10 px moving), so a righty normally shoots on the first decision frame inside the box. If the box is crossed between two decision frames, the terminator is reached and the "finished" test fires on the next decision frame.

### 5.7 compshoot (L40316-40333) and assshoot
`compshoot` pops its own return address (`addq.w #4,sp`), so `asspuckc` ends there.
```
py = pucky; if pfgoal == 0: py = -py
w = ($108 - py) lsr 3                                 ; unsigned shift: puck past the line -> large
if w >= $14 (signed): w = $14
a3.$42 (temp2) = w                                    ; windup vblanks
assreplace($12 assshoot)
```
`assshoot` (L41029): its first call is `SetShotMode`. Later calls count `temp2` down by `d7`, then press "C" to release (`ShotMode` -> `prepshot` -> `doshot`).

### 5.8 Shot/pass press: SetShotMode (L37411-37420) and setpassmode (L36893-36904)
Both start with the same PS/SO block:
```
if BA_PS_flags bit2:
    clear word_FFC2FA bit2                            ; attempt clock freezes (gmode bit0 is set)
    if bset(BA_PS_flags bit5) was already set: return ; rtss7: no second shot/pass in the attempt
    clear word_FFC2FA bit5
    word_FFC31C = $64                                 ; 100
(normal shot / pass mode start)
```
- `assshoot` calls `SetShotMode` on its first call. If bit 5 was already set, shot mode is not entered: the next `assshoot` call finds `sflags` bit 3 clear and exits.
- `passmode` (L36962-36967): for an **away** passer in PS/SO the receiver search is skipped (`_nopp`): the puck is hit in `passdir` at nobody. A **home** passer searches home objects 0..5 normally (skip self, goalies, `$63` bit 2). Parked teammates are valid targets because `resetplstuff` cleared their unavailable bit (Q9).

### 5.9 Shot aim: shotdiradj -> PSandSOpassdir (L37786-37791, L974238-974250)
`shotdiradj` (called by `doshot`) runs only for CPU shooters and one-timers. After it computes its post-based `passdir` (0, 2, 6 or 8), in PS/SO:
```
PSandSOpassdir():
    d = word_FFDA1A
    if pfgoal == 0: d = passdirlist[d]                ; mirror for the bottom net
    passdir = d
```
`word_FFDA1A` is written only when the last waypoint loads (5.4). A CPU shot before that (clock <= 3 s, or the still-puck rule) uses the previous attempt's value (Q3). A human shooter's `passdir` is the d-pad direction from `ShotMode`.

### 5.10 doshot (L37514-37695): the shootout perfect shot
At L37602-37604, after the "distance to aim point `d3` > 200 -> not perfect" test and the `ReadGoaliePulled` test:
```
if word_FFC2FA bit0: goto _perf                      ; shootout: no aim error at all
```
So in SO every shot within 200 px of its aim point goes exactly to the `shotsets` point. A penalty shot in a regular game gets the normal shot-accuracy roll. No other PS/SO code is in `prepshot`/`doshot`. `doshot` still sets `word_FFC2FA` bit 4 when the shooter has the breakaway bit; `asspuckc` normally clears that bit in PS.

---

## 6. Ending the attempt

### 6.1 sub_F2F4: attempt-over check (L41556-41598, ROM `$F2F4`)
- Port hook: `ps_attempt_check()`. Caller: `pucknorm` (L42527-42529), every frame while `BA_PS_flags` bit 2 is set (`a3` = puck). The puck's assignment runs before its `checkcoll` -> `checkgoal` in the same `updateplayers` pass.
```
sub_F2F4():
    if puckc == BA_Goalie_SCnum: goto over            ; goalie has the puck (save, cover, pickup)
    if BA_PS_flags bit5 == 0: goto clock              ; no shot/pass pressed yet
    if word_FFC2FA bit5 == 0:                         ; not released yet
        if puckc >= 0: goto count                     ; still on the stick (windup)
        set word_FFC2FA bit5                          ; released this frame
    if puckc >= 0: goto over                          ; anyone (incl. the shooter) has it again
count:
    if word_FFC31C < 0: goto over                     ; ran out: 102nd counted frame
    word_FFC31C -= 1                                  ; per frame
    goto clock
over:
    set BA_PS_flags bit4
clock:
    if word_FFD454 == 0: set BA_PS_flags bit4         ; 25 seconds used
    if BA_PS_flags bit4 == 0: return
    if BA_PS_flags bit6: return
    set BA_PS_flags bit6
    AddPenalty2($A PenWhistle)                        ; a3 = puck
    ; no rts: falls through into sub_F37C (bytes 4EB9 00011F62 4EB9 0000AFB6)
```
Causes of "over" (bit 4): the goalie gets the puck; after the press, the puck is regained by anyone, or 101 frames have been counted (press-to-release plus loose-puck time); the attempt clock reaches 0; the goalie hold timer (`assgoaliecpu`).

### 6.2 sub_F37C: attempt end (L41600-41622, ROM `$F37C`)
- Port hook: `ps_attempt_end()`. Callers: `checkgoal` (goal), fall-through from `sub_F2F4`.
```
sub_F37C():
    freezewindow                                      ; camera lock (sflags bit6)
    if word_FFC2FA bit0 == 0:                         ; PS only
        word_FFDEF0 = $A                              ; record 10 more replay frames
        set sflags2 bit2
    set gmode bit0
    clear word_FFC2FA bit2
    clear BA_PS_flags bits 2, 3, 5, 4, 6               ; bits 0, 1, 7 untouched
    SortCords[BA_Sktr_SCnum].$61 = byte_FFC31E        ; give back SetPersonel's newpnum
    sub_FC516()                                       ; 7.3, runs in PS too (Q4)
```
`word_FFC2FA` bit 1 stays set until the next normal `puckfaceoff`. `gmode` bit 0 with bit 2 clear stops all VBlank ticking.

### 6.3 checkgoal, PS/SO goal branch (`_goal`, L49758-49798)
Reached when the puck crosses the goal mouth of the net object `a2` (both nets use this code):
```
_goal:
  if BA_PS_flags bit2 == 0: goto normal              ; normal: if gmode bit0 return; else goal
  if word_FFC2FA bit0:                                ; SO: side by turn
      need_top = (word_FFD594 == 0)                   ; home shoots at +Y, away at -Y
  else:                                               ; PS: side by the shooter
      need_top = (SortCords[BA_Sktr_SCnum].pfgoal == 1)
  if need_top and pucky < 0: return                   ; wrong net: ignored (Q7)
  if not need_top and pucky >= 0: return
  set word_FFC2F4 bit5                                ; PS/SO goal
  if word_FFD594 != 0: word_FFD576 += 1               ; away SO goal
  else:                word_FFD574 += 1               ; home SO goal (also in PS: Q4)
  set byte_FFC2FE bit0                                ; next faceoff at center
  sub_F37C()
  goto goal_common                                    ; skips the gmode bit0 test
```
Then the normal goal code (L49802-49960) runs, with these PS/SO-specific points:
- Scoring team = the net's side (`pucky >= 0` -> home unless `gmode` bit 1). `$0C` (score) += 1 in SO too: `HmGoals/AwGoals` equal the SO goal counts.
- `ChkShotStat` is called twice but returns at once (`gmode` bit 0 set). No shot is counted for PS/SO goals or saves (Q6).
- L49828-49832: if `word_FFC2F4` bit 5 and not SO: `team.$362 += 1`. `$362/$360` are the "Penalty Shots" goals/attempts stats (stat table at ROM `$FE032`: "Breakaways" `$35A/$358`, "One-Timers" `$35E/$35C`, "Penalty Shots" `$362/$360`). The listing comment "SH Goals" and the `$362` entry in `rules_clock_penalties.md` 0.6 are wrong.
- `word_FFC2F4` bit 5 also makes the goal display (L56069-56095) skip the assists line. That display clears the bit.
- L49920: `bclr #3,BA_PS_flags` (already clear).
- L49923-49929: in SO `setass` is skipped (no `assscore` celebration). In PS the scoring team's skaters with `$34 > 0` get `assscore`, including the parked teammates.
- The puck is put in the net, the net SPA is `$102E`, and `AddPenalty2($E PenGoal)` is queued. `Stop4Pen` then skips the faceoff spot (`gmode` bit 0 already set).

### 6.4 After the attempt
- The whistle (`$A`, delay 0, ref 80 vblanks) or the goal (`$E`) is processed by `checkfornewpen` -> `Stop4Pen` -> `InProgress`. `Stop4Pen` finds `gmode` bit 0 set and skips the faceoff-spot code, so `fox/foy` stay as they were (`chkprogress` runs the normal path because `BA_PS_flags` bit 2 is clear).
- `InProgress` finish: `BA_PS_flags` bit 3 is clear, so the puck gets `$1B` (`puckfaceoff`).
- PS (regular game): `puckfaceoff` first call: `byte_FFC2FE` bit 0 -> `fox = foy = 0` (center) after a goal. Otherwise the spot is the one `Stop4Pen` set when the penalty-shot foul was called. `word_FFC2FA` bit 1 is cleared (`gameclock` runs again from the next live play). The usual end checks follow (`gameclock == 0` -> PeriodOver, an OT goal -> winner, ...). `puckfaceoff2` clears `BA_PS_flags` bits 2 and 5.
- SO: `puckfaceoff` (L41627-41636) clears `byte_FFC2FE` bit 4, sets `puckvx = puckvy = 0`, `assreplace($1E)` and returns, before its pfna test. So the next attempt starts (or the game ends in `sub_FC4C0`).

---

## 7. Shootout bookkeeping

### 7.1 sub_FC47C: shootout init (L968789-968809)
Called once from GameSetUp (L962442) when the menu choice was OptPlayMode 4.
```
clear SortCords $FFB04A .. +$7FF (all 16 objects, 1024 words)
word_FFDED0 = 0
word_FFD578 = 1                                        ; round 1
clear word_FFC2FA bit3
word_FFD574 = 0; word_FFD576 = 0; word_FFD586 = 0; word_FFD594 = 0
sub_FC570()                                            ; home default list
word_FFD594 = 1; sub_FC570(); word_FFD594 = 0          ; away default list
```
`sub_FC570` (L968866-968888): `a0 = $FFD586` (home, `word_FFD594 == 0`) or `$FFD594` (away). Team id = `HomeTeam` or `VisTeam`. `T = long[$30E + 4*id]`. `p = T + word[T+6]` (line 1). Then 6 times: `-(a0) = byte(p++) - 1` (word). See 1.5.5.

### 7.2 sub_FC4C0: per-attempt shootout setup (L968811-968834, ROM `$FC4C0`)
Called from the first `puckshootout` call in SO.
```
if word_FFC2FA bit3: jmp loc_172E4                     ; winner known: end of the shootout game
sub_FE756()                                            ; random CPU path
BA_Team = word_FFD594
BA_Goalie_SCnum = $B; list = $FFD57A                   ; home shoots on the away goalie
if word_FFD594 != 0:                                   ; (tst; beq skips the away case)
    BA_Goalie_SCnum = 5; list = $FFD588                ; away shoots on the home goalie
BA_Skater_Offset = list[word_FFD586]                   ; word
clear byte_FFB7AC bit2                                 ; puck $62 bit2 ("no player collision",
                                                       ; set when the last goal went in)
```
The shooter's slot comes from the shooting team's list. The goalie's slot comes from the defending team's list entry 5 (`puckpenshot`, 3.3). The shooter object is always 0 (home) or 6 (away) (`sub_EE58`), and the goalie object is always 11 or 5.

### 7.3 sub_FC516: alternation, rounds and the winner (L968836-968864, ROM `$FC516`)
Called at the end of every attempt (`sub_F37C`), PS included.
```
if (low byte of word_FFD594) bit0 == 1               ; away just shot: the round is complete
   and word_FFD578 >= 5 (signed)
   and word_FFD574 != word_FFD576:
    set word_FFC2FA bit3                              ; decided
    sub_FD618()                                       ; 7.4
    return
word_FFD594 ^= 1
if word_FFD594 != 0: return                           ; away's turn in the same round
word_FFD586 += 1; if word_FFD586 >= 5: word_FFD586 = 0    ; shooters cycle 0..4
word_FFD578 += 1                                      ; next round
```
Rules that follow:
- Home always shoots first in a round.
- At least 5 full rounds. Nothing is decided after a home shot, and nothing before round 5 even when it is mathematically over.
- From round 5 on, sudden death by full rounds: after each away shot, unequal goals end it. No round limit (`word_FFD578` is a word; the intro prints 2 digits).
- Shooter `k` of round `r` is list entry `(r-1) mod 5`. The goalie never changes (list entry 5).
- Winner = home if `word_FFD574 > word_FFD576` (signed) else away (`sub_FD618`, `sub_FC5AE`).

### 7.4 sub_FD618: winner celebration (L970647-970690)
```
set sflags2 bit2; freezewindow
word_FFDED0 = $60
base = (word_FFD574 > word_FFD576) ? SortCords[0] : SortCords[6]
for objects base+1 .. base+4 (4 objects; dbf from 4 after an initial step):
    setplayer(d3 = 6)                                 ; roster slot 6 for all four (Q10)
    $34 = 2
    Y = Vpos + (Vpos < 0 ? $F0 : $FF10); X = 0        ; 240 px from the camera center, toward
                                                      ; center ice: just off screen
    assinsert(7 assscore)
    clear pfalock ($62 bit5), $63 bit1, $62 bit2
```
`assscore` in SO (L38332-38345, also in `ai_positional.md`): every call does `if word_FFDED0 != 0: word_FFDED0 -= 1; if it reached 0: set sflags2 bit2`. All four players decrement it, so it lasts about $60/4 frames. Then `if X > $88 or X <= -$88: target y = 0`.

### 7.5 Ref and display while decided
- `SetPA` (L46566-46570): with `word_FFC2FA` bits 0 and 3, `sub_FC5AE` prints "SHOOTOUT WON BY <team>".
- `setPA2` (L46602-46612): with bits 0 and 3, every ref step's `RefCnt` is doubled.

### 7.6 End of a shootout game
After the deciding attempt: whistle or goal -> presentation -> `$1B` -> `puckfaceoff` -> `$1E` -> `puckshootout` first call -> `sub_FC4C0` -> `jmp loc_172E4` (L53859):
```
loc_172E4: song($78); goto Opening2
Opening2: KillCrowd; SR = $2700; SP = Stack; clear RAM VSCRLPM..$FFD03E
          GameSetUp            ; OptPlayMode = TempOptPlayMode (4); sub_FD73C clears BA_PS_flags,
                               ; word_FFC2F4/F8/FA and $FFD572..$FFD597; then the menus
          sub_FBB88; PlayoffScreen (only if OptPlayMode != 0)
          if word_FFC2FA bit0 == 0: sub_FCC76
          jmp StartGame
```
No `GameOver`, no `AddPOStats`, no stats screen. The `jmp` leaves the frame's stack behind (Opening2 resets SP). Port as "return to the pre-game menus".

### 7.7 OptPlayMode 4 across the game
- Menu start (L962436-962442): `TempOptPlayMode = OptPlayMode`. If it is 4: `OptPlayMode = 0`, set `word_FFC2FA` bit 0, `sub_FC47C`. So during play the mode reads as regular season (0).
- `GameSetUp` (L960192): `OptPlayMode = TempOptPlayMode` (back to 4 for the menus). Then `sub_FD73C` clears the flag words.
- `StartGame` (L29769-29777): in SO, `Create_HotCold_Table` for both teams (`sub_FCC76` is skipped in Opening2).
- `StartPer` (L29869-29875): in SO, the puck gets `$1E`, `BA_Skater_Offset = 8` and `BA_Goalie_SCnum = $B` (both overwritten by `sub_FC4C0`).
- `Intermission` (L47638): the SO menu `unk_19A00` ("Start Shootout / Shootout SetUp / Team Roster ..."). `PauseMode` (L30229): the SO pause menu `unk_19664`.
- `FigureJoy` (L55016): the shootout takes the non-playoff pad path (it sees OptPlayMode 0 anyway).
- Presentation-only checks of bit 0: `Crowd_Noise?` (L959688, no crowd noise in SO), `showclock` horizontal mode (L52293), `sub_164D6` (L52486, pad markers), `PrintScores1` (L47205).

---

## 8. Port mapping notes

- `ba_ps_flags`: keep bits 0, 1, 6, 7 as well. `BA_GOALIE_HELD` (bit 4) is the general "attempt over" flag. `ps_attempt_end()` must clear only bits 2-6, not the whole word.
- `f_c2fa`: also needs bit 1 (attempt-clock mode), bit 2 (clock live while stopped), bit 3 (SO decided) and bit 5 (released after press).
- `ps_script_dir` is 0 at power-on (the boot clears `$FFB000-$FFDEF4`) and is never reset afterwards. The port's default of 8 differs.
- `shootout_side` = `word_FFD594`. `shootout_goals[0/1]` = `word_FFD574/6`.
- Still missing in the port: `ps_clock`/`ps_clock_frac` (`$FFD454/6`), `so_round` (`$FFD578`), `so_shooter_idx` (`$FFD586`), `so_list[2][6]`, the waypoint state (`$FFDA12-$FFDA1C`), `word_FFD410`, `byte_FFC31E`, `word_FFDEF0`.
- Hooks: `ps_should_shoot(o)` = 5.6 (returns "shoot" for Z = 1). `ps_waypoint(o)` = 5.5 (returns the raw waypoint, or "unchanged/finished"; the caller tests `DA16` high byte == $80). `ps_attempt_check()` = 6.1. `ps_attempt_end()` = 6.2. `pen_shot_chk(id, victim)` = section 2.

---

## 9. Quirks (port as-is)

- **Q1. Lefty CPU shooters never "finish" the path.** `sub_FE7FC` negates the waypoint X for a shooter with `$76` bit 0 (Lefty), including the terminator word: `$8020` becomes `$7FE0`, whose high byte is not `$80`. If a lefty reaches the last waypoint between two decision frames, the terminator becomes his target: `skateto` heads for x = ±$7FE0, and `sub_FE8EC` never sees the shoot box or the finished marker. He then shoots only when `word_FFD454 <= 3`. The release countdown does not apply because nothing was pressed. A righty in the same case stops steering and shoots on the next decision frame.
- **Q2. The first waypoint is never mirrored.** It is loaded by `sub_FE756` with `a3` = puck, whose `$76` is 0. Waypoints 2+ are mirrored for lefties.
- **Q3. Stale script direction.** `word_FFDA1A` is set only when the last waypoint loads. A CPU shot fired earlier (clock <= 3 s, or the still-puck/<15 s rule) aims with the previous attempt's direction, or 0 after power-on.
- **Q4. Shootout bookkeeping in regular-game penalty shots.** `checkgoal` increments `word_FFD574/6` (chosen by `word_FFD594`'s parity, not by team), and `sub_F37C` always calls `sub_FC516`. These words are cleared per game by `sub_FD73C` (`word_FFD578 = 0`). On the 12th penalty shot of one game the decided test can pass (`FFD594` odd, `FFD578 >= 5`, counters unequal). That sets `word_FFC2FA` bit 3 and runs the `sub_FD618` celebration in a regular game. Bit 3 has no other effect without bit 0. Practically unreachable; port as-is.
- **Q5. Shootout objects are fixed.** The shooter is always object 0 (home) or 6 (away) and the goalie always object 11 or 5. `puckshootout` only re-checks the goalie object (`$34 == 0`, `$63` bit 2 clear). In SO all objects keep `$34 = 0` from `setupice` unless they once were the shooter (`$34 = 4`), so the check passes. The SO goalie gets `setplayer` twice: `sub_1592C` loads `$61` from SetPersonel, then `puckpenshot` loads the list goalie. Only the second load counts, but `tmpdst` of the first slot was set to -1.
- **Q6. No shot statistics in PS/SO.** `ChkShotStat` returns at once because `gmode` bit 0 is set: no shots, PP shots or goalie shots-against for PS/SO saves or goals. `sflags2` bit 4 (shot taken) stays set until the next counted `ChkShotStat`. Goals still count (score, ScoreSum, period goals, `$362` for PS).
- **Q7. Wrong-net goal.** In PS/SO a puck entering the net that is not under attack (the far, empty net) makes `checkgoal` return after setting `collflag`. There is no goal and no deflection.
- **Q8. The goalie starts facing his own boards.** `puckpenshot` computes the facing from a temporary Y of ±229 on the wrong end (+229 for pfgoal = 1), then moves him to ∓250. The pfgoal = 0 goalie (at +250) turns toward the puck one step per decision right away. The pfgoal = 1 goalie (at -250) does not, until the puck has negative Y (`assgoaliecpu` "other half" path; `pucky = 0` counts as the + half).
- **Q9. The parked players are not unavailable.** `sub_1592C` sets their `$63` bit 2, and `resetplstuff` clears it right after. Effects: a home passer in PS/SO can pick a parked teammate as the pass target. An away passer always passes blind (`_nopp`). `chgplayer` and `checkpuckcoll` exclude the parked players through their own `BA_PS_flags` tests.
- **Q10. Celebration roster slot.** `sub_FD618` calls `setplayer` with `d3 = 6` for all four celebrating objects (all become roster slot 6) before setting `$34 = 2`. In SO those objects usually have `$34 = 0`, so setplayer takes its goalie branch. If slot 6's tmpdst is -2, setplayer inserts `assben` under the `assscore`.
- **Q11. Setplass with the old position.** `sub_1592C` calls `Setplass` before it writes the new `$34`. In a fresh shootout every object has `$34 = 0` (cleared by `setupice`/`sub_FC47C`), so the shooter's stack gets `$0E assgoaliecpu` under `assnearest`/`asspuckc`. Nothing pops down to it during the attempt.
- **Q12. Delayed penalty at puckshootout.** If `gmode` bit 3 is set on the first call, the code branches (`bne.w`) to `Stop4Pen` after clearing the BA bits. The music, `gmode` bit 0, `word_FFC2FA` bit 1, the 25 s clock and ReturnGoalies are all skipped. The next frame takes the non-first path straight to `$1F`. Without `word_FFC2FA` bit 1 the attempt would run `gameclock` and keep the previous `word_FFD454` (0 after a timeout ends the attempt at once). `chkprogress` clears gmpendel before `InProgress` finishes, so this path looks unreachable.
- **Q13. B tap by a human goalie in PS/SO** finds no `chgplayer` candidate. With `d6` = current SCnum it calls `Sweepcheck` on the goalie (pfalock + SPA `$B24`).
- **Q14. Same-frame order.** `pucknorm` (and so `sub_F2F4`) runs before the puck's `checkcoll`/`checkgoal` in the same `updateplayers` pass. A puck that crosses the line in the frame the attempt ends (clock reaching 0, 102nd release frame, goalie touch) is not a goal: `BA_PS_flags` bit 2 is already clear and `gmode` bit 0 is set.
- **Q15. Shot/pass press freezes the attempt clock.** From then on only `word_FFC31C` limits the attempt. Every frame between the press and someone regaining the puck decrements it (100 -> -1 in 101 frames, per frame, not per vblank). The next such frame ends the attempt. The countdown also runs during the windup, before the puck leaves the stick.
- **Q16. Faceoff after a missed penalty shot** is at the spot computed when the original foul was called. `Stop4Pen` skips the spot code because the clock is stopped.
- **Q17. Intro timer is per frame.** 400 or 100 frames, not vblanks. With `d7` > 1 the intro lasts longer in real time.
- **Q18. Music.** In SO the attempt music (`ChooseSong` index 2) restarts only for home's shooter 1 (rounds 1, 6, 11, ...). In PS it plays for every attempt.
- **Q19. The scoring team's parked skaters celebrate a PS goal** (`setass` gives `assscore` to every skater with `$34 > 0`). In SO nobody celebrates until the winner (`sub_FD618`).
- **Q20. sub_EE58 tie-break.** Equal scores go to the later roster slot. The fouled player gets `$7FFF` only while he is on the bench or ice (not injured or in the box).

---

## 10. UNRESOLVED

- **U1.** `chgplayer` fallback `d6` for a pad on the defending team (and for a second pad on the shooting team) during `puckpenshot`'s `setchgplayer`. `d6` is whatever the caller left in it after `forceblack`, `sub_11738`, `checkwindow`, `SetPersonel`, `sub_1592C`, `resetplstuff`, `setplayer` and `SprSort`. Possible results: if `d6 == -1` (the freshly cleared `cNplayernum`), `Sweepcheck` runs on `a3` = **puck** (sets puck `$62` bit 5 and SPA `$B24`). If `d6` is 0..11, that object gets `pfjoycon` until step 3 of 3.6 overrides it (one defending pad only). Any other value is stored as the pad's player. Recommendation: treat "no candidate" as "leave `cNplayernum = -1`". Step 3 then gives a single defending pad the goalie, and a second pad stays idle.
- **U2.** The "Shootout SetUp" menu (ROM `$FC620`.., cursor `word_FFD5B8` 0..5, `$FFD57A` for `HmShots`, `$FFD588` otherwise) can reorder the lists and change the goalie. Its rules (which slots are allowed, duplicates) were not traced. The port should accept any 6 slots per team.
- **U3.** `byte_FFC2FC` bit 7 (set by `puckshootout`) is read only by `sub_166E6` (L52747, a sprite/animation offset). Its visual effect was not traced.
- **U4.** Stoppages other than the attempt end during an attempt (puck out of play `$06`, "puck stuck" in `pucknorm`) have no PS handling. Their presentation would end with `BA_PS_flags` bit 3 still set (another `$1E`) unless `sub_F2F4` ends the attempt first (101-frame countdown or clock). The race depends on frame length and was not resolved.
- **U5.** ReturnGoalies -> `CPgoalie` at `puckshootout` can pull a CPU goalie again (3rd period, down by exactly 2, <= 60 s, `foy` in the attacking half) right before the penalty shot. The effect on `SetPersonel`'s `$61` for the `BA_Goalie_SCnum` object (which `sub_1592C` passes to `setplayer`) was not traced. If that object's `$61` is `$FF`, `sub_1592C` writes `tmpdst[$FF]` (team struct `+$264`) and calls `setplayer(255)`.
