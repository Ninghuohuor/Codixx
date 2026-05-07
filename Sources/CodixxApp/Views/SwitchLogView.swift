import SwiftUI
import CodixxCore

struct SwitchLogView: View {
    var events: [SwitchAuditEvent]
    var strings: CodixxStrings

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(strings.switchLog)
                .font(.headline)

            if events.isEmpty {
                Text(strings.noSwitchEvents)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            } else {
                ForEach(events) { event in
                    eventRow(event)
                }
            }
        }
    }

    private func eventRow(_ event: SwitchAuditEvent) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: iconName(for: event.result))
                .foregroundStyle(color(for: event.result))
                .frame(width: 20)
                .accessibilityLabel(strings.switchResultLabel(event.result))

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(title(for: event))
                        .font(.subheadline.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Text(strings.switchResultLabel(event.result))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(color(for: event.result))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(color(for: event.result).opacity(0.12), in: Capsule())
                }

                Text(route(for: event))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Text(strings.switchTriggerLabel(event.trigger))
                    Text(event.timestamp.formatted(date: .abbreviated, time: .shortened))
                }
                .font(.caption2)
                .foregroundStyle(.secondary)

                if let errorSummary = event.errorSummary, !errorSummary.isEmpty {
                    detailLine(label: strings.errorSummaryLabel, value: errorSummary, color: .red)
                }

                if let backupPath = event.backupPath, !backupPath.isEmpty {
                    detailLine(label: strings.backupPathLabel, value: backupPath, color: .secondary)
                }
            }
        }
        .padding(12)
        .background(backgroundColor(for: event.result), in: RoundedRectangle(cornerRadius: 8))
    }

    private func detailLine(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(color)
            Text(value)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
    }

    private func title(for event: SwitchAuditEvent) -> String {
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

    private func route(for event: SwitchAuditEvent) -> String {
        let source = event.sourceAlias ?? strings.unknown
        let target = event.targetAlias ?? strings.unknown
        return "\(source) -> \(target)"
    }

    private func iconName(for result: SwitchAuditResult) -> String {
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

    private func color(for result: SwitchAuditResult) -> Color {
        switch result {
        case .success:
            return .green
        case .rolledBack, .skippedNoCandidate:
            return .orange
        case .rollbackFailed, .failedBeforeWrite, .failedDuringWrite, .failedValidation:
            return .red
        }
    }

    private func backgroundColor(for result: SwitchAuditResult) -> Color {
        switch result {
        case .success:
            return Color(nsColor: .controlBackgroundColor)
        case .rolledBack, .skippedNoCandidate:
            return Color.orange.opacity(0.10)
        case .rollbackFailed, .failedBeforeWrite, .failedDuringWrite, .failedValidation:
            return Color.red.opacity(0.10)
        }
    }
}
