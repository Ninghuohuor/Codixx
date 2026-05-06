import SwiftUI
import CodixxCore

struct AccountListView: View {
    @ObservedObject var state: AppState
    @State private var newAlias = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                saveCurrentAccount

                Text("Accounts")
                    .font(.headline)

                if state.accounts.isEmpty {
                    Text("No saved accounts")
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
            Text("Save Current Auth")
                .font(.headline)
            HStack {
                TextField("Alias", text: $newAlias)
                    .textFieldStyle(.roundedBorder)
                Button {
                    state.saveCurrentAccount(alias: newAlias)
                    newAlias = ""
                } label: {
                    Label("Save", systemImage: "key")
                }
                .help("Save current Codex auth")
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
                            Text("Current")
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
                    Label("Switch", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(account.id == state.currentAccount?.id)
                .help("Switch to this account")
            }

            HStack {
                Toggle("Enabled", isOn: Binding(
                    get: { account.isEnabled },
                    set: { state.setAccount(account, isEnabled: $0) }
                ))
                Spacer()
                Stepper("Priority \(account.priority)", value: Binding(
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
        let confidence = account.quota.confidence.rawValue
        return "Primary \(primary) / \(confidence)"
    }
}
