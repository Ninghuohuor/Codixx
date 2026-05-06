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
        }
    }
}
