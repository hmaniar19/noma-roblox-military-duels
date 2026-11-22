#!/usr/bin/env bash
# Plays the real game in Roblox Studio and checks it (tests/playtest). macOS only; needs Studio and
# Accessibility permission for the terminal (it presses Play). Opens one Studio window, closes it when
# done, and exits non-zero on any failed check, script error, or timeout.
set -uo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/.rokit/bin:$PATH"

PLACE="$PWD/.cache/playtest.rbxl"
LOGS="$HOME/Library/Logs/Roblox"
TIMEOUT=${PLAYTEST_TIMEOUT:-300}

# Force-closing skips Studio's own cleanup, so also delete the place's lock file; a stale lock makes
# the next open show a "file is in use" dialog that blocks Play.
close_window() {
	pgrep -f "RobloxStudio -localPlaceFile $PLACE" | xargs kill -9 2>/dev/null || true
	sleep 1
	rm -f "$PLACE.lock"
}

mkdir -p .cache
rojo build tests/playtest/default.project.json -o "$PLACE" >/dev/null || { echo "PLAYTEST build failed"; exit 1; }
close_window

# Studio may append a new session to an existing log, so remember how far every log already goes
# and only read what is written after that.
SNAP=$(mktemp)
OUT=$(mktemp)
trap 'rm -f "$SNAP" "$OUT"' EXIT
for f in "$LOGS"/*Studio*_last.log; do
	[[ -f "$f" ]] && echo "$(wc -l <"$f" | tr -d ' ') $f"
done >"$SNAP"
collect() {
	: >"$OUT"
	for f in "$LOGS"/*Studio*_last.log; do
		[[ -f "$f" ]] || continue
		local seen
		seen=$(awk -v f="$f" '$2 == f { print $1 }' "$SNAP")
		tail -n +$((${seen:-0} + 1)) "$f" >>"$OUT"
	done
}

open -a RobloxStudio "$PLACE"
for _ in $(seq 1 90); do
	front=$(osascript -e 'tell application "System Events" to tell (first process whose frontmost is true) to get name of front window' 2>/dev/null || true)
	[[ "$front" == *playtest.rbxl* ]] && break
	sleep 2
done
[[ "$front" == *playtest.rbxl* ]] || { echo "PLAYTEST Studio window never came up"; close_window; exit 1; }

# Press Play (F5) with Studio in front; press again if no test output shows up (Studio may still
# have been loading, or another app took focus).
started=0
for attempt in 1 2 3; do
	sleep 5
	osascript -e 'tell application "RobloxStudio" to activate' 2>/dev/null || true
	sleep 1
	osascript -e 'tell application "System Events" to key code 96'
	for _ in $(seq 1 45); do
		sleep 1
		collect
		if grep -q "PLAYTEST" "$OUT"; then
			started=1
			break
		fi
	done
	(( started )) && break
	echo "PLAYTEST Play did not start (attempt $attempt)"
done

if (( started )); then
	for _ in $(seq 1 "$TIMEOUT"); do
		collect
		grep -q "PLAYTEST SERVER DONE" "$OUT" && grep -q "PLAYTEST CLIENT DONE" "$OUT" && break
		sleep 1
	done
fi
close_window

if (( ! started )); then
	echo "PLAYTEST no test output (Play never started)"
	exit 1
fi
log="$OUT"
grep -o "PLAYTEST .*" "$log"
errors=$(grep -c "Stack Begin" "$log" || true)
if (( errors > 0 )); then
	echo "PLAYTEST script errors: $errors"
	grep "CreatorError\|Info: Script '" "$log" | cut -c1-240 | head -20
fi
done_both=$(grep -c "PLAYTEST SERVER DONE\|PLAYTEST CLIENT DONE" "$log" || true)
fails=$(grep -c "PLAYTEST FAIL" "$log" || true)
if (( fails > 0 || errors > 0 || done_both < 2 )); then
	echo "PLAYTEST FAILED (fails=$fails errors=$errors finished=$done_both/2)"
	exit 1
fi
echo "PLAYTEST OK"
