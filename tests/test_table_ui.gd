extends TestCase
## The table scene's logic: the hand readout, raise sizes, animal tells and
## the animation timeline. (How it looks is checked by screenshots.)


func _say(hole: String, board: String) -> String:
	return HandReadout.describe(Card.parse_many(hole), Card.parse_many(board))


func test_readout_preflop() -> void:
	check_eq(_say("7c 7d", ""), "Pair of 7s")
	check_eq(_say("Ah Kh", ""), "Ace-King suited")
	check_eq(_say("9s Qd", ""), "Queen-9")
	check_eq(_say("Tc Td", ""), "Pair of 10s")


func test_readout_made_hands() -> void:
	check_eq(_say("7c 2d", "7h Kd 9s"), "Pair of 7s")
	check_eq(_say("Ac 2d", "7h Kd 5s 4c 3h"), "Straight to the 5")
	check_eq(_say("Kc 7d", "7h Kd 9s"), "Two pair, Kings and 7s")
	check_eq(_say("9c 9d", "9h Kd 2s"), "Three 9s")
	check_eq(_say("Ah 2h", "7h Kh 9h"), "Flush, Ace high")
	check_eq(_say("9c 9d", "9h 4d 4s"), "Full house, 9s over 4s")
	check_eq(_say("Qc Qd", "Qh Qs 2s"), "Four Queens")
	check_eq(_say("Ah Kh", "Qh Jh Th"), "Royal flush")
	check_eq(_say("9h 8h", "7h 6h 5h"), "Straight flush to the 9")
	check_eq(_say("Tc 3d", "Ah Kd Qs Jc 2h"), "Straight to the Ace")
	check_eq(_say("Ac 2d", "7h Jd 9s"), "Ace high")


func test_readout_draws_need_your_cards() -> void:
	check_eq(_say("Ah 2h", "7h Kh 9s"), "Ace high, flush draw")
	check_eq(_say("8c 7d", "6h 5d Ks"), "King high, straight draw")
	check_eq(_say("8c 7d", "6h 4d Ks"), "King high, straight draw", "a gutshot counts")
	check_eq(_say("Ac 2d", "7h 7d 7s 7c"), "Four 7s", "no draws past a made hand")
	check_eq(_say("2c 3d", "9h 8h 7h 6h"), "9 high", "four to a flush on the board is everyone's")
	check_eq(_say("Kc Kd", "9h 8s 7d 6c"), "Pair of Kings", "four to a straight on the board is everyone's")
	check_eq(_say("Ah 2h", "7h Kh 9s 4c 3d"), "Ace high", "no draws on the river")


func _legal(min_to: int, max_to: int, to_call: int) -> Dictionary:
	return {"min_raise_to": min_to, "max_raise_to": max_to, "to_call": to_call, "can_raise": max_to > min_to - to_call}


func test_raise_sizes_jump_through_the_pot() -> void:
	# Facing a bet of 20 into a pot of 50 (including that bet): call 20, pot is 70.
	var sizes := RaiseSizes.presets(_legal(40, 1000, 20), 20, 50)
	var names: Array = sizes.map(func(p: Dictionary) -> String: return p["name"])
	var amounts: Array = sizes.map(func(p: Dictionary) -> int: return p["to"])
	check_eq(names, ["Min", "Half pot", "Pot", "2x pot", "All-in"])
	check_eq(amounts, [40, 55, 90, 160, 1000])
	check_eq(RaiseSizes.step(sizes, 40, 1), 55)
	check_eq(RaiseSizes.step(sizes, 60, 1), 90, "from a nudged amount to the next size up")
	check_eq(RaiseSizes.step(sizes, 60, -1), 55)
	check_eq(RaiseSizes.step(sizes, 1000, 1), 1000, "stays at all-in")
	check_eq(RaiseSizes.step(sizes, 40, -1), 40, "stays at the minimum")
	check_eq(RaiseSizes.nudge(_legal(40, 1000, 20), 990, 20, 1), 1000)
	check_eq(RaiseSizes.name_of(sizes, 90), "Pot")
	check_eq(RaiseSizes.name_of(sizes, 91), "")


func test_raise_sizes_short_stack() -> void:
	# 100 behind: the pot fractions are past all-in, so only Min and All-in.
	var sizes := RaiseSizes.presets(_legal(40, 100, 20), 20, 200)
	check_eq(sizes.map(func(p: Dictionary) -> String: return p["name"]), ["Min", "All-in"])
	# Only enough to go all-in: one size, called All-in.
	sizes = RaiseSizes.presets(_legal(30, 30, 20), 20, 60)
	check_eq(sizes, [{"name": "All-in", "to": 30}] as Array[Dictionary])


func _tell(species: StringName, moment: AnimalTells.Moment, hole: String, board: String, action: int, roll := 0.0) -> bool:
	return AnimalTells.fires(species, moment, Card.parse_many(hole), Card.parse_many(board), action, roll)


func test_tells_follow_the_species() -> void:
	var A := HoldemTable.Action
	var M := AnimalTells.Moment
	check(_tell(&"owl", M.ACTED, "As Ad", "", A.CALL), "owl hoots with aces")
	check(not _tell(&"owl", M.ACTED, "7s 2d", "", A.CALL), "owl quiet with junk")
	check(not _tell(&"owl", M.ACTED, "As Ad", "", A.FOLD), "no tell on a fold")
	check(_tell(&"raccoon", M.ACTED, "7s 2d", "Kh 9c 4d", A.RAISE), "raccoon rubs its paws bluffing")
	check(not _tell(&"raccoon", M.ACTED, "Ks 2d", "Kh 9c 4d", A.RAISE), "not when it has top pair")
	check(not _tell(&"raccoon", M.ACTED, "7s 2d", "Kh 9c 4d", A.CALL), "calling isn't bluffing")
	check(_tell(&"goose", M.FLOP, "Ks Qd", "Kh 9c 4d", -1), "goose honks at top pair on the flop")
	check(not _tell(&"goose", M.FLOP, "7s 2d", "Kh 9c 4d", -1), "goose quiet at a miss")
	check(not _tell(&"goose", M.ACTED, "Ks Qd", "Kh 9c 4d", A.RAISE), "goose's tell is the flop itself")
	check(_tell(&"cat", M.ACTED, "9s 9d", "9h Kc 4d", A.RAISE), "cat's tail with a set")
	check(_tell(&"squirrel", M.THINKING, "7s 2d", "", A.CALL), "squirrel restacks before calling")
	check(not _tell(&"squirrel", M.ACTED, "7s 2d", "", A.CALL), "squirrel's tell comes before the call")
	check(not _tell(&"squirrel", M.THINKING, "7s 2d", "", A.RAISE))
	check(_tell(&"possum", M.ACTED, "9s 9d", "9h Kc 4d", A.CALL), "possum still with a set")
	check(not _tell(&"possum", M.ACTED, "Ks Qd", "Kh 9c 4d", A.CALL), "top pair isn't a monster")
	check(not _tell(&"owl", M.ACTED, "As Ad", "", A.CALL, 0.9), "only some of the time")
	check(not _tell(&"dog", M.ACTED, "As Ad", "", A.CALL), "unknown species have no tell")
	check(AnimalTells.log_line(&"cat", "Tom") == "Tom's tail flicks.")


func test_tell_strength_counts_only_your_cards() -> void:
	var S := AnimalTells.Strength
	var st := func(hole: String, board: String) -> int:
		return AnimalTells.strength(Card.parse_many(hole), Card.parse_many(board))
	check_eq(st.call("7s 2d", "Kh Kc 4d"), S.WEAK, "the board's pair is everyone's")
	check_eq(st.call("Ks 2d", "Kh Kc 4d"), S.MONSTER, "trips with a king in hand")
	check_eq(st.call("Qs Qd", "Jh 9c 4d"), S.STRONG, "overpair")
	check_eq(st.call("9s 2d", "Kh 9c 4d"), S.MEDIUM, "middle pair")
	check_eq(st.call("Ks Kd", ""), S.MONSTER)
	check_eq(st.call("As Qd", ""), S.STRONG)
	check_eq(st.call("5s 5d", ""), S.MEDIUM)
	check_eq(st.call("2s 7d", ""), S.WEAK)
	check_eq(st.call("2s 3d", "Ah Kh Qh Jh Th"), S.WEAK, "playing the board")


func test_tells_fire_about_half_the_time() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var shown := 0
	for i in 1000:
		if _tell(&"owl", AnimalTells.Moment.ACTED, "As Ad", "", HoldemTable.Action.RAISE, rng.randf()):
			shown += 1
	check(shown > 440 and shown < 560, "shown %d of 1000" % shown)


func test_motion_books_beats_one_after_another() -> void:
	var m := TableMotion.new()
	var flop := m.reserve(10.0, 0.3)
	var turn := m.reserve(10.0, 0.3)  # same instant, e.g. an all-in run-out
	var river := m.reserve(10.0, 0.3)
	check_eq(flop, 10.0)
	check(is_equal_approx(turn, 10.3) and is_equal_approx(river, 10.6), "queued, not stacked: %s %s" % [turn, river])
	check(m.busy(10.8))
	check(not m.busy(10.95))
	check_eq(m.reserve(20.0, 0.2), 20.0, "an idle timeline starts now")
	var card := m.add(&"card", 30.0, 0.2, {"seat": 3})
	check_eq(m.active(29.9).size(), 0, "not in flight before its start")
	check_eq(m.active(30.1).size(), 1)
	check(is_equal_approx(card["p"], 0.5))
	check_eq(m.active(30.25).size(), 0, "landed")
	m.prune(31.0)
	check_eq(m.items.size(), 0)
	check_eq(TableMotion.ease_out(0.0), 0.0)
	check_eq(TableMotion.ease_out(1.0), 1.0)
	check(TableMotion.ease_out(0.5) > 0.5, "eases out")


func test_command_menu_grid() -> void:
	var m := CommandMenu.new()
	check_eq(m.current(), CommandMenu.Item.CALL, "starts on Call")
	m.move(Vector2i.RIGHT)
	check_eq(m.current(), CommandMenu.Item.RAISE)
	m.move(Vector2i.RIGHT)
	check_eq(m.current(), CommandMenu.Item.RAISE, "stops at the edge")
	m.move(Vector2i.DOWN)
	check_eq(m.current(), CommandMenu.Item.HELP)
	m.move(Vector2i.LEFT)
	check_eq(m.current(), CommandMenu.Item.FOLD)
	m.move(Vector2i.DOWN)
	check_eq(m.current(), CommandMenu.Item.FOLD, "stops at the bottom")
	m.enabled[CommandMenu.Item.FOLD] = false
	check_eq(m.choose(), -1, "a greyed-out item does nothing")
	m.move(Vector2i.UP)
	check_eq(m.choose(), CommandMenu.Item.CALL)
	m.move(Vector2i.RIGHT)
	m.reset()
	check_eq(m.current(), CommandMenu.Item.CALL)


func test_feed_types_lines_out_when_due() -> void:
	var f := TableFeed.new()
	f.add("Honk raises to 60!", Color.WHITE, 1.0)
	f.add("Honk wins 120!", Color.WHITE, 5.0)  # booked for when the pot moves
	f.add("Sage folds.", Color.WHITE, 2.0)
	var shown := f.visible(3.0)
	check_eq(shown.map(func(l: Dictionary) -> String: return l["text"]), ["Honk raises to 60!", "Sage folds."], "the win isn't shown early")
	check_eq(f.visible(6.0)[-1]["text"], "Honk wins 120!")
	check_eq(TableFeed.typed(f.visible(5.05)[-1], 5.05), "Honk", "types out")
	check(f.typing(5.05))
	check(not f.typing(9.0))
	f.add("Same time, said second", Color.WHITE, 2.0)
	check_eq(f.visible(2.5)[-1]["text"], "Same time, said second", "same moment keeps the order said")
	for i in 20:
		f.add("line %d" % i, Color.WHITE, 10.0 + i)
	check_eq(f.lines.size(), TableFeed.KEEP, "keeps only the recent lines")
