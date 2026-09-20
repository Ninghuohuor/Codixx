import SwiftUI
import CodixxCore

struct QuotaView: View {
    var account: CodixxAccount?
    var config: CodixxConfig
    var strings: CodixxStrings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(account?.alias ?? strings.noActiveAccountTitle)
                        .font(.headline)
                    if account == nil {
                        Text(strings.noActiveAccountDetail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer()
                Text(confidenceText)
                    .font(.caption)
                    .foregroundStyle(confidenceColor)
            }

            if quota?.primaryUsedPercent == nil && quota?.secondaryUsedPercent == nil {
                Text(strings.quotaNotReported)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if quota?.primaryUsedPercent != nil {
                quotaProgress(
                    title: strings.quotaWindowTitle(minutes: quota?.primaryWindowMinutes),
                    percentText: primaryPercentText,
                    resetText: resetText,
                    progress: primaryProgress,
                    tint: progressTint
                )
            }
            if quota?.secondaryUsedPercent != nil {
                quotaProgress(
                    title: strings.quotaWindowTitle(minutes: quota?.secondaryWindowMinutes),
                    percentText: secondaryPercentText,
                    resetText: weeklyResetText,
                    progress: secondaryProgress,
                    tint: secondaryProgressTint
                )
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }

    private func quotaProgress(
        title: String,
        percentText: String,
        resetText: String,
        progress: Double,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(title) · \(resetText)")
                Spacer()
                Text(percentText)
                    .monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            ProgressView(value: progress)
                .tint(tint)
        }
        .help("\(title): \(percentText) · \(resetText)")
    }

    private var quota: AccountQuotaState? {
        account?.quota
    }

    private var primaryProgress: Double {
        min(max((quota?.primaryUsedPercent ?? 0) / 100, 0), 1)
    }

    private var secondaryProgress: Double {
        min(max((quota?.secondaryUsedPercent ?? 0) / 100, 0), 1)
    }

    private var primaryPercentText: String {
        guard let used = quota?.primaryUsedPercent else { return "--" }
        return "\(Int(used.rounded()))%"
    }

    private var secondaryPercentText: String {
        guard let used = quota?.secondaryUsedPercent else { return "--" }
        return "\(Int(used.rounded()))%"
    }

    private var resetText: String {
        guard let date = quota?.primaryResetsAt else { return strings.resetUnknown }
        return strings.resets(date)
    }

    private var weeklyResetText: String {
        guard let date = quota?.secondaryResetsAt else { return strings.resetUnknown }
        return strings.resets(date)
    }

    private var confidenceText: String {
        switch quota?.confidence ?? .unknown {
        case .fresh:
            return strings.freshQuota
        case .recent:
            return strings.recentQuota
        case .stale:
            return strings.staleQuota
        case .unknown:
            return strings.quotaUnknown
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
        return used >= (quota?.reportedWindows.first { !$0.isSecondary }?.threshold(short: config.primaryThresholdPercent, weekly: config.secondaryThresholdPercent) ?? config.primaryThresholdPercent) ? .orange : .accentColor
    }

    private var secondaryProgressTint: Color {
        guard let used = quota?.secondaryUsedPercent else { return .secondary }
        return used >= (quota?.reportedWindows.first { $0.isSecondary }?.threshold(short: config.primaryThresholdPercent, weekly: config.secondaryThresholdPercent) ?? config.secondaryThresholdPercent) ? .orange : .green
    }
}
