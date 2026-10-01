extends TestCase
## Boss tables: the boss crew's stacks, the rigged seat draw (and a fair
## one to compare), the setup the table gets, the leader rule (a busted
## leader leaves its goons silent and scared), uneven crews through a whole
## bot match, and the Mossbank Open's final as a 3v4 boss table, including
## saves from before it was one.

const A := HoldemTable.Action
const K := PlayStyle.Kind


## A run past Mossbank's open table, where Sage and Bandit join: a new game
## no longer starts with them (docs/DEMO_SPEC.md, demo 2), and the rules
## tested here are about a run with its crew.
func _crewed() -> GameState:
	var s := GameState.fresh()
	s.join_open_table_crew()
	return s


func test_the_boss_crew_brings_your_chips_spread_leader_heavy() -> void:
	check_eq(BossTable.stacks(3, 4, 1000), [1200, 600, 600, 600] as Array[int], "3v4: the leader holds two goons' worth")
	check_eq(BossTable.stacks(3, 5, 1000), [1000, 500, 500, 500, 500] as Array[int], "3v5")
	check_eq(BossTable.stacks(3, 6, 1000), [860, 428, 428, 428, 428, 428] as Array[int], "3v6: the leader takes the odd chips")
	for boss in range(3, 7):
		for base in [200, 500, 1000, 777]:
			var total := 0
			for c in BossTable.stacks(3, boss, base):
				total += c
			check_eq(total, 3 * base, "3v%d at %d: the same total as your crew" % [boss, base])
	check_eq(BossTable.stacks(3, 4, 1000, 3), [1500, 500, 500, 500] as Array[int], "a three-share leader")


func test_the_rigged_draw_boxes_you_in_and_splits_your_crew() -> void:
	check_eq(BossTable.seat_order(3, 4), [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 2),
			Vector2i(1, 3), Vector2i(0, 2), Vector2i(1, 1)] as Array[Vector2i], "3v4, seat by seat")
	check_eq(BossTable.seat_order(3, 3), [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 2),
			Vector2i(0, 2), Vector2i(1, 1)] as Array[Vector2i], "3v3 alternates, as the road's tables do")
	for boss in range(3, 7):
		var order := BossTable.seat_order(3, boss)
		var n := order.size()
		check_eq(n, 3 + boss)
		check_eq(order[0], Vector2i(0, 0), "3v%d: you in seat 0" % boss)
		check_eq(order[1], Vector2i(1, 0), "3v%d: the leader acts right after you" % boss)
		check_eq(order[n - 1].x, 1, "3v%d: a goon right before you" % boss)
		if boss >= 5:
			check(order[2].x == 1 and order[n - 2].x == 1, "3v%d: two of them on each side of you" % boss)
		for seat in n:
			if order[seat].x == 0:
				check_eq(order[(seat + 1) % n].x, 1, "3v%d: nobody on your crew next to anybody else on it" % boss)
		_check_everyone_once(order, boss)


func test_a_fair_draw_is_random_but_repeatable() -> void:
	var seen := {}
	for draw in 20:
		var order := BossTable.seat_order(3, 4, false, draw)
		check_eq(order[0], Vector2i(0, 0), "you in seat 0")
		check_eq(order, BossTable.seat_order(3, 4, false, draw), "the same seed, the same draw")
		_check_everyone_once(order, 4)
		seen[str(order)] = true
	check(seen.size() >= 10, "20 draws, %d different seatings" % seen.size())


func _check_everyone_once(order: Array[Vector2i], boss: int) -> void:
	var seen := {}
	for slot in order:
		check(not seen.has(slot), "%s seated twice" % slot)
		seen[slot] = true
	for k in 3:
		check(seen.has(Vector2i(0, k)), "your crew's %d seated" % k)
	for k in boss:
		check(seen.has(Vector2i(1, k)), "boss crew's %d seated" % k)


func test_setup_carries_teams_chips_and_the_leader() -> void:
	var mine: Array[Dictionary] = [{"name": "You", "animal": null}, {"name": "Sage", "animal": null}, {"name": "Bandit", "animal": null}]
	var boss: Array[Dictionary] = []
	for b in ["Graves", "Tom", "Bramble", "Dusty"]:
		boss.append({"name": b, "animal": null})
	var seats := BossTable.setup(mine, boss, 1000, true, "mossbank_regulars")
	check_eq(seats.size(), 7)
	var names: Array[String] = []
	for s in seats:
		names.append(s["name"])
	check_eq(names, ["You", "Graves", "Sage", "Bramble", "Dusty", "Bandit", "Tom"] as Array[String])
	check_eq(BossTable.leader_seat(seats), 1)
	check_eq(seats[1]["chips"], 1200, "the leader's big stack")
	check_eq(seats[3]["chips"], 600, "a goon's short one")
	check_eq(seats[2]["chips"], 1000, "yours")
	check_eq(seats[1].get("crew"), "mossbank_regulars", "the boss crew carries its id (interception's code book)")
	check(not seats[2].has("crew"), "your crew doesn't")
	check_eq(boss[0].has("team"), false, "the input isn't changed")
	for s in seats:
		check_eq(s["team"], 0 if s["name"] in ["You", "Sage", "Bandit"] else 1, s["name"])


func test_a_led_boss_crew_plays_its_best_hand() -> void:
	check_eq(_goon_with_kings(true), A.FOLD, "Kings step aside: the leader holds Aces, and the crew knows it")
	check(_goon_with_kings(false) != A.FOLD, "on its own cards, a goon plays Kings")


## What a goon (seat 1, Kings) does when its leader (seat 2) holds Aces.
func _goon_with_kings(led: bool) -> int:
	var m := TeamMatch.new(1)
	m.add_player("You", 0, 1000, null)
	m.add_player("Goon", 1, 1000, PokerBot.new(PlayStyle.preset(K.SHARK), 7))
	m.add_player("Boss", 1, 1000, null)
	m.add_player("Other", 0, 1000, null)
	if led:
		m.set_leader(1, 2)
	check_eq(m.bots[1].knows_crew_cards, led)
	m.start_hand(Card.parse_many("Kh Ac 7d 2c Ks As 8d 3c 9h 4s Jd 5c Qh"))
	m.table.act(A.CALL)  # seat 3
	m.table.act(A.CALL)  # you
	return m.bots[1].decide(m.table, 1, m.talk)["action"]


## A 3-seat match: you (seat 0, 1000), the boss leader (seat 1) and a goon
## (seat 2, 1000), both bots, the leader on `leader_chips`.
func _leader_match(leader_chips: int) -> TeamMatch:
	var m := TeamMatch.new(5)
	m.add_player("You", 0, 1000, null)
	m.add_player("Boss", 1, leader_chips, PokerBot.new(PlayStyle.preset(K.ROCK), 11))
	m.add_player("Goon", 1, 1000, PokerBot.new(PlayStyle.preset(K.SHARK), 12))
	m.set_leader(1, 1)
	return m


func test_busting_the_leader_leaves_the_goons_leaderless() -> void:
	var m := _leader_match(10)
	var lost := []
	m.leader_lost.connect(func(team: int) -> void: lost.append(team))
	# Button seat 0, so the leader posts the small blind (5) and the goon the
	# big (10). Deal from the button's left: leader, goon, you, twice; then
	# the board. You hold Aces, the leader 7-2, the goon 3-2.
	m.start_hand(Card.parse_many("7c 3d Ah 2s 2h As Kd 9c 8s 4h Jd"))
	check_eq(m.table.to_act, 0, "you act first preflop")
	m.table.act(A.CALL)  # you call 10
	m.table.act(A.CALL)  # the leader calls its last 5: all-in
	m.table.act(A.CHECK)  # the goon checks
	while not m.table.hand_over:
		m.table.act(A.CHECK)
	check_eq(m.table.seats[1].stack, 0, "the leader busted")
	check_eq(m.leaderless, {1: 1}, "its crew went leaderless on hand 1")
	check_eq(lost, [1], "and the table was told, once")
	check(m.bots[2].leaderless and m.bots[1].leaderless, "every bot on the crew knows")
	check(not m.bots[2].knows_crew_cards, "and the crew stops playing as one")
	check(not m.is_over(), "the goon plays on: busting the boss isn't catching it")
	m.start_hand()
	m.table.act(A.FOLD)
	check_eq(lost, [1], "not told again")


func test_a_leaderless_goon_goes_quiet_and_plays_scared() -> void:
	var style := PlayStyle.preset(K.SHARK)
	var bot := PokerBot.new(style, 3)
	bot.lose_leader()
	check_eq(bot.style.tightness, style.tightness * PokerBot.LEADERLESS_TIGHTNESS, "tighter")
	check_eq(bot.style.bluff_rate, style.bluff_rate * PokerBot.LEADERLESS_BLUFFS, "fewer bluffs")
	check_eq(bot.style.stickiness, style.stickiness * PokerBot.LEADERLESS_STICKINESS, "fewer loose calls")
	check_eq(style.tightness, PlayStyle.preset(K.SHARK).tightness, "the style it had is untouched (a copy)")
	bot.lose_leader()
	check_eq(bot.style.tightness, style.tightness * PokerBot.LEADERLESS_TIGHTNESS, "once only")
	check_eq(_signals(false), 20, "with its leader, a chatty goon tells its crew it's weak every time")
	check_eq(_signals(true), 0, "without, never")


## Signals a chatty goon (seat 2, holding 7-2) sends over 20 decisions.
func _signals(leaderless: bool) -> int:
	var m := TeamMatch.new(1)
	m.add_player("You", 0, 1000, null)
	m.add_player("Mate", 1, 1000, null)
	var style := PlayStyle.preset(K.SHARK)
	style.chattiness = 1.0
	var bot := PokerBot.new(style, 5)
	bot.equity_iterations = 2000  # so 7-2 reads as weak every time
	if leaderless:
		bot.lose_leader()
	m.add_player("Goon", 1, 1000, bot)
	m.add_player("Other", 0, 1000, null)
	# Button 0: seat 1 posts the small blind, seat 2 the big, seat 3 acts first.
	m.start_hand(Card.parse_many("Ah 7c Kd Qs As 2s Kc Qh 8h 9h Jd 3c 4c"))
	m.table.act(A.RAISE, 40)
	m.table.act(A.FOLD)
	var sent := 0
	for i in 20:
		m.talk.clear()
		bot._signalled_street = -1
		bot.decide(m.table, 2, m.talk)
		sent += m.talk.sent.size()
	return sent


func test_a_whole_boss_match_keeps_every_chip() -> void:
	for boss in range(4, 7):
		var mine: Array[Dictionary] = []
		for k in 3:
			mine.append({"name": "M%d" % k, "animal": null})
		var crew: Array[Dictionary] = []
		for k in boss:
			crew.append({"name": "B%d" % k, "animal": null})
		var seats := BossTable.setup(mine, crew, 300, true)
		var m := TeamMatch.new(40 + boss)
		var kinds := [K.SHARK, K.ROCK, K.BLUFFER, K.MANIAC, K.CALLING_STATION]
		for i in seats.size():
			var bot := PokerBot.new(PlayStyle.preset(kinds[i % kinds.size()]), 100 + i)
			bot.equity_iterations = 40
			m.add_player(seats[i]["name"], seats[i]["team"], seats[i]["chips"], bot)
		m.set_leader(1, BossTable.leader_seat(seats))
		m.heat.dealer = Dealer.preset(Dealer.Kind.BOUGHT)
		m.max_hands = 300
		var w := m.run_to_end()
		check(w == 0 or w == 1, "3v%d: a crew wins (%d)" % [boss, w])
		check_eq(m.table.total_chips() + m.removed_chips, 1800, "3v%d: every chip accounted for" % boss)


func test_the_open_is_a_three_on_four_boss_table() -> void:
	var regulars: Dictionary = WorldMap.get_map("hall").crews[0]
	check_eq(regulars["id"], "mossbank_regulars")
	check(regulars.get("boss", false), "a boss crew")
	check_eq(regulars["dealer"], Dealer.Kind.ASLEEP, "Lou stays asleep: it's the first town")
	var rivals := WorldMap.crew_animals(regulars)
	check_eq(rivals.size(), 4, "four Regulars")
	check_eq(rivals[0].name, "Graves", "led by their captain")
	var s := _crewed()
	var seats := s.boss_table_setup(rivals, regulars["id"], regulars["chips"])
	check_eq(seats.size(), 7, "3v4")
	check_eq(seats[0]["name"], "You")
	check_eq(seats[1]["name"], "Graves")
	check(seats[1].get("leader", false), "Graves leads")
	check_eq(seats[1]["chips"], 1200, "with a big stack")
	check_eq(seats[6]["team"], 1, "a Regular on your other side too")
	check_eq([seats[2]["name"], seats[5]["name"]], ["Sage", "Bandit"], "your crew split up")
	var cells := WorldMap.crew_cells(regulars)
	check_eq(cells.size(), 4, "all four stand in the hall")
	var hall := WorldMap.get_map("hall")
	for cell in cells:
		check(hall.tile_walkable(cell), "%s stands on the floor" % cell)


## A save the game wrote before the Open was a boss table (same version,
## same keys): it loads, the Open is 3v4 for it, and what it learned of the
## Regulars' code still applies (the crew's id is the same).
func test_saves_from_before_boss_tables_still_load() -> void:
	var old := {"version": 1, "roster": [{"species": "owl", "name": "Sage", "bond": 0.6},
		{"species": "raccoon", "name": "Bandit", "bond": 0.55}, {"species": "goose", "name": "Honk", "bond": 0.2}],
		"party": [2, 0], "money": 320, "bracelets": [], "beaten": ["pond_hecklers"], "map": "hall", "cell": [9, 8],
		"facing": [0, -1], "heal_map": "diner", "heal_cell": [5, 3], "tutorial_offered": true, "tutorial_done": false,
		"seen_intro": true, "seen": {}, "recruited": {}, "found_at": {},
		"codebook": {"player": {"mossbank_regulars": {"0": 1}}}, "pending_recruit": "", "demo_complete_seen": false}
	var s := GameState.from_dict(JSON.parse_string(JSON.stringify(old)))
	if not check(s != null, "loads"):
		return
	check_eq(s.money, 320)
	check_eq(s.cell, Vector2i(9, 8))
	var regulars: Dictionary = WorldMap.get_map("hall").crews[0]
	var seats := s.boss_table_setup(WorldMap.crew_animals(regulars), regulars["id"], 1000)
	check_eq(seats.size(), 7)
	check_eq([seats[2]["name"], seats[5]["name"]], ["Honk", "Sage"], "the saved party sits down")
	check_eq(s.codebook.learned(CrewCode.PLAYER, "mossbank_regulars"), {0: 1}, "the cracked gesture is still known")
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	check_eq(back.to_dict(), s.to_dict(), "and saves again the same")
