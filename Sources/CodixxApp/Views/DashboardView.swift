import AppKit
import SwiftUI
import CodixxCore

enum DashboardLayout {
    static let width: CGFloat = 560
    static let popoverContentSize = NSSize(width: width, height: 520)
    static let accountColumnCount = 2
    static let accountColumnSpacing: CGFloat = 14
    static let accountCardMinHeight: CGFloat = 200
    static let accountCardAdditionalQuotaHeight: CGFloat = 44
    static let accountCardQuotaErrorHeight: CGFloat = 56
    static let accountCardFooterSpacerMinLength: CGFloat = 0
    static let draggingAccountOpacity: Double = 1
    static let draggingAccountScale: CGFloat = 1.026
    static let draggingAccountShadowRadius: CGFloat = 22
    static let dragReleaseSettlingDelay: TimeInterval = 0.12
    static let dragReleaseFadeDuration: TimeInterval = 0.16
    static let dropTargetStrokeWidth: CGFloat = 2
    static let accountDragMinimumDistance: CGFloat = 7

    static func accountCardHeight(quotaWindowCount: Int, showsQuotaError: Bool) -> CGFloat {
        accountCardMinHeight
            + CGFloat(max(0, quotaWindowCount - 1)) * accountCardAdditionalQuotaHeight
            + (showsQuotaError ? accountCardQuotaErrorHeight : 0)
    }
}

struct DashboardView: View {
    @ObservedObject var state: AppState
    @State private var selectedTab = 0
    @State private var isAutoSwitchPromptVisible = false
    @State private var trendRefreshTask: Task<Void, Never>?

    var body: some View {
        TabView(selection: $selectedTab) {
            accounts
                .tabItem { Label(state.strings.accounts, systemImage: "person.2") }
                .tag(0)

            ResetForecastView(store: state.resetForecastStore)
                .tabItem { Label("重置预测", systemImage: "calendar.badge.clock") }
                .tag(1)

            trends
                .tabItem { Label(state.strings.trends, systemImage: "chart.xyaxis.line") }
                .tag(2)

            settings
                .tabItem { Label(state.strings.settings, systemImage: "gearshape") }
                .tag(3)
        }
        .frame(width: DashboardLayout.width)
        .frame(minHeight: 400, idealHeight: 520, maxHeight: 620)
        .onChange(of: selectedTab) { tab in
            guard tab == 2 else {
                trendRefreshTask?.cancel()
                trendRefreshTask = nil
                return
            }
            scheduleTrendRefresh()
        }
        .onAppear {
            isAutoSwitchPromptVisible = state.pendingAutoSwitch != nil
            if selectedTab == 2 {
                scheduleTrendRefresh()
            }
        }
        .onChange(of: state.pendingAutoSwitch) { proposal in
            isAutoSwitchPromptVisible = proposal != nil
        }
        .onChange(of: isAutoSwitchPromptVisible) { visible in
            if !visible, state.pendingAutoSwitch != nil {
                state.snoozePendingAutoSwitch()
            }
        }
        .alert(
            state.strings.autoSwitchConfirmTitle,
            isPresented: $isAutoSwitchPromptVisible
        ) {
            Button(state.strings.confirmAutoSwitch) { state.confirmPendingAutoSwitch() }
            Button(state.strings.snoozeAutoSwitch, role: .cancel) { state.snoozePendingAutoSwitch() }
            Button(state.strings.disableAutoSwitch, role: .destructive) { state.disablePendingAutoSwitch() }
        } message: {
            if let proposal = state.pendingAutoSwitch {
                Text(state.strings.autoSwitchConfirmMessage(
                    current: proposal.sourceAlias,
                    target: proposal.targetAlias
                ))
            }
        }
        // Codixx 只做亮色，理由见 AppAppearancePolicy。
        .codixxAppearance()
    }

    private func scheduleTrendRefresh() {
        trendRefreshTask?.cancel()
        trendRefreshTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled, selectedTab == 2 else { return }
            state.refreshTrendsIfNeeded()
        }
    }

    private var trends: some View {
        Group {
            if state.isLoadingFullUsageSnapshot || !state.hasLoadedFullUsageSnapshot {
                TrendLoadingView(strings: state.strings)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let error = state.errorMessage {
                            Label(error, systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .lineLimit(4)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
                                .transition(.opacity)
                        }
                        UsageTrendView(
                            snapshot: state.usageSnapshot,
                            accounts: state.accounts,
                            strings: state.strings
                        )
                        ThreadRankingView(threads: state.topThreads, strings: state.strings)
                    }
                    .padding(14)
                }
                .transition(.opacity)
            }
        }
    }

    private var accounts: some View {
        AccountListView(state: state)
    }

    private var settings: some View {
        SettingsView(state: state)
    }
}

private struct TrendLoadingView: View {
    var strings: CodixxStrings

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            Text(strings.loadingTrendData)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 360, maxHeight: .infinity)
    }
}
