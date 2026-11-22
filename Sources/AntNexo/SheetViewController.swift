#if canImport(WebKit)
import Foundation
import WebKit
import AntNexoCore
#if canImport(UIKit)
import UIKit
typealias PlatformViewController = UIViewController
#else
import AppKit
typealias PlatformViewController = NSViewController
#endif

/// The sheet: the WebView full-size, a Done button, and a native retry view when the page can't load.
@MainActor
final class SheetViewController: PlatformViewController {
    let feedback: FeedbackController
    private let onClose: () -> Void
    private var closed = false
    private var failure: PlatformView?

    init(feedback: FeedbackController, onClose: @escaping () -> Void) {
        self.feedback = feedback
        self.onClose = onClose
        super.init(nibName: nil, bundle: nil)
        feedback.onLoadFailed = { [weak self] in self?.showFailure() }
        feedback.onLoaded = { [weak self] in self?.hideFailure() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// A sheet that never appeared: stops the page without reporting a close.
    func discard() {
        guard !closed else { return }
        closed = true
        feedback.tearDown()
    }

    /// Called once, however the sheet went away (Done, a swipe down, the window closing).
    func didClose() {
        guard !closed else { return }
        closed = true
        // the page stops here: no polls, no messages to the app after .closed
        feedback.tearDown()
        onClose()
    }

    @objc func done() {
        #if canImport(UIKit)
        let sheet = navigationController ?? self
        // still sliding in: UIKit ignores a dismiss during the presentation, so close when it ends
        if sheet.isBeingPresented, let t = sheet.transitionCoordinator {
            t.animate(alongsideTransition: nil) { [weak self] _ in self?.done() }
            return
        }
        // from the presenter: closes whatever is on top of the sheet too (a link in Safari), not only that
        guard let presenter = sheet.presentingViewController else { return didClose() }
        presenter.dismiss(animated: true) { [weak self] in self?.didClose() }
        #else
        if let w = view.window, let parent = w.sheetParent { parent.endSheet(w) } else { view.window?.close() }
        didClose()
        #endif
    }

    @objc func retry() {
        hideFailure()
        feedback.retry()
    }

    #if canImport(UIKit)
    typealias PlatformView = UIView

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(done))
        let web = feedback.webView
        web.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(web)
        NSLayoutConstraint.activate([
            web.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            web.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            web.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            web.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        feedback.load()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        // dismissed itself, or went away with a controller under it the app dismissed (then nothing presents it)
        if isBeingDismissed || navigationController?.isBeingDismissed == true
            || (navigationController ?? self).presentingViewController == nil { didClose() }
    }

    private func showFailure() {
        guard failure == nil else { return }
        let label = UILabel()
        label.text = "Couldn't load feedback."
        label.textColor = .secondaryLabel
        label.font = .preferredFont(forTextStyle: .body)
        let button = UIButton(type: .system)
        button.setTitle("Try again", for: .normal)
        button.addTarget(self, action: #selector(retry), for: .touchUpInside)
        let stack = UIStackView(arrangedSubviews: [label, button])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 12
        let box = UIView()
        box.backgroundColor = .systemBackground
        stack.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(stack)
        box.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(box)
        NSLayoutConstraint.activate([
            box.topAnchor.constraint(equalTo: view.topAnchor), box.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            box.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            box.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.centerXAnchor.constraint(equalTo: box.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: box.centerYAnchor),
        ])
        failure = box
    }
    #else
    typealias PlatformView = NSView

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 720))
        let web = feedback.webView
        let done = NSButton(title: "Done", target: self, action: #selector(done))
        done.keyEquivalent = "\u{1b}"
        done.bezelStyle = .rounded
        for v in [web, done] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(v)
        }
        NSLayoutConstraint.activate([
            web.topAnchor.constraint(equalTo: root.topAnchor),
            web.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            web.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            web.bottomAnchor.constraint(equalTo: done.topAnchor, constant: -10),
            done.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14),
            done.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -12),
        ])
        view = root
        feedback.load()
    }

    nonisolated(unsafe) private var closeObserver: NSObjectProtocol?

    /// The sheet ends with Done (Esc) or, as a window of its own, with its close button; being ordered out (a
    /// minimised parent, the app hidden) isn't a close.
    func watch(_ window: NSWindow) {
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.didClose() } }
    }

    deinit {
        if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
    }

    private func showFailure() {
        guard failure == nil else { return }
        let label = NSTextField(labelWithString: "Couldn't load feedback.")
        label.textColor = .secondaryLabelColor
        let button = NSButton(title: "Try again", target: self, action: #selector(retry))
        let stack = NSStackView(views: [label, button])
        stack.orientation = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        let web = feedback.webView
        web.isHidden = true
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: web.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: web.centerYAnchor),
        ])
        failure = stack
    }
    #endif

    private func hideFailure() {
        failure?.removeFromSuperview()
        failure = nil
        #if os(macOS)
        feedback.webView.isHidden = false
        #endif
    }
}
#endif
