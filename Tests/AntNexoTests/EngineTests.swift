#if canImport(WebKit)
import XCTest
@testable import AntNexo

@MainActor
final class EngineTests: XCTestCase {
    var seen = MemorySeen()

    func make(configured: Bool = true) throws -> Engine {
        let e = Engine()
        e.seenStore = seen
        e.context = { AppContext(app: "Acme") }
        e.capture = { "data:image/jpeg;base64,AAAA" }
        e.identifyTimeout = 0.2
        e.assertsOnMisuse = false
        if configured { try e.configure(host: URL(string: "https://splynx.antnexo.com")!, workspace: "splynx", options: FeedbackOptions()) }
        return e
    }

    func testConfigureValidates() throws {
        let e = try make(configured: false)
        XCTAssertThrowsError(try e.configure(host: URL(string: "https://x.com/path")!, workspace: "x", options: FeedbackOptions()))
        XCTAssertThrowsError(try e.configure(host: URL(string: "https://x.com")!, workspace: " ", options: FeedbackOptions())) {
            XCTAssertEqual($0 as? AntNexoError, .invalidWorkspace)
        }
    }

    func testPrepareBeforeConfigure() async throws {
        let e = try make(configured: false)
        let p = await e.prepare(tab: nil, screenshot: false)
        XCTAssertNil(p)
    }

    func testPrepare() async throws {
        let e = try make()
        seen.set("2026-11-01T00:00:00Z", workspace: "splynx")
        e.tokenProvider = { "jwt" }
        let prepared = await e.prepare(tab: .roadmap, screenshot: false)
        let p = try XCTUnwrap(prepared)
        XCTAssertEqual(p.state.identify, "jwt")
        XCTAssertEqual(p.state.seen, "2026-11-01T00:00:00Z")
        XCTAssertNil(p.state.screenshot)
        XCTAssertEqual(p.state.context.app, "Acme")
        XCTAssertEqual(p.page.absoluteString, "https://splynx.antnexo.com/app?workspace=splynx&tab=roadmap")
        e.sheetClosed()
        let prepared2 = await e.prepare(tab: nil, screenshot: true)
        let q = try XCTUnwrap(prepared2)
        XCTAssertEqual(q.state.screenshot, "data:image/jpeg;base64,AAAA")
    }

    func testWrapper() async throws {
        let e = try make()
        e.wrapper = (.reactNative, "9.9.9")
        let prepared = await e.prepare(tab: nil, screenshot: false)
        let p = try XCTUnwrap(prepared)
        XCTAssertEqual(p.state.platform, .reactNative)
        XCTAssertEqual(p.state.sdk, "9.9.9")
    }

    func testDefaultPlatformAndSDK() async throws {
        let e = try make()
        let prepared = await e.prepare(tab: nil, screenshot: false)
        let p = try XCTUnwrap(prepared)
        XCTAssertEqual(p.state.platform, currentPlatform())
        XCTAssertEqual(p.state.sdk, SDK_VERSION)
    }

    func testShowBeforeConfigureReturnsFalse() async throws {
        let shared = Engine.shared
        shared.clearConfiguration()
        shared.assertsOnMisuse = false
        defer { shared.assertsOnMisuse = true }
        let shown = await AntNexo.show()
        XCTAssertFalse(shown)
        AntNexo.close() // nothing open: a no-op
    }

    func testOneSheetAtATime() async throws {
        let e = try make()
        let first = await e.prepare(tab: nil, screenshot: false)
        XCTAssertNotNil(first)
        let second = await e.prepare(tab: nil, screenshot: false)
        XCTAssertNil(second)
        e.sheetClosed()
        let third = await e.prepare(tab: nil, screenshot: false)
        XCTAssertNotNil(third)
    }

    struct Boom: Error {}

    final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
        func set() { lock.lock(); value = true; lock.unlock() }
    }

    func testTokenProviderFailures() async throws {
        let e = try make()
        let release = Flag()
        let providers: [@Sendable () async throws -> String?] = [
            { throw Boom() },
            { "" },
            { nil },
            { try await Task.sleep(nanoseconds: 5_000_000_000); return "late" },
            { while !release.isSet { usleep(10_000) }; return "too late" },  // ignores cancellation
        ]
        defer { release.set() }  // let the blocked thread go when the test ends
        for provider in providers {
            e.tokenProvider = provider
            let started = Date()
            let p = await e.prepare(tab: nil, screenshot: false)
            XCTAssertNotNil(p)
            XCTAssertNil(p?.state.identify)
            XCTAssertLessThan(Date().timeIntervalSince(started), 2)
            e.sheetClosed()
        }
    }

    func testUnreadCount() async throws {
        let e = try make()
        let now = Date()
        e.now = { now }
        e.fetchDates = { _ in [now.addingTimeInterval(-86400), now.addingTimeInterval(-40 * 86400)] }
        let first = try await e.unreadCount()
        XCTAssertEqual(first, 1)
        seen.set(ISO8601DateFormatter().string(from: now), workspace: "splynx")
        let after = try await e.unreadCount()
        XCTAssertEqual(after, 0)
        let unconfigured = try make(configured: false)
        do {
            _ = try await unconfigured.unreadCount()
            XCTFail("no error")
        } catch { XCTAssertEqual(error as? AntNexoError, .notConfigured) }
    }

    func testLogout() async throws {
        let e = try make()
        seen.set("2026-11-01T00:00:00Z", workspace: "splynx")
        var cleared: [String] = []
        e.clearData = { cleared.append($0.origin) }
        await e.logout()
        XCTAssertEqual(cleared, ["https://splynx.antnexo.com"])
        XCTAssertEqual(seen.get(workspace: "splynx"), "2026-11-01T00:00:00Z")
    }
}
#endif
