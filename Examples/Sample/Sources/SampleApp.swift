import SwiftUI
import AntNexo

/// The board the sample opens: our test workspace by default; `-host` and `-workspace` launch arguments override it.
enum SampleConfig {
    static var host: URL {
        URL(string: UserDefaults.standard.string(forKey: "host") ?? "https://splynx.antnexo.com")!
    }
    static var workspace: String { UserDefaults.standard.string(forKey: "workspace") ?? "splynx" }
}

@main
struct SampleApp: App {
    init() {
        do {
            try AntNexo.configure(host: SampleConfig.host, workspace: SampleConfig.workspace)
        } catch {
            print("AntNexo.configure failed: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
