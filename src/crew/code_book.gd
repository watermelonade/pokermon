class_name CodeBook
extends RefCounted
## What each crew has worked out of other crews' signal codes: for a reader
## crew and a signalling crew, which gestures it understands and what they
## mean. Both directions matter to the player: what your crew has learned of
## each rival ("player" reading "pond_hecklers"), and what each rival has
## learned of yours ("pond_hecklers" reading "player"), which is what makes
## a fake signal land.
##
## This is the part of interception that outlives a match, so it's plain
## data with a JSON-safe round trip (to_dict / from_dict) for the save. The
## codes themselves never need saving: CrewCode derives them from crew ids.
## Learning is one-way and permanent (a crew doesn't change its code; if
## that's wanted later, `forget` drops what a reader knows of one crew).

## reader crew id -> signalling crew id -> gesture (int) -> meaning (int)
var known := {}


func learn(reader: String, signaller: String, gesture: int, meaning: int) -> void:
	var of_crew: Dictionary = known.get_or_add(reader, {}).get_or_add(signaller, {})
	of_crew[gesture] = meaning


## What `reader` takes `signaller`'s `gesture` to mean, or -1 if it doesn't know.
func meaning(reader: String, signaller: String, gesture: int) -> int:
	return known.get(reader, {}).get(signaller, {}).get(gesture, -1)


## gesture -> meaning: everything `reader` has learned of `signaller`'s code.
func learned(reader: String, signaller: String) -> Dictionary:
	return known.get(reader, {}).get(signaller, {}).duplicate()


func forget(reader: String, signaller: String) -> void:
	if known.has(reader):
		known[reader].erase(signaller)


## For the save: string keys all the way down (JSON objects can't have int keys).
func to_dict() -> Dictionary:
	var out := {}
	for reader: String in known:
		out[reader] = {}
		for signaller: String in known[reader]:
			var gestures := {}
			for g: int in known[reader][signaller]:
				gestures[str(g)] = known[reader][signaller][g]
			out[reader][signaller] = gestures
	return out


## Reads what to_dict wrote (also after a JSON round trip, where numbers come
## back as floats). Anything malformed is skipped, not fatal: a damaged save
## loses a learned gesture, not the game.
static func from_dict(data: Variant) -> CodeBook:
	var book := CodeBook.new()
	if not data is Dictionary:
		return book
	for reader: Variant in data:
		if not data[reader] is Dictionary:
			continue
		for signaller: Variant in data[reader]:
			if not data[reader][signaller] is Dictionary:
				continue
			for g: Variant in data[reader][signaller]:
				var gesture := int(str(g)) if str(g).is_valid_int() else -1
				var m: Variant = data[reader][signaller][g]
				if gesture < 0 or gesture >= CrewCode.SIZE or not (m is int or m is float):
					continue
				if int(m) < 0 or int(m) >= CrewCode.SIZE:
					continue
				book.learn(str(reader), str(signaller), gesture, int(m))
	return book
