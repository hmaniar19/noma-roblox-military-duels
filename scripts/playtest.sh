#!/usr/bin/env bash
# Plays the real game in Roblox Studio and checks it (tests/playtest). macOS only; needs Studio and
# Accessibility permission for the terminal (it presses Play). Opens one Studio window, closes it when
# done, and exits non-zero on any failed check, script error, or timeout.
set -uo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/.rokit/bin:$PATH"

PLACE="$PWD/.cache/playtest.rbxl"
LOGS="$HOME/Library/Logs/Roblox"
TIMEOUT=${PLAYTEST_TIMEOUT:-600}

# Force-closing skips Studio's own cleanup, so also delete the place's lock file (a stale lock makes
# the next open show a "file is in use" dialog that blocks Play). A force-close can also leave a
# Studio process with no windows at all, which swallows the next open request and ignores a normal
# quit; only such windowless processes are closed, never a window someone is working in.
close_window() {
	pgrep -f "RobloxStudio -localPlaceFile $PLACE" | xargs kill -9 2>/dev/null || true
	sleep 2
	rm -f "$PLACE.lock"
	local windows
	windows=$(osascript -e 'tell application "System Events" to if exists process "RobloxStudio" then count windows of process "RobloxStudio"' 2>/dev/null || echo "")
	if [[ "$windows" == "0" ]]; then
		pkill -9 -x RobloxStudio 2>/dev/null || true
		sleep 2
	fi
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

# Studio can't open a window or play while the Mac is locked, so fail fast instead of retrying.
if [[ "$(ioreg -n Root -d1)" == *'"IOConsoleLocked" = Yes'* ]]; then
	echo "PLAYTEST screen is locked; unlock the Mac and run again"
	exit 1
fi

# Look for the test window among Studio's own windows: Studio may open behind whatever app is in use.
# Studio pulls itself to the front while it starts (sometimes more than once), so remember the
# owner's app and hand focus back whenever Studio has taken it.
owner_app=$(osascript -e 'tell application "System Events" to get name of first process whose frontmost is true' 2>/dev/null || true)
give_back_focus() {
	local front
	front=$(osascript -e 'tell application "System Events" to get name of first process whose frontmost is true' 2>/dev/null || true)
	if [[ "$front" == "RobloxStudio" && -n "$owner_app" && "$owner_app" != "RobloxStudio" ]]; then
		osascript -e "tell application \"System Events\" to set frontmost of process \"$owner_app\" to true" 2>/dev/null || true
	fi
}
open -g -a RobloxStudio "$PLACE"
found=""
for _ in $(seq 1 90); do
	names=$(osascript -e 'tell application "System Events" to if exists process "RobloxStudio" then get name of every window of process "RobloxStudio"' 2>/dev/null || true)
	[[ "$names" == *playtest.rbxl* ]] && found=1 && break
	sleep 2
done
give_back_focus
[[ -n "$found" ]] || { echo "PLAYTEST Studio window never came up"; close_window; exit 1; }

# Press Play through Studio's menu (Test → Start Test Session → Test). A menu click goes to Studio
# even in the background, so the owner's keyboard and front app are never touched. Retry if no test
# output shows up (Studio may still have been loading).
PLAY_ITEM='menu item "Test" of menu 1 of menu item "Start Test Session" of menu 1 of menu bar item "Test" of menu bar 1'
started=0
for attempt in 1 2 3; do
	sleep 5
	osascript -e "tell application \"System Events\" to tell process \"RobloxStudio\" to click $PLAY_ITEM" >/dev/null 2>&1 || true
	give_back_focus
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
