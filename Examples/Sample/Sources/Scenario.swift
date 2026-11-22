#if DEBUG
import Foundation
@_spi(Testing) import AntNexo

/// Scripted checks for the simulator: `-scenario <name>` opens the sheet and steps through the page, logging to
/// Documents/scenario.log. Not something an app needs.
@MainActor
enum Scenario {
    static let file: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("scenario.log")

    static func log(_ s: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(s)\n"
        if let h = try? FileHandle(forWritingTo: file) {
            h.seekToEndOfFile()
            h.write(Data(line.utf8))
            try? h.close()
        } else {
            try? line.write(to: file, atomically: true, encoding: .utf8)
        }
    }

    static func js(_ code: String) async -> String {
        do {
            let v = try await AntNexo.evaluateInSheet(code)
            return v.map { "\($0)" } ?? "nil"
        } catch {
            return "error: \(error)"
        }
    }

    static func wait(_ s: Double) async { try? await Task.sleep(nanoseconds: UInt64(s * 1e9)) }

    /// The widget's shadow root.
    static let root = "document.querySelector('[data-antnexo-root],antnexo-widget,div')?.shadowRoot ?? [...document.querySelectorAll('*')].find(e => e.shadowRoot)?.shadowRoot"

    static func runIfAsked() async {
        guard let name = UserDefaults.standard.string(forKey: "scenario") else { return }
        try? FileManager.default.removeItem(at: file)
        log("scenario \(name)")
        if let t = UserDefaults.standard.string(forKey: "token") { AntNexo.identify { @Sendable in t } }
        let tab: FeedbackTab? = UserDefaults.standard.string(forKey: "tab").flatMap(FeedbackTab.init(rawValue:))
        Task { await AntNexo.show(tab: tab, screenshot: name == "screenshot") }
        await wait(UserDefaults.standard.double(forKey: "wait") > 0 ? UserDefaults.standard.double(forKey: "wait") : 12)
        log("location " + (await js("location.href")))
        log("bridge " + (await js("JSON.stringify({v: AntNexoApp.v, platform: AntNexoApp.platform, sdk: AntNexoApp.sdk, context: AntNexoApp.context, identify: !!AntNexoApp.identify, seen: AntNexoApp.seen, screenshot: !!AntNexoApp.screenshot})")))
        log("text " + (await js("(\(root))?.textContent?.slice(0, 400)")))
        // custom steps: -js1 "<code>" -js2 "<code>" … run in order, 3 s apart
        for i in 1...9 {
            guard let code = UserDefaults.standard.string(forKey: "js\(i)") else { break }
            log("js\(i) " + (await js(code)))
            await wait(3)
        }
        if UserDefaults.standard.bool(forKey: "close") {
            AntNexo.closeSheet()
            await wait(2)
            log("reopen")
            Task { await AntNexo.show(tab: .roadmap) }
            await wait(8)
            log("location " + (await js("location.href")))
        }
        log("done")
    }
}
#endif
