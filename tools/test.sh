#!/usr/bin/env bash
# One entry point for every test tier. Prints a pass/fail table at the end
# and exits non-zero if any tier failed.
#
#   tools/test.sh quick            unit + compile: the pre-commit check (~25s)
#   tools/test.sh full             unit + compile + pad + scene + chart: "done" for a demo
#   tools/test.sh soak             the playtester: 20 fast runs, 1 real, 10 kills (minutes)
#   tools/test.sh unit             tests/run_tests.gd (rules, maps, state; no autoloads)
#   tools/test.sh compile          tests/compile_check.tscn (every script, with the autoloads)
#   tools/test.sh pad              tests/pad_check.tscn (a pretend Xbox pad at the real table)
#   tools/test.sh scene            tests/scene_tests.tscn (the real game, driven by pad events)
#   tools/test.sh journey          the scene tests in tests/scene/test_journey.gd only
#   tools/test.sh chart            R-CHART: tools/simulate.gd -- 8 123 --cycle against
#                                  tests/baselines/cycle_8_123.txt (bot 3v3 unchanged)
#   tools/test.sh TIER... -k FRAG  pass a name fragment to the unit and scene runners
#                                  (e.g. -k S_DECK, -k G_SIT); a runner with nothing
#                                  matching shows "none", not a failure
#
# Several tiers can be given (tools/test.sh unit scene -k CASH). Environment:
# GODOT (the binary, default `godot`); for soak, JOBS (default 2) and OUT
# (results, default /tmp/playtest-soak; its runs/, real/ and kill/ are
# cleared first). The scene and soak tiers run in a throwaway XDG_DATA_HOME,
# so no real save or settings file is touched.
#
# Tests listed in tests/expected_red.txt are written ahead of their feature
# (docs/DEMO_SPEC.md): they print "red" and don't fail a tier while they
# fail on a check. README.md "Tests" has the whole story.
#
# The project is re-imported first (a few seconds), so a new class_name
# script is visible ("Identifier not declared" otherwise); TEST_NO_IMPORT=1
# skips that.
set -u
cd "$(dirname "$0")/.."
GODOT=${GODOT:-godot}
JOBS=${JOBS:-2}
OUT=${OUT:-/tmp/playtest-soak}
export GODOT JOBS OUT

tiers=()
filter=""
while [ $# -gt 0 ]; do
	case "$1" in
		-k) filter=${2:-}; shift 2 ;;
		-k*) filter=${1#-k}; shift ;;
		-h|--help) sed -n '2,31p' "$0"; exit 0 ;;
		*) tiers+=("$1"); shift ;;
	esac
done
[ ${#tiers[@]} -eq 0 ] && { sed -n '2,31p' "$0"; exit 2; }

expanded=()
for t in "${tiers[@]}"; do
	case "$t" in
		quick) expanded+=(unit compile) ;;
		full) expanded+=(unit compile pad scene chart) ;;
		unit|compile|pad|scene|journey|chart|soak) expanded+=("$t") ;;
		*) echo "unknown tier: $t" >&2; sed -n '2,31p' "$0"; exit 2 ;;
	esac
done

logs=$(mktemp -d "${TMPDIR:-/tmp}/test-sh.XXXXXX")
names=()
results=()
times=()
started_all=$(date +%s)

# Runs one tier: name, then the command. Streams its output and keeps it in
# $logs/<name>.log; the tier's result is pass, FAIL or none (a filter that
# matched no test).
run() {
	local name=$1
	shift
	echo
	echo "=== $name: $*"
	local t0=$(date +%s)
	"$@" 2>&1 | tee "$logs/$name.log"
	local code=${PIPESTATUS[0]}
	local result=pass
	if [ -n "$filter" ] && grep -qE '^0 (scene )?tests,' "$logs/$name.log"; then
		result=none
	elif [ "$code" -ne 0 ]; then
		result=FAIL
	fi
	names+=("$name")
	results+=("$result")
	times+=($(( $(date +%s) - t0 )))
}

# The scene runner in its own data dir, at a fixed 60 frames a game second.
scene() {
	local data
	data=$(mktemp -d "${TMPDIR:-/tmp}/scene-data.XXXXXX")
	XDG_DATA_HOME="$data" "$GODOT" --headless --fixed-fps 60 --path . res://tests/scene_tests.tscn -- "$@"
	local code=$?
	rm -rf "$data"
	return $code
}

# R-CHART: bot-only 3v3 matches give exactly the baseline's output (made
# with the same grep, which drops the banner, the timing line and blank
# lines). Script errors on stderr fail it too.
chart() {
	local got err
	got=$(mktemp)
	err=$(mktemp)
	"$GODOT" --headless --path . -s tools/simulate.gd -- 8 123 --cycle 2>"$err" | grep -v "Godot Engine\|matches, \|^$" > "$got"
	local code=0
	if grep -q "SCRIPT ERROR" "$err"; then
		grep -A3 "SCRIPT ERROR" "$err"
		code=1
	fi
	if diff -u tests/baselines/cycle_8_123.txt "$got"; then
		echo "chart: same as tests/baselines/cycle_8_123.txt"
	else
		echo "chart: differs from tests/baselines/cycle_8_123.txt (above)"
		code=1
	fi
	rm -f "$got" "$err"
	return $code
}

# R-PLAY: the playtester's batches; playtest.sh reports, this judges.
soak() {
	rm -rf "$OUT/runs" "$OUT/real" "$OUT/kill"
	tools/playtest.sh runs 20
	tools/playtest.sh real 1
	tools/playtest.sh kill 10 | tee "$OUT/kill.txt"
	tools/playtest.sh summary "$OUT"
	local bad=0 total=0
	for f in "$OUT"/runs/*.json "$OUT"/real/*.json; do
		[ -e "$f" ] || continue
		total=$((total + 1))
		grep -q '"ok":true' "$f" || bad=$((bad + 1))
	done
	local killed
	killed=$(grep -o '[0-9]* failed checks' "$OUT/kill.txt" | grep -o '^[0-9]*')
	echo "soak: $total runs, $bad failed; kill torture: ${killed:-?} failed checks"
	[ "$total" -eq 21 ] && [ "$bad" -eq 0 ] && [ "${killed:-1}" -eq 0 ]
}

if [ "${TEST_NO_IMPORT:-0}" != 1 ]; then
	echo "=== import (the class cache, for new class_name scripts)"
	"$GODOT" --headless --path . --import > "$logs/import.log" 2>&1 || { tail -20 "$logs/import.log"; echo "import failed"; exit 1; }
fi

for t in "${expanded[@]}"; do
	case "$t" in
		unit) run unit "$GODOT" --headless --path . -s tests/run_tests.gd -- $filter ;;
		compile) run compile "$GODOT" --headless --path . res://tests/compile_check.tscn ;;
		pad) run pad "$GODOT" --headless --path . res://tests/pad_check.tscn ;;
		scene) run scene scene $filter ;;
		journey) run journey scene journey ;;
		chart) run chart chart ;;
		soak) run soak soak ;;
	esac
done

echo
echo "tier      result  seconds"
failed=0
for i in "${!names[@]}"; do
	printf '%-9s %-7s %s\n' "${names[$i]}" "${results[$i]}" "${times[$i]}"
	[ "${results[$i]}" = FAIL ] && failed=1
done
echo "total $(( $(date +%s) - started_all ))s; logs in $logs"
exit $failed
