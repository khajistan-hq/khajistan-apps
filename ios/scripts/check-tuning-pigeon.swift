// Composite a movie frame over a ground the way AVPlayerLayer does: colour treated as premultiplied.
import AVFoundation; import AppKit
let url = URL(fileURLWithPath: CommandLine.arguments[1]); let out = CommandLine.arguments[2]; let want = Int(CommandLine.arguments[3])!
let g: (Double, Double, Double) = (0x18, 0x64, 0x09)
let asset = AVURLAsset(url: url); let sem = DispatchSemaphore(value: 0)
Task {
  let track = try! await asset.loadTracks(withMediaType: .video)[0]
  let reader = try! AVAssetReader(asset: asset)
  let o = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
  reader.add(o); reader.startReading(); var n = 0
  while let s = o.copyNextSampleBuffer() { if n == want, let pb = CMSampleBufferGetImageBuffer(s) {
    CVPixelBufferLockBaseAddress(pb, .readOnly)
    let w = CVPixelBufferGetWidth(pb), h = CVPixelBufferGetHeight(pb), bpr = CVPixelBufferGetBytesPerRow(pb)
    let p = CVPixelBufferGetBaseAddress(pb)!.assumingMemoryBound(to: UInt8.self)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: w*3, bitsPerPixel: 24)!
    let d = rep.bitmapData!
    for y in 0..<h { for x in 0..<w {
      let i = y*bpr + x*4; let a = Double(p[i+3])/255
      func c(_ v: UInt8, _ bg: Double) -> UInt8 { UInt8(min(255, Double(v) + bg*(1-a))) }
      let j = (y*w + x)*3; d[j] = c(p[i+2], g.0); d[j+1] = c(p[i+1], g.1); d[j+2] = c(p[i], g.2)
    } }
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out)); break }
    n += 1 }
  sem.signal() }
sem.wait()
