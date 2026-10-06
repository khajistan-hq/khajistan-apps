import Foundation

/// One saved thing, as `public.passport_saves` holds it. The website's Reading Room Save, the
/// receiver's heart and the dashboard read and write these same rows, so a save made on one device
/// is on every device the account signs in on.
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

    /// The account's saves on the receiver and in the Reading Room.
    static func listRequest(userId: String, accessToken: String) -> URLRequest? {
        guard isUserId(userId) else { return nil }
        return request("/rest/v1/passport_saves?select=object_ref,wing,title,href&user_id=eq.\(userId)&wing=in.(receiver,reading-room)&order=created_at.desc&limit=1000",
                       method: "GET", token: accessToken)
    }

    static func insertRequest(userId: String, ref: String, wing: String, title: String, href: String, accessToken: String) -> URLRequest? {
        guard isUserId(userId) else { return nil }
        let row: [String: Any] = ["user_id": userId, "object_ref": ref, "wing": wing, "title": String(title.prefix(200)), "href": href]
        guard let body = try? JSONSerialization.data(withJSONObject: row) else { return nil }
        var call = request("/rest/v1/passport_saves", method: "POST", token: accessToken, body: body)
        call.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        return call
    }

    static func deleteRequest(userId: String, refs: [String], accessToken: String) -> URLRequest? {
        guard isUserId(userId), !refs.isEmpty, refs.allSatisfy({ ref in
            ref.split(separator: ":", maxSplits: 1).count == 2 && isRefSafe(String(ref.split(separator: ":", maxSplits: 1)[1]))
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
        var call = URLRequest(url: URL(string: pathAndQuery, relativeTo: KJConfig.supabase)!.absoluteURL)
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
