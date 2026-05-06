import SwiftUI

struct SettingsView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Settings")
                .font(.headline)

            Toggle("Auto switch", isOn: Binding(
                get: { state.config.autoSwitchEnabled },
                set: { state.setAutoSwitchEnabled($0) }
            ))

            Toggle("Notifications", isOn: Binding(
                get: { state.config.notificationsEnabled },
                set: { state.setNotificationsEnabled($0) }
            ))

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Threshold")
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
                Text("Codex Home")
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
