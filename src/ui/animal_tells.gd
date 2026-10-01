class_name AnimalTells
extends RefCounted
## When an animal at the table gives away its hand. Every species has a tell
## (Species.CATALOG "tell"): the Owl hoots when it likes its cards, the
## Raccoon rubs its paws when bluffing, and so on. Showing it is how players
## learn to read animals, which is the game, so the rules here follow the
## catalog's wording, judged from the animal's real cards.
##
## Kept subtle on purpose: a tell fires at most once per animal per hand
## (the caller tracks that) and only on CHANCE of the moments it could. If
## it fired every time it would be a readout, not a read; at 0.5 a player
## who watches sees it often enough to learn it within a few orbits, and
## still can't be sure the Owl is weak when it stays quiet.
##
## Pure logic (no nodes) so tests can check every species' rule.

enum When {
	STRONG,  ## acts with a strong hand
	BLUFF,  ## raises with nothing
	GOOD_FLOP,  ## the flop hits it
	CALLING,  ## before it calls (a tell you see while it thinks)
	MONSTER,  ## acts with a monster
}

## Moments the table asks about.
enum Moment { THINKING, ACTED, FLOP }

## How strong a hand is, for tells (not for play: bots use Equity).
enum Strength { WEAK, MEDIUM, STRONG, MONSTER }

const CHANCE := 0.5

## species -> when it shows, the puff over its head, the log line (%s = name).
const TELLS := {
	&"owl": {"when": When.STRONG, "puff": "hoo...", "log": "%s hoots softly."},
	&"raccoon": {"when": When.BLUFF, "puff": "*rub rub*", "log": "%s rubs its paws together."},
	&"goose": {"when": When.GOOD_FLOP, "puff": "HONK!", "log": "%s honks at the flop."},
	&"cat": {"when": When.STRONG, "puff": "*flick*", "log": "%s's tail flicks."},
	&"squirrel": {"when": When.CALLING, "puff": "*stack stack*", "log": "%s restacks its chips."},
	&"possum": {"when": When.MONSTER, "puff": "...", "log": "%s goes perfectly still."},
}


## Whether `species` shows its tell at this moment. `action` is the
## HoldemTable.Action taken (ACTED) or about to be taken (THINKING), -1 for
## FLOP. `roll` is a 0..1 random number, passed in so tests are exact.
static func fires(species: StringName, moment: Moment, hole: Array, board: Array, action: int, roll: float) -> bool:
	if not TELLS.has(species) or hole.size() < 2 or roll >= CHANCE:
		return false
	var when: When = TELLS[species]["when"]
	var s := strength(hole, board)
	match when:
		When.STRONG:
			return moment == Moment.ACTED and action != HoldemTable.Action.FOLD and s >= Strength.STRONG
		When.MONSTER:
			return moment == Moment.ACTED and action != HoldemTable.Action.FOLD and s == Strength.MONSTER
		When.BLUFF:
			return moment == Moment.ACTED and action == HoldemTable.Action.RAISE and s == Strength.WEAK
		When.GOOD_FLOP:
			return moment == Moment.FLOP and s >= Strength.STRONG
		When.CALLING:
			return moment == Moment.THINKING and action == HoldemTable.Action.CALL
	return false


static func puff(species: StringName) -> String:
	return TELLS[species]["puff"] if TELLS.has(species) else ""


static func log_line(species: StringName, animal_name: String) -> String:
	return TELLS[species]["log"] % animal_name if TELLS.has(species) else ""


## Preflop: aces/kings are monsters, tens+ or two big cards strong, any pair
## or two cards ten+ medium. After the flop it only counts what the hole
## cards add to the board: a pair on the board is everyone's pair.
static func strength(hole: Array, board: Array) -> Strength:
	var a := maxi(Card.rank(hole[0]), Card.rank(hole[1]))
	var b := mini(Card.rank(hole[0]), Card.rank(hole[1]))
	if board.size() < 3:
		if a == b:
			return Strength.MONSTER if a >= 13 else (Strength.STRONG if a >= 10 else Strength.MEDIUM)
		if b >= 12:
			return Strength.STRONG
		return Strength.MEDIUM if b >= 10 else Strength.WEAK
	var score := HandEvaluator.evaluate(hole + board)
	var cat := HandEvaluator.category(score)
	if cat <= _board_category(board):
		return Strength.WEAK  # the hole cards add nothing
	if cat >= HandEvaluator.Category.TRIPS:
		return Strength.MONSTER
	if cat == HandEvaluator.Category.TWO_PAIR:
		return Strength.STRONG
	if cat == HandEvaluator.Category.PAIR:
		var pair_rank := HandReadout.score_rank(score, 0)
		var top := 0
		for c: int in board:
			top = maxi(top, Card.rank(c))
		return Strength.STRONG if pair_rank >= top else Strength.MEDIUM  # top pair or an overpair
	return Strength.WEAK


## The board's own category. Under five cards only repeated ranks count.
static func _board_category(board: Array) -> int:
	if board.size() >= 5:
		return HandEvaluator.category(HandEvaluator.evaluate(board))
	var counts := {}
	for c: int in board:
		counts[Card.rank(c)] = counts.get(Card.rank(c), 0) + 1
	var best := 0
	var pairs := 0
	for n: int in counts.values():
		best = maxi(best, n)
		if n >= 2:
			pairs += 1
	if best == 4:
		return HandEvaluator.Category.QUADS
	if best == 3:
		return HandEvaluator.Category.TRIPS
	if pairs == 2:
		return HandEvaluator.Category.TWO_PAIR
	return HandEvaluator.Category.PAIR if pairs == 1 else HandEvaluator.Category.HIGH_CARD
