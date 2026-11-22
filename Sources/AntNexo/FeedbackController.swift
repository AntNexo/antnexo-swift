#if canImport(WebKit)
import Foundation
import WebKit
import AntNexoCore

/// What the SDK reports to the app.
public enum AntNexoEvent: Sendable, Equatable {
    /// The person created a post.
    case posted(id: String)
    /// The sheet was closed.
    case closed
    /// What's new: how many entries the person hasn't seen.
    case unread(count: Int)
    /// Whether the person is signed in in the sheet.
    case signedIn(Bool)
    /// The identify token was refused (expired, wrong secret…); the person can still sign in our way.
    case identifyFailed(code: String)
}

/// Opens a link outside the sheet (the system browser).
@MainActor public protocol LinkOpener: AnyObject { func open(_ url: URL) }

/// The system's sign-in sheet for provider sign-in.
@MainActor public protocol SignInPresenter: AnyObject {
    /// Opens url; onClosed when the person closes it (not after finish()).
    func start(_ url: URL, onClosed: @escaping () -> Void)
    /// Closes it: the page is signed in.
    func finish()
}

/// Forwards script messages without the content controller keeping the controller alive.
private final class WeakHandler: NSObject, WKScriptMessageHandler {
    weak var target: FeedbackController?
    init(_ t: FeedbackController) { target = t }

    func userContentController(_ uc: WKUserContentController, didReceive message: WKScriptMessage) {
        MainActor.assumeIsolated {
            let o = message.frameInfo.securityOrigin
            target?.receive(message.body, isMainFrame: message.frameInfo.isMainFrame, scheme: o.protocol, host: o.host,
                            port: o.port)
        }
    }
}

/// The WebView and its bridge (spec §3/§3a): loads the app page once, injects `AntNexoApp`, takes messages only from
/// the board's main frame, and sends every other navigation to the browser.
@MainActor
final class FeedbackController: NSObject, WKNavigationDelegate, WKUIDelegate {
    static let handlerName = "antnexo"

    let host: BoardHost
    let workspace: String
    let page: URL
    let webView: WKWebView
    private let seenStore: SeenStore
    private let opener: LinkOpener
    private let signIn: SignInPresenter
    private let onEvent: (AntNexoEvent) -> Void
    private var gate: NavigationGate
    /// The page finished loading.
    private var finished = false
    /// Runs JS in the page (tests replace it).
    var runJS: (String) -> Void = { _ in }
    /// The page didn't load (offline, refused, an error status): the sheet shows its retry view.
    var onLoadFailed: (() -> Void)?
    /// The page loaded.
    var onLoaded: (() -> Void)?

    init(host: BoardHost, workspace: String, page: URL, state: NativeState, seenStore: SeenStore,
         dataStore: WKWebsiteDataStore, opener: LinkOpener, signIn: SignInPresenter,
         onEvent: @escaping (AntNexoEvent) -> Void) {
        self.host = host
        self.workspace = workspace
        self.page = page
        self.seenStore = seenStore
        self.opener = opener
        self.signIn = signIn
        self.onEvent = onEvent
        gate = NavigationGate(page: page)

        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = dataStore
        cfg.preferences.javaScriptCanOpenWindowsAutomatically = false
        cfg.userContentController.addUserScript(
            WKUserScript(source: bridgeScript(state, handler: Self.handlerName), injectionTime: .atDocumentStart,
                         forMainFrameOnly: true))
        #if os(iOS)
        cfg.allowsInlineMediaPlayback = true
        cfg.dataDetectorTypes = []
        #endif
        webView = WKWebView(frame: .zero, configuration: cfg)
        super.init()
        cfg.userContentController.add(WeakHandler(self), name: Self.handlerName)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        #if os(iOS)
        webView.allowsLinkPreview = false
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        #else
        webView.allowsLinkPreview = false
        webView.allowsBackForwardNavigationGestures = false
        #endif
        runJS = { [weak self] js in self?.webView.evaluateJavaScript(js, completionHandler: nil) }
    }

    func load() {
        webView.load(URLRequest(url: page))
    }

    /// Loads the page again after a failure.
    func retry() {
        gate = NavigationGate(page: page)
        load()
    }

    // MARK: messages

    func accept(isMainFrame: Bool, scheme: String, host h: String, port: Int) -> Bool {
        isMainFrame && host.matches(scheme: scheme, host: h, port: port)
    }

    func receive(_ body: Any, isMainFrame: Bool, scheme: String, host h: String, port: Int) {
        guard accept(isMainFrame: isMainFrame, scheme: scheme, host: h, port: port) else {
            log.notice("ignored a message from another frame or origin")
            return
        }
        guard let m = parsePageMessage(body, host: host) else {
            let type = ((body as? [String: Any])?["type"] as? String).map { String($0.prefix(32)) } ?? "?"
            log.notice("ignored an invalid page message: \(type, privacy: .public)")
            return
        }
        handle(m)
    }

    func handle(_ m: PageMessage) {
        switch m {
        case .ready:
            break
        case .open(let url):
            opener.open(url)
        case .auth(let url):
            signIn.start(url) { [weak self] in
                self?.runJS("window.dispatchEvent(new CustomEvent('antnexo:native',{detail:{type:'auth_closed'}}))")
            }
        case .seen(_, let raw):
            seenStore.set(raw, workspace: workspace)
        case .unread(let n):
            onEvent(.unread(count: n))
        case .session(let signedIn):
            if signedIn { signIn.finish() }
            onEvent(.signedIn(signedIn))
        case .identifyFailed(let code):
            onEvent(.identifyFailed(code: code))
        case .posted(let id):
            onEvent(.posted(id: id))
        }
    }

    // MARK: navigation (§3a: only the first load of the page; everything else to the browser)

    /// link: the person activated a link (a drag, a long-press preview): it goes to the browser. A refused main-frame
    /// navigation before the page finished loading (a redirect of the page itself) is a failed load.
    func policy(for url: URL, mainFrame: Bool, link: Bool = false) -> WKNavigationActionPolicy {
        if gate.allow(url, mainFrame: mainFrame) {
            finished = false
            return .allow
        }
        if link, let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" {
            opener.open(url)
        } else if mainFrame && !finished {
            onLoadFailed?()
        }
        return .cancel
    }

    func openNewWindow(_ url: URL) {
        if let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" { opener.open(url) }
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { return decisionHandler(.cancel) }
        decisionHandler(policy(for: url, mainFrame: action.targetFrame?.isMainFrame ?? false,
                               link: action.navigationType == .linkActivated))
    }

    func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse,
                 decisionHandler: @escaping @MainActor (WKNavigationResponsePolicy) -> Void) {
        if response.isForMainFrame, let http = response.response as? HTTPURLResponse, http.statusCode >= 400 {
            decisionHandler(.cancel)
            onLoadFailed?()
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finished = true
        onLoaded?()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if !isCancel(error) { onLoadFailed?() }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if !isCancel(error) { onLoadFailed?() }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { onLoadFailed?() }

    private func isCancel(_ error: Error) -> Bool {
        let e = error as NSError
        // our own .cancel of a later navigation (a link handed to the browser) isn't a failure of the page
        return (e.domain == NSURLErrorDomain && e.code == NSURLErrorCancelled)
            || (e.domain == "WebKitErrorDomain" && e.code == 102)
    }

    // MARK: windows

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = action.request.url { openNewWindow(url) }
        return nil
    }

    // JS dialogs: the widget uses none; refuse quietly rather than leave the page waiting.
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor () -> Void) {
        completionHandler()
    }
}
#endif
