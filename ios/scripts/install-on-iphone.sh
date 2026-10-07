#!/bin/sh
# Build Khajistan for iPhone/iPad and put it on a paired device (adapted from
# tvos/scripts/install-on-apple-tv.sh).
#
# Needs, once:
#   1. Xcode 26 or newer, opened once with its licence accepted.
#   2. An Apple ID under Xcode > Settings > Accounts. A free account signs the app for 7 days;
#      an Apple Developer Program team signs it for a year.
#   3. The Apple TV paired with this Mac: on the TV, Settings > Remotes and Devices > Remote App
#      and Devices; on the Mac, Xcode > Window > Devices and Simulators > Pair, and type the code
#      the TV shows. Both on the same network.
#
# Usage: sh tvos/scripts/install-on-apple-tv.sh            (first paired Apple TV, first team)
#        KJ_TEAM=ABCDE12345 KJ_DEVICE=<udid> sh tvos/scripts/install-on-apple-tv.sh
set -eu
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
[ -d "$DEVELOPER_DIR" ] || { echo "Xcode not found at $DEVELOPER_DIR" >&2; exit 1; }
ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK="$ROOT/.ci/device"
mkdir -p "$WORK"

TEAM="${KJ_TEAM:-}"
if [ -z "$TEAM" ]; then
  defaults export com.apple.dt.Xcode "$WORK/xcode-prefs.plist" 2>/dev/null || true
  TEAM=$(python3 - "$WORK/xcode-prefs.plist" <<'PY'
import plistlib, sys
try:
    prefs = plistlib.load(open(sys.argv[1], 'rb'))
except Exception:
    sys.exit(0)
teams = []
# Xcode 27 renamed the key; the shape is the same.
for account in (prefs.get('IDEProvisioningTeams') or prefs.get('IDEProvisioningTeamByIdentifier') or {}).values():
    for team in account or []:
        if team.get('teamID'):
            teams.append((team.get('isFreeProvisioningTeam', False), team['teamID'], team.get('teamName', '')))
teams.sort()   # a paid team first: it signs for a year
if teams:
    print(teams[0][1])
PY
)
fi
[ -n "$TEAM" ] || { echo "No signing team. Sign in under Xcode > Settings > Accounts, or set KJ_TEAM." >&2; exit 1; }

DEVICE="${KJ_DEVICE:-}"
if [ -z "$DEVICE" ]; then
  xcrun devicectl list devices --json-output "$WORK/devices.json" >/dev/null
  DEVICE=$(python3 - "$WORK/devices.json" <<'PY'
import json, sys
devices = json.load(open(sys.argv[1])).get('result', {}).get('devices', [])
for d in devices:
    hw = d.get('hardwareProperties', {})
    if hw.get('platform') == 'iOS' and d.get('connectionProperties', {}).get('pairingState') == 'paired' and hw.get('udid'):
        print(hw['udid']); break
PY
)
fi
[ -n "$DEVICE" ] || { echo "No paired iPhone or iPad. Connect it and trust this Mac, with Developer Mode on." >&2; exit 1; }

echo "Team $TEAM, device $DEVICE"
xcodebuild -project "$ROOT/Khajistan.xcodeproj" -scheme Khajistan -configuration Release \
  -destination "platform=iOS,id=$DEVICE" -derivedDataPath "$WORK/DerivedData" \
  -allowProvisioningUpdates DEVELOPMENT_TEAM="$TEAM" CODE_SIGN_STYLE=Automatic build
APP="$WORK/DerivedData/Build/Products/Release-iphoneos/Khajistan.app"
xcrun devicectl device install app --device "$DEVICE" "$APP"
xcrun devicectl device process launch --device "$DEVICE" com.khajistan.archive
echo "Khajistan is on the device."
