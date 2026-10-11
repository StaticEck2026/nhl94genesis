class_name Collisions
extends RefCounted
## Player-vs-player collision. Port of checkplcoll (L48570) and checkcx (L48617) with the
## exact integer momentum exchange, plus the sprite Y-sort that decides which neighbours
## are tested and in what order (checkcoll L48484, SprSort L53612).
## Spec: docs/specs/collisions_checking.md.

## Neighbours within this many pixels of sort Y are tested.
const SORT_WINDOW := 0x10
## Bodies touch when dx^2 + dy^2 <= $100 (16 px).
const TOUCH_SQ := 0x100
## Mass offset added to the weight byte.
const MASS_BASE := 0x8C

## Value checkint returns when nobody fell (d1 untouched).
const D1_UNCHANGED := 1 << 24

var w: HockeyWorld
## evalue: elasticity * 16. The ROM only ever writes 0 (L48644).
var evalue: int = 0

func _init(world: HockeyWorld) -> void:
	w = world

## SprSort: rebuild the Y order from scratch (ascending Y, ties by object number).
func sort_all() -> void:
	var order: Array = range(HockeyWorld.SORT_OBJS)
	order.sort_custom(func(a: int, b: int) -> bool:
		var ya := w.objects[a].y()
		var yb := w.objects[b].y()
		return ya < yb or (ya == yb and a < b))
	w.oo_list.resize(HockeyWorld.SORT_OBJS)
	w.oo_pos.resize(HockeyWorld.SORT_OBJS)
	w.ylist.resize(HockeyWorld.SORT_OBJS)
	for k in order.size():
		var i: int = order[k]
		w.oo_list[k] = i
		w.oo_pos[i] = k
		w.ylist[i] = w.objects[i].y()

## checkcoll step 7: bubble this object to keep ascending Ylist order, keyed by d3.
func resort(o: SimObject, d3: int) -> void:
	var me := o.index
	var k := w.oo_pos[me]
	while k != HockeyWorld.SORT_OBJS - 1:
		var nxt := w.oo_list[k + 1]
		if not d3 > w.ylist[nxt]:
			break
		w.oo_list[k] = nxt
		w.oo_list[k + 1] = me
		w.oo_pos[me] += 1
		w.oo_pos[nxt] -= 1
		k += 1
	while k > 0:
		var prv := w.oo_list[k - 1]
		if not d3 < w.ylist[prv]:
			break
		w.oo_list[k] = prv
		w.oo_list[k - 1] = me
		w.oo_pos[me] -= 1
		w.oo_pos[prv] += 1
		k -= 1
	w.ylist[me] = d3

## checkplcoll: walk up, then down, the Y order while neighbours are within 16 px.
func checkplcoll(o: SimObject, d2: int, d3: int) -> void:
	if o.flags2 & SimObject.PF2_NOCOLL:
		return
	if o.index > 11:
		return
	var d1 := w.oo_pos[o.index]
	while d1 != HockeyWorld.SORT_OBJS - 1:
		var other := w.oo_list[d1 + 1]
		var d5 := w.ylist[other] - d3
		if d5 > SORT_WINDOW:
			break
		checkcx(o, w.objects[other], d2, d5)
		d1 += 1
	d1 = w.oo_pos[o.index]
	while d1 != 0:
		var other := w.oo_list[d1 - 1]
		var d5 := d3 - w.ylist[other]
		if d5 > SORT_WINDOW:
			return
		checkcx(o, w.objects[other], d2, d5)
		d1 -= 1

## checkcx: circle test, impact and check events for opponents, then the momentum
## exchange (only the first pair per checkcoll call).
func checkcx(a3: SimObject, a2: SimObject, d2: int, d5: int) -> void:
	if a2.flags & SimObject.PF_NC:
		return
	if a2.flags2 & SimObject.PF2_NOCOLL:
		return
	if a2.index > 11:
		return
	var d0 := HockeyWorld.s16(a2.x() - d2)
	if d0 < -0x10 or d0 > 0x10:
		return
	if d5 * d5 + d0 * d0 > TOUCH_SQ:
		return
	evalue = 0
	var teams_differ := (a3.flags ^ a2.flags) & SimObject.PF_TEAM != 0
	var vx := HockeyWorld.s16(a3.vel.x - a2.vel.x)
	var vy := HockeyWorld.s16(a3.vel.y - a2.vel.y)
	var dx := HockeyWorld.s16(a2.x() - a3.x())
	var dy := HockeyWorld.s16(a2.y() - a3.y())
	var p := vx * dx + vy * dy
	if p < 0:
		return
	var d1 := p >> 4
	if teams_differ:
		var d4 := (d1 & 0xFFFF) >> 8
		if d4 <= 5:
			d4 = 5
		a3.impact = HockeyWorld.s16(a3.impact + d4)
		a2.impact = HockeyWorld.s16(a2.impact + d4)
		if not a2.fighting():
			a2.impactp = a3.index
		if not a3.fighting():
			a3.impactp = a2.index
		if d4 >= 0x14 and (w.puckc == a3.index or w.puckc == a2.index):
			w.checking.newcheck()
		# Quirk Q1: checkint saves only d0, so a fall it causes leaks into V1n.
		var leaked := w.checking.checkint(a3, a2)
		if leaked != D1_UNCHANGED:
			d1 = leaked
		w.checking.checkcheck(a3, a2, d4)
	var v1n := HockeyWorld.s16(d1)
	if w.collflag < 0:
		return
	exchange(a3, a2, vx, vy, dx, dy, v1n)
	w.collflag = -1

## The momentum exchange (checkcx L48700-48756). Integer for integer with the ROM.
func exchange(a3: SimObject, a2: SimObject, vx: int, vy: int, dx: int, dy: int, v1n: int) -> void:
	var v1t := HockeyWorld.s16((vx * dy - vy * dx) >> 4)
	var m1 := (a3.weight & 0xFF) + MASS_BASE
	var m2 := (a2.weight & 0xFF) + MASS_BASE
	var d7 := ((evalue * m2) & 0xFFFF) >> 4
	var num := HockeyWorld.s16(m1 - d7)
	var den := HockeyWorld.s16(m1 + m2)
	var v1n_new := HockeyWorld.s16(_divs(v1n * num, den))
	var t := HockeyWorld.s16(evalue * v1n) >> 4
	var v2n_new := HockeyWorld.s16(v1n_new + t)
	var a2x := a2.vel.x
	var a2y := a2.vel.y
	a3.vel.x = HockeyWorld.s16(HockeyWorld.s16((v1t * dy + v1n_new * dx) >> 4) + a2x)
	a3.vel.y = HockeyWorld.s16(HockeyWorld.s16((v1n_new * dy - v1t * dx) >> 4) + a2y)
	a2.vel.x = HockeyWorld.s16(a2x + HockeyWorld.s16((v2n_new * dx) >> 4))
	a2.vel.y = HockeyWorld.s16(a2y + HockeyWorld.s16((v2n_new * dy) >> 4))

## divs: signed 32/16, quotient truncated toward zero.
static func _divs(a: int, b: int) -> int:
	if b == 0:
		return 0
	var q := absi(a) / absi(b)
	return q if (a >= 0) == (b >= 0) else -q
