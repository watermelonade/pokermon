class_name TableTalk
extends RefCounted
## The secret signals passed between teammates during a hand. On a Steam
## Deck each one is a back button (a gesture under the table); see
## project.godot's input map.
##
## Reading a signal isn't free: a teammate with a weak bond sometimes
## misreads it as a different one. That's what makes bond worth training.
## Every signal is also a gesture the dealer might see: Heat listens for
## `gesture_made` (src/match/heat.gd).

signal gesture_made(from_seat: int, sig: int)

enum Sig {
	STRONG,  ## "I've got a big hand": teammates step aside
	WEAK,  ## "I'm just here for the ride"
	ATTACK,  ## "raise behind me": squeeze the opponent between us
	BACK_OFF,  ## "let me have this pot"
}

const GESTURES := ["Touch nose", "Scratch ear", "Stack chips", "Tip hat"]
const MEANINGS := ["I'm strong", "I'm weak", "Raise behind me", "Let me have it"]

## Every signal sent this hand: {from, sig, street}.
var sent: Array[Dictionary] = []
## How each reader took each signal, so a misread stays the same misread.
var _perceived := {}


func clear() -> void:
	sent.clear()
	_perceived.clear()


func send(from_seat: int, sig: Sig, street: int) -> void:
	sent.append({"from": from_seat, "sig": sig, "street": street})
	gesture_made.emit(from_seat, sig)


## What `reader` takes the signals from teammate `from_seat` to be, this hand.
## `bond` 0..1: at 0 half the signals are misread, at 1 none are.
func read_from(reader: int, from_seat: int, bond: float, rng: RandomNumberGenerator) -> Array[Sig]:
	var out: Array[Sig] = []
	for i in sent.size():
		if sent[i]["from"] != from_seat:
			continue
		var key := Vector2i(reader, i)
		if not _perceived.has(key):
			var sig: Sig = sent[i]["sig"]
			if rng.randf() < (1.0 - bond) * 0.5:
				sig = ((sig + rng.randi_range(1, 3)) % 4) as Sig
			_perceived[key] = sig
		out.append(_perceived[key])
	return out
