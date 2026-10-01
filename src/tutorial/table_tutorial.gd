class_name TableTutorial
extends RefCounted
## Runs TutorialScript at the table: deals each lesson's hand, seats the
## scripted animals, and keeps the coach's queue of lines. The table scene
## (src/ui/table_view.gd) holds one of these when it's the tutorial (its
## `tutorial` field) and calls in at a few points: a hand starting, an
## action, your turn coming up, the hand ending, you signalling. Everything
## here is plain logic with no nodes or clocks of its own, so
## tests/test_tutorial.gd drives whole lessons headless.
##
## Pausing: while the coach has lines queued the table's flow waits (bots
## don't think, your menu doesn't open, the next hand doesn't come), the
## way it already waits for the help card. Motion already booked (cards in
## flight) finishes underneath. Each line has a time it shows from, on the
## table's clock (TableView._now()), so a comment on the result shows once
## the chips have landed rather than when the rules decided; nothing here
## awaits.
##
## Each lesson is one hand. Between lessons every stack goes back to
## TutorialScript.CHIPS and the button is set where the lesson needs it,
## so a lesson's situation doesn't depend on how the last one went (a
## player who shoves every hand still gets the same five lessons, and
## nobody busts). The dealer is set per lesson too: none until Heat.
##
## Never punishing: a signal that would take your crew to a fine (70) or
## past it is refused with an explanation (TOO_HOT), so the tutorial shows
## the warning but never fines or ejects you; and the overworld ignores the
## result (no money changes hands).

## After a signal answers the coach, she waits this long before her next
## line, so the table's own text (your gesture, the dealer's warning) shows
## in the box first; otherwise "Hear that?" covered what there was to hear.
const AFTER_SIGNAL := 1.6

var start_lesson := 0  ## 0-based; a dev flag jumps ahead (--lesson=N)
var lesson_index := -1  ## the lesson being played, once the first hand starts
var skipped := false
var completed := false  ## the last lesson's hand finished
var coach_lines: Array[Dictionary] = []  ## {"text", "wait", "at"}, the next first
var match_: TeamMatch

var _fired := {}  ## coach entry index -> true, this lesson
var _you_raised := false
var _tell_seen := false
var _skip_asked := false


## The lessons as numbered for the player, 1-based ("Lesson 2 of 5").
func lesson_number() -> int:
	return lesson_index + 1


func lesson() -> Dictionary:
	return TutorialScript.lesson(lesson_index)


## Called once the match exists: how many hands it plays (one a lesson).
func hands() -> int:
	return TutorialScript.count()


## The controller for seat `seat`: scripted animals, and for your seat
## nobody (you play) unless --autoplay, when it follows the coach's advice.
func make_bot(seat: int, autoplay: bool) -> PokerBot:
	if seat == 0 and not autoplay:
		return null
	return ScriptedBot.new()


## Before each hand: the next lesson's stacks, dealer, button, and the
## stacked deck to deal (pass it to TeamMatch.start_hand). The bots' plans
## are swapped in here too, so one ScriptedBot per seat plays every lesson.
func begin_hand(m: TeamMatch) -> Array[int]:
	match_ = m
	lesson_index = start_lesson if lesson_index < 0 else lesson_index + 1
	var l := lesson()
	var t := m.table
	_fired.clear()
	_you_raised = false
	_tell_seen = false
	for i in t.seats.size():
		t.seats[i].stack = TutorialScript.CHIPS
		var bot := m.bots[i] as ScriptedBot
		if bot:
			bot.plan = l["plans"].get(i, {})
			bot.signals = l.get("signals", {}).get(i, {})
	m.heat.dealer = Dealer.preset(l["dealer"])
	# The table moves the big blind on from big_blind_seat (see
	# HoldemTable.start_hand); setting it puts the button where the lesson
	# wants it, whatever happened before. hand_number makes "Hand 3" read as
	# lesson 3 and keeps the blinds at the first level.
	t.big_blind_seat = (int(l["button"]) + 1) % t.seats.size()
	t.hand_number = lesson_index
	m.max_hands = TutorialScript.count()
	return TutorialScript.deck_for(lesson_index, t.seats.size())


## The table tells the coach what happened; matching lines are queued, to
## show from `at` (the table's clock). `info`: "street" (int), "seat",
## "action" (HoldemTable.Action).
func event(kind: String, info: Dictionary, at: float) -> void:
	if skipped or lesson_index < 0:
		return
	if kind == "acted" and info.get("seat", -1) == 0 and info.get("action", -1) == HoldemTable.Action.RAISE:
		_you_raised = true
	var entries: Array = lesson()["coach"]
	for k in entries.size():
		var e: Dictionary = entries[k]
		if _fired.has(k) or e["on"] != kind:
			continue
		if e.has("street") and ScriptedBot.street_name(info.get("street", -1)) != e["street"]:
			continue
		if e.has("seat") and e["seat"] != info.get("seat", -1):
			continue
		if e.has("action") and HoldemTable.ACTION_NAMES[info.get("action", 0)] != _action_word(e["action"]):
			continue
		if e.has("if") and not condition(e["if"]):
			continue
		_fired[k] = true
		for line: Variant in e["lines"]:
			say(line, at)
	if kind == "hand_over" and lesson_index >= TutorialScript.count() - 1:
		completed = true


func _action_word(action: String) -> String:
	return {"fold": "folds", "check": "checks", "call": "calls", "raise": "raises to"}.get(action, action)


## Queues a coach line (text, or {"text", "wait"}) to show from `at`.
func say(line: Variant, at: float, front := false) -> void:
	var entry := {"text": str(line), "wait": "", "at": at}
	if line is Dictionary:
		entry = {"text": str(line["text"]), "wait": str(line.get("wait", "")), "at": at}
	if front:
		coach_lines.push_front(entry)
	else:
		coach_lines.append(entry)


func condition(name: String) -> bool:
	var t := match_.table
	var you := t.seats[0]
	match name:
		"you_raised":
			return _you_raised
		"you_folded":
			return you.folded
		"not_folded":
			return not you.folded
		"you_won":
			return t.last_result.get("payouts", {}).has(0)
		"not_won":
			return not t.last_result.get("payouts", {}).has(0)
		"you_signalled":
			return match_.talk.sent.any(func(s: Dictionary) -> bool: return s["from"] == 0 and s["sig"] == TableTalk.Sig.STRONG)
		"facing_bet":
			return not t.hand_over and t.to_act == 0 and t.legal()["to_call"] > 0
		"not_facing_bet":
			return not t.hand_over and t.to_act == 0 and t.legal()["to_call"] == 0
		"tell_seen":
			return _tell_seen
		"no_tell":
			return not _tell_seen
	push_error("TableTutorial: unknown condition %s" % name)
	return false


# --- The coach's lines ------------------------------------------------------


func has_lines() -> bool:
	return not coach_lines.is_empty()


## True when a line is up (it's past its time): the table shows it and
## waits for A (or a signal, for a line that asks for one).
func showing(now: float) -> bool:
	return has_lines() and now >= float(coach_lines[0]["at"])


## The line up now, placeholders filled in with the table as it is.
func current_text() -> String:
	return format(coach_lines[0]["text"]) if has_lines() else ""


## "signal:0", "signal:any", "skip" or "" (A moves on).
func current_wait() -> String:
	return coach_lines[0]["wait"] if has_lines() else ""


## A dismisses the current line. On a line waiting for a signal, A has the
## coach do it for you (returns the signal to send, or -1: nothing to send).
## On the skip question, A skips. `now`: the table's clock.
func press_a(now := 0.0) -> int:
	if not has_lines():
		return -1
	var wait := current_wait()
	coach_lines.pop_front()
	if wait == "skip":
		_skip_asked = false
		skipped = true
		coach_lines.clear()
		return -1
	if wait.begins_with("signal:"):
		var sig := 0 if wait == "signal:any" else int(wait.get_slice(":", 1))
		if allow_signal(0):
			_pause_after_signal(now)
			return sig
	return -1


## B on the skip question keeps going; elsewhere B does nothing.
func press_b() -> void:
	if has_lines() and current_wait() == "skip":
		coach_lines.pop_front()
		_skip_asked = false


## You pressed signal `sig` (0-3). Returns whether to send it. A line
## waiting for a signal moves on when it gets one it asked for; one that
## would overheat your crew is refused with an explanation instead.
func on_signal(sig: int, now: float) -> bool:
	if not allow_signal(0):
		if not (has_lines() and coach_lines[0]["text"] == TutorialScript.TOO_HOT):
			say(TutorialScript.TOO_HOT, now, true)
		return false
	var wait := current_wait()
	if wait == "signal:any" or wait == "signal:%d" % sig:
		coach_lines.pop_front()
		_pause_after_signal(now)
		return true
	return not has_lines() or not wait.begins_with("signal:")


func _pause_after_signal(now: float) -> void:
	if has_lines():
		coach_lines[0]["at"] = maxf(float(coach_lines[0]["at"]), now + AFTER_SIGNAL)


## Whether `seat` may signal: anything that keeps its crew's Heat under the
## fine line. With no dealer watching, always.
func allow_signal(seat: int) -> bool:
	if match_ == null or not match_.heat.dealer.watching():
		return true
	var team := match_.table.seats[seat].team
	return match_.heat.level(team) + match_.heat.cost_of_next(seat) < Heat.FINE


## Start (or Tab) asks whether to skip the rest; it goes in front of
## whatever the coach was saying, which carries on if you say no.
func request_skip(now: float) -> void:
	if _skip_asked or skipped:
		return
	_skip_asked = true
	coach_lines.push_front({"text": TutorialScript.SKIP_PROMPT, "wait": "skip", "at": now})


func format(text: String) -> String:
	if match_ == null:
		return text
	var t := match_.table
	var heat := match_.heat.level(t.seats[0].team)
	var next := match_.heat.cost_of_next(0) if match_.heat.dealer.watching() else 0.0
	var names := {}
	for i in t.seats.size():
		names[("m%d" if t.seats[i].team == t.seats[0].team else "r%d") % i] = t.seats[i].name
	names["heat"] = roundi(heat)
	names["next"] = roundi(next)
	names["after"] = roundi(heat + next)
	return text.format(names)


# --- What the table asks ----------------------------------------------------


## The 0..1 roll for a tell (AnimalTells.fires): the lesson's tell always
## shows, every other tell never does, so the one you're taught to read
## isn't lost among others.
func tell_roll(seat: int, street: int) -> float:
	var tell: Dictionary = lesson().get("tell", {})
	if tell.get("seat", -1) == seat and tell.get("street", "") == ScriptedBot.street_name(street):
		return 0.0
	return 1.0


func note_tell(_seat: int) -> void:
	_tell_seen = true


## What the coach would play for `seat` now: {"item": CommandMenu.Item,
## "raise_to": int}. The table puts the menu cursor there.
func suggest(seat: int) -> Dictionary:
	var t := match_.table
	var policy := ScriptedBot.policy_for(lesson()["plans"].get(seat, {}), t.street)
	var choice := ScriptedBot.play(policy, t, seat, match_.talk)
	var legal := t.legal()
	match int(choice["action"]):
		HoldemTable.Action.RAISE:
			return {"item": CommandMenu.Item.RAISE, "raise_to": choice["amount"]}
		HoldemTable.Action.FOLD:
			if not legal["can_check"]:
				return {"item": CommandMenu.Item.FOLD, "raise_to": 0}
	return {"item": CommandMenu.Item.CALL, "raise_to": 0}


## The line the table ends on instead of "Your crew wins the match!".
func result_text() -> String:
	return TutorialScript.SKIPPED if skipped else TutorialScript.RESULT
