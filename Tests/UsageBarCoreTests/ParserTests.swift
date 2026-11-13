import Foundation
import Testing
@testable import UsageBarCore

private func fixture(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

@Suite struct ClaudeUsageParserTests {
    @Test func parsesTopLevelWindows() throws {
        let metrics = try ClaudeUsageParser.parse(fixture("claude_toplevel"))
        let session = try #require(metrics.first { $0.kind == .session })
        #expect(session.percent == 23)
        let reset = try #require(session.resetsAt)
        #expect(abs(reset.timeIntervalSince1970 - 1_793_804_400.5) < 0.01)
        let weekly = try #require(metrics.first { $0.kind == .weekly })
        #expect(weekly.percent == 18.5)
        let sonnet = try #require(metrics.first { $0.kind == .scoped("Sonnet") })
        #expect(sonnet.percent == 4)
        // seven_day_opus is null, so it is skipped.
        #expect(!metrics.contains { $0.kind == .scoped("Opus") })
    }

    @Test func limitsRowsOverrideTopLevelAndIncludeFable() throws {
        let metrics = try ClaudeUsageParser.parse(fixture("claude_limits"))
        #expect(metrics.first { $0.kind == .session }?.percent == 25)
        #expect(metrics.first { $0.kind == .weekly }?.percent == 18)
        let fable = try #require(metrics.first { $0.kind.isFable })
        #expect(fable.percent == 9)
        #expect(fable.title == "Weekly (Fable)")
        #expect(metrics.contains { $0.kind == .scoped("Cowork") })
        #expect(metrics.count == 4) // unknown kind is ignored
        #expect(metrics.map(\.kind).prefix(2) == [.session, .weekly])
    }

    @Test func rejectsNonObject() {
        #expect(throws: UsageError.unknownResponse) {
            try ClaudeUsageParser.parse(Data("[1,2]".utf8))
        }
    }
}

@Suite struct CodexUsageParserTests {
    let now = Date(timeIntervalSince1970: 1_793_790_000)

    @Test func parsesBothWindows() throws {
        let result = try CodexUsageParser.parse(fixture("codex_both"), now: now)
        #expect(result.plan == "plus")
        let session = try #require(result.metrics.first { $0.kind == .session })
        #expect(session.percent == 41)
        #expect(session.resetsAt == Date(timeIntervalSince1970: 1_793_800_000))
        let weekly = try #require(result.metrics.first { $0.kind == .weekly })
        #expect(weekly.percent == 30)
    }

    @Test func classifiesWeeklyOnlyPrimaryByLength() throws {
        let result = try CodexUsageParser.parse(fixture("codex_weekly_only"), now: now)
        #expect(result.metrics.count == 1)
        let weekly = try #require(result.metrics.first)
        #expect(weekly.kind == .weekly)
        #expect(weekly.percent == 12.5)
        #expect(weekly.resetsAt == now.addingTimeInterval(7200))
    }

    @Test func handlesMissingRateLimit() throws {
        let result = try CodexUsageParser.parse(fixture("codex_no_limits"), now: now)
        #expect(result.plan == "free")
        #expect(result.metrics.isEmpty)
    }
}
