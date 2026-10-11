class_name GameRules
extends RefCounted
## The rules: the penalty and stoppage queue (AddPenalty, PenaltyManager, checkfornewpen,
## Stop4Pen, limitfo, chkprogress, InProgress, updatepentime), the referee animation
## (SetPA, UpdatePA), power play (updatepwrplay, sub_1284A), the clock (VBlank tick,
## clockcont, ResetClock), periods (StartGame, StartPer, PeriodOver, Intermission),
## the crowd meters and the per-second bookkeeping. Spec:
## docs/specs/rules_clock_penalties.md; faceoff spots in faceoffs_offsides.md section 4.

## PenaltyList (L56708): id -> [delay (x32 vblanks), minutes (0 stoppage, -1 penalty-shot
## variant), text, ref script [[frame, vblanks], ...]]. The last step ends the script.
const _ROUGH := [[0, 32], [0xD, 8], [0xE, 8], [0xD, 8], [0xE, 8], [0xD, 8], [0xE, 8], [0xD, 8], [0xE, 8], [1, 8]]
const _CHARGE := [[0, 32], [1, 8], [0xA, 8], [0xB, 8], [0xA, 8], [0xB, 8], [0xA, 8], [0xB, 8], [0xA, 8], [0xB, 8], [1, 8]]
const _SLASH := [[0, 32], [1, 8], [2, 8], [3, 8], [2, 8], [3, 8], [2, 8], [3, 8], [2, 8], [3, 8], [1, 8]]
const _XCHECK := [[0, 32], [6, 8], [0xF, 8], [0x10, 8], [0xF, 8], [0x10, 8], [0xF, 8], [0x10, 8], [0xF, 8], [0x10, 8], [1, 8]]
const _HOOK := [[0, 32], [1, 8], [9, 8], [8, 8], [9, 8], [8, 8], [9, 8], [8, 8], [9, 8], [8, 8], [1, 8]]
const _TRIP := [[0, 32], [4, 8], [5, 8], [4, 8], [5, 8], [4, 8], [5, 8], [4, 8], [5, 8], [1, 8]]
const _INTERF := [[0, 32], [1, 8], [0xC, 48], [1, 8]]
const PENALTY_LIST := {
	0x02: [1, 0, "Period Over", [[5, 128]]],
	0x04: [1, 0, "Game Over", [[5, 128], [0x40, 768]]],
	0x06: [1, 0, "Face Off", [[5, 80]]],
	0x08: [1, 0, "Face Off", [[5, 80]]],
	0x0A: [0, 0, "", [[5, 80]]],
	0x0C: [1, 0, "Icing", [[0, 16], [1, 8], [2, 48]]],
	0x0E: [1, 0, "", [[5, 80], [0x40, 192]]],
	0x10: [1, 0, "Off-side", [[0, 16], [3, 8], [4, 120]]],
	0x12: [0x0A, 2, "Roughing", _ROUGH],
	0x14: [1, 0, "", [[5, 128], [0x40, 192]]],
	0x16: [4, 2, "Charging", _CHARGE],
	0x18: [4, 2, "Slashing", _SLASH],
	0x1A: [4, 2, "Roughing", _ROUGH],
	0x1C: [4, 2, "Cross Check", _XCHECK],
	0x1E: [4, 2, "Hooking", _HOOK],
	0x20: [4, 2, "Tripping", _TRIP],
	0x22: [4, 2, "Interference", _INTERF],
	0x24: [4, 2, "Holding", [[0, 32], [1, 8], [7, 48], [1, 8]]],
	0x26: [0x28, 5, "Fighting", _ROUGH],
	0x28: [0x28, 5, "Fighting *", _ROUGH],
	0x2A: [0x28, 2, "Fight Instigator", _ROUGH],
	0x2C: [0, 0, "Penalty", [[0, 24], [3, 8], [4, 120]]],
	0x2E: [4, -1, "Hooking", _HOOK],
	0x30: [4, -1, "Tripping", _TRIP],
	0x32: [0, 0, "Face Off", [[5, 80]]],
	0x34: [4, -1, "Interference", _INTERF],
	0x36: [4, -1, "Roughing", _ROUGH],
	0x38: [4, -1, "Charging", _CHARGE],
	0x3A: [4, -1, "Cross Check", _XCHECK],
	0x3C: [4, -1, "Slashing", _SLASH],
}
const PEN_EOP := 0x02
const PEN_EOG := 0x04
const PEN_OOP := 0x06
const PEN_WHISTLE := 0x0A
const PEN_ICING := 0x0C
const PEN_GOAL := 0x0E
const PEN_OFFSIDE := 0x10
const PEN_DELAY := 0x2C
## unk_1913A: penalty-shot variant per foul (shifted one entry, quirk Q1); -1 none.
const PS_MAP := {0x14: 0x38, 0x16: 0x3C, 0x18: 0x36, 0x1A: 0x3A, 0x1C: 0x2E, 0x1E: 0x30, 0x20: 0x34}
## Regular-season overtime is always 10:00.
const OT_LENGTH := 0x258
## The puck's faceoff and shootout assignments.
const ASS_PUCKFACEOFF := 0x1B
const ASS_PUCKSHOOTOUT := 0x1E
## sflags2 bit 2: do not record the replay.
const SF2_NOREC := 1 << 2
## word_FFC2F6 bit 5: the penalty being assessed is a major.
const C2F6_MAJOR := 1 << 5

var w: HockeyWorld
## PenBuf: up to 32 entries (id << 8 | SCnum, bit 7 of SCnum = called). 0 = empty.
var pen_buf: PackedInt32Array
## Pencntdwn (vblanks to presentation; negative = presenting), Penaltytimer.
var pencntdwn: int = 0
var penalty_timer: int = 0
## RefCnt, RefStep, RefPen: the referee script.
var refcnt: int = -1
var refstep: int = -1
var refpen: int = 0
## PerTimeTotal and word_FFB048 (3rd-period music cue time).
var per_time_total: int = 300
var music_cue: int = 0
## OptPlayMode (0 regular season ... 4 shootout) and gamelevel (playoff round 0-3).
var opt_play_mode: int = 0
var gamelevel: int = 0
## PenSum records: {time, id (| $80 away), pnum}.
var pen_sum: Array = []
## Crowd: crowdcnt, crowdstep, crowdframe, and the excitement statistics.
var crowd_cnt: int = 0
var crowd_step: int = 0
var crowd_frame: int = 0
var max_excite: int = 0
var sum_excite: int = 0
var num_excite: int = 0

## The referee's message text (prefmes).
signal ref_message(text: String)
## The penalty presentation turned the rink sideways (SetHor) or back (ClrHor).
signal horizontal_changed(on: bool)
signal period_started(gsp: int)
## Intermission before period gsp (after PeriodOver), or the end of the game (gsp 4).
signal intermission(gsp: int)
signal game_over
## A penalty was assessed (InProgress).
signal penalty_assessed(team: int, pnum: int, id: int, minutes: int)

func _init(world: HockeyWorld) -> void:
	w = world
	pen_buf = PackedInt32Array()
	pen_buf.resize(33)

## The rules run (the game layer's switch and the debug dock's).
func on() -> bool:
	return w.rules_active and w.settings.enable_rules

static func entry(id: int) -> Array:
	return PENALTY_LIST.get(id, [0, 0, "", [[5, 80]]])

static func minutes(id: int) -> int:
	return entry(id)[1]

# --- AddPenalty ------------------------------------------------------------------------

## AddPenalty (L45939): the gated call for fouls, icing and offside.
func add_penalty(id: int, a3: SimObject) -> void:
	if w.gmode & HockeyWorld.GM_CLOCK:
		return
	if id != PEN_ICING:
		if not w.opt_pen:
			return
		if a3.flags2 & SimObject.PF2_UNAV:
			return
		if w.gmode & HockeyWorld.GM_OFFS == 0 and id == PEN_OFFSIDE:
			return
	add_penalty2(id, a3)

## AddPenalty2 (L45954): queue an entry. A real penalty marks the team's delayed
## penalty and the player (one pending penalty per player).
func add_penalty2(id: int, a3: SimObject) -> void:
	if not on():
		w.penalty_called.emit(id, a3.index)
		return
	if w.sflags & HockeyWorld.SF_HOR:
		return
	if id >= 0xE:
		w.crowd_level += 0xC8
		var jingle := 0xC
		if a3.away():
			w.crowd_excite += 0x14
			jingle = 0xB
		w.song.emit(jingle)
	var slot := -1
	for i in 32:
		if pen_buf[i] == 0:
			slot = i
			break
	if slot < 0:
		return
	pen_buf[slot] = (id << 8) | (a3.index & 0xFF)
	w.penalty_called.emit(id, a3.index)
	if minutes(id) <= 0:
		return
	w.delayed_pen |= 4 if a3.away() else 2
	if a3.flags2 & SimObject.PF2_PEN:
		pen_buf[slot] = 0
	a3.flags2 |= SimObject.PF2_PEN

## clrPenBuf.
func clr_pen_buf() -> void:
	for i in 32:
		pen_buf[i] = 0

## PenShotChk (L46100): a foul on a breakaway skater may become a penalty shot. The
## shootout port awards it; until then the foul stands.
func pen_shot_chk(id: int, _victim: SimObject) -> int:
	return id

# --- PenaltyManager ----------------------------------------------------------------------

## PenaltyManager (L46005): every frame.
func penalty_manager(d7: int) -> void:
	updatepentime(d7)
	checkfornewpen()
	chkprogress(d7)
	update_pa(d7)

## updatepentime (L46819): every 24 vblanks of running clock: possession, PP time and
## box time.
func updatepentime(d7: int) -> void:
	w.sflags3 &= ~HockeyWorld.SF3_PENSEC
	if w.gmode & HockeyWorld.GM_CLOCK:
		return
	penalty_timer -= d7
	if penalty_timer >= 0:
		return
	penalty_timer += 0x18
	w.sflags3 |= HockeyWorld.SF3_PENSEC
	chkatop()
	if w.sflags2 & HockeyWorld.SF2_PWRPLAY:
		w.stats[1 if w.sflags2 & HockeyWorld.SF2_PWRTM else 0].pp_time += 1
	for team in 2:
		_tick_box(team)

func _tick_box(team: int) -> void:
	var st := w.stats[team]
	var mes: Array[int] = []
	var d1 := 2
	var i := 0
	while i < st.box.size():
		var p := st.box[i]
		var v := st.tmpdst[p]
		if v & 0x4000:
			v -= 1
			st.tmpdst[p] = v
			if v & 0x800:
				st.tmpdst[p] = 0 if v & 0x1000 else 0x1000
				st.box.remove_at(i)
				# Q17: the rest of this team's list skips this second.
				return
			i += 1
			continue
		d1 -= 1
		if d1 < 0:
			i += 1
			continue
		mes.append(p)
		st.tmpdst[p] = v - 1
		if v - 1 == 0:
			st.box.remove_at(i)
			continue
		i += 1
	if d1 == 1:
		_beep(team, mes[0])
	elif d1 == 0:
		_beep(team, mes[0])
		_beep(team, mes[1])
	elif d1 == -1:
		_beep(team, mes[1])

func _beep(team: int, p: int) -> void:
	var v := w.stats[team].tmpdst[p]
	if v > 5:
		return
	if v == 0:
		_return_to_ice(team, p)
		w.sound.emit(2)
	else:
		w.sound.emit(1)

## sub_129D2 (L46924): a served player comes out of the box into a free object.
func _return_to_ice(team: int, p: int) -> void:
	var st := w.stats[team]
	var a3: SimObject = null
	for i in range(st.first_object, 16):
		if w.objects[i].position < 0:
			a3 = w.objects[i]
			break
	if a3 == null:
		return
	var d1 := st.on_ice
	st.on_ice += 1
	var idx := d1 + (1 if w.goalie.goalie_pulled(team) else 0)
	a3.position = LineLogic.PRIOLIST[clampi(idx, 0, 7)] & 0xFF
	w.setplass(a3)
	w.setplayer(a3, p)
	a3.flags2 |= SimObject.PF2_UNAV

## chkatop (L46904): attack-zone time (top zone y > 88, bottom y <= -88).
func chkatop() -> void:
	var py := w.puck().y()
	var t := -1
	if py > 0x58:
		t = 0
	elif py < -0x57:
		t = 1
	else:
		return
	if w.gmode & HockeyWorld.GM_DIR:
		t = 1 - t
	w.stats[t].attack_time += 1

## checkfornewpen (L46358): whistle stoppages at once; call a penalty when the
## offender's team has the puck, otherwise delay it.
func checkfornewpen() -> void:
	if w.sflags & HockeyWorld.SF_HOR:
		return
	for i in 32:
		var e := pen_buf[i]
		if e == 0:
			return
		var id := e >> 8
		if w.gmode & HockeyWorld.GM_PEN == 0:
			var delayed := false
			if minutes(id) != 0:
				if w.puckc < 0:
					delayed = true
				else:
					var sc := HockeyWorld._sbyte(e & 0xFF)
					delayed = ((w.puckc - 6) ^ (sc - 6)) < 0
			if delayed:
				if w.gmode & HockeyWorld.GM_PENDEL == 0:
					w.gmode |= HockeyWorld.GM_PENDEL
					set_pa(PEN_DELAY)
				continue
			stop4pen(i)
		e = pen_buf[i]
		if e & 0x80:
			continue
		pen_buf[i] = e | 0x80
		var d1: int = int(entry(id)[0]) << 5
		if d1 > pencntdwn:
			pencntdwn = d1

## Stop4Pen (L46411): the whistle. The first whistle of a stoppage sets the faceoff spot.
## i is the PenBuf entry, or -1 when the spot is already set (the clock is stopped).
func stop4pen(i: int) -> void:
	var was := w.gmode & HockeyWorld.GM_CLOCK
	w.gmode |= HockeyWorld.GM_CLOCK
	if not was and i >= 0:
		var e := pen_buf[i]
		var id := e >> 8
		var x := 0
		var y := 0
		if id == PEN_GOAL:
			pass
		elif id == PEN_OOP:
			x = w.ltx
			y = w.lty
		else:
			x = w.puck().x()
			y = w.puck().y()
			if id == PEN_ICING:
				var sc := HockeyWorld._sbyte(e & 0xFF)
				var p := w.objects[clampi(sc, 0, 15)]
				y = -0x258 if p.attacking_top() else 0x258
		var ox := x
		x = clampi(x, -0x46, 0x46)
		if y >= 0xA6:
			y = 0xCE
			x = 0x46 if ox >= 0 else -0x46
		elif y <= -0xA6:
			y = -0xCE
			x = 0x46 if ox >= 0 else -0x46
		w.fox = x
		w.foy = y
		limitfo()
	pencntdwn = 0
	w.gmode |= HockeyWorld.GM_PEN
	w.sound.emit(3)
	set_pa(PEN_WHISTLE)

## limitfo (L46482): no faceoff in the attacking zone of any team with an entry.
func limitfo() -> void:
	var i := 0
	while true:
		var sc := (pen_buf[i] & 0xFF) & 0x7F
		if sc < 16:
			var p := w.objects[sc]
			if p.attacking_top():
				if w.foy >= 0x58:
					w.foy = 0x41
					w.fox = 0x46 if w.fox >= 0 else -0x46
			elif w.foy <= -0x58:
				w.foy = -0x41
				w.fox = 0x46 if w.fox >= 0 else -0x46
		i += 1
		if i >= 32 or pen_buf[i] == 0:
			break

## chkprogress (L46014): count down the stoppage, then present it.
func chkprogress(d7: int) -> void:
	if w.ba_ps_flags & HockeyWorld.BA_LIVE and w.ps_intro >= 0:
		w.ps_intro -= 1
		if w.ps_intro < 0:
			w.sflags2 &= ~SF2_NOREC
			w.f_c2fa &= ~HockeyWorld.C2FA_PS_INTRO
		return
	if w.gmode & HockeyWorld.GM_PEN == 0:
		return
	if pencntdwn < 0:
		in_progress()
		return
	pencntdwn -= d7
	if pencntdwn >= 0:
		return
	w.gmode &= ~HockeyWorld.GM_PENDEL
	var real := false
	for i in 32:
		if pen_buf[i] != 0 and minutes(pen_buf[i] >> 8) > 0:
			real = true
			break
	if not real:
		return
	# A real penalty: the sideways penalty-box view.
	w.sflags2 |= SF2_NOREC
	set_hor(true)
	w.puckc = -1
	var p := w.puck()
	w.assinsert(p, PuckLogic.ASS_PUCKUNFLIP)
	p.temp[0] = 0x1C20
	refstep = -1
	refcnt = 0
	update_pa(1)
	refcnt = 0x32
	w.ref_signal.emit(0)

## SetHor / ClrHor.
func set_hor(on: bool) -> void:
	var was := w.sflags & HockeyWorld.SF_HOR != 0
	if on:
		w.sflags |= HockeyWorld.SF_HOR
	else:
		w.sflags &= ~HockeyWorld.SF_HOR
	if was != on:
		horizontal_changed.emit(on)

## InProgress (L46187): assess entries newest first, each after the referee finishes.
func in_progress() -> void:
	if refcnt >= 0 or refstep >= 0:
		return
	while true:
		if pen_buf[0] == 0:
			_finish()
			return
		var i := 0
		while i + 1 < 32 and pen_buf[i + 1] != 0:
			i += 1
		var e := pen_buf[i]
		if e & 0x80 == 0:
			var sc := e & 0x7F
			if sc < 16 and w.objects[sc].position >= 0:
				return
			pen_buf[i] = 0
			return
		pen_buf[i] = e & ~0x80
		var id := e >> 8
		w.f_c2f6 &= ~C2F6_MAJOR
		var m := minutes(id)
		if m <= 0:
			pen_buf[i] = 0
			if w.sflags & HockeyWorld.SF_HOR:
				continue
			set_pa(id)
			return
		if m == 5:
			w.f_c2f6 |= C2F6_MAJOR
		_assess(e & 0x7F, id, m)
		return

## InProgress assessment: stats, PenSum, box time, coincidental majors, to the box.
func _assess(sc: int, id: int, m: int) -> void:
	var p := w.objects[sc]
	var team := p.team()
	var pen := w.stats[team]
	var opp := w.stats[1 - team]
	var t := (w.gsp << 14) + (per_time_total - w.gameclock)
	if pen_sum.size() < 60:
		pen_sum.append({"time": t, "id": id | (0x80 if p.away() else 0), "pnum": p.pnum})
	pen.penalties += 1
	pen.penalty_minutes += m
	w.temp_pl_offset = (0x8000 if p.away() else 0) | (p.pnum & 0xFF)
	if TeamStats.valid_pnum(p.pnum):
		pen.player_pim[p.pnum] += m
		var v := (m * 60) | 0x2000
		if pen.tmpdst[p.pnum] >= 0 and pen.tmpdst[p.pnum] & 0x1000:
			v |= 0x1000
		pen.tmpdst[p.pnum] = v
		v &= 0xEFFF
		if w.f_c2f6 & C2F6_MAJOR:
			for d1 in range(TeamStats.ROSTER - 1, -1, -1):
				if (opp.tmpdst[d1] & 0xFFFF & 0xEFFF) == v:
					opp.tmpdst[d1] |= 0x4000
					pen.tmpdst[p.pnum] |= 0x4000
					break
		if pen.box.size() < 25:
			pen.box.append(p.pnum)
	w.assreplace(p, LineLogic.ASS_PENALTY)
	set_pa(id)
	penalty_assessed.emit(team, p.pnum, id, m)

## loc_123A2: every entry handled: recount strength, back to a faceoff.
func _finish() -> void:
	recount(0)
	recount(1)
	w.gmode &= ~HockeyWorld.GM_PEN
	w.ba_ps_flags &= ~(1 << 6)
	var id := ASS_PUCKSHOOTOUT if w.ba_ps_flags & HockeyWorld.BA_AWARDED else ASS_PUCKFACEOFF
	w.assreplace(w.puck(), id)

## sub_123DE (L46333): players on the ice = 6 less the serving non-coincidental
## penalties, never under 4.
func recount(team: int) -> void:
	var st := w.stats[team]
	var d1 := 6
	for j in range(TeamStats.ROSTER - 1, -1, -1):
		var v := st.tmpdst[j]
		if v <= 0:
			continue
		v &= ~0x2000
		st.tmpdst[j] = v
		if v & 0x4000 or v & 0x1000:
			continue
		if d1 == 4:
			continue
		d1 -= 1
	st.on_ice = d1

# --- the referee ----------------------------------------------------------------------

## SetPA (L46552): start the referee script and message for an id.
func set_pa(id: int) -> void:
	refpen = id
	if id >= 0x2E:
		return
	refstep = 0
	ref_message.emit(entry(id)[2])
	_set_pa2()

## setPA2: the next script step.
func _set_pa2() -> void:
	if refstep < 0:
		w.ref_signal.emit(0x40)
		return
	var script: Array = entry(refpen)[3]
	var step: Array = script[refstep]
	refstep += 1
	if refstep >= script.size():
		refstep = -1
	refcnt = step[1]
	w.ref_signal.emit(step[0])

## UpdatePA (L46523).
func update_pa(d7: int) -> void:
	if refcnt < 0:
		return
	refcnt -= d7
	if refcnt < 0:
		_set_pa2()

# --- power play ------------------------------------------------------------------------

## updatepwrplay (L46991): once a second, the PP flags from the two strengths.
func updatepwrplay() -> void:
	if w.f_c2fa & (1 << 1):
		return
	var d := w.stats[0].on_ice - w.stats[1].on_ice
	if d == 0:
		w.sflags2 &= ~HockeyWorld.SF2_PWRPLAY
		return
	var away_pp := d < 0
	var was_away := w.sflags2 & HockeyWorld.SF2_PWRTM != 0
	if away_pp != was_away:
		w.sflags2 &= ~HockeyWorld.SF2_PWRPLAY
		if away_pp:
			w.sflags2 |= HockeyWorld.SF2_PWRTM
		else:
			w.sflags2 &= ~HockeyWorld.SF2_PWRTM
	if w.sflags2 & HockeyWorld.SF2_PWRPLAY == 0:
		w.sflags2 |= HockeyWorld.SF2_PWRPLAY
		w.stats[1 if away_pp else 0].power_plays += 1

## sub_1284A (L46773): after a goal. Against a full-strength team every queued entry
## is wiped (Q9); a power-play goal releases the first non-coincidental box player.
func pp_goal(scoring_team: int) -> void:
	var a2 := w.stats[scoring_team]
	var a1 := w.stats[1 - scoring_team]
	if a1.on_ice == 6:
		clr_pen_buf()
	if a2.on_ice <= a1.on_ice:
		return
	for i in a1.box.size():
		var b := a1.box[i]
		if a1.tmpdst[b] & 0x4000:
			continue
		a1.tmpdst[b] = 0
		a1.box.remove_at(i)
		w.delayed_pen |= 1
		a1.on_ice += 1
		a2.pp_goals += 1
		return

## sub_FF88E: the end-of-game wipe of every penalty.
func wipe_penalties() -> void:
	w.lines.pbnum[0] = 0
	w.lines.pbnum[1] = 0
	penalty_timer = 0
	pencntdwn = 0
	clr_pen_buf()
	for st in w.stats:
		for j in TeamStats.ROSTER:
			st.tmpdst[j] = TeamStats.TMPDST_BENCH
		st.box.clear()

# --- clock and periods -------------------------------------------------------------------

## The VBlank handler's clock: $AAA off the fraction each vblank, a second on borrow.
func vblank_tick() -> void:
	if not on() or w.sflags & HockeyWorld.SF_PAUSE:
		return
	if w.f_c2fa & (1 << 2) == 0 and w.gmode & HockeyWorld.GM_CLOCK:
		return
	if w.f_c2fa & (1 << 1):
		# The 25-second penalty-shot / shootout attempt clock (shootout port).
		return
	if w.gameclock == 0:
		return
	var borrow := w.clock_frac < 0xAAA
	w.clock_frac = (w.clock_frac - 0xAAA) & 0xFFFF
	if not borrow:
		return
	w.gameclock -= 1
	if w.gameclock >= 60 and w.gameclock <= 61:
		w.sound.emit(2)

## clockcont (L30074): the clock ran out while running.
func clockcont() -> void:
	if not on() or w.gmode & HockeyWorld.GM_CLOCK:
		return
	if w.gameclock != 0:
		return
	w.sound.emit(4)
	w.freezewindow()
	end_of_period()

## loc_7B5C: end of a period; celebrations and game over after regulation.
func end_of_period() -> void:
	var p := w.puck()
	w.assinsert(p, PuckLogic.ASS_PUCKNORM)
	var a3: SimObject = p
	if w.gsp >= 2:
		var d0 := HockeyAI.ASS_SCORE
		a3 = w.objects[0]
		var d1 := w.stats[0].goals - w.stats[1].goals
		if d1 != 0:
			var first := 0 if d1 > 0 else 6
			for i in 6:
				var o := w.objects[first + i]
				if o.position > 0:
					w.assinsert(o, d0)
					d0 = HockeyAI.ASS_SCORE
			_eog(a3)
			return
	if w.gsp == 3 and opt_play_mode == 0:
		_eog(a3)
		return
	add_penalty2(PEN_EOP, a3)

func _eog(a3: SimObject) -> void:
	clr_pen_buf()
	w.crowd_level += 0x3E8
	w.gmode |= HockeyWorld.GM_CLOCK | HockeyWorld.GM_EOG
	wipe_penalties()
	add_penalty2(PEN_EOG, a3)

## ResetClock (L29817): period length, the 3rd-period music cue, clock stopped.
func reset_clock() -> void:
	var d0 := w.roster.clock_length()
	if w.gsp >= 3 and opt_play_mode == 0:
		d0 = OT_LENGTH
	w.gameclock = d0
	per_time_total = d0
	w.period_seconds = d0
	music_cue = d0 - w.rng.range_(d0 >> 1)
	w.gmode |= HockeyWorld.GM_CLOCK

## StartGame (L29748) without the menus: clear the game, then the first period.
func start_game() -> void:
	w.gmode = 0
	if w.opt_pen and w.opt_offsides:
		w.gmode |= HockeyWorld.GM_OFFS
	for st in w.stats:
		st.clear_game()
	w.roster.new_game_form()
	w.score_summary.clear()
	pen_sum.clear()
	w.gsp = 0
	w.chk_cnt = 0
	for st in w.stats:
		st.on_ice = 6
		for j in TeamStats.ROSTER:
			st.tmpdst[j] = TeamStats.TMPDST_BENCH
	w.setupice()
	_period_break()

## PeriodOver (L53805): next period, overtime or the end.
func period_over() -> void:
	w.gsp += 1
	w.gmode ^= HockeyWorld.GM_DIR
	if w.gsp >= 3:
		if w.gsp != 3:
			w.gsp = 3
			if opt_play_mode == 0:
				w.gsp = 4
		if w.stats[0].goals != w.stats[1].goals:
			w.gsp = 4
	_period_break()

## loc_17278: clock, intermission, then the next period or the end.
func _period_break() -> void:
	reset_clock()
	intermission_bookkeeping()
	intermission.emit(w.gsp)
	if w.gsp == 4:
		w.gameclock = 0
		game_over.emit()
		return
	start_per()

## Intermission (L47613) without the menu: the bench reset and fresh legs.
func intermission_bookkeeping() -> void:
	w.lines.reset_bench()
	for team in 2:
		var st := w.stats[team]
		var opp := w.stats[1 - team]
		for j in TeamStats.ROSTER:
			if st.tmpdst[j] != TeamStats.TMPDST_INJURED_GAME:
				st.energy[j] = 0x1000
			if st.tmpdst[j] == TeamStats.TMPDST_INJURED_PERIOD:
				st.tmpdst[j] = TeamStats.TMPDST_BENCH
		st.line = 0
		if w.opt_line_on and st.on_ice != opp.on_ice:
			st.line = 3 if st.on_ice > opp.on_ice else 5

## StartPer (L29853).
func start_per() -> void:
	w.setupice()
	reset_clock()
	w.c_player[0] = -1
	w.c_player[1] = -1
	w.fox = 0
	w.foy = 0
	var id := ASS_PUCKFACEOFF
	if w.f_c2fa & HockeyWorld.C2FA_SHOOTOUT:
		id = ASS_PUCKSHOOTOUT
	w.assreplace(w.puck(), id)
	w.sflags2 |= SF2_NOREC
	w.crowd_excite = gamelevel << 4
	if w.gsp < 2:
		w.sflags3 |= HockeyWorld.SF3_MUSIC_CUE
	period_started.emit(w.gsp)

# --- crowd and the per-second jobs ---------------------------------------------------------

## updatecrowdf (L30028): crowd noise decays every frame; the crowd animates.
func updatecrowdf(d7: int) -> void:
	if w.crowd_level >= 0x15E:
		w.crowd_level -= 3
	w.crowd_level = maxi(w.crowd_level - d7, 0)
	crowd_cnt -= d7
	if crowd_cnt < 0:
		var d0 := mini(w.crowd_level >> 1, 0x7F) & 0x60
		crowd_step = (crowd_step + 2) & 0x1E
		var mask := 0x0C if d0 == 0 else (0x07 if d0 < 0x60 else 0x03)
		crowd_frame = d0 + crowd_step
		crowd_cnt = mask + (w.hv_rng.randi() & mask)

## UpdateCwdExcite (L30009): once a second.
func update_cwd_excite() -> void:
	var d0 := w.crowd_excite
	if d0 > max_excite:
		max_excite = d0
	sum_excite += d0
	num_excite += 1
	w.crowd_excite = maxi(w.crowd_excite - 1, 0)

## sub_7A34: the 3rd-period music cue, once.
func third_period_music() -> void:
	if w.gsp == 2 and w.gmode & HockeyWorld.GM_HL == 0 and w.gameclock <= music_cue:
		music_cue = -0x100
		w.song.emit(5)
