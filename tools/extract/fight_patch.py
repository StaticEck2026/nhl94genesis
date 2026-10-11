#!/usr/bin/env python3
"""Export what the NHL '94 fight patch adds, as loose files for the Godot port.

The patch is Chaos81's nhl94-patches (MIT, https://github.com/Chaos81/nhl94-patches):
94_fight v1.01 puts NHLPA '93's fighting into '94. Its built ROM,
94_fight/output/nhl94_fight_v1.01.bin, carries everything this script reads. The game
never reads a ROM; it loads what this writes.

Usage: python3 tools/extract/fight_patch.py <nhl94-patches checkout> [godot]

Writes:
  assets/sprites/fight_idx.png + fight.json   frames 846 (the '93 gloves and stick) and
                                              847-869 (the fighters), same format as
                                              frames.json; SpriteAtlas reads them as part
                                              of the main set
  data/hotlist_fight.json                     Hotlist entries 838-869 (the patch adds
                                              empty spots for the arrows 838-845)
  data/spalist_fight.json                     the nine fight animations ($1B96-$1CD6)
  data/teams_fight/*.tres                     the patched rosters: fight ratings raised
                                              for each club's enforcers, some moved onto
                                              the checking line (nhl94-HF_adj.bin)

The patched ROM keeps every retail frame, hot spot and animation byte for byte (checked
below); it moves the tables to $200B00 and appends to them. Spec:
docs/specs/fight_patch.md.
"""
import hashlib
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import assets  # noqa: E402
import spalist  # noqa: E402
import teams  # noqa: E402

FIGHT_ROM = "94_fight/output/nhl94_fight_v1.01.bin"
FIGHT_MD5 = "44b69e03e5968e660ad003aa0ab076ad"
# GetHot's `movea.l #HotList,a1` and updateanim's `movea.l #SPAList,a0`, repointed by
# sprite_patch.asm.
GETHOT_PTR = 0x106F6
UPDATEANIM_PTR = 0xAEFC
GLOVE_FRAME_WORD = 0x16E7C
FIRST_FRAME = 846           # the gloves; 847 ($34F, SPFfight) .. 869 are the fighters
LAST_FRAME = 869            # entry 870 is the table's end marker
FIGHT_SPAS = [0x1B96, 0x1BC8, 0x1BEA, 0x1C0C, 0x1C3E, 0x1C70, 0x1C92, 0x1CB4, 0x1CD6]
RETAIL_HOT = 838            # retail Hotlist entries (frames 0-837)


def main() -> None:
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    repo = sys.argv[1]
    godot = sys.argv[2] if len(sys.argv) > 2 else "godot"
    data = open(os.path.join(repo, FIGHT_ROM), "rb").read()
    assert hashlib.md5(data).hexdigest() == FIGHT_MD5, "unexpected fight ROM"
    retail = open("lst/nhl94.bin", "rb").read()
    rom = assets.Rom(data)

    # The tables the patch moved, and the retail parts it kept.
    hot = rom.u32(GETHOT_PTR)
    spa = rom.u32(UPDATEANIM_PTR)
    assert data[hot:hot + 2 * RETAIL_HOT] == retail[assets.HOTLIST:assets.HOTLIST + 2 * RETAIL_HOT]
    assert data[spa:spa + 0x1B96] == retail[spalist.BASE:spalist.BASE + 0x1B96]
    assert rom.u16(GLOVE_FRAME_WORD) == FIRST_FRAME

    frames = assets.sprite_frames(rom, FIRST_FRAME, LAST_FRAME, hotlist=hot, hot_last=LAST_FRAME,
                                  retail=False)
    atlas = assets.pack(frames, 256)
    out = os.path.join(godot, "assets/sprites")
    atlas.save(os.path.join(out, "fight_idx.png"))
    meta = {}
    for fr in frames:
        c = fr["canvas"]
        meta[str(fr["frame"])] = {"rect": [fr["atlas"][0], fr["atlas"][1], c.w, c.h], "origin": fr["origin"],
                                  "hot": fr["hot"], "lines": fr["lines"]}
    with open(os.path.join(out, "fight.json"), "w") as f:
        json.dump({"source": "nhl94_fight_v1.01: frameSprData $%X, Hotlist $%X" % (
            assets.ANIM + rom.u32(assets.ANIM + 4), hot),
            "atlas": [atlas.w, atlas.h], "frames": meta}, f, separators=(",", ":"))

    pairs = [[rom.s8(hot + 2 * i), rom.s8(hot + 2 * i + 1)] for i in range(RETAIL_HOT, LAST_FRAME + 1)]
    with open(os.path.join(godot, "data/hotlist_fight.json"), "w") as f:
        json.dump({"source": "nhl94_fight_v1.01 Hotlist $%X" % hot, "first": RETAIL_HOT, "frames": pairs},
                  f, separators=(",", ":"))

    anims = spalist.parse(data, spa, FIGHT_SPAS)
    with open(os.path.join(godot, "data/spalist_fight.json"), "w") as f:
        json.dump({"source": "nhl94_fight_v1.01 SPAList $%X" % spa, "anims": anims}, f, separators=(",", ":"))

    team_dir = os.path.join(godot, "data/teams_fight")
    os.makedirs(team_dir, exist_ok=True)
    trom = teams.Rom(data)
    total = 0
    for t in range(teams.TEAMS):
        team = teams.read_team(trom, t)
        teams.write_tres(team, team_dir)
        total += len(team["players"])
    assert total == 684, total
    print("wrote %d fight frames (atlas %dx%d), %d hot spots, %d animations, %d teams to %s"
          % (len(frames), atlas.w, atlas.h, len(pairs), len(anims), teams.TEAMS, godot))


if __name__ == "__main__":
    main()
