#!/bin/sh
# Compiles KhajistanTV/Core/*.swift together with the test executable and runs it against the
# station-clock fixture. Needs only the Swift toolchain; no Xcode, no simulator.
# Regenerate the fixture first when the clock or the schedule changes:
#   node scripts/station-clock-fixture.mjs
set -eu
cd "$(dirname "$0")/.."
mkdir -p .build
swiftc -swift-version 5 KhajistanTV/Core/*.swift Tests/CoreTests/main.swift -o .build/core-tests
.build/core-tests Tests/Fixtures/station-clock-fixture.json
