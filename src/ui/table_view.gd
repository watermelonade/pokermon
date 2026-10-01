extends Control
## The 3v3 table: you (seat 0) and two animal teammates against a rival
## crew. Everything is drawn from code at the 640x400 base resolution (x2 on
## the Steam Deck's 1280x800); animal art is used when it exists (AnimalArt)
## and the rest is still placeholder until Aseprite art arrives.
##
## Controls: the D-pad / stick moves between Fold / Call / Raise, A confirms,
## bumpers (or Q/E) jump between raise sizes (min, half pot, pot, 2x pot,
## all-in: RaiseSizes), D-pad up/down fine-tunes by a big blind, the four
## back buttons (or 1-4) send a signal to your teammates, and Select (or H,
## F1) opens a help card. Input actions live in project.godot; help has no
## action there yet, so it's read straight from the Back button and keys.
##
## Motion: cards slide from the shoe to the seats, board cards flip in,
## chips slide to the pot at the end of a street and the pot slides to the
## winner. All of it is a short beat (0.1-0.35s) booked on a TableMotion
## timeline, so an all-in run-out plays out card by card instead of all at
## once. Nothing waits on an animation except the next actor: a bot starts
## thinking, or your buttons appear, when the beat before it has landed.
## Bots decide when their turn starts and then "think" for a time that
## depends on what they chose (folds are quick, raises take a moment), so the
## pace feels like animals, and the Squirrel's tell can show before it calls.
##
## There are no Tweens or awaits in the game flow: the overworld frees this
## scene as soon as `finished` fires, and _process / _draw simply stop with
## it. (Only the --screenshot dev path awaits.)
##
## Tells: each animal shows its species' tell (AnimalTells) some of the time:
## a little puff over its picture and a line in the log.
##
## Heat: the dealer (watchful by default) notices signals. When someone
## signals, the dealer's eyes flash over that seat and the crew's Heat bar
## (top right, warning and fine lines marked) climbs to its new level. The
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
## and quits; --shots=N with --shot-every=seconds saves N frames instead
## (path_0.png, path_1.png...), for checking motion; --seed=N makes the deal
## and the bots repeatable; --help-open starts with the help card shown.

const YOUR_CREW := Color("2f6f6a")
const RIVALS := Color("7a3b2e")
const FELT := Color("2b5b3a")
const FELT_RIM := Color("4a3424")
const ROOM := Color("1d1a24")
const PANEL := Color("14121a")
const TEXT := Color("f4ecd8")
const QUIET := Color("a89f8c")
const GOLD := Color("e8c35a")
const HOT := Color("d9603b")
const CHIP := Color("e8c35a")
const CHIP_EDGE := Color("8a6a2a")
const HUMAN := 0
const S := UiFont.SMALL_SIZE
const L := UiFont.LARGE_SIZE

# Motion, in seconds. Short on purpose: a hand has ~20 of these beats.
const DEAL_FLIGHT := 0.18
const DEAL_STAGGER := 0.05
const FLIP := 0.2
const FLOP_STAGGER := 0.11
const COLLECT := 0.22
const BET_FLIGHT := 0.15
const MUCK := 0.18
const REVEAL := 0.22
const PAYOUT := 0.35
const RUNOUT_PAUSE := 0.55  ## between streets when everyone's all-in
const NEXT_HAND_PAUSE := 2.6
const BOUNCE := 0.25
const TELL_TIME := 1.8
const GLANCE_TIME := 0.9
const CARD_SMALL := Vector2(16, 22)
const CARD_BOARD := Vector2(22, 30)
const CARD_YOURS := Vector2(26, 36)
const BUTTON_SIZE := Vector2(98, 22)

signal finished(won: bool)

## Who sits where, in seat order: {"name": String, "team": int, "animal":
## Animal or null for you}. Seat 0 must be you.
var setup: Array[Dictionary] = []
var embedded := false
var starting_chips := 1000

var match_: TeamMatch
var last_action := {}  ## seat -> short text under its name
var bubbles := {}  ## seat -> [text, expires_at_msec]
var log_lines: Array[String] = []
var banner := ""
var raise_to := 0
var autoplay := false
var dealer_kind := Dealer.Kind.WATCHFUL  ## set before adding to the tree
var alert := ""  ## the dealer's latest words, above the controls
var _alert_until := 0

enum Flow { BOT_THINKING, HUMAN, HAND_DONE, MATCH_DONE }
var _flow := Flow.HAND_DONE
var _decide_at := 0.0  ## when the bot to act makes up its mind
var _act_at := 0.0  ## when it acts on it
var _choice := {}  ## that decision, made at _decide_at
var _controls_at := 0.0  ## when your buttons appear
var _controls_shown_at := 0.0
var _next_hand_at := 0.0
var _match_banner := ""
var _match_banner_at := INF

var _motion := TableMotion.new()
var _hole_land := {}  ## seat -> [time card 0 lands, time card 1 lands]
var _board_flip: Array[float] = []  ## when each board card starts to flip
var _reveal_at := INF  ## showdown: when the live hands turn over
var _result_at := INF  ## when the result shows and the pot moves
var _holds := {}  ## key -> [shown value, until]: numbers that wait for chips to land
var _last_bets := {}  ## seat -> street bet after the latest action
var _turn_seat := -1
var _turn_at := 0.0
var _tells := {}  ## seat -> [puff text, start time]
var _told := {}  ## seat -> true once its tell showed this hand
var _still := {}  ## seat -> true: gone perfectly still (the Possum's tell)
var _gains: Array[Array] = []  ## [seat, amount, start time]: "+240" over winners
var _glance := {}  ## {"seat", "t"}: the dealer just noticed a signal
var _heat_shown := {}  ## team -> the level the bar shows (catches up)
var _heat_flash := {}  ## team -> when it last rose
var _help_open := false
var _sizes: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()
var _seed := 0
var _buttons: HBoxContainer
var _fold: Button
var _call: Button
var _raise: Button


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var shot_path := ""
	var shot_after := 2.5
	var shots := 1
	var shot_every := 0.1
	for arg in OS.get_cmdline_user_args():
		if arg == "--autoplay":
			autoplay = true
		elif arg.begins_with("--screenshot="):
			shot_path = arg.get_slice("=", 1)
		elif arg.begins_with("--shot-after="):
			shot_after = float(arg.get_slice("=", 1))
		elif arg.begins_with("--shots="):
			shots = maxi(1, int(arg.get_slice("=", 1)))
		elif arg.begins_with("--shot-every="):
			shot_every = float(arg.get_slice("=", 1))
		elif arg.begins_with("--dealer="):
			dealer_kind = Dealer.Kind.keys().find(arg.get_slice("=", 1)) as Dealer.Kind
		elif arg.begins_with("--seed="):
			_seed = int(arg.get_slice("=", 1))
		elif arg == "--help-open":
			_help_open = true
	if setup.is_empty():
		setup = demo_setup()
	_rng.seed = hash(_seed) if _seed else int(Time.get_ticks_usec())
	theme = _make_theme()
	_build_controls()
	_new_match()
	if shot_path:
		_take_screenshots(shot_path, shot_after, shots, shot_every)


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


# --- Controls -------------------------------------------------------------


## Buttons in the pixel font with a focus frame you can see from arm's
## length: the default theme's thin focus outline vanished on the Deck.
func _make_theme() -> Theme:
	var th := Theme.new()
	th.default_font = UiFont.large()
	th.default_font_size = L
	var normal := _box(Color("2b2633"), Color("4d4558"), 1)
	var focus := _box(Color("3b3446"), GOLD, 2)
	var pressed := _box(GOLD, GOLD, 1)
	var disabled := _box(Color("221f29"), Color("332e3b"), 1)
	th.set_stylebox("normal", "Button", normal)
	th.set_stylebox("hover", "Button", normal)
	th.set_stylebox("pressed", "Button", pressed)
	th.set_stylebox("disabled", "Button", disabled)
	th.set_stylebox("focus", "Button", focus)
	th.set_stylebox("hover_pressed", "Button", pressed)
	th.set_color("font_color", "Button", TEXT)
	th.set_color("font_hover_color", "Button", TEXT)
	th.set_color("font_focus_color", "Button", GOLD)
	th.set_color("font_hover_pressed_color", "Button", ROOM)
	th.set_color("font_pressed_color", "Button", ROOM)
	th.set_color("font_disabled_color", "Button", Color("5d566a"))
	return th


func _box(bg: Color, border: Color, width: int) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = bg
	b.border_color = border
	b.set_border_width_all(width)
	b.set_content_margin_all(2)
	b.anti_aliasing = false
	return b


func _build_controls() -> void:
	_buttons = HBoxContainer.new()
	_buttons.add_theme_constant_override("separation", 6)
	add_child(_buttons)
	_fold = _make_button("Fold", func() -> void: _human_act(HoldemTable.Action.FOLD))
	_call = _make_button("Call", func() -> void: _human_act(HoldemTable.Action.CALL))
	_raise = _make_button("Raise", func() -> void: _human_act(HoldemTable.Action.RAISE))
	_set_controls_visible(false)


func _make_button(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = BUTTON_SIZE
	b.focus_mode = Control.FOCUS_ALL
	b.pressed.connect(on_press)
	_buttons.add_child(b)
	return b


func _set_controls_visible(on: bool) -> void:
	_buttons.visible = on
	if on:
		_controls_shown_at = _now()


# --- Match flow -------------------------------------------------------------


func _new_match() -> void:
	var seed_value := _seed if _seed else int(Time.get_unix_time_from_system())
	match_ = TeamMatch.new(seed_value)
	for i in setup.size():
		var animal: Animal = setup[i]["animal"]
		var bot: PokerBot = null
		var bot_seed := i + 1 + (_seed * 7919 if _seed else int(Time.get_ticks_usec()))
		if animal:
			bot = animal.make_bot(bot_seed)
		elif autoplay:
			bot = PokerBot.new(PlayStyle.preset(PlayStyle.Kind.SHARK), bot_seed)
		match_.add_player(setup[i]["name"], setup[i]["team"], starting_chips, bot)
	match_.heat.dealer = Dealer.preset(dealer_kind)
	var t := match_.table
	t.hand_started.connect(_on_hand_started)
	t.action_taken.connect(_on_action)
	t.street_dealt.connect(_on_street)
	t.hand_finished.connect(_on_hand_finished)
	match_.talk.gesture_made.connect(_on_gesture)
	match_.heat.warned.connect(func(team: int, _seat: int) -> void:
		_dealer_says("Dealer to %s: \"Hands where I can see them.\"" % _crew_name(team)))
	match_.heat.fined.connect(func(team: int, _seat: int) -> void:
		_dealer_says("The floor fines %s: a dead big blind each, next hand." % _crew_name(team)))
	match_.heat.ejection_called.connect(func(_team: int, seat: int) -> void:
		_dealer_says("%s is thrown out after this hand!" % ("You are" if seat == HUMAN else t.seats[seat].name)))
	log_lines.clear()
	alert = ""
	_heat_shown.clear()
	_match_banner = ""
	_match_banner_at = INF
	_next_hand()


func _crew_name(team: int) -> String:
	return "your crew" if team == match_.table.seats[HUMAN].team else "the rival crew"


func _dealer_says(line: String) -> void:
	alert = line
	_alert_until = Time.get_ticks_msec() + 4000
	_log(line)


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _next_hand() -> void:
	var now := _now()
	_motion.clear(now)
	_hole_land.clear()
	_board_flip.clear()
	_holds.clear()
	_tells.clear()
	_told.clear()
	_still.clear()
	_gains.clear()
	_reveal_at = INF
	_result_at = INF
	_turn_seat = -1
	banner = ""
	last_action.clear()
	match_.start_hand()  # deals: _on_hand_started books the cards' flights
	_log("Hand %d, blinds %d/%d" % [match_.table.hand_number, match_.table.small_blind, match_.table.big_blind])
	_advance_flow()


## Decides what happens next after anything changes at the table: a bot
## starts thinking, your buttons come up, or the hand is over. Each waits
## for the motion already booked (the deal, the flop) to land first.
func _advance_flow() -> void:
	var t := match_.table
	var now := _now()
	if t.hand_over:
		_turn_seat = -1
		if match_.is_over() or t.seats[HUMAN].ejected:
			_flow = Flow.MATCH_DONE
			_match_banner = _match_result()
			_match_banner_at = maxf(now, _motion.cursor) + 1.4
		else:
			_flow = Flow.HAND_DONE
			_next_hand_at = maxf(now, _motion.cursor) + NEXT_HAND_PAUSE
		return
	var start := maxf(now, _motion.cursor)
	_turn_seat = t.to_act
	_turn_at = start
	if match_.waiting_on_human():
		_flow = Flow.HUMAN
		_controls_at = start
		return
	_flow = Flow.BOT_THINKING
	_choice = {}
	_decide_at = start
	_act_at = INF


func _match_result() -> String:
	var w := match_.winner()
	var text := "Your crew wins the match!" if w == 0 else ("The rival crew wins." if w == 1 else "A draw.")
	if match_.table.seats[HUMAN].ejected:
		text = "You were thrown out. Your crew forfeits."
	elif match_.caught_team() >= 0:
		text = "The floor caught their boss! " + text
	return text


func _process(delta: float) -> void:
	if match_ == null:
		return
	var now := _now()
	if alert and Time.get_ticks_msec() > _alert_until:
		alert = ""
	if bubbles:
		var now_ms := Time.get_ticks_msec()
		for seat: int in bubbles.keys():
			if bubbles[seat][1] < now_ms:
				bubbles.erase(seat)
	_update_heat_bars(delta)
	if not _help_open:
		match _flow:
			Flow.BOT_THINKING:
				_bot_turn(now)
			Flow.HUMAN:
				if not _buttons.visible and now >= _controls_at:
					_start_human_turn()
			Flow.HAND_DONE:
				if now >= _next_hand_at:
					_next_hand()
	if Engine.get_process_frames() % 30 == 0:
		_motion.prune(now)
	queue_redraw()  # the animals idle and the timeline moves: every frame


## A bot's turn in two steps: it makes up its mind when its turn starts
## (showing any signal or pre-action tell then), and acts after thinking
## for a time that fits the choice.
func _bot_turn(now: float) -> void:
	var t := match_.table
	if _choice.is_empty():
		if now < _decide_at:
			return
		var seat := t.to_act
		_choice = match_.bots[seat].decide(t, seat, match_.talk)
		_show_new_signals()
		_maybe_tell(seat, AnimalTells.Moment.THINKING, _choice["action"])
		_act_at = now + _think_time(_choice["action"], t.legal())
		return
	if now >= _act_at:
		var choice := _choice
		_choice = {}
		t.act(choice["action"], choice["amount"])
		_advance_flow()


## Folds are quick, raises take a moment, facing a big bet takes longer.
func _think_time(action: int, legal: Dictionary) -> float:
	var base := 0.4
	match action:
		HoldemTable.Action.FOLD:
			base = 0.35
		HoldemTable.Action.CALL:
			base = 0.5
		HoldemTable.Action.RAISE:
			base = 0.65
	if legal["to_call"] > match_.table.big_blind * 4:
		base += 0.25
	return base + _rng.randf() * 0.35


func _start_human_turn() -> void:
	var t := match_.table
	var legal := t.legal()
	_sizes = RaiseSizes.presets(legal, t.current_bet, t.pot())
	raise_to = _sizes[0]["to"]
	_call.text = "Check" if legal["can_check"] else "Call %d" % legal["to_call"]
	_fold.disabled = legal["can_check"]  # folding when checking is free is never right
	_raise.disabled = not legal["can_raise"]
	_update_raise_label()
	_set_controls_visible(true)
	_call.grab_focus()


func _update_raise_label() -> void:
	var legal := match_.table.legal()
	_raise.text = "All-in %d" % raise_to if raise_to >= legal["max_raise_to"] else "Raise to %d" % raise_to


func _human_act(action: int) -> void:
	if not match_.waiting_on_human() or not _buttons.visible:
		return
	_set_controls_visible(false)
	match_.table.act(action, raise_to)
	_advance_flow()


## Help, and the raise fine-tune, read before the buttons see the event:
## a focused Button would otherwise take up/down as focus moves.
func _input(event: InputEvent) -> void:
	if _is_help_toggle(event):
		_toggle_help()
		get_viewport().set_input_as_handled()
		return
	if _help_open:
		if event.is_action_pressed("ui_cancel") or event.is_action_pressed("ui_accept"):
			_toggle_help()
		if event.is_pressed():
			get_viewport().set_input_as_handled()
		return
	if _flow == Flow.HUMAN and _buttons.visible and not _raise.disabled:
		var dir := 0
		if event.is_action_pressed("ui_up", true):
			dir = 1
		elif event.is_action_pressed("ui_down", true):
			dir = -1
		if dir:
			raise_to = RaiseSizes.nudge(match_.table.legal(), raise_to, match_.table.big_blind, dir)
			_update_raise_label()
			get_viewport().set_input_as_handled()


func _is_help_toggle(event: InputEvent) -> bool:
	if event is InputEventJoypadButton:
		return event.pressed and event.button_index == JOY_BUTTON_BACK
	if event is InputEventKey and event.pressed and not event.echo:
		return event.physical_keycode in [KEY_H, KEY_F1]
	return false


func _toggle_help() -> void:
	_help_open = not _help_open
	var now := _now()
	if _help_open:
		_buttons.visible = false
		return
	# Whoever was about to act gets a moment after the card closes.
	if _act_at < INF:
		_act_at = maxf(_act_at, now + 0.3)
	_next_hand_at = maxf(_next_hand_at, now + 1.0)
	if _flow == Flow.HUMAN and now >= _controls_at:
		_start_human_turn()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		if _flow == Flow.MATCH_DONE and _now() >= _match_banner_at:
			if embedded:
				var won := match_.winner() == 0 and not match_.table.seats[HUMAN].ejected
				finished.emit(won)
				get_viewport().set_input_as_handled()
				return
			_new_match()
			get_viewport().set_input_as_handled()
			return
		if _flow == Flow.HAND_DONE:
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
	if _flow == Flow.HUMAN and _buttons.visible:
		var dir := 0
		if event.is_action_pressed("raise_more"):
			dir = 1
		elif event.is_action_pressed("raise_less"):
			dir = -1
		if dir and not _raise.disabled:
			raise_to = RaiseSizes.step(_sizes, raise_to, dir)
			_update_raise_label()


# --- What the table tells us ------------------------------------------------


## Shows signals from your side of the table as bubbles. The rival crew's
## signals stay hidden until reads exist to intercept them (the dealer's
## glance still shows that someone gestured).
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


func _on_gesture(seat: int, _sig: int) -> void:
	if not match_.heat.dealer.watching():
		return
	_glance = {"seat": seat, "t": _now()}
	_heat_flash[match_.table.seats[seat].team] = _now()


## Shows `seat`'s tell if its species has one for this moment (at most once
## a hand, about half the time: see AnimalTells). `at` delays the puff to
## when the thing it reacts to is on screen (the flop's flip).
func _maybe_tell(seat: int, moment: AnimalTells.Moment, action: int, at := -1.0) -> void:
	var animal: Animal = setup[seat]["animal"] if seat < setup.size() else null
	if animal == null or _told.has(seat):
		return
	var s := match_.table.seats[seat]
	if not AnimalTells.fires(animal.species, moment, s.hole, match_.table.board, action, _rng.randf()):
		return
	_told[seat] = true
	_tells[seat] = [AnimalTells.puff(animal.species), at if at >= 0.0 else _now()]
	if AnimalTells.TELLS[animal.species]["when"] == AnimalTells.When.MONSTER:
		_still[seat] = true
	_log(AnimalTells.log_line(animal.species, s.name))


func _on_hand_started(_button: int) -> void:
	var t := match_.table
	var now := _now()
	_snapshot_bets()
	# Two rounds, one card at a time, starting left of the button.
	var order: Array[int] = []
	for k in range(1, t.seats.size() + 1):
		var i := (t.button + k) % t.seats.size()
		if t.seats[i].dealt:
			order.append(i)
	var start := _motion.reserve(now, DEAL_STAGGER * (order.size() * 2 - 1) + DEAL_FLIGHT)
	var n := 0
	for round_ in 2:
		for seat in order:
			var depart := start + n * DEAL_STAGGER
			n += 1
			if not _hole_land.has(seat):
				_hole_land[seat] = [INF, INF]
			_hole_land[seat][round_] = depart + DEAL_FLIGHT
			# Where it flies is worked out when drawn: the first hand is
			# dealt in _ready, before the scene has its final size.
			_motion.add(&"deal", depart, DEAL_FLIGHT, {"seat": seat, "round": round_})


func _on_action(seat: int, action: int, amount: int) -> void:
	var t := match_.table
	var s := t.seats[seat]
	var now := _now()
	var text := ""
	match action:
		HoldemTable.Action.FOLD:
			text = "fold"
		HoldemTable.Action.CHECK:
			text = "check"
		HoldemTable.Action.CALL:
			text = "call %d" % amount
		HoldemTable.Action.RAISE:
			text = "raise %d" % amount
	if s.all_in:
		text = "ALL-IN"
	last_action[seat] = text
	var long_text: String = HoldemTable.ACTION_NAMES[action]
	if action == HoldemTable.Action.RAISE or (action == HoldemTable.Action.CALL and amount > 0):
		long_text += " %d" % amount
	if s.all_in:
		long_text = "goes all-in for %d" % s.street_bet
	if seat == HUMAN:  # "You fold", not "You folds"
		long_text = long_text.replace("goes", "go").replace("folds", "fold").replace("checks", "check") \
				.replace("calls", "call").replace("raises", "raise")
	_log("%s %s" % [s.name, long_text])
	var geom := _seat_geom(seat)
	var before: int = _last_bets.get(seat, 0)
	if s.street_bet > before:
		# Chips slide out to the bet spot; the number there waits for them.
		_motion.add(&"chips", now, BET_FLIGHT, {"from": geom["center"], "to": geom["bet"], "count": 2})
		_hold("bet%d" % seat, before, now + BET_FLIGHT)
	if action == HoldemTable.Action.FOLD:
		var card_size: Vector2 = geom["card_size"]
		for k in 2:
			var from: Vector2 = geom["cards"] + Vector2(k * (card_size.x + 2), 0)
			_motion.add(&"muck", now + k * 0.04, MUCK, {"from": from, "to": _layout_center(), "size": card_size})
	_snapshot_bets()
	_maybe_tell(seat, AnimalTells.Moment.ACTED, action)


func _on_street(street: int, board: Array) -> void:
	var t := match_.table
	var now := _now()
	for seat: int in last_action.keys():
		if not t.seats[seat].folded:
			last_action.erase(seat)
	_log("%s: %s" % [HoldemTable.STREET_NAMES[street], " ".join(board.map(Card.label))])
	_collect_bets(now)
	var actors := t.seats.filter(func(s: HoldemTable.Seat) -> bool: return s.can_act()).size()
	if actors < 2 and street > HoldemTable.Street.FLOP:
		_motion.reserve(now, RUNOUT_PAUSE)  # all-in: let each card land
	while _board_flip.size() < board.size():
		_board_flip.append(_motion.reserve(now, FLOP_STAGGER))
	_motion.reserve(now, FLIP)  # let the last card finish turning
	if street == HoldemTable.Street.FLOP:
		for i in t.seats.size():
			if t.seats[i].live():
				_maybe_tell(i, AnimalTells.Moment.FLOP, -1, _motion.cursor)


func _on_hand_finished(result: Dictionary) -> void:
	var t := match_.table
	var now := _now()
	_collect_bets(now)
	var total := 0
	for seat: int in result["payouts"]:
		total += result["payouts"][seat]
	if not result["uncontested"]:
		_reveal_at = _motion.reserve(now, REVEAL + 0.45)  # turn them over, then a beat to read
	_result_at = _motion.reserve(now, PAYOUT)
	_hold("pot", total, _result_at)
	var parts: Array[String] = []
	for seat: int in result["payouts"]:
		var won: int = result["payouts"][seat]
		var line := "%s wins %d" % [t.seats[seat].name, won]
		if not result["uncontested"]:
			line += " with %s" % HandReadout.describe(t.seats[seat].hole, t.board).to_lower()
		parts.append(line)
		_hold("stack%d" % seat, t.seats[seat].stack - won, _result_at + PAYOUT)
		_motion.add(&"chips", _result_at, PAYOUT, {"from": _pot_pos(), "to": _seat_geom(seat)["center"], "count": 4})
		_gains.append([seat, won, _result_at + PAYOUT])
	banner = ", ".join(parts)
	_motion.reserve(now, 0.6)  # the "+240" lands before anything moves on
	_log(banner)


## Chips bet this street slide into the pot (one beat for every seat).
func _collect_bets(now: float) -> void:
	var any := false
	for seat: int in _last_bets:
		if _last_bets[seat] > 0:
			any = true
	if not any:
		return
	var start := _motion.reserve(now, COLLECT)
	for seat: int in _last_bets:
		if _last_bets[seat] > 0:
			_motion.add(&"chips", start, COLLECT, {"from": _seat_geom(seat)["bet"], "to": _pot_pos(), "count": 2})
	_last_bets.clear()


func _snapshot_bets() -> void:
	_last_bets.clear()
	for i in match_.table.seats.size():
		_last_bets[i] = match_.table.seats[i].street_bet


## Shows `value` for `key` until `until`, then the real number again.
func _hold(key: String, value: int, until: float) -> void:
	_holds[key] = [value, until]


func _held(key: String, actual: int) -> int:
	if _holds.has(key) and _now() < _holds[key][1]:
		return _holds[key][0]
	return actual


func _log(line: String) -> void:
	log_lines.append(line)
	if log_lines.size() > 4:
		log_lines.pop_front()


func _update_heat_bars(delta: float) -> void:
	for team in 2:
		var target := match_.heat.level(team)
		var shown: float = _heat_shown.get(team, target)
		_heat_shown[team] = move_toward(shown, target, delta * 45.0)


# --- Layout -----------------------------------------------------------------


func _layout_center() -> Vector2:
	return Vector2(size.x / 2, 172)


func _shoe_pos() -> Vector2:
	return _layout_center() + Vector2(-8, -50)


func _pot_pos() -> Vector2:
	return _layout_center() + Vector2(0, 18)


func _seat_pos(i: int) -> Vector2:
	var n := maxi(match_.table.seats.size(), 2)
	var angle := deg_to_rad(90.0 + i * 360.0 / n)
	return _layout_center() + Vector2(cos(angle) * 262, sin(angle) * 132)


## Where everything at seat `i` goes: badge, portrait, cards, bet, button.
## The portrait sits on the outer side so the table side stays clear for
## cards and chips. `revealed`: hands turned over at showdown grow to board
## size, since a 16x22 card is too small to read across a 7" screen.
func _seat_geom(i: int, revealed := false) -> Dictionary:
	var p := _seat_pos(i)
	var c := _layout_center()
	var toward := (c - p).normalized()
	var badge := Rect2((p - Vector2(48, 15)).floor(), Vector2(96, 30))
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
	return {
		"center": p,
		"badge": badge,
		"portrait": portrait.floor(),
		"cards": cards.floor(),
		"card_size": card_size,
		"bet": (p.lerp(c, 0.55) + Vector2(0, 8)).floor(),
		"dealer_button": dealer_button,
	}


# --- Drawing ----------------------------------------------------------------


func _draw() -> void:
	if match_ == null:
		return
	var t := match_.table
	var c := _layout_center()
	var now := _now()
	draw_rect(Rect2(Vector2.ZERO, size), ROOM)
	_draw_ellipse(c, Vector2(236, 112), FELT_RIM)
	_draw_ellipse(c, Vector2(228, 104), FELT)

	# The shoe the cards come from.
	var shoe := _shoe_pos()
	CardArt.draw_card(self, shoe + Vector2(2, 2), 0, false, CARD_SMALL)
	CardArt.draw_card(self, shoe, 0, false, CARD_SMALL)

	# Board: empty slots until each card's flip.
	for k in 5:
		var pos := c + Vector2(-66 + k * 27, -22)
		if k < t.board.size() and k < _board_flip.size() and now >= _board_flip[k]:
			_draw_card_flipping(pos, t.board[k], CARD_BOARD, (now - _board_flip[k]) / FLIP)
		else:
			draw_rect(Rect2(pos, CARD_BOARD), FELT.darkened(0.15))

	var pot := _held("pot", t.pot())
	if pot > 0:
		_draw_chip_stack(_pot_pos() + Vector2(-34, 4), 3)
		_text(_pot_pos() + Vector2(-26, 9), "Pot %d" % pot, L, TEXT)

	for i in t.seats.size():
		_draw_seat(i, now)
	_draw_motion(now)

	if banner and now >= _result_at:
		var text := _match_banner if _match_banner and now >= _match_banner_at else banner
		_text_box(Vector2(c.x, c.y + 50), text, L, GOLD)
		if _flow == Flow.MATCH_DONE and now >= _match_banner_at:
			_text_box(Vector2(c.x, c.y + 66), "Press A to continue" if embedded else "Press A for a rematch", S, TEXT)

	for i in t.seats.size():
		_draw_seat_overlays(i, now)

	_draw_hud(now)
	if _help_open:
		_draw_help()


func _draw_motion(now: float) -> void:
	for item in _motion.active(now):
		var p := TableMotion.ease_out(item["p"])
		var kind: StringName = item["kind"]
		if kind == &"deal":
			var geom := _seat_geom(item["seat"])
			var card_size: Vector2 = geom["card_size"]
			var to: Vector2 = geom["cards"] + Vector2(item["round"] * (card_size.x + 2), 0)
			CardArt.draw_card(self, _shoe_pos().lerp(to, p), 0, false, CARD_SMALL.lerp(card_size, p).round())
			continue
		var from: Vector2 = item["from"]
		var to: Vector2 = item["to"]
		var at := from.lerp(to, p)
		if kind == &"muck":
			var card_size: Vector2 = item["size"]
			CardArt.draw_card(self, at, 0, false, card_size.lerp(CARD_SMALL, p).round())
		elif kind == &"chips":
			_draw_chip_stack(at, item["count"])


func _draw_seat(i: int, now: float) -> void:
	var t := match_.table
	var s := t.seats[i]
	var geom := _seat_geom(i)
	var badge: Rect2 = geom["badge"]
	var revealed: bool = now >= _reveal_at
	var out := s.ejected or (s.stack == 0 and s.hand_bet == 0 and t.hand_over and not _holds.has("stack%d" % i))
	var team_color := YOUR_CREW if s.team == t.seats[HUMAN].team else RIVALS
	if out:
		team_color = team_color.darkened(0.6)
	elif s.folded and not t.hand_over:
		team_color = team_color.darkened(0.45)

	# The seat to act hops once when its turn comes; yours keeps glowing.
	if i == _turn_seat and now >= _turn_at:
		var since := now - _turn_at
		if since < BOUNCE:
			badge.position.y -= roundf(sin(since / BOUNCE * PI) * 3.0)
		var glow := GOLD
		if i == HUMAN:
			glow = GOLD.lerp(TEXT, 0.5 + 0.5 * sin(now * 6.0))
		draw_rect(badge.grow(2), glow)
	var payouts: Dictionary = t.last_result.get("payouts", {})
	var winner: bool = now >= _result_at and payouts.has(i)
	if winner:
		draw_rect(badge.grow(2), GOLD if fmod(now, 0.5) < 0.35 else TEXT)
	draw_rect(badge, team_color)
	_text(badge.position + Vector2(4, 12), s.name, L, TEXT)
	var stack := _held("stack%d" % i, s.stack)
	_draw_chip_stack(badge.position + Vector2(7, 24), 1)
	_text(badge.position + Vector2(13, 27), "%d" % stack, L, TEXT)
	var status: String = "fold" if s.folded else last_action.get(i, "")
	var scores: Dictionary = t.last_result.get("scores", {})
	if revealed and s.live() and scores.has(i):
		status = HandEvaluator.describe(scores[i]).to_lower()
	if s.ejected:
		status = "thrown out"
	elif out:
		status = "busted"
	_text(Vector2(badge.end.x - 3, badge.position.y + 27), status, S, GOLD if winner else QUIET, false, true)

	var animal: Animal = setup[i]["animal"] if i < setup.size() else null
	if animal:
		var wiggle := 0.0
		if _tells.has(i):
			var since: float = now - _tells[i][1]
			wiggle = clampf(1.0 - since / 0.6, 0.0, 1.0) if since >= 0.0 else 0.0
		AnimalArt.draw(self, geom["portrait"], animal.species, now, i * 0.37, _still.has(i), wiggle, out or s.folded)

	# Hole cards, once they've landed. Yours flip face up as they land;
	# the others turn over at showdown.
	if s.dealt and not s.folded and _hole_land.has(i):
		var shown_geom := _seat_geom(i, revealed and scores.has(i))
		var card_size: Vector2 = shown_geom["card_size"]
		for k in s.hole.size():
			var land: float = _hole_land[i][k]
			if now < land:
				continue
			var pos: Vector2 = shown_geom["cards"] + Vector2(k * (card_size.x + 2), 0)
			if i == HUMAN:
				_draw_card_flipping(pos, s.hole[k], card_size, (now - land) / 0.12)
			elif revealed and scores.has(i):
				_draw_card_flipping(pos, s.hole[k], card_size, (now - _reveal_at - k * 0.05) / REVEAL)
			else:
				CardArt.draw_card(self, pos, s.hole[k], false, card_size)

	# Chips bet this street, between the seat and the pot.
	var bet := _held("bet%d" % i, s.street_bet)
	if bet > 0:
		var spot: Vector2 = geom["bet"]
		_draw_chip_stack(spot, 2)
		_text(spot + Vector2(6, 5), "%d" % bet, L, TEXT)

	if i == t.button:
		var d: Vector2 = geom["dealer_button"]
		draw_circle(d, 6, TEXT)
		draw_circle(d, 5, Color("e9e2cf"))
		_text(d + Vector2(0, 4), "D", S, ROOM, true)


## Speech bubbles, tells, the dealer's glance and winnings: drawn after
## every seat so nothing at a neighbouring seat covers them.
func _draw_seat_overlays(i: int, now: float) -> void:
	var geom := _seat_geom(i)
	var badge: Rect2 = geom["badge"]
	var p: Vector2 = geom["center"]
	if bubbles.has(i):
		var text: String = bubbles[i][0]
		var w := UiFont.small().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, S).x + 8
		var r := Rect2(Vector2(clampf(p.x - w / 2, 2, size.x - w - 2), badge.position.y - 14).floor(), Vector2(w, 11))
		draw_rect(r, TEXT)
		draw_rect(Rect2(Vector2(p.x - 1, r.end.y), Vector2(3, 2)), TEXT)
		_text(r.position + Vector2(4, 8), text, S, ROOM)
	if _tells.has(i):
		var since: float = now - _tells[i][1]
		if since >= 0.0 and since < TELL_TIME:
			var text: String = _tells[i][0]
			var portrait: Vector2 = geom["portrait"]
			var rise := floorf(minf(since / 0.4, 1.0) * 5.0)
			var alpha := clampf((TELL_TIME - since) / 0.4, 0.0, 1.0)
			var w := UiFont.small().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, S).x + 6
			var x := clampf(portrait.x + 16 - w / 2, 2, size.x - w - 2)
			var r := Rect2(Vector2(x, portrait.y - 9 - rise).floor(), Vector2(w, 10))
			draw_rect(r, Color(PANEL, 0.85 * alpha))
			draw_rect(r, Color(GOLD, alpha), false)
			_text(r.position + Vector2(3, 8), text, S, Color(GOLD, alpha))
	if not _glance.is_empty() and _glance["seat"] == i:
		var since: float = now - _glance["t"]
		if since < GLANCE_TIME and fmod(since, 0.3) < 0.22:
			_draw_eyes(Vector2(badge.end.x - 14, badge.position.y - 7), 0)
	for g in _gains:
		if g[0] != i:
			continue
		var since: float = now - g[2]
		if since >= 0.0 and since < 1.4:
			var y := badge.position.y - 4 - floorf(minf(since / 0.5, 1.0) * 8.0)
			_text(Vector2(p.x, y), "+%d" % g[1], L, Color(GOLD, clampf((1.4 - since) / 0.4, 0.0, 1.0)), true)


## Log (top left), Heat (top right), signal legend (bottom left), your
## hand and your turn (beside your cards), the dealer's words and the raise
## slider (bottom).
func _draw_hud(now: float) -> void:
	var t := match_.table
	for k in log_lines.size():
		_text(Vector2(6, 9 + k * 9), _fit(log_lines[k], 226), S, QUIET)

	var lx := 6.0
	var ly := size.y - 58
	_text(Vector2(lx, ly), "Signals (back buttons, 1-4)", S, QUIET)
	for k in 4:
		_text(Vector2(lx, ly + 9 + k * 9), "%d %s: %s" % [k + 1, TableTalk.GESTURES[k], TableTalk.MEANINGS[k]], S, TEXT if _flow == Flow.HUMAN else QUIET)
	if match_.heat.dealer.watching() and not t.hand_over:
		var cost := match_.heat.cost_of_next(HUMAN)
		var hot := match_.heat.level(t.seats[HUMAN].team) + cost >= Heat.FINE
		_text(Vector2(lx, ly + 47), "Next signal: +%d Heat" % roundi(cost), S, HOT if hot else QUIET)
	_text(Vector2(size.x - 6, size.y - 5), "Select / H: help", S, QUIET, false, true)
	_draw_heat(Vector2(size.x - 190, 10), now)

	# Your hand in words, right of your cards; your turn, left of them.
	var me := t.seats[HUMAN]
	var mine := _seat_geom(HUMAN)
	var cards_at: Vector2 = mine["cards"]
	var land: Array = _hole_land.get(HUMAN, [INF, INF])
	if me.dealt and not me.folded and now >= land[1]:
		var shown_board: Array[int] = []
		for k in t.board.size():
			if k < _board_flip.size() and now >= _board_flip[k] + FLIP:
				shown_board.append(t.board[k])
		var readout := HandReadout.describe(me.hole, shown_board)
		_text(cards_at + Vector2(CARD_YOURS.x * 2 + 8, 20), readout, L, GOLD)
	if _flow == Flow.HUMAN and _buttons.visible:
		var pulse := GOLD.lerp(TEXT, 0.5 + 0.5 * sin(now * 6.0))
		_text(cards_at + Vector2(-8, 14), "YOUR TURN", L, pulse, false, true)
		var legal := t.legal()
		var owe := "%d to call" % legal["to_call"] if legal["to_call"] > 0 else "check is free"
		_text(cards_at + Vector2(-8, 26), owe, S, TEXT, false, true)

	if alert:
		_text_box(Vector2(_layout_center().x, size.y - 47), alert, S, HOT)

	# Controls along the bottom: they rise into place when your turn comes.
	var bar_width := BUTTON_SIZE.x * 3 + 12
	var rise := 1.0 - TableMotion.ease_out((now - _controls_shown_at) / 0.15)
	_buttons.position = Vector2(floorf(_layout_center().x - bar_width / 2), size.y - 26 + floorf(rise * 10.0))
	if _buttons.visible and not _raise.disabled:
		_draw_raise_slider(Rect2(_buttons.position + _raise.position, _raise.size))


## A track over the Raise button: one notch per size the bumpers jump to,
## the knob where the raise is now, the size's name above.
func _draw_raise_slider(button: Rect2) -> void:
	if _sizes.size() < 2:
		return
	var track := Rect2(button.position + Vector2(6, -6), Vector2(button.size.x - 12, 2))
	draw_rect(track, Color("4d4558"))
	var last := _sizes.size() - 1
	var pos := 0.0
	for k in _sizes.size():
		var x := floorf(track.position.x + track.size.x * k / last)
		draw_rect(Rect2(Vector2(x, track.position.y - 1), Vector2(1, 4)), QUIET)
		var at: int = _sizes[k]["to"]
		if at <= raise_to:
			pos = k
			if k < last and raise_to > at:
				var span: float = _sizes[k + 1]["to"] - at
				pos += (raise_to - at) / span
	var knob := Vector2(floorf(track.position.x + track.size.x * pos / last), track.position.y + 1)
	draw_rect(Rect2(knob - Vector2(2, 3), Vector2(5, 6)), GOLD)
	var label := RaiseSizes.name_of(_sizes, raise_to)
	if label:
		_text(Vector2(button.get_center().x, track.position.y - 4), "%s  (LB/RB)" % label, S, TEXT, true)


## The dealer, and a Heat bar per crew with the warning and fine lines.
## The bar climbs to a new level instead of jumping, and flashes as it does.
func _draw_heat(at: Vector2, now: float) -> void:
	var heat := match_.heat
	if not heat.dealer.watching():
		_text(at + Vector2(0, 7), "No dealer: signal freely", S, QUIET)
		return
	var glancing: bool = not _glance.is_empty() and now - _glance["t"] < GLANCE_TIME
	var look := 0
	if glancing:
		look = signi(int(_seat_pos(_glance["seat"]).x - _layout_center().x))
	_draw_eyes(at + Vector2(0, 1), look, not glancing)
	_text(at + Vector2(15, 7), "Dealer: %s" % heat.dealer.display_name(), S, GOLD if glancing else QUIET)
	var mine := match_.table.seats[HUMAN].team
	for k in 2:
		var team := mine if k == 0 else 1 - mine
		var y := at.y + 11 + k * 11
		_text(Vector2(at.x, y + 7), "Your crew" if k == 0 else "Rivals", S, QUIET)
		var bar := Rect2(Vector2(at.x + 46, y), Vector2(132, 7))
		draw_rect(bar, FELT_RIM)
		var actual := heat.level(team)
		var shown: float = _heat_shown.get(team, actual)
		var color := QUIET if actual < Heat.WARNING else (GOLD if actual < Heat.FINE else HOT)
		var flash: bool = now - _heat_flash.get(team, -10.0) < 0.6 and fmod(now, 0.16) < 0.08
		draw_rect(Rect2(bar.position, Vector2(floorf(bar.size.x * minf(shown, Heat.EJECT) / Heat.EJECT), bar.size.y)), TEXT if flash else color)
		for line in [Heat.WARNING, Heat.FINE]:
			var x: float = floorf(bar.position.x + bar.size.x * line / Heat.EJECT)
			draw_rect(Rect2(Vector2(x, y - 1), Vector2(1, 9)), TEXT)


## A pair of eyes, 11x5: looking left (-1), ahead (0) or right (1), or
## half-closed when the dealer isn't looking at anyone in particular.
func _draw_eyes(at: Vector2, look: int, sleepy := false) -> void:
	at = at.floor()
	for k in 2:
		var eye := at + Vector2(k * 6, 0)
		if sleepy:
			draw_rect(Rect2(eye + Vector2(0, 2), Vector2(5, 2)), TEXT)
			draw_rect(Rect2(eye + Vector2(2, 3), Vector2(1, 1)), ROOM)
		else:
			draw_rect(Rect2(eye, Vector2(5, 5)), TEXT)
			draw_rect(Rect2(eye + Vector2(1 + look, 1), Vector2(2, 3)), ROOM)


## Controls and what everything means, on Select (or H / F1).
func _draw_help() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(ROOM, 0.8))
	var r := Rect2(Vector2(70, 30), Vector2(size.x - 140, size.y - 60))
	draw_rect(r, PANEL)
	draw_rect(r, GOLD, false)
	var x := r.position.x + 12
	var y := r.position.y + 18
	_text(Vector2(r.get_center().x, y), "How to play", L, GOLD, true)
	y += 16
	var rows := [
		["D-pad / stick", "choose Fold, Call, Raise"],
		["A", "confirm; next hand"],
		["LB / RB  (Q / E)", "raise size: min, half pot, pot, 2x, all-in"],
		["D-pad up / down", "raise one big blind more / less"],
		["Back buttons  (1-4)", "signal your teammates (below)"],
		["Select  (H)", "this card; B or A closes it"],
	]
	for row: Array in rows:
		_text(Vector2(x, y), row[0], S, TEXT)
		_text(Vector2(x + 110, y), row[1], S, QUIET)
		y += 11
	y += 6
	_text(Vector2(x, y), "Signals", L, GOLD)
	y += 13
	var buttons := ["L4", "R4", "L5", "R5"]
	for k in 4:
		_text(Vector2(x, y), "%s / %d  %s" % [buttons[k], k + 1, TableTalk.GESTURES[k]], S, TEXT)
		_text(Vector2(x + 110, y), "\"%s\"" % TableTalk.MEANINGS[k], S, QUIET)
		y += 11
	y += 6
	_text(Vector2(x, y), "Heat", L, GOLD)
	y += 13
	for line: String in [
		"The dealer notices signals: each one adds Heat, more if your crew",
		"already signalled this hand. 40: a warning. 70: a fine (a dead big",
		"blind each). 100: the signaller is thrown out; if that's you, you lose.",
		"Watch the animals too: each species has a tell.",
	]:
		_text(Vector2(x, y), line, S, QUIET)
		y += 10


## Chips as a little stack of coins, `count` high.
func _draw_chip_stack(at: Vector2, count: int) -> void:
	at = at.floor()
	for k in count:
		var y := at.y - k * 2
		draw_rect(Rect2(Vector2(at.x - 3, y - 1), Vector2(7, 3)), CHIP_EDGE)
		draw_rect(Rect2(Vector2(at.x - 2, y - 1), Vector2(5, 2)), CHIP)


## A card turning over: the back narrows to an edge, the face widens out.
## p < 0: not yet turning (back); p >= 1: face up.
func _draw_card_flipping(pos: Vector2, card: int, card_size: Vector2, p: float) -> void:
	if p >= 1.0:
		CardArt.draw_card(self, pos, card, true, card_size)
		return
	if p < 0.0:
		CardArt.draw_card(self, pos, card, false, card_size)
		return
	var squeeze := absf(1.0 - 2.0 * p)
	var w := maxf(2.0, roundf(card_size.x * squeeze / 2.0) * 2.0)
	var center := (pos + card_size / 2).floor()
	draw_set_transform(center, 0.0, Vector2(w / card_size.x, 1.0))
	CardArt.draw_card(self, -card_size / 2, card, p >= 0.5, card_size)
	draw_set_transform(Vector2.ZERO)


func _draw_ellipse(center: Vector2, radii: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for k in 48:
		var a := TAU * k / 48.0
		points.append(center + Vector2(cos(a) * radii.x, sin(a) * radii.y))
	draw_colored_polygon(points, color)


func _font(font_size: int) -> Font:
	return UiFont.large() if font_size == L else UiFont.small()


func _text(pos: Vector2, text: String, font_size: int, color: Color, centered := false, right := false) -> void:
	var font := _font(font_size)
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	if centered:
		pos.x -= floorf(w / 2)
	elif right:
		pos.x -= w
	draw_string(font, pos.floor(), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


## Centered text on a dark plate, for lines that cross the felt and cards.
func _text_box(center: Vector2, text: String, font_size: int, color: Color) -> void:
	var font := _font(font_size)
	text = _fit(text, size.x - 16, font_size)
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var h := 13.0 if font_size == L else 10.0
	var r := Rect2(Vector2(floorf(center.x - w / 2) - 4, center.y - h + 2), Vector2(w + 8, h + 1))
	draw_rect(r, Color(PANEL, 0.88))
	_text(Vector2(center.x, center.y - (1 if font_size == L else 0)), text, font_size, color, true)


## Cuts `text` to `width` pixels, with "..." if it had to.
func _fit(text: String, width: float, font_size := S) -> String:
	var font := _font(font_size)
	if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= width:
		return text
	while text.length() > 1 and font.get_string_size(text + "...", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > width:
		text = text.left(-1)
	return text + "..."


func _take_screenshots(path: String, after: float, count: int, every: float) -> void:
	await get_tree().create_timer(after).timeout
	for k in count:
		if not is_inside_tree():
			return
		await RenderingServer.frame_post_draw
		var out := path if count == 1 else "%s_%d.png" % [path.get_basename(), k]
		get_viewport().get_texture().get_image().save_png(out)
		var t := match_.table
		print("screenshot saved: %s  (hand %d, %s, board %d, busy %s)" % [out, t.hand_number,
				"over" if t.hand_over else HoldemTable.STREET_NAMES[t.street], t.board.size(), _motion.busy(_now())])
		if k < count - 1:
			await get_tree().create_timer(every).timeout
	get_tree().quit()
