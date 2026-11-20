#!/bin/sh
# RecordedSubtitles (the Player layer) with the real Foundation core: stored files, no AVPlayerItem.
set -eu
cd "$(dirname "$0")/.."
out=$(mktemp -d "${TMPDIR:-/tmp}/kj-recorded-subs.XXXXXX")
trap 'rm -rf "$out"' EXIT HUP INT TERM
swiftc -swift-version 5 -parse-as-library KhajistanTV/Core/*.swift KhajistanTV/Player/RecordedSubtitles.swift \
    Tests/RecordedSubtitlesTests/main.swift -o "$out/recorded-subtitles-tests"
"$out/recorded-subtitles-tests"
