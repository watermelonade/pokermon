extends SceneTree
## Balance check for the type chart: plays crews of three same-style bots
## against each other and prints how often each style's crew wins.
##
##   godot --headless --path . -s tools/simulate.gd -- [matches per pairing] [seed]
##
## The design wants a cycle (Bluffer > Rock > Maniac > Shark > Calling
## Station > Bluffer, see docs/DESIGN.md). Each pairing is played with both
## crews taking turns in the team-0 seats, so seating doesn't skew it.

const K := PlayStyle.Kind
const CYCLE := [K.BLUFFER, K.ROCK, K.MANIAC, K.SHARK, K.CALLING_STATION]


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var matches := int(args[0]) if args.size() > 0 else 20
	var seed_value := int(args[1]) if args.size() > 1 else 1
	var started := Time.get_ticks_msec()
	var n := CYCLE.size()
	var wins := []
	for i in n:
		wins.append([])
		for j in n:
			wins[i].append(0.0)
	var total_hands := 0
	var played := 0
	for i in n:
		for j in range(i + 1, n):
			for k in matches:
				var swap := k % 2 == 1
				var a: int = CYCLE[j] if swap else CYCLE[i]
				var b: int = CYCLE[i] if swap else CYCLE[j]
				var m := _match(seed_value * 100003 + i * 1009 + j * 101 + k, a, b)
				var w := m.run_to_end()
				total_hands += m.table.hand_number
				played += 1
				var i_team := 1 if swap else 0
				if w == i_team:
					wins[i][j] += 1.0
				elif w == 1 - i_team:
					wins[j][i] += 1.0
				else:
					wins[i][j] += 0.5
					wins[j][i] += 0.5

	var header := "%-16s" % "row beats col"
	for j in n:
		header += "%10s" % PlayStyle.KIND_NAMES[CYCLE[j]].substr(0, 9)
	print(header)
	for i in n:
		var line := "%-16s" % PlayStyle.KIND_NAMES[CYCLE[i]]
		for j in n:
			line += "%10s" % ("-" if i == j else "%d%%" % roundi(100.0 * wins[i][j] / matches))
		print(line)
	print("\nIntended cycle (each should be > 50%):")
	for i in n:
		var j := (i + 1) % n
		print("  %-16s beats %-16s %3d%%" % [PlayStyle.KIND_NAMES[CYCLE[i]], PlayStyle.KIND_NAMES[CYCLE[j]], roundi(100.0 * wins[i][j] / matches)])
	print("\n%d matches, %.0f hands per match, %.1fs" % [played, float(total_hands) / played, (Time.get_ticks_msec() - started) / 1000.0])
	quit()


func _match(seed_value: int, team0: int, team1: int) -> TeamMatch:
	var m := TeamMatch.new(seed_value)
	for seat in 6:
		var kind := team0 if seat % 2 == 0 else team1
		var bot := PokerBot.new(PlayStyle.preset(kind), seed_value + seat * 7919)
		bot.equity_iterations = 60
		m.add_player("P%d" % seat, seat % 2, 1000, bot)
	m.max_hands = 300
	return m
