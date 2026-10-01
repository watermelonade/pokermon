class_name TableReads
extends RefCounted
## What a watchful player can learn about each seat over a match: how often
## it raises again when someone has already bet into it. A Maniac does that
## constantly; a Bluffer fires once and gives up when resisted.
##
## Bots with the `reads` style stat use it to stop respecting bets from a
## seat that never backs down. That's how the patient Rock beats the Maniac
## while still folding to the Bluffer: before reads, the Rock lost to the
## Maniac 31-37% whatever its other numbers were, because folding medium
## hands to bets (which the Bluffer link needs) also handed the Maniac every
## pot it raised.

var faced := {}  ## seat -> times it acted while facing a bet
var reraised := {}  ## seat -> times it raised while facing a bet
var _table: HoldemTable
var _level := 0  ## bet to beat on this street, before the latest action


func watch(table: HoldemTable) -> void:
	_table = table
	table.hand_started.connect(func(_button: int) -> void: _level = table.big_blind)
	table.street_dealt.connect(func(_street: int, _board: Array) -> void: _level = 0)
	table.action_taken.connect(_on_action)


func _on_action(seat: int, action: int, amount: int) -> void:
	var baseline := _table.big_blind if _table.street == HoldemTable.Street.PREFLOP else 0
	if _level > baseline and action != HoldemTable.Action.CHECK:
		faced[seat] = faced.get(seat, 0) + 1
		if action == HoldemTable.Action.RAISE:
			reraised[seat] = reraised.get(seat, 0) + 1
	if action == HoldemTable.Action.RAISE:
		_level = maxi(_level, amount)


## How often `seat` re-raises when bet into, with a prior of 1 in 5 so a
## couple of hands don't swing it.
func reraise_rate(seat: int) -> float:
	return (reraised.get(seat, 0) + 1.0) / (faced.get(seat, 0) + 5.0)
