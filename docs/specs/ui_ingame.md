# In-game overlays: score box, clock, referee messages, goal and injury boxes, penalty screen text (retail NHL '94)

Scope: everything the unpatched game prints on the screen planes **during play**. That covers the score box and clock, the power-play banner, the referee's message, the goal / injury / penalty-shot / shootout boxes, the face-off line labels, the line-change menu frame, the text on the sideways penalty screen, the playoff ticker and the "Stars of the Game" box. The pause, intermission and game-over menus and the stats pages are out of scope; another spec covers them. The referee and face-off pictures are already ported (`indicators_and_priority.md`, `faceoffs_offsides.md`); here they appear only where text shares their space.

Sources: `lst/nhl94.bin.lst` (Lnnnnn = listing line), `lst/nhl94.bin` (CRC32 `$9438F5DD`). The listing has no address column and garbles most inline `printz` data. Every inline string, table and immediate below was decoded from the ROM bytes with a capstone disassembly that steps over the inline strings. Lines marked "(garbled)" have no clean listing line, so the nearest one is cited. The extractor `tools/extract/ui_overlay.py` re-decodes all of it. Frame counts are VBlanks (60 Hz). "Loop" = one `DoGameFrame`.

Conventions:
- Cells: retail screen = H32, 32 x 28 cells of 8 x 8 (256 x 224). Cell (c, r) is at retail pixel (8c, 8r). **Port: x = 32 + 8c, y = 8r.**
- Name-table word: bit 15 priority, 14-13 palette line, 12 v-flip, 11 h-flip, 10-0 tile.
- CRAM words are `----BBB-GGG-RRR-`.
- `printa` / `printx` / `printy` / `printm` are the print cursor (`$FFB02C/28/2A/2E`).

Rendered checks (built from the exported files only, see §13), in the session scratchpad: `verify_vertical.png` (score box, team box, goal box, "Icing"), `verify_vertical_pp.png` (power-play banner, bottom line menu, hat trick), `verify_horizontal.png` (penalty screen), `verify_bigfont.png`.

---

## 0. Quick facts

- **In play the window plane is off.** `setvram` writes `$9100/$9200`, and only the pause screen turns it on (`$921C`, L30279). Every in-play overlay is a **plane-A** cell. Plane A is at VRAM `$E000`, 64 x 32 cells (`VmMap1 = $E000`, `Map1col1 = 6`, `setupice` L53031-53032). It is never scrolled, so it is a fixed 32 x 28 overlay. `setupice` fills it with tile `$7FF`, which is transparent (L53045-53048).
- **The sideways penalty screen** (`sflags` bit 7) prints the clock, the period, the team plates, the big goal numbers and the penalty-box lists into **plane B**, the side view (`VmMap2 = $C000`, 64 x 32, with Hscroll = Vscroll = 0). The referee message and the playoff ticker stay on plane A. `SetHor` blanks plane A with `DoFill` (L47128-47130) unless the game is paused.
- **Everything is high priority** (`printa = $8000` from the `$BF` / `$BE` print commands). The palette line comes from `printa` plus the art's own map bits:

| Art | VRAM base word | Upload | Line | Colours |
|---|---|---|---|---|
| print font (`$AAC52`) | `word_FFB012` | `sub_1172C` + remap `43 43 45 67 89 AB CD EF` (L53072-53077) | 0 (`printa` `$8000`) | colour 0 → 4, 1 → 3, 2 → 4. Text = line 0 [3] `$CCC` on line 0 [4] `$000`. **Every glyph cell is opaque black**, including the space. |
| printbig font (`$A9A10`) | `word_FFB010` | `sub_1172C` + remap `71 23 45 67 …` (L53078-53083) | 1 (map `$2000`) | colour 0 → 7 = `$000`. Chrome letters, opaque |
| Framer (`$55B7E`, `framermap`) | `framercset` | `sub_11F12` (L53071 → L45922), raw | 1 (map `$2000`) | outer edge and corner pixels are colour 0 (transparent); the centre tile is colour 7 = `$000` |
| EA logo (`$B3530`) | `word_FFB020` | `sub_16CAC` (L53059 → L53202), remap 0 → 7 | 1 | opaque |
| energy bars (`$AB920`) | `word_FFB016` | L53061-53062, raw | 0/1 (map) | |
| team plates (`$ABA14`) | `word_FFB022` | `sub_16D18` (L53084 → L53256) | 1 (map) | |

  In play the CRAM lines 0-1 are the rink palette (`sub_16C96` L53186, from `$5605A`), and lines 2-3 are the two teams. The overlays use lines 0 and 1 only.

  ```
  line 0: EE8 EEE EEC CCC 000 AAA 666 444 AAC 88E 64C C86 2AC EA8 222 EC8
  line 1: EE8 CCC 888 444 222 08C 06A 000 822 600 042 020 04A 006 66A 246
  ```
- **Fonts:** the small font is the same `$AAC52` font the pad markers use, but uploaded remapped. Its map entries `$12-$14` are the "ST"/"ND"/"RD" ordinal glyphs and `$16-$19` are a 4-cell "Pwr Play" logo. Letter 'O' maps to the digit-0 tile. **printbig** uses a different, larger font: 2 cells tall and 1 or 2 cells wide, at `$A9A10` (§1.4).
- **No crowd meter overlay in play.** `Crowd_Noise?` computes `CurCrowdMeter` but its display block is empty (`_stack` L959742-959746: a push and a pop with nothing between them). The meter only appears on the pause/intermission pages ("Crowd Meter" strings `$19803`…). The only HUD link is `PrintScores1`: if the crowd is loud (`word_FFC2F6` bit 7) it clears that bit and sets `word_FFC304 = $78` (L47142-47144). The port already has this (`GameRules.print_scores1`).
- **Not in retail:** shorthanded / empty-net / breakaway / overtime-goal texts, a "Final" banner in play, "Start to continue" prompts in play, and any blinking. "Breakaway" exists only on the stats pages (`$FE012`).

---

## 1. The print engine

### 1.1 Cursor and planes
`xyVmMap` (L45212): VRAM = `VmMapN + 2*((printy << MapNcol1) + printx)`, where N comes from `printm` (0 = plane A, 4 = plane B, 8 = window). It sets the VDP address, so every routine writes straight to VRAM through the data port.

### 1.2 `printz` / `print` (L45500 / L45521)
`printz` prints the string inline after the `jsr` and returns past it. `print` prints `a1`. String = word length L (counting itself), then L-2 bytes:
- `$00`: ignored. It does not use a cell.
- negative byte b: a command. `v = -b`; `printa = (v << 9) & $F800`; `printm = (v & 3)*4 - 4`; then `printx` = next byte and `printy` = next byte (both signed). So `$BF` = plane A, `$8000`; `$BE` = plane B, `$8000`; `$BD` = window, `$8000`; `$FF` = plane A, attribute 0.
- `'@'`: tile `$7FF` (transparent). `'^'`: skip a cell.
- other c: `fontmap[c] + word_FFB012 + printa`, then `printx += 1`.

### 1.3 `printz2` / `print2` (L45314 / L45336)
Same idea, but the font base is `*(&word_FFB012 + word_FFB030)` (alternate font `$BE26A`/`word_FFBF52` when `word_FFC2F8` bit 3). Its commands are table-driven (`unk_11AF4` L45399). Each takes one argument byte except `$F8`:

| byte | action |
|---|---|
| `$FF` | `printm` from (arg & 3) |
| `$FE` | `printa = (arg & 7) << 13` |
| `$FD` / `$FC` | `printx` / `printy` = arg |
| `$FB` / `$FA` | `printx` / `printy` += signed arg |
| `$F9` | `word_FFB030 = arg*2` (font select) |
| `$F8` | attr, map, x, y |

In play only the face-off line box uses it (§9.1). The period label goes through `sub_13508` → `print2`, but it has no commands.

### 1.4 `printbig` (L45804) and `sub_11DE2` (inline form)
Same commands as `print`. Letters a-z are upper-cased. Each character c (`$20`-`$5B`) looks up the signed byte `v = unk_1916A[c - $20]` (`sub_11E8E` L45864). If v < 0, the glyph is 1 cell wide at map column -v; otherwise it is 2 cells wide at column v. The glyph map is the 77 x 2 map of `$A9A10`. Cell (k, top) = `map[0][col+k]` and cell (k, bottom) = `map[1][col+k]`, each word `+ printa + word_FFB010`. Map words carry line 1 (`$2000`), and 4 cells are h-flipped. The cursor moves by the glyph width. At the end, `printx`/`printy` = the cursor (the last inline command usually moves it to the next text row).
- Characters with entry 0 (`" # $ % & ( ) * + , - / ; < = >`) draw the 'A' glyph.
- `'!'` is a 1-cell glyph (column 73). `'1'`, `'I'`, `' '`, `'`, `.` and `:` are 1 cell wide; `' ' ' . :` are blank. `?` and `@` are 2 blank cells.

### 1.5 `Framer` (L45261)
`Framer(d0 = w, d1 = h)` draws at (`printx`, `printy`). Cell = `framermap[k] + printa + framercset`:

```
row 0      : TL, T x (w-2), TR          ; framermap[0], [1], [2]
rows 1..h-2: L,  C x (w-2), R           ; [3], [4], [5]
row h-1    : BL, B x (w-2), BR          ; [6], [7], [8]
```

On return `printy = y + h` (not restored) and `printx` is unchanged. The centre tile is solid black, so a Framer box is an opaque black panel with a grey bevel. Its outer edge pixels are transparent.

### 1.6 `eraser` (L45234)
`eraser(d0 = w, d1 = h, d2 = word)` fills from (`printx`, `printy`). It ignores `printa`, and `printy` wraps `& $1F`. In play `d2` is always `$7FF` (transparent).

### 1.7 Number and name helpers
- `PushTime` (L45632), d0 = seconds → `"[T][M]:[S][S]"`, 5 characters. T is the tens-of-minutes digit or a space.
- `PushNumber` (L45676): the decimal digits, no padding.
- `DeterStrLength?` (L45704): d0 printed in d1 digits, with leading zeros shown as spaces.
- `d0toascii` (L56370): BCD jersey → 2 characters (tens 0 → space).
- Name forms, from the roster name "First Last" (team pointer `$1E(team)`):

| Routine | Form | Example |
|---|---|---|
| `sub_18B26` (L56269) | jersey, space, text after the first space | `"27 Roenick"` |
| `sub_18AE8` (L56241) | jersey, space, first letter, ". ", rest | `"27 J. Roenick"` |
| `getname` (L56201) | jersey, space, full name | `"27 Jeremy Roenick"` |

- Team strings: `team + word(team+4)` → city, then abbreviation. `PrintScores1`, the PP banner, the line menu and Stars use the **abbreviation**. The shootout intro, the shootout winner and the ticker use the **city**.

---

## 2. Score box (`PrintScores1` L47137)

### 2.1 Vertical (play)
```
PrintScores1:
  if sflags bit7: goto horizontal (2.4)
  if bclr(word_FFC2F6 bit7): word_FFC304 = $78                ; crowd part (0 above)
  printz $BF 0,23 ; Framer(9,5)                                 ; L47145-47157  cols 0-8, rows 23-27
  set disflags bit3                                             ; clock redraw next setvideo
  printz $BF 1,24                                               ; L47159
  if word_FFC2FA bit1 (attempt clock): print2 unk_191F8[4]     ; "  " (blank)
  else:                                print2 unk_191E4[gsp]    ; "1"+ST, "2"+ND, "3"+RD, "OT", " F"
  sub_12D70                                                     ; 2.2: EA logo unless power play
  if sflags3 bit0 (line menu at the bottom): return             ; L47177
  printz $BF 23,23 ; Framer(8,5)                                ; cols 23-30, rows 23-27
  printz $BF 24,26 ; sub_12D0E(home)                            ; L47185-47189
  printz $BF 24,24 ; sub_12D0E(away)                            ; L47190-47194
sub_12D0E(team):   print abbreviation at the cursor ; printx = $1C ; print DeterStrLength(team.$0C goals, 2)
```

Layout (cells):
```
 col: 0 1 2 3 4 5 6 7 8                23 24 25 26 27 28 29 30
 r23  +-----------------+              +-------------------+
 r24  | 1 ST   4 : 3 7  |              |  B  O  S     .  2 |    away
 r25  | E A   l o g o   |              |                   |
 r26  | (7 x 2 bitmap)  |              |  C  H  I     .  3 |    home
 r27  +-----------------+              +-------------------+
```
- Period label: cols 1-2, row 24. Clock: cols 3-7, row 24 (§3). Goals: cols 28-29, right-aligned. Abbreviation: from col 24 (2-3 letters; col 27 stays black panel).
- `unk_191E4` (`$191E4`): `"1\x12"`, `"2\x13"`, `"3\x14"`, `"OT"`, `" F"` (index = gsp 0-4). `unk_191F8` is the same list with `"  "` at index 4.

### 2.2 EA logo / power-play banner
- `sub_12D70` (L47270): `if sflags2 bit5 (power play): return`. Otherwise `dobitmap` of the 7 x 2 map `$B3530` at (1,25), plane A, `printa $8000` XOR the map (`$2000`), so line 1 high priority. It does not upload tiles (`a2 = $30A` points at a zero count word); the tiles were loaded by `sub_16CAC`. Result: the stylised "EA" logo, cols 1-7, rows 25-26.
- `updatepwrplay` (L46991), once per game second (`periodiceevents` L29956, not on the penalty screen, not while the attempt clock runs). It keeps the PP flags (`rules_clock_penalties.md`) and draws:
  ```
  printz $BF 1,25 "   " $16 $17 $18 $19  $BF 1,26 "  "          ; L47024 (string $12AEC)
  print PushTime(CalcPenTime(shorthanded, pp))                    ; cols 3-7, row 26
  print "$BF 1,25" + pp_team.abbreviation                         ; cols 1-3, row 25 (appendz $12B1A)
  ```
  Row 25 = PP team abbreviation (cols 1-3) and the "Pwr Play" logo (cols 4-7). Row 26 = cols 1-2 blank, then the time left `" M:SS"` (cols 3-7). It is redrawn every second. When the power play ends (`_clrpwrplay` L47063): `sub_12D70` puts the EA logo back.

### 2.3 When the score box is drawn or erased
Drawn by `PrintScores1` from:
- `ClrHor` (L47093): unpause and the end of the penalty screen, after erasing all of plane A (`printz $FF 0,0`, `eraser(32,28)`).
- `PauseMode` (L30264) on resume.
- the goal (`checkgoal` L49921).
- CPU line changes (L40152, L41753).
- `lcfound2` (L36825, closing a line menu).
- `sub_12DA6` (penalty screen, §8).

Erased only by `SetHor`'s plane-A fill and by `ClrHor`'s full erase. The bottom line menu covers the team box: `sub_B92E` sets `sflags3` bit 0, so `PrintScores1` skips the team box while that menu is open (§9.2).

### 2.4 Horizontal (penalty screen)
```
printz $BE 17,2 ; s = unk_191F8[ word_FFC2FA bit0 ? 4 : gsp ] ; printx -= s.len/2 ; print s   ; plane B, period, cols 15-16
printz $BE 23,2 ; sub_12D30(home, d0 = 0)
printz $BE 8,2  ; sub_12D30(away, d0 = $2C)
sub_12D30: x0 = printx
           sub_8078(d0): the 11 x 2 plate of RAM map $C334 + d0 at (x0-5, 2)   ; cols 18-28 (home) / 3-13 (away), rows 2-3
           printy = 4 ; n = PushNumber(team.goals)
           printx = x0 - (goals >= 10) - (n.len-2)/2 + 1 ; printbig n          ; rows 4-5
```
- The goals are big digits: col 23 (home) / col 8 (away) for 0-9, and one cell further left from 10 up. Digit '1' is 1 cell wide.
- The plates come from `sub_16D18` (L53256) at `setupice`. For `HomeTeam` (`$C330`) and `AwayTeam` (`$C332`), 22 cells each are copied from the `$ABA14` map (team t = map rows 2t, 2t+1) into VRAM tiles `word_FFB022 + 0..43`. RAM map `$C334` = home, `$C360` = away, with `$8000` added. Each plate is the city in white block letters on a two-stripe band in team colours.

---

## 3. Clock (`showclock` L52289, from `setvideo` every frame)

### 3.1 Vertical (`loc_163BE` L52387-52437)
```
if !bclr(disflags bit3): return             ; redraw only when flagged: the VBlank tick (once per game second), PrintScores1, other setters (L30079, L41292, L42063, L48251, L51790/51810, L55672)
if sflags2 bit3 (instant replay): return
if gsp == 4: return                          ; after the game: the clock is frozen
colon = fontmap[':'] + word_FFB012 | $8000                  ; word_FFBF86
t = (word_FFC2FA bit1) ? word_FFD454 (attempt clock) : gameclock
cells (backwards into $FFBF82..$FFBF8A):
   [4] = digit(t % 10) ; t /= 10
   [3] = digit(t % 6)  ; t /= 6               ; tens of seconds
   [2] = colon
   [1] = digit(t % 10) ; t /= 10              ; minutes
   [0] = t ? digit(t) : fontmap[' ']          ; tens of minutes or blank
DMA 5 words -> plane A row $18 (24), col 3   ; (horizontal: plane B row 5, col 13, never reached)
```
- `digit(d) = fontmap['0'+d] + word_FFB012 | $8000`: the same opaque glyphs as `print`. Cells (3..7, 24) = `" M:SS"` or `"MM:SS"`.
- The attempt clock (penalty shot and shootout, 25 s): `" 0:25"` counting down. The period label shows `"  "` meanwhile (§2.1).

### 3.2 Horizontal (L52292-52331)
```
if word_FFC2FA bit0 (shootout mode): return
printz $BE 13,5                                      ; plane B
d = gameclock / 600 ; if d == 0: printx += 1 else print digit(d)       ; col 13
print digit((gameclock % 600) / 60)                  ; col 14
printx += 2                                          ; cols 15-16: the side view's own colon art
print digit(s / 10) ; print digit(s % 10)            ; cols 17-18
printz $BD 13,5                                      ; cursor reset only (window selected, nothing drawn)
```
It runs every frame (no flag test) and always shows `gameclock`. When the minutes have one digit, cell 13 keeps the side view's art.

### 3.3 Port note
The port shows `w.clock_seconds()` and `shootout.ps_clock` in a Label (`hud.gd` `_refresh`). Retail updates the cells only on the tick, and freezes them during replay and after gsp 4. In practice, drawing every frame looks the same, except during the replay.

---

## 4. Referee message (`SetPA` L46552 → `prefmes` L46669)

```
SetPA(id):  RefPen = id ; if id >= $2E: return        ; penalty-shot variants: no animation, no text
            RefStep = 0 ; prefmes(id)
            if id == $E: loc_1889A (goal box, §5)
            if shootout and word_FFC2FA bit3: sub_FC5AE (winner, §7.3)
            word_FFC3EE = $7FFF ; if horizontal: word_FFC3EE = $3C
            setPA2 …                                   ; referee script (rules_clock_penalties.md)
prefmes(d0):
  if horizontal: goto hor
  if d0 < 0: printz $BF 0,10 ; eraser(13, 3, $7FF) ; return              ; clear (L46676-46683)
  printz $BF 5,10                                                          ; L46685
  s = PenaltyList[d0].text ; n = s.length word (2 + bytes, word-padded)
  if n == 2: return                                                        ; no text (goal, $A, $14)
  printx = max(0, 5 - (n-2)/2)
  w = n - (last byte == 0 ? 1 : 0)
  Framer(w, 3)                                         ; rows 10-12
  printy -= 2 ; printx += 1 ; print s                  ; text row 11, from x+1
hor:
  sub_12828: printz $BF 5,11 + 22 spaces               ; blank cols 5-26 of row 11 (opaque black)
  if d0 < 0: return
  printz $BF 17,11 ; printx -= n/2 ; print s           ; centred on col 17, row 11
```

- **Erased** when the referee script ends: `setPA2` → `PushRef($40)` → `_clearit` → `prefmes(-1)` (L46650-46661). The vertical box therefore lasts exactly as long as the referee animation (the script durations are in `rules_clock_penalties.md` §SetPA). The box sits under the referee window (cols 2-8, rows 2-9); both are centred near col 5.5.
- **Penalty screen name:** `UpdatePA` (L46523-46546) counts `word_FFC3EE` down by d7. On the penalty screen, after 60 VBlanks it blanks row 11 and prints `getname(TempPlOffset)` (`sub_18A6E` L56184: `"12 Mario Lemieux"`) centred on col 17 (L46537-46546). So the screen shows "Slashing" for 1 s, then the penalized player's number and name until the next `SetPA` or the end of the script.
- Quirk: in vertical mode the counter starts at `$7FFF`. After 32767 VBlanks without another `SetPA`, that name line would be printed at (17,11) on the rink.

| id | text (ROM) | where it comes from | vertical box: cols × rows 10-12 | text cols |
|---|---|---|---|---|
| `$02` | Period Over (`$18E4E`) | period end (L30154) | 0-12 | 1-11 |
| `$04` | Game Over (`$18E60`) | game end (L30144) | 0-10 | 1-9 |
| `$06`/`$08`/`$32` | Face Off | out of play (L50135), goalie freezes the puck (L38983, L39048, L39194), stuck puck (L42579) | 1-10 | 2-9 |
| `$0A`, `$0E`, `$14` | (none) | whistle, goal, goalie injury | – | – |
| `$0C` | Icing (`$18E82`) | icing | 2-8 | 3-7 |
| `$10` | Off-side (`$18E92`) | offside | 1-10 | 2-9 |
| `$2C` | Penalty (`$18EC0`) | delayed penalty (`checkfornewpen` L46405) | 1-9 | 2-8 |
| `$12-$2A` | Roughing, Charging, Slashing, Cross Check, Hooking, Tripping, Interference, Holding, Fighting, Fighting *, Fight Instigator | real penalties. In vertical mode the call itself is `SetPA($A)` (no text). The name is shown on the penalty screen at assessment (`InProgress` L46301) | – | centred on col 17, row 11 |
| `$2E-$3C` | penalty-shot variants | `SetPA` returns at once. The text is used by the PS intro (§7.1) | – | – |

All 30 entries (text, delay, minutes, referee script) are in `messages.json` `penalty_list`.

---

## 5. Goal box (`loc_1889A` L55990, from `SetPA($E)`)

```
if BA_PS_flags bit2: set sflags2 bit2
lcfound2(home) ; lcfound2(away)                    ; close both line menus, redraw the score box
r = ScoreSum[last]                                 ; $C46E + $C472: +2 bit7 away, +3 scorer, +4 assist1, +5 assist2 (neg = none)
printz $BF 11,2
h = 5 ; if r.a1 >= 0: h = 7 ; if r.a2 >= 0: h = 8
Framer(19, h)                                      ; cols 11-29, rows 2..(1+h)
word_FFBF48 = scoring team's goalie count (sub_F9FC0 / sub_9F40)
hdr = PP-goal (bclr word_FFC300 bit0, set by sub_1284A when the goal frees a penalized player) ? $18A34 : $18A14
if team.goals[scorer] == 3 and scorer >= word_FFBF48 (not a goalie):
    hdr = next string (HAT TRICK! variant)
    if team == HomeTeam: background animation 0 (arena_animations.md)
printbig hdr                                       ; cursor ends at (12,5)
printx = 12 ; print sub_18B26(scorer)              ; row 5, "27 Roenick"
if scorer >= word_FFBF48: print " (" goals ")"     ; sub_FEAFA: game goals, 1-3 digits; then printy+1, printx = 14
if r.a1 >= 0 and !bclr(word_FFC2F4 bit5 = penalty-shot goal):
    printz $BF 14,6 "Assist by:" $BF 12,7 ; print sub_18B26(a1) ; sub_FEAE4 " (" assists ")"
    if r.a2 >= 0: printz $BF 12,8 ; print sub_18B26(a2) ; " (" assists ")"
bclr word_FFC2F4 bit5
```

| header | string | big text at | size |
|---|---|---|---|
| normal | `$18A14` "GOAL!" | (15,3) | cols 15-24, rows 3-4 |
| hat trick | `$18A22` "HAT TRICK!" | (12,3) | cols 12-29 |
| power play | `$18A34` "PP GOAL!" | (13,3) | |
| PP hat trick | `$18A44` "HAT TRICK!" | (12,3) | |

- Rows: 2 top border; 3-4 header; 5 scorer; 6 "Assist by:" (cols 14-23); 7 first assist; 8 second assist; bottom border at row 6, 8 or 9.
- The hat-trick text is printed for both teams; the arena animation runs only for the home team. A penalty-shot goal never lists assists. Shorthanded and empty-net goals get the plain "GOAL!".
- **Timing:** the box appears when `InProgress` reaches the goal entry (`SetPA($E)`, after the goal stoppage's `Pencntdwn`). It shows the referee frame 5 for 80 VBlanks, then the window is cleared. That is not the moment of the goal (`checkgoal`).
- **Erasing:** no routine erases this box by itself. It goes away when one of these happens:
  - (a) a line menu opens at the **top** of the screen. `sub_B92E` calls `box` (L56167), which runs `printz $FF 11,2` and `eraser(19, 8)`, blanking cols 11-29, rows 2-9.
  - (b) the penalty screen starts (`SetHor` fills plane A) or a pause ends (`ClrHor` erases plane A).
  - (c) the penalty-shot or shootout intro erases cols 3-29, rows 2-9 (or 2-13).
  - (d) the face-off close-up partly overlaps it: the window is drawn at (1,3) or (18,3), and `loc_FDDE` erases its 12 x 13 cells at the drop.
- **UNRESOLVED:** whether the box visibly survives the next face-off when no top line menu opens (line changes off, or a CPU team). The code says only (d) touches it, which would leave a partial box. This needs an emulator check before the port copies that look.

---

## 6. Injury box (`loc_1871C` L55851)

Trigger: `InjCntDown` (`$C3EC`) is set to 4 at the injury (L49472; 3 in the fight patch) and counted down once per game second in `periodiceevents` (L29957-29961). The box is drawn when it reaches 0.

```
printz $BF 11,3 ; Framer(18, 5)                         ; cols 11-28, rows 3-7
if byte_FFC2FC bit5 (out for the game):
     printz "$BF 12,4 Injury to: $BF 12,6 Out for game $BF 12,5"      ; $1876C
else printz "$BF 12,4 Injury to: $BF 12,6 Out for period $BF 12,5"    ; $18740
print sub_18AC6()                 ; TempPlOffset player, "NN F. Last", row 5 from col 12
if puck $B7AD bit0 (fight): printz $BF 20,6 "the game"   ; "Out for the game" (overprints "game"/"period")
```

Erased like the goal box (§5). The port has this box, with the right texts and position (`hud.gd` `_on_injury`), but drawn as a Label panel with the full name instead of "F. Last".

---

## 7. Penalty-shot and shootout boxes

### 7.1 Penalty-shot intro (`sub_187B8` L55906, from `chkprogress` while `BA_PS_flags` bit 7)
```
set word_FFC2FA bit7 (attempt clock frozen) ; if shootout mode: goto loc_FC320 (7.2)
prefmes(-1)                                         ; clear the referee message
printz $BF 3,2 ; Framer(27, 8)                      ; cols 3-29, rows 2-9
printbig "$BF 4,3 PENALTY SHOT! $BF 4,5"            ; $18884, rows 3-4
print sub_18AE8(shooter: SortCords[word_FFD406].$66, team word_FFD404)     ; row 5: "66 M. Lemieux"
printz $BF 4,7 ; print PenaltyList[word_FFD410].text ; printz " by" $BF 4,8 ; print sub_18AE8(other team, BA_Checker_Offset)
```
Erased by `chkprogress` when `word_FFC31A` runs out: 400 frames, or 100 without pads; a pad press cuts it to 2 (`shootout_penaltyshot.md` §1.5). The erase is `printz $FF 3,2` + `eraser(27, 8 or 12 in shootout)` (L46026-46042).

### 7.2 Shootout intro (`loc_FC320` L968689)
```
prefmes(-1) ; printz $BF 3,2 ; Framer(27, 12)          ; cols 3-29, rows 2-13
printbig "$BF 4,3 SHOOTOUT MODE $BF 4,5"                ; $FC466
print sub_18AE8(shooter word_FFD40A, team word_FFD404)  ; (4,5)
printx = 4+6, printy = 6: " vs."                         ; (10,6)
$BF 4,7: sub_18AE8(goalie, other team)                  ; (4,7)
$BF 4,9: home CITY ; printx = $15: DeterStrLength(word_FFD574, 3)      ; row 9, goals cols 21-23
$BF 4,10: away CITY ; printx = $15: DeterStrLength(word_FFD576, 3)     ; row 10
$BF 4,12 "Round " DeterStrLength(word_FFD578, 2)                       ; row 12
```

### 7.3 Shootout winner (`sub_FC5AE` L968890, from `SetPA` when `word_FFC2FA` bits 0 and 3 are set)
```
printz $BF 1,13 ; Framer(30, 6)                          ; cols 1-30, rows 13-18
printbig "$BF 2,14 SHOOTOUT WON BY"                      ; rows 14-15
printy += 2 ; printx = 2 ; printbig winner CITY          ; rows 16-17 (home if FFD574 > FFD576 signed, else away)
```

---

## 8. Sideways penalty screen text (plane B unless noted)

`chkprogress` → `SetHor` (L47101) draws the 32 x 28 side view (`$BC05C`) into plane B with no palette load, then `sub_12DA6` (L47290):
```
set disflags bit3 ; PrintScores1 (2.4: period, plates, big goals)
printz $BE 20,8 ; sub_12DDE(home)
printz $BE 5,8  ; sub_12DDE(away)
sub_12DDE(team): for each box-list byte ($9A(team), until negative): non-coincidental entries first (tmpdst bit14 clear), then coincidental
sub_12E12(slot):  if printy > $A: skip                  ; at most 3 rows: 8, 9, 10
                  print jersey (2 chars) ; print PushTime(tmpdst[slot] & $7FF)      ; " M:SS" left in the box
                  printx back ; printy += 1
```

| Item | Plane | Cells |
|---|---|---|
| away plate / goals | B | plate cols 3-13, rows 2-3; big goals from col 8, rows 4-5 |
| period ("1st" …) | B | cols 15-16, row 2 (centred on 17) |
| home plate / goals | B | plate cols 18-28, rows 2-3; goals from col 23 |
| clock | B | cols 13-14 and 17-18, row 5 (§3.2) |
| away box list ("#" / "Penalty" art at row 7) | B | jersey cols 5-6, time cols 7-11, rows 8-10 |
| home box list | B | jersey cols 20-21, time cols 22-26, rows 8-10 |
| referee message, then player name | A | row 11, centred on col 17 (§4) |
| referee picture | A (no priority) | 7 x 8 cells at (13,15) (`showref`) |
| playoff ticker | A | rows 23-27 (§8.1) |

- So the "# Penalty" placeholders of the side view get the **jersey number** and the **time left** of each player in the box. The penalty name is never printed there; it shows only as the row-11 message.
- `sub_12DA6` runs at every `SetHor` and again after each assessment (`InProgress` L46302), so the lists grow as penalties are handed out. The side view is redrawn from the ROM map at each `SetHor`, which clears old entries.
- The penalized-player star with his number follows him to the box (`indicators_and_priority.md` A.3).
- Palette aside (outside this spec): the `SetHor` dobitmap passes `d5 = 0`, so the side view's own palette (`$BC05C` + `$1A8A`) is **not** loaded. CRAM lines 2-3 stay the team colours while the side view is up. The port's `palettes.json` "side" lines 2-3 are therefore not what retail shows. UNRESOLVED / for the arena owner.

### 8.1 Playoff ticker (`NewTicker` L47910, `NewTicker3pt2` L47943)
Shown only when (a) `gameclock <= 8:00`, and (b) another playoff series game is still in progress (`$CF2C`/`$CE66` game list, flags `$E` bits 1-2). It is drawn at the start of the penalty screen (L46082-46083):
```
sub_134E4: printz $BD 3,23 (window) ; if not paused: printz $BF 3,23 (plane A) ; Framer(26, 5)   ; cols 3-28, rows 23-27
printx = 4, printy = 24 ; printa = $A000 (line 1) ; 24 spaces (cols 4-27; colours line 1 [4] $222 and [3] $444)
print heading unk_13488[$D048 ? 1 + playoff round : 0]   ; "EA Hockey Night", "Stanley Cup Qualifier", "Quarterfinal", "Stanley Cup Semifinal"
print unk_191E4[game.period - 1] at col 4 + $17 - len/2   ; right part of row 24
printa = $8000 ; rows 25, 26: team CITY (TEAMS[$30E] table) at col 4, score DeterStrLength(.., 2) at col 25
```
The table has only 4 headings. Round 4 would index past it into code; the final round has no other series, so the ticker never shows then. It is erased by `ClrHor` (and by `sub_134D8` L48114 from the intermission). Out-of-scope detail: the game-list update (`NewTicker2`/`sub_13848`).

---

## 9. Face-off line labels and the line-change menu

### 9.1 Face-off window labels (`puckfaceoff2` `loc_FB54` L42215-42269)
- The window position comes from `fodrop`:
  - x = `$36` (or `$BE` if `$BF94 < 0`), so `printx = (x-$2E)>>3` = 1 or 18;
  - y = `$5C`, so `printy = 3`.
- `dobitmap` draws `FaceOffMap` 12 x 10 there (cols 1-12 or 18-29, rows 3-12, `printa` 0 XOR map). Then, **only when line changes are on** (`OptLine == 0`):
  ```
  printz2 $FA +10, $FE 4          ; printy = 13, printa = $8000
  Framer(12, 3)                    ; rows 13-15 under the window
  printz2 $FB +1, $FA -2           ; (x+1, 14)
  left = gmode bit1 ? home line : away line ; right = the other
  print2 unk_191A6[left] ; printx += 4 ; print2 unk_191A6[right]   ; "Sc1", "Sc2", "Chk", "PP1", "PP2", "PK1", "PK2"
  ```
  Labels at cols x+1..x+3 and x+8..x+10, row 14.
- Erased at the drop by `loc_FDDE` (L42427-42442): `eraser(12, 13)` from the window's top-left (rows 3-15).
- The port draws the window (`faceoff_window.gd`) but not the label box.

### 9.2 Line-change menu (`sub_B92E` L36584, `setlccords` L36634, `lcfound2` L36813)
Fully specified in `input_linechanges.md`. Cell layout, for the port:
- Frame at x = 22, 9 wide, y = 0 (top) or 22 (bottom). Home is at the bottom unless `gmode` bit 1. The frame is 6 tall (3 choices) or 5 tall at y+1 (2 choices on special teams).
- Rows bottom-up from `y + h - 2`: C, B, A. Each row is:
  - cols 23-24: "A "/"B "/"C ";
  - cols 25-27: line name (`unk_191A6`);
  - cols 28-29: energy bar (`$AB920` map row 15 - min(getlinee/256, 15)).
- The team abbreviation is on the first interior row from col 25.
- Opening at the top first calls `box` (erases cols 11-29, rows 2-9). Opening at the bottom sets `sflags3` bit 0, which hides the score team box.
- Closing (`lcfound2`) erases 9 x (h+1) and calls `PrintScores1`. After a pick the menu is redrawn showing only the chosen row.

The port's `line_menu.gd` is a Label at a fixed spot with '|' bars.

---

## 10. Stars of the Game (`sub_1850A` L55666, from `UpdatePA` every frame while RefPen == 4)

```
if RefCnt > $40: return ; if bset(gmode bit7) was set: return            ; once, in the last 64 VBlanks of the "Game Over" script
set disflags bit3 ; wait one VBlank
printz $BF 2,14 ; Framer(28, 9)                                         ; cols 2-29, rows 14-22
printz "$BF 9,16 Stars of the Game $BF 3,15"                            ; $18550, cols 9-25, row 16
dobitmap rink map ($5605A) cols $D-$12, rows $5B-$5E (6 x 4) at (3,15)   ; all rink tile $0A = solid black: a placeholder panel
sub_18620: star scores for both teams (below)
printy = $12 ; 3 times: pick = sub_185E0 (largest score, ties to the lower index, then zeroed)
                        printx = $1A ; printy += 1 ; print team abbreviation   ; col 26, rows 19-21
                        print getname(pick) at col 3                             ; "27 Jeremy Roenick"
if HmGoals > AwGoals: song($F)
```

Scores (`sub_1867E` L55791), per roster slot k (0-25) of each team, into `$CF36 + 4*(26*team + k)`:
- start from `d3 = own goals - other goals` (signed).
- A skater (k at or past the goalie count) gets:
  - `+ goals*11000 + assists*10100`;
  - `+ shots*10` if d3 ≠ 0, else `+ shots*1000 + word $136[k]`.
- A goalie gets `+32000` if `100*GA/SA <= 4`, and a further `+75000` if that ratio is 0. This counts only if `word $136[k] >= ClockLength + d2` and SA > 0.
- In overtime (gsp == 3), the record of the last goal gets `$7FFFFFFF` (first star).

UNRESOLVED: the value of d2 at `sub_18620` (`sub_1850A` loads 6 before `dobitmap`; whether `dobitmap` keeps it is not checked), and the meaning of `$136[k]` (most likely time on ice in seconds). The box stays up until the game-over flow changes the screen.

---

## 11. Not in this spec / not in retail

- Pause, intermission, game-over menus, stats pages, the instant-replay panel (`sub_A448`/`sub_A4A8`: rink map cols 32-39 rows 85-88 and the `$BB4EE` panel on the window plane), the playoff highlight ("Highlight from game:", `sub_1354C`), and the attract/demo screens.
- The fight patch's banner (`fight_patch_retail_hooks.md` §9).

---

## 12. Exported assets (`tools/extract/ui_overlay.py` → `godot/assets/ui/`)

The output is deterministic (written twice and compared). Index textures follow `assets.py`: R = colour × 17, G = line × 85, A = 255 where the colour is not 0. Colour them with `ui.json` `cram` (lines 0 and 1, CRAM words).

| File | Content |
|---|---|
| `font_idx.png` | 94 print-font tiles after the in-game remap, 16 per row (128 x 48). Opaque: the glyph background is colour 4. Glyph map = `ui.json` `font.chars` (char code → tile; the same map as `sprites/font.json`). `'@'` = transparent cell, `'^'` = skip. `$12-$14` = ordinals, `$16-$19` = Pwr Play. |
| `bigfont_idx.png` | 132 printbig tiles (remap 0 → 7), line 1, 16 per row. `ui.json` `bigfont.glyphs[code]` = `{w, col, top: [[tile, flags, line]…], bottom: […]}` for codes 32-91. Flags: bit 0 h-flip, 1 v-flip, 2 priority. |
| `framer_idx.png` | 24 x 24: the 9 Framer tiles, 3 per row, in `framermap` order TL T TR / L C R / BL B BR (`ui.json` `framer`). Line 1. |
| `ea_logo_idx.png` | 56 x 16, the score box logo (line 1, opaque). |
| `team_plates_idx.png` | 88 x 448: plate t at y = 16t (team index as in `palettes.json` teams). Line 1. |
| `energy_idx.png` | 16 x 128: bar state s at y = 8s (s = 15 - fill). Lines from the map. |
| `ui.json` | `cram`, `screen`, `font`, `bigfont`, `framer`, `ea_logo`, `team_plates`, `energy` (geometry, remap tables, glyph maps, notes). |
| `messages.json` | `penalty_list` (id, ROM address, delay, minutes, text, referee script words), `period_labels` (`$191E4`), `period_labels_alt` (`$191F8`), `line_names` (`$191A6`), `ticker_headings` (`$13488`), `clock_digits`, `special_chars`, and `inline`: every inline `printz`/`printz2`/`printbig` string listed in this spec, with address, routine, listing line and decoded ops (`{"at": [x, y], "plane": "A"\|"B"\|"W", "attr": n}`, `{"text": s}`, print2 ops `dx`/`dy`/`attr`). ROM addresses are decimal integers. |

The existing `sprites/font_idx.png` is the **raw** font (line 1, colour 0 transparent) used by the pad markers. In-game text should use `ui/font_idx.png` to get retail's opaque black cells.

---

## 13. Port

### 13.1 What the port draws now (`godot/ui/hud.gd`, `line_menu.gd`, `ref_window.gd`, `faceoff_window.gd`)

| Retail item | Port | Gap |
|---|---|---|
| score box + clock (§2, §3) | one yellow Label at the top: `"HOME n AWAY n  P1  m:ss  PP xxx"` | position, font, frame, EA logo, period glyphs, PP banner with time (CalcPenTime is not ported) |
| referee message (§4) | Label at (4,16), 150 frames | box under the referee at rows 10-12; lifetime = script; horizontal: centred on row 11 + name after 60 VBlanks |
| penalty assessed | Label "ABR name Penalty n min" | retail shows only the penalty name, then "NN Full Name", on row 11 of the penalty screen, plus the box lists (§8) |
| goal box (§5) | nothing (`goal_scored` is unused by the HUD) | all of §5 |
| injury box (§6) | PanelContainer at (11,3), right texts | Framer art, "F. Last" name form, erase rules |
| PS / SO intro (§7.1-7.2) | centred PanelContainer, abbreviations | exact boxes, big headers, city names for SO, "NN F. Last" names |
| SO winner (§7.3) | text through `ref_message` | Framer 30 x 6 at (1,13), big text, big city |
| intermission / final banner | Label "End of the 1st – Start to continue", "Final …" | belongs to the menu spec; not drawn in play by retail |
| ref window | `ref_window.gd`, exact | – |
| face-off window | `faceoff_window.gd`, exact | the line label box (§9.1) |
| line menu | `line_menu.gd` Label | Framer 9 x 6/5 at (22, 0/22), A/B/C rows, energy-bar tiles, `box`/score-box interplay |
| side view text (§8) | none | plates, period, clock, big goals, box lists |
| Stars of the Game (§10) | none | all |
| playoff ticker (§8.1) | none | needs the other-series data first |

`godot/ui/window_plane.gd` (`WindowPlane`: 32 x 28 cells, `print_at`, `frame`, `erase`, `put_tile`, `add_tileset`) is the natural host for a plane-A overlay. Two changes would make it render retail exactly:
- load `ui/font_idx.png` (opaque) for in-game text;
- register `framer_idx.png` with `add_tileset("frame", tex, 3)` and `set_frame_tiles([0..8])`. Its frame helper already expects the TL…BR order.

`bigfont`, `ea_logo`, `team_plates` and `energy` can go through `put_tile` with their own keys.

### 13.2 Port hooks (existing names)

| Need | Use |
|---|---|
| referee message id and clear | `GameRules.set_pa(id)`: `ref_message(text)` is emitted with `PenaltyList` text (empty for `$A`, `$E`, `$14`). `w.rules.refpen` holds the id. `HockeyWorld.ref_signal(frame)`: frame `$40` = script end = erase the message (`prefmes(-1)`). |
| goal box | `GameRules.set_pa(PEN_GOAL)` (draw time) and the last `w.score_summary` record (`away`, `scorer`, `assist1`, `assist2`). `HockeyWorld.goal_scored(team, rec)` fires earlier, at `checkgoal`. PP-goal flag: `w.pp_goal(scorer)` (`sub_1284A`) needs to expose the `word_FFC300` bit 0 result. Hat trick: `w.arena.hat_trick_check()` inputs (`stats[team].player_goals[scorer] == 3`). PS goal: the `word_FFC2F4` bit 5 equivalent. |
| score box redraw | `GameRules.print_scores1()` (called from `faceoff_logic.gd:168`, `line_logic.gd:336`, `puck_logic.gd:718`): add a signal there. Also redraw on `horizontal_changed(false)` and on unpause. |
| team data | `w.stats[t].data.abbreviation`, `.city` (`palettes.json` teams), `.player(slot).jersey_number / full_name`, goals `w.score(t)` |
| clock | `w.clock_seconds()`, `w.gsp`, `w.f_c2fa & ShootoutLogic.C2FA_ATTEMPT_CLOCK` → `w.shootout.ps_clock`, `HockeyWorld.C2FA_SHOOTOUT` |
| power play | `w.sflags2 & HockeyWorld.SF2_PWRPLAY`, `SF2_PWRTM` (team), `GameRules.updatepwrplay()` (once a second). Port `CalcPenTime` (`rules_clock_penalties.md`) for the time. |
| penalty screen | `GameRules.horizontal_changed(on)`, `penalty_assessed(team, pnum, id, minutes)`, `w.temp_pl_offset`, `stats[t].tmpdst` and the box lists |
| injury | `HockeyWorld.injury_message`, `w.temp_pl_offset`, `w.injury_game`, `puck().flags2 & PF2_FIGHT` |
| PS / SO | `ShootoutLogic.intro(lines)` (replace with structured data), `HockeyWorld.C2FA_PS_INTRO` cleared = erase, `w.ps_intro`, `ShootoutLogic.shootout_won(team)`, `w.shootout_goals`, `so_round` |
| face-off | `faceoff.window_open`, `faceoff.fodrop`, `faceoff_dropped` (erase), `stats[t].line`, `HockeyWorld` gmode bit 1 |
| line menu | `LineLogic.menu_changed(team)`, `stats[t].flags30 & TeamStats.F30_LINE_MENU`, `lines.getlchoice`, `lines.getlinee` |
| crowd | `GameRules.crowd_loud`, `crowd_hold`, `cur_crowd_meter` (no in-play display) |
| game over | `refpen == PEN_EOG` and `refcnt <= $40` → Stars |

### 13.3 Checklist
1. A plane-A overlay node (`WindowPlane` or a twin) behind nothing and above the rink, sprites and glass. Retail cells are high priority. Cell (c, r) at (32 + 8c, 8r). Also a plane-B text layer bound to the side view for §8.
2. Load the `ui/` assets: opaque font, big font, Framer, EA logo, plates, energy bars, `messages.json`.
3. Score box per §2.1/2.2. Redraw it on every `print_scores1`, on `horizontal_changed(false)` and on unpause. Hide the team box while a bottom line menu is open (port `sflags3` bit 0).
4. Clock cells per §3.1: redraw on the game-second tick, freeze during replay and after gsp 4. Show the attempt clock with a blank period label.
5. PP banner per §2.2, each game second; port `CalcPenTime`. Restore the EA logo when the power play ends.
6. Referee message box per §4: draw at `set_pa`, erase at `ref_signal(0x40)`. Drop the 150-frame Label.
7. Goal box per §5 at `set_pa(PEN_GOAL)`, with the PP-goal / hat-trick headers, counts and assists. Erase it per §5 (a)-(c), and decide (d) after the UNRESOLVED check.
8. Injury box: Framer art, `sub_18AC6` name form.
9. PS intro, SO intro and SO winner boxes per §7, with printbig headers. Clear them when `C2FA_PS_INTRO` drops (rows 2-9, or 2-13 in a shootout).
10. Penalty screen: plates, period, clock, big goals, box lists (§8). Message row 11: the penalty name, then the player name after 60 VBlanks.
11. Face-off label box (§9.1) when line changes are on.
12. Line menu as cells (§9.2), including `box` erasing the goal area and the score-box interplay.
13. Stars of the Game (§10) during the end of the "Game Over" script.
14. Playoff ticker (§8.1) once the playoff module tracks the other series.
15. Remove the non-retail Labels (the top scoreboard line, the penalty call line). The intermission and final banners belong to the menu port.

---

## 14. UNRESOLVED

1. Goal / injury box lifetime when no top line menu opens (§5): the code shows no eraser other than the partial face-off erase. Check on hardware or an emulator.
2. `sub_18620`'s d2 at entry and the meaning of `$136[k]` (§10).
3. The side view's CRAM lines 2-3 during the penalty screen (§8 aside): the code says team colours. Not checked against a capture.
4. Playoff ticker data (`$CE66` game list, `NewTicker2`): only the layout is specified here.

## 15. Port status

Ported in `ui/hud.gd` on `ui/window_plane.gd`: §2-§10 except the playoff ticker during play (the intermission ticker is in the menu port). Logic added: `GameRules.pa_set`, `goal_box` / `goal_box_info` (PP-goal flag from `pp_goal`, the penalty-shot flag consumed), `scores_printed`, `calc_pen_time`, `stars` / `stars_of_game`, `TeamStats.player_toi`. Port choice for UNRESOLVED 1: the goal and injury boxes go at the next face-off setup.
