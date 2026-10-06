import Foundation

/// What an App Store build leaves out. Owner ruling 2026-10-06: Pics/Vids stays out of the store
/// apps, because part of it comes from a social-media corpus that has never been screened for
/// adult material (App Review Guideline 1.1.4). The website keeps everything.
///
/// Off in every build made for our own devices. The App Store archive turns it on:
///   xcodebuild archive ... SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) KJ_APP_STORE'
enum StoreBuild {
#if KJ_APP_STORE
    static let isOn = true
#else
    static let isOn = false
#endif

    /// Whether a room the app draws itself is in this build. Website rooms (nil) always are.
    static func includes(_ room: NativeRoom?) -> Bool {
        !(isOn && room == .picsVids)
    }
}

extension AppTab {
    /// The tabs this build shows, in the bar's order.
    static var available: [AppTab] {
        allCases.filter { tab in
            switch tab {
            case .picsVids: return StoreBuild.includes(.picsVids)
            default: return true
            }
        }
    }
}

extension ArchiveDestination {
    /// The website's menu as this build shows it: a room left out of the build is not offered,
    /// and a door left with no rooms is not drawn.
    static var doorsInThisBuild: [(door: String, rooms: [ArchiveDestination])] {
        doors.map { ($0.door, $0.rooms.filter { StoreBuild.includes($0.nativeRoom) }) }
            .filter { !$0.rooms.isEmpty }
    }
}
