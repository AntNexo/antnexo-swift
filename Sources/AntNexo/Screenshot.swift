#if canImport(WebKit)
import Foundation
import AntNexoCore
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// The app's key window as a JPEG data URL (≤ 1600 px), taken before the sheet shows; nil without a window.
@MainActor
func captureScreenshot() -> String? {
    #if canImport(UIKit)
    guard let window = keyWindow() else { return nil }
    let format = UIGraphicsImageRendererFormat()
    format.scale = window.screen.scale
    let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
        window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
    }
    return image.cgImage.flatMap { jpegDataURL(from: $0) }
    #else
    guard let view = NSApp.keyWindow?.contentView ?? NSApp.mainWindow?.contentView,
          let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
    view.cacheDisplay(in: view.bounds, to: rep)
    return rep.cgImage.flatMap { jpegDataURL(from: $0) }
    #endif
}

#if canImport(UIKit)
/// The foreground scene's key window.
@MainActor
func keyWindow() -> UIWindow? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let active = scenes.filter { $0.activationState == .foregroundActive }
    return (active.isEmpty ? scenes : active).flatMap(\.windows).first { $0.isKeyWindow }
}
#endif

/// The image scaled to fit `max` on its longest side, as `data:image/jpeg;base64,…` (quality 0.7).
func jpegDataURL(from image: CGImage, max: Int = 1600) -> String? {
    let size = fittedSize(width: image.width, height: image.height, max: max)
    guard size.width > 0, size.height > 0,
          let ctx = CGContext(data: nil, width: size.width, height: size.height, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
    ctx.interpolationQuality = .high
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
    guard let scaled = ctx.makeImage() else { return nil }
    let data = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
    CGImageDestinationAddImage(dest, scaled, [kCGImageDestinationLossyCompressionQuality: 0.7] as CFDictionary)
    guard CGImageDestinationFinalize(dest) else { return nil }
    return "data:image/jpeg;base64," + (data as Data).base64EncodedString()
}
#endif
