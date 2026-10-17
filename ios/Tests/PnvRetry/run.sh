#!/bin/sh
# Runs PicsVidsStore against stubbed answers, in a simulator: the region shelf must survive a 500
# from a busy server and still give up on a refusal. About fifteen seconds.
#   ios/Tests/PnvRetry/run.sh [SIMULATOR_UDID] [REPO_ROOT]
set -eu
here=$(cd "$(dirname "$0")" && pwd)
device=${1:-booted}
root=${2:-$(cd "$here/../../.." && pwd)}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
k="$root/ios/Khajistan"
xcrun --sdk iphonesimulator swiftc -parse-as-library -swift-version 5 -target arm64-apple-ios17.0-simulator \
  "$here/Harness.swift" "$k"/Core/*.swift "$k/Services/PicsVidsStore.swift" "$k/Services/AuthStore.swift" \
  "$k/Services/ReceiverStore.swift" "$k/Services/TransmissionStore.swift" "$k/Services/Keychain.swift" "$k/Player/PlayerController.swift" -o "$work/harness"
xcrun simctl spawn "$device" "$work/harness"
