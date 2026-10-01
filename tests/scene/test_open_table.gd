extends SceneTestCase
## Demo 2's open table in Mossbank, played in the real game
## (docs/DEMO_SPEC.md G-SIT, G-LEAVE, G-CREW, G-ROSIE; and S-PARTY once
## more, in the overworld): sitting down for the buy-in, a cash game with
## the dog at seat 0, leaving with your stack, Sage and Bandit joining
## after the first sit, and Rosie's lessons offered at the diner door
## instead of in the intro.
##
## A bot plays your seat (Game.dev_args "autoplay", which the table reads
## as well as the command line). Each test starts as a run past the
## opening standing where the Mill Road comes into Mossbank
## (demo_state_at), written as the save and continued from the title.
##
## Written before the open table exists (test first): red until the
## open-table and world agents build it, listed in tests/expected_red.txt
## until then. Each test checks the table is on the map first.


## The first open-table player, or {} (failing `id`'s check).
func _player(id: String) -> Dictionary:
	var seated := open_table_npcs()
	if not check(not seated.is_empty(), "%s: Mossbank has an open table (town.open_tables() is empty)" % id):
		return {}
	if not check(mossbank_entry().x >= 0, "%s: the Mill Road comes into Mossbank" % id):
		return {}
	return seated[0]


## Continues a run past the opening at Mossbank's way in, with `money`.
func _at_mossbank(id: String, money := 500) -> bool:
	var s := demo_state_at("town", mossbank_entry())
	s.money = money
	if not check(await continue_from(s), "%s: continue at Mossbank" % id):
		return false
	return check(await advance(20.0, "cancel"), "%s: walking in Mossbank: %s" % [id, last_stop])


## Talks to the table's player and answers the seat offer with option
## `pick` (0 is yes). True once the question was asked and answered.
func _offer(id: String, npc: Dictionary, pick: int) -> bool:
	if not check(await talk_to(npc["id"]), "%s: talk to %s: %s" % [id, npc["id"], last_stop]):
		return false
	await advance(20.0, "stop")
	if not check(menu_open(), "%s: talking to %s offers a seat (no question asked; heard %s)" % [id, npc["id"], heard]):
		return false
	check_eq(menu_options().size(), 2, "%s: the seat offer is yes / no: %s options" % [id, menu_options()])
	return await choose_index(pick)


## G-SIT: talking to the open table's players offers a seat (yes / no);
## no changes nothing, yes takes the buy-in and opens the table in cash
## mode with you (the dog) at seat 0 and the table's players around it.
func test_G_SIT_seat_offered_buy_in_taken_cash_table_opens() -> void:
	var npc := _player("G-SIT")
	if npc.is_empty() or not await _at_mossbank("G-SIT"):
		return
	var t: Dictionary = npc["open_table"]
	var money := state().money
	if not await _offer("G-SIT", npc, 1):
		return
	await advance(20.0, "cancel")
	check(not at_table(), "G-SIT: no: no table")
	check_eq(state().money, money, "G-SIT: no: money unchanged:")
	if not await _offer("G-SIT", npc, 0):
		return
	if not check(await came_true(at_table, 10.0), "G-SIT: yes opens the table"):
		return
	check_eq(state().money, money - int(t["buy_in"]), "G-SIT: yes takes the $%d buy-in: money" % int(t["buy_in"]))
	check_eq(table().get("cash_game"), true, "G-SIT: the table is in cash mode: cash_game")
	var setup: Array = table().get("setup")
	if not check_eq(setup.size(), (t["players"] as Array).size() + 1, "G-SIT: seats at the table:"):
		return
	var you: Variant = setup[0].get("animal")
	check(you is Animal and (you as Animal).species == &"dog", "G-SIT: seat 0 is the dog (an Animal of species dog), got %s" % you)
	var want: Array[String] = []
	for p: Array in t["players"]:
		want.append(Species.individual(p[0], p[1]).name)
	var got: Array[String] = []
	for i in range(1, setup.size()):
		var a: Variant = setup[i].get("animal")
		got.append((a as Animal).name if a is Animal else "?")
	want.sort()
	got.sort()
	check_eq(got, want, "G-SIT: the table's players sit with you:")


## G-LEAVE: after a hand, Start (then A) leaves: the table closes, your
## stack is added to your money, and you're back where you stood.
func test_G_LEAVE_leave_after_a_hand_with_your_stack() -> void:
	var npc := _player("G-LEAVE")
	if npc.is_empty() or not await _at_mossbank("G-LEAVE"):
		return
	timeout_s = 600.0
	game.dev_args["autoplay"] = ""  # a bot plays your seat
	game.dev_args["seed"] = "7"  # the same deal and bots every run
	var buy_in := int(npc["open_table"]["buy_in"])
	var money := state().money
	if not await _offer("G-LEAVE", npc, 0):
		return
	var stood := player_cell()
	if not check(await came_true(at_table, 10.0), "G-LEAVE: the table opens"):
		return
	if not await wait_for_hand_done(1, 300.0):
		return
	var chips := await leave_table()
	if not check(chips >= 0, "G-LEAVE: Start after a hand leaves the table: " + last_stop):
		return
	await advance(60.0, "cancel")
	check_eq(state().money, money - buy_in + chips, "G-LEAVE: money = $%d - $%d buy-in + %d chips:" % [money, buy_in, chips])
	check_eq(map_id(), "town", "G-LEAVE: back on")
	check_eq(player_cell(), stood, "G-LEAVE: back where you stood:")


## G-CREW: after the first sit (win or lose) Sage and Bandit join: they
## follow you, the party screen lists them, and Ridge Road's first crew
## (the Pond Hecklers) now spots you.
func test_G_CREW_sage_and_bandit_join_after_the_first_sit() -> void:
	var npc := _player("G-CREW")
	if npc.is_empty() or not await _at_mossbank("G-CREW"):
		return
	timeout_s = 600.0
	game.dev_args["autoplay"] = ""  # a bot plays your seat
	game.dev_args["seed"] = "7"  # the same deal and bots every run
	if not await _offer("G-CREW", npc, 0):
		return
	if not check(await came_true(at_table, 10.0), "G-CREW: the table opens"):
		return
	if not await wait_for_hand_done(1, 300.0):
		return
	if not check(await leave_table() >= 0, "G-CREW: leave the table: " + last_stop):
		return
	await advance(60.0, "cancel")
	check(state().has_animal(&"owl", "Sage") and state().has_animal(&"raccoon", "Bandit"), "G-CREW: Sage and Bandit are in your roster")
	check(heard_line("Sage") and heard_line("Bandit"), "G-CREW: you're told who joined; heard %s" % [heard])
	check_eq(state().party_animals().size(), 2, "G-CREW: both sit with you: party size")
	var sprites: Array[String] = []
	for f: Object in overworld().get("followers"):
		sprites.append(str(f.get("sprite_id")))
	sprites.sort()
	check_eq(sprites, ["owl", "raccoon"] as Array[String], "G-CREW: following you:")
	# The party screen (Start, Crew) lists them.
	await press("menu")
	if check(await choose("Crew"), "G-CREW: Start opens the menu with Crew"):
		var ps: Control = overworld().get("party_screen")
		if check(await came_true(func() -> bool: return ps.visible, 3.0), "G-CREW: the party screen opens"):
			var names: Array[String] = []
			for a: Animal in (ps.get("state") as GameState).roster:
				names.append(a.name)
			check(names.has("Sage") and names.has("Bandit"), "G-CREW: the party screen lists Sage and Bandit: %s" % [names])
			await press("ui_cancel")
		await came_true(menu_open, 3.0)
		if menu_open():
			await choose("Close")
	if not check(await advance(10.0, "cancel"), "G-CREW: back to walking: " + last_stop):
		return
	# Now a crew deals you in: walk into the Pond Hecklers' sight.
	game.dev_args["match-result"] = "win"
	var town := current_map()
	var crew := town.crew_by_id("pond_hecklers")
	var sight := town.view_cells(crew["cell"], crew["facing"], crew["sight"], town.occupied_cells())
	await walk_to_any(sight, "town", 240.0)
	check(heard.has(str(crew["before"][0])), "G-CREW: with a crew, the Pond Hecklers spot you (stopped: %s)" % last_stop)
	if menu_open():
		await press("ui_cancel")  # the recruit offer: nobody, thanks


## G-ROSIE: Rosie's lessons aren't offered in the intro; they are the
## first time you walk into her diner, and only then.
func test_G_ROSIE_lessons_offered_at_the_diner_not_in_the_intro() -> void:
	if not check(await start_new_game(), "G-ROSIE: New game"):
		return
	await came_true(func() -> bool: return not heard.is_empty(), 5.0)
	await advance(60.0, "cancel")
	var offers := menus.filter(func(m: String) -> bool: return "lesson" in m.to_lower())
	check(offers.is_empty(), "G-ROSIE: the intro offers no lesson (it asked: %s)" % [offers])
	check(not state().tutorial_offered, "G-ROSIE: after the intro the lessons haven't been offered")
	# Walk into the diner, the first time.
	var door := {}
	for w: Dictionary in WorldMap.get_map("town").warps:
		if w["to"] == "diner":
			door = w
	if not check(not door.is_empty(), "G-ROSIE: Mossbank has the diner"):
		return
	var outside: Vector2i = door["cell"] + Vector2i.DOWN
	if not check(await goto_title() and await continue_from(demo_state_at("town", outside)) and await advance(20.0, "cancel"), "G-ROSIE: continue outside the diner: " + last_stop):
		return
	menus.clear()
	await walk_to(door["to_cell"], "diner", 30.0)
	await came_true(menu_open, 10.0)
	var asked := menus.filter(func(m: String) -> bool: return "lesson" in m.to_lower())
	if not check(asked.size() == 1, "G-ROSIE: walking into the diner the first time, Rosie offers her lessons (menus: %s)" % [menus]):
		return
	await press("ui_cancel")
	await advance(20.0, "cancel")
	check(state().tutorial_offered, "G-ROSIE: the offer is remembered")
	# Out and in again: no second offer.
	menus.clear()
	await walk_to(outside, "town", 30.0)
	await walk_to(door["to_cell"], "diner", 30.0)
	await frames(120)
	check(menus.filter(func(m: String) -> bool: return "lesson" in m.to_lower()).is_empty(), "G-ROSIE: the second time in, no offer (menus: %s)" % [menus])


## S-PARTY, in the game: a dog with no crew walks through the Pond
## Hecklers' line of sight and nobody deals it in.
func test_S_PARTY_in_game_a_dog_alone_is_never_spotted() -> void:
	var s := demo_state_at("town", Vector2i(40, 11))
	if not check(s.party.is_empty(), "S-PARTY: a run past the opening, before the open table, has nobody with you (party %s)" % [s.party]):
		return
	if not check(await continue_from(s) and await advance(20.0, "cancel"), "S-PARTY: continue on Ridge Road: " + last_stop):
		return
	game.dev_args["match-result"] = "win"
	var town := current_map()
	var crew := town.crew_by_id("pond_hecklers")
	var sight := town.view_cells(crew["cell"], crew["facing"], crew["sight"], town.occupied_cells())
	await walk_to_any(sight, "town", 60.0)
	await frames(60)
	check(not heard.has(str(crew["before"][0])), "S-PARTY: the Pond Hecklers dealt a dog alone in")
	check(not state().is_beaten("pond_hecklers"), "S-PARTY: no match was played")
