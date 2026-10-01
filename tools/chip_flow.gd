extends SceneTree
## Where do the chips go between two same-style crews? When simulate.gd says
## a style loses a matchup, this says why: pots won without a showdown vs at
## showdown, all-ins, raises, and how often each side re-raises when bet into.
##
##   godot --headless --path . -s tools/chip_flow.gd -- BLUFFER ROCK [matches] [seed] [--styles=file.json]
##
## Every fix in PlayStyle's docstring came from a reading like "wins the
## uncontested pots, loses it all back in all-ins".

const STATS := ["matches won", "net chips, no showdown", "net chips, showdown", "all-in showdowns won", "raises", "actions", "re-raise rate"]

var overrides := {}


func _init() -> void:
	var args: Array[String] = []
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--styles="):
			overrides = JSON.parse_string(FileAccess.get_file_as_string(arg.get_slice("=", 1)))
		else:
			args.append(arg)
	var kinds := [PlayStyle.Kind.keys().find(args[0]), PlayStyle.Kind.keys().find(args[1])]
	var matches := int(args[2]) if args.size() > 2 else 40
	var seed_value := int(args[3]) if args.size() > 3 else 1
	var totals := {}
	for stat in STATS:
		totals[stat] = [0.0, 0.0]
	for k in matches:
		_play(seed_value * 100003 + k, kinds, k % 2 == 1, totals, matches)
	for side in 2:
		print(PlayStyle.Kind.keys()[kinds[side]])
		for stat in STATS:
			var v: float = totals[stat][side]
			print("  %-26s %s" % [stat, "%.1f%%" % (100 * v) if stat == "re-raise rate" else str(int(v))])
	quit()


func _play(seed_value: int, kinds: Array, swap: bool, totals: Dictionary, matches: int) -> void:
	var m := TeamMatch.new(seed_value)
	for seat in 6:
		var kind: int = kinds[(seat % 2) ^ int(swap)]
		m.add_player("P%d" % seat, seat % 2, 1000, PokerBot.new(_style(kind), seed_value + seat * 7919))
	m.max_hands = 300
	var t := m.table
	var side := func(seat: int) -> int: return (seat % 2) ^ int(swap)
	var start: Array[int] = []
	t.hand_started.connect(func(_button: int) -> void:
		start.clear()
		for s in t.seats:
			start.append(s.stack + s.hand_bet))
	t.action_taken.connect(func(seat: int, action: int, _amount: int) -> void:
		totals["actions"][side.call(seat)] += 1
		if action == HoldemTable.Action.RAISE:
			totals["raises"][side.call(seat)] += 1)
	t.hand_finished.connect(func(result: Dictionary) -> void:
		var net := [0, 0]
		var all_in := false
		for i in t.seats.size():
			net[side.call(i)] += t.seats[i].stack - start[i]
			all_in = all_in or t.seats[i].all_in
		var key := "net chips, no showdown" if result["uncontested"] else "net chips, showdown"
		for s in 2:
			totals[key][s] += net[s]
		if all_in and not result["uncontested"]:
			totals["all-in showdowns won"][0 if net[0] > 0 else 1] += 1)
	var winner := m.run_to_end()
	if winner >= 0:
		totals["matches won"][side.call(winner)] += 1
	for seat in 6:
		totals["re-raise rate"][side.call(seat)] += m.reads.reraise_rate(seat) / (3.0 * matches)


func _style(kind: int) -> PlayStyle:
	var style := PlayStyle.preset(kind)
	var key: String = PlayStyle.Kind.keys()[kind]
	for param: String in overrides.get(key, {}):
		style.set(param, overrides[key][param])
	return style
