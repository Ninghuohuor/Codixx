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
                        x: .value(strings.hour, bucket.hour),
                        y: .value(strings.tokens, bucket.tokens)
                    )
                    .foregroundStyle(.blue)
                    AreaMark(
                        x: .value(strings.hour, bucket.hour),
                        y: .value(strings.tokens, bucket.tokens)
                    )
                    .foregroundStyle(.blue.opacity(0.18))
                }
                .chartXScale(domain: hourlyDomain)
                .chartXAxis {
                    AxisMarks(values: hourlyAxisValues) { _ in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel(format: .dateTime.hour())
                            .foregroundStyle(.clear)
                    }
                }
                .chartOverlay { proxy in
                    GeometryReader { geo in
                        let plotFrame = geo[proxy.plotAreaFrame]
                        ZStack(alignment: .topLeading) {
                            Rectangle()
                                .fill(.clear)
                                .contentShape(Rectangle())
                                .onContinuousHover { phase in
                                    switch phase {
                                    case .active(let location):
                                        guard plotFrame.contains(location) else {
                                            hoveredHour = nil
                                            return
                                        }
                                        if let date: Date = proxy.value(atX: location.x - plotFrame.origin.x) {
                                            hoveredHour = nearestBucket(to: date, buckets: hourlyBuckets, keyPath: \.hour)
                                        }
                                    case .ended:
                                        hoveredHour = nil
                                    }
                                }

                            if let hoveredHour,
                               let bucket = hourlyBuckets.first(where: { $0.hour == hoveredHour }) {
                                let xPos = (proxy.position(forX: bucket.hour) ?? 0) + plotFrame.origin.x
                                let yPos = (proxy.position(forY: bucket.tokens) ?? 0) + plotFrame.origin.y

                                Rectangle()
                                    .fill(Color.secondary.opacity(0.5))
                                    .frame(width: 1, height: plotFrame.height)
                                    .offset(x: xPos, y: plotFrame.origin.y)

                                Circle()
                                    .fill(.blue)
                                    .frame(width: 8, height: 8)
                                    .offset(x: xPos - 4, y: yPos - 4)

                                Text("\(bucket.hour.formatted(date: .omitted, time: .shortened)) · \(bucket.tokens.formatted()) \(strings.tokens)")
                                    .font(.caption.monospacedDigit())
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                                    .offset(x: max(plotFrame.origin.x, min(xPos - 40, plotFrame.origin.x + plotFrame.width - 140)), y: plotFrame.origin.y + 4)
                            }

                            ForEach(hourlyAxisValues, id: \.timeIntervalSince1970) { value in
                                if let x = proxy.position(forX: value) {
                                    Text(axisHourLabel(for: value))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 48, alignment: .center)
                                        .offset(x: plotFrame.origin.x + x - 24, y: plotFrame.maxY + 8)
                                }
                            }
                        }
                    }
                }
            }

            chartSection(title: strings.tokenUsageSevenDays) {
                Chart(dailyBuckets) { bucket in
                    RectangleMark(
                        xStart: .value(strings.day, bucket.day),
                        xEnd: .value(strings.day, bucket.dayEnd),
                        yStart: .value(strings.tokens, 0),
                        yEnd: .value(strings.tokens, bucket.tokens)
                    )
                    .foregroundStyle(.blue)

                    if let hoveredDay {
                        RuleMark(x: .value(strings.day, hoveredDay.addingTimeInterval(12 * 3_600)))
                            .foregroundStyle(.secondary.opacity(0.5))
                            .lineStyle(StrokeStyle(lineWidth: 1))
                    }
                }
                .chartXScale(domain: dailyDomain)
                .chartXAxis {
                    AxisMarks(values: dailyAxisValues) { _ in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel(format: .dateTime.weekday(.narrow))
                            .foregroundStyle(.clear)
                    }
                }
                .chartOverlay { proxy in
                    GeometryReader { geo in
                        let plotFrame = geo[proxy.plotAreaFrame]
                        Rectangle()
                            .fill(.clear)
                            .contentShape(Rectangle())
                            .onContinuousHover { phase in
                                switch phase {
                                case .active(let location):
                                    guard plotFrame.contains(location) else {
                                        hoveredDay = nil
                                        return
                                    }
                                    if let date: Date = proxy.value(atX: location.x - plotFrame.origin.x) {
                                        hoveredDay = bucket(containing: date, buckets: dailyBuckets, interval: 86_400)?.day
                                    }
                                case .ended:
                                    hoveredDay = nil
                                }
                            }
                        ForEach(dailyAxisValues, id: \.timeIntervalSince1970) { value in
                            if let x = proxy.position(forX: value) {
                                Text(axisWeekdayLabel(for: value))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 32, alignment: .center)
                                    .offset(x: plotFrame.origin.x + x - 16, y: plotFrame.maxY + 8)
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
                MetricTile(title: strings.currentMonthTokens, value: currentMonthTokens.formatted(), systemImage: "calendar.circle")
                MetricTile(title: strings.yesterdayTokens, value: yesterdayTokens.formatted(), systemImage: "calendar.badge.clock")
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

    private var hourlyDomain: ClosedRange<Date> {
        guard let first = hourlyBuckets.first?.hour,
              let last = hourlyBuckets.last?.hour
        else {
            let now = Date()
            return now.addingTimeInterval(-23 * 3_600)...now
        }
        if first == last {
            return first...first.addingTimeInterval(3_600)
        }
        return first...last
    }

    private var dailyDomain: ClosedRange<Date> {
        guard let first = dailyBuckets.first?.day,
              let last = dailyBuckets.last?.dayEnd
        else {
            let today = Calendar.current.startOfDay(for: Date())
            return today.addingTimeInterval(-6 * 86_400)...today
        }
        if first == last {
            return first...first.addingTimeInterval(86_400)
        }
        return first...last
    }

    private var hourlyAxisValues: [Date] {
        hourlyBuckets.enumerated().compactMap { index, bucket in
            index.isMultiple(of: 6) ? bucket.hour : nil
        }
    }

    private var dailyAxisValues: [Date] {
        dailyBuckets.map(\.dayCenter)
    }

    private func bucket(containing date: Date, buckets: [TokenBucket], interval: TimeInterval) -> TokenBucket? {
        if let bucket = buckets.first(where: { date >= $0.date && date < $0.date.addingTimeInterval(interval) }) {
            return bucket
        }
        return buckets.min {
            abs($0.date.addingTimeInterval(interval / 2).timeIntervalSince(date)) <
                abs($1.date.addingTimeInterval(interval / 2).timeIntervalSince(date))
        }
    }

    private func nearestBucket(to date: Date, buckets: [TokenBucket], keyPath: KeyPath<TokenBucket, Date>) -> Date? {
        buckets.min(by: { abs($0[keyPath: keyPath].timeIntervalSince(date)) < abs($1[keyPath: keyPath].timeIntervalSince(date)) })?.date
    }

    private func axisHourLabel(for date: Date) -> String {
        date.formatted(.dateTime.hour())
    }

    private func axisWeekdayLabel(for date: Date) -> String {
        date.formatted(.dateTime.weekday(.narrow))
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
    var dayCenter: Date { date.addingTimeInterval(12 * 3_600) }
    var dayEnd: Date { date.addingTimeInterval(24 * 3_600) }
    var hour: Date { date }
    var hourCenter: Date { date.addingTimeInterval(30 * 60) }
    var hourEnd: Date { date.addingTimeInterval(60 * 60) }
}
