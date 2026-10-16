class_name League
extends RefCounted
## The rest of the league (spec docs/specs/playoffs_records.md §2-§6):
## - gsstruct: the 8 other games of the night (the regular-season slate, sub_18002) or the
##   playoff series of the round, with their period-by-period scores (InitScores,
##   UpdateScores, SetScore, getscore) and the close-game flag the highlights settle;
## - the playoff tree: NewPO's seeding, MakeTree, FigureJoy's home / away and pads, the
##   series after each game (sub_18380) and the end of a playoff (sub_180FC);
## - the saved state: retail's 80-bit mixed-radix number (sub_18192 / sub_1803E) and the
##   user's cumulative Playoff Stats (AddPOStats), kept in the save RAM block (Sram).
## Retail rebuilds all of it from the save RAM at every Game Setup; the port keeps one
## League in the Sim autoload and lends it to the game's rules. RNG rolls go through the
## RetailRng it is handed (the game world's in play).

const DATA := "res://assets/ui/playoffs/playoffs.json"
const SERIES := 8
## gsstruct +$E flag bits.
const F_FLIPPED := 1
const F_HILITE := 2
const F_OVER := 4
## gsper: 1-3 periods, 4 overtime, 5 final.
const GSPER_FINAL := 5
## OptPlayMode.
const MODE_REGULAR := 0
const MODE_CONTINUE := 1
const MODE_NEW := 2
const MODE_NEW7 := 3
const MODE_SHOOTOUT := 4
## bosgames 7: one game a round.
const SINGLE := 7
## sctab (L47843): weights for 0, 1, 2, 3 goals in a period, by a rating nibble.
const SCTAB := [[43, 30, 23, 4], [39, 32, 24, 5], [35, 33, 26, 6], [30, 34, 30, 6],
	[26, 36, 30, 8], [22, 37, 31, 10], [19, 38, 31, 12], [15, 38, 32, 15]]
## _pojoylist (L55091): {cont1team, cont2team} by (user home ? 0 : 4) + pojoy.
const POJOYLIST := [[1, 0], [1, 1], [1, 2], [2, 1], [2, 0], [2, 2], [2, 1], [1, 2]]
## The save state's fields and radices, in encoding order (sub_18192).
const RADICES := [32, 8, 4, 16, 8, 0x4000]
## AddPOStats' packed widths by (103 - i) & 3.
const STAT_WIDTHS := [12, 14, 10, 10]

static var _seedings: Array = []

## Series: {team1 (home of the next game), team2, wins (first-listed, second-listed of the
## seeding pair), gsper, score1, score2, flags}.
var gs: Array = []
## The user's series this round, -1 none (gamenum).
var gamenum := -1
var postarts := 0
var bosgames := 0
var gamelevel := 0
var potreeteam := 0
var pojoy := 0
## $CEF2: bit k set when the second team of pair k advanced.
var bits := 0
## _gu0: 0-15 the seeds, 16-23 round-1 winners, 24-27, 28-29, 30 the champion.
var tree := PackedInt32Array()
## $FFCD96: goals, assists, SOG, PIM of the user's 26 slots, summed over the playoff.
var po_stats := PackedInt32Array()
## The finished best-of-7 round for the bracket after the game ($FFD176, sflags3 bit 2).
var alt_state := PackedInt32Array()
## TeamData by ROM id, for the scorer and the screens.
var teams: Array = []

func _init() -> void:
	clear_series()
	tree.resize(31)
	po_stats.resize(104)

static func seedings() -> Array:
	if _seedings.is_empty() and FileAccess.file_exists(DATA):
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA))
		if d is Dictionary:
			for e in d["seedings"]["list"]:
				_seedings.append(PackedInt32Array(e["teams"]))
	return _seedings

func clear_series() -> void:
	gs.clear()
	for i in SERIES:
		gs.append({"team1": 0, "team2": 0, "wins": [0, 0], "gsper": 0, "score1": 0, "score2": 0, "flags": 0})

## The playing teams' TeamData by id (MatchConfig.available_teams).
func set_teams(list: Array) -> void:
	teams.clear()
	teams.resize(28)
	for t in list:
		if t and t.team_index >= 0 and t.team_index < 28:
			teams[t.team_index] = t

func team(id: int) -> TeamData:
	return teams[id] if id >= 0 and id < teams.size() else null

## GetShifter (L55429): (series this round - 1, tree offset).
func shifter() -> Vector2i:
	var d2 := -16
	var d1 := 16
	for i in gamelevel + 1:
		d2 += d1
		d1 >>= 1
	return Vector2i(d1 - 1, d2)

## A playoff is saved (sub_17CA0: gamelevel | bosgames != 0).
func in_progress() -> bool:
	return gamelevel | bosgames != 0

# --- the regular season --------------------------------------------------------------------

## sub_18002: 8 games between 16 distinct random teams 0-25, never the two playing.
func slate(rng: RetailRng, home: int, vis: int) -> void:
	gamenum = -1
	var used := (1 << home) | (1 << vis)
	for g in gs:
		var a := _option(rng, used)
		used |= 1 << a
		var b := _option(rng, used)
		used |= 1 << b
		g["team1"] = a
		g["team2"] = b

## OptionRNG (L55194): randomd0(26) until the team is free.
static func _option(rng: RetailRng, used: int) -> int:
	while true:
		var d := rng.range_(26)
		if used & (1 << d) == 0:
			return d
	return 0

# --- the scorer ----------------------------------------------------------------------------

## InitScores (L47726): the other series start 0-2 periods in (rounds 1-2 only).
func init_scores(rng: RetailRng) -> void:
	if gamelevel > 1:
		return
	var d1 := shifter().x
	for i in range(d1, -1, -1):
		var g: Dictionary = gs[i]
		if i == gamenum or g["flags"] & F_OVER:
			continue
		g["gsper"] = 0
		for k in rng.range_(3):
			set_score(rng, g)

## UpdateScores (L47757): one more period of every other game.
func update_scores(rng: RetailRng) -> void:
	var d1 := shifter().x
	for i in range(d1, -1, -1):
		var g: Dictionary = gs[i]
		if i == gamenum:
			continue
		g["flags"] &= ~F_HILITE
		if g["flags"] & F_OVER == 0:
			set_score(rng, g)

## SetScore (L47780): a period; after the third a game within a goal is flagged for a
## highlight and stays in the third.
func set_score(rng: RetailRng, g: Dictionary) -> void:
	if g["gsper"] >= 4:
		return
	if g["gsper"] == 3:
		g["gsper"] = GSPER_FINAL
		var diff: int = g["score1"] - g["score2"]
		if diff > 1 or diff < -1:
			return
		g["gsper"] = 3
		g["flags"] |= F_HILITE
		return
	g["gsper"] += 1
	g["score1"] += getscore(rng, g["team1"], g["team2"])
	g["score2"] += getscore(rng, g["team2"], g["team1"])

## getscore (L47815): goals in a period from a's offense nibble and b's defense nibble.
func getscore(rng: RetailRng, a: int, b: int) -> int:
	var ta := team(a)
	var tb := team(b)
	var ra: Array = SCTAB[clampi(ta.sim_offense if ta else 0, 0, 7)]
	var rb: Array = SCTAB[clampi(tb.sim_defense if tb else 0, 0, 7)]
	var wt := []
	var total := 0
	for k in 4:
		wt.append(ra[k] + rb[k])
		total += ra[k] + rb[k]
	var r := rng.range_(total)
	for k in range(3, -1, -1):
		r -= wt[k]
		if r < 0:
			return k
	return 0

## The games the ticker and Other Scores show: this round's series but the user's.
func shown_games() -> Array:
	var out := []
	for i in range(shifter().x, -1, -1):
		if i != gamenum:
			out.append(gs[i])
	return out

## sub_1381E: a flagged game whose highlight is skipped ends now; a tie goes to a side
## by the VDP counter's bit 0.
static func settle(g: Dictionary, coin: int) -> void:
	if g["score1"] == g["score2"]:
		if coin & 1:
			g["score1"] += 1
		else:
			g["score2"] += 1
	g["gsper"] = GSPER_FINAL

# --- the playoff tree ------------------------------------------------------------------------

## NewPO (L54901): a seeding holding the team (All-Stars play as Winnipeg), from a random
## start; single games (mode 2) or best of seven (mode 3).
func new_po(rng: RetailRng, team1: int, mode: int) -> void:
	var list := seedings()
	if list.is_empty():
		return
	var t := mini(team1, 25)
	var d0 := rng.range_(32)
	for n in 33:
		d0 = (d0 + 1) & 31
		var s: PackedInt32Array = list[d0]
		var at := s.find(t)
		if at >= 0:
			potreeteam = at
			postarts = d0
			break
	gamelevel = 0
	bosgames = SINGLE
	if mode == MODE_NEW7:
		bosgames = 0
		for g in gs:
			g["wins"] = [0, 0]
	make_tree()

## MakeTree (L54939): the tree from the bracket bits; this round's series with home ice
## (the second-listed team hosts games 1, 2, 5 and 7, and every single game).
func make_tree() -> void:
	var list := seedings()
	if list.is_empty():
		return
	var s: PackedInt32Array = list[postarts]
	for i in 16:
		tree[i] = s[i]
	var b := bits
	for k in 15:
		tree[16 + k] = tree[2 * k + (b & 1)]
		b >>= 1
	var sd := shifter()
	if sd.x < 0:
		return
	for i in sd.x + 1:
		var g: Dictionary = gs[i]
		g["score1"] = 0
		g["score2"] = 0
		g["gsper"] = 0
		g["flags"] &= ~F_HILITE
		var a := tree[2 * sd.y + 2 * i]
		var c := tree[2 * sd.y + 2 * i + 1]
		if bosgames in [2, 3, 5]:
			g["team1"] = a
			g["team2"] = c
			g["flags"] &= ~F_FLIPPED
		else:
			g["team1"] = c
			g["team2"] = a
			g["flags"] |= F_FLIPPED

## The user's team (tree[potreeteam]).
func user_team() -> int:
	return tree[potreeteam]

## FigureJoy's playoff branch (L55005): the user's series this round, its home and
## visitor, and the pads (cont1team, cont2team). Empty when the user is out.
func figure_joy() -> Dictionary:
	gamenum = -1
	var user := user_team()
	var d1 := shifter().x
	for i in range(d1, -1, -1):
		var g: Dictionary = gs[i]
		var side := -1
		if g["team1"] == user:
			side = 0
		elif g["team2"] == user:
			side = 4
		if side < 0:
			continue
		gamenum = i
		var p: Array = POJOYLIST[clampi(side + pojoy, 0, POJOYLIST.size() - 1)]
		return {"home": g["team1"], "visitor": g["team2"], "opponent": g["team2"] if side == 0 else g["team1"],
			"pads": PackedInt32Array([p[0], p[1], 0, 0])}
	return {}

# --- after a playoff game ----------------------------------------------------------------------

## sub_18380 (L55538): the user's game result, every series one game on (in best of seven),
## the round decided by coin flips once the user's series is, and the next round.
func advance(rng: RetailRng, hm_goals: int, aw_goals: int) -> void:
	alt_state = PackedInt32Array()
	if gamenum >= 0:
		gs[gamenum]["score1"] = hm_goals
		gs[gamenum]["score2"] = aw_goals
	var sd := shifter()
	if bosgames != SINGLE:
		for i in range(sd.x, -1, -1):
			var g: Dictionary = gs[i]
			if g["wins"][0] == 4 or g["wins"][1] == 4:
				continue
			var d3 := 1 if g["flags"] & F_FLIPPED else 0
			if g["score1"] < g["score2"]:
				d3 ^= 1
			g["wins"][d3] += 1
		bosgames += 1
		if bosgames != SINGLE:
			var u: Dictionary = gs[maxi(gamenum, 0)]
			if u["wins"][0] != 4 and u["wins"][1] != 4:
				return
			if gamelevel < 3:
				for i in range(sd.x, -1, -1):
					var g: Dictionary = gs[i]
					while g["wins"][0] != 4 and g["wins"][1] != 4:
						if rng.range_(200) & 1:
							g["wins"][1] += 1
						else:
							g["wins"][0] += 1
				alt_state = encode()
		var nb := 0
		for i in sd.x + 1:
			var g: Dictionary = gs[i]
			if g["wins"][0] != 4:
				nb |= 1 << i
			g["wins"] = [0, 0]
		bosgames = 0
		bits = (bits & ((1 << sd.y) - 1)) | (nb << sd.y)
		gamelevel += 1
		return
	var b := 0
	for i in sd.x + 1:
		var g: Dictionary = gs[i]
		var x := 1 if g["score1"] <= g["score2"] else 0
		if g["flags"] & F_FLIPPED:
			x ^= 1
		b |= x << i
	bits = (bits & ((1 << sd.y) - 1)) | (b << sd.y)
	gamelevel += 1

## sub_180FC (L55268): after a playoff game. Returns the play mode the menu comes back
## with: 1 (Continue) while the user is still in, else New Playoffs in the same format.
func after_game(rng: RetailRng, nop: int, mode: int, hm_goals: int, aw_goals: int, sram: Sram) -> int:
	if nop == 0 or mode == MODE_REGULAR or mode == MODE_SHOOTOUT:
		return mode
	advance(rng, hm_goals, aw_goals)
	make_tree()
	figure_joy()
	if gamelevel == 4 or gamenum < 0:
		var single := bosgames == SINGLE
		if sram:
			sram.save_playoffs(PackedInt32Array(), po_stats)
		return MODE_NEW if single else MODE_NEW7
	if sram:
		sram.save_playoffs(encode(), po_stats)
	if not alt_state.is_empty():
		decode(alt_state)
		make_tree()
	return MODE_CONTINUE

# --- the saved state ---------------------------------------------------------------------------

## sub_18192: the state as one 80-bit number, five big-endian words.
func encode() -> PackedInt32Array:
	var n := PackedInt32Array([0, 0, 0, 0, 0])
	var vals := [postarts, bosgames, gamelevel, potreeteam, pojoy, bits & 0x3FFF]
	for i in RADICES.size():
		_muladd(n, RADICES[i], vals[i])
	for g in gs:
		_muladd(n, 5, mini(g["wins"][0], 4))
		_muladd(n, 5, mini(g["wins"][1], 4))
	return n

## sub_1803E: the fields peeled off in reverse. With two pads a pojoy of 1 or 2 comes
## back as 4 (sub_17CA0 then makes it 2: Two - Teammates continues as Head to Head).
func decode(n: PackedInt32Array) -> void:
	var v := n.duplicate()
	for i in range(SERIES - 1, -1, -1):
		var g: Dictionary = gs[i]
		var b := _divmod(v, 5)
		var a := _divmod(v, 5)
		g["wins"] = [a, b]
		if a == 4 or b == 4:
			g["flags"] |= F_OVER
		else:
			g["flags"] &= ~F_OVER
	bits = _divmod(v, 0x4000)
	pojoy = _divmod(v, 8)
	if pojoy == 1 or pojoy == 2:
		pojoy = 4
	potreeteam = _divmod(v, 16)
	gamelevel = _divmod(v, 4)
	bosgames = _divmod(v, 8)
	postarts = _divmod(v, 32)

## sub_17CA0: Continue Playoffs from the saved state; false when there is none.
func continue_from(n: PackedInt32Array) -> bool:
	if n.size() != 5:
		gamelevel = 0
		bosgames = 0
		return false
	decode(n)
	if not in_progress():
		return false
	make_tree()
	if pojoy >= 2:
		pojoy -= 2
	return true

static func _muladd(n: PackedInt32Array, m: int, add: int) -> void:
	var carry := add
	for i in range(4, -1, -1):
		var x := n[i] * m + carry
		n[i] = x & 0xFFFF
		carry = x >> 16

static func _divmod(n: PackedInt32Array, d: int) -> int:
	var r := 0
	for i in 5:
		var x := (r << 16) | n[i]
		n[i] = x / d
		r = x % d
	return r

# --- playoff stats -----------------------------------------------------------------------------

## AddPOStats (L55445): the user's team's game added to the playoff totals, each entry
## clamped to its packed width.
func add_po_stats(st: TeamStats) -> void:
	var arrays := [st.player_goals, st.player_assists, st.player_shots, st.player_pim]
	for c in 4:
		for slot in 26:
			var i := 26 * c + slot
			var arr: PackedInt32Array = arrays[c]
			var v := po_stats[i] + (arr[slot] if slot < arr.size() else 0)
			po_stats[i] = mini(v, (1 << STAT_WIDTHS[(103 - i) & 3]) - 1)
