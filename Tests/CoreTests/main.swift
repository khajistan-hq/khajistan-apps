import Foundation

// Core tests for Khajistan for Apple TV. Foundation only, no XCTest: this file and
// KhajistanTV/Core/*.swift compile together with swiftc (see scripts/test-core.sh) and the
// first argument is the path to Tests/Fixtures/station-clock-fixture.json.

// MARK: - Harness

struct Failure: Error, CustomStringConvertible {
    let description: String
}

/// A test that could not run here (a data file is absent). Printed as SKIP, never as PASS.
struct Skip: Error {
    let reason: String
}

func expect(_ condition: @autoclosure () throws -> Bool, _ note: @autoclosure () -> String = "", line: Int = #line) throws {
    guard try condition() else {
        let text = note()
        throw Failure(description: "line \(line): expectation failed" + (text.isEmpty ? "" : " (\(text))"))
    }
}

func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ note: @autoclosure () -> String = "", line: Int = #line) throws {
    guard actual == expected else {
        let text = note()
        throw Failure(description: "line \(line): got \(actual), expected \(expected)" + (text.isEmpty ? "" : " (\(text))"))
    }
}

func expectClose(_ actual: Double, _ expected: Double, tolerance: Double = 1e-6, line: Int = #line) throws {
    guard abs(actual - expected) <= tolerance else {
        throw Failure(description: "line \(line): got \(actual), expected \(expected) within \(tolerance)")
    }
}

func require<T>(_ value: T?, _ note: String = "required value was nil", line: Int = #line) throws -> T {
    guard let value else { throw Failure(description: "line \(line): \(note)") }
    return value
}

func expectThrows<E: Error & Equatable>(_ expected: E, line: Int = #line, _ body: () throws -> Void) throws {
    do {
        try body()
    } catch let thrown as E {
        guard thrown == expected else { throw Failure(description: "line \(line): threw \(thrown), expected \(expected)") }
        return
    } catch {
        throw Failure(description: "line \(line): threw \(error), expected \(expected)")
    }
    throw Failure(description: "line \(line): nothing thrown, expected \(expected)")
}

func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
    try JSONDecoder().decode(type, from: Data(json.utf8))
}

func jsonObject(_ json: String) throws -> [String: Any] {
    try require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any], "not a JSON object")
}

// MARK: - Clocks and paths

guard let karachiZone = TimeZone(identifier: "Asia/Karachi") else {
    print("FATAL: this system has no Asia/Karachi time zone")
    exit(2)
}
var karachi = Calendar(identifier: .gregorian)
karachi.timeZone = karachiZone

/// An instant given as a Pakistan wall-clock reading, built by Calendar so it shares no
/// arithmetic with StationClock.
func pkt(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0, _ s: Int = 0) -> Date {
    karachi.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi, second: s)) ?? Date(timeIntervalSince1970: 0)
}

func isoString(_ year: Int, _ month: Int, _ day: Int) -> String {
    "\(year)-\(month < 10 ? "0" : "")\(month)-\(day < 10 ? "0" : "")\(day)"
}

guard CommandLine.arguments.count > 1 else {
    print("usage: core-tests <path to station-clock-fixture.json>")
    exit(2)
}
let fixtureURL = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL
/// <root>/tvos/Tests/Fixtures/<file> -> <root>
let repoRoot = fixtureURL.deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()

func realFile(_ relative: String) throws -> Data {
    let url = repoRoot.appendingPathComponent(relative)
    guard FileManager.default.fileExists(atPath: url.path) else { throw Skip(reason: "\(relative) is not in this checkout") }
    return try Data(contentsOf: url)
}

// MARK: - Skin

func skinHoursAtBoundaries() throws {
    let cases: [(hour: Int, minute: Int, skin: Skin)] = [
        (4, 59, .grove), (5, 0, .smut), (7, 59, .smut), (8, 0, .day),
        (16, 59, .day), (17, 0, .smut), (19, 59, .smut), (20, 0, .grove),
    ]
    for c in cases {
        try expectEqual(Skin.current(at: pkt(2026, 10, 10, c.hour, c.minute), calendar: karachi), c.skin, "\(c.hour):\(c.minute)")
    }
    var tally: [Skin: Int] = [:]
    for hour in 0..<24 { tally[Skin.current(at: pkt(2026, 10, 10, hour, 30), calendar: karachi), default: 0] += 1 }
    try expectEqual(tally, [.day: 9, .smut: 6, .grove: 9])
    // The calendar decides whose hour it is: 08:00 in Karachi is 20:00 the evening before in Los Angeles.
    var losAngeles = Calendar(identifier: .gregorian)
    losAngeles.timeZone = try require(TimeZone(identifier: "America/Los_Angeles"))
    try expectEqual(Skin.current(at: pkt(2026, 10, 10, 8, 0), calendar: karachi), .day)
    try expectEqual(Skin.current(at: pkt(2026, 10, 10, 8, 0), calendar: losAngeles), .grove)
}

func skinColours() throws {
    try expectEqual([Skin.day.groundHex, Skin.day.inkHex, Skin.day.liftHex], [0xF3FB04, 0x000000, 0xFFFFA0])
    try expectEqual([Skin.grove.groundHex, Skin.grove.inkHex, Skin.grove.liftHex], [0x186409, 0xF3FB04, 0x004A00])
    try expectEqual([Skin.smut.groundHex, Skin.smut.inkHex, Skin.smut.liftHex], [0xC11B6B, 0xF3FB04, 0x8F1350])
    try expectEqual(Skin.allCases.map(\.accentHex), [0x186409, 0xF3FB04, 0xF3FB04])
    try expectEqual(Skin.allCases.map(\.bandHex), [0x186409, 0x002800, 0x6E003F])
    try expectEqual(Skin.allCases.map(\.mapDeepHex), [0x006F00, 0x7E9B45, 0x006F00])
    try expectEqual([Skin.mapTintHex, Skin.onBandHex], [0x7E9B45, 0xF3FB04])
    try expectEqual(Skin.allCases.map(\.rawValue), ["day", "grove", "smut"])
    let encoded = try JSONEncoder().encode([Skin.grove])
    try expectEqual(try JSONDecoder().decode([Skin].self, from: encoded), [.grove])
}

func skinChoiceResolvesAutomaticAndFixed() throws {
    try expectEqual(SkinChoice.allCases.map(\.label), ["Automatic", "Day", "Grove", "Smut"])
    // Stored values: absent, empty, the retired skins and a wrong case all read as Automatic.
    for stored in [nil, "", "night", "dawn", "Grove", "auto", "DAY"] as [String?] {
        try expectEqual(SkinChoice(stored: stored), .automatic, String(describing: stored))
    }
    for choice in SkinChoice.allCases { try expectEqual(SkinChoice(stored: choice.rawValue), choice) }
    // Automatic is the hour's skin, at each band.
    let hours: [(Int, Skin)] = [(0, .grove), (5, .smut), (8, .day), (12, .day), (16, .day), (17, .smut), (20, .grove), (23, .grove)]
    for (hour, skin) in hours {
        try expectEqual(SkinChoice.automatic.skin(at: pkt(2026, 10, 5, hour, 30), calendar: karachi), skin, "automatic at \(hour)")
    }
    // A fixed choice holds through every hour of the day, whatever the sky says.
    for choice in [SkinChoice.day, .grove, .smut] {
        let want = Skin(rawValue: choice.rawValue)
        for hour in 0..<24 {
            try expectEqual(choice.skin(at: pkt(2026, 10, 5, hour, 0), calendar: karachi), want, "\(choice) at \(hour)")
        }
    }
    // The negative case: a fixed choice is not Automatic in disguise. Grove at noon is not the noon skin.
    try expect(SkinChoice.grove.skin(at: pkt(2026, 10, 5, 12, 0), calendar: karachi) != SkinChoice.automatic.skin(at: pkt(2026, 10, 5, 12, 0), calendar: karachi))
}

// MARK: - Deep links

func deepLinksParse() throws {
    let cases: [(String, DeepLink)] = [
        ("khajistan://receiver", .receiver),
        ("khajistan://receiver/", .receiver),
        ("KHAJISTAN://Receiver", .receiver),
        ("khajistan://receiver/indus", .region("indus")),
        ("khajistan://receiver/egypt-nile", .region("egypt-nile")),
        ("khajistan://receiver/indus/", .region("indus")),
        ("khajistan://transmission", .transmission),
        ("khajistan://transmission/1", .channel(1)),
        ("khajistan://transmission/2", .channel(2)),
    ]
    for (text, link) in cases {
        try expectEqual(DeepLink(url: try require(URL(string: text))), link, text)
    }
    // Every link the extension builds reads back as itself.
    for link in [DeepLink.receiver, .region("indus"), .region("central-asia"), .transmission, .channel(1), .channel(2)] {
        try expectEqual(DeepLink(url: link.url), link, link.url.absoluteString)
    }
    // A region id that is not one does not become a link to it.
    try expectEqual(DeepLink.region("../x").url, DeepLink.receiver.url)
}

func deepLinksRefuse() throws {
    let refused = [
        "https://receiver/indus",                 // another scheme
        "khajistan://",                           // no host
        "khajistan://library",                    // a screen the app does not have
        "khajistan://receiver/indus/extra",       // too deep
        "khajistan://receiver//indus",
        "khajistan://receiver/Indus",             // ids are lower case
        "khajistan://receiver/-indus",
        "khajistan://receiver/in--dus",
        "khajistan://receiver/in%20dus",
        "khajistan://transmission/3",             // two channels
        "khajistan://transmission/0",
        "khajistan://transmission/01",
        "khajistan://transmission/+1",
        "khajistan://transmission/one",
        "khajistan://receiver?region=indus",      // no query
        "khajistan://receiver#indus",             // no fragment
        "khajistan://user@receiver",              // no user
        "khajistan://receiver:80",                // no port
    ]
    for text in refused {
        try expectEqual(DeepLink(url: try require(URL(string: text), text)), nil, text)
    }
}

// MARK: - Receiver index

let indexJSON = #"""
{"schemaVersion":"2.0.0",
 "regions":[
  {"id":"indus","label":"Indus","kind":"state","tier":"heartbeat"},
  {"id":"kurdistan","label":"Kurdistan","kind":"people","tier":"core","states":["anatolia"]},
  {"id":"anatolia","label":"Anatolia","kind":"state","tier":"core"},
  {"id":"nusantara","label":"Nusantara","kind":"state","tier":"islamicate","within":["x"]},
  {"id":"khorasan","label":"Khorasan","kind":"state","tier":"heartbeat"}],
 "totals":{"channels":10,"live":9,"byMedium":{"radio":6,"tv":3,"camera":1},"onLoad":8},
 "regionFiles":{
  "indus":"/data/open-frequencies/regions/indus.json",
  "anatolia":"/data/open-frequencies/regions/anatolia.json",
  "nusantara":"/data/open-frequencies/regions/nusantara.json",
  "unfiled":"/data/open-frequencies/regions/unfiled.json",
  "khorasan":"//evil.example/x.json"},
 "cameraFiles":{"anatolia":"/data/open-frequencies/regions/anatolia-camera.json"},
 "regionCounts":{
  "indus":{"channels":3,"live":3,"byMedium":{"tv":1,"radio":2}},
  "anatolia":{"channels":150,"live":150,"byMedium":{"tv":65,"radio":61,"camera":24}},
  "nusantara":{"channels":2,"live":2,"byMedium":{"radio":1,"camera":1,"tv":0}},
  "tvonly":{"channels":1,"live":1,"byMedium":{"tv":1}},
  "cams":{"channels":2,"live":2,"byMedium":{"camera":2}},
  "unfiled":{"channels":0,"live":0,"byMedium":{}}},
 "opening":[{"id":"x"}]}
"""#

func receiverIndexRegionsAndLines() throws {
    let index = try decode(ReceiverIndex.self, indexJSON)
    try expectEqual(index.regions.count, 5)
    // Index order, and only regions that have a shard file: kurdistan has none.
    try expectEqual(index.listedRegions.map(\.id), ["indus", "anatolia", "nusantara", "khorasan"])
    try expectEqual(index.listedRegions.first, ReceiverIndex.Region(id: "indus", label: "Indus", kind: "state", tier: "heartbeat"))
    try expectEqual(index.totals.channels, 10)
    try expectEqual(index.totals.byMedium["tv"], 3)

    try expectEqual(index.shardURL(regionId: "indus")?.absoluteString, "https://khajistan-archive.pages.dev/data/open-frequencies/regions/indus.json")
    try expectEqual(index.shardURL(regionId: "kurdistan"), nil)
    try expectEqual(index.shardURL(regionId: "nowhere"), nil)
    // A protocol-relative path would leave the site; it is refused rather than followed.
    try expectEqual(index.shardURL(regionId: "khorasan"), nil)
    try expectEqual(index.cameraURL(regionId: "anatolia")?.absoluteString, "https://khajistan-archive.pages.dev/data/open-frequencies/regions/anatolia-camera.json")
    try expectEqual(index.cameraURL(regionId: "indus"), nil)

    try expectEqual(index.mediumLine(regionId: "anatolia"), "65 television · 61 radio · 24 cameras")
    try expectEqual(index.mediumLine(regionId: "indus"), "1 television · 2 radio")
    try expectEqual(index.mediumLine(regionId: "nusantara"), "1 radio · 1 camera")
    try expectEqual(index.mediumLine(regionId: "tvonly"), "1 television")
    try expectEqual(index.mediumLine(regionId: "cams"), "2 cameras")
    try expectEqual(index.mediumLine(regionId: "unfiled"), "")
    try expectEqual(index.mediumLine(regionId: "kurdistan"), "")
}

func receiverIndexWithoutCameraFiles() throws {
    let object = try jsonObject(indexJSON)
    var trimmed = object
    trimmed.removeValue(forKey: "cameraFiles")
    let index = try JSONDecoder().decode(ReceiverIndex.self, from: try JSONSerialization.data(withJSONObject: trimmed))
    try expectEqual(index.cameraFiles, nil)
    try expectEqual(index.cameraURL(regionId: "anatolia"), nil)
    try expectEqual(index.shardURL(regionId: "indus") != nil, true)
}

// MARK: - Channels

let channelJSON = #"""
{"id":"pk-radio-1","slug":"pk-radio-1","legacyIds":["a"],"name":"Radio One","nativeName":"ریڈیو","mediaType":"radio",
 "primaryLanguage":"Urdu","regionIds":["indus"],"country":"Pakistan","territory":"Punjab","broadcaster":"Radio Pakistan",
 "officialWebsite":null,"streams":[{"id":"pk-radio-1-primary","format":"hls","cors":null},{"id":"pk-radio-1-backup","format":"hls","cors":true}],
 "activeStreamId":"pk-radio-1-backup","attributionText":"Radio Pakistan","publicationStatus":"published","healthStatus":"online",
 "manualDisabled":false,"description":"d","genres":["news"]}
"""#

/// The channel above with some keys replaced (NSNull() makes a key null) and some removed.
func channelWith(_ overrides: [String: Any] = [:], removing keys: [String] = []) throws -> Channel {
    var object = try jsonObject(channelJSON)
    for (key, value) in overrides { object[key] = value }
    for key in keys { object.removeValue(forKey: key) }
    return try JSONDecoder().decode(Channel.self, from: try JSONSerialization.data(withJSONObject: object))
}

func channelDecodesAndFindsItsActiveStream() throws {
    let channel = try channelWith()
    try expectEqual(channel.id, "pk-radio-1")
    try expectEqual(channel.nativeName, "ریڈیو")
    try expectEqual(channel.activeStream?.id, "pk-radio-1-backup")
    try expectEqual(channel.activeStream?.format, "hls")
    try expectEqual(channel.genres ?? [], ["news"])
    try expectEqual(try channelWith(["activeStreamId": NSNull()]).activeStream, nil)
    try expectEqual(try channelWith(["activeStreamId": "nope"]).activeStream, nil)
    // Every optional field may be absent or null.
    let bare = try channelWith(removing: ["nativeName", "primaryLanguage", "regionIds", "country", "territory", "broadcaster",
                                          "activeStreamId", "attributionText", "publicationStatus", "healthStatus",
                                          "manualDisabled", "description", "genres"])
    try expectEqual(bare.activeStream, nil)
    try expectEqual(bare.place, "")
    try expectEqual(try channelWith(["genres": NSNull(), "nativeName": NSNull()]).genres, nil)
}

func channelPlaceDropsWhatIsNotKnown() throws {
    try expectEqual(try channelWith().place, "Pakistan · Urdu")
    try expectEqual(try channelWith(["primaryLanguage": "Not yet verified"]).place, "Pakistan")
    try expectEqual(try channelWith(["primaryLanguage": NSNull()]).place, "Pakistan")
    try expectEqual(try channelWith(["country": ""]).place, "Urdu")
    try expectEqual(try channelWith(["country": NSNull(), "primaryLanguage": NSNull()]).place, "")
    try expectEqual(try channelWith(["country": "Iran", "primaryLanguage": "  "]).place, "Iran")
    try expectEqual(try channelWith(["country": "", "primaryLanguage": "Not yet verified"]).place, "")
}

// MARK: - Eligibility

func eligibilityChannel(_ id: String, name: String? = nil, publication: String? = "published", disabled: Bool? = false,
                        health: String? = "online", streams: [String] = ["s1"], active: String? = "s1") throws -> Channel {
    var object: [String: Any] = [
        "id": id, "name": name ?? id, "mediaType": "radio",
        "streams": streams.map { ["id": $0, "format": "hls"] },
    ]
    if let publication { object["publicationStatus"] = publication }
    if let disabled { object["manualDisabled"] = disabled }
    if let health { object["healthStatus"] = health }
    if let active { object["activeStreamId"] = active }
    return try JSONDecoder().decode(Channel.self, from: try JSONSerialization.data(withJSONObject: object))
}

func eligibilityKeepsTheGoodAndDropsEachWithdrawal() throws {
    let channels: [Channel] = [
        // kept
        try eligibilityChannel("good"),
        try eligibilityChannel("publication-absent", publication: nil),
        try eligibilityChannel("disabled-absent", disabled: nil),
        try eligibilityChannel("ratio-at-bar"),
        try eligibilityChannel("ratio-null"),
        try eligibilityChannel("health-feed-outranks-channel", health: "offline"),
        try eligibilityChannel("degraded", health: "degraded"),
        // dropped
        try eligibilityChannel("denied"),
        try eligibilityChannel("off-air"),
        try eligibilityChannel("offline-by-feed"),
        try eligibilityChannel("offline-by-channel", health: "offline"),
        try eligibilityChannel("blocked-by-feed"),
        try eligibilityChannel("blocked-by-channel", health: "blocked"),
        try eligibilityChannel("manually-disabled", disabled: true),
        try eligibilityChannel("draft", publication: "draft"),
        try eligibilityChannel("no-active-stream", active: nil),
        try eligibilityChannel("active-stream-matches-nothing", active: "zzz"),
        try eligibilityChannel("slow-0-2"),
        try eligibilityChannel("slow-0-49"),
    ]
    let denylist = try decode(Denylist.self, #"{"disabledChannelIds":["denied"],"reasonCodes":{}}"#)
    let offAir = try decode(OffAir.self, #"{"offAirChannelIds":["off-air"]}"#)
    let health = try decode(Health.self, #"""
    {"results":[
     {"channelId":"offline-by-feed","status":"offline","deliveryRatio":3.0},
     {"channelId":"blocked-by-feed","status":"blocked","deliveryRatio":null},
     {"channelId":"health-feed-outranks-channel","status":"online","deliveryRatio":1.0},
     {"channelId":"slow-0-2","status":"online","deliveryRatio":0.2},
     {"channelId":"slow-0-49","status":"online","deliveryRatio":0.49},
     {"channelId":"ratio-at-bar","status":"online","deliveryRatio":0.5},
     {"channelId":"ratio-null","status":"online","deliveryRatio":null}]}
    """#)
    let controls = Controls(denylist: denylist, offAir: offAir, health: health)
    try expectEqual(controls.denied, ["denied", "off-air"])
    try expectEqual(controls.health.count, 7)
    let kept = ReceiverRules.eligible(channels, controls: controls).map(\.id)
    try expectEqual(Set(kept), ["good", "publication-absent", "disabled-absent", "ratio-at-bar", "ratio-null",
                                "health-feed-outranks-channel", "degraded"])
    try expectEqual(kept.count, 7)
    // Without any feed nothing is withdrawn by a feed: only the channels' own fields count.
    let bare = ReceiverRules.eligible(channels, controls: .empty).map(\.id)
    try expectEqual(Set(bare), ["good", "publication-absent", "disabled-absent", "ratio-at-bar", "ratio-null", "degraded",
                                "denied", "off-air", "offline-by-feed", "blocked-by-feed", "slow-0-2", "slow-0-49"])
    try expectEqual(bare.count, 12)
}

func eligibilityKeepsADuplicateOnceAndSortsByName() throws {
    let channels: [Channel] = [
        try eligibilityChannel("dup", name: "Dup"),
        try eligibilityChannel("dup", name: "Dup"),
        // The first copy is ineligible, so the second is the one kept.
        try eligibilityChannel("dup2", name: "Dup Two", health: "offline"),
        try eligibilityChannel("dup2", name: "Dup Two"),
        try eligibilityChannel("z", name: "zeta"),
        try eligibilityChannel("a", name: "Alpha"),
        try eligibilityChannel("b", name: "beta"),
        try eligibilityChannel("r10", name: "Radio 10"),
        try eligibilityChannel("r2", name: "Radio 2"),
    ]
    let result = ReceiverRules.eligible(channels, controls: .empty)
    try expectEqual(result.map(\.id).filter { $0.hasPrefix("dup") }.sorted(), ["dup", "dup2"])
    try expectEqual(result.count, 7)
    try expectEqual(result.map(\.name), ["Alpha", "beta", "Dup", "Dup Two", "Radio 2", "Radio 10", "zeta"])
    try expectEqual(ReceiverRules.eligible([], controls: .empty).count, 0)
}

func controlsFoldTheFeedsAndLastHealthRecordWins() throws {
    let denylist = try decode(Denylist.self, #"{"disabledChannelIds":["a","b"]}"#)
    let offAir = try decode(OffAir.self, #"{"offAirChannelIds":["b","c"]}"#)
    try expectEqual(Controls(denylist: denylist, offAir: offAir, health: nil).denied, ["a", "b", "c"])
    try expectEqual(Controls(denylist: denylist, offAir: nil, health: nil).denied, ["a", "b"])
    try expectEqual(Controls(denylist: nil, offAir: offAir, health: nil).denied, ["b", "c"])
    try expectEqual(Controls.empty.denied.count + Controls.empty.health.count, 0)
    let health = try decode(Health.self, #"{"results":[{"channelId":"x","status":"offline"},{"channelId":"x","status":"online","deliveryRatio":2.5}]}"#)
    let controls = Controls(denylist: nil, offAir: nil, health: health)
    try expectEqual(controls.health["x"]?.status, "online")
    try expectEqual(controls.health["x"]?.deliveryRatio, 2.5)
}

func tiersAndMediumLabels() throws {
    try expectEqual(ReceiverRules.tiersOnByDefault, ["heartbeat", "core"])
    try expect(!ReceiverRules.tiersOnByDefault.contains("islamicate"))
    try expectEqual(ReceiverRules.mediumLabel("tv"), "Television")
    try expectEqual(ReceiverRules.mediumLabel("radio"), "Radio")
    try expectEqual(ReceiverRules.mediumLabel("camera"), "Cameras")
    try expectEqual(ReceiverRules.mediumLabel("film"), "Film")
    try expectEqual(ReceiverRules.mediumLabel("VOD"), "VOD")
    try expectEqual(ReceiverRules.mediumLabel(""), "")
}

// MARK: - Carrier

func carrierURLEncodesTheStreamID() throws {
    let plain = ReceiverRules.carrierURL(streamID: "anatolia-t-rkiye-4u-tv-720p-primary")
    try expectEqual(plain.absoluteString, "https://khajistan-archive.pages.dev/api/frequency?stream=anatolia-t-rkiye-4u-tv-720p-primary")
    // An opaque id is data: no character of it may become query or fragment syntax.
    for awkward in ["station+1&x=#fragment", "a b/c?d=e", "100%", "تهران", "a.b_c~d-e"] {
        let url = ReceiverRules.carrierURL(streamID: awkward)
        let parts = try require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        try expectEqual(parts.queryItems, [URLQueryItem(name: "stream", value: awkward)], awkward)
        try expectEqual(parts.fragment, nil, awkward)
        try expectEqual(parts.path, "/api/frequency", awkward)
    }
    try expect(ReceiverRules.carrierURL(streamID: "station+1&x=#fragment").absoluteString.hasSuffix("stream=station%2B1%26x%3D%23fragment"))
}

func carrierAnswerIsValidated() throws {
    let url = try ReceiverRules.carrier(from: Data(#"{"stream":"s","url":"https://example.com/live/index.m3u8"}"#.utf8))
    try expectEqual(url.absoluteString, "https://example.com/live/index.m3u8")
    for rejected in [#"{"url":"http://example.com/x"}"#, #"{"url":"https://user:pass@example.com/x"}"#,
                     #"{"url":"https://user@example.com/x"}"#, #"{"url":"ftp://example.com/x"}"#] {
        try expectThrows(CarrierError.rejected) { _ = try ReceiverRules.carrier(from: Data(rejected.utf8)) }
    }
    for malformed in [#"{"url":null}"#, "{}", "not json", #"{"url":""}"#, #"{"url":7}"#, ""] {
        try expectThrows(CarrierError.malformed) { _ = try ReceiverRules.carrier(from: Data(malformed.utf8)) }
    }
}

func validCarrierRules() throws {
    func valid(_ text: String) throws -> Bool { ReceiverRules.validCarrier(try require(URL(string: text), text)) }
    try expectEqual(try valid("https://example.com/a.m3u8"), true)
    try expectEqual(try valid("HTTPS://EXAMPLE.COM/a"), true)
    try expectEqual(try valid("https://example.com:8443/a?x=1"), true)
    for bad in ["http://example.com/a", "https://user:pass@example.com/a", "https://user@example.com/a",
                "ftp://example.com/a", "file:///etc/passwd", "https:/just-a-path", "mailto:a@example.com", "example.com/a"] {
        try expectEqual(try valid(bad), false, bad)
    }
}

// MARK: - Transmission

let supabasePlay = "https://qojysegeddztsxdmhjfb.supabase.co/functions/v1/tv-play?id=tvx-d35cdf39-aman-and-yane-greece-video"
let streamUID = "625a05145f897f6a3fd10d4f67643384"
let streamHostURL = "https://customer-0svgnorro16tedsf.cloudflarestream.com"

func transmissionRoutesTheThreeShapes() throws {
    try expectEqual(Transmission.route(for: supabasePlay), .tvPlay(try require(URL(string: supabasePlay))))
    try expectEqual(Transmission.route(for: "https://qojysegeddztsxdmhjfb.supabase.co:443/functions/v1/tv-play?id=x"),
                    .tvPlay(try require(URL(string: "https://qojysegeddztsxdmhjfb.supabase.co:443/functions/v1/tv-play?id=x"))))
    try expectEqual(Transmission.route(for: "\(streamHostURL)/\(streamUID)/manifest/video.m3u8"),
                    .stream(uid: streamUID, suffix: "manifest/video.m3u8"))
    for direct in ["https://example.com/live/index.m3u8",
                   "https://qojysegeddztsxdmhjfb.supabase.co/storage/v1/object/public/audio/climate-change-ramzan-96.mp3"] {
        try expectEqual(Transmission.route(for: direct), .direct(try require(URL(string: direct))), direct)
    }
}

func transmissionNeverSendsTheTokenToAnotherHost() throws {
    // Only the exact Supabase origin and exact function path get a bearer token. Anything that
    // merely looks like it is a plain URL to play, never a route that carries credentials.
    for lookalike in ["https://qojysegeddztsxdmhjfb.supabase.co.evil.example/functions/v1/tv-play?id=x",
                      "https://evil.example/functions/v1/tv-play?id=x",
                      "https://qojysegeddztsxdmhjfb.supabase.co:8443/functions/v1/tv-play?id=x",
                      "https://qojysegeddztsxdmhjfb.supabase.co/functions/v1/tv-play/?id=x",
                      "https://qojysegeddztsxdmhjfb.supabase.co/functions/v1/tv-play-other?id=x",
                      "https://qojysegeddztsxdmhjfb.supabase.co/functions/v1/tv-stream-token?uid=\(streamUID)"] {
        try expectEqual(Transmission.route(for: lookalike), .direct(try require(URL(string: lookalike))), lookalike)
    }
    let lookalikeStream = "https://customer-0svgnorro16tedsf.cloudflarestream.com.evil.example/\(streamUID)/manifest/video.m3u8"
    try expectEqual(Transmission.route(for: lookalikeStream), .direct(try require(URL(string: lookalikeStream))))
}

func transmissionRejects() throws {
    let rejects = [
        "http://qojysegeddztsxdmhjfb.supabase.co/functions/v1/tv-play?id=x",
        "http://\(streamHostURL.dropFirst(8))/\(streamUID)/manifest/video.m3u8",
        "http://example.com/a.mp4",
        "https://user:pass@example.com/a.mp4",
        "https://user@example.com/a.mp4",
        "https://:pass@example.com/a.mp4",
        "https://user:pass@qojysegeddztsxdmhjfb.supabase.co/functions/v1/tv-play?id=x",
        // The stream host serves exactly /<32 lowercase hex>/manifest/video.m3u8.
        "\(streamHostURL)/\(streamUID)/manifest/audio.m3u8",
        "\(streamHostURL)/\(streamUID)/manifest/video.m3u8/extra",
        "\(streamHostURL)/\(streamUID)/manifest/video.m3u8/",
        "\(streamHostURL)/\(streamUID.uppercased())/manifest/video.m3u8",
        "\(streamHostURL)/\(streamUID)0/manifest/video.m3u8",
        "\(streamHostURL)/\(streamUID.dropLast())/manifest/video.m3u8",
        "\(streamHostURL)/\(streamUID.dropLast())g/manifest/video.m3u8",
        "\(streamHostURL)/\(streamUID)/video.m3u8",
        "\(streamHostURL)/a/\(streamUID)/manifest/video.m3u8",
        "\(streamHostURL)/",
        streamHostURL,
        "javascript:alert(1)", "file:///etc/passwd", "ftp://example.com/a", "not a url", "", "https://", "//example.com/a",
    ]
    for text in rejects { try expectEqual(Transmission.route(for: text), nil, text) }
}

func transmissionRequests() throws {
    let play = try require(Transmission.route(for: supabasePlay))
    let request = try require(Transmission.request(for: play, accessToken: "tok-1"))
    try expectEqual(request.url?.absoluteString, supabasePlay)
    try expectEqual(request.httpMethod, "GET")
    try expectEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer tok-1")
    try expectEqual(request.value(forHTTPHeaderField: "apikey"), KJConfig.anonKey)
    try expectEqual(request.value(forHTTPHeaderField: "User-Agent"), KJConfig.userAgent)
    try expectEqual(request.cachePolicy, .reloadIgnoringLocalAndRemoteCacheData)
    try expectEqual(request.httpBody, nil)

    let stream = try require(Transmission.request(for: .stream(uid: streamUID, suffix: "manifest/video.m3u8"), accessToken: "tok-2"))
    try expectEqual(stream.url?.absoluteString, "https://qojysegeddztsxdmhjfb.supabase.co/functions/v1/tv-stream-token?uid=\(streamUID)")
    try expectEqual(stream.httpMethod, "GET")
    try expectEqual(stream.value(forHTTPHeaderField: "Authorization"), "Bearer tok-2")
    try expectEqual(stream.value(forHTTPHeaderField: "apikey"), KJConfig.anonKey)
    try expectEqual(stream.cachePolicy, .reloadIgnoringLocalAndRemoteCacheData)
    // A uid that is not hex cannot reshape the query.
    let hostile = try require(Transmission.request(for: .stream(uid: "a&b=c#d", suffix: "manifest/video.m3u8"), accessToken: "t"))
    try expect(hostile.url?.absoluteString.hasSuffix("?uid=a%26b%3Dc%23d") == true)

    try expectEqual(Transmission.request(for: .direct(try require(URL(string: "https://example.com/a.mp4"))), accessToken: "tok"), nil)
}

func transmissionCarriers() throws {
    let stream = PlayRoute.stream(uid: streamUID, suffix: "manifest/video.m3u8")
    let good = try Transmission.carrier(from: Data(#"{"token":"eyJhbGciOi.payload-part_1.sig"}"#.utf8), route: stream)
    try expectEqual(good.absoluteString, "https://customer-0svgnorro16tedsf.cloudflarestream.com/eyJhbGciOi.payload-part_1.sig/manifest/video.m3u8")
    for bad in [#"{"token":""}"#, #"{"token":"a b"}"#, #"{"token":"a/b"}"#, #"{"token":"a?b"}"#, #"{"token":"a#b"}"#,
                #"{"token":"tok\n"}"#, #"{"token":"töken"}"#, #"{"token":123}"#, #"{"token":null}"#, "{}", "nope", ""] {
        try expectThrows(CarrierError.malformed) { _ = try Transmission.carrier(from: Data(bad.utf8), route: stream) }
    }

    let play = try require(Transmission.route(for: supabasePlay))
    let url = try Transmission.carrier(from: Data(#"{"url":"https://cdn.example.com/a/b.mp4"}"#.utf8), route: play)
    try expectEqual(url.absoluteString, "https://cdn.example.com/a/b.mp4")
    try expectThrows(CarrierError.rejected) { _ = try Transmission.carrier(from: Data(#"{"url":"http://cdn.example.com/a.mp4"}"#.utf8), route: play) }
    try expectThrows(CarrierError.rejected) { _ = try Transmission.carrier(from: Data(#"{"url":"https://u:p@cdn.example.com/a.mp4"}"#.utf8), route: play) }
    try expectThrows(CarrierError.malformed) { _ = try Transmission.carrier(from: Data("{}".utf8), route: play) }

    let direct = try require(URL(string: "https://example.com/a.mp4"))
    try expectEqual(try Transmission.carrier(from: Data(), route: .direct(direct)), direct)
}

func scheduleURLAndBasicAuthorization() throws {
    try expectEqual(Transmission.scheduleURL(month: "2026-10").absoluteString,
                    "https://khajistan-archive.pages.dev/data/khajistan-tv/programming-2026-10.json")
    try expectEqual(Transmission.basicAuthorization(user: "khajistan", password: "x"), "Basic a2hhamlzdGFuOng=")
    try expectEqual(Transmission.basicAuthorization(user: KJConfig.previewUser, password: "pä:ss"), "Basic " + Data("khajistan:pä:ss".utf8).base64EncodedString())
    try expectEqual(KJConfig.previewUser, "khajistan")
    try expectEqual(KJConfig.keychainService, "com.khajistan.tv")
    try expectEqual(KJConfig.site.absoluteString, "https://khajistan-archive.pages.dev")
    try expectEqual(KJConfig.supabase.absoluteString, "https://qojysegeddztsxdmhjfb.supabase.co")
    try expectEqual(KJConfig.streamHost, "customer-0svgnorro16tedsf.cloudflarestream.com")
}

func anonKeyIsTheSitesAnonRole() throws {
    let parts = KJConfig.anonKey.split(separator: ".")
    try expectEqual(parts.count, 3)
    var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
    while payload.count % 4 != 0 { payload += "=" }
    let object = try jsonObject(String(decoding: try require(Data(base64Encoded: payload)), as: UTF8.self))
    try expectEqual(object["role"] as? String, "anon")
    try expectEqual(object["ref"] as? String, "qojysegeddztsxdmhjfb")
}

// MARK: - Auth

let authNow = Date(timeIntervalSince1970: 1_800_000_000)
let authBody = #"{"access_token":"AT","token_type":"bearer","expires_in":3600,"refresh_token":"RT","user":{"id":"u-1","email":"a@b.example","role":"authenticated","is_anonymous":false}}"#

func authSessionFromBody() throws {
    let session = try AuthAPI.session(from: Data(authBody.utf8), now: authNow)
    try expectEqual(session, Session(accessToken: "AT", refreshToken: "RT", expiresAt: authNow.addingTimeInterval(3600), email: "a@b.example", userId: "u-1"))
    // expires_at (unix seconds) wins over expires_in when present.
    let withAt = authBody.replacingOccurrences(of: #""expires_in":3600"#, with: #""expires_in":3600,"expires_at":1800007200"#)
    try expectEqual(try AuthAPI.session(from: Data(withAt.utf8), now: authNow).expiresAt, Date(timeIntervalSince1970: 1_800_007_200))
    // No email and no role are fine; a fractional expires_at is read as a number.
    let sparse = #"{"access_token":"AT","refresh_token":"RT","expires_at":1800000100.5,"user":{"id":"u-2"}}"#
    let parsed = try AuthAPI.session(from: Data(sparse.utf8), now: authNow)
    try expectEqual(parsed.email, nil)
    try expectEqual(parsed.expiresAt, Date(timeIntervalSince1970: 1_800_000_100.5))
}

func authSessionRefusesAnonymousAndMalformed() throws {
    func session(_ json: String) throws { _ = try AuthAPI.session(from: Data(json.utf8), now: authNow) }
    try expectThrows(AuthError.anonymous) { try session(authBody.replacingOccurrences(of: #""is_anonymous":false"#, with: #""is_anonymous":true"#)) }
    try expectThrows(AuthError.anonymous) { try session(authBody.replacingOccurrences(of: #""role":"authenticated""#, with: #""role":"anon""#)) }
    // A minimal anonymous body is anonymous, not malformed.
    try expectThrows(AuthError.anonymous) { try session(#"{"access_token":"x","user":{"id":"1","is_anonymous":true}}"#) }
    try expectThrows(AuthError.anonymous) { try session(#"{"access_token":"x","user":{"role":"anon"}}"#) }
    for malformed in ["", "nope", "[]", "{}", #"{"access_token":"AT"}"#,
                      #"{"refresh_token":"RT","expires_in":60,"user":{"id":"u"}}"#,
                      #"{"access_token":"","refresh_token":"RT","expires_in":60,"user":{"id":"u"}}"#,
                      #"{"access_token":"AT","refresh_token":"","expires_in":60,"user":{"id":"u"}}"#,
                      #"{"access_token":"AT","refresh_token":"RT","expires_in":60}"#,
                      #"{"access_token":"AT","refresh_token":"RT","expires_in":60,"user":{"id":""}}"#,
                      #"{"access_token":"AT","refresh_token":"RT","user":{"id":"u"}}"#,
                      #"{"access_token":"AT","refresh_token":"RT","expires_in":-5,"user":{"id":"u"}}"#,
                      #"{"access_token":5,"refresh_token":"RT","expires_in":60,"user":{"id":"u"}}"#,
                      #"{"error":"invalid_grant","error_description":"Invalid login credentials"}"#] {
        try expectThrows(AuthError.malformed) { try session(malformed) }
    }
}

func authErrorMessages() throws {
    func message(_ json: String) -> String? { AuthAPI.errorMessage(from: Data(json.utf8)) }
    try expectEqual(message(#"{"error":"invalid_grant","error_description":"Invalid login credentials"}"#), "Invalid login credentials")
    try expectEqual(message(#"{"code":400,"msg":"Email not confirmed"}"#), "Email not confirmed")
    try expectEqual(message(#"{"code":"validation_failed","message":"Unable to validate email address"}"#), "Unable to validate email address")
    try expectEqual(message(#"{"error_description":"D","message":"M","msg":"S"}"#), "D")
    try expectEqual(message(#"{"message":"M","msg":"S"}"#), "M")
    try expectEqual(message(#"{"message":{"nested":true},"msg":"S"}"#), "S")
    try expectEqual(message(#"{"error_description":"","msg":"S"}"#), "S")
    try expectEqual(message(#"{"error":"only_a_code"}"#), nil)
    try expectEqual(message("{}"), nil)
    try expectEqual(message("<html>502</html>"), nil)
    try expectEqual(message(""), nil)
    try expectEqual(message(#"["msg"]"#), nil)
}

func authRequests() throws {
    let password = "pa\"ss wörd/é\\"
    let request = AuthAPI.passwordRequest(email: "a@b.example", password: password)
    try expectEqual(request.httpMethod, "POST")
    try expectEqual(request.url?.absoluteString, "https://qojysegeddztsxdmhjfb.supabase.co/auth/v1/token?grant_type=password")
    try expectEqual(request.value(forHTTPHeaderField: "apikey"), KJConfig.anonKey)
    try expectEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
    try expectEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer " + KJConfig.anonKey)
    let body = try jsonObject(String(decoding: try require(request.httpBody), as: UTF8.self))
    try expectEqual(body["email"] as? String, "a@b.example")
    try expectEqual(body["password"] as? String, password)
    try expectEqual(body.count, 2)
    try expectEqual(String(decoding: try require(AuthAPI.passwordRequest(email: "a@b.example", password: "pw").httpBody), as: UTF8.self),
                    #"{"email":"a@b.example","password":"pw"}"#)

    let refresh = AuthAPI.refreshRequest(refreshToken: "RT/1+2=")
    try expectEqual(refresh.httpMethod, "POST")
    try expectEqual(refresh.url?.absoluteString, "https://qojysegeddztsxdmhjfb.supabase.co/auth/v1/token?grant_type=refresh_token")
    try expectEqual(refresh.value(forHTTPHeaderField: "Authorization"), "Bearer " + KJConfig.anonKey)
    try expectEqual(refresh.value(forHTTPHeaderField: "apikey"), KJConfig.anonKey)
    try expectEqual(String(decoding: try require(refresh.httpBody), as: UTF8.self), #"{"refresh_token":"RT/1+2="}"#)

    let logout = AuthAPI.logoutRequest(accessToken: "AT")
    try expectEqual(logout.httpMethod, "POST")
    try expectEqual(logout.url?.absoluteString, "https://qojysegeddztsxdmhjfb.supabase.co/auth/v1/logout")
    try expectEqual(logout.value(forHTTPHeaderField: "Authorization"), "Bearer AT")
    try expectEqual(logout.value(forHTTPHeaderField: "apikey"), KJConfig.anonKey)
    try expectEqual(logout.value(forHTTPHeaderField: "Content-Type"), "application/json")
    try expectEqual(logout.httpBody, nil)
    for built in [request, refresh, logout] { try expectEqual(built.value(forHTTPHeaderField: "User-Agent"), KJConfig.userAgent) }
}

func sessionExpiryAndStorage() throws {
    let expiry = Date(timeIntervalSince1970: 1_800_000_000)
    let session = Session(accessToken: "AT", refreshToken: "RT", expiresAt: expiry, email: nil, userId: "u")
    try expectEqual(session.isExpired(at: expiry.addingTimeInterval(-3600)), false)
    try expectEqual(session.isExpired(at: expiry.addingTimeInterval(-61)), false)
    try expectEqual(session.isExpired(at: expiry.addingTimeInterval(-60)), true)
    try expectEqual(session.isExpired(at: expiry.addingTimeInterval(-59)), true)
    try expectEqual(session.isExpired(at: expiry), true)
    try expectEqual(session.isExpired(at: expiry.addingTimeInterval(1)), true)
    let stored = try JSONEncoder().encode(session)
    try expectEqual(try JSONDecoder().decode(Session.self, from: stored), session)
}

// MARK: - Station clock: arithmetic and units

/// Instants read both ways: StationClock's own integer arithmetic against Calendar's reading of
/// the same moment in a fixed UTC+5 zone. Negative epochs, leap days and year ends are in range.
func stationNowAgreesWithCalendar() throws {
    var reference = Calendar(identifier: .gregorian)
    reference.timeZone = try require(TimeZone(secondsFromGMT: 5 * 3600))
    var checked = 0
    // Foundation's Gregorian calendar is Julian before 1582-10-15, so the sweep starts in 1779.
    var epoch: Double = -6_000_000_000
    while epoch < 4_200_000_000 {       // 2103
        let date = Date(timeIntervalSince1970: epoch)
        let c = reference.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let now = StationClock.stationNow(date)
        let iso = isoString(c.year ?? 0, c.month ?? 0, c.day ?? 0)
        let minutes = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        let seconds = minutes * 60 + (c.second ?? 0)
        guard now.iso == iso, now.minutes == minutes, now.seconds == seconds else {
            throw Failure(description: "epoch \(epoch): clock \(now), calendar \(iso) \(minutes) \(seconds)")
        }
        checked += 1
        epoch += 86_413 * 3 + 29
    }
    try expect(checked > 15_000, "only \(checked) instants checked")
    // Leap day, century rules, year end, and the 19:00 UTC rollover into the next Pakistan day.
    // Epochs below were computed with Python's datetime, not with this clock or Calendar.
    let points: [(epoch: Double, iso: String, minutes: Int, seconds: Int)] = [
        (1_582_938_000, "2020-02-29", 360, 21_600),         // 2020-02-29 06:00:00, a leap day
        (951_850_799, "2000-02-29", 1439, 86_399),          // 2000 is a leap year (divisible by 400)
        (4_107_524_399, "2100-02-28", 1439, 86_399),        // 2100 is not: the next second is 1 March
        (4_107_524_400, "2100-03-01", 0, 0),
        (1_798_743_599, "2026-12-31", 1439, 86_399),        // year end
        (1_798_743_600, "2027-01-01", 0, 0),
        (1_793_473_199, "2026-10-31", 1439, 86_399),        // month end, 18:59:59 UTC
        (1_793_473_200, "2026-11-01", 0, 0),                // 19:00:00 UTC is already tomorrow in Pakistan
        (1_835_420_400, "2028-02-29", 720, 43_200),
        (1_835_463_600, "2028-03-01", 0, 0),
        (-1, "1970-01-01", 299, 17_999),                    // one second before the epoch is 04:59:59 PKT
        (-18_001, "1969-12-31", 1439, 86_399),              // negative epochs floor, never truncate
        (-2_203_909_200, "1900-03-01", 0, 0),               // 1900 is not a leap year
    ]
    for p in points {
        let now = StationClock.stationNow(Date(timeIntervalSince1970: p.epoch))
        try expectEqual(now.iso, p.iso, "\(p.epoch)")
        try expectEqual(now.minutes, p.minutes, "\(p.epoch)")
        try expectEqual(now.seconds, p.seconds, "\(p.epoch)")
    }
    // Fractions floor to the second the way the JS getters do, before and after the epoch.
    let boundary = pkt(2026, 10, 10, 12, 0, 0)
    let at = StationClock.stationNow(boundary)
    try expectEqual(StationClock.stationNow(boundary.addingTimeInterval(0.999)).seconds, at.seconds)
    try expectEqual(StationClock.stationNow(boundary.addingTimeInterval(-0.001)).seconds, at.seconds - 1)
    try expectEqual(StationClock.stationNow(boundary.addingTimeInterval(1)).seconds, at.seconds + 1)
}

func stationMonthFollowsPakistanTime() throws {
    // 2026-10-31 19:00:00 UTC (epoch 1793473200) is already 1 November in Pakistan.
    try expectEqual(StationClock.stationMonth(Date(timeIntervalSince1970: 1_793_473_200 - 1)), "2026-10")
    try expectEqual(StationClock.stationMonth(Date(timeIntervalSince1970: 1_793_473_200)), "2026-11")
    try expectEqual(StationClock.stationMonth(pkt(2026, 10, 31, 23, 59, 59)), "2026-10")
    try expectEqual(StationClock.stationMonth(pkt(2026, 11, 1, 0, 0, 0)), "2026-11")
    try expectEqual(StationClock.stationMonth(pkt(2026, 12, 31, 23, 59, 59)), "2026-12")
    try expectEqual(StationClock.stationMonth(pkt(2027, 1, 1, 0, 0, 0)), "2027-01")
    try expectEqual(StationClock.stationMonth(pkt(2026, 10, 10)), "2026-10")
    try expectEqual(Transmission.scheduleURL(month: StationClock.stationMonth(pkt(2026, 11, 1, 0, 0, 1))).lastPathComponent, "programming-2026-11.json")
    try expectEqual(StationClock.utcOffsetMinutes, 300)
    try expectEqual(StationClock.tzLabel, "PKT")
}

func clockLabels() throws {
    try expectEqual(StationClock.clockLabel(0), "00:00")
    try expectEqual(StationClock.clockLabel(359), "05:59")
    try expectEqual(StationClock.clockLabel(360), "06:00")
    try expectEqual(StationClock.clockLabel(1380), "23:00")
    try expectEqual(StationClock.clockLabel(1440), "00:00")
    try expectEqual(StationClock.clockLabel(1445), "00:05")
    try expectEqual(StationClock.clockLabel(2880 + 61), "01:01")
}

func makeProgramme(_ id: String, seconds: Double? = nil, nominal: Double? = nil, cleanStart: Double? = nil, cleanEnd: Double? = nil) -> Programming.Programme {
    Programming.Programme(id: id, title: id, seconds: seconds, nominal_minutes: nominal, clean_start: cleanStart, clean_end: cleanEnd,
                          show: nil, channel: 1, play_url: nil, audio_only: nil, custodian: nil, transfer: nil,
                          work_kind: nil, country: nil, description: nil)
}

func runSecondsRules() throws {
    try expectEqual(StationClock.runSeconds(makeProgramme("a", seconds: 600, nominal: 10)), 600)
    try expectEqual(StationClock.runSeconds(makeProgramme("a", seconds: 600, cleanStart: 20, cleanEnd: 10)), 570)
    try expectEqual(StationClock.runSeconds(makeProgramme("a", seconds: 0, nominal: 7)), 420)
    try expectEqual(StationClock.runSeconds(makeProgramme("a", seconds: -3, nominal: 7)), 420)
    try expectEqual(StationClock.runSeconds(makeProgramme("a", seconds: nil, nominal: 5, cleanStart: 30)), 270)
    try expectEqual(StationClock.runSeconds(makeProgramme("a")), 480)
    try expectEqual(StationClock.runSeconds(makeProgramme("a", nominal: 0)), 480)
    try expectEqual(StationClock.runSeconds(nil), 480)
    try expectEqual(StationClock.runSeconds(makeProgramme("a", seconds: 5, cleanStart: 10)), 1)
    try expectEqual(StationClock.runSeconds(makeProgramme("a", seconds: 34.3)), 34.3)
}

/// A small schedule written by hand, so every number in the expectations below is arithmetic
/// anyone can redo: programmes run 600 s, 270 s (300 less a 20 s head and 10 s tail) and 300 s.
let syntheticJSON = #"""
{"_meta":{"channels":[{"id":"transfers","number":1,"name":"Channel 1","line":"x"},{"id":"audio","number":2,"name":"Channel 2"}]},
 "shows":{"a":{"slug":"a","name":"Show A","line":null,"channel":"transfers"},"b":{"slug":"b","name":"Show B"}},
 "programme_order":["p0","p1","p2","p3"],
 "programmes":{
  "p0":{"id":"p0","title":"Zero","seconds":600,"nominal_minutes":10,"channel":1},
  "p1":{"id":"p1","title":"One","seconds":300,"clean_start":20,"clean_end":10,"channel":1},
  "p2":{"id":"p2","nominal_minutes":5,"channel":1,"title":null},
  "p3":{"id":"p3","title":"Three","seconds":60}},
 "days":[
  {"date":"2026-10-10","weekday":"Saturday","channels":{"transfers":[
    {"start":"06:00","start_minute":360,"minutes":60,"show":"a","programmes":[0,1,2]},
    {"start":"07:00","start_minute":420,"minutes":60,"show":"b","programmes":[3]},
    {"start":"23:00","start_minute":1380,"minutes":60,"show":"a","programmes":[2]}],
   "audio":[{"start":"06:00","start_minute":360,"minutes":30,"show":"b","programmes":[3]}]}},
  {"date":"2026-10-11","channels":{"transfers":[{"start":"00:00","start_minute":0,"minutes":1440,"show":"unknown-show","programmes":[0]}]}},
  {"date":"2026-02-28","channels":{"transfers":[{"start":"00:00","start_minute":0,"minutes":1440,"show":"a","programmes":[3]}]}},
  {"date":"2026-03-01","channels":{"transfers":[{"start":"00:00","start_minute":0,"minutes":1440,"show":"b","programmes":[3]}]}},
  {"date":"2028-02-28","channels":{"transfers":[{"start":"00:00","start_minute":0,"minutes":1440,"show":"a","programmes":[3]}]}},
  {"date":"2028-02-29","channels":{"transfers":[{"start":"00:00","start_minute":0,"minutes":1440,"show":"b","programmes":[3]}]}},
  {"date":"2028-03-01","channels":{"transfers":[{"start":"00:00","start_minute":0,"minutes":1440,"show":"a","programmes":[3]}]}},
  {"date":"2026-04-30","channels":{"transfers":[{"start":"00:00","start_minute":0,"minutes":1440,"show":"a","programmes":[3]}]}},
  {"date":"2026-05-01","channels":{"transfers":[{"start":"00:00","start_minute":0,"minutes":1440,"show":"b","programmes":[3]}]}},
  {"date":"2026-12-31","channels":{"transfers":[{"start":"00:00","start_minute":0,"minutes":1440,"show":"a","programmes":[3]}]}},
  {"date":"2027-01-01","channels":{"transfers":[{"start":"00:00","start_minute":0,"minutes":1440,"show":"b","programmes":[3]}]}},
  {"date":"2026-02-30","channels":{"transfers":[{"start":"00:00","start_minute":0,"minutes":1440,"show":"a","programmes":[3]}]}},
  {"date":"2026-09-01","channels":{"transfers":[{"start":"00:00","start_minute":0,"minutes":60,"show":"a","programmes":[0]},{"start":"00:00","start_minute":0,"minutes":60,"show":"b","programmes":[1]}]}}]}
"""#

func syntheticSchedule() throws -> Programming { try decode(Programming.self, syntheticJSON) }

func programmeWithoutATitleDecodes() throws {
    let p = try syntheticSchedule()
    try expectEqual(p.programmes["p2"]?.title, "")   // "title": null
    try expectEqual(p.programmes["p3"]?.title, "Three")
    try expectEqual(p.programmes["p3"]?.seconds, 60)
    try expectEqual(p.programmes["p3"]?.channel, nil)
    let absent = try decode(Programming.Programme.self, #"{"id":"x","play_url":"https://example.com/x"}"#)
    try expectEqual(absent.title, "")
    try expectEqual(absent.play_url, "https://example.com/x")
    // Everything else stays strict: a wrong type is a fault, not a default.
    do {
        _ = try decode(Programming.Programme.self, #"{"id":"x","seconds":"long"}"#)
        throw Failure(description: "a string in `seconds` decoded")
    } catch is DecodingError {}
    do {
        _ = try decode(Programming.Programme.self, #"{"title":"no id"}"#)
        throw Failure(description: "a programme without an id decoded")
    } catch is DecodingError {}
}

func positionInSlotWalksAndWrapsTheRoster() throws {
    let p = try syntheticSchedule()
    let slot = try require(StationClock.slotAt(p, channel: "transfers", iso: "2026-10-10", minute: 360))
    let start = 360 * 60
    // 600 + 270 + 300 = 1170 s round.
    let cases: [(second: Int, index: Int, into: Double)] = [
        (start - 500, 0, 0),          // before the slot clamps to its start
        (start, 0, 0), (start + 599, 0, 599), (start + 600, 1, 0), (start + 869, 1, 269),
        (start + 870, 2, 0), (start + 1169, 2, 299),
        (start + 1170, 0, 0),         // a short roster runs round again
        (start + 1170 + 650, 1, 50),
        (start + 3599, 0, 89),             // 3599 - 3 * 1170
    ]
    for c in cases {
        let position = StationClock.positionInSlot(p, slot: slot, second: c.second)
        try expectEqual(position.index, c.index, "second \(c.second)")
        try expectClose(position.into, c.into)
    }
    let empty = Programming.Slot(start: "06:00", start_minute: 360, minutes: 60, show: "a", programmes: [])
    try expectEqual(StationClock.positionInSlot(p, slot: empty, second: start + 100).index, 0)
    try expectEqual(StationClock.positionInSlot(p, slot: empty, second: start + 100).into, 0)
    // An index outside programme_order is an unknown programme: eight minutes, like the JS.
    let strange = Programming.Slot(start: "06:00", start_minute: 360, minutes: 60, show: "a", programmes: [99, 0])
    let position = StationClock.positionInSlot(p, slot: strange, second: start + 500)
    try expectEqual(position.index, 1)   // 500 s in: past the 480 s unknown programme, 20 s into p0
    try expectClose(position.into, 20)
}

func slotAtAndOnAirOnTheSyntheticSchedule() throws {
    let p = try syntheticSchedule()
    try expectEqual(StationClock.slotAt(p, channel: "transfers", iso: "2026-10-10", minute: 359)?.start, nil)
    try expectEqual(StationClock.slotAt(p, channel: "transfers", iso: "2026-10-10", minute: 360)?.start, "06:00")
    try expectEqual(StationClock.slotAt(p, channel: "transfers", iso: "2026-10-10", minute: 419)?.start, "06:00")
    try expectEqual(StationClock.slotAt(p, channel: "transfers", iso: "2026-10-10", minute: 420)?.start, "07:00")
    try expectEqual(StationClock.slotAt(p, channel: "transfers", iso: "2026-10-10", minute: 480)?.start, nil)
    try expectEqual(StationClock.slotAt(p, channel: "nope", iso: "2026-10-10", minute: 360)?.start, nil)
    try expectEqual(StationClock.slotAt(p, channel: "transfers", iso: "2026-10-09", minute: 360)?.start, nil)
    try expectEqual(StationClock.channelId(p, number: 1), "transfers")
    try expectEqual(StationClock.channelId(p, number: 2), "audio")
    try expectEqual(StationClock.channelId(p, number: 3), nil)
    try expectEqual(StationClock.day(p, iso: "2026-10-10")?.weekday, "Saturday")
    try expectEqual(StationClock.day(p, iso: "2026-10-10")?.channels["audio"]?.count, 1)

    // 06:12:30 is 750 s into the slot: past p0 (600) and 150 s into p1, which is read from 20 s in.
    let air = try require(StationClock.onAir(p, channel: 1, at: pkt(2026, 10, 10, 6, 12, 30)))
    try expectEqual(air.channelId, "transfers")
    try expectEqual(air.date, "2026-10-10")
    try expectEqual(air.rosterIndex, 1)
    try expectEqual(air.programmeId, "p1")
    try expectEqual(air.programme?.title, "One")
    try expectEqual(air.show?.name, "Show A")
    try expectClose(air.into, 150)
    try expectClose(air.seekTo, 170)
    try expectEqual([air.startLabel, air.endLabel, air.nextStart ?? "-"], ["06:00", "07:00", "07:00"])
    try expectEqual(air.nextShow?.slug, "b")
    try expectEqual(StationClock.returnTime(p, channelId: "transfers", at: pkt(2026, 10, 10, 6, 12, 30)), "07:00")
    try expectEqual(StationClock.onAir(p, channel: 1, at: pkt(2026, 10, 10, 6, 12, 30)), StationClock.onAir(p, channelId: "transfers", at: pkt(2026, 10, 10, 6, 12, 30)))

    // Off air is nil with a return time, on a number the schedule lacks and on a day it lacks.
    try expectEqual(StationClock.onAir(p, channel: 1, at: pkt(2026, 10, 10, 8, 0, 0)), nil)
    try expectEqual(StationClock.returnTime(p, channelId: "transfers", at: pkt(2026, 10, 10, 8, 0, 0)), "23:00")
    try expectEqual(StationClock.onAir(p, channel: 3, at: pkt(2026, 10, 10, 6, 30, 0)), nil)
    try expectEqual(StationClock.onAir(p, channel: 1, at: pkt(2026, 10, 9, 6, 30, 0)), nil)
    try expectEqual(StationClock.returnTime(p, channelId: "transfers", at: pkt(2026, 10, 9, 6, 30, 0)), nil)

    // The show may be missing from `shows`; the programme still airs.
    let unknownShow = try require(StationClock.onAir(p, channel: 1, at: pkt(2026, 10, 11, 12, 0, 0)))
    try expectEqual(unknownShow.show, nil)
    try expectEqual(unknownShow.programmeId, "p0")
    // End of the grid: the last strip of the last day has no next strip.
    let late = try require(StationClock.onAir(p, channel: 1, at: pkt(2026, 10, 11, 23, 59, 59)))
    try expectEqual(late.nextStart, nil)
    try expectEqual(late.endLabel, "00:00")
    // On the last day of the grid the next strip is the first of the next calendar day.
    let rollover = try require(StationClock.onAir(p, channel: 1, at: pkt(2026, 10, 10, 23, 30, 0)))
    try expectEqual(rollover.nextStart, "00:00")
    try expectEqual(rollover.nextShow?.slug, nil)   // 2026-10-11's strip names a show `shows` lacks
}

func nextSlotRollsOverEveryKindOfDayEnd() throws {
    let p = try syntheticSchedule()
    // From the last minute of a day: the next calendar day, across month, leap-day and year ends.
    let rollovers: [(from: String, to: String)] = [
        ("2026-02-28", "2026-03-01"),   // 2026 is not a leap year
        ("2028-02-28", "2028-02-29"),   // 2028 is
        ("2028-02-29", "2028-03-01"),
        ("2026-04-30", "2026-05-01"),
        ("2026-12-31", "2027-01-01"),
    ]
    for r in rollovers {
        let next = try require(StationClock.nextSlot(p, channel: "transfers", iso: r.from, minute: 1439), r.from)
        try expectEqual(next.date, r.to, r.from)
    }
    // Nothing after the last day, an unknown day, an unknown channel, and a date that is not a date.
    try expectEqual(StationClock.nextSlot(p, channel: "transfers", iso: "2027-01-01", minute: 1439) == nil, true)
    try expectEqual(StationClock.nextSlot(p, channel: "transfers", iso: "2031-01-01", minute: 0) == nil, true)
    try expectEqual(StationClock.nextSlot(p, channel: "nope", iso: "2026-10-10", minute: 0) == nil, true)
    try expectEqual(StationClock.nextSlot(p, channel: "transfers", iso: "2026-02-30", minute: 1439) == nil, true)
    // Within a day: the first strip that starts strictly after the minute.
    let within = try require(StationClock.nextSlot(p, channel: "transfers", iso: "2026-10-10", minute: 360))
    try expectEqual([within.slot.start, within.date], ["07:00", "2026-10-10"])
    let atStart = try require(StationClock.nextSlot(p, channel: "transfers", iso: "2026-10-10", minute: 420))
    try expectEqual(atStart.slot.start, "23:00")
    // Two strips starting at the same minute: the earlier one in the file, as a stable sort gives.
    let tie = try require(StationClock.nextSlot(p, channel: "transfers", iso: "2026-09-01", minute: -1))
    try expectEqual(tie.slot.programmes, [0])
}

func followingWalksTheRosterAndHandsBackToTheClock() throws {
    let p = try syntheticSchedule()
    let inside = pkt(2026, 10, 10, 6, 12, 30)       // p1, 150 s in
    let current = try require(StationClock.onAir(p, channel: 1, at: inside))
    // Still inside the slot: the next roster entry, from its head, read from its clean_start.
    let next = try require(StationClock.following(current, in: p, at: inside))
    try expectEqual(next.rosterIndex, 2)
    try expectEqual(next.programmeId, "p2")
    try expectEqual(next.into, 0)
    try expectEqual(next.seekTo, 0)
    try expectEqual(next.slot, current.slot)
    try expectEqual([next.startLabel, next.endLabel, next.nextStart ?? "-"], ["06:00", "07:00", "07:00"])
    // The last entry wraps to the first, and a clean_start is the seek point.
    let wrapped = try require(StationClock.following(next, in: p, at: inside))
    try expectEqual(wrapped.rosterIndex, 0)
    try expectEqual(wrapped.programmeId, "p0")
    let intoP1 = try require(StationClock.following(wrapped, in: p, at: inside))
    try expectEqual(intoP1.programmeId, "p1")
    try expectEqual(intoP1.seekTo, 20)
    try expectEqual(intoP1.into, 0)
    // A one-programme roster replays itself.
    let single = try require(StationClock.onAir(p, channel: 1, at: pkt(2026, 10, 10, 7, 10, 0)))
    try expectEqual(try require(StationClock.following(single, in: p, at: pkt(2026, 10, 10, 7, 10, 0))).rosterIndex, 0)
    // Past the slot's end, or the same minutes on another day: the clock answers.
    let after = pkt(2026, 10, 10, 7, 0, 0)
    try expectEqual(StationClock.following(current, in: p, at: after), StationClock.onAir(p, channelId: "transfers", at: after))
    try expectEqual(StationClock.following(current, in: p, at: after)?.programmeId, "p3")
    let nextDay = pkt(2026, 10, 11, 6, 12, 30)
    try expectEqual(StationClock.following(current, in: p, at: nextDay), StationClock.onAir(p, channelId: "transfers", at: nextDay))
    try expectEqual(StationClock.following(current, in: p, at: nextDay)?.date, "2026-10-11")
    // Off air after the slot: nil.
    try expectEqual(StationClock.following(current, in: p, at: pkt(2026, 10, 10, 8, 30, 0)), nil)
}

func upcomingListsTheNextStripsInOrder() throws {
    let p = try syntheticSchedule()
    func labels(_ strips: [ScheduleStrip]) -> [String] { strips.map { "\($0.date) \($0.startLabel)-\($0.endLabel) \($0.show?.slug ?? "-")" } }
    // On air at 06:12:30: the rest of the day, then across midnight into the last day held.
    try expectEqual(labels(StationClock.upcoming(p, channelId: "transfers", at: pkt(2026, 10, 10, 6, 12, 30), count: 3)),
                    ["2026-10-10 07:00-08:00 b", "2026-10-10 23:00-00:00 a", "2026-10-11 00:00-00:00 -"])
    // The first strip up next is the one OnAir already names, everywhere on the hand-made day.
    var t = pkt(2026, 10, 10, 0, 0, 0)
    while t < pkt(2026, 10, 11, 0, 0, 0) {
        defer { t = t.addingTimeInterval(397) }
        let first = StationClock.upcoming(p, channelId: "transfers", at: t, count: 1).first
        if let air = StationClock.onAir(p, channelId: "transfers", at: t) {
            try expectEqual(first?.startLabel, air.nextStart)
            try expectEqual(first?.show?.slug, air.nextShow?.slug)
        } else {
            try expectEqual(first?.startLabel, StationClock.returnTime(p, channelId: "transfers", at: t))
        }
    }
    // Off air between strips: up next is the strip it returns with.
    try expectEqual(labels(StationClock.upcoming(p, channelId: "transfers", at: pkt(2026, 10, 10, 8, 0, 0), count: 1)),
                    ["2026-10-10 23:00-00:00 a"])
    // The last strip of the day hands over to the first of the next day...
    try expectEqual(labels(StationClock.upcoming(p, channelId: "transfers", at: pkt(2026, 10, 10, 23, 30, 0), count: 5)),
                    ["2026-10-11 00:00-00:00 -"])
    // ...and the last strip of the grid has nothing after it, however many are asked for.
    try expectEqual(StationClock.upcoming(p, channelId: "transfers", at: pkt(2026, 10, 11, 12, 0, 0), count: 5).count, 0)
    // Month and year boundaries the grid holds are crossed; the day after them is not invented.
    try expectEqual(labels(StationClock.upcoming(p, channelId: "transfers", at: pkt(2026, 4, 30, 12, 0, 0), count: 3)),
                    ["2026-05-01 00:00-00:00 b"])
    try expectEqual(labels(StationClock.upcoming(p, channelId: "transfers", at: pkt(2026, 12, 31, 12, 0, 0), count: 3)),
                    ["2027-01-01 00:00-00:00 b"])
    try expectEqual(labels(StationClock.upcoming(p, channelId: "transfers", at: pkt(2028, 2, 28, 12, 0, 0), count: 2)),
                    ["2028-02-29 00:00-00:00 b", "2028-03-01 00:00-00:00 a"])
    // Nothing for a count of zero, an unknown channel, or a day the schedule does not hold.
    try expectEqual(StationClock.upcoming(p, channelId: "transfers", at: pkt(2026, 10, 10, 6, 0, 0), count: 0).count, 0)
    try expectEqual(StationClock.upcoming(p, channelId: "nope", at: pkt(2026, 10, 10, 6, 0, 0), count: 3).count, 0)
    try expectEqual(StationClock.upcoming(p, channelId: "transfers", at: pkt(2026, 10, 9, 6, 0, 0), count: 3).count, 0)
    // Channel 2 airs one strip and then nothing: off air with no return, and no list.
    try expectEqual(StationClock.upcoming(p, channelId: "audio", at: pkt(2026, 10, 10, 6, 10, 0), count: 3).count, 0)
}

func secondsLeftCountsDownToTheSlotEnd() throws {
    let p = try syntheticSchedule()
    let air = try require(StationClock.onAir(p, channel: 1, at: pkt(2026, 10, 10, 6, 12, 30)))
    try expectEqual(StationClock.secondsLeft(in: air, at: pkt(2026, 10, 10, 6, 12, 30)), 47 * 60 + 30)
    try expectEqual(StationClock.secondsLeft(in: air, at: pkt(2026, 10, 10, 6, 59, 59)), 1)
    // The moment the slot ends the clock has left it, and so before it began, and on another day.
    try expectEqual(StationClock.secondsLeft(in: air, at: pkt(2026, 10, 10, 7, 0, 0)), nil)
    try expectEqual(StationClock.secondsLeft(in: air, at: pkt(2026, 10, 10, 5, 59, 59)), nil)
    try expectEqual(StationClock.secondsLeft(in: air, at: pkt(2026, 10, 11, 6, 12, 30)), nil)
    // And at that moment the clock has the next strip on air: now is never the slot just gone.
    try expectEqual(StationClock.onAir(p, channel: 1, at: pkt(2026, 10, 10, 7, 0, 0))?.startLabel, "07:00")
    // The last strip of the day ends at midnight.
    let late = try require(StationClock.onAir(p, channel: 1, at: pkt(2026, 10, 10, 23, 59, 0)))
    try expectEqual(StationClock.secondsLeft(in: late, at: pkt(2026, 10, 10, 23, 59, 59)), 1)
    try expectEqual(StationClock.secondsLeft(in: late, at: pkt(2026, 10, 11, 0, 0, 0)), nil)
}

func realUpcomingAgreesWithOnAir() throws {
    let p = try realProgramming("2026-10")
    var checked = 0
    for number in [1, 2] {
        let id = try require(StationClock.channelId(p, number: number))
        var t = pkt(2026, 10, 1, 0, 0, 0)
        while t <= pkt(2026, 10, 31, 23, 59, 59) {
            defer { t = t.addingTimeInterval(3517) }
            let strips = StationClock.upcoming(p, channelId: id, at: t, count: 4)
            let expectedFirst = StationClock.onAir(p, channelId: id, at: t)?.nextStart ?? StationClock.returnTime(p, channelId: id, at: t)
            try expectEqual(strips.first?.startLabel, expectedFirst)
            // Soonest first, and every strip starts after now.
            let now = StationClock.stationNow(t)
            let keys = strips.map { "\($0.date) \(StationClock.clockLabel($0.slot.start_minute))" }
            try expectEqual(keys, keys.sorted())
            try expect(strips.allSatisfy { $0.date > now.iso || $0.slot.start_minute > now.minutes })
            checked += 1
        }
    }
    print("      \(checked) instants across October")
}

// MARK: - Station clock: differential against the site's own JS

struct Fixture: Decodable {
    struct Case: Decodable {
        struct Expect: Decodable, Equatable {
            let channelId: String
            let date: String
            let programmeId: String
            let rosterIndex: Int
            let into: Double
            let seekTo: Double
            let startLabel: String
            let endLabel: String
            let nextStart: String?
            let slotStart: String
            let slotStartMinute: Int
        }

        let nowMs: Double
        let channel: Int
        let expect: Expect?
    }

    let source: String
    let generatedFrom: String
    let programming: Programming
    let cases: [Case]
}

var loadedFixture: Fixture?
func fixture() throws -> Fixture {
    if let loadedFixture { return loadedFixture }
    let decoded = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: fixtureURL))
    loadedFixture = decoded
    return decoded
}

/// What differs between the Swift clock and the JS answer for one case. Empty means they agree.
func mismatches(_ p: Programming, _ c: Fixture.Case) -> [String] {
    let air = StationClock.onAir(p, channel: c.channel, at: Date(timeIntervalSince1970: c.nowMs / 1000))
    guard let want = c.expect else {
        if let air { return ["expected off air, swift has \(air.programmeId)"] }
        return []
    }
    guard let air else { return ["expected \(want.programmeId), swift is off air"] }
    var out: [String] = []
    func check<T: Equatable>(_ name: String, _ swift: T, _ js: T) {
        if swift != js { out.append("\(name): swift \(swift), js \(js)") }
    }
    check("channelId", air.channelId, want.channelId)
    check("date", air.date, want.date)
    check("programmeId", air.programmeId, want.programmeId)
    check("rosterIndex", air.rosterIndex, want.rosterIndex)
    check("startLabel", air.startLabel, want.startLabel)
    check("endLabel", air.endLabel, want.endLabel)
    check("nextStart", air.nextStart, want.nextStart)
    check("slotStart", air.slot.start, want.slotStart)
    check("slotStartMinute", air.slot.start_minute, want.slotStartMinute)
    if abs(air.into - want.into) > 1e-6 { out.append("into: swift \(air.into), js \(want.into)") }
    if abs(air.seekTo - want.seekTo) > 1e-6 { out.append("seekTo: swift \(air.seekTo), js \(want.seekTo)") }
    return out
}

func stationClockMatchesTheJS() throws {
    let f = try fixture()
    try expectEqual(f.source, "programming-2026-10.json")
    try expectEqual(f.generatedFrom, "kj-station-clock.js")
    let cases = f.cases
    try expect(cases.count >= 400, "only \(cases.count) cases; refusing to pass")
    var failures: [String] = []
    var onAir = 0, offAir = 0, trimmed = 0
    for (position, c) in cases.enumerated() {
        let diff = mismatches(f.programming, c)
        if !diff.isEmpty { failures.append("case \(position) nowMs \(Int(c.nowMs)) ch \(c.channel): " + diff.joined(separator: "; ")) }
        if let want = c.expect { onAir += 1; if want.seekTo != want.into { trimmed += 1 } } else { offAir += 1 }
    }
    print("      \(cases.count) cases against kj-station-clock.js: \(onAir) on air, \(offAir) off air, \(trimmed) joined past a clean_start")
    try expect(failures.isEmpty, "\(failures.count) of \(cases.count) differ; first: " + failures.prefix(3).joined(separator: " | "))
    // The comparison must be able to say yes to both kinds of case, or it proves nothing.
    try expect(onAir >= 300, "only \(onAir) on-air cases")
    try expect(offAir >= 6, "only \(offAir) off-air cases")
    try expect(trimmed >= 1, "no case exercises clean_start")
    try expect(Set(cases.map(\.channel)) == [1, 2], "both channels must be present")
    // Every one of those programmes came out of the decoded trim, so the trim carried what it needed.
    for c in cases { if let want = c.expect { _ = try require(f.programming.programmes[want.programmeId], want.programmeId) } }
}

/// A check that cannot fail is decoration: bend each field of a real expectation and the
/// comparator must object; leave it alone and it must not.
func differentialComparatorCanFail() throws {
    let f = try fixture()
    let c = try require(f.cases.first { $0.expect != nil && $0.expect!.seekTo != $0.expect!.into } ?? f.cases.first { $0.expect != nil })
    let want = try require(c.expect)
    try expectEqual(mismatches(f.programming, c), [])
    func bent(_ edit: (Fixture.Case.Expect) -> Fixture.Case.Expect) -> Fixture.Case {
        Fixture.Case(nowMs: c.nowMs, channel: c.channel, expect: edit(want))
    }
    func with(channelId: String? = nil, date: String? = nil, programmeId: String? = nil, rosterIndex: Int? = nil, into: Double? = nil,
              seekTo: Double? = nil, startLabel: String? = nil, endLabel: String? = nil, nextStart: String?? = nil) -> Fixture.Case {
        bent { e in
            Fixture.Case.Expect(channelId: channelId ?? e.channelId, date: date ?? e.date, programmeId: programmeId ?? e.programmeId,
                                rosterIndex: rosterIndex ?? e.rosterIndex, into: into ?? e.into, seekTo: seekTo ?? e.seekTo,
                                startLabel: startLabel ?? e.startLabel, endLabel: endLabel ?? e.endLabel,
                                nextStart: nextStart ?? e.nextStart, slotStart: e.slotStart, slotStartMinute: e.slotStartMinute)
        }
    }
    let bends: [(String, Fixture.Case)] = [
        ("channelId", with(channelId: "x")), ("date", with(date: "1999-01-01")), ("programmeId", with(programmeId: "x")),
        ("rosterIndex", with(rosterIndex: want.rosterIndex + 1)), ("into", with(into: want.into + 0.01)),
        ("seekTo", with(seekTo: want.seekTo + 0.01)), ("startLabel", with(startLabel: "99:99")), ("endLabel", with(endLabel: "99:99")),
        ("nextStart", with(nextStart: .some(nil))), ("nextStart value", with(nextStart: .some("99:99"))),
        ("off air expected", Fixture.Case(nowMs: c.nowMs, channel: c.channel, expect: nil)),
    ]
    for (name, bad) in bends {
        // `nextStart: nil` is only a bend when the real answer has a next strip.
        if name == "nextStart", want.nextStart == nil { continue }
        try expect(!mismatches(f.programming, bad).isEmpty, "a bent \(name) was not noticed")
    }
    let off = try require(f.cases.first { $0.expect == nil })
    try expectEqual(mismatches(f.programming, off), [])
    let onAirNow = Fixture.Case(nowMs: off.nowMs, channel: off.channel, expect: want)
    try expect(!mismatches(f.programming, onAirNow).isEmpty, "an on-air expectation at an off-air instant was not noticed")
}

func stationClockEdgesAndTheEndOfTheGrid() throws {
    let f = try fixture()
    let p = f.programming
    // 10-10 is the first kept day; before 06:00 it is the late strip filed from the same day.
    for number in [1, 2] {
        let id = try require(StationClock.channelId(p, number: number))
        try expectEqual(StationClock.onAir(p, channel: number, at: pkt(2026, 10, 10, 6, 0, 0))?.startLabel, "06:00")
        try expectEqual(StationClock.onAir(p, channel: number, at: pkt(2026, 10, 10, 6, 0, 0))?.into, 0)
        try expect(StationClock.onAir(p, channel: number, at: pkt(2026, 10, 10, 5, 59, 59))?.endLabel == "06:00")
        try expectEqual(StationClock.returnTime(p, channelId: id, at: pkt(2026, 10, 10, 5, 59, 59)), "06:00")
        // The end of the trimmed grid, checked against the JS by hand when this was written:
        // the last kept day's last strip airs and has nothing after it.
        let last = try require(StationClock.onAir(p, channel: number, at: pkt(2026, 10, 13, 23, 59, 30)))
        try expectEqual(last.nextStart, nil)
        try expectEqual(last.nextShow, nil)
        try expectEqual(last.endLabel, "00:00")
        try expectEqual(StationClock.returnTime(p, channelId: id, at: pkt(2026, 10, 13, 23, 59, 30)), nil)
        try expectEqual(StationClock.onAir(p, channel: number, at: pkt(2026, 10, 14, 0, 0, 0)), nil)
    }
    let one = try require(StationClock.onAir(p, channel: 1, at: pkt(2026, 10, 13, 23, 59, 30)))
    try expectEqual([one.startLabel, String(one.rosterIndex)], ["23:00", "24"])
    try expectClose(one.into, 100.9, tolerance: 1e-6)
    let two = try require(StationClock.onAir(p, channel: 2, at: pkt(2026, 10, 13, 23, 59, 30)))
    try expectEqual([two.startLabel, String(two.rosterIndex)], ["22:10", "1"])
    try expectClose(two.into, 2920.8, tolerance: 1e-6)
    // And the rollover: the last strip of a day names the next day's first strip.
    try expectEqual(StationClock.onAir(p, channel: 1, at: pkt(2026, 10, 12, 23, 59, 59))?.nextStart, "00:00")
}

func followingAgreesWithTheRosterAtEveryFixtureInstant() throws {
    let f = try fixture()
    let p = f.programming
    var checked = 0, wrapped = 0, afterEnd = 0
    for c in f.cases {
        guard c.expect != nil else { continue }
        let date = Date(timeIntervalSince1970: c.nowMs / 1000)
        let air = try require(StationClock.onAir(p, channel: c.channel, at: date))
        let count = air.slot.programmes.count
        let next = try require(StationClock.following(air, in: p, at: date), "case \(Int(c.nowMs))")
        let index = (air.rosterIndex + 1) % count
        if index == 0 { wrapped += 1 }
        let id = p.programme_order[air.slot.programmes[index]]
        try expectEqual(next.rosterIndex, index)
        try expectEqual(next.programmeId, id)
        try expectEqual(next.into, 0)
        try expectEqual(next.seekTo, p.programmes[id]?.clean_start ?? 0)
        try expectEqual(next.slot, air.slot)
        try expectEqual([next.date, next.startLabel, next.endLabel, next.channelId], [air.date, air.startLabel, air.endLabel, air.channelId])
        try expectEqual(next.nextStart, air.nextStart)
        try expectEqual(next.show, air.show)
        checked += 1
        // One second past the slot's last second the clock answers, never the roster.
        if checked % 5 == 0 {
            let parts = air.date.split(separator: "-").compactMap { Int($0) }
            let midnight = pkt(parts[0], parts[1], parts[2])
            let past = midnight.addingTimeInterval(Double((air.slot.start_minute + air.slot.minutes) * 60 + 1))
            try expectEqual(StationClock.following(air, in: p, at: past), StationClock.onAir(p, channelId: air.channelId, at: past))
            // The same wall-clock minutes a day later are another slot of another day.
            let tomorrow = date.addingTimeInterval(86_400)
            try expectEqual(StationClock.following(air, in: p, at: tomorrow), StationClock.onAir(p, channelId: air.channelId, at: tomorrow))
            afterEnd += 1
        }
    }
    print("      following(): \(checked) instants walked the roster (\(wrapped) wrapped to the head), \(afterEnd) handed back to the clock")
    try expect(checked >= 400, "only \(checked) checked")
    try expect(wrapped >= 1, "no roster wrapped")
}

// MARK: - Real files

var realProgrammingCache: [String: Programming] = [:]
func realProgramming(_ month: String) throws -> Programming {
    if let cached = realProgrammingCache[month] { return cached }
    let decoded = try JSONDecoder().decode(Programming.self, from: try realFile("data/khajistan-tv/programming-\(month).json"))
    realProgrammingCache[month] = decoded
    return decoded
}

func realReceiverIndexDecodes() throws {
    let data = try realFile("data/open-frequencies/receiver-index.json")
    let index = try JSONDecoder().decode(ReceiverIndex.self, from: data)
    let raw = try require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    let rawRegions = try require(raw["regions"] as? [[String: Any]])
    let rawFiles = try require(raw["regionFiles"] as? [String: String])
    let listedIds = rawRegions.compactMap { $0["id"] as? String }.filter { rawFiles[$0] != nil }
    try expectEqual(index.regions.count, rawRegions.count)
    try expectEqual(index.listedRegions.map(\.id), listedIds)
    try expect(index.listedRegions.count > 20, "only \(index.listedRegions.count) listed regions")
    try expect(index.listedRegions.count < index.regions.count, "every region is listed; the unlisted ones are the people's regions")
    for region in index.listedRegions {
        let url = try require(index.shardURL(regionId: region.id), region.id)
        try expectEqual(url.host, "khajistan-archive.pages.dev")
        try expectEqual(url.path, rawFiles[region.id])
    }
    for region in index.regions where rawFiles[region.id] == nil {
        try expectEqual(index.shardURL(regionId: region.id), nil, region.id)
    }
    for (id, path) in (raw["cameraFiles"] as? [String: String]) ?? [:] {
        try expectEqual(index.cameraURL(regionId: id)?.path, path)
    }
    // The line is rebuilt here from the raw counts by a separate route.
    let rawCounts = try require(raw["regionCounts"] as? [String: [String: Any]])
    for (id, entry) in rawCounts {
        let medium = (entry["byMedium"] as? [String: Int]) ?? [:]
        var pieces: [String] = []
        if let n = medium["tv"], n > 0 { pieces.append(n == 1 ? "1 television" : "\(n) television") }
        if let n = medium["radio"], n > 0 { pieces.append("\(n) radio") }
        if let n = medium["camera"], n > 0 { pieces.append(n == 1 ? "1 camera" : "\(n) cameras") }
        try expectEqual(index.mediumLine(regionId: id), pieces.joined(separator: " · "), id)
    }
    try expect(index.totals.channels > 0 && index.totals.live > 0 && index.totals.byMedium["radio"] ?? 0 > 0)
    let tiers = Set(index.regions.map(\.tier))
    try expect(tiers.isSubset(of: ["heartbeat", "core", "islamicate"]), "unexpected tiers \(tiers)")
}

func realShardsAndWithdrawalFeedsDecode() throws {
    let indus = try JSONDecoder().decode(RegionShard.self, from: try realFile("data/open-frequencies/regions/indus.json"))
    try expectEqual(indus.region, "indus")
    try expect(indus.channels.count > 50, "only \(indus.channels.count) channels")
    try expect(indus.channels.allSatisfy { $0.mediaType == "tv" || $0.mediaType == "radio" })
    let cameras = try JSONDecoder().decode(RegionShard.self, from: try realFile("data/open-frequencies/regions/anatolia-camera.json"))
    try expectEqual(cameras.region, "anatolia")
    try expect(!cameras.channels.isEmpty && cameras.channels.allSatisfy { $0.mediaType == "camera" })

    let denylist = try JSONDecoder().decode(Denylist.self, from: try realFile("data/open-frequencies/denylist.json"))
    let offAir = try JSONDecoder().decode(OffAir.self, from: try realFile("data/open-frequencies/off-air-suspects.json"))
    let health = try JSONDecoder().decode(Health.self, from: try realFile("data/open-frequencies/health.json"))
    let controls = Controls(denylist: denylist, offAir: offAir, health: health)
    try expectEqual(controls.denied, Set(denylist.disabledChannelIds).union(offAir.offAirChannelIds))
    try expect(controls.health.count > 1000, "only \(controls.health.count) health results")

    for shard in [indus, cameras] {
        let eligible = ReceiverRules.eligible(shard.channels, controls: controls)
        try expect(!eligible.isEmpty, "\(shard.region): nothing eligible")
        try expect(eligible.count <= shard.channels.count)
        try expectEqual(Set(eligible.map(\.id)).count, eligible.count)
        try expect(eligible.allSatisfy { $0.activeStream != nil && !controls.denied.contains($0.id) })
        try expect(eligible.allSatisfy { controls.health[$0.id]?.status != "offline" && controls.health[$0.id]?.status != "blocked" })
        try expect(eligible.allSatisfy { ($0.manualDisabled ?? false) == false })
        // The withdrawn are exactly the channels a rule names: recount them by a separate route.
        let dropped = Set(shard.channels.map(\.id)).subtracting(eligible.map(\.id))
        for channel in shard.channels where dropped.contains(channel.id) {
            let check = controls.health[channel.id]
            let status = check?.status ?? channel.healthStatus
            let reason = controls.denied.contains(channel.id) || channel.manualDisabled == true
                || (channel.publicationStatus ?? "published") != "published"
                || status == "offline" || status == "blocked" || (check?.deliveryRatio ?? 1) < 0.5
                || channel.activeStream == nil
            try expect(reason, "\(channel.id) was dropped for no reason")
        }
    }
}

func everyRealShardDecodes() throws {
    let directory = repoRoot.appendingPathComponent("data/open-frequencies/regions")
    guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else {
        throw Skip(reason: "data/open-frequencies/regions is not in this checkout")
    }
    var channels = 0, shards = 0
    var ids = Set<String>()
    for name in names.sorted() where name.hasSuffix(".json") {
        let shard = try JSONDecoder().decode(RegionShard.self, from: try Data(contentsOf: directory.appendingPathComponent(name)))
        channels += shard.channels.count
        shards += 1
        ids.formUnion(shard.channels.map(\.id))
    }
    print("      \(shards) shards, \(channels) channels, \(ids.count) distinct ids")
    try expect(shards > 30 && channels > 1000)
}

func realProgrammingDecodesInEveryMonth() throws {
    let directory = repoRoot.appendingPathComponent("data/khajistan-tv")
    guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else {
        throw Skip(reason: "data/khajistan-tv is not in this checkout")
    }
    let months = names.filter { $0.hasPrefix("programming-2026-") && $0.hasSuffix(".json") }
        .map { String($0.dropFirst("programming-".count).dropLast(".json".count)) }.sorted()
    try expect(!months.isEmpty, "no programming-2026-*.json files")
    var tallies: [String: Int] = [:]
    for month in months {
        let data = try realFile("data/khajistan-tv/programming-\(month).json")
        let p = try JSONDecoder().decode(Programming.self, from: data)
        realProgrammingCache[month] = p
        let raw = try require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let rawProgrammes = try require(raw["programmes"] as? [String: [String: Any]])
        try expectEqual(p.programmes.count, rawProgrammes.count, month)
        try expectEqual(p.programme_order.count, p.programmes.count, month)
        try expectEqual(p._meta.channels.map(\.number), [1, 2], month)
        try expectEqual(p._meta.channels.map(\.id), ["transfers", "audio"], month)
        for id in p.programme_order { _ = try require(p.programmes[id], "\(month): \(id) is in programme_order and not in programmes") }
        for (key, value) in p.programmes { try expectEqual(key, value.id, month) }
        // The titleless programmes are exactly the ones whose raw record has no usable title.
        let rawTitleless = rawProgrammes.filter { (($0.value["title"] as? String) ?? "").isEmpty }.count
        try expectEqual(p.programmes.values.filter { $0.title.isEmpty }.count, rawTitleless, month)
        var slots = 0
        for day in p.days {
            for (channel, strips) in day.channels {
                try expect(channel == "transfers" || channel == "audio", "\(month): channel \(channel)")
                for slot in strips {
                    slots += 1
                    try expect(!slot.programmes.isEmpty && slot.programmes.allSatisfy { $0 >= 0 && $0 < p.programme_order.count },
                               "\(month) \(day.date) \(slot.start): a roster index is out of range")
                    try expect(slot.start_minute >= 0 && slot.minutes > 0 && slot.start_minute + slot.minutes <= 1440)
                    try expect(p.shows[slot.show] != nil, "\(month): slot names an unknown show \(slot.show)")
                    try expectEqual(StationClock.clockLabel(slot.start_minute), slot.start, "\(month) \(day.date)")
                }
            }
        }
        for programme in p.programmes.values {
            switch programme.play_url.flatMap(Transmission.route(for:)) {
            case .tvPlay?: tallies["tv-play", default: 0] += 1
            case .stream?: tallies["stream", default: 0] += 1
            case .direct?: tallies["direct", default: 0] += 1
            case nil: throw Failure(description: "\(month): \(programme.id) has a play_url that does not route: \(programme.play_url ?? "nil")")
            }
        }
        print("      \(month): \(p.days.count) days, \(slots) slots, \(p.programmes.count) programmes, \(rawTitleless) without a title")
    }
    print("      every play_url routed: \(tallies.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", "))")
    try expect((tallies["tv-play"] ?? 0) > 0)
}

func realProgrammingClockInvariants() throws {
    let p = try realProgramming("2026-10")
    var checked = 0, offAir = 0, joinedPastLeader = 0
    for number in [1, 2] {
        var t = pkt(2026, 10, 1, 0, 0, 0)
        let end = pkt(2026, 10, 31, 23, 59, 59)
        while t <= end {
            defer { t = t.addingTimeInterval(1747) }
            guard let air = StationClock.onAir(p, channel: number, at: t) else { offAir += 1; continue }
            checked += 1
            let c = karachi.dateComponents([.year, .month, .day, .hour, .minute, .second], from: t)
            let iso = isoString(c.year ?? 0, c.month ?? 0, c.day ?? 0)
            let minute = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            let programme = try require(air.programme, air.programmeId)
            try expectEqual(air.date, iso)
            try expect(minute >= air.slot.start_minute && minute < air.slot.start_minute + air.slot.minutes)
            try expectEqual(p.programme_order[air.slot.programmes[air.rosterIndex]], air.programmeId)
            try expect(air.into >= 0 && air.into < StationClock.runSeconds(programme), "into \(air.into) of \(StationClock.runSeconds(programme))")
            try expectClose(air.seekTo, (programme.clean_start ?? 0) + air.into, tolerance: 1e-9)
            if let seconds = programme.seconds, seconds > 0, StationClock.runSeconds(programme) > 1 {
                try expect(air.seekTo < seconds - (programme.clean_end ?? 0) + 1e-9, "seeks past the end of \(air.programmeId)")
            }
            if (programme.clean_start ?? 0) > 0 { joinedPastLeader += 1 }
            try expectEqual(air.startLabel, air.slot.start)
            try expectEqual(air.channelId, StationClock.channelId(p, number: number))
            // A next strip exists everywhere except in the last day of the month's file.
            if iso != "2026-10-31" { try expect(air.nextStart != nil, "\(iso) \(air.startLabel) has no next strip") }
        }
    }
    print("      \(checked) instants across October on both channels, \(offAir) off air, \(joinedPastLeader) on a programme with a clean_start")
    try expect(checked > 2500, "only \(checked) instants were on air")
}

// MARK: - Region map

func mp(_ x: Double, _ y: Double) -> MapPoint { MapPoint(x: x, y: y) }

func boxValues(_ box: ViewBox) -> [Double] { [box.minX, box.minY, box.width, box.height] }

func inside(_ point: MapPoint, _ box: ViewBox) -> Bool {
    point.x >= box.minX && point.x <= box.minX + box.width && point.y >= box.minY && point.y <= box.minY + box.height
}

func viewBoxParsesAndRefuses() throws {
    try expectEqual(boxValues(try require(ViewBox("0 0 1000 700"))), [0, 0, 1000, 700])
    try expectEqual(boxValues(try require(ViewBox("-12.0 -12.0 1444.0 949.8"))), [-12, -12, 1444, 949.8])
    try expectEqual(boxValues(try require(ViewBox("0,0,10,5"))), [0, 0, 10, 5])
    // Commas, spaces and line breaks in any mix.
    try expectEqual(boxValues(try require(ViewBox(" 1, 2 ,\n3 ,4 "))), [1, 2, 3, 4])
    // "0 0 x 10 20" has five parts, only four of them numbers; it must not pass for a box.
    let refused = ["", "0 0 0 10", "0 0 10 0", "0 0 -10 5", "a b c d", "1 2 3", "1 2 3 4 5",
                   "0 0 x 10 20", "0 0 nan 10", "0 0 inf 10", "0 0 1e999 10"]
    for text in refused {
        try expect(ViewBox(text) == nil, "\"\(text)\" was accepted")
    }
}

func svgPathAbsoluteSubpaths() throws {
    try expectEqual(SVGPath.polygons("M0,0 L10,0 L10,10 Z"), [[mp(0, 0), mp(10, 0), mp(10, 10)]])
    let two = SVGPath.polygons("M0,0 L10,0 L10,10 Z M20,20 L30,20 L30,30 L20,30 Z")
    try expectEqual(two.map(\.count), [3, 4])
    try expectEqual(two[1], [mp(20, 20), mp(30, 20), mp(30, 30), mp(20, 30)])
    // No Z: the next M closes a polygon, and so does the end of the data.
    try expectEqual(SVGPath.polygons("M0,0 L10,0 L10,10 M20,20 L30,20 L30,30").map(\.count), [3, 3])
    // Coordinates after M repeat as L.
    try expectEqual(SVGPath.polygons("M0,0 10,0 10,10 Z"), [[mp(0, 0), mp(10, 0), mp(10, 10)]])
    // Nothing to draw.
    try expectEqual(SVGPath.polygons(""), [])
    try expectEqual(SVGPath.polygons(" \n "), [])
    try expectEqual(SVGPath.polygons("Z"), [])
}

func svgPathRelativeCommands() throws {
    // m is read from the origin, h and v move along one axis, and z puts the pen back at the
    // start of the polygon so that the next m is read from there; the pair after l repeats as l.
    try expectEqual(SVGPath.polygons("m10,10 h10 v10 h-10 z m5,5 l10,0 0,10 z"), [
        [mp(10, 10), mp(20, 10), mp(20, 20), mp(10, 20)],
        [mp(15, 15), mp(25, 15), mp(25, 25)],
    ])
    // The same pairs after M are absolute and after m relative.
    try expectEqual(SVGPath.polygons("M0,0 10,0 0,10 z"), [[mp(0, 0), mp(10, 0), mp(0, 10)]])
    try expectEqual(SVGPath.polygons("m0,0 10,0 0,10 z"), [[mp(0, 0), mp(10, 0), mp(10, 10)]])
    // Absolute H and V, and H with its number repeated.
    try expectEqual(SVGPath.polygons("M5,5 H15 V15 H5 Z"), [[mp(5, 5), mp(15, 5), mp(15, 15), mp(5, 15)]])
    try expectEqual(SVGPath.polygons("M0,0 H10 20 V10 Z"), [[mp(0, 0), mp(10, 0), mp(20, 0), mp(20, 10)]])
    // A relative move after a subpath with no z is read from its last point.
    try expectEqual(SVGPath.polygons("M10,10 L20,10 L20,20 m5,5 l5,0 l0,5 z"), [
        [mp(10, 10), mp(20, 10), mp(20, 20)],
        [mp(25, 25), mp(30, 25), mp(30, 30)],
    ])
    // A line drawn after Z starts a new polygon where the last one began.
    try expectEqual(SVGPath.polygons("M0,0 L10,0 L10,10 Z L0,10 L5,5 Z"), [
        [mp(0, 0), mp(10, 0), mp(10, 10)],
        [mp(0, 0), mp(0, 10), mp(5, 5)],
    ])
}

func svgPathNumberSyntax() throws {
    // Scientific, signed, and a sign standing in for a separator.
    try expectEqual(SVGPath.polygons("M-1e1,0L0-5L5,5z"), [[mp(-10, 0), mp(0, -5), mp(5, 5)]])
    // A leading point, a second point that starts a new number, an explicit plus, a trailing
    // point, an exponent in either case.
    try expectEqual(SVGPath.polygons("M.5,.5 L1.5.5 L+2,3e-1 L5.,1E+1 Z"),
                    [[mp(0.5, 0.5), mp(1.5, 0.5), mp(2, 0.3), mp(5, 10)]])
    try expectEqual(SVGPath.polygons("M1e-3,0 L0,1e0 L1,1 Z"), [[mp(0.001, 0), mp(0, 1), mp(1, 1)]])
    // Separators in any mix, and none between a command letter and its number.
    try expectEqual(SVGPath.polygons("M 0 , 0\n\tL10,0\r\nL 10 10Z"), [[mp(0, 0), mp(10, 0), mp(10, 10)]])
}

func svgPathDropsShortSubpathsAndStopsOnTheUnreadable() throws {
    // A subpath of two points is not a polygon, and does not stop the read.
    try expectEqual(SVGPath.polygons("M0,0 L10,0 Z"), [])
    try expectEqual(SVGPath.polygons("M0,0 L10,0 Z M0,0 L10,0 L10,10 Z").map(\.count), [3])
    // An unsupported command stops the read: what came before stays, nothing after it is read.
    let curve = "C1,2 3,4 5,6"
    try expectEqual(SVGPath.polygons("M0,0 L10,0 L10,10 Z \(curve) M20,20 L30,20 L30,30 Z"),
                    [[mp(0, 0), mp(10, 0), mp(10, 10)]])
    // The polygon in progress stays when it has three points so far, and goes when it has fewer.
    try expectEqual(SVGPath.polygons("M0,0 L10,0 L10,10 Z M20,20 L30,20 L30,30 \(curve) Z").map(\.count), [3, 3])
    try expectEqual(SVGPath.polygons("M0,0 L10,0 L10,10 Z M20,20 L30,20 \(curve) Z").map(\.count), [3])
    for letter in ["A", "a", "C", "c", "Q", "q", "S", "s", "T", "t", "X", "e"] {
        try expectEqual(SVGPath.polygons("M0,0 L10,0 L10,10 Z \(letter)1 2 M5,5 L6,5 L6,6 Z").count, 1, letter)
    }
    // A malformed number stops the read the same way: a half pair is ignored, the rest unread.
    try expectEqual(SVGPath.polygons("M0,0 L10,0 L10,10 L5 Z M1,1 L2,1 L2,2 Z").map(\.count), [3])
    try expectEqual(SVGPath.polygons("M0,0 L10,0 L10,10 L- Z").map(\.count), [3])
    // A command letter with no numbers at all is malformed too, not skipped.
    try expectEqual(SVGPath.polygons("M0,0 L10,0 L10,10 L Z M1,1 L2,1 L2,2 Z").map(\.count), [3])
    // A number too large for a Double is not a point either.
    try expectEqual(SVGPath.polygons("M0,0 L10,0 L10,10 L1e999,5 Z").map(\.count), [3])
    // An "e" with no digits after it is not an exponent: the 5 stands, the e is a stray command.
    try expectEqual(SVGPath.polygons("M0,0 L10,0 L10,10 L5,5e Z"), [[mp(0, 0), mp(10, 0), mp(10, 10), mp(5, 5)]])
    // Numbers with no command, and lines before any moveto, are errors, not a start at the origin.
    try expectEqual(SVGPath.polygons("10,10 20,20 30,10 Z"), [])
    try expectEqual(SVGPath.polygons("L10,0 L10,10 L0,10 Z"), [])
    try expectEqual(SVGPath.polygons("M0,0 L10,0 L10,10 Z 5,5 M1,1 L2,1 L2,2 Z").map(\.count), [3])
}

func mapFillFollowsLuminance() throws {
    try expectEqual(RegionMapRules.fill(forData: "#050505"), .tint)
    try expectEqual(RegionMapRules.fill(forData: "#006f00"), .deep)
    try expectEqual(RegionMapRules.fill(forData: "#7E9B45"), .deep)
    try expectEqual(RegionMapRules.fill(forData: nil), .deep)
    try expectEqual(RegionMapRules.fill(forData: "nonsense"), .deep)
    // Read the way the site reads a colour: three digits, no hash, spaces round it.
    try expectEqual(RegionMapRules.fill(forData: "#000"), .tint)
    try expectEqual(RegionMapRules.fill(forData: "#fff"), .deep)
    try expectEqual(RegionMapRules.fill(forData: "050505"), .tint)
    try expectEqual(RegionMapRules.fill(forData: " #050505\n"), .tint)
    // The bar is a relative luminance of 0.06, which falls between the greys 0x45 (0.0595) and
    // 0x46 (0.0612), both worked out by hand rather than by this code.
    try expectEqual(RegionMapRules.fill(forData: "#454545"), .tint)
    try expectEqual(RegionMapRules.fill(forData: "#464646"), .deep)
    // Letter digits, in both cases. #006f00 cannot show a misread letter, since an unreadable
    // colour and a bright one are both deep, so these are dark colours that need the letters
    // read right: a/f in near-black greys, and the bar crossed inside the blue channel, between
    // 0xEB (0.05998) and 0xEC (0.06056).
    for text in ["#0a0a0a", "#0A0A0A", "#0f0f0f", "#0F0F0F", "#0000eb", "#0000EB"] {
        try expectEqual(RegionMapRules.fill(forData: text), .tint, text)
    }
    for text in ["#0000ec", "#0000EC"] {
        try expectEqual(RegionMapRules.fill(forData: text), .deep, text)
    }
    // Not three or six hex digits: unparseable, so left alone, even where the digits are dark.
    // The last five put the character just outside each digit range (g, G, :, @, `) into a dark
    // colour, since read as a digit each would come out near-black and tint.
    for text in ["", "#", "#05", "#05050", "#0505050", "#05050505", "##050505", "#gg0000", "rgb(0,0,0)", "black",
                 "#0g0g0g", "#0G0G0G", "#0:0:0:", "#0@0@0@", "#0`0`0`"] {
        try expectEqual(RegionMapRules.fill(forData: text), .deep, "\"\(text)\"")
    }
}

/// A hand-made map that reaches the rules the real files never test: an umbrella, a bad centroid,
/// a shape with no polygon, a native name that only repeats the label, an extended id that is
/// already a core id or repeats itself. Region ids are the ones the shared `indexJSON` knows.
let miniCoreJSON = #"""
{"viewBox":"0 0 100 80","projection":{"kind":"ignored"},"regions":[
 {"id":"indus","label":"Indus","path":"M0,0 L10,0 L10,10 Z","ref_path":"M0,0 L20,0 L20,20 L0,20 Z","fillRule":"evenodd","fillColor":"#050505","centroid":[5,5],"native":"  INDUS ","composition":["ignored"]},
 {"id":"kurdistan","label":"Kurdistan","path":"M30,30 L40,30 L40,40 Z","fillColor":"#006f00","centroid":[35,33],"native":"کردستان"},
 {"id":"anatolia","label":"Anatolia","path":"M50,50 L60,50 L60,60 Z","fillColor":"mauve","centroid":[55,53],"native":"   "},
 {"id":"mashriq","label":"Mashriq","path":"M1,1 L2,1 L2,2 Z","fillColor":"#006f00","centroid":[1,1],"role":"umbrella"},
 {"id":"no-centroid","label":"No centroid","path":"M1,1 L2,1 L2,2 Z","centroid":[1]},
 {"id":"three-numbers","label":"Three numbers","path":"M1,1 L2,1 L2,2 Z","centroid":[1,2,3]},
 {"id":"no-polygon","label":"No polygon","path":"M1,1 L2,1 Z","centroid":[1,1]}]}
"""#

let miniExtendedJSON = #"""
{"viewBox":"-10 -10 200 160","coreViewBox":"0 0 100 80","regions":[
 {"id":"anatolia","label":"Anatolia again","path":"M70,70 L80,70 L80,80 Z","centroid":[75,73],"tier":"islamicate"},
 {"id":"nusantara","label":"Nusantara","path":"M120,120 L130,120 L130,130 Z","centroid":[125,123],"tier":"islamicate","native":"NUSANTARA"},
 {"id":"nusantara","label":"Nusantara twice","path":"M140,120 L150,120 L150,130 Z","centroid":[145,123],"tier":"islamicate"},
 {"id":"khorasan","label":"Khorasan","path":"M1,1 L2,1 L2,2 Z","centroid":[1,1],"role":"umbrella"}]}
"""#

func composeAppliesEachRuleOnAHandMadeMap() throws {
    let core = try decode(RegionShapes.self, miniCoreJSON)
    let extended = try decode(RegionShapes.self, miniExtendedJSON)
    let index = try decode(ReceiverIndex.self, indexJSON)
    // Unknown keys are ignored, optional ones may be absent, ref_path is read as refPath.
    try expectEqual(core.regions.count, 7)
    try expectEqual(core.regions[0].refPath, "M0,0 L20,0 L20,20 L0,20 Z")
    try expectEqual(core.regions[1].refPath, nil)
    try expectEqual(extended.coreViewBox, "0 0 100 80")

    // Extensions off: umbrella, bad centroids and the polygon-less shape are left out.
    let plain = try require(RegionMapRules.compose(core: core, extended: extended, index: index, showExtensions: false))
    try expectEqual(plain.regions.map(\.id), ["indus", "kurdistan", "anatolia"])
    try expectEqual(boxValues(plain.viewBox), [0, 0, 100, 80])
    let indus = plain.regions[0], kurdistan = plain.regions[1], anatolia = plain.regions[2]
    try expectEqual(indus.polygons, [[mp(0, 0), mp(10, 0), mp(10, 10)]])
    try expectEqual(indus.outline, [[mp(0, 0), mp(20, 0), mp(20, 20), mp(0, 20)]])
    try expectEqual(indus.centroid, mp(5, 5))
    try expectEqual(indus.native, nil, "a native name that only repeats the label, in other case and with spaces")
    try expectEqual(indus.fill, .tint)
    try expectEqual(indus.isPeople, false)
    try expectEqual(indus.isExtension, false)
    try expectEqual(indus.opensChannels, true)
    try expectEqual(indus.live, 3)
    try expectEqual(kurdistan.native, "کردستان")
    try expectEqual(kurdistan.outline, kurdistan.polygons, "no ref_path, so the outline is the polygons")
    try expectEqual(kurdistan.fill, .deep)
    try expectEqual(kurdistan.isPeople, true)
    try expectEqual(kurdistan.opensChannels, false, "a people's region has no shard file")
    try expectEqual(kurdistan.live, nil)
    try expectEqual(anatolia.fill, .deep, "an unparseable colour is left alone")
    try expectEqual(anatolia.native, nil, "a blank native name")
    try expectEqual(anatolia.live, 150)

    // Extensions on: the extended viewBox, then the new ids in file order. The extended anatolia
    // is a core id, the second nusantara repeats the first, the umbrella is an umbrella.
    let wide = try require(RegionMapRules.compose(core: core, extended: extended, index: index, showExtensions: true))
    try expectEqual(wide.regions.map(\.id), ["indus", "kurdistan", "anatolia", "nusantara"])
    try expectEqual(boxValues(wide.viewBox), [-10, -10, 200, 160])
    try expectEqual(wide.regions.map(\.isExtension), [false, false, false, true])
    let nusantara = wide.regions[3]
    try expectEqual(nusantara.polygons, [[mp(120, 120), mp(130, 120), mp(130, 130)]])
    try expectEqual(nusantara.centroid, mp(125, 123))
    try expectEqual(nusantara.fill, .tint)
    try expectEqual(nusantara.native, nil, "NUSANTARA repeats Nusantara")
    try expectEqual(nusantara.opensChannels, true)
    try expectEqual(nusantara.live, 2)
    try expectEqual(wide.regions[2].polygons, anatolia.polygons, "the core anatolia stays")

    // Extensions asked for with no extended file: the core map, in the core viewBox.
    let missing = try require(RegionMapRules.compose(core: core, extended: nil, index: index, showExtensions: true))
    try expectEqual(missing.regions.map(\.id), ["indus", "kurdistan", "anatolia"])
    try expectEqual(boxValues(missing.viewBox), [0, 0, 100, 80])

    // A viewBox that does not parse makes the map nil when it is the one needed, and only then:
    // the core file's frame with extensions off, the extended file's with them on.
    let badCore = try decode(RegionShapes.self, miniCoreJSON.replacingOccurrences(of: "\"viewBox\":\"0 0 100 80\"", with: "\"viewBox\":\"0 0 0 80\""))
    let badExtended = try decode(RegionShapes.self, miniExtendedJSON.replacingOccurrences(of: "\"viewBox\":\"-10 -10 200 160\"", with: "\"viewBox\":\"wide\""))
    try expect(RegionMapRules.compose(core: badCore, extended: extended, index: index, showExtensions: false) == nil)
    try expect(RegionMapRules.compose(core: badCore, extended: extended, index: index, showExtensions: true) != nil)
    try expect(RegionMapRules.compose(core: core, extended: badExtended, index: index, showExtensions: false) != nil)
    try expect(RegionMapRules.compose(core: core, extended: badExtended, index: index, showExtensions: true) == nil)
}

/// A core shape the receiver index tiers islamicate is an extension on the receiver. Ids are the
/// ones the shared `indexJSON` knows: indus (heartbeat), anatolia (core) and nusantara
/// (islamicate); "unlisted" is on no line of that index. Nusantara's data colour is the first
/// green, so a tint on it can only come from the rule, and the ordinary shapes' fills differ from
/// it, so a forced tint on them would show. The extended file has a nusantara of its own.
let miniDoorsCoreJSON = #"""
{"viewBox":"0 0 100 80","regions":[
 {"id":"indus","label":"Indus","path":"M0,0 L10,0 L10,10 Z","fillColor":"#006f00","centroid":[5,5]},
 {"id":"nusantara","label":"Nusantara","path":"M20,20 L30,20 L30,30 Z","fillColor":"#006f00","centroid":[25,23]},
 {"id":"unlisted","label":"Unlisted","path":"M40,40 L50,40 L50,50 Z","fillColor":"#006f00","centroid":[45,43]},
 {"id":"anatolia","label":"Anatolia","path":"M60,60 L70,60 L70,70 Z","fillColor":"#050505","centroid":[65,63]}]}
"""#

let miniDoorsExtendedJSON = #"""
{"viewBox":"-10 -10 200 160","coreViewBox":"0 0 100 80","regions":[
 {"id":"nusantara","label":"Nusantara from the extended file","path":"M140,100 L150,100 L150,110 Z","centroid":[145,103]},
 {"id":"far","label":"Far","path":"M120,120 L130,120 L130,130 Z","centroid":[125,123]}]}
"""#

func composeHoldsACoreShapeTheIndexTiersIslamicateBehindTheSwitch() throws {
    let core = try decode(RegionShapes.self, miniDoorsCoreJSON)
    let extended = try decode(RegionShapes.self, miniDoorsExtendedJSON)
    let index = try decode(ReceiverIndex.self, indexJSON)

    // Switch off: nusantara is not on the map. The ordinary shapes are, the one the index does
    // not list among them, each with the fill its data gives it.
    let off = try require(RegionMapRules.compose(core: core, extended: extended, index: index, showExtensions: false))
    try expectEqual(off.regions.map(\.id), ["indus", "unlisted", "anatolia"])
    try expectEqual(off.regions.map(\.isExtension), [false, false, false])
    try expectEqual(off.regions.map(\.fill), [.deep, .deep, .tint])
    try expectEqual(boxValues(off.viewBox), [0, 0, 100, 80])

    // Switch on: it comes back where the core file has it, as an extension in the second green
    // though its data colour is the first. The extended file's shapes follow, and that file's own
    // nusantara, a core id, is skipped for the core file's.
    let on = try require(RegionMapRules.compose(core: core, extended: extended, index: index, showExtensions: true))
    try expectEqual(on.regions.map(\.id), ["indus", "nusantara", "unlisted", "anatolia", "far"])
    try expectEqual(on.regions.map(\.isExtension), [false, true, false, false, true])
    try expectEqual(on.regions.map(\.fill), [.deep, .tint, .deep, .tint, .tint])
    try expectEqual(boxValues(on.viewBox), [-10, -10, 200, 160])
    let nusantara = on.regions[1]
    try expectEqual(nusantara.polygons, [[mp(20, 20), mp(30, 20), mp(30, 30)]], "the core file's shape, not its namesake in the extended file")
    try expectEqual(nusantara.centroid, mp(25, 23))
    try expectEqual(nusantara.label, "Nusantara")
    try expectEqual(nusantara.opensChannels, true)
    try expectEqual(nusantara.live, 2)

    // Switch on with no extended file: the core file's extension is still drawn, in the core frame.
    let alone = try require(RegionMapRules.compose(core: core, extended: nil, index: index, showExtensions: true))
    try expectEqual(alone.regions.map(\.id), ["indus", "nusantara", "unlisted", "anatolia"])
    try expectEqual(alone.regions.map(\.isExtension), [false, true, false, false])
    try expectEqual(boxValues(alone.viewBox), [0, 0, 100, 80])

    // The tier is the index's. The same shapes against an index that tiers nusantara core are all
    // ordinary: shown with the switch off, not extensions, in the fill their data gives.
    let retiered = try decode(ReceiverIndex.self, indexJSON.replacingOccurrences(of: "\"tier\":\"islamicate\"", with: "\"tier\":\"core\""))
    try expectEqual(retiered.regions.first(where: { $0.id == "nusantara" })?.tier, "core", "the replacement did not apply")
    let ordinary = try require(RegionMapRules.compose(core: core, extended: extended, index: retiered, showExtensions: false))
    try expectEqual(ordinary.regions.map(\.id), ["indus", "nusantara", "unlisted", "anatolia"])
    try expectEqual(ordinary.regions.map(\.isExtension), [false, false, false, false])
    try expectEqual(ordinary.regions.map(\.fill), [.deep, .deep, .deep, .tint])
}

struct RealMapInputs {
    let core: RegionShapes
    let extended: RegionShapes
    let index: ReceiverIndex
    let rawCore: [String: Any]
    let rawExtended: [String: Any]
    let rawIndex: [String: Any]
}

/// The three real files, decoded for the app and again as raw JSON, so that expectations can be
/// worked out from the raw side by a route that shares no code with the app's decoding.
func realMapInputs() throws -> RealMapInputs {
    let coreData = try realFile("data/region-shapes.json")
    let extendedData = try realFile("data/region-shapes-extended.json")
    let indexData = try realFile("data/open-frequencies/receiver-index.json")
    func object(_ data: Data) throws -> [String: Any] {
        try require(try JSONSerialization.jsonObject(with: data) as? [String: Any], "not a JSON object")
    }
    let decoder = JSONDecoder()
    return RealMapInputs(core: try decoder.decode(RegionShapes.self, from: coreData),
                         extended: try decoder.decode(RegionShapes.self, from: extendedData),
                         index: try decoder.decode(ReceiverIndex.self, from: indexData),
                         rawCore: try object(coreData), rawExtended: try object(extendedData), rawIndex: try object(indexData))
}

/// The real files write every path as space-separated "M x,y", "L x,y" and "Z" and nothing else,
/// so they can be read by splitting, a route that shares no code with SVGPath.
func polygonsBySplitting(_ d: String) throws -> [[MapPoint]] {
    var polygons: [[MapPoint]] = []
    var open: [MapPoint] = []
    for token in d.split(separator: " ") {
        if token == "Z" {
            polygons.append(open)
            open = []
            continue
        }
        let pair = token.dropFirst().split(separator: ",").compactMap { Double($0) }
        guard token.first == "M" || token.first == "L", pair.count == 2 else {
            throw Failure(description: "the real path data holds a token this test does not read: \(token)")
        }
        if token.first == "M", !open.isEmpty { throw Failure(description: "an M inside an open polygon") }
        open.append(mp(pair[0], pair[1]))
    }
    guard open.isEmpty else { throw Failure(description: "the path does not end in Z") }
    return polygons.filter { $0.count >= 3 }
}

/// The kind and the tier of every region line in the raw receiver index, read without the app's
/// decoder so that expectations can be worked out by a route that shares no code with it.
func rawKindsAndTiers(_ rawIndex: [String: Any]) throws -> (kinds: [String: String], tiers: [String: String]) {
    var kinds: [String: String] = [:], tiers: [String: String] = [:]
    for line in try require(rawIndex["regions"] as? [[String: Any]], "no regions in the index") {
        guard let id = line["id"] as? String else { continue }
        if let kind = line["kind"] as? String { kinds[id] = kind }
        if let tier = line["tier"] as? String { tiers[id] = tier }
    }
    return (kinds, tiers)
}

/// What the receiver index says about each region, recounted from the raw index: a people's
/// region (kind), whether it opens channels (a regionFiles line) and its live count.
func expectIndexSideMatches(_ regions: [MapRegion], rawIndex: [String: Any]) throws {
    let (kinds, _) = try rawKindsAndTiers(rawIndex)
    let rawFiles = try require(rawIndex["regionFiles"] as? [String: String])
    let rawCounts = try require(rawIndex["regionCounts"] as? [String: [String: Any]])
    for region in regions {
        try expectEqual(region.isPeople, kinds[region.id] == "people", region.id)
        try expectEqual(region.opensChannels, rawFiles[region.id] != nil, region.id)
        try expectEqual(region.live, rawCounts[region.id]?["live"] as? Int, region.id)
    }
}

func realRegionMapCoreOnly() throws {
    let real = try realMapInputs()
    let map = try require(RegionMapRules.compose(core: real.core, extended: real.extended, index: real.index, showExtensions: false))
    let (_, tiers) = try rawKindsAndTiers(real.rawIndex)

    // Which regions to expect: the raw file's ids in file order, less the umbrella and less the
    // core shapes the raw index tiers islamicate, which are extensions and not on this map.
    let rawShapes = try require(real.rawCore["regions"] as? [[String: Any]])
    let expectedIds = rawShapes.compactMap { shape -> String? in
        guard let id = shape["id"] as? String, (shape["role"] as? String) != "umbrella", tiers[id] != "islamicate" else { return nil }
        return id
    }
    try expectEqual(map.regions.map(\.id), expectedIds)
    try expectEqual(map.regions.count, 16, "measured 2026-10-05: 19 shapes less the mashriq umbrella and the two islamicate-tier doors")
    try expect(!map.regions.contains { $0.id == "mashriq" }, "the umbrella is drawn by its members")
    // The two Indian doors are core shapes the index tiers islamicate, so they are extensions and
    // stay off the map until the switch is on. Their tier is checked first, so that a re-tiering
    // in the data reads as that and not as a missing region.
    for id in ["hindustan", "dakhan"] {
        try expectEqual(tiers[id], "islamicate", "\(id) is no longer tiered islamicate in the index")
        try expect(!map.regions.contains { $0.id == id }, "\(id) is on the core-only map")
    }
    try expectEqual(boxValues(map.viewBox), [0, 0, 1000, 700])
    try expect(map.regions.allSatisfy { !$0.isExtension }, "an extension in the core-only map")

    try expectIndexSideMatches(map.regions, rawIndex: real.rawIndex)
    for id in ["kurdistan", "pashtunistan", "balochistan", "kashmir"] {
        let region = try require(map.regions.first { $0.id == id }, id)
        try expect(region.isPeople, "\(id) is not a people's region in the index")
    }
    let indus = try require(map.regions.first { $0.id == "indus" })
    try expect(indus.opensChannels, "indus has no shard file")
    try expect((indus.live ?? 0) > 0, "indus has no live channel")
    try expect(!indus.isPeople)

    // Geometry: every region has something to draw and a place inside the frame, and every point
    // is the one the file wrote, checked against a parse that shares no code with SVGPath.
    let shapes = Dictionary(uniqueKeysWithValues: real.core.regions.map { ($0.id, $0) })
    var points = 0, tinted = 0, deep = 0
    for region in map.regions {
        let shape = try require(shapes[region.id], region.id)
        try expect(!region.polygons.isEmpty && region.polygons.allSatisfy { $0.count >= 3 }, "\(region.id): polygons")
        try expect(!region.outline.isEmpty && region.outline.allSatisfy { $0.count >= 3 }, "\(region.id): outline")
        try expect(inside(region.centroid, map.viewBox), "\(region.id): centroid \(region.centroid) is outside the viewBox")
        try expect(region.polygons == (try polygonsBySplitting(shape.path)), "\(region.id): path points differ from the file")
        let refPath = try require(shape.refPath, "\(region.id) has no ref_path")
        try expect(region.outline == (try polygonsBySplitting(refPath)), "\(region.id): ref_path points differ from the file")
        points += region.polygons.reduce(0) { $0 + $1.count } + region.outline.reduce(0) { $0 + $1.count }
        // The two colours the data uses, as DESIGN.md names them.
        if shape.fillColor == "#050505" {
            try expectEqual(region.fill, .tint, region.id)
            tinted += 1
        } else if shape.fillColor == "#006f00" {
            try expectEqual(region.fill, .deep, region.id)
            deep += 1
        }
    }
    try expect(tinted > 0 && deep > 0, "expected both fills in the data: \(tinted) tint, \(deep) deep")
    try expect(map.regions.contains { $0.outline != $0.polygons }, "no region draws a ref_path outline of its own")
    print("      \(map.regions.count) core regions, \(points) points checked against the file, \(tinted) tint and \(deep) deep")
}

func realRegionMapWithExtensions() throws {
    let real = try realMapInputs()
    let coreOnly = try require(RegionMapRules.compose(core: real.core, extended: real.extended, index: real.index, showExtensions: false))
    let map = try require(RegionMapRules.compose(core: real.core, extended: real.extended, index: real.index, showExtensions: true))
    let (_, tiers) = try rawKindsAndTiers(real.rawIndex)

    // From the raw files: the core file's ids in file order less the umbrella, which includes the
    // two doors where the file has them, and then the extended file's ids that are not core ids.
    func ids(_ raw: [String: Any]) throws -> [String] {
        try require(raw["regions"] as? [[String: Any]], "no regions").compactMap { $0["id"] as? String }
    }
    let rawCoreShapes = try require(real.rawCore["regions"] as? [[String: Any]])
    let coreFileIds = rawCoreShapes.filter { ($0["role"] as? String) != "umbrella" }.compactMap { $0["id"] as? String }
    let coreIds = Set(try ids(real.rawCore))
    let extensionIds = try ids(real.rawExtended).filter { !coreIds.contains($0) }
    try expectEqual(map.regions.count, coreFileIds.count + extensionIds.count)
    try expectEqual(map.regions.count, 55, "measured 2026-10-05: 18 core-file shapes, two of them doors, and 37 extended, no id in both")
    // Core file order with the doors where they stand, then the extended file.
    try expectEqual(map.regions.prefix(coreFileIds.count).map(\.id), coreFileIds)
    try expectEqual(map.regions.dropFirst(coreFileIds.count).map(\.id), extensionIds)
    try expectEqual(boxValues(map.viewBox), [-12, -12, 1444, 949.8])

    // In the core file's part, a shape is an extension exactly when the raw index tiers it
    // islamicate, and then it is drawn in the second green.
    for region in map.regions.prefix(coreFileIds.count) {
        let door = tiers[region.id] == "islamicate"
        try expectEqual(region.isExtension, door, "\(region.id): isExtension should follow the index tier")
        if door { try expectEqual(region.fill, .tint, region.id) }
    }
    // The two doors by name: present, extensions, the second green, before the extended file's
    // shapes, at the place the core file gives them, with the core file's own geometry.
    let coreShapes = Dictionary(uniqueKeysWithValues: real.core.regions.map { ($0.id, $0) })
    for id in ["hindustan", "dakhan"] {
        let at = try require(map.regions.firstIndex(where: { $0.id == id }), "\(id) is missing with the extensions on")
        let region = map.regions[at]
        try expect(region.isExtension, "\(id) is not an extension")
        try expectEqual(region.fill, .tint, id)
        try expectEqual(at, try require(coreFileIds.firstIndex(of: id)), "\(id) is not at its core-file position")
        try expect(at < coreFileIds.count, "\(id) comes after the extended file's shapes")
        let shape = try require(coreShapes[id], id)
        try expect(region.polygons == (try polygonsBySplitting(shape.path)), "\(id): path points differ from the file")
        try expect(region.outline == (try polygonsBySplitting(try require(shape.refPath, id))), "\(id): ref_path points differ from the file")
    }
    // The index side for all 55, the extended file's shapes included: some of those are people's
    // regions (crimea, lipka, champa, hausaland), and the recount can only fail on that if one is
    // really there.
    try expectIndexSideMatches(map.regions, rawIndex: real.rawIndex)
    try expect(map.regions.dropFirst(coreFileIds.count).contains { $0.isPeople }, "no extended region is a people's region in the index")
    // Turning the switch off takes exactly the extensions away and changes nothing else.
    let kept = map.regions.filter { !$0.isExtension }
    try expectEqual(coreOnly.regions.map(\.id), kept.map(\.id))
    try expect(coreOnly.regions.map(\.polygons) == kept.map(\.polygons), "the core-only map's shapes differ from the same shapes in the wide map")

    let shapes = Dictionary(uniqueKeysWithValues: real.extended.regions.map { ($0.id, $0) })
    for region in map.regions.dropFirst(coreFileIds.count) {
        let shape = try require(shapes[region.id], region.id)
        try expect(region.isExtension, "\(region.id) is an extension")
        try expectEqual(region.fill, .tint, region.id)
        try expect(!region.polygons.isEmpty && region.polygons.allSatisfy { $0.count >= 3 }, "\(region.id): polygons")
        try expect(region.outline == region.polygons, "\(region.id): no ref_path, so the outline is the polygons")
        try expect(inside(region.centroid, map.viewBox), "\(region.id): centroid \(region.centroid) is outside the viewBox")
        try expect(region.polygons == (try polygonsBySplitting(shape.path)), "\(region.id): path points differ from the file")
    }

    // The switch alone shows the core file's extensions, as it does on the site when the
    // extended file fails to load: with no extended file the doors are drawn in the core frame.
    let missing = try require(RegionMapRules.compose(core: real.core, extended: nil, index: real.index, showExtensions: true))
    try expectEqual(missing.regions.map(\.id), coreFileIds)
    try expectEqual(missing.regions.map(\.isExtension), coreFileIds.map { tiers[$0] == "islamicate" })
    try expectEqual(boxValues(missing.viewBox), [0, 0, 1000, 700])
    // And with the switch off, a missing extended file changes nothing.
    let offAndMissing = try require(RegionMapRules.compose(core: real.core, extended: nil, index: real.index, showExtensions: false))
    try expectEqual(offAndMissing.regions.map(\.id), coreOnly.regions.map(\.id))
    let doors = map.regions.prefix(coreFileIds.count).filter(\.isExtension).count
    print("      \(map.regions.count) regions: \(coreOnly.regions.count) core, \(doors) core-file doors, \(extensionIds.count) extended; every extension tint, all inside the 1444-wide frame")
}

/// The map shows the receiver's own region names, the ones the website's receiver map shows.
func realMapUsesReceiverNames() throws {
    let real = try realMapInputs()
    let map = try require(RegionMapRules.compose(core: real.core, extended: real.extended, index: real.index, showExtensions: true))
    let rawRegions = try require(real.rawIndex["regions"] as? [[String: Any]])
    var names: [String: String] = [:]
    for line in rawRegions { if let id = line["id"] as? String, let label = line["label"] as? String { names[id] = label } }
    var checked = 0
    for region in map.regions {
        if let name = names[region.id], !name.isEmpty { try expectEqual(region.label, name, region.id); checked += 1 }
    }
    try expect(checked >= 40, "only \(checked) regions carried a receiver name")
    let byId = Dictionary(map.regions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    try expectEqual(byId["levant"]?.label, "Al-Sham")
    try expectEqual(byId["arabia"]?.label, "Jazirat al-Arab")
    try expectEqual(byId["horn"]?.label, "Horn")
    print("      \(checked) regions named by the receiver index")
}

func realMapWithoutRegionFilesOpensNothing() throws {
    let real = try realMapInputs()
    // The control: with the real index some regions open channels.
    let opening = try require(RegionMapRules.compose(core: real.core, extended: real.extended, index: real.index, showExtensions: true))
    try expect(opening.regions.contains { $0.opensChannels }, "no region opens channels with the real index")

    // The same index with its shard list emptied.
    var raw = real.rawIndex
    raw["regionFiles"] = [String: String]()
    let bare = try JSONDecoder().decode(ReceiverIndex.self, from: try JSONSerialization.data(withJSONObject: raw))
    try expectEqual(bare.regionFiles.count, 0)
    let map = try require(RegionMapRules.compose(core: real.core, extended: real.extended, index: bare, showExtensions: true))
    try expectEqual(map.regions.count, opening.regions.count)
    try expect(map.regions.allSatisfy { !$0.opensChannels }, "a region opens channels with no regionFiles")
    // opensChannels follows the shard list and nothing else: the live counts are untouched.
    let indus = try require(map.regions.first { $0.id == "indus" })
    try expect((indus.live ?? 0) > 0, "indus lost its live count with the shard list")
}

// MARK: - Pics/Vids

struct PnvFixtureCase: Decodable {
    let row: PnvRow
    let thumb: String?
    let medium: String?
    let poster: String?
    let full: String?
    let tile: String?
    let candidates: [String]
}

struct PnvFixture: Decodable {
    let cases: [PnvFixtureCase]
}

func pnvFixture() throws -> PnvFixture {
    let url = fixtureURL.deletingLastPathComponent().appendingPathComponent("pnv-media-fixture.json")
    return try JSONDecoder().decode(PnvFixture.self, from: try Data(contentsOf: url))
}

func pnvRow(_ json: String) throws -> PnvRow { try decode(PnvRow.self, json) }

func pnvMismatches(_ c: PnvFixtureCase) -> [String] {
    var wrong: [String] = []
    func check(_ name: String, _ got: URL?, _ want: String?) {
        if got?.absoluteString != want { wrong.append("\(c.row.media_key) \(name): got \(got?.absoluteString ?? "nil"), want \(want ?? "nil")") }
    }
    check("thumb", PnvMedia.thumb(c.row), c.thumb)
    check("medium", PnvMedia.medium(c.row), c.medium)
    check("poster", PnvMedia.poster(c.row), c.poster)
    check("full", PnvMedia.full(c.row), c.full)
    check("tile", PnvMedia.tile(c.row), c.tile)
    let candidates = PnvMedia.pictureCandidates(c.row).map(\.absoluteString)
    // The site lists [full, medium, thumb] with blanks dropped; the app also drops repeats.
    var seen = Set<String>()
    let expected = c.candidates.filter { seen.insert($0).inserted }
    if candidates != expected { wrong.append("\(c.row.media_key) candidates: got \(candidates), want \(expected)") }
    return wrong
}

func pnvMediaMatchesTheSitesJS() throws {
    let fx = try pnvFixture()
    var wrong: [String] = []
    for c in fx.cases { wrong += pnvMismatches(c) }
    try expect(wrong.isEmpty, wrong.prefix(5).joined(separator: "; "))
    // The sample has to cover what the site serves: every host, both kinds, rows with no size.
    let combos = Set(fx.cases.map { "\($0.row.media_host ?? "none")/\($0.row.kind)" })
    for want in ["r2/image", "r2/video", "supabase/image", "supabase/video", "ktv/video"] {
        try expect(combos.contains(want), "no \(want) row in the fixture")
    }
    try expect(fx.cases.contains { $0.row.width == nil }, "no row without a size")
    try expect(fx.cases.count >= 40, "only \(fx.cases.count) cases")
    // Rows with no endpoint produce no URL at all, in every form.
    for key in ["edge-empty", "edge-null"] {
        let c = try require(fx.cases.first { $0.row.media_key == key }, key)
        try expect([PnvMedia.thumb(c.row), PnvMedia.medium(c.row), PnvMedia.poster(c.row), PnvMedia.full(c.row), PnvMedia.tile(c.row)].allSatisfy { $0 == nil }, key)
        try expect(PnvMedia.pictureCandidates(c.row).isEmpty, key)
    }
}

func pnvComparatorCanFail() throws {
    let fx = try pnvFixture()
    // The same row filed on another host must disagree with the site's answer for it.
    let r2 = try require(fx.cases.first { $0.row.media_host == "r2" && $0.row.kind == "image" })
    let moved = PnvFixtureCase(
        row: try pnvRow(#"{"media_key":"m","kind":"image","resource_type":"image","media_host":"supabase","resource_endpoint":"\#(r2.row.resource_endpoint ?? "")"}"#),
        thumb: r2.thumb, medium: r2.medium, poster: r2.poster, full: r2.full, tile: r2.tile, candidates: r2.candidates)
    try expect(!pnvMismatches(moved).isEmpty, "a row on the wrong host still matched")
}

func pnvKtvVideosGoThroughTvPlay() throws {
    let ktv = try pnvRow(#"{"media_key":"ktv-a","kind":"video","resource_type":"video","media_host":"ktv","resource_endpoint":"tv-afghanmusic-2022-mp4"}"#)
    let full = try require(PnvMedia.full(ktv))
    try expectEqual(full.absoluteString, "https://qojysegeddztsxdmhjfb.supabase.co/functions/v1/tv-play?id=tv-afghanmusic-2022-mp4")
    // The same route the Transmission player resolves, with the id kept.
    let route = try require(Transmission.route(for: full.absoluteString))
    try expectEqual(route, PlayRoute.tvPlay(full))
    let request = try require(Transmission.request(for: route, accessToken: "T"))
    try expectEqual(request.url, full)
    try expectEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer T")
    try expectEqual(try Transmission.carrier(from: Data(#"{"url":"https://cdn.example/x.m3u8"}"#.utf8), route: route).absoluteString, "https://cdn.example/x.m3u8")
    // Negative: a row that is not ktv is a plain file and needs no session.
    let r2 = try pnvRow(#"{"media_key":"r","kind":"video","resource_type":"video","media_host":"r2","resource_endpoint":"a/media/b/b"}"#)
    let plain = try require(Transmission.route(for: try require(PnvMedia.full(r2)).absoluteString))
    guard case .direct = plain else { throw Failure(description: "an r2 video must be a direct file, got \(plain)") }
    try expectEqual(Transmission.request(for: plain, accessToken: "T"), nil)
}

func pnvRowsDecode() throws {
    let url = fixtureURL.deletingLastPathComponent().appendingPathComponent("pnv-rows-sample.json")
    let rows = try JSONDecoder().decode([PnvRow].self, from: try Data(contentsOf: url))
    try expect(rows.count >= 30, "\(rows.count) rows")
    try expect(rows.contains { $0.aspect == nil } && rows.contains { $0.aspect != nil })
    try expectClose(try require(try pnvRow(#"{"media_key":"a","kind":"image","width":1170,"height":2080}"#).aspect), 1170.0 / 2080.0)
    // A zero or missing size is no shape at all, not a division by zero.
    try expectEqual(try pnvRow(#"{"media_key":"a","kind":"image","width":0,"height":5}"#).aspect, nil)
    try expectEqual(try pnvRow(#"{"media_key":"a","kind":"image","width":null,"height":null}"#).aspect, nil)
    try expectThrowsAny { _ = try pnvRow(#"{"kind":"image"}"#) }
}

func expectThrowsAny(line: Int = #line, _ body: () throws -> Void) throws {
    do { try body() } catch { return }
    throw Failure(description: "line \(line): nothing thrown")
}

func pnvRequests() throws {
    let page = PnvAPI.pageRequest(keys: ["a", "b-c", "d_e"], kind: .video, offset: 120, wantCount: true)
    try expectEqual(page.url?.absoluteString,
        "https://qojysegeddztsxdmhjfb.supabase.co/rest/v1/pnv_media?select=\(PnvAPI.columns)&account_key=in.(a,b-c,d_e)&kind=eq.video&order=feed_rank.asc,corpus.asc&limit=60&offset=120")
    try expectEqual(page.value(forHTTPHeaderField: "Prefer"), "count=exact")
    try expectEqual(page.value(forHTTPHeaderField: "apikey"), KJConfig.anonKey)
    try expectEqual(page.value(forHTTPHeaderField: "Authorization"), "Bearer \(KJConfig.anonKey)")
    // The same columns the site selects.
    try expectEqual(PnvAPI.columns, "media_key,account,account_key,shortcode,child_index,kind,resource_type,media_host,resource_endpoint,width,height,tags,taken_at,corpus,feed_rank,da_id")
    // Negative: no kind, no count asked for, a key that is not plain gets quoted.
    let later = PnvAPI.pageRequest(keys: ["a b", "q\"z"], kind: nil, offset: 60, wantCount: false)
    let text = later.url?.absoluteString ?? ""
    try expect(!text.contains("kind="), text)
    try expectEqual(later.value(forHTTPHeaderField: "Prefer"), nil)
    try expect(text.contains("account_key=in.(%22a%20b%22,%22q%5C%22z%22)"), text)
    let accounts = PnvAPI.accountsRequest()
    try expectEqual(accounts.url?.absoluteString,
        "https://qojysegeddztsxdmhjfb.supabase.co/rest/v1/pnv_accounts?select=slug,handle,url,platform,region,region_token,country,corpus,account_key")
    try expectEqual(accounts.httpMethod ?? "GET", "GET")
    let facets = PnvAPI.facetsRequest()
    try expectEqual(facets.url?.absoluteString, "https://qojysegeddztsxdmhjfb.supabase.co/rest/v1/rpc/pnv_facets")
    try expectEqual(facets.httpMethod, "POST")
    try expectEqual(String(data: facets.httpBody ?? Data(), encoding: .utf8), "{}")
}

func pnvContentRange() throws {
    try expectEqual(PnvAPI.total(fromContentRange: "0-59/99474"), 99474)
    try expectEqual(PnvAPI.total(fromContentRange: "*/0"), 0)
    try expectEqual(PnvAPI.total(fromContentRange: "0-59/*"), nil)
    try expectEqual(PnvAPI.total(fromContentRange: nil), nil)
    try expectEqual(PnvAPI.total(fromContentRange: "garbage"), nil)
}

func pnvAccount(_ key: String, _ token: String?) throws -> PnvAccount {
    let t = token.map { "\"\($0)\"" } ?? "null"
    return try decode(PnvAccount.self, #"{"slug":"\#(key)","account_key":"\#(key)","region_token":\#(t)}"#)
}

func pnvAccountKeysFollowTheRosterAndTheFold() throws {
    let roster = [try pnvAccount("a1", "arabia"), try pnvAccount("a2", "egypt-nile"), try pnvAccount("m1", "egypt"),
                  try pnvAccount("i1", "indus"), try pnvAccount("n1", nil)]
    try expectEqual(PnvAPI.accountKeys(roster: roster, region: nil), ["a1", "a2", "m1", "i1", "n1"])
    // Egypt-the-country folds into Mashriq; the token `egypt` is the Maghreb and does not.
    try expectEqual(PnvAPI.accountKeys(roster: roster, region: "arabia"), ["a1", "a2"])
    try expectEqual(PnvAPI.accountKeys(roster: roster, region: "egypt"), ["m1"])
    // Nothing on the roster, or a region nobody is filed under: nothing to ask for.
    try expectEqual(PnvAPI.accountKeys(roster: [], region: nil), nil)
    try expectEqual(PnvAPI.accountKeys(roster: roster, region: "persia"), nil)
    try expectEqual(PnvRegions.accountKeysByRegion(roster).keys.sorted(), ["arabia", "egypt", "indus"])
    try expectEqual(PnvRegions.ordered(["indus", "arabia", "egypt", "zz", "persia"]), ["egypt", "arabia", "persia", "indus", "zz"])
    try expectEqual(["egypt", "arabia", "persia", "khorasan", "indus", "anatolia", "mystery"].map(PnvRegions.label),
                    ["Maghreb", "Mashriq", "Persia", "Khorasan", "Indus", "Anatolia", "mystery"])
}

func pnvSummaryLine() throws {
    let roster = [try pnvAccount("a1", "arabia"), try pnvAccount("a2", "indus"), try pnvAccount("a3", "indus")]
    let facets = try decode(PnvFacets.self, #"{"totals":{"media":99474},"accounts":[{"slug":"a1","media":5},{"slug":"a2","media":0}]}"#)
    // a2 has no media; a3 is not in the counts at all and stays.
    try expectEqual(PnvAPI.summary(roster: roster, facets: facets), "99,474 pictures and videos \u{00B7} 2 accounts \u{00B7} 2 regions")
    try expectEqual(PnvAPI.summary(roster: roster, facets: nil), "3 accounts")
    try expectEqual(PnvAPI.summary(roster: roster, facets: try decode(PnvFacets.self, #"{"accounts":[]}"#)), "3 accounts")
}

func pnvCaptions() throws {
    let dba = try pnvRow(#"{"media_key":"k","kind":"image","corpus":"dba","shortcode":"AbC_1","da_id":null}"#)
    try expectEqual(PnvAPI.captionRequest(for: dba)?.url?.absoluteString,
                    "https://qojysegeddztsxdmhjfb.supabase.co/rest/v1/dba_posts?select=shortcode,caption&shortcode=in.(AbC_1)")
    let da = try pnvRow(#"{"media_key":"da-9","kind":"image","corpus":"digital_archive","da_id":9}"#)
    try expectEqual(PnvAPI.captionRequest(for: da)?.url?.absoluteString,
                    "https://qojysegeddztsxdmhjfb.supabase.co/rest/v1/digital_archive?select=id,description&id=in.(9)")
    // Khajistan TV rows have neither.
    let ktv = try pnvRow(#"{"media_key":"ktv-a","kind":"video","corpus":"khajistan-tv","media_host":"ktv"}"#)
    try expectEqual(PnvAPI.captionRequest(for: ktv), nil)
    try expectEqual(PnvAPI.caption(from: Data(#"[{"shortcode":"x","caption":"Lahore, 1990 https://t.co/abc #lahore  #old\n\nbazaar"}]"#.utf8)), "Lahore, 1990 bazaar")
    try expectEqual(PnvAPI.caption(from: Data(#"[{"id":9,"description":"A shrine."}]"#.utf8)), "A shrine.")
    // Nothing left after the strip, no rows, and not JSON at all are all no caption.
    try expectEqual(PnvAPI.caption(from: Data(##"[{"caption":"#a #b https://x.y"}]"##.utf8)), nil)
    try expectEqual(PnvAPI.caption(from: Data("[]".utf8)), nil)
    try expectEqual(PnvAPI.caption(from: Data("nope".utf8)), nil)
}

func pnvMetaLine() throws {
    let row = try pnvRow(#"{"media_key":"k","kind":"video","width":1170,"height":2080,"taken_at":"2026-08-27T04:29:06+00:00"}"#)
    try expectEqual(PnvAPI.metaLine(for: row, regionToken: "arabia", date: { _ in "Aug 27, 2026" }), "Video \u{00B7} Mashriq \u{00B7} Aug 27, 2026 \u{00B7} 1170\u{00D7}2080")
    let bare = try pnvRow(#"{"media_key":"k","kind":"image"}"#)
    try expectEqual(PnvAPI.metaLine(for: bare, regionToken: nil, date: { _ in "x" }), "Picture")
}

func pnvLayoutPlacesEachRowInTheShortestColumn() throws {
    func r(_ key: String, _ w: Int?, _ h: Int?) throws -> PnvRow {
        let size = (w != nil && h != nil) ? #","width":\#(w!),"height":\#(h!)"# : ""
        return try pnvRow(#"{"media_key":"\#(key)","kind":"image"\#(size)}"#)
    }
    // Heights (h/w + .03): tall 2.03, square 1.03, wide .53, unknown 1.03.
    let rows = [try r("tall", 1, 2), try r("sq", 1, 1), try r("wide", 2, 1), try r("unk", nil, nil), try r("wide2", 2, 1)]
    let cols = PnvLayout.columns(rows, count: 3).map { $0.map(\.media_key) }
    // tall -> 0, sq -> 1, wide -> 2 (0 is 2.03, 1 is 1.03, 2 is 0), unk -> 2 (.53 < 1.03), wide2 -> 2 (1.56 vs 1.03: goes to 1).
    try expectEqual(cols, [["tall"], ["sq", "wide2"], ["wide", "unk"]])
    // Appending never moves a tile already placed.
    let longer = rows + [try r("more", 1, 1), try r("more2", 3, 4)]
    let before = PnvLayout.columns(rows, count: 3)
    let after = PnvLayout.columns(longer, count: 3)
    for k in 0..<3 { try expect(Array(after[k].prefix(before[k].count)) == before[k], "column \(k) moved") }
    try expectEqual(PnvLayout.columns(rows, count: 0).count, 0)
    try expectEqual(PnvLayout.columns([], count: 4).map(\.count), [0, 0, 0, 0])
    try expectEqual(PnvLayout.columns(rows, count: 1).first?.count, 5)
}

func adultNoticeSuppressionRule() throws {
    // The site's three states, plus a confirmed account.
    try expectEqual(AdultNotice.shouldShow(stored: nil, session: nil, confirmed18: false), true)
    try expectEqual(AdultNotice.shouldShow(stored: "dismissed", session: nil, confirmed18: false), false)
    try expectEqual(AdultNotice.shouldShow(stored: nil, session: "ok", confirmed18: false), false)
    try expectEqual(AdultNotice.shouldShow(stored: nil, session: nil, confirmed18: true), false)
    // Negative: any other stored value is not a dismissal.
    try expectEqual(AdultNotice.shouldShow(stored: "ok", session: "dismissed", confirmed18: false), true)
    try expectEqual(AdultNotice.shouldShow(stored: "", session: "", confirmed18: false), true)
    try expectEqual(AdultNotice.key, "kj_adult_notice")
}

func adultNoticeProfileRequest() throws {
    let id = "0b9d1c5e-6f2a-4c53-9a7e-1d2c3b4a5f60"
    let request = try require(PnvAPI.profileRequest(userId: id, accessToken: "TOKEN"))
    try expectEqual(request.url?.absoluteString, "https://qojysegeddztsxdmhjfb.supabase.co/rest/v1/profiles?select=nsfw_age_confirmed&id=eq.\(id)")
    // It is the viewer's own token, with the anon key beside it.
    try expectEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer TOKEN")
    try expectEqual(request.value(forHTTPHeaderField: "apikey"), KJConfig.anonKey)
    // Negative: an id that is not an id adds no filter and sends nothing.
    for bad in ["", "x&select=*", "a b", "1) or (1=1", "ABCDEF"] {
        try expectEqual(PnvAPI.profileRequest(userId: bad, accessToken: "T"), nil, bad)
    }
}

func adultNoticeWordingIsTheSitesOwn() throws {
    let js = String(decoding: try realFile("scripts/kj-adult-notice.js"), as: UTF8.self)
    let start = try require(js.range(of: "<strong>"), "no <strong> in the notice")
    let end = try require(js.range(of: "</p>' +", range: start.upperBound..<js.endIndex), "no </p> in the notice")
    // The copy is JS string fragments joined with +; join them back.
    var text = String(js[start.upperBound..<end.lowerBound])
    text = text.replacingOccurrences(of: "</strong>", with: "|")
    text = text.replacingOccurrences(of: #"'\s*\+\s*'"#, with: "", options: .regularExpression)
    let parts = text.split(separator: "|").map(String.init)
    try expectEqual(parts.count, 2, text)
    try expectEqual(parts[0], AdultNotice.heading)
    try expectEqual(parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "' ")), AdultNotice.body)
    try expect(js.contains("Don\u{2019}t ask again</label>") || js.contains("Don’t ask again"), "checkbox label changed")
    try expect(js.contains("'localStorage'") && js.contains("'dismissed'") && js.contains("var KEY = 'kj_adult_notice'"))
}

// MARK: - Khajistan Radio mixes

func realMixRegister() throws -> MixRegister {
    try JSONDecoder().decode(MixRegister.self, from: try realFile("data/radio/mixtapes.json"))
}

func realMixesDecodeAndAllPlay() throws {
    let data = try realFile("data/radio/mixtapes.json")
    let register = try JSONDecoder().decode(MixRegister.self, from: data)
    let raw = try require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    try expectEqual(register.mixes.count, raw["mix_count"] as? Int, "the register's own count")
    let playable = Mixes.playable(register.mixes)
    try expectEqual(playable.count, register.mixes.count, "every mix in the register plays")
    try expectEqual(playable.map(\.id), register.mixes.map(\.id), "the register's order is kept")
    for mix in playable {
        let url = try require(Mixes.playURL(mix), mix.id)
        try expectEqual(url.scheme, "https")
        try expect(url.pathExtension == "mp3", mix.id)
    }
    // Where the record says a place, the label says it; where it says none, there is none.
    let byID = Dictionary(uniqueKeysWithValues: register.mixes.map { ($0.id, $0) })
    try expectEqual(byID["mix_psychedelistan"]?.place, "Kurdistan")
    try expectEqual(byID["mix_pia"]?.place, "Pakistan")
    try expectEqual(byID["mix_mashriq_maghreb"]?.place, nil)
    try expectEqual(byID["mix_pia"]?.program_block, "Prime Signal")
}

func mixPresentationRules() throws {
    let both = try decode(Mix.self, #"{"id":"a","title":"  ","play_url":"https://x.example/a.mp3","country":"Pakistan","territory":"Punjab","mixed_by":" DJ Z "}"#)
    try expectEqual(both.name, "Khajistan Radio mix")
    try expectEqual(both.place, "Punjab, Pakistan")
    try expectEqual(both.attribution, "A Khajistan Radio mix, mixed by DJ Z and carried by Khajistan.")
    let same = try decode(Mix.self, #"{"id":"a","title":"T","play_url":"https://x.example/a.mp3","country":"Cyprus","territory":"Cyprus"}"#)
    try expectEqual(same.place, "Cyprus")
    try expectEqual(same.name, "T")
    try expectEqual(same.attribution, "A Khajistan Radio mix, made and carried by Khajistan.")
    // Negative: blank strings are no place and no maker.
    let blank = try decode(Mix.self, #"{"id":"a","play_url":"https://x.example/a.mp3","country":" ","territory":"","mixed_by":""}"#)
    try expectEqual(blank.place, nil)
    try expectEqual(blank.attribution, "A Khajistan Radio mix, made and carried by Khajistan.")
}

func mixesRefuseWhatMustNotPlay() throws {
    func mix(_ extra: String) throws -> Mix { try decode(Mix.self, #"{"id":"m",\#(extra)}"#) }
    let good = try mix(#""play_url":"https://qojysegeddztsxdmhjfb.supabase.co/storage/v1/object/public/audio/a.mp3""#)
    let hidden = try mix(#""play_url":"https://x.example/a.mp3","hidden":true"#)
    let notHidden = try mix(#""play_url":"https://x.example/a.mp3","hidden":false"#)
    try expectEqual(Mixes.playable([good, hidden, notHidden]).count, 2)
    for bad in ["http://x.example/a.mp3", "https://localhost/a.mp3", "https://printer.local/a.mp3", "https://10.0.0.5/a.mp3",
                "https://192.168.1.9/a.mp3", "https://172.20.0.1/a.mp3", "https://127.0.0.1/a.mp3", "https://169.254.1.1/a.mp3",
                "https://0.0.0.0/a.mp3", "https://[::1]/a.mp3", "file:///etc/passwd", "not a url", ""] {
        try expectEqual(Mixes.playable([try mix(#""play_url":"\#(bad)""#)]).count, 0, bad)
    }
    // Negative: the public neighbours of the private ranges are fine.
    for ok in ["https://172.32.0.1/a.mp3", "https://172.15.0.1/a.mp3", "https://11.0.0.1/a.mp3", "https://193.168.0.1/a.mp3"] {
        try expectEqual(Mixes.playable([try mix(#""play_url":"\#(ok)""#)]).count, 1, ok)
    }
    try expectEqual(Mixes.registerURL.absoluteString, "https://khajistan-archive.pages.dev/data/radio/mixtapes.json")
}

func mixClockFormat() throws {
    try expectEqual(Mixes.clock(0), "0:00")
    try expectEqual(Mixes.clock(9.9), "0:09")
    try expectEqual(Mixes.clock(75), "1:15")
    try expectEqual(Mixes.clock(3599), "59:59")
    try expectEqual(Mixes.clock(3600), "1:00:00")
    try expectEqual(Mixes.clock(5053), "1:24:13")
    try expectEqual(Mixes.clock(-1), "\u{2014}:\u{2014}")
    try expectEqual(Mixes.clock(.nan), "\u{2014}:\u{2014}")
    try expectEqual(Mixes.clock(.infinity), "\u{2014}:\u{2014}")
}

// MARK: - The dancer: reverence and the beat gate

/// A seeded generator, so a synthetic signal is the same signal on every run.
struct SplitMix {
    var state: UInt64
    mutating func next() -> Double {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        z ^= z >> 31
        return Double(z >> 11) / Double(1 << 53)
    }
    mutating func between(_ a: Double, _ b: Double) -> Double { a + (b - a) * next() }
}

func reverenceFollowsTheSitesRule() throws {
    func reverent(_ name: String?, native: String? = nil, broadcaster: String? = nil,
                  reverent flag: Bool? = nil, visualiser: Bool? = nil) -> Bool {
        Reverence.isReverent(name: name, nativeName: native, broadcaster: broadcaster, reverent: flag, visualiser: visualiser)
    }
    // Positive: the channels' own words.
    for name in ["Saut-ul-Quran", "Quran Radio", "QURAN FM", "Qur'an Kareem", "Holy Koran", "Koranic Studies",
                 "Recitation 24/7", "Radio Tilawat", "Tilawah Channel", "Nida al-Islam", "NIDA ALISLAM"] {
        try expect(reverent(name), "\(name) must be reverent")
    }
    try expect(reverent("Radio 1", native: "إذاعة القرآن الكريم"), "Arabic native name")
    try expect(reverent("Radio 1", native: "قُرْآن"), "Arabic with harakat stripped")
    try expect(reverent("Radio 1", native: "قرـآن"), "Arabic with a tatweel stripped")
    try expect(reverent("Radio 1", broadcaster: "تلاوة"), "the broadcaster field counts")
    try expect(reverent("Radio 1", native: "نداء الإسلام"), "Nida al-Islam in Arabic")
    // A person's ruling on the record beats the name.
    try expect(reverent("City FM89", reverent: true), "reverent: true")
    try expect(reverent("City FM89", visualiser: false), "visualiser: false")
    // Negative: music, news, other faiths' devotional radio, and the switches the other way.
    // "Nida Al Islam" with a space is a negative on the site too: its pattern reads al-islam or
    // alislam, and the port keeps the pattern as it is rather than widening it here.
    for name in ["FM 101 Lahore", "City FM89", "Punjab Rocks Radio", "Live Kirtan from Golden Temple",
                 "Radio Islam", "Nida Al Islam"] {
        try expect(!reverent(name), "\(name) must not be reverent")
    }
    try expect(!reverent("City FM89", reverent: false, visualiser: true), "explicit false/true change nothing")
    try expect(!reverent("Radio 1", native: "إذاعة الشرق"), "an Arabic name without the words")
    try expect(!reverent(nil), "no name")
    try expect(!reverent("", native: "", broadcaster: ""), "empty fields")
    // Channel's own fields reach the rule.
    let channel = try decode(Channel.self, """
    {"id":"x","name":"Mehfil","nativeName":null,"mediaType":"radio","streams":[],"broadcaster":"Saut ul Quran Network"}
    """)
    try expect(channel.isReverent, "Channel.isReverent reads the broadcaster")
    let ruled = try decode(Channel.self, """
    {"id":"y","name":"Mehfil","mediaType":"radio","streams":[],"visualiser":false}
    """)
    try expect(ruled.isReverent, "Channel.isReverent reads visualiser:false")
    let plain = try decode(Channel.self, """
    {"id":"z","name":"Mehfil","mediaType":"radio","streams":[]}
    """)
    try expect(!plain.isReverent, "an ordinary channel")
}

/// 20 ms bins of a drum pattern at `binsPerBeat`: a kick on the beat, a hat on the off-beat,
/// a little timing slack and a noise floor.
func drumEnvelope(_ rng: inout SplitMix, bins: Int = 400, binsPerBeat: Int = 25) -> [Double] {
    var e = (0..<bins).map { _ in rng.next() * 0.06 }
    var beat = Int(rng.next() * Double(binsPerBeat))
    while beat < bins {
        let at = beat + Int(rng.between(-1, 2))
        for (k, a) in [1.0, 0.5, 0.2].enumerated() where at + k >= 0 && at + k < bins { e[at + k] += a * rng.between(0.8, 1.0) }
        let hat = at + binsPerBeat / 2
        if hat < bins { e[hat] += rng.between(0.2, 0.4) }
        beat += binsPerBeat
    }
    return e
}

/// 20 ms bins of speech: syllables at irregular spacing and loudness, in phrases with pauses.
func speechEnvelope(_ rng: inout SplitMix, bins: Int = 400) -> [Double] {
    var e = (0..<bins).map { _ in rng.next() * 0.06 }
    var at = Int(rng.next() * 10)
    var left = Int(rng.between(3, 9))
    while at < bins {
        let a = rng.between(0.3, 1.0)
        for (k, shape) in [1.0, 0.7, 0.35].enumerated() where at + k < bins { e[at + k] += a * shape }
        left -= 1
        if left == 0 {
            at += Int(rng.between(15, 46))      // a pause between phrases, 300–900 ms
            left = Int(rng.between(3, 9))
        } else {
            at += Int(rng.between(6, 19))       // the next syllable, 120–360 ms on
        }
    }
    return e
}

func percentile(_ values: [Double], _ p: Double) -> Double {
    let sorted = values.sorted()
    return sorted[min(sorted.count - 1, Int(Double(sorted.count - 1) * p))]
}

func beatScoreSeparatesADrumFromAVoice() throws {
    var rng = SplitMix(state: 20261005)
    // The synthetic 500 ms pulse is the case the site says scores high.
    var pulse = [Double](repeating: 0, count: 400)
    for i in stride(from: 3, to: 400, by: 25) { pulse[i] = 1 }
    try expect(BeatTracker.score(pulse) > 0.5, "a 500 ms pulse scored \(BeatTracker.score(pulse))")
    // Distributions, not samples: fifty windows of each.
    var drums: [Double] = [], voices: [Double] = []
    for _ in 0..<50 {
        drums.append(BeatTracker.score(drumEnvelope(&rng, binsPerBeat: Int(rng.between(20, 36)))))
        voices.append(BeatTracker.score(speechEnvelope(&rng)))
    }
    let drumMedian = percentile(drums, 0.5), drumLow = percentile(drums, 0.1), voiceP90 = percentile(voices, 0.9)
    print("    beat score: drum median \(String(format: "%.3f", drumMedian)), p10 \(String(format: "%.3f", drumLow)); voice p90 \(String(format: "%.3f", voiceP90)), max \(String(format: "%.3f", voices.max()!))")
    // The site's measured line: music .19–.28 and above, dialogue never above .17 at p90.
    try expect(drumLow > 0.20, "a steady drum must clear the .20 bar (p10 \(drumLow))")
    try expect(voiceP90 <= 0.17, "a voice must stay under .17 at p90 (got \(voiceP90))")
    // Nothing moving is no beat.
    try expectEqual(BeatTracker.score([Double](repeating: 0.4, count: 400)), 0)
    try expectEqual(BeatTracker.score([]), 0)
}

/// Feeds the tracker a 512-bin spectrum at 60 frames a second for `seconds`, the way kj-scope.js
/// reads an AnalyserNode, and returns the times (ms) at which the gate was open.
func runTracker(_ tracker: inout BeatTracker, seconds: Double, from start: Double = 0,
                level: (Double) -> Double, band: (Double) -> ClosedRange<Int> = { _ in 0...511 },
                noise: Double = 4, rng: inout SplitMix) -> [Double] {
    var open: [Double] = []
    var t = start
    var on = false
    while t < start + seconds * 1000 {
        let l = level(t), range = band(t)
        let spectrum: [UInt8] = (0..<512).map { i in
            let lift = range.contains(i) ? l * 150 : 0
            return UInt8(max(0, min(255, 40 + lift + rng.next() * noise)))
        }
        tracker.feed(spectrum, at: t)
        on = tracker.grooving(at: t, on: on)
        if on { open.append(t) }
        t += 1000.0 / 60
    }
    return open
}

func beatGateOpensOnADrumAndNotOnAVoice() throws {
    var rng = SplitMix(state: 7)
    // A drum at 120 BPM: a hit every 500 ms that rings for about 80 ms.
    var drum = BeatTracker()
    let kick: (Double) -> Double = { t in exp(-t.truncatingRemainder(dividingBy: 500) / 80) }
    let drumOpen = runTracker(&drum, seconds: 30, level: kick, rng: &rng)
    let firstOpen = try require(drumOpen.first, "the gate never opened on a steady drum")
    print("    drum: gate open at \(String(format: "%.1f", firstOpen / 1000)) s, open \(drumOpen.count) of 1800 frames, period \(String(format: "%.3f", drum.period)) s")
    // The envelope needs four seconds before it is scored; FM 101 Lahore opened in 6 s on the site.
    try expect(firstOpen >= 4000 && firstOpen <= 8000, "opened at \(firstOpen) ms")
    try expect(Double(drumOpen.count) > 0.7 * 1800, "the gate must stay open on the drum")
    try expect(abs(drum.period - 0.5) < 0.05, "the beat clock locks to 500 ms (\(drum.period))")

    // The same drum ends in digital silence: within the 2.5 s recent-onset rule the gate shuts.
    let silenceStart = 30000.0
    let after = runTracker(&drum, seconds: 6, from: silenceStart, level: { _ in 0 }, noise: 0, rng: &rng)
    try expect(after.allSatisfy { $0 < silenceStart + 2600 }, "a track that ends must not keep the gate open")

    // Speech: syllables at irregular spacing and loudness, each in its own part of the spectrum.
    var voice = BeatTracker()
    var syllables: [(at: Double, a: Double, band: ClosedRange<Int>)] = []
    var at = 0.0, left = 5
    while at < 60000 {
        let lo = Int(rng.between(8, 200))
        syllables.append((at, rng.between(0.3, 1.0), lo...(lo + Int(rng.between(40, 160)))))
        left -= 1
        if left == 0 { at += rng.between(300, 900); left = Int(rng.between(3, 9)) } else { at += rng.between(120, 360) }
    }
    func syllable(_ t: Double) -> (Double, ClosedRange<Int>) {
        guard let s = syllables.last(where: { $0.at <= t }) else { return (0, 0...0) }
        return (s.a * exp(-(t - s.at) / 70), s.band)
    }
    let voiceOpen = runTracker(&voice, seconds: 60, level: { syllable($0).0 }, band: { syllable($0).1 }, rng: &rng)
    print("    voice: gate open \(voiceOpen.count) of 3600 frames, last score \(String(format: "%.3f", voice.beat)), smoothed \(String(format: "%.3f", voice.groove))")
    try expect(voiceOpen.isEmpty, "a voice opened the gate \(voiceOpen.count) times")

    // A steady noise floor and silence never open it.
    var hiss = BeatTracker()
    try expect(runTracker(&hiss, seconds: 20, level: { _ in 0 }, rng: &rng).isEmpty, "hiss opened the gate")
}

func beatGateHysteresis() throws {
    // .20 to come on, .14 to stay on, and only with an onset in the last 2.5 s.
    var rng = SplitMix(state: 11)
    var tracker = BeatTracker()
    _ = runTracker(&tracker, seconds: 12, level: { t in exp(-t.truncatingRemainder(dividingBy: 500) / 80) }, rng: &rng)
    let now = 12000.0
    try expect(tracker.groove > 0.20, "precondition: the drum scored \(tracker.groove)")
    try expect(tracker.grooving(at: now, on: false) && tracker.grooving(at: now, on: true))
    try expect(!tracker.grooving(at: tracker.lastOnset + 2500, on: true), "an onset 2.5 s old is not recent")
    // A clock that runs backwards is a new signal.
    tracker.feed([UInt8](repeating: 40, count: 512), at: 100)
    try expectEqual(tracker.groove, 0)
}

func dancerStageEntersDancesAndLeaves() throws {
    var rng = SplitMix(state: 3)
    var stage = DancerStage(random: { rng.next() })
    var now = 0.0
    func run(_ ms: Double, grooving: Bool, beat: Double = 0.3, groove: Double = 0.25) -> [DancerStage.Frame] {
        var frames: [DancerStage.Frame] = []
        let end = now + ms
        while now < end {
            frames.append(stage.step(now: now, grooving: { _ in grooving }, beat: beat, groove: groove, count: Int(now / 500)))
            now += 1000.0 / 60
        }
        return frames
    }
    // A voice: he never comes on.
    try expect(run(20000, grooving: false).allSatisfy { $0 == .blank }, "a voice brought him on")
    try expectEqual(stage.name, .off)
    // An ambiguous beat must hold a full second before the entrance.
    let early = run(990, grooving: true)
    try expect(early.allSatisfy { $0 == .blank }, "he came on before the second was up")
    _ = run(40, grooving: true)
    try expectEqual(stage.name, .enter)
    try expect(DancerPieces.enter.contains { $0.0 == stage.kind }, "an entrance from the table")
    _ = run(2000, grooving: true)
    try expectEqual(stage.name, .on)
    let dancing = run(8000, grooving: true)
    try expect(dancing.allSatisfy { if case .dance = $0 { return true } else { return false } }, "he dances once on")
    // Lulls under five seconds keep him on; five seconds of no beat send him off by an exit.
    _ = run(4900, grooving: false)
    try expectEqual(stage.name, .on)
    _ = run(200, grooving: false)
    try expectEqual(stage.name, .leave)
    try expect(DancerPieces.exit.contains { $0.0 == stage.kind }, "an exit from the table")
    _ = run(4300, grooving: false)
    try expectEqual(stage.name, .off)

    // A strong rhythm enters within a quarter second.
    _ = run(300, grooving: true, beat: 0.6, groove: 0.45)
    try expectEqual(stage.name, .enter)

    // The channel goes: he leaves by an exit and is seen off with no signal under him.
    _ = run(3000, grooving: true)
    try expect(stage.leave(now: now), "a dancer on stage is owed an exit")
    var frames = 0
    while stage.stepLeaving(now: now) != .blank { now += 1000.0 / 60; frames += 1 }
    try expect(frames > 60, "the exit plays out (\(frames) frames)")
    try expect(!stage.leave(now: now), "nothing is owed when he is off")
}

func dancerMovesFollowTheSite() throws {
    try expectEqual(DancerMoves.all.count, 23)
    try expect(!DancerMoves.list(for: .base).contains("Kawliya"), "Kawliya belongs to the long-haired figure")
    try expect(DancerMoves.list(for: .hairy).contains("Kawliya"))
    var rng = SplitMix(state: 99)
    var counts = [String: Int](), current = 0
    let list = DancerMoves.list(for: .base)
    for _ in 0..<22000 {
        let next = DancerMoves.next(in: list, after: current, random: rng.next())
        try expect(next != current, "a move repeated back to back")
        current = next
        counts[list[next], default: 0] += 1
    }
    // Twerk is weighted four to one.
    let twerk = Double(counts["Twerk"] ?? 0), dabke = Double(counts["Dabke"] ?? 1)
    try expect(twerk / dabke > 3 && twerk / dabke < 5, "Twerk \(twerk) against Dabke \(dabke)")
}

// MARK: - Runner

let tests: [(String, () throws -> Void)] = [
    ("Skin hours at the boundaries", skinHoursAtBoundaries),
    ("Skin hex triples", skinColours),
    ("Skin choice: Automatic follows the hour, a fixed choice holds", skinChoiceResolvesAutomaticAndFixed),
    ("ReceiverIndex regions, URLs and medium lines", receiverIndexRegionsAndLines),
    ("ReceiverIndex without cameraFiles", receiverIndexWithoutCameraFiles),
    ("Channel decoding and active stream", channelDecodesAndFindsItsActiveStream),
    ("Channel.place drops what is unknown", channelPlaceDropsWhatIsNotKnown),
    ("Eligibility keeps the good, drops each withdrawal", eligibilityKeepsTheGoodAndDropsEachWithdrawal),
    ("Eligibility: duplicates once, sorted by name", eligibilityKeepsADuplicateOnceAndSortsByName),
    ("Controls fold the feeds", controlsFoldTheFeedsAndLastHealthRecordWins),
    ("Tiers on by default and medium labels", tiersAndMediumLabels),
    ("carrierURL encodes the stream id", carrierURLEncodesTheStreamID),
    ("Carrier answer is validated", carrierAnswerIsValidated),
    ("validCarrier rules", validCarrierRules),
    ("Deep links parse", deepLinksParse),
    ("Deep links refuse what is not one", deepLinksRefuse),
    ("Transmission routes the three shapes", transmissionRoutesTheThreeShapes),
    ("Transmission never sends the token to another host", transmissionNeverSendsTheTokenToAnotherHost),
    ("Transmission rejects", transmissionRejects),
    ("Transmission requests", transmissionRequests),
    ("Transmission carriers", transmissionCarriers),
    ("Schedule URL, basic authorization, config", scheduleURLAndBasicAuthorization),
    ("Anon key is the site's anon role", anonKeyIsTheSitesAnonRole),
    ("Auth session from a body", authSessionFromBody),
    ("Auth refuses anonymous and malformed bodies", authSessionRefusesAnonymousAndMalformed),
    ("Auth error messages", authErrorMessages),
    ("Auth requests", authRequests),
    ("Session expiry and storage", sessionExpiryAndStorage),
    ("stationNow agrees with Calendar", stationNowAgreesWithCalendar),
    ("stationMonth follows Pakistan time", stationMonthFollowsPakistanTime),
    ("Clock labels", clockLabels),
    ("runSeconds rules", runSecondsRules),
    ("Programme without a title decodes", programmeWithoutATitleDecodes),
    ("positionInSlot walks and wraps the roster", positionInSlotWalksAndWrapsTheRoster),
    ("slotAt and onAir on a hand-made schedule", slotAtAndOnAirOnTheSyntheticSchedule),
    ("nextSlot rolls over every kind of day end", nextSlotRollsOverEveryKindOfDayEnd),
    ("following() walks the roster, then the clock", followingWalksTheRosterAndHandsBackToTheClock),
    ("upcoming() lists the next strips in order", upcomingListsTheNextStripsInOrder),
    ("secondsLeft() counts down to the slot end", secondsLeftCountsDownToTheSlotEnd),
    ("Real October: upcoming() agrees with onAir", realUpcomingAgreesWithOnAir),
    ("StationClock matches the site's JS (differential)", stationClockMatchesTheJS),
    ("The differential comparator can fail", differentialComparatorCanFail),
    ("Edges and the end of the grid", stationClockEdgesAndTheEndOfTheGrid),
    ("following() at every fixture instant", followingAgreesWithTheRosterAtEveryFixtureInstant),
    ("Real receiver-index.json decodes", realReceiverIndexDecodes),
    ("Real shards and withdrawal feeds decode", realShardsAndWithdrawalFeedsDecode),
    ("Every real region shard decodes", everyRealShardDecodes),
    ("Real programming decodes in every month", realProgrammingDecodesInEveryMonth),
    ("Real October schedule clock invariants", realProgrammingClockInvariants),
    ("ViewBox parses and refuses", viewBoxParsesAndRefuses),
    ("SVGPath: absolute subpaths and implicit lineto", svgPathAbsoluteSubpaths),
    ("SVGPath: relative commands, H and V", svgPathRelativeCommands),
    ("SVGPath: number syntax and separators", svgPathNumberSyntax),
    ("SVGPath: short subpaths dropped, unreadable data stops", svgPathDropsShortSubpathsAndStopsOnTheUnreadable),
    ("Map fill follows luminance", mapFillFollowsLuminance),
    ("compose applies each rule on a hand-made map", composeAppliesEachRuleOnAHandMadeMap),
    ("compose holds a core shape tiered islamicate behind the switch", composeHoldsACoreShapeTheIndexTiersIslamicateBehindTheSwitch),
    ("Real core map composes, without the two doors", realRegionMapCoreOnly),
    ("Real map with the extensions composes, doors in place", realRegionMapWithExtensions),
    ("Real map with no regionFiles opens nothing", realMapWithoutRegionFilesOpensNothing),
    ("Real map shows the receiver's region names", realMapUsesReceiverNames),
    ("Pics/Vids: URLs match the site's KJMedia (differential)", pnvMediaMatchesTheSitesJS),
    ("Pics/Vids: the differential comparator can fail", pnvComparatorCanFail),
    ("Pics/Vids: Khajistan TV videos go through tv-play", pnvKtvVideosGoThroughTvPlay),
    ("Pics/Vids: rows decode, with and without a size", pnvRowsDecode),
    ("Pics/Vids: the page's requests", pnvRequests),
    ("Pics/Vids: Content-Range totals", pnvContentRange),
    ("Pics/Vids: account keys follow the roster and the fold", pnvAccountKeysFollowTheRosterAndTheFold),
    ("Pics/Vids: the summary line", pnvSummaryLine),
    ("Pics/Vids: captions", pnvCaptions),
    ("Pics/Vids: the viewer's meta line", pnvMetaLine),
    ("Pics/Vids: the shortest column takes the next tile", pnvLayoutPlacesEachRowInTheShortestColumn),
    ("Adult notice: the suppression rule", adultNoticeSuppressionRule),
    ("Adult notice: the profile request", adultNoticeProfileRequest),
    ("Adult notice: the wording is the site's own", adultNoticeWordingIsTheSitesOwn),
    ("Real mixtapes.json decodes and every mix plays", realMixesDecodeAndAllPlay),
    ("Mix presentation rules", mixPresentationRules),
    ("Mixes refuse what must not play", mixesRefuseWhatMustNotPlay),
    ("Mix clock format", mixClockFormat),
    ("Reverence follows the site's rule, both ways", reverenceFollowsTheSitesRule),
    ("Beat score separates a drum from a voice", beatScoreSeparatesADrumFromAVoice),
    ("Beat gate opens on a drum and not on a voice", beatGateOpensOnADrumAndNotOnAVoice),
    ("Beat gate hysteresis and reset", beatGateHysteresis),
    ("Dancer stage enters, dances and leaves", dancerStageEntersDancesAndLeaves),
    ("Dancer moves follow the site", dancerMovesFollowTheSite),
]

var passed = 0, failed = 0, skipped = 0
for (name, body) in tests {
    do {
        try body()
        passed += 1
        print("PASS \(name)")
    } catch let skip as Skip {
        skipped += 1
        print("SKIP \(name): \(skip.reason)")
    } catch {
        failed += 1
        print("FAIL \(name): \(error)")
    }
}
print("\(tests.count) tests: \(passed) passed, \(failed) failed, \(skipped) skipped")
exit(failed == 0 ? 0 : 1)
