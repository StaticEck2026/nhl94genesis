# NHL '94 (Genesis): pause menu, intermission, end of game and the stats pages

Source: `lst/nhl94.bin.lst` (IDA listing, no address column; lines are written `Lnnnnn`, the first instruction of a routine unless a label is named) and `lst/nhl94.bin` (CRC32 `$9438F5DD`). ROM addresses are written `$xxxxx`. The listing mis-decodes almost every inline string (`printz`, `printz2`, `sub_11DE2`, `appendz`, `sub_1172C` remap bytes) and most data tables in this area. Every string, table and remap below was read from the ROM bytes.

Exported data: `tools/extract/ui_menus.py` → `godot/assets/ui/menus/` (§17). It reuses the in-game overlay art of `tools/extract/ui_overlay.py` (`godot/assets/ui/`: the in-game font, the printbig font, the in-game Framer tiles and the team-name plates) and the print-engine description of `docs/specs/ui_ingame.md` §1. That spec covers the playoff ticker (§8.1) and "Stars of the Game" (§10); they are only summarised here.

**Verification.** Every screen below was checked against the real game. A small Genesis harness (unicorn 2.1.4 68000 core, a VDP with DMA and the three planes, pads, a stubbed Z80 handshake) booted the ROM in the session scratchpad, set up Los Angeles at Montreal (5-minute periods, penalties on), played a CPU-against-CPU game (`cont1team` cleared) to 10-6, and opened every pause row, every intermission menu and the shootout menus. The screenshots and plane dumps are in `/tmp/claude-0/-home-user/ef020377-92e3-57ff-8519-5d51b4a7df4d/scratchpad/ui/` (`pg_NN_*.png/.txt` one per pause row, `ex_NN_*.png` sub-screens, `im_*.png` intermissions, `so_*.png` shootout, `m_*.png` montages). The exported files were checked by rebuilding each page's static layer from them (`--preview`, `prev/*.png`): frames, titles, plates and labels land on the same cells as in the game.

---

## 0. Quick facts

- **Two screen modes.**
  - The pause menu, the intermission menu, Change Goalie and Timeout are drawn on the **window plane of the in-game H32 screen (32x28)**, over the sideways penalty-screen view (`SetHor`). They use the in-game font (remap `43 43 45 67…`: every glyph cell is opaque) and the in-game Framer.
  - Every **stats page switches the VDP to H40 (40x28, 320x224)**. A full-screen window holds the "SPORTS" background (`$54E24`), the framed big-font title and the team plates. The live text is on **plane B**, which scrolls vertically under it. Leaving a page (`$9CD8`) restores H32 and the in-game VRAM and redraws the pause menu.
- **One menu engine** (`sub_7E36`/`sub_7E46`/`sub_7EF2`/`sub_7E88`) serves the pause menu, the intermission menus and the Line Editor's exit menu. It shows a 22x6 box with 4 visible rows, a scrolling cursor, and up/down arrows. **Row 0 always closes the menu** ("Resume Game", "Start Game", "Exit Game", "Start Shootout", "Exit"), and so does **Start**. **C** runs the row's handler, a blocking routine that returns to the menu.
- The menu belongs to the pad that opened it (`sub_7E0E`, L30294): **home when that pad's `contNteam == 1`, otherwise away**. Timeout, Change Goalie, Edit Lines, Team Roster's first team and Player Stats' first team all use that team.
- The pause table `unk_19700` has 16 rows. The intermission tables add Playoff Stats and Shootout SetUp, and the Line Editor's exit menu has its own 4 rows (§3).
- **End of game:** the referee's "Game Over" window and the Stars of the Game box (ui_ingame §10), then `PeriodOver` (gsp 4) → `Intermission` with the "Exit Game" menu, the ticker and the highlights → `GameOver` → `PlayoffScreen` (playoffs only) → song `$78` → `Opening2` (setup menus). There is no separate final-score screen: the side view's scoreboard shows the final score behind the menu (`im_r_45999.png`).
- **Needs battery RAM (SRAM).** Player Cards (the whole page), Record Holders (all data), the Crowd Meter's two record rows and every records update (`sub_F9CDE`) need `ValidSRAM` (`$FFD458`) ≥ 0. With fresh SRAM, retail shows these pages with empty record lists. §16 gives what an exhibition-only port should show.

---

## 1. Flow

### 1.1 PauseMode (L30217, `$7CF8`)

Called from `GameLoop` (L29902) once `sflags` bit 0 is set. `doinput` (L35927-35940) sets it on a new Start press through `startpause1`/`startpause2` (L30187/L30193): pad 1 clears `sflags` bit 1, pad 2 sets it (`loc_7CDC`/`loc_7CEA` for pads 3/4 set `word_FFC316` = 3/4).

```
forceblack; wait a vblank; AllSndOff
push sflags
a2 = sub_7E0E()                                   ; the pausing pad's team (L30294)
a0 = unk_19700 ; a1 = sub_7DCE                    ; menu table, redraw callback
if word_FFC2FA bit 0 (shootout): a0 = unk_19664
elif $30(a2) bit 2 (timeout used): a0 = unk_1988C
sub_7E36(a0, a1)                                  ; set up and draw (falls into sub_7E46)
do {                                              ; L30245
    vcountwait; getpzjoy                          ; the pausing pad only (L34830)
    showclock; sub_11318                          ; auto-repeat (§2.4)
} while (sub_7E88() != 0)                         ; Z set = close
forceblack; pop sflags
if sflags bit 7 (sideways screen): sub_16CE0 (side-view tiles); SetHor  else ClrHor
VDP $9100/$9200 (window off); disflags bit 3; sflags bit 0 = 0
PrintScores1; setvideo; palcount = $18; wait for the fade
```

`sub_7DCE` (L30277), the redraw callback, runs on every menu draw:
- VDP `$9100/$921C`: window from row 0 down to row 28, i.e. the whole screen;
- `SetHor` (the side view on plane B), `setvideo`, `KillCrowd`;
- `printz2 $FF 3` (window), `printx/y = 0`, then `eraser(32, 28, $7FF)`: the window starts transparent.

So the pause screen is the side view (plane B, with the score board and clock printed by `showclock`) with a 22x6 box on the window.

### 1.2 Intermission (L47614, `$130E6`)

See arena_animations.md §5.1 for the zamboni and crowd. The menu part:

```
if gsp == 4: gameclock = 0; sub_F9CDE                         ; SRAM records update (§15)
sub_13056 (ResetBench, line resets); clear Xpos of the 16 objects; ZamFrameList tiles; zamx = $140
d0 = gsp + (OptPlayMode ? 5 : 0); a0 = unk_131CC[d0]           ; L47630-47637
if word_FFC2FA bit 0: a0 = unk_19A00                           ; shootout
sflags bit 0 = 1 ; sub_7E36(a0, sub_7DCE)                      ; same engine, same box
TickerNum = GetShifter()
while TickerNum >= 0:                                          ; other games (§11)
    NewTicker2; NewTicker3pt2; waitxsr($96); if chosen: break  ; 150 frames a game
    sub_134D8 (erase); waitxsr($3C); if chosen: break          ; 60 frames blank
    (break sets sflags3 bit 3)
sub_1351C                                                      ; highlights (§11.3)
if sflags3 bit 3 was set (bclr): done
repeat waitxsr($1E0) until chosen or (cont1team == 0 and cont2team == 0)
zamx = $FF..                                                   ; zamboni off
```

`waitxsr(n)` (L44354) loops `n` vblanks. Each vblank it:
- steps the zamboni, the crowd (`updatecrowdf`) and the arena animations;
- reads **pads 1, 2 (and 3, 4 in four-way play)** through `sub_11318`;
- on input from any pad, sets `sflags` bit 1 to that pad (that pad's team owns the menu) and calls `sub_7E88`;
- if `sub_7E88` returns Z ("chosen"), returns with d1 bit 7 set;
- on any input, also extends the wait to at least `$78` vblanks.

So with a human playing, the intermission lasts until row 0 (or Start) is chosen, in any phase: ticker, highlight or the final wait. With two CPU teams it ends after one `$1E0` wait. The port's `scenes/game.gd` already does the CPU case (`CPU_INTERMISSION_FRAMES`).

Shots: `t_g0.png` (pre-game "Start Game" + ticker), `im_r_11999.png` (after period 1), `im_r_45999.png` (final, "Exit Game"), `so_im.png` (shootout).

### 1.3 End of game

| Step | Where | What |
|---|---|---|
| final whistle | `UpdatePA` L46523, `RefPen == 4` | referee "Game Over" message; at `RefCnt <= $40`, `sub_1850A` (L55667) draws **Stars of the Game** on plane A (Framer 28x9 at (2,14), title at (9,16), three rows from y 18: player at x 3, team abbreviation at x $1A). Home win: song `$F`. Ported as `GameRules.stars_of_game()` + signal `stars`; layout in ui_ingame.md §10. |
| `PeriodOver` | L53807 | gsp 4; `UpdateScores`; `AddPOStats` |
| `Intermission` | L47614 | `sub_F9CDE` (records, SRAM); menu `unk_19D60` ("Exit Game"), or `unk_19E74` in playoffs; ticker; highlights |
| `GameOver` | L53852 | `sub_180FC` (playoff bookkeeping, returns unless 1 ≤ OptPlayMode ≤ 3); if OptPlayMode != 0: `sub_9428` (Playoff Stats page) |
| `PlayoffScreen` | L53890 | returns at once when OptPlayMode = 0 (L53890-53891) |
| `song($78)`, `Opening2` | L53868 | setup menus (the title is skipped) |

There is no three-stars page, final box score or "game over" page in retail beyond these. The final intermission (with Game Stats etc.) is the post-game summary.

---

## 2. The menu engine

### 2.1 State

| RAM | Name here | Meaning |
|---|---|---|
| `$FFCF20` | cursor | selected row (0-based) |
| `$FFCF22` | top | first visible row |
| `$FFCF24` | table | menu table pointer |
| `$FFCF28` | redraw | callback run before every full draw (`sub_7DCE` in play) |

### 2.2 Table format (`sub_7EF2` L30393)

```
string 0  : print2 string = the row attribute       ($0004 $FE $05 -> printa $A000: line 1, priority)
string 1  : print2 string = the cursor-row attribute ($0004 $FE $04 -> printa $8000: line 0, priority)
rows      : { print2 string ($0014 + 18 characters), long handler }
terminator: $0004 $FF00   (the loop stops when the word after a row's length word is negative)
```

A row whose first character is `x` (the goalie row) is not printed. `sub_8008` (L30477) prints `$8050` "  Manual Goalie   " when `word_FFD05A` (pad 1; `word_FFD05C` when `sflags` bit 1) is 0, else `$8064` "   Auto Goalie    ". **The row shows the current setting.**

The Line Editor exit tables use attribute strings with a font switch (`$FE $06 $F9 $01` / `$FE $04 $F9 $01`): rows in line 2, cursor in line 0, both in font 1 (§4.2).

### 2.3 Drawing (`sub_7E46` L30321, `sub_7EF2` L30393)

```
sub_7E36(table, redraw): store; cursor = top = 0; fall into sub_7E46
sub_7E46: redraw(); printz2 [$FE 4, $FC $C] (attr $8000, y 12); printx = sub_7E72()
          Framer(22, 6)                              ; box cols x..x+21, rows 12-17
          sub_7EF2(); palcount = $18 (fade in)
sub_7E72: printx = 5 on H32 (disflags bit 1), 9 on H40
sub_7EF2:
  cursor = clamp(cursor, 0, rows-1)
  if cursor < top: top = cursor ; if cursor - 3 > top: top = cursor - 3
  printx = sub_7E72(); printy = $D; print2(table string 0)     ; printa = $A000
  printz2 $7F56: blank columns x+1 and x+20 on rows 13-16 (the arrow cells)
  printy = $C; if top > 0: printz2 [$FE 5, dx 1, dy 1, '{', dy -1] ; up arrow at (x+1, 13)
  for up to 4 rows from top:
      printx = x; printz2 [dx 2, dy 1]                ; text at x+2, rows 13..16
      print2(string 0); if row == cursor: print2(string 1)
      sub_8008(row)                                    ; the 18 characters
  if rows remain below: printx = x; printz2 [$FE 5, dx 1, '}'] ; down arrow at (x+1, last row)
```

**Layout on H32** (`pz_menu.png`):
- Framer at window (5,12), 22x6 cells.
- Rows at x 7-24, y 13-16. The cursor row uses attribute `$8000` (line 0), the others `$A000` (line 1).
- `{` up arrow at (6,13), `}` down arrow at (6,16).

With the in-game font remap the glyph background is colour 4 and the ink colour 3. On the side-view palette:
- line 0 (cursor row): ink `$CCC`, background `$000` (bright on black);
- line 1 (other rows): ink `$444`, background `$222` (dim grey).

On H40 everything moves 4 columns right: box at (9,12), rows from x 11.

### 2.4 Input (`sub_7E88` L30347, `sub_11318` L44487)

```
sub_11318 (auto-repeat, d3 = held, d2 = changed): nothing held -> nothing;
   just pressed -> counter = $F; held: counter -= 1, and when it goes negative counter = 4 and
   d1 = d3 (a repeat): first repeat after 16 frames, then every 5
sub_7E88(d1 = new presses):
   Start (bit 7): return Z (close)
   down (bit 1): cursor += 1; sub_7EF2; return NZ
   up (bit 0):   cursor -= 1; sub_7EF2; return NZ
   C (bit 5): a2 = sub_7E0E(); jsr row.handler
              if bclr(word_FFC2F6 bit 1) was clear: sub_7E46   ; full redraw (callback + box)
              return Z if cursor == 0                           ; row 0 closes
   else return NZ
```

- A and B do nothing in the menu.
- A handler that sets `word_FFC2F6` bit 1 skips the redraw. Instant Replay does this when leaving with "Start = return to game", together with cursor 0, so the game resumes at once.
- Pages run inside the handler call. On return the menu is redrawn at the same cursor and top.

### 2.5 Port

- `godot/ui/pause_menu.gd` builds its own row list (Resume, Change Goalie, Edit Lines, Timeout, goalie toggle, Quit) in a Godot panel. It should instead read `menus.json` tables, keep cursor and top, show 4 rows with arrows, and use the two attributes.
- `WindowPlane` (`ui/window_plane.gd`) already has `print_at`, `frame` and `print_big` over the ui_overlay assets. The menu can be a `WindowPlane` with the box at (5,12).
- Keep the port's "Quit" row only as a port extra after the retail rows, or map it to "Exit Game" at the final intermission.

---

## 3. Menu tables (`menus.json`)

| Table | ROM | Used when | Rows |
|---|---|---|---|
| `pause` | `$19700` (L58935) | PauseMode | Resume Game, Instant Replay, Change Goalie, Edit Lines, Game Stats, Player Stats, Scoring Summary, Penalty Summary, Team Roster, Other Scores, Crowd Meter, Timeout, Player Cards, Record Holders, Period Stats, Manual/Auto Goalie |
| `pause_timeout_used` | `$1988C` | the team's `$30` bit 2 | as `pause` without Timeout |
| `pause_shootout` | `$19664` | `word_FFC2FA` bit 0 | Resume Game, Instant Replay, Team Roster, Player Cards, Record Holders, Manual/Auto Goalie |
| `intermission_pregame` | `$19A84` | `unk_131CC[0]` | Start Game, Change Goalie, Edit Lines, Team Roster, Other Scores, Player Cards, Record Holders |
| `intermission_pregame_playoffs` | `$19B38` | `[5]` | Start Game, Change Goalie, Edit Lines, Team Roster, Playoff Stats, Other Scores, Player Cards, Record Holders |
| `intermission_period` | `$19C04` | `[1-3]`, `[6-8]` | Resume Game, Game Stats, Player Stats, Scoring Summary, Penalty Summary, Team Roster, Other Scores, Crowd Meter, Change Goalie, Edit Lines, Player Cards, Record Holders, Period Stats, Manual/Auto Goalie |
| `intermission_final` | `$19D60` | `[4]` | Exit Game, Game Stats, Player Stats, Scoring Summary, Penalty Summary, Team Roster, Other Scores, Crowd Meter, Player Cards, Record Holders, Period Stats |
| `intermission_final_playoffs` | `$19E74` | `[9]` | same rows as `intermission_final` |
| `intermission_shootout` | `$19A00` | Intermission in shootout mode | Start Shootout, Shootout SetUp, Team Roster, Player Cards, Record Holders |
| `line_editor_exit` | `$19F88` | Edit Lines, a saved set exists | Exit, Set Original lines, Save Team Line, Load Team Line |
| `line_editor_exit_nosave` | `$19FF8` | no saved set | Exit, Set Original lines, Save Team Line |

The intermission index `unk_131CC` (L47683) is `gsp + (OptPlayMode != 0 ? 5 : 0)`.

Handlers (`menus.json` `handlers`):

| Handler | Line | Row | Section |
|---|---|---|---|
| `$15464` `rtss2` | L50812 | row 0 of every table (an `rts`) | §2.4 |
| `$9FD0` | L34505 | Instant Replay | §14 |
| `$9DE6` | L34315 | Change Goalie | §12 |
| `$82DA` | L30809 | Edit Lines | §13 |
| `$FDC5A` | L971880 | Game Stats | §5 |
| `$945A` | L33268 | Player Stats | §6 |
| `$9428` | L33252 | Playoff Stats (same code, d7 = 1) | §6 |
| `$8EB0` | L32247 | Scoring Summary | §7 |
| `$9142` | L32544 | Penalty Summary | §8 |
| `$89AC` | L31609 | Team Roster | §9 |
| `$80D4` | L30583 | Other Scores | §11 |
| `$9A2A` | L33980 | Crowd Meter | §10 |
| `$9D7A` | L34285 | Timeout | §12.2 |
| `$FA07E` | L965326 | Player Cards | §15.1 |
| `$FBC14` | L967908 | Record Holders | §15.2 |
| `$FD90C` | L971034 | Period Stats | §10.2 |
| `$FE1D8` | L973221 | Manual/Auto Goalie | §12.3 |
| `$FC620` | L968926 | Shootout SetUp | §13.3 |
| `$171CE`, `$8928`, `$88C8` | L53754, L31535, L31438 | Set Original lines, Save Team Line, Load Team Line | §13.2 |

---

## 4. The stats-page frame

### 4.1 Setup (`sub_9BD8` L34170) and exit (`$9CD8` L34244)

```
sub_9BD8(d0 = first plain row, d1 = end row):
  forceblack; disflags bit 0 = 0
  clear the sprite table; VDP $8C81 (H40); Map3col1 = 6 (window rows of 64 cells); $8D00; clear hscroll
  disflags bit 1 = 0 (H40)
  Framer tiles $55B86 at framercset through remap 91 23 45 67 89 AB CD EF   ; colour 0 -> 9
  font $AAC5A raw at word_FFB012 (sub_11F04)                                  ; font 0
  printz $BD 0,0 (window, $8000); dobitmap($54E24 map, all 40x28, tile base 1, no tiles, no palette)
  printz $FD 0,0 (window, attr 0); printy += d0
  dobitmap($54E24: tiles, palette lines 0, 2, 3 (mask $D), rows d0..d1-1, 40 wide)
  word_FFB014 = next tile; font $AAC5A through remap D1 23 45 67 89 AB CD EF  ; font 1
  printz $FE 0,0 (plane B); eraser(64, 32, $7FF)
  palcount = $18
$9CD8: forceblack; hscroll table back; $8D.. ; $8C00 (H32); Map3col1 = 5; disflags bit 1 = 1
  rink tiles (or RevRinkTiles), sub_FEA52, font $AAC5A remap 43 43 45 67.. at word_FFB012,
  sub_11F12 (in-game Framer), sub_16CAC/sub_16CC4/sub_16CD2/sub_16C96, SetTeamColors; rts
```

Layering, confirmed on the emulator:
- The window (`$921C` from the pause screen) covers the whole screen.
- Rows outside `d0..d1-1` are the background **with priority**.
- Rows `d0..d1-1` are the background **without priority**. Plane B's priority text shows above them, and the background hides plane B elsewhere.
- So **plane B text is clipped to rows d0..d1-1.** This is how the scrolling lists slide under the header.

| Page | d0 | d1 |
|---|---|---|
| Game Stats | 9 | 26 |
| Player Stats | 13 | 22 |
| Scoring / Penalty Summary | 10 | 26 / 25 |
| Team Roster | 13 | 23 |
| Other Scores | 6 | 26 |
| Crowd Meter | 9 | 28 |
| Period Stats, Edit Lines, Record Holders, Shootout SetUp | 0 | 28 or 26 |

### 4.2 Fonts, attributes and colours (stats palette = `$54E24`)

Print routines are as in ui_ingame.md §1:
- `print`/`printz`: a negative byte `v = -b` gives `printa = (v << 9) & $F800` and plane `v & 3`, then x, y.
- `print2`/`printz2`: `$FF` plane, `$FE` attr, `$FD` x, `$FC` y, `$FB` dx, `$FA` dy, `$F9` font, `$F8` attr-plane-x-y.
- `printbig`: 2-cell glyphs, upper case.

The `$F9 n` font switch selects the tile base `word_FFB012 + 2n`:
- font 0 (`word_FFB012`, raw): colour 0 transparent, ink colour 1, shadow colour 2.
- font 1 (`word_FFB014`, remap D1): the same with colour 0 → 13, an opaque background.

| Attribute | Line | Colour 1 (ink) | Colour 13 (font-1 background) | Use |
|---|---|---|---|---|
| `$8000` | 0 | `$EE2` cyan | `$A00` blue | numbers, the menu cursor row |
| `$A000` | 1 | `$CCC` white | `$006` | |
| `$C000` | 2 | `$0EE` yellow | `$A00` blue | column headers, labels, selected column |
| `$E000` | 3 | `$0E0` green | `$000` | assists, penalty names, ranks |

Line 1 is the in-game line 1 (`sub_9BD8` loads lines 0, 2, 3 only). It equals the `$54E24` line 1 except for colour 0.

- **Framer cells add** `map + printa + framercset`: the map words carry line 1, so a box drawn with `$8000` uses line 1 and one drawn with `$C000` uses line 3. The stats Framer remap gives a dark fill (colour 9 of line 1, `$600`) and a grey bevel.
- **printbig cells** also add (`map + printa + word_FFB010`). The in-game big font (remap 71…) carries line 1, so titles drawn with `$8000` use line 1 (white/grey bevelled letters).
- **Team plates:** `sub_8078` (L30547) copies 11x2 words from `unk_FFC334`:
  - offset 0 = home, `$2C` = away;
  - prepared by `sub_16D18` (L53257) from `$ABA14`;
  - `ui/team_plates_idx.png`, row 2t of team t;
  - after the copy, `printx += 11`, `printy` unchanged.
- **Glyphs:**
  - `{` up arrow, `}` down arrow, `[` left arrow, `]` right arrow;
  - `<` underline; codes `$12`/`$13`/`$14` = "ST"/"ND"/"RD" superscripts;
  - the letter O and the digit 0 share a glyph.

### 4.3 Scrolling lists (common pattern)

`d5ae` = plane-B scroll in pixels, `d5b0` = step (±2), `d5b2` = maximum.
- Each frame: `vcountwait`; `getpzjoy`; if Start is **held** (d3 bit 7) → `$9CD8`.
- Up/down **held** set `d5b0 = ∓2`; the page then moves 2 px a frame until `d5ae` is a multiple of the row pitch.
- When the scroll crosses a pitch boundary, the row that comes into view is redrawn into plane B's 32-row ring: the top row at `d5ae/8 - k` going up, the bottom one at `d5ae/8 + m` going down.
- The page writes VSRAM (`$40020010` = plane B V-scroll) = base + `d5ae`, so plane row 0 sits at screen row `-base/8`.
- The up/down arrows are redrawn from a 4-entry string table: none / `{` / `}` / both. Each entry prints at (x, y) then `dx -1, dy n`.

---

## 5. Game Stats (`$FDC5A` L971880)

```
sub_9BD8(9, $1A)
printz window (4,1) $8000; Framer(32, 6); printbig (6,4) "Game  Statistics"   ; title, then cursor (7,1)
sub_8078(away) at (7,1); printx += 4; sub_8078(home) at (22,1)           ; plates in the frame top
d5ac = d5ae = d5b0 = 0; d59e = OptPen ? $70 : $30                        ; scroll limit
sub_FDE24 (L972338): plates again at window (2,7) away and (26,7) home
   printz plane B (0,0) $8000
   rows = OptPen ? 15 rows at $FDFAA : 11 rows at $FE098
   for each row (printy 0, 2, 4, ...):
       printx = $15 - len/2 ; print label           ; len = the string's length word
       printx = $22, a2 = home: value ; printx = 9, a2 = away: value   ; each centred (x -= len/2)
sub_FDDAA: arrows at window (38,8) '{' when d5ae > 0, (38,26) '}' when d5ae < d59e (font 1, attr $8000)
loop: Start held -> $9CD8 ; up/down held -> scroll 2 px (stops each 16 px); VSRAM B = $FFB0 + d5ae
```

**Row values** (`sub_FDEB4` L972482; each row is label, word field, word field2):

| Label | Field | Format | TeamStats |
|---|---|---|---|
| Score | `$0C` | n | `goals` |
| Shots | `$00` | n | `shots` |
| Shooting Pct | — | goals*100/shots, "%" (0 when no shots) | `goals`, `shots` |
| Power Play * | `$02` / `$04` | n/m | `pp_goals` / `power_plays` |
| PP Minutes * | `$352` | m:ss (PushTime) | `pp_time` |
| PP Shots * | `$354` | n | `pp_shots` |
| SH Goals * | `$356` | n | `shorthanded_goals` |
| Breakaways | `$35A` / `$358` | n/m | `breakaway_goals` / `breakaway_attempts` |
| One-Timers | `$35E` / `$35C` | n/m | `onetimer_goals` / `onetimer_attempts` |
| Penalty Shots | `$362` / `$360` | n/m | `penalty_shot_goals` / `ps_attempts` |
| Faceoffs Won | `$0E` | n | `faceoffs_won` |
| Body Checks | `$10` | n | `checks` |
| Penalties | `$06` / `$08` | n/m | `penalties` / `penalty_minutes` |
| Attack Zone | `$0A` | m:ss | `attack_time` |
| Passing | `$14` / `$12` | "n/m (p%)", p = n*100/m | `passes` / `pass_attempts` |

- \* only with penalties on (`OptPen`).
- Layout: left column = **away**, right = **home**, label centred on col 21; one row every 2 plane rows; all `$8000` (cyan); plane row 0 at screen row 10.
- Screenshots: `pg_04_gamestats.png`, scrolled `ex_04_0.png`.
- The "Penalty Shots" row counts penalty-shot goals outside shootouts only (TeamStats `penalty_shot_goals` comment).

**Port: all fields exist in `TeamStats`.**

---

## 6. Player Stats / Playoff Stats (`$945A` L33268, `$9428` L33252)

```
d7 = 0 (Player Stats) or 1 (Playoff Stats: a2 = the team of potreeteam, cumulative playoff arrays)
sub_9BD8($D, $16); d5ac (category) = d5ae = d5b0 = 0
printz window (5,1); Framer(30, 6)
d7 = 0: printz2 "A - Switch Teams" at (12,26) font 1 $C000; printbig (8,4) "Player  Stats"
d7 = 1: printbig (7,4) "Playoff  Stats"
plate of a2 at (14,1)
sub_961A (L33434):                                    ; header, sort, first rows
  printz2 (4,11) font 1 $C000 "Player"
  header strings: goalie ($990E "Saves Shots Save %") or skater ("   G" "   A" " Pts" " SOG" " PIM",
     $9924), the column of the current category in $C000, the others $8000
  printz2 window (9,7); Framer(22, 3) ; printz (10,8) $E000: category string (unk_9942 + 1 + d5ac)
  sort into Satt $FFC018 (terminated by $FF):
     goalie category: only roster slots < goalie count
     key = value << 8 | ($FF - jersey number byte)       ; ties -> lower jersey number first
     value (sub_9872): goals $B4, assists $CE, points $B4+$CE, SOG $E8, PIM $102 (byte arrays + pnum);
        goalies (slot < sub_9F40) score 0 except Assists/Points (their assists)
  d5b2 = max(count - 6, 0) * 16; draw 6 rows (sub_9744)
sub_9744 (row k): plane B row 2k: rank (2 characters) at x 1 in $E000;
     sub_18B26 name ("NN Lastname") at x 4 in $8000; values from x $11, 4 characters each
     (G 17, A 21, Pts 25, SOG 29, PIM 33), the selected column $C000
     goalie category: saves = shots against - goals against (>= 0), shots against, save % = saves*100/shots, "%"
loop: Start held -> $9CD8; A (new) -> other team (not in Playoff Stats); left/right -> category -1..4
      (redraw); up/down held -> scroll 2 px (16 px rows), VSRAM B = $FF98 + d5ae
sub_99C6: arrows at window (2,11) table $9A02 (12 rows apart: '{' at row 11, '}' at row 23)
```

- Categories (`$9942`): Goalie Saves (-1), Goals (0), Assists (1), Points (2), Shots On Goal (3), Penalty Minutes (4).
- Screenshots: `pg_05_playerstats.png`, `ex_05_0..3.png`.

**Port:** `TeamStats.player_goals/player_assists/player_shots/player_pim`. The goalie entries (goals against, shots against) are the same arrays (puck_logic.gd adds to the goalie's `player_goals`; `player_shots` for the goalie = shots against, set by `chk_shot_stat`). Jersey numbers come from `PlayerData`. Playoff Stats needs the playoff arrays `$FFCD96/$FFCDCA/$FFCDFE/$FFCE32` (table `$98E6`): **not applicable**.

---

## 7. Scoring Summary (`$8EB0` L32247)

```
sub_9BD8($A, $1A); printz window (4,1); Framer(32,6); printbig (6,4) "Scoring Summary"; plates (7,1) (22,1)
printz2 window (0,8) font 1 $C000 "^Per^^Time^^Tm^^Goal/Assist^^^^^^^^P/S^^"   ; headers
d5ae = entries * 32 ; d5b2 = max(d5ae - $80, 0)
animate: d5ae -= 2 each frame down to d5b2 (redrawing entries as they come in)    ; opens at the newest
loop: Start held -> exit; up/down held -> scroll (32 px per entry); VSRAM B = $FFB0 + d5ae
entry (sub_907C, record r of ScoreSum $FFC474, 6 bytes): eraser(40, 4); printx 1:
   sub_11C72: period " 1"/" 2"/" 3"/"OT" (time >> 14), x += 2, PushTime(time & $3FFF) -> "m:ss"
   team abbreviation at x $C (team of byte 2 bit 7: 0 home, 1 away)
   strength at x $23: $912A[byte 2 & $7F] = "SH2" "SH" "" "PP" "PP2"
   scorer at x $10: sub_18AE8 "NN F. Lastname" (byte 3)
   printa $E000; assist 1 at x $12 next row (byte 4), assist 2 at x $12 the row after (byte 5), $FF = none
arrows: sub_93C4 window (4,9) table $9400
```

Shot: `pg_06_scoring.png`.

**Port:** `HockeyWorld.score_summary` = `[{time, strength, away, scorer, assist1, assist2}]`, the same fields; max 60 records (retail `$168` bytes). Present.

## 8. Penalty Summary (`$9142` L32544)

Same frame as §7 (`sub_9BD8($A, $19)`):
- title "Penalty  Summary" at (5,4);
- headers "^Per^^Time^^Tm^^Player/Penalty^^^^min^^^".

Entries are 3 rows (24 px) from PenSum `$FFC5DE` (4 bytes):
- period and time at x 1;
- team abbreviation at x `$C`;
- minutes at x `$23` (PenaltyList byte 1);
- player at x `$10` (`sub_18AE8`);
- next row: the penalty name at x `$13` in `$E000` (PenaltyList +2; texts in `ui/messages.json` `penalty_list`).

It opens at the newest entry, as §7 (`d5ae = n*24`, maximum `n*24 - $78`, 5 visible). Shot: `pg_07_penalty.png`.

**Port:** `GameRules.pen_sum = [{time, id, pnum}]` (id | `$80` away). Present.

---

## 9. Team Roster (`$89AC` L31609)

```
sub_9BD8($D, $17); d5b2 = tmline + 1 (line shown: 0 goalies, 1 Sc1 .. 7 PK2); d5ac = attribute column 0
printz window (7,1); Framer(26,6); printbig (9,4) "Team  Roster"; plate (14,1)
printz2 (2,12) font 1 $C000 "Pos.^Player", (30,12) "Rating", (12,26) "A^-^Switch^Teams"
Framer(18,3) at (1,8) and (21,8)
sub_8BA6: printz2 (2,9) font 1 $E000: line name ($8CBE: "    Goalies    }", "{  Scoring  1  }" ...
          "{Penalty Kill 2 "); (22,9): attribute name (PAttribColumns $193F8 or, for the goalie line,
          GAttribColumns $1955A); plane B rows (5 a line, $80 px a line): position, number, name,
          the attribute value at x $1E
loop: Start held -> exit; A -> other team; left/right -> attribute column; up/down -> line (scrolls
      $80 px at 2 px a frame, 0..$380); VSRAM B = $FF90 + d5ae
```

**Attribute columns** (`pages.json` `skater_columns` / `goalie_columns`). Each entry is a header string and a long `d4`: the low word is the format, the high word the attribute mask for `CalcAttrib`.

| Format | Value | Port |
|---|---|---|
| 0 Status | tmpdst: -1 "Ice", -2 "Bench", -3 "Injury P", -4 "Injury G"; ≥ 0 (in the box): m:ss of bits 0-11, "Injury G" if bit 12, " C  " suffix if bit 14 (coincidental) | `TeamStats.tmpdst` |
| 2 Energy | `energy / $28`, at most 100 | `TeamStats.energy` |
| 4 Handed / Glove Hand | "Righty"/"Lefty" | `PlayerData` handedness |
| 6 Weight | `value * 8 + $8C` "lb" | `PlayerData` weight nibble |
| `$A` rating (Overall, Agility, Speed, Off./Def. Awareness, Shot Power/Accuracy, Pass Accuracy, Stick Handling, Endurance, Aggressiveness, Checking; goalies: Puck Control, Stick/Glove Right/Left) | `CalcAttrib` (L966171) with the hot/cold table + `AttribAdjust` (L975195: < 50 → v/2 + 25). Overall uses the weight lists `OvrPlayerWgtList`/`OvrGoalWgtList`. | `PlayerData.overall()`, `RosterLogic.attribute_calc` |

Shots: `pg_08_roster.png`, `ex_08_*.png`.

---

## 10. Crowd Meter and Period Stats

### 10.1 Crowd Meter (`$9A2A` L33980)

`sub_9BD8(9, $1C)`; window (6,1) Framer(28,6); printbig (9,4) "Crowd  Meter"; plates (7,1)/(22,1).

Rows from (4,12), one every 2 rows, label in `$8000` (cyan), value at x 28 as 3 digits + " dB":

| Row | Value | Port |
|---|---|---|
| Current Level | `sroot(CwdExciteLvl*4) + $41` | `HockeyWorld.crowd_excite` |
| Average Level | `sroot((SumCwdExciteLvl / NumCwdExciteLvl)*4) + $41` | `GameRules.sum_excite / num_excite` |
| Peak Level | `sroot(MaxCwdExciteLvl*4) + $41` | `GameRules.max_excite` |
| Arena Record (ValidSRAM ≥ 0) | SRAM record of HomeTeam, block byte 8; `$50` (80 dB) when 0 | `GameRules.crowd_record_value` (always `$50` in the port) |
| League Record (ValidSRAM ≥ 0) | the same for the team `sub_FEC5E` (L974860) returns | missing (SRAM) |

Exit: Start (new press, `_rjoy` L34494). Shot: `pg_10_crowd.png`.

Note: `sroot` is `RinkBoards.sroot` in the port. The meter value `CurCrowdMeter` itself is not shown here.

### 10.2 Period Stats (`$FD90C` L971034)

```
sub_9BD8(0, $1C); d598 = 0 (goals)
plane B: Framer(8,8) at (1,11) and (1,19)
away logo ($F86F2[VisTeam], 6x6, palette $FF462 + 32*team into line 2) at (2,12) attr $C000;
   copy line 2 -> line 3 (L971172); home logo at (2,20) attr $E000 (line 2 = home)    ; map line 1 XOR attr
window (4,1): Framer(32,6); printbig (6,3) "  Period Stats  "
headers plane B row 9: "1" x 12, "2" x 17, "3" x 22, ["OT" x 26 when byte_FFC2FC bit 1], "Total" x 32;
   row 10: '<' underlines
mode line (18,7) "Goals" / "Shots", and (15,26) "For Shots ]" / "[ For Goals"
rows: away y $E, home y $16; per period k (only while gsp > k; OT column only with the OT bit):
   value at x $B, $10, $15, $1A (2 digits, 3 when >= 100), total at x $21
   field $342 + 2k (goals) or $34A + 2k (shots)
loop (_rjoy): right -> shots, left -> goals, Start -> exit
```

- `byte_FFC2FC` bit 1 is set by `StartPer` when gsp = 3 (L29856) and cleared by `GameSetUp`.
- **Port:** `TeamStats.period_goals/period_shots[0..3]`. "OT played" = `HockeyWorld.gsp >= 3` at any time this game (no flag needed).
- Shots: `pg_14_period.png`, `ex_14_0.png`.

---

## 11. Other Scores, the ticker and the highlights (other games)

### 11.1 Other Scores (`$80D4` L30583)

```
sub_9BD8(6, $1A); window (5,0) Framer(30,6); printbig (14,3) "Scores"; dobitmap $B3E74 at (11,1)
   (19x2 "HOCKEY NIGHT", no palette load)
printz2 plane B (4,0); for d3 = GetShifter() .. 0, skipping gamenum, flags bit 1, flags bit 2:
   first team 2 (+2, score +$C), then team 1 (+0, score +$A) ; sub_8250: city at x 6, score at x $18
   period at x $1C: unk_191E4[gsper - 1] ("1ST" "2ND" "3RD" "OT" " F"); next game 3 rows lower
d5b2 = (printy - $15) * 8 when positive; VSRAM B = $FFD0 + d5ae; scroll 24 px a game
arrows: window (4,6) table $82BC ('{' at row 6, '}' at row 25)
```

- With 8 games (regular season) the list is 24 rows, one 24-px scroll step.
- The arrow table has only 3 strings: index 3 ("both arrows") would read the code at `$82DA`. It is never reached with one step.
- Shots: `pg_09_others.png`, `ex_09_0.png`.

### 11.2 Ticker (intermission) — see ui_ingame.md §8.1

- Framer 26x5 at window (3,23).
- Heading at (4,24): `$13488` "EA Hockey Night" (regular season) or the playoff round names.
- Period label right-aligned at `4 + $17 - len/2`.
- Two rows: city at x 4, score at x `$19` (25), in `$8000`.

### 11.3 Highlights (`sub_1351C` L48161, `sub_1354C` L48181)

For each other game flagged close (gsstruct flags bit 1, set by `SetScore` when it is within a goal at the 3rd period):
- a Framer 24x3 "Highlight from game:" over the ticker for `$B4` frames;
- then a **live CPU-vs-CPU simulation** of that game, with:
  - its teams (HomeTeam/VisTeam swapped in, `clearTeamStats`, `restoreteams`);
  - its period and a random 60-179 s clock;
- it runs `DoGameFrame` until a goal or until C/Start, and a tie is then broken by a random goal (`$C00008` H counter).

The real game's state is restored by `restoreteams` afterwards. Not applicable to an exhibition port (§16).

### 11.4 Data

- `gsstruct` (`$FFCE66`, 16 bytes a game; rules_clock_penalties.md §0.6) is filled by `NewPO`/`MakeTree` (L54901/L54938) from a random one of the 32 playoff seedings at `$5576`. `InitScores`/`UpdateScores`/`SetScore`/`getscore` (L47726-47815) then advance it one period per real period.
- The score per period follows `sctab` (team offense nibble vs defense nibble, rules_clock_penalties.md §1.5).
- **Port: missing** (no `gsstruct`, no other games).

---

## 12. Change Goalie, Timeout, goalie toggle (pause screen, H32)

### 12.1 Change Goalie (`$9DE6` L34315)

```
push cursor/top; top = goalie count (sub_9F40)
printz window (4,12) $8000; Framer(24, 3 + goalies)
cursor = ($26(a2) < 0) ? 0 : $26 + 1
draw (L34366): rows from y $D; per row: attr $8000 on the cursor row else $A000; 22 blanks from x 5;
   row 0 "no goalie" at x 11; row k: jersey (2 BCD digits of the player record byte 0) at x 5, name at x 8
_rjoy loop: down/up move (clamped); C or Start:
   row 0: $26 = $FFFF unless $26 already < -1 (a CPU pull, high byte $FF) ; row k: $26 = k - 1
   SetPersonel (L51238); restore cursor/top; rts (the pause menu is redrawn)
```

Shot: `pg_02_goalie.png`. **Port:** `GoalieLogic.change_goalie` / `goalie_row` exist (audit_ai.md G3). Only the retail layout is missing.

### 12.2 Timeout (`$9D7A` L34285)

```
cursor -= 1; top -= 1; table = unk_1988C ; $30(a2) bit 2 = 1
printz window (5,12); Framer(22,6); printz (12,14) "Timeout", cursor (17,15): team city centred
sub_13098 on both teams (all energy $1000); waitx($78)
```

Shot: `pg_11_timeout.png`. **Port:** `HockeyWorld.timeout()` exists. Missing: the box and the 120-frame hold.

### 12.3 Manual/Auto Goalie (`$FE1D8` L973221)

- Only when `OptNOP != 0`:
  - both pads on the same team (`cont1team == cont2team`): **both** `word_FFD05C` and `word_FFD05A` toggle;
  - otherwise pad 2 (`sflags` bit 1) toggles `word_FFD05C`, pad 1 `word_FFD05A`.
- During a penalty shot or shootout attempt it also hands the goalie to the pad (L973281 on).
- **Port:** `HockeyWorld.toggle_goalie_control` (audit G6b).

---

## 13. Line Editor (Edit Lines `$82DA` L30809) and Shootout SetUp

### 13.1 Editor screen

```
$30(a2) bit 0 = 1 (line menu redraw later); sub_9BD8(0, $1C); d5ac = d5b0 = 0; d5b8 = 1 (Sc1, slot 1)
printz2 plane B; eraser(40, 28); byte_FFC012 = $FF
sub_86F8 (L31199): window = stats background; plane B (7,1) Framer(26,6); printbig (10,4) "Line  Editor"; plate (14,1)
sub_8566 (L31075): lines shown = mask $85E6[(d5b8 >> 3) (- 1 when OptLine != 0)]:
     Sc1+Sc2+Chk / PP1+PP2 / PK1+PK2
   on a mask change sub_868C (L31174): erase plane B rows 10-27, position labels LD RD LW C RW at
     x 1 rows 14, 16, 18, 20, 22 (attr $8000)
   per shown line k (sub_85EE): header at ($879E[k].x, $C) "Sc1"+" Line" ($191A6 names), $8000;
     slots ($879E[k].count + 1: 5, or 4 for PK lines) from row $E, every 2 rows, at x - 1 in $C000;
     name = sub_18B6E (last name) of RAM line $16A + 8k + slot;
     the cursor slot is printed with word_FFB030 = 2, i.e. font 1 (opaque background bar)
   name box: printz2 (8,7) font 1; Framer(24,3); (21,8): "NN First Last" of the cursor slot, centred
loop (sub_11318 repeat): Start -> exit menu; C -> Select Player; up/down: d5b8 -/+ 1;
     left/right: -/+ 8; validated through $87CA (a slot index that maps to 0 is refused)
```

Shots: `pg_03_lines.png`.

### 13.2 Select Player list and exit menu

- **Select Player (C, L30875 on):**
  - the candidates are the defensemen for an LD/RD slot (`d5b8 & 7` ≤ 2) and the forwards for LW/C/RW. The roster order is goalies, forwards, defense, with the counts from the team record (`sub_9F40` goalies, `sub_9F7E` forwards; TeamData `goalie_count`/`forward_count`/`defense_count`);
  - top boxes: Framer 18x3 at (1,0) "{Select Player}", and Framer 18x3 at (21,0) with the attribute name (PAttribColumns);
  - 6 rows from row 2: number, name and attribute value (`getNameandAttrib` L32055);
  - controls: up/down = player, left/right = attribute, C = assign (`sub_8898`: if the player is already on that line, the two trade places), Start = back.
- **Exit (Start, `$8812` L31383):**
  - the menu engine with `unk_19F88` (Exit, Set Original lines, Save Team Line, Load Team Line) or `unk_19FF8` (no Load), box at (9,12) on H40;
  - rows in font 1 line 2, the cursor in line 0;
  - C or Start chooses; Exit (row 0) → `$9CD8`.
- **Exit-menu rows:**
  - "Set Original lines" = `sub_171CE` (L53754): copy the team record's lines back;
  - "Save Team Line" = `$8928`: pack the 7 lines into `$FFD076` (team + 1, then nibbles);
  - "Load Team Line" = `$88C8`: unpack them.
  - `$FFD076` is above the area `Opening2` clears, so a saved set survives until power-off.
- Shots: `ex_03_*.png`.

**Port:** `LineLogic.edit_line` exists, with the port's own layout. The RAM lines are `TeamStats.ram_lines`, the original lines `TeamData.lines`. Save/Load is a session-only `team + lines` slot.

### 13.3 Shootout SetUp (`$FC620` L968926, shootout mode only)

- Same frame as §13.1: title "  Shootout  " (10,4), plate (15,1).
- "Shooters" at (7,12); "1. " … "5. " at x 3, rows 14-22; "Goalie" at (26,12).
- Names at x 7 (shooters) and x 26 (goalie).
- Name box at (8,7).
- Lists in `$FFD57A` (home) / `$FFD588` (away): 5 shooters then the goalie, roster slots.
- Controls:
  - up/down = shooter;
  - left = shooters column (slot 0), right = goalie (slot 5);
  - C = Select Player list (as §13.2);
  - Start = back.
- Shots: `so_setup*.png`.
- **Port:** `ShootoutLogic` already holds the lists (shootout_logic.gd:53).

---

## 14. Instant Replay (`$9FD0` L34505) — description only

**Entry:**
- clear `doshot` bit 0, forceblack, `word_FFC2EE` bit 3 (replay mode), `ClrHor`;
- fill the window with `$7FF`; load the `$BB4F6` tiles at `word_FFB026`;
- draw the button panel (`sub_A448`: rink map cells 32-39 × 85-88, `replay_panel_idx.png`, buttons A ◄◄, B |▶, C ▶) at window (2,2) for `$F0` frames, then erase it (`sub_A48A`);
- rewind the buffer (`sub_A4F6` until the start).

**Each tick** (`d7` frames, normally 1):
- **D-pad:** looks for the nearest player (squared distance 4..`$100`) within ±1 octant of the pressed direction. If there is one, the camera locks on him (`word_FFC2F0` bit 5, his SCnum in `$16(a5)`). If not, the free camera pans by the `$A23E` table, clamped to x ±`$88`, y −`$126`..`$126`.
- **C (new press):** play/stop (`word_FFC2F0` bit 1).
- **A held:** rewind 4 records a tick.
- **B held:** forward one record with the tick doubled (slow motion).
- **A+B held:** drop the camera lock.
- **Start:** shows the prompt `sub_A4A8` (`$BB4EE`, 16x11 cells at window (2,0), `replay_prompt_idx.png`: "B Options / C Reverse Angle / START = RETURN TO GAME"). In the prompt:
  - Start → leave with cursor 0 and `doshot` bit 1 (straight back to play);
  - B ("Options") → leave to the pause menu;
  - C ("Reverse Angle") → `word_FFC2F4` bit 6, clear `doshot` bit 0, erase the prompt (`sub_A4D8`) and continue the replay (the angle switch itself: UNRESOLVED U2);
  - A → nothing (the loop continues with the prompt up).
- **On leaving:** `SetRCords`, `sub_9CDC`, the in-game tiles are reloaded and `SetHor`.

**Port:** not applicable. The port has no replay buffer (audit_ai.md G8). Drop the row or show it disabled.

---

## 15. SRAM pages

### 15.1 Player Cards (`$FA07E` L965326)

**Gate:** returns at once unless `ValidSRAM` (`$FFD458`) ≥ 0.

**Setup:**
- H40 (its own setup);
- `sub_F9FC0`/`sub_F9FEA` (SRAM records into `$FFCF36…`);
- font 0 through remap `05 23 41 67 89 AB CD EF`;
- window = `cards_bg` (`$E6632`, palette lines 0, 2, 3) with the EA SPORTS and PLAYER CARDS banner built in;
- NHL shield (`$E9A80`, line 3 palette) at plane B (1,1), NHLPA (`$E9ED6`) at (33,1).

**Cards** (index `d4f0/d4f2` per team, `d4f6` = team):
- **Card 0, the team card:** city and name; "Team Rating" from the static byte table `$FE18E` (`sub_FE172` L973164; LA 74, MTL 73); "Records" (season, SRAM); "Starting Line" G LD RD LW C RW.
- **Player cards:**
  - the photo: 6x6 at B (1,8) attr `$E000`, line 2 = photo palette;
  - photo lookup: `sub_FAE26` L966584, a per-team list at `$F92F4` of {photo, roster slot}; a slot that is not listed gets a generic silhouette;
  - the photo decoder is `sub_FE98A` L974538 (3 bpp, +5);
  - number and " Goalie"/" Forward"/" Defenseman";
  - "Overall Rating";
  - "Records" (SRAM season stats);
  - "This Game": Goals/Assists, or Saves/Save %.
- Team logo 6x6 at B (33,8) with the team's line-1 palette (`sub_FA66E`).

**Controls:**
- left/right = previous/next card (wraps);
- C = next;
- A = other team;
- Start held = exit.

Shots: `pg_12_cards.png`, `ex_12_*.png`.

### 15.2 Record Holders (`$FBC14` L967908)

- `sub_9BD8(0,$1A)`; NHL and NHLPA logos at B (1,1)/(33,1); window (11,1) Framer(18,7); printbig "Record" (14,2), "Holders" (13,5); "Name" (5,8).
- Three pages from SRAM user records (`$FBDB2`, `$FBE04`, `$FBE54`):
  - "Win % / Win-Loss-Tie" with "Use A+C to clear ALL win records";
  - "Goals / Teams" with "TEAM MUST WIN TO QUALIFY";
  - "Saves / Teams".
- left/right page; A+C on page 0 clears (`sub_FE6D2`); Start held exits.
- With fresh SRAM the lists are empty (`pg_13_records.png`, `ex_13_*.png`).

---

## 16. Exhibition-only port: what applies

| Page / feature | Retail needs | Exhibition port |
|---|---|---|
| Pause / intermission menus, Change Goalie, Timeout, goalie toggle | — | **port as retail** (tables `pause*`, `intermission_pregame`, `intermission_period`, `intermission_final`, `intermission_shootout`) |
| Game Stats, Player Stats, Scoring Summary, Penalty Summary, Team Roster, Period Stats | match stats | **port as retail**; all data present |
| Crowd Meter | SRAM for the 2 record rows | first 3 rows as retail; show the 2 record rows with 80 dB (`$50`, as fresh SRAM), or hide them as retail does without SRAM |
| Edit Lines, Shootout SetUp | — | **port as retail**; Save/Load Team Line = a session slot |
| Other Scores, ticker, highlights | `gsstruct` (other league games) | optional. Cheapest faithful choice: 8 pairings of other teams, scored one period per real period with `getscore` (TeamData `sim_offense`/`sim_defense` = the rating nibbles). Otherwise drop the "Other Scores" row and the ticker. Highlights (a live sim of another game): drop. |
| Player Cards | SRAM | show with empty "Records" (as fresh SRAM) plus This Game and photos, or drop the row |
| Record Holders | SRAM | drop the row, or show the static page with empty lists (what retail shows with fresh SRAM) |
| Playoff Stats, playoff menus, PlayoffScreen, ticker round names | playoffs | **not applicable** |
| Instant Replay | replay buffer | **not applicable**: drop the row |
| End of game | — | Stars of the Game box (ported logic, ui_ingame §10), then the final intermission ("Exit Game" → setup) |

## 16.1 Data mapping summary (retail RAM → port)

| Retail | Port | Status |
|---|---|---|
| team struct `$00`-`$14`, `$342`-`$362` | `TeamStats` (`shots`, `pp_goals`, `power_plays`, `penalties`, `penalty_minutes`, `attack_time`, `goals`, `faceoffs_won`, `checks`, `pass_attempts`, `passes`, `period_goals`, `period_shots`, `pp_time`, `pp_shots`, `shorthanded_goals`, `breakaway_*`, `onetimer_*`, `ps_attempts`, `penalty_shot_goals`) | present |
| `$B4/$CE/$E8/$102/$11C/$136` + pnum | `player_goals/assists/shots/pim/checks/toi` | present |
| `$66` tmpdst, `$32` energy, `$16A` lines, `$26` goalie, `$30` flags | `tmpdst`, `energy`, `ram_lines`, `goalie_pnum`/`goalie_pulled`, `flags30` | present (a human pull's `$FFFF` state: audit G3, done) |
| ScoreSum / PenSum | `HockeyWorld.score_summary` / `GameRules.pen_sum` | present |
| CwdExciteLvl, Max/Sum/NumCwdExciteLvl, CrowdPeak, CrowdRecord | `HockeyWorld.crowd_excite`, `GameRules.max_excite/sum_excite/num_excite/crowd_peak/crowd_record_value` | present |
| `byte_FFC2FC` bit 1 (an OT period started) | `HockeyWorld.gsp >= 3` | derivable |
| team rating `$FE18E` | — | **missing**: export has it (`pages.json` `player_cards.team_rating`) |
| `gsstruct`, TickerNum, gamenum | — | **missing** (Other Scores, ticker) |
| SRAM records (`$FFCF36` block, ValidSRAM, OptUserRec, league crowd record) | — | **missing** (not applicable) |
| `$FFD076` saved lines | — | **missing** (session slot) |
| playoff arrays `$FFCD96…` | — | not applicable |
| menu state `$FFCF20-$FFCF28`, `d5ac-d5b8` page state | UI-local | the UI owns it |

---

## 17. Exported assets (`tools/extract/ui_menus.py` → `godot/assets/ui/menus/`)

| File | Content |
|---|---|
| `menus.json` | the 11 tables (labels, raw 18-char strings, handler address and id, toggle flag, attribute strings), `unk_131CC` index, the Manual/Auto strings, the engine geometry (box, rows, arrows, repeat) |
| `pages.json` | per page: handler, line, `sub_9BD8` rows, every inline string decoded into ops (`{"at":[x,y],"plane","attr"}`, `{"text"}`, `dx`/`dy`/`x`/`y`/`attr`/`font`/`plane`), Framer/plate/image ops, string tables, data tables (Game Stats rows with field offsets, formats and TeamStats names; Player Stats categories and fields; strength strings; period labels; line names; attribute columns; status strings; Edit Lines column/page/cursor tables; Record Holders pages; Player Cards strings and team ratings), layout x positions, scroll parameters, controls; the 28 team cities/abbreviations |
| `palettes.json` | `stats` (4 lines of `$54E24`), `cards` (composition and `cards_bg` lines), `team_logos` (28 lines, `$FF462`), `photo` (`$C63F8` line 1), `logo_nhl`, `logo_nhlpa` |
| `font_stats_idx.png`, `font_stats_alt_idx.png`, `font_cards_idx.png`, `font.json` | the `$AAC52` font raw / remap D1… / remap 05 23 41…, 16 tiles a row, line 0, with the char → tile map and the special glyphs |
| `framer_stats_idx.png` | Framer 3x3 (TL T TR / L C R / BL B BR) through remap 91…, map line 1 |
| `stats_bg_idx.png`, `cards_bg_idx.png` | 320x224 backgrounds; colour 0 written as line 0 colour 0 (the backdrop) |
| `hockey_night_idx.png` | 152x16, Other Scores title (page palette) |
| `logo_nhl_idx.png`, `logo_nhlpa_idx.png` | 48x48 |
| `team_logos_idx.png` | 28 logos 48x48, 4 a row, map line 1 (colour each with `palettes.json` `team_logos[t]`) |
| `photos_idx.png`, `photos.json` | 148 photos 48x48, 16 a row (0-3 generic silhouettes `$C682E $C6B98 $C6F02 $C726C`); per team `{slot, photo}`; the fallback rule |
| `replay_panel_idx.png`, `replay_prompt_idx.png` | the Instant Replay panel and prompt (rink palette), for reference |

From `godot/assets/ui/` (`ui_overlay.py`):
- `font_idx.png`: the pause/intermission text;
- `bigfont_idx.png`: every page title;
- `framer_idx.png`: pause boxes;
- `team_plates_idx.png`: `sub_8078` plates.

The run is deterministic (same bytes on a re-run). `--preview DIR` writes static page previews.

---

## 18. Port checklist

1. **Menu engine** (§2):
   - a `WindowPlane` menu that draws any `menus.json` table: box (5,12) 22x6, rows (7,13..16), cursor attribute line 0, others line 1, arrows `{`/`}` at (6,13)/(6,16);
   - auto-repeat 16/5 frames;
   - C runs the handler, Start or row 0 closes, A/B ignored.
   - Then replace `pause_menu.gd`'s ad-hoc list with `pause` / `pause_timeout_used` / `pause_shootout`.
2. **Pause screen backdrop:** the side view (`Rink2D` side mode) with the clock, as at intermission.
3. **Intermission menu:**
   - menu by gsp (`intermission_pregame`, `_period`, `_final`, `_shootout`), ticker optional (§16);
   - any pad can drive it, and the driving pad's team owns Change Goalie/Edit Lines;
   - the final intermission's row 0 "Exit Game" ends the game (`scenes/game.gd` `_quit`).
4. **Stats page host:**
   - a full 320x224 page (H40) with `stats_bg` (lines 0, 2, 3 from `palettes.json` `stats`, line 1 = in-game line 1);
   - a header layer and a clipped, scrollable text layer for rows `d0..d1-1`;
   - Framer cells use line = map line + attribute line;
   - Start held exits back to the menu at the same row.
5. Pages in order of value:
   1. Game Stats (§5)
   2. Player Stats (§6)
   3. Scoring Summary (§7)
   4. Penalty Summary (§8)
   5. Period Stats (§10.2)
   6. Team Roster (§9)
   7. Crowd Meter (§10.1)
   8. Line Editor (§13, replacing the port layout)
   9. Change Goalie and Timeout boxes (§12)
   10. Shootout SetUp (§13.3)
   11. Player Cards without SRAM (§15.1)
   12. Other Scores (optional, §11)
6. **Drop or disable:** Instant Replay, Playoff Stats, Record Holders (or the empty page), highlights.
7. **End of game:** keep the Stars of the Game box (ui_ingame §10) on the final whistle, then the final intermission; no other final screen.
8. **Data to add:**
   - team rating (`pages.json`);
   - optional other-games slate (`gsstruct` equivalent);
   - a session slot for Save/Load Team Line.

---

## 19. UNRESOLVED

- **U1.** How `NewPO`/`MakeTree` choose the 16 teams of a regular-season slate. In the emulated LA–MTL game, the 8 other games shown (Florida–Toronto … Quebec–Hartford) included neither team, although `NewPO` looks for Team 1 in the chosen seeding. Only matters if the port reproduces Other Scores.
- **U2.** The prompt's C "Reverse Angle" path (`word_FFC2F4` bit 6, `sub_A4D8`). Inferred from the prompt picture and the bit use in `sub_A528`; not stepped through.
- **U3.** Player Cards' "Records" contents and the SRAM block layout (`sub_F997A`, `$FFCF36`…): not decoded (not needed without SRAM).
- **U4.** Record Holders' record formats (pages 1-2) and `sub_FE6D2`'s clear: not decoded.
- **U5.** The Line Editor with `OptLine != 0`: the one-entry shift of `$8798` and `$85E6` was read from the code, not seen on the emulator (the test game had OptLine 0).
- **U6.** The exact format of the `$FFD076` saved-line block (`$8928`/`$88C8`) beyond "team + 1, then line nibbles".
- **U7.** Playoff Stats' cumulative arrays (`$FFCD96`…, `AddPOStats`): not decoded (not applicable).
- **U8.** Highlight simulation details (§11.3): which period a highlight runs in when the stored period is 0, and the goal-forcing rule's use of the HV counter, beyond the summary.

## 20. Port status

Ported: the palette fades (forceblack before the pause and intermission menus and the stats pages, palcount = $18 after; after the pause menu, play resumes once the game screen is back in, as loc_7DC0 waits; `ui/cram_fade.gd`). The menu engine and every table (`ui/pause_menu.gd`), the pause screen's side view (`HockeyWorld.pause_screen`), the intermission ticker, Change Goalie, Timeout, Manual/Auto Goalie, and the pages Game Stats, Player Stats, Scoring Summary, Penalty Summary, Team Roster, Crowd Meter (record rows 80 dB), Period Stats, Other Scores (an 8-game slate of the other teams scored per period by `getscore`; the pairing rule U1 is open), Record Holders (empty lists), Player Cards (no saved records), the Line Editor with its Select Player list and exit menu (a session slot for Save / Load Team Line) and Shootout SetUp (`ui/stats_pages.gd`). Instant Replay is ported (logic/replay.gd, ui/replay_view.gd) except the reverse angle (U2). Not ported: Playoff Stats (dropped row), the playoff menus, the highlights.

Port choices: every stats-page Framer uses line 1 (retail's `$C000` boxes would take line 3's grey fill; the emulator shows them dark). The Line Editor's cursor slot is drawn in line 3. Team Roster's ratings are PlayerData's display values (no hot/cold form). Fonts, fixed text, plates and boxes come from `pages.json`'s decoded print ops.
