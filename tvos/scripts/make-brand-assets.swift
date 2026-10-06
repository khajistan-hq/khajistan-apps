// Draws the tvOS app icons from the pigeon mark: house yellow #F3FB04 ground, the pigeon centred at
// 72% of the canvas height, no text, no other colour. The two static Top Shelf images in the same
// .brandassets are drawn by scripts/make-top-shelf.sh, with the extension's own drawing code, and
// are left as they are here.
//
//   swift tvos/scripts/make-brand-assets.swift <pigeon.png> <Assets.xcassets directory>
//
// Rewrites the two icon image stacks and the .brandassets Contents.json inside that directory.
import Foundation
import CoreGraphics
import ImageIO

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func sRGB() -> CGColorSpace { CGColorSpace(name: CGColorSpace.sRGB)! }

func loadImage(_ url: URL) -> CGImage {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { fail("cannot read image \(url.path)") }
    return image
}

/// One bitmap at an exact pixel size. `ground` fills house yellow and makes the PNG opaque;
/// `pigeon` is drawn centred at 72% of the height. A canvas with neither stays transparent.
func render(_ width: Int, _ height: Int, ground: Bool, pigeon: CGImage?) -> CGImage {
    let alpha = ground ? CGImageAlphaInfo.noneSkipLast : CGImageAlphaInfo.premultipliedLast
    guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                              space: sRGB(), bitmapInfo: alpha.rawValue) else { fail("cannot make a \(width)x\(height) bitmap") }
    ctx.interpolationQuality = .high
    let w = CGFloat(width), h = CGFloat(height)
    if ground {
        ctx.setFillColor(CGColor(colorSpace: sRGB(), components: [243 / 255, 251 / 255, 4 / 255, 1])!)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    }
    if let pigeon {
        let ph = h * 0.72
        let pw = ph * CGFloat(pigeon.width) / CGFloat(pigeon.height)
        ctx.draw(pigeon, in: CGRect(x: (w - pw) / 2, y: (h - ph) / 2, width: pw, height: ph))
    }
    guard let image = ctx.makeImage() else { fail("cannot read back the \(width)x\(height) bitmap") }
    return image
}

func writePNG(_ image: CGImage, _ url: URL) {
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { fail("cannot write \(url.path)") }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { fail("cannot finish \(url.path)") }
}

func writeJSON(_ value: Any, _ url: URL) {
    guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) else { fail("cannot encode \(url.path)") }
    do { try (data + Data("\n".utf8)).write(to: url) } catch { fail("cannot write \(url.path): \(error)") }
}

func makeDirectory(_ url: URL) {
    do { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) } catch { fail("cannot create \(url.path): \(error)") }
}

func xcodeInfo() -> [String: Any] { ["author": "xcode", "version": 1] }

/// `<dir>/Contents.json` plus one PNG per scale. `draw` renders a canvas of the given pixel size.
func writeImageset(_ dir: URL, stem: String, size: (width: Int, height: Int), scales: [Int], draw: (Int, Int) -> CGImage) {
    makeDirectory(dir)
    var images: [[String: String]] = []
    for scale in scales {
        let file = scale == 1 ? "\(stem).png" : "\(stem)@\(scale)x.png"
        writePNG(draw(size.width * scale, size.height * scale), dir.appendingPathComponent(file))
        images.append(["filename": file, "idiom": "tv", "scale": "\(scale)x"])
    }
    writeJSON(["images": images, "info": xcodeInfo()], dir.appendingPathComponent("Contents.json"))
}

/// A two-layer image stack: Front is the pigeon on a transparent canvas, Back is solid yellow.
func writeImagestack(_ dir: URL, size: (width: Int, height: Int), scales: [Int], pigeon: CGImage) {
    makeDirectory(dir)
    let layers = [(name: "Front", ground: false), (name: "Back", ground: true)]  // top layer first
    writeJSON(["layers": layers.map { ["filename": "\($0.name).imagestacklayer"] }, "info": xcodeInfo()], dir.appendingPathComponent("Contents.json"))
    for layer in layers {
        let layerDir = dir.appendingPathComponent("\(layer.name).imagestacklayer")
        makeDirectory(layerDir)
        writeJSON(["info": xcodeInfo()], layerDir.appendingPathComponent("Contents.json"))
        writeImageset(layerDir.appendingPathComponent("Content.imageset"), stem: layer.name.lowercased(), size: size, scales: scales) { w, h in
            render(w, h, ground: layer.ground, pigeon: layer.ground ? nil : pigeon)
        }
    }
}

func run() {
    let args = CommandLine.arguments
    guard args.count == 3 else { fail("usage: swift make-brand-assets.swift <pigeon.png> <Assets.xcassets directory>") }
    let pigeon = loadImage(URL(fileURLWithPath: args[1]))
    let catalog = URL(fileURLWithPath: args[2], isDirectory: true)
    guard FileManager.default.fileExists(atPath: catalog.path) else { fail("\(catalog.path) does not exist") }
    let brand = catalog.appendingPathComponent("App Icon & Top Shelf Image.brandassets", isDirectory: true)
    makeDirectory(brand)
    for stack in ["App Icon - App Store.imagestack", "App Icon.imagestack"] {
        _ = try? FileManager.default.removeItem(at: brand.appendingPathComponent(stack))
    }

    writeImagestack(brand.appendingPathComponent("App Icon - App Store.imagestack"), size: (1280, 768), scales: [1], pigeon: pigeon)
    writeImagestack(brand.appendingPathComponent("App Icon.imagestack"), size: (400, 240), scales: [1, 2], pigeon: pigeon)
    let assets: [[String: String]] = [
        ["filename": "App Icon - App Store.imagestack", "idiom": "tv", "role": "primary-app-icon", "size": "1280x768"],
        ["filename": "App Icon.imagestack", "idiom": "tv", "role": "primary-app-icon", "size": "400x240"],
        ["filename": "Top Shelf Image Wide.imageset", "idiom": "tv", "role": "top-shelf-image-wide", "size": "2320x720"],
        ["filename": "Top Shelf Image.imageset", "idiom": "tv", "role": "top-shelf-image", "size": "1920x720"],
    ]
    writeJSON(["assets": assets, "info": xcodeInfo()], brand.appendingPathComponent("Contents.json"))
    print("Wrote \(brand.path)")
}

run()
