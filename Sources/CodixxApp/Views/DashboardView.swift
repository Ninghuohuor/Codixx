import AppKit
import SwiftUI
import CodixxCore

struct DashboardView: View {
    @ObservedObject var state: AppState
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            accounts
                .tabItem { Label(state.strings.accounts, systemImage: "person.2") }
                .tag(0)

            trends
                .tabItem { Label(state.strings.trends, systemImage: "chart.xyaxis.line") }
                .tag(1)

            settings
                .tabItem { Label(state.strings.settings, systemImage: "gearshape") }
                .tag(2)
        }
        .frame(width: 360)
        .frame(minHeight: 400, idealHeight: 520, maxHeight: 620)
        .onChange(of: selectedTab) { tab in
            guard tab == 1 else { return }
            state.refreshTrendsIfNeeded()
        }
        .onAppear {
            state.refreshFromMenuOpen()
            if selectedTab == 1 {
                state.refreshTrendsIfNeeded()
            }
        }
    }

    private var trends: some View {
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
                    strings: state.strings,
                    isLoading: state.isLoadingFullUsageSnapshot
                )
                ThreadRankingView(threads: state.topThreads, strings: state.strings)
            }
            .padding(14)
        }
    }

    private var accounts: some View {
        AccountListView(state: state)
    }

    private var settings: some View {
        SettingsView(state: state)
    }
}
