import XCTest
@testable import AntNexoCore

final class ConfigTests: XCTestCase {
    func testBoardHostOrigin() throws {
        let h = try BoardHost(URL(string: "https://splynx.antnexo.com")!)
        XCTAssertEqual(h.origin, "https://splynx.antnexo.com")
        XCTAssertNil(h.port)
        XCTAssertEqual(try BoardHost(URL(string: "https://splynx.antnexo.com/")!).origin, "https://splynx.antnexo.com")
        let local = try BoardHost(URL(string: "http://acme.localhost:8090")!)
        XCTAssertEqual(local.origin, "http://acme.localhost:8090")
        XCTAssertEqual(local.port, 8090)
    }

    func testBoardHostRejects() {
        for s in ["ftp://x.com", "https://x.com/path", "https://x.com?q=1", "https://x.com#f", "x.com", "https://u:p@x.com"] {
            XCTAssertThrowsError(try BoardHost(URL(string: s)!), s) { XCTAssertEqual($0 as? AntNexoError, .invalidHost) }
        }
    }

    func testMatches() throws {
        let h = try BoardHost(URL(string: "https://splynx.antnexo.com")!)
        XCTAssertTrue(h.matches(scheme: "https", host: "splynx.antnexo.com", port: 0))
        XCTAssertTrue(h.matches(scheme: "https", host: "splynx.antnexo.com", port: 443))
        XCTAssertTrue(h.matches(scheme: "https", host: "SPLYNX.antnexo.com", port: 0))
        XCTAssertFalse(h.matches(scheme: "http", host: "splynx.antnexo.com", port: 0))
        XCTAssertFalse(h.matches(scheme: "https", host: "splynx.antnexo.com", port: 8443))
        XCTAssertFalse(h.matches(scheme: "https", host: "splynx.antnexo.com.evil.io", port: 0))
        let local = try BoardHost(URL(string: "http://acme.localhost:8090")!)
        XCTAssertTrue(local.matches(scheme: "http", host: "acme.localhost", port: 8090))
        XCTAssertFalse(local.matches(scheme: "http", host: "acme.localhost", port: 0))
    }

    func testAppPageURL() throws {
        let h = try BoardHost(URL(string: "https://splynx.antnexo.com")!)
        XCTAssertEqual(appPageURL(h, workspace: "splynx", FeedbackOptions()).absoluteString,
                       "https://splynx.antnexo.com/app?workspace=splynx")
        var o = FeedbackOptions()
        o.tab = .roadmap
        o.tabs = [.new, .roadmap]
        o.theme = .dark
        o.prompts = false
        o.whatsNew = .off
        o.language = "de"
        XCTAssertEqual(appPageURL(h, workspace: "splynx", o).absoluteString,
                       "https://splynx.antnexo.com/app?workspace=splynx&tab=roadmap&tabs=new,roadmap&theme=dark&prompts=off&whats-new=off&lang=de")
        o = FeedbackOptions()
        o.prompts = true
        o.boards = ["ideas", "bugs"]
        o.color = "#ff0000"
        XCTAssertEqual(appPageURL(h, workspace: "a&b", o).absoluteString,
                       "https://splynx.antnexo.com/app?workspace=a%26b&boards=ideas,bugs&color=%23ff0000&prompts=on")
    }

    func testVersion() {
        XCTAssertEqual(SDK_VERSION, "1.2.0")
    }
}

final class ConfigReviewTests: XCTestCase {
    /// WebKit encodes ' in a query (WHATWG); the gate compares exact URLs, so the SDK must encode it too.
    func testQuoteIsEncoded() throws {
        let h = try BoardHost(URL(string: "https://splynx.antnexo.com")!)
        XCTAssertEqual(appPageURL(h, workspace: "splynx", FeedbackOptions(boards: ["a'b"])).absoluteString,
                       "https://splynx.antnexo.com/app?workspace=splynx&boards=a%27b")
    }

    /// WebKit reports origins in ASCII: the host is kept in its punycode form, however it was given.
    func testIDNHostIsASCII() throws {
        let h = try BoardHost(URL(string: "https://xn--bcher-kva.example")!)
        XCTAssertEqual(h.host, "xn--bcher-kva.example")
        XCTAssertTrue(h.matches(scheme: "https", host: "xn--bcher-kva.example", port: 0))
        let u = URL(string: "https://xn--bcher-kva.example/api/v1/public/oauth/google/start")!
        XCTAssertEqual(parsePageMessage(["type": "auth", "url": u.absoluteString], host: h), .auth(u))
        #if canImport(Darwin)
        XCTAssertEqual(try BoardHost(URL(string: "https://bücher.example")!).host, "xn--bcher-kva.example")
        #endif
    }

    func testIsAntNexoHost() throws {
        XCTAssertTrue(try BoardHost(URL(string: "https://splynx.antnexo.com")!).isAntNexoSubdomain)
        XCTAssertFalse(try BoardHost(URL(string: "https://feedback.acme.com")!).isAntNexoSubdomain)
        XCTAssertFalse(try BoardHost(URL(string: "https://evilantnexo.com")!).isAntNexoSubdomain)
        XCTAssertFalse(try BoardHost(URL(string: "http://acme.localhost:8090")!).isAntNexoSubdomain)
    }
}
