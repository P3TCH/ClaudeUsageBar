import Foundation
import Testing
@testable import UsageBarCore

/// Drives the real loopback server: `open` plays the browser and hits the
/// redirect URI the way the provider would after sign-in.
@Suite struct OAuthFlowTests {
    private func run(redirectQuery: @escaping @Sendable (_ state: String) -> String) async throws -> OAuthFlow.Grant {
        try await OAuthFlow.run(port: 0, callbackPath: "/callback", authorizeURL: { redirectURI, pkce in
            OAuthFlow.url("https://example.com/authorize", [("redirect_uri", redirectURI), ("state", pkce.state)])
        }, open: { url in
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let redirect = items.first { $0.name == "redirect_uri" }?.value ?? ""
            let state = items.first { $0.name == "state" }?.value ?? ""
            Task {
                _ = try? await URLSession.shared.data(from: URL(string: redirect + "/../favicon.ico")!)
                _ = try? await URLSession.shared.data(from: URL(string: redirect + "?" + redirectQuery(state))!)
            }
        })
    }

    @Test func returnsCodeAndStripsStateSuffix() async throws {
        let grant = try await run { state in "code=abc%23\(state)&state=\(state)" }
        #expect(grant.code == "abc")
        #expect(grant.redirectURI.hasPrefix("http://localhost:"))
        #expect(grant.redirectURI.hasSuffix("/callback"))
    }

    @Test func rejectsWrongState() async {
        await #expect(throws: UsageError.stateMismatch) {
            try await run { _ in "code=abc&state=forged" }
        }
    }

    @Test func reportsProviderError() async {
        await #expect(throws: UsageError.signInDenied("User denied")) {
            try await run { state in "error=access_denied&error_description=User%20denied&state=\(state)" }
        }
    }

    @Test func authorizeURLEncodesPlusAndSpaces() {
        let url = OAuthFlow.url("https://example.com/a", [("scope", "a b"), ("x", "1+2")])
        #expect(url.absoluteString == "https://example.com/a?scope=a%20b&x=1%2B2")
    }
}
