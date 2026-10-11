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
		"test_skater_node_in_rink",
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
	var p := PuckPhysics.new(SimSettings.new())
	var r := p.follow_carrier(Vector2(0, 0), Vector2(8, -4), Vector2(3, 0))
	eq(r[0], Vector2(2, -1), "closes 1/4 of the gap")
	eq(r[1], Vector2(3, 0), "takes carrier velocity")
	var s := SimSettings.new()
	s.enable_puck_friction = false
	eq(PuckPhysics.new(s).loose_drag(Vector2i(1000, 0)), Vector2i(1000, 0), "friction toggle")
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

func ctx_at(vel: Vector2i, y: int = 0, to_puck: Vector2i = Vector2i.ZERO) -> SkaterSteering.Context:
	var c := SkaterSteering.Context.new()
	c.vel = vel
	c.y = y
	c.to_puck = to_puck
	return c

func test_steer_turn_in_place() -> bool:
	var st := SkaterSteering.State.new()
	var r := steering().steer(st, 2, ctx_at(Vector2i.ZERO))
	eq(st.facing_fx, 0x300 * 16, "standing turn rate $300 * 16")
	eq(r.action, SkaterSteering.Action.NONE, "turning in place does not push")
	eq(st.anim, SkaterSteering.Anim.GLIDE, "slow turn keeps glide")
	st = SkaterSteering.State.new()
	steering().steer(st, 6, ctx_at(Vector2i.ZERO))
	eq(st.facing_fx, SkaterSteering.FACING_WRAP - 0x3000, "left turn wraps below 0")
	return true

func test_steer_aligned() -> bool:
	var st := SkaterSteering.State.new()
	var r := steering().steer(st, 0, ctx_at(Vector2i.ZERO))
	eq(r.action, SkaterSteering.Action.ACCEL, "aligned pushes")
	eq(r.accel_dir, 0, "along facing")
	eq(st.anim, SkaterSteering.Anim.SKATE, "skate anim")
	var c := ctx_at(Vector2i.ZERO)
	c.has_puck = true
	steering().steer(st, 0, c)
	eq(st.anim, SkaterSteering.Anim.SKATE_PUCK, "skate with puck anim")
	return true

func test_steer_fast_turn() -> bool:
	var st := SkaterSteering.State.new()
	var r := steering().steer(st, 1, ctx_at(Vector2i(0, 9000)))
	eq(st.facing_fx, 0x180 * 16, "fast turn floors at $180")
	eq(st.anim, SkaterSteering.Anim.TURN_RIGHT, "turn right anim")
	check(st.anim_busy, "turn anim is one-shot")
	eq(r.accel_dir, 0, "still pushing along old facing")
	st = SkaterSteering.State.new()
	st.x_flip = true
	steering().steer(st, 1, ctx_at(Vector2i(0, 9000)))
	eq(st.anim, SkaterSteering.Anim.TURN_LEFT, "mirrored sprite swaps the turn anim")
	return true

func test_steer_hockey_stop() -> bool:
	var st := SkaterSteering.State.new()
	var r := steering().steer(st, 4, ctx_at(Vector2i(0, 5000)))
	check(r.stopping(), "stick opposite while moving forward stops")
	eq(st.anim, SkaterSteering.Anim.STOP, "stop anim above $1000")
	st = SkaterSteering.State.new()
	steering().steer(st, 4, ctx_at(Vector2i(0, 0x800)))
	eq(st.anim, SkaterSteering.Anim.GLIDE, "slow stop keeps glide")
	st = SkaterSteering.State.new()
	r = steering().steer(st, SkaterSteering.JOY_BRAKE, ctx_at(Vector2i(100, 0)))
	check(r.stopping(), "joy 9 stops a moving skater")
	return true

func test_steer_snap() -> bool:
	var st := SkaterSteering.State.new()
	var r := steering().steer(st, 4, ctx_at(Vector2i.ZERO))
	eq(st.facing_fx, 1 << 16, "stick opposite while still snaps 45 degrees")
	eq(r.action, SkaterSteering.Action.NONE, "snap does not push")
	st = SkaterSteering.State.new()
	st.x_flip = true
	steering().steer(st, 4, ctx_at(Vector2i.ZERO))
	eq(st.facing_fx, 7 << 16, "mirrored snap goes the other way")
	return true

func test_steer_reverse() -> bool:
	var st := SkaterSteering.State.new()
	var r := steering().steer(st, 4, ctx_at(Vector2i.ZERO, -100, Vector2i(0, 200)))
	check(st.reverse, "own half, stick back, puck ahead: skate backwards")
	eq(r.accel_dir, 4, "push backwards")
	eq(st.anim, SkaterSteering.Anim.SKATE_BACK, "skate back anim")
	r = steering().steer(st, 3, ctx_at(Vector2i(0, -2000), -100, Vector2i(0, 200)))
	check(st.reverse, "stays backwards within 45 degrees of straight back")
	steering().steer(st, 0, ctx_at(Vector2i(0, -2000), -100, Vector2i(0, 200)))
	check(not st.reverse, "stick forward ends backwards skating")
	st = SkaterSteering.State.new()
	steering().steer(st, 4, ctx_at(Vector2i.ZERO, 100, Vector2i(0, 200)))
	check(not st.reverse, "not in the attacking half")
	st = SkaterSteering.State.new()
	var c := ctx_at(Vector2i.ZERO, -100, Vector2i(0, 200))
	c.has_puck = true
	steering().steer(st, 4, c)
	check(not st.reverse, "not with the puck")
	st = SkaterSteering.State.new()
	c = ctx_at(Vector2i.ZERO, 100, Vector2i(0, -200))
	c.attacking_top = false
	steering().steer(st, 0, c)
	check(st.reverse, "mirrored for the team attacking down")
	return true

func test_steer_no_momentum() -> bool:
	var s := SimSettings.new()
	s.enable_momentum = false
	var st := SkaterSteering.State.new()
	var r := SkaterSteering.new(s).steer(st, 3, ctx_at(Vector2i(0, 9000)))
	eq(st.facing(), 3, "facing snaps to the stick")
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

## Whole skater: push up the ice from rest, reach top speed, hit the end boards, stay in.
	return true
func test_skater_node_in_rink() -> bool:
	var sk: Skater2D = load("res://nodes/skater.gd").new()
	sk.position = Vector2(0, 100)
	root.add_child(sk)
	sk.ai_joy = 0
	var top_speed := 0.0
	var min_y := 0
	var max_y := -1000
	for i in 600:
		sk.retail_loop()
		top_speed = maxf(top_speed, Vector2(sk.vel).length())
		max_y = maxi(max_y, sk.retail_pos().y)
	# Default sandbox skater: speed 15, so index 7 with a half step to 8 (odd speed).
	var m := SkaterMotion.new()
	var cap := sqrt(float(m.max_speed_sq_entry(7) + ((m.max_speed_sq_entry(8) - m.max_speed_sq_entry(7)) >> 1)))
	check(top_speed <= cap + 1.0, "speed caps at MaxSpeed 7.5: %f > %f" % [top_speed, cap])
	check(top_speed >= cap * 0.95, "reaches top speed: %f of %f" % [top_speed, cap])
	check(max_y >= RinkBoards.END_BOARD - 8, "reaches the top boards: %d" % max_y)
	check(max_y <= RinkBoards.END_BOARD, "never past the end boards: %d" % max_y)
	check(sk.wall_normal != Vector2i.ZERO or sk.vel.y <= 0, "pinned against or bouncing off the top board")
	sk.ai_joy = 4
	for i in 600:
		sk.retail_loop()
		min_y = mini(min_y, sk.retail_pos().y)
	check(min_y <= -(RinkBoards.END_BOARD - 8), "reaches the bottom boards: %d" % min_y)
	check(min_y >= -RinkBoards.END_BOARD, "never past the bottom boards: %d" % min_y)
	sk.queue_free()
	return true
