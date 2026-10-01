extends SceneTree
## Scores all 2,598,960 five-card hands and compares how many land in each
## category with the textbook counts. Too slow for the test suite (about 20
## seconds), so it's a one-off check to run after touching hand_evaluator.gd:
##
##   godot --headless --path . -s tools/verify_evaluator.gd

const EXPECTED := [1302540, 1098240, 123552, 54912, 10200, 5108, 3744, 624, 40]


func _init() -> void:
	var counts := PackedInt32Array()
	counts.resize(9)
	var started := Time.get_ticks_msec()
	var hand := [0, 0, 0, 0, 0]
	for a in 52:
		hand[0] = a
		for b in range(a + 1, 52):
			hand[1] = b
			for c in range(b + 1, 52):
				hand[2] = c
				for d in range(c + 1, 52):
					hand[3] = d
					for e in range(d + 1, 52):
						hand[4] = e
						counts[HandEvaluator.category(HandEvaluator.evaluate(hand))] += 1
	var ok := true
	for i in 9:
		var match_: bool = counts[i] == EXPECTED[i]
		ok = ok and match_
		print("%-16s %9d  expected %9d  %s" % [HandEvaluator.CATEGORY_NAMES[i], counts[i], EXPECTED[i], "ok" if match_ else "WRONG"])
	print("%.1fs, %s" % [(Time.get_ticks_msec() - started) / 1000.0, "all categories match" if ok else "MISMATCH"])
	quit(0 if ok else 1)
