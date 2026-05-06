import SwiftUI
import CodixxCore

struct QuotaView: View {
    var account: CodixxAccount?
    var config: CodixxConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(account?.alias ?? "No active account")
                        .font(.headline)
                    Text(confidenceText)
                        .font(.caption)
                        .foregroundStyle(confidenceColor)
                }
                Spacer()
                Text(primaryPercentText)
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }

            ProgressView(value: primaryProgress)
                .tint(progressTint)

            HStack {
                Label(secondaryPercentText, systemImage: "timer")
                Spacer()
                Label(resetText, systemImage: "clock")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }

    private var quota: AccountQuotaState? {
        account?.quota
    }

    private var primaryProgress: Double {
        min(max((quota?.primaryUsedPercent ?? 0) / 100, 0), 1)
    }

    private var primaryPercentText: String {
        guard let used = quota?.primaryUsedPercent else { return "--" }
        return "\(Int(used.rounded()))%"
    }

    private var secondaryPercentText: String {
        guard let used = quota?.secondaryUsedPercent else { return "Weekly --" }
        return "Weekly \(Int(used.rounded()))%"
    }

    private var resetText: String {
        guard let date = quota?.primaryResetsAt else { return "Reset unknown" }
        return "Resets \(date.formatted(date: .omitted, time: .shortened))"
    }

    private var confidenceText: String {
        switch quota?.confidence ?? .unknown {
        case .fresh:
            return "Fresh quota"
        case .recent:
            return "Recent quota"
        case .stale:
            return "Stale quota"
        case .unknown:
            return "Quota unknown"
        }
    }

    private var confidenceColor: Color {
        switch quota?.confidence ?? .unknown {
        case .fresh:
            return .green
        case .recent:
            return .blue
        case .stale:
            return .orange
        case .unknown:
            return .secondary
        }
    }

    private var progressTint: Color {
        guard let used = quota?.primaryUsedPercent else { return .secondary }
        return used >= config.primaryThresholdPercent ? .orange : .accentColor
    }
}
