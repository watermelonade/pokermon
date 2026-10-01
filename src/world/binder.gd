class_name Binder
extends RefCounted
## What the Binder (the collection screen, BinderScreen) shows, worked out
## from a GameState with no drawing, so it's tested headless: which slot
## holds which species, what you know about each, and the completion count.
##
## The full game has 25 species (docs/DESIGN.md, The Binder); the demo has
## the six in Species.CATALOG, in slots 1-6 in catalog order. Slots 7-24
## are locked "???" cards, so the count reads "x/25" from the start: a
## Pokedex that showed 6/6 would tell the player the demo is the whole
## game. Slot 25 is the dogs': they never join until after the finale (the
## painting, A Friend in Need), so their slot is a dog-shaped silhouette
## that can't be filled yet, a promise rather than a gap.
##
## What a card shows grows in three steps, like a Pokedex's seen/owned:
## unseen (a silhouette), seen (you watched one play: its name, style,
## where you met it, the individuals you've met), recruited (one joined
## you: the card back fills in with its tell and favourite snack, and
## your animals' bond). The tell is held back until one joins because
## learning tells is the skill the game teaches at the table; the Binder
## writes it down once you've played alongside one.

enum Status { UNSEEN, SEEN, RECRUITED, LOCKED, DOGS }

const TOTAL := 25
const DOG_SLOT := 25
const DOG_LINE := "Won't sit at your table... yet."

## Card-back flavour Species doesn't carry (it holds what the table needs).
## Move it there if the table ever uses it.
const SNACKS := {
	&"owl": "Blueberry muffins, eaten at midnight",
	&"raccoon": "Anything in a bin, honestly",
	&"goose": "Bread. It knows it shouldn't",
	&"cat": "Sardines on toast",
	&"squirrel": "Salted peanuts, buried for later",
	&"possum": "Overripe persimmons",
}

## The type chart: each style beats the next (docs/DESIGN.md).
const CYCLE := [PlayStyle.Kind.BLUFFER, PlayStyle.Kind.ROCK, PlayStyle.Kind.MANIAC,
	PlayStyle.Kind.SHARK, PlayStyle.Kind.CALLING_STATION]


## Slot number (1..TOTAL) -> species id, or &"" for a locked slot, or
## &"dog" for the dogs'.
static func species_at(number: int) -> StringName:
	var ids := Species.ids()
	if number >= 1 and number <= ids.size():
		return ids[number - 1]
	if number == DOG_SLOT:
		return &"dog"
	return &""


static func status(state: GameState, number: int) -> Status:
	if number == DOG_SLOT:
		return Status.DOGS
	var id := species_at(number)
	if id == &"":
		return Status.LOCKED
	if state.has_recruited_species(id):
		return Status.RECRUITED
	if state.has_seen_species(id):
		return Status.SEEN
	return Status.UNSEEN


## Species you've seen (recruiting one counts as seeing it).
static func seen_count(state: GameState) -> int:
	var n := 0
	for id: StringName in Species.ids():
		if state.has_seen_species(id) or state.has_recruited_species(id):
			n += 1
	return n


static func recruited_count(state: GameState) -> int:
	var n := 0
	for id: StringName in Species.ids():
		if state.has_recruited_species(id):
			n += 1
	return n


## "2/25": species with at least one animal in your crew, of the full set.
static func completion(state: GameState) -> String:
	return "%d/%d" % [recruited_count(state), TOTAL]


static func beats(kind: PlayStyle.Kind) -> PlayStyle.Kind:
	return CYCLE[(CYCLE.find(kind) + 1) % CYCLE.size()]


static func loses_to(kind: PlayStyle.Kind) -> PlayStyle.Kind:
	return CYCLE[(CYCLE.find(kind) + CYCLE.size() - 1) % CYCLE.size()]


## One line per named individual of a species, for the card back:
## {name ("?????" if not met), real_name, met, recruited, animal (yours,
## or null)}. The screen shows a met one's bio (Bios) under its name.
static func individuals(state: GameState, species_id: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for n: String in Species.get_info(species_id)["individuals"]:
		var met := state.has_seen(species_id, n) or state.has_recruited(species_id, n)
		out.append({
			"name": n if met else "?????",
			"real_name": n,
			"met": met,
			"recruited": state.has_recruited(species_id, n),
			"animal": state.roster_animal(species_id, n),
		})
	return out
