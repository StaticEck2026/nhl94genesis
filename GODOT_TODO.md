# NHL 94 Godot 4 rebuild: progress tracker

This file tracks the Godot 4 native rebuild in `godot/`. It is separate from the bitwise segment pass in `SEGMENT_AGENT.md`, which it does not touch.

Rules for this track:

- No emulation. No 68000, VDP, Z80, YM2612 or PSG. No ROM or RAM dump read at runtime.
- `lst/nhl94.bin.lst` is the behavior reference. Each translated routine cites its listing label and line.
- Fixed point becomes floats in px, px/s and radians. The conversion lives in `godot/core/nhl94_units.gd`.
- Every balance number is an exported, documented property. Defaults keep the retail value.
- Assets are loose `.png`, `.wav` and `.ogg`. `extractAssets94.js` may be used offline to produce them. The game never reads `nhl94.bin`.

Run the tests from `godot/` with Godot 4.4 or later. The script fails on any script error, not only on failed checks:

```text
tests/run_tests.sh /path/to/godot
```

Play with `godot --path godot`: the setup screen picks the teams, who controls each side and the options, then the match runs from the opening faceoff to the final horn. Pad 1 is the arrow keys with Z / X / C for A / B / C and Enter for Start; pad 2 is WASD with G / H / J and Space; real pads work too. `scenes/skate_sandbox.tscn` is the skating sandbox (no rules).

Status keys: `[x]` done, `[~]` started, `[ ]` not started. Add the commit or a note after an item when it changes.

## Research specs

Behavior specs read from the listing live in `docs/specs/`: collisions and checking, puck, shooting and passing, goalie, positional AI, puck-carrier AI, clock and penalties, faceoffs and offsides, input and line changes, team data and attributes, animation and assets. Each port cites its spec. Where two specs disagreed (handedness offset), the listing decides and the tracker records it.

## Confirmed translation facts

These come from the listing. Add a fact here before code depends on it.

| Fact | Retail form | Godot form | Source |
|---|---|---|---|
| Logic step | `d7` = vblanks since last loop, NTSC 60 Hz | `frames := delta * 60.0` | `DoGameFrame` L29914 |
| Position | 32-bit 16.16, high word is the pixel | `Vector2` px | `updateplayers` L35517-35530 |
| Position step | `pos += vel * 17 * d7` (`$16` = 22 when `word_FFD06E` is set) | `px/s = vel * 17 * 60 / 65536` | `updateplayers` L35490-35530 |
| Skate drag | `vel -= max(1, vel >> 6)` per loop, `>> 9` when `pfdoff` (pass receive, puck) | `vel *= 1 - 1/64` per loop | `updateplayers` L35496-35515 |
| Run speed | `dirtab` 8 directions, 200 (`$C8`), 141 diagonal | unit vector * 200 | `dirtab` L43933 |
| Goalie flag | `$34(a3)` is 0 for a goalie, positive for a skater, negative off the ice | `Skater.is_goalie` | `doplayeracc` L43331 (`beq goalieacc`), `updateplayers` L35455 |
| Skate accel | `dirtab * ((64 - wgt/4 + agl [+2 boost] [goalie: +agl+16]) / 2) >> 5 * d7`. Halved for a joypad goalie carrying the puck. | `SkaterMotion.accel()` | `playeracc` L43705 |
| Accel into boards | an axis of the push is dropped when it points along the last board normal | `accel(..., wall)` | `playeracc` L43711-43725 |
| Max speed | `MaxSpeed[i] = ((i + 20) * 275)^2` compared to `vx^2 + vy^2`. `i = spd/2` scaled by energy `/ $1000`. Odd `spd` takes half a step. | `SkaterMotion.max_speed()` | `MaxSpeed` L43855 |
| Max speed cuts | goalie carrying the puck: squared max `/2`. Fight injury: squared max `/8`. Skaters with the puck are not slowed. | `max / sqrt(2)`, `max / sqrt(8)` | `playeracc` L43809-43826 |
| Facing | `facedir` long, 16.16 over 8 directions (`1 << 16` = 45 degrees) | `State.facing_fx` | `doplayeracc` L43424 |
| Turning | each loop facing moves toward the stick by `max($300 - (speed^2 >> 16), $180) * 16`. The push goes along facing, not the stick. Under `speed^2 >> 16 <= 2` it turns in place without pushing. Turn anim when `speed^2 >> 16 > $14`. | `SkaterSteering.steer()` | `doplayeracc` L43424-43466 |
| Hockey stop | stick straight back while moving along facing: `dostop`. Stick straight back while still: snap facing 45 degrees. | `_no_turn()` | `noturn0` L43644 |
| Backwards skating | on: no puck, own half, stick straight back, puck in the front 135 degrees, and still or drifting within 45 degrees of the stick. Holds while the stick is within 45 degrees of back and the puck is in the front 225 degrees. | `_update_reverse()` | `doplayeracc` L43360-43418 |
| Loop order | per object: save old pos, drag, move, assignment (steer, push), clear board normal, `checkcoll` only if the pixel position changed | `Skater2D.retail_loop()` | `updateplayers` L35335, L35666-35683 |
| Rink | origin center ice, Y up. Sidelines x = +-136 (`$88`), end boards y = +-298 (`$12A`), corner radius 64 (`$40`). Goal lines y = +-264 (`$108`). Offside line y = +-84 (`$54`), players checked at +-94. | `RinkBoards`, `Rink2D` | `checkwallcoll2` L49549, `ChkOffsides` L42598, `prepshot` L37574 |
| Wall radius | skaters (8, 4), puck (5, 5), nets at y = +-268 (`$10C`) with (20, 6) | `Skater2D.wall_radius` | `defaultsprites2` L53407 |
| Board bounce | normal speed `vn`, tangent `vt`. Skater: ignore if moving away faster than 1000, else new normal speed `-vn/4`, at least 1000 away from the board. Puck: `-vn/4`, tangent loses 3/128, pops up when `-vn/4 <= -$400`. | `RinkBoards.bounce_*()` | `wallcoll` L50143 |
| Stop, no anim | `vel -= 150` (`$96`) toward 0 per call | `stop_decel` | `stopna` L43908 |
| Stop with anim | stop anim when `|vel| > $1000` on either axis, glide anim when skating backwards | FSM `STOPPING` | `dostop` L43876 |
| Puck stick bungee | puck moves 1/4 of the gap to the carrier hot spot per loop, copies carrier velocity | `PuckPhysics.follow_carrier()` | `pucknorm` L42526 |
| Z gravity | only while the Z word or Zvel is non-zero: `Zvel -= 102 * d7` (6 x step), `Zpos += Zvel * 17 * d7`. Landing: `Zpos = 0`, `Zvel = -Zvel / 2`, puck-on-ice sound `$2C + (5 - Zvel low byte)` when 0-3. Drag is skipped while the Z word is non-zero. | `HockeyWorld._integrate()` | `updateplayers` L35517-35555 |
| RNG | `seed = seed * $BB40E62D + 1`; `randomd0(n) = ((seed >> 8) & $FFFF) * n >> 16`; `randomd0s(n) = randomd0(2n) - n`. Seeded from the VDP counter. | `RetailRng` | `randomd0` L44190 |
| Crowd boost | `set_bit1_C2FE` always sets `byte_FFC2FE` bit 1 (the clear path is dead), so `playeracc` always adds +2 agility and +2 speed (cap 30) | `HockeyWorld.crowd_boost = true` | L975179 |
| 94 struct changes | `$74` fight byte, `$75` checking (new in 94), `$76` handedness; `pflags2` bit 2 unavailable, 3 line-change menu, 4 penalized, 5 no collision, 6 hurt in a fight | `SimObject` | collisions, data, input specs |
| Momentum exchange | masses `weight + $8C`, `evalue` is always 0 (perfectly plastic along the normal), outputs scaled by `|D|^2/256`, one exchange per `checkcoll` call | `Collisions.exchange()` | `checkcx` L48617 |
| Puck pickup | stick tip within 14 px (7 px while a pass is in flight); glued if speed <= Stk * 350 + 13000 rvu (13000 for a shot in flight), else deflected and the skater locked out 8 frames | `PuckLogic.puckstick()` | L50534 |
| Steals | carried puck within 6 px of an opposing stick (8 in the slot): steal when `randomd0(c - k + 36) <= 2` (4 in the slot), c and k the energy-scaled Stk/2; goalies always win, nobody steals from a goalie; the puck is knocked loose, not taken | `puckstick()` | L50566 |
| Goal | puck within 21 x 7 px of the net centre, below the crossbar (Z 13), entering through the mouth at |x| <= 20; x = 21 is the post | `PuckLogic.checkgoal()` | L49633 |
| Glass | Z above 18 leaves the rink everywhere except the top end, whose glass is 29 high | `over_glass()` | L50092 |
| Shot power | `k = energy-scaled shotspd/2 + 20`; `ps = (k * charge) * $5249 >> 16` (charge = 15 + vblanks held during the windup, about 35 full); speed `ps * 68` rvu; backhand loses 1/4 of the charge, a one-timer uses 31 | `Shooting.doshot()` | L37514 |
| Shot accuracy | perfect with chance (acc+1)/(acc+16) within 200 px; else error `((ps>>4) - acc/2 + 16) * dist >> 6`, halved within 250 px, capped 136 (Y 60) | `doshot()` | L37514 |
| Pass speed | `160 + 2 * passacc` (+1/16 for odd ratings); receiver = nearest teammate within 45 degrees of the aim, 45 degrees costs 65536 in squared distance | `dopass()` | L36924 |
| Buttons | B pass (fires on release or a held direction), C shot (hold to charge), A flip pass (tap or hold 15 loops); without the puck: B switch (tap) or goalie (hold 17 loops, Manual Goalie), C burst or one-timer, A hold | `InputLogic` | `doinput` L35886 |
| `sroot` | odd-number subtraction up to $640, Newton (10 steps, not always floor) to $F00000, bisection above | `RinkBoards.sroot()` | L44215 |
| Struct | 16 sort objects of 128 bytes; field names and flag bits from the 93 equates in `src/ram94.asm` | `SimObject` | `ram94.asm` |

## Open questions

- [x] `$34(a3)` meaning. 0 is a goalie (`doplayeracc` branches to `goalieacc` on 0). The extra agility and the carrier cuts in `playeracc` are goalie-only. Fixed in `SkaterMotion`.
- [~] Drag runs once per loop, not per vblank. The usual retail `d7` is unmeasured; `SimSettings.loop_vblanks` (default 1) sets it so the feel can be matched against hardware.
- [x] `word_FFD06E` is the VDP status bit 0 at boot, the PAL flag (the listing calls it DMA busy): PAL consoles move 22 per vblank instead of 17. `HockeyWorld.alt_step`.
- [x] Energy (`getpde`/`setpde`, L51186-51229): full is `$1000`; drain and recovery ported as retail (data spec section 4).
- [x] Rating scale: `$67` is the weight step x 8 (0-120); the rest are `AttributeCalc` 0-30. `PlayerData` uses the retail 25-99 screen values.
- [x] Rink size in px and the origin. See the Rink row above.
- [x] One-shot animation lengths: real SPAList timings now (the stand-in only runs when the data file is missing).
- [x] Where stick value 9 (brake) comes from: never the pad (`jdtab` gives 0-8). `skateto` sends 9 when its target is within 12 px on both axes (L42978).
- [x] `sroot` (L44215): ported exactly (Phase 4).

## Phase 0. Project scaffold

- [x] `godot/project.godot`: 320x224, stretch `viewport`, aspect `keep`, nearest filter, 2D pixel snap
- [x] Audio buses `Master`, `Sfx`, `Crowd`, `Announcer`, `Music` in `default_bus_layout.tres`
- [x] Folder layout: `core/`, `data/`, `logic/`, `nodes/`, `scenes/`, `ui/`, `assets/`, `addons/`, `tests/`
- [x] `Nhl94Units` fixed-point conversion helpers
- [x] `SimSettings` resource: tuning values and module toggles shared by the game and the dock
- [x] Headless test runner `tests/run_tests.gd`
- [x] Input map (2 pads, 3 buttons + start, keyboard defaults) from `tools/setup_input_map.gd`
- [x] `tests/run_tests.sh` fails on a failed check, an unfinished test, or any `SCRIPT ERROR`

## Phase 1. Data layer

- [x] `PlayerData`: ratings on the retail roster-screen scale (25-99), `rom_bytes()` rebuilds the 8 roster bytes exactly, `overall()` is the retail Overall
- [x] `TeamData`: the retail record (roster groups, 8 lines, PP/PK/home/away bonuses, ticker rows, CRAM palettes)
- [x] Extraction: `tools/extract/teams.py` reads the ROM team table at `$30E` (not `teamdata94.asm`, which is '93 data) and writes `godot/data/teams/*.tres`: 28 teams, 684 players, every nibble round-trips
- [x] Attribute math: `AttributeCalc` L959917 (with its one-form-byte quirk), `checkattriblimits`, `Create_HotCold_Table` L959871; display math (`CalcAttrib` weights, `AttribAdjust`) for the UI
- [x] `setplayer` L51556 (`RosterLogic`): PP / PK / home-away / 3rd-period bonuses, the `$73` wrap, sprite flip from handedness; team setup `sub_171BE` (RAM lines). `SetPersonel` / `SetPlList` come with the line-change port (Phase 8)

## Phase 2. Skater movement

- [x] `SkaterMotion` (`playeracc`, `MaxSpeed`, drag, `stopna`)
- [x] Turning and momentum: `SkaterSteering` (`doplayeracc` L43331, `noturn0`, `vtoa`, backwards skating, hockey stop)
- [x] Goalie skating: `goalieacc` L43477, `stopna2` L959753 (`GoalieLogic`; `HockeyWorld.skate` routes position 0 there)
- [x] `burst` L36830, `holdplayer` L36863
- [x] `skateto` L42953, `skatetopuck` L43138, `avdgoal` L43026 (`HockeyAI`)
- [x] Wall collision: boards, corners, nets (`checkgoal`/`checkgoalp`), the stick-tip board check, the puck over the glass, `CheckBump`
- [x] Player-player collision: `Collisions` (`checkplcoll`, `checkcx`, exact momentum exchange, Y-sort walk order, position restore)
- [x] Energy and fatigue: `playeracc` drain (1 in 128 calls, endurance), bench recovery in `periodiceevents`; drain, gate and recovery are tunables
- [x] `scenes/skater.tscn`: `CharacterBody2D`, capsule, runs `SkaterMotion` + `SkaterSteering` + `RinkBoards` in retail loop order
- [x] `scenes/skate_sandbox.tscn`: two pad-controlled skaters, readout of retail values (the main scene is now the setup screen)

## Phase 3. Puck

- [x] `PuckLogic`: `pucknorm` (carrier bungee, stall whistle), `findpc` (crossing prediction), Z stall counter, `puckflip`/`puckunflip`/`puckshadow`
- [x] Pickup and steals: `puckstick`, `CheckStkForContactWithSkater`, `_glue` (faceoff and pass credit, human control hand-off)
- [x] Puck vs bodies and goalies: `puckbody`, `puckgoalie` (body box by agility, cover threshold), `deflect`
- [x] Nets and goals: `checkwallcoll2` routing, `checkgoal` (box, posts, crossbar, back of the net, goal with stats and ScoreSum), `checkgoalp` + `CheckBump` for players, `setass`
- [x] Over the glass and the goal-light easter egg (`wallcollb2`); `ChkShotStat`; icing (`a2touchpuck`, `puckIChk`); offside flags (`ChkOffsides`, `a2offsides`)
- [x] Hotlist exported offline (`tools/extract/hotlist.py` -> `godot/data/hotlist.json`); `GetHot` uses facing until sprite frames are live
- [x] `PuckView` draws puck and shadow from the world

## Phase 4. Shooting and passing

- [x] Shots: `SetShotMode`, `ShotMode` (charge by elapsed vblanks, aim, forced release under shotspd 20), `prepshot` (top shelf), `doshot` (power, accuracy error, elevation, direction guard), `shotdiradj`/`shotdirmath` (CPU aims away from the goalie), `puckvzadj`
- [x] Passing: `setpassmode`, `passmode`, `dopass` (receiver cone, blind pass, 94 flip pass), `passto`, `passtoa0` (lead pass, integer for integer), `Findhittype` (decoded from ROM)
- [x] One-timers: `assonetimer`, `onetimershot`, `setonetimeranim`/`noidea`, `sub_F6C44`, `sub_FEFF0`
- [x] Pass reception: `asspassrec` (glide with `pfdoff`, CPU one-timer decision); `assshoot` (CPU windup)
- [x] Input: `PadState` (`ReadJoyN`, `jdtab`, opposite-direction cleanup) and `doinput` (B pass / switch / sweep / goalie hold, C shot / burst / one-timer, A flip pass / hold, start), `chgplayer`, `Sweepcheck`, `burst`

## Phase 5. Checking and fighting

- [x] `Checking`: `newcheck`, `checkint`/`checkint_ci` (goalie contact, interference), `CCStart`/`CheckingCalc` (body checks), `checkagr`, `holdcheck`, `Bcheck`, `holdplayer`/`Acheck`
- [x] `FallDown`, `FallList`, board pins (`sub_FEB54`), injuries (`setInjuryType`), `wallcollduringcheck`
- [x] `burst` (body-check charge); `check4check` (CPU) in `HockeyAI`
- [x] `checkfight` L49544, `fightinput` L36560: no-ops in retail '94 (see Phase 8); the fight patch fills them in (Phase 12)

## Phase 6. AI

- [x] Assignment dispatch `asstab` L56671, `assinsert`/`assreplace`/`assexit` L43192-43210, `Setplass`, `forcepldata` L51446 (`setplayer` stubbed until Phase 1)
- [x] Offense: `assdefo` L38375, `asswingo` L38682, `asscentero` L38856, `asspuckc` L39901, `chk4shot` L40183, `chk4pass` L40337, `compshoot`, `EvadePC` L40442, the carrier's evade (`loc_E12C`), the tired-line dump (`sub_E1F4`), `checkob` (delayed offside ref)
- [x] Defense: `assdefd` L38447, `asswingd` L38591, `asscenterd` L38800, `check4check` L40878, `assnearest` L40574 (hand-off, chase / contain, slot pressure)
- [x] Faceoffs (`FaceoffLogic`): `assfaceoff` L38206, `assfaceoffpl` L38218, `puckfaceoff` L41627, `puckfaceoff2` L42031 (line-up tables, drop countdown), `Endfaceoff` (the draw formula), `updatefaceoff` L42414, `setchgplayer`, `resetplstuff`
- [x] Breakaway, shootout and penalty shot: `breakaway` L39775, `BreakawayOffsidesFlagSet`, `chkpuckc`, `assbreakaway`; the CPU shooter's script (`sub_FE756`, `sub_FE7FC`, `sub_FE864`, `sub_FE8EC`) drives `asspuckc` in PS/SO
- [x] Slot bit (`setSlotBit` L963062), celebrations (`assscore`, `assstanley`), `check4bench`. The "9x5 grid" is an overlay only: retail AI uses the zone thresholds in the spec, not a grid
- [x] `HockeyAI` RefCounted; `SimSettings.enable_skater_ai` idles the CPU skater assignments

## Phase 7. Goalie

- [x] `goalieacc` L43477, `assgoaliecpu` L39072 (crease box, angle cutting with the `puckcross` lookahead, rebound dive, hold-puck whistle, pass look), `assgoaliectrl` L38963 (range whistle, off-camera hand-back), `sub_DB3E`, `sub_DB68`
- [x] `goaliesave` L39598 (all ten save animations and the reach-out glove), `assgoalietopuck` L39731, `assgoaliebreakwait` L38175. `chkgoalie` L37366 (auto-goalie redirect in PS/SO) comes with Phase 8
- [x] Pull goalie: `ReadGoaliePulled` L975229, `ChkGoalies` L41839, `ReturnGoalies`, `CPgoalie` (exactly two down, retail). `SetPersonel` is a hook until the line-change port
- [x] Reaction latency: `SimSettings.goalie_reaction_frames` adds frames to the decision reload (0 = retail, aidef / 4); `enable_goalie_tracking` idles the CPU goalie

## Phase 8. Rules and game flow

- [x] Clock and periods (`GameRules`): the VBlank clock tick ($AAA fraction), `ResetClock` L29817, `ClockLength`, `StartGame`, `StartPer` L29853, `clockcont`, end of period / OT winner (`loc_7B5C`), `PeriodOver` L53805, intermission bookkeeping, game over. `setupice` resets the objects and swaps ends each period
- [x] Offsides and icing whistles: `ChkOffsides`, `a2offsides`, `a2touchpuck`, `puckIChk` (Phase 3) now stop play through the queue
- [x] Penalties: `AddPenalty` L45939, `PenaltyList` L56708 (all 30 records), `checkfornewpen` (delayed penalties), `Stop4Pen` + `limitfo` (faceoff spots), `chkprogress`, `InProgress` (assessment, coincidental majors, PenSum), `updatepentime` (box time, beeps, return to ice), `sub_123DE`, the referee script (`SetPA`, `UpdatePA`), power play `updatepwrplay` L46991, PP goals `sub_1284A`
- [x] Line changes (`LineLogic`): `SetPersonel` L51236, `SetPlList` L51300 (sublist substitutes), `findAvailablePlayer`, `ResetBench`, `CompLine` + `getlinee`, `SetLCmode` L36566, `getlchoice`, `lineinput` L36756, `lcfound`; `assbench` L37886, `assben`, `asspenalty`, `assdopen`, `assepen`; `restorep1` in `set_c_player`
- [x] Crowd: `UpdateCwdExcite` L30009, `updatecrowdf` L30028 (the `_cd0` frames and the camera flash), the crowd meter and record (`Crowd_Noise?`, `PrintScores1`; the record makes the AI react a frame faster)
- [x] Pause menu (PauseMode L30217, the pausing pad's team): Timeout ($9D7A, the contain flag and rest for both teams), Change Goalie ($9DE6), Edit Lines (port layout), the Manual/Auto Goalie toggle; setup options Line changes On/Off/Auto (`no_fatigue`) and Goalie Manual/Auto Control. Not ported: the stats pages and the instant replay
- [x] The `updateplayers` preamble (the one-timer and breakaway bits, the crowd-record bit) and the AI audit's minor deviations M1-M9 (docs/specs/audit_ai.md section 6)
- [x] Stats: `ChkShotStat` L47451 (Phase 3), team and player stats in `TeamStats`, PenSum. `InitScores` / `UpdateScores` (other games' ticker) not ported: cosmetic, and it needs the season/playoff mode
- [x] Penalty shot and shootout (`ShootoutLogic`, spec `docs/specs/shootout_penaltyshot.md`): `PenShotChk` L46100 and `getBAplayerInfo` (the shifted variants, Q1), `puckshootout` L41046, `sub_EE58` (the shooter), `puckpenshot` L41276, `sub_1592C`, the intro and its skip, the 25-second attempt clock in the VBlank, `sub_F2F4` / `sub_F37C` (end of the attempt), the PS/SO goal, and the Shootout play mode: `sub_FC47C`, `sub_FC4C0`, `sub_FC516` (home then away, five rounds, then sudden death), `sub_FD618` (the winners skate on), the decided ref text. The "Shootout SetUp" menu that reorders the lists (U2) is not ported: the lists come from each team's first line
- [x] Fights: none in '94 (`fightinput`, `assfight`, `assfwatch` are `rts`; no caller raises the fighting penalties)

## Phase 9. Scenes and presentation

- [x] Rink: `Rink2D` builds two `TileMapLayer`s from the extracted map (base under the sprites; the priority cells, near boards and glass, over them), the home team's centre-ice logo, and the sideways penalty-screen view for `SetHor`. Placeholder drawing remains when the art is missing
- [x] Camera: `checkwindow` L35783 ported into the world (`HockeyWorld.camera` = Hpos/Vpos with `yleader`); `RinkCamera` shows it. The tile scroll itself (`updatescroll` L51912) comes with the `TileMapLayer` rink.
- [x] Sprites: `tools/extract/assets.py` exports all 845 frames into one index atlas (`assets/sprites/atlas_idx.png`) with `frames.json` (origin, hot spot); `SpriteAtlas` draws them with the `addframe2` flips; `find3d`'s projection (height lift, sideways view) in `SortObjectView`; Y-sorted like `SprSort`
- [x] Team palette swap: `shaders/palette.gdshader` colours the index art from a 16x4 CRAM texture (`PaletteBank`: rink lines, home and away uniforms; away objects use line 3 for line 2)
- [x] Animation tables: `SPAList` exported offline (`tools/extract/spalist.py` -> `godot/data/spalist.json`, 66 animations); `updateanim` ported (`Animator`) with the one-loop lag, de-glitch, loop bit and flag clearing; sprite frames are live, so `GetHot` uses the real Hotlist
- [~] Audio: crowd noise is the PSG noise channel; `updatesound` (asv) is ported and drives a looped noise on the `Crowd` bus. The 15 DAC samples export to `assets/audio/dac/*.wav`; `SfxBank` plays `sfx_XX` / `song_XX` files by retail id when present and names every id seen at the call sites. The sound effects themselves are FM sequences (`unk_2C648`): which sample and note each id plays is unresolved, so no `sfx_XX` files are generated yet
- [x] Tile decompressor (`sub_1177A`): all 16 commands decoded (`$Cx/$Dx/$Fx` are back references copied backwards, `$E0 00` ends the stream); every compressed blob decodes to exactly its tile count
- [x] Face-off close-up (`checkfo`): the close-up frames and the `FaceOffMap` window exported; `FaceoffWindow` draws the centres and the referee from `fofdata`
- [x] Referee window (`PushRef`, `showref`): `RefsMap` (7 frames on the rink) and the penalty screen's 17 frames exported; `RefWindow` follows `ref_signal`. The calls' text shows in the HUD
- [x] Sprite priority: the rink's high-priority layer draws colour 0 transparent, so players show through the near glass between its posts and streaks; sprites with attribute bit 15 (the puck over the glass, the bottom goal light) draw over it (`SortObjectView.z_for`). Spec `docs/specs/indicators_and_priority.md`
- [x] Indicators (setffo / uppads / checksso): the puck-carrier and pad stars with the jersey number and position letter (font `$AAC52`), and the off-screen arrows (`IndicatorsView`)
- [x] Arena sprites (`tools/extract/arena.py`, `ArenaAnim`, `ArenaView`, spec `docs/specs/arena_animations.md`): the animated crowd and camera flashes, the penalty-box figures, the eight background animations (fans at the glass, the hat-trick hats, the benches standing up) with their faceoff, hat-trick and boards triggers, and the intermission's side view with the zamboni
- [x] Animation audit (`docs/specs/audit_animation.md` section 8): injured players stop sliding, the glass shatter, puck shadow, GetHot and one-timer fixes, the away palette from attribute bit 0

## Phase 10. Editor tooling

- [x] `nhl94_debug` `EditorPlugin` and `Nhl94DebugDock.tscn`
- [x] Dock sliders and module toggles bound to `SimSettings`
- [x] `@tool` `_draw()` overlays: goalie cones, pass lines, interception radii, 9x5 grid (`DebugOverlay`; always in the editor, in game with `show_in_game`)
- [x] Live editing while the game runs: the dock sends changes over the debugger channel (`EditorDebuggerPlugin`) to the `Sim` autoload's `nhl94` capture (not exercised by the headless tests)

## Phase 11. UI

- [x] Setup screen: Team 1 / Team 2 `OptionButton`, line `ItemList` (the real Sc1-PK2 lines), reads `TeamData`; the play mode (Regular Game or Shootout)
- [x] HUD: clock, score, period, power play, referee calls, penalties, intermission and final banners; the penalty shot / shootout intro box and the attempt clock
- [x] Pause menu (Start; during an intermission Start resumes play instead)
- [x] Line-change box (`sub_B92E`): rows A / B / C with the line each sends and its energy, while a pad's menu is open
- [x] Title screen (`newTitleScreen` $FF042): the photo, the shield / NHLPA logo / title sliding in on plane B's line scroll, the fade-in, the scrolling credits, Start to the menus; frame for frame with the ROM (`tools/extract/title.py`, `ui/title_screen.gd`, spec `docs/specs/title_screen.md`)
- [x] Injury message (`loc_1871C`): "Injury to:", the player, out for the period or the game

## Phase 12. Chaos81's fight patch (nhl94-patches v1.01)

Spec: `docs/specs/fight_patch.md` (and `fight_patch_retail_hooks.md`). The setup screen's edition picks retail '94 or "NHL Hockey '94-Fight".

- [x] Fight code (`FightLogic`): `checkfight`, `ChkFightValue` (instigator minor), `SF`, `assfight`, `chkhit`, `CwdFight`, `FightFall` (Fighting * for the winner, the fight injury and its `$112C` box time), `assfwatch`, `fightinput`, the banner, the gloves (`upgloves`); the period-length and Arcade tables
- [x] Sprites, hot spots and the nine fight animations from the patched ROM (`tools/extract/fight_patch.py`); the gloves view behind the players
- [x] The patch's rosters (enforcers' fight ratings raised, some moved onto the checking line): `data/teams_fight/`
- [x] Menu option Fighting: Off / On / On - Arcade Mode (default On); the patch's Fgt column (0-100) in the setup screen's line tooltips
- [x] The patch's title screen and credits; its ROM name on the window
- [x] Not applicable to a native port: ROM expansion and the SRAM relocation, the checksum skip, the reverse-angle replay fixes (no replay yet), the Shootout SetUp and demo-mode menu fixes (those menus are not ported)

## Log

- 2026-10-11: Tracker written. Godot scaffold, data resources, `SkaterMotion`, `PuckPhysics` carrier follow, debug dock. 55 headless checks pass on Godot 4.4.1, including all 16 `MaxSpeed` entries against the ROM table.
- 2026-10-11: Phase 2 turning. `$34` resolved (0 = goalie), which moves the extra agility and carrier cuts to goalies only. `SkaterSteering` (facing, turning, hockey stop, backwards skating), `RinkBoards` (boards, corners, bounce), rink constants, input map, skater scene and sandbox. 130 checks pass. Sandbox checked in screenshots under Xvfb.
- 2026-10-11: World refactor. `HockeyWorld` owns the 16 retail objects and globals and steps `updateplayers`; `SimObject` mirrors the struct; nodes are views (`HockeyGame`, `Skater2D`). Retail RNG ported. Z gravity fact corrected. Research specs for every remaining subsystem are being written to `docs/specs/`.
- 2026-10-11: Player collision and checking ported (`Collisions`, `Checking`): momentum exchange, Y-sort walk, goalie contact and interference, body checks, holds, sweeps, falls, board pins, injuries. Crowd boost found to be always on. 165 checks pass.

- 2026-10-11: Puck ported (`PuckLogic`): pickup, steals, ricochets, goalie body box, nets, posts, goals with stats, offside and icing hooks, over the glass. Hotlist exported offline. All ten research specs landed. 191 checks pass.
- 2026-10-11: Animation system ported (`Animator`, SPAList export). Sprite frames are live and `GetHot` reads the real Hotlist. Attribute word bits fixed (x flip is bit 11). 200 checks pass.
- 2026-10-11: Shooting, passing, one-timers, bursts and pad input ported (`Shooting`, `InputLogic`, `PadState`); exact `sroot`. A shot taken through the pad scores on an empty net end to end. 226 checks pass.
- 2026-10-11: AI and goalies ported (`HockeyAI`, `GoalieLogic`): the six positional routines, `assnearest`, the CPU carrier (shoot / pass / evade / breakaway), `check4check`, celebrations, the CPU and pad goalie, saves, pulling the goalie, `checkwindow` camera, `forcepldata`. `DoGameFrame` order in `step()`. Twelve CPU players play a minute (shots, passes, checks, goalie whistles). 260 checks pass.
- 2026-10-11: Data layer: 28 teams and 684 players extracted from the ROM to `.tres`; `setplayer`, `AttributeCalc`, form, bonuses and the energy drain ported. The spec's seven test vectors (Bourque, Oates, Lemieux, Neely, Dollas, Moog, Roy) match byte for byte. 330 checks pass.
- 2026-10-11: Rules and game flow (`GameRules`, `FaceoffLogic`, `LineLogic`): clock, periods, OT, whistles, faceoff spots and the full faceoff, penalties with delayed calls and the box, power play, line changes and the line menu. The match scene now plays a whole game from `StartGame`; the sandbox runs without rules (`HockeyGame.run_rules`, `SimSettings.enable_rules`). A CPU Boston-Montreal game runs to the final horn in the tests. 396 checks pass.
- 2026-10-11: Presentation: the ROM art exported offline (845 sprite frames in an index atlas, rink tiles and map, 28 logos, the side view, palettes, DAC samples). The match renders with the real rink as `TileMapLayer`s, team-coloured sprites through a palette shader, the retail camera, and the sideways penalty screen. Debug overlays default to the editor only.
- 2026-10-11: Penalty shots and the shootout (`ShootoutLogic`). A foul on a breakaway skater becomes a penalty shot: the attempt is set up, played with the CPU script or the pads, and the game resumes with a faceoff. The Shootout play mode (setup screen Play Mode) plays alternating attempts to a winner. The nets, puck and shadow now start with no animation, as the struct clear leaves them (the puck had shown a skater frame until its first touch). 492 checks pass.
- 2026-10-11: Chaos81's fight patch (Phase 12) and the title screen. In the '94-Fight edition a hard hit between two willing players (fight ratings, checks thrown) can start a fight: gloves drop, the banner names them, punches land until one goes down, both take majors (Fighting * for the winner), an injured loser is out for the game. The game boots into the title screen, retail's or the patch's. setInjuryType now writes tmpdst as retail does. 599 checks pass.
- 2026-10-11: AI and animation completeness, the glass, indicators. Audits of every asstab assignment and every animation path against the listing (`docs/specs/audit_ai.md`, `audit_animation.md`). Players now show through the near glass, the stars, numbers and off-screen arrows are drawn, and the crowd, penalty box, arena animations and intermission zamboni are on screen. The pause menu has Timeout, Change Goalie, Edit Lines and the goalie-control toggle; the setup screen has auto line changes and goalie control. Playoffs (assstanley), multitap and the replay/demo are documented as not applicable. 1068 checks pass.
