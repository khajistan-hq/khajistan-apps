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

## App Privacy preparation — not final declarations

**The old two-category disclosure was incomplete. Do not reuse it for submission.**
The October 13 source audit found collection through native features and first-party embedded
archive pages. App Store Connect privacy answers and bundled manifests must be reconciled.

| Data | iOS / Mac evidence | Purpose and linkage supported by current audit |
|---|---|---|
| Email address | Sign-in and submitted contact information | App functionality; account/contact linked |
| User ID | Account saves and caption demand | App functionality; account linked |
| Device ID | Persistent caption viewer installation identifier | App functionality; account linked during caption use |
| Product interaction | Caption channel, mode, language and activity records | App functionality; account linked |
| Other user content | Saved items and submitted descriptions/provenance/consent | App functionality; linked when signed in or contact supplied |
| Name | Material-submission signature | App functionality; submitted contact linked |
| Photos or videos | Explicit archive-material uploads | App functionality; submitted contact linked |
| Audio data | Explicit archive-material uploads | App functionality; submitted contact linked |
| Customer support | Inquiries and supplied contact information | App functionality; linked when contact supplied |
| Purchase history | Account orders, memberships and film entitlements | App functionality; account linked |

TV's audited core categories are Email, User ID, Device ID, Other User Content and Product
Interaction. Confirm its actual purchase-related data before adding or excluding Purchase
History. Top Shelf has its own manifest; do not copy full-app collection into it blindly.

The bundled iOS/TV app manifests currently declare four categories, not this full set.
Their current no-tracking flags are not evidence that every embedded service or broadcaster
has been checked. Retention, IP/user-agent classification, third-party processing and tracking
answers remain unresolved. Local-only settings/history/downloads alone are not collection.
Optional caption processing does not activate the viewer's microphone.

Apple's definition concerns off-device data accessible beyond servicing the request in real
time. Optional submissions are exempt only if every optional-disclosure criterion is met;
we have not established that exemption. See the [official privacy instructions](https://developer.apple.com/app-store/app-privacy-details/).

- **Privacy policy URL:** `https://khajistan-archive.pages.dev/privacy`. The policy needs the
  optional-caption metering exception and Mac coverage; a reachable URL is not proof of accuracy.
- **Draft state recorded October 13:** ten categories saved unpublished for iOS/Mac; purpose,
  linkage and tracking setup incomplete. TV draft not prepared. Recheck live form before editing.
- **Export compliance:** existing app metadata uses `ITSAppUsesNonExemptEncryption = NO`;
  confirm the uploaded build rather than infer from this checklist.

Detailed evidence and remaining questions are owner-local:
`/Users/home/CZURImages/filmart/reports/app-distribution-20261013/PUBLIC_RELEASE_PRIVACY_AGE_REVIEW.md`.

## App Review Information

A demo account and, until launch, the preview password. Both are typed into App Store Connect
by the owner and are never written in this repo.

Related: `ios/TESTFLIGHT.md`, `tvos/STORE.md`.
