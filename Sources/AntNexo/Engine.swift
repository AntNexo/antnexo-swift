#if canImport(WebKit)
import Foundation
import os
import AntNexoCore

let log = Logger(subsystem: "com.antnexo.sdk", category: "AntNexo")

/// The SDK's state behind the `AntNexo` facade, with seams for tests.
@MainActor
final class Engine {
    static let shared = Engine()

    struct Configuration {
        let host: BoardHost
        let workspace: String
        let options: FeedbackOptions
    }

    struct Prepared {
        let host: BoardHost
        let workspace: String
        let page: URL
        let state: NativeState
    }

    private(set) var configuration: Configuration?
    var tokenProvider: (@Sendable () async throws -> String?)?
    var onEvent: ((AntNexoEvent) -> Void)?
    var seenStore: SeenStore = UserDefaultsSeenStore()
    var identifyTimeout: TimeInterval = 10
    var context: () -> AppContext = { deviceContext() }
    var capture: () -> String? = { captureScreenshot() }
    var fetchDates: (BoardHost) async throws -> [Date] = { try await ChangelogClient(host: $0).publishedDates() }
    var clearData: (BoardHost) async -> Void = { await DataStore.clear(for: $0) }
    var now: () -> Date = { Date() }
    /// The open sheet and its controller.
    private(set) weak var current: FeedbackController?
    private(set) weak var currentSheet: SheetViewController?
    /// Debug builds stop on a misuse (show before configure); tests turn it off.
    var assertsOnMisuse = true
    /// A sheet is up (or being prepared): one at a time.
    private(set) var presenting = false

    func configure(host: URL, workspace: String, options: FeedbackOptions) throws {
        let h = try BoardHost(host)
        let ws = workspace.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ws.isEmpty else { throw AntNexoError.invalidWorkspace }
        configuration = Configuration(host: h, workspace: ws, options: options)
    }

    /// Everything a sheet needs, or nil when it can't open (not configured, one already up). The screenshot is taken
    /// here, before the sheet covers the app. Call sheetClosed() when a non-nil result's sheet goes away.
    func prepare(tab: FeedbackTab?, screenshot: Bool) async -> Prepared? {
        guard let c = configuration else {
            log.error("AntNexo.show() before AntNexo.configure(host:workspace:)")
            if assertsOnMisuse { assertionFailure("AntNexo.show() before AntNexo.configure(host:workspace:)") }
            return nil
        }
        guard !presenting else { return nil }
        presenting = true
        let shot = screenshot ? capture() : nil
        let token = await identifyToken()
        var options = c.options
        if let tab { options.tab = tab }
        let state = NativeState(platform: currentPlatform(), context: context(), identify: token,
                                seen: seenStore.get(workspace: c.workspace), screenshot: shot)
        return Prepared(host: c.host, workspace: c.workspace, page: appPageURL(c.host, workspace: c.workspace, options),
                        state: state)
    }

    func opened(_ feedback: FeedbackController, _ sheet: SheetViewController) {
        current = feedback
        currentSheet = sheet
    }

    func sheetClosed() {
        presenting = false
        current = nil
        currentSheet = nil
    }

    /// The app's token, or nil when it gives none, fails, or takes longer than identifyTimeout (the sheet opens
    /// anyway; the person can sign in our way).
    private func identifyToken() async -> String? {
        guard let provider = tokenProvider else { return nil }
        let token = await firstOf(timeout: identifyTimeout, provider)
        guard let token, !token.isEmpty else { return nil }
        return token
    }

    func unreadCount() async throws -> Int {
        guard let c = configuration else { throw AntNexoError.notConfigured }
        let dates = try await fetchDates(c.host)
        let seen = seenStore.get(workspace: c.workspace).flatMap(parseISODate)
        return AntNexoCore.unreadCount(published: dates, seen: seen, now: now())
    }

    func logout() async {
        guard let c = configuration else { return }
        await clearData(c.host)
    }
}

/// The provider's answer, or nil after `timeout` seconds even if it never returns (it is cancelled, not awaited).
func firstOf(timeout: TimeInterval, _ f: @escaping @Sendable () async throws -> String?) async -> String? {
    final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var cont: CheckedContinuation<String?, Never>?
        init(_ c: CheckedContinuation<String?, Never>) { cont = c }
        func resume(_ v: String?) {
            lock.lock()
            let c = cont
            cont = nil
            lock.unlock()
            c?.resume(returning: v)
        }
    }
    return await withCheckedContinuation { cont in
        let once = Once(cont)
        let timer = Task.detached {
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            once.resume(nil)
        }
        let work = Task.detached {
            let v = try? await f()
            once.resume(v ?? nil)
            timer.cancel()
        }
        Task.detached {
            _ = await timer.result
            work.cancel()
        }
    }
}
#endif
