extends SceneTree
## Headless tests. Run from godot/ with tests/run_tests.sh, which also fails on any
## SCRIPT ERROR: an error inside a called function does not stop the test that called it.

var _failures := 0
var _checks := 0

func _initialize() -> void:
	for test in [
		"test_maxspeed_table_matches_rom",
		"test_max_speed_index_and_half_step",
		"test_max_speed_cuts",
		"test_agility_factor",
		"test_accel",
		"test_accel_cap_keeps_velocity",
		"test_drag",
		"test_stopna",
		"test_units",
		"test_dir8",
		"test_puck_follow",
		"test_fsm",
		"test_wall_mask",
		"test_vtoa",
		"test_steer_turn_in_place",
		"test_steer_aligned",
		"test_steer_fast_turn",
		"test_steer_hockey_stop",
		"test_steer_snap",
		"test_steer_reverse",
		"test_steer_no_momentum",
		"test_board_normals",
		"test_bounce_skater",
		"test_bounce_puck",
		"test_world_skater_in_rink",
		"test_rng",
		"test_z_bounce",
		"test_exchange_head_on",
		"test_opponent_impact",
		"test_moving_apart",
		"test_body_check_floors",
		"test_fall_dedupe",
		"test_holdcheck",
		"test_checkagr_max_aggression",
		"test_board_pin",
		"test_world_collision",
		"test_puck_pickup",
		"test_puck_too_fast",
		"test_goalie_steals",
		"test_goal",
		"test_post",
		"test_over_glass",
		"test_goalie_covers",
		"test_findpc",
		"test_icing",
		"test_offside",
	]:
		# A test returns true when it reaches its end. A script error aborts it and call()
		# returns null, which counts as a failure instead of passing silently.
		if call(test) != true:
			_failures += 1
			print("FAIL: %s did not finish" % test)
	print("%d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)

func check(cond: bool, what: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		push_error("FAIL: " + what)
		print("FAIL: " + what)

func eq(a: Variant, b: Variant, what: String) -> void:
	check(a == b, "%s: got %s, want %s" % [what, a, b])

func near(a: float, b: float, eps: float, what: String) -> void:
	check(absf(a - b) <= eps, "%s: got %f, want %f" % [what, a, b])

func motion() -> SkaterMotion:
	return SkaterMotion.new(SimSettings.new())

## MaxSpeed L43855 dc.l values.
func test_maxspeed_table_matches_rom() -> bool:
	var rom := [0x1CD9410, 0x1FCE3E1, 0x22E8284, 0x2626FF9, 0x298AC40, 0x2D13759, 0x30C1144, 0x3493A01,
		0x388B190, 0x3CA77F1, 0x40E8D24, 0x454F129, 0x49DA400, 0x4E8A5A9, 0x535F624, 0x5859571]
	var m := motion()
	for i in rom.size():
		eq(m.max_speed_sq_entry(i), rom[i], "MaxSpeed[%d]" % i)
	return true

func test_max_speed_index_and_half_step() -> bool:
	var m := motion()
	var s := SkaterMotion.Skater.new()
	s.speed = 30
	eq(m.max_speed_sq(s), 0x5859571, "spd 30 full energy is entry 15")
	s.speed = 29
	eq(m.max_speed_sq(s), 0x535F624 + ((0x5859571 - 0x535F624) >> 1), "spd 29 takes half a step")
	s.speed = 30
	s.energy = SkaterMotion.ENERGY_FULL >> 1
	eq(m.max_speed_sq(s), m.max_speed_sq_entry(7), "half energy halves the index")
	s.ignore_energy = true
	eq(m.max_speed_sq(s), 0x5859571, "line changes off ignores energy")
	return true

func test_max_speed_cuts() -> bool:
	var m := motion()
	var s := SkaterMotion.Skater.new()
	s.speed = 30
	s.has_puck = true
	eq(m.max_speed_sq(s), 0x5859571, "skater carrier keeps full max")
	s.is_goalie = true
	eq(m.max_speed_sq(s), 0x5859571 >> 1, "goalie carrier halves squared max")
	s.is_goalie = false
	s.has_puck = false
	s.fight_injured = true
	eq(m.max_speed_sq(s), 0x5859571 >> 3, "fight injury divides squared max by 8")
	return true

func test_agility_factor() -> bool:
	var m := motion()
	var s := SkaterMotion.Skater.new()
	s.weight = 8
	s.agility = 10
	eq(m.agility_factor(s), 36, "skater (64 - 2 + 10) / 2")
	s.is_goalie = true
	eq(m.agility_factor(s), 49, "goalie (64 - 2 + 10 + 10 + 16) / 2")
	s.is_goalie = false
	s.crowd_boost = true
	eq(m.agility_factor(s), 37, "crowd boost +2")
	return true

func test_accel() -> bool:
	var m := motion()
	var s := SkaterMotion.Skater.new()
	s.weight = 8
	s.agility = 10
	eq(m.accel(s, Vector2i(0, 200)), Vector2i(0, 225), "200 * 36 >> 5")
	eq(m.accel(s, Vector2i(0, 200), 2), Vector2i(0, 450), "d7 = 2")
	eq(m.accel(s, Vector2i(-141, -141)), Vector2i(-159, -159), "-141 * 36 >> 5 floors")
	eq(m.dirtab(3), Vector2i(141, -141), "dirtab 3")
	s.joypad = true
	s.has_puck = true
	eq(m.accel(s, Vector2i(0, 200)), Vector2i(0, 225), "skater carrier is not slowed")
	s.is_goalie = true
	eq(m.accel(s, Vector2i(0, 200)), Vector2i(0, 153), "joypad goalie carrier halves accel")
	return true

func test_accel_cap_keeps_velocity() -> bool:
	var m := motion()
	var s := SkaterMotion.Skater.new()
	s.speed = 30
	var top := 9625
	eq(m.apply_accel(s, Vector2i(0, top - 10), Vector2i(0, 200)), Vector2i(0, top - 10), "over cap keeps old velocity")
	eq(m.apply_accel(s, Vector2i(0, 0), Vector2i(0, 200)), m.accel(s, Vector2i(0, 200)), "under cap adds accel")
	return true

func test_drag() -> bool:
	eq(SkaterMotion.drag_axis(1000, 6), 985, "1000 - 15")
	eq(SkaterMotion.drag_axis(-1000, 6), -984, "asr floors toward -inf")
	eq(SkaterMotion.drag_axis(10, 6), 9, "minimum step 1")
	eq(SkaterMotion.drag_axis(-1, 6), 0, "-1 reaches 0")
	eq(SkaterMotion.drag_axis(0, 6), 0, "0 stays 0")
	eq(motion().apply_drag(Vector2i(1024, 0), true), Vector2i(1022, 0), "glide uses >> 9")
	return true

func test_stopna() -> bool:
	var m := motion()
	eq(m.apply_stop(Vector2i(1000, -1000)), Vector2i(850, -850), "150 toward 0")
	eq(m.apply_stop(Vector2i(100, -100)), Vector2i(0, 0), "does not cross 0")
	check(SkaterMotion.wants_stop_anim(Vector2i(0x1001, 0)), "stop anim above $1000")
	check(not SkaterMotion.wants_stop_anim(Vector2i(0x1000, -0x1000)), "no stop anim at $1000")
	return true

func test_units() -> bool:
	near(Nhl94Units.vel_to_px_per_sec(9625.0), 149.8, 0.1, "top speed px/s")
	near(Nhl94Units.px_per_sec_to_vel(Nhl94Units.vel_to_px_per_sec(1234.0)), 1234.0, 0.001, "round trip")
	near(Nhl94Units.frames(1.0 / 60.0), 1.0, 0.0001, "one tick is one retail frame")
	return true

func test_dir8() -> bool:
	check(Nhl94Units.dir8_to_vector(0).is_equal_approx(Vector2.UP), "dir 0 is up")
	check(Nhl94Units.dir8_to_vector(2).is_equal_approx(Vector2.RIGHT), "dir 2 is right")
	check(Nhl94Units.dir8_to_vector(1).is_equal_approx(Nhl94Units.rink_to_godot(Vector2(141, 141).normalized())), "dir 1 matches dirtab")
	return true

func test_puck_follow() -> bool:
	var w := HockeyWorld.new(SimSettings.new())
	var c := w.place(4, Vector2i(0, 0), SimObject.POS_C, false, true)
	w.drop_puck(Vector2i(0, -40))
	w.puckc = 4
	c.vel = Vector2i(300, 0)
	w.puck_logic.pucknorm(w.puck(), 1)
	var hot := w.get_hot(c)
	eq(w.puck().pos(), Vector2i(0, -40) + (hot - Vector2i(0, -40)) / 4, "closes 1/4 of the gap to the stick")
	eq(w.puck().vel, Vector2i(300, 0), "takes carrier velocity")
	w.dispose()
	return true

func test_fsm() -> bool:
	var f := PlayerFSM.new()
	check(f.enter(PlayerFSM.State.SKATING), "idle to skating")
	check(not f.enter(PlayerFSM.State.SKATING), "same state is a no-op")
	check(f.enter(PlayerFSM.State.FALLEN), "skating to fallen")
	check(not f.enter(PlayerFSM.State.SHOOTING), "fallen cannot shoot")
	f.tick(2.0)
	eq(f.frames_in_state, 2.0, "frame counter")
	return true

func test_wall_mask() -> bool:
	var m := motion()
	var s := SkaterMotion.Skater.new()
	s.weight = 8
	s.agility = 10
	eq(m.accel(s, Vector2i(0, 200), 1, Vector2i(0, 256)), Vector2i.ZERO, "no push into the top board")
	eq(m.accel(s, Vector2i(141, 141), 1, Vector2i(0, 256)), Vector2i(158, 0), "slide along the top board")
	eq(m.accel(s, Vector2i(0, -200), 1, Vector2i(0, 256)), Vector2i(0, -225), "push away from the board")
	eq(m.accel(s, Vector2i(200, 0), 1, Vector2i(-256, 0)), Vector2i(225, 0), "left board allows pushing right")
	return true

func test_vtoa() -> bool:
	var cases := [[Vector2i(0, 5), 0], [Vector2i(5, 5), 1], [Vector2i(5, 0), 2], [Vector2i(5, -5), 3],
		[Vector2i(0, -5), 4], [Vector2i(-5, -5), 5], [Vector2i(-5, 0), 6], [Vector2i(-5, 5), 7],
		[Vector2i(10, 4), 2], [Vector2i(10, 5), 1], [Vector2i.ZERO, SkaterSteering.JOY_NONE]]
	for c in cases:
		eq(SkaterSteering.vtoa(c[0]), c[1], "vtoa %s" % c[0])
	return true

func steering() -> SkaterSteering:
	return SkaterSteering.new(SimSettings.new())

## A skater object at y with velocity vel, attacking the top goal.
func skater_at(vel: Vector2i, y: int = 0) -> SimObject:
	var o := SimObject.new(4)
	o.position = SimObject.POS_C
	o.vel = vel
	o.set_pos(Vector2i(0, y))
	o.set_flag(SimObject.PF_GOAL, true)
	return o

func ctx_with(to_puck: Vector2i = Vector2i.ZERO, has_puck: bool = false) -> SkaterSteering.Context:
	var c := SkaterSteering.Context.new()
	c.to_puck = to_puck
	c.has_puck = has_puck
	return c

func test_steer_turn_in_place() -> bool:
	var o := skater_at(Vector2i.ZERO)
	var r := steering().steer(o, 2, ctx_with())
	eq(o.facing_fx, 0x300 * 16, "standing turn rate $300 * 16")
	eq(r.action, SkaterSteering.Action.NONE, "turning in place does not push")
	eq(o.spa, Spa.GLIDE, "slow turn keeps glide")
	o = skater_at(Vector2i.ZERO)
	steering().steer(o, 6, ctx_with())
	eq(o.facing_fx, SkaterSteering.FACING_WRAP - 0x3000, "left turn wraps below 0")
	return true

func test_steer_aligned() -> bool:
	var o := skater_at(Vector2i.ZERO)
	var r := steering().steer(o, 0, ctx_with())
	eq(r.action, SkaterSteering.Action.ACCEL, "aligned pushes")
	eq(r.accel_dir, 0, "along facing")
	eq(o.spa, Spa.SKATE, "skate anim")
	steering().steer(o, 0, ctx_with(Vector2i.ZERO, true))
	eq(o.spa, Spa.SKATE_PUCK, "skate with puck anim")
	o = skater_at(Vector2i.ZERO)
	o.flags2 |= SimObject.PF2_FIGHT_HURT
	steering().steer(o, 0, ctx_with())
	eq(o.spa, Spa.SKATE_INJURED, "hurt in a fight")
	return true

func test_steer_fast_turn() -> bool:
	var o := skater_at(Vector2i(0, 9000))
	var r := steering().steer(o, 1, ctx_with())
	eq(o.facing_fx, 0x180 * 16, "fast turn floors at $180")
	eq(o.spa, Spa.TURN_RIGHT, "turn right anim")
	check(o.anim_busy(), "turn anim is one-shot")
	eq(r.accel_dir, 0, "still pushing along old facing")
	o = skater_at(Vector2i(0, 9000))
	o.attribute |= 0x8
	steering().steer(o, 1, ctx_with())
	eq(o.spa, Spa.TURN_LEFT, "mirrored sprite swaps the turn anim")
	return true

func test_steer_hockey_stop() -> bool:
	var o := skater_at(Vector2i(0, 5000))
	var r := steering().steer(o, 4, ctx_with())
	check(r.stopping(), "stick opposite while moving forward stops")
	eq(o.spa, Spa.STOP, "stop anim above $1000")
	o = skater_at(Vector2i(0, 0x800))
	steering().steer(o, 4, ctx_with())
	eq(o.spa, Spa.GLIDE, "slow stop keeps glide")
	o = skater_at(Vector2i(100, 0))
	r = steering().steer(o, SkaterSteering.JOY_BRAKE, ctx_with())
	check(r.stopping(), "joy 9 stops a moving skater")
	return true

func test_steer_snap() -> bool:
	var o := skater_at(Vector2i.ZERO)
	var r := steering().steer(o, 4, ctx_with())
	eq(o.facing_fx, 1 << 16, "stick opposite while still snaps 45 degrees")
	eq(r.action, SkaterSteering.Action.NONE, "snap does not push")
	o = skater_at(Vector2i.ZERO)
	o.attribute |= 0x8
	steering().steer(o, 4, ctx_with())
	eq(o.facing_fx, 7 << 16, "mirrored snap goes the other way")
	return true

func test_steer_reverse() -> bool:
	var o := skater_at(Vector2i.ZERO, -100)
	var r := steering().steer(o, 4, ctx_with(Vector2i(0, 200)))
	check(o.reverse(), "own half, stick back, puck ahead: skate backwards")
	eq(r.accel_dir, 4, "push backwards")
	eq(o.spa, Spa.SKATE_BACK, "skate back anim")
	o.vel = Vector2i(0, -2000)
	steering().steer(o, 3, ctx_with(Vector2i(0, 200)))
	check(o.reverse(), "stays backwards within 45 degrees of straight back")
	steering().steer(o, 0, ctx_with(Vector2i(0, 200)))
	check(not o.reverse(), "stick forward ends backwards skating")
	o = skater_at(Vector2i.ZERO, 100)
	steering().steer(o, 4, ctx_with(Vector2i(0, 200)))
	check(not o.reverse(), "not in the attacking half")
	o = skater_at(Vector2i.ZERO, -100)
	steering().steer(o, 4, ctx_with(Vector2i(0, 200), true))
	check(not o.reverse(), "not with the puck")
	o = skater_at(Vector2i.ZERO, 100)
	o.set_flag(SimObject.PF_GOAL, false)
	steering().steer(o, 0, ctx_with(Vector2i(0, -200)))
	check(o.reverse(), "mirrored for the team attacking down")
	return true

func test_steer_no_momentum() -> bool:
	var s := SimSettings.new()
	s.enable_momentum = false
	var o := skater_at(Vector2i(0, 9000))
	var r := SkaterSteering.new(s).steer(o, 3, ctx_with())
	eq(o.facing(), 3, "facing snaps to the stick")
	eq(r.accel_dir, 3, "push along the stick")
	return true

func test_board_normals() -> bool:
	var rad := Vector2i(8, 4)
	eq(RinkBoards.board_normal(Vector2i.ZERO, rad), Vector2i.ZERO, "center ice")
	eq(RinkBoards.board_normal(Vector2i(0, 294), rad), Vector2i(0, 256), "top board at 298 - 4")
	eq(RinkBoards.board_normal(Vector2i(0, 293), rad), Vector2i.ZERO, "one pixel short")
	eq(RinkBoards.board_normal(Vector2i(0, -294), rad), Vector2i(0, -256), "bottom board")
	eq(RinkBoards.board_normal(Vector2i(128, 0), rad), Vector2i(256, 0), "right board at 136 - 8")
	eq(RinkBoards.board_normal(Vector2i(-128, 0), rad), Vector2i(-256, 0), "left board")
	eq(RinkBoards.board_normal(Vector2i(120, 280), rad), Vector2i(191, 170), "corner arc normal")
	eq(RinkBoards.board_normal(Vector2i(-120, -280), rad), Vector2i(-191, -170), "opposite corner")
	eq(RinkBoards.board_normal(Vector2i(100, 250), rad), Vector2i.ZERO, "inside the corner arc")
	return true

func test_bounce_skater() -> bool:
	var top := Vector2i(0, 256)
	eq(RinkBoards.bounce_skater(Vector2i(0, 4000), top).vel, Vector2i(0, -1000), "quarter bounce, -1000 at least")
	var h := RinkBoards.bounce_skater(Vector2i(3000, 8000), top)
	eq(h.vel, Vector2i(3000, -2000), "keeps tangent, quarter normal")
	check(h.hard, "hard hit above $1000")
	h = RinkBoards.bounce_skater(Vector2i(0, -2000), top)
	eq(h.vel, Vector2i(0, -2000), "moving away fast is left alone")
	eq(h.normal, top, "normal is stored anyway")
	eq(RinkBoards.bounce_skater(Vector2i(0, 100), top).vel, Vector2i(0, -1000), "slow drift pushed off at 1000")
	eq(RinkBoards.bounce_skater(Vector2i(5000, 3000), Vector2i(256, 0)).vel, Vector2i(-1250, 3000), "right board")
	return true

func test_bounce_puck() -> bool:
	var top := Vector2i(0, 256)
	eq(RinkBoards.bounce_puck(Vector2i(0, 4000), top).vel, Vector2i(0, -1000), "puck quarter normal")
	eq(RinkBoards.bounce_puck(Vector2i(6400, 4000), top).vel, Vector2i(6250, -1000), "tangent loses 3/128")
	check(RinkBoards.bounce_puck(Vector2i(0, 8000), top).puck_pop, "hard hit pops the puck")
	eq(RinkBoards.bounce_puck(Vector2i(0, -100), top).vel, Vector2i(0, -100), "moving away: no bounce")
	return true

## Whole world: a skater pushes up the ice from rest, reaches top speed, hits the end
## boards and stays in; then skates back down.
func test_world_skater_in_rink() -> bool:
	var w := HockeyWorld.new(SimSettings.new())
	var o := w.place(4, Vector2i(0, -100), SimObject.POS_C, false, true)
	o.weight = 6
	o.legstr = 15
	o.legspd = 15
	w.joy[4] = 0
	var top_speed := 0.0
	var min_y := 0
	var max_y := -1000
	for i in 600:
		w.step()
		top_speed = maxf(top_speed, Vector2(o.vel).length())
		max_y = maxi(max_y, o.y())
	# Speed 15 + 2 (the always-on crowd boost) = 17: index 8 with a half step to 9.
	var m := SkaterMotion.new()
	var cap := sqrt(float(m.max_speed_sq_entry(8) + ((m.max_speed_sq_entry(9) - m.max_speed_sq_entry(8)) >> 1)))
	check(top_speed <= cap + 1.0, "speed caps at MaxSpeed 8.5: %f > %f" % [top_speed, cap])
	check(top_speed >= cap * 0.95, "reaches top speed: %f of %f" % [top_speed, cap])
	# checkcoll also tests the stick tip (GetHot, radius 1), so the stick meets the
	# boards about 20 px before the body would.
	var stick_reach := max_y + w.get_hot(o).y
	check(stick_reach >= RinkBoards.END_BOARD - 3, "stick tip reaches the top boards: %d" % stick_reach)
	check(max_y <= RinkBoards.END_BOARD, "never past the end boards: %d" % max_y)
	w.joy[4] = 4
	for i in 600:
		w.step()
		min_y = mini(min_y, o.y())
	# Coming back down he is in his own half with the puck ahead, so he skates backwards
	# (stick up the ice) and his body meets the boards: 298 - radius 4.
	check(o.reverse(), "skates backwards in his own half")
	check(min_y <= -(RinkBoards.END_BOARD - 4), "body reaches the bottom boards: %d" % min_y)
	check(min_y >= -RinkBoards.END_BOARD, "never past the bottom boards: %d" % min_y)
	check(w.objects[0].pos() == Vector2i(384, 192), "off-ice objects stay put")
	w.dispose()
	return true

func test_rng() -> bool:
	var r := RetailRng.new(0)
	eq(r.range_(0x10000), 0, "seed 0 -> 1, bits 8-23 are 0")
	eq(r.seed, 1, "LCG +1")
	r.range_(100)
	eq(r.seed, (0xBB40E62D + 1) & 0xFFFFFFFF, "seed * $BB40E62D + 1")
	var lo := 1000
	var hi := -1000
	for i in 2000:
		var v := r.signed(50)
		lo = mini(lo, v)
		hi = maxi(hi, v)
	check(lo >= -50 and hi < 50, "randomd0s range [-50, 50): %d..%d" % [lo, hi])
	return true

func test_z_bounce() -> bool:
	var w := HockeyWorld.new(SimSettings.new())
	var p := w.puck()
	p.zvel = 0x400
	var peak := 0
	var landed := [false]
	w.landed.connect(func(_i: int, _zv: int) -> void: landed[0] = true)
	for i in 120:
		w.step()
		peak = maxi(peak, p.z())
	check(landed[0], "puck came down")
	check(peak > 0, "puck rose: %d" % peak)
	check(p.z() >= 0, "never under the ice")
	w.dispose()
	return true

## Two skaters at (0,0) and (dx,0) in a fresh world; a3 is index 1, a2 is index 2 (or 7).
func pair(dx: int, opponents: bool) -> Array:
	var w := HockeyWorld.new(SimSettings.new())
	var a3 := w.place(1, Vector2i(0, 0), SimObject.POS_LD, false, true)
	var a2 := w.place(7 if opponents else 2, Vector2i(dx, 0), SimObject.POS_LD, opponents, not opponents)
	return [w, a3, a2]

func test_exchange_head_on() -> bool:
	var t := pair(10, false)
	var w: HockeyWorld = t[0]
	var a3: SimObject = t[1]
	var a2: SimObject = t[2]
	a3.vel = Vector2i(1000, 0)
	w.collflag = 0
	w.collisions.checkcx(a3, a2, a3.x(), 0)
	# V1n = 10000 >> 4 = 625; V1n' = 625 * 140 / 280 = 312; out = 312 * 10 >> 4 = 195.
	eq(a3.vel, Vector2i(195, 0), "a3 keeps m1/(m1+m2), scaled by |D|^2/256")
	eq(a2.vel, Vector2i(195, 0), "a2 gains the same normal speed")
	eq(w.collflag, -1, "collflag set")
	eq(a3.impact, 0, "teammates add no impact")
	w.dispose()
	return true

func test_opponent_impact() -> bool:
	var t := pair(10, true)
	var w: HockeyWorld = t[0]
	var a3: SimObject = t[1]
	var a2: SimObject = t[2]
	a3.vel = Vector2i(1000, 0)
	w.collisions.checkcx(a3, a2, a3.x(), 0)
	eq(a3.impact, 5, "minimum impact 5")
	eq(a2.impact, 5, "both sides")
	eq(a3.impactp, a2.index, "impactp names the other player")
	w.dispose()
	return true

func test_moving_apart() -> bool:
	var t := pair(10, true)
	var w: HockeyWorld = t[0]
	var a3: SimObject = t[1]
	var a2: SimObject = t[2]
	a3.vel = Vector2i(-1000, 0)
	w.collisions.checkcx(a3, a2, a3.x(), 0)
	eq(a3.vel, Vector2i(-1000, 0), "no exchange when separating")
	eq(w.collflag, 0, "collflag untouched")
	w.dispose()
	return true

func test_body_check_floors() -> bool:
	var t := pair(10, true)
	var w: HockeyWorld = t[0]
	var a3: SimObject = t[1]
	var a2: SimObject = t[2]
	a3.checking = 30
	a3.set_spa(Checking.SPA_BURST)
	a3.vel = Vector2i(9000, 0)
	a2.impact = 100
	w.collisions.checkcx(a3, a2, a3.x(), 0)
	eq(a3.spa, 0xC2C, "target to the right of a facing-up checker: hip check right")
	check(a3.locked(), "checker locked")
	eq(a2.spa, Checking.SPA_BIG_HIT, "hit from behind while facing straight up, Chk >= $14: big hit")
	check(a2.locked(), "faller locked")
	eq(w.stats[0].checks, 1, "team check counted")
	eq(a2.nopuck_hi, 0x78, "faller cannot touch the puck for 120 frames")
	w.dispose()
	return true

func test_fall_dedupe() -> bool:
	var t := pair(10, true)
	var w: HockeyWorld = t[0]
	var a3: SimObject = t[1]
	var a2: SimObject = t[2]
	w.checking.fall_down(a2, a3)
	a2.flags &= ~SimObject.PF_ALOCK
	a2.set_spa(Spa.GLIDE)
	eq(w.checking.fall_down(a2, a3), Collisions.D1_UNCHANGED, "same pair cannot fall twice in a row")
	w.dispose()
	return true

func test_holdcheck() -> bool:
	var t := pair(10, true)
	var w: HockeyWorld = t[0]
	var holder: SimObject = t[1]
	var target: SimObject = t[2]
	holder.facing_fx = 2 << 16
	holder.set_spa(Checking.SPA_HOLD)
	holder.vel = Vector2i(400, 0)
	target.vel = Vector2i(0, 200)
	w.checking.holdcheck(holder, target)
	eq(holder.vel, Vector2i(200, 100), "velocities averaged")
	eq(target.vel, Vector2i(200, 100), "both")
	eq(target.spa, Checking.SPA_FLAIL, "target flails")
	eq(holder.spa, Checking.SPA_HOLD_AFTER, "holder from $1122 goes to $1154")
	eq(w.collflag, -1, "no momentum exchange")
	w.dispose()
	return true

func test_checkagr_max_aggression() -> bool:
	var t := pair(10, true)
	var w: HockeyWorld = t[0]
	var a3: SimObject = t[1]
	var a2: SimObject = t[2]
	a3.aggress = 0x28
	eq(w.checking.checkagr(a3, a2), 0, "aggression $28 leaves range 0: always a penalty")
	w.delayed_pen = 4
	eq(w.checking.checkagr(a3, a2), 0x7F, "no call while the opponent has a delayed penalty")
	w.dispose()
	return true

func test_board_pin() -> bool:
	var w := HockeyWorld.new(SimSettings.new())
	var o := w.place(1, Vector2i(100, 0), SimObject.POS_LD, false, true)
	o.set_spa(Checking.SPA_BOARDS_RIGHT)
	o.spa_num = 0
	w.checking.pin_to_boards(o)
	eq(o.x(), 100 + ((0x82 - 100) >> 1), "first frame eases halfway")
	o.spa_num = 4
	w.checking.pin_to_boards(o)
	eq(o.x(), 0x82, "then pins to x = $82")
	w.dispose()
	return true

## Two opponents skate into each other: they slow down, build impact, and do not pass
## through each other.
func test_world_collision() -> bool:
	var w := HockeyWorld.new(SimSettings.new())
	var a := w.place(1, Vector2i(0, -60), SimObject.POS_LD, false, true)
	var b := w.place(7, Vector2i(0, 60), SimObject.POS_LD, true, false)
	for o in [a, b]:
		o.weight = 6
		o.legstr = 15
		o.legspd = 15
	w.joy[1] = 0
	w.joy[7] = 4
	var touched := false
	var crossed := false
	for i in 240:
		w.step()
		if a.impact > 0:
			touched = true
		if a.y() > b.y() + 4:
			crossed = true
	check(touched, "they collided")
	check(not crossed, "and did not pass through each other")
	w.dispose()
	return true

## A world with one home skater at `at` facing up, and the puck on his stick.
func puck_world(at: Vector2i) -> Array:
	var w := HockeyWorld.new(SimSettings.new())
	var o := w.place(4, at, SimObject.POS_C, false, true)
	o.stickhand = 15
	w.drop_puck(at + w.get_hot(o))
	return [w, o]

func test_puck_pickup() -> bool:
	var t := puck_world(Vector2i(0, 0))
	var w: HockeyWorld = t[0]
	w.step()
	eq(w.puckc, 4, "a still puck on the stick is picked up")
	w.dispose()
	return true

func test_puck_too_fast() -> bool:
	var t := puck_world(Vector2i(0, 0))
	var w: HockeyWorld = t[0]
	var o: SimObject = t[1]
	# Speed 20000 > 15 * 350 + 13000 = 18250: too fast to control.
	w.puck().vel = Vector2i(0, -20000)
	w.puck_logic.checkpuckcoll(w.puck())
	eq(w.puckc, -1, "not controlled")
	eq(o.nopuck_hi, 8, "and the skater is locked out for 8 frames")
	w.dispose()
	return true

func test_goalie_steals() -> bool:
	var w := HockeyWorld.new(SimSettings.new())
	var c := w.place(4, Vector2i(0, 200), SimObject.POS_C, false, true)
	var g := w.place(6, Vector2i(0, 230), SimObject.POS_GOALIE, true, false)
	w.drop_puck(Vector2i(0, 215))
	w.puckc = 4
	w.puck_logic.puckstick(g, w.puck(), 0)
	eq(w.puckc, -1, "the goalie knocks the puck loose")
	check(c.nopuck_hi >= 0x14 and g.nopuck_hi >= 0x14, "both locked out for Stk/2 + 20")
	eq(w.lastplayer, 4, "lastplayer is the carrier")
	w.dispose()
	return true

func test_goal() -> bool:
	var w := HockeyWorld.new(SimSettings.new())
	var shooter := w.place(4, Vector2i(30, 200), SimObject.POS_C, false, true)
	shooter.pnum = 3
	w.stats[0].toucher = 3
	w.drop_puck(Vector2i(0, 240))
	w.puck().vel = Vector2i(0, 6000)
	var scored := [-1]
	w.goal_scored.connect(func(team: int, _rec: Dictionary) -> void: scored[0] = team)
	for i in 30:
		w.step()
	eq(scored[0], 0, "home scores in the top net")
	eq(w.score(0), 1, "score")
	eq(w.stats[0].player_goals[3], 1, "scorer credited")
	eq(w.puck().pos(), Vector2i(6, 0x110), "puck sits in the back of the net")
	check(w.puck().flags & SimObject.PF_NC != 0, "puck stops colliding")
	w.dispose()
	return true

func test_post() -> bool:
	var w := HockeyWorld.new(SimSettings.new())
	var sounds := []
	w.sound.connect(func(id: int) -> void: sounds.append(id))
	# Crossing the mouth at x = 21: the post.
	w.drop_puck(Vector2i(21, 250))
	w.puck().vel = Vector2i(0, 6000)
	for i in 30:
		w.step()
	eq(w.score(0), 0, "no goal off the post")
	check(8 in sounds, "post sound (8 while play runs)")
	check(w.puck().vel.y < 0, "deflected away from the net")
	w.dispose()
	return true

func test_over_glass() -> bool:
	var w := HockeyWorld.new(SimSettings.new())
	var calls := []
	w.penalty_called.connect(func(id: int, _o: int) -> void: calls.append(id))
	w.drop_puck(Vector2i(120, 0))
	w.puck().vel = Vector2i(9000, 0)
	w.puck().z_fx = 25 << 16
	w.puck().zvel = 1000
	for i in 10:
		w.step()
	check(w.puck().flags & SimObject.PF_NC != 0, "puck left the rink")
	check(PuckLogic.PEN_STALLED in calls, "puck out of play whistle (id 6)")
	w.dispose()
	return true

func test_goalie_covers() -> bool:
	var w := HockeyWorld.new(SimSettings.new())
	var g := w.place(6, Vector2i(0, 250), SimObject.POS_GOALIE, true, false)
	g.legstr = 20
	# Away from the goalie's stick (at -4, 230) so the body box decides.
	w.drop_puck(Vector2i(8, 244))
	w.puck().vel = Vector2i(0, 200)
	for i in 10:
		w.step()
	eq(w.puckc, 6, "a slow puck into the goalie's body is covered")
	w.dispose()
	return true

func test_findpc() -> bool:
	var w := HockeyWorld.new(SimSettings.new())
	w.drop_puck(Vector2i(10, 0))
	w.puck().vel = Vector2i(1024, 4096)
	w.puck_logic.findpc()
	eq(w.puckcross[1], 264, "loops to the top line: 264 * 4096 / 4096")
	eq(w.puckcross[0], 10 + 66, "x there: 264 * 1024 / 4096 + 10")
	w.puck().vel = Vector2i(2048, 4096)
	w.puck_logic.findpc()
	eq(w.puckcross[0], 408 - 142, "past the sideboards the x mirrors as 408 - x (retail quirk)")
	eq(w.puckcross[3], -1, "moving away from the bottom line")
	w.dispose()
	return true

func test_icing() -> bool:
	var w := HockeyWorld.new(SimSettings.new())
	var h := w.place(1, Vector2i(0, -100), SimObject.POS_LD, false, true)
	var a := w.place(7, Vector2i(100, 280), SimObject.POS_LD, true, false)
	var calls := []
	w.penalty_called.connect(func(id: int, _o: int) -> void: calls.append(id))
	w.drop_puck(Vector2i(0, -100))
	w.puck_logic.a2touchpuck(h)
	check(w.iflags & HockeyWorld.IF_OK != 0, "armed from the own half at even strength")
	w.drop_puck(Vector2i(100, 270))
	w.puck_logic.puck_i_chk()
	check(w.iflags & HockeyWorld.IF_CGL != 0, "crossed the far goal line wide of the crease")
	w.puck_logic.a2touchpuck(a)
	check(PuckLogic.PEN_ICING in calls, "icing called when the other team touches it")
	w.dispose()
	return true

func test_offside() -> bool:
	var w := HockeyWorld.new(SimSettings.new())
	w.gmode |= HockeyWorld.GM_OFFS
	var h := w.place(3, Vector2i(-40, 120), SimObject.POS_LW, false, true)
	var calls := []
	w.penalty_called.connect(func(id: int, _o: int) -> void: calls.append(id))
	var p := w.puck()
	w.drop_puck(Vector2i(0, 80))
	p.old_pos_fx = p.pos_fx
	p.set_pos(Vector2i(0, 90))
	w.puck_logic.chk_offsides(p)
	check(w.stats[0].flags30 & TeamStats.F30_OFFSIDE != 0, "home flagged: a skater was past the line when the puck crossed")
	w.drop_puck(Vector2i(0, 110))
	w.puck_logic.a2touchpuck(h)
	check(PuckLogic.PEN_OFFSIDE in calls, "offside called when he touches it in the zone")
	w.dispose()
	return true
