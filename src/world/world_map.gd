class_name WorldMap
extends RefCounted
## One overworld map: its tiles, written as text so a map can be read and
## edited in a diff, plus what stands on it (rival crews, townsfolk, signs,
## doors). The demo has four: Mossbank and Ridge Road (one long outdoor map,
## so walking out of town is seamless), and three interiors.
##
## Tiles are 16x16, one character each (legend in TILES). Pure data and
## queries, no nodes: line of sight, where a crew walks to meet you and
## whether the road can be walked are all tested headless
## (tests/test_world_map.gd), and the map test checks every row is the same
## width and that everything stands where it can stand.
##
## Rival crews stand side by side: the leader on `cell`, facing `facing`,
## the other two at its shoulders. Only the leader looks: anything on the
## `sight` cells in front of it, up to the first wall or body, gets
## challenged, like trainers in Pokemon. A crew with sight 0 (the
## tournament's) waits to be talked to. Crews are placed so that the first
## and third can't be walked around and the other two can, with care.

const TILE := 16
const START_MAP := "town"
const START_CELL := Vector2i(17, 7)
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
}


const MAPS := {
	"town": {
		"outdoor": true,
		"rows": [
			"TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT",
			"TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT",
			"TT................................TTTTTTTTTTTTTT...............,,,.........TTTTTTTTTTTTTTTTTTTTTTTTT",
			"TT..RRRRRRRR...RRRRRRR...RRRRRR...TTTTTTTTTTTTTT...............,,,.........TTTTTTTTTTT............TT",
			"TT..RRRRRRRR...RRRRRRR...RRRRRR...TTTTTTTTTTTTTT...........................TTTTTTTTTTT............TT",
			"TT..RRRRRRRR...RRRRRRR...RRRRRR...TTTTTTTTTTTTTT...====================....TTTTTTTTTTT..RRRRRRRRR.TT",
			"TT..#w#D##w#...#wDw#w#...#wd#w#...TTTTTTTTTTTTTT...====================....TTTTTTTTTTT..RRRRRRRRR.TT",
			"TT.....=.S.......=.........=......TTTTTTTTTTTTTT...==...;;;;;;;......==....TTTTTTTTTTT..RRRRRRRRR.TT",
			"TT.....=,,...,...=....,....=......TT...............==...;;;;;;;......==....TTTTTTTTTTT..RRRRRRRRR.TT",
			"TT.....=.........=.....,...=.......................==;;;TTTTTTTTTTT..==..T.TTTTTTTTTTT..#w#wDw#w#.TT",
			"TT.....=.........=.........=...S...................==;;;TTTTTTTTTT...==....TTTTTTTTTTT......=.....TT",
			"TT===================================================;;;TTTTTTTTTT...==....TTTTTTTTTTT......=.....TT",
			"TT===================================================...TTTTTTTTTT...==....TTTTTTTTTTT....,.=.,...TT",
			"TT........................S...........;;;;;..;;;........TTTTTTTTTT;;.==....TTTTTTTTTTT......=.....TT",
			"TT....................................;;;;;..;;;........TTTTTTTTTT;;.==..................,..=..,..TT",
			"TT...~~~~...,,,,,,,...FFFFFFFFF...TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT;;.==.....................=.....TT",
			"TT..~~~~~~..,,,,,,,...F,,,,,,,F...TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT;;.==.................S...=.....TT",
			"TT..~~~~~~............F,,,,,,,F...TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT...=============================TT",
			"TT..~~~~~~............F,,,,,,,F...TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT...=============================TT",
			"TT...~~~~....,,,,,....F,,,,,,,F...TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT................................TT",
			"TT...........,,,,,....FFFFFFFFF...TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT......,,,,....;;;;;.............TT",
			"TT................................TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT...,,,,....;;;;;.............TT",
			"TT................................TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT",
			"TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT",
			"TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT",
		],
		"labels": [
			{"rect": Rect2i(4, 3, 8, 3), "text": "DINER"},
			{"rect": Rect2i(15, 3, 7, 3), "text": "HOME"},
			{"rect": Rect2i(25, 3, 6, 3), "text": "SHOP"},
			{"rect": Rect2i(88, 5, 9, 4), "text": "TOURNAMENT HALL"},
		],
		"warps": [
			{"cell": Vector2i(7, 6), "to": "diner", "to_cell": Vector2i(6, 7), "facing": Vector2i.UP},
			{"cell": Vector2i(17, 6), "to": "home", "to_cell": Vector2i(4, 6), "facing": Vector2i.UP},
			{"cell": Vector2i(92, 9), "to": "hall", "to_cell": Vector2i(9, 10), "facing": Vector2i.UP},
		],
		"signs": [
			{"cell": Vector2i(9, 7), "text": "Rosie's Diner. If a crew cleans you out, this is where you'll wake up."},
			{"cell": Vector2i(31, 10), "text": "East: Ridge Road, then the Mossbank Tournament Hall."},
			{"cell": Vector2i(26, 13), "text": "Mossbank. Population 212, and a lot of squirrels."},
			{"cell": Vector2i(27, 6), "text": "SHOP. Closed until after the Mossbank Open."},
			{"cell": Vector2i(88, 16), "text": "Mossbank Tournament Hall. Tonight: the Mossbank Open. No dealer here has stayed awake past ten."},
		],
		"npcs": [
			{"id": "bertram", "name": "Old Bertram", "sprite": "npc_badger", "cell": Vector2i(30, 9), "facing": Vector2i.DOWN, "lines": [
				"Off to Ridge Road? Rival crews wait along it, and they don't let anyone by for free.",
				"Walk into a crew's line of sight and they'll deal you in. Beat them, and one of them might join you.",
				"Press Start (or Tab) to choose which two of your animals sit with you."]},
			{"id": "kid", "name": "Juniper, age 9", "sprite": "npc_kid", "cell": Vector2i(12, 13), "facing": Vector2i.UP, "lines": [
				"My mom says the dealer at the hall has been asleep since before I was born.",
				"So you can signal your crew all you like in there!"]},
		],
		"crews": [
			{"id": "pond_hecklers", "name": "the Pond Hecklers", "cell": Vector2i(44, 8), "facing": Vector2i.DOWN, "sight": 6,
				"members": [[&"goose", 0], [&"squirrel", 0], [&"goose", 1]],
				"before": ["Honk! Fresh faces on Ridge Road!", "Nobody gets past the Pond Hecklers without playing a hand. Sit down!"],
				"after": "Honk... We'll be back at the pond, practising.",
				"reward": 120, "chips": 500, "dealer": Dealer.Kind.STREET},
			{"id": "alley_cats", "name": "the Alley Cats", "cell": Vector2i(48, 7), "facing": Vector2i.RIGHT, "sight": 4,
				"members": [[&"cat", 0], [&"cat", 1], [&"raccoon", 1]],
				"before": ["Well, well. A stray with a crew.", "Cards on the crate. Let's see what you've got."],
				"after": "Fine. But the alley remembers.",
				"reward": 150, "chips": 500, "dealer": Dealer.Kind.STREET},
			{"id": "nut_club", "name": "the Nut Club", "cell": Vector2i(60, 2), "facing": Vector2i.DOWN, "sight": 6,
				"members": [[&"squirrel", 1], [&"squirrel", 2], [&"squirrel", 3]],
				"before": ["Halt! This stretch of road belongs to the Nut Club!", "The toll is one game. We call. We always call."],
				"after": "We called everything. Why didn't that work?",
				"reward": 180, "chips": 500, "dealer": Dealer.Kind.STREET},
			{"id": "night_shift", "name": "the Night Shift", "cell": Vector2i(78, 15), "facing": Vector2i.DOWN, "sight": 5,
				"members": [[&"possum", 0], [&"owl", 1], [&"raccoon", 2]],
				"before": ["...", "Oh. You can see us. Most folks walk right past.", "Deal. Quietly."],
				"after": "Shh. We're pretending to be asleep again.",
				"reward": 220, "chips": 500, "dealer": Dealer.Kind.STREET},
		],
	},
	"diner": {
		"outdoor": false,
		"rows": [
			"WWWWWWWWWWWWWW",
			"W____________W",
			"WCCCCCCCCC___W",
			"W____________W",
			"W____________W",
			"W_tt____tt___W",
			"W_tt____tt__pW",
			"Wp___________W",
			"W_____XX_____W",
			"WWWWWWWWWWWWWW",
		],
		"labels": [],
		"warps": [
			{"cell": Vector2i(6, 8), "to": "town", "to_cell": Vector2i(7, 7), "facing": Vector2i.DOWN},
			{"cell": Vector2i(7, 8), "to": "town", "to_cell": Vector2i(7, 7), "facing": Vector2i.DOWN},
		],
		"signs": [],
		"npcs": [
			{"id": "rosie", "name": "Rosie", "sprite": "npc_cook", "cell": Vector2i(5, 1), "facing": Vector2i.DOWN, "lines": [
				"Sit a while, hon. Nobody leaves Rosie's hungry.",
				"If a crew cleans you out, you'll wake up in that booth. Happens to everybody."]},
		],
		"crews": [],
	},
	"home": {
		"outdoor": false,
		"rows": [
			"WWWWWWWWWW",
			"W_bb___p_W",
			"W_bb_____W",
			"W________W",
			"W___tt___W",
			"W___tt___W",
			"W________W",
			"W___XX___W",
			"WWWWWWWWWW",
		],
		"labels": [],
		"warps": [
			{"cell": Vector2i(4, 7), "to": "town", "to_cell": Vector2i(17, 7), "facing": Vector2i.DOWN},
			{"cell": Vector2i(5, 7), "to": "town", "to_cell": Vector2i(17, 7), "facing": Vector2i.DOWN},
		],
		"signs": [
			{"cell": Vector2i(4, 4), "text": "Your practice table. The felt has seen better days."},
			{"cell": Vector2i(5, 4), "text": "Your practice table. The felt has seen better days."},
		],
		"npcs": [],
		"crews": [],
	},
	"hall": {
		"outdoor": false,
		"rows": [
			"WWWWWWWWWWWWWWWWWWWW",
			"W__________________W",
			"W_p______________p_W",
			"W______tttttt______W",
			"W______tttttt______W",
			"W______tttttt______W",
			"W__________________W",
			"W__________________W",
			"W__________________W",
			"W__________________W",
			"W__________________W",
			"W________XX________W",
			"WWWWWWWWWWWWWWWWWWWW",
		],
		"labels": [],
		"warps": [
			{"cell": Vector2i(9, 11), "to": "town", "to_cell": Vector2i(92, 10), "facing": Vector2i.DOWN},
			{"cell": Vector2i(10, 11), "to": "town", "to_cell": Vector2i(92, 10), "facing": Vector2i.DOWN},
		],
		"signs": [],
		"npcs": [
			{"id": "lou", "name": "Lou, the dealer", "sprite": "npc_dealer", "cell": Vector2i(9, 2), "facing": Vector2i.DOWN, "asleep": true, "lines": [
				"Zzz... ante up... zzz..."]},
		],
		"crews": [
			{"id": "mossbank_regulars", "name": "the Mossbank Regulars", "cell": Vector2i(9, 6), "facing": Vector2i.DOWN, "sight": 0,
				"members": [[&"possum", 3], [&"cat", 2], [&"owl", 2]],
				"before": ["So you're the one cleaning out Ridge Road.",
					"We're the Mossbank Regulars. Win the Open and the bracelet is yours.",
					"Lou's asleep, so signal all you like. We will."],
				"after": "Wear that bracelet with pride. The next town won't go easy on you.",
				"reward": 500, "chips": 1000, "dealer": Dealer.Kind.ASLEEP, "bracelet": "mossbank", "tournament": true},
		],
	},
}

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


static func ids() -> Array:
	return MAPS.keys()


static func get_map(map_id: String) -> WorldMap:
	if not _cache.has(map_id):
		assert(MAPS.has(map_id), "unknown map: %s" % map_id)
		var data: Dictionary = MAPS[map_id]
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
		_cache[map_id] = m
	return _cache[map_id]


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


## Where a crew stands at home: the leader, then its two shoulders.
static func crew_cells(crew: Dictionary) -> Array[Vector2i]:
	var c: Vector2i = crew["cell"]
	var f: Vector2i = crew["facing"]
	var side := Vector2i(absi(f.y), absi(f.x))
	return [c, c - side, c + side]


static func crew_animals(crew: Dictionary) -> Array[Animal]:
	var out: Array[Animal] = []
	for m: Array in crew["members"]:
		out.append(Species.individual(m[0], m[1]))
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
## followers don't (they walk behind).
func spotter(player_cell: Vector2i, beaten: Dictionary) -> Dictionary:
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
