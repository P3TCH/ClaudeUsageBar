import AppKit
import Foundation
import Observation
import UsageBarCore

@MainActor
@Observable
final class UsageStore {
    struct ProviderState {
        var token: StoredToken?
        var snapshot: UsageSnapshot?
        var error: String?
        var isLoading = false
        var isSigningIn = false
    }

    static let pollInterval: Duration = .seconds(300)
    private static let itemsKey = "menuBarItems"

    private(set) var states: [Provider: ProviderState] = [:]

    var menuBarItems: [MenuBarItem] {
        didSet { UserDefaults.standard.set(MenuBarItem.encode(menuBarItems), forKey: Self.itemsKey) }
    }

    @ObservationIgnored private let services: [Provider: any UsageService] = [
        .claude: ClaudeService(),
        .codex: CodexService(),
    ]
    @ObservationIgnored private let keychain = KeychainStore()
    @ObservationIgnored private var signInTasks: [Provider: Task<Void, Never>] = [:]
    @ObservationIgnored private var pollTask: Task<Void, Never>?

    init() {
        if let saved = UserDefaults.standard.string(forKey: Self.itemsKey) {
            menuBarItems = MenuBarItem.decode(saved)
        } else {
            menuBarItems = MenuBarItem.defaults
        }
        for provider in Provider.allCases {
            states[provider] = ProviderState(token: keychain.load(provider))
        }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshAll()
                try? await Task.sleep(for: Self.pollInterval)
            }
        }
    }

    var menuBarColumns: [[String]]? {
        MenuBarLabel.columns(items: menuBarItems, snapshots: states.compactMapValues(\.snapshot))
    }

    var menuBarAccessibilityText: String? {
        MenuBarLabel.accessibilityText(items: menuBarItems, snapshots: states.compactMapValues(\.snapshot))
    }

    func state(_ provider: Provider) -> ProviderState {
        states[provider] ?? ProviderState()
    }

    func isShown(_ item: MenuBarItem) -> Bool { menuBarItems.contains(item) }

    func setShown(_ item: MenuBarItem, _ shown: Bool) {
        if shown, !menuBarItems.contains(item) {
            menuBarItems.append(item)
        } else if !shown {
            menuBarItems.removeAll { $0 == item }
        }
    }

    // MARK: Sign in / out

    func signIn(_ provider: Provider) {
        guard let service = services[provider], signInTasks[provider] == nil else { return }
        states[provider]?.isSigningIn = true
        states[provider]?.error = nil
        signInTasks[provider] = Task {
            defer {
                states[provider]?.isSigningIn = false
                signInTasks[provider] = nil
            }
            do {
                let token = try await service.signIn { url in
                    Task { @MainActor in NSWorkspace.shared.open(url) }
                }
                try keychain.save(token, for: provider)
                states[provider]?.token = token
                await refresh(provider)
            } catch is CancellationError {
                // User cancelled; nothing to report.
            } catch {
                states[provider]?.error = error.localizedDescription
            }
        }
    }

    func cancelSignIn(_ provider: Provider) {
        signInTasks[provider]?.cancel()
    }

    func signOut(_ provider: Provider) {
        keychain.delete(provider)
        states[provider] = ProviderState()
    }

    // MARK: Refresh

    func refreshAll() async {
        await withTaskGroup(of: Void.self) { group in
            for provider in Provider.allCases {
                group.addTask { await self.refresh(provider) }
            }
        }
    }

    /// Refreshes when the popover opens, unless the data is fresh.
    func refreshIfStale() {
        let stale = Provider.allCases.contains { provider in
            let state = state(provider)
            guard state.token != nil else { return false }
            guard let fetched = state.snapshot?.fetchedAt else { return true }
            return Date().timeIntervalSince(fetched) > 60
        }
        if stale { Task { await refreshAll() } }
    }

    func refresh(_ provider: Provider) async {
        guard let service = services[provider], var token = state(provider).token, !state(provider).isLoading else { return }
        states[provider]?.isLoading = true
        defer { states[provider]?.isLoading = false }

        do {
            if token.isExpiring() {
                token = try await renew(provider, token, service)
            }
            let snapshot: UsageSnapshot
            do {
                snapshot = try await service.fetchUsage(token)
            } catch UsageError.unauthorized {
                token = try await renew(provider, token, service)
                snapshot = try await service.fetchUsage(token)
            }
            states[provider]?.snapshot = snapshot
            states[provider]?.error = nil
        } catch UsageError.unauthorized {
            keychain.delete(provider)
            states[provider] = ProviderState(error: UsageError.unauthorized.localizedDescription)
        } catch {
            states[provider]?.error = error.localizedDescription
        }
    }

    private func renew(_ provider: Provider, _ token: StoredToken, _ service: any UsageService) async throws -> StoredToken {
        let renewed = try await service.refresh(token)
        try? keychain.save(renewed, for: provider)
        states[provider]?.token = renewed
        return renewed
    }
}
