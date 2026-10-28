import Foundation

/// One saved thing, as `public.passport_saves` holds it. The website's Reading Room Save, the
/// receiver's heart and the dashboard read and write these same rows, so a save made on one device
/// is on every device the account signs in on.
/// A named Pics/Vids collection on the account.
struct PnvCollection: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let media_keys: [String]
}

struct PassportSave: Decodable, Equatable, Sendable {
    let object_ref: String
    let wing: String
    let title: String?
    let href: String
}

/// The refs and requests for `passport_saves`. The table grants select, insert and delete to a
/// signed-in account on its own rows, and no update, so a save is an insert of a row the account
/// does not hold yet and an unsave is a delete (open-frequencies.js :429-445, kj-save.js :28-67).
enum PassportSaves {
    static let receiverWing = "receiver"
    static let readingRoomWing = "reading-room"
    static let bornDigitalWing = "born-digital"
    /// The table's catch-all wing. A film is saved here: the table has no film wing.
    static let otherWing = "other"

    /// The id part of a ref, as the table's check allows it: `[A-Za-z0-9._/-]{1,200}`.
    static func isRefSafe(_ text: String) -> Bool {
        !text.isEmpty && text.count <= 200 && text.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0) && $0.isASCII || "._/-".unicodeScalars.contains($0)
        }
    }

    /// Every ref a channel answers to, the one the website writes first: its slug, else its id,
    /// then its id and former ids, so an unsave removes a save made under any of them.
    static func channelRefs(slug: String?, id: String, legacyIds: [String]?) -> [String] {
        var names: [String] = []
        if let slug, isRefSafe(slug) { names.append(slug) }
        for name in [id] + (legacyIds ?? []) where isRefSafe(name) && !names.contains(name) { names.append(name) }
        return names.map { "channel:" + $0 }
    }

    /// Where the dashboard links a saved channel: the receiver, tuned to it.
    static func channelHref(slug: String?, id: String) -> String {
        "/open-frequencies?channel=" + KJURL.encodeQueryValue(slug ?? id)
    }

    static func titleRef(slug: String) -> String? {
        isRefSafe(slug) ? "reading-room:" + slug : nil
    }

    /// The shelf's own link to a title (`?m=<slug>`, the deep link the Reading Room opens a title
    /// on). Not `/reading-room/<slug>/`: only some titles have a page there, and a saved link must open.
    static func titleHref(slug: String) -> String {
        "/reading-room.html?m=" + KJURL.encodeQueryValue(slug)
    }

    /// A Pics/Vids object, as pnv-phone-likes.js writes it: `pnv:<media_key>`, linked to the canvas.
    static func pnvRef(_ key: String) -> String? { isRefSafe(key) ? "pnv:" + key : nil }
    static func pnvHref(_ key: String) -> String { "/canvas?item=" + KJURL.encodeQueryValue(key) }

    /// A Screening Room film, by its Khajistan TV handle (`tv:<handle>`, the system:id the
    /// archive's metadata rules name), linked to the film's own page. A handle in another script
    /// (four are Persian) is one the table's Latin-only check refuses, so it is carried as `u.` and
    /// its UTF-8 bytes in lowercase hex. The app is the only writer of `tv:` rows; the website and
    /// the dashboard read the title and href, never the ref past its prefix.
    static func filmRef(_ handle: String) -> String? {
        if isRefSafe(handle) { return "tv:" + handle }
        let carried = filmHexMark + Data(handle.utf8).map { String(format: "%02x", $0) }.joined()
        return !handle.isEmpty && isRefSafe(carried) ? "tv:" + carried : nil
    }

    /// The handle a film ref names. Hex is read back only where it decodes to a handle that needed
    /// it, so a Latin handle that happens to look like hex is never mistaken for one.
    static func filmHandle(ref: String) -> String? {
        guard ref.hasPrefix("tv:") else { return nil }
        let id = String(ref.dropFirst(3))
        guard id.hasPrefix(filmHexMark), let decoded = fromHex(id.dropFirst(filmHexMark.count)), !isRefSafe(decoded) else { return id }
        return decoded
    }

    private static let filmHexMark = "u."

    private static func fromHex(_ hex: Substring) -> String? {
        let digits = Array(hex.utf8)
        guard !digits.isEmpty, digits.count.isMultiple(of: 2) else { return nil }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(digits.count / 2)
        for at in stride(from: 0, to: digits.count, by: 2) {
            guard let byte = UInt8(String(decoding: digits[at..<at + 2], as: UTF8.self), radix: 16) else { return nil }
            bytes.append(byte)
        }
        return String(bytes: bytes, encoding: .utf8)
    }
    static func filmHref(_ handle: String) -> String { "/film/" + KJURL.encodeQueryValue(handle) }

    /// A page of the site (a Madrassa essay), by its own path, linked to that path.
    static func pageRef(_ id: String) -> String? { isRefSafe(id) ? "page:" + id : nil }

    /// The account's saves: the receiver, the Reading Room, Pics/Vids and films. Newest first.
    static func listRequest(userId: String, accessToken: String) -> URLRequest? {
        guard isUserId(userId) else { return nil }
        return request("/rest/v1/passport_saves?select=object_ref,wing,title,href&user_id=eq.\(userId)&wing=in.(receiver,reading-room,born-digital,other)&order=created_at.desc&limit=1000",
                       method: "GET", token: accessToken)
    }

    /// The account's named Pics/Vids collections (`phone_media_collections`, the website's own).
    static func collectionsRequest(userId: String, accessToken: String) -> URLRequest? {
        guard isUserId(userId) else { return nil }
        return request("/rest/v1/phone_media_collections?select=id,name,media_keys&user_id=eq.\(userId)&order=updated_at.desc&limit=200",
                       method: "GET", token: accessToken)
    }

    /// A new collection, as the website's saveCollection inserts one: only the columns the table
    /// grants a signed-in account (user_id, name, media_keys), never id or the dates, and no upsert.
    /// Its rules are the website's (collectionFields): a name of 1–120 characters once trimmed, at
    /// most 500 keys, each 1–160 characters with no control characters.
    static func collectionInsertRequest(userId: String, name: String, keys: [String], accessToken: String) -> URLRequest? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isUserId(userId), (1...120).contains(trimmed.count), areCollectionKeys(keys),
              let body = try? JSONSerialization.data(withJSONObject: ["user_id": userId, "name": trimmed, "media_keys": keys]) else { return nil }
        var call = request("/rest/v1/phone_media_collections?select=id,name,media_keys", method: "POST", token: accessToken, body: body)
        call.setValue("return=representation", forHTTPHeaderField: "Prefer")
        return call
    }

    /// A collection's objects changed: media_keys only, the one column besides its name the
    /// account may update. The table's trigger moves updated_at. The changed row comes back, so a
    /// collection deleted elsewhere (no row matched) is not taken for a change.
    static func collectionUpdateRequest(userId: String, id: String, keys: [String], accessToken: String) -> URLRequest? {
        guard isUserId(userId), isUserId(id), areCollectionKeys(keys),
              let body = try? JSONSerialization.data(withJSONObject: ["media_keys": keys]) else { return nil }
        var call = request("/rest/v1/phone_media_collections?id=eq.\(id)&user_id=eq.\(userId)&select=id,name,media_keys", method: "PATCH", token: accessToken, body: body)
        call.setValue("return=representation", forHTTPHeaderField: "Prefer")
        return call
    }

    private static func areCollectionKeys(_ keys: [String]) -> Bool {
        keys.count <= 500 && keys.allSatisfy { key in
            (1...160).contains(key.count) && !key.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
        }
    }

    /// `title` is left out where the website leaves it null (a Pics/Vids save carries no title or
    /// picture, so a record taken off the shelf keeps nothing of itself in a library).
    static func insertRequest(userId: String, ref: String, wing: String, title: String?, href: String, accessToken: String) -> URLRequest? {
        guard isUserId(userId) else { return nil }
        var row: [String: Any] = ["user_id": userId, "object_ref": ref, "wing": wing, "href": href]
        // The table counts characters as code points, so the cut is made the same way.
        if let title { row["title"] = String(String.UnicodeScalarView(title.unicodeScalars.prefix(200))) }
        guard let body = try? JSONSerialization.data(withJSONObject: row) else { return nil }
        var call = request("/rest/v1/passport_saves", method: "POST", token: accessToken, body: body)
        call.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        return call
    }

    static func deleteRequest(userId: String, refs: [String], accessToken: String) -> URLRequest? {
        guard isUserId(userId), !refs.isEmpty, refs.allSatisfy({ ref in
            let parts = ref.split(separator: ":", maxSplits: 1)
            return parts.count == 2 && ["channel", "reading-room", "pnv", "tv", "page"].contains(String(parts[0])) && isRefSafe(String(parts[1]))
        }) else { return nil }
        let list = refs.map { "\"\($0)\"" }.joined(separator: ",")
        guard let encoded = list.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&+=#"))) else { return nil }
        var call = request("/rest/v1/passport_saves?user_id=eq.\(userId)&object_ref=in.(\(encoded))", method: "DELETE", token: accessToken)
        call.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        return call
    }

    private static func isUserId(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 64 && id.unicodeScalars.allSatisfy { CharacterSet(charactersIn: "0123456789abcdefABCDEF-").contains($0) }
    }

    private static func request(_ pathAndQuery: String, method: String, token: String, body: Data? = nil) -> URLRequest {
        var call = URLRequest(url: SupabaseRoute.url(pathAndQuery)!)
        call.httpMethod = method
        call.httpBody = body
        call.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        call.setValue(KJConfig.anonKey, forHTTPHeaderField: "apikey")
        call.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        call.setValue(KJConfig.userAgent, forHTTPHeaderField: "User-Agent")
        if body != nil { call.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        return call
    }
}
