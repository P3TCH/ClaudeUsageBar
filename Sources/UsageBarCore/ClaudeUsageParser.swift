import Foundation

/// Parses `GET https://api.anthropic.com/api/oauth/usage`.
///
/// The top-level `five_hour` / `seven_day` objects carry `utilization` (0-100)
/// and `resets_at`. Newer responses also send `limits[]` rows with `kind`
/// (`session`, `weekly_all`, `weekly_scoped`), `percent`, `resets_at` and a
/// `scope` naming the model or surface. The weekly Fable limit is the
/// `weekly_scoped` row for "Fable". Rows from `limits[]` win over top-level keys.
public enum ClaudeUsageParser {
    private static let legacyScopedKeys: [(key: String, name: String)] = [
        ("seven_day_sonnet", "Sonnet"),
        ("seven_day_opus", "Opus"),
    ]

    public static func parse(_ data: Data) throws -> [UsageMetric] {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw UsageError.unknownResponse
        }

        var metrics: [UsageMetric] = []
        func upsert(_ metric: UsageMetric) {
            if let index = metrics.firstIndex(where: { $0.kind == metric.kind }) {
                metrics[index] = metric
            } else {
                metrics.append(metric)
            }
        }

        if let window = root["five_hour"] as? [String: Any], let metric = window.metric(.session, percentKey: "utilization") {
            upsert(metric)
        }
        if let window = root["seven_day"] as? [String: Any], let metric = window.metric(.weekly, percentKey: "utilization") {
            upsert(metric)
        }
        for (key, name) in legacyScopedKeys {
            if let window = root[key] as? [String: Any], let metric = window.metric(.scoped(name), percentKey: "utilization") {
                upsert(metric)
            }
        }

        for row in root["limits"] as? [[String: Any]] ?? [] {
            guard let kind = kind(of: row), let metric = row.metric(kind, percentKey: "percent") else { continue }
            upsert(metric)
        }

        return metrics.sorted { rank($0.kind) < rank($1.kind) }
    }

    private static func kind(of row: [String: Any]) -> MetricKind? {
        switch row["kind"] as? String {
        case "session": return .session
        case "weekly_all": return .weekly
        case "weekly_scoped": return scopeName(row["scope"]).map(MetricKind.scoped)
        default: return nil
        }
    }

    /// `scope` looks like `{"model": {"display_name": "Fable"}}` or `{"surface": {...}}`.
    private static func scopeName(_ scope: Any?) -> String? {
        guard let scope = scope as? [String: Any] else { return nil }
        for key in ["model", "surface"] + scope.keys.sorted() {
            if let name = (scope[key] as? [String: Any])?["display_name"] as? String, !name.isEmpty {
                return name
            }
        }
        return nil
    }

    private static func rank(_ kind: MetricKind) -> Int {
        switch kind {
        case .session: 0
        case .weekly: 1
        case .scoped: 2 // stable sort keeps server order among scoped rows
        }
    }
}

private extension Dictionary where Key == String, Value == Any {
    func metric(_ kind: MetricKind, percentKey: String) -> UsageMetric? {
        guard let percent = (self[percentKey] as? NSNumber)?.doubleValue else { return nil }
        let resetsAt = (self["resets_at"] as? String).flatMap(ISO8601.parse)
        return UsageMetric(kind: kind, title: ClaudeUsageParser.title(for: kind), percent: percent, resetsAt: resetsAt)
    }
}

extension ClaudeUsageParser {
    static func title(for kind: MetricKind) -> String {
        switch kind {
        case .session: "Session (5h)"
        case .weekly: "Weekly (all models)"
        case .scoped(let name): "Weekly (\(name))"
        }
    }
}

enum ISO8601 {
    // ISO8601DateFormatter is thread-safe for parsing once configured.
    nonisolated(unsafe) private static let withFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    nonisolated(unsafe) private static let plain = ISO8601DateFormatter()

    static func parse(_ string: String) -> Date? {
        withFraction.date(from: string) ?? plain.date(from: string)
    }
}
