class_name InputLogic
extends RefCounted
## doinput (L35886) for a pad-controlled player, plus player switching (chgplayer,
## setc1player, restorep1, Sweepcheck) and faceoffinput. Spec:
## docs/specs/input_linechanges.md sections 0.3, 3 and 5.

const SPA_SWEEP := 0xB24
const SPA_FACEOFF_SWIPE := 0xFEA
const SPA_FACEOFF_READY := 0x1014
const SPA_GOALIE_DIVE := 0x2F4
const ASS_FACEOFFPL := 0x17
## Loops a B hold takes to give the pad its goalie (Manual Goalie).
const B_HOLD := 0x11
## Loops an A hold with the puck takes to flip the puck (and open the line menu).
const A_HOLD := 0xF

var w: HockeyWorld

func _init(world: HockeyWorld) -> void:
	w = world

## One doinput call. pad has already been read this loop; k is the pad (d4 = 2k).
func doinput(a3: SimObject, pad: PadState, k: int, d7: int) -> void:
	var d0 := pad.d0
	var d1 := pad.d1
	var d2 := pad.d2
	var d3 := pad.d3
	# 1. B+C together drops the B press and swallows its release.
	if d1 & PadState.B and d1 & PadState.C:
		d1 &= ~PadState.B
		a3.flags3 |= SimObject.PF3_BLOCK_B
	else:
		if d1 & PadState.B:
			a3.flags3 &= ~SimObject.PF3_BLOCK_B
		if d2 & PadState.B:
			var was := a3.flags3 & SimObject.PF3_BLOCK_B
			a3.flags3 &= ~SimObject.PF3_BLOCK_B
			if was:
				w.b_cnt[k] = B_HOLD
				d2 &= ~PadState.B
	# 2. Penalty-shot intro skip.
	if w.f_c2fa & HockeyWorld.C2FA_PS_INTRO and (d0 & 0xFF) != 8:
		if (w.cont_team[1] == 0 or w.puckc == a3.index) and w.ps_intro > 2:
			w.ps_intro = 2
	var raw_dir := d0 & 0xF
	# 4. Start pauses.
	if d1 & PadState.START:
		w.pause_requested.emit(k)
		return
	# 5. Horizontal mode rotates the stick (raw_dir keeps the unrotated value).
	if w.sflags & HockeyWorld.SF_HOR and d0 & 8 == 0:
		d0 = (d0 + 2) & 7
	if w.sflags2 & HockeyWorld.SF2_FACEOFF:
		faceoffinput(a3, d0, d1)
		return
	if a3.flags2 & SimObject.PF2_LCMENU:
		w.lines.lineinput(a3, d0, d1, d2, d7)
		return
	if not a3.joypad():
		return
	# 9. The passer's C during the pass makes the receiver one-time it.
	if _passer_onetimer(a3, d1, k):
		return
	# 10. Locked by an animation.
	if a3.flags3 & SimObject.PF3_ONETIMER == 0 and a3.locked():
		_locked(a3, d1, k)
		return
	if a3.fighting():
		return
	if w.puckc == a3.index:
		_offense(a3, d0, d1, d2, d3, k, d7)
		return
	# 13. Without the puck: A holds.
	if a3.position != SimObject.POS_GOALIE and a3.flags3 & SimObject.PF3_ONETIMER == 0 and d1 & PadState.A:
		w.checking.holdplayer(a3)
		return
	# 14-15. B.
	var b_logic := true
	if a3.position != SimObject.POS_GOALIE:
		if w.ba_ps_flags & HockeyWorld.BA_LIVE:
			b_logic = false
	elif w.auto_goalie[k]:
		changeplayer(a3, k)
		return
	if b_logic and _b_logic(a3, d1, d2, d3, k):
		return
	# 16-17.
	if a3.position == SimObject.POS_GOALIE:
		_manual_goalie(a3, d1, d3, raw_dir, d7)
	else:
		_skater_no_puck(a3, d1, raw_dir, k, d7)

## Step 9.
func _passer_onetimer(a3: SimObject, d1: int, k: int) -> bool:
	if w.lastplayer != a3.index or w.passplayer < 0 or w.onetimerplayer >= 0:
		return false
	if d1 & PadState.C == 0:
		return false
	var r := w.objects[w.passplayer]
	if r.position == SimObject.POS_GOALIE or not w.shooting.onetimer_gate(r):
		return false
	if r.joypad() or r.flags3 & SimObject.PF3_ONETIMER:
		return false
	w.inputjoy = k
	w.assreplace(r, Shooting.ASS_ONETIMER)
	return true

## Step 15: B tap switches player (or sweep-checks), a 17-loop hold takes the goalie.
## Returns true when it ended doinput.
func _b_logic(a3: SimObject, d1: int, d2: int, d3: int, k: int) -> bool:
	if d3 & PadState.B and w.faceoff_grace == 0:
		if w.b_cnt[k] == 0:
			return false
		w.b_cnt[k] = maxi(w.b_cnt[k] - 1, 0)
		if w.b_cnt[k] == 0 and not w.auto_goalie[k]:
			_switch_to_goalie(a3, k)
			return true
	if d1 & PadState.B:
		w.b_cnt[k] = B_HOLD
		return false
	if d2 & PadState.B and d3 & PadState.B == 0:
		var old := w.b_cnt[k]
		w.b_cnt[k] = B_HOLD
		if old != 0 or w.auto_goalie[k]:
			changeplayer(a3, k)
		else:
			_switch_to_goalie(a3, k)
		return true
	return false

func _switch_to_goalie(a3: SimObject, k: int) -> void:
	if w.faceoff_grace != 0:
		changeplayer(a3, k)
		return
	var g := w.goalie_of(a3.team())
	if g == null or g.joypad():
		return
	w.set_c_player(k, g)

## Step 16: a pad-controlled goalie without the puck.
func _manual_goalie(a3: SimObject, d1: int, d3: int, raw_dir: int, d7: int) -> void:
	if d1 & PadState.A and raw_dir != 8:
		a3.facing_fx = (raw_dir << 16) | (a3.facing_fx & 0xFFFF)
		a3.nopuck_hi = 8
		a3.set_spa(SPA_GOALIE_DIVE)
		a3.flags2 |= SimObject.PF2_AIP
		a3.flags |= SimObject.PF_ALOCK
		w.crowd_level += 0x96
		return
	if d1 & PadState.C and not a3.locked():
		var p := w.puck()
		var f := SkaterSteering.vtoa(Vector2i(p.x() - a3.x(), p.y() - a3.y()))
		a3.facing_fx = (f << 16) | (a3.facing_fx & 0xFFFF)
		w.ba_ps_flags &= ~1
		if a3.anim_busy():
			return
		a3.flags2 |= SimObject.PF2_AIP
		w.goalie_save(a3)
		return
	if a3.anim_busy():
		return
	# Boxed to |x| <= 36 and kept from skating toward centre inside |y| <= 231.
	var stop := false
	if a3.x() > 0x24 and a3.vel.x > 0:
		stop = true
		a3.vel.x = 0
	if a3.x() < -0x24 and a3.vel.x < 0:
		stop = true
		a3.vel.x = 0
	if a3.y() > -0xE7 and a3.y() <= 0xE7 and (a3.y() ^ a3.vel.y) < 0 and a3.vel.y != 0:
		stop = true
		a3.vel.y = 0
	if stop:
		return
	w.skate(a3, raw_dir, d7)

## Step 17: a skater without the puck. C bursts, or one-times a pass to him.
func _skater_no_puck(a3: SimObject, d1: int, raw_dir: int, k: int, d7: int) -> void:
	if a3.flags3 & SimObject.PF3_ONETIMER:
		return
	if d1 & PadState.C == 0:
		w.skate(a3, raw_dir, d7)
		return
	var last_goalie := w.lastplayer >= 0 and w.objects[w.lastplayer].position == SimObject.POS_GOALIE
	if last_goalie or a3.index != w.passplayer or w.puckc >= 0 or not w.shooting.onetimer_gate(a3):
		w.shooting.burst(a3)
		return
	w.inputjoy = k
	w.assreplace(a3, Shooting.ASS_ONETIMER)

## Step 18: the puck carrier.
func _offense(a3: SimObject, d0: int, d1: int, d2: int, d3: int, k: int, d7: int) -> void:
	w.checkob(a3)
	if a3.position == SimObject.POS_GOALIE and a3.anim_busy():
		return
	if w.sflags & HockeyWorld.SF_PASSDIR:
		w.shooting.passmode(a3, d0, d2)
		return
	if w.sflags & HockeyWorld.SF_SHOTDIR:
		w.shooting.shot_mode(a3, d0, d2, d7)
		return
	if d1 & PadState.B:
		w.shooting.setpassmode(a3)
		return
	if d1 & PadState.A:
		w.a_timer[k] = A_HOLD
	if d3 & PadState.A:
		w.a_timer[k] = maxi(w.a_timer[k] - 1, 0)
		if w.a_timer[k] == 0:
			w.f_c2f6 |= HockeyWorld.C2F6_FLIP
			w.shooting.setpassmode(a3)
			w.lines.set_lc_mode(a3)
			return
	elif d2 & PadState.A:
		w.f_c2f6 |= HockeyWorld.C2F6_FLIP
		w.shooting.setpassmode(a3)
		return
	if a3.position != SimObject.POS_GOALIE and d1 & PadState.C:
		w.shooting.set_shot_mode(a3)
		return
	w.skate(a3, d0 & 0xF, d7)

## Step 21: an animation-locked player without the puck can still switch with B.
func _locked(a3: SimObject, d1: int, k: int) -> void:
	if w.puckc == a3.index or d1 & PadState.B == 0:
		return
	changeplayer(a3, k)
	var c := w.c_player[k]
	if c >= 0:
		w.objects[c].flags3 |= SimObject.PF3_BLOCK_B

## faceoffinput (L36529): the pull direction, and B swipes.
func faceoffinput(a3: SimObject, d0: int, d1: int) -> void:
	if a3.asslist[a3.assnum & 7] != ASS_FACEOFFPL:
		return
	w.fodir[1 if a3.attacking_top() else 0] = d0
	if a3.anim_busy():
		return
	if d1 & PadState.B:
		a3.set_spa(SPA_FACEOFF_SWIPE)
		a3.flags2 |= SimObject.PF2_AIP
	else:
		a3.set_spa(SPA_FACEOFF_READY)

## chgplayer (L976652): pad k takes the teammate nearest the puck's next position;
## if that is already him, he sweep-checks instead.
func changeplayer(a3: SimObject, k: int) -> void:
	var p := w.puck()
	var tx := p.x() + (p.vel.x >> 8)
	var ty := p.y() + (p.vel.y >> 8)
	var other := w.c_player[1 - k]
	var best := 0xFFFFFFFF
	# Retail falls back to the caller's d6 (the current player when called from doinput).
	var d6 := a3.index
	var first := 0 if w.cont_team[k] == 1 else 6
	for i in 6:
		var o := w.objects[first + i]
		if o.position <= 0 or o.flags2 & SimObject.PF2_UNAV:
			continue
		if o.index != w.c_player[k] and o.joypad():
			continue
		if w.ba_ps_flags & HockeyWorld.BA_LIVE and o.index != w.ba_sktr and o.index != w.ba_goalie:
			continue
		if o.locked():
			continue
		var dist := ((tx - o.x()) * (tx - o.x()) + (ty - o.y()) * (ty - o.y())) & 0xFFFFFFFF
		if dist > best:
			continue
		if o.index == other:
			continue
		best = dist
		d6 = o.index
	if d6 == w.c_player[k]:
		sweepcheck(w.objects[d6])
		return
	w.set_c_player(k, w.objects[d6])

## Sweepcheck (L37296).
func sweepcheck(a3: SimObject) -> void:
	a3.flags |= SimObject.PF_ALOCK
	a3.set_spa(SPA_SWEEP)
