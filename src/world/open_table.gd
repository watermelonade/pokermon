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
## STUB (demo 2): the open-table agent builds this; it does nothing yet.


## Offers the seat, runs the table and settles up (async: await it).
## STUB (demo 2): the open-table agent fills it in.
static func play(_overworld: Node, _npc: Dictionary) -> void:
	pass
