import CryptoKit
import Foundation
import TVServices

/// Fetches what the slides show, draws them into the extension's caches and makes the carousel
/// items. A slide whose data cannot be fetched is left out; nothing is drawn from a guess.
enum ShelfFeed {
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpAdditionalHeaders = ["User-Agent": KJConfig.userAgent]
        return URLSession(configuration: config)
    }()

    static func items() async -> [TVTopShelfCarouselItem] {
        let skin = Skin.current(at: Date(), calendar: .current)
        let folder = prepareFolder()
        var items: [TVTopShelfCarouselItem] = []
        if let receiver = await receiverItem(skin: skin, folder: folder) { items.append(receiver) }
        items += await transmissionItems(skin: skin, folder: folder)
        return items
    }

    // MARK: Receiver

    private static func receiverItem(skin: Skin, folder: URL) async -> TVTopShelfCarouselItem? {
        guard let index: ReceiverIndex = await fetch(KJConfig.site.appendingPathComponent("data/open-frequencies/receiver-index.json")),
              let shapes: RegionShapes = await fetch(KJConfig.site.appendingPathComponent("data/region-shapes.json")),
              let map = RegionMapRules.compose(core: shapes, extended: nil, index: index, showExtensions: false)
        else { return nil }
        let live = index.totals.live
        let item = TVTopShelfCarouselItem(identifier: "receiver")
        item.contextTitle = "Khajistan Receiver"
        item.title = "\(live.formatted()) live now"
        item.summary = "Live television, live radio and public cameras from the Middle World."
        guard draw(item, name: "receiver-\(skin.rawValue)-\(live)", folder: folder, art: { scale in
            ShelfArt.receiver(skin: skin, scale: scale, map: map, live: live)
        }) else { return nil }
        // No Play: the map is a place to choose from, not a signal.
        item.displayAction = TVTopShelfAction(url: DeepLink.receiver.url)
        return item
    }

    // MARK: Transmission

    /// Channel 1 and Channel 2 as the station clock has them now. The schedule is asked for
    /// without a password first, as the app does (after launch it is public), then with the
    /// preview password the app keeps in the keychain group it shares with this extension. With
    /// no schedule, one slide carries the website's own description of the station.
    private static func transmissionItems(skin: Skin, folder: URL) async -> [TVTopShelfCarouselItem] {
        let pigeon = Bundle.main.url(forResource: "pigeon", withExtension: "png").flatMap(ShelfCanvas.loadImage)
        let now = Date()
        let url = Transmission.scheduleURL(month: StationClock.stationMonth(now))
        var programming: Programming? = await fetch(url)
        if programming == nil, let data = Keychain.read("preview"),
           let password = String(data: data, encoding: .utf8), !password.isEmpty {
            programming = await fetch(url, authorization: Transmission.basicAuthorization(user: KJConfig.previewUser, password: password))
        }
        guard let p = programming else {
            let item = TVTopShelfCarouselItem(identifier: "transmission")
            item.contextTitle = "Khajistan Transmission"
            item.title = "Two scheduled channels"
            guard draw(item, name: "transmission-\(skin.rawValue)", folder: folder, art: { scale in
                ShelfArt.transmission(skin: skin, scale: scale, pigeon: pigeon)
            }) else { return [] }
            item.displayAction = TVTopShelfAction(url: DeepLink.transmission.url)
            return [item]
        }
        return [1, 2].compactMap { number -> TVTopShelfCarouselItem? in
            let air = StationClock.onAir(p, channel: number, at: now)
            let returns = StationClock.channelId(p, number: number).flatMap { StationClock.returnTime(p, channelId: $0, at: now) }
            let line = p._meta.channels.first { $0.number == number }?.line
            let item = TVTopShelfCarouselItem(identifier: "channel-\(number)")
            item.contextTitle = "Khajistan Transmission"
            if let air {
                let show = air.show?.name ?? ""
                item.title = "Channel \(number): " + (show.isEmpty ? (air.programme?.title ?? "on air") : show)
            } else {
                item.title = "Channel \(number): off air" + (returns.map { ", returns at \($0) \(StationClock.tzLabel)" } ?? "")
            }
            let state = air.map { "\($0.programmeId)-\($0.startLabel)" } ?? "off-\(returns ?? "")"
            guard draw(item, name: "channel-\(number)-\(skin.rawValue)-\(state)", folder: folder, art: { scale in
                ShelfArt.channel(skin: skin, scale: scale, number: number, air: air, returns: returns, line: line, pigeon: pigeon)
            }) else { return nil }
            item.playAction = TVTopShelfAction(url: DeepLink.channel(number).url)
            item.displayAction = TVTopShelfAction(url: DeepLink.transmission.url)
            return item
        }
    }

    // MARK: Drawing and fetching

    /// Draws the slide at 1x and 2x into `folder` and hands the files to the item. A file is named
    /// for its own pixels, so a picture that changes (new data, a new skin, a new layout in a new
    /// build) gets a new URL that tvOS cannot have cached, and an unchanged one keeps its URL.
    private static func draw(_ item: TVTopShelfCarouselItem, name: String, folder: URL, art: (CGFloat) -> ShelfCanvas?) -> Bool {
        let stem = String(name.unicodeScalars.prefix(24).map { CharacterSet.alphanumerics.contains($0) && $0.isASCII ? Character($0) : "-" })
        for (scale, trait) in [(CGFloat(1), TVTopShelfCarouselItem.ImageTraits.screenScale1x), (2, .screenScale2x)] {
            guard let data = art(scale)?.png() else { return false }
            let digest = SHA256.hash(data: data).prefix(8).map { String(format: "%02x", $0) }.joined()
            let url = folder.appendingPathComponent("\(stem)-\(digest)@\(Int(scale))x.png")
            if !FileManager.default.fileExists(atPath: url.path) {
                guard (try? data.write(to: url, options: .atomic)) != nil else { return false }
            }
            item.setImageURL(url, for: trait)
        }
        return true
    }

    /// The caches folder for slides, emptied of slides more than six hours old.
    private static func prepareFolder() -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let folder = base.appendingPathComponent("TopShelf", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let old = Date().addingTimeInterval(-6 * 3600)
        for file in (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [] {
            if let date = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate, date < old {
                try? FileManager.default.removeItem(at: file)
            }
        }
        return folder
    }

    private static func fetch<T: Decodable>(_ url: URL, authorization: String? = nil) async -> T? {
        var request = URLRequest(url: url)
        if let authorization { request.setValue(authorization, forHTTPHeaderField: "Authorization") }
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
