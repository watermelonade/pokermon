extends RefCounted
## Property-based fuzzing for HoldemTable: random tables of 2-9 seats with
## random stacks (tiny ones included) and blinds, played with random actions,
## legal and not (wrong amounts, checking into a bet, action ids that don't
## exist), with dead money and ejections thrown in between hands.
##
## After every action it checks the invariants that must always hold: no chip
## made or lost (counting ejected chips), no negative stacks or bets, the seat
## to act can act and owes an action, legal() is consistent, and the action
## did exactly what act() promises (a fold facing a bet folds, a raise is
## clamped into the legal range...). After every hand it settles the hand
## again with an independent model written from the rules, not from the
## engine: blind positions (the big blind moves forward), what was posted,
## the uncalled bet, the main and side pots (dead money in the main pot),
## who wins each (scored with the brute-force tests/reference_evaluator.gd),
## odd chips, and every final stack.
##
## Used by tests/test_table_fuzz.gd (a few thousand hands, kept fast) and
## tools/soak_rules.gd (as many as you like).

const Reference := preload("res://tests/reference_evaluator.gd")
const A := HoldemTable.Action

var failures: Array[String] = []
var max_failures := 8
var rng := RandomNumberGenerator.new()
## What was exercised, so a test can check the fuzzer reached the hard cases.
var stats := {
	"tables": 0, "hands": 0, "actions": 0, "showdowns": 0, "side_pots": 0,
	"split_pots": 0, "odd_chips": 0, "uncalled": 0, "dead_money": 0,
	"ejections": 0, "all_in_preflop": 0, "illegal_actions": 0,
}

var t: HoldemTable
var _expected_total := 0
var _last_bb := -1
var _queued := {}  ## seat -> dead money queued for the next hand
var _dead := {}  ## seat -> dead money posted this hand (the model's own count)
var _stacks_before := []  ## stacks before the blinds, this hand
var _snap := []  ## per seat [stack, hand_bet, live], after the latest event
var _expect := {}  ## what the action being taken must do
var _min_raise := 0  ## the model's smallest legal raise increment this street
var _acted := {}  ## seats that have acted since the street began or the last raise
var _turn_from := -1  ## the model's seat to look left of for the next to act
var _context := ""


func run(seed_value: int, target_hands: int) -> void:
	rng.seed = hash(seed_value)
	while stats["hands"] < target_hands and failures.size() < max_failures:
		_play_table(target_hands)


func _fail(message: String) -> void:
	if failures.size() < max_failures:
		failures.append("%s: %s" % [_context, message])


func _play_table(target_hands: int) -> void:
	stats["tables"] += 1
	t = HoldemTable.new()
	t.rng.seed = rng.randi()
	var bb: int = [2, 4, 10, 20, 50][rng.randi() % 5]
	t.big_blind = bb
	t.small_blind = bb / 2 if rng.randf() < 0.8 else rng.randi_range(1, bb)
	var n := rng.randi_range(2, 9)
	for i in n:
		var roll := rng.randf()
		var chips: int
		if roll < 0.08:
			chips = 0  # busted before the table starts
		elif roll < 0.35:
			chips = rng.randi_range(1, bb * 2)  # tiny: all-in on the blinds
		elif roll < 0.8:
			chips = rng.randi_range(bb * 5, bb * 100)
		else:
			chips = rng.randi_range(1, bb * 400)
		t.add_seat("P%d" % i, rng.randi() % 2, chips)
	if t.players_with_chips() < 2:
		t.seats[0].stack += bb * 20
		t.seats[n - 1].stack += bb * 20
	t.hand_started.connect(_on_started)
	t.street_dealt.connect(_on_street)
	t.action_taken.connect(_on_action)
	t.hand_finished.connect(_on_finished)
	_expected_total = t.total_chips()
	_last_bb = -1
	_queued = {}
	var limit := rng.randi_range(20, 120)
	var played := 0
	while t.players_with_chips() >= 2 and played < limit and stats["hands"] < target_hands:
		_between_hands()
		if t.players_with_chips() < 2:
			break
		_play_hand()
		played += 1
		if failures.size() >= max_failures:
			return


func _between_hands() -> void:
	if rng.randf() < 0.2:
		for _k in rng.randi_range(1, 3):
			var i := rng.randi() % t.seats.size()
			var chips := rng.randi_range(1, t.big_blind * 3)
			t.queue_dead_money(i, chips)
			_queued[i] = _queued.get(i, 0) + chips
	if rng.randf() < 0.06:
		var i := rng.randi() % t.seats.size()
		# Only while the table can go on, unless it's a seat that's already out.
		if t.seats[i].stack == 0 or t.players_with_chips() >= 3:
			var had := t.seats[i].stack
			var removed := t.eject(i)
			if removed != had:
				_fail("eject returned %d, seat had %d" % [removed, had])
			_expected_total -= removed
			_queued.erase(i)
			stats["ejections"] += 1
			if not t.seats[i].ejected or t.seats[i].stack != 0:
				_fail("ejected seat still has chips")
	if rng.randf() < 0.04:
		t.small_blind *= 2
		t.big_blind *= 2


func _next_with_chips(from: int, step: int) -> int:
	var n := t.seats.size()
	for k in range(1, n + 1):
		var i := posmod(from + step * k, n)
		if t.seats[i].stack > 0:
			return i
	return -1


func _play_hand() -> void:
	stats["hands"] += 1
	_context = "table %d hand %d" % [stats["tables"], t.hand_number + 1]
	# The model's blinds: the big blind moves to the next seat with chips;
	# the small blind and button are the seats before it (heads-up, the
	# button posts the small blind).
	var dealt := 0
	_stacks_before = []
	for s in t.seats:
		_stacks_before.append(s.stack)
		if s.stack > 0:
			dealt += 1
	var button: int
	var sb: int
	var bb: int
	if _last_bb < 0:
		button = _next_with_chips(t.button, 1)
		sb = button if dealt == 2 else _next_with_chips(button, 1)
		bb = _next_with_chips(sb, 1)
	else:
		bb = _next_with_chips(_last_bb, 1)
		sb = _next_with_chips(bb, -1)
		button = sb if dealt == 2 else _next_with_chips(sb, -1)
	_last_bb = bb
	var posted := {}
	for i in t.seats.size():
		posted[i] = 0
	posted[sb] = mini(t.small_blind, _stacks_before[sb])
	posted[bb] = mini(t.big_blind, _stacks_before[bb])
	_dead = {}
	for i: int in _queued:
		if _stacks_before[i] > 0:
			_dead[i] = mini(_queued[i], _stacks_before[i] - posted[i])
			posted[i] += _dead[i]
			if _dead[i] > 0:
				stats["dead_money"] += 1
	_queued = {}
	_expect = {"start": true, "button": button, "sb": sb, "bb": bb, "posted": posted}

	t.start_hand()
	if _expect.has("start"):
		_fail("hand_started never fired")
	_check_state()
	var acts := 0
	while not t.hand_over:
		_random_action()
		acts += 1
		stats["actions"] += 1
		_check_state()
		if acts > 400:
			_fail("hand never ended")
			return
		if failures.size() >= max_failures:
			return


func _on_started(button: int) -> void:
	if not _expect.has("start"):
		_fail("hand_started out of turn")
		return
	if button != _expect["button"] or t.button != button:
		_fail("button on %d, expected %d" % [button, _expect["button"]])
	if t.small_blind_seat != _expect["sb"] or t.big_blind_seat != _expect["bb"]:
		_fail("blinds on %d/%d, expected %d/%d" % [t.small_blind_seat, t.big_blind_seat, _expect["sb"], _expect["bb"]])
	var cards := {}
	for i in t.seats.size():
		var s := t.seats[i]
		if s.dealt != (_stacks_before[i] > 0):
			_fail("seat %d dealt=%s with %d chips" % [i, s.dealt, _stacks_before[i]])
		if s.hand_bet != _expect["posted"][i]:
			_fail("seat %d posted %d, expected %d" % [i, s.hand_bet, _expect["posted"][i]])
		if s.stack != _stacks_before[i] - _expect["posted"][i]:
			_fail("seat %d stack after posting" % i)
		if s.hole.size() != (2 if s.dealt else 0):
			_fail("seat %d has %d hole cards" % [i, s.hole.size()])
		for c in s.hole:
			if cards.has(c):
				_fail("card %d dealt twice" % c)
			cards[c] = true
	if t.seats.filter(func(s: HoldemTable.Seat) -> bool: return s.dealt and not s.all_in).size() <= 1:
		stats["all_in_preflop"] += 1
	_expect = {}
	_min_raise = t.big_blind
	_acted = {}
	_turn_from = t.big_blind_seat  # first to act preflop is left of the big blind
	_snapshot()


func _on_street(_street: int, _board: Array) -> void:
	_min_raise = t.big_blind
	_acted = {}
	_turn_from = t.button  # after the flop, left of the button acts first


func _random_action() -> void:
	var seat := t.to_act
	var s := t.seats[seat]
	var legal := t.legal()
	var to_call := t.current_bet - s.street_bet
	var roll := rng.randf()
	var action: int
	var amount := 0
	if roll < 0.15:
		action = A.FOLD
	elif roll < 0.3:
		action = A.CHECK
	elif roll < 0.62:
		action = A.CALL
	elif roll < 0.96:
		action = A.RAISE
	else:
		action = [-1, 4, 99][rng.randi() % 3]  # not an action at all
		stats["illegal_actions"] += 1
	var lo: int = legal["min_raise_to"]
	var hi: int = legal["max_raise_to"]
	var pick := rng.randf()
	if pick < 0.6:
		amount = rng.randi_range(mini(lo, hi), hi)
	elif pick < 0.7:
		amount = lo
	elif pick < 0.8:
		amount = hi
	else:
		amount = [-100, 0, t.current_bet, lo - 1, hi + 1 + rng.randi() % 1000][rng.randi() % 5]
		stats["illegal_actions"] += 1

	# What act() promises.
	var kind := action
	if kind == A.RAISE and not legal["can_raise"]:
		kind = A.CALL
	if kind != A.CHECK and kind != A.CALL and kind != A.RAISE:
		kind = A.FOLD
	var street_bet := s.street_bet
	var folded := false
	var shown := kind
	var min_raise := _min_raise
	if kind == A.RAISE:
		street_bet = clampi(amount, lo, hi)
		min_raise = maxi(_min_raise, street_bet - t.current_bet)  # a short all-in doesn't lower it
	elif kind == A.FOLD:
		folded = to_call > 0
		shown = A.FOLD if folded else A.CHECK
	else:
		street_bet += maxi(0, mini(to_call, s.stack))
		shown = A.CALL if to_call > 0 else A.CHECK
	_expect = {"seat": seat, "action": shown, "street_bet": street_bet, "folded": folded, "min_raise": min_raise}
	t.act(action, amount)
	if not _expect.is_empty():
		_fail("act(%d, %d) by seat %d emitted nothing" % [action, amount, seat])
	_expect = {}


func _on_action(seat: int, action: int, _amount: int) -> void:
	if _expect.is_empty() or _expect.has("start"):
		_fail("action_taken out of turn")
		return
	var s := t.seats[seat]
	if seat != _expect["seat"] or action != _expect["action"] or s.street_bet != _expect["street_bet"] or s.folded != _expect["folded"]:
		_fail("seat %d: got action %d to %d folded=%s, expected seat %d action %d to %d folded=%s" % [
			seat, action, s.street_bet, s.folded, _expect["seat"], _expect["action"], _expect["street_bet"], _expect["folded"]])
	_min_raise = _expect["min_raise"]
	if action == A.RAISE:
		_acted = {}
	_acted[seat] = true
	_turn_from = seat
	_expect = {}
	_snapshot()


func _snapshot() -> void:
	_snap = []
	for s in t.seats:
		_snap.append([s.stack, s.hand_bet, s.live()])


func _check_state() -> void:
	var total := 0
	for i in t.seats.size():
		var s := t.seats[i]
		total += s.stack + s.hand_bet
		if s.stack < 0 or s.hand_bet < 0 or s.street_bet < 0 or s.street_bet > s.hand_bet:
			_fail("seat %d: stack %d, hand bet %d, street bet %d" % [i, s.stack, s.hand_bet, s.street_bet])
		if s.dealt and not s.folded and s.stack == 0 and not s.all_in:
			_fail("seat %d has no chips but isn't all-in" % i)
		if s.ejected and (s.stack != 0 or s.dealt):
			_fail("ejected seat %d is still in play" % i)
	if total != _expected_total:
		_fail("chips: %d on the table, expected %d" % [total, _expected_total])
	if t.pot() != total - t.seats.reduce(func(acc: int, s: HoldemTable.Seat) -> int: return acc + s.stack, 0):
		_fail("pot() isn't the sum of hand bets")
	if t.hand_over:
		if t.to_act != -1:
			_fail("hand over but %d is to act" % t.to_act)
		return
	if t.to_act < 0 or t.to_act >= t.seats.size():
		_fail("to_act is %d mid-hand" % t.to_act)
		return
	if t.min_raise != _min_raise:
		_fail("min_raise %d, expected %d" % [t.min_raise, _min_raise])
	# Next to act: the first seat left of the last actor (or of the big blind
	# or button when a round starts) that can act and still owes an action.
	var next := -1
	for k in range(1, t.seats.size() + 1):
		var i := (_turn_from + k) % t.seats.size()
		var o := t.seats[i]
		if o.can_act() and (not _acted.has(i) or o.street_bet < t.current_bet):
			next = i
			break
	if t.to_act != next:
		_fail("seat %d is to act, expected %d" % [t.to_act, next])
	var s := t.seats[t.to_act]
	if not s.can_act():
		_fail("seat %d is to act but can't" % t.to_act)
	if s.acted and s.street_bet >= t.current_bet:
		_fail("seat %d is to act but owes nothing" % t.to_act)
	var others := 0
	var most_other := 0
	for o in t.seats:
		if o != s and o.can_act():
			others += 1
		if o != s and o.live():
			most_other = maxi(most_other, o.street_bet)
	if others == 0 and s.street_bet >= most_other:
		_fail("seat %d is asked to act with nobody left to bet against" % t.to_act)
	var legal := t.legal()
	var to_call := mini(t.current_bet - s.street_bet, s.stack)
	if legal["seat"] != t.to_act or legal["to_call"] != to_call or to_call < 0:
		_fail("legal() to_call %d, expected %d" % [legal["to_call"], to_call])
	if legal["can_check"] != (to_call == 0):
		_fail("legal() can_check")
	if legal["max_raise_to"] != s.street_bet + s.stack:
		_fail("legal() max_raise_to")
	if legal["can_raise"] != (s.street_bet + s.stack > t.current_bet and others > 0):
		_fail("legal() can_raise is %s" % legal["can_raise"])
	if legal["can_raise"] and (legal["min_raise_to"] <= t.current_bet or legal["min_raise_to"] > legal["max_raise_to"]
			or legal["min_raise_to"] != mini(t.current_bet + t.min_raise, legal["max_raise_to"])):
		_fail("legal() raise range %d..%d over %d" % [legal["min_raise_to"], legal["max_raise_to"], t.current_bet])
	if t.min_raise < t.big_blind:
		_fail("min_raise %d under the big blind" % t.min_raise)


## Settles the hand again from the last snapshot, independently, and compares.
func _on_finished(result: Dictionary) -> void:
	var n := t.seats.size()
	var bets := []  # live chips (not dead) each seat put in
	var dead_total := 0
	var live: Array[int] = []
	for i in n:
		var dead: int = _dead.get(i, 0)
		bets.append(_snap[i][1] - dead)
		dead_total += dead
		if _snap[i][2]:
			live.append(i)
	# The uncalled bet: whatever the biggest bettor put in beyond everyone else.
	var returned := {}
	var top := 0
	for i in n:
		if bets[i] > bets[top]:
			top = i
	var second := 0
	for i in n:
		if i != top:
			second = maxi(second, bets[i])
	if bets[top] > second:
		returned[top] = bets[top] - second
		bets[top] = second
		stats["uncalled"] += 1
	var pots := []
	if live.size() == 1:
		var amount := dead_total
		for b: int in bets:
			amount += b
		pots.append({"amount": amount, "eligible": live, "winners": live.duplicate()})
	else:
		var board: Array = result["board"]
		if board.size() != 5:
			_fail("showdown with %d board cards" % board.size())
			return
		stats["showdowns"] += 1
		var scores := {}
		for i in live:
			scores[i] = Reference.best_of(t.seats[i].hole + board)
			if result["scores"].get(i, -1) != scores[i]:
				_fail("seat %d scored %d, reference says %d" % [i, result["scores"].get(i, -1), scores[i]])
		var levels: Array[int] = []
		for i in live:
			if not levels.has(bets[i]):
				levels.append(bets[i])
		levels.sort()
		var below := 0
		for level in levels:
			var amount := dead_total if pots.is_empty() else 0
			var eligible: Array[int] = []
			for i in n:
				amount += clampi(bets[i] - below, 0, level - below)
				if live.has(i) and bets[i] >= level:
					eligible.append(i)
			if amount > 0:
				pots.append({"amount": amount, "eligible": eligible})
			below = level
		for i in n:
			if bets[i] > below:
				pots[-1]["amount"] += bets[i] - below  # folded chips above every live seat
		if pots.size() > 1:
			stats["side_pots"] += 1
		for p: Dictionary in pots:
			var best := -1
			for i: int in p["eligible"]:
				best = maxi(best, scores[i])
			var winners: Array[int] = []
			# Seats in order from the first left of the button.
			for k in range(1, n + 1):
				var i := (t.button + k) % n
				if p["eligible"].has(i) and scores[i] == best:
					winners.append(i)
			p["winners"] = winners
			if winners.size() > 1:
				stats["split_pots"] += 1
				if p["amount"] % winners.size():
					stats["odd_chips"] += 1
	var payouts := {}
	for p: Dictionary in pots:
		var winners: Array = p["winners"]
		for k in winners.size():
			var won: int = p["amount"] / winners.size() + (1 if k < p["amount"] % winners.size() else 0)
			payouts[winners[k]] = payouts.get(winners[k], 0) + won

	if result["uncontested"] != (live.size() == 1):
		_fail("uncontested is %s with %d live seats" % [result["uncontested"], live.size()])
	if _sorted(result["payouts"]) != _sorted(payouts):
		_fail("payouts %s, expected %s" % [result["payouts"], payouts])
	if _sorted(result.get("returned", {})) != _sorted(returned):
		_fail("returned %s, expected %s" % [result.get("returned", {}), returned])
	var got_pots: Array = result["pots"]
	if got_pots.size() != pots.size():
		_fail("%d pots, expected %d: %s vs %s" % [got_pots.size(), pots.size(), got_pots, pots])
	else:
		for k in pots.size():
			var g: Dictionary = got_pots[k]
			var e: Dictionary = pots[k]
			if g["amount"] != e["amount"] or _sorted_list(g["eligible"]) != _sorted_list(e["eligible"]) or Array(g["winners"]) != Array(e["winners"]):
				_fail("pot %d is %s, expected %s" % [k, g, e])
	for i in n:
		var expected: int = _snap[i][0] + payouts.get(i, 0) + returned.get(i, 0)
		if t.seats[i].stack != expected:
			_fail("seat %d ends with %d, expected %d" % [i, t.seats[i].stack, expected])
		if t.seats[i].hand_bet != 0 or t.seats[i].street_bet != 0:
			_fail("seat %d still has chips out after the hand" % i)


func _sorted(d: Dictionary) -> Array:
	var out := []
	for k: int in d:
		if d[k] != 0:
			out.append([k, d[k]])
	out.sort()
	return out


func _sorted_list(a: Array) -> Array:
	var out := a.duplicate()
	out.sort()
	return out
