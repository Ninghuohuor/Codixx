import Charts
import SwiftUI
import CodixxCore

struct UsageTrendView: View {
    var snapshot: ThreadUsageSnapshot
    var strings: CodixxStrings

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            MetricTile(title: strings.total, value: snapshot.totalTokens.formatted(), systemImage: "sum")
            MetricTile(title: strings.threads, value: snapshot.threads.count.formatted(), systemImage: "text.bubble")
            MetricTile(title: strings.todayTokens, value: todayTokens.formatted(), systemImage: "calendar")
            MetricTile(title: strings.yesterdayTokens, value: yesterdayTokens.formatted(), systemImage: "calendar.badge.clock")

            chartSection(title: strings.threadsUpdatedSevenDays) {
                Chart(dailyBuckets) { bucket in
                    BarMark(
                        x: .value(strings.day, bucket.day, unit: .day),
                        y: .value(strings.tokens, bucket.tokens)
                    )
                    .foregroundStyle(.blue)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day)) { _ in
                        AxisValueLabel(format: .dateTime.weekday(.narrow))
                    }
                }
            }

            chartSection(title: strings.threadsUpdatedTwentyFourHours) {
                Chart(hourlyBuckets) { bucket in
                    LineMark(
                        x: .value(strings.hour, bucket.hour, unit: .hour),
                        y: .value(strings.tokens, bucket.tokens)
                    )
                    .foregroundStyle(.green)
                    AreaMark(
                        x: .value(strings.hour, bucket.hour, unit: .hour),
                        y: .value(strings.tokens, bucket.tokens)
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
        snapshot.dailyTokenUsage.map { bucket in
            TokenBucket(id: bucket.start.timeIntervalSince1970, date: bucket.start, tokens: bucket.tokens)
        }
    }

    private var todayTokens: Int {
        tokens(inDayOffset: 0)
    }

    private var yesterdayTokens: Int {
        tokens(inDayOffset: -1)
    }

    private func tokens(inDayOffset offset: Int) -> Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let day = calendar.date(byAdding: .day, value: offset, to: today) ?? today
        return snapshot.dailyTokenUsage.first { calendar.isDate($0.start, inSameDayAs: day) }?.tokens ?? 0
    }

    private var hourlyBuckets: [TokenBucket] {
        snapshot.hourlyTokenUsage.map { bucket in
            TokenBucket(id: bucket.start.timeIntervalSince1970, date: bucket.start, tokens: bucket.tokens)
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
