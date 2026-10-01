extends SceneTestCase
## Demo 2 end to end (docs/DEMO_SPEC.md J-LOOP, J-OLD): from the title with
## no save, everything a player does to get from the night of the intro to
## a crew of three in Mossbank, by walking and pressing buttons; then that
## the demo after the open table (Ridge Road's crews) still pays and
## recruits as before.
##
## The longest test here: about a minute of game time on the overworld and
## three or more real hands at the table (a bot in your seat), which with
## --fixed-fps runs in seconds. tools/test.sh journey runs just this file.
##
## Written before the demo exists (test first): red until it's built, and
## listed in tests/expected_red.txt until then.


## J-LOOP: new game, the intro, all four Aces collected by walking and
## talking, through the gate, along the Mill Road to Mossbank, a seat at
## the open table for 3+ real hands, leave, Sage and Bandit join; then
## save, quit to the title, Continue: everything as it was. (No script
## errors anywhere: the runner fails any test that logs one.)
func test_J_LOOP_title_to_a_crew_in_mossbank_and_back() -> void:
	timeout_s = 1500.0
	if not check(await start_new_game(), "J-LOOP: New game reaches the overworld"):
		return
	await came_true(func() -> bool: return not heard.is_empty(), 5.0)
	if not check(await advance(60.0, "cancel"), "J-LOOP: the intro plays out to walking: " + last_stop):
		return
	if not check_eq(map_id(), "sootbridge", "J-LOOP: after the intro, the map"):
		return
	# The four Aces, nearest first, map by map.
	var region := WorldPaths.maps_reached(WorldMap.START_MAP, WorldMap.START_CELL, false)
	var grounds: Array = []  ## [map, pickup]
	var giver: Array = []  ## [map, npc]
	for id: String in region:
		for p: Dictionary in WorldMap.get_map(id).pickups():
			grounds.append([id, p])
		for n: Dictionary in WorldMap.get_map(id).npcs:
			if n.has("gives_card"):
				giver = [id, n]
	if not check(grounds.size() == 3 and not giver.is_empty(), "J-LOOP: three Aces lie in Sootbridge and one is given (found %d and %s)" % [grounds.size(), giver.size() > 0]):
		return
	for g: Array in grounds:
		var p: Dictionary = g[1]
		if not check(await walk_to(p["cell"], g[0], 240.0), "J-LOOP: walk to %s at %s %s: %s" % [p["id"], g[0], p["cell"], last_stop]):
			return
		await advance(20.0, "cancel")
		check(state().deck.has(int(p["card"])), "J-LOOP: picked up the %s" % card_name(p["card"]))
	if not check(await talk_to(giver[1]["id"], giver[0], 240.0), "J-LOOP: talk to %s: %s" % [giver[1]["id"], last_stop]):
		return
	await advance(20.0, "cancel")
	if not check(state().has_full_deck(), "J-LOOP: all four Aces: a full deck (missing %s)" % [state().missing_cards()]):
		return
	# Through the gate and along the Mill Road.
	var road := Vector2i(-1, -1)
	for w: Dictionary in WorldMap.get_map("sootbridge").warps:
		if w["to"] == "mill_road":
			road = w["to_cell"]
	if not check(await walk_to(road, "mill_road", 240.0), "J-LOOP: through the gate onto the Mill Road: " + last_stop):
		return
	if not check(await walk_to(mossbank_entry(), "town", 240.0), "J-LOOP: along the Mill Road to Mossbank: " + last_stop):
		return
	# A seat at the open table, a bot in your seat for 3+ hands.
	var seated := open_table_npcs()
	if not check(not seated.is_empty(), "J-LOOP: Mossbank has an open table"):
		return
	var npc: Dictionary = seated[0]
	var buy_in := int(npc["open_table"]["buy_in"])
	var money := state().money
	game.dev_args["autoplay"] = ""  # a bot plays your seat
	game.dev_args["seed"] = "7"  # the same deal and bots every run
	if not check(await talk_to(npc["id"]), "J-LOOP: talk to %s: %s" % [npc["id"], last_stop]):
		return
	await advance(20.0, "stop")
	if not check(menu_open() and await choose_index(0), "J-LOOP: take the seat offered (heard %s)" % [heard.slice(-3)]):
		return
	if not check(await came_true(at_table, 10.0), "J-LOOP: the table opens"):
		return
	if not await wait_for_hand_done(3, 900.0):
		return
	var chips := await leave_table()
	if not check(chips >= 0, "J-LOOP: leave after the third hand: " + last_stop):
		return
	game.dev_args.erase("autoplay")
	await advance(60.0, "cancel")
	check_eq(state().money, money - buy_in + chips, "J-LOOP: money = $%d - $%d + %d chips:" % [money, buy_in, chips])
	check(state().has_animal(&"owl", "Sage") and state().has_animal(&"raccoon", "Bandit"), "J-LOOP: Sage and Bandit joined")
	check_eq((overworld().get("followers") as Array).size(), 2, "J-LOOP: following you:")
	# Save, quit, Continue: everything as it was.
	var saved := state().to_dict()
	var cell := player_cell()
	if not check(await save_quit_continue(), "J-LOOP: save, quit and continue: " + last_stop):
		return
	check_eq(state().to_dict(), saved, "J-LOOP: the run after Continue:")
	check_eq(map_id(), "town", "J-LOOP: after Continue, on")
	check_eq(player_cell(), cell, "J-LOOP: after Continue, standing at")
	check_eq((overworld().get("followers") as Array).size(), 2, "J-LOOP: after Continue, following you:")


## J-OLD: past the open table the demo is as before: walking into the Pond
## Hecklers' sight deals you in, and a skipped match (match-result, as the
## --match-result flag) pays $120 and offers a recruit, who joins.
func test_J_OLD_ridge_road_still_pays_and_recruits() -> void:
	var s := demo_state_at("town", Vector2i(40, 11))
	s.met_open_table = true
	var joined := s.join_open_table_crew()
	if not check_eq(joined.size(), 2, "J-OLD: Sage and Bandit join at the open table: joined"):
		return
	if not check(await continue_from(s) and await advance(20.0, "cancel"), "J-OLD: continue on Ridge Road: " + last_stop):
		return
	game.dev_args["match-result"] = "win"
	var money := state().money
	var town := current_map()
	var crew := town.crew_by_id("pond_hecklers")
	var sight := town.view_cells(crew["cell"], crew["facing"], crew["sight"], town.occupied_cells())
	await walk_to_any(sight, "town", 60.0)
	if not check(heard.has(str(crew["before"][0])), "J-OLD: the Pond Hecklers deal you in (stopped: %s)" % last_stop):
		return
	if not check(await came_true(menu_open, 30.0) and await choose("Honk"), "J-OLD: the recruit offer, Honk picked (menus: %s)" % [menus]):
		return
	await advance(30.0, "cancel")
	check(state().is_beaten("pond_hecklers"), "J-OLD: the Pond Hecklers are beaten")
	check_eq(state().money, money + int(crew["reward"]), "J-OLD: the win pays: money")
	check(state().has_animal(&"goose", "Honk"), "J-OLD: Honk joined")
	check_eq(state().roster.size(), 3, "J-OLD: roster size")
	check_eq(state().party.size(), 2, "J-OLD: party size (full: Honk waits on the bench)")
