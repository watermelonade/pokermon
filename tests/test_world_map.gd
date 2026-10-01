extends TestCase
## The maps and encounters: every map is well formed, everyone stands
## somewhere they can stand, doors lead somewhere, crews see what they
## should, and the road can't be walked without meeting the crews meant to
## block it (but can, around the others).


func _town() -> WorldMap:
	return WorldMap.get_map("town")


func test_maps_are_rectangular_and_use_known_tiles() -> void:
	for id: String in WorldMap.ids():
		var m := WorldMap.get_map(id)
		for y in m.height:
			check_eq(m.rows[y].length(), m.width, "%s row %d width" % [id, y])
			for x in m.rows[y].length():
				check(WorldMap.TILES.has(m.rows[y][x]), "%s (%d,%d): unknown tile '%s'" % [id, x, y, m.rows[y][x]])


func test_edges_cant_be_walked_off() -> void:
	for id: String in WorldMap.ids():
		var m := WorldMap.get_map(id)
		for x in m.width:
			for y in [0, m.height - 1]:
				check(not m.tile_walkable(Vector2i(x, y)) or m.warp_at(Vector2i(x, y)), "%s edge (%d,%d) is open" % [id, x, y])
		for y in m.height:
			for x in [0, m.width - 1]:
				check(not m.tile_walkable(Vector2i(x, y)), "%s edge (%d,%d) is open" % [id, x, y])


func test_everyone_stands_on_walkable_free_cells() -> void:
	for id: String in WorldMap.ids():
		var m := WorldMap.get_map(id)
		var seen := {}
		for n: Dictionary in m.npcs:
			check(m.tile_walkable(n["cell"]), "%s: %s stands in a wall" % [id, n["id"]])
			check(not seen.has(n["cell"]), "%s: two people on one cell" % id)
			seen[n["cell"]] = true
		for c: Dictionary in m.crews:
			for cell in WorldMap.crew_cells(c):
				check(m.tile_walkable(cell), "%s: %s member in a wall at %s" % [id, c["id"], cell])
				check(not seen.has(cell), "%s: %s overlaps someone at %s" % [id, c["id"], cell])
				check(not m.warp_at(cell), "%s: %s stands in a doorway" % [id, c["id"]])
				seen[cell] = true


func test_doors_lead_somewhere_you_can_stand() -> void:
	for id: String in WorldMap.ids():
		var m := WorldMap.get_map(id)
		check(not m.warps.is_empty(), "%s has a way in or out" % id)
		for w: Dictionary in m.warps:
			check(m.tile_walkable(w["cell"]), "%s: door at %s is walkable" % [id, w["cell"]])
			if not check(WorldMap.MAPS.has(w["to"]), "%s: door to unknown map %s" % [id, w["to"]]):
				continue
			var dest := WorldMap.get_map(w["to"])
			check(dest.tile_walkable(w["to_cell"]), "%s -> %s: arrive on a walkable cell" % [id, w["to"]])
			check(dest.warp_at(w["to_cell"]).is_empty(), "%s -> %s: arriving on a door would bounce you back" % [id, w["to"]])
			check(not dest.occupied_cells().has(w["to_cell"]), "%s -> %s: someone's standing in the doorway" % [id, w["to"]])
	var start := WorldMap.get_map(WorldMap.START_MAP)
	check(start.tile_walkable(WorldMap.START_CELL) and not start.occupied_cells().has(WorldMap.START_CELL), "start cell")
	var heal := WorldMap.get_map(WorldMap.HEAL_MAP)
	check(heal.tile_walkable(WorldMap.HEAL_CELL) and not heal.occupied_cells().has(WorldMap.HEAL_CELL), "blackout cell")


## Road crews are three; a boss crew (the Open's) brings four to six.
func test_crews_are_three_distinct_animals_none_of_them_yours() -> void:
	var seen := {}
	for a in GameState.fresh().roster:
		seen[a.name] = "your crew"
	for id: String in WorldMap.ids():
		for c: Dictionary in WorldMap.get_map(id).crews:
			var animals := WorldMap.crew_animals(c)
			if c.get("boss", false):
				check(animals.size() >= 4 and animals.size() <= 6, "%s: a boss crew of %d" % [c["id"], animals.size()])
			else:
				check_eq(animals.size(), 3, "%s size" % c["id"])
			for a in animals:
				check(not seen.has(a.name), "%s: %s is already in %s" % [c["id"], a.name, seen.get(a.name)])
				seen[a.name] = c["id"]
			check(c["reward"] > 0, "%s pays" % c["id"])
			if c.has("bracelet"):
				check_eq(c["dealer"], Dealer.Kind.ASLEEP, "the starter town's tournament dealer is asleep")
			else:
				check_eq(c["dealer"], Dealer.Kind.STREET, "road games have no dealer")
				check(c["sight"] > 0, "%s can spot you" % c["id"])


func test_road_has_three_to_five_crews_and_a_tournament() -> void:
	var road := 0
	var tournaments := 0
	for id: String in WorldMap.ids():
		for c: Dictionary in WorldMap.get_map(id).crews:
			if c.has("bracelet"):
				tournaments += 1
			else:
				road += 1
	check(road >= 3 and road <= 5, "%d road crews" % road)
	check_eq(tournaments, 1)


func test_line_of_sight_runs_straight_and_stops_at_walls() -> void:
	var town := _town()
	var hecklers := town.crew_by_id("pond_hecklers")
	var view := town.view_cells(hecklers["cell"], hecklers["facing"], hecklers["sight"])
	check_eq(view, [Vector2i(44, 9), Vector2i(44, 10), Vector2i(44, 11), Vector2i(44, 12), Vector2i(44, 13), Vector2i(44, 14)] as Array[Vector2i])
	# Row 15 is trees: a longer sight still stops there.
	check_eq(town.view_cells(hecklers["cell"], Vector2i.DOWN, 20).size(), 6, "trees block the view")
	# Someone standing in the way blocks it too.
	check_eq(town.view_cells(hecklers["cell"], Vector2i.DOWN, 6, {Vector2i(44, 11): true}).size(), 2)
	check(town.view_cells(Vector2i(44, 8), Vector2i.UP, 5).is_empty(), "a tree right in front")


func test_spotted_only_in_front_of_the_leader() -> void:
	var town := _town()
	check_eq(town.spotter(Vector2i(44, 12), {}).get("id"), "pond_hecklers", "straight ahead")
	check(town.spotter(Vector2i(45, 12), {}).is_empty(), "one column over")
	check(town.spotter(Vector2i(30, 12), {}).is_empty(), "in town")
	check_eq(town.spotter(Vector2i(51, 7), {}).get("id"), "alley_cats", "on the path, in the cats' row")
	check(town.spotter(Vector2i(53, 7), {}).is_empty(), "past the cats' sight of 4")
	check_eq(town.spotter(Vector2i(60, 6), {}).get("id"), "nut_club")
	check_eq(town.spotter(Vector2i(78, 18), {}).get("id"), "night_shift")
	check(WorldMap.get_map("hall").spotter(Vector2i(9, 7), {}).is_empty(), "the Regulars wait to be talked to")


func test_spotting_crew_walks_up_to_stand_next_to_you() -> void:
	check_eq(WorldMap.approach_path(Vector2i(44, 8), Vector2i.DOWN, Vector2i(44, 12)),
		[Vector2i(44, 9), Vector2i(44, 10), Vector2i(44, 11)] as Array[Vector2i])
	check_eq(WorldMap.approach_path(Vector2i(48, 7), Vector2i.RIGHT, Vector2i(52, 7)).back(), Vector2i(51, 7))
	check(WorldMap.approach_path(Vector2i(44, 8), Vector2i.DOWN, Vector2i(44, 9)).is_empty(), "already face to face")


func _hall_door() -> Vector2i:
	for w: Dictionary in _town().warps:
		if w["to"] == "hall":
			return w["cell"]
	return Vector2i(-1, -1)


func _blocked(crew_ids: Array) -> Dictionary:
	var town := _town()
	var blocked := town.occupied_cells()
	for id: String in crew_ids:
		var c := town.crew_by_id(id)
		for cell in town.view_cells(c["cell"], c["facing"], c["sight"], town.occupied_cells()):
			blocked[cell] = true
	return blocked


func test_the_road_to_the_hall_is_open_once_crews_are_beaten() -> void:
	check(_town().reachable(WorldMap.START_CELL, _hall_door(), _town().occupied_cells()),
		"beaten crews standing at home don't block the road")


func test_some_crews_cant_be_snuck_past() -> void:
	var town := _town()
	check(not town.reachable(WorldMap.START_CELL, _hall_door(), _blocked(["pond_hecklers"])), "the Pond Hecklers block the road")
	check(not town.reachable(WorldMap.START_CELL, _hall_door(), _blocked(["nut_club"])), "the Nut Club blocks the road")
	check(town.reachable(WorldMap.START_CELL, _hall_door(), _blocked(["alley_cats", "night_shift"])),
		"the Alley Cats and the Night Shift can be avoided")
