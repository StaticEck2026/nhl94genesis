class_name Records
extends RefCounted
## sub_F9CDE (L965016; spec docs/specs/playoffs_records.md §8.3): the battery-saved
## records at the end of a game, with User Records On and a valid save RAM. Every "best"
## is replaced only when strictly greater (signed bytes, as retail compares them).
## - players: each slot's best game (goals; for a goalie, saves = shots - goals against);
## - teams: goals, the best goalie's saves, and the home team's crowd peak;
## - users: games (to 9000), wins and ties, and the best goals and saves in a win.

## users: [home user, away user] (ids 0-7, 0 = no name).
static func update(sram: Sram, w: HockeyWorld, users: Array) -> void:
	if sram == null or not sram.valid():
		return
	var ids := [w.stats[0].team_index, w.stats[1].team_index]
	if ids[0] < 0 or ids[1] < 0:
		return
	for t in 2:
		_players(sram, w.stats[t], ids[t], users[t], users[1 - t], ids[1 - t])
	for t in 2:
		_team(sram, w, t, ids, users)
	for t in 2:
		_user(sram, w, t, ids, users)
	sram.commit()

static func _sb(v: int) -> int:
	v &= 0xFF
	return v - 256 if v >= 128 else v

## sub_F9F50.
static func _players(sram: Sram, st: TeamStats, team: int, own: int, opp_user: int, opp_team: int) -> void:
	var goalies := st.data.goalie_count if st.data else 2
	var n := st.data.players.size() if st.data else 0
	for slot in mini(n, 26):
		var best := st.player_goals[slot]
		if slot < goalies:
			best = maxi(st.player_shots[slot] - st.player_goals[slot], 0)
		var rec := sram.player_record(team, slot)
		if _sb(best) > _sb(rec[0]):
			sram.set_player_record(team, slot, PackedByteArray([best & 0xFF, own, opp_team, opp_user]))

## sub_F9EAA.
static func _team(sram: Sram, w: HockeyWorld, t: int, ids: Array, users: Array) -> void:
	var st := w.stats[t]
	var rec := sram.team_record(ids[t])
	var tail := [users[t], ids[1 - t], users[1 - t]]
	var goals := st.goals
	if _sb(goals) > _sb(rec[0]):
		_put(rec, 0, goals, tail)
	var goalies := st.data.goalie_count if st.data else 2
	var saves := 0
	for slot in goalies:
		saves = maxi(saves, st.player_shots[slot] - st.player_goals[slot])
	if _sb(saves) > _sb(rec[4]):
		_put(rec, 4, saves, tail)
	if t == 0:
		var crowd := w.rules.crowd_peak
		if _sb(crowd) > _sb(rec[8]):
			_put(rec, 8, crowd, tail)
	sram.set_team_record(ids[t], rec)

## sub_F9DDA.
static func _user(sram: Sram, w: HockeyWorld, t: int, ids: Array, users: Array) -> void:
	var u: int = users[t]
	var rec := sram.user_record(u)
	var own := w.stats[t].goals
	var opp := w.stats[1 - t].goals
	var games := Sram.word(rec, 10)
	if games < 9000:
		Sram.set_word(rec, 10, games + 1)
		if own > opp:
			Sram.set_word(rec, 8, Sram.word(rec, 8) + 1)
		elif own == opp:
			Sram.set_word(rec, 12, Sram.word(rec, 12) + 1)
	if own > opp:
		var tail := [ids[t], ids[1 - t], users[1 - t]]
		if _sb(own) > _sb(rec[0]):
			_put(rec, 0, own, tail)
		var o := w.stats[1 - t]
		var saves := maxi(o.shots - o.goals, 0)
		if _sb(saves) > _sb(rec[4]):
			_put(rec, 4, saves, tail)
	sram.set_user_record(u, rec)

static func _put(rec: PackedByteArray, at: int, v: int, tail: Array) -> void:
	rec[at] = v & 0xFF
	for i in 3:
		rec[at + 1 + i] = int(tail[i]) & 0xFF
