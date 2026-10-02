class_name WorldMap
extends RefCounted
## One overworld map: its tiles, written as text so a map can be read and
## edited in a diff, plus what stands on it (rival crews, townsfolk, signs,
## doors, and since demo 2 cards lying about and gates). The demo starts in
## Sootbridge (with its washhouse), takes the Mill Road east, and comes into
## Mossbank and Ridge Road (one long outdoor map, so walking out of town is
## seamless) on its west side; Mossbank has three interiors.
##
## Tiles are 16x16, one character each (legend in TILES; the maps
## themselves are in content/maps/, see below). Pure data and
## queries, no nodes: line of sight, where a crew walks to meet you and
## whether the road can be walked are all tested headless
## (tests/test_world_map.gd), and the map test checks every row is the same
## width and that everything stands where it can stand.
##
## Rival crews stand side by side: the leader on `cell`, facing `facing`,
## the others at its shoulders (a boss crew's extras further out). Only the leader looks: anything on the
## `sight` cells in front of it, up to the first wall or body, gets
## challenged, like trainers in Pokemon. A crew with sight 0 (the
## tournament's) waits to be talked to. Crews are placed so that the first
## and third can't be walked around and the other two can, with care.

const TILE := 16
const START_MAP := "sootbridge"
const START_CELL := Vector2i(12, 5)  ## by the open manhole, where the dog wakes
const HEAL_MAP := "diner"
const HEAL_CELL := Vector2i(5, 3)  ## facing the cook across the counter

## char -> [name, walkable]. The name is also the art file:
## res://assets/tiles/<name>.png (see SpriteBank).
const TILES := {
	".": ["grass", true],
	",": ["flowers", true],
	";": ["tall_grass", true],
	"=": ["path", true],
	"T": ["tree", false],
	"~": ["water", false],
	"F": ["fence", false],
	"R": ["roof", false],
	"#": ["wall", false],
	"w": ["window", false],
	"D": ["door", true],
	"d": ["door_shut", false],
	"S": ["sign", false],
	"_": ["floor", true],
	"W": ["inner_wall", false],
	"C": ["counter", false],
	"t": ["felt", false],
	"b": ["bed", false],
	"p": ["plant", false],
	"X": ["mat", true],
	":": ["cobble", true],
	"B": ["brick", false],
	"o": ["manhole", false],
	"g": ["gate", true],  ## walkable: the overworld refuses it while the deck is short (see gate_at)
	"x": ["crate", false],
	"u": ["washtub", false],
}

## The maps themselves (their tiles, the townsfolk, crews, signs, doors,
## cards lying about, gates and open tables, and every line said there)
## live in content/ since the editor's phase 1 (docs/EDITOR_SPEC.md); until
## then they were a const dictionary here, MAPS. Content builds each map in
## exactly the shape that const had (README "Content"), so everything
## below, and everyone reading WorldMap, works on the same data as before;
## tests/test_content.gd (C-SAME) checks it against a snapshot of the const.
##
## MAPS, OPEN_TABLE and STREET_GAME stay as read-only accessors over the
## loader so their callers (GameState, the tests, the playtester) didn't
## change with the move.
static var MAPS: Dictionary:
	get:
		return Content.runtime_maps()

## Mossbank's open table (docs/DEMO_SPEC.md W-TABLE): a street game anyone
## can sit at, one npc entry per player standing round the felt, each
## carrying this same dictionary (OpenTable.play reads it). Sage and Bandit
## play here until your first sit, then join you (GameState.OPEN_TABLE_CREW);
## five players so the three left after that still make a game (CashMatch
## wants two rivals at least). In content/maps/town.json's open_tables.
static var OPEN_TABLE: Dictionary:
	get:
		return Content.open_table("mossbank_open_table")

## Sootbridge's street game (demo 2.1, docs/DEMO_SPEC.md W-STREET): three
## townsfolk playing for pennies on an upturned crate outside the Lamp.
## No buy-in: they front you `stake` chips and you keep what's above it
## when you get up (OpenTable, CashMatch.cash_out_staked), and only a dog
## with less than the open table's buy-in may sit (`max_money`): it's the
## way back for a dog that lost its wallet before it had a crew, not a
## second income. The players are the three individuals no crew or table
## had yet (Pip the owl, Scraps the raccoon, Gander the goose: a Rock, a
## Bluffer and a Maniac), so none of them can ever be in your crew.
## In content/maps/sootbridge.json's open_tables.
##
## The stake and the blinds are tuned on the pace (tools/cash_sim.gd
## --street, README "Measured so far"): from $0 back to the buy-in in
## about 10-15 minutes, a bot in your seat, at about 20 s a hand. At the
## open table's depth (50 big blinds: a 50 stake at 1/2) it took a median
## 74 hands, about 25 minutes, and a bigger stake at the same depth only
## got there by paying in a few big lumps (200 at 2/4: median 41 hands but
## a tenth of runs done in 7). Shallow is what works: you keep what's above
## the stake and owe nothing below it, so every all-in is a free roll, and
## at 10 big blinds the pennies come in often and small. 60 at 3/6: median
## 39 hands (13 minutes; 4-26 for the middle 80%) on 400 runs of seeds the
## tuning never saw.
static var STREET_GAME: Dictionary:
	get:
		return Content.open_table("sootbridge_street_game")


static var _cache := {}

var id := ""
var outdoor := true
var rows: PackedStringArray = []
var width := 0
var height := 0
var warps: Array = []
var signs: Array = []
var npcs: Array = []
var crews: Array = []
var labels: Array = []
var gates: Array = []
var _pickups: Array = []


static func ids() -> Array:
	return Content.map_ids()


static func has_map(map_id: String) -> bool:
	return Content.map_ids().has(map_id)


static func get_map(map_id: String) -> WorldMap:
	if not _cache.has(map_id):
		assert(has_map(map_id), "unknown map: %s" % map_id)
		_cache[map_id] = from_data(map_id, Content.runtime_map(map_id))
	return _cache[map_id]


## A map from its runtime dictionary (Content.build_runtime_map's shape),
## not cached: for the editor's unsaved maps and the tests' made-up ones.
static func from_data(map_id: String, data: Dictionary) -> WorldMap:
	var m := WorldMap.new()
	m.id = map_id
	m.outdoor = data["outdoor"]
	m.rows = PackedStringArray(data["rows"])
	m.height = m.rows.size()
	m.width = m.rows[0].length()
	m.warps = data["warps"]
	m.signs = data["signs"]
	m.npcs = data["npcs"]
	m.crews = data["crews"]
	m.labels = data["labels"]
	m.gates = data.get("gates", [])
	m._pickups = data.get("pickups", [])
	return m


## Forgets the maps, so the next get_map reads content/ again (the editor,
## after saving).
static func reload() -> void:
	Content.reload()
	_cache.clear()


func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < width and cell.y < height


## The tile character; off the map is a tree outdoors and a wall inside.
func char_at(cell: Vector2i) -> String:
	if not in_bounds(cell):
		return "T" if outdoor else "W"
	return rows[cell.y][cell.x]


func tile_name(cell: Vector2i) -> String:
	return TILES.get(char_at(cell), ["grass", true])[0]


func tile_walkable(cell: Vector2i) -> bool:
	return TILES.get(char_at(cell), ["", false])[1]


func pixel_size() -> Vector2:
	return Vector2(width * TILE, height * TILE)


func warp_at(cell: Vector2i) -> Dictionary:
	for w: Dictionary in warps:
		if w["cell"] == cell:
			return w
	return {}


func sign_at(cell: Vector2i) -> String:
	for s: Dictionary in signs:
		if s["cell"] == cell:
			return s["text"]
	return ""


func crew_by_id(crew_id: String) -> Dictionary:
	for c: Dictionary in crews:
		if c["id"] == crew_id:
			return c
	return {}


# --- Demo 2: pickups, gates, the open table (docs/DEMO_SPEC.md) -----------------

## The cards lying on this map: [{"id", "cell", "card"}] from the map's
## "pickups" (all of them; which are taken is the run's business,
## GameState.taken_pickups). An Ace a townsperson gives is the npc entry's
## "gives_card" instead.
func pickups() -> Array:
	return _pickups


## The pickup lying on `cell` ({"id", "cell", "card"}), or {}.
func pickup_at(cell: Vector2i) -> Dictionary:
	for p: Dictionary in _pickups:
		if p["cell"] == cell:
			return p
	return {}


## The card behind a pickup id, on any map, a gift's included; -1 if no
## pickup has that id. Ids are unique across the maps (tests/test_demo_state).
static func pickup_card(pickup_id: String) -> int:
	for map_id: String in MAPS:
		var data: Dictionary = MAPS[map_id]
		for p: Dictionary in data.get("pickups", []):
			if p["id"] == pickup_id:
				return p["card"]
		for n: Dictionary in data["npcs"]:
			if n.has("gives_card") and n["gives_card"]["id"] == pickup_id:
				return n["gives_card"]["card"]
	return -1


## The gate covering `cell` ({"cells", "requires", "text"}), or {}. Gate
## cells are walkable tiles; whether you may step on one is the run's
## business (the overworld asks GameState.has_full_deck for "full_deck"),
## so the map and its paths stay the same whichever way the gate stands.
func gate_at(cell: Vector2i) -> Dictionary:
	for g: Dictionary in gates:
		if (g["cells"] as Array).has(cell):
			return g
	return {}


## The townsfolk on this map who sit at an open table: npc entries with an
## "open_table" ({"id", "buy_in", "players", "dealer"}).
func open_tables() -> Array:
	return npcs.filter(func(n: Dictionary) -> bool: return n.has("open_table"))


## Whether this townsperson has gone off with you: an open-table player
## ("animal": [species, individual]) who has joined your roster. They stop
## standing at home, like a recruit from a crew.
static func npc_joined(npc: Dictionary, state: GameState) -> bool:
	if not npc.has("animal") or state == null:
		return false
	var a: Array = npc["animal"]
	return state.has_animal(a[0], Species.individual(a[0], a[1]).name)


## Where a crew stands at home: the leader, then its two shoulders.
## Where each member stands at home: the leader on `cell`, then at its
## shoulders, then further out on alternate sides (a boss crew of four puts
## its fourth at the left shoulder's shoulder).
static func crew_cells(crew: Dictionary) -> Array[Vector2i]:
	var c: Vector2i = crew["cell"]
	var f: Vector2i = crew["facing"]
	var side := Vector2i(absi(f.y), absi(f.x))
	var out: Array[Vector2i] = [c]
	for k in range(1, (crew["members"] as Array).size()):
		out.append(c - side * ((k + 1) / 2) if k % 2 == 1 else c + side * (k / 2))
	return out


## The crew's animals, leader first. Their bond (how well they read each
## other's signals at the table) is the crew's `bond`, if it has one, else
## a stranger's 0.3.
static func crew_animals(crew: Dictionary) -> Array[Animal]:
	var out: Array[Animal] = []
	for m: Array in crew["members"]:
		out.append(Species.individual(m[0], m[1], crew.get("bond", 0.3)))
	return out


## Every cell a townsperson or crew member stands on at home (cell -> true).
func occupied_cells() -> Dictionary:
	var out := {}
	for n: Dictionary in npcs:
		out[n["cell"]] = true
	for c: Dictionary in crews:
		for cell in crew_cells(c):
			out[cell] = true
	return out


## Every cell someone stands on when this map loads, in the run `state`:
## the townsfolk, and every crew member who hasn't joined you (a recruit's
## spot is empty from then on). occupied_cells() is the same without a run.
func standing_cells(state: GameState) -> Dictionary:
	var out := {}
	for n: Dictionary in npcs:
		if not npc_joined(n, state):
			out[n["cell"]] = true
	for c: Dictionary in crews:
		var cells := crew_cells(c)
		var animals := crew_animals(c)
		for i in cells.size():
			if not state.has_animal(animals[i].species, animals[i].name):
				out[cells[i]] = true
	return out


## Where to stand you when a save puts you somewhere you can't be: `cell`
## itself if it's walkable and nobody in `taken` stands there, otherwise the
## nearest free cell (not a door) that can be walked to from the map's
## doors, so a fence next to the garden can't shut you inside it.
##
## It used to be "back to the start" for anything odd, meant for saves made
## before a map edit. But spots the map counts as taken are free in play:
## where a recruit stood, or a crew's home after it walked over to you. Quit
## there and Continue took you home to Mossbank, the whole road lost
## (found by tools/playtest.gd, which stands on such spots and continues).
func open_cell_near(cell: Vector2i, taken: Dictionary) -> Vector2i:
	if tile_walkable(cell) and not taken.has(cell):
		return cell
	var seen := {}
	var queue: Array[Vector2i] = []
	for w: Dictionary in warps:
		seen[w["cell"]] = true
		queue.append(w["cell"])
	var best := START_CELL if id == START_MAP else cell
	var best_distance := 1 << 30
	var head := 0
	while head < queue.size():
		var c: Vector2i = queue[head]
		head += 1
		var distance := absi(c.x - cell.x) + absi(c.y - cell.y)
		if distance < best_distance and warp_at(c).is_empty():
			best = c
			best_distance = distance
		for d in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var next: Vector2i = c + d
			if seen.has(next) or taken.has(next) or not tile_walkable(next):
				continue
			seen[next] = true
			queue.append(next)
	return best


## The cells a crew leader can see: straight ahead, up to `distance`, until
## a tile that isn't walkable or anyone in `occupied` blocks the view.
## Tall grass doesn't hide you; this is poker, not hide and seek.
func view_cells(from: Vector2i, facing: Vector2i, distance: int, occupied := {}) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var cell := from
	for k in distance:
		cell += facing
		if not tile_walkable(cell) or occupied.has(cell):
			break
		out.append(cell)
	return out


## The first unbeaten crew that can see `player_cell` from its home spot,
## or {}. Other crews and townsfolk block the view; the player's own
## followers don't (they walk behind). `party_size` is how many animals
## sit with you: a dog on its own (0) is nobody a crew would deal in, so
## nobody spots it (docs/DEMO_SPEC.md S-PARTY). The default (a full party)
## keeps every other caller as it was.
func spotter(player_cell: Vector2i, beaten: Dictionary, party_size := GameState.PARTY_SIZE) -> Dictionary:
	if party_size <= 0:
		return {}
	var occupied := occupied_cells()
	for c: Dictionary in crews:
		if c["sight"] <= 0 or beaten.has(c["id"]):
			continue
		if player_cell in view_cells(c["cell"], c["facing"], c["sight"], occupied):
			return c
	return {}


## The cells a leader at `from` walks through, along `facing`, to stand
## next to `target` (empty if it's already there).
static func approach_path(from: Vector2i, facing: Vector2i, target: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var cell := from + facing
	while cell != target and out.size() < 64:
		out.append(cell)
		cell += facing
	return out


## Whether `to` can be walked to from `from` without stepping on `blocked`
## cells (cell -> true). For tests: the road must stay passable around
## crews that have been beaten.
func reachable(from: Vector2i, to: Vector2i, blocked := {}) -> bool:
	var seen := {from: true}
	var queue: Array[Vector2i] = [from]
	while queue:
		var cell: Vector2i = queue.pop_front()
		if cell == to:
			return true
		for d in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var next: Vector2i = cell + d
			if seen.has(next) or blocked.has(next) or not tile_walkable(next):
				continue
			seen[next] = true
			queue.append(next)
	return false
