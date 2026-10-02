extends RefCounted
## The world as the game sees it, as plain JSON: C-SAME's snapshot
## (docs/EDITOR_SPEC.md, phase 1). tools/snapshot_world.tscn wrote
## tests/fixtures/world_before_content.json with this from the code as it
## was before any content moved out of it (the maps were consts in
## src/world/world_map.gd, the area names a const and an if in
## overworld.gd, the narration string literals in overworld.gd and
## open_table.gd); tests/test_content.gd builds the same snapshot from the
## content loader and compares.
##
## It goes through the public API the game itself uses (WorldMap.ids(),
## WorldMap.get_map() and its fields), not through the data's own shape, so
## the comparison holds whatever the data is stored as. Values are encoded
## so that a type change shows up too: Vector2i and Rect2i as their
## var_to_str text, a StringName as "&name", a float as "float:<value>"
## (a JSON loader that hands back 120.0 where the game had 120 fails), and
## dictionaries with their keys sorted (key order is meaningless to the game).
##
## Preloaded, not a class_name: it's test code, and the game shouldn't see it.

const CODE_FILES: Array[String] = ["res://src/world/overworld.gd", "res://src/world/open_table.gd"]


## Every map (in WorldMap.ids() order) with everything on it, and the area
## name shown on every cell. `area_name` is (map_id: String, cell: Vector2i)
## -> String: what the overworld's banner says standing there.
static func build(area_name: Callable) -> Dictionary:
	var ids: Array = []
	var maps := {}
	for id: String in WorldMap.ids():
		ids.append(id)
		var m := WorldMap.get_map(id)
		maps[id] = {
			"outdoor": m.outdoor, "rows": Array(m.rows), "width": m.width, "height": m.height,
			"labels": m.labels, "warps": m.warps, "signs": m.signs, "npcs": m.npcs, "crews": m.crews,
			"gates": m.gates, "pickups": m.pickups(), "areas": _areas(m, area_name),
		}
	return encode({"map_ids": ids, "maps": maps,
		"open_table": WorldMap.OPEN_TABLE, "street_game": WorldMap.STREET_GAME})


## The area name over every row of the map, run-length coded:
## [[name, cells], ...] per row.
static func _areas(m: WorldMap, area_name: Callable) -> Array:
	var out: Array = []
	for y in m.height:
		var row: Array = []
		for x in m.width:
			var name: String = area_name.call(m.id, Vector2i(x, y))
			if row and row[row.size() - 1][0] == name:
				row[row.size() - 1][1] += 1
			else:
				row.append([name, 1])
		out.append(row)
	return out


## A value as JSON-safe data that keeps its Godot type (see the top).
static func encode(v: Variant) -> Variant:
	match typeof(v):
		TYPE_DICTIONARY:
			var keys: Array = (v as Dictionary).keys()
			keys.sort_custom(func(a: Variant, b: Variant) -> bool: return str(a) < str(b))
			var out := {}
			for k: Variant in keys:
				out[str(k)] = encode(v[k])
			return out
		TYPE_ARRAY:
			var out: Array = []
			for e: Variant in v:
				out.append(encode(e))
			return out
		TYPE_PACKED_STRING_ARRAY:
			return encode(Array(v))
		TYPE_STRING_NAME:
			return "&" + str(v)
		TYPE_FLOAT:
			return "float:%s" % str(v)
		TYPE_STRING, TYPE_INT, TYPE_BOOL, TYPE_NIL:
			return v
	return var_to_str(v)


## The text in the overworld's code: every string literal with a space and
## a letter in it, per function, from each of CODE_FILES ({path: {func:
## [text]}}). Skipped: comments, dev_log and print lines, res:// paths.
## It picks up code text too (format strings, menu options, " and "); the
## test only asks that each one is still in the code or now in content.
static func code_text() -> Dictionary:
	var out := {}
	for path in CODE_FILES:
		var funcs := {}
		var current := "(top)"
		for raw in FileAccess.get_file_as_string(path).split("\n"):
			var line := raw.strip_edges()
			if raw.begins_with("func ") or raw.begins_with("static func "):
				current = raw.get_slice("func ", 1).get_slice("(", 0)
			if line.begins_with("#") or "dev_log" in line or "print(" in line or "res://" in line:
				continue
			for text in literals(line):
				if " " in text and RegEx.create_from_string("[A-Za-z]").search(text):
					if not funcs.has(current):
						funcs[current] = []
					funcs[current].append(text)
		out[path] = funcs
	return out


## The string literals on one line of GDScript, unescaped (\" and \\).
static func literals(line: String) -> Array[String]:
	var out: Array[String] = []
	var re := RegEx.create_from_string("\"((?:[^\"\\\\]|\\\\.)*)\"")
	for m in re.search_all(line):
		out.append(m.get_string(1).replace("\\\"", "\"").replace("\\\\", "\\"))
	return out


## Where two snapshots differ, as readable paths (maps.town.npcs[3].lines[1]:
## expected "...", got "..."), at most `limit` of them.
static func diff(want: Variant, got: Variant, path := "", limit := 20) -> Array[String]:
	var out: Array[String] = []
	_diff(want, got, path, out, limit)
	return out


static func _diff(want: Variant, got: Variant, path: String, out: Array[String], limit: int) -> void:
	if out.size() >= limit:
		return
	if typeof(want) != typeof(got):
		out.append("%s: expected %s, got %s" % [path, JSON.stringify(want), JSON.stringify(got)])
		return
	if want is Dictionary:
		for k: Variant in want:
			if not (got as Dictionary).has(k):
				out.append("%s.%s: missing" % [path, k])
			else:
				_diff(want[k], got[k], "%s.%s" % [path, k], out, limit)
		for k: Variant in got:
			if not (want as Dictionary).has(k):
				out.append("%s.%s: not in the snapshot (%s)" % [path, k, JSON.stringify(got[k])])
		return
	if want is Array:
		if (want as Array).size() != (got as Array).size():
			out.append("%s: %d entries, expected %d" % [path, (got as Array).size(), (want as Array).size()])
		for i in mini((want as Array).size(), (got as Array).size()):
			_diff(want[i], got[i], "%s[%d]" % [path, i], out, limit)
		return
	if want != got:
		out.append("%s: expected %s, got %s" % [path, JSON.stringify(want), JSON.stringify(got)])
