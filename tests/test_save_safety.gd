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
