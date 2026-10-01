class_name TeamMatch
extends RefCounted
## A crew-vs-crew match: one HoldemTable, a controller per seat (a PokerBot,
## or null for the human), rising blinds, and the win condition. A team is
## out when every one of its seats is busted; if a hand limit is set and
## reached first, the team holding more chips wins.
##
## Seats alternate teams (0, 1, 0, 1, ...) by default, as at the 3v3 table.
## Boss tables seat crews unevenly; pass `teams` to set them explicitly.
##
## Heat: set `heat.dealer` to someone watching (Dealer.preset) and signals
## start to cost. This class applies what Heat decides: fines become dead
## money at the next hand's start, ejections happen when the hand ends (the
## ejected seat's chips leave the game, counted in `removed_chips`). If a
## crew's `leaders` seat is thrown out, that crew loses on the spot: catching
## the boss counts as beating them. The default dealer is nobody, which is
## also what the play styles were tuned under.

const BLIND_LEVELS := [
	[5, 10], [10, 20], [15, 30], [25, 50], [50, 100], [75, 150],
	[100, 200], [150, 300], [250, 500], [500, 1000],
]

var table := HoldemTable.new()
var bots: Array[PokerBot] = []  ## null entries are human-controlled seats
var talk := TableTalk.new()
var reads := TableReads.new()
var heat := Heat.new()
var leaders := {}  ## team -> seat; catching a leader ends the match
var removed_chips := 0  ## chips that left the game with ejected seats
var hands_per_level := 8
var max_hands := 0  ## 0 = play until one crew is out


func _init(seed_value := 0) -> void:
	if seed_value:
		# Hashed: Godot's RNG gives similar streams for similar seeds, and
		# matches seeded 1, 2, 3... came out correlated (see PokerBot).
		table.rng.seed = hash(seed_value)
	table.hand_started.connect(func(_button: int) -> void: talk.clear())
	reads.watch(table)
	heat.watch(table, talk)
	table.hand_finished.connect(func(_result: Dictionary) -> void: _apply_ejections())


func add_player(player_name: String, team: int, chips: int, bot: PokerBot) -> void:
	table.add_seat(player_name, team, chips)
	if bot:
		bot.table_reads = reads
		bot.heat = heat
	bots.append(bot)


## `stacked` sets the exact deal order (for tests), as in HoldemTable.
func start_hand(stacked: Array[int] = []) -> void:
	var level: Array = BLIND_LEVELS[mini(table.hand_number / hands_per_level, BLIND_LEVELS.size() - 1)]
	table.small_blind = level[0]
	table.big_blind = level[1]
	for team in heat.pending_fines:
		for i in table.seats.size():
			if table.seats[i].team == team and table.seats[i].stack > 0:
				table.queue_dead_money(i, table.big_blind)
	heat.pending_fines.clear()
	table.start_hand(stacked)


func _apply_ejections() -> void:
	for seat in heat.pending_ejections:
		removed_chips += table.eject(seat)
	heat.pending_ejections.clear()


## The team whose leader has been thrown out, or -1.
func caught_team() -> int:
	for team: int in leaders:
		if table.seats[leaders[team]].ejected:
			return team
	return -1


## Lets bots act until the hand ends or it's a human's turn.
func play_bots() -> void:
	while not table.hand_over and bots[table.to_act] != null:
		var seat := table.to_act
		var choice := bots[seat].decide(table, seat, talk)
		table.act(choice["action"], choice["amount"])


func waiting_on_human() -> bool:
	return not table.hand_over and bots[table.to_act] == null


func team_chips(team: int) -> int:
	var total := 0
	for s in table.seats:
		if s.team == team:
			total += s.stack + s.hand_bet
	return total


func teams_alive() -> Array[int]:
	var alive: Array[int] = []
	for s in table.seats:
		if s.stack + s.hand_bet > 0 and not alive.has(s.team):
			alive.append(s.team)
	return alive


func is_over() -> bool:
	if not table.hand_over:
		return false
	if caught_team() >= 0:
		return true
	return teams_alive().size() <= 1 or (max_hands > 0 and table.hand_number >= max_hands)


## The winning team, or -1 for a tie on chips.
func winner() -> int:
	if caught_team() >= 0:
		return 1 - caught_team()
	var alive := teams_alive()
	if alive.size() == 1:
		return alive[0]
	var a := team_chips(0)
	var b := team_chips(1)
	return 0 if a > b else (1 if b > a else -1)


## Plays an all-bot match to the end (for tests and balance runs).
func run_to_end() -> int:
	while not is_over():
		start_hand()
		play_bots()
		assert(table.hand_over, "run_to_end needs every seat to be a bot")
	return winner()
