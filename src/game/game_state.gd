class_name GameState
extends RefCounted
## Everything a save file holds: your roster of animals, which two sit with
## you, money, bracelets, which crews you've beaten, and where you stand.
## The Game autoload owns one of these; the overworld reads and changes it.
##
## It's a plain object with no nodes so the rules of the run (what a win
## pays, what a blackout costs, who can join) are tested headless, like the
## poker rules are, and so a save is just `to_dict()` as JSON.
##
## The party is stored as roster indices, not Animals: the roster only
## grows (nobody is released in the demo), so an index stays valid, and the
## save file needs no object references.

const VERSION := 1
const PARTY_SIZE := 2  ## animals who sit with you; you are the third seat
const STARTING_MONEY := 200
const RECRUIT_BOND := 0.2  ## a new recruit reads your signals worse than old friends

var roster: Array[Animal] = []
var party: Array[int] = []  ## indices into roster, in seat order
var money := STARTING_MONEY
var bracelets: Array[String] = []
var beaten := {}  ## crew id (String) -> true
var map_id := "town"
var cell := Vector2i.ZERO
var facing := Vector2i.DOWN
var heal_map := "diner"  ## where a blackout wakes you
var heal_cell := Vector2i.ZERO
var seen_intro := false


## A new run: the Owl and the Raccoon from the table demo, standing outside
## your house in Mossbank.
static func fresh() -> GameState:
	var s := GameState.new()
	s.roster = [Species.individual(&"owl", 0, 0.5), Species.individual(&"raccoon", 0, 0.5)]
	s.party = [0, 1]
	s.map_id = WorldMap.START_MAP
	s.cell = WorldMap.START_CELL
	s.facing = Vector2i.DOWN
	s.heal_map = WorldMap.HEAL_MAP
	s.heal_cell = WorldMap.HEAL_CELL
	return s


func party_animals() -> Array[Animal]:
	var out: Array[Animal] = []
	for i in party:
		out.append(roster[i])
	return out


## Adds or removes a roster animal from the party. Adding to a full party
## does nothing (the party screen asks you to take someone out first).
func toggle_party(index: int) -> bool:
	if index < 0 or index >= roster.size():
		return false
	if party.has(index):
		party.erase(index)
		return true
	if party.size() >= PARTY_SIZE:
		return false
	party.append(index)
	return true


## The party is complete when every seat is filled (or, with a tiny roster,
## everyone is in it). The party screen won't close until it is.
func party_ready() -> bool:
	return party.size() == mini(PARTY_SIZE, roster.size())


func has_animal(species_id: StringName, animal_name: String) -> bool:
	for a in roster:
		if a.species == species_id and a.name == animal_name:
			return true
	return false


## Adds a beaten rival to the roster. Each individual exists once, so asking
## the same one twice is refused. Joins the party if there's an empty seat.
func recruit(animal: Animal) -> bool:
	if has_animal(animal.species, animal.name):
		return false
	var a := Animal.make(animal.species, animal.name, RECRUIT_BOND)
	roster.append(a)
	if party.size() < PARTY_SIZE:
		party.append(roster.size() - 1)
	return true


func is_beaten(crew_id: String) -> bool:
	return beaten.has(crew_id)


## A won match: the crew won't challenge again, and pays up.
func win_against(crew_id: String, reward: int) -> int:
	beaten[crew_id] = true
	money += reward
	return reward


## Pokemon's blackout: you wake at the diner with half your money (rounded
## in your favour). The crew that beat you stays unbeaten and will deal you
## in again. Returns what was lost.
func blackout() -> int:
	var lost := money / 2
	money -= lost
	map_id = heal_map
	cell = heal_cell
	facing = Vector2i.UP
	return lost


func add_bracelet(id: String) -> void:
	if not bracelets.has(id):
		bracelets.append(id)


## Who sits where for TableView.setup: you in seat 0, then teams alternate
## 0, 1, 0, 1, ... so each of your animals sits between two rivals.
func table_setup(rivals: Array[Animal]) -> Array[Dictionary]:
	var mine: Array[Animal] = [null]
	mine.append_array(party_animals())
	var out: Array[Dictionary] = []
	for i in maxi(mine.size(), rivals.size()):
		if i < mine.size():
			var a: Animal = mine[i]
			out.append({"name": "You" if a == null else a.name, "team": 0, "animal": a})
		if i < rivals.size():
			out.append({"name": rivals[i].name, "team": 1, "animal": rivals[i]})
	return out


func to_dict() -> Dictionary:
	var animals: Array = []
	for a in roster:
		animals.append({"species": String(a.species), "name": a.name, "bond": a.bond})
	return {
		"version": VERSION,
		"roster": animals,
		"party": party.duplicate(),
		"money": money,
		"bracelets": bracelets.duplicate(),
		"beaten": beaten.keys(),
		"map": map_id,
		"cell": [cell.x, cell.y],
		"facing": [facing.x, facing.y],
		"heal_map": heal_map,
		"heal_cell": [heal_cell.x, heal_cell.y],
		"seen_intro": seen_intro,
	}


## Reads what to_dict wrote, after a JSON round trip (which turns every
## number into a float). Returns null if the data isn't a save; unknown
## species are dropped rather than crashing a load after a catalog change.
static func from_dict(d: Dictionary) -> GameState:
	if not (d.has("version") and d.has("roster")):
		return null
	var s := GameState.new()
	for entry: Variant in d["roster"]:
		if not entry is Dictionary or not Species.CATALOG.has(StringName(entry.get("species", ""))):
			continue
		s.roster.append(Animal.make(StringName(entry["species"]), str(entry.get("name", "?")), float(entry.get("bond", 0.3))))
	if s.roster.size() < PARTY_SIZE:
		# Lost animals (a species gone from the catalog, a damaged file):
		# your starting pair come back, so you never sit down short-handed.
		for a in fresh().roster:
			if not s.has_animal(a.species, a.name):
				s.roster.append(a)
	s.party.clear()
	var party: Variant = d.get("party", [])
	for i: Variant in party if party is Array else []:
		var index := int(i)
		if index >= 0 and index < s.roster.size() and not s.party.has(index) and s.party.size() < PARTY_SIZE:
			s.party.append(index)
	# A damaged party: fill the empty seats with the first animals standing
	# (the party screen never lets you leave a seat empty, so a load doesn't
	# either; a one-seat party played the next match two against three).
	for i in s.roster.size():
		if s.party.size() >= PARTY_SIZE:
			break
		if not s.party.has(i):
			s.party.append(i)
	s.money = maxi(0, int(d.get("money", STARTING_MONEY)))
	for b: Variant in d.get("bracelets", []):
		s.bracelets.append(str(b))
	for c: Variant in d.get("beaten", []):
		s.beaten[str(c)] = true
	s.map_id = str(d.get("map", WorldMap.START_MAP))
	s.cell = _vec(d.get("cell"), WorldMap.START_CELL)
	if not WorldMap.MAPS.has(s.map_id):  # a map that's been renamed or removed
		s.map_id = WorldMap.START_MAP
		s.cell = WorldMap.START_CELL
	s.facing = _vec(d.get("facing"), Vector2i.DOWN)
	s.heal_map = str(d.get("heal_map", WorldMap.HEAL_MAP))
	s.heal_cell = _vec(d.get("heal_cell"), WorldMap.HEAL_CELL)
	if not WorldMap.MAPS.has(s.heal_map) or not WorldMap.get_map(s.heal_map).tile_walkable(s.heal_cell):
		# A blackout would wake you inside a wall (or off the map, with no
		# way out): wake at the diner's booth instead.
		s.heal_map = WorldMap.HEAL_MAP
		s.heal_cell = WorldMap.HEAL_CELL
	s.seen_intro = bool(d.get("seen_intro", true))
	return s


static func _vec(v: Variant, fallback: Vector2i) -> Vector2i:
	if v is Array and v.size() == 2:
		return Vector2i(int(v[0]), int(v[1]))
	return fallback
