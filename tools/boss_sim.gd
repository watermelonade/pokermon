extends SceneTree
## Boss tables, bot vs bot: how often a crew like yours beats a boss crew,
## how often the boss leader is the first of its crew to bust, and what a
## bought dealer changes. Each match is set up the way the game sets up
## yours (BossTable.setup: the rigged seat draw, the leader's big stack and
## the goons' short ones; interception on, as at every table you play), with
## a bot in your seat (a Shark, like --autoplay).
##
##   godot --headless --path . -s tools/boss_sim.gd -- [matches per crew] [seed] [flags]
##
## Flags:
##   --vs=mossbank_regulars   the boss crew, by WorldMap crew id (default:
##                            the Open's final); --vs=road plays each road
##                            crew instead, 3v3 at the same chips and no hand
##                            cap (the comparison: "harder than a road crew")
##   --boss=5                 a made-up boss crew of this size (3v5, 3v6):
##                            the Regulars plus goons from --goons
##   --goons=cat:3,goose:2    the extra goons (species:index; default as the
##                            table's --boss=N: Pudding the possum, Pip the owl)
##   --dealer=BOUGHT          who's watching (default: the crew's own dealer;
##                            BOUGHT looks away from the boss crew)
##   --fair                   a fair seat draw instead of the boss's rigged one
##   --crews=all              your side: the starters only (default) or a mix
##                            of decent crews (see CREWS)
##   --no-crew-cards          the boss crew doesn't play as one (each member
##                            on its own cards, PokerBot.knows_crew_cards)
##   --edge=1.2               the boss crew's chips over yours (BossTable)
##   --no-interception        nobody reads anybody's signals
##   --shares=2               the leader's chips in goon shares (BossTable)
##   --chips=1000             your seats' chips (the Open's)
##   --members=cat:3,owl:2  the boss crew's animals instead (species:index,
##                            leader first), for trying other line-ups
##   --boss-bond=0.9          the boss crew's bond (how well they read each
##                            other; default the crew's own)
##
## Prints, per crew of yours and overall: your win rate (with its standard
## error), how often the boss leader busted, busted first of its crew, or was
## caught by the floor, hands a match, the boss crew's signals a match and the
## share your crew noticed, and ejections.

const K := PlayStyle.Kind
## Your side's mixes: your seat is always a Shark bot (what --autoplay
## plays). "starters" is what a new game sits down with.
const CREWS := {
	"starters": [&"owl", &"raccoon"],
	"cat+goose": [&"cat", &"goose"],
	"possum+squirrel": [&"possum", &"squirrel"],
	"raccoon+goose": [&"raccoon", &"goose"],
	"owl+cat": [&"owl", &"cat"],
}
const ROAD := ["pond_hecklers", "alley_cats", "nut_club", "night_shift"]
## Extra goons past the Regulars' four, as the table's --boss=N seats them
## (TableView.boss_setup): Pudding, then Pip.
const DEFAULT_GOONS := [[&"possum", 2], [&"owl", 3]]

var dealer := -1
var rigged := true
var interception := true
var shares := BossTable.LEADER_SHARES
var chips := 1000
var boss_size := 0
var goons: Array = DEFAULT_GOONS
var boss_bond := -1.0
var members: Array = []
var edge := BossTable.CHIP_EDGE
var crew_cards := true


func _init() -> void:
	var args: Array[String] = []
	var vs := "mossbank_regulars"
	var crews := ["starters"]
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--vs="):
			vs = arg.get_slice("=", 1)
		elif arg.begins_with("--boss="):
			boss_size = int(arg.get_slice("=", 1))
		elif arg.begins_with("--goons="):
			goons = []
			for g in arg.get_slice("=", 1).split(","):
				goons.append([StringName(g.get_slice(":", 0)), int(g.get_slice(":", 1))])
		elif arg.begins_with("--dealer="):
			dealer = Dealer.Kind.keys().find(arg.get_slice("=", 1))
		elif arg == "--fair":
			rigged = false
		elif arg == "--no-crew-cards":
			crew_cards = false
		elif arg.begins_with("--edge="):
			edge = float(arg.get_slice("=", 1))
		elif arg == "--no-interception":
			interception = false
		elif arg.begins_with("--crews="):
			crews = CREWS.keys() if arg.get_slice("=", 1) == "all" else Array(arg.get_slice("=", 1).split(","))
		elif arg.begins_with("--shares="):
			shares = int(arg.get_slice("=", 1))
		elif arg.begins_with("--members="):
			for m in arg.get_slice("=", 1).split(","):
				members.append([StringName(m.get_slice(":", 0)), int(m.get_slice(":", 1))])
		elif arg.begins_with("--boss-bond="):
			boss_bond = float(arg.get_slice("=", 1))
		elif arg.begins_with("--chips="):
			chips = int(arg.get_slice("=", 1))
		else:
			args.append(arg)
	var matches := int(args[0]) if args.size() > 0 else 40
	var seed_value := int(args[1]) if args.size() > 1 else 1
	var started := Time.get_ticks_msec()
	var opponents: Array = ROAD if vs == "road" else [vs]
	print("%d matches per crew, seed %d, %s, dealer %s, %s draw, interception %s, leader %d shares, edge %.2f, %d chips" % [
		matches, seed_value, "road crews (3v3)" if vs == "road" else vs + (" at 3v%d" % boss_size if boss_size else ""),
		"(each crew's own)" if dealer < 0 else Dealer.Kind.keys()[dealer], "rigged" if rigged else "fair",
		"on" if interception else "off", shares, edge, chips])
	var all := _tally()
	for crew_name: String in crews:
		var t := _tally()
		for opp: String in opponents:
			for k in matches:
				var s := seed_value * 100003 + hash(crew_name + opp) % 10007 * 1009 + k
				_play(s, CREWS[crew_name], _crew(opp), vs == "road", t)
		_print(crew_name, t)
		for key: String in t:
			all[key] += t[key]
	if crews.size() > 1:
		_print("all", all)
	print("%.1fs" % ((Time.get_ticks_msec() - started) / 1000.0))
	quit()


func _crew(id: String) -> Dictionary:
	for map_id: String in WorldMap.ids():
		for c: Dictionary in WorldMap.get_map(map_id).crews:
			if c["id"] == id:
				var out := c.duplicate()
				if members and c.has("bracelet"):
					out["members"] = members
				if boss_bond >= 0.0 and c.has("bracelet"):
					out["bond"] = boss_bond
				if boss_size and c.has("bracelet"):
					var line_up: Array = c["members"].duplicate()
					var k := 0
					while line_up.size() < boss_size:
						line_up.append(goons[k % goons.size()])
						k += 1
					out["members"] = line_up
				return out
	push_error("no crew %s" % id)
	quit(1)
	return {}


func _tally() -> Dictionary:
	return {"matches": 0, "won": 0.0, "hands": 0, "leader_busted": 0, "leader_first": 0, "caught": 0,
		"boss_signals": 0, "boss_noticed": 0, "your_ejected": 0, "boss_ejected": 0, "leaderless_hands": 0}


func _play(seed_value: int, mates: Array, crew: Dictionary, road: bool, t: Dictionary) -> void:
	var mine: Array[Dictionary] = [{"name": "You", "animal": null}]
	for species: StringName in mates:
		mine.append({"name": String(species), "animal": Species.individual(species, 0, 0.5)})
	var rivals: Array[Dictionary] = []
	for a in WorldMap.crew_animals(crew):
		rivals.append({"name": a.name, "animal": a})
	var setup: Array[Dictionary]
	if road:
		setup = []
		for i in 3:
			var me := mine[i].duplicate()
			me["team"] = 0
			setup.append(me)
			var them := rivals[i].duplicate()
			them["team"] = 1
			setup.append(them)
	else:
		setup = BossTable.setup(mine, rivals, chips, rigged, crew["id"], shares, edge)
	var m := TeamMatch.new(seed_value)
	var kind: int = crew["dealer"] if dealer < 0 else dealer
	m.heat.dealer = Dealer.preset(kind as Dealer.Kind, 1)
	for i in setup.size():
		var animal: Animal = setup[i]["animal"]
		var bot := animal.make_bot(seed_value + i * 7919) if animal else PokerBot.new(PlayStyle.preset(K.SHARK), seed_value + i * 7919)
		m.add_player(setup[i]["name"], setup[i]["team"], setup[i].get("chips", chips), bot)
	for i in setup.size():
		if setup[i].get("leader", false):
			m.set_leader(1, i)
	if not crew_cards:
		for bot in m.bots:
			bot.knows_crew_cards = false
	m.max_hands = 400
	if interception:
		m.interception.enable_for_table(setup, 0)
	var signals := [0, 0]
	m.talk.gesture_made.connect(func(seat: int, _sig: int) -> void:
		if m.table.seats[seat].team == 1:
			signals[0] += 1)
	m.interception.noticed.connect(func(watcher: int, from_seat: int, _g: int, _meaning: int, _fake: bool) -> void:
		if m.table.seats[from_seat].team == 1 and m.table.seats[watcher].team == 0:
			signals[1] += 1)
	var first_bust := [-1]
	m.table.hand_finished.connect(func(_r: Dictionary) -> void:
		if first_bust[0] >= 0:
			return
		for i in m.table.seats.size():
			var s := m.table.seats[i]
			if s.team == 1 and s.stack == 0 and not s.ejected:
				first_bust[0] = i
				return)
	var w := m.run_to_end()
	t["matches"] += 1
	t["won"] += 1.0 if w == 0 else (0.5 if w == -1 else 0.0)
	t["hands"] += m.table.hand_number
	if m.leaders.has(1):
		var leader: int = m.leaders[1]
		t["leader_busted"] += 1 if m.leaderless.has(1) else 0
		t["leader_first"] += 1 if first_bust[0] == leader else 0
		t["caught"] += 1 if m.caught_team() == 1 else 0
		if m.leaderless.has(1):
			t["leaderless_hands"] += m.table.hand_number - int(m.leaderless[1])
	t["boss_signals"] += signals[0]
	t["boss_noticed"] += signals[1]
	for s in m.table.seats:
		if s.ejected:
			t["your_ejected" if s.team == 0 else "boss_ejected"] += 1


func _print(label: String, t: Dictionary) -> void:
	var n: int = t["matches"]
	var p: float = t["won"] / n
	var se := sqrt(p * (1.0 - p) / n)
	print("  %-16s won %5.1f%% (+-%.1f) of %d | leader busted %4.1f%%, first %4.1f%%, caught %4.1f%% | %.0f hands, %.0f leaderless | boss signals %.1f/match, %.0f%% noticed | ejected: yours %.2f, boss %.2f" % [
		label, 100.0 * p, 100.0 * se, n, 100.0 * t["leader_busted"] / n, 100.0 * t["leader_first"] / n,
		100.0 * t["caught"] / n, float(t["hands"]) / n, float(t["leaderless_hands"]) / n,
		float(t["boss_signals"]) / n, 100.0 * t["boss_noticed"] / maxi(1, t["boss_signals"]),
		float(t["your_ejected"]) / n, float(t["boss_ejected"]) / n])
