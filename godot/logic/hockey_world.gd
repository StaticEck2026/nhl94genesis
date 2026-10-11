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
const SF2_OFFSIG := 1 << 7   ## delayed-offside ref up (checkob)
## sflags3 bits.
const SF3_FACEOFF_WIN := 1 << 4
const SF3_PENSEC := 1 << 6
const SF3_MUSIC_CUE := 1 << 7  ## mid-period music cue armed (periods 1-2)
## word_FFC2F6.
const C2F6_BREAKAWAY_RAN := 1 << 2 ## this loop's asspuckc/assnearest came through breakaway()
const C2F6_FLIP := 1 << 3     ## flip-pass request (A with the puck)
const C2F6_TOPSHELF := 1 << 4 ## in-close top-shelf shot (prepshot)
## word_FFC2F4.
const C2F4_GOAL := 1 << 0
const C2F4_REACTED := 1 << 1  ## the goalie's goal-against reaction has played
const C2F4_SFX := 1 << 3      ## dead sfx-played flag (assgoaliecpu)
const C2F4_PS_GOAL := 1 << 5
## word_FFC2F8.
const C2F8_ONETIMER_SHOT := 1 << 1
const C2F8_HIGH_DUMP := 1 << 2 ## flip pass is the high dump ($3A apex)
const C2F8_NET := 1 << 4     ## net collision: wallcoll consumes it and skips the wall bit
const C2F8_SLOT := 1 << 5    ## puck carrier in the slot (setSlotBit)
## word_FFC2FA.
const C2FA_SHOOTOUT := 1 << 0
const C2FA_BREAKAWAY := 1 << 4
const C2FA_PS_INTRO := 1 << 7  ## penalty-shot / shootout intro screen up
## byte_FFC2FE.
const C2FE_PS_GOAL := 1 << 0
const C2FE_GOAL_TOGGLE := 1 << 3
const C2FE_ONETIMER_TOUCH := 1 << 7
## BA_PS_flags.
const BA_LIVE := 1 << 2
const BA_AWARDED := 1 << 3
const BA_GOALIE_HELD := 1 << 4 ## the PS goalie held the puck too long
const BA_STARTED := 1 << 5   ## the one PS pass or shot has been used
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
## The game layer's switch for the rules (the skating sandbox runs without them);
## SimSettings.enable_rules is the debug dock's.
var rules_active: bool = true
var rng: RetailRng
## Stand-in for reads of the VDP H/V counter, which retail uses as a cheap random number.
## Kept apart from `rng` so the seeded sequence matches retail call for call.
var hv_rng := RandomNumberGenerator.new()
var motion: SkaterMotion
var steering: SkaterSteering
var collisions: Collisions
var checking: Checking
var puck_logic: PuckLogic
var shooting: Shooting
var input: InputLogic
var ai: HockeyAI
var goalie: GoalieLogic
var roster: RosterLogic
var rules: GameRules
var faceoff: FaceoffLogic
var lines: LineLogic
var shootout: ShootoutLogic
var fight: FightLogic
## Hot spot per sprite frame (Hotlist, exported offline to res://data/hotlist.json).
var hotlist: Array = []
## updateanim with the SPAList data. When the data file is missing (no extraction run),
## frames stay put and GetHot falls back to a facing-based stick position.
var animator: Animator
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
var f_c2f6: int = 0
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
## byte_FFC2FC bit 4: "auto lines" (OptLine 2): no fatigue, energy reads as $1000.
var no_fatigue: bool = false
## OptLine == 0: line changes on (burst drains energy only then).
var opt_line_on: bool = true
## The on-ice markers (word_FFBE78 / word_FFBE86 nibbles), one per ffo object: 0 the
## puck-carrier star (or the penalized player on the penalty screen), 1 pad 1's star, 2 pad
## 2's star, 3 the replay cursor, 4-5 pads 3-4. A value is the marked object's index, $E
## the object's own position, $F hidden. Drawn by IndicatorsView.
const MARK_HIDDEN := 0xF
var marks: PackedInt32Array = PackedInt32Array([0xF, 0xF, 0xF, 0xF, 0xF, 0xF])
## OptFight (the fight patch's menu option, $FFDF00): 0 off (retail), 1 on, 2 on, Arcade.
var opt_fight: int = 0
## OptPen: penalties on; with OptPen 1 offsides are called too.
var opt_pen: bool = true
var opt_offsides: bool = true
## OptPerlen: period length 0-3 (5, 10, 20 minutes, 30 seconds; ClockLength).
var opt_perlen: int = 0
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
## Passing and shooting: direction 0-7 (8 none) and speed (passdir, passspeed).
var passdir: int = 8
var passspeed: int = 0
## One-timer: shooter (onetimerplayer, -1 none), word_FFBF76 state, and the pad that
## asked for it (inputjoy, -1 = CPU).
var onetimerplayer: int = -1
var onetimer_state: int = 0
var inputjoy: int = -1
## Flip pass target (word_FFD414/416) and apex height (word_FFD418).
var flip_target: Vector2i = Vector2i.ZERO
var flip_apex: int = 0x12
## Penalty shot / shootout: CPU script shot direction (word_FFDA1A), attempt timer
## (word_FFC31C) and intro countdown (word_FFC31A).
var ps_script_dir: int = 0
var ps_timer: int = 0
var ps_intro: int = 0
## Pads 1 and 2, the per-pad B and A counters (word_FFBF06, word_FFD41E bytes), the
## faceoff grace countdown (word_FFD412), Auto Goalie per pad (word_FFD05A/C) and the
## faceoff pull directions (fodir1 bottom, fodir2 top).
var pads: Array[PadState] = [PadState.new(), PadState.new()]
var b_cnt: PackedInt32Array = PackedInt32Array([0x11, 0x11])
var a_timer: PackedInt32Array = PackedInt32Array([0, 0])
var faceoff_grace: int = 0
var auto_goalie: Array[bool] = [true, true]
var fodir: PackedInt32Array = PackedInt32Array([-1, -1])
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
## word_FFD06E: VDP status bit 0 at boot, the PAL flag. PAL consoles move 22 per
## vblank instead of 17 to make up for 50 Hz.
var alt_step: bool = false
## byte_FFC2FC bit 6: the crowd record is broken. The AI and goalie reaction timers
## reload one shorter while it is set.
var crowd_record: bool = false
## threat: opponents near the CPU carrier (loc_E12C); the goalie sets 1 before chk4pass.
var threat: int = 0
## deltax / deltay: avdgoal's last target correction.
var deltax: int = 0
var deltay: int = 0
## Hpos / Vpos: the camera centre in rink coordinates (checkwindow), and yleader, the
## look-ahead in the carrier's attacking direction.
var camera: Vector2i = Vector2i.ZERO
var yleader: int = 0
## fox / foy: the next faceoff spot.
var fox: int = 0
var foy: int = 0
## lldisp: periodiceevents countdown for the once-a-second checks.
var lldisp: int = 0
## Shootout replay stop countdown (assscore).
var so_replay_stop: int = 0

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
## puckstick handed a loose puck to a one-timer shooter (onetimershot).
signal onetimer_shot(index: int)
## Start pressed on pad k.
signal pause_requested(k: int)
## PushRef: the referee graphic (6 delayed offside up, $40 clear).
signal ref_signal(id: int)
## loc_1871C: the injury message is due.
signal injury_message

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
		if i >= 12:
			# The struct clear: no animation on the nets, puck and shadow.
			o.spa = 0
		objects.append(o)
		joy[i] = SkaterSteering.JOY_NONE
	stats[0].first_object = 0
	stats[1].first_object = 6
	collisions = Collisions.new(self)
	checking = Checking.new(self)
	puck_logic = PuckLogic.new(self)
	shooting = Shooting.new(self)
	input = InputLogic.new(self)
	ai = HockeyAI.new(self)
	goalie = GoalieLogic.new(self)
	roster = RosterLogic.new(self)
	rules = GameRules.new(self)
	faceoff = FaceoffLogic.new(self)
	lines = LineLogic.new(self)
	shootout = ShootoutLogic.new(self)
	fight = FightLogic.new(self)
	ai.register(asstab)
	goalie.register(asstab)
	faceoff.register(asstab)
	lines.register(asstab)
	shootout.register(asstab)
	fight.register(asstab)
	asstab[Shooting.ASS_SHOOT] = func(o: SimObject, d7: int) -> void: shooting.assshoot(o, d7)
	asstab[Shooting.ASS_PASSREC] = func(o: SimObject, d7: int) -> void: shooting.asspassrec(o, d7)
	asstab[Shooting.ASS_ONETIMER] = func(o: SimObject, d7: int) -> void: shooting.assonetimer(o, d7)
	onetimer_shot.connect(func(i: int) -> void: shooting.onetimershot(objects[i]))
	asstab[PuckLogic.ASS_PUCKNORM] = func(o: SimObject, d7: int) -> void: puck_logic.pucknorm(o, d7)
	asstab[PuckLogic.ASS_PUCKSHADOW] = func(o: SimObject, _d7: int) -> void: puck_logic.puckshadow(o)
	asstab[PuckLogic.ASS_PUCKUNFLIP] = func(o: SimObject, _d7: int) -> void: puck_logic.puckunflip(o)
	_load_hotlist()
	animator = Animator.new()
	frames_live = animator.loaded() and not hotlist.is_empty()
	collisions.sort_all()

func _load_hotlist() -> void:
	var path := "res://data/hotlist.json"
	if not FileAccess.file_exists(path):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if data is Dictionary and data.has("frames"):
		hotlist = data["frames"]
	# The fight patch's entries from 838 on (empty spots for the arrows, then the fight
	# frames). Retail objects never show frames past 837.
	path = "res://data/hotlist_fight.json"
	if not FileAccess.file_exists(path):
		return
	data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if data is Dictionary and data.has("frames") and int(data["first"]) == hotlist.size():
		hotlist.append_array(data["frames"])

## Breaks the reference cycles between the world and its modules. Call when a match ends.
func dispose() -> void:
	for m in [collisions, checking, puck_logic, shooting, input, ai, goalie, roster, rules, faceoff, lines, shootout, fight]:
		if m:
			m.w = null
	collisions = null
	checking = null
	puck_logic = null
	shooting = null
	input = null
	ai = null
	goalie = null
	roster = null
	rules = null
	faceoff = null
	lines = null
	shootout = null
	fight = null
	asstab.clear()
	for c in onetimer_shot.get_connections():
		onetimer_shot.disconnect(c["callable"])

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
	if role == SimObject.POS_GOALIE and stats[o.team()].goalie_pnum < 0:
		# Retail rosters list goalies first, so slot 0 stands in when none is loaded.
		stats[o.team()].goalie_pnum = o.pnum if TeamStats.valid_pnum(o.pnum) else 0
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
	# pucknorm with pfna: the stalled-puck countdown starts from $78.
	assreplace(p, PuckLogic.ASS_PUCKNORM)
	puckc = -1
	collisions.sort_all()

# --- the loop ------------------------------------------------------------------------

## One DoGameFrame with d7 vblanks elapsed: the VBlank clock ticks, then
## periodiceevents, updateplayers, setSlotBit, checkwindow.
func step(d7: int = 1) -> void:
	for i in d7:
		rules.vblank_tick()
		vcount += 1
	periodic_events(d7)
	update_players(d7)
	ai.set_slot_bit()
	checkwindow(d7)
	# setvideo: the crowd meter, then the sprites (addframe2 keeps the frame it drew last;
	# chkhit tests a hit once per new frame).
	rules.crowd_noise(d7)
	# addframe2 keeps the frame it drew last ($08); chkhit tests a hit once per new frame.
	for o in objects:
		o.old_frame = o.frame & 0x7FF

## periodiceevents (L29940): the penalty manager, crowd and clock every frame; the
## once-a-second jobs every 24 vblanks (not on the sideways penalty screen).
func periodic_events(d7: int) -> void:
	rules.penalty_manager(d7)
	rules.updatecrowdf(d7)
	rules.updatesound()
	rules.clockcont()
	if sflags & SF_HOR:
		return
	lldisp -= d7
	if lldisp >= 0:
		return
	lldisp += 0x18
	goalie.chk_goalies()
	rules.update_cwd_excite()
	rules.third_period_music()
	_bench_recovery()
	_injury_countdown()
	rules.updatepwrplay()

## loc_79EA: the injury message countdown.
func _injury_countdown() -> void:
	inj_countdown -= 1
	if inj_countdown == 0:
		injury_message.emit()

## freezewindow: hold the camera where it is.
func freezewindow() -> void:
	scroll_lock = camera
	sflags |= SF_SLOCK

## setupice (L53024) for the simulation: defaultsprites2 resets all 16 objects, then the
## teams swap ends when gmdir is set. Objects wait off the ice until forcepldata.
func setupice() -> void:
	for i in SORT_OBJS:
		var o := objects[i]
		var row: Array = DEFAULT_OBJECTS[i]
		var fresh := SimObject.new(i)
		fresh.set_pos(Vector2i(row[0], row[1]))
		fresh.z_fx = row[2] << 16
		fresh.frame = row[3]
		fresh.attribute = row[4]
		fresh.radius = Vector2i(row[6], row[7])
		fresh.asslist[0] = row[8]
		fresh.flags = row[9]
		# The struct clear leaves every position 0 until forcepldata (the shootout relies
		# on it: its goalie objects are never given a position).
		fresh.position = 0
		if i >= 12:
			fresh.spa = 0
		if i < 12 and gmode & GM_DIR:
			fresh.flags ^= SimObject.PF_GOAL
		o.copy_from(fresh)
	puckc = -1
	camera = Vector2i.ZERO
	marks.fill(MARK_HIDDEN)
	collisions.sort_all()

## periodiceevents loc_79F8: with line changes on, every benched slot gains 9 energy a
## second, up to $1000.
func _bench_recovery() -> void:
	if not opt_line_on:
		return
	for st in stats:
		for i in TeamStats.ROSTER:
			if st.tmpdst[i] == TeamStats.TMPDST_BENCH:
				st.energy[i] = mini(st.energy[i] + settings.bench_recovery, 0x1000)

## checkwindow (L35783): the camera follows the carrier (with a lead in his attacking
## direction) or the puck, easing 1/16 of the way once outside a dead zone.
func checkwindow(d7: int) -> void:
	var d2 := scroll_lock.y
	var d3 := scroll_lock.x
	if sflags & SF_SLOCK == 0:
		var a3 := puck()
		if puckc >= 0 and puckc < 12:
			a3 = objects[puckc]
			if a3.attacking_top():
				yleader = mini(yleader + d7 * 2, 0x32)
			else:
				yleader = maxi(yleader - d7 * 2, -0x32)
		d2 = s16((s16(a3.vel.y) >> 7) + a3.y() + yleader)
		d3 = a3.x()
		scroll_lock = Vector2i(d3, d2)
	var d0 := s16(d2 - camera.y)
	var d1 := 0
	var moved := true
	if d0 < -10:
		d1 = maxi(d2 + 10, -0xC8)
	elif d0 > 10:
		d1 = mini(d2 - 10, 0x100)
	else:
		moved = false
	if moved:
		camera.y = s16(camera.y + _ease(s16(d1 - camera.y)))
	d0 = s16(d3 - camera.x)
	if d0 < -40:
		d1 = maxi(d3 + 40, -0x3C)
	elif d0 > 40:
		d1 = mini(d3 - 40, 0x3C)
	else:
		return
	camera.x = s16(camera.x + _ease(s16(d1 - camera.x)))

## checkwindow step: asr #4, at least 1 when not 0.
static func _ease(d: int) -> int:
	if d == 0:
		return 0
	var s := d >> 4
	return s if s != 0 else 1

## updateplayers (L35329) for every sort object.
func update_players(d7: int) -> void:
	puck_logic.z_stall()
	_preamble()
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
		# _done (L35557): the puck carrier on the ice gets the filled star, unless fighting.
		if o.index == puckc and not o.fighting() and sflags & SF_HOR == 0:
			marks[0] = o.index
		_dispatch_pads(o, d7)
		_assignment(o, d7)
		# Clear wallcos/wallsin, then checkcoll if the pixel position changed.
		o.wall = Vector2i.ZERO
		if o.pos() != o.old_pos():
			_check_collisions(o)
		_impact_decay(o, d7)

## updateplayers L35354-35371, once a loop: the crowd-record bit; while someone has the
## puck, the one-timer flags clear (so the goalies get their full body box back), and a
## carrier on a breakaway clears the breakaway-shot flag.
func _preamble() -> void:
	# L35330: the puck-carrier star goes until a carrier claims it this loop.
	if sflags & SF_HOR == 0:
		marks[0] = MARK_HIDDEN
	crowd_record = rules.cur_crowd_meter >= rules.crowd_record_value
	crowd_boost = true
	if puckc < 0:
		return
	f_c2fe &= ~C2FE_ONETIMER_TOUCH
	f_c2f8 &= ~C2F8_ONETIMER_SHOT
	if puckc < 12 and objects[puckc].flags3 & SimObject.PF3_BREAKAWAY:
		f_c2fa &= ~C2FA_BREAKAWAY

## updateanim (L35703). Without SPAList data, a fixed-length stand-in keeps the
## pf2aip / pfalock / falling flags from sticking.
const FALLBACK_ANIM_FRAMES := 20

func _update_anim(o: SimObject, d7: int) -> void:
	if animator.loaded():
		animator.update(o, d7, sflags & SF_HOR != 0)
		return
	var busy := o.anim_busy() or o.locked() or o.flags3 & SimObject.PF3_FALLING
	if not busy:
		return
	if o.spa_cnt < 0:
		o.spa_cnt = FALLBACK_ANIM_FRAMES
		return
	o.spa_num = 4
	o.spa_cnt -= d7
	if o.spa_cnt < 0:
		o.flags2 &= ~SimObject.PF2_AIP
		o.flags &= ~SimObject.PF_ALOCK
		o.flags3 &= ~SimObject.PF3_FALLING
		o.spa = 0

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
	# updateplayers L35483: an injured player lying on the ice does not move at all.
	if o.spa == Checking.SPA_INJURED_GAME or o.spa == Checking.SPA_INJURED_PERIOD:
		return
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

## updateplayers L35567-35597: the faceoff grace countdown (once per processed object,
## as retail), then doinput for the object a pad controls.
func _dispatch_pads(o: SimObject, d7: int) -> void:
	if sflags2 & SF2_FACEOFF == 0 and faceoff_grace != 0:
		faceoff_grace -= 1
		if faceoff_grace <= 0:
			faceoff_grace = 0
			b_cnt[0] = 0x11
			b_cnt[1] = 0x11
	for k in 2:
		if c_player[k] == o.index:
			pads[k].read()
			input.doinput(o, pads[k], k, d7)
			return

## The assignment call: asstab[asslist[assnum]]. Skaters without an assignment but with
## a stick value in `joy` (tests, sandbox) skate with it.
func _assignment(o: SimObject, d7: int) -> void:
	var id: int = o.asslist[o.assnum & 7]
	if asstab.has(id):
		if _module_off(id):
			assnothing(o, d7)
			return
		asstab[id].call(o, d7)
	elif o.index < 12 and not o.joypad() and joy[o.index] != SkaterSteering.JOY_NONE:
		skate(o, joy[o.index], d7)

## The debug dock's module toggles: skater AI and goalie AI assignments idle (glide to
## a stop) while their module is off. Pad players and the puck are unaffected.
func _module_off(id: int) -> bool:
	if not settings.enable_skater_ai and id in HockeyAI.AI_IDS:
		return true
	return not settings.enable_goalie_tracking and id in GoalieLogic.CPU_IDS

## Setplass (L51533): the default assignment for the position (_alist L51542).
const ALIST: Array[int] = [0x0E, 0x02, 0x02, 0x03, 0x05, 0x03, 0x05]

func setplass(o: SimObject) -> void:
	if o.position < 0:
		return
	assreplace(o, ALIST[clampi(o.position, 0, 6)])

## forcepldata (L51446), at faceoffs: each of the team's objects takes its newpos (off
## the ice when it has none), gets its Setplass assignment (the centre also chases the
## puck), and setplayer loads its roster slot. newpos and newpnum are then cleared.
func forcepldata(team: int) -> void:
	var st := stats[team]
	for i in 6:
		var o := objects[st.first_object + i]
		o.position = o.newpos if o.newpos >= 0 else SimObject.POS_OFF_ICE
		if o.position >= 0:
			setplass(o)
			if o.position == SimObject.POS_C:
				assinsert(o, HockeyAI.ASS_NEAREST)
			var p := o.newpnum & 0xFF
			if TeamStats.valid_pnum(p):
				st.tmpdst[p] = TeamStats.TMPDST_ON_ICE
			setplayer(o, p)
		o.newpnum = -1
		o.newpos = -1

## setplayer (L51556): roster slot pnum takes the object (RosterLogic).
func setplayer(o: SimObject, pnum: int) -> void:
	roster.setplayer(o, pnum)

## assnothing (L38275): locked or pad players do nothing; others glide to a stop.
func assnothing(o: SimObject, d7: int) -> void:
	if o.locked() or o.joypad():
		return
	skate(o, SkaterSteering.JOY_NONE, d7)

## The goalie of team (position 0 among its six objects), or null.
func goalie_of(team: int) -> SimObject:
	for i in 6:
		var o := objects[team * 6 + 5 - i]
		if o.position == SimObject.POS_GOALIE:
			return o
	return null

## getpde / setpde: raw stored energy of a roster slot ($1000 if no slot).
func energy_raw(o: SimObject) -> int:
	if o.index > 11 or not TeamStats.valid_pnum(o.pnum):
		return 0x1000
	return stats[o.team()].energy[o.pnum]

func set_energy(o: SimObject, e: int) -> void:
	if o.index <= 11 and TeamStats.valid_pnum(o.pnum):
		stats[o.team()].energy[o.pnum] = maxi(e, 0)

## The offside signal check (checkob) and the goalie save (goaliesave) hooks.
func checkob(o: SimObject) -> void:
	ai.checkob(o)

## doinput's save button: goaliesave with the goalie's goal line at +-$108.
func goalie_save(o: SimObject) -> void:
	if o.attacking_top():
		goalie.goaliesave(o, 2, -0x108)
	else:
		goalie.goaliesave(o, 0, 0x108)

## ReadGoaliePulled for a team.
func goalie_pulled(team: int) -> bool:
	return goalie.goalie_pulled(team)

## SetPersonel (L51236): which roster players the line wants on.
func set_personel(team: int) -> void:
	lines.set_personel(team)

## sub_E1F4's line change before the dump-in: CompLine, SetPersonel.
func cpu_line_change(team: int) -> void:
	lines.comp_line(team)
	lines.set_personel(team)

## sub_12EF6: mean stored energy of the team's objects with position > 0; 0 if none.
func average_energy(team: int) -> int:
	var total := 0
	var n := 0
	for i in 6:
		var o := objects[team * 6 + i]
		if o.position <= 0:
			continue
		total += energy_raw(o)
		n += 1
	return total / n if n > 0 else 0

## The CPU shooter's script in a penalty shot or shootout (sub_FE8EC, sub_FE864).
func ps_should_shoot(o: SimObject) -> bool:
	return shootout.ps_should_shoot(o)

func ps_waypoint(o: SimObject) -> Variant:
	return shootout.ps_waypoint(o)

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

## doplayeracc + playeracc for one skater with one stick value. Goalies go to
## goalieacc.
func skate(o: SimObject, stick: int, d7: int = 1) -> void:
	if o.position == SimObject.POS_GOALIE and o.index < 12:
		goalie.goalieacc(o, stick, d7)
		return
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
			playeracc(o, r.accel_dir, d7)
		SkaterSteering.Action.STOP:
			o.vel = motion.apply_stop(o.vel)

## playeracc (L43705) in an absolute direction 0-7 (8 is dirtab's zero entry), then the
## energy drain, which runs whether or not the speed cap let the push through.
func playeracc(o: SimObject, dir: int, d7: int) -> void:
	if dir >= 0 and dir <= 7:
		o.vel = motion.apply_accel(skater_view(o), o.vel, motion.dirtab(dir), d7, o.wall)
	_drain_energy(o)

## playeracc _sube (L43828): with line changes on, 1 call in 128 drains 33, less half
## the endurance byte while the player is above 75%.
func _drain_energy(o: SimObject) -> void:
	if not opt_line_on or o.index > 11:
		return
	if hv_rng.randi() % maxi(settings.energy_drain_gate, 1) != 0:
		return
	var e := energy_raw(o) - roundi(settings.energy_drain)
	if e < 0xC00:
		set_energy(o, e)
		return
	e += (o.endurance & 0xFF) >> 1
	set_energy(o, e)
	if o.endurance & 1 and vcount & 1:
		set_energy(o, e + 1)

## SkaterMotion inputs for an object, including the global boosts.
func skater_view(o: SimObject) -> SkaterMotion.Skater:
	var s := SkaterMotion.Skater.new()
	s.weight = o.weight
	s.agility = o.legstr
	s.speed = o.legspd
	s.energy = energy_of(o)
	s.is_goalie = o.is_goalie()
	s.crowd_boost = crowd_boost
	s.ignore_energy = no_fatigue
	s.joypad = o.joypad()
	s.has_puck = puckc == o.index
	s.fight_injured = o.flags2 & SimObject.PF2_FIGHT_HURT != 0
	return s

## Energy of a player (team struct $32 + 2 * pnum); $1000 with line changes off or for
## objects without a roster slot.
func energy_of(o: SimObject) -> int:
	if no_fatigue or o.index > 11 or not TeamStats.valid_pnum(o.pnum):
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
		if o.attribute & SimObject.ATTR_XFLIP:
			x = -x
		if o.attribute & SimObject.ATTR_YFLIP == 0:
			y = -y
		# The sideways penalty screen swaps the axes (exg d0,d1; neg d1).
		if sflags & SF_HOR:
			return Vector2i(y, -x)
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

## setc1player / setc2player with restorep1 (L37335): pad k now drives object o. The
## old player goes back to the CPU (restarting his assignment unless one-timing), but
## not while his line menu is open. In a penalty shot or shootout an Auto Goalie team
## hands the pad its first object instead of the goalie.
func set_c_player(k: int, o: SimObject) -> void:
	var d0 := o.index
	if d0 == c_player[k]:
		return
	var d1 := c_player[k]
	if d1 >= 0 and d1 < 12:
		var old := objects[d1]
		if old.flags2 & SimObject.PF2_LCMENU:
			return
		old.flags &= ~SimObject.PF_JOYCON
		if old.flags3 & SimObject.PF3_ONETIMER == 0:
			old.flags |= SimObject.PF_NA
	if d0 >= 0 and d0 < 12:
		if (ba_ps_flags & BA_LIVE or f_c2fa & C2FA_SHOOTOUT) and o.position == SimObject.POS_GOALIE \
				and auto_goalie[o.team()]:
			c_player[k] = 6 if o.away() else 0
			return
		o.flags |= SimObject.PF_JOYCON
	c_player[k] = d0

## AddPenalty / AddPenalty2 / PenShotChk / sub_1284A (GameRules).
func add_penalty(id: int, offender: SimObject) -> void:
	rules.add_penalty(id, offender)

func add_penalty2(id: int, offender: SimObject) -> void:
	rules.add_penalty2(id, offender)

func pen_shot_chk(id: int, victim: SimObject, offender: SimObject = null) -> int:
	return shootout.pen_shot_chk(id, victim, offender)

func pp_goal(scoring_team: int) -> void:
	rules.pp_goal(scoring_team)

## sub_F2F4 / sub_F37C: the end of a penalty-shot or shootout attempt (ShootoutLogic).
func ps_attempt_check() -> void:
	shootout.ps_attempt_check()

func ps_attempt_end() -> void:
	shootout.ps_attempt_end()

## sub_FEFF0: cancel a one-timer. Shooting port.
func cancel_onetimer(o: SimObject) -> void:
	# sub_FEFF0: the whole one-timer exit (state, player, Setplass or assexit, SPA restart).
	shooting.end_onetimer(o)

# --- helpers -------------------------------------------------------------------------

static func _sbyte(b: int) -> int:
	return b - 256 if b >= 128 else b

## Signed 16-bit wrap.
static func s16(v: int) -> int:
	v &= 0xFFFF
	return v - 0x10000 if v >= 0x8000 else v
