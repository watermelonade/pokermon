class_name Species
extends RefCounted
## The species catalog: the demo's six, each with its play style, its tell
## (the involuntary signal players learn to read) and four named
## individuals. The full game wants about 25 species (docs/DESIGN.md, The
## Binder); add them here. Dogs are deliberately absent: they never join
## until after the finale.
##
## Sprites are looked up by id: assets/sprites/<id>.png (see assets/README.md
## once the art exists).

const CATALOG := {
	&"owl": {
		"display": "Owl",
		"style": PlayStyle.Kind.ROCK,
		"tell": "Hoots softly when it likes its cards",
		"individuals": ["Sage", "Hoot", "Bramble", "Pip"],
	},
	&"raccoon": {
		"display": "Raccoon",
		"style": PlayStyle.Kind.BLUFFER,
		"tell": "Rubs its paws together when it's bluffing",
		"individuals": ["Bandit", "Rascal", "Smudge", "Scraps"],
	},
	&"goose": {
		"display": "Goose",
		"style": PlayStyle.Kind.MANIAC,
		"tell": "Honks at a good flop",
		"individuals": ["Honk", "Gertie", "Gander", "Waddles"],
	},
	&"cat": {
		"display": "Cat",
		"style": PlayStyle.Kind.SHARK,
		"tell": "Its tail flicks with a strong hand",
		"individuals": ["Duchess", "Whiskers", "Tom", "Mittens"],
	},
	&"squirrel": {
		"display": "Squirrel",
		"style": PlayStyle.Kind.CALLING_STATION,
		"tell": "Stacks and restacks its chips when it's going to call",
		"individuals": ["Nutmeg", "Acorn", "Hazel", "Chitter"],
	},
	&"possum": {
		"display": "Possum",
		"style": PlayStyle.Kind.ROCK,
		"tell": "Goes perfectly still with a monster hand",
		"individuals": ["Marlo", "Dusty", "Pudding", "Graves"],
	},
}


static func ids() -> Array:
	return CATALOG.keys()


static func get_info(species_id: StringName) -> Dictionary:
	assert(CATALOG.has(species_id), "unknown species: %s" % species_id)
	return CATALOG[species_id]


## The `index`th named individual of a species (0..3).
static func individual(species_id: StringName, index: int, bond := 0.3) -> Animal:
	var names: Array = get_info(species_id)["individuals"]
	return Animal.make(species_id, names[index % names.size()], bond)
