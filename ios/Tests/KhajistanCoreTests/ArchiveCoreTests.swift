import Foundation

func exactOriginsAndDeepLinks() throws {
    for value in ["https://khajistan-archive.pages.dev/canvas", "https://archive.khajistan.com/read.html?id=12"] {
        try expect(ArchiveURL.isArchive(try require(URL(string: value))))
    }
    for value in ["http://khajistan-archive.pages.dev", "https://khajistan-archive.pages.dev.evil.org", "https://user:pass@khajistan-archive.pages.dev", "https://khajistan-archive.pages.dev:8080", "javascript:alert(1)", "file:///etc/passwd"] {
        try expect(!ArchiveURL.isArchive(try require(URL(string: value))))
    }
    let encoded = URL(string: "khajistan://open?url=https%3A%2F%2Fkhajistan-archive.pages.dev%2Fread.html%3Fid%3D42")!
    try expect(ArchiveURL.deepLink(encoded)?.query == "id=42")
    try expect(ArchiveURL.deepLink(URL(string: "khajistan://open?url=https://example.com")!) == nil)
}

func searchPreservesUrduAndDelimiters() throws {
    let input = "خجستان & cinema #1 + posters"
    let url = try require(ArchiveURL.search(input))
    let query = try require(URLComponents(url: url, resolvingAgainstBaseURL: false))
    try expect(query.queryItems == [URLQueryItem(name: "q", value: input)])
    try expect(query.fragment == nil)
    try expect(ArchiveURL.search(" \n ") == nil)
}

func privatePagesNeverEnterLibrary() throws {
    var state = LibraryState()
    for path in ["/dashboard.html", "/gate?next=/", "/read.html?access_token=abc", "/read.html#refresh_token=abc", "/auth/callback?code=abc", "/downloads.html", "/?api_key=example", "/?session=example", "/?auth=example", "/?jwt=example", "/?next=https://example.com/?token=secret", "/./dashboard.html", "/x/../dashboard.html"] {
        let url = URL(string: path, relativeTo: ArchiveURL.base)!.absoluteURL
        state.visit(url, title: "Private")
        state.toggleBookmark(url, title: "Private")
    }
    try expect(state.bookmarks.isEmpty)
    try expect(state.history.isEmpty)
}

func historyDeduplicatesAndHasBoundedSize() throws {
    var state = LibraryState()
    for n in 0..<120 { state.visit(ArchiveURL.base.appendingPathComponent("item/\(n)"), title: "Item \(n)") }
    try expect(state.history.count == 100)
    let url = ArchiveURL.base.appendingPathComponent("item/50")
    state.visit(url, title: "Updated")
    try expect(state.history.count == 100)
    try expect(state.history.first?.title == "Updated")
    try expect(state.history.filter { $0.url == url }.count == 1)
    state.toggleBookmark(url, title: "Keep me")
    try expect(state.bookmarks.count == 1)
    state.toggleBookmark(url, title: "Keep me")
    try expect(state.bookmarks.isEmpty)
}

func libraryRoundTripAndCorruptFile() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = LibraryFile(url: directory.appendingPathComponent("library.json"))
    try expect(try file.read() == LibraryState())
    var state = LibraryState()
    state.toggleBookmark(ArchiveURL.base, title: "خجستان")
    try file.write(state)
    try expect(try file.read() == state)
    try Data("bad json".utf8).write(to: file.url)
    var corruptRejected = false
    do { _ = try file.read() } catch { corruptRejected = true }
    try expect(corruptRejected)
    try expect(try String(contentsOf: file.url, encoding: .utf8) == "bad json")
}

func downloadNamesCannotTraverseDirectories() throws {
    try expect(DownloadName.safe("../../secret.pdf") == "secret.pdf")
    try expect(DownloadName.safe("C:\\private\\book.pdf") == "book.pdf")
    try expect(DownloadName.safe("..") == "download")
    try expect(DownloadName.safe(".env") == "download")
    try expect(DownloadName.safe("\n") == "download")
    try expect(DownloadName.safe("book\u{0000}.pdf") == "book.pdf")
    try expect(DownloadName.safe("رسالہ.pdf") == "رسالہ.pdf")
    let longName = DownloadName.safe(String(repeating: "😀", count: 180) + ".pdf")
    try expect(longName.utf8.count <= 220)
    try expect(longName.hasSuffix(".pdf"))
}

// MARK: - Sky (the website's KJSky, differential)

private struct SkyFixture: Decodable {
    struct Case: Decodable { let zone: String; let ms: Double; let theme: String; let elevation: Double? }
    let zones: Int
    let aliases: Int
    let cases: [Case]
}

private func skyFixture() throws -> SkyFixture {
    let path = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Tests/Fixtures/sky-fixture.json"
    return try JSONDecoder().decode(SkyFixture.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
}

/// Mismatches between the Swift sky and the site's answers, `shift` seconds off the fixture's instant.
private func skyMismatches(_ fixture: SkyFixture, shift: TimeInterval = 0) throws -> [String] {
    var found: [String] = []
    for c in fixture.cases {
        let zone = try require(TimeZone(identifier: c.zone))
        let date = Date(timeIntervalSince1970: c.ms / 1000 + shift)
        let theme = Sky.theme(at: date, timeZone: zone)
        if theme.rawValue != c.theme { found.append("\(c.zone) @\(c.ms): \(theme.rawValue) vs \(c.theme)") }
        if let expected = c.elevation {
            let place = try require(Sky.position(zone: c.zone))
            let e = Sky.elevation(at: date, lat: place.lat, lon: place.lon)
            if abs(e - expected) > 1e-9 { found.append("\(c.zone) @\(c.ms): elevation \(e) vs \(expected)") }
        } else if Sky.position(zone: c.zone) != nil {
            found.append("\(c.zone): placed here, unplaced on the site")
        }
    }
    return found
}

func skyMatchesTheSitesJS() throws {
    let fixture = try skyFixture()
    // Every zone and rename the site carries, at sixteen instants, plus three it does not carry.
    try expect(fixture.zones > 400 && fixture.aliases > 10 && fixture.cases.count == (fixture.zones + fixture.aliases + 3) * 16)
    try expect(Set(fixture.cases.map(\.theme)) == ["day", "grove", "smut"])
    let found = try skyMismatches(fixture)
    if !found.isEmpty { throw AssertionFailure(description: "\(found.count) mismatches, first: \(found.prefix(3))") }
}

func skyComparatorCanFail() throws {
    // Six hours off the site's instants must disagree often, or the comparison above proves nothing.
    try expect(try skyMismatches(try skyFixture(), shift: 6 * 3600).count > 1000)
}

func skyPickHoldsOnlyInItsBand() throws {
    let karachi = try require(TimeZone(identifier: "Asia/Karachi"))
    let noon = Date(timeIntervalSince1970: 1_791_190_800)  // 2026-10-05 14:00 PKT
    let midnight = noon.addingTimeInterval(12 * 3600)
    try expect(Sky.theme(at: noon, timeZone: karachi) == .day)
    try expect(Sky.theme(at: midnight, timeZone: karachi) == .grove)
    // A pick made under today's band holds; under another band it has lapsed.
    try expect(Sky.resolve(chosen: "smut", band: "day", at: noon, timeZone: karachi) == .smut)
    try expect(Sky.isHonoured(chosen: "smut", band: "day", at: noon, timeZone: karachi))
    try expect(Sky.resolve(chosen: "smut", band: "day", at: midnight, timeZone: karachi) == .grove)
    try expect(!Sky.isHonoured(chosen: "smut", band: "day", at: midnight, timeZone: karachi))
    // No band, an unknown name, the retired skins and a JS object key are never honoured.
    for (chosen, band) in [("smut", nil), ("night", "day"), ("dawn", "day"), ("toString", "day"), ("", "day")] as [(String?, String?)] {
        try expect(Sky.resolve(chosen: chosen, band: band, at: noon, timeZone: karachi) == .day)
        try expect(!Sky.isHonoured(chosen: chosen, band: band, at: noon, timeZone: karachi))
    }
    try expect(Sky.resolve(chosen: nil, band: nil, at: noon, timeZone: karachi) == .day)
    // A rename follows one hop to its zone; a zone with no area is not placed.
    try expect(Sky.position(zone: "Asia/Calcutta")! == Sky.position(zone: "Asia/Kolkata")!)
    try expect(Sky.position(zone: "UTC") == nil && Sky.position(zone: "Mars/Olympus") == nil)
}

func skyHourBandsWhereTheZoneIsNotPlaced() throws {
    let utc = try require(TimeZone(identifier: "UTC"))
    let day0 = Date(timeIntervalSince1970: 1_791_158_400)  // 2026-10-05 00:00 UTC
    let cases: [(Int, Int, Skin)] = [(4, 59, .grove), (5, 0, .smut), (7, 59, .smut), (8, 0, .day),
                                     (16, 59, .day), (17, 0, .smut), (19, 59, .smut), (20, 0, .grove)]
    for (h, m, skin) in cases {
        try expect(Sky.theme(at: day0.addingTimeInterval(Double(h * 3600 + m * 60)), timeZone: utc) == skin)
    }
}

func skyScriptForTheWebsite() throws {
    let karachi = try require(TimeZone(identifier: "Asia/Karachi"))
    let noon = Date(timeIntervalSince1970: 1_791_190_800)
    let set = Sky.webScript(chosen: "grove", band: "day", at: noon, timeZone: karachi)
    try expect(set.contains("setItem('kj:theme','grove')") && set.contains("setItem('kj:theme:band','day')"))
    // Automatic, a lapsed pick and anything that is not a skin name all clear the site's keys,
    // so nothing the app stores is ever written into the page as code.
    for (chosen, band) in [(nil, nil), ("grove", "smut"), ("x');alert(1)//", "day"), ("grove", "day');alert(1)//")] as [(String?, String?)] {
        let script = Sky.webScript(chosen: chosen, band: band, at: noon, timeZone: karachi)
        try expect(script.contains("removeItem('kj:theme')") && script.contains("removeItem('kj:theme:band')") && !script.contains("setItem"))
    }
}

// MARK: - Subscribe and the native rooms

func joinPlansOpenTheSitesCheckout() throws {
    try expect(JoinPlan.monthly.url.absoluteString == "https://khajistan-archive.pages.dev/reading-room.html?join=monthly")
    try expect(JoinPlan.annual.url.absoluteString == "https://khajistan-archive.pages.dev/reading-room.html?join=annual")
    for plan in JoinPlan.allCases {
        try expect(ArchiveURL.isArchive(plan.url))
        try expect(!ArchiveURL.isSaveable(plan.url))  // a checkout is never kept in history
    }
}

func nativeRoomsAndEveryOtherDoorIsTheWebsite() throws {
    let native = Dictionary(uniqueKeysWithValues: ArchiveDestination.all.compactMap { d in d.nativeRoom.map { (d.id, $0) } })
    try expect(native == ["receiver": .receiver, "picsnvids": .picsVids, "passport": .yours, "chat": .chat])
    for destination in ArchiveDestination.all {
        try expect(ArchiveURL.isArchive(destination.url))
    }
    try expect(ArchiveDestination.doors.map(\.door) == ["HOME", "PUBLICATIONS", "READING ROOM", "RECEIVER", "PICS/VIDS", "CHAT", "WALL", "BAZAAR", "ABOUT", "MAP"])
}

private struct AssertionFailure: Error, CustomStringConvertible {
    let description: String
}
private func expect(_ condition: @autoclosure () throws -> Bool, file: String = #fileID, line: Int = #line) throws {
    guard try condition() else { throw AssertionFailure(description: "\(file):\(line) assertion failed") }
}
private func require<T>(_ value: T?) throws -> T {
    guard let value else { throw AssertionFailure(description: "Required value was nil") }
    return value
}
@main struct CoreTestRunner {
    static func main() throws {
        let tests: [(String, () throws -> Void)] = [
            ("Exact origins and deep links", exactOriginsAndDeepLinks),
            ("Urdu and delimiter search encoding", searchPreservesUrduAndDelimiters),
            ("Private pages excluded from persistence", privatePagesNeverEnterLibrary),
            ("Bounded history and bookmark toggle", historyDeduplicatesAndHasBoundedSize),
            ("Disk round trip and corruption preservation", libraryRoundTripAndCorruptFile),
            ("Download traversal and Unicode limits", downloadNamesCannotTraverseDirectories),
            ("Sky matches the site's KJSky (differential)", skyMatchesTheSitesJS),
            ("The sky comparator can fail", skyComparatorCanFail),
            ("A skin pick holds only in its band", skyPickHoldsOnlyInItsBand),
            ("Hour bands where the zone is not placed", skyHourBandsWhereTheZoneIsNotPlaced),
            ("The skin script for the website", skyScriptForTheWebsite),
            ("Join plans open the site's checkout", joinPlansOpenTheSitesCheckout),
            ("Native rooms; every other door is the website", nativeRoomsAndEveryOtherDoorIsTheWebsite)
        ]
        for (name, run) in tests { try run(); print("PASS \(name)") }
        print("\(tests.count) tests passed")
    }
}
