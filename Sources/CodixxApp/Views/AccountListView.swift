import SwiftUI
import CodixxCore

struct AccountListView: View {
    @ObservedObject var state: AppState
    @State private var newAlias = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                saveCurrentAccount

                Text(state.strings.accounts)
                    .font(.headline)

                if state.accounts.isEmpty {
                    Text(state.strings.noSavedAccounts)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                } else {
                    ForEach(state.accounts) { account in
                        accountRow(account)
                    }
                }
            }
        }
    }

    private var saveCurrentAccount: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(state.strings.saveCurrentAuth)
                .font(.headline)
            HStack {
                TextField(state.strings.alias, text: $newAlias)
                    .textFieldStyle(.roundedBorder)
                Button {
                    state.saveCurrentAccount(alias: newAlias)
                    newAlias = ""
                } label: {
                    Label(state.strings.save, systemImage: "key")
                }
                .help(state.strings.saveCurrentCodexAuth)
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }

    private func accountRow(_ account: CodixxAccount) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(account.alias)
                            .font(.headline)
                        if account.id == state.currentAccount?.id {
                            Text(state.strings.current)
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.14), in: Capsule())
                        }
                    }
                    Text(quotaText(for: account))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    state.switchToAccount(account)
                } label: {
                    Label(state.strings.switchAccount, systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(account.id == state.currentAccount?.id)
                .help(state.strings.switchToThisAccount)
            }

            HStack {
                Toggle(state.strings.enabled, isOn: Binding(
                    get: { account.isEnabled },
                    set: { state.setAccount(account, isEnabled: $0) }
                ))
                Spacer()
                Stepper(state.strings.priority(account.priority), value: Binding(
                    get: { account.priority },
                    set: { state.setAccount(account, priority: $0) }
                ), in: 0...100)
                .frame(width: 138)
            }
            .font(.caption)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }

    private func quotaText(for account: CodixxAccount) -> String {
        let primary = account.quota.primaryUsedPercent.map { "\(Int($0.rounded()))%" } ?? "--"
        let confidence = state.strings.confidenceLabel(account.quota.confidence)
        return state.strings.primaryQuota(primary: primary, confidence: confidence)
    }
}
