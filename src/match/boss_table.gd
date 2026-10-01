class_name BossTable
extends RefCounted
## Boss tables (docs/DESIGN.md): a boss brings a bigger crew than yours
## (3v4, 3v5, up to 3v6 at a 9-seat full ring), led by a LEADER. Pure
## functions, no nodes: who sits where and with how many chips, so the seat
## draw and the stacks are tested and simulated headless
## (tests/test_boss_table.gd, tools/boss_sim.gd). TeamMatch applies the
## leader rule; this only builds the table.
##
## - **Stacks:** the boss crew brings the same total as your crew (your
##   crew's size x the table's chips), spread over more seats: the leader
##   holds two shares, every goon one. 3v4 at 1000: the leader 1200, three
##   goons 600; 3v5: 1000 and 500s; 3v6: 860 and 428s (the leader takes the
##   odd chips, so the totals match exactly). Shallow goons are what makes
##   picking them off early swing the numbers; the big-stack leader is the
##   one to bust (TeamMatch.leaderless: without it the goons stop
##   signalling and play scared).
## - **The rigged seat draw:** the boss boxes you in and splits your crew
##   up. Its leader sits directly after you (it acts behind you every hand),
##   a goon directly before you, and from 3v5 up two of them on each side;
##   your teammates are spread round the ring with boss seats between them,
##   so nobody on your crew sits next to anybody else on it. The table shows
##   the draw and says it was rigged; seeing it coming (reads) or changing
##   it (bribing the dealer) is for later. A fair draw (random, seeded) is
##   there to measure the rig against.
##
##   Tried first: the boss in the seats nearest yours and your teammates
##   side by side across the table. It looked like boxing you in, but it
##   helped your crew: bot crews won 51.0% of 3v4 Opens that way against
##   42.5% with your crew split up (tools/boss_sim.gd, seed 50001, 200
##   matches each, the same deals), so the rig splits your crew instead.
## Seat 0 is always you, in both draws: the table and its layout count on it.

## Shares of the boss crew's chips: the leader holds this many, a goon one.
const LEADER_SHARES := 2
## The boss crew's chips over yours: 1.0, the same total, as designed.
## It's a knob, measured with tools/boss_sim.gd --edge (your five test
## crews against the Regulars, bot vs bot): at 1.4 your crews won 48.0%
## against 51.0% at 1.0 (seed 50001, 200 matches each: inside the noise);
## at 1.5, 37% against 51% (seed 10, 150 each). Chips move a boss table
## less than who's playing: see README, "Boss tables".
const CHIP_EDGE := 1.0


## Starting chips for the boss crew, leader first: `boss` seats sharing
## `mine` x `base` chips (see the top). `shares`: the leader's stack in
## goon stacks (tools/boss_sim.gd --shares tries others).
static func stacks(mine: int, boss: int, base: int, shares := LEADER_SHARES, edge := CHIP_EDGE) -> Array[int]:
	var total := roundi(mine * base * edge)
	var goon := total / (boss - 1 + shares)
	var out: Array[int] = [total - goon * (boss - 1)]
	for _i in boss - 1:
		out.append(goon)
	return out


## Who sits in each seat, as [team, index in that team's list] for seat 0,
## 1, 2...: team 0 is your crew (index 0 is you), team 1 the boss crew (index
## 0 its leader). `rigged`: the boss's draw (see the top); otherwise a fair,
## random one from `draw_seed`.
static func seat_order(mine: int, boss: int, rigged := true, draw_seed := 0) -> Array[Vector2i]:
	var n := mine + boss
	var order: Array[Vector2i] = []
	order.resize(n)
	order.fill(Vector2i(-1, -1))
	order[0] = Vector2i(0, 0)
	if not rigged:
		# Fair: everyone but you drawn at random.
		var slots: Array[Vector2i] = []
		for k in range(1, mine):
			slots.append(Vector2i(0, k))
		for b in boss:
			slots.append(Vector2i(1, b))
		var rng := RandomNumberGenerator.new()
		rng.seed = hash("seat draw %d" % draw_seed)
		for k in range(slots.size() - 1, 0, -1):
			var j := rng.randi_range(0, k)
			var t := slots[k]
			slots[k] = slots[j]
			slots[j] = t
		for k in slots.size():
			order[k + 1] = slots[k]
		return order
	# Your teammates spread round the ring (seat k * n / mine)...
	for k in range(1, mine):
		order[roundi(float(k * n) / mine) % n] = Vector2i(0, k)
	# ...and the boss crew in the rest, nearest you first: the seat after
	# yours, the one before, the next ones out (1, n-1, 2, n-2...).
	var b := 0
	for k in range(1, n):
		var seat := (k + 1) / 2 if k % 2 == 1 else n - k / 2
		if order[seat].x < 0:
			order[seat] = Vector2i(1, b)
			b += 1
	return order


## The table's `setup` for a boss match: `mine` is your side (you first, as
## {"name", "animal"}), `boss` the boss crew (leader first). Each seat gets
## its team, its starting `chips` (yours: `base`; the boss crew's: stacks())
## and the leader is marked `"leader": true`. `crew_id` names the boss crew
## for interception's code book, as in GameState.table_setup.
static func setup(mine: Array[Dictionary], boss: Array[Dictionary], base: int, rigged := true, crew_id := "",
		shares := LEADER_SHARES, edge := CHIP_EDGE, draw_seed := 0) -> Array[Dictionary]:
	var chips := stacks(mine.size(), boss.size(), base, shares, edge)
	var out: Array[Dictionary] = []
	for slot in seat_order(mine.size(), boss.size(), rigged, draw_seed):
		var seat: Dictionary
		if slot.x == 0:
			seat = mine[slot.y].duplicate()
			seat["team"] = 0
			seat["chips"] = base
		else:
			seat = boss[slot.y].duplicate()
			seat["team"] = 1
			seat["chips"] = chips[slot.y]
			if slot.y == 0:
				seat["leader"] = true
			if crew_id:
				seat["crew"] = crew_id
		out.append(seat)
	return out


## The seat of the crew's leader in a setup, or -1.
static func leader_seat(table_setup: Array[Dictionary]) -> int:
	for i in table_setup.size():
		if table_setup[i].get("leader", false):
			return i
	return -1
