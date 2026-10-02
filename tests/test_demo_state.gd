extends TestCase
## Demo 2's rules of the run (docs/DEMO_SPEC.md, the S-* outcomes): a new
## game is the dog in Sootbridge with no crew and a deck missing its four
## Aces; cards and pickups are collected once each; the deck, the pickups
## and the opening's progress survive a save; saves from before the demo
## load as runs past the opening; and the open table's crew joins once.
##
## Written before the code (test first): every test here is red until the
## world and opening agent builds it, and listed in tests/expected_red.txt
## until then. Each test is named after its outcome's ID (S_DECK for
## S-DECK), so `-s tests/run_tests.gd -- S_DECK` runs just that outcome.

const SAVE := "user://test_demo_state.json"


func _aces() -> Array[int]:
	var out: Array[int] = []
	for c: String in GameState.OPENING_MISSING:
		out.append(Card.parse(c))
	return out


func _sorted(cards: Array) -> Array[int]:
	var out: Array[int] = []
	for c: int in cards:
		out.append(c)
	out.sort()
	return out


## Every pickup and every townsperson's gift on every map: [{map, id, card}].
func _all_pickups() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for map_id: String in WorldMap.ids():
		var m := WorldMap.get_map(map_id)
		for p: Dictionary in m.pickups():
			out.append({"map": map_id, "id": str(p.get("id", "")), "card": int(p.get("card", -1))})
		for n: Dictionary in m.npcs:
			if n.has("gives_card"):
				var g: Dictionary = n["gives_card"]
				out.append({"map": map_id, "id": str(g.get("id", "")), "card": int(g.get("card", -1))})
	return out


## S-NEW: a new game is the dog at Sootbridge's start cell, nobody with it,
## STARTING_MONEY, a deck of 48 (every card but the four Aces), and the
## opening not done.
func test_S_NEW_fresh_game_is_the_dog_alone_in_sootbridge() -> void:
	var s := GameState.fresh()
	check_eq(WorldMap.START_MAP, "sootbridge", "S-NEW: WorldMap.START_MAP")
	check_eq(s.map_id, "sootbridge", "S-NEW: a new game's map")
	check_eq(s.cell, WorldMap.START_CELL, "S-NEW: a new game's cell")
	check_eq(s.roster.size(), 0, "S-NEW: roster size (the dog has no crew)")
	check_eq(s.party.size(), 0, "S-NEW: party size")
	check_eq(s.money, GameState.STARTING_MONEY, "S-NEW: money")
	check_eq(s.deck.size(), 48, "S-NEW: deck size")
	var want: Array[int] = []
	for c in 52:
		if not _aces().has(c):
			want.append(c)
	check_eq(_sorted(s.deck), want, "S-NEW: the deck is every card but the four Aces:")
	check(not s.opening_done, "S-NEW: opening_done is false")
	check(not s.met_open_table, "S-NEW: met_open_table is false")
	check(s.taken_pickups.is_empty(), "S-NEW: no pickups taken")
	check(not s.has_full_deck(), "S-NEW: the deck isn't full")


## S-DECK: collect_card adds a missing card once (true) and refuses one
## already held (false); has_full_deck is true exactly at 52;
## missing_cards lists what's missing.
func test_S_DECK_collect_adds_once_and_completes_at_52() -> void:
	var s := GameState.fresh()
	var aces := _aces()
	check_eq(_sorted(s.missing_cards()), _sorted(aces), "S-DECK: missing_cards() of a new game is the four Aces:")
	check(not s.collect_card(Card.parse("Kd")), "S-DECK: collect_card(Kd) is refused: already held")
	check_eq(s.deck.size(), 48, "S-DECK: refusing a held card leaves the deck at")
	check(s.collect_card(aces[0]), "S-DECK: collect_card(As) adds a missing Ace")
	check(not s.collect_card(aces[0]), "S-DECK: collect_card(As) again is refused")
	check_eq(s.deck.size(), 49, "S-DECK: one Ace added once: deck size")
	check_eq(_sorted(s.missing_cards()), _sorted(aces.slice(1)), "S-DECK: missing after the Ace of Spades:")
	check(not s.has_full_deck(), "S-DECK: 49 cards isn't a full deck")
	check(s.collect_card(aces[1]) and s.collect_card(aces[2]), "S-DECK: two more Aces added")
	check(not s.has_full_deck(), "S-DECK: 51 cards isn't a full deck")
	check(s.collect_card(aces[3]), "S-DECK: the last Ace added")
	check(s.has_full_deck(), "S-DECK: 52 cards is a full deck")
	check_eq(s.deck.size(), 52, "S-DECK: full deck size")
	check_eq(s.missing_cards().size(), 0, "S-DECK: nothing missing at 52:")


## S-PICK: every pickup (and the townsperson's Ace) has an id, unique
## across the maps; take_pickup(id) gives its card once and records the id;
## again gives -1 and changes nothing; an unknown id gives -1.
func test_S_PICK_each_pickup_gives_its_card_once() -> void:
	var all := _all_pickups()
	if not check(all.size() >= 4, "S-PICK: the maps hold the four Aces as pickups and a gift (found %d)" % all.size()):
		return
	var ids := {}
	for p in all:
		check(p["id"] != "", "S-PICK: a pickup on %s has no id" % p["map"])
		check(not ids.has(p["id"]), "S-PICK: pickup id %s used twice" % p["id"])
		ids[p["id"]] = true
		var s := GameState.fresh()
		var before := s.deck.size()
		check_eq(s.take_pickup(p["id"]), p["card"], "S-PICK: take_pickup(%s) gives" % p["id"])
		check(s.taken_pickups.has(p["id"]), "S-PICK: %s recorded as taken" % p["id"])
		check(s.deck.has(p["card"]), "S-PICK: %s's card is in the deck" % p["id"])
		check_eq(s.take_pickup(p["id"]), -1, "S-PICK: take_pickup(%s) twice gives" % p["id"])
		check_eq(s.deck.size(), before + 1, "S-PICK: %s adds one card, once: deck size" % p["id"])
	check_eq(GameState.fresh().take_pickup("no_such_pickup"), -1, "S-PICK: an unknown id gives")


## S-SAVE: the deck, the taken pickups, opening_done and met_open_table
## come back from a save exactly.
func test_S_SAVE_deck_pickups_and_progress_round_trip() -> void:
	var s := GameState.fresh()
	# The whole deck in an odd order (it must come back as it went), the
	# four Aces' pickups taken. (Until demo 2.1 this was six made-up cards
	# and two made-up pickups; since B-DECKFIX a load repairs the deck to
	# the rules, so the round trip is of a deck the rules allow.)
	var deck: Array[int] = []
	for k in GameState.DECK_SIZE:
		deck.append((k * 19 + 7) % GameState.DECK_SIZE)
	s.deck = deck
	for id: String in GameState.opening_pickups():
		s.taken_pickups[id] = true
	s.opening_done = true
	s.met_open_table = true
	check_eq(SaveFile.write(s, SAVE), OK, "S-SAVE: the save writes")
	var back := SaveFile.read(SAVE)
	SaveFile.erase(SAVE)
	if not check(back != null, "S-SAVE: the save reads back"):
		return
	check_eq(back.deck, deck, "S-SAVE: deck")
	check_eq(back.taken_pickups, s.taken_pickups, "S-SAVE: taken_pickups")
	check(back.opening_done, "S-SAVE: opening_done survives")
	check(back.met_open_table, "S-SAVE: met_open_table survives")
	# And the other way round: a run at the very start stays at the start.
	var start := GameState.fresh()
	var again := GameState.from_dict(JSON.parse_string(JSON.stringify(start.to_dict())))
	check_eq(again.deck.size(), 48, "S-SAVE: a new game's deck after a round trip: size")
	check(not again.opening_done, "S-SAVE: a new game's opening_done stays false")
	check(not again.met_open_table, "S-SAVE: met_open_table stays false")


## S-OLD: a save from before this demo (no deck fields) loads past the
## opening: a full deck, opening_done, its roster, party and position kept.
func test_S_OLD_pre_demo_save_loads_past_the_opening() -> void:
	# A demo-1 save, as its to_dict() wrote it (the starters and a recruit,
	# on Ridge Road).
	var old := {
		"version": 1,
		"roster": [{"species": "owl", "name": "Sage", "bond": 0.55}, {"species": "raccoon", "name": "Bandit", "bond": 0.5},
			{"species": "cat", "name": "Whiskers", "bond": 0.2}],
		"party": [0, 2], "money": 345, "bracelets": [], "beaten": ["alley_cats"],
		"map": "town", "cell": [40, 11], "facing": [1, 0], "heal_map": "diner", "heal_cell": [5, 3],
		"tutorial_offered": true, "tutorial_done": false, "seen_intro": true,
		"seen": {"owl": ["Sage"], "raccoon": ["Bandit"], "cat": ["Duchess", "Whiskers"]},
		"recruited": {"owl": ["Sage"], "raccoon": ["Bandit"], "cat": ["Whiskers"]},
		"found_at": {}, "pending_recruit": "", "demo_complete_seen": false,
	}
	var s := GameState.from_dict(JSON.parse_string(JSON.stringify(old)))
	if not check(s != null, "S-OLD: an old save still loads"):
		return
	check(s.has_full_deck(), "S-OLD: an old save has a full deck")
	check_eq(s.deck.size(), 52, "S-OLD: deck size")
	check(s.opening_done, "S-OLD: an old save is past the opening")
	var names: Array[String] = []
	for a in s.roster:
		names.append(a.name)
	check_eq(names, ["Sage", "Bandit", "Whiskers"] as Array[String], "S-OLD: roster kept")
	check_eq(s.party, [0, 2] as Array[int], "S-OLD: party kept")
	check_eq(s.map_id, "town", "S-OLD: map kept")
	check_eq(s.cell, Vector2i(40, 11), "S-OLD: cell kept")
	check_eq(s.money, 345, "S-OLD: money kept")


## S-JOIN: join_open_table_crew() adds Sage (owl) and Bandit (raccoon) to
## the roster and the party, once; a second call adds nobody.
func test_S_JOIN_open_table_crew_joins_once() -> void:
	var s := GameState.fresh()
	var joined := s.join_open_table_crew()
	var names: Array[String] = []
	for a in joined:
		names.append("%s:%s" % [a.species, a.name])
	check_eq(names, ["owl:Sage", "raccoon:Bandit"] as Array[String], "S-JOIN: who joined:")
	check(s.has_animal(&"owl", "Sage") and s.has_animal(&"raccoon", "Bandit"), "S-JOIN: Sage and Bandit are in the roster")
	check_eq(s.roster.size(), 2, "S-JOIN: roster size after joining")
	check_eq(s.party_animals().size(), 2, "S-JOIN: both sit with you: party size")
	check_eq(s.join_open_table_crew().size(), 0, "S-JOIN: a second call: joined")
	check_eq(s.roster.size(), 2, "S-JOIN: roster size after a second call")
	check_eq(s.party.size(), 2, "S-JOIN: party size after a second call")
