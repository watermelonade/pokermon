extends TestCase
## Phase 1 of the editor (docs/EDITOR_SPEC.md): the overworld's content
## lives in content/ as data files, and the game plays exactly as it did
## when it was code. One test (or two) per outcome, C-SAME to C-EXPORT; R-ALL
## is every other tier staying green.
##
## Written before the move (test first): the snapshot C-SAME compares with
## (tests/fixtures/world_before_content.json) was made by
## tools/snapshot_world.tscn from the code before anything moved, in the
## same commit as these tests. They reach the content code by path rather
## than by class_name (_script) so that this file compiled, and its tests
## were red rather than broken, before src/content/ existed.

const WorldSnapshot := preload("res://tests/world_snapshot.gd")
const FIXTURE := "res://tests/fixtures/world_before_content.json"
const ROOT := "res://content"
## The files C-NOCODE scans for text that moved (docs/EDITOR_SPEC.md).
const CODE_FILES: Array[String] = ["res://src/world/world_map.gd", "res://src/world/overworld.gd", "res://src/world/open_table.gd"]


## The content script at res://src/content/<name>.gd, or null (a failed
## check) if it isn't there yet.
func _script(name: String, outcome: String) -> Variant:
	var path := "res://src/content/%s.gd" % name
	if not check(ResourceLoader.exists(path), "%s: no %s yet" % [outcome, path]):
		return null
	return load(path)


func _fixture() -> Dictionary:
	var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	return v if v is Dictionary else {}


## `{name}` placeholders (content) and `%s`/`%d` (code) read the same.
func _norm(text: String) -> String:
	var re := RegEx.create_from_string("\\{[a-z_]+\\}|%[sd]")
	return re.sub(text, "%_", true)


# --- C-SAME -----------------------------------------------------------------

## C-SAME: the world the game gets from content/ is the one the code had:
## every map with everything on it (through WorldMap, as the game asks),
## the open table and street game, the area name on every cell, and every
## line the overworld's code said is either still in the code (system text)
## or in content/ (the intro in its order).
func test_C_SAME_the_world_is_the_snapshot() -> void:
	var fixture := _fixture()
	if not check(fixture.has("world") and fixture.has("code_text"), "C-SAME: the snapshot %s is missing or unreadable" % FIXTURE):
		return
	var content: Variant = _script("content", "C-SAME")
	if content == null or not check(FileAccess.file_exists(ROOT + "/atlas.json"), "C-SAME: no content/atlas.json yet"):
		return
	var area_name := func(map_id: String, cell: Vector2i) -> String: return content.area_name(map_id, cell)
	var got := WorldSnapshot.build(area_name)
	var want: Dictionary = fixture["world"]
	got = JSON.parse_string(JSON.stringify(got))  # the fixture went through JSON too
	var diffs := WorldSnapshot.diff(want, got, "world")
	check(diffs.is_empty(), "C-SAME: the world differs from the snapshot:\n  %s" % "\n  ".join(diffs))
	# WorldMap's maps are the loader's (not a copy left in code).
	check_eq(WorldSnapshot.encode(WorldMap.MAPS), WorldSnapshot.encode(content.runtime_maps()), "C-SAME: WorldMap.MAPS is the content loader's maps:")
	# The overworld's text: still in the code, or moved to content.
	var now := WorldSnapshot.code_text()
	var moved := {}
	for line: Dictionary in content.all_lines():
		moved[_norm(line["text"])] = true
	for area: Dictionary in content.atlas()["areas"]:
		moved[str(area["name"])] = true
	for path: String in fixture["code_text"]:
		var in_code := {}
		for fn: String in now.get(path, {}):
			for text: String in now[path][fn]:
				in_code[text] = true
		for fn: String in fixture["code_text"][path]:
			for text: String in fixture["code_text"][path][fn]:
				check(in_code.has(text) or moved.has(_norm(text)),
					"C-SAME: %s %s(): \"%s\" is in neither the code nor content/" % [path.get_file(), fn, text])
	# The intro, line for line in its order.
	var intro: Array = []
	for line: Dictionary in content.all_lines():
		if line["file"] == "intro":
			intro.append(line["text"])
	check_eq(intro, fixture["code_text"]["res://src/world/overworld.gd"]["_intro"], "C-SAME: content/script/intro.json's lines")


# --- C-ROUND ----------------------------------------------------------------

## C-ROUND: every content file, parsed and written by the canonical
## formatter, is byte-identical to itself; and the formatter writes the
## same bytes whatever form the data came in (compact JSON, keys shuffled).
func test_C_ROUND_every_file_saves_to_the_same_bytes() -> void:
	var content: Variant = _script("content", "C-ROUND")
	var format: Variant = _script("content_format", "C-ROUND")
	if content == null or format == null:
		return
	var files: Array = content.files()
	var maps := DirAccess.get_files_at(ROOT + "/maps") if DirAccess.dir_exists_absolute(ROOT + "/maps") else PackedStringArray()
	check(files.has(ROOT + "/atlas.json"), "C-ROUND: content/atlas.json is one of the files")
	check(maps.size() >= 7, "C-ROUND: a file per map (%d in content/maps)" % maps.size())
	check(files.size() >= 1 + 2 * maps.size() + 1, "C-ROUND: the atlas, maps, dialogue and script (%d files)" % files.size())
	for path: String in files:
		var text := FileAccess.get_file_as_string(path)
		var data: Variant = format.parse(text)
		if not check(data is Dictionary, "C-ROUND: %s doesn't parse" % path):
			continue
		var again: String = format.stringify(data)
		if not check(again == text, "C-ROUND: %s changes when saved (%s)" % [path, _first_difference(text, again)]):
			continue
		# The same data in another form formats the same.
		check_eq(format.stringify(JSON.parse_string(JSON.stringify(data))), text, "C-ROUND: %s from compact JSON:" % path)
		check_eq(format.stringify(_reversed(data)), text, "C-ROUND: %s with its keys in another order:" % path)
		check(text.ends_with("}\n") and not text.ends_with("\n\n"), "C-ROUND: %s ends with one newline" % path)
		check(not "\t" in text and not "\r" in text, "C-ROUND: %s: 2-space indent, \\n line ends" % path)


## The data with every dictionary's keys in reverse order.
func _reversed(v: Variant) -> Variant:
	if v is Dictionary:
		var keys: Array = (v as Dictionary).keys()
		keys.reverse()
		var out := {}
		for k: Variant in keys:
			out[k] = _reversed(v[k])
		return out
	if v is Array:
		return (v as Array).map(_reversed)
	return v


func _first_difference(a: String, b: String) -> String:
	var la := a.split("\n")
	var lb := b.split("\n")
	for i in mini(la.size(), lb.size()):
		if la[i] != lb[i]:
			return "line %d: %s  =>  %s" % [i + 1, la[i], lb[i]]
	return "%d lines, saved as %d" % [la.size(), lb.size()]


## The map files' rows are one per line, as they read in a diff.
func test_C_ROUND_maps_keep_their_rows_one_per_line() -> void:
	var content: Variant = _script("content", "C-ROUND")
	if content == null or not check(FileAccess.file_exists(ROOT + "/maps/town.json"), "C-ROUND: no content/maps/town.json yet"):
		return
	var text := FileAccess.get_file_as_string(ROOT + "/maps/town.json")
	for row in WorldMap.get_map("town").rows:
		check(("\n    \"%s\",\n" % row) in text or ("\n    \"%s\"\n" % row) in text, "C-ROUND: town's row %s on a line of its own" % row)


# --- C-SCHEMA ---------------------------------------------------------------

## C-SCHEMA: every content file is valid, and every map has its map,
## dialogue and atlas entry.
func test_C_SCHEMA_the_content_is_valid() -> void:
	var schema: Variant = _script("content_schema", "C-SCHEMA")
	var content: Variant = _script("content", "C-SCHEMA")
	if schema == null or content == null:
		return
	var docs: Dictionary = content.docs()
	check(docs.size() >= 15, "C-SCHEMA: the content files (%d)" % docs.size())
	var problems: Array = schema.check(docs)
	check(problems.is_empty(), "C-SCHEMA: %d problems:\n  %s" % [problems.size(), "\n  ".join(problems)])


## C-SCHEMA: invalid content fails with a message naming the file and the
## field. Each case breaks one thing in a copy of the real content.
func test_C_SCHEMA_problems_name_the_file_and_the_field() -> void:
	var schema: Variant = _script("content_schema", "C-SCHEMA")
	var content: Variant = _script("content", "C-SCHEMA")
	if schema == null or content == null:
		return
	var maps := ROOT + "/maps/"
	var talk := ROOT + "/dialogue/"
	var cases: Array = [
		# [what, file, change(docs), what the message must say (file, field, why)]
		["an unknown tile", maps + "town.json", func(d: Dictionary) -> void:
			d[maps + "town.json"]["rows"][3] = "?" + str(d[maps + "town.json"]["rows"][3]).substr(1),
			["content/maps/town.json", "rows[3]", "tile"]],
		["a row of the wrong width", maps + "home.json", func(d: Dictionary) -> void:
			d[maps + "home.json"]["rows"][2] += "W",
			["content/maps/home.json", "rows[2]", "wide"]],
		["a cell off the map", maps + "sootbridge.json", func(d: Dictionary) -> void:
			d[maps + "sootbridge.json"]["npcs"][0]["cell"] = [99, 99],
			["content/maps/sootbridge.json", "npcs[0].cell", "outside"]],
		["a facing that isn't one", maps + "town.json", func(d: Dictionary) -> void:
			d[maps + "town.json"]["crews"][0]["facing"] = "dwon",
			["content/maps/town.json", "crews[0].facing", "dwon"]],
		["a dealer that isn't one", maps + "town.json", func(d: Dictionary) -> void:
			d[maps + "town.json"]["crews"][1]["dealer"] = "SLEEPY",
			["content/maps/town.json", "crews[1].dealer", "SLEEPY"]],
		["a species that isn't one", maps + "town.json", func(d: Dictionary) -> void:
			d[maps + "town.json"]["crews"][2]["members"][0] = ["dragon", 0],
			["content/maps/town.json", "crews[2].members[0]", "dragon"]],
		["a card that isn't one", maps + "washhouse.json", func(d: Dictionary) -> void:
			d[maps + "washhouse.json"]["pickups"][0]["card"] = "Zz",
			["content/maps/washhouse.json", "pickups[0].card", "Zz"]],
		["a door to no map", maps + "diner.json", func(d: Dictionary) -> void:
			d[maps + "diner.json"]["warps"][0]["to"] = "nowhere",
			["content/maps/diner.json", "warps[0].to", "nowhere"]],
		["a door into a wall", maps + "diner.json", func(d: Dictionary) -> void:
			d[maps + "diner.json"]["warps"][1]["to_cell"] = [0, 0],
			["content/maps/diner.json", "warps[1].to_cell", "walkable"]],
		["a missing key", maps + "washhouse.json", func(d: Dictionary) -> void:
			(d[maps + "washhouse.json"] as Dictionary).erase("outdoor"),
			["content/maps/washhouse.json", "outdoor", "missing"]],
		["a speaker with no lines", talk + "sootbridge.json", func(d: Dictionary) -> void:
			var speakers: Array = d[talk + "sootbridge.json"]["speakers"]
			d[talk + "sootbridge.json"]["speakers"] = speakers.filter(func(s: Dictionary) -> bool: return s["id"] != "mags"),
			["content/maps/sootbridge.json", "npcs[0].dialogue", "mags"]],
		["a line id used twice", talk + "hall.json", func(d: Dictionary) -> void:
			d[talk + "hall.json"]["speakers"][0]["lines"][0]["id"] = "town.bertram.1",
			["content/dialogue/hall.json", "town.bertram.1", "twice"]],
		["a status that isn't one", talk + "diner.json", func(d: Dictionary) -> void:
			d[talk + "diner.json"]["speakers"][0]["lines"][0]["status"] = "done",
			["content/dialogue/diner.json", "status", "done"]],
		["an area with no map", ROOT + "/atlas.json", func(d: Dictionary) -> void:
			d[ROOT + "/atlas.json"]["areas"][0]["map"] = "nowhere",
			["content/atlas.json", "areas[0].map", "nowhere"]],
		["a map with no area", ROOT + "/atlas.json", func(d: Dictionary) -> void:
			var areas: Array = d[ROOT + "/atlas.json"]["areas"]
			d[ROOT + "/atlas.json"]["areas"] = areas.filter(func(a: Dictionary) -> bool: return a["map"] != "home"),
			["content/maps/home.json", "atlas"]],
	]
	var real: Dictionary = content.docs()
	if not check(real.has(maps + "town.json") and real.has(talk + "hall.json"), "C-SCHEMA: the content to break isn't there"):
		return
	check(schema.check(real).is_empty(), "C-SCHEMA: the content before breaking it is valid")
	for c: Array in cases:
		var docs: Dictionary = real.duplicate(true)
		(c[2] as Callable).call(docs)
		var problems: Array = schema.check(docs)
		var named := problems.filter(func(p: String) -> bool:
			for want: String in c[3]:
				if not want in p:
					return false
			return true)
		check(not named.is_empty(), "C-SCHEMA: %s: no problem naming %s; got %s" % [c[0], c[3], problems])


# --- C-NOCODE ---------------------------------------------------------------

## C-NOCODE: none of the overworld's dialogue or sign text is left in
## world_map.gd, overworld.gd or open_table.gd: no string literal there is
## a line in content/, or a line the snapshot had on the maps.
func test_C_NOCODE_no_overworld_text_left_in_the_code() -> void:
	var content: Variant = _script("content", "C-NOCODE")
	if content == null:
		return
	var texts := {}  ## text -> where it's from
	for line: Dictionary in content.all_lines():
		texts[_norm(line["text"])] = line["id"]
	check(texts.size() >= 100, "C-NOCODE: the lines in content/ (%d)" % texts.size())
	for map_id: String in _fixture().get("world", {}).get("maps", {}):
		var m: Dictionary = _fixture()["world"]["maps"][map_id]
		for s: Dictionary in m["signs"] + m["gates"]:
			texts[_norm(s["text"])] = "%s's sign or gate" % map_id
		for n: Dictionary in m["npcs"]:
			for l: String in n["lines"] + n.get("after", []):
				texts[_norm(l)] = "%s, %s" % [map_id, n["id"]]
		for c: Dictionary in m["crews"]:
			for l: String in c["before"] + [c["after"]]:
				texts[_norm(l)] = "%s, %s" % [map_id, c["id"]]
	for path in CODE_FILES:
		for raw in FileAccess.get_file_as_string(path).split("\n"):
			for text in WorldSnapshot.literals(raw):
				check(not texts.has(_norm(text)), "C-NOCODE: %s still says \"%s\" (%s)" % [path.get_file(), text, texts.get(_norm(text))])


# --- C-CHECKS ---------------------------------------------------------------

## C-CHECKS: the editor's live checks (src/content/content_checks.gd) find
## nothing wrong with the world: every door and pickup reachable, nobody
## standing on the only way somewhere, every line fits the text box.
func test_C_CHECKS_the_world_passes_the_editor_checks() -> void:
	var checks: Variant = _script("content_checks", "C-CHECKS")
	if checks == null:
		return
	var problems: Array = checks.problems()
	check(problems.is_empty(), "C-CHECKS: %d problems:\n  %s" % [problems.size(), "\n  ".join(problems)])


## C-CHECKS: and they do find each kind of problem, on a made-up yard:
##
##   TTTTTTTTTT   the start at (1,1); a corridor at (4,2), where `blocker`
##   T........T   stands; behind it a door to a map that doesn't exist and
##   TTTT.TTTTT   a door to a room; at (8,3) a card walled in. blocker says
##   T......T.T   one line far too long and five boxes in all.
##   TTTTTTTTTT
func test_C_CHECKS_find_each_kind_of_problem() -> void:
	var checks: Variant = _script("content_checks", "C-CHECKS")
	if checks == null or not check(_has_static("res://src/world/world_map.gd", "from_data"), "C-CHECKS: no WorldMap.from_data yet"):
		return
	var long_line := "Blah, ".repeat(40)
	var yard := {"outdoor": true, "rows": ["TTTTTTTTTT", "T........T", "TTTT.TTTTT", "T......T.T", "TTTTTTTTTT"],
		"labels": [], "signs": [], "crews": [], "gates": [],
		"warps": [{"cell": Vector2i(2, 3), "to": "nowhere", "to_cell": Vector2i(1, 1), "facing": Vector2i.DOWN},
			{"cell": Vector2i(6, 3), "to": "room", "to_cell": Vector2i(1, 1), "facing": Vector2i.DOWN}],
		"pickups": [{"id": "lost_card", "cell": Vector2i(8, 3), "card": 0}],
		"npcs": [{"id": "blocker", "name": "Blocker", "sprite": "npc", "cell": Vector2i(4, 2), "facing": Vector2i.DOWN,
			"lines": [long_line, "One.", "Two.", "Three.", "Four."]}]}
	var room := {"outdoor": false, "rows": ["WWWWW", "W___W", "WWWWW"], "labels": [], "signs": [], "crews": [],
		"npcs": [], "gates": [], "pickups": [],
		"warps": [{"cell": Vector2i(3, 1), "to": "yard", "to_cell": Vector2i(6, 3), "facing": Vector2i.UP}]}
	var maps := {"yard": _world_map().from_data("yard", yard), "room": _world_map().from_data("room", room)}
	var problems: Array = checks.problems(maps, "yard", Vector2i(1, 1))
	for want: Array in [["blocker", "(4, 2)"], ["nowhere"], ["lost_card"], ["(6, 3)"], ["blocker", "characters"], ["blocker", "boxes"]]:
		check(problems.any(func(p: String) -> bool: return want.all(func(w: String) -> bool: return w in p)),
			"C-CHECKS: nothing about %s in %s" % [want, problems])
	# Fixed (blocker steps aside and says less, the bad door and the
	# walled-in card gone), nothing's wrong.
	yard["npcs"][0]["cell"] = Vector2i(6, 1)
	yard["npcs"][0]["lines"] = ["Mind the yard."]
	yard["warps"].remove_at(0)
	yard["pickups"] = [{"id": "found_card", "cell": Vector2i(1, 3), "card": 0}]
	maps = {"yard": _world_map().from_data("yard", yard), "room": _world_map().from_data("room", room)}
	var left: Array = checks.problems(maps, "yard", Vector2i(1, 1))
	check(left.is_empty(), "C-CHECKS: the yard put right still has problems: %s" % [left])


## WorldMap's script, untyped, so a static it doesn't have yet is a
## runtime question (_has_static) rather than a parse error.
func _world_map() -> Variant:
	return load("res://src/world/world_map.gd")


func _has_static(path: String, method: String) -> bool:
	for m: Dictionary in (load(path) as GDScript).get_script_method_list():
		if m["name"] == method:
			return true
	return false


# --- C-EXPORT ---------------------------------------------------------------

## C-EXPORT: both export presets pack content/ (every file in it) and leave
## out the editor (src/editor/) and the dev-only tests/ and tools/, but not
## the content code the game runs on (src/content/). Filters are matched
## the way Godot's exporter does: a filter not starting res:// is matched as
## "*/<filter>" against the res:// path, case-insensitively.
func test_C_EXPORT_presets_pack_content_and_leave_out_the_editor() -> void:
	var cfg := ConfigFile.new()
	if not check(cfg.load("res://export_presets.cfg") == OK, "C-EXPORT: read export_presets.cfg"):
		return
	var files: Array[String] = ["content/atlas.json"]
	if DirAccess.dir_exists_absolute(ROOT):
		for sub in ["maps", "dialogue", "script"]:
			for f in DirAccess.get_files_at("%s/%s" % [ROOT, sub]):
				files.append("content/%s/%s" % [sub, f])
	var presets := 0
	for section in cfg.get_sections():
		if not section.begins_with("preset.") or section.ends_with(".options"):
			continue
		presets += 1
		var name := str(cfg.get_value(section, "name", section))
		var include := str(cfg.get_value(section, "include_filter", ""))
		var exclude := str(cfg.get_value(section, "exclude_filter", ""))
		for f in files:
			check(_filter_matches(include, f), "C-EXPORT: %s: include_filter \"%s\" doesn't pack %s" % [name, include, f])
			check(not _filter_matches(exclude, f), "C-EXPORT: %s: exclude_filter \"%s\" leaves out %s" % [name, exclude, f])
		for f in ["src/editor/edit_mode.gd", "src/editor/palette/tile_palette.gd", "tests/test_content.gd", "tools/snapshot_world.gd"]:
			check(_filter_matches(exclude, f), "C-EXPORT: %s: exclude_filter \"%s\" packs %s" % [name, exclude, f])
		for f in ["src/content/content.gd", "src/world/world_map.gd"]:
			check(not _filter_matches(exclude, f), "C-EXPORT: %s: exclude_filter \"%s\" leaves out %s" % [name, exclude, f])
	check(presets >= 2, "C-EXPORT: the Linux and Windows presets (%d)" % presets)


func _filter_matches(filters: String, path: String) -> bool:
	for raw in filters.split(","):
		var f := raw.strip_edges()
		if f == "":
			continue
		if not f.begins_with("res://"):
			f = "*/" + f
		if ("res://" + path).matchn(f):
			return true
	return false
