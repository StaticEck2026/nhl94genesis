# Audit: retail '94 AI and assignment logic vs the Godot port

Scope: every `asstab` entry, the helpers the assignments call, and the per-frame AI in `DoGameFrame` / `periodiceevents` / `updateplayers`. Only behaviour that changes play is ranked as a gap. Presentation-only routines are listed at the end.

Method: I dumped `asstab` from the ROM at `$18D7C` and mapped every entry to its listing label. I walked the retail call graph from all 36 entries plus `updateplayers` and `periodiceevents`, and checked each callee against the port by name. I then compared the control flow of every assignment routine against the listing branch by branch. Finally I grepped the port for TODO, stub, "not ported", simplified, approximation, placeholder, later, hook and stand-in.

## 1. asstab (ROM `$18D7C`, listing L56671-56707)

The table holds 36 long pointers, ids `$00`-`$23`, and ends at `$18E0C`, where `PenaltyList` starts (L56708). `HockeyWorld.asstab` (hockey_world.gd:127) is filled by the `register()` calls at hockey_world.gd:333-345. An id with no entry does nothing (hockey_world.gd:658), which matches a bare `rts`.

| id | label | ROM | listing | bare rts | port registration | GDScript | status |
|---|---|---|---|---|---|---|---|
| $00 | rtss2 | $15464 | L50810 | yes | not registered (unknown id = no-op) | - | rts-only, equivalent |
| $01 | assdefo | $CD00 | L38375 | | HockeyAI.register | hockey_ai.gd:296 `assdefo` | implemented |
| $02 | assdefd | $CDE0 | L38447 | | HockeyAI | hockey_ai.gd:320 `assdefd` | implemented |
| $03 | asswingd | $CF9A | L38591 | | HockeyAI | hockey_ai.gd:374 `asswingd` | implemented |
| $04 | asswingo | $D09C | L38682 | | HockeyAI | hockey_ai.gd:405 `asswingo` | implemented |
| $05 | asscenterd | $D1E8 | L38800 | | HockeyAI | hockey_ai.gd:444 `asscenterd` | implemented |
| $06 | asscentero | $D294 | L38856 | | HockeyAI | hockey_ai.gd:461 `asscentero` | implemented |
| $07 | assscore | $CC4E | L38315 | | HockeyAI | hockey_ai.gd:675 `assscore` | implemented |
| $08 | assstanley | $CBFA | L38287 | | HockeyAI | hockey_ai.gd:703 `assstanley` | implemented, **never assigned** (G5) |
| $09 | assben | $C882 | L37993 | | LineLogic.register | line_logic.gd:384 `assben` | implemented |
| $0A | assepen | $CA50 | L38135 | | LineLogic | line_logic.gd:461 `assepen` | implemented |
| $0B | assbench | $C710 | L37886 | | LineLogic | line_logic.gd:319 `assbench` | implemented (M1) |
| $0C | asspenalty | $C8F0 | L38026 | | LineLogic | line_logic.gd:407 `asspenalty` | implemented |
| $0D | assdopen | $CA2A | L38119 | | LineLogic | line_logic.gd:453 `assdopen` | implemented |
| $0E | assgoaliecpu | $D51C | L39072 | | GoalieLogic.register | goalie_logic.gd:69 `assgoaliecpu` | implemented |
| $0F | assgoalietopuck | $DD2E | L39731 | | GoalieLogic | goalie_logic.gd:381 `assgoalietopuck` | implemented |
| $10 | asspuckc | $DF18 | L39901 | | HockeyAI | hockey_ai.gd:778 `asspuckc` | implemented |
| $11 | assnearest | $E6F4 | L40574 | | HockeyAI | hockey_ai.gd:486 `assnearest` | implemented |
| $12 | assshoot | $EC82 | L41029 | | hockey_world.gd:339 | shooting.gd:538 `assshoot` | implemented |
| $13 | asspassrec | $EB84 | L40938 | | hockey_world.gd:340 | shooting.gd:495 `asspassrec` | implemented |
| $14 | assfight | $CBE0 | L38266 | yes | FightLogic.register | fight_logic.gd:223 (fight patch) | rts in retail; the patch routine is registered but unreachable when `opt_fight == 0` |
| $15 | assfwatch | $CBE2 | L38269 | yes | FightLogic | fight_logic.gd:372 (fight patch) | same as $14 |
| $16 | assfaceoff | $CB3A | L38206 | | FaceoffLogic.register | faceoff_logic.gd:369 `assfaceoff` | implemented |
| $17 | assfaceoffpl | $CB50 | L38218 | | FaceoffLogic | faceoff_logic.gd:377 `assfaceoffpl` | implemented |
| $18 | pucknorm | $FF0C | L42526 | | hockey_world.gd:343 | puck_logic.gd:59 `pucknorm` | implemented |
| $19 | puckshadow | $102EC | L42862 | | hockey_world.gd:344 | puck_logic.gd:271 `puckshadow` | implemented (M6) |
| $1A | puckunflip | $102A8 | L42831 | | hockey_world.gd:345 | puck_logic.gd:256 `puckunflip` | implemented |
| $1B | puckfaceoff | $F3E4 | L41627 | | FaceoffLogic | faceoff_logic.gd:59 `puckfaceoff` | implemented |
| $1C | puckfaceoff2 | $F88E | L42031 | | FaceoffLogic | faceoff_logic.gd:165 `puckfaceoff2` | implemented (M9) |
| $1D | assgoaliectrl | $D3C6 | L38963 | | GoalieLogic | goalie_logic.gd:403 `assgoaliectrl` | implemented |
| $1E | puckshootout | $ECB6 | L41046 | | ShootoutLogic.register | shootout_logic.gd:139 `puckshootout` | implemented |
| $1F | puckpenshot | $EF92 | L41276 | | ShootoutLogic | shootout_logic.gd:229 `puckpenshot` | implemented |
| $20 | assgoaliebreakwait | $CAE0 | L38175 | | GoalieLogic | goalie_logic.gd:498 `assgoaliebreakwait` | implemented |
| $21 | chkpuckc | $DEEE | L39886 | | HockeyAI | hockey_ai.gd:759 `chkpuckc` | implemented (falls into asspuckc, as retail) |
| $22 | assbreakaway | $E6CE | L40557 | | HockeyAI | hockey_ai.gd:769 `assbreakaway` | implemented (falls into assnearest, as retail) |
| $23 | assonetimer | $F693E | L959091 | | hockey_world.gd:341 | shooting.gd:573 `assonetimer` | implemented (M4) |

The listing prints entries $10 and $11 as raw `$DF18` and `$E6F4`. These are exactly `asspuckc` and `assnearest`: `chkpuckc` and `assbreakaway` end on the instruction before each one.

All 35 non-trivial ids are registered. Control flow matches the listing branch by branch for all six positional routines, `assnearest` with `check4check`, the carrier chain (`asspuckc`, `chk4shot`, `compshoot`'s stack pop, `chk4pass`, `checkob`, `sub_E1F4`, the `loc_E12C` evade, `breakaway`, `BreakawayOffsidesFlagSet`), `EvadePC`, `skateto` and `skatetopuck`, all four goalie routines with `goaliesave`, the five bench and box trips, `assscore` and `assstanley`, `asspassrec`, `assshoot` and `assonetimer`. The port has no function that returns early as unimplemented.

## 2. Gaps, most important first

### G1. Missing `updateplayers` preamble: the one-timer goalie box stays stuck (HIGH, frequent)

Retail L35354-35371 runs once per loop, before the object walk:

- L35354-35358 `byte_FFC2FC` bit 6 = `CurCrowdMeter >= CrowdRecord` (see G4).
- L35361-35364: when `puckc >= 0`, it clears `byte_FFC2FE` bit 7 (a one-timer touched the puck) and `word_FFC2F8` bit 1 (the shot is a one-timer).
- L35366-35371: when the carrier has the breakaway bit (`$64` bit 1), it clears `word_FFC2FA` bit 4 (the shot is a breakaway).

The port's `HockeyWorld.update_players` (hockey_world.gd:559) has none of this. It clears `C2F8_ONETIMER_SHOT` only in `puckfaceoff` (faceoff_logic.gd:91, retail L41663).

Effect: `checkpuckcoll` (L50460-50465, port puck_logic.gd:363-365) uses the smallest goalie body box (`$C`, `$90`) while the bit is set. In the port, the bit is set by `onetimershot` (shooting.gd:669) and by `puckshootout` (shootout_logic.gd:153, retail L41074). It then stays set until the next faceoff. So after any one-timer, every goalie plays with the minimum body box until the whistle, and a penalty-shot or shootout goalie keeps it for the whole attempt. Retail drops it as soon as anyone has the puck.

The bit 7 and bit 4 clears are stats only: one-timer goals and breakaway goals get extra credit in the port.

Fix: put the preamble at the top of `update_players`.

### G2. Pause-menu "Timeout" not ported (MEDIUM-HIGH, human teams; resolves ai_positional.md U1)

- The handler at `$9D7A` (L34283-34308) is reached from the pause menu table `unk_19700` (L58935; the "Timeout" item's pointer is at ROM `$19824`). The pausing pad's team is chosen by `sub_7E0E`.
- The handler sets that team's flags `$30(a2)` bit 2 (L34286). It calls `sub_13098` (L47575) for both teams, which refills all 26 energy slots to `$1000`. It shows "Timeout" and waits 120 loops.
- Once the bit is set, `PauseMode` (L30235-30238) shows `unk_1988C`, the same menu without Timeout, so a team gets one timeout per game.
- `$30` bit 2 is cleared only by `clearTeamStats` at `StartGame`. For the rest of the game, that team's `assnearest` always contains instead of chasing (L40770). It also clamps the contain Y to `±$44` once past `±$53` (L40791-40804).
- The port has the reads (hockey_ai.gd:581 and :599, `flags30 & (1 << 2)`) but nothing sets the bit, and there is no energy refill. ui/pause_menu.gd offers only Resume and Quit.

Where it belongs: pause_menu.gd, plus a world method that sets a new `TeamStats` timeout bit (bit 2) and refills `stats[0..1].energy`.

### G3. Pause-menu "Change Goalie" not ported (MEDIUM, human teams)

- The handler at `$9DE6` (L34310-34362) lets a human pull the goalie or swap goalies.
- Row 0 writes `$26(a2) = $FFFF`, then calls `SetPersonel` (L34355-34359). Other rows write the goalie index.
- A human pull (`$FFFF`) survives faceoffs, because `ReturnGoalies` skips `$FFFF` (L41881-41883). A CPU or delayed-penalty pull (`st` gives `$FFxx`) is returned at every faceoff.
- The port's `TeamStats.goalie_pulled` is a plain bool, set only by `chk_goalies` and `cp_goalie` and cleared for everyone by `return_goalies` (goalie_logic.gd:540). There is no human path and no state that survives faceoffs.

Where it belongs: pause_menu.gd and goalie_logic.gd (`return_goalies` must leave a human-pulled `$FFFF` state alone).

### G4. Crowd meter and crowd record not ported, so the AI's crowd-record bonus never fires (MEDIUM-LOW)

- `Crowd_Noise?` (L959685-959748), called every loop from `setvideo`, works out when the crowd is loud: `CwdExciteLvl >= (CrowdRecord - $49)^2 / 4 + 6`, gated by `word_FFC304`, which `puckfaceoff2` and goals set and `Endfaceoff` clears (L42456).
- While loud, every 20 loops it sets `CurCrowdMeter = sroot(CwdExciteLvl * 4) + $41`.
- `LoadCrowdRec` (L959665) loads `CrowdRecord` from SRAM for the home team, `$50` when there is none. `CurCrowdMeter` is cleared at `StartPer` (L29891).
- `updateplayers` L35354-35358 sets `byte_FFC2FC` bit 6 while `CurCrowdMeter >= CrowdRecord`. The meter is not recomputed when the crowd quiets down, so the bit can persist until the next period.
- Consumers that matter: the reload of every AI reaction timer loses 1 when it is non-zero. That covers assdefo L38393, assdefd L38463, asswingd L38607, asswingo L38699, asscenterd L38816, asscentero L38873, assgoaliectrl L39055, assgoaliecpu L39201, assgoalietopuck L39745, asspuckc L39966 and assnearest L40634, for both teams.
- The other readers (playeracc L43734 and L43779, Bcheck L49119, checkpuckcoll L50432, assnearest L40812) are ORed with the always-set `byte_FFC2FE` bit 1, so they are unaffected.
- In the port, `HockeyWorld.crowd_record` (hockey_world.gd:253) is never assigned. It is read at hockey_ai.gd:112 and goalie_logic.gd:53.

Where it belongs: GameRules (crowd: CurCrowdMeter, the loud state, `word_FFC304`) and the G1 preamble.

### G5. assstanley is unreachable: no playoff and Cup path in `clockcont` (LOW-MEDIUM)

- `clockcont` L30092-30111 handles the final round (`gamelevel == 3`). When `bosgames == 7` or this win is the series' 4th (`gsstruct` `gspotwins == 3`), the first skater with `position > 0` on the winning team gets assignment `$08`, the rest get `$07`, and `pfjoycon` is cleared on all 12 objects, so the pads lose control.
- The port's `GameRules.end_of_period` (game_rules.gd:639-659) always uses `$07`. `gamelevel` exists (game_rules.gd:84) but there is no playoff mode.
- The meaning of `bosgames == 7` was not traced (UNRESOLVED).

### G6. Retail options whose code is ported but cannot be reached (LOW)

- (a) **Auto line changes:** `OptLine == 2` sets `byte_FFC2FC` bit 4 (GameSetUp L962431-962434). This resolves faceoffs_offsides.md U4. Effects:
  - energy reads as full for speed (L43771) and burst (L36837);
  - no human line menu (L36570);
  - no tired-line dump (L40125);
  - the CPU picks lines for human teams (L41744).

  `HockeyWorld.no_fatigue` and all its consumers are ported, but `MatchConfig` has only a line-change bool.
- (b) **Goalie control:** `OptGoalie` is copied to `word_FFD05A` and `word_FFD05C` (L962424-962426), and the pause "Manual Goalie" toggle points to `$FE1D8` (pointer at ROM `$19880`). The port's `HockeyWorld.auto_goalie` is fixed at `[true, true]` (hockey_world.gd:222), which equals non-zero `FFD05A` (Auto). There is no setup option and no pause toggle.
- (c) **"Edit Lines"** (pause menu, `$82DA`) is not ported.

### G7. Four-way play (multitap): ported 2026-10-16

- `HockeyWorld.cont_team`, `c_player`, `pads`, `b_cnt` and `a_timer` hold four pads. `swap_pad(p)` is retail's register swap: pad 3 trades places with pad 1 and pad 4 with pad 2. The swap covers the team, the player, the pad words, the B and A counter words (`word_FFBF06`/`FFBF08`, `word_FFD41E`/`FFD420`) and the stars (`word_FFBE78`/`FFBE86`, ffo 1-2 against ffo 4-5).
- `updateplayers` (L35598-35665): pads 3 and 4 run `doinput` in the borrowed slot. `joypuckcarrier` is 0 or 1, and Start pauses as pad 3 or 4 (`real_pad`).
- `setchgplayer` (L42370): pads 3 and 4 pick their player in the borrowed slot.
- puckstick `_setd0player` (L50710-50737): a pad 3 or 4 player keeps the pad. With either of those pads in play, a pad's goalie does too.
- `assonetimer` (L959109-959140): `TmpJoyPuckCarrier` hands the shooter to pad 3 or 4.
- `checksso` (L52455): the arrows for pads 3 and 4 (frames `$346`, `$349`).
- Pause and intermission: pads 3 and 4 open the menu and drive it (`getpzjoy`, `waitxsr`). The menu is pad 1's or pad 2's team (`sub_7E0E` reads `sflags` bit 1, which `startpause3`/`startpause4` set as pad 1 or pad 2).
- Setup: `MatchConfig.Driver` PADS12, PADS13 and PADS24 give retail's `OptNOP` combinations (`_noplist`). Pad 3 always joins pad 1's side and pad 4 pad 2's.

### G8. Replay, demo and attract mode (LOW, no effect on play)

- Not ported:
  - `updatereplay` (L35236), `SetRCords` (L35038), Instant Replay and the reverse angle. `GM_HL` is never set in the port, so the `GM_HL` branches stay inert, as they do in retail live play.
  - The demo: `GameSetUp` random teams (L960200-960209) and `demoread` (L30159).
- CPU against CPU is still playable from the setup screen.

## 3. Minor deviations (all verified against the listing)

| # | retail | port | effect |
|---|---|---|---|
| M1 | `assbench` `_nobench` path, when newpnum equals pnum (L37977-37986): position from newpos and Setplass only. setplayer runs only on `_done` (L37962-37966). | line_logic.gd:336-339 goes through `_bench_place` (373-381), which always calls `setplayer`. | Ratings reload with the current PP, PK and 3rd-period bonuses, and pflags2 bit 6 is cleared. |
| M2 | `updateplayers` skips drag, move and Z for SPA `$145C` and `$1AF4` (injured lying, L35483-35486). | `_integrate` (hockey_world.gd:616) has no skip. | An injured player can be slid by velocity from collisions. |
| M3 | `chk4pass` writes `passdir` before the lane check (L40403-40404). | Written only when the pass is made (hockey_ai.gd:974). | `passdir` differs after a CPU pass is turned down. No reader that depends on it was found. |
| M4 | `assonetimer` window divisor is `$11`, or `$16` with PAL `word_FFD06E` (L959230-959233). | Always 17 (shooting.gd `assonetimer`). | PAL (`alt_step`) only. |
| M5 | `checkob` calls PushRef only when `RefCnt < 0` (L40536-40538). | `ref_signal` is always emitted (hockey_ai.gd:998 and :1001). | Presentation. |
| M6 | `puckshadow` adds 1 to X in horizontal mode (L42869-42873). | Always adds to Y (puck_logic.gd:274). | Cosmetic. |
| M7 | `assnearest`'s slot-timer halving does not check `puckc >= 0` (L40642-40660), so a stale slot bit with no carrier counts as a home carrier. | Needs `_other_team_carrier` (hockey_ai.gd:509). | One-loop edge case. |
| M8 | `sub_FF7E2` (L976500-976556) pushes `sflags2` and restores it on every exit (ROM `$FF7E6` / `$FF884`), so it never changes PWRPLAY or PWRTM; it only picks the PP song and sets `byte_FFC2FE` bit 6. | `_setup` (faceoff_logic.gd:238-244) sets PWRPLAY and PWRTM. | `updatepwrplay` (game_rules.gd:548) then finds PWRPLAY already set and skips the PP-opportunity count (retail L47023) and `sub_12D70`. Stats only. The spec (faceoffs_offsides.md section 5, step 18) is wrong here. |
| M9 | `asspenalty` and `updateplayers` call `sub_C656` (L38034, L35565). | Not called. | Pad-marker word only (cosmetic). |
| M10 | `assfight` and `assfwatch` are `rts`. | Patch routines are registered in both editions. | No effect: nothing assigns `$14` or `$15` when `opt_fight == 0`. |
| M11 | VDP H/V counter reads (asswingo/asscentero `& $7F`, check4check and asspuckc `& 3`, the evade's `& 1`). | `hv_rng` stand-in (ai_positional.md U2, accepted). | Distribution only. |

These port additions differ from retail only when changed from their defaults: `SimSettings.goalie_reaction_frames` (default 0), `enable_skater_ai`, `enable_goalie_tracking` and `enable_puck_friction`.

## 4. Port comments flagged by the grep

- rink_boards.gd:9 "checkgoal ... is not ported yet": stale. `checkgoal` is ported (puck_logic.gd:562, called at hockey_world.gd:886). Fixed.
- skater_steering.gd:7 "goalieacc ... not ported yet": stale. It is ported at goalie_logic.gd:434. Fixed.
- checking.gd:354 `sub_FE510(7)` background animation: now started through `background_anim` → `ArenaAnim.start` (arena_animations.md).
- checking.gd:402, puck_logic.gd:109 and puck_logic.gd:224 refer to spec U3 / U1 / U3: deliberate, documented choices.
- puck_logic.gd:512: the save-rating tables are dropped because retail computes and discards them. Matches retail.
- checking.gd:60-66 and hockey_world.gd:96: H/V counter stand-ins (M11).
- hockey_world.gd:582: the updateanim fallback, used only when the SPAList data is missing.
- hockey_world.gd:730 and the shootout spec's "Port hook" entries (`ps_waypoint`, `ps_should_shoot`, `ps_attempt_check`, `ps_attempt_end`): all implemented (hockey_world.gd:767-771 and 1050-1055).
- The "hook" items in fight_patch_retail_hooks.md section 13 (items 1-8) are closed by Phase 12. Item 9 (PenSum overflow) is rules, not AI.
- There are no TODO, FIXME, stub or "unimplemented" markers in godot/logic.

## 5. Spec items still open (AI-relevant)

- **Resolved here:**
  - ai_positional U1 is the Timeout bit (G2).
  - faceoffs_offsides U4 is `OptLine == 2` (G6a).
  - ai_positional U3 (`puck_pflags2` bit 0) is never set in retail; the fight edition sets it, and the port honours it (hockey_ai.gd:191).
- **Still UNRESOLVED:**
  - ai_positional U4: `_alist` entry 6.
  - ai_puckcarrier U1: `_postab2` indexed by raw position; ported as-is.
  - ai_puckcarrier U3: bit names.
  - goalie U1, U3 and U4: the findpc overflow, the xflip/handedness question, and the intent of the chkgoalie redirect.
  - faceoffs U1, U2 and U5: the stale d0 in `sub_100A6`, Stop4Pen's a0 from FallDown, and `word_FFD412`.
  - shootout U1, U4 and U5: chgplayer's d6, stoppages during an attempt, and CPgoalie at puckshootout.
  - collisions U2 and U3: the puck's `$34` acting as a goalie, and Stop4Pen's a0.
  - data_attributes U1: energy-drain rate from VDP timing.
  - The meaning of `bosgames == 7` (G5).
  - Retail default values of the menu options: the `defmenuoptions` labels at L54847-54856 may be offset and were not checked against the menu text.
- **Spec correction:** faceoffs_offsides.md section 5, step 18 (`sub_FF7E2` does not change `sflags2`; see M8). The port now follows the listing.

## 6. Port status (this round)

| Item | Status | Where |
|---|---|---|
| G1 updateplayers preamble | done | `HockeyWorld._preamble` |
| G2 Timeout | done | pause menu (ui/pause_menu.gd), `HockeyWorld.timeout`, `TeamStats.F30_TIMEOUT`; the row is gone once used and in a shootout (unk_1988C / unk_19664) |
| G3 Change Goalie | done | pause menu, `GoalieLogic.change_goalie` / `goalie_row` (row 0 pulls him for good, a CPU pull ignores it) |
| G4 crowd meter and record | done | `GameRules.crowd_noise`, `print_scores1`, `HockeyWorld.crowd_record` |
| G5 assstanley | not applicable | no playoff mode in the port; `gamelevel` never reaches 3 |
| G6a Auto line changes | done | setup screen "Line changes: Auto" → `MatchConfig.auto_lines` → `HockeyWorld.no_fatigue` |
| G6b Goalie control | done | setup screen "Goalie: Manual/Auto Control" → `auto_goalie`; pause toggle `HockeyWorld.toggle_goalie_control` (the pausing pad's word, both when the pads share a team) |
| G6c Edit Lines | done (port layout) | pause menu → `LineLogic.edit_line`: line, slot, roster player; a player already on the line trades places. Retail's screen layout was not decoded. |
| G7 multitap | done | `HockeyWorld.swap_pad`, four pads, setup drivers PADS12 / PADS13 / PADS24, actions `p3_*` / `p4_*` |
| G8 replay, demo | not applicable | no replay buffer or attract mode; CPU against CPU is playable from the setup screen |
| M1 assbench stay-on path | done | `LineLogic._nobench2` (no setplayer) |
| M2 injured slide | done | `_integrate` skips SPA `$145C` / `$1AF4` |
| M3 passdir | done | written before the lane check |
| M4 PAL one-timer divisor | done | `0x16 if alt_step else 17` |
| M5 checkob PushRef | done | only while `refcnt < 0` |
| M6 puckshadow horizontal | done | +1 to X |
| M7 slot halving | done | a carrier number of 5 or less (none included) counts as home |
| M8 sub_FF7E2 | done | `FaceoffLogic._pp_song`: picks the power-play tune and sets `byte_FFC2FE` bit 6, leaves PWRPLAY/PWRTM to updatepwrplay; the mid-period and power-play tunes play at the end of the setup (L42316-42328) |
| M9 sub_C656 | done | `HockeyWorld.marks` (the puck-carrier and pad nibbles) |
| M10, M11 | accepted | as described above |
