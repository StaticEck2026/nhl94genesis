extends SceneTree
## Headless tests. Run from godot/:
##   godot --headless --path . --script res://tests/run_tests.gd

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
	]:
		call(test)
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
func test_maxspeed_table_matches_rom() -> void:
	var rom := [0x1CD9410, 0x1FCE3E1, 0x22E8284, 0x2626FF9, 0x298AC40, 0x2D13759, 0x30C1144, 0x3493A01,
		0x388B190, 0x3CA77F1, 0x40E8D24, 0x454F129, 0x49DA400, 0x4E8A5A9, 0x535F624, 0x5859571]
	var m := motion()
	for i in rom.size():
		eq(m.max_speed_sq_entry(i), rom[i], "MaxSpeed[%d]" % i)

func test_max_speed_index_and_half_step() -> void:
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

func test_max_speed_cuts() -> void:
	var m := motion()
	var s := SkaterMotion.Skater.new()
	s.speed = 30
	s.has_puck = true
	eq(m.max_speed_sq(s), 0x5859571 >> 1, "carrier halves squared max")
	s.has_puck = false
	s.fight_injured = true
	eq(m.max_speed_sq(s), 0x5859571 >> 3, "fight injury divides squared max by 8")

func test_agility_factor() -> void:
	var m := motion()
	var s := SkaterMotion.Skater.new()
	s.weight = 8
	s.agility = 10
	eq(m.agility_factor(s), 49, "(64 - 2 + 10 + 10 + 16) / 2")
	s.double_agility = false
	eq(m.agility_factor(s), 36, "(64 - 2 + 10) / 2")
	s.crowd_boost = true
	eq(m.agility_factor(s), 37, "crowd boost +2")

func test_accel() -> void:
	var m := motion()
	var s := SkaterMotion.Skater.new()
	s.weight = 8
	s.agility = 10
	eq(m.accel(s, Vector2i(0, 200)), Vector2i(0, 306), "200 * 49 >> 5")
	eq(m.accel(s, Vector2i(0, 200), 2), Vector2i(0, 612), "d7 = 2")
	eq(m.accel(s, Vector2i(-141, -141)), Vector2i(-216, -216), "-141 * 49 >> 5 floors")
	s.joypad = true
	s.has_puck = true
	eq(m.accel(s, Vector2i(0, 200)), Vector2i(0, 153), "joypad carrier halves accel")

func test_accel_cap_keeps_velocity() -> void:
	var m := motion()
	var s := SkaterMotion.Skater.new()
	s.speed = 30
	var top := 9625
	eq(m.apply_accel(s, Vector2i(0, top - 10), Vector2i(0, 200)), Vector2i(0, top - 10), "over cap keeps old velocity")
	eq(m.apply_accel(s, Vector2i(0, 0), Vector2i(0, 200)), m.accel(s, Vector2i(0, 200)), "under cap adds accel")

func test_drag() -> void:
	eq(SkaterMotion.drag_axis(1000, 6), 985, "1000 - 15")
	eq(SkaterMotion.drag_axis(-1000, 6), -984, "asr floors toward -inf")
	eq(SkaterMotion.drag_axis(10, 6), 9, "minimum step 1")
	eq(SkaterMotion.drag_axis(-1, 6), 0, "-1 reaches 0")
	eq(SkaterMotion.drag_axis(0, 6), 0, "0 stays 0")
	eq(motion().apply_drag(Vector2i(1024, 0), true), Vector2i(1022, 0), "glide uses >> 9")

func test_stopna() -> void:
	var m := motion()
	eq(m.apply_stop(Vector2i(1000, -1000)), Vector2i(850, -850), "150 toward 0")
	eq(m.apply_stop(Vector2i(100, -100)), Vector2i(0, 0), "does not cross 0")
	check(SkaterMotion.wants_stop_anim(Vector2i(0x1001, 0)), "stop anim above $1000")
	check(not SkaterMotion.wants_stop_anim(Vector2i(0x1000, -0x1000)), "no stop anim at $1000")

func test_units() -> void:
	near(Nhl94Units.vel_to_px_per_sec(9625.0), 149.8, 0.1, "top speed px/s")
	near(Nhl94Units.px_per_sec_to_vel(Nhl94Units.vel_to_px_per_sec(1234.0)), 1234.0, 0.001, "round trip")
	near(Nhl94Units.frames(1.0 / 60.0), 1.0, 0.0001, "one tick is one retail frame")

func test_dir8() -> void:
	check(Nhl94Units.dir8_to_vector(0).is_equal_approx(Vector2.UP), "dir 0 is up")
	check(Nhl94Units.dir8_to_vector(2).is_equal_approx(Vector2.RIGHT), "dir 2 is right")
	check(Nhl94Units.dir8_to_vector(1).is_equal_approx(Nhl94Units.rink_to_godot(Vector2(141, 141).normalized())), "dir 1 matches dirtab")

func test_puck_follow() -> void:
	var p := PuckPhysics.new(SimSettings.new())
	var r := p.follow_carrier(Vector2(0, 0), Vector2(8, -4), Vector2(3, 0))
	eq(r[0], Vector2(2, -1), "closes 1/4 of the gap")
	eq(r[1], Vector2(3, 0), "takes carrier velocity")
	var s := SimSettings.new()
	s.enable_puck_friction = false
	eq(PuckPhysics.new(s).loose_drag(Vector2i(1000, 0)), Vector2i(1000, 0), "friction toggle")

func test_fsm() -> void:
	var f := PlayerFSM.new()
	check(f.enter(PlayerFSM.State.SKATING), "idle to skating")
	check(not f.enter(PlayerFSM.State.SKATING), "same state is a no-op")
	check(f.enter(PlayerFSM.State.FALLEN), "skating to fallen")
	check(not f.enter(PlayerFSM.State.SHOOTING), "fallen cannot shoot")
	f.tick(2.0)
	eq(f.frames_in_state, 2.0, "frame counter")
