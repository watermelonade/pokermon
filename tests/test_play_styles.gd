extends TestCase
## The mechanics the type chart rests on. Whether the cycle itself holds is
## measured by tools/simulate.gd (too slow for the suite); these check that
## each mechanic does what it says.

const A := HoldemTable.Action


func test_reads_count_reraises_when_bet_into() -> void:
	var t := HoldemTable.new()
	for i in 3:
		t.add_seat("P%d" % i, i % 2, 1000)
	var reads := TableReads.new()
	reads.watch(t)
	t.start_hand()
	t.act(A.RAISE, 30)  # seat 0 opens: not facing a bet, the blinds don't count
	t.act(A.RAISE, 90)  # seat 1 re-raises into it
	t.act(A.FOLD)  # seat 2 folds to it
	t.act(A.CALL)  # seat 0 calls it
	check_eq(reads.faced.get(0, 0), 1, "seat 0 faced one bet")
	check_eq(reads.reraised.get(0, 0), 0, "seat 0's open isn't a re-raise")
	check_eq(reads.faced.get(1, 0), 1, "seat 1 faced the open")
	check_eq(reads.reraised.get(1, 0), 1, "seat 1 re-raised")
	check_eq(reads.faced.get(2, 0), 1, "seat 2 faced a bet")
	check_eq(reads.reraise_rate(1), 2.0 / 6.0, "rate has a 1-in-5 prior")


func _bluff_spot(bluff_risk: float) -> int:
	# Heads-up, checked to the big blind on a flop that misses its 7-2.
	var t := HoldemTable.new()
	t.add_seat("Rival", 1, 1000)
	t.add_seat("Bluffer", 0, 1000)
	# Deal order heads-up: Bluffer, Rival, Bluffer, Rival, then the flop.
	t.start_hand(Card.parse_many("7c Ah 2s Kd As Kh 9d"))
	t.act(A.CALL)
	t.act(A.CHECK)
	var style := PlayStyle.preset(PlayStyle.Kind.BLUFFER)
	style.tightness = 5.0  # nothing is playable: any bet is a bluff
	style.bluff_rate = 1.0
	style.chattiness = 0.0
	style.bluff_risk = bluff_risk
	var bot := PokerBot.new(style, 3)
	return bot.decide(t, 1, TableTalk.new())["action"]


func test_bluff_risk_limits_how_much_a_bluff_stakes() -> void:
	check_eq(_bluff_spot(1.0), A.RAISE, "bluffs when it may risk its stack")
	check_eq(_bluff_spot(0.0), A.CALL, "checks when it may risk nothing")


func test_presets_keep_their_character() -> void:
	var rock := PlayStyle.preset(PlayStyle.Kind.ROCK)
	var maniac := PlayStyle.preset(PlayStyle.Kind.MANIAC)
	var shark := PlayStyle.preset(PlayStyle.Kind.SHARK)
	var station := PlayStyle.preset(PlayStyle.Kind.CALLING_STATION)
	var bluffer := PlayStyle.preset(PlayStyle.Kind.BLUFFER)
	check(rock.tightness > shark.tightness and shark.tightness > maniac.tightness, "Rock tightest, Maniac loosest")
	check(rock.doubt == 0.0 and shark.doubt == 1.0, "Rock never folds a strong hand; Shark can")
	check(rock.reads > 0.0, "Rock reads relentless players")
	check(maniac.persistence > bluffer.persistence, "Maniac keeps going, Bluffer gives up")
	var stickiest := [rock, maniac, shark, bluffer].all(func(o: PlayStyle) -> bool: return station.stickiness > o.stickiness)
	check(station.respect == 0.0 and stickiest, "Station believes nothing and calls the most")
	check(bluffer.bluff_rate > maniac.bluff_rate and bluffer.bluff_risk < 1.0, "Bluffer bluffs most, but small")
