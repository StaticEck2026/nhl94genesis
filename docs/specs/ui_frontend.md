# NHL '94 (Genesis): front end — Game Setup, Matchups, and back after "Exit Game"

Source: `lst/nhl94.bin.lst` (IDA listing, no address column; lines are written `Lnnnnn`, the label line of a routine unless stated) and `lst/nhl94.bin` (CRC32 `$9438F5DD`). ROM addresses are written `$xxxxx`, RAM `$FFxxxx`. The listing mis-decodes most inline data here (`printz` strings, `sub_1172C` remap bytes, the option strings, `unk_F8BF4`). Everything below was read from the ROM bytes and checked on the emulator.

Related specs: `title_screen.md` (the title, `Opening`), `ui_menus.md` (pause/intermission menus, stats pages, the pre-game "Start Game" menu, end of game), `ui_ingame.md` §1 (print engine, `Framer`, fonts).

Exported data: `tools/extract/ui_frontend.py` → `godot/assets/ui/frontend/` (§11). It reuses the team logos, photos, the SPORTS background and the `$AAC52` font that `ui_menus.py` writes to `godot/assets/ui/menus/`.

**Verification.** A Genesis harness (unicorn 68000 + VDP model + pads, `/tmp/claude-0/-home-user/ef020377-92e3-57ff-8519-5d51b4a7df4d/scratchpad/ui/emu.py`) booted the ROM, went through the title into the menus, changed every option, and started a regular game, a New Playoffs game, a Shootout, a User Records game and the idle demo. It also took the earlier agent's finished game through "Exit Game". The screenshots, plane dumps and scripts are in `/tmp/claude-0/-home-user/ef020377-92e3-57ff-8519-5d51b4a7df4d/scratchpad/fe/` (§13). `ui_frontend.py --preview` rebuilds the default Game Setup screen and the Matchups "Overall" page from the exported files. The Game Setup preview matches the emulator **pixel for pixel**. The Matchups preview matches everywhere except the typewriter text, which the preview does not draw.

---

## 0. Quick facts

- **Retail's front end after the title, in order:**
  1. **Game Setup**: one H40 menu with 9 option rows over an ice background, team-name plates and two logos.
  2. **Name Entry**: only with User Records On (SRAM).
  3. **Playoff bracket**: only in playoff modes.
  4. Then the **Matchups** screen (Ron Barr): H40, commentary, and 7 matchup pages. It is skipped in Shootout.
  5. Then `StartGame` → the pre-game intermission ("Start Game" menu, ui_menus.md §1.2) → the opening face-off.
- **No controller / "Users" screen and no pad icons in '94.** Pad assignment is the **Players** row: Demo, One - Home, One - Visitor, Two - Teammates, Two - Head to Head (plus Three / Four with the EA 4 Way Play adapter). Team selection is the **Team 1** (= home) and **Team 2** (= visitor) rows. There is no separate team-select screen.
- **Defaults** (`defmenuoptions` L54847, 9 words to `$FFD048`). The listing's labels match the screen:
  - Play Mode: Regular Season
  - Players: One - Home
  - Team 1: Montreal (`$B`)
  - Team 2: Los Angeles (`$A`)
  - Per. Length: **10 Minutes**
  - Goalies: Manual Control
  - User Records: Off
  - Penalties: **Off**
  - Line Changes: **Off**
- **Music:**
  - `$78` (title/menu theme) plays through Game Setup.
  - `$7A` for Matchups.
  - `$79` for the playoff bracket and the intermission.
- **Way back:** "Exit Game" → `GameOver` → song `$78` → `Opening2` → Game Setup with the **previous settings** (the title is skipped).
- **Hidden:** hold **A + C** while pressing **Start** on the Matchups screen to get **30-second periods** (`StartGame` L29748). An idle Game Setup screen starts a CPU demo after `$5460` frames (6 minutes).

---

## 1. Flow

```
Begin (L29715)          RAM clear, EASportsScreen, InitSaveRAM, sub_FE660 (saved lines from SRAM), HiScoreScreen,
                        LoadDefMenuOptions (L54836: defmenuoptions -> $FFD048..$FFD058), jmp Opening
Opening (L53865)        KillCrowd; newTitleScreen (title_screen.md; song $78); returns on Start
Opening2 (L53868)       KillCrowd; sr=$2700; clear RAM $FFB000-$FFD03E (options at $FFD048+ survive)
  GameSetUp (L960187)   the Game Setup menu (§2) until Start, or the idle demo (§2.10)
  sub_FBB88 (L967859)   User Records On: Name Entry for each human pad (§3)
  PlayoffScreen (L53888) OptPlayMode != 0: the bracket (§4)
  if !(word_FFC2FA bit 0): sub_FCC76 (L969615)   Matchups (§5); not in Shootout
  jmp StartGame (L29748)  A+C+Start held -> OptPerlen = 3; OptPen == 1 -> gmode bit 5 (offsides);
                        clearTeamStats; Shootout: Create_HotCold_Table x2; InitScores; setupice; LoadCrowdRec;
                        -> loc_17278 (L53825): ResetClock, song $79, Intermission (gsp 0, ui_menus.md §1.2)
...game...
PeriodOver -> Intermission ("Exit Game") -> GameOver (L53851): sub_180FC; OptPlayMode != 0: Playoff Stats
                        (sub_9428); PlayoffScreen; loc_172E4 (L53859): song $78; bra Opening2
demoread (L30159)       in play with cont1team = cont2team = 0: Start -> pause menu; any other new press ->
                        loc_172E4 (back to Game Setup)
```

---

## 2. Game Setup (`GameSetUp` L960187)

### 2.1 Screen setup (`setoptions` L962234)

```
vbint = loc_17C42; sr = $2500; disflags: bit0 = 0, bit2 = 1 (no int graphics), bit1 = 0 (H40)
VSPRITES $B400, window (VmMap3) $B800, plane B (VmMap2) $C000, plane A (VmMap1) $E000, 64-cell rows; setvram (fade from black)
orjoy
tiles (sub_11738 raw / sub_1172C remap, VRAM tile numbers as seen on the emulator):
   2     $AFE1A  team plates, raw               (home plate)
   $190  $AFE1A  through 03 41 25 67 89 AB CD EF -> word_FFD43A (visitor plate)
   $31E  $BF54A  9 Framer tiles through 03 56 75 64 89 AB CD EF -> framercset
   $327  $AAC5A  through 0F C0 45 67 89 AB CD EF -> word_FFB012 (not visible on this screen)
   $385  $BE272  the alternate font, raw -> word_FFBF52
printz plane A (0,0); eraser(40, 28, $7FF)
printz plane B (0,0); dobitmap($4B7A0, 40x28, palette mask $D = lines 0, 2, 3)          ; tiles $3E3
word_FFD432 = next tile ($4D3, 36 reserved: visitor logo); d4 += $24
printz plane A (0,0); dobitmap($4DEEE, 40x4, no palette)                                 ; header, tiles $4F7
printz plane A (1,14); word_FFD426 = d4 ($514); dobitmap($BEFB8, 38x13, no palette)      ; option panel
word_FFD430 = $51D (home logo, 36 reserved); word_FFD436 = $541: $BF70A raw (logo frame, home)
word_FFD438 = $547: $BF70A through 03 41 45 67 89 AB CD EF (logo frame, visitor)
defaultsprites2; HmShots = AwShots = $FF..
```

**Layers.** H40, 320x224. The window is off and no sprites are used.

| Plane | Cells | What | Image |
|---|---|---|---|
| B | (0,0) 40x28 | ice background with the EA logo at centre ice, line 0 | `setup_bg_idx.png` |
| A | (0,0) 40x4 | header bar: two plate slots and "AT" | `setup_header_idx.png` |
| A | (7,1) 11x2 | visitor plate (row `2*VisTeam`), line 1, priority | `team_plates_visitor_idx.png` |
| A | (22,1) 11x2 | home plate (row `2*HomeTeam`), line 1, priority | `team_plates_home_idx.png` |
| A | (8,5) 8x8 | visitor logo frame | `logo_frame_visitor_idx.png` |
| A | (24,5) 8x8 | home logo frame | `logo_frame_home_idx.png` |
| A | (9,6) 6x6 | visitor logo, line 2 | `../menus/team_logos_idx.png` |
| A | (25,6) 6x6 | home logo, line 1 | same |
| A | (1,14) 38x13 | option panel (9 tiles) | `setup_panel_idx.png` |
| A | x 3, y 15..25 step 2 | row labels, attribute `$0000` | `font_setup_idx.png` |
| A | x 17, y 15..25 step 2 | values, `$8000` (priority), 20 characters | `font_setup_idx.png` |
| A | (2,15) / (2,25) | `{` / `}` scroll arrows | font |
| A | (16, 14+2(row−top)) 23x3 | cursor box: Framer, `printa $6000` → line 0 + priority | `setup_framer_idx.png` |

**Palette** (CRAM):

| Line | Contents |
|---|---|
| 0 | `$4B7A0` line 0 |
| 1 | the home logo palette (`$FF462 + 32*HomeTeam`), then overwritten as below |
| 2 | the visitor logo palette. It replaces the background's line 2, which nothing uses. |
| 3 | `$4B7A0` line 3 |

`sub_17AF4` (L54595) overwrites line 1 as follows. The palette buffer `palfadenew` is `$FFBD28`, so `dword_FFBD4A` is line 1 colours 1-2.
- Colours 1-2 = the home team's colours, `unk_F8BF4 + 64*HomeTeam + 2`.
- Colours 3-4 = the visitor's colours, `+ $26`.
- Colour 5 = `$EEE`.

The plates and the logo frames use line 1. The visitor copies are remapped 1→3 and 2→4, so:
- the home plate and frame show the home colours;
- the visitor plate and frame show the visitor colours;
- the text is colour 5.

`sub_F8608` saves and restores `dword_FFBD4A/4E` around the home logo's `dobitmap`, so these colours survive the logo palette load. `palcount = $64` fades the change in.

**Fonts.**
- Labels and values use `print2` / `print` while `word_FFC2F8` bit 3 is set, so they take the **alternate font `$BE26A`** (`word_FFBF52`), drawn on line 0.
- That font differs from `$AAC52` in style.
- Its `(` `)` and `{` `}` glyphs are swapped. `{` and `}` are the up and down arrows.
- The char → tile map is in `frontend.json` `fonts.setup.chars`.
- O and 0 share a glyph.

### 2.2 Rows, values and defaults

The options are 9 words at `$FFD048` (`d7` = 2 × row):
- labels `unk_F80D4` (L962083);
- value strings `unk_F7D04` (L961172): 9 word offsets, then length-prefixed 22-byte strings;
- value counts `unk_F791E` (L960750), or `unk_F7930` (L960768) with 4 Way Play.

| Row | Label | RAM | Values (index: string) | Count | Default |
|---|---|---|---|---|---|
| 0 | Play Mode | `$FFD048` OptPlayMode | 0 Regular Season, 1 Continue Playoffs, 2 New Playoffs, 3 New Playoffs/7 game, 4 Shootout, (5 Demo: never selectable) | 5 | 0 |
| 1 | Players | `$FFD04A` OptNOP | 0 Demo, 1 One - Home, 2 One - Visitor, 3 Two - Teammates, 4 Two - Head to Head, 5 Two - Head to Head, 6 Two - Teammates, 7 One (4 Way Play list: 0 Demo, 1 One - Home, 2 One - Visitor, 3 Two - Teammates, 4 Two - Head to Head, 5 Three, 6 Four, 7 Two - Head to Head, 8 Two - Teammates, 9 Three, 10 Four, 11 One) | 8 (12) | 1 |
| 2 | Team 1 | `$FFD04C` Opt1Team | 28 teams by city (§2.5) | 28 | `$B` Montreal |
| 3 | Team 2 | `$FFD04E` Opt2Team | same | 28 | `$A` Los Angeles |
| 4 | Per. Length | `$FFD050` OptPerLen | 0 5 Minutes, 1 10 Minutes, 2 20 Minutes, (3 30 Seconds: cheat only) | 3 | 1 |
| 5 | Goalies | `$FFD052` OptGoalie | 0 Manual Control, 1 Auto Control | 2 | 0 |
| 6 | User Records | `$FFD054` OptUserRec | 0 On, 1 Off | 2 | 1 |
| 7 | Penalties | `$FFD056` OptPen | 0 Off, 1 On, 2 On, Except Off-sides | 3 | 0 |
| 8 | Line Changes | `$FFD058` OptLine | 0 On, 1 Off, 2 Auto | 3 | 1 |

**Special printing (`GameSetUp_4` L960985).**
- Teams: 22 blanks, then the city string of the team record (`$30E` table, team + word(+4)). Exceptions: team `$D` prints "New York Islanders" (`$F7CB2`) and `$E` prints "New York Rangers" (`$F7CC6`).
- Per. Length in Shootout prints "N/A" (`$F7CEE`).
- Team order (ROM ids):

| Ids | Teams |
|---|---|
| 0-6 | Anaheim, Boston, Buffalo, Calgary, Chicago, Dallas, Detroit |
| 7-13 | Edmonton, Florida, Hartford, Los Angeles, Montreal, New Jersey, NY Islanders |
| 14-20 | NY Rangers, Ottawa, Philadelphia, Pittsburgh, Quebec, San Jose, St. Louis |
| 21-27 | Tampa Bay, Toronto, Vancouver, Washington, Winnipeg, All Stars East, All Stars West |

The port's `res://data/teams/NN_*.tres` use the same numbering (`TeamData.team_index`).

**Per-mode value ranges** (`GameSetUp_3` L960788, `sub_F7B0A` L960944). The range is `d5 ≤ value < d4`. Leaving the range at either end wraps to the other end.

| Row | Regular Season | Continue / New Playoffs | Shootout | 4 Way Play |
|---|---|---|---|---|
| Players | 0-4 | 5-7 (Two - Head to Head, Two - Teammates, One) | 0-4 but 3 is skipped (L960871-960891) | regular 0-6; playoffs 7-11 with 9-10 skipped (L960891-960915) |
| Team 1 | 0-27 | New Playoffs: 0-25 (`moveq #$1A,d4` L960835 area: no All-Stars) | 0-27 | |

When a mode change puts a value out of its new range, the redraw clamps it (`sub_F7B20` calls `GameSetUp_3` with `d2 = 0`). For example, going from Regular Season to New Playoffs turns "One - Home" into "One"; then going to Shootout turns it into "Demo" (`pm_*.png`).

**Forced values** (`sub_F78A2` L960715, `loc_F7464` L960236):
- **Shootout:**
  - OptUserRec = 1, OptLine = 1, OptPen = 0.
  - On entering Shootout, `GameSetUp_3` saves User Records / Penalties / Line Changes to `TmpOptUserRec`/`TmpOptPen`/`TmpOptLine`, and restores them on leaving.
- **Players = Demo:**
  - OptUserRec = 1.
  - OptGoalie = 1 (Auto), and `word_FFD05A`/`word_FFD05C` = 1.
  - The goalie value stays Auto after leaving Demo.

### 2.3 Drawing

```
sub_F8070 (L962050), labels: printy = 15 - 2*top; for each of the 9 strings: if 15 <= printy <= 25:
     printx = 3, printa = 0, printm = 0 (plane A), print2 (word_FFC2F8 bit 3: alternate font); printy += 2
sub_F78A2 (L960715), redraw: forced values (above); if top changed: sub_F8070; then with word_FFC2F8 bit 3:
  sub_F7B20 (L960958): for d7 = 0..16 step 2: GameSetUp_3(d2 = 0) (clamp); if row >= top: GameSetUp_4
     GameSetUp_4 (L960985): printz $BF (17,16) -> attr $8000 plane A; printy += d7 - 2*top - 1
        (= 15 + 2*(row - top)); skip if printy > 27; print the value string (or the team, §2.2)
     sub_F7BFA (L961028): (2,25): '}' unless top == 3 or Shootout, else ' '; (2,15): '{' if top > 0 else ' '
  sub_17AF4 (L54595): HomeTeam/VisTeam = Opt1Team/Opt2Team (Regular Season and Shootout only);
     plates: dobitmap($AFE12, 11x2 from row 2*team) at (7,1) tiles word_FFD43A (visitor) and (22,1) tiles 2 (home);
     line-1 colours (2.1); sub_17190; palcount = $64
  sub_F87D2 unless a showcase card is up (word_FFD42E bit 0)
sub_F76D4 (L960512), cursor (d0 = row step, signed, in d7 units):
  scroll: going up: if row == top: top -= 1 (min 0); going down: if row - top > 5: top += 1 (twice if needed, max 3)
  d7 += d0 (min 0); if d7 >= 18: d7 -= d0
  Continue Playoffs: skip rows 1-3 (repeat the step); New Playoffs (/7): skip row 3
  sub_F780C: restore the panel under the old box: dobitmap($BEFB8 cols 15-37) at (16,14)
  sub_F7864 (L960693): printy = 14 + 2*(row - top); Framer(23, 3), or Framer(23, 5) when New Playoffs (/7)
     and row == Team 1 (the box covers Team 1 and Team 2, since the bracket fixes Team 2); printa = $6000
```

There are 6 visible rows (y 15, 17, ... 25) and `top` runs 0-3 (`word_FFD422`; `word_FFD424` is the previous top). Screenshots:
- `s01_setup_default.png`;
- `nav_down_0..8.png` (scrolling);
- `po_team1_cursor.png` (the 23x5 box);
- `so_menu_bottom2.png` (Shootout: the cursor stops at Goalies).

### 2.4 Input (`GameSetUp_2` L962336, dispatch in `GameSetUp` L960236-960490)

```
GameSetUp_2: d6 = $5460
  each frame (vcount change): ReadJoy1 + sub_11318 (auto-repeat: first repeat after 16 frames, then every 5)
     d1 != 0: if not C: return d1; C: (C held -> word_FFD43C = $53) word_FFD42E bit 5 = 1
     same for ReadJoy2 (and ReadJoy3/4 with FourWayPlay)
     (redraw a logo if a team change left word_FFD42E bit 6/7 pending)
     if d6 > $4650 or showcase running (bit 0): sub_F87EA (showcase step) else sub_F87D2
  dbf d6 -> after $5460 frames: return d1 = 0
GameSetUp loop (loc_F7464 L960236):
  Shootout: OptLine = 1, OptPen = 0, OptUserRec = 1
  d1 = GameSetUp_2()
  d1 == 0       -> loc_F8418 demo (2.10)
  bit 7 Start   -> loc_F843E start (2.8)
  bit 1 down    -> d0 = +2 rows... (skip rules below); sub_F76D4(d0); sub_F78A2
  bit 0 up      -> d0 = -2 ... ;                      sub_F76D4(d0); sub_F78A2
  bit 3 right   -> d2 = +1; bit 2 left -> d2 = -1:
        if not Shootout: FigureJoy (pads for the current options)
        GameSetUp_3(d7, d2); Regular Season/Shootout: HomeTeam = Opt1Team, VisTeam = Opt2Team
        redraw the home logo (sub_F85B0) and/or visitor logo (sub_F8608) if that team changed; sub_F78A2
  A, B          -> nothing
```

**Skip rules** for up/down (L960249-960345):
- **Down from Per. Length (row 4):**
  - Players = Demo: skip 2 rows (no Goalies).
  - Players = Demo and not Shootout: skip 3 rows (no Goalies, no User Records).
- **Down from Team 2 (row 3) in Shootout:** skip Per. Length, or don't move when Players = Demo.
- **Down from Goalies (row 5):**
  - Shootout: stop.
  - Otherwise, when `ValidSRAM < 0`, skip User Records.
- **Up:** the same rules mirrored.

There is no "back". Every pad (1, 2, and 3-4 with 4 Way Play) drives the menu. **C** only speeds up the player showcase (2.7).

### 2.5 Changing a value (`GameSetUp_3` L960788)

```
d7 = 0 (Play Mode) and d2 != 0: entering mode 4 saves User Records/Penalties/Line Changes; leaving restores them
d4 = count (unk_F791E / unk_F7930), d3 = value
New Playoffs (2-3) and d7 = 4 (Team 1): d4 = $1A
d7 = 2 (Players): Shootout skip rule; ranges by mode (2.2); FourWayPlay ranges
value = sub_F7B0A(d3 + d2, d5, d4)                       ; wrap
4 Way Play, Players: playoffs skip 9-10
store; if d2 != 0:
   Continue Playoffs and d7 = 0: sub_17CA0 (L54859, load the playoff tree); if gamelevel|bosgames == 0
        (no playoff in progress) step again (so Continue Playoffs is skipped)
   New Playoffs (/7) and (d7 = 0 or d7 = 4): j_NewPO (NewPO L54901): a new random bracket; Team 2 =
        Team 1's first-round opponent (every Team 1 change re-draws it: emulator, Team 2 changed each press)
```

### 2.6 Logos and plates (`sub_F85B0` L962531 home, `sub_F8608` L962557 visitor)

```
sub_F84FC (L962482): if a showcase card is up (word_FFD42E bit 0): clear it, erase the card area
   (8x8 at (3,5) or (28,5) and 25x8 at (11,5) or (3,5))
draw the logo frame (sub_F8770 home: tiles word_FFD436 at (24,5); sub_F878C visitor: word_FFD438 at (8,5))
   = dobitmap($BF702, 8x8, word_FFB028/2A = x, 5)
loc_F865C (L962590): word_FFD440 = $B4 (showcase delay); printy = 6
   logo $F86F2[team] (6x6) at (25,6) tiles word_FFD430 (home, palette $FF462+32*team -> line 1, mask 2)
                      or (9,6) tiles word_FFD432 (visitor, -> line 2, mask 4); palcount = $64
```

A team change redraws instantly; there is no animation (`tchg_*.png`).

### 2.7 Player showcase (`sub_F87EA` L962807, `sub_F8868` L962842)

This is an attract feature of the menu (`idle_*.png`, `m_idle_*.png`).
- **Start:** `word_FFD440` counts down from `$B4` (180 frames) after the logos are drawn. When it runs out, word_FFD42E bit 0 = 1 (showcase on).
- **Cards:** every `$AA` frames (`$53` while C was pressed) a card replaces the logos. The side alternates (bit 1 toggles; the visitor goes first).
- **Visitor card:**
  - `word_FFD43E` += 1, wrapping 6 → 0, so the first cycle shows list entries 1, 2, 3, 4, 5, 0;
  - frame (`word_FFD438`) at (3,5), photo at (4,6);
  - Framer 25x8 at (11,5), attribute `$6000`;
  - name at (12,6).
- **Home card:** same index; frame (`word_FFD436`) at (28,5), photo at (29,6), Framer at (3,5), name at (4,6).
- **Photo:** the team's photo list `$F92F4` entry k (`{photo, roster slot}`, `../menus/photos.json`). It is decoded by `sub_FE98A` and drawn with the `$C63F8` palette on line 1, mask 2.
- **Name:** "NN First Last" (`d0toascii` + `appstring`), printed with `print2` in the alternate font.
- **SRAM records:** with `ValidSRAM ≥ 0` and saved records, up to 3 record lines follow the name (`sub_F98C6`, `sub_F9A64`, `sub_F9AAC`).
- **When it runs:** the showcase steps only during the first `$E10` frames (60 s) after the last press, or while a card is up. A team change ends it (§2.6).

### 2.8 Start (`loc_F843E` L962423)

```
word_FFD05A = word_FFD05C = OptGoalie                 ; pad 1 / pad 2 goalie control (1 = auto)
sub_17AC8 (L54579): playoffs: pojoy = 7 - OptNOP (11 - OptNOP with 4 Way Play)
RNGseed from the HV counter (twice)
TmpOptLine2 = OptLine; OptLine == 2 (Auto): OptLine = 0, byte_FFC2FC bit 4 (no fatigue, CPU line changes)
TempOptPlayMode = OptPlayMode; Shootout: OptPlayMode = 0, word_FFC2FA bit 0, sub_FC47C (L968789, shootout init)
jmp MakeTree (L54939): playoff tree; FigureJoy (pads, 2.9); sub_18002 (L55173): 8 other games of 16
     distinct random teams, none of them HomeTeam/VisTeam (this answers ui_menus.md U1)
```

`GameSetUp` starts by restoring `OptLine = TmpOptLine2` and `OptPlayMode = TempOptPlayMode` (L960190-960191). So after a game, the menu shows "Auto" and "Shootout" again.

### 2.9 Players → pads (`FigureJoy` L55005)

Teams: 1 = home (Team 1), 2 = visitor (Team 2), 0 = CPU. `_noplist` (L55157), OptNOP → (cont1team, cont2team):

| OptNOP | String | pad 1 | pad 2 | pads 3/4 (4 Way Play) |
|---|---|---|---|---|
| 0 | Demo | 0 | 0 | |
| 1 | One - Home | 1 | 0 | |
| 2 | One - Visitor | 2 | 0 | |
| 3 | Two - Teammates | 1 | 1 | |
| 4 | Two - Head to Head | 1 | 2 | |
| 5 | Three (4 Way) | 1 | 2 | pad 3 = 1, pad 4 = 0 |
| 6 | Four (4 Way) | 1 | 2 | pad 3 = 1, pad 4 = 2 |

**Playoffs** (`OptPlayMode != 0` and not Shootout):
- Find the user's team (`potree[potreeteam]`) in this round's `gsstruct`. Home in the pairing → `d0 = 0`; visitor → `d0 = 4` (5 with 4 Way Play).
- Set Opt1Team/Opt2Team and HomeTeam/VisTeam from the pairing.
- `idx = d0 + pojoy`. Read the pads from `_pojoylist` (L55091) `[(1,0) (1,1) (1,2) (2,1) (2,0) (2,2) (2,1) (1,2)]`, or `_pojoylist2` with 4 Way Play.
- So "One" means pad 1 plays the user's team, home or away.

### 2.10 Demo

- **Idle:** `GameSetUp_2` returns 0 after `$5460` frames with no press (21,500 frames from the last press on the emulator).
- **`loc_F8418` (L962415):**
  - demoflag = 0;
  - RNG seed;
  - OptPlayMode = 0, OptNOP = 0 (CPU vs CPU), OptLine = 0 (On), **OptPen = 1 (On)**;
  - then the normal start. The demo game uses the teams on screen.
- **Matchups in Players = Demo:** the screen ends by itself 480 frames after its script (2022 frames on the emulator).
- **In play, `demoread` (L30159):** Start opens the pause menu. Any other new press goes to `loc_172E4` → Game Setup.
- **Back in GameSetUp:** while demoflag == 0, Opt1Team and Opt2Team are re-rolled with `randomd0($1C)` (0-27; both can be the same team) and demoflag is set again (L960200-960209). This was seen on the emulator: Washington at Detroit (`demo_exit_setup.png`).

---

## 3. Name Entry (User Records, `sub_FBB88` L967859 → `loc_FB018` L966782)

This screen runs only when OptUserRec = 0 (On):
- once for `cont1team`;
- once more for `cont2team` when it is set and differs from `cont1team`.

**Layout** (H40, SPORTS background):
- "NAME ENTRY" big title;
- a "Name Log" list with arrows;
- the team logo and city;
- a help box: "D-Pad up/down to move arrows. Press START to select name. Press B to edit."

**Edit mode** (B): an A-Z / `. 1 2` letter grid with "Enter new name:" and the help text "D-Pad to a letter. C to select letter. A to go back. B to cancel. START when done."

Matchups then greets the user ("Welcome …", the `#`/`%` tokens). The records live in SRAM (`sub_F9C68` loads `$FFD45A` from SRAM `$DA0`).

Shots: `ur_*.png`, `m_ur.png`, `m_ur2.png`, `m_ur3.png`. **Port: not applicable** (no SRAM user records). The layout is not decoded further (UNRESOLVED F4).

## 4. Playoff bracket (`PlayoffScreen` L53888)

The routine returns at once when OptPlayMode = 0. It runs:
- before Matchups;
- after a playoff game (`GameOver`).

**Layout** (H40):
- SPORTS background on plane B (`printa $6000`);
- the 16 team plates in a bracket with the Stanley Cup (`$F3098`) in the middle;
- a heading by `gamelevel`: `unk_176DE` (L54190) "Playoffs", "Quarterfinals", "Semifinals", "Finals", "Champions";
- "Press [ or ] to page" for later rounds.

**Behaviour:**
- Song `$79`.
- The user's plate flashes: `word_FFBD6A ^= $EE` every `$18` frames (`sub_175D8` L54095).
- `sub_17542` (L54037): **Start held** on pad 1 or 2 leaves; right/left scroll by `$70` px per round, up to `gamelevel`.

Shots: `po_*.png`, `m_po_0.png`, `m_po_1.png`. **Port: not applicable** (no playoffs). The art was not exported (F5).

---

## 5. Matchups (`sub_FCC76` L969615)

### 5.1 Setup

```
sub_F9C68 (SRAM records), sub_F71A2 (hot/cold picks, 5.4), word_FFD5A4 = 0, song $7A, vbint loc_15E4C
clearTeamStats; Create_HotCold_Table(home), (visitor)          ; the game's form table is made here
sub_F71A2 again; H40; Map1col1 = Map2col1 = 6; setvram
tiles: word_FFD430 = 2 (home picture, 36), word_FFD432 = $26 (visitor picture, 36)
   word_FFB010 = $4A: $A9A18 bigfont through 05 43 15 67 79 AB CD EF
   sub_11F04: $AAC5A raw -> word_FFB012 ($CE, font 0)
   word_FFB014 = $12C: $AAC5A through 0A 23 45 67 89 AB CD EF (font 1: ink -> colour 10)
   framercset = $18A: $55B86 through 05 42 25 61 89 AB CD EF
printz plane B (0,0); dobitmap($54E24 SPORTS, 40x28, mask 3 = lines 0-1)
sub_11DE2 (printbig) plane A attr $4000 (12,13) "MATCHUPS"
printz plane A (16,17) attr 0 "ADVANTAGE:"
plane B attr $4000: Framer(33,9) at (6,3); Framer(8,8) at (1,14); Framer(8,8) at (31,14)
plane A (1,1): dobitmap($B389C Ron Barr, 8x9, mask $C = lines 2-3)
HOT tiles $F5AFE -> word_FFDEE4, COLD $F5D24 -> word_FFDEE6
page = 0 (word_FFD598); word_FFD5A8 = $10D; sub_FD46C, sub_FD084, sub_FD1FE; palcount = $18
script (5.3): sub_17718; word list at $FFD5B8; word_FFD5B6 = $7FFF; dword_FFDEEC = $8CA0
```

**Layout** (H40). The coordinates were checked on the emulator (`mu_pg0..6.png`; the plane probe is in §13).

| Plane | Cells | What |
|---|---|---|
| B | 40x28 | `../menus/stats_bg_idx.png` (palette `$54E24` lines 0-1) |
| B | (6,3) 33x9 | text box, `framer_matchups_idx.png`, attribute `$4000` → map line 1 + 2 = line 3 |
| B | (1,14), (31,14) 8x8 | picture frames, same |
| A | (1,1) 8x9 | `ron_barr_idx.png` (line 3) |
| A | (9,4) 29x7 | commentary, font 0 (`../menus/font_stats_idx.png`, cyan `$EE2` = line 0 colour 1) |
| A | (12,13) 16x2 | `matchups_title_idx.png` (printbig, map line 1 + `$4000` → line 3) |
| A | (16,17) | "ADVANTAGE:", font 0 |
| A | (13,19) 16 | page label, font 1 (yellow `$0EE`) |
| A | (2,15) 6x6 | visitor picture: page 0 logo (palette → line 2, XOR `$6000`), pages 1-6 photo (photo palette → line 1) |
| A | (32,15) 6x6 | home picture: page 0 logo (line 1), pages 1-6 photo (line 1, no palette load) |
| A | (4,22), (34,22) | visitor / home rating, 2 digits, font 1 |
| A | (19,22) | 3 arrow cells, font 1 |
| A | row 23 | names, font 0: visitor at x 0; home at x 35, moved left so it ends by column 39 (`sub_FD89A` L970971); cleared on page 0 |
| A | (2,25), (32,25) | HOT (6x2) / COLD (6x3) badge or blank 8x3 (`sub_FF8DE` L976589) |

**CRAM:**
- line 0 = `$54E24` line 0;
- line 1 = the home logo palette (page 0), or the photo palette (pages 1-6);
- line 2 = the visitor logo palette (page 0). It overwrites Barr's line 2, which nothing uses.
- line 3 = the Barr palette (`$B389C` line 3). The title, the frames and the badges also use it.

### 5.2 Pages (`word_FFD598` 0-6)

| Page | Label | Pictures | Ratings |
|---|---|---|---|
| 0 | "Overall" (`unk_FCFF6` list + 4 at `$FCFFA`, entry 9; the 9 others — Shooting, Skating, Passing, Defense, Checking, Fighting, Goalkeeping, Power Play Adv., Home Team Adv. — are never printed) | team logos | `sub_FE172` (L973162): `$FE18E[team]` (LA 74, MTL 73) |
| 1 | center | photos of the starting line's player | player Overall |
| 2 | left forward | | |
| 3 | right forward | | |
| 4 | left defenseman | | |
| 5 | right defenseman | | |
| 6 | goalie | | |

- `sub_FD492` (L970410): page k uses byte `unk_FD4B8[k]` = `0 4 3 5 1 2 0` of the team's starting line (team record + word 6: G LD RD LW C RW), and roster slot = byte − 1. Labels are at `unk_FD400` (L970286).
- Player rating (`sub_FD1FE` L970128) = `CalcAttrib` with the Overall weights (`dword_19420` for skaters, `dword_19582` for goalies) × 100 / d1, then `AttribAdjust`. It includes the form table, so it changes from game to game.
- The photo comes from `sub_FAE26`, the same lookup as Player Cards (`../menus/photos.json`).

**Arrows** (`sub_FD4CA` L970443):
- `word_FFD5A6` counts 7 frames; then `word_FFD5A4` += 1, capped at 5.
- Strings: `unk_FD548` when home > visitor (`"   " "]  " "]] " "]]]" …`), `unk_FD560` when visitor > home (`"   " "  [" " [[" "[[["…`), `unk_FD5A8` "   " when equal.
- `]` and `[` are the right and left arrow glyphs. The arrows grow 0 → 3 and point to the better side.
- A page change resets the animation (`sub_FD4C0`).

### 5.3 Commentary (`sub_17718` L54250, `sub_17730` L54260)

**Script** (word list at `$FFD5B8`):
`$1B, $1D, $1A, $1D, [$22 or $23, $1D], $1E, $1D, [$1F if HomeTeam != VisTeam], $1D, $20, $1D, $21, -1`.

**Messages:** `unk_4B5C0` (L261838), CR-separated, index n = the n-th CR (`frontend.json` `matchups.script.messages`):

| # | Text |
|---|---|
| `$1A` | "Welcome to a sold out ^.  Tonight's National Hockey League game features the + *% and _ =#." |
| `$1B` | "Hi, I'm Ron Barr for EA Sports." |
| `$1C` | "And in goal tonight, [ for { and ] for }." (not in the script) |
| `$1D` | "" (blank line) |
| `$1E` | "For { < is on a hot streak, but \| is off his game." |
| `$1F` | "For } > is on a hot streak, but \ is off his game." |
| `$20` | "The ^ crowd record is @ dB." |
| `$21` | "Hit the start button to begin.  Use the A and C buttons to cycle through matchups." |
| `$22` / `$23` | "Lately $ has been playing well." / "… extremely well." |

**Tokens:**

| Token | Meaning |
|---|---|
| `^` / `;` | home / visitor arena (team string 4, `sub_FD5F4`) |
| `_`, `{` | home city |
| `+`, `}` | visitor city |
| `=` / `*` | home / visitor nickname (string 3, `sub_FD5AE`); "Home" / "Visitors" when empty (All-Stars) |
| `#` / `%` | user names (User Records) |
| `[` / `]` | home / visitor starting goalie |
| `<` / `>` | home / visitor hot player |
| `\|` / `\` | home / visitor cold player |
| `@` | home arena crowd record in dB (SRAM; `$50` = 80 when 0) |
| `$` | the team with the better form |

The team strings are city, abbreviation, nickname, arena: `TeamData.city/abbreviation/team_name/arena_name`.

**Typewriter:**
- One word appears every 10 frames, with +40 frames after a `,` or `.`.
- Lines wrap at column 29 (x 9..37).
- After 7 lines (rows 4-10) the box scrolls up one row (`sub_179D2`).
- Down held (`asv`) skips the delays.
- At the end, `word_FFD5B6 = $1E0`.

**$F7318** (L960137; the listing labels it `EASportsScreen`, wrongly):
- `d = Σ form(visitor) − Σ form(home)`;
- |d| ≥ `$BD` → message `$23`;
- |d| ≥ `$5E` → message `$22`;
- `$` = home if `d < 0`, else visitor.

### 5.4 Hot and cold (`sub_F71A2` L959993, `sub_F71F0` L960015)

- For each of the 6 starters, form = the sum of his form bytes 3..15 (of 16), skipping bytes 9 and 13.
- The list is bubble-sorted, highest first.
- The hot player is the first; the cold player is the last.
- The HOT or COLD badge appears under a page's player when he is his team's hot or cold player.

### 5.5 Input and timing (loop `loc_FCEC2` L969754)

| Input / event | Effect |
|---|---|
| Start (new press) | leave → `StartGame`. With A+C held: OptPerlen = 3 (30 s periods; `cheat30.png` shows "0 : 30"). |
| C | next page (`sub_FCF86` L969813, wraps 6 → 0) |
| A | previous page |
| no input for `$10E` (270) frames | next page |
| A or C | also resets the 270-frame page timer and the long timeout |
| script end | 480 frames, then: Players = Demo → leave; otherwise wait (`dword_FFDEEC` × 65536 frames, effectively forever) |

---

## 6. Shootout entry flow

1. **Play Mode = Shootout:**
   - Per. Length shows N/A and the cursor skips it;
   - Penalties Off, Line Changes Off, User Records Off;
   - the cursor stops at Goalies;
   - Players offers 0-4 without Two - Teammates.
2. **Start:**
   - OptPlayMode = 0;
   - `word_FFC2FA` bit 0;
   - `sub_FC47C` (L968789: shooter lists, ui_menus.md §13.3).
3. No Matchups.
4. `StartGame` makes the form tables. The intermission shows the shootout menu "Start Shootout / Shootout SetUp / Team Roster / Player Cards / Record Holders" (`so_*.png`, `m_so.png`; ui_menus.md §3).

The port already does this (`scenes/game.gd`: `f_c2fa |= C2FA_SHOOTOUT`, `init_shootout`).

## 7. Playoff entry flow

1. **New Playoffs / New Playoffs/7 game:**
   - `NewPO` draws a random 16-team bracket; Team 1 = the user's team; Team 2 = the opponent (fixed, skipped by the cursor).
   - Players: Two - Head to Head / Two - Teammates / One.
   - The cursor box spans Team 1 + Team 2.
2. **Continue Playoffs:** selectable only when a playoff is in progress (SRAM).
3. **Start:** MakeTree, then the bracket (§4), then Matchups.
4. **After each game:** `GameOver` → Playoff Stats → bracket → Game Setup.

**Port: not applicable.**

## 8. Exit Game

At the final intermission ("Exit Game" row 0, or Start; ui_menus.md §1.3):
1. `GameOver` (L53851): `sub_180FC`; playoffs: Playoff Stats; `PlayoffScreen`.
2. `loc_172E4`: `song($78)`.
3. `Opening2` → `GameSetUp`.

The setup screen comes back with the same settings: OptLine and OptPlayMode are restored (§2.8), and the teams are kept. The title is not shown again. Emulator: `m_exit.png` goes from the final intermission (LA 10 – MTL 6) to Game Setup with "5 Minutes" and "Line Changes Auto" kept. The showcase then starts after 180 frames.

---

## 9. Data mapping to the port

`godot/core/match_config.gd` (MatchConfig), `logic/hockey_world.gd` (`opt_*`), `logic/game_rules.gd`, `scenes/game.gd` `_ready`:

| Retail | Values | Port |
|---|---|---|
| OptPlayMode | 0 Regular Season, 4 Shootout (1-3 playoffs) | `MatchConfig.shootout` (true = 4); `GameRules.opt_play_mode` stays 0 (retail clears it at start and uses `word_FFC2FA` bit 0 = `HockeyWorld.f_c2fa C2FA_SHOOTOUT`). Playoffs: n/a |
| OptNOP | §2.9 table | `HockeyWorld.cont_team[0..1]` = (cont1team, cont2team). MatchConfig's `home_control/away_control` can express Demo (CPU, CPU), One - Home (PAD1, CPU), One - Visitor (CPU, PAD1), Two - Head to Head (PAD1, PAD2), but **not Two - Teammates** (`cont_team = [1, 1]`). Add a field for it (§10). |
| Opt1Team / Opt2Team | ROM ids 0-27 | `MatchConfig.home_team` / `away_team` = `available_teams()` entry with `team_index` = id (Team 1 is always home outside playoffs) |
| OptPerLen | 0 5 min, 1 10 min, 2 20 min, 3 30 s | `HockeyWorld.opt_perlen` (TIMETAB `[300, 600, 1200, 30]` already in `roster_logic.gd`). MatchConfig only has `period_minutes` 5/10/20, and the 30 s cheat needs `opt_perlen` = 3. |
| OptGoalie | 0 Manual, 1 Auto | `MatchConfig.auto_goalie` → `HockeyWorld.auto_goalie[0..1]` (`word_FFD05A/5C`) |
| OptUserRec | 0 On, 1 Off | n/a (SRAM) |
| OptPen | 0 Off, 1 On, 2 On except offsides | `MatchConfig.penalties = OptPen != 0`, `offsides = OptPen == 1` → `opt_pen`, `opt_offsides` (`StartGame` sets `gmode` bit 5 only for 1) |
| OptLine | 0 On, 1 Off, 2 Auto | `line_changes = OptLine != 1`, `auto_lines = OptLine == 2` → `opt_line_on`, `no_fatigue` (`byte_FFC2FC` bit 4) |
| — | | `MatchConfig.edition` / `fighting` are port extras (the fight patch's option rows are not in retail '94) |
| Matchups form | `Create_HotCold_Table` at Matchups | `RosterLogic` already makes `TeamStats.hotcold`; the Matchups page must read it after it is made |

## 10. Port checklist

**Port status (2026-10-16).** Both screens are built from the exported art: `ui/game_setup.gd` and `ui/matchups.gd`. The Game Setup default screen, a showcase card and Matchups page 0 match the emulator shots pixel for pixel; the only difference is the colour scale (the port maps 3-bit CRAM to 255/7 steps, the emulator to 36).
- Flow: title → Game Setup → Matchups (not in Shootout) → game. "Exit Game" and the demo exit return to Game Setup with the options kept (`Sim.options`).
- Music: `Sim.menu_sfx` carries `$78` from the title into Game Setup; Matchups plays `$7A`.
- Players uses the 4 Way Play list (the port always has pads 3 and 4), mapped through `MatchConfig.players` / `NOPLIST`.
- Matchups makes the game's form table (`RosterLogic.make_form`), which `MatchConfig.form` hands to `new_game_form`. Its ratings use `PlayerData.overall(form)`.
- The A + C + Start cheat sets `MatchConfig.perlen = 3`.
- The demo follows retail: Penalties On, Line Changes On, the teams on screen, re-rolled on the way back.
- Since done: the playoff modes (Play Mode 1-3, `ui/playoff_screen.gd`), User Records with Name Entry (`ui/name_entry.gd`), and the showcase's SRAM record lines (`sub_F98C6` / `sub_F9A64` / `sub_F9AAC`).
- Palette fades (`ui/cram_fade.gd`, `shaders/cram_fade.gdshader`): every screen change runs setvram's fade to black (`palcount = $18`, 25 VBlanks, the screen frozen), and the next screen fades in over 24 VBlanks while it already runs. The fade is `cramfade` as a post-process: each component of every CRAM colour steps one level at a time, red, green and blue in turn. Applies to title → Game Setup → Name Entry / bracket / Matchups → game, and Exit Game back.
- Port-only: B opens a box with the edition (retail or the fight patch) and the patch's Fighting option.

The original port plan follows, kept for reference. Its "skip the playoffs" and "drop Three/Four" steps were superseded once the playoffs and 4 Way Play were ported.

1. **Flow.** Replace `ui/setup_screen.tscn` with a retail **GameSetup** scene, then a **Matchups** scene:
   - flow: title → GameSetup → (Shootout ? skip : Matchups) → game;
   - "Exit Game" → GameSetup (not the title), keeping the MatchConfig;
   - both screens are H40 (320x224; `ScreenMode`); the game switches to H32 as now.
2. **GameSetup layers** (§2.1 table):
   - background plane B;
   - header, plates, frames, logos, panel on plane A;
   - text with `font_setup_idx.png` and `fonts.setup.chars`;
   - palette lines as in §2.1, with line 1 colours 1-5 from `teams[].colours` (`frontend.json`).
3. **Rows and values** from `frontend.json` `setup.rows` / `value_lists`. Implement:
   - per-mode ranges with wrap-around;
   - forced values (Shootout, Demo);
   - skip rules;
   - the 6-row window with `{`/`}` arrows;
   - the 23x3 cursor box;
   - auto-repeat 16/5 frames.
   - Use the **retail defaults** (10 Minutes, Penalties Off, Line Changes Off, Manual goalie, Montreal vs Los Angeles), unless the project prefers its current ones.
4. **Players row** (§2.9). Extend MatchConfig to carry `cont_team` per pad, or a `players` enum. `scenes/game.gd` `_take_pad` cannot express Two - Teammates today. Drop Three/Four (no 4 Way Play), and the playoff values.
5. **Play Mode:** offer Regular Season and Shootout only. Continue/New Playoffs need the bracket and the playoff tree, which the port does not have. Keep `Shootout` → `MatchConfig.shootout`.
6. **Per. Length:** 5/10/20 min. Optional: honour the A+C+Start cheat on the Matchups screen (`opt_perlen = 3`, 30 s), which needs a MatchConfig field.
7. **User Records:** show the row as retail does (On/Off) but treat it as Off, or hide it. Retail's cursor skips it only when SRAM is invalid, so with fresh SRAM it is reachable. No Name Entry.
8. **Showcase** (§2.7, optional attract):
   - 180 frames after a logo draw, alternate visitor/home cards every 170 frames;
   - use `../menus/photos.json` entries 1..5,0 and the "NN First Last" name;
   - leave out the SRAM record lines.
9. **Demo** (§2.10). The current `setup_screen.gd` `_demo` differs from retail:
   - retail forces Penalties On and Line Changes On;
   - it uses the teams on screen, and re-rolls them only on the way back from a demo;
   - any non-Start press during a CPU-only game returns to GameSetup.
10. **Matchups:**
    - layers (§5.1), 7 pages (§5.2), arrows, HOT/COLD (§5.4);
    - the commentary script with tokens from TeamData (`city`, `team_name`, `arena_name`, goalie from the starting line, hot/cold from `TeamStats.hotcold`). The crowd record is a constant 80 dB without SRAM (`GameRules.crowd_record_value`).
    - Controls: C/A pages, Start begins, auto page every 270 frames. Demo: leave 480 frames after the script.
    - Music `$7A` (`audio`), then `$79` at the intermission.
11. **Music:** `$78` continues from the title into GameSetup; `GameOver` restarts `$78`.
12. **Port extras** (edition, fighting, starting line choice) have no retail row. Keep them on a separate port-only page, or behind a key, so the retail screen stays clean.

## 11. Exported assets (`tools/extract/ui_frontend.py` → `godot/assets/ui/frontend/`)

| File | Content |
|---|---|
| `frontend.json` | flow; `setup` (routines, VRAM map, layers, rows with RAM/default/count, value lists incl. 4-way and unused entries, special strings, `_noplist`/`_pojoylist`/`_pojoylist2`, controls, skip rules, showcase, palette composition); `matchups` (routines, layers, pages/labels/slot bytes, arrows, script order, messages `$1A-$23`, tokens, controls, form rule); `playoffs` (headings, hint); `name_entry`; `fonts` (setup char map); `framers`; `images`; `teams` (id, city, abbr, nickname, arena, rating `$FE18E`, the two colour lines of `unk_F8BF4`) |
| `setup_bg_idx.png` | `$4B7A0` 320x224 opaque |
| `setup_header_idx.png` | `$4DEEE` 40x4 cells |
| `setup_panel_idx.png` | `$BEFB8` 38x13 |
| `setup_framer_idx.png` | Framer 3x3 over `$BF54A` (remap 03 56 75 64…), map line 1 (+ `$6000` → line 0) |
| `font_setup_idx.png` | `$BE26A` 94 tiles, 16 a row, line 0 |
| `logo_frame_home_idx.png` / `logo_frame_visitor_idx.png` | `$BF702` 8x8, raw / remap 03 41 45 67… |
| `team_plates_home_idx.png` / `team_plates_visitor_idx.png` | `$AFE12` 11x56 cells (row 2t = team t), raw / remap 03 41 25 67…, line 1 |
| `ron_barr_idx.png` | `$B389C` 8x9, line 3 (palette in `images`) |
| `matchups_title_idx.png` | "MATCHUPS" printbig with `$A9A10` through 05 43 15 67 79…, map line 1 (+ `$4000` → 3) |
| `font_matchups_alt_idx.png` | `$AAC5A` through 0A 23 45 67… (font 1; map = `../menus/font.json`) |
| `framer_matchups_idx.png` | Framer over `$55B86` through 05 42 25 61…, map line 1 (+ `$4000` → 3) |
| `hot_idx.png` / `cold_idx.png` | `$F5AF6` 6x2 / `$F5D1C` 6x3 (palette line 3 in `images`) |

Reused from `../menus/`:
- `team_logos_idx.png` + `palettes.json team_logos`;
- `photos_idx.png` + `photos.json`;
- `stats_bg_idx.png` (Matchups background; Matchups loads `$54E24` lines 0-1);
- `font_stats_idx.png` + `font.json` (Matchups font 0).

The run is deterministic (same bytes on a re-run). `--preview DIR` writes `preview_setup.png` and `preview_matchups.png`.

## 12. Notes for implementers

- Plane overlap matters in two places:
  - **Matchups:** the frames are on plane B, the same plane as the background. Their transparent edge pixels show the **backdrop** (`$400`), not the background.
  - **Setup:** the cursor box and the values share plane A cells. The value text overwrites the box's middle row, and the box's centre tile at x 37 shows the panel below.
- Framer and printbig **add** the attribute to the map word (line 1 + 3 = 0 with priority; line 1 + 2 = 3). `dobitmap` **XORs** `printa & $F800` into the map word.

## 13. Emulator evidence (`/tmp/claude-0/-home-user/ef020377-92e3-57ff-8519-5d51b4a7df4d/scratchpad/fe/`)

| Files | What |
|---|---|
| `overview_1_setup.png` | default menu, scrolled bottom with a showcase card, home card, New Playoffs 23x5 box, Shootout bottom |
| `overview_2_matchups.png`, `overview_2b_matchups.png`, `mu_pg0..6.png` | the 7 Matchups pages (LA at MTL) |
| `overview_3_other.png` | Name Entry, its edit mode, playoff bracket, pre-game intermission |
| `overview_4_exit.png` | final intermission → Game Setup after Exit Game; 30 s cheat (0:30 clock); Game Setup after leaving a demo (random teams) |
| `s01_setup_default.*`, `nav_down_*.*`, `pm_*.*` | menu text dumps (`.txt`) and shots |
| `m_idle_*.png`, `idle_*.png` | showcase timeline (every 30 frames) |
| `m_start_*.png`, `mu_*.png`, `m_mu_*.png` | Matchups typewriter timeline |
| `ur_*.png`, `m_ur*.png` | Name Entry |
| `po_*.png`, `m_po_*.png` | bracket; `po_team1_cursor*.png` |
| `so_*.png`, `m_so.png` | Shootout menu and entry |
| `exit_*.png`, `m_exit.png` | Exit Game |
| `demo_*.png`, `m_demo.png` | demo |
| `prev/preview_setup.png`, `prev/preview_matchups.png`, `cmp_setup.png`, `cmp_mu.png` | extractor previews vs emulator |
| `fe.py`, `probe.py`, `hh.py`, `a*.py`, `st_*.pkl` | wrapper, plane/tile probe, disassembly helper, the navigation scripts and save states |

## 14. UNRESOLVED

- **F1.** 4 Way Play was not run on the emulator: the harness has no 4 Way Play adapter, so pads 3-4 cannot be read. The Three/Four rows, the playoff 9-10 skip and `_pojoylist2` come from the code only.
- **F2.** Continue Playoffs (SRAM playoff state, `sub_17CA0`/`sub_1803E`) was not exercised. With fresh SRAM it is always skipped.
- **F3.** The showcase's SRAM record lines (`sub_F98C6`, `sub_F9A64`, `sub_F9AAC`) were not decoded. With fresh SRAM none were printed.
- **F4.** Name Entry (`loc_FB018`): the layout, the letter grid, the name-log handling and the SRAM writes were not decoded beyond the screenshots. The port does not need it.
- **F5.** The playoff bracket art (cup `$F3098`, plates `sub_17652`/`sub_17626`, bracket lines from `$B3648`) was not exported. Its exact layout and the scroll limits were not measured. The port does not need it.
- **F6.** The Matchups `@` crowd record reads SRAM block byte 8 (`sub_F9BE2`) and gives `$50` = 80 dB when it is empty. With SRAM records, the value after an arena record was not checked.
- **F7.** `asv` (down held) and the exact typewriter timing (10 frames per word, +40 after `,`/`.`) were read from the code, not measured frame by frame.
