import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Where the app keeps What's new's read state (the newest entry seen), per workspace.
public protocol SeenStore: Sendable {
    func get(workspace: String) -> String?
    func set(_ iso: String, workspace: String)
}

/// `UserDefaults` under `antnexo:<workspace>:seen`, like the widget's own storage key.
public final class UserDefaultsSeenStore: SeenStore, @unchecked Sendable {
    let defaults: UserDefaults

    public init(_ defaults: UserDefaults = .standard) { self.defaults = defaults }

    public func get(workspace: String) -> String? { defaults.string(forKey: "antnexo:\(workspace):seen") }
    public func set(_ iso: String, workspace: String) { defaults.set(iso, forKey: "antnexo:\(workspace):seen") }
}

/// On a first run only this recent news counts as new, not the archive (the widget's `FIRST_VISIT_DAYS`).
let firstRunDays: Double = 30

/// The widget's rule (`unreadEntries`): entries published after the newest one seen; with nothing seen, those of the
/// last 30 days.
public func unreadCount(published: [Date], seen: Date?, now: Date) -> Int {
    if let seen { return published.filter { $0 > seen }.count }
    let since = now.addingTimeInterval(-firstRunDays * 86400)
    return published.filter { $0 >= since }.count
}

/// Reads the board's public changelog (no sign-in, nothing personal sent).
public struct ChangelogClient: Sendable {
    let host: BoardHost
    let session: URLSession

    public init(host: BoardHost, session: URLSession = .shared) {
        self.host = host
        self.session = session
    }

    private struct Page: Decodable {
        struct Item: Decodable { let published_at: String }
        let items: [Item]
    }

    /// The publication dates of the newest 20 entries; entries with an unreadable date are skipped.
    public func publishedDates() async throws -> [Date] {
        var req = URLRequest(url: URL(string: "\(host.origin)/api/v1/public/changelog?limit=20")!)
        req.httpMethod = "GET"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, res) = try await session.data(for: req)
        guard let http = res as? HTTPURLResponse else { throw AntNexoError.badResponse }
        guard (200..<300).contains(http.statusCode) else { throw AntNexoError.http(http.statusCode) }
        guard let page = try? JSONDecoder().decode(Page.self, from: data) else { throw AntNexoError.badResponse }
        return page.items.compactMap { parseISODate($0.published_at) }
    }
}
