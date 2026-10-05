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
