import Foundation

/// What the page reports as the app's platform. `reactNative` and `flutter` are set by the wrappers.
public enum BridgePlatform: String, Sendable { case ios, macos, reactNative = "react-native", flutter }

/// The app's context the page sends with each post. Every field is optional; nil fields are left out.
public struct AppContext: Sendable, Equatable, Encodable {
    public var app, app_version, app_build, os, os_version, device, locale: String?

    public init(app: String? = nil, app_version: String? = nil, app_build: String? = nil, os: String? = nil,
                os_version: String? = nil, device: String? = nil, locale: String? = nil) {
        self.app = app
        self.app_version = app_version
        self.app_build = app_build
        self.os = os
        self.os_version = os_version
        self.device = device
        self.locale = locale
    }
}

/// What the app hands the page when the sheet opens.
public struct NativeState: Sendable, Equatable {
    public var platform: BridgePlatform
    public var context: AppContext
    /// A fresh identify token from the app's backend; never logged, never in a URL.
    public var identify: String?
    /// What's new: the newest entry seen (ISO 8601), as the page last reported it.
    public var seen: String?
    /// The app's screen as a `data:image/jpeg;base64,…` URL, when the app asked for one.
    public var screenshot: String?
    /// The SDK version the page reports: this package's, or a wrapper's (React Native).
    public var sdk: String

    public init(platform: BridgePlatform, context: AppContext, identify: String? = nil, seen: String? = nil,
                screenshot: String? = nil, sdk: String = SDK_VERSION) {
        self.sdk = sdk
        self.platform = platform
        self.context = context
        self.identify = identify
        self.seen = seen
        self.screenshot = screenshot
    }
}

private struct Payload: Encodable {
    let platform: String
    let sdk: String
    let context: AppContext
    let identify: String?
    let seen: String?
    let screenshot: String?

    enum CodingKeys: String, CodingKey { case v, platform, sdk, context, identify, seen, screenshot }

    func encode(to e: Encoder) throws {
        var c = e.container(keyedBy: CodingKeys.self)
        try c.encode(1, forKey: .v)
        try c.encode(platform, forKey: .platform)
        try c.encode(sdk, forKey: .sdk)
        try c.encode(context, forKey: .context)
        // explicit nulls: the page reads them as "none"
        try c.encode(identify, forKey: .identify)
        try c.encode(seen, forKey: .seen)
        try c.encode(screenshot, forKey: .screenshot)
    }
}

/// The script injected at document start in the main frame: `window.AntNexoApp`, frozen, its `post` sending to the
/// `handler` message handler. Everything the app provides goes through JSON, with `<` and U+2028/U+2029 escaped.
public func bridgeScript(_ s: NativeState, handler: String = "antnexo") -> String {
    let enc = JSONEncoder()
    enc.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let p = Payload(platform: s.platform.rawValue, sdk: s.sdk, context: s.context, identify: s.identify,
                    seen: s.seen, screenshot: s.screenshot)
    let json = (try? String(decoding: enc.encode(p), as: UTF8.self)) ?? "{}"
    let safe = json
        .replacingOccurrences(of: "<", with: "\\u003c")
        .replacingOccurrences(of: "\u{2028}", with: "\\u2028")
        .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
    return "window.AntNexoApp=(function(){var a=\(safe);a.context=Object.freeze(a.context);"
        + "a.post=function(m){window.webkit.messageHandlers.\(handler).postMessage(m)};return Object.freeze(a)})();"
}
