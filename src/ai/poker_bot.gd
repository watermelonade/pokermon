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
## Interception (when the match has it on): what its crew has noticed and
## understood of the other crew's signals this hand nudges it. Facing a bet
## from a seat that said "I'm strong" it reads its equity down 15% more, from
## one that said "I'm weak" 15% less, and a pot where an opponent said "I'm
## weak" (and nobody "strong") gets bluffed more; the sizes are
## Interception's constants. With it off, none of that
## code runs, so decisions and random draws are exactly as before (the
## type chart depends on it; tests/test_interception.gd holds a golden log).
##
## A boss crew plays as one while its leader runs it (`knows_crew_cards`,
## set by TeamMatch.set_leader; "our signals are older than you"): each
## member knows its live teammates' cards. It weighs its hand against the
## opponents only, with its teammates' cards out of the deck, and steps
## aside for any teammate whose hand is better, so the crew plays its best
## hand of up to six against your three.
##
## Leaderless (boss crews, TeamMatch.leaderless): once its crew's leader
## busts, a goon stops signalling (nobody's calling the plays) and plays
## scared: tighter, half the bluffs, half the loose calls (lose_leader). It
## swaps in a copy of its style, so nothing changes for anyone else.
##
## The goal is readable, beatable characters, not strong poker; each style
## is an exaggeration so players can learn to spot it.

var style: PlayStyle
var bond := 0.5  ## how well this animal reads its teammates' signals, 0..1
var table_reads: TableReads  ## set by TeamMatch; null = no history to read
var heat: Heat  ## set by TeamMatch; null = nobody watching
var interception: Interception  ## set by TeamMatch; read only while enabled
var equity_iterations := 120
var leaderless := false  ## its crew's leader is out: see lose_leader()
var knows_crew_cards := false  ## a boss crew with its leader: see the top
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


## How a goon plays once its boss is out (see the top): its equity bar for
## playing a hand goes up by this factor, its bluffs and loose calls down.
const LEADERLESS_TIGHTNESS := 1.25
const LEADERLESS_BLUFFS := 0.5
const LEADERLESS_STICKINESS := 0.5


## Its crew's leader just busted: no more signals, and it plays scared.
func lose_leader() -> void:
	if leaderless:
		return
	leaderless = true
	knows_crew_cards = false
	style = style.duplicate()
	style.tightness *= LEADERLESS_TIGHTNESS
	style.bluff_rate *= LEADERLESS_BLUFFS
	style.stickiness *= LEADERLESS_STICKINESS


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
	var crew_cards: Array[int] = []
	if knows_crew_cards and not leaderless:
		for t in teammates:
			crew_cards.append_array(table.seats[t].hole)
		others = opponents  # teammates aren't competition, and their cards are out of the deck
	var equity := Equity.estimate(seat.hole, table.board, others, equity_iterations, rng, crew_cards)
	var crew_better := crew_cards and _teammate_better(table, me, teammates, opponents, equity)
	var heard := {}  ## seat -> meanings this crew intercepted and understood
	if interception and interception.enabled:
		heard = interception.readings(seat.team)

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
		var bettor_said := _bettor_said(table, me, heard) if heard else -1
		if bettor_said >= 0:
			# The bettor told its crew it's strong (believe the bet more) or
			# weak (less): equity moves by READ_WEIGHT either way.
			var shift := Interception.READ_WEIGHT * (1.0 if bettor_said == TableTalk.Sig.STRONG else -1.0)
			equity *= 1.0 - shift
			strong_equity *= 1.0 - shift * style.doubt
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

	if crew_better or (teammate_strong and not value):
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
	if heard and _weak_pot(table, heard):
		bluff_chance = minf(1.0, bluff_chance + Interception.WEAK_BLUFF)
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


## A boss crew member's check (knows_crew_cards): does a live teammate
## hold a better hand against the opponents than ours (`mine`)?
func _teammate_better(table: HoldemTable, me: int, teammates: Array[int], opponents: int, mine: float) -> bool:
	for t in teammates:
		var dead: Array[int] = table.seats[me].hole.duplicate()
		for u in teammates:
			if u != t:
				dead.append_array(table.seats[u].hole)
		if Equity.estimate(table.seats[t].hole, table.board, opponents, equity_iterations, rng, dead) > mine:
			return true
	return false


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


## What the seat that made the bet we face said, as far as this crew could
## tell: TableTalk.Sig.STRONG (also for "let me have it"), WEAK, or -1.
func _bettor_said(table: HoldemTable, me: int, heard: Dictionary) -> int:
	for i in table.seats.size():
		if i != me and table.seats[i].live() and table.seats[i].street_bet == table.current_bet and heard.has(i):
			return _gist(heard[i])
	return -1


## True when an opponent still in the pot said "I'm weak" and none said strong.
func _weak_pot(table: HoldemTable, heard: Dictionary) -> bool:
	var weak := false
	for i: int in heard:
		if not table.seats[i].live():
			continue
		var gist := _gist(heard[i])
		if gist == TableTalk.Sig.STRONG:
			return false
		weak = weak or gist == TableTalk.Sig.WEAK
	return weak


## The latest strong-or-weak thing a seat said this hand, or -1.
func _gist(meanings: Array) -> int:
	for k in range(meanings.size() - 1, -1, -1):
		match meanings[k]:
			TableTalk.Sig.STRONG, TableTalk.Sig.BACK_OFF:
				return TableTalk.Sig.STRONG
			TableTalk.Sig.WEAK:
				return TableTalk.Sig.WEAK
	return -1


func _maybe_signal(table: HoldemTable, me: int, talk: TableTalk, value: bool, strength: float, teammates: Array[int]) -> void:
	if leaderless or teammates.is_empty() or _signalled_street == table.street + table.hand_number * 10:
		return
	if rng.randf() >= style.chattiness:
		return
	if heat and heat.dealer.watching():
		# Every animal has a comfort line for its crew's Heat: careful ones
		# stop near the warning (40), careless ones push towards ejection
		# (100). Careless ones also sometimes forget the line altogether,
		# which is how crews get thrown out. (A first try scaled the chance
		# of signalling by Heat; who got caught then depended on how long
		# their hands ran, not on caution: see README.)
		var after := heat.level(table.seats[me].team) + heat.cost_of_next(me)
		var comfort := Heat.EJECT - style.caution * (Heat.EJECT - Heat.WARNING)
		if after >= comfort and rng.randf() >= (1.0 - style.caution) * 0.5:
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
