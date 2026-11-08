import Foundation

/// What an App Store build leaves out. Owner rulings 2026-10-06, the website keeps everything:
/// - Pics/Vids: part of it comes from a social-media corpus that has never been screened for
///   adult material (App Review Guideline 1.1.4).
/// - Chat and the Wall: until the server has a word filter and a block for both (Guideline 1.2).
///   Our own builds carry them.
///
/// Off in every build made for our own devices. The App Store archive turns it on:
///   xcodebuild archive ... SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) KJ_APP_STORE'
enum StoreBuild {
#if KJ_APP_STORE
    static let isOn = true
#else
    static let isOn = false
#endif

    /// The TestFlight build for the Friends and Owner Preview groups carries Pics/Vids (owner,
    /// 2026-11-08, asked with the 10-06 reason in front of them: "Include it for Friends"). Set
    /// only on that archive, beside KJ_APP_STORE; an App Store submission leaves it off, and the
    /// 10-06 exclusion holds there unchanged.
#if KJ_FRIENDS
    static let carriesPicsVids = true
#else
    static let carriesPicsVids = false
#endif

    /// Whether a room the app draws itself is in this build. Website rooms (nil) always are.
    static func includes(_ room: NativeRoom?) -> Bool {
        !(isOn && room == .picsVids && !carriesPicsVids)
    }

    /// Whether a door of the website's menu is in this build.
    static func includes(_ destination: ArchiveDestination) -> Bool {
        includes(destination.nativeRoom) && !(isOn && ["chat", "wall"].contains(destination.id))
    }
}

extension ArchiveDestination {
    /// The website's menu as this build shows it: a room left out of the build is not offered,
    /// and a door left with no rooms is not drawn.
    static var doorsInThisBuild: [(door: String, rooms: [ArchiveDestination])] {
        doors.map { ($0.door, $0.rooms.filter { StoreBuild.includes($0) }) }
            .filter { !$0.rooms.isEmpty }
    }
}
