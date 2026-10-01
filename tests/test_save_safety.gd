extends TestCase
## Fixes for what tools/playtest.gd found when it quits and continues, kills
## the game mid-save and loads damaged saves (docs/PLAYTEST.md). Each test
## is the smallest case of a failure the playtester reported.

const SAVE := "user://test_save_safety.json"


func _town() -> WorldMap:
	return WorldMap.get_map("town")


## Found as: stand where a recruit stood (or where a crew stood before it
## walked over to you), quit, Continue: you were back outside your house.
func test_a_recruits_old_spot_is_somewhere_you_can_stand() -> void:
	var s := GameState.fresh()
	var honk := Species.individual(&"goose", 0)  # the Pond Hecklers' leader, at (44, 8)
	s.win_against("pond_hecklers", 0)
	s.recruit(honk)
	var taken := _town().standing_cells(s)
	check(not taken.has(Vector2i(44, 8)), "nobody stands on the recruit's spot")
	check(taken.has(Vector2i(43, 8)), "its crewmates still do")
	check_eq(_town().open_cell_near(Vector2i(44, 8), taken), Vector2i(44, 8), "you stay where you saved")


func test_standing_on_someone_moves_you_next_to_them_not_home() -> void:
	var s := GameState.fresh()
	var taken := _town().standing_cells(s)
	var cell := _town().open_cell_near(Vector2i(43, 8), taken)  # a Pond Heckler stands here
	check_eq(absi(cell.x - 43) + absi(cell.y - 8), 1, "the nearest free cell, not the start (got %s)" % cell)
	check(_town().tile_walkable(cell) and not taken.has(cell), "somewhere you can stand")


func test_a_wall_beside_the_garden_doesnt_shut_you_in_it() -> void:
	var town := _town()
	var taken := town.occupied_cells()
	check_eq(town.char_at(Vector2i(22, 17)), "F", "the fenced garden's west fence")
	var cell := town.open_cell_near(Vector2i(22, 17), taken)
	check(town.reachable(WorldMap.START_CELL, cell, taken), "%s can be walked out of" % cell)
	check_eq(town.open_cell_near(Vector2i(500, -3), taken).y >= 0, true, "off the map lands on it")
	check_eq(town.open_cell_near(WorldMap.START_CELL, taken), WorldMap.START_CELL, "a good cell is kept")
