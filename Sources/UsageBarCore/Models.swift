import Foundation

public enum Provider: String, Codable, CaseIterable, Sendable, Identifiable {
    case claude
    case codex

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        }
    }

    /// Short glyph used in the menu bar label.
    public var glyph: String {
        switch self {
        case .claude: "✳"
        case .codex: "◎"
        }
    }
}

public enum MetricKind: Hashable, Sendable {
    case session
    case weekly
    /// A weekly limit for one model, e.g. "Fable" or "Sonnet".
    case scoped(String)

    public var isFable: Bool {
        if case .scoped(let name) = self { return name.localizedCaseInsensitiveContains("fable") }
        return false
    }
}

public struct UsageMetric: Hashable, Sendable, Identifiable {
    public var kind: MetricKind
    public var title: String
    /// Share of the window used, 0-100.
    public var percent: Double
    public var resetsAt: Date?

    public var id: String { title }

    public init(kind: MetricKind, title: String, percent: Double, resetsAt: Date?) {
        self.kind = kind
        self.title = title
        self.percent = percent
        self.resetsAt = resetsAt
    }
}

public struct UsageSnapshot: Sendable {
    public var provider: Provider
    public var plan: String?
    public var metrics: [UsageMetric]
    public var fetchedAt: Date

    public init(provider: Provider, plan: String?, metrics: [UsageMetric], fetchedAt: Date) {
        self.provider = provider
        self.plan = plan
        self.metrics = metrics
        self.fetchedAt = fetchedAt
    }

    public func metric(_ kind: MetricKind) -> UsageMetric? {
        metrics.first { $0.kind == kind }
    }

    public var fable: UsageMetric? {
        metrics.first { $0.kind.isFable }
    }
}

public struct StoredToken: Codable, Sendable, Equatable {
    public var accessToken: String
    public var refreshToken: String
    public var expiresAt: Date?
    /// Codex: ChatGPT account id sent as the `ChatGPT-Account-Id` header.
    public var accountId: String?
    public var email: String?

    public init(accessToken: String, refreshToken: String, expiresAt: Date?, accountId: String? = nil, email: String? = nil) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.accountId = accountId
        self.email = email
    }

    /// True when the token expires within `margin` seconds.
    public func isExpiring(within margin: TimeInterval = 60, now: Date = Date()) -> Bool {
        guard let expiresAt else { return false }
        return expiresAt.timeIntervalSince(now) < margin
    }
}

public enum UsageError: LocalizedError, Equatable {
    case unauthorized
    case rateLimited
    case http(Int)
    case unknownResponse
    case portInUse(UInt16)
    case stateMismatch
    case signInTimedOut
    case signInDenied(String)
    case network(String)

    public var errorDescription: String? {
        switch self {
        case .unauthorized: "Sign in again"
        case .rateLimited: "Rate limited, will retry"
        case .http(let code): "Server error (HTTP \(code))"
        case .unknownResponse: "Unknown response from server"
        case .portInUse(let port): "Port \(port) is busy. Close any running `codex login` and try again."
        case .stateMismatch: "Sign-in failed (state mismatch)"
        case .signInTimedOut: "Sign-in timed out"
        case .signInDenied(let reason): "Sign-in failed: \(reason)"
        case .network(let message): message
        }
    }
}
