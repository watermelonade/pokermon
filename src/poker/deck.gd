class_name Deck
extends RefCounted
## A 52-card deck drawn from the top. Shuffles come from a seeded
## RandomNumberGenerator so a whole match can be replayed from its seed,
## which is what makes AI-vs-AI balance runs and bug reports reproducible.
## Tests stack the deck with `Deck.stacked()` to set up exact hands.

var cards: Array[int] = []
var _next := 0


static func shuffled(rng: RandomNumberGenerator) -> Deck:
	var deck := Deck.new()
	for c in 52:
		deck.cards.append(c)
	# Fisher-Yates, driven by our own rng rather than Array.shuffle(), which
	# uses the global seed and so can't be replayed.
	for i in range(51, 0, -1):
		var j := rng.randi_range(0, i)
		var t := deck.cards[i]
		deck.cards[i] = deck.cards[j]
		deck.cards[j] = t
	return deck


## A deck that deals exactly these cards first, in this order.
static func stacked(order: Array[int]) -> Deck:
	var deck := Deck.new()
	deck.cards = order.duplicate()
	return deck


func draw() -> int:
	assert(_next < cards.size(), "deck is empty")
	_next += 1
	return cards[_next - 1]


func remaining() -> int:
	return cards.size() - _next
