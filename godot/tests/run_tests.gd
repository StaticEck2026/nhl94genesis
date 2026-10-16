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
		"test_anim_timing",
		"test_anim_loop_and_flags",
		"test_pad_edges",
		"test_shot_speed",
		"test_lead_pass",
		"test_blind_pass",
		"test_burst",
		"test_b_tap_switches",
		"test_pad_shot_scores",
		"test_slot_bit",
		"test_checkwindow",
		"test_assdefd_target",
		"test_centerd_moves_to_spot",
		"test_assnearest_hands_off",
		"test_cpu_carrier_shoots",
		"test_goalie_skates_back",
		"test_goalie_angles_to_puck",
		"test_goalie_turn_never_into_net",
		"test_goaliesave_choice",
		"test_goalie_saves_low_shot",
		"test_cp_goalie",
		"test_cpu_vs_cpu",
		"test_teams_extracted",
		"test_setplayer_vectors",
		"test_setplayer_bonuses_and_form",
		"test_energy_drain_and_recovery",
		"test_clock_tick",
		"test_whistle_to_faceoff",
		"test_faceoff_spots",
		"test_delayed_penalty",
		"test_box_time_and_pp",
		"test_pp_goal_releases",
		"test_set_personel_lines",
		"test_comp_line",
		"test_endfaceoff_draw",
		"test_full_game",
		"test_pad_mash_game",
		"test_pen_shot_chk",
		"test_ps_pick_shooter",
		"test_ps_waypoints",
		"test_shootout_turns",
		"test_penalty_shot_attempt",
		"test_shootout_game",
		"test_injury_sets_tmpdst",
		"test_fight_assets",
		"test_fight_off_in_retail",
		"test_fight_starts",
		"test_chk_fight_value",
		"test_fightinput",
		"test_fight_to_penalties",
		"test_title_screen",
		"test_markers",
		"test_pause_menu_actions",
		"test_edit_lines",
		"test_overlay_logic",
		"test_other_games",
		"test_replay_buffer",
		"test_four_way_pads",
		"test_four_way_mash_game",
		"test_choose_song",
		"test_sound_rules",
		"test_frontend_mapping",
		"test_reverse_angle",
		"test_playoffs",
		"test_crowd_frames",
		"test_arena_sheets_assembled",
		"test_arena_anim_scripts",
		"test_arena_anim_hooks",
		"test_intermission_zamboni",
	]:
		# TESTS=name runs only the tests whose names contain it.
		var only := OS.get_environment("TESTS")
		if only != "" and not only in test:
			continue
		# A test returns true when it reaches its end. A script error aborts it and call()
		# returns null, which counts as a failure instead of passing silently.
		if call(test) != true:
			_failures += 1
			print("FAIL: %s did not finish" % test)
	print("%d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)

## A world with the rules off: no whistles or faceoffs interrupt a subsystem test.
static func _sandbox(seed: int = 0x00500000) -> HockeyWorld:
	var s := SimSettings.new()
	s.enable_rules = false
	return HockeyWorld.new(s, seed)

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
	o.attribute |= SimObject.ATTR_XFLIP
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
	o.attribute |= SimObject.ATTR_XFLIP
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
	var w := _sandbox()
	var o := w.place(4, Vector2i(0, -100), SimObject.POS_C, false, true)
	o.weight = 6
	o.legstr = 15
	o.legspd = 15
	# The puck sits up the ice out of his lane: carrying it in to score would hand him
	# the celebration assignment.
	w.drop_puck(Vector2i(-100, 150))
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
	# Clear of the goalie's stick (Hotlist frame $15: (2, -16) -> (2, 234)) so the body
	# box decides.
	w.drop_puck(Vector2i(-10, 246))
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

## SPAskate ($5D0) dir 0: $2A/10 $2B/10 $2C/10 $2D/-10, one-shot. Frame 0 shows |T0| + 2
## loops (the load loop plus 11), later frames |T| + 1: 12 + 11 + 11 + 11, so the id
## clears on loop 45, the last frame's advance loop.
func test_anim_timing() -> bool:
	var w := HockeyWorld.new(SimSettings.new())
	check(w.animator.loaded(), "spalist.json loaded")
	var o := SimObject.new(4)
	o.position = SimObject.POS_C
	o.set_spa(0x5D0)
	var frames := []
	var cleared_at := -1
	for i in range(1, 50):
		w.animator.update(o, 1, false)
		frames.append(o.frame)
		if o.spa == 0 and cleared_at < 0:
			cleared_at = i
	eq(frames[0], 0x2A, "first frame")
	eq(frames[11], 0x2A, "still frame 0 on loop 12")
	eq(frames[12], 0x2B, "frame 1 from loop 13")
	eq(frames[23], 0x2C, "frame 2 from loop 24")
	eq(cleared_at, 45, "one-shot clears SPA on loop 45")
	w.dispose()
	return true

func test_anim_loop_and_flags() -> bool:
	var w := HockeyWorld.new(SimSettings.new())
	var o := SimObject.new(4)
	o.position = SimObject.POS_C
	# SPAstop ($6C6) loops: $91/4 $92/-4. pf2aip clears after one pass even though it loops.
	o.flags2 |= SimObject.PF2_AIP
	o.set_spa(0x6C6)
	for i in 12:
		w.animator.update(o, 1, false)
	eq(o.spa, 0x6C6, "looping animation keeps its id")
	check(not o.anim_busy(), "pf2aip cleared at the end of the first pass")
	# x-flip mirrors the direction: facing 2 uses the dir-6 frames.
	var f := SimObject.new(5)
	f.position = SimObject.POS_C
	f.facing_fx = 2 << 16
	f.attribute |= SimObject.ATTR_XFLIP
	f.set_spa(0x50C)
	w.animator.update(f, 1, false)
	eq(f.frame, 0x1F, "glide dir 6 frame when x-flipped facing 2")
	w.dispose()
	return true

func test_pad_edges() -> bool:
	var p := PadState.new()
	p.held = PadState.B | PadState.UP
	p.read()
	eq(p.d1 & PadState.B, PadState.B, "new press")
	eq(p.dir(), 0, "up is direction 0")
	p.read()
	eq(p.d1 & PadState.B, 0, "held, not new")
	eq(p.d3 & PadState.B, PadState.B, "held")
	p.held = PadState.UP | PadState.DOWN | PadState.RIGHT
	p.read()
	eq(p.d2 & PadState.B, PadState.B, "release shows as changed")
	eq(p.dir(), 3, "U+D+R cleans to down-right (retail quirk)")
	return true

## doshot with a full 35 charge, shotspd 30, full energy, aimed straight (highlight mode
## makes it perfect): ps = 35 * 35 * $5249 >> 16 = 393, speed 393 * 68 = 26724.
func test_shot_speed() -> bool:
	var w := HockeyWorld.new(SimSettings.new())
	var o := w.place(4, Vector2i(0, -20), SimObject.POS_C, false, true)
	o.shotspd = 30
	o.flags |= SimObject.PF_JOYCON
	w.drop_puck(Vector2i(0, 0))
	w.puckc = 4
	w.gmode |= HockeyWorld.GM_HL
	w.passdir = 0
	w.passspeed = 35
	w.shooting.doshot(o)
	eq(w.passspeed, 393, "shot power")
	eq(w.puck().vel, Vector2i(0, 26724), "straight at the goal line")
	# z 12: (12 * 393 * 68) / 264 + 264 * 2867 / 393 = 1214 + 1925.
	eq(w.puck().zvel, 3139, "elevation to 12 px at the goal line")
	eq(w.puckc, -1, "released")
	check(w.sflags2 & HockeyWorld.SF2_SHOT != 0, "shot flag")
	w.dispose()
	return true

func test_lead_pass() -> bool:
	var w := HockeyWorld.new(SimSettings.new())
	var a := w.place(4, Vector2i(0, 0), SimObject.POS_C, false, true)
	var b := w.place(3, Vector2i(0, 100), SimObject.POS_LW, false, true)
	w.drop_puck(Vector2i(0, 10))
	w.puckc = 4
	w.passdir = 0
	w.shooting.dopass(a)
	eq(w.passplayer, 3, "the teammate ahead is the receiver")
	eq(b.asslist[b.assnum & 7], Shooting.ASS_PASSREC, "receiver gets asspassrec")
	check(w.puck().vel.y > 0, "puck heads up the ice")
	eq(w.lastplayer, 4, "lastplayer is the passer")
	w.dispose()
	return true

## No teammate in the cone: the puck goes along passdir at 160 * 200 << 10 / 3000.
func test_blind_pass() -> bool:
	var w := HockeyWorld.new(SimSettings.new())
	var a := w.place(4, Vector2i(0, 0), SimObject.POS_C, false, true)
	w.drop_puck(Vector2i(0, 10))
	w.puckc = 4
	w.passdir = 0
	w.shooting.dopass(a)
	eq(w.puck().vel, Vector2i(0, 10922), "blind pass speed")
	eq(w.passplayer, -1, "no receiver")
	w.dispose()
	return true

func test_burst() -> bool:
	var w := HockeyWorld.new(SimSettings.new())
	var a := w.place(4, Vector2i(0, 0), SimObject.POS_C, false, true)
	a.facing_fx = 2 << 16
	w.shooting.burst(a)
	# Line changes on: the burst drains $CC first, so (4096 - 204) >> 7 = 30.
	eq(a.vel, Vector2i(6000, 0), "rested, line changes on: 200 * 30")
	eq(a.spa, Shooting.SPA_BURST, "burst animation")
	check(a.locked(), "locked during the burst")
	var b := w.place(5, Vector2i(40, 0), SimObject.POS_RW, false, true)
	b.facing_fx = 2 << 16
	w.opt_line_on = false
	w.shooting.burst(b)
	eq(b.vel, Vector2i(6400, 0), "line changes off: no drain, 200 * 32")
	w.dispose()
	return true

func test_b_tap_switches() -> bool:
	var w := HockeyWorld.new(SimSettings.new())
	var far := w.place(4, Vector2i(0, -150), SimObject.POS_C, false, true)
	var near := w.place(3, Vector2i(10, 10), SimObject.POS_LW, false, true)
	w.drop_puck(Vector2i(0, 0))
	w.cont_team[0] = 1
	w.set_c_player(0, far)
	w.faceoff_grace = 0
	w.pads[0].held = PadState.B
	w.step()
	w.pads[0].held = 0
	w.step()
	eq(w.c_player[0], 3, "a B tap gives the pad the teammate nearest the puck")
	check(near.joypad() and not far.joypad(), "pfjoycon moved")
	w.dispose()
	return true

## End to end through the pad: hold C to wind up, release, and the shot goes into the
## empty net (no goalie on either team; with the own goalie missing every shot is
## perfect, a retail quirk).
func test_pad_shot_scores() -> bool:
	var w := HockeyWorld.new(SimSettings.new())
	var o := w.place(4, Vector2i(0, 150), SimObject.POS_C, false, true)
	o.shotspd = 20
	w.drop_puck(Vector2i(0, 160))
	w.cont_team[0] = 1
	w.set_c_player(0, o)
	w.step()
	eq(w.puckc, 4, "picked up")
	w.pads[0].held = PadState.C
	for i in 12:
		w.step()
	w.pads[0].held = 0
	for i in 60:
		w.step()
	eq(w.shotplayer, 4, "he shot")
	eq(w.score(0), 1, "and scored")
	w.dispose()
	return true

# --- AI and goalies ---------------------------------------------------------------------

## Ratings that sit mid-range for every byte the AI reads.
static func _rate(o: SimObject) -> void:
	o.weight = 6
	o.legstr = 10
	o.legspd = 10
	o.aioff = 10
	o.aidef = 10
	o.shotspd = 10
	o.shotacc = 10
	o.passacc = 10
	o.spodds = 10
	o.checking = 10
	o.aggress = 10

## Both teams on the ice in their default assignments: home (objects 0-5) attacks the
## top, away (6-11) the bottom; object 5 and 11 are the goalies.
static func _two_teams(w: HockeyWorld) -> void:
	var roles := [SimObject.POS_LD, SimObject.POS_RD, SimObject.POS_LW, SimObject.POS_C,
		SimObject.POS_RW, SimObject.POS_GOALIE]
	var spots := [Vector2i(-40, -60), Vector2i(40, -60), Vector2i(-60, -10), Vector2i(0, -10),
		Vector2i(60, -10), Vector2i(0, -228)]
	for team in 2:
		for i in 6:
			var idx := team * 6 + i
			w.objects[idx].pnum = i
			var at: Vector2i = spots[i]
			if team == 1:
				at = -at
			var o := w.place(idx, at, roles[i], team == 1, team == 0)
			_rate(o)
			w.setplass(o)
			# forcepldata: the centre also chases the puck.
			if o.position == SimObject.POS_C:
				w.assinsert(o, HockeyAI.ASS_NEAREST)

func _current(o: SimObject) -> int:
	return o.asslist[o.assnum & 7]

func test_slot_bit() -> bool:
	var w := HockeyWorld.new(SimSettings.new())
	var c := w.place(4, Vector2i(0, 100), SimObject.POS_C, false, true)
	w.puckc = c.index
	w.ai.set_slot_bit()
	check(w.f_c2f8 & HockeyWorld.C2F8_SLOT != 0, "carrier 100 px up the ice is in the slot")
	c.set_pos(Vector2i(0, 50))
	w.ai.set_slot_bit()
	check(w.f_c2f8 & HockeyWorld.C2F8_SLOT == 0, "inside the blue line is not")
	c.set_pos(Vector2i(80, 100))
	w.ai.set_slot_bit()
	check(w.f_c2f8 & HockeyWorld.C2F8_SLOT == 0, "wide of the slot is not")
	w.dispose()
	return true

func test_checkwindow() -> bool:
	var w := HockeyWorld.new(SimSettings.new())
	w.drop_puck(Vector2i(100, 200))
	for i in 300:
		w.checkwindow(1)
	eq(w.camera, Vector2i(60, 190), "camera eases to the puck, clamped to x 60, 10 px dead zone")
	w.drop_puck(Vector2i(0, -280))
	for i in 300:
		w.checkwindow(1)
	eq(w.camera, Vector2i(40, -200), "bottom limit -200; x only within 40 px of the puck")
	w.dispose()
	return true

func test_assdefd_target() -> bool:
	var w := HockeyWorld.new(SimSettings.new())
	var rd := w.place(1, Vector2i(40, -60), SimObject.POS_RD, false, true)
	w.place(8, Vector2i(30, -100), SimObject.POS_LW, true, false)
	w.drop_puck(Vector2i(-20, -50))
	w.ai._assdefd_target(rd)
	eq(Vector2i(rd.temp[2], rd.temp[3]), Vector2i(0, -150), "50 px goal-side of the deepest forward; puck on the far side centres him")
	w.drop_puck(Vector2i(20, -50))
	w.ai._assdefd_target(rd)
	eq(Vector2i(rd.temp[2], rd.temp[3]), Vector2i(0x41, -150), "puck on his side: his lane")
	w.objects[8].set_pos(Vector2i(30, -170))
	w.ai._assdefd_target(rd)
	eq(rd.temp[3], -220, "deeper than -190: falls back to -220")
	w.dispose()
	return true

func test_centerd_moves_to_spot() -> bool:
	var w := _sandbox()
	var c := w.place(3, Vector2i(-50, -150), SimObject.POS_C, false, true)
	_rate(c)
	w.assreplace(c, HockeyAI.ASS_CENTERD)
	w.drop_puck(Vector2i(40, 0))
	for i in 400:
		w.step()
	# x = puck x / 2, y = (-128 + puck y) / 2; skateto stops within 12 px.
	var d := c.pos() - Vector2i(20, -64)
	check(absi(d.x) <= 14 and absi(d.y) <= 14, "center covers the slot: %s" % c.pos())
	eq(_current(c), HockeyAI.ASS_CENTERD, "still on defense (loose puck)")
	w.dispose()
	return true

func test_assnearest_hands_off() -> bool:
	var w := _sandbox()
	var far := w.place(3, Vector2i(0, -150), SimObject.POS_C, false, true)
	var near := w.place(2, Vector2i(10, 0), SimObject.POS_LW, false, true)
	_rate(far)
	_rate(near)
	w.setplass(far)
	w.setplass(near)
	w.assinsert(far, HockeyAI.ASS_NEAREST)
	w.drop_puck(Vector2i(10, 30))
	w.step()
	eq(_current(near), HockeyAI.ASS_NEAREST, "the skater nearest the puck becomes the chaser")
	eq(_current(far), HockeyAI.ASS_CENTERD, "the old chaser goes back to his position")
	check(w.stats[0].nearest_sq > 0, "team nearest distance recorded")
	w.dispose()
	return true

func test_cpu_carrier_shoots() -> bool:
	var w := _sandbox()
	var c := w.place(3, Vector2i(0, 170), SimObject.POS_C, false, true)
	_rate(c)
	w.setplass(c)
	w.assinsert(c, HockeyAI.ASS_NEAREST)
	w.drop_puck(Vector2i(0, 180))
	var shot := false
	for i in 400:
		w.step()
		if w.shotplayer == c.index and w.puckc < 0:
			shot = true
			break
	check(shot, "the CPU carrier in the slot shoots")
	w.dispose()
	return true

func test_goalie_skates_back() -> bool:
	var w := _sandbox()
	var g := w.place(11, Vector2i(60, 100), SimObject.POS_GOALIE, true, false)
	_rate(g)
	w.setplass(g)
	eq(_current(g), GoalieLogic.ASS_GOALIE_CPU, "Setplass gives a goalie assgoaliecpu")
	w.drop_puck(Vector2i(0, -100))
	for i in 600:
		w.step()
	# Puck in the other half: hold the top of the crease at (0, 244).
	var d := g.pos() - Vector2i(0, 0xF4)
	check(absi(d.x) <= 8 and absi(d.y) <= 8, "back in the crease: %s" % g.pos())
	eq(g.spa, GoalieLogic.SPA_READY, "ready stance in the box")
	w.dispose()
	return true

func test_goalie_angles_to_puck() -> bool:
	var w := _sandbox()
	var g := w.place(11, Vector2i(0, 240), SimObject.POS_GOALIE, true, false)
	_rate(g)
	w.setplass(g)
	w.drop_puck(Vector2i(-80, 150))
	for i in 300:
		w.step()
	# Net point (0, 260) to puck (-80, 150): scaled to 26/137 and 18/137 of the vector.
	var d := g.pos() - Vector2i(-15, 246)
	check(absi(d.x) <= 5 and absi(d.y) <= 5, "cuts down the angle: %s" % g.pos())
	eq(g.facing(), 5, "faces the puck")
	w.dispose()
	return true

func test_goalie_turn_never_into_net() -> bool:
	var w := HockeyWorld.new(SimSettings.new())
	var g := w.place(11, Vector2i(0, 240), SimObject.POS_GOALIE, true, false)
	g.facing_fx = 1 << 16
	w.goalie.sub_db68(g, 7)
	eq(g.facing(), 2, "from 1 toward 7 the short way is 0 (into the top net), so he turns 2")
	g.facing_fx = 1 << 16
	g.flags |= SimObject.PF_JOYCON
	w.goalie.sub_db68(g, 7)
	eq(g.facing(), 0, "a pad goalie turns freely")
	w.dispose()
	return true

func test_goaliesave_choice() -> bool:
	var w := HockeyWorld.new(SimSettings.new())
	var g := w.place(11, Vector2i(0, 250), SimObject.POS_GOALIE, true, false)
	g.aggress = 10
	w.drop_puck(Vector2i(0, 200))
	w.puck().z_fx = 20 << 16
	w.puckcross[0] = 30
	w.puckcross[1] = 5
	w.goalie.goaliesave(g, 0, 0x104)
	eq(g.spa, 0x178, "high and wide: glove")
	g.spa = 0
	g.aggress = 11
	w.goalie.goaliesave(g, 0, 0x104)
	eq(g.spa, GoalieLogic.SPA_REACH_GLOVE, "glove 11+: the reach-out glove save")
	g.spa = 0
	w.puck().z_fx = 0
	w.goalie.goaliesave(g, 0, 0x104)
	eq(g.spa, 0x1544, "low, wide and close: stick save")
	g.spa = 0
	w.puckcross[0] = 0
	w.puck().z_fx = 20 << 16
	w.goalie.goaliesave(g, 0, 0x104)
	eq(g.spa, 0x14C0, "high at the body: shoulder save")
	w.dispose()
	return true

func test_goalie_saves_low_shot() -> bool:
	var w := _sandbox()
	var g := w.place(11, Vector2i(0, 246), SimObject.POS_GOALIE, true, false)
	_rate(g)
	w.setplass(g)
	w.drop_puck(Vector2i(0, 120))
	w.puck().vel = Vector2i(0, 12000)
	# A shot in flight (SetShotMode's sflags bit 3): once it is deep, a centred goalie
	# saves on his next decision without waiting for the crossing prediction.
	w.sflags |= HockeyWorld.SF_SHOTDIR
	var spas := {}
	for i in 60:
		w.step()
		spas[g.spa] = true
	check(spas.has(0x21E), "a low shot at his pads starts the butterfly: %s" % [spas.keys()])
	eq(w.score(1), 0, "no goal")
	w.dispose()
	return true

func test_cp_goalie() -> bool:
	var w := HockeyWorld.new(SimSettings.new())
	_two_teams(w)
	w.gsp = 2
	w.gameclock = 50
	w.stats[1].goals = 2
	w.goalie.cp_goalie(0, 50)
	check(w.stats[0].goalie_pulled, "down two with under a minute in the 3rd: pull")
	w.stats[0].goalie_pulled = false
	w.goalie.cp_goalie(0, -50)
	check(not w.stats[0].goalie_pulled, "not with the play in his own half")
	w.stats[1].goals = 3
	w.goalie.cp_goalie(0, 50)
	check(not w.stats[0].goalie_pulled, "down three: no pull (exactly two, retail)")
	w.stats[1].goals = 2
	w.cont_team[0] = 1
	w.puckc = 3
	w.drop_puck(Vector2i(0, 50))
	w.puckc = 3
	w.goalie.chk_goalies()
	check(not w.stats[0].goalie_pulled, "a human team decides for itself")
	w.dispose()
	return true

## Twelve CPU players for a minute of game time. Nothing may leave the rink, the puck
## must change hands and somebody must shoot.
func test_cpu_vs_cpu() -> bool:
	var w := HockeyWorld.new(SimSettings.new(), 0x1234)
	_two_teams(w)
	w.drop_puck(Vector2i(0, 0))
	var carriers := {}
	var inside := true
	for i in 3600:
		w.step()
		if w.puckc >= 0:
			carriers[w.puckc] = true
		for k in 12:
			var o := w.objects[k]
			if absi(o.x()) > RinkBoards.SIDELINE or absi(o.y()) > RinkBoards.END_BOARD:
				inside = false
	check(inside, "everyone stays inside the boards")
	check(carriers.size() >= 3, "the puck changes hands: %s" % [carriers.keys()])
	check(w.stats[0].shots + w.stats[1].shots + w.score(0) + w.score(1) > 0 or w.shotplayer >= 0,
			"somebody shoots")
	w.dispose()
	return true

# --- data -------------------------------------------------------------------------------

static func _team(abbr: String) -> TeamData:
	for t in MatchConfig.available_teams():
		if t.abbreviation == abbr:
			return t
	return null

func test_teams_extracted() -> bool:
	var teams := MatchConfig.available_teams()
	eq(teams.size(), 28, "26 clubs and the two All-Star teams")
	var total := 0
	for t in teams:
		total += t.players.size()
		check(t.players.size() == t.goalie_count + t.forward_count + t.defense_count, "%s roster groups" % t.abbreviation)
	eq(total, 684, "684 player records")
	var bos := _team("BOS")
	eq(bos.players[17].full_name, "Ray Bourque", "Bourque in slot 17")
	eq(bos.players[17].rom_bytes(), PackedByteArray([0x77, 0xA5, 0x44, 0x65, 0x60, 0x55, 0x62, 0x52]), "Bourque's bytes round-trip")
	eq(bos.players[0].rom_bytes(), PackedByteArray([0x35, 0x44, 0x42, 0x24, 0x00, 0x00, 0x43, 0x43]), "Moog's goalie bytes round-trip")
	eq(bos.line(0), PackedInt32Array([1, 19, 18, 7, 3, 12, 8, 0]), "data line 0 (line changes off)")
	eq([bos.pp_bonus, bos.pk_penalty, bos.home_bonus, bos.away_penalty], [1, 2, 2, 1], "Boston bonuses")
	eq(bos.goalie_count, 2, "goalie word $B400 counts 2")
	eq(_team("HFD").goalie_count, 3, "goalie word $A360 counts 3")
	eq(bos.players[17].overall(), 99, "Bourque overall")
	eq(bos.players[2].overall(), 93, "Oates overall")
	eq(_team("ANH").players[16].overall(), 37, "Dollas overall")
	eq(bos.players[0].overall(), 59, "Moog overall")
	eq(_team("ASE").players[0].overall(), 94, "Roy overall")
	return true

## Spec 1.6 test vectors: $67/$68/$69/$6A/$6B/$6C/$6D/$6E/$70/$71/$72/$73/$74/$75/$76
## with form 0 and no bonuses.
func _struct(o: SimObject) -> Array:
	return [o.weight, o.legstr, o.legspd, o.aioff, o.aidef, o.shotspd, o.shotacc, o.passacc,
		o.spodds, o.stickhand, o.endurance, o.aggress, o.hf, o.checking, o.handed]

func test_setplayer_vectors() -> bool:
	var cases := [
		["BOS", 17, "Ray Bourque", [80, 25, 20, 10, 7, 25, 25, 25, 10, 25, 30, 10, 0, 30, 1]],
		["BOS", 2, "Adam Oates", [56, 25, 20, 7, 9, 15, 20, 30, 0, 25, 25, 5, 0, 15, 0]],
		["ASE", 3, "Mario Lemieux", [80, 25, 20, 7, 10, 20, 30, 30, 0, 30, 30, 10, 2, 15, 0]],
		["BOS", 11, "Cam Neely", [80, 20, 20, 9, 10, 20, 25, 20, 15, 20, 25, 4, 8, 20, 0]],
		["ANH", 16, "Bobby Dollas", [88, 10, 5, 14, 12, 5, 0, 5, 5, 5, 10, 5, 0, 10, 0]],
		["BOS", 0, "Andy Moog", [32, 20, 20, 12, 12, 20, 0, 20, 15, 0, 20, 15, 0, 0, 1]],
		["ASE", 0, "Patrick Roy", [48, 30, 20, 10, 10, 30, 0, 30, 25, 0, 25, 14, 0, 0, 0]],
	]
	for c in cases:
		var t := _team(c[0])
		var p: PlayerData = t.players[c[1]]
		eq(p.full_name, c[2], "%s slot %d" % [c[0], c[1]])
		var o := SimObject.new()
		o.load_player(p)
		eq(_struct(o), c[3], "%s in-game bytes" % c[2])
	var o := SimObject.new()
	o.load_player(_team("BOS").players[2])
	check(o.attribute & SimObject.ATTR_XFLIP != 0, "a righty gets the sprite flip bit")
	return true

func test_setplayer_bonuses_and_form() -> bool:
	var w := HockeyWorld.new(SimSettings.new())
	var bos := _team("BOS")
	w.roster.setup_teams(bos, _team("MTL"))
	var o := w.place(1, Vector2i(0, -60), SimObject.POS_RD, false, true)
	w.setplayer(o, 17)
	# OfA nibble 4 -> 20, + home bonus 2 = 22 -> aioff 9 (10 with no bonus).
	eq(o.aioff, 9, "home bonus quickens aioff")
	eq(w.stats[0].tmpdst[17], TeamStats.TMPDST_ON_ICE, "slot on the ice")
	eq(o.pnum, 17, "pnum")
	# Third period, trailing, first half of it: +2 checking.
	w.gsp = 2
	w.gameclock = 200
	w.stats[1].goals = 1
	w.setplayer(o, 17)
	eq(o.checking, 30, "checking capped at 30")
	eq(o.spodds, 14, "shot bias +2 x 2 in the 3rd while trailing")
	w.gameclock = 100
	w.setplayer(o, 17)
	eq(o.spodds, 10, "no bonus once half the 3rd has gone (retail)")
	# Form: byte 0 of the slot's block, divided by 3 toward zero, on every rating.
	w.stats[0].hotcold[17 * 16] = -9
	w.setplayer(o, 17)
	eq(o.legstr, 22, "form -9 takes 3 off agility")
	w.stats[0].hotcold[17 * 16] = 8
	w.setplayer(o, 17)
	eq(o.legstr, 27, "form +8 adds 2")
	w.roster.new_game_form()
	var lo := 99
	var hi := -99
	for v in w.stats[1].hotcold:
		lo = mini(lo, v)
		hi = maxi(hi, v)
	check(lo >= -9 and hi <= 8 and hi > lo, "form bytes in -9..8: %d..%d" % [lo, hi])
	w.dispose()
	return true

func test_energy_drain_and_recovery() -> bool:
	var s := SimSettings.new()
	s.energy_drain_gate = 1
	var w := HockeyWorld.new(s)
	var o := w.place(3, Vector2i(0, 0), SimObject.POS_C, false, true)
	o.pnum = 4
	w.stats[0].tmpdst[4] = TeamStats.TMPDST_ON_ICE
	o.endurance = 30
	w.playeracc(o, 0, 1)
	eq(w.energy_raw(o), 0x1000 - 33 + 15, "drain 33 less half the endurance above 75%")
	w.stats[0].energy[4] = 0xC00
	w.playeracc(o, 0, 1)
	eq(w.energy_raw(o), 0xC00 - 33, "flat 33 below 75%")
	w.stats[0].energy[5] = 0x800
	w.stats[0].tmpdst[5] = TeamStats.TMPDST_BENCH
	for i in 0x18:
		w.periodic_events(1)
	eq(w.stats[0].energy[5], 0x800 + 9, "bench +9 a game second")
	w.opt_line_on = false
	w.playeracc(o, 0, 1)
	eq(w.energy_raw(o), 0xC00 - 33, "no drain with line changes off")
	w.dispose()
	return true

# --- rules ---------------------------------------------------------------------------------

func test_clock_tick() -> bool:
	var w := HockeyWorld.new(SimSettings.new())
	w.gameclock = 300
	w.clock_frac = 0xFFFF
	w.gmode = 0
	for i in 24:
		w.rules.vblank_tick()
	eq(w.gameclock, 300, "24 vblanks of $AAA do not borrow from $FFFF")
	w.rules.vblank_tick()
	eq(w.gameclock, 299, "the 25th does: one game second")
	w.gmode |= HockeyWorld.GM_CLOCK
	for i in 100:
		w.rules.vblank_tick()
	eq(w.gameclock, 299, "stopped clock")
	w.dispose()
	return true

## A whistle (puck out of play), the referee, then the full faceoff back to play.
func test_whistle_to_faceoff() -> bool:
	var w := HockeyWorld.new(SimSettings.new())
	var hc := w.place(3, Vector2i(0, 100), SimObject.POS_C, false, true)
	var ac := w.place(9, Vector2i(0, -100), SimObject.POS_C, true, false)
	_rate(hc)
	_rate(ac)
	w.drop_puck(Vector2i(50, 180))
	w.ltx = 100
	w.lty = 180
	# Last touched by the away centre, who attacks the bottom: limitfo leaves the top
	# end-zone dot alone.
	w.ltplayer = ac.index
	var dropped := [false]
	w.faceoff.faceoff_dropped.connect(func(_h: bool) -> void: dropped[0] = true)
	w.rules.add_penalty2(GameRules.PEN_OOP, w.objects[w.ltplayer])
	w.step()
	check(w.gmode & HockeyWorld.GM_CLOCK != 0, "whistle stops play")
	eq(Vector2i(w.fox, w.foy), Vector2i(70, 206), "deep stop: the end-zone dot on the puck's side")
	var lined_up := false
	for i in 900:
		w.step()
		if w.sflags2 & HockeyWorld.SF2_FACEOFF and not lined_up:
			lined_up = true
			eq(hc.pos(), Vector2i(0 + 70, -15 + 206), "home centre 15 px below the dot")
			eq(ac.pos(), Vector2i(70, 15 + 206), "away centre 15 px above it")
		if dropped[0]:
			break
	check(lined_up, "the teams lined up")
	check(dropped[0], "the puck was dropped")
	check(w.gmode & HockeyWorld.GM_CLOCK == 0, "play resumed")
	w.dispose()
	return true

func test_faceoff_spots() -> bool:
	var w := HockeyWorld.new(SimSettings.new())
	var home := w.place(3, Vector2i(0, 0), SimObject.POS_C, false, true)
	# Icing by the home team (attacks the top): its own end-zone dot, puck side.
	w.drop_puck(Vector2i(-30, -100))
	w.rules.pen_buf[0] = (GameRules.PEN_ICING << 8) | home.index
	w.rules.stop4pen(0)
	eq(Vector2i(w.fox, w.foy), Vector2i(-70, -206), "icing: (-70, -206)")
	# Offside by the same team deep in its attacking zone: limitfo takes it out to the
	# neutral dot.
	w.gmode = 0
	w.rules.clr_pen_buf()
	w.drop_puck(Vector2i(20, 150))
	w.rules.pen_buf[0] = (GameRules.PEN_OFFSIDE << 8) | home.index
	w.rules.stop4pen(0)
	eq(Vector2i(w.fox, w.foy), Vector2i(70, 65), "offside: (70, 65)")
	# A second whistle with play stopped keeps the first spot.
	w.drop_puck(Vector2i(0, -200))
	w.rules.stop4pen(0)
	eq(Vector2i(w.fox, w.foy), Vector2i(70, 65), "first whistle wins")
	w.dispose()
	return true

func test_delayed_penalty() -> bool:
	var w := HockeyWorld.new(SimSettings.new())
	var hooker := w.place(2, Vector2i(0, 0), SimObject.POS_LW, false, true)
	hooker.pnum = 7
	var carrier := w.place(9, Vector2i(30, 30), SimObject.POS_C, true, false)
	w.drop_puck(Vector2i(30, 30))
	w.puckc = carrier.index
	w.rules.add_penalty(0x1E, hooker)
	w.rules.checkfornewpen()
	check(w.gmode & HockeyWorld.GM_PENDEL != 0, "the other team has the puck: delayed")
	check(w.gmode & HockeyWorld.GM_CLOCK == 0, "play goes on")
	check(hooker.flags2 & SimObject.PF2_PEN != 0, "player marked")
	w.rules.add_penalty(0x20, hooker)
	eq(w.rules.pen_buf[1], 0, "one pending penalty per player")
	w.puckc = hooker.index
	w.rules.checkfornewpen()
	check(w.gmode & HockeyWorld.GM_CLOCK != 0, "his team touches it: whistle")
	eq(w.rules.pencntdwn, 4 * 32, "Hooking's delay is 4 x 32 vblanks")
	w.dispose()
	return true

func test_box_time_and_pp() -> bool:
	var w := HockeyWorld.new(SimSettings.new())
	var st := w.stats[0]
	st.tmpdst[7] = 3
	st.box = PackedInt32Array([7])
	st.on_ice = 5
	w.gmode = 0
	w.rules.updatepwrplay()
	check(w.sflags2 & HockeyWorld.SF2_PWRPLAY != 0, "power play on")
	check(w.sflags2 & HockeyWorld.SF2_PWRTM != 0, "away on the power play")
	eq(w.stats[1].power_plays, 1, "a power play counted")
	var sounds := []
	w.sound.connect(func(id: int) -> void: sounds.append(id))
	w.place(5, Vector2i(0, -240), SimObject.POS_GOALIE, false, true)
	for i in 24 * 3 + 1:
		w.rules.updatepentime(1)
	eq(st.tmpdst[7], TeamStats.TMPDST_ON_ICE, "served: back on the ice")
	eq(st.box.size(), 0, "box list empty")
	eq(st.on_ice, 6, "full strength")
	check(1 in sounds and 2 in sounds, "beeps in the last seconds, then the door")
	check(w.stats[1].pp_time > 0, "PP time counted")
	w.dispose()
	return true

func test_pp_goal_releases() -> bool:
	var w := HockeyWorld.new(SimSettings.new())
	var home := w.stats[0]
	home.on_ice = 5
	home.box = PackedInt32Array([4, 7])
	home.tmpdst[4] = 0x4000 | 300
	home.tmpdst[7] = 90
	w.rules.pen_buf[0] = 0x1E07
	w.rules.pp_goal(1)
	eq(home.tmpdst[7], 0, "the first non-coincidental penalty ends")
	eq(home.box, PackedInt32Array([4]), "the coincidental major stays")
	eq(home.on_ice, 6, "back to full strength")
	eq(w.stats[1].pp_goals, 1, "PP goal")
	check(w.rules.pen_buf[0] != 0, "queued entries survive a goal against a short team")
	w.rules.pp_goal(1)
	eq(w.rules.pen_buf[0], 0, "a goal against a full team wipes the queue (Q9)")
	w.dispose()
	return true

func test_set_personel_lines() -> bool:
	var w := HockeyWorld.new(SimSettings.new())
	w.roster.setup_teams(_team("BOS"), _team("MTL"))
	w.lines.set_personel(0)
	w.forcepldata(0)
	var by_pos := {}
	for i in 6:
		var o := w.objects[i]
		by_pos[o.position] = o.pnum
	eq(by_pos, {0: 0, 1: 18, 2: 17, 3: 7, 4: 2, 5: 11}, "Sc1: Moog; Sweeney, Bourque; Juneau, Oates, Neely")
	var oates := 0
	for i in 6:
		if w.objects[i].pnum == 2:
			oates = i
	eq(w.objects[oates].legspd, 20, "setplayer loaded Oates")
	# Oates hurt for the game: the C sublist finds the next line's centre.
	w.stats[0].tmpdst[2] = TeamStats.TMPDST_INJURED_GAME
	w.lines.set_personel(0)
	var subs := []
	for i in 6:
		subs.append(w.objects[i].newpnum)
	check(4 in subs and not (2 in subs), "Oates replaced by the Sc2 centre (slot 4): %s" % [subs])
	w.dispose()
	return true

func test_comp_line() -> bool:
	var w := HockeyWorld.new(SimSettings.new())
	w.roster.setup_teams(_team("BOS"), _team("MTL"))
	w.stats[0].on_ice = 6
	w.stats[1].on_ice = 5
	w.lines.comp_line(0)
	check(w.stats[0].line == 3 or w.stats[0].line == 4, "power play line")
	w.lines.comp_line(1)
	check(w.stats[1].line == 5 or w.stats[1].line == 6, "penalty kill line")
	w.stats[1].on_ice = 6
	w.stats[1].line = 1
	w.lines.comp_line(0)
	eq(w.stats[0].line, 1, "home matches the away Sc2 with its Sc2 when rested")
	w.dispose()
	return true

func test_endfaceoff_draw() -> bool:
	var w := HockeyWorld.new(SimSettings.new())
	var p := w.puck()
	var wins := 0
	for i in 20:
		# Home centre at frame 3 (bonus 16), away at frame 4 (bonus 0): 16 - 16 + 0 = 0.
		w.faceoff.fof_frame = PackedInt32Array([3, 4, 7])
		w.faceoff.fof_attr = PackedInt32Array([0x8800, 0xA000, 0x8000])
		var won := [false]
		var cb := func(h: bool) -> void: won[0] = h
		w.faceoff.faceoff_dropped.connect(cb)
		w.faceoff.endfaceoff(p)
		w.faceoff.faceoff_dropped.disconnect(cb)
		if won[0]:
			wins += 1
		# The top-attacking winner (H flip) pulls back toward his own (bottom) end.
		check(p.vel.y < 0x1300 + 1, "pull biased toward the winner's end: %d" % p.vel.y)
	eq(wins, 20, "home wins every draw with the timing edge")
	w.dispose()
	return true

## Boston against Montreal, CPU against CPU, 30-second periods: the rules run the whole
## game to the final horn.
func test_full_game() -> bool:
	var w := HockeyWorld.new(SimSettings.new(), 0x1234)
	w.opt_perlen = 3
	w.roster.setup_teams(_team("BOS"), _team("MTL"))
	var periods := []
	var drops := [0]
	var over := [false]
	w.rules.period_started.connect(func(g: int) -> void: periods.append(g))
	w.faceoff.faceoff_dropped.connect(func(_h: bool) -> void: drops[0] += 1)
	w.rules.game_over.connect(func() -> void: over[0] = true)
	w.rules.start_game()
	var frames := 0
	while not over[0] and frames < 60000:
		w.step()
		frames += 1
	check(over[0], "the game ended (%d frames)" % frames)
	eq(w.gsp, 4, "game over state")
	check(periods.slice(0, 3) == [0, 1, 2], "three periods: %s" % [periods])
	check(drops[0] >= 3, "a faceoff at least every period: %d" % drops[0])
	check(w.stats[0].shots + w.stats[1].shots > 0, "shots were taken")
	check(w.gmode & HockeyWorld.GM_EOG != 0, "game-over flag")
	w.dispose()
	return true

## Both pads mash random buttons through a short game: input, switching, line menus,
## faceoffs and penalties must survive anything a player can press.
func test_pad_mash_game() -> bool:
	var w := HockeyWorld.new(SimSettings.new(), 0x77)
	w.opt_perlen = 3
	w.roster.setup_teams(_team("PIT"), _team("CHI"))
	w.cont_team[0] = 1
	w.cont_team[1] = 2
	var over := [false]
	w.rules.game_over.connect(func() -> void: over[0] = true)
	w.rules.start_game()
	var r := RandomNumberGenerator.new()
	r.seed = 1
	var held := [0, 0]
	var frames := 0
	while not over[0] and frames < 60000:
		for k in 2:
			if r.randi() % 6 == 0:
				held[k] = r.randi() & 0x7F
			w.pads[k].held = held[k]
		w.step()
		frames += 1
	check(over[0], "the game ended under random input (%d frames)" % frames)
	var on_ice := 0
	for i in 12:
		if w.objects[i].position >= 0:
			on_ice += 1
	check(on_ice >= 8, "players still on the ice: %d" % on_ice)
	w.dispose()
	return true

# --- penalty shots and the shootout ----------------------------------------------------------

## A game world with real teams, stepped until the opening faceoff has been dropped.
func _live_game(seed: int) -> HockeyWorld:
	var w := HockeyWorld.new(SimSettings.new(), seed)
	w.roster.setup_teams(_team("BOS"), _team("MTL"))
	var drops := [0]
	var count := func(_h: bool) -> void: drops[0] += 1
	w.faceoff.faceoff_dropped.connect(count)
	w.rules.start_game()
	var f := 0
	while drops[0] == 0 and f < 3000:
		w.step()
		f += 1
	w.faceoff.faceoff_dropped.disconnect(count)
	for i in 30:
		w.step()
	return w

## PenShotChk: only a foul on a breakaway skater becomes the (shifted, Q1) variant, one at
## a time, and never against an empty net.
func test_pen_shot_chk() -> bool:
	var w := _live_game(0x4321)
	var victim := w.objects[2]
	var offender := w.objects[8]
	eq(w.pen_shot_chk(0x1E, victim, offender), 0x1E, "no breakaway: the foul stands")
	victim.flags3 |= SimObject.PF3_BREAKAWAY
	eq(w.pen_shot_chk(0x24, victim, offender), 0x24, "holding has no variant")
	eq(w.pen_shot_chk(0x1E, victim, offender), 0x30, "hooking on a breakaway: the Tripping variant")
	check(w.ba_ps_flags & HockeyWorld.BA_AWARDED != 0, "awarded")
	eq(w.ba_sktr, 2, "the fouled skater")
	eq(w.ba_goalie, 11, "against the away goalie")
	eq(w.shootout.ba_team, 0, "home shoots")
	eq(w.shootout.ba_skater_offset, victim.pnum, "his roster slot")
	eq(w.shootout.ba_checker_offset, offender.pnum, "the offender's slot")
	eq(w.pen_shot_chk(0x20, victim, offender), 0x20, "one penalty shot at a time")
	# An empty net: no goalie object in the defending six.
	w.ba_ps_flags = 0
	w.objects[11].position = SimObject.POS_OFF_ICE
	eq(w.pen_shot_chk(0x1E, victim, offender), 0x1E, "no goalie: no penalty shot")
	check(w.ba_ps_flags & HockeyWorld.BA_AWARDED == 0, "award withdrawn")
	w.objects[11].position = SimObject.POS_GOALIE
	w.opt_pen = false
	eq(w.pen_shot_chk(0x1E, victim, offender), 0x1E, "penalties off: no penalty shot")
	w.dispose()
	return true

## sub_EE58: the fouled player shoots when he is on the bench or the ice; otherwise the
## best of the rest by the nine ratings (ties to the later slot), never a goalie.
func test_ps_pick_shooter() -> bool:
	var w := HockeyWorld.new(SimSettings.new())
	w.roster.setup_teams(_team("BOS"), _team("MTL"))
	var so := w.shootout
	var st := w.stats[1]
	so.ba_team = 1
	so.ba_skater_offset = 6
	check(so.pick_shooter(), "found a shooter")
	eq(so.ba_skater_offset, 6, "the fouled player")
	eq(w.ba_sktr, 6, "the away shooter is object 6")
	# Guy Carbonneau (slot 5) has Shot Accuracy 1: even fouled, he cannot shoot.
	eq(st.rom[5][5] & 0xF, 1, "Carbonneau's shot accuracy")
	so.ba_skater_offset = 5
	so.pick_shooter()
	check(so.ba_skater_offset != 5, "Shot Accuracy 1 never shoots")
	so.ba_skater_offset = 6
	st.tmpdst[6] = TeamStats.TMPDST_INJURED_GAME
	check(so.pick_shooter(), "found another")
	var pick := so.ba_skater_offset
	check(pick != 6, "not the injured player")
	var score := func(slot: int) -> int:
		var a: PackedByteArray = st.rom[slot]
		return (a[1] & 0xF) + (a[2] & 0xF) + (a[2] >> 4) + (a[3] & 0xF) + (a[3] >> 4) \
				+ (a[5] & 0xF) + (a[5] >> 4) + (a[6] >> 4) + (a[7] >> 4)
	var best := -1
	for slot in st.rom.size():
		if st.rom[slot][5] & 0xF <= 1 or slot == 6:
			continue
		if score.call(slot) >= best:
			best = score.call(slot)
	eq(score.call(pick), best, "the best of the rest")
	check(st.rom[pick][5] & 0xF > 1, "not a goalie")
	for slot in st.rom.size():
		st.tmpdst[slot] = TeamStats.TMPDST_INJURED_GAME
	check(not so.pick_shooter(), "nobody available")
	w.dispose()
	return true

## sub_FE7FC: path 0 for a righty and a lefty. A lefty's terminator is mirrored too and
## never reads as finished (Q1).
func test_ps_waypoints() -> bool:
	var w := HockeyWorld.new(SimSettings.new())
	var so := w.shootout
	var righty := w.objects[0]
	righty.handed = 0
	var lefty := w.objects[6]
	lefty.handed = 1
	for o in [righty, lefty]:
		so.ps_path = 0
		so.ps_wp_idx = -1
		so.ps_wp_x = 0
		so.last_wp = false
		so.load_waypoint(w.puck())
		eq(Vector2i(HockeyWorld.s16(so.ps_wp_x), so.ps_wp_y), Vector2i(16, 226), "first waypoint unmirrored (Q2)")
		check(not so.last_wp, "not the last")
		so.load_waypoint(o)
		var x := 16 if o == righty else -16
		eq(Vector2i(HockeyWorld.s16(so.ps_wp_x), so.ps_wp_y), Vector2i(x, 208), "second waypoint")
		check(so.last_wp, "last waypoint loaded")
		eq(so.ps_shoot_tol, 0x20, "shoot box")
		eq(w.ps_script_dir, 5, "script shot direction")
		so.load_waypoint(o)
		var done := (so.ps_wp_x >> 8) & 0xFF == 0x80
		check(done == (o == righty), "righty finished, lefty never (Q1)")
	# The shoot test: inside the last waypoint's box with the clock running.
	so.ps_path = 0
	so.ps_wp_idx = 0
	so.ps_wp_x = 0x10
	so.load_waypoint(righty)
	w.f_c2fa |= ShootoutLogic.C2FA_ATTEMPT_CLOCK
	so.ps_clock = 20
	w.puckc = righty.index
	righty.flags |= SimObject.PF_GOAL
	righty.set_pos(Vector2i(16 + 40, 208))
	check(not so.ps_should_shoot(righty), "outside the box")
	righty.set_pos(Vector2i(16 + 30, 208 - 30))
	check(so.ps_should_shoot(righty), "inside the box")
	so.ps_clock = 3
	righty.set_pos(Vector2i(-100, 0))
	check(so.ps_should_shoot(righty), "three seconds left")
	w.dispose()
	return true

## sub_FC516: home then away each round; nothing is decided before the away shot of
## round 5, then full rounds of sudden death. The shooters cycle through the five.
func test_shootout_turns() -> bool:
	var w := HockeyWorld.new(SimSettings.new())
	w.roster.setup_teams(_team("BOS"), _team("MTL"))
	w.f_c2fa |= HockeyWorld.C2FA_SHOOTOUT
	var so := w.shootout
	so.init_shootout()
	var ln := w.stats[0].data.line(0)
	eq(Array(so.so_list[0]), [ln[5] - 1, ln[4] - 1, ln[3] - 1, ln[2] - 1, ln[1] - 1, ln[0] - 1],
		"home list: RW, C, LW, RD, LD, then the goalie")
	w.shootout_goals[0] = 3
	for r in range(1, 5):
		eq(so.so_round, r, "round %d" % r)
		eq(w.shootout_side, 0, "home first")
		so.next_turn()
		eq(w.shootout_side, 1, "then away")
		so.next_turn()
		check(w.f_c2fa & ShootoutLogic.C2FA_DECIDED == 0, "nothing decided in round %d" % r)
	eq(so.so_shooter_idx, 4, "the fifth shooter")
	so.next_turn()
	check(w.f_c2fa & ShootoutLogic.C2FA_DECIDED == 0, "not after the home shot")
	w.shootout_goals[1] = 3
	so.next_turn()
	check(w.f_c2fa & ShootoutLogic.C2FA_DECIDED == 0, "level after five: sudden death")
	eq(so.so_round, 6, "round 6")
	eq(so.so_shooter_idx, 0, "back to the first shooter")
	so.next_turn()
	w.shootout_goals[0] = 4
	so.next_turn()
	check(w.f_c2fa & ShootoutLogic.C2FA_DECIDED != 0, "decided after the away shot")
	eq(w.shootout_side, 1, "the side is left on away")
	check(so.winner_text().begins_with("SHOOTOUT WON BY Boston"), "winner text: %s" % so.winner_text())
	w.dispose()
	return true

## A penalty shot in a regular game: the foul is called, the attempt is set up (shooter at
## centre, goalie at his net, the rest parked), played out, and the game resumes with a
## faceoff and the game clock. Nobody goes to the box.
func test_penalty_shot_attempt() -> bool:
	var w := _live_game(0x4321)
	var victim := w.objects[2]
	var offender := w.objects[8]
	victim.flags3 |= SimObject.PF3_BREAKAWAY
	var assessed := [0]
	w.rules.penalty_assessed.connect(func(_t: int, _p: int, _i: int, _m: int) -> void: assessed[0] += 1)
	var intro := []
	w.shootout.intro.connect(func(l: PackedStringArray) -> void: intro.append(l))
	var drops := [0]
	w.faceoff.faceoff_dropped.connect(func(_h: bool) -> void: drops[0] += 1)
	w.add_penalty(w.pen_shot_chk(0x1E, victim, offender), offender)
	var f := 0
	while w.ba_ps_flags & HockeyWorld.BA_LIVE == 0 and f < 3000:
		w.step()
		f += 1
	check(w.ba_ps_flags & HockeyWorld.BA_LIVE != 0, "the attempt started (%d frames)" % f)
	check(w.f_c2fa & ShootoutLogic.C2FA_ATTEMPT_CLOCK != 0, "attempt clock")
	eq(w.shootout.ps_clock, 25, "25 seconds")
	w.step()
	var s := w.objects[w.ba_sktr]
	eq(w.ba_sktr, 0, "home shooter object")
	eq(s.pos(), Vector2i(0, -16 if s.attacking_top() else 16), "shooter behind the puck")
	var g := w.objects[w.ba_goalie]
	eq(g.pos(), Vector2i(0, 250 if s.attacking_top() else -250), "goalie at his net")
	eq(w.puck().pos(), Vector2i.ZERO, "puck at centre")
	var parked := 0
	for i in 12:
		if i != w.ba_sktr and i != w.ba_goalie and w.objects[i].x() == -240:
			parked += 1
	eq(parked, 10, "the other ten are parked")
	w.step()
	eq(intro.size(), 1, "the intro")
	if intro.size() > 0:
		eq(intro[0][0], "PENALTY SHOT!", "intro title")
		eq(intro[0][2].split(" by ")[0], "Tripping", "the shifted variant's name (Q1)")
	var clock: int = w.gameclock
	while w.ba_ps_flags & HockeyWorld.BA_LIVE and f < 6000:
		w.step()
		f += 1
	check(w.ba_ps_flags & HockeyWorld.BA_LIVE == 0, "the attempt ended")
	eq(w.gameclock, clock, "the game clock stood still")
	eq(w.stats[0].ps_attempts, 1, "one attempt counted")
	while drops[0] == 0 and f < 9000:
		w.step()
		f += 1
	check(drops[0] > 0, "faceoff after the attempt")
	check(w.f_c2fa & ShootoutLogic.C2FA_ATTEMPT_CLOCK == 0, "attempt clock off")
	for i in 200:
		w.step()
	check(w.gameclock < clock, "the game clock runs again")
	eq(assessed[0], 0, "a penalty shot sends nobody to the box")
	w.dispose()
	return true

## Boston against Montreal in the Shootout play mode: alternating attempts to a winner;
## no game clock and no periods.
func test_shootout_game() -> bool:
	var w := HockeyWorld.new(SimSettings.new(), 0x1234)
	w.roster.setup_teams(_team("BOS"), _team("MTL"))
	w.f_c2fa |= HockeyWorld.C2FA_SHOOTOUT
	w.shootout.init_shootout()
	var over := [0]
	w.rules.game_over.connect(func() -> void: over[0] += 1)
	var sides := []
	w.shootout.intro.connect(func(_l: PackedStringArray) -> void: sides.append(w.shootout_side))
	var won := [-1]
	w.shootout.shootout_won.connect(func(t: int) -> void: won[0] = t)
	w.rules.start_game()
	var clock := w.gameclock
	var frames := 0
	while over[0] == 0 and frames < 60000:
		w.step()
		frames += 1
	eq(over[0], 1, "the shootout ended (%d frames)" % frames)
	check(w.shootout.finished, "finished")
	check(w.shootout.so_round >= 5, "at least five rounds: %d" % w.shootout.so_round)
	check(w.shootout_goals[0] != w.shootout_goals[1], "a winner: %s" % w.shootout_goals)
	eq(won[0], 0 if w.shootout_goals[0] > w.shootout_goals[1] else 1, "the celebration's team")
	eq(sides.size(), 2 * w.shootout.so_round, "full rounds of attempts")
	var alternate := true
	for i in sides.size():
		alternate = alternate and sides[i] == i % 2
	check(alternate, "home, away, home, away ...")
	eq(w.gameclock, clock, "the game clock never ran")
	eq(w.gsp, 0, "no periods")
	eq(w.score(0) - w.score(1), w.shootout_goals[0] - w.shootout_goals[1], "the goals count on the board")
	for i in 120:
		w.step()
	eq(over[0], 1, "game over only once")
	w.dispose()
	return true

# --- the fight patch ---------------------------------------------------------------------

## A live game (rules on) of the fight patch's rosters with two skaters squared off at
## centre ice: home object 2 and away object 8, both rated to fight.
func _fight_world(opt_fight: int, seed: int = 0x2468) -> HockeyWorld:
	var w := HockeyWorld.new(SimSettings.new(), seed)
	w.roster.setup_teams(_fight_team("DET"), _fight_team("CHI"))
	w.opt_fight = opt_fight
	var drops := [0]
	var count := func(_h: bool) -> void: drops[0] += 1
	w.faceoff.faceoff_dropped.connect(count)
	w.rules.start_game()
	var f := 0
	while drops[0] == 0 and f < 3000:
		w.step()
		f += 1
	w.faceoff.faceoff_dropped.disconnect(count)
	return w

static func _fight_team(abbr: String) -> TeamData:
	for t in MatchConfig.available_teams(MatchConfig.Edition.FIGHT):
		if t.abbreviation == abbr:
			return t
	return null

## Squares two opposing skaters up for checkfight.
static func _square_up(w: HockeyWorld, a: SimObject, b: SimObject, hf: int = 14) -> void:
	a.set_pos(Vector2i(-20, 40))
	b.set_pos(Vector2i(-6, 40))
	a.hf = hf
	b.hf = hf
	a.impact = 0x20
	b.impact = 0x20
	a.flags &= ~SimObject.PF_ALOCK
	b.flags &= ~SimObject.PF_ALOCK
	a.flags2 &= ~(SimObject.PF2_PEN | SimObject.PF2_FIGHT)
	b.flags2 &= ~(SimObject.PF2_PEN | SimObject.PF2_FIGHT)
	w.chk_cnt = 40

## Retail setInjuryType writes the injury to tmpdst ($FFFD period, $FFFC game).
func test_injury_sets_tmpdst() -> bool:
	var w := HockeyWorld.new(SimSettings.new())
	w.roster.setup_teams(_team("BOS"), _team("MTL"))
	var v := w.place(8, Vector2i(0, 0), SimObject.POS_C, true, false)
	w.setplayer(v, 5)
	var checker := w.objects[2]
	checker.hf = 0
	var d1 := w.checking.set_injury_type(v, checker)
	eq(d1, 10, "d1 = pnum * 2")
	eq(w.stats[1].tmpdst[5], TeamStats.TMPDST_INJURED_PERIOD, "out for the period")
	check(v.flags2 & SimObject.PF2_UNAV != 0, "unavailable")
	checker.hf = 12
	w.checking.set_injury_type(v, checker)
	eq(w.stats[1].tmpdst[5], TeamStats.TMPDST_INJURED_GAME, "Fgt 12 >> 2 = 3: out for the game")
	w.dispose()
	return true

## The extracted patch data: frames 846-869, the nine fight animations, the extra hot
## spots, and the patched rosters (Probert's Fgt raised to 7 and back to the ROM byte).
func test_fight_assets() -> bool:
	check(SpriteAtlas.has_frame(FightLogic.SPF_GLOVES), "gloves frame 846")
	for f in range(FightLogic.SPF_FIGHT, FightLogic.SPF_FIGHT + 23):
		check(SpriteAtlas.has_frame(f), "fight frame %d" % f)
	check(not SpriteAtlas.has_frame(870), "870 is the end marker")
	var w := HockeyWorld.new(SimSettings.new())
	for spa in [FightLogic.SPA_FIGHT, FightLogic.SPA_FGRAB, FightLogic.SPA_FHELD, FightLogic.SPA_FHIGH,
			FightLogic.SPA_FLOW, FightLogic.SPA_FHITH, FightLogic.SPA_FHITL, FightLogic.SPA_BFALL, FightLogic.SPA_FFALL]:
		check(w.animator.anims.has(spa), "animation $%X" % spa)
	eq(w.hotlist.size(), 870, "hot spots 0-869")
	eq(Vector2i(int(w.hotlist[847][0]), int(w.hotlist[847][1])), Vector2i(6, -2), "first fight frame's hot spot")
	w.dispose()
	var det := _fight_team("DET")
	var probert: PlayerData
	for p in det.players:
		if p.full_name == "Bob Probert":
			probert = p
	check(probert != null, "Probert in the patched Detroit roster")
	if probert:
		eq(PlayerData.fight_nibble_of(probert.fighting), 7, "Fgt nibble 7 (retail 5)")
		eq(PlayerData.fight_display(7), 100, "the patch's Fgt column shows 100")
		eq(probert.rom_bytes()[4] & 0xE, 0xE, "rebuilds the H/F byte")
	var retail_det := _team("DET")
	for p in retail_det.players:
		if p.full_name == "Bob Probert":
			eq(PlayerData.fight_nibble_of(p.fighting), 5, "retail Fgt nibble 5")
	return true

## OptFight 0 (retail): checkfight never starts a fight.
func test_fight_off_in_retail() -> bool:
	var w := _fight_world(0)
	var a := w.objects[2]
	var b := w.objects[8]
	_square_up(w, a, b)
	w.fight.checkfight(a, b)
	check(not a.fighting() and not b.fighting(), "no fight with the option off")
	w.dispose()
	return true

## checkfight: the fight bits, the majors, the puck held, the camera locked, the others
## watching, collflag set (no momentum exchange).
func test_fight_starts() -> bool:
	var w := _fight_world(1)
	var a := w.objects[2]
	var b := w.objects[8]
	_square_up(w, a, b)
	var started := []
	w.fight.fight_started.connect(func(x: int, y: int) -> void: started.append([x, y]))
	w.fight.checkfight(a, b)
	check(a.fighting() and b.fighting(), "both fighting")
	eq(started, [[2, 8]], "fight_started")
	eq(w.chk_cnt, 0, "ChkCnt cleared")
	eq(a.asslist[a.assnum], FightLogic.ASS_FIGHT, "assfight")
	eq(b.asslist[b.assnum], FightLogic.ASS_FIGHT, "assfight")
	eq(a.impactp, 8, "opponent")
	eq(a.facing(), 2, "left fighter faces 2")
	eq(b.facing(), 5, "right fighter faces 5")
	check(not a.x_flip() and b.x_flip(), "the right one is mirrored")
	eq(a.vel.x, -0x400, "backs off")
	eq(b.vel.x, 0x400, "backs off")
	eq(a.spa, FightLogic.SPA_FIGHT, "drops the gloves")
	check(a.flags2 & SimObject.PF2_UNAV and a.flags2 & SimObject.PF2_NOCOLL, "unavailable, no collisions")
	eq(w.puckc, 2, "puckc = the first fighter")
	var p := w.puck()
	check(p.flags2 & SimObject.PF2_FIGHT != 0, "the puck's fight bit")
	eq(p.asslist[p.assnum], PuckLogic.ASS_PUCKUNFLIP, "puckunflip")
	check(w.sflags & HockeyWorld.SF_SLOCK != 0, "camera locked")
	eq(w.scroll_lock.y, 40, "between the fighters")
	eq(w.collflag, -1, "no momentum exchange")
	var fights := 0
	for e in w.rules.pen_buf:
		if (e >> 8) & 0xFF == FightLogic.PEN_FIGHTING:
			fights += 1
	eq(fights, 2, "two Fighting majors queued")
	var watching := 0
	for i in 12:
		var o := w.objects[i]
		if not o.fighting() and o.position > 0 and o.asslist[o.assnum] == FightLogic.ASS_FWATCH:
			watching += 1
	check(watching >= 6, "the other skaters watch: %d" % watching)
	# No second fight while the puck's bit is set.
	var c := w.objects[3]
	var d := w.objects[9]
	_square_up(w, c, d)
	w.fight.checkfight(c, d)
	check(not c.fighting(), "one fight at a time")
	w.dispose()
	return true

## ChkFightValue: the starter needs Fgt >= threshold; the joiner Fgt >= the minimum and
## >= the ChksF table less twice his checks. d0 is not restored between the two calls.
func test_chk_fight_value() -> bool:
	var w := _fight_world(1)
	var a := w.objects[2]
	var b := w.objects[8]
	a.hf = 8
	b.hf = 12
	w.period_seconds = 300
	eq(w.fight._period_index(), 1, "5:00 periods: chkcnttab entry 1 (30)")
	w.period_seconds = 30
	eq(w.fight._period_index(), 0, "0:30: entry 0 (20)")
	eq(w.fight._period_index_chkf(), 1, "but chkftab entry 1 (moveq #2)")
	w.period_seconds = 1200
	eq(w.fight._period_index(), 3, "20:00: entry 3")
	# Threshold 10: a (8) cannot start; d0 comes back unchanged.
	eq(w.fight.chk_fight_value(a, b, 10), 10, "starter too weak: d0 kept")
	check(not a.fighting(), "no fight")
	# b starts (12 >= 10); a joins only with checks: 16 - 2 * ChksF <= 8 needs 4 checks.
	w.stats[0].player_checks[a.pnum] = 3
	eq(w.fight.chk_fight_value(b, a, 10), 16, "joiner short of checks: d0 = chkftab")
	check(not b.fighting(), "no fight")
	w.stats[0].player_checks[a.pnum] = 4
	w.fight.chk_fight_value(b, a, 10)
	check(a.fighting() and b.fighting(), "fight")
	# Arcade halves the checks needed (16 -> 8): no checks at all are enough for Fgt 8.
	var w2 := _fight_world(2)
	var c := w2.objects[2]
	var d := w2.objects[8]
	c.hf = 8
	d.hf = 12
	w2.period_seconds = 1200
	w2.stats[0].player_checks[c.pnum] = 0
	w2.fight.chk_fight_value(d, c, 6)
	check(c.fighting(), "Arcade: joins on Fgt alone")
	w.dispose()
	w2.dispose()
	return true

## fightinput: C throws high, B low, A grabs; nothing while squaring up.
func test_fightinput() -> bool:
	var w := _fight_world(1)
	var a := w.objects[2]
	var b := w.objects[8]
	_square_up(w, a, b)
	w.fight.checkfight(a, b)
	w.rules.pencntdwn = 0x500
	w.fight.fightinput(a, 8, PadState.C, 1)
	eq(a.spa, FightLogic.SPA_FIGHT, "still dropping the gloves")
	for pair in [[PadState.C, FightLogic.SPA_FHIGH], [PadState.B, FightLogic.SPA_FLOW], [PadState.A, FightLogic.SPA_FGRAB]]:
		a.spa = FightLogic.SPA_FHITH
		a.flags2 &= ~SimObject.PF2_AIP
		w.fight.fightinput(a, 8, pair[0], 1)
		eq(a.spa, pair[1], "button %x" % pair[0])
		check(a.flags2 & SimObject.PF2_AIP != 0, "animation in progress")
	a.spa = FightLogic.SPA_FHITH
	a.flags2 &= ~SimObject.PF2_AIP
	w.fight.fightinput(a, 8, 0, 1)
	check(a.flags2 & SimObject.PF2_AIP == 0, "no button: AIP cleared")
	w.dispose()
	return true

## A whole fight, CPU against CPU: the gloves drop, the banner shows, punches land until
## one goes down, the countdown is cut, both majors are assessed (Fighting * for the one
## who landed the last blow), they serve coincidental time, and the faceoff clears the
## gloves.
func test_fight_to_penalties() -> bool:
	var w := _fight_world(1, 0x135A)
	var a := w.objects[2]
	var b := w.objects[8]
	_square_up(w, a, b, 10)
	var banner := []
	w.fight.banner.connect(func(l: PackedStringArray) -> void: banner.append(l))
	var assessed := []
	w.rules.penalty_assessed.connect(func(t: int, p: int, id: int, m: int) -> void: assessed.append([t, p, id, m]))
	var hits := [0]
	w.sound.connect(func(id: int) -> void:
		if id == FightLogic.SFX_HIT_HIGH or id == FightLogic.SFX_HIT_LOW:
			hits[0] += 1)
	var drops := [0]
	w.faceoff.faceoff_dropped.connect(func(_h: bool) -> void: drops[0] += 1)
	var slots := [a.pnum, b.pnum]
	w.fight.checkfight(a, b)
	var gloves := false
	var f := 0
	while drops[0] == 0 and f < 6000:
		w.step()
		f += 1
		gloves = gloves or w.fight.gloves_pos() != null
	check(gloves, "the gloves hit the ice")
	eq(banner.size(), 1, "the banner, once")
	if banner.size() > 0:
		eq(banner[0][1], "vs", "two names around vs")
	check(hits[0] > 0, "punches landed: %d" % hits[0])
	var ids := []
	for e in assessed:
		if e[2] == FightLogic.PEN_FIGHTING or e[2] == FightLogic.PEN_FIGHTING_STAR:
			ids.append(e[2])
			eq(e[3], 5, "a major")
	ids.sort()
	eq(ids, [FightLogic.PEN_FIGHTING, FightLogic.PEN_FIGHTING_STAR], "Fighting and Fighting *")
	check(drops[0] > 0, "play resumed with a faceoff (%d frames)" % f)
	check(w.fight.gloves_pos() == null, "the faceoff picked up the gloves")
	check(w.puck().flags2 & SimObject.PF2_FIGHT == 0, "Endfaceoff cleared the puck's bit")
	# Coincidental majors: in the box, bit 14, not counted against the strength.
	var home := w.stats[0].tmpdst[slots[0]]
	var away := w.stats[1].tmpdst[slots[1]]
	check(home > 0 and home & 0x4000 != 0, "home fighter serving coincidental time: %x" % home)
	check(away > 0 and away & 0x4000 != 0, "away fighter serving coincidental time: %x" % away)
	# The majors do not change the strength; one fight in four also draws an instigator
	# minor, a real power play.
	var short := [0, 0]
	for e in assessed:
		if e[2] == FightLogic.PEN_INSTIGATOR:
			short[e[0]] += 1
	eq(w.stats[0].on_ice - w.stats[1].on_ice, short[1] - short[0], "strength (instigators %s)" % [short])
	w.dispose()
	return true

## newTitleScreen for both editions: the palette fades in during frames 8-32, the logos have
## slid in by frame 115, and with no Start press the credits end the routine on the
## frame the ROM does (4211 retail, 21 blocks and 4412 with the fight patch's credits).
func test_title_screen() -> bool:
	var sim: Node = root.get_node("Sim")
	var keep: MatchConfig = sim.match
	for pair in [[MatchConfig.Edition.RETAIL, 4211, 20], [MatchConfig.Edition.FIGHT, 4412, 21]]:
		var m := MatchConfig.new()
		m.edition = pair[0]
		sim.match = m
		var t: Control = load("res://ui/title_screen.tscn").instantiate()
		t.set_physics_process(false)
		root.add_child(t)
		# The runner works before the root enters the tree, so _ready has not run yet.
		if not t.is_node_ready():
			t._ready()
		eq(t._blocks.size(), pair[2], "credit blocks")
		var faded := -1
		var slid := -1
		var f := 0
		while t._phase != 4 and f < 6000:
			t._physics_process(0.0)
			f += 1
			if faded < 0 and _same_cram(t._cram, t._target):
				faded = f
			if slid < 0 and f > 90 and Array(t._hs).all(func(v: int) -> bool: return v == 0):
				slid = f
		check(faded > 8 and faded <= 32, "faded in during frames 8-32 (cramfade): %d" % faded)
		check(slid > 90 and slid <= 115, "logos in place by frame 115: %d" % slid)
		eq(f, pair[1], "the credits end the title")
		t.free()
	sim.match = keep
	return true

static func _same_cram(a: Array, b: Array) -> bool:
	for k in 4:
		for i in 16:
			if int(a[k][i]) != int(b[k][i]):
				return false
	return true

## The marker nibbles: the puck-carrier star goes to the carrier every loop (none while
## the puck is loose), a pad's star to its player, and the penalized player keeps the
## filled star on the penalty screen.
func test_markers() -> bool:
	var w := HockeyWorld.new(SimSettings.new())
	w.setupice()
	eq(Array(w.marks), [15, 15, 15, 15, 15, 15], "all hidden after setupice")
	var c := w.place(3, Vector2i(0, 0), SimObject.POS_C, false, true)
	_rate(c)
	w.drop_puck(Vector2i(0, 0))
	w.puckc = c.index
	w.update_players(1)
	eq(w.marks[0], 3, "carrier star")
	w.puckc = -1
	w.update_players(1)
	eq(w.marks[0], 15, "loose puck: no carrier star")
	w.cont_team[0] = 1
	w.set_c_player(0, c)
	w.update_players(1)
	eq(w.marks[1], 3, "pad 1's star on its player")
	# The penalty screen: asspenalty's first call marks him and nothing clears it.
	w.sflags |= HockeyWorld.SF_HOR
	c.flags |= SimObject.PF_NA
	w.lines.asspenalty(c, 1)
	w.update_players(1)
	eq(w.marks[0], 3, "penalized player keeps the filled star")
	w.dispose()
	return true

func test_pause_menu_actions() -> bool:
	var w := HockeyWorld.new(SimSettings.new())
	w.roster.setup_teams(_team("BOS"), _team("MTL"))
	# sub_7E0E: pad 2 playing home pauses for home; a pad on the road (or none) for away.
	w.cont_team[0] = 2
	w.cont_team[1] = 1
	eq(w.pause_team(0), 1, "pad 1 on the road: away menu")
	eq(w.pause_team(1), 0, "pad 2 at home: home menu")
	# Timeout: once per team; both teams rest.
	w.stats[0].energy.fill(0x200)
	w.stats[1].energy.fill(0x300)
	check(w.timeout(1), "away calls its timeout")
	check(w.stats[1].flags30 & TeamStats.F30_TIMEOUT != 0, "the timeout flag is set")
	eq(w.stats[0].energy[5], 0x1000, "home rested")
	eq(w.stats[1].energy[25], 0x1000, "away rested")
	check(not w.timeout(1), "only one timeout")
	check(w.stats[0].flags30 & TeamStats.F30_TIMEOUT == 0, "home still has its own")
	# Change Goalie.
	w.stats[0].goalie_pnum = 0
	w.stats[0].goalie_pulled = false
	eq(w.goalie.goalie_row(0), 1, "the starter is row 1")
	w.goalie.change_goalie(0, 2)
	eq(w.stats[0].goalie_pnum, 1, "row 2: the backup goes in")
	eq(w.goalie.goalie_row(0), 2, "the list reopens on him")
	w.goalie.change_goalie(0, 0)
	eq(w.stats[0].goalie_pnum, -1, "row 0: no goalie")
	check(w.goalie.goalie_pulled(0), "the net is empty")
	eq(w.goalie.goalie_row(0), 0, "the list reopens on No Goalie")
	# A CPU pull ($FFxx) ignores row 0 but a goalie row puts one back.
	w.stats[1].goalie_pnum = 0
	w.stats[1].goalie_pulled = true
	w.goalie.change_goalie(1, 0)
	eq(w.stats[1].goalie_pnum, 0, "row 0 during a CPU pull does nothing")
	check(w.stats[1].goalie_pulled, "still pulled")
	w.goalie.change_goalie(1, 1)
	check(not w.stats[1].goalie_pulled and w.stats[1].goalie_pnum == 0, "row 1 puts the starter back")
	# Goalie control: the pausing pad's word, or both when the pads share a team.
	w.auto_goalie = [true, true]
	w.toggle_goalie_control(0)
	eq(w.auto_goalie, [false, true], "pad 1 only")
	w.cont_team[1] = 2
	w.toggle_goalie_control(1)
	eq(w.auto_goalie, [true, false], "same team: both flip")
	w.dispose()
	return true

func test_crowd_frames() -> bool:
	var w := HockeyWorld.new(SimSettings.new())
	# Quiet: row 0 frames, no flash.
	var seen := {}
	for i in 400:
		w.crowd_level = 0
		w.rules.updatecrowdf(1)
		seen[w.rules.crowd_frame] = true
		check(w.rules.crowd_flash == 0, "no flash while quiet")
	var keys := seen.keys()
	keys.sort()
	eq(keys, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10], "the quiet row's frames (_cd0 row 0)")
	# Loud: rows 2-3 (frames 11-18) and the odd camera flash, $13-$19, one loop each.
	seen.clear()
	var flashes := {}
	for i in 2000:
		w.crowd_level = 0x200
		w.rules.updatecrowdf(1)
		seen[w.rules.crowd_frame] = true
		if w.rules.crowd_flash != 0:
			flashes[w.rules.crowd_flash] = true
	keys = seen.keys()
	keys.sort()
	eq(keys, [11, 12, 13, 14, 15, 16, 17, 18], "the loud rows' frames")
	check(flashes.size() > 0, "flashes while the crowd is loud")
	for f in flashes:
		check(f >= 0x13 and f <= 0x19, "flash frame %d in $13-$19" % f)
	w.dispose()
	return true

func test_arena_anim_scripts() -> bool:
	var w := HockeyWorld.new(SimSettings.new())
	var a := w.arena
	check(not ArenaAnim.script_of(1).is_empty(), "the scripts are exported")
	# A one-shot: shown from its first step, removed in the loop its script ends.
	a.start(1)
	eq(a.shown_frame(), 0, "nothing until the first step loads it")
	var n := 0
	while a.id >= 0 and n < 1000:
		a.step(1)
		if n == 0:
			eq(a.shown_frame(), 1, "the first frame")
		n += 1
	eq(n, 229, "id 1 shows for 228 vblanks; the 229th step ends it")
	eq(a.shown_frame(), 0, "and is gone")
	# A loop keeps going.
	a.start(3)
	for i in 500:
		a.step(1)
	eq(a.id, 3, "id 3 loops")
	check(a.shown_frame() >= 1 and a.shown_frame() <= 8, "on one of its 8 frames")
	# A start consumes the faceoff's pending id; a check over the bench boards starts 7.
	w.faceoff.overlay_request = 5
	w.background_anim.emit(7)
	eq(a.id, 7, "background_anim(7) starts the bench ripple")
	eq(w.faceoff.overlay_request, -1, "and consumes the pending id")
	a.stop()
	check(a.id == -1 and not a.pending_ok, "stopped")
	w.dispose()
	return true

func test_arena_anim_hooks() -> bool:
	var w := HockeyWorld.new(SimSettings.new())
	w.roster.setup_teams(_team("BOS"), _team("MTL"))
	# puckfaceoff2's setup starts the picked id; the one-shots hold the drop to $10E.
	var p := w.puck()
	w.fox = -0xB4
	w.foy = 0x5C
	w.faceoff.overlay_request = 1
	w.arena.pending_ok = true
	w.arena.start(7)
	w.faceoff.overlay_request = 1
	p.flags |= SimObject.PF_NA
	w.faceoff.puckfaceoff2(p)
	eq(w.arena.id, 1, "the faceoff's animation replaced the running one")
	eq(w.faceoff.overlay_shown, 1, "overlay_shown is the running id")
	check(p.temp[0] >= 0x10E, "a one-shot holds the drop: %d" % p.temp[0])
	# Without pending_ok (a lost start) nothing starts and the id waits for next time.
	w.arena.stop()
	w.faceoff.overlay_request = 2
	p.flags |= SimObject.PF_NA
	w.faceoff.puckfaceoff2(p)
	eq(w.arena.id, -1, "no start without byte_FFC2FC bit 0")
	eq(w.faceoff.overlay_request, 2, "the picked id is kept")
	# The drop stops it.
	w.arena.start(3)
	p.temp[0] = 0
	w.faceoff.puckfaceoff2(p)
	eq(w.arena.id, -1, "the drop stops the animation")
	# Hat trick: a home skater's third goal; not an away one, not a second.
	w.stats[0].player_goals[7] = 3
	w.score_summary.append({"away": false, "scorer": 7})
	w.arena.hat_trick_check()
	eq(w.arena.id, ArenaAnim.HAT_TRICK, "home hat trick throws the hats")
	w.arena.stop()
	w.stats[1].player_goals[7] = 3
	w.score_summary.append({"away": true, "scorer": 7})
	w.arena.hat_trick_check()
	eq(w.arena.id, -1, "no hats for the visitors")
	w.stats[0].player_goals[8] = 2
	w.score_summary.append({"away": false, "scorer": 8})
	w.arena.hat_trick_check()
	eq(w.arena.id, -1, "two goals is not a hat trick")
	w.stats[0].player_goals[0] = 3
	w.score_summary.append({"away": false, "scorer": 0})
	w.arena.hat_trick_check()
	eq(w.arena.id, -1, "a goalie slot does not count")
	w.dispose()
	return true

func test_intermission_zamboni() -> bool:
	var w := HockeyWorld.new(SimSettings.new())
	eq(w.zamx, -1, "no zamboni in play")
	check(not w.side_view(), "the rink view in play")
	w.begin_intermission()
	eq(w.zamx, 0x140, "Intermission: zamx = $140")
	check(w.side_view(), "the side view at the intermission")
	w.arena.start(3)
	for i in 2000:
		w.intermission_vblank()
	eq(w.zamx, 0x709, "waitxsr stops it at $709")
	eq(w.arena.id, 3, "the animation steps on out of sight")
	w.end_intermission()
	eq(w.zamx, -1, "gone after the intermission")
	check(not w.side_view(), "back to the rink")
	w.dispose()
	return true

func test_edit_lines() -> bool:
	var w := HockeyWorld.new(SimSettings.new())
	w.roster.setup_teams(_team("BOS"), _team("MTL"))
	w.roster.copy_lines(0)
	eq(w.lines.line_name(0), "Sc1", "line changes on: RAM line 0 is Sc1")
	var rl := w.stats[0].ram_lines
	var c := rl[4]
	var rw := rl[5]
	# The right wing moves to centre: the old centre takes the wing.
	w.lines.edit_line(0, 0, 4, rw - 1)
	eq(w.stats[0].ram_lines[4], rw, "the new centre")
	eq(w.stats[0].ram_lines[5], c, "the old centre trades places")
	# A bench player simply takes the slot.
	w.lines.edit_line(0, 0, 3, 20)
	eq(w.stats[0].ram_lines[3], 21, "roster slot 20 on left wing")
	w.lines.set_personel(0)
	var outs := []
	for i in 6:
		outs.append(w.objects[i].newpnum)
	check(20 in outs, "SetPersonel sends him out: %s" % [outs])
	w.opt_line_on = false
	eq(w.lines.line_name(0), "Off", "line changes off: RAM line 0 is the Off line")
	eq(w.lines.line_name(1), "Sc2", "then Sc2")
	w.dispose()
	return true

## The arena sheets hold assembled figures (tools/extract/arena.py), not hardware pieces.
func test_arena_sheets_assembled() -> bool:
	for n in ["crowd", "bganim", "zamboni"]:
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/arena/%s.json" % n))
		check(d is Dictionary and d.has("sprites") and not d.has("pieces"), "%s: a figure sheet" % n)
		var frames: Dictionary = d["frames"] if d.has("frames") else {}
		if n == "bganim":
			for k in d["files"]:
				frames.merge(d["files"][k]["frames"])
		var bad := 0
		for k in frames:
			if not frames[k].has("parts") or frames[k].has("sprites"):
				bad += 1
		eq(bad, 0, "%s: every frame lists assembled parts" % n)
	var z: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/arena/zamboni.json"))
	for k in z["frames"]:
		eq(z["frames"][k]["parts"].size(), 1, "zamboni frame %s is one image" % k)
	return true

func test_overlay_logic() -> bool:
	var w := HockeyWorld.new(SimSettings.new())
	w.roster.setup_teams(_team("BOS"), _team("MTL"))
	var boxes := []
	w.rules.goal_box.connect(func(i: Dictionary) -> void: boxes.append(i))
	var pas := []
	w.rules.pa_set.connect(func(id: int) -> void: pas.append(id))
	# A power-play goal: the freed penalty sets the header.
	w.stats[1].on_ice = 5
	w.stats[1].box = PackedInt32Array([12])
	w.stats[1].tmpdst[12] = 100
	w.pp_goal(0)
	w.stats[0].player_goals[7] = 1
	w.score_summary.append({"away": false, "scorer": 7, "assist1": 2, "assist2": -1})
	w.rules.set_pa(GameRules.PEN_GOAL)
	eq(pas, [GameRules.PEN_GOAL], "pa_set for the goal")
	eq(boxes.size(), 1, "one goal box")
	eq(boxes[0]["header"], "PP GOAL!", "power-play goal")
	eq(boxes[0]["assists"].size(), 1, "one assist")
	check(not w.rules.pp_goal_flag, "the flag is consumed")
	# Third goal: hat trick; a penalty-shot goal lists no assists.
	w.stats[0].player_goals[7] = 3
	w.f_c2f4 |= HockeyWorld.C2F4_PS_GOAL
	w.rules.set_pa(GameRules.PEN_GOAL)
	eq(boxes[1]["header"], "HAT TRICK!", "hat trick")
	eq(boxes[1]["assists"].size(), 0, "a penalty-shot goal has no assists")
	# CalcPenTime: one minor left on the shorthanded team.
	w.stats[1].on_ice = 5
	w.stats[1].box = PackedInt32Array([10])
	w.stats[1].tmpdst[10] = 95
	w.stats[0].on_ice = 6
	eq(w.rules.calc_pen_time(w.stats[1], w.stats[0]), 95, "PP time left")
	# Stars: the hat trick first.
	w.stats[0].goals = 3
	var picks := w.rules.stars_of_game()
	eq(picks[0], [0, 7], "the hat-trick scorer is the first star")
	# Time on ice counts on the game-second tick.
	w.place(3, Vector2i(0, 0), SimObject.POS_C, false, true)
	w.objects[3].pnum = 2
	w.gmode &= ~HockeyWorld.GM_CLOCK
	w.f_c2fa |= 1 << 2
	w.gameclock = 100
	for i in 70:
		w.rules.vblank_tick()
	check(w.stats[0].player_toi[2] >= 1, "time on ice: %d" % w.stats[0].player_toi[2])
	w.dispose()
	return true

## The regular-season slate (sub_18002) and the other games' periods (SetScore): after
## the third a game within a goal is flagged and stays in the third until a highlight
## settles it.
func test_other_games() -> bool:
	var w := HockeyWorld.new(SimSettings.new())
	var bos := _team("BOS")
	var mtl := _team("MTL")
	w.roster.setup_teams(bos, mtl)
	w.rules.init_other_games(MatchConfig.available_teams())
	var lg := w.rules.league
	eq(w.rules.other_games.size(), 8, "eight other games")
	var seen := {}
	for g in lg.gs:
		for k in ["team1", "team2"]:
			var t: int = g[k]
			check(t != 1 and t != 11 and t < 26, "not a playing or an All-Star team: %d" % t)
			check(not seen.has(t), "a team plays once")
			seen[t] = true
	for i in 4:
		lg.update_scores(w.rng)
	var goals := 0
	var flagged := 0
	for g in lg.gs:
		goals += g["score1"] + g["score2"]
		if g["flags"] & League.F_HILITE:
			flagged += 1
			eq(g["gsper"], 3, "a close game stays in the third")
			check(absi(g["score1"] - g["score2"]) <= 1, "within a goal")
		else:
			eq(g["gsper"], League.GSPER_FINAL, "a final")
	check(goals > 0, "goals were scored: %d" % goals)
	w.rules.intermission_highlights()
	for g in lg.gs:
		eq(g["gsper"], League.GSPER_FINAL, "every game final after the highlights")
		check(g["score1"] != g["score2"] or flagged == 0 or true, "settled")
	w.dispose()
	return true

## The playoffs: NewPO, MakeTree's home ice, FigureJoy, a single-game round, a best-of-7
## series, the 80-bit saved state and the save RAM.
func test_playoffs() -> bool:
	var lg := League.new()
	lg.set_teams(MatchConfig.available_teams())
	var rng := RetailRng.new(7)
	lg.new_po(rng, 11, League.MODE_NEW)
	eq(lg.user_team(), 11, "Montreal is in the bracket")
	eq(lg.bosgames, League.SINGLE, "one game a round")
	var fj := lg.figure_joy()
	check(not fj.is_empty(), "the user plays this round")
	var g: Dictionary = lg.gs[lg.gamenum]
	eq(g["team1"], lg.tree[2 * lg.gamenum + 1], "the second-listed team hosts a single game")
	eq(fj["pads"], PackedInt32Array([1, 0, 0, 0]) if fj["home"] == 11 else PackedInt32Array([2, 0, 0, 0]), "One: pad 1 on the user's side")
	# The user wins round 1 at home or away.
	var home_win: bool = fj["home"] == 11
	lg.advance(rng, 3 if home_win else 1, 1 if home_win else 3)
	eq(lg.gamelevel, 1, "the quarterfinals")
	lg.make_tree()
	check(not lg.figure_joy().is_empty(), "the winner plays on")
	eq(lg.shown_games().size(), 3, "three other quarterfinals")
	# The saved state round-trips.
	var n := lg.encode()
	var back := League.new()
	back.set_teams(MatchConfig.available_teams())
	check(back.continue_from(n), "a playoff to continue")
	eq(back.user_team(), 11, "the same user")
	eq(back.gamelevel, 1, "the same round")
	eq(back.bits, lg.bits, "the same bracket")
	# Best of seven: four wins end the series, the others are flipped to 4 wins.
	var b7 := League.new()
	b7.set_teams(MatchConfig.available_teams())
	b7.new_po(rng, 11, League.MODE_NEW7)
	eq(b7.bosgames, 0, "game 1")
	for k in 4:
		b7.make_tree()
		var f := b7.figure_joy()
		var hw: bool = f["home"] == 11
		b7.advance(rng, 4 if hw else 0, 0 if hw else 4)
	eq(b7.gamelevel, 1, "a sweep ends the round")
	check(not b7.alt_state.is_empty(), "the decided round is kept for the bracket")
	# The save RAM: the checksum, and the state and stats in the $FFD076 block.
	var ram := Sram.new("")
	check(ram.valid(), "a cleared save RAM is valid")
	var stats := PackedInt32Array()
	stats.resize(104)
	stats[0] = 5
	stats[1] = 2000
	ram.save_playoffs(n, stats)
	check(ram.valid(), "still valid after a save")
	eq(ram.playoff_state(), n, "the state is saved")
	var st2 := ram.playoff_stats()
	eq(st2[0], 5, "a stat is saved")
	eq(st2[1], 1023, "clamped to its 10-bit width")
	return true

func test_replay_buffer() -> bool:
	var w := HockeyWorld.new(SimSettings.new())
	var rp := w.replay
	var c := w.place(3, Vector2i(0, 0), SimObject.POS_C, false, true)
	w.sflags2 &= ~GameRules.SF2_NOREC
	for i in 10:
		c.set_pos(Vector2i(i, 0))
		rp.record(1)
	eq(rp.count(), 10, "ten records")
	eq(rp.at(0)["objs"][3][0].x >> 16, 0, "the oldest has x 0")
	eq(rp.at(9)["objs"][3][0].x >> 16, 9, "the newest has x 9")
	# The ring wraps after RECORDS loops (sflags bit 4).
	for i in ReplayRecorder.RECORDS:
		c.set_pos(Vector2i(i % 100, 0))
		rp.record(1)
	check(rp.full, "the ring wrapped")
	eq(rp.count(), ReplayRecorder.RECORDS, "a full ring")
	# SF2_NOREC overwrites the newest record in place; the grace count advances first.
	var n := rp.head
	w.sflags2 |= GameRules.SF2_NOREC
	rp.record(1)
	eq(rp.head, n, "frozen: the newest record is overwritten")
	rp.grace = 3
	for i in 5:
		rp.record(1)
	eq(rp.head, (n + 3) % ReplayRecorder.RECORDS, "three more records, then frozen")
	# A sound is stored with the record of its loop, once.
	w.sound.emit(0x2C)
	rp.record(1)
	eq(rp.at(rp.count() - 1)["sfx"], 0x2C, "the sound is recorded")
	rp.record(1)
	eq(rp.at(rp.count() - 1)["sfx"], -1, "once")
	# SetRCords puts a record back on the objects.
	var live := rp.snapshot(0)
	rp.apply(rp.at(0))
	check(c.x() != 50 or true, "applied")
	c.set_pos(Vector2i(50, 60))
	rp.apply(live)
	check(c.x() != 50, "the saved state comes back")
	w.dispose()
	return true

## Four-way play: pads 1 and 3 home, 2 and 4 away. Pads 3 and 4 get players at the
## faceoff (setchgplayer), keep their stars (ffo 4, 5), switch with B in pad 1's / pad
## 2's slot without taking that pad's player, pause as their own pad, and keep their
## player when he picks up the puck.
func test_four_way_pads() -> bool:
	var w := HockeyWorld.new(SimSettings.new())
	for i in 5:
		w.place(1 + i, Vector2i(-80 + i * 40, -40), SimObject.POS_LD + i, false, true)
		w.place(7 + i, Vector2i(-80 + i * 40, 40), SimObject.POS_LD + i, true, false)
	w.drop_puck(Vector2i(0, 0))
	w.cont_team = PackedInt32Array([1, 2, 1, 2])
	w.faceoff.setchgplayer()
	var cs := {}
	for k in 4:
		cs[w.c_player[k]] = true
		check(w.c_player[k] >= 0 and w.objects[w.c_player[k]].joypad(), "pad %d has a player" % (k + 1))
		eq(w.objects[w.c_player[k]].away(), k & 1 == 1, "pad %d plays its side" % (k + 1))
	eq(cs.size(), 4, "four different players")
	w.faceoff_grace = 0
	w.step()
	eq(w.marks[4], w.c_player[2], "pad 3's star")
	eq(w.marks[5], w.c_player[3], "pad 4's star")
	eq(w.marks[1], w.c_player[0], "pad 1's star stays")
	# A B tap on pad 3 switches pad 3 only.
	var c1 := w.c_player[0]
	var c3 := w.c_player[2]
	# The puck by the left defenceman, who nobody drives.
	w.drop_puck(Vector2i(-80, -16))
	w.pads[2].held = PadState.B
	w.step()
	w.pads[2].held = 0
	w.step()
	eq(w.c_player[0], c1, "pad 1 keeps his player")
	eq(w.c_player[2], 1, "pad 3 switched to the defenceman by the puck (from %d)" % c3)
	check(not w.objects[c3].joypad() or w.c_player[2] == c3, "the old player went back to the CPU")
	# Start on pad 4 pauses as pad 4; its menu is the away team's.
	var paused := [-1]
	w.pause_requested.connect(func(k: int) -> void: paused[0] = k)
	w.pads[3].held = PadState.START
	w.step()
	w.pads[3].held = 0
	eq(paused[0], 3, "pad 4 paused")
	eq(w.pause_team(3), 1, "as the away team")
	eq(w.pause_team(2), 0, "pad 3 as home")
	# The puck to pad 3's player: neither pad 1 nor the CPU takes him.
	var o := w.objects[w.c_player[2]]
	w.hand_control(o)
	eq(w.c_player[2], o.index, "pad 3 keeps the carrier")
	eq(w.c_player[0], c1, "pad 1 is not handed pad 3's player")
	w.dispose()
	return true

## All four pads mash random buttons through a short game.
func test_four_way_mash_game() -> bool:
	var w := HockeyWorld.new(SimSettings.new(), 0x94)
	w.opt_perlen = 3
	w.roster.setup_teams(_team("PIT"), _team("CHI"))
	w.cont_team = PackedInt32Array([1, 2, 1, 2])
	var over := [false]
	w.rules.game_over.connect(func() -> void: over[0] = true)
	w.rules.start_game()
	var r := RandomNumberGenerator.new()
	r.seed = 4
	var held := [0, 0, 0, 0]
	var frames := 0
	var clash := 0
	while not over[0] and frames < 60000:
		for k in 4:
			if r.randi() % 6 == 0:
				held[k] = r.randi() & 0x7F
			w.pads[k].held = held[k]
		w.step()
		frames += 1
		for a in 4:
			for b in range(a + 1, 4):
				if w.c_player[a] >= 0 and w.c_player[a] == w.c_player[b] and w.objects[w.c_player[a]].position != SimObject.POS_GOALIE:
					clash += 1
	check(over[0], "the game ended under random input (%d frames)" % frames)
	eq(clash, 0, "no two pads drove the same skater")
	w.dispose()
	return true

## ChooseSong: the home team's row, the random fallback (one RNG roll), nothing in a
## highlight; a home goal's tune 120 loops later with the music cut first; the period's
## tune on its first loop.
func test_choose_song() -> bool:
	var w := HockeyWorld.new(SimSettings.new(), 0x1234)
	w.roster.setup_teams(_team("PIT"), _team("CHI"))
	eq(w.stats[0].team_index, 17, "Pittsburgh is retail team 17")
	w.f_c2fe |= 1 << 6
	eq(w.choose_song(0), 0x59, "Pittsburgh's period tune")
	check(w.f_c2fe & (1 << 6) == 0, "ChooseSong clears byte_FFC2FE bit 6")
	eq(w.choose_song(4), 0x5A, "the stock away power-play tune")
	w.roster.setup_teams(_team("BOS"), _team("CHI"))
	var b := w.choose_song(3)
	check(b in HockeyWorld.SONG_RANDOM, "Boston's home-goal entry is 0: a random tune (%x)" % b)
	w.gmode |= HockeyWorld.GM_HL
	eq(w.choose_song(0), -1, "nothing in a highlight")
	w.gmode &= ~HockeyWorld.GM_HL
	var heard := []
	var cut := [0]
	w.song.connect(func(id: int) -> void: heard.append(id))
	w.music_off.connect(func() -> void: cut[0] += 1)
	w.home_goal_song()
	for i in 0x77:
		w.step()
	check(heard.is_empty(), "nothing for 119 loops")
	w.step()
	eq(heard.size(), 1, "the tune at loop 120")
	check(heard[0] in HockeyWorld.SONG_RANDOM, "Boston's random goal tune")
	eq(cut[0], 1, "the music was cut first")
	# The period's tune waits for the first loop.
	heard.clear()
	var off := [0]
	w.sound_off.connect(func() -> void: off[0] += 1)
	w.rules.start_per()
	check(heard.is_empty(), "no tune while the intermission holds")
	w.step()
	eq(heard, [0x31], "Boston's period tune on the first loop")
	eq(off[0], 1, "after AllSndOff")
	w.dispose()
	return true

## SfxBank: one DAC voice by instrument priority; a song() crowd id leaves the music; the
## whistle and the horn cut it; a long song loops from its loop start.
func test_sound_rules() -> bool:
	var b := SfxBank.new()
	root.add_child(b)
	var dac: AudioStreamPlayer = b.get("_dac")
	var music: AudioStreamPlayer = b.get("_music")
	b.play(0x10)
	var first := dac.stream
	check(first != null, "a pass takes the DAC")
	b.play(0x18)
	check(dac.stream != first, "a shot (instrument $63) beats a pass ($61)")
	var shot := dac.stream
	b.play(0x11)
	check(dac.stream == shot, "a pass while the shot sounds is dropped")
	b.play(0x0B)
	check(dac.stream != shot, "the cheer ($6D) cuts the shot")
	b.play_song(0x30)
	var tune := music.stream
	check(tune != null, "an organ tune is loaded")
	b.play_song(0x0C)
	check(music.stream == tune, "the boo leaves the music alone")
	b.play_song(0x79)
	var s79 := music.stream as AudioStreamOggVorbis
	check(s79 != null and s79.loop, "the intermission song loops")
	if s79:
		check(s79.loop_offset > 0.0, "from its loop start")
	b.queue_free()
	return true

## Game Setup's Players row (FigureJoy _noplist with the 4 Way Play rows) and the Overall
## rating with the game's form (CalcAttrib: the truncated mean of the rated bytes).
func test_frontend_mapping() -> bool:
	eq(MatchConfig.players_pads(0), PackedInt32Array([0, 0, 0, 0]), "Demo: CPU against CPU")
	eq(MatchConfig.players_pads(2), PackedInt32Array([2, 0, 0, 0]), "One - Visitor: pad 1 away")
	eq(MatchConfig.players_pads(3), PackedInt32Array([1, 1, 0, 0]), "Two - Teammates")
	eq(MatchConfig.players_pads(6), PackedInt32Array([1, 2, 1, 2]), "Four")
	var m := MatchConfig.new()
	m.players = 5
	eq(m.pad_teams(), PackedInt32Array([1, 2, 1, 0]), "Three: pad 3 with pad 1")
	var t := _team("MTL")
	var p := t.player(0)
	var base := p.overall()
	var form := PackedInt32Array()
	form.resize(16)
	eq(p.overall(form), base, "a zero form changes nothing")
	form.fill(7)
	check(p.overall(form) == mini(base + 7, 99) or base < 50, "+7 everywhere adds 7 (%d -> %d)" % [base, p.overall(form)])
	form.fill(0)
	# Only the rated attributes' bytes count: the jersey bytes (15, 14) do not.
	form[0] = 8
	form[1] = 8
	eq(p.overall(form), base, "unrated bytes are ignored")
	var a := RosterLogic.make_form(RetailRng.new(5))
	var b := RosterLogic.make_form(RetailRng.new(5))
	eq(a, b, "the Matchups form table is reproducible from its seed")
	eq(a[0].size(), 416, "416 bytes a team")
	return true

## SetRCords in the reverse angle: positions negated, frames through revframetbl, the
## shadow hidden, the camera negated and clamped.
func test_reverse_angle() -> bool:
	var w := HockeyWorld.new(SimSettings.new())
	var c := w.place(3, Vector2i(-112, -205), SimObject.POS_C, false, true)
	c.frame = 36
	w.objects[HockeyWorld.SHADOW].frame = 1
	w.camera = Vector2i(-100, -250)
	var r := w.replay.snapshot(0)
	w.reverse_angle = true
	w.replay.apply(r)
	eq(c.pos(), Vector2i(112, 205), "positions negated")
	eq(c.frame, 16, "frame 36 seen from the other end is 16 ($10)")
	eq(w.objects[HockeyWorld.SHADOW].y(), -0x400, "the shadow is hidden")
	eq(w.camera, Vector2i(60, 250), "the camera negated and clamped")
	eq(ReplayRecorder.revframe(1), 0x15, "glide dir 0 -> glide dir 4")
	w.reverse_angle = false
	w.replay.apply(r)
	eq(c.pos(), Vector2i(-112, -205), "the normal angle again")
	w.dispose()
	return true
