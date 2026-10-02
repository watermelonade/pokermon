class_name SceneTestCase
extends RefCounted
## Base for scene tests: tests/scene/test_*.gd, run by tests/scene_tests.tscn
## (tests/scene_runner.gd) with the real autoloads, the real title screen,
## overworld and table, driven by input events the way a player with a
## controller would. Every method named test_* is a test; it may (and
## usually does) await. Run headless with a fixed frame time:
##
##   godot --headless --fixed-fps 60 --path . res://tests/scene_tests.tscn -- journey
##
## With --fixed-fps every frame is exactly 1/60 s of game time however fast
## it runs, so timers, tweens, the dialog's typing and the table's clock all
## run many times faster than real time and a run replays the same way.
## Waits here count frames, so "seconds" below are game seconds.
##
## Why not tests/run_tests.gd: it runs as a SceneTree script, without the
## Game/Sfx/Triggers autoloads, so the overworld and title can't even
## compile there. Why not tools/playtest.gd: that's a random restless
## player checking invariants; these are scripted walks to exact outcomes
## (docs/DEMO_SPEC.md's G-* and J-*). The techniques are the playtester's:
## real input events, walking one step at a time along a BFS path, and
## reading the scenes' fields through get() (a rename makes a test fail a
## check, not crash).
##
## The rules for writing one:
## - Only await through these helpers (frames, seconds, wait_until and the
##   ones built on them), never a raw signal: the runner stops a hung test
##   by parking it at its next helper wait (see _stopped), which can't reach
##   a test waiting on some other signal; that one would wake up later, in
##   the middle of another test.
## - Guard before you use: `if not check(...): return` when the rest of the
##   test depends on it, so a missing feature fails a check, not a script
##   error (a script error fails the test as broken, even an expected-red one).
## - Each test starts from nothing: no save (its own file, user://scene_test.json,
##   erased before and after), Game.state null, no dev flags, no scene. Set
##   flags a test needs in `game.dev_args` (for example "match-result" or
##   "autoplay"); the runner clears them after.
## - Long tests set `timeout_s` first thing (default 120 game seconds).
##
## Everything a test sees in a dialog box or a menu is recorded as it shows
## (`heard`, `menus`), so a test can check what was said without catching
## the moment.

const TITLE_SCENE := "res://scenes/title.tscn"
const WORLD_SCENE := "res://scenes/world/overworld.tscn"
const WorldPaths := preload("res://tests/world_paths.gd")
const WALK := 0  ## the overworld's Mode
const BUSY := 1
const TABLE := 2
const FLOW_HUMAN := 1  ## TableView.Flow
const FLOW_HAND_DONE := 2
const FLOW_MATCH_DONE := 3
const DIRS: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
const DIR_ACTION := {Vector2i.UP: "move_up", Vector2i.DOWN: "move_down", Vector2i.LEFT: "move_left", Vector2i.RIGHT: "move_right"}
## The pad button each action is pressed with (project.godot's input map;
## the built-in ui_* actions have the D-pad too). Anything else goes in as
## an InputEventAction.
const PAD := {
	"ui_accept": JOY_BUTTON_A, "ui_cancel": JOY_BUTTON_B, "menu": JOY_BUTTON_START, "help": JOY_BUTTON_BACK,
	"move_up": JOY_BUTTON_DPAD_UP, "move_down": JOY_BUTTON_DPAD_DOWN, "move_left": JOY_BUTTON_DPAD_LEFT, "move_right": JOY_BUTTON_DPAD_RIGHT,
	"ui_up": JOY_BUTTON_DPAD_UP, "ui_down": JOY_BUTTON_DPAD_DOWN, "ui_left": JOY_BUTTON_DPAD_LEFT, "ui_right": JOY_BUTTON_DPAD_RIGHT,
}

var tree: SceneTree
var game: Node  ## the Game autoload
var failures: Array[String] = []
var timeout_s := 120.0  ## game seconds before the runner stops this test as hung
var heard: Array[String] = []  ## every dialog line shown, in order
var speakers: Array[String] = []  ## who said each line in `heard` ("" for nobody)
var menus: Array[String] = []  ## every menu shown: "title: option | option"
var last_stop := ""  ## why the last walk_to / talk_to / advance stopped short
var _current := ""
var _aborted := false  ## the runner gave up on this test: it parks at its next wait
var _held := {}  ## action -> true while held
var _dialog_key := ""
var _menu_key := ""


# --- Checks -------------------------------------------------------------------

func check(condition: bool, message := "") -> bool:
	if not condition:
		failures.append("%s: %s" % [_current, message if message else "check failed"])
	return condition


func check_eq(actual: Variant, expected: Variant, message := "") -> bool:
	if actual != expected:
		failures.append("%s: %s expected %s, got %s" % [_current, message, str(expected), str(actual)])
		return false
	return true


func fail(message: String) -> bool:
	return check(false, message)


## Whether any line heard so far contains `text` (case-insensitive).
func heard_line(text: String) -> bool:
	for l in heard:
		if text.to_lower() in l.to_lower():
			return true
	return false


# --- Time ---------------------------------------------------------------------

## Never emitted: a test the runner has stopped parks on it at its next
## wait, for good, so nothing more of it runs (GDScript can't cancel a
## coroutine, and returning at once would turn a test's own wait loop into
## a busy loop that hangs the runner).
signal _stopped


func frames(n := 1) -> void:
	for _i in n:
		if _aborted:
			await _stopped
		await tree.process_frame
		_observe()


func seconds(s: float) -> void:
	await frames(maxi(1, int(s * 60.0)))


## Waits until `condition` (a Callable returning bool) holds, up to
## `limit` game seconds; on timeout fails the test, saying `what`.
func wait_until(condition: Callable, limit: float, what: String) -> bool:
	var left := int(limit * 60.0)
	while not condition.call():
		if left <= 0:
			return fail("timed out after %.0f game seconds waiting for %s%s" % [limit, what, _where()])
		await frames(1)
		left -= 1
	return true


## Like wait_until, without failing: whether it came true in time.
func came_true(condition: Callable, limit: float) -> bool:
	var left := int(limit * 60.0)
	while not condition.call():
		if left <= 0:
			return false
		await frames(1)
		left -= 1
	return true


# --- Input (as a pad sends it) ----------------------------------------------------

func press(action: String) -> void:
	_send(action, true)
	await frames(1)
	_send(action, false)
	await frames(1)


func hold(action: String) -> void:
	if not _held.has(action):
		_held[action] = true
		_send(action, true)


func release(action: String) -> void:
	if _held.has(action):
		_held.erase(action)
		_send(action, false)


func release_all() -> void:
	for a: String in _held.keys():
		release(a)


func _send(action: String, pressed: bool) -> void:
	if PAD.has(action):
		var e := InputEventJoypadButton.new()
		e.device = 0
		e.button_index = PAD[action]
		e.pressed = pressed
		Input.parse_input_event(e)
	else:
		var a := InputEventAction.new()
		a.action = action
		a.pressed = pressed
		Input.parse_input_event(a)


# --- The scenes -------------------------------------------------------------------

func title() -> Node:
	var cs := tree.current_scene
	return cs if cs and cs.scene_file_path == TITLE_SCENE else null


func overworld() -> Node:
	var cs := tree.current_scene
	return cs if cs and cs.scene_file_path == WORLD_SCENE and cs.get("player") != null else null


func state() -> GameState:
	return game.state


func current_map() -> WorldMap:
	var ow := overworld()
	return ow.get("map") if ow else null


func map_id() -> String:
	var m := current_map()
	return m.id if m else ""


func player() -> Object:
	var ow := overworld()
	return ow.get("player") if ow else null


func player_cell() -> Vector2i:
	var p := player()
	return p.get("cell") if p else Vector2i(-999, -999)


func dialog() -> Control:
	var ow := overworld()
	return ow.get("dialog") if ow else null


func menu() -> Control:
	var ow := overworld()
	return ow.get("menu") if ow else null


func table() -> Object:
	var ow := overworld()
	return ow.get("table") if ow else null


func dialog_open() -> bool:
	var d := dialog()
	return d != null and d.visible


func menu_open() -> bool:
	var m := menu()
	return m != null and m.visible


func at_table() -> bool:
	return table() != null


## Free to walk: the overworld in WALK mode, not mid-step, nothing on screen.
func walking() -> bool:
	var ow := overworld()
	if ow == null or int(ow.get("mode")) != WALK or ow.get("_moving"):
		return false
	return not dialog_open() and not menu_open() and not at_table()


## The current dialog line ("" if none).
func dialog_line() -> String:
	var d := dialog()
	if d == null or not d.visible:
		return ""
	var lines: Array = d.get("_lines")
	return str(lines[0]) if lines else ""


## The open menu's options ([] if none).
func menu_options() -> Array:
	return menu().get("_options") if menu_open() else []


## Goes to the title screen with no run loaded (as launching the game).
func goto_title() -> bool:
	release_all()
	game.state = null
	tree.change_scene_to_file(TITLE_SCENE)
	return await wait_until(func() -> bool: return title() != null, 5.0, "the title screen")


## Picks `option` on the title ("New game", "Continue"), as a player would.
func choose_on_title(option: String) -> bool:
	if title() == null and not await goto_title():
		return false
	await frames(2)
	var options: Array = title().get("_options")
	var want := options.find(option)
	if want < 0:
		return fail("the title has no \"%s\" (it has %s)" % [option, options])
	for _i in 8:
		var cursor := int(title().get("_cursor"))
		if cursor == want:
			break
		await press("ui_down" if want > cursor else "ui_up")
	await press("ui_accept")
	if option == "New game" and title() != null and title().get("_confirming"):
		await press("ui_up")  # "No" is first under the cursor: up to "Yes, start over"
		await press("ui_accept")
	return await wait_until(func() -> bool: return overworld() != null, 10.0, "the overworld after %s" % option)


## New game from the title (the intro is left to play: see advance()).
func start_new_game() -> bool:
	return await choose_on_title("New game")


## Continue from the title, from whatever the save holds.
func continue_game() -> bool:
	return await choose_on_title("Continue")


## Writes `s` as the save and continues it from the title: how a test
## starts somewhere other than the beginning.
func continue_from(s: GameState) -> bool:
	if not check_eq(SaveFile.write(s, game.save_path), OK, "writing the test's save"):
		return false
	game.state = null
	return await continue_game()


## Saves through the Start menu (Save, then Close), quits to the title the
## way closing the window does, and continues. Returns whether it got back
## to walking.
func save_quit_continue() -> bool:
	if not await wait_until(walking, 10.0, "walking, to open the menu"):
		return false
	await press("menu")
	if not await wait_until(menu_open, 3.0, "the Start menu"):
		return false
	if not await choose("Save"):
		return false
	await advance(5.0, "stop")  # "Saved!" then back to the menu
	if menu_open():
		await choose("Close")
	if not await wait_until(walking, 5.0, "walking after the Start menu"):
		return false
	if not await goto_title():
		return false
	if not await continue_game():
		return false
	return await advance(10.0)


# --- Dialogs and menus ---------------------------------------------------------------

## Presses A through dialog lines until you're free to walk (true). A menu
## stops it (false, the menu left open) when on_menu is "stop"; "cancel"
## answers it with B and goes on. A table opening stops it (false).
func advance(limit := 30.0, on_menu := "stop") -> bool:
	var left := int(limit * 60.0)
	var calm := 0
	while left > 0:
		if at_table():
			last_stop = "a table opened"
			return false
		if dialog_open():
			calm = 0
			await press("ui_accept")
			left -= 2
			continue
		if menu_open():
			calm = 0
			if on_menu == "stop":
				last_stop = "a menu: %s" % _menu_text()
				return false
			await press("ui_cancel")
			left -= 2
			continue
		if walking():
			calm += 1
			if calm >= 6:  # dialogs chained by a fade or a walk have gaps
				return true
		else:
			calm = 0
		await frames(1)
		left -= 1
	last_stop = "still busy after %.0f s%s" % [limit, _where()]
	return false


## In an open menu, moves to the first option starting with `prefix`
## (ignoring case) and takes it.
func choose(prefix: String) -> bool:
	if not await wait_until(menu_open, 3.0, "a menu to choose \"%s\" in" % prefix):
		return false
	var options := menu_options()
	var want := -1
	for i in options.size():
		if str(options[i]).to_lower().begins_with(prefix.to_lower()):
			want = i
			break
	if want < 0:
		return fail("no \"%s\" in the menu %s" % [prefix, _menu_text()])
	for _i in options.size() + 1:
		var cursor := int(menu().get("_cursor"))
		if cursor == want:
			break
		await press("ui_down" if want > cursor else "ui_up")
	await press("ui_accept")
	return true


## In an open menu, moves to option `index` and takes it.
func choose_index(index: int) -> bool:
	if not await wait_until(menu_open, 3.0, "a menu to choose option %d in" % index):
		return false
	if index >= menu_options().size():
		return fail("no option %d in the menu %s" % [index, _menu_text()])
	for _i in menu_options().size() + 1:
		var cursor := int(menu().get("_cursor"))
		if cursor == index:
			break
		await press("ui_down" if index > cursor else "ui_up")
	await press("ui_accept")
	return true


func _menu_text() -> String:
	if not menu_open():
		return "(none)"
	return "%s: %s" % [menu().get("_title"), " | ".join(menu_options())]


# --- Walking ------------------------------------------------------------------------

## Walks to `cell` (on `to_map`, default the current map), one step at a
## time along a BFS path around walls, anyone standing and a shut gate,
## through warps when the cell is on another map. Dialog lines on the way
## (a pickup, a crew) are read through with A and recorded. Stops (false,
## with last_stop saying why) at a menu, a table, no path, or the timeout.
func walk_to(cell: Vector2i, to_map := "", limit := 120.0) -> bool:
	return await _walk([cell], to_map, limit)


## Walks to any of `cells` (on `to_map`), as walk_to.
func walk_to_any(cells: Array, to_map := "", limit := 120.0) -> bool:
	return await _walk(cells, to_map, limit)


## Walks next to the townsperson `npc_id` (on `on_map`, default the current
## map), faces them and presses A. True once they're talking (a dialog or
## menu is open).
func talk_to(npc_id: String, on_map := "", limit := 120.0) -> bool:
	if on_map != "" and on_map != map_id():
		var entry := _npc_entry(on_map, npc_id)
		if entry.is_empty():
			last_stop = "nobody called %s on %s" % [npc_id, on_map]
			return false
		if not await _walk(WorldPaths.talk_spots(WorldMap.get_map(on_map), entry["cell"]), on_map, limit):
			return false
	var node := npc_node(npc_id)
	if node == null:
		last_stop = "nobody called %s on %s" % [npc_id, map_id()]
		return false
	var target: Vector2i = node.get("cell")
	var spots := WorldPaths.talk_spots(current_map(), target)
	if not spots.has(player_cell()) and not await _walk(spots, "", limit):
		return false
	var cell := player_cell()
	var dir := Vector2i(signi(target.x - cell.x), signi(target.y - cell.y))
	if not await face(dir):
		return false
	await press("ui_accept")
	if not await came_true(func() -> bool: return dialog_open() or menu_open() or at_table(), 3.0):
		last_stop = "pressed A facing %s, nothing happened" % npc_id
		return false
	return true


## The townsperson node with this id on the current map, or null.
func npc_node(npc_id: String) -> Object:
	var ow := overworld()
	if ow == null:
		return null
	var data: Dictionary = ow.get("npc_data")
	for n: Object in ow.get("npc_nodes"):
		if is_instance_valid(n) and str((data.get(n, {}) as Dictionary).get("id", "")) == npc_id:
			return n
	return null


func _npc_entry(on_map: String, npc_id: String) -> Dictionary:
	if not WorldMap.MAPS.has(on_map):
		return {}
	for n: Dictionary in WorldMap.get_map(on_map).npcs:
		if str(n.get("id", "")) == npc_id:
			return n
	return {}


## Turns to face `dir` (a tap toward it: blocked, so you just turn).
func face(dir: Vector2i) -> bool:
	if not DIR_ACTION.has(dir):
		last_stop = "can't face %s" % dir
		return false
	for _i in 30:
		if Vector2i(player().get("facing")) == dir:
			release_all()
			return true
		hold(DIR_ACTION[dir])
		await frames(1)
	release_all()
	last_stop = "couldn't turn to face %s" % dir
	return false


## Tries one step toward `dir` and waits for it to land (or not).
func step(dir: Vector2i) -> void:
	hold(DIR_ACTION[dir])
	await came_true(func() -> bool: return overworld() == null or overworld().get("_moving") or not walking(), 0.25)
	release_all()
	await came_true(func() -> bool: return overworld() != null and not overworld().get("_moving"), 2.0)
	await frames(2)


func _walk(goals: Array, to_map: String, limit: float) -> bool:
	var left := int(limit * 60.0)
	var stalls := 0
	var last_cell := Vector2i(-999, -999)
	last_stop = ""
	while left > 0:
		var ow := overworld()
		if ow == null:
			await frames(1)
			left -= 1
			continue
		var target_map := to_map if to_map != "" else map_id()
		if map_id() == target_map and goals.has(player_cell()) and walking():
			release_all()
			return true
		if at_table():
			release_all()
			last_stop = "a table opened on the way"
			return false
		if menu_open():
			release_all()
			last_stop = "a menu opened on the way: %s" % _menu_text()
			return false
		if dialog_open():
			release_all()
			await press("ui_accept")
			left -= 2
			continue
		if not walking():
			release_all()
			await frames(1)
			left -= 1
			continue
		var next := _next_step(goals, target_map)
		if next == Vector2i.ZERO:
			release_all()
			last_stop = "no path from %s %s to %s %s" % [map_id(), player_cell(), target_map, goals]
			return false
		if player_cell() == last_cell:
			stalls += 1
			if stalls > 5:
				release_all()
				last_stop = "stuck at %s %s, stepping %s" % [map_id(), player_cell(), next]
				return false
		else:
			stalls = 0
		last_cell = player_cell()
		await step(next)
		left -= 10
	release_all()
	if last_stop == "":
		last_stop = "didn't get to %s %s in %.0f s%s" % [to_map, goals, limit, _where()]
	return false


## The direction of the first step toward `goals` on `target_map`, or
## ZERO if there's no way. On another map: toward the warp that leads
## there soonest.
func _next_step(goals: Array, target_map: String) -> Vector2i:
	var m := current_map()
	var here := player_cell()
	var cells: Array = goals
	if m.id != target_map:
		cells = _warps_toward(target_map)
	var path := _bfs(m, here, cells)
	if path.is_empty():
		return Vector2i.ZERO
	return path[0] - here


## The warp cells on this map, closest (in maps) to `target_map` first.
func _warps_toward(target_map: String) -> Array:
	var m := current_map()
	var best: Array = []
	var best_hops := 1 << 30
	for w: Dictionary in m.warps:
		var hops := _map_hops(w["to"], target_map, {m.id: true})
		if hops < best_hops:
			best = [w["cell"]]
			best_hops = hops
		elif hops == best_hops and hops < (1 << 30):
			best.append(w["cell"])
	return best


## Warps needed from map `from` to `to` (BFS over the map graph).
func _map_hops(from: String, to: String, seen: Dictionary) -> int:
	var dist := {from: 0}
	var queue := [from]
	while queue:
		var id: String = queue.pop_front()
		if id == to:
			return dist[id]
		if not WorldMap.MAPS.has(id):
			continue
		for w: Dictionary in WorldMap.get_map(id).warps:
			if not dist.has(w["to"]) and not seen.has(w["to"]):
				dist[w["to"]] = dist[id] + 1
				queue.append(w["to"])
	return 1 << 30


## Shortest walk from `from` to any of `goals` on `m`, around walls, anyone
## standing now, a shut gate, and doors that aren't goals: the cells after
## `from`, in order ([] if there's no way).
func _bfs(m: WorldMap, from: Vector2i, goals: Array) -> Array:
	var blocked := _live_bodies()
	var gate_open := state() != null and state().has_full_deck()
	var goal := {}
	for g: Vector2i in goals:
		goal[g] = true
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
			if not gate_open and not m.gate_at(n).is_empty():
				continue
			if not m.warp_at(n).is_empty() and not goal.has(n):
				continue
			came[n] = c
			queue.append(n)
	return []


## Every cell someone stands on right now (townsfolk and crews).
func _live_bodies() -> Dictionary:
	var out := {}
	var ow := overworld()
	if ow == null:
		return out
	for n: Object in ow.get("npc_nodes"):
		if is_instance_valid(n):
			out[n.get("cell")] = true
	var crews: Dictionary = ow.get("crew_nodes")
	for id: String in crews:
		for n: Object in crews[id]:
			if n != null and is_instance_valid(n):
				out[n.get("cell")] = true
	return out


# --- The table ----------------------------------------------------------------------

## The embedded table's flow (FLOW_*), or -1 with no table.
func table_flow() -> int:
	var t := table()
	return int(t.get("_flow")) if t else -1


## The table's hand number (HoldemTable.hand_number), or -1.
func table_hand() -> int:
	var t := table()
	if t == null or t.get("match_") == null:
		return -1
	return int(t.get("match_").get("table").get("hand_number"))


## Waits until hand `n` has finished at the table (the result is showing).
func wait_for_hand_done(n: int, limit: float) -> bool:
	return await wait_until(func() -> bool: return at_table() and table_hand() >= n and table_flow() in [FLOW_HAND_DONE, FLOW_MATCH_DONE],
		limit, "hand %d to finish at the table (is a bot playing your seat? Game.dev_args has autoplay: %s)" % [n, game.dev_args.has("autoplay")])


## Leaves a cash table the way the spec has it (docs/DEMO_SPEC.md G-LEAVE):
## once a hand is over, Start, then A on the offer (its first option,
## leaving: see "Test decisions"). Returns the chips the table's
## left(chips) signal reported, or -1 if it never did or the table stayed.
func leave_table(limit := 60.0) -> int:
	var t := table()
	if t == null:
		last_stop = "no table to leave"
		return -1
	var got: Array[int] = []
	if t.has_signal("left"):
		t.connect("left", func(chips: int) -> void: got.append(chips))
	if not await wait_until(func() -> bool: return table_flow() in [FLOW_HAND_DONE, FLOW_MATCH_DONE], limit, "a hand to finish, to leave after it"):
		return -1
	await press("menu")
	await frames(10)
	await press("ui_accept")
	if not await came_true(func() -> bool: return not at_table(), 30.0):
		last_stop = "Start then A after a hand didn't close the table"
		return -1
	if got.size() != 1:
		last_stop = "the table's left(chips) fired %d times" % got.size()
		return -1
	return got[0]


# --- Demo 2 -----------------------------------------------------------------------------

## The four Aces as cards (GameState.OPENING_MISSING).
static func aces() -> Array[int]:
	var out: Array[int] = []
	for c: String in GameState.OPENING_MISSING:
		out.append(Card.parse(c))
	return out


## A card the way a line names it: "Ace of Spades" (see "Test decisions").
static func card_name(card: int) -> String:
	var ranks := ["Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine", "Ten", "Jack", "Queen", "King", "Ace"]
	var suits := ["Clubs", "Diamonds", "Hearts", "Spades"]
	return "%s of %s" % [ranks[Card.rank(card) - 2], suits[Card.suit(card)]]


## A run past the opening, standing at `cell` on `on_map`: a new game with
## all four Aces collected, the intro seen and the opening done (Rosie's
## lessons not offered yet, as in a new game). For tests that start
## somewhere along the way: write it with continue_from().
static func demo_state_at(on_map: String, cell: Vector2i) -> GameState:
	var s := GameState.fresh()
	for c in aces():
		s.collect_card(c)
	s.opening_done = true
	s.seen_intro = true
	s.map_id = on_map
	s.cell = cell
	return s


## The npc entries at Mossbank's open table (WorldMap.open_tables()).
static func open_table_npcs() -> Array:
	return WorldMap.get_map("town").open_tables()


## Sootbridge's street game (demo 2.1, W-STREET): [map id, npc entry] for
## each npc on the maps reachable from the start with the gate shut whose
## `open_table` carries a "stake".
static func street_game_npcs() -> Array:
	var out: Array = []
	if not WorldMap.MAPS.has(WorldMap.START_MAP):
		return out
	for id: String in WorldPaths.maps_reached(WorldMap.START_MAP, WorldMap.START_CELL, false):
		for n: Dictionary in WorldMap.get_map(id).npcs:
			if n.has("open_table") and (n["open_table"] as Dictionary).has("stake"):
				out.append([id, n])
	return out


## Your stack at the table (seat 0), or -1 with no table.
func table_stack() -> int:
	var t := table()
	if t == null or t.get("match_") == null:
		return -1
	return int((t.get("match_").get("table").get("seats") as Array)[0].get("stack"))


## The save file as it is on disk right now (null if it doesn't read).
func save_on_disk() -> GameState:
	return SaveFile.read(game.save_path)


## Where the Mill Road comes into Mossbank, or (-1, -1).
static func mossbank_entry() -> Vector2i:
	if not WorldMap.MAPS.has("mill_road"):
		return Vector2i(-1, -1)
	for w: Dictionary in WorldMap.get_map("mill_road").warps:
		if w["to"] == "town":
			return w["to_cell"]
	return Vector2i(-1, -1)


# --- Recording ------------------------------------------------------------------------

func _observe() -> void:
	var d := dialog()
	if d != null and d.visible:
		var line := dialog_line()
		var key := "%s|%s" % [d.get("_opened_frame"), line]
		if key != _dialog_key and line != "":
			_dialog_key = key
			heard.append(line)
			speakers.append(str(d.get("_speaker")))
	var m := menu()
	if m != null and m.visible:
		var key := "%s|%s" % [m.get("_opened_frame"), _menu_text()]
		if key != _menu_key:
			_menu_key = key
			menus.append(_menu_text())


func _where() -> String:
	var ow := overworld()
	if ow == null:
		return " (no overworld: %s)" % (tree.current_scene.scene_file_path if tree.current_scene else "no scene")
	var screen := "walking" if walking() else ("a dialog: \"%s\"" % dialog_line() if dialog_open() else ("a menu: %s" % _menu_text() if menu_open() else ("at the table" if at_table() else "busy")))
	return " (at %s %s, %s)" % [map_id(), player_cell(), screen]
