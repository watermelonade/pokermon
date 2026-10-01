extends SceneTestCase
## The harness checking itself, on the game as it is (no demo-2 feature
## needed, so these stay green before and after): the title shows, a new
## game reaches the overworld, the walking, talking and save-quit-continue
## helpers do what they say. If these fail, the other scene tests' failures
## mean nothing.


func test_harness_title_then_new_game_reaches_the_overworld() -> void:
	if not check(await goto_title(), "the title shows"):
		return
	check((title().get("_options") as Array).has("New game"), "the title offers New game")
	check(not FileAccess.file_exists("user://scene_test.json"), "each test starts with no save")
	if not check(await start_new_game(), "New game reaches the overworld"):
		return
	check(await came_true(func() -> bool: return not heard.is_empty(), 5.0), "the new game opens with a dialog")
	if not check(await advance(60.0, "cancel"), "the intro plays out to walking: " + last_stop):
		return
	check(state() != null, "a run is loaded")
	check_eq(game.save_path, "user://scene_test.json", "the save path is the test's own")
	check(current_map().tile_walkable(player_cell()), "you stand on a walkable cell")
	check_eq(state().cell, player_cell(), "the run and the overworld agree where you are")


func test_harness_walks_talks_and_continues() -> void:
	if not check(await start_new_game(), "a new game"):
		return
	if not check(await advance(60.0, "cancel"), "the intro plays to walking: " + last_stop):
		return
	# Walk to a cell 4 steps away (the first the BFS finds), then back.
	var start := player_cell()
	var dist := WorldPaths.distances(current_map(), start, false)
	var goal := start
	for c: Vector2i in dist:
		if int(dist[c]) == 4 and current_map().warp_at(c).is_empty():
			goal = c
			break
	if not check(goal != start, "somewhere 4 steps away"):
		return
	check(await walk_to(goal), "walk_to %s: %s" % [goal, last_stop])
	check_eq(player_cell(), goal, "walked to")
	check_eq(state().cell, goal, "the run's cell after walking")
	# Talk to the first townsperson on this map.
	if not current_map().npcs.is_empty():
		var who: Dictionary = current_map().npcs[0]
		var before := heard.size()
		check(await talk_to(who["id"]), "talk_to %s: %s" % [who["id"], last_stop])
		check(await advance(30.0, "cancel"), "their lines play out: " + last_stop)
		check(heard.size() > before, "%s said something" % who["id"])
		check(heard.has(str(who["lines"][0])) or not who.has("lines"), "%s's first line was heard" % who["id"])
	var saved := state().to_dict()
	if not check(await save_quit_continue(), "save, quit and continue: " + last_stop):
		return
	check_eq(state().to_dict(), saved, "the run after Continue")
	check_eq(player_cell(), state().cell, "standing where the run says")
