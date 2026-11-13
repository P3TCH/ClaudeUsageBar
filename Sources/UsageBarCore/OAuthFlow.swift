import Foundation

/// Browser sign-in with PKCE and a loopback redirect.
enum OAuthFlow {
    struct Grant {
        let code: String
        let redirectURI: String
        let pkce: PKCE
    }

    /// - Parameters:
    ///   - port: 0 picks a free port.
    ///   - authorizeURL: builds the authorize URL from the redirect URI and PKCE values.
    ///   - open: opens the URL in the browser.
    static func run(
        port: UInt16,
        callbackPath: String,
        authorizeURL: (_ redirectURI: String, _ pkce: PKCE) -> URL,
        open: @Sendable (URL) -> Void
    ) async throws -> Grant {
        let pkce = PKCE()
        let server = try LoopbackServer(port: port, callbackPath: callbackPath)
        defer { server.stop() }

        let boundPort = try await server.start()
        let redirectURI = "http://localhost:\(boundPort)\(callbackPath)"
        open(authorizeURL(redirectURI, pkce))

        let params = try await server.waitForCallback(timeout: .seconds(300))
        if let error = params["error"] {
            throw UsageError.signInDenied(params["error_description"] ?? error)
        }
        guard params["state"] == pkce.state else { throw UsageError.stateMismatch }
        // Claude can append "#state" to the code; only the part before it is the code.
        guard let rawCode = params["code"], let code = rawCode.split(separator: "#").first.map(String.init), !code.isEmpty else {
            throw UsageError.signInDenied("no authorization code")
        }
        return Grant(code: code, redirectURI: redirectURI, pkce: pkce)
    }

    static func url(_ base: String, _ query: [(String, String)]) -> URL {
        var components = URLComponents(string: base)!
        components.queryItems = query.map { URLQueryItem(name: $0.0, value: $0.1) }
        // URLComponents leaves "+" unescaped, which servers read as a space.
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return components.url!
    }
}
