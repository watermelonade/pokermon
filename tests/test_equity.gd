extends TestCase
## Checked against well-known heads-up preflop odds: AA wins about 85% of
## the time against a random hand, 72o about 35%.


func _equity(hole: String, board: String, opponents: int) -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	return Equity.estimate(Card.parse_many(hole), Card.parse_many(board), opponents, 4000, rng)


func test_aces_vs_one_random_hand() -> void:
	var e := _equity("As Ah", "", 1)
	check(e > 0.82 and e < 0.88, "AA heads-up %.3f, expected ~0.85" % e)


func test_seven_deuce_vs_one_random_hand() -> void:
	var e := _equity("7c 2d", "", 1)
	check(e > 0.31 and e < 0.38, "72o heads-up %.3f, expected ~0.35" % e)


func test_more_opponents_less_equity() -> void:
	check(_equity("As Ah", "", 5) < _equity("As Ah", "", 1), "AA is worth less six-handed")


func test_made_nuts_on_river() -> void:
	check_eq(_equity("As Ks", "Qs Js Ts 2d 3c", 3), 1.0, "royal flush can't lose")
