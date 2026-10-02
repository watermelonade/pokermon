extends TestCase
## Fixes for what tools/playtest.gd found when it quits and continues, kills
## the game mid-save and loads damaged saves (docs/PLAYTEST.md). Each test
## is the smallest case of a failure the playtester reported.

const SAVE := "user://test_save_safety.json"

## A run past Mossbank's open table, where Sage and Bandit join: a new game
## no longer starts with them (docs/DEMO_SPEC.md, demo 2), and the rules
## tested here are about a run with its crew.
func _crewed() -> GameState:
	var s := GameState.fresh()
	s.join_open_table_crew()
	return s



func _town() -> WorldMap:
	return WorldMap.get_map("town")


## Found as: stand where a recruit stood (or where a crew stood before it
## walked over to you), quit, Continue: you were back outside your house.
func test_a_recruits_old_spot_is_somewhere_you_can_stand() -> void:
	var s := _crewed()
	var honk := Species.individual(&"goose", 0)  # the Pond Hecklers' leader, at (44, 8)
	s.win_against("pond_hecklers", 0)
	s.recruit(honk)
	var taken := _town().standing_cells(s)
	check(not taken.has(Vector2i(44, 8)), "nobody stands on the recruit's spot")
	check(taken.has(Vector2i(43, 8)), "its crewmates still do")
	check_eq(_town().open_cell_near(Vector2i(44, 8), taken), Vector2i(44, 8), "you stay where you saved")


func test_standing_on_someone_moves_you_next_to_them_not_home() -> void:
	var s := _crewed()
	var taken := _town().standing_cells(s)
	var cell := _town().open_cell_near(Vector2i(43, 8), taken)  # a Pond Heckler stands here
	check_eq(absi(cell.x - 43) + absi(cell.y - 8), 1, "the nearest free cell, not the start (got %s)" % cell)
	check(_town().tile_walkable(cell) and not taken.has(cell), "somewhere you can stand")


func test_a_wall_beside_the_garden_doesnt_shut_you_in_it() -> void:
	var town := _town()
	var taken := town.occupied_cells()
	check_eq(town.char_at(Vector2i(22, 17)), "F", "the fenced garden's west fence")
	var cell := town.open_cell_near(Vector2i(22, 17), taken)
	var home := Vector2i(17, 7)  # outside your old house (Mossbank's start before demo 2)
	check(town.reachable(home, cell, taken), "%s can be walked out of" % cell)
	check_eq(town.open_cell_near(Vector2i(500, -3), taken).y >= 0, true, "off the map lands on it")
	check_eq(town.open_cell_near(home, taken), home, "a good cell is kept")


## Found as: a damaged party seated one animal, and the next match was two
## against three.
func test_a_short_party_is_filled_on_load() -> void:
	var d := _crewed().to_dict()
	d["party"] = [1]
	check_eq(GameState.from_dict(d).party, [1, 0] as Array[int])
	d["party"] = "nonsense"
	check_eq(GameState.from_dict(d).party, [0, 1] as Array[int])


func test_a_roster_that_lost_its_animals_gets_the_starters_back() -> void:
	var d := _crewed().to_dict()
	d["roster"] = [{"species": "dragon", "name": "Smaug"}, {"species": "owl", "name": "Sage", "bond": 0.8}]
	d["party"] = [0, 1]
	var s := GameState.from_dict(d)
	check_eq(s.roster.size(), 2)
	check_eq(s.party.size(), GameState.PARTY_SIZE)
	check(is_equal_approx(s.roster[0].bond, 0.8), "the owl that survived keeps its bond")
	check(s.has_animal(&"raccoon", "Bandit"), "the raccoon is back")


func test_seats_follow_their_animals_past_dropped_ones() -> void:
	var d := _crewed().to_dict()
	d["roster"] = [{"species": "owl", "name": "Sage"}, {"species": "dragon", "name": "Smaug"},
		{"species": "raccoon", "name": "Bandit"}, {"species": "cat", "name": "Duchess"}]
	d["party"] = [3, 0]
	var s := GameState.from_dict(d)
	check_eq(s.party_animals()[0].name, "Duchess", "seat 1 is still the cat, not whoever moved up")
	check_eq(s.party_animals()[1].name, "Sage")


func test_an_animal_saved_twice_is_one_animal() -> void:
	var d := _crewed().to_dict()
	d["roster"] = [d["roster"][0], d["roster"][0], d["roster"][1]]
	d["party"] = [0, 1]
	var s := GameState.from_dict(d)
	check_eq(s.roster.size(), 2)
	check_eq(s.party, [0, 1] as Array[int], "the copy's seat goes to the next animal")


## Found as: the window closed during "You beat the Regulars!" saved them
## beaten without the bracelet, and they never play again.
func test_a_beaten_tournament_comes_with_its_bracelet() -> void:
	var d := _crewed().to_dict()
	d["beaten"] = ["mossbank_regulars"]
	d["bracelets"] = []
	check_eq(GameState.from_dict(d).bracelets, ["mossbank"] as Array[String])
	d["beaten"] = ["pond_hecklers"]
	check(GameState.from_dict(d).bracelets.is_empty(), "a road crew gives no bracelet")


func test_a_blackout_never_wakes_you_in_a_wall() -> void:
	var d := _crewed().to_dict()
	d["heal_cell"] = [99, 99]
	var s := GameState.from_dict(d)
	check_eq(s.heal_cell, WorldMap.HEAL_CELL)
	d["heal_cell"] = [0, 0]
	check_eq(GameState.from_dict(d).heal_cell, WorldMap.HEAL_CELL, "the diner's wall")


## Where renaming over a file isn't allowed, SaveFile.write removes the save
## first; a crash right then left only the complete .part, which nothing
## read.
func test_a_complete_part_file_is_read_when_the_save_is_gone() -> void:
	SaveFile.erase(SAVE)
	var s := _crewed()
	s.money = 777
	var f := FileAccess.open(SAVE + ".part", FileAccess.WRITE)
	f.store_string(JSON.stringify(s.to_dict()))
	f.close()
	var back := SaveFile.read(SAVE)
	check(back != null and back.money == 777, "the .part is the save")
	check(SaveFile.exists(SAVE), "so the title offers Continue")
	check_eq(SaveFile.write(s, SAVE), OK)
	check(not FileAccess.file_exists(SAVE + ".part"), "the next save tidies it away")
	SaveFile.erase(SAVE)


func test_a_part_file_cut_short_is_ignored() -> void:
	SaveFile.erase(SAVE)
	var s := _crewed()
	s.money = 5
	SaveFile.write(s, SAVE)
	var f := FileAccess.open(SAVE + ".part", FileAccess.WRITE)
	f.store_string(JSON.stringify(s.to_dict()).left(40))
	f.close()
	check_eq(SaveFile.read(SAVE).money, 5, "the save, not half a .part")
	DirAccess.remove_absolute(SAVE)
	check_eq(SaveFile.read(SAVE), null, "half a .part alone is no save")
	SaveFile.erase(SAVE)


## Demo 2: the dog has nobody until the open table, and a save from then
## must load that way. The starting pair coming back on load is for older
## saves and runs past the open table, not a dog alone (docs/DEMO_SPEC.md,
## "Starting a scene test part-way").
func test_a_dog_alone_loads_alone() -> void:
	var s := GameState.from_dict(JSON.parse_string(JSON.stringify(GameState.fresh().to_dict())))
	check_eq(s.roster.size(), 0, "roster")
	check_eq(s.party.size(), 0, "party")
	var d := _crewed().to_dict()
	d["roster"] = []
	check_eq(GameState.from_dict(d).roster.size(), 2, "past the open table, a lost roster gets Sage and Bandit back")


# --- B-DECKFIX (demo 2.1) --------------------------------------------------------

## The four Aces' pickup ids (ground and Mags's gift) -> card, from the maps.
func _ace_pickups() -> Dictionary:
	var out := {}
	var aces := GameState.opening_missing_cards()
	for map_id: String in WorldMap.MAPS:
		var data: Dictionary = WorldMap.MAPS[map_id]
		for p: Dictionary in data.get("pickups", []):
			if aces.has(int(p["card"])):
				out[p["id"]] = int(p["card"])
		for n: Dictionary in data["npcs"]:
			if n.has("gives_card") and aces.has(int(n["gives_card"]["card"])):
				out[n["gives_card"]["id"]] = int(n["gives_card"]["card"])
	return out


## The repaired deck's rules (docs/DEMO_SPEC.md B-DECKFIX): no duplicates,
## nothing that isn't a card, every card but the Aces held, and each Ace
## held exactly when its pickup is recorded as taken.
func _deck_is_whole_but_the_untaken_aces(s: GameState, what: String) -> bool:
	var ok := true
	var seen := {}
	for c in s.deck:
		ok = check(c >= 0 and c < GameState.DECK_SIZE, "B-DECKFIX: %s: %d isn't a card" % [what, c]) and ok
		ok = check(not seen.has(c), "B-DECKFIX: %s: %d held twice" % [what, c]) and ok
		seen[c] = true
	var aces := GameState.opening_missing_cards()
	for c in GameState.DECK_SIZE:
		if not aces.has(c):
			ok = check(seen.has(c), "B-DECKFIX: %s: the %s is missing (only Aces may be)" % [what, GameState.card_name(c)]) and ok
	var pickups := _ace_pickups()
	for id: String in pickups:
		var card: int = pickups[id]
		ok = check(s.taken_pickups.has(id) == seen.has(card), "B-DECKFIX: %s: %s is %s but the %s is %s" % [what, id,
			"taken" if s.taken_pickups.has(id) else "not taken", GameState.card_name(card), "held" if seen.has(card) else "not held"]) and ok
	return ok


## B-DECKFIX: loading a save repairs its deck. Duplicates and things that
## aren't cards are dropped, any card but an Ace that's missing is put
## back, and an Ace is held exactly when its pickup (or Mags's gift) is
## recorded as taken; a run past the opening holds all four (and so has
## them all taken). Found by the playtester: `[51, 51, 51, 0, 0]` loaded as
## a 2-card deck, and a run that lost cards could never pass the gate.
func test_B_DECKFIX_loading_repairs_a_damaged_deck() -> void:
	var pickups := _ace_pickups()
	if not check_eq(pickups.size(), 4, "B-DECKFIX: the maps have the four Aces' pickups:"):
		return
	var ids: Array = pickups.keys()
	ids.sort()
	# Mid-opening, in Sootbridge: two Aces found (the first two ids).
	var s := GameState.fresh()
	for id: String in ids.slice(0, 2):
		s.take_pickup(id)
	if not check_eq(s.deck.size(), 50, "B-DECKFIX: two Aces taken: deck size"):
		return
	var base: Dictionary = JSON.parse_string(JSON.stringify(s.to_dict()))  # as a file holds it
	var cases := {
		"dupes": [51, 51, 51, 0, 0],
		"out of range": (base["deck"] as Array) + [52, -1, 99, 3.5, "As"],
		"lost cards": (base["deck"] as Array).slice(10),
		"untaken Aces held": (base["deck"] as Array) + pickups.values(),
		"garbage": "fifty-two",
		"empty": [],
	}
	for what: String in cases:
		var d: Dictionary = base.duplicate(true)
		d["deck"] = cases[what]
		var back := GameState.from_dict(JSON.parse_string(JSON.stringify(d)))
		if not check(back != null, "B-DECKFIX: %s: the save loads" % what):
			continue
		if _deck_is_whole_but_the_untaken_aces(back, what):
			check_eq(back.deck.size(), 50, "B-DECKFIX: %s: 48 cards and the two Aces taken:" % what)
	# No deck at all in a new-format save: the same.
	var none: Dictionary = base.duplicate(true)
	none.erase("deck")
	none["version"] = GameState.VERSION
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(none)))
	if check(back != null, "B-DECKFIX: a save without its deck loads"):
		_deck_is_whole_but_the_untaken_aces(back, "no deck, past the opening")
	# Past the opening (the gate let you through with all 52): the deck is
	# whole whatever the file says, and the four pickups are taken. Even
	# when they weren't recorded (a pre-demo save's run saved since).
	var past := GameState.fresh()
	for id: String in ids:
		past.take_pickup(id)
	past.opening_done = true
	var damaged := past.to_dict()
	damaged["deck"] = [51, 51, 0]
	damaged["taken_pickups"] = []
	damaged["map"] = "town"
	damaged["cell"] = [40, 12]
	back = GameState.from_dict(JSON.parse_string(JSON.stringify(damaged)))
	if check(back != null, "B-DECKFIX: past the opening: the save loads"):
		_deck_is_whole_but_the_untaken_aces(back, "past the opening")
		check(back.has_full_deck(), "B-DECKFIX: past the opening the deck is whole: %d cards" % back.deck.size())
	# A good save is untouched: the repair changes nothing that's right.
	var good := GameState.from_dict(JSON.parse_string(JSON.stringify(base)))
	check_eq(good.to_dict(), GameState.from_dict(JSON.parse_string(JSON.stringify(good.to_dict()))).to_dict(), "B-DECKFIX: a good save round trips:")
	check_eq(good.deck, s.deck, "B-DECKFIX: a good save's deck, in its order:")
