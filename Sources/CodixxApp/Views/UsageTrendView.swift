import Charts
import SwiftUI
import CodixxCore

struct UsageTrendView: View {
    var snapshot: ThreadUsageSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                MetricTile(title: "Total", value: snapshot.totalTokens.formatted(), systemImage: "sum")
                MetricTile(title: "Threads", value: snapshot.threads.count.formatted(), systemImage: "text.bubble")
            }

            chartSection(title: "7 days") {
                Chart(dailyBuckets) { bucket in
                    BarMark(
                        x: .value("Day", bucket.day, unit: .day),
                        y: .value("Tokens", bucket.tokens)
                    )
                    .foregroundStyle(.blue)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day)) { _ in
                        AxisValueLabel(format: .dateTime.weekday(.narrow))
                    }
                }
            }

            chartSection(title: "24 hours") {
                Chart(hourlyBuckets) { bucket in
                    LineMark(
                        x: .value("Hour", bucket.hour, unit: .hour),
                        y: .value("Tokens", bucket.tokens)
                    )
                    .foregroundStyle(.green)
                    AreaMark(
                        x: .value("Hour", bucket.hour, unit: .hour),
                        y: .value("Tokens", bucket.tokens)
                    )
                    .foregroundStyle(.green.opacity(0.18))
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .hour, count: 6)) { _ in
                        AxisValueLabel(format: .dateTime.hour())
                    }
                }
            }
        }
    }

    private func chartSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            content()
                .frame(height: 132)
                .padding(10)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var dailyBuckets: [TokenBucket] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date()).addingTimeInterval(-6 * 86_400)
        return (0..<7).map { offset in
            let day = calendar.date(byAdding: .day, value: offset, to: start) ?? start
            let nextDay = calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400)
            let tokens = snapshot.threads
                .filter { $0.updatedAt >= day && $0.updatedAt < nextDay }
                .reduce(0) { $0 + $1.tokensUsed }
            return TokenBucket(id: day.timeIntervalSince1970, date: day, tokens: tokens)
        }
    }

    private var hourlyBuckets: [TokenBucket] {
        let calendar = Calendar.current
        let currentHour = calendar.dateInterval(of: .hour, for: Date())?.start ?? Date()
        let start = calendar.date(byAdding: .hour, value: -23, to: currentHour) ?? currentHour
        return (0..<24).map { offset in
            let hour = calendar.date(byAdding: .hour, value: offset, to: start) ?? start
            let nextHour = calendar.date(byAdding: .hour, value: 1, to: hour) ?? hour.addingTimeInterval(3_600)
            let tokens = snapshot.threads
                .filter { $0.updatedAt >= hour && $0.updatedAt < nextHour }
                .reduce(0) { $0 + $1.tokensUsed }
            return TokenBucket(id: hour.timeIntervalSince1970, date: hour, tokens: tokens)
        }
    }
}

private struct MetricTile: View {
    var title: String
    var value: String
    var systemImage: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .frame(width: 24, height: 24)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.headline)
                    .monospacedDigit()
            }
            Spacer()
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct TokenBucket: Identifiable {
    var id: TimeInterval
    var date: Date
    var tokens: Int

    var day: Date { date }
    var hour: Date { date }
}
