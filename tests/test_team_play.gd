extends TestCase

const K := PlayStyle.Kind


func _crew_match(seed_value: int, kinds: Array) -> TeamMatch:
	var m := TeamMatch.new(seed_value)
	for i in kinds.size():
		var bot := PokerBot.new(PlayStyle.preset(kinds[i]), seed_value * 10 + i + 1)
		bot.equity_iterations = 60
		m.add_player("P%d" % i, i % 2, 1000, bot)
	m.max_hands = 400
	return m


func test_bot_match_finishes_and_keeps_every_chip() -> void:
	var m := _crew_match(3, [K.SHARK, K.MANIAC, K.ROCK, K.CALLING_STATION, K.BLUFFER, K.SHARK])
	var winner := m.run_to_end()
	check(winner == 0 or winner == 1, "a crew wins")
	check_eq(m.team_chips(0) + m.team_chips(1), 6000, "chips conserved")
	check(m.table.hand_number < 400, "ends before the safety limit (%d hands)" % m.table.hand_number)


func test_teammates_never_raise_each_other() -> void:
	var m := _crew_match(5, [K.MANIAC, K.MANIAC, K.MANIAC, K.MANIAC, K.MANIAC, K.MANIAC])
	var violations := [0]
	var t := m.table
	t.action_taken.connect(func(seat: int, action: int, _amount: int) -> void:
		if action != HoldemTable.Action.RAISE:
			return
		for i in t.seats.size():
			if t.seats[i].live() and t.seats[i].team != t.seats[seat].team:
				return
		violations[0] += 1)
	m.run_to_end()
	check_eq(violations[0], 0, "raises with only teammates left in the pot")


func _signal_scenario(teammate_signals_strong: bool) -> int:
	# Seat 0 (to act) holds A-K suited: playable, but not a monster to this
	# tight a style.
	# Seat 2, its teammate, is in the big blind.
	var t := HoldemTable.new()
	t.add_seat("Owl", 0, 1000)
	t.add_seat("Goose", 1, 1000)
	t.add_seat("Cat", 0, 1000)
	t.start_hand(Card.parse_many("7c 4d Ac 2h 5s Kc 3d 8h 9s Qd Jd"))
	var talk := TableTalk.new()
	if teammate_signals_strong:
		talk.send(2, TableTalk.Sig.STRONG, t.street)
	var style := PlayStyle.preset(K.SHARK)
	style.aggression = 0.0
	style.bluff_rate = 0.0
	style.stickiness = 0.0
	style.chattiness = 0.0
	style.tightness = 1.2
	var bot := PokerBot.new(style, 42)
	bot.bond = 1.0
	bot.equity_iterations = 2000
	return bot.decide(t, 0, talk)["action"]


func test_steps_aside_when_teammate_signals_strength() -> void:
	check_eq(_signal_scenario(false), HoldemTable.Action.CALL, "plays A-K normally")
	check_eq(_signal_scenario(true), HoldemTable.Action.FOLD, "folds it when the teammate is strong")


func test_weak_bond_misreads_some_signals() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var misread := 0
	for i in 400:
		var talk := TableTalk.new()
		talk.send(1, TableTalk.Sig.STRONG, 0)
		if talk.read_from(0, 1, 0.0, rng)[0] != TableTalk.Sig.STRONG:
			misread += 1
	# bond 0 misreads half the time
	check(misread > 160 and misread < 240, "misread %d of 400, expected ~200" % misread)
	var talk := TableTalk.new()
	talk.send(1, TableTalk.Sig.ATTACK, 0)
	var first := talk.read_from(0, 1, 0.0, rng)[0]
	for _i in 20:
		check_eq(talk.read_from(0, 1, 0.0, rng)[0], first, "a misread stays the same misread")
