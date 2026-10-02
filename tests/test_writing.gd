extends TestCase
## Every line the demo says must fit the overworld's text box: at most two
## wrapped lines (Game Boy style, read at a glance; the box has room for a
## third under a speaker's name, kept as slack), measured with the font and
## size DialogBox draws with at the 640x400 base resolution. With today's
## font every line fits on one row (about 110 characters do), so the real
## limit is the character cap on the data lines: 84, one row of the table's
## pixel font (Departure Mono, 11px), so the text still fits if the box moves
## to it. And no speech runs longer than four boxes. docs/WRITING.md has the
## rules; the format strings in overworld.gd are measured with worst-case
## names filled in instead of capped, and so are the {placeholders} in
## content/'s lines (capped too: a writer's line should fit with any name).

## The measure itself (the box's width, the greedy wrap, the caps and the
## worst-case names) is ContentChecks' since the editor's phase 1, which
## checks lines live as they're typed (docs/EDITOR_SPEC.md C-CHECKS); these
## tests call it rather than keep their own copy.
const MAX_WRAPPED := ContentChecks.MAX_WRAPPED
const LONG_NAME := ContentChecks.LONG_NAME
const BIG_NUMBER := ContentChecks.BIG_NUMBER


func _wrapped_lines(text: String) -> int:
	return ContentChecks.wrapped_lines(text)


func _check_line(text: String, where: String, cap_chars := true) -> void:
	for problem in ContentChecks.line_problems(text, where, cap_chars):
		check(false, problem)


func _check_speech(lines: Array, where: String) -> void:
	for problem in ContentChecks.speech_problems(lines, where):
		check(false, problem)


func test_the_measure_wraps() -> void:
	check_eq(_wrapped_lines("Honk."), 1)
	var long := "HONK ".repeat(60).strip_edges()
	check(_wrapped_lines(long) >= 3, "a 300-character line wraps (measured %d lines)" % _wrapped_lines(long))


func test_map_lines_fit_the_text_box() -> void:
	for map_id: String in WorldMap.ids():
		var m := WorldMap.get_map(map_id)
		for s: Dictionary in m.signs:
			_check_line(s["text"], "%s sign %s" % [map_id, s["cell"]])
		for n: Dictionary in m.npcs:
			_check_speech(n["lines"], "%s %s" % [map_id, n["id"]])
		for c: Dictionary in m.crews:
			_check_speech(c["before"], "%s before" % c["id"])
			_check_line(c["after"], "%s after" % c["id"])


func test_every_animal_has_a_bio_and_a_recruit_line() -> void:
	for id: StringName in Species.ids():
		for animal_name: String in Species.get_info(id)["individuals"]:
			var bio := Bios.bio(id, animal_name)
			var line := Bios.recruit_line(id, animal_name)
			check(bio != "", "%s %s has a bio" % [id, animal_name])
			check(line != "", "%s %s has a recruit line" % [id, animal_name])
			_check_line(bio, "%s bio" % animal_name)
			_check_line(line, "%s recruit" % animal_name)
		check_eq(Bios.BIOS.get(id, {}).size(), 4, "%s: no bios for animals that don't exist" % id)
	check_eq(Bios.bio(&"dog", "Rex"), "", "unknown animals have no bio (dogs come later)")


## The lines the overworld's code asks for by name, now in content/ (the
## intro, Rosie's, the narration; editor phase 1 moved them out of
## overworld.gd): every set of them, with worst-case names and sums in its
## {placeholders}. The townsfolk's, crews' and signs' lines are checked
## above, through the maps.
func test_content_lines_fit_the_text_box() -> void:
	var sets := {}  ## "file.speaker.set" -> [texts]
	for line: Dictionary in Content.all_lines():
		var key := "%s.%s.%s" % [line["file"], line["speaker"], line["set"]]
		if not sets.has(key):
			sets[key] = []
		sets[key].append(str(line["text"]).format({"crew": LONG_NAME, "lost": BIG_NUMBER}))
	for want: Array in Content.CODE_LINES:
		check(sets.has("%s.%s.%s" % want), "content has the lines the code says: %s" % [want])
	for key: String in sets:
		_check_speech(sets[key], key)


## What's still a string literal in src/world/overworld.gd (system text:
## what the game just did, the menus), some with %s and %d: read the source
## and check each with worst-case names and sums filled in. Before editor
## phase 1 the intro, Rosie's and the narration were here too (at least
## 10 of them); they're test_content_lines_fit_the_text_box's now.
func test_overworld_lines_fit_the_text_box() -> void:
	var source := FileAccess.get_file_as_string("res://src/world/overworld.gd")
	check(source != "", "read overworld.gd")
	var literal := RegEx.create_from_string("\"((?:[^\"\\\\]|\\\\.)*)\"")
	var checked := 0
	for raw in source.split("\n"):
		var line := raw.strip_edges()
		if line.begins_with("#") or "dev_log" in line or "res://" in line:
			continue
		for m in literal.search_all(line):
			var text := m.get_string(1).replace("\\\"", "\"")
			if text.length() < 30 or not " " in text:
				continue
			text = text.replace("%s", LONG_NAME).replace("%d", BIG_NUMBER)
			_check_line(text, "overworld.gd", false)
			checked += 1
	check(checked >= 3, "found the overworld's system lines (%d)" % checked)
