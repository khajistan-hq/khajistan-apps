#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
output_dir=$(mktemp -d "${TMPDIR:-/tmp}/kj-reading-cache.XXXXXX")
trap 'rm -rf "$output_dir"' EXIT HUP INT TERM
export KJ_READING_TEST_CACHE="$output_dir/cache"
mkdir -p "$KJ_READING_TEST_CACHE"
# macOS harness replaces only UIKit's import and the cache location. Business logic is unchanged.
python3 - "${KJ_READING_STORE_SOURCE:-tvos/KhajistanTV/Services/ReadingStore.swift}" "$output_dir/ReadingStore.swift" <<'PY'
import pathlib, sys
source = pathlib.Path(sys.argv[1]).read_text()
source = source.replace('import UIKit\n', '')
source = source.replace('FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]',
                        'URL(fileURLWithPath: ProcessInfo.processInfo.environment["KJ_READING_TEST_CACHE"]!)')
pathlib.Path(sys.argv[2]).write_text(source)
PY
baseline_flag=
if [ "${KJ_READING_BASELINE:-0}" = 1 ]; then baseline_flag=-DKJ_READING_BASELINE; fi
swiftc -swift-version 5 -parse-as-library $baseline_flag \
  tvos/KhajistanTV/Core/Config.swift tvos/KhajistanTV/Core/ReadingRoom.swift \
  "$output_dir/ReadingStore.swift" tvos/Tests/ReadingCacheTests/Harness.swift -o "$output_dir/reading-tests"
"$output_dir/reading-tests"
