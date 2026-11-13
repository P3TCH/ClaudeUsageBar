import Foundation

/// Claude (claude.ai subscription) OAuth and usage, using the same public
/// client and endpoints as Claude Code.
public struct ClaudeService: UsageService {
    static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    static let authorizeURL = "https://claude.com/cai/oauth/authorize"
    static let tokenURL = URL(string: "https://platform.claude.com/v1/oauth/token")!
    static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    static let scopes = "user:profile user:inference"

    public let provider = Provider.claude

    public init() {}

    public func signIn(open: @escaping @Sendable (URL) -> Void) async throws -> StoredToken {
        let grant = try await OAuthFlow.run(port: 0, callbackPath: "/callback", authorizeURL: { redirectURI, pkce in
            OAuthFlow.url(Self.authorizeURL, [
                ("code", "true"),
                ("client_id", Self.clientID),
                ("response_type", "code"),
                ("redirect_uri", redirectURI),
                ("scope", Self.scopes),
                ("code_challenge", pkce.challenge),
                ("code_challenge_method", "S256"),
                ("state", pkce.state),
            ])
        }, open: open)

        let request = HTTP.postJSON(Self.tokenURL, [
            "grant_type": "authorization_code",
            "code": grant.code,
            "redirect_uri": grant.redirectURI,
            "client_id": Self.clientID,
            "code_verifier": grant.pkce.verifier,
            "state": grant.pkce.state,
        ])
        return try await token(from: request, previous: nil)
    }

    public func refresh(_ token: StoredToken) async throws -> StoredToken {
        let request = HTTP.postJSON(Self.tokenURL, [
            "grant_type": "refresh_token",
            "refresh_token": token.refreshToken,
            "client_id": Self.clientID,
        ])
        return try await self.token(from: request, previous: token)
    }

    public func fetchUsage(_ token: StoredToken) async throws -> UsageSnapshot {
        var request = URLRequest(url: Self.usageURL)
        request.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("UsageBar/1.0", forHTTPHeaderField: "User-Agent")
        let data = try await HTTP.data(for: request)
        return UsageSnapshot(provider: .claude, plan: nil, metrics: try ClaudeUsageParser.parse(data), fetchedAt: Date())
    }

    private func token(from request: URLRequest, previous: StoredToken?) async throws -> StoredToken {
        let json = try HTTP.json(try await HTTP.data(for: request, isTokenRequest: true))
        guard let access = json["access_token"] as? String else { throw UsageError.unknownResponse }
        let expiresIn = (json["expires_in"] as? NSNumber)?.doubleValue
        let email = (json["account"] as? [String: Any])?["email_address"] as? String
        return StoredToken(
            accessToken: access,
            refreshToken: json["refresh_token"] as? String ?? previous?.refreshToken ?? "",
            expiresAt: expiresIn.map { Date().addingTimeInterval($0) },
            accountId: nil,
            email: email ?? previous?.email
        )
    }
}
