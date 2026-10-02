class_name CashMatch
extends RefCounted
## A cash game: Mossbank's open table (docs/DEMO_SPEC.md, S-CASH and
## S-BUYIN). You and 2-5 others, every seat on its own team, one
## HoldemTable. You can leave between any two hands with what's in front of
## you; a rival who busts leaves the table; the match is over when you
## bust, leave, or are the last one with chips. Seat 0 is you (the first
## player added, as at TableView's tables).
##
## Built on a TeamMatch (`crew_match`) with one team per seat rather than
## as a second match class beside it: the table scene already drives a
## TeamMatch (its talk, reads, Heat and bots), so in cash mode it drives
## this one's and asks CashMatch only what differs: the blinds, who has
## left, and when it's over. With no two seats on a team PokerBot's team
## play never starts (no teammates: no soft play, no signals, nobody to
## step aside for), so the bots need no cash mode of their own, and
## nothing about TeamMatch or PokerBot changed for the crew matches (R-CHART
## is untouched).
##
## Blinds are fixed, not rising: a cash game has no clock pushing it to a
## finish the way a crew match's levels do (you leave when you like), and
## fixed stakes make the buy-in mean something: a $100 seat is always 50 big
## blinds deep. `blinds_for(buy_in)` sets them at BUY_IN_BIGS big blinds to
## the buy-in (a short, quick street game; a card room's 100 would mean a lot
## of folding for every hand that matters). The default, before anyone
## picks, is HoldemTable's 5/10.
##
## Leaving keeps your chips on your seat (marked left, never dealt in again)
## rather than taking them off the table, so total_chips() still counts
## every chip that sat down: the conservation the tests check is the
## table's own sum. A busted rival likewise stays in its seat, at 0, marked
## left; HoldemTable never deals a seat with no chips, so it simply sits out.
##
## Money: sitting down takes a fixed buy-in from your money (sit_down) and
## leaving puts your stack back (cash_out), so money after = money before -
## buy-in + stack at leaving.

const YOU := 0
## The buy-in in big blinds (see the top): a $100 seat plays 1/2.
const BUY_IN_BIGS := 50

var crew_match: TeamMatch  ## the match underneath, one team per seat (see the top)
var table: HoldemTable  ## the rules, as TeamMatch.table (the same object)
var bots: Array[PokerBot] = []  ## null for a seat the caller plays (you); TeamMatch's own array
var small_blind := 5
var big_blind := 10
var _you_left := false


func _init(seed_value := 0) -> void:
	crew_match = TeamMatch.new(seed_value)
	table = crew_match.table
	bots = crew_match.bots


## The blinds for a seat that costs `buy_in`: [small, big], the big blind
## BUY_IN_BIGS to the buy-in (at least 2), the small half of it.
static func blinds_for(buy_in: int) -> Array[int]:
	var bb := maxi(2, roundi(buy_in / float(BUY_IN_BIGS)))
	return [maxi(1, bb / 2), bb]


## Fixes the blinds for every hand from now on.
func set_blinds(small: int, big: int) -> void:
	small_blind = small
	big_blind = big


## Seats a player on its own team with `chips`; `bot` null for you.
func add_player(player_name: String, chips: int, bot: PokerBot) -> void:
	crew_match.add_player(player_name, table.seats.size(), chips, bot)


## Deals the next hand at the fixed blinds; `stacked` sets the exact deal
## order (for tests). Does nothing mid-hand or once the match is over.
func start_hand(stacked: Array[int] = []) -> void:
	if is_over() or not table.hand_over:
		return
	table.small_blind = small_blind
	table.big_blind = big_blind
	table.start_hand(stacked)


## Lets bots act until the hand ends or it's your turn.
func play_bots() -> void:
	crew_match.play_bots()


## True between hands (and only then), while you're still seated.
func can_leave() -> bool:
	return table.hand_over and not _you_left


## Stands you up with your stack and ends the match: returns the chips you
## leave with. Mid-hand (or once you've left) it refuses: -1, nothing changes.
func leave() -> int:
	if not can_leave():
		return -1
	_you_left = true
	return table.seats[YOU].stack


## You busted, left, or nobody else has chips. Never mid-hand.
func is_over() -> bool:
	if not table.hand_over:
		return false
	if _you_left or table.seats[YOU].stack == 0:
		return true
	for i in range(1, table.seats.size()):
		if table.seats[i].stack > 0:
			return false
	return true


## True once `seat` has left the table: you, after leave(); a rival, once
## a hand has ended with it out of chips (all in mid-hand isn't gone yet).
func seat_left(seat: int) -> bool:
	if seat == YOU:
		return _you_left
	var s := table.seats[seat]
	return s.stack == 0 and s.hand_bet == 0


## Takes the buy-in from your money: false (and nothing taken) if you
## can't cover it.
static func sit_down(state: GameState, buy_in: int) -> bool:
	if buy_in <= 0 or state.money < buy_in:
		return false
	state.money -= buy_in
	return true


## Adds the chips you left the table with to your money.
static func cash_out(state: GameState, chips: int) -> void:
	state.money += maxi(0, chips)


## Sootbridge's street game (docs/DEMO_SPEC.md S-STREET): stub until it's
## built. Whether a dog with this much money may sit (only under
## `max_money`); takes nothing either way.
static func sit_staked(_state: GameState, _max_money: int) -> bool:
	return false


## Street game stub: adds what's above the stake to your money, returns it.
static func cash_out_staked(_state: GameState, _chips: int, _stake: int) -> int:
	return 0
