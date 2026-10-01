extends TestCase
## The table's seat layout (SeatLayout) for 2-9 seats at the 640x400 base
## resolution: up to 6 seats exactly where they always were, and nothing at
## one seat (name plate, portrait, cards face down or turned over at
## showdown, bet, dealer button, crown, signal bubbles, an intercepted
## signal, a tell's puff, the dealer's glance) overlapping anything at
## another seat or the HUD (code panel, Heat panel, signal legend, board,
## pot, shoe, your hand in words, the text box, the command menu and the
## raise picker). Everything is measured at its worst case: the widest
## bubble text, a four-digit bet, the longest hand description.
##
## Only the table sizes the game deals: 6 (every 3v3) to 9 (3v6). Fewer
## seats keep the old ellipse, which never had to fit them (at 4-5 seats a
## side seat's portrait runs off the screen). One overlap is allowed: the
## top seat's bet over the shoe the cards come from, as the 3v3 table has
## always had it (the shoe is drawn under everything).
##
## Screenshots check how it looks; this checks that it fits.

const VIEW := Vector2(640, 400)
const L := UiFont.LARGE_SIZE
const S := UiFont.SMALL_SIZE


## The 3v3 table's seat geometry before SeatLayout, copied from
## table_view.gd as it was: 6 seats (and fewer) must not move a pixel.
func _old_geom(n: int, i: int, revealed: bool) -> Dictionary:
	var c := Vector2(VIEW.x / 2, 172)
	var angle := deg_to_rad(90.0 + i * 360.0 / maxi(n, 2))
	var p := c + Vector2(cos(angle) * 262, sin(angle) * 132)
	var toward := (c - p).normalized()
	var badge := Rect2((p - Vector2(48, 16)).floor(), Vector2(96, 32))
	var card_size := Vector2(26, 36) if i == 0 else (Vector2(22, 30) if revealed else Vector2(16, 22))
	var pair_width := card_size.x * 2 + 2
	var cards: Vector2
	var portrait: Vector2
	var dealer_button: Vector2
	if i == 0:
		cards = Vector2(p.x - pair_width / 2, badge.position.y - card_size.y - 4)
		portrait = Vector2(badge.position.x - 34, badge.end.y - 32)
		dealer_button = Vector2(badge.end.x + 9, badge.position.y + 7)
	elif absf(toward.x) > 0.5:
		var right := toward.x > 0
		cards = Vector2(badge.end.x + 4 if right else badge.position.x - pair_width - 4, p.y - card_size.y / 2)
		portrait = Vector2(badge.position.x - 34 if right else badge.end.x + 2, badge.end.y - 32)
		dealer_button = Vector2(badge.end.x + 7 if right else badge.position.x - 7, badge.position.y - 4)
	else:
		cards = Vector2(p.x - pair_width / 2, badge.end.y + 4)
		portrait = Vector2(badge.position.x - 34, badge.end.y - 32)
		dealer_button = Vector2(badge.end.x + 9, badge.position.y + 7)
	return {"center": p, "badge": badge, "portrait": portrait.floor(), "cards": cards.floor(), "card_size": card_size,
		"bet": (p.lerp(c, 0.55) + Vector2(0, 8)).floor(), "dealer_button": dealer_button}


func test_six_seats_and_fewer_are_exactly_where_they_were() -> void:
	for n in range(2, 7):
		for i in n:
			for revealed in [false, true]:
				check_eq(SeatLayout.geom(n, i, VIEW, revealed), _old_geom(n, i, revealed), "%d seats, seat %d" % [n, i])


func _w(text: String, size: int) -> float:
	var font := UiFont.large() if size == L else UiFont.small()
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


## Everything drawn at seat `i` of `n`, by name, at its worst case.
func _seat_rects(n: int, i: int) -> Dictionary:
	var g := SeatLayout.geom(n, i, VIEW)
	var shown := SeatLayout.geom(n, i, VIEW, true)
	var widest_gesture := 0.0
	for gesture: String in TableTalk.GESTURES:
		widest_gesture = maxf(widest_gesture, _w(gesture.to_lower(), S) + 8)
	var widest_intercept := 0.0
	for k in 4:
		var text := "%s: %s" % [InterceptOverlay.SHORT_GESTURES[k].to_lower(), InterceptOverlay.SHORT_MEANINGS[k]]
		widest_intercept = maxf(widest_intercept, _w(text, S) + 16)
	var widest_puff := 0.0
	for species: StringName in AnimalTells.TELLS:
		widest_puff = maxf(widest_puff, _w(AnimalTells.puff(species), S) + 6)
	var out := {
		"badge": g["badge"],
		"portrait": Rect2(g["portrait"], Vector2(SeatLayout.PORTRAIT, SeatLayout.PORTRAIT)),
		"cards": SeatLayout.cards_rect(g),
		"cards at showdown": SeatLayout.cards_rect(shown),
		"bet": SeatLayout.bet_rect(g, _w("9999", L)),
		"dealer button": SeatLayout.button_rect(g),
		"crown": SeatLayout.crown_rect(g),
		"bubble": SeatLayout.bubble_rect(g, i, widest_gesture, VIEW),
		"intercepted signal": SeatLayout.intercept_rect(g, widest_intercept, VIEW),
		"tell": SeatLayout.puff_rect(g, widest_puff, VIEW),
		"dealer's glance": SeatLayout.glance_rect(g, i),
	}
	if i == 0:
		out.erase("intercepted signal")  # only rivals' signals are intercepted
		out.erase("crown")  # you're never the boss
	return out


## The HUD, from table_view.gd / intercept_overlay.gd's drawing code.
func _hud_rects() -> Dictionary:
	var c := SeatLayout.center(VIEW)
	var legend_w := _w("Signals (pad / keys)", S)  # as TableView._draw_hud writes it
	for k in 4:
		var keys := "%s/%s" % [PadControls.SIGNAL_PAD[k], PadControls.SIGNAL_KEYS[k]]
		legend_w = maxf(legend_w, _w("%-4s %s: %s" % [keys, TableTalk.GESTURES[k], TableTalk.MEANINGS[k]], S))
	var you := SeatLayout.geom(9, 0, VIEW)
	var readout_at: Vector2 = you["cards"] + Vector2(SeatLayout.CARD_YOURS.x * 2 + 8, 20)
	return {
		"code panel": Rect2(4, 4, 196, 56),
		"Heat panel": Rect2(VIEW.x - 196, 4, 192, 42),
		"signal legend": Rect2(6, 288 - 7, legend_w, 46 + 9),
		"help hint": Rect2(VIEW.x - 6 - _w("Select: help", S), 288 + 46 - 7, _w("Select: help", S), 9),
		"board": Rect2(c + Vector2(-66, -22), Vector2(4 * 27 + 22, 30)),
		"pot": Rect2(c + Vector2(-37, 18 - 3), Vector2(11 + _w("Pot 9999", L), 14)),
		"shoe": Rect2(c + Vector2(-8, -50), Vector2(18, 24)),
		"your hand in words": Rect2(readout_at - Vector2(0, 9), Vector2(_w("Full house, Queens over Jacks", L), 11)),
		"text box": Rect2(4, VIEW.y - 54, 632, 50),
		"raise picker": Rect2(398 + 238 - 156, VIEW.y - 54 - 62, 156, 60),
	}


func test_no_seat_overlaps_another_or_the_hud() -> void:
	var hud := _hud_rects()
	for n in range(6, 10):
		var seats: Array[Dictionary] = []
		for i in n:
			seats.append(_seat_rects(n, i))
		for a in n:
			for name_a: String in seats[a]:
				var ra: Rect2 = seats[a][name_a]
				check(Rect2(Vector2.ZERO, VIEW).encloses(ra), "%d seats: seat %d's %s %s is off the screen" % [n, a, name_a, ra])
				for b in range(a + 1, n):
					for name_b: String in seats[b]:
						var rb: Rect2 = seats[b][name_b]
						check(not ra.intersects(rb), "%d seats: seat %d's %s %s overlaps seat %d's %s %s" % [n, a, name_a, ra, b, name_b, rb])
				for name_h: String in hud:
					if a == 0 and name_h == "your hand in words":
						continue  # beside your own cards, on purpose
					if name_a == "bet" and name_h == "shoe":
						continue  # see the top
					check(not ra.intersects(hud[name_h]), "%d seats: seat %d's %s %s overlaps the %s %s" % [n, a, name_a, ra, name_h, hud[name_h]])


func test_seven_to_nine_seats_go_round_clockwise_from_you() -> void:
	for n in range(7, 10):
		check_eq(SeatLayout.seat_pos(n, 0, VIEW), Vector2(320, 304), "%d seats: you at the bottom, as always" % n)
		check(SeatLayout.seat_pos(n, 1, VIEW).x < 320, "%d seats: seat 1 (acts after you) on your left" % n)
		check(SeatLayout.seat_pos(n, n - 1, VIEW).x > 320, "%d seats: the last seat on your right" % n)
		for i in range(1, n):
			var p := SeatLayout.seat_pos(n, i, VIEW)
			var q := SeatLayout.seat_pos(n, (i + 1) % n, VIEW)
			if p.x < 320 and q.x < 320:
				check(q.y < p.y, "%d seats: up the left side, seat %d to %d" % [n, i, i + 1])
			elif p.x > 320 and q.x > 320:
				check(q.y > p.y, "%d seats: down the right side, seat %d to %d" % [n, i, i + 1])
