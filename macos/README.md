# Khajistan for Mac

The Mac app uses Mac Catalyst and the same native SwiftUI Receiver, caption and account implementation as iPhone/iPad. It is a real macOS app bundle, with a resizable window, keyboard shortcuts Cmd1–4, and sandboxed network/file access. It does not require an iPhone simulator.

Build from the repository root after regenerating the project:

```sh
python3 ios/scripts/generate-project.py
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project ios/Khajistan.xcodeproj -scheme Khajistan -configuration Debug -destination 'platform=macOS,variant=Mac Catalyst' -derivedDataPath macos/.ci/DerivedData CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES build
```

The local application is macos/.ci/DerivedData/Build/Products/Debug-maccatalyst/Khajistan.app. Local ad-hoc signing is for development on this Mac; App Store/TestFlight distribution needs the activated paid Apple team and distribution signing. Do not describe a local development app as notarized or distributed.
