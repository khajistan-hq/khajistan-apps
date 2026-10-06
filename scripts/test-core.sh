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
# These files are the Apple TV app's own (tvos/KhajistanTV/...), linked here so the two apps
# compile ONE copy. A copy in place of a link is how they drifted apart before (2026-10-06), so
# the check refuses to run the tests if any link has been replaced by a file.
SHARED="Core/Auth Core/Mixes Core/PicsVids Core/Programming Core/Receiver Core/RegionMap
Core/StationClock Core/Transmission Services/MixesStore Services/PicsVidsStore Player/PlayerLayerView"
for f in $SHARED; do
    if [ ! -L "Khajistan/$f.swift" ] || [ ! -f "Khajistan/$f.swift" ]; then
        echo "FAIL shared file Khajistan/$f.swift is not a working link to tvos/KhajistanTV/$f.swift" >&2
        exit 1
    fi
done
ARCHIVE=${KJ_ARCHIVE:-$(cd ../../../archive 2>/dev/null && pwd || echo /nonexistent)}
swiftc -swift-version 5 Khajistan/Core/*.swift Tests/KhajistanCoreTests/ArchiveCoreTests.swift -o .build/verify-core
.build/verify-core Tests/Fixtures/sky-fixture.json
swiftc -swift-version 5 Khajistan/Core/*.swift Tests/PortedCoreTests/main.swift -o .build/ported-core
.build/ported-core Tests/Fixtures/station-clock-fixture.json "$ARCHIVE"
