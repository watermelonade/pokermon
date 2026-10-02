#!/usr/bin/env bash
# Batch runs of the playtester (tools/playtest.gd). See docs/PLAYTEST.md.
#
#   tools/playtest.sh runs COUNT [FIRST_SEED] [--pt-flags...]   skipped matches (fast); every 10th seed
#                                                              plays on from a pre-demo save, and seeds
#                                                              ending in 5 start stranded ($0, no crew)
#   tools/playtest.sh real COUNT [FIRST_SEED] [--pt-flags...]   real matches at the table
#   tools/playtest.sh kill COUNT [FIRST_SEED]                   kill -9 at random moments, then Continue
#   tools/playtest.sh damaged [--pt-flags...]                   every kind of damaged save
#   tools/playtest.sh summary [DIR]                             failures and stats so far
#
# Environment: GODOT (the binary, default `godot`), JOBS (Godot processes at
# once, default 2), OUT (results, default /tmp/playtest). Every run gets its
# own XDG_DATA_HOME, so no real save or settings file is touched. Results:
# $OUT/<kind>/<seed>.json (one JSON line) and $OUT/<kind>/<seed>.log.
set -u
cd "$(dirname "$0")/.."
GODOT=${GODOT:-godot}
JOBS=${JOBS:-2}
OUT=${OUT:-/tmp/playtest}

one_run() {  # kind seed timeout flags...
	local kind=$1 seed=$2 limit=$3
	shift 3
	local dir="$OUT/$kind"
	local data
	data=$(mktemp -d "${TMPDIR:-/tmp}/pt-data.XXXXXX")
	XDG_DATA_HOME="$data" timeout -s KILL "$limit" "$GODOT" --headless --fixed-fps 60 --path . \
		-s tools/playtest.gd -- --pt-seed="$seed" --pt-out="$dir/$seed.json" "$@" > "$dir/$seed.log" 2>&1
	local code=$?
	if [ ! -s "$dir/$seed.json" ]; then
		# Killed by the timeout or crashed before reporting: a failure too.
		printf '{"ok":false,"seed":%s,"why":"no result (exit %s)","failures":[{"kind":"crash_or_timeout","message":"exit %s after %ss limit","frame":0}],"replay":"%s"}\n' \
			"$seed" "$code" "$code" "$limit" "XDG_DATA_HOME=\$(mktemp -d) godot --headless --fixed-fps 60 --path . -s tools/playtest.gd -- --pt-seed=$seed $*" > "$dir/$seed.json"
	fi
	rm -rf "$data"
	printf '%s %s: %s\n' "$kind" "$seed" "$(grep -o '"ok":[a-z]*' "$dir/$seed.json" | head -1)"
}
export -f one_run
export GODOT OUT

batch() {  # kind count first_seed timeout flags...
	local kind=$1 count=$2 first=$3 limit=$4
	shift 4
	mkdir -p "$OUT/$kind"
	seq "$first" $((first + count - 1)) | xargs -P "$JOBS" -I{} bash -c 'one_run "$@"' _ "$kind" {} "$limit" "$@"
}

# Kill torture: one save slot, played in short bursts that are each killed
# with SIGKILL at a random moment (often mid-write: --pt-save-spam saves many
# times a frame), then checked by a run that only loads it. The slot must
# always load, pass the state checks, and never lose a beaten crew or a
# recruit that an earlier save had (the .floor file the playtester keeps).
kill_torture() {
	local count=$1 first=$2
	local dir="$OUT/kill"
	mkdir -p "$dir"
	local data
	data=$(mktemp -d "${TMPDIR:-/tmp}/pt-kill.XXXXXX")
	local fails=0 midsave=0
	for i in $(seq "$first" $((first + count - 1))); do
		# No extra saves, some, or so many that most of the time is spent saving.
		local spam=$(( i % 3 == 0 ? 0 : (i % 3 == 1 ? 100 : 2000) ))
		local ms=$(( 300 + (RANDOM * 32768 + RANDOM) % 6000 ))
		( ( XDG_DATA_HOME="$data" timeout -s KILL "$(printf '%d.%03d' $((ms / 1000)) $((ms % 1000)))" "$GODOT" --headless --fixed-fps 60 --path . \
			-s tools/playtest.gd -- --pt-start=continue --pt-seed="$i" --pt-save-spam="$spam" --pt-reload=0.02 --pt-win=0.7 \
			> "$dir/$i.killed.log" 2>&1 ) & wait $! ) 2>/dev/null
		local code=$?
		[ -e "$data/AFriendInNeed/playtest.json.part" ] && midsave=$((midsave + 1))
		cp "$data/AFriendInNeed/playtest.json" "$dir/$i.save.json" 2>/dev/null
		cp "$data/AFriendInNeed/playtest.json.part" "$dir/$i.save.json.part" 2>/dev/null
		# The check: load what the kill left, a few frames, no saving over it first.
		XDG_DATA_HOME="$data" timeout -s KILL 60 "$GODOT" --headless --fixed-fps 60 --path . \
			-s tools/playtest.gd -- --pt-start=continue --pt-seed="$i" --pt-frames=400 --pt-reload=0 \
			--pt-out="$dir/$i.json" > "$dir/$i.log" 2>&1
		local ok
		ok=$(grep -o '"ok":[a-z]*' "$dir/$i.json" 2>/dev/null | head -1)
		[ "$ok" = '"ok":true' ] || fails=$((fails + 1))
		printf 'kill %s after %sms (spam %s, exit %s): check %s\n' "$i" "$ms" "$spam" "$code" "${ok:-no result}"
	done
	rm -rf "$data"
	echo "kill torture: $count kills ($midsave left a .part: killed mid-save), $fails failed checks"
}

DAMAGE_KINDS="ok truncated empty garbage array minimal no_version future_version unknown_species
all_unknown_species roster_dict roster_one roster_dupes party_oob party_negative party_dup party_one
party_three party_strings money_negative money_string money_huge cell_wall cell_oob cell_string
cell_crew_home cell_recruit_home cell_door map_unknown heal_wall heal_oob heal_map_unknown
beaten_unknown beaten_regulars_no_bracelet bracelet_only facing_zero facing_weird bond_weird
unbeaten_member_in_roster seen_intro_false part_only part_newer_main_truncated
pre_demo pre_demo_alone deck_short_in_town deck_garbage deck_dupes deck_oob taken_unknown
alone_met_table alone_before_table"

damaged() {
	mkdir -p "$OUT/damaged"
	local n=0
	for kind in $DAMAGE_KINDS; do
		n=$((n + 1))
		echo "$n $kind"
	# Lenient about what a damaged save legitimately carries in (strangers in
	# the roster, unknown crews, a bracelet without the win, a deck that
	# breaks the opening's rules or is short past the gate).
	done | xargs -P "$JOBS" -n 2 bash -c 'one_run damaged "$0" 300 --pt-damage="$1" --pt-frames=20000 --pt-lenient=roster_stranger,beaten_unknown,bracelet,deck_size,deck_cards,deck_pickups,pickup_unknown,gate_bypassed,crew_early '"$*"
}

summary() {
	python3 - "${1:-$OUT}" <<'EOF'
import json, sys, glob, os, collections
root = sys.argv[1]
for kind in sorted(os.listdir(root)):
    files = sorted(glob.glob(os.path.join(root, kind, "*.json")), key=lambda p: os.path.basename(p))
    results = []
    for f in files:
        if f.endswith(".save.json"):
            continue
        try:
            results.append(json.loads(open(f).read().strip().splitlines()[-1]))
        except Exception as e:
            results.append({"ok": False, "seed": os.path.basename(f), "failures": [{"kind": "unreadable_result", "message": str(e)}]})
    if not results:
        continue
    ok = sum(1 for r in results if r.get("ok"))
    print(f"== {kind}: {len(results)} runs, {ok} ok, {len(results) - ok} failed")
    stats = [r.get("stats", {}) for r in results if r.get("stats")]
    if stats:
        done = [s for s in stats if s.get("demo_complete")]
        tot = lambda k: sum(s.get(k, 0) for s in stats)
        print(f"   demo completed in {len(done)}/{len(stats)} runs; reached the hall in {sum(1 for s in stats if s.get('reached_hall'))}")
        if done:
            fr = sorted(s["frames_to_complete"] for s in done)
            print(f"   game time to complete: median {fr[len(fr)//2]/60:.0f}s, max {fr[-1]/60:.0f}s")
        new = [s for s in stats if not s.get("old_save") and not s.get("stranded_start")]
        def med(key):
            v = sorted(s[key] for s in new if s.get(key))
            return f"{len(v)}/{len(new)} (median {v[len(v)//2]/60:.0f}s)" if v else f"0/{len(new)}"
        if new:
            print(f"   opening (new games): all four Aces {med('frames_to_deck')}, Mill Road {med('frames_to_mill_road')}, "
                  f"Mossbank {med('frames_to_town')}, crew from the open table {med('frames_to_crew')}")
        print(f"   opening totals: {tot('pickups')} cards picked up, {tot('gifts')} given, {tot('gate_refusals')} gate refusals, "
              f"{tot('alone_in_sight')} times alone in a crew's sight; {sum(1 for s in stats if s.get('old_save'))} runs from a pre-demo save")
        print(f"   open table: {tot('cash_sessions')} sessions ({tot('cash_human')} by random presses, {tot('cash_forfeits')} quit while seated), "
              f"{tot('cash_hands')} hands, net {tot('cash_net'):+d} chips; {tot('cash_offers')} seat offers, {tot('cash_declined')} declined")
        stranded = [s for s in stats if s.get("stranded_start")]
        back = sorted(s["frames_stranded_to_table"] for s in stranded if s.get("frames_stranded_to_table"))
        print(f"   street game: {tot('street_sessions')} sessions, {tot('street_hands')} hands, ${tot('street_kept')} kept, "
              f"{tot('street_refusals')} dogs with money turned away; {len(stranded)} stranded starts, "
              f"{len(back)} back at the open table" + (f" (median {back[len(back)//2]/60:.0f} game s)" if back else ""))
        print(f"   totals: {tot('steps')} steps, {tot('encounters')} encounters ({tot('wins')} won, {tot('losses')} lost), "
              f"{tot('real_matches')} real matches, {tot('recruits')} recruits, {tot('talks')} talks, {tot('doors')} doors, "
              f"{tot('menus')} start menus, {tot('reloads')} quit+continue, {tot('saves_written')} saves checked")
        secs = [r.get("real_s", 0) for r in results]
        print(f"   real time: {sum(secs):.0f}s total, {max(secs):.0f}s longest run")
    by = collections.defaultdict(list)
    for r in results:
        for f in r.get("failures", []):
            by[(f.get("kind"), f.get("message", "")[:160])].append(r)
    for (k, m), rs in sorted(by.items(), key=lambda kv: -len(kv[1])):
        print(f"   FAIL {k} x{len(rs)}: {m}")
        print(f"      seeds {[r.get('seed') for r in rs][:12]}")
        print(f"      replay: {rs[0].get('replay')}")
EOF
}

cmd=${1:-}
shift || true
case "$cmd" in
	runs) batch runs "${1:-20}" "${2:-1}" 600 --pt-start=mix "${@:3}" ;;
	real) batch real "${1:-4}" "${2:-1001}" 3600 --pt-real=1 --pt-human=0.25 --pt-after=40 --pt-chips=200 --pt-seconds=3300 "${@:3}" ;;
	kill) kill_torture "${1:-50}" "${2:-1}" ;;
	damaged) damaged "$@" ;;
	summary) summary "${1:-$OUT}" ;;
	*) sed -n '2,15p' "$0"; exit 2 ;;
esac
