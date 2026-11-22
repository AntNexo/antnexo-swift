import SwiftUI
import AntNexo

struct ContentView: View {
    @State private var showFeedback = false
    @State private var showRoadmap = false
    @State private var unread = 0
    @State private var token = ""
    @State private var events: [String] = []

    var body: some View {
        NavigationView {
            Form {
                Section {
                    Button("Send feedback") { showFeedback = true }
                    Button("Roadmap") { showRoadmap = true }
                    Button("Feedback with a screenshot") { Task { await AntNexo.show(screenshot: true) } }
                    Button {
                        Task { await AntNexo.show(tab: .changelog) }
                    } label: {
                        HStack {
                            Text("What's new")
                            Spacer()
                            if unread > 0 {
                                Text("\(unread)").font(.caption.bold()).foregroundColor(.white)
                                    .padding(.horizontal, 7).padding(.vertical, 2)
                                    .background(Capsule().fill(Color.red))
                            }
                        }
                    }
                }
                Section {
                    TextField("Identify token (from your backend)", text: $token)
                        .disableAutocorrection(true)
                    Button("Use this token") {
                        let t = token
                        AntNexo.identify(t.isEmpty ? nil : { @Sendable in t })
                    }
                    Button("Log out") { Task { await AntNexo.logout() } }
                } header: {
                    Text("Identify")
                } footer: {
                    Text("A real app gets the token from its own backend, which signs it with the workspace's identify secret.")
                }
                Section {
                    ForEach(Array(events.enumerated()), id: \.offset) { Text($0.element).font(.caption.monospaced()) }
                } header: {
                    Text("Events")
                }
            }
            .navigationTitle("AntNexo Sample")
        }
        .antnexoFeedback(isPresented: $showFeedback, tab: .new)
        .antnexoFeedback(isPresented: $showRoadmap, tab: .roadmap)
        .task {
            AntNexo.onEvent = { e in
                events.insert(String(describing: e), at: 0)
                #if DEBUG
                Scenario.log("event \(e)")
                #endif
                if case .unread(let n) = e { unread = n }
            }
            unread = (try? await AntNexo.unreadCount()) ?? 0
            #if DEBUG
            await Scenario.runIfAsked()
            #endif
        }
    }
}
