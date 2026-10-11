# NHL 94 Genesis

Bitwise rebuild of NHL 94 for the Sega Genesis. The segment pass has not started.

The listing is `lst/nhl94.bin.lst`. The ROM it was generated from is `lst/nhl94.bin`. That file is the reference for every segment verify. Do not use a different ROM.

The listing is an IDA LST in ASM68K / MRI mode. It has no address column. `loc_` / `sub_` names are the address.

Style source for a segment is the matching file in [NHLPA93Genesis](https://github.com/abdulahmad/NHLPA93Genesis).

## Segment queue

`src/hockey94.asm` is the include list. `SEGMENT_AGENT.md` is the rule file. `PROMPT.md` is the first Copilot prompt. Placeholder files are comments only.

94-only files that 93 did not have:

- `attract94.asm` for `EASportsScreen`, `HiScoreScreen`, and `LoadDefMenuOptions`
- `sram94.asm` starts at `InitSaveRAM`

## Build

Segment builds use `buildseg.bat` and `npm run seg:<name>` once a segment has a stub and a confirmed org. Verify against `lst/nhl94.bin`.

`npm run extractassets` runs `extractAssets94.js` against `lst/nhl94.bin`. That is for the graphics and sound data pass, not for the code segments.

The full `npm run build:retail` path is not ready. It still points at `src/hockey94.asm`, which is the queue.

## Godot rebuild

`godot/` is a separate native Godot 4 rebuild that uses the listing as a behavior reference. It does not emulate the Genesis and does not read the ROM. Progress is tracked in `GODOT_TODO.md`.

- Run: `godot --path godot` opens the setup screen (teams, controls, options), then a full match.
- Tests: `godot/tests/run_tests.sh /path/to/godot` (headless).
- Assets: the game loads loose files under `godot/assets/` and `godot/data/teams/`. They are produced offline from `lst/nhl94.bin` by `tools/extract/assets.py` (sprites, rink, palettes, samples), `tools/extract/teams.py` (rosters), `tools/extract/spalist.py` and `tools/extract/hotlist.py` (animation and stick tables).
- Behaviour specs for every ported routine are in `docs/specs/`.
