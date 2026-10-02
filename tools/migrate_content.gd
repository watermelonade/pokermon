extends SceneTree
## One-off (editor phase 1): writes content/ from the world as the code had
## it, WorldMap.MAPS and the overworld's narration, with ContentFormat.
## The narration is taken from the C-SAME snapshot
## (tests/fixtures/world_before_content.json, made from the code), so no
## line is retyped by hand. Deleted in the commit after the one that ran
## it, once the consts it reads are gone.
##
##   godot --headless --path . -s tools/migrate_content.gd

const FIXTURE := "res://tests/fixtures/world_before_content.json"
const FACING_NAMES := {Vector2i.UP: "up", Vector2i.DOWN: "down", Vector2i.LEFT: "left", Vector2i.RIGHT: "right"}
## Sign speakers' ids, by map and cell (signs had no ids before).
const SIGN_IDS := {
	"sootbridge": {Vector2i(8, 7): "sootbridge_sign"},
	"mill_road": {Vector2i(31, 3): "mill_road_sign"},
	"town": {Vector2i(9, 7): "diner_sign", Vector2i(31, 10): "east_sign", Vector2i(26, 13): "mossbank_sign",
		Vector2i(27, 6): "shop_sign", Vector2i(88, 16): "hall_sign", Vector2i(12, 19): "open_table_sign"},
	"diner": {Vector2i(13, 4): "painting"},
	"home": {Vector2i(4, 4): "practice_table", Vector2i(5, 4): "practice_table"},
	"hall": {Vector2i(5, 0): "hall_rules"},
}
const NOTES := {
	"sootbridge": "Demo 2's first town (docs/DEMO_SPEC.md): soot-stained terraces on a canal, the street where the dog wakes by the open manhole, and the gate east to the Mill Road. The four Aces are found four ways: the Ace of Spades in the gutter in plain sight, the Ace of Diamonds up the washhouse's floor drain, the Ace of Clubs at the dead end of the coal yard's alley (behind the crates), and the Ace of Hearts given by Mags. Outside the Lamp, three townsfolk play for pennies on a crate: the street game (demo 2.1), for a dog with empty pockets.",
	"washhouse": "Sootbridge's washhouse: Nell's, mopped. An Ace came up its floor drain, by the tubs.",
	"mill_road": "The road between the towns: short, a couple of folk on it, no crews (the dog has none to play them with yet).",
	"mossbank": "Demo 1's town, the west end of the town map: the diner, home, the shop, and the open table by the pond (docs/DEMO_SPEC.md W-TABLE), where Sage and Bandit play until your first sit, then join you.",
	"ridge_road": "East out of Mossbank on the same map (one long outdoor map, so walking out of town is seamless). Four crews stand watching, placed so that the first and third can't be walked around and the other two can, with care.",
	"hall_plaza": "The plaza in front of the Tournament Hall, at Ridge Road's east end.",
	"diner": "Rosie's Diner, the healing centre: a blackout wakes you in a booth.",
	"home": "Your house and your practice table.",
	"hall": "The Mossbank Open: the Regulars, a boss crew (BossTable), four against your three, Graves leading on a big stack with the seat draw rigged around you. Lou, the dealer, is asleep.",
}

var _talk := {}  ## file id -> [speaker dicts] in order
var _code := {}  ## the snapshot's code_text


func _init() -> void:
	_code = (JSON.parse_string(FileAccess.get_file_as_string(FIXTURE)) as Dictionary)["code_text"]
	DirAccess.make_dir_recursive_absolute("res://content/maps")
	DirAccess.make_dir_recursive_absolute("res://content/dialogue")
	DirAccess.make_dir_recursive_absolute("res://content/script")
	for map_id: String in WorldMap.MAPS:
		_talk[map_id] = []
		_write("res://content/maps/%s.json" % map_id, _map(map_id, WorldMap.MAPS[map_id]))
	_code_lines()
	for map_id: String in WorldMap.MAPS:
		_write("res://content/dialogue/%s.json" % map_id, {"id": map_id, "speakers": _talk[map_id]})
	for script_id: String in ["intro", "overworld"]:
		_write("res://content/script/%s.json" % script_id, {"id": script_id, "speakers": _talk[script_id]})
	_write("res://content/atlas.json", _atlas())
	quit()


func _write(path: String, data: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(ContentFormat.stringify(data))
	f.close()
	print("wrote ", path)


func _cell(v: Vector2i) -> Array:
	return [v.x, v.y]


func _dealer(kind: int) -> String:
	return Dealer.Kind.find_key(kind)


func _animal(a: Array) -> Array:
	return [str(a[0]), a[1]]


## A speaker's sets of lines as text, numbered <file>.<speaker>.<n> down
## the file (sets in ContentFormat's key order); added to the file's
## speakers unless it's there already (two signs, one speaker).
func _speaker(file_id: String, speaker_id: String, sets: Dictionary) -> String:
	for s: Dictionary in _talk[file_id]:
		if s["id"] == speaker_id:
			return speaker_id
	var speaker := {"id": speaker_id}
	var n := 0
	for which in ContentFormat.ordered_keys(sets):
		var lines: Array = []
		for text: String in sets[which]:
			n += 1
			lines.append({"id": "%s.%s.%d" % [file_id, speaker_id, n], "text": text, "status": "placeholder"})
		speaker[which] = lines
	_talk[file_id].append(speaker)
	return speaker_id


## The text of the snapshot's code literals: file, function, which ones.
func _said(file: String, fn: String, which: Array) -> Array:
	var all: Array = _code["res://src/world/%s" % file][fn]
	return which.map(func(i: int) -> String: return all[i])


func _map(map_id: String, data: Dictionary) -> Dictionary:
	var out := {"id": map_id, "outdoor": data["outdoor"], "rows": data["rows"]}
	out["labels"] = (data["labels"] as Array).map(func(l: Dictionary) -> Dictionary:
		var r: Rect2i = l["rect"]
		return {"rect": [r.position.x, r.position.y, r.size.x, r.size.y], "text": l["text"]})
	out["warps"] = (data["warps"] as Array).map(func(w: Dictionary) -> Dictionary:
		return {"cell": _cell(w["cell"]), "to": w["to"], "to_cell": _cell(w["to_cell"]), "facing": FACING_NAMES[w["facing"]]})
	out["gates"] = (data.get("gates", []) as Array).map(func(g: Dictionary) -> Dictionary:
		return {"cells": (g["cells"] as Array).map(_cell), "requires": g["requires"],
			"dialogue": _speaker(map_id, "gate", {"lines": [g["text"]]})})
	out["pickups"] = (data.get("pickups", []) as Array).map(func(p: Dictionary) -> Dictionary:
		return {"id": p["id"], "cell": _cell(p["cell"]), "card": Card.label(p["card"])})
	out["signs"] = (data["signs"] as Array).map(func(s: Dictionary) -> Dictionary:
		return {"cell": _cell(s["cell"]), "dialogue": _speaker(map_id, SIGN_IDS[map_id][s["cell"]], {"lines": [s["text"]]})})
	var tables := {}
	for n: Dictionary in data["npcs"]:
		if n.has("open_table") and not tables.has(n["open_table"]["id"]):
			var t: Dictionary = n["open_table"]
			var doc := {"id": t["id"], "dealer": _dealer(t["dealer"]), "players": (t["players"] as Array).map(_animal)}
			for k: String in ["buy_in", "stake", "blinds", "max_money"]:
				if t.has(k):
					doc[k] = t[k]
			tables[t["id"]] = doc
	out["open_tables"] = tables.values()
	out["npcs"] = (data["npcs"] as Array).map(func(n: Dictionary) -> Dictionary:
		var doc := {"id": n["id"], "name": n["name"], "sprite": n["sprite"], "cell": _cell(n["cell"]), "facing": FACING_NAMES[n["facing"]]}
		if n.has("asleep"):
			doc["asleep"] = n["asleep"]
		if n.has("open_table"):
			doc["open_table"] = n["open_table"]["id"]
		if n.has("animal"):
			doc["animal"] = _animal(n["animal"])
		if n.has("gives_card"):
			doc["gives_card"] = {"id": n["gives_card"]["id"], "card": Card.label(n["gives_card"]["card"])}
		var sets := {"lines": n["lines"]}
		if n.has("after"):
			sets["after"] = n["after"]
		doc["dialogue"] = _speaker(map_id, n["id"], sets)
		return doc)
	out["crews"] = (data["crews"] as Array).map(func(c: Dictionary) -> Dictionary:
		var doc := {"id": c["id"], "name": c["name"], "cell": _cell(c["cell"]), "facing": FACING_NAMES[c["facing"]],
			"sight": c["sight"], "members": (c["members"] as Array).map(_animal), "reward": c["reward"],
			"chips": c["chips"], "dealer": _dealer(c["dealer"])}
		for k: String in ["boss", "tournament", "bracelet", "bond"]:
			if c.has(k):
				doc[k] = c[k]
		doc["dialogue"] = _speaker(map_id, c["id"], {"before": c["before"], "after": [c["after"]]})
		return doc)
	return out


## The lines the overworld's code said itself: the intro (its five beats,
## each a speaker so they stay in order), the narration, Rosie's, the
## Open's win, Sage's and Bandit's asks. Placeholders become {names}.
func _code_lines() -> void:
	_talk["intro"] = []
	_talk["overworld"] = []
	var intro := _said("overworld.gd", "_intro", range(10))
	_speaker("intro", "night", {"lines": intro.slice(0, 2)})
	_speaker("intro", "manhole", {"lines": intro.slice(2, 3)})
	_speaker("intro", "fall", {"lines": intro.slice(3, 5)})
	_speaker("intro", "morning", {"lines": intro.slice(5, 7)})
	_speaker("intro", "dawn", {"lines": intro.slice(7, 10)})
	_speaker("overworld", "aces_complete", {"lines": _said("overworld.gd", "_found_lines", [1])})
	_speaker("overworld", "no_crew", {"lines": _said("overworld.gd", "_encounter", [0, 1]).map(
		func(t: String) -> String: return t.replace("%s", "{crew}"))})
	_speaker("overworld", "blackout", {"lines": _said("overworld.gd", "_blackout", [1])})
	# Rosie's speaker exists (her npc); her other sets join it.
	var rosie: Dictionary = (_talk["diner"] as Array).filter(func(s: Dictionary) -> bool: return s["id"] == "rosie")[0]
	var sets := {"lines": Content.texts(rosie["lines"]),
		"champ": _said("overworld.gd", "_interact", [0]),
		"rest": _said("overworld.gd", "_rest_at_diner", [3]),
		"offer": _said("overworld.gd", "_offer_tutorial", [0, 1]),
		"declined": _said("overworld.gd", "_offer_tutorial", [5]),
		"lesson_done": _said("overworld.gd", "_play_tutorial", [0, 1]),
		"lesson_skipped": _said("overworld.gd", "_play_tutorial", [2]),
		"blackout": _said("overworld.gd", "_blackout", [2, 3]).map(func(t: String) -> String: return t.replace("%d", "{lost}"))}
	_talk["diner"].erase(rosie)
	_speaker("diner", "rosie", sets)
	var regulars: Dictionary = (_talk["hall"] as Array).filter(func(s: Dictionary) -> bool: return s["id"] == "mossbank_regulars")[0]
	_talk["hall"].erase(regulars)
	_speaker("hall", "mossbank_regulars", {"before": Content.texts(regulars["before"]), "after": Content.texts(regulars["after"]),
		"won": _said("overworld.gd", "_after_win", [1])})
	for who: Array in [["table_sage", 0], ["table_bandit", 1]]:
		var s: Dictionary = (_talk["town"] as Array).filter(func(x: Dictionary) -> bool: return x["id"] == who[0])[0]
		var i: int = (_talk["town"] as Array).find(s)
		_talk["town"].erase(s)
		_speaker("town", who[0], {"lines": Content.texts(s["lines"]), "joins": _said("open_table.gd", "_ask_line", [who[1]])})
		# back in its place, so the file keeps the map's order
		var moved: Dictionary = _talk["town"].pop_back()
		_talk["town"].insert(i, moved)


func _atlas() -> Dictionary:
	var town_height := (WorldMap.MAPS["town"]["rows"] as Array).size()
	var areas: Array = [
		_area("sootbridge", "sootbridge", "Sootbridge", "Sootbridge", "town"),
		_area("washhouse", "washhouse", "Sootbridge Washhouse", "Sootbridge", "interior"),
		_area("mill_road", "mill_road", "The Mill Road", "The Mill Road", "route"),
		_area("mossbank", "town", "Mossbank", "Mossbank", "town"),
		_area("ridge_road", "town", "Ridge Road", "Mossbank", "route", [34, 0, 52, town_height]),
		_area("hall_plaza", "town", "Mossbank Hall Plaza", "Mossbank", "town", [86, 0, 14, town_height]),
		_area("diner", "diner", "Rosie's Diner", "Mossbank", "interior"),
		_area("home", "home", "Home", "Mossbank", "interior"),
		_area("hall", "hall", "Mossbank Tournament Hall", "Mossbank", "interior"),
	]
	return {"areas": areas}


func _area(id: String, map_id: String, name: String, region: String, kind: String, at := []) -> Dictionary:
	var out := {"id": id, "map": map_id, "name": name, "region": region, "kind": kind, "status": "blockout", "notes": NOTES[id]}
	if at:
		out["rect"] = at
	return out
