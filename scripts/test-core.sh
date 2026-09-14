#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p .build
swiftc -swift-version 5 Khajistan/Core/*.swift Tests/KhajistanCoreTests/ArchiveCoreTests.swift -o .build/verify-core
.build/verify-core
