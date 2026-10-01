class_name PokerBot
extends RefCounted
## An AI seat. It estimates its equity (Equity.estimate), compares it with
## what a fair share of the pot would be, and lets its PlayStyle decide how
## to turn that into fold / call / raise. Then team play on top:
##
## - Soft play: once only teammates are left in a pot, it checks it down
##   (or folds to a teammate's bet) instead of fighting over team chips.
## - Signals: it tells teammates "I'm strong" / "I'm weak", and steps aside
##   when a teammate signals strength, or raises when asked to attack.
##
## The goal is readable, beatable characters, not strong poker; each style
## is an exaggeration so players can learn to spot it.

var style: PlayStyle
var bond := 0.5  ## how well this animal reads its teammates' signals, 0..1
var equity_iterations := 120
var rng := RandomNumberGenerator.new()
var _signalled_street := -1


func _init(play_style: PlayStyle, seed_value := 0) -> void:
	style = play_style
	if seed_value:
		rng.seed = seed_value


## Chooses an action for seat `me`, who must be the seat to act.
## Returns {"action": HoldemTable.Action, "amount": raise-to total}.
func decide(table: HoldemTable, me: int, talk: TableTalk) -> Dictionary:
	var seat := table.seats[me]
	var legal := table.legal()
	var to_call: int = legal["to_call"]

	var opponents := 0
	var teammates: Array[int] = []
	for i in table.seats.size():
		if i == me or not table.seats[i].live():
			continue
		if table.seats[i].team == seat.team:
			teammates.append(i)
		else:
			opponents += 1
	if opponents == 0:
		return _check_or_fold()  # soft play

	var others := opponents + teammates.size()
	var equity := Equity.estimate(seat.hole, table.board, others, equity_iterations, rng)
	var strength := equity * (others + 1)  # 1.0 = exactly a fair share
	var pot_odds := to_call / float(table.pot() + to_call) if to_call > 0 else 0.0
	var value := strength >= style.tightness * 1.5
	var playable := strength >= style.tightness

	_maybe_signal(table, me, talk, value, strength, teammates)

	var teammate_strong := false
	var asked_to_attack := false
	for t in teammates:
		for sig in talk.read_from(me, t, bond, rng):
			if sig == TableTalk.Sig.STRONG or sig == TableTalk.Sig.BACK_OFF:
				teammate_strong = true
			elif sig == TableTalk.Sig.ATTACK:
				asked_to_attack = true

	if teammate_strong and not value:
		return _check_or_fold()  # step aside for the teammate
	if value:
		if legal["can_raise"] and rng.randf() < style.aggression:
			return _raise(table, legal)
		return _call()
	if asked_to_attack and playable and legal["can_raise"]:
		return _raise(table, legal)
	if playable and (to_call == 0 or equity >= pot_odds):
		if to_call == 0 and legal["can_raise"] and rng.randf() < style.aggression * 0.3:
			return _raise(table, legal)
		return _call()
	if legal["can_raise"] and rng.randf() < style.bluff_rate:
		return _raise(table, legal)
	if to_call == 0:
		return _call()
	if equity >= pot_odds or rng.randf() < style.stickiness:
		return _call()
	return _check_or_fold()


func _maybe_signal(table: HoldemTable, me: int, talk: TableTalk, value: bool, strength: float, teammates: Array[int]) -> void:
	if teammates.is_empty() or _signalled_street == table.street + table.hand_number * 10:
		return
	if rng.randf() >= style.chattiness:
		return
	if value:
		talk.send(me, TableTalk.Sig.STRONG, table.street)
	elif strength < style.tightness * 0.7:
		talk.send(me, TableTalk.Sig.WEAK, table.street)
	else:
		return
	_signalled_street = table.street + table.hand_number * 10


func _raise(table: HoldemTable, legal: Dictionary) -> Dictionary:
	var size := 0.6 + style.aggression * 0.5  # fraction of the pot
	var raise_to := table.current_bet + maxi(table.min_raise, int(table.pot() * size))
	if raise_to >= legal["max_raise_to"] * 0.7:
		raise_to = legal["max_raise_to"]  # that close to all-in: just shove
	return {"action": HoldemTable.Action.RAISE, "amount": raise_to}


func _call() -> Dictionary:
	return {"action": HoldemTable.Action.CALL, "amount": 0}


func _check_or_fold() -> Dictionary:
	# The table turns a free fold into a check.
	return {"action": HoldemTable.Action.FOLD, "amount": 0}
