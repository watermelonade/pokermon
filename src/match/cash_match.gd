class_name CashMatch
extends RefCounted
## A cash game: Mossbank's open table (docs/DEMO_SPEC.md, S-CASH and
## S-BUYIN). You and 2-5 others, every seat on its own team, one
## HoldemTable. You can leave between any two hands with what's in front of
## you; a rival who busts leaves the table; the match is over when you
## bust, leave, or are the last one with chips. Seat 0 is you (the first
## player added, as at TableView's tables).
##
## Money: sitting down takes a fixed buy-in from your money (sit_down) and
## leaving puts your stack back (cash_out), so money after = money before -
## buy-in + stack at leaving.
##
## STUB (demo 2): the open-table agent builds this. Every function here
## returns a "not built" value so tests/test_cash_match.gd is red until
## then; the names and signatures are fixed (the spec's "Interfaces fixed up
## front", plus `table`, `start_hand(stacked)`, `sit_down` and `cash_out`,
## which the tests needed: see the spec's "Test decisions").

var table := HoldemTable.new()  ## the rules, as TeamMatch.table
var bots: Array[PokerBot] = []  ## null for a seat the caller plays (you)


func _init(_seed_value := 0) -> void:
	pass


## Seats a player on its own team with `chips`; `bot` null for you.
## STUB (demo 2): the open-table agent fills it in.
func add_player(_player_name: String, _chips: int, _bot: PokerBot) -> void:
	pass


## Deals the next hand; `stacked` sets the exact deal order (for tests).
## STUB (demo 2): the open-table agent fills it in.
func start_hand(_stacked: Array[int] = []) -> void:
	pass


## Lets bots act until the hand ends or it's your turn.
## STUB (demo 2): the open-table agent fills it in.
func play_bots() -> void:
	pass


## True between hands (and only then), while you're still seated.
## STUB (demo 2): the open-table agent fills it in.
func can_leave() -> bool:
	return false


## Stands you up with your stack and ends the match: returns the chips you
## leave with. Mid-hand it refuses: -1, nothing changes.
## STUB (demo 2): the open-table agent fills it in.
func leave() -> int:
	return -1


## You busted, left, or nobody else has chips.
## STUB (demo 2): the open-table agent fills it in.
func is_over() -> bool:
	return false


## True once `seat` has left the table (a rival busted, or you left).
## STUB (demo 2): the open-table agent fills it in.
func seat_left(_seat: int) -> bool:
	return false


## Takes the buy-in from your money: false (and nothing taken) if you
## can't cover it.
## STUB (demo 2): the open-table agent fills it in.
static func sit_down(_state: GameState, _buy_in: int) -> bool:
	return false


## Adds the chips you left the table with to your money.
## STUB (demo 2): the open-table agent fills it in.
static func cash_out(_state: GameState, _chips: int) -> void:
	pass
