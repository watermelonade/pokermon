extends SceneTree
## Rewrites every file in content/ in canonical form (ContentFormat) and
## lists what's wrong with the content, for after editing it by hand:
##
##   godot --headless --path . -s tools/format_content.gd            # format, then check
##   godot --headless --path . -s tools/format_content.gd -- --check  # check only, write nothing
##
## The check is C-SCHEMA's (ContentSchema: keys, tiles, cells, names, ids,
## doors, lines) and C-CHECKS' (ContentChecks: doors and cards reachable,
## nobody in the way, lines fitting the box). Exits 1 if a file doesn't
## parse or anything's wrong, so it can sit in a script. A file that
## doesn't parse is left as it is (and named, with the line).

func _init() -> void:
	var write := not OS.get_cmdline_user_args().has("--check")
	var bad := 0
	for path in Content.files():
		var text := FileAccess.get_file_as_string(path)
		var data: Variant = ContentFormat.parse(text)
		if not data is Dictionary:
			print("%s: doesn't parse: %s" % [path, ContentFormat.parse_error(text)])
			bad += 1
			continue
		var canonical := ContentFormat.stringify(data)
		if canonical == text:
			continue
		if write:
			var f := FileAccess.open(path, FileAccess.WRITE)
			f.store_string(canonical)
			f.close()
			print("formatted ", path)
		else:
			print("%s: not in canonical form (run without --check to format it)" % path)
			bad += 1
	if bad == 0:
		var problems := ContentSchema.check_files()
		if problems.is_empty():
			Content.reload()
			WorldMap.reload()
			problems = ContentChecks.problems()
		for p in problems:
			print(p)
		bad += problems.size()
	print("content: %s" % ("ok" if bad == 0 else "%d problem(s)" % bad))
	quit(1 if bad else 0)
