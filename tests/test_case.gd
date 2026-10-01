class_name TestCase
extends RefCounted
## Base for tests: every method named test_* is run by tests/run_tests.gd.
## A tiny home-grown runner instead of an addon (GUT, gdUnit4), so the tests
## run on a bare Godot binary in CI and in cloud sessions with no setup.

var failures: Array[String] = []
var expected_errors := 0  ## errors this test means to cause (see expect_errors)
var _current := ""


## Declares that the test deliberately triggers `count` logged errors (a
## push_error from misuse being refused); the runner fails it on any more
## or fewer.
func expect_errors(count: int) -> void:
	expected_errors += count


## Test names (method names, e.g. test_S_DECK_collect_adds_once) listed in
## tests/expected_red.txt, one per line, `#` starting a comment: tests
## written before the feature they check (docs/DEMO_SPEC.md is built test
## first). Both runners (this one's and tests/scene_runner.gd) report them as
## "red (expected)" without failing the run while they fail on a check, and
## fail the run if one passes (whoever turns it green deletes its line) or
## breaks instead (a script error, a timeout: that's not red, that's broken).
static func expected_red(path := "res://tests/expected_red.txt") -> Dictionary:
	var out := {}
	if not FileAccess.file_exists(path):
		return out
	for line in FileAccess.get_file_as_string(path).split("\n"):
		var name := line.get_slice("#", 0).strip_edges()
		if name:
			out[name] = true
	return out


func check(condition: bool, message := "") -> bool:
	if not condition:
		failures.append("%s: %s" % [_current, message if message else "check failed"])
	return condition


func check_eq(actual: Variant, expected: Variant, message := "") -> bool:
	if actual != expected:
		failures.append("%s: %s expected %s, got %s" % [_current, message, str(expected), str(actual)])
		return false
	return true
