extends TestCase
## Demo 2's cash game (docs/DEMO_SPEC.md, S-CASH and S-BUYIN): Mossbank's
## open table, CashMatch. Every seat plays for itself, chips are conserved
## hand after hand, you leave only between hands and take your stack with
## you, a busted rival leaves the table, and the match ends when you bust,
## leave, or hold every chip. Sitting down takes the buy-in from your money
## and leaving puts your stack back, to the chip.
##
## The exact cases use stacked decks and ScriptedBots (src/tutorial/), so
## every chip is known in advance; the long runs use seeded sessions with
## random policies at every seat, yours included. The hands are dealt the
## way HoldemTable deals: one card at a time from the seat after the button
## (seat 0, the first hand's button), twice round, then the board.
##
## Written before CashMatch (test first): red until the open-table agent
## builds it, and listed in tests/expected_red.txt until then. Every test
## first checks the table really seated everyone, so the stub fails a check
## rather than a script error.

const YOU := 0
const DRY_BOARD := "Kd Qc 8s 5d 3h"  ## pairs nothing below, makes no straight or flush with the hands used


## A cash match with you (seat 0, played by the test) and `rivals`
## ([name, chips, bot]); fails a check and returns null if they aren't all
## seated, each on its own team.
func _match(you_chips: int, rivals: Array, seed_value := 1) -> CashMatch:
	var m := CashMatch.new(seed_value)
	m.add_player("You", you_chips, null)
	for r: Array in rivals:
		m.add_player(r[0], r[1], r[2])
	if not check_eq(m.table.seats.size(), rivals.size() + 1, "S-CASH: add_player seats every player: seats"):
		return null
	return m


## Plays the current hand out: bots through play_bots(), you by `policy`
## (a Callable taking the table, returning [action, amount]). False (with a
## failure) if the hand doesn't finish.
func _play_hand(m: CashMatch, policy: Callable) -> bool:
	for _i in 400:
		m.play_bots()
		if m.table.hand_over:
			return true
		if m.table.to_act != YOU:
			return check(false, "S-CASH: play_bots() stopped with seat %d to act, not you" % m.table.to_act)
		var a: Array = policy.call(m.table)
		m.table.act(a[0], a[1])
	return check(false, "S-CASH: a hand didn't finish in 400 actions")


func _stacks(m: CashMatch) -> Array[int]:
	var out: Array[int] = []
	for s in m.table.seats:
		out.append(s.stack)
	return out


static func _fold(_t: HoldemTable) -> Array:
	return [HoldemTable.Action.FOLD, 0]


static func _check_call(_t: HoldemTable) -> Array:
	return [HoldemTable.Action.CALL, 0]


## S-CASH: you and 2-5 others, each on its own team; seat 0 is you.
func test_S_CASH_seats_you_and_two_to_five_others_each_on_their_own() -> void:
	for others in range(2, 6):
		var rivals := []
		for i in others:
			rivals.append(["Rival %d" % i, 200, ScriptedBot.new({"default": "check_call"})])
		var m := _match(200, rivals)
		if m == null:
			return
		var teams := {}
		for s in m.table.seats:
			teams[s.team] = true
		check_eq(teams.size(), others + 1, "S-CASH: %d players on their own teams: distinct teams" % (others + 1))
		check_eq(m.table.seats[YOU].name, "You", "S-CASH: seat 0")
		check_eq(m.bots[YOU], null, "S-CASH: your seat has no bot")
		check(not m.is_over(), "S-CASH: a match with %d players isn't over before it starts" % (others + 1))


## S-CASH: a rival who busts leaves the table; the winner's chips are
## exact. You (AA) raise, the Rat folds, Shorty (40 chips, 72o) calls all
## in and busts; the 60 nobody called comes back.
func test_S_CASH_busted_rival_leaves_the_table() -> void:
	var m := _match(500, [["Rat", 500, ScriptedBot.new({"default": "fold"})], ["Shorty", 40, ScriptedBot.new({"default": "check_call"})]])
	if m == null:
		return
	# Dealt from seat 1: Rat 9c, Shorty 7d, you Ah, Rat 4h, Shorty 2s, you As.
	m.start_hand(Card.parse_many("9c 7d Ah 4h 2s As " + DRY_BOARD))
	if not check(not m.table.hand_over and m.table.big_blind < 40, "S-CASH: a hand starts (blinds under Shorty's 40)"):
		return
	var sb := m.table.small_blind
	check(_play_hand(m, func(_t: HoldemTable) -> Array: return [HoldemTable.Action.RAISE, 100]), "S-CASH: the hand plays out")
	check_eq(_stacks(m), [540 + sb, 500 - sb, 0] as Array[int], "S-CASH: stacks after AA beats Shorty's all-in:")
	check(m.seat_left(2), "S-CASH: busted Shorty has left the table")
	check(not m.seat_left(1), "S-CASH: the Rat is still seated")
	check(not m.seat_left(YOU), "S-CASH: you're still seated")
	check(not m.is_over(), "S-CASH: you and the Rat still have chips: not over")
	check_eq(m.table.total_chips(), 1040, "S-CASH: chips on the table")
	m.start_hand()
	check(not m.table.seats[2].dealt, "S-CASH: Shorty isn't dealt in again")


## S-CASH: the match ends when you bust (and leaving then takes nothing).
func test_S_CASH_over_when_you_bust() -> void:
	var m := _match(40, [["Big", 500, ScriptedBot.new({"default": "check_call"})], ["Rat", 500, ScriptedBot.new({"default": "fold"})]])
	if m == null:
		return
	# Big Ah, Rat 9c, you 7d, Big As, Rat 4h, you 2s.
	m.start_hand(Card.parse_many("Ah 9c 7d As 4h 2s " + DRY_BOARD))
	if not check(not m.table.hand_over, "S-CASH: a hand starts"):
		return
	var bb := m.table.big_blind
	check(_play_hand(m, func(_t: HoldemTable) -> Array: return [HoldemTable.Action.RAISE, 40]), "S-CASH: the hand plays out")
	check_eq(_stacks(m), [0, 540 + bb, 500 - bb] as Array[int], "S-CASH: stacks after your 72o loses to Big's AA:")
	check(m.is_over(), "S-CASH: you busted: the match is over")
	check_eq(m.leave(), 0, "S-CASH: leaving busted takes")


## S-CASH: the match ends when you're the last one with chips.
func test_S_CASH_over_when_you_hold_every_chip() -> void:
	var m := _match(500, [["Ann", 40, ScriptedBot.new({"default": "check_call"})], ["Bo", 40, ScriptedBot.new({"default": "check_call"})]])
	if m == null:
		return
	# Ann 9c, Bo 7d, you Ah, Ann 4h, Bo 2s, you As.
	m.start_hand(Card.parse_many("9c 7d Ah 4h 2s As " + DRY_BOARD))
	if not check(not m.table.hand_over, "S-CASH: a hand starts"):
		return
	check(_play_hand(m, func(_t: HoldemTable) -> Array: return [HoldemTable.Action.RAISE, 100]), "S-CASH: the hand plays out")
	check_eq(_stacks(m), [580, 0, 0] as Array[int], "S-CASH: stacks after AA beats both all-ins:")
	check(m.seat_left(1) and m.seat_left(2), "S-CASH: both busted rivals left")
	check(m.is_over(), "S-CASH: you hold every chip: the match is over")
	check_eq(m.leave(), 580, "S-CASH: leaving takes your stack:")


## S-CASH: you can leave only between hands; leaving returns exactly your
## stack, ends the match and stands you up.
func test_S_CASH_leave_only_between_hands_with_your_stack() -> void:
	var m := _match(500, [["Ann", 500, ScriptedBot.new({"default": "check_call"})], ["Bo", 500, ScriptedBot.new({"default": "check_call"})]])
	if m == null:
		return
	m.start_hand(Card.parse_many("9c 7d Ah 4h 2s As " + DRY_BOARD))
	m.play_bots()
	if not check(not m.table.hand_over and m.table.to_act == YOU, "S-CASH: mid-hand, your turn (you're on the button)"):
		return
	check(not m.can_leave(), "S-CASH: can't leave mid-hand")
	check_eq(m.leave(), -1, "S-CASH: leave() mid-hand refuses:")
	check_eq(m.table.seats[YOU].stack, 500, "S-CASH: a refused leave changes nothing: your stack")
	check(not m.table.hand_over, "S-CASH: a refused leave doesn't end the hand")
	check(_play_hand(m, _fold), "S-CASH: the hand plays out")
	check(m.can_leave(), "S-CASH: between hands you can leave")
	check(not m.is_over(), "S-CASH: not over before you leave")
	var stack := m.table.seats[YOU].stack
	check_eq(stack, 500, "S-CASH: folding the button costs nothing: your stack")
	check_eq(m.leave(), stack, "S-CASH: leave() returns your stack:")
	check(m.is_over(), "S-CASH: leaving ends the match")
	check(m.seat_left(YOU), "S-CASH: you've left your seat")
	check(not m.can_leave(), "S-CASH: you can't leave twice")


## S-CASH: every hand conserves chips (what's on the table, plus what's
## left with leavers, never changes), over seeded sessions of random play
## at 3-6 seats.
func test_S_CASH_every_hand_conserves_chips() -> void:
	var policies := ["check_call", "fold", "bet:0.5", "bluff:1.0", "call_upto:60", "raise_to:80"]
	for seed_value in range(1, 31):
		var rng := RandomNumberGenerator.new()
		rng.seed = hash("cash:%d" % seed_value)
		var rivals := []
		for i in rng.randi_range(2, 5):
			var policy: String = policies[rng.randi_range(0, policies.size() - 1)]
			rivals.append(["R%d" % i, rng.randi_range(30, 400), ScriptedBot.new({"default": policy})])
		var m := _match(rng.randi_range(30, 400), rivals, seed_value)
		if m == null:
			return
		var total := m.table.total_chips()
		for hand in 40:
			if m.is_over():
				break
			m.start_hand()
			if not check(not m.table.hand_over, "S-CASH: seed %d hand %d didn't start" % [seed_value, hand]):
				return
			if not _play_hand(m, func(t: HoldemTable) -> Array: return _random_action(t, rng)):
				return
			if not check_eq(m.table.total_chips(), total, "S-CASH: seed %d after hand %d: chips on the table" % [seed_value, hand]):
				return
			for i in m.table.seats.size():
				check(m.table.seats[i].stack >= 0, "S-CASH: seed %d: seat %d negative" % [seed_value, i])
				if i != YOU and m.table.seats[i].stack == 0:
					check(m.seat_left(i), "S-CASH: seed %d: seat %d busted but still seated" % [seed_value, i])


static func _random_action(t: HoldemTable, rng: RandomNumberGenerator) -> Array:
	var legal := t.legal()
	var r := rng.randf()
	if r < 0.15:
		return [HoldemTable.Action.FOLD, 0]
	if r < 0.75 or not legal["can_raise"]:
		return [HoldemTable.Action.CALL, 0]
	return [HoldemTable.Action.RAISE, rng.randi_range(legal["min_raise_to"], legal["max_raise_to"])]


## S-BUYIN: sitting down takes the buy-in from your money, or refuses (and
## takes nothing) if you can't cover it; leaving adds your stack back:
## money after = money before - buy-in + stack at leaving, exactly, over
## 200 seeded sessions.
func test_S_BUYIN_money_after_is_money_before_minus_buy_in_plus_stack() -> void:
	var policies := ["check_call", "fold", "bet:0.5", "bluff:1.0", "call_upto:60"]
	var refused := 0
	var played := 0
	for seed_value in range(1, 201):
		var rng := RandomNumberGenerator.new()
		rng.seed = hash("buyin:%d" % seed_value)
		var s := GameState.fresh()
		s.money = rng.randi_range(0, 400)
		var buy_in: int = [50, 100, 150, 200][rng.randi_range(0, 3)]
		var before := s.money
		if before < buy_in:
			if not check(not CashMatch.sit_down(s, buy_in), "S-BUYIN: seed %d: $%d can't cover a $%d buy-in, but sat down" % [seed_value, before, buy_in]):
				return
			if not check_eq(s.money, before, "S-BUYIN: seed %d: a refused buy-in leaves money at" % seed_value):
				return
			refused += 1
			continue
		if not check(CashMatch.sit_down(s, buy_in), "S-BUYIN: seed %d: $%d covers a $%d buy-in, but sit_down refused" % [seed_value, before, buy_in]):
			return
		if not check_eq(s.money, before - buy_in, "S-BUYIN: seed %d: money after sitting down" % seed_value):
			return
		var rivals := []
		for i in rng.randi_range(2, 5):
			rivals.append(["R%d" % i, rng.randi_range(50, 300), ScriptedBot.new({"default": policies[rng.randi_range(0, policies.size() - 1)]})])
		var m := _match(buy_in, rivals, seed_value)
		if m == null:
			return
		for _hand in rng.randi_range(0, 25):
			if m.is_over():
				break
			m.start_hand()
			if not _play_hand(m, func(t: HoldemTable) -> Array: return _random_action(t, rng)):
				return
		var stack := m.table.seats[YOU].stack
		var took := m.leave()
		if not check_eq(took, stack, "S-BUYIN: seed %d: leave() returns your stack" % seed_value):
			return
		CashMatch.cash_out(s, took)
		if not check_eq(s.money, before - buy_in + stack, "S-BUYIN: seed %d: money $%d - $%d buy-in + $%d stack =" % [seed_value, before, buy_in, stack]):
			return
		played += 1
	check(refused > 10 and played > 100, "S-BUYIN: the seeds cover both cases (%d refused, %d played)" % [refused, played])
