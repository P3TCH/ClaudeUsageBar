import Foundation

/// Sign-in, token refresh and usage fetching for one provider.
public protocol UsageService: Sendable {
    var provider: Provider { get }
    func signIn(open: @escaping @Sendable (URL) -> Void) async throws -> StoredToken
    func refresh(_ token: StoredToken) async throws -> StoredToken
    func fetchUsage(_ token: StoredToken) async throws -> UsageSnapshot
}
