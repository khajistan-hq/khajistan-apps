# App Store checklist

The steps and fixed facts for submitting the two Khajistan apps. Uploading to TestFlight or the
App Store, and anything typed into App Store Connect, is the owner's.

## The apps

| app | bundle id | devices |
|---|---|---|
| Khajistan (iPhone and iPad) | `com.khajistan.archive` | iPhone and iPad, iOS 17+ |
| Khajistan for Apple TV | `com.khajistan.tv`, Top Shelf `com.khajistan.tv.topshelf` | Apple TV, tvOS 17+ |

## Steps

1. **Owner:** sign in to Xcode (Settings > Accounts) with the Apple Developer account.
2. **Owner:** in App Store Connect, create one app record per bundle id above.
3. Archive each app with the store flag set (below), signed with that team.
4. **Owner approves** the upload to TestFlight, then submission.

## The store build

App Store archives set one compilation condition. Builds for our own devices do not.

```sh
xcodebuild archive -project ios/Khajistan.xcodeproj -scheme Khajistan \
  -destination 'generic/platform=iOS' -archivePath build/Khajistan.xcarchive \
  SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) KJ_APP_STORE'
```

`KJ_APP_STORE` leaves the Pics/Vids section, Chat and the Wall out
(`ios/Khajistan/App/StoreBuild.swift`; the Apple TV app uses the same name).
`testPicsVidsChatAndWallAreLeftOutOfStoreBuildsOnly` checks both builds.

## Screenshots

At least one per device size, JPEG or PNG, no alpha channel.

| device | size |
|---|---|
| iPhone (Dynamic Island) | 1206 × 2622 |
| iPad 13-inch | 2064 × 2752 |
| Apple TV | 1920 × 1080 |

## App Privacy answers

| data | collected | linked | tracking | purpose |
|---|---|---|---|---|
| Email address | yes | yes | no | App functionality |
| User ID | yes | yes | no | App functionality |

Nothing else is collected. The privacy manifests carry the same: `ios/Khajistan/Resources/`,
`tvos/KhajistanTV/Resources/` and `tvos/TopShelf/`, with UserDefaults (CA92.1) and, for the
Top Shelf, file timestamps (C617.1).

- **Privacy policy URL:** `https://khajistan-archive.pages.dev/privacy`.
- **Export compliance:** standard encryption only. `ITSAppUsesNonExemptEncryption = NO` in both apps.

## App Review Information

A demo account and, until launch, the preview password. Both are typed into App Store Connect
by the owner and are never written in this repo.

Related: `ios/TESTFLIGHT.md`, `tvos/STORE.md`.
