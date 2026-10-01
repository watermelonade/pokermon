class_name TestCase
extends RefCounted
## Base for tests: every method named test_* is run by tests/run_tests.gd.
## A tiny home-grown runner instead of an addon (GUT, gdUnit4), so the tests
## run on a bare Godot binary in CI and in cloud sessions with no setup.

var failures: Array[String] = []
var _current := ""


func check(condition: bool, message := "") -> bool:
	if not condition:
		failures.append("%s: %s" % [_current, message if message else "check failed"])
	return condition


func check_eq(actual: Variant, expected: Variant, message := "") -> bool:
	if actual != expected:
		failures.append("%s: %s expected %s, got %s" % [_current, message, str(expected), str(actual)])
		return false
	return true
