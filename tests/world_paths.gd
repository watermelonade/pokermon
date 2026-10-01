extends RefCounted
## Walking the maps as data, for the tests: where you can get to from a cell,
## across doors and map edges (warps), with Sootbridge's gate shut or open.
## The W-* tests (tests/test_demo_world.gd) compute reachability with it
## themselves instead of trusting the maps' own queries, so a map edit that
## walls something off fails a test; the scene tests (SceneTestCase) plan
## their walks with it.
##
## Preloaded, not a class_name: it's test code, and the game shouldn't see it.
##
## A cell is open when its tile is walkable, nobody stands on it at home
## (WorldMap.occupied_cells: townsfolk and crews; switch off with
## `bodies = false`), it's not in `blocked` ({map id: {cell: true}}) and it's
## not a gate cell while the gate is shut (gate cells are walkable tiles that
## the overworld refuses to let you onto while your deck is short: see
## docs/DEMO_SPEC.md "Test decisions"). Stepping onto a warp takes you to its
## destination in the same step.

const DIRS: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]

static var _bodies := {}  ## map id -> occupied_cells(), which never change at runtime
static var _gates := {}  ## map id -> gate_cells()


## Every cell you can reach from `start_cell` on `start_map`, map by map:
## {map id: {cell: steps}}. A warp cell and its destination count the same
## steps: the door takes you through as you step on it, as in the game.
static func reach(start_map: String, start_cell: Vector2i, gate_open: bool, bodies := true, blocked := {}) -> Dictionary:
	var out := {}
	if not WorldMap.MAPS.has(start_map):
		return out
	var queue: Array = [[start_map, start_cell, 0]]
	out[start_map] = {start_cell: 0}
	var head := 0
	while head < queue.size():
		var item: Array = queue[head]
		head += 1
		var map_id: String = item[0]
		var cell: Vector2i = item[1]
		var steps: int = item[2]
		var m := WorldMap.get_map(map_id)
		var w := m.warp_at(cell)
		if not w.is_empty() and cell != start_cell and WorldMap.MAPS.has(w["to"]):
			var to: String = w["to"]
			var to_cell: Vector2i = w["to_cell"]
			if not out.has(to):
				out[to] = {}
			if not out[to].has(to_cell):
				out[to][to_cell] = steps
				queue.append([to, to_cell, steps])
			continue
		for d in DIRS:
			var next: Vector2i = cell + d
			if out[map_id].has(next) or not is_open(m, next, gate_open, bodies, blocked):
				continue
			out[map_id][next] = steps + 1
			queue.append([map_id, next, steps + 1])
	return out


## Whether `cell` on `m` can be stood on (see the top).
static func is_open(m: WorldMap, cell: Vector2i, gate_open: bool, bodies := true, blocked := {}) -> bool:
	if not m.tile_walkable(cell):
		return false
	if bodies:
		if not _bodies.has(m.id):
			_bodies[m.id] = m.occupied_cells()
		if (_bodies[m.id] as Dictionary).has(cell):
			return false
	if blocked.has(m.id) and (blocked[m.id] as Dictionary).has(cell):
		return false
	return gate_open or not gate_cells(m).has(cell)


## Every gate cell on the map (cell -> the gate), from its "gates" data.
static func gate_cells(m: WorldMap) -> Dictionary:
	if not _gates.has(m.id):
		var out := {}
		for g: Dictionary in WorldMap.MAPS[m.id].get("gates", []):
			for c: Vector2i in g.get("cells", []):
				out[c] = g
		_gates[m.id] = out
	return _gates[m.id]


## Steps from `from` to every cell reachable on this one map (no warps
## followed): {cell: steps}.
static func distances(m: WorldMap, from: Vector2i, gate_open: bool, bodies := true, blocked := {}) -> Dictionary:
	var out := {from: 0}
	var queue: Array[Vector2i] = [from]
	var head := 0
	while head < queue.size():
		var c: Vector2i = queue[head]
		head += 1
		if not m.warp_at(c).is_empty() and c != from:
			continue  # a door: you'd be through it
		for d in DIRS:
			var n: Vector2i = c + d
			if out.has(n) or not is_open(m, n, gate_open, bodies, blocked):
				continue
			out[n] = out[c] + 1
			queue.append(n)
	return out


## The maps you can walk to from `start_map` (keys of reach()).
static func maps_reached(start_map: String, start_cell: Vector2i, gate_open: bool) -> Array:
	return reach(start_map, start_cell, gate_open).keys()


## Cells next to `cell` you could stand on to talk to someone there (and
## across a counter, as the overworld allows).
static func talk_spots(m: WorldMap, cell: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for d in DIRS:
		out.append(cell + d)
		if m.char_at(cell + d) == "C":
			out.append(cell + d * 2)
	return out
