#!/bin/sh
# Plays the app's own PlayerController against a carrier that stops sending, in a simulator.
#   ios/Tests/PlayerStall/run.sh ios|tvos [SIMULATOR_UDID] [REPO_ROOT]
# REPO_ROOT defaults to this checkout; point it at another checkout to run the same cases on
# older code. The simulator must be booted (xcrun simctl boot <udid>). Takes about two minutes.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
platform=${1:?ios or tvos}
device=${2:-booted}
root=${3:-$(cd "$here/../../.." && pwd)}
work=$(mktemp -d)
port=8788

case "$platform" in
  ios)
    sdk=iphonesimulator; target=arm64-apple-ios17.0-simulator
    files="$root/ios/Khajistan/Player/PlayerController.swift $root/ios/Khajistan/Core/Config.swift" ;;
  tvos)
    sdk=appletvsimulator; target=arm64-apple-tvos17.0-simulator
    files="$root/tvos/KhajistanTV/Player/PlayerController.swift $root/tvos/KhajistanTV/Player/LiveRadio.swift $root/tvos/KhajistanTV/Player/SignalTap.swift $root/tvos/KhajistanTV/Core/Config.swift" ;;
  *) echo "ios or tvos" >&2; exit 64 ;;
esac

# shellcheck disable=SC2086
xcrun --sdk "$sdk" swiftc -parse-as-library -swift-version 6 -target "$target" \
  "$here/Harness.swift" $files -o "$work/harness"
ffmpeg -loglevel error -y -f lavfi -i "sine=frequency=440:duration=180" -ac 1 -b:a 64k "$work/tone.mp3"
python3 "$here/server.py" "$work/tone.mp3" "$port" &
server=$!
trap 'kill "$server" 2>/dev/null; rm -rf "$work"' EXIT
sleep 1
xcrun simctl spawn "$device" "$work/harness" "http://127.0.0.1:$port"
