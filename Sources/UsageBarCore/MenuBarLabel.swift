import Foundation

/// A value the user can choose to show in the menu bar.
public enum MenuBarItem: String, CaseIterable, Sendable, Identifiable {
    case claudeSession
    case claudeWeekly
    case claudeFable
    case codexSession
    case codexWeekly

    public static let defaults: [MenuBarItem] = [.claudeSession, .codexSession]

    public var id: String { rawValue }

    public var provider: Provider {
        switch self {
        case .claudeSession, .claudeWeekly, .claudeFable: .claude
        case .codexSession, .codexWeekly: .codex
        }
    }

    public var title: String {
        switch self {
        case .claudeSession: "Claude session"
        case .claudeWeekly: "Claude weekly"
        case .claudeFable: "Claude Fable weekly"
        case .codexSession: "Codex session"
        case .codexWeekly: "Codex weekly"
        }
    }

    func metric(in snapshot: UsageSnapshot?) -> UsageMetric? {
        guard let snapshot else { return nil }
        switch self {
        case .claudeSession, .codexSession: return snapshot.metric(.session)
        case .claudeWeekly, .codexWeekly: return snapshot.metric(.weekly)
        case .claudeFable: return snapshot.fable
        }
    }

    public static func encode(_ items: [MenuBarItem]) -> String {
        items.map(\.rawValue).joined(separator: ",")
    }

    public static func decode(_ string: String) -> [MenuBarItem] {
        string.split(separator: ",").compactMap { MenuBarItem(rawValue: String($0)) }
    }
}

public enum MenuBarLabel {
    /// Order in which selected items are stacked, two per column. Kept separate
    /// from `allCases` (the settings order) so weekly and Fable always share a
    /// column, as do the two session values.
    static let stackingOrder: [MenuBarItem] = [.claudeWeekly, .claudeFable, .claudeSession, .codexSession, .codexWeekly]

    /// Columns of small stacked values for the menu bar: each column is
    /// `[top, bottom]`, or a single value for a leftover item. Values are rounded
    /// percents such as "23%", or "–" when the metric is missing. The order and
    /// duplicates of `items` are ignored; `stackingOrder` decides placement.
    /// Returns nil when nothing is selected, which means "show the icon only".
    public static func columns(items: [MenuBarItem], snapshots: [Provider: UsageSnapshot]) -> [[String]]? {
        let values = entries(items: items, snapshots: snapshots).map { $0.percent ?? "–" }
        guard !values.isEmpty else { return nil }
        return stride(from: 0, to: values.count, by: 2).map { Array(values[$0..<min($0 + 2, values.count)]) }
    }

    /// Spoken description of the same values in the same order, e.g.
    /// "Claude weekly 18%, Claude Fable weekly 9%". Missing metrics read as
    /// "no data". Returns nil when nothing is selected.
    public static func accessibilityText(items: [MenuBarItem], snapshots: [Provider: UsageSnapshot]) -> String? {
        let parts = entries(items: items, snapshots: snapshots).map { "\($0.item.title) \($0.percent ?? "no data")" }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    /// Selected items in stacking order with their formatted percent (nil if missing).
    private static func entries(items: [MenuBarItem], snapshots: [Provider: UsageSnapshot]) -> [(item: MenuBarItem, percent: String?)] {
        stackingOrder.filter(items.contains).map { item in
            (item, item.metric(in: snapshots[item.provider]).map { "\(Int($0.percent.rounded()))%" })
        }
    }
}

public enum ResetText {
    public static func string(for date: Date?, now: Date = Date(), timeZone: TimeZone = .current) -> String? {
        guard let date else { return nil }
        let seconds = date.timeIntervalSince(now)
        if seconds <= 0 { return "resetting…" }
        let minutes = Int((seconds / 60).rounded(.up))
        if minutes < 60 { return "resets in \(minutes)m" }
        if seconds < 24 * 3600 {
            let totalMinutes = Int(seconds / 60)
            return "resets in \(totalMinutes / 60)h \(totalMinutes % 60)m"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "EEE HH:mm"
        return "resets \(formatter.string(from: date))"
    }
}
