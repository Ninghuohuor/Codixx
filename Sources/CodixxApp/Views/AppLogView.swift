import Foundation
import SwiftUI
import CodixxCore

enum AppLogCategory: String, CaseIterable, Identifiable, Equatable {
    case all
    case switching
    case account
    case quota
    case error
    case system

    var id: String { rawValue }
}

enum AppLogSeverity: Equatable {
    case normal
    case warning
    case error
}

struct AppLogTimestampFormatter {
    var calendar: Calendar = .current
    var timeZone: TimeZone = .current

    func string(for date: Date, now: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = calendar.isDate(date, inSameDayAs: now) ? "HH:mm:ss" : "MM/dd HH:mm"
        return formatter.string(from: date)
    }
}

struct AppLogEntry: Identifiable, Equatable {
    var id: String
    var timestamp: Date
    var category: AppLogCategory
    var title: String
    var detail: String?
    var status: String?
    var iconName: String
    var severity: AppLogSeverity

    static func entries(
        switchEvents: [SwitchAuditEvent],
        appEvents: [AppLogEvent],
        strings: CodixxStrings
    ) -> [AppLogEntry] {
        let switchEntries = switchEvents.map { entry(from: $0, strings: strings) }
        let activityEntries = appEvents.map { entry(from: $0, strings: strings) }
        return (switchEntries + activityEntries).sorted { $0.timestamp > $1.timestamp }
    }

    static func filtered(_ entries: [AppLogEntry], by category: AppLogCategory) -> [AppLogEntry] {
        switch category {
        case .all:
            return entries
        case .error:
            return entries.filter { $0.severity == .error }
        case .switching, .account, .quota, .system:
            return entries.filter { $0.category == category }
        }
    }

    private static func entry(from event: SwitchAuditEvent, strings: CodixxStrings) -> AppLogEntry {
        AppLogEntry(
            id: "switch-\(event.id.uuidString)",
            timestamp: event.timestamp,
            category: .switching,
            title: switchTitle(for: event, strings: strings),
            detail: switchDetail(for: event, strings: strings),
            status: strings.switchResultLabel(event.result),
            iconName: iconName(for: event.result),
            severity: severity(for: event.result)
        )
    }

    private static func entry(from event: AppLogEvent, strings: CodixxStrings) -> AppLogEntry {
        AppLogEntry(
            id: "app-\(event.id.uuidString)",
            timestamp: event.timestamp,
            category: category(for: event.kind),
            title: strings.appLogEventTitle(event.kind, accountAlias: event.accountAlias),
            detail: detail(for: event, strings: strings),
            status: nil,
            iconName: iconName(for: event.kind),
            severity: severity(for: event.kind)
        )
    }

    private static func switchTitle(for event: SwitchAuditEvent, strings: CodixxStrings) -> String {
        let target = event.targetAlias ?? strings.unknown
        switch event.result {
        case .success:
            return strings.switchSuccessTitle(target: target)
        case .rolledBack:
            return strings.rolledBack
        case .rollbackFailed:
            return strings.rollbackFailed
        case .skippedNoCandidate:
            return strings.noCandidate
        case .failedBeforeWrite:
            return strings.failedBeforeWrite
        case .failedDuringWrite:
            return strings.failedDuringWrite
        case .failedValidation:
            return strings.validationFailed
        }
    }

    private static func switchDetail(for event: SwitchAuditEvent, strings: CodixxStrings) -> String? {
        let source = event.sourceAlias ?? strings.unknown
        let target = event.targetAlias ?? strings.unknown
        var details = ["\(source) -> \(target)", strings.switchTriggerLabel(event.trigger)]
        if let errorSummary = event.errorSummary, !errorSummary.isEmpty {
            details.append("\(strings.errorSummaryLabel): \(errorSummary)")
        }
        if let backupPath = event.backupPath, !backupPath.isEmpty {
            details.append("\(strings.backupPathLabel): \(backupPath)")
        }
        return details.joined(separator: " · ")
    }

    private static func detail(for event: AppLogEvent, strings: CodixxStrings) -> String? {
        switch event.kind {
        case .accountRenamed:
            let source = event.accountAlias ?? strings.unknown
            let target = event.secondaryAlias ?? strings.unknown
            return "\(source) -> \(target)"
        default:
            return event.detail
        }
    }

    private static func category(for kind: AppLogEventKind) -> AppLogCategory {
        switch kind {
        case .accountSaved, .authImported, .apiProviderSaved, .apiProviderUpdated, .accountRenamed,
             .accountDeleted, .accountEnabled, .accountDisabled, .accountReordered:
            return .account
        case .apiBalanceRefreshed, .apiBalanceRefreshFailed:
            return .quota
        case .codexRestartFailed, .refreshFailed:
            return .system
        case .codexRestarted:
            return .system
        }
    }

    private static func severity(for kind: AppLogEventKind) -> AppLogSeverity {
        switch kind {
        case .codexRestartFailed, .refreshFailed, .apiBalanceRefreshFailed:
            return .error
        default:
            return .normal
        }
    }

    private static func iconName(for kind: AppLogEventKind) -> String {
        switch kind {
        case .accountSaved, .authImported, .apiProviderSaved, .apiProviderUpdated:
            return "person.crop.circle.badge.checkmark"
        case .accountRenamed:
            return "pencil.circle"
        case .accountDeleted:
            return "trash.circle"
        case .accountEnabled:
            return "checkmark.circle"
        case .accountDisabled:
            return "pause.circle"
        case .accountReordered:
            return "arrow.up.arrow.down.circle"
        case .codexRestarted:
            return "arrow.clockwise.circle"
        case .codexRestartFailed, .refreshFailed, .apiBalanceRefreshFailed:
            return "exclamationmark.triangle.fill"
        case .apiBalanceRefreshed:
            return "creditcard.circle"
        }
    }

    private static func severity(for result: SwitchAuditResult) -> AppLogSeverity {
        switch result {
        case .success:
            return .normal
        case .rolledBack, .skippedNoCandidate:
            return .warning
        case .rollbackFailed, .failedBeforeWrite, .failedDuringWrite, .failedValidation:
            return .error
        }
    }

    private static func iconName(for result: SwitchAuditResult) -> String {
        switch result {
        case .success:
            return "checkmark.circle.fill"
        case .rolledBack:
            return "arrow.uturn.backward.circle"
        case .rollbackFailed, .failedBeforeWrite, .failedDuringWrite, .failedValidation:
            return "exclamationmark.triangle.fill"
        case .skippedNoCandidate:
            return "minus.circle"
        }
    }
}

struct AppLogView: View {
    var entries: [AppLogEntry]
    var strings: CodixxStrings
    @Binding var selectedCategory: AppLogCategory
    var showsTitle = true

    private let timestampFormatter = AppLogTimestampFormatter()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsTitle {
                Text(strings.logs)
                    .font(.headline)
            }

            Picker(strings.logFilter, selection: $selectedCategory) {
                ForEach(AppLogCategory.allCases) { category in
                    Text(label(for: category)).tag(category)
                }
            }
            .pickerStyle(.segmented)

            if entries.isEmpty {
                Text(strings.noLogEvents)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(showsTitle ? 12 : 0)
                    .background(showsTitle ? Color(nsColor: .controlBackgroundColor) : .clear, in: RoundedRectangle(cornerRadius: 8))
            } else {
                ForEach(entries) { entry in
                    eventRow(entry)
                }
            }
        }
    }

    private func eventRow(_ entry: AppLogEntry) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(timestampFormatter.string(for: entry.timestamp))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 62, alignment: .leading)
                .accessibilityLabel(timestampFormatter.string(for: entry.timestamp))

            Image(systemName: entry.iconName)
                .foregroundStyle(color(for: entry.severity))
                .frame(width: 18)
                .accessibilityLabel(label(for: entry.category))

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(entry.title)
                        .font(.subheadline.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    if let status = entry.status {
                        Text(status)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(color(for: entry.severity))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(color(for: entry.severity).opacity(0.12), in: Capsule())
                    }
                }

                if let detail = entry.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(showsTitle ? 12 : 0)
        .background(showsTitle ? backgroundColor(for: entry.severity) : .clear, in: RoundedRectangle(cornerRadius: 8))
    }

    private func color(for severity: AppLogSeverity) -> Color {
        switch severity {
        case .normal:
            return .green
        case .warning:
            return .orange
        case .error:
            return .red
        }
    }

    private func label(for category: AppLogCategory) -> String {
        switch category {
        case .all:
            return strings.allLogs
        case .switching:
            return strings.switchLogs
        case .account:
            return strings.accountLogs
        case .quota:
            return strings.quotaLogs
        case .error:
            return strings.errorLogs
        case .system:
            return strings.systemLogs
        }
    }

    private func backgroundColor(for severity: AppLogSeverity) -> Color {
        switch severity {
        case .normal:
            return Color(nsColor: .controlBackgroundColor)
        case .warning:
            return Color.orange.opacity(0.10)
        case .error:
            return Color.red.opacity(0.10)
        }
    }
}
