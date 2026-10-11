class_name HockeyWorld
extends RefCounted
## The simulation: the 16 retail sort objects and the globals they share, stepped one
## retail loop at a time (DoGameFrame L29914 / updateplayers L35329). Nodes read this
## state; they do not move anything themselves.

const SORT_OBJS := 16
const NET_TOP := 12
const NET_BOTTOM := 13
const PUCK := 14
const SHADOW := 15

## gmode bits.
const GM_CLOCK := 1 << 0     ## clock stopped / play stopped
const GM_DIR := 1 << 1       ## 0: home team goes up
const GM_PEN := 1 << 2
const GM_PENDEL := 1 << 3
const GM_HL := 1 << 4
const GM_OFFS := 1 << 5
## sflags2 bits.
const SF2_FACEOFF := 1 << 0
const SF2_SHOT := 1 << 4
const SF2_PWRPLAY := 1 << 5
const SF2_PWRTM := 1 << 6

## defaultsprites2 _list (L53446): x, y, z, frame, attribute, crsize, radius x/y,
## assignment, pflags. Home skaters line up on the left (-200, y), away on the right.
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
var motion: SkaterMotion
var steering: SkaterSteering

var objects: Array[SimObject] = []
## puckc: carrier SCnum, or -1.
var puckc: int = -1
var gmode: int = 0
var sflags: int = 0
var sflags2: int = 0
var sflags3: int = 0
## vblank counter.
var vcount: int = 0
## byte_FFC2FE bit 1 / byte_FFC2FC bit 6: crowd meter record boost.
var crowd_boost: bool = false
## byte_FFC2FC bit 4: line changes off (energy ignored).
var line_changes_off: bool = false
## Score per team (0 home, 1 away), period (1-3, 4 overtime) and the game clock in
## retail jiffies (24 per second, jps). Rules (Phase 8) drive these.
var score: PackedInt32Array = PackedInt32Array([0, 0])
var period: int = 1
var clock_jiffies: int = 5 * 60 * 24

func clock_seconds() -> int:
	return clock_jiffies / 24

## Stick input per object for this loop: 0-7, SkaterSteering.JOY_NONE or JOY_BRAKE.
## The game layer fills it for pad players; AI fills it for the rest.
var joy: PackedInt32Array = PackedInt32Array()

## word_FFD06E: retail uses step 22 instead of 17 when set. Mode not named yet.
var alt_step: bool = false

## Hooks for subsystems that are not ported yet. Each takes (world, object).
var puck_update: Callable
var skater_update: Callable

## Placeholder length of one-shot animations (stop, turn) in retail frames, until the
## SPA tables (SetSPA, updateanim) are ported.
const ONE_SHOT_FRAMES := 12

signal board_hit(index: int, normal: Vector2i, hard: bool)
## The object came down onto the ice. zvel is the bounce speed after landing.
signal landed(index: int, zvel: int)
## sfx (L44279): a retail sound effect id.
signal sound(id: int)

func _init(p_settings: SimSettings = null, seed: int = 0x00500000) -> void:
	settings = p_settings if p_settings != null else SimSettings.new()
	rng = RetailRng.new(seed)
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
		o.pnum = -1
		objects.append(o)
		joy[i] = SkaterSteering.JOY_NONE

func puck() -> SimObject:
	return objects[PUCK]

func carrier() -> SimObject:
	return objects[puckc] if puckc >= 0 and puckc < 12 else null

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
	return o

## One DoGameFrame with d7 vblanks elapsed.
func step(d7: int = 1) -> void:
	vcount += d7
	update_players(d7)

## updateplayers (L35329) for every sort object.
func update_players(d7: int) -> void:
	for o in objects:
		o.spa_restarted = false
		o.old_pos_fx = o.pos_fx
		o.old_z_fx = o.z_fx
		if o.flags3 & SimObject.PF3_FALLING:
			o.vel = Vector2i.ZERO
		if o.position < 0:
			o.limpact = o.impact
			continue
		_update_anim(o, d7)
		_tick_timers(o, d7)
		_integrate(o, d7)
		_assignment(o, d7)
		# Clear wallcos/wallsin, then checkcoll if the pixel position changed.
		o.wall = Vector2i.ZERO
		if o.pos() != o.old_pos():
			_check_collisions(o)
		_impact_decay(o, d7)

## updateanim stand-in: a one-shot animation clears pf2aip after ONE_SHOT_FRAMES.
func _update_anim(o: SimObject, d7: int) -> void:
	if not o.anim_busy():
		o.spa_cnt = 0
		return
	if o.spa_cnt <= 0:
		o.spa_cnt = ONE_SHOT_FRAMES
	o.spa_cnt -= d7
	if o.spa_cnt <= 0:
		o.set_flag2(SimObject.PF2_AIP, false)

func _tick_timers(o: SimObject, d7: int) -> void:
	if o.index < 12 and o.index != puckc:
		o.flags3 &= ~(SimObject.PF3_BREAKAWAY | SimObject.PF3_OSIDE)
	o.nopuck_hi = maxi(o.nopuck_hi - d7, 0)
	o.nopuck_lo = maxi(o.nopuck_lo - d7, 0)

## Drag, move, Z (updateplayers L35486-35548).
func _integrate(o: SimObject, d7: int) -> void:
	var d4 := int(Nhl94Units.VEL_STEP_ALT if alt_step else Nhl94Units.VEL_STEP) * d7
	# Retail tests the Z word (whole pixels) here, not the long.
	if o.z() == 0:
		var gliding := o.flags & SimObject.PF_DOFF != 0
		if o.index == PUCK and not settings.enable_puck_friction:
			pass
		else:
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
		# Puck-on-ice sound: 5 - Zvel low byte (0 if negative), played when 0-3.
		var n := 5 - _sbyte(o.zvel & 0xFF)
		if n < 0:
			n = 0
		if n <= 3:
			sound.emit(0x2C + n)

## The assignment call. Pad players steer from `joy`; AI and the puck use hooks.
func _assignment(o: SimObject, d7: int) -> void:
	if o.index < 12:
		if skater_update.is_valid():
			skater_update.call(self, o)
		else:
			skate(o, joy[o.index], d7)
	elif o.index == PUCK and puck_update.is_valid():
		puck_update.call(self, o)

## doplayeracc + playeracc for one skater with one stick value.
func skate(o: SimObject, stick: int, d7: int = 1) -> void:
	if o.is_goalie():
		# goalieacc is not ported yet; goalies skate like skaters for now.
		pass
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
	s.energy = o.energy
	s.is_goalie = o.is_goalie()
	s.crowd_boost = crowd_boost
	s.ignore_energy = line_changes_off
	s.joypad = o.joypad()
	s.has_puck = puckc == o.index
	s.fight_injured = o.flags2 & SimObject.PF2_PEN != 0
	return s

## checkcoll (L48484): boards for everything that collides. Player-player comes later.
func _check_collisions(o: SimObject) -> void:
	if o.flags & SimObject.PF_NC:
		return
	if o.index >= 12 and o.index != PUCK:
		return
	var n := RinkBoards.board_normal(o.pos(), o.radius)
	if n == Vector2i.ZERO:
		return
	var hit: RinkBoards.Hit
	if o.index == PUCK:
		hit = RinkBoards.bounce_puck(o.vel, n)
	else:
		hit = RinkBoards.bounce_skater(o.vel, n)
		if hit.responded:
			o.flags3 |= SimObject.PF3_WALL
	o.vel = hit.vel
	o.wall = hit.normal
	board_hit.emit(o.index, n, hit.hard or hit.puck_pop)
	if o.index == PUCK and hit.puck_pop:
		_puck_pop(o, hit)
	elif o.index != PUCK and hit.hard and o.impact >= 0xA:
		sound.emit(0x20)

## wallcoll puck pop: random Zvel up to $800 (negated, as retail), puckflip, and a board
## sound $28 + ((vn >> 10) + 4 clamped at 0) & 3. puckflip is ported with the puck.
func _puck_pop(o: SimObject, hit: RinkBoards.Hit) -> void:
	o.zvel = -rng.range_(0x800)
	var d := (hit.normal_speed >> 10) + 4
	if d < 0:
		d = 0
	sound.emit(0x28 + (d & 3))

static func _sbyte(b: int) -> int:
	return b - 256 if b >= 128 else b

## updateplayers _nf: impact falls by 2 per frame.
func _impact_decay(o: SimObject, d7: int) -> void:
	o.impact = maxi(o.impact - 2 * d7, 0)
	o.limpact = o.impact
