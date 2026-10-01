extends TestCase
## The run's rules (GameState) and saving (SaveFile): what a win pays, what
## a blackout costs, who can join, who sits at the table, and that a save
## comes back exactly as it went out.

const SAVE := "user://test_game_state.json"


func test_new_game_starts_in_town_with_two_animals_seated() -> void:
	var s := GameState.fresh()
	check_eq(s.roster.size(), 2)
	check_eq(s.party, [0, 1] as Array[int])
	check_eq(s.money, GameState.STARTING_MONEY)
	check_eq(s.map_id, "town")
	check(WorldMap.get_map(s.map_id).tile_walkable(s.cell), "the start cell is walkable")
	check(s.party_ready())


func test_table_setup_seats_you_first_and_alternates_teams() -> void:
	var s := GameState.fresh()
	var rivals: Array[Animal] = [Species.individual(&"goose", 0), Species.individual(&"cat", 0), Species.individual(&"squirrel", 0)]
	var seats := s.table_setup(rivals)
	check_eq(seats.size(), 6)
	check_eq(seats[0]["name"], "You")
	check_eq(seats[0]["animal"], null, "seat 0 is the human")
	for i in seats.size():
		check_eq(seats[i]["team"], i % 2, "seat %d's team" % i)
	check_eq(seats[1]["name"], "Honk")
	check_eq(seats[2]["animal"], s.roster[0], "your first seated animal sits in seat 2")
	check_eq(seats[4]["animal"], s.roster[1])


func test_table_setup_follows_the_party_not_the_roster() -> void:
	var s := GameState.fresh()
	s.recruit(Species.individual(&"cat", 1))
	s.toggle_party(0)  # stand the Owl up
	s.toggle_party(2)  # seat the Cat
	var seats := s.table_setup(WorldMap.crew_animals(WorldMap.get_map("town").crews[0]))
	check_eq(seats[2]["name"], "Bandit")
	check_eq(seats[4]["name"], "Whiskers")


func test_party_holds_two_and_must_be_full_to_close() -> void:
	var s := GameState.fresh()
	s.recruit(Species.individual(&"goose", 0))
	check(not s.toggle_party(2), "a full party refuses a third")
	check(s.toggle_party(0), "standing someone up")
	check(not s.party_ready(), "one seat empty")
	check(s.toggle_party(2))
	check(s.party_ready())
	check_eq(s.party_animals()[1].name, "Honk")
	check(not s.toggle_party(9), "no such animal")


func test_recruit_adds_each_individual_once() -> void:
	var s := GameState.fresh()
	check(s.recruit(Species.individual(&"goose", 0, 0.9)))
	check_eq(s.roster.size(), 3)
	check_eq(s.roster[2].bond, GameState.RECRUIT_BOND, "recruits start with a weak bond")
	check_eq(s.party.size(), 2, "a full party stays as it was")
	check(not s.recruit(Species.individual(&"goose", 0)), "Honk can't join twice")
	check(not s.recruit(Species.individual(&"owl", 0)), "Sage is already yours")
	check(s.recruit(Species.individual(&"goose", 1)), "a different goose is fine")


func test_winning_pays_and_marks_the_crew_beaten() -> void:
	var s := GameState.fresh()
	check_eq(s.win_against("pond_hecklers", 120), 120)
	check_eq(s.money, GameState.STARTING_MONEY + 120)
	check(s.is_beaten("pond_hecklers"))
	check(not s.is_beaten("nut_club"))
	var town := WorldMap.get_map("town")
	check(town.spotter(Vector2i(44, 12), s.beaten).is_empty(), "a beaten crew doesn't challenge again")


func test_blackout_halves_money_and_wakes_you_at_the_diner() -> void:
	var s := GameState.fresh()
	s.money = 301
	s.map_id = "town"
	s.cell = Vector2i(44, 12)
	check_eq(s.blackout(), 150)
	check_eq(s.money, 151, "the odd coin stays with you")
	check_eq(s.map_id, WorldMap.HEAL_MAP)
	check_eq(s.cell, WorldMap.HEAL_CELL)
	check(not s.is_beaten("pond_hecklers"), "the crew that beat you will deal you in again")
	s.money = 1
	check_eq(s.blackout(), 0)
	check_eq(s.money, 1)


func test_bracelets_are_counted_once() -> void:
	var s := GameState.fresh()
	s.add_bracelet("mossbank")
	s.add_bracelet("mossbank")
	check_eq(s.bracelets.size(), 1)


func test_save_round_trip() -> void:
	var s := GameState.fresh()
	s.recruit(Species.individual(&"cat", 1))
	s.toggle_party(0)
	s.toggle_party(2)
	s.roster[1].bond = 0.73
	s.money = 987
	s.win_against("alley_cats", 0)
	s.add_bracelet("mossbank")
	s.map_id = "hall"
	s.cell = Vector2i(9, 7)
	s.facing = Vector2i.UP
	s.seen_intro = true
	check_eq(SaveFile.write(s, SAVE), OK)
	var back := SaveFile.read(SAVE)
	SaveFile.erase(SAVE)
	if not check(back != null, "save reads back"):
		return
	check_eq(back.to_dict(), s.to_dict(), "everything comes back")
	check_eq(back.party_animals()[1].name, "Whiskers")
	check(is_equal_approx(back.roster[1].bond, 0.73), "bond survives JSON")
	check_eq(back.cell, Vector2i(9, 7))
	check(not FileAccess.file_exists(SAVE + ".part"), "no temp file left behind")


func test_saving_twice_replaces_the_save() -> void:
	var s := GameState.fresh()
	SaveFile.write(s, SAVE)
	s.money = 5
	SaveFile.write(s, SAVE)
	var back := SaveFile.read(SAVE)
	SaveFile.erase(SAVE)
	check(back != null and back.money == 5, "the second save wins")


func test_missing_or_broken_saves_read_as_none() -> void:
	SaveFile.erase(SAVE)
	check_eq(SaveFile.read(SAVE), null, "no save")
	check(not SaveFile.exists(SAVE))
	var f := FileAccess.open(SAVE, FileAccess.WRITE)
	f.store_string("{ not json")
	f.close()
	check_eq(SaveFile.read(SAVE), null, "garbage")
	SaveFile.erase(SAVE)


func test_damaged_save_data_is_repaired_not_crashed_on() -> void:
	var s := GameState.from_dict({
		"version": 1,
		"roster": [{"species": "owl", "name": "Sage"}, {"species": "dragon", "name": "Smaug"}, "junk", {"species": "cat", "name": "Tom", "bond": 0.4}],
		"party": [7, 1, 1],
		"money": -50,
	})
	if not check(s != null, "still loads"):
		return
	check_eq(s.roster.size(), 2, "unknown species dropped")
	check_eq(s.party, [0, 1] as Array[int], "bad, unknown and repeated seats dropped, the empty seats filled")
	check_eq(s.money, 0)
	check_eq(s.map_id, WorldMap.START_MAP)
	check_eq(GameState.from_dict({"hello": 1}), null, "not a save at all")
	var moved := GameState.from_dict({"version": 1, "roster": [], "map": "old_town", "cell": [3, 3], "heal_map": "old_inn"})
	check_eq(moved.map_id, WorldMap.START_MAP, "a map that no longer exists sends you to the start")
	check_eq(moved.cell, WorldMap.START_CELL)
	check_eq(moved.heal_map, WorldMap.HEAL_MAP)
