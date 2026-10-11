class_name HockeyWorld
extends RefCounted
## The simulation: the 16 retail sort objects and the globals they share, stepped one
## retail loop at a time (DoGameFrame L29914 / updateplayers L35329). Nodes read this
## state; they do not move anything themselves.
## Flag words keep their retail names and bit numbers so ports read across from the asm.

const SORT_OBJS := 16
const NET_TOP := 12
const NET_BOTTOM := 13
const PUCK := 14
const SHADOW := 15

## gmode bits.
const GM_CLOCK := 1 << 0     ## clock stopped / play stopped
const GM_DIR := 1 << 1       ## 0: home team goes up
const GM_PEN := 1 << 2       ## a stoppage is being processed
const GM_PENDEL := 1 << 3    ## delayed penalty pending
const GM_HL := 1 << 4        ## highlight / replay
const GM_OFFS := 1 << 5      ## offsides on
const GM_EOG := 1 << 6       ## 94: game over (clockcont _eog)
## sflags bits.
const SF_PAUSE := 1 << 0
const SF_PASSDIR := 1 << 2
const SF_SHOTDIR := 1 << 3
const SF_SLOCK := 1 << 6     ## scroll lock
const SF_HOR := 1 << 7       ## horizontal (penalty screen) mode
## sflags2 bits.
const SF2_FACEOFF := 1 << 0
const SF2_SHOT := 1 << 4     ## shot taken, in flight
const SF2_PWRPLAY := 1 << 5
const SF2_PWRTM := 1 << 6    ## 0 home on the power play, 1 away
## sflags3 bits.
const SF3_FACEOFF_WIN := 1 << 4
const SF3_PENSEC := 1 << 6
## word_FFC2F4.
const C2F4_GOAL := 1 << 0
const C2F4_PS_GOAL := 1 << 5
## word_FFC2F8.
const C2F8_ONETIMER_SHOT := 1 << 1
const C2F8_NET := 1 << 4     ## net collision: wallcoll consumes it and skips the wall bit
const C2F8_SLOT := 1 << 5    ## puck carrier in the slot (setSlotBit)
## word_FFC2FA.
const C2FA_SHOOTOUT := 1 << 0
const C2FA_BREAKAWAY := 1 << 4
## byte_FFC2FE.
const C2FE_PS_GOAL := 1 << 0
const C2FE_GOAL_TOGGLE := 1 << 3
const C2FE_ONETIMER_TOUCH := 1 << 7
## BA_PS_flags.
const BA_LIVE := 1 << 2
const BA_AWARDED := 1 << 3
## iflags (icing).
const IF_CGL := 1 << 0
const IF_DIR := 1 << 1
const IF_OK := 1 << 2

## defaultsprites2 _list (L53446): x, y, z, frame, attribute, crsize, radius x/y,
## assignment, pflags.
const DEFAULT_OBJECTS := [
	[0x180, 0xC0, 0, 1, 0, 0x14, 8, 4, 0, 0x80],
	[-200, -100, 0, 1, 0, 0x14, 8, 4, 0, 0x80],
	[-200, -80, 0, 1, 0, 0x14, 8, 4, 0, 0x80],
	[-200, -60, 0, 1, 0, 0x14, 8, 4, 0, 0x80],
	[-200, -40, 0, 1, 0, 0x14, 8, 4, 0, 0x80],
	[-200, -20, 0, 1, 0, 0x14, 8, 4, 0, 0x80],
	[0xC0, 0xC0, 0, 1, 1, 0x14, 8, 4, 0, 0x40],
	[-200, 40, 0, 1, 1, 0x14, 8, 4, 0, 0x40],
	[-200, 60, 0, 1, 1, 0x14, 8, 4, 0, 0x40],
	[-200, 80, 0, 1, 1, 0x14, 8, 4, 0, 0x40],
	[-200, 100, 0, 1, 1, 0x14, 8, 4, 0, 0x40],
	[-200, 120, 0, 1, 1, 0x14, 8, 4, 0, 0x40],
	[0, 0x10C, 0, 0x195, 0, 0xB, 0x14, 6, 0, 0],
	[0, -0x10C, 0, 0x196, 0, 0x11, 0x14, 6, 0, 0],
	[0, 0, 0, 0x18B, 0, 1, 5, 5, 0x18, 1],
	[0, 0, 0, 0x18A, 0, 0x11, 3, 3, 0x19, 4],
]

var settings: SimSettings
var rng: RetailRng
## Stand-in for reads of the VDP H/V counter, which retail uses as a cheap random number.
## Kept apart from `rng` so the seeded sequence matches retail call for call.
var hv_rng := RandomNumberGenerator.new()
var motion: SkaterMotion
var steering: SkaterSteering
var collisions: Collisions
var checking: Checking
var puck_logic: PuckLogic
## Hot spot per sprite frame (Hotlist, exported offline to res://data/hotlist.json).
var hotlist: Array = []
## True once the animation port drives sprite frames; until then GetHot uses facing.
var frames_live: bool = false

var objects: Array[SimObject] = []
## Stick input per object for this loop: 0-7, SkaterSteering.JOY_NONE or JOY_BRAKE.
## The game layer fills it for pad players; tests and the sandbox use it for any skater.
var joy: PackedInt32Array = PackedInt32Array()
## asstab (L56671): assignment id -> Callable(o: SimObject, d7: int). Subsystems
## register their routines; an unknown id does nothing (entry 0 is a bare rts).
var asstab: Dictionary = {}

# --- game state ----------------------------------------------------------------------

## puckc: carrier SCnum, or -1.
var puckc: int = -1
var gmode: int = 0
var sflags: int = 0
var sflags2: int = 0
var sflags3: int = 0
var f_c2f4: int = 0
var f_c2f8: int = 0
var f_c2fa: int = 0
var f_c2fe: int = 0
var ba_ps_flags: int = 0
## vblank counter.
var vcount: int = 0
## gsp: period 0-2 regulation, 3 overtime, 4 game over. gmdir flips each period.
var gsp: int = 0
## Period length in seconds (PerTimeTotal) and the clock: seconds left plus the
## 16-bit fraction the VBlank handler counts down by $AAA per vblank.
var period_seconds: int = 300
var gameclock: int = 300
var clock_frac: int = 0
## byte_FFC2FE bit 1 or byte_FFC2FC bit 6 (crowd record broken). set_bit1_C2FE
## (L975179) sets bit 1 every loop and its clear path is dead code, so in 94 the boost
## (+2 agility, +2 speed in playeracc; -2 in Bcheck) is always on.
var crowd_boost: bool = true
## byte_FFC2FC bit 4: line changes off (energy ignored).
var line_changes_off: bool = false
## OptPen: penalties on.
var opt_pen: bool = true
## Which team each pad controls (cont1team, cont2team: 0 none, 1 home, 2 away) and the
## object each pad drives (c1playernum, c2playernum, -1 none).
var cont_team: PackedInt32Array = PackedInt32Array([0, 0])
var c_player: PackedInt32Array = PackedInt32Array([-1, -1])
## DelayedPen: bit 1 home has a delayed penalty, bit 2 away has one.
var delayed_pen: int = 0
## crowdlevel and CwdExciteLvl accumulators.
var crowd_level: int = 0
var crowd_excite: int = 0
## ChkCnt, ltack (last tackle sound 0-3), InjCntDown.
var chk_cnt: int = 0
var ltack: int = 0
var inj_countdown: int = 0
## byte_FFC2FC bit 5: the last injury lasts the game.
var injury_game: bool = false
## PlayerChked / PlayerChking: last pair that got through FallDown (SCnum, -1 none).
var player_chked: int = -1
var player_chking: int = -1
## FallXPos / FallYPos: faller position when a board animation was chosen.
var fall_x: int = 0
var fall_y: int = 0
## Scroll lock point (xc1, yc1) and TempPlOffset from the last injury.
var scroll_lock: Vector2i = Vector2i.ZERO
var temp_pl_offset: int = 0
## Last touch (ltx, lty, ltplayer), last carrier to lose the puck (lastplayer), the
## intended pass receiver (passplayer) and the last shooter (shotplayer).
var ltx: int = 0
var lty: int = 0
var ltplayer: int = 0
var lastplayer: int = -1
var passplayer: int = -1
var shotplayer: int = 0
## Icing: iflags bits and the last toucher (icingPlayer).
var iflags: int = 0
var icing_player: int = 0
## puckcross: [x at top goal line, loops until it, x at bottom line, loops until it].
var puckcross: PackedInt32Array = PackedInt32Array([0, -1, 0, -1])
## PuckZCntr / TmpPuckZ: the stalled-high-puck counter.
var puck_z_cntr: int = 0
var tmp_puck_z: int = 0
## Penalty shot / shootout: shooter and goalie, shootout side and goals per side.
var ba_sktr: int = -1
var ba_goalie: int = -1
var shootout_side: int = 0
var shootout_goals: PackedInt32Array = PackedInt32Array([0, 0])
## ScoreSum: scoring summary records (time, strength, away, scorer, assists).
var score_summary: Array = []
## Stats per team (HmShots blocks).
var stats: Array[TeamStats] = [TeamStats.new(), TeamStats.new()]
## collflag for the current checkcoll call: 0, or -1 once something set it.
var collflag: int = 0
## Sprite Y-sort lists: oo_list[k] = object at sort slot k, oo_pos[obj] = its slot,
## ylist[obj] = the Y it was sorted with. checkplcoll walks neighbours through these.
var oo_list: PackedInt32Array = PackedInt32Array()
var oo_pos: PackedInt32Array = PackedInt32Array()
var ylist: PackedInt32Array = PackedInt32Array()
## word_FFD06E: retail uses step 22 instead of 17 when set. Mode not named yet.
var alt_step: bool = false

## Placeholder animation lengths in retail frames, until the SPA tables (SetSPA,
## updateanim) are ported. One-shot (pf2aip), locked (pfalock), down, injured.
const ONE_SHOT_FRAMES := 12
const LOCK_FRAMES := 30
const DOWN_FRAMES := 60
const INJURY_FRAMES := 150

signal board_hit(index: int, normal: Vector2i, hard: bool)
## The object came down onto the ice. zvel is the bounce speed after landing.
signal landed(index: int, zvel: int)
## sfx (L44279): a retail sound effect id.
signal sound(id: int)
## song (L44297): crowd cheer $B, crowd boo $C, and the music ids.
signal song(id: int)
## sub_FE510: a background tile animation (7 = bench area after a check over the boards).
signal background_anim(id: int)
## A PenaltyList id (AddPenalty2). The rules port turns this into the penalty queue.
signal penalty_called(id: int, offender: int)
## checkgoal: team 0 home / 1 away scored. rec is the ScoreSum record.
signal goal_scored(team: int, rec: Dictionary)
## The home goal song (ChooseSong after a home goal).
signal goal_song
## puckstick handed a loose puck to a one-timer shooter (onetimershot, Phase 4).
signal onetimer_shot(index: int)

func _init(p_settings: SimSettings = null, seed: int = 0x00500000) -> void:
	settings = p_settings if p_settings != null else SimSettings.new()
	rng = RetailRng.new(seed)
	hv_rng.seed = seed
	motion = SkaterMotion.new(settings)
	steering = SkaterSteering.new(settings)
	joy.resize(SORT_OBJS)
	for i in SORT_OBJS:
		var o := SimObject.new(i)
		var row: Array = DEFAULT_OBJECTS[i]
		o.set_pos(Vector2i(row[0], row[1]))
		o.z_fx = row[2] << 16
		o.frame = row[3]
		o.attribute = row[4]
		o.radius = Vector2i(row[6], row[7])
		o.asslist[0] = row[8]
		o.flags = row[9]
		o.position = SimObject.POS_OFF_ICE if i < 12 else 0
		objects.append(o)
		joy[i] = SkaterSteering.JOY_NONE
	stats[0].first_object = 0
	stats[1].first_object = 6
	collisions = Collisions.new(self)
	checking = Checking.new(self)
	puck_logic = PuckLogic.new(self)
	asstab[PuckLogic.ASS_PUCKNORM] = func(o: SimObject, d7: int) -> void: puck_logic.pucknorm(o, d7)
	asstab[PuckLogic.ASS_PUCKSHADOW] = func(o: SimObject, _d7: int) -> void: puck_logic.puckshadow(o)
	asstab[PuckLogic.ASS_PUCKUNFLIP] = func(o: SimObject, _d7: int) -> void: puck_logic.puckunflip(o)
	_load_hotlist()
	collisions.sort_all()

func _load_hotlist() -> void:
	var path := "res://data/hotlist.json"
	if not FileAccess.file_exists(path):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if data is Dictionary and data.has("frames"):
		hotlist = data["frames"]

## Breaks the reference cycles between the world and its modules. Call when a match ends.
func dispose() -> void:
	for m in [collisions, checking, puck_logic]:
		if m:
			m.w = null
	collisions = null
	checking = null
	puck_logic = null
	asstab.clear()

func puck() -> SimObject:
	return objects[PUCK]

func carrier() -> SimObject:
	return objects[puckc] if puckc >= 0 and puckc < 12 else null

func clock_seconds() -> int:
	return gameclock

## Score of team 0 (home) or 1 (away).
func score(team: int) -> int:
	return stats[team].goals

## Puts a skater on the ice at a retail position with a position role.
func place(index: int, at: Vector2i, role: int, team_away: bool, attack_top: bool) -> SimObject:
	var o := objects[index]
	o.set_pos(at)
	o.old_pos_fx = o.pos_fx
	o.vel = Vector2i.ZERO
	o.position = role
	o.set_flag(SimObject.PF_TEAM, team_away)
	o.set_flag(SimObject.PF_GOAL, attack_top)
	o.facing_fx = (0 if attack_top else 4) << 16
	collisions.sort_all()
	return o

## Puts the puck down at a retail position, loose and still.
func drop_puck(at: Vector2i) -> void:
	var p := puck()
	p.set_pos(at)
	p.old_pos_fx = p.pos_fx
	p.vel = Vector2i.ZERO
	p.z_fx = 0
	p.zvel = 0
	p.flags &= ~SimObject.PF_NC
	puckc = -1
	collisions.sort_all()

# --- the loop ------------------------------------------------------------------------

## One DoGameFrame with d7 vblanks elapsed.
func step(d7: int = 1) -> void:
	vcount += d7
	update_players(d7)

## updateplayers (L35329) for every sort object.
func update_players(d7: int) -> void:
	puck_logic.z_stall()
	for o in objects:
		o.old_pos_fx = o.pos_fx
		o.old_z_fx = o.z_fx
		if o.flags3 & SimObject.PF3_FALLING:
			o.vel = Vector2i.ZERO
			checking.pin_to_boards(o)
		if o.position < 0:
			o.limpact = o.impact
			continue
		_update_anim(o, d7)
		o.spa_restarted = false
		_tick_timers(o, d7)
		_integrate(o, d7)
		if o.index < 12 and o.flags & SimObject.PF_JOYCON:
			doinput(o, d7)
		_assignment(o, d7)
		# Clear wallcos/wallsin, then checkcoll if the pixel position changed.
		o.wall = Vector2i.ZERO
		if o.pos() != o.old_pos():
			_check_collisions(o)
		_impact_decay(o, d7)

## updateanim stand-in until the SPA tables are ported (Phase 9). At the end of a one-shot
## or locked animation updateanim clears pf2aip, pfalock and the falling bit (L35745).
## SPAnum stays 0 for the first frame.
func _update_anim(o: SimObject, d7: int) -> void:
	var busy := o.anim_busy() or o.locked() or o.flags3 & SimObject.PF3_FALLING
	if not busy:
		o.spa_cnt = 0
		return
	if o.spa_restarted or o.spa_cnt <= 0:
		o.spa_cnt = _anim_frames(o)
		o.spa_num = 0
		return
	o.spa_num = 4
	o.spa_cnt -= d7
	if o.spa_cnt <= 0:
		o.flags2 &= ~SimObject.PF2_AIP
		var clear := SimObject.PF_ALOCK
		if o.flags3 & SimObject.PF3_FALLING:
			clear |= SimObject.PF_DOFF
		o.flags &= ~clear
		o.flags3 &= ~SimObject.PF3_FALLING
		o.set_spa(Spa.GLIDE)

func _anim_frames(o: SimObject) -> int:
	if o.spa == Checking.SPA_INJURED_GAME or o.spa == Checking.SPA_INJURED_PERIOD:
		return INJURY_FRAMES
	if o.flags3 & SimObject.PF3_FALLING or o.spa in Checking.ALREADY_DOWN:
		return DOWN_FRAMES
	if o.locked():
		return LOCK_FRAMES
	return ONE_SHOT_FRAMES

func _tick_timers(o: SimObject, d7: int) -> void:
	if o.index < 12 and o.index != puckc:
		o.flags3 &= ~(SimObject.PF3_BREAKAWAY | SimObject.PF3_OSIDE)
	o.nopuck_hi = _dec_byte(o.nopuck_hi, d7)
	o.nopuck_lo = _dec_byte(o.nopuck_lo, d7)

## sub.b d7 then clear on a negative byte result.
static func _dec_byte(v: int, d7: int) -> int:
	var r := (v - d7) & 0xFF
	return 0 if r >= 0x80 else r

## Drag, move, Z (updateplayers L35486-35555).
func _integrate(o: SimObject, d7: int) -> void:
	var d4 := int(Nhl94Units.VEL_STEP_ALT if alt_step else Nhl94Units.VEL_STEP) * d7
	# Retail tests the Z word (whole pixels) here, not the long.
	if o.z() == 0:
		var gliding := o.flags & SimObject.PF_DOFF != 0
		if not (o.index == PUCK and not settings.enable_puck_friction):
			o.vel = motion.apply_drag(o.vel, gliding)
	o.pos_fx += o.vel * d4
	if o.z() < 0:
		return
	if o.z() == 0 and o.zvel == 0:
		return
	o.zvel -= d4 * 6
	o.z_fx += o.zvel * d4
	if o.z_fx < 0:
		o.z_fx = 0
		o.zvel = (-o.zvel) >> 1
		landed.emit(o.index, o.zvel)
		# Puck-on-ice sound: 5 - Zvel high byte (0 if negative), played when 0-3.
		var n := 5 - _sbyte((o.zvel >> 8) & 0xFF)
		if n < 0:
			n = 0
		if n <= 3:
			sound.emit(0x2C + n)

## doinput for a pad player. The full button handling arrives with the input port;
## for now the stick drives doplayeracc.
func doinput(o: SimObject, d7: int) -> void:
	skate(o, joy[o.index], d7)

## The assignment call: asstab[asslist[assnum]]. Skaters without an assignment but with
## a stick value in `joy` (tests, sandbox) skate with it.
func _assignment(o: SimObject, d7: int) -> void:
	var id: int = o.asslist[o.assnum & 7]
	if asstab.has(id):
		asstab[id].call(o, d7)
	elif o.index < 12 and not o.joypad() and joy[o.index] != SkaterSteering.JOY_NONE:
		skate(o, joy[o.index], d7)

## assreplace (L43210): replace the current assignment and flag it new.
func assreplace(o: SimObject, id: int) -> void:
	o.asslist[o.assnum & 7] = id
	o.flags |= SimObject.PF_NA

## assinsert (L43202): push a new assignment over the current one.
func assinsert(o: SimObject, id: int) -> void:
	o.assnum = (o.assnum - 1) & 7
	assreplace(o, id)

## assexit (L43192): pop back to the previous assignment.
func assexit(o: SimObject) -> void:
	o.assnum = (o.assnum + 1) & 7
	o.flags |= SimObject.PF_NA

## doplayeracc + playeracc for one skater with one stick value.
func skate(o: SimObject, stick: int, d7: int = 1) -> void:
	# pfalock: locked out until the animation (check, hold, fall) is done.
	if o.locked() or o.flags3 & SimObject.PF3_FALLING:
		return
	var ctx := SkaterSteering.Context.new()
	ctx.has_puck = puckc == o.index
	var p := puck()
	ctx.to_puck = Vector2i(p.x() - o.x(), p.y() + (p.vel.y >> 8) - o.y())
	var r := steering.steer(o, stick, ctx)
	match r.action:
		SkaterSteering.Action.ACCEL:
			o.vel = motion.apply_accel(skater_view(o), o.vel, motion.dirtab(r.accel_dir), d7, o.wall)
		SkaterSteering.Action.STOP:
			o.vel = motion.apply_stop(o.vel)

## SkaterMotion inputs for an object, including the global boosts.
func skater_view(o: SimObject) -> SkaterMotion.Skater:
	var s := SkaterMotion.Skater.new()
	s.weight = o.weight
	s.agility = o.legstr
	s.speed = o.legspd
	s.energy = energy_of(o)
	s.is_goalie = o.is_goalie()
	s.crowd_boost = crowd_boost
	s.ignore_energy = line_changes_off
	s.joypad = o.joypad()
	s.has_puck = puckc == o.index
	s.fight_injured = o.flags2 & SimObject.PF2_FIGHT_HURT != 0
	return s

## Energy of a player (team struct $32 + 2 * pnum); $1000 with line changes off or for
## objects without a roster slot.
func energy_of(o: SimObject) -> int:
	if line_changes_off or o.index > 11 or not TeamStats.valid_pnum(o.pnum):
		return 0x1000
	return stats[o.team()].energy[o.pnum]

# --- collisions ----------------------------------------------------------------------

## checkcoll (L48484): boards and nets for the body, then the stick tip, then other
## players; then either restore the old pixel position (collflag) or re-sort by Y.
func _check_collisions(o: SimObject) -> void:
	collflag = 0
	var d2 := o.x()
	var d3 := o.y()
	if o.flags & SimObject.PF_NC == 0:
		checkwallcoll2(o, o.pos(), o.radius)
		if o.wall == Vector2i.ZERO and o.index <= 11:
			checkwallcoll2(o, o.pos() + get_hot(o), Vector2i(1, 1))
		collisions.checkplcoll(o, d2, d3)
	if collflag != 0:
		# Only the pixel words come back; fractions keep their new values.
		o.pos_fx = Vector2i(((o.old_pos_fx.x >> 16) << 16) | (o.pos_fx.x & 0xFFFF),
				((o.old_pos_fx.y >> 16) << 16) | (o.pos_fx.y & 0xFFFF))
		return
	collisions.resort(o, d3)

## checkwallcoll2 (L49549): corner arcs, the net at that end, then the straight boards
## (only when nothing set the wall normal).
func checkwallcoll2(o: SimObject, p: Vector2i, rad: Vector2i) -> void:
	o.flags3 &= ~SimObject.PF3_WALL
	var cx := RinkBoards.SIDELINE - rad.x - RinkBoards.CORNER_RADIUS
	var cy := RinkBoards.END_BOARD - rad.y - RinkBoards.CORNER_RADIUS
	if absi(p.y) >= cy:
		if absi(p.x) > cx:
			var n := RinkBoards.corner_normal(p, rad)
			if n != Vector2i.ZERO:
				wallcollb2(o, n)
		else:
			var net := objects[NET_TOP if p.y > 0 else NET_BOTTOM]
			puck_logic.checkgoal(o, net, p.x, p.y, rad)
	if o.wall != Vector2i.ZERO:
		return
	var s := RinkBoards.straight_normal(p, rad)
	if s != Vector2i.ZERO:
		wallcollb2(o, s)

## wallcollb2 (L50092): the puck may leave over the glass; everything else bounces.
func wallcollb2(o: SimObject, n: Vector2i) -> void:
	if o.index == PUCK and puck_logic.over_glass(o, n):
		return
	wallcoll(o, n)

## wallcoll (L50143) for any object with an outward normal.
func wallcoll(o: SimObject, n: Vector2i) -> RinkBoards.Hit:
	var hit: RinkBoards.Hit
	if o.index == PUCK:
		hit = RinkBoards.bounce_puck(o.vel, n)
	else:
		hit = RinkBoards.bounce_skater(o.vel, n)
		if hit.responded:
			if f_c2f8 & C2F8_NET:
				f_c2f8 &= ~C2F8_NET
			else:
				o.flags3 |= SimObject.PF3_WALL
	o.vel = hit.vel
	o.wall = hit.normal
	board_hit.emit(o.index, n, hit.hard or hit.puck_pop)
	if o.index == PUCK and hit.puck_pop:
		o.zvel = -rng.range_(0x800)
		puck_logic.puckflip(o, o.zvel)
		var d := (hit.normal_speed >> 10) + 4
		if d < 0:
			d = 0
		sound.emit(0x28 + (d & 3))
	elif o.index != PUCK and hit.hard and o.impact >= 0xA:
		sound.emit(0x20)
	return hit

## updateplayers _nf: impact falls by 2 per frame.
func _impact_decay(o: SimObject, d7: int) -> void:
	o.impact = maxi(o.impact - 2 * d7, 0)
	o.limpact = o.impact

## GetHot (L43282): stick hot spot offset in rink axes. Uses the Hotlist entry for the
## object's sprite frame once the animation port drives frames; until then a stand-in
## from facing: frame 1's hot spot (-4, 20 rink) rotated to the facing direction.
func get_hot(o: SimObject) -> Vector2i:
	if frames_live and o.frame > 0 and o.frame < hotlist.size():
		var e: Array = hotlist[o.frame]
		var x: int = e[0]
		var y: int = e[1]
		if o.attribute & 0x8:
			x = -x
		if o.attribute & 0x10 == 0:
			y = -y
		return Vector2i(x, y)
	if o.index > 11:
		return Vector2i.ZERO
	var a := o.facing_angle()
	var v := Vector2(-4, 20)
	if o.handed & 1 == 0:
		v.x = -v.x
	# Rotate clockwise in rink axes (Y up) by the facing angle.
	var r := Vector2(v.x * cos(a) + v.y * sin(a), -v.x * sin(a) + v.y * cos(a))
	return Vector2i(roundi(r.x), roundi(r.y))

# --- shots, control, penalties --------------------------------------------------------

## ChkShotStat (L47451): credit a shot on goal.
func chk_shot_stat() -> void:
	if gmode & GM_CLOCK or gmode & GM_HL:
		return
	if sflags2 & SF2_SHOT:
		sflags2 &= ~SF2_SHOT
		crowd_level += 0x64
		crowd_excite += 0xA
		_add_shot(shotplayer)
		return
	if f_c2f4 & C2F4_GOAL == 0:
		return
	if f_c2fe & C2FE_GOAL_TOGGLE == 0:
		f_c2fe |= C2FE_GOAL_TOGGLE
		return
	f_c2fe &= ~C2FE_GOAL_TOGGLE
	# The scorer from the last ScoreSum record gets the shot.
	if score_summary.is_empty():
		return
	var rec: Dictionary = score_summary[score_summary.size() - 1]
	var team := 1 if rec["away"] else 0
	for i in 6:
		var o := objects[stats[team].first_object + i]
		if (o.pnum & 0xFF) == (int(rec["scorer"]) & 0xFF):
			_add_shot(o.index)
			return

func _add_shot(sc: int) -> void:
	if sc < 0 or sc > 11:
		return
	var a3 := objects[sc]
	var a2 := stats[a3.team()]
	var a1 := stats[1 - a3.team()]
	a2.shots += 1
	if sflags2 & SF2_PWRPLAY:
		var pp_away := sflags2 & SF2_PWRTM != 0
		if pp_away == a3.away():
			a2.pp_shots += 1
	a2.period_shots[mini(gsp, 3)] += 1
	if TeamStats.valid_pnum(a3.pnum):
		a2.player_shots[a3.pnum] += 1
	if TeamStats.valid_pnum(a1.goalie_pnum) and not a1.goalie_pulled:
		a1.player_shots[a1.goalie_pnum] += 1

## _glue's hand-off of human control to the new carrier (setc1player / setc2player).
func hand_control(a2: SimObject) -> void:
	var d0 := a2.index
	if d0 == c_player[0] or d0 == c_player[1]:
		return
	var team := 1 if d0 < 6 else 2
	if lastplayer != c_player[1] and cont_team[0] == team:
		set_c_player(0, a2)
	elif cont_team[1] == team:
		set_c_player(1, a2)
	elif cont_team[0] == team:
		set_c_player(0, a2)

## setc1player / setc2player: pad k now drives object o. The input port adds the
## switching details (pflags3 bit 6 B-release guard and the like).
func set_c_player(k: int, o: SimObject) -> void:
	var old := c_player[k]
	if old >= 0 and old < 12:
		objects[old].flags &= ~SimObject.PF_JOYCON
	c_player[k] = o.index
	o.flags |= SimObject.PF_JOYCON

## AddPenalty (L45939): the gated call.
func add_penalty(id: int, offender: SimObject) -> void:
	if gmode & GM_CLOCK:
		return
	if id == 0xC:
		add_penalty2(id, offender)
		return
	if not opt_pen:
		return
	if offender.flags2 & SimObject.PF2_UNAV:
		return
	if gmode & GM_OFFS == 0 and id == 0x10:
		return
	add_penalty2(id, offender)

## AddPenalty2 (L45954): the forced call. Crowd reaction and the penalty flags here;
## the penalty queue and delayed-penalty play come with the rules port.
func add_penalty2(id: int, offender: SimObject) -> void:
	if sflags & SF_HOR:
		return
	if id >= 0xE and offender.index < 12:
		crowd_level += 0xC8
		if offender.away():
			crowd_excite += 0x14
			song.emit(0xB)
		else:
			song.emit(0xC)
	if id >= 0x12 and offender.index < 12:
		delayed_pen |= 4 if offender.away() else 2
		offender.flags2 |= SimObject.PF2_PEN
	penalty_called.emit(id, offender.index)

## PenShotChk (L46100): may turn a foul on a breakaway into a penalty shot. Identity
## until the rules port.
func pen_shot_chk(id: int, _victim: SimObject) -> int:
	return id

## sub_1284A: a power-play goal releases a penalized player. Rules port.
func pp_goal(_scoring_team: int) -> void:
	pass

## sub_F2F4: penalty shot / shootout attempt-over check. Rules port.
func ps_attempt_check() -> void:
	pass

## sub_F37C: end the penalty shot / shootout attempt. Rules port.
func ps_attempt_end() -> void:
	ba_ps_flags = 0
	gmode |= GM_CLOCK

## sub_FEFF0: cancel a one-timer. Shooting port.
func cancel_onetimer(o: SimObject) -> void:
	o.flags3 &= ~SimObject.PF3_ONETIMER
	o.flags &= ~SimObject.PF_ALOCK
	o.flags2 &= ~SimObject.PF2_AIP
	o.set_spa(Spa.GLIDE)

# --- helpers -------------------------------------------------------------------------

static func _sbyte(b: int) -> int:
	return b - 256 if b >= 128 else b

## Signed 16-bit wrap.
static func s16(v: int) -> int:
	v &= 0xFFFF
	return v - 0x10000 if v >= 0x8000 else v
