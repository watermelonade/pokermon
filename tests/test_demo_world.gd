extends TestCase
## Demo 2's world as data (docs/DEMO_SPEC.md, the W-* outcomes and S-PARTY):
## Sootbridge and the Mill Road exist and are well formed, the way from
## Sootbridge to Mossbank opens only with a full deck, the four Aces lie
## where each is found a different way, there are townsfolk who never block
## the way, and Mossbank has an open table you can walk up to.
##
## Reachability is computed here, from the map data (tests/world_paths.gd:
## a BFS over walkable cells and warps, with everyone standing where they
## stand at home), rather than asked of the game, so a later map edit that
## walls something off fails here, not in a playtest.
##
## Written before the maps (test first): red until the world and opening
## agent builds them, and listed in tests/expected_red.txt until then. The
## judgement calls (what counts as "in plain sight", "somewhere you go
## into", "off the obvious path", "new" townsfolk) are written down in
## docs/DEMO_SPEC.md under "Test decisions".

const WorldPaths := preload("res://tests/world_paths.gd")
const DIRS: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]


## The maps exist and the start is on Sootbridge: the guard every test here
## starts with, so a missing map fails a check instead of an assert.
func _have_maps(id: String) -> bool:
	var ok := check(WorldMap.MAPS.has("sootbridge"), "%s: map sootbridge exists" % id)
	ok = check(WorldMap.MAPS.has("mill_road"), "%s: map mill_road exists" % id) and ok
	ok = check(WorldMap.START_MAP == "sootbridge", "%s: the start map is sootbridge (WorldMap.START_MAP is %s)" % [id, WorldMap.START_MAP]) and ok
	return ok


func _aces() -> Array[int]:
	var out: Array[int] = []
	for c: String in GameState.OPENING_MISSING:
		out.append(Card.parse(c))
	return out


## Sootbridge: every map you can walk to from the start with the gate shut.
func _sootbridge_maps() -> Array:
	return WorldPaths.maps_reached(WorldMap.START_MAP, WorldMap.START_CELL, false)


## The way from the start: {map: {cell: steps}}.
func _reach(gate_open: bool, bodies := true, blocked := {}) -> Dictionary:
	return WorldPaths.reach(WorldMap.START_MAP, WorldMap.START_CELL, gate_open, bodies, blocked)


# --- W-MAPS -----------------------------------------------------------------

## W-MAPS: sootbridge and mill_road exist and pass the map checks: rows the
## same width and known tiles, everyone standing where they can stand, and
## every map's warps lead to a walkable cell on a map that exists.
func test_W_MAPS_new_maps_exist_and_are_well_formed() -> void:
	if not _have_maps("W-MAPS"):
		return
	for id: String in ["sootbridge", "mill_road"]:
		var m := WorldMap.get_map(id)
		check(m.outdoor, "W-MAPS: %s is outdoors" % id)
		for y in m.height:
			check_eq(m.rows[y].length(), m.width, "W-MAPS: %s row %d width" % [id, y])
			for x in m.rows[y].length():
				check(WorldMap.TILES.has(m.rows[y][x]), "W-MAPS: %s (%d,%d): unknown tile '%s'" % [id, x, y, m.rows[y][x]])
		var taken := {}
		for n: Dictionary in m.npcs:
			check(m.tile_walkable(n["cell"]), "W-MAPS: %s: %s stands in a wall" % [id, n["id"]])
			check(not taken.has(n["cell"]), "W-MAPS: %s: two people on %s" % [id, n["cell"]])
			check(m.warp_at(n["cell"]).is_empty(), "W-MAPS: %s: %s stands in a doorway" % [id, n["id"]])
			taken[n["cell"]] = true
		for c: Dictionary in m.crews:
			for cell in WorldMap.crew_cells(c):
				check(m.tile_walkable(cell) and not taken.has(cell), "W-MAPS: %s: %s can't stand at %s" % [id, c["id"], cell])
				taken[cell] = true
		check(not m.warps.is_empty(), "W-MAPS: %s has a way out" % id)
	for id: String in WorldMap.ids():
		var m := WorldMap.get_map(id)
		for w: Dictionary in m.warps:
			if not check(WorldMap.MAPS.has(w["to"]), "W-MAPS: %s: a warp at %s leads to unknown map %s" % [id, w["cell"], w["to"]]):
				continue
			var dest := WorldMap.get_map(w["to"])
			check(dest.tile_walkable(w["to_cell"]), "W-MAPS: %s -> %s: arrive on a walkable cell (%s)" % [id, w["to"], w["to_cell"]])
			check(dest.warp_at(w["to_cell"]).is_empty(), "W-MAPS: %s -> %s: arriving on a warp would bounce you back" % [id, w["to"]])
		for p: Dictionary in m.pickups():
			check(m.tile_walkable(p["cell"]), "W-MAPS: %s: pickup %s in a wall" % [id, p["id"]])
			check(m.warp_at(p["cell"]).is_empty(), "W-MAPS: %s: pickup %s in a doorway" % [id, p["id"]])
			check(not m.occupied_cells().has(p["cell"]), "W-MAPS: %s: someone stands on pickup %s" % [id, p["id"]])


# --- W-LINK -----------------------------------------------------------------

## W-LINK: from Sootbridge's start cell, Mossbank (`town`) can be walked to
## through warps and walkable cells when the gate is open, and not when
## it's shut (nor the Mill Road).
func test_W_LINK_mossbank_reachable_only_through_the_open_gate() -> void:
	if not _have_maps("W-LINK"):
		return
	var open := _reach(true)
	check(open.has("mill_road"), "W-LINK: the Mill Road can be reached with the gate open")
	check(open.has("town"), "W-LINK: Mossbank (town) can be reached with the gate open")
	var shut := _reach(false)
	check(not shut.has("mill_road"), "W-LINK: the Mill Road can't be reached with the gate shut")
	check(not shut.has("town"), "W-LINK: Mossbank can't be reached with the gate shut")
	check(not WorldPaths.gate_cells(WorldMap.get_map("sootbridge")).is_empty(), "W-LINK: sootbridge has gate cells to shut")


# --- W-ACES -----------------------------------------------------------------

## W-ACES: the four Aces are all in Sootbridge, three lying as pickups and
## one given by a townsperson, each reachable from the start without the
## gate; one within 10 steps of the start, one somewhere you go into (a
## building or a fenced yard), one off the obvious path (a dead end, or
## behind something: see "Test decisions").
func test_W_ACES_four_aces_found_four_ways_in_sootbridge() -> void:
	if not _have_maps("W-ACES"):
		return
	var region := _sootbridge_maps()
	check(not region.has("mill_road") and not region.has("town"), "W-ACES: Sootbridge (the maps before the gate) is closed off by the gate")
	var grounds: Array[Dictionary] = []  ## {map, id, cell, card}
	var gifts: Array[Dictionary] = []  ## {map, npc, card}
	for id: String in WorldMap.ids():
		var m := WorldMap.get_map(id)
		for p: Dictionary in m.pickups():
			check(region.has(id), "W-ACES: pickup %s is on %s, outside Sootbridge" % [p.get("id"), id])
			grounds.append({"map": id, "id": p.get("id"), "cell": p["cell"], "card": int(p["card"])})
		for n: Dictionary in m.npcs:
			if n.has("gives_card"):
				check(region.has(id), "W-ACES: %s gives a card on %s, outside Sootbridge" % [n["id"], id])
				gifts.append({"map": id, "npc": n, "card": int(n["gives_card"]["card"])})
	check_eq(grounds.size(), 3, "W-ACES: Aces lying on the ground")
	check_eq(gifts.size(), 1, "W-ACES: Aces given by a townsperson")
	var cards: Array[int] = []
	for p in grounds:
		cards.append(p["card"])
	for g in gifts:
		cards.append(g["card"])
	cards.sort()
	var want := _aces()
	want.sort()
	if not check_eq(cards, want, "W-ACES: the pickups and the gift are the four Aces, once each:"):
		return
	var reach := _reach(false)
	for p in grounds:
		check(reach.get(p["map"], {}).has(p["cell"]), "W-ACES: %s at %s %s can't be reached from the start" % [p["id"], p["map"], p["cell"]])
	for g in gifts:
		var m := WorldMap.get_map(g["map"])
		var spots := WorldPaths.talk_spots(m, g["npc"]["cell"])
		check(spots.any(func(c: Vector2i) -> bool: return reach.get(g["map"], {}).has(c)),
			"W-ACES: nobody can walk up to %s to be given the Ace" % g["npc"]["id"])
	# The three ground Aces, one each way: try every assignment.
	var kinds := ["plain", "inside", "off_path"]
	var fits := {}  ## pickup index -> {kind: true}
	for i in grounds.size():
		fits[i] = {}
		if _plain(grounds[i]):
			fits[i]["plain"] = true
		if _inside(grounds[i]):
			fits[i]["inside"] = true
		if _off_path(grounds[i]):
			fits[i]["off_path"] = true
	var found := false
	for order: Array in [[0, 1, 2], [0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0]]:
		var ok := true
		for k in 3:
			ok = ok and fits[order[k]].has(kinds[k])
		found = found or ok
	var report := []
	for i in grounds.size():
		report.append("%s %s: %s" % [grounds[i]["id"], grounds[i]["cell"], fits[i].keys()])
	check(found, "W-ACES: the ground Aces aren't one in plain sight, one inside, one off the path: %s" % ", ".join(report))


## Within 10 steps of the start, on the start map.
func _plain(p: Dictionary) -> bool:
	if p["map"] != WorldMap.START_MAP:
		return false
	var d := WorldPaths.distances(WorldMap.get_map(p["map"]), WorldMap.START_CELL, false)
	return d.has(p["cell"]) and d[p["cell"]] <= 10


## Indoors (a building), or in a fenced yard: one cell (its way in) cuts it
## off from the start, and the part cut off is at least 4 cells with a
## fence along it.
func _inside(p: Dictionary) -> bool:
	var m := WorldMap.get_map(p["map"])
	if not m.outdoor:
		return true
	if p["map"] != WorldMap.START_MAP:
		return false
	var cut := _cut_off_part(m, p["cell"])
	if cut.size() < 4:
		return false
	for c: Vector2i in cut:
		for d in DIRS:
			if m.char_at(c + d) == "F":
				return true
	return false


## At a dead end (one way in or out), or behind something: the walk there
## is at least 6 steps longer than the straight-line distance.
func _off_path(p: Dictionary) -> bool:
	var m := WorldMap.get_map(p["map"])
	if not m.outdoor or p["map"] != WorldMap.START_MAP:
		return false
	var cell: Vector2i = p["cell"]
	var ways := 0
	for d in DIRS:
		if WorldPaths.is_open(m, cell + d, false):
			ways += 1
	if ways == 1:
		return true
	var dist := WorldPaths.distances(m, WorldMap.START_CELL, false)
	if not dist.has(cell):
		return false
	var straight := absi(cell.x - WorldMap.START_CELL.x) + absi(cell.y - WorldMap.START_CELL.y)
	return int(dist[cell]) - straight >= 6


## The cells cut off from the start along with `cell` by blocking the one
## cell that does it (the yard's way in), or [] if no single cell does.
## Any such cell lies on every path, so only one shortest path's cells are
## tried.
func _cut_off_part(m: WorldMap, cell: Vector2i) -> Array:
	var dist := WorldPaths.distances(m, WorldMap.START_CELL, false)
	if not dist.has(cell):
		return []
	var path: Array[Vector2i] = []
	var c := cell
	while c != WorldMap.START_CELL:
		for d in DIRS:
			if dist.has(c + d) and int(dist[c + d]) == int(dist[c]) - 1:
				c = c + d
				break
		if c != WorldMap.START_CELL:
			path.append(c)
	var best: Array = []
	for choke in path:
		var blocked := {m.id: {choke: true}}
		var from_start := WorldPaths.distances(m, WorldMap.START_CELL, false, true, blocked)
		if from_start.has(cell):
			continue
		var part := WorldPaths.distances(m, cell, false, true, blocked).keys()
		if part.size() > best.size():
			best = part
	return best


# --- W-GATE -----------------------------------------------------------------

## W-GATE: Sootbridge's way out has a gate that requires a full deck and
## says why it's shut; gate_at() finds it on each of its cells (walkable
## tiles, refused by the overworld while the deck is short), and a short
## deck is refused by it while a full one passes.
func test_W_GATE_sootbridge_exit_needs_a_full_deck() -> void:
	if not _have_maps("W-GATE"):
		return
	var m := WorldMap.get_map("sootbridge")
	var data: Dictionary = WorldMap.MAPS.get(m.id, {})  # (not MAPS["sootbridge"]: a missing key in a const fails to compile)
	var gates: Array = data.get("gates", [])
	if not check(gates.size() >= 1, "W-GATE: sootbridge has a gate"):
		return
	for g: Dictionary in gates:
		check_eq(g.get("requires"), "full_deck", "W-GATE: the gate requires")
		check(str(g.get("text", "")).strip_edges() != "", "W-GATE: the gate has a line saying why it's shut")
		var cells: Array = g.get("cells", [])
		check(not cells.is_empty(), "W-GATE: the gate covers some cells")
		for c: Vector2i in cells:
			check(m.tile_walkable(c), "W-GATE: gate cell %s is a walkable tile" % c)
			check_eq(m.gate_at(c), g, "W-GATE: gate_at(%s)" % c)
	check_eq(m.gate_at(WorldMap.START_CELL), {}, "W-GATE: gate_at(the start cell)")
	# The rule it applies: the deck must be full.
	var s := GameState.fresh()
	check(not s.has_full_deck(), "W-GATE: a new game's 48 cards don't open it")
	for c in _aces():
		s.collect_card(c)
	check(s.has_full_deck(), "W-GATE: all 52 open it")


# --- W-NPCS -----------------------------------------------------------------

## W-NPCS: at least 4 townsfolk in Sootbridge (the Ace-giver counts), at
## least 2 on the Mill Road, at least 2 new ones in Mossbank (not the open
## table's players); each has a line; and no one of them stands where every
## route from the start to Mossbank must pass.
func test_W_NPCS_townsfolk_everywhere_none_in_the_way() -> void:
	if not _have_maps("W-NPCS"):
		return
	var region := _sootbridge_maps()
	var sootbridge: Array = []
	for id: String in region:
		sootbridge.append_array(WorldMap.get_map(id).npcs)
	check(sootbridge.size() >= 4, "W-NPCS: townsfolk in Sootbridge: %d (want 4+)" % sootbridge.size())
	var road: Array = WorldMap.get_map("mill_road").npcs
	check(road.size() >= 2, "W-NPCS: townsfolk on the Mill Road: %d (want 2+)" % road.size())
	var mossbank: Array = []
	for n: Dictionary in WorldMap.get_map("town").npcs:
		if not n["id"] in ["bertram", "kid"] and not n.has("open_table"):
			mossbank.append(n)
	check(mossbank.size() >= 2, "W-NPCS: new townsfolk in Mossbank: %d (want 2+)" % mossbank.size())
	var everyone: Array = []  ## [map id, npc]
	for id: String in region + ["mill_road", "town"]:
		for n: Dictionary in WorldMap.get_map(id).npcs:
			everyone.append([id, n])
	for e: Array in everyone:
		var n: Dictionary = e[1]
		var lines: Variant = n.get("lines", [])
		check(lines is Array and not (lines as Array).is_empty(), "W-NPCS: %s on %s has no lines" % [n["id"], e[0]])
		for l: Variant in lines if lines is Array else []:
			check(l is String and (l as String).strip_edges() != "", "W-NPCS: %s has an empty line" % n["id"])
	# Remove one townsperson's cell from the walkable set at a time.
	for e: Array in everyone:
		var blocked := {e[0]: {e[1]["cell"]: true}}
		check(_reach(true, false, blocked).has("town"), "W-NPCS: %s at %s %s stands where every route to Mossbank passes" % [e[1]["id"], e[0], e[1]["cell"]])


# --- W-TABLE ----------------------------------------------------------------

## W-TABLE: Mossbank has an open table: npc entries with `open_table` (id,
## buy-in, 2-5 players as [species, individual] with Sage and Bandit among
## them, a dealer kind), one entry per player, each standing beside the
## felt, and you can walk up to them from where the Mill Road comes in.
func test_W_TABLE_mossbank_open_table_reachable_from_the_mill_road() -> void:
	if not _have_maps("W-TABLE"):
		return
	var town := WorldMap.get_map("town")
	var seated := town.open_tables()
	if not check(not seated.is_empty(), "W-TABLE: Mossbank has an open table (town.open_tables() is empty)"):
		return
	var tables := {}  ## table id -> [npc entries]
	for n: Dictionary in seated:
		var t: Dictionary = n["open_table"]
		if not tables.has(t.get("id")):
			tables[t.get("id")] = []
		tables[t.get("id")].append(n)
	for table_id: Variant in tables:
		var entries: Array = tables[table_id]
		var t: Dictionary = entries[0]["open_table"]
		check(table_id is String and table_id != "", "W-TABLE: the table has an id")
		check(t.get("buy_in") is int and int(t.get("buy_in")) > 0, "W-TABLE: %s has a buy-in" % table_id)
		check(t.get("dealer") is int and Dealer.Kind.values().has(t.get("dealer")), "W-TABLE: %s has a dealer kind" % table_id)
		var players: Array = t.get("players", [])
		check(players.size() >= 2 and players.size() <= 5, "W-TABLE: %s seats 2-5 players (has %d)" % [table_id, players.size()])
		var who: Array[String] = []
		for p: Variant in players:
			if check(p is Array and p.size() == 2 and Species.CATALOG.has(StringName(str(p[0]))) and p[1] is int and p[1] >= 0 and p[1] < 4,
					"W-TABLE: %s: a player isn't [species, individual]: %s" % [table_id, p]):
				who.append(Species.individual(StringName(str(p[0])), p[1]).name)
		check(who.has("Sage") and who.has("Bandit"), "W-TABLE: Sage and Bandit play at %s (players: %s)" % [table_id, who])
		check_eq(entries.size(), players.size(), "W-TABLE: %s: npc entries standing at the table, one per player:" % table_id)
		for n: Dictionary in entries:
			check_eq(n["open_table"], t, "W-TABLE: %s carries the same table" % n["id"])
			var by_felt := false
			for d in DIRS:
				by_felt = by_felt or town.char_at(n["cell"] + d) == "t"
			check(by_felt, "W-TABLE: %s at %s doesn't stand beside the felt" % [n["id"], n["cell"]])
		# Walk up from where the Mill Road comes in.
		var entry := Vector2i(-1, -1)
		for w: Dictionary in WorldMap.get_map("mill_road").warps:
			if w["to"] == "town":
				entry = w["to_cell"]
		if not check(entry.x >= 0, "W-TABLE: the Mill Road leads into Mossbank"):
			return
		var dist := WorldPaths.distances(town, entry, true)
		var reachable := false
		for n: Dictionary in entries:
			for c in WorldPaths.talk_spots(town, n["cell"]):
				reachable = reachable or dist.has(c)
		check(reachable, "W-TABLE: nobody at %s can be walked up to from the Mill Road's way in (%s)" % [table_id, entry])


# --- S-PARTY ----------------------------------------------------------------

## S-PARTY: with an empty party a crew never spots you: the dog alone,
## standing in the Pond Hecklers' line of sight, isn't challenged; with
## anyone at its side, it is (spotter's party_size: see "Test decisions").
func test_S_PARTY_crews_never_spot_a_dog_alone() -> void:
	var town := WorldMap.get_map("town")
	var crew: Dictionary = town.crew_by_id("pond_hecklers")
	var sight := town.view_cells(crew["cell"], crew["facing"], crew["sight"], town.occupied_cells())
	if not check(not sight.is_empty(), "S-PARTY: the Pond Hecklers can see something"):
		return
	var cell: Vector2i = sight[sight.size() - 1]
	check_eq(town.spotter(cell, {}, 0).get("id", "nobody"), "nobody", "S-PARTY: an empty party in the Hecklers' sight is spotted by")
	check_eq(town.spotter(cell, {}, 1).get("id"), "pond_hecklers", "S-PARTY: one animal along: spotted by")
	check_eq(town.spotter(cell, {}).get("id"), "pond_hecklers", "S-PARTY: spotter's default (a full party): spotted by")


# --- W-STREET (demo 2.1) -------------------------------------------------------

## The street game's npc entries in Sootbridge (the maps reachable from the
## start with the gate shut): those whose `open_table` carries a "stake".
## [map id, npc entry] each.
func _street_players() -> Array:
	var out: Array = []
	for id: String in _sootbridge_maps():
		for n: Dictionary in WorldMap.get_map(id).npcs:
			if n.has("open_table") and (n["open_table"] as Dictionary).has("stake"):
				out.append([id, n])
	return out


## W-STREET: Sootbridge has a street table: npc entries with `open_table`
## carrying "stake" (chips fronted) and "max_money" (= the Mossbank open
## table's buy-in), one per player (2-5 of them, [species, individual]),
## each standing beside a crate or table, reachable from the start with
## the gate shut, and none of them in the way: with everyone standing and
## the gate open Mossbank is still reachable, and removing any one of them
## never matters (W-NPCS, which counts them too, still holds).
func test_W_STREET_sootbridge_has_a_street_game_for_empty_pockets() -> void:
	if not _have_maps("W-STREET"):
		return
	var found := _street_players()
	if not check(not found.is_empty(), "W-STREET: Sootbridge has a street game (no npc there has an open_table with a stake)"):
		return
	var mossbank := WorldMap.get_map("town").open_tables()
	if not check(not mossbank.is_empty(), "W-STREET: Mossbank has its open table (for max_money)"):
		return
	var buy_in := int(mossbank[0]["open_table"]["buy_in"])
	var tables := {}  ## table id -> [[map, npc]]
	for e: Array in found:
		var tid: Variant = (e[1]["open_table"] as Dictionary).get("id")
		if not tables.has(tid):
			tables[tid] = []
		tables[tid].append(e)
	var reach := _reach(false)
	for tid: Variant in tables:
		var entries: Array = tables[tid]
		var t: Dictionary = entries[0][1]["open_table"]
		check(tid is String and tid != "", "W-STREET: the street table has an id")
		check(t.get("stake") is int and int(t.get("stake")) > 0, "W-STREET: %s fronts a stake above 0 (%s)" % [tid, t.get("stake")])
		check_eq(t.get("max_money"), buy_in, "W-STREET: %s's max_money is the Mossbank buy-in:" % tid)
		check(t.get("dealer") is int and Dealer.Kind.values().has(t.get("dealer")), "W-STREET: %s has a dealer kind" % tid)
		var players: Array = t.get("players", [])
		check(players.size() >= 2 and players.size() <= 5, "W-STREET: %s seats 2-5 players (has %d)" % [tid, players.size()])
		for p: Variant in players:
			check(p is Array and p.size() == 2 and Species.CATALOG.has(StringName(str(p[0]))) and p[1] is int and p[1] >= 0 and p[1] < 4,
				"W-STREET: %s: a player isn't [species, individual]: %s" % [tid, p])
		check_eq(entries.size(), players.size(), "W-STREET: %s: npc entries standing at the table, one per player:" % tid)
		var walk_up := false
		for e: Array in entries:
			var m := WorldMap.get_map(e[0])
			var n: Dictionary = e[1]
			check_eq(n["open_table"], t, "W-STREET: %s carries the same table" % n["id"])
			var by_table := false
			for d in DIRS:
				by_table = by_table or m.char_at(n["cell"] + d) in ["x", "t"]
			check(by_table, "W-STREET: %s at %s doesn't stand beside a crate or table" % [n["id"], n["cell"]])
			var lines: Variant = n.get("lines", [])
			check(lines is Array and not (lines as Array).is_empty(), "W-STREET: %s has no lines" % n["id"])
			for c in WorldPaths.talk_spots(m, n["cell"]):
				walk_up = walk_up or reach.get(e[0], {}).has(c)
			var blocked := {e[0]: {n["cell"]: true}}
			check(_reach(true, false, blocked).has("town"), "W-STREET: %s at %s stands where every route to Mossbank passes" % [n["id"], n["cell"]])
		check(walk_up, "W-STREET: nobody at %s can be walked up to from the start with the gate shut" % tid)
	check(_reach(true).has("town"), "W-STREET: with everyone standing (the street game's players too), Mossbank is reachable")
