#!/bin/sh
# Compiles Khajistan/Core/*.swift (Foundation only) with each test executable and runs it.
# Needs only the Swift toolchain; no Xcode, no simulator.
#   verify-core   the iPhone app's own tests, with the website's sky as a fixture
#                 (regenerate: node scripts/sky-fixture.mjs)
#   ported-core   the Apple TV app's core tests over the same ported files; the "Real ..." tests
#                 read the archive's data files from KJ_ARCHIVE (default: the filmart archive
#                 checkout beside this worktree) and SKIP when it is absent.
set -eu
cd "$(dirname "$0")/.."
mkdir -p .build
ARCHIVE=${KJ_ARCHIVE:-$(cd ../../../archive 2>/dev/null && pwd || echo /nonexistent)}
swiftc -swift-version 5 Khajistan/Core/*.swift Tests/KhajistanCoreTests/ArchiveCoreTests.swift -o .build/verify-core
.build/verify-core Tests/Fixtures/sky-fixture.json
swiftc -swift-version 5 Khajistan/Core/*.swift Tests/PortedCoreTests/main.swift -o .build/ported-core
.build/ported-core Tests/Fixtures/station-clock-fixture.json "$ARCHIVE"
