class_name TableMotion
extends RefCounted
## The table's animation timeline: cards sliding from the shoe, board cards
## flipping, chips sliding to the pot and the pot to the winner.
##
## The rules engine runs a whole street (or, when everyone's all-in, the
## rest of the hand) inside one act() call, emitting signals back to back.
## Animating each signal the moment it fires would play the flop, turn and
## river flips on top of each other. So every beat reserves a slot after
## the previous one (`reserve`), and the scene shows each thing only once
## its slot comes: an all-in run-out plays out card by card.
##
## No Tweens and no awaits: everything is a pure function of the clock,
## asked for in _draw. The overworld frees the table the moment `finished`
## fires; a Tween or a coroutine mid-flight would then touch a freed node,
## while a timeline nobody reads any more just stops.
##
## Times are seconds, passed in, so tests can drive the clock.

var items: Array[Dictionary] = []
var cursor := 0.0  ## when the last reserved beat ends


## Books `duration` seconds after everything already booked (or now, if
## the timeline is idle) and returns when the slot starts.
func reserve(now: float, duration: float) -> float:
	var start := maxf(now, cursor)
	cursor = start + duration
	return start


## Something that moves: {"kind", "start", "duration", ...data}.
func add(kind: StringName, start: float, duration: float, data := {}) -> Dictionary:
	var item := data.duplicate()
	item["kind"] = kind
	item["start"] = start
	item["duration"] = duration
	items.append(item)
	return item


## Items in flight at `now`, with "p" set to their 0..1 progress.
func active(now: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for item in items:
		var p := progress(item, now)
		if p >= 0.0 and p < 1.0:
			item["p"] = p
			out.append(item)
	return out


## -1 before the item starts, 0..1 during, 1 after.
static func progress(item: Dictionary, now: float) -> float:
	var start: float = item["start"]
	var duration: float = item["duration"]
	if now < start:
		return -1.0
	return 1.0 if duration <= 0.0 else minf(1.0, (now - start) / duration)


func busy(now: float) -> bool:
	return now < cursor


## Drops finished items (call now and then; drawing ignores them anyway).
func prune(now: float) -> void:
	items = items.filter(func(item: Dictionary) -> bool: return progress(item, now) < 1.0)


func clear(now: float) -> void:
	items.clear()
	cursor = now


## Fast start, soft landing: things thrown across a table.
static func ease_out(p: float) -> float:
	return 1.0 - pow(1.0 - clampf(p, 0.0, 1.0), 3.0)
