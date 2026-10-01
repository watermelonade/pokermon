extends SceneTree
## Balance check for the type chart: plays crews of three same-style bots
## against each other and prints how often each style's crew wins.
##
##   godot --headless --path . -s tools/simulate.gd -- [matches per pairing] [seed] [flags]
##
## The design wants a cycle (Bluffer > Rock > Maniac > Shark > Calling
## Station > Bluffer, see docs/DESIGN.md). Each pairing is played with both
## crews taking turns in the team-0 seats, so seating doesn't skew it.
##
## Flags:
##   --cycle              play only the five pairings in the cycle (faster)
##   --pairs=MANIAC-SHARK,ROCK-MANIAC   play only these pairings
##   --iterations=60      equity samples per decision (default: the game's,
##                        PokerBot.equity_iterations); 60 is twice as fast
##                        for exploring, but verify at the game's setting
##   --styles=file.json   try other numbers without editing play_style.gd:
##                        {"ROCK": {"tightness": 1.5}, "SHARK": {...}}
##   --dealer=STRICT      who's watching (default STREET: nobody, which is
##                        what the styles were tuned under); see Dealer

const K := PlayStyle.Kind
const CYCLE := [K.BLUFFER, K.ROCK, K.MANIAC, K.SHARK, K.CALLING_STATION]


var overrides := {}
var iterations := 0
var dealer := Dealer.Kind.STREET


func _init() -> void:
	var args: Array[String] = []
	var cycle_only := false
	var pairs := {}
	for arg in OS.get_cmdline_user_args():
		if arg == "--cycle":
			cycle_only = true
		elif arg.begins_with("--pairs="):
			for pair in arg.get_slice("=", 1).split(","):
				var a := CYCLE.find(PlayStyle.Kind.keys().find(pair.get_slice("-", 0)))
				var b := CYCLE.find(PlayStyle.Kind.keys().find(pair.get_slice("-", 1)))
				pairs[Vector2i(mini(a, b), maxi(a, b))] = true
			cycle_only = true
		elif arg.begins_with("--dealer="):
			dealer = Dealer.Kind.keys().find(arg.get_slice("=", 1)) as Dealer.Kind
		elif arg.begins_with("--iterations="):
			iterations = int(arg.get_slice("=", 1))
		elif arg.begins_with("--styles="):
			overrides = JSON.parse_string(FileAccess.get_file_as_string(arg.get_slice("=", 1)))
		else:
			args.append(arg)
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
			if pairs and not pairs.has(Vector2i(i, j)):
				continue
			if cycle_only and not pairs and j != i + 1 and not (i == 0 and j == n - 1):
				continue
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

	if cycle_only:
		_print_cycle(wins, matches, total_hands, played, started)
		quit()
		return
	var header := "%-16s" % "row beats col"
	for j in n:
		header += "%10s" % PlayStyle.KIND_NAMES[CYCLE[j]].substr(0, 9)
	print(header)
	for i in n:
		var line := "%-16s" % PlayStyle.KIND_NAMES[CYCLE[i]]
		for j in n:
			line += "%10s" % ("-" if i == j else "%d%%" % roundi(100.0 * wins[i][j] / matches))
		print(line)
	_print_cycle(wins, matches, total_hands, played, started)
	quit()


func _print_cycle(wins: Array, matches: int, total_hands: int, played: int, started: int) -> void:
	print("\nIntended cycle (each should be > 50%):")
	for i in CYCLE.size():
		var j := (i + 1) % CYCLE.size()
		if wins[i][j] + wins[j][i] == 0:
			continue
		print("  %-16s beats %-16s %3d%%" % [PlayStyle.KIND_NAMES[CYCLE[i]], PlayStyle.KIND_NAMES[CYCLE[j]], roundi(100.0 * wins[i][j] / matches)])
	print("\n%d matches, %.0f hands per match, %.1fs" % [played, float(total_hands) / played, (Time.get_ticks_msec() - started) / 1000.0])


func _style(kind: int) -> PlayStyle:
	var style := PlayStyle.preset(kind)
	var key: String = PlayStyle.Kind.keys()[kind]
	for param: String in overrides.get(key, {}):
		style.set(param, overrides[key][param])
	return style


func _match(seed_value: int, team0: int, team1: int) -> TeamMatch:
	var m := TeamMatch.new(seed_value)
	m.heat.dealer = Dealer.preset(dealer)
	for seat in 6:
		var kind := team0 if seat % 2 == 0 else team1
		var bot := PokerBot.new(_style(kind), seed_value + seat * 7919)
		if iterations > 0:
			bot.equity_iterations = iterations
		m.add_player("P%d" % seat, seat % 2, 1000, bot)
	m.max_hands = 300
	return m
