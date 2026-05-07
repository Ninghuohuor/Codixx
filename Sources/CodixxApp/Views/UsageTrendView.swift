import Charts
import SwiftUI
import CodixxCore

struct UsageTrendView: View {
    var snapshot: ThreadUsageSnapshot
    var accounts: [CodixxAccount]
    var strings: CodixxStrings
    var isLoading: Bool = false
    @State private var selectedAccountId: UUID?
    @State private var hoveredHour: Date?
    @State private var hoveredDay: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if isLoading {
                loadingBanner
            }
            overviewSection

            chartSection(title: strings.tokenUsageTwentyFourHours) {
                Chart(hourlyBuckets) { bucket in
                    LineMark(
                        x: .value(strings.hour, bucket.hour, unit: .hour),
                        y: .value(strings.tokens, bucket.tokens)
                    )
                    .foregroundStyle(.blue)
                    AreaMark(
                        x: .value(strings.hour, bucket.hour, unit: .hour),
                        y: .value(strings.tokens, bucket.tokens)
                    )
                    .foregroundStyle(.blue.opacity(0.18))

                    if let hoveredHour {
                        RuleMark(x: .value(strings.hour, hoveredHour))
                            .foregroundStyle(.secondary.opacity(0.5))
                            .lineStyle(StrokeStyle(lineWidth: 1))
                        if let bucket = hourlyBuckets.first(where: { $0.hour == hoveredHour }) {
                            PointMark(
                                x: .value(strings.hour, bucket.hour),
                                y: .value(strings.tokens, bucket.tokens)
                            )
                            .foregroundStyle(.blue)
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .hour, count: 6)) { _ in
                        AxisValueLabel(format: .dateTime.hour())
                    }
                }
                .chartOverlay { proxy in
                    GeometryReader { geo in
                        Rectangle()
                            .fill(.clear)
                            .contentShape(Rectangle())
                            .onContinuousHover { phase in
                                switch phase {
                                case .active(let location):
                                    if let date: Date = proxy.value(atX: location.x) {
                                        hoveredHour = nearestBucket(to: date, buckets: hourlyBuckets, keyPath: \.hour)
                                    }
                                case .ended:
                                    hoveredHour = nil
                                }
                            }
                    }
                }
                .overlay(alignment: .topLeading) {
                    if let hoveredHour,
                       let bucket = hourlyBuckets.first(where: { $0.hour == hoveredHour }) {
                        Text("\(bucket.hour.formatted(date: .omitted, time: .shortened)) · \(bucket.tokens.formatted()) \(strings.tokens)")
                            .font(.caption.monospacedDigit())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                            .padding(4)
                    }
                }
            }

            chartSection(title: strings.tokenUsageSevenDays) {
                Chart(dailyBuckets) { bucket in
                    BarMark(
                        x: .value(strings.day, bucket.day, unit: .day),
                        y: .value(strings.tokens, bucket.tokens)
                    )
                    .foregroundStyle(.blue)

                    if let hoveredDay {
                        RuleMark(x: .value(strings.day, hoveredDay))
                            .foregroundStyle(.secondary.opacity(0.5))
                            .lineStyle(StrokeStyle(lineWidth: 1))
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day)) { _ in
                        AxisValueLabel(format: .dateTime.weekday(.narrow))
                    }
                }
                .chartOverlay { proxy in
                    GeometryReader { geo in
                        Rectangle()
                            .fill(.clear)
                            .contentShape(Rectangle())
                            .onContinuousHover { phase in
                                switch phase {
                                case .active(let location):
                                    if let date: Date = proxy.value(atX: location.x) {
                                        hoveredDay = nearestBucket(to: date, buckets: dailyBuckets, keyPath: \.day)
                                    }
                                case .ended:
                                    hoveredDay = nil
                                }
                            }
                    }
                }
                .overlay(alignment: .topLeading) {
                    if let hoveredDay,
                       let bucket = dailyBuckets.first(where: { $0.day == hoveredDay }) {
                        Text("\(bucket.day.formatted(date: .abbreviated, time: .omitted)) · \(bucket.tokens.formatted()) \(strings.tokens)")
                            .font(.caption.monospacedDigit())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                            .padding(4)
                    }
                }
            }
        }
    }

    private var loadingBanner: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(strings.loadingTrendData)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
    }

    private var overviewSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(strings.overview)
                    .font(.headline)
                Spacer()
                Picker("", selection: $selectedAccountId) {
                    Text(strings.allAccounts).tag(UUID?.none)
                    ForEach(accounts) { account in
                        Text(account.alias).tag(Optional(account.id))
                    }
                }
                .labelsHidden()
                .frame(width: 132)
            }

            LazyVGrid(columns: metricColumns, alignment: .leading, spacing: 10) {
                MetricTile(title: strings.total, value: overviewTotalTokens.formatted(), systemImage: "sum")
                MetricTile(title: strings.threads, value: overviewThreadCount.formatted(), systemImage: "text.bubble")
                MetricTile(title: strings.todayTokens, value: todayTokens.formatted(), systemImage: "calendar")
                MetricTile(title: strings.yesterdayTokens, value: yesterdayTokens.formatted(), systemImage: "calendar.badge.clock")
                MetricTile(title: strings.currentMonthTokens, value: currentMonthTokens.formatted(), systemImage: "calendar.circle")
                MetricTile(title: strings.previousMonthTokens, value: previousMonthTokens.formatted(), systemImage: "calendar.badge.minus")
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }

    private var metricColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ]
    }

    private func chartSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            content()
                .frame(minHeight: 100, idealHeight: 132)
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var dailyBuckets: [TokenBucket] {
        snapshot.dailyTokenUsage.map { bucket in
            TokenBucket(id: bucket.start.timeIntervalSince1970, date: bucket.start, tokens: bucket.tokens)
        }
    }

    private var todayTokens: Int {
        tokens(inDayOffset: 0, buckets: overviewDailyTokenUsage)
    }

    private var yesterdayTokens: Int {
        tokens(inDayOffset: -1, buckets: overviewDailyTokenUsage)
    }

    private var currentMonthTokens: Int {
        tokens(inMonthOffset: 0, buckets: overviewMonthlyTokenUsage)
    }

    private var previousMonthTokens: Int {
        tokens(inMonthOffset: -1, buckets: overviewMonthlyTokenUsage)
    }

    private var overviewTotalTokens: Int {
        selectedAccountSummary?.totalTokens ?? snapshot.totalTokens
    }

    private var overviewThreadCount: Int {
        selectedAccountSummary?.threadCount ?? snapshot.threads.count
    }

    private var overviewDailyTokenUsage: [TokenUsageBucket] {
        selectedAccountSummary?.dailyTokenUsage ?? snapshot.dailyTokenUsage
    }

    private var overviewMonthlyTokenUsage: [TokenUsageBucket] {
        selectedAccountSummary?.monthlyTokenUsage ?? snapshot.monthlyTokenUsage
    }

    private var selectedAccountSummary: AccountUsageSummary? {
        guard let selectedAccountId else { return nil }
        return snapshot.accountUsageSummaries.first { $0.accountId == selectedAccountId }
    }

    private func tokens(inDayOffset offset: Int, buckets: [TokenUsageBucket]) -> Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let day = calendar.date(byAdding: .day, value: offset, to: today) ?? today
        return buckets.first { calendar.isDate($0.start, inSameDayAs: day) }?.tokens ?? 0
    }

    private func tokens(inMonthOffset offset: Int, buckets: [TokenUsageBucket]) -> Int {
        let calendar = Calendar.current
        let currentMonth = calendar.dateInterval(of: .month, for: Date())?.start ?? calendar.startOfDay(for: Date())
        let month = calendar.date(byAdding: .month, value: offset, to: currentMonth) ?? currentMonth
        return buckets.first { $0.start == month }?.tokens ?? 0
    }

    private var hourlyBuckets: [TokenBucket] {
        snapshot.hourlyTokenUsage.map { bucket in
            TokenBucket(id: bucket.start.timeIntervalSince1970, date: bucket.start, tokens: bucket.tokens)
        }
    }

    private func nearestBucket(to date: Date, buckets: [TokenBucket], keyPath: KeyPath<TokenBucket, Date>) -> Date? {
        buckets.min(by: { abs($0[keyPath: keyPath].timeIntervalSince(date)) < abs($1[keyPath: keyPath].timeIntervalSince(date)) })?.date
    }
}

private struct MetricTile: View {
    var title: String
    var value: String
    var systemImage: String

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Text(value)
                    .font(.headline)
                    .monospacedDigit()
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .help("\(title): \(value)")
    }
}

private struct TokenBucket: Identifiable {
    var id: TimeInterval
    var date: Date
    var tokens: Int

    var day: Date { date }
    var hour: Date { date }
}
