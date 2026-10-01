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
## Facing a bet, it reads its equity down by its style's `respect` (bets mean
## strength), and once it has bluffed and met resistance it only keeps
## bluffing as often as its `persistence` allows. Those two are what make
## the type chart's cycle work: see PlayStyle.
##
## The goal is readable, beatable characters, not strong poker; each style
## is an exaggeration so players can learn to spot it.

var style: PlayStyle
var bond := 0.5  ## how well this animal reads its teammates' signals, 0..1
var table_reads: TableReads  ## set by TeamMatch; null = no history to read
var equity_iterations := 120
var rng := RandomNumberGenerator.new()
var _signalled_street := -1
var _bluffing_hand := -1  ## hand number of this bot's latest bluff


func _init(play_style: PlayStyle, seed_value := 0) -> void:
	style = play_style
	if seed_value:
		# Godot's RandomNumberGenerator has no avalanche effect: seeds 1, 2, 3
		# give similar streams. Unhashed, balance runs that seeded matches
		# consecutively gave 48% to 78% for the same matchup depending on the
		# base seed, far beyond sampling noise.
		rng.seed = hash(seed_value)


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

	# Facing a real bet (not just the blinds), equity is read down by how much
	# this style respects aggression: a pot-sized bet means "they have it".
	# For strong hands it's scaled by `doubt` too: a Rock never lets go of a
	# strong hand, a careful Shark can be shoved off one by a Maniac.
	var unraised_preflop := table.street == HoldemTable.Street.PREFLOP and table.current_bet <= table.big_blind
	var facing_bet := to_call > 0 and not unraised_preflop
	var strong_equity := equity
	if facing_bet:
		var pressure := minf(1.0, 2.0 * to_call / float(table.pot()))
		var respect := style.respect * (1.0 - style.reads * _relentlessness(table, me))
		equity *= 1.0 - respect * pressure * 0.5
		strong_equity *= 1.0 - respect * style.doubt * pressure * 0.5
	var strength := equity * (others + 1)  # 1.0 = exactly a fair share
	var value := strong_equity * (others + 1) >= style.tightness * 1.5
	var playable := strength >= style.tightness
	var pot_odds := to_call / float(table.pot() + to_call) if to_call > 0 else 0.0

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
	# Once resisted (raised, or called after bluffing earlier this hand), a
	# style only keeps bluffing as often as its persistence allows.
	var resisted := facing_bet or _bluffing_hand == table.hand_number
	var bluff_chance := style.bluff_rate * (style.persistence if resisted else 1.0)
	if legal["can_raise"] and rng.randf() < bluff_chance:
		var bluff := _raise(table, legal)
		var risked: int = bluff["amount"] - seat.street_bet
		if risked <= style.bluff_risk * (seat.stack + seat.street_bet):
			_bluffing_hand = table.hand_number
			return bluff
	if to_call == 0:
		return _call()
	if equity >= pot_odds:
		return _call()
	var caught_bluffing := facing_bet and _bluffing_hand == table.hand_number
	if not caught_bluffing and rng.randf() < style.stickiness:
		return _call()
	return _check_or_fold()


## 0..1: how sure we are that whoever made the bet never backs down. A
## re-raise rate of 15% or less reads as normal, 50% or more as relentless.
func _relentlessness(table: HoldemTable, me: int) -> float:
	if table_reads == null or style.reads <= 0.0:
		return 0.0
	var bettor := -1
	for i in table.seats.size():
		if i != me and table.seats[i].live() and table.seats[i].street_bet == table.current_bet:
			bettor = i
	if bettor < 0:
		return 0.0
	return clampf((table_reads.reraise_rate(bettor) - 0.15) / 0.35, 0.0, 1.0)


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
