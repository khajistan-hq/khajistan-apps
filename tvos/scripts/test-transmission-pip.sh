#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
output_dir=$(mktemp -d "${TMPDIR:-/tmp}/kj-transmission-pip.XXXXXX")
trap 'rm -rf "$output_dir"' EXIT HUP INT TERM
# Execute the production callback installer with only AVKit/UI boundaries replaced.
python3 - "$output_dir/main.swift" <<'PY'
import pathlib, sys
source = pathlib.Path('tvos/KhajistanTV/Views/TransmissionPlayerView.swift').read_text()
start = source.index('    private func startPictureInPicture() {')
end = source.index('\n    /// A line in the strip', start)
method = source[start:end].replace('private func startPictureInPicture', 'func startPictureInPicture')
# The probe is a reference type instead of a SwiftUI value with @State storage.
# Explicit capture enables the same implicit-self callback body in that context.
method = method.replace('pip.onStart = {', 'pip.onStart = { [self] in')
method = method.replace('pip.onFail = {', 'pip.onFail = { [self] in')
harness = pathlib.Path('tvos/Tests/TransmissionPiPTests/Harness.swift').read_text()
assert harness.count('// PRODUCTION_METHOD') == 1
model = pathlib.Path('tvos/KhajistanTV/App/AppModel.swift').read_text()
assert '        observeTransmissionAccess()' in model
start = model.index('    private func observeTransmissionAccess() {')
end = model.index('\n    /// A `khajistan://`', start)
observe = model[start:end].replace('private func observeTransmissionAccess', 'func observeTransmissionAccess')
start = model.index('        auth.onPreviewPasswordChange = {')
end = model.index('\n        observeTransmissionAccess()', start)
preview = model[start:end]
store = pathlib.Path('tvos/KhajistanTV/Services/TransmissionStore.swift').read_text()
start = store.index('    func accessDidChange() {')
end = store.index('\n    func stop()', start)
harness = harness.replace('// PRODUCTION_METHOD', method)
harness = harness.replace('// PRODUCTION_ACCESS_OBSERVER', observe)
harness = harness.replace('// PRODUCTION_PREVIEW_OBSERVER', preview)
harness = harness.replace('// PRODUCTION_ACCESS_INVALIDATION', store[start:end])
start = store.index('    func stop() {')
end = store.index('\n    private func tune(generation', start)
harness = harness.replace('// PRODUCTION_STOP', store[start:end])
start = store.index('    private func beginTune() -> Int {')
end = store.index('\n    private func send(', start)
harness = harness.replace('// PRODUCTION_BEGIN_TUNE', store[start:end])
start = store.index('    private func warm(channel target: Int) async {')
end = store.index('\n    /// The file ended:', start)
harness = harness.replace('// PRODUCTION_WARM', store[start:end].replace('private func warm', 'func warm'))
pathlib.Path(sys.argv[1]).write_text(harness)
PY
swiftc -swift-version 5 "$output_dir/main.swift" -o "$output_dir/pip-tests"
"$output_dir/pip-tests"
