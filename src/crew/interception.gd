class_name Interception
extends RefCounted
## Reading the other crew's signals. Every gesture at the table can be seen
## by the crews it isn't meant for, and what they make of it depends on two
## separate things:
##
## 1. **Noticing.** Each gesture gets one roll per watching animal on each
##    other crew (seat order; the first to spot it is the one who noticed).
##    An animal's chance is its attentiveness x LOOK x n, where n is how
##    many signals the signalling crew has made this hand including this one
##    (capped at MAX_CHANCE). So a lone nose-touch mostly slips by, and a
##    crew fidgeting three times in a hand is easy to catch: chatty crews
##    leak, and bigger crews, which signal more, leak more. The same n is
##    what makes Heat climb (src/match/heat.gd), so a crew that's careful
##    with the dealer is careful with rivals too. Attentiveness comes from
##    the species (SPECIES: owls and cats watch, geese honk), the player is
##    YOU, and bots with no species (tools/simulate.gd) use their style's
##    (BY_STYLE). Folded animals still watch; busted and ejected ones don't.
## 2. **Understanding.** Each crew signals in its own code (CrewCode), so a
##    noticed gesture is just "the Cat scratched its ear" until the crew has
##    learned what that crew means by it. A noticed gesture from an animal
##    whose cards are then shown at a showdown teaches its meaning, for good
##    (CodeBook, which is what a save keeps). Fakes teach nothing: the cards
##    don't match the gesture.
##
## Fakes (TableTalk.send's `fake`): your teammates ignore them, but a rival
## who notices one and has learned that gesture of your code believes it.
## Rivals learn your code the same way you learn theirs, so a fake only
## lands once they've cracked the gesture; the overlay shows which they have.
##
## Bots read what their crew has noticed and understood this hand (PokerBot):
## facing a bet from a seat that said "I'm strong" (or "let me have it") a
## bot reads its equity down a further READ_WEIGHT, from one that said "I'm
## weak" up by as much, and it bluffs WEAK_BLUFF more often into a pot where
## an opponent said "I'm weak" and none said strong.
## Kept small on purpose: an intercepted signal is a hint, and the type chart
## (README) is tuned without it.
##
## Off by default (`enabled`), and while off it never draws a random number
## or changes a decision, so bot-vs-bot balance is byte-for-byte what it was
## (tests/test_interception.gd checks a golden action log; tools/simulate.gd
## prints the same output with or without this class). It has its own RNG for
## the same reason. The table turns it on for matches you play in, and
## `tools/simulate.gd --interception` for both crews; README has the numbers.

signal noticed(watcher: int, from_seat: int, gesture: int, meaning: int, fake: bool)  ## meaning -1: not understood
signal learned(reader_team: int, signaller_team: int, gesture: int, meaning: int)

const LOOK := 0.25  ## chance per point of attentiveness, for a crew's first signal of the hand
const MAX_CHANCE := 0.9
const YOU := 0.4  ## the player's own eyes: the animals are the sharp ones
const DEFAULT := 0.4
const SPECIES := {
	&"owl": 0.8,  # watches everything, head swivelling
	&"cat": 0.75,  # pretends not to, sees it all
	&"raccoon": 0.55,  # a thief's eye for hands
	&"possum": 0.5,  # still, so it sees a lot
	&"squirrel": 0.3,  # busy with its chips
	&"goose": 0.2,  # too busy honking
}
## For bots with no species: the demo species of that style, averaged.
const BY_STYLE := {
	PlayStyle.Kind.ROCK: 0.65,  # owl, possum
	PlayStyle.Kind.MANIAC: 0.2,  # goose
	PlayStyle.Kind.SHARK: 0.75,  # cat
	PlayStyle.Kind.CALLING_STATION: 0.3,  # squirrel
	PlayStyle.Kind.BLUFFER: 0.55,  # raccoon
}
## How far an understood "strong" / "weak" from the bettor moves a bot's
## equity (x0.85 / x1.15). Heads-up against a 3x raise (tests/
## test_interception.gd, 150 deals) a Shark folds 132 hands with nothing
## heard, 138 if the raiser said strong, 91 if it said weak; a Rock checking
## behind a limp bluffs 5 times, 28 if the limper said weak. A first try
## halved the bot's respect for a "weak" bettor instead: 47 folds, so 64% of
## its folds became calls, which is more than a hint. That spot is a knife
## edge (heads-up equities bunch around 50%); the cycle numbers in README
## are the real measure.
const READ_WEIGHT := 0.15
const WEAK_BLUFF := 0.15

var enabled := false
var rng := RandomNumberGenerator.new()
var attentiveness := {}  ## seat -> 0..1; missing: DEFAULT
var crew_ids := {}  ## team -> crew id (CrewCode, CodeBook); missing: "team<N>"
var book := CodeBook.new()
## Gestures noticed this hand: {reader (team), watcher, from, sig, gesture, fake}.
var seen: Array[Dictionary] = []
## Running totals for tools and tests: signals made, noticed, gestures learned.
var stats := {"signals": 0, "noticed": 0, "learned": 0}
var _table: HoldemTable
var _talk: TableTalk
var _made_this_hand := {}  ## team -> signals made this hand
var _codes := {}  ## team -> its code (cached)


func watch(table: HoldemTable, talk: TableTalk) -> void:
	_table = table
	_talk = talk
	table.hand_started.connect(func(_button: int) -> void:
		seen.clear()
		_made_this_hand.clear())
	talk.gesture_made.connect(_on_gesture)
	table.hand_finished.connect(_on_hand_finished)


## Turns it on for an all-bot match: attentiveness from each bot's style.
func enable_for_bots(bots: Array[PokerBot]) -> void:
	enabled = true
	for i in bots.size():
		if bots[i]:
			attentiveness[i] = BY_STYLE.get(bots[i].style.kind, DEFAULT)


## Turns it on for a table you play at. `setup` is the table's seating
## ({"name", "team", "animal", and optionally "crew": a stable id for the
## rival crew, which is what learned codes are saved under}); without one,
## a crew is known by its animals' names. Your crew is CrewCode.PLAYER.
## `codebook` (optional) is what's been learned so far; it's updated in place.
func enable_for_table(setup: Array[Dictionary], human_seat: int, codebook: CodeBook = null) -> void:
	enabled = true
	if codebook:
		book = codebook
	var names := {}
	for i in setup.size():
		var animal: Animal = setup[i].get("animal")
		attentiveness[i] = YOU if animal == null else SPECIES.get(animal.species, DEFAULT)
		var team: int = setup[i]["team"]
		if setup[i].get("crew", ""):
			crew_ids[team] = setup[i]["crew"]
		names.get_or_add(team, []).append(setup[i]["name"])
	for team: int in names:
		if team == setup[human_seat]["team"]:
			crew_ids[team] = CrewCode.PLAYER
		elif not crew_ids.has(team):
			crew_ids[team] = "/".join(names[team])
	_codes.clear()


func crew_id(team: int) -> String:
	return crew_ids.get(team, "team%d" % team)


func code_of(team: int) -> Array[int]:
	if not _codes.has(team):
		_codes[team] = CrewCode.for_crew(crew_id(team))
	return _codes[team]


func attentiveness_of(seat: int) -> float:
	return attentiveness.get(seat, DEFAULT)


## The chance `watcher` spots a gesture that is its crew's `nth` this hand.
func notice_chance(watcher: int, nth: int) -> float:
	return minf(MAX_CHANCE, attentiveness_of(watcher) * LOOK * nth)


## What `reader_team` makes of `signaller_team`'s `gesture`, or -1.
func meaning_for(reader_team: int, signaller_team: int, gesture: int) -> int:
	return book.meaning(crew_id(reader_team), crew_id(signaller_team), gesture)


## seat -> meanings (TableTalk.Sig) that `reader_team` has noticed from it
## this hand and understands. What bots act on.
func readings(reader_team: int) -> Dictionary:
	var out := {}
	for e in seen:
		if e["reader"] != reader_team:
			continue
		var m := meaning_for(reader_team, _table.seats[e["from"]].team, e["gesture"])
		if m >= 0:
			out.get_or_add(e["from"], []).append(m)
	return out


func _can_watch(seat: int) -> bool:
	var s := _table.seats[seat]
	return not s.ejected and s.stack + s.hand_bet > 0


func _on_gesture(from_seat: int, sig: int) -> void:
	if not enabled:
		return
	var team := _table.seats[from_seat].team
	var nth: int = _made_this_hand.get(team, 0) + 1
	_made_this_hand[team] = nth
	stats["signals"] += 1
	var fake := false
	if _talk.sent and _talk.sent.back()["from"] == from_seat:
		fake = _talk.sent.back().get("fake", false)
	var gesture := code_of(team)[sig]
	var watchers := {}  ## team -> its seats, in seat order
	for i in _table.seats.size():
		if _table.seats[i].team != team and _can_watch(i):
			watchers.get_or_add(_table.seats[i].team, []).append(i)
	var teams := watchers.keys()
	teams.sort()
	for reader: int in teams:
		for w: int in watchers[reader]:
			if rng.randf() >= notice_chance(w, nth):
				continue
			seen.append({"reader": reader, "watcher": w, "from": from_seat, "sig": sig, "gesture": gesture, "fake": fake})
			stats["noticed"] += 1
			noticed.emit(w, from_seat, gesture, meaning_for(reader, team, gesture), fake)
			break


## A showdown shows what a signal meant: every noticed (real) gesture from a
## seat whose cards are turned over is learned.
func _on_hand_finished(result: Dictionary) -> void:
	if not enabled or result["uncontested"]:
		return
	var scores: Dictionary = result["scores"]
	for e in seen:
		if e["fake"] or not scores.has(e["from"]):
			continue
		var team := _table.seats[e["from"]].team
		if meaning_for(e["reader"], team, e["gesture"]) >= 0:
			continue
		var m := CrewCode.meaning_of(code_of(team), e["gesture"])
		book.learn(crew_id(e["reader"]), crew_id(team), e["gesture"], m)
		stats["learned"] += 1
		learned.emit(e["reader"], team, e["gesture"], m)
