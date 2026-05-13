import AppKit
import SwiftUI
import CodixxCore

struct SettingsView: View {
    @ObservedObject var state: AppState
    @State private var isShowingAllLogs = false
    @State private var selectedLogCategory: AppLogCategory = .all
    @State private var parentWindow: NSWindow?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(state.strings.settings)
                    .font(.headline)

                settingsSection(title: state.strings.generalSection) {
                    Picker(state.strings.languageLabel, selection: Binding(
                        get: { state.config.language },
                        set: { state.setLanguage($0) }
                    )) {
                        ForEach(CodixxLanguage.allCases) { language in
                            Text(language.displayName).tag(language)
                        }
                    }
                    .pickerStyle(.segmented)

                    Divider()

                    Toggle(state.strings.notifications, isOn: Binding(
                        get: { state.config.notificationsEnabled },
                        set: { state.setNotificationsEnabled($0) }
                    ))
                }

                settingsSection(title: state.strings.autoSwitchSection) {
                    Toggle(state.strings.autoSwitch, isOn: Binding(
                        get: { state.config.autoSwitchEnabled },
                        set: { state.setAutoSwitchEnabled($0) }
                    ))
                    .disabled(!state.canEnableAutoSwitch)

                    if !state.canEnableAutoSwitch {
                        Label(state.strings.autoSwitchNeedsTwoAccounts, systemImage: "person.crop.circle.badge.plus")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(state.strings.threshold)
                            Spacer()
                            Text("\(Int(state.config.primaryThresholdPercent.rounded()))%")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        Slider(
                            value: Binding(
                                get: { state.config.primaryThresholdPercent },
                                set: { state.setPrimaryThresholdPercent($0) }
                            ),
                            in: 50...99,
                            step: 1
                        )
                        Text(state.strings.thresholdHint)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(state.strings.weeklyThreshold)
                            Spacer()
                            Text("\(Int(state.config.secondaryThresholdPercent.rounded()))%")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        Slider(
                            value: Binding(
                                get: { state.config.secondaryThresholdPercent },
                                set: { state.setSecondaryThresholdPercent($0) }
                            ),
                            in: 50...100,
                            step: 1
                        )
                        Text(state.strings.weeklyThresholdHint)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Divider()

                    Picker(state.strings.apiSwitchThreadSyncScope, selection: Binding(
                        get: { state.config.apiSwitchThreadSyncScope },
                        set: { state.setAPISwitchThreadSyncScope($0) }
                    )) {
                        ForEach(APISwitchThreadSyncScope.allCases) { scope in
                            Text(state.strings.apiSwitchThreadSyncScopeLabel(scope)).tag(scope)
                        }
                    }
                    .pickerStyle(.menu)

                    Text(state.strings.apiSwitchThreadSyncScopeHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                settingsSection(title: state.strings.refreshIntervalSection) {
                    Stepper(
                        "\(state.strings.quotaRefresh): \(state.strings.secondsInterval(Int(state.config.quotaRefreshIntervalSeconds)))",
                        value: Binding(
                            get: { state.config.quotaRefreshIntervalSeconds },
                            set: { state.setQuotaRefreshIntervalSeconds($0) }
                        ),
                        in: 30...600,
                        step: 30
                    )

                    Divider()

                    Stepper(
                        "\(state.strings.usageRefresh): \(state.strings.minutesInterval(Int(state.config.usageRefreshIntervalSeconds / 60)))",
                        value: Binding(
                            get: { state.config.usageRefreshIntervalSeconds },
                            set: { state.setUsageRefreshIntervalSeconds($0) }
                        ),
                        in: 60...1_800,
                        step: 60
                    )
                }

                settingsSection(title: "Codex") {
                    Button {
                        state.restartCodexNow()
                    } label: {
                        Label(state.strings.restartCodexNow, systemImage: "arrow.clockwise")
                    }

                    Label(state.strings.restartCodexHint, systemImage: "arrow.clockwise.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Divider()

                    VStack(alignment: .leading, spacing: 4) {
                        Text(state.strings.codexHome)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(state.paths.codexHome.path)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .lineLimit(2)
                    }

                    Divider()

                    Button(role: .destructive) {
                        confirmQuit()
                    } label: {
                        Label(state.strings.quitCodixx, systemImage: "power")
                    }
                    .help(state.strings.quitCodixx)
                }

                settingsSection(title: state.strings.logs) {
                    AppLogView(
                        entries: visibleLogEntries,
                        strings: state.strings,
                        selectedCategory: $selectedLogCategory,
                        showsTitle: false
                    )

                    if filteredLogEntries.count > 3 {
                        Divider()

                        Button {
                            withAnimation(.easeInOut(duration: 0.16)) {
                                isShowingAllLogs.toggle()
                            }
                        } label: {
                            Label(
                                isShowingAllLogs ? state.strings.showLess : state.strings.showMore,
                                systemImage: isShowingAllLogs ? "chevron.up" : "chevron.down"
                            )
                        }
                        .font(.caption)
                        .buttonStyle(.borderless)
                    }
                }
            }
            .padding(14)
        }
        .background(WindowReader { window in
            parentWindow = window
        })
    }

    private var allLogEntries: [AppLogEntry] {
        AppLogEntry.entries(
            switchEvents: state.switchEvents,
            appEvents: state.appLogEvents,
            strings: state.strings
        )
    }

    private var filteredLogEntries: [AppLogEntry] {
        AppLogEntry.filtered(allLogEntries, by: selectedLogCategory)
    }

    private var visibleLogEntries: [AppLogEntry] {
        let limit = isShowingAllLogs ? 20 : 3
        return Array(filteredLogEntries.prefix(limit))
    }

    private func confirmQuit() {
        let confirmed = IconlessConfirmationDialog.run(
            title: state.strings.quitCodixx,
            message: state.strings.quitCodixxMessage,
            confirmTitle: state.strings.quitCodixx,
            cancelTitle: state.strings.cancel,
            parent: parentWindow ?? NSApplication.shared.keyWindow
        )
        guard confirmed else { return }
        NSApplication.shared.terminate(nil)
    }

    private func settingsSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 10) {
                content()
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        }
    }

}
