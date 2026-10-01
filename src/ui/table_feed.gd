class_name TableFeed
extends RefCounted
## What's happening at the table, one line at a time, for the text box at
## the bottom of the screen ("Honk raises to 60!"), the way a handheld RPG's
## battle text tells you each move. It replaced a five-line log in the
## corner that was too small to read on a 7" screen and that nobody looked
## at mid-hand.
##
## Each line has a time to appear (`at`): the rules engine reports a whole
## all-in run-out or a showdown at once, but "Honk wins 274!" should only
## type out when the pot actually slides to Honk (TableMotion's beat). The
## box shows the newest two lines that have appeared; the newest types out
## at TYPE_SPEED characters a second, fast enough never to hold up play.

const TYPE_SPEED := 90.0
const KEEP := 12

var lines: Array[Dictionary] = []  ## {"text", "color", "at"}, oldest first


func add(text: String, color: Color, at: float) -> void:
	# In time order; lines booked for the same moment keep the order they
	# were said in (sort_custom isn't stable).
	var k := lines.size()
	while k > 0 and lines[k - 1]["at"] > at:
		k -= 1
	lines.insert(k, {"text": text, "color": color, "at": at})
	if lines.size() > KEEP:
		lines.pop_front()


func clear() -> void:
	lines.clear()


## The last `count` lines that have appeared by `now`, oldest first.
func visible(now: float, count := 2) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for line in lines:
		if line["at"] <= now:
			out.append(line)
	return out.slice(maxi(0, out.size() - count))


## How much of `line` has typed out by `now`.
static func typed(line: Dictionary, now: float) -> String:
	var text: String = line["text"]
	var n := int((now - float(line["at"])) * TYPE_SPEED)
	return text.left(clampi(n, 0, text.length()))


## True while the newest visible line is still typing.
func typing(now: float) -> bool:
	var shown := visible(now, 1)
	return not shown.is_empty() and typed(shown[0], now).length() < String(shown[0]["text"]).length()
