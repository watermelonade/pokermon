class_name SeatLayout
extends RefCounted
## Where everything at each seat goes on the 640x400 table, for 2 to 9
## seats: the badge (name plate), the portrait, the hole cards, the bet, the
## dealer button, and the overlays drawn over a seat (signal bubbles, an
## intercepted rival signal, a tell's puff, the dealer's glance, the boss
## leader's crown). TableView and InterceptOverlay draw with these; the
## tests check that no two seats' rects overlap each other or the HUD
## (tests/test_seat_layout.gd), which is how 7-9 seats were fitted.
##
## Up to 6 seats sit on an ellipse round the felt, exactly as the 3v3 table
## always has (the test holds the old formula). Boss tables bring 7 to 9
## seats (BossTable), and the ellipse doesn't fit them at 640x400: at 9
## seats the side seats' portraits ran off the screen's edge and the corner
## seats sat on the code panel and the signal legend. So 7-9 seats sit in
## two columns at the 6-seat table's side seats' x, you at the bottom as
## always, the top seat kept only where it fits:
##
##   7: you, 3 down each side (at the 6-seat side seats' heights, plus the
##      middle)
##   8: the same, plus the top seat
##   9: you, 4 down each side, 48 px apart (a badge and its bubble are 46)
##
## Two top seats (for 9) were tried first and didn't fit: a top seat's
## portrait and tell puff ran into the code panel (top left), or its
## portrait into the upper side seat's cards at showdown.
##
## Seat order runs clockwise from you as before (seat 1 is to your lower
## left and acts after you), so BossTable's "nearest seats" are the ones
## beside you on screen too.

const CENTER_Y := 172.0
const RADII := Vector2(262, 132)  ## the ellipse seats sit on, up to 6 seats
const BADGE := Vector2(96, 32)
const PORTRAIT := 32
const CARD_SMALL := Vector2(16, 22)
const CARD_BOARD := Vector2(22, 30)
const CARD_YOURS := Vector2(26, 36)
const HUMAN := 0
## The 6-seat table's side seats sit at 30 degrees off the horizontal.
static var SIDE_X := RADII.x * cos(deg_to_rad(30.0))
## Seats 7-9: offsets from the table's centre, seat by seat (see the top).
static var SLOTS := {
	7: [Vector2(0, 132), Vector2(-SIDE_X, 66), Vector2(-SIDE_X, 0), Vector2(-SIDE_X, -66),
		Vector2(SIDE_X, -66), Vector2(SIDE_X, 0), Vector2(SIDE_X, 66)],
	8: [Vector2(0, 132), Vector2(-SIDE_X, 66), Vector2(-SIDE_X, 0), Vector2(-SIDE_X, -66), Vector2(0, -132),
		Vector2(SIDE_X, -66), Vector2(SIDE_X, 0), Vector2(SIDE_X, 66)],
	9: [Vector2(0, 132), Vector2(-SIDE_X, 64), Vector2(-SIDE_X, 16), Vector2(-SIDE_X, -32), Vector2(-SIDE_X, -80),
		Vector2(SIDE_X, -80), Vector2(SIDE_X, -32), Vector2(SIDE_X, 16), Vector2(SIDE_X, 64)],
}


static func center(view: Vector2) -> Vector2:
	return Vector2(view.x / 2, CENTER_Y)


## Seat `i` of `n`: the middle of its badge.
static func seat_pos(n: int, i: int, view: Vector2) -> Vector2:
	n = maxi(n, 2)
	if SLOTS.has(n):
		return center(view) + SLOTS[n][i]
	var angle := deg_to_rad(90.0 + i * 360.0 / n)
	return center(view) + Vector2(cos(angle) * RADII.x, sin(angle) * RADII.y)


## Where everything at seat `i` goes: badge, portrait, cards, bet, button.
## The portrait sits on the outer side so the table side stays clear for
## cards and chips. `revealed`: hands turned over at showdown grow to board
## size, since a 16x22 card is too small to read across a 7" screen.
static func geom(n: int, i: int, view: Vector2, revealed := false) -> Dictionary:
	var p := seat_pos(n, i, view)
	var c := center(view)
	var toward := (c - p).normalized()
	var badge := Rect2((p - BADGE / 2).floor(), BADGE)
	var card_size := CARD_YOURS if i == HUMAN else (CARD_BOARD if revealed else CARD_SMALL)
	var pair_width := card_size.x * 2 + 2
	var cards: Vector2
	var portrait: Vector2
	var dealer_button: Vector2
	if i == HUMAN:
		cards = Vector2(p.x - pair_width / 2, badge.position.y - card_size.y - 4)
		portrait = Vector2(badge.position.x - 34, badge.end.y - 32)
		dealer_button = Vector2(badge.end.x + 9, badge.position.y + 7)
	elif absf(toward.x) > 0.5:  # side seats: cards beside the badge, toward the table
		var right := toward.x > 0
		cards = Vector2(badge.end.x + 4 if right else badge.position.x - pair_width - 4, p.y - card_size.y / 2)
		portrait = Vector2(badge.position.x - 34 if right else badge.end.x + 2, badge.end.y - 32)
		dealer_button = Vector2(badge.end.x + 7 if right else badge.position.x - 7, badge.position.y - 4)
	else:  # top seat: cards under the badge
		cards = Vector2(p.x - pair_width / 2, badge.end.y + 4)
		portrait = Vector2(badge.position.x - 34, badge.end.y - 32)
		dealer_button = Vector2(badge.end.x + 9, badge.position.y + 7)
	# The bet sits 55% of the way to the middle. Its number runs to the
	# right of the chips, so at 9 seats a right-hand seat's ran into the
	# cards of the seat above it at showdown: from 7 seats up, right-hand
	# bets come in a little further.
	var pull := 0.6 if n > 6 and toward.x < -0.5 else 0.55
	return {
		"center": p,
		"badge": badge,
		"portrait": portrait.floor(),
		"cards": cards.floor(),
		"card_size": card_size,
		"bet": (p.lerp(c, pull) + Vector2(0, 8)).floor(),
		"dealer_button": dealer_button,
	}


## Both hole cards at a seat.
static func cards_rect(g: Dictionary) -> Rect2:
	var size: Vector2 = g["card_size"]
	return Rect2(g["cards"], Vector2(size.x * 2 + 2, size.y))


## Your crew's signal bubble, `width` wide: over the badge (yours over your
## cards, which sit above your badge), kept on screen.
static func bubble_rect(g: Dictionary, i: int, width: float, view: Vector2) -> Rect2:
	var p: Vector2 = g["center"]
	var badge: Rect2 = g["badge"]
	var top: float = g["cards"].y if i == HUMAN else badge.position.y
	return Rect2(Vector2(clampf(p.x - width / 2, 2, view.x - width - 2), top - 14).floor(), Vector2(width, 11))


## A rival signal your crew intercepted (InterceptOverlay), `width` wide:
## left-aligned over the badge, clear of the dealer's eyes at its right end.
static func intercept_rect(g: Dictionary, width: float, view: Vector2) -> Rect2:
	var badge: Rect2 = g["badge"]
	return Rect2(Vector2(clampf(badge.position.x, 2, view.x - width - 2), badge.position.y - 14).floor(), Vector2(width, 11))


## A tell's puff over the portrait, `width` wide, once fully risen.
static func puff_rect(g: Dictionary, width: float, view: Vector2, rise := 5.0) -> Rect2:
	var portrait: Vector2 = g["portrait"]
	var x := clampf(portrait.x + 16 - width / 2, 2, view.x - width - 2)
	return Rect2(Vector2(x, portrait.y - 9 - rise).floor(), Vector2(width, 10))


## The dealer's eyes on a seat that just signalled (a 26x14 plate).
static func glance_rect(g: Dictionary, i: int) -> Rect2:
	var badge: Rect2 = g["badge"]
	var p: Vector2 = g["center"]
	var at := Vector2(badge.end.x - 26, badge.position.y - 12)
	if i == HUMAN:  # above your cards, beside your bubble, not over a card
		at = Vector2(p.x + 24, g["cards"].y - 14)
	return Rect2(at - Vector2(2, 2), Vector2(26, 14))


## The boss leader's crown: inside the badge's top-right corner, where the
## name row has room (names are at most about 60 px), so nothing drawn over
## or beside a seat ever covers it.
static func crown_rect(g: Dictionary) -> Rect2:
	var badge: Rect2 = g["badge"]
	return Rect2(Vector2(badge.end.x - 18, badge.position.y + 5), Vector2(11, 8))


## The chips bet this street and their number (`label_width` wide).
static func bet_rect(g: Dictionary, label_width: float) -> Rect2:
	var spot: Vector2 = g["bet"]
	return Rect2(spot + Vector2(-3, -5), Vector2(9 + label_width, 12))


## The dealer button (a 6 px radius disc).
static func button_rect(g: Dictionary) -> Rect2:
	var d: Vector2 = g["dealer_button"]
	return Rect2(d - Vector2(6, 6), Vector2(12, 12))
