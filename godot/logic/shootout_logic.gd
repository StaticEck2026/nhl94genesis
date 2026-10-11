class_name ShootoutLogic
extends RefCounted
## Penalty shots and the shootout: PenShotChk / getBAplayerInfo (awarding), puckshootout
## ($1E) and puckpenshot ($1F) (the attempt setup), sub_EE58 (the shooter), sub_1592C,
## the CPU shooter's script (sub_FE756, sub_FE7FC, sub_FE864, sub_FE8EC), sub_F2F4 and
## sub_F37C (the end of an attempt), and the shootout's rounds and winner (sub_FC47C,
## sub_FC4C0, sub_FC516, sub_FD618). Spec: docs/specs/shootout_penaltyshot.md.

const ASS_PUCKSHOOTOUT := 0x1E
const ASS_PUCKPENSHOT := 0x1F
const ASS_BREAKWAIT := 0x20
const ASS_NEAREST := 0x11
const ASS_GOALIE_CPU := 0x0E
const ASS_SCORE := 0x07
const PEN_WHISTLE := 0x0A
## unk_1913A: the penalty-shot variant of each foul (shifted one entry, quirk Q1).
const PS_MAP := {0x14: 0x38, 0x16: 0x3C, 0x18: 0x36, 0x1A: 0x3A, 0x1C: 0x2E, 0x1E: 0x30, 0x20: 0x34}
## The seven CPU paths (unk_FE788, ROM $FE7A4-$FE7FB) as raw words: (X, Y) waypoints in
## the attack-top frame, then a terminator word $80tt (tt = shoot tolerance) and the
## shot direction. A trailing $4800 stands for the code byte after path 6.
const PATH_WORDS: Array[int] = [
	0x0010, 0x00E2, 0x0010, 0x00D0, 0x8020, 0x0005,
	0xFFC9, 0x00A0, 0xFFFF, 0x00C8, 0xFFE0, 0x00D0, 0x8020, 0x0005,
	0xFFB0, 0x0040, 0x001A, 0x00BC, 0x8020, 0x0005,
	0xFFCE, 0x0058, 0x0014, 0x00D0, 0x802C, 0x0005,
	0xFFCE, 0x0008, 0x0020, 0x00D0, 0x8028, 0x0006,
	0x001C, 0x00F4, 0x0008, 0x00E0, 0x8020, 0x0006,
	0xFFE6, 0x00F8, 0x0000, 0x00E0, 0x8020, 0x0002,
	0x4800,
]
const PATH_START: Array[int] = [0, 6, 14, 20, 26, 32, 38]
## word_FFC2FA bits beyond the world's named ones.
const C2FA_ATTEMPT_CLOCK := 1 << 1  ## the VBlank runs ps_clock, not gameclock
const C2FA_CLOCK_LIVE := 1 << 2     ## the clock runs although play is stopped
const C2FA_DECIDED := 1 << 3        ## the shootout has a winner
const C2FA_RELEASED := 1 << 5       ## the puck left the stick after the press
## BA_PS_flags bits beyond the world's named ones.
const BA_WHISTLED := 1 << 6         ## the attempt-over whistle is queued
const BA_INTRO := 1 << 7            ## intro text request
## sflags2 bit 2: no replay recording.
const SF2_NOREC := 1 << 2

var w: HockeyWorld
## BA_Team, BA_Skater_Offset, BA_Goalie_Offset, BA_Checker_Offset, word_FFD410.
var ba_team: int = 0
var ba_skater_offset: int = 0
var ba_goalie_offset: int = 0
var ba_checker_offset: int = 0
var ps_variant: int = 0
## word_FFD454 / word_FFD456: the attempt clock (seconds left) and its fraction.
var ps_clock: int = 0
var ps_clock_frac: int = 0
## word_FFD578 (round, 1-based), word_FFD586 (shooter 0-4), the lists ($FFD57A /
## $FFD588: shooters 0-4 then the goalie, roster slots).
var so_round: int = 0
var so_shooter_idx: int = 0
var so_list: Array[PackedInt32Array] = [PackedInt32Array([0, 0, 0, 0, 0, 0]), PackedInt32Array([0, 0, 0, 0, 0, 0])]
## The CPU script: path (word_FFDA12), waypoint index (FFDA14), waypoint words (FFDA16 /
## FFDA18), shoot tolerance (FFDA1C), byte_FFC2FC bit 3 (last waypoint loaded).
var ps_path: int = 0
var ps_wp_idx: int = -1
var ps_wp_x: int = 0
var ps_wp_y: int = 0
var ps_shoot_tol: int = 0
var last_wp: bool = false
## byte_FFC31E: the shooter object's newpnum, saved by sub_1592C.
var saved_newpnum: int = -1
## byte_FFC2FC bit 7: the PS / SO display flag.
var display: bool = false
## The shootout game is over (sub_FC4C0 found the winner; retail goes back to the menus).
var finished: bool = false

## The intro box (sub_187B8 / loc_FC320): its lines of text.
signal intro(lines: PackedStringArray)
## The shootout winner is known (team 0 home / 1 away).
signal shootout_won(team: int)

func _init(world: HockeyWorld) -> void:
	w = world

func register(t: Dictionary) -> void:
	t[ASS_PUCKSHOOTOUT] = func(o: SimObject, _d7: int) -> void: puckshootout(o)
	t[ASS_PUCKPENSHOT] = func(o: SimObject, _d7: int) -> void: puckpenshot(o)

func _so() -> bool:
	return w.f_c2fa & HockeyWorld.C2FA_SHOOTOUT != 0

static func s16(v: int) -> int:
	return HockeyWorld.s16(v)

## getGoalieSCnum: the first object at or below `last` (six of them) with position 0.
func goalie_scnum(last: int) -> int:
	for i in 6:
		var o := w.objects[last - i]
		if o.position == SimObject.POS_GOALIE:
			return o.index
	return -1

# --- awarding --------------------------------------------------------------------------

## PenShotChk (L46100): a foul on a skater on a breakaway becomes a penalty shot.
func pen_shot_chk(id: int, victim: SimObject, offender: SimObject) -> int:
	if victim == null or victim.flags3 & SimObject.PF3_BREAKAWAY == 0:
		return id
	if w.ba_ps_flags & HockeyWorld.BA_AWARDED:
		return id
	var v: int = PS_MAP.get(id, -1)
	if v < 0:
		return id
	if not get_ba_player_info(victim.index, offender):
		w.ba_ps_flags &= ~HockeyWorld.BA_AWARDED
		return id
	ps_variant = v
	return v

## getBAplayerInfo (L46136): record the shooter, the goalie and the offender.
func get_ba_player_info(d0: int, a3: SimObject) -> bool:
	if not w.opt_pen:
		return false
	w.ba_ps_flags |= HockeyWorld.BA_AWARDED
	var g := goalie_scnum(5 if d0 > 5 else 11)
	if g < 0:
		w.ba_ps_flags &= ~HockeyWorld.BA_AWARDED
		return false
	var s := w.objects[d0]
	w.ba_sktr = d0
	ba_team = 1 if s.away() else 0
	ba_skater_offset = s.pnum & 0xFF
	w.ba_goalie = g
	ba_goalie_offset = w.objects[g].pnum & 0xFF
	ba_checker_offset = a3.pnum & 0xFF if a3 else 0
	# N is bit 7 of the offender's roster byte: set means failure.
	return ba_checker_offset & 0x80 == 0

# --- the attempt -------------------------------------------------------------------------

## puckshootout ($1E, L41046): set up an attempt (first call), pick the shooter, check the
## goalie, then puckpenshot.
func puckshootout(p: SimObject) -> void:
	if finished:
		return
	if p.flags & SimObject.PF_NA:
		p.flags &= ~SimObject.PF_NA
		display = true
		w.f_c2fa &= ~HockeyWorld.C2FA_PS_INTRO
		if _so():
			if not next_shootout_attempt():
				return
		else:
			script_init()
			w.stats[ba_team].ps_attempts += 1
		w.ba_ps_flags &= ~(HockeyWorld.BA_LIVE | HockeyWorld.BA_GOALIE_HELD | HockeyWorld.BA_STARTED | BA_WHISTLED)
		w.f_c2f8 |= 1 << 1
		if w.gmode & HockeyWorld.GM_PENDEL:
			# Q12: unreachable in practice (chkprogress clears gmpendel first).
			w.rules.stop4pen(-1)
			return
		if not _so() or (w.shootout_side == 0 and so_shooter_idx == 0):
			w.song.emit(2)
		w.gmode |= HockeyWorld.GM_CLOCK
		w.f_c2fa |= C2FA_ATTEMPT_CLOCK
		p.vel = Vector2i.ZERO
		ps_clock = 0x19
		w.goalie.return_goalies()
		p.temp[0] = -0x100
		p.temp[1] = -0x100
	w.ba_ps_flags |= HockeyWorld.BA_LIVE
	if not pick_shooter():
		_abort(p)
		return
	var g := w.objects[w.ba_goalie] if w.ba_goalie >= 0 and w.ba_goalie < 12 else null
	if g == null or g.position != SimObject.POS_GOALIE or g.flags2 & SimObject.PF2_UNAV:
		var d0 := w.ba_goalie
		var found := false
		for i in 6:
			d0 -= 1
			if d0 < 0:
				d0 = 5
			elif d0 == 5:
				d0 = 11
			var o := w.objects[d0]
			if o.position == SimObject.POS_GOALIE and o.flags2 & SimObject.PF2_UNAV == 0:
				w.ba_goalie = d0
				found = true
				break
		if not found:
			_abort(p)
			return
	w.assreplace(p, ASS_PUCKPENSHOT)

func _abort(p: SimObject) -> void:
	w.ba_ps_flags &= ~HockeyWorld.BA_LIVE
	w.assreplace(p, FaceoffLogic.ASS_PUCKFACEOFF)

## sub_EE58: the shooter. In a penalty shot, the fouled player if he can (on the bench or
## the ice), else the best of the rest by nine ratings; in a shootout, the list's shooter.
## Anyone with Shot Accuracy 0 or 1 (all goalies) is skipped.
func pick_shooter() -> bool:
	var st := w.stats[ba_team]
	var best := -1
	var pick := -1
	var chosen := false
	for slot in mini(st.rom.size(), TeamStats.ROSTER):
		var a: PackedByteArray = st.rom[slot]
		if HockeyWorld._sbyte(a[5] & 0xF) <= 1:
			continue
		if _so():
			chosen = true
			break
		var td := st.tmpdst[slot]
		if td != TeamStats.TMPDST_BENCH and td != TeamStats.TMPDST_ON_ICE:
			continue
		var s := (a[1] & 0xF) + (a[2] & 0xF) + (a[2] >> 4) + (a[3] & 0xF) + (a[3] >> 4) \
				+ (a[5] & 0xF) + (a[5] >> 4) + (a[6] >> 4) + (a[7] >> 4)
		if slot == ba_skater_offset:
			s = 0x7FFF
		if s >= best:
			best = s
			pick = slot
	if not chosen:
		if pick < 0:
			return false
		ba_skater_offset = pick
	w.ba_sktr = 6 if ba_team else 0
	return true

## puckpenshot ($1F, L41276): first call lines up the attempt; the second hands the puck
## to pucknorm with the attempt clock live.
func puckpenshot(p: SimObject) -> void:
	if p.flags & SimObject.PF_NA == 0:
		w.f_c2fa |= C2FA_CLOCK_LIVE
		w.assreplace(p, PuckLogic.ASS_PUCKNORM)
		p.vel = Vector2i.ZERO
		return
	p.flags &= ~SimObject.PF_NA
	if w.crowd_level > 0x258:
		w.crowd_level = 0x258
		w.crowd_excite += 0x14
	w.sflags &= ~HockeyWorld.SF_PAUSE
	w.iflags = 0
	w.rules.refcnt = -1
	w.fight.clear_gloves()
	w.passplayer = -1
	w.rules.set_hor(false)
	w.camera = Vector2i.ZERO
	p.set_pos(Vector2i.ZERO)
	p.z_fx = 0
	p.vel = Vector2i.ZERO
	p.zvel = 0
	w.puckc = -1
	for i in [HockeyWorld.NET_TOP, HockeyWorld.NET_BOTTOM]:
		var n := w.objects[i]
		n.vel = Vector2i.ZERO
		n.set_pos(Vector2i(0, 0x10C if i == HockeyWorld.NET_TOP else -0x10C))
	var sh := w.objects[HockeyWorld.SHADOW]
	sh.frame = PuckLogic.SHADOW_FRAME
	sh.spa = 0
	sh.attribute = 0
	p.attribute = 0
	w.sflags &= ~HockeyWorld.SF_SLOCK
	for i in 101:
		w.checkwindow(1)
	w.yleader = 0x3C
	w.lines.reset_bench()
	for team in 2:
		w.lines.set_personel(team)
		_roles(team)
	w.faceoff.resetplstuff()
	for d2 in range(11, -1, -1):
		var o := w.objects[d2]
		if d2 == w.ba_sktr:
			if o.position < 0 and o.flags2 & SimObject.PF2_UNAV:
				o.flags2 &= ~SimObject.PF2_UNAV
				w.setplayer(o, o.pnum & 0xFF)
			_word_x(o, 0)
			if o.attacking_top():
				_word_y(o, -16)
				_facing(o, 0)
			else:
				_word_y(o, 16)
				_facing(o, 4)
			o.vel = Vector2i.ZERO
			o.zvel = 0
			w.assinsert(o, ASS_NEAREST)
		elif d2 == w.ba_goalie:
			if _so():
				o.pnum = so_list[1][5] if w.shootout_side == 0 else so_list[0][5]
				w.setplayer(o, o.pnum & 0xFF)
			elif o.position < 0 and o.flags2 & SimObject.PF2_UNAV:
				o.flags2 &= ~SimObject.PF2_UNAV
				w.setplayer(o, o.pnum & 0xFF)
			o.flags2 &= ~SimObject.PF2_UNAV
			_word_x(o, 0)
			# Q8: the facing comes from the wrong end (+229 for a pfgoal 1 goalie).
			var ytmp := 0xE5 if o.attacking_top() else -0xE5
			_word_y(o, ytmp)
			o.vel = Vector2i.ZERO
			o.z_fx = 0
			_facing(o, SkaterSteering.vtoa(Vector2i(0, -ytmp)))
			o.flags &= ~SimObject.PF_ALOCK
			o.set_spa(Spa.GLIDE)
		else:
			_word_x(o, -240)
			_word_y(o, 0)
			o.frame = 0
			w.assinsert(o, ASS_BREAKWAIT)
	w.collisions.sort_all()
	w.faceoff.setchgplayer()
	var g := w.objects[w.ba_goalie]
	_word_x(g, 0)
	_word_y(g, -250 if g.attacking_top() else 250)
	var t := 2 if g.away() else 1
	if w.cont_team[0] == t:
		w.set_c_player(0, g)
	elif w.cont_team[1] == t:
		w.set_c_player(1, g)
	w.assreplace(g, ASS_GOALIE_CPU)
	w.ba_ps_flags |= BA_INTRO
	w.sflags2 |= SF2_NOREC
	w.ps_intro = 0x190
	if w.cont_team[0] == 0 and w.cont_team[1] == 0:
		w.ps_intro = 0x64

## sub_1592C: the shooter and the goalie take their slots; the rest are parked.
func _roles(team: int) -> void:
	var st := w.stats[team]
	for i in 6:
		var o := w.objects[st.first_object + i]
		var put := false
		if o.index == w.ba_sktr:
			w.setplass(o)
			saved_newpnum = o.newpnum
			o.newpnum = ba_skater_offset & 0xFF
			o.position = SimObject.POS_C
			put = true
		elif o.index == w.ba_goalie:
			w.setplass(o)
			o.position = SimObject.POS_GOALIE
			put = true
		else:
			o.flags2 |= SimObject.PF2_UNAV
			w.assreplace(o, ASS_BREAKWAIT)
		if put:
			var d3 := o.newpnum & 0xFF
			if TeamStats.valid_pnum(d3):
				st.tmpdst[d3] = TeamStats.TMPDST_ON_ICE
			w.setplayer(o, d3)
		o.newpnum = -1
		o.newpos = -1

## sub_187B8 / loc_FC320 through chkprogress: the intro box goes up and freezes the clock.
func show_intro() -> void:
	w.f_c2fa |= HockeyWorld.C2FA_PS_INTRO
	intro.emit(intro_lines())

## The intro text (display only, section 1.5.8).
func intro_lines() -> PackedStringArray:
	var shooter := _name(ba_team, w.objects[w.ba_sktr].pnum if w.ba_sktr >= 0 else -1)
	if _so():
		var gteam := 1 - w.shootout_side
		var goalie := _name(gteam, so_list[gteam][5])
		return PackedStringArray(["SHOOTOUT MODE", "%s vs. %s" % [shooter, goalie],
			"%s %3d   %s %3d" % [_abbr(0), w.shootout_goals[0], _abbr(1), w.shootout_goals[1]],
			"Round %2d" % so_round])
	return PackedStringArray(["PENALTY SHOT!", shooter,
		"%s by %s" % [GameRules.entry(ps_variant)[2], _name(1 - ba_team, ba_checker_offset)]])

func _name(team: int, slot: int) -> String:
	var d := w.stats[team].data
	if d and d.player(slot):
		return d.player(slot).full_name
	return "#%d" % slot

func _abbr(team: int) -> String:
	var d := w.stats[team].data
	return d.abbreviation if d else ("HOME" if team == 0 else "AWAY")

# --- the CPU shooter's script ----------------------------------------------------------

## sub_FE756: a random path, its first waypoint loaded with the puck's handedness (Q2).
func script_init() -> void:
	var p := w.rng.range_(7)
	while p > 6:
		p = w.rng.range_(7)
	ps_path = p
	last_wp = false
	ps_wp_idx = -1
	ps_wp_x = 0
	load_waypoint(w.puck())

## sub_FE7FC: the next waypoint; a lefty mirrors X (the terminator too, Q1).
func load_waypoint(o: SimObject) -> void:
	if (ps_wp_x >> 8) & 0xFF == 0x80:
		return
	ps_wp_idx += 1
	var e := PATH_START[ps_path] + 2 * ps_wp_idx
	ps_wp_x = PATH_WORDS[e]
	if o.handed & 1:
		ps_wp_x = (-ps_wp_x) & 0xFFFF
	ps_wp_y = PATH_WORDS[e + 1]
	if (PATH_WORDS[e + 2] >> 8) == 0x80:
		last_wp = true
		ps_shoot_tol = PATH_WORDS[e + 2] & 0xFF
		w.ps_script_dir = PATH_WORDS[e + 3]

func _finished() -> bool:
	return (ps_wp_x >> 8) & 0xFF == 0x80

## sub_FE864: the waypoint to skate to (raw, attack-top frame), advancing within 10 px
## (18 while standing). Null once the path is finished.
func ps_waypoint(o: SimObject) -> Variant:
	if _finished():
		return null
	var tx := s16(ps_wp_x)
	var ty := s16(ps_wp_y)
	if not o.attacking_top():
		tx = s16(-tx)
		ty = s16(-ty)
	var still := o.vel == Vector2i.ZERO
	var dx := absi(s16(tx - o.x()))
	if dx <= 10 or (still and dx <= 18):
		var dy := absi(s16(ty - o.y()))
		if dy <= 10 or (still and dy <= 18):
			load_waypoint(o)
	if _finished():
		return null
	return Vector2i(s16(ps_wp_x), s16(ps_wp_y))

## sub_FE8EC: shoot now? Three seconds left, the path finished, inside the last
## waypoint's box, or a still puck with under 15 seconds left.
func ps_should_shoot(o: SimObject) -> bool:
	if w.f_c2fa & C2FA_ATTEMPT_CLOCK == 0:
		return false
	if o.index != w.puckc:
		return false
	if ps_clock <= 3:
		return true
	if _finished():
		return true
	if last_wp:
		var tx := s16(ps_wp_x)
		var ty := s16(ps_wp_y)
		if not o.attacking_top():
			tx = s16(-tx)
			ty = s16(-ty)
		if absi(s16(tx - o.x())) > ps_shoot_tol or absi(s16(ty - o.y())) > ps_shoot_tol:
			return false
		return true
	if w.puck().vel != Vector2i.ZERO:
		return false
	return ps_clock < 15

# --- the end of an attempt ------------------------------------------------------------------

## sub_F2F4 (from pucknorm while an attempt is live): over when the goalie has the puck,
## when anyone regains it after the shot or pass, after 101 frames, or at 0:00.
func ps_attempt_check() -> void:
	var over := false
	if w.puckc == w.ba_goalie:
		over = true
	elif w.ba_ps_flags & HockeyWorld.BA_STARTED:
		var count := false
		if w.f_c2fa & C2FA_RELEASED == 0:
			if w.puckc >= 0:
				count = true
			else:
				w.f_c2fa |= C2FA_RELEASED
		if not count and w.puckc >= 0:
			over = true
		elif w.ps_timer < 0:
			over = true
		else:
			w.ps_timer -= 1
	if over:
		w.ba_ps_flags |= HockeyWorld.BA_GOALIE_HELD
	if ps_clock == 0:
		w.ba_ps_flags |= HockeyWorld.BA_GOALIE_HELD
	if w.ba_ps_flags & HockeyWorld.BA_GOALIE_HELD == 0 or w.ba_ps_flags & BA_WHISTLED:
		return
	w.ba_ps_flags |= BA_WHISTLED
	w.add_penalty2(PEN_WHISTLE, w.puck())
	ps_attempt_end()

## sub_F37C: the attempt is over (a goal, or the whistle above).
func ps_attempt_end() -> void:
	w.freezewindow()
	if not _so():
		w.sflags2 |= SF2_NOREC
	w.gmode |= HockeyWorld.GM_CLOCK
	w.f_c2fa &= ~C2FA_CLOCK_LIVE
	w.ba_ps_flags &= ~(HockeyWorld.BA_LIVE | HockeyWorld.BA_AWARDED | HockeyWorld.BA_STARTED
			| HockeyWorld.BA_GOALIE_HELD | BA_WHISTLED)
	if w.ba_sktr >= 0 and w.ba_sktr < 12:
		w.objects[w.ba_sktr].newpnum = saved_newpnum
	next_turn()

# --- the shootout --------------------------------------------------------------------------

## sub_FC47C: a new shootout game: round 1, home first, the lists from each team's first
## data line (shooters RW, C, LW, RD, LD, then the goalie).
func init_shootout() -> void:
	finished = false
	w.so_replay_stop = 0
	so_round = 1
	w.f_c2fa &= ~C2FA_DECIDED
	w.shootout_goals[0] = 0
	w.shootout_goals[1] = 0
	so_shooter_idx = 0
	w.shootout_side = 0
	for team in 2:
		var d := w.stats[team].data
		var ln := d.line(0) if d else PackedInt32Array([1, 0, 0, 0, 0, 0, 0, 0])
		var l := PackedInt32Array()
		for i in range(5, -1, -1):
			l.append(ln[i] - 1)
		so_list[team] = l

## sub_FC4C0: the next shootout attempt, or the end once a winner is known.
func next_shootout_attempt() -> bool:
	if w.f_c2fa & C2FA_DECIDED:
		finished = true
		w.song.emit(0x78)
		w.rules.game_over.emit()
		return false
	script_init()
	ba_team = w.shootout_side
	var list := so_list[0]
	w.ba_goalie = 11
	if w.shootout_side != 0:
		w.ba_goalie = 5
		list = so_list[1]
	ba_skater_offset = list[so_shooter_idx]
	w.puck().flags &= ~SimObject.PF_NC
	return true

## sub_FC516 (after every attempt, penalty shots too, Q4): home then away each round; from
## round 5 a round that ends with the goals unequal decides it.
func next_turn() -> void:
	if w.shootout_side & 1 and so_round >= 5 and w.shootout_goals[0] != w.shootout_goals[1]:
		w.f_c2fa |= C2FA_DECIDED
		celebrate()
		return
	w.shootout_side ^= 1
	if w.shootout_side != 0:
		return
	so_shooter_idx += 1
	if so_shooter_idx >= 5:
		so_shooter_idx = 0
	so_round += 1

## sub_FD618: four of the winners skate on and celebrate (all as roster slot 6, Q10).
func celebrate() -> void:
	w.sflags2 |= SF2_NOREC
	w.freezewindow()
	w.so_replay_stop = 0x60
	var winner := 0 if w.shootout_goals[0] > w.shootout_goals[1] else 1
	var base := 0 if winner == 0 else 6
	for i in range(1, 5):
		var o := w.objects[base + i]
		w.setplayer(o, 6)
		o.position = SimObject.POS_RD
		_word_y(o, w.camera.y + (0xF0 if w.camera.y < 0 else -0xF0))
		_word_x(o, 0)
		w.assinsert(o, ASS_SCORE)
		o.flags &= ~(SimObject.PF_ALOCK | SimObject.PF_NC)
		o.flags2 &= ~SimObject.PF2_AIP
	shootout_won.emit(winner)

## The winner line SetPA prints once the shootout is decided (sub_FC5AE).
func winner_text() -> String:
	var t := 0 if w.shootout_goals[0] > w.shootout_goals[1] else 1
	var d := w.stats[t].data
	return "SHOOTOUT WON BY %s" % (d.display_name() if d else _abbr(t))

# --- word stores -----------------------------------------------------------------------------

static func _facing(o: SimObject, d: int) -> void:
	o.facing_fx = (d << 16) | (o.facing_fx & 0xFFFF)

static func _word_x(o: SimObject, v: int) -> void:
	o.pos_fx.x = (v << 16) | (o.pos_fx.x & 0xFFFF)

static func _word_y(o: SimObject, v: int) -> void:
	o.pos_fx.y = (v << 16) | (o.pos_fx.y & 0xFFFF)
