# NHL '94 (Genesis): sound driver, sequence data, sound/music ids and the offline renders

Source: `lst/nhl94.bin.lst` (IDA listing, line numbers written `Lnnnnn`) and `lst/nhl94.bin` (CRC32 `$9438F5DD`). ROM addresses are written `$xxxxx`, 68000 RAM `$FFxxxx`, Z80 RAM `Z:$xxxx`. Code the listing shows as data (the Z80 driver, the `$Bx` handler) was decoded from the ROM bytes. Everything in §1-§5 was confirmed by **running the retail code**: `tools/extract/audio.py` executes the 68000 driver in unicorn and the Z80 driver on a Z80 core, and drives a YM2612 model with what they write (§8). This document extends `animation_assets.md` §5, which it replaces where they disagree.

---

## 0. Quick facts

- **All music and effects come from one 68000-side sequencer**, `p_initfx` (L61549) + `MusicVB` (L61792), which reads MIDI-like event lists (`unk_2C648`, 123 ids `$00..$7A`). It runs once per VBlank: 1 tick = 1 NTSC frame (59.92 Hz). The PAL fix-up runs it twice on every 6th frame (§2.3).
- **The 68000 never touches the YM2612.** It builds a 33-byte command block and copies it into Z80 RAM. A **Z80 driver** (`$1AD90`, `$295` bytes) writes the YM registers and plays PCM through the YM2612 DAC (§4).
- **Voices:** 5 FM voices (YM channels 1-5) plus 1 DAC voice (YM channel 6 in DAC mode). The **PSG is not used** by the driver. The only PSG user is the crowd noise (`updatesound` L52982, `animation_assets.md` §5.3). Every FM patch pans **centre**, so retail sound is mono.
- **Ids:** `$00..$2F` are effects. `$30..$77` are 72 single-voice organ tunes (instrument `$0B`, a few with DAC drums). `$78..$7A` are looping multi-voice songs. An id ≥ `$30` first stops the current music (`sub_1A304`). The game starts some effects (`$0B $0C $0D $0F`, crowd reactions) with `song`. They are still effects and **do not stop the music**.
- **No priorities between effects and music**, except on the DAC. An FM note takes a free voice, or else steals the oldest voice, whoever owns it. A DAC note replaces the sounding DAC note only if its instrument number is **higher** (§6).
- **Offline renders:** `tools/extract/audio.py` writes `godot/assets/audio/sfx/sfx_XX.wav` (ids `$00..$2F`), `music/song_XX.wav` (`$30..$7A` and `$0B $0C $0D $0F`) and `audio.json`. The format is 44.1 kHz 16-bit mono. Loop points are in the WAV `smpl` chunk and in the JSON (§8).

---

## 1. Entry points

| Routine | Line | Address | What |
|---|---|---|---|
| `sfx` | L44279 | | Pops a word id, ignores it if negative, sets `lastsfx`, calls `p_initfx`. |
| `song` | L44297 | | Same, but leaves `lastsfx` alone. Ids < `$30` behave exactly like `sfx`. |
| `p_initfx` | L61549 | `$1A294` | Starts a sequence in a slot (§2.1). |
| `sub_1A304` | L61594 | `$1A304` | Stops music: frees the first slot whose pointer ≥ `off_2C708` (= `$2CEF2`, the first song sequence). It keys off that slot's voices (`sub_1A64C`) and sets their TL to `$7F`. Called by `p_initfx` for ids ≥ `$30`, by `clockcont` (before the horn), by `Stop4Pen` (before the whistle) and by `DoGameFrame` (before the delayed home-goal tune). |
| `AllSndOff` | L61529 | `$1A264` | Resets all slots and voices (`sub_1AD54`), keys off and mutes every channel, freezes the DAC. Called at boot, by `StartPer` (L29853, every period start) and at screen changes. |
| `MusicVB` | L61792 | `$1A50A` | Per VBlank: reads the pads (`ReadJoyData`, which also takes the Z80 bus), steps all 8 slots, sends the command block, ages the voices. |
| `Z80_LoadROM` | L63070 | `$1ACC2` | Copies the Z80 driver to `Z:$0000` and builds the DAC volume tables (§4.3). |

`lastsfx` is replayed at L34765 (`move.w (lastsfx).w,-(sp); bsr sfx`).

---

## 2. The 68000 sequencer

### 2.1 Slots (`unk_FFD3D4`, 8 x 6 bytes)

`{long pointer, word tick counter}`. A free slot has pointer `$FFFFFFFF`.

`p_initfx(d0)` works as follows:
- It returns if `d0 > $7A`, and calls `sub_1A304` if `d0 ≥ $30`.
- It picks the slot with the **smallest signed pointer** (on ties, the first). If that pointer is not negative, every slot is busy and the request is **dropped**.
- It sets pointer = `unk_2C648[d0]` and counter = first byte of the sequence (that event's delta).
- It resets that slot's channel records for MIDI channels 0-7: instrument 0, bend 0, volume `$7F`.

Slot index `i` has the slot code `7 - i`. Channel records are at `$FFD1A4 + ch*$40 + code*8`: `+0` word bend (value - `$2000`), `+3` instrument, `+4` word volume (`$7F`).

### 2.2 Events (`sub_1A5C0` L61863)

Every event is 4 bytes: `[delta, status, d1, d2]`. `delta` is the number of ticks to wait **after the previous event**. Per tick, each slot decrements its counter. When the counter goes negative, it runs events until one has a non-zero delta: that event's delta (byte 0 of the next event) reloads the counter. The first event therefore runs on tick `delta0`, and event *k* on tick `sum(delta[0..k])`. Tick 0 is the first `MusicVB` after the call.

| status | handler | meaning |
|---|---|---|
| `$00` | inline | **End/jump.** If the word at +2 is negative (`$FFFF`), the slot is freed. Otherwise the long at +2 is a new pointer, and the event there runs **at once**, with its own delta ignored. Only `$78/$79/$7A` jump: `$78` to its first event, `$79`/`$7A` to their second (start + 4). |
| `$8c` | `loc_1A61A` | Note off, `d1` = note. It finds the keyed voice whose code (`ch<<3 | slotcode`) and note both match. |
| `$9c` | `$1A68E` | Note on: `d1` = note (0-127), `d2` = velocity. Velocity 0 = note off. |
| `$Bc` | `$1AC82` | Controller. Only `d1 = 7` (volume) does anything: `d2` → channel volume, re-applied to that channel's sounding voices. |
| `$Cc` | `$1AC30` | Program change: `d1` → channel instrument. Below `$60` it is an FM patch; `$60..$6E` are DAC samples. |
| `$Ec` | `$1AC4A` | Pitch bend: word `d1:d2` - `$2000` → channel bend, re-pitches that channel's voices. |
| `$Ac $Dc $Fc` | `$1ACC0` | Ignored (`rts`). Sfx `$00` starts with four `00 FF FF FF` no-ops: a 0.5 s delay before the siren. |

`c` = MIDI channel (low nibble). The jump table is `unk_1A60A`, indexed by `(status & $70) >> 3`.

### 2.3 MusicVB (L61792)

1. `ReadJoyData`.
2. Clear the command block (`dword_FFD182`, `byte_FFD186`, the "dirty" flag `byte_FFD180`).
3. Step slots 0..7 (`d7` = slot code 7..0).
4. PAL only: if `word_FFDEF2` bit 0 is set (bit 0 of the VDP status read at boot = PAL), step the slots again whenever `word_FFD070` counts below 0 (every 6th frame). That gives 7 ticks per 6 frames, close to the NTSC tempo.
5. If anything is dirty, send the block (`sub_1A574`, §4.2).
6. Age every voice: byte +5, saturating at `$FF`.

### 2.4 Voices (`unk_FFD3A4`, 6 x 8 bytes)

`+0` code (`ch<<3 | slotcode`), `+1` note, `+2` velocity, `+3` instrument, `+4` YM channel (0, 1, 2, 4, 5, 6: the key-on code; set by `sub_1AD54`), `+5` age, `+6` bit 0 keyed.

Voices 0-4 are FM. Voice 5 (YM channel 6) is the DAC voice.

**FM note on** (`$1A68E`):
1. Oldest = the voice among 4..0 with the highest age. On ties the lower voice wins.
2. Scan voices 4..0 for free (unkeyed) ones. Prefer a free voice that already holds the same instrument; otherwise take the last free voice found (the lowest index).
3. With no free voice, take the oldest one (a **steal**: it can belong to any slot, music or effect).
4. If that voice's instrument differs, flag a patch load (`byte_FFD186` bit, `FFD19C[ch]`).
5. Set keyed, age 0, code, note, velocity. Set **both** key-off and key-on bits (`FFD182`, `FFD183`), so the note retriggers. Then volume (`sub_1ABAA`) and pitch (`sub_1A7D8`).

**FM volume** (`sub_1ABAA` L62918): `v = velocity * chvol >> 7` (0..127). The TL written to every **carrier** operator is `unk_1ABF0[v >> 3]` = `$1A $18 $16 $14 $12 $10 $0E $0C $0A $08 $06 $04 $03 $02 $01 $00` (0.75 dB steps; the patch's own carrier TL is overwritten).

**FM pitch** (`sub_1A7D8` L62057):
- `fnum = unk_1A890[note % 12]` = `$146 $159 $16E $184 $19B $1B3 $1CD $1E8 $205 $224 $245 $268`.
- With bend `b`: `fnum = fnum * unk_1A8A8[((b * range >> 2) >> 7) + $C0] * 2 >> 16`. `unk_1A8A8` is 385 words from `$4000` to `$FF13`, `2^(i/192)` x `$4000`, where 192 entries = 1 octave. `range` = patch byte `$1E` (semitones) for FM, 12 for DAC.
- Register word = `(note / 12) << 11 | fnum` (block = octave).

**DAC note on** (`loc_1A74E` L62019):
- The DAC voice is always voice 5. If voice 5 is keyed and the new instrument ≤ the current one, the note is **dropped**.
- Otherwise:
  - write the sample's 24-bit address (`unk_1B01C[instr-$60]`) to `Z:$23-$25` and the "next" pointer (always 0) to `Z:$26-$28`;
  - write `$29,$00` to `Z:$96-$97`, the restart vector (§4.1);
  - set the volume page: `Z:$83 = max(v >> 2, 3)`;
  - set the step: `Z:$8E = (fnum >> (8 - note/12)) & $FF` (bend applied first).

**Note off** (`sub_1A64C`): clears keyed. For FM it sets the key-off bit. For DAC it writes `Z:$8E = 0` (`sub_1A66E`): the step becomes 0, the loop keeps outputting the same byte, and the sample is frozen (silent).

The **DAC voice stays keyed until the sequence's note-off**, even after the sample has reached its `$00` end byte.

---

## 3. Data

### 3.1 `unk_2C648` (`$2C648`, L135000): 123 longs, id → sequence

The sequences lie between `$2C834` and `$4B7A0`. Ids `$26` and `$27` both point at `$2C840`, which is the end event of `$01`: they play nothing. The music boundary `off_2C708` = `$2CEF2` = sequence `$30`.

### 3.2 FM patches (`unk_2C248`, `$2C248`): 32 bytes each, instruments `$00..$1F` used

- Bytes 0-27 are written to YM registers `$30+ch, $34+ch, … $9C+ch`, the operator registers in register order: DT/MUL, TL, KS/AR, AM/DR, SR, SL/RR, SSG-EG, each x 4 operators.
- Byte 28 → `$B0+ch` (feedback/algorithm).
- Byte 29 → `$B4+ch` (L/R, AMS, FMS). It always has L and R set; some patches use the LFO. The Z80 init sets `$22 = $0C` (LFO on, rate 4 = 6.88 Hz).
- Byte 30 = pitch-bend range in semitones.
- Byte 31 = 0.

The Z80 reads a patch through bank 5 (`$28000`) at `$C248 + 32*instr`.

### 3.3 DAC samples (`unk_1B01C`, L63791)

The samples are unsigned 8-bit, each ended by `$00`. The table is in `animation_assets.md` §5.4, and `godot/assets/audio/dac/instr_XX.wav` are the raw samples.

**Rate** = `3,579,545 / (117 + w) * step / 256` Hz, where `w` is the Z80 wait per bank read (§4.1). The renders use `w = 3`, which gives ≈ 116.5 x step Hz: note 70 → step 72 → 8390 Hz. Per-id rates are in `audio.json` (`dac_notes`).

**Volume** = table page `p = max(v >> 2, 3)`. The output is `(s - $80) * 8 / (39 - p) + $80`, so the linear gain is `8 / (39 - p)`: 1.0 at page `$1F`, 0.22 at page 3. Ids `$13 $17 $1B` play with velocity 1, which gives page 3: still audible, at -13 dB.

---

## 4. The Z80 driver (`$1AD90`, L63139, `$295` bytes at `Z:$0000`)

### 4.1 Layout and DAC loop

| Z80 RAM | What |
|---|---|
| `$0000` | `jr $29` |
| `$02-$22` | Command block from the 68000 (§4.2) |
| `$23-$25` | Sample pointer: 68000 address bits 16-23, 8-15, 0-7 |
| `$26-$28` | "Next" pointer, played when the sample ends (always 0 = ROM byte 0, a `$00`: the loop parks) |
| `$29` | Init: `di`, `sp=$295`, `im 0`, `Z:$96 = $7D`, YM `$2B=$80` (DAC on), `$22=$0C` (LFO). Then it loads the pointer at `$23` and selects its bank. |
| `$7D-$97` | The DAC loop (117 T-states). `ld (ix),$2A`; `e=(hl)`; `d=page` (operand `Z:$83`); `a=(de)`; if `a==0` it jumps to `$67` (next pointer); `ld ($4001),a`; `c += step` (operand `Z:$8E`); `hl += carry`; `jp nc,$7D`. **The operand of that `jp` (`Z:$96/$97`) is the 68000's command vector:** `$007D` = idle, `$00D1` = run the command block, `$0029` = restart with a new sample. On `hl` overflow it falls into `$98`: `h |= $80`, then it bumps and selects the bank (operand `Z:$9D`). |
| `$AA` | Writes the 9-bit bank register `$6000` (9 serial bits of A) |
| `$D1-$258` | Command handler (§4.2). It ends by restoring `Z:$96 = $7D` and the sample bank. |
| `$300-$1FFF` | 29 volume tables of 256 bytes, built by the 68000 (page `p` at `Z:p*$100`, pages 3..`$1F`) |

**Timing.** Each sample byte costs 117 Z80 cycles, plus the 68000-bus wait of the `ld e,(hl)` read through the bank window. The FM handler runs between two sample bytes and stalls the DAC for its duration: each register write waits on the YM busy flag (32 YM clocks ≈ 90 Z80 cycles), so a 30-register patch load holds the DAC for about 1 ms.

### 4.2 Command block and handler

`sub_1A574` (L61838) handles the hand-off:
1. Request the bus.
2. If `Z:$96/$97` is not `$7D,$00` (the Z80 has not yet taken the previous command), release the bus, spin, and retry.
3. Write `$D1,$00` to `Z:$96`.
4. Copy 33 bytes from `$FFD182` to `Z:$02`.

| Z80 | 68000 | Meaning (bit n = YM channel code n: 0, 1, 2, 4, 5, 6) |
|---|---|---|
| `$02` | `FFD182` | key-off mask → `$28 = ch` |
| `$03` | `FFD183` | key-on mask → `$28 = $F0+ch`. Bit 6 (FM on channel 6) first writes `$2B = 0` (DAC off). Unused: FM never takes voice 5. |
| `$04` | `FFD184` | TL mask → carriers of channel `ch` = `Z:$07+ch` |
| `$05` | `FFD185` | frequency mask → `$A4+ch, $A0+ch` = word `Z:$0E+2ch` |
| `$06` | `FFD186` | patch mask → 30 bytes from `$2C248 + 32 * Z:$1C+ch` |
| `$07-$0D` | `FFD187` | TL per channel |
| `$0E-$1B` | `FFD18E` | block/fnum per channel |
| `$1C-$22` | `FFD19C` | patch number per channel |

The handler processes the masks in this order: key-off, patch, frequency, TL, key-on. It waits on the YM busy flag before every write. Port 1 (`$4002/3`) is used for channel codes ≥ 4.

### 4.3 Boot (`Begin` L29715)

`Z80_LoadROM` (holds the Z80 in reset; on a Mega Drive this also resets the YM2612), then `AllSndOff`, then `MusicVB`, then `KillCrowd`.

---

## 5. Sequence content

- **Effects** use MIDI channels 0-1. They are FM, DAC, or mixed: FM ids `$00-$06`, `$24`, `$25`, `$28-$2F`; DAC ids `$09-$1F`; mixed ids `$07`, `$08`, `$20-$23`.
- **Organ tunes** `$30..$77` use channel 0 (FM `$0B`, chords take several voices), plus channel 7 DAC drums (`$6A`) in 14 of them. Each ends on its own after 11-34 s.
- **`$78/$79/$7A`** use FM instruments `$01 $03 $04 $05 $09 $0A $0D $0E $14` on channels 0-6 and DAC `$6A` drums on channel 7. Each loops back to (nearly) its start (§2.2).
- **Crowd reactions** are DAC samples. `$0B` cheer and `$0F` the long "home leads" bed use `$6D`. `$0C` boo uses `$6B`. `$08` and `$0D` use `$6C`; `$0E` uses `$6C`, then `$6E`. These are the highest DAC instruments, so a crowd reaction overrides every other DAC sound (§6).

---

## 6. Channel and priority rules (what a port's mixer should follow)

1. **Music is one stream.** Starting an id ≥ `$30` stops the current music, via `sub_1A304`, before the new one starts. Ids < `$30` never stop music, even when started with `song`. `clockcont` (horn `$04`), `Stop4Pen` (whistle `$03`) and the delayed home-goal tune also call `sub_1A304` first: **the horn and the whistle cut the music**. `StartPer` calls `AllSndOff`, so every period starts in silence.
2. **Eight sequences at most.** A ninth request is dropped. In practice this never matters.
3. **FM effects share 5 FM voices with the music.** There is no effect-over-music priority: a new note steals the *oldest* voice when none is free. During a 6-voice song (`$78-$7A`), FM effects take voices from the song and the other way round. During an organ tune (1-4 voices), effects usually find a free voice.
   - Port approximation: mix FM effects over the music. Optionally duck the music by one voice (≈ -1.5 dB) while an FM effect plays.
4. **One DAC voice, priority = instrument number.** A DAC note replaces the sounding DAC note only if its instrument is **strictly higher**. Otherwise it is dropped. The DAC voice counts as busy from note-on to the sequence's note-off, even when the sample has finished.
   - So a second pass, shot or check (same instrument) **is dropped** while the first is still "keyed" (`dac_busy_seconds`, 0.42-0.90 s).
   - A crowd reaction (`$6B-$6E`) cuts any pass/shot/check. A shot (`$62`/`$63`) cuts a pass (`$61`).
   - The music's DAC drums (`$6A`) lose to crowd samples (`$6B`+) and win against effects `$60-$67`.

   `audio.json` gives `dac_priority` (the highest DAC instrument of the id) and `dac_busy_seconds` (its last DAC note-off) per effect.
5. **Effects with both FM and DAC** (`$07`, `$08`, `$20-$23`): the FM part always plays. Only the DAC part follows rule 4. For a single-file port, apply rule 4 to the whole id.
6. **Retriggering the same FM effect** restarts it on whatever voice is free or oldest, so two plays overlap rather than cut. Example: rapid board hits `$28-$2B`.

---

## 7. Songs: call sites and `ChooseSong`

### 7.1 Fixed songs

| id | where | when |
|---|---|---|
| `$78` | `newTitleScreen` L975422; L53862 | Title (keeps playing into the menus); game over |
| `$79` | `PeriodOver` L53840; L48340; `PlayoffScreen` L54022 | Period over / intermission |
| `$7A` | `sub_FCC76` L969620 | After the game setup screens |
| `$0B` | `AddPenalty` L45970; `FallDown` L49489; `puckstick` L50690; `puckgoalie` L50879 | Cheer: away player penalised or down, home faceoff win, home goalie save |
| `$0C` | `AddPenalty`; `FallDown`; `puckstick` | Boo: home player penalised or down, away faceoff win |
| `$0D` | `puckgoalie` L50879 | Away goalie save: crowd "oooh" (DAC `$6C`). Also `sfx $0D`, injury (`setInjuryType` L49503). |
| `$0F` | L55725 | After the game when the home team leads |

### 7.2 `ChooseSong` (L973979)

```
ChooseSong:
    if gmode & GM_HL (bit 4, highlight/replay): SongNum = $FFFF  ; song() ignores negatives
    else:
        clear byte_FFC2FE bit 6
        b = unk_FE5B0[HmTeam * 6 + SongIndex]      ; HmTeam = HomeTeam, 0..27
        if b == 0: b = unk_FE658[randomd0(8) & 7]  ; consumes one RNG roll only in this case
        SongNum = b
```

`unk_FE658` (the fallback) = `$34 $40 $42 $49 $58 $5C $65 $66`.

`unk_FE5B0`, `[SongIndex 0 1 2 3 4 5]` per team (00 = random fallback):

| # | team | 0 period start | 1 home PP | 2 stoppage | 3 home goal | 4 away PP | 5 3rd period |
|---|---|---|---|---|---|---|---|
| 0 | Anaheim | 77 | 75 | 76 | 00 | 5A | 00 |
| 1 | Boston | 31 | 32 | 30 | 00 | 5A | 31 |
| 2 | Buffalo | 34 | 33 | 33 | 34 | 5A | 00 |
| 3 | Calgary | 35 | 37 | 35 | 37 | 36 | 36 |
| 4 | Chicago | 38 | 3A | 39 | 38 | 5A | 65 |
| 5 | Dallas | 4A | 4B | 4B | 00 | 5A | 00 |
| 6 | Detroit | 3B | 3C | 3D | 00 | 5A | 3C |
| 7 | Edmonton | 3E | 3F | 3F | 00 | 5A | 00 |
| 8 | Florida | 77 | 75 | 76 | 00 | 5A | 00 |
| 9 | Hartford | 40 | 42 | 41 | 42 | 5A | 40 |
| 10 | Los Angeles | 43 | 43 | 45 | 44 | 5A | 46 |
| 11 | Montreal | 4F | 4E | 4F | 4D | 5A | 4C |
| 12 | New Jersey | 50 | 51 | 50 | 00 | 5A | 52 |
| 13 | NY Islanders | 47 | 48 | 47 | 49 | 5A | 49 |
| 14 | NY Rangers | 54 | 55 | 53 | 00 | 5A | 00 |
| 15 | Ottawa | 77 | 75 | 76 | 00 | 5A | 00 |
| 16 | Philadelphia | 56 | 57 | 56 | 58 | 00 | 58 |
| 17 | Pittsburgh | 59 | 5B | 59 | 5C | 5A | 5C |
| 18 | Quebec | 5D | 5E | 5D | 00 | 5A | 5E |
| 19 | San Jose | 5F | 60 | 61 | 63 | 64 | 65 |
| 20 | St. Louis | 67 | 68 | 68 | 67 | 5A | 69 |
| 21 | Tampa Bay | 6A | 6B | 6B | 00 | 5A | 00 |
| 22 | Toronto | 6C | 6C | 6D | 00 | 5A | 00 |
| 23 | Vancouver | 6E | 6F | 70 | 00 | 5A | 00 |
| 24 | Washington | 71 | 73 | 71 | 00 | 5A | 74 |
| 25 | Winnipeg | 77 | 75 | 76 | 00 | 5A | 00 |
| 26 | All Stars East | 54 | 55 | 53 | 00 | 5A | 00 |
| 27 | All Stars West | 54 | 55 | 53 | 00 | 5A | 00 |

Every id `$30..$77` except `$62` and `$72` can be chosen; those two are never picked. `$5A` is the stock "away power play" tune.

### 7.3 `SongIndex` triggers (every caller sets `HmTeam = HomeTeam` first)

| SongIndex | caller | ChooseSong when | song played when |
|---|---|---|---|
| 0 | `StartPer` L29853 (L29893) | the start of **every** period, overtime included: after `AllSndOff`, `ResetClock` (which rolls the RNG for SongIndex 5) and two `DoGameFrame` calls | at once: `song(SongNum)` L29896. `StartPer` then sets `sflags3` bit 7 when `gsp < 2`. |
| 1 / 4 | `sub_FF7E2` L976500, called from `puckfaceoff2` L42310 | a power play begins that `sflags2` does not show yet (`HmShots+$24` = players on ice, home - away): 1 if home has more players, 4 if away. It sets `byte_FFC2FE` bit 6. | at the end of `puckfaceoff2`'s setup (L42315), the same faceoff |
| 2 | `puckfaceoff` L41690 | a faceoff in the first half of the period, with `gameclock ≥ 60`, `sflags3` bit 7 set (`StartPer` sets it in periods 1 and 2 only; it is cleared here, so at most once per period), clock flag set, and no power-play tune pending. It sets `byte_FFC2FE` bit 4. | at the end of `puckfaceoff2`'s setup (L42315) |
| 2 | `puckshootout` L41085/L41092/L41090 | a shootout or penalty-shot attempt starts | at once (L41096) |
| 3 | `checkgoal` L49867 | the **home** team scores | `word_FFDECE = SongNum`, `word_FFDECC = $78`. `DoGameFrame` (L29922) counts down 120 game frames, then `sub_1A304` (stop music), then `song(word_FFDECE)` |
| 5 | `sub_7A34` L29987, from `periodiceevents` | 3rd period only (`gsp == 2`), not in highlights, once, when `gameclock ≤ word_FFB048` | at once. `ResetClock` (L29817) sets `word_FFB048 = PerTimeTotal - randomd0(PerTimeTotal/2)`: a random moment in the second half of the period. |

A SongIndex 2 tune and a power-play tune never stack: the faceoff plays whichever was picked last (bit 6 or bit 4). `ChooseSong` clears bit 6. Song ids from the table are organ tunes, so starting one stops the previous music.

---

## 8. Offline renders (`tools/extract/audio.py`)

```
python3 tools/extract/audio.py [lst/nhl94.bin] [godot/assets/audio] [--ids=0x03,0x78] [--verify]
```

**Requirements:** Python 3, numpy, `unicorn` 2.1.x (`pip install unicorn==2.1.4`) and a C compiler (`cc`). The script compiles `tools/extract/audio_core.c` together with the vendored third-party cores into a cached shared library in the temp dir:
- `third_party/nuked_opn2` (Nuked-OPN2 1.0.12, LGPL-2.1, YM2612 discrete mode; from github.com/nukeykt/Nuked-OPN2 master, unmodified);
- `third_party/z80` (superzazu/z80, MIT; from github.com/superzazu/z80 master, unmodified).

Each directory keeps its `LICENSE`.

**Per id, from a cold machine:**
1. Unicorn runs `Z80_LoadROM`, `AllSndOff`, then two frames of `MusicVB`. The Z80 runs the retail driver from Z80 RAM, so this is a real boot.
2. `p_initfx(id)`.
3. Every NTSC frame: `MusicVB` on the 68000, then the rest of the frame's 59,736 Z80 cycles. The YM is clocked at master/42 (14 Z80 cycles = 5 YM clocks) and output at master/1008 = 53,267 Hz.

Hand-offs: when the 68000 releases the bus inside a routine, the Z80 runs for 470 cycles (the `sub_1A574` retry spin). Each read through the bank window costs 3 extra Z80 cycles.

Each render stops when every slot is free and the output has been flat for two frames. A looping song stops 4 s after its first jump.

**Post-processing:**
- The chip output is checked to be L == R and kept as mono.
- It is resampled to 44.1 kHz with a 64-tap Blackman-windowed sinc.
- A 5 Hz one-pole DC blocker models the console's AC-coupled output. Without it, the DAC's held level after a sample would sit as DC.
- One fixed gain (x6, `format.gain`) is applied to every file, so relative levels are retail. The loudest peak is -8.2 dBFS (`$04` horn).
- Trailing silence is trimmed. `slot_seconds` still records how long the sequence occupies its slot.

**Loops** (`$78 $79 $7A`): pass 1 plays the loop body from silence. Pass 2 starts with pass 1's last notes still ringing.
- The tool finds the first offset `d` (≥ 0.25 s) after which pass 2's magnitude spectrum matches pass 1's within 12% over 0.25 s. It fine-tunes `d` to ±10 ms for the smallest waveform mismatch.
- It sets `loop_start = start + d` and `loop_end = jump + d`, then crossfades the 10 ms before `loop_end` into the 10 ms before `loop_start`.
- So the file is: the first-play intro (0 → `loop_start`), then the body, ending where playback jumps back to `loop_start`.
- The `smpl` chunk holds `[loop_start, loop_end)` with an **exclusive** end, which is how Godot's importer (loop mode "Detect From WAV") reads it into `AudioStreamWAV.loop_begin/loop_end`. The JSON has the same numbers.

**Files:**
- `sfx/sfx_%02x.wav`: ids `$00-$2F`, except `$26`/`$27`, which are empty.
- `music/song_%02x.wav`: `$30-$7A`, plus `$0B $0C $0D $0F`, which the game starts with `song`. These are the same render as the sfx file.
- `audio.json`:
  - `format`;
  - `mixing`;
  - `song_ids_used`;
  - `choose_song` (the tables);
  - `ids["0xNN"]`, one entry per id, with these fields:

| field | meaning |
|---|---|
| `files` | written files, relative to the audio dir |
| `kind` | `sfx` (< `$30`) or `music` |
| `use` | call sites / meaning |
| `seq_addr`, `seq_ticks`, `seq_end` | sequence address, length in ticks (frames), `end`/`loop` |
| `channels`, `fm_instruments`, `dac_instruments`, `voices`, `fm_max_voices` | static scan of the sequence |
| `dac_notes` | per DAC note (effects): instrument, note, step, rate, sample length, velocity, on/off tick. Songs get one row per distinct note. |
| `stops_music` | id ≥ `$30` (§6.1) |
| `slot_seconds` | how long the sequence holds its slot |
| `dac_priority`, `dac_busy_seconds` | the §6.4 rule for effects with DAC notes |
| `samples`, `duration` | file length (44.1 kHz frames, seconds) |
| `loops`, `loop_start`, `loop_end` | loop points, end exclusive |
| `loop_seam_rel_error` | spectral mismatch measured at the seam |
| `peak`, `clipped`, `stereo` | level checks (no file clips; `stereo` is always false) |

---

## 9. Id table

### 9.1 Effects `$00..$2F` (`sfx/sfx_XX.wav`)

Voices: FM instrument numbers, and DAC instruments with their DAC priority. Duration is the file length (trailing silence trimmed). Slot is how long the sequence runs. DAC busy is the time from the start to the last DAC note-off.

| id | meaning / call sites | FM | DAC | duration s | slot s | DAC busy s |
|---|---|---|---|---|---|---|
| `$00` | after a goal (checkgoal L49814): siren | 1F | - | 6.41 | 5.94 | - |
| `$01` | ding: breakaway (L39781, L39940), assnearest L40599; penalty-time tick (updatepentime L46877) | 1D | - | 0.38 | 0.33 | - |
| `$02` | penalty over (updatepentime L46877); one minute left (L51797) | 1D | - | 0.38 | 0.33 | - |
| `$03` | whistle (Stop4Pen L46476) | 1E | - | 1.09 | 1.84 | - |
| `$04` | horn, end of period (clockcont L30082) | 1A | - | 3.37 | 1.84 | - |
| `$05` | shot wiff (doshot); puck contact (checkpuckcoll L50528) | 1C | - | 0.28 | 0.33 | - |
| `$06` | stick deflection (puckstick L50608) | 19 1B | - | 0.38 | 0.33 | - |
| `$07` | no call site found | 17 | 60 | 0.20 | 0.17 | 0.17 |
| `$08` | puck hits the net frame, play live (checkgoal L49726) | 16 | 6C | 1.76 | 2.54 | 2.54 |
| `$09` | no retail call site (fight patch: punch, high) | - | 67 | 0.42 | 0.50 | 0.50 |
| `$0A` | no retail call site (fight patch: punch, low) | - | 67 | 0.34 | 0.50 | 0.50 |
| `$0B` | crowd cheer: song() from AddPenalty L45970, FallDown L49489, puckstick L50690, puckgoalie L50879 | - | 6D | 3.90 | 4.00 | 4.00 |
| `$0C` | crowd boo: song() from AddPenalty, FallDown | - | 6B | 1.55 | 1.50 | 1.50 |
| `$0D` | injury (setInjuryType L49503, sfx); away goalie save (puckgoalie L50879, song) | - | 6C | 1.66 | 1.67 | 1.67 |
| `$0E` | puck over / at the glass (wallcollb2 L50115) | - | 6C 6E | 1.89 | 1.84 | 1.84 |
| `$0F` | crowd bed when home leads after the game (song() L55725) | - | 6D | 18.07 | 18.02 | 18.02 |
| `$10` | pass, loudest: $10 + (($C - puckvz.b) >> 2 & 3) (passmode L37066) | - | 61 | 0.45 | 0.42 | 0.42 |
| `$11` | pass | - | 61 | 0.47 | 0.42 | 0.42 |
| `$12` | pass | - | 61 | 0.47 | 0.42 | 0.42 |
| `$13` | pass, quietest | - | 61 | 0.47 | 0.42 | 0.42 |
| `$14` | backhand shot, hardest: $14 + max(3 - speed/16, 0) (doshot L37692) | - | 62 | 0.45 | 0.42 | 0.42 |
| `$15` | backhand shot | - | 62 | 0.45 | 0.42 | 0.42 |
| `$16` | backhand shot | - | 62 | 0.45 | 0.42 | 0.42 |
| `$17` | backhand shot, softest | - | 62 | 0.45 | 0.42 | 0.42 |
| `$18` | forehand shot, hardest | - | 63 | 0.49 | 0.50 | 0.50 |
| `$19` | forehand shot | - | 63 | 0.49 | 0.50 | 0.50 |
| `$1A` | forehand shot | - | 63 | 0.49 | 0.50 | 0.50 |
| `$1B` | forehand shot, softest | - | 63 | 0.49 | 0.50 | 0.50 |
| `$1C` | body check, ltack 0 (newcheck L48769); goalie frame $2C8 (L39092) | - | 65 67 | 0.78 | 0.73 | 0.73 |
| `$1D` | body check, ltack 1 | - | 64 67 | 0.68 | 0.83 | 0.83 |
| `$1E` | body check, ltack 2 | - | 65 67 | 0.95 | 0.90 | 0.90 |
| `$1F` | body check, ltack 3 | - | 64 67 | 0.68 | 0.65 | 0.65 |
| `$20` | player hits the boards (L50205) | 18 | 66 | 0.98 | 0.53 | 0.53 |
| `$21` | no call site (player hits boards variant) | 18 | 66 | 0.97 | 0.53 | 0.53 |
| `$22` | no call site (player hits boards variant) | 18 | 66 | 0.95 | 0.53 | 0.53 |
| `$23` | no call site (player hits boards variant) | 18 | 66 | 0.93 | 0.53 | 0.53 |
| `$24` | puck hits a body / goalie (puckbody L50776, puckgoalie L50882) | 19 1B | - | 0.38 | 0.33 | - |
| `$25` | puck hits the net frame, clock stopped (checkgoal L49726) | 16 | - | 0.18 | 0.10 | - |
| `$26` | empty (points at the end event of $01) | - | - | empty | 0.00 | - |
| `$27` | empty (points at the end event of $01) | - | - | empty | 0.00 | - |
| `$28` | puck hits the boards, loudest: $28 + (d0 & 3) (wallcoll L50184) | 18 | - | 0.95 | 0.07 | - |
| `$29` | puck hits the boards | 18 | - | 0.90 | 0.05 | - |
| `$2A` | puck hits the boards | 18 | - | 0.82 | 0.03 | - |
| `$2B` | puck hits the boards, quietest | 18 | - | 0.75 | 0.02 | - |
| `$2C` | puck lands on the ice, loudest (updateplayers L35554) | 17 | - | 0.08 | 0.03 | - |
| `$2D` | puck lands on the ice | 17 | - | 0.08 | 0.03 | - |
| `$2E` | puck lands on the ice | 17 | - | 0.08 | 0.03 | - |
| `$2F` | puck lands on the ice, quietest; puck drop (Endfaceoff L42447) | 17 | - | 0.08 | 0.03 | - |

`$0B $0C $0D $0F` are also written as `music/song_0b.wav` etc. (the same bytes), because the game starts them with `song`.

### 9.2 Songs `$30..$7A` (`music/song_XX.wav`)

"Chosen by" lists `team SongIndex` pairs from `unk_FE5B0`, and `random` for the `unk_FE658` fallback. SongIndex 0 = period start, 1 = home power play, 2 = stoppage / shootout, 3 = home goal, 4 = away power play, 5 = 3rd period.

| id | duration s | drums | loop (samples @44.1k) | chosen by |
|---|---|---|---|---|
| `$30` | 21.76 | - | - | Bos 2 |
| `$31` | 20.11 | - | - | Bos 0, Bos 5 |
| `$32` | 24.30 | - | - | Bos 1 |
| `$33` | 13.83 | DAC $6A | - | Buf 1, Buf 2 |
| `$34` | 25.72 | - | - | Buf 0, Buf 3, random |
| `$35` | 18.61 | - | - | Cgy 0, Cgy 2 |
| `$36` | 21.04 | - | - | Cgy 4, Cgy 5 |
| `$37` | 20.99 | DAC $6A | - | Cgy 1, Cgy 3 |
| `$38` | 21.06 | - | - | Chi 0, Chi 3 |
| `$39` | 15.55 | - | - | Chi 2 |
| `$3A` | 13.35 | - | - | Chi 1 |
| `$3B` | 22.08 | - | - | Det 0 |
| `$3C` | 24.53 | - | - | Det 1, Det 5 |
| `$3D` | 12.43 | - | - | Det 2 |
| `$3E` | 18.51 | - | - | Edm 0 |
| `$3F` | 19.74 | - | - | Edm 1, Edm 2 |
| `$40` | 26.15 | - | - | Hfd 0, Hfd 5, random |
| `$41` | 23.55 | - | - | Hfd 2 |
| `$42` | 19.39 | - | - | Hfd 1, Hfd 3, random |
| `$43` | 17.39 | - | - | LA 0, LA 1 |
| `$44` | 20.03 | - | - | LA 3 |
| `$45` | 24.78 | - | - | LA 2 |
| `$46` | 18.86 | DAC $6A | - | LA 5 |
| `$47` | 23.10 | DAC $6A | - | NYI 0, NYI 2 |
| `$48` | 18.39 | - | - | NYI 1 |
| `$49` | 21.21 | - | - | NYI 3, NYI 5, random |
| `$4A` | 14.89 | - | - | Dal 0 |
| `$4B` | 16.80 | - | - | Dal 1, Dal 2 |
| `$4C` | 15.75 | - | - | Mtl 5 |
| `$4D` | 15.59 | - | - | Mtl 3 |
| `$4E` | 12.67 | - | - | Mtl 1 |
| `$4F` | 15.90 | - | - | Mtl 0, Mtl 2 |
| `$50` | 21.39 | DAC $6A | - | NJ 0, NJ 2 |
| `$51` | 19.07 | - | - | NJ 1 |
| `$52` | 19.17 | - | - | NJ 5 |
| `$53` | 16.42 | DAC $6A | - | NYR 2, ASE 2, ASW 2 |
| `$54` | 21.09 | - | - | NYR 0, ASE 0, ASW 0 |
| `$55` | 17.21 | - | - | NYR 1, ASE 1, ASW 1 |
| `$56` | 15.15 | - | - | Phi 0, Phi 2 |
| `$57` | 16.02 | - | - | Phi 1 |
| `$58` | 24.67 | - | - | Phi 3, Phi 5, random |
| `$59` | 12.85 | - | - | Pit 0, Pit 2 |
| `$5A` | 13.45 | - | - | Ana 4, Bos 4, Buf 4, Chi 4, Dal 4, Det 4, Edm 4, Fla 4, Hfd 4, LA 4, Mtl 4, NJ 4, NYI 4, NYR 4, Ott 4, Pit 4, Que 4, StL 4, TB 4, Tor 4, Van 4, Wsh 4, Wpg 4, ASE 4, ASW 4 |
| `$5B` | 21.38 | - | - | Pit 1 |
| `$5C` | 16.02 | - | - | Pit 3, Pit 5, random |
| `$5D` | 16.55 | - | - | Que 0, Que 2 |
| `$5E` | 24.31 | - | - | Que 1, Que 5 |
| `$5F` | 24.10 | - | - | SJ 0 |
| `$60` | 35.76 | - | - | SJ 1 |
| `$61` | 22.20 | DAC $6A | - | SJ 2 |
| `$62` | 27.75 | DAC $6A | - | never (unreachable) |
| `$63` | 29.12 | DAC $6A | - | SJ 3 |
| `$64` | 21.18 | - | - | SJ 4 |
| `$65` | 31.16 | - | - | Chi 5, SJ 5, random |
| `$66` | 25.45 | - | - | random |
| `$67` | 20.69 | - | - | StL 0, StL 3 |
| `$68` | 24.41 | - | - | StL 1, StL 2 |
| `$69` | 16.67 | - | - | StL 5 |
| `$6A` | 15.17 | DAC $6A | - | TB 0 |
| `$6B` | 12.82 | - | - | TB 1, TB 2 |
| `$6C` | 18.97 | - | - | Tor 0, Tor 1 |
| `$6D` | 16.82 | - | - | Tor 2 |
| `$6E` | 12.45 | - | - | Van 0 |
| `$6F` | 14.94 | DAC $6A | - | Van 1 |
| `$70` | 12.97 | - | - | Van 2 |
| `$71` | 14.94 | - | - | Wsh 0, Wsh 2 |
| `$72` | 27.24 | DAC $6A | - | never (unreachable) |
| `$73` | 20.49 | DAC $6A | - | Wsh 1 |
| `$74` | 27.35 | - | - | Wsh 5 |
| `$75` | 16.12 | - | - | Ana 1, Fla 1, Ott 1, Wpg 1 |
| `$76` | 22.28 | - | - | Ana 2, Fla 2, Ott 2, Wpg 2 |
| `$77` | 19.89 | DAC $6A | - | Ana 0, Fla 0, Ott 0, Wpg 0 |
| `$78` | 73.49 | DAC $6A | 31468-3240936 | title (newTitleScreen L975422) / game over (L53862) |
| `$79` | 78.84 | DAC $6A | 26185-3477044 | period over / intermission (PeriodOver L53840, L48340, PlayoffScreen L54022) |
| `$7A` | 88.86 | DAC $6A | 82154-3918649 | after the game setup screens (sub_FCC76 L969620) |

Total rendered audio: 1724 s.


---

## 10. Verification

All of these checks were run on the files now in `godot/assets/audio/`.

1. **The command stream matches the full game.** The earlier full-game harness (unicorn 68000 + VDP, Z80 stubbed as always idle) booted the ROM and logged every 68000 write into Z80 RAM, numbered by `MusicVB` call. Its title song `$78` ran 143 ticks: all 26 command blocks are **byte-identical** to `audio.py`'s isolated render of `$78`, tick for tick (scripts `xcheck.py`, `xcomp.py` and `xcomp2.py` in `/tmp/claude-0/-home-user/ef020377-92e3-57ff-8519-5d51b4a7df4d/scratchpad/atools/`, not deliverables).
   - For `$7A`, which followed `$78` in the harness, the DAC writes and the tick of every block are identical. The 4 FM blocks key the same (patch, fnum, TL) notes but on different YM channels: the voice ages left by `$78` differ from a cold start. That is the expected effect of the oldest-voice rule (§2.4), and it does not change the sound.
   - `$79` and `$4F` were cut after 6 and 34 ticks by the game's own `AllSndOff` (menu changes), so they were not compared further.
2. **Driver isolation.** For every id, the 68000 driver wrote **0 bytes to the PSG** and **0 bytes to the YM2612 directly** (`audio.json` `verify`). Every YM write came from the Z80.
3. **Pitch.**
   - `$01` ding, note 72: the FFT peak is 528 Hz; the predicted value is fnum `$146` x 2^5 x 53267 / 2^20 = 530 Hz.
   - `$04` horn, note 62: 296 Hz against 297.5 Hz predicted.
   - `$03` whistle: a 2.3 kHz tone with a fast trill (patch `$1E`, MUL 2/4 with pitch-bend events).
4. **DAC rate.** `$10` (instrument `$61`, note 70, step 72) was cross-correlated with the raw sample resampled at 7.8-9.0 kHz. The best match, r = 0.93, is at 8390 Hz, which is exactly `3579545/120*72/256`. So the emulated Z80 loop runs at its 117 + 3 cycle period.
5. **Durations.**
   - Every non-empty id has a peak ≥ 1225 (`$2F`; max 12,803 = -8.2 dBFS, `$04`), and nothing clips.
   - Files are ≥ the sequence length, except where the sequence waits silently after its last note-off. Example: `$03` keys off at tick 41 but ends at tick 110, and its file stops when the sound does.
   - Looping songs: `loop_end - loop_start` = the jump tick x 44100 / 59.9227, within one sample: `$78` 3,209,468 = 72.777 s = 4361 ticks.
6. **Loop seam.** The spectral mismatch between pass 1 and pass 2 at the seam is 0.120 (`$78`), 0.032 (`$79`) and 0.117 (`$7A`). After the crossfade, the sample step across the jump is 0-1 LSB (typical step 27-85 LSB). Godot 4.4.1 (`--headless --import` in a scratch project) imports `song_78.wav` and `song_79.wav` as `LOOP_FORWARD` with `loop_begin`/`loop_end` equal to the JSON values. `sfx_03.wav` imports as not looping.
7. **Determinism.** Two separate runs (different id order and process) produced byte-identical WAVs: sha256 compared for `$00 $08 $0B $1C $33`.
8. **Not verified:** listening against real hardware or a reference emulator recording. The output filter, absolute levels and the bank-wait figure (UNRESOLVED 1-3) can only be checked that way.

---

## 11. Port changes

**Status (2026-10-16): P1-P5, P7 and P8 are done.**
- `SfxBank` (core/sfx_bank.gd) handles P1, P2, P4, P5 and P7. Its effects pool has 5 voices; the P6 FM budget is not modelled.
- `HockeyWorld.choose_song`, `home_goal_song` and `period_song` handle P3. The period's tune and its AllSndOff wait for the first loop after the intermission hold.
- `GameRules._period_break` plays AllSndOff and `$79` at every intermission, the pregame one included (StartGame joins PeriodOver at loc_17278).
- The setup screen plays `$78`.
- P8: the music is Ogg Vorbis, made by `tools/extract/audio_ogg.py` (19 MB). Looping songs are cut at `loop_end`, and `loop_offset` is set from `audio.json`. Effects stay WAV.

`godot/core/sfx_bank.gd` and the logic need these changes to sound like retail. Line references are to the files as they are now.

**P1. `play_song(id)`: effects started with `song` must not touch the music.**
- `id < 0`: ignore.
- `id < $30`: this is an effect (`$0B` cheer, `$0C` boo, `$0D` crowd "oooh", `$0F` home-leads bed). Play it like `play(id)` on the effect/DAC path (P5), or on the `Crowd` bus. `music/song_0b.wav` etc. exist with the same bytes as `sfx/sfx_0b.wav`, so either path finds a file. Leave `_music` playing. Today these calls replace the current tune.
- `id ≥ $30`: stop `_music`, then start `music/song_XX.wav`. The stream loops by itself when the WAV has a loop (P4).

**P2. The horn and the whistle stop the music.** Retail calls `sub_1A304` right before `sfx(4)` (`clockcont` L30082) and `sfx(3)` (`Stop4Pen` L46476). Those are the only callers of 3 and 4. So `play(3)` and `play(4)` should `_music.stop()` first, or the logic can emit a stop.

**P3. Real `ChooseSong` in the logic, not in SfxBank.** It consumes a retail RNG roll (only when the table byte is 0), so it must run inside the simulation at the retail moment. Add to `HockeyWorld` (or `game_rules`):

```gdscript
const SONG_TABLE := PackedByteArray([...])   # unk_FE5B0, 28 x 6 bytes (audio.json choose_song.per_team or §7.2)
const SONG_RANDOM := PackedByteArray([0x34, 0x40, 0x42, 0x49, 0x58, 0x5C, 0x65, 0x66])  # unk_FE658
## ChooseSong (L973979). home = the home team's retail index 0..27 ($30E table order).
func choose_song(song_index: int) -> int:
	if gmode & GM_HL:
		return -1                      # SongNum = $FFFF: song() ignores it
	f_c2fe &= ~(1 << 6)                # bclr #6, byte_FFC2FE
	var b := SONG_TABLE[home * 6 + song_index]
	if b == 0:
		b = SONG_RANDOM[rng.range_(8) & 7]
	return b
```

Then replace the stand-ins:
- `faceoff_logic.gd` L115 `song_num = 2` → `song_num = w.choose_song(2)`. Call it at the same point (it already sets `f_c2fe` bit 4 after; retail's `ChooseSong` clears bit 6 before `bset #4`).
- `faceoff_logic.gd` L276 `song_num = 1 if d > 0 else 4` → `song_num = w.choose_song(1 if d > 0 else 4)`, then `w.f_c2fe |= 1 << 6`. That order is retail's: `ChooseSong` clears bit 6, then `loc_FF85E` sets it.
- `game_rules.gd` L1067 `w.song.emit(5)` → `w.song.emit(w.choose_song(5))`.
- `shootout_logic.gd` L159 `w.song.emit(2)` → `w.song.emit(w.choose_song(2))` (`puckshootout` L41085-L41096).
- **Period start (SongIndex 0):** no emitter exists. `StartPer` (L29853, every period including overtime) runs `AllSndOff`, `ResetClock` (RNG roll for `music_cue`), two `DoGameFrame` calls, then `song(choose_song(0))` (L29893-L29896). Do it at the same point in `game_rules._period_break` / the first faceoff, after `reset_clock()`, so the RNG rolls stay in retail order. `AllSndOff` also means every period starts in silence: stop the music and the effects.
- **Home goal (SongIndex 3):** `goal_song` (`hockey_world.gd` L310, emitted in `puck_logic.gd` L688) has no listener and plays nothing. Retail (`checkgoal` L49867-L49871): `word_FFDECE = choose_song(3)` at the goal and `word_FFDECC = $78`. `DoGameFrame` (L29922-L29931) then decrements once per game frame and at 0 stops the music and plays `song(word_FFDECE)`. Port: in the `goal_song` handler, store `choose_song(3)` and a 120-frame countdown in the logic, then `song.emit(id)`. With P1, the id ≥ `$30` stops the old tune.

**P4. Loops.** `song_78/79/7a.wav` carry a `smpl` loop. Godot's importer (`edit/loop_mode = 0`, "Detect From WAV", the default) turns it into `LOOP_FORWARD` with `loop_begin`/`loop_end` = `audio.json` `loop_start`/`loop_end` (checked with 4.4.1). If an `.import` overrides the loop mode, set it from `audio.json` at load time. Everything else plays once. If the files are ever converted to Ogg (`SfxBank` prefers `.ogg`), use `loop_offset = loop_start / 44100.0` and cut the file at `loop_end`.

**P5. One DAC channel with priority** (§6.4), for effects whose `audio.json` entry has `dac_priority`:

```gdscript
var _dac: AudioStreamPlayer        # one player for every id with a DAC part
var _dac_prio := 0                 # instrument number of what holds the DAC
var _dac_until := 0.0              # busy until (seconds, game clock) = start + dac_busy_seconds
func _play_dac(prio: int, busy: float, stream: AudioStream) -> void:
	var now := Time.get_ticks_msec() / 1000.0   # or the sim frame counter / 59.92
	if now < _dac_until and prio <= _dac_prio:
		return                     # retail drops it (loc_1A74E: cmp.b 3(a2),d0 / ble)
	_dac_prio = prio
	_dac_until = now + busy
	_dac.stream = stream
	_dac.play()                    # replaces the sounding DAC effect
```

- Pure-FM effects keep the round-robin pool. Mixed ids (`$07 $08 $20-$23`) can go through `_play_dac`: their FM part is short.
- Consequences to expect: a second pass, shot or check within 0.42-0.9 s of the first is **silent** in retail. Crowd cheers and boos (`$6B-$6D`) cut a shot's sound.
- Use the sim's frame clock for `now` if replays must sound identical.

**P6. Optional, FM voice budget.** Retail has 5 FM voices shared with the music. A port can skip this. If it wants the retail thinning, it can limit simultaneous FM effects to `5 - music voices`: 1-4 during organ tunes, ~0 during `$78-$7A`, which are only played outside gameplay.

**P7. Names and buses.**
- `CROWD_IDS` could hold `[0x0B, 0x0C, 0x0D, 0x0F]`; `$08` and `$0E` also contain crowd samples.
- `NAMES` misses `$07`, `$0F`, `$21-$23` (§9.1).
- `SONG_NAMES[$0D]` "away song" is the listing comment; the sound is the `$6C` crowd sample.
- The `play_song` doc comment ("93 numbering") is obsolete.

**P8. Size.** The WAVs are ~148 MB, almost all of it the 72 organ tunes (`music/`). If that is too large for the repo, convert the music to Ogg Vorbis offline (`ffmpeg -i song_XX.wav -c:a libvorbis -q:a 6 song_XX.ogg`). `SfxBank._load` already prefers `.ogg`. Godot's `compress/mode` on import shrinks only the imported copy.

---

## UNRESOLVED

1. **Z80 wait per bank-window read** (`BANK_WAIT = 3`). This sets the DAC rate (117 + w cycles per byte). Real hardware is about 3-4 cycles and varies with 68000 bus activity, so DAC pitches may be ~1% off.
2. **68000 bus holds** during `MusicVB`/`ReadJoyData` and other code stall the Z80 (and the DAC) for a few µs-ms per frame. They are not modelled: the 68000 side runs instantly at the frame start. Game-side VDP DMA does not affect the Z80.
3. **Output filtering and level.** No Model 1/Model 2 analog low-pass is applied; the renders are Nuked-OPN2's discrete-YM2612 output, DC-blocked at 5 Hz. The absolute level (gain x6) is arbitrary but the same for every file.
4. **Isolation.** Each id is rendered alone from a cold boot. In the game, voice stealing between concurrent effects and music, the DAC priority drops (§6) and the voice-age history change what is heard. §11 P5/P6 describe the rules; the files do not contain them.
5. **Loop seams** are perceptual, not sample-exact. The LFO phase, the EG counter and the DAC timing differ between passes, so pass 2 never equals pass 1 bit for bit. The seam is placed where the spectra agree (error 0.03-0.12) and crossfaded over 10 ms.
6. **Ids without a retail call site:** `$07`, `$09`, `$0A` (the fight patch uses `$09`/`$0A` as punches), `$21-$23`, and songs `$62`, `$72`, which no table entry selects. All are rendered anyway.
7. **What the crowd samples are.** `$6C` (`$08`, `$0D`, `$0E`) is taken to be a crowd "oooh", because it follows the post hit in `$08`. The listing calls `$0D` at `puckgoalie` the "away song". Not confirmed by ear.
8. **`sub_FF7E2`'s `HmShots+$24`** is read as players on ice (home - away), giving SongIndex 1 = home power play and 4 = away power play. This follows `faceoff_logic.gd` `_pp_song` and was not re-derived here.
9. **PAL tempo** (7 ticks per 6 frames, §2.3) is not rendered. The files are NTSC.
10. **`lastsfx` replay** (L34765, `sub_A528`) was not traced.
