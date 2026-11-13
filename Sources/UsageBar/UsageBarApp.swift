import SwiftUI

@main
struct UsageBarApp: App {
    @State private var store = UsageStore()

    var body: some Scene {
        MenuBarExtra {
            PopoverView(store: store)
        } label: {
            if let columns = store.menuBarColumns {
                Image(nsImage: MenuBarImage.make(columns: columns))
                    .accessibilityLabel(store.menuBarAccessibilityText ?? "")
            } else {
                Image(systemName: "gauge.with.dots.needle.50percent")
            }
        }
        .menuBarExtraStyle(.window)
    }
}
