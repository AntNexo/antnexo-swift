import XCTest
@testable import AntNexoCore

final class PolicyTests: XCTestCase {
    let host = try! BoardHost(URL(string: "https://splynx.antnexo.com")!)

    func parse(_ body: Any) -> PageMessage? { parsePageMessage(body, host: host) }

    func testSimple() {
        XCTAssertEqual(parse(["type": "ready"]), .ready)
        XCTAssertNil(parse(["type": "nope"]))
        XCTAssertNil(parse("ready"))
        XCTAssertNil(parse(["kind": "ready"]))
        XCTAssertNil(parse([1, 2]))
    }

    func testOpen() {
        XCTAssertEqual(parse(["type": "open", "url": "https://antnexo.com/x"]), .open(URL(string: "https://antnexo.com/x")!))
        XCTAssertEqual(parse(["type": "open", "url": "http://example.com"]), .open(URL(string: "http://example.com")!))
        for u in ["javascript:alert(1)", "file:///etc/passwd", "data:text/html,hi", "tel:123", "", "https://"] {
            XCTAssertNil(parse(["type": "open", "url": u]), u)
        }
        XCTAssertNil(parse(["type": "open"]))
        XCTAssertNil(parse(["type": "open", "url": 5]))
    }

    func testAuth() {
        let ok = "https://splynx.antnexo.com/api/v1/public/oauth/google/start?poll=abc"
        XCTAssertEqual(parse(["type": "auth", "url": ok]), .auth(URL(string: ok)!))
        XCTAssertNotNil(parse(["type": "auth", "url": "https://SPLYNX.antnexo.com:443/api/v1/public/oauth/git_hub-2/start"]))
        for u in [
            "https://evil.io/api/v1/public/oauth/google/start",
            "https://splynx.antnexo.com.evil.io/api/v1/public/oauth/google/start",
            "http://splynx.antnexo.com/api/v1/public/oauth/google/start",
            "https://splynx.antnexo.com:8443/api/v1/public/oauth/google/start",
            "https://splynx.antnexo.com/api/v1/public/oauth/goo%2Fgle/start",
            "https://splynx.antnexo.com/api/v1/public/oauth/../x/start",
            "https://splynx.antnexo.com/api/v1/public/oauth/google/start/extra",
            "https://splynx.antnexo.com/api/v1/public/oauth/Google/start",
            "https://splynx.antnexo.com/app",
            "https://user@splynx.antnexo.com/api/v1/public/oauth/google/start",
            "javascript:alert(1)",
        ] {
            XCTAssertNil(parse(["type": "auth", "url": u]), u)
        }
    }

    func testSeen() {
        let a = "2026-10-13T14:47:34.251324Z"
        guard case .seen(let d, let raw) = parse(["type": "seen", "at": a]) else { return XCTFail() }
        XCTAssertEqual(raw, a)
        XCTAssertEqual(d.timeIntervalSince1970, 1_791_902_854.251, accuracy: 0.01)
        XCTAssertNotNil(parse(["type": "seen", "at": "2026-10-13T14:47:34Z"]))
        XCTAssertNotNil(parse(["type": "seen", "at": "2026-10-13T14:47:34.5Z"]))
        XCTAssertNil(parse(["type": "seen", "at": "yesterday"]))
        XCTAssertNil(parse(["type": "seen", "at": 5]))
        XCTAssertNil(parse(["type": "seen", "at": String(repeating: "9", count: 100)]))
    }

    func testUnread() {
        XCTAssertEqual(parse(["type": "unread", "count": 3]), .unread(3))
        XCTAssertEqual(parse(["type": "unread", "count": 0]), .unread(0))
        for c: Any in [-1, 1000, "3", 2.5, true] {
            XCTAssertNil(parse(["type": "unread", "count": c]), "\(c)")
        }
    }

    func testSessionFailedPosted() {
        XCTAssertEqual(parse(["type": "session", "signed_in": true]), .session(signedIn: true))
        XCTAssertEqual(parse(["type": "session", "signed_in": false]), .session(signedIn: false))
        XCTAssertNil(parse(["type": "session", "signed_in": "yes"]))
        XCTAssertNil(parse(["type": "session", "signed_in": 1]))
        XCTAssertEqual(parse(["type": "identify_failed", "code": "expired"]), .identifyFailed(code: "expired"))
        XCTAssertEqual(parse(["type": "identify_failed", "code": String(repeating: "x", count: 100)]),
                       .identifyFailed(code: String(repeating: "x", count: 64)))
        XCTAssertNil(parse(["type": "identify_failed"]))
        let id = "01a135ba-e43c-7047-85cc-644923023748"
        XCTAssertEqual(parse(["type": "posted", "id": id]), .posted(id: id))
        XCTAssertNil(parse(["type": "posted", "id": "x"]))
    }

    func testGate() {
        let page = URL(string: "https://splynx.antnexo.com/app?workspace=splynx")!
        var g = NavigationGate(page: page)
        XCTAssertFalse(g.allow(page, mainFrame: false))
        XCTAssertTrue(g.allow(page, mainFrame: true))
        XCTAssertFalse(g.allow(page, mainFrame: true))
        XCTAssertFalse(g.allow(URL(string: "https://splynx.antnexo.com/x")!, mainFrame: true))
        var g2 = NavigationGate(page: page)
        XCTAssertFalse(g2.allow(URL(string: "about:blank")!, mainFrame: true))
        XCTAssertFalse(g2.allow(URL(string: "https://evil.io")!, mainFrame: true))
        XCTAssertTrue(g2.allow(page, mainFrame: true))
    }

    func testBCP47() {
        XCTAssertEqual(bcp47("en_CZ"), "en-CZ")
        XCTAssertEqual(bcp47("zh-Hans_CN"), "zh-Hans-CN")
        XCTAssertEqual(bcp47("de"), "de")
        XCTAssertEqual(bcp47("en_US@calendar=japanese"), "en-US")
        XCTAssertEqual(bcp47(""), "und")
        XCTAssertEqual(bcp47(String(repeating: "a", count: 50)).count, 35)
    }
}

#if canImport(Darwin)
/// WebKit hands JS numbers and booleans over as NSNumber: a boolean must not pass as a count, nor 1 as true.
final class NSNumberPolicyTests: XCTestCase {
    let host = try! BoardHost(URL(string: "https://splynx.antnexo.com")!)

    func testNSNumbers() {
        XCTAssertEqual(parsePageMessage(["type": "unread", "count": NSNumber(value: 4)] as NSDictionary, host: host), .unread(4))
        XCTAssertNil(parsePageMessage(["type": "unread", "count": NSNumber(value: true)] as NSDictionary, host: host))
        XCTAssertNil(parsePageMessage(["type": "unread", "count": NSNumber(value: 2.5)] as NSDictionary, host: host))
        XCTAssertEqual(parsePageMessage(["type": "session", "signed_in": NSNumber(value: true)] as NSDictionary, host: host),
                       .session(signedIn: true))
        XCTAssertNil(parsePageMessage(["type": "session", "signed_in": NSNumber(value: 1)] as NSDictionary, host: host))
    }
}
#endif
