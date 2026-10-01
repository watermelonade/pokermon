extends SceneTree
## Runs every tests/test_*.gd headless and exits non-zero on any failure:
##
##   godot --headless --path . -s tests/run_tests.gd
##
## Pass a name fragment after `--` to run only matching files or tests:
##   godot --headless --path . -s tests/run_tests.gd -- side_pot
##
## GDScript has no exceptions: a script error inside a test just returns
## null and carries on, which would let a crashing test "pass". So the runner
## installs a Logger and fails any test during which an error is logged, and
## fails the run if a test file doesn't compile.


class ErrorCounter:
	extends Logger
	var count := 0

	func _log_error(_function: String, _file: String, _line: int, _code: String, _rationale: String,
			_editor_notify: bool, _error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		count += 1


func _init() -> void:
	var errors := ErrorCounter.new()
	OS.add_logger(errors)
	var only := ""
	var args := OS.get_cmdline_user_args()
	if args:
		only = args[0]
	var total := 0
	var failed: Array[String] = []
	var started := Time.get_ticks_msec()
	for file in DirAccess.get_files_at("res://tests"):
		if not (file.begins_with("test_") and file.ends_with(".gd")) or file == "test_case.gd":
			continue
		var before_load := errors.count
		var script: GDScript = load("res://tests/" + file)
		if script == null or not script.can_instantiate() or errors.count > before_load:
			failed.append("%s: doesn't compile" % file)
			print("FAIL ", file, " (doesn't compile)")
			continue
		for method in script.get_script_method_list():
			var test_name: String = method["name"]
			if not test_name.begins_with("test_"):
				continue
			if only and not (only in file or only in test_name):
				continue
			var case: TestCase = script.new()
			case._current = "%s::%s" % [file.get_basename(), test_name]
			var before := errors.count
			case.call(test_name)
			total += 1
			var logged := errors.count - before
			if logged != case.expected_errors:
				case.failures.append("%s: %d script error(s), expected %d, see log above" % [case._current, logged, case.expected_errors])
			if case.failures:
				failed.append_array(case.failures)
				print("FAIL ", case._current)
			else:
				print("ok   ", case._current)
	print("\n%d tests, %d failures, %.1fs" % [total, failed.size(), (Time.get_ticks_msec() - started) / 1000.0])
	for f in failed:
		printerr("  ", f)
	quit(1 if failed or total == 0 else 0)
