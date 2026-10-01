extends RefCounted
## A slow, obvious evaluator to check HandEvaluator against: try every
## five-card subset and score each one from sorted ranks. Written separately
## on purpose so a bug in one is unlikely to be repeated in the other.


static func best_of(cards: Array) -> int:
	var best := -1
	var n := cards.size()
	for a in n:
		for b in range(a + 1, n):
			for c in range(b + 1, n):
				for d in range(c + 1, n):
					for e in range(d + 1, n):
						best = maxi(best, score_five([cards[a], cards[b], cards[c], cards[d], cards[e]]))
	return best


static func score_five(five: Array) -> int:
	var ranks: Array[int] = []
	var suits := {}
	for c: int in five:
		ranks.append(Card.rank(c))
		suits[Card.suit(c)] = true
	ranks.sort()
	ranks.reverse()
	var flush := suits.size() == 1
	var unique := {}
	for r in ranks:
		unique[r] = unique.get(r, 0) + 1
	var straight_high := 0
	if unique.size() == 5:
		if ranks[0] - ranks[4] == 4:
			straight_high = ranks[0]
		elif ranks == [14, 5, 4, 3, 2]:
			straight_high = 5
	# Ranks ordered by (count, rank), highest first: the tie-break order.
	var groups: Array = unique.keys()
	groups.sort_custom(func(x: int, y: int) -> bool:
		return unique[x] > unique[y] or (unique[x] == unique[y] and x > y))
	var counts: Array = groups.map(func(r: int) -> int: return unique[r])

	var cat: int
	var order: Array = groups
	if straight_high and flush:
		cat = 8
		order = [straight_high]
	elif counts[0] == 4:
		cat = 7
	elif counts[0] == 3 and counts[1] == 2:
		cat = 6
	elif flush:
		cat = 5
	elif straight_high:
		cat = 4
		order = [straight_high]
	elif counts[0] == 3:
		cat = 3
	elif counts[0] == 2 and counts[1] == 2:
		cat = 2
	elif counts[0] == 2:
		cat = 1
	else:
		cat = 0
	var s := cat
	for i in 5:
		s = s * 16 + (order[i] if i < order.size() else 0)
	return s
