extends RefCounted
## Walking the maps as data, for the tests: where you can get to from a cell,
## across doors and map edges (warps), with Sootbridge's gate shut or open.
## The W-* tests (tests/test_demo_world.gd) compute reachability with it
## themselves instead of trusting the maps' own queries (WorldMap.reachable,
## spotter), so a map edit that walls something off fails a test; the scene
## tests (SceneTestCase) plan their walks with it.
##
## Since the editor's phase 1 the walking itself is ContentChecks'
## (src/content/content_checks.gd: the checks the editor runs live, which
## need the same BFS), and this hands every call on to it, so the tests and
## the editor share one copy (docs/EDITOR_SPEC.md C-CHECKS);
## tests/test_content.gd checks the library on a made-up map.
##
## Preloaded, not a class_name: it's test code, and the game shouldn't see it.
##
## A cell is open when its tile is walkable, nobody stands on it at home
## (townsfolk and crews; switch off with `bodies = false`), it's not in
## `blocked` ({map id: {cell: true}}) and it's not a gate cell while the
## gate is shut (gate cells are walkable tiles that the overworld refuses to
## let you onto while your deck is short: see docs/DEMO_SPEC.md "Test
## decisions"). Stepping onto a warp takes you to its destination in the
## same step.

const DIRS: Array[Vector2i] = ContentChecks.DIRS


## Every cell you can reach from `start_cell` on `start_map`, map by map:
## {map id: {cell: steps}}. A warp cell and its destination count the same
## steps: the door takes you through as you step on it, as in the game.
static func reach(start_map: String, start_cell: Vector2i, gate_open: bool, bodies := true, blocked := {}) -> Dictionary:
	return ContentChecks.reach(start_map, start_cell, gate_open, bodies, blocked)


## Whether `cell` on `m` can be stood on (see the top).
static func is_open(m: WorldMap, cell: Vector2i, gate_open: bool, bodies := true, blocked := {}) -> bool:
	return ContentChecks.is_open(m, cell, gate_open, bodies, blocked)


## Every gate cell on the map (cell -> the gate), from its gates.
static func gate_cells(m: WorldMap) -> Dictionary:
	return ContentChecks.gate_cells(m)


## Steps from `from` to every cell reachable on this one map (no warps
## followed): {cell: steps}.
static func distances(m: WorldMap, from: Vector2i, gate_open: bool, bodies := true, blocked := {}) -> Dictionary:
	return ContentChecks.distances(m, from, gate_open, bodies, blocked)


## The maps you can walk to from `start_map` (keys of reach()).
static func maps_reached(start_map: String, start_cell: Vector2i, gate_open: bool) -> Array:
	return reach(start_map, start_cell, gate_open).keys()


## Cells next to `cell` you could stand on to talk to someone there (and
## across a counter, as the overworld allows).
static func talk_spots(m: WorldMap, cell: Vector2i) -> Array[Vector2i]:
	return ContentChecks.talk_spots(m, cell)
