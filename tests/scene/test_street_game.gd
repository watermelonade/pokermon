extends SceneTestCase
## Demo 2.1's street game in Sootbridge, played in the real game
## (docs/DEMO_SPEC.md G-STREET): a broke dog talks to one of the players
## round the crate, sits without paying (they front it a stake), plays with
## a bot in its seat, gets up, and keeps exactly the chips above the stake
## (or nothing, if it's below). A dog with the open table's buy-in or more
## is turned away with a line, and nothing changes.
##
## Each test starts as a run past the opening (full deck, no crew, never
## sat at the open table) standing at Sootbridge's start cell, written as
## the save and continued from the title (demo_state_at).
##
## Written before the street game exists (test first): red until it's
## built, and listed in tests/expected_red.txt until then.


## The street game's first player ([map, npc]), or [] (failing a check).
func _player(id: String) -> Array:
	var found := street_game_npcs()
	if not check(not found.is_empty(), "%s: Sootbridge has a street game (no npc with an open_table carrying a stake)" % id):
		return []
	return found[0]


## Continues a run past the opening at Sootbridge's start, with `money`.
func _in_sootbridge(id: String, money: int) -> bool:
	var s := demo_state_at(WorldMap.START_MAP, WorldMap.START_CELL)
	s.money = money
	if not check(await continue_from(s), "%s: continue in Sootbridge" % id):
		return false
	return check(await advance(20.0, "cancel"), "%s: walking in Sootbridge: %s" % [id, last_stop])


## G-STREET: a dog with $0 talks to the street game's players: offered a
## seat (yes / no), it sits without paying, the table opens in cash mode
## with the dog at seat 0 holding the stake, a bot plays two hands, it
## leaves, and its money grows by exactly the chips above the stake (or
## stays the same), on screen and on disk. It's not the open table: nobody
## joins.
func test_G_STREET_a_broke_dog_sits_free_and_keeps_what_is_above_the_stake() -> void:
	var found := _player("G-STREET")
	if found.is_empty() or not await _in_sootbridge("G-STREET", 0):
		return
	timeout_s = 600.0
	game.dev_args["autoplay"] = ""  # a bot plays your seat
	game.dev_args["seed"] = "7"  # the same deal and bots every run
	var npc: Dictionary = found[1]
	var t: Dictionary = npc["open_table"]
	var stake := int(t.get("stake", 0))
	if not check(await talk_to(npc["id"], found[0]), "G-STREET: talk to %s: %s" % [npc["id"], last_stop]):
		return
	await advance(20.0, "stop")
	if not check(menu_open(), "G-STREET: talking to %s offers a seat (no question asked; heard %s)" % [npc["id"], heard.slice(-3)]):
		return
	check_eq(menu_options().size(), 2, "G-STREET: the seat offer is yes / no: %s options" % [menu_options()])
	var stood := player_cell()
	if not await choose_index(0):
		return
	if not check(await came_true(at_table, 10.0), "G-STREET: yes opens the table"):
		return
	check_eq(state().money, 0, "G-STREET: sitting costs nothing: money")
	check_eq(table().get("cash_game"), true, "G-STREET: the table is in cash mode: cash_game")
	var setup: Array = table().get("setup")
	if not check(setup.size() >= 3, "G-STREET: you and two or more players sit (setup %d seats)" % setup.size()):
		return
	var you: Variant = setup[0].get("animal")
	check(you is Animal and (you as Animal).species == &"dog", "G-STREET: seat 0 is the dog, got %s" % you)
	check_eq(int(setup[0].get("chips", -1)), stake, "G-STREET: they front you the stake: your chips")
	if not await wait_for_hand_done(2, 300.0):
		return
	var chips := await leave_table()
	if not check(chips >= 0, "G-STREET: Start after a hand leaves the table: " + last_stop):
		return
	await advance(60.0, "cancel")
	var want := maxi(0, chips - stake)
	check_eq(state().money, want, "G-STREET: $0 + max(0, %d chips - %d stake): money" % [chips, stake])
	var disk := save_on_disk()
	if check(disk != null, "G-STREET: the save reads"):
		check_eq(disk.money, want, "G-STREET: the save has it too: money")
	check_eq(map_id(), found[0], "G-STREET: back on")
	check_eq(player_cell(), stood, "G-STREET: back where you stood:")
	check(state().roster.is_empty() and not state().met_open_table, "G-STREET: the street game isn't the open table: nobody joined (roster %d, met_open_table %s)" % [state().roster.size(), state().met_open_table])


## G-STREET: a dog with the open table's buy-in (the street game's
## max_money) or more is turned away: a line saying it's for empty
## pockets, no seat offered, no table, and the run unchanged.
func test_G_STREET_money_at_the_buy_in_is_turned_away() -> void:
	var found := _player("G-STREET")
	if found.is_empty():
		return
	var npc: Dictionary = found[1]
	var max_money := int(npc["open_table"].get("max_money", 100))
	for money in [max_money, max_money + 75]:
		if not await _in_sootbridge("G-STREET", money):  # (continue_from loads the title after writing the save)
			return
		# Walk up and face them first, so the run's "before" is where you talk.
		var target: Vector2i = npc["cell"]
		if not check(await walk_to_any(WorldPaths.talk_spots(current_map(), target), found[0]), "G-STREET: walk up to %s: %s" % [npc["id"], last_stop]):
			return
		var cell := player_cell()
		if not check(await face(Vector2i(signi(target.x - cell.x), signi(target.y - cell.y))), "G-STREET: face %s: %s" % [npc["id"], last_stop]):
			return
		var before := state().to_dict()
		var from := heard.size()
		menus.clear()
		await press("ui_accept")
		if not check(await came_true(func() -> bool: return dialog_open() or menu_open() or at_table(), 3.0), "G-STREET: A facing %s with $%d: nothing happened" % [npc["id"], money]):
			return
		await advance(20.0, "stop")
		var said := heard.slice(from)
		check(said.any(func(l: String) -> bool: return "empty pockets" in l.to_lower()), "G-STREET: $%d is turned away with a line about empty pockets; heard %s" % [money, said])
		check(menus.is_empty(), "G-STREET: $%d: no seat offered (menus %s)" % [money, menus])
		if menu_open():
			await press("ui_cancel")
			await advance(10.0, "cancel")
		check(not at_table(), "G-STREET: $%d: no table" % money)
		check_eq(state().money, money, "G-STREET: turned away: money")
		check_eq(state().to_dict(), before, "G-STREET: turned away, the run is as it was:")
