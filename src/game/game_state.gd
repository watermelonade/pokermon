class_name GameState
extends RefCounted
## Everything a save file holds: your roster of animals, which two sit with
## you, money, bracelets, which crews you've beaten, and where you stand.
## The Game autoload owns one of these; the overworld reads and changes it.
##
## Tutorial progress (Rosie's lessons, src/tutorial/): whether she's offered
## them yet, so a new game asks once and never again, and whether you've
## finished them. Both were added after saves existed: a save without them
## is from someone already past the start, so it loads as offered (no
## surprise lesson on Continue) and not done (the diner still offers it).
##
## It's a plain object with no nodes so the rules of the run (what a win
## pays, what a blackout costs, who can join) are tested headless, like the
## poker rules are, and so a save is just `to_dict()` as JSON.
##
## The party is stored as roster indices, not Animals: the roster only
## grows (nobody is released in the demo), so an index stays valid, and the
## save file needs no object references.
##
## The Binder (the collection screen) reads `seen` and `recruited`: which
## individuals you've sat across a table from, and which have joined. They
## are kept per individual, not per species, because each species has four
## named animals and the card back lists the ones you've met. `recruited`
## is stored rather than derived from the roster so that letting an animal
## go (a later feature) won't erase the record that it once joined. Saves
## from before these fields existed load with them empty and then refilled
## from what the save does know (see backfill_binder): your roster joined
## you, and every beaten crew was met.
##
## Bond grows with time together (docs/DESIGN.md: it matters more than
## level): each match an animal sits through adds BOND_PER_MATCH, a win
## BOND_PER_WIN instead, capped at 1.0. Bots read it as how reliably they
## catch your signals (PokerBot.bond). The numbers are picked so growth is
## visible inside the demo's five matches: half a heart (of five) per win,
## so a recruit at 0.2 reaches 0.6 by the Open if it plays every road game,
## while the starters at 0.5 can max out only over a longer run.

const VERSION := 1
const PARTY_SIZE := 2  ## animals who sit with you; you are the third seat
const STARTING_MONEY := 200
const RECRUIT_BOND := 0.2  ## a new recruit reads your signals worse than old friends
const BOND_PER_MATCH := 0.05  ## sat with you through a lost match
const BOND_PER_WIN := 0.1  ## sat with you through a won one
const MAX_BOND := 1.0

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
var tutorial_offered := false  ## Rosie has asked "want me to show you?" (asked once, at the start)
var tutorial_done := false  ## you played the lessons to the end
var pending_recruit := ""  ## a beaten crew whose recruit offer hasn't been answered yet
var demo_complete_seen := false  ## the end-of-demo screen has been shown
var seen_intro := false
var seen := {}  ## species id (String) -> Array of individual names met, in order met
var recruited := {}  ## species id (String) -> Array of names that joined you
var found_at := {}  ## species id (String) -> where you first met one (for the Binder)
## Rival crews' signal codes cracked so far, and what they've cracked of
## yours (interception: src/crew/code_book.gd). Kept so a rematch remembers.
var codebook := CodeBook.new()

# --- Demo 2: the opening (docs/DEMO_SPEC.md) ----------------------------------
# You are a dog. Your owner fell down a manhole in Sootbridge and the four
# Aces of his deck went with him; the deck you're left holding is short
# until you find them (pickups around Sootbridge, WorldMap "pickups" and a
# townsperson's "gives_card"). The deck is a list of the cards held rather
# than a count of missing ones so a later demo can lose and find other
# cards (the design's simple card games with the cards you have) with no
# change to the save. Pickups are recorded by id, not by card, so a card
# that lies in two places (a later map) can't be taken twice from one.
#
# Saves from before demo 2 have no "deck": they're runs past the opening
# (a full deck, opening_done) with their roster as it was. Since demo 2.1
# every load repairs the deck (repair_deck: B-DECKFIX), so a damaged file
# can't leave a run short of a card it can never find again.

## The cards the dog wakes up without: the four Aces went down the manhole
## with its owner (Card.parse format).
const OPENING_MISSING := ["As", "Ah", "Ad", "Ac"]
const DECK_SIZE := 52
## Who joins after your first sit at Mossbank's open table ([species,
## individual]): the table demo's starters, now met on the road.
const OPEN_TABLE_CREW := [[&"owl", 0], [&"raccoon", 0]]
## Their bond when they join: what the starters began with, so the matches
## after the open table play as they did when the game began with them.
const OPEN_TABLE_BOND := 0.5

var deck: Array[int] = []  ## the cards you hold (Card ints); a new game holds 48
var taken_pickups := {}  ## pickup id (String) -> true, once taken
var opening_done := false  ## past the opening (the deck is complete and you've left Sootbridge)
var met_open_table := false  ## you've sat at Mossbank's open table at least once


## A new run: the dog, alone, waking by the manhole in Sootbridge with its
## owner's wallet and a deck missing its four Aces. Nobody's in the roster
## until the open table in Mossbank (join_open_table_crew).
static func fresh() -> GameState:
	var s := GameState.new()
	s.map_id = WorldMap.START_MAP
	s.cell = WorldMap.START_CELL
	s.facing = Vector2i.DOWN
	s.heal_map = WorldMap.HEAL_MAP
	s.heal_cell = WorldMap.HEAL_CELL
	var missing := opening_missing_cards()
	for c in DECK_SIZE:
		if not missing.has(c):
			s.deck.append(c)
	return s


## A card the way a line names it: "Ace of Spades".
static func card_name(card: int) -> String:
	const RANKS := ["Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine", "Ten", "Jack", "Queen", "King", "Ace"]
	const SUITS := ["Clubs", "Diamonds", "Hearts", "Spades"]
	return "%s of %s" % [RANKS[Card.rank(card) - 2], SUITS[Card.suit(card)]]


## OPENING_MISSING as cards.
static func opening_missing_cards() -> Array[int]:
	var out: Array[int] = []
	for c: String in OPENING_MISSING:
		out.append(Card.parse(c))
	return out


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
	mark_seen(a)
	mark_recruited(a)
	if party.size() < PARTY_SIZE:
		party.append(roster.size() - 1)
	return true


# --- The Binder ---------------------------------------------------------------

## Records meeting an individual (a crew dealt you in, so you watched it
## play). `where` is kept for the species' first sighting only.
func mark_seen(animal: Animal, where := "") -> void:
	var key := String(animal.species)
	if not seen.has(key):
		seen[key] = []
	if not (seen[key] as Array).has(animal.name):
		seen[key].append(animal.name)
	if where != "" and not found_at.has(key):
		found_at[key] = where


func mark_crew_seen(animals: Array[Animal], where := "") -> void:
	for a in animals:
		mark_seen(a, where)


func mark_recruited(animal: Animal) -> void:
	var key := String(animal.species)
	if not recruited.has(key):
		recruited[key] = []
	if not (recruited[key] as Array).has(animal.name):
		recruited[key].append(animal.name)


func has_seen_species(species_id: StringName) -> bool:
	return seen.has(String(species_id))


func has_recruited_species(species_id: StringName) -> bool:
	return recruited.has(String(species_id))


func has_seen(species_id: StringName, animal_name: String) -> bool:
	return (seen.get(String(species_id), []) as Array).has(animal_name)


func has_recruited(species_id: StringName, animal_name: String) -> bool:
	return (recruited.get(String(species_id), []) as Array).has(animal_name)


## Your roster's animal of that species and name, or null.
func roster_animal(species_id: StringName, animal_name: String) -> Animal:
	for a in roster:
		if a.species == species_id and a.name == animal_name:
			return a
	return null


## After a match: everyone who sat with you grows closer, more for a win.
## Returns the animals whose bond went up (not those already at the cap),
## so the overworld can say so.
func grow_bonds(won: bool) -> Array[Animal]:
	var grew: Array[Animal] = []
	for a in party_animals():
		var before := a.bond
		a.bond = minf(MAX_BOND, a.bond + (BOND_PER_WIN if won else BOND_PER_MATCH))
		if a.bond > before:
			grew.append(a)
	return grew


## The dialog after a match: "Sage's bond grew!", and a line for anyone who
## just reached the cap.
static func bond_news(grew: Array[Animal]) -> Array[String]:
	var lines: Array[String] = []
	if grew.is_empty():
		return lines
	var names: Array[String] = []
	for a in grew:
		names.append(a.name)
	if names.size() == 1:
		lines.append("%s's bond grew!" % names[0])
	else:
		lines.append("%s and %s's bonds grew!" % [", ".join(names.slice(0, -1)), names[-1]])
	for a in grew:
		if a.bond >= MAX_BOND:
			lines.append("%s would follow you anywhere now. (Bond is full.)" % a.name)
	return lines


func is_beaten(crew_id: String) -> bool:
	return beaten.has(crew_id)


## A won match: the crew won't challenge again, and pays up. (Its animals
## are marked seen too: you can't beat a crew you never met, and a save
## should read back the same whichever way it was made.)
func win_against(crew_id: String, reward: int) -> int:
	beaten[crew_id] = true
	for map_id: String in WorldMap.ids():
		var crew := WorldMap.get_map(map_id).crew_by_id(crew_id)
		if crew:
			mark_crew_seen(WorldMap.crew_animals(crew))
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


# --- Demo 2: the deck, pickups and the open table's crew -----------------------

## Adds `card` to the deck if it's missing: true if it was added, false if
## you already hold it (or it isn't a card).
func collect_card(card: int) -> bool:
	if card < 0 or card >= DECK_SIZE or deck.has(card):
		return false
	deck.append(card)
	return true


## True exactly when all 52 cards are held.
func has_full_deck() -> bool:
	return missing_cards().is_empty()


## The cards not in the deck, lowest first.
func missing_cards() -> Array[int]:
	var out: Array[int] = []
	for c in DECK_SIZE:
		if not deck.has(c):
			out.append(c)
	return out


## Takes the pickup (or the townsperson's gift) with this id: its card goes
## into the deck and the id is recorded, once. Returns the card, or -1 if
## it's already taken or there's no such pickup. A card you already hold
## (a save from before the opening walking back into Sootbridge) gives
## nothing, and the spot is marked taken so it isn't drawn again.
func take_pickup(id: String) -> int:
	if taken_pickups.has(id):
		return -1
	var card := WorldMap.pickup_card(id)
	if card < 0:
		return -1
	taken_pickups[id] = true
	return card if collect_card(card) else -1


## Whether the pickup (or gift) with this id still has a card to give you.
func pickup_waiting(id: String, card: int) -> bool:
	return not taken_pickups.has(id) and not deck.has(card)


## After your first sit at the open table: Sage (owl) and Bandit (raccoon)
## join the roster and the party. Returns who joined; empty if nobody (a
## second call, or they're already yours: an old save had them from the
## start). Guarded by who's in the roster, not by met_open_table, so the
## open table can mark the sit first and then call this (the order J-OLD
## uses).
func join_open_table_crew() -> Array[Animal]:
	var joined: Array[Animal] = []
	met_open_table = true
	for entry: Array in OPEN_TABLE_CREW:
		var a := Species.individual(entry[0], entry[1], OPEN_TABLE_BOND)
		if has_animal(a.species, a.name):
			continue
		roster.append(a)
		mark_seen(a, "Mossbank, at the open table")
		mark_recruited(a)
		if party.size() < PARTY_SIZE:
			party.append(roster.size() - 1)
		joined.append(a)
	return joined


## Who sits where for TableView.setup: you in seat 0, then teams alternate
## 0, 1, 0, 1, ... so each of your animals sits between two rivals.
## `crew_id` names the rival crew for interception's code book, so what you
## crack of their code is remembered across rematches.
func table_setup(rivals: Array[Animal], crew_id := "") -> Array[Dictionary]:
	var mine: Array[Animal] = [null]
	mine.append_array(party_animals())
	var out: Array[Dictionary] = []
	for i in maxi(mine.size(), rivals.size()):
		if i < mine.size():
			var a: Animal = mine[i]
			out.append({"name": "You" if a == null else a.name, "team": 0, "animal": a})
		if i < rivals.size():
			var seat := {"name": rivals[i].name, "team": 1, "animal": rivals[i]}
			if crew_id:
				seat["crew"] = crew_id
			out.append(seat)
	return out


## A boss table (a crew with "boss": the Open's final): you and your party
## against a bigger crew, seated the way the boss rigs the draw and with
## the boss's chips split leader-heavy (BossTable). `chips` is each of your
## seats' stack.
func boss_table_setup(rivals: Array[Animal], crew_id: String, chips: int) -> Array[Dictionary]:
	var mine: Array[Dictionary] = [{"name": "You", "animal": null}]
	for a in party_animals():
		mine.append({"name": a.name, "animal": a})
	var boss: Array[Dictionary] = []
	for a in rivals:
		boss.append({"name": a.name, "animal": a})
	return BossTable.setup(mine, boss, chips, true, crew_id)


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
		"tutorial_offered": tutorial_offered,
		"tutorial_done": tutorial_done,
		"seen_intro": seen_intro,
		"seen": seen.duplicate(true),
		"recruited": recruited.duplicate(true),
		"found_at": found_at.duplicate(),
		"codebook": codebook.to_dict(),
		"pending_recruit": pending_recruit,
		"demo_complete_seen": demo_complete_seen,
		"deck": deck.duplicate(),
		"taken_pickups": taken_pickups.keys(),
		"opening_done": opening_done,
		"met_open_table": met_open_table,
	}


## Reads what to_dict wrote, after a JSON round trip (which turns every
## number into a float). Returns null if the data isn't a save; unknown
## species are dropped rather than crashing a load after a catalog change.
static func from_dict(d: Dictionary) -> GameState:
	if not (d.has("version") and d.has("roster")):
		return null
	var s := GameState.new()
	var moved := {}  ## index in the file's roster -> index in ours, for the party
	var entries: Variant = d["roster"]
	for i in entries.size() if entries is Array else 0:
		var entry: Variant = entries[i]
		if not entry is Dictionary or not Species.CATALOG.has(StringName(entry.get("species", ""))):
			continue
		var a := Animal.make(StringName(entry["species"]), str(entry.get("name", "?")), float(entry.get("bond", 0.3)))
		for j in s.roster.size():  # each individual once: a duplicate seats the first copy
			if s.roster[j].species == a.species and s.roster[j].name == a.name:
				moved[i] = j
		if not moved.has(i):
			moved[i] = s.roster.size()
			s.roster.append(a)
	# Before demo 2 a save had no deck: it's a run past the opening.
	var old_save := not d.has("deck")
	s.met_open_table = bool(d.get("met_open_table", false))
	if s.roster.size() < PARTY_SIZE and (old_save or s.met_open_table):
		# Lost animals (a species gone from the catalog, a damaged file):
		# the pair you started with (or met at the open table) come back,
		# so you never sit down short-handed. Not before the open table: a
		# dog alone has an empty roster, and that's no damage.
		for entry: Array in OPEN_TABLE_CREW:
			var a := Species.individual(entry[0], entry[1], OPEN_TABLE_BOND)
			if not s.has_animal(a.species, a.name):
				s.roster.append(a)
	s.party.clear()
	var party: Variant = d.get("party", [])
	for i: Variant in party if party is Array else []:
		var index: int = moved.get(int(i), -1)
		if index >= 0 and not s.party.has(index) and s.party.size() < PARTY_SIZE:
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
	for map_id: String in WorldMap.ids():
		for c: Dictionary in WorldMap.get_map(map_id).crews:
			if c.has("bracelet") and s.beaten.has(c["id"]):
				# Saved between the win and the bracelet (the window closed
				# during "You beat the Regulars!"): the Regulars won't play
				# again, so without this the bracelet could never be won.
				s.add_bracelet(c["bracelet"])
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
	s.tutorial_offered = bool(d.get("tutorial_offered", true))
	s.tutorial_done = bool(d.get("tutorial_done", false))
	s.seen_intro = bool(d.get("seen_intro", true))
	s.seen = _name_lists(d.get("seen"))
	s.recruited = _name_lists(d.get("recruited"))
	var found: Variant = d.get("found_at")
	if found is Dictionary:
		for k: Variant in found:
			if Species.CATALOG.has(StringName(str(k))):
				s.found_at[str(k)] = str(found[k])
	s.backfill_binder()
	if d.has("codebook"):  # older saves have none: start empty
		var book := CodeBook.from_dict(d["codebook"])
		if book:
			s.codebook = book
	s.pending_recruit = str(d.get("pending_recruit", ""))
	s.deck.clear()
	var cards: Variant = d.get("deck")
	if old_save or not cards is Array:
		for c in DECK_SIZE:
			s.deck.append(c)
	else:
		for c: Variant in cards:
			if (c is int or c is float) and int(c) >= 0 and int(c) < DECK_SIZE and not s.deck.has(int(c)):
				s.deck.append(int(c))
	var taken: Variant = d.get("taken_pickups", [])
	for id: Variant in taken if taken is Array else []:
		s.taken_pickups[str(id)] = true
	s.opening_done = bool(d.get("opening_done", old_save))
	s.repair_deck()
	# Older saves: a won Open means the end screen was already seen.
	s.demo_complete_seen = bool(d.get("demo_complete_seen", not s.bracelets.is_empty()))
	return s


## The deck as the rules say it must be (docs/DEMO_SPEC.md B-DECKFIX), from
## whatever a save held: every card but the opening's Aces, once each, and
## each Ace exactly when its pickup (or Mags's gift) is recorded as taken.
## A run past the opening holds all four (the gate only lets a full deck
## by, and a pre-demo save loads past it), so its four pickups are recorded
## as taken. Run on every load; a good save comes out as it went in, its
## order kept, with any card put back added at the end.
##
## Before this, a load kept whatever deck it found: the playtester's
## damaged saves loaded `[51, 51, 51, 0, 0]` as a 2-card deck, and a run in
## Sootbridge that had lost a card that isn't an Ace could never pass the
## gate. Trusting the taken pickups over the deck is what a damaged file
## can't get wrong in a way that strands you: a card you held but whose
## pickup isn't recorded is still lying where it was, to be taken again.
func repair_deck() -> void:
	var aces := opening_pickups()
	if opening_done:
		for id: String in aces:
			taken_pickups[id] = true
	var held := {}
	for id: String in aces:
		held[aces[id]] = taken_pickups.has(id)
	var out: Array[int] = []
	for c in deck:
		if c >= 0 and c < DECK_SIZE and not out.has(c) and held.get(c, true):
			out.append(c)
	for c in DECK_SIZE:
		if not out.has(c) and held.get(c, true):
			out.append(c)
	deck = out


## The opening's Aces as pickups: id -> card, for every pickup and gift on
## the maps whose card is one of OPENING_MISSING.
static func opening_pickups() -> Dictionary:
	var out := {}
	var aces := opening_missing_cards()
	for map_id: String in WorldMap.MAPS:
		var data: Dictionary = WorldMap.MAPS[map_id]
		for p: Dictionary in data.get("pickups", []):
			if aces.has(int(p["card"])):
				out[p["id"]] = int(p["card"])
		for n: Dictionary in data["npcs"]:
			if n.has("gives_card") and aces.has(int(n["gives_card"]["card"])):
				out[n["gives_card"]["id"]] = int(n["gives_card"]["card"])
	return out


## Saves from before the Binder (and damaged ones) still know who joined
## you and which crews you beat; both mean you've met those animals.
## Unbeaten crews you lost to aren't recoverable, so they read as unseen
## until you meet them again.
func backfill_binder() -> void:
	for a in roster:
		mark_seen(a)
		mark_recruited(a)
	for map_id: String in WorldMap.ids():
		for c: Dictionary in WorldMap.get_map(map_id).crews:
			if beaten.has(c["id"]):
				mark_crew_seen(WorldMap.crew_animals(c))


## {species: [names]} from JSON, dropping unknown species and non-strings.
static func _name_lists(v: Variant) -> Dictionary:
	var out := {}
	if not v is Dictionary:
		return out
	for k: Variant in v:
		var key := str(k)
		if not Species.CATALOG.has(StringName(key)) or not v[k] is Array:
			continue
		var names: Array = []
		for n: Variant in v[k]:
			if n is String and not names.has(n):
				names.append(n)
		out[key] = names
	return out


static func _vec(v: Variant, fallback: Vector2i) -> Vector2i:
	if v is Array and v.size() == 2:
		return Vector2i(int(v[0]), int(v[1]))
	return fallback
