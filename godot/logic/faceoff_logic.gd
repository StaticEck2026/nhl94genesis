class_name FaceoffLogic
extends RefCounted
## Faceoffs: the puck's puckfaceoff ($1B) and puckfaceoff2 ($1C) assignments (line
## changes, the line-up, the drop countdown), Endfaceoff (the draw), the skaters'
## assfaceoff ($16) and the centres' assfaceoffpl ($17), updatefaceoff (the referee in
## the close-up window), setchgplayer and resetplstuff.
## Spec: docs/specs/faceoffs_offsides.md section 5.

const ASS_FACEOFF := 0x16
const ASS_FACEOFFPL := 0x17
const ASS_PUCKFACEOFF := 0x1B
const ASS_PUCKFACEOFF2 := 0x1C

const SPA_PULL := 0xFEA
const SPA_READY := 0x1014

## _apl: line-up spot by strength row (6, 5, 4 on the ice) and position 0-7.
const APL: Array = [[0, 1, 2, 3, 4, 5, 6, 0], [0, 1, 5, 3, 4, 2, 0, 0], [0, 3, 5, 1, 4, 0, 0, 0]]
## _ptab: spot offsets for a team attacking the top (the goalie's is absolute).
const PTAB: Array[Vector2i] = [Vector2i(0, -250), Vector2i(-35, -50), Vector2i(35, -50),
	Vector2i(-50, -10), Vector2i(0, -15), Vector2i(50, -10), Vector2i(0, -60)]
## _ftab: draw bonus per close-up frame 1-6.
const FTAB: Array[int] = [0, 8, 16, 0, 8, 16]
## unk_FECE6: overlay ids picked for a faceoff.
const OVERLAYS: Array[int] = [3, 5, 3, 1, 5, 2, 3, 3]

var w: HockeyWorld
## fofdata: close-up window frames and attributes: home centre, away centre, referee.
var fof_frame: PackedInt32Array = PackedInt32Array([1, 4, 7])
var fof_attr: PackedInt32Array = PackedInt32Array([0x8000, 0xA800, 0x8000])
## The close-up window is up (disflags bit 4), and its screen origin (fodropx/fodropy).
var window_open: bool = false
var fodrop: Vector2i = Vector2i(0x36, 0x5C)
## word_FFD6BE (overlay asked for, -1 none) and word_FFD6B4 (overlay showing).
var overlay_request: int = -1
var overlay_shown: int = -1

## The line-up is done and the drop countdown runs.
signal faceoff_set
## The puck was dropped; home_won is the draw (the faceoff-won stat goes to whoever
## gets the puck first).
signal faceoff_dropped(home_won: bool)

func _init(world: HockeyWorld) -> void:
	w = world

func register(t: Dictionary) -> void:
	t[ASS_FACEOFF] = func(o: SimObject, _d7: int) -> void: assfaceoff(o)
	t[ASS_FACEOFFPL] = func(o: SimObject, _d7: int) -> void: assfaceoffpl(o)
	t[ASS_PUCKFACEOFF] = func(o: SimObject, d7: int) -> void: puckfaceoff(o, d7)
	t[ASS_PUCKFACEOFF2] = func(o: SimObject, _d7: int) -> void: puckfaceoff2(o)

static func _neg(v: int) -> bool:
	return HockeyWorld.s16(v) < 0

# --- puckfaceoff ($1B) -------------------------------------------------------------------

## puckfaceoff (L41627): end-of-period checks, goalies back, line changes; then $1C.
func puckfaceoff(p: SimObject, d7: int) -> void:
	w.f_c2fe &= ~(1 << 4)
	if w.f_c2fa & HockeyWorld.C2FA_SHOOTOUT:
		p.vel = Vector2i.ZERO
		w.assreplace(p, GameRules.ASS_PUCKSHOOTOUT)
		return
	if p.flags & SimObject.PF_NA:
		p.flags &= ~SimObject.PF_NA
		if _first_call(p):
			return
	# WAIT: the human line-change timers.
	_line_timer(p, 0, d7)
	_line_timer(p, 1, d7)
	if not _neg(p.temp[0]) or not _neg(p.temp[1]):
		return
	_cpu_line(0)
	overlay_request = -1
	w.assreplace(p, ASS_PUCKFACEOFF2)

## The first call. True when it left for the end of a period or the delayed whistle.
func _first_call(p: SimObject) -> bool:
	if w.f_c2fe & HockeyWorld.C2FE_PS_GOAL:
		w.f_c2fe &= ~HockeyWorld.C2FE_PS_GOAL
		w.fox = 0
		w.foy = 0
	# Stats overlay for this faceoff (sub_FECAA). Cosmetic, but it sets the drop minimum.
	var id := overlay_request
	if id < 0:
		id = OVERLAYS[w.rng.range_(100) & 7]
		if w.fox <= -64 and w.foy <= 192:
			id = 6
	overlay_request = id
	w.f_c2f8 &= ~(1 << 1)
	w.f_c2fa &= ~(1 << 1)
	if w.gameclock == 0 or w.gmode & HockeyWorld.GM_EOG:
		w.rules.period_over()
		return true
	if w.gsp == 3 and w.stats[0].goals != w.stats[1].goals:
		w.rules.end_of_period()
		return true
	if w.gmode & HockeyWorld.GM_PENDEL:
		w.rules.stop4pen(-1)
		return true
	# Mid-period music: the cue is consumed here.
	if (w.rules.per_time_total >> 1) > w.gameclock and w.gameclock >= 60 \
			and w.sflags3 & HockeyWorld.SF3_MUSIC_CUE:
		w.sflags3 &= ~HockeyWorld.SF3_MUSIC_CUE
		if w.gmode & HockeyWorld.GM_CLOCK and w.f_c2fe & (1 << 6) == 0:
			w.f_c2fe |= 1 << 4
			w.song.emit(2)
	w.goalie.return_goalies()
	p.temp[0] = -0x100
	p.temp[1] = -0x100
	if w.opt_line_on:
		for st in w.stats:
			st.flags30 &= ~TeamStats.F30_LINE_MENU
		for i in 12:
			w.objects[i].flags2 &= ~SimObject.PF2_LCMENU
		if w.sflags & HockeyWorld.SF_HOR and (w.cont_team[0] | w.cont_team[1]):
			w.sflags |= HockeyWorld.SF_SLOCK
			w.rules.set_hor(false)
		for k in 2:
			if w.c_player[k] >= 0 and w.c_player[k] < 12:
				_open_menu(p, w.objects[w.c_player[k]])
		_cpu_line(1)
	return false

## sub_F5C6: open a pad player's line menu with its timer (home 600, away 360 loops).
func _open_menu(p: SimObject, o: SimObject) -> void:
	o.flags2 &= ~SimObject.PF2_LCMENU
	w.lines.set_lc_mode(o)
	if o.flags2 & SimObject.PF2_LCMENU == 0:
		return
	if o.away():
		p.temp[1] = 0x168
		p.temp[3] = o.index
	else:
		p.temp[0] = 0x258
		p.temp[2] = o.index

## sub_F64E: a menu timer; on expiry the menu takes row A.
func _line_timer(p: SimObject, k: int, d7: int) -> void:
	if _neg(p.temp[k]):
		return
	var o := w.objects[clampi(p.temp[k + 2], 0, 11)]
	if o.flags2 & SimObject.PF2_LCMENU == 0:
		p.temp[k] = -0x100
		w.lines.menu_changed.emit(o.team())
		return
	p.temp[k] = HockeyWorld.s16(p.temp[k] - d7)
	if p.temp[k] >= 0:
		return
	w.lines.lcfound(o, 0)

## sub_F590: the CPU picks and sends a line (every team with Auto lines).
func _cpu_line(team: int) -> void:
	if not w.opt_line_on:
		return
	if not w.no_fatigue and (w.cont_team[0] == team + 1 or w.cont_team[1] == team + 1):
		return
	w.lines.comp_line(team)
	w.lines.set_personel(team)

# --- puckfaceoff2 ($1C) --------------------------------------------------------------------

## puckfaceoff2 (L42031): line everyone up, then count down to the drop.
func puckfaceoff2(p: SimObject) -> void:
	if p.flags & SimObject.PF_NA:
		p.flags &= ~SimObject.PF_NA
		_setup(p)
		return
	p.temp[0] = HockeyWorld.s16(p.temp[0] - 1)
	if p.temp[0] >= 0:
		updatefaceoff(p)
		return
	overlay_shown = -1
	endfaceoff(p)

func _setup(p: SimObject) -> void:
	w.ba_ps_flags &= ~(HockeyWorld.BA_LIVE | HockeyWorld.BA_STARTED)
	w.f_c2f4 &= ~(HockeyWorld.C2F4_GOAL | HockeyWorld.C2F4_REACTED)
	w.delayed_pen &= ~7
	w.faceoff_grace = 60
	if w.fox == 0 and w.foy == 0:
		overlay_request = -1
	w.crowd_level = mini(w.crowd_level, 600)
	w.sflags &= ~HockeyWorld.SF_PAUSE
	w.iflags = 0
	w.rules.refcnt = -1
	w.puckcross[1] = -1
	w.puckcross[3] = -1
	w.sflags2 |= HockeyWorld.SF2_FACEOFF | GameRules.SF2_NOREC
	w.passplayer = -1
	w.onetimerplayer = -1
	window_open = true
	w.rules.set_hor(false)
	w.camera = Vector2i.ZERO
	# The puck on the dot, hidden (z $FFxx), still and loose.
	p.set_pos(Vector2i(w.fox, w.foy))
	p.z_fx = -0x1000000 | (p.z_fx & 0xFFFF)
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
	w.yleader = 60
	w.lines.reset_bench()
	for team in 2:
		w.lines.set_personel(team)
		w.forcepldata(team)
	resetplstuff()
	_line_up()
	w.collisions.sort_all()
	setchgplayer()
	overlay_shown = -1
	if overlay_request >= 0:
		overlay_shown = overlay_request
		overlay_request = -1
	fodrop = Vector2i(0x36 if w.fox >= 0 else 0xBE, 0x5C)
	var t := w.rng.range_(120) + 180
	if overlay_shown in [0, 1, 5, 4, 2]:
		t = maxi(t, 0x10E)
	p.temp[0] = t
	fof_frame = PackedInt32Array([1, 4, 7])
	fof_attr = PackedInt32Array([0x8000, 0xA800, 0x8000])
	if w.gmode & HockeyWorld.GM_DIR == 0:
		fof_attr[0] ^= 0x800
		fof_attr[1] ^= 0x800
	w.fodir[0] = -1
	w.fodir[1] = -1
	# sub_FF7E2: the power-play flags from the two strengths.
	var d := w.stats[0].on_ice - w.stats[1].on_ice
	if d != 0:
		w.sflags2 |= HockeyWorld.SF2_PWRPLAY
		if d < 0:
			w.sflags2 |= HockeyWorld.SF2_PWRTM
		else:
			w.sflags2 &= ~HockeyWorld.SF2_PWRTM
	faceoff_set.emit()

## The line-up loop over objects 0-11.
func _line_up() -> void:
	var p := w.puck()
	for i in 12:
		var o := w.objects[i]
		o.pos_fx = Vector2i(-240 * 0x10000 | (o.pos_fx.x & 0xFFFF), o.pos_fx.y & 0xFFFF)
		o.frame = 0
		var pos := o.position
		if pos < 0:
			continue
		var st := w.stats[o.team()]
		if pos != SimObject.POS_GOALIE:
			if pos == SimObject.POS_C:
				st.toucher = o.pnum
				w.f_c2fe &= ~HockeyWorld.C2FE_ONETIMER_TOUCH
				st.assist1 = -1
				st.assist2 = -1
				st.flags30 &= ~TeamStats.F30_CHAIN_RESET
				w.assinsert(o, ASS_FACEOFFPL)
			else:
				w.assinsert(o, ASS_FACEOFF)
		var row := clampi(6 - st.on_ice, 0, 2)
		var e: int = APL[row][clampi(pos, 0, 7)]
		var d: Vector2i = PTAB[e]
		if not o.attacking_top():
			d = -d
		if pos == SimObject.POS_GOALIE:
			o.set_pos(d)
		else:
			if e <= 2:
				if (w.fox ^ d.x) < 0:
					d.y -= w.foy >> 3
				d.x -= w.fox >> 2
			o.set_pos(Vector2i(d.x + w.fox, d.y + w.foy))
		o.old_pos_fx = o.pos_fx
		o.vel = Vector2i.ZERO
		var f := SkaterSteering.vtoa(Vector2i(p.x() - o.x(), p.y() - o.y()))
		o.facing_fx = (f << 16) | (o.facing_fx & 0xFFFF)
		o.flags2 &= ~SimObject.PF2_UNAV
		o.flags &= ~SimObject.PF_ALOCK
		o.set_spa(Spa.GLIDE)

## resetplstuff (L53659): team offside flags off; on-ice players reset.
func resetplstuff() -> void:
	for team in 2:
		var st := w.stats[team]
		st.flags30 &= ~TeamStats.F30_OFFSIDE
		for i in 6:
			var o := w.objects[st.first_object + i]
			o.flags2 = 0
			if o.position < 0:
				continue
			o.set_spa(Spa.GLIDE)
			o.impact = 0
			o.nopuck_hi = 0
			o.flags &= SimObject.PF_TEAM | SimObject.PF_GOAL | SimObject.PF_NA

## setchgplayer (L42370): each pad takes the player nearest the dot.
func setchgplayer() -> void:
	w.c_player[0] = -1
	w.c_player[1] = -1
	for k in 2:
		if w.cont_team[k] == 0:
			continue
		var first := 0 if w.cont_team[k] == 1 else 6
		w.input.changeplayer(w.objects[first], k)

## updatefaceoff (L42414): the referee's hand in the close-up window.
func updatefaceoff(p: SimObject) -> void:
	var c := p.temp[0]
	if c != 0:
		var d := (c + 6) >> 3
		if d > 2:
			return
		fof_frame[2] = 10 - d
		return
	window_open = false

## Endfaceoff (L42445): drop the puck. Home wins the draw iff randomd0(33) >= 16 - the
## home centre's close-up bonus + the away centre's. The winner pulls with the stick
## (3 in 4) or randomly forward, biased toward his own end.
func endfaceoff(p: SimObject) -> void:
	w.sound.emit(0x2F)
	w.sflags2 &= ~(HockeyWorld.SF2_FACEOFF | GameRules.SF2_NOREC)
	w.faceoff_grace = 60
	window_open = false
	w.gmode &= ~HockeyWorld.GM_CLOCK
	p.flags2 &= ~1
	w.sflags3 |= HockeyWorld.SF3_FACEOFF_WIN
	var d3 := w.fodir[0]
	var d4 := 0x800
	var d2 := (16 - FTAB[clampi(fof_frame[0] - 1, 0, 5)] + FTAB[clampi(fof_frame[1] - 1, 0, 5)]) & 0xFF
	var r := w.rng.range_(33)
	var home_won := d2 <= r
	var attr := fof_attr[0] if home_won else fof_attr[1]
	if attr & 0x800:
		d3 = w.fodir[1]
		d4 = -0x800
	var dir := -1
	if d3 & 8 == 0:
		dir = d3 & 7
		if w.hv_rng.randi() & 3 == 0:
			dir = -1
	if dir < 0:
		dir = (w.rng.range_(5) - 2) & 7
		if d4 >= 0:
			dir ^= 4
	var v: Vector2i = SkaterMotion.DIRTAB[dir]
	p.vel = Vector2i(v.x << 5, (v.y << 5) + d4)
	p.zvel = w.rng.range_(0x800)
	p.z_fx = 0
	p.flags &= ~SimObject.PF_NC
	w.assreplace(p, PuckLogic.ASS_PUCKNORM)
	faceoff_dropped.emit(home_won)

# --- the players ------------------------------------------------------------------------

## assfaceoff ($16): stand still until the drop.
func assfaceoff(o: SimObject) -> void:
	if o.locked():
		return
	if w.sflags2 & HockeyWorld.SF2_FACEOFF == 0:
		w.assexit(o)

## assfaceoffpl ($17): the centres. The close-up frame comes from the animation; the
## CPU readies (7 in 8) or pulls while the drop is far, and pulls once it is near.
func assfaceoffpl(o: SimObject) -> void:
	if o.locked():
		return
	if w.sflags2 & HockeyWorld.SF2_FACEOFF == 0:
		o.nopuck_hi = 0x14
		w.assexit(o)
		return
	if o.flags & SimObject.PF_NA:
		o.flags &= ~SimObject.PF_NA
		o.temp[0] = 0
	var slot := 1 if o.away() else 0
	var frame := (o.spa_num >> 2) + 1
	if o.handed == 0:
		frame += 3
	fof_frame[slot] = frame
	if o.joypad():
		return
	if o.anim_busy():
		return
	o.flags2 |= SimObject.PF2_AIP
	var d1 := SPA_PULL
	if (w.puck().temp[0] & 0xFFFF) > 16 and w.rng.range_(8) != 0:
		d1 = SPA_READY
	o.set_spa(d1)
