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

    /// Called once, however the sheet went away (Done, a swipe down, the window closing).
    func didClose() {
        guard !closed else { return }
        closed = true
        onClose()
    }

    @objc func done() {
        #if canImport(UIKit)
        (navigationController ?? self).dismiss(animated: true) { [weak self] in self?.didClose() }
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
        if isBeingDismissed || navigationController?.isBeingDismissed == true { didClose() }
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

    override func viewDidDisappear() {
        super.viewDidDisappear()
        didClose()
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
