import Foundation

/// Where the app talks to. Everything here is public by design: the anon key is the same
/// literal the site ships in scripts/kj-chrome.js (payload role "anon"), so it grants a
/// signed-out visitor nothing a browser does not already have. No other key belongs here.
enum KJConfig {
    static let site = URL(string: "https://khajistan-archive.pages.dev")!
    static let supabase = URL(string: "https://qojysegeddztsxdmhjfb.supabase.co")!
    static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFvanlzZWdlZGR6dHN4ZG1oamZiIiwicm9sZSI6ImFub24iLCJpYXQiOjE2Nzc1MjM5MjQsImV4cCI6MTk5MzA5OTkyNH0.iz8hhr1TYYLWk9HyI0b_yxqlzGJgyuXKsBO_2_kuQ94"
    static let streamHost = "customer-0svgnorro16tedsf.cloudflarestream.com"
    static let userAgent = "Khajistan-iOS/1.0"
    static let previewUser = "khajistan"
    static let keychainService = "com.khajistan.archive"
}

/// URL building shared by the Core files.
enum KJURL {
    /// Percent-encodes everything except RFC 3986 unreserved characters, so `+`, `&`, `=`,
    /// `#` and `/` inside an opaque id can never be read as query syntax. `URLQueryItem`
    /// leaves some of those alone, which is why it is not used for ids.
    static func encodeQueryValue(_ value: String) -> String {
        var allowed = CharacterSet()
        allowed.insert(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }

    /// An absolute path ("/data/x.json", never "//host/x" or a full URL) placed on the site
    /// origin. A path that names another host is a nil, not a redirect of the app.
    static func sitePath(_ reference: String) -> URL? {
        guard reference.hasPrefix("/"), !reference.hasPrefix("//"),
              var parts = URLComponents(string: reference) else { return nil }
        parts.scheme = KJConfig.site.scheme
        parts.host = KJConfig.site.host
        return parts.url
    }
}
