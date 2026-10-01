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
## Embedding: set `setup` (who sits where), `dealer_kind`, `starting_chips`,
## `max_hands` (optional) and `embedded = true` before adding the scene to
## the tree; it emits `finished(won)` once, when the match ends and the
## player presses A, instead of offering a rematch. Embedded, it ignores the
## dev flags except --autoplay (the embedding scene sets the dealer and
## takes its own screenshots). With no `setup`, the demo crews below play.
##
## Tutorial: set `tutorial` (a TableTutorial, src/tutorial/) before adding
## the scene and it plays Rosie's five set-up lessons instead of a match.
## The hooks are the `tutorial` checks below: each hand comes from the
## lesson's stacked deck, the animals are ScriptedBots, the coach's lines
## take over the text box (CoachBox) and hold the flow the way the help card
## does (bots wait, your menu waits, the next hand waits) until A. Start
## (or Tab) offers to skip; an embedded tutorial then emits `finished` at
## once. With no tutorial set none of this runs.
##
## Dev flags (after `--`): --autoplay lets a bot play your seat,
## --dealer=STRICT (or STREET, ASLEEP, RELAXED, WATCHFUL, BOUGHT) picks the
## dealer, --screenshot=path.png saves the screen after --shot-after=seconds
## and quits; --shots=N with --shot-every=seconds saves N frames instead
## (path_0.png, path_1.png...), for checking motion; --seed=N makes the deal
## and the bots repeatable; --help-open starts with the help card shown.
## --tutorial plays the tutorial, --lesson=N starts it at lesson N (1-5),
## --coach-auto=S moves the coach on by itself after S seconds a line (for
## screenshots; --autoplay implies it).

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
const INK := PixelFrame.INK
const INK_SOFT := PixelFrame.INK_SOFT
const CREAM := PixelFrame.CREAM
const CREW_FRAME := Color("3f9a8f")
const RIVAL_FRAME := Color("d0603f")
const FOLDED_FILL := Color("c9c1b0")
const TEXT_BOX := Rect2(4, 346, 632, 50)  ## the battle-text box along the bottom
const MENU_BOX := Rect2(398, 346, 238, 50)  ## your commands, over its right end
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

signal finished(won: bool)

## Who sits where, in seat order: {"name": String, "team": int, "animal":
## Animal or null for you}. Seat 0 must be you.
var setup: Array[Dictionary] = []
var embedded := false
var starting_chips := 1000
## Caps the match at this many hands (the crew with more chips wins), for
## road games; 0 plays until a crew is out. Set before adding to the tree.
var max_hands := 0

var match_: TeamMatch
var last_action := {}  ## seat -> short text under its name
var bubbles := {}  ## seat -> [text, expires_at_msec]
var banner := ""
var raise_to := 0
var autoplay := false
var dealer_kind := Dealer.Kind.WATCHFUL  ## set before adding to the tree
var alert := ""  ## the dealer's latest words, in the text box
var _sounds: Array = []  ## [time, name, species] waiting for their beat
var _alert_until := 0

enum Flow { BOT_THINKING, HUMAN, HAND_DONE, MATCH_DONE }
var _flow := Flow.HAND_DONE
var _decide_at := 0.0  ## when the bot to act makes up its mind
var _act_at := 0.0  ## when it acts on it
var _choice := {}  ## that decision, made at _decide_at
var _controls_at := 0.0  ## when your command menu appears
var _controls_shown_at := 0.0
var _menu_open := false
var _raise_open := false  ## the raise amount picker, over the menu
var _menu := CommandMenu.new()
var _feed := TableFeed.new()
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
var _finished_sent := false  ## `finished` fires once, even on a double A
## The tutorial, when this table is one (see the top); null for a match.
var tutorial: TableTutorial = null
var _coach_auto := -1.0  ## seconds before a coach line moves on by itself; <0: waits for A
var _coach_line := {}  ## the coach line on screen, to time its typing
var _coach_since := 0.0
var _coach_held := false  ## the coach held the flow last frame
## The coach's walk sheet, held here: a texture loaded inside _draw and let
## go is freed before the frame renders, and drew as a white block.
var _coach_sprite: Texture2D


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var shot_path := ""
	var shot_after := 2.5
	var shots := 1
	var shot_every := 0.1
	for arg in OS.get_cmdline_user_args():
		if arg == "--autoplay":
			autoplay = true
		elif embedded:
			continue  # the embedding scene sets the dealer and takes its own screenshots
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
		elif arg == "--tutorial" and tutorial == null:
			tutorial = TableTutorial.new()
		elif arg.begins_with("--lesson="):
			if tutorial == null:
				tutorial = TableTutorial.new()
			tutorial.start_lesson = clampi(int(arg.get_slice("=", 1)) - 1, 0, TutorialScript.count() - 1)
		elif arg.begins_with("--coach-auto="):
			_coach_auto = float(arg.get_slice("=", 1))
	if autoplay and _coach_auto < 0.0:
		_coach_auto = 1.2
	if setup.is_empty():
		setup = TutorialScript.setup_for([]) if tutorial else demo_setup()
	if tutorial:
		_coach_sprite = Sprites.sheet(TutorialScript.COACH_SPRITE)
	_rng.seed = hash(_seed) if _seed else int(Time.get_ticks_usec())
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


func _set_controls_visible(on: bool) -> void:
	_menu_open = on
	_raise_open = false
	if on:
		_controls_shown_at = _now()


# --- Match flow -------------------------------------------------------------


func _new_match() -> void:
	var seed_value := _seed if _seed else int(Time.get_unix_time_from_system())
	match_ = TeamMatch.new(seed_value)
	if tutorial and tutorial.lesson_index >= 0:  # a rematch: the lessons from the top
		var start := tutorial.start_lesson
		tutorial = TableTutorial.new()
		tutorial.start_lesson = start
	for i in setup.size():
		var animal: Animal = setup[i]["animal"]
		var bot: PokerBot = null
		var bot_seed := i + 1 + (_seed * 7919 if _seed else int(Time.get_ticks_usec()))
		if tutorial:
			bot = tutorial.make_bot(i, autoplay)
		elif animal:
			bot = animal.make_bot(bot_seed)
		elif autoplay:
			bot = PokerBot.new(PlayStyle.preset(PlayStyle.Kind.SHARK), bot_seed)
		match_.add_player(setup[i]["name"], setup[i]["team"], starting_chips, bot)
	match_.heat.dealer = Dealer.preset(dealer_kind)
	match_.max_hands = tutorial.hands() if tutorial else max_hands
	var t := match_.table
	t.hand_started.connect(_on_hand_started)
	t.action_taken.connect(_on_action)
	t.street_dealt.connect(_on_street)
	t.hand_finished.connect(_on_hand_finished)
	match_.talk.gesture_made.connect(_on_gesture)
	match_.heat.warned.connect(func(team: int, _seat: int) -> void:
		_sound(&"dealer_warning")
		_dealer_says("Dealer to %s: \"Paws where I can see them.\"" % _crew_name(team)))
	match_.heat.fined.connect(func(team: int, _seat: int) -> void:
		_sound(&"fine")
		_dealer_says("The floor fines %s: a dead big blind each, next hand." % _crew_name(team)))
	match_.heat.ejection_called.connect(func(_team: int, seat: int) -> void:
		_sound(&"ejection")
		_dealer_says("You're thrown out after this hand!" if seat == HUMAN else "%s is thrown out after this hand!" % t.seats[seat].name))
	_feed.clear()
	alert = ""
	_heat_shown.clear()
	_match_banner = ""
	_match_banner_at = INF
	_next_hand()


## True once the match is over (or you were thrown out) and the table is
## waiting for A to continue. Public so an embedding scene can tell (the
## overworld's scripted runs press A for you then) without reading internals.
func is_waiting_to_continue() -> bool:
	return _flow == Flow.MATCH_DONE and _now() >= _match_banner_at and not _finished_sent and not _coach_holding()


func _crew_name(team: int) -> String:
	return "your crew" if team == match_.table.seats[HUMAN].team else "the rival crew"


func _dealer_says(line: String) -> void:
	alert = line
	_alert_until = Time.get_ticks_msec() + 4000
	_say(line, HOT)


## Plays sound `name` when the beat it belongs to lands (`at`, on the same
## clock as the motion timeline), so chips clink when they arrive rather
## than when the rules decided. `species` plays that animal's voice instead.
func _sound(name: StringName, at := -1.0, species: StringName = &"") -> void:
	_sounds.append([at if at >= 0.0 else _now(), name, species])


func _play_due_sounds(now: float) -> void:
	var i := 0
	while i < _sounds.size():
		if _sounds[i][0] <= now:
			if _sounds[i][2] != &"":
				Sfx.voice(_sounds[i][2])
			else:
				Sfx.play(_sounds[i][1])
			_sounds.remove_at(i)
		else:
			i += 1


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _next_hand() -> void:
	var now := _now()
	_motion.clear(now)
	_sounds.clear()
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
	if tutorial:
		match_.start_hand(tutorial.begin_hand(match_))  # the lesson's stacked deal
		_say("Lesson %d of %d: %s." % [tutorial.lesson_number(), TutorialScript.count(), tutorial.lesson()["title"]], INK_SOFT)
		_coach("hand_start", {})
	else:
		match_.start_hand()  # deals: _on_hand_started books the cards' flights
		_say("Hand %d. Blinds %d/%d." % [match_.table.hand_number, match_.table.small_blind, match_.table.big_blind], INK_SOFT)
	_advance_flow()


## Decides what happens next after anything changes at the table: a bot
## starts thinking, your buttons come up, or the hand is over. Each waits
## for the motion already booked (the deal, the flop) to land first.
func _advance_flow() -> void:
	var t := match_.table
	var now := _now()
	if t.hand_over:
		_turn_seat = -1
		_coach("hand_over", {}, maxf(now, _motion.cursor))
		if match_.is_over() or t.seats[HUMAN].ejected:
			_flow = Flow.MATCH_DONE
			_match_banner = _match_result()
			_match_banner_at = maxf(now, _motion.cursor) + 0.8
			_say("%s %s" % [_match_banner, "Press A." if embedded else "A: rematch."], RIVAL_FRAME.darkened(0.2), _match_banner_at)
			var won := match_.winner() == 0 and not t.seats[HUMAN].ejected
			_sound(&"win_pot" if won else &"lose", _match_banner_at)
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
	if tutorial:
		return tutorial.result_text()
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
	_play_due_sounds(now)
	var held := _coach_holding()
	if tutorial:
		_coach_tick(now)
		held = _coach_holding()
		if _coach_held and not held:
			_resume_after_pause(now)
		_coach_held = held
		if held:
			_hold_overlays(delta)
	if not _help_open and not held:
		match _flow:
			Flow.BOT_THINKING:
				_bot_turn(now)
			Flow.HUMAN:
				if not _menu_open and now >= _controls_at and not _coach("your_turn", {"street": match_.table.street}):
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
		if seat == HUMAN and _coach("your_turn", {"street": t.street}):
			return  # --autoplay in the tutorial: the coach still talks your seat through it
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
	_menu.enabled[CommandMenu.Item.FOLD] = not legal["can_check"]  # folding when checking is free is never right
	_menu.enabled[CommandMenu.Item.RAISE] = legal["can_raise"]
	_menu.reset()
	if tutorial:  # the cursor starts on what the coach suggests
		var hint := tutorial.suggest(HUMAN)
		_menu.cursor = maxi(0, CommandMenu.ORDER.find(hint["item"]))
		if hint["item"] == CommandMenu.Item.RAISE:
			raise_to = clampi(hint["raise_to"], legal["min_raise_to"], legal["max_raise_to"])
	_set_controls_visible(true)
	_sound(&"your_turn")


func _human_act(action: int) -> void:
	if not match_.waiting_on_human() or not _menu_open:
		return
	_set_controls_visible(false)
	match_.table.act(action, raise_to)
	_advance_flow()


## The command menu and help, driven by the ui_* actions (D-pad, stick,
## arrows; A / Enter; B / Escape).
func _input(event: InputEvent) -> void:
	if tutorial and event.is_action_pressed("menu") and not event.is_action_pressed("ui_cancel"):
		tutorial.request_skip(_now())  # Start or Tab; Escape stays "back"
		get_viewport().set_input_as_handled()
		return
	if _is_help_toggle(event):
		_toggle_help()
		get_viewport().set_input_as_handled()
		return
	if _help_open:
		if event.is_action_pressed("ui_cancel") or event.is_action_pressed("ui_accept"):
			_sound(&"ui_back")
			_toggle_help()
		if event.is_pressed():
			get_viewport().set_input_as_handled()
		return
	if _coach_showing():
		_coach_input(event)
		if event.is_pressed():
			get_viewport().set_input_as_handled()
		return
	if not (_flow == Flow.HUMAN and _menu_open):
		return
	var dir := Vector2i.ZERO
	if event.is_action_pressed("ui_left", true):
		dir = Vector2i.LEFT
	elif event.is_action_pressed("ui_right", true):
		dir = Vector2i.RIGHT
	elif event.is_action_pressed("ui_up", true):
		dir = Vector2i.UP
	elif event.is_action_pressed("ui_down", true):
		dir = Vector2i.DOWN
	var legal := match_.table.legal()
	if _raise_open:
		# Up/down: one big blind; left/right (and the bumpers): the next size.
		if dir.y:
			raise_to = RaiseSizes.nudge(legal, raise_to, match_.table.big_blind, -dir.y)
			_sound(&"ui_move")
		elif dir.x:
			raise_to = RaiseSizes.step(_sizes, raise_to, dir.x)
			_sound(&"ui_move")
		elif event.is_action_pressed("ui_accept"):
			_human_act(HoldemTable.Action.RAISE)
		elif event.is_action_pressed("ui_cancel"):
			_sound(&"ui_back")
			_raise_open = false
		else:
			return
		get_viewport().set_input_as_handled()
		return
	if dir != Vector2i.ZERO:
		_menu.move(dir)
		_sound(&"ui_move")
	elif event.is_action_pressed("ui_accept"):
		var item := _menu.choose()
		if item == CommandMenu.Item.RAISE or item == CommandMenu.Item.HELP:
			_sound(&"ui_confirm")  # the others make their own sound
		match item:
			CommandMenu.Item.CALL:
				_human_act(HoldemTable.Action.CALL)
			CommandMenu.Item.FOLD:
				_human_act(HoldemTable.Action.FOLD)
			CommandMenu.Item.RAISE:
				_raise_open = true
			CommandMenu.Item.HELP:
				_toggle_help()
	else:
		return
	get_viewport().set_input_as_handled()


func _is_help_toggle(event: InputEvent) -> bool:
	return event.is_action_pressed("help")  # Select, H or F1 (project.godot)


func _toggle_help() -> void:
	_help_open = not _help_open
	var now := _now()
	if _help_open:
		return
	_resume_after_pause(now)
	if _flow == Flow.HUMAN and now >= _controls_at and not _menu_open:
		_start_human_turn()


## While the coach talks, the tell puff and signal bubbles she's talking
## about stay up instead of fading on the clock.
func _hold_overlays(delta: float) -> void:
	for seat: int in _tells:
		_tells[seat][1] += delta
	for seat: int in bubbles:
		bubbles[seat][1] += int(delta * 1000.0)


## Whoever was about to act gets a moment after the help card or the coach
## lets go, and the next hand doesn't start the instant they do.
func _resume_after_pause(now: float) -> void:
	if _act_at < INF:
		_act_at = maxf(_act_at, now + 0.3)
	_decide_at = maxf(_decide_at, now + 0.2)
	_next_hand_at = maxf(_next_hand_at, now + 1.0)


func _unhandled_input(event: InputEvent) -> void:
	if _coach_holding():
		return  # A mustn't start the next hand over the coach's next line
	if event.is_action_pressed("ui_accept"):
		if _flow == Flow.MATCH_DONE and _now() >= _match_banner_at:
			if embedded:
				get_viewport().set_input_as_handled()
				if not _finished_sent:
					_finished_sent = true
					finished.emit(match_.winner() == 0 and not match_.table.seats[HUMAN].ejected)
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
			if tutorial and not tutorial.on_signal(i, _now()):
				continue  # it would overheat your crew: the coach says so instead
			_send_signal(i)
	if _flow == Flow.HUMAN and _menu_open and _menu.enabled[CommandMenu.Item.RAISE]:
		# The bumpers size the raise from the menu too; the Raise item shows it.
		var dir := 0
		if event.is_action_pressed("raise_more"):
			dir = 1
		elif event.is_action_pressed("raise_less"):
			dir = -1
		if dir:
			raise_to = RaiseSizes.step(_sizes, raise_to, dir)


func _send_signal(sig: int) -> void:
	match_.talk.send(HUMAN, sig as TableTalk.Sig, match_.table.street)
	_show_new_signals()


# --- The tutorial's coach ---------------------------------------------------


## Tells the tutorial what just happened (TableTutorial.event); true if the
## coach has something to say, which holds the flow until it's said.
func _coach(kind: String, info: Dictionary, at := -1.0) -> bool:
	if tutorial == null:
		return false
	tutorial.event(kind, info, at if at >= 0.0 else _now())
	return tutorial.has_lines()


func _coach_holding() -> bool:
	return tutorial != null and tutorial.has_lines()


func _coach_showing() -> bool:
	return tutorial != null and tutorial.showing(_now())


func _coach_cps() -> float:
	return Game.settings.chars_per_second() if Game.settings else 60.0


func _coach_typed(now: float) -> int:
	return int((now - _coach_since) * _coach_cps())


## Times the line on screen's typing, moves it on in --coach-auto runs, and
## ends a skipped tutorial.
func _coach_tick(now: float) -> void:
	if tutorial.skipped:
		_end_skipped_tutorial()
		return
	if not tutorial.showing(now):
		return
	if not is_same(tutorial.coach_lines[0], _coach_line):
		_coach_line = tutorial.coach_lines[0]
		_coach_since = now
	var text := tutorial.current_text()
	if _coach_auto >= 0.0 and now - _coach_since > text.length() / _coach_cps() + _coach_auto:
		_coach_press_a()


## A finishes the typing, then moves on (or, on a line asking for a signal,
## has the coach make it for you). B answers no to "skip?". The four signals
## answer a line that asks for one.
func _coach_input(event: InputEvent) -> void:
	var now := _now()
	if event.is_action_pressed("ui_accept"):
		if _coach_typed(now) < tutorial.current_text().length():
			_coach_since = now - 1000.0  # all of it, now
		else:
			_sound(&"ui_confirm")
			_coach_press_a()
	elif event.is_action_pressed("ui_cancel"):
		_sound(&"ui_back")
		tutorial.press_b()
	elif tutorial.current_wait().begins_with("signal:"):
		for i in 4:
			if event.is_action_pressed("signal_%d" % (i + 1)) and tutorial.on_signal(i, now):
				_send_signal(i)


func _coach_press_a() -> void:
	var sig := tutorial.press_a(_now())
	if sig >= 0:
		_send_signal(sig)
	if tutorial.skipped:
		_end_skipped_tutorial()


## Skipping ends the tutorial on the spot: an embedded one reports back
## (TableTutorial.skipped tells the embedding scene why); on its own the
## table says so and offers it again on A.
func _end_skipped_tutorial() -> void:
	if _flow == Flow.MATCH_DONE and _match_banner == tutorial.result_text():
		return
	if embedded:
		if not _finished_sent:
			_finished_sent = true
			finished.emit(false)
		return
	_set_controls_visible(false)
	_flow = Flow.MATCH_DONE
	_match_banner = tutorial.result_text()
	_match_banner_at = _now()
	_say("%s A: start again." % _match_banner, INK_SOFT)


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
		_say("%s: %s (\"%s\")" % [who, TableTalk.GESTURES[s["sig"]].to_lower(), TableTalk.MEANINGS[s["sig"]]], CREW_FRAME.darkened(0.3))
		_sound(&"signal")


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
	# The tutorial shows the one tell its lesson is about, every time, and no other.
	var roll := tutorial.tell_roll(seat, match_.table.street) if tutorial else _rng.randf()
	if not AnimalTells.fires(animal.species, moment, s.hole, match_.table.board, action, roll):
		return
	if tutorial:
		tutorial.note_tell(seat)
	_told[seat] = true
	_tells[seat] = [AnimalTells.puff(animal.species), at if at >= 0.0 else _now()]
	if AnimalTells.TELLS[animal.species]["when"] == AnimalTells.When.MONSTER:
		_still[seat] = true
	_say(AnimalTells.log_line(animal.species, s.name), INK_SOFT, at)


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
			_sound(&"card_deal", depart)
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
	_say(_action_line(seat, action, amount), RIVAL_FRAME.darkened(0.25) if s.team != t.seats[HUMAN].team else INK)
	if s.all_in and action != HoldemTable.Action.FOLD:
		_sound(&"all_in")
	else:
		match action:
			HoldemTable.Action.FOLD:
				_sound(&"fold")
			HoldemTable.Action.CHECK:
				_sound(&"check")
			_:
				_sound(&"chips")
	var animal: Animal = setup[seat]["animal"] if seat < setup.size() else null
	if animal and (action == HoldemTable.Action.RAISE or s.all_in):
		_sound(&"", now + 0.08, animal.species)  # bots get vocal when they bet big
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
	_coach("acted", {"seat": seat, "action": action, "street": t.street}, now + 0.4)


## "Honk raises to 60!", "You fold." For the text box.
func _action_line(seat: int, action: int, amount: int) -> String:
	var s := match_.table.seats[seat]
	var you := seat == HUMAN
	if s.all_in and action != HoldemTable.Action.FOLD:
		return "%s all-in for %d!" % ["You go" if you else s.name + " goes", s.street_bet]
	match action:
		HoldemTable.Action.FOLD:
			return "You fold." if you else "%s folds." % s.name
		HoldemTable.Action.CHECK:
			return "You check." if you else "%s checks." % s.name
		HoldemTable.Action.CALL:
			return "You call %d." % amount if you else "%s calls %d." % [s.name, amount]
	return "You raise to %d!" % amount if you else "%s raises to %d!" % [s.name, amount]


func _on_street(street: int, board: Array) -> void:
	var t := match_.table
	var now := _now()
	for seat: int in last_action.keys():
		if not t.seats[seat].folded:
			last_action.erase(seat)
	_collect_bets(now)
	var actors := t.seats.filter(func(s: HoldemTable.Seat) -> bool: return s.can_act()).size()
	if actors < 2 and street > HoldemTable.Street.FLOP:
		_motion.reserve(now, RUNOUT_PAUSE)  # all-in: let each card land
	while _board_flip.size() < board.size():
		_board_flip.append(_motion.reserve(now, FLOP_STAGGER))
		_sound(&"card_flip", _board_flip[-1])
	_motion.reserve(now, FLIP)  # let the last card finish turning
	_say("The %s." % HoldemTable.STREET_NAMES[street].to_lower(), INK_SOFT, _board_flip[-1])
	if street == HoldemTable.Street.FLOP:
		for i in t.seats.size():
			if t.seats[i].live():
				_maybe_tell(i, AnimalTells.Moment.FLOP, -1, _motion.cursor)


func _on_hand_finished(result: Dictionary) -> void:
	var t := match_.table
	var now := _now()
	_collect_bets(now)
	# An uncalled bet goes back to its owner before the pot is settled
	# ("returned"; "payouts" is then only what was won from the pot). Both
	# are still on the table until the chips slide.
	var returned: Dictionary = result.get("returned", {})
	var total := 0
	for seat: int in result["payouts"]:
		total += result["payouts"][seat]
	for seat: int in returned:
		total += returned[seat]
	if not result["uncontested"]:
		_reveal_at = _motion.reserve(now, REVEAL + 0.45)  # turn them over, then a beat to read
	_result_at = _motion.reserve(now, PAYOUT)
	_hold("pot", total, _result_at)
	if not result["uncontested"]:
		_sound(&"card_flip", _reveal_at)
	_sound(&"chips_pot", _result_at)
	var parts: Array[String] = []
	for seat: int in result["payouts"]:
		var won: int = result["payouts"][seat]
		var line := "%s wins %d" % [t.seats[seat].name, won]
		if not result["uncontested"]:
			line += " with %s" % HandReadout.describe(t.seats[seat].hole, t.board).to_lower()
		parts.append(line)
		_hold("stack%d" % seat, t.seats[seat].stack - won - int(returned.get(seat, 0)), _result_at + PAYOUT)
		_motion.add(&"chips", _result_at, PAYOUT, {"from": _pot_pos(), "to": _seat_geom(seat)["center"], "count": 4})
		_gains.append([seat, won, _result_at + PAYOUT])
		if t.seats[seat].team == t.seats[HUMAN].team:
			_sound(&"win_pot", _result_at + PAYOUT)
	for seat: int in returned:
		if not result["payouts"].has(seat):
			_hold("stack%d" % seat, t.seats[seat].stack - int(returned[seat]), _result_at + PAYOUT)
		_motion.add(&"chips", _result_at, PAYOUT, {"from": _pot_pos(), "to": _seat_geom(seat)["center"], "count": 1})
	banner = ", ".join(parts)
	_motion.reserve(now, 0.6)  # the "+240" lands before anything moves on
	_say(banner + "!", INK, _result_at)


## Chips bet this street slide into the pot (one beat for every seat).
func _collect_bets(now: float) -> void:
	var any := false
	for seat: int in _last_bets:
		if _last_bets[seat] > 0:
			any = true
	if not any:
		return
	var start := _motion.reserve(now, COLLECT)
	_sound(&"chips", start)
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


## A line for the text box, typed out at `at` (now if not given).
func _say(line: String, color := INK, at := -1.0) -> void:
	_feed.add(line, color, at if at >= 0.0 else _now())


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
	var badge := Rect2((p - Vector2(48, 16)).floor(), Vector2(96, 32))
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
	var frame := CREW_FRAME if s.team == t.seats[HUMAN].team else RIVAL_FRAME
	var fill := CREAM
	var ink := INK
	if out:
		frame = frame.lerp(INK_SOFT, 0.7)
		fill = FOLDED_FILL.darkened(0.25)
		ink = INK_SOFT
	elif s.folded:
		frame = frame.lerp(INK_SOFT, 0.5)
		fill = FOLDED_FILL
		ink = INK_SOFT

	# The seat to act hops once when its turn comes; yours keeps glowing.
	if i == _turn_seat and now >= _turn_at:
		var since := now - _turn_at
		if since < BOUNCE:
			badge.position.y -= roundf(sin(since / BOUNCE * PI) * 3.0)
		frame = GOLD if i != HUMAN else GOLD.lerp(HOT, 0.5 + 0.5 * sin(now * 6.0))
	var payouts: Dictionary = t.last_result.get("payouts", {})
	var winner: bool = now >= _result_at and payouts.has(i)
	if winner:
		frame = GOLD if fmod(now, 0.5) < 0.35 else CREAM
	PixelFrame.panel(self, badge, fill, frame)
	_text(badge.position + Vector2(5, 13), s.name, L, ink)
	var stack := _held("stack%d" % i, s.stack)
	_draw_chip_stack(badge.position + Vector2(8, 24), 1)
	_text(badge.position + Vector2(14, 27), "%d" % stack, L, ink)
	var status: String = "fold" if s.folded else last_action.get(i, "")
	var scores: Dictionary = t.last_result.get("scores", {})
	if revealed and s.live() and scores.has(i):
		status = HandEvaluator.describe(scores[i]).to_lower()
	if s.ejected:
		status = "thrown out"
	elif out:
		status = "busted"
	_text(Vector2(badge.end.x - 5, badge.position.y + 26), status, S, RIVAL_FRAME.darkened(0.2) if winner else INK_SOFT, false, true)

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
		# Over the badge, except yours: your cards sit above your badge.
		var top: float = geom["cards"].y if i == HUMAN else badge.position.y
		var r := Rect2(Vector2(clampf(p.x - w / 2, 2, size.x - w - 2), top - 14).floor(), Vector2(w, 11))
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
			draw_rect(r.grow(1), Color(INK, alpha))
			draw_rect(r, Color(GOLD, alpha))
			draw_rect(r.grow(-1), Color(CREAM, alpha))
			_text(r.position + Vector2(3, 8), text, S, Color(INK, alpha))
	if not _glance.is_empty() and _glance["seat"] == i:
		var since: float = now - _glance["t"]
		if since < GLANCE_TIME and fmod(since, 0.3) < 0.22:
			# The dealer's eyes on this seat, big enough to catch from the
			# corner of your eye: 2x, on a dark plate.
			var at := Vector2(badge.end.x - 26, badge.position.y - 12)
			if i == HUMAN:  # above your cards, beside your bubble, not over a card
				at = Vector2(p.x + 24, geom["cards"].y - 14)
			draw_rect(Rect2(at - Vector2(2, 2), Vector2(26, 14)), PANEL)
			draw_rect(Rect2(at - Vector2(2, 2), Vector2(26, 14)), HOT, false)
			_draw_eyes(at, 0, false, 2)
	for g in _gains:
		if g[0] != i:
			continue
		var since: float = now - g[2]
		if since >= 0.0 and since < 1.4:
			var y := badge.position.y - 4 - floorf(minf(since / 0.5, 1.0) * 8.0)
			_text(Vector2(p.x, y), "+%d" % g[1], L, Color(GOLD, clampf((1.4 - since) / 0.4, 0.0, 1.0)), true)


## Heat (top right), the signal legend (left), your hand in words (beside
## your cards), and along the bottom the text box with your command menu.
func _draw_hud(now: float) -> void:
	var t := match_.table
	var lx := 6.0
	var ly := 288.0
	_text(Vector2(lx, ly), "Signals: back buttons / 1-4", S, QUIET)
	for k in 4:
		_text(Vector2(lx, ly + 9 + k * 9), "%d %s: %s" % [k + 1, TableTalk.GESTURES[k], TableTalk.MEANINGS[k]], S, TEXT if _flow == Flow.HUMAN else QUIET)
	if match_.heat.dealer.watching() and not t.hand_over:
		var cost := match_.heat.cost_of_next(HUMAN)
		var hot := match_.heat.level(t.seats[HUMAN].team) + cost >= Heat.FINE
		_text(Vector2(lx, ly + 46), "Next signal: +%d Heat" % roundi(cost), S, HOT if hot else QUIET)
	_text(Vector2(size.x - 6, ly + 46), "Start: skip lesson   Select: help" if tutorial else "Select: help", S, QUIET, false, true)
	_draw_heat(Rect2(size.x - 196, 4, 192, 42), now)

	var me := t.seats[HUMAN]
	var cards_at: Vector2 = _seat_geom(HUMAN)["cards"]
	var land: Array = _hole_land.get(HUMAN, [INF, INF])
	var readout := ""
	if me.dealt and not me.folded and now >= land[1]:
		var shown_board: Array[int] = []
		for k in t.board.size():
			if k < _board_flip.size() and now >= _board_flip[k] + FLIP:
				shown_board.append(t.board[k])
		readout = HandReadout.describe(me.hole, shown_board)
		_text(cards_at + Vector2(CARD_YOURS.x * 2 + 8, 20), readout, L, GOLD)

	_draw_text_box(now, readout)
	if _menu_open:
		_draw_menu(now)


## The battle-text box: the last two things that happened, the newest
## typing out. On your turn it asks what you'll do, and the command menu
## covers its right end. A blinking arrow means A moves things on.
func _draw_text_box(now: float, readout: String) -> void:
	var r := TEXT_BOX
	r.position.y = size.y - r.size.y - 4
	var border := PixelFrame.BLUE
	if alert and fmod(now, 0.4) < 0.2 and Time.get_ticks_msec() < _alert_until - 2500:
		border = HOT  # the dealer just spoke
	if _coach_showing():
		var typed := _coach_typed(now)
		var text := tutorial.current_text()
		var hint := ""
		var wait := tutorial.current_wait()
		if wait == "signal:any":
			hint = "1-4 / back buttons: signal    A: Rosie does it"
		elif wait.begins_with("signal:"):
			var k := int(wait.get_slice(":", 1))
			hint = "%d / %s: %s    A: Rosie does it" % [k + 1, ["L4", "R4", "L5", "R5"][k], TableTalk.GESTURES[k].to_lower()]
		elif tutorial.current_wait() == "skip":
			hint = "A: skip    B: keep going"
		CoachBox.draw(self, r, TutorialScript.COACH, _coach_sprite, text, typed,
				hint, typed >= text.length() and fmod(now, 0.6) < 0.4)
		return
	PixelFrame.panel(self, r, CREAM, border, 3)
	var x := r.position.x + 12
	var width := r.size.x - 24
	if _flow == Flow.HUMAN and _menu_open:
		width = MENU_BOX.position.x - x - 8
		var legal := match_.table.legal()
		_text(Vector2(x, r.position.y + 21), "Your move.", L, INK)
		var owe := "%d to call." % legal["to_call"] if legal["to_call"] > 0 else "Checking is free."
		if _raise_open:
			owe = "Raise to how much?"
		elif readout:
			owe += " You hold %s." % (readout if readout.begins_with("Pair") or readout.contains("-") else readout.to_lower())
		_text(Vector2(x, r.position.y + 37), _fit(owe, width, L), L, INK_SOFT)
		return
	var lines := _feed.visible(now, 2)
	for k in lines.size():
		var line := lines[k]
		var newest := k == lines.size() - 1
		var text := TableFeed.typed(line, now) if newest else String(line["text"])
		var color: Color = line["color"] if newest else Color(line["color"], 0.55)
		_text(Vector2(x, r.position.y + 21 + (16 if lines.size() == 1 or newest else 0)), _fit(text, width, L), L, color)
	var waiting := (_flow == Flow.HAND_DONE and now >= _result_at) or (_flow == Flow.MATCH_DONE and now >= _match_banner_at)
	if waiting and not _feed.typing(now) and fmod(now, 0.6) < 0.4:
		PixelFrame.down_arrow(self, r.end - Vector2(17, 11), INK)


## Your commands, as a 2x2 grid with a cursor; disabled ones greyed out.
## It slides up into place when your turn comes. With Raise chosen, an
## amount picker opens above it.
func _draw_menu(now: float) -> void:
	var r := MENU_BOX
	var rise := 1.0 - TableMotion.ease_out((now - _controls_shown_at) / 0.12)
	r.position.y = size.y - r.size.y - 4 + floorf(rise * 12.0)
	PixelFrame.panel(self, r, CREAM, CREW_FRAME, 3)
	var legal := match_.table.legal()
	var labels := {
		CommandMenu.Item.CALL: "CHECK" if legal["can_check"] else "CALL %d" % legal["to_call"],
		CommandMenu.Item.RAISE: ("ALL-IN %d" if raise_to >= legal["max_raise_to"] else "RAISE %d") % raise_to,
		CommandMenu.Item.FOLD: "FOLD",
		CommandMenu.Item.HELP: "HELP",
	}
	for k in CommandMenu.ORDER.size():
		var item: CommandMenu.Item = CommandMenu.ORDER[k]
		var cell := Vector2(r.position.x + 16 + (k % 2) * 112, r.position.y + 21 + (k / 2) * 16)
		var on: bool = _menu.enabled[item]
		_text(cell, labels[item], L, INK if on else Color(INK_SOFT, 0.5))
		if k == _menu.cursor and not _raise_open:
			var nudge := 1.0 if fmod(now, 0.5) < 0.25 else 0.0  # the cursor ticks, like it's waiting
			PixelFrame.cursor(self, cell + Vector2(-4 + nudge, -4), INK)
	if _raise_open:
		_draw_raise_picker(Rect2(r.position + Vector2(r.size.x - 156, -62), Vector2(156, 60)), legal)


## The raise amount: up/down for a big blind, left/right or the bumpers
## for the next size (one notch each on the track), A to raise, B back.
func _draw_raise_picker(r: Rect2, legal: Dictionary) -> void:
	PixelFrame.panel(self, r, CREAM, GOLD, 3)
	var center := r.position.x + r.size.x / 2
	var all_in: bool = raise_to >= legal["max_raise_to"]
	_text(Vector2(center, r.position.y + 19), ("ALL-IN %d" if all_in else "RAISE TO %d") % raise_to, L, INK, true)
	PixelFrame.up_arrow(self, Vector2(r.position.x + 8, r.position.y + 10), INK_SOFT)
	PixelFrame.down_arrow(self, Vector2(r.position.x + 8, r.position.y + 16), INK_SOFT)
	var name := RaiseSizes.name_of(_sizes, raise_to)
	_text(Vector2(center, r.position.y + 31), name if name else "+/- one big blind", S, INK_SOFT, true)
	if _sizes.size() < 2:
		return
	var track := Rect2(Vector2(r.position.x + 14, r.position.y + 41), Vector2(r.size.x - 28, 2))
	draw_rect(track, FOLDED_FILL)
	var last := _sizes.size() - 1
	var pos := 0.0
	for k in _sizes.size():
		var x := floorf(track.position.x + track.size.x * k / last)
		draw_rect(Rect2(Vector2(x, track.position.y - 1), Vector2(1, 4)), INK_SOFT)
		var at: int = _sizes[k]["to"]
		if at <= raise_to:
			pos = k
			if k < last and raise_to > at:
				var span: float = _sizes[k + 1]["to"] - at
				pos += (raise_to - at) / span
	var knob := Vector2(floorf(track.position.x + track.size.x * pos / last), track.position.y + 1)
	draw_rect(Rect2(knob - Vector2(2, 3), Vector2(5, 6)), INK)
	draw_rect(Rect2(knob - Vector2(1, 2), Vector2(3, 4)), GOLD)
	_text(Vector2(center, r.end.y - 7), "LB/RB size   A raise   B back", S, INK_SOFT, true)


## The dealer, and a Heat bar per crew with the warning and fine lines, in
## a framed panel. The bar climbs to a new level instead of jumping, and
## flashes as it does; the dealer's eyes look toward whoever was noticed.
func _draw_heat(r: Rect2, now: float) -> void:
	var heat := match_.heat
	var glancing: bool = not _glance.is_empty() and now - _glance["t"] < GLANCE_TIME
	PixelFrame.panel(self, r, CREAM, HOT if glancing and fmod(now, 0.3) < 0.15 else PixelFrame.BLUE)
	var at := r.position + Vector2(7, 6)
	if not heat.dealer.watching():
		_text(at + Vector2(0, 9), "No dealer:", L, INK)
		_text(at + Vector2(0, 23), "signal freely", L, INK_SOFT)
		return
	var look := 0
	if glancing:
		look = signi(int(_seat_pos(_glance["seat"]).x - _layout_center().x))
	_draw_eyes(at + Vector2(0, 1), look, not glancing)
	_text(at + Vector2(16, 7), "Dealer: %s" % heat.dealer.display_name(), S, HOT if glancing else INK)
	var mine := match_.table.seats[HUMAN].team
	for k in 2:
		var team := mine if k == 0 else 1 - mine
		var y := at.y + 11 + k * 11
		_text(Vector2(at.x, y + 7), "Your crew" if k == 0 else "Rivals", S, INK)
		var bar := Rect2(Vector2(at.x + 46, y), Vector2(130, 7))
		draw_rect(bar.grow(1), INK)
		draw_rect(bar, FOLDED_FILL)
		var actual := heat.level(team)
		var shown: float = _heat_shown.get(team, actual)
		var color := Color("58b368") if actual < Heat.WARNING else (GOLD if actual < Heat.FINE else HOT)
		var flash: bool = now - _heat_flash.get(team, -10.0) < 0.6 and fmod(now, 0.16) < 0.08
		draw_rect(Rect2(bar.position, Vector2(floorf(bar.size.x * minf(shown, Heat.EJECT) / Heat.EJECT), bar.size.y)), CREAM if flash else color)
		for line in [Heat.WARNING, Heat.FINE]:
			var x: float = floorf(bar.position.x + bar.size.x * line / Heat.EJECT)
			draw_rect(Rect2(Vector2(x, y - 1), Vector2(1, 9)), INK)


## A pair of eyes, 11x5: looking left (-1), ahead (0) or right (1), or
## half-closed when the dealer isn't looking at anyone in particular.
func _draw_eyes(at: Vector2, look: int, sleepy := false, scale := 1) -> void:
	at = at.floor()
	var px := func(x: int, y: int, w: int, h: int, col: Color) -> void:
		draw_rect(Rect2(at + Vector2(x, y) * scale, Vector2(w, h) * scale), col)
	for k in 2:
		var x := k * 6
		if sleepy:
			px.call(x, 2, 5, 2, INK)
		else:
			px.call(x, 0, 5, 5, INK)
			px.call(x + 1, 1, 3, 3, Color.WHITE)
			px.call(x + 1 + look, 1, 2, 3, INK)


## Controls and what everything means, on Select (or H / F1). In the large
## font: it's read at arm's length, and there's room.
func _draw_help() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(ROOM, 0.7))
	var r := Rect2(Vector2(40, floorf(size.y / 2) - 143), Vector2(size.x - 80, 286))
	PixelFrame.panel(self, r, CREAM, PixelFrame.BLUE, 3)
	var x := r.position.x + 12
	var col := x + 166
	var y := r.position.y + 18
	_text(Vector2(r.get_center().x, y), "How to play", L, PixelFrame.BLUE.darkened(0.3), true)
	y += 18
	var rows := [
		["D-pad / stick", "move the cursor"],
		["A    Enter", "choose; next hand"],
		["B    Esc", "back"],
		["LB / RB   Q / E", "raise size: min, half pot, pot, 2x"],
		["Raise: up / down", "one big blind more / less"],
		["Select    H", "this card"],
	]
	for row: Array in rows:
		_text(Vector2(x, y), row[0], L, INK)
		_text(Vector2(col, y), row[1], L, INK_SOFT)
		y += 13
	y += 8
	_text(Vector2(x, y), "Signals to your teammates", L, PixelFrame.BLUE.darkened(0.3))
	y += 15
	var buttons := ["L4  1", "R4  2", "L5  3", "R5  4"]
	for k in 4:
		_text(Vector2(x, y), "%s  %s" % [buttons[k], TableTalk.GESTURES[k]], L, INK)
		_text(Vector2(col, y), "\"%s\"" % TableTalk.MEANINGS[k], L, INK_SOFT)
		y += 13
	y += 8
	_text(Vector2(x, y), "Heat", L, PixelFrame.BLUE.darkened(0.3))
	y += 15
	for line: String in [
		"Each signal adds Heat, more if your crew already",
		"signalled this hand. 40: a warning. 70: a fine.",
		"100: the signaller's thrown out. If that's you, you lose.",
		"And watch the animals: each kind has a tell.",
	]:
		_text(Vector2(x, y), line, L, INK_SOFT)
		y += 13


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
		var glancing: bool = not _glance.is_empty() and _now() - _glance["t"] < GLANCE_TIME
		print("screenshot saved: %s  (hand %d, %s, board %d, busy %s%s%s%s)" % [out, t.hand_number,
				"over" if t.hand_over else HoldemTable.STREET_NAMES[t.street], t.board.size(), _motion.busy(_now()),
				", glance" if glancing else "", ", tell" if _tells else "", ", alert" if alert else ""])
		if k < count - 1:
			await get_tree().create_timer(every).timeout
	get_tree().quit()
