import Foundation

/// Codex (ChatGPT plan) OAuth and usage, using the same public client and
/// endpoints as the Codex CLI.
public struct CodexService: UsageService {
    static let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"
    static let authorizeURL = "https://auth.openai.com/oauth/authorize"
    static let tokenURL = URL(string: "https://auth.openai.com/oauth/token")!
    static let usageURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
    /// OpenAI only accepts this exact redirect port for the Codex client.
    static let callbackPort: UInt16 = 1455

    public let provider = Provider.codex

    public init() {}

    public func signIn(open: @escaping @Sendable (URL) -> Void) async throws -> StoredToken {
        let grant = try await OAuthFlow.run(port: Self.callbackPort, callbackPath: "/auth/callback", authorizeURL: { redirectURI, pkce in
            OAuthFlow.url(Self.authorizeURL, [
                ("response_type", "code"),
                ("client_id", Self.clientID),
                ("redirect_uri", redirectURI),
                ("scope", "openid profile email offline_access"),
                ("code_challenge", pkce.challenge),
                ("code_challenge_method", "S256"),
                ("id_token_add_organizations", "true"),
                ("codex_cli_simplified_flow", "true"),
                ("state", pkce.state),
                ("originator", "codex_cli_rs"),
            ])
        }, open: open)

        let request = HTTP.postForm(Self.tokenURL, [
            ("grant_type", "authorization_code"),
            ("code", grant.code),
            ("redirect_uri", grant.redirectURI),
            ("client_id", Self.clientID),
            ("code_verifier", grant.pkce.verifier),
        ])
        return try await token(from: request, previous: nil)
    }

    public func refresh(_ token: StoredToken) async throws -> StoredToken {
        let request = HTTP.postJSON(Self.tokenURL, [
            "client_id": Self.clientID,
            "grant_type": "refresh_token",
            "refresh_token": token.refreshToken,
            "scope": "openid profile email",
        ])
        return try await self.token(from: request, previous: token)
    }

    public func fetchUsage(_ token: StoredToken) async throws -> UsageSnapshot {
        var request = URLRequest(url: Self.usageURL)
        request.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "Authorization")
        if let accountId = token.accountId {
            request.setValue(accountId, forHTTPHeaderField: "ChatGPT-Account-Id")
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("codex_cli_rs", forHTTPHeaderField: "originator")
        request.setValue("UsageBar/1.0", forHTTPHeaderField: "User-Agent")
        let data = try await HTTP.data(for: request)
        let parsed = try CodexUsageParser.parse(data)
        return UsageSnapshot(provider: .codex, plan: parsed.plan, metrics: parsed.metrics, fetchedAt: Date())
    }

    private func token(from request: URLRequest, previous: StoredToken?) async throws -> StoredToken {
        let json = try HTTP.json(try await HTTP.data(for: request, isTokenRequest: true))
        guard let access = json["access_token"] as? String else { throw UsageError.unknownResponse }
        let claims = (json["id_token"] as? String).flatMap(JWT.payload) ?? [:]
        let auth = claims["https://api.openai.com/auth"] as? [String: Any]
        return StoredToken(
            accessToken: access,
            refreshToken: json["refresh_token"] as? String ?? previous?.refreshToken ?? "",
            expiresAt: JWT.expiry(access) ?? (json["expires_in"] as? NSNumber).map { Date().addingTimeInterval($0.doubleValue) },
            accountId: auth?["chatgpt_account_id"] as? String ?? previous?.accountId,
            email: claims["email"] as? String ?? previous?.email
        )
    }
}
