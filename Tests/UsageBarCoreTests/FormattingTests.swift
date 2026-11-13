import Foundation
import Testing
@testable import UsageBarCore

@Suite struct MenuBarLabelTests {
    let snapshots: [Provider: UsageSnapshot] = [
        .claude: UsageSnapshot(provider: .claude, plan: nil, metrics: [
            UsageMetric(kind: .session, title: "Session", percent: 23.4, resetsAt: nil),
            UsageMetric(kind: .weekly, title: "Weekly", percent: 18, resetsAt: nil),
            UsageMetric(kind: .scoped("Fable"), title: "Weekly (Fable)", percent: 9, resetsAt: nil),
        ], fetchedAt: .now),
        .codex: UsageSnapshot(provider: .codex, plan: "plus", metrics: [
            UsageMetric(kind: .session, title: "Session", percent: 40.6, resetsAt: nil),
        ], fetchedAt: .now),
    ]

    @Test func defaultItemsShareOneColumn() {
        #expect(MenuBarLabel.columns(items: MenuBarItem.defaults, snapshots: snapshots) == [["23%", "41%"]])
    }

    @Test func weeklyAboveFable() {
        #expect(MenuBarLabel.columns(items: [.claudeWeekly, .claudeFable], snapshots: snapshots) == [["18%", "9%"]])
    }

    @Test func ignoresArgumentOrderAndLeavesSingleColumn() {
        let items: [MenuBarItem] = [.claudeSession, .claudeFable, .claudeWeekly]
        #expect(MenuBarLabel.columns(items: items, snapshots: snapshots) == [["18%", "9%"], ["23%"]])
    }

    @Test func allItemsWithDashWhenMissing() {
        #expect(MenuBarLabel.columns(items: MenuBarItem.allCases, snapshots: snapshots) == [["18%", "9%"], ["23%", "41%"], ["–"]])
    }

    @Test func emptySelectionMeansIconOnly() {
        #expect(MenuBarLabel.columns(items: [], snapshots: snapshots) == nil)
        #expect(MenuBarLabel.accessibilityText(items: [], snapshots: snapshots) == nil)
    }

    @Test func accessibilityText() {
        #expect(MenuBarLabel.accessibilityText(items: [.claudeFable, .claudeWeekly], snapshots: snapshots)
            == "Claude weekly 18%, Claude Fable weekly 9%")
        #expect(MenuBarLabel.accessibilityText(items: [.codexWeekly, .codexSession], snapshots: snapshots)
            == "Codex session 41%, Codex weekly no data")
    }

    @Test func storageRoundTrip() {
        let items: [MenuBarItem] = [.claudeWeekly, .codexSession]
        #expect(MenuBarItem.decode(MenuBarItem.encode(items)) == items)
        #expect(MenuBarItem.decode("") == [])
        #expect(MenuBarItem.decode("claudeSession,bogus") == [.claudeSession])
    }
}

@Suite struct ResetTextTests {
    let now = Date(timeIntervalSince1970: 1_793_790_000) // Wed 2026-11-04 11:00 UTC
    let utc = TimeZone(identifier: "UTC")!

    @Test func formats() {
        #expect(ResetText.string(for: nil, now: now, timeZone: utc) == nil)
        #expect(ResetText.string(for: now.addingTimeInterval(-5), now: now, timeZone: utc) == "resetting…")
        #expect(ResetText.string(for: now.addingTimeInterval(42 * 60), now: now, timeZone: utc) == "resets in 42m")
        #expect(ResetText.string(for: now.addingTimeInterval(3 * 3600 + 12 * 60), now: now, timeZone: utc) == "resets in 3h 12m")
        #expect(ResetText.string(for: now.addingTimeInterval(3 * 86400 + 11 * 3600), now: now, timeZone: utc) == "resets Sat 22:00")
    }
}

@Suite struct PKCEAndJWTTests {
    @Test func challengeIsSHA256Base64URL() {
        // Expected value computed independently: base64url(sha256(verifier)) without padding.
        let pkce = PKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r7wW1gFWFOEjXk", state: "s")
        #expect(pkce.challenge == "bwWFMyPfdG9qreDhH2lmftFx_dFeLDalzcT1gb_j68g")
    }

    @Test func randomValuesAreURLSafe() {
        let pkce = PKCE()
        #expect(pkce.verifier.count == 43)
        #expect(pkce.verifier.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
        #expect(pkce.state != pkce.verifier)
    }

    @Test func decodesPayload() {
        let payload = #"{"exp":1793790000,"email":"a@b.c"}"#
        let token = "x." + Data(payload.utf8).base64URLEncoded() + ".sig"
        #expect(JWT.payload(token)?["email"] as? String == "a@b.c")
        #expect(JWT.expiry(token) == Date(timeIntervalSince1970: 1_793_790_000))
        #expect(JWT.payload("garbage") == nil)
    }
}
