#!/bin/sh
# Real AuthStore + AuthAPI, synthetic URLProtocol and process-local persistence only.
set -eu
cd "$(dirname "$0")/.."
OUTPUT_DIR=${KJ_AUTH_TEST_OUTPUT:-/tmp/khajistan-auth-lifecycle}
mkdir -p "$OUTPUT_DIR"
for platform in ios tvos; do
    if [ "$platform" = ios ]; then auth=Khajistan/Services/AuthStore.swift
    else auth=../tvos/KhajistanTV/Services/AuthStore.swift; fi
    swiftc -swift-version 5 -parse-as-library -module-cache-path "$OUTPUT_DIR/modules" \
        Khajistan/Core/*.swift "$auth" Tests/AuthLifecycle/Stubs.swift Tests/AuthLifecycle/Runner.swift \
        -o "$OUTPUT_DIR/$platform"
    "$OUTPUT_DIR/$platform"
done
