extends Node
## Compiles every script under src/ and exits non-zero if any fails:
##
##   godot --headless --path . res://tests/compile_check.tscn
##
## A scene, not part of tests/run_tests.gd, because the test runner runs as a
## SceneTree script, where autoloads (Game, Sfx) don't exist, so any script
## that names one can't compile there. That's also how a parse error in
## overworld.gd once passed the whole suite and only showed when the game
## ran. CI runs this after the tests.


class ErrorCounter:
	extends Logger
	var count := 0

	func _log_error(_function: String, _file: String, _line: int, _code: String, _rationale: String,
			_editor_notify: bool, _error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		count += 1


func _ready() -> void:
	var errors := ErrorCounter.new()
	OS.add_logger(errors)
	var broken: Array[String] = []
	var scripts := _scripts("res://src")
	for path in scripts:
		var before := errors.count
		var script: GDScript = load(path)
		if script == null or not script.can_instantiate() or errors.count > before:
			broken.append(path)
	for path in broken:
		printerr("doesn't compile: ", path)
	print("%d scripts, %d don't compile" % [scripts.size(), broken.size()])
	get_tree().quit(1 if broken else 0)


func _scripts(dir: String) -> Array[String]:
	var out: Array[String] = []
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		out.append_array(_scripts(dir.path_join(d)))
	return out
