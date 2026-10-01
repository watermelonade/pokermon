class_name CrewCode
extends RefCounted
## Every crew's private signal code: which gesture it makes for which
## meaning. Your crew uses the code on the table's legend (touch nose = "I'm
## strong", TableTalk.GESTURES / MEANINGS in order); every rival crew has its
## own, so seeing a rival touch its nose tells you nothing until you've
## learned what that crew means by it (Interception, CodeBook).
##
## A code is an Array of 4 gesture indices, indexed by meaning (TableTalk.Sig):
## code[Sig.WEAK] is the gesture the crew makes for "I'm weak". It's derived
## from the crew's id by a hash, so the same crew always uses the same code
## and nothing about it needs saving; only what you've learned of it does.
##
## Rival codes are derangements (no gesture keeps its legend meaning): if a
## rival crew's nose-touch could mean "I'm strong" as yours does, players
## would read the legend into rival signals and "learn" codes they never
## saw. 9 of the 24 orderings qualify, so crews share codes now and then;
## that's fine, nobody can tell which crews do without learning both.

const PLAYER := "player"  ## your crew's id: the legend's code
const SIZE := 4


## The code `crew_id` signals with (meaning -> gesture).
static func for_crew(crew_id: String) -> Array[int]:
	var code: Array[int] = [0, 1, 2, 3]
	if crew_id == PLAYER:
		return code
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("crew code:" + crew_id)
	while true:
		# Fisher-Yates with the crew's own RNG (Array.shuffle would draw from
		# the global one, and differ from run to run).
		for i in range(SIZE - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var tmp := code[i]
			code[i] = code[j]
			code[j] = tmp
		if is_derangement(code):
			return code
	return code


static func is_derangement(code: Array[int]) -> bool:
	for i in code.size():
		if code[i] == i:
			return false
	return true


## What `gesture` means in `code`, or -1.
static func meaning_of(code: Array[int], gesture: int) -> int:
	return code.find(gesture)
