class_name Animal
extends Resource
## One recruitable animal: a named individual of a species. Every species
## has several individuals (docs/DESIGN.md: 4+ each, so a crew of one species
## is possible), and each one is its own character with a name and its own
## bond with you. Species-wide traits (play style, tell, flavour) live in
## Species; this holds what's personal.

@export var species: StringName
@export var name: String
@export var bond := 0.3  ## 0..1, grows with time together; how well it reads your signals


static func make(species_id: StringName, animal_name: String, starting_bond := 0.3) -> Animal:
	var a := Animal.new()
	a.species = species_id
	a.name = animal_name
	a.bond = starting_bond
	return a


func style_kind() -> PlayStyle.Kind:
	return Species.get_info(species)["style"]


## A bot that plays this animal's seat.
func make_bot(seed_value := 0) -> PokerBot:
	var bot := PokerBot.new(PlayStyle.preset(style_kind()), seed_value)
	bot.bond = bond
	return bot
