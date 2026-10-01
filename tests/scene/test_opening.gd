extends SceneTestCase
## Demo 2's opening, played in the real game (docs/DEMO_SPEC.md G-INTRO,
## G-ACE, G-GATE, G-ROAD): the intro, waking as the dog in Sootbridge,
## picking up the Aces, the gate out of town and the Mill Road to Mossbank.
## Everything goes in through the pad, as a player would: walking by held
## D-pad steps, talking and reading with A.
##
## Written before the opening exists (test first): red until the world and
## opening agent builds it, and listed in tests/expected_red.txt until
## then. Each test checks its precondition first (the intro ends in
## Sootbridge, the map exists), so today it fails on that check.


## A new game from the title, the intro read through with A: true once
## you're walking. (A menu in the intro is answered with B: today's intro
## ends with Rosie's offer, which G-ROSIE says shouldn't be there.)
func _new_game_to_walking(id: String) -> bool:
	if not check(await start_new_game(), "%s: New game reaches the overworld" % id):
		return false
	if not check(await came_true(func() -> bool: return not heard.is_empty(), 5.0), "%s: the intro says something" % id):
		return false
	return check(await advance(60.0, "cancel"), "%s: the intro plays out to walking: %s" % [id, last_stop])


## G-INTRO: a new game plays the intro (A moves it on), then you're the
## dog, walking in Sootbridge at its start cell, with nobody following.
func test_G_INTRO_new_game_wakes_as_the_dog_in_sootbridge() -> void:
	if not await _new_game_to_walking("G-INTRO"):
		return
	check(heard.size() >= 3, "G-INTRO: the intro is a few lines (heard %d: %s)" % [heard.size(), heard])
	check_eq(map_id(), "sootbridge", "G-INTRO: after the intro, the map")
	check_eq(player_cell(), WorldMap.START_CELL, "G-INTRO: standing at the start cell")
	check_eq(str(player().get("sprite_id")), "dog", "G-INTRO: the player's sprite")
	check_eq((overworld().get("followers") as Array).size(), 0, "G-INTRO: animals following you:")
	check_eq(state().party.size(), 0, "G-INTRO: the party's size")
	check_eq(state().deck.size(), 48, "G-INTRO: the deck's size")


## G-ACE: stepping onto a ground Ace takes it (a line names the card and
## how many are left, the deck grows by one, the pickup is gone and stays
## gone after save and continue); talking to the Ace-giver gives theirs,
## once.
func test_G_ACE_aces_are_picked_up_and_given_once() -> void:
	if not await _new_game_to_walking("G-ACE"):
		return
	if not check_eq(map_id(), "sootbridge", "G-ACE: walking in"):
		return
	var m := current_map()
	var dist := WorldPaths.distances(m, player_cell(), false)
	var ace := {}
	for p: Dictionary in m.pickups():
		if dist.has(p["cell"]) and (ace.is_empty() or int(dist[p["cell"]]) < int(dist[ace["cell"]])):
			ace = p
	if not check(not ace.is_empty(), "G-ACE: an Ace lies somewhere you can walk to on sootbridge"):
		return
	var card: int = ace["card"]
	var cell: Vector2i = ace["cell"]
	var deck := state().deck.size()
	var from := heard.size()
	if not check(await walk_to(cell), "G-ACE: walk onto the Ace at %s: %s" % [cell, last_stop]):
		return
	await advance(10.0)
	var said := " / ".join(heard.slice(from))
	var left := 0
	for c in aces():
		if not state().deck.has(c):
			left += 1
	check(card_name(card).to_lower() in said.to_lower(), "G-ACE: a line names the card (\"%s\"); heard: %s" % [card_name(card), said])
	check(str(left) in said, "G-ACE: a line says how many are left (%d); heard: %s" % [left, said])
	check_eq(state().deck.size(), deck + 1, "G-ACE: the deck after picking it up: size")
	check(state().deck.has(card), "G-ACE: the Ace is in the deck")
	check(state().taken_pickups.has(ace["id"]), "G-ACE: the pickup is recorded as taken")
	# Gone: step off and back on, nothing happens.
	if not await _step_off_and_back(cell, "G-ACE"):
		return
	check_eq(state().deck.size(), deck + 1, "G-ACE: stepping on the spot again: deck size")
	# Still gone after save, quit and continue.
	if not check(await save_quit_continue(), "G-ACE: save, quit, continue: " + last_stop):
		return
	check(state().taken_pickups.has(ace["id"]), "G-ACE: still taken after Continue")
	check_eq(state().deck.size(), deck + 1, "G-ACE: deck size after Continue")
	if not await _step_off_and_back(cell, "G-ACE (after Continue)"):
		return
	check_eq(state().deck.size(), deck + 1, "G-ACE: after Continue, the spot is empty: deck size")
	# The townsperson's Ace, once.
	var giver := {}
	var giver_map := ""
	for id: String in WorldPaths.maps_reached(WorldMap.START_MAP, WorldMap.START_CELL, false):
		for n: Dictionary in WorldMap.get_map(id).npcs:
			if n.has("gives_card"):
				giver = n
				giver_map = id
	if not check(not giver.is_empty(), "G-ACE: someone in Sootbridge gives an Ace"):
		return
	var gift: int = giver["gives_card"]["card"]
	if not check(await talk_to(giver["id"], giver_map), "G-ACE: talk to %s: %s" % [giver["id"], last_stop]):
		return
	await advance(20.0, "cancel")
	check(state().deck.has(gift), "G-ACE: %s gave the %s" % [giver["id"], card_name(gift)])
	check_eq(state().deck.size(), deck + 2, "G-ACE: deck size after the gift")
	if not check(await talk_to(giver["id"], giver_map), "G-ACE: talk to %s again: %s" % [giver["id"], last_stop]):
		return
	await advance(20.0, "cancel")
	check_eq(state().deck.size(), deck + 2, "G-ACE: talking again gives nothing more: deck size")


## Steps to a free neighbour of `cell` and back onto it; true if it got
## there, failing if stepping on gave a line again.
func _step_off_and_back(cell: Vector2i, id: String) -> bool:
	var m := current_map()
	var off := Vector2i(-999, -999)
	for d in DIRS:
		if WorldPaths.is_open(m, cell + d, false) and m.warp_at(cell + d).is_empty():
			off = cell + d
			break
	if not check(off.x > -999, "%s: somewhere to step off to" % id):
		return false
	if not check(await walk_to(off), "%s: step off: %s" % [id, last_stop]):
		return false
	var from := heard.size()
	if not check(await walk_to(cell), "%s: step back on: %s" % [id, last_stop]):
		return false
	await frames(30)
	return check_eq(heard.slice(from), [], "%s: lines when stepping on the empty spot:" % id)


## G-GATE: walking into the gate with Aces missing gives a line and leaves
## you on the Sootbridge side; with all four you walk through onto the Mill
## Road.
func test_G_GATE_shut_without_the_aces_open_with_them() -> void:
	if not await _new_game_to_walking("G-GATE"):
		return
	if not check_eq(map_id(), "sootbridge", "G-GATE: walking in"):
		return
	var data: Dictionary = WorldMap.MAPS.get("sootbridge", {})
	var gates: Array = data.get("gates", [])
	if not check(not gates.is_empty() and not (gates[0]["cells"] as Array).is_empty(), "G-GATE: sootbridge has a gate"):
		return
	var m := current_map()
	var dist := WorldPaths.distances(m, player_cell(), false)
	var stand := Vector2i(-999, -999)
	var dir := Vector2i.ZERO
	for g: Vector2i in gates[0]["cells"]:
		for d in DIRS:
			if dist.has(g - d):
				stand = g - d
				dir = d
	if not check(stand.x > -999, "G-GATE: the gate can be walked up to"):
		return
	if not check(await walk_to(stand), "G-GATE: walk up to the gate: " + last_stop):
		return
	var from := heard.size()
	await step(dir)
	await came_true(dialog_open, 3.0)
	await advance(10.0)
	check(str(gates[0]["text"]) in heard.slice(from), "G-GATE: walking into it says \"%s\"; heard %s" % [gates[0]["text"], heard.slice(from)])
	check_eq(map_id(), "sootbridge", "G-GATE: shut: still on")
	check_eq(player_cell(), stand, "G-GATE: shut: still standing at")
	for c in aces():
		state().collect_card(c)
	if not check(state().has_full_deck(), "G-GATE: all four Aces in the deck"):
		return
	var road := Vector2i(-1, -1)
	for w: Dictionary in m.warps:
		if w["to"] == "mill_road":
			road = w["to_cell"]
	if not check(road.x >= 0, "G-GATE: sootbridge leads to the Mill Road"):
		return
	check(await walk_to(road, "mill_road"), "G-GATE: with all four, through the gate onto the Mill Road: " + last_stop)
	check_eq(map_id(), "mill_road", "G-GATE: open: now on")


## G-ROAD: walking the Mill Road east arrives in Mossbank (town) on its
## west side.
func test_G_ROAD_mill_road_east_into_mossbank_west() -> void:
	if not check(WorldMap.MAPS.has("mill_road"), "G-ROAD: map mill_road exists"):
		return
	var road := WorldMap.get_map("mill_road")
	var start := Vector2i(-1, -1)
	if WorldMap.MAPS.has("sootbridge"):
		for w: Dictionary in WorldMap.get_map("sootbridge").warps:
			if w["to"] == "mill_road":
				start = w["to_cell"]
	var east := {}
	for w: Dictionary in road.warps:
		if w["to"] == "town":
			east = w
	if not check(start.x >= 0 and not east.is_empty(), "G-ROAD: the Mill Road runs from Sootbridge to Mossbank"):
		return
	check(east["cell"].x > road.width / 2, "G-ROAD: Mossbank is at the east end (way in at %s, map %d wide)" % [east["cell"], road.width])
	if not check(await continue_from(demo_state_at("mill_road", start)) and await advance(20.0, "cancel"), "G-ROAD: start on the Mill Road: " + last_stop):
		return
	if not check_eq(map_id(), "mill_road", "G-ROAD: starting on"):
		return
	check(await walk_to(east["to_cell"], "town"), "G-ROAD: walk east into Mossbank: " + last_stop)
	check_eq(map_id(), "town", "G-ROAD: arrived on")
	var town := WorldMap.get_map("town")
	check(player_cell().x < town.width / 4, "G-ROAD: arrived on Mossbank's west side (at %s, map %d wide)" % [player_cell(), town.width])
