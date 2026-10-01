extends TestCase


func test_catalog_has_six_species_of_four() -> void:
	check_eq(Species.ids().size(), 6, "the demo's six species")
	for id: StringName in Species.ids():
		var info := Species.get_info(id)
		check_eq(info["individuals"].size(), 4, "%s: enough for a crew of one species" % id)
		check(info["style"] in PlayStyle.Kind.values(), "%s has a play style" % id)
		check(info["tell"] != "", "%s has a tell" % id)
	check(not Species.ids().has(&"dog"), "dogs only join after the finale")


func test_animals_play_their_species_style() -> void:
	var owl := Species.individual(&"owl", 1, 0.8)
	check_eq(owl.name, "Hoot")
	check_eq(owl.style_kind(), PlayStyle.Kind.ROCK)
	var bot := owl.make_bot(3)
	check_eq(bot.style.kind, PlayStyle.Kind.ROCK)
	check_eq(bot.bond, 0.8, "bond carries over to the bot")
