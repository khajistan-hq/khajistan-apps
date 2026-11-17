import CoreGraphics

/// Where the house caption plate sits on a frame drawn for the picture-in-picture window.
///
/// Full screen, CaptionView sets the type at 2.7% of 1920. The corner window shows the frame at
/// about a third of that width, where 2.7% is a 13-pixel line nobody reads from a sofa, so the
/// type is sized for the window: 30 window pixels, kept between 4% and 9% of the frame. The plate
/// is the site's one opaque plate: 0.4 em at the sides, 0.12 em above and below, centred, its foot
/// 5% of the frame above the bottom edge. Lines wrap inside 88% of the frame (6% each side, as
/// the site's plate keeps).
enum PiPCaptionLayout {
    /// Type height the window should show, in window pixels.
    static let windowTypePixels: CGFloat = 30
    static let minShare: CGFloat = 0.04
    static let maxShare: CGFloat = 0.09
    /// Used until tvOS reports the window's size.
    static let defaultShare: CGFloat = 0.055

    /// The font size, in frame pixels, for a frame `frameWidth` wide shown in a window
    /// `windowWidth` pixels wide (0 while unknown).
    static func fontSize(frameWidth: CGFloat, windowWidth: CGFloat) -> CGFloat {
        guard frameWidth > 0 else { return 0 }
        guard windowWidth > 0 else { return (frameWidth * defaultShare).rounded() }
        let wanted = windowTypePixels * frameWidth / windowWidth
        return min(max(wanted, frameWidth * minShare), frameWidth * maxShare).rounded()
    }

    /// The widest a line may run before it wraps.
    static func textWidth(frameWidth: CGFloat) -> CGFloat { frameWidth * 0.88 }

    /// Space between lines, as CaptionView's VStack spacing.
    static func lineSpacing(fontSize: CGFloat) -> CGFloat { fontSize * 0.25 }

    /// The plate around a block of text `text` in size, in a frame of `frame` size, origin at the
    /// top left, and the rect the text is drawn in.
    static func plate(text: CGSize, fontSize: CGFloat, frame: CGSize) -> (plate: CGRect, textRect: CGRect) {
        let padX = fontSize * 0.4, padY = fontSize * 0.12
        let width = min(text.width + padX * 2, frame.width)
        let height = text.height + padY * 2
        let foot = frame.height * 0.95
        let plate = CGRect(x: ((frame.width - width) / 2).rounded(), y: (foot - height).rounded(),
                           width: width.rounded(), height: height.rounded())
        let textRect = CGRect(x: (frame.width - text.width) / 2, y: plate.minY + padY, width: text.width, height: text.height)
        return (plate, textRect)
    }
}
