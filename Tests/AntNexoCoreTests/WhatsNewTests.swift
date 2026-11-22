import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import AntNexoCore

final class StubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var respond: (URLRequest) -> (Int, Data) = { _ in (200, Data()) }
    nonisolated(unsafe) static var requests: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests.append(request)
        let (status, body) = Self.respond(request)
        let r = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: r, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class WhatsNewTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func daysAgo(_ d: Double) -> Date { now.addingTimeInterval(-d * 86400) }

    func testUnreadCount() {
        let dates = [daysAgo(1), daysAgo(29), daysAgo(31)]
        XCTAssertEqual(unreadCount(published: dates, seen: nil, now: now), 2)
        XCTAssertEqual(unreadCount(published: dates, seen: daysAgo(29), now: now), 1)
        XCTAssertEqual(unreadCount(published: dates, seen: daysAgo(0), now: now), 0)
        XCTAssertEqual(unreadCount(published: [], seen: nil, now: now), 0)
        XCTAssertEqual(unreadCount(published: [daysAgo(30)], seen: nil, now: now), 1)
    }

    func session() -> URLSession {
        let c = URLSessionConfiguration.ephemeral
        c.protocolClasses = [StubProtocol.self]
        return URLSession(configuration: c)
    }

    func testChangelogClient() async throws {
        StubProtocol.requests = []
        StubProtocol.respond = { _ in
            (200, Data(#"{"has_more":false,"items":[{"published_at":"2026-10-13T14:47:34.251324Z","title":"a"},{"published_at":"nope"},{"published_at":"2026-10-01T00:00:00Z"}]}"#.utf8))
        }
        let host = try BoardHost(URL(string: "https://splynx.antnexo.com")!)
        let dates = try await ChangelogClient(host: host, session: session()).publishedDates()
        XCTAssertEqual(dates.count, 2)
        XCTAssertEqual(StubProtocol.requests.first?.url?.absoluteString, "https://splynx.antnexo.com/api/v1/public/changelog?limit=20")
        XCTAssertEqual(StubProtocol.requests.first?.httpMethod, "GET")
    }

    func testChangelogErrors() async throws {
        let host = try BoardHost(URL(string: "https://splynx.antnexo.com")!)
        StubProtocol.respond = { _ in (500, Data("{}".utf8)) }
        do {
            _ = try await ChangelogClient(host: host, session: session()).publishedDates()
            XCTFail("no error")
        } catch { XCTAssertEqual(error as? AntNexoError, .http(500)) }
        StubProtocol.respond = { _ in (200, Data("<html>".utf8)) }
        do {
            _ = try await ChangelogClient(host: host, session: session()).publishedDates()
            XCTFail("no error")
        } catch { XCTAssertEqual(error as? AntNexoError, .badResponse) }
    }

    func testFittedSize() {
        XCTAssertTrue(fittedSize(width: 1179, height: 2556) == (738, 1600))
        XCTAssertTrue(fittedSize(width: 3000, height: 1000) == (1600, 533))
        XCTAssertTrue(fittedSize(width: 800, height: 600) == (800, 600))
        XCTAssertTrue(fittedSize(width: 0, height: 0) == (0, 0))
    }
}
