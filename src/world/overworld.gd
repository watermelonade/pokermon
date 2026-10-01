extends Node2D
## The overworld: walk Mossbank and Ridge Road, get spotted by rival crews,
## play them at the poker table, and take the Mossbank Open. The rules of
## the run live in GameState and the maps in WorldMap; this node is the
## glue: input, movement, the encounter script, and handing over to the
## table and back.
##
## Movement is on the 16px grid, Pokemon style: hold a direction and you
## walk tile to tile, each step tweened. Your two seated animals follow in
## your footsteps (each takes the cell the one ahead just left), and start
## stacked under you after a door, then fan out as you walk.
##
## Encounters: after every step, WorldMap.spotter() asks whether an
## unbeaten crew's leader can see you. If so: "!" over it, it walks up, says
## its piece, and the table (scenes/table.tscn, embedded) takes over the
## screen on its own CanvasLayer. The overworld waits on the table's
## finished(won) signal, frees it, and carries on from the same spot. Win:
## money and a recruit; lose: wake at the diner with half your money.
##
## Tutorial: a new game ends its intro with Rosie offering her table
## lessons (src/tutorial/), once (GameState.tutorial_offered); after that
## they're on her menu at the diner. They play at the embedded table like a
## match, but nothing is won or lost: only finishing them is remembered.
##
## Dev flags are parsed by the Game autoload (see src/game/game.gd).

enum Mode { WALK, BUSY, TABLE }

const TABLE_SCENE := preload("res://scenes/table.tscn")
const AREA_NAMES := {"diner": "Rosie's Diner", "home": "Home", "hall": "Mossbank Tournament Hall"}

const ROAD_GAME_HANDS := 20
var _settled := {}  ## the last match's outcome, applied once (see _settle)
var _match_count := 0
var _music: AudioStreamPlayer
var state: GameState
var map: WorldMap
var mode := Mode.BUSY
var map_view: MapView
var actors: Node2D
var player: Critter
var followers: Array[Critter] = []
var crew_nodes := {}  ## crew id -> Array of Critter (null where an animal has left to join you)
var npc_nodes: Array[Critter] = []
var npc_data := {}  ## Critter -> its map entry
var camera: Camera2D
var dialog: DialogBox
var menu: ChoiceMenu
var party_screen: PartyScreen
var options_screen: OptionsScreen
var demo_complete: DemoComplete
var table_layer: CanvasLayer
var fade: ColorRect
var table: Variant = null  ## the embedded TableView (no class_name to type it with)
var _moving := false
var _area := ""
var _area_until := 0
var _hud: Control
var _script: Array = []  ## scripted input from --walk: [kind, count]


func _ready() -> void:
	if Game.state == null:  # run directly (F6), or a dev run: continue or start fresh
		if Game.dev_args.has("new") or not Game.continue_game():
			Game.new_game()
	Game.apply_dev_state()
	state = Game.state
	RenderingServer.set_default_clear_color(UiKit.BG)  # around the small interiors
	_build()
	_parse_walk(Game.dev("walk"))
	# A save can stand you where you can't be (in a wall, after a map edit;
	# where a crew member stands when the map loads): the nearest open spot.
	var start := WorldMap.get_map(state.map_id)
	state.cell = start.open_cell_near(state.cell, start.standing_cells(state))
	_load_map(state.map_id, state.cell, state.facing)
	await _fade_in()
	if not state.seen_intro:
		state.seen_intro = true
		await _intro()
		await _offer_tutorial()
		Game.save()
		_area = ""
		_show_area()  # the banner timed out behind the intro
	await _resume_after_win()
	mode = Mode.WALK
	match Game.dev("show"):
		"party":
			_open_party()
		"start":
			_open_start_menu()
		"binder":
			mode = Mode.BUSY
			await _open_binder()
			mode = Mode.WALK
		"options":
			mode = Mode.BUSY
			await options_screen.open(Game.settings)
			mode = Mode.WALK
		"demo_complete":
			mode = Mode.BUSY
			await demo_complete.open(state, _road_crew_count())
			mode = Mode.WALK
		"tutorial":
			mode = Mode.BUSY
			await _play_tutorial()
			mode = Mode.WALK


## A win whose dialogue was cut short (the window closed): make the recruit
## offer it still owes, or show the demo-complete screen once.
func _resume_after_win() -> void:
	if state.pending_recruit:
		var crew := map.crew_by_id(state.pending_recruit)  # the win happened on this map
		if not crew.is_empty() and crew_nodes.has(crew["id"]):
			mode = Mode.BUSY
			await _offer_recruit(crew)
		state.pending_recruit = ""
		Game.save()
	if not state.bracelets.is_empty() and not state.demo_complete_seen:
		mode = Mode.BUSY
		await _show_demo_complete()


func _build() -> void:
	map_view = MapView.new()
	add_child(map_view)
	actors = Node2D.new()
	actors.y_sort_enabled = true
	add_child(actors)
	camera = Camera2D.new()
	add_child(camera)
	camera.make_current()
	table_layer = CanvasLayer.new()
	table_layer.layer = 10
	add_child(table_layer)
	var ui := CanvasLayer.new()
	ui.layer = 5
	add_child(ui)
	_hud = Control.new()
	_hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.draw.connect(_draw_hud)
	ui.add_child(_hud)
	dialog = DialogBox.new()
	ui.add_child(dialog)
	menu = ChoiceMenu.new()
	ui.add_child(menu)
	party_screen = PartyScreen.new()
	ui.add_child(party_screen)
	options_screen = OptionsScreen.new()
	ui.add_child(options_screen)
	demo_complete = DemoComplete.new()
	ui.add_child(demo_complete)
	fade = ColorRect.new()
	fade.color = Color.BLACK
	fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(fade)


# --- Maps -------------------------------------------------------------------

func _load_map(map_id: String, cell: Vector2i, facing: Vector2i) -> void:
	map = WorldMap.get_map(map_id)
	_play_room_music(map_id)
	state.map_id = map_id
	state.cell = cell
	state.facing = facing
	map_view.show_map(map)
	for c in actors.get_children():
		c.queue_free()
	crew_nodes.clear()
	npc_nodes.clear()
	npc_data.clear()
	followers.clear()
	for n: Dictionary in map.npcs:
		var node := Critter.make(n["sprite"], n["cell"], n["facing"])
		node.asleep = n.get("asleep", false)
		actors.add_child(node)
		npc_nodes.append(node)
		npc_data[node] = n
	for c: Dictionary in map.crews:
		var cells := WorldMap.crew_cells(c)
		var animals := WorldMap.crew_animals(c)
		var nodes: Array = []
		for i in animals.size():
			if state.has_animal(animals[i].species, animals[i].name):
				nodes.append(null)  # this one joined you
				continue
			var node := Critter.make(String(animals[i].species), cells[i], c["facing"])
			actors.add_child(node)
			nodes.append(node)
		crew_nodes[c["id"]] = nodes
	_make_followers(cell, facing)
	player = Critter.make("player", cell, facing)
	actors.add_child(player)
	_update_camera()
	_show_area()


func _make_followers(cell: Vector2i, facing: Vector2i) -> void:
	for f in followers:
		f.queue_free()
	followers.clear()
	for a in state.party_animals():
		var f := Critter.make(String(a.species), cell, facing)
		actors.add_child(f)
		actors.move_child(f, 0)  # under the player when stacked
		followers.append(f)


## The lounge loop plays in the card rooms (the diner and the hall), and
## nothing outdoors until there's route music.
func _play_room_music(map_id: String) -> void:
	if _music == null:
		_music = AudioStreamPlayer.new()
		_music.stream = load("res://assets/audio/music/lounge_loop.wav")
		_music.volume_db = -10.0  # under the effects, per assets/audio/README.md
		add_child(_music)
	var card_room := map_id in ["diner", "hall"]
	if card_room and not _music.playing:
		_music.play()
	elif not card_room:
		_music.stop()


func _area_name() -> String:
	if map.id == "town":
		return "Mossbank" if state.cell.x < 34 else ("Ridge Road" if state.cell.x < 86 else "Mossbank Hall Plaza")
	return AREA_NAMES.get(map.id, map.id)


func _show_area() -> void:
	var name := _area_name()
	if name != _area:
		_area = name
		_area_until = Time.get_ticks_msec() + 2200
		_hud.queue_redraw()


func _draw_hud() -> void:
	if Time.get_ticks_msec() < _area_until and mode != Mode.TABLE:
		var w := UiKit.text_width(_area, 10) + 20
		UiKit.panel(_hud, Rect2(8, 8, w, 22))
		UiKit.text(_hud, Vector2(18, 23), _area, 10, UiKit.TEXT)


func _update_camera() -> void:
	var view := get_viewport_rect().size
	var world := map.pixel_size()
	var target := player.position + Vector2(8, 8)
	# Follow, but never show past the map's edge; a map smaller than the
	# screen (the interiors) sits in the middle.
	if world.x <= view.x:
		target.x = world.x / 2
	else:
		target.x = clampf(target.x, view.x / 2, world.x - view.x / 2)
	if world.y <= view.y:
		target.y = world.y / 2
	else:
		target.y = clampf(target.y, view.y / 2, world.y - view.y / 2)
	camera.position = target.round()


# --- Walking ----------------------------------------------------------------

func _process(_delta: float) -> void:
	if player == null:
		return
	_update_camera()
	if _hud and Time.get_ticks_msec() < _area_until + 100:
		_hud.queue_redraw()
	if mode != Mode.WALK or _moving:
		return
	_run_script()
	var dir := _input_dir()
	if dir != Vector2i.ZERO:
		_try_step(dir)


func _input_dir() -> Vector2i:
	if _script and _script[0][0] in ["U", "D", "L", "R"]:
		var step: Array = _script[0]
		step[1] -= 1
		if step[1] <= 0:
			_script.pop_front()
		return {"U": Vector2i.UP, "D": Vector2i.DOWN, "L": Vector2i.LEFT, "R": Vector2i.RIGHT}[step[0]]
	# One axis at a time, the last-pressed winning ties would be nicer;
	# vertical first is what most grid games do.
	if Input.is_action_pressed("move_up"):
		return Vector2i.UP
	if Input.is_action_pressed("move_down"):
		return Vector2i.DOWN
	if Input.is_action_pressed("move_left"):
		return Vector2i.LEFT
	if Input.is_action_pressed("move_right"):
		return Vector2i.RIGHT
	return Vector2i.ZERO


func _occupied(cell: Vector2i) -> bool:
	for n in npc_nodes:
		if n.cell == cell:
			return true
	for nodes: Array in crew_nodes.values():
		for n: Critter in nodes:
			if n and n.cell == cell:
				return true
	return false


func _try_step(dir: Vector2i) -> void:
	player.face(dir)
	state.facing = dir
	var target := player.cell + dir
	if not map.tile_walkable(target) or _occupied(target):
		return
	_moving = true
	var trail := [player.cell]
	for f in followers:
		trail.append(f.cell)
	for i in followers.size():
		if followers[i].cell != trail[i]:
			followers[i].step_to(trail[i])
	Sfx.play(&"step_grass" if map.outdoor else &"step_wood")
	await player.step_to(target)
	state.cell = target
	_moving = false
	_arrived(target)


func _arrived(cell: Vector2i) -> void:
	_show_area()
	var w := map.warp_at(cell)
	if w:
		_warp(w)
		return
	var crew := map.spotter(cell, state.beaten)
	if crew:
		_encounter(crew, true)


func _warp(w: Dictionary) -> void:
	mode = Mode.BUSY
	await _fade_out()
	_load_map(w["to"], w["to_cell"], w["facing"])
	Game.save()  # on every door: entering a building is a natural checkpoint
	await _fade_in()
	mode = Mode.WALK


func _fade_out(time := 0.18) -> void:
	var tw := create_tween()
	tw.tween_property(fade, "color:a", 1.0, time)
	await tw.finished


func _fade_in(time := 0.18) -> void:
	var tw := create_tween()
	tw.tween_property(fade, "color:a", 0.0, time)
	await tw.finished


# --- Talking ----------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if mode != Mode.WALK or _moving:
		return
	if event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		_interact()
	elif event.is_action_pressed("menu"):
		get_viewport().set_input_as_handled()
		_open_start_menu()


func _interact() -> void:
	var front := player.cell + player.facing
	if map.char_at(front) == "C":  # talk across the counter, like a Pokemon Center
		front += player.facing
	for id: String in crew_nodes:
		for n: Critter in crew_nodes[id]:
			if n and n.cell == front:
				var crew := map.crew_by_id(id)
				if state.is_beaten(id):
					mode = Mode.BUSY
					n.face(-player.facing)
					await dialog.say([crew["after"]], _crew_title(crew))
					mode = Mode.WALK
				else:
					_encounter(crew, false)
				return
	for n in npc_nodes:
		if n.cell == front:
			mode = Mode.BUSY
			if not n.asleep:
				n.face(-player.facing)
			var data: Dictionary = npc_data[n]
			var lines: Array = data["lines"]
			if data["id"] == "rosie" and state.bracelets.size() > 0:
				lines = ["The Mossbank bracelet! Pie for the champ. On the house. (Not that House, hon.)"]
			await dialog.say(lines, str(data.get("name", str(data["id"]).capitalize())))
			if data["id"] == "rosie":
				await _rest_at_diner()
			mode = Mode.WALK
			return
	var text := map.sign_at(front)
	if text:
		mode = Mode.BUSY
		await dialog.say([text])
		mode = Mode.WALK


## The healing-centre ritual: a booth, a slice of pie, a short fade. Animals
## have nothing to heal yet (no stamina or tilt between matches), so for now
## it's the reassurance of the ritual, a save, and the diner as the place a
## blackout wakes you.
func _rest_at_diner() -> void:
	var pick := await menu.choose("What'll it be, hon?", ["Rest in a booth", "A table lesson", "Nothing"], 2)
	if pick == 1:
		await _play_tutorial()
		return
	if pick != 0:
		return
	await _fade_out(0.4)
	await get_tree().create_timer(0.6).timeout
	Game.save()
	await _fade_in(0.4)
	await dialog.say(["There. Pie all round. Your crew is fed, rested and itching to play."], "Rosie")


func _intro() -> void:
	var names: Array[String] = []
	for a in state.party_animals():
		names.append("%s the %s" % [a.name, Species.get_info(a.species)["display"]])
	await dialog.say([
		"Morning, Mossbank! Your crew: %s. They've practised all week." % " and ".join(names),
		"Tonight is the Mossbank Open, at the Tournament Hall, east along Ridge Road.",
		"Rival crews wait on the road. Step into their sight and they'll deal you in.",
		"Walk: arrows, WASD, D-pad or stick. Talk: A, Enter or Space. Menu: Start or Tab.",
	])


func _crew_title(crew: Dictionary) -> String:
	var nodes: Array = crew_nodes.get(crew["id"], [])
	var leader := WorldMap.crew_animals(crew)[0]
	var title: String = str(crew["name"])
	title = title.substr(0, 1).to_upper() + title.substr(1)
	if nodes and nodes[0] != null:
		return "%s, of %s" % [leader.name, crew["name"]]
	return title


## Start: a small menu in the corner, as on a handheld. It stays open until
## Close (or B, or Start again), so you can seat your crew and then save.
func _open_start_menu() -> void:
	mode = Mode.BUSY
	var pick := 0
	while true:
		pick = await menu.choose("", ["Crew", "Binder", "Save", "Options", "Close"], 4, true, pick)
		if pick == 0:
			await party_screen.open(state)
			_make_followers(player.cell, player.facing)
		elif pick == 1:
			await _open_binder()
		elif pick == 2:
			Game.save()
			await dialog.say(["Saved! (The game also saves itself at every door and after every match.)"])
		elif pick == 3:
			await options_screen.open(Game.settings)
		else:
			break
	Game.save()
	mode = Mode.WALK


## The Binder screen is made on first use, beside the other screens and
## under the fade (made here rather than in _build to keep it in one place).
func _open_binder() -> void:
	var ui := party_screen.get_parent()
	var binder := ui.get_node_or_null("BinderScreen") as BinderScreen
	if binder == null:
		binder = BinderScreen.new()
		binder.name = "BinderScreen"
		ui.add_child(binder)
		ui.move_child(binder, fade.get_index())
	await binder.open(state)


func _open_party() -> void:
	mode = Mode.BUSY
	await party_screen.open(state)
	_make_followers(player.cell, player.facing)
	Game.save()
	mode = Mode.WALK


# --- Rosie's table lessons --------------------------------------------------

## Asked once, at the end of a new game's intro. Scripted --auto runs skip it
## unless --tutorial asks for it, so they don't sit down at a table nobody
## is playing.
func _offer_tutorial() -> void:
	if state.tutorial_offered or (Game.dev_auto and not Game.dev_args.has("tutorial")):
		return
	state.tutorial_offered = true
	await dialog.say([
		"Yoo-hoo! Over here, hon! Rosie, from the diner.",
		"New to the tables? I'll show you how they work. Five minutes, pie after."], "Rosie")
	var pick := await menu.choose("Take Rosie's table lesson?", ["Yes, show me", "No thanks"], 1)
	if pick == 0:
		await _play_tutorial()
	else:
		await dialog.say(["Suit yourself, hon. I'm at the diner whenever you want a lesson."], "Rosie")


## The lessons at the embedded table, with your seated crew. Like
## _play_match, minus the stakes: no money, no blackout, and skipping (Start)
## just brings you back.
func _play_tutorial() -> void:
	state.tutorial_offered = true
	var lessons := TableTutorial.new()
	await _fade_out(0.2)
	if Game.dev("match-result"):  # scripted runs that skip tables skip this one too
		lessons.completed = Game.dev("match-result") == "win"
		await get_tree().create_timer(0.4).timeout
		await _fade_in(0.2)
	else:
		table = TABLE_SCENE.instantiate()
		table.tutorial = lessons
		table.setup = TutorialScript.setup_for(state.party_animals())
		table.starting_chips = TutorialScript.CHIPS
		table.embedded = true
		table.finished.connect(_on_table_finished)
		mode = Mode.TABLE
		_hud.queue_redraw()
		table_layer.add_child(table)
		fade.color.a = 0.0
		await _table_done
		mode = Mode.BUSY
	state.tutorial_done = state.tutorial_done or lessons.completed
	Game.save()
	Game.dev_log("tutorial: %s" % ("finished" if lessons.completed else "skipped"))
	if lessons.completed:
		await dialog.say(["Look at you, hon! A natural. Mostly.", "Come by for pie, win or lose. Or another lesson."], "Rosie")
	else:
		await dialog.say(["Fair enough, hon. I'm at the diner if you want another go."], "Rosie")


# --- Encounters -------------------------------------------------------------

func _encounter(crew: Dictionary, spotted: bool) -> void:
	mode = Mode.BUSY
	Game.dev_log("encounter: %s (%s)" % [crew["id"], "spotted you" if spotted else "you talked"])
	state.mark_crew_seen(WorldMap.crew_animals(crew), "%s, with %s" % [_area_name(), crew["name"]])  # the Binder
	# Whoever's still standing: a member you've recruited is gone from the
	# crew (its slot is null), and that may be the leader (playtester: a
	# null leader crashed here and softlocked).
	var members: Array = crew_nodes[crew["id"]].filter(func(m: Variant) -> bool: return m != null)
	if members.is_empty():
		mode = Mode.WALK
		return
	var leader: Critter = members[0]
	if spotted:
		leader.alert = true
		leader.queue_redraw()
		Sfx.play(&"encounter")
		await get_tree().create_timer(0.8).timeout
		leader.alert = false
		leader.queue_redraw()
		for cell in WorldMap.approach_path(leader.cell, leader.facing, player.cell):
			var trail: Array[Vector2i] = []
			for m: Critter in members:
				trail.append(m.cell)
			for i in range(1, members.size()):
				members[i].step_to(trail[i - 1])
			await leader.step_to(cell)
	# Face each other along the longer axis (talking to a shoulder member
	# leaves the leader off to one side).
	var gap := player.cell - leader.cell
	var toward := Vector2i(signi(gap.x), 0) if absi(gap.x) > absi(gap.y) else Vector2i(0, signi(gap.y))
	if toward == Vector2i.ZERO:
		toward = leader.facing
	leader.face(toward)
	player.face(-toward)
	state.facing = player.facing
	Sfx.voice(WorldMap.crew_animals(crew)[0].species)
	await dialog.say(crew["before"], _crew_title(crew))
	await _play_match(crew)
	mode = Mode.WALK


func _play_match(crew: Dictionary) -> void:
	_match_count += 1
	var rivals := WorldMap.crew_animals(crew)
	Game.save()
	var won := false
	var result := Game.dev("match-result")
	if result:
		await _fade_out(0.2)
		await get_tree().create_timer(0.4).timeout
		won = result == "win"
		await _fade_in(0.2)
	else:
		await _fade_out(0.2)
		table = TABLE_SCENE.instantiate()
		table.setup = state.table_setup(rivals, crew["id"])
		table.codebook = state.codebook  # interception: cracked codes carry over to rematches
		table.dealer_kind = crew["dealer"]
		table.starting_chips = int(Game.dev("chips", str(crew["chips"])))
		table.embedded = true
		# Road games are capped (the bigger stack wins at the cap): with the
		# table's real-time animations a full bust-out ran past three minutes
		# even at 60 chips, and road battles should take a minute or two.
		# Tournaments play to the end.
		table.max_hands = 0 if crew.has("bracelet") else ROAD_GAME_HANDS
		table.finished.connect(_on_table_finished)
		table.decided.connect(func(w: bool) -> void: _settle(crew, w))
		mode = Mode.TABLE
		_hud.queue_redraw()
		table_layer.add_child(table)
		fade.color.a = 0.0
		won = await _table_done
		mode = Mode.BUSY
	var outcome := _settle(crew, won)  # already settled when the table decided
	Game.dev_log("match against %s: %s" % [crew["id"], "won" if outcome["won"] else "lost"])
	if outcome["won"]:
		await _after_win(crew, outcome["reward"])
	else:
		await _blackout(crew, outcome["lost"])


## Applies a match's outcome to the run and saves it, once per match, the
## moment it's decided: the reward, the bracelet or an owed recruit offer,
## or the blackout; and bond growth. Everything after (leaving the table,
## the dialogue) only shows what's already saved. Before, quitting while the
## result was on screen (or during the dialogue after it) saved the state
## from before the match: a loss could be dodged by quitting (the
## playtester found it: tools/playtest.gd, seed 8002).
func _settle(crew: Dictionary, won: bool) -> Dictionary:
	if _settled.get("crew", "") == crew["id"] and _settled.get("match", -1) == _match_count:
		return _settled
	_settled = {"crew": crew["id"], "match": _match_count, "won": won, "reward": 0, "lost": 0}
	_grew = state.grow_bonds(won)
	if won:
		_settled["reward"] = state.win_against(crew["id"], crew["reward"])
		if crew.has("bracelet"):
			state.add_bracelet(crew["bracelet"])
		else:
			state.pending_recruit = crew["id"]
	else:
		_settled["lost"] = state.blackout()
	Game.save()
	return _settled


signal _table_done(won: bool)


## The table reports a finished match on the A press that dismisses it; the
## same press must not also reach the overworld (it'd talk to whoever is in
## front of you), so it's marked handled and the table freed next frame.
##
## The table stays in the tree until the end of the frame, and would emit
## again on a second A press in that frame, so it stops listening first.
func _on_table_finished(won: bool) -> void:
	get_viewport().set_input_as_handled()
	if table == null:
		return
	table.set_process_unhandled_input(false)
	table.finished.disconnect(_on_table_finished)
	table.queue_free()
	table = null
	await get_tree().process_frame
	_table_done.emit(won)


## In dev runs, --auto presses A when a real (--autoplay) match ends, so a
## scripted run gets back to the overworld.
func _physics_process(_delta: float) -> void:
	if table and Game.dev_auto and table.is_waiting_to_continue() and not table.has_meta("auto_pressed"):
		table.set_meta("auto_pressed", true)  # once: extra presses would skip the next dialog
		_press("ui_accept")


var _grew: Array[Animal] = []  ## whose bond grew in the last match


## "Sage's bond grew!" after a match, if anyone's did.
func _say_bond_growth() -> void:
	var lines := GameState.bond_news(_grew)
	_grew = []
	if lines:
		await dialog.say(lines)


## Shows a win that _settle has already saved (with the bracelet, or a
## pending recruit offer that's made again on the next load if the window
## closes first: closing mid-dialogue lost the offer in 136 of 200 playtest
## runs before, and once left a won Open without its bracelet).
func _after_win(crew: Dictionary, reward: int) -> void:
	var title := _crew_title(crew)
	await dialog.say(["You beat %s! They grumble and pay up: $%d." % [crew["name"], reward], crew["after"]], title)
	await _say_bond_growth()
	if crew.has("bracelet"):
		await dialog.say(["You won the Mossbank Open! The Regulars hand over the bracelet. Slowly."])
		await _show_demo_complete()
		return
	await _offer_recruit(crew)
	state.pending_recruit = ""
	Game.save()


func _show_demo_complete() -> void:
	await demo_complete.open(state, _road_crew_count())
	state.demo_complete_seen = true
	Game.save()


func _offer_recruit(crew: Dictionary) -> void:
	var animals := WorldMap.crew_animals(crew)
	var nodes: Array = crew_nodes[crew["id"]]
	var options: Array[String] = []
	var picks: Array[int] = []
	for i in animals.size():
		if nodes[i] == null:
			continue
		var a := animals[i]
		options.append("%s the %s (%s)" % [a.name, Species.get_info(a.species)["display"], PlayStyle.KIND_NAMES[a.style_kind()]])
		picks.append(i)
	options.append("Nobody, thanks")
	var pick := await menu.choose("Ask one of them to join your crew?", options, options.size() - 1)
	if pick >= picks.size():
		return
	var i := picks[pick]
	var a := animals[i]
	state.recruit(a)
	var node: Critter = nodes[i]
	nodes[i] = null
	node.queue_free()
	Sfx.play(&"win_pot")  # until there's a proper recruit jingle
	Sfx.voice(a.species)
	var hello := Bios.recruit_line(a.species, a.name)
	if hello:
		await dialog.say([hello], a.name)
	await dialog.say(["%s joins your crew! Pick who sits with you under Crew (Start or Tab)." % a.name])


## Shows a blackout that _settle has already applied and saved (closing the
## window during this dialogue used to skip it: 64 of 200 playtest runs).
func _blackout(crew: Dictionary, lost: int) -> void:
	await dialog.say(["%s cleaned you out." % _crew_title(crew), "You wander back toward town, pockets flapping, and everything goes dark..."])
	await _fade_out(0.6)
	_load_map(state.map_id, state.cell, state.facing)
	await get_tree().create_timer(0.4).timeout
	await _fade_in(0.6)
	await dialog.say([
		"Rough night, hon? You're at Rosie's. Your wallet's $%d lighter." % lost,
		"Your crew's had pie and a little cry. They're ready when you are."], "Rosie")
	await _say_bond_growth()


func _road_crew_count() -> int:
	var n := 0
	for map_id: String in WorldMap.ids():
		for c: Dictionary in WorldMap.get_map(map_id).crews:
			if not c.has("bracelet"):
				n += 1
	return n


# --- Scripted input (--walk) ------------------------------------------------

func _parse_walk(spec: String) -> void:
	var i := 0
	while i < spec.length():
		var kind := spec[i]
		i += 1
		var digits := ""
		while i < spec.length() and spec[i].is_valid_int():
			digits += spec[i]
			i += 1
		_script.append([kind.to_upper(), int(digits) if digits else 1])


## Non-movement script steps: A (confirm), M (menu), W (wait half a second).
func _run_script() -> void:
	if _script.is_empty() or _script[0][0] in ["U", "D", "L", "R"]:
		return
	var step: Array = _script.pop_front()
	match step[0]:
		"A":
			_press("ui_accept")
		"M":
			_press("menu")
		"W":
			mode = Mode.BUSY
			await get_tree().create_timer(0.5 * step[1]).timeout
			mode = Mode.WALK


func _press(action: String) -> void:
	var press := InputEventAction.new()
	press.action = action
	press.pressed = true
	Input.parse_input_event(press)
	var release := InputEventAction.new()
	release.action = action
	Input.parse_input_event.call_deferred(release)
