// Draws the two static Top Shelf images into the asset catalog with the same code the Top Shelf
// extension draws its slides with (TopShelf/ShelfCanvas.swift, ShelfArt.swift). Run it through
// scripts/make-top-shelf.sh, which compiles it with KhajistanTV/Core.
//
//   make-top-shelf <pigeon.png> <Assets.xcassets>           the static images, 1x and 2x
//   make-top-shelf <pigeon.png> --slides <repo root> <dir>  the carousel slides, drawn from the
//                                                           archive checkout's own data files, in
//                                                           all three skins, for review
import CoreGraphics
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func write(_ canvas: ShelfCanvas?, to url: URL) {
    guard let data = canvas?.png() else { fail("cannot draw \(url.lastPathComponent)") }
    do { try data.write(to: url) } catch { fail("cannot write \(url.path): \(error)") }
    print(url.path)
}

func writeImageset(_ dir: URL, stem: String, size: (width: CGFloat, height: CGFloat), pigeon: CGImage) {
    do { try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) } catch { fail("\(error)") }
    var images: [[String: String]] = []
    for scale in [1, 2] {
        let file = scale == 1 ? "\(stem).png" : "\(stem)@\(scale)x.png"
        write(ShelfArt.banner(width: size.width, height: size.height, scale: CGFloat(scale), pigeon: pigeon), to: dir.appendingPathComponent(file))
        images.append(["filename": file, "idiom": "tv", "scale": "\(scale)x"])
    }
    let json: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
    guard let data = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) else { fail("json") }
    do { try (data + Data("\n".utf8)).write(to: dir.appendingPathComponent("Contents.json")) } catch { fail("\(error)") }
}

func decode<T: Decodable>(_ type: T.Type, _ url: URL) -> T {
    do { return try JSONDecoder().decode(type, from: Data(contentsOf: url)) } catch { fail("cannot read \(url.path): \(error)") }
}

let args = CommandLine.arguments
guard args.count >= 3, let pigeon = ShelfCanvas.loadImage(URL(fileURLWithPath: args[1])) else {
    fail("usage: make-top-shelf <pigeon.png> <Assets.xcassets> | <pigeon.png> --slides <repo root> <dir>")
}
if args[2] == "--slides", args.count == 5 {
    let repo = URL(fileURLWithPath: args[3], isDirectory: true)
    let out = URL(fileURLWithPath: args[4], isDirectory: true)
    try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    let index = decode(ReceiverIndex.self, repo.appendingPathComponent("data/open-frequencies/receiver-index.json"))
    let shapes = decode(RegionShapes.self, repo.appendingPathComponent("data/region-shapes.json"))
    guard let map = RegionMapRules.compose(core: shapes, extended: nil, index: index, showExtensions: false) else { fail("the map does not compose") }
    let now = Date()
    let schedule = repo.appendingPathComponent("data/khajistan-tv/programming-\(StationClock.stationMonth(now)).json")
    let programming = FileManager.default.fileExists(atPath: schedule.path) ? decode(Programming.self, schedule) : nil
    for skin in Skin.allCases {
        write(ShelfArt.receiver(skin: skin, scale: 1, map: map, live: index.totals.live), to: out.appendingPathComponent("receiver-\(skin.rawValue).png"))
        write(ShelfArt.transmission(skin: skin, scale: 1, pigeon: pigeon), to: out.appendingPathComponent("transmission-\(skin.rawValue).png"))
        guard let p = programming else { continue }
        for number in [1, 2] {
            let id = StationClock.channelId(p, number: number)
            write(ShelfArt.channel(skin: skin, scale: 1, number: number, air: StationClock.onAir(p, channel: number, at: now),
                                   returns: id.flatMap { StationClock.returnTime(p, channelId: $0, at: now) },
                                   line: p._meta.channels.first { $0.number == number }?.line, pigeon: pigeon),
                  to: out.appendingPathComponent("channel-\(number)-\(skin.rawValue).png"))
        }
    }
    exit(0)
}
let brand = URL(fileURLWithPath: args[2], isDirectory: true).appendingPathComponent("App Icon & Top Shelf Image.brandassets", isDirectory: true)
guard FileManager.default.fileExists(atPath: brand.path) else { fail("\(brand.path) does not exist; run make-brand-assets.swift first") }
writeImageset(brand.appendingPathComponent("Top Shelf Image Wide.imageset"), stem: "top-shelf-wide", size: (2320, 720), pigeon: pigeon)
writeImageset(brand.appendingPathComponent("Top Shelf Image.imageset"), stem: "top-shelf", size: (1920, 720), pigeon: pigeon)
