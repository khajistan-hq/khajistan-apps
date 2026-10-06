#!/bin/sh
# Typecheck the SwiftUI layer without Xcode: as Mac Catalyst, against the real UIKit and
# SwiftUI interfaces in the Command Line Tools' macOS SDK. Catches the Core/app seam,
# labels, optionals and most API misuse before a CI run (macOS minutes bill at 10x).
#
# Two stand-ins, both only in a temporary copy of the sources:
#   - @State is a macro in the SDK whose plugin ships with Xcode, not the CLT, so it is
#     swapped for a plain property wrapper;
#   - onMoveCommand / onExitCommand / onPlayPauseCommand / focusSection / focusScope /
#     prefersDefaultFocus are tvOS-only (unavailable on iOS, hence Catalyst), so no-op
#     versions are added. Another tvOS-only SwiftUI member needs one more line here.
# It does not build for tvOS. An API that exists on iOS but not tvOS passes here; check
# those by name. The UI tests are not checked (XCTest is not in the CLT).
set -eu
HERE=$(cd "$(dirname "$0")/.." && pwd)
SRC="$HERE/KhajistanTV"
SDK=$(xcrun --show-sdk-path)
WORK=${TMPDIR:-/tmp}/khajistan-tvos-typecheck
OUT="$WORK/src"
rm -rf "$OUT"; mkdir -p "$OUT" "$WORK/module-cache"
find "$SRC" -name '*.swift' | while read -r f; do
  rel=${f#$SRC/}; mkdir -p "$OUT/$(dirname "$rel")"
  sed -E -e 's/@State([^A-Za-z]|$)/@KJShimState\1/g' -e 's/([^A-Za-z_.])State\(/\1KJShimState(/g' "$f" > "$OUT/$rel"
done
cat > "$OUT/_Shim.swift" <<'SHIM'
import SwiftUI
@propertyWrapper struct KJShimState<Value> {
    private let box: Value
    init(wrappedValue: Value) { box = wrappedValue }
    init(initialValue: Value) { box = initialValue }
    var wrappedValue: Value { get { box } nonmutating set { _ = newValue } }
    var projectedValue: Binding<Value> { Binding(get: { box }, set: { _ in }) }
}
extension KJShimState where Value: ExpressibleByNilLiteral { init() { box = nil } }
enum MoveCommandDirection: Sendable { case up, down, left, right }
extension View {
    func onMoveCommand(perform action: ((MoveCommandDirection) -> Void)?) -> some View { self }
    func onExitCommand(perform action: (() -> Void)?) -> some View { self }
    func onPlayPauseCommand(perform action: (() -> Void)?) -> some View { self }
    func focusSection() -> some View { self }
    func focusScope(_ namespace: Namespace.ID) -> some View { self }
    func prefersDefaultFocus(_ prefersDefaultFocus: Bool = true, in namespace: Namespace.ID) -> some View { self }
}
SHIM
cd "$OUT"
# The first run builds the module cache and takes a few minutes; later runs take seconds.
swiftc -typecheck -swift-version 5 -target arm64e-apple-ios17.0-macabi -sdk "$SDK" \
  -Fsystem "$SDK/System/iOSSupport/System/Library/Frameworks" -I "$SDK/System/iOSSupport/usr/lib/swift" \
  -module-name KhajistanTV -module-cache-path "$WORK/module-cache" $(find . -name '*.swift' | sort) "$@"
echo "typecheck: clean"
