import AppKit
// Reproducible typographic app mark in the house palette; no generated archive content.
let size = NSSize(width: 1024, height: 1024)
let bitmap = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
let context = NSGraphicsContext(cgContext: bitmap, flipped: false)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
NSColor(srgbRed: 243/255, green: 251/255, blue: 4/255, alpha: 1).setFill()
NSRect(origin: .zero, size: size).fill()
NSColor(srgbRed: 0, green: 111/255, blue: 0, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: 1024, height: 100).fill()
let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center
("K" as NSString).draw(in: NSRect(x: 60, y: 50, width: 904, height: 940), withAttributes: [.font: NSFont.systemFont(ofSize: 850, weight: .black), .foregroundColor: NSColor.black, .paragraphStyle: paragraph])
NSGraphicsContext.restoreGraphicsState()
let representation = NSBitmapImageRep(cgImage: bitmap.makeImage()!)
try representation.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
