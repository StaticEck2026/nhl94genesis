# Audit: retail '94 sprite animation vs. the Godot port

Scope: every `SetSPA` site and every direct write to the SPA fields in `lst/nhl94.bin.lst`, `updateanim`, the drawing path (`setvideo` → `addframe`/`find3d`/`addframe2`), and every per-frame sprite animation that runs outside `updateanim`. Port files: `godot/logic/*.gd`, `godot/nodes/*.gd`, `godot/ui/*.gd`, `godot/data/spalist*.json`, `tools/extract/*.py`. Retail lines are `Lnnnnn`. Port lines are `file:line`. The fight patch and replays (`SetRCords`, `revframetbl`, `updatereplay`, replay cursor `$189`) are out of scope. They are listed only where they touch the same code.

Verdict: the SPA engine (`SetSPA`, `updateanim`, SPAList data) and all 46 retail `SetSPA` call sites are ported faithfully. Almost all the gaps are sprites that retail draws outside the 16 sort objects:
- pad markers
- off-screen arrows
- crowd
- penalty-box occupants
- arena "background" animations
- zamboni

There is also the sprite priority bit, which the port ignores. A few small logic deviations are listed in §4.

---

## 1. SetSPA call sites (retail → port)

`+aip` = sets `$63` bit 1 (pf2aip). `+lock` = sets `$62` bit 5 (pfalock). "if !aip" = `SetSPA` is skipped while pf2aip is set. ✓ = same id, same condition, same flags.

| # | Retail line | Routine | SPA id(s) | Condition / flags | Port | Status |
|---|---|---|---|---|---|---|
| 1 | L36164 | doinput (pad goalie) | `$2F4` | A pressed with a direction; facedir = stick, nopuck 8, +aip +lock, crowd +$96 | input_logic.gd:146 `_manual_goalie` | ✓ |
| 2 | L36552 | faceoffinput | `$FEA` | faceoff centre, !aip, B pressed; +aip | input_logic.gd:241 | ✓ |
| 3 | L36557 | faceoffinput | `$1014` | faceoff centre, !aip, no B | input_logic.gd:244 | ✓ |
| 4 | L36854 | burst | `$C5E` | pad C without puck, CPU charge (L40926); +lock | shooting.gd:88 | ✓ |
| 5 | L36867 | holdplayer | `$1122` | pad A without puck, impact 0; +lock | checking.gd:255 | ✓ |
| 6 | L36888 | Acheck | `$1122` / `$C90` | `$C90` when the target is not behind (Y diff ≥ 0 toward own goal); +lock. Callers: holdplayer, check4check L40923/40927 | checking.gd:269 | ✓ |
| 7 | L37057 | dopass | `$366` goalie / `$718` / `$78A` | Findhittype picks backhand; +lock | shooting.gd:157 | ✓ |
| 8 | L37300 | Sweepcheck | `$B24` | +lock. Callers: chgplayer L976735 (nearest is already him), skatetopuck L43183 (puck 30–38 px ahead) | input_logic.gd:282 (from :275, hockey_ai.gd:253) | ✓ |
| 9 | L37439 | SetShotMode | `$7FC` / `$92E` | Findhittype vs the goal at ±$128; no lock (doshot sets it) | shooting.gd:310 | ✓ |
| 10 | L37929 | assbench | `$50C`, goalie `$2` | at the bench gate | line_logic.gd:346 | ✓ |
| 11 | L37946 | assbench | `$FAC` | facing 4 at the boards: facing := 2, +lock, temp1 $64 | line_logic.gd:359 | ✓ |
| 12 | L38012 | assben | `$F6E` | new assignment: pos (-$88, 14·n), facing 2, +lock. L38019 `clr.w $58` on the next call | line_logic.gd:397, :402 | ✓ |
| 13 | L38073 | asspenalty | `$50C` | at the box (timer) | line_logic.gd:436 | ✓ |
| 14 | L38094 | asspenalty | `$F6E` | facing reached (6, or 2 if `$76`≠0): +lock, then assdopen | line_logic.gd:448 | ✓ |
| 15 | L38157 | assepen | `$FAC` | new: pos ($86, ±60), facing 2, +lock, SprSort | line_logic.gd:474 | ✓ |
| 16 | L38255 | assfaceoffpl | `$FEA` / `$1014` | CPU centre, test-and-set aip; `$1014` if puck temp1 > $10 and randomd0(8) ≠ 0 | faceoff_logic.gd:400 | ✓ |
| 17 | L38299 | assstanley | `$109E` | new assignment | hockey_ai.gd:710 | **code ported, never reached** (G9) |
| 18 | L38358 | assscore | `$E8A` / `$EFC` | timer expired; `$EFC` for shotplayer; +lock | hockey_ai.gd:699 | ✓ |
| 19 | L39113 | assgoaliecpu | `$1596` / `$1684` (pfgoal) | goal scored, !aip, same half, \|x\| ≤ 20; +aip | goalie_logic.gd:86 | ✓ |
| 20 | L39170 | assgoaliecpu | `$2` | in the crease box, !aip | goalie_logic.gd:115 | ✓ |
| 21 | L39313 | assgoaliecpu | `$2F4` | rebound dive (temp4 = 0, loose slow puck within 20×30); +aip only | goalie_logic.gd:202 | ✓ |
| 22 | L39707 | goaliesave | `_saveanim[i]` (`$146 $178 $250 $2A2 $1EC $21E $148E $14C0 $14F2 $1544`), `$1AA` | `$1AA` replaces `$178` when rel&3 ≠ 0 and glove ≥ 11. Pad stack moves 6 px | goalie_logic.gd:375 | ✓ |
| 23 | L41442 | puckpenshot | `$50C` | PS/shootout goalie placement | shootout_logic.gd:301 | ✓ |
| 24 | L42196 | puckfaceoff2 | `$50C` | every on-ice object, goalies included (clears pfalock, pf2unav) | faceoff_logic.gd:291 | ✓ |
| 25 | L42856 | puckflip | `$46A` (loop) | facedir = (facedir ^ d0&1) & 3, st SPAcnt. Callers L49740, L50173, L50791, L50908, L51181, L958952 | puck_logic.gd:268 (callers :494 :548 :556 :634, hockey_world.gd:916, shooting.gd:297) | ✓ |
| 26 | L43350 | doplayeracc | `$50C` / `$A60` | stick > 7 and not (9 while moving); if !aip | skater_steering.gd:78 | ✓ |
| 27 | L43461 | doplayeracc | `$694`/`$662` (+aip) or `$50C`/`$A60` | turning: turn anim when speed²>>16 > $14 (XOR $FFCE for left and for x-flip). No aip check | skater_steering.gd:101 | ✓ |
| 28 | L43539 | goalieacc | `$2` | pad goalie in his crease, if !aip | goalie_logic.gd:452 | ✓ |
| 29 | L43622 | goalieacc `_cgl` | `$2` | idle, if !aip | goalie_logic.gd:476 | ✓ |
| 30 | L43639 | goalieacc `_d11` | `$3D8` | turn 1 step + skate. No aip check | goalie_logic.gd:485 | ✓ |
| 31 | L43672/43674 | noturn0 | `$50C` / `$A60` | stick opposite, not a stop: snap facing ±1 | skater_steering.gd:129 | ✓ |
| 32 | L43693 | noturn0 | `$A92` / `$5D0` / `$11E6` / `$53E` | rev → `$A92`; else `$5D0`, `$11E6` if `$63` b6, `$53E` if carrier; if !aip | skater_steering.gd:121 | ✓ |
| 33 | L43900 | dostop | `$6C6` (+aip) / `$50C` (pfrev) | only when \|Xvel\| or \|Yvel\| > $1000 | skater_steering.gd:143, :146 | ✓ |
| 34 | L48899 | CCStart | `checkinglist[rel]` (`$B96 $BC8 $C2C×3 $BFA×2 $B96`) | burst hitter; rel mirrored when x-flipped; +lock | checking.gd:152 | ✓ |
| 35 | L49072 | holdcheck | `$CF4` | held player; +lock | checking.gd:225 | ✓ |
| 36 | L49080 | holdcheck | `$CC2` (was `$C90`) / `$1154` | holder; +lock | checking.gd:227 | ✓ |
| 37 | L49312 | FallDown `_chkawayfrommiddle` | `$1AC2` | board check, hitter SCnum ≤ 11: temp1.b 0, glitch 0, vel 0 | checking.gd:341 | ✓ |
| 38 | L49430 | FallDown `_2` | faller: `$11E6 $DD8 $D26 $136A $1776 $17E8 $185A $18CC $193E $1A00` | FallList / big-hit / board variants; +lock | checking.gd:379 | ✓ |
| 39 | L49462 | FallDown `_21` | `$145C` | injury roll on a `$DD8` carrier facing &3 = 0 | checking.gd:392 | ✓ |
| 40 | L49469 | FallDown `_21` | `$1AF4` | not a game injury | checking.gd:395 | ✓ |
| 41 | L49956 | checkgoal | `$102E` on the shadow (`a3+$80`) | goal | puck_logic.gd:728 | ✓, plus an extra write (G10) |
| 42 | L50112 | wallcollb2 | `$1078` on the shadow | puck at the top glass, x 13–15, Yvel ≥ $FA0, Z in $13..$1D | puck_logic.gd:800 | ✓ |
| 43 | L50808 | puckbody | `$10D0` | puck Z > 8, slow; bset pfalock test-and-set | puck_logic.gd:504 | ✓ |
| 44 | L53679 | resetplstuff | `$50C` | on-ice objects (pflags2 cleared for all six) | faceoff_logic.gd:303 | ✓ |
| 45 | L959149 | assonetimer | `$7FC` / `$92E` (setonetimeranim) | clr SPAnum, +lock +aip | shooting.gd:588 | ✓ |
| 46 | L975253 | sub_FEFF0 | `$50C` | end of a one-timer (also from setass L49965) | shooting.gd:678. setass path: hockey_world.gd:1061 | ✓ / partial (G11) |

### Direct writes to SPA, SPAnum, SPAcnt, glitch, frame and attribute

| Retail | What | Port | Status |
|---|---|---|---|
| L35748 | updateanim clears SPA at the end of a one-shot | animator.gd:65 | ✓ |
| L38019 | assben `clr.w $58` | line_logic.gd:402 | ✓ |
| L41321-41323, L42099-42101 | shadow: frame `$18A`, SPA 0, attribute 0 (PS / faceoff) | shootout_logic.gd:255-259, faceoff_logic.gd:207-210 | ✓ |
| L51577 | setplayer (tmpdst ≥ 0 or bench): clr pfalock, clr SPA | roster_logic.gd:96 | ✓ |
| L37446-37465 | ShotMode SPAnum tests, `SPAnum = $1C - SPAnum` | shooting.gd:314-325 | ✓ |
| L42833-42842, L42854 | puckunflip (facedir ^2 / \|4, SPAnum 0, st SPAcnt), puckflip st SPAcnt | puck_logic.gd:257-267 | ✓ |
| L50622-50660 | puckstick: one-timer SPAnum := $18 | puck_logic.gd:425-429 | ✓ |
| L959148-959294 | assonetimer SPAnum/SPAcnt timing (`$18 - n`, `+$30`, `:= 1`) | shooting.gd:587-629 | ✓, except G12 |
| L975262 | sub_FEFF0 tail: clr SPAnum, st SPAcnt | shooting.gd:683-684 | ✓ |
| L38235 | assfaceoffpl reads SPAnum into the close-up frame (+3 if `$76` = 0) | faceoff_logic.gd:388-391 | ✓ |
| L36186-36199 | doinput pad goalie holding C: `$5C := $A` if `tst.b $5B` < 0 | not ported | dead in retail (SPAnum < $80 always): no effect |
| L49310 | `clr.b $65` (board hitter) | checking.gd:340 | ✓ |
| L37954, L38129, L41349, L42123, L50126 | frame := 0 (bench done, assdopen, PS, faceoff line-up, shadow hidden over the glass) | line_logic.gd:369, :458, shootout_logic.gd:305, faceoff_logic.gd:257, puck_logic.gd:808 | ✓ |
| L42884, L50124 | attribute `$8000` (siren at bottom end; puck over bottom glass) | puck_logic.gd:282, :807 | ✓ set, **ignored when drawn** (G3) |
| L51693-51699 | setplayer x-flip from handedness | roster_logic.gd:147-149 | ✓ |

## 2. SPAList coverage

- `spalist.json` holds all 66 retail ids (`$2`..`$1AF4`). Every SPA id that retail code uses is in it. That covers the immediates, `checkinglist`, `FallList`, `_saveanim` and `setonetimeranim`. Nothing is missing from the export.
- Port setters reach 64 of the 66. The two that are never set, `$114` and `$1298`, have no setter in retail either: no immediate, no table entry, and no computed id. They are dead data.
- `$109E` (cup skate) is set by ported code, but no path ever assigns `assstanley` (G9).
- `$11E6` is reachable both through the stagger in FallDown and through doplayeracc. The doplayeracc route needs `$63` bit 6, which only the fight patch sets.
- `$F6E` and `$FAC` dir 7: the exporter follows the out-of-entry offset `$3E` exactly as retail does. It reads 23 and 16 junk pairs, ending at a negative time. The junk list contains frames 0, -8 and -6. Retail hides these (`addframe2`: `f <= 0`). The port's `draw_frame` finds no atlas key, so it also draws nothing. Whether facing 7 ever happens during a hop is UNRESOLVED (spec §1).
- Every frame used by SPAList (1..837) is in `assets/sprites/frames.json` (845 frames). The fight-patch frames are in `fight.json`.

## 3. updateanim (L35703) vs animator.gd

Line by line, the port matches retail on all of the following:
- the SPA = 0 early exit, which clears pfalock and pf2aip only
- the attribute-word loop bit
- horizontal mode `dir-2` for SCnum < 12
- the x-flip mirror `(8-dir)&7`
- d2 read before the advance (one-loop lag)
- `SPAcnt < 0` → LOAD
- `sub d7` with `bpl` (0 still runs)
- the end test on the time of the frame that just finished
- the end-of-list clears of `$62` b5, `$63` b1 and `$64` b5, including for loops
- a one-shot clears SPA
- LOAD = |time|
- the CFRAME de-glitch: byte `-d7`, `bpl` holds, then 0, compare, frame, 4

Deviations:
- D1. Unknown SPA id: the port treats it as SPA 0 (animator.gd:41). Retail would read garbage. Only reachable with ids outside both JSON files.
- D2. Index clamp: `idx = min(SPAnum>>2, len-1)` (animator.gd:47). Retail reads past the list. No retail writer puts SPAnum past a list (the `$18`/`$1C` writes only hit the 9-frame shot lists), so this has no effect.
- D3. Facing 8: `vtoa` of a zero vector is stored as facedir 8 by the rebound dive (L39310) and by goalie_logic `_set_facing`. The port masks it with `facing() & 7` (animator.gd:33) and plays dir 0. Retail uses word +$10, the attribute word (0), as the list offset, so it plays the entry header as {frame,time} pairs. This is a rare edge case and is UNRESOLVED whether it can be seen.
- D4. SPAcnt and glitch are GDScript ints. SPAcnt is not wrapped to 16 bits, and glitch is masked. The only external add is `+$30`, so it never overflows.
- D5. `SimObject.spa` defaults to `$50C` for skaters (sim_object.gd:80, hockey_world.gd:497). Retail's struct clear gives 0. Facing is 0 after the clear, so both show frame 1, and nothing visible differs.
- D6. d7 is fixed by `SimSettings.loop_vblanks` (default 1). In retail it varies with CPU load. All times are in vblanks in both, so only the granularity differs.

## 4. Gaps, prioritised

### P1: visible features missing

**G1. Controlled-player markers (setffo L52646 / uppads L52666 / sub_C656 L37819).**
- Retail: seven "ffo" objects (`_listffo` L53375):
  - the puck-possession star `$188`, which follows the carrier (updateplayers `_done` → sub_C656 d4 = -2)
  - pad stars `$186` and `$187` (setc1player/setc2player → sub_C656)
  - `$34C` and `$34D` for pads 3/4
  - the replay cursor `$189`
  - the gloves slot
- Each pad star follows its player. sub_166E6 DMAs three font glyphs from `unk_AAC52` into the star's first tiles: jersey tens and units, and the position letter from `" DDLCRX"` (blank when `byte_FFC2FC` b7 is set). setffo shifts the first two pieces by the `2(a3)` x tweak.
- Port: there is no marker state (`word_FFBE78`/`word_FFBE86`) and no view. Nothing on screen shows which skater a pad controls.
- Where it belongs:
  - marker nibbles in `HockeyWorld`, set in `set_c_player` (hockey_world.gd:1016) and in `update_players` for the carrier
  - a view node drawn behind the sort objects (setvideo draws ffo after `setsortcords`)
  - frames from the main atlas, and digits from the font that `tools/extract/title.py` already decodes (`FONT = $AAC52`)

**G2. Off-screen pointer arrows (checksso L52455, sub_164D6).**
- When a pad player's position is more than $74 px (X) or $64 px (Y) from the camera, an arrow is drawn at the screen edge. Frames are `$180+jdtab[edges]` for pads 1/2 and `$346+…` for pads 3/4, with screen offsets from `unk_165BC`. Arrows are drawn in front of the players (before `setsortcords`).
- They are suppressed in horizontal mode. During shootout/PS/`sflags2` b3 they only show when \|x\| < $A6.
- Port: missing. Belongs next to G1 (UI or the sort-object views).

**G3. Sprite priority bit 15 ignored.**
- `addframe2` ORs attribute bits 15..11 into each sprite. Two in-game objects set `$8000`:
  - the puck flying over the **bottom** glass (wallcollb2 L50124)
  - the goal light at the bottom end (puckshadow `_siren` L42884, Y = -$12C, Z $D)
- On the VDP these draw over the near-end boards/glass priority cells (map rows 78-84).
- Port: `Skater2D` (skater.gd:47) and `SortObjectView` (sort_object_view.gd:26) clamp `z_index` to ±3000. `Rink2D.Z_FRONT` = 4000 (rink.gd:24). Both objects therefore end up **hidden behind** the near glass.
- Fix: when `attribute & $8000`, use an absolute `z_index` above `Z_FRONT`, keeping the Y order among priority sprites.

**G4. Injured players keep sliding.**
- updateplayers L35483-35486: an object with SPA `$145C` or `$1AF4` skips drag, velocity integration and Z (`beq _done`).
- Port: `_integrate` (hockey_world.gd:616) has no such test, so the injured player keeps moving under drag.
- Fix: add the SPA test in `update_players` (hockey_world.gd:573) before `_integrate`.

**G5. Crowd animation (updatecrowdf L30028 → showcrowd L52175, CrowdFrameList `$A4B54`).**
- Logic: game_rules.gd:760. Three deviations from retail:
  - It stores the **table index** `d0+step` in `crowd_frame`, not the byte from `_cd0` (L56543: 4 rows × 16 {frame, delay-mask}).
  - It never computes the second crowd frame. Retail clears `crowdframe` (high byte) on every call. When crowdlevel > $118 it sets that byte to a random $13..$19 (VDP counter & $7F in range).
  - The delay uses `hv_rng` with a mask derived per row. The masks match the table ($C / 7 / 7 / 3).
- Drawing:
  - missing: no export of CrowdFrameList ($76 tiles, 63 frames, pieces in map-pixel coordinates), no view
  - frames are culled to the camera window (sub_16246) and use attribute base `word_FFB01A`
  - horizontal mode adds `$1F` to the frame
  - retail also steps the crowd during the intermission (waitxsr L44358)
- Belongs: `tools/extract/assets.py` (new set) plus a view under `HockeyGame` drawn behind all sort objects.

**G6. Penalty-box occupants (showcrowd L52188-52195).**
- `PBnum` low nibble (away) draws crowd frames `$1A..$1A+n-1`; the high nibble (home) draws `$1D..$1D+n-1`, with n ≤ 3. The boxed player's own object is hidden (assdopen `clr.w 6(a3)`).
- Port: `pbnum` is tracked (line_logic.gd:456) but nothing draws the seated players, so the box looks empty. Needs the same asset as G5.

**G7. Arena / background animations (sub_FE510 L973950, sub_FE2C8 L973464 from periodiceevents and waitxsr, sub_FD78A L970856 from setvideo).**
- Table `$FE364`, 8 ids. Each id is a byte script of {frame, vblanks} (`$FF` loop, `$FE` end → sub_FE548) and a frame file (tiles at +8, loaded to `word_FFD6AC`):
  - id 0 → `$EA2EC`
  - ids 1/2 → `$EAB10`
  - id 3 → `$EB816`
  - ids 4/5 → `$EC284`
  - ids 6/7 → `$ED1B0`
- Triggers:
  - id 0: a home player reaches 3 goals (L56031-56045, hat trick)
  - one id per faceoff from sub_FECAA (table `3,5,3,1,5,2,3,3`; 6 when fox ≤ -64 and foy ≤ 192), started at puckfaceoff2 L42209-42214
  - id 7: a check over the boards at the benches (FallDown L49352)
- Pieces are in map-pixel coordinates (id 6/7 around map x 25-49, y 376-448 = the bench). Drawing is suppressed in reverse-angle replay, in horizontal mode and when `sflags2` b3 is set.
- Port: the ids are kept only for the faceoff drop minimum (faceoff_logic.gd:85-90, :225-232). `background_anim(7)` is emitted (checking.gd:355) but nothing receives it. The script stepping, the export and the view are all missing. The meaning of ids 1-6 (which arena scene each shows) is UNRESOLVED; it needs a render.

**G8. Zamboni during the intermission (Intermission L47613-47679, showzam L52076, ZamFrameList `$A8922`, tiles `$A892A`).**
- zamx starts at $140 and goes +1 per vblank up to $708 (waitxsr L44358).
- Frame 1 (body) is drawn at x = zamx>>2, y $12A. Frames 2-4 cycle by ((zamx>>2)>>1) mod 3. Frame 5 is drawn static when home ≤ away; otherwise frames 5-8 play from `unk_1615E` by zamx. Attribute base is `ExtraChars`.
- Port: the intermission only holds the sim (scenes/game.gd:69). The zamboni and the crowd stepping during that time are both missing.

**G9. Stanley Cup celebration.**
- clockcont L30090-30113: in the finals (gamelevel 3) when this win clinches (bosgames 7 or 3 prior wins), `pfjoycon` is cleared on all 12 objects.
- The first on-ice player of the winning team gets assignment 8 (assstanley, `$109E`). The rest get assscore.
- Port: `end_of_period` (game_rules.gd:639) only inserts ASS_SCORE, so `$109E` is unreachable.

### P2: small deviations

- **G10.** checkgoal: the port also writes `SHADOW.frame = 1` (puck_logic.gd:729); retail does not (L49944-49962). If the shadow's glitch counter is still > 0 from an earlier siren loop, frame 1 (a skater glide sprite) is drawn at the goal-light spot for up to 4 loops. Retail keeps `$18A`, so the shadow keeps following the puck until `updateanim` changes the frame. Remove the line.
- **G11.** setass → `cancel_onetimer` (hockey_world.gd:1057) is a partial sub_FEFF0. It does not clear `onetimer_state` or `onetimerplayer`, does not Setplass/assexit, and does not restart SPAnum/SPAcnt. Call `shooting.end_onetimer` instead.
- **G12.** assonetimer time-to-puck divisor is `$16` when `word_FFD06E` (alt velocity step) is set (L959230-959233). The port always uses 17 (shooting.gd:613).
- **G13.** puckshadow in horizontal mode adds 1 to **X**, not Y (L42869-42873). The port always uses Y (puck_logic.gd:274).
- **G14.** GetHot horizontal-mode swap (`exg d0,d1; neg d1`, L43305-43308) is missing from `get_hot` (hockey_world.gd:933).
- **G15.** Faceoff close-up palette: checkfo XORs attribute bits 13-14 into each piece (L52056-52061), so `$A800` maps lines 0↔1 and 2↔3. FaceoffWindow (ui/faceoff_window.gd:36-37) only swaps 2→3. Whether the close-up art has line-0/1 pieces is UNRESOLVED.
- **G16.** In-game clock: retail draws 5 window-plane tiles from font `$AAC52` (showclock `loc_163BE` L52387-52437) at tile row 24, col 3 (row 5, col 13 in horizontal mode), with high priority. The port shows a Label scoreboard (ui/hud.gd:157). This is an approximation, not tile art.
- **G17.** The away palette comes from `PF_TEAM` (`obj.away()`, skater.gd:45) and is cached on the first sync. Retail uses attribute bit 0 on every draw. The two agree in a match, but can differ in the sandbox (`place()` sets the team only).

## 5. Drawing checks (skater.gd, sort_object_view.gd, sprite_atlas.gd vs addframe/find3d/addframe2)

| Item | Retail | Port | Status |
|---|---|---|---|
| Flips | per piece `x = -8w - p.x`, `y = -8h - p.y`, flags = piece ^ attribute (bits 15-11), frame-word flag bits XOR into the attribute | whole frame mirrored about the origin (px → -px-1), `attr ^ (f & $F800)` (sprite_atlas.gd:56-68) | ✓ equivalent |
| Away palette | attribute b0 and piece line 2/3 → line 3 | shader line 2 → 3 when `away` (shaders/palette.gdshader) | ✓ (source of `away` in G17) |
| Priority b15 | sprite drawn over priority plane cells | ignored; RinkFront always on top | **G3** |
| Height | `dy += z + (z asr 1)`, z = Zpos high word | `lift = z + z>>1`, z ≥ 0 (sort_object_view.gd:42) | ✓ |
| Horizontal mode | `(dx,dy) = (-y, x-$C5)`, no scroll | `project_ground` + camera at 0 (rink_camera.gd:45) | ✓ |
| Shadow | separate object `$18A` at puck (x, y+1), Z 0 | SortObjectView 15 | ✓ (G13 in horizontal mode) |
| Sort order | OOlist by Ypos (Xpos in horizontal mode) ascending; first = in front; stable; updated by checkcoll / SprSort | `z_index` = screen Y each frame | ✓ order. Ties differ: retail keeps the previous order, the port uses tree order (skaters, nets, shadow, puck). Low |
| Hidden: Z < 0 | `addframe` skips Zpos.hi < 0 | SortObjectView ✓. Skater2D does not test Z (skater.gd:41) | low (no retail skater gets a negative Z) |
| Hidden: frame | `addframe2` skips frame ≤ 0 (signed) and ≥ 847 | `frame != 0`. A missing atlas key draws nothing | ✓ in effect |
| Off-screen | find3d drops an origin more than $90 px from centre (sprite can be cut at the edges) | viewport culling only, 320-px wide view | design difference, low |
| VDP limits | 80 sprites, 20 per line; SetSframe/crowd capped at link 64 | none | not emulated, low |
| Draw layers (setvideo L51875) | checkfo, checksso, sort objects, ffo pads, zamboni, background anims, crowd/box | faceoff window (UI), sort objects, gloves | missing layers G1, G2, G5-G8 |

## 6. Per-frame animation outside updateanim

| Feature | Retail | Port logic | Port drawing |
|---|---|---|---|
| Skate / glide / back / puck / injured / turn / stop | doplayeracc L43331, noturn0 L43644, dostop L43876 | skater_steering.gd ✓ | Skater2D ✓ |
| Goalie stance, skate, saves, dive, goal-against | goalieacc L43477, assgoaliecpu, goaliesave | goalie_logic.gd ✓ | ✓ |
| Celebrations | assscore, assstanley | ✓, cup branch missing (G9) | ✓ |
| Falls, board pins, injuries | FallDown, updateplayers L35375-35452, sub_FEB54 | checking.gd ✓ (`pin_to_boards` :449). Injured slide (G4) | ✓ |
| Checks, holds, sweep, hit by puck | CCStart, holdcheck, Acheck, Sweepcheck, puckbody | ✓ | ✓ |
| Faceoff stance and close-up | assfaceoffpl, faceoffinput, checkfo, updatefaceoff | ✓ | FaceoffWindow ✓ (G15) |
| Bench / box hops, box sitting | assben/assbench/asspenalty/assepen; box drawn by showcrowd | hops ✓ | box occupants missing (G6) |
| Puck spin | `$46A` via puckflip/puckunflip | ✓ | ✓ |
| Puck shadow, goal light, glass shatter | puckshadow, `$102E`, `$1078` | ✓ (G10, G13). Port names `$1078` "goal light"; its frames `$28D-$291` are the glass shatter | ✓, but the bottom goal light and the puck over the bottom glass are hidden (G3) |
| Nets | no animation; CheckBump only moves the net | ✓ (`_check_bump`) | ✓ |
| Crowd | updatecrowdf / showcrowd | partial (G5) | missing |
| Arena / bench background animations | sub_FE510 / FE2C8 / FD78A | ids only | missing (G7) |
| Referee | no on-ice referee; window via showref; close-up ref in fofdata | ✓ | RefWindow, FaceoffWindow ✓ |
| Zamboni | Intermission / showzam | missing | missing (G8) |
| Clock | showclock (window tiles) | ✓ | approximation (G16) |
| Pad stars + numbers, off-screen arrows | setffo/uppads, checksso | missing | missing (G1, G2) |

## 7. Unresolved

1. Whether `$F6E`/`$FAC` ever run with direction 7 (junk list), and whether facedir 8 (D3) ever reaches `updateanim` visibly.
2. What each background animation id 1-6 shows (arena scenes); this needs a render of `$EAB10`, `$EB816`, `$EC284`, `$ED1B0`. Id 0 is inferred to be the hat-trick animation from its trigger.
3. Whether the face-off close-up art uses palette lines 0/1, which would make the full XOR in G15 matter.
4. The meaning of `word_FFBE78` nibble value `$E` in uppads (special marker case, L52697), and the exact `jdtab`/`unk_165BC` arrow offsets. Both are needed only when G1/G2 are implemented.
