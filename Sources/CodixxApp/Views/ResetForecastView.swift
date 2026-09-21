import SwiftUI
import CodixxCore

struct ResetForecastView: View {
    @ObservedObject var store: ResetForecastStore

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    header
                    if let error = store.error {
                        statusBanner(error, systemImage: "wifi.exclamationmark", tint: .orange)
                    }
                    if let feed = store.feed {
                        forecastHero(feed, now: context.date)
                        activitySection(feed, now: context.date)
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
                Text("重置预测").font(.title3.weight(.semibold))
                Text("额外重置公告与重置卡消息").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button { store.refresh(force: true) } label: {
                Label(store.isRefreshing ? "更新中" : "刷新", systemImage: "arrow.clockwise")
            }
            .controlSize(.small)
            .disabled(store.isRefreshing)
        }
    }

    private func forecastHero(_ feed: ResetFeed, now: Date) -> some View {
        let estimate = ResetEstimate.calculate(feed: feed, now: now)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Label("下次自动重置预估", systemImage: "calendar.badge.clock")
                        .font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                    Text(date(estimate.day, format: "M 月 d 日"))
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                    Text("北京时间 · 非官方预告").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(Int((estimate.probability * 100).rounded()))%")
                        .font(.system(size: 28, weight: .semibold, design: .rounded)).foregroundStyle(Color.accentColor)
                    Text(estimate.basis == "empirical" ? "历史概率" : "模型概率")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Divider()
            HStack(spacing: 0) {
                metric("历史平均间隔", estimate.averageDays.map { String(format: "%.1f 天", $0) } ?? "暂无样本")
                Divider().frame(height: 28)
                metric("样本", "\(estimate.sampleCount) 个间隔")
            }
            .frame(maxWidth: .infinity)
            Text(estimate.basis == "empirical" ? "根据历史公告间隔推测，日期可能随新公告更新。" : estimate.basis == "average" ? "按历史平均间隔估算，样本仍可能变化。" : "样本不足，暂按默认 7 天间隔估算。")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }

    private func activitySection(_ feed: ResetFeed, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle("最新动态", systemImage: "list.bullet.rectangle")
            activityRow(title: "自动重置", icon: "arrow.counterclockwise", content: latestResetText(feed, now: now), link: feed.latest("automatic_reset", now: now)?.safeURL)
            Divider().padding(.leading, 30)
            cardActivityRow(feed, now: now)
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }

    private func cardActivityRow(_ feed: ResetFeed, now: Date) -> some View {
        if let outlook = ResetCardOutlook.calculate(feed: feed, now: now) {
            return AnyView(activityRow(title: "重置卡", icon: "ticket", content: "预计 \(date(outlook.date, format: outlook.explicitTime ? "M 月 d 日 HH:mm" : "M 月 d 日 EEEE", zone: outlook.explicitTime ? "Asia/Shanghai" : "America/Los_Angeles")) · 未确认线索", detail: outlook.text, link: outlook.sourceURL, warning: true))
        }
        let event = feed.latest("banked_reset", now: now)
        return AnyView(activityRow(title: "重置卡", icon: "ticket", content: event.map { "\(phase($0.effects.first { $0.kind == "banked_reset" }?.phase)) · \(date($0.announcedAt, format: "M 月 d 日 HH:mm"))" } ?? "暂无新的重置卡消息", detail: event?.summaryZh ?? event?.originalText, link: event?.safeURL))
    }

    private var reminderSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("本地提醒", systemImage: "bell")
            Toggle("自动重置公告", isOn: Binding(get: { store.preferences.automatic }, set: { store.setReminder(automatic: $0) }))
            Toggle("重置卡消息（含未确认线索）", isOn: Binding(get: { store.preferences.cards }, set: { store.setReminder(cards: $0) }))
            Text("Codixx 运行时每 5 分钟检查；首次开启不补发旧消息。").font(.caption).foregroundStyle(.secondary)
            if let error = store.notificationError { Text(error).font(.caption).foregroundStyle(.orange) }
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }

    private func sourceFooter(_ feed: ResetFeed, now: Date) -> some View {
        HStack(spacing: 6) {
            Circle().fill(feed.isFresh(at: now) && store.error == nil ? Color.green : Color.orange).frame(width: 6, height: 6)
            Text(feed.isFresh(at: now) && store.error == nil ? "数据已更新" : "数据可能延迟")
            if let updated = feed.lastSuccessAt { Text(date(updated, format: "M/d HH:mm")) }
            Spacer()
            Link("来源 codexreset", destination: URL(string: "https://codexreset.club/")!)
        }
        .font(.caption2).foregroundStyle(.secondary)
    }

    private func activityRow(title: String, icon: String, content: String, detail: String? = nil, link: URL? = nil, warning: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Image(systemName: icon).frame(width: 20)
                Text(title).font(.subheadline.weight(.medium))
                Spacer()
                if let link { Link("查看来源", destination: link).font(.caption) }
            }
            Text(content).font(.caption).foregroundStyle(warning ? .orange : .secondary)
            if let detail, !detail.isEmpty { Text(detail).font(.caption).lineLimit(2).foregroundStyle(.primary).textSelection(.enabled) }
        }
        .padding(.vertical, 10)
    }

    private func latestResetText(_ feed: ResetFeed, now: Date) -> String {
        guard let event = feed.latest("automatic_reset", now: now) else { return "暂无有效公告" }
        return "\(date(event.announcedAt, format: "M 月 d 日 HH:mm")) · \(phase(event.effects.first { $0.kind == "automatic_reset" }?.phase))"
    }

    private func sectionTitle(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage).font(.subheadline.weight(.semibold)).padding(.bottom, 2)
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(spacing: 3) { Text(title).font(.caption2).foregroundStyle(.secondary); Text(value).font(.caption.weight(.medium)) }.frame(maxWidth: .infinity)
    }

    private func statusBanner(_ text: String, systemImage: String, tint: Color) -> some View {
        Label(text, systemImage: systemImage).font(.caption).foregroundStyle(tint).fixedSize(horizontal: false, vertical: true).padding(10).frame(maxWidth: .infinity, alignment: .leading).background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
    }

    private func emptyState(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 150)
    }

    private func date(_ value: Date, format: String, zone: String = "Asia/Shanghai") -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "zh_CN"); formatter.timeZone = TimeZone(identifier: zone); formatter.dateFormat = format; return formatter.string(from: value)
    }

    private func phase(_ value: String?) -> String {
        switch value { case "announced": return "已预告"; case "rolling_out": return "正在发放 / 生效"; case "completed": return "已完成"; default: return "状态未明确" }
    }
}
