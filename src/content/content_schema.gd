class_name ContentSchema
extends RefCounted
## Whether content/ is valid (docs/EDITOR_SPEC.md C-SCHEMA): every file has
## its required keys with the right kinds of value and no keys it shouldn't
## have (a typo like "facnig" is caught, not ignored), maps are rectangles
## of known tiles, cells are inside their map, enum values are names the
## game knows, doors lead to maps that exist and land on walkable cells,
## everything placed that talks has its lines, every line id is unique
## game-wide and every status is placeholder/draft/final, and the atlas and
## the maps name each other. Plus the lines the code asks for by name
## (Content.CODE_LINES).
##
## Every problem is one string naming the file and the field:
##   content/maps/town.json: crews[0].facing: "dwon" isn't a facing (up, down, left, right)
## so the editor (phase 2) can show it where it is, and a hand edit that
## breaks something fails tests/test_content.gd with a message that says
## what to fix.
##
## It checks data, not files: check() takes {path: data} (Content.docs(),
## or the editor's unsaved copies), so a test breaks one thing in a copy of
## the real content and asks. Whether the world is playable (doors
## reachable, nobody in the way, lines fitting the box) is ContentChecks'.

const KINDS: Array[String] = ["town", "route", "interior"]
const AREA_STATUSES: Array[String] = ["blockout", "draft", "final"]
const REQUIRES: Array[String] = ["full_deck"]
const LINE_ID := "^[a-z0-9_]+\\.[a-z0-9_]+\\.[0-9]+$"

## The keys each kind of record has: required, then optional.
const AREA_KEYS := [["id", "map", "name", "region", "kind", "status", "notes"], ["rect"]]
const MAP_KEYS := [["id", "outdoor", "rows", "labels", "warps", "gates", "pickups", "signs", "open_tables", "npcs", "crews"], []]
const LABEL_KEYS := [["rect", "text"], []]
const WARP_KEYS := [["cell", "to", "to_cell", "facing"], []]
const GATE_KEYS := [["cells", "requires", "dialogue"], []]
const PICKUP_KEYS := [["id", "cell", "card"], []]
const SIGN_KEYS := [["cell", "dialogue"], []]
const TABLE_KEYS := [["id", "dealer", "players"], ["buy_in", "stake", "blinds", "max_money"]]
const NPC_KEYS := [["id", "name", "sprite", "cell", "facing", "dialogue"], ["asleep", "open_table", "animal", "gives_card"]]
const CREW_KEYS := [["id", "name", "cell", "facing", "sight", "members", "reward", "chips", "dealer", "dialogue"],
	["boss", "tournament", "bracelet", "bond"]]
const GIFT_KEYS := [["id", "card"], []]
const LINE_KEYS := [["id", "text", "status"], []]


## Every problem in `docs` ({res:// path: data}), or [] if it's all valid.
static func check(docs: Dictionary) -> Array[String]:
	var c := _Checker.new(docs)
	c.run()
	return c.out


## Every problem in content/ on disk, files that don't parse included.
static func check_files() -> Array[String]:
	var out: Array[String] = []
	var docs := {}
	for path in Content.files():
		var text := FileAccess.get_file_as_string(path)
		var data: Variant = ContentFormat.parse(text)
		if data is Dictionary:
			docs[path] = data
		else:
			out.append("%s: doesn't parse: %s" % [path.trim_prefix("res://"), ContentFormat.parse_error(text)])
	out.append_array(check(docs))
	return out


## One pass over the docs, collecting problems.
class _Checker:
	var docs: Dictionary
	var out: Array[String] = []
	var maps := {}  ## map id -> data
	var talk := {}  ## dialogue or script file id -> {speaker id: speaker}
	var talk_paths := {}  ## file id -> path
	var line_ids := {}  ## line id -> where it was first seen
	var pickup_ids := {}  ## pickup or gift id -> where
	var crew_ids := {}  ## crew id -> where
	var _file := ""

	func _init(d: Dictionary) -> void:
		docs = d

	func run() -> void:
		var maps_dir := Content.ROOT + "/maps/"
		var talk_dir := Content.ROOT + "/dialogue/"
		var script_dir := Content.ROOT + "/script/"
		for path: String in docs:
			var id := path.get_file().get_basename()
			if path.begins_with(maps_dir):
				maps[id] = docs[path]
			elif path.begins_with(talk_dir) or path.begins_with(script_dir):
				talk_paths[id] = path
			elif path != Content.atlas_path():
				_at(path)
				_bad("", "isn't a content file the game reads (atlas.json, maps/, dialogue/, script/)")
		# The words first: the maps check their speakers against them.
		for id: String in talk_paths:
			_talk_file(id, talk_paths[id])
		for id: String in maps:
			_map(id, maps[id])
			if not talk_paths.has(id):
				_at(Content.map_path(id))
				_bad("", "has no dialogue file (%s)" % _short(Content.dialogue_path(id)))
		for id: String in talk_paths:
			if talk_paths[id].begins_with(talk_dir) and not maps.has(id):
				_at(talk_paths[id])
				_bad("", "is the dialogue for a map that doesn't exist (%s)" % _short(Content.map_path(id)))
			if talk_paths[id].begins_with(script_dir) and not Content.SCRIPTS.has(id):
				_at(talk_paths[id])
				_bad("", "isn't one of the scripts the game reads (Content.SCRIPTS)")
		for id: String in Content.SCRIPTS:
			if maps.has(id):
				# Lines are found by file id (Content.say): a map and a script
				# of the same name would be one file id for two files.
				_at(Content.map_path(id))
				_bad("id", "%s is also a script's id (content/script/%s.json): pick another" % [_show(id), id])
		_atlas()
		for want: Array in Content.CODE_LINES:
			var speaker: Dictionary = talk.get(want[0], {}).get(want[1], {})
			if (speaker.get(want[2], []) as Array).is_empty():
				_at(talk_paths.get(want[0], Content.script_path(want[0]) if Content.SCRIPTS.has(want[0]) else Content.dialogue_path(want[0])))
				_bad("speakers", "no \"%s\" lines for %s, which the code says (Content.CODE_LINES)" % [want[2], want[1]])

	# --- Reporting --------------------------------------------------------

	## A value as the file shows it (cells as [5, 3]).
	func _show(v: Variant) -> String:
		return JSON.stringify(v) if v is Dictionary else ContentFormat.flat(v)

	func _short(path: String) -> String:
		return path.trim_prefix("res://")

	func _at(path: String) -> void:
		_file = _short(path)

	func _bad(field: String, why: String) -> void:
		out.append("%s: %s%s" % [_file, field + ": " if field else "", why])

	## Required keys there, no unknown ones; false if a required one is missing.
	func _keys(d: Variant, keys: Array, field: String) -> bool:
		if not d is Dictionary:
			_bad(field, "should be an object ({...}), is %s" % _show(d))
			return false
		var ok := true
		for k: String in keys[0]:
			if not (d as Dictionary).has(k):
				_bad(_join(field, k), "missing")
				ok = false
		for k: Variant in d:
			if not keys[0].has(k) and not keys[1].has(k):
				_bad(_join(field, str(k)), "isn't a key this has (%s)" % ", ".join(keys[0] + keys[1]))
		return ok

	func _join(field: String, key: String) -> String:
		return key if field == "" else "%s.%s" % [field, key]

	func _list(v: Variant, field: String) -> Array:
		if v is Array:
			return v
		_bad(field, "should be a list ([...]), is %s" % _show(v))
		return []

	func _string(v: Variant, field: String, empty_ok := false) -> bool:
		if not v is String or (not empty_ok and (v as String).strip_edges() == ""):
			_bad(field, "should be %stext, is %s" % ["" if empty_ok else "non-empty ", _show(v)])
			return false
		return true

	func _int(v: Variant, field: String, at_least := 0) -> bool:
		if not (v is float or v is int) or float(v) != floorf(float(v)) or float(v) < at_least:
			_bad(field, "should be a whole number of at least %d, is %s" % [at_least, _show(v)])
			return false
		return true

	func _bool(v: Variant, field: String) -> void:
		if not v is bool:
			_bad(field, "should be true or false, is %s" % _show(v))

	func _one_of(v: Variant, names: Array, field: String, what: String) -> bool:
		if not names.has(v):
			_bad(field, "%s isn't %s (%s)" % [_show(v), what, ", ".join(names)])
			return false
		return true

	## [x, y] inside the map (`w` x `h`); false (and said why) if not.
	func _cell(v: Variant, w: int, h: int, field: String) -> bool:
		if not (v is Array and v.size() == 2 and v.all(func(n: Variant) -> bool: return (n is float or n is int) and float(n) == floorf(float(n)))):
			_bad(field, "should be a cell [x, y], is %s" % _show(v))
			return false
		if int(v[0]) < 0 or int(v[1]) < 0 or int(v[0]) >= w or int(v[1]) >= h:
			_bad(field, "%s is outside the map (%dx%d)" % [_show(v), w, h])
			return false
		return true

	func _walkable(rows: Array, v: Variant, field: String, what := "") -> void:
		var row := str(rows[int(v[1])])
		var tile := row[int(v[0])] if int(v[0]) < row.length() else ""
		if not WorldMap.TILES.get(tile, ["", false])[1]:
			_bad(field, "%s%s is a %s: not walkable" % [_show(v), what, WorldMap.TILES.get(tile, ["?"])[0]])

	func _animal(v: Variant, field: String) -> void:
		if not (v is Array and v.size() == 2 and v[0] is String):
			_bad(field, "should be [species, individual], is %s" % _show(v))
			return
		if not Species.CATALOG.has(StringName(v[0])):
			_bad(field, "%s isn't a species (%s)" % [_show(v[0]), ", ".join(Species.ids())])
			return
		var names: Array = Species.CATALOG[StringName(v[0])]["individuals"]
		if _int(v[1], field + "[1]"):
			if int(v[1]) >= names.size():
				_bad(field + "[1]", "a %s's individual is 0-%d, not %s" % [v[0], names.size() - 1, _show(v[1])])

	func _card(v: Variant, field: String) -> void:
		if not (v is String and (v as String).length() == 2 and Card.RANK_CHARS.contains(v[0]) and Card.SUIT_CHARS.contains(v[1])):
			_bad(field, "%s isn't a card (rank 2-9TJQKA and suit cdhs: \"As\", \"Td\")" % _show(v))

	## The speaker `id` in map `map_id`'s dialogue has `which` lines (and
	## exactly one if `one`).
	func _speaks(map_id: String, id: Variant, which: String, field: String, one := false) -> void:
		var speaker: Dictionary = talk.get(map_id, {}).get(str(id), {})
		var lines: Array = speaker.get(which, []) if speaker.get(which, []) is Array else []
		if lines.is_empty():
			_bad(field, "no speaker %s with \"%s\" lines in %s" % [_show(id), which, _short(Content.dialogue_path(map_id))])
		elif one and lines.size() != 1:
			_bad(field, "%s's \"%s\" should be one line (it's shown in one box), has %d" % [id, which, lines.size()])

	# --- Files --------------------------------------------------------------

	func _atlas() -> void:
		var path := Content.atlas_path()
		_at(path)
		if not docs.has(path):
			_bad("", "missing")
			return
		var atlas: Variant = docs[path]
		if not _keys(atlas, [["areas"], []], ""):
			return
		var ids := {}
		var mapped := {}
		var areas := _list(atlas["areas"], "areas")
		for i in areas.size():
			var f := "areas[%d]" % i
			var a: Variant = areas[i]
			if not _keys(a, AREA_KEYS, f):
				continue
			if _string(a["id"], f + ".id"):
				if ids.has(a["id"]):
					_bad(f + ".id", "%s is used twice" % _show(a["id"]))
				ids[a["id"]] = true
			_string(a["name"], f + ".name")
			_string(a["region"], f + ".region")
			_string(a["notes"], f + ".notes", true)
			_one_of(a["kind"], KINDS, f + ".kind", "a kind")
			_one_of(a["status"], AREA_STATUSES, f + ".status", "a status")
			if not maps.has(a["map"]):
				_bad(f + ".map", "no map %s (%s)" % [_show(a["map"]), _short(Content.map_path(str(a["map"])))])
				continue
			mapped[a["map"]] = true
			if a.has("rect"):
				var r: Variant = a["rect"]
				var rows: Array = maps[a["map"]].get("rows", [])
				var w := str(rows[0]).length() if rows else 0
				if not (r is Array and r.size() == 4 and _cell([r[0], r[1]], w, rows.size(), f + ".rect")
						and _int(r[2], f + ".rect[2]", 1) and _int(r[3], f + ".rect[3]", 1)):
					continue
				if int(r[0]) + int(r[2]) > w or int(r[1]) + int(r[3]) > rows.size():
					_bad(f + ".rect", "%s runs off the map (%dx%d)" % [_show(r), w, rows.size()])
		for id: String in maps:
			if not mapped.has(id):
				_at(Content.map_path(id))
				_bad("", "no atlas area (%s) names this map" % _short(path))

	func _talk_file(id: String, path: String) -> void:
		_at(path)
		var d: Variant = docs[path]
		talk[id] = {}
		if not _keys(d, [["id", "speakers"], []], ""):
			return
		if d["id"] != id:
			_bad("id", "%s, but the file is %s" % [_show(d["id"]), path.get_file()])
		var speakers := _list(d["speakers"], "speakers")
		for i in speakers.size():
			var f := "speakers[%d]" % i
			var s: Variant = speakers[i]
			if not (s is Dictionary and s.has("id") and _string(s["id"], f + ".id")):
				_keys(s, [["id"], []], f)
				continue
			if talk[id].has(s["id"]):
				_bad(f + ".id", "%s is used twice in this file" % _show(s["id"]))
			talk[id][s["id"]] = s
			if s.size() < 2:
				_bad(f, "%s has no lines" % s["id"])
			for which: Variant in s:
				if which == "id":
					continue
				var lines := _list(s[which], "%s.%s" % [f, which])
				if lines.is_empty():
					_bad("%s.%s" % [f, which], "empty: a set of lines has at least one")
				for j in lines.size():
					_line(lines[j], "%s.%s[%d]" % [f, which, j])

	func _line(l: Variant, f: String) -> void:
		if not _keys(l, LINE_KEYS, f):
			return
		_string(l["text"], f + ".text")
		_one_of(l["status"], Content.STATUSES, f + ".status", "placeholder, draft or final")
		if not _string(l["id"], f + ".id"):
			return
		if not RegEx.create_from_string(LINE_ID).search(l["id"]):
			_bad(f + ".id", "%s isn't <file>.<speaker>.<n> (lowercase, e.g. sootbridge.mags.1)" % _show(l["id"]))
		if line_ids.has(l["id"]):
			_bad(f + ".id", "%s is used twice (also %s)" % [_show(l["id"]), line_ids[l["id"]]])
		else:
			line_ids[l["id"]] = "%s %s" % [_file, f]

	func _map(id: String, m: Variant) -> void:
		_at(Content.map_path(id))
		if not _keys(m, MAP_KEYS, ""):
			return
		if m["id"] != id:
			_bad("id", "%s, but the file is %s.json" % [_show(m["id"]), id])
		if not m["outdoor"] is bool:
			_bad("outdoor", "should be true or false, is %s" % _show(m["outdoor"]))
		var rows := _list(m["rows"], "rows")
		if rows.is_empty() or not rows[0] is String or (rows[0] as String).is_empty():
			_bad("rows", "a map needs at least one row of tiles")
			return
		var w := (rows[0] as String).length()
		var h := rows.size()
		for y in h:
			if not _string(rows[y], "rows[%d]" % y):
				return
			var row: String = rows[y]
			if row.length() != w:
				_bad("rows[%d]" % y, "%d wide, the map is %d wide (its first row)" % [row.length(), w])
			for x in row.length():
				if not WorldMap.TILES.has(row[x]):
					_bad("rows[%d]" % y, "unknown tile \"%s\" at x %d (the tiles: WorldMap.TILES)" % [row[x], x])
		for i in _list(m["labels"], "labels").size():
			var f := "labels[%d]" % i
			var l: Variant = m["labels"][i]
			if _keys(l, LABEL_KEYS, f):
				_string(l["text"], f + ".text")
				var r: Variant = l["rect"]
				if not (r is Array and r.size() == 4 and _cell([r[0], r[1]], w, h, f + ".rect")):
					_bad(f + ".rect", "should be [x, y, width, height] on the map, is %s" % _show(r))
		for i in _list(m["warps"], "warps").size():
			var f := "warps[%d]" % i
			var wp: Variant = m["warps"][i]
			if not _keys(wp, WARP_KEYS, f):
				continue
			if _cell(wp["cell"], w, h, f + ".cell"):
				_walkable(rows, wp["cell"], f + ".cell")
			_one_of(wp["facing"], Content.FACINGS.keys(), f + ".facing", "a facing")
			if not maps.has(wp["to"]):
				_bad(f + ".to", "no map %s (%s)" % [_show(wp["to"]), _short(Content.map_path(str(wp["to"])))])
				continue
			var dest: Dictionary = maps[wp["to"]] if maps[wp["to"]] is Dictionary else {}
			var drows: Array = dest.get("rows", []) if dest.get("rows", []) is Array else []
			if drows and drows[0] is String and _cell(wp["to_cell"], (drows[0] as String).length(), drows.size(), f + ".to_cell"):
				_walkable(drows, wp["to_cell"], f + ".to_cell", " on %s" % wp["to"])
		for i in _list(m["gates"], "gates").size():
			var f := "gates[%d]" % i
			var g: Variant = m["gates"][i]
			if not _keys(g, GATE_KEYS, f):
				continue
			var cells := _list(g["cells"], f + ".cells")
			if cells.is_empty():
				_bad(f + ".cells", "a gate covers at least one cell")
			for j in cells.size():
				if _cell(cells[j], w, h, "%s.cells[%d]" % [f, j]):
					_walkable(rows, cells[j], "%s.cells[%d]" % [f, j])
			_one_of(g["requires"], REQUIRES, f + ".requires", "a gate rule")
			_speaks(id, g["dialogue"], "lines", f + ".dialogue", true)
		for i in _list(m["pickups"], "pickups").size():
			var f := "pickups[%d]" % i
			var p: Variant = m["pickups"][i]
			if not _keys(p, PICKUP_KEYS, f):
				continue
			_pickup_id(p["id"], f + ".id")
			if _cell(p["cell"], w, h, f + ".cell"):
				_walkable(rows, p["cell"], f + ".cell")
			_card(p["card"], f + ".card")
		for i in _list(m["signs"], "signs").size():
			var f := "signs[%d]" % i
			var s: Variant = m["signs"][i]
			if _keys(s, SIGN_KEYS, f):
				_cell(s["cell"], w, h, f + ".cell")
				_speaks(id, s["dialogue"], "lines", f + ".dialogue", true)
		var tables := {}
		for i in _list(m["open_tables"], "open_tables").size():
			var f := "open_tables[%d]" % i
			var t: Variant = m["open_tables"][i]
			if not _keys(t, TABLE_KEYS, f):
				continue
			if _string(t["id"], f + ".id"):
				tables[t["id"]] = true
			_one_of(t["dealer"], Dealer.Kind.keys(), f + ".dealer", "a dealer")
			var players := _list(t["players"], f + ".players")
			for j in players.size():
				_animal(players[j], "%s.players[%d]" % [f, j])
			if not t.has("buy_in") and not t.has("stake"):
				_bad(f, "has neither a buy_in (a cash table) nor a stake (a street game)")
			for k: String in ["buy_in", "stake", "max_money"]:
				if t.has(k):
					_int(t[k], "%s.%s" % [f, k], 1)
			if t.has("stake") and not (t.has("blinds") and t.has("max_money")):
				_bad(f, "a street game (a stake) has blinds and max_money too")
			if t.has("blinds") and not (t["blinds"] is Array and t["blinds"].size() == 2):
				_bad(f + ".blinds", "should be [small, big], is %s" % _show(t["blinds"]))
		var npc_ids := {}
		for i in _list(m["npcs"], "npcs").size():
			var f := "npcs[%d]" % i
			var n: Variant = m["npcs"][i]
			if not _keys(n, NPC_KEYS, f):
				continue
			if _string(n["id"], f + ".id"):
				if npc_ids.has(n["id"]):
					_bad(f + ".id", "%s is used twice on this map" % _show(n["id"]))
				npc_ids[n["id"]] = true
			_string(n["name"], f + ".name")
			_string(n["sprite"], f + ".sprite")
			if _cell(n["cell"], w, h, f + ".cell"):
				_walkable(rows, n["cell"], f + ".cell")
			_one_of(n["facing"], Content.FACINGS.keys(), f + ".facing", "a facing")
			_speaks(id, n["dialogue"], "lines", f + ".dialogue")
			if n.has("asleep"):
				_bool(n["asleep"], f + ".asleep")
			if n.has("open_table") and not tables.has(n["open_table"]):
				_bad(f + ".open_table", "no open table %s on this map (open_tables)" % _show(n["open_table"]))
			if n.has("animal"):
				_animal(n["animal"], f + ".animal")
			if n.has("gives_card") and _keys(n["gives_card"], GIFT_KEYS, f + ".gives_card"):
				_pickup_id(n["gives_card"]["id"], f + ".gives_card.id")
				_card(n["gives_card"]["card"], f + ".gives_card.card")
		for i in _list(m["crews"], "crews").size():
			var f := "crews[%d]" % i
			var c: Variant = m["crews"][i]
			if not _keys(c, CREW_KEYS, f):
				continue
			if _string(c["id"], f + ".id"):
				if crew_ids.has(c["id"]):
					_bad(f + ".id", "%s is used twice (also %s): a crew id is a save's record of beating it" % [_show(c["id"]), crew_ids[c["id"]]])
				crew_ids[c["id"]] = "%s %s" % [_file, f]
			_string(c["name"], f + ".name")
			if _cell(c["cell"], w, h, f + ".cell"):
				_walkable(rows, c["cell"], f + ".cell")
			_one_of(c["facing"], Content.FACINGS.keys(), f + ".facing", "a facing")
			_int(c["sight"], f + ".sight")
			_int(c["reward"], f + ".reward", 1)
			_int(c["chips"], f + ".chips", 1)
			_one_of(c["dealer"], Dealer.Kind.keys(), f + ".dealer", "a dealer")
			var members := _list(c["members"], f + ".members")
			if members.is_empty():
				_bad(f + ".members", "a crew has at least one member")
			for j in members.size():
				_animal(members[j], "%s.members[%d]" % [f, j])
			_speaks(id, c["dialogue"], "before", f + ".dialogue")
			_speaks(id, c["dialogue"], "after", f + ".dialogue", true)
			for k: String in ["boss", "tournament"]:
				if c.has(k):
					_bool(c[k], "%s.%s" % [f, k])
			if c.has("bracelet"):
				_string(c["bracelet"], f + ".bracelet")
				_speaks(id, c["dialogue"], "won", f + ".dialogue")  # said as you're handed the bracelet
			if c.has("bond") and not ((c["bond"] is float or c["bond"] is int) and float(c["bond"]) >= 0.0 and float(c["bond"]) <= 1.0):
				_bad(f + ".bond", "should be a number from 0 to 1, is %s" % _show(c["bond"]))

	func _pickup_id(v: Variant, field: String) -> void:
		if not _string(v, field):
			return
		if pickup_ids.has(v):
			_bad(field, "%s is used twice (also %s): a pickup id is a save's record of taking it" % [_show(v), pickup_ids[v]])
		else:
			pickup_ids[v] = "%s %s" % [_file, field]
