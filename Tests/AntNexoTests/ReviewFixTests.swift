#if canImport(WebKit)
import XCTest
import WebKit
@testable import AntNexo

@MainActor
final class ReviewFixTests: XCTestCase {
    #if os(macOS)
    private var saved: (Bool, () -> String?, () -> AppContext)?

    override func setUp() async throws {
        let e = Engine.shared
        saved = (e.assertsOnMisuse, e.capture, e.context)
        e.assertsOnMisuse = false
        e.capture = { nil }
        e.context = { AppContext(app: "Test") }
        e.tokenProvider = nil
        try e.configure(host: URL(string: "https://splynx.antnexo.com")!, workspace: "splynx", options: FeedbackOptions())
    }

    override func tearDown() async throws {
        let e = Engine.shared
        e.currentSheet?.done()
        if let (a, c, x) = saved { e.assertsOnMisuse = a; e.capture = c; e.context = x }
        e.clearConfiguration()
    }

    /// The window only ordered out (minimised parent, Cmd-H) isn't a close.
    func testDisappearingIsNotClosing() async throws {
        var closed = 0
        await AntNexo.present(from: nil, tab: nil, screenshot: false, onClose: { closed += 1 })
        let sheet = try XCTUnwrap(Engine.shared.currentSheet)
        sheet.viewDidDisappear()
        XCTAssertEqual(closed, 0)
        XCTAssertTrue(Engine.shared.presenting)
        sheet.view.window?.close()
        XCTAssertEqual(closed, 1)
        XCTAssertFalse(Engine.shared.presenting)
    }

    /// Logging out while the sheet is open closes it: the open page mustn't keep the previous person's session.
    func testLogoutClosesTheOpenSheet() async throws {
        var closed = 0
        await AntNexo.present(from: nil, tab: nil, screenshot: false, onClose: { closed += 1 })
        Engine.shared.clearData = { _ in }
        await Engine.shared.logout()
        XCTAssertEqual(closed, 1)
        XCTAssertNil(Engine.shared.currentSheet)
    }

    /// A sheet that never appeared is discarded without a .closed event.
    func testDiscardSendsNoClosed() async throws {
        var events: [AntNexoEvent] = []
        Engine.shared.onEvent = { events.append($0) }
        defer { Engine.shared.onEvent = nil }
        var closed = 0
        await AntNexo.present(from: nil, tab: nil, screenshot: false, onClose: { closed += 1 })
        let sheet = try XCTUnwrap(Engine.shared.currentSheet)
        AntNexo.discard(sheet, onClose: { closed += 1 })
        XCTAssertEqual(closed, 1)
        XCTAssertFalse(events.contains(.closed))
        XCTAssertFalse(Engine.shared.presenting)
        sheet.done()
        XCTAssertEqual(closed, 1)
    }

    /// Closing the sheet frees the controller and its WebView, and the page can't reach the app any more.
    func testClosedSheetIsFreed() async throws {
        let e = Engine.shared
        var closed = 0
        await AntNexo.present(from: nil, tab: nil, screenshot: false, onClose: { closed += 1 })
        weak var fc = e.current
        weak var web = fc?.webView
        XCTAssertNotNil(fc)
        try XCTUnwrap(e.currentSheet).done()
        try await Task.sleep(nanoseconds: 1_000_000_000)
        XCTAssertEqual(closed, 1)
        XCTAssertFalse(e.presenting)
        XCTAssertNil(e.current)
        XCTAssertNil(fc)
        XCTAssertNil(web)
    }
    #endif

    func testTearDownCutsTheBridge() throws {
        let host = try BoardHost(URL(string: "https://splynx.antnexo.com")!)
        let c = FeedbackController(host: host, workspace: "splynx", page: appPageURL(host, workspace: "splynx", FeedbackOptions()),
                                   state: NativeState(platform: .macos, context: AppContext()), seenStore: MemorySeen(),
                                   dataStore: .nonPersistent(), opener: FakeOpener(), signIn: FakeSignIn(), onEvent: { _ in })
        c.tearDown()
        XCTAssertEqual(c.webView.configuration.userContentController.userScripts.count, 0)
        XCTAssertNil(c.webView.navigationDelegate)
    }

    /// Before iOS 17 / macOS 14 there is no store of the SDK's own: a custom-domain board gets a non-persistent one
    /// (logout can't clear a shared site without touching the app's data); a slug host clears only antnexo.com.
    func testLegacyDataStorePolicy() throws {
        let slug = try BoardHost(URL(string: "https://splynx.antnexo.com")!)
        let custom = try BoardHost(URL(string: "https://feedback.acme.com")!)
        XCTAssertFalse(DataStore.legacyEphemeral(slug))
        XCTAssertTrue(DataStore.legacyEphemeral(custom))
        XCTAssertEqual(DataStore.legacyRecordsToClear(["antnexo.com", "acme.com", "google.com"], for: slug), ["antnexo.com"])
        XCTAssertEqual(DataStore.legacyRecordsToClear(["antnexo.com", "acme.com"], for: custom), [])
    }
}
#endif
