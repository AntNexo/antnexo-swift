import XCTest
@testable import AntNexoCore

final class BridgeTests: XCTestCase {
    func state(app: String? = "Acme", identify: String? = nil) -> NativeState {
        NativeState(platform: .ios,
                    context: AppContext(app: app, app_version: "2.3.0", app_build: "45", os: "iOS", os_version: "18.1",
                                        device: "iPhone16,2", locale: "de-DE"),
                    identify: identify, seen: nil, screenshot: nil)
    }

    func testScriptShape() {
        let s = bridgeScript(state())
        XCTAssertTrue(s.hasPrefix("window.AntNexoApp="), s)
        XCTAssertTrue(s.contains(#""v":1"#))
        XCTAssertTrue(s.contains(#""platform":"ios""#))
        XCTAssertTrue(s.contains(#""sdk":"\#(SDK_VERSION)""#))
        XCTAssertTrue(s.contains(#""identify":null"#))
        XCTAssertTrue(s.contains(#""seen":null"#))
        XCTAssertTrue(s.contains(#""screenshot":null"#))
        XCTAssertTrue(s.contains(#""device":"iPhone16,2""#))
        XCTAssertTrue(s.contains("window.webkit.messageHandlers.antnexo.postMessage(m)"))
        XCTAssertTrue(s.contains("Object.freeze"))
        XCTAssertTrue(bridgeScript(state(identify: "eyJ.a.b")).contains(#""identify":"eyJ.a.b""#))
    }

    func testWrapperPlatformAndSDK() {
        var st = state()
        st.platform = .reactNative
        st.sdk = "9.9.9"
        let s = bridgeScript(st)
        XCTAssertTrue(s.contains(#""platform":"react-native""#), s)
        XCTAssertTrue(s.contains(#""sdk":"9.9.9""#), s)
        XCTAssertEqual(state().sdk, SDK_VERSION)
    }

    func testScriptEscapes() {
        let s = bridgeScript(state(app: "</script><b>\u{2028}\u{2029}\"x"))
        XCTAssertFalse(s.contains("</script>"))
        XCTAssertFalse(s.contains("<b>"))
        XCTAssertFalse(s.contains("\u{2028}"))
        XCTAssertFalse(s.contains("\u{2029}"))
        XCTAssertTrue(s.contains("\\u003c/script>"), s)
        XCTAssertTrue(s.contains("\\u2028"))
    }

    func testScriptOmitsMissingContext() {
        let s = bridgeScript(state(app: nil))
        XCTAssertFalse(s.contains(#""app":"#))
    }
}
