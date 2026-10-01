extends TestCase

const A := HoldemTable.Action


func _table(stacks: Array) -> HoldemTable:
	var t := HoldemTable.new()
	for i in stacks.size():
		t.add_seat("P%d" % i, i % 2, stacks[i])
	return t


func test_blinds_and_first_to_act_three_handed() -> void:
	var t := _table([1000, 1000, 1000])
	t.start_hand()
	check_eq(t.button, 0, "button")
	check_eq(t.seats[1].stack, 995, "small blind")
	check_eq(t.seats[2].stack, 990, "big blind")
	check_eq(t.to_act, 0, "first to act preflop is left of the big blind")
	check_eq(t.legal()["min_raise_to"], 20, "min raise is to two big blinds")


func test_heads_up_button_posts_small_blind_and_acts_first() -> void:
	var t := _table([1000, 1000])
	t.start_hand()
	check_eq(t.seats[0].stack, 995, "button posts the small blind")
	check_eq(t.to_act, 0, "button acts first preflop")
	t.act(A.CALL)
	t.act(A.CHECK)
	check_eq(t.street, HoldemTable.Street.FLOP)
	check_eq(t.to_act, 1, "big blind acts first after the flop")


func test_big_blind_gets_the_option() -> void:
	var t := _table([1000, 1000, 1000])
	t.start_hand()
	t.act(A.CALL)
	t.act(A.CALL)
	check_eq(t.street, HoldemTable.Street.PREFLOP, "still preflop")
	check_eq(t.to_act, 2, "big blind to act")
	check(t.legal()["can_check"], "big blind can check")
	t.act(A.CHECK)
	check_eq(t.street, HoldemTable.Street.FLOP)
	check_eq(t.board.size(), 3)


func test_everyone_folds_to_the_big_blind() -> void:
	var t := _table([1000, 1000, 1000])
	t.start_hand()
	t.act(A.FOLD)
	t.act(A.FOLD)
	check(t.hand_over, "hand over")
	check_eq([t.seats[0].stack, t.seats[1].stack, t.seats[2].stack], [1000, 995, 1005])
	check(t.last_result["uncontested"], "uncontested")


func test_reraise_raises_the_minimum() -> void:
	var t := _table([1000, 1000, 1000])
	t.start_hand()
	t.act(A.RAISE, 30)  # a raise of 20
	check_eq(t.legal()["min_raise_to"], 50, "next raise must be at least 20 more")
	t.act(A.RAISE, 35)  # too small: clamped up to 50
	check_eq(t.current_bet, 50)


func test_side_pots_pay_the_right_players() -> void:
	# A (button) has 100, B and C have 300. All in; A has aces, B kings, C queens.
	var t := _table([100, 300, 300])
	# Deal order: B, C, A, B, C, A, then the board.
	t.start_hand(Card.parse_many("Ks Qs As Kd Qd Ad 2c 7h 9c Jh 3d"))
	t.act(A.RAISE, 100)  # A all-in
	t.act(A.RAISE, 300)  # B all-in
	t.act(A.CALL)  # C calls all-in
	check(t.hand_over, "board runs out with everyone all-in")
	check_eq(t.board.size(), 5)
	var pots: Array = t.last_result["pots"]
	check_eq(pots.size(), 2, "main pot and one side pot")
	check_eq(pots[0]["amount"], 300, "main pot")
	check_eq(pots[1]["amount"], 400, "side pot")
	check_eq([t.seats[0].stack, t.seats[1].stack, t.seats[2].stack], [300, 400, 0])


func test_split_pot_odd_chip_goes_left_of_button() -> void:
	# Everyone plays the board's straight; B folds its small blind, so the pot is odd.
	var t := _table([1000, 1000, 1000])
	t.start_hand(Card.parse_many("Kd 2h 2c Kh 3h 3c 5d 6c 7h 8s 9d"))
	t.act(A.RAISE, 20)  # A
	t.act(A.FOLD)  # B
	t.act(A.CALL)  # C
	for _street in 3:
		t.act(A.CHECK)  # C
		t.act(A.CHECK)  # A
	check(t.hand_over, "showdown")
	check_eq(t.last_result["pots"][0]["amount"], 45)
	check_eq(t.seats[2].stack, 1003, "C is first left of the button: gets the odd chip")
	check_eq(t.seats[0].stack, 1002)


func test_all_in_on_the_blind_still_gets_cards() -> void:
	var t := _table([1000, 1000, 3])
	t.start_hand()
	check(t.seats[2].all_in, "big blind all-in for 3")
	check_eq(t.seats[2].hole.size(), 2, "still dealt in")
	t.act(A.CALL)
	t.act(A.CALL)
	while not t.hand_over:
		t.act(A.CHECK)
	check_eq(t.total_chips(), 2003, "no chips made or lost")


func test_busted_seats_sit_out_and_button_skips_them() -> void:
	var t := _table([1000, 0, 1000, 1000])
	t.start_hand()
	check_eq(t.button, 0)
	check(not t.seats[1].dealt, "busted seat isn't dealt in")
	check_eq(t.seats[2].stack, 995, "small blind skips the busted seat")
	while not t.hand_over:
		t.act(A.FOLD)
	t.start_hand()
	check_eq(t.button, 2, "button skips the busted seat")


func test_random_play_never_makes_or_loses_chips() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var hands := 0
	while hands < 600:
		var t := _table([500, 500, 500, 500, 500, 500])
		t.rng.seed = rng.randi()
		while t.players_with_chips() >= 2 and hands < 600:
			t.start_hand()
			hands += 1
			var actions := 0
			while not t.hand_over:
				var legal := t.legal()
				var roll := rng.randf()
				if roll < 0.15:
					t.act(A.FOLD)
				elif roll < 0.7:
					t.act(A.CALL)
				else:
					t.act(A.RAISE, rng.randi_range(legal["min_raise_to"], legal["max_raise_to"]))
				actions += 1
				if not check(t.total_chips() == 3000, "chips changed mid-hand"):
					return
				if not check(actions < 200, "hand never ended"):
					return
			var paid := 0
			for amount: int in t.last_result["payouts"].values():
				paid += amount
			var potted := 0
			for p: Dictionary in t.last_result["pots"]:
				potted += p["amount"]
			check_eq(paid, potted, "payouts equal the pots")
			for s in t.seats:
				if not check(s.stack >= 0, "negative stack"):
					return
	check_eq(hands, 600)


func test_a_fine_stays_in_the_pot_when_the_fined_seat_loses() -> void:
	# Heads-up: seat 0 (button, small blind) is fined 10 dead and loses a
	# checked-down hand to seat 1's aces. The fine used to count as a bet, so
	# seat 0's 10 extra came back to it as a side pot only it could win.
	var t := _table([1000, 1000])
	t.queue_dead_money(0, 10)
	# Deal order: seat 1, seat 0, seat 1, seat 0, then the board.
	t.start_hand(Card.parse_many("As 2c Ad 7d Kh Qh 9s 3c 4d"))
	check_eq(t.pot(), 25, "blinds and the fine")
	t.act(A.CALL)
	t.act(A.CHECK)
	while not t.hand_over:
		t.act(A.CHECK)
	check_eq([t.seats[0].stack, t.seats[1].stack], [980, 1020], "the fine is lost with the hand")
	check_eq(t.last_result["pots"].size(), 1, "dead money makes no side pot")


func test_a_seat_all_in_from_its_fine_can_win_only_the_dead_money() -> void:
	# Seat 0 (button) has 10 chips and is fined 10: all-in for nothing but
	# dead money. It holds aces and wins the main pot: the dead 10, not 10
	# from each player as if the fine were a bet.
	var t := _table([10, 1000, 1000])
	t.queue_dead_money(0, 10)
	# Deal order: seat 1, seat 2, seat 0, twice, then the board.
	t.start_hand(Card.parse_many("Kh 7c As Kd 2d Ad 3s 8h 9c Jd 4s"))
	check(t.seats[0].all_in, "the fine puts seat 0 all-in")
	t.act(A.CALL)  # small blind completes
	t.act(A.CHECK)  # big blind
	while not t.hand_over:
		t.act(A.CHECK)
	var pots: Array = t.last_result["pots"]
	check_eq(pots.size(), 2, "the dead money, then the blinds")
	check_eq([pots[0]["amount"], pots[0]["winners"]], [10, [0]], "seat 0 wins only the dead money")
	check_eq([pots[1]["amount"], pots[1]["winners"]], [20, [1]], "kings win the rest")
	check_eq([t.seats[0].stack, t.seats[1].stack, t.seats[2].stack], [10, 1010, 990])


func test_folding_to_a_short_all_in_big_blind_gets_the_excess_back() -> void:
	# Heads-up, the big blind has only 3 chips. The small blind (5 in) folds:
	# the big blind can win only 3 from it, so 2 come back. It used to lose
	# all 5.
	var t := _table([1000, 3])
	t.start_hand()
	check(t.seats[1].all_in, "big blind all-in for 3")
	t.act(A.FOLD)
	check(t.hand_over, "hand over")
	check_eq([t.seats[0].stack, t.seats[1].stack], [997, 6])
	check_eq(t.last_result["returned"], {0: 2}, "the uncalled 2 go back")


func test_an_uncalled_all_in_comes_back_before_the_pots() -> void:
	var t := _table([100, 300, 1000])
	t.start_hand()
	t.act(A.RAISE, 100)  # seat 0 all-in
	t.act(A.RAISE, 300)  # seat 1 all-in
	t.act(A.RAISE, 1000)  # seat 2 all-in: 700 of it nobody can call
	check(t.hand_over, "board runs out")
	check_eq(t.last_result["returned"], {2: 700})
	var pots: Array = t.last_result["pots"]
	check_eq(pots.map(func(p: Dictionary) -> int: return p["amount"]), [300, 400], "no pot of seat 2's own chips")
	check_eq(t.total_chips(), 1400, "no chips made or lost")


func test_an_unknown_action_folds_instead_of_passing() -> void:
	# An action id that isn't an Action used to mark the seat as having acted
	# without paying: it passed while facing a bet.
	var t := _table([1000, 1000, 1000])
	t.start_hand()
	t.act(99)  # seat 0, facing the big blind
	check(t.seats[0].folded, "folds")
	t.act(-1)  # seat 1, facing 5 more
	check(t.hand_over, "and so does seat 1: the big blind wins")
	check_eq([t.seats[0].stack, t.seats[1].stack, t.seats[2].stack], [1000, 995, 1005])


func test_misuse_between_and_during_hands_is_refused() -> void:
	# Asserts are stripped from release builds, so these were only guarded in
	# debug: a late act() played seats[-1] on a finished hand, and starting a
	# hand mid-hand threw away the chips in the pot.
	expect_errors(3)
	var t := _table([1000, 1000, 1000])
	t.start_hand()
	t.act(A.RAISE, 100)
	t.start_hand()  # mid-hand: refused
	check_eq(t.pot(), 115, "the pot is still there")
	check_eq(t.eject(1), 0, "no ejecting mid-hand")
	check_eq(t.seats[1].stack, 995)
	t.act(A.FOLD)
	t.act(A.FOLD)
	check(t.hand_over, "hand over")
	t.act(A.CALL)  # nobody is to act: refused
	check_eq(t.total_chips(), 3000, "no chips made or lost")
	check_eq(t.seats[2].stack, 990, "the last seat didn't call on a finished hand")
