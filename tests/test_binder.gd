extends TestCase
## The Binder's record (GameState.seen/recruited/found_at), what the Binder
## screen shows from it (Binder), and bond growth after matches. Saves
## from before the Binder must still load: they're tested as the exact
## dict the old to_dict wrote.

const SAVE := "user://test_binder.json"


func _pond() -> Dictionary:
	return WorldMap.get_map("town").crew_by_id("pond_hecklers")


func test_a_new_run_has_its_starters_seen_and_recruited() -> void:
	var s := GameState.fresh()
	check(s.has_recruited_species(&"owl") and s.has_recruited_species(&"raccoon"))
	check(s.has_recruited(&"owl", "Sage"))
	check(not s.has_seen_species(&"goose"))
	check_eq(Binder.completion(s), "2/25")
	check_eq(Binder.seen_count(s), 2)


func test_meeting_a_crew_marks_each_individual_seen_once() -> void:
	var s := GameState.fresh()
	s.mark_crew_seen(WorldMap.crew_animals(_pond()), "Ridge Road, with the Pond Hecklers")
	check(s.has_seen(&"goose", "Honk") and s.has_seen(&"goose", "Gertie"))
	check(s.has_seen(&"squirrel", "Nutmeg"))
	check(not s.has_seen(&"squirrel", "Acorn"), "only the ones you met")
	check(not s.has_recruited_species(&"goose"), "seen is not recruited")
	check_eq(s.found_at["goose"], "Ridge Road, with the Pond Hecklers")
	s.mark_crew_seen(WorldMap.crew_animals(_pond()), "somewhere else")
	check_eq(s.seen["goose"], ["Honk", "Gertie"], "meeting them again adds nobody twice")
	check_eq(s.found_at["goose"], "Ridge Road, with the Pond Hecklers", "the first sighting is kept")
	check_eq(Binder.seen_count(s), 4)
	check_eq(Binder.completion(s), "2/25")


func test_recruiting_marks_the_individual_and_species() -> void:
	var s := GameState.fresh()
	check(s.recruit(Species.individual(&"goose", 1)))
	check(s.has_recruited(&"goose", "Gertie"))
	check(s.has_seen(&"goose", "Gertie"), "recruiting one means you've met it")
	check(not s.has_recruited(&"goose", "Honk"))
	check_eq(Binder.completion(s), "3/25")
	check(not s.recruit(Species.individual(&"goose", 1)), "still once each")
	check_eq(s.recruited["goose"], ["Gertie"])


func test_beating_a_crew_means_you_met_it() -> void:
	var s := GameState.fresh()
	s.win_against("pond_hecklers", 0)
	check(s.has_seen(&"goose", "Honk"))
	check(s.has_seen(&"squirrel", "Nutmeg"))


func test_binder_slots_species_locked_and_dogs() -> void:
	var s := GameState.fresh()
	s.mark_seen(Species.individual(&"squirrel", 0))
	check_eq(Binder.species_at(1), &"owl")
	check_eq(Binder.species_at(6), &"possum")
	check_eq(Binder.species_at(7), &"", "the full game's species are locked")
	check_eq(Binder.species_at(25), &"dog")
	check_eq(Binder.status(s, 1), Binder.Status.RECRUITED)
	check_eq(Binder.status(s, 5), Binder.Status.SEEN)
	check_eq(Binder.status(s, 6), Binder.Status.UNSEEN)
	check_eq(Binder.status(s, 12), Binder.Status.LOCKED)
	check_eq(Binder.status(s, 25), Binder.Status.DOGS)
	for id: StringName in Species.ids():
		check(Binder.SNACKS.has(id), "%s has a favourite snack" % id)


func test_card_back_lists_individuals_met_and_yours() -> void:
	var s := GameState.fresh()
	s.mark_seen(Species.individual(&"owl", 1))
	var owls := Binder.individuals(s, &"owl")
	check_eq(owls.size(), 4)
	check_eq(owls[0]["name"], "Sage")
	check(owls[0]["animal"] == s.roster[0], "Sage is yours, with your bond")
	check_eq(owls[1]["name"], "Hoot")
	check(owls[1]["met"] and not owls[1]["recruited"] and owls[1]["animal"] == null)
	check_eq(owls[2]["name"], "?????", "unmet individuals stay hidden")
	check_eq(owls[2]["real_name"], "Bramble", "the screen looks the bio up by the real name")
	check(Bios.bio(&"owl", owls[1]["real_name"]) != "", "a met individual has a bio to show")


func test_type_chart_follows_the_cycle() -> void:
	var K := PlayStyle.Kind
	check_eq(Binder.beats(K.BLUFFER), K.ROCK)
	check_eq(Binder.beats(K.ROCK), K.MANIAC)
	check_eq(Binder.beats(K.CALLING_STATION), K.BLUFFER)
	check_eq(Binder.loses_to(K.BLUFFER), K.CALLING_STATION)
	check_eq(Binder.loses_to(K.SHARK), K.MANIAC)


func test_save_round_trip_keeps_the_binder() -> void:
	var s := GameState.fresh()
	s.mark_crew_seen(WorldMap.crew_animals(_pond()), "Ridge Road, with the Pond Hecklers")
	s.recruit(Species.individual(&"goose", 0))
	check_eq(SaveFile.write(s, SAVE), OK)
	var back := SaveFile.read(SAVE)
	SaveFile.erase(SAVE)
	if not check(back != null, "save reads back"):
		return
	check_eq(back.to_dict(), s.to_dict(), "everything comes back")
	check_eq(back.seen["goose"], ["Honk", "Gertie"])
	check_eq(back.found_at["goose"], "Ridge Road, with the Pond Hecklers")
	check(back.has_recruited(&"goose", "Honk"))


## Exactly what to_dict wrote before the Binder existed (after JSON: every
## number a float).
func test_old_save_without_binder_fields_loads_and_is_backfilled() -> void:
	var old := {
		"version": 1.0,
		"roster": [{"species": "owl", "name": "Sage", "bond": 0.5}, {"species": "raccoon", "name": "Bandit", "bond": 0.5},
			{"species": "cat", "name": "Whiskers", "bond": 0.2}],
		"party": [0.0, 2.0], "money": 350.0, "bracelets": [], "beaten": ["alley_cats"],
		"map": "town", "cell": [44.0, 10.0], "facing": [0.0, 1.0],
		"heal_map": "diner", "heal_cell": [5.0, 4.0], "seen_intro": true,
	}
	var f := FileAccess.open(SAVE, FileAccess.WRITE)
	f.store_string(JSON.stringify(old))
	f.close()
	var s := SaveFile.read(SAVE)
	SaveFile.erase(SAVE)
	if not check(s != null, "an old save still loads"):
		return
	check_eq(s.roster.size(), 3)
	check_eq(s.money, 350)
	check(s.has_recruited(&"cat", "Whiskers"), "the roster joined you")
	check(s.has_recruited(&"owl", "Sage"))
	check(s.has_seen(&"cat", "Duchess"), "a beaten crew was met")
	check(s.has_seen(&"raccoon", "Rascal"))
	check(not s.has_seen_species(&"goose"), "nothing invented")
	check(s.found_at.is_empty(), "where isn't known for old saves")
	check_eq(Binder.completion(s), "3/25")
	# And damaged Binder fields are dropped, not crashed on.
	old["seen"] = {"dragon": ["Smaug"], "goose": "Honk", "owl": ["Hoot", 3, "Hoot"]}
	old["recruited"] = "junk"
	old["found_at"] = {"owl": "the hall", "dragon": "a cave"}
	var d := GameState.from_dict(old)
	check(not d.seen.has("dragon"), "unknown species dropped")
	check(not d.seen.has("goose"), "a list that isn't one dropped")
	check_eq(d.seen["owl"], ["Hoot", "Sage"], "non-names and repeats dropped, roster backfilled")
	check(d.has_recruited(&"cat", "Whiskers"))
	check_eq(d.found_at, {"owl": "the hall"})


func test_bond_grows_for_the_seated_more_for_a_win_and_caps() -> void:
	var s := GameState.fresh()
	s.recruit(Species.individual(&"goose", 0))  # benched: the party is full
	var grew := s.grow_bonds(true)
	check_eq(grew.size(), 2)
	check(is_equal_approx(s.roster[0].bond, 0.5 + GameState.BOND_PER_WIN), "a win")
	check(is_equal_approx(s.roster[2].bond, GameState.RECRUIT_BOND), "the bench doesn't grow")
	s.grow_bonds(false)
	check(is_equal_approx(s.roster[0].bond, 0.5 + GameState.BOND_PER_WIN + GameState.BOND_PER_MATCH), "a loss, less")
	check(GameState.BOND_PER_WIN > GameState.BOND_PER_MATCH)
	for i in 20:
		s.grow_bonds(true)
	check_eq(s.roster[0].bond, GameState.MAX_BOND, "capped")
	check(s.grow_bonds(true).is_empty(), "nobody grows past the cap")
	check_eq(s.roster[0].make_bot().bond, GameState.MAX_BOND, "the bot reads it")


func test_bond_news_lines() -> void:
	var sage := Species.individual(&"owl", 0, 0.6)
	var bandit := Species.individual(&"raccoon", 0, 1.0)
	check_eq(GameState.bond_news([] as Array[Animal]), [] as Array[String])
	check_eq(GameState.bond_news([sage] as Array[Animal]), ["Sage's bond grew!"] as Array[String])
	var both := GameState.bond_news([sage, bandit] as Array[Animal])
	check_eq(both[0], "Sage and Bandit's bonds grew!")
	check_eq(both.size(), 2, "and a line for reaching full bond")
	check(both[1].begins_with("Bandit"))


func test_bond_survives_saving() -> void:
	var s := GameState.fresh()
	s.grow_bonds(true)
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	check(is_equal_approx(back.roster[0].bond, 0.6))
