import Foundation

public enum AntNexoError: Error, Equatable, Sendable {
    /// The host isn't a bare http(s) origin like `https://acme.antnexo.com`.
    case invalidHost
    /// `AntNexo.configure` wasn't called.
    case notConfigured
    /// The API answered with this HTTP status.
    case http(Int)
    /// The API's answer wasn't what the SDK expected.
    case badResponse
}

/// The widget's color scheme: `auto` follows the system.
public enum Theme: String, Sendable { case light, dark, auto }

/// The widget's tabs (`TabKey` in the widget).
public enum Tab: String, Sendable, CaseIterable { case new, popular, roadmap, changelog }

/// How the widget shows What's new: a badge on its tab, a popup with the newest entry, or not at all.
public enum WhatsNew: String, Sendable { case badge, popup, off }

/// The board host the app opens: the workspace's `<slug>.antnexo.com` (recommended) or its custom domain.
public struct BoardHost: Sendable, Equatable {
    public let scheme: String
    public let host: String
    /// nil: the scheme's default port.
    public let port: Int?

    public init(_ url: URL) throws {
        guard let c = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = c.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = c.host?.lowercased(), !host.isEmpty,
              c.user == nil, c.password == nil,
              c.path.isEmpty || c.path == "/", c.query == nil, c.fragment == nil
        else { throw AntNexoError.invalidHost }
        self.scheme = scheme
        self.host = host
        self.port = c.port.flatMap { $0 == Self.defaultPort(scheme) ? nil : $0 }
    }

    public var origin: String { "\(scheme)://\(host)" + (port.map { ":\($0)" } ?? "") }

    /// Whether an origin (as WebKit reports it: port 0 for the default) is exactly this host.
    public func matches(scheme: String, host: String, port: Int) -> Bool {
        let s = scheme.lowercased()
        let p = (port == 0 || port == Self.defaultPort(s)) ? nil : port
        return s == self.scheme && host.lowercased() == self.host && p == self.port
    }

    static func defaultPort(_ scheme: String) -> Int { scheme == "https" ? 443 : 80 }
}

/// What the sheet shows; nil leaves the widget's own default.
public struct Options: Sendable, Equatable {
    /// The tab it opens on.
    public var tab: Tab?
    /// Which tabs, in that order.
    public var tabs: [Tab]?
    /// Which boards (their slugs).
    public var boards: [String]?
    public var theme: Theme?
    /// The accent color, like `#4f46e5`.
    public var color: String?
    /// false: never ask the team's prompt questions.
    public var prompts: Bool?
    public var whatsNew: WhatsNew?
    /// The widget's language; by default it follows the app's.
    public var language: String?

    public init(tab: Tab? = nil, tabs: [Tab]? = nil, boards: [String]? = nil, theme: Theme? = nil, color: String? = nil,
                prompts: Bool? = nil, whatsNew: WhatsNew? = nil, language: String? = nil) {
        self.tab = tab
        self.tabs = tabs
        self.boards = boards
        self.theme = theme
        self.color = color
        self.prompts = prompts
        self.whatsNew = whatsNew
        self.language = language
    }
}

private let queryValue: CharacterSet = {
    var s = CharacterSet.urlQueryAllowed
    s.remove(charactersIn: "&=+#?,")
    return s
}()

/// The app page: `<host>/app?workspace=<slug>` and the set options. Nothing personal goes in it.
public func appPageURL(_ host: BoardHost, workspace: String, _ o: Options) -> URL {
    var q: [(String, [String])] = [("workspace", [workspace])]
    if let t = o.tab { q.append(("tab", [t.rawValue])) }
    if let t = o.tabs, !t.isEmpty { q.append(("tabs", t.map(\.rawValue))) }
    if let b = o.boards, !b.isEmpty { q.append(("boards", b)) }
    if let t = o.theme { q.append(("theme", [t.rawValue])) }
    if let c = o.color { q.append(("color", [c])) }
    if let p = o.prompts { q.append(("prompts", [p ? "on" : "off"])) }
    if let w = o.whatsNew { q.append(("whats-new", [w.rawValue])) }
    if let l = o.language { q.append(("lang", [l])) }
    // A list's commas stay commas (the widget splits on them); a comma inside a value is encoded.
    let query = q.map { k, vs in
        "\(k)=" + vs.map { $0.addingPercentEncoding(withAllowedCharacters: queryValue) ?? "" }.joined(separator: ",")
    }.joined(separator: "&")
    return URL(string: "\(host.origin)/app?\(query)")!
}
