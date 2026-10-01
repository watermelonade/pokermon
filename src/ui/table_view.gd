extends Control
## The 3v3 table, placeholder edition: you (seat 0) and two animal teammates
## against a rival crew. Everything is drawn from code at the 640x400 base
## resolution (x2 on the Steam Deck's 1280x800) so it's playable before any
## art exists; swap the _draw() calls for sprites as Aseprite art arrives.
##
## Controls: the D-pad / stick moves between Fold / Call / Raise, A confirms,
## bumpers (or Q/E) size the raise, and the four back buttons (or 1-4) send
## a signal to your teammates. Input actions live in project.godot.
##
## Heat: the dealer (watchful by default) notices signals. Both crews' Heat
## shows top right, with the warning (40) and fine (70) lines marked; the
## legend says what your next signal would cost. Get thrown out and your crew
## forfeits the match.
##
## Embedding: set `setup` (who sits where), `dealer_kind`, `starting_chips`
## and `embedded = true` before adding the scene to the tree; it emits
## `finished(won)` when the match ends and the player presses A, instead of
## offering a rematch. With no `setup`, the demo crews below play.
##
## Dev flags (after `--`): --autoplay lets a bot play your seat,
## --dealer=STRICT (or STREET, ASLEEP, RELAXED, WATCHFUL, BOUGHT) picks the
## dealer, --screenshot=path.png saves the screen after --shot-after=seconds
## and quits.

const YOUR_CREW := Color("2f6f6a")
const RIVALS := Color("7a3b2e")
const FELT := Color("2b5b3a")
const FELT_RIM := Color("4a3424")
const ROOM := Color("1d1a24")
const TEXT := Color("f4ecd8")
const QUIET := Color("a89f8c")
const GOLD := Color("e8c35a")
const HOT := Color("d9603b")
const BOT_DELAY := 0.6
const HUMAN := 0

signal finished(won: bool)

## Who sits where, in seat order: {"name": String, "team": int, "animal":
## Animal or null for you}. Seat 0 must be you.
var setup: Array[Dictionary] = []
var embedded := false
var starting_chips := 1000

var match_: TeamMatch
var last_action := {}  ## seat -> text under its name
var bubbles := {}  ## seat -> [text, expires_at_msec]
var log_lines: Array[String] = []
var banner := ""
var raise_to := 0
var autoplay := false
var dealer_kind := Dealer.Kind.WATCHFUL  ## set before adding to the tree
var alert := ""  ## the dealer's latest words, above the controls
var _alert_until := 0
var _font: Font
var _buttons: HBoxContainer
var _fold: Button
var _call: Button
var _raise: Button
var _hint: Label
var _waiting_for_next := false


func _ready() -> void:
	_font = ThemeDB.fallback_font
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var shot_path := ""
	var shot_after := 2.5
	for arg in OS.get_cmdline_user_args():
		if arg == "--autoplay":
			autoplay = true
		elif arg.begins_with("--screenshot="):
			shot_path = arg.get_slice("=", 1)
		elif arg.begins_with("--shot-after="):
			shot_after = float(arg.get_slice("=", 1))
		elif arg.begins_with("--dealer="):
			dealer_kind = Dealer.Kind.keys().find(arg.get_slice("=", 1)) as Dealer.Kind
	if setup.is_empty():
		setup = demo_setup()
	_build_controls()
	_new_match()
	if shot_path:
		_take_screenshot(shot_path, shot_after)


## You, the Owl and the Raccoon against the Goose, the Cat and the Squirrel.
static func demo_setup() -> Array[Dictionary]:
	var rivals: Array[Animal] = [Species.individual(&"goose", 0), Species.individual(&"cat", 0), Species.individual(&"squirrel", 0)]
	var crew: Array[Animal] = [null, Species.individual(&"owl", 0), Species.individual(&"raccoon", 0)]
	var out: Array[Dictionary] = []
	for i in 3:
		var mine: Animal = crew[i]
		out.append({"name": "You" if mine == null else mine.name, "team": 0, "animal": mine})
		out.append({"name": rivals[i].name, "team": 1, "animal": rivals[i]})
	return out


func _build_controls() -> void:
	_buttons = HBoxContainer.new()
	_buttons.add_theme_constant_override("separation", 6)
	add_child(_buttons)
	_fold = _make_button("Fold", func() -> void: _human_act(HoldemTable.Action.FOLD))
	_call = _make_button("Call", func() -> void: _human_act(HoldemTable.Action.CALL))
	_raise = _make_button("Raise", func() -> void: _human_act(HoldemTable.Action.RAISE))
	_hint = Label.new()
	_hint.add_theme_font_size_override("font_size", 8)
	_hint.add_theme_color_override("font_color", QUIET)
	_hint.text = "LB/RB or Q/E: raise size"
	add_child(_hint)
	_set_controls_visible(false)


func _make_button(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(76, 22)
	b.add_theme_font_size_override("font_size", 10)
	b.pressed.connect(on_press)
	_buttons.add_child(b)
	return b


func _new_match() -> void:
	match_ = TeamMatch.new(int(Time.get_unix_time_from_system()))
	for i in setup.size():
		var animal: Animal = setup[i]["animal"]
		var bot: PokerBot = null
		if animal:
			bot = animal.make_bot(i + 1 + int(Time.get_ticks_usec()))
		elif autoplay:
			bot = PokerBot.new(PlayStyle.preset(PlayStyle.Kind.SHARK))
		match_.add_player(setup[i]["name"], setup[i]["team"], starting_chips, bot)
	match_.heat.dealer = Dealer.preset(dealer_kind)
	var t := match_.table
	t.action_taken.connect(_on_action)
	t.street_dealt.connect(_on_street)
	t.hand_finished.connect(_on_hand_finished)
	match_.heat.warned.connect(func(team: int, _seat: int) -> void:
		_dealer_says("Dealer to %s: \"Hands where I can see them.\"" % _crew_name(team)))
	match_.heat.fined.connect(func(team: int, _seat: int) -> void:
		_dealer_says("The floor fines %s: a dead big blind each, next hand." % _crew_name(team)))
	match_.heat.ejection_called.connect(func(_team: int, seat: int) -> void:
		_dealer_says("%s is thrown out after this hand!" % ("You are" if seat == HUMAN else t.seats[seat].name)))
	log_lines.clear()
	alert = ""
	_next_hand()


func _crew_name(team: int) -> String:
	return "your crew" if team == match_.table.seats[HUMAN].team else "the rival crew"


func _dealer_says(line: String) -> void:
	alert = line
	_alert_until = Time.get_ticks_msec() + 4000
	_log(line)
	queue_redraw()


func _next_hand() -> void:
	_waiting_for_next = false
	var thrown_out := match_.table.seats[HUMAN].ejected
	if thrown_out or match_.is_over():
		var w := match_.winner()
		banner = "Your crew wins the match!" if w == 0 else ("The rival crew wins." if w == 1 else "A draw.")
		if thrown_out:
			banner = "You were thrown out. Your crew forfeits."
		elif match_.caught_team() >= 0:
			banner = "The floor caught their boss! " + banner
		banner += "  Press A to continue." if embedded else "  Press A for a rematch."
		_waiting_for_next = true
		queue_redraw()
		return
	banner = ""
	last_action.clear()
	match_.start_hand()
	_log("Hand %d, blinds %d/%d" % [match_.table.hand_number, match_.table.small_blind, match_.table.big_blind])
	_run()


## Bots act one at a time with a short pause, until it's your turn.
func _run() -> void:
	while true:
		queue_redraw()
		var t := match_.table
		if t.hand_over:
			_waiting_for_next = true
			get_tree().create_timer(3.0).timeout.connect(func() -> void:
				if _waiting_for_next and not match_.is_over() and not t.seats[HUMAN].ejected:
					_next_hand())
			return
		if match_.waiting_on_human():
			_start_human_turn()
			return
		await get_tree().create_timer(BOT_DELAY).timeout
		var seat := t.to_act
		var choice := match_.bots[seat].decide(t, seat, match_.talk)
		_show_new_signals()
		t.act(choice["action"], choice["amount"])


func _start_human_turn() -> void:
	var legal := match_.table.legal()
	raise_to = legal["min_raise_to"]
	_call.text = "Check" if legal["can_check"] else "Call %d" % legal["to_call"]
	_raise.disabled = not legal["can_raise"]
	_update_raise_label()
	_set_controls_visible(true)
	_call.grab_focus()


func _update_raise_label() -> void:
	var legal := match_.table.legal()
	_raise.text = "All-in %d" % raise_to if raise_to >= legal["max_raise_to"] else "Raise to %d" % raise_to


func _human_act(action: int) -> void:
	if not match_.waiting_on_human():
		return
	_set_controls_visible(false)
	match_.table.act(action, raise_to)
	_run()


func _set_controls_visible(on: bool) -> void:
	_buttons.visible = on
	_hint.visible = on


func _unhandled_input(event: InputEvent) -> void:
	if _waiting_for_next and event.is_action_pressed("ui_accept"):
		if match_.is_over() or match_.table.seats[HUMAN].ejected:
			if embedded:
				var won := match_.winner() == 0 and not match_.table.seats[HUMAN].ejected
				finished.emit(won)
				return
			_new_match()
		else:
			_next_hand()
		get_viewport().set_input_as_handled()
		return
	var t := match_.table
	if t.hand_over:
		return
	for i in 4:
		if event.is_action_pressed("signal_%d" % (i + 1)):
			match_.talk.send(HUMAN, i as TableTalk.Sig, t.street)
			_show_new_signals()
	if match_.waiting_on_human():
		var legal := t.legal()
		if event.is_action_pressed("raise_more"):
			raise_to = mini(raise_to + t.big_blind, legal["max_raise_to"])
			_update_raise_label()
		elif event.is_action_pressed("raise_less"):
			raise_to = maxi(raise_to - t.big_blind, legal["min_raise_to"])
			_update_raise_label()


## Shows signals from your side of the table as bubbles. The rival crew's
## signals stay hidden until reads exist to intercept them.
func _show_new_signals() -> void:
	for s: Dictionary in match_.talk.sent:
		var seat: int = s["from"]
		if match_.table.seats[seat].team != match_.table.seats[HUMAN].team:
			continue
		if s.get("shown", false):
			continue
		s["shown"] = true
		bubbles[seat] = [TableTalk.GESTURES[s["sig"]].to_lower(), Time.get_ticks_msec() + 2500]
		var who := "You" if seat == HUMAN else match_.table.seats[seat].name
		_log("%s: %s (\"%s\")" % [who, TableTalk.GESTURES[s["sig"]].to_lower(), TableTalk.MEANINGS[s["sig"]]])
	queue_redraw()


func _on_action(seat: int, action: int, amount: int) -> void:
	var s := match_.table.seats[seat]
	var text: String = HoldemTable.ACTION_NAMES[action]
	if action == HoldemTable.Action.RAISE or (action == HoldemTable.Action.CALL and amount > 0):
		text += " %d" % amount
	if s.all_in:
		text = "all-in %d" % s.street_bet
	last_action[seat] = text
	_log("%s %s" % [s.name, text])


func _on_street(street: int, board: Array) -> void:
	for seat: int in last_action.keys():
		if not match_.table.seats[seat].folded:
			last_action.erase(seat)
	_log("%s: %s" % [HoldemTable.STREET_NAMES[street], " ".join(board.map(Card.label))])


func _on_hand_finished(result: Dictionary) -> void:
	var t := match_.table
	var parts: Array[String] = []
	for seat: int in result["payouts"]:
		var line := "%s wins %d" % [t.seats[seat].name, result["payouts"][seat]]
		if not result["uncontested"]:
			line += " with %s" % HandEvaluator.describe(result["scores"][seat]).to_lower()
		parts.append(line)
	banner = ", ".join(parts)
	_log(banner)


func _log(line: String) -> void:
	log_lines.append(line)
	if log_lines.size() > 5:
		log_lines.pop_front()


func _process(_delta: float) -> void:
	if alert and Time.get_ticks_msec() > _alert_until:
		alert = ""
		queue_redraw()
	if bubbles:
		var now := Time.get_ticks_msec()
		for seat: int in bubbles.keys():
			if bubbles[seat][1] < now:
				bubbles.erase(seat)
				queue_redraw()


func _layout_center() -> Vector2:
	return Vector2(size.x / 2, 172)


func _seat_pos(i: int) -> Vector2:
	var angle := deg_to_rad(90.0 + i * 60.0)
	return _layout_center() + Vector2(cos(angle) * 262, sin(angle) * 132)


func _draw() -> void:
	var t := match_.table
	var c := _layout_center()
	draw_rect(Rect2(Vector2.ZERO, size), ROOM)
	_draw_ellipse(c, Vector2(236, 112), FELT_RIM)
	_draw_ellipse(c, Vector2(228, 104), FELT)

	# Board and pot.
	for k in 5:
		var pos := c + Vector2(-66 + k * 27, -22)
		if k < t.board.size():
			CardArt.draw_card(self, pos, t.board[k], true)
		else:
			draw_rect(Rect2(pos, Vector2(22, 30)), FELT.darkened(0.15))
	_text(c + Vector2(0, 24), "Pot %d" % t.pot(), 10, TEXT, true)
	if banner:
		_text(c + Vector2(0, -34), banner, 10, GOLD, true)
	if alert:
		_text(Vector2(c.x, size.y - 42), alert, 8, HOT, true)  # clear of the bets

	var showdown: bool = t.hand_over and not t.last_result.get("uncontested", true)
	for i in t.seats.size():
		_draw_seat(i, showdown)

	# Log, top left; signal legend, bottom left.
	for k in log_lines.size():
		_text(Vector2(8, 12 + k * 10), log_lines[k], 8, QUIET)
	_text(Vector2(8, 326), "Signals (back buttons, or 1-4):", 8, QUIET)
	for k in 4:
		_text(Vector2(8, 338 + k * 10), "%d  %s: %s" % [k + 1, TableTalk.GESTURES[k], TableTalk.MEANINGS[k]], 8, QUIET)
	if match_.heat.dealer.watching() and not t.hand_over:
		var cost := match_.heat.cost_of_next(HUMAN)
		var hot := match_.heat.level(t.seats[HUMAN].team) + cost >= Heat.FINE
		_text(Vector2(8, 384), "Next signal: +%d Heat" % roundi(cost), 8, HOT if hot else QUIET)
	_draw_heat(Vector2(size.x - 196, 12))

	# Controls along the bottom.
	_buttons.position = Vector2(c.x - 120, size.y - 30)
	_hint.position = Vector2(c.x + 128, size.y - 24)


## The dealer, and a Heat bar per crew with the warning and fine lines.
func _draw_heat(at: Vector2) -> void:
	var heat := match_.heat
	if not heat.dealer.watching():
		_text(at, "No dealer: signal freely", 8, QUIET)
		return
	_text(at, "Dealer: %s" % heat.dealer.display_name(), 8, QUIET)
	var mine := match_.table.seats[HUMAN].team
	for k in 2:
		var team := mine if k == 0 else 1 - mine
		var y := at.y + 6 + k * 12
		_text(Vector2(at.x, y + 7), "Your crew" if k == 0 else "Rivals", 8, QUIET)
		var bar := Rect2(Vector2(at.x + 54, y), Vector2(132, 7))
		draw_rect(bar, FELT_RIM)
		var level := heat.level(team)
		var color := QUIET if level < Heat.WARNING else (GOLD if level < Heat.FINE else HOT)
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * minf(level, Heat.EJECT) / Heat.EJECT, bar.size.y)), color)
		for line in [Heat.WARNING, Heat.FINE]:
			var x: float = bar.position.x + bar.size.x * line / Heat.EJECT
			draw_line(Vector2(x, y - 1), Vector2(x, y + 8), TEXT)


func _draw_seat(i: int, showdown: bool) -> void:
	var t := match_.table
	var s := t.seats[i]
	var p := _seat_pos(i)
	var c := _layout_center()
	var toward := (c - p).normalized()
	var badge := Rect2(p - Vector2(48, 15), Vector2(96, 30))
	var team_color := YOUR_CREW if s.team == t.seats[HUMAN].team else RIVALS
	if s.ejected or (s.stack == 0 and s.hand_bet == 0 and t.hand_over):
		team_color = team_color.darkened(0.6)
	if i == t.to_act:
		draw_rect(badge.grow(2), GOLD)
	draw_rect(badge, team_color)
	_text(badge.position + Vector2(5, 11), s.name, 10, TEXT)
	_text(badge.position + Vector2(91, 11), "%d" % s.stack, 10, TEXT, false, true)
	var status: String = "folded" if s.folded else last_action.get(i, "")
	if s.ejected:
		status = "thrown out"
	_text(badge.position + Vector2(5, 25), status, 8, QUIET)

	# Hole cards, on the table side of the badge.
	if s.dealt and not s.folded:
		var show := i == HUMAN or (showdown and s.live())
		var card_size := Vector2(26, 36) if i == HUMAN else Vector2(16, 22)
		var pair_width := card_size.x * 2 + 2
		var at: Vector2
		if i == HUMAN:
			at = Vector2(p.x - pair_width / 2, badge.position.y - card_size.y - 4)
		elif absf(toward.x) > 0.5:  # side seats: beside the badge, toward the table
			var x := badge.end.x + 4 if toward.x > 0 else badge.position.x - pair_width - 4
			at = Vector2(x, p.y - card_size.y / 2)
		else:  # top seat: under the badge
			at = Vector2(p.x - pair_width / 2, badge.end.y + 4)
		for k in s.hole.size():
			CardArt.draw_card(self, at + Vector2(k * (card_size.x + 2), 0), s.hole[k], show, card_size)

	# Chips bet this street, between the seat and the pot.
	if s.street_bet > 0:
		var chip := p.lerp(c, 0.55) + Vector2(0, 8)
		draw_circle(chip, 3, GOLD)
		_text(chip + Vector2(6, 3), "%d" % s.street_bet, 8, TEXT)

	if i == t.button:
		# On the outer side of the badge, away from the cards.
		var d := Vector2(badge.position.x - 8 if toward.x > 0.5 else badge.end.x + 8, badge.position.y + 6)
		draw_circle(d, 6, TEXT)
		_text(d + Vector2(0, 3), "D", 8, ROOM, true)

	if bubbles.has(i):
		var text: String = bubbles[i][0]
		var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x + 8
		var r := Rect2(Vector2(p.x - w / 2, badge.position.y - 15), Vector2(w, 12))
		draw_rect(r, TEXT)
		_text(r.position + Vector2(w / 2, 9), text, 8, ROOM, true)


func _draw_ellipse(center: Vector2, radii: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for k in 48:
		var a := TAU * k / 48.0
		points.append(center + Vector2(cos(a) * radii.x, sin(a) * radii.y))
	draw_colored_polygon(points, color)


func _text(pos: Vector2, text: String, font_size: int, color: Color, centered := false, right := false) -> void:
	var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	if centered:
		pos.x -= w / 2
	elif right:
		pos.x -= w
	draw_string(_font, pos.floor(), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _take_screenshot(path: String, after: float) -> void:
	await get_tree().create_timer(after).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("screenshot saved: ", path)
	get_tree().quit()
