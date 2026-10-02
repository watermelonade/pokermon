class_name ContentChecks
extends RefCounted
## The checks the editor will run live (docs/EDITOR_SPEC.md C-CHECKS), as a
## library the tests use too: whether the world is playable, where
## ContentSchema says whether the files are well formed.
##
## - Doors: every door on every map can be walked to from the start (gates
##   open, townsfolk standing where they stand; crews don't count, since a
##   crew walks up to you and is beaten or not, and two of them are meant
##   to block the road until then), and leads to a map that exists.
## - Nobody in the way: no townsperson stands where every way to a map, a
##   door or a card passes, with Sootbridge's gate shut or open (each one is
##   lifted out in turn, everyone else too, and the walk compared).
## - Cards: every card lying about, and every townsperson giving one, can
##   be reached; a card the gate needs (an Ace, for "full_deck") with the
##   gate shut, or the deck could never be whole.
## - Words: every line fits the dialog box (docs/WRITING.md): at most 84
##   characters, two wrapped rows in DialogBox's font, four boxes a speech;
##   {placeholders} filled with worst cases.
##
## Each problem is one string naming the map and the thing, e.g.
##   town: bertram at (30, 9) stands where every way to the door at (92, 9) on town passes
## and problems() is all of them ([] for a playable world). On today's
## world that's every check, all maps, in about 0.35 s headless (the
## nobody-in-the-way walk, once per townsperson per gate state, is most of
## it): fine on a save, a bit slow for every brush stroke.
##
## Walking the maps used to be tests/world_paths.gd's (written for demo 2's
## W-* tests, which compute reachability from the map data rather than ask
## the game's own queries); it moved here so the editor and the tests share
## one copy, and world_paths.gd now hands its calls on. Everything takes the
## maps to check as {id: WorldMap} ({} is the game's own, WorldMap.get_map),
## so the editor can check maps it hasn't saved and the test can check a
## made-up yard (tests/test_content.gd, which also shows each check failing).

const DIRS: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
## The text box (DialogBox, at the 640x400 base resolution): see
## docs/WRITING.md and tests/test_writing.gd for where the numbers come from.
const BASE_WIDTH := 640.0
const MAX_WRAPPED := 2
const MAX_CHARS := 84
const MAX_BOXES := 4
## Worst cases for placeholders and format strings: the longest crew title
## (two names joined) and a big sum of money.
const LONG_NAME := "Bramble the Owl and Chitter the Squirrel"
const BIG_NUMBER := "99999"


## A walk over the maps: which cells are open, from where to where.
class Walk:
	var maps: Dictionary  ## map id -> WorldMap ({}: the game's)
	var gate_open: bool
	var bodies: bool  ## townsfolk (and crews, if `crews`) stand where they stand at home
	var crews: bool
	var blocked: Dictionary  ## {map id: {cell: true}}: cells nobody may step on
	var _bodies := {}  ## map id -> {cell: true}
	var _gates := {}  ## map id -> gate cells

	func _init(m: Dictionary, open: bool, with_bodies := true, block := {}, with_crews := true) -> void:
		maps = m
		gate_open = open
		bodies = with_bodies
		blocked = block
		crews = with_crews

	func has_map(id: String) -> bool:
		return maps.has(id) if maps else WorldMap.has_map(id)

	func get_map(id: String) -> WorldMap:
		return maps[id] if maps else WorldMap.get_map(id)

	## Whether `cell` on `m` can be stood on: a walkable tile, nobody
	## standing there, not blocked, and not a shut gate's.
	func is_open(m: WorldMap, cell: Vector2i) -> bool:
		if not m.tile_walkable(cell):
			return false
		if bodies:
			if not _bodies.has(m.id):
				var out := {}
				for n: Dictionary in m.npcs:
					out[n["cell"]] = true
				if crews:
					for c: Dictionary in m.crews:
						for at in WorldMap.crew_cells(c):
							out[at] = true
				_bodies[m.id] = out
			if (_bodies[m.id] as Dictionary).has(cell):
				return false
		if blocked.has(m.id) and (blocked[m.id] as Dictionary).has(cell):
			return false
		return gate_open or not gate_cells(m).has(cell)

	func gate_cells(m: WorldMap) -> Dictionary:
		if not _gates.has(m.id):
			_gates[m.id] = ContentChecks.gate_cells(m)
		return _gates[m.id]

	## {map id: {cell: steps}} from `start_cell` on `start_map`, through
	## doors (a door and where it leads count the same steps).
	func reach(start_map: String, start_cell: Vector2i) -> Dictionary:
		var out := {}
		if not has_map(start_map):
			return out
		var queue: Array = [[start_map, start_cell, 0]]
		out[start_map] = {start_cell: 0}
		var head := 0
		while head < queue.size():
			var item: Array = queue[head]
			head += 1
			var map_id: String = item[0]
			var cell: Vector2i = item[1]
			var steps: int = item[2]
			var m := get_map(map_id)
			var w := m.warp_at(cell)
			if not w.is_empty() and cell != start_cell and has_map(w["to"]):
				var to: String = w["to"]
				var to_cell: Vector2i = w["to_cell"]
				if not out.has(to):
					out[to] = {}
				if not out[to].has(to_cell):
					out[to][to_cell] = steps
					queue.append([to, to_cell, steps])
				continue
			for d in ContentChecks.DIRS:
				var next: Vector2i = cell + d
				if out[map_id].has(next) or not is_open(m, next):
					continue
				out[map_id][next] = steps + 1
				queue.append([map_id, next, steps + 1])
		return out

	## {cell: steps} on one map from `from`, not through doors.
	func distances(m: WorldMap, from: Vector2i) -> Dictionary:
		var out := {from: 0}
		var queue: Array[Vector2i] = [from]
		var head := 0
		while head < queue.size():
			var c: Vector2i = queue[head]
			head += 1
			if not m.warp_at(c).is_empty() and c != from:
				continue  # a door: you'd be through it
			for d in ContentChecks.DIRS:
				var n: Vector2i = c + d
				if out.has(n) or not is_open(m, n):
					continue
				out[n] = out[c] + 1
				queue.append(n)
		return out


# --- Walking (tests/world_paths.gd hands its calls on to these) ------------------

## Every cell you can reach from `start_cell` on `start_map`, map by map:
## {map id: {cell: steps}}. `bodies`: everyone (townsfolk and crews) stands
## where they stand at home; `blocked` ({map id: {cell: true}}) is off
## limits; a gate's cells are shut unless `gate_open`.
static func reach(start_map: String, start_cell: Vector2i, gate_open: bool, bodies := true, blocked := {}, maps := {}) -> Dictionary:
	return Walk.new(maps, gate_open, bodies, blocked).reach(start_map, start_cell)


## Steps from `from` to every cell reachable on this one map (no doors
## followed): {cell: steps}.
static func distances(m: WorldMap, from: Vector2i, gate_open: bool, bodies := true, blocked := {}) -> Dictionary:
	return Walk.new({m.id: m}, gate_open, bodies, blocked).distances(m, from)


## Whether `cell` on `m` can be stood on (see reach).
static func is_open(m: WorldMap, cell: Vector2i, gate_open: bool, bodies := true, blocked := {}) -> bool:
	return Walk.new({m.id: m}, gate_open, bodies, blocked).is_open(m, cell)


## Every gate cell on the map (cell -> the gate).
static func gate_cells(m: WorldMap) -> Dictionary:
	var out := {}
	for g: Dictionary in m.gates:
		for c: Vector2i in g.get("cells", []):
			out[c] = g
	return out


## Cells next to `cell` you could stand on to talk to someone there (and
## across a counter, as the overworld allows).
static func talk_spots(m: WorldMap, cell: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for d in DIRS:
		out.append(cell + d)
		if m.char_at(cell + d) == "C":
			out.append(cell + d * 2)
	return out


# --- The checks -------------------------------------------------------------

## Every problem with the world (see the top), [] if none. `maps` {id:
## WorldMap}, the game's by default; the walk starts at `start_cell` on
## `start_map`. With the game's maps, the lines the code says by name
## (Content.CODE_LINES) are checked too.
static func problems(maps := {}, start_map := WorldMap.START_MAP, start_cell := WorldMap.START_CELL) -> Array[String]:
	var game := maps.is_empty()
	if game:
		for id: String in WorldMap.ids():
			maps[id] = WorldMap.get_map(id)
	var out: Array[String] = []
	out.append_array(doors(maps, start_map, start_cell))
	out.append_array(in_the_way(maps, start_map, start_cell))
	out.append_array(cards(maps, start_map, start_cell))
	out.append_array(words(maps))
	if game:
		for want: Array in Content.CODE_LINES:
			out.append_array(speech_problems(Content.say(want[0], want[1], want[2]).map(_fill), "%s.%s (%s)" % want))
	return out


## Doors that lead nowhere or can't be walked to (see the top).
static func doors(maps: Dictionary, start_map: String, start_cell: Vector2i) -> Array[String]:
	var out: Array[String] = []
	var reached := Walk.new(maps, true, true, {}, false).reach(start_map, start_cell)
	for id: String in maps:
		var m: WorldMap = maps[id]
		for w: Dictionary in m.warps:
			if not maps.has(w["to"]):
				out.append("%s: the door at %s leads to %s, which isn't a map" % [id, w["cell"], w["to"]])
		if not reached.has(id):
			out.append("%s: can't be reached from the start (%s %s)" % [id, start_map, start_cell])
			continue
		for w: Dictionary in m.warps:
			if not (reached[id] as Dictionary).has(w["cell"]):
				out.append("%s: the door at %s can't be reached from the start" % [id, w["cell"]])
	return out


## Townsfolk standing where every way to a map, door or card passes.
static func in_the_way(maps: Dictionary, start_map: String, start_cell: Vector2i) -> Array[String]:
	var out: Array[String] = []
	var said := {}  ## "map/npc" -> true: one problem each, the gate shut first
	var gated := maps.values().any(func(m: WorldMap) -> bool: return not m.gates.is_empty())
	for gate_open: bool in ([false, true] if gated else [true]):
		var all := _places(Walk.new(maps, gate_open, false).reach(start_map, start_cell), maps)
		for id: String in maps:
			for n: Dictionary in (maps[id] as WorldMap).npcs:
				var cell: Vector2i = n["cell"]
				if said.has("%s/%s" % [id, n["id"]]):
					continue
				var without := _places(Walk.new(maps, gate_open, false, {id: {cell: true}}).reach(start_map, start_cell), maps)
				for place: String in all:
					if not without.has(place):
						out.append("%s: %s at %s stands where every way to %s passes%s" % [id, n["id"], cell, place,
							"" if gate_open else " (with the gate shut)"])
						said["%s/%s" % [id, n["id"]]] = true
						break
	return out


## What a walk got to that matters: each map, door and card (by name).
static func _places(reached: Dictionary, maps: Dictionary) -> Dictionary:
	var out := {}
	for id: String in reached:
		out[id] = true
		var m: WorldMap = maps[id]
		for w: Dictionary in m.warps:
			if (reached[id] as Dictionary).has(w["cell"]):
				out["the door at %s on %s" % [w["cell"], id]] = true
		for p: Dictionary in m.pickups():
			if (reached[id] as Dictionary).has(p["cell"]):
				out["%s on %s" % [p["id"], id]] = true
	return out


## Cards lying about, and townsfolk giving one, that can't be reached (see
## the top: a card a gate needs, with the gate shut).
static func cards(maps: Dictionary, start_map: String, start_cell: Vector2i) -> Array[String]:
	var out: Array[String] = []
	var needed := GameState.opening_missing_cards()
	var shut := Walk.new(maps, false, true, {}, false).reach(start_map, start_cell)
	var open := Walk.new(maps, true, true, {}, false).reach(start_map, start_cell)
	for id: String in maps:
		var m: WorldMap = maps[id]
		for p: Dictionary in m.pickups():
			var gate_needs: bool = needed.has(int(p["card"]))
			var reached: Dictionary = (shut if gate_needs else open).get(id, {})
			if not reached.has(p["cell"]):
				out.append("%s: card %s at %s can't be reached from the start%s" % [id, p["id"], p["cell"],
					" with the gate shut (the gate needs it)" if gate_needs else ""])
		for n: Dictionary in m.npcs:
			if not n.has("gives_card"):
				continue
			var gate_needs: bool = needed.has(int(n["gives_card"]["card"]))
			var reached: Dictionary = (shut if gate_needs else open).get(id, {})
			if not talk_spots(m, n["cell"]).any(func(c: Vector2i) -> bool: return reached.has(c)):
				out.append("%s: nobody can walk up to %s at %s for card %s%s" % [id, n["id"], n["cell"], n["gives_card"]["id"],
					" with the gate shut (the gate needs it)" if gate_needs else ""])
	return out


## Lines on the maps that don't fit the box: signs and gates (a box each),
## what townsfolk and crews say.
static func words(maps: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for id: String in maps:
		var m: WorldMap = maps[id]
		for s: Dictionary in m.signs:
			out.append_array(line_problems(s["text"], "%s sign at %s" % [id, s["cell"]]))
		for g: Dictionary in m.gates:
			out.append_array(line_problems(g["text"], "%s gate" % id))
		for n: Dictionary in m.npcs:
			out.append_array(speech_problems(n["lines"], "%s %s" % [id, n["id"]]))
			if n.has("after"):
				out.append_array(speech_problems(n["after"], "%s %s after" % [id, n["id"]]))
		for c: Dictionary in m.crews:
			out.append_array(speech_problems(c["before"], "%s %s before" % [id, c["id"]]))
			out.append_array(line_problems(c["after"], "%s %s after" % [id, c["id"]]))
	return out


## {placeholders} as their worst cases.
static func _fill(text: String) -> String:
	return text.format({"crew": LONG_NAME, "lost": BIG_NUMBER})


## The width DialogBox wraps its text to (see DialogBox._draw).
static func box_width() -> float:
	return (BASE_WIDTH - 16.0) - 30.0


## Rows `text` wraps to in the box: greedy word wrap, as the box does.
static func wrapped_lines(text: String) -> int:
	var width := box_width()
	var lines := 1
	var current := ""
	for word in text.split(" "):
		var attempt := word if current == "" else current + " " + word
		if UiKit.text_width(attempt, 10) <= width or current == "":
			current = attempt
		else:
			lines += 1
			current = word
	return lines


## Why one box's text doesn't fit ([] if it does): empty, over MAX_CHARS
## (unless `cap_chars` is off, for code's format strings), or wrapping to
## more than MAX_WRAPPED rows.
static func line_problems(text: String, where: String, cap_chars := true) -> Array[String]:
	var out: Array[String] = []
	if text.strip_edges() == "":
		out.append("%s: empty line" % where)
	if cap_chars and text.length() > MAX_CHARS:
		out.append("%s: %d characters (max %d): %s" % [where, text.length(), MAX_CHARS, text])
	var n := wrapped_lines(text)
	if n > MAX_WRAPPED:
		out.append("%s: wraps to %d lines (max %d): %s" % [where, n, MAX_WRAPPED, text])
	return out


## Why a speech (one box per line) doesn't fit: too many boxes, or a line.
static func speech_problems(lines: Array, where: String) -> Array[String]:
	var out: Array[String] = []
	if lines.size() > MAX_BOXES:
		out.append("%s: %d boxes (max %d)" % [where, lines.size(), MAX_BOXES])
	for i in lines.size():
		out.append_array(line_problems(str(lines[i]), "%s[%d]" % [where, i]))
	return out
