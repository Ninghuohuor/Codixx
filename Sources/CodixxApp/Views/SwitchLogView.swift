import SwiftUI
import CodixxCore

struct SwitchLogView: View {
    var events: [SwitchAuditEvent]
    var strings: CodixxStrings

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
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
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: iconName(for: event.result))
                            .foregroundStyle(color(for: event.result))
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(title(for: event))
                                .font(.subheadline)
                                .lineLimit(1)
                            Text(event.timestamp.formatted(date: .omitted, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(10)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
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
}
