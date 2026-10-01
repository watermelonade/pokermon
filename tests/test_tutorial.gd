extends TestCase
## Rosie's tutorial (src/tutorial/): the lessons come in order, each scripted
## hand deals what its lesson says and produces the situation it teaches
## (the teammate signals and wins, your teammates step aside for your
## signal, the raccoon bluffs the river with its tell showing, the dealer
## warns your crew), any other play still gets through all five lessons
## without busting, fining or ejecting you, signals that would overheat your
## crew are refused, skipping works, the lines fit the text box, and the
## save remembers the tutorial. Played headless the way the table plays it:
## TableTutorial's hooks called at the same moments.


## A match seated the way the table seats the tutorial, with your seat
## either a scripted bot following the coach (`follow`) or empty.
func _match(tt: TableTutorial, follow: bool) -> TeamMatch:
	var m := TeamMatch.new(7)
	var setup := TutorialScript.setup_for(GameState.fresh().party_animals())
	for i in setup.size():
		m.add_player(setup[i]["name"], setup[i]["team"], TutorialScript.CHIPS, tt.make_bot(i, follow))
	m.max_hands = tt.hands()
	m.table.action_taken.connect(func(seat: int, action: int, _amount: int) -> void:
		tt.event("acted", {"seat": seat, "action": action, "street": m.table.street}, 0.0))
	return m


## Says every queued coach line, recording each; a line asking for a
## signal gets one (`by_a`: press A and let the coach do it).
func _drain(tt: TableTutorial, m: TeamMatch, said: Array[String], by_a := false) -> void:
	var guard := 0
	while tt.has_lines() and guard < 50:
		guard += 1
		said.append(tt.current_text())
		var wait := tt.current_wait()
		if wait.begins_with("signal:") and not by_a:
			var sig := 0 if wait == "signal:any" else int(wait.get_slice(":", 1))
			if tt.on_signal(sig, 0.0):
				m.talk.send(0, sig as TableTalk.Sig, m.table.street)
			else:
				tt.press_a()  # refused: the TOO_HOT line is up, dismiss it
			continue
		var sig := tt.press_a()
		if sig >= 0:
			m.talk.send(0, sig as TableTalk.Sig, m.table.street)


## Plays one lesson's hand. `you`: a policy for your seat, or "" to follow
## the coach. Returns what the coach said.
func _play_hand(tt: TableTutorial, m: TeamMatch, you := "", by_a := false) -> Array[String]:
	var said: Array[String] = []
	m.start_hand(tt.begin_hand(m))
	tt.event("hand_start", {}, 0.0)
	_drain(tt, m, said, by_a)
	var guard := 0
	while not m.table.hand_over and guard < 200:
		guard += 1
		var seat := m.table.to_act
		var choice: Dictionary
		if seat == 0:
			tt.event("your_turn", {"street": m.table.street}, 0.0)
			_drain(tt, m, said, by_a)
			var policy := you if you else ScriptedBot.policy_for(tt.lesson()["plans"][0], m.table.street)
			choice = ScriptedBot.play(policy, m.table, 0, m.talk)
		else:
			choice = m.bots[seat].decide(m.table, seat, m.talk)
		m.table.act(choice["action"], choice["amount"])
		_drain(tt, m, said, by_a)
	tt.event("hand_over", {}, 0.0)
	_drain(tt, m, said, by_a)
	return said


func _has_line(said: Array[String], fragment: String) -> bool:
	return said.any(func(l: String) -> bool: return l.contains(fragment))


func test_lessons_come_in_order() -> void:
	var ids: Array = TutorialScript.LESSONS.map(func(l: Dictionary) -> String: return l["id"])
	check_eq(ids, ["basics", "step_aside", "your_signal", "tells", "heat"])
	for k in TutorialScript.count():
		var l := TutorialScript.lesson(k)
		check_eq(l["hole"].size(), 6, "%s deals all six seats" % l["id"])
		var deck := TutorialScript.deck_for(k)
		var unique := {}
		for c in deck:
			unique[c] = true
		check_eq(unique.size(), 52, "%s's deck is a whole deck, each card once" % l["id"])
	var tt := TableTutorial.new()
	var m := _match(tt, true)
	for k in TutorialScript.count():
		_play_hand(tt, m)
		check_eq(tt.lesson_index, k)
	check(m.is_over(), "the match ends after the last lesson")
	check(tt.completed)
	check_eq(tt.result_text(), TutorialScript.RESULT)


func test_each_lesson_deals_its_hand() -> void:
	var tt := TableTutorial.new()
	var m := _match(tt, true)
	for k in TutorialScript.count():
		var l := TutorialScript.lesson(k)
		m.start_hand(tt.begin_hand(m))
		check_eq(m.table.button, l["button"], "%s: the button" % l["id"])
		check_eq(m.table.hand_number, k + 1, "%s: hand number = lesson number" % l["id"])
		check_eq(m.table.big_blind, 10, "%s: first blind level" % l["id"])
		for seat: int in l["hole"]:
			check_eq(m.table.seats[seat].hole, Card.parse_many(l["hole"][seat]), "%s: seat %d's cards" % [l["id"], seat])
		m.play_bots()
		if m.table.board.size() == 5:
			check_eq(m.table.board, Card.parse_many(l["board"]), "%s: the board" % l["id"])
		check(m.table.hand_over, "%s: bots following the coach finish the hand" % l["id"])


func test_following_the_coach_teaches_each_lesson() -> void:
	var tt := TableTutorial.new()
	var m := _match(tt, false)
	var warned := [0]
	var fined := [0]
	m.heat.warned.connect(func(_team: int, _seat: int) -> void: warned[0] += 1)
	m.heat.fined.connect(func(_team: int, _seat: int) -> void: fined[0] += 1)
	var t := m.table

	# 1. The basics: you raise your Kings, Sage steps out of the way (soft
	# play), and three Kings win.
	var said := _play_hand(tt, m)
	check(t.seats[2].folded, "your teammate folded to your raise")
	check(t.last_result["payouts"].has(0), "you win the first hand")
	check(_has_line(said, "soft play"), "Rosie names soft play")

	# 2. Bandit signals "I'm strong" and raises; you fold; Bandit wins.
	said = _play_hand(tt, m)
	var sent: Array = m.talk.sent.filter(func(s: Dictionary) -> bool: return s["from"] == 4)
	check_eq(sent.size(), 1, "your teammate signalled once")
	if sent:
		check_eq(sent[0]["sig"], TableTalk.Sig.STRONG)
		check_eq(sent[0]["street"], HoldemTable.Street.PREFLOP, "before your turn")
	check(t.seats[0].folded, "you stepped aside")
	check(t.last_result["payouts"].has(4), "the teammate who signalled wins")
	check(_has_line(said, "stay in the crew"))

	# 3. You signal; both teammates fold hands they'd have played.
	said = _play_hand(tt, m)
	check(m.talk.sent.any(func(s: Dictionary) -> bool: return s["from"] == 0 and s["sig"] == TableTalk.Sig.STRONG), "you signalled")
	check(t.seats[2].folded and t.seats[4].folded, "both teammates stepped aside")
	check(t.last_result["payouts"].has(0), "you win")
	check(_has_line(said, "read you"), "Rosie points out what they did")

	# 4. Scraps bluffs the river and its tell fires; calling wins.
	said = _play_hand(tt, m)
	var scraps := t.seats[3]
	check_eq(tt.tell_roll(3, HoldemTable.Street.RIVER), 0.0, "the lesson's tell always shows")
	check_eq(tt.tell_roll(5, HoldemTable.Street.RIVER), 1.0, "and no other")
	check(AnimalTells.fires(&"raccoon", AnimalTells.Moment.ACTED, scraps.hole, t.board, HoldemTable.Action.RAISE, 0.0),
			"a raise with Scraps' cards on this board is its bluffing tell")
	check(not t.last_result["uncontested"], "it went to a showdown")
	check(t.last_result["payouts"].has(0), "the call wins")
	check(_has_line(said, "rubbed its paws"), "Rosie explains the tell")

	# 5. Heat: two signals in one hand pass the warning, not the fine.
	check_eq(warned[0], 0, "no warnings before the dealer sits down")
	said = _play_hand(tt, m)
	check_eq(m.heat.dealer.kind, Dealer.Kind.STRICT)
	check_eq(warned[0], 1, "one warning")
	check_eq(fined[0], 0, "no fine")
	check(not t.seats[0].ejected)
	check(_has_line(said, "Heat's 20"), "the first signal's Heat, filled in")
	check(_has_line(said, "costs +40"), "and the second's cost")
	check(_has_line(said, "costs +60"), "and what a third would cost")
	check(t.last_result["payouts"].has(0), "you win the last hand")
	check(m.is_over() and m.winner() == 0, "and the match")


func test_answering_a_signal_line_with_a() -> void:
	# A on "touch your nose" has Rosie make the signal for you (on a Deck
	# whose back buttons aren't mapped, nobody's stuck).
	var tt := TableTutorial.new()
	tt.start_lesson = 2
	var m := _match(tt, false)
	_play_hand(tt, m, "", true)
	check(m.table.seats[2].folded and m.table.seats[4].folded, "your teammates still read it")
	tt = TableTutorial.new()
	tt.start_lesson = 4
	m = _match(tt, false)
	var warned := [0]
	m.heat.warned.connect(func(_team: int, _seat: int) -> void: warned[0] += 1)
	_play_hand(tt, m, "", true)
	check_eq(warned[0], 1, "two signals by A: the warning")


func test_any_play_gets_through_every_lesson_unpunished() -> void:
	for you in ["fold", "check_call", "bluff:3", "raise_to:1000", "bet:0.5"]:
		var tt := TableTutorial.new()
		var m := _match(tt, false)
		var fined := [0]
		m.heat.fined.connect(func(_team: int, _seat: int) -> void: fined[0] += 1)
		for k in TutorialScript.count():
			_play_hand(tt, m, you)
			check_eq(m.table.total_chips(), TutorialScript.CHIPS * 6, "%s, lesson %d: no chips made or lost" % [you, k + 1])
			check(m.table.hand_over, "%s, lesson %d: the hand finishes" % [you, k + 1])
			check(not m.table.seats.any(func(s: HoldemTable.Seat) -> bool: return s.ejected), "%s: nobody thrown out" % you)
		check_eq(fined[0], 0, "%s: never fined" % you)
		check(m.is_over() and tt.completed, "%s: all five lessons" % you)


func test_signals_that_would_overheat_are_refused() -> void:
	var tt := TableTutorial.new()
	tt.start_lesson = 4
	var m := _match(tt, false)
	m.start_hand(tt.begin_hand(m))
	check(tt.allow_signal(0))
	m.talk.send(0, TableTalk.Sig.STRONG, 0)  # 20
	m.talk.send(0, TableTalk.Sig.WEAK, 0)  # +40: 60, warned
	check(not tt.allow_signal(0), "+60 more would be 120: past the fine and the ejection")
	tt.coach_lines.clear()
	check(not tt.on_signal(1, 3.0), "refused")
	check_eq(tt.current_text(), "Whoa! +60 would put your crew at 120 Heat. Fined at 70, out at 100!")
	check(not tt.on_signal(1, 3.0))
	check_eq(tt.coach_lines.size(), 1, "said once, not once a press")
	# With no dealer, signals are free.
	tt = TableTutorial.new()
	m = _match(tt, false)
	m.start_hand(tt.begin_hand(m))
	for k in 6:
		m.talk.send(0, TableTalk.Sig.STRONG, 0)
	check(tt.allow_signal(0), "street rules: signal freely")


func test_a_signal_line_waits_for_the_signal_it_asks_for() -> void:
	var tt := TableTutorial.new()
	tt.start_lesson = 2
	var m := _match(tt, false)
	m.start_hand(tt.begin_hand(m))
	tt.coach_lines.clear()
	tt.say({"text": "Touch your nose.", "wait": "signal:0"}, 0.0)
	check(not tt.on_signal(2, 0.0), "the wrong signal isn't sent, and the line stays")
	check_eq(tt.current_text(), "Touch your nose.")
	check(tt.on_signal(0, 0.0), "the right one goes")
	check(not tt.has_lines())
	check(tt.on_signal(3, 0.0), "with nothing asked, signals just go")


func test_coach_lines_show_when_due_and_fire_once() -> void:
	var tt := TableTutorial.new()
	var m := _match(tt, false)
	m.start_hand(tt.begin_hand(m))
	tt.event("hand_start", {}, 5.0)
	check(tt.has_lines(), "queued")
	check(not tt.showing(4.9), "not before its time")
	check(tt.showing(5.0))
	var n := tt.coach_lines.size()
	tt.event("hand_start", {}, 6.0)
	check_eq(tt.coach_lines.size(), n, "an entry fires once a lesson")
	check(tt.current_text().begins_with("Welcome"))
	check(tt.current_text().find("{") < 0, "placeholders filled")


func test_skipping() -> void:
	var tt := TableTutorial.new()
	var m := _match(tt, false)
	m.start_hand(tt.begin_hand(m))
	tt.event("hand_start", {}, 0.0)
	var first := tt.current_text()
	tt.request_skip(1.0)
	check_eq(tt.current_wait(), "skip", "Start asks first")
	tt.request_skip(1.0)
	check_eq(tt.coach_lines.filter(func(l: Dictionary) -> bool: return l["wait"] == "skip").size(), 1, "asked once")
	tt.press_b()
	check_eq(tt.current_text(), first, "B: carry on where she was")
	check(not tt.skipped)
	tt.request_skip(2.0)
	tt.press_a()
	check(tt.skipped, "A: skipped")
	check(not tt.has_lines(), "nothing more to say")
	check(not tt.completed)
	check_eq(tt.result_text(), TutorialScript.SKIPPED)
	tt.event("your_turn", {"street": 0}, 3.0)
	check(not tt.has_lines(), "and nothing more is queued")


func test_jumping_to_a_lesson() -> void:
	var tt := TableTutorial.new()
	tt.start_lesson = 3
	var m := _match(tt, false)
	m.start_hand(tt.begin_hand(m))
	check_eq(tt.lesson()["id"], "tells")
	check_eq(m.table.button, 3)
	check_eq(m.table.hand_number, 4)
	check_eq(m.table.seats[0].hole, Card.parse_many("9h 9s"))


func test_suggested_play_puts_the_cursor_on_it() -> void:
	var tt := TableTutorial.new()
	tt.start_lesson = 1  # step aside: fold
	var m := _match(tt, false)
	m.start_hand(tt.begin_hand(m))
	while m.table.to_act != 0:
		var seat := m.table.to_act
		var c: Dictionary = m.bots[seat].decide(m.table, seat, m.talk)
		m.table.act(c["action"], c["amount"])
	check_eq(tt.suggest(0)["item"], CommandMenu.Item.FOLD)
	tt = TableTutorial.new()  # the basics: raise the Kings
	m = _match(tt, false)
	m.start_hand(tt.begin_hand(m))
	while m.table.to_act != 0:
		var seat := m.table.to_act
		var c: Dictionary = m.bots[seat].decide(m.table, seat, m.talk)
		m.table.act(c["action"], c["amount"])
	var hint := tt.suggest(0)
	check_eq(hint["item"], CommandMenu.Item.RAISE)
	check_eq(hint["raise_to"], 40)


func test_lines_fit_the_box() -> void:
	# docs/WRITING.md: about 76 characters a box, 84 at most, four boxes at a
	# time. Filled with the longest names a seat can have.
	var longest := ""
	for id: StringName in Species.ids():
		for n: String in Species.get_info(id)["individuals"]:
			if n.length() > longest.length():
				longest = n
	var fill := {"m2": longest, "m4": longest, "r1": "Waddles", "r3": "Scraps", "r5": "Mittens",
			"heat": 100, "next": 100, "after": 200}
	var width := CoachBox.text_width(632.0)
	var texts: Array[String] = [TutorialScript.TOO_HOT, TutorialScript.SKIP_PROMPT]
	for l: Dictionary in TutorialScript.LESSONS:
		for e: Dictionary in l["coach"]:
			check(e["lines"].size() <= 4, "%s: %d boxes at once" % [l["id"], e["lines"].size()])
			for line: Variant in e["lines"]:
				texts.append(str(line["text"]) if line is Dictionary else str(line))
	for text in texts:
		var filled := text.format(fill)
		check(filled.length() <= 84, "%d characters: %s" % [filled.length(), filled])
		check(CoachBox.wrap_rows(filled, width).size() <= 2, "wraps to two rows: %s" % filled)
	var setup := TutorialScript.setup_for([])
	check_eq(setup.map(func(s: Dictionary) -> String: return s["name"]), ["You", "Waddles", "Sage", "Scraps", "Bandit", "Mittens"])


func test_save_remembers_the_tutorial() -> void:
	var s := GameState.fresh()
	check(not s.tutorial_offered and not s.tutorial_done, "a new game hasn't been offered it")
	s.tutorial_offered = true
	s.tutorial_done = true
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	check(back.tutorial_offered and back.tutorial_done, "round trip")
	var old := s.to_dict()
	old.erase("tutorial_offered")
	old.erase("tutorial_done")
	var loaded := GameState.from_dict(JSON.parse_string(JSON.stringify(old)))
	check(loaded != null, "a save from before the tutorial loads")
	check(loaded.tutorial_offered, "and isn't offered it again at the start")
	check(not loaded.tutorial_done, "but can still have it at the diner")
