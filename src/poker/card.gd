class_name Card
extends RefCounted
## Cards are plain ints, 0..51, so hands, decks and boards are cheap arrays
## that the evaluator and the Monte Carlo equity loop can churn through
## thousands of times per AI decision without allocating objects.
##
## card = rank_index * 4 + suit, where rank_index 0..12 is 2..A and suit is
## 0 clubs, 1 diamonds, 2 hearts, 3 spades.

const RANK_CHARS := "23456789TJQKA"
const SUIT_CHARS := "cdhs"
const SUIT_SYMBOLS := ["♣", "♦", "♥", "♠"]


## Rank as a number, 2..14 (ace high).
static func rank(card: int) -> int:
	return (card >> 2) + 2


static func suit(card: int) -> int:
	return card & 3


static func make(card_rank: int, card_suit: int) -> int:
	return (card_rank - 2) * 4 + card_suit


## "As" -> ace of spades, "Td" -> ten of diamonds.
static func parse(text: String) -> int:
	var r := RANK_CHARS.find(text[0].to_upper())
	var s := SUIT_CHARS.find(text[1].to_lower())
	assert(r >= 0 and s >= 0, "bad card: %s" % text)
	return r * 4 + s


## "As Kd 7c" -> [cards]
static func parse_many(text: String) -> Array[int]:
	var out: Array[int] = []
	for part in text.split(" ", false):
		out.append(parse(part))
	return out


static func label(card: int) -> String:
	return RANK_CHARS[rank(card) - 2] + SUIT_CHARS[suit(card)]


static func rank_label(card: int) -> String:
	var r := rank(card)
	return "10" if r == 10 else RANK_CHARS[r - 2]


static func is_red(card: int) -> bool:
	return suit(card) == 1 or suit(card) == 2
