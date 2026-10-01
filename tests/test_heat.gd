extends TestCase

const A := HoldemTable.Action
const D := Dealer.Kind


## A 3v3 match with no bots (we drive the table by hand), seats alternating
## teams, 1000 chips each.
func _match(dealer: int) -> TeamMatch:
	var m := TeamMatch.new()
	m.heat.dealer = Dealer.preset(dealer)
	for i in 6:
		m.add_player("P%d" % i, i % 2, 1000, null)
	return m


func _fold_out(m: TeamMatch) -> void:
	while not m.table.hand_over:
		m.table.act(A.FOLD)


func _total(m: TeamMatch) -> int:
	return m.table.total_chips() + m.removed_chips


func test_no_dealer_no_heat() -> void:
	var m := _match(D.STREET)
	m.start_hand()
	for _i in 5:
		m.talk.send(0, TableTalk.Sig.STRONG, 0)
	check_eq(m.heat.level(0), 0.0, "street games have nobody watching")


func test_repeat_signals_in_a_hand_cost_more() -> void:
	var m := _match(D.WATCHFUL)  # 12 a signal
	m.start_hand()
	m.talk.send(0, TableTalk.Sig.STRONG, 0)
	check_eq(m.heat.level(0), 12.0, "first signal")
	m.talk.send(2, TableTalk.Sig.WEAK, 0)
	check_eq(m.heat.level(0), 36.0, "the crew's second this hand costs double, whoever makes it")
	m.talk.send(1, TableTalk.Sig.WEAK, 0)
	check_eq(m.heat.level(1), 12.0, "the other crew counts separately")


func test_heat_cools_after_each_hand() -> void:
	var m := _match(D.WATCHFUL)  # cools 4 a hand
	m.start_hand()
	m.talk.send(0, TableTalk.Sig.STRONG, 0)
	_fold_out(m)
	check_eq(m.heat.level(0), 8.0)
	m.start_hand()
	m.talk.send(0, TableTalk.Sig.STRONG, 0)
	check_eq(m.heat.level(0), 20.0, "a new hand starts the repeat count over")


func test_a_warning_fires_once_until_the_crew_cools_down() -> void:
	var m := _match(D.WATCHFUL)
	var warnings := [0]
	m.heat.warned.connect(func(_team: int, _seat: int) -> void: warnings[0] += 1)
	m.start_hand()
	m.talk.send(0, TableTalk.Sig.STRONG, 0)
	m.talk.send(0, TableTalk.Sig.STRONG, 0)  # 36
	m.talk.send(0, TableTalk.Sig.STRONG, 0)  # 72: warned
	_fold_out(m)
	for _hand in 2:
		m.start_hand()
		m.talk.send(0, TableTalk.Sig.STRONG, 0)  # hovering above the line
		_fold_out(m)
	check_eq(warnings[0], 1, "warned once while hovering")
	m.heat.heat[0] = 22.0
	m.start_hand()
	_fold_out(m)  # cools by 4 to 18, under half the warning line: re-armed
	m.start_hand()
	for _i in 3:
		m.talk.send(0, TableTalk.Sig.STRONG, 0)
	check_eq(warnings[0], 2, "warned again after cooling off")


func test_warning_then_fine_posts_dead_blinds_next_hand() -> void:
	var m := _match(D.WATCHFUL)
	var events := []
	m.heat.warned.connect(func(team: int, _seat: int) -> void: events.append(["warned", team]))
	m.heat.fined.connect(func(team: int, _seat: int) -> void: events.append(["fined", team]))
	m.start_hand()
	for _i in 3:
		m.talk.send(0, TableTalk.Sig.STRONG, 0)  # 12 + 24 + 36 = 72
	check_eq(events, [["warned", 0], ["fined", 0]])
	_fold_out(m)
	var before := [m.table.seats[0].stack, m.table.seats[2].stack, m.table.seats[4].stack]
	m.start_hand()  # blinds 5/10; button moves to seat 1, blinds on seats 2 and 3
	check_eq(m.table.seats[0].stack, before[0] - 10, "fined a dead big blind")
	check_eq(m.table.seats[2].stack, before[1] - 10 - 5, "fined, and posts the small blind")
	check_eq(m.table.seats[4].stack, before[2] - 10, "fined a dead big blind")
	check_eq(m.table.pot(), 5 + 10 + 30, "dead money is in the pot")
	check_eq(m.table.current_bet, 10, "dead money isn't a bet")
	_fold_out(m)
	check_eq(_total(m), 6000, "no chips made or lost")
	m.start_hand()
	check_eq(m.table.pot(), 15, "fined once, not every hand")


func test_ejection_removes_the_seat_after_the_hand() -> void:
	var m := _match(D.STRICT)  # 20 a signal
	var called := []
	m.heat.ejection_called.connect(func(_team: int, seat: int) -> void: called.append(seat))
	m.start_hand()
	for _i in 3:
		m.talk.send(4, TableTalk.Sig.STRONG, 0)  # 20 + 40 + 60 = 120
	check_eq(called, [4])
	check(not m.table.seats[4].ejected, "still playing until the hand ends")
	check_eq(m.heat.level(0), Heat.AFTER_EJECTION, "the floor keeps watching")
	var chips := m.table.seats[4].stack + m.table.seats[4].hand_bet
	_fold_out(m)
	check(m.table.seats[4].ejected, "thrown out")
	check_eq(m.table.seats[4].stack, 0)
	check_eq(m.removed_chips, chips + m.table.last_result["payouts"].get(4, 0), "its chips left the game")
	check_eq(_total(m), 6000, "every chip accounted for")
	m.start_hand()
	check(not m.table.seats[4].dealt, "never dealt in again")


func test_bought_dealer_looks_away_from_the_boss_crew() -> void:
	var m := _match(D.BOUGHT)  # boss crew is team 1
	m.start_hand()
	m.talk.send(1, TableTalk.Sig.STRONG, 0)
	m.talk.send(0, TableTalk.Sig.STRONG, 0)
	check_eq(m.heat.level(1), 3.0, "a quarter of the heat for the boss crew")
	check_eq(m.heat.level(0), 12.0)


func test_catching_the_boss_wins_the_match() -> void:
	var m := _match(D.STRICT)
	m.leaders = {1: 3}
	m.start_hand()
	for _i in 3:
		m.talk.send(3, TableTalk.Sig.STRONG, 0)
	_fold_out(m)
	check(m.is_over(), "the boss crew is done")
	check_eq(m.winner(), 0, "the crew that got them caught wins")


func _signals_sent(caution: float, team_heat: float) -> int:
	# Seat 3 (first to act, team 1) holds 7-2: a weak hand it would normally
	# tell its teammates about. Hole cards go seat 1, 2, 3, 4, 5, 0, twice.
	var m := _match(D.STRICT)
	var style := PlayStyle.preset(PlayStyle.Kind.SHARK)
	style.chattiness = 1.0
	style.caution = caution
	var bot := PokerBot.new(style, 5)
	bot.heat = m.heat
	bot.equity_iterations = 2000  # so 7-2 reads as weak every time
	m.start_hand(Card.parse_many("8h 9h 7c Jd Qs Tc Ah Ac 2s 3c 3h 4d"))
	var sent := 0
	for i in 20:
		m.talk.clear()
		m.heat.heat[1] = team_heat
		m.heat._gestures_this_hand.clear()
		bot._signalled_street = -1
		bot.decide(m.table, 3, m.talk)
		sent += m.talk.sent.size()
	return sent


func test_cautious_animals_go_quiet_when_the_dealer_is_suspicious() -> void:
	check_eq(_signals_sent(1.0, 0.0), 20, "nothing to fear yet")
	check_eq(_signals_sent(1.0, 30.0), 0, "a careful one won't push past the warning")
	check_eq(_signals_sent(0.0, 30.0), 20, "a careless one doesn't care yet")
	var reckless := _signals_sent(0.0, 90.0)
	check(reckless >= 4 and reckless <= 16, "past its line, a careless one forgets it about half the time: %d of 20" % reckless)


func test_both_leaders_caught_is_a_draw() -> void:
	var m := _match(D.STRICT)
	m.leaders = {0: 0, 1: 3}
	m.start_hand()
	for _i in 3:
		m.talk.send(0, TableTalk.Sig.STRONG, 0)
		m.talk.send(3, TableTalk.Sig.STRONG, 0)
	_fold_out(m)
	check(m.is_over(), "both crews are done")
	check_eq(m.winner(), -1, "nobody wins when both bosses are caught")
