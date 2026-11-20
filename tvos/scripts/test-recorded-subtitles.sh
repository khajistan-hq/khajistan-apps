#!/bin/sh
# RecordedSubtitles (the Player layer) with the real Foundation core: stored files, and one
# AVPlayerItem read from a local HLS master playlist for the PiP hand-off case.
set -eu
cd "$(dirname "$0")/.."
out=$(mktemp -d "${TMPDIR:-/tmp}/kj-recorded-subs.XXXXXX")
trap 'rm -rf "$out"' EXIT HUP INT TERM
swiftc -swift-version 5 -parse-as-library KhajistanTV/Core/*.swift KhajistanTV/Player/RecordedSubtitles.swift \
    Tests/RecordedSubtitlesTests/main.swift -o "$out/recorded-subtitles-tests"
# AVFoundation reads HLS over HTTP, so the playlist the test writes is served locally.
mkdir -p "$out/hls"
port=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])')
python3 -m http.server "$port" --bind 127.0.0.1 --directory "$out/hls" >/dev/null 2>&1 &
server=$!
trap 'kill "$server" 2>/dev/null; rm -rf "$out"' EXIT HUP INT TERM
sleep 1
KJ_HLS_DIR="$out/hls" KJ_HLS_BASE="http://127.0.0.1:$port" "$out/recorded-subtitles-tests"
