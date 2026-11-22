#if canImport(WebKit) && canImport(SwiftUI)
import SwiftUI
import AntNexoCore

private struct FeedbackModifier: ViewModifier {
    @Binding var isPresented: Bool
    let tab: FeedbackTab?
    let screenshot: Bool
    /// The sheet this modifier opened (another modifier's sheet is left alone).
    @State private var opened = Opened()

    final class Opened {
        weak var sheet: SheetViewController?
    }

    func body(content: Content) -> some View {
        content
            .onAppear { if isPresented { show() } }
            .onChange(of: isPresented) { shown in
                if shown { show() } else { opened.sheet?.done() }
            }
    }

    private func show() {
        Task { @MainActor in
            opened.sheet = await AntNexo.present(from: nil, tab: tab, screenshot: screenshot) { isPresented = false }
        }
    }
}

extension View {
    /// Shows the AntNexo sheet while `isPresented` is true: setting it to false closes the sheet, and closing the
    /// sheet sets it back to false.
    public func antnexoFeedback(isPresented: Binding<Bool>, tab: FeedbackTab? = nil, screenshot: Bool = false) -> some View {
        modifier(FeedbackModifier(isPresented: isPresented, tab: tab, screenshot: screenshot))
    }
}
#endif
