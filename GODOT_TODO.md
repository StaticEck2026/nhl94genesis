# NHL 94 Godot 4 rebuild: progress tracker

This file tracks the Godot 4 native rebuild in `godot/`. It is separate from the bitwise segment pass in `SEGMENT_AGENT.md`, which it does not touch.

Rules for this track:

- No emulation. No 68000, VDP, Z80, YM2612 or PSG. No ROM or RAM dump read at runtime.
- `lst/nhl94.bin.lst` is the behavior reference. Each translated routine cites its listing label and line.
- Fixed point becomes floats in px, px/s and radians. The conversion lives in `godot/core/nhl94_units.gd`.
- Every balance number is an exported, documented property. Defaults keep the retail value.
- Assets are loose `.png`, `.wav` and `.ogg`. `extractAssets94.js` may be used offline to produce them. The game never reads `nhl94.bin`.

Run the tests from `godot/` with Godot 4.4 or later:

```text
godot --headless --path . --script res://tests/run_tests.gd
```

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
| Skate accel | `200 * ((64 - wgt/4 + agl [+2 boost] [+agl+16]) / 2) / 32 * d7`, halved for a joypad puck carrier | `SkaterMotion.accel_per_frame()` | `playeracc` L43705 |
| Max speed | `MaxSpeed[i] = ((i + 20) * 275)^2` compared to `vx^2 + vy^2`. `i = spd/2` scaled by energy `/ $1000`. Odd `spd` takes half a step. | `SkaterMotion.max_speed()` | `MaxSpeed` L43855 |
| Max speed cuts | puck carrier: squared max `/2`. Fight injury: squared max `/8`. | `max / sqrt(2)`, `max / sqrt(8)` | `playeracc` L43809-43826 |
| Stop, no anim | `vel -= 150` (`$96`) toward 0 per call | `stop_decel` | `stopna` L43908 |
| Stop with anim | stop anim when `|vel| > $1000` on either axis, glide anim when skating backwards | FSM `STOPPING` | `dostop` L43876 |
| Puck stick bungee | puck moves 1/4 of the gap to the carrier hot spot per loop, copies carrier velocity | `PuckPhysics.follow_carrier()` | `pucknorm` L42526 |
| Z gravity | `Zvel -= 6 * 17 * d7`, `Zpos += Zvel * 17 * d7 / 4` | `gravity` property | `updateplayers` L35531-35545 |

## Open questions

- [ ] `$34(a3)` meaning. `playeracc` adds `agl + 16` when it is 0 and a comment says "goalie". The `_puckc` comment says the opposite. Check against NHLPA93 `playeracc` before trusting `SkaterMotion` goalie handling.
- [ ] Drag runs once per loop, not per vblank. Measure the usual `d7` in a game (1 or 2) so per-second drag matches retail feel.
- [ ] `word_FFD06E` (step 22 instead of 17). Name the mode.
- [ ] Energy (`getpde`/`setpde`, L51186-51229). Confirm full energy is `$1000` and map recovery to a fatigue curve.
- [ ] Rating scale. Player bytes `$67` wgt, `$68` agl, `$69` spd, `$72` endurance. Confirm raw ranges (spd caps at `$1E`) and the 0-100 mapping in `PlayerData`.
- [ ] Rink size in px and the origin. Read `setupice` L53024 and the wall tables used by `checkwallcoll` L959783.

## Phase 0. Project scaffold

- [x] `godot/project.godot`: 320x224, stretch `viewport`, aspect `keep`, nearest filter, 2D pixel snap
- [x] Audio buses `Master`, `Sfx`, `Crowd`, `Announcer`, `Music` in `default_bus_layout.tres`
- [x] Folder layout: `core/`, `data/`, `logic/`, `nodes/`, `scenes/`, `ui/`, `assets/`, `addons/`, `tests/`
- [x] `Nhl94Units` fixed-point conversion helpers
- [x] `SimSettings` resource: tuning values and module toggles shared by the game and the dock
- [x] Headless test runner `tests/run_tests.gd`
- [ ] Input map (2 pads, 3 buttons + start, keyboard defaults)

## Phase 1. Data layer

- [x] `PlayerData` resource (0-100 ratings, raw converters)
- [x] `TeamData` resource (roster, home/away colors, arena)
- [ ] Rating extraction: read `teamdata94.asm` (offline) and write `data/teams/*.tres`. 26 teams + 2 All-Star teams. Anaheim and Florida are new. Dallas, not Minnesota.
- [ ] Attribute math: `CalcAttrib` L966169, `AttributeCalc` L959917, `AttribWgtList` L966313, hot/cold `Create_HotCold_Table` L959871
- [ ] Line data: `SetPersonel` L51236, `SetPlList` L51300, `setplayer` L51556 (home/away bonus, 3rd period bonus)

## Phase 2. Skater movement

- [x] `SkaterMotion` (`playeracc`, `MaxSpeed`, drag, `stopna`)
- [ ] Turning and momentum: `doplayeracc` L43331 (reverse/backwards skating `_inrev`/`_rev`)
- [ ] `burst` L36830, `holdplayer` L36863
- [ ] `skateto` L42953, `skatetopuck` L43138, `avdgoal` L43026
- [ ] Wall collision: `checkwallcoll` L959783, `wallcoll` L50143, `wallcollb2` L50092, `CheckBump` L50048
- [ ] Player-player collision: `checkcoll` L48484, `checkplcoll` L48570
- [ ] Energy and fatigue (`getpde`/`setpde`, endurance `$72`)
- [ ] `Skater.tscn`: `CharacterBody2D`, capsule, reads `SkaterMotion`

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

- [ ] `Rink.tscn`: `TileMapLayer` ice and boards, static colliders for boards and posts
- [ ] `Camera2D` with smoothing, limits and puck lead (`updatescroll` L51912)
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
