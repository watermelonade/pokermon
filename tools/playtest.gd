extends SceneTree
## The automated playtester: plays the demo from the title screen the way a
## restless player would, and checks the run after every frame. Run it
## headless with a fixed frame time, in its own user dir (so it never
## touches a real save or the settings):
##
##   XDG_DATA_HOME=$(mktemp -d) godot --headless --fixed-fps 60 --path . \
##       -s tools/playtest.gd -- --pt-seed=7
##
## docs/PLAYTEST.md has the flags, the batch scripts (tools/playtest.sh) and
## what's been found. In short, it plays demo 2 from the new game: the intro
## (dialogs, A or B), then the dog alone in Sootbridge with a 48-card deck.
## It walks (goal-directed walks to the Aces lying about, to Mags who gives
## one, at the gate with and without the full deck, along the Mill Road, to
## doors, crews, townsfolk, signs and the hall, plus random wandering and
## wall bumps), talks to everyone, sits at Mossbank's open table (a bot in
## your seat for a few hands, or random presses that leave with Start or B),
## opens the start menu and its screens and backs out, saves, picks random
## menu options, recruits or declines, quits and continues through the title
## (with or without saving first), and either skips crew matches (deciding
## each one's result at random, like --match-result) or plays them for real
## (a bot in your seat, or random presses on the table's menu).
##
## What it checks, failing the run with the seed and a replay command:
## - script errors (a Logger, as tests/run_tests.gd installs);
## - softlocks: nothing on screen changes for 30 game seconds outside a
##   table, or for 90 game seconds at one;
## - the player standing in a wall, off the map, on someone, or out of step
##   with the save state; no door reachable from where you stand;
## - every save: the file must read back identical to the state just saved;
## - quit-and-continue: the run must come back exactly as it was saved;
## - money never negative; the party empty while the roster is (the dog
##   alone, before the open table), else full (2) where the roster allows,
##   pointing at real roster animals, the followers matching it; nobody in
##   the roster but Sage and Bandit (the open table's two) and animals from
##   crews you beat; nobody twice; Sage and Bandit there once you've sat;
## - the deck: 48 to 52 cards, only ever growing, only Aces missing, 52
##   exactly when all four Aces (three pickups and Mags's) are taken, a
##   taken pickup never drawn again, and never past Sootbridge's gate with
##   fewer than 52;
## - no crew ever deals in a dog with no crew;
## - after each match: a win pays the reward and marks the crew beaten, a
##   loss wakes you at the diner with half your money; after each open-table
##   session: money = before - buy-in + the stack you left with;
## - the bracelet only with the tournament beaten, and the reverse.
##
## Why a SceneTree script and not a mode in the game: it drives the real
## scenes through real input events (Input.parse_input_event and held
## actions, as a controller would), so it tests what a player can do, and
## the game needs no hooks for it. It reads a few of the scenes' private
## fields to know what's on screen (always through get(), so a rename makes
## the driver blind, not crash). Why headless with --fixed-fps: every frame
## is then exactly 1/60 s of game time however fast it runs, so the
## overworld runs at hundreds of times real speed and a run replays exactly
## from its seed. The table's clock follows the frame delta too (TableView
## _now), so real tables run as fast as the CPU allows; only a run with real
## matches against the wall-clock budget (--pt-seconds) can differ.

const TITLE_SCENE := "res://scenes/title.tscn"
const WORLD_SCENE := "res://scenes/world/overworld.tscn"
const TABLE_SCRIPT := "res://src/ui/table_view.gd"
const WALK := 0  ## Overworld.Mode
const BUSY := 1
const TABLE := 2
const FLOW_HUMAN := 1  ## TableView.Flow
const FLOW_HAND_DONE := 2
const FLOW_MATCH_DONE := 3
const DIRS: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
const DIR_ACTION := {Vector2i.UP: "move_up", Vector2i.DOWN: "move_down", Vector2i.LEFT: "move_left", Vector2i.RIGHT: "move_right"}
const SOFTLOCK_FRAMES := 1800  ## 30 game seconds with nothing changing
## At a table, in game frames (the table's clock is the frame delta): 90
## game seconds unchanged is a softlock, a match over 15 game minutes too.
const TABLE_STALL_FRAMES := 60 * 90
const TABLE_MATCH_FRAMES := 60 * 60 * 15
## Mossbank's open table (WorldMap.OPEN_TABLE): who may join from it.
const OPEN_TABLE_CREW := [["owl", 0], ["raccoon", 0]]


class Watch:
	extends Logger
	var errors: Array[String] = []
	var warnings: Array[String] = []
	var lines: Array[String] = []  ## [game] dev_log lines, read by the driver each frame
	var mutex := Mutex.new()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		var text := "%s (%s:%d in %s)" % [rationale if rationale else code, file, line, function]
		mutex.lock()
		if error_type == ERROR_TYPE_WARNING:
			warnings.append(text)
		else:
			errors.append(text)
		mutex.unlock()

	func _log_message(message: String, _error: bool) -> void:
		if message.begins_with("[game] "):
			mutex.lock()
			lines.append(message.strip_edges().substr(7))
			mutex.unlock()

	func take_lines() -> Array[String]:
		mutex.lock()
		var out := lines.duplicate()
		lines.clear()
		mutex.unlock()
		return out


var watch := Watch.new()
var rng := RandomNumberGenerator.new()
var args := {}
var seed_value := 0
var frame := 0
var started_ms := 0
var game: Node
var done := false

# Options (see docs/PLAYTEST.md).
var max_frames := 60 * 60 * 30
var max_ms := 900000
var p_real := 0.0
var p_human := 0.0
var p_win := 0.6
var p_reload := 0.004
var p_close := 0.0015  ## per frame, outside walking: close the window right now
var p_focus := 0.002  ## per frame: the window loses focus (which saves)
var lenient := {}  ## failure kinds only noted, not failed (damaged saves are allowed to be odd)
var after_complete := 300  ## decisions to keep playing after the demo-complete screen
var start := "new"  ## new, continue, old (a pre-demo save), or mix (old every 10th seed)
var damage := ""
var keep_going := false
var save_spam := 0
var p_cash_human := 0.3  ## an open-table session played by random presses rather than a bot
var cash_hands_max := 4  ## a bot in your seat gets up after 1 to this many hands

# Driver state.
var ops: Array = []  ## queued primitive inputs while walking: see _do_ops
var held := ""  ## the move action being held
var releases: Array = []  ## [frame, action] to release
var cooldown := 0
var stall := 0  ## frames the current walk op hasn't moved
var last_cell := Vector2i(-999, -999)
var history: Array[String] = []  ## what the driver did, for the failure report
var failures: Array[Dictionary] = []
var notes: Array[Dictionary] = []  ## lenient failures
var noted_cutoffs := {}
var stats := {"decisions": 0, "closes": 0, "focus_saves": 0, "continue_moved": 0, "steps": 0, "encounters": 0, "wins": 0, "losses": 0, "real_matches": 0,
	"recruits": 0, "saves": 0, "reloads": 0, "talks": 0, "menus": 0, "doors": 0, "bumps": 0,
	"maps": {}, "demo_complete": false, "reached_hall": false, "title_new_declined": 0,
	"match_ms": [], "frames_to_complete": 0,
	# Demo 2's opening and the open table.
	"old_save": false, "aces": 0, "pickups": 0, "gifts": 0, "gate_refusals": 0, "gate_walks": 0,
	"frames_to_deck": 0, "frames_to_mill_road": 0, "frames_to_town": 0, "frames_to_crew": 0,
	"cash_sessions": 0, "cash_human": 0, "cash_hands": 0, "cash_net": 0, "cash_forfeits": 0,
	"cash_offers": 0, "cash_declined": 0, "alone_in_sight": 0}
var last_saved := ""  ## the last save file's contents, normalized
var reload_expect := ""  ## after a quit: what Continue must bring back
var want_new_game := false
var title_detour := false
var sig_hash := 0
var sig_frame := 0
var table_seen: Object = null
var table_started_ms := 0
var table_started_frame := 0
var table_sig_frame := 0
var table_frames := 0  ## frames spent at real tables: not counted against --pt-frames
var table_hand := 0
var in_table := false
var last_world: Node = null
var table_mode := "auto"  ## how the next real match is played: auto or human
var expect := {}  ## a match's expected outcome, checked on the next walk
var encounter_money := 0
var encounter_crew := ""
var completed_at_decision := -1
var prev_mode := -1
var settings_before := {}
var from_old_save := false  ## the run began from a save written before demo 2 (no deck)
var deck_max := 0  ## the most cards held so far: the deck only grows
var inside_gate := {}  ## map id -> {cell: true} reachable from the start with the gates shut
var opening_ids: Array[String] = []  ## the four Aces' pickup ids (ground and gift)
var cash := {}  ## the open-table session in progress: money before, buy-in, first sit
var cash_mode := "auto"  ## how this session is played: auto (a bot) or human (random presses)
var cash_target := 0  ## human mode: leave after this many hands
var cash_stack := -1  ## your stack at the cash table, last seen
var join_expected := false  ## the first sit is over: Sage and Bandit must be in the roster
var money_seen := -1  ## money at the last checked frame (the buy-in is checked against it)
var gate_dialog_seen := false
var alone_cell := Vector2i(-999, -999)
var stranded_noted := false


func _init() -> void:
	OS.add_logger(watch)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--pt-"):
			var kv := arg.substr(5).split("=", true, 1)
			args[kv[0]] = kv[1] if kv.size() > 1 else ""
	seed_value = int(args.get("seed", str(Time.get_ticks_usec() % 1000000)))
	rng.seed = hash(seed_value)
	max_frames = int(args.get("frames", str(max_frames)))
	max_ms = int(float(args.get("seconds", "900")) * 1000)
	p_real = float(args.get("real", "0"))
	p_human = float(args.get("human", "0"))
	p_win = float(args.get("win", "0.6"))
	p_reload = float(args.get("reload", str(p_reload)))
	p_close = float(args.get("close", str(p_close)))
	p_focus = float(args.get("focus", str(p_focus)))
	for k in args.get("lenient", "").split(",", false):
		lenient[k] = true
	after_complete = int(args.get("after", str(after_complete)))
	start = args.get("start", "new")
	damage = args.get("damage", "")
	keep_going = args.has("keep-going")
	save_spam = int(args.get("save-spam", "0"))
	p_cash_human = float(args.get("cash-human", str(p_cash_human)))
	cash_hands_max = maxi(1, int(args.get("cash-hands", str(cash_hands_max))))
	if start == "mix":
		start = "old" if seed_value % 10 == 0 else "new"
	started_ms = Time.get_ticks_msec()
	node_added.connect(_on_node_added)
	process_frame.connect(_tick)


# --- Setup ----------------------------------------------------------------

func _setup() -> void:
	game = root.get_node("Game")
	game.save_path = "user://%s.json" % args.get("slot", "playtest")
	game.saved.connect(_on_saved)
	if OS.get_environment("XDG_DATA_HOME") == "" and OS.get_name() == "Linux":
		print("[pt] warning: no XDG_DATA_HOME, so the settings file is the real one (only the save slot is separate)")
	settings_before = {"text_speed": game.settings.text_speed, "volume": game.settings.volume}
	if args.has("chips"):
		game.dev_args["chips"] = args["chips"]
	match start:
		"new":
			SaveFile.erase(game.save_path)
		"continue":
			pass  # whatever the slot holds (the kill torture continues its own runs)
		"old":
			_write_damaged("pre_demo")  # a save from before demo 2: no deck fields
	if damage:
		_write_damaged(damage)
	opening_ids = _opening_ids()
	inside_gate = _inside_gate()
	if FileAccess.file_exists(game.save_path):
		# A save without a deck is from before demo 2: a run past the opening
		# whose roster (the old starters) and pickups (none) follow the old rules.
		var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(game.save_path))
		from_old_save = raw is Dictionary and raw.has("roster") and not raw.has("deck")
		stats["old_save"] = from_old_save
	if start != "new" or damage:
		_check_slot_on_disk("start")
	_log("start %s seed %d%s" % [start, seed_value, (" damage " + damage) if damage else ""])
	change_scene_to_file(TITLE_SCENE)


# --- The frame loop ---------------------------------------------------------

func _tick() -> void:
	if done:
		return
	frame += 1
	if frame == 1:
		_setup()
		return
	for r: Array in releases.duplicate():
		if r[0] <= frame:
			_send(r[1], false)
			releases.erase(r)
	for line in watch.take_lines():
		_on_game_line(line)
	if watch.errors:
		for e in watch.errors:
			_fail("script_error", e)
		watch.errors.clear()
	for w in watch.warnings:
		if "save failed" in w:
			_fail("save_failed", w)
	if save_spam > 0 and game.state != null:
		for i in save_spam:
			game.save()
	var scene := current_scene
	if scene == null:
		return
	if scene.scene_file_path == TITLE_SCENE:
		_act_title(scene)
	elif scene.scene_file_path == WORLD_SCENE and scene.get("player") != null:
		if scene != last_world:
			# The first frame of a new overworld: before any input reaches it
			# (a mashed A can start an encounter on its first free frame).
			last_world = scene
			_check_continue()
			_check_old_save_loaded()
		_check_softlock(scene)
		if not done:
			_check_world(scene)
		if not done:
			_act_world(scene)
	if frame - table_frames >= max_frames:
		_finish("frame budget")
	elif Time.get_ticks_msec() - started_ms > max_ms:
		_finish("time budget")


func _act_title(t: Node) -> void:
	_release_move()
	if cooldown > 0:
		cooldown -= 1
		return
	cooldown = rng.randi_range(3, 20)
	var options: Array = t.get("_options")
	if t.get("_confirming"):
		title_detour = false
		# "Start over?" Yes is 0, No is 1. Only a new-game start says yes.
		var want := 0 if want_new_game else 1
		_press(_toward(int(t.get("_cursor")), want) if int(t.get("_cursor")) != want else "ui_accept")
		if not want_new_game and int(t.get("_cursor")) == want:
			stats["title_new_declined"] += 1
		return
	var target := "New game" if (want_new_game or not options.has("Continue")) else "Continue"
	if title_detour and options.has("New game"):
		target = "New game"  # look at starting over, then say no
	var want_index := options.find(target)
	var cursor := int(t.get("_cursor"))
	if cursor != want_index:
		_press(_toward(cursor, want_index))
	else:
		_log("title: " + target)
		_press("ui_accept")


func _toward(cursor: int, want: int) -> String:
	return "ui_down" if want > cursor else "ui_up"


func _act_world(ow: Node) -> void:
	var mode: int = ow.get("mode")
	if mode != prev_mode:
		if mode == WALK:
			_on_walk_again(ow)
		prev_mode = mode
	# Far rarer at a table, or few matches would ever finish (a table runs
	# many more frames than the walk between two of them).
	var at_table: bool = ow.get("table") != null
	if mode != WALK and rng.randf() < p_close * (0.01 if at_table else 1.0):
		# Closing the window saves (Game._notification) and quits, mid-dialog,
		# mid-match, mid-fade: Continue must still make sense of it.
		stats["closes"] += 1
		_log("close the window (mode %d, %s)" % [mode, _screen(ow)])
		_reload(ow, true, true)
		return
	if rng.randf() < p_focus * (0.05 if at_table else 1.0):
		stats["focus_saves"] += 1
		game.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	var table: Object = ow.get("table")
	if table != null:
		_act_table(ow, table)
		return
	if in_table:  # (a freed table compares equal to null, so a flag)
		in_table = false
		if not cash:  # crew matches and lessons (an open-table session has its own stats)
			stats["match_ms"].append(Time.get_ticks_msec() - table_started_ms)
		_log("table closed after %d s (%d game s)" % [(Time.get_ticks_msec() - table_started_ms) / 1000, (frame - table_started_frame) / 60])
		table_seen = null
		table_hand = 0
	if cooldown > 0:
		cooldown -= 1
		return
	var demo: Control = ow.get("demo_complete")
	var options: Control = ow.get("options_screen")
	var party: Control = ow.get("party_screen")
	var menu: Control = ow.get("menu")
	var dialog: Control = ow.get("dialog")
	if demo.visible:
		_release_move()
		cooldown = rng.randi_range(20, 90)
		_press("ui_accept")
		_log("demo complete: A")
	elif options.visible:
		_release_move()
		_act_options(options)
	elif party.visible:
		_release_move()
		_act_party(party)
	elif menu.visible:
		_release_move()
		_act_menu(menu)
	elif dialog.visible:
		_release_move()
		cooldown = rng.randi_range(2, 25)
		_press("ui_accept" if rng.randf() < 0.85 else "ui_cancel")
	elif mode == WALK:
		if ow.get("_moving"):
			_release_move()  # one step at a time: the next is chosen when this one lands
			return
		_act_walk(ow)
	else:
		_release_move()
		var other := _other_screen(ow)
		if other or rng.randf() < 0.03:
			# A screen the driver doesn't know (a new one in the start menu),
			# or a fade or a crew walking over: mash B or A, as a player would.
			cooldown = rng.randi_range(5, 40)
			_press("ui_cancel" if other and rng.randf() < 0.7 else "ui_accept")
			if other:
				_log("unknown screen %s: pressing buttons" % other)


## A visible full-screen Control on the overworld's UI layer that isn't one
## of the screens the driver knows: its name, or "".
func _other_screen(ow: Node) -> String:
	var known := [ow.get("dialog"), ow.get("menu"), ow.get("party_screen"), ow.get("options_screen"), ow.get("demo_complete"), ow.get("fade")]
	var ui: Node = (ow.get("dialog") as Node).get_parent()
	for c: Node in ui.get_children():
		if c is Control and c.visible and not known.has(c) and c != ow.get("_hud"):
			return c.name
	return ""


## Real matches: a bot plays your seat (autoplay) or the driver presses
## random buttons. A is pressed between hands (skipping the pause) and when
## the match is over. The table's clock is the frame delta, so headless it
## runs as fast as the CPU allows (it used to be the wall clock, and this
## slept 15 ms a frame to keep from spinning).
func _act_table(_ow: Node, table: Object) -> void:
	_release_move()
	table_frames += 1
	var hand: int = table.get("match_").get("table").get("hand_number")
	if hand != table_hand:
		table_hand = hand
		_log("table: hand %d" % hand)
		if table.get("cash_game"):
			stats["cash_hands"] += 1
	if table != table_seen:
		table_seen = table
		in_table = true
		table_started_ms = Time.get_ticks_msec()
		table_started_frame = frame
		table_sig_frame = frame
		if table.get("cash_game"):
			_log("table: open table, %s, buy-in %d, %d seats" % [cash_mode, int(table.get("buy_in")), (table.get("setup") as Array).size()])
			_check_cash_seats(table)
		else:
			stats["real_matches"] += 1
			_log("table: %s, %d chips, %s" % [table_mode, int(table.get("starting_chips")), "max %d hands" % int(table.get("max_hands"))])
	if frame - table_started_frame > TABLE_MATCH_FRAMES:
		_fail("match_too_long", "a real match ran %d game s" % ((frame - table_started_frame) / 60))
		return
	if table.get("cash_game"):
		_act_cash(table)
		return
	if cooldown > 0:
		cooldown -= 1
		return
	cooldown = rng.randi_range(3, 12)
	if table.call("is_waiting_to_continue"):
		_press("ui_accept")
		return
	# Rosie's lessons (the tutorial): her text box holds the table until A,
	# and some lines wait for a signal (A has her do it). Mostly A, now and
	# then a signal, rarely Start (the skip question, answered next time).
	if table.has_method("_coach_holding") and table.call("_coach_holding"):
		var c := rng.randf()
		if c < 0.85:
			_press("ui_accept")
		elif c < 0.97:
			_press("signal_%d" % rng.randi_range(1, 4))
		else:
			_press("menu")
		return
	var flow: int = table.get("_flow")
	if flow == FLOW_HAND_DONE and rng.randf() < 0.7:
		_press("ui_accept")
	elif flow == FLOW_HUMAN and table_mode == "human":
		_random_table_press()


## Your turn, played by a restless thumb: moves, A, B, raise sizes,
## signals (a cash table ignores them), help.
func _random_table_press() -> void:
	var r := rng.randf()
	if r < 0.45:
		_press(["ui_left", "ui_right", "ui_up", "ui_down"][rng.randi_range(0, 3)])
	elif r < 0.8:
		_press("ui_accept")
	elif r < 0.86:
		_press("ui_cancel")
	elif r < 0.92:
		_press(["raise_more", "raise_less"][rng.randi_range(0, 1)])
	elif r < 0.97:
		_press("signal_%d" % rng.randi_range(1, 4))
	else:
		_press("help")


## Mossbank's open table (TableView.cash_game). With a bot in your seat
## ("auto") the table gets up by itself after cash-hands hands, or when you
## bust or clean the table out, and A takes the banner; between hands A
## skips the pause. "human": random presses on your turn, now and then
## Start mid-hand (leave once the hand is over) or Start / B between hands,
## which opens "Leave the table?"; that's answered at random (leave, Stay,
## or B) until enough hands are played, then it's leave.
func _act_cash(table: Object) -> void:
	var t: Object = table.get("match_").get("table")
	var you: Object = (t.get("seats") as Array)[0]
	if not table.get("_left_sent"):
		cash_stack = int(you.get("stack"))
	if cooldown > 0:
		cooldown -= 1
		return
	cooldown = rng.randi_range(3, 12)
	if table.call("is_waiting_to_continue"):
		_log("open table: over (%s), A" % str(table.get("_match_banner")))
		_press("ui_accept")
		return
	var flow: int = table.get("_flow")
	var played: int = int(t.get("hand_number"))
	if table.get("_leave_open"):
		var want_leave := cash_mode == "auto" or played >= cash_target or rng.randf() < 0.3
		var cursor: int = table.get("_leave_cursor")
		var r := rng.randf()
		if r < 0.1:
			_log("open table: B at the leave prompt")
			_press("ui_cancel")
		elif cursor == (0 if want_leave else 1):
			_log("open table: %s after %d hands" % ["leave" if cursor == 0 else "stay", played])
			_press("ui_accept")
		else:
			_press(["ui_up", "ui_down"][rng.randi_range(0, 1)])
		return
	if cash_mode == "auto":
		if flow == FLOW_HAND_DONE and rng.randf() < 0.7:
			_press("ui_accept")
		return
	if flow == FLOW_HAND_DONE:
		var r := rng.randf()
		if played >= cash_target and r < 0.8:
			_press("menu" if rng.randf() < 0.5 else "ui_cancel")
		elif r < 0.08:
			_press("menu" if rng.randf() < 0.5 else "ui_cancel")  # ask, maybe stay
		elif r < 0.6:
			_press("ui_accept")
	elif flow == FLOW_HUMAN:
		if played >= cash_target and rng.randf() < 0.1:
			_press("menu")  # leave once this hand is over
		else:
			_random_table_press()
	elif rng.randf() < 0.02:
		_press("menu")  # mid-hand, a bot to act: ask to leave after it


## The seats at an open table: you (the dog) at seat 0, then its players,
## none of whom has joined you.
func _check_cash_seats(table: Object) -> void:
	var setup: Array = table.get("setup")
	if setup.is_empty() or setup[0].get("animal") == null or setup[0]["animal"].species != &"dog":
		_fail("cash_seats", "seat 0 at the open table isn't the dog: %s" % [setup.slice(0, 1)])
		return
	for i in range(1, setup.size()):
		var a: Animal = setup[i]["animal"]
		if game.state.has_animal(a.species, a.name):
			_fail("cash_seats", "%s sits at the open table but is in your crew" % a.name)
		if setup[i]["team"] == setup[0]["team"]:
			_fail("cash_seats", "%s is on your team at the open table" % a.name)


func _act_options(options: Control) -> void:
	cooldown = rng.randi_range(3, 15)
	var r := rng.randf()
	if r < 0.4:
		_press(["ui_up", "ui_down"][rng.randi_range(0, 1)])
	elif r < 0.7:
		_press(["ui_left", "ui_right"][rng.randi_range(0, 1)])
	elif r < 0.85:
		_press("ui_cancel")
	else:
		_press("ui_accept")


func _act_party(party: Control) -> void:
	cooldown = rng.randi_range(3, 15)
	var r := rng.randf()
	if r < 0.4:
		_press(["ui_up", "ui_down"][rng.randi_range(0, 1)])
	elif r < 0.75:
		_press("ui_accept")
	else:
		_press("ui_cancel" if rng.randf() < 0.6 else "menu")
	_log("party: cursor %s, seated %s" % [str(party.get("_cursor")), str(game.state.party)])


## The start menu (corner) or a question (recruit, rest at the diner): walk
## the cursor to a random option and take it, or back out.
func _act_menu(menu: Control) -> void:
	cooldown = rng.randi_range(3, 18)
	var options: Array = menu.get("_options")
	var cursor: int = menu.get("_cursor")
	var target: int = menu.get_meta("pt_target", -1)
	if target < 0 or target >= options.size():
		if menu.get("_corner"):
			# Any option (Crew, Save, Options, Close...), or B / Start to close.
			var r := rng.randf()
			target = -1 if r < 0.12 else (-2 if r < 0.2 else rng.randi_range(0, options.size() - 1))
		elif str(menu.get("_title")).begins_with("Sit in?"):
			# The open table's seat: mostly yes (the crew comes from there).
			stats["cash_offers"] += 1
			var r := rng.randf()
			target = 0 if r < 0.7 else (1 if r < 0.9 else -1)
			if target != 0:
				stats["cash_declined"] += 1
		else:
			target = rng.randi_range(0, options.size() - 1) if rng.randf() < 0.85 else -1
		if target == -1:
			_press("ui_cancel")
			_log("menu %s: back out" % str(options))
			return
		if target == -2:
			_press("menu")
			_log("menu %s: Start again" % str(options))
			return
		menu.set_meta("pt_target", target)
	if cursor != target:
		# Either way round (the cursor wraps).
		_press("ui_down" if (target > cursor) == (rng.randf() < 0.8) else "ui_up")
		return
	menu.remove_meta("pt_target")
	_log("menu %s: %s" % [str(options), options[target]])
	if str(options[target]).begins_with("Save"):
		stats["saves"] += 1
	_press("ui_accept")


# --- Walking ------------------------------------------------------------------

func _act_walk(ow: Node) -> void:
	var player: Object = ow.get("player")
	var cell: Vector2i = player.get("cell")
	if ops.is_empty():
		_release_move()
		_plan(ow)
		stats["decisions"] += 1
		if completed_at_decision >= 0 and stats["decisions"] - completed_at_decision > after_complete:
			_finish("demo complete")
		return
	var op: Dictionary = ops[0]
	match op["op"]:
		"path":
			var path: Array = op["cells"]
			while path and path[0] == cell:
				path.pop_front()
				stall = 0
			if path.is_empty() or op["map"] != ow.get("map").id:
				ops.pop_front()
				_release_move()
				return
			var d: Vector2i = path[0] - cell
			if absi(d.x) + absi(d.y) != 1:
				ops.clear()  # moved by something else (a door, a blackout): plan again
				_release_move()
				return
			if cell != last_cell:
				last_cell = cell
				stall = 0
				stats["steps"] += 1
			stall += 1
			if stall > 40:
				_log("path blocked at %s toward %s" % [cell, path[0]])
				ops.clear()
				_release_move()
				return
			_hold(DIR_ACTION[d])
		"hold":
			# Held until the next op starts, so even a one-frame hold (turning
			# to face someone) reaches the overworld.
			_hold(op["action"])
			op["frames"] -= 1
			if op["frames"] <= 0:
				ops.pop_front()
		"press":
			_release_move()
			_press(op["action"])
			ops.pop_front()
			cooldown = rng.randi_range(2, 8)
		"wait":
			_release_move()
			op["frames"] -= 1
			if op["frames"] <= 0:
				ops.pop_front()
		"reload":
			ops.pop_front()
			_reload(ow, op["save"])


## Picks what to do next while walking around.
func _plan(ow: Node) -> void:
	var m: WorldMap = ow.get("map")
	var state: GameState = game.state
	if rng.randf() < p_reload:
		ops.append({"op": "reload", "save": rng.randf() < 0.6})
		return
	var r := rng.randf()
	if r < 0.05:
		_log("open the start menu")
		stats["menus"] += 1
		ops.append({"op": "press", "action": "menu"})
	elif r < 0.10:
		_log("press A at %s facing %s" % [state.cell, state.facing])
		ops.append({"op": "press", "action": "ui_accept"})
	elif r < 0.15:
		_bump(ow)
	elif r < 0.22:
		var d: Vector2i = DIRS[rng.randi_range(0, 3)]
		_log("wander %s" % d)
		ops.append({"op": "hold", "action": DIR_ACTION[d], "frames": rng.randi_range(1, 60)})
	elif r < 0.25:
		ops.append({"op": "wait", "frames": rng.randi_range(5, 60)})
	elif r < 0.42:
		_go_talk(ow)
	elif r < 0.50:
		_go_door(ow)
	elif r < 0.56:
		_go_random(ow)
	elif r < 0.66 and m.id == "town":
		_go_crew(ow)
	elif r < 0.66 and not m.pickups().is_empty():
		_go_pickup(ow, true)  # any of them, taken ones too: a taken card stays gone
	elif r < 0.70:
		_go_vacated(ow)
	elif r < 0.74 and not m.gates.is_empty():
		_go_gate(ow)
	elif r < 0.78 and m.id == "town":
		_go_open_table(ow)
	else:
		_go_progress(ow)
	if ops.is_empty():
		ops.append({"op": "wait", "frames": rng.randi_range(1, 10)})


## Toward the end of the demo: the Aces (Mags's, the ones lying about,
## the washhouse), through the gate, along the Mill Road, a seat at the
## open table (the crew comes from there), then Ridge Road and the hall.
func _go_progress(ow: Node) -> void:
	var m: WorldMap = ow.get("map")
	var state: GameState = game.state
	match m.id:
		"sootbridge", "washhouse":
			if not state.has_full_deck():
				if _go_pickup(ow, false) or _go_giver(ow):
					return
				for w: Dictionary in m.warps:  # the rest are elsewhere (the washhouse)
					if w["to"] != "mill_road" and _path_to(ow, [w["cell"]], "progress: the Aces are elsewhere, door to %s" % w["to"]):
						return
				_go_random(ow)
				return
			_go_warp_to(ow, "mill_road" if m.id == "sootbridge" else "sootbridge", "progress: out of town")
		"mill_road":
			_go_warp_to(ow, "town" if state.has_full_deck() else "sootbridge", "progress: along the Mill Road")
		"town":
			if state.party.is_empty() and _go_open_table(ow):
				return
			for w: Dictionary in m.warps:
				if w["to"] == "hall":
					_path_to(ow, [w["cell"]], "progress: the hall")
					return
		"hall":
			if not game.state.is_beaten("mossbank_regulars"):
				var crew: Dictionary = m.crews[0]
				var nodes: Array = ow.get("crew_nodes")[crew["id"]]
				if nodes[0] != null:
					_talk_to(ow, nodes[0].get("cell"), "progress: the Regulars")
					return
			_go_door(ow)
		_:
			_go_door(ow)


func _go_warp_to(ow: Node, to: String, why: String) -> bool:
	var m: WorldMap = ow.get("map")
	var cells: Array = []
	for w: Dictionary in m.warps:
		if w["to"] == to:
			cells.append(w["cell"])
	if _path_to(ow, cells, "%s (to %s)" % [why, to]):
		stats["doors"] += 1
		return true
	return false


## A card lying on this map: one still waiting (`any`: or one already
## taken, to step on its spot again: nothing must happen). Stepping on it
## takes it (the overworld's _arrived), so the walk ends there.
func _go_pickup(ow: Node, any: bool) -> bool:
	var m: WorldMap = ow.get("map")
	var state: GameState = game.state
	var cells: Array = []
	for p: Dictionary in m.pickups():
		if any or state.pickup_waiting(p["id"], p["card"]):
			cells.append(p["cell"])
	if cells.is_empty():
		return false
	var pick: Vector2i = cells[rng.randi_range(0, cells.size() - 1)]
	return _path_to(ow, [pick], "to the card at %s%s" % [pick, "" if any else " (waiting)"])


## The townsperson with an Ace for you (Mags), while it's still hers to give.
func _go_giver(ow: Node) -> bool:
	var state: GameState = game.state
	for n: Object in ow.get("npc_nodes"):
		var data: Dictionary = (ow.get("npc_data") as Dictionary).get(n, {})
		if data.has("gives_card") and state.pickup_waiting(data["gives_card"]["id"], data["gives_card"]["card"]):
			if _talk_to(ow, n.get("cell"), "to %s for the card" % data["id"]):
				stats["talks"] += 1
				return true
	return false


## Into Sootbridge's gate, whatever the deck: with Aces missing the step is
## refused with a line and you stay on the town side (checked every frame:
## gate_bypassed); with all 52 you walk through.
func _go_gate(ow: Node) -> void:
	var m: WorldMap = ow.get("map")
	var cells: Array = []
	for g: Dictionary in m.gates:
		cells.append_array(g["cells"])
	if _path_to(ow, cells, "into the gate (%d cards)" % game.state.deck.size()):
		stats["gate_walks"] += 1


## One of the open table's players, to be offered a seat.
func _go_open_table(ow: Node) -> bool:
	var data: Dictionary = ow.get("npc_data")
	var targets: Array = []
	for n: Object in ow.get("npc_nodes"):
		if (data.get(n, {}) as Dictionary).has("open_table"):
			targets.append(n.get("cell"))
	if targets.is_empty():
		return false
	var t: Vector2i = targets[rng.randi_range(0, targets.size() - 1)]
	if _talk_to(ow, t, "to the open table's player at %s" % t):
		stats["talks"] += 1
		return true
	return false


## Somewhere a townsperson or crew member stands when the map loads but
## nobody stands now (a recruit's spot, or a leader's who walked over to
## you), then quit and continue: the save puts you back on a spot the map
## thinks is taken.
func _go_vacated(ow: Node) -> void:
	var m: WorldMap = ow.get("map")
	var live := _live_bodies(ow)
	var free: Array = []
	for c: Vector2i in m.occupied_cells():
		if not live.has(c) and m.tile_walkable(c):
			free.append(c)
	if free.is_empty():
		_go_random(ow)
		return
	if _path_to(ow, free, "to a vacated spot"):
		ops.append({"op": "reload", "save": true})


func _go_door(ow: Node) -> void:
	var m: WorldMap = ow.get("map")
	var w: Dictionary = m.warps[rng.randi_range(0, m.warps.size() - 1)]
	if _path_to(ow, [w["cell"]], "door to %s" % w["to"]):
		stats["doors"] += 1


func _go_random(ow: Node) -> void:
	var m: WorldMap = ow.get("map")
	for attempt in 20:
		var c := Vector2i(rng.randi_range(0, m.width - 1), rng.randi_range(0, m.height - 1))
		if m.tile_walkable(c) and m.warp_at(c).is_empty() and _path_to(ow, [c], "walk to %s" % c):
			return


func _go_crew(ow: Node) -> void:
	var m: WorldMap = ow.get("map")
	var unbeaten: Array = []
	for c: Dictionary in m.crews:
		if not game.state.is_beaten(c["id"]) and c["sight"] > 0:
			unbeaten.append(c)
	if unbeaten.is_empty():
		_go_talk(ow)
		return
	var crew: Dictionary = unbeaten[rng.randi_range(0, unbeaten.size() - 1)]
	var sight := m.view_cells(crew["cell"], crew["facing"], crew["sight"], m.occupied_cells())
	if sight:
		_path_to(ow, sight, "into the sight of %s" % crew["id"])


## Townsfolk, crew members (beaten or not) and signs on this map.
func _go_talk(ow: Node) -> void:
	var m: WorldMap = ow.get("map")
	var targets: Array = []
	for n: Object in ow.get("npc_nodes"):
		targets.append([n.get("cell"), "npc"])
	var crew_nodes: Dictionary = ow.get("crew_nodes")
	for id: String in crew_nodes:
		for n: Object in crew_nodes[id]:
			if n != null:
				targets.append([n.get("cell"), id])
	for s: Dictionary in m.signs:
		targets.append([s["cell"], "sign"])
	if targets.is_empty():
		return
	var t: Array = targets[rng.randi_range(0, targets.size() - 1)]
	if _talk_to(ow, t[0], "talk to %s at %s" % [t[1], t[0]]):
		stats["talks"] += 1


## Walks next to `target` (or across a counter from it), faces it, presses A.
func _talk_to(ow: Node, target: Vector2i, why: String) -> bool:
	var m: WorldMap = ow.get("map")
	var stands: Array = []
	var facing := {}
	for d in DIRS:
		var c: Vector2i = target - d
		stands.append(c)
		facing[c] = d
		if m.char_at(c) == "C":  # across the counter
			stands.append(c - d)
			facing[c - d] = d
	var path := _bfs(ow, stands)
	if path.is_empty() and not stands.has(ow.get("player").get("cell")):
		return false
	var end: Vector2i = path.back() if path else ow.get("player").get("cell")
	_log(why)
	if path:
		ops.append({"op": "path", "cells": path, "map": m.id})
	ops.append({"op": "hold", "action": DIR_ACTION[facing[end]], "frames": 1})
	ops.append({"op": "press", "action": "ui_accept"})
	return true


func _bump(ow: Node) -> void:
	var m: WorldMap = ow.get("map")
	var cell: Vector2i = ow.get("player").get("cell")
	var walls: Array = []
	for d in DIRS:
		if not m.tile_walkable(cell + d):
			walls.append(d)
	if walls.is_empty():
		_go_random(ow)
		return
	var d: Vector2i = walls[rng.randi_range(0, walls.size() - 1)]
	stats["bumps"] += 1
	_log("bump %s into %s" % [d, m.char_at(cell + d)])
	ops.append({"op": "hold", "action": DIR_ACTION[d], "frames": rng.randi_range(2, 30)})


func _path_to(ow: Node, goals: Array, why: String) -> bool:
	var path := _bfs(ow, goals)
	if path.is_empty():
		return false
	_log("%s (%d steps)" % [why, path.size()])
	ops.append({"op": "path", "cells": path, "map": ow.get("map").id})
	return true


## Shortest walk from the player to any of `goals`, around walls and anyone
## standing, and never through a door that isn't a goal.
func _bfs(ow: Node, goals: Array) -> Array:
	var m: WorldMap = ow.get("map")
	var from: Vector2i = ow.get("player").get("cell")
	var blocked := _live_bodies(ow)
	var goal := {}
	for g: Vector2i in goals:
		if m.tile_walkable(g) and not blocked.has(g):
			goal[g] = true
	if goal.is_empty():
		return []
	var came := {from: from}
	var queue: Array[Vector2i] = [from]
	var head := 0
	while head < queue.size():
		var c: Vector2i = queue[head]
		head += 1
		if goal.has(c) and c != from:
			var path: Array = []
			while c != from:
				path.push_front(c)
				c = came[c]
			return path
		for d in DIRS:
			var n: Vector2i = c + d
			if came.has(n) or blocked.has(n) or not m.tile_walkable(n):
				continue
			if not m.warp_at(n).is_empty() and not goal.has(n):
				continue
			came[n] = c
			queue.append(n)
	return []


func _live_bodies(ow: Node) -> Dictionary:
	var out := {}
	for n: Object in ow.get("npc_nodes"):
		out[n.get("cell")] = true
	var crew_nodes: Dictionary = ow.get("crew_nodes")
	for id: String in crew_nodes:
		for n: Object in crew_nodes[id]:
			if n != null:
				out[n.get("cell")] = true
	return out


## Quit and continue, as closing the window and choosing Continue would:
## the window's close saves first (`save`), a crash or a kill doesn't.
func _reload(ow: Node, save: bool, closing := false) -> void:
	if save:
		if closing:
			game.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
		else:
			game.save()
	if last_saved == "":
		return
	reload_expect = last_saved
	stats["reloads"] += 1
	if expect:
		# Quit between a match's end and its outcome being saved.
		var where: String = game.state.map_id if game.state else "?"
		if not expect["won"] and where != game.state.heal_map:
			_note("blackout_skipped", "closed during the blackout dialog after losing to %s: Continue loads the save from before the match (no money lost, back on the road)" % expect["crew"])
		elif expect["won"] and expect["tournament"] and not game.state.bracelets.has("mossbank"):
			_note("bracelet_pending", "closed after beating the Regulars, before the bracelet was given")
		elif expect["won"]:
			_note("recruit_skipped", "closed during the win dialogs against %s: Continue has them beaten, the recruit offer is gone" % expect["crew"])
		expect = {}
	if cash:
		# Quit while seated: the buy-in was saved when you sat down, the stack
		# in front of you is forfeit (OpenTable's docstring), and the first sit
		# didn't happen as far as the crew goes.
		stats["cash_forfeits"] += 1
		_note("cash_forfeited", "quit at the open table: the $%d buy-in is gone, Continue has you standing by the table" % int(cash["buy_in"]))
		cash = {}
	title_detour = rng.randf() < 0.3
	_log("quit%s and continue (expect %s)" % [" after saving" if save else " without saving", _brief(reload_expect)])
	ops.clear()
	prev_mode = -1
	game.state = null
	change_scene_to_file(TITLE_SCENE)


# --- What the game says -------------------------------------------------------

func _on_game_line(line: String) -> void:
	var state: GameState = game.state
	if line.begins_with("encounter: "):
		encounter_crew = line.substr(11).get_slice(" ", 0)
		encounter_money = state.money
		stats["encounters"] += 1
		_log(line)
		if state.party.is_empty():
			_fail("spotted_alone", "a crew dealt in a dog with no crew: %s" % line)
	elif line.begins_with("picked up ") or line.begins_with("given "):
		# A card taken: the deck grew by exactly one (the frame checks hold
		# the rest: 52 iff all four taken, never drawn again).
		stats["pickups" if line.begins_with("picked") else "gifts"] += 1
		_log(line)
		if state.deck.size() != deck_max + 1:
			_fail("deck_pickup", "%s: the deck went from %d to %d cards" % [line, deck_max, state.deck.size()])
		deck_max = maxi(deck_max, state.deck.size())
		if state.has_full_deck() and not stats["frames_to_deck"]:
			stats["frames_to_deck"] = frame
	elif line.begins_with("open table: sat down for $"):
		var buy_in := int(line.get_slice("$", 1))
		cash = {"before": money_seen, "buy_in": buy_in, "first": not state.met_open_table}
		stats["cash_sessions"] += 1
		_log(line)
		if state.money != money_seen - buy_in:
			_fail("cash_buy_in", "sat down for $%d with $%d: money is now $%d" % [buy_in, money_seen, state.money])
	elif line.begins_with("open table: left with "):
		var chips := int(line.substr(22).get_slice(" ", 0))
		_log(line)
		if cash.is_empty():
			_fail("cash_money", "left the open table without having sat down: " + line)
			return
		var want: int = cash["before"] - cash["buy_in"] + chips
		if state.money != want:
			_fail("cash_money", "open table: $%d before, $%d buy-in, left with %d: money is $%d, not $%d"
				% [cash["before"], cash["buy_in"], chips, state.money, want])
		if cash_stack >= 0 and chips != cash_stack:
			_fail("cash_money", "open table: left with %d but the stack in front of you was %d" % [chips, cash_stack])
		stats["cash_net"] += chips - int(cash["buy_in"])
		if cash["first"]:
			join_expected = true
		cash = {}
	elif line.begins_with("match against "):
		var crew_id := line.substr(14).get_slice(":", 0)
		var won := line.ends_with("won")
		stats["wins" if won else "losses"] += 1
		var crew := _crew(crew_id)
		expect = {"crew": crew_id, "won": won, "money": encounter_money, "reward": int(crew.get("reward", 0)),
			"tournament": crew.has("bracelet")}
		_log(line)


## A table is being added (before its _ready): who plays your seat, and a
## seed for its deal and bots from the run's own, so a run with tables
## replays from its seed too (TableView reads Game.dev_args "seed").
func _on_node_added(node: Node) -> void:
	var s: Script = node.get_script()
	if s == null or s.resource_path != TABLE_SCRIPT:
		return
	game.dev_args["seed"] = str(rng.randi_range(1, 1 << 30))
	if node.get("cash_game"):
		# The open table: a bot for a few hands, or random presses.
		cash_mode = "human" if rng.randf() < p_cash_human else "auto"
		cash_target = rng.randi_range(1, cash_hands_max)
		game.dev_args["cash-hands"] = str(cash_target)
		cash_stack = -1
		if cash_mode == "auto":
			node.set("autoplay", true)
		else:
			stats["cash_human"] += 1
	elif table_mode == "auto":
		node.set("autoplay", true)


## Each time you're free to walk again: check what the last match should
## have done, check a continue brought the run back as saved, and decide
## how the next match (if one starts from here) is played.
func _on_walk_again(ow: Node) -> void:
	var state: GameState = game.state
	if expect:
		_check_match_outcome(state)
		expect = {}
	if join_expected:
		# After the first sit, win or lose: Sage and Bandit are in the crew.
		join_expected = false
		for e: Array in OPEN_TABLE_CREW:
			var a := Species.individual(StringName(e[0]), e[1])
			if not state.has_animal(a.species, a.name):
				_fail("crew_join", "the first sit at the open table is over and %s isn't in the roster %s" % [a.name, _roster_names(state)])
	if state.bracelets.has("mossbank") and completed_at_decision < 0:
		completed_at_decision = stats["decisions"]
		stats["demo_complete"] = true
		stats["frames_to_complete"] = frame
		_log("DEMO COMPLETE at frame %d" % frame)
	# The next match: skipped with a random result, or played.
	if rng.randf() < p_real:
		game.dev_args.erase("match-result")
		table_mode = "human" if rng.randf() < p_human else "auto"
	else:
		game.dev_args["match-result"] = "win" if rng.randf() < p_win else "lose"
		table_mode = "auto"
	ops.clear()  # anything planned before a match or a door is stale


## A save on a spot someone stands on when the map loads (a crew's home
## after it walked over to you) continues on the nearest open cell
## (WorldMap.open_cell_near): allowed. Returns the saved cell's JSON when
## that's what happened, so the comparison can ignore it.
func _moved_off_taken_cell(saved_norm: String, state: GameState) -> String:
	var saved: Dictionary = JSON.parse_string(saved_norm)
	var c: Array = saved.get("cell", [])
	if c.size() != 2 or str(saved.get("map")) != state.map_id:
		return ""
	var cell := Vector2i(int(c[0]), int(c[1]))
	if cell == state.cell:
		return ""
	var m := WorldMap.get_map(state.map_id)
	var taken := m.standing_cells(state)
	if taken.has(cell) and m.open_cell_near(cell, taken) == state.cell:
		return _cell_json(cell)
	return ""


func _cell_json(cell: Vector2i) -> String:
	return '"cell":' + JSON.stringify([cell.x, cell.y])


func _allowed_open_table(a: Animal) -> bool:
	for e: Array in OPEN_TABLE_CREW:
		if a.species == StringName(e[0]) and a.name == Species.individual(StringName(e[0]), e[1]).name:
			return true
	return false


## The state just saved has sat at the open table with nobody in the roster,
## and the file loads with Sage and Bandit seated, all else the same.
func _crew_join_pending(want: String, got: String) -> bool:
	var a: Dictionary = JSON.parse_string(want)
	var b: Dictionary = JSON.parse_string(got)
	if not a.get("met_open_table", false) or not (a.get("roster", []) as Array).is_empty():
		return false
	for k in ["roster", "party", "seen", "recruited"]:
		a.erase(k)
		b.erase(k)
	return JSON.stringify(a, "", true) == JSON.stringify(b, "", true)


func _only_bracelets_added(want: String, got: String) -> bool:
	var a: Dictionary = JSON.parse_string(want)
	var b: Dictionary = JSON.parse_string(got)
	if (b.get("bracelets", []) as Array).size() <= (a.get("bracelets", []) as Array).size():
		return false
	a.erase("bracelets")
	b.erase("bracelets")
	return JSON.stringify(a, "", true) == JSON.stringify(b, "", true)


## After a quit: Continue must bring back exactly what loading the last
## save gives (moving you off a cell someone now stands on is allowed).
func _check_continue() -> void:
	var state: GameState = game.state
	if reload_expect != "":
		var got := _norm(state.to_dict())
		var want := reload_expect
		var moved := _moved_off_taken_cell(want, state)
		if moved:
			stats["continue_moved"] += 1
			_log("continue moved you from a taken cell to %s" % state.cell)
			got = got.replace(_cell_json(state.cell), moved)
		var saved: Dictionary = JSON.parse_string(want)
		if (saved.get("party", []) as Array).size() < GameState.PARTY_SIZE:
			# Saved with the party screen half-way: the load fills the seats.
			var a := saved.duplicate()
			var b: Dictionary = JSON.parse_string(got)
			a.erase("party")
			b.erase("party")
			if JSON.stringify(a, "", true) == JSON.stringify(b, "", true):
				got = want
		if got != want:
			_fail("continue_mismatch", "after quit and continue the run isn't as saved:\n  saved:  %s\n  loaded: %s\n  diff: %s"
				% [_brief(want), _brief(got), _diff(want, got)])
		reload_expect = ""


## A run from a pre-demo save (--pt-start=old): the first world it loads is
## past the opening: all 52 cards, opening_done, the roster and party, map
## and cell as the old save had them (GameState.from_dict, S-OLD).
func _check_old_save_loaded() -> void:
	if start != "old" or stats.has("old_save_checked"):
		return
	stats["old_save_checked"] = true
	var state: GameState = game.state
	var problems: Array[String] = []
	if not state.has_full_deck():
		problems.append("%d cards" % state.deck.size())
	if not state.opening_done:
		problems.append("opening not done")
	if _roster_names(state) != str(["Sage", "Bandit", Species.individual(&"goose", 0).name]):
		problems.append("roster %s" % _roster_names(state))
	if str(state.party) != str([0, 1]):
		problems.append("party %s" % [state.party])
	if state.map_id != "town" or state.cell != Vector2i(40, 12):
		problems.append("at %s %s" % [state.map_id, state.cell])
	if problems:
		_fail("old_save_load", "a pre-demo save loaded wrong: " + ", ".join(problems))
	else:
		_log("the pre-demo save loaded past the opening")


func _check_match_outcome(state: GameState) -> void:
	var e := expect
	if e["won"]:
		if not state.is_beaten(e["crew"]):
			_fail("match_outcome", "won against %s but it isn't marked beaten" % e["crew"])
		if state.money != e["money"] + e["reward"]:
			_fail("match_outcome", "won against %s: money %d, expected %d + %d" % [e["crew"], state.money, e["money"], e["reward"]])
		if e["tournament"] and not state.bracelets.has("mossbank"):
			_fail("match_outcome", "won the tournament but no bracelet")
	else:
		var want: int = e["money"] - e["money"] / 2
		if state.money != want:
			_fail("match_outcome", "lost to %s: money %d, expected %d" % [e["crew"], state.money, want])
		if state.map_id != state.heal_map or state.cell != state.heal_cell:
			_fail("match_outcome", "lost to %s but woke at %s %s, not %s %s" % [e["crew"], state.map_id, state.cell, state.heal_map, state.heal_cell])
		if state.is_beaten(e["crew"]):
			_fail("match_outcome", "lost to %s but it's marked beaten" % e["crew"])


func _on_saved() -> void:
	stats["saves_written"] = stats.get("saves_written", 0) + 1
	var recruits := 0
	for a in game.state.roster:
		if not _allowed_open_table(a):
			recruits += 1
	stats["recruits"] = maxi(stats["recruits"], recruits)
	var want := _norm(game.state.to_dict())
	var path: String = game.save_path
	var loaded := SaveFile.read(path)
	if loaded == null:
		_fail("save_unreadable", "the save just written doesn't read back: %s" % FileAccess.get_file_as_string(path).left(300))
		return
	var got := _norm(loaded.to_dict())
	if game.state.party.size() < GameState.PARTY_SIZE and game.get_tree().current_scene.get("party_screen") \
			and game.get_tree().current_scene.get("party_screen").visible:
		# Saved (the window closed, focus lost) mid-way through re-seating
		# the party: the load fills the empty seats, as it should.
		_note("short_party_saved", "saved with %d seated while the party screen was open; the load seats %s" % [game.state.party.size(), loaded.party])
		var a: Dictionary = JSON.parse_string(want)
		var b: Dictionary = JSON.parse_string(got)
		a.erase("party")
		b.erase("party")
		if JSON.stringify(a, "", true) == JSON.stringify(b, "", true):
			got = want
	if got != want and _crew_join_pending(want, got):
		# Saved between getting up from the first sit (met_open_table, the
		# cash-out) and Sage and Bandit joining (the next save, after their
		# lines): the load seats them (GameState.from_dict), without the
		# Binder's "where you met it".
		_note("crew_join_pending", "saved after the first sit, before Sage and Bandit joined; the load adds them")
		got = want
	if got != want and _only_bracelets_added(want, got):
		# Saved between beating the Regulars and the bracelet (the window
		# closed during the win dialog): the load gives the bracelet.
		_note("bracelet_pending", "saved after beating the Regulars, before the bracelet; the load adds it")
		got = want
	if got != want:
		_fail("save_roundtrip", "the save reads back different:\n  state: %s\n  file:  %s\n  diff: %s" % [_brief(want), _brief(got), _diff(want, got)])
	if FileAccess.file_exists(path + ".part"):
		_fail("save_leftover", "a .part file is left after a save")
	last_saved = _norm(loaded.to_dict())  # what Continue will bring back
	if start == "continue":
		# For the kill torture: what this run has saved, so the next run can
		# check none of it was lost (written after the save, so it can only
		# lag behind it, never claim more).
		var floor := FileAccess.open(path + ".floor", FileAccess.WRITE)
		if floor:
			floor.store_string(JSON.stringify({"beaten": game.state.beaten.keys(), "roster": game.state.roster.size(),
				"deck": game.state.deck.size(), "taken": game.state.taken_pickups.keys()}))
			floor.close()


# --- Checks -------------------------------------------------------------------

func _check_world(ow: Node) -> void:
	var state: GameState = game.state
	if state == null:
		return
	if ow.get("state") != state:
		_fail("state_split", "the overworld and Game hold different GameStates")
	var mode: int = ow.get("mode")
	# Mid-sequence (a win's dialogs, the party screen open) some rules are
	# briefly untrue on purpose: the strict ones wait for walking.
	_check_state(state, mode != WALK or ow.get("party_screen").visible)
	var m: WorldMap = ow.get("map")
	stats["maps"][m.id] = true
	if m.id == "hall":
		stats["reached_hall"] = true
	money_seen = state.money
	_check_deck_grows(state)
	_check_milestones(state, m)
	_check_gate_dialog(ow, state, m)
	if mode != WALK or ow.get("_moving"):
		return
	var player: Object = ow.get("player")
	var cell: Vector2i = player.get("cell")
	_check_opening(ow, state, m, cell)
	if cell != state.cell or m.id != state.map_id:
		_fail("position_desync", "player at %s %s, state says %s %s" % [m.id, cell, state.map_id, state.cell])
	if not m.in_bounds(cell):
		_fail("out_of_bounds", "player at %s on %s (%dx%d)" % [cell, m.id, m.width, m.height])
	elif not m.tile_walkable(cell):
		_fail("in_wall", "player at %s on %s, a '%s' tile" % [cell, m.id, m.char_at(cell)])
	if _live_bodies(ow).has(cell):
		_fail("on_someone", "player at %s on %s shares the cell with someone" % [cell, m.id])
	var followers: Array = ow.get("followers")
	var party := state.party_animals()
	if followers.size() != party.size():
		_fail("followers", "%d followers for a party of %d" % [followers.size(), party.size()])
	else:
		for i in party.size():
			if followers[i].get("sprite_id") != String(party[i].species):
				_fail("followers", "follower %d is a %s, seat %d is a %s" % [i, followers[i].get("sprite_id"), i + 1, party[i].species])
	if frame % 30 == 0 and _bfs(ow, _warp_cells(m)).is_empty() and m.warp_at(cell).is_empty():
		_fail("trapped", "no door reachable from %s on %s (bodies at %s)" % [cell, m.id, _live_bodies(ow).keys()])
	if frame % 30 == 0 and m.id == "town" and not state.bracelets.has("mossbank"):
		# The hall must stay reachable: crews that walked over to you stand
		# where they stopped until the map reloads.
		var hall: Array = []
		for w: Dictionary in m.warps:
			if w["to"] == "hall":
				hall.append(w["cell"])
		var bodies := str(_live_bodies(ow).keys())
		if not noted_cutoffs.has(bodies) and _bfs(ow, hall).is_empty() and m.warp_at(cell).is_empty() and cell not in hall:
			noted_cutoffs[bodies] = true
			_note("hall_cut_off", "the hall door can't be reached from %s past the crews standing at %s (a door resets them)" % [cell, _live_bodies(ow).keys()])


## The deck only grows (a pickup is saved the moment it's taken, so not
## even a quit without saving loses one).
func _check_deck_grows(state: GameState) -> void:
	if state.deck.size() < deck_max:
		_fail("deck_shrank", "the deck went from %d cards to %d" % [deck_max, state.deck.size()])
	deck_max = maxi(deck_max, state.deck.size())


## How far the run has got, for the stats (game frames from the start).
func _check_milestones(state: GameState, m: WorldMap) -> void:
	var aces := 0
	for id in opening_ids:
		if state.taken_pickups.has(id):
			aces += 1
	stats["aces"] = maxi(stats["aces"], aces)
	if m.id == "mill_road" and not stats["frames_to_mill_road"]:
		stats["frames_to_mill_road"] = frame
	if m.id == "town" and not stats["frames_to_town"]:
		stats["frames_to_town"] = frame
	if state.met_open_table and not stats["frames_to_crew"]:
		stats["frames_to_crew"] = frame


## The gate's line on screen: you walked into it short of Aces (counted),
## never with all 52.
func _check_gate_dialog(ow: Node, state: GameState, m: WorldMap) -> void:
	var dialog: Control = ow.get("dialog")
	var lines: Variant = dialog.get("_lines")
	var showing := false
	if dialog.visible and lines is Array:
		for g: Dictionary in m.gates:
			if (lines as Array).has(g["text"]):
				showing = true
	if showing and not gate_dialog_seen:
		stats["gate_refusals"] += 1
		_log("the gate says no (%d cards)" % state.deck.size())
		if state.has_full_deck():
			_fail("gate_refused", "the gate refused a dog holding all 52 cards")
	gate_dialog_seen = showing


## While walking: the gate holds (with Aces missing you're never anywhere
## you can't reach from the start with the gates shut), the cards on the
## ground are exactly the ones still waiting, the open table's players who
## joined you no longer stand there, and a dog alone in a crew's sight is
## left alone (spotted_alone fails on the encounter itself; this counts it).
func _check_opening(ow: Node, state: GameState, m: WorldMap, cell: Vector2i) -> void:
	if not state.has_full_deck() and not (inside_gate.get(m.id, {}) as Dictionary).has(cell):
		_fail("gate_bypassed", "on %s at %s holding %d cards: that's past Sootbridge's gate" % [m.id, cell, state.deck.size()])
	var drawn: Dictionary = ow.get("pickup_nodes")
	for p: Dictionary in m.pickups():
		var waiting := state.pickup_waiting(p["id"], p["card"])
		if drawn.has(p["id"]) and not waiting:
			_fail("pickup_reappeared", "the card %s at %s is drawn on %s but already taken" % [p["id"], p["cell"], m.id])
		elif waiting and not drawn.has(p["id"]):
			_fail("pickup_hidden", "the card %s at %s is waiting but not drawn on %s" % [p["id"], p["cell"], m.id])
	var data: Dictionary = ow.get("npc_data")
	for n: Object in ow.get("npc_nodes"):
		if WorldMap.npc_joined(data.get(n, {}), state):
			_fail("joined_still_standing", "%s joined you but still stands at %s" % [data[n]["id"], n.get("cell")])
	if state.party.is_empty() and cell != alone_cell:
		alone_cell = cell
		if not m.spotter(cell, state.beaten).is_empty():
			stats["alone_in_sight"] += 1
	if state.roster.is_empty() and state.money < int(WorldMap.OPEN_TABLE["buy_in"]) and not stranded_noted:
		stranded_noted = true
		_note("stranded", "a dog alone with $%d, under the open table's $%d buy-in: no crew will ever play it, so the demo can't be finished"
			% [state.money, int(WorldMap.OPEN_TABLE["buy_in"])])


## The four Aces' pickup ids: the ones lying about and the one given.
func _opening_ids() -> Array[String]:
	var out: Array[String] = []
	var aces := GameState.opening_missing_cards()
	for map_id: String in WorldMap.MAPS:
		var data: Dictionary = WorldMap.MAPS[map_id]
		for p: Dictionary in data.get("pickups", []):
			if aces.has(int(p["card"])):
				out.append(p["id"])
		for n: Dictionary in data["npcs"]:
			if n.has("gives_card") and aces.has(int(n["gives_card"]["card"])):
				out.append(n["gives_card"]["id"])
	return out


## Every cell you can stand on, map by map, from the start cell with every
## gate shut (through doors, not through gate cells): with Aces missing,
## the dog is always somewhere in here.
func _inside_gate() -> Dictionary:
	var out := {}
	var queue: Array = [[WorldMap.START_MAP, WorldMap.START_CELL]]
	var head := 0
	while head < queue.size():
		var map_id: String = queue[head][0]
		var c: Vector2i = queue[head][1]
		head += 1
		if not WorldMap.MAPS.has(map_id):
			continue
		var m := WorldMap.get_map(map_id)
		if not out.has(map_id):
			out[map_id] = {}
		var seen: Dictionary = out[map_id]
		if seen.has(c) or not m.tile_walkable(c) or not m.gate_at(c).is_empty():
			continue
		seen[c] = true
		var w := m.warp_at(c)
		if not w.is_empty():
			queue.append([w["to"], w["to_cell"]])
		for d in DIRS:
			queue.append([map_id, c + d])
	return out


func _roster_names(state: GameState) -> String:
	var names: Array[String] = []
	for a in state.roster:
		names.append(a.name)
	return str(names)


func _warp_cells(m: WorldMap) -> Array:
	var out: Array = []
	for w: Dictionary in m.warps:
		out.append(w["cell"])
	return out


func _check_state(state: GameState, mid_sequence: bool) -> void:
	if state.money < 0:
		_fail("money_negative", "money is %d" % state.money)
	var seen := {}
	for a in state.roster:
		var key := "%s:%s" % [a.species, a.name]
		if seen.has(key):
			_fail("roster_duplicate", "%s is in the roster twice" % key)
		seen[key] = true
		if not _allowed_animals(state).has(key):
			_fail("roster_stranger", "%s is in the roster but isn't Sage or Bandit or from a beaten crew" % key)
	for i in state.party:
		if i < 0 or i >= state.roster.size():
			_fail("party_index", "party seat points at roster %d of %d" % [i, state.roster.size()])
			return
	if not mid_sequence:
		# The dog alone has nobody to seat; from the open table on, two.
		if state.party.size() != mini(GameState.PARTY_SIZE, state.roster.size()):
			_fail("party_size", "%d animals seated (roster %d)" % [state.party.size(), state.roster.size()])
		if not from_old_save and not state.met_open_table and not state.roster.is_empty():
			_fail("crew_early", "a crew before the open table: %s" % _roster_names(state))
		if state.met_open_table:
			for e: Array in OPEN_TABLE_CREW:
				var a := Species.individual(StringName(e[0]), e[1])
				if not state.has_animal(a.species, a.name):
					_fail("crew_missing", "sat at the open table, but %s isn't in the roster %s" % [a.name, _roster_names(state)])
		var uniq := {}
		for i in state.party:
			uniq[i] = true
		if uniq.size() != state.party.size():
			_fail("party_duplicate", "the same animal sits twice: %s" % [state.party])
	if not mid_sequence and state.bracelets.has("mossbank") != state.is_beaten("mossbank_regulars"):
		_fail("bracelet", "bracelets %s but Regulars beaten: %s" % [state.bracelets, state.is_beaten("mossbank_regulars")])
	for id: String in state.beaten:
		if _crew(id).is_empty():
			_fail("beaten_unknown", "beaten has %s, which isn't a crew" % id)
	_check_deck(state)


## The deck (docs/DEMO_SPEC.md S-DECK, S-PICK): 48 to 52 cards, only the
## Aces ever missing, and each Ace held exactly when its pickup (or Mags's
## gift) has been taken, so 52 iff all four. A pre-demo save holds all 52
## with nothing taken.
func _check_deck(state: GameState) -> void:
	var n := state.deck.size()
	if n < GameState.DECK_SIZE - 4 or n > GameState.DECK_SIZE:
		_fail("deck_size", "the deck holds %d cards" % n)
	var aces := GameState.opening_missing_cards()
	for c in state.missing_cards():
		if not aces.has(c):
			_fail("deck_cards", "the deck is missing %s, which isn't an Ace" % GameState.card_name(c))
	for id: String in state.taken_pickups:
		if WorldMap.pickup_card(id) < 0:
			_fail("pickup_unknown", "taken_pickups has %s, which no map has" % id)
	if from_old_save:
		if not state.has_full_deck():
			_fail("deck_size", "a pre-demo save's run holds %d cards, not 52" % n)
		return
	for id in opening_ids:
		var card := WorldMap.pickup_card(id)
		if state.taken_pickups.has(id) != state.deck.has(card):
			_fail("deck_pickups", "%s is %s but the %s is %s the deck" % [id, "taken" if state.taken_pickups.has(id) else "not taken",
				GameState.card_name(card), "in" if state.deck.has(card) else "not in"])


func _allowed_animals(state: GameState) -> Dictionary:
	var out := {}
	for e: Array in OPEN_TABLE_CREW:  # Sage and Bandit, from the open table (a pre-demo save's starters)
		var a := Species.individual(StringName(e[0]), e[1])
		out["%s:%s" % [a.species, a.name]] = true
	for id: String in state.beaten:
		var crew := _crew(id)
		if crew:
			for a in WorldMap.crew_animals(crew):
				out["%s:%s" % [a.species, a.name]] = true
	return out


func _crew(id: String) -> Dictionary:
	for map_id: String in WorldMap.ids():
		var c := WorldMap.get_map(map_id).crew_by_id(id)
		if c:
			return c
	return {}


## Nothing on screen has changed for too long: a softlock. A table gets
## longer (its bots think for a while, the pause between hands).
func _check_softlock(ow: Node) -> void:
	var parts: Array = [ow.get("mode"), ow.get("map").id, ow.get("fade").color.a]
	for n: Node in ow.get("actors").get_children():
		parts.append(n.get("position"))
		parts.append(n.get("facing"))
	for key in ["dialog", "menu", "party_screen", "options_screen", "demo_complete"]:
		var c: Control = ow.get(key)
		parts.append([c.visible, c.get("_cursor"), c.get("_shown"), c.get("_lines").size() if c.get("_lines") != null else 0])
	parts.append(game.state.party.duplicate() if game.state else [])
	var table: Object = ow.get("table")
	var h := str(parts).hash()
	if table != null:
		var t: Object = table.get("match_").get("table")
		var tparts := [table.get("_flow"), t.get("hand_number"), t.get("to_act"), t.call("pot"), table.get("_help_open"),
			table.get("_menu_open"), table.get("_raise_open"), table.get("_leave_open"), table.get("_left_sent")]
		h = str(tparts).hash()
		if h != sig_hash:
			sig_hash = h
			table_sig_frame = frame
		elif frame - table_sig_frame > TABLE_STALL_FRAMES:
			var stuck := (frame - table_sig_frame) / 60
			table_sig_frame = frame  # once per stretch
			_fail("softlock_table", "the table hasn't changed for %d game s (flow %s)" % [stuck, str(tparts)])
		sig_frame = frame
		return
	if h != sig_hash:
		sig_hash = h
		sig_frame = frame
	elif frame - sig_frame > SOFTLOCK_FRAMES:
		sig_frame = frame  # once per stretch
		_fail("softlock", "nothing changed for %d frames: mode %s, %s" % [frame - sig_frame, ow.get("mode"), _screen(ow)])


func _check_slot_on_disk(when: String) -> void:
	var path: String = game.save_path
	var main_exists := FileAccess.file_exists(path)
	var part_exists := FileAccess.file_exists(path + ".part")
	var s := SaveFile.read(path)
	stats["slot_read"] = s != null
	_log("slot at %s: save %s, .part %s, reads %s" % [when, main_exists, part_exists, "ok" if s else "NO"])
	print("[pt] slot at %s: save %s, .part %s (%d bytes), reads %s" % [when, main_exists, part_exists,
		FileAccess.get_file_as_string(path + ".part").length() if part_exists else 0, "ok" if s else "NO"])
	if s:
		_check_state(s, false)
		var floor_path := path + ".floor"
		if FileAccess.file_exists(floor_path):
			# Progress a killed run had saved can't go backwards.
			var json := JSON.new()
			var before := {}
			if json.parse(FileAccess.get_file_as_string(floor_path)) == OK and json.data is Dictionary:
				before = json.data
			for id: Variant in before.get("beaten", []):
				if not s.is_beaten(str(id)):
					_fail("progress_lost", "crew %s was beaten in an earlier save and isn't now" % id)
			if s.roster.size() < int(before.get("roster", 0)):
				_fail("progress_lost", "roster shrank from %d to %d" % [int(before.get("roster", 0)), s.roster.size()])
			if s.deck.size() < int(before.get("deck", 0)):
				_fail("progress_lost", "the deck shrank from %d to %d cards" % [int(before.get("deck", 0)), s.deck.size()])
			for id: Variant in before.get("taken", []):
				if not s.taken_pickups.has(str(id)):
					_fail("progress_lost", "the card %s was taken in an earlier save and isn't now" % id)
	elif start == "continue" and not damage and main_exists:
		_fail("save_lost", "the save is there but doesn't read: %s" % FileAccess.get_file_as_string(path).left(200))
	elif start == "continue" and not damage and part_exists and FileAccess.file_exists(path + ".floor"):
		_fail("save_lost", "no save after a kill, only a .part (%d bytes)" % FileAccess.get_file_as_string(path + ".part").length())


# --- Damaged saves --------------------------------------------------------------

## A save that's been through some progress (the four Aces, the open table
## sat at and Sage and Bandit with you, a crew beaten, a goose recruited,
## money won), then broken one way. Kinds are listed in docs/PLAYTEST.md.
## "pre_demo" is no damage: the same save as written before demo 2 (no
## deck, pickups, opening or open table), which must load past the opening
## (--pt-start=old plays from one).
func _write_damaged(kind: String) -> void:
	var s := GameState.fresh()
	for c in GameState.opening_missing_cards():
		s.collect_card(c)
	for id in _opening_ids():
		s.taken_pickups[id] = true
	s.seen_intro = true
	s.tutorial_offered = true
	s.opening_done = true
	s.join_open_table_crew()
	s.win_against("pond_hecklers", 120)
	s.recruit(Species.individual(&"goose", 0))
	s.map_id = "town"
	s.cell = Vector2i(40, 12)
	var d := s.to_dict()
	var raw := ""
	var path: String = game.save_path
	match kind:
		"ok":
			pass
		"truncated": raw = JSON.stringify(d, "\t").left(90)
		"empty": raw = " "
		"garbage": raw = "\u0001\u0002 this is not json {"
		"array": raw = "[1, 2, 3]"
		"minimal": d = {"version": 1, "roster": d["roster"]}
		"no_version": d.erase("version")
		"future_version":
			d["version"] = 99
			d["pets"] = {"x": 1}
		"unknown_species":
			d["roster"][1]["species"] = "dragon"
			d["roster"][2]["species"] = "unicorn"
		"all_unknown_species":
			for a: Dictionary in d["roster"]:
				a["species"] = "dragon"
		"roster_dict": d["roster"] = {"a": 1}
		"roster_one":
			d["roster"] = [d["roster"][0]]
			d["party"] = [0]
		"roster_dupes": d["roster"] = [d["roster"][0], d["roster"][0], d["roster"][1]]
		"party_oob": d["party"] = [5, 9]
		"party_negative": d["party"] = [-1, 1]
		"party_dup": d["party"] = [0, 0]
		"party_one": d["party"] = [1]
		"party_three": d["party"] = [0, 1, 2]
		"party_strings": d["party"] = ["a", "b"]
		"money_negative": d["money"] = -500
		"money_string": d["money"] = "lots"
		"money_huge": d["money"] = 1e300
		"cell_wall": d["cell"] = [0, 0]
		"cell_oob": d["cell"] = [500, -3]
		"cell_string": d["cell"] = "12,7"
		"cell_crew_home": d["cell"] = [48, 7]  # the Alley Cats' leader, unbeaten
		"cell_recruit_home": d["cell"] = [44, 8]  # where the recruited goose stood
		"cell_door": d["cell"] = [7, 6]  # standing on the diner's door
		"map_unknown": d["map"] = "moon"
		"heal_wall": d["heal_cell"] = [0, 0]
		"heal_oob": d["heal_cell"] = [99, 99]
		"heal_map_unknown": d["heal_map"] = "moon"
		"beaten_unknown": d["beaten"] = ["ghost_crew", "pond_hecklers"]
		"beaten_regulars_no_bracelet": d["beaten"].append("mossbank_regulars")
		"bracelet_only": d["bracelets"] = ["mossbank"]
		"facing_zero": d["facing"] = [0, 0]
		"facing_weird": d["facing"] = [3, -7]
		"bond_weird":
			d["roster"][0]["bond"] = -3
			d["roster"][1]["bond"] = 99
		"unbeaten_member_in_roster": d["roster"].append({"species": "cat", "name": Species.individual(&"cat", 0).name, "bond": 0.2})
		"seen_intro_false": d["seen_intro"] = false
		"pre_demo":
			for k in ["deck", "taken_pickups", "opening_done", "met_open_table"]:
				d.erase(k)
		"pre_demo_alone":  # an impossible old save: nobody in the roster
			for k in ["deck", "taken_pickups", "opening_done", "met_open_table"]:
				d.erase(k)
			d["roster"] = []
			d["party"] = []
			d["beaten"] = []
		"deck_short_in_town": d["deck"] = (d["deck"] as Array).slice(0, 48)  # past the gate without the Aces
		"deck_garbage": d["deck"] = "fifty-two"
		"deck_dupes": d["deck"] = [51, 51, 51, 0, 0]
		"deck_oob": (d["deck"] as Array).append_array([52, -1, 99])
		"taken_unknown": (d["taken_pickups"] as Array).append("ace_on_the_moon")
		"alone_met_table":  # sat at the table, nobody with you (closed before they joined)
			d["roster"] = []
			d["party"] = []
			d["beaten"] = []
		"alone_before_table":
			d["roster"] = []
			d["party"] = []
			d["beaten"] = []
			d["met_open_table"] = false
		"part_only": raw = "PART_ONLY"
		"part_newer_main_truncated": raw = "PART_AND_BROKEN_MAIN"
		_:
			_fail("bad_flag", "unknown --pt-damage kind: " + kind)
			return
	SaveFile.erase(path)
	var text := raw if raw != "" else JSON.stringify(d, "\t")
	if raw == "PART_ONLY" or raw == "PART_AND_BROKEN_MAIN":
		text = JSON.stringify(d, "\t")
		var p := FileAccess.open(path + ".part", FileAccess.WRITE)
		p.store_string(text)
		p.close()
		if raw == "PART_ONLY":
			return
		text = text.left(60)
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


# --- Input ----------------------------------------------------------------------

func _press(action: String) -> void:
	_send(action, true)
	releases.append([frame + 1, action])


func _send(action: String, pressed: bool) -> void:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = pressed
	Input.parse_input_event(e)


func _hold(action: String) -> void:
	if held == action:
		return
	_release_move()
	Input.action_press(action)
	held = action


func _release_move() -> void:
	if held:
		Input.action_release(held)
		held = ""


# --- Reporting --------------------------------------------------------------------

func _log(line: String) -> void:
	var text := "f%d %s" % [frame, line]
	history.append(text)
	if history.size() > 60:
		history.pop_front()
	if args.has("verbose"):
		print("[pt] ", text)


## Something worth knowing that isn't a failure (or a failure kind this run
## was told to be lenient about).
func _note(kind: String, message: String) -> void:
	stats["notes_" + kind] = stats.get("notes_" + kind, 0) + 1
	if notes.size() < 20 and not notes.any(func(n: Dictionary) -> bool: return n["message"] == message):
		notes.append({"kind": kind, "message": message, "frame": frame})
	_log("note %s: %s" % [kind, message])


func _fail(kind: String, message: String) -> void:
	if lenient.has(kind):
		_note(kind, message)
		return
	for f in failures:
		if f["kind"] == kind and f["message"] == message:
			return
	failures.append({"kind": kind, "message": message, "frame": frame})
	printerr("[pt] FAIL %s at frame %d: %s" % [kind, frame, message])
	if not keep_going and not done:
		_finish("failure")


func _screen(ow: Node) -> String:
	var parts: Array[String] = []
	for key in ["dialog", "menu", "party_screen", "options_screen", "demo_complete"]:
		if ow.get(key).visible:
			parts.append(key)
	if ow.get("table") != null:
		parts.append("table")
	if _other_screen(ow):
		parts.append(_other_screen(ow))
	return "showing %s, fade %.2f, at %s %s" % [parts, ow.get("fade").color.a, ow.get("map").id, ow.get("player").get("cell")]


func _norm(d: Dictionary) -> String:
	return JSON.stringify(d, "", true)


func _brief(norm: String) -> String:
	var d: Variant = JSON.parse_string(norm)
	if not d is Dictionary:
		return norm.left(200)
	var names: Array = []
	for a: Dictionary in d.get("roster", []):
		names.append(a.get("name"))
	return "%s %s $%s party %s roster %s beaten %s" % [d.get("map"), d.get("cell"), d.get("money"), d.get("party"), names, d.get("beaten")]


func _diff(a: String, b: String) -> String:
	var da: Dictionary = JSON.parse_string(a)
	var db: Dictionary = JSON.parse_string(b)
	var out: Array[String] = []
	for k: String in da:
		if str(da[k]) != str(db.get(k)):
			out.append("%s: %s -> %s" % [k, da[k], db.get(k)])
	return ", ".join(out)


func _replay() -> String:
	var parts: Array[String] = []
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--pt-out="):
			parts.append(arg)
	if not args.has("seed"):
		parts.append("--pt-seed=%d" % seed_value)
	return "XDG_DATA_HOME=$(mktemp -d) godot --headless --fixed-fps 60 --path . -s tools/playtest.gd -- " + " ".join(parts)


func _finish(why: String) -> void:
	if done:
		return
	done = true
	_release_move()
	if game and game.state and failures.is_empty() and current_scene and current_scene.scene_file_path == WORLD_SCENE:
		game.save()  # the window closing saves; the check on it runs in _on_saved
	if watch.errors:
		for e in watch.errors:
			failures.append({"kind": "script_error", "message": e, "frame": frame})
	var state_dict: Dictionary = game.state.to_dict() if game and game.state else {}
	var result := {
		"ok": failures.is_empty(),
		"seed": seed_value,
		"why": why,
		"frames": frame,
		"real_s": (Time.get_ticks_msec() - started_ms) / 1000.0,
		"failures": failures,
		"stats": stats,
		"warnings": watch.warnings.slice(0, 10),
		"notes": notes,
		"state": _brief(_norm(state_dict)) if state_dict else "",
		"replay": _replay(),
	}
	result["stats"] = stats.duplicate()
	result["stats"]["maps"] = stats["maps"].keys()
	if failures:
		result["history"] = history
		printerr("[pt] last moves:\n    ", "\n    ".join(history))
		printerr("[pt] replay: ", result["replay"])
	if args.has("out"):
		var f := FileAccess.open(args["out"], FileAccess.READ_WRITE if FileAccess.file_exists(args["out"]) else FileAccess.WRITE)
		if f:
			f.seek_end()
			f.store_line(JSON.stringify(result))
			f.close()
	print("PLAYTEST ", JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)
