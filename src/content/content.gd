class_name Content
extends RefCounted
## The overworld's content, loaded from content/ (docs/EDITOR_SPEC.md,
## phase 1; README "Content" says where everything lives). Until phase 1 the
## maps were a const dictionary in src/world/world_map.gd and the narration
## string literals in overworld.gd and open_table.gd; now they're data the
## game loads and the editor (phase 2) will save, and this is the one place
## that reads them:
##
## - content/atlas.json: every area (a named place: its map, region, kind,
##   status, notes, and for an area that's part of a map, its rect).
## - content/maps/<id>.json: a map's tiles and what's placed on it.
## - content/dialogue/<id>.json: the words for that map's speakers and signs.
## - content/script/<id>.json: narration that belongs to no map (the intro).
##
## The rest of the game doesn't see the files' shape: runtime_map() turns a
## map file (and its dialogue) into the same dictionary the const used to
## be (Vector2i cells and facings, Rect2i labels, Dealer.Kind ints,
## StringName species, card ints, every line's text in place of its id), so
## WorldMap and everything reading it work as before; C-SAME checks that
## against a snapshot of the world taken from the code before the move.
##
## Files are read with FileAccess from res://content, which works in an
## exported build too: export_presets.cfg packs content/ (C-EXPORT), and
## the game never lists a directory at runtime (the atlas names the maps),
## so it doesn't depend on a PCK's directory listing either.
##
## Everything is cached after the first read; reload() drops the cache
## (the editor, after a save; WorldMap.reload() calls it).

const ROOT := "res://content"
const FACINGS := {"up": Vector2i.UP, "down": Vector2i.DOWN, "left": Vector2i.LEFT, "right": Vector2i.RIGHT}
const STATUSES: Array[String] = ["placeholder", "draft", "final"]
## The lines the code asks for by name rather than through a placed thing:
## [file, speaker, set]. ContentSchema fails content missing any of them.
const CODE_LINES: Array = [
	["intro", "night", "lines"], ["intro", "manhole", "lines"], ["intro", "fall", "lines"],
	["intro", "morning", "lines"], ["intro", "dawn", "lines"],
	["overworld", "aces_complete", "lines"], ["overworld", "no_crew", "lines"], ["overworld", "blackout", "lines"],
	["diner", "rosie", "champ"], ["diner", "rosie", "rest"], ["diner", "rosie", "offer"], ["diner", "rosie", "declined"],
	["diner", "rosie", "lesson_done"], ["diner", "rosie", "lesson_skipped"], ["diner", "rosie", "blackout"],
	["town", "table_sage", "joins"], ["town", "table_bandit", "joins"],
]
## The script files (content/script/<id>.json): listed, not found by
## listing the directory (see the top).
const SCRIPTS: Array[String] = ["intro", "overworld"]

static var _docs := {}  ## path -> parsed file
static var _maps := {}  ## map id -> runtime dictionary
static var _speakers := {}  ## file id -> {speaker id -> speaker}


## Forgets everything read, so the next call reads the files again.
static func reload() -> void:
	_docs.clear()
	_maps.clear()
	_speakers.clear()


# --- Files ------------------------------------------------------------------

static func atlas_path() -> String:
	return ROOT + "/atlas.json"


static func map_path(map_id: String) -> String:
	return "%s/maps/%s.json" % [ROOT, map_id]


static func dialogue_path(map_id: String) -> String:
	return "%s/dialogue/%s.json" % [ROOT, map_id]


static func script_path(script_id: String) -> String:
	return "%s/script/%s.json" % [ROOT, script_id]


## A content file's data ({} with an error logged if it's missing or isn't
## JSON). Cached: callers must not change what they get (duplicate it).
static func doc(path: String) -> Dictionary:
	if not _docs.has(path):
		var data: Variant = null
		if FileAccess.file_exists(path):
			var text := FileAccess.get_file_as_string(path)
			data = ContentFormat.parse(text)
			if not data is Dictionary:
				push_error("content: %s doesn't parse (%s)" % [path, ContentFormat.parse_error(text)])
		else:
			push_error("content: %s is missing" % path)
		_docs[path] = data if data is Dictionary else {}
	return _docs[path]


static func atlas() -> Dictionary:
	return doc(atlas_path())


static func map_doc(map_id: String) -> Dictionary:
	return doc(map_path(map_id))


## The maps, in the atlas's order (an area's map, first time it's named).
static func map_ids() -> Array[String]:
	var out: Array[String] = []
	for area: Dictionary in atlas().get("areas", []):
		var map_id := str(area.get("map", ""))
		if map_id and not out.has(map_id):
			out.append(map_id)
	return out


## Every content file the game reads: the atlas, each map's map and
## dialogue file, the scripts.
static func game_files() -> Array[String]:
	var out: Array[String] = [atlas_path()]
	for map_id in map_ids():
		out.append(map_path(map_id))
		out.append(dialogue_path(map_id))
	for script_id in SCRIPTS:
		out.append(script_path(script_id))
	return out


## Every .json file under content/, found on disk (for the tests and the
## editor, in source runs; the game itself uses game_files()).
static func files(dir := ROOT) -> Array[String]:
	var out: Array[String] = []
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".json"):
			out.append("%s/%s" % [dir, f])
	for d in DirAccess.get_directories_at(dir):
		out.append_array(files("%s/%s" % [dir, d]))
	return out


## Every content file on disk, parsed: {path: data}, copies the caller may
## change (ContentSchema checks these; the editor will edit them).
static func docs() -> Dictionary:
	var out := {}
	for path in files():
		out[path] = doc(path).duplicate(true)
	return out


# --- The maps, as the game uses them ---------------------------------------

## Every map's runtime dictionary (see runtime_map), in map_ids() order.
static func runtime_maps() -> Dictionary:
	var out := {}
	for map_id in map_ids():
		out[map_id] = runtime_map(map_id)
	return out


## A map as the game uses it: the shape src/world/world_map.gd's MAPS const
## had (see the top), built from the map's file and its dialogue file.
static func runtime_map(map_id: String) -> Dictionary:
	if not _maps.has(map_id):
		_maps[map_id] = build_runtime_map(map_doc(map_id), speakers(map_id))
	return _maps[map_id]


## The runtime dictionary for a map file's data `m`, with its words from
## `talk` ({speaker id: speaker}). Static and cache-free, so the editor can
## build a map it hasn't saved yet.
static func build_runtime_map(m: Dictionary, talk: Dictionary) -> Dictionary:
	var rows: Array = []
	for r: Variant in m.get("rows", []):
		rows.append(str(r))
	var labels: Array = []
	for l: Dictionary in m.get("labels", []):
		labels.append({"rect": rect(l["rect"]), "text": str(l["text"])})
	var warps: Array = []
	for w: Dictionary in m.get("warps", []):
		warps.append({"cell": cell(w["cell"]), "to": str(w["to"]), "to_cell": cell(w["to_cell"]), "facing": facing(w["facing"])})
	var gates: Array = []
	for g: Dictionary in m.get("gates", []):
		var cells: Array = []
		for c: Variant in g["cells"]:
			cells.append(cell(c))
		gates.append({"cells": cells, "requires": str(g["requires"]), "text": _one_line(talk, g["dialogue"])})
	var pickups: Array = []
	for p: Dictionary in m.get("pickups", []):
		pickups.append({"id": str(p["id"]), "cell": cell(p["cell"]), "card": card(p["card"])})
	var signs: Array = []
	for s: Dictionary in m.get("signs", []):
		signs.append({"cell": cell(s["cell"]), "text": _one_line(talk, s["dialogue"])})
	var tables := {}
	for t: Dictionary in m.get("open_tables", []):
		tables[str(t["id"])] = _open_table(t)
	var npcs: Array = []
	for n: Dictionary in m.get("npcs", []):
		npcs.append(_npc(n, talk, tables))
	var crews: Array = []
	for c: Dictionary in m.get("crews", []):
		crews.append(_crew(c, talk))
	return {"outdoor": bool(m.get("outdoor", true)), "rows": rows, "labels": labels, "warps": warps, "gates": gates,
		"pickups": pickups, "signs": signs, "npcs": npcs, "crews": crews}


static func _npc(n: Dictionary, talk: Dictionary, tables: Dictionary) -> Dictionary:
	var out := {"id": str(n["id"]), "name": str(n["name"]), "sprite": str(n["sprite"]),
		"cell": cell(n["cell"]), "facing": facing(n["facing"])}
	var speaker: Dictionary = talk.get(str(n["dialogue"]), {})
	out["lines"] = texts(speaker.get("lines", []))
	if speaker.has("after"):
		out["after"] = texts(speaker["after"])
	if n.has("asleep"):
		out["asleep"] = bool(n["asleep"])
	if n.has("open_table"):
		out["open_table"] = tables.get(str(n["open_table"]), {})
	if n.has("animal"):
		out["animal"] = animal(n["animal"])
	if n.has("gives_card"):
		out["gives_card"] = {"id": str(n["gives_card"]["id"]), "card": card(n["gives_card"]["card"])}
	return out


static func _crew(c: Dictionary, talk: Dictionary) -> Dictionary:
	var members: Array = []
	for m: Variant in c["members"]:
		members.append(animal(m))
	var speaker: Dictionary = talk.get(str(c["dialogue"]), {})
	var out := {"id": str(c["id"]), "name": str(c["name"]), "cell": cell(c["cell"]), "facing": facing(c["facing"]),
		"sight": int(c["sight"]), "members": members, "before": texts(speaker.get("before", [])),
		"after": _one_line(talk, c["dialogue"], "after"), "reward": int(c["reward"]), "chips": int(c["chips"]),
		"dealer": dealer(c["dealer"])}
	if c.has("boss"):
		out["boss"] = bool(c["boss"])
	if c.has("tournament"):
		out["tournament"] = bool(c["tournament"])
	if c.has("bracelet"):
		out["bracelet"] = str(c["bracelet"])
	if c.has("bond"):
		out["bond"] = float(c["bond"])
	return out


## An open table's setup as OpenTable and CashMatch read it: Mossbank's
## has a buy-in, Sootbridge's street game a stake, blinds and max_money.
static func _open_table(t: Dictionary) -> Dictionary:
	var out := {"id": str(t["id"]), "dealer": dealer(t["dealer"])}
	for k: String in ["buy_in", "stake", "max_money"]:
		if t.has(k):
			out[k] = int(t[k])
	if t.has("blinds"):
		out["blinds"] = (t["blinds"] as Array).map(func(b: Variant) -> int: return int(b))
	var players: Array = []
	for p: Variant in t["players"]:
		players.append(animal(p))
	out["players"] = players
	return out


## The open table with this id, on whichever map it stands ({} if none).
static func open_table(table_id: String) -> Dictionary:
	for map_id in map_ids():
		for n: Dictionary in runtime_map(map_id)["npcs"]:
			if n.has("open_table") and n["open_table"].get("id") == table_id:
				return n["open_table"]
	return {}


# --- Values: the files' names to the game's types ----------------------------

static func cell(v: Variant) -> Vector2i:
	return Vector2i(int(v[0]), int(v[1]))


static func rect(v: Variant) -> Rect2i:
	return Rect2i(int(v[0]), int(v[1]), int(v[2]), int(v[3]))


static func facing(v: Variant) -> Vector2i:
	return FACINGS.get(str(v), Vector2i.DOWN)


static func facing_name(v: Vector2i) -> String:
	return FACINGS.find_key(v)


static func dealer(v: Variant) -> int:
	return Dealer.Kind.get(str(v), Dealer.Kind.WATCHFUL)


static func card(v: Variant) -> int:
	return Card.parse(str(v))


## [species, individual] with the species as the StringName the game uses.
static func animal(v: Variant) -> Array:
	return [StringName(str(v[0])), int(v[1])]


# --- Words ------------------------------------------------------------------

## {speaker id: speaker} for a dialogue file (a map's id) or a script file.
static func speakers(file_id: String) -> Dictionary:
	if not _speakers.has(file_id):
		var path := script_path(file_id) if SCRIPTS.has(file_id) else dialogue_path(file_id)
		var out := {}
		for s: Dictionary in doc(path).get("speakers", []):
			out[str(s["id"])] = s
		_speakers[file_id] = out
	return _speakers[file_id]


## The texts of a list of lines ({"id", "text", "status"} each).
static func texts(lines: Array) -> Array:
	var out: Array = []
	for l: Dictionary in lines:
		out.append(str(l["text"]))
	return out


## The one line a sign, a gate or a crew's "after" says.
static func _one_line(talk: Dictionary, speaker_id: Variant, which := "lines") -> String:
	var lines: Array = talk.get(str(speaker_id), {}).get(which, [])
	return str(lines[0]["text"]) if lines else ""


## What a speaker says: the texts of one of its sets of lines ("lines",
## "after", or one the code names, like Rosie's "offer"), with `args`
## filled into its {placeholders} ({"lost": 50}). From a map's dialogue
## file, or a script file (SCRIPTS).
static func say(file_id: String, speaker_id: String, which := "lines", args := {}) -> Array[String]:
	var out: Array[String] = []
	for t: String in texts(speakers(file_id).get(speaker_id, {}).get(which, [])):
		out.append(t.format(args) if args else t)
	if out.is_empty():
		push_error("content: no lines for %s.%s (%s)" % [file_id, speaker_id, which])
	return out


## Whether a speaker has that set of lines.
static func has_lines(file_id: String, speaker_id: String, which := "lines") -> bool:
	return not (speakers(file_id).get(speaker_id, {}).get(which, []) as Array).is_empty()


## The speaker a placed npc or crew on a map talks with (its "dialogue").
static func speaker_of(map_id: String, thing_id: String) -> String:
	var m := map_doc(map_id)
	for n: Dictionary in m.get("npcs", []) + m.get("crews", []):
		if n.get("id") == thing_id:
			return str(n.get("dialogue", ""))
	return ""


## Every line in the game's dialogue and script files, in file order:
## {"id", "text", "status", "file", "speaker", "set"}.
static func all_lines() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for file_id: String in map_ids() + SCRIPTS:
		for speaker: Dictionary in speakers(file_id).values():
			for which: String in ContentFormat.ordered_keys(speaker):
				if speaker[which] is Array:
					for l: Dictionary in speaker[which]:
						out.append({"id": l["id"], "text": l["text"], "status": l["status"],
							"file": file_id, "speaker": speaker["id"], "set": which})
	return out


# --- Areas ------------------------------------------------------------------

## The name the overworld shows on arriving at `cell` on a map: the area
## whose rect holds the cell, else the map's area without a rect, else the
## map's id. (Mossbank's map holds three areas: the town, Ridge Road and
## the hall's plaza.)
static func area_name(map_id: String, at: Vector2i) -> String:
	var whole := ""
	for area: Dictionary in atlas().get("areas", []):
		if area.get("map") != map_id:
			continue
		if not area.has("rect"):
			if whole == "":
				whole = str(area["name"])
		elif rect(area["rect"]).has_point(at):
			return str(area["name"])
	return whole if whole else map_id


## How the areas connect: [from map, to map] for every map with a door to
## another, derived from the warps so it can't drift (docs/EDITOR_SPEC.md).
static func connections() -> Array:
	var out: Array = []
	for map_id in map_ids():
		for w: Dictionary in map_doc(map_id).get("warps", []):
			var pair := [map_id, str(w["to"])]
			if not out.has(pair):
				out.append(pair)
	return out
