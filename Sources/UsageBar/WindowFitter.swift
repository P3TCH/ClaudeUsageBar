import AppKit
import SwiftUI

/// MenuBarExtra's `.window` style grows its window when the content grows but
/// never shrinks it, which leaves empty space after a section collapses.
/// This measures the content and resizes the hosting window to match,
/// keeping the top edge (just under the menu bar) in place.
extension View {
    func fitWindowToContent() -> some View {
        modifier(FitWindowToContent())
    }
}

private struct FitWindowToContent: ViewModifier {
    @State private var height: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .background(GeometryReader { proxy in
                Color.clear
                    .onAppear { height = proxy.size.height }
                    .onChange(of: proxy.size.height) { _, newValue in height = newValue }
            })
            .background(WindowResizer(contentHeight: height))
    }
}

private struct WindowResizer: NSViewRepresentable {
    let contentHeight: CGFloat

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        let target = contentHeight
        guard target > 0 else { return }
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            let current = window.contentRect(forFrameRect: window.frame).height
            guard abs(current - target) > 0.5 else { return }
            var frame = window.frame
            let delta = target - current
            frame.origin.y -= delta // window origin is bottom-left; keep the top fixed
            frame.size.height += delta
            window.setFrame(frame, display: true)
        }
    }
}
