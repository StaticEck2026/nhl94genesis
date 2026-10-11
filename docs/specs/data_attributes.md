# NHL '94 data and attributes: team records, player ratings, attribute math, energy

Source: `lst/nhl94.bin.lst` (line numbers `Lnnnnn`) and the ROM image `lst/nhl94.bin` (ROM offsets `$xxxx`).
Every table and every team/player fact below was read from the ROM bytes and checked against the code that reads them.
Important: `src/teamdata94.asm` is **not** NHL '94 data. It is the NHL '93 layout and roster (see 1.7). The extractor must read the ROM.

## Overview: how the pieces fit

1. **ROM team records.** The team pointer table at ROM `$30E` holds 28 longs, indexed by team number 0-27. Each long points to a team record. A record holds a 12-byte offset header, two 16-color palettes, a 4-byte team-ratings block, a goalie-count word, 8 lines of 8 bytes, the variable-length player list, and 4 name strings.
2. **Team setup.** `sub_171BE` (L53748) stores the record pointer in the RAM team struct at `$1E` and copies 7 of the 8 lines into the struct at `$16A`. `SetTeamColors` (L53781) copies the home palette of the home team and the away palette of the away team into the CRAM shadow.
3. **Per-game form ("hot/cold").** Before each game, `Create_HotCold_Table` (L959871) fills 16 random bytes in -9..+8 for each of the 26 roster slots of each team, at team struct `$1A2`.
4. **Bringing a player on ice.** `setplayer` (L51556) runs every time a player object gets a roster slot (line change, faceoff setup, penalty exit). It walks the player list to the slot, computes team bonuses (power play, penalty kill, home/away, 3rd period trailing), and writes the in-game rating bytes `$67-$76` of the SCstruct. Each 0-15 nibble goes through `AttributeCalc` (L959917): `nibble*5 + hotcold/3`, clamped to 0..30.
5. **Display.** Roster and line screens show 25-99 ratings through `getNameandAttrib` (L32053), `CalcAttrib` (L966169), `DispAttribValue` (L32183) and `AttribAdjust` (L975193). The display uses a different formula: `nibble*18 + hotcold`, then the 25..99 remap. "Overall" is a weighted sum.
6. **Energy.** Each roster slot has an energy word (`tmpde`, team struct `$32 + 2*slot`, full = `$1000`). It drains in `playeracc` and in `burst`, recovers on the bench in `periodiceevents`, and is refilled at intermissions and timeouts. `makepde` scales a rating by energy.

## Corrections to the shared SCstruct map (NHL '94, verified in setplayer and its readers)

The preamble map was derived from '93 equates. In '94, setplayer writes the following, and the listed readers use them this way:

| offset | '94 meaning | written by setplayer as | readers that confirm it |
|---|---|---|---|
| `$6F` | jersey number, packed BCD (`$77` = #77) | raw byte 0 | L47350 `move.b -8(a1),d0` -> `d0toascii` |
| `$74` | **fighting** rating, even 0..14 (bit 0 always 0) | `byte4 & $0E` | L49218 `tst.b $74(a3) ; checks fight attribute`, L974885/974892 |
| `$75` | **checking** (new in '94) 0..30 | AC(Chk)+3rd bonus | L40750, L40856, L49115, L49419 |
| `$76` | **handedness**: 1 = left-handed ("Lefty"), 0 = right ("Righty") | `(byte4 & 1) ^ 1` | L38075, L39671 (`check hand of goalie`), L50493, L974411 |
| `$04` (byte) bit 3 | sprite H-flip base: **set for right-handed** players | `bclr #3,4(a3)`, then `bset` if `$76 == 0` | sprite code |
| goalie save bytes | `GGSleft = $73`, `GGSright = $6E`, `GSSleft = $70`, `GSSright = $72` | see setplayer | `puckgoalie _list` L50959: `dc.w $73,$6E,$70,$72` = Glove L, Glove R, Stick L, Stick R |

So the preamble's `$74 handed`, `GGSright=$6D` and `GGSleft=$71` are '93 values and are wrong for '94. For goalies, `$71` (stickhand), `$6D` (shotacc) and `$75` (checking) come from nibbles that are 0 in every goalie record, so they are 0..2 (just the hot/cold offset).

## Globals, RAM and tables used

| name | address / location | use |
|---|---|---|
| team pointer table | ROM `$30E`, 28 longs (listing L282, comment "Team List Pointer Table Start") | `movea.w #$30E,a0` in `sub_171BE`, `getscore`, `sub_FAE26`, `sub_F99F2` |
| `HmShots` | `$FFC6CE` = home team struct (size `$364`) | base of all team-struct fields |
| `AwShots` | `$FFCA32` = `HmShots + $364` = away team struct | |
| `HmGoals` / `AwGoals` | `$FFC6DA` / `$FFCA3E` (team struct `+$0C`) | 3rd-period bonus lead check |
| `PPBonus` | `$FFCF2E` (byte) | setplayer |
| `PKBonus` | `$FFCF2F` (byte) | setplayer |
| `ThirdPBonus` | `$FFCF30` (byte) | setplayer |
| `HmAwBonus` | `$FFCF31` (byte) | setplayer (all four bytes cleared by one `clr.l (PPBonus)`) |
| `word_FFBF14` | `$FFBF14` | attribute index 3..$F written before each AttributeCalc call. AttributeCalc never uses it (see quirk). |
| `OvrDivisor` / `OvrDividend` | words (`$FFD6CE`/`$FFD6D0` per listing comments) | CalcAttrib hot/cold sum / count. The names are swapped: Divisor holds the **sum**, Dividend the **count**. |
| `gsp` | game period word: 0,1,2 = periods 1-3; 3 = OT; 4 = game over | 3rd-period bonus |
| `gameclock` | word, counts **down** in game-clock seconds. The VBL subtracts `$AAA` from an accumulator and decrements the clock on borrow, so 1 clock second = 24 vblanks. | |
| `OptPerlen` | 0..3 -> `ClockLength` `_timetab` = `$12C,$258,$4B0,$1E` (300, 600, 1200, 30 s) | |
| `OptLine` | 0 = line changes On, 1 = Off. Option value 2 ("Auto") is turned into 0 at setup plus `byte_FFC2FC` bit 4 (L962434 area). | |
| `byte_FFC2FC` bit 4 | "Auto" line changes: energy reads as `$1000` in makepde/playeracc/burst | |
| `sflags2` bit 5 / bit 6 | power play in progress / power-play team (0 home, 1 away) | chkpk2 |
| `vcount` | VBL counter (+1 per vblank) | parity in the energy drain |
| `VDP_CNTR` | `$C00008` HV counter, used as a cheap random source | energy drain gate |
| `RNGseed` | `randomd0` (L44190): returns 0..d0-1. `randomd0s` (L44178): returns `randomd0(2*d0) - d0` = -d0..d0-1. | |

Team struct fields (offsets from `HmShots`/`AwShots`) used here:

| off | size | meaning |
|---|---|---|
| `$0C` | w | goals (score) |
| `$16` | w | current RAM line index 0..6 (Sc1, Sc2, Chk, PP1, PP2, PK1, PK2) |
| `$1E` | l | ROM address of this team's record |
| `$22` | w | `tmsort`: address of the team's first SCstruct (`$B04A` home, `$B34A` away, set in `sub_17190`) |
| `$24` | w | `tmap`: players on ice including goalie, 4..6 |
| `$26` | w | `tmgoalie`: roster index of the goalie on ice; negative = goalie pulled |
| `$28` | w | team number 0..27 |
| `$30` | w | flags: bit 1 = line change pending, bit 2 = timeout used |
| `$32 + 2*slot` | w[26] | `tmpde`: energy, 0..`$1000` |
| `$66 + 2*slot` | w[26] | `tmpdst`: -1 on ice, -2 bench, -3 (`$FFFD`) injured for period, -4 (`$FFFC`) injured for game, >= 0 in the penalty box (time in low 12 bits, bit 12 and bit 14 are display flags) |
| `$E8 + slot` | b[26] | per-player shots (ChkShotStat) |
| `$16A` | 7 x 8 bytes | RAM lines (copied from ROM, see 1.4) |
| `$1A2` | 26 x 16 bytes | hot/cold table (`$1A2 + 16*slot + k`) |

---

## 1. Team data in ROM

### 1.1 Team pointer table (ROM `$30E`)

`TeamPtr[i] = long at $30E + 4*i`, i = 0..27. Each code path that needs a team does `movea.w #$30E,a0; asl.w #2,d0; movea.l (a0,d0.w),a0` (e.g. `sub_171BE` L53748, `getscore` L47815). The table is in the listing at L282-310. Each entry is labeled `unk_<addr>`, and the record starts at the label of the same name (e.g. `unk_966:` at L1823).

**Listing comment errors:** the comments at L282-310 swap PIT/PHI (entries 16/17) and STL/SJ (entries 19/20). The team-name strings in the records are authoritative, and the table below uses them.

| idx | ROM addr | listing label | city | abbr | nickname | arena | G | F | D | players |
|---|---|---|---|---|---|---|---|---|---|---|
| 0 | `$5330` | unk_5330 (L20713) | Anaheim | ANH | Mighty Ducks | Pond | 2 | 9 | 7 | 18 |
| 1 | `$966` | unk_966 (L1823) | Boston | BOS | Bruins | Boston Garden | 2 | 15 | 8 | 25 |
| 2 | `$C4C` | unk_C4C (L2565) | Buffalo | BUF | Sabres | Memorial Auditorium | 3 | 14 | 8 | 25 |
| 3 | `$F3A` | unk_F3A | Calgary | CGY | Flames | Olympic Saddledome | 2 | 13 | 10 | 25 |
| 4 | `$1234` | unk_1234 | Chicago | CHI | Blackhawks | Chicago Stadium | 2 | 15 | 8 | 25 |
| 5 | `$214E` | unk_214E | Dallas | DAL | Stars | Reunion Arena | 2 | 14 | 9 | 25 |
| 6 | `$152E` | unk_152E | Detroit | DET | Red Wings | Joe Louis Sports Arena | 2 | 15 | 8 | 25 |
| 7 | `$1848` | unk_1848 | Edmonton | EDM | Oilers | Northlands Coliseum | 2 | 15 | 8 | 25 |
| 8 | `$50E6` | unk_50E6 (L20127) | Florida | FLA | Panthers | Miami Arena | 2 | 9 | 6 | 17 |
| 9 | `$1B44` | unk_1B44 | Hartford | HFD | Whalers | Hartford Civic Center | 3 | 15 | 7 | 25 |
| 10 | `$1E52` | unk_1E52 | Los Angeles | LA | Kings | Great Western Forum | 3 | 13 | 9 | 25 |
| 11 | `$243E` | unk_243E | Montreal | MTL | Canadiens | Montreal Forum | 2 | 14 | 9 | 25 |
| 12 | `$2740` | unk_2740 | New Jersey | NJ | Devils | Byrne Meadowlands Arena | 2 | 15 | 8 | 25 |
| 13 | `$2A58` | unk_2A58 | New York | NYI | Islanders | Nassau Coliseum | 2 | 15 | 8 | 25 |
| 14 | `$2D5C` | unk_2D5C | New York | NYR | Rangers | Madison Square Garden | 2 | 15 | 8 | 25 |
| 15 | `$3054` | unk_3054 | Ottawa | OTW | Senators | Ottawa Civic Center | 2 | 15 | 8 | 25 |
| 16 | `$3348` | unk_3348 | Philadelphia | PHI | Flyers | Spectrum | 3 | 14 | 8 | 25 |
| 17 | `$3646` | unk_3646 | Pittsburgh | PIT | Penguins | Civic Arena | 2 | 14 | 9 | 25 |
| 18 | `$393C` | unk_393C | Quebec | QUE | Nordiques | Colisee de Quebec | 2 | 15 | 8 | 25 |
| 19 | `$3C42` | unk_3C42 | San Jose | SJ | Sharks | San Jose Arena | 3 | 13 | 9 | 25 |
| 20 | `$3F30` | unk_3F30 | St. Louis | STL | Blues | St. Louis Arena | 2 | 14 | 9 | 25 |
| 21 | `$4216` | unk_4216 | Tampa Bay | TB | Lightning | Fairgrounds Expo Hall | 3 | 15 | 7 | 25 |
| 22 | `$4518` | unk_4518 | Toronto | TOR | Maple Leafs | Maple Leaf Gardens | 3 | 14 | 8 | 25 |
| 23 | `$481C` | unk_481C | Vancouver | VAN | Canucks | Pacific Coliseum | 2 | 15 | 8 | 25 |
| 24 | `$4DFC` | unk_4DFC | Washington | WSH | Capitals | Capital Centre | 2 | 14 | 8 | 24 |
| 25 | `$4B0A` | unk_4B0A | Winnipeg | WPG | Jets | Winnipeg Arena | 2 | 15 | 8 | 25 |
| 26 | `$37E` | unk_37E (L311) | All Stars East | ASE | (empty) | Madison Square Garden | 3 | 14 | 8 | 25 |
| 27 | `$674` | unk_674 (L1069) | All Stars West | ASW | (empty) | Madison Square Garden | 3 | 14 | 8 | 25 |

Physical ROM order of the records: 26, 27, 1, 2, 3, 4, 6, 7, 9, 10, 5, 11..23, 25, 24, 8, 0. The records are contiguous: each record ends exactly where the next begins, and Anaheim ends at `$5576`. 684 player records in total. The All-Star teams have an empty nickname (string length word `$0002`). `sub_FD5AE` (L970584) prints "Home" or "Visitors" in place of an empty nickname.

### 1.2 Team record layout

All offsets are relative to the record start `T`. All header words are offsets from `T`, identical for every team except `+4`:

| off | size | content | value in ROM | read by |
|---|---|---|---|---|
| `+0` | w | offset of player list | `$0092` | setplayer, CalcAttrib, getplayername (L56354) |
| `+2` | w | offset of palettes | `$000C` | `sub_1721C` (SetTeamColors) |
| `+4` | w | offset of name strings | varies | many print routines |
| `+6` | w | offset of lines | `$0052` | `sub_171BE`, `sub_F71F0` |
| `+8` | w | offset of team-ratings block | `$004C` | setplayer, `getscore`, `sub_9F5C`, `sub_9F7E` |
| `+$A` | w | offset of goalie word | `$0050` | `sub_9F40`, `sub_FAE26`, `sub_F99F2` |
| `$0C`-`$4B` | 64 bytes | palettes: 2 x 16 Genesis CRAM words (`0000BBB0GGG0RRR0`). Bytes `$0C-$2B` = home uniform, `$2C-$4B` = away uniform. | | |
| `$4C`-`$4F` | 4 bytes | team-ratings block (below) | | |
| `$50`-`$51` | w | goalie word (below) | | |
| `$52`-`$91` | 64 bytes | 8 lines x 8 bytes (1.4) | | |
| `$92`... | var | player records (1.3), terminated by the word `$0002` | | |
| `T+[+4]`... | var | 4 strings: city, abbreviation, nickname, arena | | |

**Strings.** Each string is a word length that **includes the length word itself**, then `length-2` bytes of ASCII, padded with one `$00` when needed to keep the next string word-aligned. Strip trailing `$00` bytes. The name strings are, in order:
1. city (`adda.w 4(a1),a1`, used as is or centered by `len/2`, L34298)
2. abbreviation (one more `adda.w (a1),a1`, e.g. L32488, L47057)
3. nickname (two skips, `sub_FD5AE` L970584)
4. arena (three skips, `sub_FD5F4` L970622)

There is no organ, music or crowd data in the team record. The crowd record is per home team in SRAM (`LoadCrowdRec`). Team logos are a separate graphics table (`unk_ABA14`, `$2C` bytes per team, `sub_16D64`).

**Team-ratings block (`T+$4C`, 4 bytes; `R = T + word[T+8]`):**

| byte | bits | meaning (as the code uses it) | range in ROM |
|---|---|---|---|
| `R+0` | 6-4 | sim-score offense row (0..7), used by `getscore` for other games' ticker scores | 0..7 |
| `R+0` | 2-0 | sim-score defense row (0..7). A higher value lets the opponent score more. | 0..7 |
| `R+1` | 3-0 | power-play bonus, added (`PPBonus = R1 & $F`) when this team is on the PP | 0..2 |
| `R+1` | 7-4 | penalty-kill penalty, subtracted (`PKBonus = -(R1 >> 4)`) when this team is short-handed | 0..2 |
| `R+2` | 7-4 | home bonus, added when this team is the home team | 0..2 |
| `R+2` | 3-0 | away penalty, subtracted when this team is the visitor | 0..3 |
| `R+3` | 7-4 | number of forwards F | 9..15 |
| `R+3` | 3-0 | number of defensemen D (not read by any code found; equals players-G-F in every record) | 6..10 |

The listing comment at L51592 calls the PP low-nibble use a "(bug)". The community presumably expected the high nibble to be PP. Port the code as it is: low nibble is the PP bonus, high nibble is the PK penalty.

**Goalie word (`T+$50`).** Its nibble count gives the number of goalies G. `sub_9F40` (L34429):
```
d1 = word; d0 = 0
do { d0++; d1 <<= 4 (16-bit) } while (d1 != 0)
G = d0          ; = 4 - (number of trailing zero nibbles), minimum 1
```
Examples: `$B400` -> 2, `$CBC0` -> 3, `$A360` -> 3. The nibble values themselves are never read. They look like goalie quality marks (Roy C, Fuhr B, Barrasso C). Roster grouping: slots `0..G-1` are goalies, `G..G+F-1` forwards, `G+F..G+F+D-1` defense. `sub_9F7E` returns F, and `sub_9F5C` returns G+F (the first defenseman). `sub_9F9A` counts players by walking to the `$0002` terminator. There is no per-player position field: the on-ice position comes from the line slot.

**Palettes.** `SetTeamColors` (L53781) and `sub_1721C`: for the home struct `d1 = 0`, copies 32 bytes from `T+$0C` to `unk_FFBD68` = `palfadenew+$40` (CRAM palette line 2). For the away struct `d1 = $20`, copies `T+$0C+$20` (the away uniform) to `unk_FFBD68+$20` (palette line 3). Across all 28 teams, color indices 0,1,2,6,7,14,15 have the same value (`EE8 222 000 . . . 88C 66A . . . . . . 48C A84`). Team-specific colors are indices 3,4,5,8..13, and indices 10..13 differ between home and away for every team. Example, Boston home: `EE8 222 000 000 202 224 88C 66A 08C 08E CCC AAA CCC 888 48C A84`; Boston away: `... 08E CCC 202 224 000 48C A84`.

### 1.3 Player record layout

Player list at `P0 = T + word[T+0]`. Each record is:

```
+0           w    L = record name length INCLUDING this word (name bytes = L-2, may end with one $00 pad)
+2 .. +L-1        name, ASCII (max 19 chars seen; e.g. "Vladimir Konstantov"; some names are abbreviated in ROM, e.g. "Glen Feathrston")
+L .. +L+7        8 attribute bytes A[0..7]
next record at +L+8
```
The list ends with the word `$0002` (empty name, no attribute bytes follow). Walking to slot `s` (setplayer `_skiploop`, getplayername, CalcAttrib) goes like this:
```
a = P0
repeat s+1 times: a += word[a]; a += 8      ; a now = end of player s's attributes
attrs = a - 8                                ; setplayer: subq.w #8,a0
name  = (a - 8) - (L-2)  ; getplayername stops one record earlier and returns the record start (length word)
```

**Attribute bytes** (nibble numbers `n` are the CalcAttrib bit numbers. Nibble `n` lives in byte `(15-n)>>1`: the high nibble when `n` is odd, the low nibble when `n` is even):

| byte | nibble (n) | skater meaning | goalie meaning | ROM range skaters / goalies |
|---|---|---|---|---|
| A0 | hi (15), lo (14) | jersey number, packed BCD | same | 0..99 |
| A1 | hi (13) | **Weight**: lbs = 140 + 8*n | same | 3..14 / 1..10 |
| A1 | lo (12) | **Agility** | Agility | 0..6 / 2..6 |
| A2 | hi (11) | **Speed** | Speed | 0..6 / 3..4 |
| A2 | lo (10) | **Off. Awareness** | (not displayed; loaded into aioff) | 0..6 / 0..6 |
| A3 | hi (9) | **Def. Awareness** | Def. Awareness | 0..6 / 0..6 |
| A3 | lo (8) | **Shot Power** | **Puck Control** (loaded into `$6C`) | 0..6 / 1..6 |
| A4 | hi (7) | **Checking** | 0 | 0..6 / 0 |
| A4 | lo (6) | bit 0 = hand (1 = Righty, 0 = Lefty); bits 3-1 = **fighting** 0..6 (struct `$74 = lo & $E`) | bit 0 = Glove Hand (same Righty/Lefty strings), bits 3-1 = 0 | 0..12 / 0..1 |
| A5 | hi (5) | **Stick Handling** | 0 | 0..6 / 0 |
| A5 | lo (4) | **Shot Accuracy** | 0 | 0..6 / 0 |
| A6 | hi (3) | **Endurance** | **Stick Right** (`GSSright`, `$72`) | 0..6 / 1..6 |
| A6 | lo (2) | shot/pass bias (`spodds`, `$70`; not displayed) | **Stick Left** (`GSSleft`, `$70`) | 0..5 / 1..6 |
| A7 | hi (1) | **Pass Accuracy** | **Glove Right** (`GGSright`, `$6E`) | 0..6 / 1..6 |
| A7 | lo (0) | **Aggressiveness** | **Glove Left** (`GGSleft`, `$73`) | 0..6 / 1..6 |

Rating nibbles use 0..6 in the shipped data. The field can hold 0..15, and AttributeCalc clamps anything above 6 to 30. The handedness strings were confirmed against real players: Bourque `A4=$60` -> Lefty, Oates `$31` / Lemieux `$33` / Neely `$49` -> Righty.

### 1.4 Lines

`LN = T + word[T+6]`, 8 lines x 8 bytes. Each line is:

| byte | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 |
|---|---|---|---|---|---|---|---|---|
| slot | G | LD | RD | LW | C | RW | X (extra attacker) | always 0 |

Values are **1-based roster slots** (0 = none; never 0 in the ROM). Byte 0 is always 1 in the ROM and is ignored in play: `SetPlList` (L51300) puts `tmgoalie+1` (`$26`) in the goalie slot. Slot numbering equals the SCstruct `$34` position code (0 goalie, 1 LD, 2 RD, 3 LW, 4 C, 5 RW).

The data lines are 1 = "line changes off" line, 2 = Sc1, 3 = Sc2, 4 = Chk, 5 = PP1, 6 = PP2, 7 = PK1, 8 = PK2 (short names at ROM `$191A6`: Sc1 Sc2 Chk PP1 PP2 PK1 PK2, followed by slot labels LD RD LW C RW at `unk_191D0`; line-editor titles at `unk_8CBE`: Goalies, Scoring 1, Scoring 2, Checking, Power Play 1, Power Play 2, Penalty Kill 1, Penalty Kill 2, indexed by `word_FFD5B2` 0..7).

`sub_171BE` (L53748) copies 56 bytes into team struct `$16A` (7 RAM lines):
```
if OptLine == 0 (line changes on): RAM[0..6] = data lines 2..8           ; skip data line 1, copy 14 longs
else (off):                        RAM[0]    = data line 1; RAM[1..6] = data lines 3..8   ; data line 2 is dropped
```
Which slots are filled depends on `tmap` (players on ice) through `priolist` = `0,1,2,4,3,5,6,$FF` (G, LD, RD, C, LW, RW, X), taking the first `tmap` entries. When `tmgoalie < 0` (pulled), the list starts one entry later, so 6 skaters LD, RD, C, LW, RW, X are used. Short-handed lines use G, LD, RD, C (+LW), so the RW slot of a PK line is unused at 5-on-4. Substitution of unavailable players (`sublist`) belongs to SetPlList and is not covered here.

Example, Boston data line 2 (Sc1): `01 13 12 07 03 0C 08 00` = Moog; LD Sweeney (slot 19), RD Bourque (18), LW Juneau (7), C Oates (3), RW Neely (12), X Kvartalnov (8).

### 1.5 Sim-score table used by the ratings byte R+0 (`getscore` L47815, `sctab` ROM `$13338`)

This applies to other games' ticker scores only, not to gameplay. `getscore(d0 = scoring team, d1 = opponent)`:
```
w[0..3]  = sctab[ (R0(scoring) & $70) >> 4 ]        ; offense row, 4 words
w[0..3] += sctab[ R0(opponent) & 7 ]               ; defense row, added element-wise (as two add.l)
goals = sub_10EB4(4 entries): r = randomd0(w0+w1+w2+w3);
        k = 3; while ((r -= w[k]) >= 0) k--;  return k     ; P(k) = w[k]/sum
```
`sctab` rows (goals 0,1,2,3):

| row | w0 | w1 | w2 | w3 |
|---|---|---|---|---|
| 0 | 43 | 30 | 23 | 4 |
| 1 | 39 | 32 | 24 | 5 |
| 2 | 35 | 33 | 26 | 6 |
| 3 | 30 | 34 | 30 | 6 |
| 4 | 26 | 36 | 30 | 8 |
| 5 | 22 | 37 | 31 | 10 |
| 6 | 19 | 38 | 31 | 12 |
| 7 | 15 | 38 | 32 | 15 |

`SetScore` (L47780) adds one such draw per team per simulated period to the game-struct scores at `$A`/`$C`.

Per-team ratings bytes (code meaning; hex `R+0`, then decoded):

| idx | abbr | R+0 (off/def) | PP + | PK - | home + | away - | goalie word |
|---|---|---|---|---|---|---|---|
| 0 | ANH | `$07` (0/7) | 2 | 0 | 1 | 3 | `$D600` |
| 1 | BOS | `$41` (4/1) | 1 | 2 | 2 | 1 | `$B400` |
| 2 | BUF | `$64` (6/4) | 0 | 1 | 2 | 1 | `$B250` |
| 3 | CGY | `$42` (4/2) | 0 | 0 | 0 | 0 | `$C500` |
| 4 | CHI | `$20` (2/0) | 0 | 1 | 2 | 1 | `$E400` |
| 5 | DAL | `$14` (1/4) | 0 | 1 | 0 | 0 | `$B500` |
| 6 | DET | `$73` (7/3) | 1 | 2 | 0 | 0 | `$D400` |
| 7 | EDM | `$16` (1/6) | 2 | 0 | 1 | 2 | `$D500` |
| 8 | FLA | `$07` (0/7) | 2 | 0 | 1 | 3 | `$D600` |
| 9 | HFD | `$17` (1/7) | 2 | 0 | 0 | 0 | `$A360` |
| 10 | LA | `$66` (6/6) | 2 | 1 | 1 | 1 | `$9620` |
| 11 | MTL | `$52` (5/2) | 1 | 1 | 2 | 1 | `$C500` |
| 12 | NJ | `$34` (3/4) | 1 | 1 | 1 | 2 | `$9800` |
| 13 | NYI | `$53` (5/3) | 1 | 2 | 0 | 0 | `$9700` |
| 14 | NYR | `$34` (3/4) | 1 | 1 | 1 | 1 | `$9600` |
| 15 | OTW | `$07` (0/7) | 2 | 0 | 1 | 3 | `$C500` |
| 16 | PHI | `$36` (3/6) | 2 | 0 | 2 | 2 | `$8630` |
| 17 | PIT | `$71` (7/1) | 0 | 2 | 2 | 1 | `$C500` |
| 18 | QUE | `$75` (7/5) | 1 | 2 | 0 | 0 | `$A600` |
| 19 | SJ | `$07` (0/7) | 2 | 0 | 1 | 2 | `$6630` |
| 20 | STL | `$22` (2/2) | 0 | 2 | 2 | 1 | `$D400` |
| 21 | TB | `$05` (0/5) | 2 | 0 | 0 | 0 | `$6840` |
| 22 | TOR | `$20` (2/0) | 0 | 2 | 1 | 1 | `$9610` |
| 23 | VAN | `$61` (6/1) | 2 | 0 | 1 | 1 | `$A600` |
| 24 | WSH | `$52` (5/2) | 0 | 2 | 1 | 1 | `$B500` |
| 25 | WPG | `$45` (4/5) | 1 | 1 | 1 | 1 | `$D600` |
| 26 | ASE | `$77` (7/7) | 0 | 2 | 0 | 0 | `$CBC0` |
| 27 | ASW | `$77` (7/7) | 0 | 2 | 0 | 0 | `$ED90` |

### 1.6 Extractor (ROM -> per-player ratings)

Language-neutral pseudocode. All words are big-endian. It reproduces exactly what the game reads.

```
rom = read("lst/nhl94.bin")
w(a) = rom[a]<<8 | rom[a+1];  l(a) = w(a)<<16 | w(a+2)
pstr(a): n = w(a); return (rom[a+2 .. a+n-1] with trailing 0x00 stripped as ASCII, a+n)

for t in 0..27:
  T = l(0x30E + 4*t)
  off = [w(T+0), w(T+2), w(T+4), w(T+6), w(T+8), w(T+0xA)]
  R = T + off[4]
  team.sim_off = (rom[R] >> 4) & 7;  team.sim_def = rom[R] & 7
  team.pp_bonus = rom[R+1] & 15;     team.pk_penalty = rom[R+1] >> 4
  team.home_bonus = rom[R+2] >> 4;   team.away_penalty = rom[R+2] & 15
  F = rom[R+3] >> 4;  D = rom[R+3] & 15
  gw = w(T + off[5]); G = 0; do { G++; gw = (gw << 4) & 0xFFFF } while gw != 0
  team.pal_home = [w(T+off[1] + 2*i) for i in 0..15]
  team.pal_away = [w(T+off[1] + 32 + 2*i) for i in 0..15]
  team.lines = [rom[T+off[3] + 8*k .. +7] for k in 0..7]      ; 1-based slots, see 1.4
  a = T + off[2]; (city,a) = pstr(a); (abbr,a) = pstr(a); (nick,a) = pstr(a); (arena,a) = pstr(a)
  a = T + off[0]; s = 0
  while w(a) != 2:
     (name, b) = pstr(a); A = rom[b .. b+7]; a = b + 8
     role = s < G ? "G" : (s < G+F ? "F" : "D")
     emit player(team=t, slot=s, name, role, A); s++
  assert s == G + F + D          ; true for all 28 records
```
Per player, from `A[0..7]` (`hi(x) = x>>4`, `lo(x) = x&15`):
```
jersey      = 10*hi(A0) + lo(A0)
weight_n    = hi(A1)        weight_lbs = 140 + 8*weight_n
agility     = lo(A1)        speed      = hi(A2)
off_aware   = lo(A2)        def_aware  = hi(A3)
shot_power  = lo(A3)        (goalie: puck_control)
checking    = hi(A4)        fighting   = (lo(A4) >> 1) & 7     handed = (A4 & 1) ? "R" : "L"
stickhand   = hi(A5)        shot_acc   = lo(A5)
endurance   = hi(A6)        (goalie: stick_right)
shot_bias   = lo(A6)        (goalie: stick_left)
pass_acc    = hi(A7)        (goalie: glove_right)
aggression  = lo(A7)        (goalie: glove_left)
```
Derived values (hot/cold = 0, no team bonus) follow from sections 2 and 3:
`display(n) = {0:25, 1:34, 2:43, 3:54, 4:72, 5:90, 6:99}`, and `ingame(n) = min(5n, 30)` = `0,5,10,15,20,25,30`.

**Test vectors** (raw bytes, then in-game struct with hc=0 and no bonuses, then display):

| team/slot | name | A0..A7 | struct `$67/$68/$69/$6A/$6B/$6C/$6D/$6E/$70/$71/$72/$73/$74/$75/$76` | overall |
|---|---|---|---|---|
| BOS 17 | Ray Bourque | `77 A5 44 65 60 55 62 52` | 80/25/20/10/7/25/25/25/10/25/30/10/0/30/1 (Lefty, 220 lb) | 99 |
| BOS 2 | Adam Oates | `12 75 46 53 31 54 50 61` | 56/25/20/7/9/15/20/30/0/25/25/5/0/15/0 (Righty, 196 lb) | 93 |
| ASE 3 | Mario Lemieux | `66 A5 46 44 33 66 60 62` | 80/25/20/7/10/20/30/30/0/30/30/10/2/15/0 | 99 (raw 100) |
| BOS 11 | Cam Neely | `08 A4 45 44 49 45 53 44` | 80/20/20/9/10/20/25/20/15/20/25/**4**/8/20/0 | 86 |
| ANH 16 | Bobby Dollas | `32 B2 11 21 21 10 21 11` | 88/10/5/14/12/5/0/5/5/5/10/5/0/10/0 | 37 (raw 25) |
| BOS 0 (G) | Andy Moog | `35 44 42 24 00 00 43 43` | 32/20/20/12/12/20/0/20/15/0/20/15/0/0/1 | 59 |
| ASE 0 (G) | Patrick Roy | `33 66 44 46 01 00 55 66` | 48/30/20/10/10/30/0/30/25/0/25/**14**/0/0/0 | 94 |

Display examples: Bourque Agl 90, Spd 72, OfA 72, DfA 99, ShP 90, Chk 99, Stk 90, ShA 90, End 99, Pas 90, Agr 43. Moog Agl 72, Spd 72, DfA 43, PuckCtl 72, StkR 72, StkL 54, GlvR 72, GlvL 54.

### 1.7 State of `src/teamdata94.asm` (1447 lines)

The file is the NHL '93 data, not '94:
- `TeamList` has 26 entries in '93 order: Boston..Winnipeg, then Campbell, Wales. It includes Minnesota and lacks Anaheim, Dallas and Florida.
- The header equates (`Playerdata=0, Palettedata=2, Teamname=4, ScoutReport=6, LineSets=8, ScoreOdds=10`) are '93 meanings. In '94, `+6` is lines, `+8` the ratings block and `+$A` the goalie word.
- Players are 8 `hex2` bytes with **no name records**, and there are 7 lines, not 8.
- The `.tn` strings of Ottawa (L849, "New York Rangers") and TampaBay (L1143, "Toronto Maple Leafs") are copy errors.

Do not extract from it. Use 1.6 against `lst/nhl94.bin`, or re-emit the asm from the ROM with `incbin`-free `dc.b` blocks at the listing labels `unk_37E` ... `unk_5330`.

---

## 2. In-game attribute loading

### setplayer (L51556)
- Purpose: put roster slot `d3` on the ice in object `a3` and load its ratings into SCstruct `$67-$76`. Callers: `assbench+132` (line-change arrival, L37966), `puckpenshot` (L41362, L41412: penalty-shot setup of the shooter and goalie, with `d3 = $66(a3)`, which may first be set to the chosen shooter `byte_FFD593`/`byte_FFD585`), `sub_129D2` (L46946, after `Setplass`), `sub_1592C` (L51433), and `SetPersonel _notnear` (L51478). Every caller sets `$34` (position) first.
- Inputs: `d3` = roster slot (byte, 0..25), `a3` = SCstruct; `$62` bit 6 (team), `$34` (position, 0 = goalie); globals `sflags2`, `gsp`, `gameclock`, `HmGoals`, `AwGoals`, `OptPerlen`; team struct `$66+2*slot` (tmpdst), `$1E`; ROM record; hot/cold table.
- Outputs: `$63` bit 6 cleared; `$66` = slot; tmpdst[slot] = -1; possibly an assignment inserted; `$58` cleared; `$62` bit 5 cleared; `$67,$68,$69,$6A,$6B,$6C,$6D,$6E,$6F,$70,$71,$72,$73,$74,$75,$76`; byte `$04` bit 3; `PPBonus`, `PKBonus`, `HmAwBonus`, `ThirdPBonus`; `word_FFBF14`.

Steps:
1. `bclr #6,$63(a3)`. In '94 this is the "injured in a fight" flag that divides max speed by 8 in playeracc.
2. `a0` = team struct (`HmShots`, `+$364` if `$62` bit 6 set). `$66(a3) = d3`.
3. `d1 = tmpdst[d3]` (word at `$66(a0, 2*d3)`):
   - if `d1 >= 0` (was in the penalty box): `assinsert(d0 = $A /*aepen*/)`, then `bclr #5,$62(a3)` and `clr.w $58(a3)`;
   - else if `d1 == -2` (bench): `assinsert(d0 = 9 /*assben*/)`, then the same two clears;
   - else (-1, -3, -4): nothing.
   Then `tmpdst[d3] = -1` (on ice).
4. `a0 = $1E(team)` (ROM record T), pushed. `a0 = T + word[T+8]` (ratings block R). `clr.l (PPBonus)`, which zeroes all 4 bonus bytes.
5. If `$34(a3) == 0` (goalie): skip to step 9. **Goalies get no bonuses.**
6. Power play: if `sflags2` bit 5 (PP in progress): `chkpk2` (L40168) returns Z set when `sflags2` bit 6 != this team's `$62` bit 6 (this team is short-handed):
   - not killing (on the PP): `PPBonus = R[1] & $0F`;
   - killing: `PKBonus = -(R[1] >> 4)` (byte negate).
7. Home/away: `d0 = -(R[2] & $0F)` (away penalty). If home (`$62` bit 6 clear), `d0 = R[2] >> 4`. `HmAwBonus = d0`.
8. 3rd-period/OT trailing bonus:
   ```
   if gsp < 2: goto 9
   if gsp == 2:                                   ; 3rd period
       half = ClockLength() >> 1                  ; lsr.w: 150, 300, 600 or 15
       if half > gameclock (signed word compare): goto 9      ; bgt
   ; gsp > 2 (OT) jumps straight here
   diff = HmGoals - AwGoals
   if diff == 0: ThirdPBonus = 2
   else if home and diff < 0: ThirdPBonus = 2
   else if away and diff > 0: ThirdPBonus = 2     ; eori #8,ccr flips N, then bpl skips the leader
   ```
   **Quirk (listing comment "bug"):** because the clock counts down, the 3rd-period bonus applies while `gameclock >= half`, i.e. during the **first** half of the 3rd period. In OT it always applies to both teams (the score is tied). `ClockLength` clobbers `a0`, but `a0` is restored from the stack in step 9, so this is harmless.
9. `_playdatamove`: `a0 = T` (popped). `a0 += word[T]` (player list). Walk `d3+1` records (`a0 += word[a0]; a0 += 8`), then `a0 -= 8`, so `a0` = attribute bytes `A[0..7]` of slot d3.
10. Load, in this exact order (`AC(n)` = AttributeCalc on nibble n; `LIM(x)` = checkattriblimits; all adds are byte adds of the signed bonus bytes):
    ```
    $6F = A0                                         ; jersey BCD
    $67 = (A1 & $F0) >> 1                            ; weight nibble * 8, 0..120, no hot/cold
    $68 = AC(A1 & $F)            [FFBF14=3]          ; agility (legstr)
    $69 = AC(A2 >> 4)            [4]                 ; speed (legspd)
    t   = LIM(AC(A2 & $F) [5] + PPBonus + PKBonus + HmAwBonus + ThirdPBonus)
    $6A = ((((t >> 1) ^ $0F) + $0F) & $FF) >> 1      ; aioff = (30 - (t>>1)) >> 1, 7..15
    t   = LIM(AC(A3 >> 4) [6] + HmAwBonus)
    $6B = same transform                             ; aidef, 7..15
    $6C = AC(A3 & $F)            [7]                 ; shotspd (goalie: puck control), no bonus, no LIM
    $75 = LIM(AC(A4 >> 4) [8] + ThirdPBonus)          ; checking
    byte $04: bclr #3; $76 = (A4 & 1) ^ 1; if $76 == 0 then bset #3   ; righty -> H-flip bit set
    $74 = A4 & $0E                                   ; fighting*2, raw, no AC
    $71 = LIM(AC(A5 >> 4) [$A] + PPBonus + PKBonus + HmAwBonus)   ; stickhand
    $6D = LIM(AC(A5 & $F) [$B] + PPBonus + PKBonus + HmAwBonus)   ; shotacc
    $72 = AC(A6 >> 4)            [$C]                ; endurance (goalie: GSSright)
    $70 = LIM(AC(A6 & $F) [$D] + 2*ThirdPBonus)       ; spodds / shot-pass bias (goalie: GSSleft)
    $6E = LIM(AC(A7 >> 4) [$E] + PPBonus + HmAwBonus) ; passacc (goalie: GGSright)
    $73 = AC(A7 & $F) [$F] & $0F                     ; aggress (goalie: GGSleft) -- masked to 4 bits AFTER scaling
    ```
- Quirks (port as-is):
  - **`$73` wraps.** AC returns 0..30, and `& $F` maps it to `AC mod 16`. With hc = 0: nibble 0..6 -> 0, 5, 10, 15, 4, 9, 14. A skater with Aggressiveness 4 gets `$73 = 4`, less than one with 3 (15). This also hits the goalie **Glove Left** save value (`puckgoalie` uses `15 + $73`). The listing comment ("so max is 15") does not mention the wrap.
  - Bonuses are evaluated only when setplayer runs (line change, faceoff setup), not continuously.
  - `aioff`/`aidef` are frame-countdown reloads (`assdefo` L38390: `move.b $6A(a3),$40(a3)`), so lower is better. The transform maps t = 0..30 to 15..7: t 0,1 -> 15; 2..5 -> 14; 6..9 -> 13; 10..13 -> 12; 14..17 -> 11; 18..21 -> 10; 22..25 -> 9; 26..29 -> 8; 30 -> 7.
  - The PK penalty also lowers `$6A`. A PK team keeps its HmAw bonus.
  - `word_FFBF14` is written before every AC call but never read (see AttributeCalc).

### checkattriblimits (L51753)
- Clamps the byte `d3` to 0..30.
- `tst.b d3; bpl` -> if bit 7 is set, `clr.w d3`. `cmp.b #$1E,d3; ble` (signed) -> if > 30, `d3 = $1E`.

### AttributeCalc (L959917)
- Purpose: scale a 0-15 rating nibble to the 0..30 in-game range and add per-game form. Callers: setplayer only.
- Inputs: `d3.w` = nibble (high byte 0); `a3` (`$62` bit 6, `$66` slot). Output: `d3.w` = 0..30. Preserves d0-d2/a1.
```
hc  = (signed byte) hotcold[team][slot*16 + 0]     ; ALWAYS offset 0 of the slot's 16-byte block
q   = trunc(hc / 3)                                ; ext.w, ext.l, divs.w #3 -> quotient (toward zero)
v   = d3*5 + q                                     ; asl.w #2 + add
if v < 0 (bmi): v = 0
else if v >= 30: v = 30                            ; cmp.w #$1E; blt keeps < 30
d3  = v & $FF
```
- **Quirk/bug:** the routine loads `word_FFBF14` (the attribute index) into d1 and then `clr.w d1` overwrites it. Every in-game attribute of a player gets the **same** hot/cold value: block offset 0, which the display code associates with the jersey-tens nibble and never shows. So in-game form is one number per player per game.
- `q` distribution, with hc uniform on -9..8 (18 values): -3: 1/18, -2: 3/18, -1: 3/18, 0: 5/18, +1: 3/18, +2: 3/18 (mean -1/6).
- Range per nibble n: n=0 -> 0..2; 1 -> 2..7; 2 -> 7..12; 3 -> 12..17; 4 -> 17..22; 5 -> 22..27; 6 -> 27..30 (30 when q >= 0); n >= 7 -> always 30.

### Create_HotCold_Table (L959871)
- Purpose: roll each player's form for the game. Input `a0` = team struct.
- `for d1 = $19F downto 0: byte[a0 + $1A2 + d1] = randomd0s(9)` -> each of the 416 bytes (26 slots x 16) is uniform in **-9..+8** (`randomd0(18) - 9`; the comment "-9 - +8" is right; the comment "26*8*2" is wrong, it is 26*16 for one team).
- Callers:
  - `sub_FCC76` (L969615, called from `Opening2` at PeriodOver+F6 before every new game, when `word_FFC2FA` bit 0, shootout mode, is clear): `clearTeamStats`, then home and away tables, then `sub_F71A2`.
  - `StartGame` L29773/29775 (only when `word_FFC2FA` bit 0 is set, i.e. shootout).
- Persistence: `clearTeamStats` (L53690) copies both 416-byte tables to `$FFD6D2`/`$FFD872`, zeroes both team structs (`$364` bytes each), and copies the tables back. So hot/cold survives the stats clear and lasts the whole game.
- Related, `sub_F71A2`/`sub_F71F0` (L960015, "hot/cold players" for the pregame screen): for each of the 6 slots of **data line 1** (G..RW), `sum = Σ hotcold[slot*16 + k]` for k = 3..15 except 9 and 13 (byte add, signed compare). The 6 (slot, sum) pairs are bubble-sorted descending by sum. The first (hottest) goes to `$FFBF5E`/`$FFBF5C` and the last (coldest) to `$FFBF62`/`$FFBF60`, for home/away.

### chkpk2 (L40168)
- Returns the Z flag set when this player's team is short-handed: `Z = (sflags2 bit6 == 0) XOR (pfteam == 0)`, computed by EOR-ing the two saved SR words. Preserves d0/d1. `chkpk` (L40159) is the same, except that when no PP is in progress it returns Z clear ("not killing"): `btst #5,(sflags2)` leaves Z = 1, then `eori #4,ccr` flips it.

### Stored -> in-game summary (hc = per-player AC offset q in -3..2; bonuses as above)

| struct | name | formula | range |
|---|---|---|---|
| `$67` | weight | `hi(A1)*8` | 0..120 (ROM 8..112) |
| `$68` | legstr / agility | `AC(lo A1)` | 0..30 |
| `$69` | legspd / speed | `AC(hi A2)` | 0..30 |
| `$6A` | aioff | `(30 - (LIM(AC(lo A2)+PP+PK+HA+P3) >> 1)) >> 1` | 7..15 |
| `$6B` | aidef | `(30 - (LIM(AC(hi A3)+HA) >> 1)) >> 1` | 7..15 |
| `$6C` | shotspd (G: puck control) | `AC(lo A3)` | 0..30 |
| `$6D` | shotacc | `LIM(AC(lo A5)+PP+PK+HA)` | 0..30 |
| `$6E` | passacc (G: glove right) | `LIM(AC(hi A7)+PP+HA)` | 0..30 |
| `$6F` | jersey (BCD) | `A0` | `$00..$99` |
| `$70` | spodds (G: stick left) | `LIM(AC(lo A6)+2*P3)` | 0..30 |
| `$71` | stickhand | `LIM(AC(hi A5)+PP+PK+HA)` | 0..30 |
| `$72` | endurance (G: stick right) | `AC(hi A6)` | 0..30 |
| `$73` | aggress (G: glove left) | `AC(lo A7) & 15` | 0..15 (wraps) |
| `$74` | fighting | `lo(A4) & $E` | 0..14 even (ROM 0..12) |
| `$75` | checking | `LIM(AC(hi A4)+P3)` | 0..30 |
| `$76` | handed | `(A4 & 1) ^ 1` | 1 = left |

PP 0..15 (ROM 0..2), PK -15..0 (ROM -2..0), HA -15..15 (ROM -3..+2), P3 0 or 2. All four are 0 for goalies.

---

## 3. Display attribute math (25-99 ratings)

### PAttribColumns (L58201, ROM `$193F8`) / GAttribColumns (L58514, ROM `$1955A`)
Each entry is a length-prefixed 16-character header string followed by a long `d4`: the high word is a nibble bitmask (bit n = nibble n, numbering of 1.3) and the low word is the `attribjmp` offset. The list ends with `$FFFF`. The first entry is " Status" with `d4 = 0`.

| skater column | d4 | nibble | | goalie column | d4 | nibble |
|---|---|---|---|---|---|---|
| Overall | `$1FBA000A` | 12,11,10,9,8,7,5,4,3,1 | | Overall | `$130F000A` | 12,9,8,3,2,1,0 |
| Energy | `$00000002` | (energy) | | Agility | `$1000000A` | 12 |
| Agility | `$1000000A` | 12 | | Speed | `$0800000A` | 11 |
| Speed | `$0800000A` | 11 | | Glove Hand | `$00400004` | 6 (bit 0) |
| Handed | `$00400004` | 6 (bit 0) | | Def. Awareness | `$0200000A` | 9 |
| Off. Awareness | `$0400000A` | 10 | | Puck Control | `$0100000A` | 8 |
| Def. Awareness | `$0200000A` | 9 | | Stick Right | `$0008000A` | 3 |
| Shot Power | `$0100000A` | 8 | | Stick Left | `$0004000A` | 2 |
| Shot Accuracy | `$0010000A` | 4 | | Glove Right | `$0002000A` | 1 |
| Pass Accuracy | `$0002000A` | 1 | | Glove Left | `$0001000A` | 0 |
| Stick Handling | `$0020000A` | 5 | | Weight | `$20000006` | 13 |
| Weight | `$20000006` | 13 | | | | |
| Endurance | `$0008000A` | 3 | | | | |
| Aggressiveness | `$0001000A` | 0 | | | | |
| Checking | `$0080000A` | 7 | | | | |

The ROM strings are "[   Checking    " and "[    Weight     " (closing bracket missing). There is no Fight column (attribjmp `8` is unused by both tables). `dword_19420` = the skater Overall long, `dword_19582` = the goalie Overall long.

### getNameandAttrib (L32053) / attribjmp (L32074)
- Inputs: `d0` = roster slot, `d4` = column long, `a2` = team struct. Prints the name (`getname`, `print`) and sets `printx = $1E`.
- If `d4.w <= 2` (unsigned): jump directly. Otherwise `CalcAttrib` (which swaps d4), then `swap d4`. Then jump to `attribjmp + attribjmp[d4.w]`:

| d4.w | offset | handler |
|---|---|---|
| 0 | `$0C` | status: `v = tmpdst[d0]`. If `v < 0`: `i = ~v` (-1 -> 0 "Ice", -2 -> 1 "Bench", -3 -> 2 "Injury P", -4 -> 3 "Injury G"; `i > 3` -> 1). If `v >= 0`: when bit 12 is set, "Injury G"; otherwise print `v & $FFF` as time, followed by "    " or " C  " when bit 14 is set. Strings at `unk_8DEC`. |
| 2 | `$98` | energy: `d0 = tmpde[d0] / 40` (divu `#$28`), capped at 100. Printed without AttribAdjust. |
| 4 | `$E0` | handedness: `idx = (d0 & 1) ^ 1`. `Handedlist[0] = "Righty"`, `[1] = "Lefty"`, so raw bit 0 = 1 means Righty. |
| 6 | `$106` | weight: `d0*8 + $8C` -> 148..252 "lb" (140 + 8n). |
| 8 | `$B2` | fight (unused): `d0 &= $E; d1 -= 1`, then falls into DispAttribValue. |
| `$A` | `$B8` | regular: DispAttribValue. |

### CalcAttrib (L966169)
- Purpose: value for a display column. Inputs: `d0` = slot, `d4` = column long, `a2` = team struct. Outputs: `d0` = value, `d1` = divisor (100 or larger); `d4` is left swapped.
- Weight table: `AttribWgtList` by default; `OvrPlayerWgtList` if `d4 == dword_19420`; `OvrGoalWgtList` if `d4 == dword_19582`.
- `a0` = end of slot d0's 8 attribute bytes (same walk as setplayer, without the `-8`); `a4 = team + $1A2 + 16*d0 + 16`; `OvrDivisor = OvrDividend = 0`; `d0 = d1 = 0`; `swap d4`.
- For `d2 = 15 downto 0`, if bit d2 of `d4.w` is set:
  ```
  n = nibble d2 (byte a0 - 1 - (d2>>1); high nibble if d2 odd)
  if d2 == 13 (weight) or d2 == 6 (hand/fight): d0 += n; d1 += 100; continue      ; raw, no hot/cold
  w = list[d2]
  if w != 2: n = (n * w) >> 1        ; loop adds n (w-1) times, then asr #1 (floor)
  hcd = (signed byte) hotcold[slot*16 + 15 - d2]
  if list != AttribWgtList:                      ; Overall
      OvrDivisor += hcd; OvrDividend += 1
  else:                                          ; single attribute
      n = n*18 (asl #4 + 2n); n.b = n.b + hcd (byte add); if n.b bit 7 set: n.b = 0
  d0 += n; d1 += 100
  ```
- After the loop, for Overall only: `d1 = 100; d0 += trunc(OvrDivisor / OvrDividend)` (divs.w, low-word quotient).
- Final cap: `if d0 >= d1: d1 = d0; d0 = d0 - 1` (signed word compare). Combined with `d0*100/d1`, this displays any value >= 100 as 99.
- Weight lists, indexed by nibble number d2 = 0..15 (dumped from L966281/966297/966313):
  - `OvrPlayerWgtList` = `2,2,2,2,4,6,2,4,2,4,6,6,4,2,2,2`
  - `OvrGoalWgtList` = `2,2,2,2,2,2,2,2,9,9,2,2,9,2,2,2`
  - `AttribWgtList` = `2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2` (w=2 means "no reweighting")
- Skater Overall raw = `2*Agl + 3*Spd + 3*OfA + 2*DfA + 1*ShP + 2*Chk + 3*Stk + 2*ShA + 1*End + 1*Pas` + trunc(mean of those 10 display hc bytes). Raw range 0..120 (+hc).
- Goalie Overall raw = `floor(9*Agl/2) + floor(9*DfA/2) + floor(9*PuckCtl/2) + StkR + StkL + GlvR + GlvL` + trunc(mean of 7 hc). Raw range 0..105 (+hc).
- Quirks:
  - Single-attribute display uses `n*18 + hcd` with the full -9..8 hc (not /3) and a per-attribute hc byte. The in-game value uses `trunc(hotcold[slot*16 + 0] / 3)` for every attribute, so display "hot/cold" does not match in-game form.
  - For n >= 7 (not in the ROM), `n*18 + hcd` can reach >= 128, and the bit-7 test zeroes it.
  - `OvrDivisor`/`OvrDividend` names are swapped.

### DispAttribValue (L32183)
`d0 = (d0 * 100) / d1` (mulu, divu, quotient), then `AttribAdjust`, then print 4 characters (`DeterStrLength?` with `d1 = 4`).

### AttribAdjust (L975193)
`if d0 < 50 (signed): d0 = (d0 >> 1) + 25` (asr). Values >= 50 are unchanged. Display range 25..99.

### Display formulas and ranges
- Single attribute, nibble n, display hc byte h (-9..8): `v = 18n + h` (0 if negative); `v >= 100 -> 99`; `v < 50 -> (v >> 1) + 25`; otherwise v.
  - With h = 0: n 0..6 -> 25, 34, 43, 54, 72, 90, 99.
  - Ranges over h: n=0 -> 25..29; 1 -> 29..38; 2 -> 38..47; 3 -> 47..62; 4 -> 63..80; 5 -> 81..98; 6 -> 99.
- Overall: `raw = weighted sum + trunc(mean hc)`; `>= 100 -> 99`; `< 50 -> raw/2 + 25`.
- Weight 148..252 lb. Energy 0..100. Handed Righty/Lefty.
- Other callers using the same CalcAttrib -> `*100/d1` -> AttribAdjust chain: `sub_FA8AC` (L966053, an Overall readout on another screen; `PAttribColumns` carries the listing comment "start point for shootout", so probably the shootout setup) and `sub_FD1FE` (L970247/970270).

---

## 4. Energy

Storage: `tmpde[slot]` word at team struct `$32 + 2*slot`, 0..`$1000` (4096 = full). It is indexed by roster slot, not by object, so a player keeps his energy on the bench.

### getpde (L51207)
- `a2` = team struct of `a3` (`HmShots`, `+$364` if `$62` bit 6). `d1 = 2 * (signed byte) $66(a3)`. `d0 = tmpde = word $32(a2,d1)`.
- Clobbers a2 and d1. setpde relies on both.

### setpde (L51224)
- `if d0 < 0 (signed): d0 = 0`; `word $32(a2,d1) = d0`. There is no upper clamp. Also leaves the clamped value in d0.

### makepde (L51186)
- Purpose: scale a rating by energy. Input `d0.b` = value (ext.w), `a0` = player. Preserves d1/a2/a3.
- `e = getpde(player a0)`; if `byte_FFC2FC` bit 4 ("Auto" lines): `e = $1000`. `d0 = high word of ((value * e) << 4)`, sign-extended to long. So `d0 = floor(value * e / 4096)`, i.e. 0..value.
- Callers: `doshot+90` (L37553: `shotspd>>1` scaled, +`$14`, times `passspeed`), `puckstick` (L50569-50599: `stickhand>>1` scaled, for the steal roll and the `nopuck` timers).

### Drain in playeracc (end of routine, label `_sube`, L43828-43850)
Runs on every playeracc call, after the velocity update, whether or not the speed cap blocked it:
```
if OptLine != 0: return                         ; line changes off: no drain
if (VDP_CNTR & $7F) != 0: return                ; HV counter low 7 bits as a random gate
e = getpde() - $21                              ; -33
if e < $C00 (signed): setpde(e); return         ; below 75%: flat -33 (clamped at 0)
e += endurance_byte($72) >> 1                   ; ext.w, lsr.w: 0..15
setpde(e)
if ($72 & 1) and (vcount & 1): setpde(e + 1)
```
- Net drain per event: below `$C00 + 33` it is a flat 33. Otherwise `33 - (end>>1)`, minus 1 more half the time when end is odd. With end = 30 that is 18. With end = 0 it is 33.
- Goalies are drained too. `goalieacc` (L43477) ends with `bra.w playeracc` on two paths (`loc_10A3C`, `_d11`), and `assgoaliecpu` branches to `playeracc` (L39498). So a goalie's `tmpde` drains by the same rule, using the goalie's `$72` (Stick Right) as "endurance".
- The gate depends on hardware timing (the H counter at the moment of the read). The H counter hits values with low 7 bits = 0 (`$00`, `$80`) on 2 of ~171 positions in H32 mode, 2 of ~211 in H40. Port with a random 1-in-N gate: N = 128 is the nominal value, 86-106 is the hardware-implied range. See UNRESOLVED.

### Drain in burst (L36830)
```
e = getpde()
if OptLine == 0: e -= $CC; setpde(e)            ; -204 per burst, clamped at 0 (also clamps e)
if byte_FFC2FC bit 4: e = $1000
impulse = e >> 7                                ; 0..32, applied along facedir via dirtab, then SPA $C5E
```
The rest of burst (impulse application) is outside this spec.

### Bench recovery (`periodiceevents` -> `loc_79F8`, L29963)
- `periodiceevents` (L29940) is called by every `DoGameFrame` with `d7` = vblanks elapsed. If `sflags` bit 7 is set, it returns early. `lldisp -= d7`; when it goes negative, `lldisp += $18` (24 vblanks = one game-clock second), and the once-per-second jobs run: ChkGoalies, UpdateCwdExcite, sub_7A34, **loc_79F8**, loc_79EA, updatepwrplay.
- `loc_79F8`: if `OptLine != 0`, exit. For both teams and all 26 slots: if `tmpdst[slot] == -2` (bench): `tmpde[slot] += 9`, capped at `$1000`.
- Recovery = +9 per 24 vblanks (+22.5/s at 60 Hz). It runs while the clock is stopped too, since only `sflags` bit 7 blocks it. Penalty-box and injured players do not recover.

### Energy resets
- `sub_130BE` (L47595), at the start of each period: `Intermission` -> `sub_13056` -> `ResetBench`, `sub_13068` -> `sub_130BE`. This also covers game start, because `StartGame` -> `loc_17278` -> Intermission. For every slot, unless `tmpdst == -4` (injured for game): `tmpde = $1000`, and if `tmpdst == -3` (injured for period) then `tmpdst = -2` (back to bench). Game-injured players keep their energy.
- `sub_13098` (L47575), on a **timeout** (ROM `$9DD0`, sets team `$30` bit 2): intended to skip injured players, but both tests branch to "set", so **every** slot gets `tmpde = $1000` (quirk: `cmpi #$FFFD; bne set; cmpi #$FFFC; bne set`, and a value equal to `$FFFD` is never `$FFFC`).
- `clearTeamStats` (L53690) zeroes the whole struct, including energy. Intermission then refills it.
- `restoreteams` (L29800) sets `tmap = 6` and all `tmpdst = -2`.

### Energy readers
- `getlinee` (L47394), for CompLine AI line changes: average energy of a RAM line's skaters. For `i = tmap-1 downto 0`: `p = priolist[i]`; if p == 0 skip; `r = line[p]` (1-based); `sum += word $30(a2, 2r)` (= `tmpde[r-1]`); count++. Returns `sum / count` (divu). If a line slot were 0, it would read `$30(a2)` (tmflags); this never happens with ROM lines.
- `sub_12EF6` (L47424): average `tmpde` of the team's on-ice objects with `$34 > 0` (skaters) among the 6 at `tmsort`. Returns 0 if there are none.
- Display: `tmpde/40`, capped at 100 (section 3).
- `playeracc` (already ported): max-speed index uses `((legspd >> 1) * e * 16 >> 16) * 4`.

---

## 5. Other small routines in scope

### loadTeamStruct (L47539)
Returns `a2` = own team struct, `a1` = other team struct, for player `a3`: `a2 = HmShots; a1 = a2 + $364`; if `$62` bit 6 is set, `exg a1,a2`. This is a RAM team-struct helper, not ROM team data.

### sub_17190 / sub_171BE (L53733 / L53748): team setup
For home (`HomeTeam`, struct `HmShots`, `$22 = $B04A`) and away (`VisTeam`, `AwShots`, `$22 = $B34A`): `$28 = team number; $1E = TeamPtr[team]`; line copy as in 1.4.

### sub_FAE26 (L966582)
Chooses sprite/graphics data per slot: compares slot d0 with G (goalie-word count). For goalies it picks `unk_C6F02` if A4 bit 0 = 1, else `unk_C726C`. For skaters it picks `unk_C6B98` (bit 0 = 1) or `unk_C682E`. So handedness also selects art sets.

---

## UNRESOLVED

1. **Exact drain probability.** The `playeracc` energy drain fires when `(VDP_CNTR & $7F) == 0`. The real rate depends on when in the scanline the instruction executes. The nominal rate is 1/128; the hardware H-counter layout suggests about 1/86 (H32) to 1/106 (H40). The game screen mode was not pinned down: `setvram` uses `disflags` bit 1 to choose H32/H40. Tried reading `setvram` L44805.
2. **Goalie fatigue effect.** Goalies reach the playeracc drain (see section 4), and their max speed in playeracc is energy-scaled like skaters'. It was not checked whether any goalie-specific save code reads energy. `setpde` is called only by burst (L36836) and playeracc (L43842/43848).
3. **Goalie-word nibble values** (`$B400` etc.) are never read except to count the nibbles. Their intended meaning (goalie quality?) is unknown.
4. **Defense count `R+3` low nibble.** No reader was found (`sub_9F7E`/`sub_9F5C` read only the high nibble). It equals players-G-F in every record, so the extractor can use it as a check.
5. **Team comparison ratings** (ROM `$FD024`: Shooting, Skating, Passing, Defense, Checking, Fighting, Goalkeeping, Power Play Adv., Home Team Adv., Overall) are computed elsewhere (around `sub_FA8AC`/`sub_FD1FE`). Their formulas are not specified here.
6. **Status display bits 12/14** of a non-negative `tmpdst` ("Injury G" and " C  " suffix). The meaning of bit 14 ("C") in the penalty-box value was not traced.
