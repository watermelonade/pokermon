class_name HandEvaluator
extends RefCounted
## Scores the best five-card poker hand out of 5 to 7 cards as one int, so
## comparing two hands is comparing two numbers.
##
## Score layout: category * 16^5 + up to five ranks (2..14), four bits each,
## most significant first. The ranks are the ones that decide ties, in the
## order they decide them: a full house is [trips, pair], two pair is
## [high pair, low pair, kicker], a straight is just its top card.
##
## It works straight from rank counts and suit bitmasks instead of trying
## all 21 five-card subsets. tests/test_hand_evaluator.gd checks it against
## a brute-force reference on thousands of random hands, and
## tools/verify_evaluator.gd enumerates all 2,598,960 five-card hands
## against the known category counts.

enum Category {
	HIGH_CARD,
	PAIR,
	TWO_PAIR,
	TRIPS,
	STRAIGHT,
	FLUSH,
	FULL_HOUSE,
	QUADS,
	STRAIGHT_FLUSH,
}

const CATEGORY_NAMES := [
	"High card", "Pair", "Two pair", "Three of a kind", "Straight",
	"Flush", "Full house", "Four of a kind", "Straight flush",
]


static func evaluate(cards: Array) -> int:
	var counts := PackedInt32Array()
	counts.resize(15)
	var suit_masks := PackedInt32Array([0, 0, 0, 0])
	var suit_counts := PackedInt32Array([0, 0, 0, 0])
	var rank_mask := 0
	for c: int in cards:
		var r := (c >> 2) + 2
		var s := c & 3
		counts[r] += 1
		suit_masks[s] |= 1 << r
		suit_counts[s] += 1
		rank_mask |= 1 << r

	var flush_mask := 0
	for s in 4:
		if suit_counts[s] >= 5:
			flush_mask = suit_masks[s]
	if flush_mask:
		var sf_high := _straight_high(flush_mask)
		if sf_high:
			return _score(Category.STRAIGHT_FLUSH, [sf_high])

	var quads: Array[int] = []
	var trips: Array[int] = []
	var pairs: Array[int] = []
	var singles: Array[int] = []
	for r in range(14, 1, -1):
		match counts[r]:
			4: quads.append(r)
			3: trips.append(r)
			2: pairs.append(r)
			1: singles.append(r)

	if quads:
		var kicker := 0
		for r in range(14, 1, -1):
			if counts[r] > 0 and r != quads[0]:
				kicker = r
				break
		return _score(Category.QUADS, [quads[0], kicker])

	if trips and (trips.size() >= 2 or pairs):
		var pair_rank := pairs[0] if pairs else 0
		if trips.size() >= 2:
			pair_rank = maxi(pair_rank, trips[1])
		return _score(Category.FULL_HOUSE, [trips[0], pair_rank])

	if flush_mask:
		return _score(Category.FLUSH, _top_ranks(flush_mask, 5))

	var straight_high := _straight_high(rank_mask)
	if straight_high:
		return _score(Category.STRAIGHT, [straight_high])

	if trips:
		return _score(Category.TRIPS, [trips[0]] + singles.slice(0, 2))

	if pairs.size() >= 2:
		# A third pair's rank can be the kicker.
		var kicker := 0
		if pairs.size() > 2:
			kicker = pairs[2]
		if singles:
			kicker = maxi(kicker, singles[0])
		return _score(Category.TWO_PAIR, [pairs[0], pairs[1], kicker])

	if pairs:
		return _score(Category.PAIR, [pairs[0]] + singles.slice(0, 3))

	return _score(Category.HIGH_CARD, singles.slice(0, 5))


static func category(score: int) -> int:
	return score >> 20


static func describe(score: int) -> String:
	return CATEGORY_NAMES[category(score)]


## Highest card of the best straight in a rank bitmask (bit r = rank r), or 0.
static func _straight_high(mask: int) -> int:
	if mask & (1 << 14):
		mask |= 1 << 1  # the ace also plays low: A-2-3-4-5
	for high in range(14, 4, -1):
		if (mask >> (high - 4)) & 0x1F == 0x1F:
			return high
	return 0


static func _top_ranks(mask: int, n: int) -> Array[int]:
	var out: Array[int] = []
	for r in range(14, 1, -1):
		if mask & (1 << r):
			out.append(r)
			if out.size() == n:
				break
	return out


static func _score(cat: int, ranks: Array) -> int:
	var s := cat
	for i in 5:
		s = (s << 4) | (ranks[i] if i < ranks.size() else 0)
	return s
