#!/bin/sh
# Real caption services + real Foundation-only core; scripted in-memory network/player.
set -eu
cd "$(dirname "$0")/../.."
output_dir=$(mktemp -d "${TMPDIR:-/tmp}/kj-caption-session.XXXXXX")
trap 'rm -rf "$output_dir"' EXIT HUP INT TERM
# UIKit is imported by the production service for platform build context; no UIKit symbol
# is used here. A local empty module allows the unchanged source to compile on macOS.
printf 'import Foundation\n' > "$output_dir/UIKit.swift"
swiftc -emit-module -module-name UIKit "$output_dir/UIKit.swift" -emit-module-path "$output_dir/UIKit.swiftmodule"
for platform in ${KJ_CAPTION_TEST_PLATFORMS:-tvos ios}; do
    if [ "$platform" = tvos ]; then service=tvos/KhajistanTV/Services/LiveCaptionSession.swift
    else service=ios/Khajistan/Services/LiveCaptionSession.swift; fi
    service=${KJ_CAPTION_SERVICE_SOURCE:-$service}
    swiftc -swift-version 5 -parse-as-library -I "$output_dir" \
        tvos/KhajistanTV/Core/Config.swift tvos/KhajistanTV/Core/Sky.swift \
        tvos/KhajistanTV/Core/Receiver.swift tvos/KhajistanTV/Core/Captions.swift \
        "$service" tvos/Tests/CaptionSessionTests/Harness.swift \
        -o "$output_dir/$platform-caption-tests"
    echo "Running actual $platform caption service"
    "$output_dir/$platform-caption-tests"
done
