extends Node
## Runs every tests/scene/test_*.gd with the real game around it and exits
## non-zero on any failure:
##
##   godot --headless --fixed-fps 60 --path . res://tests/scene_tests.tscn
##   godot --headless --fixed-fps 60 --path . res://tests/scene_tests.tscn -- journey
##
## A name fragment after `--` runs only the files or tests that contain it.
## tools/test.sh runs it as the `scene` and `journey` tiers, each in a
## throwaway XDG_DATA_HOME so the settings file isn't the real one either.
##
## A scene (this one), not a SceneTree script like tests/run_tests.gd,
## because scene tests need the Game, Sfx and Triggers autoloads, which a
## SceneTree script runs without. This node takes itself out of the way
## (it stops being the current scene) so a test's change_scene_to_file
## swaps the title and the overworld without freeing the runner.
##
## Each test gets a clean start (SceneTestCase's top has the rules): its own
## save file (user://scene_test.json, erased before and after; never the
## real save.json), Game.state null, no dev flags, no scene, nothing held on
## the pad. A Logger fails a test on any script error logged while it runs
## (GDScript has no exceptions: a crash in a test or in the game just logs
## and carries on). A test that doesn't finish within its `timeout_s` game
## seconds (or 10 real minutes) fails as hung and is parked for good at its
## next wait (SceneTestCase._stopped): GDScript can't cancel a coroutine.
##
## tests/expected_red.txt lists tests written ahead of their feature
## (TestCase.expected_red): while they fail on a check they print "red" and
## don't fail the run; if one passes, or breaks (a script error, a
## timeout), the run fails.

const SAVE_PATH := "user://scene_test.json"
const WALL_LIMIT_MS := 600000
const AFTER_TIMEOUT_FRAMES := 30  ## frames for a timed-out test to reach a wait and park


class ErrorCounter:
	extends Logger
	var count := 0
	var last := ""
	var mutex := Mutex.new()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return
		mutex.lock()
		count += 1
		last = "%s (%s:%d in %s)" % [rationale if rationale else code, file, line, function]
		mutex.unlock()


var _errors := ErrorCounter.new()


func _ready() -> void:
	OS.add_logger(_errors)
	_run.call_deferred()


func _run() -> void:
	var tree := get_tree()
	tree.current_scene = null  # so change_scene_to_file never frees the runner
	var only := ""
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--"):
			only = arg
	if OS.get_environment("XDG_DATA_HOME") == "" and OS.get_name() == "Linux":
		print("[scene] note: no XDG_DATA_HOME, so settings.cfg is the real one (saves go to %s, never save.json)" % SAVE_PATH)
	var expected := TestCase.expected_red()
	var total := 0
	var failed: Array[String] = []
	var red: Array[String] = []
	var started := Time.get_ticks_msec()
	var files: Array = Array(DirAccess.get_files_at("res://tests/scene"))
	files.sort()
	for file: String in files:
		if not (file.begins_with("test_") and file.ends_with(".gd")):
			continue
		var before_load := _errors.count
		var script: GDScript = load("res://tests/scene/" + file)
		if script == null or not script.can_instantiate() or _errors.count > before_load:
			failed.append("%s: doesn't compile" % file)
			print("FAIL ", file, " (doesn't compile)")
			continue
		for method in script.get_script_method_list():
			var test_name: String = method["name"]
			if not test_name.begins_with("test_"):
				continue
			if only and not (only in file or only in test_name):
				continue
			total += 1
			var case: SceneTestCase = script.new()
			case._current = "%s::%s" % [file.get_basename(), test_name]
			var outcome := await _run_one(case, test_name)
			var broken: bool = outcome["broken"]
			var took: float = outcome["seconds"]
			if expected.has(test_name):
				if case.failures.is_empty():
					failed.append("%s: listed in tests/expected_red.txt but passes now: delete its line" % case._current)
					print("FAIL %s (expected red, but it passes) %.1fs" % [case._current, took])
				elif broken:
					failed.append_array(case.failures)
					print("FAIL %s (expected red, but broken) %.1fs" % [case._current, took])
				else:
					red.append(case.failures[0])
					print("red  %s %.1fs" % [case._current, took])
			elif case.failures:
				failed.append_array(case.failures)
				print("FAIL %s %.1fs" % [case._current, took])
			else:
				print("ok   %s %.1fs" % [case._current, took])
	print("\n%d scene tests, %d failures, %d red (expected), %.1fs" % [total, failed.size(), red.size(), (Time.get_ticks_msec() - started) / 1000.0])
	if red:
		print("red (expected, tests/expected_red.txt), first failure each:")
		for r in red:
			print("  ", r)
	for f in failed:
		printerr("  ", f)
	await _clean(tree)
	tree.quit(1 if failed or total == 0 else 0)


## Runs one test from a clean start; returns {"broken": a script error or a
## timeout, "seconds": real seconds taken}.
func _run_one(case: SceneTestCase, test_name: String) -> Dictionary:
	var tree := get_tree()
	await _clean(tree)
	case.tree = tree
	case.game = _game()
	var errors_before := _errors.count
	var started := Time.get_ticks_msec()
	var done := [false]
	var body := func() -> void:
		await case.call(test_name)
		done[0] = true
	body.call()
	var frames := 0
	var timed_out := false
	while not done[0]:
		await tree.process_frame
		frames += 1
		if frames > int(case.timeout_s * 60.0) or Time.get_ticks_msec() - started > WALL_LIMIT_MS:
			timed_out = true
			case.failures.append("%s: timed out: still running after %.0f game seconds (%.0f real)%s" % [case._current, frames / 60.0,
				(Time.get_ticks_msec() - started) / 1000.0, case._where()])
			case._aborted = true
			for _i in AFTER_TIMEOUT_FRAMES:
				await tree.process_frame
			break
	case.release_all()
	var logged := _errors.count - errors_before
	if logged:
		case.failures.append("%s: %d script error(s), the last: %s" % [case._current, logged, _errors.last])
	await _clean(tree)
	return {"broken": timed_out or logged > 0, "seconds": (Time.get_ticks_msec() - started) / 1000.0}


## No scene, no run, no dev flags, no save, nothing held.
func _clean(tree: SceneTree) -> void:
	var game := _game()
	for action in ["ui_accept", "ui_cancel", "menu", "move_up", "move_down", "move_left", "move_right", "ui_up", "ui_down", "ui_left", "ui_right"]:
		Input.action_release(action)
	await tree.process_frame
	await tree.process_frame  # a change_scene_to_file in flight lands
	var scene := tree.current_scene
	if scene:
		tree.current_scene = null
		scene.queue_free()
	for c in tree.root.get_children():
		if c != self and c != game and c.name not in ["Sfx", "Triggers"]:
			c.queue_free()  # anything else a test left at the root
	await tree.process_frame
	game.state = null
	game.save_path = SAVE_PATH
	game.dev_args = {}
	game.dev_auto = false
	game.dev_choice = 0
	SaveFile.erase(SAVE_PATH)


func _game() -> Node:
	return get_tree().root.get_node("Game")
