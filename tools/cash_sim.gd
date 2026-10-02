extends SceneTree
## Mossbank's open table, bot vs bot: what a session there is worth. Each
## session sits you down for the buy-in with a bot in your seat (a Shark,
## like --autoplay) against the table's players, all for themselves at
## CashMatch's fixed blinds, plays up to N hands (stopping early if you bust
## or clean the table out) and leaves. For the economy design: no target
## yet, just the number.
##
##   godot --headless --path . -s tools/cash_sim.gd -- [sessions] [hands] [seed] [flags]
##
## Defaults: 200 sessions of 20 hands, seed 1. The table is the one on
## Mossbank's map (WorldMap "town", open_tables()), with Sage and Bandit;
## without one on the map yet, owl, raccoon, goose and squirrel at $100.
##
## Flags:
##   --buy-in=100          the buy-in (default: the map's)
##   --players=owl:0,cat:1 the table's players instead (species:index)
##   --you=SHARK           your seat's style (PlayStyle.Kind name)
##
## Prints the average cash-out against the buy-in (with its standard
## error), how sessions ended (bust, cleaned out, left at the hand limit),
## and what each player at the table took home on average.
##
## Sootbridge's street game (demo 2.1), the pace from broke:
##
##   godot --headless --path . -s tools/cash_sim.gd -- --street [runs] [hands] [seed] [flags]
##
## Each run is a broke dog climbing back: from $0 it sits at the street
## game (WorldMap.STREET_GAME: a stake fronted, keep what's above it when
## you get up) session after session, a Shark bot in your seat, until its
## money reaches the table's max_money (the open table's buy-in). A session
## ends when you bust, clean the table out, have played `hands` (default
## 8), or, with --leave=up (the default), after the first hand that leaves
## you above the stake; --leave=hands plays every session to the limit.
## --stake=N tries another stake, --blinds=2/4 other blinds (default the
## table's, CashMatch.table_blinds), --players= other players. Prints, over
## the runs, the sessions and hands it took (median and the 10th and 90th
## percentiles), and the minutes that is at about 20 s a hand for a person
## (an estimate: the table's own pace with a person playing, not measured
## here), so the stake can be tuned toward docs/DESIGN.md's 10-15 minutes.

var sessions := 200
var hands := 20
var seed_base := 1
var buy_in := 0
var players: Array = []
var you_style := PlayStyle.Kind.SHARK
var street := false  ## --street: the pace from broke at Sootbridge's street game
var stake := 0  ## --stake=: the street game's stake (default the map's)
var leave_up := true  ## --leave=up: get up after the first hand above the stake
var blinds_flag: Array[int] = []  ## --blinds=1/2: the street game's blinds instead of the stake's
const SECONDS_A_HAND := 20.0  ## a person's pace at the table: an estimate, see the top


func _init() -> void:
	var plain: Array[String] = []
	for arg in OS.get_cmdline_user_args():
		if arg == "--street":
			street = true
		elif arg.begins_with("--stake="):
			stake = int(arg.get_slice("=", 1))
		elif arg.begins_with("--blinds="):
			blinds_flag = [int(arg.get_slice("=", 1).get_slice("/", 0)), int(arg.get_slice("=", 1).get_slice("/", 1))]
		elif arg.begins_with("--leave="):
			leave_up = arg.get_slice("=", 1) == "up"
		elif arg.begins_with("--buy-in="):
			buy_in = int(arg.get_slice("=", 1))
		elif arg.begins_with("--players="):
			for p in arg.get_slice("=", 1).split(","):
				players.append([StringName(p.get_slice(":", 0)), int(p.get_slice(":", 1))])
		elif arg.begins_with("--you="):
			you_style = PlayStyle.Kind.keys().find(arg.get_slice("=", 1)) as PlayStyle.Kind
		elif not arg.begins_with("--"):
			plain.append(arg)
	if plain.size() > 0:
		sessions = int(plain[0])
	if plain.size() > 1:
		hands = int(plain[1])
	if plain.size() > 2:
		seed_base = int(plain[2])
	if street:
		if plain.size() < 2:
			hands = 8
		_run_street()
		quit()
		return
	var table := {}
	var seated := WorldMap.get_map("town").open_tables()
	if not seated.is_empty():
		table = seated[0]["open_table"]
	if players.is_empty():
		players = table.get("players", [[&"owl", 0], [&"raccoon", 0], [&"goose", 0], [&"squirrel", 0]])
	if buy_in <= 0:
		buy_in = int(table.get("buy_in", 100))
	_run()
	quit()


func _run() -> void:
	var blinds := CashMatch.blinds_for(buy_in)
	var names: Array[String] = ["You (%s)" % PlayStyle.Kind.keys()[you_style].capitalize()]
	for p: Array in players:
		var a := Species.individual(p[0], p[1])
		names.append("%s (%s)" % [a.name, PlayStyle.KIND_NAMES[a.style_kind()]])
	print("Open table: %d sessions of up to %d hands, $%d buy-in, blinds %d/%d, seed %d" % [sessions, hands, buy_in, blinds[0], blinds[1], seed_base])
	print("  at the table: %s" % ", ".join(names))
	var outs: Array[float] = []
	var totals: Array[float] = []
	totals.resize(players.size() + 1)
	totals.fill(0.0)
	var ended := {"bust": 0, "cleaned out": 0, "hand limit": 0}
	var hands_played := 0
	for k in sessions:
		var session_seed := seed_base * 100003 + k
		var m := CashMatch.new(session_seed)
		m.set_blinds(blinds[0], blinds[1])
		m.add_player("You", buy_in, PokerBot.new(PlayStyle.preset(you_style), session_seed * 31 + 1))
		for i in players.size():
			var a := Species.individual(players[i][0], players[i][1])
			m.add_player(a.name, buy_in, a.make_bot(session_seed * 31 + i + 2))
		for _h in hands:
			if m.is_over():
				break
			m.start_hand()
			m.play_bots()
			assert(m.table.hand_over, "every seat is a bot")
		hands_played += m.table.hand_number
		var stack := m.table.seats[0].stack
		if stack == 0:
			ended["bust"] += 1
		elif m.is_over():
			ended["cleaned out"] += 1
		else:
			ended["hand limit"] += 1
		var took := m.leave()
		outs.append(took)
		for i in m.table.seats.size():
			totals[i] += m.table.seats[i].stack
	var mean := 0.0
	for x in outs:
		mean += x
	mean /= outs.size()
	var variance := 0.0
	for x in outs:
		variance += (x - mean) * (x - mean)
	var se := sqrt(variance / maxf(1.0, outs.size() - 1.0) / outs.size())
	print("  your average cash-out: %.1f on a %d buy-in (%+.1f%%, +-%.1f standard error), %.1f hands a session" % [mean, buy_in, (mean - buy_in) * 100.0 / buy_in, se * 100.0 / buy_in, hands_played / float(sessions)])
	print("  sessions ended: %d bust, %d cleaned the table out, %d left after %d hands" % [ended["bust"], ended["cleaned out"], ended["hand limit"], hands])
	for i in names.size():
		print("    %-22s %7.1f average (%+.1f%%)" % [names[i], totals[i] / sessions, (totals[i] / sessions - buy_in) * 100.0 / buy_in])


## The street game's pace (see the top): `sessions` runs from $0 to the
## table's max_money, each session up to `hands` hands.
func _run_street() -> void:
	var t: Dictionary = WorldMap.STREET_GAME
	if players.is_empty():
		players = t["players"]
	if stake <= 0:
		stake = int(t["stake"])
	var target := int(t["max_money"])
	var blinds := blinds_flag if blinds_flag.size() == 2 else CashMatch.table_blinds(t)
	var names: Array[String] = ["You (%s)" % PlayStyle.Kind.keys()[you_style].capitalize()]
	for p: Array in players:
		var a := Species.individual(p[0], p[1])
		names.append("%s (%s)" % [a.name, PlayStyle.KIND_NAMES[a.style_kind()]])
	print("Street game: %d runs from $0 to $%d, stake %d, blinds %d/%d, up to %d hands a session%s, seed %d" % [sessions, target, stake,
		blinds[0], blinds[1], hands, ", leaving once above the stake" if leave_up else "", seed_base])
	print("  at the table: %s" % ", ".join(names))
	var run_hands: Array[int] = []
	var run_sessions: Array[int] = []
	var busts := 0
	var all_sessions := 0
	var kept_total := 0
	for r in sessions:
		var money := 0
		var played := 0
		var k := 0
		while money < target and k < 1000:
			var session_seed := (seed_base * 100003 + r) * 1009 + k
			var m := CashMatch.new(session_seed)
			m.set_blinds(blinds[0], blinds[1])
			m.add_player("You", stake, PokerBot.new(PlayStyle.preset(you_style), session_seed * 31 + 1))
			for i in players.size():
				var a := Species.individual(players[i][0], players[i][1])
				m.add_player(a.name, stake, a.make_bot(session_seed * 31 + i + 2))
			for _h in hands:
				if m.is_over():
					break
				m.start_hand()
				m.play_bots()
				if leave_up and m.table.seats[0].stack > stake:
					break
			played += m.table.hand_number
			var chips := m.leave()
			if chips == 0:
				busts += 1
			var kept := maxi(0, chips - stake)
			kept_total += kept
			money += kept
			k += 1
		run_hands.append(played)
		run_sessions.append(k)
		all_sessions += k
	run_hands.sort()
	run_sessions.sort()
	var n := run_hands.size()
	var pct := func(a: Array[int], q: float) -> int: return a[mini(n - 1, int(q * n))]
	print("  sessions to $%d: median %d (10th-90th percentile %d-%d)" % [target, pct.call(run_sessions, 0.5), pct.call(run_sessions, 0.1), pct.call(run_sessions, 0.9)])
	print("  hands: median %d (%d-%d), so about %.0f minutes (%.0f-%.0f) at %.0f s a hand" % [pct.call(run_hands, 0.5), pct.call(run_hands, 0.1), pct.call(run_hands, 0.9),
		pct.call(run_hands, 0.5) * SECONDS_A_HAND / 60.0, pct.call(run_hands, 0.1) * SECONDS_A_HAND / 60.0, pct.call(run_hands, 0.9) * SECONDS_A_HAND / 60.0, SECONDS_A_HAND])
	print("  a session: %.1f hands, $%.1f kept on average, %.0f%% busted" % [float(run_hands.reduce(func(a: int, b: int) -> int: return a + b, 0)) / all_sessions,
		float(kept_total) / all_sessions, busts * 100.0 / all_sessions])
