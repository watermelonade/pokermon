extends TestCase

const Reference := preload("res://tests/reference_evaluator.gd")


func _score(text: String) -> int:
	return HandEvaluator.evaluate(Card.parse_many(text))


func _cat(text: String) -> int:
	return HandEvaluator.category(_score(text))


func test_categories() -> void:
	var C := HandEvaluator.Category
	check_eq(_cat("As Ks Qs Js Ts 2d 3c"), C.STRAIGHT_FLUSH, "royal flush")
	check_eq(_cat("9h 9d 9s 9c Kd 2c 3c"), C.QUADS)
	check_eq(_cat("9h 9d 9s Kc Kd 2c 3c"), C.FULL_HOUSE)
	check_eq(_cat("2h 7h 9h Jh Kh 2c 3c"), C.FLUSH)
	check_eq(_cat("5d 6c 7h 8s 9d Kc Kh"), C.STRAIGHT)
	check_eq(_cat("9h 9d 9s Kc 4d 2c 3h"), C.TRIPS)
	check_eq(_cat("9h 9d Ks Kc 4d 2c 3h"), C.TWO_PAIR)
	check_eq(_cat("9h 9d As Kc 4d 2c 7h"), C.PAIR)
	check_eq(_cat("9h Jd As Kc 4d 2c 7h"), C.HIGH_CARD)


func test_wheel_is_five_high_straight() -> void:
	check_eq(_cat("Ad 2c 3h 4s 5d Kc Kh"), HandEvaluator.Category.STRAIGHT)
	check(_score("Ad 2c 3h 4s 5d") < _score("2d 3c 4h 5s 6d"), "wheel loses to six-high")
	check_eq(_cat("Ah 2h 3h 4h 5h 9c"), HandEvaluator.Category.STRAIGHT_FLUSH, "steel wheel")


func test_kickers_decide() -> void:
	check(_score("Ah Ad Kc 7s 3d") > _score("As Ac Qh 7d 3c"), "pair of aces, king kicker wins")
	check(_score("Kh Kd 9c 9s Ad") > _score("Ks Kc 9h 9d Qc"), "two pair, ace kicker wins")
	check(_score("2h 7h 9h Jh Ah") > _score("3d 7d 9d Jd Kd"), "ace-high flush wins")
	check_eq(_score("Ah Kd Qc Js 9d 3c 2h"), _score("As Kc Qh Jd 9s 4d 2c"), "same five cards play")


func test_two_trips_make_a_full_house() -> void:
	check_eq(_score("9h 9d 9s 5c 5d 5h 2c"), _score("9c 9s 9d 5s 5h"), "nines full of fives")


func test_three_pairs_use_best_kicker() -> void:
	# KK 99 44 + 2: the fours become the kicker over the deuce.
	check_eq(_score("Kh Kd 9c 9s 4d 4c 2h"), _score("Ks Kc 9h 9d 4s"))


func test_matches_brute_force_on_random_hands() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var mismatches := 0
	for _i in 3000:
		var cards := Deck.shuffled(rng).cards.slice(0, 7)
		if HandEvaluator.evaluate(cards) != Reference.best_of(cards):
			mismatches += 1
			if mismatches <= 3:
				check(false, "mismatch on %s" % str(cards.map(Card.label)))
	check_eq(mismatches, 0, "mismatches out of 3000")
