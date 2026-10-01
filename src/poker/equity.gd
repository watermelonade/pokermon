class_name Equity
extends RefCounted
## Monte Carlo estimate of a hand's share of the pot against N unknown hands:
## deal the opponents and the rest of the board at random many times and
## count wins (ties pay a fraction). This is what the AI "feels" about its
## cards. It's deliberately simple: opponents are treated as random hands,
## and play styles, reads and signals adjust the bot's behaviour on top.
##
## Cost is iterations * (opponents + 1) evaluations; 150 iterations is
## plenty for a bot that's meant to be beatable (about +-4% at worst).


## `dead`: other cards known to be out of play (a boss crew's teammates'
## hands, PokerBot.knows_crew_cards); with none it draws exactly as before.
static func estimate(hole: Array, board: Array, opponents: int, iterations: int, rng: RandomNumberGenerator, dead: Array = []) -> float:
	if opponents <= 0:
		return 1.0
	var known := {}
	for c: int in hole + board + dead:
		known[c] = true
	var pool: Array[int] = []
	for c in 52:
		if not known.has(c):
			pool.append(c)

	var board_needed := 5 - board.size()
	var needed := opponents * 2 + board_needed
	var total := 0.0
	for _i in iterations:
		# Partial Fisher-Yates: only shuffle the cards we're about to use.
		for k in needed:
			var j := rng.randi_range(k, pool.size() - 1)
			var t := pool[k]
			pool[k] = pool[j]
			pool[j] = t
		var run_out := board.duplicate()
		for k in board_needed:
			run_out.append(pool[opponents * 2 + k])
		var hero_score := HandEvaluator.evaluate(hole + run_out)
		var tied := 1
		var lost := false
		for o in opponents:
			var score := HandEvaluator.evaluate([pool[o * 2], pool[o * 2 + 1]] + run_out)
			if score > hero_score:
				lost = true
				break
			if score == hero_score:
				tied += 1
		if not lost:
			total += 1.0 / tied
	return total / iterations
