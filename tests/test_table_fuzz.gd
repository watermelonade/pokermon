extends TestCase
## Randomized tests: thousands of random hands through tests/table_fuzzer.gd
## (every invariant after every action, every hand settled again by an
## independent model), random crew matches through TeamMatch with fines,
## ejections and caught leaders, and Heat against a model of its rules.
## tools/soak_rules.gd runs the table fuzzer for as long as you like.

const Fuzzer := preload("res://tests/table_fuzzer.gd")
const A := HoldemTable.Action
const D := Dealer.Kind


func test_random_tables_keep_every_rule() -> void:
	var fuzz := Fuzzer.new()
	fuzz.run(20261001, 6000)
	for f in fuzz.failures:
		check(false, f)
	var stats := fuzz.stats
	check_eq(stats["hands"], 6000, "hands played")
	# The run has to reach the hard cases, or passing means little.
	for key: String in ["side_pots", "split_pots", "odd_chips", "uncalled", "dead_money", "ejections", "all_in_preflop", "illegal_actions"]:
		check(stats[key] >= 20, "only %d hands with %s" % [stats[key], key])


## Mostly calls and small raises, so matches last long enough to reach the
## blind levels, the hand limit and the heads-up endgame.
func _random_action(t: HoldemTable, rng: RandomNumberGenerator) -> void:
	var legal := t.legal()
	var roll := rng.randf()
	if roll < 0.25:
		t.act(A.FOLD)
	elif roll < 0.88:
		t.act(A.CALL)
	elif roll < 0.97:
		t.act(A.RAISE, legal["min_raise_to"])
	else:
		t.act(A.RAISE, rng.randi_range(legal["min_raise_to"], legal["max_raise_to"]))


## Crew matches of 2-9 seats with uneven crews, played by random actions,
## with the floor fining and ejecting at random and a leader on each side
## some of the time. Chips are conserved counting removed_chips, fines land
## as dead money, ejected seats never play again, and is_over()/winner()
## agree with the rules in TeamMatch's docstring.
func test_random_matches_keep_every_chip_and_end_right() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(77)
	var hands := 0
	var endings := {"caught": 0, "one crew left": 0, "hand limit": 0}
	for match_no in 150:
		var m := TeamMatch.new(rng.randi())
		var n := rng.randi_range(2, 9)
		for i in n:
			var team := i % 2 if i < 2 else rng.randi() % 2
			m.add_player("P%d" % i, team, rng.randi_range(1, 400) if rng.randf() < 0.3 else 1000, null)
		m.hands_per_level = rng.randi_range(1, 8)
		m.max_hands = rng.randi_range(5, 60)
		if rng.randf() < 0.3:
			m.leaders = {0: 0, 1: 1}
		var total := m.table.total_chips()
		var ejected := {}
		while not m.is_over():
			if not check(m.table.players_with_chips() >= 2, "match %d: not over, but no two seats with chips" % match_no):
				return
			var fined := m.heat.pending_fines.duplicate()
			m.start_hand()
			hands += 1
			var level: Array = TeamMatch.BLIND_LEVELS[mini((m.table.hand_number - 1) / m.hands_per_level, TeamMatch.BLIND_LEVELS.size() - 1)]
			check_eq([m.table.small_blind, m.table.big_blind], level, "blind level")
			for i in n:
				var s := m.table.seats[i]
				var fine := 0
				if fined.has(s.team) and s.dealt:
					var blinds := 0
					if i == m.table.small_blind_seat:
						blinds = mini(m.table.small_blind, s.stack + s.hand_bet)
					if i == m.table.big_blind_seat:
						blinds = mini(m.table.big_blind, s.stack + s.hand_bet)
					fine = mini(m.table.big_blind, s.stack + s.hand_bet - blinds)
				check_eq(s.dead_bet, fine, "match %d seat %d: fined a dead big blind" % [match_no, i])
				if ejected.has(i):
					check(not s.dealt and s.stack == 0, "an ejected seat plays again")
			var acts := 0
			while not m.table.hand_over:
				var team := rng.randi() % 2
				if rng.randf() < 0.02 and not m.heat.pending_fines.has(team):
					m.heat.pending_fines.append(team)
				if rng.randf() < 0.01:
					m.heat.pending_ejections.append(rng.randi() % n)
				_random_action(m.table, rng)
				acts += 1
				if not check(m.table.total_chips() + m.removed_chips == total, "match %d: chips not conserved" % match_no):
					return
				if not check(acts < 300, "hand never ended"):
					return
			check(m.heat.pending_ejections.is_empty(), "ejections applied at the hand's end")
			for i in n:
				if m.table.seats[i].ejected:
					ejected[i] = true
			check_eq(m.table.total_chips() + m.removed_chips, total, "match %d: chips conserved" % match_no)
		# How it ended.
		var caught := m.caught_team()
		var alive := m.teams_alive()
		var expected := -1
		if caught >= 0:
			expected = 1 - caught
			endings["caught"] += 1
		elif alive.size() == 1:
			expected = alive[0]
			endings["one crew left"] += 1
		elif alive.is_empty():
			expected = -1  # the floor threw out the last seat of both crews: nobody wins
		else:
			check(m.table.hand_number >= m.max_hands, "match %d over with both crews alive before the hand limit" % match_no)
			endings["hand limit"] += 1
			var a := m.team_chips(0)
			var b := m.team_chips(1)
			expected = 0 if a > b else (1 if b > a else -1)
		check_eq(m.winner(), expected, "match %d winner" % match_no)
	check(hands > 1500, "only %d hands" % hands)
	for key: String in endings:
		check(endings[key] >= 5, "only %d matches ended by %s" % [endings[key], key])


## Heat against a model of its documented rules: what each signal costs
## (repeats within a hand cost 1x, 2x, 3x...), cooling, one warning and one
## fine per episode, re-armed only once the crew cools below half the
## warning line, ejection at 100 with Heat back to 60.
func test_heat_follows_its_rules_under_random_signals() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(4242)
	var counts := {"warned": 0, "fined": 0, "ejected": 0, "rearmed": 0}
	for trial in 40:
		var kind: int = [D.ASLEEP, D.RELAXED, D.WATCHFUL, D.STRICT, D.BOUGHT][trial % 5]
		var m := TeamMatch.new(rng.randi())
		m.heat.dealer = Dealer.preset(kind)
		for i in 6:
			m.add_player("P%d" % i, i % 2, 100000, null)
		var events := []
		m.heat.warned.connect(func(team: int, seat: int) -> void: events.append(["warned", team, seat]))
		m.heat.fined.connect(func(team: int, seat: int) -> void: events.append(["fined", team, seat]))
		m.heat.ejection_called.connect(func(team: int, seat: int) -> void: events.append(["ejected", team, seat]))
		var heat := {0: 0.0, 1: 0.0}
		var armed := {0: [true, true], 1: [true, true]}
		var d := m.heat.dealer
		for hand in 40:
			m.start_hand()
			var gestures := {0: 0, 1: 0}
			var seats := []
			for i in 6:
				if m.table.seats[i].dealt:
					seats.append(i)
			for _g in rng.randi_range(0, 4):
				var seat: int = seats[rng.randi() % seats.size()]
				var team := seat % 2
				gestures[team] += 1
				var after: float = heat[team] + d.notice * d.team_bias.get(team, 1.0) * gestures[team]
				var expected := []
				if after >= Heat.WARNING and armed[team][0]:
					armed[team][0] = false
					expected.append(["warned", team, seat])
				if after >= Heat.FINE and armed[team][1]:
					armed[team][1] = false
					expected.append(["fined", team, seat])
				if after >= Heat.EJECT:
					expected.append(["ejected", team, seat])
					after = Heat.AFTER_EJECTION
				heat[team] = after
				events.clear()
				m.talk.send(seat, TableTalk.Sig.STRONG, 0)
				check_eq(events, expected, "trial %d hand %d: what the floor did" % [trial, hand])
				check(absf(m.heat.level(team) - heat[team]) < 1e-6, "trial %d: Heat %.2f, expected %.2f" % [trial, m.heat.level(team), heat[team]])
				for e: Array in expected:
					counts[e[0]] += 1
			while not m.table.hand_over:
				m.table.act(A.FOLD)
			for team: int in heat:
				heat[team] = maxf(0.0, heat[team] - d.cooling)
				if heat[team] < Heat.WARNING / 2 and not (armed[team][0] and armed[team][1]):
					armed[team] = [true, true]
					counts["rearmed"] += 1
				check(absf(m.heat.level(team) - heat[team]) < 1e-6, "trial %d: Heat after cooling" % trial)
			if m.is_over():
				break
	for key: String in counts:
		check(counts[key] >= 5, "only %d times %s" % [counts[key], key])
