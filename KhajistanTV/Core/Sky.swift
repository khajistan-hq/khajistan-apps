import Foundation

/// The three skins. Day is the sun above the horizon, Grove (green) is the night, Smut (pink)
/// is dawn and dusk. `groundHex` is the page ground and `inkHex` the foreground; `liftHex` is
/// the raised or hovered plate. Ground is never used as a text colour on its own ground.
enum Skin: String, CaseIterable, Codable, Sendable {
    case day, grove, smut

    var groundHex: UInt32 {
        switch self {
        case .day: return 0xF3FB04
        case .grove: return 0x186409
        case .smut: return 0xC11B6B
        }
    }

    var inkHex: UInt32 {
        switch self {
        case .day: return 0x000000
        case .grove: return 0xF3FB04
        case .smut: return 0xF3FB04
        }
    }

    var liftHex: UInt32 {
        switch self {
        case .day: return 0xFFFFA0
        case .grove: return 0x004A00
        case .smut: return 0x8F1350
        }
    }

    /// Hours 8 to 16 are day, 5 to 7 and 17 to 19 are smut, the rest is grove. The hour is the
    /// calendar's own, so the caller chooses whose clock it is (the viewer's, or Pakistan's).
    static func current(at date: Date, calendar: Calendar) -> Skin {
        switch calendar.component(.hour, from: date) {
        case 8...16: return .day
        case 5...7, 17...19: return .smut
        default: return .grove
        }
    }
}

/// What the viewer chose in Account: follow the hour, or hold one skin. The website's switch
/// names the three skins Day, Grove and Smut (archive/scripts/kj-theme.js, LABEL); it has no
/// name for following the sky because that is its default, so this app calls it Automatic.
enum SkinChoice: String, CaseIterable, Sendable {
    case automatic, day, grove, smut

    /// A stored value. Absent or unknown is Automatic, so a bad value can never pin a skin.
    init(stored: String?) {
        self = stored.flatMap(SkinChoice.init(rawValue:)) ?? .automatic
    }

    var label: String {
        switch self {
        case .automatic: return "Automatic"
        case .day: return "Day"
        case .grove: return "Grove"
        case .smut: return "Smut"
        }
    }

    /// The skin on screen at `date`: the hour's for Automatic, otherwise the one chosen.
    func skin(at date: Date, calendar: Calendar) -> Skin {
        switch self {
        case .automatic: return Skin.current(at: date, calendar: calendar)
        case .day: return .day
        case .grove: return .grove
        case .smut: return .smut
        }
    }
}
