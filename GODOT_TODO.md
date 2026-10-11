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

Play the skating sandbox with `godot --path godot`. P1 is the arrow keys, P2 is WASD, or pads 1 and 2.

Status keys: `[x]` done, `[~]` started, `[ ]` not started. Add the commit or a note after an item when it changes.

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
| Struct | 16 sort objects of 128 bytes; field names and flag bits from the 93 equates in `src/ram94.asm` | `SimObject` | `ram94.asm` |

## Open questions

- [x] `$34(a3)` meaning. 0 is a goalie (`doplayeracc` branches to `goalieacc` on 0). The extra agility and the carrier cuts in `playeracc` are goalie-only. Fixed in `SkaterMotion`.
- [ ] Drag runs once per loop, not per vblank. Measure the usual `d7` in a game (1 or 2) so per-second drag matches retail feel.
- [ ] `word_FFD06E` (step 22 instead of 17). Name the mode.
- [ ] Energy (`getpde`/`setpde`, L51186-51229). Confirm full energy is `$1000` and map recovery to a fatigue curve.
- [ ] Rating scale. Player bytes `$67` wgt, `$68` agl, `$69` spd, `$72` endurance. Confirm raw ranges (spd caps at `$1E`) and the 0-100 mapping in `PlayerData`.
- [x] Rink size in px and the origin. See the Rink row above.
- [ ] One-shot animation lengths. `Skater2D.ONE_SHOT_FRAMES` (12) stands in until `SetSPA` / `updateanim` and the SPA tables are ported. It decides how long a stop or turn animation blocks the skate animation.
- [ ] Where stick value 9 (brake) comes from. `doplayeracc` handles it; the input side has not been read yet (`doinput` L35886).
- [ ] `sroot` (L44215) is Newton iteration. `RinkBoards.sroot` uses floor of the real root; check they agree on corner distances (64-100).

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

- [x] `PlayerData` resource (0-100 ratings, raw converters)
- [x] `TeamData` resource (roster, home/away colors, arena)
- [ ] Rating extraction: read `teamdata94.asm` (offline) and write `data/teams/*.tres`. 26 teams + 2 All-Star teams. Anaheim and Florida are new. Dallas, not Minnesota.
- [ ] Attribute math: `CalcAttrib` L966169, `AttributeCalc` L959917, `AttribWgtList` L966313, hot/cold `Create_HotCold_Table` L959871
- [ ] Line data: `SetPersonel` L51236, `SetPlList` L51300, `setplayer` L51556 (home/away bonus, 3rd period bonus)

## Phase 2. Skater movement

- [x] `SkaterMotion` (`playeracc`, `MaxSpeed`, drag, `stopna`)
- [x] Turning and momentum: `SkaterSteering` (`doplayeracc` L43331, `noturn0`, `vtoa`, backwards skating, hockey stop)
- [ ] Goalie skating: `goalieacc` L43477, `stopna2` L959753
- [ ] `burst` L36830, `holdplayer` L36863
- [ ] `skateto` L42953, `skatetopuck` L43138, `avdgoal` L43026
- [~] Wall collision: `RinkBoards` has the boards and corners (`checkwallcoll2`, `wallcoll`). Still to do: nets (`checkgoal` L49633), stick-end board check (`checkcoll` second call with the `GetHot` point), puck over the glass (`wallcollb2` L50092), `CheckBump` L50048
- [ ] Player-player collision: `checkcoll` L48484, `checkplcoll` L48570
- [ ] Energy and fatigue (`getpde`/`setpde`, endurance `$72`)
- [x] `scenes/skater.tscn`: `CharacterBody2D`, capsule, runs `SkaterMotion` + `SkaterSteering` + `RinkBoards` in retail loop order
- [x] `scenes/skate_sandbox.tscn` (main scene): two pad-controlled skaters, readout of retail values

## Phase 3. Puck

- [~] `PuckPhysics` carrier bungee (`pucknorm` L42526)
- [ ] Loose puck: drag `>> 9`, `puckIChk` L42796, `puckshadow` L42862, `puckflip`/`puckunflip`
- [ ] Puck vs boards and posts: `checkpuckcoll` L50247, `checkgoal` L49633, `checkgoalp` L50000, `deflect` L51170
- [ ] Stick pickup and steals: `puckstick` L50534, `CheckStkForContactWithSkater` L50566
- [ ] Puck vs body and goalie: `puckbody` L50765, `puckgoalie` L50818
- [ ] `Puck.tscn` with continuous bounce math

## Phase 4. Shooting and passing

- [ ] Shot input and charge: `SetShotMode` L37411, `ShotMode` L37444, `prepshot` L37473
- [ ] Shot power and aim: `doshot` L37514, `shotsets` L37697, `shotdiradj` L37721, `shotdirmath` L37806
- [ ] Passing: `setpassmode` L36893, `passmode` L36913, `dopass` L36924, `passto` L37074, `passtoa0` L37114
- [ ] One-timers: `assonetimer` L959091, `onetimershot` L959386
- [ ] Pass reception window (`pfdoff` drag, `asspassrec` L40938)

## Phase 5. Checking and fighting

- [ ] `checkcx` L48617, `newcheck` L48758, `checkint` L48778, `CheckingCalc` L48909
- [ ] `checkagr` L48971, `holdcheck` L49037, `Bcheck` L49103
- [ ] `FallDown` L49156, `FallList` L49396, injuries `setInjuryType` L49497
- [ ] `checkfight` L49544, `fightinput` L36560

## Phase 6. AI

- [ ] Assignment dispatch `asstab` L56671, `assinsert`/`assreplace`/`assexit` L43192-43210
- [ ] Offense: `assdefo` L38375, `asswingo` L38682, `asscentero` L38856, `asspuckc` L39901, `chk4shot` L40183, `chk4pass` L40337, `EvadePC` L40442
- [ ] Defense: `assdefd` L38447, `asswingd` L38591, `asscenterd` L38800, `check4check` L40878, `assnearest` L40574
- [ ] Faceoffs: `assfaceoff` L38206, `puckfaceoff` L41627, `puckfaceoff2` L42031, `updatefaceoff` L42414
- [ ] Breakaway, shootout and penalty shot: `breakaway` L39775, `puckshootout` L41046, `puckpenshot` L41276
- [ ] 9x5 tactical grid and slot bits (`setSlotBit` L963062)
- [ ] `HockeyAI` RefCounted with per-module toggle

## Phase 7. Goalie

- [ ] `goalieacc` L43477, `assgoaliecpu` L39072, `assgoaliectrl` L38963
- [ ] `goaliesave` L39598, `assgoalietopuck` L39731, `chkgoalie` L37366
- [ ] Pull goalie: `ReadGoaliePulled` L975229, `ChkGoalies` L41839
- [ ] Reaction latency exposed in frames and ms

## Phase 8. Rules and game flow

- [ ] Clock and periods: `ResetClock` L29817, `ClockLength` L29839, `StartPer` L29853, `clockcont`, `PeriodOver` L53805, `GameOver` L53851
- [ ] Offsides and icing: `ChkOffsides` L42598, `a2offsides` L42687, `a2touchpuck` L42716
- [ ] Penalties: `AddPenalty` L45939, `PenaltyManager` L46005, `PenaltyList` L56708, power play `updatepwrplay` L46991
- [ ] Line changes: `changeplayer` L37216, `SetLCmode` L36566, `lineinput` L36756, `assbench` L37886
- [ ] Crowd excitement: `UpdateCwdExcite` L30009, `updatecrowdf` L30028
- [ ] Stats: `ChkShotStat` L47451, `AddChktoPlayerStats` L49211, `InitScores` L47726

## Phase 9. Scenes and presentation

- [~] Rink: `Rink2D` draws a placeholder from the listing constants and builds static board colliders. The `TileMapLayer` waits on the tile PNGs.
- [~] `Camera2D` with smoothing, limits and lead: `RinkCamera` with tuning defaults. Retail scroll (`updatescroll` L51912) not ported.
- [ ] Sprite sheets from `Spritetiles` L337811 / `frameSprData` L602163 exported offline to PNG
- [ ] Team palette swap `.gdshader` (`SetTeamColors` L53781)
- [ ] Animation tables: `SetSPA` L43319, `updateanim` L35703
- [ ] Audio: sfx ids from `ram94.asm` comments, buses wired

## Phase 10. Editor tooling

- [x] `nhl94_debug` `EditorPlugin` and `Nhl94DebugDock.tscn`
- [x] Dock sliders and module toggles bound to `SimSettings`
- [ ] `@tool` `_draw()` overlays: goalie cones, pass lines, interception radii, 9x5 grid
- [ ] Live editing while the game runs (remote `SimSettings` sync)

## Phase 11. UI

- [ ] Setup screen: Team 1 / Team 2 `OptionButton`, line `ItemList`, reads `TeamData`
- [ ] HUD: clock, score, period, power play
- [ ] Pause menu

## Log

- 2026-10-11: Tracker written. Godot scaffold, data resources, `SkaterMotion`, `PuckPhysics` carrier follow, debug dock. 55 headless checks pass on Godot 4.4.1, including all 16 `MaxSpeed` entries against the ROM table.
- 2026-10-11: Phase 2 turning. `$34` resolved (0 = goalie), which moves the extra agility and carrier cuts to goalies only. `SkaterSteering` (facing, turning, hockey stop, backwards skating), `RinkBoards` (boards, corners, bounce), rink constants, input map, skater scene and sandbox. 130 checks pass. Sandbox checked in screenshots under Xvfb.
- 2026-10-11: World refactor. `HockeyWorld` owns the 16 retail objects and globals and steps `updateplayers`; `SimObject` mirrors the struct; nodes are views (`HockeyGame`, `Skater2D`). Retail RNG ported. Z gravity fact corrected. Research specs for every remaining subsystem are being written to `docs/specs/`.
