class_name HoldemTable
extends RefCounted
## The rules of one no-limit hold'em table: seats, blinds, betting rounds,
## side pots and showdown. Nothing here knows about nodes, drawing or AI, so
## tests and AI-vs-AI balance runs can play thousands of hands headless, and
## the table scene just watches its signals and calls `act()` for the human.
##
## Simplifications, on purpose (none change who wins a pot):
## - No burn cards. A stacked test deck deals hole cards (one per seat at a
##   time, starting left of the button) and then the board, in order.
## - An all-in raise smaller than a full raise still reopens the betting.
## - A short big blind still sets the bet to call at the full big blind.
##
## Dead money (a fine from the floor) goes into the pot at the start of the
## next hand without counting as a bet, like a dead blind in a real card
## room: the seat can still win it back.

signal hand_started(button: int)
signal action_taken(seat: int, action: int, amount: int)
signal street_dealt(street: int, board: Array)
signal hand_finished(result: Dictionary)

enum Street { PREFLOP, FLOP, TURN, RIVER, SHOWDOWN }
enum Action { FOLD, CHECK, CALL, RAISE }

const STREET_NAMES := ["Preflop", "Flop", "Turn", "River", "Showdown"]
const ACTION_NAMES := ["folds", "checks", "calls", "raises to"]


class Seat:
	var name: String
	var team: int
	var stack: int
	var hole: Array[int] = []
	var dealt := false  ## has cards this hand (busted seats sit out)
	var folded := false
	var all_in := false
	var street_bet := 0  ## chips put in on the current street
	var hand_bet := 0  ## chips put in over the whole hand
	var acted := false
	var ejected := false  ## thrown out by the floor; never dealt in again

	func _init(seat_name: String, seat_team: int, chips: int) -> void:
		name = seat_name
		team = seat_team
		stack = chips

	func live() -> bool:
		return dealt and not folded

	func can_act() -> bool:
		return dealt and not folded and not all_in


var seats: Array[Seat] = []
var small_blind := 5
var big_blind := 10
var button := -1
var board: Array[int] = []
var street := Street.PREFLOP
var to_act := -1
var current_bet := 0
var min_raise := 0
var hand_over := true
var hand_number := 0
var last_result := {}
var rng := RandomNumberGenerator.new()
var _deck: Deck
var _dead_money := {}  ## seat -> chips to post dead at the next hand's start


func add_seat(seat_name: String, team: int, chips: int) -> Seat:
	var seat := Seat.new(seat_name, team, chips)
	seats.append(seat)
	return seat


func players_with_chips() -> int:
	return seats.filter(func(s: Seat) -> bool: return s.stack > 0).size()


func pot() -> int:
	var total := 0
	for s in seats:
		total += s.hand_bet
	return total


func total_chips() -> int:
	var total := 0
	for s in seats:
		total += s.stack + s.hand_bet
	return total


## Start a new hand. `stacked` sets the exact deal order (for tests).
func start_hand(stacked: Array[int] = []) -> void:
	assert(players_with_chips() >= 2, "need two players with chips")
	hand_number += 1
	for s in seats:
		s.hole.clear()
		s.dealt = s.stack > 0
		s.folded = false
		s.all_in = false
		s.street_bet = 0
		s.hand_bet = 0
		s.acted = false
	board.clear()
	last_result = {}
	street = Street.PREFLOP
	hand_over = false
	_deck = Deck.stacked(stacked) if stacked else Deck.shuffled(rng)

	button = _next_dealt(button)
	var sb: int
	var bb: int
	if _dealt_count() == 2:
		sb = button  # heads-up: the button posts the small blind
		bb = _next_dealt(button)
	else:
		sb = _next_dealt(button)
		bb = _next_dealt(sb)
	_put_in(seats[sb], small_blind)
	_put_in(seats[bb], big_blind)
	current_bet = big_blind
	min_raise = big_blind
	for i: int in _dead_money:
		var dead := mini(_dead_money[i], seats[i].stack)
		seats[i].stack -= dead
		seats[i].hand_bet += dead
		seats[i].all_in = seats[i].stack == 0
	_dead_money.clear()

	for _round in 2:
		var i := button
		for _n in _dealt_count():
			i = _next_dealt(i)
			seats[i].hole.append(_deck.draw())

	hand_started.emit(button)
	to_act = bb
	_advance()


## `chips` go into the next hand's pot from `seat`, dead (see the top).
func queue_dead_money(seat: int, chips: int) -> void:
	_dead_money[seat] = _dead_money.get(seat, 0) + chips


## Removes a seat from play between hands; its chips leave the game.
## Returns how many chips were removed.
func eject(seat: int) -> int:
	assert(hand_over, "eject between hands")
	var s := seats[seat]
	var removed := s.stack
	s.stack = 0
	s.ejected = true
	_dead_money.erase(seat)
	return removed


## What the seat to act may do right now.
func legal() -> Dictionary:
	var s := seats[to_act]
	var to_call := mini(current_bet - s.street_bet, s.stack)
	var max_to := s.street_bet + s.stack
	var min_to := mini(current_bet + min_raise, max_to)
	return {
		"seat": to_act,
		"to_call": to_call,
		"can_check": to_call == 0,
		"can_raise": max_to > current_bet,
		"min_raise_to": min_to,
		"max_raise_to": max_to,
	}


## The seat to act folds, checks, calls or raises. For RAISE, `amount` is the
## total to raise to on this street; it's clamped into the legal range, and
## raising everything is going all-in.
func act(action: int, amount := 0) -> void:
	assert(not hand_over and to_act >= 0, "no one is to act")
	var s := seats[to_act]
	var to_call := current_bet - s.street_bet
	match action:
		Action.FOLD:
			if to_call <= 0:
				action = Action.CHECK  # never fold when checking is free
			else:
				s.folded = true
		Action.CHECK:
			if to_call > 0:
				action = Action.CALL
				_put_in(s, to_call)
		Action.CALL:
			if to_call <= 0:
				action = Action.CHECK
			else:
				_put_in(s, to_call)
		Action.RAISE:
			var range_ := legal()
			if not range_["can_raise"]:
				action = Action.CALL
				_put_in(s, to_call)
			else:
				var raise_to := clampi(amount, range_["min_raise_to"], range_["max_raise_to"])
				_put_in(s, raise_to - s.street_bet)
				min_raise = maxi(min_raise, raise_to - current_bet)
				current_bet = raise_to
				for other in seats:
					if other != s:
						other.acted = false
	s.acted = true
	var shown := s.street_bet if action == Action.RAISE else (mini(to_call, s.street_bet) if action == Action.CALL else 0)
	action_taken.emit(seats.find(s), action, shown)
	_advance()


func _put_in(s: Seat, chips: int) -> void:
	var paid := mini(chips, s.stack)
	s.stack -= paid
	s.street_bet += paid
	s.hand_bet += paid
	if s.stack == 0:
		s.all_in = true


## After every action: end the hand, move to the next street, or pass the
## turn to the next seat that still owes an action.
func _advance() -> void:
	var live := seats.filter(func(s: Seat) -> bool: return s.live())
	if live.size() == 1:
		_finish_uncontested(live[0])
		return
	if not _round_complete():
		to_act = _next_owing(to_act)
		return
	while true:
		if street == Street.RIVER:
			_showdown()
			return
		_deal_street()
		var actors := seats.filter(func(s: Seat) -> bool: return s.can_act()).size()
		if actors >= 2:
			to_act = _next_owing(button)
			return
		# Everyone (or all but one) is all-in: run the board out.


func _round_complete() -> bool:
	for s in seats:
		if s.can_act() and (not s.acted or s.street_bet < current_bet):
			return false
	return true


func _deal_street() -> void:
	street += 1
	for s in seats:
		s.street_bet = 0
		s.acted = false
	current_bet = 0
	min_raise = big_blind
	var count := 3 if street == Street.FLOP else 1
	for _i in count:
		board.append(_deck.draw())
	street_dealt.emit(street, board.duplicate())


## Next seat after `from` that's in this hand (has cards, folded or not).
func _next_dealt(from: int) -> int:
	for k in range(1, seats.size() + 1):
		var i := (from + k) % seats.size()
		if seats[i].dealt:
			return i
	return -1


func _dealt_count() -> int:
	return seats.filter(func(s: Seat) -> bool: return s.dealt).size()


func _next_owing(from: int) -> int:
	for k in range(1, seats.size() + 1):
		var i := (from + k) % seats.size()
		var s := seats[i]
		if s.can_act() and (not s.acted or s.street_bet < current_bet):
			return i
	return -1


func _finish_uncontested(winner: Seat) -> void:
	var amount := pot()
	_clear_bets()
	winner.stack += amount
	var w := seats.find(winner)
	_end_hand({
		"uncontested": true,
		"payouts": {w: amount},
		"pots": [{"amount": amount, "eligible": [w], "winners": [w]}],
		"scores": {},
		"board": board.duplicate(),
	})


func _showdown() -> void:
	street = Street.SHOWDOWN
	var scores := {}
	for i in seats.size():
		if seats[i].live():
			scores[i] = HandEvaluator.evaluate(seats[i].hole + board)
	var pots := build_pots()
	var payouts := {}
	for p: Dictionary in pots:
		var best := -1
		var winners: Array[int] = []
		for i: int in p["eligible"]:
			if scores[i] > best:
				best = scores[i]
				winners = [i]
			elif scores[i] == best:
				winners.append(i)
		# Odd chips go to the first winners left of the button.
		winners.sort_custom(func(a: int, b: int) -> bool: return _from_button(a) < _from_button(b))
		var share: int = p["amount"] / winners.size()
		var odd: int = p["amount"] % winners.size()
		for k in winners.size():
			var won: int = share + (1 if k < odd else 0)
			payouts[winners[k]] = payouts.get(winners[k], 0) + won
		p["winners"] = winners
	_clear_bets()
	for i: int in payouts:
		seats[i].stack += payouts[i]
	_end_hand({
		"uncontested": false,
		"payouts": payouts,
		"pots": pots,
		"scores": scores,
		"board": board.duplicate(),
	})


## Main pot and side pots from what each seat put in. Each pot is
## {amount, eligible}: every live seat that put in at least that pot's level.
## Folded chips count toward the pots but can't win them.
func build_pots() -> Array[Dictionary]:
	var left := {}
	for i in seats.size():
		if seats[i].hand_bet > 0:
			left[i] = seats[i].hand_bet
	var pots: Array[Dictionary] = []
	while not left.is_empty():
		var level := -1
		for i: int in left:
			if seats[i].live() and (level < 0 or left[i] < level):
				level = left[i]
		if level < 0:
			# Only folded chips remain: they belong to the last pot.
			for i: int in left:
				pots[-1]["amount"] += left[i]
			break
		var amount := 0
		var eligible: Array[int] = []
		for i: int in left.keys():
			var take := mini(left[i], level)
			amount += take
			left[i] -= take
			if seats[i].live():
				eligible.append(i)
			if left[i] == 0:
				left.erase(i)
		pots.append({"amount": amount, "eligible": eligible})
	return pots


func _from_button(i: int) -> int:
	return (i - button - 1 + seats.size()) % seats.size()


func _clear_bets() -> void:
	for s in seats:
		s.street_bet = 0
		s.hand_bet = 0


func _end_hand(result: Dictionary) -> void:
	hand_over = true
	to_act = -1
	last_result = result
	hand_finished.emit(result)
