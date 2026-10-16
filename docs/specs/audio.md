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
| `AllSndOff` | L61529 | `$1A264` | Resets all slots and voices (`sub_1AD54`), keys off and mutes every channel, freezes the DAC. Called at boot and at screen changes. |
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
| `$00` | inline | **End/jump.** If the word at +2 is negative (`$FFFF`), the slot is freed. Otherwise the long at +2 is a new pointer, and the event there runs **at once**, with its own delta ignored. Only `$78/$79/$7A` jump: each loops to its own first event. |
| `$8c` | `loc_1A61A` | Note off, `d1` = note. It finds the keyed voice whose `(code<<3|slot, note)` matches. |
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
- Byte 29 → `$B4+ch` (L/R, AMS, FMS). It always has L and R set; some patches use the LFO. The Z80 init sets `$22 = $0C` (LFO on, 5.56 Hz).
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

**Timing.** Each sample byte costs 117 Z80 cycles, plus the 68000-bus wait of the `ld e,(hl)` read through the bank window. The FM handler runs between two sample bytes and stalls the DAC for its duration: about 1-2 ms per frame with notes.

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
- **Organ tunes** `$30..$77` use channel 0 (FM `$0B`, chords take several voices), plus channel 7 DAC drums (`$6A`) in 16 of them. Each ends on its own after 11-34 s.
- **`$78/$79/$7A`** use FM instruments `$01 $03 $04 $05 $09 $0A $0D $0E $14` on channels 0-6 and DAC `$6A` drums on channel 7. Each loops to its start.
- **Crowd reactions** are DAC samples. `$0B` cheer and `$0F` the long "home leads" bed use `$6D`. `$0C` boo uses `$6B`. `$08`, `$0D` and `$0E` use `$6C`. These are the highest DAC instruments, so a crowd reaction overrides every other DAC sound (§6).

---

## 6. Channel and priority rules (what a port's mixer should follow)

1. **Music is one stream.** Starting an id ≥ `$30` stops the current music, via `sub_1A304`, before the new one starts. Ids < `$30` never stop music, even when started with `song`. `clockcont` (horn `$04`), `Stop4Pen` (whistle `$03`) and the delayed home-goal tune also call `sub_1A304` first: **the horn and the whistle cut the music**.
2. **Eight sequences at most.** A ninth request is dropped. In practice this never matters.
3. **FM effects share 5 FM voices with the music.** There is no effect-over-music priority: a new note steals the *oldest* voice when none is free. During a 6-voice song (`$78-$7A`), FM effects take voices from the song and the other way round. During an organ tune (1-4 voices), effects usually find a free voice.
   - Port approximation: mix FM effects over the music. Optionally duck the music by one voice (≈ -1.5 dB) while an FM effect plays.
4. **One DAC voice, priority = instrument number.** A DAC note replaces the sounding DAC note only if its instrument is **strictly higher**. Otherwise it is dropped. The DAC voice counts as busy from note-on to the sequence's note-off, even when the sample has finished.
   - So a second pass, shot or check (same instrument) **is dropped** while the first is still "keyed" (`dac_busy_seconds`, 0.42-0.75 s).
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
| `$0D` | `puckgoalie` L50879 | Away goalie save (also `sfx $0D`, injury, `setInjuryType` L49503) |
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

| # | team | 0 start | 1 home PP | 2 stoppage | 3 home goal | 4 away PP | 5 3rd period |
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
| 0 | L29893 (game start, after `DoGameFrame` x2) | game start | at once: `song(SongNum)` L29896 |
| 1 / 4 | `sub_FF7E2` L976500, called from `puckfaceoff2` L42310 | a power play begins that `sflags2` does not show yet (`HmShots+$24` = players on ice, home - away): 1 if home has more players, 4 if away. It sets `byte_FFC2FE` bit 6. | at the end of `puckfaceoff2`'s setup (L42315), the same faceoff |
| 2 | `puckfaceoff` L41690 | a faceoff in the first half of the period, with `gameclock ≥ 60`, `sflags3` bit 7 set (once per period), clock flag set, and no power-play tune pending. It sets `byte_FFC2FE` bit 4. | at the end of `puckfaceoff2`'s setup (L42315) |
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
- `third_party/nuked_opn2` (Nuked-OPN2 1.0.12, LGPL-2.1, YM2612 discrete mode);
- `third_party/z80` (superzazu/z80, MIT).

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
- One fixed gain (x6, `format.gain`) is applied to every file, so relative levels are retail. Peaks reach about -7 dBFS.
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

<!-- ID_TABLE -->

---

## 10. Verification

<!-- VERIFY -->

---

## 11. Port changes (not made here; for whoever owns `SfxBank` and the logic)

<!-- PORT -->

---

## UNRESOLVED

<!-- UNRESOLVED -->
