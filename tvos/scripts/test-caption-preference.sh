#!/bin/sh
# Actual tvOS caption lifecycle with synthetic auth, player and in-memory networking.
set -eu
cd "$(dirname "$0")/../.."
output_dir=$(mktemp -d "${TMPDIR:-/tmp}/kj-caption-preference.XXXXXX")
trap 'rm -rf "$output_dir"' EXIT HUP INT TERM
printf 'import Foundation\n' > "$output_dir/UIKit.swift"
swiftc -emit-module -module-name UIKit "$output_dir/UIKit.swift" -emit-module-path "$output_dir/UIKit.swiftmodule"
swiftc -swift-version 5 -parse-as-library -I "$output_dir" \
    tvos/KhajistanTV/Core/Config.swift tvos/KhajistanTV/Core/Sky.swift \
    tvos/KhajistanTV/Core/Receiver.swift tvos/KhajistanTV/Core/Captions.swift \
    tvos/KhajistanTV/Services/LiveCaptionSession.swift \
    tvos/Tests/CaptionPreferenceTests/Harness.swift -o "$output_dir/tests"
"$output_dir/tests"
