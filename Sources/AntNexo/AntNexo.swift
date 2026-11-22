@_exported import AntNexoCore

#if canImport(WebKit)
import Foundation
import WebKit
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// AntNexo in your app: the workspace's feedback board, roadmap and What's new in a sheet.
///
/// ```swift
/// try AntNexo.configure(host: URL(string: "https://acme.antnexo.com")!, workspace: "acme")
/// await AntNexo.show()
/// ```
@MainActor
public enum AntNexo {
    /// Once, at launch. `host` is the workspace's board host: `https://<slug>.antnexo.com` (recommended: it works on
    /// every plan and never changes with a custom domain) or its custom domain.
    public static func configure(host: URL, workspace: String, options: FeedbackOptions = FeedbackOptions()) throws {
        try Engine.shared.configure(host: host, workspace: workspace, options: options)
    }

    /// When your app has its own accounts: a provider of a fresh identify token, signed by your backend with the
    /// workspace's identify secret (never put the secret in the app). Called each time the sheet opens; nil or an
    /// error opens it without signing the person in. Pass nil to stop.
    public static func identify(_ tokenProvider: (@Sendable () async throws -> String?)?) {
        Engine.shared.tokenProvider = tokenProvider
    }

    /// What happens in the sheet: posts, the What's new count, sign-in, closing.
    public static var onEvent: ((AntNexoEvent) -> Void)? {
        get { Engine.shared.onEvent }
        set { Engine.shared.onEvent = newValue }
    }

    /// Signs the person out of the sheet: clears its web data. Call it on every account switch in your app.
    public static func logout() async {
        await Engine.shared.logout()
    }

    /// What's new: how many entries the person hasn't seen (for a badge on your own button).
    public static func unreadCount() async throws -> Int {
        try await Engine.shared.unreadCount()
    }

    /// For the sample app's scripted checks: runs JS in the open sheet's page. Not part of the API.
    @_spi(Testing)
    public static func evaluateInSheet(_ js: String) async throws -> Any? {
        guard let web = Engine.shared.current?.webView else { return nil }
        return try await web.evaluateJavaScript(js)
    }

    #if canImport(UIKit)
    /// Shows the sheet over `from` (by default the top-most controller of the key window).
    /// - Parameter screenshot: attach a screenshot of the app as it is now; the person sees it and can remove it
    ///   before sending. Off by default: the screen can hold private data.
    public static func show(from: UIViewController? = nil, tab: FeedbackTab? = nil, screenshot: Bool = false) async {
        await present(from: from, tab: tab, screenshot: screenshot, onClose: nil)
    }

    static func present(from: UIViewController?, tab: FeedbackTab?, screenshot: Bool, onClose: (() -> Void)?) async {
        let engine = Engine.shared
        guard let p = await engine.prepare(tab: tab, screenshot: screenshot) else { return onClose?() ?? () }
        guard let presenter = from ?? topController() else {
            log.error("AntNexo.show(): no view controller to present from")
            engine.sheetClosed()
            onClose?()
            return
        }
        let opener = SafariOpener(presenter: nil)
        var sheet: SheetViewController?
        let signIn = SystemSignIn(anchor: { sheet?.view.window })
        let feedback = FeedbackController(host: p.host, workspace: p.workspace, page: p.page, state: p.state,
                                          seenStore: engine.seenStore, dataStore: DataStore.store(for: p.host),
                                          opener: opener, signIn: signIn, onEvent: { engine.onEvent?($0) })
        engine.current = feedback
        let vc = SheetViewController(feedback: feedback) {
            signIn.finish()
            engine.sheetClosed()
            engine.onEvent?(.closed)
            onClose?()
        }
        sheet = vc
        let nav = UINavigationController(rootViewController: vc)
        opener.presenter = nav
        nav.modalPresentationStyle = .pageSheet
        if let s = nav.sheetPresentationController { s.detents = [.large()] }
        presenter.present(nav, animated: true)
    }

    private static func topController() -> UIViewController? {
        var top = keyWindow()?.rootViewController
        while let next = top?.presentedViewController, !next.isBeingDismissed { top = next }
        return top
    }
    #else
    /// Shows the sheet on `from` (by default the key window; a window of its own when there is none).
    /// - Parameter screenshot: attach a screenshot of the app as it is now; the person sees it and can remove it
    ///   before sending. Off by default: the screen can hold private data.
    public static func show(from: NSWindow? = nil, tab: FeedbackTab? = nil, screenshot: Bool = false) async {
        await present(from: from, tab: tab, screenshot: screenshot, onClose: nil)
    }

    static func present(from: NSWindow?, tab: FeedbackTab?, screenshot: Bool, onClose: (() -> Void)?) async {
        let engine = Engine.shared
        guard let p = await engine.prepare(tab: tab, screenshot: screenshot) else { return onClose?() ?? () }
        var window: NSWindow?
        let signIn = SystemSignIn(anchor: { window })
        let feedback = FeedbackController(host: p.host, workspace: p.workspace, page: p.page, state: p.state,
                                          seenStore: engine.seenStore, dataStore: DataStore.store(for: p.host),
                                          opener: BrowserOpener(), signIn: signIn, onEvent: { engine.onEvent?($0) })
        engine.current = feedback
        let vc = SheetViewController(feedback: feedback) {
            signIn.finish()
            engine.sheetClosed()
            engine.onEvent?(.closed)
            onClose?()
        }
        let w = NSWindow(contentViewController: vc)
        w.setContentSize(NSSize(width: 480, height: 720))
        w.isReleasedWhenClosed = false
        window = w
        if let parent = from ?? NSApp.keyWindow ?? NSApp.mainWindow {
            parent.beginSheet(w, completionHandler: nil)
        } else {
            w.styleMask = [.titled, .closable, .resizable]
            w.center()
            w.makeKeyAndOrderFront(nil)
        }
    }
    #endif
}
#endif
