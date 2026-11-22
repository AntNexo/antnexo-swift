#if canImport(WebKit)
import Foundation
import AuthenticationServices
import AntNexoCore
#if canImport(UIKit)
import UIKit
import SafariServices
#else
import AppKit
#endif

/// Provider sign-in in the system's sheet (Google refuses embedded WebViews). The page never talks to it: it polls
/// until the person pressed Continue there, then says it is signed in and the sheet is closed (spec §4).
@MainActor
final class SystemSignIn: NSObject, SignInPresenter, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?
    /// The window the sheet is shown over.
    var anchor: () -> ASPresentationAnchor?

    init(anchor: @escaping () -> ASPresentationAnchor?) {
        self.anchor = anchor
    }

    func start(_ url: URL, onClosed: @escaping () -> Void) {
        finish()
        weak var current: ASWebAuthenticationSession?  // weak: the session holds this closure
        let s = ASWebAuthenticationSession(url: url, callbackURLScheme: nil) { [weak self] _, _ in
            Task { @MainActor in
                // finish() drops the session first: closing it ourselves isn't the person closing it
                guard let self, let current, self.session === current else { return }
                self.session = nil
                onClosed()
            }
        }
        current = s
        s.prefersEphemeralWebBrowserSession = true
        s.presentationContextProvider = self
        session = s
        if !s.start() {
            log.error("the sign-in sheet didn't start")
            session = nil
            onClosed()
        }
    }

    func finish() {
        let s = session
        session = nil
        s?.cancel()
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated { anchor() ?? ASPresentationAnchor() }
    }
}

#if canImport(UIKit)
/// Links in Safari's view over the sheet.
@MainActor
final class SafariOpener: LinkOpener {
    weak var presenter: UIViewController?
    init(presenter: UIViewController?) { self.presenter = presenter }

    func open(_ url: URL) {
        guard let p = presenter, p.viewIfLoaded?.window != nil else {
            UIApplication.shared.open(url)
            return
        }
        let vc = SFSafariViewController(url: url)
        vc.dismissButtonStyle = .done
        p.present(vc, animated: true)
    }
}
#else
/// Links in the default browser.
@MainActor
final class BrowserOpener: LinkOpener {
    func open(_ url: URL) { NSWorkspace.shared.open(url) }
}
#endif
#endif
