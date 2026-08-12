#!/usr/bin/env bash
# Runs the device tests under integration_test/ and keeps the notification
# permission granted while the run is up, which is what the reminder cases
# need and what cannot be done from inside a test.
#
#   tools/integration.sh                     # the only attached device
#   tools/integration.sh emulator-5554       # a particular one
#   tools/integration.sh emulator-5554 integration_test/learn_test.dart
#
# app_test.dart goes against signdict.org, the other two run off seeded rows.
set -euo pipefail

cd "$(dirname "$0")/.."

PACKAGE="gg.prinz.gebaerden"
device="${1:-}"
target="${2:-integration_test}"

if [[ -z "$device" ]]; then
	device=$(flutter devices --machine |
		python3 -c 'import json,sys; print(next((d["id"] for d in json.load(sys.stdin) if d["targetPlatform"].startswith(("android", "ios"))), ""))')
fi

if [[ -z "$device" ]]; then
	echo "No device. Start an emulator or plug a phone in, then check with: flutter devices"
	exit 1
fi

echo "Device $device, target $target"

# Every file in the run installs the app again and an install clears the
# permission, so granting once up front is worth nothing and the app ends up
# asking on screen. This keeps at it until the run is over. pm grant is
# idempotent and answers with 1 while the app is not on the device yet.
keep_granted() {
	local run="$1" said=

	until ! kill -0 "$run" 2>/dev/null; do
		if adb -s "$device" shell pm grant "$PACKAGE" \
			android.permission.POST_NOTIFICATIONS >/dev/null 2>&1; then
			[[ -n "$said" ]] || echo "POST_NOTIFICATIONS granted"
			said=1
		else
			said=
		fi
		sleep 1
	done
}

flutter test "$target" -d "$device" &
run=$!

# Only where adb knows the device, an iPhone has no such thing.
if command -v adb >/dev/null && adb devices | grep -q "^$device"; then
	keep_granted "$run" &
	watcher=$!
	trap 'kill "$watcher" 2> /dev/null || true' EXIT
fi

status=0
wait "$run" || status=$?

echo
echo "The permission request itself is not covered by this. That one needs an"
echo "uninstall and no grant at all: adb uninstall $PACKAGE"
exit "$status"
