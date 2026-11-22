#if canImport(WebKit)
import XCTest
import CoreGraphics
import ImageIO
@testable import AntNexo

@MainActor
final class DeviceContextTests: XCTestCase {
    func testFromInfo() {
        let c = deviceContext(info: ["CFBundleDisplayName": "Acme", "CFBundleName": "AcmeX",
                                     "CFBundleShortVersionString": "2.3.0", "CFBundleVersion": "45"],
                              locale: Locale(identifier: "en_CZ"))
        XCTAssertEqual(c.app, "Acme")
        XCTAssertEqual(c.app_version, "2.3.0")
        XCTAssertEqual(c.app_build, "45")
        XCTAssertEqual(c.locale, "en-CZ")
        #if os(macOS)
        XCTAssertEqual(c.os, "macOS")
        XCTAssertEqual(currentPlatform(), .macos)
        #endif
        XCTAssertNotNil(c.os_version?.range(of: #"^\d+\.\d+(\.\d+)?$"#, options: .regularExpression))
        let device = c.device ?? ""
        XCTAssertNotNil(device.range(of: #"^(Mac.*|[A-Za-z]+\d+,\d+)$"#, options: .regularExpression), device)
        XCTAssertEqual(deviceContext(info: ["CFBundleName": "AcmeX"], locale: Locale(identifier: "de")).app, "AcmeX")
        XCTAssertNil(deviceContext(info: nil, locale: Locale(identifier: "de")).app)
    }

    func testJPEGDataURL() throws {
        let ctx = CGContext(data: nil, width: 3200, height: 800, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: 3200, height: 800))
        let url = try XCTUnwrap(jpegDataURL(from: ctx.makeImage()!))
        XCTAssertTrue(url.hasPrefix("data:image/jpeg;base64,"))
        let data = try XCTUnwrap(Data(base64Encoded: String(url.dropFirst("data:image/jpeg;base64,".count))))
        let src = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let img = try XCTUnwrap(CGImageSourceCreateImageAtIndex(src, 0, nil))
        XCTAssertEqual(img.width, 1600)
        XCTAssertEqual(img.height, 400)
    }
}
#endif
