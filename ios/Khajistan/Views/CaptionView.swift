import SwiftUI

/// Captions belong to the video, not the controls; hiding the chrome never hides the words.
struct ReceiverCaptionPlate: View {
    let text: String?
    let skin: Skin
    var body: some View {
        if let text, !text.isEmpty {
            VStack(spacing: 3) {
                ForEach(Array(CaptionText.lines(text).enumerated()), id: \.offset) { line in
                    Text(line.element)
                        .multilineTextAlignment(.center)
                        .environment(\.layoutDirection, CaptionText.isRightToLeft(line.element) ? .rightToLeft : .leftToRight)
                }
            }
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(Color(hex: skin.captionTextHex))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Color(hex: skin.captionPlateHex))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("receiverCaption")
            .allowsHitTesting(false)
        }
    }
}

struct ReceiverCaptionStatus: View {
    let session: LiveCaptionSession
    var body: some View {
        if !session.note.isEmpty {
            Text(session.note).kjSmall(faint: true)
                .accessibilityIdentifier("receiverCaptionStatus")
        }
    }
}
