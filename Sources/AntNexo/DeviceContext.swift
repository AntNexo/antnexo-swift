#if canImport(WebKit)
import Foundation
import AntNexoCore
#if canImport(UIKit)
import UIKit
#endif

/// The platform this build runs on.
func currentPlatform() -> BridgePlatform {
    #if os(macOS)
    return .macos
    #else
    return .ios
    #endif
}

/// The app's context sent with posts: its name, version and build, the OS and its version, the device model and the
/// locale. Nothing that identifies the device itself (no identifiers, no serial).
@MainActor
func deviceContext(info: [String: Any]? = Bundle.main.infoDictionary, locale: Locale = .current) -> AppContext {
    let v = ProcessInfo.processInfo.operatingSystemVersion
    let osVersion = v.patchVersion > 0 ? "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
        : "\(v.majorVersion).\(v.minorVersion)"
    return AppContext(
        app: nonEmpty(info?["CFBundleDisplayName"]) ?? nonEmpty(info?["CFBundleName"]),
        app_version: nonEmpty(info?["CFBundleShortVersionString"]),
        app_build: nonEmpty(info?["CFBundleVersion"]),
        os: osName(),
        os_version: osVersion,
        device: deviceModel(),
        locale: bcp47(locale.identifier)
    )
}

private func nonEmpty(_ v: Any?) -> String? {
    guard let s = v as? String, !s.isEmpty else { return nil }
    return s
}

@MainActor
private func osName() -> String {
    #if os(macOS)
    return "macOS"
    #else
    return UIDevice.current.systemName  // "iOS", "iPadOS"
    #endif
}

/// The model identifier: `iPhone16,2`, `Mac15,3`; the simulated model in the simulator.
private func deviceModel() -> String? {
    #if os(macOS)
    var size = 0
    sysctlbyname("hw.model", nil, &size, nil, 0)
    guard size > 0 else { return nil }
    var buf = [UInt8](repeating: 0, count: size)
    sysctlbyname("hw.model", &buf, &size, nil, 0)
    return String(decoding: buf.prefix { $0 != 0 }, as: UTF8.self)
    #else
    if let sim = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] { return sim }
    var u = utsname()
    uname(&u)
    return withUnsafeBytes(of: &u.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
    #endif
}
#endif
