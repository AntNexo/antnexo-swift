#if canImport(WebKit)
import XCTest
import WebKit
@testable import AntNexo

@MainActor
final class FakeOpener: LinkOpener {
    var opened: [URL] = []
    func open(_ url: URL) { opened.append(url) }
}

@MainActor
final class FakeSignIn: SignInPresenter {
    var started: [URL] = []
    var finished = 0
    var onClosed: (() -> Void)?
    func start(_ url: URL, onClosed: @escaping () -> Void) {
        started.append(url)
        self.onClosed = onClosed
    }
    func finish() { finished += 1 }
}

final class MemorySeen: SeenStore, @unchecked Sendable {
    var values: [String: String] = [:]
    func get(workspace: String) -> String? { values[workspace] }
    func set(_ iso: String, workspace: String) { values[workspace] = iso }
}

@MainActor
final class FeedbackControllerTests: XCTestCase {
    let host = try! BoardHost(URL(string: "https://splynx.antnexo.com")!)
    var opener = FakeOpener()
    var signIn = FakeSignIn()
    var seen = MemorySeen()
    var events: [AntNexoEvent] = []
    var js: [String] = []

    var page: URL { appPageURL(host, workspace: "splynx", Options()) }
    let state = NativeState(platform: .macos, context: AppContext(app: "Acme"), identify: "jwt.token.x")

    func make() -> FeedbackController {
        let c = FeedbackController(host: host, workspace: "splynx", page: page, state: state, seenStore: seen,
                                   dataStore: .nonPersistent(), opener: opener, signIn: signIn,
                                   onEvent: { [unowned self] in self.events.append($0) })
        c.runJS = { [unowned self] in self.js.append($0) }
        return c
    }

    func testAcceptsOnlyTheBoardMainFrame() {
        let c = make()
        XCTAssertTrue(c.accept(isMainFrame: true, scheme: "https", host: "splynx.antnexo.com", port: 0))
        XCTAssertFalse(c.accept(isMainFrame: false, scheme: "https", host: "splynx.antnexo.com", port: 0))
        XCTAssertFalse(c.accept(isMainFrame: true, scheme: "http", host: "splynx.antnexo.com", port: 0))
        XCTAssertFalse(c.accept(isMainFrame: true, scheme: "https", host: "splynx.antnexo.com", port: 8443))
        XCTAssertFalse(c.accept(isMainFrame: true, scheme: "https", host: "evil.io", port: 0))
    }

    func testReceiveIgnoresForeignFrames() {
        let c = make()
        c.receive(["type": "open", "url": "https://antnexo.com"], isMainFrame: false, scheme: "https", host: "splynx.antnexo.com", port: 0)
        c.receive(["type": "open", "url": "https://antnexo.com"], isMainFrame: true, scheme: "https", host: "evil.io", port: 0)
        c.receive(["type": "open", "url": "javascript:alert(1)"], isMainFrame: true, scheme: "https", host: "splynx.antnexo.com", port: 0)
        XCTAssertEqual(opener.opened, [])
        c.receive(["type": "open", "url": "https://antnexo.com"], isMainFrame: true, scheme: "https", host: "splynx.antnexo.com", port: 0)
        XCTAssertEqual(opener.opened, [URL(string: "https://antnexo.com")!])
    }

    func testMessages() {
        let c = make()
        let auth = URL(string: "https://splynx.antnexo.com/api/v1/public/oauth/google/start?poll=x")!
        c.handle(.auth(auth))
        XCTAssertEqual(signIn.started, [auth])
        signIn.onClosed?()
        XCTAssertEqual(js, ["window.dispatchEvent(new CustomEvent('antnexo:native',{detail:{type:'auth_closed'}}))"])
        c.handle(.session(signedIn: true))
        XCTAssertEqual(signIn.finished, 1)
        c.handle(.session(signedIn: false))
        XCTAssertEqual(signIn.finished, 1)
        c.handle(.seen(Date(), raw: "2026-11-01T00:00:00Z"))
        XCTAssertEqual(seen.get(workspace: "splynx"), "2026-11-01T00:00:00Z")
        c.handle(.unread(4))
        c.handle(.posted(id: "01a135ba-e43c-7047-85cc-644923023748"))
        c.handle(.identifyFailed(code: "expired"))
        XCTAssertEqual(events, [.signedIn(true), .signedIn(false), .unread(count: 4),
                                .posted(id: "01a135ba-e43c-7047-85cc-644923023748"), .identifyFailed(code: "expired")])
    }

    func testConfiguration() {
        let c = make()
        let cfg = c.webView.configuration
        let scripts = cfg.userContentController.userScripts
        XCTAssertEqual(scripts.count, 1)
        XCTAssertEqual(scripts.first?.injectionTime, .atDocumentStart)
        XCTAssertEqual(scripts.first?.isForMainFrameOnly, true)
        XCTAssertEqual(scripts.first?.source, bridgeScript(state))
        XCTAssertFalse(cfg.preferences.javaScriptCanOpenWindowsAutomatically)
    }

    func testDeallocates() {
        weak var weakC: FeedbackController?
        autoreleasepool {
            let c = make()
            weakC = c
            c.load()
        }
        XCTAssertNil(weakC)
    }

    func testNavigationPolicy() {
        let c = make()
        var failed = 0
        c.onLoadFailed = { failed += 1 }
        XCTAssertEqual(c.policy(for: page, mainFrame: true), .allow)
        // the page redirected before it loaded: refused, and the sheet shows its retry view
        XCTAssertEqual(c.policy(for: URL(string: "https://other.antnexo.com/app")!, mainFrame: true), .cancel)
        XCTAssertEqual(failed, 1)
        c.retry()
        XCTAssertEqual(c.policy(for: page, mainFrame: true), .allow)
        c.webView(c.webView, didFinish: nil)
        XCTAssertEqual(c.policy(for: page, mainFrame: true), .cancel)
        XCTAssertEqual(c.policy(for: URL(string: "https://antnexo.com/x")!, mainFrame: true, link: true), .cancel)
        XCTAssertEqual(c.policy(for: URL(string: "https://antnexo.com/y")!, mainFrame: true), .cancel)
        XCTAssertEqual(c.policy(for: URL(string: "about:blank")!, mainFrame: false), .cancel)
        XCTAssertEqual(c.policy(for: URL(string: "javascript:x")!, mainFrame: true, link: true), .cancel)
        // a dragged or long-pressed http(s) link still goes to the browser; script navigations don't
        XCTAssertEqual(opener.opened, [URL(string: "https://antnexo.com/x")!])
        XCTAssertEqual(failed, 1)
    }

    func testNewWindowGoesToTheBrowser() {
        let c = make()
        c.openNewWindow(URL(string: "https://antnexo.com/w")!)
        c.openNewWindow(URL(string: "file:///etc/passwd")!)
        XCTAssertEqual(opener.opened, [URL(string: "https://antnexo.com/w")!])
    }

    func testDataStorePerHost() {
        guard #available(macOS 14, iOS 17, *) else { return }
        XCTAssertEqual(DataStore.identifier(for: host), DataStore.identifier(for: host))
        let other = try! BoardHost(URL(string: "https://acme.antnexo.com")!)
        XCTAssertNotEqual(DataStore.identifier(for: host), DataStore.identifier(for: other))
    }
}
#endif
