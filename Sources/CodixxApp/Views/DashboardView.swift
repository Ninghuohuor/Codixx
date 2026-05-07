import AppKit
import SwiftUI
import CodixxCore

struct DashboardView: View {
    @ObservedObject var state: AppState
    @State private var selectedTab = 0
    @State private var isShowingSettings = false

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $selectedTab) {
                overview
                    .tabItem { Label(state.strings.overview, systemImage: "gauge.with.dots.needle.67percent") }
                    .tag(0)

                trends
                    .tabItem { Label(state.strings.trends, systemImage: "chart.xyaxis.line") }
                    .tag(1)

                accounts
                    .tabItem { Label(state.strings.accounts, systemImage: "person.2") }
                    .tag(2)

                logs
                    .tabItem { Label(state.strings.logs, systemImage: "list.clipboard") }
                    .tag(3)
            }
            .frame(width: 360, height: 520)

            Divider()

            HStack(spacing: 10) {
                Text(footerText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Button {
                    state.refreshNow()
                } label: {
                    Label(state.strings.refresh, systemImage: state.isRefreshing ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                }
                .labelStyle(.iconOnly)
                .help(state.strings.refresh)

                Button {
                    isShowingSettings.toggle()
                } label: {
                    Label(state.strings.settings, systemImage: "gearshape")
                }
                .labelStyle(.iconOnly)
                .help(state.strings.settings)
                .popover(isPresented: $isShowingSettings) {
                    SettingsView(state: state)
                        .frame(width: 320)
                        .padding()
                }

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Label(state.strings.quitCodixx, systemImage: "power")
                }
                .labelStyle(.iconOnly)
                .help(state.strings.quitCodixx)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .onAppear {
            state.refreshFromMenuOpen()
        }
    }

    private var overview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                QuotaView(account: state.currentAccount, config: state.config, strings: state.strings)
                activeThreadCard

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
            }
            .padding(14)
        }
    }

    private var activeThreadCard: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: state.usageSnapshot.activeThread == nil ? "text.bubble" : "text.bubble.fill")
                .foregroundStyle(state.usageSnapshot.activeThread == nil ? Color.secondary : Color.green)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 3) {
                Text(state.strings.activeThread)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let thread = state.usageSnapshot.activeThread {
                    Text(activeThreadTitle(thread))
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(activeThreadDetail(thread))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text(state.strings.noActiveThread)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }

    private func activeThreadTitle(_ thread: ThreadUsage) -> String {
        if let projectName = projectFolderName(from: thread.cwd) {
            return "\(projectName) - \(thread.title)"
        }
        return thread.title
    }

    private func activeThreadDetail(_ thread: ThreadUsage) -> String {
        "\(thread.tokensUsed.formatted()) \(state.strings.tokens) / \(thread.model)"
    }

    private func projectFolderName(from cwd: String) -> String? {
        let trimmed = cwd.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let url = URL(fileURLWithPath: trimmed, isDirectory: true)
        let name = url.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? trimmed : name
    }

    private var trends: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                UsageTrendView(snapshot: state.usageSnapshot, strings: state.strings)
                ThreadRankingView(threads: state.topThreads, strings: state.strings)
            }
            .padding(14)
        }
    }

    private var accounts: some View {
        AccountListView(state: state)
            .padding(14)
    }

    private var logs: some View {
        ScrollView {
            SwitchLogView(events: Array(state.switchEvents.prefix(20)), strings: state.strings)
                .padding(14)
        }
    }

    private var footerText: String {
        guard let lastUpdatedAt = state.lastUpdatedAt else { return state.strings.notRefreshedYet }
        return state.strings.updated(lastUpdatedAt)
    }
}
