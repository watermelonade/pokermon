class_name HandReadout
extends RefCounted
## Your hand in words ("Pair of 7s", "Two pair, Kings and 7s"), shown next
## to your cards. On a 7" screen, reading five small board cards plus your
## two for a straight or a flush is the hardest part of the table for a new
## player, and the game is about reading animals, not boards. So the table
## says what you have, plus a flush or straight draw on the flop and turn
## when one of your cards is part of it (a draw that's all on the board is
## everyone's, so it isn't mentioned).
##
## Made hands come from HandEvaluator's score: category in the top bits,
## then the deciding ranks four bits each, most significant first.

const FACE_NAMES := {11: "Jack", 12: "Queen", 13: "King", 14: "Ace"}
const FACE_PLURALS := {11: "Jacks", 12: "Queens", 13: "Kings", 14: "Aces"}


## "Ace", "King", ... "10", "2".
static func rank_name(r: int) -> String:
	return FACE_NAMES.get(r, str(r))


## "Aces", "Kings", ... "10s", "2s".
static func rank_plural(r: int) -> String:
	return FACE_PLURALS.get(r, "%ds" % r)


## The `n`th deciding rank of a HandEvaluator score (0 = most significant).
static func score_rank(score: int, n: int) -> int:
	return (score >> (16 - 4 * n)) & 0xF


static func describe(hole: Array, board: Array) -> String:
	if hole.size() < 2:
		return ""
	if board.size() < 3:
		return _describe_preflop(hole)
	var score := HandEvaluator.evaluate(hole + board)
	var cat := HandEvaluator.category(score)
	var r0 := score_rank(score, 0)
	var r1 := score_rank(score, 1)
	var text := ""
	match cat:
		HandEvaluator.Category.HIGH_CARD:
			text = "%s high" % rank_name(r0)
		HandEvaluator.Category.PAIR:
			text = "Pair of %s" % rank_plural(r0)
		HandEvaluator.Category.TWO_PAIR:
			text = "Two pair, %s and %s" % [rank_plural(r0), rank_plural(r1)]
		HandEvaluator.Category.TRIPS:
			text = "Three %s" % rank_plural(r0)
		HandEvaluator.Category.STRAIGHT:
			text = "Straight to the %s" % rank_name(r0)
		HandEvaluator.Category.FLUSH:
			text = "Flush, %s high" % rank_name(r0)
		HandEvaluator.Category.FULL_HOUSE:
			text = "Full house, %s over %s" % [rank_plural(r0), rank_plural(r1)]
		HandEvaluator.Category.QUADS:
			text = "Four %s" % rank_plural(r0)
		HandEvaluator.Category.STRAIGHT_FLUSH:
			text = "Royal flush" if r0 == 14 else "Straight flush to the %s" % rank_name(r0)
	if board.size() < 5 and cat < HandEvaluator.Category.STRAIGHT:
		if has_flush_draw(hole, board):
			text += ", flush draw"
		elif has_straight_draw(hole, board):
			text += ", straight draw"
	return text


static func _describe_preflop(hole: Array) -> String:
	var a := maxi(Card.rank(hole[0]), Card.rank(hole[1]))
	var b := mini(Card.rank(hole[0]), Card.rank(hole[1]))
	if a == b:
		return "Pair of %s" % rank_plural(a)
	var text := "%s-%s" % [rank_name(a), rank_name(b)]
	if Card.suit(hole[0]) == Card.suit(hole[1]):
		text += " suited"
	return text


## Four cards of one suit, at least one of them yours.
static func has_flush_draw(hole: Array, board: Array) -> bool:
	for suit in 4:
		var mine := hole.filter(func(c: int) -> bool: return Card.suit(c) == suit).size()
		var theirs := board.filter(func(c: int) -> bool: return Card.suit(c) == suit).size()
		if mine > 0 and mine + theirs == 4:
			return true
	return false


## Four of the five ranks of some straight (open-ended or gutshot), where
## the board alone doesn't already have those four.
static func has_straight_draw(hole: Array, board: Array) -> bool:
	return _best_run(hole + board) == 4 and _best_run(board) < 4


## The most ranks any one five-rank straight window holds (the ace plays
## high and low).
static func _best_run(cards: Array) -> int:
	var mask := 0
	for c: int in cards:
		mask |= 1 << Card.rank(c)
	if mask & (1 << 14):
		mask |= 1 << 1
	var best := 0
	for low in range(1, 11):
		var n := 0
		for r in range(low, low + 5):
			if mask & (1 << r):
				n += 1
		best = maxi(best, n)
	return best
