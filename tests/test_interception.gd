extends TestCase
## Interception (src/crew/interception.gd): noticing odds, crew codes,
## learning at a showdown, fake signals, how bots use what they read, the
## save round trip, and the guarantee the type chart rests on: switched off,
## nothing changes.

const A := HoldemTable.Action
const K := PlayStyle.Kind
const Sig := TableTalk.Sig


## You (seat 0) and a cat against a goose: `setup` as the table builds it.
func _setup() -> Array[Dictionary]:
	return [
		{"name": "You", "team": 0, "animal": null},
		{"name": "Honk", "team": 1, "animal": Species.individual(&"goose", 0)},
		{"name": "Duchess", "team": 0, "animal": Species.individual(&"cat", 0)},
		{"name": "Gertie", "team": 1, "animal": Species.individual(&"goose", 1)},
	]


func _table_match(seed_value: int, codebook: CodeBook = null) -> TeamMatch:
	var m := TeamMatch.new(seed_value)
	var setup := _setup()
	for i in setup.size():
		m.add_player(setup[i]["name"], setup[i]["team"], 1000, null)
	m.interception.enable_for_table(setup, 0, codebook)
	return m


## Golden action logs recorded on the engine before interception existed
## (same bots, seeds and settings): with it off, every action, amount and
## signal must come out the same, so every random draw does too.
func test_off_changes_nothing_in_bot_matches() -> void:
	var golden := {11: "a67942ad306f23860bbf59e2c0be54a8", 12: "866d0edc4c83bcf4ad91e244abe7b04d"}
	var kinds := [K.ROCK, K.MANIAC, K.SHARK, K.CALLING_STATION, K.BLUFFER, K.SHARK]
	for seed_value: int in golden:
		var m := TeamMatch.new(seed_value)
		if seed_value == 12:
			m.heat.dealer = Dealer.preset(Dealer.Kind.WATCHFUL)  # the Heat path through _maybe_signal too
		for i in 6:
			var bot := PokerBot.new(PlayStyle.preset(kinds[i]), seed_value * 10 + i + 1)
			bot.equity_iterations = 40
			m.add_player("P%d" % i, i % 2, 1000, bot)
		m.max_hands = 60
		var log: Array[String] = []
		m.table.action_taken.connect(func(s: int, a: int, amt: int) -> void: log.append("%d:%d:%d" % [s, a, amt]))
		m.talk.gesture_made.connect(func(s: int, sig: int) -> void: log.append("g%d:%d" % [s, sig]))
		var rng_before := m.interception.rng.state
		m.run_to_end()
		check_eq(",".join(log).md5_text(), golden[seed_value], "seed %d plays exactly as before" % seed_value)
		check_eq(m.interception.stats["signals"], 0, "off: nothing counted")
		check_eq(m.interception.rng.state, rng_before, "off: no random draws")


func test_crew_codes_are_private_and_stable() -> void:
	check_eq(CrewCode.for_crew(CrewCode.PLAYER), [0, 1, 2, 3] as Array[int], "your crew uses the legend")
	var codes := {}
	for id in ["pond_hecklers", "ridge_regulars", "mossbank_open", "a", "b", "c", "d", "e"]:
		var code := CrewCode.for_crew(id)
		check_eq(code, CrewCode.for_crew(id), "%s: the same code every time" % id)
		check(CrewCode.is_derangement(code), "%s: no gesture keeps its legend meaning (%s)" % [id, code])
		var sorted := code.duplicate()
		sorted.sort()
		check_eq(sorted, [0, 1, 2, 3] as Array[int], "%s: a permutation" % id)
		codes[str(code)] = true
	check(codes.size() >= 3, "crews don't all share one code (%d distinct)" % codes.size())
	var code := CrewCode.for_crew("pond_hecklers")
	for meaning in 4:
		check_eq(CrewCode.meaning_of(code, code[meaning]), meaning)


func test_attentiveness_from_species() -> void:
	var m := _table_match(1)
	var itc := m.interception
	check_eq(itc.attentiveness_of(0), Interception.YOU, "you")
	check_eq(itc.attentiveness_of(2), Interception.SPECIES[&"cat"], "the cat")
	check(itc.attentiveness_of(2) > itc.attentiveness_of(1), "a cat watches better than a goose")
	check_eq(itc.crew_id(0), CrewCode.PLAYER)
	check_eq(itc.crew_id(1), "Honk/Gertie", "an unnamed crew is known by its animals")
	var named := _setup()
	for s in named:
		if s["team"] == 1:
			s["crew"] = "pond_hecklers"
	itc.enable_for_table(named, 0)
	check_eq(itc.crew_id(1), "pond_hecklers", "the overworld's crew id when given")


## Measured against the formula: attentiveness x LOOK x (the crew's nth
## signal this hand), per watcher, capped.
func test_noticing_odds() -> void:
	check_eq(snappedf(Interception.new().notice_chance(0, 1), 0.001), snappedf(Interception.DEFAULT * Interception.LOOK, 0.001))
	var trials := 3000
	var counts := [0, 0, 0]  # the rivals' 1st, 2nd, 3rd signal of a hand
	var by_watcher := {0: 0, 2: 0}
	var m := _table_match(77)
	m.hands_per_level = 1000000
	m.interception.noticed.connect(func(watcher: int, _from: int, _g: int, _m: int, _fake: bool) -> void: by_watcher[watcher] += 1)
	for t in trials:
		m.start_hand()
		for nth in 3:
			var before := m.interception.seen.size()
			m.talk.send(1 if nth % 2 == 0 else 3, Sig.STRONG, 0)
			if m.interception.seen.size() > before:
				counts[nth] += 1
		while not m.table.hand_over:
			m.table.act(A.FOLD)
		m.table.seats[0].stack = 1000  # keep everyone in
		m.table.seats[1].stack = 1000
		m.table.seats[2].stack = 1000
		m.table.seats[3].stack = 1000
	var itc := m.interception
	for nth in 3:
		# Your crew: you (0.4) and the cat (0.75) both get a look.
		var expected := 1.0 - (1.0 - itc.notice_chance(0, nth + 1)) * (1.0 - itc.notice_chance(2, nth + 1))
		var got: float = counts[nth] / float(trials)
		var sigma := sqrt(expected * (1.0 - expected) / trials)
		check(absf(got - expected) < 4.0 * sigma, "signal %d of the hand: noticed %.3f, expected %.3f" % [nth + 1, got, expected])
	check(counts[2] > counts[1] and counts[1] > counts[0], "chatty crews leak: %s" % [counts])
	check(by_watcher[2] > by_watcher[0], "the cat spots more than you do: %s" % by_watcher)
	check_eq(itc.stats["signals"], trials * 3)


## Plays the hand out by calling/checking to a showdown (or folding the
## signaller) and returns what your crew learned of the rival crew.
func _signal_then(m: TeamMatch, sig: int, signaller_folds: bool, fake := false) -> Dictionary:
	m.start_hand()
	m.interception.attentiveness[0] = 100.0  # capped at MAX_CHANCE: noticed within a few tries
	var tries := 0
	while m.interception.seen.is_empty() and tries < 20:
		m.talk.send(1, sig, 0, fake)
		tries += 1
	check(not m.interception.seen.is_empty(), "noticed")
	while not m.table.hand_over:
		var folding := signaller_folds and m.table.to_act == 1
		m.table.act(A.FOLD if folding else A.CALL)
	return m.interception.book.learned(CrewCode.PLAYER, m.interception.crew_id(1))


func test_a_showdown_teaches_the_gesture() -> void:
	var m := _table_match(5)
	var events: Array = []
	m.interception.learned.connect(func(r: int, s: int, g: int, meaning: int) -> void: events.append([r, s, g, meaning]))
	var gesture: int = m.interception.code_of(1)[Sig.WEAK]
	check_eq(m.interception.meaning_for(0, 1, gesture), -1, "unknown before")
	var learned := _signal_then(m, Sig.WEAK, false)
	check_eq(learned, {gesture: Sig.WEAK}, "seeing their cards teaches what the gesture meant")
	check_eq(events, [[0, 1, gesture, Sig.WEAK]])
	check_eq(m.interception.meaning_for(0, 1, gesture), Sig.WEAK)
	check(gesture != Sig.WEAK, "and it isn't the legend's gesture for it")
	# Next hand the same gesture is understood the moment it's noticed.
	var meanings: Array = []
	m.interception.noticed.connect(func(_w: int, _f: int, _g: int, meaning: int, _fake: bool) -> void: meanings.append(meaning))
	_signal_then(m, Sig.WEAK, false)
	check_eq(meanings.back(), Sig.WEAK, "the overlay can show the meaning now")
	check_eq(events.size(), 1, "learned once")


func test_no_showdown_teaches_nothing() -> void:
	var m := _table_match(6)
	check_eq(_signal_then(m, Sig.STRONG, true), {}, "the signaller folded: its cards were never seen")


func test_fake_signals() -> void:
	var m := _table_match(8)
	m.heat.dealer = Dealer.preset(Dealer.Kind.WATCHFUL)
	m.start_hand()
	m.talk.send(0, Sig.STRONG, 0, true)
	check(m.heat.level(0) > 0.0, "a fake is still a gesture the dealer can see")
	var rng := RandomNumberGenerator.new()
	check_eq(m.talk.read_from(2, 0, 1.0, rng), [] as Array[Sig], "teammates know it's for show")
	m.talk.send(0, Sig.WEAK, 0)
	check_eq(m.talk.read_from(2, 0, 1.0, rng), [Sig.WEAK] as Array[Sig], "real signals still read")
	# A rival that has cracked your nose-touch believes the fake.
	var book := CodeBook.new()
	book.learn("Honk/Gertie", CrewCode.PLAYER, 0, Sig.STRONG)
	m = _table_match(9, book)
	m.interception.attentiveness[1] = 100.0
	m.interception.attentiveness[3] = 100.0
	m.start_hand()
	var tries := 0
	while m.interception.readings(1).is_empty() and tries < 20:
		m.talk.send(0, Sig.STRONG, 0, true)
		tries += 1
	check_eq(m.interception.readings(1), {0: [Sig.STRONG]}, "the rivals read the fake as strength")
	# The showdown contradicts a fake, so it teaches nothing new.
	m = _table_match(10)
	check_eq(_signal_then(m, Sig.STRONG, false, true), {}, "fakes don't teach the code")


func test_codebook_survives_a_save() -> void:
	var book := CodeBook.new()
	book.learn(CrewCode.PLAYER, "pond_hecklers", 2, Sig.WEAK)
	book.learn(CrewCode.PLAYER, "pond_hecklers", 0, Sig.STRONG)
	book.learn("pond_hecklers", CrewCode.PLAYER, 1, Sig.WEAK)
	var json := JSON.stringify(book.to_dict())
	var back := CodeBook.from_dict(JSON.parse_string(json))
	check_eq(back.known, book.known, "a JSON round trip")
	check_eq(back.meaning(CrewCode.PLAYER, "pond_hecklers", 2), Sig.WEAK)
	check_eq(back.learned("pond_hecklers", CrewCode.PLAYER), {1: Sig.WEAK}, "what they know of yours")
	var damaged := CodeBook.from_dict({"player": {"x": {"9": 1, "a": 2, "1": "?", "2": 3}, "y": 5}, "z": []})
	check_eq(damaged.known, {"player": {"x": {2: 3}}}, "damaged entries are dropped, the rest kept")
	check_eq(CodeBook.from_dict(null).known, {})


## A heads-up spot: the rival raises and `me` faces the bet with whatever
## the deal gave it. Returns the bot's action with nothing heard, with the
## raiser read as strong, and read as weak, from the same bot seed (so the
## same equity samples: a paired comparison).
func _facing_raise(k: int, kind: int) -> Array[int]:
	var m := TeamMatch.new(5000 + k)
	m.add_player("A", 0, 1000, null)
	m.add_player("B", 1, 1000, null)
	m.interception.enabled = true
	m.start_hand()
	var raiser := m.table.to_act
	m.table.act(A.RAISE, m.table.big_blind * 3)
	return _decisions(m, raiser, kind, k)


## The big blind with a free check after the rival limps.
func _after_limp(k: int, kind: int) -> Array[int]:
	var m := TeamMatch.new(8000 + k)
	m.add_player("A", 0, 1000, null)
	m.add_player("B", 1, 1000, null)
	m.interception.enabled = true
	m.start_hand()
	var limper := m.table.to_act
	m.table.act(A.CALL)
	return _decisions(m, limper, kind, k)


func _decisions(m: TeamMatch, other: int, kind: int, k: int) -> Array[int]:
	var me := m.table.to_act
	var itc := m.interception
	var out: Array[int] = []
	for heard in [-1, Sig.STRONG, Sig.WEAK]:
		itc.book = CodeBook.new()
		itc.seen.clear()
		if heard >= 0:
			var gesture: int = itc.code_of(m.table.seats[other].team)[heard]
			itc.book.learn(itc.crew_id(m.table.seats[me].team), itc.crew_id(m.table.seats[other].team), gesture, heard)
			itc.seen.append({"reader": m.table.seats[me].team, "watcher": me, "from": other, "sig": heard, "gesture": gesture, "fake": false})
		var style := PlayStyle.preset(kind)
		style.chattiness = 0.0
		var bot := PokerBot.new(style, 900 + k)
		bot.interception = itc
		bot.equity_iterations = 200
		out.append(bot.decide(m.table, me, m.talk)["action"])
	return out


func test_bots_respect_strength_and_bluff_weakness() -> void:
	var folds := [0, 0, 0]  # nothing heard, heard strong, heard weak
	for k in 150:
		var acts := _facing_raise(k, K.SHARK)
		for c in 3:
			if acts[c] == A.FOLD:
				folds[c] += 1
	check(folds[1] > folds[0], "folds more to a raiser who said strong: %s" % [folds])
	check(folds[2] < folds[0], "folds less to one who said weak: %s" % [folds])
	check(folds[1] - folds[0] < 50 and folds[0] - folds[2] < 50, "modest: changes under a third of the decisions: %s of 150" % [folds])
	var raises := [0, 0, 0]
	for k in 150:
		var acts := _after_limp(k, K.ROCK)
		for c in 3:
			if acts[c] == A.RAISE:
				raises[c] += 1
	check(raises[2] > raises[0], "bluffs at a limper who said weak: %s" % [raises])
	check_eq(raises[1], raises[0], "a limper who said strong isn't bluffed more: %s" % [raises])


func test_bot_match_with_interception_on() -> void:
	var m := TeamMatch.new(31)
	for i in 6:
		var bot := PokerBot.new(PlayStyle.preset([K.MANIAC, K.SHARK][i % 2]), 310 + i)
		bot.equity_iterations = 40
		m.add_player("P%d" % i, i % 2, 1000, bot)
	m.max_hands = 80
	m.interception.enable_for_bots(m.bots)
	check_eq(m.interception.attentiveness_of(1), Interception.BY_STYLE[K.SHARK])
	m.run_to_end()
	check_eq(m.team_chips(0) + m.team_chips(1), 6000, "chips conserved")
	var stats := m.interception.stats
	check(stats["signals"] > 0 and stats["noticed"] > 0, "signals were made and noticed: %s" % stats)
	check(stats["noticed"] < stats["signals"], "but not all of them: %s" % stats)
	check(stats["learned"] <= 4, "bots only say strong and weak: at most 2 gestures per crew")


func test_fake_press_is_shift_or_lb() -> void:
	var key := InputEventKey.new()
	key.physical_keycode = KEY_1
	key.pressed = true
	check(not InterceptOverlay.is_fake_press(key), "plain 1: a real signal")
	key.shift_pressed = true
	check(InterceptOverlay.is_fake_press(key), "Shift+1: for show")
