import CoreGraphics
import Foundation

/// The Top Shelf's pictures (DESIGN.md, Top Shelf). The static banner is drawn once, on the Mac,
/// by scripts/make-top-shelf.sh; the carousel slides are drawn by the extension from live data.
/// Every word on them is the website's own or a figure read from a feed.
enum ShelfArt {
    // MARK: The static banner

    /// The masthead on the day ground: the pigeon, KHAJISTAN set as the app's wordmark, and the
    /// website's line under it. tvOS shows a wide image 784 points high across the screen's 1920,
    /// so about 280 points of a 2320-point image are cut off each side; the group is centred and
    /// sized to clear that.
    static func banner(width: CGFloat, height: CGFloat, scale: CGFloat, pigeon: CGImage) -> ShelfCanvas? {
        let skin = Skin.day
        guard let c = ShelfCanvas(width: width, height: height, scale: scale, ground: skin.groundHex) else { return nil }
        let size: CGFloat = 170, em: CGFloat = -0.03
        let word = ShelfCanvas.width(of: ShelfCanvas.line("KHAJISTAN", size: size, weight: .black, em: em, hex: 0))
        let bird: CGFloat = 460, gap: CGFloat = 32
        let left = (width - (bird + gap + word)) / 2
        c.draw(pigeon, fitting: CGRect(x: left, y: (height - bird) / 2 - 20, width: bird, height: bird))
        c.text("KHAJISTAN", size: size, weight: .black, em: em, hex: skin.inkHex, x: left + bird + gap, top: 240)
        c.text("MEDIA OF THE MIDDLE WORLD", size: 32, weight: .black, em: 0.13, hex: skin.accentHex,
               x: left + bird + gap + 7, top: 418)
        return c
    }

    // MARK: Carousel slides

    /// tvOS draws a carousel slide full screen. The app row covers it from 784 points down, and
    /// with the carousel opened its Play and More Info buttons sit bottom centre and its previous
    /// and next arrows sit at mid-height within 180 points of each side, so everything here stays
    /// above 740 and between 200 and 1720. The clock sits top right.
    static let slideSize = CGSize(width: 1920, height: 1080)
    private static let margin: CGFloat = 200

    private static func slide(_ skin: Skin, _ scale: CGFloat) -> ShelfCanvas? {
        ShelfCanvas(width: slideSize.width, height: slideSize.height, scale: scale, ground: skin.groundHex)
    }

    /// DESIGN.md's faint: ink at 62%, 85% or 95%.
    private static func faint(_ skin: Skin) -> CGFloat {
        switch skin {
        case .day: return 0.62
        case .grove: return 0.85
        case .smut: return 0.95
        }
    }

    /// The receiver: the live count and the website's sentence at left, the map at right.
    static func receiver(skin: Skin, scale: CGFloat, map: ComposedMap, live: Int) -> ShelfCanvas? {
        guard let c = slide(skin, scale) else { return nil }
        c.map(map, in: CGRect(x: 780, y: 140, width: 940, height: 600), skin: skin)
        c.text("KHAJISTAN RECEIVER", size: 26, weight: .black, em: 0.13, hex: skin.accentHex, x: margin, top: 170)
        c.text(live.formatted(), size: 220, weight: .black, em: -0.05, hex: skin.inkHex, x: margin - 10, top: 230, maxWidth: 540)
        c.text("LIVE NOW", size: 26, weight: .black, em: 0.13, hex: skin.accentHex, x: margin, top: 480)
        c.paragraph("Live television, live radio and public cameras from the Middle World.", size: 34, weight: .regular,
                    hex: skin.inkHex, x: margin, top: 540, width: 520)
        return c
    }

    /// One transmission channel: what the clock has on it, or that it is off air and when it
    /// returns. The pigeon stands at right.
    static func channel(skin: Skin, scale: CGFloat, number: Int, air: OnAir?, returns: String?, line: String?,
                        pigeon: CGImage?) -> ShelfCanvas? {
        guard let c = slide(skin, scale) else { return nil }
        let width: CGFloat = 900
        if let pigeon { c.draw(pigeon, fitting: CGRect(x: 1140, y: 120, width: 580, height: 580)) }
        c.text("KHAJISTAN TRANSMISSION \u{00B7} CHANNEL \(number)", size: 26, weight: .black, em: 0.13,
               hex: skin.accentHex, x: margin, top: 170, maxWidth: width)
        guard let air else {
            c.text("OFF AIR", size: 150, weight: .black, em: -0.075, hex: skin.inkHex, x: margin - 8, top: 260)
            var y: CGFloat = 470
            if let returns, !returns.isEmpty {
                y = c.text("Returns at \(returns) \(StationClock.tzLabel)", size: 40, weight: .black, em: -0.03,
                           hex: skin.inkHex, x: margin, top: y, maxWidth: width).maxY + 36
            }
            if let line, !line.isEmpty {
                c.paragraph(line, size: 30, weight: .regular, hex: skin.inkHex, alpha: faint(skin), x: margin, top: y,
                            width: width, maxLines: 3)
            }
            return c
        }
        c.text("\u{25CF} ON AIR  \(air.startLabel)\u{2013}\(air.endLabel) \(StationClock.tzLabel)", size: 26,
               weight: .black, em: 0.13, hex: skin.inkHex, x: margin, top: 220, maxWidth: width)
        let show = air.show?.name ?? ""
        var y: CGFloat = 290
        if !show.isEmpty {
            y = c.paragraph(show.uppercased(), size: 110, weight: .black, em: -0.055, hex: skin.inkHex, x: margin - 6,
                            top: y, width: width, leading: 0.95, maxLines: 2) + 40
        }
        if let title = air.programme?.title, !title.isEmpty, title != show {
            y = c.paragraph(title, size: 40, weight: .black, em: -0.03, hex: skin.inkHex, x: margin, top: y,
                            width: width, maxLines: 2) + 30
        }
        if let showLine = air.show?.line, !showLine.isEmpty {
            y = c.paragraph(showLine, size: 30, weight: .regular, hex: skin.inkHex, alpha: faint(skin), x: margin, top: y,
                            width: width, maxLines: 2) + 36
        }
        if let next = air.nextShow?.name, !next.isEmpty, let at = air.nextStart, y < 700 {
            c.text("UP NEXT  \(at)  \(next.uppercased())", size: 26, weight: .black, em: 0.13, hex: skin.accentHex,
                   x: margin, top: y, maxWidth: width)
        }
        return c
    }

    /// Khajistan Transmission without its schedule (it is behind the preview password until
    /// launch): the website's own description of the station, and the pigeon.
    static func transmission(skin: Skin, scale: CGFloat, pigeon: CGImage?) -> ShelfCanvas? {
        guard let c = slide(skin, scale) else { return nil }
        if let pigeon { c.draw(pigeon, fitting: CGRect(x: 1140, y: 120, width: 580, height: 580)) }
        c.text("KHAJISTAN TRANSMISSION", size: 26, weight: .black, em: 0.13, hex: skin.accentHex, x: margin, top: 170)
        let y = c.paragraph("TWO SCHEDULED CHANNELS", size: 110, weight: .black, em: -0.055, hex: skin.inkHex,
                            x: margin - 6, top: 240, width: 900, leading: 0.95, maxLines: 2) + 40
        c.paragraph("The ripped media on Channel\u{00A0}1, sound only on Channel\u{00A0}2, with the archive record behind every programme.",
                    size: 34, weight: .regular, hex: skin.inkHex, x: margin, top: y, width: 820, maxLines: 3)
        return c
    }
}
