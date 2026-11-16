import XCTest

/// What every remote-driven UI test needs: a kept screenshot, a pause that lets focus settle, and
/// a walk toward an element by the Siri Remote's presses.
extension XCTestCase {
    /// Existing navigation fixtures keep the map visible; autoplay has its own acceptance test.
    func kjLaunch(_ app: XCUIApplication, autoplay: Bool = false) {
        if !autoplay { app.launchArguments += ["-kjnoautoplay", "YES"] }
        app.launch()
    }

    func kjScreenshot(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func kjPause(_ seconds: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    /// From the top bar (or Surf, where focus rests at launch) to the Receiver's region strip:
    /// Down through the sidebar until a region card has focus. Since the front became two bands
    /// (2026-10-29) the strip runs under the sidebar, so the old Right off the sidebar found
    /// nothing. Never presses Select, so nothing on the way is switched.
    @discardableResult
    func kjFocusStrip(_ app: XCUIApplication) -> Bool {
        let regions = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'region-'"))
        let focused = regions.matching(NSPredicate(format: "hasFocus == true")).firstMatch
        for _ in 0..<10 where !focused.exists { XCUIRemote.shared.press(.down); kjPause(0.35) }
        return focused.exists
    }

    /// Presses toward `element` until it has focus, steering by where it sits against the focused
    /// control. Returns whether it got there.
    @discardableResult
    func kjFocus(_ element: XCUIElement, app: XCUIApplication, limit: Int = 40) -> Bool {
        for _ in 0..<limit {
            if element.exists && element.hasFocus { return true }
            let focused = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
            guard element.exists, focused.exists else {
                XCUIRemote.shared.press(.down)
                kjPause(0.4)
                continue
            }
            let target = element.frame, here = focused.frame
            let dx = target.midX - here.midX, dy = target.midY - here.midY
            // A different row first (up or down), then along the row.
            if abs(dy) > max(here.height, target.height) * 0.6 {
                XCUIRemote.shared.press(dy > 0 ? .down : .up)
            } else {
                XCUIRemote.shared.press(dx > 0 ? .right : .left)
            }
            kjPause(0.4)
        }
        return element.exists && element.hasFocus
    }
}

/// The channels one region offers on the site right now, read the way the app reads them and
/// filtered by the app's own rules (ReceiverRules.eligible): published, not switched off, not on
/// the denylist or off-air list, not graded offline or blocked by a health file under two hours
/// old, at least half the expected stream, with a stream. Tests that name a channel take it from
/// here, because channels leave the dial: 24 News HD and ABN News did, and two tests that named
/// them failed on data rather than on code.
func kjLiveChannels(region: String) -> [[String: Any]] {
    let site = "https://khajistan-archive.pages.dev"
    func json(_ path: String) -> [String: Any] {
        var request = URLRequest(url: URL(string: site + path)!)
        request.setValue("Mozilla/5.0 kj-uitest", forHTTPHeaderField: "User-Agent")
        var result: [String: Any] = [:]
        let done = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { data, response, _ in
            if (response as? HTTPURLResponse)?.statusCode == 200 {
                result = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
            }
            done.signal()
        }.resume()
        _ = done.wait(timeout: .now() + 30)
        return result
    }
    let dir = "/data/open-frequencies/"
    let files = json(dir + "receiver-index.json")["regionFiles"] as? [String: String] ?? [:]
    guard let path = files[region] else { return [] }
    var denied = Set(json(dir + "denylist.json")["disabledChannelIds"] as? [String] ?? [])
    denied.formUnion(json(dir + "off-air-suspects.json")["offAirChannelIds"] as? [String] ?? [])
    var health: [String: [String: Any]] = [:]
    let healthFile = json(dir + "health.json")
    let iso = ISO8601DateFormatter()
    iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let at = healthFile["generatedAt"] as? String,
       let written = iso.date(from: at) ?? ISO8601DateFormatter().date(from: at),
       Date().timeIntervalSince(written) <= 2 * 60 * 60 {
        for row in healthFile["results"] as? [[String: Any]] ?? [] {
            if let id = row["channelId"] as? String { health[id] = row }
        }
    }
    var seen = Set<String>()
    return (json(path)["channels"] as? [[String: Any]] ?? []).filter { channel in
        guard let id = channel["id"] as? String else { return false }
        if let published = channel["publicationStatus"] as? String, published != "published" { return false }
        if channel["manualDisabled"] as? Bool == true || denied.contains(id) { return false }
        let status = health[id]?["status"] as? String ?? channel["healthStatus"] as? String
        if status == "offline" || status == "blocked" { return false }
        if (health[id]?["deliveryRatio"] as? Double ?? 1) < 0.5 { return false }
        return channel["activeStreamId"] is String && seen.insert(id).inserted
    }
}
