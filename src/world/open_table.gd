class_name OpenTable
extends RefCounted
## Mossbank's open table, from the overworld's side (docs/DEMO_SPEC.md,
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
## Who sits: you, then the table's players in the map's order, each with
## the buy-in in front of them (the same stacks: a fixed-buy-in street game),
## minus anyone who has since joined your crew (Sage and Bandit leave the
## table when they come along). With fewer than two left there's no game.

const TABLE_SCENE := preload("res://scenes/table.tscn")
const MIN_RIVALS := 2


## Offers the seat, runs the table and settles up (async: await it).
static func play(overworld: Node, npc: Dictionary) -> void:
	var ow: Variant = overworld  # overworld.gd has no class_name to type it with
	var state: GameState = ow.state
	var t: Dictionary = npc["open_table"]
	var buy_in := int(t["buy_in"])
	var speaker := str(npc.get("name", str(npc["id"]).capitalize()))
	var lines: Array = npc.get("lines", [])
	if lines:
		await ow.dialog.say(lines, speaker)
	var setup := seats(state, t)
	if setup.size() < MIN_RIVALS + 1:
		await ow.dialog.say(["Not enough of us left for a game. Another time."], speaker)
		return
	if state.money < buy_in:
		await ow.dialog.say(["It's $%d to sit in, and you've got $%d. Come back flush, pup." % [buy_in, state.money]], speaker)
		return
	var pick: int = await ow.menu.choose("Sit in? The buy-in is $%d." % buy_in, ["Deal me in", "Not now"], 1)
	if pick != 0 or not CashMatch.sit_down(state, buy_in):
		await ow.dialog.say(["Suit yourself. The seat's here when you want it."], speaker)
		return
	Game.save()  # the buy-in is gone: see the top
	Game.dev_log("open table: sat down for $%d" % buy_in)
	var chips: int = await _run(ow, setup, buy_in, t)
	CashMatch.cash_out(state, chips)
	var first := not state.met_open_table
	state.met_open_table = true
	Game.save()
	Game.dev_log("open table: left with %d (bought in for %d)" % [chips, buy_in])
	await ow.dialog.say([cash_out_line(chips, buy_in)])
	if first:
		await _crew_joins(ow, state)


## Who sits at the open table `t` (TableView.setup): you (the dog) at seat
## 0, then its players who haven't joined your crew, each its own team.
static func seats(state: GameState, t: Dictionary) -> Array[Dictionary]:
	var buy_in := int(t["buy_in"])
	var out: Array[Dictionary] = [{"name": "You", "team": 0, "animal": Animal.make(&"dog", "You"), "chips": buy_in}]
	for p: Array in t["players"]:
		var a := Species.individual(p[0], p[1])
		if state.has_animal(a.species, a.name):
			continue
		out.append({"name": a.name, "team": out.size(), "animal": a, "chips": buy_in})
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


## The embedded table in cash mode until you leave: the chips you left with.
## Shown and freed the way _play_match does it (see overworld.gd), except
## that leaving is the table's `left` signal rather than `finished`.
static func _run(ow: Variant, setup: Array[Dictionary], buy_in: int, t: Dictionary) -> int:
	await ow._fade_out(0.2)
	var view: Control = TABLE_SCENE.instantiate()
	view.set("cash_game", true)
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


## After the first sit, win or lose: Sage and Bandit ask to come along.
## They leave the table's crowd and follow you.
static func _crew_joins(ow: Variant, state: GameState) -> void:
	var joined := state.join_open_table_crew()
	if joined.is_empty():
		return
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
	Game.save()
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
## round the table (they're following you now). An npc entry is theirs if
## its sprite is their species and it names them.
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


## Is this npc entry that animal (by its name or id, and its sprite)?
static func _is_animal(entry: Dictionary, a: Animal) -> bool:
	if str(entry.get("sprite", "")) != String(a.species):
		return false
	var who := (str(entry.get("name", "")) + " " + str(entry.get("id", ""))).to_lower()
	return a.name.to_lower() in who
