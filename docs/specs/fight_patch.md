# The NHL '94 fight patch in the Godot port

Source: Chaos81's [nhl94-patches](https://github.com/Chaos81/nhl94-patches) (MIT), version 1.01 of `94_fight`. It puts NHLPA '93's fighting into NHL '94 and is built as "NHL Hockey '94-Fight" (`94_fight/output/nhl94_fight_v1.01.bin`). The patch's notes call its code '93's fight routines with '94 addresses. The retail '94 routines it hooks are in `fight_patch_retail_hooks.md`, and the title screen it replaces is in `title_screen.md`.

The port offers the patch as an **edition** (`MatchConfig.Edition.FIGHT`, the default on the setup screen). Picking it brings in the patch's rosters, the Fighting option, its title screen and its credits. The retail edition plays the unpatched game: `HockeyWorld.opt_fight` stays 0 and no fight code runs.

## 1. Every file of the patch and where it went

| Patch file | What it does to the ROM | Port |
|---|---|---|
| `94_fight/scripts/fight_patch.asm` | fight code at `$200100`, hooks in doinput, checkcx, asstab `$14/$15`, uppads, the Begin RAM clear, the Fgt display, reverse-angle replay | `godot/logic/fight_logic.gd` (section 2) |
| `scripts/sprite_patch.asm` | moves SPAList, the frame table, SprData and Hotlist to `$200B00` and appends the fight data; adds 227 tiles after the retail tiles; the gloves frame word `$16E7C` = `$34E` | `tools/extract/fight_patch.py`: frames 846-869 → `assets/sprites/fight_idx.png` + `fight.json` (SpriteAtlas falls back to them), Hotlist 838-869 → `data/hotlist_fight.json`, SPAs `$1B96-$1CD6` → `data/spalist_fight.json`. The patched ROM keeps every retail frame, hot spot and animation byte for byte (checked by the extractor). The appended sprite palette equals retail's. |
| `rom/nhl94-HF_adj.bin` (the build's input ROM) | raises the fight ratings of about 60 enforcers (Probert, Domi, Odjick, Grimson, McSorley ... to 6-7) and moves some onto the checking line | `data/teams_fight/*.tres`, written by the same extractor from the built ROM |
| `scripts/menu_patch/*` (McMarkis) | a tenth main-menu item "Fighting: Off / On / On - Arcade Mode" stored at `$FFDF00` | setup screen "Fighting" option, `MatchConfig.fighting` → `HockeyWorld.opt_fight` |
| `loadDefFight` (`$17C86` hook) | `DefFight = 1`: the menu starts on On | `MatchConfig.fighting` defaults to `ON` |
| `fgtdisp` (`$8E3A` hook), `AttribHdr.bin` | the Team Rosters and Edit Lines screens show Fgt as `(H/F & $E) * 100 / 14` (0-100, no curve) | `PlayerData.fighting` now stores that scale (`fight_display`, `fight_nibble_of`), so nibble 7 round-trips. The port has no roster screen; the setup screen's line tooltips show Fgt for the fight edition. |
| `scripts/title_patch.asm` | new photo, shield, NHLPA logo and title (from the 30-team ROM) at `$11259C`; font colour remap `$0D $10` → `$0E $F0` | `tools/extract/title.py` → `assets/title/fight/`; `ui/title_screen.gd` |
| `scripts/credits_patch.asm` | `scroll_text.bin` at `$5776` (adds "Fight Patch 1.01 by chaos", "Menu Patch by McMarkis", the NHL94.com community) | same extractor; 21 blocks instead of 20 |
| `scripts/chg_header.asm` | ROM name "NHL Hockey '94-Fight", serial `GM T-50656 -0F` | the window and setup titles of the fight edition; the extractor checks the name |
| `scripts/94_to_3MB.asm`, `94_expand/*`, `notes/SRAM_code.asm` | pads the ROM to 3 or 4 MB and moves the SRAM read/write code below 2 MB with the SRAM bank switch | not applicable: the port has no ROM image or cartridge SRAM |
| `scripts/patch_checksum.asm` | skips the boot checksum | not applicable |
| reverse-angle replay fixes (`$A724`, `$A77C`, `$A784`, upgloves' flip) | flip the fight frames and the gloves in the reverse-angle replay | not applicable yet: the port has no instant replay |
| v1.01 "Shootout mode attribute list" (`$FC85C`, `$FC88E`) | the Shootout SetUp menu's attribute list follows the new headers | not applicable: the Shootout SetUp menu is not ported (`shootout_penaltyshot.md` U2) |
| menu patch demo-mode fix (`$F753C...`) | stops demo mode skipping two menu items | not applicable: the port has no menu demo |
| `94_custom_patch/*` | applies the same patches to any ROM (also 30- and 32-team hacks) | `fight_patch.py` and `title.py` take a patched ROM path as well as the checkout; the port's data model holds the 28 retail teams, so 30/32-team ROMs are refused by the roster check |

## 2. The fight code (`FightLogic`)

Hooks, as the patch places them:
- `collisions.gd` checkcx: `checkint`, `checkcheck`, then `checkfight(a3, a2)` (opposing players only), before the collflag test.
- `input_logic.gd` doinput: a pad player with the fight bit goes to `fightinput(a3, d0, d1, d7)` at the retail branch (`$B258`).
- asstab `$14` assfight, `$15` assfwatch (retail: `rts`).
- `HockeyWorld.step`: every object's `old_frame` (struct `$08`, written by addframe2) after the frame, for chkhit's once-per-frame test.
- glovecords cleared by puckfaceoff2's setup and puckpenshot (retail clears it there); Endfaceoff clears the puck's fight bit (retail).

Routines (all in `fight_logic.gd`, integer for integer with `fight_patch.asm`):

| Routine | Port | Notes |
|---|---|---|
| checkfight | `checkfight` | off with OptFight 0; both impacts >= 10, no lock, no pending penalty, no goalie, clock running, no highlight, no fight already (puck pflags2 bit 0), no OT (`gsp > 2`), puck not on puckfaceoff. Threshold `max(0, chkcnttab - ChkCnt) >> 2 + fgtatttab`. |
| ChkFightValue | `chk_fight_value` | returns d0: the routine does not restore it, so the second call (players swapped) starts from whatever the first left (the threshold, the chkftab value, the H/V bits, `$2A` or `$FFFF`). One fight in four (H/V counter & 3 == 0) also gives a teammate of the starter an Instigator minor (`$2A`), only with penalties on. |
| SF | `start_fight` | Fighting major (`$26`) through AddPenalty2 (no OptPen gate), setd0player (`hand_control`), assfight on top, x velocity -/+`$400`, the right-hand fighter mirrored, unavailable + AIP + no-collision bits, SPAfight. |
| assfight | `assfight` | strength `((energy * Fgt) & $FFFF) >> 12`, at least 5; the left fighter's banner delay 90; the CPU punch pick `randomd0(8)`: grab 3/8, high 4/8, low 1/8; the x pull toward the fight centre and the y clamp. Ends (assnothing) once Pencntdwn is negative. |
| chkhit | `chkhit` | once per new frame; frame 849 drops the gloves (glovecords from xc1/yc1, clamped to +-90 px); frames 853/858 high, 854/859 low, 851/856 grab within 22 x 8 px. |
| CwdFight | `cwd_fight` | crowd +`$50`/+`$A`; the victim's x velocity += `(5 + attacker strength) * 500`, negated when he faces 2. |
| FightFall | `fight_fall` | the **puncher's** `$26` entry becomes `$28` ("Fighting *": the winner); Pencntdwn = 60; the injury roll `randomd0(injtab) <= winner's Chk` → Pencntdwn 180, the toddle bit, SPAffall, the banner erased, setInjuryType, the victim's tmpdst = `$112C`, InjCntDown = 3; otherwise SPAbfall and sfx `$B` (away loser) / `$C` (home loser). The ROM's PenBuf scan has no bound; the port stops at the buffer's end. |
| assfwatch | `assfwatch` | every 60 frames, a spot 80 px from the fight centre on the player's side (x clamped to +-126); skateto then check4check. |
| fightinput | `fightinput` | d-pad moves (playeracc), the x pull, C high / B low / A grab. |
| banner | `show_banner` → `banner` signal | the last two PenBuf entries; the higher Fgt on top (ties: the older entry); "jersey Name ABBR"; drawn by the HUD at tile rows 1-5. |
| clear | `banner_cleared` signal | |
| upgloves | `gloves_pos`, `nodes/gloves_view.gd` | frame 846 at glovecords * 4, behind every sort object |

Tables (`fight_patch.asm` "Modifications"), by PerTimeTotal (5:00 → index 1, 10:00 → 2, 20:00 → 3, 0:30 → 0; chkftab uses entry 1 for 0:30):

| | < 2 min | 2-7 | 7-20 | >= 20 |
|---|---|---|---|---|
| chkcnttab (total checks) | 20 | 30 | 40 | 40 |
| chkftab (joiner's ChksF, halved in Arcade) | 8 | 8 | 16 | 16 |

fgtatttab (start) 10 / 6, minfgttab (join) 2 / 2, injtab 60 / 45 (On / Arcade). Loopskip = 1: ChksF is not cleared after a fight.

The penalties then run through the retail queue unchanged (`fight_patch_retail_hooks.md` 1): the two majors pair as coincidental, a fight-injured player serves with bit 12 and leaves `$1000` (out for the game), the instigator's minor is a real power play.

## 3. Retail fix found on the way

`setInjuryType` writes `$FFFD`/`$FFFC` to the injured player's tmpdst. The port wrote them to a separate array nobody read, so injured players stayed in the lineup. It now writes tmpdst, as retail does (this also affects the unpatched game).

## 4. Rebuilding the assets

```
python3 tools/extract/fight_patch.py <nhl94-patches checkout | patched ROM> godot
python3 tools/extract/title.py <nhl94-patches checkout | patched ROM> godot/assets/title
```
Both are deterministic; re-running them on the reference build reproduces the committed files.
