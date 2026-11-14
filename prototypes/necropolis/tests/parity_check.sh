#!/usr/bin/env bash
# Reduced-motion parity: the raid bot (old-sluice day1 fixture, hollow-redoubt tier-3 profile) and the
# boss bot, seed 1, run headless with and without --reduced-motion; the result lines must be identical.
# Usage: tests/parity_check.sh   (exit 0 = identical, 1 = a difference, 2 = a run printed no result)
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT=(godot --headless --audio-driver Dummy --fixed-fps 60 --disable-vsync --max-fps 0 --path "$DIR")
fail=0

# run <scene> <result-grep> <args...>: print the result lines of one headless run
run() {
	local scene="$1" pat="$2"; shift 2
	timeout 300 "${GODOT[@]}" "$scene" -- "$@" 2>&1 | grep -E "$pat" || true
}

check() {
	local name="$1" scene="$2" pat="$3"; shift 3
	local a b
	a="$(run "$scene" "$pat" "$@")"
	b="$(run "$scene" "$pat" "$@" --reduced-motion)"
	if [[ -z "$a" || -z "$b" ]]; then
		echo "PARITY $name: no result line (normal=${#a} chars, reduced=${#b} chars)"
		fail=2
	elif [[ "$a" == "$b" ]]; then
		echo "PARITY $name: identical"
	else
		echo "PARITY $name: DIFFERENT"
		diff <(echo "$a") <(echo "$b") || true
		[[ $fail -eq 0 ]] && fail=1
	fi
}

check "raid old-sluice day1" res://scenes/raid/Raid.tscn '^(AUTOPILOT_RESULT|RAID_RESULT)' \
	--new-game --raid-fixture=day1,old-sluice --raid-autopilot=70 --raid-autopilot-seed=1
check "raid hollow-redoubt tier 3" res://scenes/raid/Raid.tscn '^(AUTOPILOT_RESULT|RAID_RESULT)' \
	--new-game --raid-profile=3 --raid-fort=hollow-redoubt --raid-autopilot=70 --raid-autopilot-seed=1
check "boss seed 1" res://scenes/boss/VeiBoss.tscn '^(BOSS_RESULT|BOSS_AUTOPLAY)' \
	--boss-autoplay=70 --boss-seed=1
exit $fail
