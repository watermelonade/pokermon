extends SceneTree
## How often each dealer warns, fines and ejects each style's crew. Plays
## same-style crews against each other (both crews count) and prints, per
## crew per match: warnings, fines, ejections, and the share of matches in
## which the crew lost someone to the floor.
##
##   godot --headless --path . -s tools/heat_report.gd -- [matches] [seed] [DEALER ...]
##
## A dealer can also be given as CUSTOM:notice:cooling to try numbers before
## putting them in Dealer.preset.
##
## The design wants a sleepy dealer to almost never fine anyone and a strict
## one to catch a chatty crew most matches, with cautious styles (Rock,
## Shark) getting caught far less than careless ones (Maniac).

const K := PlayStyle.Kind
const STYLES := [K.ROCK, K.SHARK, K.BLUFFER, K.CALLING_STATION, K.MANIAC]


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var matches := int(args[0]) if args.size() > 0 else 20
	var seed_value := int(args[1]) if args.size() > 1 else 1
	var dealers: Array[Dealer] = []
	for name in args.slice(2):
		if name.begins_with("CUSTOM:"):
			var d := Dealer.preset(Dealer.Kind.WATCHFUL)
			d.notice = float(name.get_slice(":", 1))
			d.cooling = float(name.get_slice(":", 2))
			dealers.append(d)
		else:
			dealers.append(Dealer.preset(Dealer.Kind.keys().find(name)))
	if dealers.is_empty():
		for kind in [Dealer.Kind.ASLEEP, Dealer.Kind.RELAXED, Dealer.Kind.WATCHFUL, Dealer.Kind.STRICT]:
			dealers.append(Dealer.preset(kind))
	for dealer in dealers:
		print("\n%s dealer (notice %.0f, cooling %.0f): per crew per match" % [dealer.display_name(), dealer.notice, dealer.cooling])
		print("  %-16s %9s %7s %10s %13s %12s" % ["", "warnings", "fines", "ejections", "lost a seat", "signals/hand"])
		for style in STYLES:
			var totals := [0, 0, 0, 0, 0, 0]
			for k in matches:
				_play(seed_value * 100003 + style * 1009 + k, style, dealer, totals)
			var crews := 2.0 * matches
			print("  %-16s %9.2f %7.2f %10.2f %12d%% %12.2f" % [PlayStyle.KIND_NAMES[style],
					totals[0] / crews, totals[1] / crews, totals[2] / crews, roundi(100 * totals[3] / crews),
					totals[4] / (2.0 * totals[5])])
	quit()


func _play(seed_value: int, style: int, dealer: Dealer, totals: Array) -> void:
	var m := TeamMatch.new(seed_value)
	m.heat.dealer = dealer
	for seat in 6:
		m.add_player("P%d" % seat, seat % 2, 1000, PokerBot.new(PlayStyle.preset(style), seed_value + seat * 7919))
	m.max_hands = 300
	m.heat.warned.connect(func(_team: int, _seat: int) -> void: totals[0] += 1)
	m.heat.fined.connect(func(_team: int, _seat: int) -> void: totals[1] += 1)
	m.heat.ejection_called.connect(func(_team: int, _seat: int) -> void: totals[2] += 1)
	m.talk.gesture_made.connect(func(_seat: int, _sig: int) -> void: totals[4] += 1)
	m.run_to_end()
	totals[5] += m.table.hand_number
	for team in 2:
		for s in m.table.seats:
			if s.team == team and s.ejected:
				totals[3] += 1
				break
