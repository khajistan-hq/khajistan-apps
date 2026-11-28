#!/bin/sh
# Which tap an audio file gets (SignalTap.tapsBeforeEffects), with real files: an AAC file made by
# afconvert, and an mp3 made by ffmpeg when ffmpeg is installed (SKIP without it). Runs on the Mac.
set -eu
cd "$(dirname "$0")/.."
out=$(mktemp -d "${TMPDIR:-/tmp}/kj-signal-tap.XXXXXX")
trap 'rm -rf "$out"' EXIT HUP INT TERM
swiftc -swift-version 5 -parse-as-library KhajistanTV/Player/SignalTap.swift Tests/SignalTapTests/main.swift -o "$out/signal-tap-tests"
# One second of a 440 Hz tone, 44.1 kHz mono 16-bit.
python3 - "$out/tone.wav" <<'PY'
import math, struct, sys, wave
with wave.open(sys.argv[1], "wb") as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(44100)
    w.writeframes(b"".join(struct.pack("<h", int(12000 * math.sin(2 * math.pi * 440 * i / 44100))) for i in range(44100)))
PY
afconvert -f m4af -d aac "$out/tone.wav" "$out/tone.m4a"
if command -v ffmpeg >/dev/null 2>&1; then
    ffmpeg -loglevel error -y -i "$out/tone.wav" -b:a 64k "$out/tone.mp3"
    KJ_TAP_MP3="$out/tone.mp3" KJ_TAP_AAC="$out/tone.m4a" "$out/signal-tap-tests"
else
    KJ_TAP_AAC="$out/tone.m4a" "$out/signal-tap-tests"
fi
