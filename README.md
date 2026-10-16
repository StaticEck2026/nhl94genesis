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

- Run: `godot --path godot` shows the title screen, then the setup screen (edition, teams, controls, options, line changes On/Off/Auto, goalie control, the Shootout mode, Fighting), then a full match. Start pauses: Timeout, Change Goalie, Edit Lines, Manual/Auto Goalie.
- Pads (A / B / C / Start): pad 1 is the arrows with Z X C Enter, pad 2 is W A S D with G H J Space, pad 3 is numpad 8 4 5 6 with numpad 1 2 3 Enter, and pad 4 is O K L ; with 7 8 9 0. Joypads 1-4 also work. Pads 3 and 4 are retail's four-way play: in the setup screen, choose "Pads 1 + 3" or "Pads 2 + 4" for a side.
- Editions: retail NHL '94, or "NHL Hockey '94-Fight", Chaos81's [fight patch](https://github.com/Chaos81/nhl94-patches) (MIT): NHLPA '93's fighting, its rosters, its title screen and credits, and the Fighting option (Off / On / On - Arcade Mode). See `docs/specs/fight_patch.md`.
- Tests: `godot/tests/run_tests.sh /path/to/godot` (headless).
- Assets: the game loads loose files under `godot/assets/` and `godot/data/`. They are produced offline from `lst/nhl94.bin` by `tools/extract/assets.py` (sprites, rink, palettes, samples), `tools/extract/teams.py` (rosters), `tools/extract/spalist.py` and `tools/extract/hotlist.py` (animation and stick tables), `tools/extract/title.py` (title screen) and `tools/extract/arena.py` (crowd, penalty box, arena animations, zamboni). The fight patch's data comes from its built ROM: `tools/extract/fight_patch.py <nhl94-patches checkout>` and `tools/extract/title.py <nhl94-patches checkout>`.
- Behaviour specs for every ported routine are in `docs/specs/`.
