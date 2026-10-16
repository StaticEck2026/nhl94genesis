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
var crowd_flash: int = 0
## word_FFC300 bit 0: the last goal freed a penalized player (the goal box says PP GOAL!).
var pp_goal_flag: bool = false
## The flash's VDP counter read. Retail's counter reads do not disturb one another, so the
## (purely visual) flash draws from its own stream instead of HockeyWorld.hv_rng.
var flash_rng := RandomNumberGenerator.new()
var max_excite: int = 0
var sum_excite: int = 0
var num_excite: int = 0

## The referee's message text (prefmes).
signal ref_message(text: String)
## SetPA (L46552) with an id below $2E: the overlay draws the referee's message box.
signal pa_set(id: int)
## loc_1889A (L55990): the goal box, at SetPA($E). See goal_box_info.
signal goal_box(info: Dictionary)
## PrintScores1 (L47137) ran: the score box is redrawn.
signal scores_printed
## sub_1850A (L55666): the three stars, as [team, roster slot], in the last 64 VBlanks of
## the Game Over script.
signal stars(picks: Array)
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
	flash_rng.seed = w.hv_rng.seed ^ 0x5A5A

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
	# A penalty shot or shootout attempt: the intro box, then its countdown (per frame).
	if w.ba_ps_flags & HockeyWorld.BA_LIVE:
		if w.ba_ps_flags & ShootoutLogic.BA_INTRO:
			w.shootout.show_intro()
			w.ba_ps_flags &= ~ShootoutLogic.BA_INTRO
			return
		if w.ps_intro >= 0:
			w.ps_intro -= 1
			if w.ps_intro >= 0:
				return
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
	pa_set.emit(id)
	if id == PEN_GOAL:
		w.arena.hat_trick_check()
		goal_box.emit(goal_box_info())
	refstep = 0
	ref_message.emit(entry(id)[2])
	if w.f_c2fa & HockeyWorld.C2FA_SHOOTOUT and w.f_c2fa & ShootoutLogic.C2FA_DECIDED:
		ref_message.emit(w.shootout.winner_text())
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
	if w.f_c2fa & HockeyWorld.C2FA_SHOOTOUT and w.f_c2fa & ShootoutLogic.C2FA_DECIDED:
		refcnt *= 2
	w.ref_signal.emit(step[0])

## UpdatePA (L46523).
func update_pa(d7: int) -> void:
	if refcnt < 0:
		return
	if refpen == PEN_EOG and refcnt <= 0x40 and w.gmode & HockeyWorld.GM_STARS == 0:
		w.gmode |= HockeyWorld.GM_STARS
		stars.emit(stars_of_game())
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
		pp_goal_flag = true
		return

## loc_1889A (L55990): what the goal box shows for the last ScoreSum record. The header
## is "PP GOAL!" when the goal freed a penalized player (word_FFC300 bit 0) and "HAT TRICK!"
## for a skater's third; a penalty-shot goal (word_FFC2F4 bit 5) lists no assists. Both
## flags are consumed here, as retail's bclr does.
func goal_box_info() -> Dictionary:
	var pp := pp_goal_flag
	pp_goal_flag = false
	var ps := w.f_c2f4 & HockeyWorld.C2F4_PS_GOAL != 0
	w.f_c2f4 &= ~HockeyWorld.C2F4_PS_GOAL
	if w.score_summary.is_empty():
		return {}
	var rec: Dictionary = w.score_summary[w.score_summary.size() - 1]
	var team := 1 if rec["away"] else 0
	var st := w.stats[team]
	var goalies := st.data.goalie_count if st.data else 2
	var scorer := int(rec["scorer"])
	var skater := TeamStats.valid_pnum(scorer) and scorer >= goalies
	var header := "PP GOAL!" if pp else "GOAL!"
	if skater and st.player_goals[scorer] == 3:
		header = "HAT TRICK!"
	var info := {"team": team, "header": header, "scorer": scorer,
		"goals": st.player_goals[scorer] if skater else -1, "assists": []}
	if not ps:
		for k in ["assist1", "assist2"]:
			var a := int(rec[k])
			if a < 0:
				break
			info["assists"].append([a, st.player_assists[a] if TeamStats.valid_pnum(a) else 0])
	return info

## sub_18620 / sub_1867E (L55791): the star scores of every roster slot of both teams,
## then sub_185E0 three times (the largest, ties to the lower slot; zeroed once picked).
## A skater scores goals*11000 + assists*10100, plus shots*10 in a decided game or
## shots*1000 + time on ice in a tie; a goalie who played the game (time on ice at least
## ClockLength + 6, d2 inferred) with shots against earns 32000 for 4 % or less against
## and 75000 more for a shutout. Everyone starts from his team's goal difference. In
## overtime the last goal's scorer is the first star.
func stars_of_game() -> Array:
	var scores := []
	for team in 2:
		var st := w.stats[team]
		var d3 := w.score(team) - w.score(1 - team)
		var goalies := st.data.goalie_count if st.data else 2
		var n := st.data.players.size() if st.data else TeamStats.ROSTER
		for k in TeamStats.ROSTER:
			var s := d3
			if k >= n:
				s = -0x7FFFFFFF
			elif k >= goalies:
				s += st.player_goals[k] * 11000 + st.player_assists[k] * 10100
				if d3 != 0:
					s += st.player_shots[k] * 10
				else:
					s += st.player_shots[k] * 1000 + st.player_toi[k]
			elif st.player_toi[k] >= w.roster.clock_length() + 6 and st.player_shots[k] > 0:
				var r := 100 * st.player_goals[k] / st.player_shots[k]
				if r <= 4:
					s += 32000
				if r == 0:
					s += 75000
			scores.append(s)
	if w.gsp == 3 and not w.score_summary.is_empty():
		var rec: Dictionary = w.score_summary[w.score_summary.size() - 1]
		var sc := int(rec["scorer"])
		if TeamStats.valid_pnum(sc):
			scores[(TeamStats.ROSTER if rec["away"] else 0) + sc] = 0x7FFFFFFF
	var picks := []
	for i in 3:
		var best := 0
		for j in scores.size():
			if scores[j] > scores[best]:
				best = j
		picks.append([best / TeamStats.ROSTER, best % TeamStats.ROSTER])
		scores[best] = -0x7FFFFFFF
	return picks

## CalcPenTime (L46955): the power-play banner's time left. a2 is the shorthanded team,
## a3 the team on the power play. Ported as is, odd accumulation included
## (rules_clock_penalties.md); the box times are the low 11 bits of tmpdst.
func calc_pen_time(a2: TeamStats, a3: TeamStats) -> int:
	var d0 := 0
	var d3 := 0
	for b in a2.box:
		var t := a2.tmpdst[b]
		if t & 0x4000:
			continue
		t = (t & 0x7FF) - d3
		d0 += t
		d3 = t
	if a3.on_ice == 6:
		return d0
	d0 -= d3
	for b in a3.box:
		var t := a3.tmpdst[b]
		if t & 0x4000:
			continue
		if d0 < (t & 0x7FF):
			return d0
		return d0 + d3
	return d0

# --- the other games of the night (InitScores / UpdateScores / getscore, L47726-47843) ----

## The rest of the league: the other games (gsstruct) and, in the playoffs, the tree
## (League). The game scene lends the menus' League; tests and the sandbox get their own.
var league := League.new()

## The regular-season slate (sub_18002, run by FigureJoy at the menu's exit) for these
## teams, on the game's RNG.
func init_other_games(teams: Array) -> void:
	league.set_teams(teams)
	league.slate(w.rng, maxi(w.stats[0].team_index, 0), maxi(w.stats[1].team_index, 0))

## The games the ticker and Other Scores show.
var other_games: Array:
	get:
		return league.shown_games()

## sub_1351C (Intermission step 6): every flagged close game is settled. The port plays
## no live highlight: as when one is skipped (sub_1381E), a tie goes to a side by the
## VDP counter's bit 0.
func intermission_highlights() -> void:
	for i in range(league.shifter().x, -1, -1):
		var g: Dictionary = league.gs[i]
		if g["flags"] & League.F_OVER == 0 and g["flags"] & League.F_HILITE:
			g["flags"] &= ~League.F_HILITE
			League.settle(g, w.vcount)

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
	if w.f_c2fa & ShootoutLogic.C2FA_ATTEMPT_CLOCK:
		# The 25-second attempt clock; the intro absorbs the ticks without counting.
		var so := w.shootout
		if so.ps_clock == 0:
			return
		var b := so.ps_clock_frac < 0xAAA
		so.ps_clock_frac = (so.ps_clock_frac - 0xAAA) & 0xFFFF
		if not b or w.f_c2fa & HockeyWorld.C2FA_PS_INTRO:
			return
		so.ps_clock -= 1
		return
	if w.gameclock == 0:
		return
	var borrow := w.clock_frac < 0xAAA
	w.clock_frac = (w.clock_frac - 0xAAA) & 0xFFFF
	if not borrow:
		return
	w.gameclock -= 1
	for o in w.objects.slice(0, 12):
		if o.position >= 0 and TeamStats.valid_pnum(o.pnum & 0xFF):
			w.stats[o.team()].player_toi[o.pnum & 0xFF] += 1
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
		var d0 := cup_assignment()
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

## clockcont L30092-30121: the game that wins the Stanley Cup (the single-game final, or
## the fourth win of the final series) gives its first skater the cup (assstanley) and
## takes the pads away; any other win is assscore.
func cup_assignment() -> int:
	if gamelevel != 3 or opt_play_mode == 0:
		return HockeyAI.ASS_SCORE
	if league.bosgames != League.SINGLE:
		var g: Dictionary = league.gs[maxi(league.gamenum, 0)]
		var d3 := 1 if g["flags"] & League.F_FLIPPED else 0
		if w.stats[0].goals < w.stats[1].goals:
			d3 ^= 1
		if g["wins"][d3] != 3:
			return HockeyAI.ASS_SCORE
	for i in 12:
		w.objects[i].flags &= ~SimObject.PF_JOYCON
	return HockeyAI.ASS_STANLEY

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
	# L970846: word_FFC2F4 cleared (the reverse angle off).
	w.reverse_angle = false
	if w.opt_pen and w.opt_offsides:
		w.gmode |= HockeyWorld.GM_OFFS
	for st in w.stats:
		st.clear_game()
	w.roster.new_game_form()
	w.score_summary.clear()
	pen_sum.clear()
	w.arena.stop()
	# L29878: no recording until the first drop; the buffer starts over.
	w.sflags2 |= SF2_NOREC
	w.replay.reset()
	w.gsp = 0
	w.chk_cnt = 0
	for st in w.stats:
		st.on_ice = 6
		for j in TeamStats.ROSTER:
			st.tmpdst[j] = TeamStats.TMPDST_BENCH
	# InitScores (L29773), and the first game of a new playoff clears the Playoff Stats
	# (sub_77E4).
	league.init_scores(w.rng)
	if opt_play_mode > 1:
		league.po_stats.fill(0)
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

## song $79: the intermission (PeriodOver L53840).
const SONG_INTERMISSION := 0x79

## loc_17278: clock, intermission, then the next period or the end.
func _period_break() -> void:
	reset_clock()
	# L29881-29889: AllSndOff, then the intermission song (the pregame one too, StartGame
	# joins here).
	w.sound_off.emit()
	w.song.emit(SONG_INTERMISSION)
	# UpdateScores, then AddPOStats after the last period.
	league.update_scores(w.rng)
	if w.gsp == 4 and opt_play_mode >= 1:
		for st in w.stats:
			if st.team_index == league.user_team():
				league.add_po_stats(st)
				break
	intermission_bookkeeping()
	intermission.emit(w.gsp)
	if w.gsp == 4:
		w.gameclock = 0
		game_over.emit()
		return
	start_per()

## Intermission (L47613) without the menu: the bench reset and fresh legs; the other
## games move on a period (UpdateScores at PeriodOver).
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
	w.goal_song_timer = 0
	w.faceoff.overlay_request = -1
	w.setupice()
	reset_clock()
	cur_crowd_meter = 0
	w.c_player[0] = -1
	w.c_player[1] = -1
	w.fox = 0
	w.foy = 0
	var id := ASS_PUCKFACEOFF
	if w.f_c2fa & HockeyWorld.C2FA_SHOOTOUT:
		id = ASS_PUCKSHOOTOUT
		w.shootout.ba_skater_offset = 8
		w.ba_goalie = 11
	w.assreplace(w.puck(), id)
	w.sflags2 |= SF2_NOREC
	w.crowd_excite = gamelevel << 4
	# StartPer's AllSndOff and the period's tune (SongIndex 0, L29892-29896). The port
	# starts the period before the intermission hold, so both wait for its first loop
	# (HockeyWorld.step). No team has a 0 in that column: no RNG roll, so the later
	# moment does not change the stream.
	w.period_song = w.choose_song(0)
	if w.gsp < 2:
		w.sflags3 |= HockeyWorld.SF3_MUSIC_CUE
	period_started.emit(w.gsp)

# --- crowd and the per-second jobs ---------------------------------------------------------

# --- the crowd meter (Crowd_Noise?, LoadCrowdRec) -------------------------------------

## CrowdRecord: LoadCrowdRec reads the home team's record from the cartridge's save RAM,
## $50 when there is none (a fresh cartridge; the port keeps no save RAM).
var crowd_record_value: int = 0x50
## CrowdAvg, CurCrowdMeter, CrowdPeak, CwdChkCntr, CwdChkCnt.
var crowd_avg: int = 0
var cur_crowd_meter: int = 0
var crowd_peak: int = 0
var cwd_chk_cntr: int = 0
var cwd_chk_cnt: int = 0
## word_FFC2F6 bit 7: the crowd is loud. word_FFC304: frames before it can get loud.
var crowd_loud: bool = false
var crowd_hold: int = 0

## Crowd_Noise? (L959685, from setvideo every loop): the crowd turns loud once the
## excitement beats a level set by the record; while loud, every 20 loops the meter is
## sqrt(excitement * 4) + $41. Its record bit (updateplayers) speeds up the AI.
func crowd_noise(d7: int) -> void:
	if w.sflags & HockeyWorld.SF_HOR or w.f_c2fa & HockeyWorld.C2FA_SHOOTOUT:
		return
	if not crowd_loud:
		if crowd_hold != 0:
			crowd_hold -= 1
			if crowd_hold < 0:
				crowd_hold = 0
			return
		crowd_avg = crowd_record_value - 0xB
		var d0 := crowd_record_value - 0x49
		d0 = HockeyWorld.s16(((d0 * d0) >> 2) + 6)
		if d0 > w.crowd_excite:
			return
		crowd_loud = true
		return
	var q := crowd_avg - 0x41
	if HockeyWorld.s16((q * q) >> 2) >= w.crowd_excite:
		crowd_loud = false
	cwd_chk_cntr -= d7
	if cwd_chk_cntr >= 0:
		return
	cwd_chk_cntr = 0x14
	cwd_chk_cnt += 1
	# ext.l then asl.w: only the low word is shifted.
	var e := w.crowd_excite
	var v := (e & ~0xFFFF) | ((e << 2) & 0xFFFF) if e < 0 else (e << 2) & 0xFFFF
	cur_crowd_meter = RinkBoards.sroot(v) + 0x41
	crowd_peak = maxi(crowd_peak, cur_crowd_meter)

## PrintScores1's crowd part: the score box is redrawn over the meter, so a loud crowd is
## reset and held off for 120 loops.
func print_scores1() -> void:
	scores_printed.emit()
	if w.sflags & HockeyWorld.SF_HOR:
		return
	if crowd_loud:
		crowd_loud = false
		crowd_hold = 0x78

## _cd0 (L56543): the crowd frame by crowdlevel row (< $40, < $80, < $C0, more) and
## column; the rows' delay masks are $C, 7, 7 and 3.
const CD0: Array[int] = [
	1, 2, 3, 4, 5, 10, 9, 8, 6, 7, 8, 9, 10, 5, 4, 3,
	1, 2, 3, 4, 5, 11, 12, 13, 6, 7, 8, 9, 10, 11, 12, 13,
	14, 15, 16, 17, 18, 11, 12, 13, 18, 17, 16, 15, 14, 13, 12, 11,
	14, 15, 16, 17, 18, 11, 12, 13, 18, 17, 16, 15, 14, 13, 12, 11]

## updatecrowdf (L30028): crowd noise decays every frame; the crowd animates. The low
## byte of crowdframe is the fans' frame (1-$12), the high byte a camera flash ($13-$19)
## for this one loop while the crowd is loud.
func updatecrowdf(d7: int) -> void:
	if w.crowd_level >= 0x15E:
		w.crowd_level -= 3
	w.crowd_level = maxi(w.crowd_level - d7, 0)
	crowd_cnt -= d7
	if crowd_cnt < 0:
		var d0 := mini(w.crowd_level >> 1, 0x7F) & 0x60
		crowd_step = (crowd_step + 2) & 0x1E
		var mask := 0x0C if d0 == 0 else (0x07 if d0 < 0x60 else 0x03)
		crowd_frame = CD0[(d0 + crowd_step) >> 1]
		crowd_cnt = mask + (w.hv_rng.randi() & mask)
	crowd_flash = 0
	if w.crowd_level > 0x118:
		var r := flash_rng.randi() & 0x7F
		if r >= 0x13 and r <= 0x19:
			crowd_flash = r

## asv: the crowd noise level updatesound (L52982) eases toward the crowd meter.
var asv: int = 0

## updatesound: asv moves $28 a frame toward crowdlevel*8 + $400 (at most $EFF); the PSG
## noise attenuation is 15 minus asv's high byte.
func updatesound() -> void:
	var target := mini(w.crowd_level * 8 + 0x400, 0xEFF)
	var diff := target - asv
	if diff > 0x28:
		asv += 0x28
	elif diff < -0x28:
		asv = maxi(asv - 0x28, 0)

func crowd_attenuation() -> int:
	# Crowd_Noise? (L959688): no crowd noise in a shootout.
	if w.f_c2fa & HockeyWorld.C2FA_SHOOTOUT:
		return 15
	return ((asv >> 8) & 0xF) ^ 0xF

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
		w.song.emit(w.choose_song(5))
