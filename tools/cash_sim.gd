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

var sessions := 200
var hands := 20
var seed_base := 1
var buy_in := 0
var players: Array = []
var you_style := PlayStyle.Kind.SHARK


func _init() -> void:
	var plain: Array[String] = []
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--buy-in="):
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
