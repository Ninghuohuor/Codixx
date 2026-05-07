import SwiftUI
import CodixxCore

struct SettingsView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(state.strings.settings)
                .font(.headline)

            Picker(state.strings.languageLabel, selection: Binding(
                get: { state.config.language },
                set: { state.setLanguage($0) }
            )) {
                ForEach(CodixxLanguage.allCases) { language in
                    Text(language.displayName).tag(language)
                }
            }
            .pickerStyle(.segmented)

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

            Toggle(state.strings.notifications, isOn: Binding(
                get: { state.config.notificationsEnabled },
                set: { state.setNotificationsEnabled($0) }
            ))

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
            }

            Stepper(
                "\(state.strings.quotaRefresh): \(state.strings.secondsInterval(Int(state.config.quotaRefreshIntervalSeconds)))",
                value: Binding(
                    get: { state.config.quotaRefreshIntervalSeconds },
                    set: { state.setQuotaRefreshIntervalSeconds($0) }
                ),
                in: 30...600,
                step: 30
            )

            Stepper(
                "\(state.strings.usageRefresh): \(state.strings.minutesInterval(Int(state.config.usageRefreshIntervalSeconds / 60)))",
                value: Binding(
                    get: { state.config.usageRefreshIntervalSeconds },
                    set: { state.setUsageRefreshIntervalSeconds($0) }
                ),
                in: 60...1_800,
                step: 60
            )

            Picker(state.strings.postSwitchAction, selection: Binding(
                get: { state.config.postSwitchAction },
                set: { state.setPostSwitchAction($0) }
            )) {
                ForEach(PostSwitchAction.allCases) { action in
                    Text(state.strings.postSwitchActionLabel(action)).tag(action)
                }
            }
            .pickerStyle(.menu)

            Button {
                state.restartCodexNow()
            } label: {
                Label(state.strings.restartCodexNow, systemImage: "arrow.clockwise")
            }

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

            Label(state.strings.restartCodexHint, systemImage: "arrow.clockwise.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
