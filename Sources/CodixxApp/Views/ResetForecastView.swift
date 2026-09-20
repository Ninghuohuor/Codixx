import SwiftUI
import CodixxCore

struct ResetForecastView: View {
    @ObservedObject var store: ResetForecastStore

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("重置预测").font(.headline)
                            Text("追踪 Codex 额外重置与重置卡消息").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { store.refresh(force: true) } label: {
                            Label(store.isRefreshing ? "更新中…" : "刷新", systemImage: "arrow.clockwise")
                        }.disabled(store.isRefreshing)
                    }
                    if let error = store.error {
                        Label(error, systemImage: "wifi.exclamationmark").font(.caption).foregroundStyle(.orange)
                    }
                    if let feed = store.feed {
                        forecast(feed, now: context.date)
                        latestReset(feed, now: context.date)
                        cardNews(feed, now: context.date)
                        HStack {
                            Circle().fill(feed.isFresh(at: context.date) && store.error == nil ? Color.green : Color.orange).frame(width: 6, height: 6)
                            Text(feed.isFresh(at: context.date) && store.error == nil ? "数据已更新" : "数据可能延迟 · 基于已保存记录")
                            if let updated = feed.lastSuccessAt { Text(date(updated, format: "M/d HH:mm")) }
                            Spacer()
                            Link("来源 codexreset", destination: URL(string: "https://codexreset.club/")!)
                        }.font(.caption2).foregroundStyle(.secondary)
                    } else if store.isRefreshing {
                        ProgressView("正在获取预测数据…").frame(maxWidth: .infinity, minHeight: 180)
                    } else {
                        Label("暂未获取到预测数据，请点击刷新。", systemImage: "calendar.badge.exclamationmark")
                            .foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 140)
                    }
                    reminders
                }.padding(14)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { store.refresh() }
    }

    private func forecast(_ feed: ResetFeed, now: Date) -> some View {
        let estimate = ResetEstimate.calculate(feed: feed, now: now)
        return panel {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Label("下次自动重置预估", systemImage: "calendar.badge.clock").font(.subheadline.weight(.medium))
                    Text(date(estimate.day, format: "M 月 d 日")).font(.system(size: 28, weight: .semibold, design: .rounded))
                    Text("北京时间 · 非官方预告").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    Text("\(Int((estimate.probability * 100).rounded()))%").font(.system(size: 28, weight: .semibold, design: .rounded)).foregroundStyle(Color.accentColor)
                    Text(estimate.basis == "empirical" ? "当日概率 · 历史估计" : "当日概率 · 模型估计").font(.caption).foregroundStyle(.secondary)
                }
            }
            Divider()
            HStack {
                Text("历史平均间隔")
                Spacer()
                Text(estimate.averageDays.map { String(format: "%.1f 天", $0) } ?? "暂无样本")
            }.font(.caption)
            Text(estimate.basis == "empirical" ? "根据 \(estimate.sampleCount) 个历史间隔推测。" : estimate.basis == "average" ? "按历史平均间隔建立等待模型。" : "样本不足，按默认 7 天间隔建立等待模型。")
                .font(.caption).foregroundStyle(.secondary)
            Text("预测的是额外重置公告，不是账号固定的周额度重置时间。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func latestReset(_ feed: ResetFeed, now: Date) -> some View {
        panel {
            Label("最近一次自动重置", systemImage: "arrow.counterclockwise").font(.subheadline.weight(.medium))
            if let event = feed.latest("automatic_reset", now: now) {
                HStack {
                    Text(date(event.announcedAt, format: "M 月 d 日 HH:mm"))
                    Spacer()
                    Text(phase(event.effects.first { $0.kind == "automatic_reset" }?.phase)).foregroundStyle(.secondary)
                }.font(.caption)
                Text(event.summaryZh ?? event.originalText ?? "暂无摘要").font(.caption).textSelection(.enabled)
                if let url = event.safeURL { Link("查看原始公告 ↗", destination: url).font(.caption) }
            } else { Text("暂无有效的自动重置公告").font(.caption).foregroundStyle(.secondary) }
        }
    }

    private func cardNews(_ feed: ResetFeed, now: Date) -> some View {
        panel {
            Label("重置卡消息", systemImage: "ticket").font(.subheadline.weight(.medium))
            if let outlook = ResetCardOutlook.calculate(feed: feed, now: now) {
                Text(outlook.explicitTime ? date(outlook.date, format: "M 月 d 日 HH:mm") : date(outlook.date, format: "M 月 d 日 EEEE", zone: "America/Los_Angeles"))
                    .font(.title3.weight(.semibold))
                Text(outlook.explicitTime ? "预告时间 · 北京时间" : "回复线索 · 未确认；按美国太平洋日期解读，原文未注明时区")
                    .font(.caption).foregroundStyle(.orange)
                Text(outlook.text).font(.caption).textSelection(.enabled)
                Link("查看来源 ↗", destination: outlook.sourceURL).font(.caption)
            } else if let event = feed.latest("banked_reset", now: now) {
                Text(event.summaryZh ?? event.originalText ?? "暂无摘要").font(.caption).textSelection(.enabled)
                Text("\(date(event.announcedAt, format: "M/d HH:mm")) · \(phase(event.effects.first { $0.kind == "banked_reset" }?.phase))")
                    .font(.caption).foregroundStyle(.secondary)
                if let audience = event.effects.first(where: { $0.kind == "banked_reset" })?.audienceText {
                    Text("适用范围：\(audience)").font(.caption).foregroundStyle(.secondary)
                }
                if let url = event.safeURL { Link("查看原始公告 ↗", destination: url).font(.caption) }
            } else { Text("暂无新的重置卡消息").font(.caption).foregroundStyle(.secondary) }
        }
    }

    private var reminders: some View {
        panel {
            Label("本地提醒", systemImage: "bell").font(.subheadline.weight(.medium))
            Toggle("自动重置公告", isOn: Binding(get: { store.preferences.automatic }, set: { store.setReminder(automatic: $0) }))
            Toggle("重置卡消息（含未确认线索）", isOn: Binding(get: { store.preferences.cards }, set: { store.setReminder(cards: $0) }))
            Text("Codixx 运行时每 5 分钟检查，通过 macOS 通知提醒新消息；首次开启不补发旧消息。")
                .font(.caption).foregroundStyle(.secondary)
            if let error = store.notificationError { Text(error).font(.caption).foregroundStyle(.orange) }
        }
    }
    private func panel<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10, content: content)
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }
    private func date(_ value: Date, format: String, zone: String = "Asia/Shanghai") -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = TimeZone(identifier: zone)
        formatter.dateFormat = format
        return formatter.string(from: value)
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
