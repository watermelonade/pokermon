extends SceneTree
## Long fuzzing soak for the rules engine (too slow for the test suite):
##
##   godot --headless --path . -s tools/soak_rules.gd -- [hands] [seed] [--bots=N]
##
## Plays random tables through tests/table_fuzzer.gd, which checks every
## invariant after every action and settles every hand again with an
## independent model (see that file). With --bots=N it also plays N crew
## matches of real bots under a strict dealer (signals, fines, ejections),
## checking that every chip is accounted for after every action and that
## every hand and match ends. Prints what was exercised and the first
## failures, and exits non-zero if there were any.
##
## Measured: 20,000 hands in about 19s; seeds 1-3 at 20,000 hands each, no
## failures.

const Fuzzer := preload("res://tests/table_fuzzer.gd")
const K := PlayStyle.Kind


func _init() -> void:
	var args: Array[String] = []
	var bot_matches := 0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--bots="):
			bot_matches = int(arg.get_slice("=", 1))
		else:
			args.append(arg)
	var hands := int(args[0]) if args.size() > 0 else 50000
	var seed_value := int(args[1]) if args.size() > 1 else 1
	var started := Time.get_ticks_msec()
	var fuzz := Fuzzer.new()
	fuzz.max_failures = 20
	fuzz.run(seed_value, hands)
	print(fuzz.stats)
	var failures := fuzz.failures.duplicate()
	if bot_matches > 0:
		failures.append_array(_bot_matches(bot_matches, seed_value))
	for f in failures:
		printerr("  ", f)
	print("%d table hands, %d failures, %.1fs" % [fuzz.stats["hands"], failures.size(), (Time.get_ticks_msec() - started) / 1000.0])
	quit(1 if failures else 0)


func _bot_matches(count: int, seed_value: int) -> Array[String]:
	var failures: Array[String] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_value)
	var hands := 0
	var removed := 0
	var fines := [0]  # an Array: lambdas capture ints by value
	for match_no in count:
		var m := TeamMatch.new(rng.randi())
		m.heat.dealer = Dealer.preset(Dealer.Kind.STRICT)
		m.heat.fined.connect(func(_team: int, _seat: int) -> void: fines[0] += 1)
		var n := rng.randi_range(2, 9)
		for i in n:
			var bot := PokerBot.new(PlayStyle.preset(rng.randi() % PlayStyle.Kind.size()), rng.randi())
			bot.equity_iterations = 30
			m.add_player("P%d" % i, i % 2, rng.randi_range(100, 2000), bot)
		m.max_hands = 300
		var total := m.table.total_chips()
		while not m.is_over():
			m.start_hand()
			hands += 1
			var acts := 0
			while not m.table.hand_over:
				var seat := m.table.to_act
				var choice := m.bots[seat].decide(m.table, seat, m.talk)
				m.table.act(choice["action"], choice["amount"])
				acts += 1
				if m.table.total_chips() + m.removed_chips != total:
					failures.append("bot match %d hand %d: chips not conserved" % [match_no, m.table.hand_number])
					return failures
				if acts > 500:
					failures.append("bot match %d hand %d never ended" % [match_no, m.table.hand_number])
					return failures
			var paid := 0
			for p: Dictionary in m.table.last_result["pots"]:
				paid += p["amount"]
			for amount: int in m.table.last_result["payouts"].values():
				paid -= amount
			if paid != 0:
				failures.append("bot match %d hand %d: payouts don't match the pots" % [match_no, m.table.hand_number])
		removed += m.removed_chips
	print("%d bot matches, %d hands, %d fines, %d chips removed with ejected seats" % [count, hands, fines[0], removed])
	return failures
