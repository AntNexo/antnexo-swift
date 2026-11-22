#if canImport(WebKit) && canImport(SwiftUI)
import SwiftUI
import AntNexoCore

private struct FeedbackModifier: ViewModifier {
    @Binding var isPresented: Bool
    let tab: FeedbackTab?
    let screenshot: Bool

    func body(content: Content) -> some View {
        content.onChange(of: isPresented) { shown in
            guard shown else { return }
            Task { @MainActor in
                await AntNexo.present(from: nil, tab: tab, screenshot: screenshot) { isPresented = false }
            }
        }
    }
}

extension View {
    /// Shows the AntNexo sheet while `isPresented` is true; sets it back to false when the sheet closes.
    public func antnexoFeedback(isPresented: Binding<Bool>, tab: FeedbackTab? = nil, screenshot: Bool = false) -> some View {
        modifier(FeedbackModifier(isPresented: isPresented, tab: tab, screenshot: screenshot))
    }
}
#endif
