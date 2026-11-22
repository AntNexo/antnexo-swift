import Foundation

public enum AntNexoError: Error, Equatable, Sendable {
    /// The host isn't a bare http(s) origin like `https://acme.antnexo.com`.
    case invalidHost
    /// The workspace slug is empty.
    case invalidWorkspace
    /// `AntNexo.configure` wasn't called.
    case notConfigured
    /// The API answered with this HTTP status.
    case http(Int)
    /// The API's answer wasn't what the SDK expected.
    case badResponse
}

/// The widget's color scheme: `auto` follows the system.
public enum FeedbackTheme: String, Sendable { case light, dark, auto }

/// The widget's tabs (`TabKey` in the widget).
public enum FeedbackTab: String, Sendable, CaseIterable { case new, popular, roadmap, changelog }

/// How the widget shows What's new: a badge on its tab, a popup with the newest entry, or not at all.
public enum WhatsNewMode: String, Sendable { case badge, popup, off }

/// The board host the app opens: the workspace's `<slug>.antnexo.com` (recommended) or its custom domain.
public struct BoardHost: Sendable, Equatable {
    public let scheme: String
    public let host: String
    /// nil: the scheme's default port.
    public let port: Int?

    public init(_ url: URL) throws {
        guard let c = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = c.scheme?.lowercased(), scheme == "https" || scheme == "http",
              // the ASCII (punycode) form, as WebKit reports origins; URLComponents.host would decode it
              let host = asciiHost(url), !host.isEmpty,
              c.user == nil, c.password == nil,
              c.path.isEmpty || c.path == "/", c.query == nil, c.fragment == nil
        else { throw AntNexoError.invalidHost }
        self.scheme = scheme
        self.host = host
        self.port = c.port.flatMap { $0 == Self.defaultPort(scheme) ? nil : $0 }
    }

    /// A workspace's own `<slug>.antnexo.com` host (not a custom domain).
    public var isAntNexoSubdomain: Bool { scheme == "https" && host.hasSuffix(".antnexo.com") }

    public var origin: String { "\(scheme)://\(host)" + (port.map { ":\($0)" } ?? "") }

    /// Whether an origin (as WebKit reports it: port 0 for the default) is exactly this host.
    public func matches(scheme: String, host: String, port: Int) -> Bool {
        let s = scheme.lowercased()
        let p = (port == 0 || port == Self.defaultPort(s)) ? nil : port
        return s == self.scheme && host.lowercased() == self.host && p == self.port
    }

    static func defaultPort(_ scheme: String) -> Int { scheme == "https" ? 443 : 80 }
}

/// A URL's host in ASCII form (`xn--bcher-kva.example`), lowercased; nil when it has none or isn't ASCII.
func asciiHost(_ url: URL) -> String? {
    guard let h = url.host?.lowercased(), h.unicodeScalars.allSatisfy(\.isASCII) else { return nil }
    return h
}

/// What the sheet shows; nil leaves the widget's own default.
public struct FeedbackOptions: Sendable, Equatable {
    /// The tab it opens on.
    public var tab: FeedbackTab?
    /// Which tabs, in that order.
    public var tabs: [FeedbackTab]?
    /// Which boards (their slugs).
    public var boards: [String]?
    public var theme: FeedbackTheme?
    /// The accent color, like `#4f46e5`.
    public var color: String?
    /// false: never ask the team's prompt questions.
    public var prompts: Bool?
    public var whatsNew: WhatsNewMode?
    /// The widget's language; by default it follows the app's.
    public var language: String?

    public init(tab: FeedbackTab? = nil, tabs: [FeedbackTab]? = nil, boards: [String]? = nil, theme: FeedbackTheme? = nil, color: String? = nil,
                prompts: Bool? = nil, whatsNew: WhatsNewMode? = nil, language: String? = nil) {
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
    // ' too: WebKit encodes it in a query (WHATWG), and the first load must be exactly this URL
    s.remove(charactersIn: "&=+#?,'")
    return s
}()

/// The app page: `<host>/app?workspace=<slug>` and the set options. Nothing personal goes in it.
public func appPageURL(_ host: BoardHost, workspace: String, _ o: FeedbackOptions) -> URL {
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
