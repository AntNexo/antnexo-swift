import SwiftUI
import AntNexo

/// The sample's state, shared by all its windows: AntNexo's events go to one place.
@MainActor
final class SampleModel: ObservableObject {
    /// Why the SDK isn't configured, if it isn't.
    @Published var configError: String?
    @Published var unread = 0
    @Published var events: [String] = []
    /// Bumped by every .unread event: a slower badge fetch that started earlier mustn't overwrite it.
    private var unreadVersion = 0
    private var started = false

    init() {
        // Your board: pass `-host https://<slug>.antnexo.com -workspace <slug>` as launch arguments
        // (Edit Scheme → Run → Arguments). There is no default, so the sample never posts to someone else's board.
        let d = UserDefaults.standard
        guard let host = d.string(forKey: "host").flatMap(URL.init(string:)), let workspace = d.string(forKey: "workspace") else {
            configError = "Set -host https://<slug>.antnexo.com and -workspace <slug> in the scheme's launch arguments."
            return
        }
        do {
            try AntNexo.configure(host: host, workspace: workspace)
        } catch {
            configError = "AntNexo.configure failed: \(error)"
        }
    }

    /// Once per app, whichever window appears first.
    func start() async {
        guard !started, configError == nil else { return }
        started = true
        AntNexo.onEvent = { [weak self] e in
            guard let self else { return }
            events.insert(String(describing: e), at: 0)
            #if DEBUG
            Scenario.log("event \(e)")
            #endif
            if case .unread(let n) = e {
                unreadVersion += 1
                unread = n
            }
        }
        let version = unreadVersion
        if let n = try? await AntNexo.unreadCount(), version == unreadVersion { unread = n }
        #if DEBUG
        await Scenario.runIfAsked()
        #endif
    }
}

@main
struct SampleApp: App {
    @StateObject private var model = SampleModel()

    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(model)
        }
    }
}
