import SwiftUI
import AntNexo

struct ContentView: View {
    @EnvironmentObject private var model: SampleModel
    @State private var showFeedback = false
    @State private var showRoadmap = false
    @State private var token = ""

    var body: some View {
        NavigationView {
            Form {
                if let error = model.configError {
                    Section { Text(error).foregroundColor(.red) }
                }
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
                            if model.unread > 0 {
                                Text("\(model.unread)").font(.caption.bold()).foregroundColor(.white)
                                    .padding(.horizontal, 7).padding(.vertical, 2)
                                    .background(Capsule().fill(Color.red))
                            }
                        }
                    }
                }
                .disabled(model.configError != nil)
                Section {
                    TextField("Identify token (from your backend)", text: $token)
                        .disableAutocorrection(true)
                    Button("Use this token") {
                        let t = token
                        AntNexo.identify(t.isEmpty ? nil : { @Sendable in t })
                    }
                    Button("Log out") {
                        // an account switch: stop handing out the old person's token, then clear the sheet's session
                        token = ""
                        AntNexo.identify(nil)
                        Task { await AntNexo.logout() }
                    }
                } header: {
                    Text("Identify")
                } footer: {
                    Text("A real app gets the token from its own backend, which signs it with the workspace's identify secret.")
                }
                .disabled(model.configError != nil)
                Section {
                    ForEach(Array(model.events.enumerated()), id: \.offset) { Text($0.element).font(.caption.monospaced()) }
                } header: {
                    Text("Events")
                }
            }
            .navigationTitle("AntNexo Sample")
        }
        .antnexoFeedback(isPresented: $showFeedback, tab: .new)
        .antnexoFeedback(isPresented: $showRoadmap, tab: .roadmap)
        .task { await model.start() }
    }
}
