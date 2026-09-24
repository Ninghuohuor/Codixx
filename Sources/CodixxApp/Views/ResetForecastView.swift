import SwiftUI
import CodixxCore

struct ResetForecastView: View {
    @ObservedObject var store: ResetForecastStore
    @State private var calendarWeeks = 26
    @State private var selectedCalendarDate: Date?

    private let resetSiteURL = URL(string: "https://codexreset.club/")!

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    header
                    if let error = store.error {
                        statusBanner(error, systemImage: "wifi.exclamationmark", tint: .orange)
                    }

                    if let feed = store.feed {
                        forecastModule(feed)
                        if let outlook = ResetCardOutlook.calculate(feed: feed, now: context.date) {
                            resetCardModule(outlook)
                        }
                        latestResetModule(feed, now: context.date)
                        resetCalendarModule(feed, now: context.date)
                        reminderSection
                        sourceFooter(feed, now: context.date)
                    } else if store.isRefreshing {
                        emptyState("正在获取预测数据…", systemImage: "arrow.clockwise")
                    } else {
                        emptyState("暂未获取到预测数据，请点击刷新。", systemImage: "calendar.badge.exclamationmark")
                    }
                }
                .padding(14)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { store.refresh() }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("重置预测")
                    .font(.title3.weight(.semibold))
                Text("自动重置公告与重置卡公开信息")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            HStack(spacing: 8) {
                Link(destination: resetSiteURL) {
                    Label("查看详情", systemImage: "arrow.up.right.square")
                }
                .controlSize(.small)
                .buttonStyle(.borderless)

                Button { store.refresh(force: true) } label: {
                    Label(store.isRefreshing ? "更新中" : "刷新", systemImage: "arrow.clockwise")
                }
                .controlSize(.small)
                .disabled(store.isRefreshing)
            }
        }
    }

    private func forecastModule(_ feed: ResetFeed) -> some View {
        return moduleCard(accent: .blue) {
            moduleHeader(
                title: "预测自动重置",
                subtitle: "来自 codexreset.club 的预测",
                systemImage: "calendar.badge.clock",
                accent: .blue
            )

            if let estimate = feed.forecast {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(date(estimate.day, format: "M 月 d 日"))
                            .font(.system(size: 28, weight: .semibold, design: .rounded))
                        Text("北京时间 · 非官方预告")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("\(Int((estimate.probability * 100).rounded()))%")
                            .font(.system(size: 26, weight: .semibold, design: .rounded))
                            .foregroundStyle(.blue)
                        Text("截至当日累计概率")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                HStack(spacing: 0) {
                    metric("历史平均间隔", estimate.averageDays.map { String(format: "%.1f 天", $0) } ?? "暂无样本")
                    Divider().frame(height: 28)
                    metric("有效间隔样本", "\(estimate.sampleCount) 个")
                }
                .frame(maxWidth: .infinity)

                Text(estimate.basis == "default" ? "按默认 7 天间隔推算等待时间的中位日期，非官方预告。" : "按历史间隔和当前等待时间推算中位日期，非官方预告。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("网站尚未提供预测结果，请稍后刷新。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func resetCardModule(_ outlook: ResetCardOutlook) -> some View {
        moduleCard(accent: .orange) {
            moduleHeader(
                title: "重置卡",
                subtitle: "公开公告中的重置卡线索",
                systemImage: "ticket.fill",
                accent: .orange
            )

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(date(outlook.date, format: outlook.explicitTime ? "M 月 d 日 HH:mm" : "M 月 d 日 EEEE", zone: outlook.explicitTime ? "Asia/Shanghai" : "America/Los_Angeles"))
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                    Text(outlook.explicitTime ? "已公布具体时间" : "预计日期，尚未确认")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Spacer(minLength: 8)
                Link("查看来源", destination: outlook.sourceURL)
                    .font(.caption)
            }

            Text(outlook.text.isEmpty ? "已抓取到重置卡相关公告。" : outlook.text)
                .font(.caption)
                .foregroundStyle(.primary)
                .lineLimit(3)
                .textSelection(.enabled)
        }
    }

    private func latestResetModule(_ feed: ResetFeed, now: Date) -> some View {
        let event = feed.latest("automatic_reset", now: now)
        return moduleCard(accent: .purple) {
            moduleHeader(
                title: "什么时候自动重置过",
                subtitle: "最近一条已收录的自动重置公告",
                systemImage: "clock.arrow.circlepath",
                accent: .purple
            )

            if let event {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(date(event.announcedAt, format: "M 月 d 日 HH:mm"))
                            .font(.system(size: 24, weight: .semibold, design: .rounded))
                        Text("北京时间 · \(phase(event.effects.first { $0.kind == "automatic_reset" }?.phase))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    if let link = event.safeURL {
                        Link("查看来源", destination: link)
                            .font(.caption)
                    }
                }
                if let summary = event.summaryZh ?? event.originalText, !summary.isEmpty {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .lineLimit(3)
                        .textSelection(.enabled)
                }
            } else {
                Label("暂未收录自动重置公告", systemImage: "clock.badge.questionmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func resetCalendarModule(_ feed: ResetFeed, now: Date) -> some View {
        let days = calendarDays(feed, now: now, weeks: calendarWeeks)
        let columns = calendarColumns(from: days)
        return moduleCard(accent: .green) {
            HStack(alignment: .top, spacing: 10) {
                moduleHeader(
                    title: "重置日历",
                    subtitle: "按公告日期查看收录情况",
                    systemImage: "calendar",
                    accent: .green
                )
                Spacer(minLength: 8)
                Picker("", selection: $calendarWeeks) {
                    Text("近半年").tag(26)
                    Text("近一年").tag(53)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 132)
            }

            HStack(spacing: 10) {
                calendarLegend("自动重置", color: .blue)
                calendarLegend("重置卡", color: .orange)
                calendarLegend("两种都有", color: .purple)
                calendarLegend("无公告", color: Color.secondary.opacity(0.16))
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: calendarWeeks == 53) {
                HStack(alignment: .top, spacing: 4) {
                    VStack(spacing: 3) {
                        Text("")
                            .frame(height: 14)
                        ForEach(Array(["一", "", "三", "", "五", "", "日"].enumerated()), id: \.offset) { _, label in
                            Text(label)
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                                .frame(width: 12, height: 14)
                        }
                    }

                    HStack(alignment: .top, spacing: 3) {
                        ForEach(Array(columns.enumerated()), id: \.offset) { _, week in
                            VStack(spacing: 3) {
                                Text(monthLabel(for: week))
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                                    .frame(height: 14)
                                ForEach(week) { day in
                                    calendarCell(day)
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let selectedCalendarDate,
               let selectedDay = days.first(where: { $0.date == selectedCalendarDate }) {
                Text("已选 " + date(selectedDay.date, format: "M 月 d 日") + " · " + String(selectedDay.count) + " 条公告")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var reminderSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "bell.badge")
                    .foregroundStyle(.secondary)
                Text("Codixx 提醒")
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }
            Toggle("自动重置公告", isOn: Binding(get: { store.preferences.automatic }, set: { store.setReminder(automatic: $0) }))
            Toggle("重置卡消息（含未确认线索）", isOn: Binding(get: { store.preferences.cards }, set: { store.setReminder(cards: $0) }))
            Text("Codixx 运行时每 5 分钟检查；首次开启不补发旧消息。")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let error = store.notificationError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
    }

    private func sourceFooter(_ feed: ResetFeed, now: Date) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(feed.isFresh(at: now) && store.error == nil ? Color.green : Color.orange)
                .frame(width: 6, height: 6)
            Text(feed.isFresh(at: now) && store.error == nil ? "数据已更新" : "数据可能延迟")
            if let updated = feed.lastSuccessAt {
                Text(date(updated, format: "M/d HH:mm"))
            }
            Spacer()
            Link("codexreset.club", destination: resetSiteURL)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private func moduleCard<Content: View>(accent: Color, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 154, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .strokeBorder(accent.opacity(0.18), lineWidth: 1)
        }
        .overlay(alignment: .topLeading) {
            Capsule()
                .fill(accent)
                .frame(width: 34, height: 3)
                .padding(.leading, 14)
        }
    }

    private func moduleHeader(title: String, subtitle: String, systemImage: String, accent: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 28, height: 28)
                .background(accent.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func calendarCell(_ day: ResetCalendarDay) -> some View {
        Button {
            selectedCalendarDate = day.date
        } label: {
            RoundedRectangle(cornerRadius: 3)
                .fill(calendarColor(day.marker))
                .frame(width: 14, height: 14)
                .overlay {
                    if day.isToday {
                        RoundedRectangle(cornerRadius: 3)
                            .strokeBorder(Color.primary.opacity(0.7), lineWidth: 1)
                    }
                    if day.date == selectedCalendarDate {
                        RoundedRectangle(cornerRadius: 3)
                            .strokeBorder(Color.green, lineWidth: 2)
                    }
                }
        }
        .buttonStyle(.plain)
        .help("\(date(day.date, format: "M 月 d 日")) · \(day.count) 条公告")
        .accessibilityLabel("\(date(day.date, format: "M 月 d 日"))，\(day.count) 条公告")
    }

    private func calendarLegend(_ title: String, color: Color) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 10, height: 10)
            Text(title)
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.medium))
        }
        .frame(maxWidth: .infinity)
    }

    private func statusBanner(_ text: String, systemImage: String, tint: Color) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption)
            .foregroundStyle(tint)
            .fixedSize(horizontal: false, vertical: true)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
    }

    private func emptyState(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 150)
    }

    private func calendarDays(_ feed: ResetFeed, now: Date, weeks: Int) -> [ResetCalendarDay] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let today = calendar.startOfDay(for: now)
        let weekday = calendar.component(.weekday, from: today)
        let mondayOffset = (weekday + 5) % 7
        let start = calendar.date(byAdding: .day, value: -mondayOffset - (weeks - 1) * 7, to: today) ?? today
        var records: [String: (count: Int, kinds: Set<String>)] = [:]

        for event in feed.announcements where event.isUsable && event.announcedAt <= now {
            let key = calendarKey(event.announcedAt, calendar: calendar)
            var record = records[key] ?? (0, [])
            record.count += 1
            event.effects.forEach { record.kinds.insert($0.kind) }
            records[key] = record
        }

        return (0..<(weeks * 7)).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            let key = calendarKey(date, calendar: calendar)
            let record = records[key]
            return ResetCalendarDay(
                id: key,
                date: date,
                count: record?.count ?? 0,
                marker: marker(for: record?.kinds ?? []),
                isToday: calendar.isDate(date, inSameDayAs: today)
            )
        }
    }

    private func calendarColumns(from days: [ResetCalendarDay]) -> [[ResetCalendarDay]] {
        stride(from: 0, to: days.count, by: 7).map { index in
            Array(days[index..<min(index + 7, days.count)])
        }
    }

    private func marker(for kinds: Set<String>) -> ResetCalendarMarker {
        let hasAutomatic = kinds.contains("automatic_reset")
        let hasCard = kinds.contains("banked_reset")
        if hasAutomatic && hasCard { return .both }
        if hasAutomatic { return .automatic }
        if hasCard { return .card }
        return .empty
    }

    private func calendarColor(_ marker: ResetCalendarMarker) -> Color {
        switch marker {
        case .automatic: return .blue
        case .card: return .orange
        case .both: return .purple
        case .empty: return Color.secondary.opacity(0.14)
        }
    }

    private func calendarKey(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    private func monthLabel(for week: [ResetCalendarDay]) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        guard let date = week.first(where: { calendar.component(.day, from: $0.date) == 1 })?.date else { return "" }
        return dateFormatter("M 月", zone: "Asia/Shanghai").string(from: date)
    }

    private func dateFormatter(_ format: String, zone: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = TimeZone(identifier: zone)
        formatter.dateFormat = format
        return formatter
    }

    private func date(_ value: Date, format: String, zone: String = "Asia/Shanghai") -> String {
        dateFormatter(format, zone: zone).string(from: value)
    }

    private func phase(_ value: String?) -> String {
        switch value {
        case "announced": return "已预告"
        case "rolling_out": return "正在发放 / 生效"
        case "completed": return "已完成"
        default: return "状态未明确"
        }
    }
}

private enum ResetCalendarMarker: Hashable {
    case empty
    case automatic
    case card
    case both
}

private struct ResetCalendarDay: Identifiable, Hashable {
    let id: String
    let date: Date
    let count: Int
    let marker: ResetCalendarMarker
    let isToday: Bool
}
