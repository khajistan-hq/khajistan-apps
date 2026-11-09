#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
output_dir=$(mktemp -d "${TMPDIR:-/tmp}/kj-auth-session.XXXXXX")
trap 'rm -rf "$output_dir"' EXIT HUP INT TERM
for platform in ${KJ_AUTH_TEST_PLATFORMS:-tvos ios}; do
    if [ "$platform" = tvos ]; then service=tvos/KhajistanTV/Services/AuthStore.swift
    else service=ios/Khajistan/Services/AuthStore.swift; fi
    service=${KJ_AUTH_SERVICE_SOURCE:-$service}
    swiftc -swift-version 5 -parse-as-library tvos/KhajistanTV/Core/Config.swift \
        tvos/KhajistanTV/Core/Auth.swift tvos/KhajistanTV/Core/TVSignIn.swift \
        "$service" tvos/Tests/AuthSessionTests/Harness.swift -o "$output_dir/auth-tests"
    echo "Testing $service"
    "$output_dir/auth-tests"
done
