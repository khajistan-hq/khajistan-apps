import SwiftUI

/// A mix's card: its name, the programme block it aired in, and where it is from and in what
/// language. It lies on the Receiver's front, on the Khajistan Radio shelf.
struct MixCard: View {
    static let width: CGFloat = 440
    static let height: CGFloat = 220

    let mix: Mix

    var body: some View {
        CardPlate(width: Self.width, height: Self.height) {
            VStack(alignment: .leading, spacing: 10) {
                Kicker(mix.program_block ?? "Mixtape")
                    .lineLimit(1)
                Text(mix.name)
                    .kjName(36)
                    .lineLimit(3)
                Spacer(minLength: 0)
                let detail = [mix.place, mix.language].compactMap { $0 }.joined(separator: " \u{00B7} ")
                if !detail.isEmpty {
                    Text(detail)
                        .kjSmall(faint: true)
                        .lineLimit(1)
                }
            }
        }
    }
}
