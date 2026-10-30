/// Whether this binary is the App Store build. Pics/Vids stays out of it (owner, 2026-10-06):
/// a third of its feed is the social-media corpus, which carries no adult marker and has never
/// been screened. Builds for our own devices keep it. Set only when archiving for the store:
/// `xcodebuild archive ... SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) KJ_APP_STORE'`,
/// the same condition the phone reads (ios/Khajistan/App/StoreBuild.swift).
enum StoreBuild {
    #if KJ_APP_STORE
    static let isOn = true
    #else
    static let isOn = false
    #endif

    static func includes(_ section: Section) -> Bool {
        // Chat too, until a server-side word filter and a room block exist (owner, 2026-10-06:
        // App Review 1.2). And the Reading Room (owner, 2026-10-29: the Apple TV store build is
        // "reciever transmission screening room account").
        !(isOn && (section == .picsvids || section == .chat || section == .reading))
    }

    /// The Rooms door holds the Screening Room alone in the App Store build: no Bazaar, Madrassa
    /// or databases (owner, 2026-10-29). The door is then the Screening Room itself.
    static var roomsAreScreeningOnly: Bool { isOn }
}

extension Section {
    /// The sections this build offers, in top-bar order.
    static var available: [Section] { allCases.filter(StoreBuild.includes) }
}
