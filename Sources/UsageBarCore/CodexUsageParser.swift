import Foundation

/// Parses `GET https://chatgpt.com/backend-api/wham/usage`.
///
/// `rate_limit.primary_window` / `secondary_window` each carry `used_percent`,
/// `limit_window_seconds` and `reset_at` (Unix seconds) or `reset_after_seconds`.
/// Either can be null, and some plans send only a weekly primary window, so a
/// window is classified by its length rather than its position.
public enum CodexUsageParser {
    public static let sessionMaxWindow: TimeInterval = 24 * 3600

    public static func parse(_ data: Data, now: Date = Date()) throws -> (plan: String?, metrics: [UsageMetric]) {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw UsageError.unknownResponse
        }
        let plan = root["plan_type"] as? String
        let rateLimit = root["rate_limit"] as? [String: Any]

        var metrics: [UsageMetric] = []
        let windows: [(key: String, fallback: MetricKind)] = [("primary_window", .session), ("secondary_window", .weekly)]
        for (key, fallback) in windows {
            guard let window = rateLimit?[key] as? [String: Any],
                  let percent = (window["used_percent"] as? NSNumber)?.doubleValue else { continue }

            var kind = fallback
            if let length = (window["limit_window_seconds"] as? NSNumber)?.doubleValue, length > 0 {
                kind = length <= sessionMaxWindow ? .session : .weekly
            }
            guard !metrics.contains(where: { $0.kind == kind }) else { continue }

            let resetsAt: Date?
            if let resetAt = (window["reset_at"] as? NSNumber)?.doubleValue {
                resetsAt = Date(timeIntervalSince1970: resetAt)
            } else if let after = (window["reset_after_seconds"] as? NSNumber)?.doubleValue {
                resetsAt = now.addingTimeInterval(after)
            } else {
                resetsAt = nil
            }
            let title = kind == .session ? "Session (5h)" : "Weekly"
            metrics.append(UsageMetric(kind: kind, title: title, percent: percent, resetsAt: resetsAt))
        }
        metrics.sort { $0.kind == .session && $1.kind != .session }
        return (plan, metrics)
    }
}
