import Foundation

/// A message from the page (`AntNexoApp.post`), after validation. Anything else is ignored.
public enum PageMessage: Equatable, Sendable {
    case ready
    /// A link to open in the system browser (http(s) only).
    case open(URL)
    /// The board's own OAuth start URL, to open in the system's sign-in sheet.
    case auth(URL)
    /// The person saw What's new up to this entry.
    case seen(Date, raw: String)
    case unread(Int)
    case session(signedIn: Bool)
    case identifyFailed(code: String)
    case posted(id: String)
}

/// Parses and validates a page message (a WebKit message body). The caller has already checked that it came from
/// the main frame on the board host. nil: ignore it.
public func parsePageMessage(_ body: Any, host: BoardHost) -> PageMessage? {
    guard let m = body as? [String: Any], let type = m["type"] as? String else { return nil }
    switch type {
    case "ready":
        return .ready
    case "open":
        guard let u = webURL(m["url"]) else { return nil }
        return .open(u)
    case "auth":
        guard let u = webURL(m["url"]), isOAuthStart(u, host: host) else { return nil }
        return .auth(u)
    case "seen":
        guard let s = m["at"] as? String, s.count <= 64, let d = parseISODate(s) else { return nil }
        return .seen(d, raw: s)
    case "unread":
        guard let n = jsInt(m["count"]), (0...999).contains(n) else { return nil }
        return .unread(n)
    case "session":
        guard let b = jsBool(m["signed_in"]) else { return nil }
        return .session(signedIn: b)
    case "identify_failed":
        guard let c = m["code"] as? String else { return nil }
        return .identifyFailed(code: String(c.prefix(64)))
    case "posted":
        guard let id = m["id"] as? String, UUID(uuidString: id) != nil else { return nil }
        return .posted(id: id)
    default:
        return nil
    }
}

/// An http(s) URL with a host, or nil.
func webURL(_ v: Any?) -> URL? {
    guard let s = v as? String, let u = URL(string: s), let scheme = u.scheme?.lowercased(),
          scheme == "https" || scheme == "http", let h = u.host, !h.isEmpty else { return nil }
    return u
}

private let oauthPath = try! NSRegularExpression(pattern: "^/api/v1/public/oauth/[a-z0-9_-]{1,32}/start$")

/// Whether u is the board's own `/api/v1/public/oauth/<provider>/start` (the path compared as sent, still encoded).
func isOAuthStart(_ u: URL, host: BoardHost) -> Bool {
    guard let c = URLComponents(url: u, resolvingAgainstBaseURL: false), let scheme = c.scheme, let h = asciiHost(u),
          c.user == nil, c.password == nil,
          host.matches(scheme: scheme, host: h, port: c.port ?? 0) else { return false }
    let path = c.percentEncodedPath
    return oauthPath.firstMatch(in: path, range: NSRange(path.startIndex..., in: path)) != nil
}

/// An ISO 8601 date with or without fractional seconds (any number of digits).
public func parseISODate(_ s: String) -> Date? {
    let plain = ISO8601DateFormatter()
    if let d = plain.date(from: s) { return d }
    // ISO8601DateFormatter takes up to 3 fraction digits: cut the rest ("…34.251324Z" → "…34.251Z").
    guard let dot = s.firstIndex(of: ".") else { return nil }
    let digits = s[s.index(after: dot)...].prefix { $0.isNumber }
    guard !digits.isEmpty else { return nil }
    let rest = s[s.index(dot, offsetBy: 1 + digits.count)...]
    let frac = ISO8601DateFormatter()
    frac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return frac.date(from: s[..<dot] + "." + digits.prefix(3).padding(toLength: 3, withPad: "0", startingAt: 0) + rest)
}

/// A JS boolean: WebKit sends NSNumber, which must be a real boolean, not 0 or 1.
func jsBool(_ v: Any?) -> Bool? {
    #if canImport(Darwin)
    if let n = v as? NSNumber { return CFGetTypeID(n) == CFBooleanGetTypeID() ? n.boolValue : nil }
    #endif
    return v as? Bool
}

/// A JS integer: a whole number that isn't a boolean.
func jsInt(_ v: Any?) -> Int? {
    #if canImport(Darwin)
    if let n = v as? NSNumber {
        guard CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
        let d = n.doubleValue
        return d.rounded() == d && abs(d) < 1e9 ? Int(d) : nil
    }
    #endif
    if v is Bool { return nil }
    return v as? Int
}

/// Lets through only the first load of the app page in the main frame: every later navigation (a dragged link, a
/// long-press preview, a redirect) is refused, and so is anything in a subframe.
public struct NavigationGate: Sendable {
    let page: URL
    var loaded = false

    public init(page: URL) { self.page = page }

    public mutating func allow(_ url: URL, mainFrame: Bool) -> Bool {
        guard mainFrame, !loaded, url == page else { return false }
        loaded = true
        return true
    }
}
