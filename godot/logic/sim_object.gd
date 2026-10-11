class_name SimObject
extends RefCounted
## One retail sort object (SCstruct, 128 bytes at SortCords). Indices: 0-5 home skaters,
## 6-11 away skaters, 12 and 13 nets, 14 puck, 15 puck shadow. Field names follow the
## NHL 93 equates in src/ram94.asm; offsets in comments are the retail struct offsets.
## Retail axes: X right, Y up the ice. Positions are 16.16 fixed point.

# pflags ($62)
const PF_DOFF := 1 << 0      ## deceleration off (gliding drag >> 9)
const PF_NA := 1 << 1        ## new assignment
const PF_NC := 1 << 2        ## no collision mode
const PF_JOYCON := 1 << 3    ## joystick controlled
const PF_REV := 1 << 4       ## skating backwards
const PF_ALOCK := 1 << 5     ## locked until the animation is done
const PF_TEAM := 1 << 6      ## 0 home, 1 away
const PF_GOAL := 1 << 7      ## 0 shoots at the bottom goal, 1 at the top
# pflags2 ($63), as 94 uses it (several bits moved from the 93 equates in ram94.asm;
# see docs/specs/collisions_checking.md).
const PF2_FIGHT := 1 << 0     ## fighting
const PF2_AIP := 1 << 1       ## animation in progress
const PF2_UNAV := 1 << 2      ## unavailable (injured; passes skip him)
const PF2_LCMENU := 1 << 3    ## line-change menu open
const PF2_PEN := 1 << 4       ## has committed a penalty (AddPenalty2)
const PF2_NOCOLL := 1 << 5    ## line change / no player collision
const PF2_FIGHT_HURT := 1 << 6 ## hurt in a fight (playeracc speed cut, skate injured anim)
const PF2_BIT7 := 1 << 7
# pflags3 ($64)
const PF3_OSIDE := 1 << 0    ## offside
const PF3_BREAKAWAY := 1 << 1
const PF3_OFFCAM := 1 << 2   ## pad goalie off camera: the CPU goalie logic drives him
const PF3_ONETIMER := 1 << 3 ## one-timer in progress
const PF3_WALL := 1 << 4     ## hit the boards this loop
const PF3_FALLING := 1 << 5
const PF3_BLOCK_B := 1 << 6  ## the next B release does nothing (just given control, or B+C)

# position ($34)
const POS_OFF_ICE := -1
const POS_GOALIE := 0
const POS_LD := 1
const POS_RD := 2
const POS_LW := 3
const POS_C := 4
const POS_RW := 5

## SCnum ($52).
var index: int = 0
## $00, $14, $18: 16.16 longs.
var pos_fx: Vector2i = Vector2i.ZERO
var z_fx: int = 0
## $1C, $20, $24.
var old_pos_fx: Vector2i = Vector2i.ZERO
var old_z_fx: int = 0
## $28, $2A, $2C: rvu.
var vel: Vector2i = Vector2i.ZERO
var zvel: int = 0
## $04 sprite attribute word: bit 0 away-team palette swap, bit 11 x flip (byte 4 bit 3,
## set for one handedness), bit 12 y flip, bits 13-14 palette, bit 15 priority. $06 frame.
var attribute: int = 0
var frame: int = 0
## $2E, $30, $32.
var impactp: int = 0
var limpact: int = 0
var impact: int = 0
## $34.
var position: int = POS_OFF_ICE
## $36, $38: assignment stack, 8 bytes.
var assnum: int = 0
var asslist: PackedByteArray = PackedByteArray([0, 0, 0, 0, 0, 0, 0, 0])
## $40-$48.
var temp: PackedInt32Array = PackedInt32Array([0, 0, 0, 0, 0])
## $4A, $4C.
var radius: Vector2i = Vector2i(8, 4)
## $4E wallcos, $50 wallsin as an outward normal (normal.y = cos, normal.x = -sin), 8.8.
var wall: Vector2i = Vector2i.ZERO
## $54.
var facing_fx: int = 0
## $58 SPA, $5A SPAnum, $5C SPAcnt.
var spa: int = Spa.GLIDE
var spa_num: int = 0
var spa_cnt: int = 0
## Set when spa changes (SetSPA restart). Views use it to restart the animation.
var spa_restarted: bool = false
## $5E, $5F: no-puck timers (frames).
var nopuck_hi: int = 0
var nopuck_lo: int = 0
## $60, $61: the position and roster slot this object changes to ($FF none).
var newpos: int = -1
var newpnum: int = -1
## $62, $63, $64.
var flags: int = 0
var flags2: int = 0
var flags3: int = 0
## $65 glitch counter (de-glitches quick frame changes).
var glitch: int = 0
## $66 roster slot (pnum), -1 for none.
var pnum: int = -1
## $67-$74 ratings, raw retail bytes.
var weight: int = 0
var legstr: int = 0
var legspd: int = 0
var aioff: int = 0
var aidef: int = 0
var shotspd: int = 0
var shotacc: int = 0
var passacc: int = 0
var rostnum: int = 0
var spodds: int = 0
var stickhand: int = 0
var endurance: int = 0
var aggress: int = 0
## $74 fight byte: bit 1 chkFgtBit1, bits 2-7 fight rating (getFgtbyte); 0 adds
## to ChkCnt twice.
var hf: int = 0
## $75 Chk: checking rating (check4check caps it at $1E).
var checking: int = 0
## $76 handedness in 94 (1 = left). The goalie and faceoff specs both read it here.
var handed: int = 0
## $73 read as the glove rating for goalies (GGSleft in the 93 equates).
func glove() -> int:
	return aggress

## Energy (getpde/setpde). $1000 is rested.
var energy: int = 0x1000

func _init(p_index: int = 0) -> void:
	index = p_index

# --- positions -------------------------------------------------------------------

func x() -> int:
	return pos_fx.x >> 16

func y() -> int:
	return pos_fx.y >> 16

func z() -> int:
	return z_fx >> 16

func pos() -> Vector2i:
	return Vector2i(pos_fx.x >> 16, pos_fx.y >> 16)

func set_pos(p: Vector2i) -> void:
	pos_fx = Vector2i(p.x << 16, p.y << 16)

func set_posf(p: Vector2) -> void:
	pos_fx = Vector2i(roundi(p.x * 65536.0), roundi(p.y * 65536.0))

func posf() -> Vector2:
	return Vector2(pos_fx) / 65536.0

func old_pos() -> Vector2i:
	return Vector2i(old_pos_fx.x >> 16, old_pos_fx.y >> 16)

# --- flags -----------------------------------------------------------------------

func on_ice() -> bool:
	return position >= 0

## position == 0. Retail tests only the field, so the puck (index 14, position 0)
## also reads as a goalie in routines that do not check SCnum first.
func is_goalie() -> bool:
	return position == POS_GOALIE

func is_skater_slot() -> bool:
	return index < 12

func away() -> bool:
	return flags & PF_TEAM != 0

func team() -> int:
	return 1 if away() else 0

func attacking_top() -> bool:
	return flags & PF_GOAL != 0

func joypad() -> bool:
	return flags & PF_JOYCON != 0

func reverse() -> bool:
	return flags & PF_REV != 0

func anim_busy() -> bool:
	return flags2 & PF2_AIP != 0

func locked() -> bool:
	return flags & PF_ALOCK != 0

func fighting() -> bool:
	return flags2 & PF2_FIGHT != 0

func set_flag(bit: int, on: bool) -> void:
	flags = (flags | bit) if on else (flags & ~bit)

func set_flag2(bit: int, on: bool) -> void:
	flags2 = (flags2 | bit) if on else (flags2 & ~bit)

func set_flag3(bit: int, on: bool) -> void:
	flags3 = (flags3 | bit) if on else (flags3 & ~bit)

const ATTR_AWAY := 0x0001
const ATTR_XFLIP := 0x0800
const ATTR_YFLIP := 0x1000
const ATTR_PRIORITY := 0x8000

func x_flip() -> bool:
	return attribute & ATTR_XFLIP != 0

func facing() -> int:
	return facing_fx >> 16

## Facing in radians, Godot axes (0 is screen up, clockwise).
func facing_angle() -> float:
	return float(facing_fx) / 65536.0 * TAU / 8.0

## SetSPA (L43319): restart only when the animation changes.
func set_spa(id: int) -> void:
	if spa == id:
		return
	spa = id
	spa_num = 0
	# st $5C(a3): only the high byte, so the word is negative ("load the first frame").
	spa_cnt = -1
	spa_restarted = true

## Mid-range setplayer bytes (every rating nibble 3, 188 lb) for an object with no
## roster data (sandbox, tests).
func default_ratings() -> void:
	weight = 48
	legstr = 15
	legspd = 15
	aioff = RosterLogic.reaction(15)
	aidef = RosterLogic.reaction(15)
	shotspd = 15
	shotacc = 15
	passacc = 15
	stickhand = 15
	spodds = 15
	endurance = 15
	aggress = 15
	checking = 15

## Loads a PlayerData's ratings as setplayer would with no form and no bonuses.
func load_player(p: PlayerData) -> void:
	RosterLogic.load_bytes(self, p.rom_bytes())
