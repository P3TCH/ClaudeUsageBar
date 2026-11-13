import UsageBarCore
import SwiftUI

struct PopoverView: View {
    let store: UsageStore
    @State private var showSettings = false

    var body: some View {
        // Flat, system-panel layout: sections sit on the window background and
        // are separated by dividers. Every divider is followed by content, so
        // no two dividers are ever adjacent whether settings are shown or not.
        VStack(alignment: .leading, spacing: 10) {
            header
            ForEach(Provider.allCases) { provider in
                Divider()
                ProviderSection(provider: provider, store: store)
            }
            if showSettings {
                Divider()
                SettingsPanel(store: store)
            }
            Divider()
            HStack {
                Text("Updates every 5 minutes").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.borderless)
            }
        }
        .padding(14)
        .frame(width: 330)
        .fixedSize(horizontal: false, vertical: true)
        .fitWindowToContent()
        .onAppear { store.refreshIfStale() }
    }

    private var header: some View {
        HStack {
            Text("UsageBar").font(.headline)
            Spacer()
            Button {
                Task { await store.refreshAll() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh now")
            Button {
                showSettings.toggle()
            } label: {
                Image(systemName: showSettings ? "gearshape.fill" : "gearshape")
            }
            .buttonStyle(.borderless)
            .help("Choose what the menu bar shows")
        }
    }
}

private struct ProviderSection: View {
    let provider: Provider
    let store: UsageStore

    var body: some View {
        let state = store.state(provider)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(provider.glyph)
                Text(provider.displayName).font(.subheadline.weight(.semibold))
                if let plan = state.snapshot?.plan {
                    Text(plan.capitalized).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if state.isLoading { ProgressView().controlSize(.small) }
            }

            if state.token == nil {
                signInRow(state)
            } else {
                if let email = state.token?.email {
                    Text(email).font(.caption).foregroundStyle(.secondary)
                }
                if let snapshot = state.snapshot {
                    if snapshot.metrics.isEmpty {
                        Text("No limits reported for this plan").font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(snapshot.metrics) { MetricRow(metric: $0) }
                } else if !state.isLoading {
                    Text("No data yet").font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    if let fetched = state.snapshot?.fetchedAt {
                        Text("Updated \(fetched, style: .relative) ago").font(.caption2).foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Button("Sign out") { store.signOut(provider) }
                        .buttonStyle(.borderless)
                        .font(.caption)
                }
            }

            if let error = state.error {
                Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
        }
        // Fill the row so a signed-out section (just a small button) still
        // left-aligns with the header.
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func signInRow(_ state: UsageStore.ProviderState) -> some View {
        if state.isSigningIn {
            HStack {
                ProgressView().controlSize(.small)
                Text("Finish signing in in your browser…").font(.caption)
                Spacer()
                Button("Cancel") { store.cancelSignIn(provider) }.font(.caption)
            }
        } else {
            Button("Sign in with \(provider.displayName)") { store.signIn(provider) }
                .controlSize(.small)
        }
    }
}

private struct MetricRow: View {
    let metric: UsageMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(metric.title).font(.caption)
                Spacer()
                Text("\(Int(metric.percent.rounded()))%").font(.caption.monospacedDigit().weight(.semibold))
            }
            ProgressView(value: min(max(metric.percent, 0), 100), total: 100)
                .tint(color)
            if let reset = ResetText.string(for: metric.resetsAt) {
                Text(reset).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private var color: Color {
        switch metric.percent {
        case ..<70: .green
        case ..<90: .orange
        default: .red
        }
    }
}

private struct SettingsPanel: View {
    let store: UsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Show in menu bar").font(.subheadline.weight(.semibold))
            ForEach(MenuBarItem.allCases) { item in
                Toggle(item.title, isOn: Binding(
                    get: { store.isShown(item) },
                    set: { store.setShown(item, $0) }
                ))
                .toggleStyle(.checkbox)
                .font(.caption)
            }
            Text("Nothing selected shows the icon only.").font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
