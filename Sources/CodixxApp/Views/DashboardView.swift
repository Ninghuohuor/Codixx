import AppKit
import Combine
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

@MainActor
final class DashboardPresentationState: ObservableObject {
    @Published private(set) var language: CodixxLanguage
    @Published private(set) var pendingAutoSwitch: AutoSwitchProposal?
    private var cancellables: Set<AnyCancellable> = []

    init(state: AppState) {
        language = state.config.language
        pendingAutoSwitch = state.pendingAutoSwitch
        state.$config.map(\.language).removeDuplicates().dropFirst()
            .sink { [weak self] in self?.language = $0 }
            .store(in: &cancellables)
        state.$pendingAutoSwitch.removeDuplicates().dropFirst()
            .sink { [weak self] in self?.pendingAutoSwitch = $0 }
            .store(in: &cancellables)
    }

    var strings: CodixxStrings { CodixxStrings(language: language) }
}

struct DashboardView: View {
    let state: AppState
    @StateObject private var presentation: DashboardPresentationState
    @State private var selectedTab = 0

    init(state: AppState) {
        self.state = state
        _presentation = StateObject(wrappedValue: DashboardPresentationState(state: state))
    }

    var body: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                accounts
                    .tabItem { Label(presentation.strings.accounts, systemImage: "person.2") }
                    .tag(0)

                ResetForecastView(store: state.resetForecastStore)
                    .tabItem { Label("重置预测", systemImage: "calendar.badge.clock") }
                    .tag(1)

                settings
                    .tabItem { Label(presentation.strings.settings, systemImage: "gearshape") }
                    .tag(2)
            }
            .allowsHitTesting(presentation.pendingAutoSwitch == nil)

            if let proposal = presentation.pendingAutoSwitch {
                Color.black.opacity(0.16)
                    .ignoresSafeArea()
                autoSwitchConfirmation(proposal)
                    .padding(24)
            }
        }
        .frame(width: DashboardLayout.width)
        .frame(minHeight: 400, idealHeight: 520, maxHeight: 620)
        // Codixx 只做亮色，理由见 AppAppearancePolicy。
        .codixxAppearance()
    }

    private func autoSwitchConfirmation(_ proposal: AutoSwitchProposal) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(state.strings.autoSwitchConfirmTitle, systemImage: "arrow.triangle.2.circlepath")
                .font(.headline)
            Text(state.strings.autoSwitchConfirmMessage(
                current: proposal.sourceAlias,
                target: proposal.targetAlias
            ))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button(state.strings.disableAutoSwitch) { state.disablePendingAutoSwitch() }
                    .buttonStyle(.borderless)
                Spacer()
                Button(state.strings.snoozeAutoSwitch) { state.snoozePendingAutoSwitch() }
                Button(state.strings.confirmAutoSwitch) { state.confirmPendingAutoSwitch() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(maxWidth: 440)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.16), radius: 18, y: 8)
    }

    private var accounts: some View { AccountListView(state: state) }
    private var settings: some View { SettingsView(state: state) }
}
