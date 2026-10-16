# NHL '94 (Genesis): playoff mode, battery-saved records and the reverse-angle replay

Sources: `lst/nhl94.bin.lst` (IDA listing, no address column; `Lnnnnn` = listing line of the first instruction unless a label is named) and `lst/nhl94.bin` (CRC32 `$9438F5DD`). ROM addresses are `$xxxxx`, RAM addresses `$FFxxxx`. The listing garbles inline `printz`/`printz2` strings and most tables in this area; every string and table below was read from the ROM bytes (capstone disassembly that steps over inline strings). RAM names come from operands that the listing names (`OptPlayMode` = `$FFD048`, `gamelevel` = `$FFCEEC`, ...).

Related specs: `ui_menus.md` (menu engine, stats pages, §11 other games, §15 SRAM pages), `rules_clock_penalties.md` (§0.6 `gsstruct`, `InitScores`/`UpdateScores`/`SetScore`/`getscore`/`GetShifter`, `clockcont`, `PeriodOver`, `GameOver`), `ui_ingame.md` (§8.1 ticker, §10 Stars of the Game), `audit_ai.md` (G5 `assstanley`), `ai_positional.md` (`assstanley`), `animation_assets.md` (`revframetbl`, reverse rink).

Exported data: `tools/extract/playoffs.py` → `godot/assets/ui/playoffs/` (§12).

**Verification.** The emulation harness of the earlier UI work (`/tmp/claude-0/-home-user/ef020377-92e3-57ff-8519-5d51b4a7df4d/scratchpad/ui/emu.py`: unicorn 68000, VDP model, pads; battery RAM is the mapped area at `$200000`) booted the ROM. Drivers in `.../scratchpad/po/` (`drv.py`, `run.py`, `p*.py`, `u*.py`, `rv*.py`) hook the routines named below, clear `cont1team`/`cont2team` during play (CPU against CPU), use 30-second periods (`OptPerlen` 3) and, where noted, force the user's team to lead by one goal with a second left in the third period. Runs made:
- **Single-game playoffs** (New Playoffs), Montreal: round 1 to the Stanley Cup (two runs, one eliminated in the quarterfinal, one champion).
- **Best-of-7** (New Playoffs/7 game): a 4-0 series win.
- **Regular-season game with User Records On:** a name typed on Name Entry, the records pages read back, and A+C on Record Holders.
- **Instant replay:** toggled to the reverse angle.

Every screen and every SRAM byte quoted below was seen there. The screenshots are in `/tmp/claude-0/-home-user/ef020377-92e3-57ff-8519-5d51b4a7df4d/scratchpad/po/` (list in §13).

---

## 0. Quick facts

- **Play modes** (`OptPlayMode` `$FFD048`, setup row "Play Mode"):
  - 0 Regular Season;
  - 1 Continue Playoffs;
  - 2 New Playoffs: **one game a round** (`bosgames` = 7);
  - 3 New Playoffs/7 game: best of seven;
  - 4 Shootout.

  The table in `rules_clock_penalties.md` §0.5 has 2 and 3 swapped.
- **A 16-team bracket per new playoff.** The bracket is one of 32 fixed seedings at `$5576` that contains the user's team. Pairs (2k, 2k+1) meet in round 1; teams 0-7 are East, 8-15 West; the second team of a pair has home ice. 4 rounds: `gamelevel` 0 to 3. The user plays one series a round. Every other series is simulated by the `gsstruct` scorer (`getscore`) at one game per user game. In best-of-7, once the user's series ends, the others are finished by coin flips.
- **The playoff state lives in battery RAM:**
  - an 80-bit mixed-radix number at `$FFD088` (a leftover of NHLPA '93's password);
  - the user's cumulative Playoff Stats, bit-packed at `$FFD0DC`.

  Both are inside the 256-byte block `$FFD076..$FFD175`, which is written to SRAM after every playoff game (`sub_FE696`) and read back at power-on and on every setup menu (`sub_FE660`). Neither `sub_FE660` nor `sub_FE696` tests `ValidSRAM`: with fresh (cleared) SRAM the state is 0 and "Continue Playoffs" is skipped; without a battery RAM chip the state would be whatever the bus returns (not tested).
- **SRAM records** need the setup option **User Records = On** (`OptUserRec` 0; the default is 1 = Off) and valid SRAM (`ValidSRAM` ≥ 0). Then:
  - at every game end, `sub_F9CDE` updates per-player best games, per-team records (goals, goalie saves, home crowd dB) and per-user records (win/loss/tie, best goals and saves in a win);
  - before each game a **Name Entry** screen lets each human pick one of 7 named users.

  Player Cards, Record Holders, the setup screen's player cards, the Crowd Meter and the Ron Barr "Matchups" screen read them.
- **Saved lines** (`$FFD076`, "Save Team Line") are in the same block, so they also persist in SRAM (`sub_8928` L31535 ends with `sub_FE696`). They are not RAM-only.
- **Stanley Cup:**
  - the winning goal or final horn of the cup-clinching game gives one winning skater `assstanley` (the cup held overhead, SPA `$109E`) and the others `assscore`; the pads lose control;
  - the Stars of the Game box (home win: song `$F`), the final intermission and the Playoff Stats page follow;
  - then the bracket screen at `gamelevel` 4 with the champion's plate under the cup and "Champions".

  There is no other ceremony, trophy screen or special music.
- **Reverse angle:** a 180° view. Every object's x and y are negated, the camera is negated and clamped, frames are mapped through `revframetbl`, and the rink is drawn from the reverse rink map; the crowd sprites and arena animations are hidden (§10).

---

## 1. RAM

| Address | Name | Size | Meaning |
|---|---|---|---|
| `$FFD048` | OptPlayMode | w | 0-4 (§0). `TempOptPlayMode` `$FFD074` is the copy restored by `GameSetUp` (L960192) |
| `$FFD04A` | OptNOP | w | "Players" row. In playoffs 7 One, 6 Two - Teammates, 5 Two - Head to Head (2 pads) |
| `$FFD04C` / `$FFD04E` | Opt1Team / Opt2Team | w | In playoffs: the user's team and its current opponent (written by `FigureJoy`) |
| `$FFD054` | OptUserRec | w | 0 = User Records On, 1 = Off (default, `defmenuoptions` L54847) |
| `$FFCE66` | gsstruct | 8 x 16 | other games / series (below) |
| `$FFCEE6` | gamenum | w | the user's series index this round; `$FFxx` (negative) = the user is not in this round (eliminated, or regular season, `st.b` L55026/L55174) |
| `$FFCEE8` | postarts | w | seeding index 0-31 |
| `$FFCEEA` | bosgames | w | game of the series 0-6; 7 = single-game playoffs |
| `$FFCEEC` | gamelevel | w | round 0-3; 4 = playoffs over (champion known) |
| `$FFCEEE` | potreeteam | w | the user's index 0-15 in the seeding; user team = tree[potreeteam] |
| `$FFCEF0` | pojoy | w | playoff pad set-up, 7 - OptNOP (11 - OptNOP four-way), `sub_17AC8` L54579 |
| `$FFCEF2` | (bracket bits) | w | bit k = 1: the second team of pair k advanced (k: 0-7 round 1, 8-11 QF, 12-13 SF, 14 final) |
| `$FFCEF4` | tree (`_gu0`) | 31 bytes | 0-15 seeds, 16-23 round-1 winners, 24-27 QF winners, 28-29 SF winners, 30 champion (`MakeTree`) |
| `$FFCF2C` | TickerNum | w | next ticker game (counts down) |
| `$FFCD96` | playoff stats | 104 words | goals[26], assists[26], SOG[26], PIM[26] of the user's team, unpacked (§4) |
| `$FFD076` | saved block | 256 bytes | saved line (`$D076`-`$D086`), playoff state (`$D088`-`$D091`), packed playoff stats (`$D0DC`-`$D173`) |
| `$FFD176` | alt state | 5 words | the state of a finished best-of-7 round (for the post-game bracket), not saved |
| `$FFD042` / `$FFD044` | (user ids) | w | the user (0-7) on the home / away team for records; 0 = none |
| `$FFD45A` | (user names) | `$80` | 12 bytes a user, id 1-7 at `12*id` |
| `$FFD458` | ValidSRAM | w | 0 valid, negative invalid |
| `$FFCF36` | (record buffer) | `$80` | scratch for SRAM records (also Stars of the Game scores) |

**`gsstruct` record** (16 bytes, `rules_clock_penalties.md` §0.6):

| Offset | Field |
|---|---|
| +0 | team1 = home of the next game |
| +2 | team2 |
| +4 | wins of the **first-listed** team of the seeding pair |
| +6 | wins of the second-listed team |
| +8 | gsper: periods played, 5 = final |
| +$A / +$C | score1 / score2 |
| +$E (byte) | bit 0 teams flipped (team1 is the second-listed); bit 1 close game, highlight pending; bit 2 series over |

---

## 2. Setup menu and the start of a playoff

### 2.1 Options (GameSetUp L960187, `GameSetUp_4` L960986)

- Row 0 "Play Mode": `Regular Season`, `Continue Playoffs`, `New Playoffs`, `New Playoffs/7 game`, `Shootout` (`$F7D16`).
- On entry (L960210-960221):
  - modes 2/3 → `j_NewPO` (a **fresh seeding every time the menu is entered**);
  - mode 1 → `sub_17CA0` (decode the saved state).
- Changing "Play Mode" (`d7` = 0) or "Team 1" (`d7` = 4) in modes 2/3 re-runs `NewPO` (L960932-960939). Stepping row 0 onto mode 1 runs `sub_17CA0`. If the decoded `gamelevel | bosgames` is 0, there is no playoff to continue, and the option is skipped in the same direction (L960924-960928). So with fresh SRAM, Right from Regular Season lands on New Playoffs (`m1.png`).
- In playoff modes the "Team 1" row is the user's team and "Team 2" shows the opponent from the tree.
- Menu exit (L962415-962443):
  - `sub_17AC8`: modes 2/3 only, `pojoy = 7 - OptNOP` (11 four-way);
  - `TempOptPlayMode = OptPlayMode`;
  - Shootout → `OptPlayMode` 0 + `word_FFC2FA` bit 0;
  - `jmp MakeTree`, which ends in `FigureJoy` (§2.4).

### 2.2 NewPO (L54901)

```
d0 = randomd0(32)
do { d0 = (d0 + 1) & 31; a0 = $5576 + 16*d0
     t = min(Opt1Team, 25)                          ; All-Star East/West (26/27) search as Winnipeg (25)
} while t not in a0[0..15]                           ; every team 0-25 is in 6..32 seedings (no hang)
potreeteam = index of t in a0;  postarts = d0;  gamelevel = 0;  bosgames = 7
if OptPlayMode == 2: goto MakeTree                   ; single game a round
bosgames = 0; clear +4/+6 of all 8 gsstruct entries
MakeTree
```
- The seeding is not uniform: the first one after a random start that holds the team.
- `$CEF2` and `pojoy` are not reset here. `MakeTree` masks the stale bits away round by round.
- **Quirk:** picking an All-Star team as Team 1 makes the user play the playoffs as Winnipeg.

### 2.3 MakeTree (L54939) and GetShifter (L55429)

```
GetShifter: d2 = -16; d1 = 16; repeat gamelevel+1 times { d2 += d1; d1 >>= 1 }; d1 -= 1
            ; gamelevel 0..4 -> d1 (series - 1) = 7, 3, 1, 0, -1;  d2 (tree offset) = 0, 8, 12, 14, 15
MakeTree:
  tree[0..15] = $5576[16*postarts ..]
  bits = $CEF2
  for k = 0..14: tree[16 + k] = tree[2k + (bits & 1)]; bits >>= 1
  d1, d2 = GetShifter(); if d1 < 0: return               ; gamelevel 4
  a0 = tree + 2*d2
  for i = 0..d1: g = gsstruct[i]
      g.score1 = g.score2 = g.gsper = 0; clear g.flags bit 1
      sub_17E04: if bosgames in {2, 3, 5}: not flipped: team1 = a0[0], team2 = a0[1]
                 else (0, 1, 4, 6 and 7):  flipped:     team1 = a0[1], team2 = a0[0]
      a0 += 2
  FigureJoy
```
Home ice: the second-listed (higher) seed is home in games 1, 2, 5, 7 (`bosgames` 0, 1, 4, 6), the first-listed in games 3, 4, 6. In single-game playoffs the second-listed team is always home. Example: seeding 0 lists Buffalo, Boston: Boston has home ice.

### 2.4 FigureJoy (L55005)

```
cont1team..cont4team = 0
if demoflag == 0: goto sub_18002 (slate only)
if OptPlayMode == 0 or shootout: goto _fjnpo
d1 = GetShifter(); user = tree[potreeteam]; gamenum = $FFxx
for i = d1 .. 0: g = gsstruct[i]
    if g.team1 == user: side = 0;              Opt1Team = user, Opt2Team = g.team2; break
    if g.team2 == user: side = 4 (5 four-way); Opt1Team = user, Opt2Team = g.team1; break
if not found: return                                   ; eliminated: no pads, gamenum < 0
gamenum = i; HomeTeam = g.team1; VisTeam = g.team2
{cont1team, cont2team} = _pojoylist[side + pojoy]      ; _pojoylist2 four-way (+ cont3/4 rules L55064-55089)
_fjnpo: {cont1team, cont2team} = _noplist[OptNOP] (+ four-way copies); then sub_18002
```
- `_pojoylist` (`$17F52`), entries {cont1team, cont2team}, 1 = controls home, 2 = away:
  - user home: pojoy 0 = (1,0) One; 1 = (1,1) Teammates; 2 = (1,2) Head to Head;
  - user away: 0 = (2,0); 1 = (2,2); 2 = (2,1).
- `_noplist` (`$17FE6`): (0,0) Demo, (1,0), (2,0), (1,1), (1,2), (1,2), (1,2).
- `_pojoylist2` (`$17F72`, 4 Way Play), indexed by side (0 home, 5 visitor) + pojoy (= 11 - OptNOP):
  - home: 0 (1,0) One; 1 (1,2) Four; 2 (1,2) Three; 3 (1,1) Two - Teammates; 4 (1,2) Two - Head to Head;
  - visitor: 5 (2,0); 6 (2,1); 7 (2,1); 8 (2,2); 9 (2,1);
  - index 1 or 6: cont3team = cont1team, cont4team = cont2team; index 2 or 7: cont3team = cont1team, cont4team = 0.
  - `GameSetUp_3` skips Players 9-10 (Three, Four) in the playoffs, so indexes 1-2 and 6-7 are never reached. The playoff Players row is 7 Two - Head to Head, 8 Two - Teammates, 11 One. Each gives the same pads as its two-pad value (5, 6, 7).
- **U1 resolved — the regular-season slate** (`sub_18002` L55173): `gamenum = $FFxx`. d3 = a 32-bit mask with bits HomeTeam and VisTeam set. For each of the 8 entries: team1 = `OptionRNG`, team2 = `OptionRNG`, where `OptionRNG` (L55194) draws `randomd0(26)` until the bit is free and sets it. So the slate is 8 games between 16 distinct random real teams (0-25), never the two playing teams nor an All-Star team. It runs on every `FigureJoy`, also in playoffs, but then only the series entries are used.
- **Quirk (regular season while a playoff is saved):** `UpdateScores`, `InitScores`, Other Scores, the ticker and the highlights all count games with `GetShifter`, which uses the **decoded `gamelevel`**. A regular-season game played while a playoff is saved at round 2 shows only 4 other games (seen: `gamelevel` 1, entries 4-7 never advanced). `CwdExciteLvl` also starts at `gamelevel << 4`.

### 2.5 Continue Playoffs: sub_17CA0 (L54860)

```
sub_1803E(a3 = $FFD088)                     ; decode (§3.2)
if gamelevel | bosgames == 0: return        ; nothing saved
MakeTree
d0 = 7 (11 four-way)
two pads: if pojoy >= 2: pojoy -= 2
four-way: pojoy 1 -> 3, 2 -> 4
OptNOP = d0 - pojoy
```
**Quirk (seen):** with two pads the decoder turns a saved pojoy of 1 or 2 into 4, and this turns it into 2. A playoff started as "Two - Teammates" continues as "Two - Head to Head". In mode 1, `sub_17AC8` does not recompute pojoy at menu exit, so changing "Players" while continuing has no effect.

### 2.6 Before each game: Opening2 (L53868)

The order is:
1. `GameSetUp` (menus);
2. `sub_FBB88`, Name Entry, when User Records is On (§8.4);
3. `PlayoffScreen` (returns at once in mode 0);
4. `sub_FCC76`, the Ron Barr "Matchups" screen (not in shootout; it names the home arena's crowd record, §8.6);
5. `StartGame`.

`StartGame` (L29748):
- if `OptPlayMode > 1` (the first game of a new playoff), `sub_77E4` clears 228 words from `$FFD092`. That covers the packed playoff stats, `$FFD176` and RAM up to `$FFD259`.
- `InitScores` (§5.1);
- `LoadCrowdRec` (§8.5).

---

## 3. The saved playoff state

### 3.1 Encode: sub_18192 (L55309)

The state is one unsigned 80-bit integer, big-endian in the 5 words at a3 (`$FFD088`, or `$FFD176`). Horner form `N = N*radix + value` (`sub_181F6` → `sub_18236` multiply, `sub_1821A` add), in this order:

| # | value | radix |
|---|---|---|
| 1 | postarts | 32 |
| 2 | bosgames | 8 |
| 3 | gamelevel | 4 |
| 4 | potreeteam | 16 |
| 5 | pojoy | 8 |
| 6 | `$CEF2` bracket bits | `$4000` (bit 14, the final's result, is not kept) |
| 7-22 | series 0..7: +4 wins, then +6 wins | 5 each |

Max ≈ 2^31 · 5^16 < 2^80. `gamelevel` 4 cannot be stored; the state is cleared then instead.

### 3.2 Decode: sub_1803E (L55204)

1. Save the 5 words.
2. Peel the fields in reverse with `sub_1826C` (5-word long division, remainder = value):
   - series 7..0, +6 then +4; a series with a 4 in either field gets flags bit 2 (series over) and the others have it cleared;
   - `$CEF2`;
   - pojoy: with two pads, 1 or 2 become 4;
   - potreeteam, gamelevel, bosgames, postarts.
3. Restore the 5 words.

An all-zero state decodes to "no playoff".

---

## 4. Playoff stats

**AddPOStats** (L55445), called by `PeriodOver` when `gsp` becomes 4, before the final intermission:

```
if OptPlayMode < 1: return
sub_1833A                                   ; unpack $FFD0DC.. -> $FFCD96 (104 words)
a2 = the team struct (HmShots $FFC6CE or AwShots $FFCA32) whose +$28 (team id) == tree[potreeteam]
for i = 0..103: $FFCD96[i] += byte (a2 + $B4 + i)   ; goals $B4, assists $CE, SOG $E8, PIM $102 (26 slots each)
pack: for i = 0..103: w = widths[(103 - i) & 3]; v = min($FFCD96[i], 2^w - 1)
      written at bit offset sum(widths before i), in longs going down from $FFD170
      (word address $FFD170 - 2*(offset >> 4), value rotated left by offset & 15)
```
- `unk_18336` = `0C 0E 0A 0A`: the widths by `i mod 4` are 10, 10, 14, 12 bits, whatever the category (a quirk; never reached in practice). 1196 bits occupy `$FFD0DC-$FFD173`.
- For goalie slots the goals array holds goals against and the SOG array holds shots against (`TeamStats.player_goals` / `player_shots` of the goalie).
- The stats survive within one playoff, because the block is saved with the state. They are cleared at the first game of the next New Playoffs (`sub_77E4`).

**Playoff Stats page** (`sub_9428` L33252):
- `sub_1833A`;
- a2 = the user's team struct;
- `d7 = 1`, then the Player Stats page body (`ui_menus.md` §6) with:
  - big title "Playoff  Stats" at window (7,4);
  - no "A - Switch Teams" line and no A key;
  - values from table `$98E6`: goals `$CD96`, assists `$CDCA`, points = `$CD96 + $CDCA`, SOG `$CDFE`, PIM `$CE32`.
- The goalie category (Saves, Shots, Save %) uses categories 3 and 0 (shots against, goals against). The team plate is that of the user's team.
- It opens automatically after every playoff game (`GameOver` L53852-53856, any mode ≠ 0 after `sub_180FC`), and from the playoff pregame menu.
- Shots: `r0_sub_9428_17249.png`, `ps_*.png` (the categories).

---

## 5. Other series, ticker and highlights

### 5.1 Simulation (L47726-47815; `rules_clock_penalties.md` §2 has the code)

- `InitScores` (`StartGame`): only when `gamelevel ≤ 1`. For each round series other than `gamenum` and not over: `gsper = 0`, then `SetScore` 0-2 times (`randomd0(3)`). Scores are not cleared here; `MakeTree` cleared them.
- `UpdateScores` (`PeriodOver`, and once at game start through `loc_17278`):
  - `TickerNum = GetShifter()`;
  - for each series ≠ `gamenum`: clear flags bit 1; if not over, `SetScore`.
- `SetScore`:
  - `gsper` ≥ 4: nothing.
  - `gsper` = 3: final (`gsper` 5) if the margin is ≥ 2; otherwise flags bit 1 ("highlight") and it stays 3.
  - Else `gsper += 1` and each side scores `getscore(own, other)` (0-3 goals, `sctab` by offense nibble + opponent's defense nibble).
- A 3-period game calls `SetScore` 4 times plus 0-2, so by the final intermission every other game is final or flagged. The flagged ones are settled in that intermission (§5.3).
- Port: `GameRules.init_other_games` / `update_other_games` / `getscore` already do the scoring. The pairing rule is §2.4, and the "close game" flag and highlights are missing.

### 5.2 Ticker (`NewTicker*` L47910-47990; layout `ui_ingame.md` §8.1)

- **Heading** = `unk_13488[OptPlayMode ? 1 + gamelevel : 0]`:
  - "EA Hockey Night" (regular season);
  - "Stanley Cup Qualifier" (round 1);
  - "Quarterfinal" (round 2);
  - "Stanley Cup Semifinal" (round 3).

  In the final, `GetShifter` gives a single series, the user's, so no ticker shows. The table has no 5th entry.
- **Order:** `TickerNum` counts down from `GetShifter()`. It skips `gamenum`, flagged games (bit 1, "highlight coming up") and finished series (bit 2).
- **Rows:** visitor first (team2, score2), then home (team1, score1). Period label `unk_191E4[gsper - 1]`: "1ST" "2ND" "3RD" (stored as a digit plus a glyph `$12`-`$14`), "OT", " F".
- **When:**
  - during play, at each penalty screen, once `gameclock ≤ 8:00` (`chkprogress` → `NewTicker`); also in the regular season;
  - in every intermission: each game 150 frames, 60 blank, any pad press stops (§`ui_menus.md` 1.2).
- Seen: `r0_Intermission_1997.png` ("Stanley Cup Qualifier"), `f1_Intermission_103484` ("Quarterfinal").

### 5.3 Highlights: sub_1351C (L48160), sub_1354C (L48180) — U8 resolved

```
sub_1351C: for each round series (GetShifter .. 0): if !over and bclr(flag bit 1) was set: sub_1354C
sub_1354C:
  if sflags3 bit 3 (the intermission was skipped): sub_1381E; return
  sub_13848: save $FFC2EA.. (gmode .. $5BE words) and ScoreSumbytes to $FF0000
  show the game's ticker; Framer 24x3 at window (4,18), "Highlight from game:" at (5,19)
  waitxsr($B4); on a press: restore, sub_1381E, set sflags3 bit 3; return
  live: zamx off, CwdExciteLvl 0, HomeTeam = team1, VisTeam = team2, clearTeamStats,
        restoreteams, both pads off (c1/c2playernum = -1, cont1team = cont2team = 0)
        gameclock = 60 + randomd0(120)   (60..179 s)
        gsp = gsper - 1                   (a flagged game has gsper 3 -> the 3rd period; 4 -> OT)
        HmGoals/AwGoals = score1/score2; gmode = $10 (highlight; bit 1 = odd gsp ends)
        reset the bench, positions from unk_1387C; fade in
  loop DoGameFrame:
        when gmode bit 0 (clock stopped: a goal or any whistle): 180 more frames, then stop
        pad C or Start: stop, and if tied add a goal to a random side (VDP H/V counter bit 0)
  score1/score2 = HmGoals/AwGoals; restore RAM (sub_13862), the side view and the menu; song $79
  gsper = 4; if still tied: loop again (an OT highlight, gsp 3)
  gsper = 5; show its ticker $B4 frames, erase, wait $3C (a press sets sflags3 bit 3)
sub_1381E (skip): if tied, add a goal to a random side (VDP counter bit 0); gsper = 5
```
- A highlight is not "until a goal". It runs to the first stoppage plus 180 frames.
- A tie remains only when the 180 frames ran out; then a new highlight starts in OT.
- Highlights also run in the regular season and at the pregame intermission.
- Shots: `hl_caption.png` ("Highlight from game:" over the San Jose / Los Angeles ticker), `hl_sim.png` (LA-SJ 1-1, 3rd period, 2:27).

---

## 6. End of a playoff game

### 6.1 Stanley Cup clinch: clockcont (L30074, cup part L30092-30121)

At the final horn or the overtime goal (`puckfaceoff` → `loc_7B5C`), when `gsp ≥ 2`:
```
d0 = 7 (assscore)
if gamelevel == 3:
    if bosgames == 7: goto _sc                        ; single-game final
    g = gsstruct[gamenum]; d3 = flipped ? 2 : 0; if HmGoals < AwGoals: d3 ^= 2
    if g.wins[+4 + d3] == 3: goto _sc                 ; this win is the 4th
    goto _t3
_sc: d0 = 8 (assstanley); clear pflags bit 3 (pfjoycon) on objects 0-11
_t3: winner side (tie: _eop); for its 6 objects with position > 0: assinsert(d0); d0 = 7
```
- **G5 is resolved:** `bosgames == 7` means single-game playoffs. Exactly one skater, the first eligible one in object order, gets `assstanley`. `ai_positional.md` already documents the routine: it snaps to a heading toward (±90, Vpos) and shows SPA `$109E` (frame `$D9`, cup overhead). Teammates get `assscore`.
- No team has pad control afterwards.
- The Stars of the Game box follows as in any game. Song `$F` plays only when the home team won (so not for a road cup winner).
- Shots: `m_cup_end.png` (frames 0-400 after the horn), `cup_carrier_x3.png`.

### 6.2 Flow after the final horn (PeriodOver L53805 → GameOver L53851)

1. `UpdateScores`.
2. `AddPOStats` (§4).
3. `Intermission`:
   - `sub_F9CDE` (records, §8.3);
   - menu `unk_131CC[4 + 5]` = `$19E74`, the same rows as the regular-season final menu (`ui_menus.md` §3);
   - ticker; `sub_1351C` (settles the flagged games).
4. `GameOver` → `sub_180FC` (§6.3); then, if mode ≠ 0, `sub_9428` (Playoff Stats).
5. `PlayoffScreen` (§7).
6. Song `$78` → `Opening2`.

### 6.3 sub_180FC (L55268) and sub_18380 (L55538)

```
sub_180FC:
  if OptNOP == 0 (demo) or OptPlayMode == 0 or OptPlayMode == 4: return
  OptPlayMode = TempOptPlayMode = 1
  sub_18380
  MakeTree
  if gamelevel == 4 or gamenum < 0: goto over
  encode -> $FFD088; sub_FE696 (save the $FFD076 block to SRAM, checksum)
  if sflags3 bit 2: decode $FFD176; MakeTree           ; show the finished round on the bracket
  return
over:                                                  ; champion, or the user is out
  clear $FFD088 (5 words); sub_FE696
  OptPlayMode = TempOptPlayMode = (bosgames == 7 ? 2 : 3)     ; back to New Playoffs, same format

sub_18380:
  g = gsstruct[gamenum]; g.score1 = HmGoals; g.score2 = AwGoals       ; team1 is home
  d1, d2 = GetShifter()
  if bosgames == 7: goto single
  for each series s (d1 .. 0) without a 4:            ; uses each game's final score
      d3 = s.flipped ? 2 : 0; if s.score1 < s.score2: d3 ^= 2          ; tie counts for team1
      s.wins[+4 + d3] += 1
  bosgames += 1
  if bosgames == 7: goto round_over
  if neither side of the user's series has 4: return                   ; next game of the series
  if gamelevel >= 3: goto round_over
  for each other series without a 4:                                   ; finish by coin flips
      repeat: if randomd0(200) & 1: wins[+6] += 1 else wins[+4] += 1   ; until one side has 4
  encode -> $FFD176; set sflags3 bit 2
round_over:
  bosgames = 0; bits = 0
  for each series s: if s.wins[+4] != 4: bits |= 1 << s ; clear both wins
  $CEF2 = ($CEF2 & ((1 << d2) - 1)) | (bits << d2); gamelevel += 1
single:
  for each series s: b = (s.score1 <= s.score2); if s.flipped: b ^= 1; bits |= b << s
  $CEF2 = ($CEF2 & ((1 << d2) - 1)) | (bits << d2); gamelevel += 1
```
- The user's series ends at 4 wins. The **other** series advance one game for every user game, each scored by its own `gsstruct` simulation. Once the user's series is decided, the rest are decided by coin flips. In the final round (`gamelevel` 3) the user's series is the only one.
- After the user wins a best-of-7 round:
  - the saved state (`$FFD088`) is the next round;
  - the RAM (and so the bracket screen right after) shows the decided round with its "4-x" scores, decoded from `$FFD176`;
  - the next setup menu decodes `$FFD088` again.
- Seen in the best-of-7 run:
  - after game 3: `bosgames` 3, series wins such as 1-2, 2-1;
  - after game 4 (4-0): the post-game bracket shows 3-4, 1-4, 0-4, 3-4 / 3-4, 4-3, 4-2, 1-4 (`b7_3_PlayoffScreen_loop_146859.png`), and the next menu shows round 2.
- `gamenum < 0` after `MakeTree`: the user's team is not in the new round, i.e. it lost. Seen in the single-game run: Montreal lost the quarterfinal, so mode 2 came back, the state was cleared and the next menu re-seeded.

---

## 7. PlayoffScreen (L53890) — the bracket

Shown in `Opening2` before every playoff game and after `GameOver`. Not shown in mode 0. Shots:
- `po_bracket0.png` (round 1, single game);
- `b7_2_PlayoffScreen_loop_103664.png` (mid-series scores);
- `b7_3_...146859.png` (finished round);
- `r0_PlayoffScreen_loop_17408.png` (QF view, paging);
- `f3_PlayoffScreen_loop_180450.png` (Finals);
- `f3_PlayoffScreen_loop_214533.png` (Champions).

### 7.1 Screen

- **H40.**
  - Plane A at `$E000`, 128 x 32 cells (VDP reg 16 = `$03`), horizontally scrolled by `$FEA0 + DispAttribCtr` (at 0 the view starts at plane column 44).
  - Plane B at `$C000` = the stats-page background `$54E24` (`ui/menus/stats_bg_idx.png`).
  - The window is rows 0-1 (`$9202`).
- **CRAM (targets, faded in with `palcount = $18`):**
  - line 0 = the cup palette (`$F3098`: `600 EEE ECC CCC CAA AAA A88 888 866 666 644 444 422 222 200 000`);
  - line 1 = background line 1;
  - line 2 = background line 1 again;
  - line 3 = background line 0.

  Every 24 frames `sub_175D8` XORs line 2 colour 1 with `$0EE` (`$CCC` ↔ `$C22`): the letters of the **user's plates** blink white / blue (`po_flash_crop.png`).
- **Plates** (`sub_17652`): the 11x2 plate of the team, from the in-game plate map `$ABA14` (`ui/team_plates_idx.png`, rows 2t, 2t+1), at the plane-A cells of the layout table. Plate i shows tree byte i. A plate of the user's team (tree[potreeteam]) is drawn in **line 2**, the others in line 1 (cell words `$40xx` vs `$20xx`, checked in VRAM).
- **Bracket strips** (`sub_17626`): 2 x 23 cells from columns (src, src+1) of the `$B3640` image (12 x 23 cells, line 1, tiles loaded to `ExtraChars`), at plane A (x, 2).
- **Series scores** (`sub_175FC`): "`<+4>-<+6>`" (single digits) of series i at the listed cell, attr `$2000`. Skipped when `bosgames == 7` (single-game playoffs show no scores).
- **Round label** (`unk_176DE`, by `gamelevel`): "Playoffs", "Quarterfinals", "Semifinals", "Finals", "Champions". Plane A, centred on column 65, row 26, attr `$2000`. It scrolls with the bracket.
- **Paging line:** "Press [ or ] to page" (`[`/`]` are the arrow glyphs) at window (10,1), attr `$6000`. Only when `gamelevel ≠ 0`.
- **The cup** is a sprite: `unk_F3098`, one frame of ten 4x4 pieces, 64 x 144 px, line 0, priority, tiles at `word_FFB016`. `sub_FED2A` draws it every frame at sprite (x = `$100 + DispAttribCtr`, y = `$A0`), i.e. screen (128, 32) when not scrolled. It is hidden once x leaves `$40..$200`.
- **Song:** `$79`.

### 7.2 Layout table `unk_1928E`

Plane-A cells; the view's column 0 is plane column 44.

| gamelevel | plates (count: x columns; y rows) | strips (x: src col) | score spots |
|---|---|---|---|
| 0 | 16: x 46 (seeds 0-7) and 71 (8-15); y 2, 5, … 23 | 57:0, 69:10 | (50 / 75; 4, 10, 16, 22) |
| 1 | 24: seeds at x 32 / 85; R1 winners at x 46 / 71, y 4, 10, 15, 21 | 43:0, 57:2, 69:8, 83:10 | (50 / 75; 8, 18) |
| 2 | 28: seeds x 18 / 99; R1 winners x 32 / 85; QF winners x 46 / 71, y 7, 18 | 29:0, 43:2, 57:4, 69:6, 83:8, 97:10 | (50, 13), (75, 13) |
| 3 | 30: seeds x 4 / 113; then 18 / 99, 32 / 85; SF winners x 46 / 71, y 12 | 15:0, 29:2, 43:4, 83:6, 97:8, 111:10 | (63, 23) |
| 4 | 31: as 3, plus the champion at (58, 23) | as 3 | none |

The exact lists are in `playoffs.json` `screen.levels`. The latest round is always in the centre; earlier rounds move outward.

### 7.3 Loop

```
DispAttribCtr = 1; PlayerScrollCtr = -1; sub_17572           ; snaps to 0
loop: sub_175D8 (flash, wait a vblank); sub_FED2A (cup sprite)
      pads 1|2: Start -> exit
                right -> PlayerScrollCtr = -2 ; left -> +2
      sub_17572: d0 = DispAttribCtr + PlayerScrollCtr
                 if |d0| > $70 * min(gamelevel, 3): ignore
                 DispAttribCtr = d0; cup x = d0 + $100 if $40 <= d0 + $100 <= $200 else hidden
                 if d0 % $70 == 0: PlayerScrollCtr = 0          ; stop at each 14-cell page
```
- **Right** moves the view toward the West (right) half of the bracket, 2 px a frame, one 112-px page per press.
- The VBlank handler `loc_17692`: sprite DMA, Hscroll A, `cramfade`, music.

---

## 8. SRAM

### 8.1 Hardware and boot (L61322-61525)

- **Bus:** 8 KB on odd bytes, byte k at `$200001 + 2k`. `WriteSRAM`/`ReadSRAM` (d0 = offset, d1 = count, a0 = RAM).
- **Checksum:** byte `$1FFF` = sum of bytes `0..$1FFD` (mod 256); `$1FFE` = its complement. `ValidateSRAM` → `ValidSRAM` 0 (ok) / `$FFFF`. `MakeSRAMChecksum` re-reads all 8 KB and rewrites the two bytes.
- **InitSaveRAM** (Begin):
  - read all 8 KB into `$FF0000`, validate;
  - if invalid, `ClearSRAM` (zero, `$1FFE = $FF`, byte 0 = 1, checksum) and validate again. A cartridge without SRAM stays invalid: no records (`sub_F9CDE`, Player Cards test `ValidSRAM`).
  - Debug: Start+A+C at power-on runs a write test of all 8 KB and then hangs flashing the screen; Start+B+C checks for the signature `$12345678`.
- **`sub_FE660`** (Begin, `GameSetUp`) reads offset `$1EF6`, `$100` bytes, into `$FFD076`. **`sub_FE696`** writes it back and fixes the checksum.

### 8.2 Map

| Offset | Size | Content | Read / written by |
|---|---|---|---|
| `$0000` | `$B60` | player best games: 4 bytes at `4 * (roster_base[team] + slot)`, `roster_base` = `unk_F9CA4` = 26·team (28 teams × 26 slots) | `sub_F9B94` (+`sub_F9BDA` write) |
| `$0B60` | `$1C0` | team records, 16 bytes at `$B60 + 16·team` | `sub_F9BE2` / `sub_F9C18` |
| `$0D20` | `$80` | user records, 16 bytes, users 0-7 | `sub_F9C20` / `sub_F9C56`; Record Holders `sub_FC282` |
| `$0DA0` | `$80` | user names = `$FFD45A` (12 bytes a user, id 1-7) | `sub_F9C68` / `sub_F9C5E` |
| `$0E20` | — | unused | |
| `$1EF6` | `$100` | `$FFD076` block: `$D076` saved-line team + 1 (0 = none); `$D077-$D086` the line nibbles; `$D088` playoff state; `$D0DC-$D173` packed playoff stats | `sub_FE660` / `sub_FE696` |
| `$1FFE` | 2 | checksum | |

**Saved line** (U6 of `ui_menus.md`): `sub_8928` (L31535, Save Team Line) / `$88C8` (L31438, Load).
- `$D076` = team + 1.
- Then one 4-bit value per entry of the list `$898A`: line-table offsets 1-5, 9-13, `$11-$15`, `$19-$1D`, `$21-$25`, `$29-$2C`, `$31-$34`. That is 33 entries, ending with `$FF` (checked in the ROM bytes), so 17 bytes up to `$D087`.
- The values are packed low nibble first, then high nibble.
- Value = roster slot - 1 - goalie count, minus the forward count as well for offsets ending in 1-2 (the defence positions); i.e. the index within the position group.

### 8.3 Records update at game end: sub_F9CDE (L965016)

Called by `Intermission` when `gsp == 4`.

```
if ValidSRAM < 0 or OptUserRec != 0: return              ; User Records Off = no records
$D448/$D44A = goalie counts (sub_F9FC0 -> sub_9F40)
players: sub_F9F50(home struct, HomeTeam, own user $D043, opp user $D045, opp VisTeam)
         sub_F9F50(away struct, VisTeam, ...)
teams:   sub_F9EAA(home, users $D042/$D044, HomeTeam vs VisTeam); sub_F9EAA(away, ...)
users:   sub_F9DDA(home user, away user, HomeTeam, VisTeam); sub_F9DDA(away user, ...)
MakeSRAMChecksum
```
All "greater" tests are signed byte compares (`cmp.b`), so values above 127 compare low (not reachable in play).

| Record | Bytes | Rule |
|---|---|---|
| **player** (`sub_F9F50`, 26 slots) | +0 best, +1 own user, +2 opponent team, +3 opponent user | skater (slot ≥ goalie count): goals in the game (`$B4`); goalie: saves = `$E8 - $B4` (shots against - goals against). Replaced when strictly greater, win or not |
| **team** (`sub_F9EAA`) | +0 goals, +1 own user, +2 opp team, +3 opp user; +4 best goalie saves, +5 own user, +6 opp team, +7 opp user; +8 crowd dB, +9 own user, +A opp team, +B opp user; +C-F unused | goals = the team's score; saves = the best of its goalies; crowd = `CrowdPeak` (`$FFC314`), **home team only**. Strictly greater, win or not |
| **user** (`sub_F9DDA`) | +0 goals, +1 own team, +2 opp team, +3 opp user; +4 saves, +5 own team, +6 opp team, +7 opp user; +8/9 wins, +A/B games, +C/D ties (words) | games += 1 unless already ≥ 9000, then wins (score >) or ties (=). Goals = own score; saves = opponent shots - opponent goals; both **only in a win** ("TEAM MUST WIN TO QUALIFY"). User 0 (no name) is updated too but never listed |

Verified bytes after a 3-0 Montreal (user 1 "ABCC") win over LA (user 0), slot 6 scoring 3:

| Record | Bytes |
|---|---|
| player MTL slot 6 (`$490`) | `03 01 0A 00` |
| team MTL (`$C10`) | `03 01 0A 00 00 00 00 00 4B 01 0A 00 …` (3 goals; crowd 75 dB) |
| user 1 (`$D30`) | `03 0B 0A 00 00 00 00 00 00 01 00 01 00 00` |
| user 0 (`$D20`) | games 1 |
| checksum | `$69 $96` |

### 8.4 Name Entry: sub_FBB88 (L967859), loc_FB018 (L966782)

`Opening2` runs it when User Records is On. It clears `$D042`/`$D044`. Pad 1 (`cont1team`), then pad 2 if it is on the other team, each get the screen. The chosen id goes to `$D042` for the home side and `$D044` for the away side.

The screen (`u_sel0.png`, `u_edit0.png`, `u_edit1.png`):
- big title "NAME ENTRY";
- "Name Log": 7 rows, `------------` when empty, an arrow pair on the cursor row;
- the team's city and logo;
- an instruction box: "D-Pad up/down to move arrows. Press START to select name. Press B to edit."
- **B → edit:** "Enter new name:" with a 12-character field, and a letter grid `A-Z`, space, `.`, `1`, `2` with a box cursor. Instructions: "D-Pad to a letter. C to select letter. A to go back. B to cancel. START when done."

The names are saved to SRAM `$DA0` (`sub_F9C5E` from `sub_FB9D4`).

**Edit rules.** These were measured on the ROM in Genesis Plus GX (pad-scripted runs; shots and battery-RAM dumps in `/tmp/claude-0/-home-user/ef020377-92e3-57ff-8519-5d51b4a7df4d/scratchpad/xchk/ne/`).
- **Grid:** 5 rows of 6, `ABCDEF GHIJKL MNOPQR STUVWX YZ.12` plus a sixth cell that is a blank (space).
  - The d-pad stops at the edges; it does not wrap.
  - The box is the frame tiles (`framer`, line 1) around the letter's cell. Their black (line 1 colour 7) is see-through, so the background shows inside the box.
- **Field:** 12 positions at (5,18). An empty position shows `-`. The current position has a 7 x 2-pixel bar in the text colour, at pixel row 153 (2 pixels into row 19), with a 1-pixel black shadow down and right.
- **The letter under the box is the current position's letter**, written as the box moves. On entry the position is 0. The box goes to the name's first letter, or `A` for an empty name, which then reads `A`.
- **C** moves to the next position and stops at the 12th; C there does nothing more. If the new position already has a letter, the box jumps to it. Otherwise the box's letter is written there.
- **A** moves back a position in the same way. The letters after it stay.
- **B** cancels: back to the Name Log, with the name unchanged.
- **Start** saves the name and picks that row, as Start on the log does, and the screen moves on. Start on the log only picks.
- **Stored:** the 12 bytes as typed, zero after the last position used. "I", space, "J" is saved as `49 20 4A 00 ...`.

### 8.5 Where records are shown

- **Player Cards** (`$FA07E`, `ui_menus.md` §15.1). The "Records" box, `sub_FA7B0`, prints 3 lines when the value ≠ 0:
  - `<n> Goals by` / `<n> Goal by` (no "by" with user 0); saves use ` Saves`/` Save`; the crowd uses ` dB Crowd Level`;
  - `<own user name> vs.`;
  - `<opp user name> <opp team abbreviation>`.

  The team card shows team +0 (Goals), +4 (Saves) and +8 (crowd). A player card shows the player record (Goals for skaters, Saves for goalies). These are **best single games**, not season totals. Shots: `u_card0.png` ("3 Goals by / ABCC vs. / LA", "75 dB Crowd Level …"), `u_cardb3.png`. Card order: the starting six (G LD RD LW C RW), then the rest by slot.
- **Record Holders** (`$FBC14` L967908). Names from `$FFD45A`; user records read from SRAM `$D20` into `$FFCF36`. Rows on plane B at y = 10, 12 … 22, x = 2: `<rank>. <name>` for users 1-7 in sorted order. A row with no games (page 0) or a zero record (pages 1-2) prints as spaces.
  - Page 0 "Win %  Win-Loss-Tie":
    - columns: win% at x 19 (3 chars), wins x 26 (4), losses x 31 (4) = games - wins - ties, ties x 36 (3);
    - win% = wins·100/games;
    - sort (`sub_FC184`): win% descending, then ties, then games.
  - Page 1 "Goals  Teams": value at x 18; at x 25 `by <own abbr> vs. <opp abbr>`; sort by +0.
  - Page 2 "Saves  Teams": the same with +4.
  - Left/right pages, Start held exits.
  - **A+C on page 0** (`sub_FE6D2` L974217): zero bytes 8-11 (wins and games) of all 8 user records and write them to SRAM. **Ties (12-13) are not cleared** (seen: ties 2 survived). Later losses = games - wins - ties can then go wrong.
  - Shots: `u_rec0.png` (`1. ABCC 100 1 0 0`), `u_rec1.png` (`3 by MTL vs. LA`), `u_rec_t0.png` (20% 1-2-2).
- **Setup screen** (`sub_F87EA` L962807 → `sub_F8868` L962842). Every ~170 frames the menu shows a random player's card in the top box: photo, number and name. Under it (`sub_F98C6`/`sub_F9A64`/`sub_F9AAC`): `Record <n> goals` (`goal`, `saves`, `save`), `by <user>`, `vs. <user> <team>` when the player has a record (`sc_record.png`).
- **Crowd:**
  - `LoadCrowdRec` (L959665, `StartGame`): `CrowdRecord` = the home team's +8, `$50` when 0. It reads SRAM even when User Records is Off.
  - `sub_FEC5E` (L974860, Crowd Meter page): the league record = the largest +8 over all 28 teams (0 counts as `$50`), with that team (scan from 27 down).
  - The Ron Barr Matchups screen says "The Montreal Forum crowd record is 75 dB." (`u_wait_66000.png`).

### 8.6 What an SRAM-less or exhibition port shows

Fresh SRAM: all records 0, user names empty, crowd records 80 dB, no Continue Playoffs. That is what the port shows now (`ui_menus.md` §16).

---

## 9. Playoff menus

- Pregame (`intermission_pregame_playoffs`, `$19B38`): Start Game, Change Goalie, Edit Lines, Team Roster, **Playoff Stats**, Other Scores, Player Cards, Record Holders.
- Between periods: the regular `intermission_period` table.
- After the game (`intermission_final_playoffs`, `$19E74`): the same rows as `intermission_final`. Playoff Stats is not in it; it opens by itself after the game.
- The pause menu has no Playoff Stats row.

---

## 10. Reverse-angle replay (U2 resolved)

**Entry:** in the replay, Start opens the prompt and C sets `$FFC2F4` bit 6. Bits of `$FFC2F4` (a byte; `$1000` in the word view): 4 = reverse on, 6 = toggle request, 7 = "re-apply" marker.

**Toggle: `sub_A528`** (L34928, every replay tick):

```
if !bclr(bit 6): goto normal tick
bchg bit 4
save Hpos, Vpos; forceblack2; 2 vblanks
sub_9CDC: in-game VRAM again, rink tiles = bit 4 ? RevRinkTiles : Rinktiles (L34264-34266)
Hpos = Vpos = 0; Oldrow = $7D0 (forces a full plane-B redraw); setvideo x2
restore Hpos/Vpos; setvideo x2
word +8 of $FFB64A and $FFB6CA = 1
RevReplayAdj: if bit 4: set bit 7; SetRCords        ; redraw the current record at once
sub_A448: replay button panel (from RevRinkTilelist when reversed)
palcount = $64                                      ; fade in
```

**`SetRCords`** (L35038), for each of the 16 recorded objects (`$FFB04A` + `$80`·i):
- x = record x, y = record y; if reverse: **x = -x, y = -y**, and the 16th object (i = 15) gets y + 2.
- frame f = record frame. If reverse: f' = `revframetbl[f]` (`$F600E`); f' is used if 1 ≤ f' < `$34E`, else f.
  - The object with `$52 == $F` and f' ≠ `$18A` gets y = `$FC00` (hidden).
  - f' in `$28D..$291` (glass) gets y = `$190`.
- h/v flip bits 11-12 from the record. If reverse and f' in `$162..$178`: h-flip toggled.
- Camera: Hpos/Vpos from the record; if reverse: negated, then clamped by `sub_A88C` to Hpos -60..60, Vpos -200..256 (`$FF38..$100`).

**Seen** (`rv_n.png` → `rv_r.png`, the same stopped record):

| Object | Normal | Reverse | `revframetbl[f]` |
|---|---|---|---|
| 0 | (-112, -205), frame 36 | (112, 205), frame 16 | `$10` |
| 1 | (-19, -205), frame 1 | (19, 205), frame 21 | `$15` |
| 15 | y -300 | y -1024 (hidden) | |

Flips unchanged otherwise.

**Rendering:**
- plane B uses the reverse rink map (`updatescroll` L51928, `sub_A448`, `setupice` L53052): already exported as `rink/rink_reverse_*`, including the centre-ice logo rotated 180°;
- `showcrowd` (L52176) draws no crowd sprites;
- `sub_FD78A` (L970861) draws no arena animations;
- the replay camera follows the same rules on negated coordinates.

**Exit:** `$FFC2F4` is cleared at game start (L970846) and bit 4 by the replay exit (L34807). Leaving the replay reloads the normal tiles.

Shots: `rv_1.png` (normal), `rv_rev_3.png` (just toggled, panel up), `rv_rev_7.png`.

---

## 11. Port checklist

**Port status (2026-10-16).**

Items 1-10 are done:
- `League` (logic/league.gd) holds the state, `Sram` (logic/sram.gd) saves it, and both live in the Sim autoload.
- Game Setup offers Continue / New Playoffs / New Playoffs/7 game, with their team rows and Players values.
- `ui/playoff_screen.gd` is the bracket. Round 1 matches the emulator shot except the plate-flash phase. The label is centred at 64 - len/2, as seen.
- Playoff Stats is the Player Stats body over `League.po_stats`.
- The playoff intermission tables are used. The clinch is `GameRules.cup_assignment`.
- The ticker headings follow the round.

The highlights (§5.3) are done:
- `ui/highlights.gd` shows the caption and ticker, then plays the close game live in a `HighlightGame` (scenes/highlight.gd) in its own viewport. Players start from `unk_1387C`, the clock is 60-179 s, and the clip ends 180 loops after the first stoppage or on C/Start.
- A tie leads to an overtime clip; a press during the caption skips the rest.
- The port has to set the puck's stalled counter to `$78`. Retail keeps it from the held game's RAM.

Items still open or simplified:
- Done: 4 Way Play in the playoffs. The port always has pads 3 and 4 (`League.four_way`). So the playoff Players row is retail's 4 Way Play row: 7, 8 and 11, with 9-10 skipped. `pojoy = 11 - OptNOP`, and FigureJoy uses `_pojoylist2` with its pad 3/4 rules. A saved two-pad pojoy of 1 or 2 continues as 3 or 4, as `sub_17CA0` does.
- Done: the regular-season quirk of a saved playoff's `gamelevel`. `Sim.league` plays retail's globals. It is decoded whenever Game Setup's cursor passes Continue Playoffs (`sub_17CA0`, saved or not), and it advances with the playoff. A regular-season game takes its `gamelevel` for the slate size (GetShifter), InitScores / UpdateScores and `CwdExciteLvl`.
- Done: the Playoff Stats in the save file in AddPOStats' exact layout (`Sram._pack_stats`). Bit b is bit b & 15 of the big-endian word at `$FFD172 - 2 * (b >> 4)`, so the stats fill `$D0DC-$D173` from the top, and the spare bits are left alone. A playoff saved by an older port build reads back with scrambled stats.

Items 11-12 (records and saved lines) are done too:
- **Records:** `Records.update` runs at the final intermission when User Records is On.
- **Name Entry** (`ui/name_entry.gd`): the select screen matches `u_sel0.png` pixel for pixel. The edit screen follows the edit rules in §8.4 and matches the ROM pixel for pixel in eight edit states (GPGX shots, colour levels compared).
- **Where the records show:**
  - Player Cards "Records" (`_record_lines`);
  - Record Holders (sorted pages, A+C clear);
  - the setup showcase's record lines;
  - `LoadCrowdRec`, plus the Crowd Meter's arena and league records;
  - the Matchups `@` token.
- **Save Team Line** is kept in the block (33 nibbles; the spec's "31" was corrected from the ROM).

Item 13 (the reverse angle) is also done:
- `ReplayRecorder.apply` covers the frames, flips, shadow, glass and camera;
- `HockeyWorld.reverse_angle` holds the state; C in the replay prompt toggles it;
- `Rink2D` draws the reverse rink with the logo rotated;
- `ArenaView` hides the crowd and the arena animations.

Port names: `GameRules` (`logic/game_rules.gd`), `TeamStats`, `HockeyWorld`, `HockeyAI`, `MatchConfig`, `ui/setup_screen.gd`, `ui/pause_menu.gd`, `ui/stats_pages.gd`, `logic/replay.gd`, `ui/replay_view.gd`.

1. **Mode and state.**
   - Add `MatchConfig.play_mode` (0-4) and a `PlayoffState` resource holding:
     - `postarts`, `bosgames`, `gamelevel`, `potreeteam`, `pojoy`, `bracket_bits`;
     - the 8 series `{team1, team2, wins_a, wins_b, gsper, score1, score2, flipped, hilite, over}`;
     - the 104 cumulative stats.
   - `GameRules.opt_play_mode` / `gamelevel` already exist. Save it to `user://` in place of SRAM (one file = the `$FFD076` block). Keep the exact state fields (§3) so "Continue" works; the 80-bit encoding itself is optional.
2. **New playoffs** (§2.2-2.4):
   - seedings from `playoffs.json` (All-Star → Winnipeg rule);
   - `MakeTree` (tree from bracket bits; flip by `bosgames` ∈ {2,3,5});
   - `FigureJoy`: home/away and pads from `pojoylist`; Opt2Team for the setup row.
   - `ui/setup_screen.gd`: Play Mode list = the 5 retail strings ("Continue Playoffs" only when a state exists); Team 2 shows the opponent; Players: One / Two - Teammates / Two - Head to Head.
3. **Regular-season slate** (U1): replace the shuffle in `GameRules.init_other_games` with `sub_18002`: 8 pairs of distinct random teams 0-25 excluding home and away (`randomd0(26)` with rejection). Keep `GetShifter` (the count depends on `gamelevel`) if the quirk is wanted.
4. **Other games as series:**
   - `update_other_games` = `UpdateScores`/`SetScore` with the close-game flag (margin ≤ 1 at `gsper` 3 → flagged, stays 3);
   - `InitScores` (0-2 extra periods, `gamelevel` ≤ 1);
   - skip the user's series (`gamenum`) and finished series.
   - Highlights: either the live sim (§5.3) or `sub_1381E` only (a random goal when tied, `gsper` 5). The cheap version is exact for a skipped intermission.
5. **Ticker heading by round** (§5.2), visitor row first; no ticker in the final.
6. **Clinch:** in `GameRules.end_of_period` (`clockcont` port), use `HockeyAI.ASS_STANLEY` for the first eligible winner when `gamelevel == 3` and (`bosgames == 7` or the winner's wins == 3), clear pad control on objects 0-11 (G5).
7. **Overtime:** playoff OT is already ported (`period_over` with `opt_play_mode != 0`, `reset_clock` normal length).
8. **After the game** (`GameRules.game_over` / `scenes/game.gd`):
   - `AddPOStats` (sum `TeamStats.player_goals/assists/shots/pim` of the user's team into the cumulative arrays, clamp widths 10/10/14/12 by index mod 4 if bit-exact);
   - `sub_18380` + `MakeTree` + save / clear;
   - then the Playoff Stats page, then the bracket screen;
   - mode back to New Playoffs on elimination or after the cup.
9. **Playoff Stats page:** `ui/stats_pages.gd` Player Stats body with the cumulative arrays, title "Playoff  Stats", no team switch. Add the row back (`pause_menu.gd` `DROPPED`) and use `intermission_pregame_playoffs` in playoffs.
10. **Bracket screen** (§7): a 1024 x 224 plane with `stats_bg` behind it, plates (`ui/team_plates_idx.png`, line 2 for the user with the line-2 colour-1 flash), strips (`bracket_idx.png`), scores, round label, the cup sprite (`cup_idx.png`, line 0) moving with the scroll, the paging text, song `$79`, 2 px/frame paging in 112-px steps.
11. **Records** (optional, needs a persistent file):
    - User Records option, Name Entry (7 users);
    - `sub_F9CDE` at game end (player/team/user rules of §8.3, with `GameRules.crowd_peak`);
    - Player Cards "Records", Record Holders lists and the A+C clear (keep or fix the ties quirk);
    - `GameRules.crowd_record_value` from the home team's record (else 80);
    - the league record on the Crowd Meter.
12. **Saved lines:** persist the Save/Load Team Line slot in the same file (retail keeps it in SRAM).
13. **Reverse angle** (§10):
    - in `replay.gd` `apply` (SetRCords): negate x/y, map frames via `replay_reverse.json` `revframetbl`, toggle h-flip for `$162..$178`, hide the shadow and glass cases;
    - negate and clamp the camera;
    - swap the rink layers to `rink/rink_reverse_*`; hide the crowd and arena animations;
    - fade in. `replay_view.gd` C in the prompt toggles.

---

## 12. Exported assets (`tools/extract/playoffs.py` → `godot/assets/ui/playoffs/`)

| File | Content |
|---|---|
| `playoffs.json` | teams; 32 seedings; the bracket screen (planes, scroll, CRAM lines, plate/strip/score/label/page-text rules, cup and strip image metadata, `levels` = `unk_1928E` decoded); ticker headings, period labels, highlight caption; setup Play Mode / Players strings; `_pojoylist`, `_pojoylist2`, `_noplist`; save-state radices; packed-stat widths |
| `records.json` | SRAM map, roster bases, player/team/user record layouts and update rules, every record string, Record Holders columns and sorts, Player Cards format, crowd rules |
| `replay_reverse.json` | `revframetbl` (846 words) and the reverse-angle rules |
| `cup_idx.png` | the cup sprite, 64 x 144, line 0 |
| `bracket_idx.png` | the strip image, 96 x 184 (12 x 23 cells), line 1 |

Index textures as in `assets.py` (R = colour index · 17, G = line · 85, A = 255 where drawn). The run is deterministic. `--preview DIR` writes RGB renders of plane A per `gamelevel` (`preview_level0..4.png`) with seeding 0; they match the emulator's plate and strip cells.

---

## 13. Screenshots

All in `/tmp/claude-0/-home-user/ef020377-92e3-57ff-8519-5d51b4a7df4d/scratchpad/po/`.

| File | What |
|---|---|
| `m_playoffs_overview.png` | montage of 16 key screens (setup, brackets, stats, ticker, highlight, Name Entry, cards, records, Matchups, reverse angle) |
| `m1.png` | setup menu, New Playoffs (Montreal vs Quebec, seeding 3) |
| `po_bracket0.png` | bracket before round 1 |
| `r0_PlayoffScreen_loop_17408.png` | after round 1 (QF view, paging text) |
| `b7_2_PlayoffScreen_loop_103664.png` | best-of-7 after 3 games |
| `b7_3_PlayoffScreen_loop_146859.png` | best-of-7 round decided (4-x) |
| `f3_PlayoffScreen_loop_180450.png` | Finals |
| `f3_PlayoffScreen_loop_214533.png` | Champions |
| `po_flash_crop.png` | the user plate flash |
| `r0_Intermission_1997.png`, `r0_Intermission_6012.png`, `f1_Intermission_103484.png` | playoff intermissions with ticker |
| `hl_caption.png`, `hl_sim.png` | highlight |
| `r0_sub_9428_17249.png`, `ps_0..8.png` | Playoff Stats |
| `m_cup_end.png`, `cup_carrier_x3.png` | the clinch, cup overhead |
| `u_sel0.png`, `u_edit0.png`, `u_edit1.png` | Name Entry |
| `u_card0.png`, `u_cardb3.png` | Player Cards records |
| `u_rec0.png`, `u_rec1.png`, `u_rec_t0.png` | Record Holders |
| `sc_record.png` | setup-screen card with a record |
| `u_wait_66000.png` | Matchups screen naming the crowd record |
| `rv_1.png`, `rv_rev_3.png`, `rv_rev_7.png`, `rv_n.png`, `rv_r.png` | reverse angle |

---

## 14. UNRESOLVED

- **P1.** The "Players" row in playoff mode was not driven on the emulator. Its range (5-7 two-pad, 7-11 four-way?) is read from `GameSetUp_3` limits (L960873-960890) only. The four-way `pojoy` / `_pojoylist2` / cont3-4 rules (L55064-55089) were not exercised.
- **P2.** Name Entry was measured on the ROM (§8.4), not decoded. The listing's inline print data is mis-decoded. Editing a name that already has letters, and A at position 0, were not driven.
- **P3.** The Ron Barr Matchups text (`sub_FCC76`, `unk_4B5C0` script) was seen naming the arena crowd record. Whether other records (players, users) appear in its messages was not read.
- **P4.** The setup screen's card timer (`sub_F87EA`: `$D43C` = `$AA`, the `$52` toggle of the team side, `$D42E` bits) is summarised, not decoded line by line.
- **P5.** What RAM `$FFD17A-$FFD259` holds (cleared by `sub_77E4` at the first game of a new playoff) was not checked; it overlaps the sound driver's variables (`$FFD182`).
- **P6.** The bracket screen's per-plate attribute arithmetic in `dobitmap` (why printa `$6000` yields line 2) is taken from the VRAM result, not from `dobitmap`'s code.
- **P7.** On real hardware the Playoff Stats goalie category table read at `$98E2` would be the instruction word `$4E75` if category −1 ever reached `sub_98CE`. The page uses categories 0 and 3 for goalies, so it does not, but the sort path for category −1 (`sub_9872` in `d7 = 1` mode) was not traced.
