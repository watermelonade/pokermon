class_name OpenTable
extends RefCounted
## Mossbank's open table and Sootbridge's street game, from the
## overworld's side (docs/DEMO_SPEC.md,
## G-SIT, G-LEAVE, G-CREW): talk to one of its players and you're offered
## a seat; yes takes the buy-in (CashMatch.sit_down) and opens the table in
## cash mode (TableView.cash_game) with you (the dog) and the table's
## players; leaving adds your stack back (CashMatch.cash_out); and the first
## time, Sage and Bandit ask to come along (GameState.join_open_table_crew).
## The overworld calls play() from _interact() for an npc with "open_table".
##
## A static function on the overworld rather than more of overworld.gd:
## the open table is its own little flow (offer, buy-in, table, cash-out,
## the crew joining) and the overworld file belongs to the world's work;
## this reaches into it only for what it already shows for a crew match
## (dialog, menu, the table layer, the fade, the followers), the same way
## _play_match does.
##
## Money is saved twice: right after the buy-in (so quitting at the table
## can't hand it back: a losing session could otherwise be undone by
## closing the window, the dodge _settle closed for crew matches) and after
## the cash-out. The other side of that: quitting while seated forfeits
## what's in front of you, as walking away from a real table would.
##
## The cash-out runs inside the table's `left` signal, not after it
## (demo 2.1, B-CASHOUT): it used to wait a frame for the table to go, and
## a quit in that frame (the playtester found it, seeds 6 and 18) forfeited
## a stack you had already got up with. And after the first sit Sage and
## Bandit join in that same save (B-JOINSAVE): they used to join (and be
## saved) only after the cash-out line and their own two lines, so a quit
## during those three lines left a save that had sat at the table with
## nobody along; the load put the pair back, but without the Binder's
## "Mossbank, at the open table". Now the lines only tell you what the
## save already holds.
##
## Sootbridge's street game (demo 2.1, docs/DEMO_SPEC.md S-STREET, G-STREET)
## is the same flow on the same table with other money (_play_street): it
## seats only a dog with less than the open table's buy-in, the players
## front the stake, and you keep what's above it. It's the way back for a
## dog that lost its wallet at the open table before its crew joined (the
## playtester's "stranded" dog): no crew plays a dog alone, so without it
## the demo couldn't be finished.
##
## Who sits: you, then the table's players in the map's order, each with
## the buy-in in front of them (the same stacks: a fixed-buy-in street game),
## minus anyone who has since joined your crew (Sage and Bandit leave the
## table when they come along). With fewer than two left there's no game.

const TABLE_SCENE := preload("res://scenes/table.tscn")
const MIN_RIVALS := 2


## Offers the seat, runs the table and settles up (async: await it). The
## player you talked to has its say; the refusals are narration, since any
## of them (an owl, a raccoon, a goose in capitals) may be the one asked.
## A table whose dictionary has a "stake" is Sootbridge's street game
## (_play_street); otherwise it's Mossbank's, with a buy-in.
static func play(overworld: Node, npc: Dictionary) -> void:
	var ow: Variant = overworld  # overworld.gd has no class_name to type it with
	var state: GameState = ow.state
	var t: Dictionary = npc["open_table"]
	var speaker := str(npc.get("name", str(npc["id"]).capitalize()))
	var lines: Array = npc.get("lines", [])
	if lines:
		await ow.dialog.say(lines, speaker)
	var setup := seats(state, t)
	if setup.size() < MIN_RIVALS + 1:
		await ow.dialog.say(["Too few players left at the table for a game. Maybe another day."])
		return
	if t.has("stake"):
		await _play_street(ow, state, t, setup)
		return
	var buy_in := int(t["buy_in"])
	if state.money < buy_in:
		await ow.dialog.say(["The buy-in is $%d and you have $%d. Not today." % [buy_in, state.money]])
		return
	var pick: int = await ow.menu.choose("Sit in? The buy-in is $%d." % buy_in, ["Deal me in", "Not now"], 1)
	if pick != 0 or not CashMatch.sit_down(state, buy_in):
		await ow.dialog.say(["Maybe later. The seat isn't going anywhere."])
		return
	Game.save()  # the buy-in is gone: see the top
	Game.dev_log("open table: sat down for $%d" % buy_in)
	var first := not state.met_open_table
	var joined: Array[Animal] = []
	var settle := func(chips: int) -> void:
		# The moment you get up, in the same frame (see the top): the stack
		# is banked, and after the first sit the pair join, in one save.
		CashMatch.cash_out(state, chips)
		state.met_open_table = true
		if first:
			joined.append_array(state.join_open_table_crew())
		Game.save()
		Game.dev_log("open table: left with %d (bought in for %d)" % [chips, buy_in])
	var chips: int = await _run(ow, setup, buy_in, t, settle)
	await ow.dialog.say([cash_out_line(chips, buy_in)])
	if not joined.is_empty():
		await _crew_joins(ow, joined)


## Sootbridge's street game (docs/DEMO_SPEC.md, demo 2.1): no buy-in, the
## players front you `stake` chips, and only a dog under `max_money` (the
## open table's buy-in) may sit. Getting up you keep what's above the stake
## (CashMatch.cash_out_staked), so nothing is saved on sitting down: there's
## nothing of yours on the table, and quitting there loses nothing.
static func _play_street(ow: Variant, state: GameState, t: Dictionary, setup: Array[Dictionary]) -> void:
	var stake := int(t["stake"])
	if not CashMatch.sit_staked(state, int(t["max_money"])):
		await ow.dialog.say(["This game's for empty pockets. With $%d, Mossbank's open table will have you." % state.money])
		return
	var pick: int = await ow.menu.choose("Sit in? They'll stake you %d chips." % stake, ["Deal me in", "Not now"], 1)
	if pick != 0:
		await ow.dialog.say(["Suit yourself. The crate's not going anywhere."])
		return
	Game.dev_log("street game: sat down, staked %d" % stake)
	var settle := func(chips: int) -> void:
		var kept := CashMatch.cash_out_staked(state, chips, stake)
		Game.save()
		Game.dev_log("street game: left with %d (staked %d, kept %d)" % [chips, stake, kept])
	var chips: int = await _run(ow, setup, stake, t, settle, true)
	await ow.dialog.say([street_line(chips, stake)])


## Who sits at the open table `t` (TableView.setup): you (the dog) at seat
## 0, then its players who haven't joined your crew, each its own team,
## everyone with the buy-in (or the street game's stake) in front of them.
static func seats(state: GameState, t: Dictionary) -> Array[Dictionary]:
	var chips := int(t["stake"]) if t.has("stake") else int(t["buy_in"])
	var out: Array[Dictionary] = [{"name": "You", "team": 0, "animal": Animal.make(&"dog", "You"), "chips": chips}]
	for p: Array in t["players"]:
		var a := Species.individual(p[0], p[1])
		if state.has_animal(a.species, a.name):
			continue
		out.append({"name": a.name, "team": out.size(), "animal": a, "chips": chips})
	return out


## What you're told when you get up.
static func cash_out_line(chips: int, buy_in: int) -> String:
	if chips <= 0:
		return "You're cleaned out. The $%d buy-in stays on the felt." % buy_in
	if chips > buy_in:
		return "You cash out $%d: up $%d on the buy-in." % [chips, chips - buy_in]
	if chips == buy_in:
		return "You cash out $%d, exactly what you sat down with." % chips
	return "You cash out $%d: down $%d on the buy-in." % [chips, buy_in - chips]


## The street game's line when you get up.
static func street_line(chips: int, stake: int) -> String:
	if chips > stake:
		return "You hand back their %d and keep $%d. Not bad for a crate." % [stake, chips - stake]
	if chips == stake:
		return "You hand back their %d chips. Even. Nothing won, nothing owed." % stake
	return "You're under their %d. They wave it off: you owe nothing." % stake


## The embedded table in cash mode until you leave: the chips you left with.
## Shown and freed the way _play_match does it (see overworld.gd), except
## that leaving is the table's `left` signal rather than `finished`.
## `settle` (the money, the save) runs as soon as `left` fires, in the
## same frame, before the table is even freed (B-CASHOUT: see the top).
## `staked` is the street game's table: a stake, not a buy-in, on the HUD.
static func _run(ow: Variant, setup: Array[Dictionary], buy_in: int, t: Dictionary, settle: Callable, staked := false) -> int:
	await ow._fade_out(0.2)
	var view: Control = TABLE_SCENE.instantiate()
	view.set("cash_game", true)
	view.set("staked", staked)
	view.set("embedded", true)
	view.set("buy_in", buy_in)
	view.set("starting_chips", buy_in)
	view.set("setup", setup)
	view.set("dealer_kind", int(t.get("dealer", Dealer.Kind.WATCHFUL)))
	ow.table = view
	ow.mode = ow.Mode.TABLE
	ow._hud.queue_redraw()
	ow.table_layer.add_child(view)
	var fade: ColorRect = ow.fade
	fade.color.a = 0.0
	var chips: int = await Signal(view, "left")
	settle.call(chips)  # still inside the table's left.emit: no frame in between
	# The press that left mustn't also reach the overworld (it'd talk to the
	# player in front of you), and the table stops listening before it goes.
	ow.get_viewport().set_input_as_handled()
	view.set_process_unhandled_input(false)
	view.set_process_input(false)
	view.queue_free()
	ow.table = null
	ow.mode = ow.Mode.BUSY
	await ow.get_tree().process_frame
	return chips


## After the first sit, win or lose: Sage and Bandit ask to come along
## (they joined the run, and the save, when you got up: see play). They
## leave the table's crowd and follow you.
static func _crew_joins(ow: Variant, joined: Array[Animal]) -> void:
	var names: Array[String] = []
	for a in joined:
		names.append(a.name)
		Sfx.voice(a.species)
		var hello := _ask_line(a)
		if hello:
			await ow.dialog.say([hello], a.name)
	_leave_the_table_crowd(ow, joined)
	ow._make_followers(ow.player.cell, ow.player.facing)
	Sfx.play(&"win_pot")  # until there's a proper recruit jingle
	await ow.dialog.say(["%s join your crew! Now the crews on the road will deal you in." % " and ".join(names)])


## What each of the two says when it asks to come along, in its voice
## (docs/WRITING.md); its recruit line (Bios) for anyone else.
static func _ask_line(a: Animal) -> String:
	if a.species == &"owl" and a.name == "Sage":
		return "You fold with conviction. I could make something of that. I'm coming along."
	if a.species == &"raccoon" and a.name == "Bandit":
		return "*psst* me too. a dog with no crew is a plan with no raccoon."
	return Bios.recruit_line(a.species, a.name)


## Takes the animals who just joined you off the map, where they stood
## round the table (they're following you now): the npc entries whose
## "animal" ([species, index], the map's) is one of them. (The overworld
## leaves them out when a map loads; this is for the map you're on.)
static func _leave_the_table_crowd(ow: Variant, joined: Array[Animal]) -> void:
	var nodes: Array = ow.npc_nodes
	var data: Dictionary = ow.npc_data
	for n: Variant in nodes.duplicate():
		var entry: Dictionary = data.get(n, {})
		if not entry.has("open_table"):
			continue
		for a in joined:
			if _is_animal(entry, a):
				nodes.erase(n)
				data.erase(n)
				(n as Node).queue_free()
				break


## Is this npc entry that animal?
static func _is_animal(entry: Dictionary, a: Animal) -> bool:
	var which: Array = entry.get("animal", [])
	if which.size() != 2 or StringName(which[0]) != a.species:
		return false
	return Species.individual(which[0], which[1]).name == a.name
